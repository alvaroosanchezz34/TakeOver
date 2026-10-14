--!strict
--[[
	Textos de la interfaz en español e inglés. Cada texto se define con AMBOS idiomas a la vez,
	así no puede quedar una clave sin traducir. El servidor nunca envía texto de interfaz: envía
	códigos (p. ej. "INSUFFICIENT_FUNDS", kind = "offer_received") y el cliente los traduce aquí.

	Los parámetros se escriben {nombre}; llegan ya formateados (cantidades con Format).
]]

export type Lang = "es" | "en"

local Locale = {}

local es: { [string]: string } = {}
local en: { [string]: string } = {}

local function K(key: string, spanish: string, english: string)
	es[key] = spanish
	en[key] = english
end

-- ───────────── Marca y HUD ─────────────
K("brand.tagline", "Construye. Compra. Domina.", "Build. Buy. Dominate.")
K("hud.cash", "Cash", "Cash")
K("hud.income", "Ingresos", "Income")
K("hud.networth", "Patrimonio", "Net worth")
K("hud.rank", "Puesto", "Rank")
K("hud.rank.value", "#{pos} de {count}", "#{pos} of {count}")
K("hud.companies", "Empresas", "Companies")
K("hud.next", "Siguiente mejora", "Next upgrade")
K("hud.next.missing", "Faltan {amount}", "Need {amount} more")
K("hud.next.ready", "¡Disponible!", "Ready!")
K("hud.next.payback", "Se amortiza en {time}", "Pays back in {time}")
K("hud.next.none", "Todo al máximo: ¡expándete o invierte!", "All maxed: expand or invest!")
K("hud.btn.company", "Empresa", "Company")
K("hud.btn.market", "Mercado", "Market")
K("hud.btn.ranking", "Ranking", "Ranking")
K("hud.btn.menu", "Menú", "Menu")
K("hud.btn.buy", "Comprar", "Buy")
K("hud.loading", "Cargando tu imperio…", "Loading your empire…")
K("hud.offline", "Sin conexión con el servidor", "Disconnected from server")
K("hud.retry", "Reintentar", "Retry")

-- ───────────── Genérico ─────────────
K("common.close", "Cerrar", "Close")
K("common.back", "Atrás", "Back")
K("common.confirm", "Confirmar", "Confirm")
K("common.cancel", "Cancelar", "Cancel")
K("common.accept", "Aceptar", "Accept")
K("common.reject", "Rechazar", "Reject")
K("common.ok", "Entendido", "Got it")
K("common.skip", "Omitir", "Skip")
K("common.max", "MÁX.", "MAX")
K("common.level", "Nivel {n}", "Level {n}")
K("common.loading", "Cargando…", "Loading…")
K("common.you", "Tú", "You")
K("common.market", "Bolsa", "Exchange")
K("common.empty", "Nada por aquí todavía", "Nothing here yet")
K("common.online", "Conectado", "Online")
K("common.offline", "Desconectado", "Offline")
K("common.per_second", "/s", "/s")

-- ───────────── Sectores ─────────────
K("sector.commerce", "Comercio", "Commerce")
K("sector.tech", "Tecnología", "Technology")
K("sector.industry", "Industria", "Industry")
K(
	"sector.commerce.desc",
	"Ingresos estables y mejoras fáciles de entender. Ideal para empezar.",
	"Steady income and easy-to-read upgrades. Great for starting out."
)
K(
	"sector.tech.desc",
	"Crecimiento alto y mejoras caras. Su valoración sube y baja con el ciclo del mercado.",
	"High growth, pricey upgrades. Its valuation swings with the market cycle."
)
K(
	"sector.industry.desc",
	"Gran inversión inicial y un potente crecimiento a medio plazo gracias a la automatización.",
	"Big upfront investment and strong mid-term growth through automation."
)
K(
	"sector.commerce.mech",
	"Lealtad: +1 % de ingresos cada 5 min de sesión (hasta +10 %).",
	"Loyalty: +1% income every 5 min online (up to +10%)."
)
K(
	"sector.tech.mech",
	"Hype: su valoración oscila ±12 % cada ~15 min. ¡Compra barato, vende caro!",
	"Hype: its valuation swings ±12% every ~15 min. Buy low, sell high!"
)
K(
	"sector.industry.mech",
	"Escala: +10 % de ingresos por cada nivel de la empresa.",
	"Scale: +10% income for every company level."
)

