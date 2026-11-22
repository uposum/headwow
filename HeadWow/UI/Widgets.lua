-- Shared UI building blocks: sortable tables, cards with link rows, buttons, checkboxes,
-- dropdowns, and the item / NPC context menus. Everything is made of native client
-- templates (ColumnDisplayTemplate, WowScrollBoxList, UIPanelButtonTemplate, ...).

local HW = HeadWow

local UI = {}
HW.UI = UI

UI.SCROLLBAR_SPACE = 18
UI.ROW_HEIGHT = 24
UI.LINK_ROW_HEIGHT = 20

---------------------------------------------------------------------------
-- Small widgets
---------------------------------------------------------------------------

-- Adds a tooltip to a frame: fill(tooltip) adds the lines after the title.
function UI.SetTooltip(frame, title, fill, anchor)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, type(title) == "function" and title() or title)
		if fill then fill(GameTooltip) end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
end

function UI.Button(parent, text, onClick, width)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetText(text)
	button:SetSize(width or math.max(90, button:GetTextWidth() + 30), 22)
	button:SetScript("OnClick", onClick)
	return button
end

-- A checkbox with a label; get() gives its state, set(on) is called on clicks.
function UI.Checkbox(parent, label, get, set, tooltip)
	local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	box:SetSize(24, 24)
	local text = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	text:SetPoint("LEFT", box, "RIGHT", 1, 0)
	text:SetText(label)
	box.Label = text
	box:SetHitRectInsets(0, -(text:GetStringWidth() + 6), 0, 0)
	box:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	function box:Update() self:SetChecked(get() and true or false) end
	box:SetScript("OnShow", box.Update)
	if tooltip then UI.SetTooltip(box, label, function(tip) GameTooltip_AddNormalLine(tip, tooltip, true) end) end
	box:Update()
	return box
end

-- A width the checkbox and its label take up, for laying out rows of them.
function UI.CheckboxWidth(box)
	return 26 + box.Label:GetStringWidth()
end

function UI.Dropdown(parent, width, setup)
	local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dropdown:SetWidth(width)
	dropdown:SetupMenu(setup)
	return dropdown
end

-- Renames a TabSystem tab (e.g. to update a count) and fits its width to the new text.
function UI.SetTabText(tabSystem, tabID, text)
	local button = tabSystem.GetTabButton and tabSystem:GetTabButton(tabID)
	if not button then return end
	button.tabText = text
	if button.UpdateTabText then button:UpdateTabText() else button:SetText(text) end
	if button.UpdateTabWidth then
		button.Text:SetWidth(0)
		button:UpdateTabWidth()
	end
end

---------------------------------------------------------------------------
-- Cards: a titled panel of link rows (icon, text, value), sized to its rows
---------------------------------------------------------------------------

local CardMixin = {}

