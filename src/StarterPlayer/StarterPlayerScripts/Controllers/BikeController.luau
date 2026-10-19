--!strict
-- StarterPlayer > StarterPlayerScripts > Controllers > BikeController (ModuleScript)
-- Simulates the local player's bike. The client owns the bike's physics (the server sets
-- network ownership), so forces are worked out here every frame and written to the chassis's
-- VectorForce/Torque; Roblox's solver integrates them and replicates the result to everyone.
--
-- Per frame:
--   1. Sphere-cast under each wheel -> suspension compression, contact point, surface.
--   2. Spring/damper normal force, then drive, brakes and sideways grip at each contact,
--      limited by a friction circle (surface × tyre × bike grip).
--   3. Wheelie pitch torques: motor torque (stronger when leaning back), rider weight shift,
--      rear brake, a configurable balance assist, and damping. Gravity pulls the nose back
--      down through the real contact geometry; nothing holds the bike at a fixed angle.
--   4. Steering via a yaw-rate controller and a roll controller that leans into turns.
--   5. Crash checks: looping out, tipping over, or a hard impact.
-- See PhysicsConfig for the reasoning behind the numbers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PhysicsConfig = require(ReplicatedStorage.Shared.PhysicsConfig)
local CustomisationConfig = require(ReplicatedStorage.Shared.CustomisationConfig)
local BikeStats = require(ReplicatedStorage.Shared.BikeStats)
local Utilities = require(ReplicatedStorage.Shared.Utilities)
local InputController = require(script.Parent.InputController)

local BikeController = {}

type Wheel = {
	Name: string,
	ZLocal: number,
	Compression: number,
	PrevCompression: number,
	Contact: boolean,
	Point: Vector3,
	Normal: Vector3,
	Material: Enum.Material,
	Load: number,
	Spin: number,
}

local function newWheel(name: string, zLocal: number): Wheel
	return {
		Name = name,
		ZLocal = zLocal,
		Compression = 0,
		PrevCompression = 0,
		Contact = false,
		Point = Vector3.zero,
		Normal = Vector3.yAxis,
		Material = Enum.Material.Plastic,
		Load = 0,
		Spin = 0,
	}
end

BikeController.state = {
	Active = false,
	Model = nil :: Model?,
	Speed = 0, -- studs/s along the bike
	Velocity = Vector3.zero,
	Pitch = 0, -- degrees, nose up positive
	PitchRate = 0, -- degrees/s
	Roll = 0,
	FrontContact = false,
	RearContact = false,
	FrontCompression = 0,
	RearCompression = 0,
	FrontSpin = 0,
	RearSpin = 0,
	SteerAngle = 0, -- radians, positive = right
	Throttle = 0,
	Brake = 0,
	RearBrake = 0,
	Lean = 0,
	Battery = 1,
	SurfaceKind = "Paved",
	SurfaceMaterial = Enum.Material.Asphalt,
	InWheelie = false,
	Airborne = false,
	Crashed = false,
	IdealAngle = 46,
	MotorLoad = 0, -- 0..1, for audio
	Stats = nil :: BikeStats.Stats?,
}

local wheels = { newWheel("Front", 0), newWheel("Rear", 0) }
local connection: RBXScriptConnection? = nil
local chassis: BasePart? = nil
local driveForce: VectorForce? = nil
local antiGravity: VectorForce? = nil
local controlTorque: Torque? = nil
local castParams = RaycastParams.new()
local crashListeners: { (reason: string) -> () } = {}
local assistPenalty = 0
local assistSetting = 1
local previousVelocity = Vector3.zero
local loopOutTimer = 0
local inputEnabled = true

castParams.FilterType = Enum.RaycastFilterType.Exclude
castParams.CollisionGroup = "BikeRay"
castParams.IgnoreWater = false

local function surfaceFor(material: Enum.Material)
	return PhysicsConfig.Surfaces[material.Name] or PhysicsConfig.Surfaces.Default
end

local function zeroActuators()
	if driveForce then
		driveForce.Force = Vector3.zero
	end
	if controlTorque then
		controlTorque.Torque = Vector3.zero
	end
end

local function crash(reason: string)
	local s = BikeController.state
	if s.Crashed then
		return
	end
	s.Crashed = true
	s.InWheelie = false
	zeroActuators()
	for _, listener in crashListeners do
		task.spawn(listener, reason)
	end
end

