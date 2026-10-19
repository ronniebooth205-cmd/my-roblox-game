--!strict
-- StarterPlayer > StarterPlayerScripts > UI > HUD (ModuleScript)
-- The in-game HUD: level/XP/cash, quick buttons, the semicircle speedometer, bike name and
-- battery, the wheelie panel (distance, predicted score, combo multiplier, best) with a balance
-- meter, trick popups, reward popups, toasts, zone banners and context prompts. The wheelie
-- panel only becomes prominent during a wheelie. Animations are throttled and respect
-- reduced motion.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Utilities = require(ReplicatedStorage.Shared.Utilities)
local EconomyConfig = require(ReplicatedStorage.Shared.EconomyConfig)
local BikeDefinitions = require(ReplicatedStorage.Shared.BikeDefinitions)
local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Controllers = script.Parent.Parent.Controllers
local BikeController = require(Controllers.BikeController)
local WheelieController = require(Controllers.WheelieController)
local TrickController = require(Controllers.TrickController)
local InputController = require(Controllers.InputController)
local ClientState = require(Controllers.ClientState)

local HUD = {}

local C = Theme.Colors
local new = Components.new

local root: Frame
local elements: { [string]: any } = {}
local riding = false
local reducedMotion = false
local showSpeedo = true
local units = "MPH"
local wheelieAlpha = 0
local lastZone: string? = nil
local actions: { [string]: () -> () } = {}

local GAUGE_TICKS = 25
local GAUGE_SWEEP = 240 -- degrees

------------------------------------------------------------------------ building blocks

local function corner(parent: Instance, radius: UDim?)
	Components.corner(parent, radius)
end

local function glassPanel(props: { [string]: any }): Frame
	local frame = new("Frame", {
		BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = root,
	})
	for k, v in props do
		(frame :: any)[k] = v
	end
	corner(frame, Theme.Radius.Large)
	Components.stroke(frame, C.Stroke, 1, 0.5)
	return frame
end

local function buildTopBar()
	local bar = glassPanel({ Name = "TopBar", Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(290, 66) })
	local badge = new("Frame", { BackgroundColor3 = C.Accent, Position = UDim2.fromOffset(10, 9), Size = UDim2.fromOffset(48, 48), Parent = bar })
	corner(badge, Theme.Radius.Pill)
	elements.Level = Components.text(badge, "1", 22, C.AccentText, Theme.Fonts.Display, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	elements.Cash = Components.text(bar, "£0", 22, C.Text, Theme.Fonts.Display, { Position = UDim2.fromOffset(70, 8), Size = UDim2.new(1, -80, 0, 26) })
	local xpHolder = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(70, 42), Size = UDim2.new(1, -84, 0, 8), Parent = bar })
	local xpBar = Components.bar(xpHolder, C.Accent, 8)
	xpBar.Frame.Size = UDim2.fromScale(1, 1)
	elements.XpBar = xpBar
	elements.XpText = Components.text(bar, "", 11, C.TextMuted, Theme.Fonts.Heading, { Position = UDim2.fromOffset(70, 50), Size = UDim2.new(1, -84, 0, 14) })
end

