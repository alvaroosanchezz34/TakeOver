# Arquitectura

## Principios

1. **El servidor decide todo lo económico.** Dinero, ingresos, valoración, mejoras, propiedad,
   recompensas y guardado. El cliente solo presenta y solicita.
2. **Núcleo puro + inyección de dependencias.** Las reglas del juego (`src/shared/Economy`,
   `src/server/Core`) no tocan servicios de Roblox directamente: reciben reloj, DataStore, etc.
   Por eso se pueden ejecutar íntegras fuera de Studio (simulador Lune).
3. **Una sola puerta de entrada.** Toda petición del cliente pasa por el `Dispatcher`.
4. **Una sola fuente de verdad del dinero.** Solo el `Ledger` modifica `data.cash`
   (lo comprueba una prueba estática en `tests/spec/security.spec.luau`).
5. **Configuración, no constantes mágicas.** Todo número de diseño vive en `src/shared/Config/*`
   (congelado en profundidad al cargar).

## Capas

```
src/shared
  Util/        Result, Table, Clock, Signal, RateLimiter, Validate, Format
  Config/      Balance, Sectors, Governance, Events, Limits, Monetization, Progression, Cosmetics, Market
  Economy/     Money, Catalog, Income, Pricing, Valuation, Ownership, Company   (puro, sin Roblox)
  Locale.luau  textos ES/EN + mensajes de error por código
  Remotes.luau crea/espera los dos únicos remotes (Invoke, Push)
  BuildingSpec geometría de los edificios (la usa el WorldBuilder)

src/server
  Core/        núcleo autoritativo (sin servicios de Roblox)
    PlayerData, ProfileStore, MemoryDataStore   persistencia versionada con bloqueo de sesión
    Ledger                                      único punto de cambio de dinero
    World, Session                              sesiones, empresas, valoraciones, patrimonio
    CompanyOps                                  fundar, mejorar, subir de nivel, renombrar, logo
    IncomeEngine                                tick global de ingresos y dividendos
    OfferBook, TradeEngine                      ofertas y transacciones atómicas
    EventDirector, Alliances, Leaderboard       eventos globales, alianzas, rankings
    Progression                                 tutorial, logros/títulos, recompensa diaria
    Analytics, Receipts                         analítica sin PII, recibos idempotentes
    Dispatcher, Actions, Views                  puerta de entrada, 21 acciones, vistas por espectador
    Server                                      raíz de composición
  Services/    capa fina con servicios de Roblox
    Net, Persistence, AnalyticsSink, Shop, WorldBuilder
  Main.server.luau   arranque: un único Heartbeat acumulador (tick 1 s), BindToClose, QA solo en Studio

src/client
  Main.client, App    composición, capas ScreenGui, escala responsive, mensajes del servidor
  Net, State/Store    transporte y estado local (extrapola Cash solo para MOSTRARLO)
  UI/                 Theme, Responsive, Kit, Windows, Widgets
  Controllers/        HUD, CompanyPanel, MarketPanel, Trading, RankingPanel, MenuPanel,
                      Notifications, Tutorial, EventBanner, Effects
```

## Flujo de una acción (ejemplo: aceptar una oferta)

1. El jugador pulsa *Aceptar* → `Net:invoke("RespondOffer", { offerId, action, confirm })`.
2. `Services/Net` (`OnServerInvoke`) llama a `Dispatcher.dispatch(userId, action, payload)`.
3. El `Dispatcher`: ¿acción conocida? → límite global y por acción (token bucket) → ¿sesión
   cargada? → validación del payload contra el esquema (devuelve una **copia limpia**) → handler en `pcall`.
4. El handler (`Actions.RespondOffer`) obtiene la identidad de la **sesión**, nunca del payload,
   y llama a `TradeEngine.acceptOffer`.
5. `TradeEngine` revalida *todo* (estado de la oferta, revisión de la estructura de propiedad,
   deriva de valoración, fondos, participaciones, partes presentes, confirmación), toma una foto,
   ejecuta con el `Ledger` y `Ownership.transfer`, y si algo falla restaura la foto (**rollback**).
6. El resultado `{ ok, data }` o `{ ok = false, code, params }` vuelve al cliente, que lo
   localiza con `Locale`. Además se empujan `state`, `notify`, `offers`… a las partes afectadas.

## Bucle económico

`Main.server.luau` mantiene **un único** Heartbeat con acumulador: cada segundo ejecuta
`server.tick(dt)` y `worldBuilder.update()`. `dt` se limita a `Balance.MaxTickDelta` (5 s) para que
un servidor atascado no acredite de golpe todo el tiempo perdido. `IncomeEngine.tick` calcula los
ingresos de cada empresa una sola vez y reparte dividendos a todos los accionistas.

## Persistencia

`ProfileStore` guarda un registro por jugador (`Player_<userId>`) con `UpdateAsync`:
bloqueo de sesión (`jobId` + marca de tiempo, caduca a los 300 s), latido en cada guardado,
`LOCK_LOST` → se expulsa al jugador, guardado con **foto** de los datos, reintentos con espera
exponencial, migraciones por versión (`PlayerData`), reparación de datos corruptos y
comprobación de que todo es serializable. Sin acceso a la API (Studio sin permisos) se cae a
`MemoryDataStore` **avisando claramente**.

## Cliente

El cliente no calcula precios ni propiedad. `Store` guarda el último estado recibido y extrapola
el Cash únicamente para que el contador suba suavemente; cada foto del servidor (al menos cada 5 s)
lo corrige. Los textos se resuelven con `Locale` (ES/EN, auto según `RobloxLocaleId`).

## Qué NO está en la arquitectura (a propósito)

- Sin `ModuleScript` que ejecute código desde el cliente en el servidor.
- Sin más remotes que `Invoke` y `Push`.
- Sin dependencias externas en tiempo de ejecución (todo el código es del repositorio).
