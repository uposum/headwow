-- A tiny snapshot in the generated data's row formats (see tools/convert.mjs).

local Data = HeadWowData
Data.zones = { "Felwood", "Azshara", "The Barrens", "Nowhere" }
-- npcs[id] = { name, zoneIdx, ... }
Data.npcs = { [1] = { "Wolf", 1 }, [2] = { "Bear", 2, 1 }, [3] = { "Raptor", 3 }, [4] = { "Ghost", 4 } }
-- items[id] = { name, quality, itemLevel, requiredLevel, slotIdx, sourceMask, sellCopper, zoneIdx, from, dropRows }
Data.items = {
	[100] = { "Plate Chest", 2, 50, 45, 1, 1, nil, nil, nil, 4 }, [101] = { "Cloth Chest", 2, 50, 45, 1, 1 },
	[102] = { "Dagger", 2, 20, 15, 1, 1 }, [103] = { "Shield", 3, 40, 35, 1, 1 }, [104] = { "Cloak", 2, 30, 25, 1, 1 },
	[105] = { "Wand", 2, 30, 25, 1, 1 }, [106] = { "Ring", 4, 62, 61, 1, 1 }, [200] = { "Junk", 0, 1, nil, nil, 1 },
}
-- drops[itemId] = { leftOut, npcId, chanceBasisPoints, samples, stack x100, ... }
Data.drops = {
	[100] = { 0, 1, 50, 1000, 100, 2, 100, 500, 100, 3, 2, 9000, 100, 4, 300, 10, 100 }, -- wolf 0.5%, bear 1%, raptor 0.02%, ghost 3% (no spawns)
	[200] = { 0, 1, 4000, 1000, 200 },                                       -- wolf junk 40%, 2 at a time
	[101] = { 0, 1, 5, 1000, 100 },                                          -- wolf 0.05% (below the notable threshold)
	[103] = { 0, 1, 200, 1000, 100 },                                        -- wolf 2%
}
-- npcLevels[id] = min * 10000 + max * 10 + rank: the ghost's own 33-34 beats QuestieDB's 30-31;
-- 99 is a "??" boss
Data.npcLevels = { [4] = 330340, [99] = 3 }
Data.npcTags = { [5] = "Cloak Seller" }
Data.npcs[5] = { "Vendor Bob", 2 }
-- spawns[npcId] = { uiMapID, count, x*10 * 1000 + y*10, ... }: Bob twice in Felwood
Data.spawns = { [5] = { 1448, 2, 400600, 410615 } }
-- sources[itemId] = { kind, id, a, b, c, ... }: the cloak is sold by Bob for 3s (unlimited),
-- skinned from the bear (50%, 1.5 at a time) and a reward of quest 77
Data.sources = { [104] = { 1, 5, 300, -1, 1, 2, 2, 5000, 800, 150, 9, 77, 0, 0, 0 } }
Data.quests = { [77] = { "Cloak Quest", 60 } }
HeadWow.db = { wishlist = {}, tooltipLines = 3, mobTooltipLines = 4, wishAlert = true }
-- the Map module's zone lookups, without the world map
HeadWow.Map = {
	ResolveZoneName = function(_, n) return ({ Felwood = 1448, Azshara = 1447, ["The Barrens"] = 1413 })[n] end,
	ResolveZone = function(self, idx) local n = HeadWowData.zones[idx]; return self:ResolveZoneName(n), 3 end,
}
