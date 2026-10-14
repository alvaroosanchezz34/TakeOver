--!strict
--[[
	Director de eventos económicos globales (ver Config/Events para las reglas públicas).

	Ciclo:   espera -> ANUNCIO (cuenta atrás visible) -> INICIO -> FIN -> espera ...
	El evento siguiente se decide al programarlo, así es siempre predecible: la interfaz muestra
	cuál viene y cuándo. Todo depende del reloj monotónico inyectado (testable, sin hilos).
]]

local Shared = game:GetService("ReplicatedStorage").Shared

local Config = require(Shared.Config.Events)

export type Transition = { kind: string, id: string } -- kind: "announce" | "start" | "end"

export type Snapshot = {
	active: { id: string, icon: string, remaining: number, duration: number }?,
	nextId: string?,
	startsIn: number?, -- sólo cuando ya está anunciado
}

local EventDirector = {}
EventDirector.__index = EventDirector

export type EventDirector = typeof(setmetatable(
	{} :: {
		_clock: { unix: () -> number, mono: () -> number },
		_rng: Random,
		_nextId: string?,
		_announceAt: number,
		_startAt: number,
		_announced: boolean,
		_active: { id: string, startedAt: number, endsAt: number }?,
		_lastId: string?,
		_enabled: boolean,
	},
	EventDirector
))

function EventDirector._pick(self: EventDirector): string
	local total = 0
	for _, id in Config.Order do
		if id ~= self._lastId then
			total += Config.Events[id].weight
		end
	end
	local roll = self._rng:NextNumber() * total
	local acc = 0
	for _, id in Config.Order do
		if id ~= self._lastId then
			acc += Config.Events[id].weight
			if roll <= acc then
				return id
			end
		end
	end
	return Config.Order[1]
end

function EventDirector._schedule(self: EventDirector, announceAt: number)
	self._nextId = self:_pick()
	self._announceAt = announceAt
	self._startAt = announceAt + Config.AnnounceLeadSeconds
	self._announced = false
end

function EventDirector.new(clock: { unix: () -> number, mono: () -> number }, rng: Random): EventDirector
	local self = setmetatable({
		_clock = clock,
		_rng = rng,
		_nextId = nil,
		_announceAt = 0,
		_startAt = 0,
		_announced = false,
		_active = nil,
		_lastId = nil,
		_enabled = true,
	}, EventDirector)
	self:_schedule(clock.mono() + math.max(0, Config.FirstEventDelaySeconds - Config.AnnounceLeadSeconds))
	return self
end

-- Avanza el reloj interno; devuelve los cambios de estado ocurridos (para notificar).
function EventDirector.update(self: EventDirector): { Transition }
	local out: { Transition } = {}
	local now = self._clock.mono()

	if self._active and now >= self._active.endsAt then
		table.insert(out, { kind = "end", id = self._active.id })
		self._lastId = self._active.id
		self._active = nil
		local span = Config.MaxIntervalSeconds - Config.MinIntervalSeconds
		self:_schedule(now + Config.MinIntervalSeconds + self._rng:NextNumber() * span)
	end

	if self._active == nil and self._nextId ~= nil then
		if not self._announced and now >= self._announceAt then
			self._announced = true
			table.insert(out, { kind = "announce", id = self._nextId })
		end
		if now >= self._startAt then
			if not self._announced then
				table.insert(out, { kind = "announce", id = self._nextId })
			end
			local def = Config.Events[self._nextId]
			self._active = { id = def.id, startedAt = now, endsAt = now + def.durationSeconds }
			table.insert(out, { kind = "start", id = def.id })
			self._nextId = nil
			self._announced = false
		end
	end
	return out
end

-- Fuerza el inicio de un evento (herramienta de administración y pruebas).
function EventDirector.forceStart(self: EventDirector, id: string): boolean
	local def = Config.Events[id]
	if def == nil or self._active ~= nil then
		return false
	end
	local now = self._clock.mono()
	self._active = { id = id, startedAt = now, endsAt = now + def.durationSeconds }
	self._nextId = nil
	self._announced = false
	return true
end

function EventDirector.activeId(self: EventDirector): string?
	return self._active and self._active.id
end

local function modifier(self: EventDirector, field: string, sector: string, neutral: number): number
	local active = self._active
	if active == nil then
		return neutral
	end
	local def = Config.Events[active.id]
	local perSector = def[field]
	if perSector == nil then
		return neutral
	end
	return perSector[sector] or neutral
end

function EventDirector.incomeMult(self: EventDirector, sector: string): number
	return modifier(self, "incomeMult", sector, 1)
end

function EventDirector.discount(self: EventDirector, sector: string): number
	return modifier(self, "discount", sector, 0)
end

function EventDirector.hypeBonus(self: EventDirector, sector: string): number
	return modifier(self, "hypeBonus", sector, 0)
end

function EventDirector.snapshot(self: EventDirector): Snapshot
	local now = self._clock.mono()
	local active = nil
	if self._active then
		local def = Config.Events[self._active.id]
		active = {
			id = def.id,
			icon = def.icon,
			remaining = math.max(0, math.ceil(self._active.endsAt - now)),
			duration = def.durationSeconds,
		}
	end
	local startsIn = nil
	if self._active == nil and self._announced then
		startsIn = math.max(0, math.ceil(self._startAt - now))
	end
	return { active = active, nextId = if self._announced then self._nextId else nil, startsIn = startsIn }
end

return EventDirector
