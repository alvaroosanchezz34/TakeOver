--!nocheck
local fs = require("@lune/fs")

local function walk(dir, out)
	for _, e in fs.readDir(dir) do
		local full = dir .. "/" .. e
		if fs.isDir(full) then
			walk(full, out)
		elseif e:match("%.luau$") then
			table.insert(out, full)
		end
	end
	return out
end

-- Quita comentarios para no dar falsos positivos con texto explicativo.
local function stripComments(source)
	source = source:gsub("%-%-%[(=*)%[.-%]%1%]", "")
	source = source:gsub("%-%-[^\n]*", "")
	return source
end

local function scan(files, pattern)
	local hits = {}
	for _, path in files do
		local code = stripComments(fs.readFile(path))
		for line in code:gmatch("[^\n]+") do
			if line:find(pattern) then
				table.insert(hits, path .. ": " .. line:gsub("^%s+", ""))
			end
		end
	end
	return hits
end

return function(t, load)
	local files = walk("src", {})

	t:describe("Auditoría estática de seguridad", function()
		t:test("no hay ejecución dinámica de código (loadstring, getfenv, setfenv)", function()
			t:expect(scan(files, "loadstring")):toEqual({})
			t:expect(scan(files, "getfenv")):toEqual({})
			t:expect(scan(files, "setfenv")):toEqual({})
		end)

		t:test("no hay require por ID de asset (vector típico de backdoors)", function()
			t:expect(scan(files, "require%(%s*%d")):toEqual({})
			t:expect(scan(files, "require%(%s*[\"']rbxassetid")):toEqual({})
		end)

		t:test("no se descargan ni insertan assets/código externos", function()
			t:expect(scan(files, "InsertService")):toEqual({})
			t:expect(scan(files, "LoadAsset")):toEqual({})
			t:expect(scan(files, "HttpService:%a*Async")):toEqual({})
			t:expect(scan(files, "RequestAsync")):toEqual({})
			t:expect(scan(files, "rbxassetid")):toEqual({}) -- sin assets de terceros: todo es código
		end)

		t:test("no se crean scripts en tiempo de ejecución ni se escribe .Source", function()
			t:expect(scan(files, 'Instance%.new%("[%a]*Script"')):toEqual({})
			t:expect(scan(files, "%.Source%s*=")):toEqual({})
		end)

		t:test("el ÚNICO punto de entrada de red del servidor es el despachador", function()
			local invokes = scan(files, "OnServerInvoke%s*=")
			t:expect(#invokes):toBe(1)
			t:expect(invokes[1]):toContain("Services/Net.luau")
			t:expect(scan(files, "OnServerEvent")):toEqual({})
		end)

		t:test("los remotes sólo se crean en Shared/Remotes (uno de cada tipo)", function()
			local functions = scan(files, 'Instance%.new%("RemoteFunction"')
			local events = scan(files, 'Instance%.new%("RemoteEvent"')
			t:expect(#functions):toBe(1)
			t:expect(#events):toBe(1)
			t:expect(functions[1]):toContain("shared/Remotes.luau")
			t:expect(events[1]):toContain("shared/Remotes.luau")
			t:expect(scan(files, 'Instance%.new%("Bindable')):toEqual({})
		end)

		t:test("el cliente nunca toca DataStore ni servicios de servidor", function()
			local client = walk("src/client", {})
			t:expect(scan(client, "DataStoreService")):toEqual({})
			t:expect(scan(client, "ServerScriptService")):toEqual({})
			t:expect(scan(client, "ServerStorage")):toEqual({})
			t:expect(scan(client, "MessagingService")):toEqual({})
		end)

		t:test("el cliente no importa módulos del servidor", function()
			local client = walk("src/client", {})
			t:expect(scan(client, "Server%.Core")):toEqual({})
			t:expect(scan(client, "require%(.-Server")):toEqual({})
		end)

		t:test("el acceso global _G sólo existe en las herramientas de QA de Studio", function()
			local hits = scan(files, "_G%.")
			for _, h in hits do
				t:expect(h):toContain("Main.server.luau")
			end
			local main = stripComments(fs.readFile("src/server/Main.server.luau"))
			local qa = main:find("if RunService:IsStudio%(%) then\n%s*_G%.Takeover")
			t:expect(qa ~= nil):toBe(true)
		end)

		t:test(
			"el servidor nunca confía en identidad enviada por el cliente: ninguna acción recibe userId propio",
			function()
				local actions = fs.readFile("src/server/Core/Actions.luau")
				-- Los esquemas no aceptan campos que representen al jugador que actúa.
				t:expect(actions:find("playerId%s*=")):toBeNil()
				t:expect(actions:find("actorId%s*=")):toBeNil()
				t:expect(actions:find("buyerId%s*=%s*V%.")):toBeNil()
				-- Ningún esquema de acción acepta un precio de MEJORA ni una cantidad de Cash.
				t:expect(actions:find("cost%s*=%s*V%.")):toBeNil()
				t:expect(actions:find("cash%s*=%s*V%.")):toBeNil()
			end
		)

		t:test("el dinero sólo cambia por el Ledger (nadie escribe data.cash directamente)", function()
			local allowed = {
				["src/server/Core/Ledger.luau"] = true,
				["src/server/Core/PlayerData.luau"] = true, -- plantilla y reparación al cargar
			}
			local offenders = {}
			for _, path in files do
				if not allowed[path] then
					local code = stripComments(fs.readFile(path))
					if
						code:find("data%.cash%s*=[^=]")
						or code:find("%.cash%s*%+=")
						or code:find("%.cash%s*%-=")
					then
						table.insert(offenders, path)
					end
				end
			end
			t:expect(offenders):toEqual({})
		end)

		t:test(
			"los tests de integridad no se saltan: existe cobertura de las salvaguardas críticas",
			function()
				local tool = fs.readFile("tools/mutation_check.py")
				local count = 0
				for _ in tool:gmatch("\n    %(\n") do
					count += 1
				end
				t:expect(count >= 18):toBe(true)
			end
		)
	end)
end
