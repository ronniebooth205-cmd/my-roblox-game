--!strict
-- ReplicatedStorage > Shared > BikeBuilder (ModuleScript)
-- Builds a complete electric dirt bike Model out of parts: frame, battery, motor, swingarm,
-- shock, forks, bars, grips, wheels with rims/spokes/discs, chain, mudguards, lights, plate and
-- footpegs. Used by the server (BikeService) for rideable bikes and by the client for the
-- garage/menu previews, so both always look identical.
--
-- Structure (forward is -Z, built around the chassis at the origin, then pivoted into place):
--   Chassis      invisible, the only part with mass; root of the assembly
--   Hull         massless collision box around the body
--   Seat         where the rider sits
--   SteerHub     Motor6D "SteerJoint" (rotates for steering, along the raked steering axis)
--     ForkSlider Motor6D "ForkJoint" (slides along the fork for front suspension)
--       FrontWheel Motor6D "FrontWheelJoint" (spins)
--   Swingarm     Motor6D "SwingarmJoint" (pivots with rear suspension)
--   RearWheel    Motor6D "RearWheelJoint" (moves with suspension and spins)
-- The joints' Transforms are animated on every client by BikeVisuals; physics never touches
-- them, so the visuals can't destabilise the simulation.
--
-- Body meshes: if ReplicatedStorage has a "BikeMeshes" folder holding the Surron-style meshes
-- from tools/blender (Frame, BatteryCover, Plastics, Seat, Mudguards), they replace the
-- part-built frame, battery, plastics, seat and rear mudguard. Without it the bike is built from
-- parts as before. See docs/BIKE_MESHES.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CustomisationConfig = require(script.Parent.CustomisationConfig)
local BikeDefinitions = require(script.Parent.BikeDefinitions)
local BikeStats = require(script.Parent.BikeStats)
local PhysicsConfig = require(script.Parent.PhysicsConfig)
local BikeMeshLayout = require(script.Parent.BikeMeshLayout)

local BikeBuilder = {}

export type BuildOptions = {
	Anchored: boolean?, -- previews are anchored; rideable bikes are not
	Name: string?,
}

local TYRE_COLOUR = Color3.fromRGB(28, 28, 30)
local METAL_DARK = Color3.fromRGB(70, 72, 78)
local METAL_LIGHT = Color3.fromRGB(150, 154, 160)

local function paint(setup: BikeStats.BikeSetup, slot: string): (Color3, Enum.Material?)
	local name = setup.Colours[slot]
	local colour = name and CustomisationConfig.colour(name)
	if not colour then
		local slotDef = CustomisationConfig.paintSlot(slot)
		colour = slotDef and CustomisationConfig.colour(slotDef.Default)
	end
	if not colour then
		return Color3.new(0.5, 0.5, 0.5), nil
	end
	local material = (colour :: any).Material
	return colour.Color, material and (Enum.Material :: any)[material] or nil
end

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = colour
	part.Material = material or Enum.Material.SmoothPlastic
	part.Shape = shape or Enum.PartType.Block
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = size.Magnitude > 1
	part.Parent = parent
	return part
end

-- A box stretched between two points (tubes, rails, chain runs).
local function beam(parent: Instance, name: string, a: Vector3, b: Vector3, width: number, height: number, colour: Color3, material: Enum.Material?): Part
	local length = (b - a).Magnitude
	return newPart(parent, name, Vector3.new(width, height, length), CFrame.lookAt((a + b) / 2, b), colour, material)
end

-- A cylinder between two points (fork tubes, shock).
local function tube(parent: Instance, name: string, a: Vector3, b: Vector3, radius: number, colour: Color3, material: Enum.Material?): Part
	local length = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
	return newPart(parent, name, Vector3.new(length, radius * 2, radius * 2), cf, colour, material, Enum.PartType.Cylinder)
end

-- A disc whose flat faces point along X (wheels, discs, sprockets).
local function disc(parent: Instance, name: string, centre: Vector3, radius: number, width: number, colour: Color3, material: Enum.Material?): Part
	return newPart(parent, name, Vector3.new(width, radius * 2, radius * 2), CFrame.new(centre), colour, material, Enum.PartType.Cylinder)
end

