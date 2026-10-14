--!nonstrict
--[[
	Tienda: Game Passes y Developer Products (sólo cosméticos; ver Config/Monetization).

	- ProcessReceipt es IDEMPOTENTE (Core/Receipts): el mismo PurchaseId nunca concede dos veces.
	- Sólo se devuelve PurchaseGranted cuando la concesión YA está guardada en el DataStore;
	  si el guardado falla se devuelve NotProcessedYet y Roblox reintenta.
	- Nunca se concede nada porque el cliente "diga" que ha pagado: sólo por recibos de Roblox o
	  por UserOwnsGamePassAsync (servidor).
	- Los productos con id = 0 (sin configurar) están desactivados.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Receipts = require(script.Parent.Parent.Core.Receipts)

local Shop = {}

function Shop.start(server)
	local function applyPasses(session)
		local player = Players:GetPlayerByUserId(session.userId)
		if player == nil then
			return
		end
		for _, pass in Monetization.GamePasses do
			if pass.id ~= 0 then
				local ok, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(session.userId, pass.id)
				end)
				if ok and owns then
					Receipts.applyGrants(session.data, pass.grants)
					server.touch(session)
				elseif not ok then
					warn("[Shop] no se pudo comprobar el pase " .. pass.key .. ": " .. tostring(owns))
				end
			end
		end
	end

	-- Compra de pase terminada: se vuelve a comprobar la propiedad en el servidor.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not wasPurchased then
			return
		end
		local session = server.world.sessions[tostring(player.UserId)]
		if session == nil then
			return
		end
		applyPasses(session)
		server:pushState(session)
		server.analytics:track(session.userId, "pass_purchased", { product = tostring(passId) })
	end)

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local declined = Enum.ProductPurchaseDecision.NotProcessedYet
		local session = server.world.sessions[tostring(receiptInfo.PlayerId)]
		if session == nil then
			return declined -- el jugador no está: Roblox reintentará cuando vuelva
		end

		local outcome = Receipts.process(session.data, {
			PurchaseId = tostring(receiptInfo.PurchaseId),
			ProductId = receiptInfo.ProductId,
			PlayerId = receiptInfo.PlayerId,
			CurrencySpent = receiptInfo.CurrencySpent,
		}, os.time())

		if outcome == "retry" then
			warn("[Shop] recibo de un producto no configurado: " .. tostring(receiptInfo.ProductId))
			return declined
		end

		server.touch(session)
		-- Persistir ANTES de confirmar la compra.
		local saved = server:save(session, false)
		if not saved.ok then
			warn("[Shop] no se pudo guardar la compra: " .. tostring(saved.code))
			return declined
		end

		if outcome == "granted" then
			server.analytics:track(
				session.userId,
				"product_purchased",
				{ product = tostring(receiptInfo.ProductId) }
			)
			server:notify(session.userId, "purchase_done", {})
			server:pushState(session)
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	return { applyPasses = applyPasses }
end

return Shop
