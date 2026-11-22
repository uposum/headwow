-- A stand-in for the WoW client's UI API, enough to build and drive HeadWow's UI outside
-- the game. Frames are plain tables; unknown methods are no-ops returning nil, unknown
-- fields are child frames created on first use (so template children like frame.Inset
-- exist). Template scripts run (OnLoad), ScrollBoxes run their row initializers, menus run
-- their generators, and every menu action is recorded so the driver can run it.

MOCK = { widgets = {}, eventFrames = {}, timers = {}, menuActions = {}, tabSystems = {}, scrollBoxes = {}, log = {} }

local unpack = table.unpack or unpack
local Widget = {}
local WidgetMT = {}

local function IsWidget(t) return type(t) == "table" and rawget(t, "__widget") == true end

local function NewWidget(kind, name, parent)
	local w = setmetatable({
		__widget = true, __kind = kind, __shown = true, __scripts = {}, __hooks = {},
		__parent = parent, __w = 0, __h = 0, __text = "", __children = {}, __lines = 0,
		__name = name, __checked = false, __enabled = true, __points = 0,
	}, WidgetMT)
	if IsWidget(parent) then table.insert(parent.__children, w) end
	if name then _G[name] = w end
	MOCK.widgets[#MOCK.widgets + 1] = w
	return w
end
MOCK.NewWidget = NewWidget

-- Unknown keys: a child widget that can also be called as a method (returns nil).
local CallableMT = {}
WidgetMT.__index = function(t, k)
	local m = Widget[k]
	if m ~= nil then return m end
	if type(k) ~= "string" or k:sub(1, 2) == "__" then return nil end
	-- lowercase keys are plain fields nobody set
	if not k:match("^[A-Z]") then return nil end
	local child = NewWidget("Auto", nil, t)
	rawset(t, k, child)
	return child
end
WidgetMT.__call = function() return nil end

local function Fire(w, script, ...)
	local fn = w.__scripts[script]
	if fn then fn(w, ...) end
	for _, hook in ipairs(w.__hooks[script] or {}) do hook(w, ...) end
end
MOCK.Fire = Fire

local function Visible(w)
	while IsWidget(w) do
		if not w.__shown then return false end
		w = w.__parent
	end
	return true
end

-- Geometry: rough, but numbers where code does math.
function Widget:SetPoint() self.__points = self.__points + 1 end
function Widget:ClearAllPoints() self.__points = 0 end
function Widget:SetAllPoints() self.__points = 1 end
function Widget:GetPoint() return "CENTER", UIParent, "CENTER", 0, 0 end
function Widget:GetNumPoints() return self.__points end
function Widget:SetSize(w, h) self.__w, self.__h = w or self.__w, h or self.__h end
function Widget:SetWidth(w) assert(type(w) == "number", "SetWidth: number expected, got " .. type(w)); self.__w = w end
function Widget:SetHeight(h) assert(type(h) == "number", "SetHeight: number expected, got " .. type(h)); self.__h = h end
function Widget:GetWidth() return self.__w > 0 and self.__w or 500 end
function Widget:GetHeight() return self.__h > 0 and self.__h or 300 end
function Widget:GetSize() return self:GetWidth(), self:GetHeight() end
function Widget:GetLeft() return 300 end
function Widget:GetRight() return 800 end
function Widget:GetTop() return 700 end
function Widget:GetBottom() return 200 end
function Widget:GetCenter() return 550, 450 end
function Widget:GetEffectiveScale() return 1 end
function Widget:GetScale() return 1 end
function Widget:GetFrameLevel() return self.__level or 1 end
function Widget:SetFrameLevel(l) assert(type(l) == "number"); self.__level = l end
function Widget:GetFrameStrata() return "MEDIUM" end

-- Visibility
function Widget:Show()
	local was = self.__shown
	self.__shown = true
	if not was and Visible(self) then Fire(self, "OnShow") end
end
function Widget:Hide()
	local was = self.__shown
	self.__shown = false
	if was then Fire(self, "OnHide") end
end
function Widget:SetShown(s) if s then self:Show() else self:Hide() end end
function Widget:IsShown() return self.__shown end
function Widget:IsVisible() return Visible(self) end

-- Scripts and events
function Widget:SetScript(name, fn) self.__scripts[name] = fn end
function Widget:GetScript(name) return self.__scripts[name] end
function Widget:HookScript(name, fn)
	self.__hooks[name] = self.__hooks[name] or {}
	table.insert(self.__hooks[name], fn)
end
function Widget:HasScript() return true end
function Widget:RegisterEvent(event)
	self.__events = self.__events or {}
	self.__events[event] = true
	MOCK.eventFrames[self] = true
end
function Widget:UnregisterEvent() end
function Widget:RegisterForClicks() end
function Widget:RegisterForDrag() end

-- Text
function Widget:SetText(text)
	text = text == nil and "" or text
	assert(type(text) == "string" or type(text) == "number", "SetText: string expected, got " .. type(text))
	local old = self.__text
	self.__text = tostring(text)
	if self.__kind == "EditBox" and old ~= self.__text then Fire(self, "OnTextChanged", false) end
end
function Widget:GetText() return self.__text end
function Widget:SetFormattedText(fmt, ...) self:SetText(string.format(fmt, ...)) end
function Widget:GetStringWidth() return #self.__text * 6 end
function Widget:GetTextWidth() return #self.__text * 6 end
function Widget:SetTextColor(r, g, b)
	assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "SetTextColor: numbers expected")
