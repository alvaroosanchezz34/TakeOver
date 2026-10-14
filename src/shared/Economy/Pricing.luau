--!strict
--[[
	Precios de mejoras, niveles y empresas nuevas + "beneficio esperado" y recomendación.

	  coste(mejora) = ceil(base × crecimiento^nivelActual × (1 − descuento))
	  coste(nivel)  = ceil(baseNivel × crecimientoNivel^(nivel−1) × (1 − descuento))

	Estas funciones son puras y compartidas: el cliente las usa para MOSTRAR precios,
	pero el servidor las recalcula siempre antes de cobrar (el cliente nunca envía precios).
]]

local Balance = require(script.Parent.Parent.Config.Balance)
local Catalog = require(script.Parent.Catalog)
local Income = require(script.Parent.Income)
local Money = require(script.Parent.Money)

export type Option = {
	kind: string, -- "upgrade" | "level"
	id: string, -- id de mejora, o "level"
	nameKey: string,
	icon: string,
	effectKind: string,
	effectValue: number,
	currentLevel: number,
	maxLevel: number,
	maxed: boolean,
	cost: number,
	deltaIncome: number,
	paybackSeconds: number,
}

export type CompanyLike = Income.CompanyLike

local Pricing = {}

local function priceFrom(raw: number, discount: number): number
	local value = math.ceil(raw * (1 - discount) - 1e-9)
	return math.clamp(value, 1, Money.MAX)
end

-- Descuento total (mejoras + evento) acotado por Balance.MaxUpgradeDiscount.
function Pricing.discount(company: CompanyLike, eventDiscount: number?): number
	local sector = Catalog.sector(company.sector)
	local total = eventDiscount or 0
	if sector then
		for _, def in sector.upgrades do
			if def.effect.kind == "discount" then
				total += def.effect.value * (company.upgrades[def.id] or 0)
			end
		end
	end
	return math.clamp(total, 0, Balance.MaxUpgradeDiscount)
end

function Pricing.upgradeCost(
	sectorId: string,
	upgradeId: string,
	currentLevel: number,
	discount: number
): number?
	local def = Catalog.upgrade(sectorId, upgradeId)
	if def == nil then
		return nil
	end
	return priceFrom(def.baseCost * def.growth ^ currentLevel, discount)
end

function Pricing.levelUpCost(sectorId: string, level: number, discount: number): number?
	local sector = Catalog.sector(sectorId)
	if sector == nil then
		return nil
	end
	return priceFrom(sector.levelCostBase * sector.levelCostGrowth ^ (level - 1), discount)
end

-- Nivel máximo actual = base del sector + licencias (capacity).
function Pricing.maxLevel(company: CompanyLike): number
	local sector = Catalog.sector(company.sector)
	if sector == nil then
		return 1
	end
	local max = sector.baseMaxLevel
	for _, def in sector.upgrades do
		if def.effect.kind == "capacity" then
			max += def.effect.value * (company.upgrades[def.id] or 0)
		end
	end
	return max
end

function Pricing.foundingCost(sectorId: string): number?
	local sector = Catalog.sector(sectorId)
	return sector and sector.foundingCost
end

local function withUpgrade(company: CompanyLike, upgradeId: string, newLevel: number): CompanyLike
	local upgrades = table.clone(company.upgrades)
	upgrades[upgradeId] = newLevel
	return { sector = company.sector, level = company.level, upgrades = upgrades }
end

local function payback(cost: number, delta: number): number
	if delta <= 1e-9 then
		return math.huge
	end
	return cost / delta
end

-- Todas las opciones de inversión de una empresa con su precio y beneficio esperado.
function Pricing.options(company: CompanyLike, ctx: Income.Context?, eventDiscount: number?): { Option }
	local sector = Catalog.sector(company.sector)
	local out: { Option } = {}
	if sector == nil then
		return out
	end
	local discount = Pricing.discount(company, eventDiscount)
	local current = Income.compute(company, ctx).total

	for _, def in sector.upgrades do
		local lvl = company.upgrades[def.id] or 0
		local maxed = lvl >= def.maxLevel
		local cost = priceFrom(def.baseCost * def.growth ^ lvl, discount)
		local delta = 0
		if not maxed then
			delta = Income.compute(withUpgrade(company, def.id, lvl + 1), ctx).total - current
		end
		table.insert(out, {
			kind = "upgrade",
			id = def.id,
			nameKey = def.nameKey,
			icon = def.icon,
			effectKind = def.effect.kind,
			effectValue = def.effect.value,
			currentLevel = lvl,
			maxLevel = def.maxLevel,
			maxed = maxed,
			cost = cost,
			deltaIncome = delta,
			paybackSeconds = if maxed then math.huge else payback(cost, delta),
		})
	end

	local maxLevel = Pricing.maxLevel(company)
	local levelMaxed = company.level >= maxLevel
	local levelCost = priceFrom(sector.levelCostBase * sector.levelCostGrowth ^ (company.level - 1), discount)
	local levelDelta = 0
	if not levelMaxed then
		local next: CompanyLike =
			{ sector = company.sector, level = company.level + 1, upgrades = company.upgrades }
		levelDelta = Income.compute(next, ctx).total - current
	end
	table.insert(out, {
		kind = "level",
		id = "level",
		nameKey = "upgrade.level",
		icon = "⬆️",
		effectKind = "level",
		effectValue = 1,
		currentLevel = company.level,
		maxLevel = maxLevel,
		maxed = levelMaxed,
		cost = levelCost,
		deltaIncome = levelDelta,
		paybackSeconds = if levelMaxed then math.huge else payback(levelCost, levelDelta),
	})

	return out
end

--[[
	Siguiente mejora recomendada: la que antes se amortiza contando también el tiempo que
	falta para poder pagarla (eta = tiempo hasta poder comprar + tiempo de amortización).
	Si ya no queda ninguna que aumente ingresos (p. ej. nivel al tope) recomienda ampliar
	capacidad. Devuelve nil sólo cuando no queda nada que comprar.
]]
function Pricing.recommended(options: { Option }, cash: number, incomePerSecond: number): Option?
	local rate = math.max(incomePerSecond, 0.01)
	local best: Option? = nil
	local bestEta = math.huge
	for _, opt in options do
		if not opt.maxed and opt.deltaIncome > 1e-9 then
			local wait = math.max(0, opt.cost - cash) / rate
			local eta = wait + opt.paybackSeconds
			if best == nil or eta < bestEta or (eta == bestEta and opt.cost < best.cost) then
				best = opt
				bestEta = eta
			end
		end
	end
	if best then
		return best
	end
	for _, opt in options do
		if not opt.maxed and opt.effectKind == "capacity" then
			return opt
		end
	end
	for _, opt in options do
		if not opt.maxed then
			return opt
		end
	end
	return nil
end

return Pricing
