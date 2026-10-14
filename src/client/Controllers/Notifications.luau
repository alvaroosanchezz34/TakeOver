--!nonstrict
--[[
	Notificaciones económicas y sociales. El servidor manda un `kind` y parámetros; aquí se
	traducen a texto localizado con su estilo y sonido. `describe` es una función pura (se prueba
	sin Roblox); `Notifications.new` pinta los avisos apilados (toasts) en pantalla.
]]

local Notifications = {}
Notifications.__index = Notifications

local STYLE_COLORS = { info = "accent", good = "green", warn = "warn", bad = "red", gold = "gold" }

--[[
	Devuelve (texto, estilo, sonido, destino).
	destino: ventana/pestaña a abrir al tocar el aviso (opcional).
]]
function Notifications.describe(ctx, kind, p)
	local T = ctx.T
	p = p or {}
	local function evName(id)
		return T("event." .. tostring(id))
	end

	if kind == "offer_received" then
		return T(
			"notify.offer_received",
			{ from = p.from, company = p.company, bps = ctx.bps(p.bps), price = ctx.cash(p.price) }
		),
			"gold",
			"notify",
			{ window = "market", tab = "offers" }
	elseif kind == "offer_accepted" then
		return T(
			"notify.offer_accepted",
			{ seller = p.seller, company = p.company, bps = ctx.bps(p.bps), price = ctx.cash(p.price) }
		),
			"good",
			"deal",
			nil
	elseif kind == "offer_rejected" then
		return T("notify.offer_rejected", { seller = p.seller, company = p.company }), "warn", "error", nil
	elseif kind == "offer_cancelled" then
		return T("notify.offer_cancelled"), "warn", "notify", nil
	elseif kind == "offer_expired" then
		return T("notify.offer_expired", { company = p.company }), "warn", "notify", nil
	elseif kind == "offer_failed" then
		return T("notify.offer_failed") .. " — " .. ctx.errText(p.code, p), "bad", "error", nil
	elseif kind == "deal_closed" then
		return T(
			"notify.deal_closed",
			{ buyer = p.buyer, company = p.company, bps = ctx.bps(p.bps), received = ctx.cash(p.received) }
		),
			"good",
			"deal",
			nil
	elseif kind == "control_gained" then
		return T("notify.control_gained", { company = p.company }), "gold", "deal", { window = "company" }
	elseif kind == "control_lost" then
		return T("notify.control_lost", { company = p.company }), "warn", "notify", nil
	elseif kind == "alliance_invite" then
		return T("notify.alliance_invite", { from = p.from }),
			"info",
			"notify",
			{ window = "market", tab = "people" }
	elseif kind == "alliance_joined" then
		return T("notify.alliance_joined", { name = p.name }), "good", "notify", nil
	elseif kind == "alliance_left" then
		return T("notify.alliance_left", { name = p.name }), "warn", "notify", nil
	elseif kind == "event_announce" then
		return T("notify.event_announce", { name = evName(p.id), time = ctx.duration(p.seconds or 0) }),
			"info",
			"notify",
			nil
	elseif kind == "event_start" then
		return T("notify.event_start", { name = evName(p.id) }), "gold", "notify", nil
	elseif kind == "event_end" then
		return T("notify.event_end", { name = evName(p.id) }), "info", nil, nil
	elseif kind == "achievement" then
		return T("notify.achievement", { name = T("ach." .. tostring(p.id)) }), "gold", "deal", nil
	elseif kind == "tutorial_done" then
		return T("notify.tutorial_done", { reward = ctx.cash(p.reward or 0) }), "good", "deal", nil
	elseif kind == "daily_claimed" then
		return T("notify.daily_claimed", { reward = ctx.cash(p.reward or 0), streak = p.streak or 1 }),
			"good",
			"cash",
			nil
	elseif kind == "market_liquidation" then
		return T("notify.market_liquidation", { cash = ctx.cash(p.cash or 0) }), "warn", "notify", nil
	elseif kind == "rank_up" then
		return T("notify.rank_up", { badge = T("rank." .. tostring(p.badge)) }), "gold", "deal", nil
	elseif kind == "purchase_done" then
		return T("notify.purchase_done"), "good", "deal", nil
	end
	return nil
end

function Notifications.new(ctx)
	local self = setmetatable({ ctx = ctx, _items = {} }, Notifications)
	local K = ctx.kit
	local container = K.frame(ctx.layers.toasts, {
		name = "ToastStack",
		size = UDim2.new(0.94, 0, 0, 0),
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 150),
		autoY = true,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(460, 600)
	limit.Parent = container
	K.layout(container, { gap = 6 })
	self.container = container
	self.maxVisible = 4
	return self
end

function Notifications:show(text, style, onTap)
	local ctx = self.ctx
	local K = ctx.kit
	local C = ctx.theme.colors
	local color = C[STYLE_COLORS[style or "info"] or "accent"]

	while #self._items >= self.maxVisible do
		local old = table.remove(self._items, 1)
		if old and old.Parent then
			old:Destroy()
		end
	end

	-- Un aviso es un botón (se puede tocar para descartarlo o ir a su destino).
	local toast
	toast = K.button(self.container, "", function()
		if onTap then
			onTap()
		end
		if self._items and table.find(self._items, toast) then
			table.remove(self._items, table.find(self._items, toast))
		end
		toast:Destroy()
	end, { name = "Toast", style = "ghost", size = UDim2.new(1, 0, 0, 0) })
	toast.AutomaticSize = Enum.AutomaticSize.Y
	toast.Text = ""
	toast.BackgroundColor3 = C.surface
	K.stroke(toast, color, 2)
	K.padding(toast, 10)
	local label = K.label(toast, text, { size = ctx.theme.sizes.text, color = C.text, name = "ToastText" })
	label.TextXAlignment = Enum.TextXAlignment.Left
	table.insert(self._items, toast)

	task.delay(5, function()
		if toast.Parent then
			local idx = table.find(self._items, toast)
			if idx then
				table.remove(self._items, idx)
			end
			toast:Destroy()
		end
	end)
	return toast
end

-- Muestra la notificación de un `kind` del servidor y la guarda en la bandeja.
function Notifications:handle(kind, params)
	local ctx = self.ctx
	local text, style, sound, target = Notifications.describe(ctx, kind, params)
	if text == nil then
		return
	end
	ctx.store:pushNotification({ text = text, style = style, kind = kind, t = os.time() })
	if sound then
		ctx.sfx(sound)
	end
	self:show(text, style, target and function()
		ctx.openWindow(target.window, target)
	end or nil)
end

return Notifications
