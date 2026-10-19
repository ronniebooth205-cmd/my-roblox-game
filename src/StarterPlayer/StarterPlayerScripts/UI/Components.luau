--!strict
-- StarterPlayer > StarterPlayerScripts > UI > Components (ModuleScript)
-- Reusable UI pieces built on Theme: panels, buttons, tabs, bars, sliders, toggles, choice
-- cyclers, colour swatches and modals. Every interactive piece is gamepad-selectable and
-- touch-friendly (44px+ hit areas), and plays the UI click sound.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)

local Components = {}

local C = Theme.Colors
local clickSound: (() -> ())? = nil

function Components.setClickSound(fn: () -> ())
	clickSound = fn
end

function Components.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end
local new = Components.new

function Components.corner(parent: Instance, radius: UDim?): UICorner
	return new("UICorner", { CornerRadius = radius or Theme.Radius.Medium, Parent = parent })
end

function Components.stroke(parent: Instance, colour: Color3?, thickness: number?, transparency: number?): UIStroke
	return new("UIStroke", {
		Color = colour or C.Stroke,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Components.padding(parent: Instance, px: number, py: number?): UIPadding
	local y = py or px
	return new("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, y),
		PaddingBottom = UDim.new(0, y),
		Parent = parent,
	})
end

function Components.list(parent: Instance, direction: Enum.FillDirection?, gap: number?, align: Enum.HorizontalAlignment?): UIListLayout
	return new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or Theme.Spacing.S),
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function Components.text(parent: Instance?, text: string, size: number?, colour: Color3?, font: Enum.Font?, props: { [string]: any }?): TextLabel
	local label = new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size or Theme.TextSize.Body,
		TextColor3 = colour or C.Text,
		Font = font or Theme.Fonts.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, (size or Theme.TextSize.Body) + 6),
		TextWrapped = true,
		Parent = parent,
	})
	if props then
		for k, v in props do
			(label :: any)[k] = v
		end
	end
	return label
end

function Components.panel(parent: Instance?, props: { [string]: any }?): Frame
	local frame = new("Frame", {
		BackgroundColor3 = C.Surface,
		BorderSizePixel = 0,
		Parent = parent,
	})
	if props then
		for k, v in props do
			(frame :: any)[k] = v
		end
	end
	Components.corner(frame, Theme.Radius.Large)
	Components.stroke(frame, C.Stroke, 1, 0.3)
	return frame
end

local BUTTON_STYLES = {
	Primary = { Bg = C.Accent, Hover = Color3.fromRGB(120, 255, 175), Text = C.AccentText },
	Secondary = { Bg = C.SurfaceRaised, Hover = C.SurfaceHover, Text = C.Text },
	Ghost = { Bg = C.Surface, Hover = C.SurfaceRaised, Text = C.TextMuted },
	Danger = { Bg = C.Danger, Hover = Color3.fromRGB(255, 120, 130), Text = C.Text },
	Gold = { Bg = C.Gold, Hover = Color3.fromRGB(255, 226, 150), Text = C.AccentText },
}

