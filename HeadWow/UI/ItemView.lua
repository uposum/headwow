-- Item page: header (icon, name, star, facts, prices), and three tabs:
--   Overview       the game's own tooltip, with cards beside it: how to get the item, the best
--                  places to farm it, and the NPCs that drop it most often
--   Dropped by     every NPC that drops it (sortable)
--   Where to farm  zones ranked by drops per clear of their best camp

local HW = HeadWow
local UI = HW.UI
local F = HW.F

local ItemView = {}
HW.ItemView = ItemView

local VENDOR_BIT, QUEST_BIT, CRAFTED_BIT = 2, 4, 8
local WEAPON, ARMOR = 2, 4
local TOP_SPOTS, TOP_DROPPERS = 3, 4
local ICONS = {
	vendor = "Interface\\Icons\\INV_Misc_Coin_01",
	drop = "Interface\\Icons\\INV_Misc_Bag_10",
	quest = "Interface\\Icons\\INV_Misc_Note_01",
	crafted = "Interface\\Icons\\Trade_BlackSmithing",
	zone = "Interface\\Icons\\INV_Misc_Map_01",
}

local TAB_KEYS = {}                  -- tabID -> "overview" | "drops" | "farm"
local TAB_IDS = {}                   -- key -> tabID
local ui = {}
local itemID

---------------------------------------------------------------------------
-- Overview
---------------------------------------------------------------------------

local function CreateOverview(parent)
	local page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()

	-- The real in-game item tooltip, embedded in the page.
	local tooltip = CreateFrame("GameTooltip", "HeadWowDetailTooltip", page, "GameTooltipTemplate")
	page.Tooltip = tooltip

	local column = CreateFrame("Frame", nil, page)
	column:SetHeight(1)
	page.Column = column
	page.Sources = UI.CreateCard(column, "How to get it")
	page.Sources:SetPoint("TOPLEFT")
	page.Sources:SetPoint("TOPRIGHT")
	page.Spots = UI.CreateCard(column, "Best places to farm")
	page.Spots:SetPoint("TOPLEFT", page.Sources, "BOTTOMLEFT", 0, -8)
	page.Spots:SetPoint("TOPRIGHT", page.Sources, "BOTTOMRIGHT", 0, -8)
	page.Droppers = UI.CreateCard(column, "Dropped most often by")
	page.Droppers:SetPoint("TOPLEFT", page.Spots, "BOTTOMLEFT", 0, -8)
	page.Droppers:SetPoint("TOPRIGHT", page.Spots, "BOTTOMRIGHT", 0, -8)

	-- The cards sit right of the tooltip, or across the page while there is none (the game
	-- hasn't got the item's data yet, or doesn't know the item).
	local function PlaceColumn()
		column:ClearAllPoints()
		if tooltip:IsShown() and tooltip:NumLines() > 0 then
			column:SetPoint("TOPLEFT", tooltip, "TOPRIGHT", 10, 0)
		else
			column:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -10)
		end
		column:SetPoint("RIGHT", page, "RIGHT", -10, 0)
	end
	tooltip:HookScript("OnShow", PlaceColumn)
	tooltip:HookScript("OnHide", PlaceColumn)
	tooltip:HookScript("OnSizeChanged", PlaceColumn)
	PlaceColumn()

	local waitingFor
	function page:ShowTooltip(id)
		local cached = not C_Item.IsItemDataCachedByID or C_Item.IsItemDataCachedByID(id)
		if not cached then
			tooltip:Hide()
			if waitingFor ~= id then
				waitingFor = id
				local item = Item:CreateFromItemID(id)
				if not item:IsItemEmpty() then
					item:ContinueOnItemLoad(function()
						if waitingFor == id and itemID == id and page:IsVisible() then page:ShowTooltip(id) end
					end)
				end
			end
			return
		end
		tooltip:SetOwner(page, "ANCHOR_NONE")
		tooltip:ClearAllPoints()
		tooltip:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -8)
		tooltip:SetFrameStrata(page:GetFrameStrata())
		tooltip:SetFrameLevel(page:GetFrameLevel() + 5)
		tooltip:SetItemByID(id)
		tooltip:Show()
		if tooltip:NumLines() == 0 then tooltip:Hide() end
		PlaceColumn()
	end

	page:SetScript("OnShow", function() if itemID then page:ShowTooltip(itemID) end end)
	return page
