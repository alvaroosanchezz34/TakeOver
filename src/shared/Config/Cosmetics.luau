--!strict
--[[
	Personalización SEGURA de empresas: nunca se acepta texto libre del jugador para nombres
	ni logotipos. El nombre se compone con tres elecciones de listas predefinidas
	(prefijo + núcleo del sector + sufijo) y el logotipo con un icono y un color predefinidos.
	Así no hay contenido arbitrario que moderar ni modelos generados desde texto de usuarios.
]]

local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	NamePrefixes = {
		"Nova",
		"Apex",
		"Vertex",
		"Orion",
		"Atlas",
		"Delta",
		"Zenith",
		"Pulse",
		"Lumen",
		"Quantum",
		"Titan",
		"Aurora",
	},
	NameCores = {
		commerce = { "Market", "Retail", "Bazar", "Trade", "Shop", "Mercantil" },
		tech = { "Labs", "Systems", "Data", "Cloud", "Robotics", "Net" },
		industry = { "Works", "Steel", "Foundry", "Motors", "Mining", "Plastics" },
	},
	NameSuffixes = { "Co.", "Group", "Holdings", "Corp.", "& Sons", "Partners" },

	LogoIcons = {
		"⭐",
		"🔷",
		"🔶",
		"🌀",
		"🦅",
		"🐺",
		"🦁",
		"🚀",
		"⚡",
		"🔥",
		"🌿",
		"💎",
	},
	LogoColors = {
		{ 255, 99, 99 },
		{ 255, 170, 60 },
		{ 250, 220, 80 },
		{ 110, 220, 120 },
		{ 80, 200, 255 },
		{ 110, 140, 255 },
		{ 190, 110, 255 },
		{ 240, 240, 245 },
	},
})
