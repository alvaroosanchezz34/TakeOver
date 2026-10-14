--!strict
--[[
	Parámetros globales de balance. TODO número "de diseño" vive en Config/*:
	cambiar el balance no requiere tocar la lógica.
	El módulo se congela al cargarse: modificarlo en runtime lanza error.
]]

local Table = require(script.Parent.Parent.Util.Table)

local Balance = {
	-- ───────── Dinero ─────────
	StartingCash = 100,
	-- Tope duro por saldo y por operación. 2^53 ≈ 9,0e15 es el límite de enteros exactos
	-- en un double; 1e15 deja margen para sumas intermedias sin perder precisión.
	MaxCash = 1e15,
	MaxIncomePerSecond = 1e11,

	-- ───────── Tiempo ─────────
	TickSeconds = 1, -- cadencia del bucle económico (UN bucle global, no uno por jugador)
	MaxTickDelta = 5, -- si el servidor se atasca no se acredita más de esto por tick
	AutosaveSeconds = 60,
	SnapshotResyncSeconds = 5, -- reenvío de seguridad del estado al cliente
	RankingRefreshSeconds = 5,

	-- ───────── Empresas ─────────
	MaxOwnedCompanies = 3,
	HistoryLimit = 40, -- operaciones guardadas por empresa
	NotificationInboxLimit = 25,
	UnclaimedDividendCapSeconds = 1800, -- dividendos acumulables para un accionista desconectado

	-- ───────── Propiedad (puntos básicos: 10 000 = 100 %) ─────────
	BpsTotal = 10000,
	LotBps = 100, -- los tratos se hacen en múltiplos del 1 %

	-- ───────── Mercado entre jugadores ─────────
	OfferExpirySeconds = 120,
	MaxOutgoingOffers = 5,
	MaxIncomingOffers = 8,
	MinPriceRatio = 0.6, -- precio mínimo respecto a la valoración de referencia de la participación
	MaxPriceRatio = 2.5, -- y máximo: acota las transferencias abusivas entre cuentas
	SaleTaxBps = 300, -- impuesto sobre la venta (se destruye): las operaciones circulares pierden dinero
	MinPlayBeforeTradingSeconds = 90, -- anti-alts: una cuenta recién creada no puede comerciar al instante
	PairTradeCooldownSeconds = 8, -- entre las mismas dos personas
	MaxDealsPerPairPerHour = 12,
	MaxValuationDriftBps = 2500, -- si la valoración se mueve más de un 25 % desde la oferta, se renueva
	BigDealConfirmCash = 5000, -- por encima, la interfaz exige una segunda confirmación explícita
	MinOfferPrice = 1,

	-- ───────── Bolsa de empresas del servidor (compradora/vendedora automática) ─────────
	Npc = {
		FloatCapBps = 4900, -- máximo que pueden poseer los jugadores en conjunto
		PerPlayerCapBps = 2000,
		AskSpreadBps = 500, -- se compra a valoración × 1,05
		BidSpreadBps = 500, -- se vende a valoración × 0,95
		PayoutRatio = 0.6, -- el resto del beneficio lo retiene la empresa
		GrowthPerMinuteBps = 20, -- las empresas de la Bolsa crecen con el tiempo del servidor
		MaxGrowthBps = 5000,
	},

	-- ───────── Alianzas (sólo en sesión) ─────────
	Alliance = {
		MaxMembers = 4,
		BonusPerOtherMember = 0.03, -- ingresos +3 % por aliado conectado
		MaxBonus = 0.09, -- tope: un grupo de amigos no puede escalar sin límite
		InviteSeconds = 60,
		RejoinCooldownSeconds = 300,
	},

	-- ───────── Descuentos ─────────
	MaxUpgradeDiscount = 0.40,

	-- ───────── Recompensas ─────────
	TutorialBonusCash = 50,
	Daily = {
		CooldownSeconds = 20 * 3600,
		MaxStreak = 7,
		BaseCash = 200,
		IncomeSeconds = 120, -- recompensa = máx(Base, 2 min de tus ingresos), con tope
		MaxIncomeSeconds = 900, -- nunca más de 15 min de ingresos
		StreakStep = 0.10,
	},

	-- ───────── Insignias de posición (patrimonio neto) ─────────
	Ranks = {
		{ id = "startup", minNetWorth = 0 },
		{ id = "entrepreneur", minNetWorth = 5000 },
		{ id = "executive", minNetWorth = 50000 },
		{ id = "magnate", minNetWorth = 1000000 },
		{ id = "tycoon", minNetWorth = 100000000 },
	},
}

return Table.deepFreeze(Balance)
