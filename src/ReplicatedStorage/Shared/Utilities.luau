--!strict
-- ReplicatedStorage > Shared > Utilities (ModuleScript)
-- Small maths, formatting and table helpers shared by the server and the client.

local GameConfig = require(script.Parent.GameConfig)

local Utilities = {}

function Utilities.clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

function Utilities.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Frame-rate independent smoothing: moves `current` towards `target`, covering about 63% of the
-- gap every `timeConstant` seconds whatever the frame rate.
function Utilities.smooth(current: number, target: number, timeConstant: number, dt: number): number
	if timeConstant <= 0 then
		return target
	end
	return current + (target - current) * (1 - math.exp(-dt / timeConstant))
end

function Utilities.moveTowards(current: number, target: number, maxDelta: number): number
	if math.abs(target - current) <= maxDelta then
		return target
	end
	return current + math.sign(target - current) * maxDelta
end

function Utilities.studsToMetres(studs: number): number
	return studs * GameConfig.Units.MetresPerStud
end

function Utilities.studsPerSecondToMph(speed: number): number
	return speed * GameConfig.Units.MetresPerStud * 2.236936
end

function Utilities.studsPerSecondToKmh(speed: number): number
	return speed * GameConfig.Units.MetresPerStud * 3.6
end

function Utilities.formatNumber(n: number): string
	local whole = math.floor(math.abs(n) + 0.5)
	local text = tostring(whole)
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return (n < 0 and "-" or "") .. formatted
end

function Utilities.formatCash(n: number): string
	return "£" .. Utilities.formatNumber(n)
end

function Utilities.formatDistance(metres: number): string
	if metres >= 1000 then
		return string.format("%.2f km", metres / 1000)
	end
	return string.format("%d m", math.floor(metres))
end

function Utilities.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[k] = Utilities.deepCopy(v)
	end
	return copy :: any
end

-- Fills in any keys missing from `target` with copies from `defaults`, recursively. Used to
-- upgrade saved profiles and settings without throwing away what the player already has.
function Utilities.reconcile(target: { [any]: any }, defaults: { [any]: any })
	for k, v in defaults do
		if target[k] == nil then
			target[k] = Utilities.deepCopy(v)
		elseif type(v) == "table" and type(target[k]) == "table" then
			Utilities.reconcile(target[k], v)
		end
	end
end

-- Signed pitch of a CFrame in degrees relative to a ground normal (positive = nose up).
function Utilities.pitchDegrees(cf: CFrame, normal: Vector3?): number
	local n = normal or Vector3.yAxis
	return math.deg(math.asin(math.clamp(cf.LookVector:Dot(n), -1, 1)))
end

-- Signed roll of a CFrame in degrees (positive = leaning left).
function Utilities.rollDegrees(cf: CFrame): number
	return math.deg(math.asin(math.clamp(cf.RightVector.Y, -1, 1)))
end

-- Per-key rate limiter for remotes: allows `count` calls per `window` seconds.
export type RateLimiter = {
	check: (self: RateLimiter, key: any) -> boolean,
	clear: (self: RateLimiter, key: any) -> (),
}

function Utilities.newRateLimiter(count: number, window: number): RateLimiter
	local buckets: { [any]: { number } } = {}
	local limiter = {}
	function limiter.check(_self, key: any): boolean
		local now = os.clock()
		local bucket = buckets[key]
		if not bucket then
			bucket = {}
			buckets[key] = bucket
		end
		while bucket[1] and now - bucket[1] > window do
			table.remove(bucket, 1)
		end
		if #bucket >= count then
			return false
		end
		table.insert(bucket, now)
		return true
	end
	function limiter.clear(_self, key: any)
		buckets[key] = nil
	end
	return limiter :: any
end

-- Cleans up connections, instances and functions in one go so controllers don't leak.
export type Janitor = {
	add: <T>(self: Janitor, item: T) -> T,
	cleanup: (self: Janitor) -> (),
}

function Utilities.newJanitor(): Janitor
	local items: { any } = {}
	local janitor = {}
	function janitor.add<T>(_self, item: T): T
		table.insert(items, item)
		return item
	end
	function janitor.cleanup(_self)
		for i = #items, 1, -1 do
			local item = items[i]
			items[i] = nil
			local kind = typeof(item)
			if kind == "RBXScriptConnection" then
				(item :: RBXScriptConnection):Disconnect()
			elseif kind == "Instance" then
				(item :: Instance):Destroy()
			elseif kind == "function" then
				(item :: () -> ())()
			end
		end
	end
	return janitor :: any
end

return Utilities
