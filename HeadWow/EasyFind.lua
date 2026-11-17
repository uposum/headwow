-- EasyFind integration (only when EasyFind is installed; see EasyFind/API/README.md).
--
--  * An extension tile "HeadWow" that opens the browser.
--  * Item sources: clicking an item in EasyFind opens its sources page; HeadWow adds what the
--    snapshot knows (who drops it and how often, the vendor or quest it comes from).
--  * "Open in HeadWow" / "Show drops on map" on the right-click menu of EasyFind's item rows.

local HW = HeadWow
local F = HW.F

local EF = {}
HW.EasyFind = EF

local ID = "headwow"
local ICON = "Interface\\AddOns\\HeadWow\\Media\\EasyFindIcon"
local MAX_DROP_ROWS = 40
local VENDOR_BIT = 2

local function GetAPI()
	local api = EasyFind and EasyFind.API
	if type(api) == "table" and api.VERSION == 1 and (api.MINOR or 0) >= 11 then return api end
end

function EF:IsAvailable()
	return self.registered == true
end

-- EasyFind's map open, which keeps the world map untainted (see its OpenMap docs). Returns
-- false when EasyFind isn't there or refused (e.g. in combat).
function EF:OpenMap(mapID)
	local api = GetAPI()
	return api and api.OpenMap and api.OpenMap(mapID) or false
end

function EF:NotifyOpenChanged()
	local api = self.registered and GetAPI()
	if api and api.NotifyOpenChanged then api.NotifyOpenChanged(ID) end
end

---------------------------------------------------------------------------
-- Item sources page rows
---------------------------------------------------------------------------

