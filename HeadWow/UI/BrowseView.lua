-- Browse: search items and NPCs. Results on the left (switch between Items and NPCs), and on
-- the right the item page, the NPC page, or while nothing is open a home page with shortcuts,
-- what you looked at lately and a few tips.

local HW = HeadWow
local UI = HW.UI
local F = HW.F
local Data = HeadWowData

local Browse = {}
HW.Views = HW.Views or {}
HW.Views.browse = Browse

local LIST_WIDTH = 310
local SEARCH_DELAY = 0.12
local MAX_RECENT = 8

local filters = HW:CreateDefaultFilters()
local scope = "items"                 -- which results the list shows: "items" or "npcs"
local selection = { view = "home" }   -- what the right-hand side shows
local SCOPE_ITEMS, SCOPE_NPCS          -- tab IDs

local ui = {}                         -- this view's frames

---------------------------------------------------------------------------
-- Result row (an item or an NPC)
---------------------------------------------------------------------------

HeadWowResultRowMixin = {}

function HeadWowResultRowMixin:OnLoad()
	self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
end

function HeadWowResultRowMixin:Init(element)
	self.kind, self.id = element.kind, element.id
	self:Refresh()
end

function HeadWowResultRowMixin:Refresh()
	local id = self.id
	local selected
	if self.kind == "npc" then
		HW:SetNpcPortrait(self.Icon, id)
		self.Name:SetText(HW:GetNpcName(id))
		self.Name:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
		local info = {}
		local level = HW:FormatNpcLevel(id)
		if level ~= "" then info[#info + 1] = (LEVEL or "Level") .. " " .. level end
		local zones = HW:GetNpcZoneText(id, 2)
		if zones ~= "" then info[#info + 1] = zones end
		self.Info:SetText(table.concat(info, "  ·  "))
		self.Price:SetText("")
		self.Star:Hide()
		selected = selection.view == "npc" and selection.id == id
	else
		local row = HW:GetItem(id)
		if not row then return end
		HW:ForgetNpcPortrait(self.Icon)
		self.Icon:SetTexture(HW:GetItemIcon(id))
		self.Icon:SetVertexColor(1, 1, 1)
		local quality = HW:GetItemQuality(id)
		if quality == nil then C_Item.RequestLoadItemDataByID(id) end
		self.Name:SetText(row[F.NAME])
		self.Name:SetTextColor(HW:GetQualityColor(quality))

		local info = {}
		if row[F.ILVL] then info[#info + 1] = "iLvl " .. row[F.ILVL] end
		if row[F.SLOT] then info[#info + 1] = HW:GetSlotName(row[F.SLOT]) end
		local source = HW:GetSourceText(row[F.SOURCE])
		if source then info[#info + 1] = source end
		self.Info:SetText(table.concat(info, "  ·  "))

		-- AH price; grayed with a ~ when the item has no steady market
		local price, reliable = HW:GetShownAuctionPrice(id)
		local text = price and GetMoneyString(price, true) or ""
		if price and reliable == false then text = "~" .. text end
		self.Price:SetText(text)
		self.Price:SetAlpha(reliable == false and 0.5 or 1)

		local wished = HW:IsWished(id)
		if wished then HW:SetStarTexture(self.Star, true) end
		self.Star:SetShown(wished)
		selected = selection.view == "item" and selection.id == id
	end
	self.Selected:SetShown(selected)
	self.SelectedBar:SetShown(selected)
end

function HeadWowResultRowMixin:OnClick(button)
	local id = self.id
	if self.kind == "npc" then
		if button == "RightButton" then HW:ShowNpcContextMenu(self, id) else Browse:SelectNpc(id) end
		return
	end
	if button == "RightButton" then
		HW:ShowItemContextMenu(self, id)
	elseif IsModifiedClick("CHATLINK") then
		HW:InsertItemLink(id)
	elseif IsModifiedClick("DRESSUP") then
		HW:WithItemLink(id, DressUpItemLink)
	else
		Browse:SelectItem(id)
	end
end

function HeadWowResultRowMixin:OnEnter()
	if self.kind == "npc" then
		HW:ShowNpcTooltip(self, self.id, "ANCHOR_LEFT")
	else
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetItemByID(self.id)
		GameTooltip:Show()
	end
end

function HeadWowResultRowMixin:OnLeave()
	GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Filter menu
---------------------------------------------------------------------------

local function SortedSlots()
	local list = {}
	for idx, name in ipairs(Data.slots) do list[#list + 1] = { idx = idx, name = name } end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

local function SetupFilterMenu(_, root)
	local function Changed() Browse:Search() end

	local qualityMenu = root:CreateButton(QUALITY or "Quality")
	for q = 5, 0, -1 do
		local label = _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)
		qualityMenu:CreateCheckbox(HW:GetQualityHex(q) .. label .. "|r",
			function() return filters.qualities[q] end,
			function() filters.qualities[q] = not filters.qualities[q]; Changed() end)
	end
	qualityMenu:CreateCheckbox("Unknown",
		function() return filters.qualities[-1] end,
		function() filters.qualities[-1] = not filters.qualities[-1]; Changed() end)
	qualityMenu:CreateDivider()
	qualityMenu:CreateButton(CHECK_ALL or "Check all", function()
		for q = -1, 5 do filters.qualities[q] = true end
		Changed()
		return MenuResponse.Refresh
	end)
	qualityMenu:CreateButton(UNCHECK_ALL or "Uncheck all", function()
		for q = -1, 5 do filters.qualities[q] = false end
		Changed()
		return MenuResponse.Refresh
	end)

	local sourceMenu = root:CreateButton(SOURCES or "Source")
	for _, source in ipairs(HW.SOURCES) do
		sourceMenu:CreateCheckbox(source.label,
			function() return bit.band(filters.sources, source.bit) ~= 0 end,
			function() filters.sources = bit.bxor(filters.sources, source.bit); Changed() end)
	end

	local slotMenu = root:CreateButton("Slot")
	slotMenu:SetScrollMode(20 * 16)
	slotMenu:CreateRadio("Any", function() return filters.slot == nil end, function() filters.slot = nil; Changed() end)
	for _, slot in ipairs(SortedSlots()) do
		slotMenu:CreateRadio(slot.name,
			function() return filters.slot == slot.idx end,
			function() filters.slot = slot.idx; Changed() end)
	end

	local _, className = UnitClass("player")
	local charMenu = root:CreateButton("My character")
	local function Toggle(key, label, tooltip)
		local box = charMenu:CreateCheckbox(label,
			function() return filters[key] end,
			function() filters[key] = not filters[key]; Changed() end)
		box:SetTooltip(function(tip) GameTooltip_AddNormalLine(tip, tooltip, true) end)
	end
	Toggle("classUsable", "Usable by " .. (className or "my class"),
		"Weapons and armor your class can learn to use. Everything else is kept.")
	Toggle("armorType", "My armor type only",
		"Body armor of your class's type: plate for warriors and paladins, mail for hunters and shamans (one type lighter before level 40), leather for rogues and druids, cloth for casters. Cloaks, rings and other gear are kept.")
	Toggle("levelUsable", "Usable at my level", "Items whose required level you have reached.")
	Toggle("npcLevel", "NPCs near my level",
		"NPCs within 5 levels of yours. NPCs whose level isn't known are left out.")

	root:CreateDivider()
	root:CreateCheckbox("Has drop sources",
		function() return filters.dropsOnly end,
		function() filters.dropsOnly = not filters.dropsOnly; Changed() end)
	root:CreateCheckbox("Search NPCs too",
		function() return filters.npcs end,
		function() filters.npcs = not filters.npcs; Changed() end)
end

---------------------------------------------------------------------------
-- Home page (nothing selected)
---------------------------------------------------------------------------

local ICONS = {
	wishlist = "Interface\\Icons\\INV_Misc_Note_02",
	gold = "Interface\\Icons\\INV_Misc_Coin_02",
	map = "Interface\\Icons\\INV_Misc_Map_01",
	settings = "Interface\\Icons\\Trade_Engineering",
}

local function CreateHome(host)
	local home = CreateFrame("Frame", nil, host)
	home:SetAllPoints()

	local title = home:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 6, -8)
	title:SetText("Find any item or NPC")
	local subtitle = home:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	subtitle:SetPoint("RIGHT", -6, 0)
	subtitle:SetJustifyH("LEFT")
	home.Subtitle = subtitle

	home.Jump = UI.CreateCard(home, "Go to")
	home.Jump:SetPoint("TOPLEFT", 0, -52)
	home.Jump:SetPoint("RIGHT", home, "CENTER", -5, 0)

	home.Tips = UI.CreateCard(home, "Tips")
	home.Tips:SetPoint("TOPLEFT", home.Jump, "BOTTOMLEFT", 0, -10)
	home.Tips:SetPoint("RIGHT", home, "CENTER", -5, 0)

	home.Recent = UI.CreateCard(home, "Recently viewed")
	home.Recent:SetPoint("TOPLEFT", home, "TOP", 5, -52)
	home.Recent:SetPoint("RIGHT", home, "RIGHT", 0, 0)

	home.Tips:SetRows({
		{ text = "Alt-click any item (bags, chat, loot) to open it here" },
		{ text = "Shift-click: link in chat  ·  Ctrl-click: preview" },
		{ text = "Point at mobs in the world to see their best drops" },
		{ text = "Right-click rows for more options" },
		{ text = "Mouse buttons 4 and 5 go back and forward" },
	})
	return home
end

local function RefreshHome()
	local home = ui.Home
	local snapshot = Data.snapshot and Data.snapshot:sub(1, 10)
	home.Subtitle:SetText(string.format("Wowhead's WoW Forever database%s: %s items, %s NPCs.",
		snapshot and (", snapshot of " .. snapshot) or "",
		BreakUpLargeNumbers(ui.itemCount or 0), BreakUpLargeNumbers(ui.npcCount or 0)))

	local count = HW:GetWishlistCount()
	local jump = {
		{ icon = ICONS.wishlist, text = "Wishlist", value = count == 1 and "1 item" or (count .. " items"),
		  onClick = function() HW:ShowWishlist() end },
		{ icon = ICONS.gold, text = "Gold farming", value = "mobs ranked by loot value",
		  onClick = function() HW:ShowGoldFarm() end },
	}
	local tracked = HW.Map:GetActive()
	if tracked then
		jump[#jump + 1] = { icon = HW:GetItemIcon(tracked.itemID), text = "On the map: " .. HW:GetColoredItemName(tracked.itemID),
			onClick = function() HW:ShowItem(tracked.itemID) end }
	end
	jump[#jump + 1] = { icon = ICONS.settings, text = "Settings", onClick = function() HW:OpenSettings() end }
	home.Jump:SetRows(jump)

	local recent = {}
	for _, entry in ipairs(UI.GetRecent(MAX_RECENT)) do
		if entry.view == "item" then
			recent[#recent + 1] = { icon = HW:GetItemIcon(entry.id), text = HW:GetColoredItemName(entry.id),
				onClick = function() HW:ShowItem(entry.id) end }
		else
			recent[#recent + 1] = { npcID = entry.id, text = HW:GetNpcName(entry.id), value = HW:FormatNpcLevel(entry.id, true),
				onClick = function() HW:ShowNpc(entry.id) end }
		end
	end
	home.Recent:SetRows(recent, "Items and NPCs you open show up here.")
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

function Browse:Create(content, toolbar)
	-- Toolbar: search, filter, result summary
	local search = CreateFrame("EditBox", nil, toolbar, "SearchBoxTemplate")
	search:SetSize(270, 20)
	search:SetPoint("LEFT", 6, 0)
	search.Instructions:SetText("Search items and NPCs")
	-- React to any change, not only typing: the clear button and HW:Open set the text from code.
	local lastText = ""
	search:HookScript("OnTextChanged", function(self)
		local text = self:GetText()
		if text == lastText then return end
		lastText = text
		if ui.searchTimer then ui.searchTimer:Cancel() end
		ui.searchTimer = C_Timer.NewTimer(SEARCH_DELAY, function() Browse:Search() end)
	end)
	search:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		local list = scope == "items" and ui.items or ui.npcs
		local first = list and list[1]
		if first then
			if scope == "items" then Browse:SelectItem(first) else Browse:SelectNpc(first) end
		end
	end)
	ui.Search = search

	local filter = CreateFrame("DropdownButton", nil, toolbar, "WowStyle1FilterDropdownTemplate")
	filter:SetPoint("LEFT", search, "RIGHT", 12, 0)
	filter:SetupMenu(SetupFilterMenu)
	filter:SetIsDefaultCallback(function() return HW:IsDefaultFilters(filters) end)
	filter:SetDefaultCallback(function()
		filters = HW:CreateDefaultFilters()
		Browse:Search()
	end)
	ui.Filter = filter

	local summary = toolbar:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	summary:SetPoint("RIGHT", -6, 0)
	summary:SetJustifyH("RIGHT")
	ui.Summary = summary

	-- Left: Items / NPCs switch over the results
	local tabs = CreateFrame("Frame", nil, content, "HeadWowTopTabSystemTemplate")
	tabs:SetPoint("TOPLEFT", 8, 0)
	SCOPE_ITEMS = tabs:AddTab("Items")
	SCOPE_NPCS = tabs:AddTab("NPCs")
	tabs:SetTabSelectedCallback(function(tabID)
		scope = tabID == SCOPE_NPCS and "npcs" or "items"
		Browse:ShowList()
		return false
	end)
	ui.Tabs = tabs

	local list = CreateFrame("Frame", nil, content, "InsetFrameTemplate")
	list:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", -8, 1)
	list:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
	list:SetWidth(LIST_WIDTH)

	local scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", 3, -3)
	scrollBox:SetPoint("BOTTOMRIGHT", -UI.SCROLLBAR_SPACE, 3)
	local scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, -2)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 2)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(36)
	view:SetElementInitializer("HeadWowResultRowTemplate", function(row, element) row:Init(element) end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	ui.ScrollBox = scrollBox

	local empty = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	empty:SetPoint("CENTER", scrollBox, "CENTER")
	empty:SetWidth(LIST_WIDTH - 40)
	empty:SetSpacing(3)
	ui.Empty = empty

	-- Right: home / item / NPC
	local host = CreateFrame("Frame", nil, content)
	host:SetPoint("TOPLEFT", content, "TOPLEFT", LIST_WIDTH + 10, 0)
	host:SetPoint("BOTTOMRIGHT")
	ui.Host = host
	ui.Home = CreateHome(host)
	HW.ItemView:Create(host)
	HW.NpcView:Create(host)

	local itemCount, npcCount = 0, 0
	for _ in pairs(Data.items) do itemCount = itemCount + 1 end
	for _ in pairs(Data.npcs) do npcCount = npcCount + 1 end
	ui.itemCount, ui.npcCount = itemCount, npcCount

	tabs:SetTab(SCOPE_ITEMS)
	self:Search()
	self:ShowSelection()
end

---------------------------------------------------------------------------
-- Searching and the list
---------------------------------------------------------------------------

function Browse:Search()
	local query = ui.Search:GetText()
	local items = HW:Search(query, filters)
	local npcs = filters.npcs and HW:SearchNpcs(query) or {}
	if filters.npcLevel then npcs = HW:FilterNpcsByLevel(npcs) end
	ui.items, ui.npcs = items, npcs

	-- An empty side gives way to the other (searching "Hogger" shows the NPC).
	if scope == "items" and #items == 0 and #npcs > 0 then scope = "npcs"
	elseif scope == "npcs" and #npcs == 0 and #items > 0 then scope = "items" end

	UI.SetTabText(ui.Tabs, SCOPE_ITEMS, "Items  " .. HW:GrayText(BreakUpLargeNumbers(#items)))
	UI.SetTabText(ui.Tabs, SCOPE_NPCS, "NPCs  " .. HW:GrayText(BreakUpLargeNumbers(#npcs)))
	ui.Tabs:SetTab(scope == "npcs" and SCOPE_NPCS or SCOPE_ITEMS) -- shows the list
	ui.Filter:ValidateResetState()
	ui.Summary:SetText(HW:IsDefaultFilters(filters) and "" or "Filtered")
end

function Browse:ShowList()
	local list = scope == "npcs" and ui.npcs or ui.items
	local kind = scope == "npcs" and "npc" or "item"
	local elements = {}
	for i, id in ipairs(list or {}) do elements[i] = { kind = kind, id = id } end
	ui.ScrollBox:SetDataProvider(CreateDataProvider(elements))

	local query = strtrim(ui.Search:GetText() or "")
	if #elements > 0 then
		ui.Empty:Hide()
	else
		if scope == "npcs" and query == "" then
			ui.Empty:SetText(filters.npcs and "Type a name to search NPCs." or "NPC search is off in the filter menu.")
		else
			ui.Empty:SetText("Nothing matches.\nTry fewer words or a looser filter.")
		end
		ui.Empty:Show()
	end
end

function Browse:RefreshRows()
	if ui.ScrollBox then ui.ScrollBox:ForEachFrame(function(row) row:Refresh() end) end
end

function Browse:SetQuery(text)
	ui.Search:SetText(text or "")
	self:Search()
end

---------------------------------------------------------------------------
-- Selection
---------------------------------------------------------------------------

function Browse:ShowSelection()
	local view = selection.view
	ui.Home:SetShown(view == "home")
	if view ~= "item" then HW.ItemView:Hide() end
	if view ~= "npc" then HW.NpcView:Hide() end
	if view == "home" then RefreshHome() end
	self:RefreshRows()
end

function Browse:SelectItem(itemID)
	selection = { view = "item", id = itemID }
	HW.ItemView:Show(itemID)
	self:ShowSelection()
	UI.PushHistory(selection)
end

function Browse:SelectNpc(npcID, fromItemID)
	selection = { view = "npc", id = npcID, from = fromItemID }
	HW.NpcView:Show(npcID, fromItemID)
	self:ShowSelection()
	UI.PushHistory(selection)
end

function Browse:ShowHome()
	selection = { view = "home" }
	self:ShowSelection()
	UI.PushHistory(selection)
end

function Browse:CurrentEntry()
	return selection
end

function Browse:OnShow()
	-- prices may have moved (an Auctionator scan), the map may track something new
	self:RefreshRows()
	if selection.view == "home" then RefreshHome()
	elseif selection.view == "item" then HW.ItemView:Refresh()
	elseif selection.view == "npc" then HW.NpcView:Refresh() end
end

function Browse:OnWishlistChanged()
	self:RefreshRows()
	if selection.view == "home" then RefreshHome() end
	HW.ItemView:OnWishlistChanged()
	HW.NpcView:OnWishlistChanged()
end
