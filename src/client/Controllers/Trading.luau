--!nonstrict
--[[
	Diálogos de comercio: confirmaciones, nueva oferta y compra/venta a la Bolsa.

	Principios de interfaz:
	  - Precio, porcentaje, valor de referencia y condiciones siempre visibles.
	  - Los límites que se muestran (banda de precios, impuesto) son informativos: el SERVIDOR
	    valida y recalcula todo; si algo no cuadra, devuelve un error con su motivo.
	  - Operaciones importantes: segundo aviso explícito (lo pide el servidor).
]]

local Trading = {}

-- Fondo atenuado + tarjeta centrada. Tocar fuera cancela. Devuelve { card, body, close }.
local function modal(ctx, name, width)
	local K = ctx.kit
	local C = ctx.theme.colors
	local root = K.frame(ctx.layers.modals, { name = name, size = UDim2.fromScale(1, 1) })
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.BackgroundColor3 = C.black
	dim.BackgroundTransparency = 0.35
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.Parent = root
	local obj = {}
	function obj.close()
		if root.Parent then
			root:Destroy()
		end
	end
	dim.Activated:Connect(obj.close)

	local card = K.card(root, {
		name = "ModalCard",
		size = UDim2.new(0.92, 0, 0, 0),
		autoY = true,
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		color = C.surface,
		strokeColor = C.accent,
		pad = 16,
	})
	card.Active = true -- los toques sobre la tarjeta no la cierran
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(width or 480, 700)
	limit.Parent = card
	K.layout(card, { gap = 10 })
	obj.root, obj.card = root, card
	return obj
end
Trading.modal = modal

--[[
	Confirmación genérica.
	props: title, lines = { texto... }, warning (opcional), confirmText, onConfirm()
]]
function Trading.confirm(ctx, props)
	local K = ctx.kit
	local C = ctx.theme.colors
	local S = ctx.theme.sizes
	local m = modal(ctx, "ConfirmModal", 460)
	K.label(m.card, props.title, { bold = true, size = S.textBig, name = "ConfirmTitle" })
	for _, line in props.lines or {} do
		K.label(m.card, line, { size = S.text, color = C.text })
	end
	if props.warning then
		local warn = K.card(m.card, { name = "Warning", color = C.surface2, strokeColor = C.warn })
		K.label(warn, props.warning, { size = S.text, color = C.warn, bold = true })
	end
	local row = K.frame(m.card, { name = "Buttons", size = UDim2.new(1, 0, 0, S.touch) })
	K.layout(row, { horizontal = true, gap = 8 })
	K.button(
		row,
		ctx.T("common.cancel"),
		m.close,
		{ name = "Cancel", style = "secondary", size = UDim2.new(0.5, -4, 1, 0) }
	)
	local confirm
	confirm = K.button(row, props.confirmText or ctx.T("common.confirm"), function()
		K.setBusy(confirm, true)
		local ok = props.onConfirm()
		if ok ~= false then
			m.close()
		else
			K.setBusy(confirm, false)
		end
	end, { name = "Confirm", style = "primary", size = UDim2.new(0.5, -4, 1, 0) })
	return m
end

-- Texto "+12 % sobre el valor" / "8 % bajo el valor" / "Precio justo".
local function premiumText(ctx, price, fair)
	if fair <= 0 then
		return ""
	end
	local pct = (price - fair) / fair * 100
	if math.abs(pct) < 0.5 then
		return ctx.T("offer.fair_price")
	elseif pct > 0 then
		return ctx.T("offer.premium", { pct = string.format("%d %%", math.floor(pct + 0.5)) })
	end
	return ctx.T("offer.discount", { pct = string.format("%d %%", math.floor(-pct + 0.5)) })
end
Trading.premiumText = premiumText