-- ───────────── Mejoras ─────────────
K("upgrade.level", "Ampliar empresa", "Expand company")
K("upgrade.commerce.shelves", "Más estanterías", "More shelves")
K("upgrade.commerce.marketing", "Marketing local", "Local marketing")
K("upgrade.commerce.logistics", "Logística", "Logistics")
K("upgrade.commerce.license", "Licencia comercial", "Trade license")
K("upgrade.commerce.facade", "Fachada renovada", "New facade")
K("upgrade.tech.servers", "Servidores", "Servers")
K("upgrade.tech.algorithms", "Algoritmos", "Algorithms")
K("upgrade.tech.research", "I+D", "R&D")
K("upgrade.tech.cloud", "Nube", "Cloud")
K("upgrade.tech.license", "Licencia tecnológica", "Tech license")
K("upgrade.tech.holo", "Oficina holográfica", "Holographic office")
K("upgrade.industry.machines", "Máquinas", "Machines")
K("upgrade.industry.automation", "Automatización", "Automation")
K("upgrade.industry.maintenance", "Mantenimiento", "Maintenance")
K("upgrade.industry.license", "Licencia industrial", "Industrial license")
K("upgrade.industry.plant", "Planta moderna", "Modern plant")
K("effect.flat", "+{v} $/s por nivel", "+{v} $/s per level")
K("effect.mult", "Ingresos ×{v} por nivel", "Income ×{v} per level")
K("effect.discount", "−{v} % en el coste de las mejoras por nivel", "−{v}% upgrade costs per level")
K("effect.capacity", "+{v} niveles máximos de empresa", "+{v} max company levels")
K("effect.look", "Mejora el aspecto (+{v} % ingresos)", "Better look (+{v}% income)")
K(
	"effect.level",
	"Sube de nivel: más ingresos base y mejor aspecto",
	"Level up: more base income and a better look"
)
K("upgrade.gain", "+{v} $/s", "+{v} $/s")
K("upgrade.owned", "Nivel {n}/{max}", "Level {n}/{max}")

-- ───────────── Empresa ─────────────
K("company.title", "Tu empresa", "Your company")
K("company.valuation", "Valoración", "Valuation")
K("company.income", "Ingresos", "Income")
K("company.owner", "Propietario original", "Original owner")
K("company.manager", "Gestiona", "Managed by")
K("company.ownership", "Propiedad", "Ownership")
K("company.history", "Operaciones", "Operations")
K("company.upgrades", "Mejoras", "Upgrades")
K("company.found", "Fundar empresa", "Found company")
K("company.found.cost", "Coste: {cost}", "Cost: {cost}")
K(
	"company.found.locked",
	"Gana {need} en total para desbloquear (llevas {have})",
	"Earn {need} in total to unlock (you have {have})"
)
K("company.found.slots", "Empresas: {n}/{max}", "Companies: {n}/{max}")
K("company.rename", "Renombrar", "Rename")
K("company.logo", "Logotipo", "Logo")
K(
	"company.style.hint",
	"Elige entre opciones seguras: no se admite texto libre.",
	"Pick from safe presets: free text isn't allowed."
)
K("company.hype", "Hype del mercado", "Market hype")
K(
	"company.not_managed",
	"Sólo quien gestiona puede comprar mejoras. Para gestionar necesitas más del 50 %.",
	"Only the manager can buy upgrades. You need over 50% to manage."
)
K("company.books", "Libros", "Books")
K("company.books.locked", "Necesitas el 25 % para ver los libros", "You need 25% to see the books")
K("company.stake", "Tu participación: {pct}", "Your stake: {pct}")
K("company.sell_to", "Hacer una oferta a {name}", "Make an offer to {name}")
K("company.history.founded", "Empresa fundada", "Company founded")
K(
	"company.history.trade",
	"{buyer} compró {pct} a {seller} por {price}",
	"{buyer} bought {pct} from {seller} for {price}"
)
K("company.history.upgrade", "Mejora comprada ({note})", "Upgrade bought ({note})")
K("company.history.level", "Nivel {note}", "Level {note}")
K("company.history.rename", "Nuevo nombre: {note}", "New name: {note}")
K("company.history.style", "Nuevo logotipo", "New logo")

