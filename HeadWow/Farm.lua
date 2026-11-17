-- Where to farm an item: its drop sources with their spawn points (the snapshot's, else QuestieDB's), and the zones
-- ranked by how many drops to expect from one clear of the zone's best camp: the densest
-- ~225-yard area (HW:FindCamp) of spawns of every NPC that drops it, each spawn counting its
-- drop chance. Not the whole zone: nobody clears a few hundred spawns spread across it.
--
-- Without spawn points for an NPC (neither the snapshot nor QuestieDB has them) the NPC counts as
-- a single spawn in each of its snapshot zones, and the spot is marked as a guess.

local HW = HeadWow

local Farm = {}
HW.Farm = Farm

local cache = {} -- itemID -> { sources, spots }

-- Returns sources, spots for an item.
--  sources: { npcID, name, chance, samples, zoneIdxs, spawnZones, spawnPoints }, best chance first
--           (spawnZones as HW:GetNpcSpawnZones, nil without spawn data)
--  spots:   { mapID, name, expected (drops per camp clear), spawns (in the camp), zoneSpawns,
--             campX, campY, guessed, npcs = { { npcID, name, chance, count (in the camp) } } },
--           most expected drops first
function Farm:Get(itemID)
	local cached = cache[itemID]
	if cached then return cached.sources, cached.spots end

	local drops = HW:GetDrops(itemID)
	local sources, zonesByMap = {}, {}

	local function Zone(mapID, name)
		local zone = zonesByMap[mapID]
		if not zone then
			zone = { mapID = mapID, name = name, points = {}, zoneSpawns = 0, guessed = {}, npcs = {} }
			zonesByMap[mapID] = zone
		end
		return zone
	end

	for _, drop in ipairs(drops) do
		local zones, points = HW:GetNpcSpawnZones(drop.npcID)
		local source = {
			npcID = drop.npcID, name = drop.name, chance = drop.chance, samples = drop.samples,
			zoneIdxs = drop.zones, spawnZones = zones, spawnPoints = points or 0,
		}
		sources[#sources + 1] = source

		local chance = drop.chance and drop.chance / 100
		if chance and chance > 0 then
			local placed = false
			for mapID, z in pairs(zones or {}) do
				if #z.points > 0 then
					local zone = Zone(mapID, z.name)
					for _, point in ipairs(z.points) do
						zone.points[#zone.points + 1] = { point[1], point[2], chance, drop.npcID }
					end
					zone.zoneSpawns = zone.zoneSpawns + z.count
					zone.npcs[drop.npcID] = drop
					placed = true
				end
			end
			if not placed then
				for _, zoneIdx in ipairs(drop.zones) do
					local mapID = HW.Map:ResolveZone(zoneIdx)
					if mapID then
						local zone = Zone(mapID, HW:GetZoneName(zoneIdx))
						zone.guessed[#zone.guessed + 1] = drop
					end
				end
			end
		end
	end

	local spots = {}
	for mapID, zone in pairs(zonesByMap) do
		local spot = { mapID = mapID, name = zone.name, expected = 0, spawns = 0, zoneSpawns = zone.zoneSpawns, npcs = {} }
		local camp = HW:FindCamp(mapID, zone.points)
		if camp then
			spot.expected, spot.spawns = camp.weight, camp.count
			spot.campX, spot.campY = camp.x, camp.y
			for npcID, count in pairs(camp.tags) do
				local drop = zone.npcs[npcID]
				spot.npcs[#spot.npcs + 1] = { npcID = npcID, name = drop.name, chance = drop.chance, count = count }
			end
		else
			-- no spawn points here: each NPC counts as one spawn
			for _, drop in ipairs(zone.guessed) do
				spot.expected = spot.expected + drop.chance / 100
				spot.npcs[#spot.npcs + 1] = { npcID = drop.npcID, name = drop.name, chance = drop.chance }
			end
			spot.guessed = true
		end
		spots[#spots + 1] = spot
	end

	table.sort(sources, function(a, b) return (a.chance or -1) > (b.chance or -1) end)
	table.sort(spots, function(a, b)
		if a.expected ~= b.expected then return a.expected > b.expected end
		return a.name < b.name
	end)
	for _, spot in ipairs(spots) do
		table.sort(spot.npcs, function(a, b) return (a.chance or 0) * (a.count or 1) > (b.chance or 0) * (b.count or 1) end)
	end

	-- QuestieDB may still be loading: only keep results once its data is in.
	if HW:HasSpawnData() then cache[itemID] = { sources = sources, spots = spots } end
	return sources, spots
end

-- The best spot for an item, or nil.
function Farm:GetBest(itemID)
	local _, spots = self:Get(itemID)
	return spots[1]
end

-- Drops per clear of a camp: "2.4 per clear", "0.35 per clear", "1 per 12 clears";
-- short: "2.4", "0.35", "1 in 12".
function Farm:FormatRate(expected, short)
	if not expected or expected <= 0 then return "?" end
	if expected >= 0.1 then
		local value = string.format(expected >= 1 and "%.1f" or "%.2f", expected)
		return short and value or (value .. " per clear")
	end
	local clears = BreakUpLargeNumbers(math.floor(1 / expected + 0.5))
	return short and ("1 in " .. clears) or ("1 per " .. clears .. " clears")
end

-- One line describing a spot: "0.35 per clear · camp of 24 spawns".
function Farm:Describe(spot)
	if spot.guessed then
		local best = spot.npcs[1]
		return "Best chance " .. HW:FormatChance(best and best.chance) .. "  ·  spawns unknown"
	end
	return self:FormatRate(spot.expected) .. "  ·  camp of " .. spot.spawns .. (spot.spawns == 1 and " spawn" or " spawns")
end

-- Tooltip body for a spot (after its title).
function Farm:AddSpotLines(tooltip, spot, maxNpcs)
	maxNpcs = maxNpcs or 8
	GameTooltip_AddNormalLine(tooltip, self:Describe(spot))
	if not spot.guessed then
		GameTooltip_AddHighlightLine(tooltip, string.format("Camp: the densest %d-yard area, around %.0f, %.0f (%d spawns in the whole zone).",
			HW.CAMP_SIZE, spot.campX * 100, spot.campY * 100, spot.zoneSpawns), true)
	end
	GameTooltip_AddBlankLineToTooltip(tooltip)
	for i, npc in ipairs(spot.npcs) do
		if i > maxNpcs then
			GameTooltip_AddDisabledLine(tooltip, string.format("+%d more", #spot.npcs - maxNpcs))
			break
		end
		local left = npc.name .. (npc.count and (" |cff808080x" .. npc.count .. "|r") or "")
		GameTooltip_AddColoredDoubleLine(tooltip, left, HW:FormatChance(npc.chance), HIGHLIGHT_FONT_COLOR, HW:GetChanceColor(npc.chance))
	end
	GameTooltip_AddBlankLineToTooltip(tooltip)
	if spot.guessed then
		GameTooltip_AddDisabledLine(tooltip, "No spawn points for these NPCs; each counts as one spawn.", true)
	end
	GameTooltip_AddDisabledLine(tooltip, "Per clear: drops to expect from killing every spawn in the camp once.", true)
end
