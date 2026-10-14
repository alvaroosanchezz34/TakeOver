--!nonstrict
--[[
	Capa de red del servidor: expone el despachador al RemoteFunction y entrega los mensajes
	del servidor a cada cliente por el RemoteEvent. Sin lógica de juego.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Net = {}

function Net.create()
	local invoke, pushRemote = Remotes.createServer()
	local self = { invoke = invoke, pushRemote = pushRemote }

	-- Servidor -> un cliente concreto (si ya no está, se ignora).
	function self.push(userId: number, message: { [string]: any })
		local player = Players:GetPlayerByUserId(userId)
		if player then
			pushRemote:FireClient(player, message)
		end
	end

	-- Cliente -> servidor. Pase lo que pase dentro, el cliente recibe SIEMPRE una respuesta
	-- bien formada y nunca un error con detalles internos.
	function self.bind(server)
		invoke.OnServerInvoke = function(player, action, payload)
			if typeof(player) ~= "Instance" or not player:IsA("Player") then
				return { ok = false, code = "BAD_REQUEST" }
			end
			local ok, response = pcall(server.dispatch, server, player.UserId, action, payload)
			if not ok or type(response) ~= "table" then
				warn("[Net] fallo al despachar " .. tostring(action) .. ": " .. tostring(response))
				return { ok = false, code = "INTERNAL" }
			end
			return response
		end
	end

	return self
end

return Net
