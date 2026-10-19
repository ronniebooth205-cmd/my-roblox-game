--!strict
-- ReplicatedStorage > Shared > CustomisationConfig (ModuleScript)
-- Everything the garage sells or lets players change: paint colours and the parts they apply
-- to, visual options (bars, tyres, decals...), performance upgrades and controller tuning.
-- Prices and level locks are checked on the server (GarageService); the client only displays.

local CustomisationConfig = {}

-- Paint palette. Buying a colour unlocks it for every paint slot on every bike.
CustomisationConfig.Colours = {
	{ Name = "Black", Color = Color3.fromRGB(22, 22, 24), Price = 0, Level = 1 },
	{ Name = "Graphite", Color = Color3.fromRGB(58, 60, 64), Price = 0, Level = 1 },
	{ Name = "Silver", Color = Color3.fromRGB(176, 180, 186), Price = 0, Level = 1 },
	{ Name = "White", Color = Color3.fromRGB(236, 238, 240), Price = 0, Level = 1 },
	{ Name = "Volt Green", Color = Color3.fromRGB(57, 255, 136), Price = 0, Level = 1 },
	{ Name = "Race Red", Color = Color3.fromRGB(214, 36, 44), Price = 750, Level = 1 },
	{ Name = "Electric Blue", Color = Color3.fromRGB(30, 120, 255), Price = 750, Level = 1 },
	{ Name = "Hi-Vis Yellow", Color = Color3.fromRGB(240, 230, 40), Price = 900, Level = 3 },
	{ Name = "Burnt Orange", Color = Color3.fromRGB(240, 110, 30), Price = 900, Level = 3 },
	{ Name = "Purple Haze", Color = Color3.fromRGB(140, 70, 220), Price = 1200, Level = 5 },
	{ Name = "Army Green", Color = Color3.fromRGB(78, 92, 54), Price = 1200, Level = 5 },
	{ Name = "Gold", Color = Color3.fromRGB(212, 168, 60), Price = 2000, Level = 8 },
	{ Name = "Baby Blue", Color = Color3.fromRGB(130, 190, 240), Price = 1500, Level = 10 },
	{ Name = "Hot Pink", Color = Color3.fromRGB(255, 70, 170), Price = 1500, Level = 10 },
	{ Name = "Chrome", Color = Color3.fromRGB(210, 214, 220), Price = 5000, Level = 20, Material = "Metal" },
	{ Name = "Neon Lime", Color = Color3.fromRGB(150, 255, 40), Price = 12000, Level = 30, Material = "Neon" },
	{ Name = "Prestige Pearl", Color = Color3.fromRGB(245, 240, 255), Price = 30000, Level = 50, Material = "Glass" },
}

-- Paint slots, grouped into the garage tabs they appear under. `Default` is used when neither
-- the player nor the bike definition has picked a colour.
CustomisationConfig.PaintSlots = {
	{ Id = "Frame", Label = "Frame", Tab = "Body", Default = "Graphite" },
	{ Id = "Swingarm", Label = "Swingarm", Tab = "Body", Default = "Graphite" },
	{ Id = "Plastics", Label = "Plastics", Tab = "Body", Default = "Volt Green" },
	{ Id = "BatteryCover", Label = "Battery cover", Tab = "Body", Default = "Black" },
	{ Id = "Seat", Label = "Seat", Tab = "Body", Default = "Black" },
	{ Id = "Forks", Label = "Forks", Tab = "Body", Default = "Black" },
	{ Id = "Mudguards", Label = "Mudguards", Tab = "Body", Default = "Black" },
	{ Id = "Rims", Label = "Rims", Tab = "Wheels", Default = "Black" },
	{ Id = "Spokes", Label = "Spokes", Tab = "Wheels", Default = "Silver" },
	{ Id = "Bars", Label = "Handlebars", Tab = "Bars", Default = "Black" },
	{ Id = "Grips", Label = "Grips", Tab = "Bars", Default = "Black" },
	{ Id = "Stem", Label = "Stem", Tab = "Bars", Default = "Graphite" },
	{ Id = "BarPad", Label = "Bar pad", Tab = "Bars", Default = "Volt Green" },
	{ Id = "Chain", Label = "Chain / belt", Tab = "Extras", Default = "Graphite" },
	{ Id = "Headlight", Label = "Headlight tint", Tab = "Extras", Default = "White" },
}

