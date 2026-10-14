--!nonstrict
--[[
	Adaptación a PC, tablet y móvil. Una interfaz diseñada para 1280×720 se escala con UIScale
	según el área visible; en pantallas estrechas (móvil vertical) se pasa a modo compacto:
	ventanas a pantalla casi completa, controles apilados y tipografía algo menor.
]]

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Responsive = {}

Responsive.DESIGN = Vector2.new(1280, 720)
Responsive.MIN_SCALE = 0.62
Responsive.MAX_SCALE = 1.25
Responsive.COMPACT_WIDTH = 760 -- por debajo (tras escalar) se considera pantalla estrecha

-- Escala para un viewport dado (función pura: se prueba sin Roblox).
function Responsive.scaleFor(width: number, height: number): number
	local sx = width / Responsive.DESIGN.X
	local sy = height / Responsive.DESIGN.Y
	-- Se escala por el lado más ajustado, con límites razonables.
	local s = math.min(sx, sy)
	if width < Responsive.COMPACT_WIDTH then
		-- En vertical manda el ancho: el diseño compacto parte de 420 px.
		s = math.min(width / 420, height / 760)
	end
	return math.clamp(s, Responsive.MIN_SCALE, Responsive.MAX_SCALE)
end

function Responsive.isCompact(width: number): boolean
	return width < Responsive.COMPACT_WIDTH
end

-- Viewport actual (cámara) o un valor por defecto si aún no está disponible.
function Responsive.viewport(): Vector2
	local camera = Workspace.CurrentCamera
	if camera and camera.ViewportSize.X > 0 then
		return camera.ViewportSize
	end
	return Responsive.DESIGN
end

function Responsive.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Aplica la escala a un UIScale y devuelve si el modo es compacto.
function Responsive.apply(uiScale: UIScale): boolean
	local v = Responsive.viewport()
	uiScale.Scale = Responsive.scaleFor(v.X, v.Y)
	-- Ancho "lógico" tras escalar: lo que ve el layout.
	return Responsive.isCompact(v.X / uiScale.Scale)
end

return Responsive
