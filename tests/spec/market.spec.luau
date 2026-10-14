--!nocheck
local Game = require("../harness/Game")
local task = require("@lune/task")

return function(t, load)
	local Balance = load:shared("Config/Balance")
	local Ownership = load:shared("Economy/Ownership")
	local Money = load:shared("Economy/Money")
	local Random = load.Random

	local function newGame()
		return Game.new(load)
	end

	-- Dos jugadores; A es fundadora con una empresa que vale bastante y B tiene dinero.
	local function pair(g)
		local a = g:addPlayer(1, "Fundadora")
		local b = g:addPlayer(2, "Inversor")
		local c = g:companyOf(a)
		c.level = 3
		c.upgrades.shelves = 14 -- empresa decente: la valoración es de varios miles
		a.data.cash = 0
		b.data.cash = 100000
		return a, b, c
	end

	local function fairPrice(g, c, bps)
		return g.world:stakeValue(c, bps)
	end

	local function sumCaps(g)
		for _, s in g.world.sessions do
			for _, comp in s.data.companies do
				local ok, why = Ownership.validate(comp.cap)
				if not ok then
					error("cap inválida en " .. comp.id .. ": " .. tostring(why))
				end
			end
		end
	end

	t:describe("Crear ofertas (validación en servidor)", function()
		t:test("oferta válida: queda pendiente con datos de referencia del servidor", function()
			local g = newGame()
			local a, b, c = pair(g)
			local price = fairPrice(g, c, 3000)
			local r = g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 3000, price = price })
			t:expect(r):toBeOk()
			local o = r.value
			t:expect(o.state):toBe("pending")
			t:expect(o.capRev):toBe(c.cap.rev)
			t:expect(o.refValuation):toBe(g.world:valuationOf(c))
			t:expect(o.expiresMono - o.createdMono):toBe(Balance.OfferExpirySeconds)
			t:expect(b.data.stats.offersMade):toBe(1)
			-- crear una oferta NO mueve nada
			t:expect(b.data.cash):toBe(100000)
			t:expect(c.cap.holders[a.id]):toBe(10000)
		end)

		t:test(
			"participaciones inválidas: 0, negativas, no múltiplos del 1 %, >100 %, NaN, texto",
			function()
				local g = newGame()
				local a, b, c = pair(g)
				for _, bad in { 0, -100, 150, 10100, 0 / 0, math.huge, 33.3, "3000" } do
					local r =
						g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = bad, price = 1000 })
					t:expect(r):toBeErr("INVALID_SHARES")
				end
			end
		)

		t:test("precios inválidos: 0, negativos, fraccionarios, NaN, mayores que el tope", function()
			local g = newGame()
			local a, b, c = pair(g)
			for _, bad in { 0, -5, 10.5, 0 / 0, math.huge, 1e16, "100" } do
				local r =
					g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 1000, price = bad })
				t:expect(r):toBeErr("INVALID_PRICE")
			end
		end)

		t:test("precio fuera de banda (transferencias abusivas): muy bajo y muy alto", function()
			local g = newGame()
			local a, b, c = pair(g)
			local fair = fairPrice(g, c, 3000)
			local low = g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 3000, price = 1 })
			t:expect(low):toBeErr("PRICE_OUT_OF_RANGE")
			t:expect(low.params.min):toBe(math.ceil(fair * Balance.MinPriceRatio))
			local high =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 3000, price = fair * 10 })
			t:expect(high):toBeErr("PRICE_OUT_OF_RANGE")
			-- los extremos de la banda sí valen
			t:expect(g.trade:createOffer(b, {
				companyId = c.id,
				sellerId = a.id,
				bps = 3000,
				price = low.params.min,
			})):toBeOk()
		end)

		t:test(
			"empresa inexistente, vendedor desconectado, auto-trato y participaciones que no tiene",
			function()
				local g = newGame()
				local a, b, c = pair(g)
				local p = { companyId = c.id, sellerId = a.id, bps = 1000, price = fairPrice(g, c, 1000) }
				t
					:expect(
						g.trade:createOffer(
							b,
							{ companyId = "9:9", sellerId = a.id, bps = 1000, price = 500 }
						)
					)
					:toBeErr("COMPANY_NOT_FOUND")
				t:expect(
					g.trade:createOffer(
						b,
						{ companyId = "npc:tech", sellerId = a.id, bps = 1000, price = 500 }
					)
				):toBeErr("COMPANY_NOT_FOUND")
				t
					:expect(
						g.trade:createOffer(b, { companyId = c.id, sellerId = "77", bps = 1000, price = 500 })
					)
					:toBeErr("SELLER_OFFLINE")
				t:expect(g.trade:createOffer(a, p)):toBeErr("SAME_PARTIES")
				-- b no tiene nada que vender
				local other = g:addPlayer(3, "Tercero")
				other.data.cash = 1e6
				t
					:expect(
						g.trade:createOffer(
							other,
							{ companyId = c.id, sellerId = b.id, bps = 1000, price = 500 }
						)
					)
					:toBeErr("INSUFFICIENT_SHARES")
			end
		)

		t:test("sin fondos al ofertar", function()
			local g = newGame()
			local a, b, c = pair(g)
			b.data.cash = 10
			local r = g.trade:createOffer(
				b,
				{ companyId = c.id, sellerId = a.id, bps = 3000, price = fairPrice(g, c, 3000) }
			)
			t:expect(r):toBeErr("INSUFFICIENT_FUNDS")
		end)

		t:test("cuentas nuevas no pueden comerciar (anti-alts), ni con ellas", function()
			local g = newGame()
			local a, b, c = pair(g)
			b.data.stats.playSeconds = 5
			local price = fairPrice(g, c, 1000)
			t:expect(g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 1000, price = price }))
				:toBeErr("TOO_NEW")
			b.data.stats.playSeconds = 10000
			a.data.stats.playSeconds = 5
			t:expect(g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 1000, price = price }))
				:toBeErr("SELLER_TOO_NEW")
		end)

		t:test("regla pública del gestor: no se puede dejar la empresa sin gestor viable", function()
			local g = newGame()
			local a, b, c = pair(g)
			Ownership.transfer(c.cap, a.id, "x", 4000) -- a 60 %
			-- a vende 45 % -> a 15 % sin mayoría para nadie: gestor con < 20 %
			local r = g.trade:createOffer(
				b,
				{ companyId = c.id, sellerId = a.id, bps = 4500, price = fairPrice(g, c, 4500) }
			)
			t:expect(r):toBeErr("MANAGER_STAKE_TOO_LOW")
		end)

		t:test("límites: ofertas duplicadas, demasiadas salientes y vendedor saturado", function()
			local g = newGame()
			local a, b, c = pair(g)
			local price = fairPrice(g, c, 1000)
			t:expect(g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 1000, price = price }))
				:toBeOk()
			t:expect(g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 1000, price = price }))
				:toBeErr("DUPLICATE_OFFER")
			-- vendedor saturado: 8 compradores distintos
			local ok = 1
			for i = 10, 30 do
				local buyer = g:addPlayer(i, "B" .. i)
				buyer.data.cash = 1e6
				local r = g.trade:createOffer(
					buyer,
					{ companyId = c.id, sellerId = a.id, bps = 1000, price = price }
				)
				if r.ok then
					ok += 1
				else
					t:expect(r):toBeErr("SELLER_BUSY")
				end
			end
			t:expect(ok):toBe(Balance.MaxIncomingOffers)
		end)

		t:test("demasiadas ofertas salientes del mismo comprador", function()
			local g = newGame()
			local b = g:addPlayer(2, "Inversor")
			b.data.cash = 1e9
			local made = 0
			for i = 10, 30 do
				local seller = g:addPlayer(i, "V" .. i)
				local c = g:companyOf(seller)
				local r = g.trade:createOffer(b, {
					companyId = c.id,
					sellerId = seller.id,
					bps = 1000,
					price = fairPrice(g, c, 1000),
				})
				if r.ok then
					made += 1
				else
					t:expect(r):toBeErr("TOO_MANY_OFFERS")
				end
			end
			t:expect(made):toBe(Balance.MaxOutgoingOffers)
		end)
	end)

	t:describe("Aceptar ofertas (adquisición atómica)", function()
		t:test("EJEMPLO DEL ENUNCIADO: 30 % de una empresa por su valor justo", function()
			local g = newGame()
			local a, b, c = pair(g)
			local price = fairPrice(g, c, 3000)
			local offer =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 3000, price = price }).value
			local cashB, cashA = b.data.cash, a.data.cash
			local r = g.trade:acceptOffer(a, offer.id, price >= Balance.BigDealConfirmCash)
			t:expect(r):toBeOk()
			local tax = Money.mulBps(price, Balance.SaleTaxBps)
			t:expect(r.value.tax):toBe(tax)
			t:expect(b.data.cash):toBe(cashB - price)
			t:expect(a.data.cash):toBe(cashA + price - tax)
			t:expect(c.cap.holders[a.id]):toBe(7000)
			t:expect(c.cap.holders[b.id]):toBe(3000)
			t:expect(Ownership.validate(c.cap)):toBe(true)
			t:expect(offer.state):toBe("accepted")
			-- espejo del inversor, historial, estadísticas y registro público
			t:expect(b.data.holdings[c.id].bps):toBe(3000)
			t:expect(b.data.holdings[c.id].paid):toBe(price)
			t:expect(c.history[#c.history].kind):toBe("trade")
			t:expect(a.data.stats.dealsClosed):toBe(1)
			t:expect(#g.offers:recentDeals(10)):toBe(1)
			-- todos los perfiles implicados quedan marcados para guardar
			t:expect(a.profile.dirty and b.profile.dirty):toBe(true)
			t:expect(r.value.controlChanged):toBe(false)
		end)

		t:test("el vendedor recibe el precio menos el impuesto, que se destruye", function()
			local g = newGame()
			local a, b, c = pair(g)
			local price = fairPrice(g, c, 2000)
			local before = a.data.cash + b.data.cash
			local offer =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 2000, price = price }).value
			local r = g.trade:acceptOffer(a, offer.id, true)
			t:expect(r):toBeOk()
			t:expect(before - (a.data.cash + b.data.cash)):toBe(r.value.tax)
			t:expect(r.value.tax):toBeGreaterThan(0)
		end)

		t:test("una oferta no puede ejecutarse dos veces (idempotencia)", function()
			local g = newGame()
			local a, b, c = pair(g)
			local price = fairPrice(g, c, 3000)
			local offer =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 3000, price = price }).value
			t:expect(g.trade:acceptOffer(a, offer.id, true)):toBeOk()
			local cashB = b.data.cash
			t:expect(g.trade:acceptOffer(a, offer.id, true)):toBeErr("OFFER_NOT_PENDING")
			t:expect(b.data.cash):toBe(cashB)
			t:expect(c.cap.holders[b.id]):toBe(3000)
		end)

		t:test("sólo el vendedor puede aceptar; el comprador no puede aceptar su propia oferta", function()
			local g = newGame()
			local a, b, c = pair(g)
			local mallory = g:addPlayer(3, "Mallory")
			local price = fairPrice(g, c, 3000)
			local offer =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 3000, price = price }).value
			t:expect(g.trade:acceptOffer(b, offer.id, true)):toBeErr("NOT_YOUR_OFFER")
			t:expect(g.trade:acceptOffer(mallory, offer.id, true)):toBeErr("NOT_YOUR_OFFER")
			t:expect(g.trade:rejectOffer(b, offer.id)):toBeErr("NOT_YOUR_OFFER")
			t:expect(g.trade:cancelOffer(a, offer.id)):toBeErr("NOT_YOUR_OFFER")
			t:expect(g.trade:acceptOffer(a, "o999", true)):toBeErr("OFFER_NOT_FOUND")
			t:expect(offer.state):toBe("pending")
			t:expect(c.cap.holders[a.id]):toBe(10000)
		end)

		t:test("rechazar y cancelar cierran la oferta sin mover nada", function()
			local g = newGame()
			local a, b, c = pair(g)
			local price = fairPrice(g, c, 1000)
			local o1 =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 1000, price = price }).value
			t:expect(g.trade:rejectOffer(a, o1.id)):toBeOk()
			t:expect(o1.state):toBe("rejected")
			t:expect(g.trade:acceptOffer(a, o1.id, true)):toBeErr("OFFER_NOT_PENDING")
			local o2 =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 1000, price = price }).value
			t:expect(g.trade:cancelOffer(b, o2.id)):toBeOk()
			t:expect(g.trade:acceptOffer(a, o2.id, true)):toBeErr("OFFER_NOT_PENDING")
			t:expect(b.data.cash):toBe(100000)
			t:expect(c.cap.holders[a.id]):toBe(10000)
		end)

		t:test("ofertas caducadas no se aceptan", function()
			local g = newGame()
			local a, b, c = pair(g)
			local price = fairPrice(g, c, 3000)
			local offer =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 3000, price = price }).value
			g.clock:advance(Balance.OfferExpirySeconds + 1)
			t:expect(g.trade:acceptOffer(a, offer.id, true)):toBeErr("OFFER_EXPIRED")
			t:expect(offer.state):toBe("expired")
			t:expect(b.data.cash):toBe(100000)
			t:expect(c.cap.holders[b.id]):toBeNil()
		end)

		t:test("sweep caduca las vencidas y las devuelve para avisar", function()
			local g = newGame()
			local a, b, c = pair(g)
			g.trade:createOffer(
				b,
				{ companyId = c.id, sellerId = a.id, bps = 1000, price = fairPrice(g, c, 1000) }
			)
			t:expect(#g.trade:sweep()):toBe(0)
			g.clock:advance(Balance.OfferExpirySeconds + 1)
			local expired = g.trade:sweep()
			t:expect(#expired):toBe(1)
			t:expect(expired[1].state):toBe("expired")
			t:expect(#g.trade:sweep()):toBe(0)
		end)

		t:test("sin fondos al aceptar: no se mueve nada y la oferta sigue viva", function()
			local g = newGame()
			local a, b, c = pair(g)
			local price = fairPrice(g, c, 3000)
			local offer =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 3000, price = price }).value
			b.data.cash = price - 1 -- el comprador gastó el dinero mientras tanto
			local r = g.trade:acceptOffer(a, offer.id, true)
			t:expect(r):toBeErr("INSUFFICIENT_FUNDS")
			t:expect(r.params.missing):toBe(1)
			t:expect(offer.state):toBe("pending")
			t:expect(c.cap.holders[a.id]):toBe(10000)
			b.data.cash = price
			t:expect(g.trade:acceptOffer(a, offer.id, true)):toBeOk()
		end)

		t:test("DATOS OBSOLETOS: otra operación cambió la propiedad -> la oferta ya no vale", function()
			local g = newGame()
			local a, b, c = pair(g)
			local d = g:addPlayer(3, "Tercero")
			d.data.cash = 1e6
			local price = fairPrice(g, c, 3000)
			local o1 =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 3000, price = price }).value
			local o2 =
				g.trade:createOffer(d, { companyId = c.id, sellerId = a.id, bps = 3000, price = price }).value
			t:expect(g.trade:acceptOffer(a, o1.id, true)):toBeOk()
			-- la segunda oferta fue anulada al cambiar la estructura
			t:expect(o2.state):toBe("cancelled")
			t:expect(g.trade:acceptOffer(a, o2.id, true)):toBeErr("OFFER_NOT_PENDING")
			t:expect(c.cap.holders[d.id]):toBeNil()
			t:expect(d.data.cash):toBe(1e6)
		end)

		t:test(
			"DATOS OBSOLETOS (2ª línea de defensa): la estructura cambió por una vía ajena al libro de ofertas",
			function()
				local g = newGame()
				local a, b, c = pair(g)
				local price = fairPrice(g, c, 3000)
				local offer = g.trade:createOffer(
					b,
					{ companyId = c.id, sellerId = a.id, bps = 3000, price = price }
				).value
				-- a todavía tendría participaciones de sobra, pero la estructura ya no es la que se ofertó
				Ownership.transfer(c.cap, a.id, "otro", 1000)
				local r = g.trade:acceptOffer(a, offer.id, true)
				t:expect(r):toBeErr("STALE_OFFER")
				t:expect(offer.state):toBe("failed")
				t:expect(c.cap.holders[b.id]):toBeNil()
				t:expect(b.data.cash):toBe(100000)
			end
		)

		t:test("DATOS OBSOLETOS: la valoración se movió más de un 25 % desde la oferta", function()
			local g = newGame()
			local a, b, c = pair(g)
			local price = fairPrice(g, c, 3000)
			local offer =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 3000, price = price }).value
			c.upgrades.marketing = 8 -- ingresos x3,7 : la empresa vale mucho más
			local r = g.trade:acceptOffer(a, offer.id, true)
			t:expect(r):toBeErr("STALE_OFFER")
			t:expect(offer.state):toBe("failed")
			t:expect(c.cap.holders[b.id]):toBeNil()
			t:expect(b.data.cash):toBe(100000)
		end)

		t:test("el vendedor ya no tiene las participaciones (las vendió por fuera del libro)", function()
			local g = newGame()
			local a, b, c = pair(g)
			local price = fairPrice(g, c, 6000)
			local offer =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 6000, price = price }).value
			Ownership.transfer(c.cap, a.id, "z", 5000) -- cambio no pasa por el libro (p. ej. Bolsa)
			local r = g.trade:acceptOffer(a, offer.id, true)
			t:expect(r.ok):toBe(false)
			t:expect(c.cap.holders[b.id]):toBeNil()
		end)

		t:test("una de las partes se fue: no se ejecuta", function()
			local g = newGame()
			local a, b, c = pair(g)
			local price = fairPrice(g, c, 3000)
			local offer =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 3000, price = price }).value
			local removed = g:removePlayer(b)
			local cancelled = g.trade:onPlayerLeft(b.id, removed)
			t:expect(#cancelled):toBe(1)
			t:expect(offer.state):toBe("cancelled")
			t:expect(g.trade:acceptOffer(a, offer.id, true)):toBeErr("OFFER_NOT_PENDING")
		end)

		t:test("PARTY_LEFT si el comprador se va sin que se limpien sus ofertas", function()
			local g = newGame()
			local a, b, c = pair(g)
			local price = fairPrice(g, c, 3000)
			local offer =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 3000, price = price }).value
			g:removePlayer(b)
			t:expect(g.trade:acceptOffer(a, offer.id, true)):toBeErr("PARTY_LEFT")
			t:expect(offer.state):toBe("failed")
		end)

		t:test("si se va el fundador sus empresas desaparecen del mundo y sus ofertas se anulan", function()
			local g = newGame()
			local a, b, c = pair(g)
			local price = fairPrice(g, c, 3000)
			local offer =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 3000, price = price }).value
			local removed = g:removePlayer(a)
			t:expect(removed):toContain(c.id)
			g.trade:onPlayerLeft(a.id, removed)
			t:expect(offer.state):toBe("cancelled")
			t:expect(g.world.companies[c.id]):toBeNil()
		end)
	end)

	t:describe("Confirmaciones y control", function()
		t:test("operaciones grandes exigen confirmación explícita (y no mueven nada sin ella)", function()
			local g = newGame()
			local a, b, c = pair(g)
			c.upgrades.marketing = 8
			c.level = 4
			local price = fairPrice(g, c, 2000)
			t:expect(price >= Balance.BigDealConfirmCash):toBe(true)
			local offer =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 2000, price = price }).value
			local r = g.trade:acceptOffer(a, offer.id, false)
			t:expect(r):toBeErr("CONFIRMATION_REQUIRED")
			t:expect(offer.state):toBe("pending")
			t:expect(c.cap.holders[b.id]):toBeNil()
			t:expect(g.trade:acceptOffer(a, offer.id, nil)):toBeErr("CONFIRMATION_REQUIRED")
			t:expect(g.trade:acceptOffer(a, offer.id, "yes")):toBeErr("CONFIRMATION_REQUIRED") -- sólo `true` vale
			t:expect(g.trade:acceptOffer(a, offer.id, true)):toBeOk()
		end)

		t:test("cruzar el 50 % cambia el gestor, exige confirmación y lo informa", function()
			local g = newGame()
			local a, b, c = pair(g)
			c.upgrades = {}
			c.level = 1 -- empresa pequeña: precio bajo, aun así hay confirmación por control
			local price = fairPrice(g, c, 6000)
			t:expect(price < Balance.BigDealConfirmCash):toBe(true)
			local offer =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 6000, price = price }).value
			t:expect(g.trade:acceptOffer(a, offer.id, false)):toBeErr("CONFIRMATION_REQUIRED")
			local r = g.trade:acceptOffer(a, offer.id, true)
			t:expect(r):toBeOk()
			t:expect(r.value.controlChanged):toBe(true)
			t:expect(r.value.newManager):toBe(b.id)
			-- el nuevo gestor puede invertir; el fundador ya no
			b.data.cash = 1000
			t:expect(g.ops:buyUpgrade(b, c.id, "shelves")):toBeOk()
			a.data.cash = 1000
			t:expect(g.ops:buyUpgrade(a, c.id, "shelves")):toBeErr("NOT_MANAGER")
			-- el fundador sigue siendo propietario original con el 40 %
			t:expect(c.founderId):toBe(a.id)
			t:expect(c.cap.holders[a.id]):toBe(4000)
		end)

		t:test("exactamente 50 % no cambia el gestor", function()
			local g = newGame()
			local a, b, c = pair(g)
			c.upgrades = {}
			c.level = 1
			local price = fairPrice(g, c, 5000)
			local offer =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 5000, price = price }).value
			local r = g.trade:acceptOffer(a, offer.id, true)
			t:expect(r):toBeOk()
			t:expect(r.value.controlChanged):toBe(false)
			t:expect(Ownership.manager(c.cap, c.founderId)):toBe(a.id)
		end)
	end)

	t:describe("Atomicidad: un fallo en cualquier etapa lo deja todo como estaba", function()
		for _, stage in { "afterDebit", "afterCredit", "afterTransfer", "afterHoldings", "afterLog" } do
			t:test("fallo inyectado en " .. stage, function()
				local g = newGame()
				local a, b, c = pair(g)
				local price = fairPrice(g, c, 3000)
				local offer = g.trade:createOffer(
					b,
					{ companyId = c.id, sellerId = a.id, bps = 3000, price = price }
				).value

				local before = {
					cashA = a.data.cash,
					cashB = b.data.cash,
					statsA = table.clone(a.data.stats),
					statsB = table.clone(b.data.stats),
					holders = table.clone(c.cap.holders),
					rev = c.cap.rev,
					history = #c.history,
					holdingsB = b.data.holdings[c.id],
					dealsLogged = #g.offers:recentDeals(100),
				}

				g.fault = function(s)
					if s == stage then
						error("fallo simulado en " .. s)
					end
				end
				local r = g.trade:acceptOffer(a, offer.id, true)
				g.fault = nil

				t:expect(r.ok):toBe(false)
				t:expect(a.data.cash):toBe(before.cashA)
				t:expect(b.data.cash):toBe(before.cashB)
				t:expect(a.data.stats):toEqual(before.statsA)
				t:expect(b.data.stats):toEqual(before.statsB)
				t:expect(c.cap.holders):toEqual(before.holders)
				t:expect(c.cap.rev):toBe(before.rev)
				t:expect(#c.history):toBe(before.history)
				t:expect(b.data.holdings[c.id]):toBe(before.holdingsB)
				t:expect(#g.offers:recentDeals(100)):toBe(before.dealsLogged)
				t:expect(offer.state):toBe("failed") -- una oferta fallida no puede reintentarse
				t:expect(Ownership.validate(c.cap)):toBe(true)

				-- y el sistema sigue sano: una oferta nueva funciona
				local retry =
					g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 3000, price = price })
				t:expect(retry):toBeOk()
				g.clock:advance(Balance.PairTradeCooldownSeconds + 1)
				t:expect(g.trade:acceptOffer(a, retry.value.id, true)):toBeOk()
			end)
		end
	end)

	t:describe("Concurrencia", function()
		t:test("dos compradores, un solo bloque de participaciones: sólo uno lo consigue", function()
			local g = newGame()
			local a, b, c = pair(g)
			local d = g:addPlayer(3, "Tercero")
			d.data.cash = 1e6
			local price = fairPrice(g, c, 8000)
			local o1 =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 8000, price = price }).value
			local o2 =
				g.trade:createOffer(d, { companyId = c.id, sellerId = a.id, bps = 8000, price = price }).value
			local results = {}
			local pending = 2
			for i, o in { o1, o2 } do
				task.spawn(function()
					results[i] = g.trade:acceptOffer(a, o.id, true)
					pending -= 1
				end)
			end
			while pending > 0 do
				task.wait()
			end
			local oks = 0
			for _, r in results do
				if r.ok then
					oks += 1
				end
			end
			t:expect(oks):toBe(1)
			local holders = 0
			for id in c.cap.holders do
				if id ~= a.id then
					holders += 1
				end
			end
			t:expect(holders):toBe(1)
			t:expect(Ownership.validate(c.cap)):toBe(true)
		end)

		t:test("un comprador con dinero para una sola compra: la segunda falla sin dejar rastro", function()
			local g = newGame()
			local a, b, c1 = pair(g)
			local x = g:addPlayer(3, "Otra")
			local c2 = g:companyOf(x)
			local p1 = fairPrice(g, c1, 3000)
			local p2 = fairPrice(g, c2, 3000)
			b.data.cash = math.max(p1, p2) + 1
			local o1 =
				g.trade:createOffer(b, { companyId = c1.id, sellerId = a.id, bps = 3000, price = p1 }).value
			local o2 =
				g.trade:createOffer(b, { companyId = c2.id, sellerId = x.id, bps = 3000, price = p2 }).value
			local r1 = g.trade:acceptOffer(a, o1.id, true)
			local r2 = g.trade:acceptOffer(x, o2.id, true)
			t:expect(r1.ok):toBe(true)
			if p1 + p2 > b.data.cash + p1 then
				t:expect(r2.ok):toBe(false)
				t:expect(c2.cap.holders[b.id]):toBeNil()
			end
			t:expect(b.data.cash >= 0):toBe(true)
		end)
	end)

	t:describe("Conservación del dinero (FUZZ)", function()
		t:test(
			"tras miles de operaciones aleatorias: Cash + impuestos destruidos == Cash inicial, y todas las caps suman 100 %",
			function()
				local rng = Random.new(31337)
				local g = newGame()
				local players = {}
				for i = 1, 6 do
					players[i] = g:addPlayer(i, "P" .. i)
					players[i].data.cash = rng:NextInteger(50_000, 500_000)
					local c = g:companyOf(players[i])
					c.level = rng:NextInteger(1, 4)
					c.upgrades.shelves = rng:NextInteger(0, 14)
				end
				local initial = g:totalCash()
				local burned = 0
				local deals, attempts = 0, 0
				local lots = { 1000, 2000, 2500, 3000, 5000, 6000 }

				for _ = 1, 3000 do
					g.clock:advance(rng:NextInteger(0, 20))
					g.trade:sweep()
					local buyer = players[rng:NextInteger(1, #players)]
					local seller = players[rng:NextInteger(1, #players)]
					local company = g:companyOf(players[rng:NextInteger(1, #players)])
					local bps = lots[rng:NextInteger(1, #lots)]
					local min, max = g.trade:priceBand(company, bps)
					local price = rng:NextInteger(min, math.max(min, max))
					if rng:NextInteger(1, 10) == 1 then
						price = rng:NextInteger(-5, 3) -- precios basura de vez en cuando
					end
					attempts += 1
					local offer = g.trade:createOffer(buyer, {
						companyId = company.id,
						sellerId = seller.id,
						bps = bps,
						price = price,
					})
					if offer.ok then
						local pick = rng:NextInteger(1, 4)
						if pick <= 2 then
							local r = g.trade:acceptOffer(seller, offer.value.id, true)
							if r.ok then
								deals += 1
								burned += r.value.tax
							end
						elseif pick == 3 then
							g.trade:rejectOffer(seller, offer.value.id)
						else
							g.trade:cancelOffer(buyer, offer.value.id)
						end
					end

					-- invariantes tras CADA operación
					sumCaps(g)
					local total = g:totalCash()
					if total + burned ~= initial then
						error(("dinero no conservado: %d + %d != %d"):format(total, burned, initial))
					end
					for _, p in players do
						if p.data.cash < 0 or p.data.cash % 1 ~= 0 then
							error("cash inválido: " .. tostring(p.data.cash))
						end
					end
				end
				t:expect(deals):toBeGreaterThan(30)
				t:expect(g:totalCash() + burned):toBe(initial)
			end
		)

		t:test(
			"operaciones circulares (A->B->A al mismo precio) siempre pierden dinero por el impuesto",
			function()
				local g = newGame()
				local a, b, c = pair(g)
				local price = fairPrice(g, c, 4000)
				local before = a.data.cash + b.data.cash
				local o1 = g.trade:createOffer(
					b,
					{ companyId = c.id, sellerId = a.id, bps = 4000, price = price }
				).value
				g.trade:acceptOffer(a, o1.id, true)
				g.clock:advance(Balance.PairTradeCooldownSeconds + 1)
				a.data.cash += 1000 -- la fundadora necesita efectivo para recomprar (ya perdió el impuesto)
				before += 1000
				-- b vende de vuelta a a (a es el comprador ahora)
				local o2 =
					g.trade:createOffer(a, { companyId = c.id, sellerId = b.id, bps = 4000, price = price })
				t:expect(o2):toBeOk()
				t:expect(g.trade:acceptOffer(b, o2.value.id, true)):toBeOk()
				local after = a.data.cash + b.data.cash
				t:expect(after < before):toBe(true)
				t:expect(c.cap.holders[a.id]):toBe(10000)
			end
		)

		t:test("cooldown entre las mismas dos personas", function()
			local g = newGame()
			local a, b, c = pair(g)
			local price = fairPrice(g, c, 1000)
			local o1 =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 1000, price = price }).value
			g.trade:acceptOffer(a, o1.id, true)
			local again =
				g.trade:createOffer(b, { companyId = c.id, sellerId = a.id, bps = 1000, price = price })
			t:expect(again):toBeErr("PAIR_COOLDOWN")
		end)
	end)

	t:describe("Bolsa automática", function()
		local function market()
			local g = newGame()
			local a = g:addPlayer(1, "Ana")
			a.data.cash = 1e7
			return g, a, g.world.npcs["npc:commerce"]
		end

		t:test(
			"comprar: precio de venta con diferencial, la Bolsa cede participación y se anota el espejo",
			function()
				local g, a, npc = market()
				local value = g.world:stakeValue(npc, 1000)
				local r = g.trade:buyFromMarket(a, npc.id, 1000, true)
				t:expect(r):toBeOk()
				t:expect(r.value.price):toBe(math.ceil(value * 1.05))
				t:expect(a.data.cash):toBe(1e7 - r.value.price)
				t:expect(npc.cap.holders[a.id]):toBe(1000)
				t:expect(npc.cap.holders[Ownership.MARKET]):toBe(9000)
				t:expect(Ownership.validate(npc.cap)):toBe(true)
				t:expect(a.data.holdings[npc.id].bps):toBe(1000)
			end
		)

		t:test(
			"vender: precio de compra con diferencial; comprar y vender enseguida SIEMPRE pierde",
			function()
				local g, a, npc = market()
				local cash = a.data.cash
				local buy = g.trade:buyFromMarket(a, npc.id, 2000, true)
				local sell = g.trade:sellToMarket(a, npc.id, 2000)
				t:expect(sell):toBeOk()
				t:expect(sell.value.price < buy.value.price):toBe(true)
				t:expect(a.data.cash < cash):toBe(true)
				t:expect(npc.cap.holders[a.id]):toBeNil()
				t:expect(npc.cap.holders[Ownership.MARKET]):toBe(10000)
				t:expect(a.data.holdings[npc.id]):toBeNil()
				-- pérdida mínima ~ 10 % (5 % + 5 %)
				t:expect((cash - a.data.cash) / buy.value.price >= 0.09):toBe(true)
			end
		)

		t:test("límite por jugador (20 %) y cupo total del servidor (49 %)", function()
			local g, a, npc = market()
			t:expect(g.trade:buyFromMarket(a, npc.id, 2000, true)):toBeOk()
			t:expect(g.trade:buyFromMarket(a, npc.id, 100, true)):toBeErr("PLAYER_CAP")
			local others = {}
			for i = 2, 5 do
				others[i] = g:addPlayer(i, "O" .. i)
				others[i].data.cash = 1e7
			end
			t:expect(g.trade:buyFromMarket(others[2], npc.id, 2000, true)):toBeOk() -- 40 %
			t:expect(g.trade:buyFromMarket(others[3], npc.id, 900, true)):toBeOk() -- 49 %
			local r = g.trade:buyFromMarket(others[4], npc.id, 100, true)
			t:expect(r):toBeErr("MARKET_SOLD_OUT")
			t:expect(r.params.available):toBe(0)
			t:expect(npc.cap.holders[Ownership.MARKET]):toBe(5100)
			-- nunca se supera el 49 % en manos de jugadores => nadie controla una empresa de la Bolsa
			t:expect(Ownership.controller(npc.cap)):toBe(Ownership.MARKET)
		end)

		t:test("lotes inválidos, sin fondos y sin participaciones", function()
			local g, a, npc = market()
			t:expect(g.trade:buyFromMarket(a, npc.id, 150, true)):toBeErr("INVALID_SHARES")
			t:expect(g.trade:buyFromMarket(a, npc.id, 0, true)):toBeErr("INVALID_SHARES")
			t:expect(g.trade:buyFromMarket(a, "npc:nope", 1000, true)):toBeErr("COMPANY_NOT_FOUND")
			t:expect(g.trade:sellToMarket(a, npc.id, 1000)):toBeErr("INSUFFICIENT_SHARES")
			a.data.cash = 10
			t:expect(g.trade:buyFromMarket(a, npc.id, 1000, true)):toBeErr("INSUFFICIENT_FUNDS")
			t:expect(a.data.cash):toBe(10)
		end)

		t:test("compras caras de la Bolsa también exigen confirmación", function()
			local g, a = market()
			local npc = g.world.npcs["npc:tech"] -- 20 % de Quantum Labs supera el umbral
			local r = g.trade:buyFromMarket(a, npc.id, 2000, false)
			t:expect(r):toBeErr("CONFIRMATION_REQUIRED")
			t:expect(a.data.cash):toBe(1e7)
			t:expect(npc.cap.holders[a.id]):toBeNil()
		end)

		t:test("fallo inyectado al comprar a la Bolsa: se revierte todo", function()
			local g, a, npc = market()
			for _, stage in { "afterDebit", "afterTransfer", "afterHoldings" } do
				g.fault = function(s)
					if s == stage then
						error("boom")
					end
				end
				local r = g.trade:buyFromMarket(a, npc.id, 1000, true)
				g.fault = nil
				t:expect(r.ok):toBe(false)
				t:expect(a.data.cash):toBe(1e7)
				t:expect(npc.cap.holders[a.id]):toBeNil()
				t:expect(npc.cap.holders[Ownership.MARKET]):toBe(10000)
				t:expect(a.data.holdings[npc.id]):toBeNil()
			end
		end)

		t:test("al salir el jugador devuelve su participación a la Bolsa; al volver la recupera", function()
			local g, a, npc = market()
			g.trade:buyFromMarket(a, npc.id, 1500, true)
			g.trade:releaseMarketStakes(a)
			t:expect(npc.cap.holders[a.id]):toBeNil()
			t:expect(npc.cap.holders[Ownership.MARKET]):toBe(10000)
			t:expect(a.data.holdings[npc.id].bps):toBe(1500) -- el espejo se conserva en su perfil
			local liq = g.trade:restoreMarketStakes(a)
			t:expect(#liq):toBe(0)
			t:expect(npc.cap.holders[a.id]):toBe(1500)
			t:expect(Ownership.validate(npc.cap)):toBe(true)
			-- idempotente
			g.trade:restoreMarketStakes(a)
			t:expect(npc.cap.holders[a.id]):toBe(1500)
		end)

		t:test(
			"si el cupo del servidor está lleno al volver, el exceso se liquida al precio de compra",
			function()
				local g, a, npc = market()
				g.trade:buyFromMarket(a, npc.id, 2000, true)
				g.trade:releaseMarketStakes(a)
				-- mientras tanto otros llenan el cupo
				local fillers = {}
				for i = 2, 4 do
					fillers[i] = g:addPlayer(i, "F" .. i)
					fillers[i].data.cash = 1e7
				end
				g.trade:buyFromMarket(fillers[2], npc.id, 2000, true)
				g.trade:buyFromMarket(fillers[3], npc.id, 2000, true)
				g.trade:buyFromMarket(fillers[4], npc.id, 900, true) -- 49 %
				local cash = a.data.cash
				local liq = g.trade:restoreMarketStakes(a)
				t:expect(#liq):toBe(1)
				t:expect(liq[1].bps):toBe(2000)
				t:expect(a.data.cash):toBe(cash + liq[1].cash)
				t:expect(npc.cap.holders[a.id]):toBeNil()
				t:expect(a.data.holdings[npc.id]):toBeNil()
				t:expect(Ownership.validate(npc.cap)):toBe(true)
			end
		)
	end)
end
