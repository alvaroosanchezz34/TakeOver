--!nonstrict
--[[
	Remotes del juego. TODA la comunicación pasa por dos objetos:

	  Invoke (RemoteFunction)  cliente -> servidor: { action, payload } => { ok, data | code, params }
	  Push   (RemoteEvent)     servidor -> cliente: mensajes { type = "state" | "notify" | ... }

	El servidor los crea (una vez) bajo ReplicatedStorage.TakeoverRemotes. No hay más remotes:
	toda petición pasa por el despachador del servidor (validación, límites, identidad).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

Remotes.FOLDER = "TakeoverRemotes"
Remotes.INVOKE = "Invoke"
Remotes.PUSH = "Push"

function Remotes.createServer()
	local folder = ReplicatedStorage:FindFirstChild(Remotes.FOLDER)
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = Remotes.FOLDER
		folder.Parent = ReplicatedStorage
	end
	local invoke = folder:FindFirstChild(Remotes.INVOKE)
	if invoke == nil then
		invoke = Instance.new("RemoteFunction")
		invoke.Name = Remotes.INVOKE
		invoke.Parent = folder
	end
	local push = folder:FindFirstChild(Remotes.PUSH)
	if push == nil then
		push = Instance.new("RemoteEvent")
		push.Name = Remotes.PUSH
		push.Parent = folder
	end
	return invoke, push
end

-- Cliente: espera a que existan (el servidor los crea al arrancar).
function Remotes.waitClient()
	local folder = ReplicatedStorage:WaitForChild(Remotes.FOLDER)
	return folder:WaitForChild(Remotes.INVOKE), folder:WaitForChild(Remotes.PUSH)
end

return Remotes
