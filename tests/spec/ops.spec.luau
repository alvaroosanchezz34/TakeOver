--!nocheck
return function(t, load)
	local Clock = load:shared("Util/Clock")
	local Validate = load:shared("Util/Validate")
	local Result = load:shared("Util/Result")
	local Limits = load:shared("Config/Limits")
	local Monetization = load:shared("Config/Monetization")
	local Dispatcher = load:server("Core/Dispatcher")
	local Analytics = load:server("Core/Analytics")
	local Receipts = load:server("Core/Receipts")
	local PlayerData = load:server("Core/PlayerData")

	t:describe("Dispatcher (capa de red)", function()
		local function setup(extraActions)
			local clock = Clock.fake()
			local calls = {}
			local abuse = {}
			local sessions = { [1] = { id = "1" }, [2] = { id = "2" } }
			local actions = {
				Echo = {
					schema = Validate.object({ n = Validate.int({ min = 1, max = 100 }) }),
					handler = function(session, payload)
						table.insert(calls, { session = session, payload = payload })
						return Result.ok({ n = payload.n * 2 })
					end,
				},
				Boom = {
					schema = Validate.none(),
					handler = function()
						error("secreto interno")
					end,
				},
				Denied = {
					schema = Validate.none(),
					handler = function()
						return Result.err("INSUFFICIENT_FUNDS", { missing = 5 })
					end,
				},
				BadReturn = {
					schema = Validate.none(),
					handler = function()
						return "no soy un Result"
					end,
				},
			}
			for k, v in extraActions or {} do
				actions[k] = v
			end
			local d = Dispatcher.new({
				clock = clock,
				actions = actions,
				getSession = function(userId)
					return sessions[userId]
				end,
				onAbuse = function(userId, reason)
					table.insert(abuse, { userId = userId, reason = reason })
				end,
			})
			return d, clock, calls, abuse
		end

		t:test("camino feliz: valida, limpia el payload y devuelve datos", function()
			local d, _, calls = setup()
			local r = d:dispatch(1, "Echo", { n = 21, hack = "x" })
			t:expect(r.ok):toBe(true)
			t:expect(r.data.n):toBe(42)
			t:expect(calls[1].payload.hack):toBeNil() -- el handler nunca ve claves no declaradas
			t:expect(calls[1].session.id):toBe("1") -- la identidad sale del servidor, no del payload
		end)

		t:test("errores de negocio se devuelven con código y parámetros", function()
			local d = setup()
			local r = d:dispatch(1, "Denied", nil)
			t:expect(r.ok):toBe(false)
			t:expect(r.code):toBe("INSUFFICIENT_FUNDS")
			t:expect(r.params.missing):toBe(5)
		end)

		t:test("un error del handler no se propaga ni filtra detalles", function()
			local d = setup()
			local r = d:dispatch(1, "Boom", nil)
			t:expect(r):toEqual({ ok = false, code = "INTERNAL" })
			t:expect(d:dispatch(1, "BadReturn", nil).code):toBe("INTERNAL")
			t:expect(d:dispatch(1, "Echo", { n = 1 }).ok):toBe(true) -- sigue funcionando
		end)

		t:test("acciones desconocidas y tipos raros -> BAD_REQUEST", function()
			local d = setup()
			for _, action in { "NoExiste", 5, nil, {}, "__index", "" } do
				t:expect(d:dispatch(1, action, {}).code):toBe("BAD_REQUEST")
			end
		end)

		t:test("payloads inválidos: tipo, rango, NaN, texto, tabla anidada", function()
			local d = setup()
			for _, bad in
				{
					{ n = 0 },
					{ n = 101 },
					{ n = 0 / 0 },
					{ n = "5" },
					{ n = math.huge },
					{},
					"x",
					5,
					{ n = 1.5 },
				}
			do
				t:expect(d:dispatch(1, "Echo", bad).code):toBe("BAD_REQUEST")
			end
			t:expect(d:dispatch(1, "Echo", nil).code):toBe("BAD_REQUEST")
		end)

		t:test("sin sesión cargada -> NOT_READY y no se ejecuta nada", function()
			local d, _, calls = setup()
			t:expect(d:dispatch(99, "Echo", { n = 1 }).code):toBe("NOT_READY")
			t:expect(#calls):toBe(0)
		end)

		t:test("límite por acción: rechaza la ráfaga y se recupera con el tiempo", function()
			local d, clock = setup()
			local cap = 40 -- el límite global manda sobre una acción sin límite propio
			local accepted, limited = 0, 0
			for _ = 1, cap + 20 do
				local r = d:dispatch(1, "Echo", { n = 1 })
				if r.ok then
					accepted += 1
				elseif r.code == "RATE_LIMITED" then
					limited += 1
				end
			end
			t:expect(accepted):toBe(Limits.Global.capacity)
			t:expect(limited):toBeGreaterThan(0)
			clock:advance(2)
			t:expect(d:dispatch(1, "Echo", { n = 1 }).ok):toBe(true)
		end)

		t:test("los límites son independientes por jugador", function()
			local d = setup()
			for _ = 1, 100 do
				d:dispatch(1, "Echo", { n = 1 })
			end
			t:expect(d:dispatch(2, "Echo", { n = 1 }).ok):toBe(true)
		end)

		t:test("límite específico de una acción real (BuyUpgrade)", function()
			local d = setup({
				BuyUpgrade = {
					schema = Validate.none(),
					handler = function()
						return Result.ok(nil)
					end,
				},
			})
			local ok, limited = 0, 0
			for _ = 1, 30 do
				local r = d:dispatch(1, "BuyUpgrade", nil)
				if r.ok then
					ok += 1
				elseif r.code == "RATE_LIMITED" then
					limited += 1
				end
			end
			t:expect(ok):toBe(Limits.Actions.BuyUpgrade.capacity)
			t:expect(limited):toBe(30 - ok)
		end)

		t:test("ser limitado por frecuencia NO expulsa a un jugador legítimo", function()
			local d, _, _, abuse = setup()
			for _ = 1, 500 do
				d:dispatch(1, "Echo", { n = 1 })
			end
			t:expect(#abuse):toBe(0)
			t:expect(d:strikes(1)):toBe(0)
		end)

		t:test("violaciones de protocolo repetidas expulsan al jugador (y sólo a él)", function()
			local d, clock, _, abuse = setup()
			for _ = 1, Limits.MaxStrikes - 1 do
				d:dispatch(1, "NoExiste", {})
				clock:advance(0.3)
			end
			t:expect(#abuse):toBe(0)
			d:dispatch(1, "NoExiste", {})
			t:expect(#abuse):toBe(1)
			t:expect(abuse[1].userId):toBe(1)
			t:expect(d:strikes(2)):toBe(0)
		end)

		t:test("los strikes caducan: errores aislados espaciados no expulsan", function()
			local d, clock, _, abuse = setup()
			for _ = 1, Limits.MaxStrikes * 3 do
				d:dispatch(1, "NoExiste", {})
				clock:advance(Limits.StrikeWindowSeconds / 5)
			end
			t:expect(#abuse):toBe(0)
		end)

		t:test("onPlayerLeft libera límites y strikes", function()
			local d = setup()
			d:dispatch(1, "NoExiste", {})
			d:onPlayerLeft(1)
			t:expect(d:strikes(1)):toBe(0)
		end)
	end)

	t:describe("Analítica", function()
		local function setup()
			local clock = Clock.fake()
			local events = {}
			local a = Analytics.new(clock, function(e)
				table.insert(events, e)
			end)
			return a, clock, events
		end

		t:test(
			"las propiedades se filtran por lista cerrada: nada de texto libre ni datos privados",
			function()
				local a, _, events = setup()
				a:track(7, "offer_made", {
					sector = "tech",
					price = 500,
					playerName = "Juan Pérez", -- no permitido
					chat = "hola mundo", -- no permitido
					note = "x", -- no permitido
					amount = 0 / 0, -- NaN descartado
					reason = string.rep("a", 100), -- demasiado largo
				})
				local p = events[1].props
				t:expect(p.sector):toBe("tech")
				t:expect(p.price):toBe(500)
				t:expect(p.playerName):toBeNil()
				t:expect(p.chat):toBeNil()
				t:expect(p.note):toBeNil()
				t:expect(p.amount):toBeNil()
				t:expect(p.reason):toBeNil()
			end
		)

		t:test("tipos incorrectos en propiedades permitidas se descartan", function()
			local a, _, events = setup()
			a:track(7, "x", { price = "mucho", sector = 5, controlChanged = "si" })
			t:expect(events[1].props):toEqual({})
		end)

		t:test("embudo: cada paso se registra una vez por sesión con los segundos transcurridos", function()
			local a, clock, events = setup()
			a:sessionStart(7)
			clock:advance(12)
			a:funnel(7, 2)
			a:funnel(7, 2) -- repetido: ignorado
			clock:advance(30)
			a:funnel(7, 3)
			local names = {}
			for _, e in events do
				table.insert(names, e.name)
			end
			t:expect(names):toEqual({ "joined", "first_upgrade", "market_opened" })
			t:expect(events[2].props.seconds):toBe(12)
			t:expect(events[3].props.seconds):toBe(42)
		end)

		t:test("una sesión nueva reinicia el embudo", function()
			local a, _, events = setup()
			a:sessionStart(7)
			a:funnel(7, 2)
			a:sessionEnd(7, 100)
			a:sessionStart(7)
			a:funnel(7, 2)
			local n = 0
			for _, e in events do
				if e.name == "first_upgrade" then
					n += 1
				end
			end
			t:expect(n):toBe(2)
		end)

		t:test("un sink que falla no rompe el juego", function()
			local clock = Clock.fake()
			local a = Analytics.new(clock, function()
				error("sink caído")
			end)
			a:track(1, "x", nil)
			t:expect(a.counters.x):toBe(1)
		end)

		t:test("contadores y buffer reciente acotado", function()
			local a = setup()
			for _ = 1, 500 do
				a:track(1, "tick", nil)
			end
			t:expect(a.counters.tick):toBe(500)
			t:expect(#a.recent <= 200):toBe(true)
		end)

		t:test("eventos económicos incluyen flujo, importe y saldo", function()
			local a, _, events = setup()
			a:economy(7, "sink", 100, 900, "upgrade")
			t:expect(events[1].kind):toBe("economy")
			t:expect(events[1].props.flow):toBe("sink")
			t:expect(events[1].props.balance):toBe(900)
		end)
	end)

	t:describe("Recibos (ProcessReceipt idempotente)", function()
		-- Los IDs reales no existen aún (0): para probar la lógica usamos un producto de prueba.
		local function withProduct(fn)
			local product = Monetization.DeveloperProducts.confetti_pack
			local original = product.id
			-- La config está congelada; se prueba con una copia del módulo cargada aparte.
			fn(product, original)
		end

		t:test("con ID 0 (sin configurar) un producto se considera desactivado y no se procesa", function()
			local data = PlayerData.template(1)
			local outcome = Receipts.process(data, { PurchaseId = "p1", ProductId = 0, PlayerId = 1 }, 100)
			t:expect(outcome):toBe("retry")
			t:expect(next(data.receipts)):toBeNil()
			t:expect(data.cosmetics.consumables.confetti):toBeNil()
			withProduct(function(p)
				t:expect(p.id):toBe(0)
			end)
		end)

		t:test("productos desconocidos -> reintentar, nunca conceder", function()
			local data = PlayerData.template(1)
			t:expect(Receipts.process(data, { PurchaseId = "p1", ProductId = 99999, PlayerId = 1 }, 100))
				:toBe("retry")
			t:expect(next(data.receipts)):toBeNil()
		end)

		t:test("applyGrants da cosméticos, títulos y consumibles acumulables", function()
			local data = PlayerData.template(1)
			Receipts.applyGrants(
				data,
				{ cosmetics = { "fx_golden" }, titles = { "founder" }, consumables = { confetti = 10 } }
			)
			Receipts.applyGrants(data, { consumables = { confetti = 10 } })
			t:expect(data.cosmetics.owned.fx_golden):toBe(true)
			t:expect(data.cosmetics.owned["title:founder"]):toBe(true)
			t:expect(data.cosmetics.consumables.confetti):toBe(20)
		end)

		local testCatalog = {
			DeveloperProducts = {
				confetti_pack = { id = 4242, grants = { consumables = { confetti = 10 } } },
				skin = { id = 4243, grants = { cosmetics = { "office_gold" } } },
			},
			GamePasses = { vip = { id = 9001, grants = { cosmetics = { "fx_golden" } } } },
		}

		t:test("compra válida: se concede una vez y queda registrada", function()
			local data = PlayerData.template(1)
			local r = { PurchaseId = "abc", ProductId = 4242, PlayerId = 1 }
			t:expect(Receipts.process(data, r, 100, testCatalog)):toBe("granted")
			t:expect(data.cosmetics.consumables.confetti):toBe(10)
			t:expect(data.receipts["abc"]):toBe(100)
		end)

		t:test("IDEMPOTENCIA: reintentos del mismo recibo no duplican la recompensa", function()
			local data = PlayerData.template(1)
			local r = { PurchaseId = "abc", ProductId = 4242, PlayerId = 1 }
			Receipts.process(data, r, 100, testCatalog)
			for _ = 1, 5 do
				t:expect(Receipts.process(data, r, 200, testCatalog)):toBe("already")
			end
			t:expect(data.cosmetics.consumables.confetti):toBe(10)
			t:expect(data.receipts["abc"]):toBe(100) -- conserva la fecha original
		end)

		t:test("compras distintas del mismo producto sí se acumulan", function()
			local data = PlayerData.template(1)
			Receipts.process(data, { PurchaseId = "a", ProductId = 4242, PlayerId = 1 }, 1, testCatalog)
			Receipts.process(data, { PurchaseId = "b", ProductId = 4242, PlayerId = 1 }, 2, testCatalog)
			t:expect(data.cosmetics.consumables.confetti):toBe(20)
		end)

		t:test("producto con ID desconocido en un catálogo válido -> reintentar sin conceder", function()
			local data = PlayerData.template(1)
			t
				:expect(
					Receipts.process(data, { PurchaseId = "z", ProductId = 1, PlayerId = 1 }, 1, testCatalog)
				)
				:toBe("retry")
			t:expect(data.receipts["z"]):toBeNil()
		end)

		t:test("búsqueda de pases y productos con catálogo", function()
			t:expect(Receipts.passById(9001, testCatalog) ~= nil):toBe(true)
			t:expect(Receipts.productById(4243, testCatalog) ~= nil):toBe(true)
			t:expect(Receipts.passById(0, testCatalog)):toBeNil()
		end)

		t:test("los pases y productos se buscan por ID real; id 0 nunca coincide", function()
			t:expect(Receipts.productById(0)):toBeNil()
			t:expect(Receipts.passById(0)):toBeNil()
			t:expect(Receipts.passById(777)):toBeNil()
		end)

		t:test("equipar exige propiedad verificada en el servidor", function()
			local data = PlayerData.template(1)
			t:expect(Receipts.canEquip(data, "fx_default")):toBe(true) -- gratis
			t:expect(Receipts.canEquip(data, "fx_golden")):toBe(false) -- de pago, no comprado
			t:expect(Receipts.canEquip(data, "no_existe")):toBe(false)
			t:expect(Receipts.canEquip(data, "fx_confetti")):toBe(false) -- sin cargas
			data.cosmetics.consumables.confetti = 3
			t:expect(Receipts.canEquip(data, "fx_confetti")):toBe(true)
			data.cosmetics.owned.fx_golden = true
			t:expect(Receipts.canEquip(data, "fx_golden")):toBe(true)
		end)

		t:test("REGLA ÉTICA: nada de lo que se vende da Cash, ingresos ni ventaja en tratos", function()
			local function check(grants)
				for key in grants or {} do
					t:expect(table.find({ "cosmetics", "titles", "consumables" }, key) ~= nil):toBe(true)
				end
				for id in (grants or {}).consumables or {} do
					t:expect(table.find({ "confetti", "neon_skyline" }, id) ~= nil):toBe(true)
				end
			end
			for _, p in Monetization.GamePasses do
				check(p.grants)
			end
			for _, p in Monetization.DeveloperProducts do
				check(p.grants)
			end
		end)
	end)
end
