-- Misn05 Mission Script (Converted from Misn05Mission.cpp)

-- Compatibility for 1.5
SetLabel = SetLabel or SetLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})
local exu = require("exu")
-- Native MultST Init precedes Start; retain the authored Montana only.
if type(IsNetGame) == "function" and IsNetGame() then
    assert(exu.DisableStartingRecycler and exu.GetMyNetID,
        "misn05 co-op requires the bundled EXU multiplayer hooks")
    exu.DisableStartingRecycler()
end
local aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")
local subtit = require("ScriptSubtitles")
local PersistentConfig = require("PersistentConfig")
local Environment = require("Environment")
local CRMarsWeather = require("CRMarsWeather")
local PhysicsImpact = require("PhysicsImpact")
local CRCoop = require("CRCoop")
local LEADER_TEAM, ENEMY_TEAM, MINE_TEAM, SUPPORT_TEAM = 1, 5, 6, 7
local stockWeatherWindPush = CRMarsWeather.AllowWindPush
local M
local ApplyDifficultyObjectives


-- Object-camera presentation uses the established misn04 E/A and C transport. Only the campaign leader runs the mission
-- below; HUD/audio/removal/end calls are explicitly delivered to every peer.
-- E/A are an ordered, acknowledged event stream (eight small packets in flight,
-- retried every 0.2s). C is a replaceable camera snapshot. No tables go on wire.
-- These types do not collide with CRCoop's H/Q/K/P protocol. Join-in-progress
-- still requires a restart: native world reconstruction is not available here.
local unpackArgs = unpack or table.unpack
local native = {
    ClearObjectives = ClearObjectives, AddObjective = AddObjective,
    UpdateObjective = UpdateObjective, SetObjectiveOn = SetObjectiveOn,
    SetObjectiveOff = SetObjectiveOff, SetObjectiveName = SetObjectiveName,
    SetUserTarget = SetUserTarget, RemoveObject = RemoveObject,
    SucceedMission = SucceedMission, FailMission = FailMission,
    CameraReady = CameraReady, CameraObject = CameraObject,
    CameraFinish = CameraFinish, CameraCancelled = CameraCancelled,
    Play = subtit.Play, Queue = subtit.Queue, Stop = subtit.Stop,
}
local events, acknowledgements = {}, {}
local receivedEvent = 0
local nextEventSend, nextCameraSend = 0, 0
local cameraFrame, cameraGeneration, cameraSerial = nil, 0, 0
local remoteCameraSerial, localCameraGeneration = 0, 0
local cameraSkipped, localCameraActive = false, false
local remoteCamera

local function FromLeader(from)
    local player = CRCoop.GetPlayers()[from]
    return player and player.team == LEADER_TEAM
end

local function ApplyPresentation(op, ...)
    if op == "Resources" then
        local team, scrap, pilots = ...
        -- Each human owns their team resources. Do not mutate a remote team.
        if CRCoop.GetLocalTeam() == team then
            SetScrap(team, scrap)
            SetPilot(team, pilots)
        end
    elseif op == "Difficulty" then
        M.difficulty = ...
        ApplyDifficultyObjectives()
        if exu.SetDifficulty then exu.SetDifficulty(M.difficulty) end
    elseif op == "WeatherTarget" then
        if CRMarsWeather.SetTargetLevel then CRMarsWeather.SetTargetLevel(...) end
    elseif op == "WeatherForce" then
        if CRMarsWeather.ForceLevel then CRMarsWeather.ForceLevel(...) end
    elseif op == "WeatherLevel" then
        -- Guests follow the host's actual rung; their random ladder is disabled.
        if not CRCoop.IsAuthority() and CRMarsWeather.ForceLevel then
            CRMarsWeather.ForceLevel((...), 86400)
        end
    elseif op == "SucceedMission" or op == "FailMission" then
        local when, description = ...
        if localCameraActive then native.CameraFinish() end
        cameraFrame = nil
        localCameraActive = false
        M.coopResult = true
        native[op](math.max(GetTime() + 0.5, when), description)
    else
        return native[op](...)
    end
end

