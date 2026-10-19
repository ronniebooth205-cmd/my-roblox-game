--!strict
-- StarterPlayer > StarterPlayerScripts > UI > GarageUI (ModuleScript)
-- The garage: your bike on the Volt Customs turntable with a rotating preview camera, and
-- tabs for paint, wheels, bars, extras, performance upgrades, controller tuning and the
-- number plate. Picking something previews it instantly on the turntable; owned items apply
-- straight away, locked ones show their price/level with a buy button. Every change goes
-- through the server (GarageService) which checks ownership, level and cash.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BikeBuilder = require(ReplicatedStorage.Shared.BikeBuilder)
local BikeDefinitions = require(ReplicatedStorage.Shared.BikeDefinitions)
local BikeStats = require(ReplicatedStorage.Shared.BikeStats)
local CustomisationConfig = require(ReplicatedStorage.Shared.CustomisationConfig)
local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local Utilities = require(ReplicatedStorage.Shared.Utilities)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Controllers = script.Parent.Parent.Controllers
local ClientState = require(Controllers.ClientState)
local CameraController = require(Controllers.CameraController)

local GarageUI = {}

local C = Theme.Colors
local new = Components.new

local modal: Components.Modal
local content: ScrollingFrame
local statsPanel: Frame
local bikeLabel: TextLabel
local equipButton: TextButton
local buyBar: Frame
local buyText: TextLabel
local buyButton: TextButton
local tabs: { select: (name: string) -> () }
local currentTab = "Body"
local editingBike = ""
local previewSetup: BikeStats.BikeSetup? = nil
local previewModel: Model? = nil
local spin = 0
local spinConnection: RBXScriptConnection? = nil
local pendingBuy: (() -> ())? = nil
local notify: (text: string, kind: string?) -> () = function(_text: string, _kind: string?) end

local TABS = { "Body", "Wheels", "Bars", "Extras", "Performance", "Tuning", "Plate" }

local function profile(): { [string]: any }?
	return ClientState.profile
end

local function invoke(action: string, ...: any): boolean
	local args = table.pack(...)
	local ok, result = pcall(function()
		return Remotes.func("Garage"):InvokeServer(action, table.unpack(args, 1, args.n))
	end)
	if ok and type(result) == "table" then
		notify(result.Message, if result.Ok then "Reward" else "Warning")
		return result.Ok == true
	end
	notify("Couldn't reach the garage. Try again.", "Warning")
	return false
end

------------------------------------------------------------------------ preview

local function turntableCFrame(model: Model): CFrame
	local r = model:GetAttribute("WheelRadius") :: number
	local height = r + (model:GetAttribute("SuspensionRest") :: number) - (model:GetAttribute("StaticSag") :: number) + (model:GetAttribute("MountDrop") :: number)
	return CFrame.new(MapLayout.Places.GarageTurntable + Vector3.new(0, MapLayout.RoadTop + 0.8 + height, 0)) * CFrame.Angles(0, spin, 0)
end

local function rebuildPreview()
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end
	if editingBike == "" or not previewSetup then
		return
	end
	local model = BikeBuilder.build(editingBike, previewSetup, { Anchored = true, Name = "GaragePreview" })
	model:PivotTo(turntableCFrame(model))
	BikeBuilder.setPlateText(model, previewSetup.Plate)
	model.Parent = Workspace
	previewModel = model
end

local function sceneCFrame(): CFrame
	local focus = MapLayout.Places.GarageTurntable + Vector3.new(0, 3, 0)
	local cam = focus + MapLayout.Places.GarageCameraOffset
	-- Frame the bike to the right of the panel.
	return CFrame.lookAt(cam, focus) * CFrame.new(-3, 0, 0)
end

------------------------------------------------------------------------ stats

