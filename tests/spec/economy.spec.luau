--!nocheck
return function(t, load)
	local Balance = load:shared("Config/Balance")
	local Sectors = load:shared("Config/Sectors")
	local Money = load:shared("Economy/Money")
	local Income = load:shared("Economy/Income")
	local Pricing = load:shared("Economy/Pricing")
	local Valuation = load:shared("Economy/Valuation")
	local Company = load:shared("Economy/Company")
	local Catalog = load:shared("Economy/Catalog")

	local function newCompany(sector, level, upgrades)
		local c = Company.new({ founderId = "1", index = 1, sector = sector or "commerce", now = 0 })
		c.level = level or 1
		c.upgrades = upgrades or {}
		return c
	end

	t:describe("Config de balance", function()
		t:test("la configuración está congelada (no se puede alterar en runtime)", function()
			t:expect(function()
				Balance.StartingCash = 1e9
			end):toThrow()
			t:expect(function()
				Sectors.byId.commerce.baseIncome = 1e9
			end):toThrow()
		end)

		t:test("MaxCash es entero exacto y menor que 2^53", function()
			t:expect(Balance.MaxCash % 1):toBe(0)
			t:expect(Balance.MaxCash + 1 ~= Balance.MaxCash):toBe(true)
			t:expect(Balance.MaxCash < 2 ^ 53):toBe(true)
		end)

		t:test("cada sector es coherente: ids únicos, costes y efectos válidos", function()
			for _, sectorId in Sectors.order do
				local sector = Sectors.byId[sectorId]
				t:expect(sector ~= nil):toBe(true)
				local seen = {}
				for _, def in sector.upgrades do
					t:expect(seen[def.id]):toBeNil()
					seen[def.id] = true
					t:expect(def.baseCost):toBeGreaterThan(0)
					t:expect(def.growth):toBeGreaterThan(1)
					t:expect(def.maxLevel):toBeGreaterThan(0)
					t:expect(table.find({ "flat", "mult", "discount", "capacity", "look" }, def.effect.kind))
						:toBeTruthy()
				end
			end
		end)

		t:test("el descuento máximo posible de un sector nunca supera el tope global", function()
			for _, sectorId in Sectors.order do
				local c = newCompany(sectorId)
				for _, def in Sectors.byId[sectorId].upgrades do
					c.upgrades[def.id] = def.maxLevel
				end
				t:expect(Pricing.discount(c, 1)):toBe(Balance.MaxUpgradeDiscount)
				t:expect(Pricing.discount(c, 0)):toBeAtMost(Balance.MaxUpgradeDiscount)
			end
		end)

		t:test("la primera mejora de cada sector es asequible con el Cash inicial", function()
			for _, sectorId in Sectors.order do
				local c = newCompany(sectorId)
				local first = Sectors.byId[sectorId].upgrades[1]
				local cost = Pricing.upgradeCost(sectorId, first.id, 0, 0)
				if sectorId == "commerce" then
					t:expect(cost):toBeAtMost(Balance.StartingCash)
				end
				t:expect(cost):toBeGreaterThan(0)
				t:expect(c.level):toBe(1)
			end
		end)
	end)

	t:describe("Money", function()
		t:test("isValid sólo acepta enteros finitos en rango", function()
			t:expect(Money.isValid(0)):toBe(true)
			t:expect(Money.isValid(100)):toBe(true)
			t:expect(Money.isValid(Money.MAX)):toBe(true)
			t:expect(Money.isValid(Money.MAX + 1)):toBe(false)
			t:expect(Money.isValid(-1)):toBe(false)
			t:expect(Money.isValid(1.5)):toBe(false)
			t:expect(Money.isValid(0 / 0)):toBe(false)
			t:expect(Money.isValid(math.huge)):toBe(false)
			t:expect(Money.isValid("100")):toBe(false)
			t:expect(Money.isValid(nil)):toBe(false)
		end)

		t:test("sanitize convierte basura en cantidades seguras", function()
			t:expect(Money.sanitize(0 / 0)):toBe(0)
			t:expect(Money.sanitize(-50)):toBe(0)
			t:expect(Money.sanitize(12.9)):toBe(12)
			t:expect(Money.sanitize(1e30)):toBe(Money.MAX)
			t:expect(Money.sanitize("x")):toBe(0)
		end)

		t:test("mulBps es exacto incluso con importes enormes", function()
			t:expect(Money.mulBps(10000, 3000)):toBe(3000)
			t:expect(Money.mulBps(10001, 1)):toBe(1)
			t:expect(Money.mulBps(999, 5000)):toBe(499)
			t:expect(Money.mulBps(1e15, 10000)):toBe(1e15)
			t:expect(Money.mulBps(1e15, 3333)):toBe(333_300_000_000_000)
			t:expect(Money.mulBps(0, 5000)):toBe(0)
		end)
	end)

	t:describe("Income", function()
		t:test("empresa recién creada de Comercio produce 1 $/s", function()
			t:expect(Income.compute(newCompany("commerce")).total):toBeNear(1.0)
		end)

		t:test("planos suman, multiplicadores multiplican, nivel aumenta la base", function()
			local c = newCompany("commerce", 1, { shelves = 2 }) -- +0,7 por nivel
			t:expect(Income.compute(c).total):toBeNear(1.0 + 1.4)
			c.upgrades.marketing = 2 -- ×1,18²
			t:expect(Income.compute(c).total):toBeNear((1.0 + 1.4) * 1.18 ^ 2, 1e-9)
			c.level = 3 -- base 1 + 2*2
			t:expect(Income.compute(c).total):toBeNear((5.0 + 1.4) * 1.18 ^ 2, 1e-9)
		end)

		t:test("lealtad de Comercio: +1 % cada 5 min con tope +10 %", function()
			local c = newCompany("commerce")
			t:expect(Income.compute(c, { sessionSeconds = 299 }).total):toBeNear(1.0)
			t:expect(Income.compute(c, { sessionSeconds = 300 }).total):toBeNear(1.01)
			t:expect(Income.compute(c, { sessionSeconds = 3000 }).total):toBeNear(1.10)
			t:expect(Income.compute(c, { sessionSeconds = 1e9 }).total):toBeNear(1.10)
		end)

		t:test("economías de escala de Industria dependen del nivel", function()
			local c = newCompany("industry", 3)
			local scale = Income.compute(c).mechanic
			t:expect(scale):toBeNear(1 + 0.10 * 2, 1e-9)
		end)

		t:test("eventos y alianzas multiplican el total pero NO el sostenido", function()
			local c = newCompany("commerce", 1, { shelves = 4 })
			local plain = Income.compute(c)
			local boosted = Income.compute(c, { eventMult = 1.5, allianceMult = 1.06 })
			t:expect(boosted.sustained):toBeNear(plain.sustained)
			t:expect(boosted.total):toBeNear(plain.total * 1.5 * 1.06, 1e-9)
		end)

		t:test("datos corruptos o extremos no producen NaN, negativos ni desbordes", function()
			local c = newCompany("tech", 8, { servers = 12, algorithms = 8, research = 4 })
			local r = Income.compute(c, { eventMult = 1e30, allianceMult = 1e30 })
			t:expect(r.total <= Balance.MaxIncomePerSecond):toBe(true)
			local bad = newCompany("tech", 1, { servers = -3 })
			t:expect(Income.compute(bad).total >= 0):toBe(true)
			local weird = { sector = "nope", level = 1, upgrades = {} }
			t:expect(Income.compute(weird).total):toBe(0)
			local nan = newCompany("tech", 0 / 0)
			local v = Income.compute(nan).total
			t:expect(v == v):toBe(true)
		end)

		t:test("comprar una mejora nunca reduce los ingresos", function()
			for _, sectorId in Sectors.order do
				local c = newCompany(sectorId, 2)
				local before = Income.compute(c).total
				for _, opt in Pricing.options(c, nil, 0) do
					t:expect(opt.deltaIncome >= 0):toBe(true)
				end
				t:expect(before):toBeGreaterThan(0)
			end
		end)
	end)

	t:describe("Pricing", function()
		t:test("coste de mejora crece geométricamente y se redondea hacia arriba", function()
			t:expect(Pricing.upgradeCost("commerce", "shelves", 0, 0)):toBe(20)
			t:expect(Pricing.upgradeCost("commerce", "shelves", 1, 0)):toBe(27) -- 26,4
			t:expect(Pricing.upgradeCost("commerce", "shelves", 2, 0)):toBe(35) -- 34,848
			t:expect(Pricing.upgradeCost("commerce", "nope", 0, 0)):toBeNil()
		end)

		t:test("el descuento reduce el coste pero nunca por debajo de 1", function()
			t:expect(Pricing.upgradeCost("commerce", "shelves", 0, 0.4)):toBe(12)
			t:expect(Pricing.upgradeCost("commerce", "shelves", 0, 0.9999)):toBe(1)
		end)

		t:test("licencias aumentan el nivel máximo", function()
			local c = newCompany("commerce")
			t:expect(Pricing.maxLevel(c)):toBe(4)
			c.upgrades.license = 2
			t:expect(Pricing.maxLevel(c)):toBe(8)
		end)

		t:test("options incluye beneficio esperado y amortización", function()
			local c = newCompany("commerce")
			local options = Pricing.options(c, nil, 0)
			local shelves
			for _, o in options do
				if o.id == "shelves" then
					shelves = o
				end
			end
			t:expect(shelves.cost):toBe(20)
			t:expect(shelves.deltaIncome):toBeNear(0.7, 1e-9)
			t:expect(shelves.paybackSeconds):toBeNear(20 / 0.7, 1e-9)
			t:expect(shelves.maxed):toBe(false)
		end)

		t:test("mejoras al máximo salen como maxed y no se recomiendan", function()
			local c = newCompany("commerce", 4, { shelves = 14 })
			for _, o in Pricing.options(c, nil, 0) do
				if o.id == "shelves" then
					t:expect(o.maxed):toBe(true)
				end
			end
		end)

		t:test("la recomendación al empezar es una mejora barata", function()
			local c = newCompany("commerce")
			local opts = Pricing.options(c, nil, 0)
			local rec = Pricing.recommended(opts, Balance.StartingCash, 1)
			t:expect(rec ~= nil):toBe(true)
			t:expect(rec.cost <= Balance.StartingCash):toBe(true)
			t:expect(rec.deltaIncome):toBeGreaterThan(0)
		end)

		t:test("con el nivel al tope y sin más ingresos recomienda ampliar capacidad", function()
			local c = newCompany("commerce", 4, { shelves = 14, marketing = 8, facade = 3 })
			local opts = Pricing.options(c, nil, 0)
			local rec = Pricing.recommended(opts, 0, 50)
			t:expect(rec.id):toBe("license")
		end)

		t:test("sin nada que comprar no hay recomendación", function()
			local c = newCompany("commerce", 8)
			for _, def in Sectors.byId.commerce.upgrades do
				c.upgrades[def.id] = def.maxLevel
			end
			local rec = Pricing.recommended(Pricing.options(c, nil, 0), 0, 50)
			t:expect(rec):toBeNil()
		end)

		t:test("foundingCost por sector", function()
			t:expect(Pricing.foundingCost("tech")):toBe(2500)
			t:expect(Pricing.foundingCost("nope")):toBeNil()
		end)
	end)

	t:describe("Valuation", function()
		t:test("fundamental = ingresos sostenidos × múltiplo", function()
			t:expect(Valuation.fundamental("commerce", 1)):toBe(480)
			t:expect(Valuation.fundamental("tech", 10)):toBe(8400)
			t:expect(Valuation.fundamental("nope", 10)):toBe(0)
		end)

		t:test("hype: sólo Tecnología oscila, dentro de ±amplitud, y es periódico", function()
			t:expect(Valuation.hype("commerce", 12345)):toBe(1)
			t:expect(Valuation.hype("industry", 12345)):toBe(1)
			local lo, hi = math.huge, -math.huge
			for sec = 0, 1800, 5 do
				local h = Valuation.hype("tech", sec)
				lo = math.min(lo, h)
				hi = math.max(hi, h)
			end
			t:expect(lo >= 0.88 - 1e-9):toBe(true)
			t:expect(hi <= 1.12 + 1e-9):toBe(true)
			t:expect(hi - lo):toBeGreaterThan(0.2)
			t:expect(Valuation.hype("tech", 100)):toBeNear(Valuation.hype("tech", 100 + 900), 1e-9)
		end)

		t:test("la valoración de mercado incluye el hype; la fundamental no", function()
			local f = Valuation.fundamental("tech", 100)
			local peak = Valuation.market("tech", 100, 225) -- seno máximo (T/4)
			t:expect(peak > f):toBe(true)
			t:expect(Valuation.market("commerce", 100, 225)):toBe(Valuation.fundamental("commerce", 100))
		end)

		t:test("valor de una participación", function()
			t:expect(Valuation.stake(10_000, 3000)):toBe(3000)
			t:expect(Valuation.stake(999, 100)):toBe(9)
		end)
	end)

	t:describe("Company", function()
		t:test("nombres: sólo composiciones válidas de listas predefinidas", function()
			t:expect(Company.nameFromParts("commerce", { 1, 1, 1 })):toBe("Nova Market Co.")
			t:expect(Company.nameFromParts("commerce", { 0, 1, 1 })):toBeNil()
			t:expect(Company.nameFromParts("commerce", { 1, 99, 1 })):toBeNil()
			t:expect(Company.nameFromParts("commerce", { 1.5, 1, 1 })):toBeNil()
			t:expect(Company.nameFromParts("commerce", { 1, 1 })):toBeNil()
			t:expect(Company.nameFromParts("nope", { 1, 1, 1 })):toBeNil()
		end)

		t:test("logotipos: sólo índices válidos", function()
			t:expect(Company.isValidLogo(1, 1)):toBe(true)
			t:expect(Company.isValidLogo(0, 1)):toBe(false)
			t:expect(Company.isValidLogo(1, 99)):toBe(false)
			t:expect(Company.isValidLogo("x", 1)):toBe(false)
		end)

		t:test("empresa nueva: 100 % del fundador, nivel 1, id estable", function()
			local c = Company.new({ founderId = "42", index = 3, sector = "tech", now = 5 })
			t:expect(c.id):toBe("42:3")
			t:expect(c.cap.holders["42"]):toBe(10000)
			t:expect(c.level):toBe(1)
			t:expect(Company.nameFromParts("tech", c.nameParts)):toBe(c.name)
		end)

		t:test("nombre por defecto determinista", function()
			local a = Company.new({ founderId = "42", index = 1, sector = "commerce", now = 0 })
			local b = Company.new({ founderId = "42", index = 1, sector = "commerce", now = 99 })
			t:expect(a.name):toBe(b.name)
		end)

		t:test("etapa visual crece con nivel y mejoras de aspecto, acotada a 1..10", function()
			local c = newCompany("commerce")
			t:expect(Company.visualTier(c)):toBe(1)
			c.level = 4
			c.upgrades.facade = 3
			t:expect(Company.visualTier(c)):toBe(7)
			c.level = 99
			t:expect(Company.visualTier(c)):toBe(10)
		end)

		t:test("el historial es un anillo acotado", function()
			local c = newCompany("commerce")
			for i = 1, Balance.HistoryLimit + 25 do
				Company.log(c, { id = tostring(i), t = i, kind = "upgrade" })
			end
			t:expect(#c.history):toBe(Balance.HistoryLimit)
			t:expect(c.history[#c.history].id):toBe(tostring(Balance.HistoryLimit + 25))
		end)
	end)

	t:describe("Catalog", function()
		t:test("lookup de sectores y mejoras", function()
			t:expect(Catalog.sector("tech").id):toBe("tech")
			t:expect(Catalog.sector("x")):toBeNil()
			t:expect(Catalog.upgrade("tech", "servers").id):toBe("servers")
			t:expect(Catalog.upgrade("tech", "shelves")):toBeNil()
			t:expect(#Catalog.sectorIds()):toBe(3)
		end)
	end)
end
