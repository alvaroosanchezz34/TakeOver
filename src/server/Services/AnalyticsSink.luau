--!nonstrict
--[[
	Traduce los eventos de analítica del juego a AnalyticsService de Roblox.
	Cada llamada va en pcall: la analítica NUNCA puede romper la partida.
	Sólo recibe las propiedades de la lista cerrada de Core/Analytics (sin datos personales).
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

local AnalyticsSink = {}

function AnalyticsSink.create()
	return function(event)
		local player = Players:GetPlayerByUserId(event.userId)
		if player == nil then
			return
		end
		local ok, err = pcall(function()
			if event.kind == "funnel" then
				AnalyticsService:LogOnboardingFunnelStepEvent(
					player,
					event.value or 0,
					event.name,
					event.props
				)
			elseif event.kind == "economy" then
				local flow = if event.props.flow == "source"
					then Enum.AnalyticsEconomyFlowType.Source
					else Enum.AnalyticsEconomyFlowType.Sink
				AnalyticsService:LogEconomyEvent(
					player,
					flow,
					"Cash",
					event.value or 0,
					event.props.balance or 0,
					"Gameplay",
					event.name,
					nil
				)
			else
				AnalyticsService:LogCustomEvent(player, event.name, event.value, event.props)
			end
		end)
		if not ok then
			warn("[AnalyticsSink] " .. tostring(err))
		end
	end
end

return AnalyticsSink