local function CreateLinkRow(card, index)
	local row = CreateFrame("Button", nil, card)
	row:SetHeight(UI.LINK_ROW_HEIGHT)
	row:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -26 - (index - 1) * UI.LINK_ROW_HEIGHT)
	row:SetPoint("RIGHT", card, "RIGHT", -6, 0)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)

	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(16, 16)
	row.Icon:SetPoint("LEFT", 2, 0)

	row.Value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Value:SetPoint("RIGHT", -4, 0)
	row.Value:SetJustifyH("RIGHT")
	row.Value:SetWordWrap(false)

	row.Text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Text:SetPoint("RIGHT", row.Value, "LEFT", -6, 0)
	row.Text:SetJustifyH("LEFT")
	row.Text:SetWordWrap(false)

	row:SetScript("OnClick", function(self, button)
		if self.data and self.data.onClick then self.data.onClick(button, self) end
	end)
	row:SetScript("OnEnter", function(self)
		if self.data and self.data.onEnter then self.data.onEnter(self) end
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

local function SetLinkRow(row, data)
	row.data = data
	local icon = row.Icon
	row.Text:ClearAllPoints()
	if data.npcID then
		HW:SetNpcPortrait(icon, data.npcID)
		icon:Show()
	elseif data.icon then
		HW:ForgetNpcPortrait(icon)
		icon:SetTexture(data.icon)
		icon:SetVertexColor(1, 1, 1)
		icon:Show()
	else
		HW:ForgetNpcPortrait(icon)
		icon:Hide()
	end
	row.Text:SetPoint("LEFT", icon:IsShown() and icon or row, icon:IsShown() and "RIGHT" or "LEFT", icon:IsShown() and 6 or 4, 0)
	row.Text:SetPoint("RIGHT", row.Value, "LEFT", -6, 0)
	row.Text:SetText(data.text or "")
	row.Text:SetFontObject(data.dim and "GameFontDisableSmall" or "GameFontHighlightSmall")
	row.Value:SetText(data.value or "")
	row:EnableMouse(data.onClick ~= nil or data.onEnter ~= nil)
end

-- rows: list of { text, value, icon | npcID, onClick(button, row), onEnter(row), dim }.
-- emptyText shows when there are none.
function CardMixin:SetRows(rows, emptyText)
	for i, data in ipairs(rows) do
		local row = self.Rows[i] or CreateLinkRow(self, i)
		self.Rows[i] = row
		SetLinkRow(row, data)
		row:Show()
	end
	for i = #rows + 1, #self.Rows do self.Rows[i]:Hide() end
	local empty = #rows == 0 and emptyText
	self.Empty:SetText(empty or "")
	self.Empty:SetShown(empty and true or false)
	self:SetHeight(32 + #rows * UI.LINK_ROW_HEIGHT + (empty and 14 or 0))
end

function CardMixin:SetTitle(text)
	self.Title:SetText(text)
end

function UI.CreateCard(parent, title)
	local card = CreateFrame("Frame", nil, parent)
	Mixin(card, CardMixin)
	local bg = card:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.3)
	local rule = card:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 6, -22)
	rule:SetPoint("TOPRIGHT", -6, -22)
	rule:SetColorTexture(1, 0.82, 0, 0.2)

	card.Title = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	card.Title:SetPoint("TOPLEFT", 8, -6)
	card.Title:SetPoint("RIGHT", -8, 0)
	card.Title:SetJustifyH("LEFT")
	card.Title:SetText(title or "")

	card.Empty = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	card.Empty:SetPoint("TOPLEFT", 10, -28)
	card.Empty:SetPoint("RIGHT", -10, 0)
	card.Empty:SetJustifyH("LEFT")
	card.Empty:Hide()

	card.Rows = {}
	card:SetHeight(32)
	return card
end

---------------------------------------------------------------------------
-- Tables: sortable columns over a ScrollBox
--
-- spec = {
--   columns = { {
--     title,                 header text
--     width | flex,          fixed width, or a share of the space left (default flex 1)
--     align,                 "LEFT" (default) or "RIGHT"
--     font,                  font object for the cell (default GameFontHighlightSmall)
--     icon = fn(item),       first column only: returns "npc", npcID | "item", itemID | "texture", file
--     text = fn(item),       the cell's text
--     sort = fn(a, b),       a < b; columns without one can't be sorted
--     descending,            the first click on the header sorts high to low
--   }, ... },
--   sort, descending,        the starting sort
--   onClick(item, button, row), onEnter(item, row),
--   tint = fn(item),         a color ({ r, g, b, a }) to wash the item's row in, or nil
--   footer = true,           a line of small print under the table
--   maxRows,                 cap on rows shown (after sorting)
--   inset = true,            draw its own inset background
-- }
---------------------------------------------------------------------------

local TableMixin = {}

