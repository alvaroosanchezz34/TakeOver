--!nocheck
--[[
	Simulación de ritmo (balance). Un jugador "voraz" compra siempre la opción recomendada.
	No es un test: imprime hitos para calibrar Config/Sectors y Config/Balance.

	    lune run tests/sim/pacing [commerce|tech|industry] [minutos]
]]

local process = require("@lune/process")
local Loader = require("../harness/Loader")

local load = Loader.new({ root = "." })
local Balance = load:shared("Config/Balance")
local Company = load:shared("Economy/Company")
local Income = load:shared("Economy/Income")
local Pricing = load:shared("Economy/Pricing")
local Valuation = load:shared("Economy/Valuation")
local Format = load:shared("Util/Format")

local sectorId = process.args[1] or "commerce"
local minutes = tonumber(process.args[2]) or 90
local startCash = tonumber(process.args[3]) or Balance.StartingCash

local company = Company.new({ founderId = "1", index = 1, sector = sectorId, now = 0 })
local cash = startCash
local carry = 0
local purchases = 0
local totalEarned = 0
local nextMilestones = { 5, 15, 30, 60, 120, 300, 600, 1200, 1800, 2700, 3600, 5400, 7200, 10800 }
local mi = 1
local lastBuyT = 0
local longestWait = 0
local longestWaitAt = ""

local function ctxAt(t)
	return { sessionSeconds = t }
end

print(("Sector: %s · %d min · Cash inicial %s"):format(sectorId, minutes, Format.cash(startCash, "es")))
print(string.rep("─", 96))

for t = 0, minutes * 60 do
	local ctx = ctxAt(t)
	local rate = Income.compute(company, ctx).total
	carry += rate
	local whole = math.floor(carry)
	carry -= whole
	cash += whole
	totalEarned += whole

	-- compra voraz
	while true do
		local options = Pricing.options(company, ctx, 0)
		local pick = Pricing.recommended(options, cash, rate)
		if pick and pick.cost <= cash and not pick.maxed then
			cash -= pick.cost
			purchases += 1
			if pick.kind == "level" then
				company.level += 1
			else
				company.upgrades[pick.id] = (company.upgrades[pick.id] or 0) + 1
			end
			local waited = t - lastBuyT
			if waited > longestWait then
				longestWait = waited
				longestWaitAt = ("t=%s (%s)"):format(Format.duration(t), pick.id)
			end
			lastBuyT = t
		else
			break
		end
	end

	if mi <= #nextMilestones and t == nextMilestones[mi] * 1 then
		local r = Income.compute(company, ctx)
		print(
			("t=%7s │ compras %3d │ nivel %d │ ingresos %12s │ valoración %12s │ caja %10s │ ganado %12s"):format(
				Format.duration(t),
				purchases,
				company.level,
				Format.rate(r.total, "es"),
				Format.cash(Valuation.fundamental(sectorId, r.sustained), "es"),
				Format.cash(cash, "es"),
				Format.cash(totalEarned, "es")
			)
		)
		mi += 1
	end
end

local r = Income.compute(company, ctxAt(minutes * 60))
print(string.rep("─", 96))
print(
	("Final: %d compras · nivel %d/%d · %s · espera máxima entre compras: %ds en %s"):format(
		purchases,
		company.level,
		Pricing.maxLevel(company),
		Format.rate(r.total, "es"),
		longestWait,
		longestWaitAt
	)
)
