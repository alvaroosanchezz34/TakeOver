--!nonstrict
--[[
	HUD principal. Lo que el jugador ve SIEMPRE:
	  - Cash y cuánto gana por segundo (cifras grandes, animadas suavemente),
	  - patrimonio neto y puesto en el ranking,
	  - la SIGUIENTE MEJORA recomendada, con su precio, beneficio y cuánto falta,
	  - acceso rápido a Empresa, Mercado, Ranking y Menú.
	Entiende qué hacer en 5 segundos: hay UNA acción destacada ("Comprar") y está a un toque.
]]

local RunService = game:GetService("RunService")

local HUD = {}
HUD.__index = HUD

function HUD.new(ctx)
	local self = setmetatable({ ctx = ctx, _accum = 0, _pulse = {}, _lastCash = nil }, HUD)
	local K = ctx.kit
	local C = ctx.theme.colors
	local S = ctx.theme.sizes
	local gui = ctx.layers.hud
	self.gui = gui

	local root = K.frame(gui, { name = "HUDRoot" })
	self.root = root

	-- ───────── Tarjeta de Cash (arriba a la izquierda) ─────────
	local cashCard = K.card(root, {
		name = "CashCard",
		size = UDim2.new(0, 250, 0, 0),
		autoY = true,
		position = UDim2.fromOffset(12, 8),
		color = C.surface,
		transparency = 0.06,
	})
	K.layout(cashCard, { gap = 2 })
	self.cashCard = cashCard
	K.label(
		cashCard,
		ctx.T("hud.cash"),
		{ size = S.textSmall, color = C.textDim, height = 16, name = "CashTitle" }
	)
	self.cashLabel = K.label(
		cashCard,
		"0 $",
		{ bold = true, size = S.hero, color = C.gold, height = 40, name = "CashValue" }
	)
	self.incomeLabel = K.label(
		cashCard,
		"",
		{ size = S.text, color = C.green, bold = true, height = 22, name = "IncomeValue" }
	)
	self.netLabel =
		K.label(cashCard, "", { size = S.textSmall, color = C.textDim, height = 18, name = "NetWorth" })

	-- ───────── Puesto (arriba a la derecha) ─────────
	local rankCard = K.card(root, {
		name = "RankCard",
		size = UDim2.new(0, 160, 0, 0),
		autoY = true,
		anchor = Vector2.new(1, 0),
		position = UDim2.new(1, -12, 0, 8),
		color = C.surface,
		transparency = 0.06,
	})
	K.layout(rankCard, { gap = 2 })
	self.rankCard = rankCard
	self.badgeLabel = K.label(rankCard, "🌱", { size = 28, height = 32, align = "center", name = "Badge" })
	self.rankLabel = K.label(
		rankCard,
		"",
		{ bold = true, size = S.text, height = 20, align = "center", name = "RankValue" }
	)
	self.rankName = K.label(
		rankCard,
		"",
		{ size = S.textSmall, color = C.textDim, height = 16, align = "center", name = "RankName" }
	)
	self.companiesLabel = K.label(
		rankCard,
		"",
		{ size = S.textSmall, color = C.textDim, height = 16, align = "center", name = "CompaniesCount" }
	)

	-- ───────── Siguiente mejora (abajo, centro) ─────────
	local nextCard = K.card(root, {
		name = "NextCard",
		size = UDim2.new(0.94, 0, 0, 0),
		autoY = true,
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -(S.touch + 30)),
		color = C.surface,
		transparency = 0.04,
	})
	local nextLimit = Instance.new("UISizeConstraint")
	nextLimit.MaxSize = Vector2.new(560, 400)
	nextLimit.Parent = nextCard
	K.layout(nextCard, { gap = 6 })
	self.nextCard = nextCard
	K.label(
		nextCard,
		ctx.T("hud.next"),
		{ size = S.textSmall, color = C.textDim, height = 16, name = "NextTitle" }
	)

	local row = K.frame(nextCard, { name = "NextRow", size = UDim2.new(1, 0, 0, S.touch + 4) })
	self.nextName = K.label(row, "", {
		bold = true,
		size = S.text + 1,
		height = 22,
		size2 = UDim2.new(1, -150, 0, 22),
		name = "NextName",
	})
	self.nextEffect = K.label(row, "", {
		size = S.textSmall,
		color = C.textDim,
		height = 32,
		size2 = UDim2.new(1, -150, 0, 32),
		position = UDim2.fromOffset(0, 22),
		name = "NextEffect",
	})
	self.buyButton = K.button(row, ctx.T("hud.btn.buy"), function()
		self:_buy()
	end, {
		name = "BuyButton",
		style = "success",
		size = UDim2.new(0, 140, 0, S.touch),
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, 0, 0.5, 0),
	})
	self.nextProgress = K.progress(nextCard, 0, C.gold, 8)
	self.nextStatus =
		K.label(nextCard, "", { size = S.textSmall, color = C.textDim, height = 16, name = "NextStatus" })

	-- ───────── Navegación (abajo) ─────────
	local nav = K.frame(root, {
		name = "Nav",
		size = UDim2.new(0.94, 0, 0, S.touch + 6),
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -8),
	})
	local navLimit = Instance.new("UISizeConstraint")
	navLimit.MaxSize = Vector2.new(560, S.touch + 6)
	navLimit.Parent = nav
	K.layout(nav, { horizontal = true, gap = 6 })
	local function navButton(id, key, icon)
		return K.button(nav, ctx.T(key), function()
			ctx.openWindow(id)
		end, {
			name = "Nav_" .. id,
			icon = icon,
			size = UDim2.new(0.25, -5, 1, 0),
			textSize = S.textSmall + 1,
			style = "ghost",
		})
	end
	self.navCompany = navButton("company", "hud.btn.company", "🏢")
	self.navMarket = navButton("market", "hud.btn.market", "🏛")
	self.navRanking = navButton("ranking", "hud.btn.ranking", "🏆")
	self.navMenu = navButton("menu", "hud.btn.menu", "☰")

	-- ───────── Pantalla de carga / reconexión ─────────
	local loading = K.frame(gui, { name = "Loading", size = UDim2.fromScale(1, 1) })
	loading.BackgroundTransparency = 0
	loading.BackgroundColor3 = C.bg
	loading.Active = true
	K.label(loading, "TAKEOVER", {
		bold = true,
		size = 54,
		color = C.accent,
		align = "center",
		height = 70,
		size2 = UDim2.new(1, 0, 0, 70),
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.42),
		name = "LoadingTitle",
	})
	K.label(loading, ctx.T("hud.loading"), {
		size = S.textBig,
		color = C.textDim,
		align = "center",
		height = 30,
		size2 = UDim2.new(1, 0, 0, 30),
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.55),
		name = "LoadingText",
	})
	self.loading = loading

	-- Bucle de refresco suave (10 Hz): cifras y pulso del tutorial.
	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:tick(dt)
	end)

	self:relayout()
	self:render()
	return self
