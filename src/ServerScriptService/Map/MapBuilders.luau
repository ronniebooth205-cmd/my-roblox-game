--!strict
-- ServerScriptService > Map > MapBuilders (ModuleScript)
-- Building blocks for the generated city: buildings, street furniture, vehicles and greenery,
-- all made from plain anchored parts with original, fictional signage. Kept low on part count
-- (a terraced house is ~10 parts) so the whole map stays light enough for phones.

local MapBuilders = {}

MapBuilders.Palette = {
	Brick = { Color3.fromRGB(142, 74, 56), Color3.fromRGB(160, 92, 66), Color3.fromRGB(122, 64, 50), Color3.fromRGB(176, 118, 86), Color3.fromRGB(150, 140, 128) },
	Render = { Color3.fromRGB(230, 226, 214), Color3.fromRGB(214, 208, 190), Color3.fromRGB(196, 210, 214) },
	Roof = { Color3.fromRGB(60, 60, 66), Color3.fromRGB(88, 62, 52), Color3.fromRGB(70, 74, 82) },
	Door = { Color3.fromRGB(28, 60, 110), Color3.fromRGB(120, 24, 30), Color3.fromRGB(30, 30, 30), Color3.fromRGB(40, 90, 50), Color3.fromRGB(236, 236, 236) },
	Car = { Color3.fromRGB(200, 200, 205), Color3.fromRGB(30, 30, 34), Color3.fromRGB(150, 20, 24), Color3.fromRGB(30, 60, 140), Color3.fromRGB(240, 240, 240), Color3.fromRGB(90, 96, 104), Color3.fromRGB(20, 80, 60) },
	Glass = Color3.fromRGB(120, 160, 190),
	Volt = Color3.fromRGB(57, 255, 136),
}

local GLASS = MapBuilders.Palette.Glass

function MapBuilders.part(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material?, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = collide ~= false
	if collide == false then
		p.CanQuery = false
		p.CanTouch = false
	end
	p.Parent = parent
	return p
end
local part = MapBuilders.part

function MapBuilders.cylinder(parent: Instance, name: string, length: number, radius: number, cf: CFrame, colour: Color3, material: Enum.Material?, collide: boolean?): Part
	local p = part(parent, name, Vector3.new(length, radius * 2, radius * 2), cf, colour, material, collide)
	p.Shape = Enum.PartType.Cylinder
	return p
end

function MapBuilders.wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material?): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = size
	w.CFrame = cf
	w.Color = colour
	w.Material = material or Enum.Material.SmoothPlastic
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Parent = parent
	return w
end

function MapBuilders.model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- A SurfaceGui text sign on one face of a part.
function MapBuilders.label(target: BasePart, face: Enum.NormalId, text: string, textColour: Color3, font: Enum.Font?, background: Color3?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0.2
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if background then 0 else 1
	label.BackgroundColor3 = background or Color3.new()
	label.Text = text
	label.TextScaled = true
	label.Font = font or Enum.Font.GothamBlack
	label.TextColor3 = textColour
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.1, 0)
	padding.PaddingBottom = UDim.new(0.1, 0)
	padding.Parent = label
	return label
end

------------------------------------------------------------------------ buildings
-- All building functions take a CFrame at ground level, centred on the footprint, with the
-- front (door/shopfront) facing the CFrame's LookVector.

