--!strict
-- ReplicatedStorage > Shared > GameConfig (ModuleScript)
-- Game-wide settings: units, spawning rules, data store names, collision groups, controls and
-- camera tuning. Bike-specific numbers live in BikeDefinitions and PhysicsConfig.

local GameConfig = {}

GameConfig.GameName = "SURRON LIFE: WHEELIE CITY"

-- One stud is treated as 0.32 m. That keeps bikes in proportion with default-sized avatars
-- (a 5-stud avatar is about 1.6 m) and is the only real-world conversion used anywhere: speeds,
-- distances and scores all go through Utilities.studsToMetres / studsPerSecondToMph.
GameConfig.Units = {
	MetresPerStud = 0.32,
	SpeedUnit = "MPH", -- default for new players; "KMH" is available in settings
}

GameConfig.Data = {
	StoreName = "SurronLife_Profiles_v1",
	SchemaVersion = 1,
	AutosaveInterval = 120, -- seconds
	SessionLockTimeout = 600, -- a lock older than this is treated as abandoned by a crashed server
	LoadRetries = 5,
	LeaderboardStore = "SurronLife_LongestWheelie_v1",
	LeaderboardRefresh = 120,
}

GameConfig.Spawning = {
	Cooldown = 3, -- seconds between bike spawns per player
	RecoverCooldown = 2,
	ForwardOffset = 8, -- try to spawn this far in front of the character
	ClearanceSize = Vector3.new(4, 5, 8),
	AutoRecoverAfterCrash = 3, -- seconds before the bike is offered back after a crash
}

GameConfig.CollisionGroups = {
	Bikes = "Bikes",
	Riders = "Riders",
}

-- Default key bindings. Players can rebind these in Settings (stored per profile).
GameConfig.DefaultKeybinds = {
	Throttle = "W",
	Brake = "S",
	SteerLeft = "A",
	SteerRight = "D",
	LeanBack = "LeftShift",
	LeanForward = "LeftControl",
	RearBrake = "Space",
	Mount = "E",
	Recover = "R",
	Camera = "C",
	Headlight = "H",
	Garage = "G",
	Map = "M",
	Tricks = "T",
	Trick1 = "One",
	Trick2 = "Two",
	Trick3 = "Three",
	Trick4 = "Four",
	Trick5 = "Five",
}

GameConfig.Camera = {
	Modes = { "Chase", "Close", "FirstPerson", "Cinematic", "FreeLook" },
	Chase = { Distance = 12, Height = 4.2, LookHeight = 2.4, FovBase = 70, FovMax = 84 },
	Close = { Distance = 7.5, Height = 3.2, LookHeight = 2.2, FovBase = 72, FovMax = 86 },
	FirstPersonFov = 80,
	Cinematic = { Side = 11, Height = 2.2, Behind = 2 },
	FollowSmoothing = 0.12, -- seconds; lower = tighter follow
	WheelieLift = 1.6, -- how far the camera rises during a wheelie so the road ahead stays visible
	SpeedZoom = 4, -- extra distance at top speed
	CollisionPadding = 0.6,
}

GameConfig.Remote = {
	-- Unreliable bike state stream (steer, throttle, lean...) used for other players' visuals.
	StateSendRate = 10,
}

-- Player settings and the rules the server uses to validate them before saving.
GameConfig.DefaultSettings = {
	MasterVolume = 0.8,
	MotorVolume = 0.8,
	UiVolume = 0.7,
	CameraSensitivity = 1,
	CameraMode = "Chase",
	Graphics = "Auto", -- "Auto" | "Low" | "High"; Low turns off dust, trails and extra lights
	WheelieAssist = 1, -- multiplies the bike's balance assist
	ShowSpeedometer = true,
	UiScale = 1,
	MobileLayout = "Right", -- "Right" (throttle on the right) | "Left"
	Units = "MPH",
	TyreTrails = true,
	ReducedMotion = false,
	Keybinds = {},
}

GameConfig.SettingsSchema = {
	MasterVolume = { Type = "number", Min = 0, Max = 1 },
	MotorVolume = { Type = "number", Min = 0, Max = 1 },
	UiVolume = { Type = "number", Min = 0, Max = 1 },
	CameraSensitivity = { Type = "number", Min = 0.2, Max = 3 },
	CameraMode = { Type = "string", Options = { "Chase", "Close", "FirstPerson", "Cinematic", "FreeLook" } },
	Graphics = { Type = "string", Options = { "Auto", "Low", "High" } },
	WheelieAssist = { Type = "number", Min = 0, Max = 1 },
	ShowSpeedometer = { Type = "boolean" },
	UiScale = { Type = "number", Min = 0.75, Max = 1.3 },
	MobileLayout = { Type = "string", Options = { "Right", "Left" } },
	Units = { Type = "string", Options = { "MPH", "KMH" } },
	TyreTrails = { Type = "boolean" },
	ReducedMotion = { Type = "boolean" },
	Keybinds = { Type = "keybinds" },
}

GameConfig.Lighting = {
	ClockTime = 15.5,
}

return GameConfig