--[[
	Nueva oferta de compra a un titular concreto.
	company: ficha con valuation y name; holder: { id, name, bps }.
]]
function Trading.openOffer(ctx, company, holder)
	local K = ctx.kit
	local C = ctx.theme.colors
	local S = ctx.theme.sizes
	local T = ctx.T
	local Balance = ctx.Balance

	local m = modal(ctx, "OfferModal", 500)
	K.label(m.card, T("offer.new"), { bold = true, size = S.textBig, name = "OfferTitle" })
	K.label(m.card, T("offer.company") .. ": " .. company.name, { size = S.text })
	K.label(
		m.card,
		T("offer.to") .. ": " .. holder.name .. "  (" .. ctx.bps(holder.bps) .. ")",
		{ size = S.text }
	)

	local maxPct = math.floor(holder.bps / Balance.LotBps)
	K.label(m.card, T("offer.pick_amount"), { size = S.textSmall, color = C.textDim })
	local fairLabel, premiumLabel, taxLabel, fundsLabel, rangeLabel
	local priceStepper

	local function fairFor(pct)
		return math.floor(company.valuation * (pct * Balance.LotBps) / Balance.BpsTotal)
	end
	local function bounds(pct)
		local fair = fairFor(pct)
		local lo = math.max(Balance.MinOfferPrice, math.ceil(fair * Balance.MinPriceRatio))
		local hi = math.max(lo, math.floor(fair * Balance.MaxPriceRatio))
		return lo, hi, fair
	end
	local function refresh(price)
		local pct = m.stake.get()
		local lo, hi, fair = bounds(pct)
		price = price or priceStepper.get()
		fairLabel.Text = T("offer.fair") .. ": " .. ctx.cash(fair)
		premiumLabel.Text = premiumText(ctx, price, fair)
		local tax = math.floor(price * Balance.SaleTaxBps / Balance.BpsTotal)
		taxLabel.Text = T("offer.tax", { v = ctx.cash(tax) })
			.. "  ·  "
			.. T("offer.receive", { v = ctx.cash(price - tax) })
		rangeLabel.Text = T("offer.price.min", { v = ctx.cash(lo) })
			.. "  ·  "
			.. T("offer.price.max", { v = ctx.cash(hi) })
		local cash = ctx.store.state and ctx.store.state.cash or 0
		if cash < price then
			fundsLabel.Text = T("offer.needs_funds", { missing = ctx.cash(price - cash) })
			fundsLabel.TextColor3 = C.warn
		else
			fundsLabel.Text = ""
		end
	end

	m.stake = K.stepper(m.card, {
		value = math.min(10, maxPct),
		min = 1,
		max = math.max(1, maxPct),
		step = 1,
		format = function(v)
			return string.format("%d %%", v)
		end,
		onChange = function(pct)
			if priceStepper then
				local lo, hi, fair = bounds(pct)
				priceStepper.setRange(lo, hi)
				priceStepper.set(fair)
				refresh(fair)
			end
		end,
	})

	K.label(m.card, T("offer.pick_price"), { size = S.textSmall, color = C.textDim })
	local lo0, hi0, fair0 = bounds(m.stake.get())
	priceStepper = K.stepper(m.card, {
		value = math.clamp(fair0, lo0, hi0),
		min = lo0,
		max = hi0,
		step = math.max(1, math.floor(fair0 * 0.05 + 0.5)),
		format = function(v)
			return ctx.cash(v)
		end,
		onChange = function(price)
			if fairLabel then
				refresh(price)
			end
		end,
	})

	-- Atajos de precio
	local quick = K.frame(m.card, { name = "Quick", size = UDim2.new(1, 0, 0, 44) })
	K.layout(quick, { horizontal = true, gap = 6 })
	for _, q in
		{
			{ key = "offer.quick.low", f = 0.85 },
			{ key = "offer.quick.fair", f = 1 },
			{ key = "offer.quick.high", f = 1.2 },
		}
	do
		K.button(quick, T(q.key), function()
			local _, _, fair = bounds(m.stake.get())
			priceStepper.set(math.floor(fair * q.f + 0.5))
		end, {
			name = "Quick_" .. q.key,
			style = "ghost",
			size = UDim2.new(1 / 3, -4, 0, 44),
			textSize = S.textSmall + 1,
		})
	end

	local info = K.card(m.card, { name = "OfferInfo", color = C.surface2 })
	K.layout(info, { gap = 3 })
	fairLabel = K.label(info, "", { size = S.text, name = "Fair" })
	premiumLabel = K.label(info, "", { size = S.text, bold = true, color = C.gold, name = "Premium" })
	taxLabel = K.label(info, "", { size = S.textSmall, color = C.textDim, name = "Tax" })
	rangeLabel = K.label(info, "", { size = S.textSmall, color = C.textDim, name = "Range" })
	fundsLabel = K.label(info, "", { size = S.textSmall, bold = true, name = "Funds" })
	K.label(m.card, "• " .. T("offer.cond.atomic"), { size = S.textSmall, color = C.textDim })
	K.label(m.card, "• " .. T("offer.cond.revalidated"), { size = S.textSmall, color = C.textDim })
	refresh()

	local row = K.frame(m.card, { name = "Buttons", size = UDim2.new(1, 0, 0, S.touch) })
	K.layout(row, { horizontal = true, gap = 8 })
	K.button(row, T("common.cancel"), m.close, { name = "Cancel", size = UDim2.new(0.4, -4, 1, 0) })
	local send
	send = K.button(row, T("offer.send"), function()
		local pct = m.stake.get()
		local r = ctx.run("MakeOffer", {
			companyId = company.id,
			sellerId = holder.id,
			bps = pct * Balance.LotBps,
			price = priceStepper.get(),
		}, { button = send })
		if r.ok then
			ctx.sfx("notify")
			ctx.toast(T("offer.waiting", { name = holder.name }), "info")
			m.close()
			ctx.refreshMarket()
		end
	end, { name = "Send", style = "primary", size = UDim2.new(0.6, -4, 1, 0) })
	return m
