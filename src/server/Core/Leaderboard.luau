--!strict
--[[
	Rankings del servidor: mayores empresas (por valoración de mercado) y mayor riqueza individual
	(patrimonio neto = Cash + participaciones). Ordenación determinista (desempate por id).
	El patrimonio máximo histórico se anota en las estadísticas del jugador.
]]

local Shared = game:GetService("ReplicatedStorage").Shared

local Balance = require(Shared.Config.Balance)
local Money = require(Shared.Economy.Money)
local Ownership = require(Shared.Economy.Ownership)

local World = require(script.Parent.World)

export type CompanyRow = {
	rank: number,
	id: string,
	name: string,
	sector: string,
	valuation: number,
	income: number,
	founderId: string,
	founderName: string,
	managerId: string,
	managerName: string,
}

export type PlayerRow = {
	rank: number,
	userId: string,
	name: string,
	netWorth: number,
	badge: string,
}

export type Position = { playerRank: number, playerCount: number, netWorth: number, badge: string }

export type Result = {
	companies: { CompanyRow },
	players: { PlayerRow },
	positions: { [string]: Position },
}

local Leaderboard = {}

-- Insignia de posición empresarial según el patrimonio neto.
function Leaderboard.badgeFor(netWorth: number): string
	local badge = Balance.Ranks[1].id
	for _, rank in Balance.Ranks do
		if netWorth >= rank.minNetWorth then
			badge = rank.id
		end
	end
	return badge
end

local function nameOf(world: World.World, userId: string): string
	local session = world.sessions[userId]
	if session then
		return session.name
	end
	if userId == Ownership.MARKET then
		return "Bolsa"
	end
	return "?"
end

function Leaderboard.compute(world: World.World, limit: number): Result
	local companies: { CompanyRow } = {}
	for _, company in world.companies do
		local manager = Ownership.manager(company.cap, company.founderId)
		table.insert(companies, {
			rank = 0,
			id = company.id,
			name = company.name,
			sector = company.sector,
			valuation = world:valuationOf(company),
			income = world:incomeOf(company).total,
			founderId = company.founderId,
			founderName = nameOf(world, company.founderId),
			managerId = manager,
			managerName = nameOf(world, manager),
		})
	end
	table.sort(companies, function(a, b)
		if a.valuation ~= b.valuation then
			return a.valuation > b.valuation
		end
		return a.id < b.id
	end)
	for i, row in companies do
		row.rank = i
	end

	local players: { PlayerRow } = {}
	for id, session in world.sessions do
		local nw = world:netWorth(session)
		session.data.stats.peakNetWorth =
			math.max(session.data.stats.peakNetWorth or 0, math.min(nw, Money.MAX))
		table.insert(
			players,
			{ rank = 0, userId = id, name = session.name, netWorth = nw, badge = Leaderboard.badgeFor(nw) }
		)
	end
	table.sort(players, function(a, b)
		if a.netWorth ~= b.netWorth then
			return a.netWorth > b.netWorth
		end
		return a.userId < b.userId
	end)
	local positions: { [string]: Position } = {}
	for i, row in players do
		row.rank = i
		positions[row.userId] =
			{ playerRank = i, playerCount = #players, netWorth = row.netWorth, badge = row.badge }
	end

	local topCompanies, topPlayers = {}, {}
	for i = 1, math.min(limit, #companies) do
		topCompanies[i] = companies[i]
	end
	for i = 1, math.min(limit, #players) do
		topPlayers[i] = players[i]
	end
	return { companies = topCompanies, players = topPlayers, positions = positions }
end

return Leaderboard
