--!strict
-- ReplicatedStorage > Shared > BikeStats (ModuleScript)
-- Works out a bike's final handling numbers from its definition, the player's performance
-- upgrades and controller tuning. The client uses the result to drive the physics; the server
-- uses the same function to sanity-check wheelie submissions (e.g. top speed), so both sides
-- always agree on what a bike can do.

local BikeDefinitions = require(script.Parent.BikeDefinitions)
local CustomisationConfig = require(script.Parent.CustomisationConfig)
local PhysicsConfig = require(script.Parent.PhysicsConfig)

local BikeStats = {}

export type BikeSetup = {
	Colours: { [string]: string },
	Upgrades: { [string]: number },
	Options: { [string]: string },
	Tuning: { [string]: number },
	Plate: string,
}

export type Stats = {
	Handling: { [string]: number },
	Geometry: { [string]: number },
	BatterySeconds: number,
	TyreType: string,
	Tuning: { [string]: number },
}

function BikeStats.defaultSetup(bikeId: string): BikeSetup
	local def = BikeDefinitions.get(bikeId)
	local colours = {}
	for _, slot in CustomisationConfig.PaintSlots do
		colours[slot.Id] = (def and def.DefaultColours[slot.Id]) or slot.Default
	end
	local options = {}
	for optionId, option in CustomisationConfig.Options :: any do
		options[optionId] = option.Choices[1].Id
	end
	local upgrades = {}
	for _, id in CustomisationConfig.UpgradeOrder do
		upgrades[id] = 0
	end
	local tuning = {}
	for id, t in CustomisationConfig.Tuning :: any do
		tuning[id] = t.Default
	end
	return {
		Colours = colours,
		Upgrades = upgrades,
		Options = options,
		Tuning = tuning,
		Plate = CustomisationConfig.Plate.Default,
	}
end

-- Allowed [min, max] for a tuning slider at the given controller upgrade level.
function BikeStats.tuningRange(tuningId: string, controllerLevel: number): (number, number)
	local t = (CustomisationConfig.Tuning :: any)[tuningId]
	local range = t.Ranges[math.clamp(controllerLevel + 1, 1, #t.Ranges)]
	return range[1], range[2]
end

function BikeStats.compute(bikeId: string, setup: BikeSetup?): Stats
	local def = BikeDefinitions.get(bikeId) or BikeDefinitions.get(BikeDefinitions.StarterBike)
	assert(def, "missing starter bike definition")
	local s = setup or BikeStats.defaultSetup(bikeId)

	local handling: { [string]: number } = table.clone(PhysicsConfig.Handling)
	for k, v in def.Handling do
		handling[k] = v
	end
	local geometry: { [string]: number } = {}
	for k, v in PhysicsConfig.Geometry :: any do
		if type(v) == "number" then
			geometry[k] = v
		end
	end
	for k, v in def.Geometry do
		geometry[k] = v
	end
	local battery = def.BatterySeconds

	-- Performance upgrades: each level adds PerLevel × base value.
	for upgradeId, upgrade in CustomisationConfig.Upgrades :: any do
		local level = math.clamp(math.floor(s.Upgrades[upgradeId] or 0), 0, def.MaxUpgradeLevel)
		if level > 0 then
			for stat, perLevel in upgrade.PerLevel do
				if stat == "BatterySeconds" then
					battery *= 1 + perLevel * level
				elseif handling[stat] then
					handling[stat] *= 1 + perLevel * level
				end
			end
		end
	end

	-- Controller tuning, clamped to what the controller upgrade allows.
	local controllerLevel = math.clamp(s.Upgrades.Controller or 0, 0, def.MaxUpgradeLevel)
	local tuning: { [string]: number } = {}
	for tuningId, t in CustomisationConfig.Tuning :: any do
		local lo, hi = BikeStats.tuningRange(tuningId, controllerLevel)
		tuning[tuningId] = math.clamp(s.Tuning[tuningId] or t.Default, lo, hi)
	end
	handling.ThrottleResponse = handling.ThrottleResponse / tuning.ThrottleResponse
	handling.MaxAccel *= tuning.TorqueDelivery
	handling.WheelieLift *= 0.85 + 0.15 * tuning.TorqueDelivery
	handling.RegenDecel *= 0.4 + 1.2 * tuning.Regen
	handling.TopSpeedLimited = handling.TopSpeed * tuning.SpeedLimiter
	handling.BalanceAssist *= tuning.WheelieAssist

	local wheelScale = CustomisationConfig.WheelSizes[s.Options.WheelSize or "Stock"] or 1
	geometry.WheelRadius *= wheelScale

	return {
		Handling = handling,
		Geometry = geometry,
		BatterySeconds = battery,
		TyreType = s.Options.TyreType or "Street",
		Tuning = tuning,
	}
end

-- Simple 0..1 ratings for the garage/shop stat bars.
function BikeStats.ratings(stats: Stats): { [string]: number }
	local h = stats.Handling
	return {
		Speed = math.clamp(h.TopSpeed / 100, 0, 1),
		Acceleration = math.clamp(h.MaxAccel / 65, 0, 1),
		Wheelie = math.clamp((h.WheelieLift - 0.9) / 1.0, 0, 1),
		Brakes = math.clamp(h.BrakeDecel / 85, 0, 1),
		Handling = math.clamp(h.Grip / 1.4, 0, 1),
		Stability = math.clamp(h.BalanceAssist / 0.7, 0, 1),
	}
end

return BikeStats
