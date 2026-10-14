--!nocheck
return function(t, load)
	local Ownership = load:shared("Economy/Ownership")
	local Governance = load:shared("Config/Governance")
	local Balance = load:shared("Config/Balance")
	local Random = load.Random

	local function cap(holders)
		return { holders = holders, rev = 0 }
	end

	local function sum(c)
		local s = 0
		for _, v in c.holders do
			s += v
		end
		return s
	end

	t:describe("Estructura de propiedad", function()
		t:test("empresa nueva: el fundador tiene el 100 %", function()
			local c = Ownership.newCap("1")
			t:expect(c.holders["1"]):toBe(10000)
			t:expect(Ownership.validate(c)):toBe(true)
		end)

		t:test("validate detecta sumas incorrectas y valores inválidos", function()
			t:expect((Ownership.validate(cap({ a = 5000 })))):toBe(false)
			t:expect((Ownership.validate(cap({ a = 6000, b = 5000 })))):toBe(false)
			t:expect((Ownership.validate(cap({ a = 10000, b = 0 })))):toBe(false)
			t:expect((Ownership.validate(cap({ a = 5000.5, b = 4999.5 })))):toBe(false)
			t:expect((Ownership.validate(cap({ a = 10001, b = -1 })))):toBe(false)
			t:expect((Ownership.validate(cap({ [""] = 10000 })))):toBe(false)
			t:expect((Ownership.validate(cap({ a = 0 / 0 })))):toBe(false)
			t:expect((Ownership.validate(cap({ a = 5000, b = 5000 })))):toBe(true)
		end)
	end)

	t:describe("Transferencias", function()
		t:test("mueve participación y conserva el 100 %", function()
			local c = Ownership.newCap("1")
			local r = Ownership.transfer(c, "1", "2", 3000)
			t:expect(r):toBeOk()
			t:expect(c.holders["1"]):toBe(7000)
			t:expect(c.holders["2"]):toBe(3000)
			t:expect(sum(c)):toBe(10000)
			t:expect(c.rev):toBe(1)
		end)

		t:test("vender todo elimina al titular (sin entradas a cero)", function()
			local c = Ownership.newCap("1")
			Ownership.transfer(c, "1", "2", 10000)
			t:expect(c.holders["1"]):toBeNil()
			t:expect(c.holders["2"]):toBe(10000)
		end)

		t:test("no se pueden vender acciones inexistentes", function()
			local c = Ownership.newCap("1")
			t:expect(Ownership.transfer(c, "2", "1", 100)):toBeErr("INSUFFICIENT_SHARES")
			t:expect(Ownership.transfer(c, "1", "2", 10001)):toBeErr("INVALID_SHARES")
			t:expect(c.holders["1"]):toBe(10000)
			t:expect(c.rev):toBe(0)
		end)

		t:test("no se puede vender la misma participación dos veces", function()
			local c = Ownership.newCap("1")
			t:expect(Ownership.transfer(c, "1", "2", 6000)):toBeOk()
			t:expect(Ownership.transfer(c, "1", "3", 6000)):toBeErr("INSUFFICIENT_SHARES")
			t:expect(c.holders["3"]):toBeNil()
			t:expect(sum(c)):toBe(10000)
		end)

		t:test("rechaza cantidades inválidas: 0, negativas, fraccionarias, NaN", function()
			local c = Ownership.newCap("1")
			for _, bad in { 0, -100, 50.5, 0 / 0, math.huge } do
				t:expect(Ownership.transfer(c, "1", "2", bad)):toBeErr("INVALID_SHARES")
			end
			t:expect(Ownership.transfer(c, "1", "1", 100)):toBeErr("SAME_PARTIES")
			t:expect(c.holders["1"]):toBe(10000)
		end)

		t:test("FUZZ: 20 000 transferencias aleatorias nunca rompen el invariante", function()
			local rng = Random.new(2024)
			local c = Ownership.newCap("1")
			local ids = { "1", "2", "3", "4", "5", "6" }
			local accepted = 0
			for _ = 1, 20000 do
				local from = ids[rng:NextInteger(1, #ids)]
				local to = ids[rng:NextInteger(1, #ids)]
				local bps = rng:NextInteger(-50, 10500)
				local before = table.clone(c.holders)
				local r = Ownership.transfer(c, from, to, bps)
				if r.ok then
					accepted += 1
				else
					-- un fallo no debe alterar nada
					t:expect(c.holders):toEqual(before)
				end
				local ok = Ownership.validate(c)
				if not ok then
					error("invariante roto tras transferir " .. from .. "->" .. to .. " " .. bps)
				end
			end
			t:expect(accepted):toBeGreaterThan(500)
			t:expect(sum(c)):toBe(10000)
		end)
	end)

	t:describe("Gobernanza (umbrales públicos)", function()
		t:test("niveles por porcentaje en los bordes", function()
			t:expect(Ownership.tier(0)):toBe("none")
			t:expect(Ownership.tier(1)):toBe("minority")
			t:expect(Ownership.tier(2499)):toBe("minority")
			t:expect(Ownership.tier(2500)):toBe("board")
			t:expect(Ownership.tier(5000)):toBe("board")
			t:expect(Ownership.tier(5001)):toBe("control")
			t:expect(Ownership.tier(9999)):toBe("control")
			t:expect(Ownership.tier(10000)):toBe("full")
		end)

		t:test("exactamente el 50 % NO da control", function()
			local c = cap({ a = 5000, b = 5000 })
			t:expect(Ownership.controller(c)):toBeNil()
			t:expect(Ownership.manager(c, "a")):toBe("a")
			t:expect(Ownership.manager(c, "b")):toBe("b") -- sin mayoría gestiona el fundador
		end)

		t:test("más del 50 % gestiona, aunque no sea el fundador", function()
			local c = cap({ founder = 4900, buyer = 5100 })
			t:expect(Ownership.controller(c)):toBe("buyer")
			t:expect(Ownership.manager(c, "founder")):toBe("buyer")
		end)

		t:test("derechos por titular", function()
			local c = cap({ f = 6000, a = 2500, b = 1500 })
			local rf = Ownership.rights(c, "f", "f")
			local ra = Ownership.rights(c, "a", "f")
			local rb = Ownership.rights(c, "b", "f")
			t:expect(rf.manages):toBe(true)
			t:expect(ra.manages):toBe(false)
			t:expect(ra.seesBooks):toBe(true) -- consejero (≥ 25 %)
			t:expect(rb.seesBooks):toBe(false) -- minoritario
			t:expect(rb.dividends):toBe(true)
			t:expect(Ownership.rights(c, "nadie", "f").dividends):toBe(false)
		end)

		t:test("el fundador no puede quedarse sin gestor: regla del mínimo", function()
			-- f 60 % vende 45 % -> f 15 %, nadie con mayoría: gestiona f con 15 % < 20 %
			local c = cap({ f = 6000, a = 4000 })
			t:expect(Ownership.canTransfer(c, "f", "f", "b", 4500)):toBeErr("MANAGER_STAKE_TOO_LOW")
			-- vender 40 % deja f=20 % (justo el mínimo): permitido
			t:expect(Ownership.canTransfer(c, "f", "f", "b", 4000)):toBeOk()
			-- canTransfer NO modifica la estructura real
			t:expect(c.holders.f):toBe(6000)
		end)

		t:test("entregar el control a un comprador mayoritario es válido", function()
			local c = Ownership.newCap("f")
			-- f vende 80 %: comprador con 80 % gestiona; f queda con 20 %
			t:expect(Ownership.canTransfer(c, "f", "f", "b", 8000)):toBeOk()
			-- f vende 100 %: el comprador gestiona con 100 %
			t:expect(Ownership.canTransfer(c, "f", "f", "b", 10000)):toBeOk()
		end)

		t:test("un tercero no puede 'expulsar' al fundador sin comprar más del 50 %", function()
			local c = cap({ f = 5000, a = 5000 })
			-- a no tiene mayoría: no gestiona, aunque tenga el mismo 50 %
			t:expect(Ownership.manager(c, "f")):toBe("f")
			-- sólo comprando 1 bps más al fundador pasa a gestionar:
			Ownership.transfer(c, "f", "a", 100)
			t:expect(Ownership.manager(c, "f")):toBe("a")
		end)
	end)

	t:describe("Reparto de dividendos (mayor resto)", function()
		t:test("ejemplo: 100 entre 33,33/33,33/33,34 reparte exactamente 100", function()
			local c = cap({ a = 3333, b = 3333, c = 3334 })
			local out = Ownership.split(100, c)
			t:expect(out.a + out.b + out.c):toBe(100)
			t:expect(out.c >= out.a):toBe(true)
		end)

		t:test("importe 0 y 1 con muchos titulares", function()
			local c = cap({ a = 2500, b = 2500, c = 2500, d = 2500 })
			local zero = Ownership.split(0, c)
			t:expect(zero.a + zero.b + zero.c + zero.d):toBe(0)
			local one = Ownership.split(1, c)
			t:expect(one.a + one.b + one.c + one.d):toBe(1)
		end)

		t:test("es determinista (mismo resultado siempre)", function()
			local c = cap({ a = 3333, b = 3333, c = 3334 })
			t:expect(Ownership.split(7, c)):toEqual(Ownership.split(7, c))
		end)

		t:test("FUZZ: la suma repartida siempre iguala el importe", function()
			local rng = Random.new(7)
			for _ = 1, 5000 do
				-- cap aleatoria válida
				local holders = {}
				local remaining = 10000
				local n = rng:NextInteger(1, 8)
				for i = 1, n do
					local part = if i == n
						then remaining
						else rng:NextInteger(1, math.max(1, remaining - (n - i)))
					holders["h" .. i] = part
					remaining -= part
				end
				local c = cap(holders)
				if Ownership.validate(c) then
					local amount = rng:NextInteger(0, 1_000_000_000) * rng:NextInteger(1, 1000)
					local out = Ownership.split(amount, c)
					local total = 0
					for id, v in out do
						t:expect(v >= 0):toBe(true)
						total += v
						-- nunca más de lo proporcional + 1
						t:expect(v <= (amount * holders[id]) / 10000 + 1):toBe(true)
					end
					if total ~= amount then
						error(("reparto incorrecto: %d vs %d"):format(total, amount))
					end
				end
			end
		end)

		t:test("importes enormes (1e15) no pierden precisión", function()
			local c = cap({ a = 3333, b = 3333, c = 3334 })
			local out = Ownership.split(Balance.MaxCash, c)
			t:expect(out.a + out.b + out.c):toBe(Balance.MaxCash)
		end)
	end)
end
