-- StarterPlayer > StarterPlayerScripts > ClientMain (LocalScript)
-- Client entry point. Starts every controller and the UI, then runs the riding lifecycle:
-- mounting your own bike starts the physics controller, riding camera, HUD and touch controls;
-- getting off (or crashing) stops them. Also streams your bike's control state to the server
-- ~10 times a second so other players see your steering, lean, brake light and pose.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local BikeStats = require(ReplicatedStorage.Shared.BikeStats)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Controllers = script.Parent:WaitForChild("Controllers")
local ClientState = require(Controllers.ClientState)
local InputController = require(Controllers.InputController)
local BikeController = require(Controllers.BikeController)
local WheelieController = require(Controllers.WheelieController)
local TrickController = require(Controllers.TrickController)
local CameraController = require(Controllers.CameraController)
local BikeVisuals = require(Controllers.BikeVisuals)
local RiderController = require(Controllers.RiderController)
local AudioController = require(Controllers.AudioController)
local UI = script.Parent:WaitForChild("UI")
local UIController = require(UI.UIController)
local HUD = require(UI.HUD)
local Components = require(UI.Components)

local player = Players.LocalPlayer
local bikeAction = Remotes.event("BikeAction")
local bikeState = Remotes.unreliable("BikeState")

local riding = false
local ridingModel: Model? = nil
local playerModule: any = nil
local crashTime = 0

local function myBike(): Model?
	local folder = Workspace:FindFirstChild("Bikes")
	if not folder then
		return nil
	end
	for _, model in folder:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("OwnerUserId") == player.UserId then
			return model
		end
	end
	return nil
end

local function humanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function setCharacterControls(enabled: boolean)
	if not playerModule then
		local ok, module = pcall(function()
			return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript)
		end)
		playerModule = if ok then module else false
	end
	if playerModule then
		local controls = playerModule:GetControls()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end
	local h = humanoid()
	if h then
		h:SetStateEnabled(Enum.HumanoidStateType.Jumping, enabled)
	end
end

------------------------------------------------------------------------ riding lifecycle

local function updatePrompt()
	if riding then
		HUD.setPrompt(nil)
		local recover = HUD.keyHint("Recover")
		local mount = HUD.keyHint("Mount")
		local camera = HUD.keyHint("Camera")
		if InputController.device() == "Touch" then
			HUD.setHint("")
		elseif BikeController.state.Crashed then
			HUD.setHint(string.format("[%s] Recover bike", recover))
		else
			HUD.setHint(string.format("[%s] Get off   ·   [%s] Recover   ·   [%s] Camera", mount, recover, camera))
		end
	elseif BikeController.state.Crashed or os.clock() - crashTime < GameConfig.Spawning.AutoRecoverAfterCrash then
		HUD.setPrompt("RECOVER BIKE")
		HUD.setHint("")
	elseif myBike() then
		HUD.setPrompt("RIDE")
		HUD.setHint(if InputController.device() == "Touch" then "" else string.format("[%s] Ride your bike", HUD.keyHint("Mount")))
	else
		HUD.setPrompt("SPAWN BIKE")
		HUD.setHint("")
	end
end