-- ───────────── Gobernanza (reglas públicas) ─────────────
K("gov.title", "Reglas de control", "Control rules")
K(
	"gov.minority",
	"Inversor minoritario (< 25 %): cobras dividendos.",
	"Minority investor (< 25%): you earn dividends."
)
K(
	"gov.board",
	"Consejero (≥ 25 %): además ves los libros de la empresa.",
	"Board member (≥ 25%): you also see the company's books."
)
K(
	"gov.control",
	"Control (> 50 %): tú gestionas la empresa: mejoras, nombre y logotipo.",
	"Control (> 50%): you manage the company: upgrades, name and logo."
)
K("gov.full", "Propiedad completa (100 %).", "Full ownership (100%).")
K(
	"gov.manager_floor",
	"Sin mayoría, gestiona el fundador, que debe conservar al menos el {pct}.",
	"Without a majority the founder manages and must keep at least {pct}."
)
K("tier.none", "Sin participación", "No stake")
K("tier.minority", "Minoritario", "Minority")
K("tier.board", "Consejero", "Board")
K("tier.control", "Control", "Control")
K("tier.full", "Propietario", "Owner")

-- ───────────── Mercado y negociación ─────────────
K("market.title", "Mercado", "Market")
K("market.tab.companies", "Empresas", "Companies")
K("market.tab.portfolio", "Mi cartera", "My portfolio")
K("market.tab.offers", "Ofertas", "Offers")
K("market.tab.people", "Jugadores", "Players")
K("market.tab.deals", "Operaciones", "Deals")
K("market.exchange", "Empresas de la Bolsa", "Exchange companies")
K("market.players_companies", "Empresas de jugadores", "Player companies")
K("market.valuation", "Valoración: {v}", "Valuation: {v}")
K("market.price_per_pct", "{v} por 1 %", "{v} per 1%")
K("market.buy_exchange", "Comprar a la Bolsa", "Buy from exchange")
K("market.sell_exchange", "Vender a la Bolsa", "Sell to exchange")
K("market.exchange.ask", "Precio de compra: {v} por 1 %", "Buy price: {v} per 1%")
K("market.exchange.bid", "Precio de venta: {v} por 1 %", "Sell price: {v} per 1%")
K("market.exchange.float", "Disponible: {pct}", "Available: {pct}")
K("market.exchange.cap", "Máximo por jugador: {pct}", "Max per player: {pct}")
K(
	"market.exchange.hint",
	"La Bolsa siempre compra y vende, con diferencial. Nadie puede controlarla.",
	"The exchange always buys and sells, with a spread. Nobody can control it."
)
K(
	"market.empty_portfolio",
	"Aún no tienes participaciones. ¡Invierte en una empresa!",
	"You hold no stakes yet. Invest in a company!"
)
K(
	"market.portfolio.offline",
	"Fundador desconectado: valor del último dato",
	"Founder offline: last known value"
)
K("market.no_offers", "No tienes ofertas pendientes.", "You have no pending offers.")
K("market.no_deals", "Todavía no hay operaciones.", "No deals yet.")
K(
	"market.people.hint",
	"Toca a un jugador para ver sus empresas o invitarle a una alianza.",
	"Tap a player to see their companies or invite them to an alliance."
)
K(
	"market.rules",
	"Banda de precios: entre {min}× y {max}× del valor. Impuesto de venta: {tax}.",
	"Price band: {min}× to {max}× of fair value. Sales tax: {tax}."
)

