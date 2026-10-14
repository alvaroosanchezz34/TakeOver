--!strict
--[[
	Persistencia de perfiles sobre DataStore (sin depender de librerías externas).

	- Bloqueo de sesión (session lock) dentro de UpdateAsync: un perfil sólo lo escribe el
	  servidor que lo tiene bloqueado. Evita regresiones de datos y duplicaciones al
	  cambiar de servidor.
	- El bloqueo se refresca (heartbeat) en cada guardado; si un servidor muere, el bloqueo
	  caduca (`lockTimeout`) y otro puede tomarlo.
	- Si en un guardado el bloqueo ya no es nuestro => LOCK_LOST: se deja de guardar y el
	  llamador debe expulsar al jugador (nunca sobrescribimos datos de otro servidor).
	- Guardado con instantánea: se clona el perfil antes de ceder el hilo, así lo que se
	  escribe es coherente aunque el juego siga mutando mientras dura la llamada.
	- Reintentos con retroceso exponencial; si se agotan, el perfil sigue `dirty` y se
	  reintenta en el siguiente ciclo de autoguardado.

	Todas las dependencias (DataStore, reloj, espera, jobId) se inyectan => testable en Lune.
]]

local Shared = game:GetService("ReplicatedStorage").Shared

local Result = require(Shared.Util.Result)
local Table = require(Shared.Util.Table)
local PlayerData = require(script.Parent.PlayerData)

export type Deps = {
	dataStore: any, -- necesita UpdateAsync(key, fn)
	clock: { unix: () -> number, mono: () -> number },
	jobId: string,
	wait: (number) -> (),
	log: ((string) -> ())?,
	lockTimeout: number?,
	maxRetries: number?,
	retryBaseDelay: number?,
	lockAcquireAttempts: number?,
	lockAcquireDelay: number?,
}

export type Profile = {
	key: string,
	data: PlayerData.Data,
	active: boolean,
	dirty: boolean,
	rev: number,
	savedRev: number,
	saving: boolean,
	lockLost: boolean,
	isNew: boolean,
	repairs: { string },
	loadedAt: number,
	lastSaveAt: number,
}

local RECORD_VERSION = 1

local ProfileStore = {}
ProfileStore.__index = ProfileStore

export type ProfileStore = typeof(setmetatable(
	{} :: {
		_ds: any,
		_clock: { unix: () -> number, mono: () -> number },
		_jobId: string,
		_wait: (number) -> (),
		_log: (string) -> (),
		_lockTimeout: number,
		_maxRetries: number,
		_retryBaseDelay: number,
		_lockAttempts: number,
		_lockDelay: number,
	},
	ProfileStore
))

function ProfileStore.new(deps: Deps): ProfileStore
	return setmetatable({
		_ds = deps.dataStore,
		_clock = deps.clock,
		_jobId = deps.jobId,
		_wait = deps.wait,
		_log = deps.log or function() end,
		_lockTimeout = deps.lockTimeout or 300,
		_maxRetries = deps.maxRetries or 4,
		_retryBaseDelay = deps.retryBaseDelay or 1,
		_lockAttempts = deps.lockAcquireAttempts or 8,
		_lockDelay = deps.lockAcquireDelay or 2,
	}, ProfileStore)
end

-- Marca el perfil como modificado (lo recogerá el próximo guardado).
function ProfileStore.touch(_self: ProfileStore, profile: Profile)
	profile.rev += 1
	profile.dirty = true
end

--[[
	Carga el perfil de `key` tomando el bloqueo de sesión.
	Errores: SESSION_LOCKED, LOAD_FAILED, DATA_FROM_FUTURE, DATA_*.
]]
function ProfileStore.load(self: ProfileStore, key: string): Result.Result<Profile>
	local networkFailures = 0
	local lockAttempts = 0

	while true do
		local lockedBy: string? = nil
		local record: any = nil
		local ok, err = pcall(function()
			local updated = self._ds:UpdateAsync(key, function(old: any)
				lockedBy = nil
				if old ~= nil and type(old) ~= "table" then
					-- Registro corrupto: no lo tocamos (mejor fallar que perder datos).
					error("registro corrupto en " .. key)
				end
				local now = self._clock.unix()
				if old ~= nil and old.lock ~= nil and old.lock.jobId ~= self._jobId then
					if now - (old.lock.t or 0) < self._lockTimeout then
						lockedBy = tostring(old.lock.jobId)
						return nil -- cancelar: otro servidor lo tiene
					end
					self._log(
						("[ProfileStore] bloqueo caducado de %s en %s"):format(tostring(old.lock.jobId), key)
					)
				end
				local rec = old or { recordVersion = RECORD_VERSION, createdAt = now, saves = 0 }
				rec.lock = { jobId = self._jobId, t = now }
				return rec
			end)
			record = updated
		end)

		if not ok then
			networkFailures += 1
			self._log(
				("[ProfileStore] fallo al cargar %s (intento %d): %s"):format(
					key,
					networkFailures,
					tostring(err)
				)
			)
			if networkFailures >= self._maxRetries then
				return Result.err("LOAD_FAILED", { reason = tostring(err) })
			end
			self._wait(self._retryBaseDelay * 2 ^ (networkFailures - 1))
		elseif lockedBy ~= nil then
			lockAttempts += 1
			if lockAttempts >= self._lockAttempts then
				return Result.err("SESSION_LOCKED", { jobId = lockedBy })
			end
			self._wait(self._lockDelay)
		else
			return self:_decode(key, record)
		end
	end
