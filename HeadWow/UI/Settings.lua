-- HeadWow's page in the game's Settings panel (Options > AddOns > HeadWow).

local HW = HeadWow

local category

local function Checkbox(cat, key, name, tooltip, onChange)
	local setting = Settings.RegisterProxySetting(cat, "HEADWOW_" .. key:upper(), Settings.VarType.Boolean, name,
		HW.db[key] and true or false,
		function() return HW.db[key] and true or false end,
		function(value)
			HW.db[key] = value
			if onChange then onChange(value) end
		end)
	Settings.CreateCheckbox(cat, setting, tooltip)
	return setting
end

local function Slider(cat, key, name, tooltip, minValue, maxValue)
	local setting = Settings.RegisterProxySetting(cat, "HEADWOW_" .. key:upper(), Settings.VarType.Number, name,
		HW.db[key],
		function() return HW.db[key] end,
		function(value) HW.db[key] = math.floor(value + 0.5) end)
	local options = Settings.CreateSliderOptions(minValue, maxValue, 1)
	if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
	end
	Settings.CreateSlider(cat, setting, options, tooltip)
	return setting
end

local function Header(layout, text)
	if layout and CreateSettingsListSectionHeaderInitializer then
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
	end
end

local function Build()
	local cat, layout = Settings.RegisterVerticalLayoutCategory("HeadWow")

	Header(layout, "General")
	Checkbox(cat, "minimapButton", "Minimap button",
		"A HeadWow button on the minimap's edge: click to open, right-click for a menu, drag to move it.",
		function(on) HW:SetMinimapButtonShown(on) end)
	if layout and CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsButtonInitializer("Window", "Reset size and position",
			function() HW:ResetWindow() end, "Puts the HeadWow window back in the middle of the screen at its default size.", true))
	end

	Header(layout, "Tooltips")
	Checkbox(cat, "tooltip", "Drop sources in item tooltips",
		"Item tooltips list the NPCs that drop the item, best chance first.")
	Slider(cat, "tooltipLines", "Item tooltip lines", "How many NPCs item tooltips list.", 1, 10)
	Checkbox(cat, "mobTooltip", "Notable drops in mob tooltips",
		"Mob tooltips list what the mob drops that's worth knowing: wishlist items first, then uncommon and better.",
		function(on) if on then HW:EnsureDrops() end end)
	Slider(cat, "mobTooltipLines", "Mob tooltip lines", "How many drops mob tooltips list.", 1, 8)

	Header(layout, "World map")
	Checkbox(cat, "mapPins", "Tracked item on the map",
		"Pins where the item you last used \"Show on map\" for drops: the spawn points of the mobs, else their zones.",
		function() HW.Map:Refresh() end)
	Checkbox(cat, "wishMap", "Wishlist mobs on the map",
		"Pins every spawn of the mobs that drop a wishlist item (pink rings).",
		function() HW.Map:Refresh() end)

	Header(layout, "Wishlist")
	Checkbox(cat, "wishAlert", "Announce wishlist drops",
		"A raid warning and a chat message when you loot an item on your wishlist.")
	Checkbox(cat, "wishSound", "Play a sound with it", "The raid warning sound, with the announcement.")

	if layout and CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsButtonInitializer("Your wishlist", "Show",
			function() HW:ShowWishlist() end, "Opens HeadWow on your wishlist.", true))
	end

	Settings.RegisterAddOnCategory(cat)
	return cat
end

function HW:RegisterSettings()
	if category or not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then return end
	local ok, result = pcall(Build)
	if ok then
		category = result
	else
		self.settingsError = result
	end
end

function HW:OpenSettings()
	if category and Settings.OpenToCategory then
		Settings.OpenToCategory(category:GetID())
	else
		self:Print("The settings page isn't available" .. (self.settingsError and (": " .. tostring(self.settingsError)) or ".")
			.. " Use /hw help for the slash commands.")
	end
end
