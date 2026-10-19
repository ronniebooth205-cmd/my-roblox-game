--!strict
-- ServerScriptService > Map > MapGenerator (ModuleScript)
-- Builds the whole city into Workspace.Map from MapLayout: road network (with clean junctions,
-- pavements, markings, lights, speed bumps, drains), the bike meet and garage, the town
-- centre, the housing estate, the industrial estate, Victoria Park, the wheelie strip and the
-- countryside (terrain hills, stream, dirt track, fields). Deterministic: the same seed always
-- builds the same city. Runs once at server start (MapService) and yields between zones so it
-- never stalls the server for long.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local EconomyConfig = require(ReplicatedStorage.Shared.EconomyConfig)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local B = require(script.Parent.MapBuilders)

local MapGenerator = {}

local ROAD_TOP = MapLayout.RoadTop
local PAVE_TOP = MapLayout.PavementTop
local PAVE_W = MapLayout.PavementWidth
local ASPHALT = Color3.fromRGB(52, 54, 58)
local PAVEMENT = Color3.fromRGB(150, 150, 146)
local LINE_WHITE = Color3.fromRGB(235, 235, 230)
local LINE_YELLOW = Color3.fromRGB(240, 200, 40)
local GRASS = Color3.fromRGB(86, 128, 62)

type Road = MapLayout.Road
type Interval = { number }

local rng = Random.new(20261019)

------------------------------------------------------------------------ road geometry helpers

local function isAlongX(road: Road): boolean
	return road.A.Y == road.B.Y
end

-- Along-axis extent and the fixed cross coordinate of a straight road.
local function extent(road: Road): (number, number, number)
	if isAlongX(road) then
		return math.min(road.A.X, road.B.X), math.max(road.A.X, road.B.X), road.A.Y
	end
	return math.min(road.A.Y, road.B.Y), math.max(road.A.Y, road.B.Y), road.A.X
end

-- World position of a point `along` the road and `across` from its centreline.
local function at(road: Road, along: number, across: number, y: number): Vector3
	local _, _, c = extent(road)
	if isAlongX(road) then
		return Vector3.new(along, y, c + across)
	end
	return Vector3.new(c + across, y, along)
end

-- A box lying along the road between `from` and `to`, offset `across`.
local function strip(parent: Instance, road: Road, from: number, to: number, across: number, width: number, top: number, thickness: number, colour: Color3, material: Enum.Material, name: string, collide: boolean?): Part?
	if to - from < 0.2 then
		return nil
	end
	local centre = at(road, (from + to) / 2, across, top - thickness / 2)
	local size = if isAlongX(road) then Vector3.new(to - from, thickness, width) else Vector3.new(width, thickness, to - from)
	local p = B.part(parent, name, size, CFrame.new(centre), colour, material, collide)
	if collide == false then
		p.CastShadow = false
	end
	return p
end

local function subtract(a0: number, a1: number, gaps: { Interval }): { Interval }
	table.sort(gaps, function(x, y)
		return x[1] < y[1]
	end)
	local pieces = {}
	local cursor = a0
	for _, gap in gaps do
		if gap[2] > cursor and gap[1] < a1 then
			if gap[1] > cursor then
				table.insert(pieces, { cursor, gap[1] })
			end
			cursor = math.max(cursor, gap[2])
		end
	end
	if cursor < a1 then
		table.insert(pieces, { cursor, a1 })
	end
	return pieces
end

local function inGap(value: number, gaps: { Interval }, margin: number): boolean
	for _, gap in gaps do
		if value > gap[1] - margin and value < gap[2] + margin then
			return true
		end
	end
	return false
end

------------------------------------------------------------------------ roads

