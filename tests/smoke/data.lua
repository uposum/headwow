-- A tiny snapshot for the smoke test, in the generated data's row formats (see tools/convert.mjs),
-- and a QuestieDB stand-in with levels and spawn points.

local Data = HeadWowData
Data.snapshot = "2026-11-10T00:00:00Z"
Data.zones = { "Felwood", "Azshara", "The Barrens", "Nowhere" }
Data.slots = { "Chest", "One-Hand", "Finger" }
Data.npcs = { [1] = { "Felpaw Wolf", 1 }, [2] = { "Bear", 2, 1 }, [3] = { "Raptor", 3 }, [4] = { "Ghost", 4 } }
-- items[id] = { name, quality, itemLevel, requiredLevel, slotIdx, sourceMask, sellCopper, zoneIdx, from, dropRows }
Data.items = {
	[100] = { "Plate Chest", 2, 50, 45, 1, 1, 5000, nil, nil, 4 },
	[101] = { "Cloth Chest", 2, 50, 45, 1, 1, 100, nil, nil, 1 },
	[102] = { "Dagger", 2, 20, 15, 2, 1 },
	[103] = { "Shield", 3, 40, 35, 1, 3, 2000, 1, "Mister Graphed", 1 },
	[104] = { "Ring", 4, 62, 61, 3, 2, 300, 2, "Vendor Bob" },
	[200] = { "Junk", 0, 1, nil, nil, 1, 300, nil, nil, 1 },
}
-- drops[itemId] = { leftOut, npcId, chanceBasisPoints, samples, stack x100, ... }
Data.drops = {
	[100] = { 2, 1, 50, 1000, 100, 2, 100, 500, 100, 3, 2, 9000, 150, 4, 300, 10, 100 },
	[200] = { 0, 1, 4000, 1000, 250 },
	[101] = { 0, 1, 5, 1000, 100 },
	[103] = { 0, 1, 200, 1000, 100 },
}
Data.npcs[5] = { "Vendor Bob", 2 }
Data.npcLevels = { [1] = 400420, [5] = 300300, [6] = 3 }
Data.npcTags = { [5] = "Ring Seller" }
Data.zoneMaps = { [1] = 1448 }
-- sources[itemId] = { kind, id, a, b, c, ... }: every kind once
Data.sources = {
	[104] = { 1, 5, 300, -1, 1, 1, 2, 250, 3, 5, 9, 77, 0, 0, 0, 10, 88, 0, 0, 0 },
	[100] = { 2, 2, 5000, 800, 150, 3, 3, 120, 40, 100, 4, 900, 9600, 150000, 100, 5, 901, 9900, 59000, 200,
	          6, 902, 1500, 300, 100, 7, 3, 3, 290000, 333, 8, 104, 220, 1100, 100 },
}
Data.spawns = { [5] = { 1448, 2, 400600, 410615 }, [2] = { 1447, 1, 300300 } }
Data.objects = { [900] = { "Copper Vein", 3 }, [901] = { "Silverleaf", 1 }, [902] = { "Battered Chest", 2 } }
Data.quests = { [77] = { "A Ring for Bob", 60 } }
Data.spells = { [88] = { "Ring Making", 150 } }

local SPAWNS = {
	[1] = { [361] = { { 40, 60 }, { 41, 61 }, { 42, 62 } } },
	[2] = { [16] = { { 10, 20 } }, [361] = { { 50, 50 } } },
	[3] = { [17] = { { 1, 1 }, { 2, 2 }, { 3, 3 } } },
}
LibQuestieDB = { RequireContract = function() return true end, Npc = { Get = function(id, key)
	if key == "spawns" then return SPAWNS[id] end
	if key == "minLevel" then return ({ 40, 45, 15, 30 })[id] end
	if key == "maxLevel" then return ({ 42, 45, 16, 31 })[id] end
	if key == "rank" then return 0 end
	if key == "subName" then return id == 2 and "Bear Things" or nil end
end } }