-- The imported body meshes, or nil unless every one in the layout is there (a half-imported set
-- would leave holes in the bike, so it's all or nothing).
local function findBodyMeshes(): { [string]: MeshPart }?
	local folder = ReplicatedStorage:FindFirstChild("BikeMeshes")
	if not folder then
		return nil
	end
	local found: { [string]: MeshPart } = {}
	for name in BikeMeshLayout.Meshes do
		local mesh = folder:FindFirstChild(name :: string, true)
		if not (mesh and mesh:IsA("MeshPart")) then
			return nil
		end
		found[name :: string] = mesh
	end
	return found
end

-- Studio's importer centres each mesh on its bounding box, so the layout's centre and size put
-- it back in place whatever scale it came in at. The meshes are modelled on the standard 4-stud
-- wheelbase; bikes with other geometry stretch them lengthways (L) and move them with the ground.
local STANDARD_GROUND_Y = -(1.3 + 0.9 - 0.3) - 1.05
-- Studio's OBJ importer brings the meshes in facing backwards (seen in the first playtest: the
-- side covers sat over the rear wheel), so they're turned round. The body is symmetric side to
-- side, so a half turn about Y is the same as flipping front and back.
local IMPORT_ROTATION = CFrame.Angles(0, math.pi, 0)
local function bodyMesh(parent: Instance, source: MeshPart, name: string, L: number, groundY: number, colour: Color3, material: Enum.Material?): MeshPart
	local layout = BikeMeshLayout.Meshes[name]
	local centre = layout.Centre
	local size = layout.Size
	local part = source:Clone()
	part:ClearAllChildren() -- drop any SurfaceAppearance the importer added, so paint shows
	-- "Body" prefix: the rider's Seat is found by name, so the seat mesh mustn't be called "Seat".
	part.Name = "Body" .. name
	part.TextureID = ""
	part.Size = Vector3.new(size.X, size.Y, size.Z * L)
	part.CFrame = CFrame.new(centre.X, centre.Y + groundY - STANDARD_GROUND_Y, centre.Z * L) * IMPORT_ROTATION
	part.Color = colour
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = true
	part.Parent = parent
	return part
end

local function weldTo(part: BasePart, target: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = target
	weld.Part1 = part
	weld.Parent = part
end

local function hub(parent: Instance, name: string, cf: CFrame): Part
	local part = newPart(parent, name, Vector3.new(0.2, 0.2, 0.2), cf, Color3.new(), nil)
	part.Transparency = 1
	part.CastShadow = false
	return part
end

local function motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame): Motor6D
	local joint = Instance.new("Motor6D")
	joint.Name = name
	joint.Part0 = part0
	joint.Part1 = part1
	joint.C0 = c0
	joint.C1 = CFrame.identity
	joint.Parent = part0
	return joint
end

local function buildWheel(model: Model, hubPart: BasePart, centre: Vector3, radius: number, width: number, setup: BikeStats.BikeSetup, discSide: number, discRadius: number)
	local rimColour, rimMaterial = paint(setup, "Rims")
	local spokeColour = paint(setup, "Spokes")
	local parts: { BasePart } = {}
	table.insert(parts, disc(model, "Tyre", centre, radius, width, TYRE_COLOUR, Enum.Material.Rubber))
	-- The rim disc sits just proud of the tyre walls so its colour and spokes show on both sides.
	table.insert(parts, disc(model, "Rim", centre, radius * 0.74, width + 0.04, rimColour, rimMaterial or Enum.Material.Metal))
	table.insert(parts, disc(model, "RimInner", centre, radius * 0.66, width + 0.06, Color3.fromRGB(16, 16, 18), Enum.Material.SmoothPlastic))
	table.insert(parts, disc(model, "Hub", centre, 0.16, width + 0.14, METAL_LIGHT, Enum.Material.Metal))
	local spokes = 10
	for i = 1, spokes do
		local angle = (i / spokes) * math.pi * 2
		local spoke = newPart(model, "Spoke", Vector3.new(width + 0.1, 0.035, radius * 0.66), CFrame.new(centre) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, 0, radius * 0.33), spokeColour, Enum.Material.Metal)
		spoke.CastShadow = false
		table.insert(parts, spoke)
	end

	-- Knobbly tyres get tread blocks round the outside.
	local tyreType = setup.Options.TyreType or "Street"
	local knobs = if tyreType == "OffRoad" then 18 elseif tyreType == "Mixed" then 12 else 0
	for i = 1, knobs do
		local angle = (i / knobs) * math.pi * 2
		local knob = newPart(model, "Knob", Vector3.new(width * 0.9, 0.14, 0.22), CFrame.new(centre) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, radius - 0.03, 0), TYRE_COLOUR, Enum.Material.Rubber)
		knob.CastShadow = false
		table.insert(parts, knob)
	end

	-- Brake disc on one side.
	local discX = centre + Vector3.new(discSide * (width / 2 + 0.06), 0, 0)
	local discStyle = setup.Options.DiscStyle or "Solid"
	table.insert(parts, disc(model, "BrakeDisc", discX, discRadius, 0.04, METAL_LIGHT, Enum.Material.Metal))
	if discStyle == "Wave" then
		for i = 1, 8 do
			local angle = (i / 8) * math.pi * 2
			table.insert(parts, newPart(model, "DiscWave", Vector3.new(0.05, 0.12, 0.2), CFrame.new(discX) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, discRadius - 0.04, 0), METAL_DARK, Enum.Material.Metal))
		end
	elseif discStyle == "Drilled" then
		for i = 1, 10 do
			local angle = (i / 10) * math.pi * 2
			local hole = disc(model, "DiscHole", discX + Vector3.new(0, math.cos(angle), math.sin(angle)) * discRadius * 0.7, 0.045, 0.05, Color3.fromRGB(20, 20, 20), nil)
			hole.CastShadow = false
			table.insert(parts, hole)
		end
	end
	table.insert(parts, disc(model, "DiscCarrier", discX, discRadius * 0.45, 0.05, METAL_DARK, Enum.Material.Metal))

	for _, part in parts do
		weldTo(part, hubPart)
	end
