-- Shared single-player/co-op helpers for Campaign Reimagined Lua missions.
--
-- Campaign contract:
--   * 1-4 human players use teams 1-4.
--   * team 1 is always the campaign leader and intended network host.
--   * campaign enemies must use team 5 or higher.
--   * a migrated network host must NOT automatically inherit campaign authority.
--
-- Multiplayer behavior follows Docs/BZR_LUA_AGENT_REFERENCE.md and the
-- project-observed notes in Text/ScriptingGuide.txt. Keep network messages
-- compact: stock Lua Send() only uses the first character of the type string
-- and has a small payload budget.
local CRCoop = {}

local PROTOCOL_VERSION = 1
local HANDLE_MESSAGE = "H"
local SYNC_REQUEST_MESSAGE = "Q"
local SYNC_ACK_MESSAGE = "K"

local DEFAULT_LEADER_TEAM = 1
local DEFAULT_HUMAN_TEAM_MIN = 1
local DEFAULT_HUMAN_TEAM_MAX = 4

local players = {}
local localPlayerId = nil
local getLocalPlayerId = nil
local leaderTeam = DEFAULT_LEADER_TEAM
local humanTeamMin = DEFAULT_HUMAN_TEAM_MIN
local humanTeamMax = DEFAULT_HUMAN_TEAM_MAX
local handleBroadcastInterval = 0.5
local handshakeRetryInterval = 1.0
local nextHandleBroadcast = 0.0
local nextHandshakeRequest = 0.0
local syncAcknowledged = false
local missionStarted = false
local leaderDeparted = false

local function IsNetworkGame()
    return type(IsNetGame) == "function" and IsNetGame()
end

local function IsUsableHandle(h)
    return h ~= nil and (type(IsValid) ~= "function" or IsValid(h))
end

local function IsHumanTeam(team)
    return type(team) == "number" and team >= humanTeamMin and team <= humanTeamMax
end

local function RegisterPlayer(id, name, team)
    if id == nil then
        return nil
    end

    local player = players[id]
    if player == nil then
        player = {
            id = id,
            ready = false,
            lateJoin = missionStarted and true or false,
        }
        players[id] = player
    end

    if name ~= nil then
        player.name = name
    end
    if team ~= nil then
        player.team = team
    end
    return player
end

local function ResolveLocalPlayerId()
    if localPlayerId ~= nil then
        return localPlayerId
    end

    if type(getLocalPlayerId) == "function" then
        local ok, value = pcall(getLocalPlayerId)
        if ok and value ~= nil then
            localPlayerId = value
        end
    end

    return localPlayerId
end

local function RefreshLocalHandle()
    if type(GetPlayerHandle) ~= "function" then
        return nil
    end

    local h = GetPlayerHandle()
    local id = ResolveLocalPlayerId()
    if id ~= nil then
        local player = RegisterPlayer(id)
        player.handle = h
        if player.team == nil and IsUsableHandle(h) and type(GetTeamNum) == "function" then
            player.team = GetTeamNum(h)
        end
    end

    return h
end

local function GetLocalPlayerRecord()
    local id = ResolveLocalPlayerId()
    if id == nil then
        return nil
    end
    return players[id]
end

local function FindLeaderId()
    for id, player in pairs(players) do
        if player.team == leaderTeam then
            return id
        end
    end
    return nil
end

function CRCoop.Initialize(options)
    options = options or {}

    if type(options.getLocalPlayerId) == "function" then
        getLocalPlayerId = options.getLocalPlayerId
        localPlayerId = nil
    end

    if type(options.leaderTeam) == "number" then
        leaderTeam = options.leaderTeam
    end
    if type(options.humanTeamMin) == "number" then
        humanTeamMin = options.humanTeamMin
    end
    if type(options.humanTeamMax) == "number" then
        humanTeamMax = options.humanTeamMax
    end

    if type(options.handleBroadcastInterval) == "number" and options.handleBroadcastInterval > 0 then
        handleBroadcastInterval = options.handleBroadcastInterval
    end
    if type(options.handshakeRetryInterval) == "number" and options.handshakeRetryInterval > 0 then
        handshakeRetryInterval = options.handshakeRetryInterval
    end

    nextHandleBroadcast = 0.0
    nextHandshakeRequest = 0.0
    syncAcknowledged = false
    leaderDeparted = false
    RefreshLocalHandle()
