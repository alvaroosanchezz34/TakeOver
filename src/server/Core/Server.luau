--!strict
--[[
	Raíz de composición del servidor: une los módulos puros y gestiona el ciclo de vida del jugador.
	NO usa APIs de Roblox directamente; todo lo externo entra por `Deps` (DataStore, red, tiempo,
	expulsión). Así la partida completa se simula en los tests y la capa de Roblox queda fina.

	Flujo:
	  playerAdded    -> carga el perfil (con bloqueo de sesión), crea la sesión y la empresa inicial
	  tick(dt)       -> bucle económico + mantenimiento (eventos, caducidad de ofertas, rankings,
	                    sincronización con clientes, autoguardado)
	  dispatch       -> peticiones del cliente (validadas, con límites)
	  playerRemoving -> cancela ofertas, devuelve la Bolsa, guarda y libera el bloqueo
	  shutdown       -> guarda a todos (BindToClose)
]]

local Shared = game:GetService("ReplicatedStorage").Shared

local Balance = require(Shared.Config.Balance)
local Catalog = require(Shared.Economy.Catalog)
local Cosmetics = require(Shared.Config.Monetization)
local Ownership = require(Shared.Economy.Ownership)
local ProgressionConfig = require(Shared.Config.Progression)
local Result = require(Shared.Util.Result)
local Sectors = require(Shared.Config.Sectors)

local Actions = require(script.Parent.Actions)
local Alliances = require(script.Parent.Alliances)
local Analytics = require(script.Parent.Analytics)
local CompanyOps = require(script.Parent.CompanyOps)
local Dispatcher = require(script.Parent.Dispatcher)
local EventDirector = require(script.Parent.EventDirector)
local IncomeEngine = require(script.Parent.IncomeEngine)
local Leaderboard = require(script.Parent.Leaderboard)
local Ledger = require(script.Parent.Ledger)
local OfferBook = require(script.Parent.OfferBook)
local Progression = require(script.Parent.Progression)
local Session = require(script.Parent.Session)
local TradeEngine = require(script.Parent.TradeEngine)
local Views = require(script.Parent.Views)
local World = require(script.Parent.World)

type SessionT = World.Session

export type Deps = {
	clock: { unix: () -> number, mono: () -> number },
	rng: Random,
	store: any, -- ProfileStore
	push: (userId: number, message: { [string]: any }) -> (),
	kick: (userId: number, code: string) -> (),
	spawn: (fn: (...any) -> (), ...any) -> (),
	wait: (seconds: number) -> (),
	analyticsSink: Analytics.Sink?,
	log: ((string) -> ())?,
}

local Server = {}
Server.__index = Server

export type Server = typeof(setmetatable({} :: { [string]: any }, Server))

