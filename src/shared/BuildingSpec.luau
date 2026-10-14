--!strict
--[[
	Especificación de los edificios de empresa como DATOS (sin Instances): lista de piezas con
	tamaño, posición relativa al centro de la parcela, color y material. Así la forma de cada
	sector y su evolución se puede probar sin Roblox, y el constructor de mundo sólo crea piezas.

	Cada empresa evoluciona visualmente con su etapa (1..10 = nivel + mejoras de aspecto):
	  commerce  kiosco -> tienda -> supermercado -> centro comercial (ancho y bajo, cálido)
	  tech      torre de cristal que crece, neón, antena, anillo y holograma (alto, futurista)
	  industry  nave -> fábrica con chimeneas, silos y cintas (pesado, humeante)

	Convenciones: (0,0,0) = centro de la parcela a nivel del suelo; +Y arriba; la FACHADA mira a +Z.
	Un "Cylinder" tiene size = { diámetro, ALTURA, diámetro } con eje VERTICAL (el constructor lo orienta).
	(el constructor orienta la parcela hacia la plaza). La parcela mide LOT_SIZE × LOT_SIZE.
]]

export type Part = {
	name: string,
	shape: string, -- "Block" | "Cylinder" | "Ball"
	size: { number },
	pos: { number }, -- centro de la pieza respecto al centro de la parcela
	color: { number },
	material: string,
	transparency: number?,
	collide: boolean,
	role: string, -- "body" | "glass" | "neon" | "roof" | "detail" | "smoke" | "sign"
}

export type Spec = {
	parts: { Part },
	signPos: { number }, -- centro de la placa con el nombre
	signSize: { number },
	height: number,
}

local BuildingSpec = {}

BuildingSpec.LOT_SIZE = 20
BuildingSpec.MAX_TIER = 10
BuildingSpec.MAX_PARTS = 90

local function shade(c: { number }, f: number): { number }
	return {
		math.clamp(math.floor(c[1] * f), 0, 255),
		math.clamp(math.floor(c[2] * f), 0, 255),
		math.clamp(math.floor(c[3] * f), 0, 255),
	}
end

local function add(list: { Part }, p: Part)
	table.insert(list, p)
end

local function block(
	name: string,
	sx: number,
	sy: number,
	sz: number,
	x: number,
	y: number,
	z: number,
	color: { number },
	material: string,
	role: string,
	opts: { transparency: number?, collide: boolean?, shape: string? }?
): Part
	return {
		name = name,
		shape = opts and opts.shape or "Block",
		size = { sx, sy, sz },
		pos = { x, y, z },
		color = color,
		material = material,
		transparency = opts and opts.transparency,
		collide = if opts and opts.collide ~= nil then opts.collide else true,
		role = role,
	}
end

