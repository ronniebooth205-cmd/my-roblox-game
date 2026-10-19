--!strict
-- ReplicatedStorage > Shared > TrickDefinitions (ModuleScript)
-- Wheelie tricks. Input tricks are held with a key/button; Auto tricks are detected from how
-- the wheelie is ridden. A trick only scores once its conditions have held for `HoldTime`.
-- The server re-checks every submitted trick against these rules (TrickService).
--   AssistPenalty: how much balance assist the pose takes away (harder to balance one-handed).
--   Pose: rider pose name used by RiderController.

export type Trick = {
	Id: string,
	Name: string,
	Input: string, -- "Trick1".."Trick4" or "Auto"
	MinAngle: number,
	MaxAngle: number,
	MinSpeed: number, -- studs/s
	MaxSpeed: number,
	HoldTime: number,
	Points: number,
	Cooldown: number,
	Pose: string?,
	AssistPenalty: number,
	Description: string,
}

local list: { Trick } = {
	{
		Id = "OneHand",
		Name = "One-Hander",
		Input = "Trick1",
		MinAngle = 15,
		MaxAngle = 75,
		MinSpeed = 4,
		MaxSpeed = math.huge,
		HoldTime = 1.0,
		Points = 150,
		Cooldown = 3,
		Pose = "OneHand",
		AssistPenalty = 0.15,
		Description = "Let go with one hand mid-wheelie.",
	},
	{
		Id = "NoHander",
		Name = "No-Hander",
		Input = "Trick2",
		MinAngle = 20,
		MaxAngle = 72,
		MinSpeed = 8,
		MaxSpeed = math.huge,
		HoldTime = 0.8,
		Points = 400,
		Cooldown = 5,
		Pose = "NoHands",
		AssistPenalty = 0.4,
		Description = "Both hands off the bars. Risky.",
	},
	{
		Id = "Standing",
		Name = "Standing Wheelie",
		Input = "Trick3",
		MinAngle = 12,
		MaxAngle = 75,
		MinSpeed = 3,
		MaxSpeed = math.huge,
		HoldTime = 1.5,
		Points = 250,
		Cooldown = 3,
		Pose = "Standing",
		AssistPenalty = 0.05,
		Description = "Stand on the pegs while on one wheel.",
	},
	{
		Id = "SeatTap",
		Name = "Seat Tap",
		Input = "Auto",
		MinAngle = 15,
		MaxAngle = 75,
		MinSpeed = 3,
		MaxSpeed = math.huge,
		HoldTime = 0,
		Points = 200,
		Cooldown = 2,
		Pose = nil,
		AssistPenalty = 0,
		Description = "Stand for a second, sit, and stand straight back up.",
	},
	{
		Id = "LegOut",
		Name = "Leg Extension",
		Input = "Trick4",
		MinAngle = 15,
		MaxAngle = 72,
		MinSpeed = 5,
		MaxSpeed = math.huge,
		HoldTime = 1.0,
		Points = 220,
		Cooldown = 4,
		Pose = "LegOut",
		AssistPenalty = 0.2,
		Description = "Swing a leg out to the side.",
	},
	{
		Id = "SlowBalance",
		Name = "Slow Balance",
		Input = "Auto",
		MinAngle = 0, -- checked against the bike's ideal angle instead (±8°)
		MaxAngle = 90,
		MinSpeed = 1,
		MaxSpeed = 13,
		HoldTime = 2.5,
		Points = 350,
		Cooldown = 6,
		Pose = nil,
		AssistPenalty = 0,
		Description = "Hold the balance point at walking pace.",
	},
	{
		Id = "HighAngle",
		Name = "Sky High",
		Input = "Auto",
		MinAngle = 62,
		MaxAngle = 90,
		MinSpeed = 3,
		MaxSpeed = math.huge,
		HoldTime = 1.5,
		Points = 300,
		Cooldown = 6,
		Pose = nil,
		AssistPenalty = 0,
		Description = "Hang it past 62 degrees.",
	},
	{
		Id = "LongCombo",
		Name = "Combo King",
		Input = "Auto",
		MinAngle = 0,
		MaxAngle = 90,
		MinSpeed = 0,
		MaxSpeed = math.huge,
		HoldTime = 0,
		Points = 500,
		Cooldown = 0,
		Pose = nil,
		AssistPenalty = 0,
		Description = "Land three different tricks in one wheelie.",
	},
}

local byId: { [string]: Trick } = {}
for _, trick in list do
	byId[trick.Id] = trick
end

return {
	List = list,
	ById = byId,
	SlowBalanceWindow = 8, -- degrees either side of the ideal angle
	SeatTapWindow = 0.8, -- seconds between sitting and standing again
	SeatTapMinStand = 1.0,
	ComboTricksNeeded = 3,
}
