--!strict
--[[
	Motor de adquisiciones. Toda operación que mueve dinero y participaciones pasa por aquí.

	GARANTÍAS
	1. El cliente sólo envía ids y la intención (quién, qué empresa, cuánto %, a qué precio de
	   oferta). Valoraciones, límites, fondos y propiedad los comprueba SIEMPRE el servidor.
	2. Una oferta se ejecuta como mucho UNA vez (estados finales irreversibles).
	3. `acceptOffer` revalida TODO contra el estado actual (fondos, participaciones,
	   estructura de propiedad, valoración, presencia de ambas partes). Nada de lo que se
	   comprobó al ofertar se da por válido al aceptar.
	4. La ejecución es atómica: no hay cesión de hilo entre validar y aplicar (otra petición
	   no puede colarse) y si CUALQUIER paso falla se restaura la instantánea exacta.
	5. El dinero sólo se mueve por el Ledger; las participaciones sólo por Ownership.transfer.
	6. Impuesto de venta (SaleTaxBps) destruido: las operaciones circulares pierden dinero.
]]

local Shared = game:GetService("ReplicatedStorage").Shared

local Balance = require(Shared.Config.Balance)
local Company = require(Shared.Economy.Company)
local Money = require(Shared.Economy.Money)
local Ownership = require(Shared.Economy.Ownership)
local Result = require(Shared.Util.Result)
local Table = require(Shared.Util.Table)

local Ledger = require(script.Parent.Ledger)
local OfferBook = require(script.Parent.OfferBook)
local World = require(script.Parent.World)

type Session = World.Session

export type Deps = {
	world: World.World,
	ledger: Ledger.Ledger,
	offers: OfferBook.OfferBook,
	clock: { unix: () -> number, mono: () -> number },
	touch: (Session) -> (),
	-- Sólo tests: permite forzar un fallo en una etapa concreta de la ejecución.
	fault: ((stage: string) -> ())?,
}

export type Deal = {
	offerId: string?,
	companyId: string,
	companyName: string,
	buyerId: string,
	sellerId: string,
	bps: number,
	price: number,
	tax: number,
	sellerReceives: number,
	controlChanged: boolean,
	newManager: string,
	touched: { Session },
}

local TradeEngine = {}
TradeEngine.__index = TradeEngine

export type TradeEngine = typeof(setmetatable(
	{} :: {
		_d: Deps,
		_pairs: { [string]: { last: number, history: { number } } },
	},
	TradeEngine
))

function TradeEngine.new(deps: Deps): TradeEngine
	return setmetatable({ _d = deps, _pairs = {} }, TradeEngine)
end

-- ───────────── utilidades ─────────────

local function isLot(bps: any): boolean
	return type(bps) == "number"
		and bps == bps
		and bps % Balance.LotBps == 0
		and bps >= Balance.LotBps
		and bps <= Balance.BpsTotal
end

local function pairKey(a: string, b: string): string
	if a < b then
		return a .. "|" .. b
	end
	return b .. "|" .. a
end

-- Banda de precios permitida para una participación (acota transferencias abusivas).
function TradeEngine.priceBand(self: TradeEngine, company: any, bps: number): (number, number, number)
	local ref = self._d.world:stakeValue(company, bps)
	local min = math.max(Balance.MinOfferPrice, math.ceil(ref * Balance.MinPriceRatio))
	local max = math.min(Money.MAX, math.max(min, math.floor(ref * Balance.MaxPriceRatio)))
	return min, max, ref
end

local function tradeEligible(session: Session): Result.Result<nil>
	local played = session.data.stats.playSeconds or 0
	if played < Balance.MinPlayBeforeTradingSeconds then
		return Result.err("TOO_NEW", { remaining = math.ceil(Balance.MinPlayBeforeTradingSeconds - played) })
	end
	return Result.ok(nil)
end

local function snapshotHolding(session: Session, companyId: string): any
	return Table.deepClone(session.data.holdings[companyId])
