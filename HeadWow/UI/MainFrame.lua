-- HeadWow's window: the shell around the views (title, top bar with back / forward, bottom
-- tabs, resize grip), the navigation history, and the entry points the rest of the addon
-- uses: HW:ShowItem, HW:ShowNpc, HW:Open, HW:Toggle, HW:ShowWishlist, HW:ShowGoldFarm.
--
-- Views live in their own files and register in HW.Views[key]:
--   view:Create(content, toolbar)  build into the content area and the top bar
--   view:OnShow()                  it became the visible view (refresh what may be stale)
--   view:OnWishlistChanged()       optional
-- The shell hides and shows view.content and view.toolbar.

local HW = HeadWow
local UI = HW.UI

HW.Views = HW.Views or {}

local DEFAULT_WIDTH, DEFAULT_HEIGHT = 980, 640
local MIN_WIDTH, MIN_HEIGHT = 860, 560
local MAX_WIDTH, MAX_HEIGHT = 1600, 1100
local MAX_HISTORY = 60

local TABS = {
	{ key = "browse", label = "Browse" },
	{ key = "wishlist", label = "Wishlist" },
	{ key = "gold", label = "Gold farming" },
}

local frame
local current -- key of the visible view

---------------------------------------------------------------------------
-- History (back / forward through items, NPCs and views)
---------------------------------------------------------------------------

local history, position = {}, 0
local navigating = false

local function EntryName(entry)
	if not entry then return nil end
	if entry.view == "item" then return HW:GetColoredItemName(entry.id) end
	if entry.view == "npc" then return HW:GetNpcName(entry.id) end
	if entry.view == "wishlist" then return "Wishlist" end
	if entry.view == "gold" then return "Gold farming" end
	return "Browse"
end

