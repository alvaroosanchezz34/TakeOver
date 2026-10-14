--!strict
--[[
	Operaciones sobre empresas: fundar, comprar mejoras, subir de nivel, personalizar.

	Todas validan en el servidor con datos del servidor: el cliente sólo indica QUÉ quiere
	(ids), nunca precios, cantidades ni resultados. El orden es siempre:
	  1) validar todo  2) cobrar  3) aplicar (sin posibilidad de fallo)  4) registrar.
]]

local Shared = game:GetService("ReplicatedStorage").Shared

local Balance = require(Shared.Config.Balance)
local Catalog = require(Shared.Economy.Catalog)
local Company = require(Shared.Economy.Company)
local Ownership = require(Shared.Economy.Ownership)
local Pricing = require(Shared.Economy.Pricing)
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

local STYLE_COOLDOWN_SECONDS = 20

local CompanyOps = {}
CompanyOps.__index = CompanyOps

export type CompanyOps = typeof(setmetatable({} :: { _d: Deps }, CompanyOps))

function CompanyOps.new(deps: Deps): CompanyOps
	return setmetatable({ _d = deps }, CompanyOps)
end

-- El documento de la empresa vive en el perfil del FUNDADOR: hay que marcarlo como modificado.
function CompanyOps._touchCompany(self: CompanyOps, company: any)
	local founder = self._d.world.sessions[company.founderId]
	if founder then
		self._d.touch(founder)
	end
end

function CompanyOps._log(self: CompanyOps, company: any, entry: { [string]: any })
	company.seq = (company.seq or 0) + 1
	entry.id = company.id .. "#" .. tostring(company.seq)
	entry.t = self._d.clock.unix()
	Company.log(company, entry :: any)
end

function CompanyOps.countOwned(_self: CompanyOps, session: Session): number
	local n = 0
	for _, c in session.data.companies do
		if c.founderId == session.id then
			n += 1
		end
	end
	return n
end

-- Primera empresa del jugador: gratis, para generar dinero desde el primer segundo.
function CompanyOps.ensureStarterCompany(self: CompanyOps, session: Session): any?
	local data = session.data
	if next(data.companies) ~= nil or data.counters.companiesFounded > 0 then
		return nil
	end
	local company = Company.new({
		founderId = session.id,
		index = 1,
		sector = "commerce",
		now = self._d.clock.unix(),
		founderName = session.name,
	})
	data.counters.companiesFounded = 1
	data.companies[company.id] = company
	self._d.world:registerCompany(company)
	self:_log(company, { kind = "founded", a = session.id })
	self._d.touch(session)
	return company
end

function CompanyOps.found(
	self: CompanyOps,
	session: Session,
	sectorId: string,
	nameParts: { number }?,
	logo: { icon: number, color: number }?
): Result.Result<any>
	local sector = Catalog.sector(sectorId)
	if sector == nil then
		return Result.err("SECTOR_UNKNOWN")
	end
	if self:countOwned(session) >= Balance.MaxOwnedCompanies then
		return Result.err("SLOTS_FULL", { max = Balance.MaxOwnedCompanies })
	end
	local earned = session.data.stats.totalEarned or 0
	if earned < sector.unlockTotalEarned then
		return Result.err("SECTOR_LOCKED", { need = sector.unlockTotalEarned, have = earned })
	end
	if nameParts ~= nil and not Company.isValidParts(sectorId, nameParts) then
		return Result.err("INVALID_NAME")
	end
	if logo ~= nil and not Company.isValidLogo(logo.icon, logo.color) then
		return Result.err("INVALID_LOGO")
	end

	local index = session.data.counters.companiesFounded + 1
	local ok, company = pcall(Company.new, {
		founderId = session.id,
		index = index,
		sector = sectorId,
		nameParts = nameParts,
		logo = logo,
		now = self._d.clock.unix(),
		founderName = session.name,
	})
	if not ok then
		return Result.err("INTERNAL", { reason = tostring(company) })
	end

	local paid = self._d.ledger:debit(session, sector.foundingCost, "found", { sector = sectorId })
	if not paid.ok then
		return paid :: any
	end

	session.data.counters.companiesFounded = index
	session.data.companies[company.id] = company
	self._d.world:registerCompany(company)
	self:_log(company, { kind = "founded", a = session.id, amount = sector.foundingCost })
	self._d.touch(session)
	return Result.ok(company)
end

-- Comprueba empresa cargada + que `session` la gestiona.
function CompanyOps._managed(self: CompanyOps, session: Session, companyId: string): Result.Result<any>
	local company = self._d.world.companies[companyId]
	if company == nil then
		return Result.err("COMPANY_NOT_FOUND")
	end
	if Ownership.manager(company.cap, company.founderId) ~= session.id then
		return Result.err("NOT_MANAGER")
	end
	return Result.ok(company)