end

-- Espejo informativo de lo que posee un jugador en empresas ajenas (la verdad está en el cap).
local function addHolding(session: Session, company: any, bps: number, paid: number)
	if session.id == company.founderId then
		return
	end
	local h = session.data.holdings[company.id]
	if h == nil then
		h = {
			bps = 0,
			paid = 0,
			founderId = company.founderId,
			founderName = company.names and company.names[company.founderId] or "",
			name = company.name,
			sector = company.sector,
			valueHint = 0,
		}
		session.data.holdings[company.id] = h
	end
	h.bps += bps
	h.paid = math.min(Money.MAX, h.paid + paid)
	h.name = company.name
end

local function removeHolding(session: Session, companyId: string, bps: number)
	local h = session.data.holdings[companyId]
	if h == nil then
		return
	end
	local before = h.bps
	h.bps -= bps
	if h.bps <= 0 then
		session.data.holdings[companyId] = nil
	else
		h.paid = math.floor(h.paid * h.bps / before)
	end
end

-- ───────────── ofertas ─────────────

export type OfferParams = { companyId: string, sellerId: string, bps: number, price: number }

function TradeEngine.createOffer(
	self: TradeEngine,
	buyer: Session,
	p: OfferParams
): Result.Result<OfferBook.Offer>
	local d = self._d
	local world = d.world

	if not isLot(p.bps) then
		return Result.err("INVALID_SHARES", { lot = Balance.LotBps })
	end
	if not Money.isValid(p.price) or p.price < Balance.MinOfferPrice then
		return Result.err("INVALID_PRICE")
	end
	local company = world.companies[p.companyId]
	if company == nil then
		return Result.err("COMPANY_NOT_FOUND")
	end
	local seller = world.sessions[p.sellerId]
	if seller == nil or not seller.active then
		return Result.err("SELLER_OFFLINE")
	end
	if seller.id == buyer.id then
		return Result.err("SAME_PARTIES")
	end

	local eligible = tradeEligible(buyer)
	if not eligible.ok then
		return eligible :: any
	end
	local sellerEligible = tradeEligible(seller)
	if not sellerEligible.ok then
		return Result.err("SELLER_TOO_NEW")
	end

	local available = Ownership.stake(company.cap, seller.id)
	if available < p.bps then
		return Result.err("INSUFFICIENT_SHARES", { available = available, requested = p.bps })
	end
	local allowed = Ownership.canTransfer(company.cap, company.founderId, seller.id, buyer.id, p.bps)
	if not allowed.ok then
		return allowed :: any
	end

	local min, max = self:priceBand(company, p.bps)
	if p.price < min or p.price > max then
		return Result.err("PRICE_OUT_OF_RANGE", { min = min, max = max })
	end
	if not d.ledger:canAfford(buyer, p.price) then
		return Result.err(
			"INSUFFICIENT_FUNDS",
			{ missing = p.price - Money.sanitize(buyer.data.cash), need = p.price }
		)
	end

	-- Anti-spam y anti-abuso entre las mismas dos personas.
	local pair = self._pairs[pairKey(buyer.id, seller.id)]
	local now = d.clock.mono()
	if pair then
		if now - pair.last < Balance.PairTradeCooldownSeconds then
			return Result.err(
				"PAIR_COOLDOWN",
				{ seconds = math.ceil(Balance.PairTradeCooldownSeconds - (now - pair.last)) }
			)
		end
		local recent = 0
		for _, t in pair.history do
			if now - t < 3600 then
				recent += 1
			end
		end
		if recent >= Balance.MaxDealsPerPairPerHour then
			return Result.err("PAIR_LIMIT")
		end
	end
	if d.offers:findDuplicate(buyer.id, seller.id, company.id) then
		return Result.err("DUPLICATE_OFFER")
	end
	if d.offers:countPending(buyer.id, "buyer") >= Balance.MaxOutgoingOffers then
		return Result.err("TOO_MANY_OFFERS", { max = Balance.MaxOutgoingOffers })
	end
	if d.offers:countPending(seller.id, "seller") >= Balance.MaxIncomingOffers then
		return Result.err("SELLER_BUSY")
	end

	local offer = d.offers:create({
		companyId = company.id,
		buyerId = buyer.id,
		sellerId = seller.id,
		bps = p.bps,
		price = p.price,
		capRev = company.cap.rev,
		refValuation = world:valuationOf(company),
	})
	buyer.data.stats.offersMade += 1
	d.touch(buyer)
	return Result.ok(offer)
