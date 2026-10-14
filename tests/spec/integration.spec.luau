--!nocheck
local Cluster = require("../harness/Cluster")

return function(t, load)
	local Balance = load:shared("Config/Balance")
	local Limits = load:shared("Config/Limits")
	local EventsConfig = load:shared("Config/Events")
	local Actions = load:server("Core/Actions")
	local Ownership = load:shared("Economy/Ownership")

	local function newCluster(options)
		return Cluster.new(load, options)
	end

	-- Dos jugadores con empresa decente y dinero (cuentas con antigüedad suficiente para comerciar).
	local function duo(cl)
		local veteran = function(cash, extra)
			return function(d)
				d.cash = cash
				d.stats.playSeconds = 99999
				d.stats.totalEarned = 50000
				d.tutorial.done = true
				if extra then
					extra(d)
				end
			end
		end
		cl:join(1, "Ana", veteran(0))
		cl:join(2, "Beto", veteran(424242))
		local a = cl:session(1)
		local c = a.data.companies["1:1"]
		c.level, c.upgrades.shelves, c.upgrades.marketing = 3, 14, 8
		return a, cl:session(2), c
	end

	t:describe("Entrada del jugador", function()
		t:test("jugador nuevo: perfil creado, empresa inicial, 100 $ y estado completo enviado", function()
			local cl = newCluster()
			local r = cl:join(1, "Ana")
			t:expect(r):toBeOk()
			local state = cl:lastState(1)
			t:expect(state.cash):toBe(100)
			t:expect(#state.companies):toBe(1)
			t:expect(state.companies[1].manages):toBe(true)
			t:expect(state.companies[1].sector):toBe("commerce")
			t:expect(state.tutorial.step):toBe(1)
			t:expect(state.recommended.id):toBe("shelves")
			t:expect(state.recommended.cost <= state.cash):toBe(true)
			t:expect(#cl:messages(1, "leaderboard")):toBeGreaterThan(0)
			t:expect(#cl:messages(1, "event")):toBeGreaterThan(0)
			t:expect(state.founding.sectors[2].unlocked):toBe(false)
		end)

		t:test("no se puede entrar dos veces con la misma cuenta", function()
			local cl = newCluster()
			cl:join(1, "Ana")
			t:expect(cl:join(1, "Ana")):toBeErr("ALREADY_JOINED")
		end)

		t:test("si se va mientras carga, no se crea sesión y se libera el bloqueo", function()
			local cl = newCluster()
			-- simulamos la carrera: el almacén tarda y PlayerRemoving llega antes
			local original = cl.store.load
			cl.store.load = function(self, key)
				local r = original(self, key)
				cl.server._present[1] = false -- se marchó durante la carga
				return r
			end
			t:expect(cl:join(1, "Ana")):toBeErr("LEFT_DURING_LOAD")
			t:expect(cl:session(1)):toBeNil()
			t:expect(cl.ds:peek("Player_1").lock):toBeNil()
		end)

		t:test("contrato: cada acción existe, tiene límite de frecuencia y viceversa", function()
			local cl = newCluster()
			cl:join(1, "Ana")
			for _, name in Actions.NAMES do
				t:expect(cl.server.dispatcher._d.actions[name] ~= nil):toBe(true)
				t:expect(Limits.Actions[name] ~= nil):toBe(true)
			end
			for name in Limits.Actions do
				t:expect(table.find(Actions.NAMES, name) ~= nil):toBe(true)
			end
		end)
	end)

	t:describe("Primera sesión completa (tutorial por acciones reales)", function()
		t:test(
			"comprar mejora -> ver ingresos -> abrir mercado -> inspeccionar -> primera inversión -> bonus",
			function()
				local cl = newCluster()
				cl:join(1, "Ana")
				local s = cl:session(1)

				-- 1) primera mejora, asequible desde el segundo 0
				local up = cl:call(1, "BuyUpgrade", { companyId = "1:1", upgradeId = "shelves" })
				t:expect(up.ok):toBe(true)
				t:expect(s.data.tutorial.step):toBe(2)
				local st = cl:lastState(1)
				t:expect(st.cash):toBe(80)
				t:expect(st.companies[1].income):toBeNear(1.7)

				-- 2) mirar crecer los ingresos (avanza solo a los pocos segundos)
				cl:run(7)
				t:expect(s.data.tutorial.step):toBe(3)

				-- 3) abrir el mercado
				local market = cl:call(1, "GetMarket", nil)
				t:expect(market.ok):toBe(true)
				t:expect(#market.data.companies):toBeGreaterThan(2) -- las 3 de la Bolsa + la suya
				t:expect(s.data.tutorial.step):toBe(4)

				-- 4) inspeccionar la empresa de la Bolsa
				local detail = cl:call(1, "InspectCompany", { companyId = "npc:commerce" })
				t:expect(detail.ok):toBe(true)
				t:expect(detail.data.isNpc):toBe(true)
				t:expect(s.data.tutorial.step):toBe(5)

				-- 5) primera inversión cuando tiene dinero
				local early = cl:call(1, "BuyMarket", { companyId = "npc:commerce", bps = 100 })
				t:expect(early.ok):toBe(false)
				t:expect(early.code):toBe("INSUFFICIENT_FUNDS")
				t:expect(early.params.missing):toBeGreaterThan(0)
				s.data.cash = 5000
				local cashBefore = s.data.cash
				local buy = cl:call(1, "BuyMarket", { companyId = "npc:commerce", bps = 100 })
				t:expect(buy.ok):toBe(true)
				t:expect(s.data.tutorial.done):toBe(true)
				t:expect(s.data.cash):toBe(cashBefore - buy.data.price + Balance.TutorialBonusCash)
				t:expect(#cl:notifications(1, "tutorial_done")):toBe(1)

				-- embudo completo registrado, una sola vez cada paso
				local steps = {}
				for _, e in cl.analytics do
					if e.kind == "funnel" then
						table.insert(steps, e.name)
					end
				end
				t:expect(steps):toEqual({
					"joined",
					"first_upgrade",
					"market_opened",
					"company_inspected",
					"first_offer",
					"tutorial_done",
				})
			end
		)

		t:test("omitir el tutorial no da bonus y no bloquea nada", function()
			local cl = newCluster()
			cl:join(1, "Ana")
			t:expect(cl:call(1, "SkipTutorial", nil).ok):toBe(true)
			t:expect(cl:lastState(1).tutorial.skipped):toBe(true)
			t:expect(cl:call(1, "BuyUpgrade", { companyId = "1:1", upgradeId = "shelves" }).ok):toBe(true)
			t:expect(cl:session(1).data.tutorial.bonusPaid):toBe(false)
		end)
	end)

	t:describe("Mercado entre dos jugadores (flujo de red completo)", function()
		t:test(
			"oferta -> aviso al vendedor -> aceptación con confirmación -> estados sincronizados",
			function()
				local cl = newCluster()
				local a, b, c = duo(cl)
				local price = cl.server.world:stakeValue(c, 3000)
				cl:clearPushes()

				local offer =
					cl:call(2, "MakeOffer", { companyId = c.id, sellerId = "1", bps = 3000, price = price })
				t:expect(offer.ok):toBe(true)
				-- el vendedor es avisado y recibe la oferta con valoración de referencia
				t:expect(#cl:notifications(1, "offer_received")):toBe(1)
				local offers = cl:messages(1, "offers")
				local incoming = offers[#offers].incoming
				t:expect(#incoming):toBe(1)
				t:expect(incoming[1].price):toBe(price)
				t:expect(incoming[1].fairPrice):toBe(price)
				t:expect(incoming[1].counterpartName):toBe("Beto")

				-- grande => exige confirmación explícita
				local noConfirm =
					cl:call(1, "RespondOffer", { offerId = offer.data.offerId, action = "accept" })
				t:expect(noConfirm.code):toBe("CONFIRMATION_REQUIRED")
				t:expect(c.cap.holders["2"]):toBeNil()

				local before = a.data.cash + b.data.cash
				local ok = cl:call(
					1,
					"RespondOffer",
					{ offerId = offer.data.offerId, action = "accept", confirm = true }
				)
				t:expect(ok.ok):toBe(true)
				t:expect(c.cap.holders["1"]):toBe(7000)
				t:expect(c.cap.holders["2"]):toBe(3000)
				t:expect(before - (a.data.cash + b.data.cash)):toBe(ok.data.tax)

				-- ambos reciben su nuevo estado y avisos
				t:expect(cl:lastState(2).portfolio[1].bps):toBe(3000)
				t:expect(cl:lastState(1).cash):toBe(a.data.cash)
				t:expect(#cl:notifications(1, "deal_closed")):toBe(1)
				t:expect(#cl:notifications(2, "offer_accepted")):toBe(1)
				t:expect(a.data.achievements.first_deal ~= nil):toBe(true)
				-- el trato se guardó de inmediato en ambos perfiles
				t:expect(cl.ds:peek("Player_1").data.companies["1:1"].cap.holders["2"]):toBe(3000)
				t:expect(cl.ds:peek("Player_2").data.holdings["1:1"].bps):toBe(3000)
			end
		)

		t:test("tomar el control (>50 %) emite un efecto público y cambia quién gestiona", function()
			local cl = newCluster()
			local a, b, c = duo(cl)
			c.level, c.upgrades = 1, {}
			local price = cl.server.world:stakeValue(c, 6000)
			local offer =
				cl:call(2, "MakeOffer", { companyId = c.id, sellerId = "1", bps = 6000, price = price })
			cl:clearPushes()
			local r = cl:call(
				1,
				"RespondOffer",
				{ offerId = offer.data.offerId, action = "accept", confirm = true }
			)
			t:expect(r.data.controlChanged):toBe(true)
			local fx = cl:messages(2, "effect")
			t:expect(#fx):toBe(1)
			t:expect(fx[1].kind):toBe("takeover")
			t:expect(fx[1].who):toBe("Beto")
			t:expect(#cl:messages(1, "effect")):toBe(1) -- todos lo ven
			t:expect(#cl:notifications(2, "control_gained")):toBe(1)
			t:expect(#cl:notifications(1, "control_lost")):toBe(1)
			t:expect(cl:call(2, "BuyUpgrade", { companyId = c.id, upgradeId = "marketing" }).ok):toBe(true)
			t:expect(cl:call(1, "BuyUpgrade", { companyId = c.id, upgradeId = "marketing" }).code)
				:toBe("NOT_MANAGER")
			t:expect(b.data.achievements.first_takeover ~= nil):toBe(true)
		end)

		t:test("rechazar, cancelar y caducar avisan a la otra parte", function()
			local cl = newCluster()
			local _, _, c = duo(cl)
			local price = cl.server.world:stakeValue(c, 1000)
			local o1 =
				cl:call(2, "MakeOffer", { companyId = c.id, sellerId = "1", bps = 1000, price = price })
			t:expect(cl:call(1, "RespondOffer", { offerId = o1.data.offerId, action = "reject" }).ok)
				:toBe(true)
			t:expect(#cl:notifications(2, "offer_rejected")):toBe(1)
			cl:run(Balance.PairTradeCooldownSeconds + 1)
			local o2 =
				cl:call(2, "MakeOffer", { companyId = c.id, sellerId = "1", bps = 1000, price = price })
			t:expect(cl:call(2, "RespondOffer", { offerId = o2.data.offerId, action = "cancel" }).ok)
				:toBe(true)
			local o3 =
				cl:call(2, "MakeOffer", { companyId = c.id, sellerId = "1", bps = 1000, price = price })
			cl:run(Balance.OfferExpirySeconds + 2)
			t:expect(#cl:notifications(1, "offer_expired")):toBeGreaterThan(0)
			t
				:expect(
					cl:call(
						1,
						"RespondOffer",
						{ offerId = o3.data.offerId, action = "accept", confirm = true }
					).code
				)
				:toBe("OFFER_NOT_PENDING")
		end)

		t:test(
			"un jugador malicioso no puede aceptar/cancelar ofertas ajenas ni usar ids inventados",
			function()
				local cl = newCluster()
				local _, _, c = duo(cl)
				cl:join(3, "Mallory")
				local price = cl.server.world:stakeValue(c, 1000)
				local o =
					cl:call(2, "MakeOffer", { companyId = c.id, sellerId = "1", bps = 1000, price = price })
				t:expect(
					cl:call(
						3,
						"RespondOffer",
						{ offerId = o.data.offerId, action = "accept", confirm = true }
					).code
				):toBe("NOT_YOUR_OFFER")
				t:expect(cl:call(3, "RespondOffer", { offerId = o.data.offerId, action = "cancel" }).code)
					:toBe("NOT_YOUR_OFFER")
				t
					:expect(
						cl:call(3, "RespondOffer", { offerId = "o9999", action = "accept", confirm = true }).code
					)
					:toBe("OFFER_NOT_FOUND")
				t:expect(cl:call(3, "RespondOffer", { offerId = "'; DROP", action = "accept" }).code)
					:toBe("BAD_REQUEST")
			end
		)

		t:test("el cliente NO puede imponer precios de mejoras ni otorgarse dinero", function()
			local cl = newCluster()
			cl:join(1, "Ana")
			-- campos extra (precio, coste, cash) se descartan: el servidor cobra lo suyo
			local r = cl:call(
				1,
				"BuyUpgrade",
				{ companyId = "1:1", upgradeId = "shelves", cost = 0, price = -999, cash = 1e9 }
			)
			t:expect(r.ok):toBe(true)
			t:expect(r.data.cost):toBe(20)
			t:expect(cl:session(1).data.cash):toBe(80)
			-- acciones inventadas de "dar dinero"
			for _, action in { "AddCash", "SetCash", "GiveMoney", "Admin" } do
				t:expect(cl:call(1, action, { amount = 1e9 }).code):toBe("BAD_REQUEST")
			end
			t:expect(cl:session(1).data.cash):toBe(80)
		end)
	end)

	t:describe("Privacidad", function()
		t:test("el Cash de otro jugador no aparece en NINGÚN mensaje ni vista que reciba", function()
			local cl = newCluster()
			local a, b, c = duo(cl)
			local secret = b.data.cash
			t:expect(secret):toBe(424242)
			cl:clearPushes()
			cl:call(1, "GetState", nil)
			local market = cl:call(1, "GetMarket", nil)
			local inspect = cl:call(1, "InspectCompany", { companyId = "2:1" })
			local lb = cl:call(1, "GetLeaderboard", nil)
			cl:run(10)
			t:expect(Cluster.contains(market.data, secret)):toBe(false)
			t:expect(Cluster.contains(inspect.data, secret)):toBe(false)
			t:expect(Cluster.contains(lb.data, secret)):toBe(false)
			for _, m in cl.pushes[1] or {} do
				t:expect(Cluster.contains(m, secret)):toBe(false)
			end
			_ = c
			_ = a
		end)

		t:test("los libros de una empresa ajena sólo se ven siendo consejero (≥ 25 %)", function()
			local cl = newCluster()
			local a, b, c = duo(cl)
			local noBooks = cl:call(2, "InspectCompany", { companyId = c.id })
			t:expect(noBooks.data.books):toBeNil()
			t:expect(noBooks.data.options):toBeNil()
			Ownership.transfer(c.cap, a.id, b.id, 2500)
			local books = cl:call(2, "InspectCompany", { companyId = c.id })
			t:expect(books.data.books ~= nil):toBe(true)
			t:expect(books.data.options):toBeNil() -- ver los libros no da poder de gestión
			t:expect(books.data.rights.tier):toBe("board")
			local owner = cl:call(1, "InspectCompany", { companyId = c.id })
			t:expect(owner.data.options ~= nil):toBe(true)
		end)

		t:test("el historial público sólo muestra tratos; las mejoras son para consejeros", function()
			local cl = newCluster()
			local a, _, c = duo(cl)
			a.data.cash = 1000
			cl:call(1, "BuyUpgrade", { companyId = c.id, upgradeId = "logistics" })
			local view = cl:call(2, "InspectCompany", { companyId = c.id })
			for _, e in view.data.history do
				t:expect(e.kind ~= "upgrade"):toBe(true)
			end
			local own = cl:call(1, "InspectCompany", { companyId = c.id })
			local sawUpgrade = false
			for _, e in own.data.history do
				sawUpgrade = sawUpgrade or e.kind == "upgrade"
			end
			t:expect(sawUpgrade):toBe(true)
		end)
	end)

	t:describe("Persistencia entre sesiones y servidores", function()
		t:test("el progreso se conserva al salir y volver (otro servidor)", function()
			local cl = newCluster()
			cl:join(1, "Ana")
			cl:call(1, "BuyUpgrade", { companyId = "1:1", upgradeId = "shelves" })
			cl:run(30)
			local cash = cl:session(1).data.cash
			local bought = cl:session(1).data.companies["1:1"].upgrades.shelves
			cl:leave(1)
			t:expect(cl:session(1)):toBeNil()
			t:expect(cl.ds:peek("Player_1").lock):toBeNil()

			local cl2 = newCluster({ ds = cl.ds, clock = cl.clock, jobId = "server-B" })
			t:expect(cl2:join(1, "Ana")):toBeOk()
			local s = cl2:session(1)
			t:expect(s.data.cash):toBe(cash)
			t:expect(s.data.companies["1:1"].upgrades.shelves):toBe(bought)
			t:expect(s.data.stats.sessions):toBe(2)
			t:expect(s.data.counters.companiesFounded):toBe(1)
		end)

		t:test("no se puede estar en dos servidores a la vez (bloqueo de sesión)", function()
			local cl = newCluster()
			cl:join(1, "Ana")
			local cl2 = newCluster({ ds = cl.ds, clock = cl.clock, jobId = "server-B" })
			t:expect(cl2:join(1, "Ana")):toBeErr("SESSION_LOCKED")
			t:expect(cl2:session(1)):toBeNil()
		end)

		t:test("tratos y estructura de propiedad sobreviven a la salida de ambos", function()
			local cl = newCluster()
			local _, _, c = duo(cl)
			local price = cl.server.world:stakeValue(c, 2000)
			local o = cl:call(2, "MakeOffer", { companyId = c.id, sellerId = "1", bps = 2000, price = price })
			cl:call(1, "RespondOffer", { offerId = o.data.offerId, action = "accept", confirm = true })
			cl:leave(2)
			cl:leave(1)
			local cl2 = newCluster({ ds = cl.ds, clock = cl.clock, jobId = "server-B" })
			cl2:join(1, "Ana")
			cl2:join(2, "Beto")
			local company = cl2:session(1).data.companies["1:1"]
			t:expect(company.cap.holders["1"]):toBe(8000)
			t:expect(company.cap.holders["2"]):toBe(2000)
			t:expect(Ownership.validate(company.cap)):toBe(true)
			t:expect(cl2:session(2).data.holdings["1:1"].bps):toBe(2000)
			-- y Beto vuelve a cobrar dividendos de la empresa de Ana
			local before = cl2:session(2).data.cash
			cl2:run(20)
			local gained = cl2:session(2).data.cash - before
			t:expect(gained):toBeGreaterThan(20) -- su empresa propia (1 $/s) + dividendos
		end)

		t:test("autoguardado cada minuto con el latido del bloqueo", function()
			local cl = newCluster()
			cl:join(1, "Ana")
			local lock0 = cl.ds:peek("Player_1").lock.t
			cl:run(Balance.AutosaveSeconds + 2)
			local rec = cl.ds:peek("Player_1")
			t:expect(rec.lock.t > lock0):toBe(true)
			t:expect(rec.data.cash >= 100 + Balance.AutosaveSeconds - 2):toBe(true)
		end)

		t:test("un servidor zombi que pierde el bloqueo expulsa al jugador en vez de pisar datos", function()
			local cl = newCluster()
			cl:join(1, "Ana")
			cl.clock:advance(1000) -- el bloqueo caduca sin latido
			local cl2 = newCluster({ ds = cl.ds, clock = cl.clock, jobId = "server-B" })
			t:expect(cl2:join(1, "Ana")):toBeOk()
			cl2:session(1).data.cash = 777
			cl2.server.store:touch(cl2:session(1).profile)
			cl2.store:save(cl2:session(1).profile)
			-- el servidor A intenta autoguardar
			cl.server.store:touch(cl:session(1).profile)
			cl:run(Balance.AutosaveSeconds + 1)
			t:expect(cl.kicked[1]):toBe("DATA_LOCK_LOST")
			t:expect(cl.ds:peek("Player_1").data.cash):toBe(777)
		end)

		t:test("apagado del servidor: guarda y libera a todos", function()
			local cl = newCluster()
			duo(cl)
			cl:call(2, "BuyUpgrade", { companyId = "2:1", upgradeId = "shelves" })
			cl.server:shutdown()
			t:expect(cl.ds:peek("Player_1").lock):toBeNil()
			t:expect(cl.ds:peek("Player_2").lock):toBeNil()
			t:expect(cl.ds:peek("Player_2").data.companies["2:1"].upgrades.shelves):toBe(1)
		end)

		t:test("si el DataStore falla al salir, el jugador no rompe el servidor", function()
			local cl = newCluster()
			cl:join(1, "Ana")
			cl.ds:failNext(100)
			cl:leave(1)
			t:expect(cl:session(1)):toBeNil()
			cl.ds:failNext(0)
		end)
	end)

	t:describe("Salida de jugadores", function()
		t:test(
			"si se va el fundador sus ofertas se anulan, la empresa deja el mundo y el inversor lo ve",
			function()
				local cl = newCluster()
				local _, _, c = duo(cl)
				local price = cl.server.world:stakeValue(c, 2000)
				local o =
					cl:call(2, "MakeOffer", { companyId = c.id, sellerId = "1", bps = 2000, price = price })
				cl:call(1, "RespondOffer", { offerId = o.data.offerId, action = "accept", confirm = true })
				cl:run(Balance.PairTradeCooldownSeconds + 1)
				local o2 = cl:call(2, "MakeOffer", {
					companyId = c.id,
					sellerId = "1",
					bps = 1000,
					price = cl.server.world:stakeValue(c, 1000),
				})
				cl:clearPushes()
				cl:leave(1)
				t:expect(cl.server.world.companies[c.id]):toBeNil()
				t:expect(#cl:notifications(2, "offer_cancelled")):toBe(1)
				t:expect(cl:call(2, "RespondOffer", { offerId = o2.data.offerId, action = "cancel" }).code)
					:toBe("OFFER_NOT_PENDING")
				cl:run(2)
				local state = cl:lastState(2)
				local found = false
				for _, p in state.portfolio do
					if p.companyId == c.id then
						found = true
						t:expect(p.online):toBe(false)
						t:expect(p.bps):toBe(2000)
					end
				end
				t:expect(found):toBe(true)
			end
		)

		t:test("su participación en la Bolsa vuelve al mercado al salir", function()
			local cl = newCluster()
			cl:join(1, "Ana", function(d)
				d.cash = 1e6
			end)
			cl:join(2, "Beto")
			cl:call(1, "BuyMarket", { companyId = "npc:commerce", bps = 1000, confirm = true })
			local npc = cl.server.world.npcs["npc:commerce"]
			t:expect(npc.cap.holders["1"]):toBe(1000)
			cl:leave(1)
			t:expect(npc.cap.holders["1"]):toBeNil()
			t:expect(npc.cap.holders[Ownership.MARKET]):toBe(10000)
			t:expect(Ownership.validate(npc.cap)):toBe(true)
			-- y al volver la recupera
			cl:join(1, "Ana")
			t:expect(npc.cap.holders["1"]):toBe(1000)
		end)
	end)

	t:describe("Eventos globales en el servidor", function()
		t:test("anuncio -> inicio -> fin, con avisos y efecto real en los ingresos", function()
			local cl = newCluster()
			cl:join(1, "Ana")
			local company = cl:session(1).data.companies["1:1"]
			local base = cl.server.world:incomeOf(company).total
			cl:run(EventsConfig.FirstEventDelaySeconds - EventsConfig.AnnounceLeadSeconds + 1)
			t:expect(#cl:notifications(1, "event_announce")):toBe(1)
			cl:run(EventsConfig.AnnounceLeadSeconds + 1)
			t:expect(#cl:notifications(1, "event_start")):toBe(1)
			local id = cl.server.events:activeId()
			local boosted = cl.server.world:incomeOf(company).total
			if EventsConfig.Events[id].incomeMult and EventsConfig.Events[id].incomeMult.commerce then
				t:expect(boosted > base):toBe(true)
			end
			cl:run(EventsConfig.Events[id].durationSeconds + 2)
			t:expect(#cl:notifications(1, "event_end")):toBe(1)
			t:expect(cl.server.world:incomeOf(company).total):toBeNear(base * (1 + 0), 0.2)
		end)
	end)

	t:describe("Alianzas por la red", function()
		t:test(
			"invitar, aceptar y salir con avisos; el bono sube los ingresos y se retira al salir",
			function()
				local cl = newCluster()
				cl:join(1, "Ana")
				cl:join(2, "Beto")
				local company = cl:session(1).data.companies["1:1"]
				local base = cl.server.world:incomeOf(company).total
				t:expect(cl:call(1, "AllianceInvite", { targetId = "2" }).ok):toBe(true)
				local invites = cl:lastState(2).alliance.invites
				t:expect(#invites):toBe(1)
				t:expect(cl:call(2, "AllianceRespond", { inviteId = invites[1].id, accept = true }).ok)
					:toBe(true)
				t:expect(cl.server.world:incomeOf(company).total):toBeNear(base * 1.03, 1e-9)
				t:expect(#cl:lastState(1).alliance.members):toBe(2)
				t:expect(cl:call(1, "AllianceLeave", nil).ok):toBe(true)
				t:expect(cl.server.world:incomeOf(company).total):toBeNear(base, 1e-9)
				t:expect(#cl:notifications(2, "alliance_left")):toBe(1)
			end
		)

		t:test("invitar a alguien inexistente o a uno mismo falla limpiamente", function()
			local cl = newCluster()
			cl:join(1, "Ana")
			t:expect(cl:call(1, "AllianceInvite", { targetId = "99" }).code):toBe("TARGET_OFFLINE")
			t:expect(cl:call(1, "AllianceInvite", { targetId = "1" }).code):toBe("SAME_PARTIES")
			t:expect(cl:call(1, "AllianceLeave", nil).code):toBe("NOT_IN_ALLIANCE")
		end)
	end)

	t:describe("Rankings, recompensa diaria y ajustes", function()
		t:test("la clasificación se sincroniza y el jugador conoce su posición", function()
			local cl = newCluster()
			cl:join(1, "Ana", function(d)
				d.cash = 10
			end)
			cl:join(2, "Beto", function(d)
				d.cash = 99999
			end)
			cl:run(Balance.RankingRefreshSeconds + 1)
			local s1, s2 = cl:lastState(1), cl:lastState(2)
			t:expect(s2.rank.pos):toBe(1)
			t:expect(s1.rank.pos):toBe(2)
			t:expect(s1.rank.count):toBe(2)
			local lb = cl:call(1, "GetLeaderboard", nil).data
			t:expect(lb.players[1].name):toBe("Beto")
			t:expect(#lb.companies):toBe(2)
		end)

		t:test("nuevo número uno: efecto público", function()
			local cl = newCluster()
			cl:join(1, "Ana", function(d)
				d.cash = 100000
			end)
			cl:join(2, "Beto", function(d)
				d.cash = 10
			end)
			cl:run(Balance.RankingRefreshSeconds + 1)
			cl:clearPushes()
			cl:session(2).data.cash = 900000
			cl:run(Balance.RankingRefreshSeconds + 2)
			local fx = cl:messages(1, "effect")
			local found = false
			for _, m in fx do
				found = found or (m.kind == "new_number_one" and m.who == "Beto")
			end
			t:expect(found):toBe(true)
		end)

		t:test("recompensa diaria por la red, con enfriamiento", function()
			local cl = newCluster()
			cl:join(1, "Ana")
			local r = cl:call(1, "ClaimDaily", nil)
			t:expect(r.ok):toBe(true)
			t:expect(r.data.reward):toBeGreaterThan(0)
			t:expect(cl:call(1, "ClaimDaily", nil).code):toBe("DAILY_NOT_READY")
			t:expect(#cl:notifications(1, "daily_claimed")):toBe(1)
		end)

		t:test("ajustes y cosméticos validados", function()
			local cl = newCluster()
			cl:join(1, "Ana")
			t:expect(cl:call(1, "SetSetting", { key = "sfx", value = "off" }).ok):toBe(true)
			t:expect(cl:session(1).data.settings.sfx):toBe(false)
			t:expect(cl:call(1, "SetSetting", { key = "lang", value = "es" }).ok):toBe(true)
			t:expect(cl:call(1, "SetSetting", { key = "lang", value = "xx" }).code):toBe("BAD_REQUEST")
			t:expect(cl:call(1, "SetSetting", { key = "sfx", value = "maybe" }).code):toBe("BAD_REQUEST")
			t:expect(cl:call(1, "SetSetting", { key = "cash", value = "on" }).code):toBe("BAD_REQUEST")
			t:expect(cl:call(1, "EquipCosmetic", { slot = "effect", id = "fx_golden" }).code)
				:toBe("COSMETIC_NOT_OWNED")
			t:expect(cl:call(1, "EquipCosmetic", { slot = "effect", id = "fx_default" }).ok):toBe(true)
			t:expect(cl:call(1, "EquipCosmetic", { slot = "office", id = "fx_default" }).code)
				:toBe("COSMETIC_UNKNOWN")
			t:expect(cl:call(1, "SelectTitle", { id = "founder" }).code):toBe("TITLE_NOT_OWNED")
		end)

		t:test("fundar empresas por la red: desbloqueo, coste y estado", function()
			local cl = newCluster()
			cl:join(1, "Ana", function(d)
				d.cash = 5000
				d.stats.totalEarned = 4000
			end)
			local r = cl:call(1, "FoundCompany", { sector = "tech" })
			t:expect(r.ok):toBe(true)
			t:expect(r.data.companyId):toBe("1:2")
			cl.clock:advance(10)
			t:expect(cl:session(1).data.cash):toBe(2500)
			t:expect(#cl:lastState(1).companies):toBe(2)
			t:expect(cl:call(1, "FoundCompany", { sector = "industry" }).code):toBe("SECTOR_LOCKED")
			cl.clock:advance(10)
			t:expect(cl:call(1, "FoundCompany", { sector = "tech", parts = { 60, 1, 1 } }).code)
				:toBe("INVALID_NAME")
			cl.clock:advance(10)
			-- un índice fuera del esquema de red (> 64) ni siquiera llega a la lógica
			t:expect(cl:call(1, "FoundCompany", { sector = "tech", parts = { 99, 1, 1 } }).code)
				:toBe("BAD_REQUEST")
			t:expect(cl:call(1, "FoundCompany", { sector = "tech", parts = { 1, 1 } }).code)
				:toBe("INVALID_NAME")
		end)
	end)

	t:describe("Abuso del protocolo", function()
		t:test("spam de acciones inexistentes expulsa al jugador, sin afectar a otros", function()
			local cl = newCluster()
			cl:join(1, "Ana")
			cl:join(2, "Beto")
			for _ = 1, Limits.MaxStrikes + 5 do
				cl:call(1, "HackTheGame", { x = 1 })
				cl.clock:advance(0.2)
			end
			t:expect(cl.kicked[1]):toBe("ABUSE")
			t:expect(cl.kicked[2]):toBeNil()
		end)

		t:test("peticiones antes de cargar el perfil: NOT_READY", function()
			local cl = newCluster()
			t:expect(cl:call(7, "BuyUpgrade", { companyId = "7:1", upgradeId = "shelves" }).code)
				:toBe("NOT_READY")
		end)

		t:test("payloads hostiles no rompen ni cambian el estado", function()
			local cl = newCluster()
			cl:join(1, "Ana")
			local hostile = {
				{ companyId = {}, upgradeId = "shelves" },
				{ companyId = "1:1", upgradeId = string.rep("a", 500) },
				{ companyId = "1:1", upgradeId = "shelves; DROP" },
				{ companyId = 12345, upgradeId = 5 },
				"cadena",
				12,
				true,
			}
			for _, payload in hostile do
				local r = cl:call(1, "BuyUpgrade", payload)
				t:expect(r.ok):toBe(false)
				cl.clock:advance(1)
			end
			t:expect(cl:session(1).data.cash):toBe(100)
		end)
	end)
end
