--!strict
-- ReplicatedStorage > Shared > EconomyConfig (ModuleScript)
-- Scoring, cash/XP rewards, levels, unlocks, milestones, daily challenges and codes.
-- `scoreWheelie` is shared so the HUD can preview a score, but only the server's result (from
-- validated numbers) ever pays out.

local TrickDefinitions = require(script.Parent.TrickDefinitions)

local EconomyConfig = {}

EconomyConfig.StartingCash = 1000

EconomyConfig.Score = {
	PointsPerMetre = 10,
	PointsPerSecond = 5,
	AngleBonusMax = 0.5, -- up to +50% for steep average angles
	SpeedBonusMax = 0.4, -- up to +40% for fast wheelies
	BalancePointsPerSecond = 15, -- time spent within ±8° of the bike's ideal angle
	ComboStep = 0.25, -- +25% per trick in the wheelie
	ComboCap = 8,
	CrashPenalty = 0.5, -- a crash ends the wheelie and keeps half the points
	MinDistance = 4, -- metres before a wheelie pays anything
}

EconomyConfig.Rewards = {
	CashPerPoint = 0.2,
	XpPerPoint = 0.2,
	MaxCashPerWheelie = 6000,
	ExploreZoneCash = 250,
	ExploreZoneXp = 100,
	RideCashPerKm = 40,
}

export type WheelieSummary = {
	Distance: number, -- metres
	Duration: number, -- seconds
	AvgAngle: number, -- degrees
	AvgSpeedMph: number,
	BalanceTime: number, -- seconds near the ideal angle
	Tricks: { string },
	Crashed: boolean,
}

