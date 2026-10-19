--!strict
-- StarterPlayer > StarterPlayerScripts > UI > MapUI (ModuleScript)
-- The M-key map: every road and zone from MapLayout drawn to scale, live dots for players
-- (your rideout group highlighted) and the rideout meeting points. Rideout leaders can tap a
-- meeting point to set it for the group. Player dots refresh a few times a second only while
-- the map is open.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)

local MapUI = {}

local C = Theme.Colors
local new = Components.new

local modal: Components.Modal
local canvas: Frame
local dots: { [Player]: Frame } = {}
local MIN = Vector2.new(-1700, -720)
local MAX = Vector2.new(1150, 1100)
local isLeader: () -> boolean = function()
	return false
end

local function toMap(x: number, z: number): UDim2
	return UDim2.fromScale((x - MIN.X) / (MAX.X - MIN.X), (z - MIN.Y) / (MAX.Y - MIN.Y))
end

local function rectFrame(parent: Instance, a: Vector2, b: Vector2, colour: Color3, transparency: number, z: number): Frame
	local p0 = toMap(math.min(a.X, b.X), math.min(a.Y, b.Y))
	local p1 = toMap(math.max(a.X, b.X), math.max(a.Y, b.Y))
	return new("Frame", {
		BackgroundColor3 = colour,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		Position = p0,
		Size = UDim2.fromScale(p1.X.Scale - p0.X.Scale, p1.Y.Scale - p0.Y.Scale),
		ZIndex = z,
		Parent = parent,
	})
end

local function draw()
	Components.clear(canvas)
	for _, zone in MapLayout.Zones do
		for _, rect in zone.Rects do
			rectFrame(canvas, rect[1], rect[2], zone.Colour, 0.86, 21)
		end
		local first = zone.Rects[1]
		local centre = (first[1] + first[2]) / 2
		local label = Components.text(canvas, zone.Name:upper(), 12, zone.Colour, Theme.Fonts.Heading, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = toMap(centre.X, centre.Y),
			Size = UDim2.fromOffset(200, 16),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 24,
		})
		label.TextStrokeTransparency = 0.4
	end
	for _, road in MapLayout.Roads do
		local half = road.Width / 2
		if road.A.Y == road.B.Y then
			rectFrame(canvas, Vector2.new(road.A.X, road.A.Y - half), Vector2.new(road.B.X, road.B.Y + half), C.Text, 0.15, 22)
		else
			rectFrame(canvas, Vector2.new(road.A.X - half, road.A.Y), Vector2.new(road.B.X + half, road.B.Y), C.Text, 0.15, 22)
		end
	end
	for _, point in MapLayout.MeetPoints do
		local marker = Components.button(canvas, "◎", "Primary", function()
			if isLeader() then
				Remotes.event("Rideout"):FireServer("SetMeet", point.Id)
			end
		end, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = toMap(point.Position.X, point.Position.Z),
			Size = UDim2.fromOffset(30, 30),
			TextSize = 16,
			ZIndex = 25,
		})
		marker.Name = "Meet_" .. point.Id
	end
	table.clear(dots)
end

local function updateDots()
	local me = Players.LocalPlayer
	local myGroup = me:GetAttribute("RideoutId")
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local dot = dots[player]
		if root then
			if not dot then
				dot = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12), ZIndex = 30, Parent = canvas })
				Components.corner(dot :: Frame, Theme.Radius.Pill)
				Components.stroke(dot :: Frame, Color3.new(0, 0, 0), 2, 0)
				dots[player] = dot :: Frame
			end
			local d = dot :: Frame
			d.Position = toMap(root.Position.X, root.Position.Z)
			local grouped = myGroup ~= nil and player:GetAttribute("RideoutId") == myGroup
			d.BackgroundColor3 = if player == me then C.Accent elseif grouped then C.Gold else C.Info
			d.Size = if player == me then UDim2.fromOffset(16, 16) else UDim2.fromOffset(12, 12)
		elseif dot then
			dot:Destroy()
			dots[player] = nil
		end
	end
	for player, dot in dots do
		if not player.Parent then
			dot:Destroy()
			dots[player] = nil
		end
	end
end

function MapUI.init(screen: ScreenGui, leaderCheck: () -> boolean)
	isLeader = leaderCheck
	modal = Components.modal(screen, "Map", 0.86, 0.86)
	local holder = new("Frame", { BackgroundColor3 = Color3.fromRGB(30, 46, 30), Size = UDim2.fromScale(1, 1), ClipsDescendants = true, Parent = modal.Body })
	Components.corner(holder)
	canvas = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), Parent = holder })
	new("UIAspectRatioConstraint", { AspectRatio = (MAX.X - MIN.X) / (MAX.Y - MIN.Y), Parent = canvas })
	Components.text(holder, "Green: you · Gold: your rideout · Blue: other riders · ◎ meeting points (rideout leaders tap to set)", 12, C.TextMuted, Theme.Fonts.Heading, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -6),
		Size = UDim2.new(1, -20, 0, 16),
		ZIndex = 40,
	})
	draw()
end

function MapUI.open()
	modal.open()
	task.spawn(function()
		while modal.isOpen() do
			updateDots()
			task.wait(0.25)
		end
	end)
end

function MapUI.modal(): Components.Modal
	return modal
end

return MapUI
