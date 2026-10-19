--!strict
-- ServerScriptService > Services > GarageService (ModuleScript)
-- Every garage and shop action, behind the "Garage" RemoteFunction. The client only ever asks;
-- this checks ownership, level, price and argument types before touching the profile, so a
-- modified client can't get bikes, paint or upgrades for free or edit someone else's bike.
-- Returns { Ok = boolean, Message = string }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BikeDefinitions = require(ReplicatedStorage.Shared.BikeDefinitions)
local BikeStats = require(ReplicatedStorage.Shared.BikeStats)
local CustomisationConfig = require(ReplicatedStorage.Shared.CustomisationConfig)
local Utilities = require(ReplicatedStorage.Shared.Utilities)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local BikeService = require(script.Parent.BikeService)

local GarageService = {}

type Result = { Ok: boolean, Message: string }

local limiter = Utilities.newRateLimiter(20, 5)

local function fail(message: string): Result
	return { Ok = false, Message = message }
end

local function ok(message: string): Result
	return { Ok = true, Message = message }
end

local function isString(value: any, maxLength: number): boolean
	return type(value) == "string" and #value <= maxLength
end

-- Free items (price 0) are owned by everyone who meets the level.
local function ownsCosmetic(profile: any, key: string, price: number, level: number): boolean
	if profile.Level < level then
		return false
	end
	return price <= 0 or profile.OwnedCosmetics[key] == true
end

local handlers: { [string]: (player: Player, profile: any, ...any) -> Result } = {}

function handlers.BuyBike(player, profile, bikeId)
	local def = isString(bikeId, 40) and BikeDefinitions.get(bikeId)
	if not def then
		return fail("Unknown bike.")
	end
	if profile.OwnedBikes[def.Id] then
		return fail("You already own this bike.")
	end
	if profile.Level < def.LevelRequired then
		return fail("Reach level " .. def.LevelRequired .. " to buy this bike.")
	end
	if not EconomyService.spend(player, def.Price) then
		return fail("Not enough cash.")
	end
	profile.OwnedBikes[def.Id] = true
	profile.BikeSetups[def.Id] = profile.BikeSetups[def.Id] or BikeStats.defaultSetup(def.Id)
	profile.EquippedBike = def.Id
	return ok("Bought the " .. def.DisplayName .. "!")
end

function handlers.EquipBike(player, profile, bikeId)
	if not isString(bikeId, 40) or not profile.OwnedBikes[bikeId] then
		return fail("You don't own that bike.")
	end
	profile.EquippedBike = bikeId
	BikeService.refreshBike(player)
	return ok("Equipped.")
end

function handlers.BuyUpgrade(_player, profile, bikeId, upgradeId)
	local def = isString(bikeId, 40) and BikeDefinitions.get(bikeId)
	local upgrade = isString(upgradeId, 30) and (CustomisationConfig.Upgrades :: any)[upgradeId]
	if not def or not upgrade or not profile.OwnedBikes[def.Id] then
		return fail("Invalid upgrade.")
	end
	local setup = profile.BikeSetups[def.Id]
	local current = setup.Upgrades[upgradeId] or 0
	local nextLevel = current + 1
	if nextLevel > def.MaxUpgradeLevel or not upgrade.Prices[nextLevel] then
		return fail("This bike can't take any more " .. upgrade.Label:lower() .. " upgrades.")
	end
	local levelNeeded = upgrade.LevelRequired[nextLevel] or 1
	if profile.Level < levelNeeded then
		return fail("Reach level " .. levelNeeded .. " first.")
	end
	if not EconomyService.spend(_player, upgrade.Prices[nextLevel]) then
		return fail("Not enough cash.")
	end
	setup.Upgrades[upgradeId] = nextLevel
	return ok(upgrade.Label .. " upgraded to " .. (upgrade.LevelNames[nextLevel + 1] or ("level " .. nextLevel)) .. ".")
end

function handlers.BuyColour(player, profile, colourName)
	local colour = isString(colourName, 40) and CustomisationConfig.colour(colourName)
	if not colour then
		return fail("Unknown colour.")
	end
	local key = "colour:" .. colour.Name
	if ownsCosmetic(profile, key, colour.Price, colour.Level) then
		return fail("You already have this colour.")
	end
	if profile.Level < colour.Level then
		return fail("Reach level " .. colour.Level .. " to unlock this colour.")
	end
	if not EconomyService.spend(player, colour.Price) then
		return fail("Not enough cash.")
	end
	profile.OwnedCosmetics[key] = true
	return ok("Unlocked " .. colour.Name .. ".")