local function castWheel(wheel: Wheel, cf: CFrame, g: { [string]: number })
	local up = cf.UpVector
	local mount = cf:PointToWorldSpace(Vector3.new(0, -g.MountDrop, wheel.ZLocal))
	local lift = PhysicsConfig.Geometry.CastLift
	local origin = mount + up * lift
	local result = Workspace:Spherecast(origin, g.WheelRadius, -up * (g.SuspensionRest + lift), castParams)
	wheel.PrevCompression = wheel.Compression
	if result then
		local axleDistance = result.Distance - lift
		wheel.Compression = math.max(g.SuspensionRest - axleDistance, 0)
		wheel.Contact = true
		wheel.Point = result.Position
		wheel.Normal = result.Normal
		wheel.Material = result.Material
	else
		wheel.Compression = 0
		wheel.Contact = false
	end
end

local function step(dt: number)
	local s = BikeController.state
	local stats = s.Stats
	local part = chassis
	if not stats or not part or not part.Parent or not driveForce or not controlTorque or not antiGravity then
		return
	end
	dt = math.clamp(dt, 1 / 240, 1 / 20)
	local h = stats.Handling
	local g = stats.Geometry

	-- Until the server releases the bike it is anchored (infinite mass): apply nothing.
	local mass = part.AssemblyMass
	if part.Anchored or mass ~= mass or mass == math.huge or mass <= 0 then
		zeroActuators()
		antiGravity.Force = Vector3.zero
		return
	end
	local cf = part.CFrame
	local com = part.AssemblyCenterOfMass
	local velocity = part.AssemblyLinearVelocity
	local omega = part.AssemblyAngularVelocity
	local up, look, right = cf.UpVector, cf.LookVector, cf.RightVector
	local gravity = PhysicsConfig.BikeGravity

	antiGravity.Force = Vector3.new(0, mass * (Workspace.Gravity - gravity), 0)

	-- Inputs, smoothed so keyboard taps feel like a twist of the throttle.
	local input = InputController.state
	local active = inputEnabled and not s.Crashed
	local throttleTarget = if active then input.Throttle else 0
	s.Throttle = Utilities.smooth(s.Throttle, throttleTarget, h.ThrottleResponse, dt)
	s.Brake = if active then input.Brake else 0
	s.RearBrake = if active then input.RearBrake else 0
	s.Lean = Utilities.smooth(s.Lean, if active then input.Lean else 0, 0.08, dt)

	-- Suspension casts.
	local front, rear = wheels[1], wheels[2]
	front.ZLocal = -g.Wheelbase / 2
	rear.ZLocal = g.Wheelbase / 2
	castWheel(front, cf, g)
	castWheel(rear, cf, g)

	local k = mass * gravity / 2 / g.StaticSag
	local c = 2 * PhysicsConfig.Suspension.DampingRatio * math.sqrt(k * mass / 2)
	local totalLoad = 0
	for _, wheel in wheels do
		if wheel.Contact then
			local compressionSpeed = math.clamp((wheel.Compression - wheel.PrevCompression) / dt, -40, 40)
			local force = k * wheel.Compression + c * compressionSpeed
			local over = wheel.Compression - g.SuspensionTravel
			if over > 0 then
				force += k * PhysicsConfig.Suspension.BumpStopStiffness * over
			end
			wheel.Load = math.max(force, 0)
		else
			wheel.Load = 0
		end
		totalLoad += wheel.Load
	end

	local groundNormal = if rear.Contact then rear.Normal elseif front.Contact then front.Normal else Vector3.yAxis
	local forwardSpeed = velocity:Dot(look)
	s.Velocity = velocity
	s.Speed = forwardSpeed
	s.Pitch = math.deg(math.asin(math.clamp(look:Dot(groundNormal), -1, 1)))
	s.PitchRate = math.deg(omega:Dot(right))
	s.Roll = math.deg(math.asin(math.clamp(right.Y, -1, 1)))
	s.FrontContact = front.Contact and front.Load > 0
	s.RearContact = rear.Contact and rear.Load > 0
	s.FrontCompression = front.Compression
	s.RearCompression = rear.Compression
	s.Airborne = not s.FrontContact and not s.RearContact
	s.InWheelie = not s.Crashed and s.RearContact and not s.FrontContact and s.Pitch > h.WheelieThreshold

	if rear.Contact then
		local surface = surfaceFor(rear.Material)
		s.SurfaceKind = surface.Kind
		s.SurfaceMaterial = rear.Material
	end

	-- Battery: drains with throttle, a little comes back under braking/regen.
	local power = 1
	if s.Battery <= PhysicsConfig.Battery.LowPowerThreshold then
		power = PhysicsConfig.Battery.LowPowerOutput
	end
	s.Battery = math.clamp(s.Battery - s.Throttle * dt / stats.BatterySeconds, 0, 1)

	if s.Crashed then
		zeroActuators()
		previousVelocity = velocity
		return
	end

	-- Steering angle shrinks with speed so the bike stays calm when fast.
	local steerTarget = if active then input.Steer else 0
	local maxSteer = math.rad(h.MaxSteerAngle) / (1 + math.abs(forwardSpeed) / h.SteerFalloffSpeed)
	s.SteerAngle = Utilities.smooth(s.SteerAngle, steerTarget * maxSteer, h.SteerResponse, dt)

	local topSpeed = h.TopSpeedLimited or h.TopSpeed
	local speedRatio = math.clamp(math.abs(forwardSpeed) / topSpeed, 0, 1.2)
	local torqueCurve = if forwardSpeed < 0 then 1 else math.clamp(1 - speedRatio ^ 2.2, 0, 1)
	local reversing = s.Brake > 0.5 and s.Throttle < 0.05 and forwardSpeed < 1.5

	local netForce = Vector3.zero
	local netTorque = Vector3.zero
	local tyreGrip = CustomisationConfig.TyreTypes[stats.TyreType] or CustomisationConfig.TyreTypes.Street
	local regenEnergy = 0
	local driveUsed = 0

	for _, wheel in wheels do
		if wheel.Contact and wheel.Load > 0 then
			local n = wheel.Normal
			local isFront = wheel == front
			local wheelLook = if isFront then CFrame.fromAxisAngle(up, -s.SteerAngle):VectorToWorldSpace(look) else look
			local along = wheelLook - n * wheelLook:Dot(n)
			if along.Magnitude < 1e-3 then
				continue
			end
			along = along.Unit
			local side = along:Cross(n)
			local pointVelocity = velocity + omega:Cross(wheel.Point - com)
			local vLong = pointVelocity:Dot(along)
			local vLat = pointVelocity:Dot(side)
			local surface = surfaceFor(wheel.Material)
			local mu = surface.Grip * ((tyreGrip :: any)[surface.Kind] or 1) * h.Grip
			local maxFriction = mu * wheel.Load
			local share = if totalLoad > 0 then wheel.Load / totalLoad else 0.5

			-- Drive and brakes.
			local long = 0
			if not isFront then
				if reversing then
					long = -mass * 12 * s.Brake * math.clamp(1 - (-vLong) / h.ReverseSpeed, 0, 1)
				else
					long = mass * h.MaxAccel * torqueCurve * s.Throttle * power
					if s.Throttle < 0.05 and math.abs(vLong) > 0.5 then
						local regen = mass * h.RegenDecel * math.min(1, math.abs(vLong) / 3)
						long -= math.sign(vLong) * regen
						regenEnergy += regen * math.abs(vLong)
					end
				end
				driveUsed = math.abs(long)
			end
			local brakeInput = if isFront then (if reversing then 0 else s.Brake) else math.max(s.RearBrake, s.Brake * 0.35)
			if brakeInput > 0 then
				local shareOfBrakes = if isFront then h.FrontBrakeShare else 1 - h.FrontBrakeShare
				local brakeForce = mass * h.BrakeDecel * shareOfBrakes * brakeInput
				if math.abs(vLong) > PhysicsConfig.Grip.StopSpeed then
					long -= math.sign(vLong) * brakeForce
				else
					long += math.clamp(-vLong * mass * share / dt * 0.5, -brakeForce, brakeForce)
				end
				regenEnergy += brakeForce * math.abs(vLong) * 0.3
			end
			long = math.clamp(long, -maxFriction, maxFriction)

			-- Sideways grip: remove part of the slip each frame, up to the grip limit.
			local lat = -vLat * (mass * share / dt) * PhysicsConfig.Grip.LateralStiffness
			lat = math.clamp(lat, -maxFriction, maxFriction)
			local combined = math.sqrt(long * long + lat * lat)
			local limit = maxFriction * PhysicsConfig.Grip.CombinedLimit
			if combined > limit then
				long *= limit / combined
				lat *= limit / combined
			end

			-- Forces act in the bike's centre plane so they don't fight the lean controller;
			-- grip acts at centre-of-mass height so cornering doesn't roll the bike over.
			-- Drive/brake act partway up towards the centre of mass: the full real lever arm made
			-- the nose run away faster than anyone can react (see DrivePitchShare).
			local contact = wheel.Point - right * (wheel.Point - com):Dot(right)
			local comHeight = (com - contact):Dot(n)
			local gripPoint = contact + n * comHeight
			local drivePoint = contact + n * comHeight * (1 - h.DrivePitchShare)
			local normal = n * wheel.Load
			local drive = along * long
			local grip = side * lat
			netForce += normal + drive + grip
			netTorque += (contact - com):Cross(normal) + (drivePoint - com):Cross(drive) + (gripPoint - com):Cross(grip)

			wheel.Spin -= vLong / g.WheelRadius * dt
		else
			-- A free wheel keeps spinning, slowly winding down (and spins up under throttle).
			local spinRate = if wheel == rear then -s.Throttle * 20 else 0
			wheel.Spin += spinRate * dt
		end
	end
	s.FrontSpin = front.Spin
	s.RearSpin = rear.Spin
	s.MotorLoad = math.clamp(driveUsed / math.max(mass * h.MaxAccel, 1), 0, 1)
	s.Battery = math.clamp(s.Battery + regenEnergy / (mass * 4000) * PhysicsConfig.Battery.RegenShare * dt, 0, 1)

	-- When the bike leans, the ground's push on the tyres no longer passes under the centre of
	-- mass, so on its own it tips the bike over like a pencil on its point (~m·g·h per radian,
	-- several times what the lean controller can hold). Real riders balance that with steering
	-- and body weight; here the roll controller below does the balancing, so the contact forces'
	-- roll torque is removed and lean is owned by the controller. Collisions still roll it.
	-- Lean is measured around the bike's heading along the ground, not its own nose, which points
	-- up at the sky in a wheelie.
	local heading = look - groundNormal * look:Dot(groundNormal)
	heading = if heading.Magnitude > 0.05 then heading.Unit else -up
	netTorque -= heading * netTorque:Dot(heading)

	-- Rolling resistance and air drag.
	local anyContact = s.FrontContact or s.RearContact
	if anyContact then
		netForce -= velocity * mass * PhysicsConfig.Grip.RollingResistance
	end
	netForce -= velocity * velocity.Magnitude * mass * PhysicsConfig.Grip.AeroDrag

	-- Inertia of the chassis box (the only part with mass).
	local size = part.Size
	local inertiaPitch = mass / 12 * (size.Y ^ 2 + size.Z ^ 2)
	local inertiaRoll = mass / 12 * (size.X ^ 2 + size.Y ^ 2)
	local inertiaYaw = mass / 12 * (size.X ^ 2 + size.Z ^ 2)

	-- Pitch: wheelie torques. G0 is gravity's torque on a flat bike about the rear axle.
	local halfBase = g.Wheelbase / 2
	local g0 = mass * gravity * halfBase
	local pivotHeight = g.MountDrop + g.SuspensionRest - 2 * g.StaticSag
	local pivotArm = math.sqrt(halfBase * halfBase + pivotHeight * pivotHeight)
	local pitchRate = math.rad(s.PitchRate)
	local pitchTorque = 0
	s.IdealAngle = h.IdealBalanceAngle
	if s.RearContact then
		local leanBack = math.max(s.Lean, 0)
		local liftShare = h.PassiveLiftShare + (1 - h.PassiveLiftShare) * leanBack
		-- Lift mostly survives at speed (the motor still has torque to spare for the wheel) and
		-- is boosted while the front is low so a wheelie pops quickly, then settles.
		local liftCurve = math.max(torqueCurve, h.HighSpeedLift)
		local pop = 1 + (h.PopBoost - 1) * math.max(0, 1 - math.max(s.Pitch, 0) / h.PopAngle)
		pitchTorque += s.Throttle * power * liftCurve * pop * h.WheelieLift * liftShare * g0
		pitchTorque += s.Lean * h.LeanShift * g0
		if not s.FrontContact and s.Pitch > 0 then
			pitchTorque -= s.RearBrake * h.RearBrakePitch * g0
			local fromIdeal = s.Pitch - h.IdealBalanceAngle
			if s.Pitch > h.WheelieThreshold and math.abs(fromIdeal) < h.AssistWindow then
				local assist = math.clamp(h.BalanceAssist * assistSetting * (1 - assistPenalty), 0, 1.2)
				pitchTorque -= assist * mass * gravity * pivotArm * math.rad(fromIdeal)
			end
			pitchTorque -= h.PitchDamping * (inertiaPitch + mass * pivotArm * pivotArm) * pitchRate
		else
			pitchTorque -= h.GroundPitchDamping * inertiaPitch * pitchRate
		end
	elseif not anyContact then
		pitchTorque += s.Lean * h.AirPitchControl * 0.3 * g0
		pitchTorque -= 0.8 * inertiaPitch * pitchRate
	end
	netTorque += right * pitchTorque

	-- Yaw: follow the bicycle-model yaw rate for the current steering angle.
	local yawRate = omega:Dot(groundNormal)
	if anyContact then
		local steerFactor = if s.InWheelie then h.WheelieSteerFactor else 1
		local targetYawRate = -(forwardSpeed * math.tan(s.SteerAngle) / g.Wheelbase) * steerFactor
		netTorque += groundNormal * inertiaYaw * h.YawGain * (targetYawRate - yawRate)
	else
		netTorque -= groundNormal * inertiaYaw * 2 * yawRate
	end

	-- Roll: lean into turns (and stand the bike up when stopped), around the ground heading so
	-- it works the same in a wheelie. Inertia around that axis blends roll and yaw with pitch.
	local maxLean = math.rad(h.MaxLeanAngle)
	local targetLean = if anyContact then math.clamp(math.atan(forwardSpeed * yawRate / gravity), -maxLean, maxLean) else 0
	local rollRad = math.rad(s.Roll)
	local rollRate = -omega:Dot(heading)
	local rollGain = if anyContact then 1 else 0.5
	local cosPitch = math.cos(math.rad(s.Pitch))
	local inertiaHeading = inertiaRoll * cosPitch * cosPitch + inertiaYaw * (1 - cosPitch * cosPitch)
	local rollTorque = inertiaHeading * rollGain * (h.RollStiffness * (targetLean - rollRad) - h.RollDamping * rollRate)
	netTorque -= heading * rollTorque

	driveForce.Force = netForce
	controlTorque.Torque = netTorque

	-- Crash checks.
	if s.Pitch > h.FallAngle then
		loopOutTimer += dt
		if loopOutTimer > 0.12 then
			crash("LoopedOut")
		end
	else
		loopOutTimer = 0
	end
	if math.abs(s.Roll) > h.CrashRollAngle or up.Y < 0.15 then
		crash("TippedOver")
	end
	if (velocity - previousVelocity).Magnitude > h.CrashImpactSpeed then
		crash("Impact")
	end
	previousVelocity = velocity
