--!strict
--[[
	Tutorial contextual, logros y recompensas. El tutorial es CORTO, omitible y se completa
	haciendo acciones reales (no leyendo): cada paso avanza cuando el jugador hace lo que se le pide.
]]

local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	-- Pasos en orden. `event` es la acción real que lo completa. TODOS los eventos los genera el
	-- servidor al ejecutar la acción real (abrir el mercado, inspeccionar...): el cliente no
	-- puede "avisar" de nada para avanzar el tutorial.
	TutorialSteps = {
		{ id = "buy_upgrade", event = "upgrade_bought" },
		{ id = "see_income", event = "income_seen" }, -- avanza solo, tras ver subir los ingresos
		{ id = "open_market", event = "market_opened" },
		{ id = "inspect_company", event = "company_inspected" },
		{ id = "first_offer", event = "first_offer" },
	},

	Achievements = {
		{ id = "first_upgrade", titleKey = "ach.first_upgrade" },
		{ id = "first_deal", titleKey = "ach.first_deal" },
		{ id = "first_takeover", titleKey = "ach.first_takeover" },
		{ id = "diversified", titleKey = "ach.diversified" },
		{ id = "shareholder", titleKey = "ach.shareholder" },
		{ id = "millionaire", titleKey = "ach.millionaire" },
		{ id = "number_one", titleKey = "ach.number_one" },
	},

	MillionaireNetWorth = 1_000_000,
	ShareholderMinCompanies = 3,
})
