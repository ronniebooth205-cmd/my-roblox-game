--!strict
-- ServerScriptService > Services > BikeService (ModuleScript)
-- Spawning, mounting, parking, recovering and despawning bikes, plus the server's view of
-- each ridden bike (position/pitch samples) that TrickService uses to check wheelie claims.
--
-- Ownership model: a parked bike is anchored (it can't be pushed around or stolen). When its
-- owner mounts, the chassis is unanchored and network ownership goes to that player, whose
-- client runs the physics (BikeController). Only the owner may sit on their bike.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local BikeDefinitions = require(ReplicatedStorage.Shared.BikeDefinitions)
local BikeBuilder = require(ReplicatedStorage.Shared.BikeBuilder)
local BikeStats = require(ReplicatedStorage.Shared.BikeStats)
local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local CustomisationConfig = require(ReplicatedStorage.Shared.CustomisationConfig)
local Utilities = require(ReplicatedStorage.Shared.Utilities)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerDataService = require(script.Parent.PlayerDataService)

local BikeService = {}

local Services: any = nil

export type Sample = { Time: number, Position: Vector3, Pitch: number, Valid: boolean }

local bikes: { [Player]: Model } = {}
local samples: { [Player]: { Sample } } = {}
local lastSafe: { [Player]: CFrame } = {}
local spawnCooldown: { [Player]: number } = {}
local recoverCooldown: { [Player]: number } = {}
local plateCache: { [Player]: { Raw: string, Filtered: string } } = {}
local bikesFolder: Folder
local actionLimiter = Utilities.newRateLimiter(12, 2)
local stateLimiter = Utilities.newRateLimiter(30, 1)
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.CollisionGroup = "BikeRay"

local SAMPLE_INTERVAL = 0.25
local SAMPLE_HISTORY = 180 -- seconds
local POSES = { "Seated", "Standing", "OneHand", "NoHands", "LegOut", "Hype", "Crashed" }
local RIDER_ROOT_HEIGHT_R15 = 1.1
local RIDER_ROOT_HEIGHT_R6 = 1.5

------------------------------------------------------------------------ collision groups

local function setupCollisionGroups()
	local groups = GameConfig.CollisionGroups
	for _, name in { groups.Bikes, groups.Riders, "Characters", "BikeRay" } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	-- Riders pass through everything while seated (their bike's hull does the colliding).
	for _, other in { "Default", groups.Bikes, groups.Riders, "Characters" } do
		PhysicsService:CollisionGroupSetCollidable(groups.Riders, other, false)
	end
	-- Bikes don't collide with each other or with people on foot, so nobody can be rammed.
	PhysicsService:CollisionGroupSetCollidable(groups.Bikes, groups.Bikes, false)
	PhysicsService:CollisionGroupSetCollidable(groups.Bikes, "Characters", false)
	-- Suspension casts only see the world.
	for _, other in { groups.Bikes, groups.Riders, "Characters", "BikeRay" } do
		PhysicsService:CollisionGroupSetCollidable("BikeRay", other, false)
	end
end

local function setCharacterGroup(character: Model, group: string)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

------------------------------------------------------------------------ helpers

local function rideHeight(model: Model): number
	local r = model:GetAttribute("WheelRadius") :: number? or 1.05
	local rest = model:GetAttribute("SuspensionRest") :: number? or 0.9
	local sag = model:GetAttribute("StaticSag") :: number? or 0.3
	local drop = model:GetAttribute("MountDrop") :: number? or 1.3
	return r + rest - sag + drop
end

local function characterParts(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or humanoid.Health <= 0 or not root then
		return character, nil, nil
	end
	return character, humanoid, root
end

local function groundBelow(position: Vector3, extraExclude: { Instance }?): RaycastResult?
	local exclude: { Instance } = { bikesFolder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	if extraExclude then
		for _, item in extraExclude do
			table.insert(exclude, item)
		end
	end
	groundParams.FilterDescendantsInstances = exclude
	return Workspace:Raycast(position + Vector3.new(0, 12, 0), Vector3.new(0, -60, 0), groundParams)
end

-- Is there room for a bike here? Ignores the spawning player's own character.
local function isClear(cf: CFrame, ignore: Model?): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bikesFolder, ignore :: Instance }
	params.RespectCanCollide = true
	local parts = Workspace:GetPartBoundsInBox(cf + Vector3.new(0, 1, 0), GameConfig.Spawning.ClearanceSize, params)
	if #parts > 0 then
		return false
	end
	-- Keep a gap from other bikes too.
	for _, bike in bikesFolder:GetChildren() do
		if bike:IsA("Model") and bike.PrimaryPart and (bike.PrimaryPart.Position - cf.Position).Magnitude < 6 then
			return false
		end
	end
	return true
end

local function placementAt(groundPoint: Vector3, facing: Vector3, height: number): CFrame
	local flat = Vector3.new(facing.X, 0, facing.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	local position = groundPoint + Vector3.new(0, height, 0)
	return CFrame.lookAt(position, position + flat.Unit)
end

local function filteredPlate(player: Player, raw: string): string
	local cached = plateCache[player]
	if cached and cached.Raw == raw then
		return cached.Filtered
	end
	local filtered = ""
	local ok, result = pcall(function()
		local filterResult = TextService:FilterStringAsync(raw, player.UserId, Enum.TextFilterContext.PublicChat)
		return filterResult:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(result) == "string" then
		filtered = result
	end
	plateCache[player] = { Raw = raw, Filtered = filtered }
	return filtered
end

------------------------------------------------------------------------ rider attach/detach

local function addRiderIK(character: Model, humanoid: Humanoid, model: Model)
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end
	local function find(partName: string, attachName: string): Attachment?
		local part = model:FindFirstChild(partName, true)
		return part and part:FindFirstChild(attachName) :: Attachment?
	end
	local chains = {
		{ Name = "LeftHand", Root = "LeftUpperArm", Effector = "LeftHand", Target = find("GripL", "GripL") },
		{ Name = "RightHand", Root = "RightUpperArm", Effector = "RightHand", Target = find("GripR", "GripR") },
		{ Name = "LeftFoot", Root = "LeftUpperLeg", Effector = "LeftFoot", Target = find("PegL", "PegL") },
		{ Name = "RightFoot", Root = "RightUpperLeg", Effector = "RightFoot", Target = find("PegR", "PegR") },
	}
	for _, chain in chains do
		local rootPart = character:FindFirstChild(chain.Root)
		local effector = character:FindFirstChild(chain.Effector)
		if rootPart and effector and chain.Target then
			local ik = Instance.new("IKControl")
			ik.Name = "BikeIK_" .. chain.Name
			ik.Type = Enum.IKControlType.Position
			ik.ChainRoot = rootPart
			ik.EndEffector = effector
			ik.Target = chain.Target
			ik.SmoothTime = 0.05
			ik.Parent = humanoid
		end
	end
end

local function removeRiderIK(humanoid: Humanoid?)
	if not humanoid then
		return
	end
	for _, child in humanoid:GetChildren() do
		if child:IsA("IKControl") and child.Name:sub(1, 7) == "BikeIK_" then
			child:Destroy()
		end
	end
end

local function setRiderPhysics(character: Model, riding: boolean)
	setCharacterGroup(character, if riding then GameConfig.CollisionGroups.Riders else "Characters")
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			-- Massless riders keep the bike's mass and balance point exactly as tuned.
			part.Massless = riding
		end
	end
end

------------------------------------------------------------------------ parking

local function park(model: Model)
	local chassis = model.PrimaryPart
	if not chassis or not chassis.Parent then
		return
	end
	local seat = model:FindFirstChild("Seat") :: Seat?
	if seat and seat.Occupant then
		return
	end
	local cf = chassis.CFrame
	local hit = groundBelow(cf.Position, { model })
	local ground = if hit then hit.Position else cf.Position - Vector3.new(0, rideHeight(model), 0)
	chassis.Anchored = true
	model:PivotTo(placementAt(ground, cf.LookVector, rideHeight(model)))
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	model:SetAttribute("Crashed", false)
	model:SetAttribute("Throttle", 0)
	model:SetAttribute("Brake", 0)
end

------------------------------------------------------------------------ public API

function BikeService.getBike(player: Player): Model?
	local model = bikes[player]
	if model and model.Parent then
		return model
	end
	return nil
end

function BikeService.isRiding(player: Player): boolean
	local model = BikeService.getBike(player)
	local seat = model and model:FindFirstChild("Seat") :: Seat?
	local _, humanoid = characterParts(player)
	return seat ~= nil and humanoid ~= nil and seat.Occupant == humanoid
end

function BikeService.getSamples(player: Player): { Sample }
	return samples[player] or {}
end

function BikeService.despawn(player: Player)
	local model = bikes[player]
	bikes[player] = nil
	if model then
		local seat = model:FindFirstChild("Seat") :: Seat?
		local weld = seat and seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		model:Destroy()
	end
end

-- `cf` is a point on the ground and the direction the bike should face.
local function build(player: Player, cf: CFrame): Model?
	local profile = PlayerDataService.get(player)
	if not profile then
		return nil
	end
	local bikeId = profile.EquippedBike
	local def = BikeDefinitions.get(bikeId)
	if not def or not profile.OwnedBikes[bikeId] then
		return nil
	end
	local setup = PlayerDataService.setupFor(player, bikeId)
	local model = BikeBuilder.build(bikeId, setup, { Name = "Bike_" .. player.Name })
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("OwnerName", player.DisplayName)
	model:SetAttribute("Headlight", false)
	model:SetAttribute("Pose", "Seated")
	local chassis = model.PrimaryPart :: BasePart
	chassis.Anchored = true
	model:PivotTo(placementAt(cf.Position, cf.LookVector, rideHeight(model)))
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = GameConfig.CollisionGroups.Bikes
		end
	end
	CollectionService:AddTag(model, "SurronBike")
	model.Parent = bikesFolder

	local seat = model:FindFirstChild("Seat") :: Seat
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		BikeService._onOccupantChanged(player, model, seat)
	end)

	local plate = if setup and type(setup.Plate) == "string" then setup.Plate else CustomisationConfig.Plate.Default
	task.spawn(function()
		local text = filteredPlate(player, plate)
		if model.Parent then
			BikeBuilder.setPlateText(model, text)
		end
	end)
	return model
end

-- Finds a free spot: in front of the player, else the nearest free bike bay at the meet.
local function findSpawnSpot(player: Player): CFrame?
	local character, _, root = characterParts(player)
	local candidates: { CFrame } = {}
	if root then
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
		local side = look:Cross(Vector3.yAxis)
		for _, offset in { look * GameConfig.Spawning.ForwardOffset, side * 6, -side * 6, -look * 6 } do
			local hit = groundBelow(root.Position + offset)
			if hit and hit.Normal.Y > 0.85 then
				table.insert(candidates, CFrame.lookAt(hit.Position, hit.Position + look))
			end
		end
	end
	local bays = table.clone(MapLayout.Places.BikeBays)
	if root then
		local from = root.Position
		table.sort(bays, function(a, b)
			return (a - from).Magnitude < (b - from).Magnitude
		end)
	end
	for _, bay in bays do
		local hit = groundBelow(bay)
		local point = if hit then hit.Position else bay
		table.insert(candidates, CFrame.lookAt(point, point + Vector3.new(0, 0, -1)))
	end
	for _, cf in candidates do
		if isClear(cf, character) then
			return cf
		end
	end
	return candidates[#candidates]
end

function BikeService.spawn(player: Player, autoMount: boolean): (boolean, string?)
	local now = os.clock()
	if now < (spawnCooldown[player] or 0) then
		return false, "Wait a moment before spawning again."
	end
	local profile = PlayerDataService.get(player)
	if not profile then
		return false, "Still loading your data."
	end
	local _, humanoid = characterParts(player)
	if not humanoid then
		return false, "Respawn first."
	end
	spawnCooldown[player] = now + GameConfig.Spawning.Cooldown
	local spot = findSpawnSpot(player)
	if not spot then
		return false, "No room to spawn here."
	end
	BikeService.despawn(player)
	local model = build(player, spot)
	if not model then
		return false, "You don't own that bike."
	end
	bikes[player] = model
	samples[player] = {}
	lastSafe[player] = model:GetPivot()
	Remotes.event("BikeSpawned"):FireClient(player, model, "Spawned")
	if autoMount then
		BikeService.mount(player)
	end
	return true, nil
end

function BikeService.mount(player: Player): (boolean, string?)
	local model = BikeService.getBike(player)
	local character, humanoid, root = characterParts(player)
	if not model or not character or not humanoid or not root then
		return false, "No bike to ride."
	end
	local chassis = model.PrimaryPart :: BasePart
	local seat = model:FindFirstChild("Seat") :: Seat
	if seat.Occupant then
		return false, nil
	end
	if (root.Position - chassis.Position).Magnitude > 16 then
		return false, "Get closer to your bike."
	end
	-- The bike stays anchored until the rider's client says its controller is running
	-- ("Release"), so it can't sag or tip in the moment before forces are applied.
	setRiderPhysics(character, true)
	seat:Sit(humanoid)
	return true, nil
end

function BikeService.release(player: Player)
	local model = BikeService.getBike(player)
	if not model or not BikeService.isRiding(player) or model:GetAttribute("Crashed") == true then
		return
	end
	local chassis = model.PrimaryPart :: BasePart
	if chassis.Anchored then
		chassis.Anchored = false
	end
	chassis:SetNetworkOwner(player)
end

function BikeService._onOccupantChanged(owner: Player, model: Model, seat: Seat)
	local occupant = seat.Occupant
	local _, ownerHumanoid = characterParts(owner)
	if occupant and occupant ~= ownerHumanoid then
		-- Someone else touched the seat: only the owner rides their bike.
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		local intruder = occupant.Parent
		if intruder and intruder:IsA("Model") then
			setRiderPhysics(intruder, false)
		end
		return
	end
	local character = owner.Character
	if occupant and character then
		-- Mounted: position the rider, hand physics to the owner, attach hands and feet.
		local weld = seat:FindFirstChild("SeatWeld") or seat:WaitForChild("SeatWeld", 2)
		if weld and weld:IsA("Weld") then
			local rootHeight = if occupant.RigType == Enum.HumanoidRigType.R15 then RIDER_ROOT_HEIGHT_R15 else RIDER_ROOT_HEIGHT_R6
			if weld.Part0 == seat then
				weld.C0 = CFrame.new(0, seat.Size.Y / 2, 0)
				weld.C1 = CFrame.new(0, -rootHeight, 0)
			end
		end
		setRiderPhysics(character, true)
		local chassis = model.PrimaryPart :: BasePart
		if not chassis.Anchored then
			chassis:SetNetworkOwner(owner)
		end
		model:SetAttribute("RiderUserId", owner.UserId)
		-- Normally the rider's client asks for the bike to be released once it is simulating it.
		-- If that message never arrives, release it anyway so the bike can't stay stuck.
		task.delay(1.5, function()
			if model.Parent and seat.Occupant == occupant and chassis.Anchored then
				BikeService.release(owner)
			end
		end)
		removeRiderIK(occupant)
		addRiderIK(character, occupant, model)
		owner:SetAttribute("Riding", true)
	else
		-- Dismounted (or died): restore the character and park the bike once it settles.
		model:SetAttribute("RiderUserId", nil)
		owner:SetAttribute("Riding", false)
		if character then
			setRiderPhysics(character, false)
			removeRiderIK(character:FindFirstChildOfClass("Humanoid"))
		end
		local crashed = model:GetAttribute("Crashed") == true
		task.delay(if crashed then GameConfig.Spawning.AutoRecoverAfterCrash else 0.25, function()
			if model.Parent and not seat.Occupant then
				park(model)
			end
		end)
	end
end

function BikeService.dismount(player: Player)
	local model = BikeService.getBike(player)
	local seat = model and model:FindFirstChild("Seat")
	local weld = seat and seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
end

function BikeService.recover(player: Player): (boolean, string?)
	local now = os.clock()
	if now < (recoverCooldown[player] or 0) then
		return false, nil
	end
	recoverCooldown[player] = now + GameConfig.Spawning.RecoverCooldown
	local model = BikeService.getBike(player)
	if not model then
		return BikeService.spawn(player, true)
	end
	local _, humanoid, root = characterParts(player)
	if not humanoid or not root then
		return false, "Respawn first."
	end
	local chassis = model.PrimaryPart :: BasePart
	local seat = model:FindFirstChild("Seat") :: Seat
	local weld = seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	local target = lastSafe[player] or chassis.CFrame
	local hit = groundBelow(target.Position, { model })
	local ground = if hit then hit.Position else target.Position - Vector3.new(0, rideHeight(model), 0)
	model:SetAttribute("Crashed", false)
	chassis.Anchored = true
	model:PivotTo(placementAt(ground, target.LookVector, rideHeight(model)))
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	Remotes.event("BikeSpawned"):FireClient(player, model, "Recovered")
	-- Put the rider back on, unless they're far away (then they can walk over and press E).
	if (root.Position - chassis.Position).Magnitude < 120 then
		local character = player.Character :: Model
		character:PivotTo(seat.CFrame + Vector3.new(0, 3, 0))
		task.wait(0.1)
		BikeService.mount(player)
	end
	return true, nil
end

-- Rebuilds a parked bike with the player's latest setup (after garage changes).
function BikeService.refreshBike(player: Player)
	local model = BikeService.getBike(player)
	if not model then
		return
	end
	local seat = model:FindFirstChild("Seat") :: Seat?
	if seat and seat.Occupant then
		return -- don't yank a moving bike; changes apply when they next park or respawn
	end
	local pivot = model:GetPivot()
	BikeService.despawn(player)
	local newModel = build(player, pivot)
	if newModel then
		bikes[player] = newModel
		newModel:PivotTo(pivot)
		Remotes.event("BikeSpawned"):FireClient(player, newModel, "Refreshed")
	end
end

------------------------------------------------------------------------ remotes

local function onBikeAction(player: Player, action: any, arg: any)
	if type(action) ~= "string" or not actionLimiter:check(player) then
		return
	end
	local ok, message = true, nil
	if action == "Spawn" then
		ok, message = BikeService.spawn(player, arg ~= false)
	elseif action == "Despawn" then
		BikeService.despawn(player)
	elseif action == "Mount" then
		ok, message = BikeService.mount(player)
	elseif action == "Release" then
		BikeService.release(player)
	elseif action == "Dismount" then
		BikeService.dismount(player)
	elseif action == "Recover" then
		ok, message = BikeService.recover(player)
	elseif action == "Headlight" then
		local model = BikeService.getBike(player)
		if model then
			model:SetAttribute("Headlight", arg == true)
		end
	elseif action == "Crash" then
		local model = BikeService.getBike(player)
		if model and BikeService.isRiding(player) then
			model:SetAttribute("Crashed", true)
			model:SetAttribute("Pose", "Crashed")
			local profile = PlayerDataService.get(player)
			if profile then
				profile.Stats.Crashes += 1
			end
			if Services.ChallengeService then
				Services.ChallengeService.onCrash(player)
			end
			BikeService.dismount(player)
		end
	end
	if not ok and message then
		Remotes.event("Notify"):FireClient(player, { Text = message, Kind = "Warning" })
	end
end

local function onBikeState(player: Player, payload: any)
	if type(payload) ~= "table" or not stateLimiter:check(player) then
		return
	end
	local model = BikeService.getBike(player)
	if not model or model:GetAttribute("RiderUserId") ~= player.UserId then
		return
	end
	local function num(value: any, lo: number, hi: number): number
		if type(value) ~= "number" or value ~= value then
			return 0
		end
		return math.clamp(math.floor(value * 100 + 0.5) / 100, lo, hi)
	end
	model:SetAttribute("Steer", num(payload.Steer, -1, 1))
	model:SetAttribute("Throttle", num(payload.Throttle, 0, 1))
	model:SetAttribute("Lean", num(payload.Lean, -1, 1))
	model:SetAttribute("Brake", num(payload.Brake, 0, 1))
	model:SetAttribute("Wheelie", payload.Wheelie == true)
	-- Poses combine ("Standing,OneHand"); every part must be a known pose.
	if type(payload.Pose) == "string" and #payload.Pose <= 64 and model:GetAttribute("Crashed") ~= true then
		local valid = true
		for part in payload.Pose:gmatch("[^,]+") do
			if not table.find(POSES, part) then
				valid = false
			end
		end
		if valid then
			model:SetAttribute("Pose", payload.Pose)
		end
	end
end

------------------------------------------------------------------------ sampling

local function sampleBikes()
	local now = os.clock()
	for player, model in bikes do
		local chassis = model.PrimaryPart
		if not chassis or not model.Parent then
			continue
		end
		local list = samples[player]
		if not list then
			list = {}
			samples[player] = list
		end
		local cf = chassis.CFrame
		local previous = list[#list]
		local valid = true
		local riding = model:GetAttribute("RiderUserId") == player.UserId
		if previous then
			local dt = now - previous.Time
			local moved = Vector3.new(cf.Position.X - previous.Position.X, 0, cf.Position.Z - previous.Position.Z).Magnitude
			local profile = PlayerDataService.get(player)
			local stats = BikeStats.compute(model:GetAttribute("BikeId") :: string, profile and profile.BikeSetups[model:GetAttribute("BikeId") :: string])
			-- Anything faster than the bike could possibly go is a teleport (recover, or an
			-- exploit): it doesn't count towards distances.
			if moved > stats.Handling.TopSpeed * 1.4 * dt + 4 then
				valid = false
			end
			if riding and valid and moved > 0.05 then
				local metres = Utilities.studsToMetres(moved)
				if profile then
					profile.Stats.TotalRideDistance += metres
				end
				if Services.ChallengeService then
					Services.ChallengeService.onRide(player, metres)
				end
			end
		end
		table.insert(list, {
			Time = now,
			Position = cf.Position,
			Pitch = Utilities.pitchDegrees(cf),
			Valid = valid,
		})
		while list[1] and now - list[1].Time > SAMPLE_HISTORY do
			table.remove(list, 1)
		end
		-- Remember the last upright spot on the ground for recovery.
		if riding and math.abs(Utilities.pitchDegrees(cf)) < 12 and math.abs(Utilities.rollDegrees(cf)) < 15 then
			local hit = groundBelow(cf.Position, { model })
			if hit and cf.Position.Y - hit.Position.Y < rideHeight(model) + 1.5 then
				lastSafe[player] = cf
			end
		end
	end
end

------------------------------------------------------------------------ lifecycle

function BikeService.init(services: any)
	Services = services
	setupCollisionGroups()
	local existing = Workspace:FindFirstChild("Bikes")
	if existing and existing:IsA("Folder") then
		bikesFolder = existing
	else
		bikesFolder = Instance.new("Folder")
		bikesFolder.Name = "Bikes"
		bikesFolder.Parent = Workspace
	end
	Remotes.event("BikeAction").OnServerEvent:Connect(onBikeAction)
	Remotes.unreliable("BikeState").OnServerEvent:Connect(onBikeState)
end

function BikeService.start()
	local function onCharacter(player: Player, character: Model)
		setCharacterGroup(character, "Characters")
		character.DescendantAdded:Connect(function(part)
			if part:IsA("BasePart") then
				part.CollisionGroup = if player:GetAttribute("Riding") then GameConfig.CollisionGroups.Riders else "Characters"
			end
		end)
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			onCharacter(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		BikeService.despawn(player)
		samples[player] = nil
		lastSafe[player] = nil
		spawnCooldown[player] = nil
		recoverCooldown[player] = nil
		plateCache[player] = nil
		actionLimiter:clear(player)
		stateLimiter:clear(player)
	end)
	task.spawn(function()
		while true do
			task.wait(SAMPLE_INTERVAL)
			local ok, err = pcall(sampleBikes)
			if not ok then
				warn("[BikeService] sampling error:", err)
			end
		end
	end)
end

return BikeService
