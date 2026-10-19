--!strict
-- StarterPlayer > StarterPlayerScripts > UI > ProgressUI (ModuleScript)
-- Challenges and progress: today's daily challenges with progress bars, distance milestones,
-- career stats, level unlocks, and the trick list with how to perform each trick on the
-- current device. Read-only: progress comes from the server-owned profile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage.Shared.EconomyConfig)
local TrickDefinitions = require(ReplicatedStorage.Shared.TrickDefinitions)
local Utilities = require(ReplicatedStorage.Shared.Utilities)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Controllers = script.Parent.Parent.Controllers
local ClientState = require(Controllers.ClientState)
local InputController = require(Controllers.InputController)

local ProgressUI = {}

local C = Theme.Colors
local new = Components.new

local modal: Components.Modal
local content: ScrollingFrame
local tabs: { select: (name: string) -> () }
local currentTab = "Challenges"

local function card(order: number, height: number): Frame
	local frame = Components.panel(content, { Size = UDim2.new(1, -8, 0, height), LayoutOrder = order, BackgroundColor3 = C.SurfaceRaised })
	Components.padding(frame, 14, 10)
	return frame
end

local function challenges(p: { [string]: any })
	local day = EconomyConfig.dayIndex(os.time())
	local record = p.Challenges
	local sameDay = record and record.Day == day
	Components.text(content, "New challenges every day (UTC). Rewards pay out automatically.", 13, C.TextMuted, Theme.Fonts.Body, { LayoutOrder = 0 })
	for i, challenge in EconomyConfig.dailyChallenges(day) do
		local progress = if sameDay then (record.Progress[challenge.Id] or 0) else 0
		local done = sameDay and record.Claimed[challenge.Id] == true
		local frame = card(i, 92)
		Components.text(frame, challenge.Text, 17, if done then C.Accent else C.Text, Theme.Fonts.Heading, { Size = UDim2.new(0.7, 0, 0, 22) })
		Components.text(frame, string.format("%s  ·  +%d XP", Utilities.formatCash(challenge.Cash), challenge.Xp), 14, C.Gold, Theme.Fonts.Heading, {
			Position = UDim2.new(0.7, 0, 0, 0),
			Size = UDim2.new(0.3, 0, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		local holder = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 10), Parent = frame })
		local bar = Components.bar(holder, C.Accent, 10)
		bar.Frame.Size = UDim2.fromScale(1, 1)
		bar.set(if done then 1 else progress / challenge.Goal)
		local unit = if challenge.Type == "RideDistance" or challenge.Type == "SingleWheelie" or challenge.Type == "TotalWheelie" then " m" elseif challenge.Type == "BalanceTime" then " s" else ""
		Components.text(frame, if done then "COMPLETE ✓" else string.format("%d / %d%s", math.floor(progress), challenge.Goal, unit), 13, C.TextMuted, Theme.Fonts.Heading, { Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 18) })
	end
end

