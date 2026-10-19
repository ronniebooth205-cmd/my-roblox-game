--!strict
-- StarterPlayer > StarterPlayerScripts > Controllers > RiderController (ModuleScript)
-- Procedural rider poses for everyone riding nearby. The server attaches IKControls that pin
-- hands to the grips and feet to the pegs; this layers body language on top by offsetting the
-- R15 joints' C0 (locally, so it never replicates or fights the physics):
--   lean forward/back with the lean input, crouch over the bars when braking, stand on the
--   pegs, one hand or both hands off, swing a leg out.
-- Your own pose comes straight from TrickController/BikeController; other riders' poses come
-- from the Pose/Lean attributes the server relays. Original C0s are restored on dismount.
-- R6 avatars keep the default seated pose.
-- Replace or extend `POSES` to plug in authored animations later.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BikeController = require(script.Parent.BikeController)
local TrickController = require(script.Parent.TrickController)

local RiderController = {}

type JointState = { Joint: Motor6D, Original: CFrame }
type Rider = {
	Character: Model,
	Joints: { [string]: JointState },
	Blend: { [string]: number },
	Pose: string,
}

-- Per-pose targets: root lift, torso pitch, and which limbs leave their IK target.
local POSES: { [string]: { Lift: number, Pitch: number, LeftHand: boolean, RightHand: boolean, LeftFoot: boolean } } = {
	Seated = { Lift = 0, Pitch = 0, LeftHand = true, RightHand = true, LeftFoot = true },
	Standing = { Lift = 1.1, Pitch = -12, LeftHand = true, RightHand = true, LeftFoot = true },
	OneHand = { Lift = 0, Pitch = 4, LeftHand = true, RightHand = false, LeftFoot = true },
	NoHands = { Lift = 0.2, Pitch = 10, LeftHand = false, RightHand = false, LeftFoot = true },
	LegOut = { Lift = 0.1, Pitch = 0, LeftHand = true, RightHand = true, LeftFoot = false },
	Crashed = { Lift = 0, Pitch = 0, LeftHand = false, RightHand = false, LeftFoot = false },
}

local riders: { [Model]: Rider } = {}

local JOINTS = {
	Root = { "LowerTorso", "Root" },
	Waist = { "UpperTorso", "Waist" },
	RightShoulder = { "RightUpperArm", "RightShoulder" },
	LeftShoulder = { "LeftUpperArm", "LeftShoulder" },
	LeftHip = { "LeftUpperLeg", "LeftHip" },
}

local function riderFor(character: Model): Rider?
	local existing = riders[character]
	if existing then
		return existing
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return nil
	end
	local joints = {}
	for key, path in JOINTS do
		local part = character:FindFirstChild(path[1])
		local motor = part and part:FindFirstChild(path[2])
		if motor and motor:IsA("Motor6D") then
			joints[key] = { Joint = motor, Original = motor.C0 }
		end
	end
	local rider: Rider = { Character = character, Joints = joints, Blend = { Lift = 0, Pitch = 0, Lean = 0, RightArm = 0, LeftArm = 0, Leg = 0 }, Pose = "Seated" }
	riders[character] = rider
	return rider
end

local function restore(rider: Rider)
	for _, state in rider.Joints do
		if state.Joint.Parent then
			state.Joint.C0 = state.Original
		end
	end
	local humanoid = rider.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		for _, child in humanoid:GetChildren() do
			if child:IsA("IKControl") then
				child.Enabled = true
			end
		end
	end
end

local function setIK(character: Model, name: string, enabled: boolean)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local ik = humanoid and humanoid:FindFirstChild("BikeIK_" .. name)
	if ik and ik:IsA("IKControl") and ik.Enabled ~= enabled then
		ik.Enabled = enabled
	end
end

local function apply(rider: Rider, pose: string, lean: number, braking: number, dt: number)
	local target = POSES[pose] or POSES.Seated
	local k = 1 - math.exp(-dt / 0.12)
	local b = rider.Blend
	b.Lift += (target.Lift - b.Lift) * k
	b.Pitch += (target.Pitch + braking * -10 - (if pose == "Standing" then 0 else 6) - lean * 14 - b.Pitch) * k
	b.RightArm += ((if target.RightHand then 0 else 1) - b.RightArm) * k
	b.LeftArm += ((if target.LeftHand then 0 else 1) - b.LeftArm) * k
	b.Leg += ((if target.LeftFoot then 0 else 1) - b.Leg) * k
	local j = rider.Joints
	if j.Root then
		j.Root.Joint.C0 = j.Root.Original * CFrame.new(0, b.Lift, -b.Lift * 0.2)
	end
	if j.Waist then
		-- Positive rotation about X tips the torso back; forward lean is negative.
		j.Waist.Joint.C0 = j.Waist.Original * CFrame.Angles(math.rad(b.Pitch), 0, 0)
	end
	if j.RightShoulder then
		j.RightShoulder.Joint.C0 = j.RightShoulder.Original * CFrame.Angles(0, 0, math.rad(95 * b.RightArm))
	end
	if j.LeftShoulder then
		j.LeftShoulder.Joint.C0 = j.LeftShoulder.Original * CFrame.Angles(0, 0, math.rad(-95 * b.LeftArm))
	end
	if j.LeftHip then
		j.LeftHip.Joint.C0 = j.LeftHip.Original * CFrame.Angles(0, 0, math.rad(-55 * b.Leg))
	end
	setIK(rider.Character, "RightHand", b.RightArm < 0.5)
	setIK(rider.Character, "LeftHand", b.LeftArm < 0.5)
	setIK(rider.Character, "LeftFoot", b.Leg < 0.5)
end

local function update(dt: number)
	local seen: { [Model]: boolean } = {}
	local folder = Workspace:FindFirstChild("Bikes")
	local camera = Workspace.CurrentCamera
	local localPlayer = Players.LocalPlayer
	if folder then
		for _, model in folder:GetChildren() do
			local riderId = model:GetAttribute("RiderUserId")
			local player = riderId and Players:GetPlayerByUserId(riderId :: number)
			local character = player and player.Character
			local chassis = model:IsA("Model") and model.PrimaryPart
			if character and chassis and camera and (chassis.Position - camera.CFrame.Position).Magnitude < 200 then
				local rider = riderFor(character)
				if rider then
					seen[character] = true
					local pose, lean, braking
					if player == localPlayer and BikeController.state.Active then
						pose = if BikeController.state.Crashed then "Crashed" else TrickController.pose
						lean = BikeController.state.Lean
						braking = math.max(BikeController.state.Brake, BikeController.state.RearBrake)
					else
						pose = model:GetAttribute("Pose") :: string? or "Seated"
						lean = model:GetAttribute("Lean") :: number? or 0
						braking = model:GetAttribute("Brake") :: number? or 0
					end
					apply(rider, pose, lean, braking, dt)
				end
			end
		end
	end
	for character, rider in riders do
		if not seen[character] then
			restore(rider)
			riders[character] = nil
		end
	end
end

function RiderController.init()
	RunService.Stepped:Connect(function(_time, dt)
		update(dt)
	end)
end

return RiderController
