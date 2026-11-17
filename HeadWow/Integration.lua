-- Game integration: drop sources in item tooltips, Alt-click any item to open it in HeadWow.

local HW = HeadWow
local F = HW.F

---------------------------------------------------------------------------
-- Item tooltips
---------------------------------------------------------------------------

local function AddDropLines(tooltip, data)
	if not HW.db or not HW.db.tooltip then return end
	if tooltip == HeadWowDetailTooltip then return end -- the details pane shows the full table
	local itemID = data and data.id
	local row = itemID and HW:GetItem(itemID)
	if not row or not row[F.DROPS] then return end

	local drops = HW:GetDrops(itemID)
	if #drops == 0 then return end
	table.sort(drops, function(a, b) return (a.chance or 0) > (b.chance or 0) end)

	GameTooltip_AddBlankLineToTooltip(tooltip)
	GameTooltip_AddNormalLine(tooltip, "Dropped by (HeadWow)")
	for i = 1, math.min(HW.db.tooltipLines, #drops) do
		local d = drops[i]
		local zone = d.zones[1] and HW:GetZoneName(d.zones[1])
		local left = "  " .. d.name .. (zone and (" |cff808080" .. zone .. "|r") or "")
		GameTooltip_AddColoredDoubleLine(tooltip, left, HW:FormatChance(d.chance), HIGHLIGHT_FONT_COLOR, HW:GetChanceColor(d.chance))
	end
	if row[F.DROPS] > HW.db.tooltipLines then
		GameTooltip_AddDisabledLine(tooltip, string.format("  +%d more  ·  Alt-click to browse", row[F.DROPS] - HW.db.tooltipLines))
	end
end

---------------------------------------------------------------------------
-- Mob tooltips: what the mob drops that's worth knowing (wishlist items first)
---------------------------------------------------------------------------

local function NpcIDFromGUID(guid)
	if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

local function AddMobLines(tooltip, data)
	local db = HW.db
	if not db or not db.mobTooltip or tooltip ~= GameTooltip then return end
	local guid = data and data.guid
	if not guid then
		local _, unit = tooltip:GetUnit()
		guid = unit and UnitGUID(unit)
	end
	local npcID = NpcIDFromGUID(guid)
	if not npcID or not HW:GetNpc(npcID) then return end -- only NPCs the snapshot has drops for

	local lines, total = HW:GetNotableLoot(npcID, db.mobTooltipLines)
	if #lines == 0 then return end
	GameTooltip_AddBlankLineToTooltip(tooltip)
	for _, entry in ipairs(lines) do
		local icon = ("|T%s:14:14|t "):format(HW:GetItemIcon(entry.itemID))
		local left = icon .. (entry.wished and (HW:StarMarkup(12) .. " ") or "") .. HW:GetColoredItemName(entry.itemID)
		GameTooltip_AddColoredDoubleLine(tooltip, left, HW:FormatChance(entry.chance),
			HIGHLIGHT_FONT_COLOR, HW:GetChanceColor(entry.chance))
	end
	if total > #lines then
		GameTooltip_AddDisabledLine(tooltip, string.format("%d more drops in HeadWow", total - #lines))
	end
end

---------------------------------------------------------------------------
-- Alt-click any item (bags, chat links, loot, character sheet, quest rewards...)
---------------------------------------------------------------------------

local function OnModifiedItemClick(link)
	if not link or not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
	local itemID = tonumber(link:match("item:(%d+)"))
	if itemID and HW:GetItem(itemID) then
		HW:ShowItem(itemID)
	end
end

-- Mob tooltips need the drop data; load it a little after login, out of combat, rather than
-- with a hitch on the first mob you point at.
local PRELOAD_DELAY = 8

local function PreloadDrops()
	if not (HW.db.mobTooltip or HW.db.wishAlert and next(HW.db.wishlist)) then return end
	if InCombatLockdown() then
		C_Timer.After(PRELOAD_DELAY, PreloadDrops)
		return
	end
	HW:EnsureDrops()
end

function HW:OnLogin()
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddDropLines)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, AddMobLines)
	hooksecurefunc("HandleModifiedItemClick", OnModifiedItemClick)
	HW.Map:SetUpOpenMap()
	HW.EasyFind:Register()
	HW:RegisterSettings()
	HW:SetUpMinimapButton()
	C_Timer.After(PRELOAD_DELAY, PreloadDrops)
end
