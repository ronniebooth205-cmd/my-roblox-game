--!strict
-- StarterPlayer > StarterPlayerScripts > Controllers > ClientState (ModuleScript)
-- The client's read-only copy of its profile (sent by the server) and its settings, with
-- change listeners for the UI. Changing a setting saves it to the server (validated there).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Utilities = require(ReplicatedStorage.Shared.Utilities)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ClientState = {}

ClientState.profile = nil :: { [string]: any }?
ClientState.settings = Utilities.deepCopy(GameConfig.DefaultSettings) :: { [string]: any }

local profileListeners: { (profile: { [string]: any }) -> () } = {}
local settingsListeners: { (settings: { [string]: any }) -> () } = {}
local saveQueued = false

local function setProfile(profile: { [string]: any }?)
	if type(profile) ~= "table" then
		return
	end
	local first = ClientState.profile == nil
	ClientState.profile = profile
	if first and type(profile.Settings) == "table" then
		for key, value in profile.Settings do
			ClientState.settings[key] = value
		end
		for _, listener in settingsListeners do
			task.spawn(listener, ClientState.settings)
		end
	end
	for _, listener in profileListeners do
		task.spawn(listener, profile)
	end
end

function ClientState.init()
	Remotes.event("ProfileUpdated").OnClientEvent:Connect(setProfile)
	task.spawn(function()
		while not ClientState.profile do
			local ok, profile = pcall(function()
				return Remotes.func("GetProfile"):InvokeServer()
			end)
			if ok and profile then
				setProfile(profile)
			else
				task.wait(1)
			end
		end
	end)
end

function ClientState.onProfile(listener: (profile: { [string]: any }) -> ())
	table.insert(profileListeners, listener)
	if ClientState.profile then
		task.spawn(listener, ClientState.profile)
	end
end

function ClientState.onSettings(listener: (settings: { [string]: any }) -> ())
	table.insert(settingsListeners, listener)
	task.spawn(listener, ClientState.settings)
end

function ClientState.setSetting(key: string, value: any)
	ClientState.settings[key] = value
	for _, listener in settingsListeners do
		task.spawn(listener, ClientState.settings)
	end
	-- Batch rapid slider changes into one save.
	if not saveQueued then
		saveQueued = true
		task.delay(1, function()
			saveQueued = false
			Remotes.event("Settings"):FireServer(ClientState.settings)
		end)
	end
end

function ClientState.markTutorialDone()
	local payload = table.clone(ClientState.settings)
	payload.TutorialDone = true
	Remotes.event("Settings"):FireServer(payload)
end

function ClientState.ownsCosmetic(key: string, price: number, level: number): boolean
	local profile = ClientState.profile
	if not profile or profile.Level < level then
		return false
	end
	return price <= 0 or profile.OwnedCosmetics[key] == true
end

return ClientState