local function refreshStats()
	Components.clear(statsPanel)
	if editingBike == "" or not previewSetup then
		return
	end
	local p = profile()
	local saved = p and p.BikeSetups[editingBike]
	local now = BikeStats.ratings(BikeStats.compute(editingBike, saved))
	local preview = BikeStats.ratings(BikeStats.compute(editingBike, previewSetup))
	Components.text(statsPanel, "STATS", Theme.TextSize.Caption, C.TextMuted, Theme.Fonts.Heading, { LayoutOrder = 0 })
	for i, key in { "Speed", "Acceleration", "Wheelie", "Brakes", "Handling", "Stability" } do
		local row = Components.statRow(statsPanel, key:upper(), now[key], preview[key])
		row.LayoutOrder = i
	end
end

------------------------------------------------------------------------ buy bar

local function showBuy(text: string?, label: string?, action: (() -> ())?)
	pendingBuy = action
	buyBar.Visible = text ~= nil
	if text then
		buyText.Text = text
		buyButton.Text = label or "BUY"
		buyButton.Visible = action ~= nil
	end
end

------------------------------------------------------------------------ tab content

local function sectionTitle(text: string, order: number)
	Components.text(content, text:upper(), Theme.TextSize.Caption, C.TextMuted, Theme.Fonts.Heading, { LayoutOrder = order })
end

local function paintSection(slot: { [string]: any }, order: number): number
	local setup = previewSetup :: BikeStats.BikeSetup
	sectionTitle(slot.Label, order)
	local grid = new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.fromScale(1, 0), LayoutOrder = order + 1, Parent = content })
	new("UIGridLayout", { CellSize = UDim2.fromOffset(52, 52), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	for i, colour in CustomisationConfig.Colours do
		local owned = ClientState.ownsCosmetic("colour:" .. colour.Name, colour.Price, colour.Level)
		local swatch = Components.swatch(grid, colour.Color, not owned, setup.Colours[slot.Id] == colour.Name, function()
			setup.Colours[slot.Id] = colour.Name
			rebuildPreview()
			refreshStats()
			if owned then
				showBuy(nil)
				task.spawn(invoke, "SetPaint", editingBike, slot.Id, colour.Name)
			else
				local p = profile()
				if p and p.Level < colour.Level then
					showBuy(string.format("%s unlocks at level %d", colour.Name, colour.Level), nil, nil)
				else
					showBuy(string.format("%s  ·  %s", colour.Name, Utilities.formatCash(colour.Price)), "BUY & APPLY", function()
						if invoke("BuyColour", colour.Name) then
							invoke("SetPaint", editingBike, slot.Id, colour.Name)
							showBuy(nil)
						end
					end)
				end
			end
			GarageUI.refresh()
		end)
		swatch.LayoutOrder = i
	end
	return order + 2
end

local function optionSection(optionId: string, option: { [string]: any }, order: number): number
	local setup = previewSetup :: BikeStats.BikeSetup
	sectionTitle(option.Label, order)
	local row = new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.fromScale(1, 0), LayoutOrder = order + 1, Parent = content })
	new("UIGridLayout", { CellSize = UDim2.fromOffset(150, 48), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
	for i, choice in option.Choices do
		local owned = ClientState.ownsCosmetic("option:" .. optionId .. ":" .. choice.Id, choice.Price, choice.Level)
		local selected = setup.Options[optionId] == choice.Id
		local label = choice.Label .. (if owned then "" else "  🔒")
		local button = Components.button(row, label, if selected then "Primary" else "Secondary", function()
			setup.Options[optionId] = choice.Id
			rebuildPreview()
			refreshStats()
			if owned then
				showBuy(nil)
				task.spawn(invoke, "SetOption", editingBike, optionId, choice.Id)
			else
				local p = profile()
				if p and p.Level < choice.Level then
					showBuy(string.format("%s unlocks at level %d", choice.Label, choice.Level), nil, nil)
				else
					showBuy(string.format("%s  ·  %s", choice.Label, Utilities.formatCash(choice.Price)), "BUY & FIT", function()
						if invoke("BuyOption", optionId, choice.Id) then
							invoke("SetOption", editingBike, optionId, choice.Id)
							showBuy(nil)
						end
					end)
				end
			end
			GarageUI.refresh()
		end, { TextSize = 14 })
		button.LayoutOrder = i
	end
	return order + 2
end

local function performanceTab()
	local p = profile()
	local def = BikeDefinitions.get(editingBike)
	if not p or not def then
		return
	end
	local setup = p.BikeSetups[editingBike]
	for i, upgradeId in CustomisationConfig.UpgradeOrder do
		local upgrade = (CustomisationConfig.Upgrades :: any)[upgradeId]
		local level = setup.Upgrades[upgradeId] or 0
		local card = Components.panel(content, { Size = UDim2.new(1, -8, 0, 96), LayoutOrder = i, BackgroundColor3 = C.SurfaceRaised })
		Components.padding(card, 12, 10)
		Components.text(card, upgrade.Label:upper() .. "  ·  " .. (upgrade.LevelNames[level + 1] or ""), 16, C.Text, Theme.Fonts.Heading, { Size = UDim2.new(0.62, 0, 0, 22) })
		Components.text(card, upgrade.Description, 13, C.TextMuted, Theme.Fonts.Body, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(0.62, 0, 0, 30) })
		local pips = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 58), Size = UDim2.new(0.6, 0, 0, 10), Parent = card })
		Components.list(pips, Enum.FillDirection.Horizontal, 4)
		for k = 1, def.MaxUpgradeLevel do
			local pip = new("Frame", { BackgroundColor3 = if k <= level then C.Accent else C.Surface, Size = UDim2.fromOffset(28, 8), LayoutOrder = k, Parent = pips })
			Components.corner(pip, Theme.Radius.Pill)
		end
		local nextLevel = level + 1
		local text, style, enabled
		if nextLevel > def.MaxUpgradeLevel or not upgrade.Prices[nextLevel] then
			text, style, enabled = "MAXED", "Ghost", false
		elseif p.Level < (upgrade.LevelRequired[nextLevel] or 1) then
			text, style, enabled = "LEVEL " .. upgrade.LevelRequired[nextLevel], "Ghost", false
		else
			text, style, enabled = "UPGRADE " .. Utilities.formatCash(upgrade.Prices[nextLevel]), if p.Cash >= upgrade.Prices[nextLevel] then "Primary" else "Secondary", true
		end
		Components.button(card, text, style, function()
			if enabled and invoke("BuyUpgrade", editingBike, upgradeId) then
				task.delay(0.3, GarageUI.refresh)
			end
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.new(0.36, 0, 0, 48), TextSize = 15 })
	end
