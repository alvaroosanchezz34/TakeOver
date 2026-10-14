--!nonstrict
--[[
	Raíz de composición del cliente.

	Responsabilidades: crear las capas de interfaz, aplicar la escala según el dispositivo,
	conectar los mensajes del servidor con el estado y los controladores, y dar a todos los
	controladores un `ctx` común (textos localizados, formato de cantidades, llamadas al servidor
	con estado de carga/error, sonidos...).

	El cliente solo PRESENTA y SOLICITA: nunca calcula precios, dinero ni propiedad.
]]

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Company = require(Shared.Economy.Company)
local Cosmetics = require(Shared.Config.Cosmetics)
local Format = require(Shared.Util.Format)
local Locale = require(Shared.Locale)
local Monetization = require(Shared.Config.Monetization)
local Ownership = require(Shared.Economy.Ownership)
local Remotes = require(Shared.Remotes)

local Controllers = script.Parent:WaitForChild("Controllers")
local UI = script.Parent:WaitForChild("UI")
local CompanyPanel = require(Controllers.CompanyPanel)
local Effects = require(Controllers.Effects)
local EventBanner = require(Controllers.EventBanner)
local HUD = require(Controllers.HUD)
local MarketPanel = require(Controllers.MarketPanel)
local MenuPanel = require(Controllers.MenuPanel)
local Notifications = require(Controllers.Notifications)
local RankingPanel = require(Controllers.RankingPanel)
local Tutorial = require(Controllers.Tutorial)
local Kit = require(UI.Kit)
local Responsive = require(UI.Responsive)
local Theme = require(UI.Theme)
local Windows = require(UI.Windows)
local Net = require(script.Parent:WaitForChild("Net"))
local Store = require(script.Parent:WaitForChild("State"):WaitForChild("Store"))

local App = {}

local LAYERS = {
	{ name = "hud", display = 1 },
	{ name = "windows", display = 5 },
	{ name = "modals", display = 10 },
	{ name = "toasts", display = 20 },
	{ name = "fx", display = 30 },
}

-- Parámetros de los errores que son cantidades de dinero / porcentajes (para formatearlos).
local CASH_PARAMS = {
	INSUFFICIENT_FUNDS = { "missing", "need", "have" },
	SECTOR_LOCKED = { "need", "have" },
	PRICE_OUT_OF_RANGE = { "min", "max" },
}

