--!strict
--[[
	Utilidades de tablas. Todo lo que se persiste debe poder copiarse y
	congelarse sin referencias cíclicas.
]]

local Table = {}

function Table.deepClone<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy: { [any]: any } = {}
	for k, v in value :: any do
		copy[k] = Table.deepClone(v)
	end
	return copy :: any
end

function Table.deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value :: any) then
		for _, v in value :: any do
			Table.deepFreeze(v)
		end
		table.freeze(value :: any)
	end
	return value
end

function Table.count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

function Table.sortedKeys(t: { [string]: any }): { string }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

-- Añade `item` a una lista acotada (anillo): descarta los más antiguos.
function Table.ringPush<T>(list: { T }, item: T, max: number)
	table.insert(list, item)
	while #list > max do
		table.remove(list, 1)
	end
end

-- Fisher-Yates con un generador inyectado (determinista en tests).
function Table.shuffle<T>(list: { T }, rng: Random): { T }
	local out = table.clone(list)
	for i = #out, 2, -1 do
		local j = rng:NextInteger(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

-- Recorre un diccionario de forma determinista (orden por clave).
function Table.sortedPairs<V>(t: { [string]: V }): () -> (string?, V?)
	local keys = Table.sortedKeys(t)
	local i = 0
	return function()
		i += 1
		local k = keys[i]
		if k == nil then
			return nil, nil
		end
		return k, t[k]
	end
end

return Table
