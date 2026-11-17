-- Gold farming: mobs well below your level, ranked by what their drops sell for (GoldFarm.lua
-- works out the values). The full width of the window, since it has the most columns.

local HW = HeadWow
local UI = HW.UI

local Gold = {}
HW.Views = HW.Views or {}
HW.Views.gold = Gold

local MAX_ROWS = 400 -- the long tail isn't worth farming; keeps sorting quick
local ui = {}

local function LevelLabel(below)
	if below == 0 then return "Any level" end
	return below .. "+ levels below you"
end

local SPEC = {
	columns = {
		{ title = "NPC", icon = function(e) return "npc", e.npcID end, text = function(e) return e.name end, sort = UI.ByText("name") },
		{ title = "Level", width = 54, text = function(e) return HW:FormatNpcLevel(e.npcID, true) end,
		  sort = UI.ByNumber("maxLevel"), descending = true },
		{ title = "Zone", width = 150, font = "GameFontDisableSmall", text = function(e) return e.zone or "" end, sort = UI.ByText("zone") },
		{ title = "Camp", width = 58, align = "RIGHT", font = "GameFontDisableSmall",
		  text = function(e) return e.spawns and tostring(e.spawns) or "?" end, sort = UI.ByNumber("spawns"), descending = true },
		{ title = "Per kill", width = 76, align = "RIGHT", text = function(e) return HW:FormatMoneyShort(e.perKill) end,
		  sort = UI.ByNumber("perKill"), descending = true },
		{ title = "Per clear", width = 84, align = "RIGHT",
		  text = function(e) return e.perClear and HW:FormatMoneyShort(e.perClear) or "|cff808080?|r" end,
		  sort = UI.ByNumber("perClear"), descending = true },
		{ title = "Worth most", flex = 1, font = "GameFontDisableSmall",
		  text = function(e) local top = e.top[1]; return top and HW:GetColoredItemName(top.itemID) or "" end },
	},
	sort = 6, descending = true, footer = true, maxRows = MAX_ROWS,
	onClick = function(e, button, row)
		if button == "RightButton" then HW:ShowNpcContextMenu(row, e.npcID, nil, e.mapID) else HW:ShowNpc(e.npcID) end
	end,
	onEnter = function(e, row) Gold:ShowTooltip(e, row) end,
}

function Gold:ShowTooltip(e, row)
	local tooltip = GameTooltip
	local white = HIGHLIGHT_FONT_COLOR
	tooltip:SetOwner(row, "ANCHOR_RIGHT")
	HW:FillNpcTooltip(tooltip, e.npcID)
	GameTooltip_AddBlankLineToTooltip(tooltip)
	GameTooltip_AddColoredDoubleLine(tooltip, "Per kill", HW:FormatMoneyShort(e.perKill), NORMAL_FONT_COLOR, white)
	if e.spawns then
		GameTooltip_AddColoredDoubleLine(tooltip, "Spawns in the best camp", tostring(e.spawns), NORMAL_FONT_COLOR, white)
		GameTooltip_AddColoredDoubleLine(tooltip, "Per clear of the camp", HW:FormatMoneyShort(e.perClear), NORMAL_FONT_COLOR, white)
		GameTooltip_AddHighlightLine(tooltip, string.format("The densest %d-yard area of %s, around %.0f, %.0f (%d spawns in the zone).",
			HW.CAMP_SIZE, e.zone, e.campX * 100, e.campY * 100, e.zoneSpawns), true)
	end
	if e.kills > 0 then
		GameTooltip_AddColoredDoubleLine(tooltip, "Kills recorded on Wowhead", BreakUpLargeNumbers(e.kills), NORMAL_FONT_COLOR, white)
	end
	if e.skinPerKill and e.skinPerKill > 0 then
		GameTooltip_AddColoredDoubleLine(tooltip, "  of that from skinning", HW:FormatMoneyShort(e.skinPerKill), NORMAL_FONT_COLOR, white)
	end
	GameTooltip_AddBlankLineToTooltip(tooltip)
	GameTooltip_AddNormalLine(tooltip, "Where the value comes from")
	for _, top in ipairs(e.top) do
		local left = ("|T%s:14:14|t %s%s"):format(HW:GetItemIcon(top.itemID), HW:GetColoredItemName(top.itemID),
			top.skinned and " |cff808080(skinned)|r" or "")
		local stack = top.stack and top.stack >= 1.05 and (" × %.1f"):format(top.stack) or ""
		local right = ("%s%s × %s%s = %s"):format(HW:FormatChance(top.chance), stack, HW:FormatMoneyShort(top.value),
			top.source == "ah" and " |cff808080AH|r" or "", HW:FormatMoneyShort(top.contrib))
		GameTooltip_AddColoredDoubleLine(tooltip, left, right, white, white)
		if top.source == "ah" and top.market then
			GameTooltip_AddDisabledLine(tooltip, "      AH median, " .. HW:DescribeMarket(top.market))
		end
	end
	if #e.ignored > 0 then
		GameTooltip_AddBlankLineToTooltip(tooltip)
		GameTooltip_AddNormalLine(tooltip, "AH prices left out (no steady market)")
		for _, ign in ipairs(e.ignored) do
			local left = ("|T%s:14:14|t %s"):format(HW:GetItemIcon(ign.itemID), HW:GetColoredItemName(ign.itemID))
			GameTooltip_AddColoredDoubleLine(tooltip, left, HW:FormatMoneyShort(ign.market.price), white, GRAY_FONT_COLOR)
			GameTooltip_AddDisabledLine(tooltip, "      " .. ign.market.reason)
		end
	end
	GameTooltip_AddBlankLineToTooltip(tooltip)
	GameTooltip_AddInstructionLine(tooltip, "Click: NPC page  ·  Right-click: map")
	tooltip:Show()
	HW:AttachNpcCard(tooltip, e.npcID)