-- Runs one part of the riding setup; a failure is reported on screen instead of silently
-- leaving the rest (and the anchored bike) stuck.
local function setupStep(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(string.format("[ClientMain] riding setup failed at %s: %s", name, tostring(err)))
		HUD.toast(string.format("Riding setup error (%s): %s", name, tostring(err)), "Error")
	end
end

local function startRiding(model: Model)
	if riding and ridingModel == model then
		return
	end
	riding = true
	ridingModel = model
	setupStep("bike physics", function()
		local profile = ClientState.profile
		local bikeId = model:GetAttribute("BikeId") :: string
		local setup = profile and profile.BikeSetups[bikeId]
		BikeController.start(model, BikeStats.compute(bikeId, setup), ClientState.settings.WheelieAssist)
	end)
	-- The server keeps the bike anchored until we're simulating it.
	bikeAction:FireServer("Release")
	setupStep("controls", function()
		InputController.setRiding(true)
	end)
	setupStep("camera", function()
		CameraController.setRiding(true)
	end)
	setupStep("character", function()
		setCharacterControls(false)
	end)
	setupStep("HUD", function()
		UIController.setRiding(true)
	end)
	updatePrompt()
end

local function stopRiding()
	if not riding then
		return
	end
	riding = false
	ridingModel = nil
	setupStep("stop bike", BikeController.stop)
	setupStep("stop controls", function()
		InputController.setRiding(false)
	end)
	setupStep("stop camera", function()
		CameraController.setRiding(false)
	end)
	setupStep("stop character", function()
		setCharacterControls(true)
	end)
	setupStep("stop HUD", function()
		UIController.setRiding(false)
	end)
	updatePrompt()
end

local function onSeated(active: boolean, seat: BasePart?)
	if active and seat then
		local model = seat:FindFirstAncestorOfClass("Model")
		if model and model:GetAttribute("OwnerUserId") == player.UserId then
			startRiding(model)
			return
		end
	end
	stopRiding()
end

local function onCharacter(character: Model)
	stopRiding()
	local h = character:WaitForChild("Humanoid") :: Humanoid
	h.Seated:Connect(onSeated)
	if h.SeatPart then
		onSeated(true, h.SeatPart)
	end
end

local function getOff()
	local h = humanoid()
	local model = ridingModel
	if not h or not model then
		return
	end
	h.Sit = false
	bikeAction:FireServer("Dismount")
	-- Step off to the side so we don't land inside the bike.
	local chassis = model.PrimaryPart
	local character = player.Character
	if chassis and character then
		task.defer(function()
			character:PivotTo(CFrame.new(chassis.Position + chassis.CFrame.RightVector * -3 + Vector3.new(0, 2, 0)))
		end)
	end
end

local function rideOrSpawn()
	if riding then
		getOff()
		return
	end
	local bike = myBike()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if bike and bike.PrimaryPart and root and (bike.PrimaryPart.Position - root.Position).Magnitude < 16 then
		bikeAction:FireServer("Mount")
	elseif bike and bike.PrimaryPart and root and (bike.PrimaryPart.Position - root.Position).Magnitude < 120 then
		-- Close enough: bring the bike to you.
		bikeAction:FireServer("Recover")
	else
		bikeAction:FireServer("Spawn", true)
	end
end

------------------------------------------------------------------------ crash handling

BikeController.onCrash(function()
	crashTime = os.clock()
	bikeAction:FireServer("Crash")
	local h = humanoid()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if h then
		h.Sit = false
		task.defer(function()
			h:ChangeState(Enum.HumanoidStateType.FallingDown)
			if root then
				-- Carry the bike's momentum into the fall.
				local chassis = ridingModel and ridingModel.PrimaryPart
				local v = if chassis then chassis.AssemblyLinearVelocity else Vector3.zero
				root.AssemblyLinearVelocity = v * 0.8 + Vector3.new(0, 18, 0)
			end
		end)
		task.delay(2, function()
			if h.Parent and h:GetState() == Enum.HumanoidStateType.FallingDown then
				h:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
	end
	updatePrompt()
end)

------------------------------------------------------------------------ actions

InputController.onAction(function(action)
	if UIController.isAnyOpen() and action ~= "Garage" and action ~= "Map" then
		return
	end
	if action == "Mount" then
		rideOrSpawn()
	elseif action == "Recover" then
		bikeAction:FireServer("Recover")
	elseif action == "Camera" then
		CameraController.cycleMode()
		HUD.toast("Camera: " .. CameraController.mode, "Info")
	elseif action == "Headlight" then
		local bike = myBike()
		if bike then
			bikeAction:FireServer("Headlight", bike:GetAttribute("Headlight") ~= true)
		end
	elseif action == "Garage" then
		UIController.toggle("Garage")
	elseif action == "Map" then
		UIController.toggle("Map")
	elseif action == "Tricks" then
		UIController.toggle("Progress", "Tricks")
	end
end)

-- The counter inside Volt Customs opens the garage.
game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt)
	if prompt.Name == "GaragePrompt" then
		UIController.open("Garage")
	end
end)

Remotes.event("BikeSpawned").OnClientEvent:Connect(function(_model, reason)
	if reason == "Recovered" then
		BikeController.clearCrash()
	end
	task.delay(0.2, updatePrompt)
end)

