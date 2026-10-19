--!strict
-- StarterPlayer > StarterPlayerScripts > Controllers > WheelieController (ModuleScript)
-- Watches the bike for wheelies and keeps a running session: distance, time, angles, balance
-- time and tricks. The HUD shows a predicted score from this; when the front wheel touches
-- down (or the rider crashes) the summary is sent to the server, which checks it against its
-- own position samples before paying anything (TrickService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EconomyConfig = require(ReplicatedStorage.Shared.EconomyConfig)
local TrickDefinitions = require(ReplicatedStorage.Shared.TrickDefinitions)
local Utilities = require(ReplicatedStorage.Shared.Utilities)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local BikeController = require(script.Parent.BikeController)

local WheelieController = {}

export type Session = {
	Active: boolean,
	StartTime: number,
	Duration: number,
	Distance: number, -- metres
	AngleSum: number,
	SpeedSum: number,
	Samples: number,
	MaxAngle: number,
	BalanceTime: number,
	Tricks: { string },
	LastPosition: Vector3,
	PredictedScore: number,
}

local session: Session = {
	Active = false,
	StartTime = 0,
	Duration = 0,
	Distance = 0,
	AngleSum = 0,
	SpeedSum = 0,
	Samples = 0,
	MaxAngle = 0,
	BalanceTime = 0,
	Tricks = {},
	LastPosition = Vector3.zero,
	PredictedScore = 0,
}
WheelieController.session = session

local START_DELAY = 0.12 -- front wheel must be up this long to count
local END_DELAY = 0.15 -- and down this long to end (stops bounces splitting a wheelie)
local upTimer = 0
local downTimer = 0
local connection: RBXScriptConnection? = nil
local startListeners: { () -> () } = {}
local endListeners: { (summary: EconomyConfig.WheelieSummary, score: number) -> () } = {}
local wheelieRemote: RemoteEvent? = nil

local function summary(crashed: boolean): EconomyConfig.WheelieSummary
	local samples = math.max(session.Samples, 1)
	return {
		Distance = session.Distance,
		Duration = session.Duration,
		AvgAngle = session.AngleSum / samples,
		AvgSpeedMph = session.SpeedSum / samples,
		BalanceTime = session.BalanceTime,
		Tricks = table.clone(session.Tricks),
		Crashed = crashed,
	}
end

local function begin(position: Vector3)
	session.Active = true
	session.StartTime = os.clock()
	session.Duration = 0
	session.Distance = 0
	session.AngleSum = 0
	session.SpeedSum = 0
	session.Samples = 0
	session.MaxAngle = 0
	session.BalanceTime = 0
	session.Tricks = {}
	session.LastPosition = position
	session.PredictedScore = 0
	if wheelieRemote then
		wheelieRemote:FireServer("Start")
	end
	for _, listener in startListeners do
		task.spawn(listener)
	end
end

local function finish(crashed: boolean)
	if not session.Active then
		return
	end
	session.Active = false
	local result = summary(crashed)
	local score = EconomyConfig.scoreWheelie(result)
	if wheelieRemote then
		wheelieRemote:FireServer("End", result)
	end
	for _, listener in endListeners do
		task.spawn(listener, result, score)
	end
end

local function step(dt: number)
	local s = BikeController.state
	local model = s.Model
	if not s.Active or not model or not model.PrimaryPart then
		if session.Active then
			finish(false)
		end
		return
	end
	local position = model.PrimaryPart.Position

	if s.InWheelie then
		downTimer = 0
		upTimer += dt
		if not session.Active and upTimer >= START_DELAY then
			begin(position)
		end
	else
		upTimer = 0
		if session.Active then
			downTimer += dt
			if downTimer >= END_DELAY then
				finish(false)
			end
		end
	end

	if session.Active then
		local flat = Vector3.new(position.X - session.LastPosition.X, 0, position.Z - session.LastPosition.Z)
		session.Distance += Utilities.studsToMetres(flat.Magnitude)
		session.LastPosition = position
		session.Duration += dt
		if s.InWheelie then
			session.AngleSum += s.Pitch
			session.SpeedSum += Utilities.studsPerSecondToMph(math.abs(s.Speed))
			session.Samples += 1
			session.MaxAngle = math.max(session.MaxAngle, s.Pitch)
			if math.abs(s.Pitch - s.IdealAngle) <= TrickDefinitions.SlowBalanceWindow then
				session.BalanceTime += dt
			end
		end
		session.PredictedScore = EconomyConfig.scoreWheelie(summary(false))
	end
end

function WheelieController.init()
	wheelieRemote = Remotes.event("Wheelie")
	BikeController.onCrash(function()
		finish(true)
	end)
	connection = RunService.Heartbeat:Connect(step)
end

function WheelieController.addTrick(trickId: string)
	if session.Active and TrickDefinitions.ById[trickId] then
		table.insert(session.Tricks, trickId)
	end
end

function WheelieController.isActive(): boolean
	return session.Active
end

function WheelieController.elapsed(): number
	return if session.Active then os.clock() - session.StartTime else 0
end

function WheelieController.onStart(listener: () -> ())
	table.insert(startListeners, listener)
end

function WheelieController.onEnd(listener: (summary: EconomyConfig.WheelieSummary, score: number) -> ())
	table.insert(endListeners, listener)
end

function WheelieController.destroy()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

return WheelieController