function Components.button(parent: Instance?, text: string, style: string?, onClick: (() -> ())?, props: { [string]: any }?): TextButton
	local s = BUTTON_STYLES[style or "Secondary"] or BUTTON_STYLES.Secondary
	local button = new("TextButton", {
		Text = text,
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Label,
		TextColor3 = s.Text,
		BackgroundColor3 = s.Bg,
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, 48),
		Selectable = true,
		Parent = parent,
	})
	if props then
		for k, v in props do
			(button :: any)[k] = v
		end
	end
	Components.corner(button, Theme.Radius.Medium)
	local scale = new("UIScale", { Parent = button })
	button.MouseEnter:Connect(function()
		TweenService:Create(button, Theme.Tween.Fast, { BackgroundColor3 = s.Hover }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, Theme.Tween.Fast, { BackgroundColor3 = s.Bg }):Play()
		TweenService:Create(scale, Theme.Tween.Fast, { Scale = 1 }):Play()
	end)
	button.SelectionGained:Connect(function()
		TweenService:Create(button, Theme.Tween.Fast, { BackgroundColor3 = s.Hover }):Play()
	end)
	button.SelectionLost:Connect(function()
		TweenService:Create(button, Theme.Tween.Fast, { BackgroundColor3 = s.Bg }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, Theme.Tween.Fast, { Scale = 0.96 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, Theme.Tween.Fast, { Scale = 1 }):Play()
	end)
	if onClick then
		button.Activated:Connect(function()
			if clickSound then
				clickSound()
			end
			onClick()
		end)
	end
	return button
end

-- Restyles a button (e.g. to show it's selected).
function Components.setButtonStyle(button: TextButton, style: string)
	local s = BUTTON_STYLES[style] or BUTTON_STYLES.Secondary
	button.BackgroundColor3 = s.Bg
	button.TextColor3 = s.Text
end

export type Bar = { Frame: Frame, set: (fraction: number, colour: Color3?) -> () }

function Components.bar(parent: Instance?, colour: Color3?, height: number?): Bar
	local track = new("Frame", {
		BackgroundColor3 = C.SurfaceRaised,
		Size = UDim2.new(1, 0, 0, height or 8),
		BorderSizePixel = 0,
		Parent = parent,
	})
	Components.corner(track, Theme.Radius.Pill)
	local fill = new("Frame", {
		BackgroundColor3 = colour or C.Accent,
		Size = UDim2.fromScale(0, 1),
		BorderSizePixel = 0,
		Parent = track,
	})
	Components.corner(fill, Theme.Radius.Pill)
	return {
		Frame = track,
		set = function(fraction: number, newColour: Color3?)
			fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			if newColour then
				fill.BackgroundColor3 = newColour
			end
		end,
	}
end

-- A labelled stat bar row ("Speed ▮▮▮▮▯").
function Components.statRow(parent: Instance?, label: string, fraction: number, compare: number?): Frame
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), Parent = parent })
	Components.text(row, label, Theme.TextSize.Caption, C.TextMuted, Theme.Fonts.Heading, { Size = UDim2.new(0.35, 0, 1, 0) })
	local holder = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(0.38, 0.35), Size = UDim2.new(0.62, 0, 0.3, 0), Parent = row })
	local bar = Components.bar(holder, C.Accent, 8)
	bar.Frame.Size = UDim2.fromScale(1, 1)
	bar.set(fraction)
	if compare and math.abs(compare - fraction) > 0.005 then
		local ghost = new("Frame", {
			BackgroundColor3 = if compare > fraction then C.Info else C.Danger,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(math.min(fraction, compare), 0),
			Size = UDim2.fromScale(math.abs(compare - fraction), 1),
			Parent = bar.Frame,
		})
		Components.corner(ghost, Theme.Radius.Pill)
	end
	return row
end

