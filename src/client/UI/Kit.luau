--!nonstrict
--[[
	Componentes de interfaz reutilizables. Reglas que cumplen todos:
	  - objetivos táctiles ≥ 48 px de alto,
	  - todo botón EXIGE un manejador (si no, assert: no existen botones decorativos),
	  - texto con contraste suficiente sobre las superficies del tema,
	  - sin dependencias de assets: sólo texto, emojis y formas.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local C = Theme.colors
local S = Theme.sizes

local Kit = {}

-- Gancho opcional (lo asigna App): sonido al pulsar cualquier botón.
Kit.onClickSound = nil :: (() -> ())?

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or S.radius)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color or C.stroke
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function padding(parent, all, vertical)
	local p = Instance.new("UIPadding")
	local h = all or S.pad
	local v = vertical or h
	p.PaddingLeft = UDim.new(0, h)
	p.PaddingRight = UDim.new(0, h)
	p.PaddingTop = UDim.new(0, v)
	p.PaddingBottom = UDim.new(0, v)
	p.Parent = parent
	return p
end

Kit.corner = corner
Kit.stroke = stroke
Kit.padding = padding

local ALIGN = {
	left = Enum.TextXAlignment.Left,
	center = Enum.TextXAlignment.Center,
	right = Enum.TextXAlignment.Right,
}

-- Contenedor sin fondo.
function Kit.frame(parent, props)
	props = props or {}
	local f = Instance.new("Frame")
	f.Name = props.name or "Frame"
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = props.size or UDim2.fromScale(1, 1)
	if props.position then
		f.Position = props.position
	end
	if props.anchor then
		f.AnchorPoint = props.anchor
	end
	if props.autoY then
		f.AutomaticSize = Enum.AutomaticSize.Y
	end
	if props.layoutOrder then
		f.LayoutOrder = props.layoutOrder
	end
	f.Parent = parent
	return f
end

-- Tarjeta con fondo, esquinas y borde.
function Kit.card(parent, props)
	props = props or {}
	local f = Instance.new("Frame")
	f.Name = props.name or "Card"
	f.BackgroundColor3 = props.color or C.surface
	f.BackgroundTransparency = props.transparency or 0
	f.BorderSizePixel = 0
	f.Size = props.size or UDim2.new(1, 0, 0, 0)
	if props.autoY ~= false and (props.size == nil or props.autoY) then
		f.AutomaticSize = Enum.AutomaticSize.Y
	end
	if props.position then
		f.Position = props.position
	end
	if props.anchor then
		f.AnchorPoint = props.anchor
	end
	if props.layoutOrder then
		f.LayoutOrder = props.layoutOrder
	end
	corner(f, props.radius)
	if props.stroke ~= false then
		stroke(f, props.strokeColor)
	end
	if props.pad ~= false then
		padding(f, props.pad)
	end
	f.Parent = parent
	return f
end

-- Disposición vertical u horizontal.
function Kit.layout(parent, props)
	props = props or {}
	local l = Instance.new("UIListLayout")
	l.FillDirection = props.horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, props.gap or S.gap)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = props.hAlign or Enum.HorizontalAlignment.Left
	l.VerticalAlignment = props.vAlign or Enum.VerticalAlignment.Top
	l.Parent = parent
	return l
end

-- Pila: Frame con layout y tamaño automático en vertical.
function Kit.stack(parent, props)
	props = props or {}
	local f = Kit.frame(parent, {
		name = props.name or "Stack",
		size = props.size or UDim2.new(1, 0, 0, 0),
		position = props.position,
		anchor = props.anchor,
		layoutOrder = props.layoutOrder,
		autoY = not props.horizontal,
	})
	if props.horizontal then
		f.AutomaticSize = props.fixedHeight and Enum.AutomaticSize.None or Enum.AutomaticSize.Y
	end
	Kit.layout(f, props)
	return f
end

function Kit.label(parent, text, props)
	props = props or {}
	local l = Instance.new("TextLabel")
	l.Name = props.name or "Label"
	l.BackgroundTransparency = 1
	l.Text = text or ""
	l.Font = props.font or (props.bold and Theme.fonts.title or Theme.fonts.body)
	l.TextSize = props.size or S.text
	l.TextColor3 = props.color or C.text
	l.TextXAlignment = ALIGN[props.align or "left"]
	l.TextYAlignment = props.vAlign or Enum.TextYAlignment.Center
	l.TextWrapped = props.wrap ~= false
	l.RichText = props.rich == true
	l.BorderSizePixel = 0
	if props.height then
		l.Size = props.size2 or UDim2.new(props.width or 1, 0, 0, props.height)
	else
		l.Size = props.size2 or UDim2.new(1, 0, 0, 0)
		l.AutomaticSize = Enum.AutomaticSize.Y
	end
	if props.width and not props.size2 and not props.height then
		l.Size = UDim2.new(props.width, 0, 0, 0)
	end
	if props.position then
		l.Position = props.position
	end
	if props.anchor then
		l.AnchorPoint = props.anchor
	end
	if props.layoutOrder then
		l.LayoutOrder = props.layoutOrder
	end
	l.Parent = parent
	return l
