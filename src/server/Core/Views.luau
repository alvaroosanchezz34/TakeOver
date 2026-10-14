--!strict
--[[
	Vistas: lo que el servidor deja ver a cada jugador. Principios:
	- Sólo datos de presentación; el cliente NUNCA calcula nada que tenga efecto económico.
	- Privacidad: del resto de jugadores solo se muestra lo PÚBLICO (nombre, empresas,
	  estructura de propiedad, valoración, patrimonio neto agregado). Nunca su Cash,
	  sus cuentas de dividendos pendientes ni ofertas que no les conciernan.
	- Todo es serializable por RemoteEvent: sin infinitos, NaN ni tablas mixtas.
]]

local Shared = game:GetService("ReplicatedStorage").Shared

local Balance = require(Shared.Config.Balance)
local Company = require(Shared.Economy.Company)
local Governance = require(Shared.Config.Governance)
local Ownership = require(Shared.Economy.Ownership)
local Pricing = require(Shared.Economy.Pricing)
local Valuation = require(Shared.Economy.Valuation)

local World = require(script.Parent.World)

local Views = {}

local function round2(x: number): number
	if x ~= x or x == math.huge or x == -math.huge then
		return 0
	end
	return math.floor(x * 100 + 0.5) / 100
end
Views.round2 = round2

function Views.holderName(world: World.World, company: any, id: string): string
	if id == Ownership.MARKET then
		return "MARKET"
	end
	local session = world.sessions[id]
	if session then
		return session.name
	end
	return (company.names and company.names[id]) or "?"
end

local function holdersList(
	world: World.World,
	company: any
): { { id: string, name: string, bps: number, online: boolean } }
	local out = {}
	for _, h in Ownership.holderList(company.cap) do
		table.insert(out, {
			id = h.id,
			name = Views.holderName(world, company, h.id),
			bps = h.bps,
			online = h.id == Ownership.MARKET or world.sessions[h.id] ~= nil,
		})
	end
	return out
end

-- Ficha pública de una empresa (la ve cualquiera).
function Views.companyBrief(world: World.World, company: any): { [string]: any }
	local income = world:incomeOf(company)
	local isNpc = company.isNpc == true
	local manager = if isNpc then Ownership.MARKET else Ownership.manager(company.cap, company.founderId)
	local hype = nil
	if not isNpc then
		hype = round2(
			Valuation.hype(
				company.sector,
				world._clock.unix(),
				world.modifiers.eventHypeBonus(company.sector)
			)
		)
	end
	return {
		id = company.id,
		name = company.name,
		sector = company.sector,
		isNpc = isNpc,
		level = company.level or 5,
		visualTier = if isNpc then 6 else Company.visualTier(company),
		logo = company.logo or { icon = 1, color = 1 },
		income = round2(income.total),
		valuation = world:valuationOf(company),
		hype = hype,
		founderId = company.founderId,
		founderName = Views.holderName(world, company, company.founderId),
		managerId = manager,
		managerName = Views.holderName(world, company, manager),
		holders = holdersList(world, company),
		rev = company.cap.rev,
	}
end

-- Opciones de inversión de una empresa (precio ya con descuentos, beneficio esperado, amortización).
function Views.options(world: World.World, company: any, cash: number): { { [string]: any } }
	local ctx = world:incomeContext(company)
	local options = Pricing.options(company, ctx, world.modifiers.eventDiscount(company.sector))
	local out = {}
	for _, o in options do
		table.insert(out, {
			kind = o.kind,
			id = o.id,
			nameKey = o.nameKey,
			icon = o.icon,
			effectKind = o.effectKind,
			effectValue = o.effectValue,
			currentLevel = o.currentLevel,
			maxLevel = o.maxLevel,
			maxed = o.maxed,
			cost = o.cost,
			missing = math.max(0, o.cost - cash),
			deltaIncome = round2(o.deltaIncome),
			paybackSeconds = if o.paybackSeconds == math.huge then nil else math.floor(o.paybackSeconds),
		})
	end
	return out
end

local HISTORY_PUBLIC = { trade = true, founded = true }

local function historyView(world: World.World, company: any, full: boolean): { { [string]: any } }
	local out = {}
	for i = #company.history, 1, -1 do
		local e = company.history[i]
		if full or HISTORY_PUBLIC[e.kind] then
			table.insert(out, {
				t = e.t,
				kind = e.kind,
				a = e.a and Views.holderName(world, company, e.a),
				b = e.b and Views.holderName(world, company, e.b),
				bps = e.bps,
				amount = e.amount,
				note = if e.kind == "upgrade" or e.kind == "level" then e.note else nil,
			})
			if #out >= 15 then
				break
			end
		end
	end
	return out
end