local function UpdateNavButtons()
	if not (frame and frame.Back) then return end
	frame.Back:SetEnabled(position > 1)
	frame.Forward:SetEnabled(position < #history)
end

-- Records where the user is now (views call this when they open something).
function UI.PushHistory(entry)
	if navigating then return end
	local here = history[position]
	if here and here.view == entry.view and here.id == entry.id then return end
	for i = #history, position + 1, -1 do history[i] = nil end
	history[#history + 1] = entry
	if #history > MAX_HISTORY then table.remove(history, 1) end
	position = #history
	UpdateNavButtons()
end

-- The items and NPCs looked at lately, newest first, each once.
function UI.GetRecent(max)
	local out, seen = {}, {}
	for i = #history, 1, -1 do
		local entry = history[i]
		if entry.view == "item" or entry.view == "npc" then
			local key = entry.view .. entry.id
			if not seen[key] then
				seen[key] = true
				out[#out + 1] = entry
				if #out >= max then break end
			end
		end
	end
	return out
end

local function OpenEntry(entry)
	if entry.view == "item" then HW:ShowItem(entry.id)
	elseif entry.view == "npc" then HW:ShowNpc(entry.id, entry.from)
	elseif entry.view == "home" then HW:Open()
	elseif entry.view == "wishlist" then HW:ShowWishlist()
	elseif entry.view == "gold" then HW:ShowGoldFarm() end
end

function HW:NavigateHistory(delta)
	local entry = history[position + delta]
	if not entry then return end
	position = position + delta
	navigating = true
	xpcall(OpenEntry, geterrorhandler(), entry)
	navigating = false
	UpdateNavButtons()
end

---------------------------------------------------------------------------
-- Views
---------------------------------------------------------------------------

local function SetVisibleView(key)
	for i, tab in ipairs(TABS) do
		local view = HW.Views[tab.key]
		local shown = tab.key == key
		view.content:SetShown(shown)
		view.toolbar:SetShown(shown)
		if shown then PanelTemplates_SetTab(frame, i) end
	end
	current = key
end

local function ShowView(key)
	local f = HW:GetFrame()
	SetVisibleView(key)
	if f:IsShown() then
		HW.Views[key]:OnShow()
	else
		f:Show() -- its OnShow refreshes the view
	end
end

local function UpdateWishlistTab()
	if not frame then return end
	local count = HW:GetWishlistCount()
	local tab = frame.Tabs[2]
	tab:SetText(count > 0 and ("Wishlist (" .. count .. ")") or "Wishlist")
	PanelTemplates_TabResize(tab, frame.tabPadding, nil, frame.minTabWidth, frame.maxTabWidth)
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local function SaveGeometry()
	local point, _, relPoint, x, y = frame:GetPoint(1)
	HW.db.point = { point, relPoint, x, y }
	HW.db.size = { math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5) }
end

local function RestoreGeometry()
	local size = HW.db.size
	local width = size and math.min(MAX_WIDTH, math.max(MIN_WIDTH, size[1])) or DEFAULT_WIDTH
	local height = size and math.min(MAX_HEIGHT, math.max(MIN_HEIGHT, size[2])) or DEFAULT_HEIGHT
	frame:SetSize(width, height)
	frame:ClearAllPoints()
	local p = HW.db.point
	if p then
		frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		frame:SetPoint("CENTER")
	end
end

local function CreateNavButton(direction)
	local back = direction < 0
	local button = CreateFrame("Button", nil, frame.TopBar)
	button:SetSize(28, 28)
	local base = back and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-"
	button:SetNormalTexture(base .. "Up")
	button:SetPushedTexture(base .. "Down")
	button:SetDisabledTexture(base .. "Disabled")
	button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	button:SetScript("OnClick", function() HW:NavigateHistory(direction) end)
	UI.SetTooltip(button, back and (BACK or "Back") or "Forward", function(tip)
		local target = EntryName(history[position + direction])
		if target then GameTooltip_AddHighlightLine(tip, target) end
		GameTooltip_AddDisabledLine(tip, back and "Mouse button 4" or "Mouse button 5")
	end, "ANCHOR_BOTTOM")
	button:Disable()
	return button
end

local function CreateMainFrame()
	frame = CreateFrame("Frame", "HeadWowFrame", UIParent, "ButtonFrameTemplate")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SaveGeometry()
	end)
	frame:SetTitle("HeadWow")
	frame:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Book_09")
	ButtonFrameTemplate_HideButtonBar(frame)
	frame.Inset:Hide() -- each view lays out its own panels
	frame:Hide()
	tinsert(UISpecialFrames, "HeadWowFrame") -- close on Escape
	RestoreGeometry()

	-- Mouse buttons 4 / 5 step through the history.
	frame:SetScript("OnMouseUp", function(_, button)
		if button == "Button4" then HW:NavigateHistory(-1)
		elseif button == "Button5" then HW:NavigateHistory(1) end
	end)

	-- Top bar: back / forward, then the visible view's own controls.
	local topBar = CreateFrame("Frame", nil, frame)
	topBar:SetPoint("TOPLEFT", 62, -26) -- clear of the portrait ring
	topBar:SetPoint("TOPRIGHT", -10, -26)
	topBar:SetHeight(32)
	frame.TopBar = topBar
	frame.Back = CreateNavButton(-1)
	frame.Back:SetPoint("LEFT", 4, 0)
	frame.Forward = CreateNavButton(1)
	frame.Forward:SetPoint("LEFT", frame.Back, "RIGHT", 0, 0)

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", 6, -62)
	content:SetPoint("BOTTOMRIGHT", -6, 6)
	frame.Content = content

	-- Views
	for _, tab in ipairs(TABS) do
		local view = HW.Views[tab.key]
		view.content = CreateFrame("Frame", nil, content)
		view.content:SetAllPoints()
		view.content:Hide()
		view.toolbar = CreateFrame("Frame", nil, topBar)
		view.toolbar:SetPoint("TOPLEFT", frame.Forward, "TOPRIGHT", 12, 0)
		view.toolbar:SetPoint("BOTTOMRIGHT", topBar, "BOTTOMRIGHT")
		view.toolbar:Hide()
		view:Create(view.content, view.toolbar)
	end

	-- Bottom tabs
	for i, tab in ipairs(TABS) do
		local button = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
		button:SetID(i)
		button:SetText(tab.label)
		button:SetScript("OnClick", function()
			ShowView(tab.key)
			if tab.key == "browse" then
				UI.PushHistory(HW.Views.browse:CurrentEntry())
			else
				UI.PushHistory({ view = tab.key })
			end
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
		end)
		if i == 1 then button:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2) end
	end
	PanelTemplates_SetNumTabs(frame, #TABS)
	UpdateWishlistTab()

	-- Resize grip
	local grip = CreateFrame("Button", nil, frame, "PanelResizeButtonTemplate")
	grip:SetPoint("BOTTOMRIGHT", -3, 3)
	grip:SetFrameLevel(frame:GetFrameLevel() + 50)
	grip:Init(frame, MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
	grip:HookScript("OnMouseUp", SaveGeometry)

	frame:HookScript("OnShow", function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
		if current then HW.Views[current]:OnShow() end
		HW.EasyFind:NotifyOpenChanged()
	end)
	frame:HookScript("OnHide", function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
		HW.EasyFind:NotifyOpenChanged()
	end)

	-- Items the client hadn't cached yet: redraw what's visible once their data arrives.
	frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
	frame:SetScript("OnEvent", function()
		if frame.redrawPending or not frame:IsShown() then return end
		frame.redrawPending = true
		C_Timer.After(0.25, function()
			frame.redrawPending = false
			HW:RefreshVisibleRows()
		end)
	end)

	SetVisibleView("browse")
	UI.PushHistory({ view = "home" })
end

---------------------------------------------------------------------------
-- Entry points
---------------------------------------------------------------------------

function HW:GetFrame()
	if not frame then CreateMainFrame() end
	return frame
end

function HW:Toggle()
	local f = self:GetFrame()
	f:SetShown(not f:IsShown())
end

-- Opens the browser, searching for query when given.
function HW:Open(query)
	self:GetFrame()
	local browse = HW.Views.browse
	if query then
		browse:SetQuery(query)
	elseif navigating then
		browse:ShowHome()
	end
	ShowView("browse")
end

-- Opens an item's page (alt-click, slash command, links, map, EasyFind).
function HW:ShowItem(itemID)
	if not self:GetItem(itemID) then
		self:Print("Item " .. itemID .. " is not in the snapshot.")
		return
	end
	self:GetFrame()
	HW.Views.browse:SelectItem(itemID)
	ShowView("browse")
end

-- Opens an NPC's page. fromItemID: the item it was opened from (its drop is highlighted).
function HW:ShowNpc(npcID, fromItemID)
	self:GetFrame()
	HW.Views.browse:SelectNpc(npcID, fromItemID)
	ShowView("browse")
end

function HW:ShowWishlist()
	self:GetFrame()
	ShowView("wishlist")
	UI.PushHistory({ view = "wishlist" })
end

function HW:ShowGoldFarm()
	self:GetFrame()
	ShowView("gold")
	UI.PushHistory({ view = "gold" })
end

-- Back to the default size, in the middle of the screen.
function HW:ResetWindow()
	self.db.point, self.db.size = nil, nil
	if frame then RestoreGeometry() end
end

-- Called by the wishlist whenever an item is starred or unstarred.
function HW:OnWishlistChanged()
	if not frame then return end
	UpdateWishlistTab()
	for _, tab in ipairs(TABS) do
		local view = HW.Views[tab.key]
		if view.OnWishlistChanged then view:OnWishlistChanged() end
	end
end

-- Redraws the visible result rows (prices, names that just loaded, stars).
function HW:RefreshVisibleRows()
	if frame then HW.Views.browse:RefreshRows() end
end
