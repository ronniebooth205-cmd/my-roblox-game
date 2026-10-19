--!strict
-- StarterPlayer > StarterPlayerScripts > UI > MobileControls (ModuleScript)
-- Touch riding controls: big steering pads on one side; throttle, brake, the wheelie-mode
-- toggle, lean forward and rear brake on the other; small camera/trick/mount/recover buttons along the
-- top edge. Buttons are sized from the shorter screen side, so they stay thumb-sized on phones
-- and tablets in portrait or landscape, and sit inside the device safe area. Multi-touch:
-- every button tracks its own touch, so you can steer, throttle and lean at once.
-- "Left" layout mirrors everything for left-handed players.

local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Controllers = script.Parent.Parent.Controllers
local InputController = require(Controllers.InputController)
local TrickController = require(Controllers.TrickController)

local MobileControls = {}

local C = Theme.Colors
local new = Components.new

local root: Frame
local ridingGroup: Frame
local trickLabel: TextButton? = nil
local leftHanded = false
local utilityGrid: Frame? = nil
local buttons: { { Button: TextButton, Spec: { [string]: any } } } = {}

-- Positions are in "units" of the base size from the chosen corner (x from the side edge,
-- y from the bottom). `Action` buttons are held; `Press` buttons fire once.
local RIDE_BUTTONS = {
	{ Name = "Throttle", Label = "GO", Side = "Right", X = 0.15, Y = 0.15, Size = 1.25, Action = "Throttle", Colour = C.Accent, TextColour = C.AccentText },
	{ Name = "Brake", Label = "BRAKE", Side = "Right", X = 1.55, Y = 0.1, Size = 0.85, Action = "Brake", Colour = C.Danger },
	{ Name = "RearBrake", Label = "REAR", Side = "Right", X = 1.4, Y = 1.15, Size = 0.75, Action = "RearBrake", Colour = C.SurfaceRaised },
	{ Name = "LeanForward", Label = "LEAN ▲", Side = "Right", X = 1.3, Y = 2.05, Size = 0.7, Action = "LeanForward", Colour = C.SurfaceRaised },
	{ Name = "SteerLeft", Label = "◀", Side = "Left", X = 0.15, Y = 0.3, Size = 1.15, Action = "SteerLeft", Colour = C.SurfaceRaised },
	{ Name = "SteerRight", Label = "▶", Side = "Left", X = 1.45, Y = 0.3, Size = 1.15, Action = "SteerRight", Colour = C.SurfaceRaised },
}

local TOP_BUTTONS = {
	{ Name = "Camera", Label = "CAM", Press = "Camera" },
	{ Name = "Mount", Label = "OFF", Press = "Mount" },
	{ Name = "Recover", Label = "RESET", Press = "Recover" },
	{ Name = "Headlight", Label = "LIGHT", Press = "Headlight" },
}

local function baseSize(): number
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return math.clamp(math.min(viewport.X, viewport.Y) * 0.17, 64, 128)
end

local function layout()
	local unit = baseSize()
	for _, entry in buttons do
		local spec = entry.Spec
		local size = unit * spec.Size
		local side = spec.Side
		if leftHanded then
			side = if side == "Right" then "Left" else "Right"
		end
		local x = spec.X * unit
		local y = spec.Y * unit
		entry.Button.Size = UDim2.fromOffset(size, size)
		if side == "Right" then
			entry.Button.AnchorPoint = Vector2.new(1, 1)
			entry.Button.Position = UDim2.new(1, -x, 1, -y)
		else
			entry.Button.AnchorPoint = Vector2.new(0, 1)
			entry.Button.Position = UDim2.new(0, x, 1, -y)
		end
		entry.Button.TextSize = math.floor(size * 0.2)
	end
end

local function holdButton(parent: Instance, spec: { [string]: any }): TextButton
	local button = new("TextButton", {
		Name = spec.Name,
		Text = spec.Label,
		Font = Theme.Fonts.Display,
		TextColor3 = spec.TextColour or C.Text,
		BackgroundColor3 = spec.Colour,
		BackgroundTransparency = 0.15,
		AutoButtonColor = false,
		Selectable = false,
		Parent = parent,
	})
	Components.corner(button, Theme.Radius.Pill)
	Components.stroke(button, C.Text, 2, 0.75)
	local active = 0
	local function set(on: boolean)
		active = math.max(0, active + (if on then 1 else -1))
		InputController.setTouch(spec.Action, if active > 0 then 1 else 0)
		button.BackgroundTransparency = if active > 0 then 0 else 0.15
	end
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			set(true)
			local connection: RBXScriptConnection
			connection = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
				if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
					connection:Disconnect()
					set(false)
				end
			end)
		end
	end)
	return button
end

