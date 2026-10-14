--!nonstrict
--[[
	Red del cliente: llamadas al servidor con tiempo de espera y mensajes del servidor.
	`invoke` SIEMPRE devuelve una tabla { ok = true, data } | { ok = false, code, params }:
	nunca lanza ni se queda colgada.
]]

local Net = {}
Net.__index = Net

local TIMEOUT_SECONDS = 8

function Net.new(invokeRemote, pushRemote)
	return setmetatable({ _invoke = invokeRemote, _push = pushRemote }, Net)
end

function Net.invoke(self, action, payload)
	local done = false
	local response
	task.spawn(function()
		local ok, result = pcall(function()
			return self._invoke:InvokeServer(action, payload)
		end)
		if ok and type(result) == "table" then
			response = result
		else
			response = { ok = false, code = "NETWORK" }
		end
		done = true
	end)
	local waited = 0
	while not done and waited < TIMEOUT_SECONDS do
		waited += task.wait()
	end
	if not done then
		return { ok = false, code = "TIMEOUT" }
	end
	return response
end

-- Mensajes del servidor (estado, notificaciones, ofertas...).
function Net.onPush(self, handler)
	return self._push.OnClientEvent:Connect(function(message)
		if type(message) == "table" and type(message.type) == "string" then
			local ok, err = pcall(handler, message)
			if not ok then
				warn("[Net] error al procesar '" .. message.type .. "': " .. tostring(err))
			end
		end
	end)
end

return Net
