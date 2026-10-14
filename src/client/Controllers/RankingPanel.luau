--!nonstrict
--[[
	Clasificación del servidor: mayores empresas (por valoración) y mayores magnates (por
	patrimonio neto), con tu puesto destacado. Los datos llegan del servidor cada pocos segundos.
]]

local RankingPanel = {}

function RankingPanel.register(ctx)
	local K = ctx.kit
	local C = ctx.theme.colors
	local S = ctx.theme.sizes
	local T = ctx.T

	local scroll

	local function medal(rank)
		return ({ "🥇", "🥈", "🥉" })[rank] or ("#" .. rank)
	end

	local function render()
		if scroll == nil or not scroll.Parent then
			return
		end
		K.clear(scroll)
		local state = ctx.store.state
		local board = ctx.store.leaderboard
		local me = state and state.userId

		if state then
			local card = K.card(
				scroll,
				{ name = "MyRank", color = C.surface2, layoutOrder = 1, strokeColor = C.accent }
			)
			K.layout(card, { gap = 2 })
			K.label(card, T("ranking.you"), { size = S.textSmall, color = C.textDim })
			K.label(
				card,
				(ctx.theme.badges[state.rank.badge] or "")
					.. "  "
					.. T("hud.rank.value", { pos = state.rank.pos, count = state.rank.count })
					.. "  ·  "
					.. T("rank." .. state.rank.badge),
				{
					bold = true,
					size = S.textBig,
				}
			)
			K.label(
				card,
				T("hud.networth") .. ": " .. ctx.cash(state.netWorth),
				{ size = S.text, color = C.gold }
			)
		end

		K.label(scroll, "🏆 " .. T("ranking.players"), { bold = true, size = S.text + 1, layoutOrder = 2 })
		if #board.players == 0 then
			K.label(scroll, T("common.empty"), { size = S.text, color = C.textDim, layoutOrder = 3 })
		end
		for i, p in board.players do
			local isMe = p.userId == me
			local row = K.card(scroll, {
				name = "Player_" .. p.userId,
				size = UDim2.new(1, 0, 0, 52),
				autoY = false,
				color = isMe and C.surface3 or C.surface,
				layoutOrder = 3 + i,
				pad = 8,
			})
			K.label(row, medal(p.rank), {
				bold = true,
				size = S.text + 2,
				height = 36,
				size2 = UDim2.fromOffset(46, 36),
				name = "Rank",
			})
			K.label(
				row,
				(ctx.theme.badges[p.badge] or "")
					.. " "
					.. p.name
					.. (isMe and (" (" .. T("common.you") .. ")") or ""),
				{
					bold = isMe,
					size = S.text,
					height = 36,
					size2 = UDim2.new(1, -190, 0, 36),
					position = UDim2.fromOffset(50, 0),
					name = "Name",
				}
			)
			K.label(row, ctx.cash(p.netWorth), {
				bold = true,
				size = S.text,
				color = C.gold,
				align = "right",
				height = 36,
				size2 = UDim2.new(0, 130, 0, 36),
				position = UDim2.new(1, -130, 0, 0),
				name = "Worth",
			})
		end

		K.label(
			scroll,
			"🏢 " .. T("ranking.companies"),
			{ bold = true, size = S.text + 1, layoutOrder = 30 }
		)
		if #board.companies == 0 then
			K.label(scroll, T("common.empty"), { size = S.text, color = C.textDim, layoutOrder = 31 })
		end
		for i, c in board.companies do
			local row = K.button(scroll, "", function()
				ctx.openWindow("company", { companyId = c.id })
			end, {
				name = "Company_" .. c.id,
				style = "ghost",
				size = UDim2.new(1, 0, 0, 56),
				layoutOrder = 31 + i,
			})
			row.Text = ""
			K.stroke(row, C.sector[c.sector] or C.stroke, 1, 0.4)
			K.label(row, medal(c.rank), {
				bold = true,
				size = S.text + 2,
				height = 56,
				size2 = UDim2.fromOffset(46, 56),
				position = UDim2.fromOffset(6, 0),
				name = "Rank",
			})
			K.label(row, c.name, {
				bold = true,
				size = S.text,
				height = 22,
				size2 = UDim2.new(1, -200, 0, 22),
				position = UDim2.fromOffset(56, 6),
				name = "Name",
			})
			K.label(row, T("company.manager") .. ": " .. c.managerName, {
				size = S.textSmall,
				color = C.textDim,
				height = 16,
				size2 = UDim2.new(1, -200, 0, 16),
				position = UDim2.fromOffset(56, 30),
				name = "Manager",
			})
			K.label(row, ctx.cash(c.valuation), {
				bold = true,
				size = S.text,
				color = C.gold,
				align = "right",
				height = 22,
				size2 = UDim2.new(0, 130, 0, 22),
				position = UDim2.new(1, -138, 0, 6),
				name = "Value",
			})
			K.label(row, "+" .. ctx.rate(c.income), {
				size = S.textSmall,
				color = C.green,
				align = "right",
				height = 16,
				size2 = UDim2.new(0, 130, 0, 16),
				position = UDim2.new(1, -138, 0, 30),
				name = "Income",
			})
		end
	end

	ctx.windows:register("ranking", {
		title = function()
			return "🏆 " .. T("ranking.title")
		end,
		build = function(body)
			scroll = K.scroll(body, { name = "RankingScroll" })
			render()
			task.spawn(function()
				local r = ctx.run("GetLeaderboard", nil, {})
				if r.ok then
					ctx.store:set("leaderboard", r.data)
				end
			end)
		end,
		refresh = render,
		onClose = function()
			scroll = nil
		end,
	})
end

return RankingPanel
