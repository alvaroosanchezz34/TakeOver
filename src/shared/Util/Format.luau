--!strict
--[[
	Formato de cantidades para la interfaz.

	  es:  950 $ · 1,25 K $ · 3,40 M $ · 2,15 B $
	  en:  $950  · $1.25K   · $3.40M   · $2.15B

	Sólo es presentación: la economía usa números exactos (enteros) y nunca lee
	estos textos.
]]

export type Locale = "en" | "es"

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa" } -- 1e0, 1e3, 1e6, 1e9, 1e12, 1e15
local MAX_TIER = #SUFFIXES - 1

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function separator(locale: Locale?): string
	if locale == "es" then
		return ","
	end
	return "."
end

local function round2(x: number): number
	return math.floor(x * 100 + 0.5) / 100
end

-- Quita ceros finales: "1.50" -> "1.5", "2.00" -> "2".
local function trim(text: string): string
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "") :: string
		text = string.gsub(text, "%.$", "") :: string
	end
	return text
end

-- Devuelve el número escalado (con 2 decimales como mucho) y el sufijo.
local function scale(abs: number): (number, string)
	if abs < 1000 then
		return abs, ""
	end
	local tier = 0
	while tier < MAX_TIER and abs >= 10 ^ ((tier + 1) * 3) do
		tier += 1
	end
	local scaled = round2(abs / 10 ^ (tier * 3))
	if scaled >= 1000 and tier < MAX_TIER then
		tier += 1
		scaled = round2(abs / 10 ^ (tier * 3))
	end
	return scaled, SUFFIXES[tier + 1]
end

local function body(abs: number, locale: Locale?, keepTwoDecimals: boolean): (string, string)
	local scaled, suffix = scale(abs)
	local text
	if suffix == "" then
		text = trim(string.format("%.2f", round2(scaled)))
		if not keepTwoDecimals then
			text = string.format("%d", math.floor(scaled))
		end
	else
		text = string.format("%.2f", scaled) -- 1,25 K: siempre 2 decimales en notación compacta
	end
	return (string.gsub(text, "%.", separator(locale))), suffix
end

local function wrap(text: string, suffix: string, locale: Locale?, negative: boolean, plus: boolean): string
	local sign = if negative then "-" elseif plus then "+" else ""
	if locale == "es" then
		if suffix == "" then
			return sign .. text .. " $"
		end
		return sign .. text .. " " .. suffix .. " $"
	end
	return sign .. "$" .. text .. suffix
end

-- Cash entero ("950 $", "1,25 K $").
function Format.cash(amount: number, locale: Locale?): string
	if not isFinite(amount) then
		amount = 0
	end
	local negative = amount < 0
	local text, suffix = body(math.floor(math.abs(amount)), locale, false)
	return wrap(text, suffix, locale, negative and amount ~= 0, false)
end

-- Variación con signo explícito ("+1,25 K $").
function Format.delta(amount: number, locale: Locale?): string
	if not isFinite(amount) then
		amount = 0
	end
	local negative = amount < 0
	local text, suffix = body(math.floor(math.abs(amount)), locale, false)
	return wrap(text, suffix, locale, negative, not negative)
end

-- Ingresos por segundo ("1,5 $/s"). Admite decimales por debajo de 1000.
function Format.rate(perSecond: number, locale: Locale?): string
	if not isFinite(perSecond) then
		perSecond = 0
	end
	local text, suffix = body(math.max(0, perSecond), locale, true)
	local base = wrap(text, suffix, locale, false, false)
	return base .. "/s"
end

-- Decimal corto sin moneda (hasta 2 decimales, sin ceros finales): 0.7 -> "0,7", 12 -> "12".
function Format.decimal(n: number, locale: Locale?): string
	if not isFinite(n) then
		n = 0
	end
	local text = trim(string.format("%.2f", n))
	return (string.gsub(text, "%.", separator(locale)))
end

-- Número genérico sin moneda ("1,25 K").
function Format.count(n: number, locale: Locale?): string
	if not isFinite(n) then
		n = 0
	end
	local text, suffix = body(math.abs(math.floor(n)), locale, false)
	local sign = if n < 0 then "-" else ""
	if suffix == "" then
		return sign .. text
	end
	return sign .. text .. " " .. suffix
end

-- Porcentaje a partir de puntos básicos (1 bp = 0,01 %): 2500 -> "25 %".
function Format.bps(bps: number, locale: Locale?): string
	if not isFinite(bps) then
		bps = 0
	end
	local pct = bps / 100
	local text = trim(string.format("%.2f", pct))
	text = string.gsub(text, "%.", separator(locale)) :: string
	if locale == "es" then
		return text .. " %"
	end
	return text .. "%"
end

-- 75 -> "1:15", 3725 -> "1:02:05".
function Format.duration(seconds: number): string
	if not isFinite(seconds) or seconds < 0 then
		seconds = 0
	end
	seconds = math.floor(seconds)
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- Elige el idioma a partir de un RobloxLocaleId ("es_es", "en_us"...).
function Format.localeFromRoblox(robloxLocaleId: string?): Locale
	if robloxLocaleId and string.sub(string.lower(robloxLocaleId), 1, 2) == "es" then
		return "es"
	end
	return "en"
end

return Format