end

function HUD:relayout()
	local compact = self.ctx.compact()
	self.cashCard.Size = UDim2.new(0, compact and 190 or 250, 0, 0)
	self.rankCard.Size = UDim2.new(0, compact and 118 or 160, 0, 0)
	self.cashLabel.TextSize = compact and 28 or self.ctx.theme.sizes.hero
end

function HUD:_buy()
	local ctx = self.ctx
	local rec = ctx.store.state and ctx.store.state.recommended
	if rec == nil then
		return
	end
	local action = if rec.kind == "level" then "LevelUp" else "BuyUpgrade"
	local payload = if rec.kind == "level"
		then { companyId = rec.companyId }
		else { companyId = rec.companyId, upgradeId = rec.id }
	local r = ctx.run(action, payload, { button = self.buyButton })
	if r.ok then
		ctx.sfx("buy")
	end
end

-- Resalta un botón con un borde que pulsa (guía del tutorial).
function HUD:setPulse(button, on)
	if button == nil then
		return
	end
	local stroke = button:FindFirstChild("PulseStroke")
	if on then
		if stroke == nil then
			stroke = Instance.new("UIStroke")
			stroke.Name = "PulseStroke"
			stroke.Color = self.ctx.theme.colors.gold
			stroke.Thickness = 3
			stroke.Parent = button
		end
		self._pulse[button] = true
	else
		if stroke then
			stroke:Destroy()
		end
		self._pulse[button] = nil
	end
