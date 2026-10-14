--!strict
--[[
	Cash es SIEMPRE un entero en [0, MaxCash]. MaxCash (1e15) < 2^53, así que sumas y
	restas son exactas en un double. Las fracciones de ingresos se acumulan aparte
	(`carry` por titular) y sólo se acredita la parte entera.
]]

local Balance = require(script.Parent.Parent.Config.Balance)

local Money = {}

Money.MAX = Balance.MaxCash

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- ¿Es una cantidad válida para mover? (entero, finito, 0..MAX)
function Money.isValid(n: any): boolean
	return type(n) == "number" and isFinite(n) and n % 1 == 0 and n >= 0 and n <= Money.MAX
end

-- Convierte cualquier número en una cantidad segura (para presentación o datos corruptos).
function Money.sanitize(n: any): number
	if type(n) ~= "number" or not isFinite(n) then
		return 0
	end
	return math.clamp(math.floor(n), 0, Money.MAX)
end

-- floor(amount * bps / 10000) con aritmética entera exacta (sin desbordar 2^53).
function Money.mulBps(amount: number, bps: number): number
	amount = math.floor(amount)
	local q = amount // Balance.BpsTotal
	local r = amount % Balance.BpsTotal
	return q * bps + (r * bps) // Balance.BpsTotal
end

return Money
