# Monetización

## Principios (no negociables en el diseño)

- **Solo cosmética y personalización.** Nada de lo que se vende da Cash, ingresos, descuentos,
  mejores precios, probabilidad ni ventaja en un trato. **Pagar no compra la victoria.**
- Ni Robux ni dinero real pueden intercambiarse entre jugadores; el Cash del juego no se vende.
- No hay temporizadores de presión, cajas de botín, ni ofertas "solo hoy" engañosas.
- Todo producto con `id = 0` está **desactivado**: ni se muestra ni se procesa.
  **El repositorio no contiene ningún ID real; no se ha inventado ninguno.**

## Catálogo previsto (`src/shared/Config/Monetization.luau`)

| Clave | Tipo | Qué da | Robux sugeridos* |
| --- | --- | --- | --- |
| `vip_office` | Game Pass | Despachos "dorado" y "neón" (cosmético) | 199 |
| `golden_takeover` | Game Pass | Efecto dorado al cerrar un takeover | 149 |
| `founder_title` | Game Pass | Título "Fundador" | 99 |
| `confetti_pack` | Developer Product | 10 cargas del efecto confeti (consumible cosmético) | 49 |
| `neon_skyline` | Developer Product | 1 carga del horizonte neón (consumible cosmético) | 79 |

\* Orientativos. El precio real se fija en el Creator Dashboard; **valídalos con jugadores reales**.

## Cómo configurarlo (manual, en Roblox)

1. Publica el lugar (*File > Publish to Roblox*).
2. En el **Creator Dashboard** (`create.roblox.com`) abre tu experiencia:
   - *Monetización > Pases*: crea los 3 pases con nombre, descripción, icono y precio.
   - *Monetización > Productos de desarrollador*: crea los 2 productos.
3. Copia el **ID** de cada pase/producto y pégalo en `Monetization.luau` (campo `id`).
   Los pases y productos son cosas distintas: no mezcles sus IDs.
4. Sincroniza con Rojo, prueba en Studio (comprueba en el aviso de compra que es una compra de prueba antes de aceptar) y publica de nuevo.
5. Comprueba en la tienda del juego (Menú > Tienda) que aparece solo lo configurado.

## Cómo funciona por dentro

- **Pases:** al entrar, el servidor llama a `UserOwnsGamePassAsync` y aplica las concesiones. Tras
  una compra (`PromptGamePassPurchaseFinished`) vuelve a comprobarlo **en el servidor**.
- **Productos:** `MarketplaceService.ProcessReceipt` → `Receipts.process`:
  - idempotente por `PurchaseId` (el registro vive en `data.receipts` y se persiste);
  - producto desconocido o desactivado → `NotProcessedYet` (Roblox reintentará);
  - la concesión se **guarda en el DataStore antes de confirmar** `PurchaseGranted`;
  - jugador ausente → `NotProcessedYet` (se procesará cuando vuelva).
- Equipar un cosmético lo valida el servidor (`Receipts.canEquip`): propiedad, o cargas del consumible.
- El cliente nunca concede nada: solo *abre* los avisos de compra de Roblox.

## Probar sin Robux

`tests/spec/ops.spec.luau` cubre: concesión, repetición del mismo `PurchaseId`, producto
desconocido, y equipar sin propiedad. Lo que **no** se ha probado en este entorno: el flujo real de
`MarketplaceService` con Roblox (compra, reintento de recibos, restauración tras caída).
Pruébalo en Studio con un pase/producto de prueba antes de publicar.

## Ideas futuras compatibles con la política

Más despachos y efectos, nombres de empresa con tipografías, skins de edificio, pases de temporada
**solo cosméticos**. No añadir nada que afecte al Cash, a los precios o a la propiedad.
