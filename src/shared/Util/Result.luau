--!strict
--[[
	Result: forma uniforme de devolver éxito/fallo sin lanzar errores.
	Los fallos llevan un `code` estable (nunca texto de UI). El cliente traduce el
	código a un mensaje localizado (ver Shared/Locale).
]]

export type Params = { [string]: any }
export type Ok<T> = { ok: true, value: T }
export type Err = { ok: false, code: string, params: Params? }
export type Result<T> = Ok<T> | Err

local Result = {}

function Result.ok<T>(value: T): Ok<T>
	return { ok = true, value = value }
end

function Result.err(code: string, params: Params?): Err
	return { ok = false, code = code, params = params }
end

return Result
