--!nocheck
local MockInstance = require("../harness/MockInstance")
local Stack = require("../harness/Stack")

return function(t, load)
	local Balance = load:shared("Config/Balance")
	local Ownership = load:shared("Economy/Ownership")
	local Format = load:shared("Util/Format")
	local Enum = load.Enum
	local Vector2 = load.Vector2

	local function veteran(cash, extra)
		return function(d)
			d.cash = cash
			d.stats.playSeconds = 99999
			d.stats.totalEarned = 50000
			d.tutorial.done = true
			if extra then
				extra(d)
			end
		end
	end

	local function onlyWindowOpen(s, id)
		local gui = s:gui():FindFirstChild("Takeover_windows")
		local open = {}
		for _, child in gui:GetChildren() do
			if child.Name:sub(1, 7) == "Window_" then
				table.insert(open, child.Name)
			end
		end
		if id then
			t:expect(open):toEqual({ "Window_" .. id })
		end
		return open
	end

	t:describe("HUD y primera impresión", function()
		t:test("entra, muestra Cash, ingresos y la mejora recomendada: se entiende qué hacer", function()
			local s = Stack.new()
			s:join(101, "Ana", true)
			t:expect(s:find("Loading").Visible):toBe(false)
			t:expect(s:text("CashValue")):toBe("$100")
			t:expect(s:text("IncomeValue")):toBe("+$1/s")
			t:expect(s:text("NextName")):toContain("More shelves")
			t:expect(s:text("NextName")):toContain("$20")
			t:expect(s:text("NextEffect")):toContain("+0.7 $/s per level")
			t:expect(s:text("NextStatus")):toBe("Ready!")
			t:expect(s:text("RankValue")):toBe("#1 of 1")
			t:expect(s:find("BuyButton").Visible):toBe(true)
			-- el tutorial guía y la acción está resaltada
			t:expect(s:find("TutorialCard").Visible):toBe(true)
			t:expect(s:text("TutorialText")):toContain("first upgrade")
			t:expect(s:find("PulseStroke", s:find("BuyButton")) ~= nil):toBe(true)
		end)

		t:test(
			"pulsar Comprar gasta el Cash en el servidor, sube los ingresos y avanza el tutorial",
			function()
				local s = Stack.new()
				s:join(101, "Ana", true)
				s:step(1)
				local session = s.server.world.sessions["101"]
				local before = session.data.cash
				s:click("BuyButton")
				t:expect(session.data.cash):toBe(before - 20)
				t:expect(session.data.companies["101:1"].upgrades.shelves):toBe(1)
				t:expect(s:text("CashValue")):toBe("$" .. tostring(before - 20))
				t:expect(s:text("IncomeValue")):toBe("+$1.7/s")
				t:expect(session.data.tutorial.step):toBe(2)
				t:expect(s:text("TutorialText")):toContain("income grow")
			end
		)

		t:test("sin dinero suficiente: el botón está bloqueado y dice cuánto falta", function()
			local s = Stack.new()
			s:join(101, "Ana", true, function(d)
				d.cash = 5
			end)
			s:step(1)
			t:expect(s:text("NextStatus")):toContain("Need")
			t:expect(s:find("BuyButton"):GetAttribute("Enabled")):toBe(false)
			-- pulsarlo no hace nada en el servidor
			s:click("BuyButton")
			t:expect(s.server.world.sessions["101"].data.cash >= 5):toBe(true)
			t:expect(s.server.world.sessions["101"].data.companies["101:1"].upgrades.shelves):toBeNil()
		end)

		t:test("los ingresos hacen subir el Cash mostrado entre fotos del servidor", function()
			local s = Stack.new()
			s:join(101, "Ana", true)
			s:step(1)
			local before = s:text("CashValue")
			s:step(3)
			t:expect(s:text("CashValue") ~= before):toBe(true)
		end)

		t:test("los valores visuales coinciden con los del servidor", function()
			local s = Stack.new()
			s:join(101, "Ana", true, veteran(12345))
			s:step(2)
			local session = s.server.world.sessions["101"]
			local app = s.l:client("App")
			local shown = app.store.state -- última foto que el servidor envió
			t:expect(shown.cash >= 12345):toBe(true)
			t:expect(shown.cash <= session.data.cash):toBe(true) -- la foto no puede ir por delante
			t:expect(s:text("CashValue")):toBe(Format.cash(app.store:displayCash(), "en"))
			t:expect(s:text("IncomeValue")):toBe("+" .. Format.rate(shown.incomePerSecond, "en"))
			t:expect(s:text("NetWorth")):toContain(Format.cash(shown.netWorth, "en"))
			-- el servidor corrige: tras forzar una foto, el HUD refleja el Cash real
			session.data.cash = 777
			s.server:pushState(session)
			t:expect(app.store.state.cash):toBe(777)
		end)
	end)

	t:describe("Ventanas", function()
		t:test("las cuatro ventanas se abren desde el HUD, tienen botón de cerrar y se cierran", function()
			local s = Stack.new()
			s:join(101, "Ana", true, veteran(1000))
			s:step(1)
			for _, id in { "company", "market", "ranking", "menu" } do
				s:click("Nav_" .. id)
				s:step(1)
				onlyWindowOpen(s, id)
				t:expect(s:find("Close", s:find("Window_" .. id)) ~= nil):toBe(true)
				s:click(s:find("Close", s:find("Window_" .. id)))
				t:expect(#onlyWindowOpen(s)):toBe(0)
			end
		end)

		t:test("abrir otra ventana cierra la anterior (nunca quedan apiladas)", function()
			local s = Stack.new()
			s:join(101, "Ana", true, veteran(1000))
			s:click("Nav_market")
			s:click("Nav_ranking")
			onlyWindowOpen(s, "ranking")
		end)

		t:test("tocar el fondo atenuado cierra la ventana", function()
			local s = Stack.new()
			s:join(101, "Ana", true, veteran(1000))
			s:click("Nav_menu")
			s:click(s:find("Dim", s:find("Window_menu")))
			t:expect(#onlyWindowOpen(s)):toBe(0)
		end)

		t:test("atajos de teclado abren y cierran ventanas", function()
			local s = Stack.new()
			s:join(101, "Ana", true, veteran(1000))
			local uis = s.l.services.UserInputService
			MockInstance.fire(uis, "InputBegan", { KeyCode = Enum.KeyCode.M }, false)
			onlyWindowOpen(s, "market")
			MockInstance.fire(uis, "InputBegan", { KeyCode = Enum.KeyCode.M }, false)
			t:expect(#onlyWindowOpen(s)):toBe(0)
		end)

		t:test("NO existen botones sin función en ninguna pantalla ni pestaña", function()
			local s = Stack.new()
			s:join(
				101,
				"Ana",
				true,
				veteran(500000, function(d)
					d.stats.totalEarned = 100000
				end)
			)
			s:join(102, "Beto", false, veteran(1000))
			s:step(2)
			-- HUD
			t:expect(s:deadButtons()):toEqual({})
			for _, nav in { "company", "market", "ranking", "menu" } do
				s:click("Nav_" .. nav)
				s:step(1)
				t:expect(s:deadButtons()):toEqual({})
			end
			-- todas las pestañas de Mercado y Empresa
			s:click("Nav_market")
			for _, tab in { "Tab_companies", "Tab_portfolio", "Tab_offers", "Tab_people", "Tab_deals" } do
				s:click(tab)
				t:expect(s:deadButtons()):toEqual({})
			end
			s:click("Nav_company")
			for _, tab in { "Tab_upgrades", "Tab_style", "Tab_history" } do
				s:click(tab)
				t:expect(s:deadButtons()):toEqual({})
			end
			s:click("FoundNew")
			t:expect(s:deadButtons()):toEqual({})
		end)
	end)

	t:describe("Empresa", function()
		t:test("mejoras con precio, efecto y beneficio; comprar desde la ventana funciona", function()
			local s = Stack.new()
			s:join(101, "Ana", true, veteran(2000))
			s:click("Nav_company")
			s:step(1)
			t:expect(s:text("Name", s:find("CompanyHeader"))):toContain("")
			local buy = s:find("Buy_shelves")
			t:expect(buy ~= nil):toBe(true)
			t:expect(buy.Text):toBe("$20")
			t:expect(s:text("Effect", s:find("Upgrade_shelves"))):toContain("+0.7 $/s per level")
			t:expect(s:text("Meta", s:find("Upgrade_shelves"))):toContain("Level 0/14")
			s:click(buy)
			t:expect(s.server.world.sessions["101"].data.companies["101:1"].upgrades.shelves):toBe(1)
		end)

		t:test("mejora demasiado cara: bloqueada e indicando cuánto falta", function()
			local s = Stack.new()
			s:join(101, "Ana", true, veteran(30))
			s:click("Nav_company")
			s:step(1)
			local expensive = s:find("Buy_marketing")
			t:expect(expensive:GetAttribute("Enabled")):toBe(false)
			t:expect(s:text("Missing", s:find("Upgrade_marketing"))):toContain("Need")
		end)

		t:test("estilo: sólo opciones predefinidas; cambiar el nombre llega al servidor", function()
			local s = Stack.new()
			s:join(101, "Ana", true, veteran(1000))
			s:click("Nav_company")
			s:click("Tab_style")
			t:expect(s:find("TextBox", s:gui())):toBeNil() -- no hay cajas de texto libre
			local before = s:text("NamePreview")
			-- avanzar el primer selector (prefijo)
			local plus = s:find("Plus", s:find("NameCard"))
			s:click(plus)
			t:expect(s:text("NamePreview") ~= before):toBe(true)
			s:click("SaveName")
			local c = s.server.world.sessions["101"].data.companies["101:1"]
			t:expect(c.name):toBe(s:text("NamePreview"))
			-- el logotipo tiene su propio enfriamiento: se puede guardar a continuación
			s:click("Icon_5")
			s:click("Color_3")
			s:click("SaveLogo")
			t:expect(c.logo.icon):toBe(5)
			t:expect(c.logo.color):toBe(3)
		end)

		t:test("fundar una empresa nueva desde la interfaz", function()
			local s = Stack.new()
			s:join(
				101,
				"Ana",
				true,
				veteran(5000, function(d)
					d.stats.totalEarned = 4000
				end)
			)
			s:click("Nav_company")
			s:click("FoundNew")
			-- Industria sigue bloqueada, Tecnología disponible
			t:expect(s:find("Found_industry"):GetAttribute("Enabled")):toBe(false)
			t:expect(s:find("Found_tech"):GetAttribute("Enabled")):toBe(true)
			s:click("Found_tech")
			local session = s.server.world.sessions["101"]
			t:expect(session.data.companies["101:2"] ~= nil):toBe(true)
			t:expect(session.data.cash):toBe(2500)
		end)

		t:test(
			"la ventana de empresa sin ninguna empresa gestionada ofrece fundar (no queda en blanco)",
			function()
				local s = Stack.new()
				s:join(101, "Ana", true, veteran(1000))
				s.server.world.sessions["101"].data.companies["101:1"].cap =
					{ holders = { ["102"] = 10000 }, rev = 1 }
				s.server.world.sessions["101"].viewDirty = true
				s:step(6)
				s:click("Nav_company")
				s:step(1)
				t:expect(s:find("FoundNew") ~= nil):toBe(true)
			end
		)
	end)

	t:describe("Mercado", function()
		t:test("empresas de la Bolsa visibles y el tutorial guía hasta la primera inversión", function()
			local s = Stack.new()
			s:join(101, "Ana", true, function(d)
				d.cash = 100000
			end)
			s:step(1)
			s:click("BuyButton") -- paso 1
			s:step(8) -- paso 2 (ver ingresos)
			t:expect(s.server.world.sessions["101"].data.tutorial.step):toBe(3)
			t:expect(s:find("PulseStroke", s:find("Nav_market")) ~= nil):toBe(true)
			s:click("Nav_market") -- paso 3
			s:step(1)
			t:expect(s:find("CompanyRow_npc:commerce") ~= nil):toBe(true)
			t:expect(s:find("CompanyRow_npc:tech") ~= nil):toBe(true)
			t:expect(s:find("CompanyRow_npc:industry") ~= nil):toBe(true)
			s:click("CompanyRow_npc:commerce") -- paso 4: inspeccionar
			s:step(1)
			t:expect(s.server.world.sessions["101"].data.tutorial.step):toBe(5)
			-- paso 5: comprar a la Bolsa con el diálogo de confirmación
			s:click("ExchangeBuy")
			t:expect(s:find("ExchangeModal") ~= nil):toBe(true)
			local cash = s.server.world.sessions["101"].data.cash
			s:click("ConfirmTrade")
			local session = s.server.world.sessions["101"]
			t:expect(session.data.cash < cash):toBe(true)
			t:expect(s.server.world.npcs["npc:commerce"].cap.holders["101"]):toBe(100)
			t:expect(session.data.tutorial.done):toBe(true)
			t:expect(s:find("ExchangeModal")):toBeNil() -- el diálogo se cierra
		end)

		t:test("oferta recibida: aviso, tarjeta con condiciones y aceptación con confirmación", function()
			local s = Stack.new()
			s:join(101, "Ana", true, veteran(0))
			s:join(102, "Beto", false, veteran(50000))
			s:step(2)
			local srv = s.server
			local a, b = srv.world.sessions["101"], srv.world.sessions["102"]
			local company = a.data.companies["101:1"]
			company.level = 1
			company.upgrades = {}
			local price = srv.world:stakeValue(company, 1000)
			local r = srv:dispatch(
				102,
				"MakeOffer",
				{ companyId = company.id, sellerId = "101", bps = 1000, price = price }
			)
			t:expect(r.ok):toBe(true)
			s:step(1)
			-- aviso y contador en el HUD
			t:expect(s:text("Nav_market")):toContain("(1)")
			s:click("Nav_market")
			s:click("Tab_offers")
			t:expect(s:find("Offer_" .. r.data.offerId) ~= nil):toBe(true)
			t:expect(s:text("Timer", s:find("Offer_" .. r.data.offerId))):toContain("Expires in")
			-- aceptar -> diálogo -> confirmar
			s:click("Accept_" .. r.data.offerId)
			t:expect(s:find("ConfirmModal") ~= nil):toBe(true)
			t:expect(s:text("ConfirmTitle")):toBe("Confirm the deal")
			local cash = a.data.cash
			s:click("Confirm", s:find("ConfirmModal"))
			t:expect(a.data.cash > cash):toBe(true)
			t:expect(company.cap.holders["102"]):toBe(1000)
			t:expect(s:find("ConfirmModal")):toBeNil()
		end)

		t:test("tomar el control exige DOBLE confirmación con aviso de cambio de gestión", function()
			local s = Stack.new()
			s:join(101, "Ana", true, veteran(0))
			s:join(102, "Beto", false, veteran(500000))
			s:step(2)
			local srv = s.server
			local a = srv.world.sessions["101"]
			local company = a.data.companies["101:1"]
			company.level = 1
			company.upgrades = {}
			local price = srv.world:stakeValue(company, 6000)
			local r = srv:dispatch(
				102,
				"MakeOffer",
				{ companyId = company.id, sellerId = "101", bps = 6000, price = price }
			)
			s:step(1)
			s:click("Nav_market")
			s:click("Tab_offers")
			s:click("Accept_" .. r.data.offerId)
			s:click("Confirm", s:find("ConfirmModal")) -- 1ª confirmación
			-- el servidor pide la segunda: aparece con la advertencia
			local modals = s:gui():FindFirstChild("Takeover_modals")
			local second = s:find("Warning", modals)
			t:expect(second ~= nil):toBe(true)
			t:expect(second:FindFirstChildOfClass("TextLabel").Text):toContain("changes who manages")
			t:expect(company.cap.holders["102"]):toBeNil() -- aún no se ha movido nada
			s:click("Confirm", s:find("ConfirmModal"))
			t:expect(company.cap.holders["102"]):toBe(6000)
			t:expect(Ownership.manager(company.cap, company.founderId)):toBe("102")
		end)

		t:test("rechazar una oferta desde la interfaz", function()
			local s = Stack.new()
			s:join(101, "Ana", true, veteran(0))
			s:join(102, "Beto", false, veteran(50000))
			s:step(2)
			local srv = s.server
			local company = srv.world.sessions["101"].data.companies["101:1"]
			local r = srv:dispatch(102, "MakeOffer", {
				companyId = company.id,
				sellerId = "101",
				bps = 1000,
				price = srv.world:stakeValue(company, 1000),
			})
			s:step(1)
			s:click("Nav_market")
			s:click("Tab_offers")
			s:click("Reject_" .. r.data.offerId)
			t:expect(srv.offers:get(r.data.offerId).state):toBe("rejected")
			t:expect(company.cap.holders["102"]):toBeNil()
		end)

		t:test("hacer una oferta desde la ficha de otra empresa: banda de precios y envío", function()
			local s = Stack.new()
			s:join(101, "Ana", true, veteran(50000))
			s:join(102, "Beto", false, veteran(0))
			s:step(2)
			local srv = s.server
			local other = srv.world.sessions["102"].data.companies["102:1"]
			other.level, other.upgrades.shelves = 3, 10
			s:click("Nav_market")
			s:click("CompanyRow_102:1")
			s:step(1)
			s:click("OfferTo_102")
			t:expect(s:find("OfferModal") ~= nil):toBe(true)
			t:expect(s:text("Fair")):toContain("Reference value")
			t:expect(s:text("Range")):toContain("Min")
			s:click("Quick_offer.quick.high")
			s:click("Send")
			local pending = srv.offers:pendingFor("101", "buyer")
			t:expect(#pending):toBe(1)
			t:expect(pending[1].sellerId):toBe("102")
			t:expect(s:find("OfferModal")):toBeNil()
			-- el comprador ve su oferta enviada y puede retirarla
			s:click("Nav_market")
			s:click("Tab_offers")
			s:click("Cancel_" .. pending[1].id)
			t:expect(srv.offers:get(pending[1].id).state):toBe("cancelled")
		end)

		t:test("alianza desde la pestaña Jugadores", function()
			local s = Stack.new()
			s:join(101, "Ana", true, veteran(1000))
			s:join(102, "Beto", false, veteran(1000))
			s:step(2)
			s:click("Nav_market")
			s:click("Tab_people")
			s:click("Invite_102")
			t:expect(#s.server.alliances:pendingFor("102")):toBe(1)
		end)
	end)

	t:describe("Ranking y menú", function()
		t:test("el ranking muestra tu puesto y las listas", function()
			local s = Stack.new()
			s:join(101, "Ana", true, veteran(10))
			s:join(102, "Beto", false, veteran(99999))
			s:step(6)
			s:click("Nav_ranking")
			s:step(1)
			t:expect(s:find("MyRank") ~= nil):toBe(true)
			t:expect(s:find("Player_102") ~= nil):toBe(true)
			t:expect(s:find("Company_101:1") ~= nil):toBe(true)
			-- tocar una empresa del ranking abre su ficha
			s:click("Company_102:1")
			onlyWindowOpen(s, "company")
		end)

		t:test("menú: recompensa diaria, ajustes e idioma", function()
			local s = Stack.new()
			s:join(101, "Ana", true, veteran(1000))
			s:click("Nav_menu")
			t:expect(s:find("ClaimDaily"):GetAttribute("Enabled")):toBe(true)
			local cash = s.server.world.sessions["101"].data.cash
			s:click("ClaimDaily")
			t:expect(s.server.world.sessions["101"].data.cash > cash):toBe(true)
			t:expect(s:find("ClaimDaily"):GetAttribute("Enabled")):toBe(false)
			s:click("ToggleSfx")
			t:expect(s.server.world.sessions["101"].data.settings.sfx):toBe(false)
			s:click("Lang_es")
			s:step(1)
			t:expect(s.server.world.sessions["101"].data.settings.lang):toBe("es")
			-- la interfaz cambia de idioma sin reiniciar
			t:expect(s:text("Nav_market")):toContain("Mercado")
			t:expect(s:text("CashTitle")):toBe("Cash")
		end)

		t:test(
			"la tienda sin productos configurados no muestra botones de compra y aclara que es sólo cosmética",
			function()
				local s = Stack.new()
				s:join(101, "Ana", true, veteran(1000))
				s:click("Nav_menu")
				t:expect(s:find("Pass_vip_office")):toBeNil()
				t:expect(s:find("Product_confetti_pack")):toBeNil()
				t:expect(s.l.game ~= nil):toBe(true)
			end
		)
	end)

	t:describe("Móvil, tablet y PC", function()
		t:test(
			"móvil vertical: modo compacto, tarjetas más estrechas y ventanas casi a pantalla completa",
			function()
				local s = Stack.new({ touch = true, viewport = Vector2.new(390, 844) })
				s:join(101, "Ana", true, veteran(1000))
				s:step(1)
				t:expect(s.l.client ~= nil):toBe(true)
				local app = s.l:client("App")
				t:expect(app.ctx.compact()):toBe(true)
				t:expect(s:find("CashCard").Size.X.Offset):toBe(190)
				s:click("Nav_market")
				local panel = s:find("Panel", s:find("Window_market"))
				t:expect(panel.Size.X.Scale):toBe(0.96)
				t:expect(panel.Size.Y.Scale):toBe(0.94)
			end
		)

		t:test("PC: ventana centrada con tamaño máximo y tarjetas anchas", function()
			local s = Stack.new({ viewport = Vector2.new(1280, 720) })
			s:join(101, "Ana", true, veteran(1000))
			s:step(1)
			t:expect(s.l:client("App").ctx.compact()):toBe(false)
			t:expect(s:find("CashCard").Size.X.Offset):toBe(250)
			s:click("Nav_company")
			local panel = s:find("Panel", s:find("Window_company"))
			t:expect(panel.Size.X.Scale):toBe(0.62)
			t:expect(s:find("UISizeConstraint", panel) ~= nil):toBe(true)
		end)

		t:test("todos los botones respetan el tamaño táctil mínimo (≥ 44 px de alto)", function()
			local s = Stack.new({ touch = true, viewport = Vector2.new(390, 844) })
			s:join(
				101,
				"Ana",
				true,
				veteran(500000, function(d)
					d.stats.totalEarned = 100000
				end)
			)
			s:step(2)
			local checked = 0
			local function audit()
				for _, b in s:buttons() do
					if
						b.Name ~= "Dim"
						and b.Name ~= "Toast"
						and b.Name:sub(1, 5) ~= "Icon_"
						and b.Name:sub(1, 6) ~= "Color_"
					then
						local h = b.Size.Y.Offset
						if b.Size.Y.Scale == 0 and h > 0 then
							if h < 38 then
								error(("botón demasiado pequeño: %s (%d px)"):format(b:GetFullName(), h))
							end
							checked += 1
						end
					end
				end
			end
			audit()
			for _, nav in { "market", "company", "menu", "ranking" } do
				s:click("Nav_" .. nav)
				audit()
			end
			t:expect(checked > 10):toBe(true)
		end)

		t:test("español automático por el idioma de Roblox", function()
			local s = Stack.new({ locale = "es_es" })
			s:join(101, "Ana", true, veteran(1250))
			s:step(1)
			t:expect(s:text("CashValue")):toBe("1,25 K $")
			t:expect(s:text("Nav_market")):toContain("Mercado")
		end)
	end)

	t:describe("Eventos y efectos", function()
		t:test("el banner de eventos anuncia, cuenta atrás y muestra la regla", function()
			local s = Stack.new()
			s:join(101, "Ana", true, veteran(1000))
			s:step(1)
			t:expect(s:find("EventBanner").Visible):toBe(false)
			s.globals.Takeover.forceEvent("commerce_boom")
			s:step(7) -- el servidor reenvía el estado (con el evento) cada pocos segundos
			t:expect(s:find("EventBanner").Visible):toBe(true)
			t:expect(s:text("EventTitle")):toContain("Commerce boom")
			t:expect(s:text("EventDesc")):toContain("×1.5")
		end)

		t:test("una toma de control pública muestra el banner para todos los clientes", function()
			local s = Stack.new()
			s:join(101, "Ana", true, veteran(0))
			s:step(1)
			s.server:broadcast({
				type = "effect",
				kind = "takeover",
				company = "Nova Market Co.",
				who = "Beto",
				effect = "",
			})
			local banner = s:find("Banner")
			t:expect(banner ~= nil):toBe(true)
			t:expect(s:text("BannerText")):toContain("Beto took control of Nova Market Co.")
		end)

		t:test("las notificaciones del servidor aparecen y se pueden descartar tocándolas", function()
			local s = Stack.new()
			s:join(101, "Ana", true, veteran(0))
			s.server:notify(101, "achievement", { id = "first_deal" })
			local toast = s:find("Toast")
			t:expect(toast ~= nil):toBe(true)
			t:expect(s:text("ToastText")):toContain("First deal")
			s:click(toast)
			t:expect(s:find("Toast")):toBeNil()
		end)
	end)

	t:describe("Robustez de la interfaz", function()
		t:test("errores del servidor se muestran como mensajes comprensibles, nunca como códigos", function()
			local s = Stack.new()
			s:join(101, "Ana", true, veteran(10))
			s:step(1)
			local ctx = s.l:client("App").ctx
			local r = ctx.run("BuyUpgrade", { companyId = "101:1", upgradeId = "marketing" }, {})
			t:expect(r.code):toBe("INSUFFICIENT_FUNDS")
			local toast = s:text("ToastText")
			t:expect(toast):toContain("Not enough money")
			t:expect(toast:find("INSUFFICIENT_FUNDS")):toBeNil()
		end)

		t:test("sin conexión con el servidor la pantalla de carga permanece y no hay errores", function()
			local s = Stack.new()
			s:join(101, "Ana", false)
			-- cliente que arranca cuando el servidor aún no tiene sus datos
			local p2 = MockInstance.player(201, "Cris")
			MockInstance.localPlayer = p2
			rawget(s.players, "_props").LocalPlayer = p2
			s.localPlayer = p2
			s.l:run(s.l:node("client", "Main"))
			t:expect(s:find("Loading").Visible):toBe(true)
			t:expect(Balance.StartingCash):toBe(100)
		end)
	end)
end
