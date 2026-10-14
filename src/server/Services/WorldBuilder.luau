--!nonstrict
--[[
	Constructor del distrito empresarial. TODO se genera por código (sin modelos externos ni
	assets de terceros): plaza central, edificio del mercado, 12 parcelas orientadas a la plaza,
	tableros de clasificación, iluminación y señalización. Los edificios de cada empresa
	evolucionan visualmente con su etapa (ver Shared/BuildingSpec).

	Rendimiento: ~2 000 piezas ancladas y sin colisión en los detalles; los edificios sólo se
	reconstruyen cuando cambia su firma (sector, etapa, nombre, logotipo, gestor).
]]

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local BuildingSpec = require(Shared.BuildingSpec)
local Company = require(Shared.Economy.Company)
local Cosmetics = require(Shared.Config.Cosmetics)
local Format = require(Shared.Util.Format)
local Ownership = require(Shared.Economy.Ownership)
local Sectors = require(Shared.Config.Sectors)

local PLOT_COUNT = 12
local PLOT_RADIUS = 150
local LOT_X = { -22, 0, 22 }
local BADGES =
	{ startup = "🌱", entrepreneur = "💼", executive = "📈", magnate = "💎", tycoon = "👑" }

local WorldBuilder = {}
WorldBuilder.__index = WorldBuilder

-- ───────────── utilidades ─────────────

