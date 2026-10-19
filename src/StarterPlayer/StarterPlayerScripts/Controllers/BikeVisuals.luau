--!strict
-- StarterPlayer > StarterPlayerScripts > Controllers > BikeVisuals (ModuleScript)
-- Client-only visuals for every bike nearby: wheel spin, suspension travel, swingarm angle,
-- steering, brake light and headlight, plus tyre dust on loose surfaces and optional tyre
-- marks. Your own bike uses the exact physics state; other players' bikes are reconstructed
-- from their replicated motion and the state attributes the server relays. None of this
-- affects physics, and it all switches off for far-away bikes or on Low graphics.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PhysicsConfig = require(ReplicatedStorage.Shared.PhysicsConfig)
local BikeController = require(script.Parent.BikeController)

local BikeVisuals = {}

BikeVisuals.effectsEnabled = true
BikeVisuals.trailsEnabled = true

type Rig = {
	Model: Model,
	Chassis: BasePart,
	Steer: Motor6D?,
	Fork: Motor6D?,
	FrontWheel: Motor6D?,
	Swingarm: Motor6D?,
	RearWheel: Motor6D?,
	TailLight: BasePart?,
	TailGlow: PointLight?,
	Beam: SpotLight?,
	Dust: ParticleEmitter?,
	TrailAttachment: Attachment?,
	Trail: Trail?,
	FrontSpin: number,
	RearSpin: number,
	FrontComp: number,
	RearComp: number,
	BrakeLit: boolean?,
}

local rigs: { [Model]: Rig } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.CollisionGroup = "BikeRay"
local MAX_DISTANCE = 260

local function joint(model: Model, name: string): Motor6D?
	local found = model:FindFirstChild(name, true)
	return if found and found:IsA("Motor6D") then found else nil
end

local function buildRig(model: Model): Rig?
	local chassis = model.PrimaryPart
	if not chassis then
		return nil
	end
	local tail = model:FindFirstChild("TailLight") :: BasePart?
	local headlight = model:FindFirstChild("Headlight", true)
	local rig: Rig = {
		Model = model,
		Chassis = chassis,
		Steer = joint(model, "SteerJoint"),
		Fork = joint(model, "ForkJoint"),
		FrontWheel = joint(model, "FrontWheelJoint"),
		Swingarm = joint(model, "SwingarmJoint"),
		RearWheel = joint(model, "RearWheelJoint"),
		TailLight = tail,
		TailGlow = tail and tail:FindFirstChild("TailGlow") :: PointLight?,
		Beam = headlight and headlight:FindFirstChild("Beam") :: SpotLight?,
		FrontSpin = 0,
		RearSpin = 0,
		FrontComp = model:GetAttribute("StaticSag") :: number? or 0.3,
		RearComp = model:GetAttribute("StaticSag") :: number? or 0.3,
	}
	-- Dust and tyre marks hang off an attachment at the rear contact patch.
	local axleDrop = (model:GetAttribute("MountDrop") :: number? or 1.3) + (model:GetAttribute("SuspensionRest") :: number? or 0.9) - (model:GetAttribute("StaticSag") :: number? or 0.3)
	local radius = model:GetAttribute("WheelRadius") :: number? or 1.05
	local base = model:GetAttribute("Wheelbase") :: number? or 4
	local contact = Instance.new("Attachment")
	contact.Name = "RearContact"
	contact.Position = Vector3.new(0, -axleDrop - radius + 0.1, base / 2 + 0.3)
	contact.Parent = chassis
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "Dust"
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(150, 125, 95))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 3.5) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.6, 1.2)
	dust.Speed = NumberRange.new(2, 5)
	dust.SpreadAngle = Vector2.new(25, 25)
	dust.EmissionDirection = Enum.NormalId.Back
	dust.Rate = 0
	dust.LightInfluence = 1
	dust.Parent = contact
	rig.Dust = dust
	local a0 = Instance.new("Attachment")
	a0.Position = contact.Position + Vector3.new(-0.12, 0.02, 0)
	a0.Parent = chassis
	local a1 = Instance.new("Attachment")
	a1.Position = contact.Position + Vector3.new(0.12, 0.02, 0)
	a1.Parent = chassis
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.fromRGB(20, 20, 20))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 2.5
	trail.MinLength = 0.2
	trail.FaceCamera = false
	trail.Enabled = false
	trail.Parent = chassis
	rig.Trail = trail
	rig.TrailAttachment = contact
	return rig
end

local function surfaceKind(material: Enum.Material): string
	local surface = PhysicsConfig.Surfaces[material.Name] or PhysicsConfig.Surfaces.Default
	return surface.Kind
end

