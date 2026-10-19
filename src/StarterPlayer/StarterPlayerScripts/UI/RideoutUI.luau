--!strict
-- StarterPlayer > StarterPlayerScripts > UI > RideoutUI (ModuleScript)
-- Rideout groups: start a group, invite anyone in the server, accept/decline invites, see
-- members, kick (leader), pick a meeting point (leader) and leave. Group members get a
-- floating marker over each other's heads and a marker on the meeting point, visible through
-- buildings. All group rules are enforced by MultiplayerService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)

local RideoutUI = {}

local C = Theme.Colors
local new = Components.new

local modal: Components.Modal
local content: ScrollingFrame
local group: { [string]: any }? = nil
local markers: { [number]: BillboardGui } = {}
local meetMarker: BillboardGui? = nil
local inviteFrame: Frame
local pendingInvite: string? = nil

local function send(action: string, arg: any?)
	Remotes.event("Rideout"):FireServer(action, arg)
end

local function render()
	Components.clear(content)
	local me = Players.LocalPlayer
	if not group then
		Components.text(content, "Ride with friends: start a rideout, invite riders, and pick a meeting point.", 15, C.TextMuted, Theme.Fonts.Body, { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 40) })
		Components.button(content, "START A RIDEOUT", "Primary", function()
			send("Create")
		end, { LayoutOrder = 1 })
		return
	end
	local g = group :: { [string]: any }
	local leader = g.Leader == me.UserId
	Components.text(content, "YOUR RIDEOUT", Theme.TextSize.Caption, C.Accent, Theme.Fonts.Heading, { LayoutOrder = 0 })
	for i, member in g.Members do
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 44), LayoutOrder = i, Parent = content })
		Components.text(row, (if member.UserId == g.Leader then "★ " else "") .. member.Name, 17, C.Text, Theme.Fonts.Heading, { Size = UDim2.fromScale(0.7, 1) })
		if leader and member.UserId ~= me.UserId then
			Components.button(row, "KICK", "Ghost", function()
				send("Kick", member.UserId)
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(90, 38), TextSize = 14 })
		end
	end
	local order = 20
	Components.text(content, "MEETING POINT", Theme.TextSize.Caption, C.Accent, Theme.Fonts.Heading, { LayoutOrder = order })
	for _, point in MapLayout.MeetPoints do
		order += 1
		local chosen = g.Meet == point.Id
		Components.button(content, point.Name .. (if chosen then "  ✓" else ""), if chosen then "Primary" else "Secondary", function()
			if leader then
				send("SetMeet", point.Id)
			end
		end, { LayoutOrder = order, TextSize = 15 })
	end
	order += 1
	Components.text(content, "INVITE RIDERS", Theme.TextSize.Caption, C.Accent, Theme.Fonts.Heading, { LayoutOrder = order })
	local inGroup: { [number]: boolean } = {}
	for _, member in g.Members do
		inGroup[member.UserId] = true
	end
	for _, player in Players:GetPlayers() do
		if not inGroup[player.UserId] then
			order += 1
			local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 44), LayoutOrder = order, Parent = content })
			Components.text(row, player.DisplayName, 16, C.Text, Theme.Fonts.Heading, { Size = UDim2.fromScale(0.65, 1) })
			Components.button(row, "INVITE", "Secondary", function()
				send("Invite", player.UserId)
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(110, 38), TextSize = 14 })
		end
	end
	order += 1
	Components.button(content, "LEAVE RIDEOUT", "Danger", function()
		send("Leave")
	end, { LayoutOrder = order + 1 })
end

