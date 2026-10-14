--!strict
--[[
	Fórmula de ingresos (por segundo) de una empresa.

	  sostenido = (base(sector, nivel) + Σ planos) × Π multiplicadores × mecánica de sector
	  total     = sostenido × evento × alianza

	`sostenido` es lo que sirve para valorar la empresa (los bonos temporales de eventos
	y alianzas NO inflan la valoración). `total` es lo que realmente se cobra.
]]

local Balance = require(script.Parent.Parent.Config.Balance)
local Catalog = require(script.Parent.Catalog)

export type Context = {
	eventMult: number?,
	allianceMult: number?,
	sessionSeconds: number?,
}

export type CompanyLike = {
	sector: string,
	level: number,
	upgrades: { [string]: number },
}

export type Breakdown = {
	base: number,
	flat: number,
	mult: number,
	mechanic: number,
	event: number,
	alliance: number,
	sustained: number,
	total: number,
}

local Income = {}

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function clampRate(n: number): number
	if not isFinite(n) or n < 0 then
		return 0
	end
	return math.min(n, Balance.MaxIncomePerSecond)
end

function Income.compute(company: CompanyLike, ctx: Context?): Breakdown
	local sector = Catalog.sector(company.sector)
	if sector == nil then
		return {
			base = 0,
			flat = 0,
			mult = 1,
			mechanic = 1,
			event = 1,
			alliance = 1,
			sustained = 0,
			total = 0,
		}
	end
	local level = math.clamp(math.floor(company.level), 1, 99)
	local base = sector.baseIncome + sector.levelIncomeStep * (level - 1)

	local flat, mult = 0, 1
	for _, def in sector.upgrades do
		local lvl = company.upgrades[def.id]
		if lvl ~= nil and lvl > 0 then
			local kind = def.effect.kind
			if kind == "flat" then
				flat += def.effect.value * lvl
			elseif kind == "mult" or kind == "look" then
				mult *= def.effect.value ^ lvl
			end
		end
	end

	local mechanic = 1
	local m = sector.mechanic
	if m.kind == "loyalty" then
		local session = (ctx and ctx.sessionSeconds) or 0
		local steps = math.floor(math.max(0, session) / m.stepSeconds)
		mechanic = 1 + math.min(m.maxBonus, steps * m.stepBonus)
	elseif m.kind == "scale" then
		mechanic = 1 + m.perLevelBonus * (level - 1)
	end

	local event = (ctx and ctx.eventMult) or 1
	local alliance = (ctx and ctx.allianceMult) or 1
	local sustained = clampRate((base + flat) * mult * mechanic)
	local total = clampRate(sustained * event * alliance)

	return {
		base = base,
		flat = flat,
		mult = mult,
		mechanic = mechanic,
		event = event,
		alliance = alliance,
		sustained = sustained,
		total = total,
	}
end

return Income
