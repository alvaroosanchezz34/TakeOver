--!nonstrict
--[[
	Menú: recompensa diaria, ajustes (sonido, música, idioma), títulos, estadísticas, cosméticos
	y tienda. La tienda vende SOLO cosméticos: pagar nunca da ventaja económica ni en tratos.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MenuPanel = {}

function MenuPanel.register(ctx)
	local K = ctx.kit
	local C = ctx.theme.colors
	local S = ctx.theme.sizes
	local T = ctx.T

	local scroll
	local dailyLabel, dailyButton

	local function card(title, order)
		local c = K.card(scroll, { name = "Section_" .. order, color = C.surface, layoutOrder = order })
		K.layout(c, { gap = 6 })
		K.label(c, title, { bold = true, size = S.text + 1 })
		return c
	end

	local function setSetting(key, value, button)
		ctx.run("SetSetting", { key = key, value = value }, { button = button })
	end

	local function renderDaily(state)
		local c = card("🎁 " .. T("menu.daily"), 1)
		dailyLabel = K.label(c, "", { size = S.text, color = C.textDim, name = "DailyStatus" })
		dailyButton = K.button(c, T("menu.daily"), function()
			local r = ctx.run("ClaimDaily", nil, { button = dailyButton })
			if r.ok then
				ctx.sfx("cash")
				ctx.popup("+" .. ctx.cash(r.data.reward), C.green)
			end
		end, { name = "ClaimDaily", style = "gold" })
		ctx.refreshDaily = function()
			local daily = ctx.store.state and ctx.store.state.daily
			if daily == nil or dailyLabel == nil or not dailyLabel.Parent then
				return
			end
			local remaining = math.max(0, daily.remaining - (ctx.clock() - ctx.store.receivedAt))
			if remaining <= 0 then
				dailyLabel.Text = T("menu.daily.ready")
					.. "  ·  "
					.. T("menu.daily.streak", { n = daily.streak })
				K.setEnabled(dailyButton, true)
			else
				dailyLabel.Text = T("menu.daily.wait", { time = ctx.duration(remaining) })
					.. "  ·  "
					.. T("menu.daily.streak", { n = daily.streak })
				K.setEnabled(dailyButton, false)
			end
		end
		ctx.refreshDaily()
	end

	local function renderSettings(state)
		local c = card("⚙ " .. T("menu.title"), 2)
		local sfx, music
		sfx = K.button(c, T("menu.sfx") .. ": " .. (state.settings.sfx and "ON" or "OFF"), function()
			setSetting("sfx", state.settings.sfx and "off" or "on", sfx)
		end, { name = "ToggleSfx", style = "ghost" })
		music = K.button(c, T("menu.music") .. ": " .. (state.settings.music and "ON" or "OFF"), function()
			setSetting("music", state.settings.music and "off" or "on", music)
		end, { name = "ToggleMusic", style = "ghost" })
		K.label(c, T("menu.language"), { size = S.textSmall, color = C.textDim })
		local row = K.frame(c, { name = "Languages", size = UDim2.new(1, 0, 0, 44) })
		K.layout(row, { horizontal = true, gap = 6 })
		for _, l in
			{ { "auto", "menu.language.auto" }, { "es", "menu.language.es" }, { "en", "menu.language.en" } }
		do
			local selected = state.settings.lang == l[1]
			K.button(row, T(l[2]), function()
				setSetting("lang", l[1])
			end, {
				name = "Lang_" .. l[1],
				style = selected and "primary" or "ghost",
				size = UDim2.new(1 / 3, -4, 0, 44),
				textSize = S.textSmall + 1,
			})
		end
	end

	local function renderTitles(state)
		local c = card("🏅 " .. T("menu.titles"), 3)
		local function pick(id, label)
			local selected = state.titles.selected == id
			K.button(c, (selected and "✓ " or "") .. label, function()
				ctx.run("SelectTitle", { id = id }, {})
			end, {
				name = "Title_" .. (id == "" and "none" or id),
				style = selected and "primary" or "ghost",
				textSize = S.textSmall + 1,
			})
		end
		pick("", T("menu.title.none"))
		for _, id in state.titles.available do
			pick(id, T("title." .. id))
		end
	end

	local function renderStats(state)
		local c = card("📊 " .. T("menu.stats"), 4)
		local st = state.stats
		local function line(label, value)
			K.label(c, label .. ": " .. value, { size = S.text })
		end
		line(T("menu.stat.earned"), ctx.cash(st.totalEarned))
		line(T("menu.stat.peak"), ctx.cash(st.peakNetWorth))
		line(T("menu.stat.deals"), tostring(st.dealsClosed))
		line(T("menu.stat.upgrades"), tostring(st.upgradesBought))
		line(T("menu.stat.time"), ctx.duration(st.playSeconds))
	end

	local function renderCosmetics(state)
		local c = card("✨ " .. T("menu.cosmetics"), 5)
		local owned = {}
		for _, id in state.cosmetics.owned do
			owned[id] = true
		end
		local function equip(slot, id)
			local def = ctx.MonetizationConfig.Cosmetics[id]
			local isFree = def.free
			local has = isFree
				or owned[id]
				or (def.consumable and (state.cosmetics.consumables[def.consumable] or 0) > 0)
			if not has then
				return
			end
			local selected = state.cosmetics.equipped[slot] == id
			K.button(c, (selected and "✓ " or "") .. T("cosmetic." .. id), function()
				ctx.run("EquipCosmetic", { slot = slot, id = id }, {})
			end, {
				name = "Equip_" .. id,
				style = selected and "primary" or "ghost",
				textSize = S.textSmall + 1,
			})
		end
		for _, id in
			{ "fx_default", "fx_confetti", "fx_golden", "office_default", "office_gold", "office_neon" }
		do
			equip(ctx.MonetizationConfig.Cosmetics[id].slot, id)
		end
	end

	local function renderShop(state)
		local c = card("🛒 " .. T("menu.shop"), 6)
		K.label(c, T("menu.shop.fair"), { size = S.textSmall, color = C.green, bold = true })
		local shop = state.monetization
		local any = false
		for _, p in shop.passes do
			any = true
			K.button(c, T(p.nameKey), function()
				MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, p.id)
			end, { name = "Pass_" .. p.key, style = "gold" })
			K.label(c, T(p.descKey), { size = S.textSmall, color = C.textDim })
		end
		for _, p in shop.products do
			any = true
			K.button(c, T(p.nameKey), function()
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, p.id)
			end, { name = "Product_" .. p.key, style = "gold" })
			K.label(c, T(p.descKey), { size = S.textSmall, color = C.textDim })
		end
		if not any then
			K.label(c, T("menu.shop.empty"), { size = S.text, color = C.textDim })
		end
	end

	local function render()
		if scroll == nil or not scroll.Parent then
			return
		end
		local state = ctx.store.state
		if state == nil then
			return
		end
		K.clear(scroll)
		renderDaily(state)
		renderSettings(state)
		renderTitles(state)
		renderStats(state)
		renderCosmetics(state)
		renderShop(state)
	end

	ctx.windows:register("menu", {
		title = function()
			return "☰ " .. T("menu.title")
		end,
		build = function(body, window)
			scroll = K.scroll(body, { name = "MenuScroll" })
			render()
			local accum = 0
			window.conn = RunService.Heartbeat:Connect(function(dt)
				accum += dt
				if accum >= 1 and ctx.refreshDaily then
					accum = 0
					ctx.refreshDaily()
				end
			end)
		end,
		refresh = render,
		onClose = function(window)
			if window.conn then
				window.conn:Disconnect()
			end
			scroll = nil
			dailyLabel, dailyButton = nil, nil
		end,
	})
end

return MenuPanel
