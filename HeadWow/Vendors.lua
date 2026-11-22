-- Vendors: who sells an item, whether they'll trade with your faction, and how far away they are.
--
-- Reactions come from the NPCs' Wowhead pages (npcReact, see tools/convert.mjs). Distances are
-- straight lines from you to a vendor's nearest spawn point, in the world coordinates the map
-- API gives for map positions, so only vendors on your continent have one.

local HW = HeadWow
local Data = HeadWowData

---------------------------------------------------------------------------
-- Reactions
---------------------------------------------------------------------------

-- An NPC's reaction to a faction ("Alliance" or "Horde"): 1 friendly, 0 neutral, -1 hostile, or
-- nil when unknown.
function HW:GetNpcReaction(npcID, faction)
	local packed = Data.npcReact[npcID]
	if not packed then return end
	local part
	if faction == "Alliance" then
		part = math.floor(packed / 4)
	elseif faction == "Horde" then
		part = packed % 4
	end
	if part and part > 0 then return part - 2 end
end

function HW:GetNpcReactionToPlayer(npcID)
	return self:GetNpcReaction(npcID, (UnitFactionGroup("player")))
end

---------------------------------------------------------------------------
-- Distances
---------------------------------------------------------------------------

local worldPoints = {} -- npcID -> { { continent, x, y, mapID, mapX, mapY }, ... }, or false for none

local function WorldPosition(mapID, x, y)
	if not (C_Map.GetWorldPosFromMapPos and CreateVector2D and x and y) then return end
	local continent, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
	if continent and pos then
		local wx, wy = pos:GetXY()
		return continent, wx, wy
	end
end

-- Where you are: { continent, x, y (world yards), mapID }, or nil where the game won't say
-- (in instances).
function HW:GetPlayerPosition()
	local mapID = C_Map.GetBestMapForUnit("player")
	local pos = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return end
	local continent, x, y = WorldPosition(mapID, pos:GetXY())
	if continent then return { continent = continent, x = x, y = y, mapID = mapID } end
end

local function NpcWorldPoints(npcID)
	local cached = worldPoints[npcID]
	if cached ~= nil then return cached or nil end
	local points = {}
	for _, spawn in ipairs(HW:GetNpcSpawns(npcID) or {}) do
		if spawn.mapID then
			for _, p in ipairs(spawn.points) do
				local continent, x, y = WorldPosition(spawn.mapID, p[1], p[2])
				if continent then points[#points + 1] = { continent, x, y, spawn.mapID, p[1], p[2] } end
			end
		end
	end
	worldPoints[npcID] = #points > 0 and points or false
	return worldPoints[npcID] or nil
end

-- Yards from `from` (HW:GetPlayerPosition()) to the NPC's nearest spawn point on the same
-- continent, and that point's map ID and x, y (0..1); nil when it has none there.
function HW:GetNpcDistance(npcID, from)
	local points = from and NpcWorldPoints(npcID)
	if not points then return end
	local best, bestPoint
	for _, p in ipairs(points) do
		if p[1] == from.continent then
			local dx, dy = p[2] - from.x, p[3] - from.y
			local d = dx * dx + dy * dy
			if not best or d < best then best, bestPoint = d, p end
		end
	end
	if bestPoint then return math.sqrt(best), bestPoint[4], bestPoint[5], bestPoint[6] end
end

function HW:FormatDistance(yards)
	if yards < 1000 then return math.max(5, math.floor(yards / 5 + 0.5) * 5) .. " yd" end
	return BreakUpLargeNumbers(math.floor(yards / 10 + 0.5) * 10) .. " yd"
end

---------------------------------------------------------------------------
-- An item's vendors
---------------------------------------------------------------------------

-- Vendors you can buy from before hostile ones; then the ones near you, nearest first; then
-- those on other continents, by continent and zone; then those with no known spawn point.
local function Rank(v)
	local where = v.yards and 0 or (v.homeMapID and 1 or 2)
	return (v.reaction == -1 and 3 or 0) + where
end

function HW.CompareVendors(a, b)
	local ra, rb = Rank(a), Rank(b)
	if ra ~= rb then return ra < rb end
	if a.yards and b.yards and a.yards ~= b.yards then return a.yards < b.yards end
	if (a.continent or "") ~= (b.continent or "") then return (a.continent or "") < (b.continent or "") end
	if a.zoneText ~= b.zoneText then return a.zoneText < b.zoneText end
	if (a.unitPrice or math.huge) ~= (b.unitPrice or math.huge) then return (a.unitPrice or math.huge) < (b.unitPrice or math.huge) end
	if a.name ~= b.name then return a.name < b.name end
	return a.npcID < b.npcID
end

-- Works out each vendor's distance from `from` (HW:GetPlayerPosition(), nil when unknown), marks
-- the nearest one you can buy from and sorts the list (HW.CompareVendors). Returns that vendor.
function HW:UpdateVendors(vendors, from)
	local nearest
	for _, v in ipairs(vendors) do
		v.yards, v.mapID, v.x, v.y = self:GetNpcDistance(v.npcID, from)
		v.nearest = nil
		if v.yards and v.reaction ~= -1 and (not nearest or v.yards < nearest.yards) then nearest = v end
	end
	if nearest then nearest.nearest = true end
	table.sort(vendors, HW.CompareVendors)
	return nearest
end

-- The item's vendors as a list of { npcID, name, zoneText, copper (0: another currency), stock
-- (-1: unlimited), stack, unitPrice, reaction (to you), homeMapID (the map with most of its
-- spawns), continent (its name) }, plus what HW:UpdateVendors adds: yards, mapID, x, y (the
-- nearest spawn) and nearest. Sorted, nearest first. Also returns the nearest vendor you can buy
-- from and your position (nil when unknown).
function HW:GetVendors(itemID)
	local vendors = {}
	for _, e in ipairs(self:GetSources(itemID).vendor or {}) do
		local spawns = self:GetNpcSpawns(e.npcID)
		local home
		for _, spawn in ipairs(spawns or {}) do
			if spawn.mapID then
				home = spawn
				break
			end
		end
		local zoneText = e.zones[1] and self:GetZoneName(e.zones[1]) or (home and home.name) or ""
		local stack = e.stack or 1
		vendors[#vendors + 1] = {
			npcID = e.npcID, name = e.name, zoneText = zoneText,
			copper = e.copper or 0, stock = e.stock or -1, stack = stack,
			unitPrice = (e.copper or 0) > 0 and e.copper / stack or nil,
			reaction = self:GetNpcReactionToPlayer(e.npcID),
			homeMapID = home and home.mapID,
			continent = home and self.Map and self.Map.GetContinentName and self.Map:GetContinentName(home.mapID) or nil,
		}
	end
	local from = self:GetPlayerPosition()
	return vendors, self:UpdateVendors(vendors, from), from
end
