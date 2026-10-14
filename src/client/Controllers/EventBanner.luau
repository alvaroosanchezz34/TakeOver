--!nonstrict
--[[
	Banner del evento económico: qué evento está activo (con su regla y cuenta atrás) o cuál
	viene y cuándo. Los eventos son PREDECIBLES: siempre se anuncian con antelación.
]]

local EventBanner = {}
EventBanner.__index = EventBanner

function EventBanner.new(ctx)
	local self = setmetatable({ ctx = ctx, _accum = 0 }, EventBanner)
	local K = ctx.kit
	local C = ctx.theme.colors
	local S = ctx.theme.sizes

	local card = K.card(ctx.layers.hud, {
		name = "EventBanner",
		size = UDim2.new(0, 330, 0, 0),
		autoY = true,
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 8),
		color = C.surface2,
		strokeColor = C.gold,
	})
	K.layout(card, { gap = 2 })
	self.card = card
	self.title = K.label(
		card,
		"",
		{ bold = true, size = S.text, color = C.gold, height = 20, align = "center", name = "EventTitle" }
	)
	self.desc =
		K.label(card, "", { size = S.textSmall, color = C.textDim, align = "center", name = "EventDesc" })
	card.Visible = false
	self.RunService = game:GetService("RunService")
	self._conn = self.RunService.Heartbeat:Connect(function(dt)
		self._accum += dt
		if self._accum >= 0.5 then
			self._accum = 0
			self:render()
		end
	end)
	return self
end

function EventBanner:relayout()
	local compact = self.ctx.compact()
	self.card.Size = UDim2.new(0, compact and 280 or 330, 0, 0)
	self.card.Position = compact and UDim2.new(0.5, 0, 0, 150) or UDim2.new(0.5, 0, 0, 8)
end

function EventBanner:render()
	local ctx = self.ctx
	local mode, seconds, info = ctx.store:eventRemaining()
	if mode == nil or mode == "none" then
		self.card.Visible = false
		return
	end
	self.card.Visible = true
	local T = ctx.T
	if mode == "active" then
		self.title.Text = info.icon
			.. "  "
			.. T("event.active", { name = T("event." .. info.id), time = ctx.duration(seconds) })
		self.desc.Text = T("event." .. info.id .. ".desc")
	else
		local name = T("event." .. info.nextId)
		self.title.Text = "⏳  "
			.. T("event.next", { name = name })
			.. " · "
			.. T("event.starts_in", { time = ctx.duration(seconds) })
		self.desc.Text = T("event." .. info.nextId .. ".desc")
	end
end

function EventBanner:destroy()
	if self._conn then
		self._conn:Disconnect()
	end
end

return EventBanner