function Components.tabs(parent: Instance?, names: { string }, onSelect: (name: string) -> ()): { select: (name: string) -> () }
	local bar = new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		Parent = parent,
	})
	Components.list(bar, Enum.FillDirection.Horizontal, 6)
	local buttons: { [string]: TextButton } = {}
	local function selectTab(name: string)
		for n, b in buttons do
			Components.setButtonStyle(b, if n == name then "Primary" else "Ghost")
		end
		onSelect(name)
	end
	for i, name in names do
		local b = Components.button(bar, name, "Ghost", function()
			selectTab(name)
		end, { Size = UDim2.new(0, math.max(90, #name * 10 + 30), 0, 40), LayoutOrder = i, TextSize = 15 })
		buttons[name] = b
	end
	return { select = selectTab }
end

function Components.slider(parent: Instance?, label: string, min: number, max: number, value: number, step: number, onChange: (value: number) -> (), format: ((number) -> string)?): Frame
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56), Parent = parent })
	local title = Components.text(row, label, Theme.TextSize.Body, C.Text, Theme.Fonts.Heading, { Size = UDim2.new(0.7, 0, 0, 22) })
	local valueLabel = Components.text(row, "", Theme.TextSize.Body, C.Accent, Theme.Fonts.Heading, {
		Size = UDim2.new(0.3, 0, 0, 22),
		Position = UDim2.fromScale(0.7, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local track = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.SurfaceRaised,
		Position = UDim2.new(0, 0, 0, 32),
		Size = UDim2.new(1, 0, 0, 14),
		Selectable = true,
		Parent = row,
	})
	Components.corner(track, Theme.Radius.Pill)
	local fill = new("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = track })
	Components.corner(fill, Theme.Radius.Pill)
	local knob = new("Frame", {
		BackgroundColor3 = C.Text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.fromScale(0, 0.5),
		Parent = track,
	})
	Components.corner(knob, Theme.Radius.Pill)
	local current = value
	local function render()
		local f = if max > min then (current - min) / (max - min) else 0
		fill.Size = UDim2.fromScale(f, 1)
		knob.Position = UDim2.fromScale(f, 0.5)
		valueLabel.Text = if format then format(current) else string.format(if step >= 1 then "%d" else "%.2f", current)
	end
	local function set(v: number, notify: boolean)
		v = math.clamp(math.floor((v - min) / step + 0.5) * step + min, min, max)
		if v ~= current then
			current = v
			render()
			if notify then
				onChange(v)
			end
		end
	end
	local dragging = false
	local function fromX(x: number)
		local f = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		set(min + f * (max - min), true)
	end
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromX(input.Position.X)
		elseif input.KeyCode == Enum.KeyCode.DPadRight or input.KeyCode == Enum.KeyCode.Right then
			set(current + step, true)
		elseif input.KeyCode == Enum.KeyCode.DPadLeft or input.KeyCode == Enum.KeyCode.Left then
			set(current - step, true)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			fromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	title.Text = label
	render()
	return row
end

function Components.toggle(parent: Instance?, label: string, value: boolean, onChange: (value: boolean) -> ()): Frame
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = parent })
	Components.text(row, label, Theme.TextSize.Body, C.Text, Theme.Fonts.Heading, { Size = UDim2.new(0.75, 0, 1, 0) })
	local switch = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(58, 32),
		BackgroundColor3 = C.SurfaceRaised,
		Selectable = true,
		Parent = row,
	})
	Components.corner(switch, Theme.Radius.Pill)
	local dot = new("Frame", { Size = UDim2.fromOffset(24, 24), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = C.Text, Parent = switch })
	Components.corner(dot, Theme.Radius.Pill)
	local state = value
	local function render()
		TweenService:Create(switch, Theme.Tween.Fast, { BackgroundColor3 = if state then C.Accent else C.SurfaceRaised }):Play()
		TweenService:Create(dot, Theme.Tween.Fast, { Position = if state then UDim2.new(1, -28, 0.5, 0) else UDim2.new(0, 4, 0.5, 0) }):Play()
	end
	switch.Activated:Connect(function()
		state = not state
		render()
		if clickSound then
			clickSound()
		end
		onChange(state)
	end)
	render()
	return row
end

