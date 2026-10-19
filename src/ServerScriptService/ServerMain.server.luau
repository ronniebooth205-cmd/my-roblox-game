-- ServerScriptService > ServerMain (Script)
-- Server entry point for SURRON LIFE: WHEELIE CITY. Creates the remotes, then initialises and
-- starts every service in dependency order. Services get a shared table so they can reach each
-- other without circular requires.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
Remotes.init()

local Services = script.Parent:WaitForChild("Services")

local ORDER = {
	"PlayerDataService",
	"EconomyService",
	"MapService",
	"BikeService",
	"TrickService",
	"ChallengeService",
	"GarageService",
	"MultiplayerService",
}

local registry = {}
for _, name in ORDER do
	registry[name] = require(Services:WaitForChild(name))
end

for _, name in ORDER do
	local ok, err = pcall(registry[name].init, registry)
	if not ok then
		warn(string.format("[ServerMain] %s.init failed: %s", name, tostring(err)))
	end
end
for _, name in ORDER do
	local ok, err = pcall(registry[name].start)
	if not ok then
		warn(string.format("[ServerMain] %s.start failed: %s", name, tostring(err)))
	end
end

print("[ServerMain] SURRON LIFE: WHEELIE CITY server ready")
