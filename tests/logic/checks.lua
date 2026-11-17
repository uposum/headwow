-- Checks for the data side: camps and where to farm, notable loot and the wishlist, search
-- filters, loot messages, gold farming values and the AH market rules.

local HW = HeadWow
local passed, failed = 0, {}
local function check(cond, msg)
	if cond then passed = passed + 1 else failed[#failed + 1] = msg end
end

-- Where to farm item 100
local sources, spots = HW.Farm:Get(100)
check(sources[1].npcID == 4, "sources best chance first (ghost 3%)")
-- Camps (default 3000x2000-yard map, 75-yard cells, 3x3 cells): Felwood's 3 wolves sit together,
-- the bear at 50,50 is far away -> camp = the wolves, 3 x 0.5% = 0.015. Azshara: bear 1%.
-- Barrens: 10 raptors on a diagonal from 1,1 to 10,10 -> the densest block holds 7 of them.
check(spots[1].name == "Felwood" and math.abs(spots[1].expected - 0.015) < 1e-9, "Felwood camp: 3 wolves, 0.015 per clear")
check(spots[1].spawns == 3 and spots[1].zoneSpawns == 4, "Felwood camp has 3 of the zone's 4 spawns")
check(#spots[1].npcs == 1 and spots[1].npcs[1].npcID == 1, "only the wolf is in the Felwood camp")
check(spots[2].name == "Azshara" and math.abs(spots[2].expected - 0.01) < 1e-9, "Azshara second")
check(spots[3].name == "The Barrens" and spots[3].spawns == 7 and math.abs(spots[3].expected - 0.0014) < 1e-9,
	"Barrens camp: 7 of 10 spread raptors")
check(#spots == 3, "the ghost's unresolvable zone adds no spot")
-- a mob spread over a zone: 500 spawns on a grid, only the ones in one 225-yard block count
local spread = {}
for i = 0, 24 do for j = 0, 19 do spread[#spread + 1] = { i / 25 + 0.01, j / 20 + 0.01 } end end
local camp = HW:FindCamp(9999, spread)
check(#spread == 500 and camp.count == 6, "500 spawns spread 120x100 yards apart -> camp of 6 (2x3)")
check(HW.Farm:FormatRate(0.025) == "1 per 40 clears", "rate text 1 per 40")
check(HW.Farm:FormatRate(0.35) == "0.35 per clear", "rate text 0.35")
check(HW.Farm:FormatRate(2.4, true) == "2.4", "short rate")
check(HW.Farm:FormatRate(0.025, true) == "1 in 40", "short rate small")

-- Notable loot for the wolf: junk (quality 0) left out, 0.05% below the threshold left out
local list, total = HW:GetNotableLoot(1, 4)
check(total == 4, "wolf drops 4 items in all")
check(#list == 2 and list[1].itemID == 103 and list[2].itemID == 100, "notable: shield 2% then plate 0.5%")
HW:SetWished(101, true)
list = HW:GetNotableLoot(1, 4)
check(list[1].itemID == 101 and list[1].wished, "wished item first even below the threshold")
check(#HW:GetWishedLoot(1) == 1, "wished loot of the wolf")
HW:SetWished(101, false)
check(#HW:GetWishedLoot(1) == 0, "wish cache cleared on change")

-- Search filters
local function ids(f) local r = HW:Search("", f); table.sort(r); return table.concat(r, ",") end
local f = HW:CreateDefaultFilters()
check(HW:IsDefaultFilters(f), "defaults are default")
f.classUsable = true
check(ids(f) == "100,101,102,103,104,106,200", "warrior: all but the wand")
f.armorType = true
check(ids(f) == "100,102,103,104,106,200", "warrior plate only: cloth chest out, cloak kept")
PLAYER_CLASS = "MAGE"
f.armorType = false
check(ids(f) == "101,102,104,105,106,200", "mage: no plate, no shield")
PLAYER_CLASS, PLAYER_LEVEL = "HUNTER", 30
f.classUsable, f.armorType = false, false
f.levelUsable = true
check(ids(f) == "102,104,105,200", "level 30: required level <= 30")
check(not HW:IsDefaultFilters(f), "non-default detected")
f = HW:CreateDefaultFilters(); f.wishOnly = true
HW:SetWished(104, true)
check(ids(f) == "104", "wishlist only")
HW:SetWished(104, false)

-- NPC level filter: wolf 50-52, bear 55, raptor 15-16, ghost 30-31
PLAYER_LEVEL = 30
local near = HW:FilterNpcsByLevel({ 1, 2, 3, 4 })
check(#near == 1 and near[1] == 4, "near level 30: only the ghost")
PLAYER_LEVEL = 18
near = HW:FilterNpcsByLevel({ 1, 2, 3, 4 })
check(#near == 1 and near[1] == 3, "near level 18: the raptor")

-- Loot message patterns (as Wishlist.lua builds them)
local link = "|cff1eff00|Hitem:100::::::::60:::::|h[Plate Chest]|h|r"
local pats = {}
for _, fmt in ipairs({ LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF }) do
	local p = fmt:gsub("[%(%)%.%[%]%*%+%-%?%^%$]", "%%%0")
	p = p:gsub("%%s", ".+"):gsub("%%d", "%%d+")
	pats[#pats + 1] = "^" .. p
end
local function own(text) for _, p in ipairs(pats) do if text:match(p) then return true end end return false end
check(own("You receive loot: " .. link .. "."), "own loot matches")
check(own("You receive loot: " .. link .. "x3."), "own multiple loot matches")
check(not own("Bob receives loot: " .. link .. "."), "someone else's loot does not")
check(("You receive loot: " .. link .. "."):match("|c.-|Hitem:.-|h.-|h|r") == link, "link extracted")
check(tonumber(link:match("|Hitem:(%d+)")) == 100, "item id parsed")

-- GUID parsing as in Integration.lua
local kind, _, _, _, _, id = strsplit("-", "Creature-0-4170-0-12-8959-0000ABCDEF")
check(kind == "Creature" and tonumber(id) == 8959, "creature GUID parsed")

-- Gold farming. Sell prices: plate 5000c, junk 300c, shield 2000c
HeadWowData.items[100][7] = 5000
HeadWowData.items[200][7] = 300
HeadWowData.items[103][7] = 2000
PLAYER_LEVEL = 60
-- Auctionator's API only (no readable database): the shield sells for 10000 on the AH
Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(_, item) return ({ [103] = 10000 })[item] end } } }
local gold = HW.GoldFarm:Build({ below = 0, elites = false, price = "best" })
local byId = {}
for _, e in ipairs(gold) do byId[e.npcID] = e end
-- wolf: plate 0.5% x 5000 = 25 + junk 40% x 300 = 120 + shield 2% x (10000 x 0.95) = 190 = 335
check(math.abs(byId[1].perKill - 335) < 1e-6, "wolf per kill 335c with the AH shield (5% cut)")
check(byId[1].spawns == 3 and math.abs(byId[1].perClear - 1005) < 1e-6, "wolf per clear = camp of 3")
check(byId[3].spawns == 7 and byId[3].zoneSpawns == 10, "raptor camp 7 of 10")
check(byId[1].top[1].itemID == 103 and byId[1].top[1].source == "ah", "the shield is the top contributor, from the AH")
check(byId[1].kills == 1000, "kills recorded = max samples")
check(math.abs(byId[2].perKill - 50) < 1e-6, "bear per kill 50c")
for _, e in ipairs(HW.GoldFarm:Build({ below = 0, elites = false, price = "vendor" })) do
	if e.npcID == 1 then check(math.abs(e.perKill - (25 + 120 + 40)) < 1e-6, "vendor mode: the shield at its 2000c vendor price") end
end
-- level filter: player 60, 10 below -> level 50 and under: wolf (50-52) out, raptor and ghost in
local below = {}
for _, e in ipairs(HW.GoldFarm:Build({ below = 10, elites = false, price = "best" })) do below[#below + 1] = e.npcID end
table.sort(below)
check(table.concat(below, ",") == "3,4", "10 below level 60: raptor and ghost only")
check(HW:FormatMoneyShort(335) == "|cffc7c7cf3s|r", "money short silver")
check(HW:FormatMoneyShort(123456) == "|cffffd70012.3g|r", "money short gold")
check(HW:FormatMoneyShort(45) == "|cffeda55f45c|r", "money short copper")

-- AH market check against a mock Auctionator database: today = day 100, scan days 95..100
GetTime = function() return 1000 end
time = os.time
local DAY0 = time() - 100 * 86400 - 3600
local db = {}
for i = 1, 20 do
	local h = {}
	for d = 95, 100 do h[tostring(d)] = 100 end
	db["9" .. i] = { h = h, l = {}, a = {}, m = 100 }
end
local function hist(days, price, available)
	local h, l, a = {}, {}, {}
	for _, d in ipairs(days) do h[tostring(d)] = price; l[tostring(d)] = price; a[tostring(d)] = available end
	return { h = h, l = l, a = a, m = price }
end
db["103"] = hist({ 96, 97, 98, 99, 100 }, 10000, 12) -- steady market
db["103"].l["98"] = 500000                           -- one silly day: the median ignores it
db["100"] = hist({ 90 }, 100000, 1)                  -- one listing, 10 days before the last scan
db["102"] = hist({ 99, 100 }, 50000, 1)              -- 2 of 6 scan days
Auctionator = { Constants = { SCAN_DAY_0 = DAY0 }, Database = { db = db },
	API = { v1 = { GetAuctionPriceByItemID = function(_, item) return db[tostring(item)] and db[tostring(item)].m end } } }
local m = HW:GetMarket(103)
check(m.reliable and m.price == 10000 and m.listed == 5 and m.scans == 6, "steady item: reliable, median 10000 despite a 50g day")
m = HW:GetMarket(100)
check(not m.reliable and m.reason:find("not listed in your last 10 days"), "stale single listing left out")
m = HW:GetMarket(102)
check(not m.reliable and m.reason:find("listed on only 2 of 6"), "rarely listed item left out")
check(HW:GetMarket(104) == nil, "never seen: no market")
check(HW:GetMarketPrice(103) == 10000 and HW:GetMarketPrice(100) == nil, "market price only for the reliable item")
for _, e in ipairs(HW.GoldFarm:Build({ below = 0, elites = false, price = "best" })) do
	if e.npcID == 2 then
		-- bear drops plate (item 100) at 1%: its lone 10g listing is ignored -> vendor 5000 -> 50c per kill
		check(math.abs(e.perKill - 50) < 1e-6 and #e.ignored == 1 and e.ignored[1].itemID == 100,
			"bear: the plate's lone 10g listing ignored, vendor price used")
	end
end

for _, msg in ipairs(failed) do print("FAIL " .. msg) end
print(("logic: %d checks passed, %d failed"):format(passed, #failed))
if #failed > 0 then error(#failed .. " logic checks failed", 0) end
