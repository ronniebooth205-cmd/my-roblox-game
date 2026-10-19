--!strict
-- ServerScriptService > Services > MultiplayerService (ModuleScript)
-- Social features: the wheelie leaderboard at the meet (this server + all-time via an
-- OrderedDataStore) and rideout groups (create, invite, accept, leave, kick, pick a meeting
-- point). Group membership is published as a player attribute so every client can draw group
-- markers; full group details only go to members.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local Utilities = require(ReplicatedStorage.Shared.Utilities)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerDataService = require(script.Parent.PlayerDataService)

local MultiplayerService = {}

local MAX_GROUP = 6
local INVITE_TTL = 60

type Group = { Id: string, Leader: Player, Members: { Player }, Meet: string? }

local groups: { [string]: Group } = {}
local playerGroup: { [Player]: string } = {}
local invites: { [Player]: { GroupId: string, Expires: number } } = {}
local limiter = Utilities.newRateLimiter(10, 5)
local nextGroupId = 0

local orderedStore: OrderedDataStore? = nil
local pendingBest: { [number]: number } = {}
local globalTop: { { Name: string, Metres: number } } = {}
local nameCache: { [number]: string } = {}

------------------------------------------------------------------------ leaderboard

local function nameFor(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	nameCache[userId] = if ok and type(name) == "string" then name else "Rider"
	return nameCache[userId]
end

local function boardRows(boardName: string): { TextLabel }
	local map = Workspace:FindFirstChild("Map")
	local board = map and map:FindFirstChild(boardName, true)
	local gui = board and board:FindFirstChildWhichIsA("SurfaceGui")
	local list = gui and gui:FindFirstChild("Rows", true)
	local rows = {}
	if list then
		for i = 1, 10 do
			local row = list:FindFirstChild("Row" .. i)
			if row and row:IsA("TextLabel") then
				rows[i] = row
			end
		end
	end
	return rows
end

local function refreshBoards()
	local serverEntries = {}
	for _, player in Players:GetPlayers() do
		local profile = PlayerDataService.get(player)
		if profile and profile.Stats.LongestWheelie > 0 then
			table.insert(serverEntries, { Name = player.DisplayName, Metres = profile.Stats.LongestWheelie })
		end
	end
	table.sort(serverEntries, function(a, b)
		return a.Metres > b.Metres
	end)
	local function fill(rows: { TextLabel }, entries: { { Name: string, Metres: number } })
		for i = 1, 10 do
			local row = rows[i]
			if row then
				local entry = entries[i]
				row.Text = if entry then string.format("%d. %s  —  %s", i, entry.Name, Utilities.formatDistance(entry.Metres)) else ""
			end
		end
	end
	fill(boardRows("ServerBoard"), serverEntries)
	fill(boardRows("GlobalBoard"), globalTop)
end

local function refreshGlobal()
	local store = orderedStore
	if not store then
		return
	end
	for userId, metres in pendingBest do
		pendingBest[userId] = nil
		pcall(function()
			store:UpdateAsync("u_" .. userId, function(old: number?)
				local value = math.floor(metres * 10)
				if old and old >= value then
					return nil
				end
				return value
			end)
		end)
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, 10)
	end)
	if ok and pages then
		local top = {}
		for _, entry in (pages :: DataStorePages):GetCurrentPage() do
			local userId = tonumber((entry.key :: string):sub(3))
			if userId then
				table.insert(top, { Name = nameFor(userId), Metres = (entry.value :: number) / 10 })
			end
		end
		globalTop = top
	end
	refreshBoards()
end

function MultiplayerService.onWheelie(player: Player, metres: number, isBest: boolean)
	if isBest then
		pendingBest[player.UserId] = metres
		refreshBoards()
	end
end

------------------------------------------------------------------------ rideouts

local function groupPayload(group: Group)
	local members = {}
	for _, member in group.Members do
		table.insert(members, { UserId = member.UserId, Name = member.DisplayName })
	end
	return { Id = group.Id, Leader = group.Leader.UserId, Members = members, Meet = group.Meet }
end

local function broadcast(group: Group)
	local payload = groupPayload(group)
	for _, member in group.Members do
		Remotes.event("Rideout"):FireClient(member, "State", payload)
	end
end

local function leave(player: Player)
	local id = playerGroup[player]
	if not id then
		return
	end
	playerGroup[player] = nil
	player:SetAttribute("RideoutId", nil)
	Remotes.event("Rideout"):FireClient(player, "State", nil)
	local group = groups[id]
	if not group then
		return
	end
	local index = table.find(group.Members, player)
	if index then
		table.remove(group.Members, index)
	end
	if #group.Members == 0 then
		groups[id] = nil
		return
	end
	if group.Leader == player then
		group.Leader = group.Members[1]
	end
	broadcast(group)
end

local function onRideout(player: Player, action: any, arg: any)
	if type(action) ~= "string" or not limiter:check(player) then
		return
	end
	local groupId = playerGroup[player]
	local group = groupId and groups[groupId]
	if action == "Create" then
		if group then
			return
		end
		nextGroupId += 1
		local id = "G" .. nextGroupId
		groups[id] = { Id = id, Leader = player, Members = { player }, Meet = nil }
		playerGroup[player] = id
		player:SetAttribute("RideoutId", id)
		broadcast(groups[id])
	elseif action == "Invite" then
		local target = type(arg) == "number" and Players:GetPlayerByUserId(arg)
		if not group or not target or target == player or playerGroup[target] or #group.Members >= MAX_GROUP then
			return
		end
		invites[target] = { GroupId = group.Id, Expires = os.clock() + INVITE_TTL }
		Remotes.event("Rideout"):FireClient(target, "Invite", { GroupId = group.Id, From = player.DisplayName })
	elseif action == "Accept" then
		local invite = invites[player]
		invites[player] = nil
		local target = invite and groups[invite.GroupId]
		if not invite or not target or os.clock() > invite.Expires or #target.Members >= MAX_GROUP then
			Remotes.event("Notify"):FireClient(player, { Text = "That invite has expired.", Kind = "Warning" })
			return
		end
		leave(player)
		table.insert(target.Members, player)
		playerGroup[player] = target.Id
		player:SetAttribute("RideoutId", target.Id)
		broadcast(target)
	elseif action == "Decline" then
		invites[player] = nil
	elseif action == "Leave" then
		leave(player)
	elseif action == "Kick" then
		local target = type(arg) == "number" and Players:GetPlayerByUserId(arg)
		if group and group.Leader == player and target and playerGroup[target] == group.Id and target ~= player then
			leave(target)
		end
	elseif action == "SetMeet" then
		if group and group.Leader == player and type(arg) == "string" then
			for _, point in MapLayout.MeetPoints do
				if point.Id == arg then
					group.Meet = arg
					broadcast(group)
				end
			end
		end
	end
end

------------------------------------------------------------------------ lifecycle

function MultiplayerService.init()
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(GameConfig.Data.LeaderboardStore)
	end)
	if ok then
		orderedStore = store
	end
	Remotes.event("Rideout").OnServerEvent:Connect(onRideout)
end

function MultiplayerService.start()
	Players.PlayerRemoving:Connect(function(player)
		leave(player)
		invites[player] = nil
		limiter:clear(player)
		task.defer(refreshBoards)
	end)
	PlayerDataService.onLoaded(function()
		refreshBoards()
	end)
	task.spawn(function()
		task.wait(5)
		while true do
			refreshGlobal()
			task.wait(GameConfig.Data.LeaderboardRefresh)
		end
	end)
end

return MultiplayerService