-- Detalle de una empresa para un espectador concreto (más información si es consejero o gestor).
function Views.companyDetail(world: World.World, company: any, viewer: World.Session): { [string]: any }
	local view = Views.companyBrief(world, company)
	local myBps = Ownership.stake(company.cap, viewer.id)
	local rights = if company.isNpc
		then { tier = Ownership.tier(myBps), dividends = myBps > 0, seesBooks = false, manages = false }
		else Ownership.rights(company.cap, viewer.id, company.founderId)
	view.myBps = myBps
	view.rights = rights
	view.history = historyView(world, company, rights.seesBooks)
	if rights.manages and not company.isNpc then
		view.options = Views.options(world, company, viewer.data.cash)
	end
	if rights.seesBooks and not company.isNpc then
		local b = world:incomeOf(company)
		view.books = {
			base = round2(b.base),
			flat = round2(b.flat),
			mult = round2(b.mult),
			mechanic = round2(b.mechanic),
			event = round2(b.event),
			alliance = round2(b.alliance),
			sustained = round2(b.sustained),
			total = round2(b.total),
		}
	end
	view.governance = {
		boardMinBps = Governance.BoardMinBps,
		controlMinBpsExclusive = Governance.ControlMinBpsExclusive,
		minManagerBps = Governance.MinManagerBps,
	}
	return view
end

-- Ingreso pasivo por segundo del jugador: su parte de todas las empresas cargadas.
function Views.incomeRate(world: World.World, session: World.Session): number
	local total = 0
	for _, company in world.companies do
		local bps = Ownership.stake(company.cap, session.id)
		if bps > 0 then
			total += world:incomeOf(company).total * bps / Balance.BpsTotal
		end
	end
	for _, npc in world.npcs do
		local bps = Ownership.stake(npc.cap, session.id)
		if bps > 0 then
			total += world:incomeOf(npc).total * Balance.Npc.PayoutRatio * bps / Balance.BpsTotal
		end
	end
	return total
end

-- Siguiente mejora recomendada entre todas las empresas que el jugador gestiona.
function Views.recommended(world: World.World, session: World.Session): { [string]: any }?
	local best: { [string]: any }? = nil
	local bestEta = math.huge
	local rate = math.max(Views.incomeRate(world, session), 0.01)
	local cash = session.data.cash
	for _, company in world.companies do
		if Ownership.manager(company.cap, company.founderId) == session.id then
			local ctx = world:incomeContext(company)
			local options = Pricing.options(company, ctx, world.modifiers.eventDiscount(company.sector))
			local pick = Pricing.recommended(options, cash, rate)
			if pick then
				local eta = math.max(0, pick.cost - cash) / rate
					+ (if pick.paybackSeconds == math.huge then 1e9 else pick.paybackSeconds)
				if best == nil or eta < bestEta then
					bestEta = eta
					best = {
						companyId = company.id,
						companyName = company.name,
						kind = pick.kind,
						id = pick.id,
						nameKey = pick.nameKey,
						icon = pick.icon,
						effectKind = pick.effectKind,
						effectValue = pick.effectValue,
						cost = pick.cost,
						missing = math.max(0, pick.cost - cash),
						deltaIncome = round2(pick.deltaIncome),
						paybackSeconds = if pick.paybackSeconds == math.huge
							then nil
							else math.floor(pick.paybackSeconds),
					}
				end
			end
		end
	end
	return best
end

-- Cartera: participaciones en empresas (propias o ajenas) con su valor actual.
function Views.portfolio(world: World.World, session: World.Session): { { [string]: any } }
	local out = {}
	local function push(company: any, bps: number)
		table.insert(out, {
			companyId = company.id,
			name = company.name,
			sector = company.sector,
			bps = bps,
			value = world:stakeValue(company, bps),
			founderName = Views.holderName(world, company, company.founderId),
			isNpc = company.isNpc == true,
			isOwn = company.founderId == session.id,
			online = true,
		})
	end
	local seen: { [string]: boolean } = {}
	for _, company in world.companies do
		local bps = Ownership.stake(company.cap, session.id)
		if bps > 0 then
			seen[company.id] = true
			push(company, bps)
		end
	end
	for _, npc in world.npcs do
		local bps = Ownership.stake(npc.cap, session.id)
		if bps > 0 then
			seen[npc.id] = true
			push(npc, bps)
		end
	end
	-- Participaciones en empresas cuyo fundador no está: último valor conocido.
	for id, h in session.data.holdings do
		if not seen[id] then
			table.insert(out, {
				companyId = id,
				name = h.name,
				sector = h.sector,
				bps = h.bps,
				value = h.valueHint or 0,
				founderName = h.founderName or "?",
				isNpc = false,
				isOwn = false,
				online = false,
			})
		end
	end
	table.sort(out, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.companyId < b.companyId
	end)
	return out
end

return Views
