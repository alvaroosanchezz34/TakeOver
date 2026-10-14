--!nocheck
return function(t, load)
	local Format = load:shared("Util/Format")
	local Validate = load:shared("Util/Validate")
	local RateLimiter = load:shared("Util/RateLimiter")
	local Clock = load:shared("Util/Clock")
	local Table = load:shared("Util/Table")
	local Signal = load:shared("Util/Signal")

	t:describe("Format.cash", function()
		t:test("es: ejemplos del enunciado", function()
			t:expect(Format.cash(950, "es")):toBe("950 $")
			t:expect(Format.cash(1250, "es")):toBe("1,25 K $")
			t:expect(Format.cash(3_400_000, "es")):toBe("3,40 M $")
			t:expect(Format.cash(2_150_000_000, "es")):toBe("2,15 B $")
		end)

		t:test("en: separador decimal punto y símbolo delante", function()
			t:expect(Format.cash(950, "en")):toBe("$950")
			t:expect(Format.cash(1250, "en")):toBe("$1.25K")
			t:expect(Format.cash(3_400_000, "en")):toBe("$3.40M")
		end)

		t:test("redondeo en el borde de un tramo sube de sufijo", function()
			t:expect(Format.cash(999_999, "en")):toBe("$1.00M")
			t:expect(Format.cash(999_500, "en")):toBe("$999.50K")
			t:expect(Format.cash(1000, "en")):toBe("$1.00K")
			t:expect(Format.cash(999, "en")):toBe("$999")
		end)

		t:test("cero, negativos, NaN e infinito no rompen", function()
			t:expect(Format.cash(0, "es")):toBe("0 $")
			t:expect(Format.cash(-1500, "es")):toBe("-1,50 K $")
			t:expect(Format.cash(0 / 0, "es")):toBe("0 $")
			t:expect(Format.cash(math.huge, "es")):toBe("0 $")
		end)

		t:test("hasta 1e15 usa sufijos conocidos", function()
			t:expect(Format.cash(1e12, "en")):toBe("$1.00T")
			t:expect(Format.cash(1e15, "en")):toBe("$1.00Qa")
		end)

		t:test("fracciones de Cash se truncan (la economía usa enteros)", function()
			t:expect(Format.cash(12.9, "en")):toBe("$12")
		end)
	end)

	t:describe("Format.rate / bps / duration", function()
		t:test("rate admite decimales por debajo de 1000", function()
			t:expect(Format.rate(1.5, "en")):toBe("$1.5/s")
			t:expect(Format.rate(1.5, "es")):toBe("1,5 $/s")
			t:expect(Format.rate(12.25, "en")):toBe("$12.25/s")
			t:expect(Format.rate(1500, "es")):toBe("1,50 K $/s")
		end)

		t:test("bps a porcentaje", function()
			t:expect(Format.bps(2500, "es")):toBe("25 %")
			t:expect(Format.bps(1250, "es")):toBe("12,5 %")
			t:expect(Format.bps(10000, "en")):toBe("100%")
			t:expect(Format.bps(100, "en")):toBe("1%")
		end)

		t:test("duración", function()
			t:expect(Format.duration(75)):toBe("1:15")
			t:expect(Format.duration(3725)):toBe("1:02:05")
			t:expect(Format.duration(-5)):toBe("0:00")
		end)

		t:test("locale desde RobloxLocaleId", function()
			t:expect(Format.localeFromRoblox("es_es")):toBe("es")
			t:expect(Format.localeFromRoblox("es_mx")):toBe("es")
			t:expect(Format.localeFromRoblox("en_us")):toBe("en")
			t:expect(Format.localeFromRoblox(nil)):toBe("en")
		end)
	end)

	t:describe("Validate", function()
		local schema = Validate.object({
			companyId = Validate.string({ maxLen = 20, pattern = "^[%w_:]+$" }),
			bps = Validate.int({ min = 1, max = 10000 }),
			note = Validate.optional(Validate.string({ maxLen = 5 })),
		})

		t:test("acepta payload válido y descarta claves extra", function()
			local ok, clean = Validate.check(schema, { companyId = "u1:1", bps = 500, hack = 9 })
			t:expect(ok):toBe(true)
			t:expect(clean.companyId):toBe("u1:1")
			t:expect(clean.bps):toBe(500)
			t:expect(clean.hack):toBeNil()
		end)

		t:test("rechaza NaN, infinito, fraccionarios y fuera de rango", function()
			t:expect((Validate.check(schema, { companyId = "a", bps = 0 / 0 }))):toBe(false)
			t:expect((Validate.check(schema, { companyId = "a", bps = math.huge }))):toBe(false)
			t:expect((Validate.check(schema, { companyId = "a", bps = 1.5 }))):toBe(false)
			t:expect((Validate.check(schema, { companyId = "a", bps = 0 }))):toBe(false)
			t:expect((Validate.check(schema, { companyId = "a", bps = 10001 }))):toBe(false)
			t:expect((Validate.check(schema, { companyId = "a", bps = -5 }))):toBe(false)
		end)

		t:test("rechaza tipos incorrectos y cadenas peligrosas", function()
			t:expect((Validate.check(schema, { companyId = 5, bps = 1 }))):toBe(false)
			t:expect((Validate.check(schema, { companyId = "a b", bps = 1 }))):toBe(false)
			t:expect((Validate.check(schema, { companyId = "a\nb", bps = 1 }))):toBe(false)
			t:expect((Validate.check(schema, { companyId = string.rep("a", 21), bps = 1 }))):toBe(false)
			t:expect((Validate.check(schema, "texto"))):toBe(false)
			t:expect((Validate.check(schema, nil))):toBe(false)
		end)

		t:test("number (no entero) rechaza NaN e infinitos aunque estén en rango aparente", function()
			local rule = Validate.number({ min = 0, max = 100 })
			t:expect((Validate.check(rule, 0 / 0))):toBe(false)
			t:expect((Validate.check(rule, math.huge))):toBe(false)
			t:expect((Validate.check(rule, -math.huge))):toBe(false)
			t:expect((Validate.check(Validate.number(), 0 / 0))):toBe(false)
			t:expect((Validate.check(Validate.number(), math.huge))):toBe(false)
			t:expect((Validate.check(rule, 12.5))):toBe(true)
		end)

		t:test("optional acepta nil pero valida si viene", function()
			t:expect((Validate.check(schema, { companyId = "a", bps = 1, note = "toolong" }))):toBe(false)
			t:expect((Validate.check(schema, { companyId = "a", bps = 1, note = "ok" }))):toBe(true)
		end)

		t:test("oneOf, bool, array y none", function()
			t:expect((Validate.check(Validate.oneOf({ "a", "b" }), "a"))):toBe(true)
			t:expect((Validate.check(Validate.oneOf({ "a", "b" }), "c"))):toBe(false)
			t:expect((Validate.check(Validate.bool(), "true"))):toBe(false)
			t:expect((Validate.check(Validate.array(Validate.int(), 2), { 1, 2, 3 }))):toBe(false)
			t:expect((Validate.check(Validate.none(), nil))):toBe(true)
			t:expect((Validate.check(Validate.none(), 5))):toBe(false)
		end)

		t:test("rechaza objetos con demasiadas claves (DoS)", function()
			local big = {}
			for i = 1, 100 do
				big["k" .. i] = i
			end
			t:expect((Validate.check(Validate.object({}), big))):toBe(false)
		end)
	end)

	t:describe("RateLimiter", function()
		t:test("agota la capacidad y se recupera con el tiempo", function()
			local clock = Clock.fake()
			local rl = RateLimiter.new(clock)
			for _ = 1, 3 do
				t:expect(rl:consume(1, "buy", 3, 1)):toBe(true)
			end
			t:expect(rl:consume(1, "buy", 3, 1)):toBe(false)
			clock:advance(2)
			t:expect(rl:consume(1, "buy", 3, 1)):toBe(true)
			t:expect(rl:consume(1, "buy", 3, 1)):toBe(true)
			t:expect(rl:consume(1, "buy", 3, 1)):toBe(false)
		end)

		t:test("cubos independientes por jugador y por clave", function()
			local clock = Clock.fake()
			local rl = RateLimiter.new(clock)
			t:expect(rl:consume(1, "a", 1, 0)):toBe(true)
			t:expect(rl:consume(1, "a", 1, 0)):toBe(false)
			t:expect(rl:consume(2, "a", 1, 0)):toBe(true)
			t:expect(rl:consume(1, "b", 1, 0)):toBe(true)
		end)

		t:test("reset libera al jugador", function()
			local clock = Clock.fake()
			local rl = RateLimiter.new(clock)
			rl:consume(1, "a", 1, 0)
			rl:reset(1)
			t:expect(rl:consume(1, "a", 1, 0)):toBe(true)
		end)
	end)

	t:describe("Table / Signal", function()
		t:test("deepFreeze impide mutar configuración", function()
			local cfg = Table.deepFreeze({ a = { b = 1 } })
			t:expect(function()
				cfg.a.b = 2
			end):toThrow()
		end)

		t:test("ringPush acota", function()
			local list = {}
			for i = 1, 10 do
				Table.ringPush(list, i, 3)
			end
			t:expect(list):toEqual({ 8, 9, 10 })
		end)

		t:test("deepClone no comparte referencias", function()
			local a = { x = { y = 1 } }
			local b = Table.deepClone(a)
			b.x.y = 2
			t:expect(a.x.y):toBe(1)
		end)

		t:test("Signal: Connect/Fire/Disconnect y aislamiento de errores", function()
			local s = Signal.new()
			local calls = 0
			local c = s:Connect(function()
				calls += 1
			end)
			s:Connect(function()
				error("boom")
			end)
			s:Fire()
			t:expect(calls):toBe(1)
			c:Disconnect()
			s:Fire()
			t:expect(calls):toBe(1)
		end)
	end)
end
