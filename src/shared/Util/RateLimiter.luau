--!strict
--[[
	Token bucket por (jugador, clave). Sin tareas en segundo plano: los cubos se
	rellenan perezosamente al consumirlos y se liberan con `reset` al salir el jugador.
]]

local Clock = require(script.Parent.Clock)

type Bucket = { tokens: number, last: number }

export type RateLimiter = {
	consume: (
		self: RateLimiter,
		userId: number,
		key: string,
		capacity: number,
		refillPerSecond: number,
		cost: number?
	) -> boolean,
	reset: (self: RateLimiter, userId: number) -> (),
	_buckets: { [number]: { [string]: Bucket } },
	_clock: Clock.Clock,
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(clock: Clock.Clock): RateLimiter
	return setmetatable({ _buckets = {}, _clock = clock }, RateLimiter) :: any
end

function RateLimiter.consume(
	self: RateLimiter,
	userId: number,
	key: string,
	capacity: number,
	refillPerSecond: number,
	cost: number?
): boolean
	local now = self._clock.mono()
	local perUser = self._buckets[userId]
	if perUser == nil then
		perUser = {}
		self._buckets[userId] = perUser
	end
	local bucket = perUser[key]
	if bucket == nil then
		bucket = { tokens = capacity, last = now }
		perUser[key] = bucket
	end
	local elapsed = math.max(0, now - bucket.last)
	bucket.tokens = math.min(capacity, bucket.tokens + elapsed * refillPerSecond)
	bucket.last = now
	local needed = cost or 1
	if bucket.tokens >= needed then
		bucket.tokens -= needed
		return true
	end
	return false
end

function RateLimiter.reset(self: RateLimiter, userId: number)
	self._buckets[userId] = nil
end

return RateLimiter