function UI.CreateTable(parent, spec)
	local tbl = CreateFrame("Frame", nil, parent, spec.inset and "InsetFrameTemplate" or nil)
	Mixin(tbl, TableMixin)
	tbl.spec = spec
	tbl.sortColumn = spec.sort or 1
	tbl.sortDescending = spec.descending and true or false
	tbl.items = {}
	tbl.widths = {}

	local columns = CreateFrame("Frame", nil, tbl, "ColumnDisplayTemplate")
	columns.Background:Hide()
	columns.TopTileStreaks:Hide()
	columns:SetHeight(24)
	columns:SetPoint("TOPLEFT", 2, -2)
	columns:SetPoint("TOPRIGHT", -2, -2)
	columns.sortingFunction = function(_, index) tbl:SortBy(index) end
	tbl.Columns = columns

	local bottom = spec.footer and 36 or 4
	local scrollBox = CreateFrame("Frame", nil, tbl, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", columns, "BOTTOMLEFT", 0, -2)
	scrollBox:SetPoint("BOTTOMRIGHT", -UI.SCROLLBAR_SPACE, bottom)
	local scrollBar = CreateFrame("EventFrame", nil, tbl, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, -2)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 2)

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(spec.rowHeight or UI.ROW_HEIGHT)
	view:SetElementInitializer("HeadWowTableRowTemplate", function(row, element)
		row:Init(tbl, element.item, element.index)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	tbl.ScrollBox = scrollBox

	tbl.Footer = tbl:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	tbl.Footer:SetPoint("BOTTOMLEFT", 8, 6)
	tbl.Footer:SetPoint("BOTTOMRIGHT", -8, 6)
	tbl.Footer:SetJustifyH("LEFT")
	tbl.Footer:SetSpacing(2)

	tbl.Empty = tbl:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	tbl.Empty:SetPoint("CENTER", scrollBox, "CENTER")
	tbl.Empty:SetWidth(360)
	tbl.Empty:SetSpacing(3)
	tbl.Empty:Hide()

	tbl:SetScript("OnSizeChanged", function() tbl:Layout() end)
	tbl:Layout()
	return tbl
end

function TableMixin:SortBy(index)
	local column = self.spec.columns[index]
	if not (column and column.sort) then return end
	if self.sortColumn == index then
		self.sortDescending = not self.sortDescending
	else
		self.sortColumn = index
		self.sortDescending = column.descending and true or false
	end
	self:Layout()
end

-- Works out the column widths from the table's width, lays out the headers, redraws.
function TableMixin:Layout()
	local columns = self.spec.columns
	local fixed, flex = 0, 0
	for _, column in ipairs(columns) do
		if column.width then fixed = fixed + column.width else flex = flex + (column.flex or 1) end
	end
	local total = (self:GetWidth() or 0) - UI.SCROLLBAR_SPACE - 6
	local rest = math.max(flex * 90, total - fixed)
	local info = {}
	for i, column in ipairs(columns) do
		local width = column.width or math.floor(rest * (column.flex or 1) / math.max(flex, 1))
		self.widths[i] = width
		local title = column.title or ""
		if i == self.sortColumn and column.sort then title = HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(title) end
		info[i] = { title = title, width = width }
	end
	self.Columns:LayoutColumns(info)
	self:Refresh()
end

function TableMixin:SetData(items, emptyText)
	self.items = items or {}
	if emptyText then self.Empty:SetText(emptyText) end
	self.Empty:SetShown(#self.items == 0)
	self:Refresh()
end

function TableMixin:SetFooter(text)
	self.Footer:SetText(text or "")
end

-- Sorts and redraws, keeping the scroll position.
function TableMixin:Refresh()
	local items = self.items
	local column = self.spec.columns[self.sortColumn]
	if column and column.sort then
		local compare, descending = column.sort, self.sortDescending
		table.sort(items, function(a, b)
			if descending then return compare(b, a) end
			return compare(a, b)
		end)
	end
	local elements = {}
	for i = 1, math.min(#items, self.spec.maxRows or #items) do
		elements[i] = { item = items[i], index = i }
	end
	self.ScrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants.RetainScrollPosition)
end

-- Redraws the visible rows (data changed in place, e.g. a portrait or a star).
function TableMixin:RedrawRows()
	self.ScrollBox:ForEachFrame(function(row) if row.item then row:Init(self, row.item, row.index) end end)
end

HeadWowTableRowMixin = {}

function HeadWowTableRowMixin:OnLoad()
	self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	self.Cells = {}
end

function HeadWowTableRowMixin:Init(tbl, item, index)
	self.tbl, self.item, self.index = tbl, item, index
	self.Stripe:SetShown(index % 2 == 0)
	self.Icon:Hide()
	local tint = tbl.spec.tint and tbl.spec.tint(item)
	if tint then
		if not self.Tint then
			self.Tint = self:CreateTexture(nil, "BACKGROUND", nil, 1)
			self.Tint:SetAllPoints()
		end
		self.Tint:SetColorTexture(tint.r, tint.g, tint.b, tint.a or 0.15)
		self.Tint:Show()
	elseif self.Tint then
		self.Tint:Hide()
	end

	local x = 4
	for i, column in ipairs(tbl.spec.columns) do
		local cell = self.Cells[i]
		if not cell then
			cell = self:CreateFontString(nil, "ARTWORK", column.font or "GameFontHighlightSmall")
			cell:SetWordWrap(false)
			self.Cells[i] = cell
		end
		local width = tbl.widths[i] or column.width or 100
		local textX = x
		if column.icon then
			local kind, id = column.icon(item)
			local icon = self.Icon
			icon:ClearAllPoints()
			icon:SetPoint("LEFT", x, 0)
			if kind == "npc" then
				HW:SetNpcPortrait(icon, id)
			else
				HW:ForgetNpcPortrait(icon)
				icon:SetTexture(kind == "item" and HW:GetItemIcon(id) or id)
				icon:SetVertexColor(1, 1, 1)
			end
			icon:Show()
			textX = x + 25
		end
		cell:ClearAllPoints()
		cell:SetPoint("LEFT", textX, 0)
		cell:SetWidth(math.max(10, width - (textX - x) - 8))
		cell:SetJustifyH(column.align or "LEFT")
		cell:SetText(column.text(item) or "")
		x = x + width - 2 -- header buttons overlap by 2px
	end
end

function HeadWowTableRowMixin:OnClick(button)
	local onClick = self.tbl and self.tbl.spec.onClick
	if onClick then onClick(self.item, button, self) end
end

function HeadWowTableRowMixin:OnEnter()
	local onEnter = self.tbl and self.tbl.spec.onEnter
	if onEnter then onEnter(self.item, self) end
end

function HeadWowTableRowMixin:OnLeave()
	GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Common column pieces
---------------------------------------------------------------------------

function UI.ChanceText(chance)
	return HW:GetChanceColor(chance):WrapTextInColorCode(HW:FormatChance(chance))
end

function UI.ByNumber(key)
	return function(a, b) return (a[key] or -1) < (b[key] or -1) end
end

function UI.ByText(key)
	return function(a, b) return (a[key] or "") < (b[key] or "") end
end

---------------------------------------------------------------------------
-- Context menus
---------------------------------------------------------------------------

function HW:ShowItemContextMenu(owner, itemID)
	local row = self:GetItem(itemID)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(self:GetColoredItemName(itemID))
		root:CreateButton("Open", function() self:ShowItem(itemID) end)
		root:CreateButton(self:IsWished(itemID) and "Remove from wishlist" or "Add to wishlist",
			function() self:ToggleWished(itemID) end)
		local map = root:CreateButton("Show where it drops on the map", function() self.Map:ShowItem(itemID) end)
		map:SetEnabled(row ~= nil and row[self.F.DROPS] ~= nil)
		root:CreateDivider()
		root:CreateButton("Link in chat", function() self:InsertItemLink(itemID) end)
		root:CreateButton("Preview (dressing room)", function() self:WithItemLink(itemID, DressUpItemLink) end)
		root:CreateButton("Copy Wowhead link", function() self:ShowURL(self:GetWowheadURL("item", itemID)) end)
	end)
end

function HW:ShowNpcContextMenu(owner, npcID, itemID, focusMapID)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(self:GetNpcName(npcID))
		root:CreateButton("Open NPC page", function() self:ShowNpc(npcID, itemID) end)
		root:CreateButton("Show its spawns on the map", function() self.Map:ShowNpc(npcID, focusMapID) end)
		if itemID then
			root:CreateButton("Show where this item drops", function() self.Map:ShowItem(itemID, nil, focusMapID) end)
		end
		root:CreateDivider()
		root:CreateButton("Copy Wowhead link", function() self:ShowURL(self:GetWowheadURL("npc", npcID)) end)
	end)
end
