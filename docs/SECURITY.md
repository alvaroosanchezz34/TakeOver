# Seguridad y antiexploit

## Modelo de amenazas

El cliente es **no confiable**: puede enviar cualquier cosa en cualquier momento, repetirla, o no
llegar a enviar nada. Un exploiter controla su propio cliente, no el servidor. Por tanto:

| Amenaza | Defensa | Dónde |
| --- | --- | --- |
| Inyectar dinero / precios desde el cliente | Ningún esquema acepta cantidades de dinero; precios y costes los calcula el servidor | `Actions`, test estático |
| Suplantar a otro jugador | Identidad = sesión del servidor; el payload no contiene "quién soy" | `Dispatcher` |
| Payloads malformados, NaN, inf, tablas enormes | `Validate` (tipos, rangos, claves desconocidas descartadas, NaN/inf rechazados) | `Util/Validate` |
| Spam de peticiones | Token bucket global + por acción; no cuenta como infracción | `RateLimiter`, `Config/Limits` |
| Fuzzing / acciones inexistentes | Strikes (25 en 60 s) → expulsión del jugador (solo a él) | `Dispatcher` |
| Doble ejecución / repetición de una oferta | Estado de la oferta + revisión de la estructura de propiedad | `TradeEngine` |
| Fallo a mitad de un trato | Foto + rollback; probado inyectando fallos en cada etapa | `TradeEngine` |
| Gestionar la empresa de otro | `NOT_MANAGER` (gestor = >50 % o fundador) | `CompanyOps`, `Actions` |
| Alts para trasvasar dinero | Impuesto 3 % destruido, banda de precio 0,6–2,5×, cuenta nueva ≥ 90 s, espera y tope por pareja | `TradeEngine`, `Balance` |
| Aceptar sin querer un trato grande | `CONFIRMATION_REQUIRED` (≥ 5 000 $ o cambio de gestor) | `TradeEngine` |
| Duplicar dinero con dos servidores | Bloqueo de sesión en `UpdateAsync` + `LOCK_LOST` → expulsar | `ProfileStore` |
| Perder el progreso en un fallo | Reintentos, guardado con foto, guardado al salir y en `BindToClose` | `ProfileStore`, `Persistence` |
| Compras duplicadas / fraudulentas | `ProcessReceipt` idempotente por `PurchaseId`; nada se concede por petición del cliente | `Receipts`, `Shop` |
| Espiar la riqueza de otros | El Cash ajeno no aparece en ningún mensaje (probado); libros solo para consejeros | `Views`, tests |
| Backdoors / código oculto | Auditoría estática en cada ejecución de los tests | `tests/spec/security.spec` |

## Auditoría estática automática (`tests/spec/security.spec.luau`)

Se ejecuta con toda la suite y falla si en `src/` aparece:

- `loadstring`, `getfenv`, `setfenv`, `require` por ID de asset, `InsertService`, `LoadAsset`,
  `HttpService:*Async`, `RequestAsync`, cualquier `rbxassetid`;
- creación de `Script` en tiempo de ejecución o escritura de `.Source`;
- más de un `OnServerInvoke`, algún `OnServerEvent`, o más de un `RemoteFunction`/`RemoteEvent`;
- `DataStoreService`, `ServerScriptService`, `ServerStorage` o `MessagingService` en el cliente;
- uso de `_G` fuera de las herramientas de QA de Studio;
- escritura directa de `data.cash` fuera de `Ledger`/`PlayerData`;
- menos de 18 mutaciones registradas en `tools/mutation_check.py`.

Es una comprobación por patrones, **no sustituye** una revisión manual ni un análisis dinámico.

## Comprobación por mutación

`python3 tools/mutation_check.py` rompe una a una 26 salvaguardas (revalidar la oferta, rollback,
banda de precio, bloqueo de sesión, privacidad de libros, recibos idempotentes, strikes, etc.) sobre
una copia temporal y exige que la suite falle. Resultado actual: **26/26 detectadas**. Si añades una
salvaguarda crítica, añade su mutación.

## Límites conocidos (no los ocultamos)

1. **Dos guardados no son atómicos.** Un trato entre jugadores modifica dos perfiles (dos claves
   de DataStore). Si el servidor se cae exactamente entre ambos guardados, un perfil puede quedar
   con el trato aplicado y el otro no. Mitigación: ambos perfiles se guardan inmediatamente tras el
   trato (`saveSoon`, un hilo por jugador), pero no hay transacciones entre claves. Si esto preocupa, la solución es un
   registro de tratos con idempotencia por `dealId` y reconciliación al cargar.
2. **Ofertas y alianzas no se persisten**: un cierre del servidor las cancela (sin pérdida de dinero).
3. **Sin veto de consejo**: ser consejero (≥ 25 %) da visibilidad y avisos, no poder de bloqueo.
4. **El anti-alts es heurístico**: impuesto y topes reducen el incentivo, no lo eliminan.
5. **Sin rankings globales entre servidores** (OrderedDataStore): los rankings son por servidor.
6. **No se ha probado contra un cliente hostil real.** Sí se ha probado con peticiones inválidas
   (tipos erróneos, NaN, texto, tablas anidadas, acciones inexistentes), con 20 000 transferencias
   aleatorias de propiedad, con fuzzing de conservación del dinero en tratos y con 30 jugadores
   simulados actuando al azar (`tests/spec/load.spec`).
