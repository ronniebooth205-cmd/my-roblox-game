--!strict
-- StarterPlayer > StarterPlayerScripts > Controllers > CameraController (ModuleScript)
-- Riding cameras: Chase (default), Close, FirstPerson, Cinematic (side-on, good for filming
-- wheelies) and FreeLook (orbit with the mouse/right stick). Follows the bike's heading with
-- smoothing rather than its exact orientation, so lean and suspension never shake the view.
-- During a wheelie the camera rises and looks further ahead so the road stays visible.
-- Collision rays stop it going through walls. On foot the default Roblox camera is restored.
-- Can also be pointed at the garage turntable or the menu bike (setScene).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Utilities = require(ReplicatedStorage.Shared.Utilities)
local BikeController = require(script.Parent.BikeController)

local CameraController = {}

local cfg = GameConfig.Camera
CameraController.mode = "Chase"
CameraController.sensitivity = 1
CameraController.reducedMotion = false

local riding = false
local scene: (() -> CFrame)? = nil
local smoothedYaw: number? = nil
local smoothedPos: Vector3? = nil
local smoothedLift = 0
local orbitYaw, orbitPitch = 0, math.rad(12)
local renderBound = false
local modeListeners: { (mode: string) -> () } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function camera(): Camera
	return Workspace.CurrentCamera :: Camera
end

local function angleLerp(a: number, b: number, t: number): number
	local diff = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + diff * t
end

local function collide(focus: Vector3, desired: Vector3): Vector3
	local direction = desired - focus
	local result = Workspace:Raycast(focus, direction, rayParams)
	if result then
		return result.Position - direction.Unit * cfg.CollisionPadding
	end
	return desired
end

local function update(dt: number)
	local cam = camera()
	if scene then
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = cam.CFrame:Lerp(scene(), 1 - math.exp(-dt / 0.25))
		cam.FieldOfView = Utilities.smooth(cam.FieldOfView, 60, 0.3, dt)
		return
	end
	local s = BikeController.state
	local model = s.Model
	local chassis = model and model.PrimaryPart
	if not riding or not chassis then
		return
	end
	cam.CameraType = Enum.CameraType.Scriptable
	local character = Players.LocalPlayer.Character
	rayParams.FilterDescendantsInstances = { Workspace:FindFirstChild("Bikes") or chassis, character or chassis }

	local cf = chassis.CFrame
	local flatLook = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if flatLook.Magnitude < 0.05 then
		flatLook = Vector3.new(cf.UpVector.X, 0, cf.UpVector.Z) * -1
	end
	local yaw = math.atan2(-flatLook.X, -flatLook.Z)
	local follow = 1 - math.exp(-dt / cfg.FollowSmoothing)
	smoothedYaw = if smoothedYaw then angleLerp(smoothedYaw, yaw, follow) else yaw
	local heading = CFrame.Angles(0, smoothedYaw :: number, 0)
	local speedFrac = math.clamp(math.abs(s.Speed) / 80, 0, 1)
	local wheelieLift = if s.InWheelie then math.clamp(s.Pitch / 50, 0, 1) else 0
	smoothedLift = Utilities.smooth(smoothedLift, wheelieLift, 0.35, dt)
	-- The rear axle stays on the road in a wheelie, so frame from there rather than the chassis.
	local base = chassis.Position - Vector3.new(0, 1.2, 0)

	local mode = CameraController.mode
	local target: CFrame
	local fov = cfg.Chase.FovBase
	if mode == "FirstPerson" then
		local head = character and character:FindFirstChild("Head") :: BasePart?
		local eye = if head then head.Position + Vector3.new(0, 0.2, 0) else cf.Position + Vector3.new(0, 3, 0)
		-- Pitch follows the bike a little so wheelies are felt, but never fully.
		local pitch = math.rad(math.clamp(s.Pitch, -20, 60)) * 0.45
		target = CFrame.new(eye) * heading * CFrame.Angles(pitch - math.rad(6), 0, 0)
		fov = cfg.FirstPersonFov
	elseif mode == "Cinematic" then
		local c = cfg.Cinematic
		local offset = heading:VectorToWorldSpace(Vector3.new(c.Side, c.Height, c.Behind))
		local desired = base + offset
		target = CFrame.lookAt(collide(base + Vector3.new(0, 1.5, 0), desired), base + Vector3.new(0, 1.5 + smoothedLift, 0))
		fov = 55
	elseif mode == "FreeLook" then
		local rot = heading * CFrame.Angles(0, orbitYaw, 0) * CFrame.Angles(-orbitPitch, 0, 0)
		local focus = base + Vector3.new(0, cfg.Chase.LookHeight, 0)
		local desired = focus + rot:VectorToWorldSpace(Vector3.new(0, 0, cfg.Chase.Distance))
		target = CFrame.lookAt(collide(focus, desired), focus)
	else
		local m = if mode == "Close" then cfg.Close else cfg.Chase
		local distance = m.Distance + speedFrac * cfg.SpeedZoom + smoothedLift * 1.5
		local height = m.Height + smoothedLift * cfg.WheelieLift
		local focus = base + Vector3.new(0, m.LookHeight + smoothedLift * 1.2, 0) + heading.LookVector * (2 + smoothedLift * 4)
		local desired = base + heading:VectorToWorldSpace(Vector3.new(0, height, distance))
		target = CFrame.lookAt(collide(focus, desired), focus)
		fov = m.FovBase + (m.FovMax - m.FovBase) * speedFrac
	end
	if CameraController.reducedMotion then
		fov = cfg.Chase.FovBase
	end

	-- Smooth the camera's position a touch (rotation already follows the smoothed yaw).
	local pos = target.Position
	if smoothedPos and (smoothedPos - pos).Magnitude < 30 then
		pos = smoothedPos:Lerp(pos, 1 - math.exp(-dt / 0.05))
	end
	smoothedPos = pos
	cam.CFrame = CFrame.new(pos) * target.Rotation
	cam.FieldOfView = Utilities.smooth(cam.FieldOfView, fov, 0.4, dt)
