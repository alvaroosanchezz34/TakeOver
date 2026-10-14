--!nocheck
--[[
	Servidor completo de pruebas: raíz de composición real + ProfileStore real + DataStore falso.
	Captura todo lo que el servidor "envía" a cada cliente y permite lanzar peticiones por el
	despachador como si vinieran de la red.
]]

local FakeDataStore = require("./FakeDataStore")

local Cluster = {}
Cluster.__index = Cluster

function Cluster.new(load, options)
	options = options or {}
	local Clock = load:shared("Util/Clock")
	local PlayerData = load:server("Core/PlayerData")
	local ProfileStore = load:server("Core/ProfileStore")
	local Server = load:server("Core/Server")

	local self = setmetatable({}, Cluster)
	self.load = load
	self.clock = options.clock or Clock.fake()
	self.ds = options.ds or FakeDataStore.new({ validate = PlayerData.assertSerializable })
	self.pushes = {} -- userId -> lista de mensajes
	self.kicked = {} -- userId -> código
	self.analytics = {}
	self.logs = {}
	self.jobId = options.jobId or "server-A"

	local store = ProfileStore.new({
		dataStore = self.ds,
		clock = self.clock,
		jobId = self.jobId,
		wait = function() end,
		log = function(m)
			table.insert(self.logs, m)
		end,
		lockAcquireAttempts = 2,
	})
	self.store = store

	self.server = Server.new({
		clock = self.clock,
		rng = load.Random.new(options.seed or 5),
		store = store,
		push = function(userId, message)
			self.pushes[userId] = self.pushes[userId] or {}
			table.insert(self.pushes[userId], message)
		end,
		kick = function(userId, code)
			self.kicked[userId] = code
		end,
		spawn = function(fn, ...)
			fn(...)
		end,
		wait = function() end,
		analyticsSink = function(e)
			table.insert(self.analytics, e)
		end,
		log = function(m)
			table.insert(self.logs, m)
		end,
	})
	return self
end

function Cluster:join(userId, name, mutate)
	if mutate then
		-- Prepara datos previos en el almacén (jugador "veterano").
		local PlayerData = self.load:server("Core/PlayerData")
		local data = PlayerData.template(self.clock.unix())
		mutate(data)
		self.ds:set("Player_" .. userId, { recordVersion = 1, data = data })
	end
	local r = self.server:playerAdded(userId, name or ("P" .. userId))
	return r
end

function Cluster:leave(userId)
	self.server:playerRemoving(userId)
end

function Cluster:call(userId, action, payload)
	return self.server:dispatch(userId, action, payload)
end

-- Avanza `seconds` con ticks de 1 s (economía + mantenimiento).
function Cluster:run(seconds)
	for _ = 1, seconds do
		self.clock:advance(1)
		self.server:tick(1)
	end
end

function Cluster:session(userId)
	return self.server.world.sessions[tostring(userId)]
end

function Cluster:messages(userId, messageType)
	local out = {}
	for _, m in self.pushes[userId] or {} do
		if messageType == nil or m.type == messageType then
			table.insert(out, m)
		end
	end
	return out
end

function Cluster:lastState(userId)
	local list = self:messages(userId, "state")
	return list[#list]
end

function Cluster:notifications(userId, kind)
	local out = {}
	for _, m in self:messages(userId, "notify") do
		if kind == nil or m.kind == kind then
			table.insert(out, m)
		end
	end
	return out
end

function Cluster:clearPushes()
	self.pushes = {}
end

-- Búsqueda profunda de un valor (número o texto) dentro de cualquier estructura.
function Cluster.contains(value, needle, depth)
	depth = depth or 0
	if depth > 12 then
		return false
	end
	if value == needle then
		return true
	end
	if type(value) == "table" then
		for k, v in value do
			if k == needle or Cluster.contains(v, needle, depth + 1) then
				return true
			end
		end
	end
	return false
end

return Cluster