function MobileControls.init(screen: ScreenGui)
	root = new("Frame", { Name = "MobileControls", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = screen })
	ridingGroup = new("Frame", { Name = "Riding", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })
	for _, spec in RIDE_BUTTONS do
		table.insert(buttons, { Button = holdButton(ridingGroup, spec), Spec = spec })
	end
	-- Small utility buttons in a 2x2 grid on the left, below the HUD's bike panel and above
	-- the steering pads (HUD.setTouchLayout keeps that space clear).
	local grid = new("Frame", { Name = "Utility", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 176), Size = UDim2.fromOffset(152, 100), Parent = ridingGroup })
	new("UIGridLayout", { CellSize = UDim2.fromOffset(72, 44), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	utilityGrid = grid
	for i, spec in TOP_BUTTONS do
		Components.button(grid, spec.Label, "Secondary", function()
			InputController.firePress(spec.Press)
		end, { LayoutOrder = i, TextSize = 14 })
	end
	-- Trick button (hold) with a small selector to choose which trick it performs.
	local trickSpec = { Name = "Trick", Label = "TRICK", Side = "Right", X = 2.45, Y = 1.75, Size = 0.75, Colour = Color3.fromRGB(140, 70, 220) }
	local trickButton = new("TextButton", {
		Name = "Trick",
		Text = "TRICK",
		Font = Theme.Fonts.Display,
		TextColor3 = C.Text,
		BackgroundColor3 = trickSpec.Colour,
		BackgroundTransparency = 0.15,
		AutoButtonColor = false,
		Selectable = false,
		Parent = ridingGroup,
	})
	Components.corner(trickButton, Theme.Radius.Pill)
	trickButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			InputController.firePress("TrickHeld")
			local connection: RBXScriptConnection
			connection = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
				if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
					connection:Disconnect()
					InputController.firePress("TrickReleased")
				end
			end)
		end
	end)
	table.insert(buttons, { Button = trickButton, Spec = trickSpec })
	-- Wheelie mode is a tap-to-toggle switch, lit while on.
	local wheelieSpec = { Name = "Wheelie", Side = "Right", X = 0.25, Y = 1.55, Size = 0.95 }
	local wheelie = new("TextButton", {
		Name = "Wheelie",
		Text = "WHEELIE\nOFF",
		Font = Theme.Fonts.Display,
		TextColor3 = C.Text,
		BackgroundColor3 = C.SurfaceRaised,
		BackgroundTransparency = 0.15,
		AutoButtonColor = false,
		Selectable = false,
		Parent = ridingGroup,
	})
	Components.corner(wheelie, Theme.Radius.Pill)
	Components.stroke(wheelie, C.Gold, 2, 0.2)
	wheelie.Activated:Connect(function()
		InputController.setWheelieMode(not InputController.state.WheelieMode)
	end)
	InputController.onWheelieModeChanged(function(on)
		wheelie.Text = if on then "WHEELIE\nON" else "WHEELIE\nOFF"
		wheelie.BackgroundColor3 = if on then C.Gold else C.SurfaceRaised
		wheelie.TextColor3 = if on then C.AccentText else C.Text
	end)
	table.insert(buttons, { Button = wheelie, Spec = wheelieSpec })
	local selector = Components.button(ridingGroup, "", "Secondary", function()
		InputController.firePress("TrickNext")
		task.defer(MobileControls.refreshTrick)
	end, { Size = UDim2.fromOffset(150, 36), TextSize = 13 })
	trickLabel = selector
	table.insert(buttons, { Button = selector, Spec = { Side = "Right", X = 2.3, Y = 2.55, Size = 0.01 } })
	layout()
	-- The selector is a pill, not a circle: restore its size after the generic layout.
	selector.Size = UDim2.fromOffset(150, 36)
	MobileControls.refreshTrick()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			layout()
			selector.Size = UDim2.fromOffset(150, 36)
		end)
	end
end

function MobileControls.refreshTrick()
	if trickLabel then
		trickLabel.Text = "◆ " .. TrickController.selectedTrick().Name:upper()
	end
end

function MobileControls.setVisible(visible: boolean)
	root.Visible = visible
	if not visible then
		for _, action in { "Throttle", "Brake", "LeanForward", "RearBrake", "SteerLeft", "SteerRight" } do
			InputController.setTouch(action, 0)
		end
	end
end

function MobileControls.setLeftHanded(left: boolean)
	leftHanded = left
	layout()
	if utilityGrid then
		utilityGrid.AnchorPoint = Vector2.new(if left then 1 else 0, 0)
		utilityGrid.Position = if left then UDim2.new(1, -16, 0, 176) else UDim2.fromOffset(16, 176)
	end
	if trickLabel then
		trickLabel.Size = UDim2.fromOffset(150, 36)
	end
end

return MobileControls
