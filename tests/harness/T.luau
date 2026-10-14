--!nocheck
--[[
	Mini framework de pruebas: describe / test / expect.
	Sin dependencias; ejecuta con `lune run tests/run`.
]]

local T = {}
T.__index = T

local function deepEqual(a, b, seen)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		-- NaN == NaN
		return a ~= a and b ~= b
	end
	seen = seen or {}
	if seen[a] == b then
		return true
	end
	seen[a] = b
	for k, v in a do
		if not deepEqual(v, b[k], seen) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function show(v, depth)
	depth = depth or 0
	if type(v) == "string" then
		return string.format("%q", v)
	end
	if type(v) ~= "table" then
		return tostring(v)
	end
	if depth > 3 then
		return "{...}"
	end
	local keys = {}
	for k in v do
		table.insert(keys, k)
	end
	table.sort(keys, function(x, y)
		return tostring(x) < tostring(y)
	end)
	local parts = {}
	for _, k in keys do
		table.insert(parts, tostring(k) .. "=" .. show(v[k], depth + 1))
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local Expectation = {}
Expectation.__index = Expectation

local function fail(msg)
	error({ __testfail = true, message = msg }, 3)
end

function Expectation:toBe(expected)
	if self.value ~= expected then
		fail(("esperado %s, recibido %s"):format(show(expected), show(self.value)))
	end
end

function Expectation:toEqual(expected)
	if not deepEqual(self.value, expected) then
		fail(("no son iguales\n    esperado: %s\n    recibido: %s"):format(show(expected), show(self.value)))
	end
end

function Expectation:toBeNear(expected, tolerance)
	tolerance = tolerance or 1e-6
	if type(self.value) ~= "number" or math.abs(self.value - expected) > tolerance then
		fail(("esperado ≈ %s (±%s), recibido %s"):format(show(expected), tolerance, show(self.value)))
	end
end

function Expectation:toBeTruthy()
	if not self.value then
		fail("esperado valor verdadero, recibido " .. show(self.value))
	end
end

function Expectation:toBeFalsy()
	if self.value then
		fail("esperado valor falso/nil, recibido " .. show(self.value))
	end
end

function Expectation:toBeNil()
	if self.value ~= nil then
		fail("esperado nil, recibido " .. show(self.value))
	end
end

function Expectation:toBeGreaterThan(n)
	if not (type(self.value) == "number" and self.value > n) then
		fail(("esperado > %s, recibido %s"):format(n, show(self.value)))
	end
end

function Expectation:toBeLessThan(n)
	if not (type(self.value) == "number" and self.value < n) then
		fail(("esperado < %s, recibido %s"):format(n, show(self.value)))
	end
end

function Expectation:toBeAtLeast(n)
	if not (type(self.value) == "number" and self.value >= n) then
		fail(("esperado >= %s, recibido %s"):format(n, show(self.value)))
	end
end

function Expectation:toBeAtMost(n)
	if not (type(self.value) == "number" and self.value <= n) then
		fail(("esperado <= %s, recibido %s"):format(n, show(self.value)))
	end
end

function Expectation:toContain(item)
	if type(self.value) == "string" then
		if not string.find(self.value, item, 1, true) then
			fail(("el texto %s no contiene %s"):format(show(self.value), show(item)))
		end
		return
	end
	if table.find(self.value, item) == nil then
		fail(("la lista %s no contiene %s"):format(show(self.value), show(item)))
	end
end

function Expectation:toHaveLength(n)
	if #self.value ~= n then
		fail(("esperada longitud %d, recibida %d"):format(n, #self.value))
	end
end

-- La función debe lanzar un error; `pattern` (opcional) se busca en el mensaje.
function Expectation:toThrow(pattern)
	local ok, err = pcall(self.value)
	if ok then
		fail("esperado que lanzara un error, pero terminó bien")
	end
	if pattern then
		local message = type(err) == "table" and tostring(err.message) or tostring(err)
		if not string.find(message, pattern, 1, true) then
			fail(("el error %s no contiene %s"):format(show(message), show(pattern)))
		end
	end
end

-- Para Result: { ok = false, code = "X" }
function Expectation:toBeErr(code)
	local v = self.value
	if type(v) ~= "table" or v.ok ~= false then
		fail("esperado Result de error, recibido " .. show(v))
	end
	if code and v.code ~= code then
		fail(("esperado código %s, recibido %s"):format(show(code), show(v.code)))
	end
end

function Expectation:toBeOk()
	local v = self.value
	if type(v) ~= "table" or v.ok ~= true then
		fail("esperado Result ok, recibido " .. show(v))
	end
end

function T.new()
	return setmetatable({ _tests = {}, _prefix = {} }, T)
end

function T:describe(name, fn)
	table.insert(self._prefix, name)
	fn()
	table.remove(self._prefix)
end

function T:test(name, fn)
	local full = table.concat(self._prefix, " › ")
	table.insert(self._tests, { name = (full ~= "" and (full .. " › ") or "") .. name, fn = fn })
end

function T:expect(value)
	return setmetatable({ value = value }, Expectation)
end

T.deepEqual = deepEqual
T.show = show

-- Ejecuta y devuelve { passed, failed, failures = {{name, message}} }
function T:run(filter)
	local passed, failed, failures = 0, 0, {}
	for _, test in self._tests do
		if not filter or string.find(test.name, filter, 1, true) then
			local ok, err = xpcall(test.fn, function(e)
				if type(e) == "table" and e.__testfail then
					return e
				end
				return { message = tostring(e), trace = debug.traceback("", 2) }
			end)
			if ok then
				passed += 1
			else
				failed += 1
				table.insert(failures, {
					name = test.name,
					message = err.message,
					trace = err.trace,
				})
			end
		end
	end
	return { passed = passed, failed = failed, failures = failures }
end

return T