end

function CRCoop.IsNetworkGame()
    return IsNetworkGame()
end

function CRCoop.IsHumanTeam(team)
    return IsHumanTeam(team)
end

function CRCoop.GetLeaderTeam()
    return leaderTeam
end

function CRCoop.GetHumanTeamRange()
    return humanTeamMin, humanTeamMax
end

function CRCoop.GetLocalPlayerId()
    return ResolveLocalPlayerId()
end

function CRCoop.GetLocalTeam()
    local player = GetLocalPlayerRecord()
    if player and player.team ~= nil then
        return player.team
    end

    local h = RefreshLocalHandle()
    if IsUsableHandle(h) and type(GetTeamNum) == "function" then
        return GetTeamNum(h)
    end
    return nil
end

function CRCoop.IsCampaignLeader()
    if not IsNetworkGame() then
        return true
    end

    -- Deliberately require both the campaign leader slot and current network
    -- hosting. If Redux migrates the network host after Player 1 leaves, the
    -- promoted peer must not silently inherit campaign simulation authority.
    if CRCoop.GetLocalTeam() ~= leaderTeam then
        return false
    end
    return type(IsHosting) == "function" and IsHosting()
end

function CRCoop.IsAuthority()
    return CRCoop.IsCampaignLeader()
end

function CRCoop.HasLeader()
    if not IsNetworkGame() then
        return true
    end

    if FindLeaderId() ~= nil then
        return true
    end

    return CRCoop.GetLocalTeam() == leaderTeam
end

function CRCoop.HasLeaderDeparted()
    return leaderDeparted
end

function CRCoop.MarkMissionStarted()
    missionStarted = true
    for _, player in pairs(players) do
        player.lateJoin = false
    end
end

function CRCoop.HasLateJoiners()
    for _, player in pairs(players) do
        if player.lateJoin then
            return true
        end
    end
    return false
end

function CRCoop.CreatePlayer(id, name, team)
    RegisterPlayer(id, name, team)
    RefreshLocalHandle()
end

function CRCoop.AddPlayer(id, name, team)
    RegisterPlayer(id, name, team)
    RefreshLocalHandle()
end

function CRCoop.DeletePlayer(id)
    if id == nil then
        return
    end

    local player = players[id]
    if player and player.team == leaderTeam then
        leaderDeparted = true
    end
    players[id] = nil
end

function CRCoop.ApplyCoopAlliances(enemyTeam)
    if type(Ally) ~= "function" then
        return false
    end

    -- Apply both directions because team-alliance state can become asymmetric.
    for a = humanTeamMin, humanTeamMax do
        for b = humanTeamMin, humanTeamMax do
            if a ~= b then
                pcall(Ally, a, b)
            end
        end
    end

    if type(enemyTeam) == "number" and type(UnAlly) == "function" then
        for team = humanTeamMin, humanTeamMax do
            pcall(UnAlly, team, enemyTeam)
            pcall(UnAlly, enemyTeam, team)
        end
    end

    return true
end

function CRCoop.Update()
    local localHandle = RefreshLocalHandle()

    if not IsNetworkGame() or not IsUsableHandle(localHandle) then
        return
    end

    local now = type(GetTime) == "function" and GetTime() or 0.0

    if now >= nextHandleBroadcast then
        nextHandleBroadcast = now + handleBroadcastInterval
        if type(Send) == "function" then
            Send(0, HANDLE_MESSAGE, localHandle)
        end
    end

    if not CRCoop.IsCampaignLeader() and not syncAcknowledged and now >= nextHandshakeRequest then
        nextHandshakeRequest = now + handshakeRetryInterval
        if type(Send) == "function" then
            -- Broadcast the request because a joining client may not yet know
            -- the leader's current network ID. Only the campaign leader answers.
            Send(0, SYNC_REQUEST_MESSAGE, localHandle, CRCoop.GetLocalTeam(), PROTOCOL_VERSION)
        end
    end
end

