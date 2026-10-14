--!strict
--[[
	Progresión: tutorial contextual, logros/títulos y recompensa diaria.

	- El tutorial avanza al REALIZAR la acción pedida (no leyendo texto) y se puede omitir.
	- Los logros sólo se conceden por condiciones comprobadas en el servidor.
	- La recompensa diaria usa el reloj del servidor (os.time): cambiar la hora del dispositivo
	  no sirve de nada. Está acotada (nunca más de 15 min de tus ingresos) y escala poco con la racha.
]]

local Shared = game:GetService("ReplicatedStorage").Shared

local Balance = require(Shared.Config.Balance)
local Config = require(Shared.Config.Progression)
local Catalog = require(Shared.Economy.Catalog)
local Ownership = require(Shared.Economy.Ownership)
local Result = require(Shared.Util.Result)

local Ledger = require(script.Parent.Ledger)
local World = require(script.Parent.World)

type Session = World.Session

export type Deps = {
	world: World.World,
	ledger: Ledger.Ledger,
	clock: { unix: () -> number, mono: () -> number },
	touch: (Session) -> (),
}

export type EventOutcome = { advanced: boolean, step: number, completed: boolean, reward: number }

local Progression = {}
Progression.__index = Progression

export type Progression = typeof(setmetatable({} :: { _d: Deps }, Progression))

function Progression.new(deps: Deps): Progression
	return setmetatable({ _d = deps }, Progression)
end

-- ───────────── Tutorial ─────────────

function Progression.tutorialStep(_self: Progression, session: Session): number
	return session.data.tutorial.step
end

function Progression.tutorialActive(_self: Progression, session: Session): boolean
	local tut = session.data.tutorial
	return not tut.done and not tut.skipped
end

--[[
	Notifica una acción real del jugador. Avanza el tutorial sólo si es el evento del paso actual.
	Al completar el último paso concede el bonus (una única vez).
]]
function Progression.event(self: Progression, session: Session, name: string): EventOutcome
	local tut = session.data.tutorial
	local outcome: EventOutcome = { advanced = false, step = tut.step, completed = false, reward = 0 }
	if tut.done or tut.skipped then
		return outcome
	end
	local def = Config.TutorialSteps[tut.step]
	if def == nil or def.event ~= name then
		return outcome
	end

	tut.step += 1
	outcome.advanced = true
	outcome.step = tut.step
	session.stepStartedMono = self._d.clock.mono()
	if tut.step > #Config.TutorialSteps then
		tut.done = true
		outcome.completed = true
		if not tut.bonusPaid then
			tut.bonusPaid = true
			local paid =
				self._d.ledger:credit(session, Balance.TutorialBonusCash, "reward", { source = "tutorial" })
			if paid.ok then
				outcome.reward = Balance.TutorialBonusCash
			end
		end
	end
	self._d.touch(session)
	return outcome
end

-- El paso "ver cómo suben los ingresos" avanza solo unos segundos después del anterior.
function Progression.tick(self: Progression, session: Session): EventOutcome?
	local tut = session.data.tutorial
	if tut.done or tut.skipped then
		return nil
	end
	local def = Config.TutorialSteps[tut.step]
	if def ~= nil and def.event == "income_seen" then
		local started = session.stepStartedMono
		if started == nil then
			session.stepStartedMono = self._d.clock.mono()
		elseif self._d.clock.mono() - started >= 6 then
			return self:event(session, "income_seen")
		end
	end
	return nil
end

function Progression.skipTutorial(self: Progression, session: Session)
	local tut = session.data.tutorial
	if not tut.done then
		tut.skipped = true
		self._d.touch(session)
	end
end

-- ───────────── Logros ─────────────

local function distinctSectors(session: Session): number
	local seen: { [string]: boolean } = {}
	local n = 0
	for _, company in session.data.companies do
		if
			company.founderId == session.id
			and not seen[company.sector]
			and Catalog.sector(company.sector)
		then
			seen[company.sector] = true
			n += 1
		end
	end
	return n
end

