--!nocheck
return function(t, load)
	local BuildingSpec = load:shared("BuildingSpec")
	local Sectors = load:shared("Config/Sectors")
	local Company = load:shared("Economy/Company")

	local function finite(n)
		return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
	end

	t:describe("Edificios (especificación pura)", function()
		t:test("todas las piezas de todos los sectores y etapas son válidas", function()
			for _, sectorId in Sectors.order do
				local color = Sectors.byId[sectorId].color
				for tier = 1, BuildingSpec.MAX_TIER do
					local spec = BuildingSpec.build(sectorId, tier, color)
					t:expect(#spec.parts > 0):toBe(true)
					t:expect(#spec.parts <= BuildingSpec.MAX_PARTS):toBe(true)
					local names = {}
					for _, p in spec.parts do
						t:expect(names[p.name]):toBeNil() -- nombres únicos dentro de un edificio
						names[p.name] = true
						for i = 1, 3 do
							t:expect(finite(p.size[i]) and p.size[i] > 0):toBe(true)
							t:expect(finite(p.pos[i])):toBe(true)
							t:expect(finite(p.color[i]) and p.color[i] >= 0 and p.color[i] <= 255):toBe(true)
						end
						t:expect(table.find({ "Block", "Cylinder", "Ball" }, p.shape) ~= nil):toBe(true)
						t:expect(type(p.material)):toBe("string")
						t:expect(type(p.collide)):toBe("boolean")
						-- nada bajo el suelo
						t:expect(p.pos[2] - p.size[2] / 2 >= -0.01):toBe(true)
					end
					t:expect(finite(spec.height) and spec.height > 0):toBe(true)
				end
			end
		end)

		t:test("cada edificio cabe en su parcela (no invade a las vecinas ni la acera)", function()
			local half = 11 -- las parcelas están a 22 studs una de otra
			for _, sectorId in Sectors.order do
				local color = Sectors.byId[sectorId].color
				for tier = 1, BuildingSpec.MAX_TIER do
					local spec = BuildingSpec.build(sectorId, tier, color)
					for _, p in spec.parts do
						local halfX = p.size[1] / 2
						local halfZ = p.size[3] / 2
						if not (p.pos[1] - halfX >= -half - 1e-6 and p.pos[1] + halfX <= half + 1e-6) then
							error(
								("%s etapa %d: la pieza %s se sale en X (%.1f..%.1f)"):format(
									sectorId,
									tier,
									p.name,
									p.pos[1] - halfX,
									p.pos[1] + halfX
								)
							)
						end
						if not (p.pos[3] - halfZ >= -12 and p.pos[3] + halfZ <= 12) then
							error(
								("%s etapa %d: la pieza %s se sale en Z (%.1f..%.1f)"):format(
									sectorId,
									tier,
									p.name,
									p.pos[3] - halfZ,
									p.pos[3] + halfZ
								)
							)
						end
					end
				end
			end
			t:expect(true):toBe(true)
		end)

		t:test("los edificios crecen con la etapa: más altos o con más piezas", function()
			for _, sectorId in Sectors.order do
				local color = Sectors.byId[sectorId].color
				local first = BuildingSpec.build(sectorId, 1, color)
				local last = BuildingSpec.build(sectorId, BuildingSpec.MAX_TIER, color)
				t:expect(#last.parts > #first.parts):toBe(true)
				t:expect(last.height >= first.height):toBe(true)
				-- monotonía débil del número de piezas
				local prev = 0
				for tier = 1, BuildingSpec.MAX_TIER do
					local n = #BuildingSpec.build(sectorId, tier, color).parts
					t:expect(n >= prev):toBe(true)
					prev = n
				end
			end
		end)

		t:test("los sectores se distinguen visualmente: formas y rasgos propios", function()
			local color = { 200, 200, 200 }
			local function has(spec, roleOrName)
				for _, p in spec.parts do
					if p.role == roleOrName or string.find(p.name, roleOrName, 1, true) then
						return true
					end
				end
				return false
			end
			local commerce = BuildingSpec.build("commerce", 5, color)
			local tech = BuildingSpec.build("tech", 5, color)
			local industry = BuildingSpec.build("industry", 5, color)
			t:expect(has(commerce, "Toldo")):toBe(true)
			t:expect(has(tech, "Antena")):toBe(true)
			t:expect(has(industry, "Chimenea")):toBe(true)
			t:expect(has(industry, "smoke")):toBe(true)
			t:expect(has(tech, "Chimenea")):toBe(false)
			t:expect(tech.height > commerce.height):toBe(true) -- la torre es más alta que la tienda
		end)

		t:test("etapas fuera de rango se acotan; sector desconocido usa un diseño por defecto", function()
			local color = { 100, 100, 100 }
			t:expect(#BuildingSpec.build("tech", -5, color).parts)
				:toBe(#BuildingSpec.build("tech", 1, color).parts)
			t:expect(#BuildingSpec.build("tech", 99, color).parts)
				:toBe(#BuildingSpec.build("tech", 10, color).parts)
			t:expect(#BuildingSpec.build("nope", 3, color).parts > 0):toBe(true)
		end)

		t:test("la placa del nombre queda dentro de la parcela", function()
			for _, sectorId in Sectors.order do
				for tier = 1, BuildingSpec.MAX_TIER do
					local spec = BuildingSpec.build(sectorId, tier, { 10, 10, 10 })
					t:expect(math.abs(spec.signPos[1]) + spec.signSize[1] / 2 <= 11):toBe(true)
					t:expect(spec.signSize[1] > 0 and spec.signSize[2] > 0):toBe(true)
				end
			end
		end)

		t:test("la etapa visual de una empresa real está en 1..10", function()
			local c = Company.new({ founderId = "1", index = 1, sector = "industry", now = 0 })
			c.level = 8
			c.upgrades.plant = 3
			local tier = Company.visualTier(c)
			t:expect(tier >= 1 and tier <= BuildingSpec.MAX_TIER):toBe(true)
		end)
	end)
end
