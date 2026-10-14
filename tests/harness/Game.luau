--!nocheck
--[[
	Partida de pruebas: ensambla los módulos REALES del servidor con un reloj falso y
	perfiles simulados (sin DataStore). Cada servicio nuevo se añade aquí para que todos los
	specs compartan el mismo montaje.
]]

local Game = {}
Game.__index = Game

function Game.new(load, options)
	options = options or {}
	local Clock = load:shared("Util/Clock")
	local PlayerData = load:server("Core/PlayerData")
	local World = load:server("Core/World")
	local Ledger = load:server("Core/Ledger")
	local CompanyOps = load:server("Core/CompanyOps")
	local IncomeEngine = load:server("Core/IncomeEngine")
	local Session = load:server("Core/Session")
	local OfferBook = load:server("Core/OfferBook")
	local TradeEngine = load:server("Core/TradeEngine")

	local self = setmetatable({}, Game)
	self.load = load
	self.clock = Clock.fake(options.unix)
	self.touches = {}
	self.PlayerData = PlayerData
	self.SessionModule = Session

	local function touch(session)
		session.profile.rev += 1
		session.profile.dirty = true
		self.touches[session.id] = (self.touches[session.id] or 0) + 1
	end
	self.touch = touch

	self.world = World.new(self.clock, options.modifiers)
	self.ledger = Ledger.new(touch)
	self.ops = CompanyOps.new({ world = self.world, ledger = self.ledger, clock = self.clock, touch = touch })
	self.engine = IncomeEngine.new({ world = self.world, ledger = self.ledger, touch = touch })
	self.offers = OfferBook.new(self.clock)
	self.fault = nil -- function(stage) para inyectar fallos en el motor de comercio
	self.trade = TradeEngine.new({
		world = self.world,
		ledger = self.ledger,
		offers = self.offers,
		clock = self.clock,
		touch = touch,
		fault = function(stage)
			if self.fault then
				self.fault(stage)
			end
		end,
	})
	self.changes = {}
	self.ledger:observe(function(change)
		table.insert(self.changes, change)
	end)
	return self
end

-- Añade un jugador con perfil simulado y su empresa inicial.
function Game:addPlayer(userId, name, mutate)
	local data = self.PlayerData.template(self.clock.unix())
	data.stats.playSeconds = 10_000 -- cuenta con antigüedad suficiente para comerciar
	if mutate then
		mutate(data)
	end
	local profile = { key = tostring(userId), data = data, dirty = false, rev = 0, active = true }
	local session = self.SessionModule.new(userId, name or ("P" .. userId), profile, self.clock)
	self.world:addSession(session)
	self.ops:ensureStarterCompany(session)
	return session
end

function Game:removePlayer(session)
	session.active = false
	return self.world:removeSession(session.id)
end

-- Avanza `seconds` en ticks de 1 s.
function Game:run(seconds, dt)
	dt = dt or 1
	local steps = math.floor(seconds / dt + 1e-9)
	for _ = 1, steps do
		self.clock:advance(dt)
		self.engine:tick(dt)
	end
end

function Game:cash(session)
	return session.data.cash
end

function Game:companyOf(session, index)
	return session.data.companies[session.id .. ":" .. (index or 1)]
end

-- Suma de Cash de todas las sesiones (para pruebas de conservación).
function Game:totalCash()
	local total = 0
	for _, s in self.world.sessions do
		total += s.data.cash
	end
	return total
end

return Game