function MapBuilders.windows(parent: Instance, base: CFrame, width: number, height: number, depth: number, floors: number, startFloor: number, rng: Random)
	local perFloor = math.max(1, math.floor(width / 9))
	local floorHeight = height / floors
	for floor = startFloor, floors - 1 do
		for i = 1, perFloor do
			local x = -width / 2 + (i - 0.5) * (width / perFloor)
			local y = floor * floorHeight + floorHeight * 0.55
			part(parent, "Window", Vector3.new(3.4, 4.2, 0.3), base * CFrame.new(x, y, -depth / 2 - 0.1), GLASS, Enum.Material.Glass, false).Transparency = 0.2
			part(parent, "Sill", Vector3.new(3.8, 0.3, 0.5), base * CFrame.new(x, y - 2.25, -depth / 2 - 0.2), Color3.fromRGB(225, 225, 220), Enum.Material.Concrete, false)
		end
	end
	if rng:NextNumber() < 0.3 then
		-- some back windows too, so buildings don't look like cardboard from behind
		for i = 1, perFloor do
			local x = -width / 2 + (i - 0.5) * (width / perFloor)
			part(parent, "Window", Vector3.new(3.4, 4.2, 0.3), base * CFrame.new(x, floorHeight * 1.55, depth / 2 + 0.1), GLASS, Enum.Material.Glass, false).Transparency = 0.2
		end
	end
end

function MapBuilders.pitchedRoof(parent: Instance, base: CFrame, width: number, depth: number, wallHeight: number, roofHeight: number, colour: Color3)
	local half = depth / 2 + 0.6
	MapBuilders.wedge(parent, "Roof", Vector3.new(width + 1, roofHeight, half), base * CFrame.new(0, wallHeight + roofHeight / 2, -half / 2), colour, Enum.Material.RoofShingles)
	MapBuilders.wedge(parent, "Roof", Vector3.new(width + 1, roofHeight, half), base * CFrame.new(0, wallHeight + roofHeight / 2, half / 2) * CFrame.Angles(0, math.pi, 0), colour, Enum.Material.RoofShingles)
end