local function estimateCompression(rig: Rig, zLocal: number, cf: CFrame): (number, Enum.Material?)
	local model = rig.Model
	local drop = model:GetAttribute("MountDrop") :: number? or 1.3
	local rest = model:GetAttribute("SuspensionRest") :: number? or 0.9
	local radius = model:GetAttribute("WheelRadius") :: number? or 1.05
	local mount = cf:PointToWorldSpace(Vector3.new(0, -drop, zLocal))
	local up = cf.UpVector
	local result = Workspace:Raycast(mount + up * 0.5, -up * (rest + radius + 0.5), rayParams)
	if result then
		return math.clamp(rest - (result.Distance - 0.5 - radius), 0, rest), result.Material
	end
	return 0, nil
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else Vector3.zero
	local own = BikeController.state
	for model, rig in rigs do
		if not model.Parent or not rig.Chassis.Parent then
			rigs[model] = nil
			continue
		end
		local chassis = rig.Chassis
		local cf = chassis.CFrame
		if (cf.Position - camPos).Magnitude > MAX_DISTANCE then
			continue
		end
		local isOwn = own.Active and own.Model == model
		local base = model:GetAttribute("Wheelbase") :: number? or 4
		local radius = model:GetAttribute("WheelRadius") :: number? or 1.05
		local sag = model:GetAttribute("StaticSag") :: number? or 0.3
		local rake = model:GetAttribute("Rake") :: number? or 0.32
		local armLength = model:GetAttribute("SwingarmLength") :: number? or 1.6
		local speed = chassis.AssemblyLinearVelocity:Dot(cf.LookVector)
		local steer, brake, throttle
		local rearMaterial: Enum.Material? = nil
		local wheelie = false
		if isOwn then
			rig.FrontComp = own.FrontCompression
			rig.RearComp = own.RearCompression
			rig.FrontSpin = own.FrontSpin
			rig.RearSpin = own.RearSpin
			steer = own.SteerAngle
			brake = math.max(own.Brake, own.RearBrake)
			throttle = own.Throttle
			rearMaterial = if own.RearContact then own.SurfaceMaterial else nil
			wheelie = own.InWheelie
		else
			local frontComp, _ = estimateCompression(rig, -base / 2, cf)
			local rearComp, material = estimateCompression(rig, base / 2, cf)
			local k = 1 - math.exp(-dt / 0.05)
			rig.FrontComp += (frontComp - rig.FrontComp) * k
			rig.RearComp += (rearComp - rig.RearComp) * k
			rig.FrontSpin -= (if frontComp > 0 then speed else 0) / radius * dt
			rig.RearSpin -= speed / radius * dt
			steer = (model:GetAttribute("Steer") :: number? or 0) * math.rad(28) / (1 + math.abs(speed) / 28)
			brake = model:GetAttribute("Brake") :: number? or 0
			throttle = model:GetAttribute("Throttle") :: number? or 0
			rearMaterial = material
			wheelie = model:GetAttribute("Wheelie") == true
		end

		local frontOffset = rig.FrontComp - sag
		local rearOffset = rig.RearComp - sag
		if rig.Steer then
			rig.Steer.Transform = CFrame.Angles(0, -steer, 0)
		end
		if rig.Fork then
			rig.Fork.Transform = CFrame.new(0, frontOffset / math.cos(rake), 0)
		end
		if rig.FrontWheel then
			rig.FrontWheel.Transform = CFrame.Angles(rig.FrontSpin, 0, 0)
		end
		if rig.Swingarm then
			rig.Swingarm.Transform = CFrame.Angles(math.asin(math.clamp(rearOffset / armLength, -0.9, 0.9)), 0, 0)
		end
		if rig.RearWheel then
			rig.RearWheel.Transform = CFrame.new(0, rearOffset, 0) * CFrame.Angles(rig.RearSpin, 0, 0)
		end

		local braking = brake > 0.1
		if rig.TailLight and braking ~= rig.BrakeLit then
			rig.BrakeLit = braking
			rig.TailLight.Material = if braking then Enum.Material.Neon else Enum.Material.SmoothPlastic
			rig.TailLight.Color = if braking then Color3.fromRGB(255, 40, 40) else Color3.fromRGB(120, 10, 10)
			if rig.TailGlow then
				rig.TailGlow.Brightness = if braking then 2.5 else 0.6
			end
		end
		if rig.Beam then
			rig.Beam.Enabled = model:GetAttribute("Headlight") == true and BikeVisuals.effectsEnabled
		end

		local loose = rearMaterial ~= nil and surfaceKind(rearMaterial :: Enum.Material) ~= "Paved"
		if rig.Dust then
			rig.Dust.Rate = if BikeVisuals.effectsEnabled and loose and math.abs(speed) > 6 then math.clamp(math.abs(speed) * 0.8 + throttle * 20, 0, 60) else 0
		end
		if rig.Trail then
			local skid = braking and math.abs(speed) > 15
			rig.Trail.Enabled = BikeVisuals.effectsEnabled and BikeVisuals.trailsEnabled and rearMaterial ~= nil and not loose and (wheelie or skid)
		end
	end
end

local function track(model: Instance)
	if model:IsA("Model") and not rigs[model] then
		-- Wait for the bike's parts to stream in before rigging it.
		task.spawn(function()
			local chassis = model:WaitForChild("Chassis", 10)
			if chassis and model.Parent and not rigs[model] then
				model:WaitForChild("RearWheel", 5)
				local rig = buildRig(model)
				if rig then
					rigs[model] = rig
				end
			end
		end)
	end
end

function BikeVisuals.init()
	-- The server makes the Bikes folder after building the map, so wait for it in the
	-- background rather than holding up the rest of the client.
	task.spawn(function()
		local folder = Workspace:WaitForChild("Bikes")
		folder.ChildAdded:Connect(track)
		for _, child in folder:GetChildren() do
			track(child)
		end
		folder.ChildRemoved:Connect(function(child)
			rigs[child :: Model] = nil
		end)
		rayParams.FilterDescendantsInstances = { folder }
		RunService.RenderStepped:Connect(update)
	end)
end

return BikeVisuals
