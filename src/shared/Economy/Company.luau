--!strict
--[[
	Modelo de empresa y utilidades puras (sin servicios de Roblox).

	El documento de la empresa se guarda DENTRO del perfil del fundador
	(`data.companies[id]`). La estructura de propiedad (`cap`) es la fuente de verdad de
	quién posee qué y cuánto cobra cada cual.
]]

local Balance = require(script.Parent.Parent.Config.Balance)
local Catalog = require(script.Parent.Catalog)
local Cosmetics = require(script.Parent.Parent.Config.Cosmetics)
local Ownership = require(script.Parent.Ownership)

export type HistoryEntry = {
	id: string,
	t: number, -- unix
	kind: string, -- "founded" | "upgrade" | "level" | "trade" | "rename" | "style"
	a: string?, -- actor / comprador (userId)
	b: string?, -- contraparte / vendedor (userId)
	bps: number?,
	amount: number?,
	note: string?,
}

export type Company = {
	id: string,
	sector: string,
	founderId: string,
	name: string,
	nameParts: { number },
	logo: { icon: number, color: number },
	level: number,
	upgrades: { [string]: number },
	cap: Ownership.Cap,
	unclaimed: { [string]: number }, -- dividendos pendientes de titulares desconectados
	history: { HistoryEntry },
	earned: number, -- ingresos brutos acumulados
	carry: { [string]: number }, -- fracción de Cash aún no pagada a cada titular (0 <= x < 1)
	createdAt: number,
}

local Company = {}

function Company.isValidParts(sectorId: string, parts: { number }): boolean
	local cores = Cosmetics.NameCores[sectorId]
	if cores == nil or type(parts) ~= "table" or #parts ~= 3 then
		return false
	end
	local function ok(i: any, max: number): boolean
		return type(i) == "number" and i % 1 == 0 and i >= 1 and i <= max
	end
	return ok(parts[1], #Cosmetics.NamePrefixes)
		and ok(parts[2], #cores)
		and ok(parts[3], #Cosmetics.NameSuffixes)
end

function Company.nameFromParts(sectorId: string, parts: { number }): string?
	if not Company.isValidParts(sectorId, parts) then
		return nil
	end
	local cores = Cosmetics.NameCores[sectorId]
	return Cosmetics.NamePrefixes[parts[1]]
		.. " "
		.. cores[parts[2]]
		.. " "
		.. Cosmetics.NameSuffixes[parts[3]]
end

function Company.isValidLogo(icon: number, color: number): boolean
	return type(icon) == "number"
		and icon % 1 == 0
		and icon >= 1
		and icon <= #Cosmetics.LogoIcons
		and type(color) == "number"
		and color % 1 == 0
		and color >= 1
		and color <= #Cosmetics.LogoColors
end

-- Nombre/logotipo por defecto, deterministas a partir de una semilla (p. ej. userId + índice).
function Company.defaultParts(sectorId: string, seed: number): { number }
	local cores = Cosmetics.NameCores[sectorId] or Cosmetics.NameCores.commerce
	local s = math.abs(math.floor(seed))
	return {
		(s % #Cosmetics.NamePrefixes) + 1,
		((s // 7) % #cores) + 1,
		((s // 31) % #Cosmetics.NameSuffixes) + 1,
	}
end

function Company.defaultLogo(seed: number): { icon: number, color: number }
	local s = math.abs(math.floor(seed))
	return { icon = (s % #Cosmetics.LogoIcons) + 1, color = ((s // 5) % #Cosmetics.LogoColors) + 1 }
end

export type NewParams = {
	founderId: string,
	index: number,
	sector: string,
	nameParts: { number }?,
	logo: { icon: number, color: number }?,
	now: number,
}

function Company.new(p: NewParams): Company
	assert(Catalog.sector(p.sector), "sector desconocido: " .. tostring(p.sector))
	local seed = (tonumber(p.founderId) or 0) * 13 + p.index * 101
	local parts = p.nameParts or Company.defaultParts(p.sector, seed)
	local name = Company.nameFromParts(p.sector, parts)
	assert(name, "partes de nombre inválidas")
	return {
		id = p.founderId .. ":" .. tostring(p.index),
		sector = p.sector,
		founderId = p.founderId,
		name = name,
		nameParts = parts,
		logo = p.logo or Company.defaultLogo(seed),
		level = 1,
		upgrades = {},
		cap = Ownership.newCap(p.founderId),
		unclaimed = {},
		history = {},
		earned = 0,
		carry = {},
		createdAt = p.now,
	}
end

-- Suma de niveles de mejoras de aspecto (look).
function Company.lookLevels(company: Company): number
	local sector = Catalog.sector(company.sector)
	local n = 0
	if sector then
		for _, def in sector.upgrades do
			if def.effect.kind == "look" then
				n += company.upgrades[def.id] or 0
			end
		end
	end
	return n
end

-- Etapa visual 1..10 del edificio (nivel + mejoras de aspecto).
function Company.visualTier(company: Company): number
	return math.clamp(company.level + Company.lookLevels(company), 1, 10)
end

-- Registro de operaciones acotado (anillo).
function Company.log(company: Company, entry: HistoryEntry)
	table.insert(company.history, entry)
	while #company.history > Balance.HistoryLimit do
		table.remove(company.history, 1)
	end
end

return Company
