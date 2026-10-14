--!strict
--[[
	Monetización ÉTICA: sólo cosmética y personalización. Nada de lo que se vende da Cash,
	ingresos, descuentos ni ventaja en los tratos. Pagar no compra la victoria.

	IMPORTANTE — IDs: los `id` valen 0 hasta que crees cada producto en el Creator Dashboard
	(Monetización > Pases / Productos de desarrollador) y pegues aquí el ID real.
	Con id = 0 el producto queda DESACTIVADO (no se muestra ni se procesa).
	Los precios en Robux se fijan en el Dashboard; `suggestedRobux` es sólo una orientación
	para el equipo y debe validarse con jugadores reales.
]]

local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	GamePasses = {
		vip_office = {
			key = "vip_office",
			id = 0, -- ← REEMPLAZAR por el ID real del pase
			nameKey = "shop.vip_office",
			descKey = "shop.vip_office.desc",
			suggestedRobux = 199,
			grants = { cosmetics = { "office_gold", "office_neon" } },
		},
		golden_takeover = {
			key = "golden_takeover",
			id = 0,
			nameKey = "shop.golden_takeover",
			descKey = "shop.golden_takeover.desc",
			suggestedRobux = 149,
			grants = { cosmetics = { "fx_golden" } },
		},
		founder_title = {
			key = "founder_title",
			id = 0,
			nameKey = "shop.founder_title",
			descKey = "shop.founder_title.desc",
			suggestedRobux = 99,
			grants = { titles = { "founder" } },
		},
	},

	DeveloperProducts = {
		confetti_pack = {
			key = "confetti_pack",
			id = 0,
			nameKey = "shop.confetti_pack",
			descKey = "shop.confetti_pack.desc",
			suggestedRobux = 49,
			-- Consumible cosmético: cargas del efecto "confeti" al cerrar un trato.
			grants = { consumables = { confetti = 10 } },
		},
		neon_skyline = {
			key = "neon_skyline",
			id = 0,
			nameKey = "shop.neon_skyline",
			descKey = "shop.neon_skyline.desc",
			suggestedRobux = 79,
			grants = { consumables = { neon_skyline = 1 } },
		},
	},

	-- Catálogo de cosméticos que pueden equiparse.
	Cosmetics = {
		fx_default = { id = "fx_default", slot = "effect", free = true },
		fx_confetti = { id = "fx_confetti", slot = "effect", consumable = "confetti" },
		fx_golden = { id = "fx_golden", slot = "effect", free = false },
		office_default = { id = "office_default", slot = "office", free = true },
		office_gold = { id = "office_gold", slot = "office", free = false },
		office_neon = { id = "office_neon", slot = "office", free = false },
	},

	-- Títulos: algunos se ganan jugando (logros) y otros se compran (cosméticos).
	PurchasableTitles = { "founder" },
})