K("offer.new", "Nueva oferta", "New offer")
K("offer.to", "Vendedor", "Seller")
K("offer.from", "Comprador", "Buyer")
K("offer.company", "Empresa", "Company")
K("offer.stake", "Participación", "Stake")
K("offer.price", "Precio total", "Total price")
K("offer.fair", "Valor de referencia", "Reference value")
K("offer.premium", "{pct} sobre el valor", "{pct} above value")
K("offer.discount", "{pct} bajo el valor", "{pct} below value")
K("offer.fair_price", "Precio justo", "Fair price")
K("offer.tax", "Impuesto de venta: {v}", "Sales tax: {v}")
K("offer.receive", "El vendedor recibirá {v}", "Seller receives {v}")
K("offer.expires", "Caduca en {time}", "Expires in {time}")
K("offer.send", "Enviar oferta", "Send offer")
K("offer.cancel", "Retirar oferta", "Withdraw offer")
K("offer.incoming", "Ofertas recibidas", "Offers received")
K("offer.outgoing", "Ofertas enviadas", "Offers sent")
K("offer.waiting", "Esperando respuesta de {name}", "Waiting for {name}")
K("offer.wants", "{name} quiere comprar {pct} de {company}", "{name} wants to buy {pct} of {company}")
K("offer.conditions", "Condiciones", "Conditions")
K(
	"offer.cond.atomic",
	"Si aceptas, el dinero y las participaciones se transfieren a la vez o no se transfiere nada.",
	"If you accept, money and shares move together or not at all."
)
K(
	"offer.cond.revalidated",
	"Se vuelve a comprobar todo en el servidor al aceptar.",
	"Everything is re-checked on the server when you accept."
)
K(
	"offer.control_warning",
	"⚠ Con este trato cambia quién gestiona la empresa.",
	"⚠ This deal changes who manages the company."
)
K("offer.confirm.title", "Confirma la operación", "Confirm the deal")
K("offer.confirm.big", "Es una operación importante. ¿Seguro?", "This is a big deal. Are you sure?")
K(
	"offer.confirm.buy",
	"Vas a pagar {price} por {pct} de {company}.",
	"You'll pay {price} for {pct} of {company}."
)
K(
	"offer.confirm.sell",
	"Vas a vender {pct} de {company} y recibirás {receive}.",
	"You'll sell {pct} of {company} and receive {receive}."
)
K("offer.needs_funds", "Te faltan {missing} para esta oferta", "You're {missing} short for this offer")
K("offer.pick_amount", "Porcentaje", "Percentage")
K("offer.pick_price", "Precio", "Price")
K("offer.price.min", "Mín. {v}", "Min {v}")
K("offer.price.max", "Máx. {v}", "Max {v}")
K("offer.quick.fair", "Justo", "Fair")
K("offer.quick.low", "Bajo", "Low")
K("offer.quick.high", "Alto", "High")

K("people.invite", "Invitar a alianza", "Invite to alliance")
K("people.companies", "Ver empresas", "View companies")
K(
	"people.no_others",
	"Eres el único en el servidor. ¡Invita a un amigo!",
	"You're alone on the server. Invite a friend!"
)

-- ───────────── Alianzas ─────────────
K("alliance.title", "Alianza", "Alliance")
K("alliance.members", "Miembros", "Members")
K("alliance.bonus", "Bono de ingresos: +{pct}", "Income bonus: +{pct}")
K(
	"alliance.hint",
	"+3 % de ingresos por aliado conectado (tope +9 %). No impide negociar con nadie.",
	"+3% income per connected ally (cap +9%). It never stops you trading with anyone."
)
K("alliance.leave", "Salir de la alianza", "Leave alliance")
K("alliance.none", "No estás en ninguna alianza.", "You're not in an alliance.")
K("alliance.invites", "Invitaciones", "Invitations")
K("alliance.invite_from", "{name} te invita a su alianza", "{name} invites you to their alliance")

-- ───────────── Ranking ─────────────
K("ranking.title", "Clasificación", "Leaderboard")
K("ranking.companies", "Mayores empresas", "Top companies")
K("ranking.players", "Mayores magnates", "Top tycoons")
K("ranking.you", "Tu puesto", "Your rank")
K("rank.startup", "Emprendedor novel", "Startup")
K("rank.entrepreneur", "Empresario", "Entrepreneur")
K("rank.executive", "Ejecutivo", "Executive")
K("rank.magnate", "Magnate", "Magnate")
K("rank.tycoon", "Tycoon", "Tycoon")

-- ───────────── Eventos ─────────────
K("event.tech_boom", "Auge tecnológico", "Tech boom")
K("event.commerce_boom", "Boom comercial", "Commerce boom")
K("event.industry_shortage", "Escasez industrial", "Industrial shortage")
K("event.new_opportunity", "Nueva oportunidad", "New opportunity")
K("event.economic_expansion", "Expansión económica", "Economic expansion")
K(
	"event.tech_boom.desc",
	"Ingresos tecnológicos ×1,5 y el mercado se entusiasma con el sector.",
	"Tech income ×1.5 and the market gets excited about the sector."
)
K("event.commerce_boom.desc", "Ingresos del comercio ×1,5.", "Commerce income ×1.5.")
K(
	"event.industry_shortage.desc",
	"Los suministros escasean: ingresos industriales ×1,4.",
	"Supplies run short: industrial income ×1.4."
)
K(
	"event.new_opportunity.desc",
	"Contratos con proveedores: −20 % en todas las mejoras.",
	"Supplier contracts: −20% on all upgrades."
)
K("event.economic_expansion.desc", "Todos los sectores ×1,25.", "All sectors ×1.25.")
K("event.next", "Próximo evento: {name}", "Next event: {name}")
K("event.starts_in", "empieza en {time}", "starts in {time}")
K("event.active", "{name} · quedan {time}", "{name} · {time} left")
K("event.none", "Sin eventos activos", "No active events")
K("event.rule", "Los eventos nunca te quitan dinero.", "Events never take your money.")