function Progression.checkAchievements(
	self: Progression,
	session: Session,
	ranking: { playerRank: number, playerCount: number }?
): { string }
	local d = self._d
	local data = session.data
	local unlocked: { string } = {}
	local function grant(id: string, condition: boolean)
		if condition and data.achievements[id] == nil then
			data.achievements[id] = d.clock.unix()
			table.insert(unlocked, id)
		end
	end

	grant("first_upgrade", (data.stats.upgradesBought or 0) >= 1)
	grant("first_deal", (data.stats.dealsClosed or 0) >= 1)

	local takeover = false
	for _, company in d.world.companies do
		if
			company.founderId ~= session.id
			and Ownership.manager(company.cap, company.founderId) == session.id
		then
			takeover = true
			break
		end
	end
	grant("first_takeover", takeover)
	grant("diversified", distinctSectors(session) >= 3)

	local stakes = 0
	for _ in data.holdings do
		stakes += 1
	end
	grant("shareholder", stakes >= Config.ShareholderMinCompanies)
	grant("millionaire", d.world:netWorth(session) >= Config.MillionaireNetWorth)
	grant("number_one", ranking ~= nil and ranking.playerRank == 1 and ranking.playerCount >= 2)

	if #unlocked > 0 then
		d.touch(session)
	end
	return unlocked
end

-- Los títulos disponibles = logros conseguidos + títulos comprados.
function Progression.availableTitles(_self: Progression, session: Session): { string }
	local out: { string } = {}
	for id in session.data.achievements do
		table.insert(out, id)
	end
	for id, owned in session.data.cosmetics.owned do
		if owned and string.sub(id, 1, 6) == "title:" then
			table.insert(out, string.sub(id, 7))
		end
	end
	table.sort(out)
	return out
end

function Progression.selectTitle(self: Progression, session: Session, titleId: string): Result.Result<nil>
	if titleId ~= "" and table.find(self:availableTitles(session), titleId) == nil then
		return Result.err("TITLE_NOT_OWNED")
	end
	session.data.titles.selected = titleId
	self._d.touch(session)
	return Result.ok(nil)
end

-- ───────────── Recompensa diaria ─────────────

function Progression.dailyStatus(
	self: Progression,
	session: Session
): { ready: boolean, remaining: number, streak: number }
	local daily = session.data.daily
	local elapsed = self._d.clock.unix() - daily.lastClaim
	local remaining = math.max(0, Balance.Daily.CooldownSeconds - elapsed)
	return { ready = remaining == 0, remaining = remaining, streak = daily.streak }
end

function Progression.claimDaily(
	self: Progression,
	session: Session,
	incomePerSecond: number
): Result.Result<{ reward: number, streak: number }>
	local d = self._d
	local daily = session.data.daily
	local now = d.clock.unix()
	local elapsed = now - daily.lastClaim
	if daily.lastClaim > 0 and elapsed < Balance.Daily.CooldownSeconds then
		return Result.err("DAILY_NOT_READY", { remaining = Balance.Daily.CooldownSeconds - elapsed })
	end
	if elapsed > Balance.Daily.CooldownSeconds + 24 * 3600 or daily.lastClaim == 0 then
		daily.streak = 0 -- se perdió la racha (o primera vez)
	end
	daily.streak = math.min(Balance.Daily.MaxStreak, daily.streak + 1)

	-- Base: lo mayor entre un mínimo y 2 min de ingresos; la racha suma un +10 % por día (máx. 7).
	local base = math.max(Balance.Daily.BaseCash, incomePerSecond * Balance.Daily.IncomeSeconds)
	local reward = math.floor(base * (1 + Balance.Daily.StreakStep * (daily.streak - 1)))
	-- Tope duro: nunca más de 15 min de ingresos (o el doble del mínimo en cuentas muy pequeñas).
	reward = math.min(
		reward,
		math.max(Balance.Daily.BaseCash * 2, math.floor(incomePerSecond * Balance.Daily.MaxIncomeSeconds))
	)

	local paid = d.ledger:credit(session, reward, "reward", { source = "daily" })
	if not paid.ok then
		return paid :: any
	end
	daily.lastClaim = now
	d.touch(session)
	return Result.ok({ reward = reward, streak = daily.streak })
end

return Progression
