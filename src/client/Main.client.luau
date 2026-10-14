--!nonstrict
--[[
	TAKEOVER — arranque del cliente. Toda la lógica está en App; este script solo la inicia y
	registra cualquier fallo de arranque en lugar de dejar una pantalla vacía sin explicación.
]]

local App = require(script.Parent:WaitForChild("App"))

local ok, err = pcall(App.start)
if not ok then
	warn("[TAKEOVER] error al iniciar la interfaz: " .. tostring(err))
end
