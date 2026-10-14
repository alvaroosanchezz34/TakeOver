--!nonstrict
--[[
	Estado del cliente. SOLO PRESENTACIÓN: el servidor es la única autoridad económica.

	Contiene la última foto del estado enviada por el servidor y permite mostrar el Cash con
	extrapolación suave entre fotos (cash + ingresos × tiempo transcurrido). Esa extrapolación es
	puramente visual y se corrige en cada foto del servidor; nunca se envía de vuelta.
]]

local Signal = require(game:GetService("ReplicatedStorage").Shared.Util.Signal)

local Store = {}
Store.__index = Store

local MAX_EXTRAPOLATION_SECONDS = 12 -- si el servidor deja de enviar, el número se detiene

function Store.new(clock)
	local self = setmetatable({
		state = nil, -- última foto
		offers = { incoming = {}, outgoing = {} },
		leaderboard = { companies = {}, players = {} },
		event = nil,
		market = nil,
		receivedAt = 0,
		clock = clock or os.clock,
		changed = Signal.new(), -- (topic: string)
		notifications = {}, -- bandeja (últimas 25)
	}, Store)
	return self
end

function Store.set(self, topic, value)
	if topic == "state" then
		self.state = value
		self.receivedAt = self.clock()
	elseif topic == "offers" then
		self.offers = { incoming = value.incoming or {}, outgoing = value.outgoing or {} }
		self.offersAt = self.clock()
	elseif topic == "leaderboard" then
		self.leaderboard = { companies = value.companies or {}, players = value.players or {} }
	elseif topic == "event" then
		self.event = value.event
		self.eventAt = self.clock()
	elseif topic == "market" then
		self.market = value
	end
	self.changed:Fire(topic)
end

function Store.ready(self)
	return self.state ~= nil
end

function Store.pushNotification(self, entry)
	table.insert(self.notifications, entry)
	while #self.notifications > 25 do
		table.remove(self.notifications, 1)
	end
	self.changed:Fire("notifications")
end

-- Cash a mostrar (entero): foto del servidor + ingresos extrapolados.
function Store.displayCash(self)
	local s = self.state
	if s == nil then
		return 0
	end
	local elapsed = math.clamp(self.clock() - self.receivedAt, 0, MAX_EXTRAPOLATION_SECONDS)
	return math.floor(s.cash + (s.incomePerSecond or 0) * elapsed)
end

-- Segundos que faltan para un evento/oferta según el momento en que llegó el dato.
function Store.elapsedSince(self, at)
	return math.max(0, self.clock() - (at or self.clock()))
end

function Store.eventRemaining(self)
	local e = self.event
	if e == nil then
		return nil
	end
	local passed = self:elapsedSince(self.eventAt)
	if e.active then
		return "active", math.max(0, e.active.remaining - passed), e.active
	elseif e.nextId and e.startsIn then
		return "next", math.max(0, e.startsIn - passed), e
	end
	return "none", 0, e
end

-- Segundos que le quedan a una oferta (según cuándo llegó el dato).
function Store.offerRemaining(self, offer)
	return math.max(0, offer.expiresIn - self:elapsedSince(self.offersAt))
end

function Store.company(self, companyId)
	local s = self.state
	if s == nil then
		return nil
	end
	for _, c in s.companies do
		if c.id == companyId then
			return c
		end
	end
	return nil
end

-- Empresas que el jugador gestiona.
function Store.managed(self)
	local out = {}
	if self.state then
		for _, c in self.state.companies do
			if c.manages then
				table.insert(out, c)
			end
		end
	end
	return out
end

return Store