end

function ProfileStore._decode(self: ProfileStore, key: string, record: any): Result.Result<Profile>
	local now = self._clock.unix()
	local isNew = record == nil or record.data == nil
	local data: PlayerData.Data
	local repairs: { string } = {}

	if isNew then
		data = PlayerData.template(now)
	else
		local migrated = PlayerData.migrate(record.data)
		if not migrated.ok then
			self:_releaseLockOnly(key)
			return migrated :: any
		end
		data = migrated.value
		PlayerData.reconcile(data, PlayerData.template(now))
		repairs = PlayerData.repair(data, now)
		if #repairs > 0 then
			self._log(("[ProfileStore] %s reparado: %s"):format(key, table.concat(repairs, ", ")))
		end
	end

	local profile: Profile = {
		key = key,
		data = data,
		active = true,
		dirty = isNew or #repairs > 0,
		rev = 0,
		savedRev = 0,
		saving = false,
		lockLost = false,
		isNew = isNew,
		repairs = repairs,
		loadedAt = self._clock.mono(),
		lastSaveAt = self._clock.mono(),
	}
	return Result.ok(profile)
end

-- Libera el bloqueo sin escribir datos (p. ej. si la migración falla).
function ProfileStore._releaseLockOnly(self: ProfileStore, key: string)
	pcall(function()
		self._ds:UpdateAsync(key, function(old: any)
			if type(old) == "table" and old.lock ~= nil and old.lock.jobId == self._jobId then
				old.lock = nil
				return old
			end
			return nil
		end)
	end)
end

--[[
	Guarda el perfil. Con `release = true` además libera el bloqueo y lo desactiva.
	Errores: LOCK_LOST, SAVE_FAILED, NOT_SERIALIZABLE.
]]
function ProfileStore.save(self: ProfileStore, profile: Profile, release: boolean?): Result.Result<nil>
	if profile.lockLost then
		return Result.err("LOCK_LOST")
	end

	-- Un solo guardado a la vez por perfil.
	local waited = 0
	while profile.saving and waited < 30 do
		self._wait(0.1)
		waited += 0.1
	end
	if profile.saving then
		return Result.err("SAVE_IN_PROGRESS")
	end
	if not profile.active then
		return Result.err("PROFILE_INACTIVE")
	end

	profile.saving = true
	local snapshot = Table.deepClone(profile.data)
	local revAtSnapshot = profile.rev

	local serializable, path, why = PlayerData.assertSerializable(snapshot)
	if not serializable then
		profile.saving = false
		self._log(("[ProfileStore] datos no serializables en %s: %s"):format(tostring(path), tostring(why)))
		return Result.err("NOT_SERIALIZABLE", { path = path, reason = why })
	end

	local lockLost = false
	local lastError: any = nil
	for attempt = 1, self._maxRetries do
		lockLost = false
		local ok, err = pcall(function()
			self._ds:UpdateAsync(profile.key, function(old: any)
				if type(old) ~= "table" or old.lock == nil or old.lock.jobId ~= self._jobId then
					lockLost = true
					return nil
				end
				local now = self._clock.unix()
				old.recordVersion = RECORD_VERSION
				old.data = snapshot
				old.savedAt = now
				old.saves = (old.saves or 0) + 1
				if release then
					old.lock = nil
				else
					old.lock = { jobId = self._jobId, t = now }
				end
				return old
			end)
		end)

		if lockLost then
			profile.lockLost = true
			profile.saving = false
			self._log("[ProfileStore] bloqueo perdido en " .. profile.key)
			return Result.err("LOCK_LOST")
		end
		if ok then
			profile.savedRev = revAtSnapshot
			profile.dirty = profile.rev ~= revAtSnapshot
			profile.lastSaveAt = self._clock.mono()
			profile.saving = false
			if release then
				profile.active = false
			end
			return Result.ok(nil)
		end

		lastError = err
		self._log(
			("[ProfileStore] fallo al guardar %s (intento %d/%d): %s"):format(
				profile.key,
				attempt,
				self._maxRetries,
				tostring(err)
			)
		)
		if attempt < self._maxRetries then
			self._wait(self._retryBaseDelay * 2 ^ (attempt - 1))
		end
	end

	profile.saving = false
	profile.dirty = true
	return Result.err("SAVE_FAILED", { reason = tostring(lastError) })
end

return ProfileStore
