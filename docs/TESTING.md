# Pruebas

## Cómo ejecutarlas (exacto)

```bash
# Herramientas (una vez)
rokit install            # o: tools/setup.sh && export PATH="$PWD/.tools/bin:$PATH"

# Todo: formato (StyLua) + build Rojo + análisis de tipos (luau-lsp con la API de Roblox) + tests
tools/check.sh

# Solo tests (≈ 7 s)
lune run tests/run
lune run tests/run "texto del nombre"      # filtra por nombre de test (sin "--")

# Comprobación por mutación (≈ 3–4 min): rompe 26 salvaguardas y exige que los tests fallen
python3 tools/mutation_check.py [filtro]

# Simulación de ritmo/balance (informativa, imprime curvas por sector)
lune run tests/sim/pacing

# Prueba de carga con informe de rendimiento
TAKEOVER_LOAD_REPORT=1 lune run tests/run "jugadores jugando"
```

## Qué es cada cosa — y qué NO es

Esto es un **simulador**: ejecuta el código real del servidor y del cliente en Lune con
`Instance`/servicios simulados (`tests/harness/MockInstance`, `Loader`). Sirve para validar lógica,
cableado y flujos. **No sustituye a Roblox Studio ni a jugadores reales.**

| Capa | Qué comprueba | Fiabilidad |
| --- | --- | --- |
| Tests automáticos (Lune) | Reglas de economía, propiedad, tratos, persistencia, protocolo, localización, UI (cableado), carga simulada | Alta para lógica; nula para aspecto visual y latencia real |
| Análisis estático (`luau-lsp`, StyLua, Rojo build) | Tipos con la API de Roblox, formato, que el proyecto se construye | Alta; solo detecta errores de tipos/estructura |
| Auditoría estática de seguridad | Patrones peligrosos en `src/` | Media; por patrones |
| Mutación | Que las salvaguardas críticas están realmente cubiertas | Alta para las 26 salvaguardas elegidas |
| **Manual en Studio / móvil / multijugador real** | Aspecto, táctil, sonidos, iluminación, DataStore, Marketplace, latencia | **Pendiente: no se ha hecho** (ver `docs/PUBLISHING.md`) |

## Resultado actual (verificado en la última ejecución)

- **358 pruebas OK, 0 fallos**, ≈ 7 s.
- `luau-lsp analyze`: sin errores. `stylua --check`: limpio. `rojo build`: genera `build/TakeOver.rbxl`.
- **Mutación: 26/26 detectadas.**
- **Carga:** 30 jugadores × 180 s simulados, 1 045 acciones aleatorias (733 aceptadas) → sin errores internos,
  invariantes intactos cada 10 s, tick más lento ≈ 8 ms (CPU del entorno de pruebas, no de Roblox).

| Spec | Pruebas | Cubre |
| --- | --- | --- |
| `util` | 24 | Result, Table, Signal, RateLimiter, Validate, Format |
| `economy` | 35 | Dinero, ingresos, precios, valoración, sectores, datos extremos |
| `ownership` | 20 | Reparto exacto, gobierno, fuzz de 20 000 transferencias, dividendos |
| `persistence` | 24 | Migraciones, bloqueo de sesión, reintentos, reparación, pérdida de bloqueo |
| `tycoon` | 39 | Empresas, mejoras, niveles, ingresos por tick, tutorial |
| `market` | 46 | Ofertas, aceptación, rollback con fallos inyectados, Bolsa, fuzz de conservación del dinero |
| `social` | 30 | Alianzas, notificaciones, rankings, eventos, logros, recompensa diaria |
| `ops` | 32 | Dispatcher, límites, strikes, recibos, analítica, cosméticos |
| `integration` | 34 | Servidor completo con varios jugadores, privacidad, flujos extremo a extremo |
| `boot` / `world` | 9 / 7 | Arranque real de `Main.server`, mapa generado |
| `locale` / `ui` | 9 / 33 | ES/EN completos, UI cliente + servidor juntos (botones, ventanas, textos, móvil) |
| `security` | 12 | Auditoría estática |
| `load` | 4 | 30 jugadores, tráfico, top 10, ofertas simultáneas |

## Reproducir un fallo

1. `lune run tests/run "fragmento del nombre"` ejecuta solo ese test y muestra el mensaje y la pila.
2. Los tests usan semillas fijas (`Random.new(seed)`): el mismo comando reproduce el mismo caso.
3. Para investigar un trato fallido: `tests/spec/market.spec.luau` inyecta fallos en cada etapa del trato
   mediante el gancho `fault(stage)` de `TradeEngine` y comprueba que el rollback deja todo intacto.
4. Para una partida completa con servidor + cliente: `tests/harness/Stack.luau` (ver `ui.spec.luau`).

## Pruebas manuales que faltan

La lista completa y el guion están en [`PUBLISHING.md`](PUBLISHING.md#qa-manual-guion).
