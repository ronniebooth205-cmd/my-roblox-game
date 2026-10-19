--!strict
-- StarterPlayer > StarterPlayerScripts > Controllers > TrickController (ModuleScript)
-- Wheelie tricks. Input tricks (one-hander, no-hander, standing, leg out, hype dance) are
-- toggles: press once to start the move, again to stop. They can be combined (standing
-- one-hander...). A toggled move scores once its conditions hold for its HoldTime during a
-- wheelie, then again on the next wheelie or after re-toggling. Auto tricks (seat tap, slow balance, sky high, combo)
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
local active: { [string]: boolean } = {} -- toggled input tricks by id
local toggleListeners: { () -> () } = {}
-- Pose flags in the order they're published (BikeService validates each one).
local POSE_ORDER = { "Standing", "OneHand", "NoHands", "LegOut", "Hype" }
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

local function setActive(trick: TrickDefinitions.Trick, on: boolean)
	if (active[trick.Id] == true) == on then
		return
	end
	active[trick.Id] = if on then true else nil
	holdTimers[trick.Id] = 0
	for _, listener in toggleListeners do
		task.spawn(listener)
	end
end

function TrickController.toggle(trick: TrickDefinitions.Trick)
	setActive(trick, not active[trick.Id])
end

function TrickController.isActive(trickId: string): boolean
	return active[trickId] == true
end

function TrickController.clear()
	for _, trick in INPUT_TRICKS do
		setActive(trick, false)
	end
end

function TrickController.onToggled(listener: () -> ())
	table.insert(toggleListeners, listener)
end

local function step(dt: number)
	local s = BikeController.state
	if not s.Active or s.Crashed then
		TrickController.pose = if s.Crashed then "Crashed" else "Seated"
		BikeController.setAssistPenalty(0)
		if next(active) then
			TrickController.clear()
		end
		table.clear(holdTimers)
		return
	end
	local now = os.clock()

	-- Toggled tricks combine into one pose; balance gets as hard as the hardest move.
	local flags: { [string]: boolean } = {}
	local penalty = 0
	for _, trick in INPUT_TRICKS do
		if active[trick.Id] then
			if trick.Pose then
				flags[trick.Pose] = true
			end
			penalty = math.max(penalty, trick.AssistPenalty)
			if eligible(trick) and now >= (cooldowns[trick.Id] or 0) then
				holdTimers[trick.Id] = (holdTimers[trick.Id] or 0) + dt
				if holdTimers[trick.Id] >= trick.HoldTime then
					holdTimers[trick.Id] = -math.huge -- once per toggle (resets each wheelie)
					land(trick)
				end
			end
		end
	end
	local parts = {}
	for _, flag in POSE_ORDER do
		if flags[flag] then
			table.insert(parts, flag)
		end
	end
	local pose = if #parts > 0 then table.concat(parts, ",") else "Seated"
	TrickController.pose = pose
	BikeController.setAssistPenalty(penalty)
	local standingNow = flags.Standing == true or flags.Hype == true

	if not WheelieController.isActive() then
		table.clear(landedThisWheelie)
		wasStanding = standingNow
		return
	end

	-- Seat tap: stand long enough, sit, and stand again quickly.
	local standing = standingNow
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
		local index = tonumber(action:match("^Trick(%d)$"))
		if index then
			for _, trick in INPUT_TRICKS do
				if trick.Input == action then
					TrickController.toggle(trick)
				end
			end
		elseif action == "TrickToggle" then
			TrickController.toggle(INPUT_TRICKS[TrickController.selectedIndex])
		elseif action == "TrickNext" then
			TrickController.selectedIndex = TrickController.selectedIndex % #INPUT_TRICKS + 1
		elseif action == "TrickPrevious" then
			TrickController.selectedIndex = (TrickController.selectedIndex - 2) % #INPUT_TRICKS + 1
		end
	end)
	WheelieController.onStart(function()
		table.clear(landedThisWheelie)
		-- Moves still toggled on score again in the new wheelie.
		for id in active do
			holdTimers[id] = 0
		end
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
