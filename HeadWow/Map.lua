-- World map integration: the tracked item's drop zones as pins, via a native MapCanvas data
-- provider. Works on Blizzard's world map and on OpenMap's stitched map (OpenMapAPI).
--
-- "Show on map" makes an item the tracked one (saved across sessions). Its pins show while
-- HeadWow.db.mapPins is on; with OpenMap that switch is a toggle in OpenMap's own menu.
--
-- With spawn points (the snapshot's, else QuestieDB's), the NPCs that drop the item are pinned on their spawn points
-- (rings colored by drop chance). NPCs without spawn data get one pin per zone instead, which
-- lists them. The same spawn pins show an NPC's page ("Show on map") and, optionally, every
-- mob that drops a wishlist item.

local HW = HeadWow
local Data = HeadWowData

local Map = {}
HW.Map = Map

local PIN_TEMPLATE = "HeadWowMapPinTemplate"
local SPAWN_PIN_TEMPLATE = "HeadWowSpawnPinTemplate"
local MAX_SPAWN_PINS = 400
local MAX_WISH_PINS = 300
local MAX_MAP_ID = 6000
local MAX_TOOLTIP_NPCS = 12
local OPENMAP_OWNER = "HeadWow"
local OPENMAP_TOGGLE = "drops"
local OPENMAP_WISH_TOGGLE = "wishlist"
local FIT_MARGIN = 1.35         -- view size over the zones' extent when gliding OpenMap to them
local MAX_FIT_ZOOM = 24         -- never zoom in further than this when fitting (OpenMap zoom, 1 = world)
local STITCHED_RANGE = 3        -- on the stitched map, pins this many host-map widths away still show

-- Map types that make sense as a pin target (continents/world are too coarse).
local PIN_TYPES = {}
local TYPE_PRIORITY = {}

local function InitMapTypes()
	local T = Enum.UIMapType
	PIN_TYPES = { [T.Zone] = true, [T.Dungeon] = true, [T.Micro] = true, [T.Orphan] = true }
	TYPE_PRIORITY = { [T.Zone] = 1, [T.Dungeon] = 2, [T.Micro] = 3, [T.Orphan] = 4, [T.Continent] = 5, [T.World] = 6, [T.Cosmic] = 7 }
end

---------------------------------------------------------------------------
-- OpenMap
---------------------------------------------------------------------------

local function OpenMap()
	local api = OpenMapAPI
	if type(api) == "table" and api.major == 1 then return api end
end

local function IsStitched()
	local api = OpenMap()
	return api and api.IsStitched() or false
end

-- A map's rectangle on OpenMap's stitched world (u0, v0, u1, v1), from the map itself or, for
-- maps that aren't part of the stitch (dungeons), its nearest ancestor that is.
local function WorldRect(mapID)
	local api = OpenMap()
	if not api then return end
	local m = mapID
	while m and m ~= 0 do
		local u0, v0 = api.WorldFromMap(m, 0, 0)
		local u1, v1 = api.WorldFromMap(m, 1, 1)
		if u0 and u1 and u1 > u0 and v1 > v0 then return u0, v0, u1, v1, m end
		local info = C_Map.GetMapInfo(m)
		m = info and info.parentMapID
	end
end

---------------------------------------------------------------------------
-- Zone name -> uiMapID (resolved in-game, no lookup table needed)
---------------------------------------------------------------------------

function Map:BuildLookup()
	if self.byName then return end
	InitMapTypes()
	self.byName = {}
	for mapID = 1, MAX_MAP_ID do
		local info = C_Map.GetMapInfo(mapID)
		if info and info.name and info.name ~= "" then
			local key = info.name:lower()
			local current = self.byName[key]
			local prio = TYPE_PRIORITY[info.mapType] or 9
			if not current or prio < current.prio then
				self.byName[key] = { mapID = mapID, prio = prio, mapType = info.mapType }
			end
		end
	end
	self.zoneCache = {}
end

-- Returns uiMapID, mapType for a zone name (or nil).
function Map:ResolveZoneName(name)
	self:BuildLookup()
	local found = name and self.byName[name:lower()]
	if found then return found.mapID, found.mapType end
end

