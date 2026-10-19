--!strict
-- StarterPlayer > StarterPlayerScripts > UI > MainMenu (ModuleScript)
-- The title screen shown on join (and from the ☰ button): PLAY, GARAGE, BIKES, SHOP, SETTINGS,
-- CODES, over a slow camera orbit of your bike on the showroom plinth at the meet. Also holds
-- the small Codes window.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local BikeBuilder = require(ReplicatedStorage.Shared.BikeBuilder)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Controllers = script.Parent.Parent.Controllers
local ClientState = require(Controllers.ClientState)
local CameraController = require(Controllers.CameraController)

local MainMenu = {}

local C = Theme.Colors
local new = Components.new

local root: CanvasGroup
local showcase: Model? = nil
local orbitConnection: RBXScriptConnection? = nil
local orbitAngle = 0
local isOpen = false
local handlers: { [string]: () -> () } = {}
local codes: Components.Modal

local function buildShowcase()
	if showcase then
		showcase:Destroy()
		showcase = nil
	end
	local profile = ClientState.profile
	if not profile then
		return
	end
	local bikeId = profile.EquippedBike
	local model = BikeBuilder.build(bikeId, profile.BikeSetups[bikeId], { Anchored = true, Name = "MenuShowcase" })
	local r = model:GetAttribute("WheelRadius") :: number
	local height = r + (model:GetAttribute("SuspensionRest") :: number) - (model:GetAttribute("StaticSag") :: number) + (model:GetAttribute("MountDrop") :: number)
	local base = MapLayout.Places.MenuBike + Vector3.new(0, MapLayout.RoadTop + 1.2 + height, 0)
	model:PivotTo(CFrame.new(base) * CFrame.Angles(0, math.rad(35), 0))
	BikeBuilder.setPlateText(model, "")
	model.Parent = Workspace
	showcase = model
end

local function sceneCFrame(): CFrame
	local focus = MapLayout.Places.MenuBike + Vector3.new(0, 3.2, 0)
	local offset = CFrame.Angles(0, orbitAngle, 0):VectorToWorldSpace(Vector3.new(0, 2.5, 13))
	-- Shift the bike right of centre so the menu buttons don't cover it.
	local look = CFrame.lookAt(focus + offset, focus)
	return look * CFrame.new(-3.5, 0, 0)
end

local function buildCodes(screen: ScreenGui)
	codes = Components.modal(screen, "Codes", 0.4, 0.4)
	local body = codes.Body
	Components.list(body, Enum.FillDirection.Vertical, 12)
	Components.text(body, "Enter a code from our socials for free cash.", Theme.TextSize.Body, C.TextMuted)
	local box = new("TextBox", {
		PlaceholderText = "ENTER CODE",
		Text = "",
		Font = Theme.Fonts.Heading,
		TextSize = 20,
		TextColor3 = C.Text,
		PlaceholderColor3 = C.TextDim,
		BackgroundColor3 = C.SurfaceRaised,
		ClearTextOnFocus = false,
		Size = UDim2.new(1, 0, 0, 52),
		Parent = body,
	})
	Components.corner(box)
	local status = Components.text(body, "", Theme.TextSize.Body, C.Accent, Theme.Fonts.Heading)
	Components.button(body, "REDEEM", "Primary", function()
		local ok, result = pcall(function()
			return Remotes.func("RedeemCode"):InvokeServer(box.Text)
		end)
		if ok and type(result) == "table" then
			status.Text = result.Message
			status.TextColor3 = if result.Ok then C.Accent else C.Danger
		end
	end)
end

function MainMenu.init(screen: ScreenGui, actions: { [string]: () -> () })
	handlers = actions
	root = new("CanvasGroup", { Name = "MainMenu", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 10, Parent = screen })
	-- Dark gradient on the left for legibility, fading to clear over the bike.
	local shade = new("Frame", { BackgroundColor3 = C.Background, BorderSizePixel = 0, Size = UDim2.fromScale(0.62, 1), Parent = root })
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.6, 0.35), NumberSequenceKeypoint.new(1, 1) }), Parent = shade })

	local column = new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 48, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.new(0.34, 0, 0.86, 0), Parent = root })
	new("UISizeConstraint", { MinSize = Vector2.new(260, 300), MaxSize = Vector2.new(420, 760), Parent = column })
	Components.list(column, Enum.FillDirection.Vertical, 10)
	local title = Components.text(column, "SURRON LIFE", 52, C.Text, Theme.Fonts.Display, { Size = UDim2.new(1, 0, 0, 56), LayoutOrder = 1, TextScaled = true })
	new("UITextSizeConstraint", { MaxTextSize = 56, Parent = title })
	local sub = Components.text(column, "WHEELIE CITY", 24, C.Accent, Theme.Fonts.Display, { Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 2 })
	sub.TextScaled = true
	new("UITextSizeConstraint", { MaxTextSize = 28, Parent = sub })
	new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 3, Parent = column })
	for i, entry in { { "PLAY", "Primary" }, { "GARAGE", "Secondary" }, { "BIKES", "Secondary" }, { "SHOP", "Secondary" }, { "SETTINGS", "Secondary" }, { "CODES", "Ghost" } } do
		local name = entry[1]
		local button = Components.button(column, name, entry[2], function()
			if name == "CODES" then
				codes.open()
				return
			end
			local fn = handlers[name]
			if fn then
				fn()
			end
		end, { Size = UDim2.new(1, 0, 0, if name == "PLAY" then 64 else 52), LayoutOrder = 10 + i, TextSize = if name == "PLAY" then 26 else 20 })
		button.Name = name
	end
	Components.text(root, "Original game. All names and brands are fictional.", 12, C.TextDim, Theme.Fonts.Body, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 48, 1, -16),
		Size = UDim2.fromOffset(420, 16),
	})
	buildCodes(screen)
	ClientState.onProfile(function()
		if isOpen then
			buildShowcase()
		end
	end)
end

function MainMenu.open()
	if isOpen then
		return
	end
	isOpen = true
	root.Visible = true
	root.GroupTransparency = 1
	TweenService:Create(root, Theme.Tween.Normal, { GroupTransparency = 0 }):Play()
	buildShowcase()
	CameraController.setScene(sceneCFrame)
	orbitConnection = RunService.RenderStepped:Connect(function(dt)
		orbitAngle += dt * 0.12
	end)
	local play = root:FindFirstChild("PLAY", true)
	local GuiService = game:GetService("GuiService")
	if play and play:IsA("GuiObject") then
		GuiService.SelectedObject = play
	end
end

function MainMenu.close()
	if not isOpen then
		return
	end
	isOpen = false
	root.Visible = false
	if orbitConnection then
		orbitConnection:Disconnect()
		orbitConnection = nil
	end
	if showcase then
		showcase:Destroy()
		showcase = nil
	end
	codes.close()
	CameraController.setScene(nil)
	game:GetService("GuiService").SelectedObject = nil
end

function MainMenu.isOpen(): boolean
	return isOpen
end

return MainMenu
