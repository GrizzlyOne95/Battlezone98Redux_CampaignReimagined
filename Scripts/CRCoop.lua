-- Shared single-player/co-op helpers for Campaign Reimagined Lua missions.
--
-- Multiplayer behavior here follows Docs/BZR_LUA_AGENT_REFERENCE.md and the
-- project-observed notes in Text/ScriptingGuide.txt. Keep network messages
-- compact: stock Lua Send() only uses the first character of the type string
-- and has a small payload budget.
local CRCoop = {}

local HANDLE_MESSAGE = "H"
local players = {}
local localPlayerId = nil
local getLocalPlayerId = nil
local handleBroadcastInterval = 0.5
local nextHandleBroadcast = 0.0

local function IsNetworkGame()
    return type(IsNetGame) == "function" and IsNetGame()
end

local function IsUsableHandle(h)
    return h ~= nil and (type(IsValid) ~= "function" or IsValid(h))
end

local function RegisterPlayer(id, name, team)
    if id == nil then
        return
    end

    local player = players[id]
    if player == nil then
        player = { id = id }
        players[id] = player
    end

    player.name = name
    player.team = team
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
        RegisterPlayer(id)
        players[id].handle = h
    end

    return h
end

function CRCoop.Initialize(options)
    options = options or {}

    if type(options.getLocalPlayerId) == "function" then
        getLocalPlayerId = options.getLocalPlayerId
        localPlayerId = nil
    end

    if type(options.handleBroadcastInterval) == "number" and options.handleBroadcastInterval > 0 then
        handleBroadcastInterval = options.handleBroadcastInterval
    end

    nextHandleBroadcast = 0.0
    RefreshLocalHandle()
end

function CRCoop.IsNetworkGame()
    return IsNetworkGame()
end

function CRCoop.IsAuthority()
    return not IsNetworkGame() or (type(IsHosting) == "function" and IsHosting())
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
    if id ~= nil then
        players[id] = nil
    end
end

function CRCoop.Update()
    local localHandle = RefreshLocalHandle()

    if not IsNetworkGame() or not IsUsableHandle(localHandle) then
        return
    end

    local now = type(GetTime) == "function" and GetTime() or 0.0
    if now < nextHandleBroadcast then
        return
    end

    nextHandleBroadcast = now + handleBroadcastInterval

    if type(Send) == "function" then
        Send(0, HANDLE_MESSAGE, localHandle)
    end
end

function CRCoop.Receive(from, kind, ...)
    if kind ~= HANDLE_MESSAGE then
        return false
    end

    local h = ...
    RegisterPlayer(from)
    players[from].handle = h
    return true
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
        count = count + 1
        if id == ResolveLocalPlayerId() then
            player.handle = RefreshLocalHandle()
        end
        if not IsUsableHandle(player.handle) then
            return false
        end
    end

    -- In a net game, an empty registry means the player lifecycle callbacks
    -- have not populated yet. Treat that as incomplete rather than allowing a
    -- mission transition based only on the local player.
    return count > 0
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
