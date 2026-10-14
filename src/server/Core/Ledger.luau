--!strict
--[[
	Libro mayor: ÚNICO punto por el que cambia el dinero de un jugador.

	- Cantidades siempre enteras y dentro de [0, MaxCash]; cualquier otra cosa se rechaza.
	- Un débito nunca deja el saldo negativo (se rechaza antes de tocar nada).
	- Un crédito que superaría MaxCash se recorta (el exceso se pierde, se informa).
	- `transfer` mueve dinero entre dos jugadores como un bloque: si el crédito fallara
	  tras el débito, se revierte (no hay estado a medias).
	- Cada cambio notifica a los observadores (analítica, sincronización con el cliente).
]]

local Shared = game:GetService("ReplicatedStorage").Shared

local Money = require(Shared.Economy.Money)
local Result = require(Shared.Util.Result)

export type Session = {
	id: string,
	userId: number,
	data: { [string]: any },
	[string]: any,
}

export type Change = {
	session: Session,
	delta: number,
	reason: string,
	balance: number,
	meta: { [string]: any }?,
}

export type Observer = (change: Change) -> ()

local EARN_REASONS: { [string]: boolean } = { income = true, dividend = true, reward = true }

local Ledger = {}
Ledger.__index = Ledger

export type Ledger = typeof(setmetatable(
	{} :: {
		_observers: { Observer },
		_touch: (Session) -> (),
	},
	Ledger
))

function Ledger.new(touch: (Session) -> ()): Ledger
	return setmetatable({ _observers = {}, _touch = touch }, Ledger)
end

function Ledger.observe(self: Ledger, observer: Observer)
	table.insert(self._observers, observer)
end

function Ledger._notify(self: Ledger, change: Change)
	for _, observer in self._observers do
		local ok, err = pcall(function()
			observer(change)
		end)
		if not ok then
			warn("[Ledger] observador falló: " .. tostring(err))
		end
	end
end

function Ledger.balance(_self: Ledger, session: Session): number
	return Money.sanitize(session.data.cash)
end

function Ledger.canAfford(_self: Ledger, session: Session, amount: number): boolean
	return Money.isValid(amount) and Money.sanitize(session.data.cash) >= amount
end

function Ledger.credit(
	self: Ledger,
	session: Session,
	amount: number,
	reason: string,
	meta: { [string]: any }?
): Result.Result<number>
	if not Money.isValid(amount) then
		return Result.err("INVALID_AMOUNT")
	end
	if amount == 0 then
		return Result.ok(Money.sanitize(session.data.cash))
	end
	local before = Money.sanitize(session.data.cash)
	local after = math.min(Money.MAX, before + amount)
	session.data.cash = after
	local applied = after - before

	if EARN_REASONS[reason] then
		local stats = session.data.stats
		stats.totalEarned = math.min(Money.MAX, (stats.totalEarned or 0) + applied)
	end
	self._touch(session)
	self:_notify({
		session = session,
		delta = applied,
		reason = reason,
		balance = after,
		meta = meta,
	})
	return Result.ok(after)
end

function Ledger.debit(
	self: Ledger,
	session: Session,
	amount: number,
	reason: string,
	meta: { [string]: any }?
): Result.Result<number>
	if not Money.isValid(amount) then
		return Result.err("INVALID_AMOUNT")
	end
	local before = Money.sanitize(session.data.cash)
	if before < amount then
		return Result.err("INSUFFICIENT_FUNDS", { missing = amount - before, have = before, need = amount })
	end
	if amount == 0 then
		return Result.ok(before)
	end
	local after = before - amount
	session.data.cash = after
	local stats = session.data.stats
	stats.totalSpent = math.min(Money.MAX, (stats.totalSpent or 0) + amount)
	self._touch(session)
	self:_notify({
		session = session,
		delta = -amount,
		reason = reason,
		balance = after,
		meta = meta,
	})
	return Result.ok(after)
end

--[[
	Reversión exacta: restablece saldo y estadísticas a una instantánea tomada ANTES de una
	operación compuesta que ha fallado a medias. Notifica el ajuste (razón "rollback") para
	que la interfaz y la analítica vean el estado real.
]]
function Ledger.restore(self: Ledger, session: Session, cash: number, stats: { [string]: number })
	local current = Money.sanitize(session.data.cash)
	session.data.cash = Money.sanitize(cash)
	for k in session.data.stats do
		if stats[k] == nil then
			session.data.stats[k] = nil
		end
	end
	for k, v in stats do
		session.data.stats[k] = v
	end
	self._touch(session)
	self:_notify({
		session = session,
		delta = session.data.cash - current,
		reason = "rollback",
		balance = session.data.cash,
		meta = nil,
	})
end

--[[
	Mueve `amount` de `from` a `to` como una unidad. Si el crédito no pudiera aplicarse
	se devuelve el dinero al origen. `burn` es la parte que se destruye (impuestos): sale
	del débito pero no se acredita a nadie.
]]
function Ledger.transfer(
	self: Ledger,
	from: Session,
	to: Session,
	amount: number,
	burn: number,
	reason: string,
	meta: { [string]: any }?
): Result.Result<nil>
	if not Money.isValid(amount) or not Money.isValid(burn) or burn > amount then
		return Result.err("INVALID_AMOUNT")
	end
	if from == to then
		return Result.err("SAME_PARTIES")
	end
	local debited = self:debit(from, amount, reason, meta)
	if not debited.ok then
		return debited :: any
	end
	local credited = self:credit(to, amount - burn, reason, meta)
	if not credited.ok then
		-- Reversión: devolvemos exactamente lo debitado.
		self:credit(from, amount, "refund", meta)
		return credited :: any
	end
	return Result.ok(nil)
end

return Ledger
