--!strict
-- ReplicatedStorage > Shared > MapLayout (ModuleScript)
-- The city plan: roads, zones and key locations, in studs on the X/Z plane (Y is up, ground
-- level is 0). MapGenerator builds the world from this; MapService uses the zones for
-- exploration rewards; the M-key map draws the roads from it. Move a road here and every
-- system follows.
--
-- Rough plan (north is -Z):
--
--   North Road ──────────────────────────────────────────────
--   │ Town centre        │TownW│            │Fifth St │      │
--   High Street ─────────────────────────────────────────────  z = -300
--   │ Beacon Estate     │ Garage│ Bike Meet │Av│ Dockside     │
--   │                   │      (origin)     │  │ Industrial   │
--   South Road ──────────────────────────────────────────────  z = 240
--   │ Countryside (west) │                                    │
--   ═══════════════ The Strip (wheelie strip) ═══════════════  z = 600

export type Road = {
	Name: string,
	A: Vector2,
	B: Vector2,
	Width: number,
	Kind: string, -- "Main" | "Estate" | "Industrial" | "Strip" | "Country"
	SpeedBumps: boolean?,
	NoPavement: boolean?,
}

export type Zone = {
	Id: string,
	Name: string,
	Rects: { { Vector2 } }, -- list of {min, max} corners
	Colour: Color3,
}

local MapLayout = {}

MapLayout.GroundLevel = 0
MapLayout.RoadTop = 0.3
MapLayout.PavementTop = 0.75
MapLayout.PavementWidth = 8

-- Listed by priority: where two roads meet, the earlier one keeps a continuous surface.
MapLayout.Roads = {
	{ Name = "The Strip", A = Vector2.new(-1100, 600), B = Vector2.new(1100, 600), Width = 34, Kind = "Strip" },
	{ Name = "High Street", A = Vector2.new(-800, -300), B = Vector2.new(800, -300), Width = 28, Kind = "Main" },
	{ Name = "South Road", A = Vector2.new(-800, 240), B = Vector2.new(800, 240), Width = 28, Kind = "Main" },
	{ Name = "Kingsway", A = Vector2.new(180, -700), B = Vector2.new(180, 600), Width = 28, Kind = "Main" },
	{ Name = "Western Road", A = Vector2.new(-800, -700), B = Vector2.new(-800, 600), Width = 26, Kind = "Main" },
	{ Name = "Eastern Road", A = Vector2.new(800, -700), B = Vector2.new(800, 600), Width = 26, Kind = "Main" },
	{ Name = "North Road", A = Vector2.new(-800, -700), B = Vector2.new(800, -700), Width = 26, Kind = "Main" },
	{ Name = "Dock Road", A = Vector2.new(180, -90), B = Vector2.new(800, -90), Width = 36, Kind = "Industrial" },
	{ Name = "Fifth Street", A = Vector2.new(500, -700), B = Vector2.new(500, 240), Width = 26, Kind = "Industrial" },
	{ Name = "Beacon Way", A = Vector2.new(-800, 0), B = Vector2.new(-130, 0), Width = 22, Kind = "Estate", SpeedBumps = true },
	{ Name = "Meet Lane", A = Vector2.new(130, 0), B = Vector2.new(180, 0), Width = 24, Kind = "Main" },
	{ Name = "Hollow Lane", A = Vector2.new(-470, -300), B = Vector2.new(-470, 240), Width = 22, Kind = "Estate", SpeedBumps = true },
	{ Name = "Oak Close", A = Vector2.new(-800, -150), B = Vector2.new(-470, -150), Width = 20, Kind = "Estate", SpeedBumps = true },
	{ Name = "Crescent Drive", A = Vector2.new(-470, 120), B = Vector2.new(-215, 120), Width = 20, Kind = "Estate" },
	{ Name = "Market Street", A = Vector2.new(-200, -700), B = Vector2.new(-200, -300), Width = 22, Kind = "Main" },
	{ Name = "Old Mill Lane", A = Vector2.new(-1100, -300), B = Vector2.new(-1100, 600), Width = 20, Kind = "Country", NoPavement = true },
	{ Name = "Mill Link", A = Vector2.new(-1100, -300), B = Vector2.new(-800, -300), Width = 20, Kind = "Country", NoPavement = true },
} :: { Road }

MapLayout.Roundabouts = {
	{ Centre = Vector2.new(180, -300), IslandRadius = 9 },
	{ Centre = Vector2.new(180, 240), IslandRadius = 9 },
}

-- Junctions with traffic lights (client-side visuals cycle them).
MapLayout.TrafficLights = {
	Vector2.new(-200, -300),
	Vector2.new(500, -300),
	Vector2.new(-470, -300),
}