local function buildQuickButtons()
	local row = new("Frame", {
		Name = "QuickButtons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(360, 52),
		Parent = root,
	})
	local layout = Components.list(row, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	for i, entry in { { "Rideout", "👥" }, { "Challenges", "★" }, { "Map", "🗺" }, { "Garage", "🔧" }, { "Menu", "☰" } } do
		local b = Components.button(row, entry[2], if entry[1] == "Menu" then "Primary" else "Secondary", function()
			local fn = actions[entry[1]]
			if fn then
				fn()
			end
		end, { Size = UDim2.fromOffset(52, 52), LayoutOrder = i, TextSize = 22 })
		b.Name = entry[1]
	end
end

local function buildSpeedometer()
	local gauge = glassPanel({
		Name = "Speedometer",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -20),
		Size = UDim2.fromOffset(240, 168),
		Visible = false,
	})
	local centre = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 104), Size = UDim2.fromOffset(0, 0), Parent = gauge })
	local ticks = {}
	for i = 0, GAUGE_TICKS - 1 do
		local angle = -GAUGE_SWEEP / 2 + GAUGE_SWEEP * i / (GAUGE_TICKS - 1)
		local holder = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(4, 176), Rotation = angle, Parent = centre })
		local tick = new("Frame", {
			BackgroundColor3 = C.SurfaceHover,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(if i % 4 == 0 then 6 else 4, if i % 4 == 0 then 18 else 12),
			Parent = holder,
		})
		corner(tick, Theme.Radius.Pill)
		ticks[i + 1] = tick
	end
	elements.GaugeTicks = ticks
	local needleHolder = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(4, 150), Parent = centre })
	local needle = new("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(4, 62), Parent = needleHolder })
	corner(needle, Theme.Radius.Pill)
	elements.Needle = needleHolder
	elements.Speed = Components.text(gauge, "0", 46, C.Text, Theme.Fonts.Display, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(140, 50), TextXAlignment = Enum.TextXAlignment.Center })
	elements.SpeedUnit = Components.text(gauge, "MPH", 13, C.TextMuted, Theme.Fonts.Heading, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 116), Size = UDim2.fromOffset(140, 16), TextXAlignment = Enum.TextXAlignment.Center })
	-- Throttle and brake strips along the bottom.
	local throttleHolder = new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 16, 1, -22), Size = UDim2.new(0.5, -22, 0, 6), Parent = gauge })
	local throttleBar = Components.bar(throttleHolder, C.Accent, 6)
	throttleBar.Frame.Size = UDim2.fromScale(1, 1)
	elements.ThrottleBar = throttleBar
	local brakeHolder = new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.5, 6, 1, -22), Size = UDim2.new(0.5, -22, 0, 6), Parent = gauge })
	local brakeBar = Components.bar(brakeHolder, C.Danger, 6)
	brakeBar.Frame.Size = UDim2.fromScale(1, 1)
	elements.BrakeBar = brakeBar
	elements.Speedometer = gauge
end

local function buildBikeInfo()
	local info = glassPanel({ Name = "BikeInfo", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, -20), Size = UDim2.fromOffset(250, 74), Visible = false })
	elements.BikeName = Components.text(info, "", 16, C.Text, Theme.Fonts.Heading, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 20) })
	Components.text(info, "BATTERY", 11, C.TextMuted, Theme.Fonts.Heading, { Position = UDim2.fromOffset(14, 36), Size = UDim2.fromOffset(80, 14) })
	elements.BatteryText = Components.text(info, "100%", 11, C.Accent, Theme.Fonts.Heading, { Position = UDim2.new(1, -74, 0, 36), Size = UDim2.fromOffset(60, 14), TextXAlignment = Enum.TextXAlignment.Right })
	local holder = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 54), Size = UDim2.new(1, -28, 0, 8), Parent = info })
	local bar = Components.bar(holder, C.Accent, 8)
	bar.Frame.Size = UDim2.fromScale(1, 1)
	elements.BatteryBar = bar
	elements.BikeInfo = info
end