local function rgb(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function material(name)
	local ok, value = pcall(function()
		return Enum.Material[name]
	end)
	return ok and value or Enum.Material.SmoothPlastic
end

local function newPart(parent, props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = props.castShadow ~= false
	for k, v in props do
		if k ~= "castShadow" then
			part[k] = v
		end
	end
	part.Parent = parent
	return part
end

local function addLabel(parent, text, props)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = text
	for k, v in props or {} do
		label[k] = v
	end
	label.Parent = parent
	return label
end

local function surfaceSign(part, face, lines)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = part
	local labels = {}
	local rows = #lines
	for i, line in lines do
		labels[i] = addLabel(gui, line.text, {
			Size = UDim2.fromScale(1, (line.height or 1 / rows)),
			Position = UDim2.fromScale(0, (line.y or (i - 1) / rows)),
			TextColor3 = line.color or Color3.fromRGB(255, 255, 255),
			TextXAlignment = line.align or Enum.TextXAlignment.Center,
		})
	end
	return gui, labels
end

-- ───────────── construcción del mundo ─────────────

function WorldBuilder.new()
	return setmetatable({
		plots = {},
		plotOf = {},
		boards = {},
		_boardsFor = nil,
		_presence = {},
	}, WorldBuilder)
end

function WorldBuilder:_setupLighting()
	Lighting.ClockTime = 17.6
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(70, 70, 92)
	Lighting.OutdoorAmbient = Color3.fromRGB(95, 95, 125)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.5

	local function ensure(className, name)
		local obj = Lighting:FindFirstChild(name)
		if obj == nil then
			obj = Instance.new(className)
			obj.Name = name
			obj.Parent = Lighting
		end
		return obj
	end
	local atm = ensure("Atmosphere", "TakeoverAtmosphere")
	atm.Density = 0.28
	atm.Offset = 0.25
	atm.Color = Color3.fromRGB(195, 175, 205)
	atm.Decay = Color3.fromRGB(110, 70, 95)
	atm.Glare = 0.3
	atm.Haze = 1.2
	local bloom = ensure("BloomEffect", "TakeoverBloom")
	bloom.Intensity = 0.55
	bloom.Size = 24
	bloom.Threshold = 1.1
	local cc = ensure("ColorCorrectionEffect", "TakeoverGrade")
	cc.Saturation = 0.12
	cc.Contrast = 0.08
	cc.TintColor = Color3.fromRGB(255, 244, 235)
	local rays = ensure("SunRaysEffect", "TakeoverRays")
	rays.Intensity = 0.08
	rays.Spread = 0.6
end

function WorldBuilder:_buildPlaza(root)
	local ground = newPart(root, {
		Name = "Suelo",
		Size = Vector3.new(440, 1, 440),
		Position = Vector3.new(0, -0.5, 0),
		Color = Color3.fromRGB(44, 46, 56),
		Material = Enum.Material.Concrete,
		castShadow = false,
	})
	ground.Name = "Suelo"

	-- Plaza circular de mármol
	local plaza = newPart(root, {
		Name = "Plaza",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 96, 96),
		CFrame = CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(205, 200, 210),
		Material = Enum.Material.Marble,
		castShadow = false,
	})
	plaza.Name = "Plaza"

	-- Fuente / obelisco central con el nombre del juego (visible desde cualquier lado)
	newPart(root, {
		Name = "FuenteBase",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.5, 16, 16),
		CFrame = CFrame.new(0, 0.9, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(70, 74, 90),
		Material = Enum.Material.Concrete,
	})
	newPart(root, {
		Name = "FuenteAgua",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 13, 13),
		CFrame = CFrame.new(0, 1.7, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(70, 190, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
	})
	local obelisk = newPart(root, {
		Name = "Obelisco",
		Size = Vector3.new(4, 26, 4),
		Position = Vector3.new(0, 14, 0),
		Color = Color3.fromRGB(18, 20, 28),
		Material = Enum.Material.Metal,
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
		surfaceSign(obelisk, face, {
			{ text = "TAKEOVER", y = 0.22, height = 0.2, color = Color3.fromRGB(80, 220, 255) },
			{
				text = "Build · Buy · Dominate",
				y = 0.42,
				height = 0.07,
				color = Color3.fromRGB(255, 200, 90),
			},
		})
	end
	newPart(root, {
		Name = "ObeliscoLuz",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3, 3, 3),
		Position = Vector3.new(0, 28.5, 0),
		Color = Color3.fromRGB(80, 220, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})

	-- Punto de aparición neutral (antes de que el perfil cargue y se asigne parcela)
	local plazaSpawn = Instance.new("SpawnLocation")
	plazaSpawn.Name = "SpawnPlaza"
	plazaSpawn.Anchored = true
	plazaSpawn.Size = Vector3.new(10, 0.4, 10)
	plazaSpawn.Position = Vector3.new(0, 0.8, 30)
	plazaSpawn.Neutral = true
	plazaSpawn.Duration = 0
	plazaSpawn.Transparency = 0.7
	plazaSpawn.Color = Color3.fromRGB(80, 220, 255)
	plazaSpawn.Material = Enum.Material.Neon
	plazaSpawn.CanCollide = false
	plazaSpawn.Parent = root

	-- Farolas alrededor de la plaza
	for i = 1, 8 do
		local a = (i - 1) / 8 * math.pi * 2
		local x, z = math.cos(a) * 44, math.sin(a) * 44
		newPart(root, {
			Name = "Farola" .. i,
			Size = Vector3.new(0.6, 9, 0.6),
			Position = Vector3.new(x, 4.5, z),
			Color = Color3.fromRGB(30, 32, 40),
			Material = Enum.Material.Metal,
			CanCollide = false,
		})
		local lamp = newPart(root, {
			Name = "Lampara" .. i,
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.6, 1.6, 1.6),
			Position = Vector3.new(x, 9.4, z),
			Color = Color3.fromRGB(255, 220, 150),
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		local light = Instance.new("PointLight")
		light.Brightness = 1.6
		light.Range = 26
		light.Color = Color3.fromRGB(255, 214, 150)
		light.Parent = lamp
	end

	-- Skyline lejano (decoración fija, sin colisión)
	local rng = Random.new(7)
	for i = 1, 24 do
		local a = (i - 1) / 24 * math.pi * 2
		local r = 225 + rng:NextNumber() * 10
		local h = 30 + rng:NextNumber() * 80
		newPart(root, {
			Name = "Skyline" .. i,
			Size = Vector3.new(14 + rng:NextNumber() * 10, h, 14 + rng:NextNumber() * 10),
			Position = Vector3.new(math.cos(a) * r, h / 2, math.sin(a) * r),
			Color = Color3.fromRGB(30 + (i % 3) * 8, 36 + (i % 4) * 6, 52),
			Material = Enum.Material.Glass,
			Transparency = 0.1,
			CanCollide = false,
			castShadow = false,
		})
	end
end

function WorldBuilder:_buildMarket(root)
	local model = Instance.new("Model")
	model.Name = "Mercado"
	model.Parent = root
	local z = -88
	newPart(model, {
		Name = "Cimiento",
		Size = Vector3.new(76, 1, 44),
		Position = Vector3.new(0, 0.5, z),
		Color = Color3.fromRGB(60, 62, 74),
		Material = Enum.Material.Concrete,
	})
	newPart(model, {
		Name = "Cuerpo",
		Size = Vector3.new(70, 28, 38),
		Position = Vector3.new(0, 15, z),
		Color = Color3.fromRGB(34, 38, 52),
		Material = Enum.Material.Metal,
	})
	newPart(model, {
		Name = "Cristalera",
		Size = Vector3.new(56, 18, 0.5),
		Position = Vector3.new(0, 11, z + 19.1),
		Color = Color3.fromRGB(120, 200, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.4,
		CanCollide = false,
	})
	newPart(model, {
		Name = "Marquesina",
		Size = Vector3.new(60, 0.8, 8),
		Position = Vector3.new(0, 20.5, z + 23),
		Color = Color3.fromRGB(255, 190, 70),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	local sign = newPart(model, {
		Name = "Letrero",
		Size = Vector3.new(50, 7, 1),
		Position = Vector3.new(0, 25, z + 19.2),
		Color = Color3.fromRGB(14, 16, 24),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	surfaceSign(sign, Enum.NormalId.Front, {
		{ text = "MERCADO · MARKET", y = 0.08, height = 0.84, color = Color3.fromRGB(255, 205, 90) },
	})
	-- Pasarela hasta la plaza y señalización
	newPart(model, {
		Name = "Pasarela",
		Size = Vector3.new(16, 0.2, 40),
		Position = Vector3.new(0, 0.1, z + 42),
		Color = Color3.fromRGB(90, 94, 110),
		Material = Enum.Material.Slate,
		CanCollide = false,
		castShadow = false,
	})
end

function WorldBuilder:_buildBoard(root, name, position, lookAt, title)
	local board = newPart(root, {
		Name = name,
		Size = Vector3.new(22, 15, 1),
		CFrame = CFrame.lookAt(position, lookAt),
		Color = Color3.fromRGB(12, 14, 22),
		Material = Enum.Material.SmoothPlastic,
	})
	board.CFrame = CFrame.lookAt(position, lookAt) * CFrame.Angles(0, math.pi, 0)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = board

	addLabel(gui, title, {
		Size = UDim2.fromScale(1, 0.11),
		TextColor3 = Color3.fromRGB(255, 205, 90),
	})
	local rows = {}
	for i = 1, 10 do
		rows[i] = addLabel(gui, "", {
			Size = UDim2.fromScale(0.94, 0.08),
			Position = UDim2.fromScale(0.03, 0.12 + (i - 1) * 0.088),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(235, 238, 245),
			Font = Enum.Font.GothamMedium,
		})
	end
	-- Postes
	for _, dx in { -9, 9 } do
		newPart(root, {
			Name = name .. "Poste",
			Size = Vector3.new(0.8, 9, 0.8),
			CFrame = CFrame.lookAt(position, lookAt) * CFrame.new(dx, -8, 0.8),
			Color = Color3.fromRGB(40, 42, 52),
			Material = Enum.Material.Metal,
			CanCollide = false,
		})
	end
	self.boards[name] = rows
end

function WorldBuilder:_buildPlots(root)
	local center = Vector3.new(0, 0, 0)
	for i = 1, PLOT_COUNT do
		local angle = (i - 1) / PLOT_COUNT * math.pi * 2 + math.pi / PLOT_COUNT
		local pos = Vector3.new(math.cos(angle) * PLOT_RADIUS, 0, math.sin(angle) * PLOT_RADIUS)
		-- +Z local mira a la plaza: así las fachadas de BuildingSpec dan a ella.
		local cf = CFrame.lookAt(pos, center) * CFrame.Angles(0, math.pi, 0)

		local model = Instance.new("Model")
		model.Name = "Parcela" .. i
		model.Parent = root

		newPart(model, {
			Name = "Base",
			Size = Vector3.new(68, 1, 32),
			CFrame = cf * CFrame.new(0, 0.5, 0),
			Color = Color3.fromRGB(70, 74, 88),
			Material = Enum.Material.Slate,
			castShadow = false,
		})
		newPart(model, {
			Name = "Borde",
			Size = Vector3.new(68, 0.3, 0.8),
			CFrame = cf * CFrame.new(0, 1.15, 15.6),
			Color = Color3.fromRGB(80, 220, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
			castShadow = false,
		})

		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "Spawn"
		spawn.Anchored = true
		spawn.Size = Vector3.new(6, 0.4, 6)
		spawn.CFrame = cf * CFrame.new(0, 1.2, 12)
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Transparency = 0.6
		spawn.Color = Color3.fromRGB(80, 220, 255)
		spawn.Material = Enum.Material.Neon
		spawn.CanCollide = false
		spawn.Parent = model

		-- Cartel de la parcela
		local post = newPart(model, {
			Name = "Cartel",
			Size = Vector3.new(14, 3, 0.5),
			CFrame = cf * CFrame.new(-26, 4.5, 13.5),
			Color = Color3.fromRGB(14, 16, 24),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
		local _, labels = surfaceSign(post, Enum.NormalId.Front, {
			{ text = "PARCELA " .. i, y = 0.0, height = 0.38, color = Color3.fromRGB(150, 160, 180) },
			{ text = "LIBRE", y = 0.38, height = 0.6, color = Color3.fromRGB(255, 255, 255) },
		})

		local lots = {}
		for k = 1, #LOT_X do
			lots[k] = { cf = cf * CFrame.new(LOT_X[k], 1, -3), model = nil, sig = nil, tier = 0 }
		end
		self.plots[i] = {
			index = i,
			model = model,
			cf = cf,
			spawn = spawn,
			owner = nil,
			lots = lots,
			label = labels[2],
			title = labels[1],
		}
	end
end

function WorldBuilder:build()
	local old = Workspace:FindFirstChild("TakeoverWorld")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "TakeoverWorld"
	root.Parent = Workspace
	self.root = root

	self:_setupLighting()
	self:_buildPlaza(root)
	self:_buildMarket(root)
	self:_buildBoard(
		root,
		"TableroEmpresas",
		Vector3.new(-40, 12, 26),
		Vector3.new(0, 8, 0),
		"🏢  TOP EMPRESAS"
	)
	self:_buildBoard(
		root,
		"TableroMagnates",
		Vector3.new(40, 12, 26),
		Vector3.new(0, 8, 0),
		"💰  TOP MAGNATES"
	)
	self:_buildPlots(root)

	-- Cartel de dirección hacia el mercado y las parcelas
	local signpost = newPart(root, {
		Name = "Indicador",
		Size = Vector3.new(14, 3, 0.5),
		CFrame = CFrame.lookAt(Vector3.new(0, 4, -40), Vector3.new(0, 4, 0)) * CFrame.Angles(0, math.pi, 0),
		Color = Color3.fromRGB(14, 16, 24),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	surfaceSign(
		signpost,
		Enum.NormalId.Front,
		{ { text = "MERCADO ▲", color = Color3.fromRGB(255, 205, 90) } }
	)
	return root
end

-- ───────────── parcelas y edificios ─────────────

function WorldBuilder:assignPlot(player, session)
	local existing = self.plotOf[player.UserId]
	if existing then
		return self.plots[existing]
	end
	for i, plot in self.plots do
		if plot.owner == nil then
			plot.owner = player.UserId
			self.plotOf[player.UserId] = i
			plot.label.Text = string.upper(session.name)
			plot.title.Text = "PARCELA " .. i
			player.RespawnLocation = plot.spawn
			return plot
		end
	end
	return nil -- servidor lleno de parcelas: se puede jugar igualmente
end

function WorldBuilder:teleportToPlot(player)
	local plot = self.plots[self.plotOf[player.UserId] or 0]
	local character = player.Character
	if plot and character then
		character:PivotTo(plot.spawn.CFrame + Vector3.new(0, 4, 0))
	end
end

function WorldBuilder:releasePlot(userId)
	local index = self.plotOf[userId]
	if index == nil then
		return
	end
	local plot = self.plots[index]
	for _, lot in plot.lots do
		if lot.model then
			lot.model:Destroy()
		end
		lot.model, lot.sig, lot.tier = nil, nil, 0
	end
	plot.owner = nil
	plot.label.Text = "LIBRE"
	self.plotOf[userId] = nil
end

local function pulse(root, cf, color)
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.4, 6, 6)
	ring.CFrame = cf * CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.2
	ring.Parent = root
	TweenService:Create(ring, TweenInfo.new(0.9), { Size = Vector3.new(0.4, 32, 32), Transparency = 1 })
		:Play()
	Debris:AddItem(ring, 1.2)
end

function WorldBuilder:_buildCompany(plot, lot, company, managerName)
	if lot.model then
		lot.model:Destroy()
	end
	local sector = Sectors.byId[company.sector]
	local tier = Company.visualTier(company)
	local color = sector.color
	local spec = BuildingSpec.build(company.sector, tier, color)

	local model = Instance.new("Model")
	model.Name = "Empresa_" .. company.id
	model.Parent = plot.model

	for _, p in spec.parts do
		local shape = Enum.PartType.Block
		local size = Vector3.new(p.size[1], p.size[2], p.size[3])
		local rotation = CFrame.new()
		if p.shape == "Ball" then
			shape = Enum.PartType.Ball
		elseif p.shape == "Cylinder" then
			shape = Enum.PartType.Cylinder
			size = Vector3.new(p.size[2], p.size[1], p.size[3]) -- eje vertical
			rotation = CFrame.Angles(0, 0, math.rad(90))
		end
		local part = newPart(model, {
			Name = p.name,
			Shape = shape,
			Size = size,
			CFrame = lot.cf * CFrame.new(p.pos[1], p.pos[2], p.pos[3]) * rotation,
			Color = rgb(p.color),
			Material = material(p.material),
			Transparency = p.transparency or 0,
			CanCollide = p.collide,
			castShadow = p.role ~= "neon" and p.role ~= "smoke",
		})
		if p.role == "neon" then
			local light = Instance.new("PointLight")
			light.Color = rgb(p.color)
			light.Brightness = 0.6
			light.Range = 10
			light.Parent = part
		elseif p.role == "smoke" then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Rate = 3 + tier
			emitter.Lifetime = NumberRange.new(2.5, 4)
			emitter.Speed = NumberRange.new(2, 4)
			emitter.Size = NumberSequence.new(1.2)
			emitter.Transparency = NumberSequence.new(0.5)
			emitter.Color = ColorSequence.new(Color3.fromRGB(190, 190, 195))
			emitter.Parent = part
		end
	end

	-- Placa con logotipo, nombre y propietario
	local sign = newPart(model, {
		Name = "Letrero",
		Size = Vector3.new(spec.signSize[1], spec.signSize[2], spec.signSize[3]),
		CFrame = lot.cf * CFrame.new(spec.signPos[1], spec.signPos[2], spec.signPos[3]),
		Color = Color3.fromRGB(14, 16, 24),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	local logoColor = Cosmetics.LogoColors[company.logo.color] or color
	local logo = Cosmetics.LogoIcons[company.logo.icon] or "⭐"
	local owner = if managerName ~= nil and managerName ~= "" then ("Gestiona: " .. managerName) else ""
	surfaceSign(sign, Enum.NormalId.Front, {
		{ text = logo .. " " .. company.name, y = 0.02, height = 0.62, color = rgb(logoColor) },
		{ text = owner, y = 0.66, height = 0.3, color = Color3.fromRGB(190, 195, 210) },
	})
	lot.model = model
	return tier
end

function WorldBuilder:_syncPlots(server)
	local world = server.world
	for userId, index in self.plotOf do
		local session = world.sessions[tostring(userId)]
		local plot = self.plots[index]
		if session then
			local owned = {}
			for _, company in session.data.companies do
				if company.founderId == session.id then
					table.insert(owned, company)
				end
			end
			table.sort(owned, function(a, b)
				return a.id < b.id
			end)
			for k, lot in plot.lots do
				local company = owned[k]
				if company == nil then
					if lot.model then
						lot.model:Destroy()
						lot.model, lot.sig, lot.tier = nil, nil, 0
					end
				else
					local manager = Ownership.manager(company.cap, company.founderId)
					local managerName = ""
					if manager ~= company.founderId then
						local m = world.sessions[manager]
						managerName = m and m.name or (company.names and company.names[manager]) or ""
					end
					local tier = Company.visualTier(company)
					local sig = table.concat({
						company.sector,
						tier,
						company.name,
						company.logo.icon,
						company.logo.color,
						managerName,
					}, "|")
					if lot.sig ~= sig then
						local previous = lot.tier
						local newTier = self:_buildCompany(plot, lot, company, managerName)
						lot.sig, lot.tier = sig, newTier
						if previous > 0 and newTier > previous then
							pulse(self.root, lot.cf, rgb(Sectors.byId[company.sector].color))
						end
					end
				end
			end
		end
	end
end

-- ───────────── tableros e insignias ─────────────

function WorldBuilder:_syncBoards(server)
	local r = server.rankings
	if r == nil or r == self._boardsFor then
		return
	end
	self._boardsFor = r
	local companyRows = self.boards["TableroEmpresas"]
	local playerRows = self.boards["TableroMagnates"]
	for i = 1, 10 do
		local c = r.companies[i]
		local p = r.players[i]
		if companyRows then
			companyRows[i].Text = if c
				then string.format(
					"%d. %s  %s  —  %s",
					i,
					Sectors.byId[c.sector].icon,
					c.name,
					Format.cash(c.valuation, "en")
				)
				else ""
		end
		if playerRows then
			playerRows[i].Text = if p
				then string.format(
					"%d. %s %s  —  %s",
					i,
					BADGES[p.badge] or "",
					p.name,
					Format.cash(p.netWorth, "en")
				)
				else ""
		end
	end
end

-- Insignia sobre la cabeza: emoji de posición + nombre (corona para el nº 1).
function WorldBuilder:_syncPresence(server)
	local r = server.rankings
	for _, player in game:GetService("Players"):GetPlayers() do
		local session = server.world.sessions[tostring(player.UserId)]
		local pos = session and r and r.positions[session.id]
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		if session and pos and head then
			local text = (BADGES[pos.badge] or "") .. " " .. session.name
			if pos.playerRank == 1 and pos.playerCount >= 2 then
				text = "👑 " .. text
			end
			local gui = head:FindFirstChild("TakeoverTag")
			if gui == nil then
				gui = Instance.new("BillboardGui")
				gui.Name = "TakeoverTag"
				gui.Size = UDim2.fromOffset(220, 34)
				gui.StudsOffset = Vector3.new(0, 2.6, 0)
				gui.AlwaysOnTop = false
				gui.MaxDistance = 90
				gui.Parent = head
				local label = addLabel(gui, text, { Name = "Text", TextStrokeTransparency = 0.4 })
				label.TextSize = 18
			end
			local label = gui:FindFirstChild("Text")
			if label and label.Text ~= text then
				label.Text = text
			end
		end
	end
end

-- Llamar una vez por segundo.
function WorldBuilder:update(server)
	local ok, err = pcall(function()
		self:_syncPlots(server)
		self:_syncBoards(server)
		self:_syncPresence(server)
	end)
	if not ok then
		warn("[WorldBuilder] " .. tostring(err))
	end
end

return WorldBuilder