end

local tuneTimers: { [string]: number } = {}

local function tuningTab()
	local p = profile()
	if not p then
		return
	end
	local setup = p.BikeSetups[editingBike]
	local controllerLevel = setup.Upgrades.Controller or 0
	Components.text(content, "Upgrade the controller to widen these ranges.", 13, C.TextMuted, Theme.Fonts.Body, { LayoutOrder = 0 })
	local order = 1
	for tuningId, tuning in CustomisationConfig.Tuning :: any do
		local lo, hi = BikeStats.tuningRange(tuningId, controllerLevel)
		local value = math.clamp(setup.Tuning[tuningId] or tuning.Default, lo, hi)
		local isPercent = tuningId == "SpeedLimiter" or tuningId == "Regen" or tuningId == "WheelieAssist"
		local row = Components.slider(content, tuning.Label, lo, hi, value, 0.05, function(v)
			if previewSetup then
				previewSetup.Tuning[tuningId] = v
				refreshStats()
			end
			-- Save after the slider settles.
			local stamp = os.clock()
			tuneTimers[tuningId] = stamp
			task.delay(0.6, function()
				if tuneTimers[tuningId] == stamp then
					invoke("SetTuning", editingBike, tuningId, v)
				end
			end)
		end, function(v)
			return if isPercent then string.format("%d%%", math.floor(v * 100 + 0.5)) else string.format("%.2fx", v)
		end)
		row.LayoutOrder = order
		order += 1
	end
