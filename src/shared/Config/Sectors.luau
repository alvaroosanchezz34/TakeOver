--!strict
--[[
	Sectores y mejoras. Datos puros: la lógica vive en Shared/Economy.

	Efectos de mejora (`effect.kind`):
	  flat      suma `value` $/s por nivel a la producción base (antes de multiplicadores)
	  mult      multiplica los ingresos por `value` por nivel
	  discount  reduce el coste de TODAS las mejoras `value` (0,03 = 3 %) por nivel
	  capacity  sube el nivel máximo de la empresa en `value` por nivel
	  look      sube el aspecto visual +1 y multiplica ingresos por `value` (pequeño)

	Mecánicas propias de sector (`mechanic`), con diferencias reales de gameplay:
	  commerce  loyalty : +1 % de ingresos por cada 5 min de sesión (tope +10 %). Premia estar.
	  tech      hype    : la VALORACIÓN de mercado oscila ±12 % con un ciclo de ~15 min
	                      (oportunidades de comprar barato / vender caro entre jugadores).
	  industry  scale   : +8 % de ingresos por nivel de empresa por encima del 1. Premia expandir.
]]

local Table = require(script.Parent.Parent.Util.Table)

export type Effect = { kind: string, value: number }
export type UpgradeDef = {
	id: string,
	nameKey: string,
	icon: string,
	maxLevel: number,
	baseCost: number,
	growth: number,
	effect: Effect,
}
export type SectorDef = {
	id: string,
	nameKey: string,
	icon: string,
	color: { number },
	baseIncome: number,
	levelIncomeStep: number,
	baseMaxLevel: number,
	levelCostBase: number,
	levelCostGrowth: number,
	foundingCost: number,
	unlockTotalEarned: number,
	valuationMultiple: number,
	mechanic: { [string]: any },
	upgrades: { UpgradeDef },
}

local commerce: SectorDef = {
	id = "commerce",
	nameKey = "sector.commerce",
	icon = "🏪",
	color = { 255, 170, 60 },
	baseIncome = 1.0,
	levelIncomeStep = 2.0,
	baseMaxLevel = 4,
	levelCostBase = 150,
	levelCostGrowth = 3.0,
	foundingCost = 800,
	unlockTotalEarned = 0,
	valuationMultiple = 480,
	mechanic = { kind = "loyalty", stepSeconds = 300, stepBonus = 0.01, maxBonus = 0.10 },
	upgrades = {
		{
			id = "shelves",
			nameKey = "upgrade.commerce.shelves",
			icon = "🧺",
			maxLevel = 14,
			baseCost = 20,
			growth = 1.32,
			effect = { kind = "flat", value = 0.7 },
		},
		{
			id = "marketing",
			nameKey = "upgrade.commerce.marketing",
			icon = "📣",
			maxLevel = 8,
			baseCost = 120,
			growth = 1.75,
			effect = { kind = "mult", value = 1.18 },
		},
		{
			id = "logistics",
			nameKey = "upgrade.commerce.logistics",
			icon = "🚚",
			maxLevel = 6,
			baseCost = 250,
			growth = 2.0,
			effect = { kind = "discount", value = 0.03 },
		},
		{
			id = "license",
			nameKey = "upgrade.commerce.license",
			icon = "📜",
			maxLevel = 2,
			baseCost = 1500,
			growth = 4.0,
			effect = { kind = "capacity", value = 2 },
		},
		{
			id = "facade",
			nameKey = "upgrade.commerce.facade",
			icon = "🎨",
			maxLevel = 3,
			baseCost = 400,
			growth = 3.0,
			effect = { kind = "look", value = 1.04 },
		},
	},
}