-- Returns uiMapID, mapType for a snapshot zone index (or nil).
function Map:ResolveZone(zoneIdx)
	self:BuildLookup()
	local cached = self.zoneCache[zoneIdx]
	if cached == nil then
		-- the snapshot's own map ID for the zone first, else the zone's name
		local known = Data.zoneMaps[zoneIdx]
		local info = known and C_Map.GetMapInfo(known)
		if info then
			cached = { mapID = known, mapType = info.mapType }
		else
			local name = Data.zones[zoneIdx]
			cached = name and self.byName[name:lower()] or false
		end
		self.zoneCache[zoneIdx] = cached
	end
	if cached then return cached.mapID, cached.mapType end
end

function Map:ReportUnresolvedZones()
	local missing = {}
	for idx, name in ipairs(Data.zones) do
		if not self:ResolveZone(idx) then missing[#missing + 1] = name end
	end
	if #missing == 0 then
		HW:Print("All " .. #Data.zones .. " zones resolved to world map IDs.")
	else
		HW:Print(#missing .. " zones without a world map: " .. table.concat(missing, ", "))
	end
end

local function GetContinent(mapID)
	local info = C_Map.GetMapInfo(mapID)
	while info do
		if info.mapType == Enum.UIMapType.Continent then return info.mapID end
		if not info.parentMapID or info.parentMapID == 0 then break end
		info = C_Map.GetMapInfo(info.parentMapID)
	end
	return mapID
end

local function IsAncestor(ancestorID, mapID)
	local info = C_Map.GetMapInfo(mapID)
	while info and info.parentMapID and info.parentMapID ~= 0 do
		if info.parentMapID == ancestorID then return true end
		info = C_Map.GetMapInfo(info.parentMapID)
	end
	return false
end

-- Where a zone's pin goes on the displayed map (Blizzard's map): the center of the zone, or of
-- its nearest ancestor the displayed map contains (e.g. a dungeon's parent zone).
local function GetPinPosition(zoneMapID, displayedMapID)
	local m = zoneMapID
	while m and m ~= 0 do
		if m == displayedMapID then return 0.5, 0.5, m end
		local left, right, top, bottom = C_Map.GetMapRectOnMap(m, displayedMapID)
		if left and right and right > left and bottom > top then
			local x, y = (left + right) / 2, (top + bottom) / 2
			if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
				return x, y, m
			end
		end
		local info = C_Map.GetMapInfo(m)
		m = info and info.parentMapID
	end
end

-- The same on OpenMap's stitched map: through the stitched world, so zones next to the map
-- underneath (which the view shows too) get their pins, placed past its edges.
local function GetStitchedPinPosition(zoneMapID, hostMapID)
	local u0, v0, u1, v1, anchor = WorldRect(zoneMapID)
	if not u0 then return end
	local x, y = OpenMap().MapFromWorld(hostMapID, (u0 + u1) / 2, (v0 + v1) / 2)
	if x and y and x > -STITCHED_RANGE and x < 1 + STITCHED_RANGE and y > -STITCHED_RANGE and y < 1 + STITCHED_RANGE then
		return x, y, anchor
	end
end

---------------------------------------------------------------------------
-- Tracked item
---------------------------------------------------------------------------

-- An item's drop sources, for the map:
--  spawnSources: the NPCs with spawn points (snapshot or QuestieDB), pinned where they stand
--  zones:        by world map zone (snapshot zones), every NPC in `npcs`; the NPCs without
--                spawn points in `unpinned`, which get one pin for the zone
--  targets:      mapID -> best chance there, the places the view can be framed on
--  spots:        the best places to farm it (Farm)
function Map:Collect(itemID)
	local sources, spots = HW.Farm:Get(itemID)
	local zones, spawnSources, targets = {}, {}, {}
	local unmapped = 0
	for _, src in ipairs(sources) do
		-- NPCs that only stand in dungeons keep a zone pin too: their spawn pins show only on
		-- the dungeon's own map, the zone pin finds the entrance's zone.
		local hasPoints = false
		if src.spawnPoints > 0 then
			spawnSources[#spawnSources + 1] = src
			for mapID, z in pairs(src.spawnZones) do
				if #z.points > 0 then
					targets[mapID] = math.max(targets[mapID] or -1, src.chance or 0)
					local info = C_Map.GetMapInfo(mapID)
					if info and info.mapType == Enum.UIMapType.Zone then hasPoints = true end
				end
			end
		end
		local placed = src.spawnPoints > 0
		for _, zoneIdx in ipairs(src.zoneIdxs) do
			local mapID, mapType = self:ResolveZone(zoneIdx)
			if mapID and PIN_TYPES[mapType] then
				local z = zones[mapID]
				if not z then
					z = { mapID = mapID, zoneIdx = zoneIdx, npcs = {}, unpinned = {}, best = -1 }
					zones[mapID] = z
				end
				z.npcs[#z.npcs + 1] = src -- sources come best chance first
				if not hasPoints then
					z.unpinned[#z.unpinned + 1] = src
					targets[mapID] = math.max(targets[mapID] or -1, src.chance or 0)
				end
				z.best = math.max(z.best, src.chance or 0)
				placed = true
			end
		end
		if not placed then unmapped = unmapped + 1 end
	end
	return {
		zones = zones, spawnSources = spawnSources, targets = targets, spots = spots,
		total = #sources, unmapped = unmapped,
	}
end

local function Track(itemID)
	local active = Map:Collect(itemID)
	if not next(active.targets) then return nil end
	active.itemID = itemID
	Map.active = active
	return active
end

-- The tracked item, restored from the saved variables the first time it's needed (so the drop
-- data only loads once a map is actually shown).
function Map:GetActive()
	if not self.active and HW.db and HW.db.mapItemID and not self.restoreFailed then
		if not Track(HW.db.mapItemID) then
			self.restoreFailed = true
			HW.db.mapItemID = nil
		end
	end
	return self.active
end

function Map:IsShowingPins()
	return HW.db and HW.db.mapPins and self:GetActive() ~= nil or false
end

function Map:SetPinsShown(shown)
	HW.db.mapPins = shown and true or false
	self:Refresh()
end

-- Which zones to frame when showing an item: the focused one, else those on the player's
-- continent, else those on the continent of the best place to farm it (or best drop chance).
local function PickTargets(active, focusZoneIdx, focusMapID)
	local focus = focusMapID or (focusZoneIdx and Map:ResolveZone(focusZoneIdx))
	if focus and active.targets[focus] then
		return { focus }, focus
	end

	local playerMap = C_Map.GetBestMapForUnit("player")
	local continent = playerMap and GetContinent(playerMap)
	local bestMap, bestChance
	local onPlayerContinent = false
	for mapID, chance in pairs(active.targets) do
		if continent and GetContinent(mapID) == continent then onPlayerContinent = true end
		if not bestMap or chance > bestChance then bestMap, bestChance = mapID, chance end
	end
	local spot = active.spots[1]
	if spot and active.targets[spot.mapID] then bestMap = spot.mapID end
	if not onPlayerContinent then continent = GetContinent(bestMap) end

	local targets = {}
	for mapID in pairs(active.targets) do
		if GetContinent(mapID) == continent then targets[#targets + 1] = mapID end
	end
	return targets, (#targets == 1 and targets[1] or continent)
end

-- Glides OpenMap's stitched view to frame the given maps. OpenMap may only switch to its
-- stitched map a moment after the world map opens, so this retries briefly.
function Map:FitView(mapIDs)
	local api = OpenMap()
	if not api then return false end
	local token = {}
	self.fitToken = token
	local tries = 0
	local function attempt()
		if self.fitToken ~= token or not WorldMapFrame:IsShown() then return end
		if not api.IsStitched() then
			tries = tries + 1
			if tries < 20 then C_Timer.After(0.05, attempt) end
			return
		end
		local u0, v0, u1, v1
		for _, mapID in ipairs(mapIDs) do
			local a, b, c, d = WorldRect(mapID)
			if a then
				u0, v0 = math.min(u0 or a, a), math.min(v0 or b, b)
				u1, v1 = math.max(u1 or c, c), math.max(v1 or d, d)
			end
		end
		if not u0 then return end
		local w, h = (u1 - u0) * FIT_MARGIN, (v1 - v0) * FIT_MARGIN
		local zoom = math.min(1 / math.max(w, 1e-3), 1 / math.max(h, 1e-3), MAX_FIT_ZOOM)
		api.ShowWorld((u0 + u1) / 2, (v0 + v1) / 2, math.max(1, zoom))
	end
	attempt()
	return true
end

-- Opens the world map on mapID, or turns the open map to it. Through EasyFind's OpenMap when
-- it's installed: a SetMapID from an addon taints the world map for the session.
local function OpenMapTo(mapID)
	if HW.EasyFind and HW.EasyFind:OpenMap(mapID) then return end
	if WorldMapFrame:IsShown() then
		WorldMapFrame:SetMapID(mapID)
	else
		OpenWorldMap(mapID)
	end
end

-- Moves the map to one zone: a glide on OpenMap's map, a map change on Blizzard's.
function Map:FocusMap(mapID)
	if IsStitched() then
		self:FitView({ mapID })
	else
		OpenMapTo(mapID)
	end
end

-- Opens the map on a set of snapshot zones (an NPC's), framing them on OpenMap's map.
function Map:ShowZones(zoneIdxs)
	local targets = {}
	for _, zoneIdx in ipairs(zoneIdxs or {}) do
		local mapID = self:ResolveZone(zoneIdx)
		if mapID then targets[#targets + 1] = mapID end
	end
	if #targets == 0 then
		HW:Print("No world map for this NPC's zones.")
		return
	end
	if OpenMap() then
		if not WorldMapFrame:IsShown() then OpenMapTo(targets[1]) end
		self:FitView(targets)
	else
		OpenMapTo(#targets == 1 and targets[1] or GetContinent(targets[1]))
	end
end

-- "Show on map": track the item, turn the pins on, open the map framed on where it drops
-- (focusZoneIdx: a snapshot zone, focusMapID: a world map, e.g. a place to farm it).
function Map:ShowItem(itemID, focusZoneIdx, focusMapID)
	self.npc = nil
	local active = Track(itemID)
	if not active then
		HW:Print("No map locations known for " .. HW:GetColoredItemName(itemID) .. ".")
		return
	end
	self.restoreFailed = nil
	HW.db.mapItemID = itemID
	HW.db.mapPins = true
	self:RegisterOpenMapToggle()

	local targets, openTo = PickTargets(active, focusZoneIdx, focusMapID)
	if OpenMap() then
		-- OpenMap: open the map (if needed) on the right continent, then glide to the zones.
		if not WorldMapFrame:IsShown() then OpenMapTo(openTo) end
		self:Refresh()
		self:FitView(targets)
	else
		OpenMapTo(openTo)
		self:Refresh()
	end
end

-- Shows an NPC's spawn points (snapshot or QuestieDB) on the map, framed on focusMapID or on the zone
-- where it has the most. Without spawn data, the map goes to the NPC's zones instead.
function Map:ShowNpc(npcID, focusMapID)
	local all, total = HW:GetNpcSpawnZones(npcID)
	local zones = {}
	for mapID, z in pairs(all or {}) do
		if #z.points > 0 then zones[mapID] = z end
	end
	if not total or total == 0 then
		local _, zoneIdxs = HW:GetNpc(npcID)
		if zoneIdxs and #zoneIdxs > 0 then return self:ShowZones(zoneIdxs) end
		HW:Print("No known locations for " .. HW:GetNpcName(npcID) .. ".")
		return
	end
	self.npc = { npcID = npcID, zones = zones, total = total }

	local target = focusMapID and zones[focusMapID] and focusMapID
	if not target then
		for mapID, z in pairs(zones) do
			if not target or #z.points > #zones[target].points then target = mapID end
		end
	end
	if OpenMap() then
		if not WorldMapFrame:IsShown() then OpenMapTo(target) end
		self:Refresh()
		self:FitView({ target })
	else
		OpenMapTo(target)
		self:Refresh()
	end
end

function Map:ClearNpc()
	self.npc = nil
	self:Refresh()
end

-- The NPCs that drop wishlist items and have spawn points: { npcID, zones, best }, best chance
-- first. Built when the map first needs it, rebuilt after the wishlist changes.
function Map:GetWishSources()
	if self.wishSources then return self.wishSources end
	local list, byNpc = {}, {}
	for itemID in pairs(HW.db.wishlist) do
		for _, drop in ipairs(HW:GetDrops(itemID)) do
			local zones, points = HW:GetNpcSpawnZones(drop.npcID)
			if zones and points > 0 then
				local src = byNpc[drop.npcID]
				if not src then
					src = { npcID = drop.npcID, zones = zones, best = -1 }
					byNpc[drop.npcID] = src
					list[#list + 1] = src
				end
				src.best = math.max(src.best, drop.chance or 0)
			end
		end
	end
	table.sort(list, function(a, b) return a.best > b.best end)
	if HW:HasSpawnData() then self.wishSources = list end
	return list
end

function Map:WishlistChanged()
	self.wishSources = nil
	if HW.db.wishMap then self:Refresh() end
end

function Map:SetWishPinsShown(shown)
	HW.db.wishMap = shown and true or false
	self:Refresh()
	if shown and not next(HW.db.wishlist) then
		HW:Print("Your wishlist is empty. Star items in HeadWow to see the mobs that drop them.")
	end
end

-- Stops tracking the item altogether.
function Map:Clear()
	self.active = nil
	self.fitToken = nil
	HW.db.mapItemID = nil
	self:RegisterOpenMapToggle()
	self:Refresh()
end

function Map:Refresh()
	if self.provider and self.provider:GetMap() then
		self.provider:RefreshAllData()
	end
end

---------------------------------------------------------------------------
-- Data provider + pins
---------------------------------------------------------------------------

local Provider = CreateFromMixins(MapCanvasDataProviderMixin)

function Provider:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
	self:GetMap():RemoveAllPinsByTemplate(SPAWN_PIN_TEMPLATE)
end

-- A function placing points (0..1) of mapID on the displayed map (nil for points off it), or
-- nil when the displayed map doesn't show mapID at all.
local function Projector(mapID, displayed, stitched)
	if stitched then
		local api = OpenMap()
		return function(x, y)
			local u, v = api.WorldFromMap(mapID, x, y)
			if not u then return end
			local px, py = api.MapFromWorld(displayed, u, v)
			if px and py and px > -STITCHED_RANGE and px < 1 + STITCHED_RANGE and py > -STITCHED_RANGE and py < 1 + STITCHED_RANGE then
				return px, py
			end
		end
	end
	if mapID == displayed then return function(x, y) return x, y end end
	local left, right, top, bottom = C_Map.GetMapRectOnMap(mapID, displayed)
	if not (left and right and right > left and bottom > top) then return end
	return function(x, y)
		local px, py = left + x * (right - left), top + y * (bottom - top)
		if px >= 0 and px <= 1 and py >= 0 and py <= 1 then return px, py end
	end
end

function Provider:RefreshAllData()
	self:RemoveAllData()
	Map:UpdateBanner()
	local map = self:GetMap()
	local displayed = map:GetMapID()
	if not displayed then return end
	local stitched = IsStitched()
	local drawn = {} -- npcIDs already pinned (an NPC can be on the page, drop the item and a wish)

	-- Pins one NPC's spawn points, at most budget of them; returns how many it placed.
	local function PlaceSpawns(npcID, zones, budget, info)
		local placed = 0
		drawn[npcID] = true
		for mapID, z in pairs(zones) do
			local project = #z.points > 0 and Projector(mapID, displayed, stitched)
			if project then
				for _, point in ipairs(z.points) do
					if placed >= budget then return placed end
					local x, y = project(point[1], point[2])
					if x then
						placed = placed + 1
						map:AcquirePin(SPAWN_PIN_TEMPLATE, {
							npcID = npcID, x = x, y = y, kind = info.kind,
							itemID = info.itemID, chance = info.chance, samples = info.samples,
						})
					end
				end
			end
		end
		return placed
	end

	-- The NPC opened with "Show on map"
	local npc = Map.npc
	if npc then PlaceSpawns(npc.npcID, npc.zones, MAX_SPAWN_PINS, { kind = "npc" }) end

	-- Wishlist mobs (optional)
	local function PlaceWishes()
		if not (HW.db.wishMap and next(HW.db.wishlist)) then return end
		local budget = MAX_WISH_PINS
		for _, src in ipairs(Map:GetWishSources()) do
			if budget <= 0 then break end
			if not drawn[src.npcID] then
				budget = budget - PlaceSpawns(src.npcID, src.zones, budget, { kind = "wish" })
			end
		end
	end

	if not Map:IsShowingPins() then return PlaceWishes() end
	local active = Map.active

	-- The tracked item: the spawn points of the NPCs that drop it, best chance first...
	local budget = MAX_SPAWN_PINS
	for _, src in ipairs(active.spawnSources) do
		if budget <= 0 then break end
		if not drawn[src.npcID] then
			budget = budget - PlaceSpawns(src.npcID, src.spawnZones, budget,
				{ kind = "item", itemID = active.itemID, chance = src.chance, samples = src.samples })
		end
	end
	PlaceWishes()

	-- ...and a pin per zone for the NPCs without spawn data. Zones that land on the same spot
	-- (e.g. several dungeons in one parent zone) share one.
	local groups = {}
	for mapID, z in pairs(active.zones) do
		if #z.unpinned > 0 and (stitched or not IsAncestor(mapID, displayed)) then
			local x, y, anchorMapID
			if stitched then
				x, y, anchorMapID = GetStitchedPinPosition(mapID, displayed)
			else
				x, y, anchorMapID = GetPinPosition(mapID, displayed)
			end
			if x then
				local g = groups[anchorMapID]
				if not g then
					g = { x = x, y = y, navigateTo = mapID, zones = {}, best = -1, count = 0 }
					groups[anchorMapID] = g
				end
				g.zones[#g.zones + 1] = z
				g.count = g.count + #z.unpinned
				if z.best > g.best then
					g.best = z.best
					g.navigateTo = mapID
				end
			end
		end
	end

	for _, g in pairs(groups) do
		g.itemID = active.itemID
		map:AcquirePin(PIN_TEMPLATE, g)
	end
end

HeadWowMapPinMixin = CreateFromMixins(MapCanvasPinMixin)

function HeadWowMapPinMixin:OnLoad()
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self:SetScalingLimits(1, 1.0, 1.3)
end

-- OpenMap draws its stitched art on the canvas at high frame levels; pins have to sit above it.
function HeadWowMapPinMixin:ApplyFrameLevel()
	MapCanvasPinMixin.ApplyFrameLevel(self)
	local api = OpenMap()
	local top = api and api.IsStitched() and api.ArtTopLevel()
	if type(top) == "number" and self:GetFrameLevel() <= top then
		self:SetFrameLevel(math.min(top + 5, 9900))
	end
end

function HeadWowMapPinMixin:OnAcquired(group)
	self.group = group
	self:SetPosition(group.x, group.y)
	self.Icon:SetTexture(HW:GetItemIcon(group.itemID))
	self.Count:SetText(group.count > 1 and group.count or "")
end

function HeadWowMapPinMixin:OnMouseEnter()
	local g = self.group
	local tooltip = GetAppropriateTooltip and GetAppropriateTooltip() or GameTooltip
	tooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(tooltip, HW:GetColoredItemName(g.itemID))
	for _, z in ipairs(g.zones) do
		GameTooltip_AddBlankLineToTooltip(tooltip)
		GameTooltip_AddNormalLine(tooltip, HW:GetZoneName(z.zoneIdx))
		for i, npc in ipairs(z.unpinned) do
			if i > MAX_TOOLTIP_NPCS then
				GameTooltip_AddDisabledLine(tooltip, string.format("  +%d more", #z.unpinned - MAX_TOOLTIP_NPCS))
				break
			end
			GameTooltip_AddColoredDoubleLine(tooltip, "  " .. npc.name, HW:FormatChance(npc.chance),
				HIGHLIGHT_FONT_COLOR, HW:GetChanceColor(npc.chance))
		end
	end
	GameTooltip_AddBlankLineToTooltip(tooltip)
	GameTooltip_AddDisabledLine(tooltip, "No spawn points known; the pin marks the zone.", true)
	GameTooltip_AddInstructionLine(tooltip, "Click to zoom in")
	tooltip:Show()
end

function HeadWowMapPinMixin:OnMouseLeave()
	local tooltip = GetAppropriateTooltip and GetAppropriateTooltip() or GameTooltip
	tooltip:Hide()
end

function HeadWowMapPinMixin:OnMouseClickAction(button)
	if button == "LeftButton" then
		Map:FocusMap(self.group.navigateTo)
	end
end

-- One NPC spawn point.
HeadWowSpawnPinMixin = CreateFromMixins(MapCanvasPinMixin)

function HeadWowSpawnPinMixin:OnLoad()
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self.Ring:SetVertexColor(1, 0.82, 0)
	self:SetScalingLimits(1, 0.9, 1.2)
end

HeadWowSpawnPinMixin.ApplyFrameLevel = HeadWowMapPinMixin.ApplyFrameLevel

-- Ring colors: gold for an NPC you opened, pink for wishlist mobs; for a tracked item's drop,
-- the drop chance's color (green common ... gray rare).
local RING_COLORS = { npc = { 1, 0.82, 0 }, wish = { 1, 0.45, 0.95 } }

function HeadWowSpawnPinMixin:OnAcquired(info)
	self.info = info
	self:SetPosition(info.x, info.y)
	HW:SetNpcPortrait(self.Portrait, info.npcID)
	if info.kind == "item" then
		self.Ring:SetVertexColor(HW:GetChanceColor(info.chance):GetRGB())
	else
		local c = RING_COLORS[info.kind] or RING_COLORS.npc
		self.Ring:SetVertexColor(c[1], c[2], c[3])
	end
end

function HeadWowSpawnPinMixin:OnMouseEnter()
	local info = self.info
	local drop = info.itemID and { itemID = info.itemID, chance = info.chance, samples = info.samples }
	HW:ShowNpcTooltip(self, info.npcID, "ANCHOR_RIGHT", drop, { "Click: NPC page" })
end

function HeadWowSpawnPinMixin:OnMouseLeave()
	GameTooltip:Hide()
end

function HeadWowSpawnPinMixin:OnMouseClickAction(button)
	if button == "LeftButton" then HW:ShowNpc(self.info.npcID) end
end

---------------------------------------------------------------------------
-- Banner on the world map: what is pinned + NPCs in the zone being viewed
---------------------------------------------------------------------------

local function CreateBanner()
	local banner = CreateFrame("Frame", nil, WorldMapFrame, "TooltipBackdropTemplate")
	banner:SetPoint("TOP", WorldMapFrame.ScrollContainer, "TOP", 0, -8)
	banner:SetSize(360, 40)
	banner:SetFrameStrata(WorldMapFrame.BorderFrame:GetFrameStrata())
	banner:SetFrameLevel(WorldMapFrame.BorderFrame:GetFrameLevel() + 10)
	banner:EnableMouse(true)

	local icon = banner:CreateTexture(nil, "ARTWORK")
	icon:SetSize(24, 24)
	icon:SetPoint("TOPLEFT", 9, -8)
	banner.Icon = icon

	local title = banner:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 0)
	title:SetPoint("RIGHT", -30, 0)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)
	banner.Title = title

	local text = banner:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	text:SetPoint("RIGHT", -12, 0)
	text:SetJustifyH("LEFT")
	text:SetSpacing(2)
	banner.Text = text

	local close = CreateFrame("Button", nil, banner, "UIPanelCloseButtonNoScripts")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function()
		if Map.npc then Map:ClearNpc() else Map:Clear() end
	end)
	close:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, Map.npc and "Hide these spawn points" or "Stop tracking this item")
		GameTooltip:Show()
	end)
	close:SetScript("OnLeave", GameTooltip_Hide)

	banner:SetScript("OnMouseUp", function(_, button)
		if button ~= "LeftButton" then return end
		if Map.npc then HW:ShowNpc(Map.npc.npcID)
		elseif Map.active then HW:ShowItem(Map.active.itemID) end
	end)
	return banner
end

function Map:UpdateBanner()
	if not self.banner then return end
	local banner = self.banner

	-- NPC spawn points take the banner while they're up
	local npc = self.npc
	if npc then
		HW:SetNpcPortrait(banner.Icon, npc.npcID)
		local level = HW:FormatNpcLevel(npc.npcID)
		local title = HW:GetNpcName(npc.npcID)
		if level ~= "" then title = title .. "  |cffffffff" .. (LEVEL or "Level") .. " " .. level .. "|r" end
		banner.Title:SetText(title)
		local zoneCount = 0
		for _ in pairs(npc.zones) do zoneCount = zoneCount + 1 end
		local text = string.format("%d spawn points in %d zone%s", npc.total, zoneCount, zoneCount == 1 and "" or "s")
		local here = npc.zones[WorldMapFrame:GetMapID()]
		if here then text = string.format("%d spawn points in %s", #here.points, here.name) end
		banner.Text:SetText(text)
		banner:SetHeight(26 + banner.Title:GetStringHeight() + banner.Text:GetStringHeight())
		banner:Show()
		return
	end

	if not self:IsShowingPins() then
		banner:Hide()
		return
	end
	local active = self.active

	HW:ForgetNpcPortrait(banner.Icon)
	banner.Icon:SetTexture(HW:GetItemIcon(active.itemID))
	banner.Title:SetText(HW:GetColoredItemName(active.itemID))

	local zoneCount = 0
	for _ in pairs(active.targets) do zoneCount = zoneCount + 1 end
	local lines = { string.format("Dropped by %d NPCs in %d zones", active.total, zoneCount) }
	local mapID = WorldMapFrame:GetMapID()

	local best = active.spots[1]
	if best then
		lines[#lines + 1] = NORMAL_FONT_COLOR:WrapTextInColorCode("Best place: ") .. best.name
			.. "  |cff808080" .. HW.Farm:Describe(best) .. "|r"
	end

	local here = active.zones[mapID]
	if here then
		local spotHere
		for _, spot in ipairs(active.spots) do
			if spot.mapID == mapID then spotHere = spot break end
		end
		lines[#lines + 1] = NORMAL_FONT_COLOR:WrapTextInColorCode("In this zone:")
			.. (spotHere and ("  |cff808080" .. HW.Farm:Describe(spotHere) .. "|r") or "")
		for i, npc in ipairs(here.npcs) do
			if i > 6 then
				lines[#lines + 1] = string.format("+%d more", #here.npcs - 6)
				break
			end
			lines[#lines + 1] = npc.name .. "  " .. HW:GetChanceColor(npc.chance):WrapTextInColorCode(HW:FormatChance(npc.chance))
		end
	end

	banner.Text:SetText(table.concat(lines, "\n"))
	banner:SetHeight(26 + banner.Title:GetStringHeight() + banner.Text:GetStringHeight())
	banner:Show()
end

---------------------------------------------------------------------------
-- OpenMap menu toggle
---------------------------------------------------------------------------

-- (Re-)registers the switch in OpenMap's menu; registering again under the same id replaces
-- it, which keeps its icon on the tracked item.
function Map:RegisterOpenMapToggle()
	local api = OpenMap()
	if not (api and api.RegisterMenuToggle and HW.db) then return end
	local active = self.active
	api.RegisterMenuToggle(OPENMAP_OWNER, {
		id = OPENMAP_TOGGLE,
		label = "Tracked item drops",
		icon = active and HW:GetItemIcon(active.itemID) or "Interface\\Icons\\INV_Misc_Book_09",
		section = "HeadWow",
		get = function() return HW.db.mapPins end,
		set = function(on)
			Map:SetPinsShown(on)
			if on and not Map:GetActive() then
				HW:Print("No item tracked. Use \"Show on map\" on an item in HeadWow (/hw).")
			end
		end,
	})
end

function Map:RegisterOpenMapWishToggle()
	local api = OpenMap()
	if not (api and api.RegisterMenuToggle and HW.db) then return end
	api.RegisterMenuToggle(OPENMAP_OWNER, {
		id = OPENMAP_WISH_TOGGLE,
		label = "Wishlist mobs",
		icon = "Interface\\Icons\\INV_Misc_Note_02",
		section = "HeadWow",
		get = function() return HW.db.wishMap end,
		set = function(on) Map:SetWishPinsShown(on) end,
	})
end

function Map:SetUpOpenMap()
	local api = OpenMap()
	if not api then return end
	self:RegisterOpenMapToggle()
	self:RegisterOpenMapWishToggle()
	if api.RegisterCallback then
		-- pins are placed (and layered) differently on the stitched map
		api.RegisterCallback(self, "OpenMap_StitchedChanged", function() Map:Refresh() end)
	end
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
	Map.provider = CreateFromMixins(Provider)
	WorldMapFrame:AddDataProvider(Map.provider)
	Map.banner = CreateBanner()
	Map.banner:Hide()
end)
