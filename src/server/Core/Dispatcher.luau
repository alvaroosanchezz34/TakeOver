--!strict
--[[
	Despachador de peticiones del cliente (independiente de Roblox: testable).

	Cada petición pasa, en orden, por:
	  1. ¿acción conocida?                       (si no: strike)
	  2. límite global y por acción              (token bucket)
	  3. ¿hay sesión cargada para ese jugador?
	  4. validación del payload contra el esquema (si falla: strike) -> el handler recibe una
	     COPIA LIMPIA, nunca el valor original
	  5. handler dentro de pcall                 (un error no tumba al servidor ni filtra detalles)

	Los strikes sólo se acumulan por violaciones de PROTOCOLO (acciones inexistentes, payloads
	imposibles), algo que el cliente legítimo nunca envía. Superar el umbral expulsa al jugador.
	Ser rechazado por frecuencia NO cuenta como strike (un jugador legítimo puede pulsar rápido).
]]

local Shared = game:GetService("ReplicatedStorage").Shared

local Limits = require(Shared.Config.Limits)
local RateLimiter = require(Shared.Util.RateLimiter)
local Result = require(Shared.Util.Result)
local Validate = require(Shared.Util.Validate)

export type ActionDef = {
	schema: Validate.Rule,
	handler: (session: any, payload: any) -> Result.Result<any>,
}

export type Response = { ok: true, data: any } | { ok: false, code: string, params: { [string]: any }? }

export type Deps = {
	clock: { unix: () -> number, mono: () -> number },
	actions: { [string]: ActionDef },
	getSession: (userId: number) -> any?,
	onAbuse: (userId: number, reason: string) -> (),
	log: ((string) -> ())?,
}

local Dispatcher = {}
Dispatcher.__index = Dispatcher

export type Dispatcher = typeof(setmetatable(
	{} :: {
		_d: Deps,
		_limiter: RateLimiter.RateLimiter,
		_strikes: { [number]: { number } },
	},
	Dispatcher
))

function Dispatcher.new(deps: Deps): Dispatcher
	return setmetatable({
		_d = deps,
		_limiter = RateLimiter.new(deps.clock),
		_strikes = {},
	}, Dispatcher)
end

function Dispatcher._strike(self: Dispatcher, userId: number, reason: string)
	local now = self._d.clock.mono()
	local list = self._strikes[userId]
	if list == nil then
		list = {}
		self._strikes[userId] = list
	end
	table.insert(list, now)
	local fresh = {}
	for _, t in list do
		if now - t <= Limits.StrikeWindowSeconds then
			table.insert(fresh, t)
		end
	end
	self._strikes[userId] = fresh
	if #fresh >= Limits.MaxStrikes then
		self._strikes[userId] = {}
		self._d.onAbuse(userId, reason)
	end
end

function Dispatcher.strikes(self: Dispatcher, userId: number): number
	return #(self._strikes[userId] or {})
end

function Dispatcher.onPlayerLeft(self: Dispatcher, userId: number)
	self._limiter:reset(userId)
	self._strikes[userId] = nil
end

local function fail(code: string, params: { [string]: any }?): Response
	return { ok = false, code = code, params = params }
end

function Dispatcher.dispatch(self: Dispatcher, userId: number, action: any, payload: any): Response
	local def = if type(action) == "string" then self._d.actions[action] else nil
	if def == nil then
		self:_strike(userId, "acción desconocida")
		return fail("BAD_REQUEST")
	end

	local global = Limits.Global
	local perAction = Limits.Actions[action]
	if not self._limiter:consume(userId, "*", global.capacity, global.refill) then
		return fail("RATE_LIMITED")
	end
	if perAction and not self._limiter:consume(userId, action, perAction.capacity, perAction.refill) then
		return fail("RATE_LIMITED")
	end

	local session = self._d.getSession(userId)
	if session == nil then
		return fail("NOT_READY")
	end

	local valid, clean = Validate.check(def.schema, payload)
	if not valid then
		self:_strike(userId, "payload inválido")
		if self._d.log then
			self._d.log(
				("[Dispatcher] payload inválido de %d en %s: %s"):format(userId, action, tostring(clean))
			)
		end
		return fail("BAD_REQUEST")
	end

	local ok, result = pcall(def.handler, session, clean)
	if not ok then
		if self._d.log then
			self._d.log(("[Dispatcher] error en %s: %s"):format(action, tostring(result)))
		end
		return fail("INTERNAL")
	end
	if type(result) ~= "table" or type(result.ok) ~= "boolean" then
		return fail("INTERNAL")
	end
	if result.ok then
		return { ok = true, data = result.value }
	end
	return fail(result.code, result.params)
end

return Dispatcher
