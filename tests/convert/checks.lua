-- Checks on what tools/convert.mjs made of tests/convert/snapshot.mjs.

local D = HeadWowData
local passed, failed = 0, {}
local function check(cond, msg)
	if cond then passed = passed + 1 else failed[#failed + 1] = msg end
end
local function zoneIdx(name)
	for i, z in ipairs(D.zones) do if z == name then return i end end
end
local function has(list, ...)
	local want = { ... }
	for i = 1, #list - #want + 1 do
		local ok = true
		for k = 1, #want do if list[i + k - 1] ~= want[k] then ok = false break end end
		if ok and (i - 1) % 5 == 0 then return true end
	end
	return false
end

local elwynn, barrens = zoneIdx("Elwynn Forest"), zoneIdx("The Barrens")
check(D.snapshot == "2026-11-18T05:00:00.000Z", "snapshot date")
check(D.itemCount == 5, "5 items")

-- items[id] = { name, quality, itemLevel, requiredLevel, slotIdx, sourceMask, sellCopper, zoneIdx, from, dropRows, buyCopper }
local i1 = D.items[1]
check(i1[1] == "Boar Tusk" and i1[2] == 0 and i1[3] == 5 and i1[6] == 1 and i1[7] == 105 and i1[8] == elwynn, "listing item")
check(i1[10] == 30, "dropped by 30 NPCs in all")
local i2 = D.items[2]
check(i2[1] == "Courser Eye" and i2[2] == 1 and i2[3] == 22 and i2[4] == 20 and D.slots[i2[5]] == "Trinket" and i2[7] == 7,
	"a sitemap-only item filled in from its page")
check(i2[6] == 1, "its page says it drops")
local i3 = D.items[3]
check(i3[6] == 2 + 4 + 8 + 16 + 32 + 64 + 128, "every source bit from the page (vendor, quest, recipe, skinning, mining, container, fishing)")
check(i3[11] == 60, "vendor buy price")
check(D.items[4][6] == nil and D.items[4][10] == nil, "an item with nothing known")

-- drops[itemId] = { leftOut, npcId, bp, samples, stack x100, ... }
local r1 = D.drops[1]
check(r1[1] == 5 and #r1 == 1 + 25 * 4, "the best 25 droppers kept, the 5 under 0.05% beyond them left out")
check(r1[2] == 1001 and r1[3] == 1000 and r1[4] == 500 and r1[5] == 200, "the best dropper: 10%, 500 kills, 2 at a time")
check(r1[#r1 - 3] == 1025 and r1[#r1 - 2] == 1, "the 25th, at 0.01%, kept as one of the best 25")
check(D.drops[2][2] == 4018 and D.drops[2][3] == 8550, "the sitemap item's dropper")

-- sources[itemId] = { kind, id, a, b, c, ... }
local s3 = D.sources[3]
check(has(s3, 1, 151, 25, -1, 5), "sold by Brog for 25c, unlimited, 5 at a time")
check(has(s3, 2, 113, 7170, 35000, 150), "skinned from the boar, 71.7%, 1.5 at a time")
check(has(s3, 4, 1731, 9660, 150000, 100), "mined from a copper vein")
check(has(s3, 7, barrens, 0, 290000, 333), "fished in the Barrens")
check(has(s3, 8, 6307, 8, 1200, 100), "contained in an item")
check(has(s3, 9, 8, 0, 0, 0) and has(s3, 10, 2881, 0, 0, 0), "a quest reward and a recipe")
check(D.sources[1] == nil, "no other sources for the tusk")
check(#D.sources[5] == 30 * 5 and D.sources[5][#D.sources[5] - 3] == 5030, "every one of 30 vendors kept")

-- NPCs: every one a bundled table points at
check(D.npcs[113][1] == "Stonetusk Boar" and D.npcs[113][2] == elwynn, "the boar and its zone")
check(D.npcs[1001][1] == "NPC 1001", "an NPC the snapshot doesn't name")
check(D.npcs[1030] == nil, "an NPC only in left-out rows isn't bundled")
check(D.npcLevels[113] == 50060 and D.npcLevels[151] == 100100, "levels packed")
check(D.npcLevels[4018] == 3, "a boss without a level is ??")
check(D.npcTags[151] == "General Supplies", "vendor title")
-- npcReact[id] = (alliance + 2) * 4 + (horde + 2), 0 for an unknown part
check(D.npcReact[113] == 1 * 4 + 1, "the boar is hostile to both factions")
check(D.npcReact[151] == 3 * 4 + 1, "Brog is friendly to the Alliance, so hostile to the Horde he says nothing on")
check(D.npcReact[5001] == 1 * 4 + 3, "a Horde vendor silent on the Alliance is hostile to it")
check(D.npcReact[5002] == 2 * 4 + 0, "neutral to the Alliance, unknown to the Horde")
check(D.npcReact[5003] == nil and D.npcReact[4018] == nil, "no reaction known")
check(D.spawns[113][1] == 1429 and D.spawns[113][2] == 2 and D.spawns[113][3] == 469357 and D.spawns[113][4] == 474999,
	"spawns packed on the game's map ID (y 100 kept below 1000)")
check(D.zoneMaps[elwynn] == 1429 and D.zoneMaps[barrens] == nil, "zone map IDs where the snapshot has them")

-- names of what the sources point at
check(D.objects[1731][1] == "Copper Vein" and D.objects[1731][2] == barrens, "object and its zone")
check(D.quests[8][1] == "A Rogue's Deal" and D.quests[8][2] == 5, "quest")
check(D.spells[2881][1] == "Light Leather" and D.spells[2881][2] == 20, "recipe")

for _, msg in ipairs(failed) do print("FAIL " .. msg) end
print(("convert: %d checks passed, %d failed"):format(passed, #failed))
if #failed > 0 then error(#failed .. " convert checks failed", 0) end