local function buildWheeliePanel()
	local panel = new("CanvasGroup", {
		Name = "WheeliePanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.fromOffset(340, 120),
		BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.3,
		GroupTransparency = 1,
		Parent = root,
	})
	corner(panel, Theme.Radius.Large)
	elements.WheelieDistance = Components.text(panel, "0 m", 48, C.Text, Theme.Fonts.Display, { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 52), TextXAlignment = Enum.TextXAlignment.Center })
	elements.WheelieScore = Components.text(panel, "0 PTS", 18, C.Accent, Theme.Fonts.Heading, { Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center })
	elements.WheelieCombo = Components.text(panel, "x1.00", 16, C.Gold, Theme.Fonts.Display, { Position = UDim2.fromOffset(16, 90), Size = UDim2.new(0.5, -16, 0, 20) })
	elements.WheelieBest = Components.text(panel, "BEST 0 m", 13, C.TextMuted, Theme.Fonts.Heading, { Position = UDim2.new(0.5, 0, 0, 92), Size = UDim2.new(0.5, -16, 0, 18), TextXAlignment = Enum.TextXAlignment.Right })
	elements.WheeliePanel = panel

	-- Balance meter: pitch against the bike's ideal angle (green band) and the loop-out zone.
	local meter = new("CanvasGroup", {
		Name = "BalanceMeter",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.45, 0),
		Size = UDim2.fromOffset(36, 240),
		BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.3,
		GroupTransparency = 1,
		Parent = root,
	})
	corner(meter, Theme.Radius.Pill)
	local track = new("Frame", { BackgroundColor3 = C.SurfaceRaised, BorderSizePixel = 0, Position = UDim2.fromOffset(13, 12), Size = UDim2.new(0, 10, 1, -24), Parent = meter })
	corner(track, Theme.Radius.Pill)
	local zone = new("Frame", { BackgroundColor3 = C.Accent, BackgroundTransparency = 0.25, BorderSizePixel = 0, Size = UDim2.fromScale(1, 0.18), Parent = track })
	corner(zone, Theme.Radius.Pill)
	local danger = new("Frame", { BackgroundColor3 = C.Danger, BackgroundTransparency = 0.3, BorderSizePixel = 0, Size = UDim2.fromScale(1, 0.1), Parent = track })
	corner(danger, Theme.Radius.Pill)
	local marker = new("Frame", { BackgroundColor3 = C.Text, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(28, 6), Parent = track })
	corner(marker, Theme.Radius.Pill)
	elements.BalanceMeter = meter
	elements.BalanceZone = zone
	elements.BalanceDanger = danger
	elements.BalanceMarker = marker

	local feed = new("Frame", { Name = "TrickFeed", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 218), Size = UDim2.fromOffset(320, 140), Parent = root })
	Components.list(feed, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center)
	elements.TrickFeed = feed
end

local function buildPrompt()
	local prompt = new("Frame", { Name = "Prompt", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(320, 56), Parent = root })
	local button = Components.button(prompt, "SPAWN BIKE", "Primary", function()
		local fn = actions.Prompt
		if fn then
			fn()
		end
	end, { Size = UDim2.fromScale(1, 1), TextSize = 20 })
	elements.PromptButton = button
	elements.Prompt = prompt
	elements.Hint = Components.text(root, "", 14, C.TextMuted, Theme.Fonts.Heading, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -84),
		Size = UDim2.fromOffset(520, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.6,
	})
end

local function buildToasts()
	local holder = new("Frame", { Name = "Toasts", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.fromOffset(420, 200), Parent = root })
	Components.list(holder, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)
	elements.Toasts = holder
	elements.Banner = Components.text(root, "", 34, C.Text, Theme.Fonts.Display, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(700, 44),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		TextTransparency = 1,
		TextStrokeColor3 = Color3.new(0, 0, 0),
	})
end

------------------------------------------------------------------------ dynamic pieces

local function fadeOut(label: TextLabel, delay: number)
	task.delay(delay, function()
		if label.Parent then
			local tween = TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 })
			tween:Play()
			tween.Completed:Wait()
			label:Destroy()
		end
	end)
end

