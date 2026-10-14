--!strict
--[[
	Esquema versionado de los datos de jugador + migraciones + reparación.

	Reglas de oro:
	- `version` sube con cada cambio de esquema; hay UNA migración por salto (n -> n+1).
	- `reconcile` añade campos nuevos con su valor por defecto sin tocar lo existente.
	- Datos de una versión FUTURA se rechazan (no se sobrescriben con un servidor antiguo).
	- Todo debe ser serializable por DataStore: claves string, números finitos, sin
	  funciones ni metatablas. `assertSerializable` lo comprueba (se usa en tests y antes de guardar).
]]

local Shared = game:GetService("ReplicatedStorage").Shared

local Balance = require(Shared.Config.Balance)
local Money = require(Shared.Economy.Money)
local Ownership = require(Shared.Economy.Ownership)
local Result = require(Shared.Util.Result)
local Table = require(Shared.Util.Table)

export type Data = { [string]: any }

local PlayerData = {}

PlayerData.CURRENT_VERSION = 1
PlayerData.MAX_RECEIPTS = 300

function PlayerData.template(now: number): Data
	return {
		version = PlayerData.CURRENT_VERSION,
		cash = Balance.StartingCash,
		stats = {
			totalEarned = 0, -- sólo ingresos y dividendos (no cuentan los tratos): desbloquea sectores
			totalSpent = 0,
			upgradesBought = 0,
			offersMade = 0,
			offersAccepted = 0,
			dealsClosed = 0,
			playSeconds = 0,
			sessions = 0,
			peakNetWorth = 0,
		},
		companies = {},
		counters = { companiesFounded = 0 },
		holdings = {},
		tutorial = { step = 1, done = false, skipped = false, bonusPaid = false },
		achievements = {},
		titles = { selected = "" },
		settings = { sfx = true, music = true, lang = "auto" },
		cosmetics = { owned = {}, equipped = { effect = "", office = "" }, consumables = {} },
		receipts = {},
		daily = { lastClaim = 0, streak = 0 },
		meta = { firstJoin = now, lastJoin = now },
	}
end

local function isPlainDict(v: any): boolean
	if type(v) ~= "table" then
		return false
	end
	for k in v do
		if type(k) ~= "string" then
			return false
		end
	end
	return true
end

-- Añade lo que falte según la plantilla (recursivo), sin pisar valores existentes.
function PlayerData.reconcile(data: Data, template: Data)
	for key, default in template do
		local current = data[key]
		if current == nil then
			data[key] = Table.deepClone(default)
		elseif
			type(default) == "table"
			and type(current) == "table"
			and isPlainDict(default)
			and next(default) ~= nil
		then
			PlayerData.reconcile(current, default)
		end
	end
end

--[[
	Migraciones: MIGRATIONS[v] transforma datos de la versión v a v+1.
	La versión 0 representa datos anteriores al versionado (builds de desarrollo): el dinero
	se llamaba `money` y no existían ajustes ni contadores.
]]
local MIGRATIONS: { [number]: (Data) -> Data } = {
	[0] = function(data)
		if data.cash == nil and type(data.money) == "number" then
			data.cash = data.money
		end
		data.money = nil
		data.version = 1
		return data
	end,
}

function PlayerData.migrate(data: Data): Result.Result<Data>
	local version = data.version
	if version == nil then
		version = 0
	end
	if type(version) ~= "number" or version % 1 ~= 0 or version < 0 then
		return Result.err("DATA_VERSION_INVALID")
	end
	if version > PlayerData.CURRENT_VERSION then
		return Result.err("DATA_FROM_FUTURE", { version = version })
	end
	while version < PlayerData.CURRENT_VERSION do
		local step = MIGRATIONS[version]
		if step == nil then
			return Result.err("DATA_NO_MIGRATION", { version = version })
		end
		local ok, migrated = pcall(step, data)
		if not ok then
			return Result.err("DATA_MIGRATION_FAILED", { version = version, reason = tostring(migrated) })
		end
		data = migrated
		version += 1
		data.version = version
	end
	return Result.ok(data)
end