end

local STYLES = {
	primary = { bg = C.accent, fg = C.bg, hover = Color3.fromRGB(120, 228, 255) },
	secondary = { bg = C.surface3, fg = C.text, hover = Color3.fromRGB(62, 74, 112) },
	success = { bg = C.green, fg = C.bg, hover = Color3.fromRGB(130, 238, 178) },
	danger = { bg = C.red, fg = C.bg, hover = Color3.fromRGB(255, 140, 140) },
	gold = { bg = C.gold, fg = C.bg, hover = Color3.fromRGB(255, 220, 130) },
	ghost = { bg = C.surface, fg = C.text, hover = C.surface3 },
}

--[[
	Botón. `onClick` es OBLIGATORIO. opts: style, size (UDim2), icon, layoutOrder, textSize.
	Devuelve el TextButton; usa Kit.setEnabled / Kit.setBusy para estados.
]]
function Kit.button(parent, text, onClick, opts)
	assert(type(onClick) == "function", "Kit.button: onClick es obligatorio (no hay botones sin función)")
	opts = opts or {}
	local style = STYLES[opts.style or "secondary"] or STYLES.secondary
	local b = Instance.new("TextButton")
	b.Name = opts.name or "Button"
	b.AutoButtonColor = false
	b.BackgroundColor3 = style.bg
	b.TextColor3 = style.fg
	b.Font = Theme.fonts.title
	b.TextSize = opts.textSize or S.text
	b.Text = (opts.icon and (opts.icon .. "  ") or "") .. text
	b.TextWrapped = true
	b.BorderSizePixel = 0
	b.Size = opts.size or UDim2.new(1, 0, 0, S.touch)
	if opts.layoutOrder then
		b.LayoutOrder = opts.layoutOrder
	end
	if opts.position then
		b.Position = opts.position
	end
	if opts.anchor then
		b.AnchorPoint = opts.anchor
	end
	corner(b)
	-- Los botones seleccionables funcionan con mando.
	b.Selectable = true

	-- Estado visual (hover/pulsado/deshabilitado). Se guarda en atributos para poder consultarlo.
	b:SetAttribute("Style", opts.style or "secondary")
	b:SetAttribute("Enabled", true)

	b.MouseEnter:Connect(function()
		if b:GetAttribute("Enabled") then
			b.BackgroundColor3 = style.hover
		end
	end)
	b.MouseLeave:Connect(function()
		if b:GetAttribute("Enabled") then
			b.BackgroundColor3 = style.bg
		end
	end)
	b.Activated:Connect(function()
		if not b:GetAttribute("Enabled") then
			return
		end
		if Kit.onClickSound then
			Kit.onClickSound()
		end
		onClick()
	end)
	b.Parent = parent
	return b
end

function Kit.setEnabled(button, enabled)
	button:SetAttribute("Enabled", enabled)
	local styleName = button:GetAttribute("Style") or "secondary"
	local style = STYLES[styleName] or STYLES.secondary
	if enabled then
		button.BackgroundColor3 = style.bg
		button.TextTransparency = 0
	else
		button.BackgroundColor3 = C.surface2
		button.TextTransparency = 0.45
	end
end

-- Estado "cargando": bloquea pulsaciones repetidas mientras el servidor responde.
function Kit.setBusy(button, busy, idleText)
	if busy then
		button:SetAttribute("IdleText", button.Text)
		button.Text = "…"
		Kit.setEnabled(button, false)
	else
		button.Text = idleText or button:GetAttribute("IdleText") or button.Text
		Kit.setEnabled(button, true)
	end
end

function Kit.chip(parent, text, color, textColor)
	local f = Instance.new("TextLabel")
	f.Name = "Chip"
	f.AutomaticSize = Enum.AutomaticSize.XY
	f.Size = UDim2.new(0, 0, 0, 24)
	f.BackgroundColor3 = color or C.surface3
	f.TextColor3 = textColor or C.text
	f.Font = Theme.fonts.title
	f.TextSize = S.textSmall
	f.Text = text
	f.BorderSizePixel = 0
	corner(f, 12)
	padding(f, 8, 2)
	f.Parent = parent
	return f
end

function Kit.progress(parent, ratio, color, height)
	local track = Instance.new("Frame")
	track.Name = "Progress"
	track.BackgroundColor3 = C.surface3
	track.BorderSizePixel = 0
	track.Size = UDim2.new(1, 0, 0, height or 8)
	corner(track, 6)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = color or C.accent
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(math.clamp(ratio or 0, 0, 1), 1)
	corner(fill, 6)
	fill.Parent = track
	track.Parent = parent
	return track
