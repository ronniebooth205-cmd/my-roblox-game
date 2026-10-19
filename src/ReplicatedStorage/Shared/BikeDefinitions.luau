--!strict
-- ReplicatedStorage > Shared > BikeDefinitions (ModuleScript)
-- Every rideable bike. Add a new bike by adding an entry here: the builder, shop, garage,
-- physics and save system all read from this table. `Handling` overrides PhysicsConfig.Handling
-- and `Geometry` overrides PhysicsConfig.Geometry for that bike.
-- The names are fictional; they describe a style of bike, not a real product.

export type BikeDefinition = {
	Id: string,
	DisplayName: string,
	Tagline: string,
	Voltage: string,
	Order: number,
	Price: number,
	LevelRequired: number,
	MaxUpgradeLevel: number,
	BatterySeconds: number, -- full-throttle seconds on a full charge
	Handling: { [string]: number },
	Geometry: { [string]: number },
	DefaultColours: { [string]: string },
	Style: { FrameShape: string, BodyShape: string },
}

local BikeDefinitions: { [string]: BikeDefinition } = {
	StreetERide = {
		Id = "StreetERide",
		DisplayName = "Street E-Ride 60V",
		Tagline = "Light, friendly and easy to wheelie. Every rider starts here.",
		Voltage = "60V",
		Order = 1,
		Price = 0,
		LevelRequired = 1,
		MaxUpgradeLevel = 2,
		BatterySeconds = 300,
		Handling = {
			TopSpeed = 45,
			MaxAccel = 26,
			WheelieLift = 1.15,
			BalanceAssist = 0.9,
			PitchDamping = 10,
			ThrottleResponse = 0.2,
			IdealBalanceAngle = 44,
		},
		Geometry = {},
		DefaultColours = {
			Frame = "Graphite",
			Plastics = "Volt Green",
			Seat = "Black",
			Rims = "Black",
		},
		Style = { FrameShape = "Standard", BodyShape = "Standard" },
	},
	LightBeeStyle = {
		Id = "LightBeeStyle",
		DisplayName = "Light Bee Style 72V",
		Tagline = "More torque, more speed, quicker to pop up.",
		Voltage = "72V",
		Order = 2,
		Price = 12500,
		LevelRequired = 5,
		MaxUpgradeLevel = 3,
		BatterySeconds = 330,
		Handling = {
			TopSpeed = 66,
			MaxAccel = 34,
			WheelieLift = 1.3,
			BalanceAssist = 0.9,
			PitchDamping = 12,
			ThrottleResponse = 0.2,
			MaxSteerAngle = 30,
			IdealBalanceAngle = 46,
		},
		Geometry = {},
		DefaultColours = {
			Frame = "Silver",
			Plastics = "Black",
			Seat = "Black",
			Rims = "Gold",
		},
		Style = { FrameShape = "Standard", BodyShape = "Slim" },
	},
	UltraEMoto = {
		Id = "UltraEMoto",
		DisplayName = "Ultra E-Moto 80V",
		Tagline = "Brutal torque and a sensitive balance point. For confident riders.",
		Voltage = "80V",
		Order = 3,
		Price = 42000,
		LevelRequired = 10,
		MaxUpgradeLevel = 3,
		BatterySeconds = 360,
		Handling = {
			TopSpeed = 77,
			MaxAccel = 44,
			WheelieLift = 1.15,
			BalanceAssist = 0.9,
			PitchDamping = 14,
			ThrottleResponse = 0.12,
			RearBrakePitch = 1.0,
			MaxSteerAngle = 29,
			IdealBalanceAngle = 48,
		},
		Geometry = { WheelRadius = 1.1, Wheelbase = 4.2 },
		DefaultColours = {
			Frame = "Black",
			Plastics = "Electric Blue",
			Seat = "Black",
			Rims = "Black",
		},
		Style = { FrameShape = "Tall", BodyShape = "Bulky" },
	},
	MXElectricPro = {
		Id = "MXElectricPro",
		DisplayName = "MX Electric Pro",
		Tagline = "Race-bred power, strong rear brake, top-shelf suspension.",
		Voltage = "96V",
		Order = 4,
		Price = 95000,
		LevelRequired = 20,
		MaxUpgradeLevel = 4,
		BatterySeconds = 380,
		Handling = {
			TopSpeed = 84,
			MaxAccel = 50,
			WheelieLift = 1.0,
			BalanceAssist = 0.75,
			PitchDamping = 12,
			ThrottleResponse = 0.12,
			RearBrakePitch = 1.25,
			BrakeDecel = 65,
			MaxSteerAngle = 28,
			IdealBalanceAngle = 50,
			Grip = 1.12,
		},
		Geometry = { WheelRadius = 1.15, Wheelbase = 4.4, SuspensionTravel = 0.85 },
		DefaultColours = {
			Frame = "White",
			Plastics = "Race Red",
			Seat = "Black",
			Rims = "Black",
		},
		Style = { FrameShape = "MX", BodyShape = "MX" },
	},
}

local Module = {}

Module.Bikes = BikeDefinitions
Module.StarterBike = "StreetERide"

function Module.get(id: string): BikeDefinition?
	return BikeDefinitions[id]
end

function Module.list(): { BikeDefinition }
	local list = {}
	for _, def in BikeDefinitions do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

return Module
