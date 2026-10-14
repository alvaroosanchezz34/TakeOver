--!strict
--[[
	Estructura de propiedad (cap table) de una empresa.

	- Las participaciones se miden en puntos básicos (bps): 10 000 = 100 %. Todo son enteros,
	  así que "suma exactamente 100 %" es una igualdad exacta, no una aproximación.
	- No existen operaciones para emitir ni destruir participaciones: sólo `transfer`,
	  que mueve bps de un titular a otro. El invariante (suma = 10 000, titulares con
	  valores enteros positivos) se comprueba tras cada transferencia.
	- `split` reparte un importe entero entre los titulares por el método del mayor resto:
	  la suma de lo repartido es SIEMPRE igual al importe (no se crea ni se pierde dinero
	  por redondeo).
]]

local Balance = require(script.Parent.Parent.Config.Balance)
local Governance = require(script.Parent.Parent.Config.Governance)
local Result = require(script.Parent.Parent.Util.Result)

export type Cap = {
	holders: { [string]: number },
	rev: number, -- se incrementa en cada transferencia (detecta ofertas obsoletas)
}

export type Holder = { id: string, bps: number }
export type Tier = "none" | "minority" | "board" | "control" | "full"

local Ownership = {}

Ownership.MARKET = "MARKET" -- titular especial: la Bolsa automática del servidor

local TOTAL = Balance.BpsTotal

function Ownership.newCap(founderId: string): Cap
	return { holders = { [founderId] = TOTAL }, rev = 0 }
end

function Ownership.stake(cap: Cap, holderId: string): number
	return cap.holders[holderId] or 0
end

-- Comprueba el invariante. Devuelve (true) o (false, motivo).
function Ownership.validate(cap: Cap): (boolean, string?)
	if type(cap) ~= "table" or type(cap.holders) ~= "table" then
		return false, "estructura inválida"
	end
	local sum = 0
	for id, bps in cap.holders do
		if type(id) ~= "string" or id == "" then
			return false, "titular inválido"
		end
		if type(bps) ~= "number" or bps ~= bps or bps % 1 ~= 0 or bps <= 0 or bps > TOTAL then
			return false, "participación inválida para " .. tostring(id)
		end
		sum += bps
	end
	if sum ~= TOTAL then
		return false, "la suma es " .. tostring(sum) .. ", debe ser " .. tostring(TOTAL)
	end
	return true, nil
end

-- Titulares ordenados: mayor participación primero, desempate por id.
function Ownership.holderList(cap: Cap): { Holder }
	local list: { Holder } = {}
	for id, bps in cap.holders do
		table.insert(list, { id = id, bps = bps })
	end
	table.sort(list, function(a, b)
		if a.bps ~= b.bps then
			return a.bps > b.bps
		end
		return a.id < b.id
	end)
	return list
end

-- Titular con MÁS del 50 % (nil si nadie tiene mayoría).
function Ownership.controller(cap: Cap): string?
	for id, bps in cap.holders do
		if bps > Governance.ControlMinBpsExclusive then
			return id
		end
	end
	return nil
end

-- Quién gestiona (compra mejoras, nombre, logotipo): el mayoritario; sin mayoría, el fundador.
function Ownership.manager(cap: Cap, founderId: string): string
	return Ownership.controller(cap) or founderId
end

function Ownership.tier(bps: number): Tier
	if bps <= 0 then
		return "none"
	elseif bps >= TOTAL then
		return "full"
	elseif bps > Governance.ControlMinBpsExclusive then
		return "control"
	elseif bps >= Governance.BoardMinBps then
		return "board"
	end
	return "minority"
end

export type Rights = { dividends: boolean, seesBooks: boolean, manages: boolean, tier: Tier }

function Ownership.rights(cap: Cap, holderId: string, founderId: string): Rights
	local bps = Ownership.stake(cap, holderId)
	local tier: Tier = Ownership.tier(bps)
	return {
		tier = tier,
		dividends = bps > 0,
		seesBooks = bps >= Governance.BoardMinBps or holderId == founderId,
		manages = Ownership.manager(cap, founderId) == holderId,
	}
end

-- Mueve `bps` de `fromId` a `toId`. Devuelve la nueva revisión.
function Ownership.transfer(cap: Cap, fromId: string, toId: string, bps: number): Result.Result<number>
	if type(bps) ~= "number" or bps ~= bps or bps % 1 ~= 0 or bps <= 0 or bps > TOTAL then
		return Result.err("INVALID_SHARES")
	end
	if fromId == toId then
		return Result.err("SAME_PARTIES")
	end
	local available = cap.holders[fromId] or 0
	if available < bps then
		return Result.err("INSUFFICIENT_SHARES", { available = available, requested = bps })
	end

	local remaining = available - bps
	if remaining > 0 then
		cap.holders[fromId] = remaining
	else
		cap.holders[fromId] = nil
	end
	cap.holders[toId] = (cap.holders[toId] or 0) + bps
	cap.rev += 1

	local ok, why = Ownership.validate(cap)
	if not ok then
		-- No debería ser alcanzable; si lo fuera, se revierte y se informa.
		cap.holders[toId] = (cap.holders[toId] or 0) - bps
		if cap.holders[toId] == 0 then
			cap.holders[toId] = nil
		end
		cap.holders[fromId] = (cap.holders[fromId] or 0) + bps
		cap.rev -= 1
		return Result.err("CAP_INVARIANT", { reason = why })
	end
	return Result.ok(cap.rev)
end

local function cloneCap(cap: Cap): Cap
	return { holders = table.clone(cap.holders), rev = cap.rev }
end

--[[
	Simula la transferencia sin tocar la estructura real y aplica las reglas públicas:
	tras el trato, quien gestione debe conservar al menos Governance.MinManagerBps.
]]
function Ownership.canTransfer(
	cap: Cap,
	founderId: string,
	fromId: string,
	toId: string,
	bps: number
): Result.Result<nil>
	local sim = cloneCap(cap)
	local moved = Ownership.transfer(sim, fromId, toId, bps)
	if not moved.ok then
		return moved :: any
	end
	local manager = Ownership.manager(sim, founderId)
	if Ownership.stake(sim, manager) < Governance.MinManagerBps then
		return Result.err("MANAGER_STAKE_TOO_LOW", { minBps = Governance.MinManagerBps })
	end
	return Result.ok(nil)
end

--[[
	Reparte `amount` (entero) entre los titulares por el método del mayor resto.
	Garantiza: Σ resultado == amount.
]]
function Ownership.split(amount: number, cap: Cap): { [string]: number }
	amount = math.max(0, math.floor(amount))
	local q = amount // TOTAL
	local r = amount % TOTAL

	local out: { [string]: number } = {}
	local fractions: { { id: string, frac: number } } = {}
	local distributed = 0
	for id, bps in cap.holders do
		local base = q * bps + (r * bps) // TOTAL
		out[id] = base
		distributed += base
		table.insert(fractions, { id = id, frac = (r * bps) % TOTAL })
	end

	table.sort(fractions, function(a, b)
		if a.frac ~= b.frac then
			return a.frac > b.frac
		end
		return a.id < b.id
	end)

	local leftover = amount - distributed
	local n = #fractions
	for i = 1, leftover do
		local entry = fractions[((i - 1) % n) + 1]
		out[entry.id] += 1
	end
	return out
end

return Ownership