end

function TradeEngine.cancelOffer(
	self: TradeEngine,
	buyer: Session,
	offerId: string
): Result.Result<OfferBook.Offer>
	local offer = self._d.offers:get(offerId)
	if offer == nil then
		return Result.err("OFFER_NOT_FOUND")
	end
	if offer.buyerId ~= buyer.id then
		return Result.err("NOT_YOUR_OFFER")
	end
	if not self._d.offers:close(offer, "cancelled", "CANCELLED_BY_BUYER") then
		return Result.err("OFFER_NOT_PENDING")
	end
	return Result.ok(offer)
end

function TradeEngine.rejectOffer(
	self: TradeEngine,
	seller: Session,
	offerId: string
): Result.Result<OfferBook.Offer>
	local offer = self._d.offers:get(offerId)
	if offer == nil then
		return Result.err("OFFER_NOT_FOUND")
	end
	if offer.sellerId ~= seller.id then
		return Result.err("NOT_YOUR_OFFER")
	end
	if not self._d.offers:close(offer, "rejected", "REJECTED_BY_SELLER") then
		return Result.err("OFFER_NOT_PENDING")
	end
	return Result.ok(offer)
end

-- ───────────── ejecución atómica ─────────────

type Snapshot = {
	buyerCash: number,
	sellerCash: number,
	buyerStats: { [string]: number },
	sellerStats: { [string]: number },
	capHolders: { [string]: number },
	capRev: number,
	history: { any },
	names: { [string]: string },
	seq: any,
	buyerHolding: any,
	sellerHolding: any,
}

local function takeSnapshot(buyer: Session, seller: Session, company: any): Snapshot
	return {
		buyerCash = buyer.data.cash,
		sellerCash = seller.data.cash,
		buyerStats = table.clone(buyer.data.stats),
		sellerStats = table.clone(seller.data.stats),
		capHolders = table.clone(company.cap.holders),
		capRev = company.cap.rev,
		history = Table.deepClone(company.history),
		names = table.clone(company.names or {}),
		seq = company.seq,
		buyerHolding = snapshotHolding(buyer, company.id),
		sellerHolding = snapshotHolding(seller, company.id),
	}
end

function TradeEngine._rollback(
	self: TradeEngine,
	snap: Snapshot,
	buyer: Session,
	seller: Session,
	company: any
)
	local ledger = self._d.ledger
	ledger:restore(buyer, snap.buyerCash, snap.buyerStats)
	ledger:restore(seller, snap.sellerCash, snap.sellerStats)
	company.cap.holders = snap.capHolders
	company.cap.rev = snap.capRev
	company.history = snap.history
	company.names = snap.names
	company.seq = snap.seq
	buyer.data.holdings[company.id] = snap.buyerHolding
	seller.data.holdings[company.id] = snap.sellerHolding
end

function TradeEngine._stage(self: TradeEngine, name: string)
	local fault = self._d.fault
	if fault then
		fault(name)
	end
end