end

function CompanyOps.buyUpgrade(
	self: CompanyOps,
	session: Session,
	companyId: string,
	upgradeId: string
): Result.Result<any>
	local managed = self:_managed(session, companyId)
	if not managed.ok then
		return managed
	end
	local company = managed.value
	local def = Catalog.upgrade(company.sector, upgradeId)
	if def == nil then
		return Result.err("UPGRADE_UNKNOWN")
	end
	local level = company.upgrades[upgradeId] or 0
	if level >= def.maxLevel then
		return Result.err("MAXED")
	end
	local discount = Pricing.discount(company, self._d.world.modifiers.eventDiscount(company.sector))
	local cost = Pricing.upgradeCost(company.sector, upgradeId, level, discount)
	if cost == nil then
		return Result.err("UPGRADE_UNKNOWN")
	end

	local paid =
		self._d.ledger:debit(session, cost, "upgrade", { companyId = companyId, upgradeId = upgradeId })
	if not paid.ok then
		return paid :: any
	end

	company.upgrades[upgradeId] = level + 1
	session.data.stats.upgradesBought += 1
	self:_log(
		company,
		{ kind = "upgrade", a = session.id, amount = cost, note = upgradeId .. ":" .. (level + 1) }
	)
	self:_touchCompany(company)
	self._d.touch(session)
	return Result.ok({ cost = cost, newLevel = level + 1, income = self._d.world:incomeOf(company).total })
end

function CompanyOps.levelUp(self: CompanyOps, session: Session, companyId: string): Result.Result<any>
	local managed = self:_managed(session, companyId)
	if not managed.ok then
		return managed
	end
	local company = managed.value
	if company.level >= Pricing.maxLevel(company) then
		return Result.err("LEVEL_CAP", { max = Pricing.maxLevel(company) })
	end
	local discount = Pricing.discount(company, self._d.world.modifiers.eventDiscount(company.sector))
	local cost = Pricing.levelUpCost(company.sector, company.level, discount)
	if cost == nil then
		return Result.err("INTERNAL")
	end

	local paid = self._d.ledger:debit(session, cost, "level", { companyId = companyId })
	if not paid.ok then
		return paid :: any
	end

	company.level += 1
	session.data.stats.upgradesBought += 1
	self:_log(company, { kind = "level", a = session.id, amount = cost, note = tostring(company.level) })
	self:_touchCompany(company)
	self._d.touch(session)
	return Result.ok({ cost = cost, newLevel = company.level, income = self._d.world:incomeOf(company).total })
end

-- Enfriamiento independiente para el nombre y para el logotipo (guardar ambos seguidos es válido).
function CompanyOps._styleCooldown(self: CompanyOps, company: any, field: string): Result.Result<nil>
	local now = self._d.clock.unix()
	local last = company[field] or 0
	if now - last < STYLE_COOLDOWN_SECONDS then
		return Result.err("COOLDOWN", { seconds = STYLE_COOLDOWN_SECONDS - (now - last) })
	end
	return Result.ok(nil)
end

function CompanyOps.rename(
	self: CompanyOps,
	session: Session,
	companyId: string,
	parts: { number }
): Result.Result<string>
	local managed = self:_managed(session, companyId)
	if not managed.ok then
		return managed :: any
	end
	local company = managed.value
	local name = Company.nameFromParts(company.sector, parts)
	if name == nil then
		return Result.err("INVALID_NAME")
	end
	local cooldown = self:_styleCooldown(company, "nameAt")
	if not cooldown.ok then
		return cooldown :: any
	end
	company.nameParts = parts
	company.name = name
	company.nameAt = self._d.clock.unix()
	self:_log(company, { kind = "rename", a = session.id, note = name })
	self:_touchCompany(company)
	return Result.ok(name)
end

function CompanyOps.setLogo(
	self: CompanyOps,
	session: Session,
	companyId: string,
	icon: number,
	color: number
): Result.Result<nil>
	local managed = self:_managed(session, companyId)
	if not managed.ok then
		return managed :: any
	end
	local company = managed.value
	if not Company.isValidLogo(icon, color) then
		return Result.err("INVALID_LOGO")
	end
	local cooldown = self:_styleCooldown(company, "logoAt")
	if not cooldown.ok then
		return cooldown
	end
	company.logo = { icon = icon, color = color }
	company.logoAt = self._d.clock.unix()
	self:_log(company, { kind = "style", a = session.id })
	self:_touchCompany(company)
	return Result.ok(nil)
end

return CompanyOps