end

local function plateTab()
	local setup = previewSetup :: BikeStats.BikeSetup
	Components.text(content, "Letters, numbers and spaces, up to " .. CustomisationConfig.Plate.MaxLength .. " characters. Plates are filtered before others see them.", 13, C.TextMuted, Theme.Fonts.Body, { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 36) })
	local box = new("TextBox", {
		Text = setup.Plate,
		PlaceholderText = "PLATE",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		TextColor3 = Color3.fromRGB(20, 20, 20),
		BackgroundColor3 = Color3.fromRGB(245, 205, 40),
		ClearTextOnFocus = false,
		Size = UDim2.new(1, -8, 0, 64),
		LayoutOrder = 1,
		Parent = content,
	})
	Components.corner(box)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local cleaned = box.Text:upper():gsub("[^%w ]", ""):sub(1, CustomisationConfig.Plate.MaxLength)
		if cleaned ~= box.Text then
			box.Text = cleaned
		end
	end)
	Components.button(content, "SAVE PLATE", "Primary", function()
		if invoke("SetPlate", editingBike, box.Text) then
			setup.Plate = box.Text
			rebuildPreview()
		end
	end, { LayoutOrder = 2, Size = UDim2.new(1, -8, 0, 48) })
end

local function renderTab()
	Components.clear(content)
	if not previewSetup then
		return
	end
	if currentTab == "Performance" then
		performanceTab()
	elseif currentTab == "Tuning" then
		tuningTab()
	elseif currentTab == "Plate" then
		plateTab()
	else
		local order = 0
		for _, slot in CustomisationConfig.PaintSlots do
			if slot.Tab == currentTab then
				order = paintSection(slot, order)
			end
		end
		for optionId, option in CustomisationConfig.Options :: any do
			if option.Tab == currentTab then
				order = optionSection(optionId, option, order + 100)
			end
		end
	end
end

------------------------------------------------------------------------ bike selector

local function ownedBikes(): { string }
	local p = profile()
	local list = {}
	if p then
		for _, def in BikeDefinitions.list() do
			if p.OwnedBikes[def.Id] then
				table.insert(list, def.Id)
			end
		end
	end
	return list
end

local function selectBike(bikeId: string)
	local p = profile()
	if not p or not p.OwnedBikes[bikeId] then
		return
	end
	editingBike = bikeId
	previewSetup = Utilities.deepCopy(p.BikeSetups[bikeId]) or BikeStats.defaultSetup(bikeId)
	local def = BikeDefinitions.get(bikeId)
	bikeLabel.Text = if def then def.DisplayName:upper() else bikeId
	local equipped = p.EquippedBike == bikeId
	equipButton.Text = if equipped then "EQUIPPED" else "EQUIP"
	Components.setButtonStyle(equipButton, if equipped then "Ghost" else "Primary")
	showBuy(nil)
	rebuildPreview()
	refreshStats()
	renderTab()
end