--[[
	Reparación defensiva tras cargar: nada que venga del almacén se da por bueno.
	Devuelve la lista de reparaciones (para analítica/registro).
]]
function PlayerData.repair(data: Data, now: number): { string }
	local repairs: { string } = {}
	local function note(msg: string)
		table.insert(repairs, msg)
	end

	local cash = data.cash
	local clean = Money.sanitize(cash)
	if cash ~= clean then
		note("cash")
		data.cash = clean
	end

	for _, key in { "stats", "counters", "tutorial", "settings", "cosmetics", "daily", "meta", "titles" } do
		if type(data[key]) ~= "table" then
			note("tabla ausente: " .. key)
			data[key] = nil
		end
	end
	for _, key in { "companies", "holdings", "achievements", "receipts" } do
		if type(data[key]) ~= "table" then
			note("tabla ausente: " .. key)
			data[key] = {}
		end
	end
	PlayerData.reconcile(data, PlayerData.template(now))

	-- Estadísticas: números finitos y no negativos.
	for k, v in data.stats do
		if type(v) ~= "number" or v ~= v or v == math.huge or v < 0 then
			note("stat " .. tostring(k))
			data.stats[k] = 0
		end
	end

	-- Empresas: cap table válida y nivel/mejoras en rango.
	for id, company in data.companies do
		if type(company) ~= "table" or type(company.cap) ~= "table" then
			note("empresa irrecuperable " .. tostring(id))
			data.companies[id] = nil
		else
			local ok = Ownership.validate(company.cap)
			if not ok then
				note("cap inválido " .. tostring(id))
				company.cap = Ownership.newCap(tostring(company.founderId))
				company.unclaimed = {}
			end
			if type(company.level) ~= "number" or company.level ~= company.level or company.level < 1 then
				note("nivel " .. tostring(id))
				company.level = 1
			end
			company.level = math.floor(company.level)
			if type(company.upgrades) ~= "table" then
				company.upgrades = {}
			end
			for uid, lvl in company.upgrades do
				if type(lvl) ~= "number" or lvl ~= lvl or lvl < 0 then
					company.upgrades[uid] = 0
					note("mejora " .. tostring(uid))
				else
					company.upgrades[uid] = math.floor(lvl)
				end
			end
			if type(company.unclaimed) ~= "table" then
				company.unclaimed = {}
			end
			for holder, amount in company.unclaimed do
				company.unclaimed[holder] = Money.sanitize(amount)
			end
			if type(company.history) ~= "table" then
				company.history = {}
			end
			if type(company.carry) ~= "table" then
				company.carry = {}
			end
			if type(company.names) ~= "table" then
				company.names = {}
			end
			for holder, frac in company.carry do
				if type(frac) ~= "number" or frac ~= frac or frac < 0 or frac >= 2 then
					company.carry[holder] = 0
				end
			end
		end
	end

	-- Participaciones en otras empresas: bps enteros en 1..10000.
	for id, h in data.holdings do
		if type(h) ~= "table" or type(h.bps) ~= "number" or h.bps ~= h.bps or h.bps <= 0 or h.bps > 10000 then
			note("participación " .. tostring(id))
			data.holdings[id] = nil
		else
			h.bps = math.floor(h.bps)
		end
	end

	-- Recibos: se conservan los más recientes (el almacén no crece sin límite).
	local count = 0
	for _ in data.receipts do
		count += 1
	end
	if count > PlayerData.MAX_RECEIPTS then
		local entries = {}
		for id, t in data.receipts do
			table.insert(entries, { id = id, t = t })
		end
		table.sort(entries, function(a, b)
			return (tonumber(a.t) or 0) > (tonumber(b.t) or 0)
		end)
		for i = PlayerData.MAX_RECEIPTS + 1, #entries do
			data.receipts[entries[i].id] = nil
		end
		note("recibos recortados")
	end

	return repairs
end

--[[
	Comprueba que el valor es seguro para DataStore. Devuelve (true) o (false, ruta, motivo).
	- claves: sólo strings (o un array contiguo 1..n, pero no mezclado)
	- valores: string, boolean, número finito o tabla; nada de funciones/userdata/metatablas
]]
function PlayerData.assertSerializable(value: any, path: string?, depth: number?): (boolean, string?, string?)
	path = path or "data"
	depth = depth or 0
	if (depth :: number) > 12 then
		return false, path, "profundidad excesiva (¿ciclo?)"
	end
	local kind = type(value)
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return false, path, "número no finito"
		end
		return true
	elseif kind == "string" then
		if not utf8.len(value) then
			return false, path, "texto no UTF-8"
		end
		return true
	elseif kind == "boolean" then
		return true
	elseif kind == "table" then
		if getmetatable(value) ~= nil then
			return false, path, "metatabla no permitida"
		end
		local stringKeys, numberKeys = 0, 0
		local maxIndex = 0
		for k in value do
			if type(k) == "string" then
				stringKeys += 1
			elseif type(k) == "number" and k % 1 == 0 and k >= 1 then
				numberKeys += 1
				maxIndex = math.max(maxIndex, k)
			else
				return false, path, "clave no permitida: " .. tostring(k)
			end
		end
		if stringKeys > 0 and numberKeys > 0 then
			return false, path, "tabla mixta (claves string y numéricas)"
		end
		if numberKeys > 0 and maxIndex ~= numberKeys then
			return false, path, "array con huecos"
		end
		for k, v in value do
			local ok, p, why = PlayerData.assertSerializable(
				v,
				(path :: string) .. "." .. tostring(k),
				(depth :: number) + 1
			)
			if not ok then
				return false, p, why
			end
		end
		return true
	end
	return false, path, "tipo no serializable: " .. kind
end

return PlayerData
