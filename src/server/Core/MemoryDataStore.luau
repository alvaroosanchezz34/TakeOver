--!strict
--[[
	DataStore en memoria con la misma interfaz mínima que usa ProfileStore (UpdateAsync/GetAsync).
	Se usa cuando el DataStore real no está disponible (Studio sin "Enable Studio Access to API
	Services" o lugar sin publicar): el juego es jugable pero NADA se conserva al cerrar el servidor.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Table = require(Shared.Util.Table)

local MemoryDataStore = {}
MemoryDataStore.__index = MemoryDataStore

export type MemoryDataStore = typeof(setmetatable({} :: { _data: { [string]: any } }, MemoryDataStore))

function MemoryDataStore.new(): MemoryDataStore
	return setmetatable({ _data = {} }, MemoryDataStore)
end

function MemoryDataStore.UpdateAsync(self: MemoryDataStore, key: string, transform: (any) -> any): any
	local new = transform(Table.deepClone(self._data[key]))
	if new == nil then
		return nil
	end
	self._data[key] = Table.deepClone(new)
	return Table.deepClone(new)
end

function MemoryDataStore.GetAsync(self: MemoryDataStore, key: string): any
	return Table.deepClone(self._data[key])
end

return MemoryDataStore
