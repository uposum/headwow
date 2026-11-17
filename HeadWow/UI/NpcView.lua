-- NPC page: header (portrait, name, level, title, what a kill is worth), the 3D model with its
-- facts and locations on the left, and its loot table on the right (built from the item drop
-- tables), with what each drop adds to a kill's value.

local HW = HeadWow
local UI = HW.UI

local NpcView = {}
HW.NpcView = NpcView

local LEFT_WIDTH = 210
local MAX_LOCATIONS = 6
local ICONS = { zone = "Interface\\Icons\\INV_Misc_Map_01", camp = "Interface\\Icons\\Ability_Hunter_Pathfinding" }

local ui = {}
local npcID, fromItemID

---------------------------------------------------------------------------
-- Loot table
---------------------------------------------------------------------------

local function ItemName(entry)
	return (HW:IsWished(entry.itemID) and (HW:StarMarkup(12) .. " ") or "") .. HW:GetColoredItemName(entry.itemID)
end

local LOOT_SPEC = {
	columns = {
		{ title = "Item", icon = function(e) return "item", e.itemID end, text = ItemName,
		  sort = function(a, b) return (a.name or "") < (b.name or "") end },
		{ title = "Chance", width = 66, align = "RIGHT", text = function(e) return UI.ChanceText(e.chance) end,
		  sort = UI.ByNumber("chance"), descending = true },
		{ title = "Per kill", width = 70, align = "RIGHT",
		  text = function(e) return e.contrib and e.contrib > 0 and HW:FormatMoneyShort(e.contrib) or "|cff808080-|r" end,
		  sort = UI.ByNumber("contrib"), descending = true },
		{ title = "Kills", width = 60, align = "RIGHT", font = "GameFontDisableSmall",
		  text = function(e) return BreakUpLargeNumbers(e.samples or 0) end, sort = UI.ByNumber("samples"), descending = true },
	},
	sort = 2, descending = true, footer = true,
	onClick = function(e, button, row)
		if button == "RightButton" then HW:ShowItemContextMenu(row, e.itemID)
		elseif IsModifiedClick("CHATLINK") then HW:InsertItemLink(e.itemID)
		elseif IsModifiedClick("DRESSUP") then HW:WithItemLink(e.itemID, DressUpItemLink)
		else HW:ShowItem(e.itemID) end
	end,
	onEnter = function(e, row)
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(e.itemID)
		if e.contrib and e.contrib > 0 then
			GameTooltip_AddBlankLineToTooltip(GameTooltip)
			GameTooltip_AddColoredDoubleLine(GameTooltip, "Per kill (HeadWow)",
				("%s × %s%s"):format(HW:FormatChance(e.chance), HW:FormatMoneyShort(e.value), e.source == "ah" and " AH" or ""),
				NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR)
		end
		GameTooltip:Show()
	end,
}

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function CreateHeader(view)
	local header = CreateFrame("Frame", nil, view)
	header:SetPoint("TOPLEFT", 0, -2)
	header:SetPoint("TOPRIGHT", 0, -2)
	header:SetHeight(50)

	local portrait = header:CreateTexture(nil, "ARTWORK")
	portrait:SetSize(42, 42)
	portrait:SetPoint("TOPLEFT", 2, -2)
	header.Portrait = portrait

	local name = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	name:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 10, -1)
	name:SetPoint("RIGHT", -4, 0)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	header.Name = name

	local line1 = header:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	line1:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
	line1:SetPoint("RIGHT", -4, 0)
	line1:SetJustifyH("LEFT")
	line1:SetWordWrap(false)
	header.Line1 = line1

	local line2 = header:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	line2:SetPoint("TOPLEFT", line1, "BOTTOMLEFT", 0, -3)
	line2:SetPoint("RIGHT", -4, 0)
	line2:SetJustifyH("LEFT")
	line2:SetWordWrap(false)
	header.Line2 = line2
	return header
end

