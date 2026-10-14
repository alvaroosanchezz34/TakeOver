--!strict
--[[
	Acceso indexado a los datos de Config/Sectors.
]]

local Sectors = require(script.Parent.Parent.Config.Sectors)

local upgradeIndex: { [string]: { [string]: Sectors.UpgradeDef } } = {}
for sectorId, sector in Sectors.byId do
	local perSector = {}
	for _, def in sector.upgrades do
		perSector[def.id] = def
	end
	upgradeIndex[sectorId] = perSector
end

local Catalog = {}

function Catalog.sector(sectorId: string): Sectors.SectorDef?
	return Sectors.byId[sectorId]
end

function Catalog.upgrade(sectorId: string, upgradeId: string): Sectors.UpgradeDef?
	local perSector = upgradeIndex[sectorId]
	return perSector and perSector[upgradeId]
end

function Catalog.sectorIds(): { string }
	return Sectors.order
end

return Catalog