function TradeEngine._apply(
	self: TradeEngine,
	buyer: Session,
	seller: Session,
	company: any,
	bps: number,
	price: number,
	tax: number
): Result.Result<nil>
	local ledger = self._d.ledger
	local debited = ledger:debit(buyer, price, "trade_buy", { companyId = company.id })
	if not debited.ok then
		return debited :: any
	end
	self:_stage("afterDebit")

	local credited = ledger:credit(seller, price - tax, "trade_sell", { companyId = company.id })
	if not credited.ok then
		return credited :: any
	end
	self:_stage("afterCredit")

	local moved = Ownership.transfer(company.cap, seller.id, buyer.id, bps)
	if not moved.ok then
		return moved :: any
	end
	self:_stage("afterTransfer")

	company.names = company.names or {}
	company.names[buyer.id] = buyer.name
	company.names[seller.id] = seller.name
	addHolding(buyer, company, bps, price)
	removeHolding(seller, company.id, bps)
	self:_stage("afterHoldings")

	local now = self._d.clock.unix()
	company.seq = (company.seq or 0) + 1
	Company.log(company, {
		id = company.id .. "#" .. tostring(company.seq),
		t = now,
		kind = "trade",
		a = buyer.id,
		b = seller.id,
		bps = bps,
		amount = price,
	})
	buyer.data.stats.dealsClosed += 1
	seller.data.stats.dealsClosed += 1
	seller.data.stats.offersAccepted += 1
	self:_stage("afterLog")
	return Result.ok(nil)
end

-- ¿Cambia quién gestiona la empresa con este trato?
local function managerAfter(company: any, sellerId: string, buyerId: string, bps: number): string
	local sim = { holders = table.clone(company.cap.holders), rev = company.cap.rev }
	Ownership.transfer(sim, sellerId, buyerId, bps)
	return Ownership.manager(sim, company.founderId)
end