-- ───────────── Tutorial ─────────────
K("tutorial.title", "Primeros pasos", "Getting started")
K("tutorial.step", "Paso {n} de {total}", "Step {n} of {total}")
K(
	"tutorial.buy_upgrade",
	"Compra tu primera mejora para ganar más dinero.",
	"Buy your first upgrade to earn more."
)
K(
	"tutorial.see_income",
	"¡Mira cómo suben tus ingresos! Sigue ganando mientras juegas.",
	"Watch your income grow! You keep earning while you play."
)
K(
	"tutorial.open_market",
	"Abre el Mercado: ahí compras participaciones de otras empresas.",
	"Open the Market: that's where you buy stakes in other companies."
)
K("tutorial.inspect_company", "Toca una empresa para inspeccionarla.", "Tap a company to inspect it.")
K(
	"tutorial.first_offer",
	"Compra una participación a la Bolsa o haz una oferta a otro jugador.",
	"Buy a stake from the exchange or make an offer to another player."
)
K("tutorial.done", "¡Tutorial completado! Bonus: {reward}", "Tutorial complete! Bonus: {reward}")
K("tutorial.skip", "Omitir tutorial", "Skip tutorial")

-- ───────────── Menú / ajustes ─────────────
K("menu.title", "Menú", "Menu")
K("menu.sfx", "Efectos de sonido", "Sound effects")
K("menu.music", "Música", "Music")
K("menu.language", "Idioma", "Language")
K("menu.language.auto", "Automático", "Automatic")
K("menu.language.es", "Español", "Español")
K("menu.language.en", "English", "English")
K("menu.daily", "Recompensa diaria", "Daily reward")
K("menu.daily.ready", "¡Lista! Toca para reclamar", "Ready! Tap to claim")
K("menu.daily.wait", "Disponible en {time}", "Available in {time}")
K("menu.daily.streak", "Racha: {n} días", "Streak: {n} days")
K("menu.titles", "Títulos", "Titles")
K("menu.title.none", "Sin título", "No title")
K("menu.stats", "Estadísticas", "Stats")
K("menu.stat.earned", "Ganado en total", "Total earned")
K("menu.stat.peak", "Patrimonio máximo", "Peak net worth")
K("menu.stat.deals", "Tratos cerrados", "Deals closed")
K("menu.stat.upgrades", "Mejoras compradas", "Upgrades bought")
K("menu.stat.time", "Tiempo jugado", "Time played")
K("menu.cosmetics", "Cosméticos", "Cosmetics")
K("menu.shop", "Tienda", "Shop")
K("menu.shop.empty", "La tienda abrirá pronto.", "The shop opens soon.")
K(
	"menu.shop.fair",
	"Sólo cosméticos: pagar nunca te da ventaja económica.",
	"Cosmetics only: paying never gives an economic edge."
)
K("menu.alliance", "Alianza", "Alliance")

-- ───────────── Cosméticos y tienda ─────────────
K("cosmetic.fx_default", "Efecto estándar", "Standard effect")
K("cosmetic.fx_confetti", "Confeti", "Confetti")
K("cosmetic.fx_golden", "Toma de control dorada", "Golden takeover")
K("cosmetic.office_default", "Oficina estándar", "Standard office")
K("cosmetic.office_gold", "Oficina dorada", "Golden office")
K("cosmetic.office_neon", "Oficina neón", "Neon office")
K("shop.vip_office", "Pack de oficinas VIP", "VIP office pack")
K(
	"shop.vip_office.desc",
	"Oficinas doradas y neón para tu empresa. Sólo cosmético.",
	"Golden and neon offices for your company. Cosmetic only."
)
K("shop.golden_takeover", "Toma de control dorada", "Golden takeover")
K(
	"shop.golden_takeover.desc",
	"Un efecto exclusivo cuando tomas el control de una empresa.",
	"An exclusive effect when you take over a company."
)
K("shop.founder_title", "Título «Fundador»", "“Founder” title")
K("shop.founder_title.desc", "Un título especial junto a tu nombre.", "A special title next to your name.")
K("shop.confetti_pack", "Pack de confeti (x10)", "Confetti pack (x10)")
K(
	"shop.confetti_pack.desc",
	"10 usos del efecto confeti al cerrar un trato.",
	"10 uses of the confetti effect when you close a deal."
)
K("shop.neon_skyline", "Skyline neón", "Neon skyline")
K(
	"shop.neon_skyline.desc",
	"Ilumina tu parcela con neón durante un rato.",
	"Light up your plot with neon for a while."
)

