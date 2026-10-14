--!strict
--[[
	Alianzas de sesión (viven mientras sus miembros están en el servidor).

	Ventaja: +3 % de ingresos por aliado conectado, con TOPE (+9 %): un grupo de amigos no
	puede crecer sin límite gracias a la alianza. Una alianza no da exclusividad ni
	bloqueos: no limita los tratos con terceros ni las ofertas sobre sus empresas.
	Al salir de una alianza hay un enfriamiento antes de unirse a otra (evita rotarlas para
	cobrar bonos), y las invitaciones caducan.
]]

local Shared = game:GetService("ReplicatedStorage").Shared

local Balance = require(Shared.Config.Balance)
local Result = require(Shared.Util.Result)

export type Invite = {
	id: string,
	fromId: string,
	toId: string,
	expiresMono: number,
	state: string, -- pending | accepted | declined | expired
}

local MAX_PENDING_INVITES_PER_PLAYER = 3

local Alliances = {}
Alliances.__index = Alliances

export type Alliances = typeof(setmetatable(
	{} :: {
		_clock: { unix: () -> number, mono: () -> number },
		_isOnline: (string) -> boolean,
		_alliances: { [string]: { id: string, members: { [string]: boolean } } },
		_byUser: { [string]: string },
		_invites: { [string]: Invite },
		_cooldown: { [string]: number },
		_seq: number,
	},
	Alliances
))

function Alliances.new(
	clock: { unix: () -> number, mono: () -> number },
	isOnline: (string) -> boolean
): Alliances
	return setmetatable({
		_clock = clock,
		_isOnline = isOnline,
		_alliances = {},
		_byUser = {},
		_invites = {},
		_cooldown = {},
		_seq = 0,
	}, Alliances)
end

local function memberCount(alliance: { members: { [string]: boolean } }): number
	local n = 0
	for _ in alliance.members do
		n += 1
	end
	return n
end

function Alliances.membersOf(self: Alliances, userId: string): { string }
	local id = self._byUser[userId]
	local out: { string } = {}
	if id == nil then
		return out
	end
	for member in self._alliances[id].members do
		table.insert(out, member)
	end
	table.sort(out)
	return out
end