end
function Widget:SetFontObject(font) assert(font ~= nil, "SetFontObject: nil font") end
function Widget:IsTruncated() return false end

-- Textures
function Widget:SetTexture(tex) self.__texture = tex end
function Widget:SetAtlas(atlas) assert(type(atlas) == "string", "SetAtlas: string expected"); self.__atlas = atlas end
function Widget:SetVertexColor(r, g, b) assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "SetVertexColor: numbers expected") end
function Widget:SetColorTexture(r, g, b) assert(type(r) == "number", "SetColorTexture: numbers expected") end
function Widget:SetTexCoord() end

-- Creation of regions
function Widget:CreateTexture(name) return NewWidget("Texture", name, self) end
function Widget:CreateFontString(name, layer, font) return NewWidget("FontString", name, self) end
function Widget:CreateMaskTexture(name) return NewWidget("Texture", name, self) end
function Widget:CreateAnimationGroup() return NewWidget("AnimationGroup", nil, self) end

-- Hierarchy
function Widget:GetParent() return self.__parent end
function Widget:SetParent(p) self.__parent = p end
function Widget:GetName() return self.__name end
function Widget:SetID(id) self.__id = id end
function Widget:GetID() return self.__id or 0 end
function Widget:GetChildren() return unpack(self.__children) end

-- Buttons, check buttons
function Widget:SetChecked(v) self.__checked = v and true or false end
function Widget:GetChecked() return self.__checked end
function Widget:SetEnabled(v) self.__enabled = v and true or false end
function Widget:Enable() self.__enabled = true end
function Widget:Disable() self.__enabled = false end
function Widget:IsEnabled() return self.__enabled end
function Widget:GetButtonState() return "NORMAL" end
function Widget:IsMouseOver() return false end
function Widget:GetItemLink() return nil end
function Widget:GetFontString() return self.Text end

-- Tooltips
function Widget:SetOwner(owner, anchor) self.__lines = 0; self.__owner = owner; self.__shown = true end
function Widget:GetOwner() return self.__owner end
function Widget:AddLine(text) self.__lines = self.__lines + 1 end
function Widget:AddDoubleLine() self.__lines = self.__lines + 1 end
function Widget:ClearLines() self.__lines = 0 end
function Widget:NumLines() return self.__lines end
function Widget:SetItemByID(id) assert(type(id) == "number", "SetItemByID: number expected, got " .. type(id)); self.__lines = self.__lines + 3 end
function Widget:SetHyperlink() self.__lines = self.__lines + 2 end
function Widget:GetUnit() return "Mob", "mouseover" end