end

function handlers.BuyOption(player, profile, optionId, choiceId)
	local choice = isString(optionId, 30) and isString(choiceId, 30) and CustomisationConfig.optionChoice(optionId, choiceId)
	if not choice then
		return fail("Unknown part.")
	end
	local key = "option:" .. optionId .. ":" .. choice.Id
	if ownsCosmetic(profile, key, choice.Price, choice.Level) then
		return fail("You already have this.")
	end
	if profile.Level < choice.Level then
		return fail("Reach level " .. choice.Level .. " to unlock this.")
	end
	if not EconomyService.spend(player, choice.Price) then
		return fail("Not enough cash.")
	end
	profile.OwnedCosmetics[key] = true
	return ok("Unlocked " .. choice.Label .. ".")
end

function handlers.SetPaint(player, profile, bikeId, slotId, colourName)
	local colour = isString(colourName, 40) and CustomisationConfig.colour(colourName)
	local slot = isString(slotId, 30) and CustomisationConfig.paintSlot(slotId)
	if not colour or not slot or not isString(bikeId, 40) or not profile.OwnedBikes[bikeId] then
		return fail("Invalid paint.")
	end
	if not ownsCosmetic(profile, "colour:" .. colour.Name, colour.Price, colour.Level) then
		return fail("Unlock this colour first.")
	end
	profile.BikeSetups[bikeId].Colours[slot.Id] = colour.Name
	BikeService.refreshBike(player)
	return ok("Painted.")
end

function handlers.SetOption(player, profile, bikeId, optionId, choiceId)
	local choice = isString(optionId, 30) and isString(choiceId, 30) and CustomisationConfig.optionChoice(optionId, choiceId)
	if not choice or not isString(bikeId, 40) or not profile.OwnedBikes[bikeId] then
		return fail("Invalid part.")
	end
	if not ownsCosmetic(profile, "option:" .. optionId .. ":" .. choice.Id, choice.Price, choice.Level) then
		return fail("Unlock this first.")
	end
	profile.BikeSetups[bikeId].Options[optionId] = choice.Id
	BikeService.refreshBike(player)
	return ok("Fitted.")
end

function handlers.SetTuning(_player, profile, bikeId, tuningId, value)
	local tuning = isString(tuningId, 30) and (CustomisationConfig.Tuning :: any)[tuningId]
	if not tuning or not isString(bikeId, 40) or not profile.OwnedBikes[bikeId] or type(value) ~= "number" or value ~= value then
		return fail("Invalid setting.")
	end
	local setup = profile.BikeSetups[bikeId]
	local lo, hi = BikeStats.tuningRange(tuningId, setup.Upgrades.Controller or 0)
	setup.Tuning[tuningId] = math.clamp(value, lo, hi)
	return ok("Tuned.")
end

function handlers.SetPlate(player, profile, bikeId, text)
	if not isString(bikeId, 40) or not profile.OwnedBikes[bikeId] or not isString(text, CustomisationConfig.Plate.MaxLength) then
		return fail("Invalid plate.")
	end
	local upper = (text :: string):upper()
	if #upper == 0 or not upper:match(CustomisationConfig.Plate.Pattern) then
		return fail("Plates can only use letters, numbers and spaces.")
	end
	profile.BikeSetups[bikeId].Plate = upper
	BikeService.refreshBike(player)
	return ok("Plate updated.")
end

function GarageService.init()
	Remotes.func("Garage").OnServerInvoke = function(player: Player, action: any, ...: any): Result
		if not limiter:check(player) then
			return fail("Slow down a little.")
		end
		local profile = PlayerDataService.get(player)
		if not profile then
			return fail("Still loading your data.")
		end
		local handler = type(action) == "string" and handlers[action]
		if not handler then
			return fail("Unknown action.")
		end
		local success, result = pcall(handler, player, profile, ...)
		if not success then
			warn("[GarageService] " .. tostring(action) .. " failed: " .. tostring(result))
			return fail("Something went wrong. Try again.")
		end
		PlayerDataService.push(player)
		return result
	end
end

function GarageService.start() end

return GarageService
