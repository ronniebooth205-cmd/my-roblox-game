--!strict
-- ServerScriptService > Services > TrickService (ModuleScript)
-- Turns wheelie claims from clients into rewards, but only after checking them against what
-- the server itself saw. The client's summary is an upper bound, never the truth:
--   * time: capped by the server's clock between the Start and End messages
--   * distance: capped by the bike's own replicated movement (BikeService samples)
--   * wheelie: most server samples in that window must show the nose up
--   * speed: capped by the bike's real top speed with the player's upgrades
--   * tricks: known ids only, within cooldown and hold-time limits for the wheelie's length
-- The score is then recalculated here with EconomyConfig.scoreWheelie.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage.Shared.EconomyConfig)
local TrickDefinitions = require(ReplicatedStorage.Shared.TrickDefinitions)
local BikeStats = require(ReplicatedStorage.Shared.BikeStats)
local PhysicsConfig = require(ReplicatedStorage.Shared.PhysicsConfig)
local Utilities = require(ReplicatedStorage.Shared.Utilities)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local BikeService = require(script.Parent.BikeService)

local TrickService = {}

local Services: any = nil
local sessions: { [Player]: { Start: number, BikeId: string } } = {}
local limiter = Utilities.newRateLimiter(6, 3)

local MIN_WHEELIE_SHARE = 0.6
local MAX_TRICKS = 16

local function validTricks(raw: any, duration: number): { string }
	local result = {}
	if type(raw) ~= "table" then
		return result
	end
	local counts: { [string]: number } = {}
	local distinct: { [string]: boolean } = {}
	for i, id in raw do
		if type(i) ~= "number" or i > MAX_TRICKS * 2 then
			break
		end
		local trick = type(id) == "string" and TrickDefinitions.ById[id]
		if trick and id ~= "LongCombo" and #result < MAX_TRICKS then
			local allowed = math.floor(duration / math.max(trick.Cooldown + trick.HoldTime, 0.5)) + 1
			if trick.HoldTime <= duration and (counts[id] or 0) < allowed then
				counts[id] = (counts[id] or 0) + 1
				distinct[id] = true
				table.insert(result, id)
			end
		end
	end
	local distinctCount = 0
	for _ in distinct do
		distinctCount += 1
	end
	if distinctCount >= TrickDefinitions.ComboTricksNeeded then
		table.insert(result, "LongCombo")
	end
	return result
end

local function onWheelie(player: Player, action: any, payload: any)
	if type(action) ~= "string" or not limiter:check(player) then
		return
	end
	if action == "Start" then
		local model = BikeService.getBike(player)
		if model and BikeService.isRiding(player) then
			sessions[player] = { Start = os.clock(), BikeId = model:GetAttribute("BikeId") :: string }
		end
		return
	end
	if action ~= "End" or type(payload) ~= "table" then
		return
	end
	local session = sessions[player]
	sessions[player] = nil
	local profile = PlayerDataService.get(player)
	if not session or not profile then
		return
	end
	local now = os.clock()
	local serverDuration = now - session.Start

	local function num(value: any, lo: number, hi: number): number
		if type(value) ~= "number" or value ~= value then
			return lo
		end
		return math.clamp(value, lo, hi)
	end

	-- What the server saw: distance and nose-up share over the wheelie's window.
	local serverDistance = 0
	local noseUp, total = 0, 0
	local previous = nil
	for _, sample in BikeService.getSamples(player) do
		if sample.Time >= session.Start - 0.3 and sample.Time <= now + 0.1 then
			total += 1
			if sample.Pitch > PhysicsConfig.Handling.WheelieThreshold * 0.5 then
				noseUp += 1
			end
			if previous and sample.Valid then
				local d = sample.Position - previous.Position
				serverDistance += Vector3.new(d.X, 0, d.Z).Magnitude
			end
			previous = sample
		end
	end

	local duration = math.min(num(payload.Duration, 0, 3600), serverDuration + 0.4)
	if duration > 1 and total >= 3 and noseUp / total < MIN_WHEELIE_SHARE then
		warn(string.format("[TrickService] rejected wheelie from %s: nose up in %d/%d samples", player.Name, noseUp, total))
		return
	end
	local stats = BikeStats.compute(session.BikeId, profile.BikeSetups[session.BikeId])
	local maxMph = Utilities.studsPerSecondToMph(stats.Handling.TopSpeed * 1.1)
	local maxDistance = math.min(
		Utilities.studsToMetres(serverDistance) * 1.15 + 3,
		Utilities.studsToMetres(stats.Handling.TopSpeed * 1.1 * duration) + 2
	)

	local summary: EconomyConfig.WheelieSummary = {
		Distance = math.min(num(payload.Distance, 0, 100000), maxDistance),
		Duration = duration,
		AvgAngle = num(payload.AvgAngle, 0, 85),
		AvgSpeedMph = math.min(num(payload.AvgSpeedMph, 0, 500), maxMph),
		BalanceTime = math.min(num(payload.BalanceTime, 0, 3600), duration),
		Tricks = validTricks(payload.Tricks, duration),
		Crashed = payload.Crashed == true,
	}
	local score = EconomyConfig.scoreWheelie(summary)
	if score <= 0 then
		return
	end

	local rewards = EconomyConfig.Rewards
	local cash = math.min(math.floor(score * rewards.CashPerPoint), rewards.MaxCashPerWheelie)
	local xp = math.floor(score * rewards.XpPerPoint)
	local s = profile.Stats
	local isBest = summary.Distance > s.LongestWheelie
	s.TotalWheelieDistance += summary.Distance
	s.LongestWheelie = math.max(s.LongestWheelie, summary.Distance)
	s.BestScore = math.max(s.BestScore, score)
	s.TotalTricks += #summary.Tricks
	s.Wheelies += 1
	EconomyService.grant(player, cash, xp)
	Remotes.event("Notify"):FireClient(player, {
		Kind = "Wheelie",
		Score = score,
		Cash = cash,
		Xp = xp,
		Distance = summary.Distance,
		Best = isBest,
		Tricks = summary.Tricks,
	})

	for _, milestone in EconomyConfig.Milestones do
		if summary.Distance >= milestone.Distance and not profile.Milestones[milestone.Id] then
			profile.Milestones[milestone.Id] = true
			EconomyService.grant(player, milestone.Cash, milestone.Xp, "Milestone: " .. milestone.Text, "Milestone")
		end
	end
	if Services.ChallengeService then
		Services.ChallengeService.onWheelie(player, summary)
	end
	if Services.MultiplayerService then
		Services.MultiplayerService.onWheelie(player, summary.Distance, isBest)
	end
end

function TrickService.init(services: any)
	Services = services
	Remotes.event("Wheelie").OnServerEvent:Connect(onWheelie)
end

function TrickService.start()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		limiter:clear(player)
	end)
end

return TrickService