-- Non-colour options. Each choice has a price and level; the first choice is always free.
CustomisationConfig.Options = {
	HandlebarStyle = {
		Label = "Bar style",
		Tab = "Bars",
		Choices = {
			{ Id = "Stock", Label = "Stock", Price = 0, Level = 1 },
			{ Id = "Riser", Label = "High riser", Price = 1500, Level = 3 },
			{ Id = "MX", Label = "MX bend", Price = 2500, Level = 8 },
			{ Id = "Flat", Label = "Flat tracker", Price = 2000, Level = 5 },
		},
	},
	TyreType = {
		Label = "Tyres",
		Tab = "Wheels",
		Choices = {
			{ Id = "Street", Label = "Street", Price = 0, Level = 1 },
			{ Id = "Mixed", Label = "Mixed terrain", Price = 2000, Level = 3 },
			{ Id = "OffRoad", Label = "Off-road knobbly", Price = 3500, Level = 6 },
		},
	},
	WheelSize = {
		Label = "Wheel size",
		Tab = "Wheels",
		Choices = {
			{ Id = "Stock", Label = "Stock", Price = 0, Level = 1 },
			{ Id = "Big", Label = "Big wheel kit", Price = 6000, Level = 12 },
		},
	},
	DiscStyle = {
		Label = "Brake discs",
		Tab = "Extras",
		Choices = {
			{ Id = "Solid", Label = "Solid", Price = 0, Level = 1 },
			{ Id = "Wave", Label = "Wave", Price = 1200, Level = 4 },
			{ Id = "Drilled", Label = "Drilled", Price = 1800, Level = 7 },
		},
	},
	SeatDesign = {
		Label = "Seat design",
		Tab = "Body",
		Choices = {
			{ Id = "Plain", Label = "Plain", Price = 0, Level = 1 },
			{ Id = "Ribbed", Label = "Ribbed", Price = 900, Level = 3 },
			{ Id = "Gripper", Label = "Gripper", Price = 1400, Level = 6 },
		},
	},
	Decal = {
		Label = "Decals",
		Tab = "Extras",
		Choices = {
			{ Id = "None", Label = "None", Price = 0, Level = 1 },
			{ Id = "Stripe", Label = "Race stripe", Price = 1500, Level = 3 },
			{ Id = "Bolt", Label = "Volt bolt", Price = 2500, Level = 8 },
			{ Id = "Checker", Label = "Chequered", Price = 4000, Level = 15 },
			{ Id = "Prestige", Label = "Prestige crown", Price = 25000, Level = 50 },
		},
	},
	Reflective = {
		Label = "Reflective trim",
		Tab = "Extras",
		Choices = {
			{ Id = "Off", Label = "Off", Price = 0, Level = 1 },
			{ Id = "On", Label = "Reflective", Price = 3000, Level = 10 },
		},
	},
}

-- Tyre grip multipliers by surface kind (see PhysicsConfig.Surfaces).
CustomisationConfig.TyreTypes = {
	Street = { Paved = 1.05, Grass = 0.85, Dirt = 0.8, Gravel = 0.8 },
	Mixed = { Paved = 1.0, Grass = 0.95, Dirt = 0.95, Gravel = 0.95 },
	OffRoad = { Paved = 0.92, Grass = 1.05, Dirt = 1.12, Gravel = 1.1 },
}

CustomisationConfig.WheelSizes = {
	Stock = 1.0,
	Big = 1.08,
}

-- Number plate rules. Plates are filtered by TextService on the server before anyone sees them.
CustomisationConfig.Plate = {
	MaxLength = 8,
	Default = "SUR R0N",
	Pattern = "^[%w ]+$",
}