function Alliances.multiplierFor(self: Alliances, userId: string): number
	local members = self:membersOf(userId)
	if #members < 2 then
		return 1
	end
	local bonus = math.min(Balance.Alliance.MaxBonus, (#members - 1) * Balance.Alliance.BonusPerOtherMember)
	return 1 + bonus
end

function Alliances.invite(self: Alliances, fromId: string, toId: string): Result.Result<Invite>
	local now = self._clock.mono()
	if fromId == toId then
		return Result.err("SAME_PARTIES")
	end
	if not self._isOnline(toId) then
		return Result.err("TARGET_OFFLINE")
	end
	if self._byUser[toId] ~= nil then
		return Result.err("TARGET_IN_ALLIANCE")
	end
	if (self._cooldown[fromId] or 0) > now or (self._cooldown[toId] or 0) > now then
		return Result.err("ALLIANCE_COOLDOWN")
	end
	local myAlliance = self._byUser[fromId]
	if myAlliance ~= nil and memberCount(self._alliances[myAlliance]) >= Balance.Alliance.MaxMembers then
		return Result.err("ALLIANCE_FULL", { max = Balance.Alliance.MaxMembers })
	end

	local outstanding = 0
	for _, inv in self._invites do
		if inv.state == "pending" and inv.expiresMono > now then
			if inv.fromId == fromId and inv.toId == toId then
				return Result.err("DUPLICATE_INVITE")
			end
			if inv.fromId == fromId then
				outstanding += 1
			end
		end
	end
	if outstanding >= MAX_PENDING_INVITES_PER_PLAYER then
		return Result.err("TOO_MANY_INVITES")
	end

	self._seq += 1
	local invite: Invite = {
		id = "i" .. tostring(self._seq),
		fromId = fromId,
		toId = toId,
		expiresMono = now + Balance.Alliance.InviteSeconds,
		state = "pending",
	}
	self._invites[invite.id] = invite
	return Result.ok(invite)
end

function Alliances.accept(self: Alliances, userId: string, inviteId: string): Result.Result<{ string }>
	local invite = self._invites[inviteId]
	if invite == nil or invite.toId ~= userId then
		return Result.err("INVITE_NOT_FOUND")
	end
	if invite.state ~= "pending" then
		return Result.err("INVITE_NOT_FOUND")
	end
	local now = self._clock.mono()
	if now >= invite.expiresMono then
		invite.state = "expired"
		return Result.err("INVITE_EXPIRED")
	end
	if not self._isOnline(invite.fromId) or not self._isOnline(userId) then
		invite.state = "expired"
		return Result.err("TARGET_OFFLINE")
	end
	if self._byUser[userId] ~= nil then
		return Result.err("ALREADY_IN_ALLIANCE")
	end
	if (self._cooldown[userId] or 0) > now then
		return Result.err("ALLIANCE_COOLDOWN")
	end

	local allianceId = self._byUser[invite.fromId]
	if allianceId == nil then
		self._seq += 1
		allianceId = "a" .. tostring(self._seq)
		self._alliances[allianceId] = { id = allianceId, members = { [invite.fromId] = true } }
		self._byUser[invite.fromId] = allianceId
	end
	local alliance = self._alliances[allianceId]
	if memberCount(alliance) >= Balance.Alliance.MaxMembers then
		return Result.err("ALLIANCE_FULL", { max = Balance.Alliance.MaxMembers })
	end
	alliance.members[userId] = true
	self._byUser[userId] = allianceId
	invite.state = "accepted"
	return Result.ok(self:membersOf(userId))
end

function Alliances.decline(self: Alliances, userId: string, inviteId: string): Result.Result<nil>
	local invite = self._invites[inviteId]
	if invite == nil or invite.toId ~= userId or invite.state ~= "pending" then
		return Result.err("INVITE_NOT_FOUND")
	end
	invite.state = "declined"
	return Result.ok(nil)
end

-- Quita al jugador; disuelve la alianza si queda uno solo. Devuelve los antiguos compañeros.
function Alliances._remove(self: Alliances, userId: string): { string }
	local id = self._byUser[userId]
	if id == nil then
		return {}
	end
	local alliance = self._alliances[id]
	alliance.members[userId] = nil
	self._byUser[userId] = nil
	local others: { string } = {}
	for member in alliance.members do
		table.insert(others, member)
	end
	table.sort(others)
	if #others < 2 then
		for _, member in others do
			self._byUser[member] = nil
		end
		self._alliances[id] = nil
	end
	return others
end

-- Salida voluntaria: enfriamiento antes de unirse a otra.
function Alliances.leave(self: Alliances, userId: string): Result.Result<{ string }>
	if self._byUser[userId] == nil then
		return Result.err("NOT_IN_ALLIANCE")
	end
	local others = self:_remove(userId)
	self._cooldown[userId] = self._clock.mono() + Balance.Alliance.RejoinCooldownSeconds
	return Result.ok(others)
end

-- Desconexión: sin penalización.
function Alliances.onPlayerLeft(self: Alliances, userId: string): { string }
	local others = self:_remove(userId)
	for id, inv in self._invites do
		if inv.fromId == userId or inv.toId == userId then
			self._invites[id] = nil
		end
	end
	self._cooldown[userId] = nil
	return others
end

function Alliances.sweep(self: Alliances)
	local now = self._clock.mono()
	for id, inv in self._invites do
		if inv.state == "pending" and now >= inv.expiresMono then
			inv.state = "expired"
		end
		if inv.state ~= "pending" and now >= inv.expiresMono + 120 then
			self._invites[id] = nil
		end
	end
end

function Alliances.pendingFor(self: Alliances, userId: string): { Invite }
	local now = self._clock.mono()
	local out: { Invite } = {}
	for _, inv in self._invites do
		if inv.toId == userId and inv.state == "pending" and now < inv.expiresMono then
			table.insert(out, inv)
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

return Alliances
