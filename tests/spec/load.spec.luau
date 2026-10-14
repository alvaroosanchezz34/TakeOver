--!nocheck
local Cluster = require("../harness/Cluster")
local process = require("@lune/process")

-- Tamaño aproximado (bytes) de lo que viajaría por la red: cuenta claves y valores.
local function weight(value, depth)
	depth = depth or 0
	if depth > 12 then
		return 0
	end
	local kind = type(value)
	if kind == "string" then
		return #value + 2
	elseif kind == "number" then
		return 8
	elseif kind == "boolean" then
		return 1
	elseif kind == "table" then
		local total = 4
		for k, v in value do
			total += weight(k, depth + 1) + weight(v, depth + 1)
		end
		return total
	end
	return 0
end

return function(t, load)
	local Balance = load:shared("Config/Balance")
	local Ownership = load:shared("Economy/Ownership")
	local Random = load.Random

	local function veteran(cash)
		return function(d)
			d.cash = cash
			d.stats.playSeconds = 99999
			d.stats.totalEarned = 80000
			d.tutorial.done = true
		end
	end

	t:describe("Carga multijugador simulada (30 jugadores)", function()
		t:test("30 jugadores jugando 3 minutos: invariantes intactos, sin errores y tick barato", function()
			local rng = Random.new(2026)
			local cl = Cluster.new(load, { seed = 11 })
			local N = 30
			for i = 1, N do
				cl:join(i, "J" .. i, veteran(rng:NextInteger(2_000, 400_000)))
			end
			t:expect(cl.server.world.sessions["30"] ~= nil):toBe(true)

			local calls, okCalls = 0, 0
			local started = os.clock()
			local worst = 0
			for second = 1, 180 do
				cl.clock:advance(1)
				local tickStart = os.clock()
				cl.server:tick(1)
				worst = math.max(worst, os.clock() - tickStart)

				-- cada segundo ~6 jugadores aleatorios hacen algo
				for _ = 1, 6 do
					local uid = rng:NextInteger(1, N)
					local pick = rng:NextInteger(1, 8)
					local r
					if pick <= 2 then
						local up = ({ "shelves", "marketing", "logistics", "facade" })[rng:NextInteger(1, 4)]
						r = cl:call(uid, "BuyUpgrade", { companyId = uid .. ":1", upgradeId = up })
					elseif pick == 3 then
						r = cl:call(uid, "LevelUp", { companyId = uid .. ":1" })
					elseif pick == 4 then
						local npc = ({ "npc:commerce", "npc:tech", "npc:industry" })[rng:NextInteger(1, 3)]
						r = cl:call(
							uid,
							"BuyMarket",
							{ companyId = npc, bps = 100 * rng:NextInteger(1, 5), confirm = true }
						)
					elseif pick == 5 then
						local npc = ({ "npc:commerce", "npc:tech", "npc:industry" })[rng:NextInteger(1, 3)]
						r = cl:call(uid, "SellMarket", { companyId = npc, bps = 100 })
					elseif pick == 6 or pick == 7 then
						-- oferta a otro jugador por su parte justa
						local other = rng:NextInteger(1, N)
						local company = cl:session(other).data.companies[other .. ":1"]
						local bps = 100 * rng:NextInteger(1, 4)
						local fair = cl.server.world:stakeValue(company, bps)
						r = cl:call(uid, "MakeOffer", {
							companyId = company.id,
							sellerId = tostring(other),
							bps = bps,
							price = math.max(1, fair),
						})
					else
						-- responder a una oferta pendiente
						local incoming = cl.server.offers:pendingFor(tostring(uid), "seller")
						if #incoming > 0 then
							local act = rng:NextInteger(1, 3) == 1 and "reject" or "accept"
							r = cl:call(
								uid,
								"RespondOffer",
								{ offerId = incoming[1].id, action = act, confirm = true }
							)
						end
					end
					if r then
						calls += 1
						if r.ok then
							okCalls += 1
						end
					end
				end

				-- invariantes cada 10 s
				if second % 10 == 0 then
					for _, s in cl.server.world.sessions do
						local cash = s.data.cash
						if not (cash >= 0 and cash % 1 == 0 and cash <= Balance.MaxCash) then
							error("cash inválido: " .. tostring(cash))
						end
						for _, company in s.data.companies do
							local ok, why = Ownership.validate(company.cap)
							if not ok then
								error("cap inválida " .. company.id .. ": " .. tostring(why))
							end
						end
					end
					for _, npc in cl.server.world.npcs do
						local ok, why = Ownership.validate(npc.cap)
						if not ok then
							error("cap inválida " .. npc.id .. ": " .. tostring(why))
						end
						t:expect(npc.cap.holders[Ownership.MARKET] >= 10000 - Balance.Npc.FloatCapBps)
							:toBe(true)
					end
				end
			end
			local elapsed = os.clock() - started

			t:expect(calls > 800):toBe(true)
			t:expect(okCalls > 200):toBe(true)
			-- Ningún error interno ni de guardado durante toda la partida
			for _, line in cl.logs do
				if line:find("fallo en") or line:find("error en") or line:find("INTERNAL") then
					error("registro de error durante la carga: " .. line)
				end
			end
			-- Rendimiento: el tick más lento y el total, con margen amplio (la CPU del entorno es limitada)
			if process.env.TAKEOVER_LOAD_REPORT then
				print(
					string.format(
						"[carga] 30 jugadores x 180 s: %d acciones (%d ok), tick mas lento %.1f ms, total %.2f s",
						calls,
						okCalls,
						worst * 1000,
						elapsed
					)
				)
			end
			t:expect(worst < 0.25):toBe(true)
			t:expect(elapsed < 30):toBe(true)
		end)

		t:test("tráfico de red razonable: mensajes por segundo y tamaño de la foto por jugador", function()
			local cl = Cluster.new(load, { seed = 3 })
			local N = 30
			for i = 1, N do
				cl:join(i, "J" .. i, veteran(50_000))
			end
			cl:clearPushes()
			cl:run(60) -- un minuto de juego sin acciones: sólo ingresos
			local perPlayer = 0
			for uid = 1, N do
				perPlayer += #(cl.pushes[uid] or {})
			end
			perPlayer /= N
			-- Sin acciones, cada jugador recibe pocas fotos por minuto (reenvío de seguridad cada 5 s,
			-- ranking cada 5 s): nada de un mensaje por segundo.
			t:expect(perPlayer < 40):toBe(true)
			local sizes = 0
			local count = 0
			for _, m in cl.pushes[1] do
				if m.type == "state" then
					sizes = math.max(sizes, weight(m))
					count += 1
				end
			end
			t:expect(count > 0):toBe(true)
			t:expect(sizes < 24_000):toBe(true) -- una foto completa pesa unos pocos KB
		end)

		t:test("mensajes públicos (ranking) acotados al top 10 aunque haya 30 jugadores", function()
			local cl = Cluster.new(load)
			for i = 1, 30 do
				cl:join(i, "J" .. i, veteran(1000 * i))
			end
			cl:run(Balance.RankingRefreshSeconds + 1)
			local boards = cl:messages(1, "leaderboard")
			local last = boards[#boards]
			t:expect(#last.players):toBe(10)
			t:expect(#last.companies):toBe(10)
			t:expect(last.players[1].name):toBe("J30")
		end)

		t:test(
			"las ofertas simultáneas sobre la misma empresa nunca crean participaciones de más",
			function()
				local cl = Cluster.new(load, { seed = 9 })
				for i = 1, 12 do
					cl:join(i, "J" .. i, veteran(500_000))
				end
				local company = cl:session(1).data.companies["1:1"]
				company.level, company.upgrades.shelves = 3, 10
				local fair = cl.server.world:stakeValue(company, 500)
				-- 11 compradores quieren el mismo 5 %; el vendedor tiene el 100 %: sólo caben si hay estructura
				local offers = {}
				for i = 2, 12 do
					local r = cl:call(
						i,
						"MakeOffer",
						{ companyId = "1:1", sellerId = "1", bps = 500, price = fair }
					)
					if r.ok then
						table.insert(offers, r.data.offerId)
					end
				end
				t:expect(#offers):toBeGreaterThan(0)
				local accepted = 0
				for _, id in offers do
					local r = cl:call(1, "RespondOffer", { offerId = id, action = "accept", confirm = true })
					if r.ok then
						accepted += 1
					end
					-- aunque se acepten varias, la suma sigue siendo exactamente el 100 %
					local ok = Ownership.validate(company.cap)
					t:expect(ok):toBe(true)
				end
				-- tras la primera adquisición, las demás ofertas quedan obsoletas (la estructura cambió)
				t:expect(accepted):toBe(1)
				local total = 0
				for _, bps in company.cap.holders do
					total += bps
				end
				t:expect(total):toBe(10000)
			end
		)
	end)
end