-- The 3D model: drag to turn, mouse wheel to zoom.
local function CreateModel(parent)
	local holder = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
	local model = CreateFrame("PlayerModel", nil, holder)
	model:SetPoint("TOPLEFT", 3, -3)
	model:SetPoint("BOTTOMRIGHT", -3, 3)
	model:EnableMouse(true)
	model:EnableMouseWheel(true)
	model.rotation, model.zoom = math.rad(15), 1
	model:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then self.dragX = GetCursorPosition() end
	end)
	model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
	model:SetScript("OnUpdate", function(self)
		if not self.dragX then return end
		local x = GetCursorPosition()
		self.rotation = self.rotation + (x - self.dragX) * 0.01
		self.dragX = x
		self:SetRotation(self.rotation)
	end)
	model:SetScript("OnMouseWheel", function(self, delta)
		self.zoom = math.max(0.5, math.min(2, self.zoom - delta * 0.1))
		self:SetCamDistanceScale(self.zoom)
	end)
	local hint = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOM", 0, 6)
	hint:SetText("Drag to turn  ·  wheel to zoom")
	holder.Model = model
	return holder
end

function NpcView:Create(host)
	local view = CreateFrame("Frame", nil, host)
	view:SetAllPoints()
	view:Hide()
	ui.View = view
	ui.Header = CreateHeader(view)

	-- Actions
	local wowhead = UI.Button(view, "Wowhead link", function() HW:ShowURL(HW:GetWowheadURL("npc", npcID)) end, 116)
	wowhead:SetPoint("BOTTOMRIGHT", 0, 0)
	local map = UI.Button(view, "Show on map", function() HW.Map:ShowNpc(npcID, ui.campMapID) end, 120)
	map:SetPoint("RIGHT", wowhead, "LEFT", -4, 0)
	UI.SetTooltip(map, "Show on map", function(tip)
		GameTooltip_AddNormalLine(tip, "Pins every spawn point (from QuestieDB), framed on its best camp's zone.", true)
	end)
	ui.MapButton = map
	local back = UI.Button(view, "", function() if fromItemID then HW:ShowItem(fromItemID) end end, 220)
	back:SetPoint("BOTTOMLEFT", 0, 0)
	ui.BackButton = back

	-- Left: locations at the bottom, the model filling the space above them
	local locations = UI.CreateCard(view, "Locations")
	locations:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", 0, 30)
	locations:SetWidth(LEFT_WIDTH)
	ui.Locations = locations

	local model = CreateModel(view)
	model:SetPoint("TOPLEFT", ui.Header, "BOTTOMLEFT", 0, -8)
	model:SetPoint("BOTTOMRIGHT", locations, "TOPRIGHT", 0, 8)
	ui.Model = model

	-- Right: loot
	local lootInset = CreateFrame("Frame", nil, view, "InsetFrameTemplate")
	lootInset:SetPoint("TOPLEFT", model, "TOPRIGHT", 8, 0)
	lootInset:SetPoint("BOTTOMRIGHT", wowhead, "TOPRIGHT", 0, 8)
	ui.Loot = UI.CreateTable(lootInset, LOOT_SPEC)
	ui.Loot:SetAllPoints()
end

---------------------------------------------------------------------------
-- Filling
---------------------------------------------------------------------------