end

function Kit.setProgress(track, ratio)
	local fill = track:FindFirstChild("Fill")
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(ratio or 0, 0, 1), 1)
	end
end

function Kit.divider(parent, layoutOrder)
	local d = Instance.new("Frame")
	d.Name = "Divider"
	d.BackgroundColor3 = C.stroke
	d.BackgroundTransparency = 0.4
	d.BorderSizePixel = 0
	d.Size = UDim2.new(1, 0, 0, 1)
	if layoutOrder then
		d.LayoutOrder = layoutOrder
	end
	d.Parent = parent
	return d
end

-- Lista desplazable con tamaño de contenido automático.
function Kit.scroll(parent, props)
	props = props or {}
	local s = Instance.new("ScrollingFrame")
	s.Name = props.name or "Scroll"
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.Size = props.size or UDim2.fromScale(1, 1)
	if props.position then
		s.Position = props.position
	end
	s.CanvasSize = UDim2.new(0, 0, 0, 0)
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.ScrollBarThickness = 5
	s.ScrollBarImageColor3 = C.stroke
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	s.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	Kit.layout(s, { gap = props.gap or S.gap })
	if props.pad ~= false then
		local p = Instance.new("UIPadding")
		p.PaddingRight = UDim.new(0, 8)
		p.PaddingBottom = UDim.new(0, 8)
		p.Parent = s
	end
	s.Parent = parent
	return s
end

-- Borra el contenido de un contenedor conservando sus layouts/paddings.
function Kit.clear(container)
	for _, child in container:GetChildren() do
		if
			not (
				child:IsA("UIListLayout")
				or child:IsA("UIPadding")
				or child:IsA("UICorner")
				or child:IsA("UIStroke")
			)
		then
			child:Destroy()
		end
	end
end

--[[
	Selector numérico con − / +. Devuelve un objeto con :set(v) y :get().
	format(v) -> texto mostrado.
]]
function Kit.stepper(parent, props)
	local value = props.value
	local row = Kit.frame(
		parent,
		{ name = "Stepper", size = UDim2.new(1, 0, 0, S.touch), layoutOrder = props.layoutOrder }
	)
	Kit.layout(row, { horizontal = true, gap = 6, vAlign = Enum.VerticalAlignment.Center })
	local display
	local obj = {}
	local function refresh()
		display.Text = props.format(value)
		if props.onChange then
			props.onChange(value)
		end
	end
	local function change(delta)
		local nv = math.clamp(value + delta, props.min, props.max)
		if nv ~= value then
			value = nv
			refresh()
		end
	end
	Kit.button(row, "−", function()
		change(-props.step)
	end, { size = UDim2.new(0, S.touch, 0, S.touch), textSize = 24, name = "Minus" })
	display = Kit.label(row, props.format(value), {
		bold = true,
		align = "center",
		height = S.touch,
		size = S.textBig,
		size2 = UDim2.new(1, -(S.touch * 2 + 12), 0, S.touch),
		name = "Value",
	})
	Kit.button(row, "+", function()
		change(props.step)
	end, { size = UDim2.new(0, S.touch, 0, S.touch), textSize = 24, name = "Plus" })
	function obj.set(v)
		value = math.clamp(v, props.min, props.max)
		display.Text = props.format(value)
		if props.onChange then
			props.onChange(value)
		end
	end
	function obj.get()
		return value
	end
	function obj.setRange(min, max)
		props.min, props.max = min, max
		value = math.clamp(value, min, max)
		display.Text = props.format(value)
	end
	obj.frame = row
	return obj
end

-- Pestañas: devuelve { select(id), bar }. tabs = { {id=, text=} }.
function Kit.tabs(parent, tabs, onSelect, layoutOrder)
	local bar = Kit.frame(parent, { name = "Tabs", size = UDim2.new(1, 0, 0, 44), layoutOrder = layoutOrder })
	Kit.layout(bar, { horizontal = true, gap = 6 })
	local buttons = {}
	local current
	local function select(id)
		current = id
		for tid, b in buttons do
			local active = tid == id
			b.BackgroundColor3 = active and C.accent or C.surface3
			b.TextColor3 = active and C.bg or C.text
		end
		onSelect(id)
	end
	for _, tab in tabs do
		local b = Kit.button(bar, tab.text, function()
			select(tab.id)
		end, {
			size = UDim2.new(1 / #tabs, -6, 0, 44),
			textSize = S.textSmall + 1,
			name = "Tab_" .. tab.id,
		})
		buttons[tab.id] = b
	end
	return {
		select = select,
		bar = bar,
		buttons = buttons,
		current = function()
			return current
		end,
		setText = function(id, text)
			if buttons[id] then
				buttons[id].Text = text
			end
		end,
	}
end

function Kit.tween(instance, seconds, goal)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		goal
	)
	tween:Play()
	return tween
end

return Kit
