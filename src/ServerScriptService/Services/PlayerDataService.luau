--!strict
-- ServerScriptService > Services > PlayerDataService (ModuleScript)
-- Loads, saves and owns every player's profile. Only the server ever changes a profile; the
-- client gets read-only copies through the ProfileUpdated remote.
--
-- Safety rules:
--   * Session lock: a profile stores which server has it open. Another server waits (with
--     retries) instead of loading a stale copy, so items can't be duplicated across servers.
--     A lock older than SessionLockTimeout is treated as left behind by a crashed server.
--   * A failed load never creates a blank profile that saves: the player plays on a temporary
--     profile flagged NoSave and is told progress won't be kept this session.
--   * Saves use UpdateAsync and refuse to write if another server has taken the lock.
--   * Autosave every few minutes, on leave, and on shutdown (BindToClose).
--   * In Studio without "Enable Studio Access to API Services", data stores are unavailable,
--     so everyone gets a temporary profile.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local EconomyConfig = require(ReplicatedStorage.Shared.EconomyConfig)
local BikeDefinitions = require(ReplicatedStorage.Shared.BikeDefinitions)
local BikeStats = require(ReplicatedStorage.Shared.BikeStats)
local Utilities = require(ReplicatedStorage.Shared.Utilities)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PlayerDataService = {}

export type Profile = { [string]: any }

local profiles: { [Player]: Profile } = {}
local noSave: { [Player]: boolean } = {}
local loadedListeners: { (player: Player, profile: Profile) -> () } = {}
local dirty: { [Player]: boolean } = {}
local store: DataStore? = nil
local storeAvailable = false

local function defaultProfile(): Profile
	local starter = BikeDefinitions.StarterBike
	return {
		Version = GameConfig.Data.SchemaVersion,
		Cash = EconomyConfig.StartingCash,
		Xp = 0,
		Level = 1,
		OwnedBikes = { [starter] = true },
		EquippedBike = starter,
		BikeSetups = { [starter] = BikeStats.defaultSetup(starter) },
		OwnedCosmetics = {},
		Stats = {
			TotalWheelieDistance = 0,
			LongestWheelie = 0,
			BestScore = 0,
			TotalRideDistance = 0,
			TotalTricks = 0,
			TotalCashEarned = 0,
			Wheelies = 0,
			Crashes = 0,
		},
		Milestones = {},
		ZonesVisited = {},
		RedeemedCodes = {},
		Challenges = { Day = 0, Progress = {}, Claimed = {}, CleanStreak = 0 },
		Settings = Utilities.deepCopy(GameConfig.DefaultSettings),
		TutorialDone = false,
	}
end

-- Upgrades older saves to the current schema. Add a step here whenever the shape changes, and
-- bump GameConfig.Data.SchemaVersion.
local function migrate(data: Profile): Profile
	local version = tonumber(data.Version) or 0
	if version < 1 then
		-- Pre-release saves had no version; nothing to move yet, reconcile fills the gaps.
		data.Version = 1
	end
	Utilities.reconcile(data, defaultProfile())
	-- Every owned bike needs a full setup (new slots/options get their defaults).
	for bikeId in data.OwnedBikes do
		if not BikeDefinitions.get(bikeId) then
			data.OwnedBikes[bikeId] = nil
		else
			data.BikeSetups[bikeId] = data.BikeSetups[bikeId] or BikeStats.defaultSetup(bikeId)
			Utilities.reconcile(data.BikeSetups[bikeId], BikeStats.defaultSetup(bikeId))
		end
	end
	if not data.OwnedBikes[data.EquippedBike] then
		data.EquippedBike = BikeDefinitions.StarterBike
		data.OwnedBikes[BikeDefinitions.StarterBike] = true
	end
	data.Version = GameConfig.Data.SchemaVersion
	return data
end

local function key(player: Player): string
	return "Player_" .. player.UserId
end

local function stripForClient(profile: Profile): Profile
	local copy = Utilities.deepCopy(profile)
	copy.Lock = nil
	return copy
end

local function updateLeaderstats(player: Player, profile: Profile)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
		for _, name in { "Level", "Best (m)", "Cash" } do
			local value = Instance.new("IntValue")
			value.Name = name
			value.Parent = folder
		end
	end
	(folder:FindFirstChild("Level") :: IntValue).Value = profile.Level;
	(folder:FindFirstChild("Best (m)") :: IntValue).Value = math.floor(profile.Stats.LongestWheelie);
	(folder:FindFirstChild("Cash") :: IntValue).Value = math.floor(profile.Cash)
end

-- Tries UpdateAsync with exponential backoff. Returns ok, result.
local function withRetries(label: string, fn: () -> any): (boolean, any)
	local attempts = GameConfig.Data.LoadRetries
	local lastError = nil
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		warn(string.format("[PlayerData] %s failed (attempt %d/%d): %s", label, attempt, attempts, tostring(result)))
		if attempt < attempts then
			task.wait(math.min(2 ^ attempt, 16))
		end
	end
	return false, lastError
end

