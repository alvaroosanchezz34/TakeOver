--!strict
--[[
	Eventos económicos globales. Reglas PÚBLICAS y predecibles:
	- Siempre se anuncia el siguiente evento (cuál y cuándo) con antelación.
	- Sólo hay un evento activo a la vez.
	- Ningún evento quita dinero ni reduce ingresos: todos son bonificaciones temporales que
	  abren oportunidades de negociación (p. ej. comprar antes del auge de un sector).
	- No se repite el mismo evento dos veces seguidas.
]]

local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	FirstEventDelaySeconds = 150, -- desde que arranca el servidor
	MinIntervalSeconds = 360, -- entre el FIN de un evento y el ANUNCIO del siguiente
	MaxIntervalSeconds = 600,
	AnnounceLeadSeconds = 45, -- cuenta atrás visible antes de que empiece

	Events = {
		tech_boom = {
			id = "tech_boom",
			icon = "🚀",
			durationSeconds = 180,
			weight = 3,
			incomeMult = { tech = 1.5 },
			hypeBonus = { tech = 0.10 }, -- el mercado se entusiasma: las valoraciones suben
		},
		commerce_boom = {
			id = "commerce_boom",
			icon = "🛍️",
			durationSeconds = 180,
			weight = 3,
			incomeMult = { commerce = 1.5 },
		},
		industry_shortage = {
			id = "industry_shortage",
			icon = "⛏️",
			durationSeconds = 180,
			weight = 2,
			-- La escasez de suministros encarece sus productos: más ingresos, a cambio de que
			-- sólo beneficia al sector industrial.
			incomeMult = { industry = 1.4 },
		},
		new_opportunity = {
			id = "new_opportunity",
			icon = "📑",
			durationSeconds = 240,
			weight = 2,
			discount = { commerce = 0.20, tech = 0.20, industry = 0.20 }, -- contratos con proveedores
		},
		economic_expansion = {
			id = "economic_expansion",
			icon = "🌍",
			durationSeconds = 150,
			weight = 2,
			incomeMult = { commerce = 1.25, tech = 1.25, industry = 1.25 },
		},
	},

	-- Orden estable para el sorteo determinista.
	Order = { "tech_boom", "commerce_boom", "industry_shortage", "new_opportunity", "economic_expansion" },
})