-- Models
function Widget:GetDisplayInfo() return 0 end

-- ScrollBox
function Widget:SetDataProvider(dp)
	assert(type(dp) == "table" and dp.__list, "SetDataProvider: data provider expected")
	local view = self.__view
	assert(view, "ScrollBox has no view (ScrollUtil.InitScrollBoxListWithScrollBar not called)")
	self.__frames = self.__frames or {}
	self.__visible = {}
	for i, element in ipairs(dp.__list) do
		if i > 30 then break end
		local template, init = view.__template, view.__init
		if view.__factory then
			view.__factory(function(t, fn) template, init = t, fn end, element)
		end
		assert(template, "no row template")
		local key = template .. "#" .. i
		local frame = self.__frames[key]
		if not frame then
			frame = CreateFrame("Button", nil, self, template)
			self.__frames[key] = frame
		end
		if init then init(frame, element) end
		self.__visible[#self.__visible + 1] = frame
	end
	self.__dp = dp
	MOCK.scrollBoxes[self] = true
end
function Widget:ForEachFrame(fn) for _, f in ipairs(self.__visible or {}) do fn(f) end end
function Widget:FindElementDataIndexByPredicate(fn)
	for i, e in ipairs(self.__dp and self.__dp.__list or {}) do if fn(e) then return i end end
end

-- TabSystem (also harmless on other widgets)
function Widget:AddTab(text)
	self.__tabs = self.__tabs or {}
	local id = #self.__tabs + 1
	local button = NewWidget("Button", nil, self)
	button.tabText = text
	button.Text = NewWidget("FontString", nil, button)
	button.Text:SetText(text)
	button.UpdateTabText = function(b) b.Text:SetText(b.tabText) end
	button.UpdateTabWidth = function() end
	self.__tabs[id] = button
	MOCK.tabSystems[self] = true
	return id
end
function Widget:SetTabSelectedCallback(fn) self.__tabCallback = fn end
function Widget:SetTab(id, user)
	assert(self.__tabs and self.__tabs[id], "SetTab: no tab " .. tostring(id))
	self.__selectedTab = id
	if self.__tabCallback then self.__tabCallback(id, user) end
end
function Widget:SetTabEnabled(id, enabled) assert(self.__tabs[id], "SetTabEnabled: no tab " .. tostring(id)) end
function Widget:GetTabButton(id) return self.__tabs and self.__tabs[id] end

-- Dropdowns run their menu generator right away.
local MenuDescription = {}
local MenuMT = { __index = function(t, k)
	if MenuDescription[k] then return MenuDescription[k] end
	return function() end
end }
local function NewMenu() return setmetatable({}, MenuMT) end
function MenuDescription:CreateButton(text, fn)
	assert(type(text) == "string", "menu button text must be a string")
	if fn then MOCK.menuActions[#MOCK.menuActions + 1] = { text = text, fn = fn } end
	return NewMenu()
end
function MenuDescription:CreateCheckbox(text, isSelected, setSelected)
	assert(type(text) == "string" and type(isSelected) == "function" and type(setSelected) == "function", "bad checkbox")
	isSelected()
	MOCK.menuActions[#MOCK.menuActions + 1] = { text = "[x] " .. text, fn = setSelected }
	return NewMenu()
end
function MenuDescription:CreateRadio(text, isSelected, setSelected)
	assert(type(text) == "string" and type(isSelected) == "function" and type(setSelected) == "function", "bad radio")
	isSelected()
	MOCK.menuActions[#MOCK.menuActions + 1] = { text = "(o) " .. text, fn = setSelected }
	return NewMenu()
end
function MenuDescription:CreateTitle(text) assert(type(text) == "string", "menu title must be a string"); return NewMenu() end
function MenuDescription:CreateDivider() return NewMenu() end
function MenuDescription:SetTooltip(fn) assert(type(fn) == "function"); fn(GameTooltip, self) end
function Widget:SetupMenu(fn) self.__menu = fn; fn(self, NewMenu()) end
function Widget:GenerateMenu() if self.__menu then self.__menu(self, NewMenu()) end end
MenuUtil = { CreateContextMenu = function(owner, fn) fn(owner, NewMenu()) end }
MenuResponse = { Refresh = 1, Close = 2 }

---------------------------------------------------------------------------
-- CreateFrame and templates
---------------------------------------------------------------------------

local BLIZZARD = {}
BLIZZARD.PanelTabButtonTemplate = function(w, parent)
	parent.Tabs = rawget(parent, "Tabs") or {}
	table.insert(parent.Tabs, w)
end
BLIZZARD.TabSystemTemplate = function(w) MOCK.tabSystems[w] = true end

local function ApplyTemplate(w, name, parent)
	for one in name:gmatch("[^,%s]+") do
		local tpl = HW_TEMPLATES[one]
		if tpl then
			if tpl.inherits then ApplyTemplate(w, tpl.inherits, parent) end
			for _, child in ipairs(tpl.children) do
				local c = NewWidget(child.kind, nil, w)
				if child.hidden then c.__shown = false end
				rawset(w, child.parentKey, c)
			end
			for k, v in pairs(tpl.keyValues) do rawset(w, k, v) end
			if tpl.mixin then
				local mixin = _G[tpl.mixin]
				assert(type(mixin) == "table", "template " .. one .. ": mixin " .. tpl.mixin .. " is not defined")
				for k, v in pairs(mixin) do rawset(w, k, v) end
			end
			for script, method in pairs(tpl.scripts) do
				if method ~= "inline" and script ~= "OnLoad" then
					local fn = w[method]
					assert(type(fn) == "function", "template " .. one .. ": " .. script .. " method " .. method .. " missing")
					w:SetScript(script, function(self, ...) return self[method](self, ...) end)
				end
			end
			if tpl.scripts.OnLoad and tpl.scripts.OnLoad ~= "inline" then
				local fn = w[tpl.scripts.OnLoad]
				assert(type(fn) == "function", "template " .. one .. ": OnLoad missing")
				fn(w)
			end
		elseif BLIZZARD[one] then
			BLIZZARD[one](w, parent)
		end
	end
end

function CreateFrame(kind, name, parent, template)
	assert(type(kind) == "string", "CreateFrame: frame type expected")
	local w = NewWidget(kind, name, parent)
	if template then ApplyTemplate(w, template, parent) end
	return w
end

---------------------------------------------------------------------------
-- Blizzard Lua API
---------------------------------------------------------------------------

UIParent = NewWidget("Frame", "UIParent")
Minimap = NewWidget("Frame", "Minimap")
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
WorldMapFrame = NewWidget("Frame", "WorldMapFrame")
WorldMapFrame.__shown = false
function WorldMapFrame:AddDataProvider(p) p.map = WorldMapFrame; p.GetMap = function() return WorldMapFrame end; MOCK.provider = p end
function WorldMapFrame:GetMapID() return 1448 end
function WorldMapFrame:AcquirePin(template, info)
	local pin = CreateFrame("Frame", nil, WorldMapFrame, template)
	pin.SetPosition = function() end
	pin.UseFrameLevelType = function() end
	pin.SetScalingLimits = function() end
	if pin.OnLoad then pin:OnLoad() end
	if pin.OnAcquired then pin:OnAcquired(info) end
	MOCK.pins = (MOCK.pins or 0) + 1
	MOCK.lastPins = MOCK.lastPins or {}
	table.insert(MOCK.lastPins, pin)
	return pin
end
function WorldMapFrame:RemoveAllPinsByTemplate() end
function WorldMapFrame:SetMapID() end
RaidWarningFrame = NewWidget("Frame", "RaidWarningFrame")

function CreateFromMixins(...)
	local t = {}
	for _, m in ipairs({ ... }) do for k, v in pairs(m) do t[k] = v end end
	return t
end
function Mixin(t, ...) for _, m in ipairs({ ... }) do for k, v in pairs(m) do t[k] = v end end return t end
function CreateAndInitFromMixin(m, ...) local t = CreateFromMixins(m); if t.Init then t:Init(...) end return t end
MapCanvasDataProviderMixin = { GetMap = function(self) return self.map end }
MapCanvasPinMixin = { ApplyFrameLevel = function() end }

local function Color(r, g, b)
	return {
		r = r, g = g, b = b,
		GetRGB = function() return r, g, b end,
		WrapTextInColorCode = function(_, text) return "|cffxxxxxx" .. tostring(text) .. "|r" end,
	}
end
NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR, GRAY_FONT_COLOR = Color(1, .82, 0), Color(1, 1, 1), Color(.5, .5, .5)
GREEN_FONT_COLOR, YELLOW_FONT_COLOR, ORANGE_FONT_COLOR, DISABLED_FONT_COLOR = Color(0, 1, 0), Color(1, 1, 0), Color(1, .5, 0), Color(.5, .5, .5)
ITEM_QUALITY_COLORS = {}
for q = 0, 7 do ITEM_QUALITY_COLORS[q] = { r = 1, g = 1, b = 1, hex = "|cffffffff" }; _G["ITEM_QUALITY" .. q .. "_DESC"] = "Q" .. q end
BACK, LEVEL, QUALITY, SOURCES, CHECK_ALL, UNCHECK_ALL, CLOSE = "Back", "Level", "Quality", "Sources", "Check all", "Uncheck all", "Close"
LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %s.", "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %s.", "You receive item: %sx%d."
ChatTypeInfo = { RAID_WARNING = { r = 1, g = .3, b = 0 } }
SOUNDKIT = { IG_CHARACTER_INFO_OPEN = 1, IG_CHARACTER_INFO_CLOSE = 2, IG_CHARACTER_INFO_TAB = 3, RAID_WARNING = 8959 }
UISpecialFrames = {}
StaticPopupDialogs = {}
SlashCmdList = {}
tinsert = table.insert
unpack = unpack
strtrim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
strsplit = function(sep, s)
	local out = {}
	for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
	return unpack(out)
end
bit = {
	band = function(a, b) local r, p = 0, 1 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + p end a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2 end return r end,
	bxor = function(a, b) local r, p = 0, 1 while a > 0 or b > 0 do if (a % 2) ~= (b % 2) then r = r + p end a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2 end return r end,
}
time = os.time
GetTime = function() return MOCK.now or 1000 end
math.atan2 = math.atan2 or math.atan
BreakUpLargeNumbers = function(n) return tostring(n) end
GetMoneyString = function(c) assert(type(c) == "number", "GetMoneyString: number expected, got " .. type(c)); return tostring(c) .. "c" end
PlaySound = function(id) assert(id ~= nil, "PlaySound: nil sound") end
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end MOCK.log[#MOCK.log + 1] = table.concat(t, " ") end
geterrorhandler = function() return function(err) error(err, 0) end end
InCombatLockdown = function() return false end
IsModifiedClick = function() return false end
IsAltKeyDown, IsShiftKeyDown, IsControlKeyDown = function() return false end, function() return false end, function() return false end
GetCursorPosition = function() return 600, 500 end
UnitLevel = function() return MOCK.playerLevel or 60 end
UnitClass = function() return "Warrior", "WARRIOR" end
UnitGUID = function(u) return u == "player" and "Player-1-00000001" or "Creature-0-1-0-1-1-0000000001" end
UnitName = function() return "Tester" end
DressUpItemLink = function() end
ChatFrameUtil = { InsertLink = function() end }
StaticPopup_Show = function() end
RaidNotice_AddMessage = function() end
ButtonFrameTemplate_HideButtonBar = function() end
SetItemButtonTexture = function() end
GameTooltip_Hide = function() GameTooltip:Hide() end
GetAppropriateTooltip = function() return GameTooltip end
local function TipCheck(tooltip) assert(IsWidget(tooltip), "tooltip expected") end
GameTooltip_SetTitle = function(tip, text) TipCheck(tip); assert(type(text) == "string", "GameTooltip_SetTitle: string expected, got " .. type(text)); tip:AddLine(text) end
for _, fn in ipairs({ "AddNormalLine", "AddHighlightLine", "AddInstructionLine", "AddDisabledLine", "AddErrorLine" }) do
	_G["GameTooltip_" .. fn] = function(tip, text) TipCheck(tip); assert(type(text) == "string", "GameTooltip_" .. fn .. ": string expected, got " .. type(text)); tip:AddLine(text) end
end
GameTooltip_AddBlankLineToTooltip = function(tip) TipCheck(tip); tip:AddLine(" ") end
GameTooltip_AddColoredDoubleLine = function(tip, left, right, lc, rc)
	TipCheck(tip)
	assert(type(left) == "string" and type(right) == "string", "double line: strings expected, got " .. type(left) .. ", " .. type(right))
	assert(type(lc) == "table" and lc.GetRGB and type(rc) == "table" and rc.GetRGB, "double line: colors expected")
	tip:AddLine(left)
end
PanelTemplates_SetNumTabs = function(frame, n) frame.numTabs = n; assert(#frame.Tabs == n, "PanelTemplates_SetNumTabs: " .. #frame.Tabs .. " tabs, " .. n .. " expected") end
PanelTemplates_SetTab = function(frame, id) assert(frame.Tabs[id], "PanelTemplates_SetTab: no tab " .. tostring(id)); frame.selectedTab = id end
PanelTemplates_TabResize = function(tab) assert(IsWidget(tab), "tab expected") end
SetPortraitTextureFromCreatureDisplayID = function() end
issecretvalue = nil

C_Timer = {
	After = function(t, fn) assert(type(fn) == "function"); MOCK.timers[#MOCK.timers + 1] = fn end,
	NewTimer = function(t, fn) local timer = { Cancel = function(self) self.cancelled = true end }; MOCK.timers[#MOCK.timers + 1] = function() if not timer.cancelled then fn() end end; return timer end,
}
function MOCK.FlushTimers()
	for _ = 1, 5 do
		local list = MOCK.timers
		MOCK.timers = {}
		for _, fn in ipairs(list) do fn() end
	end
end
C_AddOns = { LoadAddOn = function() return true end }
C_Texture = { GetAtlasInfo = function(a) return a == "auctionhouse-icon-favorite" and {} or nil end }
C_TooltipInfo = { GetHyperlink = function() return nil end }
C_Item = {
	GetItemIconByID = function() return 134400 end,
	GetItemQualityByID = function() return 2 end,
	GetItemInfo = function() return nil end,
	RequestLoadItemDataByID = function() end,
	IsItemDataCachedByID = function(id) return id ~= 101 end,
	GetItemInfoInstant = function(id)
		local t = { [100] = { 4, 4, "INVTYPE_CHEST", "Plate" }, [102] = { 2, 15, "INVTYPE_WEAPON", "Daggers" } }
		local k = t[id]
		if not k then return id, "Misc", "Junk", "", 134400, 15, 0 end
		return id, "Armor", k[4], k[3], 134400, k[1], k[2]
	end,
}
Item = { CreateFromItemID = function(_, id)
	return { IsItemEmpty = function() return false end, ContinueOnItemLoad = function(_, fn) MOCK.timers[#MOCK.timers + 1] = fn end,
	         GetItemLink = function() return "|cff1eff00|Hitem:" .. id .. "|h[Item]|h|r" end }
end }
Enum = {
	TooltipDataType = { Item = 0, Unit = 2 },
	UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 },
}
local MAPS = {
	[1448] = { mapID = 1448, name = "Felwood", mapType = 3, parentMapID = 1414 },
	[1447] = { mapID = 1447, name = "Azshara", mapType = 3, parentMapID = 1414 },
	[1413] = { mapID = 1413, name = "The Barrens", mapType = 3, parentMapID = 1414 },
	[1414] = { mapID = 1414, name = "Kalimdor", mapType = 2, parentMapID = 947 },
	[1429] = { mapID = 1429, name = "Elwynn Forest", mapType = 3, parentMapID = 1415, continent = 0, offset = 0 },
	[1415] = { mapID = 1415, name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
}
MAPS[1448].continent, MAPS[1448].offset = 1, 0
MAPS[1447].continent, MAPS[1447].offset = 1, 5000
MAPS[1413].continent, MAPS[1413].offset = 1, 10000
CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
MOCK.playerPos = { 0.45, 0.5 }
UnitFactionGroup = function() local f = MOCK.faction or "Alliance"; return f, f end
C_Map = {
	GetMapInfo = function(id) return MAPS[id] end,
	GetAreaInfo = function(id) return ({ [361] = "Felwood", [16] = "Azshara", [17] = "The Barrens" })[id] end,
	GetMapRectOnMap = function(a, b) if a == b then return 0, 1, 0, 1 end if b == 1414 then return 0.4, 0.6, 0.3, 0.5 end end,
	GetBestMapForUnit = function() return 1448 end,
	GetPlayerMapPosition = function() return MOCK.playerPos and CreateVector2D(MOCK.playerPos[1], MOCK.playerPos[2]) end,
	GetWorldPosFromMapPos = function(mapID, pos)
		local info = MAPS[mapID]
		if not (info and info.continent) then return end
		local x, y = pos:GetXY()
		return info.continent, CreateVector2D(info.offset + x * 1000, y * 1000)
	end,
}
TooltipDataProcessor = { callbacks = {}, AddTooltipPostCall = function(kind, fn) TooltipDataProcessor.callbacks[kind] = fn end }
EventUtil = { ContinueOnAddOnLoaded = function(_, fn) fn() end }
hooksecurefunc = function(a, b, c)
	if type(a) == "table" then
		local old = a[b]
		a[b] = function(...) local r = { old(...) }; c(...); return unpack(r) end
	else
		local old = _G[a]
		_G[a] = function(...) local r = { old(...) }; b(...); return unpack(r) end
	end
end
HandleModifiedItemClick = function() end

CreateDataProvider = function(list) assert(type(list) == "table", "CreateDataProvider: table expected"); return { __list = list } end
CreateScrollBoxListLinearView = function()
	local view = {}
	function view:SetElementInitializer(template, fn) self.__template, self.__init = template, fn end
	function view:SetElementFactory(fn) self.__factory = fn end
	function view:SetElementExtent() end
	function view:SetElementExtentCalculator() end
	return view
end
ScrollUtil = { InitScrollBoxListWithScrollBar = function(box, bar, view) rawset(box, "__view", view) end }
ScrollBoxConstants = { RetainScrollPosition = true, AlignCenter = 1 }

-- Settings panel
local settingsLayout = { AddInitializer = function() end }
Settings = {
	VarType = { Boolean = "boolean", Number = "number", String = "string" },
	RegisterVerticalLayoutCategory = function(name) return { GetID = function() return 99 end, name = name }, settingsLayout end,
	RegisterProxySetting = function(cat, var, kind, name, default, get, set)
		assert(type(get) == "function" and type(set) == "function", "proxy setting needs get/set")
		get()
		MOCK.menuActions[#MOCK.menuActions + 1] = { text = "setting " .. name, fn = function() set(get()) end }
		return { var = var }
	end,
	CreateCheckbox = function() end,
	CreateSlider = function() end,
	CreateSliderOptions = function() return { SetLabelFormatter = function() end } end,
	RegisterAddOnCategory = function() end,
	OpenToCategory = function(id) assert(id == 99, "OpenToCategory: bad id") end,
}
CreateSettingsListSectionHeaderInitializer = function() return {} end
CreateSettingsButtonInitializer = function(name, text, fn)
	MOCK.menuActions[#MOCK.menuActions + 1] = { text = "settings button " .. text, fn = fn }
	return {}
end

function MOCK.FireEvent(event, ...)
	for frame in pairs(MOCK.eventFrames) do
		if frame.__events[event] then Fire(frame, "OnEvent", event, ...) end
	end
end
OpenWorldMap = function(mapID) WorldMapFrame:Show() end
function Widget:GetStringHeight() return 12 end
