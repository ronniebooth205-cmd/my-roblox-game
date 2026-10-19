--!strict
-- StarterPlayer > StarterPlayerScripts > UI > UIController (ModuleScript)
-- Builds the ScreenGui and every screen, and decides what is open. One window at a time;
-- opening one closes the others. While any window or the main menu is open the bike coasts
-- (inputs paused). Gamepad: B closes the open window, menus get a selected button so the
-- D-pad works straight away. Applies UI scale, safe-area insets and the touch layout.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local HUD = require(script.Parent.HUD)
local MobileControls = require(script.Parent.MobileControls)
local MainMenu = require(script.Parent.MainMenu)
local GarageUI = require(script.Parent.GarageUI)
local ShopUI = require(script.Parent.ShopUI)
local SettingsUI = require(script.Parent.SettingsUI)
local ProgressUI = require(script.Parent.ProgressUI)
local MapUI = require(script.Parent.MapUI)
local RideoutUI = require(script.Parent.RideoutUI)
local Controllers = script.Parent.Parent.Controllers
local BikeController = require(Controllers.BikeController)
local InputController = require(Controllers.InputController)

local UIController = {}

local screen: ScreenGui
local uiScale: UIScale
local modals: { [string]: Components.Modal } = {}
local riding = false
local touchLayout = false
local listeners: { (open: boolean) -> () } = {}
local playHandler: () -> () = function() end

local function anyOpen(): boolean
	if MainMenu.isOpen() then
		return true
	end
	for _, modal in modals do
		if modal.isOpen() then
			return true
		end
	end
	return false
end

local function refreshInputGate()
	local open = anyOpen()
	BikeController.setInputEnabled(not open)
	MobileControls.setVisible(riding and touchLayout and not open)
	if open then
		ContextActionService:BindActionAtPriority("SurronCloseMenu", function(_, state)
			if state == Enum.UserInputState.Begin then
				UIController.closeAll()
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode.ButtonB)
	else
		ContextActionService:UnbindAction("SurronCloseMenu")
	end
	for _, listener in listeners do
		task.spawn(listener, open)
	end
end

local function selectFirst(container: Instance)
	if InputController.device() ~= "Gamepad" then
		return
	end
	task.defer(function()
		for _, child in container:GetDescendants() do
			if child:IsA("GuiButton") and child.Selectable and child.Visible and child.Name ~= "Close" then
				GuiService.SelectedObject = child
				return
			end
		end
	end)
end

function UIController.closeAll()
	for _, modal in modals do
		modal.close()
	end
	MainMenu.close()
	GuiService.SelectedObject = nil
	refreshInputGate()
end

function UIController.open(name: string, arg: any?)
	for key, modal in modals do
		if key ~= name then
			modal.close()
		end
	end
	if name ~= "MainMenu" then
		MainMenu.close()
	end
	if name == "MainMenu" then
		MainMenu.open()
	elseif name == "Garage" then
		GarageUI.open(arg)
	elseif name == "Shop" then
		ShopUI.open(arg)
	elseif name == "Settings" then
		SettingsUI.open()
	elseif name == "Progress" then
		ProgressUI.open(arg)
	elseif name == "Map" then
		MapUI.open()
	elseif name == "Rideout" then
		RideoutUI.open()
	end
	local modal = modals[name]
	if modal then
		selectFirst(modal.Frame)
	end
	refreshInputGate()
end

function UIController.toggle(name: string, arg: any?)
	local modal = modals[name]
	if modal and modal.isOpen() then
		UIController.closeAll()
	else
		UIController.open(name, arg)
	end
end

function UIController.init(handlers: { [string]: () -> () })
	playHandler = handlers.Play or playHandler
	local player = Players.LocalPlayer
	screen = Components.new("ScreenGui", {
		Name = "SurronUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	uiScale = Components.new("UIScale", { Parent = screen })

	HUD.init(screen, {
		Menu = function()
			UIController.toggle("MainMenu")
		end,
		Garage = function()
			UIController.toggle("Garage")
		end,
		Map = function()
			UIController.toggle("Map")
		end,
		Challenges = function()
			UIController.toggle("Progress")
		end,
		Rideout = function()
			UIController.toggle("Rideout")
		end,
		Prompt = handlers.Prompt,
	})
	MobileControls.init(screen)
	local notify = function(text: string, kind: string?)
		HUD.toast(text, kind)
	end
	GarageUI.init(screen, notify)
	ShopUI.init(screen, notify, function(bikeId)
		UIController.open("Garage", bikeId)
	end)
	SettingsUI.init(screen)
	ProgressUI.init(screen)
	RideoutUI.init(screen)
	MapUI.init(screen, RideoutUI.isLeader)
	modals = {
		Garage = GarageUI.modal(),
		Shop = ShopUI.modal(),
		Settings = SettingsUI.modal(),
		Progress = ProgressUI.modal(),
		Map = MapUI.modal(),
		Rideout = RideoutUI.modal(),
	}
	for _, modal in modals do
		modal.onClose(refreshInputGate)
	end
	MainMenu.init(screen, {
		PLAY = function()
			UIController.closeAll()
			playHandler()
		end,
		GARAGE = function()
			UIController.open("Garage")
		end,
		BIKES = function()
			UIController.open("Shop", "My bikes")
		end,
		SHOP = function()
			UIController.open("Shop", "Bikes")
		end,
		SETTINGS = function()
			UIController.open("Settings")
		end,
	})

	local function updateTouch()
		touchLayout = InputController.device() == "Touch" or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
		HUD.setTouchLayout(touchLayout, false)
		refreshInputGate()
	end
	InputController.onDeviceChanged(updateTouch)
	updateTouch()
end

function UIController.setRiding(isRiding: boolean)
	riding = isRiding
	HUD.setRiding(isRiding)
	refreshInputGate()
end

function UIController.applySettings(settings: { [string]: any })
	uiScale.Scale = settings.UiScale or 1
	HUD.applySettings(settings)
	local left = settings.MobileLayout == "Left"
	MobileControls.setLeftHanded(left)
	HUD.setTouchLayout(touchLayout, left)
end

function UIController.isAnyOpen(): boolean
	return anyOpen()
end

function UIController.onMenuStateChanged(listener: (open: boolean) -> ())
	table.insert(listeners, listener)
end

function UIController.screen(): ScreenGui
	return screen
end

UIController.Theme = Theme

return UIController