end

function BikeBuilder.build(bikeId: string, setupIn: BikeStats.BikeSetup?, options: BuildOptions?): Model
	local def = BikeDefinitions.get(bikeId) or BikeDefinitions.get(BikeDefinitions.StarterBike)
	assert(def, "missing bike definition")
	local setup = setupIn or BikeStats.defaultSetup(def.Id)
	local stats = BikeStats.compute(def.Id, setup)
	local g = stats.Geometry
	local opts: BuildOptions = options or {}

	local model = Instance.new("Model")
	model.Name = opts.Name or ("Bike_" .. def.Id)

	local WB = g.Wheelbase
	local L = WB / 4.0 -- length scale relative to the reference 4-stud wheelbase
	local r = g.WheelRadius
	local axleY = -(g.MountDrop + g.SuspensionRest - g.StaticSag)
	local groundY = axleY - r
	local function P(x: number, z: number, heightAboveGround: number): Vector3
		return Vector3.new(x, groundY + heightAboveGround, z * L)
	end
	local frontAxle = Vector3.new(0, axleY, -WB / 2)
	local rearAxle = Vector3.new(0, axleY, WB / 2)

	local frameColour, frameMaterial = paint(setup, "Frame")
	local plasticColour, plasticMaterial = paint(setup, "Plastics")
	local batteryColour, batteryMaterial = paint(setup, "BatteryCover")
	local seatColour, seatMaterial = paint(setup, "Seat")
	local forkColour, forkMaterial = paint(setup, "Forks")
	local guardColour, guardMaterial = paint(setup, "Mudguards")
	local swingColour, swingMaterial = paint(setup, "Swingarm")
	local barColour, barMaterial = paint(setup, "Bars")
	local gripColour = paint(setup, "Grips")
	local stemColour, stemMaterial = paint(setup, "Stem")
	local padColour = paint(setup, "BarPad")
	local chainColour = paint(setup, "Chain")
	local headlightColour = paint(setup, "Headlight")

	------------------------------------------------------------------ chassis (mass carrier)
	local chassis = newPart(model, "Chassis", PhysicsConfig.Geometry.ChassisSize, CFrame.identity, Color3.new(), nil)
	chassis.Transparency = 1
	chassis.Massless = false
	chassis.CanCollide = false
	chassis.CanQuery = false
	chassis.CastShadow = false
	chassis.RootPriority = 127
	chassis.CustomPhysicalProperties = PhysicalProperties.new(PhysicsConfig.Geometry.ChassisDensity, 0.3, 0.1)
	model.PrimaryPart = chassis

	local hull = newPart(model, "Hull", PhysicsConfig.Geometry.HullSize, CFrame.new(PhysicsConfig.Geometry.HullOffset * Vector3.new(1, 1, L)), Color3.new(), nil)
	hull.Transparency = 1
	hull.CanCollide = true
	hull.CanTouch = true
	hull.CastShadow = false
	hull.CustomPhysicalProperties = PhysicalProperties.new(1, 0.4, 0.2)
	weldTo(hull, chassis)

	local bodyParts: { BasePart } = {}
	local function body(part: BasePart): BasePart
		table.insert(bodyParts, part)
		return part
	end

	------------------------------------------------------------------ frame and body
	local meshes = findBodyMeshes()
	local style = def.Style
	local batterySize = if style.BodyShape == "Bulky"
		then Vector3.new(0.82, 1.2, 1.7)
		elseif style.BodyShape == "Slim" then Vector3.new(0.66, 0.95, 1.45)
		elseif style.BodyShape == "MX" then Vector3.new(0.7, 1.0, 1.5)
		else Vector3.new(0.72, 1.05, 1.55)
	-- The mesh body is modelled on the Standard frame, so the head and seat must match it.
	local frameShape = if meshes then "Standard" else style.FrameShape
	local headTopH = if frameShape == "Tall" then 3.1 elseif frameShape == "MX" then 3.15 else 3.0
	local seatH = if frameShape == "MX" then 3.1 else 3.0

	-- Steering axis: from the front axle up to the head, raked back ~18°.
	local rake = math.rad(18.5)
	local axisUp = Vector3.new(0, math.cos(rake), math.sin(rake))
	local forkLength = (headTopH - r) / math.cos(rake)
	local headTop = frontAxle + axisUp * forkLength
	local headBottom = headTop - axisUp * 0.6

	-- Twin main spars from the head down to the swingarm pivot, and top rails to the tail.
	local pivot = P(0, 0.6, 1.3)
	if meshes then
		body(bodyMesh(model, meshes.Frame, "Frame", L, groundY, frameColour, frameMaterial or Enum.Material.Metal))
		body(bodyMesh(model, meshes.BatteryCover, "BatteryCover", L, groundY, batteryColour, batteryMaterial))
		body(bodyMesh(model, meshes.Plastics, "Plastics", L, groundY, plasticColour, plasticMaterial))
		body(bodyMesh(model, meshes.Seat, "Seat", L, groundY, seatColour, if setup.Options.SeatDesign == "Gripper" then Enum.Material.Fabric else (seatMaterial or Enum.Material.Leather)))
		body(bodyMesh(model, meshes.Mudguards, "Mudguards", L, groundY, guardColour, guardMaterial))
	end
	local partSides: { number } = if meshes then {} else { -1, 1 }
	for _, side in partSides do
		body(beam(model, "FrameSpar", headBottom + Vector3.new(side * 0.34, 0, 0), pivot + Vector3.new(side * 0.36, 0.1, 0), 0.16, 0.42, frameColour, frameMaterial or Enum.Material.Metal))
		body(beam(model, "FrameTopRail", headTop + Vector3.new(side * 0.26, -0.08, 0.05), P(side * 0.3, -0.15, seatH - 0.3), 0.12, 0.2, frameColour, frameMaterial or Enum.Material.Metal))
		body(beam(model, "Subframe", P(side * 0.3, -0.15, seatH - 0.3), P(side * 0.28, 1.95, seatH - 0.28), 0.1, 0.14, frameColour, frameMaterial or Enum.Material.Metal))
		body(beam(model, "SubframeStay", pivot + Vector3.new(side * 0.32, 0.25, 0.1), P(side * 0.28, 1.3, seatH - 0.3), 0.08, 0.1, frameColour, frameMaterial or Enum.Material.Metal))
	end
	local batteryCentre = P(0, -0.45, 1.6 + batterySize.Y / 2)
	if not meshes then
		body(tube(model, "HeadTube", headBottom - axisUp * 0.1, headTop + axisUp * 0.05, 0.17, frameColour, frameMaterial or Enum.Material.Metal))
		body(newPart(model, "Battery", batterySize, CFrame.new(batteryCentre), batteryColour, batteryMaterial or Enum.Material.SmoothPlastic))
		body(newPart(model, "BatteryLid", Vector3.new(batterySize.X + 0.04, 0.08, batterySize.Z * 0.9), CFrame.new(batteryCentre + Vector3.new(0, batterySize.Y / 2, 0)), METAL_DARK, Enum.Material.Metal))
	end
	body(newPart(model, "Controller", Vector3.new(0.5, 0.28, 0.7), CFrame.new(P(0, 0.35, 2.3)), Color3.fromRGB(20, 20, 22), Enum.Material.Metal))
	body(disc(model, "MotorHousing", P(0, 0.55, 1.35), 0.38, 0.56, METAL_DARK, Enum.Material.Metal))
	body(disc(model, "MotorCap", P(-0.3, 0.55, 1.35), 0.26, 0.06, METAL_LIGHT, Enum.Material.Metal))
	body(newPart(model, "Skidplate", Vector3.new(0.7, 0.08, batterySize.Z + 0.2), CFrame.new(batteryCentre - Vector3.new(0, batterySize.Y / 2 + 0.06, 0)), METAL_LIGHT, Enum.Material.Metal))

	-- Side plastics wrapping the top of the battery, plus the tail section.
	for _, side in partSides do
		local panelCf = CFrame.new(P(side * (batterySize.X / 2 + 0.05), -0.35, 2.45)) * CFrame.Angles(math.rad(-8), 0, 0)
		body(newPart(model, "SidePanel", Vector3.new(0.06, 0.6, batterySize.Z + 0.25), panelCf, plasticColour, plasticMaterial))
		body(newPart(model, "TailPanel", Vector3.new(0.06, 0.32, 1.5), CFrame.new(P(side * 0.32, 1.35, seatH - 0.35)) * CFrame.Angles(math.rad(6), 0, 0), plasticColour, plasticMaterial))
	end
	if not meshes then
		body(newPart(model, "FrontShroud", Vector3.new(batterySize.X + 0.2, 0.55, 0.35), CFrame.new(P(0, -1.18, 2.6)) * CFrame.Angles(math.rad(25), 0, 0), plasticColour, plasticMaterial))
	end

	-- Seat: long flat dirt-bike saddle.
	local seatLength = 1.95
	local seatCentre = P(0, 0.55, seatH - 0.12)
	local seatMat = if setup.Options.SeatDesign == "Gripper" then Enum.Material.Fabric else (seatMaterial or Enum.Material.Leather)
	if not meshes then
		body(newPart(model, "SeatPad", Vector3.new(0.62, 0.24, seatLength * L), CFrame.new(seatCentre), seatColour, seatMat))
	end
	if setup.Options.SeatDesign == "Ribbed" then
		-- The mesh saddle is narrower and sits a little higher than the part-built one.
		local ribWidth, ribHeight = if meshes then 0.52 else 0.64, if meshes then 0.17 else 0.13
		for i = -2, 2 do
			body(newPart(model, "SeatRib", Vector3.new(ribWidth, 0.05, 0.06), CFrame.new(seatCentre + Vector3.new(0, ribHeight, i * 0.3)), seatColour:Lerp(Color3.new(1, 1, 1), 0.2), Enum.Material.SmoothPlastic))
		end
	end

	-- Tail / rear mudguard, tail light and number plate.
	local tailEnd = P(0, 2.55, seatH - 0.35)
	if not meshes then
		body(newPart(model, "RearMudguard", Vector3.new(0.5, 0.08, 1.4 * L), CFrame.new(P(0, 1.95, seatH - 0.3)) * CFrame.Angles(math.rad(-10), 0, 0), guardColour, guardMaterial))
	end
	local tailLight = body(newPart(model, "TailLight", Vector3.new(0.34, 0.14, 0.08), CFrame.new(tailEnd + Vector3.new(0, -0.02, 0.05)), Color3.fromRGB(120, 10, 10), Enum.Material.SmoothPlastic))
	tailLight.CastShadow = false
	local tailGlow = Instance.new("PointLight")
	tailGlow.Name = "TailGlow"
	tailGlow.Color = Color3.fromRGB(255, 30, 30)
	tailGlow.Range = 6
	tailGlow.Brightness = 0.6
	tailGlow.Shadows = false
	tailGlow.Parent = tailLight
	body(beam(model, "PlateHanger", tailEnd + Vector3.new(0, -0.05, 0), tailEnd + Vector3.new(0, -0.45, 0.2), 0.06, 0.06, METAL_DARK, Enum.Material.Metal))
	local plate = body(newPart(model, "NumberPlate", Vector3.new(0.85, 0.42, 0.04), CFrame.new(tailEnd + Vector3.new(0, -0.55, 0.24)) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(245, 205, 40), Enum.Material.SmoothPlastic))
	local plateGui = Instance.new("SurfaceGui")
	plateGui.Name = "PlateGui"
	plateGui.Face = Enum.NormalId.Back
	plateGui.PixelsPerStud = 120
	plateGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	plateGui.LightInfluence = 1
	plateGui.Parent = plate
	local plateText = Instance.new("TextLabel")
	plateText.Name = "PlateText"
	plateText.BackgroundTransparency = 1
	plateText.Size = UDim2.fromScale(1, 1)
	plateText.Font = Enum.Font.GothamBlack
	plateText.TextScaled = true
	plateText.TextColor3 = Color3.fromRGB(15, 15, 15)
	plateText.Text = ""
	plateText.Parent = plateGui

	-- Footpegs with rider attachments.
	for _, side in { -1, 1 } do
		local peg = body(newPart(model, if side < 0 then "PegL" else "PegR", Vector3.new(0.4, 0.1, 0.18), CFrame.new(P(side * 0.58, 0.35, 1.15)), METAL_LIGHT, Enum.Material.DiamondPlate))
		local attach = Instance.new("Attachment")
		attach.Name = if side < 0 then "PegL" else "PegR"
		attach.Position = Vector3.new(side * 0.05, 0.12, 0.08)
		attach.Parent = peg
		body(beam(model, "PegMount", P(side * 0.36, 0.3, 1.15), P(side * 0.4, 0.35, 1.15), 0.08, 0.08, METAL_DARK, Enum.Material.Metal))
	end

	-- Rear shock: from the frame to the swingarm.
	body(tube(model, "ShockBody", P(0, 0.15, 2.45), P(0, 0.75, 1.75), 0.12, Color3.fromRGB(230, 120, 20), Enum.Material.Metal))
	body(tube(model, "ShockSpring", P(0, 0.4, 2.15), P(0, 0.85, 1.6), 0.17, Color3.fromRGB(255, 200, 30), Enum.Material.Metal))

	-- Decals and reflective trim.
	local decal = setup.Options.Decal or "None"
	local decalColour = Color3.new(1, 1, 1):Lerp(plasticColour, 0.1)
	for _, side in { -1, 1 } do
		-- On the mesh body the decals sit on the side covers instead of the battery.
		local x = if meshes then side * (BikeMeshLayout.PanelOuterX + 0.01) else side * (batterySize.X / 2 + 0.09)
		if decal == "Stripe" then
			body(newPart(model, "DecalStripe", Vector3.new(0.02, 0.1, batterySize.Z + 0.1), CFrame.new(P(x, -0.35, 2.45)) * CFrame.Angles(math.rad(-8), 0, 0), decalColour, Enum.Material.SmoothPlastic))
		elseif decal == "Bolt" then
			local c = P(x, -0.35, 2.45)
			body(beam(model, "DecalBolt", c + Vector3.new(0, 0.22, -0.4), c + Vector3.new(0, 0, 0), 0.02, 0.09, decalColour, Enum.Material.Neon))
			body(beam(model, "DecalBolt", c, c + Vector3.new(0, 0.05, 0.25), 0.02, 0.09, decalColour, Enum.Material.Neon))
			body(beam(model, "DecalBolt", c + Vector3.new(0, 0.05, 0.25), c + Vector3.new(0, -0.22, 0.6), 0.02, 0.09, decalColour, Enum.Material.Neon))
		elseif decal == "Checker" then
			for i = 0, 5 do
				for j = 0, 1 do
					if (i + j) % 2 == 0 then
						body(newPart(model, "DecalCheck", Vector3.new(0.02, 0.14, 0.14), CFrame.new(P(x, -0.9 + i * 0.14, 2.55 + j * 0.14)), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic))
					end
				end
			end
		elseif decal == "Prestige" then
			local c = P(x, -0.35, 2.5)
			body(newPart(model, "DecalCrown", Vector3.new(0.02, 0.12, 0.5), CFrame.new(c), Color3.fromRGB(240, 200, 60), Enum.Material.Neon))
			for i = -1, 1 do
				body(newPart(model, "DecalCrownPoint", Vector3.new(0.02, 0.16, 0.08), CFrame.new(c + Vector3.new(0, 0.13, i * 0.2)), Color3.fromRGB(240, 200, 60), Enum.Material.Neon))
			end
		end
		if setup.Options.Reflective == "On" then
			body(newPart(model, "ReflectiveTrim", Vector3.new(0.02, 0.05, 1.3 * L), CFrame.new(P(side * 0.26, 1.95, seatH - 0.27)) * CFrame.Angles(math.rad(-10), 0, 0), Color3.fromRGB(230, 240, 255), Enum.Material.Neon))
		end
	end

	for _, part in bodyParts do
		weldTo(part, chassis)
	end

	-- Seat the rider sits in. Touch-to-sit is left on; BikeService ejects anyone who isn't the
	-- bike's owner.
	local seat = Instance.new("Seat")
	seat.Name = "Seat"
	seat.Size = Vector3.new(0.9, 0.2, 1.0)
	seat.CFrame = CFrame.new(P(0, 0.5, seatH - 0.1))
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanQuery = false
	seat.Massless = true
	seat.Anchored = false
	seat.Parent = model
	weldTo(seat, chassis)

	------------------------------------------------------------------ swingarm and rear wheel
	local swingCf = CFrame.lookAt(pivot, rearAxle)
	local swingarm = hub(model, "Swingarm", swingCf)
	local armLength = (rearAxle - pivot).Magnitude
	local swingParts: { BasePart } = {}
	for _, side in { -1, 1 } do
		table.insert(swingParts, newPart(model, "SwingarmArm", Vector3.new(0.12, 0.3, armLength + 0.2), swingCf * CFrame.new(side * (g.TyreWidth / 2 + 0.16), 0, -armLength / 2), swingColour, swingMaterial or Enum.Material.Metal))
	end
	table.insert(swingParts, newPart(model, "SwingarmBrace", Vector3.new(g.TyreWidth + 0.44, 0.22, 0.25), swingCf * CFrame.new(0, 0, -0.35), swingColour, swingMaterial or Enum.Material.Metal))
	-- Drive chain/belt on the left: motor sprocket to rear sprocket.
	local motorSprocket = P(-0.36, 0.55, 1.35)
	local rearSprocket = rearAxle + Vector3.new(-0.36, 0, 0)
	table.insert(swingParts, disc(model, "MotorSprocket", motorSprocket, 0.16, 0.05, METAL_LIGHT, Enum.Material.Metal))
	table.insert(swingParts, disc(model, "RearSprocket", rearSprocket, 0.42, 0.05, METAL_LIGHT, Enum.Material.Metal))
	table.insert(swingParts, beam(model, "ChainTop", motorSprocket + Vector3.new(0, 0.16, 0), rearSprocket + Vector3.new(0, 0.42, 0), 0.05, 0.05, chainColour, Enum.Material.Metal))
	table.insert(swingParts, beam(model, "ChainBottom", motorSprocket - Vector3.new(0, 0.16, 0), rearSprocket - Vector3.new(0, 0.42, 0), 0.05, 0.05, chainColour, Enum.Material.Metal))
	table.insert(swingParts, newPart(model, "RearCaliper", Vector3.new(0.12, 0.3, 0.22), CFrame.new(rearAxle + Vector3.new(g.TyreWidth / 2 + 0.12, 0.42, -0.1)), Color3.fromRGB(200, 40, 40), Enum.Material.Metal))
	for _, part in swingParts do
		weldTo(part, swingarm)
	end
	motor("SwingarmJoint", chassis, swingarm, swingCf)

	local rearWheel = hub(model, "RearWheel", CFrame.new(rearAxle))
	buildWheel(model, rearWheel, rearAxle, r, g.TyreWidth, setup, 1, r * 0.48)
	motor("RearWheelJoint", chassis, rearWheel, CFrame.new(rearAxle))

	------------------------------------------------------------------ steering, forks, front wheel
	-- SteerHub frame: Y along the steering axis, -Z pointing forward/up, X to the right.
	local steerCf = CFrame.fromMatrix(headTop, Vector3.xAxis, axisUp)
	local steerHub = hub(model, "SteerHub", steerCf)
	local function S(x: number, y: number, z: number): CFrame
		return steerCf * CFrame.new(x, y, z)
	end
	local steerParts: { BasePart } = {}
	local function steerPart(part: BasePart)
		table.insert(steerParts, part)
	end
	local forkSpread = g.TyreWidth / 2 + 0.17
	steerPart(newPart(model, "TopClamp", Vector3.new(forkSpread * 2 + 0.3, 0.14, 0.35), S(0, 0.05, 0), stemColour, stemMaterial or Enum.Material.Metal))
	steerPart(newPart(model, "BottomClamp", Vector3.new(forkSpread * 2 + 0.3, 0.16, 0.38), S(0, -0.6, 0), stemColour, stemMaterial or Enum.Material.Metal))
	for _, side in { -1, 1 } do
		steerPart(newPart(model, "ForkUpper", Vector3.new(1.35, 0.2, 0.2), S(side * forkSpread, -0.55, 0) * CFrame.Angles(0, 0, math.rad(90)), forkColour, forkMaterial or Enum.Material.Metal, Enum.PartType.Cylinder))
	end

	-- Handlebars.
	local barStyle = setup.Options.HandlebarStyle or "Stock"
	local barRise = if barStyle == "Riser" then 0.85 elseif barStyle == "MX" then 0.72 elseif barStyle == "Flat" then 0.42 else 0.58
	local barHalf = if barStyle == "Flat" then 1.38 elseif barStyle == "MX" then 1.3 else 1.22
	local barBack = 0.22
	steerPart(newPart(model, "Stem", Vector3.new(0.3, barRise, 0.3), S(0, 0.05 + barRise / 2, barBack / 2), stemColour, stemMaterial or Enum.Material.Metal))
	steerPart(newPart(model, "Handlebar", Vector3.new(barHalf * 2, 0.13, 0.13), S(0, 0.08 + barRise, barBack), barColour, barMaterial or Enum.Material.Metal, Enum.PartType.Cylinder))
	if barStyle == "MX" then
		steerPart(newPart(model, "Crossbar", Vector3.new(0.9, 0.09, 0.09), S(0, 0.35 + barRise, barBack), barColour, barMaterial or Enum.Material.Metal, Enum.PartType.Cylinder))
		steerPart(newPart(model, "BarPad", Vector3.new(0.75, 0.18, 0.18), S(0, 0.35 + barRise, barBack), padColour, Enum.Material.Fabric))
	else
		steerPart(newPart(model, "BarPad", Vector3.new(0.6, 0.2, 0.2), S(0, 0.12 + barRise, barBack), padColour, Enum.Material.Fabric))
	end
	for _, side in { -1, 1 } do
		local grip = newPart(model, if side < 0 then "GripL" else "GripR", Vector3.new(0.42, 0.17, 0.17), S(side * (barHalf - 0.2), 0.08 + barRise, barBack), gripColour, Enum.Material.Rubber, Enum.PartType.Cylinder)
		steerPart(grip)
		local attach = Instance.new("Attachment")
		attach.Name = if side < 0 then "GripL" else "GripR"
		attach.Parent = grip
		steerPart(newPart(model, "BrakeLever", Vector3.new(0.5, 0.04, 0.08), S(side * (barHalf - 0.45), 0.1 + barRise, barBack - 0.18), METAL_LIGHT, Enum.Material.Metal))
		steerPart(newPart(model, "Mirror", Vector3.new(0.05, 0.16, 0.24), S(side * (barHalf - 0.55), 0.4 + barRise, barBack), Color3.fromRGB(25, 25, 25), Enum.Material.SmoothPlastic))
	end

	-- Number board with headlight, and the front mudguard.
	steerPart(newPart(model, "NumberBoard", Vector3.new(0.95, 0.95, 0.1), S(0, -0.35, -0.32) * CFrame.Angles(math.rad(-6), 0, 0), plasticColour, plasticMaterial))
	local headlight = newPart(model, "Headlight", Vector3.new(0.08, 0.42, 0.42), S(0, -0.32, -0.39) * CFrame.Angles(0, math.rad(90), 0), headlightColour, Enum.Material.Neon, Enum.PartType.Cylinder)
	headlight.CastShadow = false
	steerPart(headlight)
	local beamLight = Instance.new("SpotLight")
	beamLight.Name = "Beam"
	beamLight.Face = Enum.NormalId.Right -- the cylinder's +X face points forward after the 90° turn
	beamLight.Angle = 70
	beamLight.Range = 48
	beamLight.Brightness = 3
	beamLight.Color = headlightColour:Lerp(Color3.new(1, 1, 1), 0.6)
	beamLight.Shadows = false
	beamLight.Enabled = false
	beamLight.Parent = headlight
	steerPart(newPart(model, "FrontMudguard", Vector3.new(0.45, 0.07, 1.5), S(0, -0.82, -0.25) * CFrame.Angles(math.rad(8), 0, 0), guardColour, guardMaterial))

	for _, part in steerParts do
		weldTo(part, steerHub)
	end
	motor("SteerJoint", chassis, steerHub, steerCf)

	-- Fork lowers slide along the steering axis; the front wheel spins inside them.
	local sliderCf = steerCf * CFrame.new(0, -forkLength, 0)
	local forkSlider = hub(model, "ForkSlider", sliderCf)
	local sliderParts: { BasePart } = {}
	for _, side in { -1, 1 } do
		table.insert(sliderParts, newPart(model, "ForkLower", Vector3.new(1.2, 0.26, 0.26), sliderCf * CFrame.new(side * forkSpread, 0.55, 0) * CFrame.Angles(0, 0, math.rad(90)), METAL_DARK, Enum.Material.Metal, Enum.PartType.Cylinder))
		table.insert(sliderParts, newPart(model, "ForkFoot", Vector3.new(0.2, 0.3, 0.32), sliderCf * CFrame.new(side * forkSpread, 0, 0), METAL_DARK, Enum.Material.Metal))
		if setup.Options.Reflective == "On" then
			table.insert(sliderParts, newPart(model, "ReflectiveTrim", Vector3.new(0.03, 0.6, 0.04), sliderCf * CFrame.new(side * (forkSpread + 0.13), 0.55, -0.05), Color3.fromRGB(230, 240, 255), Enum.Material.Neon))
		end
	end
	table.insert(sliderParts, newPart(model, "FrontCaliper", Vector3.new(0.12, 0.32, 0.24), sliderCf * CFrame.new(-(g.TyreWidth / 2 + 0.12), 0.45, 0.15), Color3.fromRGB(200, 40, 40), Enum.Material.Metal))
	for _, part in sliderParts do
		weldTo(part, forkSlider)
	end
	motor("ForkJoint", steerHub, forkSlider, CFrame.new(0, -forkLength, 0))

	local frontWheel = hub(model, "FrontWheel", sliderCf)
	buildWheel(model, frontWheel, frontAxle, r, g.TyreWidth, setup, -1, r * 0.55)
	motor("FrontWheelJoint", forkSlider, frontWheel, CFrame.identity)

	------------------------------------------------------------------ physics actuators
	local centre = Instance.new("Attachment")
	centre.Name = "Centre"
	centre.Parent = chassis
	local antiGravity = Instance.new("VectorForce")
	antiGravity.Name = "AntiGravity"
	antiGravity.Attachment0 = centre
	antiGravity.ApplyAtCenterOfMass = true
	antiGravity.RelativeTo = Enum.ActuatorRelativeTo.World
	antiGravity.Force = Vector3.zero
	antiGravity.Parent = chassis
	local driveForce = Instance.new("VectorForce")
	driveForce.Name = "DriveForce"
	driveForce.Attachment0 = centre
	driveForce.ApplyAtCenterOfMass = true
	driveForce.RelativeTo = Enum.ActuatorRelativeTo.World
	driveForce.Force = Vector3.zero
	driveForce.Parent = chassis
	local controlTorque = Instance.new("Torque")
	controlTorque.Name = "ControlTorque"
	controlTorque.Attachment0 = centre
	controlTorque.RelativeTo = Enum.ActuatorRelativeTo.World
	controlTorque.Torque = Vector3.zero
	controlTorque.Parent = chassis

	------------------------------------------------------------------ metadata
	model:SetAttribute("BikeId", def.Id)
	model:SetAttribute("Wheelbase", WB)
	model:SetAttribute("WheelRadius", r)
	model:SetAttribute("MountDrop", g.MountDrop)
	model:SetAttribute("SuspensionRest", g.SuspensionRest)
	model:SetAttribute("StaticSag", g.StaticSag)
	model:SetAttribute("ForkLength", forkLength)
	model:SetAttribute("Rake", rake)
	model:SetAttribute("SwingarmLength", armLength)

	if opts.Anchored then
		-- Display models (garage, menu): nothing to sit on, bump into or simulate.
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = part == chassis
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
			end
		end
		seat.Disabled = true
		chassis.Anchored = true
	end

	return model
end

-- Plate text is set separately because the server must filter it first.
function BikeBuilder.setPlateText(model: Model, text: string)
	local plate = model:FindFirstChild("NumberPlate")
	local gui = plate and plate:FindFirstChild("PlateGui")
	local label = gui and gui:FindFirstChild("PlateText")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

return BikeBuilder
