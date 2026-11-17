-- Wishlist: every starred item with where to farm it, who drops it best and what it sells for.
-- The toolbar holds the wishlist's own switches (mobs on the map, loot announcements).

local HW = HeadWow
local UI = HW.UI

local Wishlist = {}
HW.Views = HW.Views or {}
HW.Views.wishlist = Wishlist

local ui = {}

local function BestDrop(itemID)
	local best
	for _, drop in ipairs(HW:GetDrops(itemID)) do
		if drop.chance and (not best or drop.chance > best.chance) then best = drop end
	end
	return best
end

local function Entry(itemID)
	local row = HW:GetItem(itemID)
	local entry = { itemID = itemID, name = row and row[HW.F.NAME] or "" }
	if row and row[HW.F.DROPS] then
		entry.spot = HW.Farm:GetBest(itemID)
		entry.rate = entry.spot and not entry.spot.guessed and entry.spot.expected or nil
		entry.drop = BestDrop(itemID)
		entry.chance = entry.drop and entry.drop.chance
	end
	entry.price = HW:GetShownAuctionPrice(itemID)
	return entry
end

local SPEC = {
	columns = {
		{ title = "Item", icon = function(e) return "item", e.itemID end,
		  text = function(e) return HW:GetColoredItemName(e.itemID) end, sort = UI.ByText("name") },
		{ title = "Best place to farm", width = 230,
		  text = function(e)
			if not e.spot then return "|cff808080-|r" end
			local rate = e.spot.guessed and "" or (" |cff808080" .. HW.Farm:FormatRate(e.spot.expected) .. "|r")
			return e.spot.name .. rate
		  end,
		  sort = UI.ByNumber("rate"), descending = true },
		{ title = "Best drop", width = 200,
		  text = function(e)
			if not e.drop then return "|cff808080-|r" end
			return e.drop.name .. "  " .. UI.ChanceText(e.drop.chance)
		  end,
		  sort = UI.ByNumber("chance"), descending = true },
		{ title = "AH", width = 90, align = "RIGHT",
		  text = function(e) return e.price and HW:FormatMoneyShort(e.price) or "|cff808080-|r" end,
		  sort = UI.ByNumber("price"), descending = true },
	},
	sort = 1, footer = true,
	onClick = function(e, button, row)
		if button == "RightButton" then HW:ShowItemContextMenu(row, e.itemID)
		elseif IsModifiedClick("CHATLINK") then HW:InsertItemLink(e.itemID)
		else HW:ShowItem(e.itemID) end
	end,
	onEnter = function(e, row)
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(e.itemID)
		if e.spot then
			GameTooltip_AddBlankLineToTooltip(GameTooltip)
			GameTooltip_AddNormalLine(GameTooltip, "Best place to farm: " .. e.spot.name)
			GameTooltip_AddHighlightLine(GameTooltip, HW.Farm:Describe(e.spot))
		end
		GameTooltip_AddBlankLineToTooltip(GameTooltip)
		GameTooltip_AddInstructionLine(GameTooltip, "Click: open  ·  Right-click: more")
		GameTooltip:Show()
	end,
}

function Wishlist:Create(content, toolbar)
	ui.MapBox = UI.Checkbox(toolbar, "Show their mobs on the map",
		function() return HW.db.wishMap end,
		function(on) HW.Map:SetWishPinsShown(on) end,
		"Pins every spawn of the mobs that drop a wishlist item (pink rings).")
	ui.MapBox:SetPoint("LEFT", 4, 0)

	ui.AlertBox = UI.Checkbox(toolbar, "Announce drops",
		function() return HW.db.wishAlert end,
		function(on) HW.db.wishAlert = on end,
		"A raid warning, a sound and a chat line when you loot a wishlist item.")
	ui.AlertBox:SetPoint("LEFT", ui.MapBox, "LEFT", UI.CheckboxWidth(ui.MapBox) + 16, 0)

	ui.Count = toolbar:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	ui.Count:SetPoint("RIGHT", -6, 0)

	local inset = CreateFrame("Frame", nil, content, "InsetFrameTemplate")
	inset:SetAllPoints()
	ui.Table = UI.CreateTable(inset, SPEC)
	ui.Table:SetAllPoints()
end

function Wishlist:Refresh()
	local entries = {}
	for itemID in pairs(HW.db.wishlist) do
		if HW:GetItem(itemID) then entries[#entries + 1] = Entry(itemID) end
	end
	ui.Table:SetData(entries,
		"Your wishlist is empty.\nStar an item (on its page, or right-click > Add to wishlist) to follow it here.")
	ui.Table:SetFooter(#entries > 0
		and "Mobs that drop these items list them first in their tooltips. AH: the median of steady markets only."
		or "")
	ui.Count:SetText(#entries == 1 and "1 item" or (#entries .. " items"))
	ui.MapBox:Update()
	ui.AlertBox:Update()
end

function Wishlist:OnShow()
	self:Refresh()
end

function Wishlist:OnWishlistChanged()
	if self.content and self.content:IsShown() then self:Refresh() end
end
