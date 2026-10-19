--!strict
-- ReplicatedStorage > Shared > Remotes (ModuleScript)
-- The complete list of remotes. The server creates them once (Remotes.init); both sides fetch
-- them by name. Every client-to-server remote is validated and rate limited by the service
-- that handles it, so adding a remote here never trusts the client by itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local DEFINITIONS: { [string]: string } = {
	-- client -> server: ("Spawn" | "Despawn" | "Mount" | "Dismount" | "Recover" | "Crash" | "Headlight", ...)
	BikeAction = "RemoteEvent",
	-- client -> server, ~10 Hz: steering/throttle/lean/pose for other players' visuals and audio
	BikeState = "UnreliableRemoteEvent",
	-- client -> server: ("Start") / ("End", summary)
	Wheelie = "RemoteEvent",
	-- client -> server: settings table to save
	Settings = "RemoteEvent",
	-- both ways: rideout group actions and updates
	Rideout = "RemoteEvent",
	-- server -> client: the player's profile (read-only copy)
	ProfileUpdated = "RemoteEvent",
	-- server -> client: { Text, Kind, Cash?, Xp? } toasts and reward popups
	Notify = "RemoteEvent",
	-- server -> client: the bike model that was just spawned for you
	BikeSpawned = "RemoteEvent",
	-- client -> server -> result: garage purchases and setup changes
	Garage = "RemoteFunction",
	-- client -> server -> profile
	GetProfile = "RemoteFunction",
	-- client -> server -> result
	RedeemCode = "RemoteFunction",
}

local FOLDER_NAME = "Remotes"

function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init is server-only")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for name, className in DEFINITIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	end
end

local function folder(): Instance
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

function Remotes.event(name: string): RemoteEvent
	assert(DEFINITIONS[name] == "RemoteEvent", "unknown RemoteEvent " .. name)
	return folder():WaitForChild(name) :: RemoteEvent
end

function Remotes.unreliable(name: string): UnreliableRemoteEvent
	assert(DEFINITIONS[name] == "UnreliableRemoteEvent", "unknown UnreliableRemoteEvent " .. name)
	return folder():WaitForChild(name) :: UnreliableRemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	assert(DEFINITIONS[name] == "RemoteFunction", "unknown RemoteFunction " .. name)
	return folder():WaitForChild(name) :: RemoteFunction
end

return Remotes
