--!strict
--[[
	Reloj inyectable.
	- unix(): segundos enteros de época. Es lo que se persiste (createdAt, lastLogin...).
	- mono(): segundos fraccionarios monotónicos. Se usa para temporizar en memoria
	  (caducidad de ofertas, ticks, cooldowns). Nunca se envía como autoridad al cliente.
	El servidor es la única fuente de tiempo económico: no se lee ningún reloj del cliente.
]]

export type Clock = {
	unix: () -> number,
	mono: () -> number,
}

export type FakeClock = Clock & {
	advance: (self: FakeClock, seconds: number) -> (),
}

local Clock = {}

function Clock.system(): Clock
	-- OJO: en Roblox os.clock() mide tiempo de CPU, no de pared (un servidor ocioso casi no lo
	-- avanza). `time()` son los segundos reales desde que arrancó la instancia. Fuera de Roblox
	-- (herramientas, Lune) se cae en os.clock.
	local mono: () -> number = os.clock
	if typeof(time) == "function" then
		mono = time
	end
	return {
		unix = function()
			return os.time()
		end,
		mono = mono,
	}
end

-- Reloj de tests: avanza sólo cuando se le indica.
function Clock.fake(startUnix: number?): FakeClock
	local unixT = startUnix or 1_700_000_000
	local monoT = 0
	local clock = {} :: any
	clock.unix = function()
		return math.floor(unixT)
	end
	clock.mono = function()
		return monoT
	end
	clock.advance = function(_self: any, seconds: number)
		unixT += seconds
		monoT += seconds
	end
	return clock
end

return Clock