-- Performance upgrades. Each level multiplies (or adds to) the stats listed. `Price` is the
-- cost of each level in order (LevelNames[1] is the stock part); bikes cap how many levels they
-- accept (BikeDefinitions MaxUpgradeLevel).
CustomisationConfig.Upgrades = {
	Battery = {
		Label = "Battery",
		Description = "Bigger pack: more top speed and range.",
		LevelNames = { "Standard", "Upgraded 72V", "Performance 80V", "Race 96V", "Prototype 110V" },
		Prices = { 4000, 11000, 26000, 52000 },
		LevelRequired = { 2, 6, 15, 25 },
		PerLevel = { TopSpeed = 0.06, BatterySeconds = 0.25 },
	},
	Motor = {
		Label = "Motor",
		Description = "Stronger motor: harder acceleration and easier wheelies.",
		LevelNames = { "Stock", "Stage 1", "Stage 2", "Stage 3", "Stage 4" },
		Prices = { 3500, 9500, 24000, 48000 },
		LevelRequired = { 2, 6, 15, 25 },
		PerLevel = { MaxAccel = 0.08, WheelieLift = 0.04 },
	},
	Controller = {
		Label = "Controller",
		Description = "Unlocks wider tuning ranges for throttle and torque.",
		LevelNames = { "Stock", "Sport", "Race", "Unlocked", "Factory" },
		Prices = { 3000, 8000, 20000, 40000 },
		LevelRequired = { 3, 8, 20, 30 },
		PerLevel = { MaxAccel = 0.03 },
	},
	Brakes = {
		Label = "Brakes",
		Description = "Stronger brakes and more rear-brake control in wheelies.",
		LevelNames = { "Stock", "4-piston", "Race", "Pro", "Factory" },
		Prices = { 2500, 7000, 18000, 36000 },
		LevelRequired = { 2, 5, 12, 25 },
		PerLevel = { BrakeDecel = 0.1, RearBrakePitch = 0.08 },
	},
	Suspension = {
		Label = "Suspension",
		Description = "Calmer landings and a steadier balance point.",
		LevelNames = { "Stock", "Adjustable", "Performance", "Factory", "Works" },
		Prices = { 3000, 8500, 21000, 42000 },
		LevelRequired = { 3, 7, 18, 28 },
		PerLevel = { PitchDamping = 0.06, CrashImpactSpeed = 0.06 },
	},
	Tyres = {
		Label = "Tyre compound",
		Description = "Stickier rubber everywhere.",
		LevelNames = { "Stock", "Sport", "Soft", "Race", "Qualifier" },
		Prices = { 2000, 6000, 15000, 30000 },
		LevelRequired = { 1, 5, 12, 22 },
		PerLevel = { Grip = 0.05 },
	},
}

CustomisationConfig.UpgradeOrder = { "Battery", "Motor", "Controller", "Brakes", "Suspension", "Tyres" }

-- Controller tuning sliders. The controller upgrade level decides the allowed range.
CustomisationConfig.Tuning = {
	ThrottleResponse = {
		Label = "Throttle response",
		Default = 1.0,
		Ranges = { { 0.8, 1.1 }, { 0.7, 1.25 }, { 0.6, 1.4 }, { 0.5, 1.6 }, { 0.5, 1.8 } },
	},
	TorqueDelivery = {
		Label = "Torque delivery",
		Default = 1.0,
		Ranges = { { 0.9, 1.0 }, { 0.85, 1.05 }, { 0.8, 1.1 }, { 0.75, 1.15 }, { 0.7, 1.2 } },
	},
	Regen = {
		Label = "Regen braking",
		Default = 0.5,
		Ranges = { { 0.3, 0.6 }, { 0.2, 0.8 }, { 0.1, 1.0 }, { 0, 1.0 }, { 0, 1.0 } },
	},
	SpeedLimiter = {
		Label = "Speed limiter",
		Default = 1.0,
		Ranges = { { 0.5, 1.0 }, { 0.4, 1.0 }, { 0.3, 1.0 }, { 0.2, 1.0 }, { 0.2, 1.0 } },
	},
	WheelieAssist = {
		Label = "Wheelie assist",
		Default = 1.0,
		Ranges = { { 0.5, 1.0 }, { 0.25, 1.0 }, { 0, 1.0 }, { 0, 1.2 }, { 0, 1.2 } },
	},
}

function CustomisationConfig.colour(name: string): any
	for _, c in CustomisationConfig.Colours do
		if c.Name == name then
			return c
		end
	end
	return nil
end

function CustomisationConfig.optionChoice(optionId: string, choiceId: string): any
	local option = (CustomisationConfig.Options :: any)[optionId]
	if not option then
		return nil
	end
	for _, choice in option.Choices do
		if choice.Id == choiceId then
			return choice
		end
	end
	return nil
end

function CustomisationConfig.paintSlot(slotId: string): any
	for _, slot in CustomisationConfig.PaintSlots do
		if slot.Id == slotId then
			return slot
		end
	end
	return nil
end

return CustomisationConfig
