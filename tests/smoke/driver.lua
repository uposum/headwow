-- Drives HeadWow's UI in the mock client: open every view, click and hover every row,
-- card, tab and menu entry, and report every Lua error with where it happened.

local failures, passed = {}, 0

local function step(name, fn, ...)
	local ok, err = xpcall(fn, debug.traceback, ...)
	if SMOKE_TRACE and name:find(SMOKE_TRACE) then REAL_PRINT("STEP " .. name) end
	if ok then
		passed = passed + 1
	else
		local lines = {}
		for line in tostring(err):gmatch("[^\n]+") do
			if not (line:find("driver.lua") or line:find("wow.lua") or line:find("%[JS%]") or line:find("tail calls")
				or line:find("stack traceback")) then
				lines[#lines + 1] = line
			end
			if #lines >= 5 then break end
		end
		failures[#failures + 1] = name .. "\n    " .. table.concat(lines, "\n    ")
	end
	MOCK.FlushTimers()
end

local HW = HeadWow

local function Rows()
	local rows = {}
	for box in pairs(MOCK.scrollBoxes) do
		for _, frame in ipairs(box.__visible or {}) do rows[#rows + 1] = frame end
	end
	return rows
end

-- Hover and click everything in the visible scroll boxes and cards.
local function Poke(label)
	for i, row in ipairs(Rows()) do
		if row:IsVisible() then
			step(label .. ": hover row " .. i, function() MOCK.Fire(row, "OnEnter"); MOCK.Fire(row, "OnLeave") end)
		end
	end
	for _, w in ipairs(MOCK.widgets) do
		if w.__kind == "Button" and w:IsVisible() and w.data then -- card link rows
			step(label .. ": hover card row " .. tostring(w.Text and w.Text.__text), function() MOCK.Fire(w, "OnEnter") end)
		end
	end
end

local function ClickRows(label, button, limit)
	local n = 0
	for _, row in ipairs(Rows()) do
		if row:IsVisible() and row.__scripts.OnClick then
			n = n + 1
			if n > (limit or 3) then break end
			step(label .. ": " .. button .. " row " .. n, function() MOCK.Fire(row, "OnClick", button) end)
		end
	end
end

local function ClickCards(label)
	local list = {}
	for _, w in ipairs(MOCK.widgets) do
		if w.__kind == "Button" and w:IsVisible() and w.data and w.data.onClick then list[#list + 1] = w end
	end
	for _, w in ipairs(list) do
		step(label .. ": click card row " .. tostring(w.Text and w.Text.__text), function() MOCK.Fire(w, "OnClick", "LeftButton") end)
	end
end

local function AllTabs(label)
	for system in pairs(MOCK.tabSystems) do
		if system:IsVisible() and system.__tabs then
			for id in ipairs(system.__tabs) do
				step(label .. ": tab " .. tostring(system.__tabs[id].tabText), function() system:SetTab(id, true) end)
				Poke(label .. " tab " .. id)
			end
		end
	end
end

-- Load and log in
step("ADDON_LOADED", function() MOCK.FireEvent("ADDON_LOADED", "HeadWow") end)
step("PLAYER_LOGIN", function() MOCK.FireEvent("PLAYER_LOGIN") end)

-- Open the window
step("/hw", function() SlashCmdList.HEADWOW("") end)
step("window shown", function() assert(HeadWowFrame and HeadWowFrame:IsShown(), "HeadWowFrame not shown") end)
Poke("home")
ClickCards("home")

-- Browse: search, lists, rows
step("open browse", function() HW:Open("") end)
step("search chest", function() HW:Open("chest") end)
Poke("search chest")
ClickRows("items", "LeftButton", 2)
Poke("item page")
AllTabs("item page")
ClickRows("item page", "RightButton", 3)
ClickCards("item page")

step("search wolf (NPCs)", function() HW:Open("wolf") end)
Poke("npc results")
ClickRows("npc results", "LeftButton", 1)
Poke("npc page")
ClickRows("npc page", "LeftButton", 2)
step("npc page from item", function() HW:ShowNpc(1, 100) end)
Poke("npc page from item")
ClickCards("npc page")

-- Enter in the search box, filter menu
step("search hogger + enter", function()
	HW:Open("plate")
	for _, w in ipairs(MOCK.widgets) do
		if w.__kind == "EditBox" and w.__scripts.OnEnterPressed then MOCK.Fire(w, "OnEnterPressed") end
	end
end)

-- Uncached item (no tooltip yet)
step("uncached item", function() HW:ShowItem(101) end)
step("item without drops", function() HW:ShowItem(104) end)

-- Wishlist
step("star item", function() HW:ToggleWished(100) end)
step("star item 2", function() HW:ToggleWished(103) end)
step("wishlist view", function() HW:ShowWishlist() end)
Poke("wishlist")
ClickRows("wishlist", "RightButton", 2)
ClickRows("wishlist", "LeftButton", 1)

-- Gold farming
step("gold view", function() HW:ShowGoldFarm() end)
Poke("gold")
ClickRows("gold", "RightButton", 2)
ClickRows("gold", "LeftButton", 1)
step("gold, no level filter", function() HW.db.farmBelow = 0; HW:ShowGoldFarm() end)
Poke("gold any level")
step("gold, with skinning", function() HW.db.farmSkinning = true; HW:ShowGoldFarm() end)
Poke("gold with skinning")

-- Every other way to get an item (vendor, skinning, mining, quest, ...)
step("item with every source", function() HW:ShowItem(100) end)
Poke("item 100 sources")
step("item with vendor, quest, recipe", function() HW:ShowItem(104) end)
Poke("item 104 sources")
step("snapshot spawns on the NPC page", function() HW:ShowNpc(2) end)
Poke("npc 2")

-- History
for i = 1, 6 do step("back " .. i, function() HW:NavigateHistory(-1) end) end
for i = 1, 6 do step("forward " .. i, function() HW:NavigateHistory(1) end) end

-- Bottom tabs
step("bottom tabs", function()
	for i, tab in ipairs(HeadWowFrame.Tabs) do MOCK.Fire(tab, "OnClick", "LeftButton") end
end)

-- Every button with an OnClick inside the window that isn't a row (actions, stars, nav)
step("window buttons", function()
	for _, w in ipairs(MOCK.widgets) do
		if w.__kind == "Button" and w:IsVisible() and w.__scripts.OnClick and not w.data and not w.tbl and not w.kind then
			MOCK.Fire(w, "OnClick", "LeftButton")
		end
	end
end)

-- Minimap button
step("minimap button", function()
	local b = HeadWowMinimapButton
	assert(b, "no minimap button")
	MOCK.Fire(b, "OnEnter")
	MOCK.Fire(b, "OnClick", "RightButton")
	MOCK.Fire(b, "OnDragStart")
	local update = b.__scripts.OnUpdate
	assert(update, "drag sets OnUpdate")
	update(b, 0.1)
	MOCK.Fire(b, "OnDragStop")
	MOCK.Fire(b, "OnClick", "LeftButton")
end)
step("/hw minimap off/on", function() SlashCmdList.HEADWOW("minimap"); SlashCmdList.HEADWOW("minimap") end)

-- Slash commands
for _, cmd in ipairs({ "gold", "wish", "wish plate", "config", "map plate chest", "map", "help", "plate", "item:100" }) do
	step("/hw " .. cmd, function() SlashCmdList.HEADWOW(cmd) end)
end

-- Map pins, banner, spawn pins
step("map: show item", function() HW.Map:ShowItem(100) end)
step("map: show npc", function() HW.Map:ShowNpc(1) end)
step("map: wish pins", function() HW.Map:SetWishPinsShown(true) end)
step("map: pins hover", function()
	for _, pin in ipairs(MOCK.lastPins or {}) do
		if pin.OnMouseEnter then pin:OnMouseEnter(); pin:OnMouseLeave() end
	end
end)

-- Tooltips in the world
step("mob tooltip", function()
	local fn = TooltipDataProcessor.callbacks[Enum.TooltipDataType.Unit]
	GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
	fn(GameTooltip, { guid = "Creature-0-1-0-1-1-0000000001" })
end)
step("item tooltip", function()
	local fn = TooltipDataProcessor.callbacks[Enum.TooltipDataType.Item]
	GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
	fn(GameTooltip, { id = 100 })
end)

-- Loot alert
step("loot alert", function() MOCK.FireEvent("CHAT_MSG_LOOT", "You receive loot: |cff1eff00|Hitem:100::|h[Plate Chest]|h|r.") end)

-- Every recorded menu action / setting / checkbox (context menus, filter, dropdowns)
local actions = MOCK.menuActions
MOCK.menuActions = {}
for i, action in ipairs(actions) do
	step("menu action " .. i .. " " .. action.text, function() action.fn() end)
end

-- Resize grip, mouse buttons, hide
step("mouse button 4/5", function()
	MOCK.Fire(HeadWowFrame, "OnMouseUp", "Button4")
	MOCK.Fire(HeadWowFrame, "OnMouseUp", "Button5")
end)
step("drag window", function() MOCK.Fire(HeadWowFrame, "OnDragStop") end)
step("reset window", function() HW:ResetWindow() end)
step("toggle closed", function() HW:Toggle(); assert(not HeadWowFrame:IsShown(), "still shown") end)
step("toggle open", function() HW:Toggle() end)

for _, f in ipairs(failures) do REAL_PRINT("FAIL " .. f) end
REAL_PRINT(("smoke: %d steps passed, %d failed"):format(passed, #failures))
if #failures > 0 then error(#failures .. " smoke steps failed", 0) end
