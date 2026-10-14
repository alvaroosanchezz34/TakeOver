--!strict
--[[
	Libro de ofertas entre jugadores (en memoria; las ofertas NO se persisten: caducan en
	segundos y no mueven nada hasta que el vendedor acepta y el servidor revalida).

	Estados:  pending -> accepted | rejected | cancelled | expired | failed
	Un estado final es definitivo: una oferta sólo se puede ejecutar UNA vez.
]]

local Shared = game:GetService("ReplicatedStorage").Shared

local Balance = require(Shared.Config.Balance)

export type State = "pending" | "accepted" | "rejected" | "cancelled" | "expired" | "failed"

export type Offer = {
	id: string,
	companyId: string,
	buyerId: string,
	sellerId: string,
	bps: number,
	price: number,
	capRev: number, -- revisión de la estructura de propiedad al ofertar (detecta datos obsoletos)
	refValuation: number, -- valoración de la empresa al ofertar
	createdMono: number,
	expiresMono: number,
	state: State,
	reason: string?, -- código cuando termina en failed/cancelled/expired
	closedMono: number?,
}

export type DealRecord = {
	t: number,
	companyId: string,
	companyName: string,
	buyerId: string,
	buyerName: string,
	sellerId: string,
	sellerName: string,
	bps: number,
	price: number,
}

local OfferBook = {}
OfferBook.__index = OfferBook

export type OfferBook = typeof(setmetatable(
	{} :: {
		_offers: { [string]: Offer },
		_seq: number,
		_deals: { DealRecord },
		_clock: { unix: () -> number, mono: () -> number },
	},
	OfferBook
))

local DEAL_LOG_LIMIT = 60

function OfferBook.new(clock: { unix: () -> number, mono: () -> number }): OfferBook
	return setmetatable({ _offers = {}, _seq = 0, _deals = {}, _clock = clock }, OfferBook)
end

export type NewOffer = {
	companyId: string,
	buyerId: string,
	sellerId: string,
	bps: number,
	price: number,
	capRev: number,
	refValuation: number,
}

function OfferBook.create(self: OfferBook, p: NewOffer): Offer
	self._seq += 1
	local now = self._clock.mono()
	local offer: Offer = {
		id = "o" .. tostring(self._seq),
		companyId = p.companyId,
		buyerId = p.buyerId,
		sellerId = p.sellerId,
		bps = p.bps,
		price = p.price,
		capRev = p.capRev,
		refValuation = p.refValuation,
		createdMono = now,
		expiresMono = now + Balance.OfferExpirySeconds,
		state = "pending",
		reason = nil,
		closedMono = nil,
	}
	self._offers[offer.id] = offer
	return offer
end

function OfferBook.get(self: OfferBook, id: string): Offer?
	return self._offers[id]
end

-- Cierra una oferta pendiente. Devuelve false si ya estaba cerrada (no se reabre jamás).
function OfferBook.close(self: OfferBook, offer: Offer, state: State, reason: string?): boolean
	if offer.state ~= "pending" then
		return false
	end
	offer.state = state
	offer.reason = reason
	offer.closedMono = self._clock.mono()
	return true
end

function OfferBook.pending(self: OfferBook): { Offer }
	local out: { Offer } = {}
	for _, o in self._offers do
		if o.state == "pending" then
			table.insert(out, o)
		end
	end
	table.sort(out, function(a, b)
		return a.createdMono < b.createdMono
	end)
	return out
end

-- Ofertas pendientes de un jugador. role: "buyer" | "seller"
function OfferBook.pendingFor(self: OfferBook, userId: string, role: string): { Offer }
	local out: { Offer } = {}
	for _, o in self:pending() do
		if (role == "buyer" and o.buyerId == userId) or (role == "seller" and o.sellerId == userId) then
			table.insert(out, o)
		end
	end
	return out
end

function OfferBook.countPending(self: OfferBook, userId: string, role: string): number
	return #self:pendingFor(userId, role)
end

function OfferBook.findDuplicate(
	self: OfferBook,
	buyerId: string,
	sellerId: string,
	companyId: string
): Offer?
	for _, o in self:pending() do
		if o.buyerId == buyerId and o.sellerId == sellerId and o.companyId == companyId then
			return o
		end
	end
	return nil
end

-- Caduca las ofertas vencidas. Devuelve las ofertas que acaban de caducar.
function OfferBook.sweep(self: OfferBook): { Offer }
	local now = self._clock.mono()
	local expired: { Offer } = {}
	for _, o in self:pending() do
		if now >= o.expiresMono then
			self:close(o, "expired", "OFFER_EXPIRED")
			table.insert(expired, o)
		end
	end
	-- Limpieza: las ofertas cerradas hace más de 5 minutos se olvidan (memoria acotada).
	for id, o in self._offers do
		if o.state ~= "pending" and o.closedMono ~= nil and now - o.closedMono > 300 then
			self._offers[id] = nil
		end
	end
	return expired
end

-- Cancela todas las pendientes que cumplan el predicado. Devuelve las canceladas.
function OfferBook.cancelWhere(self: OfferBook, predicate: (Offer) -> boolean, reason: string): { Offer }
	local out: { Offer } = {}
	for _, o in self:pending() do
		if predicate(o) then
			self:close(o, "cancelled", reason)
			table.insert(out, o)
		end
	end
	return out
end

function OfferBook.recordDeal(self: OfferBook, deal: DealRecord)
	table.insert(self._deals, deal)
	while #self._deals > DEAL_LOG_LIMIT do
		table.remove(self._deals, 1)
	end
end

function OfferBook.recentDeals(self: OfferBook, limit: number): { DealRecord }
	local out: { DealRecord } = {}
	local n = #self._deals
	for i = math.max(1, n - limit + 1), n do
		table.insert(out, self._deals[i])
	end
	return out
end

return OfferBook
