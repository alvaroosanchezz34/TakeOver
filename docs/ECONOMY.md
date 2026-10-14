# Economía y balance

Todos los números de diseño están en `src/shared/Config/*`. Cámbialos ahí, no en la lógica.
**El balance se ajustó con simulación (`tests/sim/pacing.luau`), no con jugadores reales**:
trátalo como hipótesis inicial y valídalo en el primer playtest (ver `docs/PUBLISHING.md`).

## Cash

- Entero, `0 ≤ Cash ≤ 1e15` (`Money`). Los cálculos con decimales se redondean hacia abajo al
  acreditar y el resto fraccionario se arrastra (`carry`) para no perder ni regalar céntimos.
- Formato compacto (`Format.cash`): `950 $`, `1,25 K $`, `3,40 M $`, `2,15 B $` (ES) y su
  equivalente con punto decimal en EN.
- Comienzo: **100 $**. Bono único de tutorial: **50 $**.

## Ingresos de una empresa

```
ingreso/s = (base del nivel + mejoras planas) × multiplicadores × mecánica de sector
            × evento activo × alianza
```

- `sustained` = el ingreso sin evento ni alianza. **Es la base de la valoración**: un evento
  temporal no infla el precio de una empresa.
- Mecánica de sector (solo afecta a su sector):
  - **Comercio — fidelización:** +1 % por cada 5 min de empresa, hasta +10 %.
  - **Tecnología — hype:** la *valoración* oscila ±12 % (sinusoide); el hype nunca cambia los ingresos.
  - **Industria — escala:** +10 % de ingresos por nivel de empresa.
- Techo de seguridad: `MaxIncomePerSecond = 1e11`.

## Valoración y precios

- `valoración = ingreso sostenido × múltiplo del sector` (Comercio 480, Tecnología 840, Industria 660)
  × hype (solo Tecnología).
- Una participación de `bps` vale `valoración × bps / 10000`.
- Coste de una mejora: `ceil(base × crecimiento^nivel × (1 − descuento))`; el descuento acumulado
  nunca supera el 40 %. La interfaz recomienda la mejora con menor tiempo de amortización.

## Sectores

| | Comercio | Tecnología | Industria |
| --- | --- | --- | --- |
| Fundar | 800 $ (empresa inicial gratis) | 2 500 $, tras ganar 3 000 $ | 12 000 $, tras ganar 25 000 $ |
| Carácter (según simulación) | Techo bajo, estable | Valoración volátil | Mayor ingreso a largo plazo |
| Mecánica | Fidelización | Hype | Escala |

Ritmo simulado (desde 5 000 $, 2 h de juego óptimo): Comercio ≈ 115 $/s, Tecnología ≈ 556 $/s,
Industria ≈ 866 $/s. Máximo 3 empresas propias.

## Propiedad y gobierno

- Reparto en **puntos básicos**: 10 000 = 100 %. `Ownership.validate` exige suma exacta; las
  transferencias se hacen en lotes de 100 pb (1 %). Un test aleatorio de 20 000 transferencias comprueba
  que la suma nunca deriva.
- Niveles: `< 25 %` minoritario (cobra dividendos) · `≥ 25 %` consejero (ve los libros y recibe
  aviso de cambios de control) · `> 50 %` control (gestiona la empresa) · `100 %` propiedad total.
- Sin mayoría gestiona el fundador. El gestor debe conservar al menos el **20 %** (`MinManagerBps`)
  para que la empresa no quede sin gestor viable. Estos umbrales son **parámetros de diseño**.
- Dividendos: cada segundo el ingreso se reparte a los accionistas en proporción; el reparto usa
  un acarreo fraccionario por accionista (sin sesgo de redondeo). Un accionista desconectado
  acumula hasta 30 min de dividendos (`unclaimed`).

## Ofertas entre jugadores

Rango de precio **0,6×–2,5×** el valor de referencia · caducidad **120 s** · máx. 5 salientes / 8
entrantes · impuesto de venta **3 %** (se destruye) · cuenta nueva: 90 s de juego antes de
comerciar · espera de 8 s entre las mismas dos personas y máx. 12 tratos/hora por pareja ·
confirmación explícita si el precio ≥ 5 000 $ o si cambia el gestor · se invalida si la valoración
se desvía > 25 % o cambió la estructura de propiedad.

## Bolsa NPC

Tres empresas de Bolsa (`npc:commerce`, `npc:tech`, `npc:industry`). Los jugadores en conjunto
pueden poseer como máximo el 49 % (el resto queda para el mercado), con un máximo del 20 % por
jugador. Se compra a valoración × 1,05 y se vende a × 0,95. Reparten el 60 % de su beneficio. No
tienen hype, para que no sean una fuente de arbitraje previsible.

## Eventos globales

Sin pérdidas para nadie: todos son bonificaciones temporales y **se anuncian 45 s antes**.

| Evento | Efecto | Duración |
| --- | --- | --- |
| Auge tecnológico | Tecnología ×1,5 ingresos, hype +10 % | 180 s |
| Auge comercial | Comercio ×1,5 | 180 s |
| Escasez industrial | Industria ×1,4 | 180 s |
| Nueva oportunidad | −20 % al coste de mejoras | 240 s |
| Expansión económica | Todos los sectores ×1,25 | 150 s |

Primer evento a los 150 s del arranque; después, entre 360 y 600 s tras el fin del anterior; nunca
el mismo dos veces seguidas.

## Alianzas

Hasta 4 miembros; +3 % de ingresos por aliado conectado, con tope +9 %; 5 min de espera para reunirse.

## Recompensa diaria

Cada 20 h; máx(200 $, 2 min de ingresos) con +10 % por día de racha (máx. 7), con tope de 15 min de ingresos.

## Rangos (por patrimonio)

Startup · Emprendedor (5 K) · Ejecutivo (50 K) · Magnate (1 M) · Tycoon (100 M).
