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

local function placeholders(text)
	local set = {}
	for name in text:gmatch("{([%w_]+)}") do
		set[name] = true
	end
	return set
end

return function(t, load)
	local Locale = load:shared("Locale")
	local Sectors = load:shared("Config/Sectors")
	local Events = load:shared("Config/Events")
	local Monetization = load:shared("Config/Monetization")
	local Progression = load:shared("Config/Progression")
	local Balance = load:shared("Config/Balance")
	local Format = load:shared("Util/Format")

	t:describe("Localización", function()
		t:test("ES y EN tienen exactamente las mismas claves", function()
			for key in Locale.es do
				if Locale.en[key] == nil then
					error("falta en inglés: " .. key)
				end
			end
			for key in Locale.en do
				if Locale.es[key] == nil then
					error("falta en español: " .. key)
				end
			end
			t:expect(#Locale.keys() > 300):toBe(true)
		end)

		t:test("los parámetros {x} coinciden entre idiomas y no hay textos vacíos", function()
			for key, es in Locale.es do
				local en = Locale.en[key]
				t:expect(#es > 0 and #en > 0):toBe(true)
				local a, b = placeholders(es), placeholders(en)
				for name in a do
					if not b[name] then
						error(("%s: el parámetro {%s} falta en inglés"):format(key, name))
					end
				end
				for name in b do
					if not a[name] then
						error(("%s: el parámetro {%s} falta en español"):format(key, name))
					end
				end
			end
		end)

		t:test("interpolación y fallbacks", function()
			t:expect(Locale.t("es", "common.level", { n = 3 })):toBe("Nivel 3")
			t:expect(Locale.t("en", "common.level", { n = 3 })):toBe("Level 3")
			t:expect(Locale.t("es", "clave.inexistente")):toBe("clave.inexistente")
			t:expect(Locale.t("es", "hud.next.missing", {})):toContain("{amount}") -- sin valor no se pierde el hueco
			t:expect(Locale.err("es", "INSUFFICIENT_FUNDS", { missing = "5 $" })):toContain("5 $")
			t:expect(Locale.err("en", "CODIGO_RARO")):toBe(Locale.en["err.UNKNOWN"])
			t:expect(Locale.err("es", nil)):toBe(Locale.es["err.UNKNOWN"])
		end)

		t:test("todo nameKey/descKey de la configuración existe en ambos idiomas", function()
			local function need(key)
				t:expect(Locale.has("es", key) and Locale.has("en", key)):toBe(true)
				if not (Locale.has("es", key) and Locale.has("en", key)) then
					error("sin traducir: " .. key)
				end
			end
			for _, sectorId in Sectors.order do
				local sector = Sectors.byId[sectorId]
				need(sector.nameKey)
				need(sector.nameKey .. ".desc")
				need(sector.nameKey .. ".mech")
				for _, up in sector.upgrades do
					need(up.nameKey)
					need("effect." .. up.effect.kind)
				end
			end
			need("effect.level")
			need("upgrade.level")
			for _, p in Monetization.GamePasses do
				need(p.nameKey)
				need(p.descKey)
			end
			for _, p in Monetization.DeveloperProducts do
				need(p.nameKey)
				need(p.descKey)
			end
			for id in Events.Events do
				need("event." .. id)
				need("event." .. id .. ".desc")
			end
			for _, a in Progression.Achievements do
				need(a.titleKey)
				need("title." .. a.id)
			end
			for _, step in Progression.TutorialSteps do
				need("tutorial." .. step.id)
			end
			for _, r in Balance.Ranks do
				need("rank." .. r.id)
			end
			for id in Monetization.Cosmetics do
				need("cosmetic." .. id)
			end
			for _, tier in { "none", "minority", "board", "control", "full" } do
				need("tier." .. tier)
			end
		end)

		t:test("CADA código de error que puede emitir el servidor tiene mensaje en ambos idiomas", function()
			-- Los códigos del ciclo de vida de la sesión (carga/guardado/bloqueo) NUNCA llegan al cliente
			-- como respuesta de una acción: terminan en una expulsión con mensaje propio en Main.server
			-- (se comprueba aparte). El resto de códigos sí se traducen en la interfaz.
			local lifecycleFiles =
				{ ["src/server/Core/ProfileStore.luau"] = true, ["src/server/Core/PlayerData.luau"] = true }
			local lifecycleCodes = { ALREADY_JOINED = true, LEFT_DURING_LOAD = true }
			local files = {}
			for _, f in walk("src/server", {}) do
				if not lifecycleFiles[f] then
					table.insert(files, f)
				end
			end
			for _, f in walk("src/shared", {}) do
				table.insert(files, f)
			end
			local codes = {}
			for _, path in files do
				local source = fs.readFile(path)
				for code in source:gmatch('Result%.err%("([A-Z_]+)"') do
					codes[code] = path
				end
				for code in source:gmatch('fail%("([A-Z_]+)"') do
					codes[code] = path
				end
				for code in source:gmatch('code = "([A-Z_]+)"') do
					codes[code] = path
				end
			end
			-- Códigos del cliente (red) que también se traducen.
			for _, c in { "TIMEOUT", "NETWORK", "BAD_REQUEST", "RATE_LIMITED", "NOT_READY", "INTERNAL" } do
				codes[c] = "cliente"
			end
			local checked = 0
			local missing = {}
			for code, where in codes do
				checked += 1
				if lifecycleCodes[code] then
					continue
				end
				if not (Locale.has("es", "err." .. code) and Locale.has("en", "err." .. code)) then
					table.insert(missing, code .. " (" .. where .. ")")
				end
			end
			table.sort(missing)
			if #missing > 0 then
				error("códigos de error sin mensaje: " .. table.concat(missing, ", "))
			end
			t:expect(checked > 40):toBe(true)
		end)

		t:test("las expulsiones técnicas de Main.server tienen mensaje bilingüe", function()
			local source = fs.readFile("src/server/Main.server.luau")
			for _, code in { "SESSION_LOCKED", "LOAD_FAILED", "DATA_FROM_FUTURE", "DATA_LOCK_LOST", "ABUSE" } do
				local line = source:match(code .. ' = "([^"]+)"')
				t:expect(line ~= nil):toBe(true)
				t:expect(line):toContain("\\n") -- español + inglés en el mismo mensaje
			end
		end)

		t:test("CADA tipo de notificación que envía el servidor tiene texto", function()
			local kinds = {}
			for _, path in walk("src/server", {}) do
				local source = fs.readFile(path)
				for kind in source:gmatch(':notify%([^,\n]+,%s*"([a-z_]+)"') do
					kinds[kind] = path
				end
			end
			local checked = 0
			local missing = {}
			for kind, where in kinds do
				checked += 1
				if not (Locale.has("es", "notify." .. kind) and Locale.has("en", "notify." .. kind)) then
					table.insert(missing, kind .. " (" .. where .. ")")
				end
			end
			if #missing > 0 then
				error("notificaciones sin texto: " .. table.concat(missing, ", "))
			end
			t:expect(checked > 15):toBe(true)
		end)

		t:test("los efectos públicos (banners) tienen texto", function()
			for _, kind in { "takeover", "deal", "new_number_one", "new_magnate" } do
				t:expect(Locale.has("es", "fx." .. kind) and Locale.has("en", "fx." .. kind)):toBe(true)
			end
		end)

		t:test("los textos se pueden formatear con cantidades reales sin romperse", function()
			local msg = Locale.t("es", "notify.offer_received", {
				from = "Ana",
				company = "Nova Market Co.",
				bps = Format.bps(3000, "es"),
				price = Format.cash(3000, "es"),
			})
			t:expect(msg):toBe("Ana te ofrece comprar 30 % de Nova Market Co. por 3,00 K $")
		end)
	end)
end