local function buildRoads(parent: Instance)
	local folder = B.model(parent, "Roads")
	local roads = MapLayout.Roads
	for i, road in roads do
		local roadModel = B.model(folder, road.Name)
		local a0, a1, c = extent(road)
		local w = road.Width
		local surfaceGaps: { Interval } = {}
		local markingGaps: { Interval } = {}
		local paveGaps: { [number]: { Interval } } = { [-1] = {}, [1] = {} }

		for j, other in roads do
			if j ~= i and isAlongX(other) ~= isAlongX(road) then
				local b0, b1, oc = extent(other)
				local ow = other.Width
				-- Do the two centrelines meet (allowing for road widths at T-junctions)?
				if oc >= a0 - ow / 2 and oc <= a1 + ow / 2 and c >= b0 - w / 2 and c <= b1 + w / 2 then
					if j < i then
						table.insert(surfaceGaps, { oc - ow / 2, oc + ow / 2 })
					end
					table.insert(markingGaps, { oc - ow / 2 - 3, oc + ow / 2 + 3 })
					for _, side in { -1, 1 } do
						local sideCoord = c + side * (w / 2 + PAVE_W / 2)
						if sideCoord >= b0 - 1 and sideCoord <= b1 + 1 then
							local extra = if j < i then PAVE_W else 0
							table.insert(paveGaps[side], { oc - ow / 2 - extra, oc + ow / 2 + extra })
						end
					end
				end
			end
		end
		-- Roundabout islands sit in the middle of junctions; keep markings clear of them.
		for _, roundabout in MapLayout.Roundabouts do
			local rc = if isAlongX(road) then roundabout.Centre.X else roundabout.Centre.Y
			local rcCross = if isAlongX(road) then roundabout.Centre.Y else roundabout.Centre.X
			if rcCross == c then
				table.insert(markingGaps, { rc - 30, rc + 30 })
			end
		end

		local surfaceColour = if road.Kind == "Strip" then Color3.fromRGB(44, 46, 50) else ASPHALT
		for _, piece in subtract(a0, a1, surfaceGaps) do
			strip(roadModel, road, piece[1], piece[2], 0, w, ROAD_TOP, 1, surfaceColour, Enum.Material.Asphalt, "Surface")
		end

		if not road.NoPavement then
			for _, side in { -1, 1 } do
				for _, piece in subtract(a0 - w / 2 - PAVE_W, a1 + w / 2 + PAVE_W, paveGaps[side]) do
					strip(roadModel, road, piece[1], piece[2], side * (w / 2 + PAVE_W / 2), PAVE_W, PAVE_TOP, 1.4, PAVEMENT, Enum.Material.Pavement, "Pavement")
					strip(roadModel, road, piece[1], piece[2], side * (w / 2 + 0.25), 0.5, PAVE_TOP + 0.02, 0.5, Color3.fromRGB(175, 175, 170), Enum.Material.Concrete, "Kerb", false)
				end
			end
		end

		-- Markings: edge lines everywhere, dashed centre on two-lane roads.
		local markTop = ROAD_TOP + 0.03
		for _, piece in subtract(a0, a1, markingGaps) do
			for _, side in { -1, 1 } do
				strip(roadModel, road, piece[1], piece[2], side * (w / 2 - 1.4), 0.4, markTop, 0.06, LINE_WHITE, Enum.Material.SmoothPlastic, "EdgeLine", false)
			end
			if road.Kind ~= "Estate" then
				local dash = if road.Kind == "Strip" then 14 else 10
				local s = piece[1] + 4
				while s + dash < piece[2] - 4 do
					strip(roadModel, road, s, s + dash, 0, 0.5, markTop, 0.06, LINE_WHITE, Enum.Material.SmoothPlastic, "CentreDash", false)
					s += dash * 2
				end
			end
		end

		-- Street furniture along the road.
		local lampSpacing = if road.Kind == "Country" then math.huge else 110
		local s = a0 + 30
		local side = 1
		while s < a1 - 20 do
			if not inGap(s, markingGaps, 6) then
				local pos = at(road, s, side * (w / 2 + PAVE_W - 1.2), PAVE_TOP)
				local facing = at(road, s, 0, PAVE_TOP) - pos
				B.lamp(roadModel, pos, facing.Unit)
			end
			s += lampSpacing
			side = -side
		end
		-- Drains near the kerb and the odd manhole cover.
		s = a0 + 18
		while s < a1 - 10 do
			if not inGap(s, markingGaps, 4) then
				local drain = strip(roadModel, road, s, s + 1.6, (w / 2 - 0.9), 0.9, ROAD_TOP + 0.02, 0.06, Color3.fromRGB(30, 30, 30), Enum.Material.DiamondPlate, "Drain", false)
				if drain and rng:NextNumber() < 0.35 then
					local manhole = B.cylinder(roadModel, "Manhole", 0.08, 1.3, CFrame.new(at(road, s + 6, -w / 4, ROAD_TOP + 0.03)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 70, 72), Enum.Material.DiamondPlate, false)
					manhole.CastShadow = false
				end
			end
			s += 70
		end
		-- Estate speed bumps.
		if road.SpeedBumps then
			s = a0 + 60
			while s < a1 - 40 do
				if not inGap(s, markingGaps, 10) then
					local centre = at(road, s, 0, ROAD_TOP - 1.15)
					local rot = if isAlongX(road) then CFrame.Angles(0, math.rad(90), 0) else CFrame.identity
					local bump = B.cylinder(roadModel, "SpeedBump", w - 3, 1.5, CFrame.new(centre) * rot, ASPHALT:Lerp(Color3.new(0, 0, 0), 0.1), Enum.Material.Asphalt)
					bump.CastShadow = false
					for k = -2, 2 do
						strip(roadModel, road, s - 0.3, s + 0.3, k * (w / 6), 1.2, ROAD_TOP + 0.4, 0.05, LINE_WHITE, Enum.Material.SmoothPlastic, "BumpMark", false)
					end
				end
				s += 120
			end
		end
		-- Street name sign at the start.
		B.streetSign(roadModel, at(road, a0 + w + 6, (w / 2 + PAVE_W - 2), PAVE_TOP), at(road, a0 + 50, 0, PAVE_TOP) - at(road, a0 + w + 6, 0, PAVE_TOP), road.Name)
		if i % 4 == 0 then
			task.wait()
		end
	end

	-- Roundabouts: raised planted island with a kerb ring and keep-left bollard.
	for _, roundabout in MapLayout.Roundabouts do
		local centre = Vector3.new(roundabout.Centre.X, 0, roundabout.Centre.Y)
		local r = roundabout.IslandRadius
		B.cylinder(folder, "RoundaboutKerb", 0.9, r + 0.6, CFrame.new(centre + Vector3.new(0, ROAD_TOP + 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 200, 195), Enum.Material.Concrete)
		B.cylinder(folder, "RoundaboutIsland", 1.0, r, CFrame.new(centre + Vector3.new(0, ROAD_TOP + 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), GRASS, Enum.Material.Grass)
		B.tree(folder, centre + Vector3.new(0, ROAD_TOP + 0.9, 0), 0.8, rng)
	end

	-- Traffic lights on all four corners of signalised junctions.
	for _, junction in MapLayout.TrafficLights do
		for _, corner in { Vector2.new(1, 1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.new(-1, -1) } do
			local pos = Vector3.new(junction.X + corner.X * 18, PAVE_TOP, junction.Y + corner.Y * 18)
			local group = if corner.X * corner.Y > 0 then "X" else "Z"
			local facing = if group == "X" then Vector3.new(-corner.X, 0, 0) else Vector3.new(0, 0, -corner.Y)
			B.trafficLight(folder, pos, facing, group)
		end
	end

	-- Zebra crossings with Belisha beacons.
	for _, crossing in MapLayout.Crossings do
		local width = 28
		for k = -6, 6 do
			local offset = k * 2.2
			local pos = if crossing.Axis == "X" then Vector3.new(crossing.Position.X, ROAD_TOP + 0.02, crossing.Position.Y + offset) else Vector3.new(crossing.Position.X + offset, ROAD_TOP + 0.02, crossing.Position.Y)
			local size = if crossing.Axis == "X" then Vector3.new(6, 0.06, 1.1) else Vector3.new(1.1, 0.06, 6)
			if k % 2 == 0 then
				local stripe = B.part(folder, "ZebraStripe", size, CFrame.new(pos), LINE_WHITE, Enum.Material.SmoothPlastic, false)
				stripe.CastShadow = false
			end
		end
		for _, side in { -1, 1 } do
			local pos = if crossing.Axis == "X" then Vector3.new(crossing.Position.X + 4, PAVE_TOP, crossing.Position.Y + side * (width / 2 + 2)) else Vector3.new(crossing.Position.X + side * (width / 2 + 2), PAVE_TOP, crossing.Position.Y + 4)
			B.belisha(folder, pos)
		end
	end
end

------------------------------------------------------------------------ zones

local function buildGround(parent: Instance)
	-- Grass under the city. The countryside around it is Terrain (buildCountryside).
	local ground = B.part(parent, "CityGround", Vector3.new(1640, 4, 1380), CFrame.new(0, -2, -30), GRASS, Enum.Material.Grass)
	ground.CastShadow = false
end

local function buildMeet(parent: Instance)
	local meet = B.model(parent, "Meet")
	local volt = B.Palette.Volt
	-- Car park surface with a kerbed edge.
	B.part(meet, "CarPark", Vector3.new(260, 1, 200), CFrame.new(0, ROAD_TOP - 0.5, 0), Color3.fromRGB(48, 50, 54), Enum.Material.Asphalt)
	for _, z in { -100.5, 100.5 } do
		B.part(meet, "Kerb", Vector3.new(260, 0.8, 1), CFrame.new(0, ROAD_TOP + 0.2, z), Color3.fromRGB(190, 190, 186), Enum.Material.Concrete)
	end
	-- Parking bays for bikes (north and south rows) and a big painted VOLT YARD logo area.
	for x = -110, 110, 10 do
		for _, z in { -88, 88 } do
			local line = B.part(meet, "BayLine", Vector3.new(0.4, 0.05, 14), CFrame.new(x, ROAD_TOP + 0.03, z), LINE_WHITE, Enum.Material.SmoothPlastic, false)
			line.CastShadow = false
		end
	end
	local logo = B.part(meet, "Logo", Vector3.new(60, 0.05, 20), CFrame.new(0, ROAD_TOP + 0.03, -20), Color3.fromRGB(48, 50, 54), Enum.Material.SmoothPlastic, false)
	B.label(logo, Enum.NormalId.Top, "VOLT YARD", volt)

	-- Spawn pad.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MeetSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 0.4, 14)
	spawn.CFrame = CFrame.new(MapLayout.Places.Spawn + Vector3.new(0, ROAD_TOP + 0.2, 0))
	spawn.Color = Color3.fromRGB(30, 32, 36)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = meet
	local ring = B.part(meet, "SpawnRing", Vector3.new(0.1, 15, 15), CFrame.new(MapLayout.Places.Spawn + Vector3.new(0, ROAD_TOP + 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90)), volt, Enum.Material.Neon, false)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.4

	-- Bike bays where BikeService spawns bikes when the spot in front of a player is blocked.
	for _, bay in MapLayout.Places.BikeBays do
		local pad = B.part(meet, "BikeBay", Vector3.new(6, 0.05, 10), CFrame.new(bay + Vector3.new(0, ROAD_TOP + 0.03, 0)), volt, Enum.Material.Neon, false)
		pad.Transparency = 0.7
	end

	-- The garage / customs shop.
	local g = MapLayout.Places.GarageBuilding
	local gw, gd = g.Max.X - g.Min.X, g.Max.Y - g.Min.Y
	local gc = Vector3.new((g.Min.X + g.Max.X) / 2, 0, (g.Min.Y + g.Max.Y) / 2)
	local garage = B.model(meet, "Garage")
	local wallColour = Color3.fromRGB(34, 36, 40)
	local height = 26
	B.part(garage, "Floor", Vector3.new(gw, 1, gd), CFrame.new(gc + Vector3.new(0, ROAD_TOP - 0.45, 0)), Color3.fromRGB(70, 72, 76), Enum.Material.Concrete)
	B.part(garage, "BackWall", Vector3.new(gw, height, 2), CFrame.new(gc + Vector3.new(0, height / 2, -gd / 2 + 1)), wallColour, Enum.Material.Metal)
	for _, side in { -1, 1 } do
		B.part(garage, "SideWall", Vector3.new(2, height, gd), CFrame.new(gc + Vector3.new(side * (gw / 2 - 1), height / 2, 0)), wallColour, Enum.Material.Metal)
		-- Front wall sections either side of the big open door.
		B.part(garage, "FrontWall", Vector3.new(22, height, 2), CFrame.new(gc + Vector3.new(side * (gw / 2 - 11), height / 2, gd / 2 - 1)), wallColour, Enum.Material.Metal)
	end
	B.part(garage, "Lintel", Vector3.new(gw - 44, 8, 2), CFrame.new(gc + Vector3.new(0, height - 4, gd / 2 - 1)), wallColour, Enum.Material.Metal)
	B.part(garage, "Roof", Vector3.new(gw + 2, 1.5, gd + 2), CFrame.new(gc + Vector3.new(0, height + 0.75, 0)), Color3.fromRGB(24, 24, 26), Enum.Material.Metal)
	local sign = B.part(garage, "Sign", Vector3.new(50, 7, 1), CFrame.new(gc + Vector3.new(0, height + 5, gd / 2 - 1)), Color3.fromRGB(12, 12, 14), Enum.Material.SmoothPlastic)
	B.label(sign, Enum.NormalId.Back, "VOLT CUSTOMS", volt)
	B.part(garage, "SignTrim", Vector3.new(51, 0.5, 1.2), CFrame.new(gc + Vector3.new(0, height + 1.4, gd / 2 - 1)), volt, Enum.Material.Neon, false)
	-- Interior: neon strip lights, tool walls, the display turntable.
	for x = -30, 30, 15 do
		B.part(garage, "StripLight", Vector3.new(10, 0.4, 0.8), CFrame.new(gc + Vector3.new(x, height - 1, 0)), Color3.fromRGB(230, 255, 240), Enum.Material.Neon, false)
	end
	for _, x in { -35, 35 } do
		local board = B.part(garage, "ToolBoard", Vector3.new(0.4, 10, 20), CFrame.new(gc + Vector3.new(x * (gw / 2 - 2.5) / 35, 9, -8)), Color3.fromRGB(60, 62, 66), Enum.Material.DiamondPlate)
		board.CanCollide = false
	end
	local turntable = MapLayout.Places.GarageTurntable
	B.cylinder(garage, "Turntable", 0.8, 9, CFrame.new(turntable + Vector3.new(0, ROAD_TOP + 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(30, 30, 34), Enum.Material.DiamondPlate)
	B.cylinder(garage, "TurntableRing", 0.85, 9.4, CFrame.new(turntable + Vector3.new(0, ROAD_TOP + 0.38, 0)) * CFrame.Angles(0, 0, math.rad(90)), volt, Enum.Material.Neon, false)
	local counter = B.part(garage, "Counter", Vector3.new(16, 4, 4), CFrame.new(gc + Vector3.new(30, 2.3, -12)), Color3.fromRGB(20, 20, 22), Enum.Material.SmoothPlastic)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GaragePrompt"
	prompt.ActionText = "Open garage"
	prompt.ObjectText = "Volt Customs"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonL3
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	-- Showroom plinth for the menu screen bike.
	local menuBike = MapLayout.Places.MenuBike
	B.cylinder(meet, "Plinth", 1.2, 7, CFrame.new(menuBike + Vector3.new(0, ROAD_TOP + 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(22, 22, 26), Enum.Material.SmoothPlastic)
	B.cylinder(meet, "PlinthGlow", 1.25, 7.3, CFrame.new(menuBike + Vector3.new(0, ROAD_TOP + 0.55, 0)) * CFrame.Angles(0, 0, math.rad(90)), volt, Enum.Material.Neon, false)

	-- Leaderboards and the challenge board along the north edge.
	local lb = MapLayout.Places.Leaderboard
	B.board(meet, "ServerBoard", CFrame.lookAt(lb + Vector3.new(-26, 0, 0), lb + Vector3.new(-26, 0, 10)), 24, 14, "SERVER BEST WHEELIES")
	B.board(meet, "GlobalBoard", CFrame.lookAt(lb + Vector3.new(0, 0, 0), lb + Vector3.new(0, 0, 10)), 24, 14, "ALL-TIME TOP 10")
	local cb = MapLayout.Places.ChallengeBoard
	local rows = B.board(meet, "ChallengeBoard", CFrame.lookAt(cb, cb + Vector3.new(0, 0, 10)), 30, 14, "TODAY'S CHALLENGES")
	local day = EconomyConfig.dayIndex(os.time())
	for i, challenge in EconomyConfig.dailyChallenges(day) do
		local row = rows:FindFirstChild("Row" .. (i * 2 - 1)) :: TextLabel?
		if row then
			row.Text = "• " .. challenge.Text
		end
		local reward = rows:FindFirstChild("Row" .. (i * 2)) :: TextLabel?
		if reward then
			reward.Text = string.format("    £%d  +%d XP", challenge.Cash, challenge.Xp)
			reward.TextColor3 = B.Palette.Volt
		end
	end

	-- Floodlights, bike racks, benches and a food van.
	for _, pos in { Vector3.new(-125, 0, -95), Vector3.new(125, 0, -95), Vector3.new(-125, 0, 95), Vector3.new(125, 0, 95) } do
		B.part(meet, "FloodPole", Vector3.new(1, 30, 1), CFrame.new(pos + Vector3.new(0, 15, 0)), Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
		B.part(meet, "FloodHead", Vector3.new(5, 2, 2), CFrame.lookAt(pos + Vector3.new(0, 30, 0), Vector3.new(0, 0, 0)), Color3.fromRGB(255, 250, 230), Enum.Material.Neon, false)
	end
	for x = -100, -40, 12 do
		B.part(meet, "BikeRack", Vector3.new(0.4, 3, 6), CFrame.new(x, ROAD_TOP + 1.5, 70), Color3.fromRGB(180, 180, 186), Enum.Material.Metal)
	end
	for x = 50, 110, 20 do
		B.bench(meet, CFrame.new(x, ROAD_TOP, 75) * CFrame.Angles(0, math.pi, 0))
	end
	local van = B.model(meet, "FoodVan")
	B.part(van, "Body", Vector3.new(8, 9, 18), CFrame.new(110, ROAD_TOP + 5, 40), Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic)
	local hatch = B.part(van, "Hatch", Vector3.new(0.3, 3, 10), CFrame.new(105.9, ROAD_TOP + 6, 40), Color3.fromRGB(20, 20, 20), Enum.Material.SmoothPlastic)
	B.label(hatch, Enum.NormalId.Left, "VOLT BITES", volt)
	for _, z in { 32, 48 } do
		B.cylinder(van, "Wheel", 1, 1.6, CFrame.new(110, ROAD_TOP + 1.6, z), Color3.fromRGB(20, 20, 20), Enum.Material.Rubber)
	end
end

local SHOP_NAMES = {
	{ "CORNER MART", Color3.fromRGB(40, 120, 60) },
	{ "GOLDEN FRY", Color3.fromRGB(200, 120, 20) },
	{ "PERI JUNCTION", Color3.fromRGB(180, 30, 40) },
	{ "FISH & CHIPS", Color3.fromRGB(30, 80, 160) },
	{ "VAPE & VOLT", Color3.fromRGB(90, 40, 150) },
	{ "TOP CUTS BARBER", Color3.fromRGB(20, 20, 20) },
	{ "PIZZA ROYALE", Color3.fromRGB(170, 40, 40) },
	{ "PHONE FIX", Color3.fromRGB(30, 140, 190) },
	{ "BOOKIES", Color3.fromRGB(20, 100, 60) },
	{ "BAKERY", Color3.fromRGB(150, 100, 60) },
	{ "LAUNDERETTE", Color3.fromRGB(60, 120, 180) },
	{ "PHARMACY", Color3.fromRGB(30, 150, 80) },
	{ "KEBAB HOUSE", Color3.fromRGB(200, 60, 20) },
	{ "CHARITY SHOP", Color3.fromRGB(120, 60, 140) },
	{ "NAIL STUDIO", Color3.fromRGB(220, 90, 150) },
	{ "OFF LICENCE", Color3.fromRGB(110, 30, 40) },
}

-- A row of shops facing a road along X, between x0 and x1, `side` = -1 (north) or 1 (south).
local function shopRow(parent: Instance, x0: number, x1: number, roadZ: number, side: number, depth: number)
	local frontZ = roadZ + side * (14 + PAVE_W + 0.5)
	local facing = Vector3.new(0, 0, -side)
	local x = x0
	while x < x1 - 20 do
		local width = rng:NextInteger(24, 34)
		if x + width > x1 then
			break
		end
		local entry = SHOP_NAMES[rng:NextInteger(1, #SHOP_NAMES)]
		local centre = Vector3.new(x + width / 2, 0, frontZ + side * depth / 2)
		B.shop(parent, CFrame.lookAt(centre, centre + facing), width, depth, entry[1], entry[2], rng)
		x += width
	end
end

local function buildTown(parent: Instance)
	local town = B.model(parent, "Town")
	-- High street shops on both sides, leaving gaps at junctions.
	for _, span in { { -786, -486 }, { -456, -216 }, { -186, 164 }, { 196, 486 }, { 516, 786 } } do
		shopRow(town, span[1], span[2], -300, -1, 30)
	end
	for _, span in { { -786, -486 }, { -456, -216 }, { 196, 486 }, { 516, 786 } } do
		shopRow(town, span[1], span[2], -300, 1, 26)
	end
	task.wait()

	-- Petrol station (Market Street corner).
	local petrol = B.model(town, "PetrolStation")
	local pc = Vector3.new(-120, 0, -390)
	B.part(petrol, "Forecourt", Vector3.new(90, 1, 60), CFrame.new(pc + Vector3.new(0, ROAD_TOP - 0.5, 0)), Color3.fromRGB(170, 170, 168), Enum.Material.Concrete)
	B.part(petrol, "Canopy", Vector3.new(60, 2.5, 34), CFrame.new(pc + Vector3.new(0, 18, 0)), Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic)
	local band = B.part(petrol, "CanopyBand", Vector3.new(60.4, 1.4, 34.4), CFrame.new(pc + Vector3.new(0, 17, 0)), Color3.fromRGB(20, 120, 200), Enum.Material.SmoothPlastic, false)
	B.label(band, Enum.NormalId.Back, "RAPIDFUEL", Color3.new(1, 1, 1))
	for _, x in { -20, 0, 20 } do
		B.part(petrol, "Column", Vector3.new(1.2, 17, 1.2), CFrame.new(pc + Vector3.new(x, 8.5, 0)), Color3.fromRGB(230, 230, 230), Enum.Material.Metal)
		B.part(petrol, "Pump", Vector3.new(3, 6, 2), CFrame.new(pc + Vector3.new(x, 3.3, 5)), Color3.fromRGB(20, 120, 200), Enum.Material.SmoothPlastic)
		B.part(petrol, "Pump", Vector3.new(3, 6, 2), CFrame.new(pc + Vector3.new(x, 3.3, -5)), Color3.fromRGB(20, 120, 200), Enum.Material.SmoothPlastic)
	end
	B.shop(petrol, CFrame.lookAt(pc + Vector3.new(0, 0, -50), pc + Vector3.new(0, 0, 0)), 40, 24, "RAPIDFUEL SHOP", Color3.fromRGB(20, 120, 200), rng)

	-- Supermarket with a big car park.
	local market = B.model(town, "Supermarket")
	local sc = Vector3.new(340, 0, -560)
	B.part(market, "CarPark", Vector3.new(260, 1, 150), CFrame.new(340, ROAD_TOP - 0.5, -420), Color3.fromRGB(56, 58, 62), Enum.Material.Asphalt)
	for x = 220, 460, 12 do
		for _, z in { -450, -390 } do
			B.part(market, "BayLine", Vector3.new(0.4, 0.05, 16), CFrame.new(x, ROAD_TOP + 0.03, z), LINE_WHITE, Enum.Material.SmoothPlastic, false).CastShadow = false
		end
	end
	for k = 1, 10 do
		B.car(market, CFrame.new(220 + rng:NextInteger(0, 20) * 12 + 6, ROAD_TOP, if k % 2 == 0 then -450 else -390) * CFrame.Angles(0, if rng:NextNumber() < 0.5 then 0 else math.pi, 0), B.Palette.Car[rng:NextInteger(1, #B.Palette.Car)])
	end
	local storeModel = B.warehouse(market, CFrame.lookAt(sc, sc + Vector3.new(0, 0, 1)), 160, 90, 26, "FRESHWAY SUPERSTORE", rng)
	storeModel.Name = "Supermarket"

	-- Town square with a bus station, phone box and post box.
	local square = B.model(town, "TownSquare")
	local tc = Vector3.new(0, 0, -430)
	B.part(square, "Paving", Vector3.new(120, 1, 100), CFrame.new(tc + Vector3.new(30, PAVE_TOP - 0.5, 0)), Color3.fromRGB(180, 172, 160), Enum.Material.Cobblestone)
	B.busStop(square, CFrame.lookAt(tc + Vector3.new(30, PAVE_TOP, 40), tc + Vector3.new(30, PAVE_TOP, 60)), "TOWN SQUARE")
	B.busStop(square, CFrame.lookAt(tc + Vector3.new(70, PAVE_TOP, 40), tc + Vector3.new(70, PAVE_TOP, 60)), "TOWN SQUARE")
	B.phoneBox(square, CFrame.new(tc + Vector3.new(-20, PAVE_TOP, 30)))
	B.postBox(square, CFrame.new(tc + Vector3.new(-12, PAVE_TOP, 30)))
	B.part(square, "ClockTower", Vector3.new(8, 40, 8), CFrame.new(tc + Vector3.new(30, 20, -10)), Color3.fromRGB(150, 110, 80), Enum.Material.Brick)
	local face = B.part(square, "ClockFace", Vector3.new(6, 6, 0.4), CFrame.new(tc + Vector3.new(30, 34, -5.9)), Color3.fromRGB(240, 240, 230), Enum.Material.SmoothPlastic, false)
	B.label(face, Enum.NormalId.Back, "XII", Color3.new(0, 0, 0))
	for k = 1, 8 do
		B.tree(square, tc + Vector3.new(-25 + k * 12, PAVE_TOP, -40), 0.7, rng)
		B.bench(square, CFrame.new(tc + Vector3.new(-25 + k * 12, PAVE_TOP, -32)))
	end

	-- Flats behind the shops fill the northern blocks.
	for _, x in { -700, -560, -400, 600, 720 } do
		B.house(town, CFrame.lookAt(Vector3.new(x, 0, -520), Vector3.new(x, 0, -300)), 40, 30, rng, { Height = 34, RoofHeight = 8 })
	end
	-- Back alleys behind the north shops: narrow lanes with bins.
	for _, x in { -640, -320, 640 } do
		B.part(town, "Alley", Vector3.new(10, 1, 120), CFrame.new(x, ROAD_TOP - 0.5, -420), Color3.fromRGB(70, 70, 70), Enum.Material.Concrete)
		for k = 0, 4 do
			B.bin(town, CFrame.new(x + 4, ROAD_TOP, -460 + k * 18))
		end
	end
	-- Parked cars along the high street.
	for _ = 1, 14 do
		local x = rng:NextInteger(-760, 760)
		if math.abs(x - 180) > 40 and math.abs(x + 200) > 30 and math.abs(x - 500) > 30 and math.abs(x + 470) > 30 then
			B.car(town, CFrame.new(x, ROAD_TOP, -300 - 10) * CFrame.Angles(0, math.rad(90), 0), B.Palette.Car[rng:NextInteger(1, #B.Palette.Car)])
		end
	end
end

local function buildEstate(parent: Instance)
	local estate = B.model(parent, "Estate")
	-- Terraces along both sides of Beacon Way (z = 0), between Western Road and the meet.
	for _, span in { { -780, -494 }, { -446, -230 } } do
		local x0, x1 = span[1], span[2]
		local count = math.floor((x1 - x0) / 22)
		local width = count * 22
		for _, side in { -1, 1 } do
			local centre = Vector3.new((x0 + x1) / 2, 0, side * (11 + PAVE_W + 16 + 13))
			B.terrace(estate, CFrame.lookAt(centre, centre - Vector3.new(0, 0, side)), count, 22, 26, rng)
			-- Back fences, with an alleyway behind each terrace.
			local backZ = side * (11 + PAVE_W + 16 + 26 + 8)
			B.fence(estate, Vector3.new(x0, ROAD_TOP, backZ), Vector3.new(x0 + width, ROAD_TOP, backZ), 6)
			B.part(estate, "Alley", Vector3.new(width, 1, 8), CFrame.new((x0 + x0 + width) / 2, ROAD_TOP - 0.5, backZ + side * 5), Color3.fromRGB(80, 80, 80), Enum.Material.Concrete)
		end
		task.wait()
	end
	-- Semi-detached houses on Oak Close.
	for x = -770, -510, 52 do
		for _, side in { -1, 1 } do
			local centre = Vector3.new(x + 20, 0, -150 + side * 42)
			local base = CFrame.lookAt(centre, centre - Vector3.new(0, 0, side))
			local colour = B.Palette.Brick[rng:NextInteger(1, #B.Palette.Brick)]
			B.house(estate, base * CFrame.new(-10, 0, 0), 20, 26, rng, { Colour = colour, DoorOffset = -5 })
			B.house(estate, base * CFrame.new(10, 0, 0), 20, 26, rng, { Colour = colour, DoorOffset = 5, Chimney = false })
			-- Drive with a parked car.
			if rng:NextNumber() < 0.6 then
				B.car(estate, CFrame.new(centre + Vector3.new(24, ROAD_TOP, -side * 18)), B.Palette.Car[rng:NextInteger(1, #B.Palette.Car)])
			end
		end
	end
	task.wait()
	-- Houses along Hollow Lane (x = -470) on its west side and Crescent Drive.
	for z = -260, 200, 34 do
		if math.abs(z) > 40 and math.abs(z + 150) > 30 and math.abs(z - 120) > 30 then
			local centre = Vector3.new(-470 - (11 + PAVE_W + 18), 0, z)
			B.house(estate, CFrame.lookAt(centre, centre + Vector3.new(1, 0, 0)), 26, 24, rng)
		end
	end
	for x = -440, -250, 34 do
		local centre = Vector3.new(x, 0, 120 + 10 + PAVE_W + 16)
		B.house(estate, CFrame.lookAt(centre, centre - Vector3.new(0, 0, 1)), 26, 24, rng)
	end
	-- Turning circle at the end of Crescent Drive.
	B.cylinder(estate, "TurningCircle", 1, 22, CFrame.new(-215, ROAD_TOP - 0.5, 120) * CFrame.Angles(0, 0, math.rad(90)), ASPHALT, Enum.Material.Asphalt)
	-- Lock-up garages block.
	local lockups = B.model(estate, "LockUps")
	for k = 0, 7 do
		local x = -440 + k * 14
		B.part(lockups, "Garage", Vector3.new(13.6, 10, 20), CFrame.new(x, 5, 190), Color3.fromRGB(150, 140, 128), Enum.Material.Brick)
		B.part(lockups, "Door", Vector3.new(11, 8, 0.3), CFrame.new(x, 4, 179.9), Color3.fromRGB(80 + k * 10, 90, 100), Enum.Material.DiamondPlate, false)
	end
	B.part(lockups, "Yard", Vector3.new(120, 1, 30), CFrame.new(-390, ROAD_TOP - 0.5, 165), Color3.fromRGB(90, 90, 90), Enum.Material.Concrete)
	-- Small estate park with a playground.
	local park = B.model(estate, "EstatePark")
	B.fence(park, Vector3.new(-760, ROAD_TOP, 60), Vector3.new(-560, ROAD_TOP, 60), 3, Color3.fromRGB(40, 90, 50), Enum.Material.Metal)
	for k = 1, 6 do
		B.tree(park, Vector3.new(-750 + k * 30, 0, 100 + rng:NextInteger(-20, 40)), 0.8 + rng:NextNumber() * 0.4, rng)
	end
	B.part(park, "Swings", Vector3.new(14, 0.6, 0.6), CFrame.new(-650, 9, 140), Color3.fromRGB(200, 40, 40), Enum.Material.Metal)
	for _, x in { -657, -643 } do
		B.part(park, "SwingLeg", Vector3.new(0.6, 9, 0.6), CFrame.new(x, 4.5, 140), Color3.fromRGB(200, 40, 40), Enum.Material.Metal)
	end
	B.part(park, "Slide", Vector3.new(3, 0.5, 14), CFrame.new(-610, 3.5, 150) * CFrame.Angles(math.rad(25), 0, 0), Color3.fromRGB(240, 200, 30), Enum.Material.SmoothPlastic)
	-- Wheelie bins outside houses.
	for k = 1, 30 do
		B.bin(estate, CFrame.new(rng:NextInteger(-780, -240), ROAD_TOP + 0.45, (if k % 2 == 0 then 1 else -1) * (11 + PAVE_W - 1)), if k % 3 == 0 then Color3.fromRGB(30, 90, 160) else nil)
	end
end

local function buildIndustrial(parent: Instance)
	local ind = B.model(parent, "Industrial")
	local names = { "NORTHGATE LOGISTICS", "ACE METALWORKS", "PARCELFAST", "DOCKSIDE TIMBER", "EASTWAY TRADE", "KWIKPALLET" }
	local n = 0
	-- Warehouses north of Dock Road (z -286..-108), facing the road.
	for _, x in { 270, 420, 610, 730 } do
		n += 1
		local centre = Vector3.new(x, 0, -200)
		B.warehouse(ind, CFrame.lookAt(centre, centre + Vector3.new(0, 0, 1)), if x > 600 then 100 else 120, 70, 30, names[n], rng)
	end
	task.wait()
	-- South of Dock Road: two warehouses west of Fifth Street, the big open yard to the east.
	for _, x in { 280, 420 } do
		n += 1
		local centre = Vector3.new(x, 0, 30)
		B.warehouse(ind, CFrame.lookAt(centre, centre - Vector3.new(0, 0, 1)), 120, 80, 32, names[(n - 1) % #names + 1], rng)
	end
	-- The yard: a huge flat concrete apron, perfect for wheelie practice.
	local yard = B.model(ind, "PracticeYard")
	B.part(yard, "Apron", Vector3.new(270, 1, 290), CFrame.new(655, ROAD_TOP - 0.48, 70), Color3.fromRGB(150, 150, 148), Enum.Material.Concrete)
	for k = 0, 8 do
		B.part(yard, "YardLine", Vector3.new(0.6, 0.05, 260), CFrame.new(540 + k * 30, ROAD_TOP + 0.04, 70), LINE_YELLOW, Enum.Material.SmoothPlastic, false).CastShadow = false
	end
	local sign = B.part(yard, "YardSign", Vector3.new(30, 6, 0.6), CFrame.new(655, 10, -60), Color3.fromRGB(20, 20, 22))
	B.label(sign, Enum.NormalId.Back, "DOCKSIDE YARD", B.Palette.Volt)
	B.part(yard, "SignLeg", Vector3.new(1, 8, 1), CFrame.new(645, 4, -60), Color3.fromRGB(40, 40, 40), Enum.Material.Metal)
	B.part(yard, "SignLeg", Vector3.new(1, 8, 1), CFrame.new(665, 4, -60), Color3.fromRGB(40, 40, 40), Enum.Material.Metal)
	-- Container stacks along the yard's east edge.
	local containerColours = { Color3.fromRGB(180, 50, 40), Color3.fromRGB(30, 90, 160), Color3.fromRGB(40, 120, 70), Color3.fromRGB(200, 140, 40), Color3.fromRGB(120, 120, 120) }
	for k = 0, 8 do
		local z = -50 + k * 24
		local base = CFrame.new(768, ROAD_TOP, z) * CFrame.Angles(0, math.rad(90), 0)
		B.container(yard, base, containerColours[rng:NextInteger(1, #containerColours)])
		if k % 2 == 0 then
			B.container(yard, base * CFrame.new(0, 8.7, 0), containerColours[rng:NextInteger(1, #containerColours)])
		end
	end
	-- Security fencing round the yard.
	B.fence(ind, Vector3.new(522, ROAD_TOP, 216), Vector3.new(786, ROAD_TOP, 216), 8, Color3.fromRGB(60, 90, 60), Enum.Material.Metal)
	-- Pallets and a few vans.
	for _ = 1, 8 do
		B.part(ind, "Pallet", Vector3.new(4, 1, 4), CFrame.new(rng:NextInteger(230, 470), ROAD_TOP + 0.5, rng:NextInteger(-130, -110)), Color3.fromRGB(150, 110, 70), Enum.Material.WoodPlanks)
	end
	for k = 1, 6 do
		B.car(ind, CFrame.new(rng:NextInteger(230, 470), ROAD_TOP, if k % 2 == 0 then -125 else 90) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(240, 240, 240))
	end
end

local function buildPark(parent: Instance)
	local park = B.model(parent, "VictoriaPark")
	B.part(park, "Path", Vector3.new(6, 1, 110), CFrame.new(0, ROAD_TOP - 0.45, 165), Color3.fromRGB(190, 180, 160), Enum.Material.Pavement)
	B.part(park, "Path", Vector3.new(260, 1, 6), CFrame.new(-15, ROAD_TOP - 0.45, 165), Color3.fromRGB(190, 180, 160), Enum.Material.Pavement)
	for _ = 1, 18 do
		local pos = Vector3.new(rng:NextInteger(-180, 150), 0, rng:NextInteger(115, 220))
		if math.abs(pos.X) > 8 and math.abs(pos.Z - 165) > 8 then
			B.tree(park, pos, 0.8 + rng:NextNumber() * 0.5, rng)
		end
	end
	for _, x in { -60, 40, 100 } do
		B.bench(park, CFrame.new(x, ROAD_TOP, 172) * CFrame.Angles(0, math.pi, 0))
	end
	local pond = B.cylinder(park, "Pond", 0.4, 18, CFrame.new(-120, 0.1, 190) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(60, 110, 140), Enum.Material.Glass, false)
	pond.Transparency = 0.2
	-- Little skate/bike pump track: two rollers and a kicker.
	B.cylinder(park, "Roller", 20, 4, CFrame.new(80, -2.6, 130) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(170, 170, 168), Enum.Material.Concrete)
	B.cylinder(park, "Roller", 20, 4, CFrame.new(110, -2.6, 130) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(170, 170, 168), Enum.Material.Concrete)
	B.wedge(park, "Kicker", Vector3.new(12, 3, 10), CFrame.new(140, 1.5, 130) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(170, 170, 168), Enum.Material.Concrete)
end

local function buildStrip(parent: Instance)
	local stripModel = B.model(parent, "WheelieStrip")
	local start = MapLayout.Places.StripStart
	local metre = 1 / GameConfig.Units.MetresPerStud
	local markerEvery = 50 * metre
	local x = start.X
	local metres = 0
	-- Start gantry.
	for _, z in { -20, 20 } do
		B.part(stripModel, "GantryLeg", Vector3.new(1.4, 20, 1.4), CFrame.new(start.X, 10, start.Z + z), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
	end
	local gantry = B.part(stripModel, "Gantry", Vector3.new(2, 4, 42), CFrame.new(start.X, 21, start.Z), Color3.fromRGB(16, 16, 18), Enum.Material.SmoothPlastic)
	B.label(gantry, Enum.NormalId.Right, "THE STRIP  ▸  WHEELIE ZONE", B.Palette.Volt)
	B.label(gantry, Enum.NormalId.Left, "THE STRIP", B.Palette.Volt)
	while x <= 1080 do
		local line = B.part(stripModel, "DistanceLine", Vector3.new(0.8, 0.06, 32), CFrame.new(x, ROAD_TOP + 0.04, start.Z), if metres % 100 == 0 then B.Palette.Volt else LINE_WHITE, Enum.Material.SmoothPlastic, false)
		line.CastShadow = false
		if metres > 0 then
			local board = B.part(stripModel, "Marker", Vector3.new(0.5, 4, 8), CFrame.new(x, 7, start.Z - 17 - PAVE_W - 2), Color3.fromRGB(16, 16, 18), Enum.Material.SmoothPlastic)
			B.label(board, Enum.NormalId.Left, metres .. " m", Color3.new(1, 1, 1))
			B.label(board, Enum.NormalId.Right, metres .. " m", Color3.new(1, 1, 1))
			B.part(stripModel, "MarkerPost", Vector3.new(0.4, 5, 0.4), CFrame.new(x, 2.5, start.Z - 17 - PAVE_W - 2), Color3.fromRGB(60, 60, 60), Enum.Material.Metal)
		end
		x += markerEvery
		metres += 50
	end
	-- Spectator stands on the north side at intervals.
	for _, sx in { -800, -400, 0, 400, 800 } do
		local stand = B.model(stripModel, "Stand")
		for step = 0, 3 do
			B.part(stand, "Step", Vector3.new(60, 2, 4), CFrame.new(sx, 1 + step * 2, start.Z - 34 - step * 4), Color3.fromRGB(150, 150, 150), Enum.Material.Concrete)
		end
		B.part(stand, "Canopy", Vector3.new(62, 0.6, 20), CFrame.new(sx, 16, start.Z - 40), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
		for _, px in { -30, 30 } do
			B.part(stand, "CanopyPost", Vector3.new(0.6, 16, 0.6), CFrame.new(sx + px, 8, start.Z - 48), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
		end
	end
	-- Low barriers along the south edge.
	B.part(stripModel, "Barrier", Vector3.new(2200, 2.4, 1.2), CFrame.new(0, PAVE_TOP + 1.2, start.Z + 17 + PAVE_W + 1), Color3.fromRGB(200, 200, 200), Enum.Material.Concrete)
end

local function terrainHeight(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	local hit = Workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -400, 0), params)
	return if hit then hit.Position.Y else 0
end

local function buildCountryside(parent: Instance)
	local country = B.model(parent, "Countryside")
	local terrain = Workspace.Terrain
	-- Flat grass base around the city (top at y = 0), then hills.
	terrain:FillBlock(CFrame.new(-1260, -10, 190), Vector3.new(880, 20, 1820), Enum.Material.Grass)
	terrain:FillBlock(CFrame.new(165, -10, 880), Vector3.new(1970, 20, 440), Enum.Material.Grass)
	for _, hill in {
		{ Vector3.new(-1460, -40, -460), 90 },
		{ Vector3.new(-1560, -45, 520), 95 },
		{ Vector3.new(-960, -48, 920), 75 },
		{ Vector3.new(380, -55, 960), 95 },
		{ Vector3.new(800, -50, 900), 80 },
		{ Vector3.new(-1600, -30, 900), 70 },
	} do
		terrain:FillBall(hill[1], hill[2], Enum.Material.Grass)
	end
	terrain:FillBall(Vector3.new(-1460, -30, -460), 60, Enum.Material.Ground)
	task.wait()

	-- Stream crossing Old Mill Lane under a small bridge.
	local streamZ = -150
	terrain:FillBlock(CFrame.new(-1265, -3, streamZ), Vector3.new(870, 6, 24), Enum.Material.Air)
	terrain:FillBlock(CFrame.new(-1265, -4.5, streamZ), Vector3.new(870, 3, 24), Enum.Material.Water)
	terrain:FillBlock(CFrame.new(-1265, -7, streamZ), Vector3.new(870, 2, 28), Enum.Material.Mud)
	for _, side in { -1, 1 } do
		B.part(country, "BridgeRail", Vector3.new(0.6, 3, 30), CFrame.new(-1100 + side * 10.5, ROAD_TOP + 1.5, streamZ), Color3.fromRGB(140, 130, 120), Enum.Material.Cobblestone)
		B.part(country, "BridgeBeam", Vector3.new(1.5, 3, 30), CFrame.new(-1100 + side * 10.5, -1.5, streamZ), Color3.fromRGB(110, 100, 90), Enum.Material.Cobblestone)
	end

	-- Dirt track loop with jumps, linked to Old Mill Lane.
	local track = B.model(country, "DirtTrack")
	local centre = MapLayout.Places.DirtTrackCentre
	local rx, rz = 150, 105
	local segments = 28
	local dirt = Color3.fromRGB(120, 90, 60)
	for k = 0, segments - 1 do
		local a0 = (k / segments) * math.pi * 2
		local a1 = ((k + 1) / segments) * math.pi * 2
		local p0 = centre + Vector3.new(math.cos(a0) * rx, 0, math.sin(a0) * rz)
		local p1 = centre + Vector3.new(math.cos(a1) * rx, 0, math.sin(a1) * rz)
		local length = (p1 - p0).Magnitude + 2
		B.part(track, "Track", Vector3.new(18, 1, length), CFrame.lookAt((p0 + p1) / 2 + Vector3.new(0, ROAD_TOP - 0.5, 0), (p1 + p0) / 2 + (p1 - p0) + Vector3.new(0, ROAD_TOP - 0.5, 0)), dirt, Enum.Material.Ground)
		if k % 7 == 3 then
			local mid = (p0 + p1) / 2
			local dir = (p1 - p0).Unit
			B.wedge(track, "Kicker", Vector3.new(14, 3.5, 12), CFrame.lookAt(mid + Vector3.new(0, ROAD_TOP + 1.75, 0), mid + Vector3.new(0, ROAD_TOP + 1.75, 0) - dir), dirt, Enum.Material.Ground)
		end
	end
	local link0 = centre + Vector3.new(rx, 0, 0)
	B.part(track, "TrackLink", Vector3.new(math.abs(-1110 - link0.X), 1, 16), CFrame.new((link0.X + -1110) / 2, ROAD_TOP - 0.5, centre.Z), dirt, Enum.Material.Ground)
	task.wait()

	-- Hedgerows along the lane and fields to the south.
	B.hedge(country, Vector3.new(-1117, terrainHeight(-1117, -280), -280), Vector3.new(-1117, 0, -170), 5)
	B.hedge(country, Vector3.new(-1083, 0, -280), Vector3.new(-1083, 0, -170), 5)
	B.hedge(country, Vector3.new(-1083, 0, -130), Vector3.new(-1083, 0, 560), 5)
	for fx = -760, -260, 125 do
		B.hedge(country, Vector3.new(fx, 0, 680), Vector3.new(fx, 0, 1040), 5)
	end
	B.hedge(country, Vector3.new(-760, 0, 680), Vector3.new(-135, 0, 680), 5)
	-- A barn.
	local barn = B.model(country, "Barn")
	B.part(barn, "Walls", Vector3.new(40, 18, 60), CFrame.new(-480, 9, 900), Color3.fromRGB(150, 40, 30), Enum.Material.WoodPlanks)
	B.pitchedRoof(barn, CFrame.new(-480, 0, 900) * CFrame.Angles(0, math.rad(90), 0), 60, 40, 18, 10, Color3.fromRGB(70, 70, 74))

	-- Trees scattered across the countryside, kept off the roads, track and stream.
	local placed = 0
	local attempts = 0
	while placed < 110 and attempts < 600 do
		attempts += 1
		local x, z
		if rng:NextNumber() < 0.6 then
			x, z = rng:NextNumber(-1680, -840), rng:NextNumber(-700, 1080)
		else
			x, z = rng:NextNumber(-820, 1120), rng:NextNumber(680, 1080)
		end
		local nearLane = math.abs(x + 1100) < 25 and z < 620
		local nearStrip = math.abs(z - 600) < 40
		local d = Vector2.new((x - centre.X) / (rx + 20), (z - centre.Z) / (rz + 20))
		local nearTrack = d.Magnitude < 1.25 and d.Magnitude > 0.7
		local nearStream = math.abs(z - streamZ) < 20 and x < -820
		if not (nearLane or nearStrip or nearTrack or nearStream) then
			B.tree(country, Vector3.new(x, terrainHeight(x, z) - 0.5, z), 0.9 + rng:NextNumber() * 0.7, rng)
			placed += 1
		end
	end
end

------------------------------------------------------------------------ entry point

function MapGenerator.generate(): Folder
	local existing = Workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end
	local map = Instance.new("Folder")
	map.Name = "Map"
	-- Build off-screen, then parent once, so clients get one replication burst.
	buildGround(map)
	buildRoads(map)
	buildMeet(map)
	task.wait()
	buildTown(map)
	task.wait()
	buildEstate(map)
	task.wait()
	buildIndustrial(map)
	buildPark(map)
	buildStrip(map)
	map.Parent = Workspace
	-- Terrain lives on Workspace.Terrain, so the countryside goes last (it raycasts the terrain).
	buildCountryside(map)
	return map
end

return MapGenerator
