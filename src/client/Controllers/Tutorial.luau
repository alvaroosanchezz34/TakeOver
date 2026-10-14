--!nonstrict
--[[
	Tutorial contextual: una tarjeta breve con el siguiente paso, sin pausar el juego y omitible.
	Avanza cuando el SERVIDOR confirma que el jugador hizo la acción real; aquí sólo se muestra.
	Además resalta con un borde pulsante el botón que toca usar.
]]

local Tutorial = {}
Tutorial.__index = Tutorial

function Tutorial.new(ctx, hud)
	local self = setmetatable({ ctx = ctx, hud = hud }, Tutorial)
	local K = ctx.kit
	local C = ctx.theme.colors
	local S = ctx.theme.sizes

	local card = K.card(ctx.layers.hud, {
		name = "TutorialCard",
		size = UDim2.new(0, 250, 0, 0),
		autoY = true,
		position = UDim2.fromOffset(12, 156),
		color = C.surface2,
		strokeColor = C.accent,
	})
	K.layout(card, { gap = 6 })
	self.card = card
	self.title = K.label(
		card,
		"",
		{ bold = true, size = S.text, color = C.accent, height = 20, name = "TutorialTitle" }
	)
	self.text = K.label(card, "", { size = S.text - 1, name = "TutorialText" })
	self.progress = K.progress(card, 0, C.accent, 6)
	self.skip = K.button(card, ctx.T("tutorial.skip"), function()
		ctx.run("SkipTutorial", nil, { button = self.skip })
	end, { name = "SkipTutorial", style = "ghost", size = UDim2.new(1, 0, 0, 40), textSize = S.textSmall })
	return self
end

function Tutorial:relayout()
	self.card.Size = UDim2.new(0, self.ctx.compact() and 190 or 250, 0, 0)
end

function Tutorial:render()
	local ctx = self.ctx
	local state = ctx.store.state
	local tut = state and state.tutorial
	local active = tut ~= nil and not tut.done and not tut.skipped
	self.card.Visible = active
	-- Quitar resaltados anteriores
	self.hud:setPulse(self.hud.buyButton, false)
	self.hud:setPulse(self.hud.navMarket, false)
	if not active then
		return
	end
	self.title.Text = ctx.T("tutorial.title")
		.. " · "
		.. ctx.T("tutorial.step", { n = math.min(tut.step, tut.total), total = tut.total })
	self.text.Text = ctx.T("tutorial." .. tostring(tut.stepId))
	ctx.kit.setProgress(self.progress, (tut.step - 1) / tut.total)
	if tut.stepId == "buy_upgrade" then
		self.hud:setPulse(self.hud.buyButton, true)
	elseif tut.stepId == "open_market" then
		self.hud:setPulse(self.hud.navMarket, true)
	end
end

return Tutorial
