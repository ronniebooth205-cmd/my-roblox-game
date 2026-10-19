--!strict
-- ReplicatedStorage > Shared > PhysicsConfig (ModuleScript)
-- Shared bike physics constants: chassis geometry, suspension, surface grip and the default
-- wheelie tuning. Each bike in BikeDefinitions can override the wheelie/handling numbers.
--
-- How the bike is simulated (see Controllers/BikeController): one invisible, massive "Chassis"
-- part carries all of the bike's mass. Every other part (body, wheels, rider) is massless, so
-- the centre of mass and inertia are exactly known. Each frame the owning client sphere-casts
-- under both wheels, works out spring, grip, drive and brake forces at the real contact
-- points, and hands the totals to one VectorForce and one Torque. Roblox's solver then
-- integrates them, so wheelies, squat and landings come out of the forces rather than an
-- animation. Units: studs, seconds, and mass-normalised forces (studs/s²).

local PhysicsConfig = {}

-- Gravity the bike feels, in studs/s². Roblox's default 196.2 makes a bike pendulum fall about
-- 2.4x faster than real life at our scale, which made wheelies twitchy and unplayable; an
-- upward force at the centre of mass brings the bike down to this value.
PhysicsConfig.BikeGravity = 70

PhysicsConfig.Geometry = {
	Wheelbase = 4.0, -- axle to axle
	WheelRadius = 1.05,
	TyreWidth = 0.42,
	MountDrop = 1.3, -- suspension mounts sit this far below the chassis centre (sets CoM height)
	SuspensionRest = 0.9, -- mount-to-axle distance with the spring fully extended
	SuspensionTravel = 0.75, -- compression before the bump stop
	StaticSag = 0.3, -- compression under the bike's own weight on both wheels
	CastLift = 0.4, -- sphere casts start this far above the mount so kerbs don't start inside them
	-- The invisible mass carrier. Its size sets the bike's inertia; 2.4 x 4.2 gives a pitch
	-- inertia close to a real bike-plus-rider (a smaller box made wheelies spin up far too fast).
	ChassisSize = Vector3.new(1.6, 2.4, 4.2),
	ChassisDensity = 10,
	HullSize = Vector3.new(0.9, 1.6, 3.6), -- massless collision box around the battery/body
	HullOffset = Vector3.new(0, -0.7, 0.1),
}

PhysicsConfig.Suspension = {
	DampingRatio = 0.55,
	BumpStopStiffness = 8, -- multiple of the spring rate past SuspensionTravel
}

PhysicsConfig.Grip = {
	LateralStiffness = 0.6, -- fraction of sideways slip removed per frame (lower = more drift)
	CombinedLimit = 1.1, -- friction circle allowance before forces are scaled back
	RollingResistance = 0.12,
	AeroDrag = 0.0012,
	StopSpeed = 1.2, -- below this the brakes hold the bike still
}

-- Grip multiplier per surface, keyed by Enum.Material name. Tyre types scale these again
-- (CustomisationConfig.TyreTypes) so off-road tyres really do help on dirt.
PhysicsConfig.Surfaces = {
	Asphalt = { Grip = 1.0, Kind = "Paved" },
	Concrete = { Grip = 0.95, Kind = "Paved" },
	Pavement = { Grip = 0.92, Kind = "Paved" },
	SmoothPlastic = { Grip = 0.9, Kind = "Paved" },
	Plastic = { Grip = 0.9, Kind = "Paved" },
	Brick = { Grip = 0.85, Kind = "Paved" },
	Cobblestone = { Grip = 0.8, Kind = "Paved" },
	Metal = { Grip = 0.75, Kind = "Paved" },
	DiamondPlate = { Grip = 0.8, Kind = "Paved" },
	Wood = { Grip = 0.8, Kind = "Paved" },
	WoodPlanks = { Grip = 0.8, Kind = "Paved" },
	Grass = { Grip = 0.7, Kind = "Grass" },
	LeafyGrass = { Grip = 0.68, Kind = "Grass" },
	Ground = { Grip = 0.75, Kind = "Dirt" },
	Mud = { Grip = 0.6, Kind = "Dirt" },
	Sand = { Grip = 0.55, Kind = "Dirt" },
	Pebble = { Grip = 0.7, Kind = "Gravel" },
	Slate = { Grip = 0.85, Kind = "Paved" },
	Rock = { Grip = 0.8, Kind = "Gravel" },
	Ice = { Grip = 0.25, Kind = "Paved" },
	Default = { Grip = 0.85, Kind = "Paved" },
}

-- Default handling and wheelie tuning. Bikes override any of these in BikeDefinitions.
-- Torques are expressed as multiples of G0 = mass * BikeGravity * (Wheelbase / 2), the torque
-- gravity puts on a flat bike about its rear axle, so values stay meaningful if the geometry
-- or gravity change.
PhysicsConfig.Handling = {
	TopSpeed = 45, -- studs/s (about 32 mph)
	MaxAccel = 28, -- studs/s² at full throttle from a standstill
	ReverseSpeed = 7,
	BrakeDecel = 55, -- front + rear combined at full input
	FrontBrakeShare = 0.65,
	RegenDecel = 5, -- deceleration when off the throttle (scaled by controller regen setting)
	Grip = 1.05,
	MaxSteerAngle = 32, -- degrees at walking pace
	SteerFalloffSpeed = 28, -- steering angle halves at this speed
	SteerResponse = 0.08, -- seconds to follow the steering input
	MaxLeanAngle = 42, -- degrees of visual/physical lean in turns
	YawGain = 9,
	RollStiffness = 60,
	RollDamping = 14,

	-- Wheelies. Tuned with tools/wheelie_sim.py, which replays this exact force model against a
	-- simulated keyboard player with 0.15-0.25 s reactions; see docs/PHYSICS.md.
	WheelieLift = 1.0, -- throttle torque at full lean-back, as a multiple of G0
	PassiveLiftShare = 0.1, -- share of WheelieLift available without leaning back
	DrivePitchShare = 0.4, -- share of the drive force's real pitch-up torque that is kept
	LeanShift = 0.12, -- rider weight shift torque per unit of lean input (× G0)
	RearBrakePitch = 0.9, -- nose-down torque from a full rear brake while wheelieing (× G0)
	IdealBalanceAngle = 46, -- degrees; centre of the HUD's green zone and of balance assist
	BalanceAssist = 0.8, -- 0..1 share of the tip-over instability cancelled near the ideal angle
	AssistWindow = 25, -- assist only works within this many degrees of the ideal angle
	PitchDamping = 10, -- per second, while on the back wheel
	GroundPitchDamping = 1.5,
	WheelieSteerFactor = 0.55, -- steering authority on one wheel
	ThrottleResponse = 0.15, -- seconds for the throttle to follow the input
	FallAngle = 80, -- loop out above this pitch
	WheelieThreshold = 6, -- degrees of pitch that count as a wheelie
	AirPitchControl = 0.5,
	CrashRollAngle = 72,
	CrashImpactSpeed = 55, -- sudden velocity change (studs/s in one frame) that throws the rider
}

PhysicsConfig.Battery = {
	DrainPerSecond = 0.004, -- share of a full battery used per second at full throttle
	RegenShare = 0.25, -- share of braking energy put back
	LowPowerThreshold = 0.05,
	LowPowerOutput = 0.4,
}

return PhysicsConfig
