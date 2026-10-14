--!strict
--[[
	Sesión de jugador: unión de identidad + perfil cargado + estado volátil de la partida.
	Nada de lo volátil (sessionSeconds) se confía al cliente ni se persiste como Cash.
]]

export type Session = {
	id: string, -- tostring(userId): clave de todos los diccionarios del juego
	userId: number,
	name: string,
	profile: any,
	data: { [string]: any },
	joinedMono: number,
	sessionSeconds: number,
	active: boolean,
	lastActionMono: number,
	[string]: any,
}

local Session = {}

function Session.new(userId: number, name: string, profile: any, clock: { mono: () -> number }): Session
	return {
		id = tostring(userId),
		userId = userId,
		name = name,
		profile = profile,
		data = profile.data,
		joinedMono = clock.mono(),
		sessionSeconds = 0,
		active = true,
		lastActionMono = clock.mono(),
	}
end

return Session
