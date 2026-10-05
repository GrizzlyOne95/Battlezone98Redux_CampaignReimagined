-- misn03mission.lua

-- Compatibility for 1.5
SetLabel = SetLabel or SetLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})
local exu = require("exu")
-- MultSTMission creates a player craft and (normally) a free recycler during
-- native Init, before Start. Keep the authored Montana as the only recycler.
-- EXU documents this as a loose/pre-start call; never move it into Start.
if type(IsNetGame) == "function" and IsNetGame() then
    assert(exu.DisableStartingRecycler and exu.GetMyNetID,
        "misn03 co-op requires the bundled EXU multiplayer hooks")
    exu.DisableStartingRecycler()
end
local aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")
local subtit = require("ScriptSubtitles")
local PersistentConfig = require("PersistentConfig")
local autosave = require("AutoSave")
local PlayerPilotMode = require("PlayerPilotMode")
local CRCoop = require("CRCoop")

local LEADER_TEAM = 1
local ENEMY_TEAM = 5

local PHASE_DEFENSE = 1
local PHASE_FORTIFY = 2

local difficulty = 2
local M
local TRACE_UPDATE_CALLS = false

-- Mission presentation transport. Only the campaign leader runs the mission
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
    SetMaxHealth = SetMaxHealth, SetCurHealth = SetCurHealth,
    SucceedMission = SucceedMission, FailMission = FailMission,
    CameraReady = CameraReady, CameraPath = CameraPath,
    CameraFinish = CameraFinish, CameraCancelled = CameraCancelled,
    Play = subtit.Play, Queue = subtit.Queue, Stop = subtit.Stop,
}
local cameraSkipped, localCameraActive = false, false

-- Co-op trace of every native CameraReady/CameraFinish (role, time, whether a
-- camera was already active) so an unbalanced pair is visible in BZLogger next
-- to the engine's "Camera Stack 0verfow". Cinematic-rate, network games only.
do
    local ready, finish = native.CameraReady, native.CameraFinish
    local function Trace(call)
        if not CRCoop.IsNetworkGame() then return end
        print(string.format("[misn03 camera] %s %s t=%.2f active=%s",
            CRCoop.IsAuthority() and "host" or "guest", call, GetTime(), tostring(localCameraActive)))
    end
    native.CameraReady = function(...) Trace("Ready"); return ready(...) end
    native.CameraFinish = function(...) Trace("Finish"); return finish(...) end
end

local events, acknowledgements = {}, {}
local receivedEvent = 0
local nextEventSend, nextCameraSend = 0, 0
local cameraFrame, cameraGeneration, cameraSerial = nil, 0, 0
local remoteCameraSerial, localCameraGeneration = 0, 0
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
        difficulty = ...
        M.coopDifficulty = difficulty
        if exu.SetDifficulty then exu.SetDifficulty(difficulty) end
    elseif op == "SetMaxHealth" then
        local h, value = ...
        -- Native SetMaxHealth only assigns a local field; stock state packets
        -- carry health/fractions, not this mission's custom maximum. Preserve
        -- the replica's latest health fraction until the next owner update.
        local fraction = GetHealth(h)
        native.SetMaxHealth(h, value)
        native.SetCurHealth(h, fraction * value)
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
local function SetMaxHealth(...) return Present("SetMaxHealth", ...) end
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
local function CameraPath(path, height, speed, target)
    cameraFrame = { path, height, speed, target }
    if CRCoop.IsNetworkGame() and native.CameraCancelled() then
        cameraSkipped = true
        if localCameraActive then native.CameraFinish() end
        localCameraActive = false
    end
    if not cameraSkipped then return native.CameraPath(path, height, speed, target) end
end
local function CameraCancelled()
    -- A player's skip releases only their own camera; never skips shared
    -- destruction, transport orders, or the success gate for everyone else.
    if CRCoop.IsNetworkGame() then return false end
    return native.CameraCancelled()
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
    local generation, path, height, speed, target = unpackArgs(remoteCamera)
    if path == "" or M.coopResult then
        if localCameraActive then native.CameraFinish() end
        localCameraActive = false
        return
    end
    if generation ~= localCameraGeneration then
        localCameraGeneration = generation
        cameraSkipped = false
    end
    if cameraSkipped or not IsValid(target) then return end
    if not localCameraActive then
        native.CameraReady()
        localCameraActive = true
    elseif native.CameraCancelled() then
        cameraSkipped = true
        localCameraActive = false
        native.CameraFinish()
        return
    end
    native.CameraPath(path, height, speed, target)
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
            Send(0, "C", cameraSerial, cameraGeneration, "", 0, 0)
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
        local seq, generation, path, height, speed, target = ...
        if type(seq) == "number" and seq > remoteCameraSerial and type(generation) == "number" and
            type(path) == "string" and type(height) == "number" and type(speed) == "number" then
            remoteCameraSerial = seq
            remoteCamera = { generation, path, height, speed, target }
        end
        return true
    end
    local seq, op, expires = ...
    if type(seq) ~= "number" or type(op) ~= "string" or type(expires) ~= "number" then return true end
    if seq == receivedEvent + 1 and (native[op] or op == "Resources" or op == "Difficulty") then
        local args = { select(4, ...) }
        -- Dynamic handles can arrive after the Lua packet. Withhold the ACK
        -- until the next retransmission resolves it, rather than losing markers.
        local missing = (op == "SetObjectiveOn" or op == "SetObjectiveName" or op == "SetUserTarget" or
            op == "SetMaxHealth") and
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

local function TraceUpdateCall(label, fn, ...)
    if type(fn) ~= "function" then
        return nil
    end

    if not TRACE_UPDATE_CALLS then
        return fn(...)
    end

    local args = { ... }
    local ok, result = xpcall(function()
        return fn((table.unpack or unpack)(args))
    end, function(err)
        local text = tostring(err)
        if debug and type(debug.traceback) == "function" then
            return debug.traceback(text, 2)
        end
        return text
    end)

    if not ok then
        print("[lua-trace] " .. label .. " failed: " .. tostring(result))
        error(result, 0)
    end

    return result
end

-- Helper for AI
local function SetupAI(preserveExisting)
    local playerTeam, enemyTeam
    if preserveExisting and aiCore.ActiveTeams and aiCore.ActiveTeams[LEADER_TEAM] and aiCore.ActiveTeams[ENEMY_TEAM] then
        playerTeam, enemyTeam = aiCore.ActiveTeams[LEADER_TEAM], aiCore.ActiveTeams[ENEMY_TEAM]
    else
        playerTeam, enemyTeam = DiffUtils.SetupTeams(aiCore.Factions.NSDF, aiCore.Factions.CCA, ENEMY_TEAM)
    end

    -- Team 1 is fully manual apart from explicit PlayerPilotMode support.
    playerTeam:SetConfig("manageFactories", false)
    playerTeam:SetConfig("manageBase", false)
    playerTeam:SetConfig("manageTacticalOrders", false)
    playerTeam:SetConfig("autoManage", false)
    playerTeam:SetConfig("autoRepairWingmen", PersistentConfig.Settings.AutoRepairWingmen)
    playerTeam:SetConfig("enableParatroopers", false)

    -- Mission 03's Team 5 force is entirely mission-scripted. Keep the shared
    -- aiCore team object available, but disable strategic production/automation.
    enemyTeam:SetConfig("manageFactories", false)
    enemyTeam:SetConfig("manageBase", false)
    enemyTeam:SetConfig("manageTacticalOrders", false)
    enemyTeam:SetConfig("autoManage", false)
    enemyTeam:SetConfig("autoBuild", false)
    enemyTeam:SetConfig("enableParatroopers", false)
end

local function BootstrapPlayerSideAI()
    local restoreIndependence = {}

    -- AddObject already keeps scripted Team 5 units out of aiCore. Bootstrap
    -- also scans the live world, so temporarily lock Team 5 craft out of that
    -- scan and restore their original independence immediately afterward.
    if type(GetIndependence) == "function" and type(SetIndependence) == "function" then
        for h in AllCraft() do
            if h and IsValid(h) and GetTeamNum(h) == ENEMY_TEAM then
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

    -- Add only aiSpecial combat behavior to pre-placed scripted units. This
    -- does not put them into production, squad, or base-management lists.
    for h in AllObjects() do
        if h and IsValid(h) and GetTeamNum(h) == ENEMY_TEAM then
            aiCore.AddSpecialObject(h)
        end
    end
end

local function PilotModeCanManageHandle(h)
    if not h or not IsValid(h) then
        return false
    end
    if CRCoop.IsNetworkGame() and not IsLocal(h) then return false end

    if h == M.rescue1 or h == M.rescue2 or h == M.help1 or h == M.help2 then
        return false
    end

    -- In co-op, never let Pilot Mode claim a human player's craft. Stock
    -- GetPlayerHandle(team) is not usable for remote players, so CRCoop tracks
    -- current player handles through CreatePlayer/AddPlayer plus Send/Receive.
    -- Until that registry is complete, fail closed and manage no handles.
    if CRCoop.IsNetworkGame() and not CRCoop.HasAllPlayerHandles() then
        return false
    end

    return not CRCoop.IsHumanCraft(h)
end