function HUD.toast(text: string, kind: string?)
	local colour = if kind == "Warning" then C.Warning elseif kind == "Error" then C.Danger elseif kind == "Reward" or kind == "Challenge" or kind == "Milestone" then C.Accent else C.Text
	local toast = new("TextLabel", {
		BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.15,
		Text = text,
		TextColor3 = colour,
		Font = Theme.Fonts.Heading,
		TextSize = 16,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(420, 40),
		Parent = elements.Toasts,
	})
	corner(toast, Theme.Radius.Medium)
	Components.padding(toast, 12, 8)
	task.delay(4, function()
		if toast.Parent then
			TweenService:Create(toast, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			task.wait(0.45)
			toast:Destroy()
		end
	end)
end

function HUD.banner(text: string, colour: Color3?)
	local banner = elements.Banner :: TextLabel
	banner.Text = text
	banner.TextColor3 = colour or C.Text
	banner.TextTransparency = 0
	banner.TextStrokeTransparency = 0.5
	if not reducedMotion then
		banner.Position = UDim2.fromScale(0.5, 0.33)
		TweenService:Create(banner, Theme.Tween.Normal, { Position = UDim2.fromScale(0.5, 0.3) }):Play()
	end
	task.delay(2.2, function()
		if banner.Text == text then
			TweenService:Create(banner, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

local function floatPopup(text: string, colour: Color3, size: number, startY: number)
	local label = Components.text(root, text, size, colour, Theme.Fonts.Display, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, startY),
		Size = UDim2.fromOffset(600, size + 10),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
	})
	if not reducedMotion then
		TweenService:Create(label, TweenInfo.new(1.6, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(0.5, startY - 0.08) }):Play()
	end
	fadeOut(label, 1.2)
end

function HUD.trickLanded(name: string, points: number)
	local label = Components.text(elements.TrickFeed, string.format("%s  +%d", name:upper(), points), 20, C.Gold, Theme.Fonts.Display, {
		Size = UDim2.fromOffset(320, 26),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
	})
	if not reducedMotion then
		local scale = new("UIScale", { Scale = 1.4, Parent = label })
		TweenService:Create(scale, Theme.Tween.Pop, { Scale = 1 }):Play()
	end
	fadeOut(label, 1.8)
end

function HUD.notify(payload: { [string]: any })
	if payload.Kind == "Wheelie" then
		local text = string.format("%s  ·  %s PTS", Utilities.formatDistance(payload.Distance or 0), Utilities.formatNumber(payload.Score or 0))
		floatPopup(text, C.Text, 30, 0.42)
		task.delay(0.25, function()
			floatPopup(string.format("+%s   +%d XP", Utilities.formatCash(payload.Cash or 0), payload.Xp or 0), C.Accent, 24, 0.48)
		end)
		if payload.Best then
			HUD.banner("NEW PERSONAL BEST!", C.Gold)
		end
	elseif payload.Kind == "LevelUp" then
		HUD.banner("LEVEL " .. tostring(payload.Level) .. "!", C.Accent)
		for _, unlock in payload.Unlocks or {} do
			HUD.toast("Unlocked: " .. unlock, "Reward")
		end
	else
		local text = payload.Text or ""
		if payload.Cash and payload.Cash > 0 then
			text ..= string.format("  +%s", Utilities.formatCash(payload.Cash))
		end
		if payload.Xp and payload.Xp > 0 then
			text ..= string.format("  +%d XP", payload.Xp)
		end
		HUD.toast(text, payload.Kind)
	end
end

------------------------------------------------------------------------ per-frame update

local function setProfile(profile: { [string]: any })
	elements.Level.Text = tostring(profile.Level)
	elements.Cash.Text = Utilities.formatCash(profile.Cash)
	local need = EconomyConfig.xpForLevel(profile.Level)
	elements.XpBar.set(profile.Xp / math.max(need, 1))
	elements.XpText.Text = string.format("%s / %s XP", Utilities.formatNumber(profile.Xp), Utilities.formatNumber(need))
	elements.WheelieBest.Text = "BEST " .. Utilities.formatDistance(profile.Stats.LongestWheelie)
	local def = BikeDefinitions.get(profile.EquippedBike)
	elements.BikeName.Text = if def then def.DisplayName:upper() else ""
end

function HUD.update(dt: number)
	local s = BikeController.state
	local stats = s.Stats
	if riding and stats then
		local speed = math.abs(s.Speed)
		local display = if units == "KMH" then Utilities.studsPerSecondToKmh(speed) else Utilities.studsPerSecondToMph(speed)
		local top = Utilities.studsPerSecondToMph(stats.Handling.TopSpeed) * (if units == "KMH" then 1.609 else 1)
		local frac = math.clamp(display / math.max(top * 1.1, 1), 0, 1)
		elements.Speed.Text = tostring(math.floor(display + 0.5))
		elements.SpeedUnit.Text = units
		elements.Needle.Rotation = -GAUGE_SWEEP / 2 + GAUGE_SWEEP * frac
		local lit = math.floor(frac * GAUGE_TICKS + 0.5)
		for i, tick in elements.GaugeTicks do
			local on = i <= lit
			local colour = if not on then C.SurfaceHover elseif i > GAUGE_TICKS * 0.85 then C.Danger else C.Accent
			if tick.BackgroundColor3 ~= colour then
				tick.BackgroundColor3 = colour
			end
		end
		elements.ThrottleBar.set(s.Throttle)
		elements.BrakeBar.set(math.max(s.Brake, s.RearBrake))
		elements.BatteryBar.set(s.Battery, if s.Battery < 0.15 then C.Danger elseif s.Battery < 0.35 then C.Warning else C.Accent)
		elements.BatteryText.Text = string.format("%d%%", math.floor(s.Battery * 100))
	end

	-- Wheelie panel fades in while wheelieing and lingers briefly after.
	local active = WheelieController.isActive()
	local target = if active then 1 else 0
	wheelieAlpha = Utilities.smooth(wheelieAlpha, target, if active then 0.08 else 0.5, dt)
	elements.WheeliePanel.GroupTransparency = 1 - wheelieAlpha
	elements.BalanceMeter.GroupTransparency = 1 - wheelieAlpha
	if active then
		local session = WheelieController.session
		elements.WheelieDistance.Text = Utilities.formatDistance(session.Distance)
		elements.WheelieScore.Text = Utilities.formatNumber(session.PredictedScore) .. " PTS"
		elements.WheelieCombo.Text = string.format("x%.2f", EconomyConfig.comboMultiplier(#session.Tricks))
	end
	if wheelieAlpha > 0.01 and stats then
		local h = stats.Handling
		local function y(angle: number): number
			return 1 - math.clamp(angle / 90, 0, 1)
		end
		elements.BalanceZone.Position = UDim2.fromScale(0, y(h.IdealBalanceAngle + 8))
		elements.BalanceZone.Size = UDim2.fromScale(1, 16 / 90)
		elements.BalanceDanger.Position = UDim2.fromScale(0, 0)
		elements.BalanceDanger.Size = UDim2.fromScale(1, y(h.FallAngle - 6))
		elements.BalanceMarker.Position = UDim2.fromScale(0.5, y(s.Pitch))
		local near = math.abs(s.Pitch - h.IdealBalanceAngle) <= 8
		elements.BalanceMarker.BackgroundColor3 = if s.Pitch > h.FallAngle - 6 then C.Danger elseif near then C.Accent else C.Text
	end

	-- Zone banners when entering a new part of the map.
	local character = Players.LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if rootPart then
		local zone = MapLayout.zoneAt(rootPart.Position)
		local id = zone and zone.Id
		if id ~= lastZone then
			lastZone = id
			if zone then
				HUD.banner(zone.Name:upper(), zone.Colour)
			end
		end
	end
end

------------------------------------------------------------------------ public API

function HUD.init(screen: ScreenGui, handlers: { [string]: () -> () })
	actions = handlers
	root = new("Frame", { Name = "HUD", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = screen })
	buildTopBar()
	buildQuickButtons()
	buildSpeedometer()
	buildBikeInfo()
	buildWheeliePanel()
	buildPrompt()
	buildToasts()
	ClientState.onProfile(setProfile)
	TrickController.onLanded(function(trick)
		HUD.trickLanded(trick.Name, trick.Points)
	end)
	BikeController.onCrash(function(reason)
		local text = if reason == "LoopedOut" then "LOOPED OUT!" elseif reason == "TippedOver" then "BAILED!" else "CRASHED!"
		HUD.banner(text, C.Danger)
	end)
end

function HUD.setRiding(isRiding: boolean)
	riding = isRiding
	elements.Speedometer.Visible = isRiding and showSpeedo
	elements.BikeInfo.Visible = isRiding
end

-- Bottom-centre call to action: a button (spawn/ride) or nothing while riding.
function HUD.setPrompt(text: string?)
	elements.Prompt.Visible = text ~= nil
	if text then
		elements.PromptButton.Text = text
	end
end

function HUD.setHint(text: string)
	elements.Hint.Text = text
end

function HUD.applySettings(settings: { [string]: any })
	reducedMotion = settings.ReducedMotion == true
	showSpeedo = settings.ShowSpeedometer ~= false
	units = settings.Units or "MPH"
	elements.Speedometer.Visible = riding and showSpeedo
end

-- On touch screens the bottom corners belong to the riding buttons, so the gauge and bike
-- info move up out of the way.
function HUD.setTouchLayout(touch: boolean, leftHanded: boolean)
	if touch then
		elements.Speedometer.AnchorPoint = Vector2.new(0.5, 0)
		elements.Speedometer.Position = UDim2.new(0.5, 0, 0, 92)
		elements.Speedometer.Size = UDim2.fromOffset(200, 140)
		elements.WheeliePanel.Position = UDim2.new(0.5, 0, 0, 240)
		elements.TrickFeed.Position = UDim2.new(0.5, 0, 0, 366)
		-- Balance meter on the edge away from the utility buttons, short enough to clear the
		-- riding buttons below it.
		elements.BalanceMeter.AnchorPoint = Vector2.new(if leftHanded then 0 else 1, 0.5)
		elements.BalanceMeter.Position = if leftHanded then UDim2.new(0, 16, 0.3, 0) else UDim2.new(1, -16, 0.3, 0)
		elements.BalanceMeter.Size = UDim2.fromOffset(30, 160)
		elements.BikeInfo.AnchorPoint = Vector2.new(if leftHanded then 1 else 0, 0)
		elements.BikeInfo.Position = if leftHanded then UDim2.new(1, -16, 0, 92) else UDim2.fromOffset(16, 92)
		elements.Prompt.Position = UDim2.new(0.5, 0, 1, -16)
	else
		elements.Speedometer.AnchorPoint = Vector2.new(1, 1)
		elements.Speedometer.Position = UDim2.new(1, -20, 1, -20)
		elements.Speedometer.Size = UDim2.fromOffset(240, 168)
		elements.BikeInfo.AnchorPoint = Vector2.new(0, 1)
		elements.BikeInfo.Position = UDim2.new(0, 20, 1, -20)
		elements.WheeliePanel.Position = UDim2.new(0.5, 0, 0, 92)
		elements.TrickFeed.Position = UDim2.new(0.5, 0, 0, 218)
		elements.BalanceMeter.AnchorPoint = Vector2.new(1, 0.5)
		elements.BalanceMeter.Position = UDim2.new(1, -24, 0.45, 0)
		elements.BalanceMeter.Size = UDim2.fromOffset(36, 240)
		elements.Prompt.Position = UDim2.new(0.5, 0, 1, -24)
	end
end

function HUD.root(): Frame
	return root
end

function HUD.keyHint(action: string): string
	local device = InputController.device()
	if device == "Gamepad" then
		local pad = { Mount = "X", Recover = "Y", Camera = "LB", Throttle = "RT", Brake = "LT", LeanBack = "Right stick ↓", RearBrake = "A" }
		return pad[action] or "?"
	elseif device == "Touch" then
		return ""
	end
	return InputController.keyName(action)
end

return HUD