local INCOME_REASONS: { [string]: boolean } = { income = true, dividend = true }
function Server.new(deps: Deps): Server
	local self = setmetatable({}, Server) :: any
	self.deps = deps
	self.clock = deps.clock
	self.log = deps.log or function() end
	self.store = deps.store
	self._present = {} :: { [number]: boolean }
	self.rankings = nil :: Leaderboard.Result?
	self._lastRank = 0
	self._lastLeader = nil :: string?

	local function touch(session: SessionT)
		deps.store:touch(session.profile)
	end
	self.touch = touch

	self.events = EventDirector.new(deps.clock, deps.rng)
	self.alliances = Alliances.new(deps.clock, function(id: string)
		return self.world.sessions[id] ~= nil
	end)
	self.world = World.new(deps.clock, {
		eventIncomeMult = function(sector)
			return self.events:incomeMult(sector)
		end,
		eventDiscount = function(sector)
			return self.events:discount(sector)
		end,
		eventHypeBonus = function(sector)
			return self.events:hypeBonus(sector)
		end,
		allianceMult = function(userId)
			return self.alliances:multiplierFor(userId)
		end,
	})
	self.ledger = Ledger.new(touch)
	self.ops = CompanyOps.new({ world = self.world, ledger = self.ledger, clock = deps.clock, touch = touch })
	self.offers = OfferBook.new(deps.clock)
	self.trade = TradeEngine.new({
		world = self.world,
		ledger = self.ledger,
		offers = self.offers,
		clock = deps.clock,
		touch = touch,
	})
	self.engine = IncomeEngine.new({ world = self.world, ledger = self.ledger, touch = touch })
	self.progression =
		Progression.new({ world = self.world, ledger = self.ledger, clock = deps.clock, touch = touch })
	self.analytics = Analytics.new(deps.clock, deps.analyticsSink)

	-- Observador del libro mayor: sincroniza al cliente y alimenta la analítica económica.
	self.ledger:observe(function(change)
		local session = change.session
		if INCOME_REASONS[change.reason] then
			session.incomeAccum = (session.incomeAccum or 0) + change.delta
		else
			session.viewDirty = true
			if change.reason ~= "rollback" and change.delta ~= 0 then
				self.analytics:economy(
					session.userId,
					if change.delta > 0 then "source" else "sink",
					math.abs(change.delta),
					change.balance,
					change.reason
				)
			end
		end
	end)

	self.dispatcher = Dispatcher.new({
		clock = deps.clock,
		actions = Actions.build(self),
		getSession = function(userId: number)
			return self.world.sessions[tostring(userId)]
		end,
		onAbuse = function(userId: number, reason: string)
			self.log(("[Server] expulsando a %d por abuso: %s"):format(userId, reason))
			self.analytics:track(userId, "kicked_abuse", { reason = "protocol" })
			deps.kick(userId, "ABUSE")
		end,
		log = self.log,
	})
	self._lastRankingMono = -1e9
	self._shuttingDown = false
	return self
end

-- ───────────── Comunicación con clientes ─────────────

function Server.notify(self: any, userId: number, kind: string, params: { [string]: any }?)
	self.deps.push(userId, { type = "notify", kind = kind, params = params or {}, t = self.clock.unix() })
end

function Server.broadcast(self: any, message: { [string]: any })
	for _, session in self.world.sessions do
		self.deps.push(session.userId, message)
	end
end

function Server.pushState(self: any, session: SessionT?)
	if session == nil or not session.active then
		return
	end
	session.viewDirty = false
	session.lastPushMono = self.clock.mono()
	self.deps.push(session.userId, self:buildState(session))
end

function Server.pushOffers(self: any, userId: string)
	local session = self.world.sessions[userId]
	if session then
		self.deps.push(session.userId, self:buildOffers(session))
	end
end

function Server.onFailure(self: any, session: SessionT, action: string, r: any)
	local code = r.code
	if code == "INTERNAL" then
		self.analytics:track(session.userId, "economy_error", { action = action, code = code })
		return
	end
	self.analytics:track(session.userId, "action_failed", { action = action, code = code })
end

-- ───────────── Construcción de vistas ─────────────

function Server.buildOffers(self: any, session: SessionT): { [string]: any }
	local now = self.clock.mono()
	local function view(offer: any, counterpartId: string)
		local company = self.world.companies[offer.companyId]
		local counterpart = self.world.sessions[counterpartId]
		return {
			id = offer.id,
			companyId = offer.companyId,
			companyName = company and company.name or "?",
			sector = company and company.sector or "commerce",
			counterpartId = counterpartId,
			counterpartName = counterpart and counterpart.name or "?",
			bps = offer.bps,
			price = offer.price,
			fairPrice = company and self.world:stakeValue(company, offer.bps) or 0,
			expiresIn = math.max(0, math.ceil(offer.expiresMono - now)),
			needsConfirm = offer.price >= Balance.BigDealConfirmCash,
		}
	end
	local incoming, outgoing = {}, {}
	for _, o in self.offers:pendingFor(session.id, "seller") do
		table.insert(incoming, view(o, o.buyerId))
	end
	for _, o in self.offers:pendingFor(session.id, "buyer") do
		table.insert(outgoing, view(o, o.sellerId))
	end
	return { type = "offers", incoming = incoming, outgoing = outgoing }
end

