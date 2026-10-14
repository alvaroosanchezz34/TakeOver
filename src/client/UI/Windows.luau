--!nonstrict
--[[
	Gestor de ventanas. Reglas:
	  - Sólo una ventana principal abierta a la vez.
	  - TODA ventana tiene botón de cerrar visible (48 px) y se cierra tocando fuera: ninguna
	    interfaz puede bloquear el juego de forma permanente.
	  - En pantallas estrechas (móvil) ocupan casi toda la pantalla; en PC, un panel centrado.
]]

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)

local C = Theme.colors
local S = Theme.sizes

local Windows = {}
Windows.__index = Windows

function Windows.new(layer, getCompact)
	return setmetatable({ _layer = layer, _getCompact = getCompact, _open = nil, _defs = {} }, Windows)
end

-- def: { title = function() -> string, build = function(body, window), onClose? }
function Windows.register(self, id, def)
	self._defs[id] = def
end

function Windows.isOpen(self, id)
	return self._open ~= nil and (id == nil or self._open.id == id)
end

function Windows.current(self)
	return self._open and self._open.id
end

function Windows.close(self)
	local open = self._open
	if open == nil then
		return
	end
	self._open = nil
	if open.def.onClose then
		pcall(open.def.onClose, open)
	end
	open.root:Destroy()
end

function Windows.open(self, id, args)
	local def = self._defs[id]
	assert(def, "ventana no registrada: " .. tostring(id))
	if self._open then
		self:close()
	end

	local compact = self._getCompact()
	local root = Instance.new("Frame")
	root.Name = "Window_" .. id
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = self._layer

	-- Fondo atenuado: tocarlo cierra la ventana.
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.BackgroundColor3 = C.black
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.Parent = root
	dim.Activated:Connect(function()
		self:close()
	end)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = C.bg
	panel.BorderSizePixel = 0
	panel.Active = true -- absorbe los toques: no cierran la ventana
	if compact then
		panel.Size = UDim2.new(0.96, 0, 0.94, 0)
	else
		panel.Size = UDim2.new(0.62, 0, 0.82, 0)
		local limit = Instance.new("UISizeConstraint")
		limit.MaxSize = Vector2.new(820, 620)
		limit.MinSize = Vector2.new(520, 360)
		limit.Parent = panel
	end
	Kit.corner(panel, 16)
	Kit.stroke(panel, C.stroke, 1.5)
	panel.Parent = root

	-- Cabecera: título + cerrar
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundColor3 = C.surface
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, 60)
	Kit.corner(header, 16)
	header.Parent = panel
	local title = Kit.label(header, def.title(args), {
		name = "Title",
		bold = true,
		size = S.textBig,
		height = 60,
		size2 = UDim2.new(1, -80, 1, 0),
		position = UDim2.fromOffset(16, 0),
	})
	Kit.button(header, "✕", function()
		self:close()
	end, {
		name = "Close",
		style = "secondary",
		size = UDim2.new(0, S.touch, 0, S.touch),
		position = UDim2.new(1, -(S.touch + 8), 0, 6),
		textSize = 22,
	})

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(0, 64)
	body.Size = UDim2.new(1, 0, 1, -64)
	Kit.padding(body, 12)
	body.Parent = panel

	local window = {
		id = id,
		def = def,
		root = root,
		body = body,
		title = title,
		args = args,
		compact = compact,
	}
	self._open = window
	def.build(body, window)
	return window
end

-- Redibuja el contenido de la ventana abierta (p. ej. al llegar un estado nuevo).
function Windows.refresh(self, id)
	local open = self._open
	if open == nil or (id ~= nil and open.id ~= id) then
		return
	end
	if open.def.refresh then
		open.def.refresh(open.body, open)
	end
	if open.def.title then
		open.title.Text = open.def.title(open.args)
	end
end

return Windows
