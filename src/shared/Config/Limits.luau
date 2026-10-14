--!strict
--[[
	Límites de frecuencia por acción (token bucket): { capacity, refillPerSecond }.
	`capacity` es la ráfaga permitida; `refill` la tasa sostenida. Calibrados para un uso
	humano rápido (también táctil) y bastante por debajo de lo que haría un script abusivo.
]]

local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	-- Cualquier petición (red de seguridad global por jugador).
	Global = { capacity = 40, refill = 20 },

	-- Strikes por peticiones mal formadas / acciones desconocidas: se expulsa al abusar.
	StrikeWindowSeconds = 60,
	MaxStrikes = 25,

	Actions = {
		GetState = { capacity = 4, refill = 1 },
		BuyUpgrade = { capacity = 10, refill = 6 },
		LevelUp = { capacity = 4, refill = 1 },
		FoundCompany = { capacity = 2, refill = 0.2 },
		Rename = { capacity = 3, refill = 0.2 },
		SetLogo = { capacity = 3, refill = 0.2 },
		GetMarket = { capacity = 6, refill = 1 },
		InspectCompany = { capacity = 8, refill = 2 },
		MakeOffer = { capacity = 5, refill = 0.5 },
		RespondOffer = { capacity = 8, refill = 2 },
		BuyMarket = { capacity = 5, refill = 1 },
		SellMarket = { capacity = 5, refill = 1 },
		AllianceInvite = { capacity = 3, refill = 0.2 },
		AllianceRespond = { capacity = 5, refill = 1 },
		AllianceLeave = { capacity = 2, refill = 0.2 },
		ClaimDaily = { capacity = 2, refill = 0.1 },
		TutorialEvent = { capacity = 6, refill = 1 },
		SkipTutorial = { capacity = 2, refill = 0.2 },
		GetLeaderboard = { capacity = 4, refill = 0.5 },
		SetSetting = { capacity = 6, refill = 1 },
		SelectTitle = { capacity = 4, refill = 0.5 },
		EquipCosmetic = { capacity = 4, refill = 0.5 },
	},
})