function TradeEngine.acceptOffer(
	self: TradeEngine,
	seller: Session,
	offerId: string,
	confirm: boolean?
): Result.Result<Deal>
	local d = self._d
	local world = d.world

	local offer = d.offers:get(offerId)
	if offer == nil then
		return Result.err("OFFER_NOT_FOUND")
	end
	if offer.sellerId ~= seller.id then
		return Result.err("NOT_YOUR_OFFER")
	end
	if offer.state ~= "pending" then
		return Result.err("OFFER_NOT_PENDING", { state = offer.state })
	end
	if d.clock.mono() >= offer.expiresMono then
		d.offers:close(offer, "expired", "OFFER_EXPIRED")
		return Result.err("OFFER_EXPIRED")
	end

	-- ── Revalidación completa contra el estado ACTUAL ──
	local function fail(code: string, params: { [string]: any }?): Result.Result<Deal>
		d.offers:close(offer, "failed", code)
		return Result.err(code, params)
	end

	local buyer = world.sessions[offer.buyerId]
	if buyer == nil or not buyer.active or not seller.active or world.sessions[seller.id] ~= seller then
		return fail("PARTY_LEFT")
	end
	local company = world.companies[offer.companyId]
	if company == nil then
		return fail("COMPANY_NOT_FOUND")
	end
	if company.cap.rev ~= offer.capRev then
		return fail("STALE_OFFER", { reason = "ownership" })
	end
	if Ownership.stake(company.cap, seller.id) < offer.bps then
		return fail("INSUFFICIENT_SHARES")
	end

	local valuation = world:valuationOf(company)
	if offer.refValuation > 0 then
		local drift = math.abs(valuation - offer.refValuation) / offer.refValuation
		if drift > Balance.MaxValuationDriftBps / Balance.BpsTotal then
			return fail("STALE_OFFER", { reason = "valuation" })
		end
	end
	local min, max = self:priceBand(company, offer.bps)
	if offer.price < min or offer.price > max then
		return fail("PRICE_OUT_OF_RANGE", { min = min, max = max })
	end

	local sellerOk, buyerOk = tradeEligible(seller), tradeEligible(buyer)
	if not sellerOk.ok then
		return fail("TOO_NEW")
	end
	if not buyerOk.ok then
		return fail("TOO_NEW")
	end
	local allowed = Ownership.canTransfer(company.cap, company.founderId, seller.id, buyer.id, offer.bps)
	if not allowed.ok then
		return fail(allowed.code, allowed.params)
	end
	if not d.ledger:canAfford(buyer, offer.price) then
		-- Sin fondos no se cierra la oferta: el comprador aún puede reunir el dinero mientras no caduque.
		return Result.err("INSUFFICIENT_FUNDS", { missing = offer.price - Money.sanitize(buyer.data.cash) })
	end

	-- ── Confirmación explícita para operaciones importantes ──
	local before = Ownership.manager(company.cap, company.founderId)
	local after = managerAfter(company, seller.id, buyer.id, offer.bps)
	local controlChanged: boolean = before ~= after
	if (offer.price >= Balance.BigDealConfirmCash or controlChanged) and confirm ~= true then
		return Result.err("CONFIRMATION_REQUIRED", {
			price = offer.price,
			bps = offer.bps,
			controlChanged = controlChanged,
		})
	end

	-- ── Ejecución atómica (sin cesión de hilo) con reversión exacta ──
	local tax = Money.mulBps(offer.price, Balance.SaleTaxBps)
	local snap = takeSnapshot(buyer, seller, company)
	local ok, outcome = pcall(self._apply, self, buyer, seller, company, offer.bps, offer.price, tax)
	if not ok or not (outcome :: any).ok then
		self:_rollback(snap, buyer, seller, company)
		local code = if ok then (outcome :: any).code else "INTERNAL"
		local params = if ok then (outcome :: any).params else { reason = tostring(outcome) }
		return fail(code, params)
	end

	d.offers:close(offer, "accepted", nil)

	-- Registro del trato, cooldowns y limpieza de lo que ha quedado obsoleto.
	local key = pairKey(buyer.id, seller.id)
	local pair = self._pairs[key]
	if pair == nil then
		pair = { last = 0, history = {} }
		self._pairs[key] = pair
	end
	pair.last = d.clock.mono()
	table.insert(pair.history, pair.last)
	while #pair.history > 40 do
		table.remove(pair.history, 1)
	end

	d.offers:recordDeal({
		t = d.clock.unix(),
		companyId = company.id,
		companyName = company.name,
		buyerId = buyer.id,
		buyerName = buyer.name,
		sellerId = seller.id,
		sellerName = seller.name,
		bps = offer.bps,
		price = offer.price,
	})

	-- La estructura de propiedad cambió: el resto de ofertas sobre esta empresa están obsoletas.
	d.offers:cancelWhere(function(o)
		return o.companyId == company.id
	end, "STALE_OFFER")

	local touched: { Session } = { buyer, seller }
	local founder = world.sessions[company.founderId]
	if founder and founder ~= buyer and founder ~= seller then
		table.insert(touched, founder)
	end
	for _, s in touched do
		d.touch(s)
	end

	return Result.ok({
		offerId = offer.id,
		companyId = company.id,
		companyName = company.name,
		buyerId = buyer.id,
		sellerId = seller.id,
		bps = offer.bps,
		price = offer.price,
		tax = tax,
		sellerReceives = offer.price - tax,
		controlChanged = controlChanged,
		newManager = after,
		touched = touched,
	} :: Deal)
end

-- ───────────── mantenimiento ─────────────

-- Caduca ofertas vencidas. Devuelve las que han caducado ahora (para avisar a los jugadores).
function TradeEngine.sweep(self: TradeEngine): { OfferBook.Offer }
	return self._d.offers:sweep()
end

-- Un jugador se va: sus ofertas (como comprador o vendedor) y las de sus empresas se anulan.
function TradeEngine.onPlayerLeft(
	self: TradeEngine,
	sessionId: string,
	removedCompanyIds: { string }
): { OfferBook.Offer }
	local removed: { [string]: boolean } = {}
	for _, id in removedCompanyIds do
		removed[id] = true
	end
	return self._d.offers:cancelWhere(function(o)
		return o.buyerId == sessionId or o.sellerId == sessionId or removed[o.companyId] == true
	end, "PARTY_LEFT")
