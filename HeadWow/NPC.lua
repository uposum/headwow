-- NPCs: data access, loot tables, portraits and the 3D hover card.
--
-- The snapshot has each NPC's name and zones (and, through the item drop tables, what it
-- drops). It has no display IDs, so portraits come from the game: a hidden model is pointed
-- at the creature (SetCreature) and asked for its display ID, which is cached in the saved
-- variables. Portraits are then drawn with SetPortraitTextureFromCreatureDisplayID.

local HW = HeadWow
local Data = HeadWowData

local PLACEHOLDER_PORTRAIT = "Interface\\Minimap\\UI-Minimap-Background" -- a dark disc, not a face
HW.NPC_PORTRAIT_PLACEHOLDER = PLACEHOLDER_PORTRAIT
local RESOLVE_RETRY = 0.25      -- seconds between checks while the client fetches a creature
local RESOLVE_TRIES = 20         -- 5 s for the server to answer about a creature
local CARD_WIDTH, CARD_HEIGHT = 150, 190

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

-- Returns name, zones (list of zone indices) for an NPC in the snapshot, or nil.
function HW:GetNpc(npcID)
	local row = Data.npcs[npcID]
	if not row then return nil end
	local zones = {}
	for i = 2, #row do zones[#zones + 1] = row[i] end
	return row[1], zones
end

function HW:GetNpcName(npcID)
	local row = Data.npcs[npcID]
	return row and row[1] or ("NPC " .. npcID)
end