function Server.buildState(self: any, session: SessionT): { [string]: any }
	local world = self.world
	local data = session.data
	local companies = {}
	for _, company in world.companies do
		local myBps = Ownership.stake(company.cap, session.id)
		if myBps > 0 then
			local detail = Views.companyBrief(world, company)
			detail.myBps = myBps
			detail.manages = Ownership.manager(company.cap, company.founderId) == session.id
			if detail.manages then
				detail.options = Views.options(world, company, data.cash)
			end
			table.insert(companies, detail)
		end
	end
	table.sort(companies, function(a, b)
		if a.manages ~= b.manages then
			return a.manages
		end
		return a.id < b.id
	end)

	local position = self.rankings and self.rankings.positions[session.id]
	local owned = 0
	for _, c in data.companies do
		if c.founderId == session.id then
			owned += 1
		end
	end
	local sectors = {}
	for _, id in Sectors.order do
		local def = assert(Catalog.sector(id), "sector sin definición")
		table.insert(sectors, {
			id = id,
			cost = def.foundingCost,
			needEarned = def.unlockTotalEarned,
			unlocked = (data.stats.totalEarned or 0) >= def.unlockTotalEarned,
		})
	end

	local mates = {}
	for _, id in self.alliances:membersOf(session.id) do
		local s = world.sessions[id]
		if s then
			table.insert(mates, { id = id, name = s.name })
		end
	end
	local invites = {}
	for _, inv in self.alliances:pendingFor(session.id) do
		local from = world.sessions[inv.fromId]
		table.insert(invites, {
			id = inv.id,
			fromId = inv.fromId,
			fromName = from and from.name or "?",
			expiresIn = math.max(0, math.ceil(inv.expiresMono - self.clock.mono())),
		})
	end

	local owners = {}
	for id, v in data.cosmetics.owned do
		if v then
			table.insert(owners, id)
		end
	end
	table.sort(owners)

	return {
		type = "state",
		t = self.clock.unix(),
		userId = session.id,
		cash = data.cash,
		incomePerSecond = Views.round2(Views.incomeRate(world, session)),
		netWorth = position and position.netWorth or world:netWorth(session),
		rank = position
				and { pos = position.playerRank, count = position.playerCount, badge = position.badge }
			or { pos = 1, count = 1, badge = Leaderboard.badgeFor(data.cash) },
		companies = companies,
		portfolio = Views.portfolio(world, session),
		recommended = Views.recommended(world, session),
		tutorial = {
			step = data.tutorial.step,
			total = #ProgressionConfig.TutorialSteps,
			done = data.tutorial.done,
			skipped = data.tutorial.skipped,
			stepId = if ProgressionConfig.TutorialSteps[data.tutorial.step]
				then ProgressionConfig.TutorialSteps[data.tutorial.step].id
				else nil,
		},
		daily = self.progression:dailyStatus(session),
		titles = { selected = data.titles.selected, available = self.progression:availableTitles(session) },
		achievements = data.achievements,
		settings = data.settings,
		cosmetics = {
			equipped = data.cosmetics.equipped,
			owned = owners,
			consumables = data.cosmetics.consumables,
		},
		alliance = {
			members = mates,
			multiplier = Views.round2(self.alliances:multiplierFor(session.id)),
			invites = invites,
		},
		event = self.events:snapshot(),
		founding = { owned = owned, max = Balance.MaxOwnedCompanies, sectors = sectors },
		stats = {
			totalEarned = data.stats.totalEarned,
			upgradesBought = data.stats.upgradesBought,
			dealsClosed = data.stats.dealsClosed,
			offersMade = data.stats.offersMade,
			peakNetWorth = data.stats.peakNetWorth,
			playSeconds = math.floor(data.stats.playSeconds or 0),
			sessions = data.stats.sessions,
		},
		monetization = self:_shopView(),
	}
end

