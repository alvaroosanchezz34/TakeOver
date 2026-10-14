--!strict
--[[
	Reglas PÚBLICAS de control empresarial. Son parámetros de diseño, no leyes
	inmutables. La interfaz las muestra tal cual (ver Locale: "governance.*").

	  < 25 %   Inversor minoritario : cobra dividendos.
	  ≥ 25 %   Consejero           : además ve los libros (ingresos, ofertas) y recibe aviso
	                                  de operaciones que cambian el control.
	  > 50 %   Control             : es quien GESTIONA la empresa (compra mejoras, nombre,
	                                  logotipo, aspecto).
	  100 %    Propiedad completa.

	Sin mayoría, gestiona el fundador. Nadie puede quedarse una empresa sin una
	transacción válida: para gestionar hay que comprar más del 50 % a quien lo posee.
]]

local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	BoardMinBps = 2500, -- desde aquí (inclusive)
	ControlMinBpsExclusive = 5000, -- estrictamente por encima
	-- El gestor debe conservar al menos esto (tener algo en juego). Evita que el fundador
	-- se desprenda de todo mientras nadie tiene mayoría y la empresa quede sin gestor.
	MinManagerBps = 2000,
})
