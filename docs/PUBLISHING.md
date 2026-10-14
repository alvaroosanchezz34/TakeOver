# Antes de publicar

> **No se ha publicado nada.** Publicar es manual, desde Studio, y es decisión tuya.

## Lista previa (marca cada punto)

**Bloqueantes**

- [ ] Abrir con Rojo en Studio y comprobar que no hay errores en Output al pulsar Play.
- [ ] Probar en *Test > Local Server* con 2–4 jugadores: fundar, mejorar, ofertar, aceptar, ver rankings.
- [ ] Probar en el emulador de dispositivo de Studio (teléfono pequeño, tablet, 16:9): botones
      tocables, nada tapado por la barra superior ni por la zona segura, ventanas con botón cerrar.
- [ ] Publicar el lugar (privado) y activar *Game Settings > Security > Enable Studio Access to API Services*.
- [ ] Jugar, salir y volver: el progreso, las empresas y las participaciones se conservan.
- [ ] Probar dos servidores a la vez con la misma cuenta (bloqueo de sesión): el segundo no debe sobrescribir.
- [ ] Crear los Game Passes/Developer Products y poner sus IDs (`docs/MONETIZATION.md`), o dejarlos en 0.
- [ ] Confirmar que **ningún asset de terceros** es necesario (el juego usa solo código).

**Recomendados**

- [ ] Revisar en Studio que el mapa del distrito se ve bien (luces, edificios, cámara).
- [ ] Comprobar sonidos (`Effects`): si no suenan, las rutas `rbxasset://` hay que sustituirlas por assets propios.
- [ ] Rellenar la página del juego: nombre TAKEOVER, descripción, iconos, miniaturas, clasificación por edades.
- [ ] Revisar políticas de monetización de Roblox y la política de privacidad (la analítica no recoge PII).
- [ ] En el panel de analítica del Creator Dashboard, verificar que llegan el embudo de incorporación
      (`LogOnboardingFunnelStepEvent`), los eventos de economía (`LogEconomyEvent`) y los personalizados.
- [ ] Ejecutar `tools/check.sh` y `python3 tools/mutation_check.py` justo antes de publicar.

## QA manual (guion)

1. **Primer minuto.** Entrar con una cuenta nueva. Debe verse: Cash 100 $, ingresos/s subiendo, la
   siguiente acción recomendada. ¿Se entiende en cinco segundos qué hacer? Cronométralo con alguien nuevo.
2. **Tutorial.** Compra una mejora → mira cómo suben los ingresos → abre el mercado → inspecciona una
   empresa → haz una oferta. Cada paso debe avanzar por la acción, no por texto. Prueba "Omitir".
3. **Tratos.** Con dos cuentas: A ofrece a B; B acepta, rechaza, deja caducar; B cancela. Con el
   precio ≥ 5 000 $ debe pedir confirmación. Con una oferta que cambia al gestor, también.
4. **Control.** Llega a > 50 % de una empresa: avisos de control ganado/perdido, quién gestiona.
5. **Bolsa.** Compra y vende participaciones NPC; comprueba cupos (20 % por jugador) y spread.
6. **Eventos.** `_G.Takeover.forceEvent("tech_boom")` (solo Studio): banner, cuenta atrás, fin.
7. **Móvil.** Teléfono: ventanas modo compacto, texto legible, ningún botón < 44 px, teclado
   no tapa campos, rotación.
8. **Persistencia.** Cerrar y reabrir; matar el servidor a mitad de un guardado (Output).
9. **Idiomas.** Cambiar a EN en Menú > Idioma; no debe quedar ningún texto sin traducir.
10. **Ataques básicos** (solo Studio, tu propio juego): desde la consola del cliente, invocar
    `Invoke` con acciones inexistentes, payloads enormes, `NaN`, precios negativos. Todas deben
    devolver `BAD_REQUEST` sin cambiar nada; abusar debe expulsarte.

## Métricas del primer playtest

| Pregunta | Métrica | Dónde |
| --- | --- | --- |
| ¿Se entiende? | Embudo: `joined` → `first_upgrade` → `market_opened` → `company_inspected` → `first_offer` → `tutorial_done` | Analítica (`Analytics.FUNNEL`) |
| ¿Engancha? | Duración de sesión, retorno D1/D7, reclamaciones de recompensa diaria | Dashboard de Roblox |
| ¿Es social? | Ofertas enviadas/aceptadas por jugador, % de ofertas rechazadas/caducadas, alianzas formadas | `offer_*`, `deal_closed`, `alliance_*` |
| ¿Balance? | Tiempo hasta 1ª mejora / 1ª empresa extra / 1ª participación; distribución de patrimonio; % de jugadores sin gastar | `economy` events |
| ¿Fricción? | Códigos de error más frecuentes (`INSUFFICIENT_FUNDS`, `PRICE_OUT_OF_RANGE`, `RATE_LIMITED`) | `custom` events de error |
| ¿Abuso? | Strikes/expulsiones, tratos entre pares con precios extremos, ganancia por hora anómala | Registro del servidor |
| ¿Estable? | Fallos de guardado (`SAVE_FAILED`, `LOCK_LOST`), tiempo del tick (`Heartbeat`) | Output / `MicroProfiler` |

## Siguientes 3 pasos de mayor impacto

1. **Playtest real con 6–10 personas** (móvil y PC): validar comprensión (embudo), ritmo y UI. Es lo
   único que aporta lo que ningún test puede decir.
2. **Pulir lo que ese playtest señale en la interfaz móvil y en el primer minuto**, y ajustar el
   balance de `Config/*` con los datos del embudo (no a ojo).
3. **Robustecer lo multijugador a escala:** registro idempotente de tratos con reconciliación al
   cargar (cierra el hueco de los dos guardados) y rankings globales con `OrderedDataStore`.
