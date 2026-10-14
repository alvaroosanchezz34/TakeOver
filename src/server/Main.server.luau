--!nonstrict
--[[
	TAKEOVER — arranque del servidor.

	Une las piezas: persistencia (DataStore con bloqueo de sesión), red (un RemoteFunction + un
	RemoteEvent), tienda (Game Passes / Developer Products), analítica, mundo y el bucle
	económico (UN solo Heartbeat global, no un bucle por jugador).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Util.Clock)

local Core = script.Parent:WaitForChild("Core")
local Services = script.Parent:WaitForChild("Services")
local Server = require(Core.Server)
local AnalyticsSink = require(Services.AnalyticsSink)
local Net = require(Services.Net)
local Persistence = require(Services.Persistence)
local Shop = require(Services.Shop)
local WorldBuilder = require(Services.WorldBuilder)

local clock = Clock.system()
local jobId = if game.JobId ~= "" then game.JobId else ("studio-" .. tostring(os.time()))

-- Mensajes al expulsar por un motivo técnico (siempre en ES + EN: aún no hay idioma del cliente).
local KICK_MESSAGES = {
	SESSION_LOCKED = "Tus datos están en uso en otro servidor. Vuelve a entrar en unos segundos.\nYour data is in use on another server. Please rejoin in a few seconds.",
	LOAD_FAILED = "No pudimos cargar tus datos. No se ha perdido nada: vuelve a entrar.\nWe couldn't load your data. Nothing was lost: please rejoin.",
	DATA_FROM_FUTURE = "Tus datos pertenecen a una versión más reciente del juego.\nYour data belongs to a newer version of the game.",
	DATA_LOCK_LOST = "Tu sesión se abrió en otro servidor. Vuelve a entrar.\nYour session was opened on another server. Please rejoin.",
	ABUSE = "Actividad anómala detectada.\nUnusual activity detected.",
}

local function kick(userId: number, code: string)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		player:Kick(KICK_MESSAGES[code] or ("Error " .. tostring(code)))
	end
end

local store, persistent = Persistence.create(jobId, clock)
local net = Net.create()

local server = Server.new({
	clock = clock,
	rng = Random.new(),
	store = store,
	push = net.push,
	kick = kick,
	spawn = task.spawn,
	wait = task.wait,
	analyticsSink = AnalyticsSink.create(),
	log = warn,
})
net.bind(server)

local worldBuilder = WorldBuilder.new()
worldBuilder:build()
local shop = Shop.start(server)

local function onPlayerAdded(player: Player)
	task.spawn(function()
		local result = server:playerAdded(player.UserId, player.DisplayName)
		if not result.ok then
			if result.code ~= "LEFT_DURING_LOAD" and player.Parent then
				kick(player.UserId, result.code)
			end
			return
		end
		if player.Parent == nil then
			return
		end
		local session = result.value
		shop.applyPasses(session)
		worldBuilder:assignPlot(player, session)
		worldBuilder:teleportToPlot(player)
		server:pushState(session)
	end)
end

local function onPlayerRemoving(player: Player)
	task.spawn(function()
		worldBuilder:releasePlot(player.UserId)
		server:playerRemoving(player.UserId)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

-- Bucle global: economía + mantenimiento una vez por segundo.
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator >= 1 then
		local step = accumulator
		accumulator = 0
		local ok, err = pcall(function()
			server:tick(step)
			worldBuilder:update(server)
		end)
		if not ok then
			warn("[Main] error en el bucle principal: " .. tostring(err))
		end
	end
end)

game:BindToClose(function()
	server:shutdown()
end)

-- Herramientas de QA: SÓLO en Studio (en servidores reales no existen).
if RunService:IsStudio() then
	_G.Takeover = {
		server = server,
		persistent = persistent,
		giveCash = function(userId: number, amount: number)
			local session = server.world.sessions[tostring(userId)]
			if session then
				server.ledger:credit(session, amount, "reward", { source = "debug" })
			end
		end,
		forceEvent = function(id: string)
			return server.events:forceStart(id)
		end,
	}
	print("[TAKEOVER] Servidor listo. Persistencia real: " .. tostring(persistent) .. ". QA: _G.Takeover")
end
