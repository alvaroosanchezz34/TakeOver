# Estado del proyecto

Última verificación: ver `docs/TESTING.md`. **Nada de lo marcado «pendiente» se ha comprobado.**

## Hecho y verificado (automático)

- [x] Proyecto Rojo (`default.project.json`) que construye `build/TakeOver.rbxl` sin errores.
- [x] Economía autoritativa (ingresos, mejoras, valoración, tres sectores con mecánica propia).
- [x] Propiedad en puntos básicos con suma exacta; gobierno (minoritario/consejero/control/total).
- [x] Ofertas entre jugadores con transacción atómica, rollback con fallos inyectados, confirmaciones,
      impuesto, límites anti-alts; Bolsa NPC con cupos.
- [x] Persistencia versionada con migraciones, bloqueo de sesión, reintentos y reparación.
- [x] Dispatcher con esquemas, límites de frecuencia y expulsión por abuso; privacidad del Cash ajeno.
- [x] Alianzas, notificaciones, logros/títulos, recompensa diaria, rankings (por servidor), eventos globales.
- [x] Cliente completo en código: HUD, empresa, mercado, ofertas, ranking, menú, tutorial, banner de eventos.
- [x] Localización ES/EN con comprobación automática de claves y parámetros.
- [x] Monetización cosmética con recibos idempotentes (IDs a 0 = desactivada).
- [x] Analítica sin PII (propiedades en lista blanca) y embudo de 6 pasos.
- [x] 358 pruebas automáticas, análisis de tipos, auditoría estática, 26/26 mutaciones detectadas, carga simulada de 30 jugadores.

## Pendiente (requiere Studio / personas / cuentas reales)

- [ ] Ver y ajustar el aspecto visual (UI, mapa, iluminación, sonidos) en Studio.
- [ ] Probar en móvil/tablet reales (o emulador) y con 2+ jugadores reales.
- [ ] Probar DataStore real, cierre de servidor, y dos servidores a la vez.
- [ ] Crear Game Passes / Developer Products y probar el flujo de compra real.
- [ ] Verificar la analítica de Roblox en el Creator Dashboard.
- [ ] Ejecutar el workflow de CI (`.github/workflows/ci.yml`) por primera vez.
- [ ] Playtest con jugadores y ajuste de balance con datos.

## Ver también

[`README.md`](README.md) · [`docs/PUBLISHING.md`](docs/PUBLISHING.md) · [`docs/DECISIONS.md`](docs/DECISIONS.md)