local function milestones(p: { [string]: any })
	for i, m in EconomyConfig.Milestones do
		local done = p.Milestones[m.Id] == true
		local frame = card(i, 64)
		Components.text(frame, (if done then "✓  " else "") .. m.Text, 17, if done then C.Accent else C.Text, Theme.Fonts.Heading, { Size = UDim2.new(0.65, 0, 1, 0) })
		Components.text(frame, string.format("%s  ·  +%d XP", Utilities.formatCash(m.Cash), m.Xp), 14, C.Gold, Theme.Fonts.Heading, {
			Position = UDim2.fromScale(0.65, 0),
			Size = UDim2.fromScale(0.35, 1),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
	end
	Components.text(content, "LEVEL UNLOCKS", Theme.TextSize.Caption, C.TextMuted, Theme.Fonts.Heading, { LayoutOrder = 50 })
	for i, unlock in EconomyConfig.LevelUnlocks do
		local reached = p.Level >= unlock.Level
		Components.text(content, string.format("Lv %d  —  %s", unlock.Level, unlock.Text), 15, if reached then C.Accent else C.TextMuted, Theme.Fonts.Heading, { LayoutOrder = 50 + i })
	end
end

local function stats(p: { [string]: any })
	local s = p.Stats
	local rows = {
		{ "Level", tostring(p.Level) },
		{ "Longest wheelie", Utilities.formatDistance(s.LongestWheelie) },
		{ "Best wheelie score", Utilities.formatNumber(s.BestScore) },
		{ "Total wheelie distance", Utilities.formatDistance(s.TotalWheelieDistance) },
		{ "Total riding distance", Utilities.formatDistance(s.TotalRideDistance) },
		{ "Wheelies", Utilities.formatNumber(s.Wheelies) },
		{ "Tricks landed", Utilities.formatNumber(s.TotalTricks) },
		{ "Crashes", Utilities.formatNumber(s.Crashes) },
		{ "Cash earned", Utilities.formatCash(s.TotalCashEarned) },
	}
	local owned = 0
	for _ in p.OwnedBikes do
		owned += 1
	end
	table.insert(rows, { "Bikes owned", tostring(owned) })
	for i, row in rows do
		local frame = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 34), LayoutOrder = i, Parent = content })
		Components.text(frame, row[1], 16, C.TextMuted, Theme.Fonts.Heading, { Size = UDim2.fromScale(0.6, 1) })
		Components.text(frame, row[2], 18, C.Text, Theme.Fonts.Display, { Position = UDim2.fromScale(0.6, 0), Size = UDim2.fromScale(0.4, 1), TextXAlignment = Enum.TextXAlignment.Right })
	end
end

local function tricks()
	local device = InputController.device()
	Components.text(content, if device == "Keyboard"
		then "Tricks are toggles: press a trick key to start the move, press it again to stop. Combine them!"
		elseif device == "Gamepad" then "Pick a trick with the D-pad, press RB to switch it on or off."
		else "Pick a trick with the selector, tap TRICK to switch it on or off.", 14, C.TextMuted, Theme.Fonts.Body, { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 36) })
	for i, trick in TrickDefinitions.List do
		local frame = card(i, 74)
		local how = if trick.Input == "Auto" then "AUTO" elseif device == "Keyboard" then "[" .. InputController.keyName(trick.Input) .. "]" else "TRICK"
		Components.text(frame, trick.Name:upper(), 17, C.Text, Theme.Fonts.Heading, { Size = UDim2.new(0.6, 0, 0, 22) })
		Components.text(frame, string.format("%s  ·  +%d", how, trick.Points), 14, C.Gold, Theme.Fonts.Heading, { Position = UDim2.fromScale(0.6, 0), Size = UDim2.new(0.4, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Right })
		Components.text(frame, trick.Description, 13, C.TextMuted, Theme.Fonts.Body, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 30) })
	end
end

local function render()
	Components.clear(content)
	local p = ClientState.profile
	if not p then
		return
	end
	if currentTab == "Challenges" then
		challenges(p)
	elseif currentTab == "Milestones" then
		milestones(p)
	elseif currentTab == "Stats" then
		stats(p)
	else
		tricks()
	end
end

function ProgressUI.init(screen: ScreenGui)
	modal = Components.modal(screen, "Progress", 0.5, 0.8)
	local tabHolder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = modal.Body })
	tabs = Components.tabs(tabHolder, { "Challenges", "Milestones", "Stats", "Tricks" }, function(name)
		currentTab = name
		render()
	end)
	content = Components.scroll(modal.Body, { Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 1, -54) })
	Components.list(content, Enum.FillDirection.Vertical, 8)
	Components.padding(content, 2, 4)
	ClientState.onProfile(function()
		if modal.isOpen() then
			render()
		end
	end)
end

function ProgressUI.open(tab: string?)
	modal.open()
	tabs.select(tab or "Challenges")
end

function ProgressUI.modal(): Components.Modal
	return modal
end

return ProgressUI
