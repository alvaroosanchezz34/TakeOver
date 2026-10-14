--!nocheck
--[[
	Servidor + cliente reales ejecutándose juntos en el simulador. Sirve para recorrer la
	interfaz como lo haría un jugador y comprobar que cada pieza funciona de extremo a extremo.
	LIMITACIÓN: valida lógica y cableado (botones, ventanas, textos, flujos), no el aspecto visual.
]]

local FakeDataStore = require("./FakeDataStore")
local Loader = require("./Loader")
local MockInstance = require("./MockInstance")
local task = require("@lune/task")

local Stack = {}
Stack.__index = Stack

function Stack.new(options)
	options = options or {}
	local fastTask = setmetatable({
		wait = function()
			return 0
		end,
		delay = function() end, -- los temporizadores de cortesía (toasts) no se disparan en tests
	}, { __index = task })
	local fake = { mono = 0, unix = 1_700_000_000 }
	local globals = {} -- _G visible para los scripts (Main.server publica aquí las herramientas de QA)
	local fakeOs = setmetatable({
		time = function()
			return math.floor(fake.unix)
		end,
		clock = function()
			return fake.mono
		end,
	}, { __index = os })

	local l = Loader.new({
		env = {
			_G = globals,
			task = fastTask,
			time = function()
				return fake.mono
			end,
			os = fakeOs,
		},
		serviceOptions = {
			touch = options.touch,
			locale = options.locale,
		},
	})
	local PlayerData = l:server("Core/PlayerData")
	local ds = options.dataStore or FakeDataStore.new({ validate = PlayerData.assertSerializable })
	rawget(l.services.DataStoreService, "_props").GetDataStore = function()
		return ds
	end

	local self = setmetatable({ l = l, ds = ds, fake = fake, globals = globals }, Stack)
	self.players = l.services.Players
	self.run = l.services.RunService

	if options.viewport then
		l.services.Workspace.CurrentCamera.ViewportSize = options.viewport
	end

	-- Servidor
	l:run(l:node("server", "Main"))
	self.server = globals.Takeover.server
	return self
end

-- Un jugador entra. Si `asClient`, además arranca su cliente (sólo puede haber uno).
function Stack:join(userId, name, asClient, mutate)
	if mutate then
		local PlayerData = self.l:server("Core/PlayerData")
		local data = PlayerData.template(self.fake.unix)
		mutate(data)
		self.ds:set("Player_" .. userId, { recordVersion = 1, data = data })
	end
	local player = MockInstance.player(userId, name)
	if asClient then
		MockInstance.localPlayer = player
		rawget(self.players, "_props").LocalPlayer = player
		MockInstance.joinPlayer(self.players, player)
		self.l:run(self.l:node("client", "Main"))
		self.localPlayer = player
	else
		MockInstance.joinPlayer(self.players, player)
	end
	return player
end

function Stack:step(seconds)
	for _ = 1, seconds or 1 do
		self.fake.mono += 1
		self.fake.unix += 1
		MockInstance.fire(self.run, "Heartbeat", 1)
	end
end

-- Interfaz del jugador local.
function Stack:gui()
	return self.localPlayer:FindFirstChild("PlayerGui")
end

function Stack:find(name, root)
	local container = root or self:gui()
	return container:FindFirstChild(name, true)
end

function Stack:click(nameOrInstance)
	local button = type(nameOrInstance) == "string" and self:find(nameOrInstance) or nameOrInstance
	assert(button, "botón no encontrado: " .. tostring(nameOrInstance))
	MockInstance.fire(button, "Activated")
	return button
end

function Stack:text(nameOrInstance, root)
	local inst = type(nameOrInstance) == "string" and self:find(nameOrInstance, root) or nameOrInstance
	return inst and inst.Text or nil
end

-- Todos los botones del juego que no tienen NINGÚN manejador de pulsación.
function Stack:deadButtons()
	local dead = {}
	for _, d in self:gui():GetDescendants() do
		if d.ClassName == "TextButton" or d.ClassName == "ImageButton" then
			if MockInstance.connectionCount(d, "Activated") < 1 then
				table.insert(dead, d:GetFullName())
			end
		end
	end
	return dead
end

function Stack:buttons()
	local out = {}
	for _, d in self:gui():GetDescendants() do
		if d.ClassName == "TextButton" or d.ClassName == "ImageButton" then
			table.insert(out, d)
		end
	end
	return out
end

return Stack
