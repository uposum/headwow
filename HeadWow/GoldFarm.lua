-- Gold farming: mobs ranked by what their drops sell for.
--
--   per kill  = sum over the mob's drops of drop chance x item value
--   per clear = per kill x the mob's spawns in its best camp: the densest ~225-yard area of
--               its spawn points (QuestieDB), what one farming loop covers, not the whole zone
--
-- An item's value is its vendor price, or its AH price minus the AH cut when its market looks
-- real: listed on most of your recent scan days and still listed lately (HW:GetMarket). Coin,
-- skinning, kill speed and respawn times aren't in any data HeadWow has, so they're left out.

local HW = HeadWow
local F = HW.F

local GF = {}
HW.GoldFarm = GF

local AH_CUT = 0.95  -- the auction house keeps 5% of a sale
local MAX_TOP = 6    -- drops listed per mob
local MAX_IGNORED = 3 -- AH prices left out, listed per mob

GF.PRICE_MODES = {
	{ key = "best", label = "Best of vendor and AH" },
	{ key = "vendor", label = "Vendor prices only" },
	{ key = "ah", label = "AH (vendor where unknown)" },
}
GF.LEVEL_OPTIONS = { 0, 5, 10, 15, 20 }

-- The price mode in use: the saved one, or vendor prices without Auctionator.
function GF:PriceMode()
	return HW:HasAuctionPrices() and HW.db.farmPrice or "vendor"
end

-- An item's value in copper, where it comes from ("vendor" or "ah") and its AH market (see
-- HW:GetMarket; an AH price whose market doesn't look real isn't used). cache: per build.
function GF:ItemValue(itemID, mode, cache)
	local cached = cache[itemID]
	if cached then return cached[1], cached[2], cached[3] end
	local row = HW:GetItem(itemID)
	local vendor = row and row[F.SELL] or 0
	local ah, market
	if mode ~= "vendor" then ah, market = HW:GetMarketPrice(itemID) end
	ah = ah and math.floor(ah * AH_CUT) or nil
	local value, source = vendor, "vendor"
	if ah and (mode == "ah" or ah > vendor) then value, source = ah, "ah" end
	cache[itemID] = { value, source, market }
	return value, source, market
end

-- The mob's best camp (its densest ~225-yard area, HW:FindCamp) over all its zones:
-- mapID, zone name, spawns in the camp, spawns in that zone, camp x, y; nil without points.
local function BestCamp(npcID)
	local zones = HW:GetNpcSpawnZones(npcID)
	local best, bestZone
	for mapID, z in pairs(zones or {}) do
		local camp = HW:FindCamp(mapID, z.points)
		if camp and (not best or camp.count > best.count) then best, bestZone = camp, z end
	end
	if best then return bestZone.mapID, bestZone.name, best.count, bestZone.count, best.x, best.y end
end

-- Returns a list of mobs worth farming under the options, and whether any mob was left out
-- because its level is unknown. opts: { below = levels under the player (0: any), elites,
-- price = a PRICE_MODES key }. Each entry: { npcID, name, minLevel, maxLevel, rank, perKill,
-- top = { itemID, chance, value, source, contrib }, kills, mapID, zone, spawns, perClear }.
function GF:Build(opts)
	local list, unknownLevels = {}, 0
	local index = HW:GetLootIndex()
	if not index then return list, unknownLevels end
	local ceiling = opts.below > 0 and (UnitLevel("player") - opts.below) or nil
	local cache = {}

	for npcID, loot in pairs(index) do
		local minLevel, maxLevel, rank = HW:GetNpcLevel(npcID)
		local keep = true
		if ceiling then
			if not minLevel or minLevel < 0 then
				keep = false
				if not minLevel then unknownLevels = unknownLevels + 1 end
			elseif maxLevel > ceiling then
				keep = false
			end
		end
		if keep and not opts.elites and rank and rank ~= 0 then keep = false end

		if keep then
			local perKill, top, kills, ignored = 0, {}, 0, {}
			for _, entry in ipairs(loot) do
				if entry.chance and entry.chance > 0 then
					local value, source, market = self:ItemValue(entry.itemID, opts.price, cache)
					if value > 0 then
						local contrib = entry.chance / 100 * value
						perKill = perKill + contrib
						top[#top + 1] = {
							itemID = entry.itemID, chance = entry.chance, value = value, source = source,
							contrib = contrib, market = market,
						}
					end
					-- an AH price left out because its market doesn't look real, worth saying so
					if market and not market.reliable and market.price * AH_CUT > value then
						ignored[#ignored + 1] = {
							itemID = entry.itemID, chance = entry.chance, market = market,
							would = entry.chance / 100 * market.price * AH_CUT,
						}
					end
				end
				-- Wowhead's sample is how often the mob was looted: the same for each of its items
				if (entry.samples or 0) > kills then kills = entry.samples end
			end
			if perKill > 0 then
				table.sort(top, function(a, b) return a.contrib > b.contrib end)
				for i = #top, MAX_TOP + 1, -1 do top[i] = nil end
				table.sort(ignored, function(a, b) return a.would > b.would end)
				for i = #ignored, MAX_IGNORED + 1, -1 do ignored[i] = nil end
				local mapID, zone, spawns, zoneSpawns, campX, campY = BestCamp(npcID)
				if not zone then
					local _, zoneIdxs = HW:GetNpc(npcID)
					zone = zoneIdxs and zoneIdxs[1] and HW:GetZoneName(zoneIdxs[1])
				end
				list[#list + 1] = {
					npcID = npcID, name = HW:GetNpcName(npcID),
					minLevel = minLevel, maxLevel = maxLevel, rank = rank,
					perKill = perKill, top = top, kills = kills, ignored = ignored,
					mapID = mapID, zone = zone, spawns = spawns, zoneSpawns = zoneSpawns,
					campX = campX, campY = campY,
					perClear = spawns and perKill * spawns or nil,
				}
			end
		end
	end
	return list, unknownLevels
end
