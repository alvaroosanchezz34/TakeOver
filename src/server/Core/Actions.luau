--!strict
--[[
	Acciones que el cliente puede pedir al servidor: esquema de entrada + manejador.

	Cada manejador:
	  - recibe la sesión del jugador (identidad del servidor) y un payload YA validado y limpio,
	  - llama al motor correspondiente (que vuelve a validar con datos del servidor),
	  - registra analítica / progreso y avisa a quien corresponda,
	  - devuelve un Result; nunca lanza errores esperables.
]]

local Shared = game:GetService("ReplicatedStorage").Shared

local Balance = require(Shared.Config.Balance)
local Monetization = require(Shared.Config.Monetization)
local Receipts = require(script.Parent.Receipts)
local Result = require(Shared.Util.Result)
local V = require(Shared.Util.Validate)

local Views = require(script.Parent.Views)

local Actions = {}

local COMPANY_ID = V.string({ minLen = 3, maxLen = 40, pattern = "^[%w_:%-]+$" })
local USER_ID = V.string({ minLen = 1, maxLen = 24, pattern = "^%-?%d+$" })
local ID = V.string({ minLen = 1, maxLen = 32, pattern = "^[%w_]+$" })
local SMALL = V.int({ min = 1, max = 64 })

-- `server` es la raíz de composición (ver Server.luau).
function Actions.build(server: any): { [string]: any }
	local world = server.world

	-- Efectos comunes tras cualquier operación que cambie el estado del jugador.
	local function after(session: any)
		server:onProgress(session)
		server:pushState(session)
	end

	local function companyOrErr(companyId: string): (any?, Result.Result<any>?)
		local company = world:getCompany(companyId)
		if company == nil then
			return nil, Result.err("COMPANY_NOT_FOUND")
		end
		return company, nil
	end

	local actions: { [string]: any } = {}

	actions.GetState = {
		schema = V.none(),
		handler = function(session: any): Result.Result<any>
			return Result.ok(server:buildState(session))
		end,
	}

	actions.BuyUpgrade = {
		schema = V.object({ companyId = COMPANY_ID, upgradeId = ID }),
		handler = function(session: any, p: any): Result.Result<any>
			local r = server.ops:buyUpgrade(session, p.companyId, p.upgradeId)
			if not r.ok then
				server:onFailure(session, "buy_upgrade", r)
				return r
			end
			server.analytics:track(session.userId, "upgrade_bought", {
				upgradeId = p.upgradeId,
				level = r.value.newLevel,
				amount = r.value.cost,
			})
			server.analytics:funnel(session.userId, 2)
			server.progression:event(session, "upgrade_bought")
			after(session)
			return r
		end,
	}

	actions.LevelUp = {
		schema = V.object({ companyId = COMPANY_ID }),
		handler = function(session: any, p: any): Result.Result<any>
			local r = server.ops:levelUp(session, p.companyId)
			if not r.ok then
				server:onFailure(session, "level_up", r)
				return r
			end
			server.analytics:track(
				session.userId,
				"company_level_up",
				{ level = r.value.newLevel, amount = r.value.cost }
			)
			server.progression:event(session, "upgrade_bought")
			after(session)
			return r
		end,
	}

	actions.FoundCompany = {
		schema = V.object({
			sector = ID,
			parts = V.optional(V.array(SMALL, 3)),
			logo = V.optional(V.object({ icon = SMALL, color = SMALL })),
		}),
		handler = function(session: any, p: any): Result.Result<any>
			local r = server.ops:found(session, p.sector, p.parts, p.logo)
			if not r.ok then
				server:onFailure(session, "found_company", r)
				return r
			end
			server.analytics:track(session.userId, "company_founded", { sector = p.sector })
			after(session)
			return Result.ok({ companyId = r.value.id })
		end,
	}

	actions.Rename = {
		schema = V.object({ companyId = COMPANY_ID, parts = V.array(SMALL, 3) }),
		handler = function(session: any, p: any): Result.Result<any>
			local r = server.ops:rename(session, p.companyId, p.parts)
			if r.ok then
				after(session)
			end
			return r
		end,
	}

	actions.SetLogo = {
		schema = V.object({ companyId = COMPANY_ID, icon = SMALL, color = SMALL }),
		handler = function(session: any, p: any): Result.Result<any>
			local r = server.ops:setLogo(session, p.companyId, p.icon, p.color)
			if r.ok then
				after(session)
			end
			return r
		end,
	}

	actions.GetMarket = {
		schema = V.none(),
		handler = function(session: any): Result.Result<any>
			server.progression:event(session, "market_opened")
			server.analytics:funnel(session.userId, 3)
			return Result.ok(server:buildMarket(session))
		end,
	}

	actions.InspectCompany = {
		schema = V.object({ companyId = COMPANY_ID }),
		handler = function(session: any, p: any): Result.Result<any>
			local company, err = companyOrErr(p.companyId)
			if company == nil then
				return err :: any
			end
			if company.founderId ~= session.id then
				server.progression:event(session, "company_inspected")
				server.analytics:funnel(session.userId, 4)
			end
			return Result.ok(Views.companyDetail(world, company, session))
		end,
	}

	actions.MakeOffer = {
		schema = V.object({
			companyId = COMPANY_ID,
			sellerId = USER_ID,
			bps = V.int({ min = 1, max = Balance.BpsTotal }),
			price = V.int({ min = 1, max = Balance.MaxCash }),
		}),
		handler = function(session: any, p: any): Result.Result<any>
			local r = server.trade:createOffer(session, p)
			if not r.ok then
				server:onFailure(session, "make_offer", r)
				return r
			end
			local offer = r.value
			server.analytics:track(session.userId, "offer_made", { bps = p.bps, price = p.price })
			server.analytics:funnel(session.userId, 5)
			server.progression:event(session, "first_offer")
			local company = world.companies[offer.companyId]
			server:notify(tonumber(offer.sellerId) :: number, "offer_received", {
				from = session.name,
				company = company and company.name or "?",
				bps = offer.bps,
				price = offer.price,
			})
			server:pushOffers(offer.sellerId)
			server:pushOffers(session.id)
			after(session)
			return Result.ok({ offerId = offer.id, expiresIn = Balance.OfferExpirySeconds })
		end,
	}

	actions.RespondOffer = {
		schema = V.object({
			offerId = V.string({ minLen = 2, maxLen = 16, pattern = "^o%d+$" }),
			action = V.oneOf({ "accept", "reject", "cancel" }),
			confirm = V.optional(V.bool()),
		}),
		handler = function(session: any, p: any): Result.Result<any>
			if p.action == "accept" then
				return server:acceptOffer(session, p.offerId, p.confirm == true)
			end
			local r
			if p.action == "reject" then
				r = server.trade:rejectOffer(session, p.offerId)
			else
				r = server.trade:cancelOffer(session, p.offerId)
			end
			if not r.ok then
				return r
			end
			local offer = r.value
			local other = if p.action == "reject" then offer.buyerId else offer.sellerId
			local company = world.companies[offer.companyId]
			if p.action == "reject" then
				server:notify(tonumber(other) :: number, "offer_rejected", {
					seller = session.name,
					company = company and company.name or "?",
				})
			end
			server:pushOffers(offer.buyerId)
			server:pushOffers(offer.sellerId)
			return Result.ok(nil)
		end,
	}

	actions.BuyMarket = {
		schema = V.object({
			companyId = COMPANY_ID,
			bps = V.int({ min = 1, max = Balance.BpsTotal }),
			confirm = V.optional(V.bool()),
		}),
		handler = function(session: any, p: any): Result.Result<any>
			local r = server.trade:buyFromMarket(session, p.companyId, p.bps, p.confirm == true)
			if not r.ok then
				server:onFailure(session, "market_buy", r)
				return r
			end
			server.analytics:track(session.userId, "market_buy", { bps = p.bps, price = r.value.price })
			server.progression:event(session, "first_offer")
			server.analytics:funnel(session.userId, 5)
			server:saveSoon(r.value.touched)
			after(session)
			return Result.ok({ price = r.value.price, bps = r.value.bps })
		end,
	}

	actions.SellMarket = {
		schema = V.object({ companyId = COMPANY_ID, bps = V.int({ min = 1, max = Balance.BpsTotal }) }),
		handler = function(session: any, p: any): Result.Result<any>
			local r = server.trade:sellToMarket(session, p.companyId, p.bps)
			if not r.ok then
				server:onFailure(session, "market_sell", r)
				return r
			end
			server.analytics:track(session.userId, "market_sell", { bps = p.bps, price = r.value.price })
			server:saveSoon(r.value.touched)
			after(session)
			return Result.ok({ price = r.value.price, bps = r.value.bps })
		end,
	}

	actions.AllianceInvite = {
		schema = V.object({ targetId = USER_ID }),
		handler = function(session: any, p: any): Result.Result<any>
			local r = server.alliances:invite(session.id, p.targetId)
			if not r.ok then
				return r
			end
			server.analytics:track(session.userId, "alliance_invite", nil)
			server:notify(tonumber(p.targetId) :: number, "alliance_invite", { from = session.name })
			server:pushState(world.sessions[p.targetId])
			return Result.ok(nil)
		end,
	}

	actions.AllianceRespond = {
		schema = V.object({
			inviteId = V.string({ minLen = 2, maxLen = 16, pattern = "^i%d+$" }),
			accept = V.bool(),
		}),
		handler = function(session: any, p: any): Result.Result<any>
			if not p.accept then
				local r = server.alliances:decline(session.id, p.inviteId)
				server:pushState(session)
				return r
			end
			local r = server.alliances:accept(session.id, p.inviteId)
			if not r.ok then
				return r
			end
			server.analytics:track(session.userId, "alliance_joined", { count = #r.value })
			for _, memberId in r.value do
				local member = world.sessions[memberId]
				if member then
					if memberId ~= session.id then
						server:notify(member.userId, "alliance_joined", { name = session.name })
					end
					server:pushState(member)
				end
			end
			return Result.ok(nil)
		end,
	}

	actions.AllianceLeave = {
		schema = V.none(),
		handler = function(session: any): Result.Result<any>
			local r = server.alliances:leave(session.id)
			if not r.ok then
				return r
			end
			for _, memberId in r.value do
				local member = world.sessions[memberId]
				if member then
					server:notify(member.userId, "alliance_left", { name = session.name })
					server:pushState(member)
				end
			end
			server:pushState(session)
			return Result.ok(nil)
		end,
	}

	actions.ClaimDaily = {
		schema = V.none(),
		handler = function(session: any): Result.Result<any>
			local r = server.progression:claimDaily(session, Views.incomeRate(world, session))
			if not r.ok then
				return r
			end
			server.analytics:track(
				session.userId,
				"daily_claimed",
				{ count = r.value.streak, amount = r.value.reward }
			)
			server:notify(
				session.userId,
				"daily_claimed",
				{ reward = r.value.reward, streak = r.value.streak }
			)
			server:pushState(session)
			return r
		end,
	}

	actions.SkipTutorial = {
		schema = V.none(),
		handler = function(session: any): Result.Result<any>
			server.progression:skipTutorial(session)
			server.analytics:track(session.userId, "tutorial_skipped", { step = session.data.tutorial.step })
			server:pushState(session)
			return Result.ok(nil)
		end,
	}

	actions.GetLeaderboard = {
		schema = V.none(),
		handler = function(): Result.Result<any>
			return Result.ok(server:buildLeaderboard())
		end,
	}

	actions.SetSetting = {
		schema = V.object({
			key = V.oneOf({ "sfx", "music", "lang" }),
			value = V.string({ minLen = 1, maxLen = 8, pattern = "^%a+$" }),
		}),
		handler = function(session: any, p: any): Result.Result<any>
			local settings = session.data.settings
			if p.key == "lang" then
				if not table.find({ "auto", "es", "en" }, p.value) then
					return Result.err("BAD_REQUEST")
				end
				settings.lang = p.value
			else
				if p.value ~= "on" and p.value ~= "off" then
					return Result.err("BAD_REQUEST")
				end
				settings[p.key] = p.value == "on"
			end
			server.touch(session)
			server:pushState(session)
			return Result.ok(nil)
		end,
	}

	actions.SelectTitle = {
		schema = V.object({ id = V.string({ minLen = 0, maxLen = 32, pattern = "^[%w_]*$" }) }),
		handler = function(session: any, p: any): Result.Result<any>
			local r = server.progression:selectTitle(session, p.id)
			if r.ok then
				server:pushState(session)
			end
			return r
		end,
	}

	actions.EquipCosmetic = {
		schema = V.object({
			slot = V.oneOf({ "effect", "office" }),
			id = V.string({ minLen = 1, maxLen = 32, pattern = "^[%w_]+$" }),
		}),
		handler = function(session: any, p: any): Result.Result<any>
			local def = Monetization.Cosmetics[p.id]
			if def == nil or def.slot ~= p.slot then
				return Result.err("COSMETIC_UNKNOWN")
			end
			if not Receipts.canEquip(session.data, p.id) then
				return Result.err("COSMETIC_NOT_OWNED")
			end
			session.data.cosmetics.equipped[p.slot] = p.id
			server.touch(session)
			server:pushState(session)
			return Result.ok(nil)
		end,
	}

	return actions
end

-- Expuesto para pruebas de contrato: las acciones que existen.
Actions.NAMES = {
	"GetState",
	"BuyUpgrade",
	"LevelUp",
	"FoundCompany",
	"Rename",
	"SetLogo",
	"GetMarket",
	"InspectCompany",
	"MakeOffer",
	"RespondOffer",
	"BuyMarket",
	"SellMarket",
	"AllianceInvite",
	"AllianceRespond",
	"AllianceLeave",
	"ClaimDaily",
	"SkipTutorial",
	"GetLeaderboard",
	"SetSetting",
	"SelectTitle",
	"EquipCosmetic",
}

return Actions