function App.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local invoke, push = Remotes.waitClient()

	local store = Store.new(os.clock)
	local net = Net.new(invoke, push)

	-- ───────── Capas ─────────
	local layers, scales = {}, {}
	for _, def in LAYERS do
		local gui = Instance.new("ScreenGui")
		gui.Name = "Takeover_" .. def.name
		gui.ResetOnSpawn = false
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.DisplayOrder = def.display
		gui.IgnoreGuiInset = def.name == "fx"
		gui.Parent = playerGui
		local scale = Instance.new("UIScale")
		scale.Parent = gui
		layers[def.name] = gui
		table.insert(scales, scale)
	end

	local compact = false
	local function applyScale()
		for _, s in scales do
			compact = Responsive.apply(s)
		end
	end
	applyScale()

	-- ───────── ctx ─────────
	local ctx: any = {
		store = store,
		net = net,
		kit = Kit,
		theme = Theme,
		layers = layers,
		player = player,
		Balance = Balance,
		Company = Company,
		Cosmetics = Cosmetics,
		MonetizationConfig = Monetization,
		Ownership = Ownership,
		clock = os.clock,
	}

	local function lang()
		local state = store.state
		local setting = state and state.settings and state.settings.lang or "auto"
		if setting == "es" or setting == "en" then
			return setting
		end
		return Format.localeFromRoblox(LocalizationService.RobloxLocaleId)
	end
	ctx.lang = lang
	ctx.T = function(key, params)
		return Locale.t(lang(), key, params)
	end
	ctx.cash = function(n)
		return Format.cash(n, lang())
	end
	ctx.rate = function(n)
		return Format.rate(n, lang())
	end
	ctx.bps = function(n)
		return Format.bps(n, lang())
	end
	ctx.num = function(n)
		return Format.decimal(n, lang())
	end
	ctx.duration = Format.duration
	ctx.compact = function()
		return compact
	end

	-- Valor numérico de un efecto de mejora, ya listo para insertar en el texto.
	ctx.effectValue = function(kind, value)
		if kind == "discount" then
			return Format.decimal(value * 100, lang())
		elseif kind == "look" then
			return Format.decimal((value - 1) * 100, lang())
		end
		return Format.decimal(value, lang())
	end
	ctx.logoGlyph = function(logo)
		return Cosmetics.LogoIcons[logo and logo.icon or 1] or "⭐"
	end

	ctx.errText = function(code, params)
		local formatted = table.clone(params or {})
		for _, name in CASH_PARAMS[code] or {} do
			if formatted[name] ~= nil then
				formatted[name] = ctx.cash(formatted[name])
			end
		end
		if code == "MANAGER_STAKE_TOO_LOW" then
			formatted.pct = ctx.bps(formatted.minBps or 2000)
		elseif code == "PLAYER_CAP" and formatted.max then
			formatted.max = ctx.bps(formatted.max)
		end
		return Locale.err(lang(), code, formatted)
	end

	-- ───────── Controladores ─────────
	ctx.windows = Windows.new(layers.windows, ctx.compact)
	local controllers = {}

	ctx.effects = Effects.new(ctx)
	ctx.sfx = function(name)
		ctx.effects:sound(name)
	end
	Kit.onClickSound = function()
		ctx.sfx("click")
	end
	ctx.popup = function(text, color)
		ctx.effects:popup(text, color)
	end

	controllers.notifications = Notifications.new(ctx)
	ctx.toast = function(text, style)
		controllers.notifications:show(text, style)
	end

	-- Ejecuta una acción en el servidor con estado de carga y error comprensible.
	ctx.run = function(action, payload, opts)
		opts = opts or {}
		if opts.button then
			Kit.setBusy(opts.button, true)
		end
		local response = net:invoke(action, payload)
		if opts.button and opts.button.Parent then
			Kit.setBusy(opts.button, false)
		end
		if not response.ok and not opts.silent then
			ctx.sfx("error")
			ctx.toast(ctx.errText(response.code, response.params), "bad")
		end
		return response
	end

	ctx.openWindow = function(id, args)
		ctx.windows:open(id, args)
	end

	local function buildHud()
		for _, c in { "hud", "tutorial", "events" } do
			if controllers[c] and controllers[c].destroy then
				controllers[c]:destroy()
			end
		end
		local hudGui = layers.hud
		for _, child in hudGui:GetChildren() do
			if not child:IsA("UIScale") then
				child:Destroy()
			end
		end
		controllers.hud = HUD.new(ctx)
		controllers.tutorial = Tutorial.new(ctx, controllers.hud)
		controllers.events = EventBanner.new(ctx)
		ctx.pulse = function(button, on)
			if button ~= nil then
				controllers.hud:setPulse(button, on)
			end
		end
	end
	buildHud()

	CompanyPanel.register(ctx)
	MarketPanel.register(ctx)
	RankingPanel.register(ctx)
	MenuPanel.register(ctx)

	local function relayout()
		applyScale()
		for _, name in { "hud", "tutorial", "events" } do
			local c = controllers[name]
			if c and c.relayout then
				c:relayout()
			end
		end
	end
	relayout()

	local lastLang = lang()
	local function renderAll()
		local currentLang = lang()
		if currentLang ~= lastLang then
			lastLang = currentLang
			ctx.windows:close()
			buildHud()
			relayout()
		end
		controllers.hud:render()
		controllers.tutorial:render()
		controllers.events:render()
		ctx.windows:refresh()
	end

	-- ───────── Mensajes del servidor ─────────
	local function onState(message)
		local before = store:displayCash()
		local hadState = store.state ~= nil
		store:set("state", message)
		store:set("event", { event = message.event })
		if hadState then
			local delta = message.cash - before
			local threshold = math.max(10, (message.incomePerSecond or 0) * 8)
			if delta >= threshold then
				ctx.popup("+" .. ctx.cash(delta), Theme.colors.green)
			elseif -delta >= 5 and -delta > (message.incomePerSecond or 0) * 3 then
				ctx.popup("−" .. ctx.cash(-delta), Theme.colors.warn)
			end
		end
		renderAll()
	end

	net:onPush(function(message)
		local kind = message.type
		if kind == "state" then
			onState(message)
		elseif kind == "notify" then
			controllers.notifications:handle(message.kind, message.params)
		elseif kind == "offers" then
			store:set("offers", message)
			controllers.hud:render()
			ctx.windows:refresh("market")
		elseif kind == "leaderboard" then
			store:set("leaderboard", message)
			ctx.windows:refresh("ranking")
		elseif kind == "event" then
			store:set("event", message)
		elseif kind == "effect" then
			ctx.effects:handlePublic(message)
		end
	end)

	-- Atajos de teclado en PC (no se usan con el chat abierto).
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		local shortcuts = {
			[Enum.KeyCode.C] = "company",
			[Enum.KeyCode.M] = "market",
			[Enum.KeyCode.R] = "ranking",
			[Enum.KeyCode.Tab] = "menu",
		}
		local id = shortcuts[input.KeyCode]
		if id and store:ready() then
			if ctx.windows:isOpen(id) then
				ctx.windows:close()
			else
				ctx.openWindow(id)
			end
		end
	end)

	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
	end

	-- Primera carga: el servidor puede no tener aún los datos del jugador; se reintenta unos segundos.
	task.spawn(function()
		for _ = 1, 40 do
			local r = net:invoke("GetState", nil)
			if r.ok then
				onState(r.data)
				ctx.fetchMarket(true) -- también trae las ofertas pendientes
				local market = store.market
				if market and market.offers then
					store:set("offers", market.offers)
					controllers.hud:render()
				end
				local board = net:invoke("GetLeaderboard", nil)
				if board.ok then
					store:set("leaderboard", board.data)
				end
				return
			end
			if
				r.code ~= "NOT_READY"
				and r.code ~= "TIMEOUT"
				and r.code ~= "NETWORK"
				and r.code ~= "RATE_LIMITED"
			then
				break
			end
			task.wait(1)
		end
	end)

	App.ctx = ctx
	App.controllers = controllers
	App.store = store
	return ctx
end

return App