local function loadProfile(player: Player): (Profile?, string?)
	local dataStore = store
	if not storeAvailable or not dataStore then
		return nil, "NoStore"
	end
	local lockTimeout = GameConfig.Data.SessionLockTimeout
	for attempt = 1, GameConfig.Data.LoadRetries do
		local lockedElsewhere = false
		local ok, result = withRetries("Load " .. player.UserId, function()
			return dataStore:UpdateAsync(key(player), function(old: Profile?)
				local data = old or defaultProfile()
				local lock = data.Lock
				if lock and lock.JobId ~= game.JobId and os.time() - (lock.Time or 0) < lockTimeout then
					lockedElsewhere = true
					return nil -- leave it alone; another server is still saving it
				end
				data.Lock = { JobId = game.JobId, Time = os.time() }
				return data
			end)
		end)
		if not ok then
			return nil, "LoadFailed"
		end
		if not lockedElsewhere and result then
			return migrate(result), nil
		end
		-- Another server still holds the lock (e.g. the player just hopped servers): wait for it.
		task.wait(math.min(3 * attempt, 10))
		if not player.Parent then
			return nil, "Left"
		end
	end
	return nil, "Locked"
end

local function saveProfile(player: Player, release: boolean): boolean
	local profile = profiles[player]
	local dataStore = store
	if not profile or noSave[player] or not storeAvailable or not dataStore then
		return false
	end
	local snapshot = Utilities.deepCopy(profile)
	snapshot.Lock = if release then nil else { JobId = game.JobId, Time = os.time() }
	local ok = withRetries("Save " .. player.UserId, function()
		return dataStore:UpdateAsync(key(player), function(old: Profile?)
			if old and old.Lock and old.Lock.JobId ~= game.JobId then
				-- Another server took over this profile; never overwrite its newer data.
				return nil
			end
			return snapshot
		end)
	end)
	return ok
end

local function onPlayerAdded(player: Player)
	local profile, reason = loadProfile(player)
	if not player.Parent then
		return
	end
	if not profile then
		if reason == "Locked" then
			player:Kick("Your data is still saving on another server. Please rejoin in a minute.")
			return
		end
		profile = defaultProfile()
		noSave[player] = true
		task.delay(4, function()
			if player.Parent then
				local text = if reason == "NoStore"
					then "Studio test: data stores are off, so progress won't save."
					else "We couldn't load your save. You can play, but progress won't save this time."
				Remotes.event("Notify"):FireClient(player, { Text = text, Kind = "Warning" })
			end
		end)
	end
	local loaded = profile :: Profile
	profiles[player] = loaded
	updateLeaderstats(player, loaded)
	player:SetAttribute("Level", loaded.Level)
	player:SetAttribute("DataLoaded", true)
	for _, listener in loadedListeners do
		task.spawn(listener, player, loaded)
	end
	PlayerDataService.push(player)
end

local function onPlayerRemoving(player: Player)
	if profiles[player] then
		saveProfile(player, true)
	end
	profiles[player] = nil
	noSave[player] = nil
	dirty[player] = nil
end

function PlayerDataService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.Data.StoreName)
	end)
	if ok then
		store = result
		-- In Studio, a quick read tells us whether API access is turned on.
		if RunService:IsStudio() then
			local readOk = pcall(function()
				(result :: DataStore):GetAsync("__probe")
			end)
			storeAvailable = readOk
		else
			storeAvailable = true
		end
	end
	if not storeAvailable then
		warn("[PlayerData] DataStores unavailable; profiles are temporary this session.")
	end

	Remotes.func("GetProfile").OnServerInvoke = function(player: Player)
		local profile = profiles[player]
		return if profile then stripForClient(profile) else nil
	end
end

function PlayerDataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(GameConfig.Data.AutosaveInterval)
			for player in profiles do
				task.spawn(saveProfile, player, false)
			end
		end
	end)

	-- Profile pushes are batched so a burst of changes sends one update.
	task.spawn(function()
		while true do
			task.wait(0.25)
			for player in dirty do
				dirty[player] = nil
				local profile = profiles[player]
				if profile and player.Parent then
					updateLeaderstats(player, profile)
					player:SetAttribute("Level", profile.Level)
					Remotes.event("ProfileUpdated"):FireClient(player, stripForClient(profile))
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				saveProfile(player, true)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

function PlayerDataService.get(player: Player): Profile?
	return profiles[player]
end

function PlayerDataService.isTemporary(player: Player): boolean
	return noSave[player] == true
end

-- Call after changing a profile: sends the client a fresh copy (batched).
function PlayerDataService.push(player: Player)
	dirty[player] = true
end

function PlayerDataService.onLoaded(listener: (player: Player, profile: Profile) -> ())
	table.insert(loadedListeners, listener)
	for player, profile in profiles do
		task.spawn(listener, player, profile)
	end
end

function PlayerDataService.setupFor(player: Player, bikeId: string): BikeStats.BikeSetup?
	local profile = profiles[player]
	if not profile or not profile.OwnedBikes[bikeId] then
		return nil
	end
	profile.BikeSetups[bikeId] = profile.BikeSetups[bikeId] or BikeStats.defaultSetup(bikeId)
	return profile.BikeSetups[bikeId]
end

return PlayerDataService