end

-- ───────────── Bolsa automática ─────────────

function TradeEngine._npc(self: TradeEngine, npcId: string): any?
	return self._d.world.npcs[npcId]
end

function TradeEngine.floatBps(_self: TradeEngine, npc: any): number
	return Balance.BpsTotal - Ownership.stake(npc.cap, Ownership.MARKET)
end

-- Precio al que la Bolsa VENDE `bps` (compra del jugador) y al que COMPRA (venta del jugador).
function TradeEngine.marketQuote(self: TradeEngine, npc: any, bps: number): (number, number)
	local value = self._d.world:stakeValue(npc, bps)
	local ask =
		math.max(1, math.ceil(value * (Balance.BpsTotal + Balance.Npc.AskSpreadBps) / Balance.BpsTotal))
	local bid =
		math.max(0, math.floor(value * (Balance.BpsTotal - Balance.Npc.BidSpreadBps) / Balance.BpsTotal))
	return math.min(ask, Money.MAX), bid
end

function TradeEngine.buyFromMarket(
	self: TradeEngine,
	buyer: Session,
	npcId: string,
	bps: number,
	confirm: boolean?
): Result.Result<Deal>
	local d = self._d
	local npc = self:_npc(npcId)
	if npc == nil then
		return Result.err("COMPANY_NOT_FOUND")
	end
	if not isLot(bps) then
		return Result.err("INVALID_SHARES", { lot = Balance.LotBps })
	end
	local owned = Ownership.stake(npc.cap, buyer.id)
	if owned + bps > Balance.Npc.PerPlayerCapBps then
		return Result.err("PLAYER_CAP", { max = Balance.Npc.PerPlayerCapBps, owned = owned })
	end
	local available = Balance.Npc.FloatCapBps - self:floatBps(npc)
	if bps > available then
		return Result.err("MARKET_SOLD_OUT", { available = math.max(0, available) })
	end
	local ask = self:marketQuote(npc, bps)
	if not d.ledger:canAfford(buyer, ask) then
		return Result.err(
			"INSUFFICIENT_FUNDS",
			{ missing = ask - Money.sanitize(buyer.data.cash), need = ask }
		)
	end
	if ask >= Balance.BigDealConfirmCash and confirm ~= true then
		return Result.err("CONFIRMATION_REQUIRED", { price = ask, bps = bps, controlChanged = false })
	end

	-- Atómico: débito + transferencia + espejo; si algo falla, se restaura.
	local snapCash, snapStats = buyer.data.cash, table.clone(buyer.data.stats)
	local snapCap, snapRev = table.clone(npc.cap.holders), npc.cap.rev
	local snapHolding = snapshotHolding(buyer, npc.id)
	local ok, outcome = pcall(function()
		local debited = d.ledger:debit(buyer, ask, "market_buy", { companyId = npc.id })
		if not debited.ok then
			error(debited.code)
		end
		self:_stage("afterDebit")
		local moved = Ownership.transfer(npc.cap, Ownership.MARKET, buyer.id, bps)
		if not moved.ok then
			error(moved.code)
		end
		self:_stage("afterTransfer")
		addHolding(buyer, npc, bps, ask)
		self:_stage("afterHoldings")
	end)
	if not ok then
		d.ledger:restore(buyer, snapCash, snapStats)
		npc.cap.holders, npc.cap.rev = snapCap, snapRev
		buyer.data.holdings[npc.id] = snapHolding
		return Result.err("INTERNAL", { reason = tostring(outcome) })
	end
	d.touch(buyer)
	return Result.ok({
		companyId = npc.id,
		companyName = npc.name,
		buyerId = buyer.id,
		sellerId = Ownership.MARKET,
		bps = bps,
		price = ask,
		tax = 0,
		sellerReceives = 0,
		controlChanged = false,
		newManager = Ownership.MARKET,
		touched = { buyer },
	} :: Deal)