function HW:GetNpcZoneText(npcID, max)
	local _, zones = self:GetNpc(npcID)
	if not zones then return "" end
	local names = {}
	for i, z in ipairs(zones) do
		if max and i > max then
			names[#names + 1] = "..."
			break
		end
		names[#names + 1] = self:GetZoneName(z)
	end
	return table.concat(names, ", ")
end

---------------------------------------------------------------------------
-- Levels (not in the snapshot): QuestieDB's public API (LibQuestieDB, installed with Questie)
-- when it's there, else the game's own tooltip data for the creature, which it has once the
-- creature has been seen.
---------------------------------------------------------------------------

local RANK_TEXT = { [1] = "Elite", [2] = "Rare Elite", [3] = "Boss", [4] = "Rare" }
local QUESTIEDB_CONTRACT = 4
local levelCache = {} -- npcID -> { min, max, rank }

local function NpcDB()
	local lib = _G.LibQuestieDB
	if type(lib) ~= "table" or type(lib.Npc) ~= "table" or type(lib.Npc.Get) ~= "function" then return end
	if lib.RequireContract and not lib.RequireContract(QUESTIEDB_CONTRACT) then return end
	return lib.Npc
end

local function LevelFromQuestie(npcID)
	local db = NpcDB()
	if not db then return end
	local ok, minLevel = pcall(db.Get, npcID, "minLevel")
	if not ok or type(minLevel) ~= "number" or minLevel <= 0 then return end
	local _, maxLevel = pcall(db.Get, npcID, "maxLevel")
	local _, rank = pcall(db.Get, npcID, "rank")
	return { minLevel, type(maxLevel) == "number" and maxLevel or minLevel, type(rank) == "number" and rank or 0 }
end

local levelPattern
local function LevelFromTooltip(npcID)
	if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return end
	local ok, data = pcall(C_TooltipInfo.GetHyperlink, ("unit:Creature-0-0-0-0-%d-0000000000"):format(npcID))
	if not ok or not data or not data.lines then return end
	levelPattern = levelPattern or ("^" .. (LEVEL or "Level") .. " (%S+)")
	for i = 2, #data.lines do
		local text = data.lines[i].leftText
		local value = text and text:match(levelPattern)
		if value then
			local level = tonumber(value)
			if level then return { level, level, 0 } end
			return { -1, -1, 3 } -- "??": a boss
		end
	end
end

-- Returns minLevel, maxLevel, rank (0 normal, 1 elite, 2 rare elite, 3 boss, 4 rare), or nil.
-- minLevel is -1 for "??".
function HW:GetNpcLevel(npcID)
	local cached = levelCache[npcID]
	if not cached then
		cached = LevelFromQuestie(npcID) or LevelFromTooltip(npcID)
		if not cached then return nil end
		levelCache[npcID] = cached
	end
	return cached[1], cached[2], cached[3]
end

-- "12", "12-14", "60 Elite", "?? Boss"; "" when unknown. short: no rank word.
function HW:FormatNpcLevel(npcID, short)
	local minLevel, maxLevel, rank = self:GetNpcLevel(npcID)
	if not minLevel then return "" end
	local text
	if minLevel < 0 then text = "??"
	elseif maxLevel > minLevel then text = minLevel .. "-" .. maxLevel
	else text = tostring(minLevel) end
	if not short and RANK_TEXT[rank] then text = text .. " " .. RANK_TEXT[rank] end
	return text
end

-- For sorting: the NPC's highest level, 999 for "??", -1 when unknown.
function HW:GetNpcSortLevel(npcID)
	local minLevel, maxLevel = self:GetNpcLevel(npcID)
	if not minLevel then return -1 end
	if minLevel < 0 then return 999 end
	return maxLevel
end

---------------------------------------------------------------------------
-- Spawns (QuestieDB): where the NPC stands, by zone
---------------------------------------------------------------------------

-- The NPC's title ("Weapon Vendor"), from QuestieDB, or nil.
function HW:GetNpcSubName(npcID)
	local db = NpcDB()
	if not db then return end
	local ok, subName = pcall(db.Get, npcID, "subName")
	if ok and type(subName) == "string" and subName ~= "" then return subName end
end

-- Returns a list of { areaID, name, mapID, points = { {x, y}, ... } (0..1 on mapID), count },
-- most spawns first, or nil when QuestieDB doesn't know the NPC. mapID is nil for an area
-- without a world map (some instances); points is empty where the spawns have no position.
function HW:GetNpcSpawns(npcID)
	local db = NpcDB()
	if not db then return end
	local ok, spawns = pcall(db.Get, npcID, "spawns")
	if not ok or type(spawns) ~= "table" or not next(spawns) then return end
	local out = {}
	for areaID, list in pairs(spawns) do
		if type(areaID) == "number" and type(list) == "table" then
			local name = C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID)
			local mapID = name and self.Map:ResolveZoneName(name)
			local points = {}
			for _, p in ipairs(list) do
				local x, y = type(p) == "table" and p[1], type(p) == "table" and p[2]
				if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
					points[#points + 1] = { x / 100, y / 100 }
				end
			end
			out[#out + 1] = { areaID = areaID, name = name or ("Area " .. areaID), mapID = mapID, points = points, count = #list }
		end
	end
	table.sort(out, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.name < b.name
	end)
	return out
end

function HW:HasSpawnData()
	return NpcDB() ~= nil
end

---------------------------------------------------------------------------
-- Camps: where spawns are densest. A zone's total spawns can be spread over the whole zone
-- (or a mob can stand in many zones), and nobody clears all of them; a camp is what one
-- farming loop covers: the busiest CAMP_CELLS x CAMP_CELLS block of CAMP_CELL-yard cells.
---------------------------------------------------------------------------

local CAMP_CELL = 75                  -- yards
local CAMP_CELLS = 3                  -- so a camp is ~225 yards across
local DEFAULT_MAP_SIZE = { 3000, 2000 } -- yards, when the game can't tell (a typical zone)
HW.CAMP_SIZE = CAMP_CELL * CAMP_CELLS

local mapSizes = {}

local function MapSize(mapID)
	local size = mapSizes[mapID]
	if size then return size[1], size[2] end
	local width, height
	if C_Map.GetMapWorldSize then
		width, height = C_Map.GetMapWorldSize(mapID)
	end
	if not (width and width > 0 and height and height > 0) and C_Map.GetWorldPosFromMapPos and CreateVector2D then
		local _, a = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
		local _, b = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 1))
		if a and b then
			-- world X runs north-south and Y east-west; either way the extents are the size
			local ax, ay = a:GetXY()
			local bx, by = b:GetXY()
			width, height = math.abs(ay - by), math.abs(ax - bx)
		end
	end
	if not (width and width > 0 and height and height > 0) then
		width, height = DEFAULT_MAP_SIZE[1], DEFAULT_MAP_SIZE[2]
	end
	mapSizes[mapID] = { width, height }
	return width, height
end

-- Finds the densest camp among points on mapID. points: list of { x, y, weight, tag } (x, y
-- 0..1; weight defaults to 1; tag, e.g. an npcID, is tallied). Returns nil for no points, or
-- { weight = summed weight, count = points, x, y = its center (0..1), tags = { [tag] = n } }.
function HW:FindCamp(mapID, points)
	if #points == 0 then return nil end
	local width, height = MapSize(mapID)
	local cellX, cellY = CAMP_CELL / width, CAMP_CELL / height
	local cells = {}
	for _, p in ipairs(points) do
		local cx, cy = math.floor(p[1] / cellX), math.floor(p[2] / cellY)
		local key = cx * 100000 + cy
		local cell = cells[key]
		if not cell then
			cell = { cx = cx, cy = cy, weight = 0, points = {} }
			cells[key] = cell
		end
		cell.weight = cell.weight + (p[3] or 1)
		cell.points[#cell.points + 1] = p
	end

	-- every block of cells with an occupied cell at its center (CAMP_CELLS is odd)
	local reach = math.floor(CAMP_CELLS / 2)
	local best
	for _, center in pairs(cells) do
		local weight, count = 0, 0
		for dx = -reach, reach do
			for dy = -reach, reach do
				local cell = cells[(center.cx + dx) * 100000 + center.cy + dy]
				if cell then
					weight = weight + cell.weight
					count = count + #cell.points
				end
			end
		end
		if not best or weight > best.weight or (weight == best.weight and count > best.count) then
			best = { weight = weight, count = count, center = center }
		end
	end

	local tags = {}
	for dx = -reach, reach do
		for dy = -reach, reach do
			local cell = cells[(best.center.cx + dx) * 100000 + best.center.cy + dy]
			for _, p in ipairs(cell and cell.points or {}) do
				if p[4] ~= nil then tags[p[4]] = (tags[p[4]] or 0) + 1 end
			end
		end
	end
	return {
		weight = best.weight, count = best.count, tags = tags,
		x = (best.center.cx + 0.5) * cellX, y = (best.center.cy + 0.5) * cellY,
	}
end

-- The NPC's spawns grouped by world map: { [mapID] = { mapID, name, points, count } } (count:
-- all spawns there, points: those with a position) and the number of points, or nil when
-- QuestieDB doesn't know the NPC. Cached; callers must not change the tables.
local spawnZoneCache = {}

function HW:GetNpcSpawnZones(npcID)
	local cached = spawnZoneCache[npcID]
	if cached ~= nil then
		if cached then return cached.zones, cached.total end
		return
	end
	local spawns = self:GetNpcSpawns(npcID)
	if not spawns then
		if NpcDB() then spawnZoneCache[npcID] = false end -- known to have none
		return
	end
	local zones, total = {}, 0
	for _, spawn in ipairs(spawns) do
		if spawn.mapID then
			local z = zones[spawn.mapID]
			if not z then
				z = { mapID = spawn.mapID, name = spawn.name, points = {}, count = 0 }
				zones[spawn.mapID] = z
			end
			z.count = z.count + spawn.count
			for _, point in ipairs(spawn.points) do
				z.points[#z.points + 1] = point
				total = total + 1
			end
		end
	end
	spawnZoneCache[npcID] = { zones = zones, total = total }
	return zones, total
end

-- npcID -> list of { itemID, chance, samples }, built from the item drop tables on first use.
-- Only as complete as those tables: an item whose Wowhead table was truncated may be missing.
local lootIndex

local function BuildLootIndex()
	lootIndex = {}
	for itemID, raw in pairs(Data.drops) do
		for i = 2, #raw, 3 do
			local npcID, bp, samples = raw[i], raw[i + 1], raw[i + 2]
			local list = lootIndex[npcID]
			if not list then
				list = {}
				lootIndex[npcID] = list
			end
			list[#list + 1] = { itemID = itemID, chance = bp >= 0 and bp / 100 or nil, samples = samples }
		end
	end
end

-- The whole index (npcID -> entries), for passes over every NPC; nil without drop data.
-- Callers must not change it.
function HW:GetLootIndex()
	if not self:EnsureDrops() then return nil end
	if not lootIndex then BuildLootIndex() end
	return lootIndex
end

function HW:GetNpcLoot(npcID)
	if not self:EnsureDrops() then return {} end
	if not lootIndex then BuildLootIndex() end
	local out = {}
	for i, entry in ipairs(lootIndex[npcID] or {}) do
		out[i] = { itemID = entry.itemID, chance = entry.chance, samples = entry.samples }
	end
	return out
end

-- Search over NPC names. Returns a sorted array of npcIDs.
local npcIndex

local function BuildNpcIndex()
	local ids, names = {}, {}
	for id in pairs(Data.npcs) do ids[#ids + 1] = id end
	table.sort(ids)
	for i, id in ipairs(ids) do names[i] = Data.npcs[id][1]:lower() end
	npcIndex = { ids = ids, names = names }
end

function HW:SearchNpcs(query)
	query = strtrim(query or ""):lower()
	if query == "" then return {} end
	if not npcIndex then BuildNpcIndex() end
	local tokens = {}
	for token in query:gmatch("%S+") do tokens[#tokens + 1] = token end
	local exactID = tonumber(query)

	local results, scores = {}, {}
	local ids, names = npcIndex.ids, npcIndex.names
	for i = 1, #ids do
		local id, name = ids[i], names[i]
		local match = true
		for t = 1, #tokens do
			if not name:find(tokens[t], 1, true) then
				match = false
				break
			end
		end
		if exactID and id == exactID then
			results[#results + 1] = id
			scores[id] = -1
		elseif match and not exactID then
			results[#results + 1] = id
			if name == query then scores[id] = 0
			elseif name:sub(1, #query) == query then scores[id] = 1
			else scores[id] = 2 end
		end
	end
	table.sort(results, function(a, b)
		if scores[a] ~= scores[b] then return scores[a] < scores[b] end
		return Data.npcs[a][1] < Data.npcs[b][1]
	end)
	return results
end

---------------------------------------------------------------------------
-- Portraits
---------------------------------------------------------------------------

local RETRY_FAILED_AFTER = 60   -- seconds before a creature the game couldn't show is asked again

local resolver                  -- off-screen-ish PlayerModel used to look up display IDs
local queue, queued = {}, {}
local failed = {}               -- npcID -> GetTime() when the game couldn't give a display
local waiting = setmetatable({}, { __mode = "k" }) -- texture -> npcID it should show
local current, tries, loaded, before

local DISPLAY_CACHE_VERSION = 2 -- bump to drop display IDs cached by an older lookup

local function DisplayCache()
	if HW.db.npcDisplayVersion ~= DISPLAY_CACHE_VERSION then
		HW.db.npcDisplay, HW.db.npcDisplayVersion = {}, DISPLAY_CACHE_VERSION
	end
	return HW.db.npcDisplay
end

function HW:GetNpcDisplayID(npcID)
	return DisplayCache()[npcID]
end

local function Resolved(npcID, displayID)
	DisplayCache()[npcID] = displayID
	failed[npcID] = nil
	for texture, id in pairs(waiting) do
		if id == npcID then
			texture:SetVertexColor(1, 1, 1)
			SetPortraitTextureFromCreatureDisplayID(texture, displayID)
			waiting[texture] = nil
		end
	end
end

local Check

local function Next()
	current = table.remove(queue, 1)
	if not current then return end
	queued[current] = nil
	tries, loaded = 0, false
	resolver:ClearModel()
	before = resolver:GetDisplayInfo() or 0
	resolver:SetCreature(current)
	Check()
end

-- A display counts once the model has loaded the creature (OnModelLoaded), or once it differs
-- from what the cleared model reported, so a stale display is never taken for the new NPC.
function Check()
	local npcID = current
	if not npcID then return end
	local displayID = resolver:GetDisplayInfo()
	if displayID and displayID > 0 and (loaded or displayID ~= before) then
		Resolved(npcID, displayID)
		return Next()
	end
	tries = tries + 1
	if tries >= RESOLVE_TRIES then
		failed[npcID] = GetTime()
		return Next()
	end
	C_Timer.After(RESOLVE_RETRY, function()
		if current == npcID then Check() end
	end)
end

local function CreateResolver()
	-- Models that aren't drawn never load (Blizzard's own hidden models sit at alpha 0.01).
	resolver = CreateFrame("PlayerModel", nil, UIParent)
	resolver:SetSize(32, 32)
	resolver:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
	resolver:SetFrameStrata("BACKGROUND")
	resolver:SetFrameLevel(0)
	resolver:SetAlpha(0.01)
	resolver:EnableMouse(false)
	resolver:SetScript("OnModelLoaded", function()
		loaded = true
		Check()
	end)
end

local function Request(npcID)
	if queued[npcID] or npcID == current then return end
	if failed[npcID] and GetTime() - failed[npcID] < RETRY_FAILED_AFTER then return end
	if not resolver then CreateResolver() end
	queued[npcID] = true
	queue[#queue + 1] = npcID
	if not current then Next() end
end

-- Learns an NPC's display from a model the player can see (NPC page, hover card), which the
-- game always loads: the portrait cache fills in as NPCs are looked at.
function HW:LearnNpcDisplay(model, npcID)
	model.hwNpcID = npcID
	if self:GetNpcDisplayID(npcID) then return end
	local start = model:GetDisplayInfo() or 0
	local n = 0
	local function Poll()
		if model.hwNpcID ~= npcID or self:GetNpcDisplayID(npcID) then return end
		local displayID = model:GetDisplayInfo()
		if displayID and displayID > 0 and displayID ~= start then
			Resolved(npcID, displayID)
			return
		end
		n = n + 1
		if n < 25 then C_Timer.After(0.2, Poll) end
	end
	C_Timer.After(0.1, Poll)
end

-- Stops a pending portrait from landing on a texture that now shows something else.
function HW:ForgetNpcPortrait(texture)
	waiting[texture] = nil
end

-- Shows the NPC's round portrait on a texture, or a placeholder until the game has it (the
-- texture is filled in when the display ID arrives, unless it was given another NPC since).
function HW:SetNpcPortrait(texture, npcID)
	local displayID = npcID and self:GetNpcDisplayID(npcID)
	if displayID then
		waiting[texture] = nil
		texture:SetVertexColor(1, 1, 1)
		SetPortraitTextureFromCreatureDisplayID(texture, displayID)
		return
	end
	texture:SetTexture(PLACEHOLDER_PORTRAIT)
	texture:SetVertexColor(1, 1, 1)
	if npcID then
		waiting[texture] = npcID
		Request(npcID)
	else
		waiting[texture] = nil
	end
end

---------------------------------------------------------------------------
-- Hover card: the NPC's 3D model beside GameTooltip
---------------------------------------------------------------------------

local card

local function CreateCard()
	card = CreateFrame("Frame", "HeadWowNpcCard", UIParent, "TooltipBackdropTemplate")
	card:SetSize(CARD_WIDTH, CARD_HEIGHT)
	card:SetFrameStrata("TOOLTIP")
	card:SetClampedToScreen(true)
	card:Hide()

	local model = CreateFrame("PlayerModel", nil, card)
	model:SetPoint("TOPLEFT", 5, -5)
	model:SetPoint("BOTTOMRIGHT", -5, 5)
	card.Model = model

	GameTooltip:HookScript("OnHide", function() card:Hide() end)
end

-- The card goes on the tooltip's far side from whatever it describes (the row, the window
-- it's in), so it never covers that; the near side only when the screen edge leaves no room.
local function CardOnRight(tooltip)
	local left, right = tooltip:GetLeft(), tooltip:GetRight()
	if not (left and right) then return false end
	local scale = tooltip:GetEffectiveScale()
	local need = (CARD_WIDTH + 10) * card:GetEffectiveScale()
	local roomLeft = left * scale
	local roomRight = UIParent:GetRight() * UIParent:GetEffectiveScale() - right * scale

	local onRight = roomLeft < need
	local owner = tooltip:GetOwner()
	local ownerX = owner and owner ~= UIParent and owner.GetCenter and owner:GetCenter()
	if ownerX then
		onRight = ownerX * owner:GetEffectiveScale() < (left + right) / 2 * scale
	end
	if onRight and roomRight < need then return false end
	if not onRight and roomLeft < need then return true end
	return onRight
end

-- Call after filling (and showing) the tooltip.
function HW:AttachNpcCard(tooltip, npcID)
	if not npcID then return end
	if not card then CreateCard() end
	tooltip = tooltip or GameTooltip
	card:ClearAllPoints()
	if CardOnRight(tooltip) then
		card:SetPoint("TOPLEFT", tooltip, "TOPRIGHT", 2, 0)
	else
		card:SetPoint("TOPRIGHT", tooltip, "TOPLEFT", -2, 0)
	end
	card.Model:ClearModel()
	card.Model:SetCreature(npcID)
	HW:LearnNpcDisplay(card.Model, npcID)
	card.Model:SetRotation(math.rad(15))
	card:Show()
end

---------------------------------------------------------------------------
-- Shared NPC tooltip
---------------------------------------------------------------------------

-- Fills GameTooltip for an NPC. `drop` (optional) adds the chance for the item in view;
-- `hints` is a list of instruction lines.
function HW:ShowNpcTooltip(owner, npcID, anchor, drop, hints)
	local tooltip = GameTooltip
	tooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
	self:FillNpcTooltip(tooltip, npcID, drop, hints)
	tooltip:Show()
	self:AttachNpcCard(tooltip, npcID)
end

function HW:FillNpcTooltip(tooltip, npcID, drop, hints)
	GameTooltip_SetTitle(tooltip, self:GetNpcName(npcID))
	local level = self:FormatNpcLevel(npcID)
	if level ~= "" then GameTooltip_AddNormalLine(tooltip, (LEVEL or "Level") .. " " .. level) end
	local zones = self:GetNpcZoneText(npcID)
	if zones ~= "" then GameTooltip_AddHighlightLine(tooltip, zones, true) end
	if drop then
		GameTooltip_AddBlankLineToTooltip(tooltip)
		if drop.itemID then GameTooltip_AddNormalLine(tooltip, "Drops " .. self:GetColoredItemName(drop.itemID)) end
		GameTooltip_AddColoredDoubleLine(tooltip, "Drop chance", self:FormatChance(drop.chance),
			NORMAL_FONT_COLOR, self:GetChanceColor(drop.chance))
		if drop.samples and drop.samples > 0 then
			GameTooltip_AddColoredDoubleLine(tooltip, "Kills sampled", BreakUpLargeNumbers(drop.samples),
				NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR)
		end
	end
	self:AddWishedLootLines(tooltip, npcID, drop and drop.itemID)
	if hints and #hints > 0 then
		GameTooltip_AddBlankLineToTooltip(tooltip)
		for _, hint in ipairs(hints) do GameTooltip_AddInstructionLine(tooltip, hint) end
	end
end
