--!nocheck
--[[
	Loader de pruebas (Lune).

	Reproduce el mapeo de Rojo (default.project.json) con un árbol de Instances
	virtual para ejecutar los módulos REALES del juego sin modificarlos:

	  src/shared -> ReplicatedStorage.Shared
	  src/server -> ServerScriptService.Server
	  src/client -> StarterPlayer.StarterPlayerScripts.Client

	Cada módulo recibe su propio `script` (con .Parent y hermanos) y un `require`
	que acepta nodos, igual que en Roblox.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")

local Mock = require("./Mock")

-- ───────────── Nodos virtuales ─────────────

local Node = {}
local methods = {}

Node.__index = function(self, key)
	local method = methods[key]
	if method then
		return method
	end
	return rawget(self, "_children")[key]
end

local function newNode(name, className)
	return setmetatable({ Name = name, ClassName = className, Parent = nil, _children = {} }, Node)
end

function methods.FindFirstChild(self, name, recursive)
	local child = self._children[name]
	if child or not recursive then
		return child
	end
	for _, c in self._children do
		local found = methods.FindFirstChild(c, name, true)
		if found then
			return found
		end
	end
	return nil
end

function methods.WaitForChild(self, name)
	local child = self._children[name]
	if not child then
		error(
			("WaitForChild('%s') no encontrado bajo %s (en tests no se espera)"):format(
				name,
				methods.GetFullName(self)
			),
			2
		)
	end
	return child
end

function methods.GetChildren(self)
	local out = {}
	for _, c in self._children do
		table.insert(out, c)
	end
	table.sort(out, function(a, b)
		return a.Name < b.Name
	end)
	return out
end

function methods.IsA(self, className)
	return self.ClassName == className or className == "Instance"
end

function methods.GetFullName(self)
	local parts = {}
	local n = self
	while n and n.Name ~= "game" do
		table.insert(parts, 1, n.Name)
		n = n.Parent
	end
	return table.concat(parts, ".")
end

function methods.GetService(self, name)
	local svc = self._children[name]
	if svc then
		return svc
	end
	error(("GetService('%s') no soportado por el entorno de tests"):format(name), 2)
end

local function attach(parent, child)
	child.Parent = parent
	parent._children[child.Name] = child
end

-- ───────────── Construcción del árbol desde disco ─────────────

local function classForFile(file)
	if file:match("%.server%.luau$") then
		return "Script", file:gsub("%.server%.luau$", "")
	elseif file:match("%.client%.luau$") then
		return "LocalScript", file:gsub("%.client%.luau$", "")
	elseif file:match("%.luau$") then
		return "ModuleScript", file:gsub("%.luau$", "")
	end
	return nil
end

local function buildDir(path, name)
	local entries = fs.readDir(path)
	local node = newNode(name, "Folder")
	local initFile
	for _, e in entries do
		if e == "init.luau" or e == "init.server.luau" or e == "init.client.luau" then
			initFile = e
		end
	end
	if initFile then
		local className = classForFile(initFile)
		node.ClassName = className
		node._source = fs.readFile(path .. "/" .. initFile)
		node._path = path .. "/" .. initFile
	end
	table.sort(entries)
	for _, e in entries do
		local full = path .. "/" .. e
		if fs.isDir(full) then
			attach(node, buildDir(full, e))
		elseif e ~= initFile and not e:match("%.spec%.luau$") then
			local className, base = classForFile(e)
			if className then
				local child = newNode(base, className)
				child._source = fs.readFile(full)
				child._path = full
				attach(node, child)
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
	  root:   directorio del repo (por defecto ".")
	  env:    globales extra para los módulos (mocks de Roblox, etc.)
	  gameServices: nombre -> objeto devuelto por game:GetService(nombre)
]]
function Loader.new(options)
	options = options or {}
	local root = options.root or "."

	local game = newNode("game", "DataModel")
	local function service(name)
		local s = newNode(name, name)
		attach(game, s)
		return s
	end
	local rs = service("ReplicatedStorage")
	local sss = service("ServerScriptService")
	local sp = service("StarterPlayer")
	local sps = newNode("StarterPlayerScripts", "StarterPlayerScripts")
	attach(sp, sps)

	attach(rs, buildDir(root .. "/src/shared", "Shared"))
	attach(sss, buildDir(root .. "/src/server", "Server"))
	attach(sps, buildDir(root .. "/src/client", "Client"))

	local self = setmetatable({
		game = game,
		_cache = {},
		_loading = {},
		_extraServices = options.gameServices or {},
	}, Loader)

	local baseEnv = Mock.globals()
	baseEnv.task = task
	baseEnv.game = game
	for k, v in options.env or {} do
		baseEnv[k] = v
	end
	self._baseEnv = baseEnv

	-- game:GetService() devuelve primero los servicios simulados inyectados.
	local rawGetService = methods.GetService
	rawset(game, "GetService", function(_, name)
		if self._extraServices[name] then
			return self._extraServices[name]
		end
		return rawGetService(game, name)
	end)

	return self
end

-- Servicios simulados (DataStoreService, MarketplaceService...) por test.
function Loader:setService(name, obj)
	self._extraServices[name] = obj
end

function Loader:require(node)
	if type(node) ~= "table" or node._source == nil then
		error("require: no es un ModuleScript conocido: " .. tostring(node), 2)
	end
	local cached = self._cache[node]
	if cached ~= nil then
		return cached.value
	end
	if self._loading[node] then
		error("require circular detectado en " .. methods.GetFullName(node), 2)
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

	local fn = luau.load(node._source, { debugName = "@" .. node._path, environment = env })
	local value = fn()
	self._loading[node] = nil
	self._cache[node] = { value = value }
	return value
end

-- Atajos: loader:shared("Economy/Income"), loader:server("Core/World"), loader:client(...)
local function resolve(root, path)
	local node = root
	for part in path:gmatch("[^/%.]+") do
		node = node._children[part]
		if not node then
			error("módulo no encontrado: " .. path, 3)
		end
	end
	return node
end

function Loader:shared(path)
	return self:require(resolve(self.game.ReplicatedStorage._children.Shared, path))
end

function Loader:server(path)
	return self:require(resolve(self.game.ServerScriptService._children.Server, path))
end

function Loader:client(path)
	return self:require(
		resolve(self.game.StarterPlayer._children.StarterPlayerScripts._children.Client, path)
	)
end

-- Nodo (sin ejecutar), útil para comprobar la estructura Rojo.
function Loader:node(root, path)
	local base = ({
		shared = self.game.ReplicatedStorage._children.Shared,
		server = self.game.ServerScriptService._children.Server,
		client = self.game.StarterPlayer._children.StarterPlayerScripts._children.Client,
	})[root]
	return resolve(base, path)
end

return Loader