local function GetPilotModeObjectiveContext()
    if M.lost or M.final_objective or M.end_game then
        return { key = "terminal", objectiveIds = {}, actions = {} }
    end

    -- The mission keeps scripted transports and the recycler under its own
    -- handles. Pilot Mode may support the objective with ordinary combat
    -- craft, but never retasks those mission-owned objects.
    if not M.movie_over then
        local actions = {}
        if IsAlive(M.solar1) then
            actions[#actions + 1] = { id = "defend-command-tower", command = "defend", target = M.solar1 }
        elseif IsAlive(M.solar2) then
            actions[#actions + 1] = { id = "defend-solar-array", command = "defend", target = M.solar2 }
        end
        return { key = "array-defense", objectiveIds = { "misn0301.otf" }, actions = actions }
    end

    if not M.third_objective then
        local target = IsAlive(M.rescue1) and M.rescue1 or M.rescue2
        return {
            key = "evacuation",
            objectiveIds = { "misn0311.otf", "misn0312.otf", "misn0303.otf" },
            actions = target and { { id = "escort-transport", command = "follow", target = target } } or {},
        }
    end

    return {
        key = "launch",
        objectiveIds = { "misn0313.otf", "misn0304.otf" },
        actions = IsAlive(M.launch)
            and { { id = "hold-launch-pad", command = "defend", target = M.launch } } or {},
    }
end

local function InitializePilotMode()
    PlayerPilotMode.Initialize({
        profile = {
            autoManage = false,
            autoRescue = true,
            stickToPlayer = false,
            manageFactories = false,
            autoBuild = false,
        },
        shouldManageHandle = PilotModeCanManageHandle,
        getObjectiveContext = GetPilotModeObjectiveContext,
    }, M.playerPilotModeState)
end

-- Mission State
M = {
    -- Bools
    first_wave_done = false,
    second_wave_done = false,
    third_wave_done = false,
    fourth_wave_done = false,
    fifth_wave_done = false,
    turret_move_done = false,
    rescue_move_done = false,
    help_spawn = false,
    help_arrive = false,
    end_game = false,
    trans_underway = false,
    ambush_message = false,
    start_done = false,
    first_objective = false,
    second_objective = false,
    third_objective = false,
    final_objective = false,
    special_objective = false,
    start_retreat = false,
    done_retreat = false,
    new_message_start = false,
    dead1 = false,
    dead2 = false,
    dead3 = false,
    camera_on = false,
    camera_off = false,
    help_stop1 = false,
    help_stop2 = false,
    recycle_stop = false,
    message1 = false,
    scavhunt = false,
    scavhunt2 = false,
    lost = false,
    camera_ready = false,
    start_movie = false,
    movie_over = false,
    remove_props = false,
    more_show = false,
    tanks_go = false,
    camera_2 = false,
    show_tank_attack = false,
    tower_dead = false,
    climax1 = false,
    climax2 = false,
    clear_debis = false,
    last_blown = false,
    end_shot = false,
    clean_sweep = false,
    startfinishingmovie = false,
    turrets_set = false,
    speach2 = false,
    second_warning = false,
    last_warning = false,

    -- New Bools for Enhancements
    solar1_warned = false,
    solar2_warned = false,
    patrols_spawned = false,
    apc_arrived_at_base = false,
    apc_bonus_pilots_spawned = false,
    recycler_follow_transport = false,
    recycler_follow_launch = false,
    recycler_pack_transport_issued = false,
    recycler_follow_transport_issued = false,
    recycler_pack_launch_issued = false,
    recycler_follow_launch_issued = false,
    patrol_soldiers = { nil, nil, nil },
    patrol_respawn_timers = { 0, 0, 0 },

    -- Floats
    next_second = 0.0,
    alarm_sound_timer = 0.0,
    retreat_timer = 0.0,
    next_wave = 99999.0,
    second_wave_time = 99999.0,
    ambush_message_time = 99999.0,
    new_message_time = 99999.0,
    apc_spawn_time = 99999.0,
    pull_out_time = 99999.0,
    third_wave_time = 99999.0,
    fourth_wave_time = 99999.0,
    fifth_wave_time = 99999.0,
    turret_move_time = 99999.0,
    wave3_time = 99999.0,
    wave4_time = 99999.0,
    camera_off_time = 99999.0,
    support_time = 99999.0,
    movie_time = 99999.0,
    new_unit_time = 99999.0,
    next_shot = 99999.0,
    kill_tower = 99999.0,
    clear_debis_time = 99999.0,
    unit_check = 99999.0,
    clean_sweep_time = 99999.0,
    final_check = 99999.0,

    -- Handles
    user = nil,
    avrecycler = nil,
    geyser = nil,
    cam_geyser = nil,
    shot_geyser = nil,
    scav1 = nil,
    scav2 = nil,
    scav3 = nil,
    scav4 = nil,
    scav5 = nil,
    scav6 = nil,
    crate1 = nil,
    crate2 = nil,
    crate3 = nil,
    rescue1 = nil,
    rescue2 = nil,
    rescue3 = nil,
    wave1_1 = nil,
    wave1_2 = nil,
    wave1_3 = nil,
    wave2_1 = nil,
    wave2_2 = nil,
    wave2_3 = nil,
    wave3_1 = nil,
    wave3_2 = nil,
    wave3_3 = nil,
    wave4_1 = nil,
    wave4_2 = nil,
    wave4_3 = nil,
    wave5_1 = nil,
    wave5_2 = nil,
    wave5_3 = nil,
    wave6_1 = nil,
    wave6_2 = nil,
    wave6_3 = nil,
    wave7_1 = nil,
    wave7_2 = nil,
    wave7_3 = nil,
    wave7_4 = nil,
    wave7_5 = nil,
    wave7_6 = nil,
    turret1 = nil,
    turret2 = nil,
    turret3 = nil,
    turret4 = nil,
    spawn_point1 = nil,
    spawn_point2 = nil,
    launch = nil,
    nest = nil,
    solar1 = nil,
    solar2 = nil,
    solar3 = nil,
    solar4 = nil,
    help1 = nil,
    help2 = nil,
    build1 = nil,
    build2 = nil,
    build3 = nil,
    build4 = nil,
    build5 = nil,
    hanger = nil,
    prop1 = nil,
    prop2 = nil,
    prop3 = nil,
    prop4 = nil,
    prop5 = nil,
    prop6 = nil,
    prop7 = nil,
    prop8 = nil,
    prop9 = nil,
    prop0 = nil,
    guy1 = nil,
    guy2 = nil,
    guy3 = nil,
    guy4 = nil,
    box1 = nil,
    sucker = nil,
    avturret1 = nil,
    avturret2 = nil,
    avturret3 = nil,
    avturret4 = nil,
    avturret5 = nil,
    avturret6 = nil,
    avturret7 = nil,
    avturret8 = nil,
    avturret9 = nil,
    avturret10 = nil,

    -- Integers
    x = 4000,
    z = 1,
    y = 1,
    audmsg = nil,
    loading_done = false,
    loadGracePeriod = 0,

    -- Tables
    solar_list = { false, false, false }, -- Track objective status for solar2, solar3, solar4

    -- Input State Logic is now handled by PersistentConfig module
}

local hardDifficultyObjective = { "hard_diff", "yellow", 8.0, "High Difficulty: Enemy presence intensified." }
local easyDifficultyObjective = { "easy_diff", "blue", 8.0, "Low Difficulty: Enemy presence reduced." }

local function RefreshDifficulty()
    if exu and exu.GetDifficulty then
        local d = exu.GetDifficulty()
        if d ~= nil then
            difficulty = d
        end
    end
    return difficulty
end

local function ApplyDifficultyObjectives()
    if difficulty >= 3 then
        AddObjective(hardDifficultyObjective[1], hardDifficultyObjective[2], hardDifficultyObjective[3], hardDifficultyObjective[4])
    elseif difficulty <= 1 then
        AddObjective(easyDifficultyObjective[1], easyDifficultyObjective[2], easyDifficultyObjective[3], easyDifficultyObjective[4])
    end
end

local function ApplyQOL()
    if exu then
        if exu.SetReticleRange then
            exu.SetReticleRange(600)
        end
        if exu.SetOrdnanceVelocInheritance then
            exu.SetOrdnanceVelocInheritance(true)
        end
        if exu.SetGlobalTurbo then
            exu.SetGlobalTurbo(true)
        end
    end

    if PersistentConfig and PersistentConfig.Initialize and not M.persistentConfigInitialized then
        M.persistentConfigInitialized = true
        PersistentConfig.Initialize()
    end
end

local function TurboValue(team)
    if CRCoop.IsHumanTeam(team) then
        return true
    end
    if team ~= 0 and difficulty and difficulty > 3 then
        return true
    end
end

local function ApplyTurbo(h)
    if not (exu and exu.SetUnitTurbo and IsCraft(h)) then
        return
    end
    if CRCoop.IsNetworkGame() and not IsLocal(h) then return end
    local value = TurboValue(GetTeamNum(h))
    if value ~= nil and value ~= false then
        exu.SetUnitTurbo(h, value)
    else
        exu.SetUnitTurbo(h, false)
    end
end

local function ApplyTurboToAll()
    if not (exu and exu.SetUnitTurbo) then
        return
    end
    for h in AllCraft() do
        ApplyTurbo(h)
    end
end

local function CountHumanUnitsNearObject(object, distance, odf)
    local count = 0
    for team = 1, 4 do
        count = count + CountUnitsNearObject(object, distance, team, odf)
    end
    return count
end

local function PresentMissionPhase()
    local phase = CRCoop.GetMissionPhase()
    local presented = M.coopPresentedPhase or 0

    if phase <= presented then
        return
    end

    local handled = false

    if phase == PHASE_DEFENSE then
        ClearObjectives()
        AddObjective("misn0301.otf", "white")
        if not M.message1 then
            M.audmsg = subtit.Play("misn0311.wav")
            M.message1 = true
        end
        handled = true
    elseif phase == PHASE_FORTIFY then
        subtit.Play("misn0312.wav")
        ClearObjectives()
        AddObjective("misn0302.otf", "white")
        AddObjective("misn0301.otf", "white")
        M.done_retreat = true
        handled = true
    end

    if handled then
        M.coopPresentedPhase = phase
    end
end

local function UpdateModules(dt)
    if exu and exu.UpdateOrdnance then
        TraceUpdateCall("misn03.UpdateModules exu.UpdateOrdnance", exu.UpdateOrdnance)
    end
    if subtit and subtit.Update then
        TraceUpdateCall("misn03.UpdateModules subtit.Update", subtit.Update)
    end
    if PersistentConfig then
        if PersistentConfig.UpdateInputs then
            TraceUpdateCall("misn03.UpdateModules PersistentConfig.UpdateInputs", PersistentConfig.UpdateInputs)
        end
        if PersistentConfig.UpdateHeadlights then
            TraceUpdateCall("misn03.UpdateModules PersistentConfig.UpdateHeadlights", PersistentConfig.UpdateHeadlights)
        end
    end
end

function Save()
    M.playerPilotModeState = PlayerPilotMode.Save()
    return M, aiCore.Save(), M.playerPilotModeState
end

function Load(missionData, aiData, pilotModeData)
    M = missionData or M
    M.playerPilotModeState = pilotModeData or M.playerPilotModeState
    if aiData then
        aiCore.Load(aiData)
    end
    M.loading_done = false
    M.loadGracePeriod = GetTime() + 2.0
    -- This flag rides along inside the saved M table, so without clearing it a
    -- loaded game would skip PersistentConfig.Initialize entirely — no config
    -- load, no settings apply: broken PDA text, subtitles, radar and lighting.
    M.persistentConfigInitialized = false
end

function Start()
    M.x = 4000
    M.z = 1
    M.y = 1

    M.avrecycler = GetHandle("avrec3-1_recycler")
    native.SetObjectiveName(M.avrecycler, "Recycler Montana")
    M.scav1 = GetHandle("scav1")
    M.scav2 = GetHandle("scav2")
    M.wave1_1 = GetHandle("svfigh1")
    M.wave1_2 = GetHandle("svfigh2")
    M.wave1_3 = nil -- 0 in C++
    M.turret1 = GetHandle("enemyturret_1")
    M.turret2 = GetHandle("enemyturret_2")
    M.turret3 = GetHandle("enemyturret_3")
    M.turret4 = GetHandle("enemyturret_4")
    M.geyser = GetHandle("geyser1")
    M.solar1 = GetHandle("solar1")
    M.solar2 = GetHandle("solar2")
    M.solar3 = GetHandle("solar3")
    M.solar4 = GetHandle("solar4")
    M.launch = GetHandle("launch_pad")
    M.build1 = GetHandle("build1")
    M.build3 = GetHandle("build3")
    M.build4 = GetHandle("build4")
    M.build5 = GetHandle("build5")
    M.hanger = GetHandle("hanger")
    M.cam_geyser = GetHandle("cam_geyser")
    M.shot_geyser = GetHandle("shot_geyser")
    M.box1 = GetHandle("box1")
    M.crate1 = GetHandle("crate1")
    M.crate2 = GetHandle("crate2")
    M.crate3 = GetHandle("crate3")
    M.guy1 = GetHandle("guy1")
    M.guy2 = GetHandle("guy2")
    M.sucker = GetHandle("sucker")

    M.TPS = M.TPS or 20
    RefreshDifficulty()
    ApplyDifficultyObjectives()
    ApplyQOL()
    CRCoop.Initialize({
        getLocalPlayerId = function()
            if exu and exu.GetMyNetID then
                return exu.GetMyNetID()
            end
            return nil
        end,
        leaderTeam = LEADER_TEAM,
        humanTeamMin = 1,
        humanTeamMax = 4,
    })
    CRCoop.ApplyCoopAlliances(ENEMY_TEAM)
    if CRCoop.IsAuthority() then
        SetupAI()
        BootstrapPlayerSideAI()
        InitializePilotMode()
    end
    ApplyTurboToAll()
    subtit.Initialize("durations.csv")
    if CRCoop.IsNetworkGame() and exu.SetLives then exu.SetLives(999) end
    M.loading_done = true
end

function CreatePlayer(id, name, team)
    CRCoop.CreatePlayer(id, name, team)
    CRCoop.ApplyCoopAlliances(ENEMY_TEAM)
end

function AddPlayer(id, name, team)
    CRCoop.AddPlayer(id, name, team)
    CRCoop.ApplyCoopAlliances(ENEMY_TEAM)
end

function DeletePlayer(id, name, team)
    CRCoop.DeletePlayer(id)
end

function Receive(from, kind, ...)
    if ReceivePresentation(from, kind, ...) then return true end
    if CRCoop.Receive(from, kind, ...) then
        return true
    end
    return false
end

function AddObject(h)
    local team = GetTeamNum(h)

    if PersistentConfig and PersistentConfig.OnObjectCreated then
        PersistentConfig.OnObjectCreated(h)
    end
    ApplyTurbo(h)

    -- Native MultST owns local player craft/respawns. Only the host registers
    -- mission AI, and PilotMode's predicate excludes every tracked human.
    if not CRCoop.IsAuthority() then return end

    if IsOdf(h, "avturr") then
        if M.avturret1 == nil then
            M.avturret1 = h
        elseif M.avturret2 == nil then
            M.avturret2 = h
        elseif M.avturret3 == nil then
            M.avturret3 = h
        elseif M.avturret4 == nil then
            M.avturret4 = h
        elseif M.avturret5 == nil then
            M.avturret5 = h
        elseif M.avturret6 == nil then
            M.avturret6 = h
        elseif M.avturret7 == nil then
            M.avturret7 = h
        elseif M.avturret8 == nil then
            M.avturret8 = h
        elseif M.avturret9 == nil then
            M.avturret9 = h
        elseif M.avturret10 == nil then
            M.avturret10 = h
        end
    elseif IsOdf(h, "avscav") then
        if M.scav3 == nil then
            M.scav3 = h
        elseif M.scav4 == nil then
            M.scav4 = h
        elseif M.scav5 == nil then
            M.scav5 = h
        elseif M.scav6 == nil then
            M.scav6 = h
        end
    end

    -- Register player-team spawns immediately for PlayerPilotMode. Team 5
    -- waves remain outside full aiCore ownership, but receive the reusable
    -- aiSpecial combat layer.
    if team == 1 then
        PlayerPilotMode.AddObject(h)
    elseif team == ENEMY_TEAM then
        aiCore.AddSpecialObject(h)
    end
end

function Update()
    if GetTime() < (M.loadGracePeriod or 0) then
        return
    end
    if not M.loading_done then
        RefreshDifficulty()
        ApplyDifficultyObjectives()
        ApplyQOL()
        if CRCoop.IsAuthority() then
            InitializePilotMode()
            SetupAI(true)
            BootstrapPlayerSideAI()
        end
        ApplyTurboToAll()
        M.loading_done = true
    end
    M.user = GetPlayerHandle()
    CRCoop.Update()
    UpdatePresentationTransport()
    TraceUpdateCall("misn03.Update UpdateModules", UpdateModules, 1.0 / (M.TPS or 20))
    if M.coopResult or M.coopPendingResult then return end

    -- Player 1 is the campaign leader. If that player leaves, do not allow a
    -- Redux network-host migration to inherit campaign simulation authority.
    if CRCoop.IsNetworkGame() and CRCoop.HasLeaderDeparted() then
        if not M.coopLeaderDepartureHandled then
            M.coopLeaderDepartureHandled = true
            if localCameraActive then native.CameraFinish() end
            localCameraActive = false
            native.FailMission(GetTime() + 1.0)
        end
        return
    end

    -- coop_spawn1 sits exactly on the BZN's offline user craft, so MultST drops
    -- the leader's craft on top of it. Waiting for the start gate (registry +
    -- load grace) left them overlapping for seconds; remove it on the first
    -- authority frame instead. It is a Team-1 craft, so only the leader (the
    -- local player on the authority) could have been placed in it.
    if CRCoop.IsNetworkGame() and CRCoop.IsAuthority() and not M.coopOfflineCraftCleared then
        M.coopOfflineCraftCleared = true
        local offlineCraft = GetHandle("myCar_hover")
        local leaderCraft = GetPlayerHandle()
        local inUse = not IsValid(offlineCraft) or offlineCraft == leaderCraft
            or CRCoop.IsHumanCraft(offlineCraft)
        if IsValid(leaderCraft) then
            local p = GetPosition(leaderCraft)
            print(string.format("[misn03 spawn] leader craft at %.1f,%.1f,%.1f", p.x, p.y, p.z))
        end
        print("[misn03 spawn] offline craft " .. (IsValid(offlineCraft) and (inUse and "kept (human)" or "removed") or "absent"))
        if not inUse then RemoveObject(offlineCraft) end
    end

    -- Lifecycle Send/Receive traffic is not reliable during join transitions.
    -- Pause campaign simulation until every current human has a usable handle
    -- and the retrying leader/client handshake has completed.
    if CRCoop.IsNetworkGame() and CRCoop.HasUnsupportedPlayerTeam() then
        if not M.coopUnsupportedTeamWarned then
            M.coopUnsupportedTeamWarned = true
            if type(DisplayMessage) == "function" then
                DisplayMessage("Campaign co-op supports human teams 1-4 only.")
            end
            print("[CRCoop] Unsupported human team detected; campaign simulation paused.")
        end
        return
    end

    if CRCoop.IsNetworkGame() and not CRCoop.IsSessionReady() then
        return
    end

    if CRCoop.IsNetworkGame() and CRCoop.HasLateJoiners() then
        if not M.coopLateJoinWarned then
            M.coopLateJoinWarned = true
            if type(DisplayMessage) == "function" then
                DisplayMessage("Late join/rejoin detected. Restart the mission to avoid world-state desync.")
            end
            print("[CRCoop] Late join/rejoin detected; world reconciliation is not yet proven safe.")
        end
        return
    end

    if not M.coopMissionStarted then
        CRCoop.MarkMissionStarted()
        M.coopMissionStarted = true
    end

    -- Get difficulty for dynamic adjustments (0=Very Easy, 1=Easy, 2=Medium, 3=Hard, 4=Very Hard)
    local diff = 2
    if exu and exu.GetDifficulty then diff = exu.GetDifficulty() end
    local isAuthority = CRCoop.IsAuthority()

    if isAuthority then
        TraceUpdateCall("misn03.Update PlayerPilotMode.Update", PlayerPilotMode.Update)
        TraceUpdateCall("misn03.Update aiCore.Update", aiCore.Update)
    end
    if not CRCoop.IsNetworkGame() and autosave and autosave.Update then
        TraceUpdateCall("misn03.Update autosave.Update", autosave.Update, 1.0 / (M.TPS or 20))
    end


    -- Update Objective Health Status
    if IsAlive(M.solar1) then
        native.SetObjectiveName(M.solar1, "Command Tower: " .. math.floor(GetHealth(M.solar1) * 100) .. "%")
    end
    if IsAlive(M.solar2) then
        native.SetObjectiveName(M.solar2, "Solar Array: " .. math.floor(GetHealth(M.solar2) * 100) .. "%")
    end
    if IsAlive(M.solar3) then
        native.SetObjectiveName(M.solar3, "Solar Array: " .. math.floor(GetHealth(M.solar3) * 100) .. "%")
    end
    if IsAlive(M.solar4) then
        native.SetObjectiveName(M.solar4, "Solar Array: " .. math.floor(GetHealth(M.solar4) * 100) .. "%")
    end

    -- Every branch below can mutate the world or mission progression. Clients
    -- consume the reliable presentation stream above and never run these gates.
    if not isAuthority then return end
    if M.lost then return end

    if not M.start_done then
        ApplyQOL()

        if CRCoop.IsNetworkGame() then
            -- MultST creates its own local player craft. Some map-loading
            -- paths retain the BZN's offline user craft as an extra Team-1
            -- vehicle. Remove it only after the human registry is complete,
            -- and never if the engine reused it as a current human handle.
            local offlineCraft = GetHandle("myCar_hover")
            if IsValid(offlineCraft) and not CRCoop.IsHumanCraft(offlineCraft) then
                RemoveObject(offlineCraft)
            end
        end

        -- Team resources are simulation state. In a network game the host owns
        -- these mutations; every peer still initializes its local presentation.
        if isAuthority then
            local startingScrap = math.max(4, DiffUtils.ScaleRes(10))
            local startingPilots = DiffUtils.ScaleRes(10)
            Present("Difficulty", RefreshDifficulty())
            CRCoop.ForEachHumanTeam(function(team)
                if CRCoop.IsNetworkGame() then
                    Present("Resources", team, startingScrap, startingPilots)
                else
                    SetScrap(team, startingScrap)
                    SetPilot(team, startingPilots)
                end
            end)
            SetScrap(ENEMY_TEAM, 40) -- Give enemy AI starting scrap
        end

        subtit.Initialize("durations.csv")

        SetObjectiveOn(M.solar1)
        SetObjectiveName(M.solar1, "Command Tower")
        SetCritical(M.solar1, true)

        -- Solar Array Objectives (Difficulty Based)
        -- We only mark the number we are required to save
        local diff = (exu and exu.GetDifficulty and exu.GetDifficulty()) or 2
        local required = 1
        if diff == 3 then
            required = 2
        elseif diff > 3 then
            required = 3
        end

        SetObjectiveOn(M.solar2)
        SetObjectiveName(M.solar2, "Solar Array")
        SetCritical(M.solar2, false)
        M.solar_list[1] = true

        if required >= 2 and IsAlive(M.solar3) then
            SetObjectiveOn(M.solar3)
            SetObjectiveName(M.solar3, "Solar Array")
            SetCritical(M.solar3, false)
            M.solar_list[2] = true
        end
        if required >= 3 and IsAlive(M.solar4) then
            SetObjectiveOn(M.solar4)
            SetObjectiveName(M.solar4, "Solar Array")
            SetCritical(M.solar4, false)
            M.solar_list[3] = true
        end

        -- Difficulty Health Scaling for Critical Buildings
        local m = DiffUtils.Get()
        local health_mod = m.res -- reuse resource mult for simplicity or inverse?
        -- User didn't specify health but keep it scaled.

        if isAuthority then
            if IsAlive(M.solar1) then
                SetMaxHealth(M.solar1, GetMaxHealth(M.solar1) * health_mod)
                SetCurHealth(M.solar1, GetMaxHealth(M.solar1))
            end
            if IsAlive(M.solar2) then
                SetMaxHealth(M.solar2, GetMaxHealth(M.solar2) * health_mod)
                SetCurHealth(M.solar2, GetMaxHealth(M.solar2))
            end

            Goto(M.avrecycler, "recycle_point")

            -- Randomized mission schedule is authoritative. Clients will
            -- eventually consume synchronized phase changes rather than
            -- independently rolling these timers.
            M.second_wave_time = GetTime() + DiffUtils.ScaleTimer(200.0) + math.random(-10, 20)
            M.third_wave_time = GetTime() + DiffUtils.ScaleTimer(310.0) + math.random(-15, 30)
            M.fourth_wave_time = GetTime() + DiffUtils.ScaleTimer(430.0) + math.random(-20, 40)

            M.apc_spawn_time = GetTime() + 530.0
            M.support_time = GetTime() + 430.0
            M.next_second = GetTime() + 1.0
            M.unit_check = GetTime() + 60.0
        end

        M.start_done = true
        if isAuthority then
            CRCoop.SetMissionPhase(PHASE_DEFENSE)
        end
    end

    PresentMissionPhase()

    -- Alarm for Command Tower
    if IsAlive(M.solar1) and GetHealth(M.solar1) < 1.0 then
        if not M.alarm_sound_timer or GetTime() > M.alarm_sound_timer then
            StartSound("misn0708.wav", M.solar1)
            M.alarm_sound_timer = GetTime() + 2.0
        end
    end

    -- Dynamic Health Warnings
    if IsAlive(M.solar1) and not M.solar1_warned then
        if GetHealth(M.solar1) < 0.4 then
            -- Using a generic warning sound or reusing a mission sound
            subtit.Play("misn0708.wav")
            UpdateObjective("misn0301.otf", "yellow")
            M.solar1_warned = true
        end
    end

    if IsAlive(M.solar2) and not M.solar2_warned then
        if GetHealth(M.solar2) < 0.4 then
            subtit.Play("misn0708.wav")
            UpdateObjective("misn0301.otf", "yellow")
            M.solar2_warned = true
        end
    end

    -- Solar Array Defense Logic (Count Check)
    local solarCount = 0
    if IsAlive(M.solar2) then solarCount = solarCount + 1 end
    if IsAlive(M.solar3) then solarCount = solarCount + 1 end
    if IsAlive(M.solar4) then solarCount = solarCount + 1 end

    local required = 1
    if diff == 3 then
        required = 2 -- Hard
    elseif diff > 3 then
        required = 3
    end -- Very Hard

    -- Dynamic Objective Update: Ensure we always show 'required' number of living arrays
    -- If S2 dies (and was marked), reveal S3, etc.
    local visibleCount = 0
    local arrays = { M.solar2, M.solar3, M.solar4 }

    for i, h in ipairs(arrays) do
        if IsAlive(h) and M.solar_list[i] then
            visibleCount = visibleCount + 1
        end
    end

    if visibleCount < required then
        -- Find a hidden survivor and mark it
        for i, h in ipairs(arrays) do
            if IsAlive(h) and not M.solar_list[i] then
                SetObjectiveOn(h)
                SetObjectiveName(h, "Solar Array")
                SetCritical(h, false)
                M.solar_list[i] = true
                visibleCount = visibleCount + 1
                if visibleCount >= required then break end
            end
        end
    end

    -- Defense ends at evacuation; the outro deliberately destroys all arrays.
    -- Running this gate during that film incorrectly failed a completed defense.
    if solarCount < required and not M.second_objective and not M.lost and not M.final_objective then
        -- Trigger Failure
        FailMission(GetTime() + 5.0)
        M.lost = true
    end

    -- Foot Soldier Patrols
    if isAuthority and M.start_done and IsAlive(M.build5) then
        M.patrol_soldiers = M.patrol_soldiers or { nil, nil, nil }
        M.patrol_respawn_timers = M.patrol_respawn_timers or { 0, 0, 0 }

        for i = 1, 3 do
            local soldier = M.patrol_soldiers[i]

            if not IsAlive(soldier) then
                if M.patrol_respawn_timers[i] == 0 then
                    -- Schedule spawn
                    local delay = 30.0
                    if not M.patrols_spawned then delay = 1.0 + (i * 2.0) end -- Initial spawn staggered
                    M.patrol_respawn_timers[i] = GetTime() + delay
                elseif GetTime() > M.patrol_respawn_timers[i] then
                    -- Spawn now
                    local pos = GetPositionNear(GetPosition(M.build5), 0, 10)
                    local new_soldier = BuildObject("aspilop", 1, pos)
                    if IsAlive(new_soldier) then
                        -- Jump!
                        local vel = GetVelocity(new_soldier)
                        vel.y = vel.y + 15.0
                        SetVelocity(new_soldier, vel)

                        -- Orders
                        if i == 1 then
                            SetPathLoop("footpatrol")
                            Patrol(new_soldier, "footpatrol", 1)
                        elseif i == 2 then
                            Defend2(new_soldier, M.solar1)
                        elseif i == 3 then
                            Defend2(new_soldier, M.solar2)
                        end

                        M.patrol_soldiers[i] = new_soldier
                        M.patrol_respawn_timers[i] = 0
                    end
                end
            end
        end
        M.patrols_spawned = true
    end

    if isAuthority and IsAlive(M.solar1) and not M.show_tank_attack then
        if GetTime() > M.next_second then
            AddHealth(M.solar1, 50)
            if IsAlive(M.solar2) then AddHealth(M.solar2, 50) end
            if IsAlive(M.solar3) then AddHealth(M.solar3, 50) end
            if IsAlive(M.solar4) then AddHealth(M.solar4, 50) end
            M.next_second = GetTime() + 1.0
        end
    end

    if isAuthority and M.start_done and GetDistance(M.avrecycler, "recycle_point") < 50.0 and not M.recycle_stop then
        SetCommand(M.avrecycler, 16, 1, M.geyser)
        M.recycle_stop = true
    end

    if isAuthority and not M.first_wave_done then
        Attack(M.wave1_1, M.solar1, 1)
        Attack(M.wave1_2, M.solar1, 1)
        M.first_wave_done = true
    end

    if isAuthority and M.first_wave_done and not M.start_retreat then
        if diff < 3 then
            if not IsAlive(M.wave1_1) then
                Retreat(M.wave1_2, "retreat_path", 1)
                M.new_message_time = GetTime() + 13.0
                M.start_retreat = true
            elseif not IsAlive(M.wave1_2) then
                Retreat(M.wave1_1, "retreat_path", 1)
                M.new_message_time = GetTime() + 10.0
                M.start_retreat = true
            end
        end
    end

    -- If all enemies are dead (regardless of difficulty), advance the plot
    if isAuthority and not IsAlive(M.wave1_1) and not IsAlive(M.wave1_2) then
        -- Only set if not already retreating (to avoid overriding timer if one died earlier)
        if not M.start_retreat then
            M.new_message_time = GetTime() + 2.0
            M.start_retreat = true
        end
    end
    if isAuthority and M.start_retreat and M.new_message_time < GetTime() and not M.done_retreat then
        M.done_retreat = true
        CRCoop.SetMissionPhase(PHASE_FORTIFY)
    end

    if not M.turrets_set and IsAlive(M.solar1) and M.unit_check < GetTime() then
        M.unit_check = GetTime() + 5.0
        M.z = CountHumanUnitsNearObject(M.solar1, 200.0, "avturr")

        if M.z > 3 then
            ClearObjectives()
            AddObjective("misn0302.otf", "green")
            AddObjective("misn0301.otf", "white")
            M.turrets_set = true
        end
    end

    local spawns = { "nspawn", "wspawn", "spawn_scrap1" }

    -- Randomized Enemy Spawns for Wave 2
    if not M.second_wave_done and M.second_wave_time < GetTime() then
        -- Randomize unit types
        local type1 = "svfigh"
        local type2 = "svfigh"

        if diff >= 2 then -- Medium: Chance for light tanks
            if math.random() > 0.5 then type1 = "svltnk" end
            if math.random() > 0.5 then type2 = "svltnk" end
        end
        if diff >= 3 then -- Hard: Guaranteed light tanks
            type1 = "svltnk"
            type2 = "svtank"
            -- Extra unit for hard difficulty
            local pos = GetPositionNear(GetPosition(spawns[math.random(1, 3)]), 0, 40)
            local extra = BuildObject("svfigh", ENEMY_TEAM, pos)
            Attack(extra, M.solar1)
        end

        local p1 = spawns[math.random(1, 3)]
        local p2 = spawns[math.random(1, 3)]
        M.wave2_1 = BuildObject(type1, ENEMY_TEAM, GetPositionNear(GetPosition(p1), 0, 40))
        M.wave2_2 = BuildObject(type2, ENEMY_TEAM, GetPositionNear(GetPosition(p2), 0, 40))

        Attack(M.wave2_1, M.solar1)
        Goto(M.wave2_2, M.solar1)

        M.second_wave_done = true
    end

    if not M.third_wave_done and M.third_wave_time < GetTime() then
        local type3 = "svfigh"
        if diff >= 3 then type3 = "svltnk" end

        local p1 = spawns[math.random(1, 3)]
        local p2 = spawns[math.random(1, 3)]
        M.wave3_1 = BuildObject(type3, ENEMY_TEAM, GetPositionNear(GetPosition(p1), 0, 40))
        M.wave3_2 = BuildObject("svfigh", ENEMY_TEAM, GetPositionNear(GetPosition(p2), 0, 40))

        Attack(M.wave3_1, M.solar1, 1)
        Attack(M.wave3_2, M.solar1, 1)

        M.third_wave_done = true
    end

    if not M.scavhunt and M.third_wave_done then
        if IsAlive(M.wave1_1) then
            Attack(M.wave1_1, M.scav1, 1)
        end
        if IsAlive(M.wave1_2) then
            Attack(M.wave1_2, M.scav1, 1)
        end
        M.scavhunt = true
    end

    if not M.fourth_wave_done and M.fourth_wave_time < GetTime() then
        local p1 = spawns[math.random(1, 3)]
        local p2 = spawns[math.random(1, 3)]
        local p3 = spawns[math.random(1, 3)]
        M.wave4_1 = BuildObject("svapc", ENEMY_TEAM, GetPositionNear(GetPosition(p1), 0, 40))
        M.wave4_2 = BuildObject("svtank", ENEMY_TEAM, GetPositionNear(GetPosition(p2), 0, 40))
        M.wave5_1 = BuildObject("svfigh", ENEMY_TEAM, GetPositionNear(GetPosition(p3), 0, 40))

        if diff >= 3 then
            local p_extra = spawns[math.random(1, 3)]
            local extra_tank = BuildObject("svtank", ENEMY_TEAM, GetPositionNear(GetPosition(p_extra), 0, 40))
            Attack(extra_tank, M.solar2, 1)
        end

        if IsAlive(M.avrecycler) then
            Attack(M.wave4_1, M.avrecycler, 1)
        elseif IsAlive(M.solar3) then
            Attack(M.wave4_1, M.solar3, 1)
        elseif IsAlive(M.solar4) then
            Attack(M.wave4_1, M.solar4, 1)
        end

        Attack(M.wave4_2, M.solar2, 1)
        M.fourth_wave_done = true
    end

    if not M.scavhunt2 and M.fourth_wave_done and IsAlive(M.wave5_1) then
        if IsAlive(M.scav1) then
            Attack(M.wave5_1, M.scav1, 1)
        -- PORT FIX: the DLL's fallback had !IsAlive(scav2), ordering an attack
        -- on a dead target and ignoring the surviving second scavenger. Use
        -- the living fallback; the wave, hunt latch and phase timing are unchanged.
        elseif IsAlive(M.scav2) then
            Attack(M.wave5_1, M.scav2, 1)
        end
        M.scavhunt2 = true
    end

    if not M.help_spawn and M.support_time < GetTime() then
        -- Spawn escort reinforcements (matches original C++ behaviour)
        local escortSpawn = GetPosition("spawn_scrap2")
        local transportSpawn = GetPosition("lpadspawn")
        M.help1 = BuildObject("avfigh", 1, GetPositionNear(escortSpawn, 0, 12))
        M.help2 = BuildObject("avtank", 1, GetPositionNear(escortSpawn, 12, 24))
        M.rescue1 = BuildObject("avapc2", 1, GetPositionNear(transportSpawn, 0, 10))
        M.rescue2 = BuildObject("avapc2", 1, GetPositionNear(transportSpawn, 12, 22))
        SetUserTarget(M.rescue1)
        Follow(M.rescue1, M.build5)
        Follow(M.rescue2, M.build5)
        Follow(M.help1, M.rescue1, 0)
        Follow(M.help2, M.rescue2, 0)
        subtit.Play("misn0314.wav")
        M.help_spawn = true
    end

    -- ORIGINAL DLL BEHAVIOR (inactive QOL alternative): the native escorts
    -- Goto solar2, stop within 75m, and re-task near the player. This port gives
    -- them Follow(rescue1/rescue2) orders above and spawns the transports early.
    -- Retain those current escort orders; reactivating the native hooks would
    -- interrupt them. Keep the entire replaced block for reconstruction.
    --[==[
if ((!help_spawn) && (support_time < Get_Time()))
	{
		help1 = BuildObject("avfigh",1,"spawn_scrap2");
		help2 = BuildObject("avtank",1,"spawn_scrap2");
		AudioMessage("misn0314.wav");
		Goto(help1, solar2, 0);
		Goto(help2, solar2, 0);
		help_spawn = true;
	}

		if ((help_spawn) && (IsAlive(help1)) && (IsAlive(solar2)) && (!help_stop1))
		{
			if (GetDistance(help1, solar2) < 75.0f)
			{
				Stop(help1, 0);
				help_stop1 = true;
			}
		}

		if ((help_spawn) && (IsAlive(help2)) && (IsAlive(solar2)) && (!help_stop2))
		{
			if (GetDistance(help2, solar2) < 75.0f)
			{
				Stop(help2, 0);
				help_stop2 = true;
			}
		}

	if ((help_spawn) && (!help_arrive) && (GetDistance(help1,user) < 50.0f))
	{
//		AudioMessage("misn0313.wav");
		Goto(help1, solar2, 0);
		help_arrive = true;
	}
	if ((help_spawn) && (!help_arrive) && (GetDistance(help2,user) < 50.0f))
	{
//		AudioMessage("misn0313.wav");
		Goto(help2, solar2, 0);
		help_arrive = true;
	}
    ]==]

    if not M.second_objective and M.apc_spawn_time < GetTime() then
        M.apc_spawn_time = GetTime() + 1.0

        -- SP keeps the original local-player test. In co-op, every active
        -- human player must be clear of nearby tanks/fighters before the
        -- evacuation phase advances. Missing remote handles fail closed.
        local combatClear = CRCoop.AllPlayersSatisfy(function(playerHandle)
            local tanks = CountUnitsNearObject(playerHandle, 500.0, ENEMY_TEAM, "svtank")
            local fighters = CountUnitsNearObject(playerHandle, 500.0, ENEMY_TEAM, "svfigh")
            return tanks == 0 and fighters == 0
        end)

        if combatClear then
            M.audmsg = subtit.Play("misn0305.wav")
            M.second_objective = true
        end
    end

    if not M.camera_ready and M.second_objective then
        CameraReady()
        M.movie_time = GetTime() + 14.5
        M.new_unit_time = GetTime() + 7.5
        M.prop1 = BuildObject("svrecy", ENEMY_TEAM, "recy_spawn")
        M.prop2 = BuildObject("svmuf", ENEMY_TEAM, "muf_spawn")
        M.prop3 = BuildObject("svtank", ENEMY_TEAM, "tank1_spawn")
        M.prop4 = BuildObject("svtank", ENEMY_TEAM, "tank2_spawn")
        M.prop5 = BuildObject("svfigh", ENEMY_TEAM, "fighter1_spawn")
        M.guy1 = BuildObject("sssold", ENEMY_TEAM, GetPositionNear(GetPosition("guy1_spawn"), 0, 10))
        M.guy2 = BuildObject("sssold", ENEMY_TEAM, GetPositionNear(GetPosition("guy2_spawn"), 0, 10))
        M.guy3 = BuildObject("sssold", ENEMY_TEAM, GetPositionNear(GetPosition("guy1_spawn"), 0, 10))
        M.guy4 = BuildObject("sssold", ENEMY_TEAM, GetPositionNear(GetPosition("guy2_spawn"), 0, 10))

        Defend(M.prop1, 1)
        Goto(M.prop2, "tank1_spawn", 1)
        Goto(M.prop3, "that_path", 1)
        Goto(M.prop4, "cool_path", 1)
        Goto(M.prop5, "cool_path", 1)
        Goto(M.guy1, "guy_spot", 1)
        Goto(M.guy2, "guy_spot", 1)
        Goto(M.guy3, "guy_spot", 1)
        Goto(M.guy4, "guy_spot", 1)
        M.camera_ready = true
    end

    if M.camera_ready and not M.movie_over then
        CameraPath("movie_path", 175, 850, M.prop1)
        Defend(M.prop1, 1)
        M.start_movie = true
    end

    if M.camera_ready and not M.more_show and not M.movie_over then
        if M.new_unit_time < GetTime() then
            local mpos = GetPosition("muf_spawn")
            M.prop8 = BuildObject("svfigh", ENEMY_TEAM, GetPositionNear(mpos, 0, 20))
            M.prop9 = BuildObject("svfigh", ENEMY_TEAM, GetPositionNear(mpos, 0, 20))
            Goto(M.prop8, "tank2_spawn", 1)
            Goto(M.prop9, "fighter1_spawn", 1)
            M.more_show = true
        end
    end

    if M.start_movie and not M.movie_over and (CameraCancelled() or M.movie_time < GetTime()) then
        CameraFinish()
        if CameraCancelled() then subtit.Stop() end

        -- Spawn transports at their spawn points (matches original C++)
        --M.rescue1 = BuildObject("avapc", 1, "apc1_spawn")
       -- M.rescue2 = BuildObject("avapc", 1, "apc2_spawn")

        -- Fixed pull-out timer (matches original: 28s) and turret retreat (30s)
        M.pull_out_time = GetTime() + 28.0
        M.turret_move_time = GetTime() + 30.0

        SetObjectiveOff(M.solar1)
        SetObjectiveOff(M.solar2)
        SetObjectiveOff(M.solar3)
        SetObjectiveOff(M.solar4)

        SetObjectiveOn(M.rescue1)
        SetObjectiveName(M.rescue1, "Transport 1")
        SetObjectiveOn(M.rescue2)
        SetObjectiveName(M.rescue2, "Transport 2")
        SetObjectiveOn(M.launch)
        SetObjectiveName(M.launch, "Launch Pad")

        ClearObjectives()
        AddObjective("misn0311.otf", "green")
        AddObjective("misn0312.otf", "green")
        AddObjective("misn0303.otf", "white")

        M.recycler_follow_transport = true
        M.recycler_follow_launch = false
        M.recycler_pack_transport_issued = false
        M.recycler_follow_transport_issued = false
        M.recycler_pack_launch_issued = false
        M.recycler_follow_launch_issued = false

        if IsAlive(M.avrecycler) and IsAlive(M.rescue2) then
            if IsDeployed(M.avrecycler) then
                SetCommand(M.avrecycler, AiCommand.UNDEPLOY, 1)
                M.recycler_pack_transport_issued = true
            else
                Follow(M.avrecycler, M.rescue2, 1)
                M.recycler_follow_transport_issued = true
            end
        end

        M.movie_over = true
    end

    if M.movie_over and not M.remove_props then
        M.audmsg = subtit.Play("misn0306.wav")
        -- Remove all cinematic props immediately (matches original C++)
        RemoveObject(M.prop1)
        RemoveObject(M.prop2)
        RemoveObject(M.prop3)
        RemoveObject(M.prop4)
        RemoveObject(M.prop5)
        if IsAlive(M.prop8) then RemoveObject(M.prop8) end
        if IsAlive(M.prop9) then RemoveObject(M.prop9) end
        if IsAlive(M.guy1) then RemoveObject(M.guy1) end
        if IsAlive(M.guy2) then RemoveObject(M.guy2) end
        if IsAlive(M.guy3) then RemoveObject(M.guy3) end
        if IsAlive(M.guy4) then RemoveObject(M.guy4) end
        M.remove_props = true
    end

    if M.recycler_follow_transport and not M.third_objective and
        M.recycler_pack_transport_issued and not M.recycler_follow_transport_issued and
        IsAlive(M.avrecycler) and IsAlive(M.rescue2) and not IsDeployed(M.avrecycler) then
        Follow(M.avrecycler, M.rescue2, 1)
        M.recycler_follow_transport_issued = true
    elseif M.recycler_follow_launch and
        M.recycler_pack_launch_issued and not M.recycler_follow_launch_issued and
        IsAlive(M.avrecycler) and IsAlive(M.launch) and not IsDeployed(M.avrecycler) then
        Follow(M.avrecycler, M.launch, 1)
        M.recycler_follow_launch_issued = true
    end

    if M.startfinishingmovie and not M.tanks_go then
        if M.new_unit_time < GetTime() then
            -- MODIFIED: Outro Swarm & Invincibility (Fixed Health Bug)
            local function PrepOutroUnit(h)
                if IsAlive(h) then
                    SetMaxHealth(h, 50000) -- Massive Health for "Invincibility"
                    SetCurHealth(h, 50000)
                    SetWeaponMask(h, 3)    -- Double Weapons
                end
            end

            Goto(M.prop1, "line1", 1)
            Goto(M.prop2, "line2", 1)
            Goto(M.prop3, "line3", 1)
            PrepOutroUnit(M.prop1)
            PrepOutroUnit(M.prop2)
            PrepOutroUnit(M.prop3)

            -- Spawn Massive Swarm
            for i = 1, 10 do
                local sp = spawns[math.random(1, 3)]
                local s = BuildObject("svtank", ENEMY_TEAM, GetPositionNear(GetPosition(sp), 0, 50))
                PrepOutroUnit(s)
                Goto(s, "line" .. math.random(1, 3), 1)
            end

            M.tanks_go = true
        else
            Defend(M.prop1)
            Defend(M.prop2)
            Defend(M.prop3)
        end
    end

    -- (apc_arrived_at_base logic removed; pull_out_time is set directly in movie_over block)


    if M.remove_props then
        if not M.trans_underway and M.pull_out_time < GetTime() then
            -- Retreat transports to launch pad (matches original C++)
            Retreat(M.rescue1, "rescue_path")
            Retreat(M.rescue2, "rescue_path")
            -- Escorts follow transports (player-controllable, priority 0)
            if IsAlive(M.help1) then Follow(M.help1, M.rescue1, 0) end
            if IsAlive(M.help2) then Follow(M.help2, M.rescue2, 0) end

            M.ambush_message_time = GetTime() + 15.0
            M.trans_underway = true
            M.rescue_move_done = true
        end
    end

    -- Bonus pilot grant: when rescue APCs reach barracks area, spawn extra pilots near APCs.
    if M.remove_props and not M.apc_bonus_pilots_spawned and IsAlive(M.build5) then
        local barracksPos = GetPosition(M.build5)
        local r1Close = IsAlive(M.rescue1) and GetDistance(M.rescue1, barracksPos) < 130.0
        local r2Close = IsAlive(M.rescue2) and GetDistance(M.rescue2, barracksPos) < 130.0

        if r1Close or r2Close then
            local function SpawnPilotPair(apc)
                if not IsAlive(apc) then return end
                local apos = GetPosition(apc)
                BuildObject("aspilo", 1, GetPositionNear(apos, 5, 18))
                BuildObject("aspilo", 1, GetPositionNear(apos, 5, 18))
            end

            SpawnPilotPair(M.rescue1)
            SpawnPilotPair(M.rescue2)
            M.apc_bonus_pilots_spawned = true
        end
    end

    if M.remove_props then
        if not M.turret_move_done and M.turret_move_time < GetTime() then
            Retreat(M.turret1, "turret_path1")
            Retreat(M.turret2, "turret_path2")
            Retreat(M.turret3, "turret_path3")
            Retreat(M.turret4, "base")

            -- Spawn fighters to help turrets on Hard/Very Hard
            if exu and exu.GetDifficulty and exu.GetDifficulty() >= 2 then -- Hard+
                -- MODIFIED: Enemy forces follow the blocking turrets
                local b1 = BuildObject("svtank", ENEMY_TEAM, "turret_path1")
                local b2 = BuildObject("svfigh", ENEMY_TEAM, "turret_path2")
                Follow(b1, M.turret1)
                Follow(b2, M.turret2)
            end

            M.turret_move_done = true
        end
        -- ... existing attack logic preserved ...
        if IsAlive(M.wave1_1) then Attack(M.wave1_1, M.rescue1, 1) end
        if IsAlive(M.wave1_2) then Attack(M.wave1_2, M.rescue1, 1) end
        if IsAlive(M.wave5_1) then Attack(M.wave5_1, M.rescue2, 1) end
        if IsAlive(M.wave5_2) then Attack(M.wave5_2, M.rescue1, 1) end
        if IsAlive(M.wave5_3) then Attack(M.wave5_3, M.rescue2, 1) end
    end

    if M.trans_underway and M.ambush_message_time < GetTime() and not M.ambush_message then
        subtit.Play("misn0315.wav")
        -- MODIFIED: Split Spawns (Recycler locked down earlier)

        local wsp = GetPosition("wspawn")
        local ssp = GetPosition(spawns[2])
        M.wave6_1 = BuildObject("svtank", ENEMY_TEAM, GetPositionNear(wsp, 0, 40)) -- West
        M.wave6_2 = BuildObject("svtank", ENEMY_TEAM, GetPositionNear(ssp, 0, 40)) -- South
        M.wave6_3 = BuildObject("svtank", ENEMY_TEAM, GetPositionNear(wsp, 0, 40))
        local w4 = BuildObject("svtank", ENEMY_TEAM, GetPositionNear(ssp, 0, 40))
        local w5 = BuildObject("svtank", ENEMY_TEAM, GetPositionNear(wsp, 0, 40))

        if IsAlive(M.avrecycler) then
            Attack(M.wave6_1, M.avrecycler)
            Attack(M.wave6_2, M.avrecycler)
            Attack(M.wave6_3, M.avrecycler)
            Attack(w4, M.avrecycler)
            Attack(w5, M.avrecycler)
        end

        M.ambush_message = true
    end

    if M.remove_props and not M.lost and not M.third_objective and
        GetDistance(M.rescue1, M.launch) < 100.0 and GetDistance(M.rescue2, M.launch) < 100.0 then
        subtit.Play("misn0310.wav")
        if IsAlive(M.rescue1) then SetObjectiveOff(M.rescue1) end
        if IsAlive(M.rescue2) then SetObjectiveOff(M.rescue2) end

        Follow(M.rescue1, M.launch, 1)
        Follow(M.rescue2, M.launch, 1)
        M.recycler_follow_transport = false
        M.recycler_follow_launch = true
        M.recycler_pack_launch_issued = false
        M.recycler_follow_launch_issued = false

        if IsAlive(M.avrecycler) and IsAlive(M.launch) then
            if IsDeployed(M.avrecycler) then
                SetCommand(M.avrecycler, AiCommand.UNDEPLOY, 1)
                M.recycler_pack_launch_issued = true
            else
                Follow(M.avrecycler, M.launch, 1)
                M.recycler_follow_launch_issued = true
            end
        end

        ClearObjectives()
        AddObjective("misn0313.otf", "green")
        AddObjective("misn0304.otf", "white")
        local p1 = spawns[math.random(1, 3)]
        local p2 = spawns[math.random(1, 3)]
        local p3 = spawns[math.random(1, 3)]
        M.wave7_1 = BuildObject("svtank", ENEMY_TEAM, GetPositionNear(GetPosition(p1), 0, 40))
        M.wave7_2 = BuildObject("svtank", ENEMY_TEAM, GetPositionNear(GetPosition(p2), 0, 40))
        M.wave7_3 = BuildObject("svtank", ENEMY_TEAM, GetPositionNear(GetPosition(p3), 0, 40))
        Goto(M.wave7_1, "base", 1)
        Goto(M.wave7_2, "base", 1)
        Goto(M.wave7_3, "base", 1)
        M.final_check = GetTime() + 120.0
        M.third_objective = true
    end

    if not M.final_objective and not M.second_warning and M.final_check < GetTime() then
        M.final_check = GetTime() + 120.0
        ClearObjectives()
        AddObjective("misn0313.otf", "green")
        AddObjective("misn0304.otf", "white")
        subtit.Queue("misn0310.wav")
        M.second_warning = true
    end

    if not M.final_objective and M.second_warning and not M.last_warning and M.final_check < GetTime() then
        M.final_check = GetTime() + 120.0
        ClearObjectives()
        AddObjective("misn0313.otf", "green")
        AddObjective("misn0304.otf", "white")
        subtit.Queue("misn0310.wav")
        M.last_warning = true
    end

    if not M.final_objective and M.third_objective and CountUnitsNearObject(M.geyser, 5000.0, ENEMY_TEAM, "svtank") < 5 then
        local p4 = spawns[math.random(1, 3)]
        local p5 = spawns[math.random(1, 3)]
        M.wave7_4 = BuildObject("svtank", ENEMY_TEAM, GetPositionNear(GetPosition(p4), 0, 40))
        M.wave7_5 = BuildObject("svtank", ENEMY_TEAM, GetPositionNear(GetPosition(p5), 0, 40))
        Goto(M.wave7_4, "base", 1)
        Goto(M.wave7_5, "base", 1)
    end

    if M.third_objective and CRCoop.AllPlayersNear(M.launch, 100.0) and not M.lost and not M.final_objective then
        M.final_objective = true
    end

    if not M.startfinishingmovie and M.final_objective then
        -- Don't remove Recycler; let it ride
        --if IsAlive(M.avrecycler) then RemoveObject(M.avrecycler) end
        if IsAlive(M.scav1) then RemoveObject(M.scav1) end
        if IsAlive(M.scav2) then RemoveObject(M.scav2) end
        if IsAlive(M.scav3) then RemoveObject(M.scav3) end
        if IsAlive(M.scav4) then RemoveObject(M.scav4) end
        if IsAlive(M.scav5) then RemoveObject(M.scav5) end
        if IsAlive(M.scav6) then RemoveObject(M.scav6) end
        if IsAlive(M.help1) then RemoveObject(M.help1) end
        if IsAlive(M.help2) then RemoveObject(M.help2) end
        if IsAlive(M.wave4_1) then RemoveObject(M.wave4_1) end
        if IsAlive(M.wave4_2) then RemoveObject(M.wave4_2) end
        if IsAlive(M.wave6_1) then RemoveObject(M.wave6_1) end
        if IsAlive(M.wave6_2) then RemoveObject(M.wave6_2) end
        if IsAlive(M.wave6_3) then RemoveObject(M.wave6_3) end
        if IsAlive(M.wave7_1) then RemoveObject(M.wave7_1) end
        if IsAlive(M.wave7_2) then RemoveObject(M.wave7_2) end
        if IsAlive(M.wave7_3) then RemoveObject(M.wave7_3) end
        if IsAlive(M.wave7_4) then RemoveObject(M.wave7_4) end
        if IsAlive(M.wave7_5) then RemoveObject(M.wave7_5) end

        M.clean_sweep_time = GetTime() + 14.0
        -- With local-only skipping in co-op, a pathfinding-stalled film prop
        -- must not hold the entire session forever. Offline keeps its skip gate.
        M.coopOutroDeadline = GetTime() + 90.0
        M.next_shot = GetTime() + 18.5
        M.new_unit_time = GetTime() + 2.0
        M.audmsg = subtit.Play("misn0316.wav")
        M.prop1 = BuildObject("svtank", ENEMY_TEAM, GetPositionNear(GetPosition("spawna"), 0, 40))
        M.prop2 = BuildObject("svtank", ENEMY_TEAM, GetPositionNear(GetPosition("spawnb"), 0, 40))
        M.prop3 = BuildObject("svtank", ENEMY_TEAM, GetPositionNear(GetPosition("spawnc"), 0, 40))
        CameraReady()
        M.startfinishingmovie = true
    end

    if M.startfinishingmovie and not M.camera_2 then
        CameraPath("camera_path", M.x, 3500, M.cam_geyser)
        M.x = M.x - 15
        M.camera_on = true
    end

    if M.startfinishingmovie and M.clean_sweep_time < GetTime() and not M.clean_sweep then
        M.clean_sweep = true
    end

    if M.startfinishingmovie and M.next_shot < GetTime() and not M.camera_off then
        CameraPath("inbase_path", 160, 90, M.prop1)
        M.camera_2 = true
    end

    if M.camera_2 and not M.speach2 then
        M.audmsg = subtit.Play("misn0317.wav")
        M.speach2 = true
    end

    if M.camera_2 and not M.show_tank_attack then
        -- MODIFIED: Increased distance to 80.0 to prevent softlock from traffic jams (swarm)
        -- Added fail-safe for dead prop
        if not IsAlive(M.prop1) or GetDistance(M.prop1, M.shot_geyser) < 80.0 then
            if IsAlive(M.prop1) then
                Attack(M.prop1, M.solar1)
            end
            if IsAlive(M.prop2) then
                Attack(M.prop2, M.solar1)
            end

            if IsAlive(M.solar1) then
                if IsAlive(M.solar2) then Damage(M.solar2, 20000) end
                if IsAlive(M.solar3) then Damage(M.solar3, 20000) end
                if IsAlive(M.solar4) then Damage(M.solar4, 20000) end
            end
            -- PORT FIX: solar1 may already be destroyed after evacuation
            -- begins, when its defense failure gate is inactive. Advance the
            -- visual sequence even then, retaining the authored seven-second
            -- destruction delay rather than leaving the outro waiting forever.
            M.kill_tower = GetTime() + 7.0
            M.show_tank_attack = true
        end
    end

    if M.show_tank_attack and not M.tower_dead and M.kill_tower < GetTime() then
        if IsAlive(M.solar1) then
            Damage(M.solar1, 25000)
        end
        M.tower_dead = true
    end

    if M.tower_dead and not M.climax1 then
        Retreat(M.prop1, "climax_path1", 1)
        Retreat(M.prop2, "spawn_scrap1", 1)
        Retreat(M.prop3, "spawn_scrap1", 1)
        M.clear_debis_time = GetTime() + 6.0
        M.audmsg = subtit.Play("misn0318.wav")
        M.climax1 = true
    end

    if M.climax1 and not M.clear_debis and M.clear_debis_time < GetTime() then
        if IsAlive(M.build3) then Damage(M.build3, 20000) end
        M.prop8 = BuildObject("svtank", ENEMY_TEAM, GetPositionNear(GetPosition(M.cam_geyser), 0, 20))
        Retreat(M.prop8, "climax_path2", 1)
        M.clear_debis = true
    end

    if M.climax1 and not M.climax2 then
        -- PORT FIX: the existing dead-prop fallback must also cover later
        -- distance gates. A dead prop cannot reach these marks; continue the
        -- same debris shots and delays without changing the evacuation gate.
        if not IsAlive(M.prop1) or GetDistance(M.prop1, M.cam_geyser) < 100.0 then
            Retreat(M.prop1, "climax_path2", 1)
            local s_pos = GetPosition("solar_spot")
            M.prop9 = BuildObject("svfigh", ENEMY_TEAM, GetPositionNear(s_pos, 0, 20))
            M.prop0 = BuildObject("svfigh", ENEMY_TEAM, GetPositionNear(s_pos, 0, 20))
            Retreat(M.prop9, "camera_pass", 1)
            Retreat(M.prop0, "camera_pass", 1)
            if IsAlive(M.hanger) then Damage(M.hanger, 20000) end
            M.clear_debis_time = GetTime() + 3.0
            M.climax2 = true
        end
    end

    if M.climax2 and not M.last_blown and M.clear_debis_time < GetTime() then
        if IsAlive(M.box1) then Damage(M.box1, 20000) end
        if IsAlive(M.build1) then Damage(M.build1, 20000) end
        if IsAlive(M.crate1) then Damage(M.crate1, 20000) end
        if IsAlive(M.crate2) then Damage(M.crate2, 20000) end
        if IsAlive(M.crate3) then Damage(M.crate3, 20000) end

        Retreat(M.prop2, "solar_spot")
        Retreat(M.prop8, "spawn_scrap1", 1)
        M.sucker = BuildObject("abwpow", 1, GetPositionNear(GetPosition("sucker_spot"), 0, 10))
        M.last_blown = true
    end

    if M.last_blown and not M.end_shot and (not IsAlive(M.prop1) or GetDistance(M.prop1, M.sucker) < 65.0) then
        if IsAlive(M.prop1) then Attack(M.prop1, M.sucker, 1) end
        M.camera_off_time = GetTime() + 6.0 -- MODIFIED: Increased from 1.5s to 6.0s
        M.end_shot = true
    end

    if M.camera_on and not M.camera_off and (CameraCancelled() or M.camera_off_time < GetTime() or
        (CRCoop.IsNetworkGame() and GetTime() > (M.coopOutroDeadline or math.huge))) then
        M.startfinishingmovie = false
        CameraFinish()
        -- Only stop subtitles if the user skipped the cinematic
        if CameraCancelled() then
            subtit.Stop()
        end
        SucceedMission(0.1, "misn03w1.des")
        M.camera_off = true
    end

    if M.last_warning and M.final_check < GetTime() and not M.final_objective and not M.lost then
        FailMission(GetTime() + 1.0, "misn03f5.des")
        M.lost = true
    end

    if not M.dead1 and not M.show_tank_attack and not M.second_objective and not IsAlive(M.solar1) then
        subtit.Play("misn0302.wav")
        ClearObjectives()
        AddObjective("misn0311.otf", "red")
        AddObjective("misn0312.otf", "white")
        M.lost = true
        M.dead1 = true
        if not M.turrets_set then
            FailMission(GetTime() + 10.0, "misn03f1.des")
        else
            FailMission(GetTime() + 10.0, "misn03f2.des")
        end
    end

    -- PORT FIX: the QOL defense rule above accepts any required number of
    -- living arrays. This stock solar2-only branch contradicted that rule and
    -- failed the mission even with sufficient survivors. Keep the original
    -- loss message/debrief when the required count is actually unavailable.
    if not M.dead2 and not M.tanks_go and not IsAlive(M.solar2) and solarCount < required and not M.second_objective then
        subtit.Play("misn0303.wav")
        ClearObjectives()
        AddObjective("misn0311.otf", "red")
        AddObjective("misn0312.otf", "white")
        M.lost = true
        M.dead2 = true
        if not M.turrets_set then
            FailMission(GetTime() + 10.0, "misn03f3.des")
        else
            FailMission(GetTime() + 10.0, "misn03f3.des")
        end
    end

    if M.movie_over and not M.dead3 and not IsAlive(M.rescue1) and not M.third_objective then
        subtit.Play("misn0304.wav")
        ClearObjectives()
        AddObjective("misn0311.otf", "green")
        AddObjective("misn0312.otf", "green")
        AddObjective("misn0303.otf", "red")
        M.lost = true
        M.dead3 = true
        FailMission(GetTime() + 10.0, "misn03f4.des")
    end
    if M.movie_over and not M.dead3 and not IsAlive(M.rescue2) and not M.third_objective then
        subtit.Play("misn0304.wav")
        ClearObjectives()
        AddObjective("misn0311.otf", "green")
        AddObjective("misn0312.otf", "green")
        AddObjective("misn0303.otf", "red")
        M.lost = true
        M.dead3 = true
        FailMission(GetTime() + 10.0, "misn03f4.des")
    end
    -- New Fail Condition for Recycler
    if M.movie_over and not M.dead3 and not IsAlive(M.avrecycler) and not M.third_objective then
        subtit.Play("misn0304.wav") -- Reuse "Vehicle Destroyed"
        ClearObjectives()
        AddObjective("misn0311.otf", "green")
        AddObjective("misn0312.otf", "green")
        AddObjective("misn0303.otf", "red")
        M.lost = true
        M.dead3 = true
        FailMission(GetTime() + 10.0, "misn03f4.des")
    end

    -- Preserve the stock mission failure if the evacuation launch pad is destroyed.
    if not M.lost and not IsAlive(M.launch) then
        FailMission(GetTime() + 1.0)
        M.lost = true
    end

end

-- Original DLL comments and cut-content ledger. These are historical C++
-- fragments, kept inactive for reconstruction alongside the complete, verbatim
-- References/EarlyMissionSources/Misn03Mission.cpp. QOL behavior above is retained.
--[==[

Misn03Mission.cpp:5
/*
	Misn03Mission
*/

Misn03Mission.cpp:27
// bools

Misn03Mission.cpp:60
// since there are many ways you can loose we will make loosing a boolean

Misn03Mission.cpp:70
// floats

Misn03Mission.cpp:103
// handles

Misn03Mission.cpp:132
// integers

Misn03Mission.cpp:149
/*
Here's where you set the values at the start.  
*/

Misn03Mission.cpp:237
//	wave1_3 = GetHandle ("svfigh3");	

Misn03Mission.cpp:250
//	build2 = GetHandle ("build2");

Misn03Mission.cpp:424
//assigns the player a handle every frame

Misn03Mission.cpp:476
//		Attack(wave1_3, solar1);

Misn03Mission.cpp:481
// this sends the first wave retreating after one of them is destroyed

Misn03Mission.cpp:487
//			Retreat(wave1_3, "retreat_path2", 1);

Misn03Mission.cpp:496
//				Retreat(wave1_3, "retreat_path2", 1);

Misn03Mission.cpp:500
//			else

Misn03Mission.cpp:501
//			{

Misn03Mission.cpp:502
//				if (!IsAlive(wave1_3))

Misn03Mission.cpp:503
//				{

Misn03Mission.cpp:504
//					Retreat(wave1_1,"retreat_path", 1);

Misn03Mission.cpp:505
//					Retreat(wave1_2, "retreat_path2", 1);

Misn03Mission.cpp:506
//					new_message_time = Get_Time() + 10.0f;

Misn03Mission.cpp:507
//					start_retreat = true;

Misn03Mission.cpp:508
//				}

Misn03Mission.cpp:509
//			}

Misn03Mission.cpp:540
//		wave2_3 = BuildObject("svfigh",2,"spawn_scrap1");	

Misn03Mission.cpp:544
//		Goto(wave2_3, solar1);

Misn03Mission.cpp:553
//		wave3_3 = BuildObject("svfigh",2,"spawn_scrap1");

Misn03Mission.cpp:557
//		Goto(wave3_3, solar1, 1);

Misn03Mission.cpp:574
//		if (IsAlive(wave1_3))

Misn03Mission.cpp:575
//		{

Misn03Mission.cpp:576
//			Attack(wave1_3, scav1, 1);

Misn03Mission.cpp:577
//		}

Misn03Mission.cpp:586
//		wave4_3 = BuildObject("svtank",2,"spawn_scrap1");

Misn03Mission.cpp:610
//		Goto(wave4_3, solar2, 1);

Misn03Mission.cpp:661
//		AudioMessage("misn0313.wav");

Misn03Mission.cpp:667
//		AudioMessage("misn0313.wav");

Misn03Mission.cpp:672
//  Time to evacuate the base

Misn03Mission.cpp:675
// soviet movie

Misn03Mission.cpp:700
//		prop6 = BuildObject("svtank", 2, "fighter2_spawn");

Misn03Mission.cpp:701
//		prop7 = BuildObject("svtank", 2, "fighter3_spawn");

Misn03Mission.cpp:708
//		Defend(prop6, 1);

Misn03Mission.cpp:709
//		Defend(prop7, 1);

Misn03Mission.cpp:734
//			Goto(prop6, "cool_path2", 1);

Misn03Mission.cpp:735
//			Goto(prop7, "cool_path2", 1);

Misn03Mission.cpp:742
//			Defend(prop6);

Misn03Mission.cpp:743
//			Defend(prop7);

Misn03Mission.cpp:784
//		RemoveObject(prop6);

Misn03Mission.cpp:785
//		RemoveObject(prop7);

Misn03Mission.cpp:843
//		if (IsAlive (wave1_3))

Misn03Mission.cpp:844
//		{

Misn03Mission.cpp:845
//			Attack(wave1_3, rescue2, 1);

Misn03Mission.cpp:846
//		}

Misn03Mission.cpp:873
// I removed this for andrew:(GetDistance(rescue3,launch) < 100.0f)

Misn03Mission.cpp:926
// win/loose conditions	taken out for movie testing

Misn03Mission.cpp:1088
/*
		  Camera canceled
		  could be called and this would
		  still play
		*/

Misn03Mission.cpp:1180
//		if (IsAlive(build2))

Misn03Mission.cpp:1181
//		{

Misn03Mission.cpp:1182
//			Damage(build2, 20000);

Misn03Mission.cpp:1183
//		}

Misn03Mission.cpp:1188
//		if (IsAlive(build2))

Misn03Mission.cpp:1189
//		{

Misn03Mission.cpp:1190
//			RemoveObject(build2);

Misn03Mission.cpp:1191
//		}

Misn03Mission.cpp:1241
//		clear_debis_time = Get_Time() + 6.0f;

Misn03Mission.cpp:1262
// win/loose conditions

Misn03Mission.cpp:1266
// you didn't reach the launch pad in time

Misn03Mission.cpp:1270
//new

Misn03Mission.cpp:1280
// com tower dead - you didn't build enough turrets

Misn03Mission.cpp:1284
// com tower dead

Misn03Mission.cpp:1288
//new

Misn03Mission.cpp:1298
/// solar arrays dead - you didn't build enough turrets

Misn03Mission.cpp:1302
/// solar arrays dead

Misn03Mission.cpp:1315
// transport dead

Misn03Mission.cpp:1326
// transport dead

Misn03Mission.cpp:1331
// lost your launch pad no des

Misn03Mission.cpp:1349
// init bools

Misn03Mission.cpp:1355
// init floats

Misn03Mission.cpp:1361
// init handles

Misn03Mission.cpp:1367
// init ints

Misn03Mission.cpp:1379
// bools

Misn03Mission.cpp:1384
// floats

Misn03Mission.cpp:1389
// Handles

Misn03Mission.cpp:1394
// ints

Misn03Mission.cpp:1423
// bools

Misn03Mission.cpp:1428
// floats

Misn03Mission.cpp:1433
// Handles

Misn03Mission.cpp:1438
// ints
]==]