-- A house: brick or rendered walls, pitched roof, door, windows, chimney.
function MapBuilders.house(parent: Instance, base: CFrame, width: number, depth: number, rng: Random, options: { [string]: any }?): Model
	local opts = options or {}
	local m = MapBuilders.model(parent, "House")
	local palette = MapBuilders.Palette
	local rendered = rng:NextNumber() < 0.25
	local wallColour = opts.Colour or (if rendered then palette.Render[rng:NextInteger(1, #palette.Render)] else palette.Brick[rng:NextInteger(1, #palette.Brick)])
	local height = opts.Height or 18
	part(m, "Walls", Vector3.new(width, height, depth), base * CFrame.new(0, height / 2, 0), wallColour, if rendered then Enum.Material.Plaster else Enum.Material.Brick)
	MapBuilders.pitchedRoof(m, base, width, depth, height, opts.RoofHeight or 7, palette.Roof[rng:NextInteger(1, #palette.Roof)])
	part(m, "Door", Vector3.new(3.4, 7, 0.3), base * CFrame.new(opts.DoorOffset or -width / 4, 3.5, -depth / 2 - 0.1), palette.Door[rng:NextInteger(1, #palette.Door)], Enum.Material.Wood, false)
	part(m, "Step", Vector3.new(4.5, 0.6, 2), base * CFrame.new(opts.DoorOffset or -width / 4, 0.3, -depth / 2 - 1), Color3.fromRGB(190, 190, 185), Enum.Material.Concrete)
	MapBuilders.windows(m, base, width, height, depth, 2, 0, rng)
	if opts.Chimney ~= false then
		part(m, "Chimney", Vector3.new(2.2, 6, 2.2), base * CFrame.new(width / 2 - 2, height + 5, 1), wallColour, Enum.Material.Brick)
	end
	return m
end

-- A row of terraced houses sharing walls, each with a small front wall.
function MapBuilders.terrace(parent: Instance, base: CFrame, count: number, houseWidth: number, depth: number, rng: Random): Model
	local m = MapBuilders.model(parent, "Terrace")
	local palette = MapBuilders.Palette
	local brick = palette.Brick[rng:NextInteger(1, #palette.Brick)]
	local total = count * houseWidth
	for i = 1, count do
		local x = -total / 2 + (i - 0.5) * houseWidth
		local colour = if rng:NextNumber() < 0.2 then palette.Render[rng:NextInteger(1, #palette.Render)] else brick
		MapBuilders.house(m, base * CFrame.new(x, 0, 0), houseWidth, depth, rng, { Colour = colour, Chimney = i % 2 == 0, DoorOffset = if i % 2 == 0 then houseWidth / 4 else -houseWidth / 4 })
		-- Low brick front garden wall with a gap for the path.
		part(m, "FrontWall", Vector3.new(houseWidth - 4, 2.2, 0.8), base * CFrame.new(x + (if i % 2 == 0 then -2 else 2), 1.1, -depth / 2 - 6), brick, Enum.Material.Brick)
	end
	return m
end

function MapBuilders.shop(parent: Instance, base: CFrame, width: number, depth: number, name: string, signColour: Color3, rng: Random): Model
	local m = MapBuilders.model(parent, "Shop_" .. name)
	local palette = MapBuilders.Palette
	local height = 22
	local wall = palette.Brick[rng:NextInteger(1, #palette.Brick)]
	part(m, "Walls", Vector3.new(width, height, depth), base * CFrame.new(0, height / 2, 0), wall, Enum.Material.Brick)
	part(m, "Parapet", Vector3.new(width + 0.4, 1.5, depth + 0.4), base * CFrame.new(0, height + 0.75, 0), wall:Lerp(Color3.new(1, 1, 1), 0.15), Enum.Material.Concrete)
	local front = part(m, "Shopfront", Vector3.new(width - 3, 8, 0.4), base * CFrame.new(0, 5, -depth / 2 - 0.15), GLASS, Enum.Material.Glass, false)
	front.Transparency = 0.25
	part(m, "ShopDoor", Vector3.new(4, 7.5, 0.5), base * CFrame.new(width / 2 - 4, 3.75, -depth / 2 - 0.2), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, false)
	local sign = part(m, "Sign", Vector3.new(width - 2, 3.4, 0.6), base * CFrame.new(0, 10.6, -depth / 2 - 0.35), signColour, Enum.Material.SmoothPlastic)
	MapBuilders.label(sign, Enum.NormalId.Front, name, Color3.new(1, 1, 1))
	part(m, "Awning", Vector3.new(width - 2, 0.4, 3), base * CFrame.new(0, 8.8, -depth / 2 - 1.6) * CFrame.Angles(math.rad(12), 0, 0), signColour:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Fabric, false)
	MapBuilders.windows(m, base, width, height, depth, 2, 1, rng)
	return m
end

function MapBuilders.warehouse(parent: Instance, base: CFrame, width: number, depth: number, height: number, name: string?, rng: Random): Model
	local m = MapBuilders.model(parent, "Warehouse")
	local colours = { Color3.fromRGB(160, 168, 176), Color3.fromRGB(120, 130, 140), Color3.fromRGB(70, 90, 110), Color3.fromRGB(180, 170, 150) }
	local colour = colours[rng:NextInteger(1, #colours)]
	part(m, "Walls", Vector3.new(width, height, depth), base * CFrame.new(0, height / 2, 0), colour, Enum.Material.CorrodedMetal)
	part(m, "Roof", Vector3.new(width + 1, 1.2, depth + 1), base * CFrame.new(0, height + 0.6, 0), colour:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Metal)
	part(m, "BaseBand", Vector3.new(width + 0.2, 4, depth + 0.2), base * CFrame.new(0, 2, 0), Color3.fromRGB(110, 110, 110), Enum.Material.Concrete)
	local doors = math.max(1, math.floor(width / 36))
	for i = 1, doors do
		local x = -width / 2 + (i - 0.5) * (width / doors)
		part(m, "RollerDoor", Vector3.new(16, 16, 0.4), base * CFrame.new(x, 8, -depth / 2 - 0.15), Color3.fromRGB(200, 200, 205), Enum.Material.DiamondPlate, false)
		-- Loading dock in front of each door, with yellow-and-black bumpers.
		part(m, "Dock", Vector3.new(20, 4, 8), base * CFrame.new(x, 2, -depth / 2 - 4), Color3.fromRGB(150, 150, 150), Enum.Material.Concrete)
		for _, side in { -1, 1 } do
			part(m, "Bumper", Vector3.new(1.2, 2.5, 0.8), base * CFrame.new(x + side * 6, 2.2, -depth / 2 - 8.3), Color3.fromRGB(240, 200, 30), Enum.Material.Rubber)
		end
	end
	if name then
		local sign = part(m, "Sign", Vector3.new(math.min(width * 0.6, 60), 6, 0.5), base * CFrame.new(0, height - 5, -depth / 2 - 0.3), Color3.fromRGB(240, 240, 240))
		MapBuilders.label(sign, Enum.NormalId.Front, name, Color3.fromRGB(20, 40, 80))
	end
	return m
end

function MapBuilders.container(parent: Instance, cf: CFrame, colour: Color3)
	local m = MapBuilders.model(parent, "Container")
	part(m, "Box", Vector3.new(8.4, 8.6, 19), cf * CFrame.new(0, 4.3, 0), colour, Enum.Material.CorrodedMetal)
	part(m, "Doors", Vector3.new(8, 8.2, 0.2), cf * CFrame.new(0, 4.3, 9.55), colour:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.DiamondPlate, false)
	for _, x in { -2, 2 } do
		part(m, "Bar", Vector3.new(0.2, 8, 0.3), cf * CFrame.new(x, 4.3, 9.7), Color3.fromRGB(60, 60, 60), Enum.Material.Metal, false)
	end
end

------------------------------------------------------------------------ vehicles and furniture

function MapBuilders.car(parent: Instance, cf: CFrame, colour: Color3)
	local m = MapBuilders.model(parent, "ParkedCar")
	part(m, "Body", Vector3.new(6, 2.4, 13), cf * CFrame.new(0, 2, 0), colour, Enum.Material.SmoothPlastic)
	part(m, "Cabin", Vector3.new(5.4, 2.2, 7), cf * CFrame.new(0, 4.3, 0.6), colour, Enum.Material.SmoothPlastic)
	local glass = part(m, "Glass", Vector3.new(5.5, 1.7, 7.1), cf * CFrame.new(0, 4.4, 0.6), Color3.fromRGB(40, 50, 60), Enum.Material.Glass, false)
	glass.Transparency = 0.1
	for _, x in { -2.8, 2.8 } do
		for _, z in { -4.2, 4.2 } do
			MapBuilders.cylinder(m, "Wheel", 1, 1.25, cf * CFrame.new(x, 1.25, z), Color3.fromRGB(25, 25, 25), Enum.Material.Rubber, false)
		end
	end
	part(m, "Lights", Vector3.new(5, 0.6, 0.2), cf * CFrame.new(0, 2.3, -6.55), Color3.fromRGB(255, 250, 220), Enum.Material.Neon, false)
	part(m, "Rear", Vector3.new(5, 0.6, 0.2), cf * CFrame.new(0, 2.3, 6.55), Color3.fromRGB(150, 20, 20), Enum.Material.SmoothPlastic, false)
end

function MapBuilders.tree(parent: Instance, position: Vector3, scale: number, rng: Random)
	local m = MapBuilders.model(parent, "Tree")
	local trunkHeight = 10 * scale
	part(m, "Trunk", Vector3.new(1.4 * scale, trunkHeight, 1.4 * scale), CFrame.new(position + Vector3.new(0, trunkHeight / 2, 0)), Color3.fromRGB(96, 70, 48), Enum.Material.Wood)
	local leaf = Color3.fromRGB(58 + rng:NextInteger(-10, 10), 110 + rng:NextInteger(-15, 15), 52)
	local canopy = part(m, "Canopy", Vector3.one * 11 * scale, CFrame.new(position + Vector3.new(0, trunkHeight + 3 * scale, 0)), leaf, Enum.Material.LeafyGrass, false)
	canopy.Shape = Enum.PartType.Ball
	local top = part(m, "Canopy", Vector3.one * 8 * scale, CFrame.new(position + Vector3.new(1.5 * scale, trunkHeight + 7 * scale, -1 * scale)), leaf:Lerp(Color3.new(0.3, 0.6, 0.2), 0.2), Enum.Material.LeafyGrass, false)
	top.Shape = Enum.PartType.Ball
end

function MapBuilders.lamp(parent: Instance, position: Vector3, facing: Vector3)
	local m = MapBuilders.model(parent, "Streetlight")
	local base = CFrame.lookAt(position, position + facing)
	MapBuilders.cylinder(m, "Pole", 18, 0.35, base * CFrame.new(0, 9, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 74, 80), Enum.Material.Metal)
	part(m, "Arm", Vector3.new(0.4, 0.4, 4), base * CFrame.new(0, 17.8, -2), Color3.fromRGB(70, 74, 80), Enum.Material.Metal, false)
	part(m, "Head", Vector3.new(1.4, 0.5, 2.4), base * CFrame.new(0, 17.6, -4), Color3.fromRGB(255, 236, 190), Enum.Material.Neon, false)
end

function MapBuilders.bench(parent: Instance, cf: CFrame)
	local m = MapBuilders.model(parent, "Bench")
	part(m, "Seat", Vector3.new(6, 0.4, 1.8), cf * CFrame.new(0, 1.8, 0), Color3.fromRGB(110, 76, 50), Enum.Material.WoodPlanks)
	part(m, "Back", Vector3.new(6, 1.6, 0.3), cf * CFrame.new(0, 2.9, 0.8), Color3.fromRGB(110, 76, 50), Enum.Material.WoodPlanks, false)
	for _, x in { -2.6, 2.6 } do
		part(m, "Leg", Vector3.new(0.3, 1.8, 1.6), cf * CFrame.new(x, 0.9, 0), Color3.fromRGB(40, 40, 40), Enum.Material.Metal)
	end
end

function MapBuilders.bin(parent: Instance, cf: CFrame, colour: Color3?)
	local m = MapBuilders.model(parent, "WheelieBin")
	part(m, "Body", Vector3.new(2, 3.4, 2.2), cf * CFrame.new(0, 1.7, 0), colour or Color3.fromRGB(40, 40, 44), Enum.Material.SmoothPlastic)
	part(m, "Lid", Vector3.new(2.1, 0.2, 2.4), cf * CFrame.new(0, 3.5, 0), (colour or Color3.fromRGB(40, 40, 44)):Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.SmoothPlastic, false)
end

function MapBuilders.busStop(parent: Instance, cf: CFrame, name: string)
	local m = MapBuilders.model(parent, "BusStop")
	local glass = part(m, "BackPanel", Vector3.new(10, 7, 0.2), cf * CFrame.new(0, 3.5, 1.5), GLASS, Enum.Material.Glass)
	glass.Transparency = 0.5
	part(m, "Roof", Vector3.new(11, 0.4, 4), cf * CFrame.new(0, 7.2, 0), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
	for _, x in { -5, 5 } do
		part(m, "Post", Vector3.new(0.3, 7, 0.3), cf * CFrame.new(x, 3.5, 1.5), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
	end
	part(m, "Bench", Vector3.new(6, 0.3, 1.2), cf * CFrame.new(0, 1.8, 0.9), Color3.fromRGB(80, 80, 85), Enum.Material.Metal)
	part(m, "SignPole", Vector3.new(0.3, 10, 0.3), cf * CFrame.new(-6.5, 5, -1), Color3.fromRGB(120, 120, 120), Enum.Material.Metal)
	local flag = part(m, "Flag", Vector3.new(0.2, 2, 2.4), cf * CFrame.new(-6.5, 9, -1), Color3.fromRGB(200, 30, 40), Enum.Material.SmoothPlastic, false)
	MapBuilders.label(flag, Enum.NormalId.Left, "BUS", Color3.new(1, 1, 1))
	MapBuilders.label(glass, Enum.NormalId.Front, name, Color3.fromRGB(20, 20, 20), Enum.Font.GothamBold)
end

function MapBuilders.phoneBox(parent: Instance, cf: CFrame)
	local m = MapBuilders.model(parent, "PhoneBox")
	local red = Color3.fromRGB(196, 22, 28)
	part(m, "Box", Vector3.new(3.2, 8, 3.2), cf * CFrame.new(0, 4, 0), red, Enum.Material.SmoothPlastic)
	part(m, "Top", Vector3.new(3.6, 0.6, 3.6), cf * CFrame.new(0, 8.3, 0), red, Enum.Material.SmoothPlastic)
	local glass = part(m, "Glass", Vector3.new(2.4, 4.5, 0.2), cf * CFrame.new(0, 4.4, -1.65), GLASS, Enum.Material.Glass, false)
	glass.Transparency = 0.4
end

function MapBuilders.postBox(parent: Instance, cf: CFrame)
	local m = MapBuilders.model(parent, "PostBox")
	MapBuilders.cylinder(m, "Body", 4.4, 0.9, cf * CFrame.new(0, 2.2, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(196, 22, 28), Enum.Material.Metal)
	local cap = part(m, "Cap", Vector3.new(2, 0.8, 2), cf * CFrame.new(0, 4.6, 0), Color3.fromRGB(196, 22, 28), Enum.Material.Metal)
	cap.Shape = Enum.PartType.Ball
end

-- Belisha beacon: the striped pole with an amber globe at UK zebra crossings.
function MapBuilders.belisha(parent: Instance, position: Vector3)
	local m = MapBuilders.model(parent, "Belisha")
	for i = 0, 4 do
		local colour = if i % 2 == 0 then Color3.new(0.1, 0.1, 0.1) else Color3.new(0.95, 0.95, 0.95)
		MapBuilders.cylinder(m, "Pole", 1.8, 0.2, CFrame.new(position + Vector3.new(0, 0.9 + i * 1.8, 0)) * CFrame.Angles(0, 0, math.rad(90)), colour, Enum.Material.SmoothPlastic)
	end
	local globe = part(m, "Globe", Vector3.one * 1.4, CFrame.new(position + Vector3.new(0, 9.7, 0)), Color3.fromRGB(255, 170, 30), Enum.Material.Neon, false)
	globe.Shape = Enum.PartType.Ball
end

function MapBuilders.fence(parent: Instance, a: Vector3, b: Vector3, height: number, colour: Color3?, material: Enum.Material?)
	local length = (b - a).Magnitude
	if length < 0.5 then
		return
	end
	local cf = CFrame.lookAt((a + b) / 2, b)
	part(parent, "Fence", Vector3.new(0.4, height, length), cf * CFrame.new(0, height / 2, 0), colour or Color3.fromRGB(120, 90, 60), material or Enum.Material.WoodPlanks)
end

function MapBuilders.hedge(parent: Instance, a: Vector3, b: Vector3, height: number)
	local length = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) / 2, b)
	part(parent, "Hedge", Vector3.new(3, height, length), cf * CFrame.new(0, height / 2, 0), Color3.fromRGB(56, 96, 44), Enum.Material.LeafyGrass)
end

function MapBuilders.streetSign(parent: Instance, position: Vector3, facing: Vector3, text: string)
	local m = MapBuilders.model(parent, "StreetSign")
	local cf = CFrame.lookAt(position, position + facing)
	for _, x in { -2.4, 2.4 } do
		part(m, "Post", Vector3.new(0.25, 3.2, 0.25), cf * CFrame.new(x, 1.6, 0), Color3.fromRGB(40, 40, 40), Enum.Material.Metal)
	end
	local board = part(m, "Board", Vector3.new(6, 1.6, 0.2), cf * CFrame.new(0, 3, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	MapBuilders.label(board, Enum.NormalId.Front, text, Color3.fromRGB(15, 15, 15), Enum.Font.GothamBold)
	MapBuilders.label(board, Enum.NormalId.Back, text, Color3.fromRGB(15, 15, 15), Enum.Font.GothamBold)
end

-- Traffic light post. Lamps are tagged so MapService can cycle them; `group` is "X" or "Z":
-- the axis of the road this light controls.
function MapBuilders.trafficLight(parent: Instance, position: Vector3, facing: Vector3, group: string)
	local CollectionService = game:GetService("CollectionService")
	local m = MapBuilders.model(parent, "TrafficLight")
	local cf = CFrame.lookAt(position, position + facing)
	part(m, "Pole", Vector3.new(0.5, 10, 0.5), cf * CFrame.new(0, 5, 0), Color3.fromRGB(40, 40, 40), Enum.Material.Metal)
	part(m, "Head", Vector3.new(1.6, 4.4, 1.2), cf * CFrame.new(0, 11.6, 0), Color3.fromRGB(25, 25, 25), Enum.Material.Metal)
	local colours = { Red = Color3.fromRGB(255, 40, 30), Amber = Color3.fromRGB(255, 170, 20), Green = Color3.fromRGB(40, 255, 90) }
	for i, name in { "Red", "Amber", "Green" } do
		local lamp = part(m, "Lamp" .. name, Vector3.new(1, 1, 0.3), cf * CFrame.new(0, 13 - (i - 1) * 1.35, -0.6), colours[name], Enum.Material.Neon, false)
		lamp.Shape = Enum.PartType.Cylinder
		lamp.Size = Vector3.new(0.3, 1, 1)
		lamp.CFrame = cf * CFrame.new(0, 13 - (i - 1) * 1.35, -0.62) * CFrame.Angles(0, math.rad(90), 0)
		lamp:SetAttribute("Colour", name)
		lamp:SetAttribute("Group", group)
		lamp:SetAttribute("OnColour", colours[name])
		CollectionService:AddTag(lamp, "TrafficLamp")
	end
end

-- A stand-up board for leaderboards/challenges: returns the SurfaceGui's row container.
function MapBuilders.board(parent: Instance, name: string, cf: CFrame, width: number, height: number, title: string): Frame
	local m = MapBuilders.model(parent, name)
	for _, x in { -width / 2 + 1, width / 2 - 1 } do
		part(m, "Leg", Vector3.new(0.8, 6, 0.8), cf * CFrame.new(x, 3, 0.4), Color3.fromRGB(30, 30, 32), Enum.Material.Metal)
	end
	local panel = part(m, "Panel", Vector3.new(width, height, 0.6), cf * CFrame.new(0, 6 + height / 2, 0), Color3.fromRGB(16, 16, 18), Enum.Material.SmoothPlastic)
	part(m, "Trim", Vector3.new(width + 0.4, 0.4, 0.8), cf * CFrame.new(0, 6 + height + 0.2, 0), MapBuilders.Palette.Volt, Enum.Material.Neon, false)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	gui.Parent = panel
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.fromScale(1, 0.16)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = MapBuilders.Palette.Volt
	titleLabel.Text = title
	titleLabel.Parent = gui
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.fromScale(0.04, 0.18)
	rows.Size = UDim2.fromScale(0.92, 0.8)
	rows.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = rows
	for i = 1, 10 do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Size = UDim2.fromScale(1, 0.1)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.GothamBold
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = Color3.new(1, 1, 1)
		row.Text = ""
		row.Parent = rows
	end
	return rows
end

return MapBuilders
