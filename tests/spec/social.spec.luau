--!nocheck
local Game = require("../harness/Game")

return function(t, load)
	local Balance = load:shared("Config/Balance")
	local EventsConfig = load:shared("Config/Events")
	local Clock = load:shared("Util/Clock")
	local EventDirector = load:server("Core/EventDirector")
	local Alliances = load:server("Core/Alliances")
	local Leaderboard = load:server("Core/Leaderboard")
	local Progression = load:server("Core/Progression")
	local Ownership = load:shared("Economy/Ownership")
	local Random = load.Random

	t:describe("Eventos económicos", function()
		local function director(seed)
			local clock = Clock.fake()
			return EventDirector.new(clock, Random.new(seed or 1)), clock
		end

		t:test("el primer evento se anuncia con cuenta atrás y luego empieza", function()
			local d, clock = director()
			t:expect(#d:update()):toBe(0)
			t:expect(d:snapshot().nextId):toBeNil() -- aún no anunciado
			clock:advance(EventsConfig.FirstEventDelaySeconds - EventsConfig.AnnounceLeadSeconds)
			local tr = d:update()
			t:expect(tr[1].kind):toBe("announce")
			local snap = d:snapshot()
			t:expect(snap.nextId ~= nil):toBe(true)
			t:expect(snap.startsIn):toBe(EventsConfig.AnnounceLeadSeconds)
			clock:advance(EventsConfig.AnnounceLeadSeconds)
			local tr2 = d:update()
			t:expect(tr2[1].kind):toBe("start")
			t:expect(tr2[1].id):toBe(snap.nextId) -- el que se anunció es el que empieza
			t:expect(d:snapshot().active.id):toBe(snap.nextId)
		end)

		t:test("el evento termina tras su duración y programa el siguiente con pausa", function()
			local d, clock = director()
			clock:advance(EventsConfig.FirstEventDelaySeconds)
			d:update()
			local active = d:activeId()
			t:expect(active ~= nil):toBe(true)
			local dur = EventsConfig.Events[active].durationSeconds
			clock:advance(dur - 1)
			t:expect(#d:update()):toBe(0)
			t:expect(d:activeId()):toBe(active)
			clock:advance(1)
			local tr = d:update()
			t:expect(tr[1].kind):toBe("end")
			t:expect(d:activeId()):toBeNil()
			-- pausa mínima antes del siguiente anuncio
			clock:advance(EventsConfig.MinIntervalSeconds - 1)
			t:expect(#d:update()):toBe(0)
			clock:advance(EventsConfig.MaxIntervalSeconds)
			t:expect(d:update()[1].kind):toBe("announce")
		end)

		t:test("nunca se repite el mismo evento dos veces seguidas (300 ciclos)", function()
			local d, clock = director(7)
			local last
			for _ = 1, 300 do
				clock:advance(EventsConfig.FirstEventDelaySeconds + EventsConfig.MaxIntervalSeconds + 400)
				for _, tr in d:update() do
					if tr.kind == "start" then
						t:expect(tr.id ~= last):toBe(true)
						last = tr.id
					end
				end
				clock:advance(300)
				d:update()
			end
			t:expect(last ~= nil):toBe(true)
		end)

		t:test("los modificadores sólo existen mientras el evento está activo", function()
			local d, clock = director()
			t:expect(d:incomeMult("tech")):toBe(1)
			d:forceStart("tech_boom")
			t:expect(d:incomeMult("tech")):toBe(1.5)
			t:expect(d:incomeMult("commerce")):toBe(1)
			t:expect(d:hypeBonus("tech")):toBe(0.10)
			clock:advance(1000)
			d:update()
			t:expect(d:incomeMult("tech")):toBe(1)
			t:expect(d:hypeBonus("tech")):toBe(0)
		end)

		t:test("descuento del evento 'nueva oportunidad' en todos los sectores", function()
			local d = director()
			d:forceStart("new_opportunity")
			for _, s in { "commerce", "tech", "industry" } do
				t:expect(d:discount(s)):toBe(0.20)
			end
		end)

		t:test("REGLA PÚBLICA: ningún evento reduce ingresos ni sube costes", function()
			for id, def in EventsConfig.Events do
				for _, v in def.incomeMult or {} do
					t:expect(v >= 1):toBe(true)
				end
				for _, v in def.discount or {} do
					t:expect(v >= 0 and v <= Balance.MaxUpgradeDiscount):toBe(true)
				end
				t:expect(def.durationSeconds):toBeGreaterThan(0)
				local _ = id
			end
		end)

		t:test("no se puede forzar un evento si ya hay uno activo; ids desconocidos se rechazan", function()
			local d = director()
			t:expect(d:forceStart("tech_boom")):toBe(true)
			t:expect(d:forceStart("commerce_boom")):toBe(false)
			local d2 = director()
			t:expect(d2:forceStart("nope")):toBe(false)
		end)

		t:test(
			"los eventos afectan al cálculo de ingresos del mundo, no a la valoración sostenida",
			function()
				local clock = Clock.fake()
				local d = EventDirector.new(clock, Random.new(1))
				local g = Game.new(load, {
					modifiers = {
						eventIncomeMult = function(s)
							return d:incomeMult(s)
						end,
						eventDiscount = function(s)
							return d:discount(s)
						end,
						eventHypeBonus = function(s)
							return d:hypeBonus(s)
						end,
						allianceMult = function()
							return 1
						end,
					},
				})
				local p = g:addPlayer(1)
				local c = g:companyOf(p)
				local base = g.world:incomeOf(c).total
				d:forceStart("commerce_boom")
				t:expect(g.world:incomeOf(c).total):toBeNear(base * 1.5)
				t:expect(g.world:valuationOf(c)):toBe(480)
			end
		)
	end)

	t:describe("Alianzas", function()
		local function setup()
			local clock = Clock.fake()
			local online = { a = true, b = true, c = true, d = true, e = true }
			local al = Alliances.new(clock, function(id)
				return online[id] == true
			end)
			return al, clock, online
		end

		t:test("invitar, aceptar y formar alianza: +3 % de ingresos por aliado", function()
			local al = setup()
			local inv = al:invite("a", "b")
			t:expect(inv):toBeOk()
			t:expect(al:multiplierFor("a")):toBe(1)
			t:expect(al:accept("b", inv.value.id)):toBeOk()
			t:expect(al:multiplierFor("a")):toBeNear(1.03)
			t:expect(al:multiplierFor("b")):toBeNear(1.03)
			t:expect(al:membersOf("a")):toEqual({ "a", "b" })
		end)

		t:test("el bono tiene tope (+9 %) y la alianza un máximo de 4 miembros", function()
			local al = setup()
			for _, id in { "b", "c", "d" } do
				local inv = al:invite("a", id)
				t:expect(al:accept(id, inv.value.id)):toBeOk()
			end
			t:expect(al:multiplierFor("a")):toBeNear(1.09)
			t:expect(al:invite("a", "e")):toBeErr("ALLIANCE_FULL")
		end)

		t:test("sólo se acepta lo que te invitaron a ti; las invitaciones caducan", function()
			local al, clock = setup()
			local inv = al:invite("a", "b").value
			t:expect(al:accept("c", inv.id)):toBeErr("INVITE_NOT_FOUND")
			clock:advance(Balance.Alliance.InviteSeconds + 1)
			t:expect(al:accept("b", inv.id)):toBeErr("INVITE_EXPIRED")
			t:expect(al:accept("b", "i999")):toBeErr("INVITE_NOT_FOUND")
		end)

		t:test("no se puede invitar a uno mismo, a alguien desconectado o con alianza", function()
			local al, _, online = setup()
			t:expect(al:invite("a", "a")):toBeErr("SAME_PARTIES")
			online.b = false
			t:expect(al:invite("a", "b")):toBeErr("TARGET_OFFLINE")
			online.b = true
			local inv = al:invite("a", "b").value
			al:accept("b", inv.id)
			t:expect(al:invite("c", "b")):toBeErr("TARGET_IN_ALLIANCE")
		end)

		t:test("invitaciones duplicadas y exceso de invitaciones pendientes", function()
			local al = setup()
			t:expect(al:invite("a", "b")):toBeOk()
			t:expect(al:invite("a", "b")):toBeErr("DUPLICATE_INVITE")
			t:expect(al:invite("a", "c")):toBeOk()
			t:expect(al:invite("a", "d")):toBeOk()
			t:expect(al:invite("a", "e")):toBeErr("TOO_MANY_INVITES")
		end)

		t:test("salir: enfriamiento antes de unirse a otra; la alianza de 2 se disuelve", function()
			local al, clock = setup()
			local inv = al:invite("a", "b").value
			al:accept("b", inv.id)
			t:expect(al:leave("b")):toBeOk()
			t:expect(al:multiplierFor("a")):toBe(1) -- queda uno solo: disuelta
			t:expect(al:membersOf("a")):toEqual({})
			t:expect(al:invite("c", "b")):toBeErr("ALLIANCE_COOLDOWN")
			clock:advance(Balance.Alliance.RejoinCooldownSeconds + 1)
			t:expect(al:invite("c", "b")):toBeOk()
			t:expect(al:leave("e")):toBeErr("NOT_IN_ALLIANCE")
		end)

		t:test("desconexión: sin penalización y se recalcula el bono de los demás", function()
			local al = setup()
			for _, id in { "b", "c" } do
				al:accept(id, al:invite("a", id).value.id)
			end
			t:expect(al:multiplierFor("a")):toBeNear(1.06)
			al:onPlayerLeft("c")
			t:expect(al:multiplierFor("a")):toBeNear(1.03)
			al:onPlayerLeft("b")
			t:expect(al:multiplierFor("a")):toBe(1)
			-- sin enfriamiento tras desconectar
			t:expect(al:invite("d", "c")):toBeOk()
		end)

		t:test("la alianza no restringe tratos: una alianza no bloquea ofertas de terceros", function()
			local g = Game.new(load)
			local a = g:addPlayer(1)
			local b = g:addPlayer(2)
			local x = g:addPlayer(3)
			local al = Alliances.new(g.clock, function(id)
				return g.world.sessions[id] ~= nil
			end)
			al:accept("2", al:invite("1", "2").value.id)
			a.data.cash, b.data.cash, x.data.cash = 0, 0, 1e6
			local c = g:companyOf(a)
			c.level, c.upgrades.shelves = 3, 14
			local price = g.world:stakeValue(c, 2000)
			-- el tercero (fuera de la alianza) puede comprar igual a un miembro
			local o = g.trade:createOffer(x, { companyId = c.id, sellerId = a.id, bps = 2000, price = price })
			t:expect(o):toBeOk()
			t:expect(g.trade:acceptOffer(a, o.value.id, true)):toBeOk()
		end)
	end)

	t:describe("Rankings", function()
		t:test("empresas por valoración y jugadores por patrimonio, con desempate estable", function()
			local g = Game.new(load)
			local a = g:addPlayer(1, "Ana")
			local b = g:addPlayer(2, "Beto")
			local c = g:addPlayer(3, "Cris")
			g:companyOf(b).upgrades.shelves = 10
			g:companyOf(c).upgrades.shelves = 5
			b.data.cash, a.data.cash, c.data.cash = 5, 5000, 20
			local r = Leaderboard.compute(g.world, 10)
			t:expect(r.companies[1].id):toBe("2:1")
			t:expect(r.companies[2].id):toBe("3:1")
			t:expect(r.companies[3].id):toBe("1:1")
			t:expect(r.companies[1].rank):toBe(1)
			t:expect(r.players[1].userId):toBe("1")
			t:expect(r.positions["1"].playerRank):toBe(1)
			t:expect(r.positions["2"].playerCount):toBe(3)
		end)

		t:test("incluye el valor de las participaciones en el patrimonio", function()
			local g = Game.new(load)
			local a = g:addPlayer(1, "Ana")
			local b = g:addPlayer(2, "Beto")
			g:companyOf(a).upgrades.shelves = 14
			g:companyOf(a).level = 4
			Ownership.transfer(g:companyOf(a).cap, "1", "2", 4000)
			local r = Leaderboard.compute(g.world, 10)
			local nwB = g.world:netWorth(b)
			t:expect(nwB > b.data.cash + g.world:valuationOf(g:companyOf(b))):toBe(true)
			t:expect(r.positions["2"].netWorth):toBe(nwB)
		end)

		t:test("el límite recorta las tablas pero las posiciones cubren a todos", function()
			local g = Game.new(load)
			for i = 1, 5 do
				g:addPlayer(i, "P" .. i)
			end
			local r = Leaderboard.compute(g.world, 3)
			t:expect(#r.companies):toBe(3)
			t:expect(#r.players):toBe(3)
			t:expect(r.positions["5"] ~= nil):toBe(true)
		end)

		t:test("insignias de posición por patrimonio y registro del máximo histórico", function()
			t:expect(Leaderboard.badgeFor(0)):toBe("startup")
			t:expect(Leaderboard.badgeFor(4999)):toBe("startup")
			t:expect(Leaderboard.badgeFor(5000)):toBe("entrepreneur")
			t:expect(Leaderboard.badgeFor(60000)):toBe("executive")
			t:expect(Leaderboard.badgeFor(2e6)):toBe("magnate")
			t:expect(Leaderboard.badgeFor(1e9)):toBe("tycoon")
			local g = Game.new(load)
			local p = g:addPlayer(1)
			p.data.cash = 777
			Leaderboard.compute(g.world, 5)
			t:expect(p.data.stats.peakNetWorth >= 777):toBe(true)
			p.data.cash = 10
			Leaderboard.compute(g.world, 5)
			t:expect(p.data.stats.peakNetWorth >= 777):toBe(true) -- no baja
		end)

		t:test("servidor vacío: sin errores", function()
			local g = Game.new(load)
			local r = Leaderboard.compute(g.world, 10)
			t:expect(#r.companies):toBe(0)
			t:expect(#r.players):toBe(0)
		end)
	end)

	t:describe("Progresión", function()
		local function setup()
			local g = Game.new(load)
			local p = g:addPlayer(1, "Ana")
			local prog =
				Progression.new({ world = g.world, ledger = g.ledger, clock = g.clock, touch = g.touch })
			return g, p, prog
		end

		t:test("tutorial: cada paso avanza sólo con su acción real y el bonus se paga una vez", function()
			local g, p, prog = setup()
			t:expect(prog:event(p, "market_opened").advanced):toBe(false) -- fuera de orden: no avanza
			t:expect(prog:event(p, "upgrade_bought").advanced):toBe(true)
			t:expect(p.data.tutorial.step):toBe(2)
			t:expect(prog:tick(p)):toBeNil() -- aún no ha pasado el tiempo
			g.clock:advance(7)
			local auto = prog:tick(p)
			t:expect(auto ~= nil and auto.advanced):toBe(true)
			t:expect(p.data.tutorial.step):toBe(3)
			prog:event(p, "market_opened")
			prog:event(p, "company_inspected")
			local cash = p.data.cash
			local last = prog:event(p, "first_offer")
			t:expect(last.completed):toBe(true)
			t:expect(last.reward):toBe(Balance.TutorialBonusCash)
			t:expect(p.data.cash):toBe(cash + Balance.TutorialBonusCash)
			t:expect(p.data.tutorial.done):toBe(true)
			-- repetir no vuelve a pagar
			t:expect(prog:event(p, "first_offer").reward):toBe(0)
			t:expect(p.data.cash):toBe(cash + Balance.TutorialBonusCash)
		end)

		t:test("omitir el tutorial lo cierra sin bonus y sin volver a molestar", function()
			local _, p, prog = setup()
			prog:skipTutorial(p)
			t:expect(prog:tutorialActive(p)):toBe(false)
			local cash = p.data.cash
			t:expect(prog:event(p, "upgrade_bought").advanced):toBe(false)
			t:expect(p.data.cash):toBe(cash)
			t:expect(p.data.tutorial.bonusPaid):toBe(false)
		end)

		t:test("logros: se conceden una sola vez por condiciones del servidor", function()
			local g, p, prog = setup()
			t:expect(prog:checkAchievements(p, nil)):toEqual({})
			g.ops:buyUpgrade(p, "1:1", "shelves")
			t:expect(prog:checkAchievements(p, nil)):toEqual({ "first_upgrade" })
			t:expect(prog:checkAchievements(p, nil)):toEqual({}) -- ya concedido
			p.data.stats.dealsClosed = 1
			t:expect(prog:checkAchievements(p, nil)):toEqual({ "first_deal" })
		end)

		t:test("primera adquisición: gestionar una empresa que no fundaste", function()
			local g, p, prog = setup()
			local other = g:addPlayer(2, "Beto")
			Ownership.transfer(g:companyOf(other).cap, "2", "1", 6000)
			local got = prog:checkAchievements(p, nil)
			t:expect(table.find(got, "first_takeover") ~= nil):toBe(true)
		end)

		t:test("número uno: exige ser primero con al menos dos jugadores", function()
			local _, p, prog = setup()
			t:expect(table.find(prog:checkAchievements(p, { playerRank = 1, playerCount = 1 }), "number_one"))
				:toBeNil()
			t:expect(
				table.find(prog:checkAchievements(p, { playerRank = 1, playerCount = 2 }), "number_one")
					~= nil
			):toBe(true)
		end)

		t:test("millonario por patrimonio neto, no por Cash prestado", function()
			local _, p, prog = setup()
			p.data.cash = 990_000 -- + la empresa propia suma < 10 000, no llega
			t:expect(table.find(prog:checkAchievements(p, nil), "millionaire")):toBeNil()
			p.data.cash = 1_100_000
			t:expect(table.find(prog:checkAchievements(p, nil), "millionaire") ~= nil):toBe(true)
		end)

		t:test("títulos: sólo los que posees; '' los quita", function()
			local g, p, prog = setup()
			g.ops:buyUpgrade(p, "1:1", "shelves")
			prog:checkAchievements(p, nil)
			t:expect(prog:selectTitle(p, "first_upgrade")):toBeOk()
			t:expect(p.data.titles.selected):toBe("first_upgrade")
			t:expect(prog:selectTitle(p, "tycoon_king")):toBeErr("TITLE_NOT_OWNED")
			t:expect(prog:selectTitle(p, "")):toBeOk()
			-- un título comprado
			p.data.cosmetics.owned["title:founder"] = true
			t:expect(prog:selectTitle(p, "founder")):toBeOk()
		end)

		t:test("recompensa diaria: reloj del servidor, enfriamiento, racha y tope", function()
			local g, p, prog = setup()
			t:expect(prog:dailyStatus(p).ready):toBe(true)
			local r1 = prog:claimDaily(p, 1)
			t:expect(r1):toBeOk()
			t:expect(r1.value.reward):toBe(Balance.Daily.BaseCash)
			t:expect(r1.value.streak):toBe(1)
			t:expect(prog:claimDaily(p, 1)):toBeErr("DAILY_NOT_READY")
			t:expect(prog:dailyStatus(p).ready):toBe(false)
			g.clock:advance(Balance.Daily.CooldownSeconds + 1)
			local r2 = prog:claimDaily(p, 1)
			t:expect(r2.value.streak):toBe(2)
			t:expect(r2.value.reward):toBe(math.floor(Balance.Daily.BaseCash * 1.1))
			-- si pasa demasiado tiempo se pierde la racha
			g.clock:advance(Balance.Daily.CooldownSeconds + 3 * 24 * 3600)
			t:expect(prog:claimDaily(p, 1).value.streak):toBe(1)
		end)

		t:test(
			"la recompensa diaria escala con los ingresos pero con tope de 15 min de producción",
			function()
				local g, p, prog = setup()
				local rate = 1000
				local r = prog:claimDaily(p, rate)
				t:expect(r.value.reward):toBe(rate * Balance.Daily.IncomeSeconds)
				t:expect(r.value.reward <= rate * Balance.Daily.MaxIncomeSeconds):toBe(true)
				for _ = 1, 10 do
					g.clock:advance(Balance.Daily.CooldownSeconds + 1)
					local x = prog:claimDaily(p, rate)
					t:expect(x.value.reward <= rate * Balance.Daily.MaxIncomeSeconds):toBe(true)
					t:expect(x.value.streak <= Balance.Daily.MaxStreak):toBe(true)
				end
			end
		)
	end)
end
