--!nonstrict
--[[
	Mercado: lo importante primero y sin parecer una terminal financiera.
	  Empresas   · la Bolsa (siempre compra y vende) y las empresas de otros jugadores
	  Mi cartera · lo que posees y cuánto vale
	  Ofertas    · recibidas (aceptar/rechazar con confirmación) y enviadas
	  Jugadores  · quién está en el servidor, alianzas, acceso rápido a sus empresas
	  Operaciones· últimos tratos del servidor
]]

local RunService = game:GetService("RunService")

local Trading = require(script.Parent.Trading)
local Widgets = require(script.Parent.Parent.UI.Widgets)

local MarketPanel = {}

function MarketPanel.register(ctx)
	local K = ctx.kit
	local C = ctx.theme.colors
	local S = ctx.theme.sizes
	local T = ctx.T

	local view = { tab = "companies", fetchedAt = -1e9 }
	local scroll, tabs
	local countdowns = {}
	local render

	-- Pide el mercado al servidor (con caché corta) y lo guarda en el almacén.
	function ctx.fetchMarket(force)
		if not force and ctx.store.market and ctx.clock() - view.fetchedAt < 3 then
			return ctx.store.market
		end
		local r = ctx.run("GetMarket", nil, {})
		if r.ok then
			view.fetchedAt = ctx.clock()
			ctx.store:set("market", r.data)
			return r.data
		end
		return nil
	end

	function ctx.refreshMarket()
		task.spawn(function()
			ctx.fetchMarket(true)
			if ctx.windows:isOpen("market") then
				render()
			end
		end)
	end

	local function finishAccepted(result)
		ctx.sfx("deal")
		ctx.popup("+" .. ctx.cash(result.received), ctx.theme.colors.green)
		if result.controlChanged then
			ctx.effects:confetti(40)
		end
		ctx.refreshMarket()
	end

	-- Aceptar una oferta: confirmación propia + segundo aviso si el servidor lo exige.
	local function acceptOffer(offer)
		local tax = math.floor(offer.price * ctx.Balance.SaleTaxBps / ctx.Balance.BpsTotal)
		Trading.confirm(ctx, {
			title = T("offer.confirm.title"),
			lines = {
				T("offer.confirm.sell", {
					pct = ctx.bps(offer.bps),
					company = offer.companyName,
					receive = ctx.cash(offer.price - tax),
				}),
				T("offer.fair") .. ": " .. ctx.cash(offer.fairPrice) .. "  ·  " .. Trading.premiumText(
					ctx,
					offer.price,
					offer.fairPrice
				),
				T("offer.tax", { v = ctx.cash(tax) }),
			},
			confirmText = T("common.accept"),
			onConfirm = function()
				local r = ctx.run(
					"RespondOffer",
					{ offerId = offer.id, action = "accept", confirm = false },
					{ silent = true }
				)
				if r.ok then
					finishAccepted(r.data)
					return true
				end
				if r.code == "CONFIRMATION_REQUIRED" then
					-- Operación importante: segundo aviso explícito.
					Trading.confirm(ctx, {
						title = T("offer.confirm.title"),
						lines = {
							T("offer.confirm.big"),
							T("offer.confirm.sell", {
								pct = ctx.bps(offer.bps),
								company = offer.companyName,
								receive = ctx.cash(offer.price - tax),
							}),
						},
						warning = (r.params and r.params.controlChanged) and T("offer.control_warning")
							or nil,
						confirmText = T("common.confirm"),
						onConfirm = function()
							local r2 = ctx.run(
								"RespondOffer",
								{ offerId = offer.id, action = "accept", confirm = true },
								{}
							)
							if r2.ok then
								finishAccepted(r2.data)
							end
							return r2.ok
						end,
					})
					return true
				end
				ctx.toast(ctx.errText(r.code, r.params), "bad")
				ctx.refreshMarket()
				return true
			end,
		})
	end

	-- ───────── Pestañas ─────────

	local function section(title, order)
		K.label(scroll, title, { bold = true, size = S.text + 1, layoutOrder = order, name = "Section" })
	end

	local function renderCompanies(data)
		local tut = ctx.store.state and ctx.store.state.tutorial
		local pulseInspect = tut and not tut.done and not tut.skipped and tut.stepId == "inspect_company"
		section(T("market.exchange"), 1)
		local order = 2
		local pulsed = false
		for _, c in data.companies do
			if c.isNpc then
				local row = Widgets.companyRow(ctx, scroll, c, function()
					ctx.openWindow("company", { companyId = c.id })
				end, { layoutOrder = order })
				if pulseInspect and not pulsed then
					pulsed = true
					ctx.pulse(row, true)
				end
				order += 1
			end
		end
		section(T("market.players_companies"), 10)
		local any = false
		order = 11
		for _, c in data.companies do
			if not c.isNpc then
				any = true
				Widgets.companyRow(ctx, scroll, c, function()
					ctx.openWindow("company", { companyId = c.id })
				end, { layoutOrder = order })
				order += 1
			end
		end
		if not any then
			K.label(scroll, T("common.empty"), { size = S.text, color = C.textDim, layoutOrder = 11 })
		end
		K.label(
			scroll,
			T("market.rules", {
				min = ctx.num(data.rules.minPriceRatio),
				max = ctx.num(data.rules.maxPriceRatio),
				tax = ctx.bps(data.rules.saleTaxBps),
			}),
			{ size = S.textSmall, color = C.textDim, layoutOrder = 100 }
		)
	end

	local function renderPortfolio()
		local state = ctx.store.state
		local list = state and state.portfolio or {}
		if #list == 0 then
			K.label(
				scroll,
				T("market.empty_portfolio"),
				{ size = S.text, color = C.textDim, layoutOrder = 1 }
			)
			return
		end
		for i, p in list do
			local row = K.button(scroll, "", function()
				if p.online then
					ctx.openWindow("company", { companyId = p.companyId })
				else
					ctx.toast(T("market.portfolio.offline"), "warn")
				end
			end, {
				name = "Holding_" .. p.companyId,
				style = "ghost",
				size = UDim2.new(1, 0, 0, 70),
				layoutOrder = i,
			})
			row.Text = ""
			K.stroke(row, C.stroke, 1, 0.3)
			K.label(row, p.name, {
				bold = true,
				size = S.text,
				height = 22,
				size2 = UDim2.new(1, -140, 0, 22),
				position = UDim2.fromOffset(12, 6),
				name = "Name",
			})
			K.label(
				row,
				ctx.bps(p.bps)
					.. "  ·  "
					.. (p.isOwn and T("common.you") or p.founderName)
					.. (p.online and "" or ("  ·  " .. T("common.offline"))),
				{
					size = S.textSmall,
					color = C.textDim,
					height = 16,
					size2 = UDim2.new(1, -140, 0, 16),
					position = UDim2.fromOffset(12, 30),
					name = "Detail",
				}
			)
			K.label(row, ctx.cash(p.value), {
				bold = true,
				size = S.text,
				color = C.gold,
				align = "right",
				height = 22,
				size2 = UDim2.new(0, 120, 0, 22),
				position = UDim2.new(1, -128, 0, 10),
				name = "Value",
			})
			if not p.online then
				K.label(row, T("market.portfolio.offline"), {
					size = S.textSmall - 1,
					color = C.textDim,
					height = 14,
					size2 = UDim2.new(1, -24, 0, 14),
					position = UDim2.fromOffset(12, 50),
					name = "OfflineNote",
				})
			end
		end
	end

	local function offerCard(offer, incoming, order)
		local card = K.card(scroll, {
			name = "Offer_" .. offer.id,
			color = C.surface,
			layoutOrder = order,
			strokeColor = incoming and C.gold or C.stroke,
		})
		K.layout(card, { gap = 6 })
		if incoming then
			K.label(
				card,
				T(
					"offer.wants",
					{ name = offer.counterpartName, pct = ctx.bps(offer.bps), company = offer.companyName }
				),
				{ bold = true, size = S.text }
			)
		else
			K.label(
				card,
				T("offer.waiting", { name = offer.counterpartName })
					.. " · "
					.. offer.companyName
					.. " "
					.. ctx.bps(offer.bps),
				{ bold = true, size = S.text }
			)
		end
		K.label(
			card,
			T("offer.price")
				.. ": "
				.. ctx.cash(offer.price)
				.. "   ·   "
				.. T("offer.fair")
				.. ": "
				.. ctx.cash(offer.fairPrice),
			{ size = S.text, color = C.gold }
		)
		K.label(
			card,
			Trading.premiumText(ctx, offer.price, offer.fairPrice),
			{ size = S.textSmall, color = C.textDim }
		)
		local timer = K.label(
			card,
			T("offer.expires", { time = ctx.duration(ctx.store:offerRemaining(offer)) }),
			{ size = S.textSmall, color = C.warn, name = "Timer" }
		)
		table.insert(countdowns, { label = timer, offer = offer })
		if incoming then
			K.label(card, "• " .. T("offer.cond.atomic"), { size = S.textSmall, color = C.textDim })
			K.label(card, "• " .. T("offer.cond.revalidated"), { size = S.textSmall, color = C.textDim })
			local row = K.frame(card, { name = "Buttons", size = UDim2.new(1, 0, 0, S.touch) })
			K.layout(row, { horizontal = true, gap = 8 })
			local reject
			reject = K.button(row, T("common.reject"), function()
				local r = ctx.run(
					"RespondOffer",
					{ offerId = offer.id, action = "reject" },
					{ button = reject }
				)
				if r.ok then
					ctx.refreshMarket()
				end
			end, { name = "Reject_" .. offer.id, style = "secondary", size = UDim2.new(0.4, -4, 1, 0) })
			K.button(row, T("common.accept"), function()
				acceptOffer(offer)
			end, { name = "Accept_" .. offer.id, style = "success", size = UDim2.new(0.6, -4, 1, 0) })
		else
			local cancel
			cancel = K.button(card, T("offer.cancel"), function()
				local r = ctx.run(
					"RespondOffer",
					{ offerId = offer.id, action = "cancel" },
					{ button = cancel }
				)
				if r.ok then
					ctx.refreshMarket()
				end
			end, { name = "Cancel_" .. offer.id, style = "secondary" })
		end
	end

	local function renderOffers()
		local offers = ctx.store.offers
		K.label(scroll, T("offer.incoming"), { bold = true, size = S.text + 1, layoutOrder = 1 })
		if #offers.incoming == 0 then
			K.label(scroll, T("market.no_offers"), { size = S.text, color = C.textDim, layoutOrder = 2 })
		end
		for i, o in offers.incoming do
			offerCard(o, true, 2 + i)
		end
		K.label(scroll, T("offer.outgoing"), { bold = true, size = S.text + 1, layoutOrder = 50 })
		if #offers.outgoing == 0 then
			K.label(scroll, T("market.no_offers"), { size = S.text, color = C.textDim, layoutOrder = 51 })
		end
		for i, o in offers.outgoing do
			offerCard(o, false, 51 + i)
		end
	end

	local function renderPeople(data)
		local state = ctx.store.state
		local me = state.userId
		-- Alianza
		local al = state.alliance
		local card = K.card(scroll, { name = "AllianceCard", color = C.surface2, layoutOrder = 1 })
		K.layout(card, { gap = 6 })
		K.label(card, "🤝 " .. T("alliance.title"), { bold = true, size = S.text + 1 })
		if #al.members >= 2 then
			local names = {}
			for _, m in al.members do
				table.insert(names, m.name)
			end
			K.label(card, T("alliance.members") .. ": " .. table.concat(names, ", "), { size = S.text })
			K.label(
				card,
				T("alliance.bonus", { pct = ctx.bps((al.multiplier - 1) * 10000) }),
				{ size = S.text, color = C.green, bold = true }
			)
			local leave
			leave = K.button(card, T("alliance.leave"), function()
				local r = ctx.run("AllianceLeave", nil, { button = leave })
				if r.ok then
					ctx.refreshMarket()
				end
			end, { name = "LeaveAlliance", style = "secondary" })
		else
			K.label(card, T("alliance.none"), { size = S.text, color = C.textDim })
		end
		K.label(card, T("alliance.hint"), { size = S.textSmall, color = C.textDim })
		for _, inv in al.invites do
			local row = K.frame(card, { name = "Invite_" .. inv.id, size = UDim2.new(1, 0, 0, S.touch) })
			K.layout(row, { horizontal = true, gap = 8 })
			K.label(
				row,
				T("alliance.invite_from", { name = inv.fromName }),
				{ size = S.textSmall, height = S.touch, size2 = UDim2.new(0.4, 0, 1, 0) }
			)
			K.button(row, T("common.reject"), function()
				ctx.run("AllianceRespond", { inviteId = inv.id, accept = false }, {})
				ctx.refreshMarket()
			end, { name = "DeclineInvite", size = UDim2.new(0.28, -4, 1, 0), textSize = S.textSmall })
			K.button(row, T("common.accept"), function()
				local r = ctx.run("AllianceRespond", { inviteId = inv.id, accept = true }, {})
				if r.ok then
					ctx.refreshMarket()
				end
			end, {
				name = "AcceptInvite",
				style = "success",
				size = UDim2.new(0.32, -4, 1, 0),
				textSize = S.textSmall,
			})
		end

		K.label(scroll, T("market.people.hint"), { size = S.textSmall, color = C.textDim, layoutOrder = 2 })
		local others = 0
		for i, p in data.players do
			if p.id ~= me then
				others += 1
				local row =
					K.card(scroll, { name = "Player_" .. p.id, color = C.surface, layoutOrder = 10 + i })
				K.layout(row, { gap = 6 })
				K.label(
					row,
					(ctx.theme.badges[p.badge] or "") .. "  " .. p.name .. "   ·   " .. T("rank." .. p.badge),
					{ bold = true, size = S.text }
				)
				local buttons = K.frame(row, { name = "Buttons", size = UDim2.new(1, 0, 0, S.touch) })
				K.layout(buttons, { horizontal = true, gap = 8 })
				K.button(buttons, T("people.companies"), function()
					ctx.openWindow("company", { companyId = p.id .. ":1" })
				end, { name = "View_" .. p.id, size = UDim2.new(0.5, -4, 1, 0), textSize = S.textSmall })
				K.button(buttons, T("people.invite"), function()
					local r = ctx.run("AllianceInvite", { targetId = p.id }, {})
					if r.ok then
						ctx.toast(T("people.invite") .. " ✓", "good")
					end
				end, {
					name = "Invite_" .. p.id,
					style = "primary",
					size = UDim2.new(0.5, -4, 1, 0),
					textSize = S.textSmall,
				})
			end
		end
		if others == 0 then
			K.label(scroll, T("people.no_others"), { size = S.text, color = C.textDim, layoutOrder = 10 })
		end
	end

	local function renderDeals(data)
		if #data.deals == 0 then
			K.label(scroll, T("market.no_deals"), { size = S.text, color = C.textDim, layoutOrder = 1 })
			return
		end
		for i = #data.deals, 1, -1 do
			local d = data.deals[i]
			local card =
				K.card(scroll, { name = "Deal_" .. i, color = C.surface, layoutOrder = #data.deals - i + 1 })
			K.label(card, T("company.history.trade", {
				buyer = d.buyerName,
				seller = d.sellerName,
				pct = ctx.bps(d.bps),
				price = ctx.cash(d.price),
			}) .. " · " .. d.companyName, { size = S.text })
		end
	end

	function render()
		if scroll == nil or not scroll.Parent then
			return
		end
		K.clear(scroll)
		countdowns = {}
		ctx.pulse(nil, false)
		local data = ctx.store.market
		if view.tab == "offers" then
			renderOffers()
		elseif view.tab == "portfolio" then
			renderPortfolio()
		elseif data == nil then
			K.label(scroll, T("common.loading"), { size = S.text, color = C.textDim })
		elseif view.tab == "companies" then
			renderCompanies(data)
		elseif view.tab == "people" then
			renderPeople(data)
		elseif view.tab == "deals" then
			renderDeals(data)
		end
		-- contador de ofertas en la pestaña
		if tabs then
			local incoming = #ctx.store.offers.incoming
			tabs.setText(
				"offers",
				T("market.tab.offers") .. (incoming > 0 and (" (" .. incoming .. ")") or "")
			)
		end
	end

	ctx.windows:register("market", {
		title = function()
			return "🏛 " .. T("market.title")
		end,
		build = function(body, window)
			local args = window.args or {}
			view.tab = args.tab or view.tab or "companies"
			local column = K.frame(body, { name = "Column", size = UDim2.fromScale(1, 1) })
			K.layout(column, { gap = 8 })
			tabs = K.tabs(column, {
				{ id = "companies", text = T("market.tab.companies") },
				{ id = "portfolio", text = T("market.tab.portfolio") },
				{ id = "offers", text = T("market.tab.offers") },
				{ id = "people", text = T("market.tab.people") },
				{ id = "deals", text = T("market.tab.deals") },
			}, function(id)
				view.tab = id
				render()
			end, 1)
			scroll = K.scroll(column, { name = "MarketScroll", size = UDim2.new(1, 0, 1, -52) })
			scroll.LayoutOrder = 2
			tabs.select(view.tab)
			task.spawn(function()
				ctx.fetchMarket(true)
				render()
			end)

			local accum = 0
			window.conn = RunService.Heartbeat:Connect(function(dt)
				accum += dt
				if accum >= 0.5 then
					accum = 0
					for _, c in countdowns do
						if c.label.Parent then
							c.label.Text =
								T("offer.expires", { time = ctx.duration(ctx.store:offerRemaining(c.offer)) })
						end
					end
				end
			end)
		end,
		refresh = function()
			render()
		end,
		onClose = function(window)
			if window.conn then
				window.conn:Disconnect()
			end
			scroll, tabs = nil, nil
			countdowns = {}
		end,
	})

	return view
end

return MarketPanel
