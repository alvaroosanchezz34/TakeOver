# TAKEOVER — *Build. Buy. Dominate.*

Tycoon económico multijugador para Roblox. Empiezas con una pequeña empresa y 100 $ de Cash,
generas ingresos automáticos, mejoras, y compras participaciones en las empresas de otros
jugadores mediante **ofertas voluntarias**. Quien reúne más del 50 % de una empresa la controla.
Compites en rankings de empresas y de patrimonio.

> **Estado:** primera versión funcional **completa a nivel de código y de simulación**. Lo que NO se ha
> podido comprobar en este entorno (Roblox Studio, aspecto visual, multijugador real, móviles,
> DataStore/Marketplace en vivo) está listado sin maquillar en [`STATUS.md`](STATUS.md) y en
> [`docs/PUBLISHING.md`](docs/PUBLISHING.md).

## Qué hay

| Área | Resumen |
| --- | --- |
| Sectores | Comercio (fidelización), Tecnología (hype de valoración), Industria (escala). Mecánicas distintas, no solo números. |
| Economía | Servidor autoritativo. Cash entero ≤ 1 000 000 000 000 000. Ingresos, mejoras y valoración calculados solo en servidor. |
| Propiedad | Reparto en puntos básicos (10 000 = 100 %), siempre suma exacta. Minoritario < 25 %, consejero ≥ 25 %, control > 50 %, propiedad total 100 %. |
| Tratos | Ofertas voluntarias con banda de precio, caducidad, confirmación en tratos grandes, impuesto de venta, transacción atómica con rollback. |
| Bolsa NPC | Empresas de la Bolsa permiten invertir sin depender de otros jugadores (cupos y diferencial de compra/venta). |
| Social | Alianzas (máx. 4), notificaciones, títulos/logros, rankings de empresas y de patrimonio, eventos globales anunciados con antelación. |
| Persistencia | DataStore con esquema versionado, migraciones, bloqueo de sesión, reintentos y reparación de datos. |
| Interfaz | Construida por código, adaptable a PC/tablet/móvil, ES/EN, tutorial guiado por acciones reales. |
| Monetización | Solo cosmética. IDs en `0` (desactivados) hasta que los crees en el Creator Dashboard. |
| Mapa | Distrito de negocios generado por código (`WorldBuilder`). |

## Abrir y ejecutar en Roblox Studio (con Rojo)

Requisitos: Roblox Studio, el plugin de Rojo (7.x) y las herramientas del repo.

```bash
# 1) Herramientas (elige UNA vía)
rokit install                 # si usas Rokit (ver rokit.toml)
# o bien:
tools/setup.sh                # compila/descarga todo en ./.tools (necesita cargo, curl y unzip)
export PATH="$PWD/.tools/bin:$PATH"

# 2) Opción A: sincronización en vivo
rojo serve                    # y pulsa "Connect" en el plugin de Rojo dentro de Studio

# 2) Opción B: generar un lugar
rojo build -o build/TakeOver.rbxl   # y abre build/TakeOver.rbxl en Studio
```

Pulsa **Play** (o *Start* con 2+ jugadores en *Test > Local Server*). En Studio, para que el
progreso se guarde de verdad hay que **publicar el lugar** y activar *Game Settings > Security >
Enable Studio Access to API Services*. Sin eso el juego usa memoria y lo avisa en la consola.

Herramientas de QA (solo existen en Studio): en la barra de comandos del servidor,
`_G.Takeover.giveCash(userId, 50000)` y `_G.Takeover.forceEvent("tech_boom")`.

## Verificar el proyecto

```bash
tools/check.sh              # formato + build Rojo + análisis de tipos + todos los tests
lune run tests/run          # solo los tests
lune run tests/run Bolsa    # solo los tests cuyo nombre contiene "Bolsa"
python3 tools/mutation_check.py   # rompe 26 salvaguardas a propósito y exige que los tests fallen
```

Detalles y resultados en [`docs/TESTING.md`](docs/TESTING.md).

## Estructura

```
src/shared   → ReplicatedStorage.Shared               (config, economía pura, util, protocolo)
src/server   → ServerScriptService.Server             (núcleo autoritativo + servicios Roblox)
src/client   → StarterPlayer.StarterPlayerScripts.Client (solo presentación y peticiones)
tests        → simulador Lune: harness + specs + simulación de ritmo
tools        → setup, check y comprobación por mutación
docs         → arquitectura, economía, seguridad, monetización, protocolo, decisiones, publicación
```

## Documentación

- [`STATUS.md`](STATUS.md) — qué está hecho, qué está verificado y qué no.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — capas, módulos y flujo de una acción.
- [`docs/ECONOMY.md`](docs/ECONOMY.md) — fórmulas, sectores, propiedad, Bolsa, eventos, balance.
- [`docs/SECURITY.md`](docs/SECURITY.md) — modelo de amenazas, defensas y límites conocidos.
- [`docs/MONETIZATION.md`](docs/MONETIZATION.md) — cómo configurar Game Passes y Developer Products.
- [`docs/PROTOCOL.md`](docs/PROTOCOL.md) — acciones, mensajes del servidor y códigos de error.
- [`docs/TESTING.md`](docs/TESTING.md) — qué se prueba, cómo ejecutarlo y qué NO cubre.
- [`docs/DECISIONS.md`](docs/DECISIONS.md) — decisiones de diseño y problemas conocidos.
- [`docs/PUBLISHING.md`](docs/PUBLISHING.md) — lista previa a publicar, QA manual y métricas del primer playtest.

## Publicación

El repositorio no contiene credenciales ni ninguna publicación. **No se ha publicado nada en
Roblox.** Publicar es una decisión tuya y se hace manualmente desde Studio (ver `docs/PUBLISHING.md`).