-- Sólo los productos activos (ID configurado). Con ID 0 la tienda aparece vacía.
function Server._shopView(_self: any): { [string]: any }
	local passes, products = {}, {}
	local passDefs: { [string]: any } = Cosmetics.GamePasses
	local productDefs: { [string]: any } = Cosmetics.DeveloperProducts
	for _, p in passDefs do
		if p.id ~= 0 then
			table.insert(passes, { key = p.key, id = p.id, nameKey = p.nameKey, descKey = p.descKey })
		end
	end
	for _, p in productDefs do
		if p.id ~= 0 then
			table.insert(products, { key = p.key, id = p.id, nameKey = p.nameKey, descKey = p.descKey })
		end
	end
	table.sort(passes, function(a, b)
		return a.key < b.key
	end)
	table.sort(products, function(a, b)
		return a.key < b.key
	end)
	return { passes = passes, products = products }
end

function Server.buildMarket(self: any, session: SessionT): { [string]: any }
	local world = self.world
	local list = {}
	for _, company in world.companies do
		local brief = Views.companyBrief(world, company)
		brief.myBps = Ownership.stake(company.cap, session.id)
		brief.fairPer1Pct = world:stakeValue(company, Balance.LotBps)
		table.insert(list, brief)
	end
	for _, id in world.npcOrder do
		local npc = world.npcs[id]
		local brief = Views.companyBrief(world, npc)
		brief.myBps = Ownership.stake(npc.cap, session.id)
		local ask, bid = self.trade:marketQuote(npc, Balance.LotBps)
		brief.ask1Pct, brief.bid1Pct = ask, bid
		brief.floatLeftBps = math.max(0, Balance.Npc.FloatCapBps - self.trade:floatBps(npc))
		brief.playerCapBps = Balance.Npc.PerPlayerCapBps
		table.insert(list, brief)
	end
	table.sort(list, function(a, b)
		if a.valuation ~= b.valuation then
			return a.valuation > b.valuation
		end
		return a.id < b.id
	end)
	local players = {}
	for id, s in world.sessions do
		table.insert(players, {
			id = id,
			name = s.name,
			badge = self.rankings and self.rankings.positions[id] and self.rankings.positions[id].badge
				or "startup",
		})
	end
	table.sort(players, function(a, b)
		return a.id < b.id
	end)
	return {
		companies = list,
		players = players,
		deals = self.offers:recentDeals(10),
		offers = self:buildOffers(session),
		rules = {
			minPriceRatio = Balance.MinPriceRatio,
			maxPriceRatio = Balance.MaxPriceRatio,
			saleTaxBps = Balance.SaleTaxBps,
			lotBps = Balance.LotBps,
			expirySeconds = Balance.OfferExpirySeconds,
			bigDealCash = Balance.BigDealConfirmCash,
		},
	}
end

function Server.buildLeaderboard(self: any): { [string]: any }
	local r = self.rankings
	if r == nil then
		r = Leaderboard.compute(self.world, 10)
		self.rankings = r
	end
	return { type = "leaderboard", companies = r.companies, players = r.players }
end

-- ───────────── Acciones compuestas ─────────────

-- Sincroniza logros y estado de progreso tras una acción del jugador.
function Server.onProgress(self: any, session: SessionT)
	local ranking = self.rankings and self.rankings.positions[session.id]
	local unlocked = self.progression:checkAchievements(session, ranking)
	for _, id in unlocked do
		self:notify(session.userId, "achievement", { id = id })
		self.analytics:track(session.userId, "achievement", { code = id })
	end
	local tut = session.data.tutorial
	if tut.done and not session.tutorialReported then
		session.tutorialReported = true
		if tut.bonusPaid and not tut.skipped then
			self.analytics:funnel(session.userId, 6)
			self:notify(session.userId, "tutorial_done", { reward = Balance.TutorialBonusCash })
		end
	end
end