end

local function bind()
	if not renderBound then
		renderBound = true
		RunService:BindToRenderStep("SurronCamera", Enum.RenderPriority.Camera.Value + 1, update)
	end
end

local function unbind()
	if renderBound then
		renderBound = false
		RunService:UnbindFromRenderStep("SurronCamera")
	end
end

local function restoreDefault()
	local cam = camera()
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = 70
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		cam.CameraSubject = humanoid
	end
end

function CameraController.init()
	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if processed or not riding or CameraController.mode ~= "FreeLook" then
			return
		end
		local sens = CameraController.sensitivity
		if input.UserInputType == Enum.UserInputType.MouseMovement and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
			orbitYaw -= input.Delta.X * 0.006 * sens
			orbitPitch = math.clamp(orbitPitch + input.Delta.Y * 0.004 * sens, math.rad(-10), math.rad(60))
		elseif input.UserInputType == Enum.UserInputType.Touch and input.Position.X > camera().ViewportSize.X * 0.35 and input.Position.X < camera().ViewportSize.X * 0.65 then
			orbitYaw -= input.Delta.X * 0.008 * sens
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 and math.abs(input.Position.X) > 0.2 then
			orbitYaw -= input.Position.X * 0.05 * sens
		end
	end)
end

function CameraController.setRiding(isRiding: boolean)
	riding = isRiding
	smoothedYaw = nil
	smoothedPos = nil
	orbitYaw = 0
	if isRiding or scene then
		bind()
	else
		unbind()
		restoreDefault()
	end
end

function CameraController.cycleMode()
	local modes = cfg.Modes
	local index = table.find(modes, CameraController.mode) or 1
	CameraController.setMode(modes[index % #modes + 1])
end

function CameraController.setMode(mode: string)
	if table.find(cfg.Modes, mode) then
		CameraController.mode = mode
		orbitYaw = 0
		for _, listener in modeListeners do
			task.spawn(listener, mode)
		end
	end
end

function CameraController.onModeChanged(listener: (mode: string) -> ())
	table.insert(modeListeners, listener)
end

-- Points the camera at a scripted shot (garage, menu). Pass nil to go back to normal.
function CameraController.setScene(provider: (() -> CFrame)?)
	scene = provider
	if provider or riding then
		bind()
	else
		unbind()
		restoreDefault()
	end
end

return CameraController
