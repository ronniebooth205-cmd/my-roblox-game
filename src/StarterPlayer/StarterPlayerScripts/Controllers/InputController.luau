--!strict
-- StarterPlayer > StarterPlayerScripts > Controllers > InputController (ModuleScript)
-- One input layer for keyboard, gamepad and touch. Riding code reads `InputController.state`
-- (analogue values) and listens to `InputController.onAction` (button presses) without caring
-- which device the player is using. Key bindings come from GameConfig.DefaultKeybinds and can
-- be overridden per player from Settings.

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local InputController = {}

export type InputState = {
	Throttle: number, -- 0..1
	Brake: number, -- 0..1 (front brake, reverse when stopped)
	Steer: number, -- -1 (left) .. 1 (right)
	Lean: number, -- -1 (forward) .. 1 (back)
	RearBrake: number, -- 0..1
	WheelieMode: boolean, -- toggled with Lean back: the rider sits back so W lifts the front
}

InputController.state = {
	Throttle = 0,
	Brake = 0,
	Steer = 0,
	Lean = 0,
	RearBrake = 0,
	WheelieMode = false,
} :: InputState

local actionListeners: { (action: string) -> () } = {}
local keyboard: { [string]: boolean } = {}
local touch: { [string]: number } = {}
local pad = { RT = 0, LT = 0, StickX = 0, StickY = 0, RearBrake = 0 }
local keybinds: { [string]: string } = table.clone(GameConfig.DefaultKeybinds)
local riding = false
local lastDevice = "Keyboard"
local deviceListeners: { (device: string) -> () } = {}

-- Analogue riding actions (held) and one-shot actions (pressed).
-- Lean back is a toggle (wheelie mode), not held, so it isn't in this list.
-- Tricks are toggles too (press on, press off).
local HELD_ACTIONS = { "Throttle", "Brake", "SteerLeft", "SteerRight", "LeanForward", "RearBrake" }
local PRESS_ACTIONS = { "LeanBack", "Trick1", "Trick2", "Trick3", "Trick4", "Trick5", "Mount", "Recover", "Camera", "Headlight", "Garage", "Map", "Tricks" }
-- Riding-only presses: off the bike these keys keep their normal jobs (1-5 equip tools, Shift).
local RIDING_ONLY = { LeanBack = true, Trick1 = true, Trick2 = true, Trick3 = true, Trick4 = true, Trick5 = true }

local GAMEPAD_PRESS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.ButtonX] = "Mount",
	[Enum.KeyCode.ButtonY] = "Recover",
	[Enum.KeyCode.ButtonL1] = "Camera",
	[Enum.KeyCode.DPadUp] = "Headlight",
	[Enum.KeyCode.ButtonSelect] = "Map",
	[Enum.KeyCode.DPadRight] = "TrickNext",
	[Enum.KeyCode.DPadLeft] = "TrickPrevious",
	[Enum.KeyCode.DPadDown] = "Garage",
	[Enum.KeyCode.ButtonR3] = "LeanBack",
}

local function fire(action: string)
	for _, listener in actionListeners do
		task.spawn(listener, action)
	end
end

local function setDevice(device: string)
	if device ~= lastDevice then
		lastDevice = device
		for _, listener in deviceListeners do
			task.spawn(listener, device)
		end
	end
end

-- Enum lookups throw on unknown names, so saved/rebound key names go through here.
local function toKeyCode(name: string?): Enum.KeyCode?
	if not name then
		return nil
	end
	local ok, key = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	return if ok then key else nil
end

local function keyFor(action: string): Enum.KeyCode?
	return toKeyCode(keybinds[action])
end

local function recompute()
	local s = InputController.state
	local kbThrottle = if keyboard.Throttle then 1 else 0
	local kbBrake = if keyboard.Brake then 1 else 0
	local kbSteer = (if keyboard.SteerRight then 1 else 0) - (if keyboard.SteerLeft then 1 else 0)
	local kbLean = (if s.WheelieMode then 1 else 0) - (if keyboard.LeanForward then 1 else 0)
	local kbRear = if keyboard.RearBrake then 1 else 0

	s.Throttle = math.clamp(math.max(kbThrottle, pad.RT, touch.Throttle or 0), 0, 1)
	s.Brake = math.clamp(math.max(kbBrake, pad.LT, touch.Brake or 0), 0, 1)
	local touchSteer = (touch.SteerRight or 0) - (touch.SteerLeft or 0)
	s.Steer = math.clamp(kbSteer + pad.StickX + touchSteer, -1, 1)
	local touchLean = -(touch.LeanForward or 0)
	s.Lean = math.clamp(kbLean + pad.StickY + touchLean, -1, 1)
	s.RearBrake = math.clamp(math.max(kbRear, pad.RearBrake, touch.RearBrake or 0), 0, 1)
end

local function deadzone(x: number): number
	if math.abs(x) < 0.15 then
		return 0
	end
	return math.sign(x) * (math.abs(x) - 0.15) / 0.85
end

