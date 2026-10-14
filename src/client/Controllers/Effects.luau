--!nonstrict
--[[
	Efectos y "jugo": sonidos, números flotantes, banners de adquisición y confeti. Son sólo
	presentación y se pueden desactivar en el menú. Se mantienen baratos: pocos elementos, tweens
	cortos y limpieza inmediata.
]]

local Debris = game:GetService("Debris")

local Effects = {}
Effects.__index = Effects

local CONFETTI_COLORS = {
	Color3.fromRGB(255, 202, 84),
	Color3.fromRGB(86, 224, 146),
	Color3.fromRGB(64, 212, 255),
	Color3.fromRGB(255, 100, 140),
	Color3.fromRGB(190, 110, 255),
}

function Effects.new(ctx)
	local self = setmetatable({ ctx = ctx, _rng = Random.new() }, Effects)
	local K = ctx.kit
	self.layer = K.frame(ctx.layers.fx, { name = "FX", size = UDim2.fromScale(1, 1) })
	self.layer.Active = false
	return self
end

function Effects:sound(name)
	local ctx = self.ctx
	local state = ctx.store.state
	if state and state.settings and state.settings.sfx == false then
		return
	end
	local id = ctx.theme.sounds[name]
	if id == nil then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = 0.45
	sound.Parent = self.layer
	sound:Play()
	Debris:AddItem(sound, 4)
end

-- Número que sube y se desvanece (p. ej. "+1,25 K $").
function Effects:popup(text, color, position)
	local ctx = self.ctx
	local K = ctx.kit
	local label = K.label(self.layer, text, {
		name = "Popup",
		bold = true,
		size = ctx.theme.sizes.textBig,
		color = color or ctx.theme.colors.green,
		align = "left",
		height = 28,
		size2 = UDim2.fromOffset(200, 28),
		position = position or UDim2.fromOffset(24, 138),
	})
	label.TextStrokeTransparency = 0.5
	K.tween(label, 1.1, {
		Position = label.Position - UDim2.fromOffset(0, 46),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	Debris:AddItem(label, 1.3)
end

function Effects:confetti(count)
	local K = self.ctx.kit
	for _ = 1, count or 28 do
		local piece = Instance.new("Frame")
		piece.Name = "Confetti"
		piece.BorderSizePixel = 0
		piece.BackgroundColor3 = CONFETTI_COLORS[self._rng:NextInteger(1, #CONFETTI_COLORS)]
		local size = self._rng:NextInteger(6, 11)
		piece.Size = UDim2.fromOffset(size, size)
		local x = self._rng:NextNumber()
		piece.Position = UDim2.new(x, 0, 0, -20)
		piece.Rotation = self._rng:NextInteger(0, 360)
		piece.Parent = self.layer
		K.tween(piece, 1.4 + self._rng:NextNumber() * 1.1, {
			Position = UDim2.new(math.clamp(x + (self._rng:NextNumber() - 0.5) * 0.25, 0, 1), 0, 1, 20),
			Rotation = piece.Rotation + self._rng:NextInteger(-300, 300),
			BackgroundTransparency = 0.6,
		})
		Debris:AddItem(piece, 3)
	end
end

-- Banner grande y compartible: tomas de control, nuevo número uno, nuevo magnate...
function Effects:banner(text, color)
	local ctx = self.ctx
	local K = ctx.kit
	local C = ctx.theme.colors
	local card = K.card(self.layer, {
		name = "Banner",
		size = UDim2.new(0.9, 0, 0, 0),
		autoY = true,
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, -90),
		color = C.surface,
		strokeColor = color or C.gold,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(520, 200)
	limit.Parent = card
	K.stroke(card, color or C.gold, 3)
	K.label(
		card,
		text,
		{ bold = true, size = ctx.theme.sizes.textBig, align = "center", name = "BannerText" }
	)
	K.tween(card, 0.45, { Position = UDim2.new(0.5, 0, 0, 190) })
	task.delay(4.5, function()
		if card.Parent then
			K.tween(card, 0.4, { Position = UDim2.new(0.5, 0, 0, -120) })
			Debris:AddItem(card, 0.6)
		end
	end)
end

-- Mensajes públicos del servidor (efectos de interés social).
function Effects:handlePublic(message)
	local ctx = self.ctx
	local T = ctx.T
	local kind = message.kind
	local text = T("fx." .. tostring(kind), { who = message.who, company = message.company })
	if kind == "takeover" or kind == "deal" then
		self:banner(text, ctx.theme.colors.gold)
		self:confetti(message.effect == "fx_golden" and 60 or 34)
		self:sound("deal")
	elseif kind == "new_number_one" or kind == "new_magnate" then
		self:banner(text, ctx.theme.colors.accent)
		self:confetti(24)
		self:sound("deal")
	end
end

return Effects