local function ZoneList(zones)
	local names = {}
	for i, zoneIdx in ipairs(zones) do
		if i > 3 then
			names[#names + 1] = "..."
			break
		end
		names[#names + 1] = HW:GetZoneName(zoneIdx)
	end
	return table.concat(names, ", ")
end

local HookRowIcons

local function SourceRows(itemID)
	local item = HW:GetItem(itemID)
	if not item then return nil end
	C_Timer.After(0, HookRowIcons) -- EasyFind makes its rows as it needs them
	-- Rows that open HeadWow lead the section; the sources follow.
	local opens, out = {}, {}
	local function Add(row, list)
		row.category = ID -- routes the row's click and tooltip to the provider below
		-- (hwItem, not itemID: EasyFind treats rows with an itemID as items of its own)
		row.hwItem = itemID
		list = list or out
		list[#list + 1] = row
	end

	if item[F.FROM] then
		local vendor = item[F.SOURCE] and bit.band(item[F.SOURCE], VENDOR_BIT) ~= 0
		local desc = vendor and "Sold by" or "From"
		if item[F.ZONE] then desc = desc .. "  ·  " .. HW:GetZoneName(item[F.ZONE]) end
		Add({ name = item[F.FROM], searchCommandDesc = desc, hwKind = "from", hwZoneIdx = item[F.ZONE] })
	end

	if item[F.DROPS] then
		local drops, truncated = HW:GetDrops(itemID)
		table.sort(drops, function(a, b) return (a.chance or -1) > (b.chance or -1) end)
		for i, drop in ipairs(drops) do
			if i > MAX_DROP_ROWS then break end
			local desc = HW:FormatChance(drop.chance)
			local level = HW:FormatNpcLevel(drop.npcID)
			if level ~= "" then desc = (LEVEL or "Level") .. " " .. level .. "  ·  " .. desc end
			if #drop.zones > 0 then desc = desc .. "  ·  " .. ZoneList(drop.zones) end
			local keywords = {}
			for _, zoneIdx in ipairs(drop.zones) do keywords[#keywords + 1] = HW:GetZoneName(zoneIdx) end
			Add({
				name = drop.name, searchCommandDesc = desc, keywords = keywords, hwKind = "drop",
				hwNpc = drop.npcID, hwZoneIdx = drop.zones[1], hwChance = drop.chance, hwSamples = drop.samples,
			})
		end
		local more = math.max(0, #drops - MAX_DROP_ROWS) + (truncated or 0)
		if more > 0 then
			Add({ name = string.format("%d more sources", more), searchCommandDesc = "See all in HeadWow", hwKind = "open" }, opens)
		end
	end

	if #out == 0 then return nil end
	local open = { name = "Open in HeadWow", searchCommandDesc = HW:GetSourceText(item[F.SOURCE]), icon = HW:GetItemIcon(itemID), hwKind = "open" }
	Add(open, opens)
	table.remove(opens)
	table.insert(opens, 1, open) -- "Open in HeadWow" first, then the best place, "N more sources"
	local best = HW.Farm:GetBest(itemID)
	if best then
		local farm = {
			name = "Best place to farm: " .. best.name, searchCommandDesc = HW.Farm:Describe(best),
			hwKind = "farm", hwMap = best.mapID, hwSpot = best,
		}
		Add(farm, opens)
		table.remove(opens)
		table.insert(opens, 2, farm)
	end
	for _, row in ipairs(out) do opens[#opens + 1] = row end
	return opens
end

local function SelectRow(row)
	if row.hwKind == "drop" then
		if IsAltKeyDown() then
			HW.Map:ShowItem(row.hwItem, row.hwZoneIdx)
		else
			HW:ShowNpc(row.hwNpc, row.hwItem)
		end
	elseif row.hwKind == "farm" then
		HW.Map:ShowItem(row.hwItem, nil, row.hwMap)
	else
		HW:ShowItem(row.hwItem)
	end
end

local function RowTooltip(row, tooltip)
	if row.hwKind == "drop" then
		HW:FillNpcTooltip(tooltip, row.hwNpc,
			{ itemID = row.hwItem, chance = row.hwChance, samples = row.hwSamples },
			{ "Click: NPC page  ·  Alt-click: show on map" })
		-- the 3D model beside it, once EasyFind has placed and shown the tooltip
		C_Timer.After(0, function()
			if tooltip:IsShown() then HW:AttachNpcCard(tooltip, row.hwNpc) end
		end)
		return true
	elseif row.hwKind == "farm" then
		GameTooltip_SetTitle(tooltip, row.hwSpot.name)
		HW.Farm:AddSpotLines(tooltip, row.hwSpot)
		GameTooltip_AddInstructionLine(tooltip, "Click: show the spawns on the map")
		return true
	elseif row.hwKind == "from" then
		GameTooltip_SetTitle(tooltip, row.name)
		GameTooltip_AddNormalLine(tooltip, row.searchCommandDesc)
		GameTooltip_AddBlankLineToTooltip(tooltip)
		GameTooltip_AddInstructionLine(tooltip, "Click: open in HeadWow")
		return true
	end
	tooltip:SetItemByID(row.hwItem)
	return true
end

local function NpcMenu(npcID, itemID, zoneIdx)
	return {
		{ kind = "action", label = "Open NPC page", closes = true, onClick = function() HW:ShowNpc(npcID, itemID) end },
		{ kind = "action", label = "Show this drop on map", closes = true, onClick = function() HW.Map:ShowItem(itemID, zoneIdx) end },
		{ kind = "action", label = "Copy Wowhead link", closes = true,
		  onClick = function() HW:ShowURL(HW:GetWowheadURL("npc", npcID)) end },
	}
end

local function ItemMenu(itemID)
	local item = HW:GetItem(itemID)
	local hasDrops = item and item[F.DROPS] ~= nil
	return {
		{ kind = "action", label = "Open in HeadWow", closes = true, onClick = function() HW:ShowItem(itemID) end },
		{ kind = "action", label = "Show drops on map", closes = true, disabled = not hasDrops,
		  tooltip = hasDrops and "Pin the mobs that drop it" or "HeadWow has no drop data for this item",
		  onClick = function() HW.Map:ShowItem(itemID) end },
		{ kind = "action", label = HW:IsWished(itemID) and "Remove from wishlist" or "Add to wishlist",
		  onClick = function() HW:ToggleWished(itemID) end },
	}
end

---------------------------------------------------------------------------
-- NPC portraits on EasyFind's rows
--
-- EasyFind marks each row on the left with the glyph of the addon it comes from (HeadWow's
-- book) and has no API for a per-row portrait there. On HeadWow's NPC rows the portrait takes
-- the glyph's place, in its own colors: whenever EasyFind paints or tints that glyph, the hooks
-- below put the portrait back. EasyFind sets row.data before it paints, so they see the row.
---------------------------------------------------------------------------

local ROW_PREFIX = "EasyFindResultButton"
local hookedRows = {}
local painting = false

local function NpcOf(row)
	local data = row.data
	return data and data.category == ID and data.hwNpc
end

local function OnPainted(row)
	if painting then return end
	local glyph = row.flatCatIcon
	local npcID = NpcOf(row)
	if not npcID then
		HW:ForgetNpcPortrait(glyph)
		return
	end
	painting = true
	HW:SetNpcPortrait(glyph, npcID)
	glyph:SetTexCoord(0, 1, 0, 1)
	glyph:SetDesaturated(false)
	glyph:SetVertexColor(1, 1, 1, 1)
	painting = false
end

local function OnTinted(row)
	if painting or not NpcOf(row) then return end
	painting = true
	row.flatCatIcon:SetDesaturated(false)
	row.flatCatIcon:SetVertexColor(1, 1, 1, 1)
	painting = false
end

function HookRowIcons()
	local i = 1
	while true do
		local row = _G[ROW_PREFIX .. i]
		if not row then break end
		local glyph = row.flatCatIcon
		if glyph and not hookedRows[row] then
			hookedRows[row] = true
			hooksecurefunc(glyph, "SetTexture", function() OnPainted(row) end)
			hooksecurefunc(glyph, "SetAtlas", function() OnPainted(row) end)
			hooksecurefunc(glyph, "SetVertexColor", function() OnTinted(row) end)
			hooksecurefunc(glyph, "SetDesaturated", function() OnTinted(row) end)
			-- rows first painted before they were hooked
			if row:IsShown() and NpcOf(row) then OnPainted(row) end
		end
		i = i + 1
	end
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

function EF:Register()
	local api = GetAPI()
	if not api or self.registered then return end

	api.RegisterExtension({
		id = ID,
		name = "HeadWow",
		description = "Wowhead's item database: drop sources, chances and where to find them.",
		icon = ICON,
		keywords = { "wowhead", "drops", "loot", "drop chance" },
		open = function() HW:Open() end,
		close = function() if HeadWowFrame then HeadWowFrame:Hide() end end,
		isOpen = function() return HeadWowFrame ~= nil and HeadWowFrame:IsShown() end,
		menu = function()
			return {
				{ kind = "check", label = "Tracked item on the map",
				  get = function() return HW.db.mapPins end, set = function(on) HW.Map:SetPinsShown(on) end },
				{ kind = "check", label = "Wishlist mobs on the map",
				  get = function() return HW.db.wishMap end, set = function(on) HW.Map:SetWishPinsShown(on) end },
				{ kind = "check", label = "Drop sources in item tooltips",
				  get = function() return HW.db.tooltip end, set = function(on) HW.db.tooltip = on end },
				{ kind = "check", label = "Notable drops in mob tooltips",
				  get = function() return HW.db.mobTooltip end, set = function(on) HW.db.mobTooltip = on end },
				{ kind = "separator" },
				{ kind = "action", label = "Wishlist", closes = true, onClick = function() HW:ShowWishlist() end },
				{ kind = "action", label = "Gold farming", closes = true, onClick = function() HW:ShowGoldFarm() end },
				{ kind = "action", label = "Settings", closes = true, onClick = function() HW:OpenSettings() end },
			}
		end,
	})

	-- Only here to own the rows on the item sources page (their clicks and tooltips): lazy and
	-- with no rows of its own, so it adds nothing to plain searches.
	api.RegisterSearchProvider({
		key = ID,
		label = "HeadWow",
		extension = ID,
		lazy = true,
		rows = function() return {} end,
		select = SelectRow,
		tooltip = RowTooltip,
		hint = function(row)
			if row.hwKind == "drop" then return { click = "NPC page", alt = "Map" } end
			if row.hwKind == "farm" then return { click = "Map" } end
			return { click = "HeadWow" }
		end,
		menu = function(row)
			if row.hwKind == "drop" then return NpcMenu(row.hwNpc, row.hwItem, row.hwZoneIdx) end
			return ItemMenu(row.hwItem)
		end,
	})

	api.RegisterItemSources(ID, SourceRows)

	api.RegisterRowDecorator({
		id = ID,
		label = "HeadWow",
		applies = function(row)
			return row.itemID ~= nil and row.category ~= ID and HW:GetItem(row.itemID) ~= nil
		end,
		menu = function(row) return ItemMenu(row.itemID) end,
	})

	self.registered = true
end
