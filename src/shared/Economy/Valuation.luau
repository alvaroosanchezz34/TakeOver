--!strict
--[[
	Valoración de una empresa.

	  fundamental = ingresos sostenidos × múltiplo del sector
	  mercado     = fundamental × hype(sector, hora)         (sólo Tecnología oscila)

	- Los bonos TEMPORALES (eventos, alianzas) no entran: no se puede inflar el precio
	  de una empresa con un evento para colocar participaciones caras.
	- La Bolsa automática usa SIEMPRE `fundamental` (sin hype), así que el ciclo de hype no
	  permite arbitrar contra ella; el riesgo y la oportunidad están sólo entre jugadores.
	- El hype depende de la hora del servidor (os.time), igual en todos los servidores.
]]

local Catalog = require(script.Parent.Catalog)
local Money = require(script.Parent.Money)

local Valuation = {}

function Valuation.fundamental(sectorId: string, sustainedIncome: number): number
	local sector = Catalog.sector(sectorId)
	if sector == nil then
		return 0
	end
	return Money.sanitize(sustainedIncome * sector.valuationMultiple)
end

-- Multiplicador de hype del sector en el instante `unixTime` (1 = neutro).
-- `eventBonus` se suma durante un evento (p. ej. "Auge tecnológico": +0,10).
function Valuation.hype(sectorId: string, unixTime: number, eventBonus: number?): number
	local sector = Catalog.sector(sectorId)
	if sector == nil or sector.mechanic.kind ~= "hype" then
		return 1
	end
	local m = sector.mechanic
	local angle = 2 * math.pi * (unixTime / m.periodSeconds) + m.phase
	return 1 + m.amplitude * math.sin(angle) + (eventBonus or 0)
end

function Valuation.market(
	sectorId: string,
	sustainedIncome: number,
	unixTime: number,
	eventBonus: number?
): number
	local fundamental = Valuation.fundamental(sectorId, sustainedIncome)
	return Money.sanitize(fundamental * Valuation.hype(sectorId, unixTime, eventBonus))
end

-- Valor de una participación del `bps` sobre una valoración.
function Valuation.stake(valuation: number, bps: number): number
	return Money.mulBps(valuation, bps)
end

return Valuation
