# Decisiones de diseño y problemas conocidos

## Decisiones

| # | Decisión | Por qué | Alternativa descartada |
| --- | --- | --- | --- |
| 1 | Servidor autoritativo; el cliente solo presenta | Anti-exploit básico | Cálculo en cliente con validación posterior |
| 2 | Núcleo puro + inyección de dependencias | Probar la lógica real sin Studio | Código ligado a servicios de Roblox |
| 3 | Propiedad en puntos básicos enteros (10 000) | Suma exacta, sin errores de coma flotante | Porcentajes decimales |
| 4 | Cash entero ≤ 1e15 | Sin pérdida de precisión en doubles (< 2⁵³) | Números ilimitados / decimales |
| 5 | Lotes de 1 % en los tratos | Simplifica UI y límites; evita micro-operaciones | Cualquier fracción |
| 6 | Ofertas voluntarias con banda de precio 0,6–2,5× | Un jugador nunca "pierde" su empresa a la fuerza; limita regalos entre alts | Precio libre / compra forzosa |
| 7 | Impuesto de venta 3 % destruido | Un ciclo de tratos entre cuentas propias pierde dinero | Sin impuesto |
| 8 | Valoración = ingreso **sostenido** × múltiplo | Un evento temporal no infla precios ni permite arbitraje | Valorar el ingreso instantáneo |
| 9 | Hype tecnológico solo afecta a la valoración | Da volatilidad al sector sin tocar el flujo de dinero | Hype sobre ingresos |
| 10 | Dividendos con acarreo fraccionario por accionista | Sin sesgo de redondeo contra accionistas pequeños | "Resto al mayor" |
| 11 | Gestor = >50 % o el fundador; el gestor conserva ≥ 20 % | Siempre hay alguien que gestiona | Gestión por votación |
| 12 | Bolsa NPC con cupos y diferencial | Mercado profundo con pocos jugadores, sin arbitraje fácil | Solo P2P |
| 13 | Eventos solo positivos y anunciados | Cumple "nunca quitar dinero injustamente" | Eventos negativos |
| 14 | Nombres de empresa por partes + logos predefinidos | Evita moderación de texto libre | Texto libre |
| 15 | Ofertas y alianzas efímeras (no se persisten) | Menos estados que corromper | Persistirlas |
| 16 | Tutorial dirigido por acciones reales del servidor | No se puede "saltar" con trampas; mide el embudo | Texto con "Siguiente" |
| 17 | Monetización solo cosmética | Evita pay-to-win; compatible con política de Roblox | Venta de Cash/ventajas |
| 18 | Un único bucle global de 1 s | Rendimiento con muchos jugadores | Un bucle por jugador/empresa |
| 19 | Dos remotes únicos con despachador | Superficie de ataque mínima y testable | Un remote por acción |
| 20 | UI construida por código | Sin assets de terceros, reproducible por Rojo | UI hecha a mano en Studio |

## Problemas y limitaciones conocidos

1. **Sin verificación en Studio.** El aspecto visual, los márgenes en móvil, los sonidos, la
   iluminación y el rendimiento real en dispositivos no se han visto. Los tests validan cableado,
   no estética.
2. **Rutas de sonido `rbxasset://`** sin comprobar que existan en el cliente real: si faltan, el juego
   funciona sin audio.
3. **Un trato entre jugadores = dos guardados** (sin transacción entre claves). Ver `SECURITY.md`.
4. **Ofertas/alianzas se pierden** al cerrar el servidor (sin pérdida de dinero).
5. **Sin veto de consejo:** ≥ 25 % da información, no bloqueo.
6. **Rankings por servidor**, no globales.
7. **Balance sin datos reales:** ajustado por simulación. Comercio llega al máximo en ≈ 41 min
   simulados; después el dinero solo sirve para invertir y fundar. Hay que verificar si eso resulta
   satisfactorio o aburrido en el primer playtest.
8. **IDs de monetización = 0:** la tienda aparece vacía hasta que los configures.
9. **Llamadas de analítica de Roblox** (`AnalyticsService:LogEconomyEvent`, funnel, custom) están
   comprobadas por tipos pero **no ejecutadas en vivo**.
10. **DataStore real** no probado aquí: requiere lugar publicado y *Enable Studio Access to API Services*.

## Cambios de rumbo notables durante el desarrollo (para no repetir errores)

- `os.clock` en Roblox es tiempo de CPU: se usa `time()` para el reloj monotónico.
- El reparto de dividendos "al mayor resto" regalaba sistemáticamente al NPC: sustituido por acarreo por accionista.
- El tutorial comparte reloj con el servidor: nunca avanza por tiempo salvo el paso "ver subir ingresos".
- Se dividió el cooldown compartido de nombre/logo en dos (`nameAt`, `logoAt`).
