--!nocheck
local FakeDataStore = require("../harness/FakeDataStore")
local Loader = require("../harness/Loader")
local MockInstance = require("../harness/MockInstance")
local task = require("@lune/task")

return function(t, load)
	local function boot(options)
		options = options or {}
		-- Las esperas de reintento (1 s, 2 s, 4 s...) no deben dormir de verdad en los tests.
		local fastTask = setmetatable({
			wait = function() end,
		}, { __index = task })
		-- Reloj simulado: time() (segundos de partida) y os.time() (unix) avanzan sólo con env.step().
		local fake = { mono = 0, unix = 1_700_000_000 }
		local fakeOs = setmetatable({
			time = function()
				return math.floor(fake.unix)
			end,
		}, { __index = os })
		local l = Loader.new({
			env = {
				task = fastTask,
				time = function()
					return fake.mono
				end,
				os = fakeOs,
			},
			serviceOptions = {
				dataStore = options.dataStore,
				isStudio = options.isStudio,
			},
		})
		local PlayerData = l:server("Core/PlayerData")
		local ds = options.dataStore or FakeDataStore.new({ validate = PlayerData.assertSerializable })
		l.services.DataStoreService.GetDataStore = nil
		rawget(l.services.DataStoreService, "_props").GetDataStore = function()
			return ds
		end
		l:run(l:node("server", "Main"))
		local players = l.services.Players
		local run = l.services.RunService
		local env = { l = l, ds = ds, players = players, run = run }

		function env.join(userId, name)
			local p = MockInstance.player(userId, name)
			MockInstance.joinPlayer(players, p)
			return p
		end
		function env.leave(p)
			MockInstance.leavePlayer(players, p)
		end
		function env.step(seconds)
			for _ = 1, seconds do
				fake.mono += 1
				fake.unix += 1
				MockInstance.fire(run, "Heartbeat", 1)
			end
		end
		function env.remotes()
			local folder = l.services.ReplicatedStorage:FindFirstChild("TakeoverRemotes")
			return folder.Invoke, folder.Push
		end
		return env
	end

	t:describe("Arranque del servidor (Main.server en el simulador)", function()
		t:test("arranca sin errores y crea los remotes, el mundo y los servicios", function()
			local b = boot()
			local invoke, push = b.remotes()
			t:expect(invoke.ClassName):toBe("RemoteFunction")
			t:expect(push.ClassName):toBe("RemoteEvent")
			local workspace = b.l.services.Workspace
			t:expect(workspace:FindFirstChild("TakeoverWorld") ~= nil):toBe(true)
			t:expect(#workspace.TakeoverWorld:GetChildren()):toBeGreaterThan(40)
			t:expect(b.l.services.Lighting:FindFirstChild("TakeoverAtmosphere") ~= nil):toBe(true)
		end)

		t:test("un jugador entra: perfil, parcela, estado enviado y petición de red atendida", function()
			local b = boot()
			local invoke, push = b.remotes()
			local p = b.join(101, "Ana")
			b.step(1)
			local fired = MockInstance.fired(push)
			local sawState = false
			for _, f in fired do
				if f.args[1].type == "state" and f.player == p then
					sawState = true
					t:expect(f.args[1].cash >= 100):toBe(true)
				end
			end
			t:expect(sawState):toBe(true)
			-- el cliente pide comprar una mejora por el RemoteFunction
			MockInstance.localPlayer = p
			local r = invoke:InvokeServer("BuyUpgrade", { companyId = "101:1", upgradeId = "shelves" })
			t:expect(r.ok):toBe(true)
			t:expect(r.data.cost):toBe(20)
			-- la parcela se construyó con su edificio
			b.step(2)
			local plot1 = b.l.services.Workspace.TakeoverWorld.Parcela1
			t:expect(plot1:FindFirstChild("Empresa_101:1") ~= nil):toBe(true)
		end)

		t:test("el RemoteFunction nunca lanza ni filtra detalles ante entradas hostiles", function()
			local b = boot()
			local invoke = b.remotes()
			local p = b.join(101, "Ana")
			b.step(1)
			MockInstance.localPlayer = p
			for _, args in
				{
					{ nil, nil },
					{ 5, 5 },
					{ "BuyUpgrade", "x" },
					{ "BuyUpgrade", { companyId = "101:1", upgradeId = 5 } },
					{ {}, {} },
				}
			do
				local r = invoke:InvokeServer(args[1], args[2])
				t:expect(r.ok):toBe(false)
			end
			-- un "cliente" que no es un Player
			MockInstance.localPlayer = "no soy un jugador"
			t:expect(invoke:InvokeServer("GetState", nil).ok):toBe(false)
		end)

		t:test("la economía avanza con el Heartbeat y se guarda con el autoguardado", function()
			local b = boot()
			local p = b.join(101, "Ana")
			b.step(70)
			local rec = b.ds:peek("Player_101")
			t:expect(rec ~= nil):toBe(true)
			t:expect(rec.data.cash > 100):toBe(true)
			t:expect(rec.lock.jobId):toBe("test-job")
		end)

		t:test("al salir se guarda y libera; al cerrar el servidor se guarda a todos", function()
			local b = boot()
			local p1 = b.join(101, "Ana")
			b.join(102, "Beto")
			b.step(3)
			b.leave(p1)
			t:expect(b.ds:peek("Player_101").lock):toBeNil()
			t:expect(b.l.services.Workspace.TakeoverWorld.Parcela1:FindFirstChild("Empresa_101:1")):toBeNil()
			b.l:close()
			t:expect(b.ds:peek("Player_102").lock):toBeNil()
		end)

		t:test("sin acceso a DataStore usa memoria y el juego sigue funcionando", function()
			local failing = FakeDataStore.new()
			failing:failNext(1000)
			local b = boot({ dataStore = failing })
			local invoke = b.remotes()
			local p = b.join(101, "Ana")
			b.step(1)
			MockInstance.localPlayer = p
			t:expect(invoke:InvokeServer("GetState", nil).ok):toBe(true)
		end)

		t:test(
			"si el DataStore falla al cargar: se expulsa con un mensaje claro y no se toca nada",
			function()
				local PlayerData = load:server("Core/PlayerData")
				local ds = FakeDataStore.new({ validate = PlayerData.assertSerializable })
				ds:set("Player_201", { recordVersion = 1, data = { cash = 777 } })
				local b = boot({ dataStore = ds })
				ds:failNext(100) -- el arranque pasó la prueba de acceso; ahora el servicio falla
				local p = b.join(201, "Ana")
				b.step(1)
				local kicked = MockInstance.props(p).KickedWith
				t:expect(kicked ~= nil):toBe(true)
				t:expect(kicked):toContain("No pudimos cargar")
				ds:failNext(0)
				t:expect(ds:peek("Player_201").data.cash):toBe(777)
			end
		)

		t:test("si sus datos están bloqueados por otro servidor: se expulsa sin pisarlos", function()
			local PlayerData = load:server("Core/PlayerData")
			local ds = FakeDataStore.new({ validate = PlayerData.assertSerializable })
			local b = boot({ dataStore = ds })
			ds:set("Player_202", {
				recordVersion = 1,
				data = PlayerData.template(os.time()),
				lock = { jobId = "otro-servidor", t = os.time() },
			})
			local p = b.join(202, "Beto")
			b.step(1)
			t:expect(MockInstance.props(p).KickedWith):toContain("otro servidor")
			t:expect(ds:peek("Player_202").lock.jobId):toBe("otro-servidor")
		end)

		t:test("herramientas de QA sólo con IsStudio", function()
			local studio = boot({ isStudio = true })
			t:expect(studio.l.game ~= nil):toBe(true)
		end)
	end)
end