end

function TradeEngine.sellToMarket(
	self: TradeEngine,
	seller: Session,
	npcId: string,
	bps: number
): Result.Result<Deal>
	local d = self._d
	local npc = self:_npc(npcId)
	if npc == nil then
		return Result.err("COMPANY_NOT_FOUND")
	end
	if not isLot(bps) then
		return Result.err("INVALID_SHARES", { lot = Balance.LotBps })
	end
	local owned = Ownership.stake(npc.cap, seller.id)
	if owned < bps then
		return Result.err("INSUFFICIENT_SHARES", { available = owned, requested = bps })
	end
	local _, bid = self:marketQuote(npc, bps)

	local snapCash, snapStats = seller.data.cash, table.clone(seller.data.stats)
	local snapCap, snapRev = table.clone(npc.cap.holders), npc.cap.rev
	local snapHolding = snapshotHolding(seller, npc.id)
	local ok, outcome = pcall(function()
		local moved = Ownership.transfer(npc.cap, seller.id, Ownership.MARKET, bps)
		if not moved.ok then
			error(moved.code)
		end
		self:_stage("afterTransfer")
		local credited = d.ledger:credit(seller, bid, "market_sell", { companyId = npc.id })
		if not credited.ok then
			error(credited.code)
		end
		self:_stage("afterCredit")
		removeHolding(seller, npc.id, bps)
	end)
	if not ok then
		d.ledger:restore(seller, snapCash, snapStats)
		npc.cap.holders, npc.cap.rev = snapCap, snapRev
		seller.data.holdings[npc.id] = snapHolding
		return Result.err("INTERNAL", { reason = tostring(outcome) })
	end
	d.touch(seller)
	return Result.ok({
		companyId = npc.id,
		companyName = npc.name,
		buyerId = Ownership.MARKET,
		sellerId = seller.id,
		bps = bps,
		price = bid,
		tax = 0,
		sellerReceives = bid,
		controlChanged = false,
		newManager = Ownership.MARKET,
		touched = { seller },
	} :: Deal)
end

--[[
	Al entrar: recupera las participaciones del jugador en la Bolsa. Si el cupo del servidor ya
	está ocupado por otros, el exceso se liquida automáticamente al precio de compra de la Bolsa.
	Devuelve la lista de liquidaciones (para avisar al jugador).
]]
function TradeEngine.restoreMarketStakes(
	self: TradeEngine,
	session: Session
): { { companyId: string, bps: number, cash: number } }
	local d = self._d
	local liquidations = {}
	for id, npc in d.world.npcs do
		local h = session.data.holdings[id]
		if h ~= nil and Ownership.stake(npc.cap, session.id) == 0 then
			local want = math.min(h.bps, Balance.Npc.PerPlayerCapBps)
			local free = math.max(0, Balance.Npc.FloatCapBps - self:floatBps(npc))
			local grant = math.min(want, free)
			if grant > 0 then
				Ownership.transfer(npc.cap, Ownership.MARKET, session.id, grant)
			end
			local excess = h.bps - grant
			if excess > 0 then
				local _, bid = self:marketQuote(npc, excess)
				d.ledger:credit(session, bid, "market_liquidation", { companyId = id })
				table.insert(liquidations, { companyId = id, bps = excess, cash = bid })
				removeHolding(session, id, excess)
			end
		end
	end
	return liquidations
end

-- Al salir: devuelve a la Bolsa lo que el jugador tenía en ella (el espejo en su perfil se conserva).
function TradeEngine.releaseMarketStakes(self: TradeEngine, session: Session)
	for _, npc in self._d.world.npcs do
		local stake = Ownership.stake(npc.cap, session.id)
		if stake > 0 then
			Ownership.transfer(npc.cap, session.id, Ownership.MARKET, stake)
		end
	end
end

return TradeEngine
