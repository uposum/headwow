-- HeadWow core: namespace, data accessors, saved variables, slash commands.

local ADDON_NAME = ...

-- Filled by the generated data files (Data\Generated\*.lua and HeadWow_Drops).
HeadWowData = { items = {}, drops = {}, npcs = {}, zones = {}, slots = {} }

HeadWow = {}
local HW = HeadWow
local Data = HeadWowData

-- Item row layout produced by tools/convert.mjs
HW.F = { NAME = 1, QUALITY = 2, ILVL = 3, REQ = 4, SLOT = 5, SOURCE = 6, SELL = 7, ZONE = 8, FROM = 9, DROPS = 10 }
local F = HW.F

HW.SOURCES = {
	{ bit = 1, label = "Drop" },
	{ bit = 2, label = "Vendor" },
	{ bit = 4, label = "Quest" },
	{ bit = 8, label = "Crafted" },
}

HW.WOWHEAD_BASE = "https://www.wowhead.com/forever/"
HW.FALLBACK_ICON = 134400 -- INV_Misc_QuestionMark

local DEFAULTS = {
	tooltip = true,      -- add drop sources to item tooltips
	tooltipLines = 3,
	detailTab = "overview", -- item page tab you used last: "overview", "drops" or "farm"
	minimapButton = true,
	minimapAngle = 220,  -- degrees around the minimap
	mapPins = true,      -- show the tracked item's drop zones on the world map
	mapItemID = nil,     -- the item tracked on the map ("Show on map")
	mobTooltip = true,   -- notable drops in the tooltip of mobs in the world
	mobTooltipLines = 4,
	wishMap = false,     -- the mobs that drop wishlist items on the world map
	wishAlert = true,    -- announce a looted wishlist item
	wishSound = true,
	farmBelow = 10,      -- gold farming: mobs at least this many levels below you (0 = any)
	farmElites = false,  -- gold farming: include elites and rares
	farmPrice = "best",  -- gold farming: "best" of vendor and AH, "vendor", "ah"
	point = nil,         -- saved window position
	size = nil,          -- saved window size { width, height }
}

---------------------------------------------------------------------------
-- Item accessors
---------------------------------------------------------------------------

function HW:GetItem(itemID)
	return Data.items[itemID]
end

function HW:GetItemQuality(itemID)
	local row = Data.items[itemID]
	local q = row and row[F.QUALITY]
	if q == nil and C_Item and C_Item.GetItemQualityByID then
		q = C_Item.GetItemQualityByID(itemID)
	end
	return q
end

-- Returns r, g, b only (safe to pass straight into SetTextColor).
function HW:GetQualityColor(quality)
	local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if c then
		return c.r, c.g, c.b
	end
	return 1, 1, 1
end

function HW:GetQualityHex(quality)
	local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	return (c and c.hex) or "|cffffffff"
end

function HW:GetItemIcon(itemID)
	return (C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)) or HW.FALLBACK_ICON
end

function HW:GetColoredItemName(itemID)
	local row = Data.items[itemID]
	local name = row and row[F.NAME] or ("Item " .. itemID)
	return self:GetQualityHex(self:GetItemQuality(itemID)) .. name .. "|r"
end

function HW:GetZoneName(zoneIdx)
	return zoneIdx and Data.zones[zoneIdx]
end

function HW:GetSlotName(slotIdx)
	return slotIdx and Data.slots[slotIdx]
end