function Server.acceptOffer(
	self: any,
	seller: SessionT,
	offerId: string,
	confirm: boolean
): Result.Result<any>
	local world = self.world
	local offer = self.offers:get(offerId)
	local r = self.trade:acceptOffer(seller, offerId, confirm)
	if not r.ok then
		self:onFailure(seller, "accept_offer", r)
		-- Las ofertas cerradas por fallo se reflejan en ambas partes.
		if offer then
			self:pushOffers(offer.buyerId)
			self:pushOffers(offer.sellerId)
			local buyer = world.sessions[offer.buyerId]
			if
				buyer
				and r.code ~= "INSUFFICIENT_FUNDS"
				and r.code ~= "CONFIRMATION_REQUIRED"
				and r.code ~= "NOT_YOUR_OFFER"
			then
				self:notify(buyer.userId, "offer_failed", { code = r.code })
			end
		end
		return r
	end

	local deal = r.value
	local buyer = world.sessions[deal.buyerId]
	self.analytics:track(
		seller.userId,
		"offer_accepted",
		{ bps = deal.bps, price = deal.price, controlChanged = deal.controlChanged }
	)
	if buyer then
		self.analytics:track(buyer.userId, "deal_closed", { bps = deal.bps, price = deal.price })
	end
	self:notify(seller.userId, "deal_closed", {
		buyer = buyer and buyer.name or "?",
		company = deal.companyName,
		bps = deal.bps,
		received = deal.sellerReceives,
	})
	if buyer then
		self:notify(buyer.userId, "offer_accepted", {
			seller = seller.name,
			company = deal.companyName,
			bps = deal.bps,
			price = deal.price,
		})
	end

	if deal.controlChanged then
		local manager = world.sessions[deal.newManager]
		self:broadcast({
			type = "effect",
			kind = "takeover",
			company = deal.companyName,
			who = manager and manager.name or "?",
			effect = manager and manager.data.cosmetics.equipped.effect or "",
		})
		if manager then
			self:notify(manager.userId, "control_gained", { company = deal.companyName })
		end
		local founder =
			world.sessions[deal.companyId and world.companies[deal.companyId] and world.companies[deal.companyId].founderId or ""]
		if founder and founder ~= manager then
			self:notify(founder.userId, "control_lost", { company = deal.companyName })
		end
	elseif deal.price >= Balance.BigDealConfirmCash then
		self:broadcast({
			type = "effect",
			kind = "deal",
			company = deal.companyName,
			who = buyer and buyer.name or "?",
			effect = "",
		})
	end

	self:saveSoon(deal.touched)
	-- Todas las partes afectadas y el resto de ofertas del libro.
	for _, s in deal.touched do
		self:onProgress(s)
		self:pushState(s)
	end
	for _, o in self.offers:pending() do
		self:pushOffers(o.buyerId)
		self:pushOffers(o.sellerId)
	end
	self:pushOffers(deal.buyerId)
	self:pushOffers(deal.sellerId)
	self.rankings = nil -- se recalcula en el siguiente mantenimiento
	self._lastRankingMono = -1e9
	return Result.ok({
		price = deal.price,
		tax = deal.tax,
		received = deal.sellerReceives,
		controlChanged = deal.controlChanged,
	})
end

-- ───────────── Guardado ─────────────

function Server._save(self: any, session: SessionT, release: boolean): Result.Result<nil>
	local r = self.store:save(session.profile, release)
	if not r.ok then
		if r.code == "LOCK_LOST" then
			self.log("[Server] bloqueo perdido de " .. session.id)
			self.deps.kick(session.userId, "DATA_LOCK_LOST")
		elseif r.code ~= "SAVE_IN_PROGRESS" then
			self.analytics:track(session.userId, "economy_error", { action = "save", code = r.code })
		end
	end
	return r
end

-- Guardado inmediato de un jugador (p. ej. antes de confirmar una compra con Robux).
function Server.save(self: any, session: SessionT, release: boolean?): Result.Result<nil>
	return self:_save(session, release == true)
end

-- Guarda ya (en un hilo aparte) a las partes de una operación importante.
function Server.saveSoon(self: any, sessions: { SessionT })
	for _, s in sessions do
		if s.active and s.profile.active then
			self.deps.spawn(function()
				self:_save(s, false)
			end)
		end
	end
end

-- ───────────── Ciclo de vida del jugador ─────────────