-- "< Option >" cycler, good on every input device.
function Components.choice(parent: Instance?, label: string, options: { string }, value: string, onChange: (value: string) -> (), display: ((string) -> string)?): Frame
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = parent })
	Components.text(row, label, Theme.TextSize.Body, C.Text, Theme.Fonts.Heading, { Size = UDim2.new(0.45, 0, 1, 0) })
	local index = table.find(options, value) or 1
	local holder = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(0.45, 0), Size = UDim2.fromScale(0.55, 1), Parent = row })
	local valueLabel = Components.text(holder, "", Theme.TextSize.Body, C.Accent, Theme.Fonts.Heading, {
		Size = UDim2.new(1, -96, 1, 0),
		Position = UDim2.fromOffset(48, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local function render()
		valueLabel.Text = if display then display(options[index]) else options[index]
	end
	local function shift(delta: number)
		index = (index - 1 + delta) % #options + 1
		render()
		onChange(options[index])
	end
	Components.button(holder, "<", "Secondary", function()
		shift(-1)
	end, { Size = UDim2.fromOffset(44, 40), Position = UDim2.new(0, 0, 0.5, -20) })
	Components.button(holder, ">", "Secondary", function()
		shift(1)
	end, { Size = UDim2.fromOffset(44, 40), Position = UDim2.new(1, -44, 0.5, -20) })
	render()
	return row
end

function Components.swatch(parent: Instance?, colour: Color3, locked: boolean, selected: boolean, onClick: () -> ()): TextButton
	local button = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = colour,
		Size = UDim2.fromOffset(52, 52),
		Selectable = true,
		Parent = parent,
	})
	Components.corner(button, Theme.Radius.Medium)
	Components.stroke(button, if selected then C.Accent else C.Stroke, if selected then 3 else 1, 0)
	if locked then
		local lock = Components.text(button, "🔒", 18, C.Text, Theme.Fonts.Heading, {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.4,
		})
		lock.ZIndex = 2
	end
	button.Activated:Connect(function()
		if clickSound then
			clickSound()
		end
		onClick()
	end)
	return button
end

export type Modal = {
	Frame: Frame,
	Body: Frame,
	Title: TextLabel,
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	onClose: (fn: () -> ()) -> (),
}

-- A centred window with a title bar and close button. Size is a scale of the screen, capped
-- for big monitors and full-width on phones.
function Components.modal(screen: Instance, title: string, widthScale: number?, heightScale: number?): Modal
	local frame = Components.panel(screen, {
		Name = "Modal_" .. title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(widthScale or 0.6, heightScale or 0.75),
		Visible = false,
		ZIndex = 20,
	})
	frame.BackgroundTransparency = 0.04
	new("UISizeConstraint", { MaxSize = Vector2.new(980, 720), MinSize = Vector2.new(300, 260), Parent = frame })
	local scale = new("UIScale", { Parent = frame })
	Components.padding(frame, Theme.Spacing.L)
	local titleLabel = Components.text(frame, title:upper(), Theme.TextSize.Title, C.Text, Theme.Fonts.Display, { Size = UDim2.new(1, -60, 0, 32) })
	local closeListeners: { () -> () } = {}
	local modal: Modal
	local closeButton = Components.button(frame, "✕", "Ghost", function()
		modal.close()
	end, { Size = UDim2.fromOffset(44, 44), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, -6) })
	closeButton.Name = "Close"
	local accent = new("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 38), Size = UDim2.fromOffset(48, 4), Parent = frame })
	Components.corner(accent, Theme.Radius.Pill)
	local body = new("Frame", { Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 1, -54), Parent = frame })
	local openState = false
	modal = {
		Frame = frame,
		Body = body,
		Title = titleLabel,
		open = function()
			openState = true
			frame.Visible = true
			scale.Scale = 0.92
			TweenService:Create(scale, Theme.Tween.Pop, { Scale = 1 }):Play()
		end,
		close = function()
			if not openState then
				return
			end
			openState = false
			frame.Visible = false
			for _, fn in closeListeners do
				task.spawn(fn)
			end
		end,
		isOpen = function()
			return openState
		end,
		onClose = function(fn: () -> ())
			table.insert(closeListeners, fn)
		end,
	}
	return modal
end

function Components.scroll(parent: Instance?, props: { [string]: any }?): ScrollingFrame
	local scroller = new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Stroke,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	})
	if props then
		for k, v in props do
			(scroller :: any)[k] = v
		end
	end
	return scroller
end

function Components.clear(container: Instance)
	for _, child in container:GetChildren() do
		-- Keep layouts, padding, corners and constraints; remove content only.
		if not child:IsA("UIComponent") then
			child:Destroy()
		end
	end
end

return Components
