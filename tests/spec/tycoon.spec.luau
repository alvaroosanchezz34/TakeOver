--!nocheck
local Game = require("../harness/Game")

return function(t, load)
	local Balance = load:shared("Config/Balance")
	local Ownership = load:shared("Economy/Ownership")
	local Income = load:shared("Economy/Income")
	local Random = load.Random

	local function newGame(options)
		return Game.new(load, options)
	end

	t:describe("Inicio de partida", function()
		t:test("jugador nuevo: 100 $, una empresa de Comercio al 100 % y 1 $/s", function()
			local g = newGame()
			local p = g:addPlayer(1, "Ana")
			t:expect(g:cash(p)):toBe(100)
			local c = g:companyOf(p)
			t:expect(c.sector):toBe("commerce")
			t:expect(c.level):toBe(1)
			t:expect(c.cap.holders["1"]):toBe(10000)
			t:expect(g.world:incomeOf(c).total):toBeNear(1.0)
			t:expect(g.world:valuationOf(c)):toBe(480)
			t:expect(p.data.counters.companiesFounded):toBe(1)
		end)

		t:test("la empresa inicial sólo se crea una vez", function()
			local g = newGame()
			local p = g:addPlayer(1)
			t:expect(g.ops:ensureStarterCompany(p)):toBeNil()
			t:expect(g.ops:countOwned(p)):toBe(1)
		end)

		t:test("si borra su empresa de los datos, no se regala otra (contador > 0)", function()
			local g = newGame()
			local p = g:addPlayer(1)
			p.data.companies = {}
			t:expect(g.ops:ensureStarterCompany(p)):toBeNil()
		end)

		t:test("empieza a ganar dinero desde el primer tick", function()
			local g = newGame()
			local p = g:addPlayer(1)
			g:run(1)
			t:expect(g:cash(p)):toBe(101)
		end)
	end)

	t:describe("Producción automática", function()
		t:test("10 s de producción = 10 $ (1 $/s)", function()
			local g = newGame()
			local p = g:addPlayer(1)
			g:run(10)
			t:expect(g:cash(p)):toBe(110)
			t:expect(p.data.stats.totalEarned):toBe(10)
		end)

		t:test(
			"las fracciones se acumulan: ticks de 0,1 s a 1 $/s dan 10 $ en 10 s sin perder ni inventar",
			function()
				local g = newGame()
				local p = g:addPlayer(1)
				local c = g:companyOf(p)
				g:run(10, 0.1)
				t:expect(g:cash(p)):toBe(110)
				t:expect(c.carry["1"] >= 0 and c.carry["1"] < 1):toBe(true)
			end
		)

		t:test("CONSERVACIÓN: Cash creado + fracciones pendientes == producción (sin deriva)", function()
			local g = newGame()
			local p = g:addPlayer(1)
			local c = g:companyOf(p)
			c.upgrades.shelves = 3 -- 1 + 2,1 = 3,1 $/s (menos de 300 s: sin lealtad)
			local startCash = g:cash(p)
			g:run(250, 0.37)
			local seconds = math.floor(250 / 0.37 + 1e-9) * 0.37
			local produced = 3.1 * seconds
			local credited = g:cash(p) - startCash
			t:expect(math.abs(credited + c.carry["1"] - produced) < 1e-6):toBe(true)
			t:expect(credited % 1):toBe(0)
		end)

		t:test("un tick atrasado (servidor atascado) se limita a MaxTickDelta", function()
			local g = newGame()
			local p = g:addPlayer(1)
			g.engine:tick(10_000)
			t:expect(g:cash(p)):toBe(100 + Balance.MaxTickDelta)
		end)

		t:test("dt negativo o cero no crea ni quita dinero", function()
			local g = newGame()
			local p = g:addPlayer(1)
			g.engine:tick(-5)
			g.engine:tick(0)
			t:expect(g:cash(p)):toBe(100)
		end)

		t:test("los eventos aumentan lo cobrado pero no la valoración", function()
			local boost = 1.5
			local g = newGame({
				modifiers = {
					eventIncomeMult = function()
						return boost
					end,
					eventDiscount = function()
						return 0
					end,
					eventHypeBonus = function()
						return 0
					end,
					allianceMult = function()
						return 1
					end,
				},
			})
			local p = g:addPlayer(1)
			local c = g:companyOf(p)
			t:expect(g.world:incomeOf(c).total):toBeNear(1.5)
			t:expect(g.world:valuationOf(c)):toBe(480)
			g:run(10)
			t:expect(g:cash(p)):toBe(115)
		end)

		t:test("sólo producen las empresas cuyo fundador está en el servidor", function()
			local g = newGame()
			local a = g:addPlayer(1)
			local b = g:addPlayer(2)
			g:run(5)
			g:removePlayer(b)
			local before = b.data.cash
			g:run(5)
			t:expect(b.data.cash):toBe(before)
			t:expect(a.data.cash):toBe(110)
		end)

		t:test("lealtad de Comercio: sube con el tiempo de sesión", function()
			local g = newGame()
			local p = g:addPlayer(1)
			local c = g:companyOf(p)
			g:run(600)
			t:expect(g.world:incomeOf(c).mechanic):toBeNear(1.02, 1e-9)
		end)
	end)

	t:describe("Mejoras", function()
		t:test("comprar la primera mejora cuesta 20 $, sube ingresos a 1,7 $/s y se registra", function()
			local g = newGame()
			local p = g:addPlayer(1)
			local r = g.ops:buyUpgrade(p, "1:1", "shelves")
			t:expect(r):toBeOk()
			t:expect(r.value.cost):toBe(20)
			t:expect(r.value.newLevel):toBe(1)
			t:expect(r.value.income):toBeNear(1.7, 1e-9)
			t:expect(g:cash(p)):toBe(80)
			t:expect(p.data.stats.upgradesBought):toBe(1)
			t:expect(p.data.stats.totalSpent):toBe(20)
			local c = g:companyOf(p)
			t:expect(c.history[#c.history].kind):toBe("upgrade")
		end)

		t:test("la mejora de cada compra sube de precio", function()
			local g = newGame()
			local p = g:addPlayer(1)
			p.data.cash = 1000
			local prices = {}
			for _ = 1, 4 do
				prices[#prices + 1] = g.ops:buyUpgrade(p, "1:1", "shelves").value.cost
			end
			t:expect(prices):toEqual({ 20, 27, 35, 46 })
		end)

		t:test("sin fondos: error con lo que falta y NADA cambia", function()
			local g = newGame()
			local p = g:addPlayer(1)
			p.data.cash = 10
			local c = g:companyOf(p)
			local r = g.ops:buyUpgrade(p, "1:1", "shelves")
			t:expect(r):toBeErr("INSUFFICIENT_FUNDS")
			t:expect(r.params.missing):toBe(10)
			t:expect(g:cash(p)):toBe(10)
			t:expect(c.upgrades.shelves):toBeNil()
			t:expect(p.data.stats.upgradesBought):toBe(0)
		end)

		t:test("mejora desconocida, empresa inexistente y empresa ajena", function()
			local g = newGame()
			local a = g:addPlayer(1)
			local b = g:addPlayer(2)
			t:expect(g.ops:buyUpgrade(a, "1:1", "nope")):toBeErr("UPGRADE_UNKNOWN")
			t:expect(g.ops:buyUpgrade(a, "1:1", "servers")):toBeErr("UPGRADE_UNKNOWN") -- de otro sector
			t:expect(g.ops:buyUpgrade(a, "9:9", "shelves")):toBeErr("COMPANY_NOT_FOUND")
			t:expect(g.ops:buyUpgrade(b, "1:1", "shelves")):toBeErr("NOT_MANAGER")
			t:expect(g:cash(b)):toBe(100)
		end)

		t:test("no se puede superar el nivel máximo de una mejora", function()
			local g = newGame()
			local p = g:addPlayer(1)
			p.data.cash = 1e12
			for _ = 1, 14 do
				t:expect(g.ops:buyUpgrade(p, "1:1", "shelves")):toBeOk()
			end
			t:expect(g.ops:buyUpgrade(p, "1:1", "shelves")):toBeErr("MAXED")
			t:expect(g:companyOf(p).upgrades.shelves):toBe(14)
		end)

		t:test("los descuentos (logística y eventos) rebajan el precio con tope", function()
			local g = newGame()
			local p = g:addPlayer(1)
			p.data.cash = 1000
			local c = g:companyOf(p)
			c.upgrades.logistics = 2 -- 6 % de descuento
			local r = g.ops:buyUpgrade(p, "1:1", "marketing") -- base 120
			t:expect(r.value.cost):toBe(113) -- ceil(120 * 0.94) = 113 (112,8)
		end)

		t:test("subir de nivel: coste, tope y licencias", function()
			local g = newGame()
			local p = g:addPlayer(1)
			p.data.cash = 1e9
			local r = g.ops:levelUp(p, "1:1")
			t:expect(r.value.cost):toBe(150)
			t:expect(r.value.newLevel):toBe(2)
			t:expect(g.ops:levelUp(p, "1:1").value.cost):toBe(450)
			g.ops:levelUp(p, "1:1")
			t:expect(g:companyOf(p).level):toBe(4)
			t:expect(g.ops:levelUp(p, "1:1")):toBeErr("LEVEL_CAP")
			g.ops:buyUpgrade(p, "1:1", "license")
			t:expect(g.ops:levelUp(p, "1:1")):toBeOk()
			t:expect(g:companyOf(p).level):toBe(5)
		end)

		t:test("cada compra marca el perfil como modificado (se guardará)", function()
			local g = newGame()
			local p = g:addPlayer(1)
			p.profile.dirty = false
			local rev = p.profile.rev
			g.ops:buyUpgrade(p, "1:1", "shelves")
			t:expect(p.profile.dirty):toBe(true)
			t:expect(p.profile.rev > rev):toBe(true)
		end)
	end)

	t:describe("Nuevas empresas y sectores", function()
		t:test("Tecnología está bloqueada hasta ganar 3 000 $ en total", function()
			local g = newGame()
			local p = g:addPlayer(1)
			p.data.cash = 1e6
			local r = g.ops:found(p, "tech")
			t:expect(r):toBeErr("SECTOR_LOCKED")
			t:expect(r.params.need):toBe(3000)
			p.data.stats.totalEarned = 3000
			t:expect(g.ops:found(p, "tech")):toBeOk()
		end)

		t:test("fundar cobra el coste, crea la empresa al 100 % y la registra", function()
			local g = newGame()
			local p = g:addPlayer(1)
			p.data.cash = 5000
			p.data.stats.totalEarned = 3000
			local r = g.ops:found(p, "tech", { 2, 3, 4 }, { icon = 5, color = 6 })
			t:expect(r):toBeOk()
			t:expect(g:cash(p)):toBe(2500)
			local c = r.value
			t:expect(c.id):toBe("1:2")
			t:expect(c.name):toBe("Apex Data Corp.")
			t:expect(c.logo.icon):toBe(5)
			t:expect(c.cap.holders["1"]):toBe(10000)
			t:expect(g.world.companies["1:2"]):toBe(c)
			t:expect(p.data.companies["1:2"]):toBe(c)
		end)

		t:test("sin fondos no se crea nada ni se cobra", function()
			local g = newGame()
			local p = g:addPlayer(1)
			p.data.cash = 2499
			p.data.stats.totalEarned = 99999
			t:expect(g.ops:found(p, "tech")):toBeErr("INSUFFICIENT_FUNDS")
			t:expect(g:cash(p)):toBe(2499)
			t:expect(g.ops:countOwned(p)):toBe(1)
			t:expect(p.data.counters.companiesFounded):toBe(1)
		end)

		t:test("máximo 3 empresas por jugador", function()
			local g = newGame()
			local p = g:addPlayer(1)
			p.data.cash = 1e9
			p.data.stats.totalEarned = 1e9
			t:expect(g.ops:found(p, "commerce")):toBeOk()
			t:expect(g.ops:found(p, "tech")):toBeOk()
			t:expect(g.ops:found(p, "industry")):toBeErr("SLOTS_FULL")
			t:expect(g.ops:countOwned(p)):toBe(3)
		end)

		t:test("nombres y logotipos inválidos se rechazan sin cobrar", function()
			local g = newGame()
			local p = g:addPlayer(1)
			p.data.cash = 1e9
			t:expect(g.ops:found(p, "commerce", { 99, 1, 1 })):toBeErr("INVALID_NAME")
			t:expect(g.ops:found(p, "commerce", { 1, 1, 1 }, { icon = 0, color = 1 })):toBeErr("INVALID_LOGO")
			t:expect(g.ops:found(p, "nope")):toBeErr("SECTOR_UNKNOWN")
			t:expect(g:cash(p)):toBe(1e9)
		end)

		t:test("renombrar y cambiar logotipo: sólo el gestor, con cooldown", function()
			local g = newGame()
			local a = g:addPlayer(1)
			local b = g:addPlayer(2)
			t:expect(g.ops:rename(b, "1:1", { 1, 1, 1 })):toBeErr("NOT_MANAGER")
			local r = g.ops:rename(a, "1:1", { 2, 2, 2 })
			t:expect(r):toBeOk()
			t:expect(r.value):toBe("Apex Retail Group")
			t:expect(g.ops:rename(a, "1:1", { 3, 3, 3 })):toBeErr("COOLDOWN")
			-- el logotipo tiene su propio enfriamiento: guardar nombre y logo seguidos es válido
			t:expect(g.ops:setLogo(a, "1:1", 2, 2)):toBeOk()
			t:expect(g.ops:setLogo(a, "1:1", 3, 3)):toBeErr("COOLDOWN")
			g.clock:advance(21)
			t:expect(g.ops:setLogo(a, "1:1", 3, 3)):toBeOk()
			g.clock:advance(21)
			t:expect(g.ops:rename(a, "1:1", { 0, 1, 1 })):toBeErr("INVALID_NAME")
			t:expect(g.ops:setLogo(a, "1:1", 99, 1)):toBeErr("INVALID_LOGO")
		end)
	end)

	t:describe("Dividendos y propiedad compartida", function()
		local function shared(g, bps)
			local a = g:addPlayer(1, "Fundadora")
			local b = g:addPlayer(2, "Inversor")
			local c = g:companyOf(a)
			c.upgrades.shelves = 9 -- 1 + 6,3 = 7,3 $/s
			Ownership.transfer(c.cap, "1", "2", bps)
			return a, b, c
		end

		t:test("el beneficio se reparte según los porcentajes (40 % al inversor)", function()
			local g = newGame()
			local a, b = shared(g, 4000)
			local ca, cb = g:cash(a), g:cash(b)
			g:run(100)
			local gotA, gotB = g:cash(a) - ca, g:cash(b) - cb
			-- b cobra además lo que produce su propia empresa (1 $/s): 100 + 40 % de 730
			t:expect(gotB):toBeAtLeast(100 + 291)
			t:expect(gotB):toBeAtMost(100 + 293)
			-- a cobra el 60 % de 730 + su parte
			t:expect(gotA):toBeAtLeast(437)
			t:expect(gotA):toBeAtMost(439)
		end)

		t:test("CONSERVACIÓN con tres titulares y cientos de ticks fraccionarios", function()
			local g = newGame()
			local a, b, c = shared(g, 3333)
			local d = g:addPlayer(3, "Tercero")
			Ownership.transfer(c.cap, "1", "3", 3333)
			local before = g:totalCash()
			g:run(250, 0.3)
			local seconds = math.floor(250 / 0.3 + 1e-9) * 0.3
			local produced = (7.3 + 1.0 + 1.0) * seconds -- empresa compartida + las dos propias
			local carries = 0
			for _, s in g.world.sessions do
				for _, comp in s.data.companies do
					for _, f in comp.carry do
						carries += f
					end
				end
			end
			local delta = g:totalCash() - before
			t:expect(math.abs(delta + carries - produced) < 1e-6):toBe(true)
			t:expect(a.data.cash % 1 + b.data.cash % 1 + d.data.cash % 1):toBe(0)
		end)

		t:test("el reparto no tiene sesgo de redondeo a largo plazo (20 % de 10,8 $/s)", function()
			local g = newGame()
			local a = g:addPlayer(1)
			local x = g:addPlayer(2)
			local c = g:companyOf(a)
			c.upgrades.shelves = 14 -- 1 + 9,8 = 10,8 $/s
			Ownership.transfer(c.cap, "1", "2", 2000)
			local before = x.data.cash
			g:run(200) -- 2 160 $ producidos
			local got = x.data.cash - before - 200 -- descontamos la propia empresa de x (1 $/s)
			t:expect(got):toBeAtLeast(math.floor(2160 * 0.2) - 1)
			t:expect(got):toBeAtMost(math.floor(2160 * 0.2) + 1)
		end)

		t:test("un titular desconectado acumula dividendos (con tope) y los cobra al volver", function()
			local g = newGame()
			local a, b, c = shared(g, 5000)
			g:removePlayer(b)
			g:run(60)
			local pending = c.unclaimed["2"]
			t:expect(pending):toBeGreaterThan(0)
			t:expect(b.data.cash):toBe(100) -- b no cobra mientras está fuera
			-- vuelve
			g.world:addSession(b)
			local before = b.data.cash
			g:run(1)
			t:expect(b.data.cash - before >= pending):toBe(true)
			t:expect(c.unclaimed["2"]):toBeNil()
		end)

		t:test("los dividendos pendientes tienen tope (no crecen sin límite)", function()
			local g = newGame()
			local a, b, c = shared(g, 5000)
			g:removePlayer(b)
			g:run(Balance.UnclaimedDividendCapSeconds * 3)
			-- la lealtad de Comercio puede subir los ingresos hasta +10 %
			local cap = math.floor(7.3 * 1.1 * Balance.UnclaimedDividendCapSeconds * 5000 / 10000) + 1
			t:expect(c.unclaimed["2"]):toBeAtMost(cap)
			t:expect(c.unclaimed["2"]):toBeAtLeast(math.floor(cap * 0.8))
			_ = a
		end)

		t:test("comprar mejoras como inversor minoritario NO está permitido; con >50 % sí", function()
			local g = newGame()
			local a, b = shared(g, 4000)
			b.data.cash = 1000
			t:expect(g.ops:buyUpgrade(b, "1:1", "marketing")):toBeErr("NOT_MANAGER")
			-- b compra más del 50 %
			Ownership.transfer(g:companyOf(a).cap, "1", "2", 2000) -- b: 60 %
			t:expect(g.ops:buyUpgrade(b, "1:1", "marketing")):toBeOk()
			t:expect(g:cash(b) < 1000):toBe(true)
			-- y el fundador deja de poder gestionar
			a.data.cash = 1000
			t:expect(g.ops:buyUpgrade(a, "1:1", "marketing")):toBeErr("NOT_MANAGER")
		end)

		t:test(
			"gestionar una empresa ajena marca como modificado el perfil del FUNDADOR (donde vive el documento)",
			function()
				local g = newGame()
				local a, b = shared(g, 6000)
				b.data.cash = 1000
				a.profile.dirty = false
				b.profile.dirty = false
				t:expect(g.ops:buyUpgrade(b, "1:1", "marketing")):toBeOk()
				t:expect(a.profile.dirty):toBe(true)
				t:expect(b.profile.dirty):toBe(true)
			end
		)

		t:test("el pago ocurre sólo a titulares con participación", function()
			local g = newGame()
			local a = g:addPlayer(1)
			local x = g:addPlayer(2)
			g:run(10)
			t:expect(x.data.cash):toBe(110) -- su propia empresa
			t:expect(a.data.cash):toBe(110)
		end)
	end)

	t:describe("La Bolsa automática (empresas del servidor)", function()
		t:test("existen 3 empresas con 100 % de la Bolsa y ingresos que crecen con el tiempo", function()
			local g = newGame()
			local npc = g.world.npcs["npc:tech"]
			t:expect(npc.cap.holders[Ownership.MARKET]):toBe(10000)
			local i0 = g.world:incomeOf(npc).total
			g.clock:advance(600)
			t:expect(g.world:incomeOf(npc).total > i0):toBe(true)
			g.clock:advance(1e6)
			t:expect(g.world:incomeOf(npc).total <= 90 * 1.5 + 1e-6):toBe(true) -- tope de crecimiento
		end)

		t:test("la Bolsa paga sólo PayoutRatio a sus accionistas; el resto se destruye", function()
			local g = newGame()
			local p = g:addPlayer(1)
			local npc = g.world.npcs["npc:commerce"] -- 40 $/s
			Ownership.transfer(npc.cap, Ownership.MARKET, "1", 2000)
			p.data.cash = 0
			local own = g.world:incomeOf(g:companyOf(p)).total
			g:run(100)
			local fromNpc = p.data.cash - own * 100
			-- 40 $/s × 20 % × 60 % = 4,8 $/s -> ~480 en 100 s
			t:expect(fromNpc):toBeAtLeast(476)
			t:expect(fromNpc):toBeAtMost(484)
		end)

		t:test("la valoración de la Bolsa NO incluye hype (sin arbitraje de ciclo)", function()
			local g = newGame()
			local npc = g.world.npcs["npc:tech"]
			local seen = {}
			for s = 0, 900, 30 do
				g.clock:advance(30)
				seen[#seen + 1] = g.world:valuationOf(npc)
				_ = s
			end
			-- crece suavemente con el tiempo, nunca oscila: es monótona no decreciente
			for i = 2, #seen do
				t:expect(seen[i] >= seen[i - 1]):toBe(true)
			end
		end)
	end)

	t:describe("Patrimonio neto", function()
		t:test("suma Cash + valor de las participaciones", function()
			local g = newGame()
			local a = g:addPlayer(1)
			local b = g:addPlayer(2)
			local c = g:companyOf(a)
			Ownership.transfer(c.cap, "1", "2", 5000)
			local val = g.world:valuationOf(c)
			t:expect(g.world:netWorth(b))
				:toBe(g:cash(b) + g.world:valuationOf(g:companyOf(b)) + math.floor(val / 2))
		end)
	end)

	t:describe("FUZZ del tycoon", function()
		t:test("secuencias aleatorias de acciones nunca dejan Cash negativo, fraccionario ni NaN", function()
			local rng = Random.new(99)
			local g = newGame()
			local players = {}
			for i = 1, 4 do
				players[i] = g:addPlayer(i)
			end
			local upgrades = { "shelves", "marketing", "logistics", "license", "facade" }
			for step = 1, 4000 do
				local p = players[rng:NextInteger(1, #players)]
				local action = rng:NextInteger(1, 6)
				if action == 1 then
					g.ops:buyUpgrade(p, p.id .. ":1", upgrades[rng:NextInteger(1, #upgrades)])
				elseif action == 2 then
					g.ops:levelUp(p, p.id .. ":1")
				elseif action == 3 then
					g.ops:found(p, ({ "commerce", "tech", "industry" })[rng:NextInteger(1, 3)])
				elseif action == 4 then
					-- el cliente malicioso intenta gestionar empresas ajenas
					local other = players[rng:NextInteger(1, #players)]
					g.ops:buyUpgrade(p, other.id .. ":1", "shelves")
				else
					g:run(rng:NextInteger(1, 30))
				end
				for _, s in players do
					local cash = s.data.cash
					if not (cash == cash and cash >= 0 and cash % 1 == 0 and cash <= Balance.MaxCash) then
						error(
							("Cash inválido (%s) del jugador %s en el paso %d"):format(
								tostring(cash),
								s.id,
								step
							)
						)
					end
				end
			end
			t:expect(true):toBe(true)
			local c = g:companyOf(players[1])
			t:expect(Income.compute(c).total >= 1):toBe(true)
		end)
	end)
end