function Server.playerAdded(self: any, userId: number, name: string): Result.Result<SessionT>
	local id = tostring(userId)
	if self.world.sessions[id] ~= nil then
		return Result.err("ALREADY_JOINED")
	end
	self._present[userId] = true
	local loaded = self.store:load("Player_" .. id)
	if not loaded.ok then
		self.analytics:track(userId, "load_failed", { code = loaded.code })
		return loaded :: any
	end
	local profile = loaded.value
	if not self._present[userId] then
		-- Se fue mientras cargaba: liberar el bloqueo sin crear sesión.
		self.store:save(profile, true)
		return Result.err("LEFT_DURING_LOAD")
	end

	local session = Session.new(userId, name, profile, self.clock)
	session.viewDirty = true
	session.incomeAccum = 0
	local data = session.data
	data.stats.sessions += 1
	data.meta.lastJoin = self.clock.unix()

	self.world:addSession(session)
	self.ops:ensureStarterCompany(session)

	-- Nombres visibles y valor conocido de las participaciones en empresas ajenas.
	for _, company in self.world.companies do
		if company.names and company.names[session.id] ~= nil and company.names[session.id] ~= name then
			company.names[session.id] = name
		end
		if company.founderId == session.id then
			company.names = company.names or {}
			company.names[session.id] = name
		end
	end

	for _, liquidation in self.trade:restoreMarketStakes(session) do
		self:notify(
			userId,
			"market_liquidation",
			{ company = liquidation.companyId, cash = liquidation.cash }
		)
	end

	self.analytics:sessionStart(userId)
	self.analytics:track(userId, "session_start", { count = data.stats.sessions })
	self.touch(session)

	self:_refreshRankings()
	self:pushState(session)
	self.deps.push(userId, self:buildLeaderboard())
	self.deps.push(userId, { type = "event", event = self.events:snapshot() })
	self.deps.push(userId, self:buildOffers(session))
	return Result.ok(session)
end

function Server.playerRemoving(self: any, userId: number)
	self._present[userId] = false
	local id = tostring(userId)
	local session = self.world.sessions[id]
	if session == nil then
		return
	end
	session.active = false

	local holdersToRefresh: { [string]: boolean } = {}
	for _, company in session.data.companies do
		for holder in company.cap.holders do
			holdersToRefresh[holder] = true
		end
	end

	local removed = self.world:removeSession(id)
	local cancelled = self.trade:onPlayerLeft(id, removed)
	for _, offer in cancelled do
		local other = if offer.buyerId == id then offer.sellerId else offer.buyerId
		local otherSession = self.world.sessions[other]
		if otherSession then
			self:notify(otherSession.userId, "offer_cancelled", { reason = offer.reason })
			self:pushOffers(other)
		end
	end
	self.trade:releaseMarketStakes(session)

	for _, mate in self.alliances:onPlayerLeft(id) do
		local m = self.world.sessions[mate]
		if m then
			self:notify(m.userId, "alliance_left", { name = session.name })
			m.viewDirty = true
		end
	end
	for holder in holdersToRefresh do
		local s = self.world.sessions[holder]
		if s then
			s.viewDirty = true
		end
	end

	self.dispatcher:onPlayerLeft(userId)
	self.analytics:sessionEnd(userId, session.data.stats.playSeconds or 0)

	local saved = self:_save(session, true)
	if not saved.ok then
		self.log(("[Server] no se pudo guardar a %s al salir: %s"):format(id, saved.code))
		-- Sin liberar el bloqueo caducará por sí solo; el último autoguardado conserva el progreso.
	end
	self.rankings = nil
end

-- ───────────── Bucle ─────────────

