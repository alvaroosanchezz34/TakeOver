--!strict
--[[
	Validación de payloads de red. Todo lo que llega del cliente es hostil:
	- tipos exactos, números finitos, enteros y rangos,
	- cadenas acotadas y con patrón,
	- objetos: sólo se copian las claves declaradas (el resto se descarta).
	Devuelve una copia limpia; el handler nunca ve el valor original.
]]

export type Rule = { [string]: any }

local Validate = {}

local MAX_KEYS = 32

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

function Validate.int(opts: { min: number?, max: number? }?): Rule
	return { kind = "int", min = opts and opts.min, max = opts and opts.max }
end

function Validate.number(opts: { min: number?, max: number? }?): Rule
	return { kind = "number", min = opts and opts.min, max = opts and opts.max }
end

function Validate.string(opts: { minLen: number?, maxLen: number?, pattern: string? }?): Rule
	return {
		kind = "string",
		minLen = opts and opts.minLen or 0,
		maxLen = opts and opts.maxLen or 64,
		pattern = opts and opts.pattern,
	}
end

function Validate.bool(): Rule
	return { kind = "bool" }
end

function Validate.oneOf(values: { string }): Rule
	return { kind = "oneOf", values = values }
end

function Validate.optional(rule: Rule): Rule
	return { kind = "optional", inner = rule }
end

function Validate.object(fields: { [string]: Rule }): Rule
	return { kind = "object", fields = fields }
end

function Validate.array(item: Rule, maxLen: number?): Rule
	return { kind = "array", item = item, maxLen = maxLen or 16 }
end

-- Sin parámetros (acepta nil o tabla vacía).
function Validate.none(): Rule
	return { kind = "none" }
end

local function fail(path: string, reason: string): (boolean, string)
	return false, path .. ": " .. reason
end

local function run(rule: Rule, value: any, path: string): (boolean, any)
	local kind = rule.kind

	if kind == "optional" then
		if value == nil then
			return true, nil
		end
		return run(rule.inner, value, path)
	end

	if kind == "none" then
		return true, nil
	end

	if kind == "int" or kind == "number" then
		if type(value) ~= "number" then
			return fail(path, "debe ser número")
		end
		if not isFinite(value) then
			return fail(path, "número no finito")
		end
		if kind == "int" and value % 1 ~= 0 then
			return fail(path, "debe ser entero")
		end
		if rule.min ~= nil and value < rule.min then
			return fail(path, "por debajo del mínimo")
		end
		if rule.max ~= nil and value > rule.max then
			return fail(path, "por encima del máximo")
		end
		return true, value
	end

	if kind == "string" then
		if type(value) ~= "string" then
			return fail(path, "debe ser texto")
		end
		local len = #value
		if len < rule.minLen or len > rule.maxLen then
			return fail(path, "longitud fuera de rango")
		end
		-- Sin caracteres de control: evita inyección en logs y UI.
		if string.find(value, "[%c]") then
			return fail(path, "caracteres no permitidos")
		end
		if rule.pattern and not string.match(value, rule.pattern) then
			return fail(path, "formato inválido")
		end
		return true, value
	end

	if kind == "bool" then
		if type(value) ~= "boolean" then
			return fail(path, "debe ser booleano")
		end
		return true, value
	end

	if kind == "oneOf" then
		if type(value) ~= "string" then
			return fail(path, "debe ser texto")
		end
		if table.find(rule.values, value) == nil then
			return fail(path, "valor no permitido")
		end
		return true, value
	end

	if kind == "array" then
		if type(value) ~= "table" then
			return fail(path, "debe ser lista")
		end
		local n = #value
		if n > rule.maxLen then
			return fail(path, "demasiados elementos")
		end
		local out = {}
		for i = 1, n do
			local ok, clean = run(rule.item, value[i], path .. "[" .. i .. "]")
			if not ok then
				return false, clean
			end
			out[i] = clean
		end
		return true, out
	end

	if kind == "object" then
		if type(value) ~= "table" then
			return fail(path, "debe ser objeto")
		end
		local keyCount = 0
		for _ in value do
			keyCount += 1
			if keyCount > MAX_KEYS then
				return fail(path, "demasiadas claves")
			end
		end
		local out = {}
		for name, fieldRule in rule.fields do
			local ok, clean = run(fieldRule, value[name], path .. "." .. name)
			if not ok then
				return false, clean
			end
			out[name] = clean
		end
		return true, out
	end

	return fail(path, "regla desconocida")
end

-- Devuelve (true, valorLimpio) o (false, motivo).
function Validate.check(rule: Rule, value: any): (boolean, any)
	if rule.kind == "none" then
		if value ~= nil and type(value) ~= "table" then
			return false, "payload: se esperaba vacío"
		end
		return true, {}
	end
	if value == nil and rule.kind == "object" then
		return false, "payload: ausente"
	end
	return run(rule, value, "payload")
end

return Validate
