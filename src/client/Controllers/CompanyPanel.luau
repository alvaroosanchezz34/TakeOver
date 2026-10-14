--!nonstrict
--[[
	Pantalla de empresa. Dos usos:
	  - TU empresa (o una que gestionas): resumen, mejoras con precio/efecto/beneficio esperado,
	    estilo (nombre y logotipo con opciones predefinidas) e historial.
	  - Una empresa AJENA o de la Bolsa: ficha pública, propiedad, reglas de control y botones para
	    hacer una oferta (o comprar/vender a la Bolsa).
	El servidor decide qué ve cada cual (libros sólo con ≥ 25 %); aquí sólo se muestra.
]]

local RunService = game:GetService("RunService")

local Trading = require(script.Parent.Trading)
local Widgets = require(script.Parent.Parent.UI.Widgets)

local CompanyPanel = {}

function CompanyPanel.register(ctx)
	local K = ctx.kit
	local C = ctx.theme.colors
	local S = ctx.theme.sizes
	local T = ctx.T

	local view = {
		companyId = nil,
		tab = "upgrades",
		detail = nil,
		loading = false,
		mode = "company", -- "company" | "found"
		fetchedAt = 0,
	}
	local scroll
	local upgradeButtons = {}
	local render

	local function fetch(companyId)
		view.companyId = companyId
		view.loading = true
		render()
		local r = ctx.run("InspectCompany", { companyId = companyId }, {})
		view.loading = false
		if r.ok then
			view.detail = r.data
			view.fetchedAt = ctx.clock()
		else
			view.detail = nil
		end
		if scroll and scroll.Parent then
			render()
		end
	end

	-- ───────── Piezas ─────────

	local function renderSelector()
		local managed = ctx.store:managed()
		local bar = K.frame(scroll, { name = "Selector", size = UDim2.new(1, 0, 0, 44), layoutOrder = 1 })
		K.layout(bar, { horizontal = true, gap = 6 })
		for _, c in managed do
			local selected = view.mode == "company" and view.companyId == c.id
			local b = K.button(bar, ctx.logoGlyph(c.logo) .. " " .. c.name, function()
				view.mode = "company"
				task.spawn(fetch, c.id)
			end, {
				name = "Select_" .. c.id,
				style = selected and "primary" or "ghost",
				size = UDim2.new(0, 190, 0, 44),
				textSize = S.textSmall + 1,
			})
			b.TextTruncate = Enum.TextTruncate.AtEnd
		end
		K.button(bar, "＋ " .. T("company.found"), function()
			view.mode = "found"
			render()
		end, {
			name = "FoundNew",
			style = view.mode == "found" and "primary" or "ghost",
			size = UDim2.new(0, 170, 0, 44),
			textSize = S.textSmall + 1,
		})
		-- barra desplazable horizontal en pantallas estrechas
		bar.Size = UDim2.new(1, 0, 0, 44)
	end

	local function renderHeader(detail)
		local card = K.card(scroll, { name = "CompanyHeader", color = C.surface, layoutOrder = 2 })
		K.layout(card, { gap = 6 })
		local top = K.frame(card, { name = "Top", size = UDim2.new(1, 0, 0, 44) })
		K.label(
			top,
			ctx.logoGlyph(detail.logo),
			{ size = 34, height = 44, align = "center", size2 = UDim2.fromOffset(52, 44), name = "Logo" }
		)
		K.label(top, detail.name, {
			bold = true,
			size = S.title - 2,
			height = 44,
			size2 = UDim2.new(1, -60, 0, 44),
			position = UDim2.fromOffset(58, 0),
			name = "Name",
		})
		local chips = K.frame(card, { name = "Chips", size = UDim2.new(1, 0, 0, 26) })
		K.layout(chips, { horizontal = true, gap = 6 })
		K.chip(
			chips,
			(ctx.theme.sectorIcons[detail.sector] or "") .. " " .. T("sector." .. detail.sector),
			C.surface3
		)
		if not detail.isNpc then
			K.chip(chips, T("common.level", { n = detail.level }), C.surface3)
		end
		if detail.rights then
			K.chip(
				chips,
				T("tier." .. detail.rights.tier),
				detail.rights.manages and C.accentDark or C.surface3
			)
		end
		K.label(card, T("sector." .. detail.sector .. ".desc"), { size = S.textSmall, color = C.textDim })
		K.label(
			card,
			"★ " .. T("sector." .. detail.sector .. ".mech"),
			{ size = S.textSmall, color = C.gold }
		)

		local stats = K.frame(scroll, { name = "Stats", size = UDim2.new(1, 0, 0, 66), layoutOrder = 3 })
		K.layout(stats, { horizontal = true, gap = 6 })
		Widgets.stat(ctx, stats, T("company.valuation"), ctx.cash(detail.valuation), C.gold, 1)
		Widgets.stat(ctx, stats, T("company.income"), "+" .. ctx.rate(detail.income), C.green, 2)
		if detail.hype and detail.sector == "tech" then
			local arrow = detail.hype > 1.005 and "▲" or (detail.hype < 0.995 and "▼" or "•")
			Widgets.stat(
				ctx,
				stats,
				T("company.hype"),
				arrow .. " ×" .. ctx.num(detail.hype),
				detail.hype >= 1 and C.green or C.warn,
				3
			)
		else
			Widgets.stat(ctx, stats, T("common.level", { n = "" }), tostring(detail.level), C.text, 3)
		end
	end

	local function renderUpgrades(detail)
		upgradeButtons = {}
		for i, o in detail.options or {} do
			local card = K.card(scroll, {
				name = "Upgrade_" .. o.id,
				color = C.surface,
				layoutOrder = 10 + (o.kind == "level" and 0 or i),
			})
			local row = K.frame(card, { name = "Row", size = UDim2.new(1, 0, 0, 78) })
			K.label(
				row,
				o.icon,
				{ size = 28, align = "center", height = 78, size2 = UDim2.fromOffset(44, 78), name = "Icon" }
			)
			K.label(row, T(o.nameKey), {
				bold = true,
				size = S.text,
				height = 20,
				size2 = UDim2.new(1, -190, 0, 20),
				position = UDim2.fromOffset(50, 0),
				name = "Name",
			})
			local effect
			if o.kind == "level" then
				effect = T("effect.level")
			else
				effect = T("effect." .. o.effectKind, { v = ctx.effectValue(o.effectKind, o.effectValue) })
			end
			K.label(row, effect, {
				size = S.textSmall,
				color = C.textDim,
				height = 30,
				size2 = UDim2.new(1, -190, 0, 30),
				position = UDim2.fromOffset(50, 20),
				name = "Effect",
			})
			local meta = T("upgrade.owned", { n = o.currentLevel, max = o.maxLevel })
			if o.deltaIncome > 0 then
				meta = meta .. "  ·  " .. T("upgrade.gain", { v = ctx.num(o.deltaIncome) })
			end
			if o.paybackSeconds then
				meta = meta .. "  ·  " .. T("hud.next.payback", { time = ctx.duration(o.paybackSeconds) })
			end
			K.label(row, meta, {
				size = S.textSmall,
				color = C.green,
				height = 18,
				size2 = UDim2.new(1, -190, 0, 18),
				position = UDim2.fromOffset(50, 56),
				name = "Meta",
			})
			local missingLabel = K.label(row, "", {
				size = S.textSmall,
				color = C.warn,
				align = "right",
				height = 16,
				size2 = UDim2.new(0, 130, 0, 16),
				position = UDim2.new(1, -130, 0, 56),
				name = "Missing",
			})
			local buy
			buy = K.button(row, o.maxed and T("common.max") or ctx.cash(o.cost), function()
				local action = o.kind == "level" and "LevelUp" or "BuyUpgrade"
				local payload = o.kind == "level" and { companyId = detail.id }
					or { companyId = detail.id, upgradeId = o.id }
				local r = ctx.run(action, payload, { button = buy })
				if r.ok then
					ctx.sfx("buy")
					task.spawn(fetch, detail.id)
				end
			end, {
				name = "Buy_" .. o.id,
				style = "success",
				size = UDim2.new(0, 130, 0, 40),
				anchor = Vector2.new(1, 0),
				position = UDim2.new(1, 0, 0, 8),
				textSize = S.text,
			})
			table.insert(
				upgradeButtons,
				{ button = buy, cost = o.cost, maxed = o.maxed, label = missingLabel }
			)
		end
		ctx.refreshUpgradeStates()
	end

	-- Actualiza qué botones de compra están disponibles y cuánto falta (Cash extrapolado).
	function ctx.refreshUpgradeStates()
		local cash = ctx.store:displayCash()
		for _, u in upgradeButtons do
			if u.button.Parent then
				if u.maxed then
					K.setEnabled(u.button, false)
					u.label.Text = ""
				elseif cash >= u.cost then
					K.setEnabled(u.button, true)
					u.label.Text = ""
				else
					K.setEnabled(u.button, false)
					u.label.Text = T("hud.next.missing", { amount = ctx.cash(u.cost - cash) })
				end
			end
		end
	end

	local function renderStyle(detail)
		local company = ctx.Company
		local Cosmetics = ctx.Cosmetics
		local parts = table.clone(detail.nameParts or { 1, 1, 1 })
		local logo = { icon = detail.logo.icon, color = detail.logo.color }
		K.label(scroll, T("company.style.hint"), { size = S.textSmall, color = C.textDim, layoutOrder = 10 })

		local nameCard = K.card(scroll, { name = "NameCard", color = C.surface, layoutOrder = 11 })
		K.layout(nameCard, { gap = 6 })
		local preview = K.label(
			nameCard,
			"",
			{ bold = true, size = S.textBig, color = C.gold, align = "center", name = "NamePreview" }
		)
		local function refreshPreview()
			preview.Text = company.nameFromParts(detail.sector, parts) or "?"
		end
		local cores = Cosmetics.NameCores[detail.sector]
		local lists = { Cosmetics.NamePrefixes, cores, Cosmetics.NameSuffixes }
		for i = 1, 3 do
			K.stepper(nameCard, {
				value = parts[i],
				min = 1,
				max = #lists[i],
				step = 1,
				format = function(v)
					return lists[i][v]
				end,
				onChange = function(v)
					parts[i] = v
					refreshPreview()
				end,
			})
		end
		refreshPreview()
		local saveName
		saveName = K.button(nameCard, T("company.rename"), function()
			local r = ctx.run("Rename", { companyId = detail.id, parts = parts }, { button = saveName })
			if r.ok then
				ctx.sfx("buy")
				task.spawn(fetch, detail.id)
			end
		end, { name = "SaveName", style = "primary" })

		local logoCard = K.card(scroll, { name = "LogoCard", color = C.surface, layoutOrder = 12 })
		K.layout(logoCard, { gap = 6 })
		K.label(logoCard, T("company.logo"), { bold = true, size = S.text })
		local grid = K.frame(logoCard, { name = "IconGrid", size = UDim2.new(1, 0, 0, 0), autoY = true })
		local gridLayout = Instance.new("UIGridLayout")
		gridLayout.CellSize = UDim2.fromOffset(52, 52)
		gridLayout.CellPadding = UDim2.fromOffset(6, 6)
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.Parent = grid
		local iconButtons = {}
		local function paintIcons()
			for i, b in iconButtons do
				b.BackgroundColor3 = i == logo.icon and C.accentDark or C.surface3
			end
		end
		for i, glyph in Cosmetics.LogoIcons do
			local b = K.button(grid, glyph, function()
				logo.icon = i
				paintIcons()
			end, { name = "Icon_" .. i, size = UDim2.fromOffset(52, 52), textSize = 26, layoutOrder = i })
			iconButtons[i] = b
		end
		paintIcons()
		local swatches = K.frame(logoCard, { name = "Swatches", size = UDim2.new(1, 0, 0, 0), autoY = true })
		local swGrid = Instance.new("UIGridLayout")
		swGrid.CellSize = UDim2.fromOffset(52, 40)
		swGrid.CellPadding = UDim2.fromOffset(6, 6)
		swGrid.SortOrder = Enum.SortOrder.LayoutOrder
		swGrid.Parent = swatches
		local swButtons = {}
		local function paintSwatches()
			for i, b in swButtons do
				local rgb = Cosmetics.LogoColors[i]
				b.BackgroundColor3 = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
				b.Text = i == logo.color and "✓" or ""
			end
		end
		for i in Cosmetics.LogoColors do
			swButtons[i] = K.button(swatches, "", function()
				logo.color = i
				paintSwatches()
			end, { name = "Color_" .. i, size = UDim2.fromOffset(52, 40), layoutOrder = i })
			swButtons[i].TextColor3 = C.bg
		end
		paintSwatches()
		local saveLogo
		saveLogo = K.button(logoCard, T("company.logo"), function()
			local r = ctx.run(
				"SetLogo",
				{ companyId = detail.id, icon = logo.icon, color = logo.color },
				{ button = saveLogo }
			)
			if r.ok then
				ctx.sfx("buy")
				task.spawn(fetch, detail.id)
			end
		end, { name = "SaveLogo", style = "primary" })
	end

	local function renderHistory(detail)
		local card = K.card(scroll, { name = "History", color = C.surface, layoutOrder = 10 })
		K.layout(card, { gap = 6 })
		if #detail.history == 0 then
			K.label(card, T("common.empty"), { size = S.text, color = C.textDim })
			return
		end
		for _, e in detail.history do
			local text
			if e.kind == "trade" then
				text = T("company.history.trade", {
					buyer = e.a or "?",
					seller = e.b or "?",
					pct = ctx.bps(e.bps or 0),
					price = ctx.cash(e.amount or 0),
				})
			elseif e.kind == "founded" then
				text = T("company.history.founded")
			elseif e.kind == "upgrade" then
				text = T("company.history.upgrade", { note = tostring(e.note or "") })
			elseif e.kind == "level" then
				text = T("company.history.level", { note = tostring(e.note or "") })
			elseif e.kind == "rename" then
				text = T("company.history.rename", { note = tostring(e.note or "") })
			else
				text = T("company.history.style")
			end
			K.label(card, "• " .. text, { size = S.textSmall, color = C.text })
		end
	end

	local function renderOwnership(detail)
		local card = K.card(scroll, { name = "Ownership", color = C.surface, layoutOrder = 30 })
		K.layout(card, { gap = 6 })
		K.label(card, T("company.ownership"), { bold = true, size = S.text })
		K.label(
			card,
			T("company.owner")
				.. ": "
				.. tostring(detail.founderName)
				.. "   ·   "
				.. T("company.manager")
				.. ": "
				.. (detail.managerId == "MARKET" and T("common.market") or tostring(detail.managerName)),
			{
				size = S.textSmall,
				color = C.textDim,
			}
		)
		local me = ctx.store.state and ctx.store.state.userId
		Widgets.ownershipList(ctx, card, detail.holders, me, (not detail.isNpc) and function(holder)
			Trading.openOffer(ctx, detail, holder)
		end or nil)
		if detail.myBps and detail.myBps > 0 then
			K.label(
				card,
				T("company.stake", { pct = ctx.bps(detail.myBps) }),
				{ size = S.text, bold = true, color = C.accent }
			)
		end
		local gov = Widgets.governanceCard(ctx, scroll, detail.governance)
		gov.LayoutOrder = 31
	end

	local function renderExchange(detail)
		-- Empresa de la Bolsa: comprar y vender con precio visible.
		local card = K.card(
			scroll,
			{ name = "ExchangeCard", color = C.surface2, layoutOrder = 9, strokeColor = C.gold }
		)
		K.layout(card, { gap = 8 })
		K.label(card, T("market.exchange"), { bold = true, size = S.text })
		K.label(card, T("market.exchange.hint"), { size = S.textSmall, color = C.textDim })
		local row = K.frame(card, { name = "Buttons", size = UDim2.new(1, 0, 0, S.touch) })
		K.layout(row, { horizontal = true, gap = 8 })
		local function open(mode)
			local market = ctx.fetchMarket()
			if market == nil then
				return
			end
			for _, c in market.companies do
				if c.id == detail.id then
					Trading.openExchange(ctx, c, mode)
					return
				end
			end
		end
		local buyButton = K.button(row, T("market.buy_exchange"), function()
			open("buy")
		end, {
			name = "ExchangeBuy",
			style = "success",
			size = UDim2.new(0.5, -4, 1, 0),
			textSize = S.textSmall + 1,
		})
		local tut = ctx.store.state and ctx.store.state.tutorial
		if tut and not tut.done and not tut.skipped and tut.stepId == "first_offer" then
			ctx.pulse(buyButton, true)
		end
		K.button(row, T("market.sell_exchange"), function()
			open("sell")
		end, {
			name = "ExchangeSell",
			style = "secondary",
			size = UDim2.new(0.5, -4, 1, 0),
			textSize = S.textSmall + 1,
		})
	end

	local function renderFound()
		local state = ctx.store.state
		local founding = state and state.founding
		K.label(
			scroll,
			T(
				"company.found.slots",
				{ n = founding and founding.owned or 0, max = founding and founding.max or 3 }
			),
			{
				bold = true,
				size = S.text,
				layoutOrder = 10,
			}
		)
		for i, sector in (founding and founding.sectors or {}) do
			local card =
				K.card(scroll, { name = "Sector_" .. sector.id, color = C.surface, layoutOrder = 10 + i })
			K.layout(card, { gap = 6 })
			K.label(
				card,
				(ctx.theme.sectorIcons[sector.id] or "") .. "  " .. T("sector." .. sector.id),
				{ bold = true, size = S.textBig }
			)
			K.label(card, T("sector." .. sector.id .. ".desc"), { size = S.textSmall, color = C.textDim })
			K.label(
				card,
				"★ " .. T("sector." .. sector.id .. ".mech"),
				{ size = S.textSmall, color = C.gold }
			)
			K.label(
				card,
				T("company.found.cost", { cost = ctx.cash(sector.cost) }),
				{ size = S.text, bold = true, color = C.gold }
			)
			local slotsFull = founding.owned >= founding.max
			local enough = ctx.store:displayCash() >= sector.cost
			if not sector.unlocked then
				K.label(
					card,
					T(
						"company.found.locked",
						{ need = ctx.cash(sector.needEarned), have = ctx.cash(state.stats.totalEarned) }
					),
					{ size = S.textSmall, color = C.warn }
				)
			elseif slotsFull then
				K.label(
					card,
					T("err.SLOTS_FULL", { max = founding.max }),
					{ size = S.textSmall, color = C.warn }
				)
			elseif not enough then
				K.label(
					card,
					T("err.INSUFFICIENT_FUNDS", { missing = ctx.cash(sector.cost - ctx.store:displayCash()) }),
					{ size = S.textSmall, color = C.warn }
				)
			end
			local found
			found = K.button(card, T("company.found"), function()
				local r = ctx.run("FoundCompany", { sector = sector.id }, { button = found })
				if r.ok then
					ctx.sfx("deal")
					ctx.effects:confetti(18)
					view.mode = "company"
					task.spawn(fetch, r.data.companyId)
				end
			end, { name = "Found_" .. sector.id, style = "primary" })
			K.setEnabled(found, sector.unlocked and not slotsFull and enough)
		end
	end

	-- ───────── Render general ─────────

	function render()
		if scroll == nil or not scroll.Parent then
			return
		end
		K.clear(scroll)
		upgradeButtons = {}
		renderSelector()
		if view.mode == "found" then
			renderFound()
			return
		end
		if view.loading and view.detail == nil then
			K.label(scroll, T("common.loading"), { size = S.text, color = C.textDim, layoutOrder = 5 })
			return
		end
		local detail = view.detail
		if detail == nil then
			K.label(scroll, T("common.empty"), { size = S.text, color = C.textDim, layoutOrder = 5 })
			return
		end
		renderHeader(detail)

		if detail.isNpc then
			renderExchange(detail)
		elseif detail.rights and detail.rights.manages then
			local tabs = K.tabs(scroll, {
				{ id = "upgrades", text = T("company.upgrades") },
				{ id = "style", text = T("company.rename") },
				{ id = "history", text = T("company.history") },
			}, function(id)
				view.tab = id
				-- se repinta el contenido de la pestaña (sin volver a pedir datos)
				for _, child in scroll:GetChildren() do
					-- Sólo los GuiObject tienen LayoutOrder (un UIListLayout no).
					if child:IsA("GuiObject") and child.LayoutOrder >= 9 and child.LayoutOrder < 30 then
						child:Destroy()
					end
				end
				upgradeButtons = {}
				if id == "upgrades" then
					renderUpgrades(detail)
				elseif id == "style" then
					renderStyle(detail)
				else
					renderHistory(detail)
				end
			end, 8)
			tabs.select(view.tab)
		else
			K.label(
				scroll,
				T("company.not_managed"),
				{ size = S.textSmall, color = C.textDim, layoutOrder = 8 }
			)
			renderHistory(detail)
		end
		renderOwnership(detail)
	end

	-- ───────── Registro de la ventana ─────────

	ctx.windows:register("company", {
		title = function()
			return T("company.title")
		end,
		build = function(body, window)
			scroll = K.scroll(body, { name = "CompanyScroll" })
			local args = window.args or {}
			view.mode = "company"
			local target = args.companyId
			if target == nil then
				local first = ctx.store:managed()[1]
				target = first and first.id
			end
			if target == nil then
				view.mode = "found"
				view.detail = nil
				render()
				return
			end
			view.detail = nil
			task.spawn(fetch, target)

			-- Estados de los botones de compra al ritmo del Cash extrapolado.
			local accum = 0
			window.conn = RunService.Heartbeat:Connect(function(dt)
				accum += dt
				if accum >= 0.25 then
					accum = 0
					ctx.refreshUpgradeStates()
				end
			end)
		end,
		refresh = function()
			-- Llegó un estado nuevo: se actualizan las opciones (precios/cash) sin perder la pestaña.
			if view.mode == "company" and view.companyId and not view.loading then
				local mine = ctx.store:company(view.companyId)
				if mine and mine.options and view.detail and view.detail.options then
					view.detail.options = mine.options
					view.detail.valuation = mine.valuation
					view.detail.income = mine.income
					view.detail.level = mine.level
				end
				render()
			elseif view.mode == "found" then
				render()
			end
		end,
		onClose = function(window)
			if window.conn then
				window.conn:Disconnect()
			end
			scroll = nil
			upgradeButtons = {}
		end,
	})

	return view
end

return CompanyPanel
