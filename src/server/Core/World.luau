--!strict
--[[
	Estado en memoria del servidor: sesiones, empresas cargadas y empresas de la Bolsa.

	Las empresas de jugadores son REFERENCIAS vivas a los documentos dentro de los perfiles
	(`data.companies`), así que mutar una empresa muta lo que se guarda. Cuando un jugador
	se va, sus empresas se retiran del mundo (no producen mientras su fundador no juega).

	Modificadores externos (eventos, alianzas) se inyectan como funciones para que el núcleo
	sea puro y testable.
]]

local Shared = game:GetService("ReplicatedStorage").Shared

local Balance = require(Shared.Config.Balance)
local MarketConfig = require(Shared.Config.Market)
local Income = require(Shared.Economy.Income)
local Money = require(Shared.Economy.Money)
local Ownership = require(Shared.Economy.Ownership)
local Valuation = require(Shared.Economy.Valuation)

export type Session = {
	id: string,
	userId: number,
	name: string,
	data: { [string]: any },
	profile: any,
	joinedMono: number,
	[string]: any,
}

export type Modifiers = {
	eventIncomeMult: (sectorId: string) -> number,
	eventDiscount: (sectorId: string) -> number,
	eventHypeBonus: (sectorId: string) -> number,
	allianceMult: (userId: string) -> number,
}

export type Npc = {
	id: string,
	sector: string,
	name: string,
	baseIncome: number,
	founderId: string,
	isNpc: boolean,
	cap: Ownership.Cap,
	carry: { [string]: number },
	history: { any },
}

local World = {}
World.__index = World

export type World = typeof(setmetatable(
	{} :: {
		sessions: { [string]: Session },
		companies: { [string]: any },
		npcs: { [string]: Npc },
		npcOrder: { string },
		modifiers: Modifiers,
		_clock: { unix: () -> number, mono: () -> number },
		_startMono: number,
	},
	World
))

local NEUTRAL: Modifiers = {
	eventIncomeMult = function()
		return 1
	end,
	eventDiscount = function()
		return 0
	end,
	eventHypeBonus = function()
		return 0
	end,
	allianceMult = function()
		return 1
	end,
}

function World.new(clock: { unix: () -> number, mono: () -> number }, modifiers: Modifiers?): World
	local self = setmetatable({
		sessions = {},
		companies = {},
		npcs = {},
		npcOrder = {},
		modifiers = modifiers or NEUTRAL,
		_clock = clock,
		_startMono = clock.mono(),
	}, World)

	for _, def in MarketConfig.NpcCompanies do
		self.npcs[def.id] = {
			id = def.id,
			sector = def.sector,
			name = def.name,
			baseIncome = def.baseIncome,
			founderId = Ownership.MARKET,
			isNpc = true,
			cap = Ownership.newCap(Ownership.MARKET),
			carry = {},
			history = {},
		}
		table.insert(self.npcOrder, def.id)
	end
	return self
end

function World.setModifiers(self: World, modifiers: Modifiers)
	self.modifiers = modifiers
end

-- ───────────── Sesiones y empresas ─────────────

function World.addSession(self: World, session: Session)
	self.sessions[session.id] = session
	for id, company in session.data.companies do
		self.companies[id] = company
	end
end

-- Retira la sesión y sus empresas. Devuelve los ids de las empresas retiradas.
function World.removeSession(self: World, sessionId: string): { string }
	local session = self.sessions[sessionId]
	local removed: { string } = {}
	if session then
		for id in session.data.companies do
			if self.companies[id] ~= nil then
				self.companies[id] = nil
				table.insert(removed, id)
			end
		end
	end
	self.sessions[sessionId] = nil
	return removed
end

function World.registerCompany(self: World, company: any)
	self.companies[company.id] = company
end

function World.getSession(self: World, sessionId: string): Session?
	return self.sessions[sessionId]
end

-- Empresa de jugador o de la Bolsa.
function World.getCompany(self: World, companyId: string): any?
	return self.companies[companyId] or self.npcs[companyId]
end

function World.isNpc(_self: World, company: any): boolean
	return company.isNpc == true
end

-- ───────────── Ingresos y valoración ─────────────

function World.npcUptimeMinutes(self: World): number
	return (self._clock.mono() - self._startMono) / 60
end

function World.npcSustainedIncome(self: World, npc: Npc): number
	local growthBps =
		math.min(Balance.Npc.MaxGrowthBps, self:npcUptimeMinutes() * Balance.Npc.GrowthPerMinuteBps)
	return npc.baseIncome * (1 + growthBps / Balance.BpsTotal)
end

function World.incomeContext(self: World, company: any): Income.Context
	local founderSession = self.sessions[company.founderId]
	local sessionSeconds = 0
	if founderSession then
		sessionSeconds = founderSession.sessionSeconds or (self._clock.mono() - founderSession.joinedMono)
	end
	return {
		eventMult = self.modifiers.eventIncomeMult(company.sector),
		allianceMult = self.modifiers.allianceMult(company.founderId),
		sessionSeconds = sessionSeconds,
	}
end

-- Ingresos por segundo (total cobrado y sostenido) de cualquier empresa.
function World.incomeOf(self: World, company: any): Income.Breakdown
	if company.isNpc then
		local sustained = self:npcSustainedIncome(company)
		local event = self.modifiers.eventIncomeMult(company.sector)
		return {
			base = sustained,
			flat = 0,
			mult = 1,
			mechanic = 1,
			event = event,
			alliance = 1,
			sustained = sustained,
			total = math.min(Balance.MaxIncomePerSecond, sustained * event),
		}
	end
	return Income.compute(company, self:incomeContext(company))
end

-- Valoración de referencia para PRECIOS (jugadores: con hype; Bolsa: fundamental).
function World.valuationOf(self: World, company: any): number
	local income = self:incomeOf(company)
	if company.isNpc then
		return Valuation.fundamental(company.sector, income.sustained)
	end
	return Valuation.market(
		company.sector,
		income.sustained,
		self._clock.unix(),
		self.modifiers.eventHypeBonus(company.sector)
	)
end

-- Valor de la participación `bps` de una empresa.
function World.stakeValue(self: World, company: any, bps: number): number
	return Valuation.stake(self:valuationOf(company), bps)
end

-- Patrimonio neto de una sesión: Cash + participaciones (a valor de mercado si la empresa está cargada).
function World.netWorth(self: World, session: Session): number
	local total = Money.sanitize(session.data.cash)
	for _, company in self.companies do
		local stake = company.cap.holders[session.id]
		if stake then
			total += self:stakeValue(company, stake)
		end
	end
	for _, npc in self.npcs do
		local stake = npc.cap.holders[session.id]
		if stake then
			total += self:stakeValue(npc, stake)
		end
	end
	-- Participaciones en empresas de jugadores que no están cargadas: último valor conocido.
	for id, holding in session.data.holdings do
		if self.companies[id] == nil and self.npcs[id] == nil then
			total += Money.sanitize(holding.valueHint or 0)
		end
	end
	return math.min(Money.MAX, total)
end

return World