end

--[[
	Compra / venta a la Bolsa automática. npc = ficha del mercado (ask1Pct, bid1Pct, floatLeftBps,
	playerCapBps, myBps). mode inicial: "buy" | "sell".
]]
function Trading.openExchange(ctx, npc, mode)
	local K = ctx.kit
	local C = ctx.theme.colors
	local S = ctx.theme.sizes
	local T = ctx.T
	local Balance = ctx.Balance

	local m = modal(ctx, "ExchangeModal", 480)
	K.label(m.card, npc.name, { bold = true, size = S.textBig, name = "ExchangeTitle" })
	K.label(m.card, T("market.exchange.hint"), { size = S.textSmall, color = C.textDim })
	K.label(
		m.card,
		T("market.exchange.ask", { v = ctx.cash(npc.ask1Pct) }),
		{ size = S.text, color = C.text }
	)
	K.label(
		m.card,
		T("market.exchange.bid", { v = ctx.cash(npc.bid1Pct) }),
		{ size = S.text, color = C.text }
	)
	K.label(
		m.card,
		T("market.exchange.float", { pct = ctx.bps(npc.floatLeftBps) })
			.. "  ·  "
			.. T("market.exchange.cap", { pct = ctx.bps(npc.playerCapBps) }),
		{ size = S.textSmall, color = C.textDim }
	)
	if npc.myBps and npc.myBps > 0 then
		K.label(
			m.card,
			T("company.stake", { pct = ctx.bps(npc.myBps) }),
			{ size = S.text, bold = true, color = C.accent }
		)
	end

	local totalLabel
	local stepper
	local current = mode or "buy"
	local actionButton

	local function limits()
		if current == "buy" then
			local room = math.min(npc.floatLeftBps, npc.playerCapBps - (npc.myBps or 0))
			return math.max(0, math.floor(room / Balance.LotBps))
		end
		return math.floor((npc.myBps or 0) / Balance.LotBps)
	end
	local function refresh()
		local maxPct = limits()
		local pct = math.max(1, stepper and stepper.get() or 1)
		local per = current == "buy" and npc.ask1Pct or npc.bid1Pct
		totalLabel.Text = (current == "buy" and T("market.buy_exchange") or T("market.sell_exchange"))
			.. ":  ≈ "
			.. ctx.cash(per * pct)
		K.setEnabled(actionButton, maxPct >= 1)
	end

	local tabs = K.tabs(m.card, {
		{ id = "buy", text = T("market.buy_exchange") },
		{ id = "sell", text = T("market.sell_exchange") },
	}, function(id)
		current = id
		if stepper then
			local maxPct = limits()
			stepper.setRange(1, math.max(1, maxPct))
			refresh()
		end
	end)
	stepper = K.stepper(m.card, {
		value = 1,
		min = 1,
		max = math.max(1, limits()),
		step = 1,
		format = function(v)
			return string.format("%d %%", v)
		end,
		onChange = function()
			if totalLabel then
				refresh()
			end
		end,
	})
	totalLabel = K.label(m.card, "", { bold = true, size = S.textBig, color = C.gold, name = "Total" })
	local row = K.frame(m.card, { name = "Buttons", size = UDim2.new(1, 0, 0, S.touch) })
	K.layout(row, { horizontal = true, gap = 8 })
	K.button(row, T("common.cancel"), m.close, { name = "Cancel", size = UDim2.new(0.4, -4, 1, 0) })
	actionButton = K.button(row, T("common.confirm"), function()
		local pct = stepper.get()
		local payload = { companyId = npc.id, bps = pct * Balance.LotBps }
		local r
		if current == "buy" then
			payload.confirm = true -- el jugador ve el precio en este diálogo: es la confirmación explícita
			r = ctx.run("BuyMarket", payload, { button = actionButton })
		else
			r = ctx.run("SellMarket", payload, { button = actionButton })
		end
		if r.ok then
			ctx.sfx("buy")
			ctx.popup(
				(current == "buy" and "-" or "+") .. ctx.cash(r.data.price),
				current == "buy" and ctx.theme.colors.warn or ctx.theme.colors.green
			)
			m.close()
			ctx.refreshMarket()
		end
	end, { name = "ConfirmTrade", style = "primary", size = UDim2.new(0.6, -4, 1, 0) })
	tabs.select(mode or "buy")
	refresh()
	return m
end

return Trading
