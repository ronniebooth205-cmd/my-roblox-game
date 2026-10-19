--!strict
-- ServerScriptService > Services > EconomyService (ModuleScript)
-- The only place cash and XP change. Handles levelling up, reward notifications, redeemable
-- codes and saving player settings (validated against GameConfig.SettingsSchema).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage.Shared.EconomyConfig)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Utilities = require(ReplicatedStorage.Shared.Utilities)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerDataService = require(script.Parent.PlayerDataService)

local EconomyService = {}

local codeLimiter = Utilities.newRateLimiter(5, 30)
local settingsLimiter = Utilities.newRateLimiter(10, 10)

local function notify(player: Player, payload: { [string]: any })
	Remotes.event("Notify"):FireClient(player, payload)
end
EconomyService.notify = notify

-- Adds XP and handles any level-ups. Returns the number of levels gained.
local function addXp(player: Player, amount: number): number
	local profile = PlayerDataService.get(player)
	if not profile or amount <= 0 then
		return 0
	end
	profile.Xp += math.floor(amount)
	local gained = 0
	while profile.Level < EconomyConfig.MaxLevel and profile.Xp >= EconomyConfig.xpForLevel(profile.Level) do
		profile.Xp -= EconomyConfig.xpForLevel(profile.Level)
		profile.Level += 1
		gained += 1
	end
	if gained > 0 then
		local unlocks = {}
		for _, unlock in EconomyConfig.LevelUnlocks do
			if unlock.Level > profile.Level - gained and unlock.Level <= profile.Level then
				table.insert(unlocks, unlock.Text)
			end
		end
		notify(player, { Kind = "LevelUp", Level = profile.Level, Unlocks = unlocks, Text = "Level " .. profile.Level .. "!" })
	end
	return gained
end

-- Pays cash and/or XP with a reason shown to the player. Amounts come from server-side config
-- or validated calculations only.
function EconomyService.grant(player: Player, cash: number, xp: number, text: string?, kind: string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return
	end
	cash = math.max(0, math.floor(cash))
	xp = math.max(0, math.floor(xp))
	profile.Cash += cash
	profile.Stats.TotalCashEarned += cash
	addXp(player, xp)
	PlayerDataService.push(player)
	if text then
		notify(player, { Kind = kind or "Reward", Text = text, Cash = cash, Xp = xp })
	end
end

-- Spends cash if the player can afford it. Returns true when paid.
function EconomyService.spend(player: Player, amount: number): boolean
	local profile = PlayerDataService.get(player)
	if not profile or amount < 0 or profile.Cash < amount then
		return false
	end
	profile.Cash -= math.floor(amount)
	PlayerDataService.push(player)
	return true
end

local function validateSettings(input: any): { [string]: any }?
	if type(input) ~= "table" then
		return nil
	end
	local clean = {}
	for keyName, rule in GameConfig.SettingsSchema :: any do
		local value = input[keyName]
		local validString = rule.Type == "string" and type(value) == "string" and table.find(rule.Options, value) ~= nil
		if rule.Type == "number" and type(value) == "number" and value == value then
			clean[keyName] = math.clamp(value, rule.Min, rule.Max)
		elseif (rule.Type == "boolean" and type(value) == "boolean") or validString then
			clean[keyName] = value
		elseif rule.Type == "keybinds" and type(value) == "table" then
			local binds = {}
			local count = 0
			for action, keyNameValue in value do
				if type(action) == "string" and type(keyNameValue) == "string" and GameConfig.DefaultKeybinds[action] and #keyNameValue <= 24 then
					local ok = pcall(function()
						return (Enum.KeyCode :: any)[keyNameValue]
					end)
					if ok then
						binds[action] = keyNameValue
						count += 1
					end
				end
				if count > 40 then
					break
				end
			end
			clean[keyName] = binds
		end
	end
	return clean
end

function EconomyService.init()
	Remotes.func("RedeemCode").OnServerInvoke = function(player: Player, code: any)
		if not codeLimiter:check(player) then
			return { Ok = false, Message = "Slow down a little." }
		end
		local profile = PlayerDataService.get(player)
		if not profile or type(code) ~= "string" or #code > 32 then
			return { Ok = false, Message = "That code isn't valid." }
		end
		local normalised = code:upper():gsub("%s", "")
		local reward = (EconomyConfig.Codes :: any)[normalised]
		if not reward then
			return { Ok = false, Message = "That code isn't valid." }
		end
		if profile.RedeemedCodes[normalised] then
			return { Ok = false, Message = "You've already used that code." }
		end
		profile.RedeemedCodes[normalised] = true
		EconomyService.grant(player, reward.Cash or 0, reward.Xp or 0, "Code redeemed!", "Reward")
		return { Ok = true, Message = "Code redeemed!" }
	end

	Remotes.event("Settings").OnServerEvent:Connect(function(player: Player, input: any)
		if not settingsLimiter:check(player) then
			return
		end
		local profile = PlayerDataService.get(player)
		local clean = validateSettings(input)
		if profile and clean then
			for keyName, value in clean do
				profile.Settings[keyName] = value
			end
			if type(input) == "table" and input.TutorialDone == true then
				profile.TutorialDone = true
			end
		end
	end)
end

function EconomyService.start() end

return EconomyService