-- Zebra crossings: position and the axis of the road they cross ("X" = road runs along X).
MapLayout.Crossings = {
	{ Position = Vector2.new(-60, -300), Axis = "X" },
	{ Position = Vector2.new(320, -300), Axis = "X" },
	{ Position = Vector2.new(-620, -300), Axis = "X" },
}

MapLayout.Zones = {
	{ Id = "Meet", Name = "Volt Yard Bike Meet", Colour = Color3.fromRGB(57, 255, 136), Rects = { { Vector2.new(-200, -180), Vector2.new(166, 105) } } },
	{ Id = "Town", Name = "Town Centre", Colour = Color3.fromRGB(255, 200, 80), Rects = { { Vector2.new(-814, -714), Vector2.new(814, -260) } } },
	{ Id = "Estate", Name = "Beacon Estate", Colour = Color3.fromRGB(240, 130, 90), Rects = { { Vector2.new(-814, -260), Vector2.new(-200, 226) } } },
	{ Id = "Industrial", Name = "Dockside Industrial", Colour = Color3.fromRGB(120, 170, 255), Rects = { { Vector2.new(194, -260), Vector2.new(814, 226) } } },
	{ Id = "Park", Name = "Victoria Park", Colour = Color3.fromRGB(120, 220, 120), Rects = { { Vector2.new(-200, 105), Vector2.new(166, 226) } } },
	{ Id = "WheelieStrip", Name = "The Strip", Colour = Color3.fromRGB(255, 255, 255), Rects = { { Vector2.new(-1100, 570), Vector2.new(1100, 660) } } },
	{
		Id = "Countryside",
		Name = "Old Mill Countryside",
		Colour = Color3.fromRGB(150, 200, 90),
		Rects = { { Vector2.new(-1700, -720), Vector2.new(-820, 1100) }, { Vector2.new(-820, 660), Vector2.new(1100, 1100) } },
	},
} :: { Zone }

-- Key places, as world positions on the ground.
MapLayout.Places = {
	Spawn = Vector3.new(0, 0, 55),
	SpawnFacing = Vector3.new(0, 0, -1),
	-- Bike spawn bays at the meet; BikeService falls back to these when the spot in front of the
	-- player is blocked.
	BikeBays = {
		Vector3.new(-60, 0, 20),
		Vector3.new(-40, 0, 20),
		Vector3.new(-20, 0, 20),
		Vector3.new(20, 0, 20),
		Vector3.new(40, 0, 20),
		Vector3.new(60, 0, 20),
	},
	GarageBuilding = { Min = Vector2.new(-130, -178), Max = Vector2.new(-30, -104) },
	GarageTurntable = Vector3.new(-80, 0, -142),
	GarageCameraOffset = Vector3.new(9, 5.5, 13),
	MenuBike = Vector3.new(30, 0, -60),
	Leaderboard = Vector3.new(60, 0, -100),
	ChallengeBoard = Vector3.new(110, 0, -100),
	StripStart = Vector3.new(-1000, 0, 600),
	DirtTrackCentre = Vector3.new(-1380, 0, 180),
	StreamZ = 100,
}

-- Meeting points rideout leaders can pick.
MapLayout.MeetPoints = {
	{ Id = "Meet", Name = "Volt Yard", Position = Vector3.new(0, 0, 0) },
	{ Id = "Strip", Name = "The Strip", Position = Vector3.new(-1000, 0, 600) },
	{ Id = "Industrial", Name = "Dockside Yard", Position = Vector3.new(650, 0, 80) },
	{ Id = "Town", Name = "Town Square", Position = Vector3.new(0, 0, -420) },
	{ Id = "Country", Name = "Old Mill Tracks", Position = Vector3.new(-1380, 0, 180) },
}

function MapLayout.zoneAt(position: Vector3): Zone?
	-- Smaller, more specific zones are listed before the big catch-alls where it matters
	-- (Meet and Park sit inside the Estate/Industrial bands), so check them first.
	for _, id in { "Meet", "Park", "WheelieStrip" } do
		for _, zone in MapLayout.Zones do
			if zone.Id == id then
				for _, rect in zone.Rects do
					if position.X >= rect[1].X and position.X <= rect[2].X and position.Z >= rect[1].Y and position.Z <= rect[2].Y then
						return zone
					end
				end
			end
		end
	end
	for _, zone in MapLayout.Zones do
		for _, rect in zone.Rects do
			if position.X >= rect[1].X and position.X <= rect[2].X and position.Z >= rect[1].Y and position.Z <= rect[2].Y then
				return zone
			end
		end
	end
	return nil
end

return MapLayout
