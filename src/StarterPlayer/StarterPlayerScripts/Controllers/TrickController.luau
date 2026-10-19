--!strict
-- StarterPlayer > StarterPlayerScripts > Controllers > TrickController (ModuleScript)
-- Wheelie tricks. Held tricks (one-hander, no-hander, standing, leg out) are performed by
-- holding their button during a wheelie; auto tricks (seat tap, slow balance, sky high, combo)
-- are detected from how the wheelie is ridden. A trick scores once its conditions hold for its
-- HoldTime, then goes on cooldown. The current pose is published for RiderController and other
-- players, and some poses make balancing harder (BikeController assist penalty).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TrickDefinitions = require(ReplicatedStorage.Shared.TrickDefinitions)
local BikeController = require(script.Parent.BikeController)
local WheelieController = require(script.Parent.WheelieController)
local InputController = require(script.Parent.InputController)

local TrickController = {}

local INPUT_TRICKS: { TrickDefinitions.Trick } = {}
for _, trick in TrickDefinitions.List do
	if trick.Input ~= "Auto" then
		table.insert(INPUT_TRICKS, trick)
	end
end

TrickController.pose = "Seated"
TrickController.selectedIndex = 1 -- for the single trick button on touch/gamepad

local holdTimers: { [string]: number } = {}
local cooldowns: { [string]: number } = {}
local landedThisWheelie: { [string]: boolean } = {}
local selectedHeld = false
local standStart = 0
local lastSitTime = -math.huge
local wasStanding = false
local landedListeners: { (trick: TrickDefinitions.Trick) -> () } = {}
local connection: RBXScriptConnection? = nil

local function eligible(trick: TrickDefinitions.Trick): boolean
	local s = BikeController.state
	if not s.InWheelie then
		return false
	end
	local speed = math.abs(s.Speed)
	return s.Pitch >= trick.MinAngle and s.Pitch <= trick.MaxAngle and speed >= trick.MinSpeed and speed <= trick.MaxSpeed
end

local function land(trick: TrickDefinitions.Trick)
	cooldowns[trick.Id] = os.clock() + trick.Cooldown
	landedThisWheelie[trick.Id] = true
	WheelieController.addTrick(trick.Id)
	for _, listener in landedListeners do
		task.spawn(listener, trick)
	end
	-- Three different tricks in one wheelie earns the combo trick once.
	local distinct = 0
	for id in landedThisWheelie do
		if id ~= "LongCombo" then
			distinct += 1
		end
	end
	if distinct >= TrickDefinitions.ComboTricksNeeded and not landedThisWheelie.LongCombo then
		land(TrickDefinitions.ById.LongCombo)
	end
end

local function isHeld(trick: TrickDefinitions.Trick): boolean
	if InputController.state.Held[trick.Input] then
		return true
	end
	return selectedHeld and INPUT_TRICKS[TrickController.selectedIndex] == trick
end

local function step(dt: number)
	local s = BikeController.state
	if not s.Active or s.Crashed then
		TrickController.pose = if s.Crashed then "Crashed" else "Seated"
		BikeController.setAssistPenalty(0)
		table.clear(holdTimers)
		return
	end
	local now = os.clock()

	-- Held tricks: the newest held button wins the pose.
	local pose = "Seated"
	local penalty = 0
	for _, trick in INPUT_TRICKS do
		if isHeld(trick) then
			pose = trick.Pose or pose
			penalty = math.max(penalty, trick.AssistPenalty)
			if eligible(trick) and now >= (cooldowns[trick.Id] or 0) then
				holdTimers[trick.Id] = (holdTimers[trick.Id] or 0) + dt
				if holdTimers[trick.Id] >= trick.HoldTime then
					holdTimers[trick.Id] = -math.huge -- once per hold
					land(trick)
				end
			end
		else
			holdTimers[trick.Id] = 0
		end
	end
	TrickController.pose = pose
	BikeController.setAssistPenalty(penalty)

	if not WheelieController.isActive() then
		table.clear(landedThisWheelie)
		wasStanding = pose == "Standing"
		return
	end

	-- Seat tap: stand long enough, sit, and stand again quickly.
	local standing = pose == "Standing"
	if standing and not wasStanding then
		if now - lastSitTime <= TrickDefinitions.SeatTapWindow then
			local trick = TrickDefinitions.ById.SeatTap
			if eligible(trick) and now >= (cooldowns.SeatTap or 0) then
				land(trick)
			end
		end
		standStart = now
	elseif not standing and wasStanding then
		if now - standStart >= TrickDefinitions.SeatTapMinStand then
			lastSitTime = now
		end
	end
	wasStanding = standing

	-- Slow balance and sky high: ridden, not pressed.
	local slow = TrickDefinitions.ById.SlowBalance
	local nearIdeal = math.abs(s.Pitch - s.IdealAngle) <= TrickDefinitions.SlowBalanceWindow
	if s.InWheelie and nearIdeal and math.abs(s.Speed) >= slow.MinSpeed and math.abs(s.Speed) <= slow.MaxSpeed then
		holdTimers.SlowBalance = (holdTimers.SlowBalance or 0) + dt
		if holdTimers.SlowBalance >= slow.HoldTime and now >= (cooldowns.SlowBalance or 0) then
			holdTimers.SlowBalance = 0
			land(slow)
		end
	else
		holdTimers.SlowBalance = 0
	end
	local high = TrickDefinitions.ById.HighAngle
	if eligible(high) then
		holdTimers.HighAngle = (holdTimers.HighAngle or 0) + dt
		if holdTimers.HighAngle >= high.HoldTime and now >= (cooldowns.HighAngle or 0) then
			holdTimers.HighAngle = 0
			land(high)
		end
	else
		holdTimers.HighAngle = 0
	end
end

function TrickController.init()
	InputController.onAction(function(action)
		if action == "TrickHeld" then
			selectedHeld = true
		elseif action == "TrickReleased" then
			selectedHeld = false
		elseif action == "TrickNext" then
			TrickController.selectedIndex = TrickController.selectedIndex % #INPUT_TRICKS + 1
		elseif action == "TrickPrevious" then
			TrickController.selectedIndex = (TrickController.selectedIndex - 2) % #INPUT_TRICKS + 1
		end
	end)
	WheelieController.onStart(function()
		table.clear(landedThisWheelie)
	end)
	connection = RunService.Heartbeat:Connect(step)
end

function TrickController.selectedTrick(): TrickDefinitions.Trick
	return INPUT_TRICKS[TrickController.selectedIndex]
end

function TrickController.inputTricks(): { TrickDefinitions.Trick }
	return INPUT_TRICKS
end

function TrickController.onLanded(listener: (trick: TrickDefinitions.Trick) -> ())
	table.insert(landedListeners, listener)
end

function TrickController.destroy()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

return TrickController