function Server._refreshRankings(self: any)
	self.rankings = Leaderboard.compute(self.world, 10)
	self._lastRankingMono = self.clock.mono()
	for id, session in self.world.sessions do
		-- Valor conocido de las participaciones de este jugador en empresas cargadas.
		for companyId, holding in session.data.holdings do
			local company = self.world:getCompany(companyId)
			if company then
				holding.valueHint = self.world:stakeValue(company, holding.bps)
			end
		end
		local pos = self.rankings.positions[id]
		if pos then
			if session.lastBadge ~= nil and session.lastBadge ~= pos.badge then
				local order = {}
				for i, rank in Balance.Ranks do
					order[rank.id] = i
				end
				if order[pos.badge] > order[session.lastBadge] then
					self:notify(session.userId, "rank_up", { badge = pos.badge })
					if order[pos.badge] >= order["magnate"] then
						self:broadcast({
							type = "effect",
							kind = "new_magnate",
							who = session.name,
							effect = "",
						})
					end
				end
			end
			session.lastBadge = pos.badge
		end
	end
	-- Nuevo número uno del servidor (con al menos dos jugadores).
	local top = self.rankings.players[1]
	if top and #self.rankings.players >= 2 and self._lastLeader ~= nil and self._lastLeader ~= top.userId then
		self:broadcast({ type = "effect", kind = "new_number_one", who = top.name, effect = "" })
	end
	self._lastLeader = top and top.userId or nil
end

function Server._maintenance(self: any)
	local now = self.clock.mono()
	local world = self.world

	for _, tr in self.events:update() do
		if tr.kind == "announce" then
			self:broadcast({ type = "event", event = self.events:snapshot() })
			for _, s in world.sessions do
				self:notify(
					s.userId,
					"event_announce",
					{ id = tr.id, seconds = self.events:snapshot().startsIn }
				)
			end
		elseif tr.kind == "start" then
			self:broadcast({ type = "event", event = self.events:snapshot() })
			for _, s in world.sessions do
				self:notify(s.userId, "event_start", { id = tr.id })
				s.viewDirty = true
			end
		else
			self:broadcast({ type = "event", event = self.events:snapshot() })
			for _, s in world.sessions do
				self:notify(s.userId, "event_end", { id = tr.id })
				s.viewDirty = true
			end
		end
	end

	for _, offer in self.trade:sweep() do
		local company = world.companies[offer.companyId]
		for _, uid in { offer.buyerId, offer.sellerId } do
			local s = world.sessions[uid]
			if s then
				self:notify(s.userId, "offer_expired", { company = company and company.name or "?" })
				self:pushOffers(uid)
			end
		end
	end
	self.alliances:sweep()

	if now - self._lastRankingMono >= Balance.RankingRefreshSeconds then
		self:_refreshRankings()
		self:broadcast(self:buildLeaderboard())
		for _, s in world.sessions do
			self:onProgress(s)
		end
	end

	for _, s in world.sessions do
		if s.viewDirty or now - (s.lastPushMono or -1e9) >= Balance.SnapshotResyncSeconds then
			self:pushState(s)
		end
		local profile = s.profile
		local due = profile.dirty and now - profile.lastSaveAt >= Balance.AutosaveSeconds
		local heartbeat = now - profile.lastSaveAt >= 120
		if (due or heartbeat) and not profile.saving and profile.active then
			if (s.incomeAccum or 0) > 0 then
				self.analytics:economy(s.userId, "source", math.floor(s.incomeAccum), s.data.cash, "income")
				s.incomeAccum = 0
			end
			self.deps.spawn(function()
				self:_save(s, false)
			end)
		end
	end
end

function Server.tick(self: any, dt: number)
	if self._shuttingDown then
		return
	end
	self.engine:tick(dt)
	for _, s in self.world.sessions do
		local advanced = self.progression:tick(s)
		if advanced then
			s.viewDirty = true
		end
	end
	local ok, err = pcall(function()
		self:_maintenance()
	end)
	if not ok then
		self.log("[Server] error en mantenimiento: " .. tostring(err))
	end
end

function Server.dispatch(self: any, userId: number, action: any, payload: any)
	return self.dispatcher:dispatch(userId, action, payload)
end

-- BindToClose: guarda y libera a todos los jugadores.
function Server.shutdown(self: any)
	self._shuttingDown = true
	local pending = 0
	for _, session in self.world.sessions do
		pending += 1
		self.deps.spawn(function()
			session.active = false
			self.trade:releaseMarketStakes(session)
			self:_save(session, true)
			pending -= 1
		end)
	end
	local waited = 0
	while pending > 0 and waited < 25 do
		self.deps.wait(0.25)
		waited += 0.25
	end
end

return Server
