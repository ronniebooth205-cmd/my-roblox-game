--!strict
-- StarterPlayer > StarterPlayerScripts > UI > SettingsUI (ModuleScript)
-- Settings: audio, camera, graphics, wheelie assist, HUD, UI scale, mobile layout, units, and
-- key rebinding. Values are saved to the profile (validated by the server).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Controllers = script.Parent.Parent.Controllers
local ClientState = require(Controllers.ClientState)
local InputController = require(Controllers.InputController)

local SettingsUI = {}

local C = Theme.Colors
local new = Components.new

local modal: Components.Modal
local content: ScrollingFrame
local capturing: string? = nil

local function percent(v: number): string
	return string.format("%d%%", math.floor(v * 100 + 0.5))
end

local function section(text: string, order: number)
	local label = Components.text(content, text, Theme.TextSize.Caption, C.Accent, Theme.Fonts.Heading, { LayoutOrder = order })
	label.Size = UDim2.new(1, 0, 0, 28)
end

local function render()
	Components.clear(content)
	local s = ClientState.settings
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local function set(key: string)
		return function(value: any)
			ClientState.setSetting(key, value)
		end
	end

	section("AUDIO", nextOrder())
	Components.slider(content, "Master volume", 0, 1, s.MasterVolume, 0.05, set("MasterVolume"), percent).LayoutOrder = nextOrder()
	Components.slider(content, "Motor volume", 0, 1, s.MotorVolume, 0.05, set("MotorVolume"), percent).LayoutOrder = nextOrder()
	Components.slider(content, "UI volume", 0, 1, s.UiVolume, 0.05, set("UiVolume"), percent).LayoutOrder = nextOrder()

	section("RIDING", nextOrder())
	Components.slider(content, "Wheelie assist", 0, 1, s.WheelieAssist, 0.05, set("WheelieAssist"), percent).LayoutOrder = nextOrder()
	Components.choice(content, "Speed units", { "MPH", "KMH" }, s.Units, set("Units")).LayoutOrder = nextOrder()

	section("CAMERA", nextOrder())
	Components.choice(content, "Default camera", GameConfig.Camera.Modes, s.CameraMode, set("CameraMode")).LayoutOrder = nextOrder()
	Components.slider(content, "Camera sensitivity", 0.2, 3, s.CameraSensitivity, 0.1, set("CameraSensitivity"), function(v)
		return string.format("%.1fx", v)
	end).LayoutOrder = nextOrder()
	Components.toggle(content, "Reduced motion", s.ReducedMotion, set("ReducedMotion")).LayoutOrder = nextOrder()

	section("DISPLAY", nextOrder())
	Components.choice(content, "Graphics", { "Auto", "Low", "High" }, s.Graphics, set("Graphics")).LayoutOrder = nextOrder()
	Components.toggle(content, "Show speedometer", s.ShowSpeedometer, set("ShowSpeedometer")).LayoutOrder = nextOrder()
	Components.toggle(content, "Tyre marks", s.TyreTrails, set("TyreTrails")).LayoutOrder = nextOrder()
	Components.slider(content, "UI scale", 0.75, 1.3, s.UiScale, 0.05, set("UiScale"), percent).LayoutOrder = nextOrder()
	Components.choice(content, "Touch layout", { "Right", "Left" }, s.MobileLayout, set("MobileLayout"), function(v)
		return if v == "Right" then "Throttle right" else "Throttle left"
	end).LayoutOrder = nextOrder()

	if UserInputService.KeyboardEnabled then
		section("KEYBOARD (click a key, then press the new one)", nextOrder())
		for _, action in { "Throttle", "Brake", "SteerLeft", "SteerRight", "LeanBack", "LeanForward", "RearBrake", "Mount", "Recover", "Camera", "Headlight", "Garage", "Map", "Tricks", "Trick1", "Trick2", "Trick3", "Trick4" } do
			local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = nextOrder(), Parent = content })
			Components.text(row, action:gsub("(%l)(%u)", "%1 %2"), Theme.TextSize.Body, C.Text, Theme.Fonts.Heading, { Size = UDim2.new(0.6, 0, 1, 0) })
			Components.button(row, if capturing == action then "PRESS A KEY…" else InputController.keyName(action), if capturing == action then "Primary" else "Secondary", function()
				capturing = action
				render()
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(170, 40), TextSize = 14 })
		end
		Components.button(content, "RESET KEYS", "Ghost", function()
			ClientState.setSetting("Keybinds", {})
			InputController.setKeybinds({})
			render()
		end, { LayoutOrder = nextOrder() })
	end
end

function SettingsUI.init(screen: ScreenGui)
	modal = Components.modal(screen, "Settings", 0.5, 0.82)
	content = Components.scroll(modal.Body)
	Components.list(content, Enum.FillDirection.Vertical, 4)
	Components.padding(content, 4, 4)
	UserInputService.InputBegan:Connect(function(input)
		if capturing and input.UserInputType == Enum.UserInputType.Keyboard then
			local action = capturing
			capturing = nil
			if input.KeyCode ~= Enum.KeyCode.Escape then
				local binds = table.clone(ClientState.settings.Keybinds or {})
				binds[action] = input.KeyCode.Name
				ClientState.setSetting("Keybinds", binds)
				InputController.setKeybinds(binds)
			end
			render()
		end
	end)
	modal.onClose(function()
		capturing = nil
	end)
end

function SettingsUI.open()
	modal.open()
	render()
end

function SettingsUI.modal(): Components.Modal
	return modal
end

return SettingsUI
