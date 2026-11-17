-- Just enough of the game API for HeadWow's data modules (no frames).

StaticPopupDialogs, SlashCmdList = {}, {}
bit = { band = function(a, b) local r, p = 0, 1 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + p end a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2 end return r end }
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strsplit = function(sep, s) local out = {} for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end return table.unpack(out) end
unpack = table.unpack
BreakUpLargeNumbers = function(n) return tostring(n) end
ITEM_QUALITY_COLORS = {}
for q = 0, 5 do ITEM_QUALITY_COLORS[q] = { r = 1, g = 1, b = 1, hex = "|cffq" .. q } end
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end, HookScript = function() end } end
C_Timer = { After = function() end }
C_AddOns = { LoadAddOn = function() return true end }
C_Item = {
	GetItemIconByID = function() return 1 end,
	GetItemInfoInstant = function(id)
		-- 100 plate chest, 101 cloth chest, 102 dagger, 103 shield, 104 cloak (cloth), 105 wand, 106 ring
		local t = { [100] = { 4, 4, "INVTYPE_CHEST" }, [101] = { 4, 1, "INVTYPE_CHEST" }, [102] = { 2, 15, "INVTYPE_WEAPON" },
		            [103] = { 4, 6, "INVTYPE_SHIELD" }, [104] = { 4, 1, "INVTYPE_CLOAK" }, [105] = { 2, 19, "INVTYPE_RANGEDRIGHT" },
		            [106] = { 4, 0, "INVTYPE_FINGER" } }
		local k = t[id]
		if not k then return id, nil, nil, nil, nil, 15, 0 end
		return id, nil, nil, k[3], nil, k[1], k[2]
	end,
}
PLAYER_CLASS, PLAYER_LEVEL = "WARRIOR", 60
UnitClass = function() return "Warrior", PLAYER_CLASS end
UnitLevel = function() return PLAYER_LEVEL end
UnitGUID = function() return "Player-1-ABC" end
C_Map = {
	GetAreaInfo = function(id) return ({ [361] = "Felwood", [16] = "Azshara", [17] = "The Barrens" })[id] end,
	GetMapInfo = function(id) local name = ({ [1448] = "Felwood", [1447] = "Azshara", [1413] = "The Barrens" })[id]; return name and { name = name, mapType = 3 } end,
}
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
SPAWNS = {
	[1] = { [361] = { { 40, 60 }, { 41, 61 }, { 42, 62 } } }, -- 3 spawns Felwood
	[2] = { [16] = { { 10, 20 } }, [361] = { { 50, 50 } } },  -- 1 Azshara, 1 Felwood
	[3] = { [17] = { { 1, 1 }, { 2, 2 }, { 3, 3 }, { 4, 4 }, { 5, 5 }, { 6, 6 }, { 7, 7 }, { 8, 8 }, { 9, 9 }, { 10, 10 } } }, -- 10 Barrens
}
LibQuestieDB = { RequireContract = function() return true end, Npc = { Get = function(id, key)
	if key == "spawns" then return SPAWNS[id] end
	if key == "minLevel" then return ({ 50, 55, 15, 30 })[id] end
	if key == "maxLevel" then return ({ 52, 55, 16, 31 })[id] end
	if key == "rank" then return 0 end
end } }
