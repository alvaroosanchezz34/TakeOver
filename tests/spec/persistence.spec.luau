--!nocheck
local FakeDataStore = require("../harness/FakeDataStore")
local task = require("@lune/task")

return function(t, load)
	local PlayerData = load:server("Core/PlayerData")
	local ProfileStore = load:server("Core/ProfileStore")
	local Clock = load:shared("Util/Clock")
	local Ownership = load:shared("Economy/Ownership")
	local Company = load:shared("Economy/Company")

	local function newWorld()
		local clock = Clock.fake()
		local ds = FakeDataStore.new({ validate = PlayerData.assertSerializable })
		local logs = {}
		local waits = {}
		local function store(jobId, extra)
			local deps = {
				dataStore = ds,
				clock = clock,
				jobId = jobId,
				wait = function(s)
					table.insert(waits, s)
				end,
				log = function(m)
					table.insert(logs, m)
				end,
				lockAcquireAttempts = 3,
			}
			for k, v in extra or {} do
				deps[k] = v
			end
			return ProfileStore.new(deps)
		end
		return { clock = clock, ds = ds, store = store, logs = logs, waits = waits }
	end

	t:describe("PlayerData", function()
		t:test("plantilla: 100 $ iniciales y versión actual", function()
			local d = PlayerData.template(1000)
			t:expect(d.cash):toBe(100)
			t:expect(d.version):toBe(PlayerData.CURRENT_VERSION)
			t:expect(d.meta.firstJoin):toBe(1000)
			t:expect(PlayerData.assertSerializable(d)):toBe(true)
		end)

		t:test("migración v0 -> v1 conserva los datos existentes", function()
			local legacy = { money = 777, stats = { totalEarned = 5000 }, extra = "se conserva" }
			local r = PlayerData.migrate(legacy)
			t:expect(r):toBeOk()
			t:expect(r.value.cash):toBe(777)
			t:expect(r.value.money):toBeNil()
			t:expect(r.value.version):toBe(1)
			t:expect(r.value.stats.totalEarned):toBe(5000)
			t:expect(r.value.extra):toBe("se conserva")
		end)

		t:test("datos de una versión futura se rechazan", function()
			t:expect(PlayerData.migrate({ version = 99 })):toBeErr("DATA_FROM_FUTURE")
			t:expect(PlayerData.migrate({ version = -1 })):toBeErr("DATA_VERSION_INVALID")
			t:expect(PlayerData.migrate({ version = 1.5 })):toBeErr("DATA_VERSION_INVALID")
		end)

		t:test("reconcile añade campos nuevos sin pisar los existentes", function()
			local d = { cash = 5, stats = { totalEarned = 9 } }
			PlayerData.reconcile(d, PlayerData.template(1))
			t:expect(d.cash):toBe(5)
			t:expect(d.stats.totalEarned):toBe(9)
			t:expect(d.stats.dealsClosed):toBe(0)
			t:expect(d.settings.sfx):toBe(true)
			-- no comparte referencias con la plantilla
			local d2 = {}
			PlayerData.reconcile(d2, PlayerData.template(1))
			d2.settings.sfx = false
			local d3 = {}
			PlayerData.reconcile(d3, PlayerData.template(1))
			t:expect(d3.settings.sfx):toBe(true)
		end)

		t:test("repair neutraliza dinero NaN/negativo/enorme", function()
			for _, bad in { 0 / 0, -50, 1e30, math.huge, "mucho" } do
				local d = PlayerData.template(1)
				d.cash = bad
				PlayerData.repair(d, 1)
				t:expect(d.cash >= 0 and d.cash <= 1e15 and d.cash % 1 == 0):toBe(true)
			end
		end)

		t:test("repair arregla una cap table rota sin perder la empresa", function()
			local d = PlayerData.template(1)
			local c = Company.new({ founderId = "1", index = 1, sector = "commerce", now = 1 })
			c.cap.holders["2"] = 5000 -- suma 15000: corrupta
			d.companies[c.id] = c
			local repairs = PlayerData.repair(d, 1)
			t:expect(#repairs):toBeGreaterThan(0)
			t:expect(Ownership.validate(d.companies[c.id].cap)):toBe(true)
			t:expect(d.companies[c.id].cap.holders["1"]):toBe(10000)
		end)

		t:test("repair descarta participaciones inválidas y recorta recibos", function()
			local d = PlayerData.template(1)
			d.holdings["a:1"] = { bps = -5 }
			d.holdings["b:1"] = { bps = 2500 }
			for i = 1, PlayerData.MAX_RECEIPTS + 20 do
				d.receipts[tostring(i)] = i
			end
			PlayerData.repair(d, 1)
			t:expect(d.holdings["a:1"]):toBeNil()
			t:expect(d.holdings["b:1"].bps):toBe(2500)
			local n = 0
			for _ in d.receipts do
				n += 1
			end
			t:expect(n):toBe(PlayerData.MAX_RECEIPTS)
			t:expect(d.receipts[tostring(PlayerData.MAX_RECEIPTS + 20)]):toBe(PlayerData.MAX_RECEIPTS + 20)
		end)

		t:test("assertSerializable rechaza lo que DataStore rechazaría", function()
			t:expect((PlayerData.assertSerializable({ a = 1, b = { c = "x" } }))):toBe(true)
			t:expect((PlayerData.assertSerializable({ a = function() end }))):toBe(false)
			t:expect((PlayerData.assertSerializable({ a = 0 / 0 }))):toBe(false)
			t:expect((PlayerData.assertSerializable({ a = math.huge }))):toBe(false)
			t:expect((PlayerData.assertSerializable({ [1] = "a", x = "b" }))):toBe(false)
			t:expect((PlayerData.assertSerializable({ [1] = "a", [3] = "b" }))):toBe(false)
			t:expect((PlayerData.assertSerializable({ [5.5] = "a" }))):toBe(false)
			t:expect((PlayerData.assertSerializable(setmetatable({}, {})))):toBe(false)
			t:expect((PlayerData.assertSerializable({ a = "\xff\xfe" }))):toBe(false)
			local cyc = {}
			cyc.self = cyc
			t:expect((PlayerData.assertSerializable(cyc))):toBe(false)
		end)
	end)

	t:describe("ProfileStore: ciclo guardar / recuperar", function()
		t:test("jugador nuevo: perfil por defecto y bloqueo tomado", function()
			local w = newWorld()
			local s = w.store("A")
			local r = s:load("u1")
			t:expect(r):toBeOk()
			t:expect(r.value.isNew):toBe(true)
			t:expect(r.value.data.cash):toBe(100)
			t:expect(w.ds:peek("u1").lock.jobId):toBe("A")
		end)

		t:test("el progreso se conserva al salir y se recupera al volver a entrar", function()
			local w = newWorld()
			local s = w.store("A")
			local p = s:load("u1").value
			p.data.cash = 4321
			p.data.stats.totalEarned = 9999
			local c = Company.new({ founderId = "1", index = 1, sector = "tech", now = 1 })
			c.upgrades.servers = 3
			c.level = 2
			Ownership.transfer(c.cap, "1", "2", 3000)
			p.data.companies[c.id] = c
			s:touch(p)
			t:expect(s:save(p, true)):toBeOk()
			t:expect(p.active):toBe(false)
			t:expect(w.ds:peek("u1").lock):toBeNil()

			-- vuelve a entrar (otro servidor)
			local s2 = w.store("B")
			local r2 = s2:load("u1")
			t:expect(r2):toBeOk()
			local d = r2.value.data
			t:expect(r2.value.isNew):toBe(false)
			t:expect(d.cash):toBe(4321)
			t:expect(d.stats.totalEarned):toBe(9999)
			t:expect(d.companies["1:1"].level):toBe(2)
			t:expect(d.companies["1:1"].upgrades.servers):toBe(3)
			t:expect(d.companies["1:1"].cap.holders["2"]):toBe(3000)
			t:expect(Ownership.validate(d.companies["1:1"].cap)):toBe(true)
		end)

		t:test("autoguardado conserva el bloqueo y renueva el latido", function()
			local w = newWorld()
			local s = w.store("A")
			local p = s:load("u1").value
			local t0 = w.ds:peek("u1").lock.t
			w.clock:advance(60)
			p.data.cash = 50
			s:touch(p)
			t:expect(s:save(p)):toBeOk()
			local rec = w.ds:peek("u1")
			t:expect(rec.lock.jobId):toBe("A")
			t:expect(rec.lock.t):toBe(t0 + 60)
			t:expect(rec.data.cash):toBe(50)
			t:expect(p.active):toBe(true)
			t:expect(p.dirty):toBe(false)
		end)

		t:test("migra datos antiguos al cargar", function()
			local w = newWorld()
			w.ds:set("u9", { recordVersion = 1, data = { money = 321 } })
			local r = w.store("A"):load("u9")
			t:expect(r):toBeOk()
			t:expect(r.value.data.cash):toBe(321)
			t:expect(r.value.data.version):toBe(PlayerData.CURRENT_VERSION)
			t:expect(r.value.data.settings.sfx):toBe(true)
		end)

		t:test("datos de versión futura: no se cargan y no se pisa el registro", function()
			local w = newWorld()
			w.ds:set("u9", { recordVersion = 1, data = { version = 99, cash = 5 } })
			local r = w.store("A"):load("u9")
			t:expect(r):toBeErr("DATA_FROM_FUTURE")
			t:expect(w.ds:peek("u9").data.cash):toBe(5)
			t:expect(w.ds:peek("u9").lock):toBeNil() -- bloqueo liberado
		end)

		t:test("datos corruptos se reparan al cargar y quedan marcados para guardar", function()
			local w = newWorld()
			local bad = PlayerData.template(1)
			bad.cash = -999
			w.ds:set("u9", { recordVersion = 1, data = bad })
			local p = w.store("A"):load("u9").value
			t:expect(p.data.cash):toBe(0)
			t:expect(#p.repairs):toBeGreaterThan(0)
			t:expect(p.dirty):toBe(true)
		end)
	end)

	t:describe("ProfileStore: errores de DataStore", function()
		t:test("un fallo transitorio se reintenta y acaba guardando", function()
			local w = newWorld()
			local s = w.store("A")
			local p = s:load("u1").value
			p.data.cash = 777
			s:touch(p)
			w.ds:failNext(2)
			t:expect(s:save(p)):toBeOk()
			t:expect(w.ds:peek("u1").data.cash):toBe(777)
			t:expect(#w.waits):toBe(2) -- dos esperas con retroceso exponencial
			t:expect(w.waits[1]):toBe(1)
			t:expect(w.waits[2]):toBe(2)
		end)

		t:test("si se agotan los reintentos no se pierde nada: sigue sucio", function()
			local w = newWorld()
			local s = w.store("A")
			local p = s:load("u1").value
			p.data.cash = 888
			s:touch(p)
			w.ds:failNext(100)
			t:expect(s:save(p)):toBeErr("SAVE_FAILED")
			t:expect(p.dirty):toBe(true)
			t:expect(p.active):toBe(true)
			-- el servicio se recupera: el siguiente guardado funciona
			w.ds:failNext(0)
			t:expect(s:save(p)):toBeOk()
			t:expect(w.ds:peek("u1").data.cash):toBe(888)
			t:expect(p.dirty):toBe(false)
		end)

		t:test("fallos al cargar: se reintenta y después se informa", function()
			local w = newWorld()
			w.ds:failNext(1)
			t:expect(w.store("A"):load("u1")):toBeOk()
			w.ds:failNext(100)
			t:expect(w.store("A"):load("u2")):toBeErr("LOAD_FAILED")
		end)

		t:test("cambios hechos MIENTRAS se guarda no se pierden (siguen sucios)", function()
			local w = newWorld()
			local s = w.store("A")
			local p = s:load("u1").value
			p.data.cash = 10
			s:touch(p)
			-- simulamos que el juego muta durante la llamada a UpdateAsync
			local original = w.ds.UpdateAsync
			w.ds.UpdateAsync = function(self, key, fn)
				p.data.cash = 20
				s:touch(p)
				return original(self, key, fn)
			end
			t:expect(s:save(p)):toBeOk()
			w.ds.UpdateAsync = original
			t:expect(w.ds:peek("u1").data.cash):toBe(10) -- lo guardado es la instantánea coherente
			t:expect(p.dirty):toBe(true) -- y el cambio posterior sigue pendiente
			t:expect(s:save(p)):toBeOk()
			t:expect(w.ds:peek("u1").data.cash):toBe(20)
		end)

		t:test("datos no serializables nunca llegan al DataStore", function()
			local w = newWorld()
			local s = w.store("A")
			local p = s:load("u1").value
			p.data.oops = function() end
			s:touch(p)
			local before = w.ds.updates
			t:expect(s:save(p)):toBeErr("NOT_SERIALIZABLE")
			t:expect(w.ds.updates):toBe(before)
		end)
	end)

	t:describe("ProfileStore: bloqueo de sesión (dos servidores)", function()
		t:test("un segundo servidor no puede cargar un perfil bloqueado", function()
			local w = newWorld()
			local a = w.store("A")
			local b = w.store("B")
			local pa = a:load("u1").value
			pa.data.cash = 555
			a:touch(pa)
			a:save(pa)
			t:expect(b:load("u1")):toBeErr("SESSION_LOCKED")
			t:expect(w.ds:peek("u1").lock.jobId):toBe("A") -- B no tocó el bloqueo
		end)

		t:test("tras liberar, el otro servidor ve los datos más recientes", function()
			local w = newWorld()
			local a = w.store("A")
			local pa = a:load("u1").value
			pa.data.cash = 2468
			a:touch(pa)
			a:save(pa, true)
			local rb = w.store("B"):load("u1")
			t:expect(rb):toBeOk()
			t:expect(rb.value.data.cash):toBe(2468)
		end)

		t:test(
			"un bloqueo caducado (servidor caído) puede tomarse; el antiguo pierde el derecho a escribir",
			function()
				local w = newWorld()
				local a = w.store("A")
				local pa = a:load("u1").value
				pa.data.cash = 100
				a:touch(pa)
				a:save(pa)
				w.clock:advance(301) -- más que lockTimeout
				local rb = w.store("B"):load("u1")
				t:expect(rb):toBeOk()
				-- A sigue vivo (zombi) e intenta guardar sobre los datos de B
				pa.data.cash = 999999
				a:touch(pa)
				t:expect(a:save(pa)):toBeErr("LOCK_LOST")
				t:expect(pa.lockLost):toBe(true)
				t:expect(w.ds:peek("u1").data.cash):toBe(100) -- no se sobrescribió
				t:expect(w.ds:peek("u1").lock.jobId):toBe("B")
				-- y ya no puede ni intentarlo
				t:expect(a:save(pa)):toBeErr("LOCK_LOST")
			end
		)

		t:test("CARRERA: dos servidores cargan a la vez y sólo uno obtiene el perfil", function()
			local w = newWorld()
			w.ds.yield = true -- cada operación cede el hilo: fuerza intercalado real
			local results = {}
			local pending = 2
			for _, job in { "A", "B" } do
				task.spawn(function()
					results[job] = w.store(job):load("u1")
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
			local winner = if results.A.ok then "A" else "B"
			t:expect(w.ds:peek("u1").lock.jobId):toBe(winner)
		end)

		t:test("CARRERA: guardados concurrentes del mismo perfil no se pisan ni se pierden", function()
			local w = newWorld()
			local s = w.store("A")
			local p = s:load("u1").value
			w.ds.yield = true
			local done = 0
			for i = 1, 3 do
				task.spawn(function()
					p.data.cash += i
					s:touch(p)
					s:save(p)
					done += 1
				end)
			end
			while done < 3 do
				task.wait()
			end
			s:touch(p)
			w.ds.yield = false
			t:expect(s:save(p)):toBeOk()
			t:expect(w.ds:peek("u1").data.cash):toBe(100 + 1 + 2 + 3)
		end)
	end)
end
