--!nocheck
--[[
	DataStore falso con la semántica relevante de Roblox:
	- UpdateAsync(key, fn): lectura-modificación-escritura atómica por clave.
	  Si fn devuelve nil se cancela y no se escribe nada.
	- Valida que lo escrito sea serializable (como el servicio real lo exigiría).
	- Inyección de fallos (failNext) y cesión de hilo opcional (yield) para probar carreras.
]]

local task = require("@lune/task")

local FakeDataStore = {}
FakeDataStore.__index = FakeDataStore

local function deepClone(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepClone(x)
	end
	return out
end

function FakeDataStore.new(options)
	options = options or {}
	return setmetatable({
		store = {},
		validate = options.validate, -- function(value) -> ok, path, reason
		yield = options.yield or false, -- ceder el hilo antes de cada operación
		failures = 0,
		failMessage = "DataStore request was added to queue. (fake)",
		calls = 0,
		updates = 0,
		log = {},
	}, FakeDataStore)
end

function FakeDataStore:failNext(count, message)
	self.failures = count
	if message then
		self.failMessage = message
	end
end

function FakeDataStore:peek(key)
	return deepClone(self.store[key])
end

function FakeDataStore:set(key, value)
	self.store[key] = deepClone(value)
end

function FakeDataStore:UpdateAsync(key, fn)
	self.calls += 1
	if self.yield then
		task.wait()
	end
	if self.failures > 0 then
		self.failures -= 1
		error(self.failMessage, 2)
	end
	-- Sección atómica (sin ceder): lectura -> callback -> escritura.
	local old = deepClone(self.store[key])
	local new = fn(old)
	if new == nil then
		return nil
	end
	if self.validate then
		local ok, path, why = self.validate(new)
		if not ok then
			error(("DataStore: valor no serializable en %s: %s"):format(tostring(path), tostring(why)), 2)
		end
	end
	self.store[key] = deepClone(new)
	self.updates += 1
	return deepClone(new)
end

function FakeDataStore:GetAsync(key)
	self.calls += 1
	if self.failures > 0 then
		self.failures -= 1
		error(self.failMessage, 2)
	end
	return deepClone(self.store[key])
end

return FakeDataStore