-- ───────────── Logros y títulos ─────────────
K("ach.first_upgrade", "Primera mejora", "First upgrade")
K("ach.first_deal", "Primer trato", "First deal")
K("ach.first_takeover", "Primera adquisición", "First takeover")
K("ach.diversified", "Imperio diversificado", "Diversified empire")
K("ach.shareholder", "Accionista", "Shareholder")
K("ach.millionaire", "Millonario", "Millionaire")
K("ach.number_one", "Número uno", "Number one")
K("ach.founder", "Fundador", "Founder")
K("title.first_upgrade", "Primera mejora", "First upgrade")
K("title.first_deal", "Negociador", "Dealmaker")
K("title.first_takeover", "Adquisidor", "Acquirer")
K("title.diversified", "Diversificado", "Diversified")
K("title.shareholder", "Accionista", "Shareholder")
K("title.millionaire", "Millonario", "Millionaire")
K("title.number_one", "Número uno", "Number one")
K("title.founder", "Fundador", "Founder")

-- ───────────── Notificaciones ─────────────
K(
	"notify.offer_received",
	"{from} te ofrece comprar {bps} de {company} por {price}",
	"{from} offers to buy {bps} of {company} for {price}"
)
K(
	"notify.offer_accepted",
	"{seller} aceptó: compraste {bps} de {company} por {price}",
	"{seller} accepted: you bought {bps} of {company} for {price}"
)
K(
	"notify.offer_rejected",
	"{seller} rechazó tu oferta por {company}",
	"{seller} rejected your offer for {company}"
)
K("notify.offer_cancelled", "Una oferta se canceló", "An offer was cancelled")
K("notify.offer_expired", "Una oferta por {company} caducó", "An offer for {company} expired")
K("notify.offer_failed", "La operación no se pudo completar", "The deal couldn't be completed")
K(
	"notify.deal_closed",
	"Vendiste {bps} de {company} a {buyer} y recibiste {received}",
	"You sold {bps} of {company} to {buyer} and received {received}"
)
K("notify.control_gained", "¡Ahora gestionas {company}!", "You now manage {company}!")
K("notify.control_lost", "Has perdido la gestión de {company}", "You no longer manage {company}")
K("notify.alliance_invite", "{from} te invita a una alianza", "{from} invites you to an alliance")
K("notify.alliance_joined", "{name} se unió a tu alianza", "{name} joined your alliance")
K("notify.alliance_left", "{name} dejó la alianza", "{name} left the alliance")
K("notify.event_announce", "Próximo evento: {name} ({time})", "Next event: {name} ({time})")
K("notify.event_start", "¡Empieza {name}!", "{name} starts now!")
K("notify.event_end", "Terminó {name}", "{name} is over")
K("notify.achievement", "Logro desbloqueado: {name}", "Achievement unlocked: {name}")
K("notify.tutorial_done", "¡Tutorial completado! +{reward}", "Tutorial complete! +{reward}")
K(
	"notify.daily_claimed",
	"Recompensa diaria: +{reward} (racha {streak})",
	"Daily reward: +{reward} (streak {streak})"
)
K(
	"notify.market_liquidation",
	"El cupo de la Bolsa estaba lleno: tu participación se vendió por {cash}",
	"The exchange was full: your stake was sold for {cash}"
)
K("notify.rank_up", "¡Subes a {badge}!", "You've reached {badge}!")
K(
	"notify.purchase_done",
	"¡Compra completada! Gracias por apoyar el juego.",
	"Purchase complete! Thanks for supporting the game."
)
K("notify.income_reward", "+{v}", "+{v}")
K("fx.takeover", "⚡ {who} ha tomado el control de {company}", "⚡ {who} took control of {company}")
K(
	"fx.deal",
	"🤝 {who} cierra una gran operación sobre {company}",
	"🤝 {who} closes a big deal on {company}"
)
K("fx.new_number_one", "👑 {who} es el nuevo número uno", "👑 {who} is the new number one")
K("fx.new_magnate", "💎 {who} se ha convertido en magnate", "💎 {who} became a magnate")