function CRCoop.Receive(from, kind, ...)
    if kind == HANDLE_MESSAGE then
        local h = ...
        local player = RegisterPlayer(from)
        player.handle = h
        return true
    end

    if kind == SYNC_REQUEST_MESSAGE then
        local h, team, version = ...
        local player = RegisterPlayer(from, nil, team)
        player.handle = h
        player.protocolVersion = version

        if CRCoop.IsCampaignLeader() and IsHumanTeam(player.team) and version == PROTOCOL_VERSION then
            player.ready = true
            if type(Send) == "function" then
                Send(from, SYNC_ACK_MESSAGE, PROTOCOL_VERSION)
            end
        end
        return true
    end

    if kind == SYNC_ACK_MESSAGE then
        local version = ...
        local leaderId = FindLeaderId()
        local leader = players[from]
        if version == PROTOCOL_VERSION and
            ((leaderId ~= nil and from == leaderId) or (leader and leader.team == leaderTeam)) then
            syncAcknowledged = true
        end
        return true
    end

    return false
end

function CRCoop.IsHumanCraft(h)
    if h == nil then
        return false
    end

    local localHandle = RefreshLocalHandle()
    if localHandle ~= nil and h == localHandle then
        return true
    end

    for _, player in pairs(players) do
        if player.handle ~= nil and h == player.handle then
            return true
        end
    end

    return false
end

function CRCoop.HasAllPlayerHandles()
    if not IsNetworkGame() then
        return IsUsableHandle(RefreshLocalHandle())
    end

    local count = 0
    for id, player in pairs(players) do
        if IsHumanTeam(player.team) then
            count = count + 1
            if id == ResolveLocalPlayerId() then
                player.handle = RefreshLocalHandle()
            end
            if not IsUsableHandle(player.handle) then
                return false
            end
        end
    end

    return count > 0
end

function CRCoop.IsSessionReady()
    if not IsNetworkGame() then
        return true
    end

    if not CRCoop.HasAllPlayerHandles() then
        return false
    end

    if CRCoop.IsCampaignLeader() then
        for id, player in pairs(players) do
            if IsHumanTeam(player.team) and id ~= ResolveLocalPlayerId() and not player.ready then
                return false
            end
        end
        return true
    end

    return syncAcknowledged
end

function CRCoop.HasUnsupportedPlayerTeam()
    for _, player in pairs(players) do
        if player.team ~= nil and not IsHumanTeam(player.team) then
            return true
        end
    end
    return false
end

function CRCoop.ForEachHumanTeam(fn)
    if type(fn) ~= "function" then
        return 0
    end

    local seen = {}
    local count = 0

    if not IsNetworkGame() then
        fn(leaderTeam)
        return 1
    end

    for _, player in pairs(players) do
        if IsHumanTeam(player.team) and not seen[player.team] then
            seen[player.team] = true
            count = count + 1
            fn(player.team)
        end
    end
    return count
end

function CRCoop.ForEachPlayerHandle(fn)
    if type(fn) ~= "function" then
        return 0
    end

    if not IsNetworkGame() then
        local h = RefreshLocalHandle()
        if IsUsableHandle(h) then
            fn(h, nil, true)
            return 1
        end
        return 0
    end

    local localId = ResolveLocalPlayerId()
    local count = 0
    local seen = {}

    for id, player in pairs(players) do
        if IsHumanTeam(player.team) then
            local h = player.handle
            if id == localId then
                h = RefreshLocalHandle()
                player.handle = h
            end

            if IsUsableHandle(h) and not seen[h] then
                seen[h] = true
                count = count + 1
                fn(h, id, id == localId)
            end
        end
    end

    return count
end

function CRCoop.AllPlayersSatisfy(predicate)
    if type(predicate) ~= "function" then
        return false
    end

    if IsNetworkGame() and not CRCoop.HasAllPlayerHandles() then
        return false
    end

    local allMatch = true
    local count = CRCoop.ForEachPlayerHandle(function(h, id, isLocal)
        if allMatch and not predicate(h, id, isLocal) then
            allMatch = false
        end
    end)

    return count > 0 and allMatch
end

function CRCoop.AnyPlayerSatisfies(predicate)
    if type(predicate) ~= "function" then
        return false
    end

    local matched = false
    CRCoop.ForEachPlayerHandle(function(h, id, isLocal)
        if not matched and predicate(h, id, isLocal) then
            matched = true
        end
    end)
    return matched
end

function CRCoop.AllPlayersNear(target, distance)
    if target == nil or type(distance) ~= "number" then
        return false
    end

    return CRCoop.AllPlayersSatisfy(function(h)
        return GetDistance(h, target) < distance
    end)
end

function CRCoop.GetPlayers()
    return players
end

return CRCoop
