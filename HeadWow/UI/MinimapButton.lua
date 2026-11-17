-- Minimap button: left-click opens HeadWow, right-click for a menu, drag to move it around
-- the minimap's edge. Settings > HeadWow (or /hw minimap) turns it off.

local HW = HeadWow

local ICON = "Interface\\Icons\\INV_Misc_Book_09"
local RADIUS_PAD = 10     -- how far outside the minimap's edge the button's center sits
local button
local atan2 = math.atan2 or math.atan

-- Minimap shapes as other addons report them (GetMinimapShape): which quarters are round.
local ROUND_QUARTERS = {
	ROUND = { true, true, true, true },
	SQUARE = { false, false, false, false },
	["CORNER-TOPLEFT"] = { false, false, false, true },
	["CORNER-TOPRIGHT"] = { false, false, true, false },
	["CORNER-BOTTOMLEFT"] = { false, true, false, false },
	["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
	["SIDE-LEFT"] = { false, true, false, true },
	["SIDE-RIGHT"] = { true, false, true, false },
	["SIDE-TOP"] = { false, false, true, true },
	["SIDE-BOTTOM"] = { true, true, false, false },
	["TRICORNER-TOPLEFT"] = { false, true, true, true },
	["TRICORNER-TOPRIGHT"] = { true, false, true, true },
	["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
	["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function Place()
	local angle = math.rad(HW.db.minimapAngle or 220)
	local x, y = math.cos(angle), math.sin(angle)
	local quarter = 1
	if x < 0 then quarter = quarter + 1 end
	if y > 0 then quarter = quarter + 2 end
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	local quarters = ROUND_QUARTERS[shape] or ROUND_QUARTERS.ROUND
	local w = Minimap:GetWidth() / 2 + RADIUS_PAD
	local h = Minimap:GetHeight() / 2 + RADIUS_PAD
	if quarters[quarter] then
		x, y = x * w, y * h
	else
		-- square corner: push out to the edge
		local diagW, diagH = math.sqrt(2 * w * w) - RADIUS_PAD, math.sqrt(2 * h * h) - RADIUS_PAD
		x = math.max(-w, math.min(x * diagW, w))
		y = math.max(-h, math.min(y * diagH, h))
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	cx, cy = cx / scale, cy / scale
	HW.db.minimapAngle = math.deg(atan2(cy - my, cx - mx)) % 360
	Place()
end

local function ShowMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("HeadWow")
		root:CreateButton("Browse", function() HW:Open() end)
		root:CreateButton("Wishlist", function() HW:ShowWishlist() end)
		root:CreateButton("Gold farming", function() HW:ShowGoldFarm() end)
		root:CreateDivider()
		root:CreateCheckbox("Tracked item on the map",
			function() return HW.db.mapPins end,
			function() HW.Map:SetPinsShown(not HW.db.mapPins) end)
		root:CreateCheckbox("Wishlist mobs on the map",
			function() return HW.db.wishMap end,
			function() HW.Map:SetWishPinsShown(not HW.db.wishMap) end)
		root:CreateDivider()
		root:CreateButton("Settings", function() HW:OpenSettings() end)
		root:CreateButton("Hide this button", function()
			HW:SetMinimapButtonShown(false)
			HW:Print("Minimap button hidden. Turn it back on in the settings or with /hw minimap.")
		end)
	end)
end

local function Create()
	button = CreateFrame("Button", "HeadWowMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.Icon = icon

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function(self, mouse)
		GameTooltip:Hide()
		if mouse == "RightButton" then ShowMenu(self) else HW:Toggle() end
	end)
	button:SetScript("OnMouseDown", function() icon:SetTexCoord(0.12, 0.88, 0.12, 0.88) end)
	button:SetScript("OnMouseUp", function() icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end)
	button:SetScript("OnDragStart", function(self)
		self:LockHighlight()
		self:SetScript("OnUpdate", OnDragUpdate)
		GameTooltip:Hide()
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		self:UnlockHighlight()
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip_SetTitle(GameTooltip, "HeadWow")
		local tracked = HW.Map:GetActive()
		if tracked then GameTooltip_AddNormalLine(GameTooltip, "On the map: " .. HW:GetColoredItemName(tracked.itemID)) end
		local count = HW:GetWishlistCount()
		if count > 0 then GameTooltip_AddNormalLine(GameTooltip, "Wishlist: " .. count .. (count == 1 and " item" or " items")) end
		GameTooltip_AddBlankLineToTooltip(GameTooltip)
		GameTooltip_AddInstructionLine(GameTooltip, "Click: open  ·  Right-click: menu")
		GameTooltip_AddDisabledLine(GameTooltip, "Drag to move")
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	Place()
end

function HW:SetMinimapButtonShown(shown)
	self.db.minimapButton = shown and true or false
	if shown and not button then Create() end
	if button then button:SetShown(shown) end
end

function HW:SetUpMinimapButton()
	if not Minimap then return end
	if self.db.minimapButton then Create() end
end
