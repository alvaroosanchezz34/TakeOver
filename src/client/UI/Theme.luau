--!nonstrict
--[[
	Lenguaje visual de TAKEOVER: oscuro, limpio y de alto contraste (texto ≥ 4,5:1 sobre las
	superficies), acento cian "futurista", dinero en dorado, ganancias en verde.
]]

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local Theme = {
	colors = {
		bg = rgb(12, 15, 26),
		surface = rgb(23, 28, 45),
		surface2 = rgb(33, 40, 63),
		surface3 = rgb(44, 53, 82),
		stroke = rgb(58, 69, 100),
		text = rgb(241, 244, 251),
		textDim = rgb(165, 174, 198),
		accent = rgb(64, 212, 255),
		accentDark = rgb(22, 128, 165),
		gold = rgb(255, 202, 84),
		green = rgb(86, 224, 146),
		red = rgb(255, 100, 100),
		warn = rgb(255, 172, 72),
		white = rgb(255, 255, 255),
		black = rgb(0, 0, 0),
		sector = {
			commerce = rgb(255, 170, 60),
			tech = rgb(80, 200, 255),
			industry = rgb(190, 110, 255),
		},
	},

	fonts = {
		title = Enum.Font.GothamBold,
		body = Enum.Font.GothamMedium,
		light = Enum.Font.Gotham,
	},

	sizes = {
		-- Tamaño táctil mínimo recomendado: 44-48 px. Nada interactivo baja de aquí.
		touch = 48,
		radius = 12,
		pad = 12,
		gap = 8,
		text = 16,
		textSmall = 13,
		textBig = 22,
		title = 26,
		hero = 34,
	},

	badges = {
		startup = "🌱",
		entrepreneur = "💼",
		executive = "📈",
		magnate = "💎",
		tycoon = "👑",
	},
	sectorIcons = { commerce = "🏪", tech = "💻", industry = "🏭" },

	-- Efectos de sonido: recursos propios del cliente de Roblox. Si alguno no existiera en tu
	-- versión, simplemente no suena (cámbialos por assets propios cuando los tengas).
	sounds = {
		click = "rbxasset://sounds/button.wav",
		buy = "rbxasset://sounds/electronicpingshort.wav",
		cash = "rbxasset://sounds/switch.wav",
		deal = "rbxasset://sounds/victory.wav",
		error = "rbxasset://sounds/snap.mp3",
		notify = "rbxasset://sounds/electronicpingshort.wav",
	},
}

return Theme
