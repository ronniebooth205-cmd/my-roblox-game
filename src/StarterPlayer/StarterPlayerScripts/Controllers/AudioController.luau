--!strict
-- StarterPlayer > StarterPlayerScripts > Controllers > AudioController (ModuleScript)
-- Electric-bike audio. Every nearby bike gets looping sounds whose pitch and volume follow
-- speed, throttle and motor load (a rising electric whine, not a petrol engine); your own bike
-- also gets tyre, skid, landing and crash sounds. UI sounds are played through `ui(name)`.
-- Asset IDs live in Shared/AudioConfig and are empty until real licensed sounds are added;
-- empty entries are skipped, so the system is wired up and silent rather than broken.
-- Volumes come from Settings through three SoundGroups.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local AudioConfig = require(ReplicatedStorage.Shared.AudioConfig)
local BikeController = require(script.Parent.BikeController)

local AudioController = {}

local groups: { [string]: SoundGroup } = {}
local bikeSounds: { [Model]: { [string]: Sound } } = {}
local uiSounds: { [string]: Sound } = {}
local wasFrontContact = true
local lastLanding = 0

local function group(name: string): SoundGroup
	local existing = groups[name]
	if existing then
		return existing
	end
	local g = Instance.new("SoundGroup")
	g.Name = "Surron" .. name
	g.Parent = SoundService
	groups[name] = g
	return g
end

local function makeSound(parent: Instance, id: string, looped: boolean, groupName: string): Sound?
	if id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Looped = looped
	sound.Volume = 0
	sound.RollOffMaxDistance = 180
	sound.RollOffMinDistance = 8
	sound.SoundGroup = group(groupName)
	sound.Parent = parent
	if looped then
		sound:Play()
	end
	return sound
end

local function soundsFor(model: Model): { [string]: Sound }?
	local existing = bikeSounds[model]
	if existing then
		return existing
	end
	local chassis = model.PrimaryPart
	if not chassis then
		return nil
	end
	local sounds: { [string]: Sound } = {}
	for _, name in { "MotorWhine", "MotorLoad", "TyreRoll", "TyreDirt", "TyreSkid" } do
		local s = makeSound(chassis, (AudioConfig :: any)[name], true, if name:sub(1, 5) == "Motor" then "Motor" else "World")
		if s then
			sounds[name] = s
		end
	end
	for _, name in { "Landing", "Brake", "Crash" } do
		local s = makeSound(chassis, (AudioConfig :: any)[name], false, "World")
		if s then
			sounds[name] = s
		end
	end
	bikeSounds[model] = sounds
	return sounds
end

local function update()
	local folder = Workspace:FindFirstChild("Bikes")
	if not folder then
		return
	end
	local own = BikeController.state
	for _, model in folder:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local sounds = soundsFor(model)
		local chassis = model.PrimaryPart
		if not sounds or not chassis then
			continue
		end
		local isOwn = own.Active and own.Model == model
		local speed = math.abs(chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector))
		local throttle = if isOwn then own.Throttle else (model:GetAttribute("Throttle") :: number? or 0)
		local load = if isOwn then own.MotorLoad else throttle * 0.6
		local ridden = model:GetAttribute("RiderUserId") ~= nil
		local speedFrac = math.clamp(speed / 80, 0, 1)
		if sounds.MotorWhine then
			sounds.MotorWhine.PlaybackSpeed = 0.55 + speedFrac * 1.5 + load * 0.15
			sounds.MotorWhine.Volume = if ridden then 0.12 + throttle * 0.45 + speedFrac * 0.2 else 0
		end
		if sounds.MotorLoad then
			sounds.MotorLoad.PlaybackSpeed = 0.7 + speedFrac * 0.8
			sounds.MotorLoad.Volume = if ridden then load * 0.5 else 0
		end
		local loose = isOwn and own.SurfaceKind ~= "Paved"
		if sounds.TyreRoll then
			sounds.TyreRoll.Volume = if loose then 0 else speedFrac * 0.4
			sounds.TyreRoll.PlaybackSpeed = 0.8 + speedFrac * 0.6
		end
		if sounds.TyreDirt then
			sounds.TyreDirt.Volume = if loose then speedFrac * 0.5 else 0
		end
		if sounds.TyreSkid then
			local braking = if isOwn then math.max(own.Brake, own.RearBrake) else (model:GetAttribute("Brake") :: number? or 0)
			sounds.TyreSkid.Volume = if braking > 0.6 and speed > 15 then 0.4 else 0
		end
		if isOwn then
			-- Thump when the front wheel comes back down from a wheelie or jump.
			if own.FrontContact and not wasFrontContact and os.clock() - lastLanding > 0.4 then
				lastLanding = os.clock()
				if sounds.Landing then
					sounds.Landing.Volume = 0.6
					sounds.Landing:Play()
				end
			end
			wasFrontContact = own.FrontContact
		end
	end
end

function AudioController.init()
	for _, name in { "Master", "Motor", "World", "UI" } do
		group(name)
	end
	BikeController.onCrash(function()
		local model = BikeController.state.Model
		local sounds = model and bikeSounds[model]
		if sounds and sounds.Crash then
			sounds.Crash.Volume = 0.8
			sounds.Crash:Play()
		end
	end)
	for _, name in { "UiClick", "UiConfirm", "UiError", "Reward", "LevelUp", "GarageAmbience" } do
		local s = makeSound(SoundService, (AudioConfig :: any)[name], name == "GarageAmbience", "UI")
		if s then
			s:Stop()
			s.Volume = 0.6
			uiSounds[name] = s
		end
	end
	task.spawn(function()
		local folder = Workspace:WaitForChild("Bikes")
		folder.ChildRemoved:Connect(function(child)
			bikeSounds[child :: Model] = nil
		end)
		RunService.Heartbeat:Connect(update)
	end)
end

function AudioController.ui(name: string)
	local s = uiSounds[name]
	if s then
		s:Play()
	end
end

function AudioController.setLoop(name: string, playing: boolean)
	local s = uiSounds[name]
	if s then
		if playing and not s.IsPlaying then
			s:Play()
		elseif not playing then
			s:Stop()
		end
	end
end

-- Volumes from Settings (0..1).
function AudioController.setVolumes(master: number, motor: number, ui: number)
	group("Motor").Volume = master * motor
	group("World").Volume = master
	group("UI").Volume = master * ui
end

return AudioController
