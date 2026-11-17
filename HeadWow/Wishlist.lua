-- Wishlist: items you're after. Starred items are marked in the browser, listed first in mob
-- tooltips, optionally shown on the map (the mobs that drop them), and announced when looted.

local HW = HeadWow

local Wish = {}
HW.Wishlist = Wish

local MIN_NOTABLE_CHANCE = 0.1 -- percent; below this a drop isn't worth a tooltip line (world drops)
local POOR = 0
local UNCOMMON = 2

---------------------------------------------------------------------------
-- Store
---------------------------------------------------------------------------

function HW:IsWished(itemID)
	return itemID ~= nil and self.db ~= nil and self.db.wishlist[itemID] == true
end

function HW:SetWished(itemID, wished)
	self.db.wishlist[itemID] = wished and true or nil
	Wish.lootCache = {}
	if self.Map and self.Map.WishlistChanged then self.Map:WishlistChanged() end
	if self.OnWishlistChanged then self:OnWishlistChanged() end
end

function HW:ToggleWished(itemID)
	local wished = not self:IsWished(itemID)
	self:SetWished(itemID, wished)
	self:Print((wished and "Added to" or "Removed from") .. " your wishlist: " .. self:GetColoredItemName(itemID))
end

function HW:GetWishlistCount()
	local n = 0
	for _ in pairs(self.db.wishlist) do n = n + 1 end
	return n
end

---------------------------------------------------------------------------
-- Star icon
---------------------------------------------------------------------------

local STAR_ATLASES = { "auctionhouse-icon-favorite", "PetJournal-FavoritesIcon" }
local STAR_FALLBACK = "Interface\\COMMON\\ReputationStar"
local starAtlas

local function StarAtlas()
	if starAtlas == nil then
		starAtlas = false
		for _, atlas in ipairs(STAR_ATLASES) do
			if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
				starAtlas = atlas
				break
			end
		end
	end
	return starAtlas
end

-- A star on a texture: bright when on, a faint outline-ish gray when off.
function HW:SetStarTexture(texture, on)
	local atlas = StarAtlas()
	if atlas then
		texture:SetAtlas(atlas)
	else
		texture:SetTexture(STAR_FALLBACK)
		texture:SetTexCoord(0, 0.5, 0, 0.5)
	end
	texture:SetDesaturated(not on)
	texture:SetAlpha(on and 1 or 0.4)
end

-- Inline star for text.
function HW:StarMarkup(size)
	size = size or 14
	local atlas = StarAtlas()
	if atlas then return ("|A:%s:%d:%d|a"):format(atlas, size, size) end
	return ("|T%s:%d:%d:0:0:32:32:0:16:0:16|t"):format(STAR_FALLBACK, size, size)
end

---------------------------------------------------------------------------
-- What an NPC drops that's worth knowing
---------------------------------------------------------------------------

Wish.lootCache = {}

-- Up to max entries { itemID, chance, wished } for an NPC: wishlist items first, then uncommon
-- and better, then the rest; poor items and near-zero world drops left out. Also returns how
-- many items the NPC drops in all.
function HW:GetNotableLoot(npcID, max)
	local loot = self:GetNpcLoot(npcID)
	local list = {}
	for _, entry in ipairs(loot) do
		local wished = self:IsWished(entry.itemID)
		local quality = self:GetItemQuality(entry.itemID) or 1
		if wished or (quality > POOR and (entry.chance or 0) >= MIN_NOTABLE_CHANCE) then
			list[#list + 1] = {
				itemID = entry.itemID, chance = entry.chance, wished = wished,
				rank = wished and 0 or (quality >= UNCOMMON and 1 or 2),
			}
		end
	end
	table.sort(list, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		return (a.chance or 0) > (b.chance or 0)
	end)
	if max then
		for i = #list, max + 1, -1 do list[i] = nil end
	end
	return list, #loot
end

-- The wishlist items an NPC drops: { itemID, chance }, best chance first (cached).
function HW:GetWishedLoot(npcID)
	if not next(self.db.wishlist) then return {} end
	local cached = Wish.lootCache[npcID]
	if cached then return cached end
	local out = {}
	for _, entry in ipairs(self:GetNpcLoot(npcID)) do
		if self:IsWished(entry.itemID) then out[#out + 1] = entry end
	end
	table.sort(out, function(a, b) return (a.chance or 0) > (b.chance or 0) end)
	Wish.lootCache[npcID] = out
	return out
end

-- Adds "<star> Item  2.1%" lines for an NPC's wishlist drops to a tooltip.
function HW:AddWishedLootLines(tooltip, npcID, skipItemID)
	local first = true
	for _, entry in ipairs(self:GetWishedLoot(npcID)) do
		if entry.itemID ~= skipItemID then
			if first then
				GameTooltip_AddBlankLineToTooltip(tooltip)
				first = false
			end
			GameTooltip_AddColoredDoubleLine(tooltip, self:StarMarkup(12) .. " " .. self:GetColoredItemName(entry.itemID),
				self:FormatChance(entry.chance), HIGHLIGHT_FONT_COLOR, self:GetChanceColor(entry.chance))
		end
	end
end

---------------------------------------------------------------------------
-- Loot alert
---------------------------------------------------------------------------

local selfPatterns

local function SelfLootPatterns()
	if selfPatterns then return selfPatterns end
	selfPatterns = {}
	local formats = { LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE }
	for _, fmt in ipairs(formats) do
		if type(fmt) == "string" then
			local pattern = fmt:gsub("[%(%)%.%[%]%*%+%-%?%^%$]", "%%%0")
			pattern = pattern:gsub("%%s", ".+"):gsub("%%d", "%%d+")
			selfPatterns[#selfPatterns + 1] = "^" .. pattern
		end
	end
	return selfPatterns
end

local function IsOwnLoot(text, guid)
	if guid and guid == UnitGUID("player") then return true end
	for _, pattern in ipairs(SelfLootPatterns()) do
		if text:match(pattern) then return true end
	end
	return false
end

local function OnLoot(_, _, text, _, _, _, _, _, _, _, _, _, _, guid)
	local db = HW.db
	if not (db and db.wishAlert and next(db.wishlist)) or type(text) ~= "string" then return end
	local ok, itemID = pcall(function() return tonumber(text:match("|Hitem:(%d+)")) end)
	if not ok or not itemID or not HW:IsWished(itemID) then return end
	if not IsOwnLoot(text, guid) then return end

	local link = text:match("|c.-|Hitem:.-|h.-|h|r") or HW:GetColoredItemName(itemID)
	if db.wishSound then PlaySound(SOUNDKIT.RAID_WARNING or 8959, "Master") end
	if RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, HW:StarMarkup(18) .. " Wishlist drop: " .. link, ChatTypeInfo.RAID_WARNING)
	end
	HW:Print(HW:StarMarkup(12) .. " Wishlist item looted: " .. link .. "  |cff808080(/hw wish to see the list)|r")
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_LOOT")
events:SetScript("OnEvent", OnLoot)