end

function HUD:tick(dt)
	self._accum += dt
	-- pulso (cada frame, barato)
	local alpha = 0.2 + 0.5 * (0.5 + 0.5 * math.sin(os.clock() * 5))
	for button in self._pulse do
		local stroke = button:FindFirstChild("PulseStroke")
		if stroke then
			stroke.Transparency = 1 - alpha
		end
	end
	if self._accum >= 0.1 then
		self._accum = 0
		self:renderNumbers()
	end
end

-- Cifras que cambian con el tiempo: Cash extrapolado y cuenta atrás del siguiente evento.
function HUD:renderNumbers()
	local ctx = self.ctx
	local state = ctx.store.state
	if state == nil then
		return
	end
	local cash = ctx.store:displayCash()
	self._lastCash = cash
	self.cashLabel.Text = ctx.cash(cash)

	local rec = state.recommended
	if rec then
		local missing = math.max(0, rec.cost - cash)
		self.nextProgress:FindFirstChild("Fill").Size =
			UDim2.fromScale(math.clamp(cash / math.max(1, rec.cost), 0, 1), 1)
		if missing > 0 then
			self.nextStatus.Text = ctx.T("hud.next.missing", { amount = ctx.cash(missing) })
			ctx.kit.setEnabled(self.buyButton, false)
		else
			self.nextStatus.Text = ctx.T("hud.next.ready")
			ctx.kit.setEnabled(self.buyButton, true)
		end
	end
end

function HUD:render()
	local ctx = self.ctx
	local state = ctx.store.state
	self.loading.Visible = state == nil
	if state == nil then
		return
	end
	local T = ctx.T

	self.incomeLabel.Text = "+" .. ctx.rate(state.incomePerSecond)
	self.netLabel.Text = T("hud.networth") .. ": " .. ctx.cash(state.netWorth)
	self.badgeLabel.Text = ctx.theme.badges[state.rank.badge] or "🌱"
	self.rankLabel.Text = T("hud.rank.value", { pos = state.rank.pos, count = state.rank.count })
	self.rankName.Text = T("rank." .. state.rank.badge)
	local owned = 0
	for _, c in state.companies do
		if c.manages then
			owned += 1
		end
	end
	self.companiesLabel.Text = T("hud.companies") .. ": " .. owned

	-- Siguiente mejora
	local rec = state.recommended
	self.nextCard.Visible = true
	if rec then
		self.nextName.Text = rec.icon .. "  " .. T(rec.nameKey) .. "  ·  " .. ctx.cash(rec.cost)
		local effect
		if rec.kind == "level" then
			effect = T("effect.level")
		else
			effect = T("effect." .. rec.effectKind, { v = ctx.effectValue(rec.effectKind, rec.effectValue) })
		end
		local gain = if rec.deltaIncome > 0
			then ("  ·  " .. T("upgrade.gain", { v = ctx.num(rec.deltaIncome) }))
			else ""
		local payback = if rec.paybackSeconds
			then ("  ·  " .. T("hud.next.payback", { time = ctx.duration(rec.paybackSeconds) }))
			else ""
		self.nextEffect.Text = effect .. gain .. payback
		self.buyButton.Visible = true
	else
		self.nextName.Text = T("hud.next.none")
		self.nextEffect.Text = ""
		self.nextStatus.Text = ""
		self.buyButton.Visible = false
	end
	self:renderNumbers()

	-- Contador de ofertas recibidas en el botón del mercado
	local incoming = #ctx.store.offers.incoming
	self.navMarket.Text = "🏛  "
		.. T("hud.btn.market")
		.. (incoming > 0 and (" (" .. incoming .. ")") or "")
end

function HUD:destroy()
	if self._conn then
		self._conn:Disconnect()
	end
end

return HUD