local function cycleBike(delta: number)
	local list = ownedBikes()
	local index = table.find(list, editingBike) or 1
	selectBike(list[(index - 1 + delta) % #list + 1])
end

------------------------------------------------------------------------ public

function GarageUI.init(screen: ScreenGui, notifyFn: (text: string, kind: string?) -> ())
	notify = notifyFn
	modal = Components.modal(screen, "Volt Customs", 0.42, 0.9)
	modal.Frame.AnchorPoint = Vector2.new(0, 0.5)
	modal.Frame.Position = UDim2.new(0, 16, 0.5, 0)
	local body = modal.Body

	local selector = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), Parent = body })
	Components.button(selector, "◀", "Secondary", function()
		cycleBike(-1)
	end, { Size = UDim2.fromOffset(44, 44) })
	bikeLabel = Components.text(selector, "", 16, C.Text, Theme.Fonts.Display, { Position = UDim2.fromOffset(52, 0), Size = UDim2.new(1, -230, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true })
	new("UITextSizeConstraint", { MaxTextSize = 18, Parent = bikeLabel })
	Components.button(selector, "▶", "Secondary", function()
		cycleBike(1)
	end, { Size = UDim2.fromOffset(44, 44), Position = UDim2.new(1, -170, 0, 0) })
	equipButton = Components.button(selector, "EQUIP", "Primary", function()
		if invoke("EquipBike", editingBike) then
			task.delay(0.3, function()
				selectBike(editingBike)
			end)
		end
	end, { Size = UDim2.fromOffset(116, 44), Position = UDim2.new(1, -116, 0, 0), TextSize = 15 })

	local tabHolder = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 44), Parent = body })
	tabs = Components.tabs(tabHolder, TABS, function(name)
		currentTab = name
		showBuy(nil)
		renderTab()
	end)

	content = Components.scroll(body, { Position = UDim2.fromOffset(0, 108), Size = UDim2.new(1, 0, 1, -230) })
	Components.list(content, Enum.FillDirection.Vertical, 8)
	Components.padding(content, 2, 4)

	statsPanel = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -58), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = body })
	Components.list(statsPanel, Enum.FillDirection.Vertical, 0)
	statsPanel.Visible = false

	buyBar = Components.panel(body, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = C.SurfaceRaised, Visible = false })
	buyText = Components.text(buyBar, "", 15, C.Text, Theme.Fonts.Heading, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.6, 0, 1, 0) })
	buyButton = Components.button(buyBar, "BUY", "Primary", function()
		if pendingBuy then
			pendingBuy()
			task.delay(0.3, GarageUI.refresh)
		end
	end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.new(0.38, 0, 0, 40), TextSize = 14 })

	-- Stats live in their own small panel at the bottom right, beside the bike.
	local statsCard = Components.panel(screen, { Name = "GarageStats", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.fromOffset(300, 240), Visible = false })
	Components.padding(statsCard, 14, 12)
	statsPanel.Parent = statsCard
	statsPanel.AnchorPoint = Vector2.zero
	statsPanel.Position = UDim2.new()
	statsPanel.Size = UDim2.fromScale(1, 1)
	statsPanel.Visible = true

	modal.onClose(function()
		statsCard.Visible = false
		if spinConnection then
			spinConnection:Disconnect()
			spinConnection = nil
		end
		if previewModel then
			previewModel:Destroy()
			previewModel = nil
		end
		CameraController.setScene(nil)
	end)
	modal.Frame:GetPropertyChangedSignal("Visible"):Connect(function()
		statsCard.Visible = modal.Frame.Visible
	end)
	ClientState.onProfile(function()
		if modal.isOpen() then
			GarageUI.refresh()
		end
	end)
end

-- Re-renders after the profile changes, keeping any un-bought preview choices.
function GarageUI.refresh()
	local p = profile()
	if not p or editingBike == "" then
		return
	end
	local equipped = p.EquippedBike == editingBike
	equipButton.Text = if equipped then "EQUIPPED" else "EQUIP"
	Components.setButtonStyle(equipButton, if equipped then "Ghost" else "Primary")
	refreshStats()
	renderTab()
end

function GarageUI.open(bikeId: string?)
	local p = profile()
	if not p then
		return
	end
	modal.open()
	CameraController.setScene(sceneCFrame)
	selectBike(bikeId or p.EquippedBike)
	tabs.select(currentTab)
	spinConnection = RunService.RenderStepped:Connect(function(dt)
		spin += dt * 0.35
		if previewModel then
			previewModel:PivotTo(turntableCFrame(previewModel))
		end
	end)
end

function GarageUI.modal(): Components.Modal
	return modal
end

return GarageUI
