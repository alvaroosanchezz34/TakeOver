--!nocheck
--[[
	Loader de pruebas (Lune).

	Reproduce el mapeo de Rojo (default.project.json) con Instances simuladas para ejecutar los
	módulos REALES del juego sin modificarlos:

	  src/shared -> ReplicatedStorage.Shared
	  src/server -> ServerScriptService.Server
	  src/client -> StarterPlayer.StarterPlayerScripts.Client

	Cada módulo recibe su propio `script` (con .Parent y hermanos) y un `require` que acepta
	nodos, igual que en Roblox. Los servicios de Roblox (Players, RunService, DataStoreService...)
	son simulados y se obtienen con game:GetService().
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")

local Mock = require("./Mock")
local MockInstance = require("./MockInstance")

-- ───────────── Construcción del árbol desde disco ─────────────

local function classForFile(file)
	if file:match("%.server%.luau$") then
		return "Script", (file:gsub("%.server%.luau$", ""))
	elseif file:match("%.client%.luau$") then
		return "LocalScript", (file:gsub("%.client%.luau$", ""))
	elseif file:match("%.luau$") then
		return "ModuleScript", (file:gsub("%.luau$", ""))
	end
	return nil
end

local function makeNode(className, name, source, path)
	local node = MockInstance.new(className)
	node.Name = name
	if source then
		rawset(node, "_source", source)
		rawset(node, "_path", path)
	end
	return node
end

local function buildDir(path, name)
	local entries = fs.readDir(path)
	local initFile
	for _, e in entries do
		if e == "init.luau" or e == "init.server.luau" or e == "init.client.luau" then
			initFile = e
		end
	end
	local node
	if initFile then
		local className = classForFile(initFile)
		node = makeNode(className, name, fs.readFile(path .. "/" .. initFile), path .. "/" .. initFile)
	else
		node = makeNode("Folder", name)
	end
	table.sort(entries)
	for _, e in entries do
		local full = path .. "/" .. e
		if fs.isDir(full) then
			buildDir(full, e).Parent = node
		elseif e ~= initFile and not e:match("%.spec%.luau$") then
			local className, base = classForFile(e)
			if className then
				makeNode(className, base, fs.readFile(full), full).Parent = node
			end
		end
	end
	return node
end

-- ───────────── Loader ─────────────

local Loader = {}
Loader.__index = Loader

--[[
	options:
	  root:           directorio del repo (por defecto ".")
	  env:            globales extra para los módulos
	  serviceOptions: opciones para MockInstance.services (touch, locale, dataStore, ...)
]]
function Loader.new(options)
	options = options or {}
	local root = options.root or "."

	local game = MockInstance.new("DataModel")
	game.Name = "game"
	local services = MockInstance.services(options.serviceOptions)
	for _, svc in services do
		svc.Parent = game
	end
	local function service(name)
		local s = game:FindFirstChild(name)
		if not s then
			s = MockInstance.new(name)
			s.Name = name
			s.Parent = game
		end
		return s
	end
	rawget(game, "_props").JobId = options.jobId or "test-job"
	local closeCallbacks = {}
	rawget(game, "_props").BindToClose = function(_, fn)
		table.insert(closeCallbacks, fn)
	end
	rawset(game, "_closeCallbacks", closeCallbacks)
	rawget(game, "_props").GetService = function(_, name)
		local s = game:FindFirstChild(name)
		if not s then
			error(("GetService('%s') no soportado por el entorno de tests"):format(name), 2)
		end
		return s
	end

	buildDir(root .. "/src/shared", "Shared").Parent = service("ReplicatedStorage")
	buildDir(root .. "/src/server", "Server").Parent = service("ServerScriptService")
	local sp = service("StarterPlayer")
	local sps = sp:FindFirstChild("StarterPlayerScripts")
	if not sps then
		sps = MockInstance.new("StarterPlayerScripts")
		sps.Name = "StarterPlayerScripts"
		sps.Parent = sp
	end
	buildDir(root .. "/src/client", "Client").Parent = sps

	local self = setmetatable({
		game = game,
		services = services,
		_cache = {},
		_loading = {},
	}, Loader)

	local baseEnv = Mock.globals()
	baseEnv.task = task
	baseEnv.game = game
	baseEnv.workspace = services.Workspace
	for k, v in options.env or {} do
		baseEnv[k] = v
	end
	self._baseEnv = baseEnv
	-- Los specs se cargan con el require de Lune (sin este entorno): exponemos lo útil.
	self.Random = baseEnv.Random
	return self
end

function Loader:setService(name, obj)
	local existing = self.game:FindFirstChild(name)
	if existing then
		existing.Parent = nil
	end
	obj.Name = name
	obj.Parent = self.game
	self.services[name] = obj
end

-- Simula el cierre del servidor (game:BindToClose).
function Loader:close()
	for _, fn in rawget(self.game, "_closeCallbacks") do
		fn()
	end
end

function Loader:require(node)
	local source = type(node) == "table" and rawget(node, "_source")
	if not source then
		error("require: no es un ModuleScript conocido: " .. tostring(node), 2)
	end
	local cached = self._cache[node]
	if cached ~= nil then
		return cached.value
	end
	if self._loading[node] then
		error("require circular detectado en " .. node:GetFullName(), 2)
	end
	self._loading[node] = true

	local env = {}
	for k, v in self._baseEnv do
		env[k] = v
	end
	env.script = node
	env.require = function(target)
		return self:require(target)
	end

	local fn = luau.load(source, { debugName = "@" .. rawget(node, "_path"), environment = env })
	local value = fn()
	self._loading[node] = nil
	self._cache[node] = { value = value }
	return value
end

-- Ejecuta un Script/LocalScript (sin devolver módulo): los de arranque (Main.server / Main.client).
function Loader:run(node)
	local source = rawget(node, "_source")
	local env = {}
	for k, v in self._baseEnv do
		env[k] = v
	end
	env.script = node
	env.require = function(target)
		return self:require(target)
	end
	local fn = luau.load(source, { debugName = "@" .. rawget(node, "_path"), environment = env })
	return fn()
end

local function resolve(root, path)
	local node = root
	for part in path:gmatch("[^/%.]+") do
		node = node:FindFirstChild(part)
		if not node then
			error("módulo no encontrado: " .. path, 3)
		end
	end
	return node
end

function Loader:root(which)
	if which == "shared" then
		return self.game.ReplicatedStorage.Shared
	elseif which == "server" then
		return self.game.ServerScriptService.Server
	end
	return self.game.StarterPlayer.StarterPlayerScripts.Client
end

function Loader:shared(path)
	return self:require(resolve(self:root("shared"), path))
end

function Loader:server(path)
	return self:require(resolve(self:root("server"), path))
end

function Loader:client(path)
	return self:require(resolve(self:root("client"), path))
end

-- Nodo (sin ejecutar), útil para comprobar la estructura Rojo y ejecutar scripts de arranque.
function Loader:node(which, path)
	return resolve(self:root(which), path)
end

return Loader
