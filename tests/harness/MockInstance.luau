--!nocheck
--[[
	Simulador mínimo de Instance + tipos de datos + servicios de Roblox, para ejecutar en Lune
	el código de red, mundo e interfaz y cazar errores de EJECUCIÓN (nil, typos, handlers
	ausentes). No simula física, renderizado ni layout: NO sustituye a probar en Studio.
]]

local MockInstance = {}

-- ───────────── Señales ─────────────

local function newSignal()
	local signal = { _handlers = {}, _waiting = {} }
	function signal:Connect(fn)
		local conn = { Connected = true, _fn = fn }
		function conn:Disconnect()
			self.Connected = false
			local idx = table.find(signal._handlers, self)
			if idx then
				table.remove(signal._handlers, idx)
			end
		end
		conn.disconnect = conn.Disconnect
		table.insert(self._handlers, conn)
		return conn
	end
	function signal:Once(fn)
		local conn
		conn = self:Connect(function(...)
			conn:Disconnect()
			fn(...)
		end)
		return conn
	end
	function signal:Wait()
		error("Signal:Wait() no soportado en el simulador", 2)
	end
	function signal:Fire(...)
		for _, conn in table.clone(self._handlers) do
			if conn.Connected then
				conn._fn(...)
			end
		end
	end
	function signal:Count()
		return #self._handlers
	end
	return signal
end
MockInstance.newSignal = newSignal

-- Nombres de eventos conocidos (cualquier otra clave sin definir devuelve nil).
local EVENTS = {}
for _, name in
	{
		"Activated",
		"MouseButton1Click",
		"MouseButton1Down",
		"MouseButton1Up",
		"MouseButton2Click",
		"MouseEnter",
		"MouseLeave",
		"InputBegan",
		"InputEnded",
		"InputChanged",
		"FocusLost",
		"Focused",
		"Changed",
		"ChildAdded",
		"ChildRemoved",
		"DescendantAdded",
		"DescendantRemoving",
		"AncestryChanged",
		"Destroying",
		"Touched",
		"TouchEnded",
		"Triggered",
		"OnServerEvent",
		"OnClientEvent",
		"Completed",
		"Heartbeat",
		"RenderStepped",
		"Stepped",
		"PlayerAdded",
		"PlayerRemoving",
		"CharacterAdded",
		"CharacterRemoving",
		"PromptGamePassPurchaseFinished",
		"PromptProductPurchaseFinished",
		"LastInputTypeChanged",
		"TextChanged",
		"ViewportSizeChanged",
		"Ended",
		"Stopped",
		"Played",
	}
do
	EVENTS[name] = true
end

-- ───────────── Tipos de datos ─────────────

local function vec3(x, y, z)
	local v = { X = x or 0, Y = y or 0, Z = z or 0 }
	v.Magnitude = math.sqrt(v.X ^ 2 + v.Y ^ 2 + v.Z ^ 2)
	return setmetatable(v, {
		__add = function(a, b)
			return vec3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
		end,
		__sub = function(a, b)
			return vec3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
		end,
		__mul = function(a, b)
			if type(a) == "number" then
				a, b = b, a
			end
			if type(b) == "number" then
				return vec3(a.X * b, a.Y * b, a.Z * b)
			end
			return vec3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
		end,
		__div = function(a, b)
			return vec3(a.X / b, a.Y / b, a.Z / b)
		end,
		__unm = function(a)
			return vec3(-a.X, -a.Y, -a.Z)
		end,
		__eq = function(a, b)
			return a.X == b.X and a.Y == b.Y and a.Z == b.Z
		end,
		__tostring = function(a)
			return ("%g, %g, %g"):format(a.X, a.Y, a.Z)
		end,
	})
end

local function vec2(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, {
		__add = function(a, b)
			return vec2(a.X + b.X, a.Y + b.Y)
		end,
		__sub = function(a, b)
			return vec2(a.X - b.X, a.Y - b.Y)
		end,
		__mul = function(a, b)
			if type(a) == "number" then
				a, b = b, a
			end
			if type(b) == "number" then
				return vec2(a.X * b, a.Y * b)
			end
			return vec2(a.X * b.X, a.Y * b.Y)
		end,
		__div = function(a, b)
			return vec2(a.X / b, a.Y / b)
		end,
	})