local tech: SectorDef = {
	id = "tech",
	nameKey = "sector.tech",
	icon = "💻",
	color = { 80, 200, 255 },
	baseIncome = 0.8,
	levelIncomeStep = 1.6,
	baseMaxLevel = 4,
	levelCostBase = 600,
	levelCostGrowth = 3.4,
	foundingCost = 2500,
	unlockTotalEarned = 3000,
	valuationMultiple = 840,
	mechanic = { kind = "hype", amplitude = 0.12, periodSeconds = 900, phase = 0.0 },
	upgrades = {
		{
			id = "servers",
			nameKey = "upgrade.tech.servers",
			icon = "🖥️",
			maxLevel = 12,
			baseCost = 60,
			growth = 1.42,
			effect = { kind = "flat", value = 0.9 },
		},
		{
			id = "algorithms",
			nameKey = "upgrade.tech.algorithms",
			icon = "🧠",
			maxLevel = 8,
			baseCost = 400,
			growth = 2.3,
			effect = { kind = "mult", value = 1.22 },
		},
		{
			id = "research",
			nameKey = "upgrade.tech.research",
			icon = "🔬",
			maxLevel = 4,
			baseCost = 2500,
			growth = 3.4,
			effect = { kind = "mult", value = 1.45 },
		},
		{
			id = "cloud",
			nameKey = "upgrade.tech.cloud",
			icon = "☁️",
			maxLevel = 5,
			baseCost = 700,
			growth = 2.2,
			effect = { kind = "discount", value = 0.04 },
		},
		{
			id = "license",
			nameKey = "upgrade.tech.license",
			icon = "📜",
			maxLevel = 2,
			baseCost = 5000,
			growth = 4.0,
			effect = { kind = "capacity", value = 2 },
		},
		{
			id = "holo",
			nameKey = "upgrade.tech.holo",
			icon = "🔮",
			maxLevel = 3,
			baseCost = 900,
			growth = 3.0,
			effect = { kind = "look", value = 1.04 },
		},
	},
}

local industry: SectorDef = {
	id = "industry",
	nameKey = "sector.industry",
	icon = "🏭",
	color = { 190, 110, 255 },
	baseIncome = 2.0,
	levelIncomeStep = 4.0,
	baseMaxLevel = 4,
	levelCostBase = 2500,
	levelCostGrowth = 3.2,
	foundingCost = 12000,
	unlockTotalEarned = 25000,
	valuationMultiple = 660,
	mechanic = { kind = "scale", perLevelBonus = 0.10 },
	upgrades = {
		{
			id = "machines",
			nameKey = "upgrade.industry.machines",
			icon = "⚙️",
			maxLevel = 20,
			baseCost = 150,
			growth = 1.30,
			effect = { kind = "flat", value = 1.8 },
		},
		{
			id = "automation",
			nameKey = "upgrade.industry.automation",
			icon = "🤖",
			maxLevel = 6,
			baseCost = 1200,
			growth = 2.1,
			effect = { kind = "mult", value = 1.35 },
		},
		{
			id = "maintenance",
			nameKey = "upgrade.industry.maintenance",
			icon = "🔧",
			maxLevel = 6,
			baseCost = 1500,
			growth = 2.2,
			effect = { kind = "discount", value = 0.035 },
		},
		{
			id = "license",
			nameKey = "upgrade.industry.license",
			icon = "📜",
			maxLevel = 2,
			baseCost = 12000,
			growth = 4.0,
			effect = { kind = "capacity", value = 2 },
		},
		{
			id = "plant",
			nameKey = "upgrade.industry.plant",
			icon = "🏗️",
			maxLevel = 3,
			baseCost = 3000,
			growth = 3.0,
			effect = { kind = "look", value = 1.03 },
		},
	},
}

local byId: { [string]: SectorDef } = { commerce = commerce, tech = tech, industry = industry }

local Sectors: { order: { string }, byId: { [string]: SectorDef }, defaultSector: string } = {
	order = { "commerce", "tech", "industry" },
	byId = byId,
	defaultSector = "commerce",
}

return Table.deepFreeze(Sectors)