function EconomyConfig.scoreWheelie(s: WheelieSummary): number
	local cfg = EconomyConfig.Score
	if s.Distance < cfg.MinDistance then
		return 0
	end
	local base = s.Distance * cfg.PointsPerMetre + s.Duration * cfg.PointsPerSecond
	local angleMult = 1 + math.clamp((s.AvgAngle - 15) / 60, 0, 1) * cfg.AngleBonusMax
	local speedMult = 1 + math.clamp(s.AvgSpeedMph / 50, 0, 1) * cfg.SpeedBonusMax
	local trickPoints = 0
	for _, id in s.Tricks do
		local trick = TrickDefinitions.ById[id]
		if trick then
			trickPoints += trick.Points
		end
	end
	local combo = 1 + math.min(#s.Tricks, cfg.ComboCap) * cfg.ComboStep
	local total = (base * angleMult * speedMult + s.BalanceTime * cfg.BalancePointsPerSecond + trickPoints) * combo
	if s.Crashed then
		total *= cfg.CrashPenalty
	end
	return math.floor(total)
end

function EconomyConfig.comboMultiplier(trickCount: number): number
	return 1 + math.min(trickCount, EconomyConfig.Score.ComboCap) * EconomyConfig.Score.ComboStep
end

-- XP needed to go from `level` to `level + 1`.
function EconomyConfig.xpForLevel(level: number): number
	return math.floor(100 * level ^ 1.45)
end

EconomyConfig.MaxLevel = 100

-- Shown in the level-up popup and the bikes screen. The real locks are the Level fields on each
-- bike, colour, option and upgrade.
EconomyConfig.LevelUnlocks = {
	{ Level = 1, Text = "Street E-Ride 60V" },
	{ Level = 3, Text = "Hi-vis and orange paint, riser bars, mixed tyres" },
	{ Level = 5, Text = "Light Bee Style 72V and more paint" },
	{ Level = 10, Text = "Ultra E-Moto 80V and reflective trim" },
	{ Level = 12, Text = "Big wheel kit" },
	{ Level = 15, Text = "Stage 3 upgrades and chequered decals" },
	{ Level = 20, Text = "MX Electric Pro, chrome paint, unlocked controller" },
	{ Level = 30, Text = "Neon Lime paint" },
	{ Level = 50, Text = "Prestige pearl paint and crown decal" },
}

-- One-off rewards for a single wheelie reaching each distance (metres).
EconomyConfig.Milestones = {
	{ Id = "W50", Distance = 50, Cash = 500, Xp = 100, Text = "First 50 m wheelie" },
	{ Id = "W100", Distance = 100, Cash = 1000, Xp = 200, Text = "100 m wheelie" },
	{ Id = "W250", Distance = 250, Cash = 2500, Xp = 500, Text = "250 m wheelie" },
	{ Id = "W500", Distance = 500, Cash = 5000, Xp = 1000, Text = "500 m wheelie" },
	{ Id = "W1000", Distance = 1000, Cash = 12000, Xp = 2500, Text = "1 km wheelie" },
}

-- Daily challenge pool. Three are picked each UTC day with a seed from the date, so every
-- server shows the same three.
--   SingleWheelie: one wheelie of Goal metres
--   TricksInCombo: Goal tricks in a single wheelie
--   RideDistance: ride Goal metres today
--   TotalWheelie: Goal metres of wheelie today
--   VisitZone: reach zone `Zone`
--   CleanWheelies: Goal wheelies of 20 m+ without crashing
--   BalanceTime: Goal seconds at the balance point in one wheelie
EconomyConfig.ChallengesPerDay = 3
EconomyConfig.ChallengePool = {
	{ Id = "Single50", Type = "SingleWheelie", Goal = 50, Text = "Do a 50 m wheelie", Cash = 600, Xp = 150 },
	{ Id = "Single100", Type = "SingleWheelie", Goal = 100, Text = "Do a 100 m wheelie", Cash = 1200, Xp = 300 },
	{ Id = "Single200", Type = "SingleWheelie", Goal = 200, Text = "Do a 200 m wheelie", Cash = 2500, Xp = 600 },
	{ Id = "Total500", Type = "TotalWheelie", Goal = 500, Text = "Wheelie 500 m in total", Cash = 1500, Xp = 400 },
	{ Id = "Combo3", Type = "TricksInCombo", Goal = 3, Text = "Land 3 tricks in one wheelie", Cash = 1500, Xp = 400 },
	{ Id = "Combo2", Type = "TricksInCombo", Goal = 2, Text = "Land 2 tricks in one wheelie", Cash = 800, Xp = 200 },
	{ Id = "Ride5k", Type = "RideDistance", Goal = 5000, Text = "Ride 5 km", Cash = 1200, Xp = 300 },
	{ Id = "Ride2k", Type = "RideDistance", Goal = 2000, Text = "Ride 2 km", Cash = 500, Xp = 120 },
	{ Id = "VisitIndustrial", Type = "VisitZone", Zone = "Industrial", Goal = 1, Text = "Visit the industrial estate", Cash = 400, Xp = 100 },
	{ Id = "VisitCountry", Type = "VisitZone", Zone = "Countryside", Goal = 1, Text = "Ride out to the countryside", Cash = 400, Xp = 100 },
	{ Id = "VisitStrip", Type = "VisitZone", Zone = "WheelieStrip", Goal = 1, Text = "Hit the wheelie strip", Cash = 300, Xp = 80 },
	{ Id = "Clean5", Type = "CleanWheelies", Goal = 5, Text = "Five 20 m+ wheelies without crashing", Cash = 1000, Xp = 250 },
	{ Id = "Balance5", Type = "BalanceTime", Goal = 5, Text = "Hold the balance point for 5 s", Cash = 1000, Xp = 250 },
}

function EconomyConfig.dayIndex(unixTime: number): number
	return math.floor(unixTime / 86400)
end

-- The day's challenges. Deterministic, so the client can list them without asking the server.
function EconomyConfig.dailyChallenges(day: number): { any }
	local pool = table.clone(EconomyConfig.ChallengePool)
	local rng = Random.new(day * 7919 + 17)
	local picked = {}
	for _ = 1, math.min(EconomyConfig.ChallengesPerDay, #pool) do
		local index = rng:NextInteger(1, #pool)
		table.insert(picked, pool[index])
		table.remove(pool, index)
	end
	return picked
end

-- Redeemable codes (CODES menu). Each can be used once per player.
EconomyConfig.Codes = {
	WHEELIECITY = { Cash = 1500, Xp = 0 },
	VOLTUP = { Cash = 750, Xp = 250 },
}

return EconomyConfig