function HW:GetSourceText(mask)
	if not mask then return nil end
	local parts = {}
	for _, s in ipairs(HW.SOURCES) do
		if bit.band(mask, s.bit) ~= 0 then parts[#parts + 1] = s.label end
	end
	return #parts > 0 and table.concat(parts, ", ") or nil
end

function HW:GetWowheadURL(kind, id)
	return HW.WOWHEAD_BASE .. kind .. "=" .. id
end

-- Calls back with a real item link once the client has the item cached.
function HW:WithItemLink(itemID, callback)
	local item = Item:CreateFromItemID(itemID)
	if item:IsItemEmpty() then return end
	item:ContinueOnItemLoad(function()
		local link = item:GetItemLink()
		if link then callback(link) end
	end)
end

function HW:InsertItemLink(itemID)
	self:WithItemLink(itemID, function(link)
		ChatFrameUtil.InsertLink(link)
	end)
end

---------------------------------------------------------------------------
-- Drop data (HeadWow_Drops, load on demand)
---------------------------------------------------------------------------

function HW:EnsureDrops()
	if self.dropsLoaded then return true end
	local loaded, reason = C_AddOns.LoadAddOn("HeadWow_Drops")
	if not loaded then
		if not self.dropsWarned then
			self.dropsWarned = true
			self:Print("Could not load drop data (HeadWow_Drops): " .. tostring(reason))
		end
		return false
	end
	self.dropsLoaded = true
	return true
end

-- Returns a list of { npcID, name, chance (0-100 or nil), samples, zones = {zoneIdx...} } and the
-- number of additional sources Wowhead listed but the snapshot did not include.
function HW:GetDrops(itemID)
	if not self:EnsureDrops() then return {}, 0 end
	local raw = Data.drops[itemID]
	if not raw then return {}, 0 end
	local list = {}
	for i = 2, #raw, 3 do
		local npcID, bp, samples = raw[i], raw[i + 1], raw[i + 2]
		local npc = Data.npcs[npcID]
		local zones = {}
		if npc then
			for z = 2, #npc do zones[#zones + 1] = npc[z] end
		end
		list[#list + 1] = {
			npcID = npcID,
			name = npc and npc[1] or ("NPC " .. npcID),
			chance = bp >= 0 and bp / 100 or nil,
			samples = samples,
			zones = zones,
		}
	end
	return list, raw[1] or 0
end

---------------------------------------------------------------------------
-- Auction prices (from Auctionator when it's installed; HeadWow does no scanning)
---------------------------------------------------------------------------

local AUCTIONATOR_CALLER = "HeadWow"

local function AuctionatorAPI()
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if api and api.GetAuctionPriceByItemID then return api end
end

function HW:HasAuctionPrices()
	return AuctionatorAPI() ~= nil
end

-- Returns Auctionator's last seen price (copper) and its age in days (nil if older than
-- Auctionator tracks), or nil when Auctionator is missing or has never seen the item.
-- Uses the item link when the client has it, so item-level variants are priced right.
function HW:GetAuctionPrice(itemID)
	local api = AuctionatorAPI()
	if not api then return nil end
	local link = C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(itemID))
	local ok, price, age
	if link and api.GetAuctionPriceByItemLink then
		ok, price = pcall(api.GetAuctionPriceByItemLink, AUCTIONATOR_CALLER, link)
		if ok and price and api.GetAuctionAgeByItemLink then
			local okAge, a = pcall(api.GetAuctionAgeByItemLink, AUCTIONATOR_CALLER, link)
			age = okAge and a or nil
		end
	end
	if not (ok and price) then
		ok, price = pcall(api.GetAuctionPriceByItemID, AUCTIONATOR_CALLER, itemID)
		if ok and price and api.GetAuctionAgeByItemID then
			local okAge, a = pcall(api.GetAuctionAgeByItemID, AUCTIONATOR_CALLER, itemID)
			age = okAge and a or nil
		end
	end
	if ok and type(price) == "number" and price > 0 then return price, age end
end

-- The same by item ID only: never asks the game for item info, so it's fine for passes over
-- thousands of items.
function HW:GetAuctionPriceByID(itemID)
	local api = AuctionatorAPI()
	if not api then return nil end
	local ok, price = pcall(api.GetAuctionPriceByItemID, AUCTIONATOR_CALLER, itemID)
	if ok and type(price) == "number" and price > 0 then return price end
end

