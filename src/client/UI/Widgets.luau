--!nonstrict
--[[
	Piezas de interfaz del dominio (filas de empresa, barras de propiedad...) compartidas por varias
	pantallas. Dependen de `ctx` (textos localizados y formateo), no de Roblox más allá de Instances.
]]

local Widgets = {}

local function sectorColor(ctx, sector)
	return ctx.theme.colors.sector[sector] or ctx.theme.colors.accent
end

--[[
	Fila de empresa tocable. company = ficha pública (Views.companyBrief).
	onTap se llama al pulsar; la fila ENTERA es el botón (objetivo táctil grande).
]]
function Widgets.companyRow(ctx, parent, company, onTap, opts)
	opts = opts or {}
	local K = ctx.kit
	local C = ctx.theme.colors
	local S = ctx.theme.sizes
	local T = ctx.T

	local row = K.button(parent, "", onTap, {
		name = "CompanyRow_" .. company.id,
		style = "ghost",
		size = UDim2.new(1, 0, 0, 74),
		layoutOrder = opts.layoutOrder,
	})
	row.Text = ""
	row.BackgroundColor3 = C.surface
	K.stroke(row, sectorColor(ctx, company.sector), 1.5, 0.3)

	local logo = ctx.logoGlyph(company.logo)
	K.label(row, logo, {
		size = 30,
		align = "center",
		height = 74,
		size2 = UDim2.new(0, 48, 1, 0),
		position = UDim2.fromOffset(6, 0),
		name = "Logo",
	})
	K.label(row, company.name, {
		bold = true,
		size = S.text,
		height = 22,
		size2 = UDim2.new(1, -150, 0, 22),
		position = UDim2.fromOffset(58, 8),
		name = "Name",
	})
	local detail = (ctx.theme.sectorIcons[company.sector] or "")
		.. " "
		.. T("sector." .. company.sector)
		.. "  ·  "
		.. T("common.level", { n = company.level })
	K.label(row, detail, {
		size = S.textSmall,
		color = C.textDim,
		height = 16,
		size2 = UDim2.new(1, -150, 0, 16),
		position = UDim2.fromOffset(58, 30),
		name = "Detail",
	})
	local manager = company.managerId == "MARKET" and T("common.market") or company.managerName
	K.label(row, T("company.manager") .. ": " .. tostring(manager), {
		size = S.textSmall,
		color = C.textDim,
		height = 16,
		size2 = UDim2.new(1, -150, 0, 16),
		position = UDim2.fromOffset(58, 48),
		name = "Manager",
	})
	K.label(row, ctx.cash(company.valuation), {
		bold = true,
		size = S.text,
		color = C.gold,
		align = "right",
		height = 22,
		size2 = UDim2.new(0, 120, 0, 22),
		position = UDim2.new(1, -128, 0, 10),
		name = "Valuation",
	})
	K.label(row, "+" .. ctx.rate(company.income), {
		size = S.textSmall,
		color = C.green,
		align = "right",
		height = 16,
		size2 = UDim2.new(0, 120, 0, 16),
		position = UDim2.new(1, -128, 0, 34),
		name = "Income",
	})
	if company.myBps and company.myBps > 0 then
		local chip = K.chip(row, ctx.bps(company.myBps), C.accentDark)
		chip.Position = UDim2.new(1, -90, 1, -28)
	end
	return row
end

-- Barra de reparto de propiedad: una fila por titular con su porcentaje y su nivel de derechos.
function Widgets.ownershipList(ctx, parent, holders, meId, onOffer)
	local K = ctx.kit
	local C = ctx.theme.colors
	local S = ctx.theme.sizes
	local T = ctx.T
	local Ownership = ctx.Ownership

	for i, h in holders do
		local row =
			K.frame(parent, { name = "Holder_" .. h.id, size = UDim2.new(1, 0, 0, 56), layoutOrder = i })
		local isMe = h.id == meId
		local name = h.id == "MARKET" and T("common.market")
			or (isMe and (h.name .. " (" .. T("common.you") .. ")") or h.name)
		K.label(row, name, {
			bold = true,
			size = S.text,
			height = 20,
			size2 = UDim2.new(1, -140, 0, 20),
			name = "HolderName",
		})
		local tier = Ownership.tier(h.bps)
		K.label(
			row,
			ctx.bps(h.bps)
				.. "  ·  "
				.. T("tier." .. tier)
				.. (h.online and "" or ("  ·  " .. T("common.offline"))),
			{
				size = S.textSmall,
				color = C.textDim,
				height = 16,
				size2 = UDim2.new(1, -140, 0, 16),
				position = UDim2.fromOffset(0, 20),
				name = "HolderTier",
			}
		)
		local bar = K.progress(
			row,
			h.bps / 10000,
			tier == "control" and C.gold or (tier == "board" and C.accent or C.green),
			8
		)
		bar.Position = UDim2.fromOffset(0, 42)
		bar.Size = UDim2.new(1, -140, 0, 8)
		if onOffer and not isMe and h.id ~= "MARKET" and h.online then
			K.button(row, T("offer.new"), function()
				onOffer(h)
			end, {
				name = "OfferTo_" .. h.id,
				style = "primary",
				size = UDim2.new(0, 130, 0, 44),
				anchor = Vector2.new(1, 0.5),
				position = UDim2.new(1, 0, 0.5, 0),
				textSize = S.textSmall,
			})
		end
	end
end

-- Reglas públicas de control (siempre visibles donde se negocia).
function Widgets.governanceCard(ctx, parent, governance)
	local K = ctx.kit
	local C = ctx.theme.colors
	local S = ctx.theme.sizes
	local T = ctx.T
	local card = K.card(parent, { name = "Governance", color = C.surface2 })
	K.layout(card, { gap = 4 })
	K.label(card, T("gov.title"), { bold = true, size = S.text, name = "GovTitle" })
	K.label(card, "• " .. T("gov.minority"), { size = S.textSmall, color = C.textDim })
	K.label(card, "• " .. T("gov.board"), { size = S.textSmall, color = C.textDim })
	K.label(card, "• " .. T("gov.control"), { size = S.textSmall, color = C.textDim })
	K.label(
		card,
		"• " .. T("gov.manager_floor", { pct = ctx.bps(governance and governance.minManagerBps or 2000) }),
		{ size = S.textSmall, color = C.textDim }
	)
	return card
end

-- Tarjeta de una cifra con título (valoración, ingresos...).
function Widgets.stat(ctx, parent, title, value, color, order)
	local K = ctx.kit
	local C = ctx.theme.colors
	local S = ctx.theme.sizes
	local card = K.card(parent, {
		name = "Stat_" .. title,
		size = UDim2.new(0.333, -6, 0, 66),
		autoY = false,
		color = C.surface,
		layoutOrder = order,
		pad = 8,
	})
	K.label(card, title, { size = S.textSmall, color = C.textDim, height = 16, align = "center" })
	local v = K.label(card, value, {
		bold = true,
		size = S.text + 2,
		color = color or C.text,
		height = 26,
		align = "center",
		position = UDim2.fromOffset(0, 20),
		size2 = UDim2.new(1, 0, 0, 26),
		name = "Value",
	})
	return card, v
end

return Widgets
