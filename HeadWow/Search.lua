-- Item search and filtering over the bundled snapshot.

local HW = HeadWow
local Data = HeadWowData
local F = HW.F

local index -- { ids = {...}, names = {lowercased...} }, built lazily

local function BuildIndex()
	local ids, names = {}, {}
	for id, row in pairs(Data.items) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for i, id in ipairs(ids) do
		names[i] = Data.items[id][F.NAME]:lower()
	end
	index = { ids = ids, names = names }
end

-- Default filter state. Quality key -1 = unknown quality (item only known by name).
function HW:CreateDefaultFilters()
	return {
		qualities = { [-1] = true, [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true },
		sources = 0,         -- bitmask; 0 = any
		slot = nil,          -- slot index; nil = any
		dropsOnly = false,   -- only items with a drop table
		npcs = true,         -- also list matching NPCs
		wishOnly = false,    -- only wishlist items
		classUsable = false, -- only gear the player's class can use
		armorType = false,   -- only the player's armor type (cloth/leather/mail/plate)
		levelUsable = false, -- only items the player's level allows
		npcLevel = false,    -- only NPCs near the player's level
	}
end

function HW:IsDefaultFilters(f)
	for q = -1, 5 do
		if not f.qualities[q] then return false end
	end
	return f.sources == 0 and f.slot == nil and not f.dropsOnly and f.npcs and not f.wishOnly
		and not f.classUsable and not f.armorType and not f.levelUsable and not f.npcLevel
end

---------------------------------------------------------------------------
-- What the player's class can use (classic proficiencies, all trainable ones)
---------------------------------------------------------------------------

local WEAPON, ARMOR = 2, 4 -- item class IDs
-- Weapon subclasses: 0 1H axe, 1 2H axe, 2 bow, 3 gun, 4 1H mace, 5 2H mace, 6 polearm,
-- 7 1H sword, 8 2H sword, 10 staff, 13 fist, 14 misc, 15 dagger, 16 thrown, 18 crossbow,
-- 19 wand, 20 fishing pole.
local CLASS_WEAPONS = {
	WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
	PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
	HUNTER  = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
	ROGUE   = { 2, 3, 4, 7, 13, 15, 16, 18 },
	PRIEST  = { 4, 10, 15, 19 },
	SHAMAN  = { 0, 1, 4, 5, 10, 13, 15 },
	MAGE    = { 7, 10, 15, 19 },
	WARLOCK = { 7, 10, 15, 19 },
	DRUID   = { 4, 5, 10, 13, 15 },
}
-- Armor subclasses: 0 misc (rings, necks, trinkets, off-hands), 1 cloth, 2 leather, 3 mail,
-- 4 plate, 5 cosmetic, 6 shield, 7 libram, 8 idol, 9 totem. `best` is the heaviest armor
-- the class wears from level 40 (one lighter before).
local CLASS_ARMOR = {
	WARRIOR = { best = 4, shield = true },
	PALADIN = { best = 4, shield = true, relic = 7 },
	HUNTER  = { best = 3 },
	SHAMAN  = { best = 3, shield = true, relic = 9 },
	ROGUE   = { best = 2 },
	DRUID   = { best = 2, relic = 8 },
	PRIEST  = { best = 1 },
	MAGE    = { best = 1 },
	WARLOCK = { best = 1 },
}
local HEAVY_ARMOR_LEVEL = 40

local kinds = {} -- itemID -> { classID, subclassID, equipLoc } or false

local function ItemKind(itemID)
	local kind = kinds[itemID]
	if kind == nil then
		local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
		kind = classID and { classID, subclassID, equipLoc } or false
		kinds[itemID] = kind
	end
	return kind
end

-- The player's proficiencies, or nil for a class this doesn't know (then nothing is filtered).
local function PlayerGear()
	local _, classFile = UnitClass("player")
	local weapons, armor = CLASS_WEAPONS[classFile], CLASS_ARMOR[classFile]
	if not (weapons and armor) then return end
	local gear = { weapons = { [14] = true, [20] = true }, armor = armor, armorType = armor.best }
	for _, sub in ipairs(weapons) do gear.weapons[sub] = true end
	if armor.best >= 3 and UnitLevel("player") < HEAVY_ARMOR_LEVEL then gear.armorType = armor.best - 1 end
	return gear
end

local function UsableByClass(itemID, gear)
	local kind = ItemKind(itemID)
	if not kind then return true end
	local classID, sub = kind[1], kind[2]
	if classID == WEAPON then return gear.weapons[sub] == true end
	if classID ~= ARMOR then return true end
	if sub >= 1 and sub <= 4 then return sub <= gear.armorType or kind[3] == "INVTYPE_CLOAK" end
	if sub == 6 then return gear.armor.shield == true end
	if sub >= 7 and sub <= 9 then return gear.armor.relic == sub end
	return true
end

-- Armor that isn't the player's own type (cloth for a warrior, plate for a mage) is left out;
-- everything that isn't body armor passes.
local function IsOwnArmorType(itemID, gear)
	local kind = ItemKind(itemID)
	if not kind or kind[1] ~= ARMOR or kind[3] == "INVTYPE_CLOAK" then return true end
	local sub = kind[2]
	if sub < 1 or sub > 4 then return true end
	return sub == gear.armorType
end

local function PassesFilters(id, row, f, ctx)
	local q = row[F.QUALITY] or -1
	if not f.qualities[q] then return false end
	if f.sources ~= 0 and bit.band(row[F.SOURCE] or 0, f.sources) == 0 then return false end
	if f.slot and row[F.SLOT] ~= f.slot then return false end
	if f.dropsOnly and not row[F.DROPS] then return false end
	if f.wishOnly and not HW:IsWished(id) then return false end
	if f.levelUsable and (row[F.REQ] or 0) > ctx.level then return false end
	if ctx.gear then
		if f.classUsable and not UsableByClass(id, ctx.gear) then return false end
		if f.armorType and not IsOwnArmorType(id, ctx.gear) then return false end
	end
	return true
end

-- Keeps the NPCs whose level is within range of the player's (unknown levels are left out).
local NPC_LEVEL_RANGE = 5

function HW:FilterNpcsByLevel(npcIDs)
	local level = UnitLevel("player")
	local out = {}
	for _, npcID in ipairs(npcIDs) do
		local minLevel, maxLevel = self:GetNpcLevel(npcID)
		if minLevel and minLevel >= 0 and maxLevel >= level - NPC_LEVEL_RANGE and minLevel <= level + NPC_LEVEL_RANGE then
			out[#out + 1] = npcID
		end
	end
	return out
end

local function Tokenize(query)
	local tokens = {}
	for token in query:lower():gmatch("%S+") do
		tokens[#tokens + 1] = token
	end
	return tokens
end

-- Lower score = better match.
local function Score(name, query, firstToken)
	if name == query then return 0 end
	if name:sub(1, #query) == query then return 1 end
	if name:find("%f[%w]" .. firstToken:gsub("%p", "%%%0")) then return 2 end
	return 3
end

-- Returns a sorted array of item IDs matching query + filters.
function HW:Search(query, filters)
	if not index then BuildIndex() end
	query = strtrim(query or ""):lower()
	local tokens = Tokenize(query)
	local exactID = tonumber(query)

	local results, scores = {}, {}
	local items, ids, names = Data.items, index.ids, index.names
	local ctx = {
		level = UnitLevel("player"),
		gear = (filters.classUsable or filters.armorType) and PlayerGear() or nil,
	}

	for i = 1, #ids do
		local id = ids[i]
		local row = items[id]
		if PassesFilters(id, row, filters, ctx) then
			local name = names[i]
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
			elseif match then
				results[#results + 1] = id
				scores[id] = #tokens > 0 and Score(name, query, tokens[1]) or 0
			end
		end
	end

	table.sort(results, function(a, b)
		local sa, sb = scores[a], scores[b]
		if sa ~= sb then return sa < sb end
		local ra, rb = items[a], items[b]
		local qa, qb = ra[F.QUALITY] or -1, rb[F.QUALITY] or -1
		if qa ~= qb then return qa > qb end
		local la, lb = ra[F.ILVL] or 0, rb[F.ILVL] or 0
		if la ~= lb then return la > lb end
		return ra[F.NAME] < rb[F.NAME]
	end)

	return results
end

function HW:FindBestMatch(query)
	local results = self:Search(query, self:CreateDefaultFilters())
	return results[1]
end
