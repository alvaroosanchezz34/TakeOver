--!strict
--[[
	Compras de Developer Products (ProcessReceipt) — lógica IDEMPOTENTE y testable.

	Reglas (las exige Roblox):
	- ProcessReceipt puede llamarse varias veces para la misma compra: se concede UNA vez.
	  Se usa `PurchaseId` como clave; el registro vive en el perfil (data.receipts) y se persiste.
	- Sólo se devuelve "granted" si la concesión quedó guardada (lo hace la capa de Roblox tras
	  persistir); si algo falla se devuelve "retry" y Roblox reintentará.
	- NUNCA se concede por una petición del cliente: sólo por el recibo que entrega Roblox.
]]

local Shared = game:GetService("ReplicatedStorage").Shared

local Monetization = require(Shared.Config.Monetization)

export type Receipt = { PurchaseId: string, ProductId: number, PlayerId: number, CurrencySpent: number? }
export type Outcome = "granted" | "already" | "retry"

local Receipts = {}

-- `catalog` es inyectable (tests); por defecto, la configuración real.
function Receipts.productById(productId: number, catalog: any?): any?
	if productId == 0 then
		return nil
	end
	for _, p in (catalog or Monetization).DeveloperProducts do
		if p.id == productId then
			return p
		end
	end
	return nil
end

function Receipts.passById(passId: number, catalog: any?): any?
	if passId == 0 then
		return nil
	end
	for _, p in (catalog or Monetization).GamePasses do
		if p.id == passId then
			return p
		end
	end
	return nil
end

-- Aplica en memoria las concesiones de un producto/pase (cosméticos, títulos, consumibles).
function Receipts.applyGrants(data: { [string]: any }, grants: any)
	if grants == nil then
		return
	end
	for _, id in grants.cosmetics or {} do
		data.cosmetics.owned[id] = true
	end
	for _, id in grants.titles or {} do
		data.cosmetics.owned["title:" .. id] = true
	end
	for id, amount in grants.consumables or {} do
		data.cosmetics.consumables[id] = (data.cosmetics.consumables[id] or 0) + amount
	end
end

--[[
	Procesa un recibo sobre los datos del jugador. Devuelve:
	  "granted"  recién concedido (la capa de Roblox debe persistir antes de confirmar)
	  "already"  ya estaba concedido (idempotente: confirmar sin volver a dar nada)
	  "retry"    producto desconocido/desactivado => no confirmar
]]
function Receipts.process(data: { [string]: any }, receipt: Receipt, now: number, catalog: any?): Outcome
	local key = tostring(receipt.PurchaseId)
	if data.receipts[key] ~= nil then
		return "already"
	end
	local product = Receipts.productById(receipt.ProductId, catalog)
	if product == nil then
		return "retry"
	end
	Receipts.applyGrants(data, product.grants)
	data.receipts[key] = now
	return "granted"
end

-- Efectos cosméticos que un jugador puede equipar (propiedad verificada en el servidor).
function Receipts.canEquip(data: { [string]: any }, cosmeticId: string): boolean
	local def = Monetization.Cosmetics[cosmeticId]
	if def == nil then
		return false
	end
	if def.free then
		return true
	end
	if def.consumable ~= nil then
		return (data.cosmetics.consumables[def.consumable] or 0) > 0
	end
	return data.cosmetics.owned[cosmeticId] == true
end

return Receipts