-- Location rows: zones with their spawn counts (QuestieDB), else the snapshot's zone names.
-- Returns the rows and the mapID of the best camp (nil without spawn points).
local function LocationRows(id)
	local rows, campMapID = {}, nil
	local zones = HW:GetNpcSpawnZones(id)
	if zones then
		local list, best = {}, nil
		for mapID, z in pairs(zones) do
			list[#list + 1] = z
			local camp = HW:FindCamp(mapID, z.points)
			if camp and (not best or camp.count > best.camp.count) then best = { zone = z, camp = camp } end
		end
		table.sort(list, function(a, b) return a.count > b.count end)
		if best then
			campMapID = best.zone.mapID
			rows[#rows + 1] = {
				icon = ICONS.camp, text = string.format("Best camp: %.0f, %.0f", best.camp.x * 100, best.camp.y * 100),
				value = best.camp.count .. " spawns",
				onClick = function() HW.Map:ShowNpc(id, best.zone.mapID) end,
				onEnter = function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip_SetTitle(GameTooltip, "Best camp in " .. best.zone.name)
					GameTooltip_AddNormalLine(GameTooltip, string.format("The densest %d-yard area of its spawns: %d of the %d in the zone.",
						HW.CAMP_SIZE, best.camp.count, best.zone.count), true)
					GameTooltip_AddInstructionLine(GameTooltip, "Click: show on the map")
					GameTooltip:Show()
				end,
			}
		end
		for i, z in ipairs(list) do
			if i > MAX_LOCATIONS then
				rows[#rows + 1] = { text = string.format("+%d more zones", #list - MAX_LOCATIONS), dim = true }
				break
			end
			rows[#rows + 1] = {
				icon = ICONS.zone, text = z.name, value = tostring(z.count),
				onClick = #z.points > 0 and function() HW.Map:ShowNpc(id, z.mapID) end or nil,
			}
		end
	end
	if #rows == 0 then
		local _, zoneIdxs = HW:GetNpc(id)
		for _, zoneIdx in ipairs(zoneIdxs or {}) do
			rows[#rows + 1] = { icon = ICONS.zone, text = HW:GetZoneName(zoneIdx),
				onClick = function() HW.Map:ShowZones({ zoneIdx }) end }
		end
	end
	return rows, campMapID
end

function NpcView:Show(id, fromItem)
	npcID, fromItemID = id, fromItem
	ui.View:Show()

	local model = ui.Model.Model
	model:ClearModel()
	model:SetCreature(npcID)
	HW:LearnNpcDisplay(model, npcID) -- fills in the portrait if the game couldn't before
	model.rotation, model.zoom = math.rad(15), 1
	model:SetRotation(model.rotation)
	model:SetCamDistanceScale(1)

	self:Refresh()
end

function NpcView:Hide()
	if ui.View then ui.View:Hide() end
end

function NpcView:Refresh()
	if not npcID then return end
	local header = ui.Header
	HW:SetNpcPortrait(header.Portrait, npcID)
	header.Name:SetText(HW:GetNpcName(npcID))

	local level = HW:FormatNpcLevel(npcID)
	local subName = HW:GetNpcSubName(npcID)
	local line1 = {}
	line1[#line1 + 1] = level ~= "" and ((LEVEL or "Level") .. " " .. level) or "Level unknown"
	if subName then line1[#line1 + 1] = "<" .. subName .. ">" end
	local zoneText = HW:GetNpcZoneText(npcID, 3)
	if zoneText ~= "" then line1[#line1 + 1] = zoneText end
	header.Line1:SetText(table.concat(line1, "  ·  "))

	-- Loot with what each drop is worth per kill (same prices as gold farming)
	local loot = HW:GetNpcLoot(npcID)
	local cache, perKill = {}, 0
	local mode = HW.GoldFarm:PriceMode()
	for _, entry in ipairs(loot) do
		local item = HW:GetItem(entry.itemID)
		entry.name = item and item[HW.F.NAME] or ""
		if entry.chance and entry.chance > 0 then
			local value, source = HW.GoldFarm:ItemValue(entry.itemID, mode, cache)
			entry.value, entry.source = value, source
			entry.contrib = entry.chance / 100 * value
			perKill = perKill + entry.contrib
		end
	end
	local line2 = { string.format("Drops %d known item%s", #loot, #loot == 1 and "" or "s") }
	if perKill > 0 then line2[#line2 + 1] = "worth ~" .. HW:FormatMoneyShort(perKill) .. " per kill" end
	line2[#line2 + 1] = "ID " .. npcID
	header.Line2:SetText(table.concat(line2, "  ·  "))

	ui.Loot:SetData(loot, "No known loot for this NPC.")
	ui.Loot:SetFooter(#loot > 0
		and "From the item drop tables, so items whose table was cut short may be missing. Per kill: chance × vendor or steady AH price."
		or "")

	local rows, campMapID = LocationRows(npcID)
	ui.campMapID = campMapID
	ui.Locations:SetRows(rows, "Unknown")
	ui.MapButton:SetEnabled(#rows > 0)

	if fromItemID then
		ui.BackButton:SetText("< " .. HW:GetColoredItemName(fromItemID))
		ui.BackButton:Show()
	else
		ui.BackButton:Hide()
	end
end

function NpcView:OnWishlistChanged()
	if ui.View and ui.View:IsShown() then ui.Loot:RedrawRows() end
end