local function Present(op, ...)
    if CRCoop.IsNetworkGame() then
        if not CRCoop.IsAuthority() then return end
        events[#events + 1] = { op = op, args = { ... }, n = select("#", ...), expires = GetTime() + 5 }
    end
    return ApplyPresentation(op, ...)
end

-- Lexical wrappers affect this mission only; shared modules retain stock APIs.
local function ClearObjectives(...) return Present("ClearObjectives", ...) end
local function AddObjective(...) return Present("AddObjective", ...) end
local function UpdateObjective(...) return Present("UpdateObjective", ...) end
local function SetObjectiveOn(...) return Present("SetObjectiveOn", ...) end
local function SetObjectiveOff(...) return Present("SetObjectiveOff", ...) end
local function SetObjectiveName(...) return Present("SetObjectiveName", ...) end
local function SetUserTarget(...) return Present("SetUserTarget", ...) end
local function RemoveObject(...) return Present("RemoveObject", ...) end
-- Preserve the real subtitle module for Update/Initialize and return values.
subtit = setmetatable({
    Play = function(...) return Present("Play", ...) end,
    Queue = function(...) return Present("Queue", ...) end,
    Stop = function(...) return Present("Stop", ...) end,
}, { __index = subtit })

local function EndMission(op, when, description)
    if M.coopResult or M.coopPendingResult then return end
    if CRCoop.IsNetworkGame() then
        -- Flush preceding narrative/cleanup before publishing the result. Keep
        -- five seconds for result retries before native AiMission shuts down.
        M.coopPendingResult = { op, when, description }
    else
        M.coopResult = true
        native[op](when, description)
    end
end
local function SucceedMission(...) return EndMission("SucceedMission", ...) end
local function FailMission(...) return EndMission("FailMission", ...) end

local function CameraReady()
    cameraGeneration = cameraGeneration + 1
    cameraSkipped = false
    if CRCoop.IsNetworkGame() and localCameraActive then native.CameraFinish() end
    localCameraActive = true
    return native.CameraReady()
end
local function CameraObject(subject, x, y, z, target)
    cameraFrame = { subject, x, y, z, target }
    if cameraSkipped then return end
    local done = native.CameraObject(subject, x, y, z, target)
    -- Match the authored CameraObject -> CameraCancelled order: the object
    -- camera can process the skip during this call, before the next frame.
    if CRCoop.IsNetworkGame() and native.CameraCancelled() then
        cameraSkipped = true
        local wasActive = localCameraActive
        localCameraActive = false
        if wasActive then native.CameraFinish() end
    end
    return done
end
local function CameraCancelled(clear)
    -- A player's skip releases only their own camera; never skips shared
    -- destruction, transport orders, or the success gate for everyone else.
    if CRCoop.IsNetworkGame() then return false end
    return native.CameraCancelled(clear)
end
local function CameraFinish()
    cameraFrame = nil
    cameraSkipped = false
    local wasActive = localCameraActive
    localCameraActive = false
    if not CRCoop.IsNetworkGame() or wasActive then return native.CameraFinish() end
end

local function UpdateRemoteCamera()
    if not remoteCamera then return end
    local generation, subject, x, y, z, target = unpackArgs(remoteCamera)
    if subject == "" or M.coopResult then
        if localCameraActive then native.CameraFinish() end
        localCameraActive = false
        return
    end
    if generation ~= localCameraGeneration then
        localCameraGeneration = generation
        cameraSkipped = false
    end
    if cameraSkipped or not IsValid(subject) or not IsValid(target) then return end
    if not localCameraActive then
        native.CameraReady()
        localCameraActive = true
    end
    native.CameraObject(subject, x, y, z, target)
    if native.CameraCancelled() then
        cameraSkipped = true
        localCameraActive = false
        native.CameraFinish()
    end
end

local function UpdatePresentationTransport()
    if not CRCoop.IsNetworkGame() then return end
    if not CRCoop.IsAuthority() then
        UpdateRemoteCamera()
        return
    end
    local now, allDelivered = GetTime(), true
    for id, player in pairs(CRCoop.GetPlayers()) do
        if CRCoop.IsHumanTeam(player.team) and id ~= CRCoop.GetLocalPlayerId() then
            local ack = acknowledgements[id] or 0
            if ack < #events then allDelivered = false end
            if now >= nextEventSend then
                for seq = ack + 1, math.min(ack + 8, #events) do
                    local event = events[seq]
                    Send(id, "E", seq, event.op, event.expires, unpackArgs(event.args, 1, event.n))
                end
            end
        end
    end
    if now >= nextEventSend then nextEventSend = now + 0.2 end
    if M.coopPendingResult and allDelivered then
        local result = M.coopPendingResult
        M.coopPendingResult = nil
        Present(result[1], math.max(now + 5, result[2] or 0), result[3])
    end
    if now >= nextCameraSend then
        nextCameraSend = now + 0.2
        cameraSerial = cameraSerial + 1
        if cameraFrame then
            Send(0, "C", cameraSerial, cameraGeneration, unpackArgs(cameraFrame))
        else
            Send(0, "C", cameraSerial, cameraGeneration, "", 0, 0, 0)
        end
    end
end

local function ReceivePresentation(from, kind, ...)
    if not CRCoop.IsNetworkGame() then return false end
    if kind == "A" then
        local seq = ...
        if CRCoop.IsAuthority() and CRCoop.GetPlayers()[from] and
            type(seq) == "number" and seq >= 0 and seq <= #events and seq == math.floor(seq) then
            acknowledgements[from] = math.max(acknowledgements[from] or 0, seq)
        end
        return true
    end
    if kind ~= "E" and kind ~= "C" then return false end
    if CRCoop.IsAuthority() or not FromLeader(from) then return true end
    if kind == "C" then
        local seq, generation, subject, x, y, z, target = ...
        if type(seq) == "number" and seq > remoteCameraSerial and type(generation) == "number" and
            type(x) == "number" and type(y) == "number" and type(z) == "number" then
            remoteCameraSerial = seq
            remoteCamera = { generation, subject, x, y, z, target }
        end
        return true
    end
    local seq, op, expires = ...
    if type(seq) ~= "number" or type(op) ~= "string" or type(expires) ~= "number" then return true end
    if seq == receivedEvent + 1 and (native[op] or op == "Resources" or op == "Difficulty" or
        op == "WeatherTarget" or op == "WeatherForce" or op == "WeatherLevel") then
        local args = { select(4, ...) }
        -- Dynamic handles can arrive after the Lua packet. Withhold the ACK
        -- until the next retransmission resolves it, rather than losing markers.
        local missing = (op == "SetObjectiveOn" or op == "SetObjectiveName" or op == "SetUserTarget") and
            not IsValid(args[1])
        if missing and GetTime() < expires then return true end
        -- A target destroyed before its packet arrived must not block the
        -- stream (and the mission result) forever. Only that stale marker drops.
        if not missing then ApplyPresentation(op, unpackArgs(args, 1, select("#", ...) - 3)) end
        receivedEvent = seq
    end
    Send(from, "A", receivedEvent)
    return true
end


-- BuildObject invokes AddObject synchronously. This guard lets explicit mission
-- spawns bypass aiCore while leaving aiCore-produced CCA units managed normally.
local spawningScriptedEnemy = false

-- Helper for AI
local function SetupAI()
    DiffUtils.SetupTeams(aiCore.Factions.NSDF, aiCore.Factions.CCA, ENEMY_TEAM)

    -- Configure Player Team (1) for Scavenger Assist
    if aiCore.ActiveTeams and aiCore.ActiveTeams[1] then
        aiCore.ActiveTeams[1]:SetConfig("scavengerAssist", PersistentConfig.Settings.ScavengerAssistEnabled)
        aiCore.ActiveTeams[1]:SetConfig("manageFactories", false)
        aiCore.ActiveTeams[1]:SetConfig("autoRepairWingmen", PersistentConfig.Settings.AutoRepairWingmen)
    end

    -- Configure CCA (Team 5)
    if aiCore and aiCore.ActiveTeams and aiCore.ActiveTeams[ENEMY_TEAM] then
        local cca = aiCore.ActiveTeams[ENEMY_TEAM]
        cca:SetMaintainList(
            { scout = 2, scavenger = 4, constructor = 1 },                                 -- Recycler
            { tank = 1, lighttank = 1, bomber = 1, turret = 6, howitzer = 3, armory = 1 }, -- Factory
            true                                                                           -- Locked
        )
        cca.Config.resourceBoost = true
        cca.Config.autoManage = true
        cca.Config.autoBuild = true
        cca.Config.manageFactories = true
        cca.Config.manageConstructor = true
        cca.Config.requireConstructorFirst = true

        cca:PlanDefensivePerimeter(2, 4) -- 2 powers, 4 towers each
    end
end

-- Variables (Encapsulated for Save/Load)
local function NewMissionState()
    return {
    game_start = false,
    reconfactory = false,
    missionwon = false,
    missionfail = false,
    neworders = false,
    basewave = false,
    sent1Done = false,
    sent2Done = false,
    sent3Done = false,
    sent4Done = false,
    shuffle = false,
    notfound = false,
    go = false,
    check1 = false,
    check2 = false,
    check3 = false,
    check4 = false,
    newobjective = false,
    possiblewin = false,
    takeoutfactory = false,
    attacktimeset = false,
    attackstatement = false,
    endseq_started = false,
    endseq_spawned = false,
    endseq_cutscene_done = false,
    endseq_commander_revealed = false,

    -- Attack Wave sub-states
    aw1sent = false,
    aw2sent = false,
    aw3sent = false,
    aw4sent = false,
    aw1aattack = false,
    aw2aattack = false,
    aw3aattack = false,
    aw4aattack = false,
    aw9aattack = false,
    attackcmd = false,

    -- Timers
    randomwave = 99999999.0,
    readtime = 99999999999.0,
    start = 99999999999999.0,
    platoonhere = 99999999999999.0,
    bombtime = 0,
    aw1t = 99999999999.0,
    aw2t = 99999999999.0,
    aw3t = 99999999999.0,
    aw4t = 99999999999.0,

    -- Send Times array for shuffling
    sendTime = { 99999999.0, 99999999.0, 99999999.0, 99999999.0 },

    -- Handles
    lemnos = nil,
    player = nil,
    svrec = nil,
    avrec = nil,
    wBu1 = nil,
    wBu2 = nil,
    wBu3 = nil,
    w1u1 = nil,
    w1u2 = nil,
    w1u3 = nil,
    w1u4 = nil,
    w2u1 = nil,
    w2u2 = nil,
    w2u3 = nil,
    w2u4 = nil,
    w3u1 = nil,
    w3u2 = nil,
    w3u3 = nil,
    w3u4 = nil,
    w4u1 = nil,
    w4u2 = nil,
    w4u3 = nil,
    w4u4 = nil,
    rand1 = nil,
    rand2 = nil,
    aw1 = nil,
    aw2 = nil,
    aw3 = nil,
    aw4 = nil,
    aw5 = nil,
    aw1a = nil,
    aw2a = nil,
    aw3a = nil,
    aw4a = nil,
    aw5a = nil,
    aw6a = nil,
    aw7a = nil,
    aw8a = nil,
    aw9a = nil,
    cam1 = nil,

    -- Additional Logic Vars
    needtospawn = true,
    reconed = false,
    lemcin1 = false,
    lemcin2 = false,
    lemcinstart = 99999999.0,
    lemcinend = 99999999.0,
    endseq_cutscene_end = 99999999.0,
    endseq_post_wait_end = 99999999.0,
    difficulty = 2,
    cmdEldritch = nil,
    endCamTank = nil,
    endFleet = {},

    -- Script-owned enemy registries. scriptedEnemies isolates explicit mission
    -- spawns from aiCore; preAttackEnemies gates the final Lemnos assault;
    -- victoryEnemies gates mission completion.
    scriptedEnemies = {},
    preAttackEnemies = {},
    victoryEnemies = {},

    loading_done = false,
    loadGracePeriod = 0,
}
end
M = NewMissionState()

local function AddUniqueHandle(list, h)
    if not h or not IsValid(h) then return end
    for _, existing in ipairs(list) do
        if existing == h then return end
    end
    list[#list + 1] = h
end

local function PruneHandleList(list)
    local out = {}
    for _, h in ipairs(list or {}) do
        if h and IsValid(h) then
            out[#out + 1] = h
        end
    end
    return out
end

local function RegisterScriptedEnemy(h, countsForPreAttack, countsForVictory)
    if not h or not IsValid(h) then return h end

    M.scriptedEnemies = M.scriptedEnemies or {}
    M.preAttackEnemies = M.preAttackEnemies or {}
    M.victoryEnemies = M.victoryEnemies or {}

    AddUniqueHandle(M.scriptedEnemies, h)
    if countsForPreAttack then AddUniqueHandle(M.preAttackEnemies, h) end
    if countsForVictory then AddUniqueHandle(M.victoryEnemies, h) end
    return h
end

local function SpawnScriptedEnemy(odf, spawn, countsForPreAttack, countsForVictory)
    spawningScriptedEnemy = true
    local ok, h = pcall(BuildObject, odf, ENEMY_TEAM, spawn)
    spawningScriptedEnemy = false
    if not ok then
        error(h, 0)
    end
    return RegisterScriptedEnemy(h, countsForPreAttack, countsForVictory)
end

local function AnyAlive(list)
    for _, h in ipairs(list or {}) do
        if IsAlive(h) then return true end
    end
    return false
end

local function RefreshDifficulty()
    if CRCoop.IsNetworkGame() and not CRCoop.IsAuthority() then return M.difficulty end
    if exu and exu.GetDifficulty then
        local d = exu.GetDifficulty()
        if d ~= nil then M.difficulty = d end
    end
    if M.difficulty == nil then M.difficulty = 2 end
    return M.difficulty
end

ApplyDifficultyObjectives = function()
    if M.difficulty >= 3 then
        AddObjective("hard_diff", "yellow", 8.0, "High Difficulty: Enemy presence intensified.")
    elseif M.difficulty <= 1 then
        AddObjective("easy_diff", "blue", 8.0, "Low Difficulty: Enemy presence reduced.")
    end
end

local function ConfigureAlliances()
    CRCoop.ApplyCoopAlliances(ENEMY_TEAM)
    for team = 1, 4 do
        Ally(team, SUPPORT_TEAM); Ally(SUPPORT_TEAM, team)
        UnAlly(team, MINE_TEAM); UnAlly(MINE_TEAM, team)
    end
    UnAlly(ENEMY_TEAM, MINE_TEAM); UnAlly(MINE_TEAM, ENEMY_TEAM)
    UnAlly(ENEMY_TEAM, SUPPORT_TEAM); UnAlly(SUPPORT_TEAM, ENEMY_TEAM)
end

local function RefreshMissionHandles()
    local h = GetHandle("oblema110_i76building")
    if h and IsValid(h) then M.lemnos = h end

    h = GetHandle("svrecy-1_recycler")
    if h and IsValid(h) then M.svrec = h end

    h = GetHandle("avrecy-1_recycler")
    if h and IsValid(h) then M.avrec = h end

    h = GetHandle("cam1")
    if h and IsValid(h) then
        M.cam1 = h
        -- PORT FIX: native SetName changes the displayed name, not the map
        -- lookup label. SetLabel broke later GetHandle("cam1") rehydration and
        -- did not set the objective caption. Keep the same camera and flow.
        if SetObjectiveName then SetObjectiveName(M.cam1, "Volcano") end
    end
end

local function RebuildScriptedEnemyRegistry()
    M.scriptedEnemies = PruneHandleList(M.scriptedEnemies)
    M.preAttackEnemies = PruneHandleList(M.preAttackEnemies)
    M.victoryEnemies = PruneHandleList(M.victoryEnemies)

    -- Backward compatibility for saves made before the registries existed.
    local preAttack = {
        M.w1u1, M.w1u2, M.w1u3, M.w1u4,
        M.w2u1, M.w2u2, M.w2u3, M.w2u4,
        M.w3u1, M.w3u2, M.w3u3, M.w3u4,
        M.w4u1, M.w4u2, M.w4u3, M.w4u4,
    }
    for _, h in ipairs(preAttack) do
        RegisterScriptedEnemy(h, true, true)
    end

    local finalAttack = {
        M.aw1, M.aw2, M.aw3, M.aw4, M.aw5,
        M.aw1a, M.aw2a, M.aw3a, M.aw4a, M.aw5a,
        M.aw6a, M.aw7a, M.aw8a, M.aw9a,
    }
    for _, h in ipairs(finalAttack) do
        RegisterScriptedEnemy(h, false, true)
    end

    local nongating = { M.rand1, M.rand2, M.wBu1, M.wBu2, M.wBu3 }
    for _, h in ipairs(nongating) do
        RegisterScriptedEnemy(h, false, false)
    end
end

local function ApplyTurboToAll()
    if not (exu and exu.SetUnitTurbo) then return end
    for h in AllCraft() do
        local team = GetTeamNum(h)
        if CRCoop.IsNetworkGame() and not IsLocal(h) then
            -- The owning peer applies its own craft settings.
        elseif CRCoop.IsHumanTeam(team) then
            exu.SetUnitTurbo(h, true)
        elseif team ~= 0 then
            exu.SetUnitTurbo(h, M.difficulty >= 2)
        end
    end
end

function ApplyQOL()
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(600) end
        if exu.SetOrdnanceVelocInheritance then exu.SetOrdnanceVelocInheritance(true) end
    end
    PersistentConfig.Initialize()
    Environment.Init()

    -- Volcano-flank Mars weather. Init is idempotent, so the reload path can
    -- call ApplyQOL again without restarting the storm.
    --
    -- The Volcano profile is not the plains ladder turned down: ridges shelter
    -- the ground layer, the wind is a slope wind that reverses rather than a
    -- prevailing one, and the sky carries an orographic ice veil. It also
    -- disables haboob fronts, which need a long unobstructed fetch to organise
    -- and would not form on a ridge system.
    --
    -- No baseSky is supplied, so the sky layer stays off and the weather reads
    -- through fog, light and particles.
    if CRMarsWeather and CRMarsWeather.Init then
        local weatherOptions = {
            profile     = "Volcano",
            startLevel  = 1,
            targetLevel = 2,
            windPush = stockWeatherWindPush,
        }
        if CRCoop.IsNetworkGame() then weatherOptions.windPush = false end
        CRMarsWeather.Init(weatherOptions)
        if CRMarsWeather.SetAutomatic then
            CRMarsWeather.SetAutomatic(not CRCoop.IsNetworkGame() or CRCoop.IsAuthority())
        end

        if M and M.weatherState ~= nil and CRMarsWeather.Load then
            CRMarsWeather.Load(M.weatherState)
            M.weatherState = nil
        end
    end

    PhysicsImpact.Init()
end

local function BootstrapWithoutScriptedEnemies()
    if CRCoop.IsNetworkGame() then
        local scripted = {}
        for _, h in ipairs(M.scriptedEnemies or {}) do scripted[h] = true end
        aiCore.ResetObjectCacheTracking()
        for h in AllObjects() do
            aiCore.TrackWorldObject(h)
            if IsValid(h) and IsLocal(h) and not CRCoop.IsHumanCraft(h) and not scripted[h] then
                aiCore.AddObject(h)
            end
        end
        aiCore.RefreshObjectCache(true)
        return
    end
    local restoreIndependence = {}

    -- aiCore.Bootstrap scans the whole world. Temporarily mark explicit mission
    -- enemies as independence-locked so Bootstrap skips them, then restore each
    -- unit's original value before normal mission updates resume.
    if type(GetIndependence) == "function" and type(SetIndependence) == "function" then
        for _, h in ipairs(M.scriptedEnemies or {}) do
            if h and IsValid(h) and IsAlive(h) then
                local ok, value = pcall(GetIndependence, h)
                if ok then
                    restoreIndependence[h] = value
                    pcall(SetIndependence, h, 0)
                end
            end
        end
    end

    aiCore.Bootstrap()

    if type(SetIndependence) == "function" then
        for h, value in pairs(restoreIndependence) do
            if h and IsValid(h) then
                pcall(SetIndependence, h, value)
            end
        end
    end
end

local function RehydrateMissionRuntime()
    M.TPS = M.TPS or 20
    RefreshMissionHandles()
    RefreshDifficulty()
    ApplyQOL()
    RebuildScriptedEnemyRegistry()
    if CRCoop.IsAuthority() then
        SetupAI()
        BootstrapWithoutScriptedEnemies()
        SetAIP("misn05.aip", ENEMY_TEAM)
    end
    subtit.Initialize()
    ApplyTurboToAll()
    M.loading_done = true
end

function Start()
    M = NewMissionState()
    M.TPS = 20
    CRCoop.Initialize({
        getLocalPlayerId = function() return exu.GetMyNetID and exu.GetMyNetID() end,
        leaderTeam = LEADER_TEAM, humanTeamMin = 1, humanTeamMax = 4,
        onOutOfLives = function() FailMission(GetTime() + 3.0) end,
        -- MultST consumes its spawn buoys during initialization. Rally at the
        -- persistent Montana instead of the removed team-start marker.
        rallyPoints = { [1] = "avrecy-1_recycler", [2] = "oblema110_i76building" },
    })
    ConfigureAlliances()
    events, acknowledgements, receivedEvent = {}, {}, 0
    nextEventSend, nextCameraSend = 0, 0
    cameraFrame, cameraGeneration, cameraSerial = nil, 0, 0
    remoteCamera, remoteCameraSerial, localCameraGeneration = nil, 0, 0
    cameraSkipped, localCameraActive = false, false
    RefreshMissionHandles()
    RefreshDifficulty()
    if not CRCoop.IsNetworkGame() then ApplyDifficultyObjectives() end
    if CRMarsWeather.Shutdown then CRMarsWeather.Shutdown() end
    ApplyQOL()
    if CRCoop.IsAuthority() then
        SetupAI()
        if not CRCoop.IsNetworkGame() then aiCore.Bootstrap() end
        -- Preserve the clearable field; reserve separate hostile and support teams.
        for i = 1, 23 do
            local pathName = "path_" .. i
            BuildObject("boltmine", MINE_TEAM, pathName)
        end
    end
    subtit.Initialize()
    ApplyTurboToAll()
    M.loading_done = true
end

function CreatePlayer(id, name, team)
    CRCoop.CreatePlayer(id, name, team)
    ConfigureAlliances()
end
function AddPlayer(id, name, team)
    CRCoop.AddPlayer(id, name, team)
    ConfigureAlliances()
end
function DeletePlayer(id, name, team) CRCoop.DeletePlayer(id) end
function Receive(from, kind, ...)
    if ReceivePresentation(from, kind, ...) then return true end
    return CRCoop.Receive(from, kind, ...)
end

function AddObject(h)
    local team = GetTeamNum(h)

    if PersistentConfig and PersistentConfig.OnObjectCreated then
        PersistentConfig.OnObjectCreated(h)
    end
    Environment.OnObjectCreated(h)
    if CRMarsWeather and CRMarsWeather.OnObjectCreated then
        CRMarsWeather.OnObjectCreated(h)
    end
    PhysicsImpact.OnObjectCreated(h)

    -- EXU Turbo
    if exu and exu.SetUnitTurbo and IsCraft(h) and
        (not CRCoop.IsNetworkGame() or IsLocal(h)) then
        if CRCoop.IsHumanTeam(team) then
            exu.SetUnitTurbo(h, true)
        elseif team ~= 0 then
            if M.difficulty >= 2 then
                -- exu.SetUnitTurbo is boolean on/off; the turbo magnitude is
                -- engine-side. Passing a number raises and aborts AddObject.
                exu.SetUnitTurbo(h, true)
            end
        end
    end

    -- AI Core Hook. Explicit mission-scripted CCA units are kept out of
    -- aiCore so their Follow/Goto/Patrol/Attack orders remain authoritative.
    if CRCoop.IsNetworkGame() and
        (not CRCoop.IsAuthority() or not IsLocal(h) or not CRCoop.HasAllPlayerHandles() or CRCoop.IsHumanCraft(h)) then
        return
    end
    if team == ENEMY_TEAM then
        if not spawningScriptedEnemy then
            local nearBase = false
            if M.svrec and IsAlive(M.svrec) and GetDistance(h, M.svrec) < 400 then
                nearBase = true
            elseif GetHandle("cca_base") and GetDistance(h, "cca_base") < 400 then
                nearBase = true
            end

            if nearBase then
                aiCore.AddObject(h)
            end
        end
    elseif team == 1 then
        aiCore.AddObject(h)
    end
end

function DeleteObject(h)
end

-- Weather beats.
--
-- Recomputed from mission state every frame rather than latched on transitions,
-- so a save taken mid-mission lands on the right weather without persisting
-- which beats had already fired. The set piece is the one exception and carries
-- its own flag.
--
-- These only move the *target*: the director still walks the ladder there over
-- a few minutes, so nothing here cuts the weather.
--
-- The shape of the curve is the mission's own. misn05 opens with the player
-- hunting a structure across ridges above mined gullies, which is a navigation
-- problem, so it opens CALM -- weather that hides the ridgeline while the
-- objective is "find something" is not tension, it is an unfair death. The
-- storm arrives with the CCA and peaks while the factory is being held, which
-- is a fixed-position fight where poor visibility cuts both ways.
local function UpdateWeatherBeats()
    if not CRCoop.IsAuthority() then return end
    if not (CRMarsWeather and CRMarsWeather.SetTargetLevel) then
        return
    end

    -- Searching the ridges. Clear enough to read the terrain.
    local target = 1

    -- Structure found; the recon is under way and the map is known.
    if M.reconfactory then
        target = 2
    end

    -- The CCA deployment is in the field.
    if M.reconed then
        target = 2
    end

    -- Final assault ordered: hold the factory until the Sixth arrives.
    if M.go then
        target = 3
    end

    -- The last waves are on top of the factory. This is the peak.
    if M.aw1sent then
        target = 4
    end

    -- Won: stand the weather down so the closing cutscene plays in clear air.
    -- The fleet flyby and the commander reveal are the payoff, and dust across
    -- the camera is the one thing that can spoil them.
    if M.missionwon or M.missionfail then
        target = 1
    end

    if CRMarsWeather.GetTargetLevel() ~= target then
        Present("WeatherTarget", target)
    end

    -- Set piece: the final attackers arrive inside a summit blackout. Forced
    -- rather than targeted because it has to land on cue, and deliberately
    -- short -- the Volcano profile's severe rung is the briefest in either
    -- ladder for exactly this reason.
    if M.aw1sent and not M.weatherSetPiece and not M.missionwon then
        M.weatherSetPiece = true
        if CRMarsWeather.ForceLevel then
            Present("WeatherForce", 5, 60.0, 14.0)
        end
    end
    if CRCoop.IsNetworkGame() and CRMarsWeather.GetLevel then
        local level = CRMarsWeather.GetLevel()
        if level ~= M.coopWeatherLevel then
            M.coopWeatherLevel = level
            Present("WeatherLevel", level)
        end
    end
end

function Update()
    if GetTime() < (M.loadGracePeriod or 0) then
        return
    end
    if not M.loading_done then
        RehydrateMissionRuntime()
    end

    M.player = GetPlayerHandle()
    if exu and exu.UpdateOrdnance then exu.UpdateOrdnance() end
    -- Weather updates before Environment on purpose: CRWeather contributes fog
    -- and light into Environment's frame through its modifier hook, so it has
    -- to have run for this frame before Environment resolves that frame.
    if CRMarsWeather and CRMarsWeather.Update then
        UpdateWeatherBeats()
        CRMarsWeather.Update(1.0 / M.TPS)
    end
    Environment.Update(1.0 / M.TPS)
    PhysicsImpact.Update(1.0 / M.TPS)
    subtit.Update()
    PersistentConfig.UpdateInputs(localCameraActive)
    PersistentConfig.UpdateHeadlights()

    CRCoop.Update()
    UpdatePresentationTransport()
    if M.coopResult or M.coopPendingResult then return end
    if CRCoop.IsNetworkGame() then
        if CRCoop.HasLeaderDeparted() then
            M.coopResult = true
            if localCameraActive then native.CameraFinish() end
            localCameraActive = false
            native.FailMission(GetTime() + 1.0)
            return
        end
        if CRCoop.HasUnsupportedPlayerTeam() or CRCoop.HasLateJoiners() then
            if not M.coopRestartWarned then
                DisplayMessage("Use distinct teams 1-4 and start together. Late join/rejoin requires a mission restart.")
                M.coopRestartWarned = true
            end
            return
        end
        if not CRCoop.IsSessionReady() then return end
    end
    if not M.coopMissionStarted then
        CRCoop.MarkMissionStarted()
        M.coopMissionStarted = true
    end
    if not CRCoop.IsAuthority() then return end
    if CRCoop.IsNetworkGame() and not M.coopBootstrapped then
        BootstrapWithoutScriptedEnemies()
        M.coopBootstrapped = true
    end
    aiCore.Update()

    -- Game Start / Initial Setup
    if not M.game_start then
        if CRCoop.IsNetworkGame() then
            Present("Difficulty", RefreshDifficulty())
            CRCoop.ForEachHumanTeam(function(team)
                Present("Resources", team, DiffUtils.ScaleRes(40), DiffUtils.ScaleRes(10))
            end)
            local offlinePlayer = GetHandle("player-1_hover")
            if IsValid(offlinePlayer) and not CRCoop.IsHumanCraft(offlinePlayer) then RemoveObject(offlinePlayer) end
        else
            SetScrap(1, DiffUtils.ScaleRes(40))
            SetPilot(1, DiffUtils.ScaleRes(10))
        end
        SetScrap(ENEMY_TEAM, DiffUtils.ScaleRes(40))

        RefreshMissionHandles()

        SetAIP("misn05.aip", ENEMY_TEAM)
        subtit.Play("misn0501.wav")
        M.game_start = true
        CRCoop.SetMissionPhase(1)

        M.randomwave = GetTime() + DiffUtils.ScaleTimer(5.0)

        if M.cam1 and IsValid(M.cam1) and SetObjectiveName then SetObjectiveName(M.cam1, "Volcano") end
        M.newobjective = true
    end

    -- Objectives
    if M.newobjective then
        ClearObjectives()
        if M.missionwon then
            AddObjective("misn0502.otf", "green")
        end
        if M.neworders and not M.missionwon then
            AddObjective("misn0502.otf", "white")
        end
        if M.neworders then
            AddObjective("misn0503.otf", "green")
        end
        if M.reconfactory and not M.neworders then
            AddObjective("misn0503.otf", "white")
        end
        if M.reconfactory then
            AddObjective("misn0501.otf", "green")
        else
            AddObjective("misn0501.otf", "white")
        end
        M.newobjective = false
    end

    -- Random Spawns (Start of mission)
    if not M.reconed then
        if M.needtospawn then
            if (M.randomwave < GetTime()) and IsAlive(M.svrec) then
                local type1 = "svfigh"
                if M.difficulty >= 3 then type1 = "svltnk" end

                M.rand1 = SpawnScriptedEnemy(type1, M.svrec, false, false)
                M.rand2 = SpawnScriptedEnemy("svfigh", M.svrec, false, false)
                Attack(M.rand1, M.avrec)
                Attack(M.rand2, M.avrec)

                for i = 1, DiffUtils.ScaleEnemy(1) - 1 do
                    local h = SpawnScriptedEnemy("svfigh", M.svrec, false, false)
                    Attack(h, M.avrec)
                    SetIndependence(h, 1)
                end
                SetIndependence(M.rand1, 1)
                SetIndependence(M.rand2, 1)
                M.needtospawn = false
            end
        else
            if (not IsAlive(M.rand1)) and (not IsAlive(M.rand2)) then
                M.needtospawn = true
                M.randomwave = GetTime() + DiffUtils.ScaleTimer(20.0)
            end
        end
    end

    -- Not Found Warning (Player near factory but hasn't triggered recon yet)
    if (not M.reconfactory) and (CRCoop.AnyPlayerSatisfies(function(h) return GetDistance(h, M.lemnos) < 600.0 end)) and (not M.notfound) then
        subtit.Play("misn0502.wav")
        M.notfound = true
    end

    -- Recon Factory Logic
    if (not M.reconfactory) and (CRCoop.AnyPlayerSatisfies(function(h) return GetDistance(h, M.lemnos) < 230.0 end)) then
        subtit.Play("misn0503.wav")
        subtit.Play("misn0504.wav")
        M.reconfactory = true
        CRCoop.SetMissionPhase(2)
        M.newobjective = true
        M.start = GetTime() + DiffUtils.ScaleTimer(90.0)

        -- Cut Cinematic: Recon Factory
        M.lemcinstart = GetTime() - 0.1
        M.lemcinend = GetTime() + 4.0
    end

    -- Cinematic Logic
    if (not M.lemcin1) and (M.lemcinstart < GetTime()) and M.reconfactory then
        CameraReady()
        M.lemcin1 = true
    end

    if M.lemcin1 and (not M.lemcin2) then
        if M.lemcinend > GetTime() then
            CameraObject(M.player, 0, 5000, -5000, M.lemnos)
        else
            CameraFinish()
            M.lemcin2 = true
        end

        if CameraCancelled() then
            CameraFinish()
            M.lemcin2 = true
        end
    end

    -- Shuffle Logic (Triggered by 'notfound' aka getting close to 600m)
    if M.notfound and (not M.shuffle) then
        M.sendTime = {
            GetTime() + DiffUtils.ScaleTimer(10.0),
            GetTime() + DiffUtils.ScaleTimer(90.0),
            GetTime() + DiffUtils.ScaleTimer(130.0),
            GetTime() + DiffUtils.ScaleTimer(190.0)
        }

        for i = 1, 10 do
            local j, k = math.random(1, 4), math.random(1, 4)
            M.sendTime[j], M.sendTime[k] = M.sendTime[k], M.sendTime[j]
        end
        M.shuffle = true
    end

    -- Wave 1
    if (M.sendTime[1] < GetTime()) and (not M.sent1Done) then
        local type1 = "svfigh"
        if M.difficulty >= 3 then type1 = "svltnk" end

        M.w1u1 = SpawnScriptedEnemy(type1, M.svrec, true, true)
        M.w1u2 = SpawnScriptedEnemy("svfigh", M.svrec, true, true)
        M.w1u3 = SpawnScriptedEnemy("svturr", M.svrec, true, true)
        M.w1u4 = SpawnScriptedEnemy("svturr", M.svrec, true, true)

        for i = 1, DiffUtils.ScaleEnemy(1) - 1 do
            local h = SpawnScriptedEnemy("svfigh", M.svrec, true, true)
            Attack(h, M.avrec)
            SetIndependence(h, 1)
        end
        M.sent1Done = true

        Follow(M.w1u1, M.w1u3)
        Follow(M.w1u2, M.w1u4)
        SetIndependence(M.w1u1, 1)
        SetIndependence(M.w1u2, 1)
        Goto(M.w1u3, "defendrim2")
        Goto(M.w1u4, "defendrim1")

        M.check1 = true
        M.check2 = true
    end

    -- Check Logic (Turrets -> Patrol if dead/arrived)
    if IsAlive(M.w1u3) and (not M.check1) and (GetCurrentCommand(M.w1u3) == 0) then
        Defend(M.w1u3, 1)
    end
    if M.check1 and (not IsAlive(M.w1u3) or GetDistance(M.w1u3, "defendrim2") < 40.0) then
        if IsAlive(M.w1u3) then Stop(M.w1u3, 1) end
        Patrol(M.w1u1, "attackpatrol1", 1)
        M.check1 = false
    end

    if IsAlive(M.w1u4) and (not M.check2) and (GetCurrentCommand(M.w1u4) == 0) then
        Defend(M.w1u4, 1)
    end
    if M.check2 and (not IsAlive(M.w1u4) or GetDistance(M.w1u4, "defendrim1") < 40.0) then
        if IsAlive(M.w1u4) then Stop(M.w1u4, 1) end
        Patrol(M.w1u2, "attackpatrol1", 1)
        M.check2 = false
    end

    -- Wave 2 (Tanks + Turrets)
    if (M.sendTime[2] < GetTime()) and (not M.sent2Done) then
        local type2 = "svtank"
        if M.difficulty <= 1 then type2 = "svltnk" end

        M.w2u1 = SpawnScriptedEnemy(type2, M.svrec, true, true)
        M.w2u2 = SpawnScriptedEnemy(type2, M.svrec, true, true)
        M.w2u3 = SpawnScriptedEnemy("svturr", M.svrec, true, true)
        M.w2u4 = SpawnScriptedEnemy("svturr", M.svrec, true, true)

        for i = 1, DiffUtils.ScaleEnemy(1) - 1 do
            local h = SpawnScriptedEnemy(type2, M.svrec, true, true)
            Attack(h, M.avrec)
            SetIndependence(h, 1)
        end
        M.sent2Done = true
        Follow(M.w2u1, M.w2u3)
        Follow(M.w2u2, M.w2u4)
        SetIndependence(M.w2u1, 1)
        SetIndependence(M.w2u2, 1)
        Goto(M.w2u3, "defendrim3")
        Goto(M.w2u4, "defendrim4")
        -- PORT FIX: the DLL armed these wave-2 checks in wave 1. Shuffling can
        -- make wave 1 run first and consume them on absent wave-2 handles, so
        -- the tanks never transition from escort to patrol. Arm each check
        -- when its own turret exists; wave times, units and patrol path stay.
        M.check3 = true
        M.check4 = true
    end

    if IsAlive(M.w2u3) and (not M.check3) and (GetCurrentCommand(M.w2u3) == 0) then
        Defend(M.w2u3, 1)
    end
    if M.check3 and (not IsAlive(M.w2u3) or GetDistance(M.w2u3, "defendrim3") < 40.0) then
        if IsAlive(M.w2u3) then Stop(M.w2u3, 1) end
        Patrol(M.w2u1, "attackpatrol1", 1)
        M.check3 = false
    end

    if IsAlive(M.w2u4) and (not M.check4) and (GetCurrentCommand(M.w2u4) == 0) then
        Defend(M.w2u4, 1)
    end
    if M.check4 and (not IsAlive(M.w2u4) or GetDistance(M.w2u4, "defendrim4") < 40.0) then
        if IsAlive(M.w2u4) then Stop(M.w2u4, 1) end
        Patrol(M.w2u2, "attackpatrol1", 1)
        M.check4 = false
    end

    -- Wave 3
    if (M.sendTime[3] < GetTime()) and (not M.sent3Done) then
        M.w3u3 = SpawnScriptedEnemy("svfigh", M.svrec, true, true)
        M.w3u4 = SpawnScriptedEnemy("svfigh", M.svrec, true, true)
        M.sent3Done = true
        Patrol(M.w3u3, "attackpatrol1", 1)
        Patrol(M.w3u4, "attackpatrol1", 1)

        for i = 1, DiffUtils.ScaleEnemy(2) - 2 do
            local h = SpawnScriptedEnemy("svfigh", M.svrec, true, true)
            Patrol(h, "attackpatrol1", 1)
            SetIndependence(h, 1)
        end
    end

    -- Wave 4
    if (M.sendTime[4] < GetTime()) and (not M.sent4Done) then
        local type4 = "svltnk"
        if M.difficulty >= 3 then type4 = "svtank" end

        M.w4u3 = SpawnScriptedEnemy(type4, M.svrec, true, true)
        M.w4u4 = SpawnScriptedEnemy(type4, M.svrec, true, true)
        M.sent4Done = true
        Patrol(M.w4u3, "attackpatrol1", 1)
        Patrol(M.w4u4, "attackpatrol1", 1)

        for i = 1, DiffUtils.ScaleEnemy(2) - 2 do
            local h = SpawnScriptedEnemy(type4, M.svrec, true, true)
            Patrol(h, "attackpatrol1", 1)
            SetIndependence(h, 1)
        end
    end

    -- Post-Recon Logic
    if M.reconfactory and (not M.reconed) then
        if IsInfo("oblema") or (M.start < GetTime()) then
            subtit.Play("misn0515.wav")
            SetObjectiveName(M.lemnos, "Lemnos Factory")
            M.readtime = GetTime() + 10.0
            M.reconed = true
        end
    end

    if (not M.neworders) and (M.readtime < GetTime()) then
        M.neworders = true
        subtit.Play("misn0506.wav")
        M.newobjective = true
    end

    -- Base Wave (Spawns after recon; intentionally does not gate progression)
    if IsAlive(M.svrec) and (not M.basewave) and M.reconfactory then
        M.wBu1 = SpawnScriptedEnemy("svtank", M.svrec, false, false)
        M.wBu2 = SpawnScriptedEnemy("svfigh", M.svrec, false, false)
        M.wBu3 = SpawnScriptedEnemy("svfigh", M.svrec, false, false)
        Attack(M.wBu1, M.avrec)
        Attack(M.wBu2, M.avrec)
        Attack(M.wBu3, M.avrec)
        SetIndependence(M.wBu1, 1)
        SetIndependence(M.wBu2, 1)
        SetIndependence(M.wBu3, 1)
        M.basewave = true
    end

    -- Check if all four shuffled deployment waves, including difficulty extras,
    -- are dead before triggering the final Lemnos assault.
    if M.sent1Done and M.sent2Done and M.sent3Done and M.sent4Done and
        (not AnyAlive(M.preAttackEnemies)) and (not M.attacktimeset) then
        subtit.Play("misn0507.wav")
        M.platoonhere = GetTime() + DiffUtils.ScaleTimer(45.0)
        M.attacktimeset = true
        M.go = true
    end

    -- Spawn Final Attackers
    if (not IsAlive(M.aw1)) and (not IsAlive(M.aw2)) and (not IsAlive(M.aw3)) and (not IsAlive(M.aw4)) and (not IsAlive(M.aw5)) and
        (M.platoonhere < GetTime()) and M.go and IsAlive(M.svrec) then
        -- PORT FIX: the port correctly waits until platoonhere (the DLL used
        -- > instead of <), but must consume this one-shot latch too. Otherwise
        -- killing the main razors respawns them forever and resets all four
        -- reinforcement timers before victory can be checked. This preserves
        -- the scheduled assault and its 15/55/110/160-second reinforcements.
        M.go = false
        subtit.Play("misn0508.wav")
        subtit.Play("misn0509.wav")

        local attacksent = math.random(0, 3)
        M.attackstatement = false

        local dest = "destroy1"
        if attacksent == 1 then
            dest = "destroy2"
        elseif attacksent == 2 then
            dest = "destroy3"
        elseif attacksent == 3 then
            dest = "destroy4"
        end

        M.aw1 = SpawnScriptedEnemy("svhraz", M.svrec, false, true)
        M.aw2 = SpawnScriptedEnemy("svhraz", M.svrec, false, true)
        M.aw3 = SpawnScriptedEnemy("svhraz", M.svrec, false, true)
        Goto(M.aw1, dest)
        Goto(M.aw2, dest)
        Goto(M.aw3, dest)
        M.razorAttackers = { M.aw1, M.aw2, M.aw3 }
        M.razorAttackIssued = {}

        for i = 1, DiffUtils.ScaleEnemy(3) - 3 do
            local h = SpawnScriptedEnemy("svhraz", M.svrec, false, true)
            Goto(h, dest)
            SetIndependence(h, 1)
            table.insert(M.razorAttackers, h)
        end

        if M.difficulty >= 3 then
            M.aw4 = SpawnScriptedEnemy("svhraz", M.svrec, false, true)
            M.aw5 = SpawnScriptedEnemy("svhraz", M.svrec, false, true)
            Goto(M.aw4, dest)
            Goto(M.aw5, dest)
            table.insert(M.razorAttackers, M.aw4)
            table.insert(M.razorAttackers, M.aw5)
        end

        M.bombtime = GetTime() + DiffUtils.ScaleTimer(10.0)
        M.attackcmd = false

        M.aw1t = GetTime() + DiffUtils.ScaleTimer(15.0)
        M.aw2t = GetTime() + DiffUtils.ScaleTimer(55.0)
        M.aw3t = GetTime() + DiffUtils.ScaleTimer(110.0)
        M.aw4t = GetTime() + DiffUtils.ScaleTimer(160.0)
    end

    -- Attack Command Switch (Razors switch to attack Factory)
    if (not M.attackcmd) and (M.bombtime < GetTime()) then
        -- PORT FIX: Lua's old `a() or b() ...` stopped after the first razor,
        -- unlike the DLL's five independent checks. The DLL's shared latch
        -- also stranded late arrivals. Track each order, including difficulty
        -- extras, until every survivor reaches either existing QOL 60m trigger.
        -- Keep the original three-second polling and all phase/spawn gates.
        if not M.razorAttackers then
            -- Old saves retain named handles but predate this registry.
            M.razorAttackers = {}
            for _, name in ipairs({ "aw1", "aw2", "aw3", "aw4", "aw5" }) do
                if M[name] then table.insert(M.razorAttackers, M[name]) end
            end
        end
        M.razorAttackIssued = M.razorAttackIssued or {}
        local allOrdered = true
        for i, u in ipairs(M.razorAttackers) do
            if IsAlive(u) and not M.razorAttackIssued[i] then
                if GetDistance(u, "dest1") < 60.0 or GetDistance(u, "dest2") < 60.0 then
                    Attack(u, M.lemnos)
                    SetIndependence(u, 1)
                    M.razorAttackIssued[i] = true
                else
                    allOrdered = false
                end
            end
        end
        M.attackcmd = allOrdered
        M.bombtime = GetTime() + 3.0
    end

    -- Platoon Closing In Warning
    if (not M.attackstatement) then
        local function IsThreat(u)
            return IsAlive(u) and (GetDistance(u, M.lemnos) < 500.0)
        end

        if IsThreat(M.aw1) or IsThreat(M.aw2) or IsThreat(M.aw3) or IsThreat(M.aw4) or IsThreat(M.aw5) then
            subtit.Play("misn0510.wav")
            M.attackstatement = true
        end
    end

    -- Additional Waves (aw1a...aw9a) triggered by timers
    if (M.aw1t < GetTime()) and (not M.aw1sent) and IsAlive(M.svrec) then
        M.aw2a = SpawnScriptedEnemy("svfigh", M.svrec, false, true)
        Attack(M.aw2a, M.lemnos)
        SetIndependence(M.aw2a, 1)
        M.aw1sent = true
    end

    if (M.aw2t < GetTime()) and (not M.aw2sent) and IsAlive(M.svrec) then
        M.aw4a = SpawnScriptedEnemy("svtank", M.svrec, false, true)
        Attack(M.aw4a, M.lemnos)
        SetIndependence(M.aw4a, 1)
        M.aw2sent = true
    end

    if (M.aw3t < GetTime()) and (not M.aw3sent) and IsAlive(M.svrec) then
        M.aw5a = SpawnScriptedEnemy("svfigh", M.svrec, false, true)
        M.aw6a = SpawnScriptedEnemy("svfigh", M.svrec, false, true)
        Attack(M.aw5a, M.lemnos)
        Attack(M.aw6a, M.lemnos)
        SetIndependence(M.aw5a, 1)
        SetIndependence(M.aw6a, 1)
        M.aw3sent = true
    end

    if (M.aw4t < GetTime()) and (not M.aw4sent) and IsAlive(M.svrec) then
        M.aw8a = SpawnScriptedEnemy("svfigh", M.svrec, false, true)
        local type9 = "svtank"
        if M.difficulty >= 3 then type9 = "svhraz" end
        M.aw9a = SpawnScriptedEnemy(type9, M.svrec, false, true)
        Attack(M.aw8a, M.lemnos)
        Attack(M.aw9a, M.lemnos)
        SetIndependence(M.aw8a, 1)
        SetIndependence(M.aw9a, 1)
        M.aw4sent = true
    end

    -- Force attack factory if near
    local function ForceAttack(u, flag)
        if (not flag) and IsAlive(u) and (GetDistance(u, M.lemnos) < 300.0) then
            Attack(u, M.lemnos)
            SetIndependence(u, 1)
            return true
        end
        return flag
    end
    M.aw1aattack = ForceAttack(M.aw1a, M.aw1aattack)
    M.aw2aattack = ForceAttack(M.aw2a, M.aw2aattack)
    M.aw3aattack = ForceAttack(M.aw3a, M.aw3aattack)
    M.aw4aattack = ForceAttack(M.aw4a, M.aw4aattack)
    M.aw9aattack = ForceAttack(M.aw9a, M.aw9aattack)

    -- Possible Win (Recycler Dead) -> Send every registered victory-gating
    -- scripted attacker to Lemnos, including anonymous difficulty extras.
    if (not IsAlive(M.svrec)) and (not M.possiblewin) then
        M.possiblewin = true
        subtit.Play("misn0516.wav")

        M.aw1aattack = true
        M.aw2aattack = true
        M.aw3aattack = true
        M.aw4aattack = true
        M.aw9aattack = true

        M.sent1Done = true
        M.sent2Done = true
        M.sent3Done = true
        M.sent4Done = true
        M.aw1sent = true
        M.aw2sent = true
        M.aw3sent = true
        M.aw4sent = true

        local remaining = false
        for _, u in ipairs(M.victoryEnemies or {}) do
            if IsAlive(u) then
                Attack(u, M.lemnos)
                SetIndependence(u, 1)
                remaining = true
            end
        end

        if remaining then
            subtit.Play("misn0517.wav")
        end

        M.takeoutfactory = true
    end

    -- Win Condition. The registry includes all difficulty-added attackers so
    -- mission completion cannot race ahead while an anonymous extra survives.
    -- PORT FIX: the DLL checked recycler/factory losses before this win test.
    -- The port moved losses below it, allowing an enemy-clear frame to win
    -- despite a destroyed objective (or an already pending failure). Retain
    -- failure precedence without changing the QOL fleet/commander sequence.
    if M.sent1Done and M.sent2Done and M.sent3Done and M.sent4Done and M.aw1sent and M.aw2sent and M.aw3sent and M.aw4sent and (not M.missionwon)
        and not M.missionfail and IsAlive(M.avrec) and IsAlive(M.lemnos) then
        if not AnyAlive(M.victoryEnemies) then
            M.missionwon = true
            M.newobjective = true
            M.endseq_started = false
            M.endseq_spawned = false
            M.endseq_cutscene_done = false
            M.endseq_commander_revealed = false
        end
    end

    -- Mission win sequence: spawn allied fleet cinematic, then reveal commander and finish.
    if M.missionwon then
        if not M.endseq_started then
            M.endseq_started = true
            M.endseq_cutscene_end = GetTime() + 10.0
            M.endseq_post_wait_end = 99999999.0

            -- Support team stays separate from the hostile minefield.

            -- Spawn a friendly armored fleet and move toward Lemnos.
            local anchor = M.avrec
            if not IsAlive(anchor) then anchor = M.player end
            M.endFleet = {}
            for i = 1, 7 do
                local spawnPos = GetPositionNear(GetPosition(anchor), 40, 140)
                local t = BuildObject("avtank", SUPPORT_TEAM, spawnPos)
                if IsAlive(t) then
                    table.insert(M.endFleet, t)
                    Goto(t, M.lemnos, 1)
                end
            end

            M.endCamTank = M.endFleet[1]
            M.cmdEldritch = M.endFleet[1]
            M.aud11 = subtit.Play("misn0511.wav")
            CameraReady()
        end

        if M.endseq_started and not M.endseq_cutscene_done then
            if (GetTime() < M.endseq_cutscene_end) and (not CameraCancelled()) then
                local camTank = M.endCamTank
                if not IsAlive(camTank) then
                    camTank = M.player
                end
                -- CameraObject offsets are centimeters: frame the fleet from
                -- 25 m to the side, 18 m above and 85 m behind its lead tank.
                CameraObject(camTank, -2500, 1800, -8500, M.lemnos)
            else
                CameraFinish()
                CameraCancelled(false)
                M.endseq_cutscene_done = true
                M.endseq_post_wait_end = GetTime() + 15.0
            end
        end

        if M.endseq_cutscene_done and (not M.endseq_commander_revealed) and GetTime() >= M.endseq_post_wait_end then
            if IsAlive(M.cmdEldritch) then
                SetObjectiveOn(M.cmdEldritch)
                SetObjectiveName(M.cmdEldritch, "Commander Eldritch")
            end
            M.endseq_commander_revealed = true
            subtit.Play("misn0512.wav")
            SucceedMission(GetTime() + 1.0, "misn05w1.des")
        end
    end

    -- Fail Conditions
    if (not M.missionwon) and (not IsAlive(M.avrec)) and (not M.missionfail) then
        FailMission(GetTime() + 15.0, "misn05l1.des")
        subtit.Play("misn0513.wav")
        M.missionfail = true
    end

    if (not M.missionwon) and (not IsAlive(M.lemnos)) and (not M.missionfail) then
        FailMission(GetTime() + 15.0, "misn05l2.des")
        subtit.Play("misn0514.wav")
        M.missionfail = true
    end
end

function Save()
    -- Only the scalar storm state: the particle systems are rebuilt from the
    -- preset on load, because Ogre objects do not survive a save.
    if CRMarsWeather and CRMarsWeather.Save then
        M.weatherState = CRMarsWeather.Save()
    end
    return M, aiCore.Save()
end

function Load(missionData, _)
    M = missionData or M

    M.TPS = M.TPS or 20
    M.scriptedEnemies = M.scriptedEnemies or {}
    M.preAttackEnemies = M.preAttackEnemies or {}
    M.victoryEnemies = M.victoryEnemies or {}
    -- Old saves can retain the pre-fix shared latch after only one razor was
    -- ordered. Recheck their named survivors once; new saves retain per-unit
    -- progress. A main handle or armed reinforcement timer proves the spawn
    -- was used, even if dead handles have disappeared from an old save.
    if not M.razorAttackers then M.attackcmd = false end
    if M.attacktimeset and (M.aw1 ~= nil or (M.aw1t or 99999999999.0) < 99999999999.0) then M.go = false end
    M.loading_done = false
    M.loadGracePeriod = GetTime() + 2.0
    spawningScriptedEnemy = false
end

-- Original DLL comments and cut-content ledger. These are historical C++
-- fragments, kept inactive for reconstruction alongside the complete, verbatim
-- References/EarlyMissionSources/Misn05Mission.cpp. QOL behavior above is retained.
--[==[

Misn05Mission.cpp:7
/*
	Misn05Mission Event
*/

Misn05Mission.cpp:27
// bools

Misn05Mission.cpp:48
// floats

Misn05Mission.cpp:62
// handles

Misn05Mission.cpp:82
// integers

Misn05Mission.cpp:246
/*
	Here's where you
	set the values
	at the start.  
	*/

Misn05Mission.cpp:276
/*
		Here is where you 
		put what happens 
		every frame.  
	*/

Misn05Mission.cpp:377
//rand3 = BuildObject("svfigh",2,svrec);

Misn05Mission.cpp:380
//Attack (rand3, avrec);

Misn05Mission.cpp:383
//SetIndependence(rand3, 1);

Misn05Mission.cpp:394
//&&

Misn05Mission.cpp:395
//(!IsAlive(rand3)) 

Misn05Mission.cpp:1068
//w3u1 = BuildObject ("svfigh",2,svrec);

Misn05Mission.cpp:1069
//w3u2 = BuildObject ("svfigh",2,svrec);

Misn05Mission.cpp:1073
//Patrol (w3u1, "attackpatrol1",1);

Misn05Mission.cpp:1074
//Patrol (w3u2, "attackpatrol1",1);

Misn05Mission.cpp:1084
//w4u1 = BuildObject ("svfigh",2,svrec);

Misn05Mission.cpp:1085
//w4u2 = BuildObject ("svfigh",2,svrec);

Misn05Mission.cpp:1089
//Patrol (w4u1, "attackpatrol1",1);

Misn05Mission.cpp:1090
//Patrol (w4u2, "attackpatrol1",1);

Misn05Mission.cpp:1115
//lemcinstart = GetTime() - 1.0f;

Misn05Mission.cpp:1116
//lemcinend = GetTime() + 3.0f;

Misn05Mission.cpp:1119
/*if
		(
		(lemcin1 == false) && (lemcinstart < GetTime())
		)
	{
		CameraReady();
		lemcin1 = true;
	}

	if
		(
		(lemcin2 == false) && (lemcinend > GetTime())
		)
	{
		CameraObject(player, 0, 5000, - 5000, lemnos);
	}

	if
		(
		(lemcin2 == false) && (lemcinend < GetTime())
		)
	{
		CameraFinish();
		lemcin2 = true;
	}*/

Misn05Mission.cpp:1160
//AudioMessage ("misn0515.wav");

Misn05Mission.cpp:1191
// make sure dead things stay 

Misn05Mission.cpp:1247
//600.0f

Misn05Mission.cpp:1273
//aw4 = BuildObject ("svhraz", 2, svrec);

Misn05Mission.cpp:1274
//aw5 = BuildObject ("svhraz", 2, svrec);

Misn05Mission.cpp:1278
//Goto (aw4, "destroy1");

Misn05Mission.cpp:1279
//Goto (aw5, "destroy1");

Misn05Mission.cpp:1285
//aw4 = BuildObject ("svhraz", 2, svrec);

Misn05Mission.cpp:1286
//aw5 = BuildObject ("svhraz", 2, svrec);

Misn05Mission.cpp:1290
//Goto (aw4, "destroy2");

Misn05Mission.cpp:1291
//Goto (aw5, "destroy2");

Misn05Mission.cpp:1297
//aw4 = BuildObject ("svhraz", 2, svrec);

Misn05Mission.cpp:1298
//aw5 = BuildObject ("svhraz", 2, svrec);

Misn05Mission.cpp:1302
//Goto (aw4, "destroy3");

Misn05Mission.cpp:1303
//Goto (aw5, "destroy3");

Misn05Mission.cpp:1309
//aw4 = BuildObject ("svhraz", 2, svrec);

Misn05Mission.cpp:1310
//aw5 = BuildObject ("svhraz", 2, svrec);

Misn05Mission.cpp:1314
//Goto (aw4, "destroy4");

Misn05Mission.cpp:1315
//Goto (aw5, "destroy4");

Misn05Mission.cpp:1384
/*if
			(
			(platoonhere < GetTime()) && 
			(!IsAlive(aw1)) &&
			(!IsAlive(aw2)) &&
			(!IsAlive(aw3)) &&
			(!IsAlive(aw4)) &&
			(!IsAlive(aw5)) &&
			(missionwon == false)
			)
		{
			missionwon = true;
			AudioMessage ("misn0511.wav");
			AudioMessage ("misn0512.wav");
			SucceedMission (GetTime() + 15.0f);
		}*/

Misn05Mission.cpp:1447
//aw1a = BuildObject ("svfigh", 2, svrec);

Misn05Mission.cpp:1449
//Goto (aw1a, lemnos);

Misn05Mission.cpp:1462
//aw3a = BuildObject ("svtank", 2, svrec);

Misn05Mission.cpp:1464
//Goto (aw3a, lemnos);

Misn05Mission.cpp:1479
//aw7a = BuildObject ("svfigh", 2, svrec);

Misn05Mission.cpp:1484
//Goto (aw7a, lemnos);

Misn05Mission.cpp:1618
//

Misn05Mission.cpp:1649
//

Misn05Mission.cpp:1754
// init bools

Misn05Mission.cpp:1760
// init floats

Misn05Mission.cpp:1766
// init handles

Misn05Mission.cpp:1772
// init ints

Misn05Mission.cpp:1784
// bools

Misn05Mission.cpp:1789
// floats

Misn05Mission.cpp:1794
// Handles

Misn05Mission.cpp:1799
// ints

Misn05Mission.cpp:1831
// bools

Misn05Mission.cpp:1836
// floats

Misn05Mission.cpp:1841
// Handles

Misn05Mission.cpp:1846
// ints

Misn05Mission.cpp:1862
// this is broken right now
]==]