---------------------------------------------------------------------------
-- AH market check (Auctionator's price history)
--
-- A last-seen price says nothing about whether the item really sells: one listing at 10g
-- that never sold, or an item nobody has listed for a week, looks the same as a busy market.
-- Auctionator keeps, per item and day, the lowest and highest price seen and how many were
-- listed (its database, not its public API; read defensively). From that:
--   price     the median of the daily lowest prices, so a one-off listing doesn't set it
--   listed    on how many of your recent scan days it was up at all
--   recent    whether it was still up within a few days of your latest scan
-- Scan days aren't recorded either: a day counts as one when a good share of the database
-- was seen that day (a full scan), so a day you searched for a few items doesn't.
---------------------------------------------------------------------------

local MARKET_WINDOW = 14       -- days of history considered
local MARKET_MIN_SHARE = 0.5   -- listed on at least this share of scan days...
local MARKET_MIN_DAYS = 2      -- ...and on at least this many of them
local MARKET_MAX_AGE = 3       -- days between the last listing and your latest scan
local SCAN_DAY_SHARE = 0.25    -- a scan day saw at least this share of the busiest day's items
local SCAN_DAY_SAMPLE = 4000   -- database entries looked at to find the scan days
local SCAN_DAYS_TTL = 300      -- seconds before the scan days are worked out again

local scanDays -- { days = { [day] = true }, count, latest, at }

local function AuctionatorDB()
	local db = Auctionator and Auctionator.Database and Auctionator.Database.db
	local day0 = Auctionator and Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0
	if type(db) == "table" and type(day0) == "number" then return db, day0 end
end

local function Today(day0)
	return math.floor((time() - day0) / 86400)
end

local function ScanDays()
	if scanDays and GetTime() - scanDays.at < SCAN_DAYS_TTL then return scanDays end
	local db, day0 = AuctionatorDB()
	if not db then return nil end
	local from = Today(day0) - MARKET_WINDOW
	local perDay, looked = {}, 0
	for _, entry in pairs(db) do
		if type(entry) == "table" and type(entry.h) == "table" then
			for day in pairs(entry.h) do
				local d = tonumber(day)
				if d and d > from then perDay[d] = (perDay[d] or 0) + 1 end
			end
			looked = looked + 1
			if looked >= SCAN_DAY_SAMPLE then break end
		end
	end
	local busiest = 0
	for _, n in pairs(perDay) do busiest = math.max(busiest, n) end
	local days, count, latest = {}, 0, nil
	for d, n in pairs(perDay) do
		if n >= busiest * SCAN_DAY_SHARE then
			days[d] = true
			count = count + 1
			latest = math.max(latest or d, d)
		end
	end
	scanDays = { days = days, count = count, latest = latest, at = GetTime() }
	return scanDays
end

-- Returns nil without Auctionator data for the item, else a table:
--   price      median daily low over the window (copper), last = Auctionator's last price
--   listed     scan days it was listed on, scans = scan days in the window
--   age        days from its last listing to your latest scan
--   available  average quantity listed on the days it was up
--   reliable   whether the AH price should count; reason says why not
function HW:GetMarket(itemID)
	local db, day0 = AuctionatorDB()
	if not db then return nil end
	local ok, market = pcall(function()
		local entry = db[tostring(itemID)]
		if type(entry) ~= "table" or type(entry.h) ~= "table" then return nil end
		local scans = ScanDays()
		local from = Today(day0) - MARKET_WINDOW
		local lows, listed, availableSum, availableDays, lastDay = {}, 0, 0, 0, nil
		for day, high in pairs(entry.h) do
			local d = tonumber(day)
			if d and d > from then
				local low = (type(entry.l) == "table" and entry.l[day]) or high
				if type(low) == "number" and low > 0 then lows[#lows + 1] = low end
				if scans.days[d] then listed = listed + 1 end
				local available = type(entry.a) == "table" and entry.a[day]
				if type(available) == "number" then
					availableSum, availableDays = availableSum + available, availableDays + 1
				end
				lastDay = math.max(lastDay or d, d)
			end
		end
		if #lows == 0 then return nil end
		table.sort(lows)
		local mid = math.floor((#lows + 1) / 2)
		local price = #lows % 2 == 1 and lows[mid] or math.floor((lows[mid] + lows[mid + 1]) / 2)

		local m = {
			price = price, last = entry.m, listed = listed, scans = scans.count,
			age = (scans.latest or lastDay) - lastDay,
			available = availableDays > 0 and availableSum / availableDays or nil,
		}
		if m.scans < MARKET_MIN_DAYS then
			m.reason = string.format("only %d scan day%s recorded; scan the AH on more days", m.scans, m.scans == 1 and "" or "s")
		elseif m.age > MARKET_MAX_AGE then
			m.reason = string.format("not listed in your last %d days of scans", m.age)
		elseif listed < MARKET_MIN_DAYS or listed < m.scans * MARKET_MIN_SHARE then
			m.reason = string.format("listed on only %d of %d scan days", listed, m.scans)
		end
		m.reliable = m.reason == nil
		return m
	end)
	if ok then return market end
end

-- The AH price to count for an item (median daily low), or nil when there is none or its
-- market doesn't look real (see GetMarket). Falls back to Auctionator's API price when its
-- database can't be read.
function HW:GetMarketPrice(itemID)
	if AuctionatorDB() then
		local market = self:GetMarket(itemID)
		return market and market.reliable and market.price or nil, market
	end
	return self:GetAuctionPriceByID(itemID), nil
end

-- The AH price to show for an item: price, and whether it can be trusted (true), looks off
-- (false: a lone or stale listing; then price is its median anyway), or can't be judged (nil).
function HW:GetShownAuctionPrice(itemID)
	if AuctionatorDB() then
		local market = self:GetMarket(itemID)
		if market then return market.price, market.reliable, market end
		return nil
	end
	return self:GetAuctionPrice(itemID), nil
end

-- "listed on 9 of 12 scan days, ~14 up"
function HW:DescribeMarket(market)
	if not market then return "" end
	local text = string.format("listed on %d of %d scan days", market.listed, market.scans)
	if market.available then text = text .. string.format(", ~%d up", math.floor(market.available + 0.5)) end
	return text
end

-- Compact money: "12.3g", "45s", "7c" (colored like coins).
function HW:FormatMoneyShort(copper)
	copper = math.floor((copper or 0) + 0.5)
	if copper >= 10000 then
		local gold = copper / 10000
		return ("|cffffd700%s|r"):format(gold >= 100 and BreakUpLargeNumbers(math.floor(gold + 0.5)) .. "g" or ("%.1fg"):format(gold))
	elseif copper >= 100 then
		return ("|cffc7c7cf%ds|r"):format(math.floor(copper / 100 + 0.5))
	end
	return ("|cffeda55f%dc|r"):format(copper)
end

function HW:FormatChance(chance)
	if not chance then return "?" end
	if chance >= 10 then return string.format("%.0f%%", chance) end
	if chance >= 1 then return string.format("%.1f%%", chance) end
	return string.format("%.2f%%", chance)
end

-- Colors a drop chance from grey (rare) to green (common).
function HW:GetChanceColor(chance)
	if not chance then return GRAY_FONT_COLOR end
	if chance >= 25 then return GREEN_FONT_COLOR end
	if chance >= 5 then return YELLOW_FONT_COLOR end
	if chance >= 1 then return ORANGE_FONT_COLOR or NORMAL_FONT_COLOR end
	return GRAY_FONT_COLOR
end

---------------------------------------------------------------------------
-- Misc
---------------------------------------------------------------------------

function HW:Print(msg)
	print("|cff4fc3f7HeadWow|r: " .. msg)
end

function HW:GrayText(text)
	return "|cff808080" .. tostring(text) .. "|r"
end

StaticPopupDialogs["HEADWOW_COPY_URL"] = {
	text = "Press Ctrl+C to copy the Wowhead link:",
	button1 = CLOSE,
	hasEditBox = true,
	editBoxWidth = 320,
	OnShow = function(self, url)
		local editBox = self.GetEditBox and self:GetEditBox() or self.editBox
		editBox:SetText(url or "")
		editBox:HighlightText()
		editBox:SetFocus()
	end,
	EditBoxOnEnterPressed = function(editBox) editBox:GetParent():Hide() end,
	EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

function HW:ShowURL(url)
	StaticPopup_Show("HEADWOW_COPY_URL", nil, nil, url)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		HeadWowDB = HeadWowDB or {}
		for k, v in pairs(DEFAULTS) do
			if HeadWowDB[k] == nil then HeadWowDB[k] = v end
		end
		HeadWowDB.wishlist = HeadWowDB.wishlist or {} -- itemID -> true
		HW.db = HeadWowDB
	elseif event == "PLAYER_LOGIN" then
		if HW.OnLogin then HW:OnLogin() end
	end
end)

---------------------------------------------------------------------------
-- Slash commands, key binding, addon compartment
---------------------------------------------------------------------------

BINDING_HEADER_HEADWOW = "HeadWow"
BINDING_NAME_HEADWOW_TOGGLE = "Toggle HeadWow"

SLASH_HEADWOW1 = "/hw"
SLASH_HEADWOW2 = "/headwow"
SlashCmdList.HEADWOW = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S+)%s*(.-)$")
	cmd = cmd and cmd:lower()

	if cmd == "map" and rest ~= "" then
		local itemID = tonumber(rest:match("item:(%d+)") or rest) or HW:FindBestMatch(rest)
		if itemID then HW.Map:ShowItem(itemID) else HW:Print("No item found for '" .. rest .. "'.") end
	elseif cmd == "map" then
		HW.Map:SetPinsShown(not HW.db.mapPins)
		HW:Print("Map pins " .. (HW.db.mapPins and "shown." or "hidden."))
	elseif cmd == "tooltip" then
		HW.db.tooltip = not HW.db.tooltip
		HW:Print("Tooltip drop sources " .. (HW.db.tooltip and "enabled." or "disabled."))
	elseif cmd == "wish" and rest ~= "" then
		local itemID = tonumber(rest:match("item:(%d+)") or rest) or HW:FindBestMatch(rest)
		if itemID and HW:GetItem(itemID) then HW:ToggleWished(itemID) else HW:Print("No item found for '" .. rest .. "'.") end
	elseif cmd == "wish" then
		HW:ShowWishlist()
	elseif cmd == "gold" or cmd == "farm" then
		HW:ShowGoldFarm()
	elseif cmd == "minimap" then
		HW:SetMinimapButtonShown(not HW.db.minimapButton)
		HW:Print("Minimap button " .. (HW.db.minimapButton and "shown." or "hidden."))
	elseif cmd == "config" or cmd == "settings" or cmd == "options" then
		HW:OpenSettings()
	elseif cmd == "zones" then
		HW.Map:ReportUnresolvedZones()
	elseif cmd == "help" then
		HW:Print("/hw [search]  open the browser (optionally searching)")
		HW:Print("/hw map <item name, id or link>  show where an item drops on the world map")
		HW:Print("/hw map  show or hide the tracked item's map pins")
		HW:Print("/hw wish  show your wishlist;  /hw wish <item>  add or remove an item")
		HW:Print("/hw tooltip  toggle drop sources in item tooltips")
		HW:Print("/hw gold  mobs to farm for gold, ranked by what their drops sell for")
		HW:Print("/hw minimap  show or hide the minimap button")
		HW:Print("/hw config  open HeadWow's settings")
		HW:Print("Alt-click any item (bags, chat, loot...) to open it in HeadWow.")
	elseif msg ~= "" then
		local itemID = tonumber(msg:match("item:(%d+)") or "")
		if itemID then HW:ShowItem(itemID) else HW:Open(msg) end
	else
		HW:Toggle()
	end
end

function HeadWow_OnAddonCompartmentClick()
	HW:Toggle()
end

function HeadWow_OnAddonCompartmentEnter(_, button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip_SetTitle(GameTooltip, "HeadWow")
	GameTooltip_AddInstructionLine(GameTooltip, "Click to browse the Wowhead snapshot")
	if Data.snapshot then
		GameTooltip_AddNormalLine(GameTooltip, "Snapshot: " .. Data.snapshot:sub(1, 10))
	end
	GameTooltip:Show()
end

function HeadWow_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
