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
	return {
		unix = function()
			return os.time()
		end,
		mono = os.clock,
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
