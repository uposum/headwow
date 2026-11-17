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
-- drops[itemId] = { truncatedCount, npcId, chanceBasisPoints, samples, ... }
Data.drops = {
	[100] = { 0, 1, 50, 1000, 2, 100, 500, 3, 2, 9000, 4, 300, 10 }, -- wolf 0.5%, bear 1%, raptor 0.02%, ghost 3% (no spawns)
	[200] = { 0, 1, 4000, 1000 },                                       -- wolf junk 40%
	[101] = { 0, 1, 5, 1000 },                                          -- wolf 0.05% (below the notable threshold)
	[103] = { 0, 1, 200, 1000 },                                        -- wolf 2%
}
HeadWow.db = { wishlist = {}, tooltipLines = 3, mobTooltipLines = 4, wishAlert = true }
-- the Map module's zone lookups, without the world map
HeadWow.Map = {
	ResolveZoneName = function(_, n) return ({ Felwood = 1448, Azshara = 1447, ["The Barrens"] = 1413 })[n] end,
	ResolveZone = function(self, idx) local n = HeadWowData.zones[idx]; return self:ResolveZoneName(n), 3 end,
}