end

function Gold:Create(content, toolbar)
	local level = UI.Dropdown(toolbar, 170, function(_, root)
		for _, below in ipairs(HW.GoldFarm.LEVEL_OPTIONS) do
			root:CreateRadio(LevelLabel(below),
				function() return HW.db.farmBelow == below end,
				function() HW.db.farmBelow = below; Gold:Refresh() end)
		end
	end)
	level:SetPoint("LEFT", 4, 0)

	local price = UI.Dropdown(toolbar, 200, function(_, root)
		for _, mode in ipairs(HW.GoldFarm.PRICE_MODES) do
			local radio = root:CreateRadio(mode.label,
				function() return HW.db.farmPrice == mode.key end,
				function() HW.db.farmPrice = mode.key; Gold:Refresh() end)
			if mode.key ~= "vendor" and not HW:HasAuctionPrices() then
				radio:SetTooltip(function(tip) GameTooltip_AddNormalLine(tip, "Needs Auctionator; without it vendor prices are used.", true) end)
			end
		end
	end)
	price:SetPoint("LEFT", level, "RIGHT", 8, 0)

	ui.Elites = UI.Checkbox(toolbar, "Elites and rares",
		function() return HW.db.farmElites end,
		function(on) HW.db.farmElites = on; Gold:Refresh() end)
	ui.Elites:SetPoint("LEFT", price, "RIGHT", 10, 0)

	ui.Skinning = UI.Checkbox(toolbar, "Skinning",
		function() return HW.db.farmSkinning end,
		function(on) HW.db.farmSkinning = on; Gold:Refresh() end,
		"Count what skinning the mob gives (leather, hides, scales) in its value.")
	ui.Skinning:SetPoint("LEFT", ui.Elites, "LEFT", UI.CheckboxWidth(ui.Elites) + 12, 0)

	ui.Summary = toolbar:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	ui.Summary:SetPoint("RIGHT", -6, 0)
	ui.Summary:SetJustifyH("RIGHT")

	local inset = CreateFrame("Frame", nil, content, "InsetFrameTemplate")
	inset:SetAllPoints()
	ui.Table = UI.CreateTable(inset, SPEC)
	ui.Table:SetAllPoints()
end

function Gold:Refresh()
	local db = HW.db
	local opts = { below = db.farmBelow or 0, elites = db.farmElites, price = HW.GoldFarm:PriceMode(), skinning = db.farmSkinning }
	local entries, unknownLevels = HW.GoldFarm:Build(opts)
	local hasSpawns = HW:HasSpawnData()
	local tbl = ui.Table
	if not hasSpawns and tbl.sortColumn == 6 then
		tbl.sortColumn = 5 -- no per clear without spawn data
		tbl:Layout()
	end

	local empty
	if unknownLevels > 0 and #entries == 0 then
		empty = "The levels of these mobs aren't known.\nChoose \"Any level\" to see them."
	else
		empty = "No mobs match. Try fewer levels below you."
	end
	tbl:SetData(entries, empty)

	local prices = opts.price == "vendor" and "vendor sell price"
		or "vendor price, or the AH median minus the 5% cut for items listed on most of your recent scan days"
	local footer = "Per kill: drop chance × average stack × " .. prices .. ". "
	footer = footer .. (hasSpawns
		and ("Per clear: per kill × spawns in the mob's best camp (its densest " .. HW.CAMP_SIZE .. "-yard area).")
		or "No spawn points known, so no camps or per clear.")
	footer = footer .. "\nNot counted: coin, kill speed, respawn time"
		.. (opts.skinning and "." or ", skinning (tick Skinning to count it).")
		.. " Drops under 0.05% beyond an item's 25 best sources aren't bundled."
	tbl:SetFooter(footer)

	local playerLevel = UnitLevel("player")
	ui.Summary:SetText(opts.below > 0
		and string.format("Level %d and below  ·  %d mobs", playerLevel - opts.below, #entries)
		or string.format("%d mobs", #entries))
	ui.Elites:Update()
	ui.Skinning:Update()
end

function Gold:OnShow()
	self:Refresh()
end
