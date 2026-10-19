--!strict
-- ServerScriptService > Services > MapService (ModuleScript)
-- Builds the city (MapGenerator), sets the lighting, points every player's respawn at the
-- meet, rewards first visits to each zone (exploration), and cycles the traffic lights.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local EconomyConfig = require(ReplicatedStorage.Shared.EconomyConfig)
local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local MapGenerator = require(script.Parent.Parent.Map.MapGenerator)
local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)

local MapService = {}

local Services: any = nil
local spawnLocation: SpawnLocation? = nil

-- The default Baseplate from a new place sits at the same height as our ground and would
-- z-fight with it, so it is hidden for the session (this does not change the saved place).
local HIDE_DEFAULT_BASEPLATE = true

local function setupLighting()
	Lighting.ClockTime = GameConfig.Lighting.ClockTime
	Lighting.Brightness = 2.2
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 132, 140)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.28
		atmosphere.Offset = 0.15
		atmosphere.Color = Color3.fromRGB(200, 210, 222)
		atmosphere.Decay = Color3.fromRGB(110, 120, 135)
		atmosphere.Haze = 1.2
		atmosphere.Parent = Lighting
	end
	if not Lighting:FindFirstChild("SurronGrade") then
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "SurronGrade"
		grade.Contrast = 0.08
		grade.Saturation = 0.05
		grade.Parent = Lighting
	end
end

local function cycleTrafficLights()
	-- X-axis roads go green while Z-axis roads are red, then swap, with amber in between.
	local phases = {
		{ X = "Green", Z = "Red", Time = 8 },
		{ X = "Amber", Z = "Red", Time = 2 },
		{ X = "Red", Z = "Green", Time = 8 },
		{ X = "Red", Z = "Amber", Time = 2 },
	}
	local off = Color3.fromRGB(40, 40, 40)
	while true do
		for _, phase in phases do
			for _, lamp in CollectionService:GetTagged("TrafficLamp") do
				if lamp:IsA("BasePart") then
					local lit = (phase :: any)[lamp:GetAttribute("Group")] == lamp:GetAttribute("Colour")
					lamp.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
					lamp.Color = if lit then (lamp:GetAttribute("OnColour") :: Color3? or off) else off
				end
			end
			task.wait(phase.Time)
		end
	end
end

local function trackZones()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local profile = PlayerDataService.get(player)
			if root and profile then
				local zone = MapLayout.zoneAt(root.Position)
				local id = zone and zone.Id
				if player:GetAttribute("Zone") ~= id then
					player:SetAttribute("Zone", id)
				end
				if zone and not profile.ZonesVisited[zone.Id] then
					profile.ZonesVisited[zone.Id] = true
					EconomyService.grant(player, EconomyConfig.Rewards.ExploreZoneCash, EconomyConfig.Rewards.ExploreZoneXp, "Discovered " .. zone.Name, "Explore")
				end
				if zone and Services.ChallengeService then
					Services.ChallengeService.onZone(player, zone.Id)
				end
			end
		end
	end
end

function MapService.init(services: any)
	Services = services
	setupLighting()
	if HIDE_DEFAULT_BASEPLATE then
		local baseplate = Workspace:FindFirstChild("Baseplate")
		if baseplate and baseplate:IsA("BasePart") then
			baseplate.Transparency = 1
			baseplate.CanCollide = false
			baseplate.CanQuery = false
			baseplate.CanTouch = false
		end
	end
	local map = MapGenerator.generate()
	local found = map:FindFirstChild("MeetSpawn", true)
	if found and found:IsA("SpawnLocation") then
		spawnLocation = found
	end
end

function MapService.start()
	local function assignSpawn(player: Player)
		if spawnLocation then
			player.RespawnLocation = spawnLocation
		end
	end
	Players.PlayerAdded:Connect(function(player)
		assignSpawn(player)
		-- The first character may already have spawned at a default SpawnLocation before the
		-- map existed; move it to the meet.
		player.CharacterAdded:Connect(function(character)
			task.wait()
			if spawnLocation then
				character:PivotTo(spawnLocation.CFrame + Vector3.new(0, 4, 0))
			end
		end)
	end)
	for _, player in Players:GetPlayers() do
		assignSpawn(player)
		if player.Character and spawnLocation then
			player.Character:PivotTo(spawnLocation.CFrame + Vector3.new(0, 4, 0))
		end
	end
	task.spawn(cycleTrafficLights)
	task.spawn(trackZones)
end

return MapService