end

local function cframe(x, y, z)
	local c = { X = x or 0, Y = y or 0, Z = z or 0, Position = vec3(x or 0, y or 0, z or 0) }
	return setmetatable(c, {
		__mul = function(a, b)
			if getmetatable(b) and b.Position and not b.R then
				return cframe(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
			end
			return vec3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
		end,
		__add = function(a, b)
			return cframe(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
		end,
	})
end

local function color3(r, g, b)
	local c = { R = r, G = g, B = b }
	function c.Lerp(self, other, alpha)
		return color3(
			self.R + (other.R - self.R) * alpha,
			self.G + (other.G - self.G) * alpha,
			self.B + (other.B - self.B) * alpha
		)
	end
	function c.ToHSV(self)
		return 0, 0, math.max(self.R, self.G, self.B)
	end
	return c
end

local function udim(scale, offset)
	return { Scale = scale or 0, Offset = offset or 0 }
end

local udim2
local udim2Meta = {
	__add = function(a, b)
		return udim2(
			a.X.Scale + b.X.Scale,
			a.X.Offset + b.X.Offset,
			a.Y.Scale + b.Y.Scale,
			a.Y.Offset + b.Y.Offset
		)
	end,
	__sub = function(a, b)
		return udim2(
			a.X.Scale - b.X.Scale,
			a.X.Offset - b.X.Offset,
			a.Y.Scale - b.Y.Scale,
			a.Y.Offset - b.Y.Offset
		)
	end,
}
function udim2(xs, xo, ys, yo)
	return setmetatable(
		{ X = udim(xs, xo), Y = udim(ys, yo), Width = udim(xs, xo), Height = udim(ys, yo) },
		udim2Meta
	)
end

local function enumItem(enumName, name, value)
	return setmetatable({ Name = name, Value = value or 0, EnumType = enumName }, {
		__tostring = function()
			return "Enum." .. enumName .. "." .. name
		end,
	})
end

local Enum = setmetatable({}, {
	__index = function(self, enumName)
		local items = {}
		local e = setmetatable({}, {
			__index = function(_, itemName)
				if itemName == "GetEnumItems" then
					return function()
						return {}
					end
				end
				local item = items[itemName]
				if item == nil then
					item = enumItem(enumName, itemName, #items)
					items[itemName] = item
				end
				return item
			end,
		})
		rawset(self, enumName, e)
		return e
	end,
})

function MockInstance.datatypes()
	return {
		Vector3 = {
			new = vec3,
			zero = vec3(0, 0, 0),
			one = vec3(1, 1, 1),
			xAxis = vec3(1, 0, 0),
			yAxis = vec3(0, 1, 0),
			zAxis = vec3(0, 0, 1),
		},
		Vector2 = { new = vec2, zero = vec2(0, 0), one = vec2(1, 1) },
		CFrame = {
			new = function(x, y, z)
				if type(x) == "table" then
					return cframe(x.X, x.Y, x.Z)
				end
				return cframe(x, y, z)
			end,
			Angles = function()
				return cframe(0, 0, 0)
			end,
			lookAt = function(from)
				return cframe(from.X, from.Y, from.Z)
			end,
			identity = cframe(0, 0, 0),
		},
		Color3 = {
			new = color3,
			fromRGB = function(r, g, b)
				return color3(r / 255, g / 255, b / 255)
			end,
			fromHSV = function(h, s, v)
				return color3(v, v, v)
			end,
			fromHex = function()
				return color3(0, 0, 0)
			end,
		},
		UDim = { new = udim },
		UDim2 = {
			new = udim2,
			fromScale = function(x, y)
				return udim2(x, 0, y, 0)
			end,
			fromOffset = function(x, y)
				return udim2(0, x, 0, y)
			end,
		},
		Rect = {
			new = function(a, b, c, d)
				return { Min = vec2(a, b), Max = vec2(c, d) }
			end,
		},
		TweenInfo = {
			new = function(time, style, dir)
				return { Time = time, EasingStyle = style, EasingDirection = dir }
			end,
		},
		NumberRange = {
			new = function(a, b)
				return { Min = a, Max = b or a }
			end,
		},
		NumberSequence = {
			new = function(a)
				return { Keypoints = a }
			end,
		},
		NumberSequenceKeypoint = {
			new = function(t, v)
				return { Time = t, Value = v }
			end,
		},
		ColorSequence = {
			new = function(a)
				return { Keypoints = a }
			end,
		},
		ColorSequenceKeypoint = {
			new = function(t, v)
				return { Time = t, Value = v }
			end,
		},
		Font = {
			new = function(family)
				return { Family = family }
			end,
			fromEnum = function(e)
				return { Enum = e }
			end,
		},
		Enum = Enum,
		PhysicalProperties = {
			new = function()
				return {}
			end,
		},
		Region3 = {
			new = function()
				return {}
			end,
		},
	}
end

-- ───────────── Instance ─────────────

local Inst = {}
local methods = {}

local function isA(self, className)
	if className == "Instance" or self.ClassName == className then
		return true
	end
	local alias = {
		GuiObject = {
			Frame = 1,
			TextLabel = 1,
			TextButton = 1,
			ImageLabel = 1,
			ImageButton = 1,
			ScrollingFrame = 1,
			TextBox = 1,
			ViewportFrame = 1,
		},
		GuiButton = { TextButton = 1, ImageButton = 1 },
		LayerCollector = { ScreenGui = 1, SurfaceGui = 1, BillboardGui = 1 },
		BasePart = { Part = 1, MeshPart = 1, WedgePart = 1, TrussPart = 1, SpawnLocation = 1 },
		PVInstance = { Part = 1, Model = 1, MeshPart = 1 },
		ValueBase = { StringValue = 1, IntValue = 1, NumberValue = 1, BoolValue = 1 },
	}
	return alias[className] ~= nil and alias[className][self.ClassName] ~= nil
end

local function fireChanged(self, prop)
	local sigs = rawget(self, "_changedSignals")
	if sigs and sigs[prop] then
		sigs[prop]:Fire()
	end
	local changed = rawget(self, "_signals").Changed
	if changed then
		changed:Fire(prop)
	end
end

local function detach(self)
	local parent = rawget(self, "_parent")
	if parent then
		local list = rawget(parent, "_children")
		local idx = table.find(list, self)
		if idx then
			table.remove(list, idx)
		end
		local sigs = rawget(parent, "_signals")
		if sigs.ChildRemoved then
			sigs.ChildRemoved:Fire(self)
		end
	end
	rawset(self, "_parent", nil)
end

local function attach(self, parent)
	rawset(self, "_parent", parent)
	table.insert(rawget(parent, "_children"), self)
	local sigs = rawget(parent, "_signals")
	if sigs.ChildAdded then
		sigs.ChildAdded:Fire(self)
	end
	local p = parent
	while p do
		local ps = rawget(p, "_signals")
		if ps.DescendantAdded then
			ps.DescendantAdded:Fire(self)
		end
		p = rawget(p, "_parent")
	end
end

Inst.__index = function(self, key)
	if key == "Parent" then
		return rawget(self, "_parent")
	end
	local m = methods[key]
	if m then
		return m
	end
	local props = rawget(self, "_props")
	local value = props[key]
	if value ~= nil then
		return value
	end
	if EVENTS[key] then
		local sigs = rawget(self, "_signals")
		if sigs[key] == nil then
			sigs[key] = newSignal()
		end
		return sigs[key]
	end
	for _, child in rawget(self, "_children") do
		if rawget(child, "_props").Name == key then
			return child
		end
	end
	local custom = rawget(self, "_classIndex")
	if custom then
		return custom(self, key)
	end
	return nil
end

Inst.__newindex = function(self, key, value)
	if key == "Parent" then
		detach(self)
		if value ~= nil then
			attach(self, value)
		end
		return
	end
	local props = rawget(self, "_props")
	props[key] = value
	fireChanged(self, key)
end

Inst.__tostring = function(self)
	return rawget(self, "_props").Name
end

function methods.IsA(self, className)
	return isA(self, className)
end

function methods.FindFirstChild(self, name, recursive)
	for _, child in rawget(self, "_children") do
		if rawget(child, "_props").Name == name then
			return child
		end
	end
	if recursive then
		for _, child in rawget(self, "_children") do
			local found = methods.FindFirstChild(child, name, true)
			if found then
				return found
			end
		end
	end
	return nil
end

function methods.FindFirstChildOfClass(self, className)
	for _, child in rawget(self, "_children") do
		if rawget(child, "_props").ClassName == className then
			return child
		end
	end
	return nil
end

function methods.FindFirstChildWhichIsA(self, className)
	for _, child in rawget(self, "_children") do
		if isA(child, className) then
			return child
		end
	end
	return nil
end

function methods.WaitForChild(self, name)
	local child = methods.FindFirstChild(self, name)
	if not child then
		error(("WaitForChild('%s') no encontrado bajo %s"):format(name, tostring(self)), 2)
	end
	return child
end

function methods.GetChildren(self)
	return table.clone(rawget(self, "_children"))
end

function methods.GetDescendants(self)
	local out = {}
	local function walk(node)
		for _, c in rawget(node, "_children") do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end

function methods.ClearAllChildren(self)
	for _, c in table.clone(rawget(self, "_children")) do
		methods.Destroy(c)
	end
end

function methods.Destroy(self)
	local sigs = rawget(self, "_signals")
	if sigs.Destroying then
		sigs.Destroying:Fire()
	end
	for _, c in table.clone(rawget(self, "_children")) do
		methods.Destroy(c)
	end
	detach(self)
	rawset(self, "_destroyed", true)
end

function methods.IsDescendantOf(self, other)
	local p = rawget(self, "_parent")
	while p do
		if p == other then
			return true
		end
		p = rawget(p, "_parent")
	end
	return false
end

function methods.GetFullName(self)
	local parts = {}
	local n = self
	while n do
		table.insert(parts, 1, rawget(n, "_props").Name)
		n = rawget(n, "_parent")
	end
	return table.concat(parts, ".")
end

function methods.SetAttribute(self, name, value)
	rawget(self, "_attrs")[name] = value
end

function methods.GetAttribute(self, name)
	return rawget(self, "_attrs")[name]
end

function methods.GetPropertyChangedSignal(self, prop)
	local sigs = rawget(self, "_changedSignals")
	if sigs[prop] == nil then
		sigs[prop] = newSignal()
	end
	return sigs[prop]
end

function methods.Clone(self)
	local copy = MockInstance.new(rawget(self, "_props").ClassName)
	for k, v in rawget(self, "_props") do
		rawget(copy, "_props")[k] = v
	end
	for _, c in rawget(self, "_children") do
		methods.Clone(c).Parent = copy
	end
	return copy
end

-- Eventos remotos / funciones remotas
function methods.FireClient(self, player, ...)
	table.insert(rawget(self, "_fired"), { player = player, args = table.pack(...) })
	-- Si el destinatario es el cliente simulado, el mensaje llega a OnClientEvent.
	if player == MockInstance.localPlayer then
		local sigs = rawget(self, "_signals")
		if sigs.OnClientEvent then
			sigs.OnClientEvent:Fire(...)
		end
	end
end

function methods.FireAllClients(self, ...)
	table.insert(rawget(self, "_fired"), { player = "ALL", args = table.pack(...) })
end

function methods.FireServer(self, ...)
	local sigs = rawget(self, "_signals")
	if sigs.OnServerEvent then
		sigs.OnServerEvent:Fire(MockInstance.localPlayer, ...)
	end
end

function methods.InvokeServer(self, ...)
	local handler = rawget(self, "_props").OnServerInvoke
	if handler == nil then
		error("RemoteFunction sin OnServerInvoke", 2)
	end
	return handler(MockInstance.localPlayer, ...)
end

-- Tween / Sound / Humanoid: stubs
function methods.Play(self)
	local sigs = rawget(self, "_signals")
	if sigs.Completed then
		sigs.Completed:Fire()
	end
	rawget(self, "_props").Playing = true
end

function methods.Stop(self) end
function methods.Cancel(self) end
function methods.Pause(self) end

function methods.TweenSize(self) end
function methods.TweenPosition(self) end
function methods.GetTextSize() end
function methods.PivotTo(self, cf)
	rawget(self, "_props").Pivot = cf
end
function methods.GetPivot(self)
	return rawget(self, "_props").Pivot or cframe(0, 0, 0)
end
function methods.MoveTo(self, pos)
	rawget(self, "_props").MovedTo = pos
end
function methods.SetPrimaryPartCFrame(self, cf)
	rawget(self, "_props").Pivot = cf
end
function methods.GetBoundingBox()
	return cframe(0, 0, 0), vec3(1, 1, 1)
end
function methods.Emit(self, n)
	rawget(self, "_props").Emitted = (rawget(self, "_props").Emitted or 0) + (n or 1)
end
function methods.CaptureFocus() end
function methods.ReleaseFocus() end
function methods.Kick(self, message)
	rawget(self, "_props").KickedWith = message or ""
end
function methods.LoadCharacter() end
function methods.Load() end

function MockInstance.new(className, parent)
	local self = setmetatable({
		_props = { ClassName = className, Name = className },
		_children = {},
		_signals = {},
		_changedSignals = {},
		_attrs = {},
		_fired = {},
	}, Inst)
	if
		className == "TextButton"
		or className == "ImageButton"
		or className == "TextLabel"
		or className == "Frame"
	then
		rawget(self, "_props").Visible = true
	end
	if className == "RemoteFunction" then
		rawget(self, "_props").OnServerInvoke = nil
	end
	if parent then
		self.Parent = parent
	end
	return self
end

function MockInstance.fired(remote)
	return rawget(remote, "_fired")
end

function MockInstance.clearFired(remote)
	for k in rawget(remote, "_fired") do
		rawget(remote, "_fired")[k] = nil
	end
end

function MockInstance.props(instance)
	return rawget(instance, "_props")
end

-- ¿Tiene al menos un manejador conectado el evento `name`?
function MockInstance.connectionCount(instance, name)
	local sig = rawget(instance, "_signals")[name]
	return sig and sig:Count() or 0
end

function MockInstance.fire(instance, name, ...)
	local sigs = rawget(instance, "_signals")
	if sigs[name] == nil then
		sigs[name] = newSignal()
	end
	sigs[name]:Fire(...)
end

-- ───────────── Servicios ─────────────

function MockInstance.player(userId, name)
	local player = MockInstance.new("Player")
	player.Name = name
	player.UserId = userId
	player.DisplayName = name
	player.Character = nil
	local gui = MockInstance.new("PlayerGui")
	gui.Name = "PlayerGui"
	gui.Parent = player
	return player
end

-- Un jugador entra / sale del servicio Players simulado (dispara PlayerAdded / PlayerRemoving).
function MockInstance.joinPlayer(players, player)
	table.insert(rawget(players, "_list"), player)
	player.Parent = players
	MockInstance.fire(players, "PlayerAdded", player)
end

function MockInstance.leavePlayer(players, player)
	MockInstance.fire(players, "PlayerRemoving", player)
	local list = rawget(players, "_list")
	local idx = table.find(list, player)
	if idx then
		table.remove(list, idx)
	end
	player.Parent = nil
end

function MockInstance.services(options)
	options = options or {}
	local services = {}

	local function service(className)
		local s = MockInstance.new(className)
		s.Name = className
		services[className] = s
		return s
	end

	local players = service("Players")
	local list = {}
	rawset(players, "_list", list)
	rawget(players, "_props").GetPlayers = function()
		return table.clone(list)
	end
	rawget(players, "_props").GetPlayerByUserId = function(_, userId)
		for _, p in list do
			if p.UserId == userId then
				return p
			end
		end
		return nil
	end
	rawget(players, "_props").LocalPlayer = options.localPlayer
	rawget(players, "_props").CharacterAutoLoads = true

	local run = service("RunService")
	rawget(run, "_props").IsStudio = function()
		return options.isStudio ~= false
	end
	rawget(run, "_props").IsServer = function()
		return true
	end
	rawget(run, "_props").IsClient = function()
		return false
	end
	rawget(run, "_props").IsRunning = function()
		return true
	end

	local rs = service("ReplicatedStorage")
	rs.Name = "ReplicatedStorage"
	service("ServerStorage")
	service("ServerScriptService")
	service("Lighting")
	service("SoundService")
	local debris = service("Debris")
	rawget(debris, "_props").AddItem = function() end
	service("GuiService")
	service("StarterGui")
	service("TextChatService")
	service("ContextActionService")
	service("CollectionService")
	service("PhysicsService")

	local workspace = service("Workspace")
	local cam = MockInstance.new("Camera")
	cam.ViewportSize = vec2(1280, 720)
	cam.Parent = workspace
	rawget(workspace, "_props").CurrentCamera = cam
	rawget(workspace, "_props").GetServerTimeNow = function()
		return os.time()
	end

	local ts = service("TweenService")
	rawget(ts, "_props").Create = function(_, instance, info, goal)
		local tween = MockInstance.new("Tween")
		rawget(tween, "_props").Instance = instance
		for k, v in goal do
			instance[k] = v -- el simulador aplica el resultado final inmediatamente
		end
		return tween
	end

	local uis = service("UserInputService")
	rawget(uis, "_props").TouchEnabled = options.touch == true
	rawget(uis, "_props").KeyboardEnabled = options.touch ~= true
	rawget(uis, "_props").MouseEnabled = options.touch ~= true
	rawget(uis, "_props").GamepadEnabled = false
	rawget(uis, "_props").GetFocusedTextBox = function()
		return nil
	end

	local loc = service("LocalizationService")
	rawget(loc, "_props").RobloxLocaleId = options.locale or "en_us"
	rawget(loc, "_props").SystemLocaleId = options.locale or "en_us"

	local http = service("HttpService")
	rawget(http, "_props").GenerateGUID = function()
		return "00000000-0000-0000-0000-000000000000"
	end

	local market = service("MarketplaceService")
	rawget(market, "_props").UserOwnsGamePassAsync = function(_, userId, passId)
		return options.ownedPasses ~= nil and options.ownedPasses[passId] == true
	end
	rawget(market, "_props").PromptGamePassPurchase = function() end
	rawget(market, "_props").PromptProductPurchase = function() end

	local analytics = service("AnalyticsService")
	analytics._calls = {}
	for _, name in
		{ "LogEconomyEvent", "LogFunnelStepEvent", "LogOnboardingFunnelStepEvent", "LogCustomEvent" }
	do
		rawget(analytics, "_props")[name] = function(_, ...)
			table.insert(rawget(analytics, "_props")._log, { name = name, args = table.pack(...) })
		end
	end
	rawget(analytics, "_props")._log = {}

	local dss = service("DataStoreService")
	if options.dataStore then
		rawget(dss, "_props").GetDataStore = function()
			return options.dataStore
		end
	end
	rawget(dss, "_props").GetRequestBudgetForRequestType = function()
		return 100
	end

	return services
end

-- ───────────── Entorno global para los módulos ─────────────

function MockInstance.globals()
	local env = MockInstance.datatypes()
	env.Instance = { new = MockInstance.new }
	env.Random = nil -- lo aporta Mock.luau
	env.typeof = function(v)
		if type(v) == "table" then
			if getmetatable(v) == Inst then
				return "Instance"
			end
			if v.EnumType then
				return "EnumItem"
			end
		end
		return type(v)
	end
	env.tick = os.clock
	env.time = os.clock
	env.workspace = nil
	return env
end

MockInstance.EventNames = EVENTS

return MockInstance
