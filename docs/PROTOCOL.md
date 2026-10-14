# Protocolo cliente ↔ servidor

Solo existen dos objetos en `ReplicatedStorage.TakeoverRemotes`:

- `Invoke` (RemoteFunction): cliente → servidor. `Invoke(action, payload)`.
- `Push` (RemoteEvent): servidor → cliente. Mensajes `{ type = "...", ... }`.

## Respuesta de `Invoke`

```
{ ok = true,  data = ... }
{ ok = false, code = "INSUFFICIENT_FUNDS", params = { missing = 50, need = 100, have = 50 } }
```

El servidor devuelve **códigos**, no frases: el cliente los localiza (`Locale.err`). Un test comprueba que
todo código que el servidor puede emitir tiene texto en ES y EN con los mismos parámetros.

Códigos solo del cliente: `TIMEOUT`, `NETWORK`.

## Acciones (21)

| Acción | Payload | Notas |
| --- | --- | --- |
| `GetState` | — | Foto completa del jugador. `NOT_READY` mientras carga el perfil. |
| `BuyUpgrade` | `companyId, upgradeId` | Solo el gestor. Precio calculado en servidor. |
| `LevelUp` | `companyId` | Solo el gestor. |
| `FoundCompany` | `sector, parts?, logo?` | Requiere haber ganado el mínimo del sector y pagar la fundación. Máx. 3 empresas. |
| `Rename` | `companyId, parts` | Nombre por combinación de partes (sin texto libre). |
| `SetLogo` | `companyId, icon, color` | |
| `GetMarket` | — | Empresas visibles, Bolsa y ofertas del jugador. |
| `InspectCompany` | `companyId` | Más datos si eres consejero/gestor. |
| `MakeOffer` | `companyId, sellerId, bps, price` | `bps` múltiplo de 100; precio dentro de la banda. |
| `RespondOffer` | `offerId, action(accept\|reject\|cancel), confirm?` | `CONFIRMATION_REQUIRED` si hace falta confirmar. |
| `BuyMarket` / `SellMarket` | `companyId, bps, confirm?` / `companyId, bps` | Bolsa NPC con cupos y diferencial. |
| `AllianceInvite` | `targetId` | |
| `AllianceRespond` | `inviteId, accept` | |
| `AllianceLeave` | — | |
| `ClaimDaily` | — | |
| `SkipTutorial` | — | |
| `GetLeaderboard` | — | Top 10 de empresas y de patrimonio. |
| `SetSetting` | `key(sfx\|music\|lang), value` | |
| `SelectTitle` | `id` | Solo títulos propios. |
| `EquipCosmetic` | `slot(effect\|office), id` | Solo cosméticos poseídos. |

Ninguna acción acepta importes de Cash, costes ni "quién soy".

## Mensajes `Push`

| `type` | Contenido |
| --- | --- |
| `state` | Foto del jugador: Cash, ingresos/s, empresas, participaciones, tutorial, evento, ajustes. Al menos cada 5 s y tras cada cambio. |
| `notify` | `{ kind, params }`. Tipos: `achievement`, `alliance_invite`, `alliance_joined`, `alliance_left`, `control_gained`, `control_lost`, `deal_closed`, `event_end`, `event_start`, `offer_accepted`, `offer_cancelled`, `offer_expired`, `offer_failed`, `offer_received`, `offer_rejected`, `purchase_done`, `rank_up`, `tutorial_done`. |
| `offers` | Ofertas pendientes del jugador (entrantes y salientes). |
| `leaderboard` | Top 10 de empresas y de patrimonio (el patrimonio del top 10 es público por diseño) y tu posición. No se envía el Cash ni el patrimonio del resto de jugadores. |
| `event` | Evento global actual y siguiente (con cuenta atrás). |
| `effect` | Efectos públicos (p. ej. un takeover grande) para ambientación. |

## Códigos de error del servidor

`ALLIANCE_COOLDOWN`, `ALLIANCE_FULL`, `ALREADY_IN_ALLIANCE`, `BAD_REQUEST`, `COMPANY_NOT_FOUND`,
`CONFIRMATION_REQUIRED`, `COOLDOWN`, `COSMETIC_NOT_OWNED`, `COSMETIC_UNKNOWN`, `DAILY_NOT_READY`,
`DUPLICATE_INVITE`, `DUPLICATE_OFFER`, `INSUFFICIENT_FUNDS`, `INSUFFICIENT_SHARES`, `INTERNAL`,
`INVALID_AMOUNT`, `INVALID_LOGO`, `INVALID_NAME`, `INVALID_PRICE`, `INVALID_SHARES`,
`INVITE_EXPIRED`, `INVITE_NOT_FOUND`, `LEVEL_CAP`, `MANAGER_STAKE_TOO_LOW`, `MARKET_SOLD_OUT`,
`MAXED`, `NOT_IN_ALLIANCE`, `NOT_MANAGER`, `NOT_READY`, `NOT_YOUR_OFFER`, `OFFER_EXPIRED`,
`OFFER_NOT_FOUND`, `OFFER_NOT_PENDING`, `PAIR_LIMIT`, `PLAYER_CAP`, `PRICE_OUT_OF_RANGE`,
`RATE_LIMITED`, `SAME_PARTIES`, `SECTOR_LOCKED`, `SECTOR_UNKNOWN`, `SELLER_BUSY`, `SELLER_OFFLINE`,
`SELLER_TOO_NEW`, `SLOTS_FULL`, `TARGET_IN_ALLIANCE`, `TARGET_OFFLINE`, `TITLE_NOT_OWNED`,
`TOO_MANY_INVITES`, `TOO_MANY_OFFERS`, `TOO_NEW`, `UPGRADE_UNKNOWN`.

Códigos de carga/guardado (no llegan al cliente como respuesta de acción, solo al registro):
`LOAD_FAILED`, `SESSION_LOCKED`, `LOCK_LOST`, `SAVE_FAILED`, `SAVE_IN_PROGRESS`, `NOT_SERIALIZABLE`,
`DATA_FROM_FUTURE`, `DATA_MIGRATION_FAILED`, `DATA_NO_MIGRATION`, `DATA_VERSION_INVALID`,
`PROFILE_INACTIVE`, `LEFT_DURING_LOAD`, `ALREADY_JOINED`, `CAP_INVARIANT`.

## Límites de frecuencia

Definidos en `src/shared/Config/Limits.luau`: global 40 ráfaga / 20 por s; por acción p. ej.
`BuyUpgrade` 10 / 6 por s, `MakeOffer` 5 / 0,5 por s, `FoundCompany` 2 / 0,2 por s. Superar el límite
devuelve `RATE_LIMITED` y **no** cuenta como infracción; las peticiones mal formadas sí (25 en 60 s
→ expulsión).