end

function BikeController.start(model: Model, stats: BikeStats.Stats, settingsAssist: number?)
	BikeController.stop()
	local part = model.PrimaryPart
	if not part then
		return
	end
	chassis = part
	driveForce = part:FindFirstChild("DriveForce") :: VectorForce?
	antiGravity = part:FindFirstChild("AntiGravity") :: VectorForce?
	controlTorque = part:FindFirstChild("ControlTorque") :: Torque?
	local bikesFolder = Workspace:FindFirstChild("Bikes")
	castParams.FilterDescendantsInstances = { bikesFolder or model, model }

	local s = BikeController.state
	s.Active = true
	s.Model = model
	s.Stats = stats
	s.Crashed = false
	s.Throttle, s.Lean, s.SteerAngle = 0, 0, 0
	s.Battery = 1
	assistSetting = settingsAssist or 1
	previousVelocity = part.AssemblyLinearVelocity
	loopOutTimer = 0
	for _, wheel in wheels do
		wheel.Compression, wheel.PrevCompression, wheel.Load = 0, 0, 0
	end
	connection = RunService.PreSimulation:Connect(step)
end

function BikeController.stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	zeroActuators()
	if antiGravity then
		antiGravity.Force = Vector3.zero
	end
	chassis, driveForce, antiGravity, controlTorque = nil, nil, nil, nil
	local s = BikeController.state
	s.Active = false
	s.Model = nil
	s.InWheelie = false
	s.Throttle = 0
end

-- Inputs are ignored (bike coasts) while menus are open or the rider has dismounted.
function BikeController.setInputEnabled(enabled: boolean)
	inputEnabled = enabled
end

function BikeController.clearCrash()
	BikeController.state.Crashed = false
	previousVelocity = if chassis then chassis.AssemblyLinearVelocity else Vector3.zero
	loopOutTimer = 0
end

function BikeController.setAssistPenalty(penalty: number)
	assistPenalty = math.clamp(penalty, 0, 1)
end

function BikeController.setAssistSetting(multiplier: number)
	assistSetting = math.clamp(multiplier, 0, 1.5)
end

function BikeController.onCrash(listener: (reason: string) -> ())
	table.insert(crashListeners, listener)
end

return BikeController
