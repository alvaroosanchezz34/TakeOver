--!strict
--[[
	Analítica de producto. Privacidad por diseño: SOLO se aceptan propiedades de una lista
	cerrada con tipos simples; no hay nombres, mensajes ni texto libre de jugadores.

	El sink (ver Services/AnalyticsSink) traduce estos eventos a AnalyticsService de Roblox;
	aquí sólo se decide QUÉ se mide, de forma testable y sin depender de Roblox.

	Embudo de incorporación (cada paso se registra UNA vez por sesión, con segundos desde que entró):
	  1 joined → 2 first_upgrade → 3 market_opened → 4 company_inspected → 5 first_offer → 6 tutorial_done
	Con él se ve en qué paso abandona la gente.
]]

export type Event = {
	kind: string, -- "custom" | "funnel" | "economy"
	userId: number,
	name: string,
	value: number?,
	props: { [string]: any },
}

export type Sink = (Event) -> ()

local ALLOWED: { [string]: "number" | "string" | "boolean" } = {
	sector = "string",
	companyId = "string",
	upgradeId = "string",
	level = "number",
	amount = "number",
	bps = "number",
	price = "number",
	code = "string",
	step = "number",
	seconds = "number",
	balance = "number",
	reason = "string",
	action = "string",
	product = "string",
	flow = "string",
	count = "number",
	controlChanged = "boolean",
	result = "string",
	rank = "number",
}

local Analytics = {}
Analytics.__index = Analytics

export type Analytics = typeof(setmetatable(
	{} :: {
		_clock: { unix: () -> number, mono: () -> number },
		_sink: Sink,
		counters: { [string]: number },
		recent: { Event },
		_funnelDone: { [number]: { [number]: boolean } },
		_joinMono: { [number]: number },
	},
	Analytics
))

Analytics.FUNNEL =
	{ "joined", "first_upgrade", "market_opened", "company_inspected", "first_offer", "tutorial_done" }

function Analytics.new(clock: { unix: () -> number, mono: () -> number }, sink: Sink?): Analytics
	return setmetatable({
		_clock = clock,
		_sink = sink or function() end,
		counters = {},
		recent = {},
		_funnelDone = {},
		_joinMono = {},
	}, Analytics)
end

local function clean(props: { [string]: any }?): { [string]: any }
	local out: { [string]: any } = {}
	if props == nil then
		return out
	end
	for key, value in props do
		local expected = ALLOWED[key]
		if expected ~= nil and type(value) == expected then
			if type(value) == "string" then
				if #value <= 40 and not string.find(value, "[%c]") then
					out[key] = value
				end
			elseif type(value) == "number" then
				if value == value and value ~= math.huge and value ~= -math.huge then
					out[key] = value
				end
			else
				out[key] = value
			end
		end
	end
	return out
end

function Analytics._emit(self: Analytics, event: Event)
	self.counters[event.name] = (self.counters[event.name] or 0) + 1
	table.insert(self.recent, event)
	while #self.recent > 200 do
		table.remove(self.recent, 1)
	end
	local ok, err = pcall(function()
		self._sink(event)
	end)
	if not ok then
		warn("[Analytics] sink falló: " .. tostring(err))
	end
end

function Analytics.track(
	self: Analytics,
	userId: number,
	name: string,
	props: { [string]: any }?,
	value: number?
)
	self:_emit({ kind = "custom", userId = userId, name = name, value = value, props = clean(props) })
end

function Analytics.sessionStart(self: Analytics, userId: number)
	self._joinMono[userId] = self._clock.mono()
	self._funnelDone[userId] = {}
	self:funnel(userId, 1)
end

-- Paso del embudo (1..6): se registra una sola vez por sesión.
function Analytics.funnel(self: Analytics, userId: number, step: number)
	local done = self._funnelDone[userId]
	if done == nil or done[step] then
		return
	end
	done[step] = true
	local since = self._clock.mono() - (self._joinMono[userId] or self._clock.mono())
	self:_emit({
		kind = "funnel",
		userId = userId,
		name = Analytics.FUNNEL[step] or ("step_" .. step),
		value = step,
		props = clean({ step = step, seconds = math.floor(since) }),
	})
end

-- Flujo económico (fuente/sumidero) para el panel económico de Roblox.
function Analytics.economy(
	self: Analytics,
	userId: number,
	flow: string,
	amount: number,
	balance: number,
	reason: string
)
	self:_emit({
		kind = "economy",
		userId = userId,
		name = reason,
		value = amount,
		props = clean({ flow = flow, amount = amount, balance = balance, reason = reason }),
	})
end

function Analytics.sessionEnd(self: Analytics, userId: number, playSeconds: number)
	self:track(userId, "session_end", { seconds = math.floor(playSeconds) })
	self._funnelDone[userId] = nil
	self._joinMono[userId] = nil
end

return Analytics
