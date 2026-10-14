--!nocheck
--[[
	Globales de Roblox simulados para ejecutar el código del juego en Lune.
	Sólo lo imprescindible; los mocks de Instance/UI se añaden en MockInstance.
]]

local Mock = {}

-- Random determinista (xorshift32). Misma API que Roblox: NextInteger / NextNumber.
local RandomClass = {}
RandomClass.__index = RandomClass

function RandomClass.new(seed)
	local state = (seed or os.time()) % 4294967296
	if state == 0 then
		state = 2463534242
	end
	return setmetatable({ _s = state }, RandomClass)
end

function RandomClass:_next()
	local x = self._s
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self._s = x % 4294967296
	return self._s / 4294967296
end

function RandomClass:NextNumber(min, max)
	local r = self:_next()
	if min == nil then
		return r
	end
	return min + (max - min) * r
end

function RandomClass:NextInteger(min, max)
	return min + math.floor(self:_next() * (max - min + 1))
end

local MockInstance = require("./MockInstance")

function Mock.globals()
	local env = {
		Random = RandomClass,
	}
	for k, v in MockInstance.globals() do
		env[k] = v
	end
	return env
end

return Mock
