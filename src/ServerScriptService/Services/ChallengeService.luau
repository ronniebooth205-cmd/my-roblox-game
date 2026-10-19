--!strict
-- ServerScriptService > Services > ChallengeService (ModuleScript)
-- Daily challenges. The day's three are chosen from EconomyConfig.ChallengePool using the UTC
-- date (server clock), so every server and the client agree on them. Progress is only ever
-- fed by validated server events (wheelies from TrickService, ride distance from BikeService
-- samples, zone visits from MapService), and rewards are paid automatically on completion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage.Shared.EconomyConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)

local ChallengeService = {}

local function today(): number
	return EconomyConfig.dayIndex(os.time())
end

-- Returns the player's challenge record, resetting it when the day rolls over.
local function record(player: Player): { [string]: any }?
	local profile = PlayerDataService.get(player)
	if not profile then
		return nil
	end
	local day = today()
	local c = profile.Challenges
	if c.Day ~= day then
		profile.Challenges = { Day = day, Progress = {}, Claimed = {}, CleanStreak = 0 }
		c = profile.Challenges
		PlayerDataService.push(player)
	end
	return c
end

local function update(player: Player, kind: string, apply: (challenge: any, current: number) -> number)
	local c = record(player)
	if not c then
		return
	end
	local changed = false
	for _, challenge in EconomyConfig.dailyChallenges(c.Day) do
		if challenge.Type == kind and not c.Claimed[challenge.Id] then
			local current = c.Progress[challenge.Id] or 0
			local new = apply(challenge, current)
			if new ~= current then
				c.Progress[challenge.Id] = new
				changed = true
			end
			if new >= challenge.Goal then
				c.Claimed[challenge.Id] = true
				EconomyService.grant(player, challenge.Cash, challenge.Xp, "Challenge complete: " .. challenge.Text, "Challenge")
			end
		end
	end
	if changed then
		PlayerDataService.push(player)
	end
end

function ChallengeService.onWheelie(player: Player, summary: EconomyConfig.WheelieSummary)
	update(player, "SingleWheelie", function(_, current)
		return math.max(current, math.floor(summary.Distance))
	end)
	update(player, "TotalWheelie", function(_, current)
		return current + math.floor(summary.Distance)
	end)
	local distinct = {}
	for _, id in summary.Tricks do
		if id ~= "LongCombo" then
			distinct[id] = true
		end
	end
	local count = 0
	for _ in distinct do
		count += 1
	end
	update(player, "TricksInCombo", function(_, current)
		return math.max(current, count)
	end)
	update(player, "BalanceTime", function(_, current)
		return math.max(current, math.floor(summary.BalanceTime))
	end)
	local c = record(player)
	if c and summary.Distance >= 20 and not summary.Crashed then
		c.CleanStreak = (c.CleanStreak or 0) + 1
		update(player, "CleanWheelies", function(_, current)
			return math.max(current, c.CleanStreak)
		end)
	end
end

function ChallengeService.onCrash(player: Player)
	local c = record(player)
	if c then
		c.CleanStreak = 0
	end
end

function ChallengeService.onRide(player: Player, metres: number)
	update(player, "RideDistance", function(_, current)
		return current + metres
	end)
end

function ChallengeService.onZone(player: Player, zoneId: string)
	update(player, "VisitZone", function(challenge, current)
		return if challenge.Zone == zoneId then 1 else current
	end)
end

function ChallengeService.init() end

function ChallengeService.start()
	PlayerDataService.onLoaded(function(player)
		record(player)
	end)
end

return ChallengeService
