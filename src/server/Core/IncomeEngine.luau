--!strict
--[[
	Bucle económico. UN solo bucle global por servidor (no uno por jugador).

	Por tick y por empresa cargada:
	  producción = ingresos/s × dt
	  cada titular acumula su parte exacta (producción × bps / 10 000) + su fracción pendiente
	  (`company.carry[titular]`); se le paga la parte entera y la fracción se arrastra.
	Así el reparto es justo A LARGO PLAZO (sin sesgo de redondeo hacia un titular) y no se
	crea ni se pierde dinero: Σ pagado + Σ fracciones = Σ producido.

	Los dividendos de titulares desconectados se acumulan en la propia empresa
	(`unclaimed`, con tope) y se pagan cuando vuelven a estar en el servidor.
	La Bolsa paga un % (PayoutRatio) a sus accionistas; lo demás se destruye.
]]

local Shared = game:GetService("ReplicatedStorage").Shared

local Balance = require(Shared.Config.Balance)
local Money = require(Shared.Economy.Money)
local Ownership = require(Shared.Economy.Ownership)

local Ledger = require(script.Parent.Ledger)
local World = require(script.Parent.World)

export type Deps = {
	world: World.World,
	ledger: Ledger.Ledger,
	touch: (World.Session) -> (),
}

export type TickSummary = { companies: number, paid: number, errors: number }

local IncomeEngine = {}
IncomeEngine.__index = IncomeEngine

export type IncomeEngine = typeof(setmetatable({} :: { _d: Deps }, IncomeEngine))

function IncomeEngine.new(deps: Deps): IncomeEngine
	return setmetatable({ _d = deps }, IncomeEngine)
end

-- Paga la parte de un titular. Devuelve lo realmente acreditado.
function IncomeEngine._pay(
	self: IncomeEngine,
	company: any,
	holderId: string,
	amount: number,
	ratePerSecond: number,
	bps: number
): number
	if holderId == Ownership.MARKET then
		return 0 -- la Bolsa no cobra: dinero destruido
	end
	local session = self._d.world.sessions[holderId]
	if session ~= nil then
		local pending = company.unclaimed and company.unclaimed[holderId] or 0
		local total = amount + pending
		if total <= 0 then
			return 0
		end
		if pending > 0 then
			company.unclaimed[holderId] = nil
		end
		local reason = if holderId == company.founderId then "income" else "dividend"
		self._d.ledger:credit(session, math.min(total, Money.MAX), reason, { companyId = company.id })
		return total
	end

	-- Titular desconectado: se acumula con tope en la propia empresa.
	if company.unclaimed == nil or amount <= 0 then
		return 0
	end
	local cap = math.floor(ratePerSecond * Balance.UnclaimedDividendCapSeconds * bps / Balance.BpsTotal) + 1
	local pending = company.unclaimed[holderId] or 0
	company.unclaimed[holderId] = math.min(cap, pending + amount)
	local founder = self._d.world.sessions[company.founderId]
	if founder then
		self._d.touch(founder)
	end
	return 0
end

function IncomeEngine._tickCompany(self: IncomeEngine, company: any, dt: number): number
	local world = self._d.world
	local rate = world:incomeOf(company).total
	local produced = rate * dt
	company.earned = math.min(Money.MAX, (company.earned or 0) + produced)

	-- La Bolsa sólo reparte una parte de su beneficio; el resto lo retiene (dinero destruido).
	local distributable = produced
	if company.isNpc then
		distributable = produced * Balance.Npc.PayoutRatio
	end

	company.carry = company.carry or {}
	local carry = company.carry

	-- Orden determinista (los tests y los registros no dependen del orden de hash).
	local ids = {}
	for id in company.cap.holders do
		table.insert(ids, id)
	end
	table.sort(ids)

	local paid = 0
	for _, id in ids do
		local bps = company.cap.holders[id]
		if id == Ownership.MARKET then
			carry[id] = nil
		else
			local exact = distributable * bps / Balance.BpsTotal + (carry[id] or 0)
			local whole = math.floor(exact + 1e-9)
			if whole < 0 then
				whole = 0
			end
			carry[id] = math.max(0, exact - whole) -- acota la deriva de coma flotante (~1e-13)
			paid += self:_pay(company, id, math.min(whole, Money.MAX), rate, bps)
		end
	end
	-- Quien ya no es titular no arrastra fracciones.
	for id in carry do
		if company.cap.holders[id] == nil then
			carry[id] = nil
		end
	end
	return paid
end

function IncomeEngine.tick(self: IncomeEngine, dt: number): TickSummary
	dt = math.clamp(dt, 0, Balance.MaxTickDelta)
	local summary: TickSummary = { companies = 0, paid = 0, errors = 0 }
	local world = self._d.world

	-- Sesiones: tiempo de juego (fidelidad de Comercio y estadísticas).
	for _, session in world.sessions do
		session.sessionSeconds = (session.sessionSeconds or 0) + dt
		session.data.stats.playSeconds = (session.data.stats.playSeconds or 0) + dt
	end

	local ids = {}
	for id in world.companies do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local company = world.companies[id]
		if company ~= nil then
			local ok, result = pcall(self._tickCompany, self, company, dt)
			summary.companies += 1
			if ok then
				summary.paid += result
			else
				summary.errors += 1
				warn(("[IncomeEngine] fallo en %s: %s"):format(id, tostring(result)))
			end
		end
	end

	for _, id in world.npcOrder do
		local npc = world.npcs[id]
		local ok, result = pcall(self._tickCompany, self, npc, dt)
		summary.companies += 1
		if ok then
			summary.paid += result
		else
			summary.errors += 1
			warn(("[IncomeEngine] fallo en %s: %s"):format(id, tostring(result)))
		end
	end
	return summary
end

return IncomeEngine
