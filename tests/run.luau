--!nocheck
--[[
	Ejecuta toda la suite:

	    lune run tests/run                 # todo
	    lune run tests/run -- Ownership    # sólo tests cuyo nombre contenga "Ownership"

	Cada fichero tests/spec/*.spec.luau devuelve function(t, load) donde
	  t    = API de pruebas (describe/test/expect)
	  load = Loader con los módulos reales (load:shared / load:server / load:client)
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local T = require("./harness/T")
local Loader = require("./harness/Loader")

local filter = process.args[1]

local specs = {}
for _, entry in fs.readDir("tests/spec") do
	if entry:match("%.spec%.luau$") then
		table.insert(specs, entry)
	end
end
table.sort(specs)

local totalPassed, totalFailed = 0, 0
local allFailures = {}
local started = os.clock()

for _, file in specs do
	local name = file:gsub("%.spec%.luau$", "")
	local ok, specOrErr = pcall(function()
		return require("./spec/" .. name .. ".spec")
	end)
	if not ok then
		totalFailed += 1
		table.insert(allFailures, { name = name .. " (carga del spec)", message = tostring(specOrErr) })
		print(stdio.color("red") .. "✗ " .. stdio.color("reset") .. name .. " — error al cargar el spec")
	else
		local t = T.new()
		local loader = Loader.new({ root = "." })
		local registered, regErr = pcall(specOrErr, t, loader)
		if not registered then
			totalFailed += 1
			table.insert(allFailures, { name = name .. " (registro)", message = tostring(regErr) })
			print(stdio.color("red") .. "✗ " .. stdio.color("reset") .. name .. " — error al registrar")
		else
			local result = t:run(filter)
			totalPassed += result.passed
			totalFailed += result.failed
			for _, f in result.failures do
				table.insert(allFailures, f)
			end
			local mark = if result.failed == 0
				then stdio.color("green") .. "✓"
				else stdio.color("red") .. "✗"
			print(
				("%s%s %s — %d ok, %d fallos"):format(
					mark,
					stdio.color("reset"),
					name,
					result.passed,
					result.failed
				)
			)
		end
	end
end

if #allFailures > 0 then
	print("")
	print(stdio.color("red") .. "FALLOS:" .. stdio.color("reset"))
	for _, f in allFailures do
		print("  • " .. f.name)
		print("      " .. tostring(f.message):gsub("\n", "\n      "))
		if f.trace and f.trace ~= "" then
			print("      " .. f.trace:gsub("\n", "\n      "))
		end
	end
end

print("")
print(("%d pruebas OK, %d fallos (%.2fs)"):format(totalPassed, totalFailed, os.clock() - started))
if totalFailed > 0 or (totalPassed == 0) then
	process.exit(1)
end