-- ───────────── Errores (códigos del servidor) ─────────────
K("err.UNKNOWN", "Algo ha fallado. Inténtalo de nuevo.", "Something went wrong. Please try again.")
K(
	"err.INSUFFICIENT_FUNDS",
	"No tienes suficiente dinero: te faltan {missing}.",
	"Not enough money: you need {missing} more."
)
K(
	"err.COMPANY_NOT_FOUND",
	"Esa empresa ya no está disponible (¿su fundador se fue?).",
	"That company is no longer available (did its founder leave?)."
)
K(
	"err.NOT_MANAGER",
	"Sólo quien gestiona la empresa puede hacer esto.",
	"Only the company's manager can do that."
)
K("err.UPGRADE_UNKNOWN", "Esa mejora no existe.", "That upgrade doesn't exist.")
K("err.MAXED", "Esa mejora ya está al máximo.", "That upgrade is already maxed.")
K(
	"err.LEVEL_CAP",
	"Tu empresa está en su nivel máximo. Compra una licencia para ampliar el tope.",
	"Your company is at its level cap. Buy a license to raise it."
)
K("err.SECTOR_UNKNOWN", "Sector desconocido.", "Unknown sector.")
K(
	"err.SLOTS_FULL",
	"Ya tienes el máximo de empresas ({max}).",
	"You already have the maximum number of companies ({max})."
)
K(
	"err.SECTOR_LOCKED",
	"Sector bloqueado: necesitas haber ganado {need} en total.",
	"Sector locked: you need to have earned {need} in total."
)
K("err.INVALID_NAME", "Ese nombre no es válido.", "That name isn't valid.")
K("err.INVALID_LOGO", "Ese logotipo no es válido.", "That logo isn't valid.")
K(
	"err.COOLDOWN",
	"Espera {seconds} s antes de volver a cambiarlo.",
	"Wait {seconds}s before changing it again."
)
K(
	"err.INVALID_SHARES",
	"Esa participación no es válida (usa múltiplos del 1 %).",
	"That stake isn't valid (use multiples of 1%)."
)
K("err.INVALID_PRICE", "Ese precio no es válido.", "That price isn't valid.")
K("err.SELLER_OFFLINE", "El vendedor no está en el servidor.", "The seller isn't on the server.")
K("err.SAME_PARTIES", "No puedes hacer esto contigo mismo.", "You can't do this with yourself.")
K(
	"err.INSUFFICIENT_SHARES",
	"El vendedor no tiene tantas participaciones.",
	"The seller doesn't hold that much."
)
K(
	"err.MANAGER_STAKE_TOO_LOW",
	"Con este trato la empresa se quedaría sin un gestor con al menos el {pct}.",
	"This deal would leave the company without a manager holding at least {pct}."
)
K(
	"err.PRICE_OUT_OF_RANGE",
	"El precio debe estar entre {min} y {max}.",
	"The price must be between {min} and {max}."
)
K(
	"err.TOO_NEW",
	"Juega un poco más antes de comerciar ({remaining} s).",
	"Play a bit longer before trading ({remaining}s)."
)
K(
	"err.SELLER_TOO_NEW",
	"El vendedor aún no puede comerciar (cuenta nueva).",
	"The seller can't trade yet (new account)."
)
K(
	"err.PAIR_COOLDOWN",
	"Espera {seconds} s antes de volver a negociar con esta persona.",
	"Wait {seconds}s before trading with this person again."
)
K(
	"err.PAIR_LIMIT",
	"Demasiados tratos con esta persona. Prueba más tarde.",
	"Too many deals with this person. Try again later."
)
K(
	"err.DUPLICATE_OFFER",
	"Ya tienes una oferta igual pendiente.",
	"You already have an identical pending offer."
)
K(
	"err.TOO_MANY_OFFERS",
	"Tienes demasiadas ofertas pendientes (máx. {max}).",
	"You have too many pending offers (max {max})."
)
K(
	"err.SELLER_BUSY",
	"El vendedor tiene demasiadas ofertas pendientes.",
	"The seller has too many pending offers."
)
K("err.OFFER_NOT_FOUND", "Esa oferta ya no existe.", "That offer no longer exists.")
K("err.OFFER_NOT_PENDING", "Esa oferta ya fue resuelta.", "That offer has already been resolved.")
K("err.NOT_YOUR_OFFER", "Esa oferta no es tuya.", "That offer isn't yours.")
K("err.OFFER_EXPIRED", "La oferta ha caducado.", "The offer has expired.")
K(
	"err.STALE_OFFER",
	"Los datos cambiaron desde la oferta. Pídele que la renueve.",
	"Things changed since the offer. Ask for a fresh one."
)
K("err.PARTY_LEFT", "La otra parte se ha ido del servidor.", "The other party left the server.")
K("err.CONFIRMATION_REQUIRED", "Confirma la operación para continuar.", "Confirm the deal to continue.")
K(
	"err.MARKET_SOLD_OUT",
	"La Bolsa ya no tiene participaciones disponibles.",
	"The exchange has nothing left to sell."
)
K(
	"err.PLAYER_CAP",
	"Has alcanzado tu límite de participación en esa empresa ({max}).",
	"You've reached your stake limit in that company ({max})."
)
K("err.INTERNAL", "Error del servidor. No se ha cobrado nada.", "Server error. You weren't charged.")
K("err.BAD_REQUEST", "Petición no válida.", "Invalid request.")
K("err.RATE_LIMITED", "Vas demasiado rápido. Espera un momento.", "You're going too fast. Wait a moment.")
K("err.NOT_READY", "Tus datos aún se están cargando.", "Your data is still loading.")
K(
	"err.TIMEOUT",
	"El servidor tarda en responder. Inténtalo otra vez.",
	"The server is slow to respond. Try again."
)
K("err.NETWORK", "Problema de conexión.", "Connection problem.")
K("err.DAILY_NOT_READY", "La recompensa diaria aún no está lista.", "The daily reward isn't ready yet.")
K("err.TITLE_NOT_OWNED", "Aún no tienes ese título.", "You don't have that title yet.")
K("err.COSMETIC_UNKNOWN", "Ese cosmético no existe.", "That cosmetic doesn't exist.")
K("err.COSMETIC_NOT_OWNED", "Aún no tienes ese cosmético.", "You don't own that cosmetic yet.")
K("err.TARGET_OFFLINE", "Ese jugador no está en el servidor.", "That player isn't on the server.")
K("err.TARGET_IN_ALLIANCE", "Ese jugador ya está en una alianza.", "That player is already in an alliance.")
K(
	"err.ALLIANCE_COOLDOWN",
	"Espera un poco antes de unirte a otra alianza.",
	"Wait a bit before joining another alliance."
)
K("err.ALLIANCE_FULL", "La alianza está completa (máx. {max}).", "The alliance is full (max {max}).")
K("err.DUPLICATE_INVITE", "Ya le has invitado.", "You've already invited them.")
K(
	"err.TOO_MANY_INVITES",
	"Tienes demasiadas invitaciones pendientes.",
	"You have too many pending invitations."
)
K("err.INVITE_NOT_FOUND", "Esa invitación ya no existe.", "That invitation no longer exists.")
K("err.INVITE_EXPIRED", "La invitación ha caducado.", "The invitation has expired.")
K("err.ALREADY_IN_ALLIANCE", "Ya estás en una alianza.", "You're already in an alliance.")
K("err.NOT_IN_ALLIANCE", "No estás en ninguna alianza.", "You're not in an alliance.")
K("err.INVALID_AMOUNT", "Cantidad no válida.", "Invalid amount.")
K("err.CAP_INVARIANT", "Error de propiedad: operación cancelada.", "Ownership error: deal cancelled.")
K("err.ABUSE", "Actividad anómala detectada.", "Unusual activity detected.")

Locale.es = es
Locale.en = en

local function interpolate(text: string, params: { [string]: any }?): string
	if params == nil then
		return text
	end
	local out = string.gsub(text, "{([%w_]+)}", function(name)
		local v = params[name]
		if v == nil then
			return "{" .. name .. "}"
		end
		return tostring(v)
	end)
	return out
end

function Locale.has(lang: Lang, key: string): boolean
	local tbl = if lang == "es" then es else en
	return tbl[key] ~= nil
end

function Locale.t(lang: Lang, key: string, params: { [string]: any }?): string
	local tbl = if lang == "es" then es else en
	local text = tbl[key] or en[key] or es[key]
	if text == nil then
		return key
	end
	return interpolate(text, params)
end

-- Mensaje para un código de error del servidor.
function Locale.err(lang: Lang, code: string?, params: { [string]: any }?): string
	if code ~= nil and Locale.has(lang, "err." .. code) then
		return Locale.t(lang, "err." .. code, params)
	end
	return Locale.t(lang, "err.UNKNOWN", params)
end

function Locale.keys(): { string }
	local out = {}
	for k in es do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

return Locale
