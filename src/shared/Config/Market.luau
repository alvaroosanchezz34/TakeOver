--!strict
--[[
	Empresas de la Bolsa automática. Siempre hay algo que inspeccionar y en lo que invertir,
	aunque estés solo en el servidor (primera oferta y descubrimiento del mercado).

	Sus nombres son fijos (no hay texto de usuario). Su estructura de propiedad suma 100 %
	como la de cualquier empresa: la Bolsa (MARKET) posee lo que los jugadores no.
]]

local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	NpcCompanies = {
		{ id = "npc:commerce", sector = "commerce", name = "Nexus Retail", baseIncome = 40 },
		{ id = "npc:tech", sector = "tech", name = "Quantum Labs", baseIncome = 90 },
		{ id = "npc:industry", sector = "industry", name = "Titan Works", baseIncome = 140 },
	},
})