end

local function SourceRows(row, drops)
	local rows = {}
	local mask = row[F.SOURCE] or 0
	if row[F.FROM] then
		local vendor = bit.band(mask, VENDOR_BIT) ~= 0
		rows[#rows + 1] = {
			icon = vendor and ICONS.vendor or ICONS.quest,
			text = (vendor and "Sold by " or "From ") .. row[F.FROM],
			value = row[F.ZONE] and HW:GetZoneName(row[F.ZONE]) or nil,
		}
	elseif row[F.ZONE] then
		rows[#rows + 1] = { icon = ICONS.zone, text = "Found in " .. HW:GetZoneName(row[F.ZONE]) }
	end
	if row[F.DROPS] then
		local best = drops[1]
		rows[#rows + 1] = {
			icon = ICONS.drop, text = "Dropped by " .. row[F.DROPS] .. " NPCs",
			value = best and ("best " .. UI.ChanceText(best.chance)) or nil,
			onClick = function() ui.Tabs:SetTab(TAB_IDS.drops, true) end,
			onEnter = function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip_AddInstructionLine(GameTooltip, "Click: see them all")
				GameTooltip:Show()
			end,
		}
	end
	if bit.band(mask, QUEST_BIT) ~= 0 and not row[F.FROM] then rows[#rows + 1] = { icon = ICONS.quest, text = "Quest reward" } end
	if bit.band(mask, CRAFTED_BIT) ~= 0 then rows[#rows + 1] = { icon = ICONS.crafted, text = "Crafted" } end
	return rows
end

local function SpotRows(spots)
	local rows = {}
	for i = 1, math.min(TOP_SPOTS, #spots) do
		local spot = spots[i]
		rows[#rows + 1] = {
			icon = ICONS.zone, text = spot.name,
			value = spot.guessed and "|cff808080spawns unknown|r" or HW.Farm:FormatRate(spot.expected),
			onClick = function() HW.Map:ShowItem(itemID, nil, spot.mapID) end,
			onEnter = function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip_SetTitle(GameTooltip, spot.name)
				HW.Farm:AddSpotLines(GameTooltip, spot)
				GameTooltip_AddInstructionLine(GameTooltip, "Click: show on the map")
				GameTooltip:Show()
			end,
		}
	end
	if #spots > TOP_SPOTS then
		rows[#rows + 1] = { text = string.format("All %d zones...", #spots), dim = true,
			onClick = function() ui.Tabs:SetTab(TAB_IDS.farm, true) end }
	end
	return rows
end

local function DropperRows(drops)
	local rows = {}
	for i = 1, math.min(TOP_DROPPERS, #drops) do
		local drop = drops[i]
		local level = HW:FormatNpcLevel(drop.npcID, true)
		rows[#rows + 1] = {
			npcID = drop.npcID,
			text = drop.name .. (level ~= "" and (" |cff808080" .. level .. "|r") or ""),
			value = UI.ChanceText(drop.chance),
			onClick = function(button, self)
				if button == "RightButton" then HW:ShowNpcContextMenu(self, drop.npcID, itemID) else HW:ShowNpc(drop.npcID, itemID) end
			end,
			onEnter = function(self)
				HW:ShowNpcTooltip(self, drop.npcID, "ANCHOR_RIGHT", { chance = drop.chance, samples = drop.samples },
					{ "Click: NPC page  ·  Right-click: more" })
			end,
		}
	end
	return rows
end

---------------------------------------------------------------------------
-- Tables
---------------------------------------------------------------------------

local function ZoneText(zones)
	local names = {}
	for _, z in ipairs(zones) do names[#names + 1] = HW:GetZoneName(z) end
	return table.concat(names, ", ")
end

local DROPS_SPEC = {
	columns = {
		{ title = "NPC", icon = function(d) return "npc", d.npcID end, text = function(d) return d.name end, sort = UI.ByText("name") },
		{ title = "Level", width = 56, text = function(d) return HW:FormatNpcLevel(d.npcID, true) end,
		  sort = function(a, b) return HW:GetNpcSortLevel(a.npcID) < HW:GetNpcSortLevel(b.npcID) end, descending = true },
		{ title = "Zone", width = 150, font = "GameFontDisableSmall", text = function(d) return d.zoneText end, sort = UI.ByText("zoneText") },
		{ title = "Chance", width = 68, align = "RIGHT", text = function(d) return UI.ChanceText(d.chance) end,
		  sort = UI.ByNumber("chance"), descending = true },
		{ title = "Kills", width = 64, align = "RIGHT", font = "GameFontDisableSmall",
		  text = function(d) return BreakUpLargeNumbers(d.samples or 0) end, sort = UI.ByNumber("samples"), descending = true },
	},
	sort = 4, descending = true, footer = true,
	onClick = function(d, button, row)
		if button == "RightButton" then HW:ShowNpcContextMenu(row, d.npcID, itemID) else HW:ShowNpc(d.npcID, itemID) end
	end,
	onEnter = function(d, row)
		HW:ShowNpcTooltip(row, d.npcID, "ANCHOR_RIGHT", { chance = d.chance, samples = d.samples },
			{ "Click: NPC page  ·  Right-click: more" })
	end,
}

local FARM_SPEC = {
	columns = {
		{ title = "Zone", icon = function() return "texture", ICONS.zone end, text = function(s) return s.name end, sort = UI.ByText("name") },
		{ title = "Per clear", width = 96, align = "RIGHT",
		  text = function(s) return s.guessed and "|cff808080?|r" or HW.Farm:FormatRate(s.expected, true) end,
		  sort = UI.ByNumber("expected"), descending = true },
		{ title = "Camp", width = 60, align = "RIGHT", font = "GameFontDisableSmall",
		  text = function(s) return s.guessed and "?" or tostring(s.spawns) end, sort = UI.ByNumber("spawns"), descending = true },
		{ title = "NPCs there", flex = 1.2, font = "GameFontDisableSmall", text = function(s) return s.npcText end },
	},
	sort = 2, descending = true, footer = true,
	onClick = function(s) HW.Map:ShowItem(itemID, nil, s.mapID) end,
	onEnter = function(s, row)
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, s.name)
		HW.Farm:AddSpotLines(GameTooltip, s)
		GameTooltip_AddInstructionLine(GameTooltip, "Click: show on the map")
		GameTooltip:Show()
	end,
}

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function CreateHeader(view)
	local header = CreateFrame("Frame", nil, view)
	header:SetPoint("TOPLEFT", 0, -2)
	header:SetPoint("TOPRIGHT", 0, -2)
	header:SetHeight(50)

	local button = CreateFrame("ItemButton", nil, header)
	button:SetPoint("TOPLEFT", 2, -2)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(itemID)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnClick", function()
		if IsModifiedClick("CHATLINK") then HW:InsertItemLink(itemID)
		elseif IsModifiedClick("DRESSUP") then HW:WithItemLink(itemID, DressUpItemLink) end
	end)
	header.Button = button

	local star = CreateFrame("Button", nil, header)
	star:SetSize(26, 26)
	star:SetPoint("TOPRIGHT", -2, -2)
	star.Icon = star:CreateTexture(nil, "ARTWORK")
	star.Icon:SetAllPoints()
	star:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	star:SetScript("OnClick", function() HW:ToggleWished(itemID) end)
	UI.SetTooltip(star, function() return HW:IsWished(itemID) and "On your wishlist" or "Add to wishlist" end, function(tip)
		GameTooltip_AddNormalLine(tip, "Mobs that drop wishlist items are marked in their tooltips (and on the map, "
			.. "if you turn that on), and you're told when one drops.", true)
		GameTooltip_AddInstructionLine(tip, HW:IsWished(itemID) and "Click: remove" or "Click: add")
	end, "ANCHOR_LEFT")
	header.Star = star

	local name = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	name:SetPoint("TOPLEFT", button, "TOPRIGHT", 10, -1)
	name:SetPoint("RIGHT", star, "LEFT", -8, 0)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	header.Name = name

	local line1 = header:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	line1:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
	line1:SetPoint("RIGHT", star, "LEFT", -8, 0)
	line1:SetJustifyH("LEFT")
	line1:SetWordWrap(false)
	header.Line1 = line1

	local line2 = header:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	line2:SetPoint("TOPLEFT", line1, "BOTTOMLEFT", 0, -3)
	line2:SetPoint("RIGHT", header, "RIGHT", -2, 0)
	line2:SetJustifyH("LEFT")
	line2:SetWordWrap(false)
	header.Line2 = line2
	return header
end

function ItemView:Create(host)
	local view = CreateFrame("Frame", nil, host)
	view:SetAllPoints()
	view:Hide()
	ui.View = view
	ui.Header = CreateHeader(view)

	-- Actions
	local wowhead = UI.Button(view, "Wowhead link", function() HW:ShowURL(HW:GetWowheadURL("item", itemID)) end, 116)
	wowhead:SetPoint("BOTTOMRIGHT", 0, 0)
	local link = UI.Button(view, "Link in chat", function() HW:InsertItemLink(itemID) end, 110)
	link:SetPoint("RIGHT", wowhead, "LEFT", -4, 0)
	local map = UI.Button(view, "Show on map", function() HW.Map:ShowItem(itemID) end, 120)
	map:SetPoint("RIGHT", link, "LEFT", -4, 0)
	UI.SetTooltip(map, "Show on map", function(tip)
		GameTooltip_AddNormalLine(tip, "Pins where the mobs that drop it stand (with Questie installed), ringed by drop chance.", true)
	end)
	ui.MapButton = map

	-- Tabs over the body
	local tabs = CreateFrame("Frame", nil, view, "HeadWowTopTabSystemTemplate")
	tabs:SetPoint("TOPLEFT", ui.Header, "BOTTOMLEFT", 8, -6)
	ui.Tabs = tabs

	local body = CreateFrame("Frame", nil, view, "InsetFrameTemplate")
	body:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", -8, 1)
	body:SetPoint("RIGHT", view, "RIGHT", 0, 0)
	body:SetPoint("BOTTOM", wowhead, "TOP", 0, 6)

	ui.Overview = CreateOverview(body)
	ui.Drops = UI.CreateTable(body, DROPS_SPEC)
	ui.Drops:SetAllPoints()
	ui.Farm = UI.CreateTable(body, FARM_SPEC)
	ui.Farm:SetAllPoints()

	local pages = { overview = ui.Overview, drops = ui.Drops, farm = ui.Farm }
	for _, key in ipairs({ "overview", "drops", "farm" }) do
		local id = tabs:AddTab(({ overview = "Overview", drops = "Dropped by", farm = "Where to farm" })[key])
		TAB_KEYS[id], TAB_IDS[key] = key, id
	end
	tabs:SetTabSelectedCallback(function(tabID, isUserAction)
		local key = TAB_KEYS[tabID]
		for k, page in pairs(pages) do page:SetShown(k == key) end
		if isUserAction then HW.db.detailTab = key end
		return false
	end)
	tabs:SetTab(TAB_IDS.overview)
end

---------------------------------------------------------------------------
-- Filling
---------------------------------------------------------------------------

local function Facts(row, id)
	local facts = {}
	if row[F.ILVL] then facts[#facts + 1] = "Item Level " .. row[F.ILVL] end
	if row[F.REQ] then facts[#facts + 1] = "Requires Level " .. row[F.REQ] end
	if row[F.SLOT] then facts[#facts + 1] = HW:GetSlotName(row[F.SLOT]) end
	local _, _, subType, _, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
	if subType and ((classID == ARMOR and subclassID and subclassID >= 1 and subclassID <= 4) or classID == WEAPON) then
		facts[#facts + 1] = subType
	end
	return table.concat(facts, "  ·  ")
end

local function Prices(row, id)
	local parts = {}
	local source = HW:GetSourceText(row[F.SOURCE])
	if source then parts[#parts + 1] = source end
	if row[F.SELL] then parts[#parts + 1] = "Vendor " .. GetMoneyString(row[F.SELL], true) end
	local price, reliable, market = HW:GetShownAuctionPrice(id)
	if price then
		local ah = "AH " .. GetMoneyString(price, true)
		if market then
			ah = ah .. " |cff808080(" .. (reliable and HW:DescribeMarket(market) or ("unreliable: " .. market.reason)) .. ")|r"
		end
		parts[#parts + 1] = ah
	end
	parts[#parts + 1] = "ID " .. id
	return table.concat(parts, "  ·  ")
end

function ItemView:Show(id)
	itemID = id
	ui.View:Show()
	self:Refresh()
end

function ItemView:Hide()
	if ui.View then ui.View:Hide() end
end

function ItemView:Refresh()
	if not itemID then return end
	local row = HW:GetItem(itemID)
	local header = ui.Header

	header.Button:SetItem(itemID)
	if not header.Button:GetItemLink() then SetItemButtonTexture(header.Button, HW:GetItemIcon(itemID)) end
	header.Name:SetText(row[F.NAME])
	header.Name:SetTextColor(HW:GetQualityColor(HW:GetItemQuality(itemID)))
	header.Line1:SetText(Facts(row, itemID))
	header.Line2:SetText(Prices(row, itemID))
	self:UpdateStar()

	-- Data
	local hasDrops = row[F.DROPS] ~= nil
	local drops, truncated, spots = {}, 0, {}
	if hasDrops then
		drops, truncated = HW:GetDrops(itemID)
		table.sort(drops, function(a, b) return (a.chance or -1) > (b.chance or -1) end)
		for _, drop in ipairs(drops) do drop.zoneText = ZoneText(drop.zones) end
		spots = select(2, HW.Farm:Get(itemID))
		for _, spot in ipairs(spots) do
			local names = {}
			for _, npc in ipairs(spot.npcs) do names[#names + 1] = npc.name end
			spot.npcText = table.concat(names, ", ")
		end
	end
	local hasSpots = #spots > 0

	-- Overview
	local overview = ui.Overview
	overview.Sources:SetRows(SourceRows(row, drops), "No source known.")
	overview.Spots:SetShown(hasDrops)
	overview.Droppers:SetShown(hasDrops)
	if hasDrops then
		overview.Spots:SetRows(SpotRows(spots), "No drop chances known.")
		overview.Droppers:SetRows(DropperRows(drops))
	end
	if overview:IsVisible() then overview:ShowTooltip(itemID) end

	-- Dropped by
	ui.Drops:SetData(drops, "No drop data for this item.")
	ui.Drops:SetFooter(truncated > 0
		and string.format("%d sources here, %d more on Wowhead that the snapshot doesn't include.", #drops, truncated)
		or (#drops > 0 and string.format("%d sources. Kills: how often Wowhead users looted the NPC.", #drops) or ""))

	-- Where to farm
	ui.Farm:SetData(spots, "No drop chances known for this item.")
	ui.Farm:SetFooter(HW:HasSpawnData()
		and ("Per clear: drops to expect from killing every spawn in the zone's best camp (its densest "
			.. HW.CAMP_SIZE .. "-yard area) once. Click a zone to see it on the map.")
		or "Install Questie for spawn points; without them each NPC counts once, so zones rank by drop chance.")

	-- Tabs: the one you used last when this item has it, else the Overview
	local tabs = ui.Tabs
	UI.SetTabText(tabs, TAB_IDS.drops, hasDrops and ("Dropped by  " .. HW:GrayText(#drops)) or "Dropped by")
	tabs:SetTabEnabled(TAB_IDS.drops, hasDrops, "No drop data for this item")
	tabs:SetTabEnabled(TAB_IDS.farm, hasSpots, "No drop chances known for this item")
	local preferred = HW.db.detailTab
	local available = (preferred == "drops" and hasDrops) or (preferred == "farm" and hasSpots)
	tabs:SetTab(available and TAB_IDS[preferred] or TAB_IDS.overview)

	ui.MapButton:SetEnabled(hasDrops)
end

function ItemView:UpdateStar()
	if itemID then HW:SetStarTexture(ui.Header.Star.Icon, HW:IsWished(itemID)) end
end

function ItemView:OnWishlistChanged()
	if ui.View and ui.View:IsShown() then self:UpdateStar() end
end