local function commerce(tier: number, color: { number }): Spec
	local parts: { Part } = {}
	local floors = 1 + (tier - 1) // 4 -- 1..3
	local w = math.min(14, 8 + tier * 1.0) -- ≤ 14 para dejar sitio al anexo dentro de la parcela
	local d = math.min(16, 8 + tier * 0.8)
	local fh = 5
	local h = floors * fh

	add(parts, block("Cimiento", w + 1, 0.5, d + 1, 0, 0.25, 0, shade(color, 0.35), "Concrete", "body"))
	add(parts, block("Cuerpo", w, h, d, 0, 0.5 + h / 2, 0, shade(color, 0.9), "Brick", "body"))
	add(
		parts,
		block("Tejado", w + 0.8, 0.6, d + 0.8, 0, 0.5 + h + 0.3, 0, shade(color, 0.5), "Concrete", "roof")
	)
	-- escaparate de cristal en la fachada
	add(
		parts,
		block(
			"Escaparate",
			w - 2,
			fh - 1.5,
			0.3,
			0,
			0.5 + (fh - 1.5) / 2 + 0.3,
			d / 2 + 0.05,
			{ 160, 220, 255 },
			"Glass",
			"glass",
			{ transparency = 0.45 }
		)
	)
	-- toldo
	add(
		parts,
		block(
			"Toldo",
			w - 1,
			0.35,
			2.2,
			0,
			0.5 + fh - 0.5,
			d / 2 + 1.1,
			color,
			"Fabric",
			"detail",
			{ collide = false }
		)
	)
	for f = 2, floors do
		add(
			parts,
			block(
				"Ventanas" .. f,
				w - 2,
				1.8,
				0.3,
				0,
				0.5 + (f - 1) * fh + 2.6,
				d / 2 + 0.05,
				{ 160, 220, 255 },
				"Glass",
				"glass",
				{ transparency = 0.4 }
			)
		)
	end
	if tier >= 4 then
		add(parts, block("Anexo", 4, 4, d - 2, -(w / 2 + 2), 2.5, 0, shade(color, 0.75), "Brick", "body"))
	end
	if tier >= 6 then
		add(
			parts,
			block(
				"Cartel",
				4,
				3,
				0.4,
				w / 2 - 2,
				h + 2.6,
				d / 2 - 1,
				color,
				"Neon",
				"neon",
				{ collide = false }
			)
		)
		add(
			parts,
			block(
				"Poste",
				0.5,
				2.2,
				0.5,
				w / 2 - 2,
				h + 1.6,
				d / 2 - 1,
				{ 60, 60, 66 },
				"Metal",
				"detail",
				{ collide = false }
			)
		)
	end
	if tier >= 8 then
		add(
			parts,
			block(
				"Atrio",
				6,
				h + 4,
				6,
				w / 2 - 3,
				0.5 + (h + 4) / 2,
				-d / 2 + 3,
				{ 160, 220, 255 },
				"Glass",
				"glass",
				{ transparency = 0.5 }
			)
		)
	end
	if tier >= 9 then
		for i = -2, 2 do
			add(
				parts,
				block(
					"Farola" .. i,
					0.4,
					3.5,
					0.4,
					i * 3.4,
					1.75,
					d / 2 + 3.6,
					{ 70, 70, 78 },
					"Metal",
					"detail",
					{ collide = false }
				)
			)
		end
	end
	return {
		parts = parts,
		signPos = { 0, 0.5 + h + 1.9, d / 2 + 0.2 },
		signSize = { math.min(w, 14), 2.6, 0.3 },
		height = h + 1,
	}
end

local function tech(tier: number, color: { number }): Spec
	local parts: { Part } = {}
	local floors = 2 + tier -- 3..12
	local fh = 4
	local baseW = math.min(12, 7 + tier * 0.5)
	add(parts, block("Cimiento", baseW + 3, 0.5, baseW + 3, 0, 0.25, 0, { 30, 34, 44 }, "Concrete", "body"))
	for f = 1, floors do
		-- La torre se estrecha con la altura (aspecto de rascacielos).
		local taper = 1 - (f - 1) / (floors * 2.2)
		local w = baseW * taper
		local y = 0.5 + (f - 0.5) * fh
		add(
			parts,
			block(
				"Planta" .. f,
				w,
				fh - 0.3,
				w,
				0,
				y,
				0,
				{ 40, 56, 78 },
				"Glass",
				"glass",
				{ transparency = 0.15 }
			)
		)
		add(
			parts,
			block(
				"Banda" .. f,
				w + 0.3,
				0.3,
				w + 0.3,
				0,
				y + fh / 2 - 0.15,
				0,
				color,
				"Neon",
				"neon",
				{ collide = false }
			)
		)
	end
	local topW = baseW * (1 - (floors - 1) / (floors * 2.2))
	local topY = 0.5 + floors * fh
	add(
		parts,
		block(
			"Antena",
			0.4,
			6 + tier * 0.4,
			0.4,
			0,
			topY + 3 + tier * 0.2,
			0,
			{ 200, 205, 215 },
			"Metal",
			"detail",
			{ collide = false }
		)
	)
	add(
		parts,
		block(
			"Baliza",
			0.9,
			0.9,
			0.9,
			0,
			topY + 6 + tier * 0.4,
			0,
			{ 255, 80, 80 },
			"Neon",
			"neon",
			{ collide = false, shape = "Ball" }
		)
	)
	add(
		parts,
		block(
			"Vestibulo",
			baseW + 2,
			3.2,
			3,
			0,
			1.6 + 0.5,
			baseW / 2 + 1.2,
			{ 130, 220, 255 },
			"Glass",
			"glass",
			{ transparency = 0.35 }
		)
	)
	if tier >= 5 then
		add(
			parts,
			block(
				"Dron",
				2,
				0.4,
				2,
				baseW / 2 + 2,
				topY * 0.55,
				0,
				color,
				"Neon",
				"neon",
				{ collide = false }
			)
		)
	end
	if tier >= 6 then
		add(
			parts,
			block(
				"Anillo",
				topW * 2.4 + 4,
				0.5,
				topW * 2.4 + 4,
				0,
				topY * 0.75,
				0,
				color,
				"Neon",
				"neon",
				{ collide = false, shape = "Cylinder", transparency = 0.25 }
			)
		)
	end
	if tier >= 9 then
		add(
			parts,
			block(
				"Holograma",
				4,
				4,
				4,
				0,
				topY + 12 + tier * 0.4,
				0,
				color,
				"Neon",
				"neon",
				{ collide = false, shape = "Ball", transparency = 0.5 }
			)
		)
	end
	return {
		parts = parts,
		signPos = { 0, 6.5, baseW / 2 + 3.4 },
		signSize = { 10, 2.6, 0.3 },
		height = topY + 6,
	}
