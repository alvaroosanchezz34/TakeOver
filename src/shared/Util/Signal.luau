--!nonstrict
--[[
	Signal ligero en Luau puro (sin BindableEvent) para que funcione igual en
	servidor, cliente y tests. Los errores de un manejador no rompen a los demás.
]]

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local list = self._signal._handlers
	local idx = table.find(list, self)
	if idx then
		table.remove(list, idx)
	end
end

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	assert(type(fn) == "function", "Signal:Connect espera una función")
	local conn = setmetatable({ _signal = self, _fn = fn, Connected = true }, Connection)
	table.insert(self._handlers, conn)
	return conn
end

function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Fire(...)
	for _, conn in table.clone(self._handlers) do
		if conn.Connected then
			local ok, err = pcall(conn._fn, ...)
			if not ok then
				warn("[Signal] error en manejador: " .. tostring(err))
			end
		end
	end
end

function Signal:DisconnectAll()
	for _, conn in table.clone(self._handlers) do
		conn:Disconnect()
	end
end

return Signal