Remotes.event("Notify").OnClientEvent:Connect(function(payload)
	if type(payload) == "table" then
		HUD.notify(payload)
		if payload.Kind == "LevelUp" then
			AudioController.ui("LevelUp")
		elseif payload.Kind == "Wheelie" or payload.Kind == "Reward" or payload.Kind == "Challenge" then
			AudioController.ui("Reward")
		end
	end
end)

------------------------------------------------------------------------ settings

local function applySettings(settings: { [string]: any })
	InputController.setKeybinds(settings.Keybinds)
	CameraController.sensitivity = settings.CameraSensitivity or 1
	CameraController.reducedMotion = settings.ReducedMotion == true
	CameraController.setMode(settings.CameraMode or "Chase")
	BikeController.setAssistSetting(settings.WheelieAssist or 1)
	AudioController.setVolumes(settings.MasterVolume or 0.8, settings.MotorVolume or 0.8, settings.UiVolume or 0.7)
	local low = settings.Graphics == "Low"
	BikeVisuals.effectsEnabled = not low
	BikeVisuals.trailsEnabled = settings.TyreTrails ~= false
	UIController.applySettings(settings)
end

------------------------------------------------------------------------ startup

ClientState.init()
InputController.init()
CameraController.init()
WheelieController.init()
TrickController.init()
BikeVisuals.init()
RiderController.init()
AudioController.init()
Components.setClickSound(function()
	AudioController.ui("UiClick")
end)
UIController.init({
	Prompt = function()
		if BikeController.state.Crashed or (not riding and os.clock() - crashTime < GameConfig.Spawning.AutoRecoverAfterCrash) then
			bikeAction:FireServer("Recover")
		else
			rideOrSpawn()
		end
	end,
	Play = function()
		if not riding then
			rideOrSpawn()
		end
	end,
})
ClientState.onSettings(applySettings)
InputController.onDeviceChanged(function()
	updatePrompt()
end)

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

-- Show the title screen once the profile has loaded; first-timers get a short how-to.
task.spawn(function()
	while not ClientState.profile do
		task.wait(0.2)
	end
	UIController.open("MainMenu")
	local profile = ClientState.profile
	if profile and not profile.TutorialDone then
		task.delay(1, function()
			HUD.toast("Press PLAY to get your bike. Hold throttle and lean back to wheelie!", "Info")
			HUD.toast("Balance with the throttle; tap the rear brake to bring the front down.", "Info")
		end)
		ClientState.markTutorialDone()
	end
end)

-- Stream control state for other players' visuals (unreliable, ~10 Hz, only while riding).
local sendInterval = 1 / GameConfig.Remote.StateSendRate
local sinceSend = 0
local promptTimer = 0
RunService.Heartbeat:Connect(function(dt)
	setupStep("HUD update", function()
		HUD.update(dt)
	end)
	promptTimer += dt
	if promptTimer > 0.5 then
		promptTimer = 0
		-- Backup for Humanoid.Seated: if we're sitting on our own bike (or got off) and the event
		-- was missed, catch up here.
		local h = humanoid()
		local seat = h and h.SeatPart
		local seatModel = seat and seat:FindFirstAncestorOfClass("Model")
		local onOwnBike = seatModel ~= nil and seatModel:GetAttribute("OwnerUserId") == player.UserId
		if onOwnBike and (not riding or ridingModel ~= seatModel) then
			startRiding(seatModel :: Model)
		elseif riding and not onOwnBike then
			stopRiding()
		end
		updatePrompt()
	end
	if not riding then
		return
	end
	if ridingModel and not ridingModel.Parent then
		stopRiding()
		return
	end
	sinceSend += dt
	if sinceSend >= sendInterval then
		sinceSend = 0
		local s = BikeController.state
		bikeState:FireServer({
			Steer = InputController.state.Steer,
			Throttle = s.Throttle,
			Lean = s.Lean,
			Brake = math.max(s.Brake, s.RearBrake),
			Pose = if s.Crashed then "Crashed" else TrickController.pose,
			Wheelie = s.InWheelie,
		})
	end
end)