end

local function industry(tier: number, color: { number }): Spec
	local parts: { Part } = {}
	local w = math.min(14, 10 + tier * 0.5) -- los silos de la derecha deben caber en la parcela
	local d = math.min(13, 9 + tier * 0.5) -- deja sitio a la nave trasera dentro de la parcela
	local h = 6 + tier * 0.6
	add(parts, block("Cimiento", w + 1, 0.5, d + 1, 0, 0.25, 0, { 60, 60, 64 }, "Concrete", "body"))
	add(parts, block("Nave", w, h, d, 0, 0.5 + h / 2, 0, shade(color, 0.55), "Metal", "body"))
	-- tejado en dientes de sierra
	local teeth = math.max(2, math.floor(w / 4))
	for i = 1, teeth do
		local x = -w / 2 + (i - 0.5) * (w / teeth)
		add(
			parts,
			block(
				"Diente" .. i,
				w / teeth,
				1.6,
				d,
				x,
				0.5 + h + 0.8,
				0,
				shade(color, 0.7),
				"CorrodedMetal",
				"roof"
			)
		)
	end
	add(parts, block("Porton", 5, 4, 0.3, 0, 2.5, d / 2 + 0.05, { 230, 190, 60 }, "DiamondPlate", "detail"))
	add(
		parts,
		block("Franja", w, 0.6, 0.3, 0, h - 0.6, d / 2 + 0.05, color, "Neon", "neon", { collide = false })
	)

	local stacks = 1 + tier // 3 -- 1..4 chimeneas
	for i = 1, stacks do
		local x = -w / 2 + 1.5 + (i - 1) * 2.4
		local sh = 12 + i * 2
		add(
			parts,
			block(
				"Chimenea" .. i,
				1.6,
				sh,
				1.6,
				x,
				0.5 + sh / 2,
				-d / 2 + 1.5,
				{ 120, 90, 80 },
				"Brick",
				"detail",
				{ shape = "Cylinder" }
			)
		)
		add(
			parts,
			block(
				"Humo" .. i,
				0.2,
				0.2,
				0.2,
				x,
				0.5 + sh + 0.5,
				-d / 2 + 1.5,
				{ 200, 200, 200 },
				"SmoothPlastic",
				"smoke",
				{ collide = false, transparency = 1 }
			)
		)
	end
	local silos = tier // 2
	for i = 1, math.min(silos, 4) do
		add(
			parts,
			block(
				"Silo" .. i,
				3.2,
				9,
				3.2,
				w / 2 + 2.2,
				5,
				-d / 2 + 2 + (i - 1) * 3.6,
				{ 190, 195, 205 },
				"Metal",
				"detail",
				{ shape = "Cylinder" }
			)
		)
	end
	if tier >= 3 then
		add(
			parts,
			block(
				"Cinta",
				w - 2,
				0.5,
				1.2,
				0,
				1.1,
				d / 2 + 2,
				{ 50, 50, 54 },
				"Metal",
				"detail",
				{ collide = false }
			)
		)
	end
	if tier >= 8 then
		add(
			parts,
			block(
				"NaveB",
				w * 0.6,
				h * 0.8,
				d * 0.36,
				0,
				0.5 + h * 0.4,
				-d / 2 - d * 0.18,
				shade(color, 0.5),
				"Metal",
				"body"
			)
		)
	end
	return {
		parts = parts,
		signPos = { 0, h + 3.2, d / 2 + 0.2 },
		signSize = { math.min(w, 14), 2.6, 0.3 },
		height = h + 8,
	}
end

local BUILDERS: { [string]: (number, { number }) -> Spec } = {
	commerce = commerce,
	tech = tech,
	industry = industry,
}

function BuildingSpec.build(sector: string, tier: number, color: { number }): Spec
	local builder = BUILDERS[sector] or commerce
	return builder(math.clamp(math.floor(tier), 1, BuildingSpec.MAX_TIER), color)
end

return BuildingSpec