local function billboard(adornee: Instance, text: string, colour: Color3): BillboardGui
	local gui = new("BillboardGui", {
		Size = UDim2.fromOffset(160, 40),
		StudsOffset = Vector3.new(0, 4, 0),
		AlwaysOnTop = true,
		MaxDistance = 2000,
		LightInfluence = 0,
		Parent = adornee,
	})
	local label = Components.text(gui, text, 16, colour, Theme.Fonts.Display, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	label.TextStrokeTransparency = 0.3
	label.Name = "Label"
	return gui
end

local function updateMarkers()
	local me = Players.LocalPlayer
	local wanted: { [number]: boolean } = {}
	local myRoot = me.Character and me.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if group then
		for _, member in (group :: any).Members do
			if member.UserId ~= me.UserId then
				local player = Players:GetPlayerByUserId(member.UserId)
				local head = player and player.Character and player.Character:FindFirstChild("Head")
				if head then
					wanted[member.UserId] = true
					local marker = markers[member.UserId]
					if not marker or marker.Parent ~= head then
						if marker then
							marker:Destroy()
						end
						marker = billboard(head, member.Name, C.Gold)
						markers[member.UserId] = marker
					end
					if myRoot then
						local label = (marker :: BillboardGui):FindFirstChild("Label") :: TextLabel
						local metres = math.floor((((head :: BasePart).Position - myRoot.Position).Magnitude * 0.32))
						label.Text = string.format("%s · %dm", member.Name, metres)
					end
				end
			end
		end
	end
	for userId, marker in markers do
		if not wanted[userId] then
			marker:Destroy()
			markers[userId] = nil
		end
	end
	-- Meeting point marker.
	local meet = group and (group :: any).Meet
	if meet then
		for _, point in MapLayout.MeetPoints do
			if point.Id == meet then
				if not meetMarker then
					local anchor = new("Part", {
						Name = "RideoutMeet",
						Anchored = true,
						CanCollide = false,
						CanQuery = false,
						CanTouch = false,
						Transparency = 1,
						Size = Vector3.one,
						Parent = Workspace,
					})
					meetMarker = billboard(anchor, "◎ MEET HERE", C.Accent)
					;(meetMarker :: BillboardGui).StudsOffset = Vector3.new(0, 10, 0)
				end
				local anchor = (meetMarker :: BillboardGui).Parent :: BasePart
				anchor.Position = point.Position + Vector3.new(0, 2, 0)
			end
		end
	elseif meetMarker then
		local anchor = meetMarker.Parent
		if anchor then
			anchor:Destroy()
		end
		meetMarker = nil
	end
end

function RideoutUI.init(screen: ScreenGui)
	modal = Components.modal(screen, "Rideout", 0.42, 0.78)
	content = Components.scroll(modal.Body)
	Components.list(content, Enum.FillDirection.Vertical, 6)
	Components.padding(content, 2, 4)

	-- Invite popup.
	inviteFrame = Components.panel(screen, {
		Name = "RideoutInvite",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 220),
		Size = UDim2.fromOffset(380, 120),
		Visible = false,
		ZIndex = 30,
	})
	Components.padding(inviteFrame, 14, 12)
	local inviteText = Components.text(inviteFrame, "", 17, C.Text, Theme.Fonts.Heading, { Size = UDim2.new(1, 0, 0, 44) })
	Components.button(inviteFrame, "JOIN", "Primary", function()
		if pendingInvite then
			send("Accept")
		end
		inviteFrame.Visible = false
	end, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(0.48, 0, 0, 44) })
	Components.button(inviteFrame, "NO THANKS", "Ghost", function()
		send("Decline")
		inviteFrame.Visible = false
	end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.new(0.48, 0, 0, 44) })

	Remotes.event("Rideout").OnClientEvent:Connect(function(kind: string, payload: any)
		if kind == "State" then
			group = payload
			if modal.isOpen() then
				render()
			end
		elseif kind == "Invite" and type(payload) == "table" then
			pendingInvite = payload.GroupId
			inviteText.Text = string.format("%s invited you to their rideout!", tostring(payload.From))
			inviteFrame.Visible = true
			task.delay(30, function()
				if pendingInvite == payload.GroupId then
					inviteFrame.Visible = false
				end
			end)
		end
	end)
	Players.PlayerAdded:Connect(function()
		if modal.isOpen() then
			render()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if modal.isOpen() then
			task.defer(render)
		end
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed > 0.5 then
			elapsed = 0
			updateMarkers()
		end
	end)
end

function RideoutUI.open()
	modal.open()
	render()
end

function RideoutUI.isLeader(): boolean
	return group ~= nil and (group :: any).Leader == Players.LocalPlayer.UserId
end

function RideoutUI.modal(): Components.Modal
	return modal
end

return RideoutUI