local function onHeld(actionName: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	local action = actionName:gsub("^Ride_", "")
	keyboard[action] = inputState == Enum.UserInputState.Begin or inputState == Enum.UserInputState.Change
	setDevice("Keyboard")
	recompute()
	return if riding then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
end

local wheelieListeners: { (on: boolean) -> () } = {}

function InputController.setWheelieMode(on: boolean)
	if InputController.state.WheelieMode == on then
		return
	end
	InputController.state.WheelieMode = on
	recompute()
	for _, listener in wheelieListeners do
		task.spawn(listener, on)
	end
end

function InputController.onWheelieModeChanged(listener: (on: boolean) -> ())
	table.insert(wheelieListeners, listener)
end

local function onPress(actionName: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		local action = actionName:gsub("^Press_", "")
		if RIDING_ONLY[action] and not riding then
			return Enum.ContextActionResult.Pass
		end
		if action == "LeanBack" then
			InputController.setWheelieMode(not InputController.state.WheelieMode)
		end
		fire(action)
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function onGamepad(_actionName: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	setDevice("Gamepad")
	local active = inputState ~= Enum.UserInputState.End and inputState ~= Enum.UserInputState.Cancel
	local key = input.KeyCode
	if key == Enum.KeyCode.ButtonR2 then
		pad.RT = if active then math.clamp(input.Position.Z, 0, 1) else 0
	elseif key == Enum.KeyCode.ButtonL2 then
		pad.LT = if active then math.clamp(input.Position.Z, 0, 1) else 0
	elseif key == Enum.KeyCode.Thumbstick1 then
		pad.StickX = if active then deadzone(input.Position.X) else 0
	elseif key == Enum.KeyCode.Thumbstick2 then
		-- Pulling the right stick back (down) leans back.
		pad.StickY = if active then -deadzone(input.Position.Y) else 0
	elseif key == Enum.KeyCode.ButtonA then
		pad.RearBrake = if active then 1 else 0
	elseif key == Enum.KeyCode.ButtonR1 then
		if inputState == Enum.UserInputState.Begin then
			fire("TrickToggle")
		end
	elseif inputState == Enum.UserInputState.Begin and GAMEPAD_PRESS[key] then
		if GAMEPAD_PRESS[key] == "LeanBack" and riding then
			InputController.setWheelieMode(not InputController.state.WheelieMode)
		end
		fire(GAMEPAD_PRESS[key])
	end
	recompute()
	return if riding then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
end

local function bindKeyboard()
	for _, action in HELD_ACTIONS do
		ContextActionService:UnbindAction("Ride_" .. action)
		local key = keyFor(action)
		if key then
			ContextActionService:BindActionAtPriority("Ride_" .. action, onHeld, false, Enum.ContextActionPriority.High.Value, key)
		end
	end
	for _, action in PRESS_ACTIONS do
		ContextActionService:UnbindAction("Press_" .. action)
		local key = keyFor(action)
		if key then
			ContextActionService:BindActionAtPriority("Press_" .. action, onPress, false, Enum.ContextActionPriority.High.Value, key)
		end
	end
end

local function bindGamepad()
	ContextActionService:UnbindAction("Ride_Gamepad")
	local keys: { Enum.KeyCode } = {
		Enum.KeyCode.ButtonR2,
		Enum.KeyCode.ButtonL2,
		Enum.KeyCode.Thumbstick1,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonR1,
	}
	if riding then
		-- Only take the right stick while riding; on foot it still moves the camera.
		table.insert(keys, Enum.KeyCode.Thumbstick2)
	end
	for key in GAMEPAD_PRESS do
		table.insert(keys, key)
	end
	ContextActionService:BindActionAtPriority("Ride_Gamepad", onGamepad, false, Enum.ContextActionPriority.High.Value, table.unpack(keys))
end

function InputController.init()
	bindKeyboard()
	bindGamepad()
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		if inputType == Enum.UserInputType.Touch then
			setDevice("Touch")
		elseif inputType.Name:find("Gamepad") then
			setDevice("Gamepad")
		elseif inputType == Enum.UserInputType.Keyboard or inputType.Name:find("Mouse") then
			setDevice("Keyboard")
		end
	end)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		lastDevice = "Touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		lastDevice = "Gamepad"
	end
end

-- Riding mode sinks the riding keys so the character/camera don't also react to them.
function InputController.setRiding(isRiding: boolean)
	riding = isRiding
	if not isRiding then
		InputController.setWheelieMode(false)
		table.clear(keyboard)
		table.clear(touch)
		pad.RT, pad.LT, pad.StickX, pad.StickY, pad.RearBrake = 0, 0, 0, 0, 0
	end
	bindGamepad()
	recompute()
end

-- Touch buttons (MobileControls) write here: action is one of Throttle, Brake, SteerLeft,
-- SteerRight, LeanForward, RearBrake. (Wheelie mode and tricks are toggles.)
function InputController.setTouch(action: string, value: number)
	touch[action] = value
	setDevice("Touch")
	recompute()
end

function InputController.firePress(action: string)
	fire(action)
end

function InputController.onAction(listener: (action: string) -> ())
	table.insert(actionListeners, listener)
end

function InputController.onDeviceChanged(listener: (device: string) -> ())
	table.insert(deviceListeners, listener)
end

function InputController.device(): string
	return lastDevice
end

function InputController.keyName(action: string): string
	return keybinds[action] or "?"
end

function InputController.setKeybinds(overrides: { [string]: string }?)
	keybinds = table.clone(GameConfig.DefaultKeybinds)
	if overrides then
		for action, keyName in overrides do
			if keybinds[action] and toKeyCode(keyName) then
				keybinds[action] = keyName
			end
		end
	end
	bindKeyboard()
end

return InputController
