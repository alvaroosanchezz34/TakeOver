--!nonstrict
--[[
	Crea el DataStore real (o uno en memoria si no hay acceso) y el ProfileStore.

	En Studio, DataStore sólo funciona si el lugar está publicado y se ha activado
	"Enable Studio Access to API Services". Si no, se usa memoria y se AVISA claramente:
	el juego funciona, pero el progreso no se conserva.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local MemoryDataStore = require(script.Parent.Parent.Core.MemoryDataStore)
local ProfileStore = require(script.Parent.Parent.Core.ProfileStore)

local DATASTORE_NAME = "Takeover_PlayerData_v1"

local Persistence = {}

function Persistence.create(jobId: string, clock)
	local dataStore: any
	local persistent = true

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if ok then
		dataStore = result
		-- Prueba de acceso: en Studio sin permisos falla aquí y no durante la partida.
		local probeOk, probeErr = pcall(function()
			return dataStore:GetAsync("__probe__")
		end)
		if not probeOk then
			persistent = false
			warn("[Persistence] DataStore no disponible: " .. tostring(probeErr))
		end
	else
		persistent = false
		warn("[Persistence] no se pudo obtener el DataStore: " .. tostring(result))
	end

	if not persistent then
		if RunService:IsStudio() then
			warn(
				"[Persistence] MODO MEMORIA: el progreso NO se guardará. Publica el lugar y activa Game Settings > Security > 'Enable Studio Access to API Services'."
			)
		else
			warn(
				"[Persistence] ¡DATASTORE NO DISPONIBLE EN UN SERVIDOR REAL! Los jugadores no podrán conservar progreso."
			)
		end
		dataStore = MemoryDataStore.new()
	end

	local store = ProfileStore.new({
		dataStore = dataStore,
		clock = clock or Clock.system(),
		jobId = jobId,
		wait = task.wait,
		log = function(message)
			warn(message)
		end,
	})
	return store, persistent
end

return Persistence
