--!strict
-- StarterPlayer > StarterPlayerScripts > UI > ShopUI (ModuleScript)
-- BIKES and SHOP: a scrolling row of bike cards (name, voltage, stats, price, level) with
-- buy/equip/customise buttons, plus a paint shop that unlocks colours for every bike.
-- Purchases are requests to GarageService; nothing is granted on the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BikeDefinitions = require(ReplicatedStorage.Shared.BikeDefinitions)
local BikeStats = require(ReplicatedStorage.Shared.BikeStats)
local CustomisationConfig = require(ReplicatedStorage.Shared.CustomisationConfig)
local Utilities = require(ReplicatedStorage.Shared.Utilities)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Controllers = script.Parent.Parent.Controllers
local ClientState = require(Controllers.ClientState)

local ShopUI = {}

local C = Theme.Colors
local new = Components.new

local modal: Components.Modal
local content: ScrollingFrame
local tabs: { select: (name: string) -> () }
local currentTab = "Bikes"
local notify: (text: string, kind: string?) -> () = function(_text: string, _kind: string?) end
local openGarage: (bikeId: string) -> () = function(_bikeId: string) end

local function invoke(action: string, ...: any): boolean
	local args = table.pack(...)
	local ok, result = pcall(function()
		return Remotes.func("Garage"):InvokeServer(action, table.unpack(args, 1, args.n))
	end)
	if ok and type(result) == "table" then
		notify(result.Message, if result.Ok then "Reward" else "Warning")
		return result.Ok == true
	end
	return false
end

local function bikeCard(def: BikeDefinitions.BikeDefinition, order: number)
	local p = ClientState.profile
	if not p then
		return
	end
	local owned = p.OwnedBikes[def.Id] == true
	local equipped = p.EquippedBike == def.Id
	local card = Components.panel(content, { Size = UDim2.new(0, 290, 1, -12), LayoutOrder = order, BackgroundColor3 = C.SurfaceRaised })
	Components.padding(card, 16, 14)
	Components.list(card, Enum.FillDirection.Vertical, 6)
	local badge = Components.text(card, def.Voltage .. (if equipped then "  ·  EQUIPPED" elseif owned then "  ·  OWNED" else ""), 13, if equipped then C.Accent else C.TextMuted, Theme.Fonts.Heading, { LayoutOrder = 1 })
	badge.Size = UDim2.new(1, 0, 0, 16)
	Components.text(card, def.DisplayName:upper(), 22, C.Text, Theme.Fonts.Display, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 54) })
	Components.text(card, def.Tagline, 13, C.TextMuted, Theme.Fonts.Body, { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 36) })
	local ratings = BikeStats.ratings(BikeStats.compute(def.Id, if owned then p.BikeSetups[def.Id] else nil))
	for i, key in { "Speed", "Acceleration", "Wheelie", "Stability" } do
		local row = Components.statRow(card, key:upper(), ratings[key])
		row.LayoutOrder = 3 + i
	end
	local text, style
	if owned then
		text, style = if equipped then "CUSTOMISE" else "EQUIP", if equipped then "Secondary" else "Primary"
	elseif p.Level < def.LevelRequired then
		text, style = "REACH LEVEL " .. def.LevelRequired, "Ghost"
	else
		text, style = "BUY  " .. Utilities.formatCash(def.Price), if p.Cash >= def.Price then "Primary" else "Secondary"
	end
	Components.button(card, text, style, function()
		if owned and equipped then
			openGarage(def.Id)
		elseif owned then
			invoke("EquipBike", def.Id)
		elseif p.Level >= def.LevelRequired then
			invoke("BuyBike", def.Id)
		end
	end, { LayoutOrder = 20, TextSize = 16 })
end

local function paintShop()
	local p = ClientState.profile
	if not p then
		return
	end
	for i, colour in CustomisationConfig.Colours do
		local key = "colour:" .. colour.Name
		local owned = ClientState.ownsCosmetic(key, colour.Price, colour.Level)
		local card = Components.panel(content, { Size = UDim2.new(0, 160, 1, -12), LayoutOrder = i, BackgroundColor3 = C.SurfaceRaised })
		Components.padding(card, 12, 12)
		local swatch = new("Frame", { BackgroundColor3 = colour.Color, Size = UDim2.new(1, 0, 0.45, 0), Parent = card })
		Components.corner(swatch)
		Components.text(card, colour.Name:upper(), 15, C.Text, Theme.Fonts.Heading, { Position = UDim2.new(0, 0, 0.48, 0), Size = UDim2.new(1, 0, 0, 36) })
		local text, style
		if owned then
			text, style = "OWNED", "Ghost"
		elseif p.Level < colour.Level then
			text, style = "LEVEL " .. colour.Level, "Ghost"
		else
			text, style = Utilities.formatCash(colour.Price), "Primary"
		end
		Components.button(card, text, style, function()
			if not owned and p.Level >= colour.Level then
				invoke("BuyColour", colour.Name)
			end
		end, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 44), TextSize = 15 })
	end
end

local function render()
	Components.clear(content)
	if currentTab == "Paint" then
		paintShop()
		return
	end
	local p = ClientState.profile
	for i, def in BikeDefinitions.list() do
		if currentTab == "Bikes" or (p and p.OwnedBikes[def.Id]) then
			bikeCard(def, i)
		end
	end
end

function ShopUI.init(screen: ScreenGui, notifyFn: (text: string, kind: string?) -> (), garageFn: (bikeId: string) -> ())
	notify = notifyFn
	openGarage = garageFn
	modal = Components.modal(screen, "Bikes", 0.8, 0.78)
	local tabHolder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = modal.Body })
	tabs = Components.tabs(tabHolder, { "Bikes", "My bikes", "Paint" }, function(name)
		currentTab = name
		render()
	end)
	content = Components.scroll(modal.Body, {
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 1, -54),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
	})
	local list = Components.list(content, Enum.FillDirection.Horizontal, 12)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	Components.padding(content, 2, 4)
	ClientState.onProfile(function()
		if modal.isOpen() then
			render()
		end
	end)
end

function ShopUI.open(tab: string?)
	modal.Title.Text = if tab == "My bikes" then "MY BIKES" else "SHOP"
	modal.open()
	tabs.select(tab or "Bikes")
end

function ShopUI.modal(): Components.Modal
	return modal
end

return ShopUI
