-- Faithful stock misn07 port for Battlezone 98 Redux / Lua 5.1, with the shared
-- offline + 2-4 player co-op layer of the misn06 port (Docs/MISN07_COOP.md).
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misn07Mission.cpp.
-- Original disabled C++ remains in long comments at its original locations.
-- Full source, including native serialization, is in References/Misn07Source/.
-- Offline play reproduces the DLL; only the leader runs the mission body.
local M

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})
local exu = require("exu")
-- Native MultST Init precedes Start; the authored Utah arrives later by script.
if type(IsNetGame) == "function" and IsNetGame() then
    assert(exu.DisableStartingRecycler and exu.GetMyNetID,
        "misn07 co-op requires the bundled EXU multiplayer hooks")
    exu.DisableStartingRecycler()
end
local subtit = require("ScriptSubtitles")
local CRCoop = require("CRCoop")
local LEADER_TEAM, ENEMY_TEAM, SUPPORT_TEAM = 1, 5, 7
-- CR Venus weather >>
local CRVenusWeather = require("CRVenusWeather")
local VenusSites = require("CRVenusSites07")
local Environment = require("Environment")
local VENUS_OPS = { VenusState = true, VenusStrike = true, VenusErupt = true }
-- CR Venus weather <<
-- CR restored VO >>
-- Prototype svtnk7 tunables (see RestoredPrototypeTanks). The cap is 2 solo, +1 per extra
-- human team, at most 4; the first tank is built no sooner than 90 s after the trigger.
local PROTO_CAP_BASE, PROTO_CAP_PER_PLAYER, PROTO_CAP_MAX = 2, 1, 4
local PROTO_INTERVAL_S, PROTO_FIRST_DELAY_S = 135.0, 90.0
local PROTO_RETRY_S, PROTO_ORDER_S = 15.0, 30.0
local PROTO_SCRAP_COST = 8 -- svtnk7.odf scrapCost
-- CR restored VO <<
-- CR Razor One infiltration >>
-- Razor One's ship regenerates 2% of max health per second after 4 s without damage
-- (svfigh pair: ~470 effective dps vs 1800-4062 health, see MISN07_COOP.md).
local RK_HEAL_QUIET_S, RK_HEAL_PER_S = 4.0, 0.02
-- CR Razor One infiltration <<

-- Co-op presentation uses the established misn03/misn05 E/A and C transport.
-- Only the campaign leader runs the mission body below; HUD/audio/removal/timer/
-- end calls are explicitly delivered to every peer.
-- E/A are an ordered, acknowledged event stream (eight small packets in flight,
-- retried every 0.2s). C is a replaceable camera snapshot carrying a kind: "P"
-- (CameraPath), "O" (CameraObject) or "" (no camera). No tables go on wire.
-- These types do not collide with CRCoop's H/Q/K/P/L protocol. Join-in-progress
-- still requires a restart: native world reconstruction is not available here.
local unpackArgs = unpack or table.unpack
local native = {
    ClearObjectives = ClearObjectives, AddObjective = AddObjective,
    UpdateObjective = UpdateObjective, SetObjectiveOn = SetObjectiveOn,
    SetObjectiveOff = SetObjectiveOff, SetObjectiveName = SetObjectiveName,
    SetUserTarget = SetUserTarget, RemoveObject = RemoveObject,
    StartCockpitTimer = StartCockpitTimer, StopCockpitTimer = StopCockpitTimer,
    HideCockpitTimer = HideCockpitTimer,
    SucceedMission = SucceedMission, FailMission = FailMission,
    CameraReady = CameraReady, CameraPath = CameraPath, CameraObject = CameraObject,
    CameraFinish = CameraFinish, CameraCancelled = CameraCancelled,
    Play = subtit.Play, Queue = subtit.Queue, Stop = subtit.Stop,
}
local events, acknowledgements = {}, {}
local receivedEvent = 0
local pendingSeq, pendingSince
local nextEventSend, nextCameraSend = 0, 0
local cameraFrame, cameraGeneration, cameraSerial = nil, 0, 0
local remoteCameraSerial, localCameraGeneration = 0, 0
local cameraSkipped, localCameraActive = false, false
local remoteCamera
local function ResetPresentation()
    events, acknowledgements, receivedEvent = {}, {}, 0
    pendingSeq, pendingSince = nil, nil
    nextEventSend, nextCameraSend = 0, 0
    cameraFrame, cameraGeneration, cameraSerial = nil, 0, 0
    remoteCamera, remoteCameraSerial, localCameraGeneration = nil, 0, 0
    cameraWaitSince = nil
    cameraSkipped, localCameraActive = false, false
end

local function FromLeader(from)
    local player = CRCoop.GetPlayers()[from]
    return player and player.team == LEADER_TEAM
end

local function ApplyPresentation(op, ...)
    if op == "Resources" then
        local team, scrap, pilots = ...
        -- Each human owns their team resources. Do not mutate a remote team.
        if CRCoop.GetLocalTeam() == team then
            -- Guests have no starting recycler, hence zero native capacity.
            -- Reserve room before setting their mission starting resources.
            SetMaxScrap(team, math.max(GetMaxScrap(team), scrap))
            SetMaxPilot(team, math.max(GetMaxPilot(team), pilots))
            SetScrap(team, scrap)
            SetPilot(team, pilots)
        end
-- CR Venus weather >>
    elseif VENUS_OPS[op] then
        -- Weather events carry no handles: never labelled, never waited on.
        return CRVenusWeather.ApplyNetEvent(op, ...)
-- CR Venus weather <<
    elseif op == "Rally" then
        -- Respawn rally: the rendezvous nav until the Utah deploys, then the Utah.
        -- Every peer's respawn service resolves the handle itself.
        local utah = ...
        CRCoop.GetRespawn().SetRallyPoints({ [0] = "cam3", [1] = utah })
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

-- Ops whose first argument is a game object. The engine maps a handle across
-- Send only for replicated objects: a map-authored non-replicated one (misn06's
-- rendezvous geyser) arrives as nil on every guest, however long we wait. Those
-- go on the wire as "@handle@label" (handles are numbers, so a leading @ is
-- unambiguous) and each guest resolves the label with GetHandle.
local HANDLE_OPS = { SetObjectiveOn = true, SetObjectiveOff = true, SetObjectiveName = true,
    SetUserTarget = true, RemoveObject = true, Rally = true }
local WAIT_OPS = { SetObjectiveOn = true, SetObjectiveName = true, SetUserTarget = true, Rally = true }
-- A replica gets this many seconds, measured on the RECEIVER's own clock from
-- the first time its event is next in line, before the stale marker is dropped.
local EVENT_TTL = 5

local function WireHandle(handle)
    if handle == nil then return nil end
    local ok, label = pcall(GetLabel, handle)
    if ok and type(label) == "string" and label ~= "" and #label <= 126 then
        local found, resolved = pcall(GetHandle, label)
        if found and resolved == handle then
            -- "@handle@label": the label wins on a guest, but a label that only
            -- the leader knows (SetLabel on a spawned, replicated object) still
            -- falls back to the replicated handle.
            return "@" .. (type(handle) == "number" and string.format("%d", handle) or tostring(handle)) ..
                "@" .. label
        end
    end
    return handle
end

local function Present(op, ...)
    if CRCoop.IsNetworkGame() then
        if not CRCoop.IsAuthority() then return end
        local wire = { ... }
        if HANDLE_OPS[op] and wire[1] ~= nil then wire[1] = WireHandle(wire[1]) end
        events[#events + 1] = { op = op, args = wire, n = select("#", ...), ttl = EVENT_TTL }
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
local function StartCockpitTimer(...) return Present("StartCockpitTimer", ...) end
local function StopCockpitTimer(...) return Present("StopCockpitTimer", ...) end
local function HideCockpitTimer(...) return Present("HideCockpitTimer", ...) end
-- Preserve the real subtitle module for Update/Initialize and return values.
-- Play returns the native audio handle on the leader (offline: AudioMessage's).
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
        -- Offline the DLL re-issues these every frame it holds; stay a pass-through.
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
    cameraFrame = { "P", path, height, speed, WireHandle(target) }
    if CRCoop.IsNetworkGame() and native.CameraCancelled() then
        cameraSkipped = true
        if localCameraActive then native.CameraFinish() end
        localCameraActive = false
    end
    if not cameraSkipped then return native.CameraPath(path, height, speed, target) end
end
local function CameraObject(subject, x, y, z, target)
    cameraFrame = { "O", WireHandle(subject), x, y, z, WireHandle(target) }
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

-- Camera frames carry their handles like markers do ("@handle@label"). A guest resolves
-- them each update; a target that stays unresolved for CAMERA_RESOLVE_WINDOW seconds of
-- the guest's OWN clock no longer skips the film: it plays aimed at the other handle,
-- or at the guest's own craft, rather than not at all.
local CAMERA_RESOLVE_WINDOW = 2
local cameraWaitSince

local function ResolveCameraHandle(sent)
    if type(sent) ~= "string" or sent:sub(1, 1) ~= "@" then return sent end
    local sentHandle, sentLabel = sent:match("^@([^@]*)@(.*)$")
    local resolved = sentLabel and GetHandle(sentLabel)
    if not IsValid(resolved) and sentHandle and sentHandle ~= "" then
        local candidate = tonumber(sentHandle) or sentHandle
        if IsValid(candidate) then resolved = candidate end
    end
    return resolved
end

-- ready, subject, target. subject == nil means the kind carries none (path cameras).
local function ResolveCameraHandles(sentSubject, sentTarget)
    local subject, target = ResolveCameraHandle(sentSubject), ResolveCameraHandle(sentTarget)
    if (sentSubject == nil or IsValid(subject)) and IsValid(target) then
        cameraWaitSince = nil
        return true, subject, target
    end
    if not localCameraActive then
        local now = GetTime()
        if not cameraWaitSince or now < cameraWaitSince then cameraWaitSince = now end
        if now - cameraWaitSince < CAMERA_RESOLVE_WINDOW then return false end
    end
    local me = GetPlayerHandle and GetPlayerHandle()
    if not IsValid(target) then target = IsValid(subject) and subject or me end
    if sentSubject ~= nil and not IsValid(subject) then subject = IsValid(target) and target or me end
    if not IsValid(target) then return false end
    return true, subject, target
end

local function UpdateRemoteCamera()
    if not remoteCamera then return end
    local cam = remoteCamera
    if cam.kind == "" or M.coopResult then
        if localCameraActive then native.CameraFinish() end
        localCameraActive = false
        return
    end
    if cam.generation ~= localCameraGeneration then
        localCameraGeneration = cam.generation
        cameraSkipped = false
        cameraWaitSince = nil
    end
    if cameraSkipped then return end
    local ready, subject, target = ResolveCameraHandles(cam.kind == "O" and cam.subject or nil, cam.target)
    if not ready then return end
    cam = setmetatable({ subject = subject, target = target }, { __index = cam })
    if cam.kind == "O" then
        if not localCameraActive then
            native.CameraReady()
            localCameraActive = true
        end
        native.CameraObject(cam.subject, cam.x, cam.y, cam.z, cam.target)
        if native.CameraCancelled() then
            cameraSkipped = true
            localCameraActive = false
            native.CameraFinish()
        end
    else
        if not localCameraActive then
            native.CameraReady()
            localCameraActive = true
        elseif native.CameraCancelled() then
            cameraSkipped = true
            localCameraActive = false
            native.CameraFinish()
            return
        end
        native.CameraPath(cam.path, cam.height, cam.speed, cam.target)
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
                    Send(id, "E", seq, event.op, event.ttl, unpackArgs(event.args, 1, event.n))
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
            Send(0, "C", cameraSerial, cameraGeneration, "")
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
        local seq, generation, camKind, a, b, c, d, e = ...
        if type(seq) == "number" and seq > remoteCameraSerial and type(generation) == "number" then
            local cam
            if camKind == "" then
                cam = { generation = generation, kind = "" }
            elseif camKind == "P" and type(a) == "string" and type(b) == "number" and type(c) == "number" then
                cam = { generation = generation, kind = "P", path = a, height = b, speed = c, target = d }
            elseif camKind == "O" and type(b) == "number" and type(c) == "number" and type(d) == "number" then
                cam = { generation = generation, kind = "O", subject = a, x = b, y = c, z = d, target = e }
            end
            if cam then
                remoteCameraSerial = seq
                remoteCamera = cam
            end
        end
        return true
    end
    local seq, op, ttl = ...
    if type(seq) ~= "number" or type(op) ~= "string" or type(ttl) ~= "number" then return true end
    if seq == receivedEvent + 1 and (native[op] or VENUS_OPS[op] or op == "Resources" or op == "Rally") then
        local args = { select(4, ...) }
        local count = select("#", ...) - 3
        local apply = true
        if HANDLE_OPS[op] then
            if type(args[1]) == "string" and args[1]:sub(1, 1) == "@" then
                local sentHandle, sentLabel = args[1]:match("^@([^@]*)@(.*)$")
                local resolved = sentLabel and GetHandle(sentLabel)
                if not IsValid(resolved) and sentHandle and sentHandle ~= "" then
                    local candidate = tonumber(sentHandle) or sentHandle
                    if IsValid(candidate) then resolved = candidate end
                end
                args[1] = resolved
                -- A label with no object here (destroyed, or not loaded yet).
                if not IsValid(args[1]) then apply = false end
            end
            if WAIT_OPS[op] and not IsValid(args[1]) then
                -- Dynamic handles and map labels can resolve after the Lua packet.
                -- Withhold the ACK so the retransmission retries, but bound the
                -- wait on OUR clock: the leader's GetTime() is not comparable.
                local now = GetTime()
                if pendingSeq ~= seq or now < pendingSince then pendingSeq, pendingSince = seq, now end
                if now - pendingSince < ttl then return true end
                -- A target destroyed before its packet arrived must not block the
                -- stream (and the mission result) forever. Only that marker drops.
                apply = false
            end
        end
        pendingSeq = nil
        if apply then ApplyPresentation(op, unpackArgs(args, 1, count)) end
        receivedEvent = seq
    end
    Send(from, "A", receivedEvent)
    return true
end

-- Presentation adapter ends. BuildObject invokes AddObject synchronously.

-- Lexical SetScrap: the DLL's SetScrap(1, 5) means every human's starting scrap
-- in co-op (each owner applies their own team). Offline it is the stock call.
local nativeSetScrap = SetScrap
local function SetScrap(team, amount)
    if CRCoop.IsNetworkGame() and team == LEADER_TEAM then
        CRCoop.ForEachHumanTeam(function(humanTeam)
            Present("Resources", humanTeam, amount, GetPilot(LEADER_TEAM))
        end)
        return
    end
    return nativeSetScrap(team, amount)
end

local function ConfigureAlliances()
    CRCoop.ApplyCoopAlliances(ENEMY_TEAM)
    for team = 1, 4 do
        Ally(team, SUPPORT_TEAM); Ally(SUPPORT_TEAM, team)
    end
    UnAlly(ENEMY_TEAM, SUPPORT_TEAM); UnAlly(SUPPORT_TEAM, ENEMY_TEAM)
end

local function NewState()
    local state = {}
    state.test = false
    state.utah_found = false
    state.start_done = false
    state.out_of_car = false
    state.alarm_on = false
    state.start_evac = false
    state.ccaguntower1_down = false
    state.ccaguntower2_down = false
    state.radar_dead = false
    state.player_dead = false
    state.over_wall = false
    state.guntower_attacked = false
    state.fence_off = false
    state.rendezvous = false
    state.recon_message1 = false
    state.recon_message2 = false
    state.build_scouts = false
    state.jump_cam_spawned = false
    state.rookie_moved = false
    state.becon_build = false
    state.free1 = false
    state.free2 = false
    state.p1_retreat = false
    state.p2_retreat = false
    state.p3_retreat = false
    state.p4_retreat = false
    state.retreat_message_done = false
    state.first_objective = false
    state.second_objective = false
    state.turret_move = false
    state.next_mission = false
    state.rookie_lost = false
    state.mine_pathed = false
    state.detected = false
    state.getum = false
    state.patrola1 = false
    state.patrola2 = false
    state.patrolb1 = false
    state.patrolb2 = false
    state.patrolc1 = false
    state.patrolc2 = false
    state.retreat_success = false
    state.detected_message = false
    state.fighter_moved = false
    state.unit_spawn = false
    state.vehicle_stolen = false
    state.trigger1 = false
    state.alarm_special = false
    state.m_on = {}
    for index = 0, 110 do state.m_on[index] = false end
    state.m_dead = {}
    for index = 0, 110 do state.m_dead[index] = false end
    state.alarm_sound = false
    state.rookie_removed = false
    state.forces_enroute = false
    state.test_tank_built = false
    state.camera1_on = false
    state.camera2_on = false
    state.camera3_on = false
    state.camera4_on = false
    state.camera_off = false
    state.camera2_oned = false
    state.camera3_oned = false
    state.camera_ready = false
    state.tank_switch = false
    state.sound_started = false
    state.test_found = false
    state.game_over = false
    state.first_camera_ready = false
    state.first_camera_off = false
    state.cute_camera_ready = false
    state.cute_camera_off = false
    state.radar_camera_off = false
    state.next_camera_on = false
    state.rookie_jumped = false
    state.tower_warning = false
    state.rookie_found = false
    state.opening_vo = false
    state.shot1 = false
    state.shot2 = false
    state.unit_spawn_time = 99999.0
    state.recon_message_time = 99999.0
    state.becon_build_time = 99999.0
    state.rookie_rendezvous_time = 99999.0
    state.getaway_message_time = 99999.0
    state.patrol2_move_time = 99999.0
    state.rookie_move_time = 99999.0
    state.alarm_time = 99999.0
    state.alarm_timer = 99999.0
    state.rendezous_check = 99999.0
    state.alarm_check = 99999.0
    state.rookie_remove_time = 99999.0
    state.runner_check = 99999.0
    state.check_jump_geyser = 99999.0
    state.reach_mine_time = 99999.0
    state.check_range = 99999.0
    state.change_angle = 99999.0
    state.change_angle1 = 99999.0
    state.change_angle2 = 99999.0
    state.change_angle3 = 99999.0
    state.switch_tank = 99999.0
    state.start_sound = 99999.0
    state.recon_message2_time = 99999.0
    state.first_camera_time = 99999.0
    state.radar_camera_time = 99999.0
    state.next_mission_time = 99999.0
    state.cute_camera_time = 99999.0
    state.next_shot_time = 99999.0
    state.tower_check = 99999.0
    state.user = nil
    state.nsdfrecycle = nil
    state.nsdfmuf = nil
    state.rookie = nil
    state.jump_cam = nil
    state.jump_geyz = nil
    state.remove_geyz = nil
    state.mine_geyz = nil
    state.pilot1 = nil
    state.pilot2 = nil
    state.pilot3 = nil
    state.pilot4 = nil
    state.pilot5 = nil
    state.ccaguntower1 = nil
    state.ccaguntower2 = nil
    state.ccacomtower = nil
    state.powrplnt1 = nil
    state.powrplnt2 = nil
    state.parkedtank1 = nil
    state.parkedtank2 = nil
    state.parkedtank3 = nil
    state.parkedtank4 = nil
    state.barrack1 = nil
    state.barrack2 = nil
    state.nav1 = nil
    state.nav2 = nil
    state.nav3 = nil
    state.nav4 = nil
    state.nav5 = nil
    state.nav6 = nil
    state.nav7 = nil
    state.becon1 = nil
    state.becon2 = nil
    state.becon3 = nil
    state.becon4 = nil
    state.wingman1 = nil
    state.wingman2 = nil
    state.wingtank1 = nil
    state.wingtank2 = nil
    state.wingtank3 = nil
    state.wingturret1 = nil
    state.wingturret2 = nil
    state.nsdfarmory = nil
    state.svapc = nil
    state.m = {}
    for index = 0, 110 do state.m[index] = nil end
    state.ccarecycle = nil
    state.ccamuf = nil
    state.ccaslf = nil
    state.basepowrplnt1 = nil
    state.pbaseowrplnt2 = nil
    state.ccabaseguntower1 = nil
    state.ccabaseguntower2 = nil
    state.guard_tank1 = nil
    state.guard_tank2 = nil
    state.guard_tank3 = nil
    state.test_tank = nil
    state.patrol1_1 = nil
    state.patrol1_2 = nil
    state.patrol1_3 = nil
    state.svpatrol1_1 = nil
    state.svpatrol1_2 = nil
    state.svpatrol1_3 = nil
    state.svpatrol2_1 = nil
    state.svpatrol2_2 = nil
    state.svpatrol2_3 = nil
    state.svpatrol3_1 = nil
    state.svpatrol3_2 = nil
    state.svpatrol3_3 = nil
    state.svpatrol4_1 = nil
    state.svpatrol4_2 = nil
    state.guard_turret1 = nil
    state.guard_turret2 = nil
    state.spawn_turret1 = nil
    state.spawn_turret2 = nil
    state.parked1 = nil
    state.parked2 = nil
    state.parked3 = nil
    state.parkturret1 = nil
    state.parkturret2 = nil
    state.spawn_point = nil
    state.fence = nil
    state.test_turret = nil
    state.tank_spawn = nil
    state.power1_geyser = nil
    state.power2_geyser = nil
    state.radar_geyser = nil
    state.camera_geyser = nil
    state.show_geyser = nil
    state.new_tank1 = nil
    state.new_tank2 = nil
    state.turret1_spot = nil
    state.mine = {}
    for index = 0, 110 do state.mine[index] = nil end
    state.count = 0
    state.mine_check = 0
    state.x = 0
    state.units = 0
    state.audmsg = 0
    -- CR co-op state: per-player infiltration and stolen-vehicle latches (by player id).
    state.infiltrated = {}
    state.stolen = {}
-- CR Razor One infiltration >>
    state.rk = nil
    state.rh = nil
-- CR Razor One infiltration <<
-- CR Venus weather >>
    state.venusSeed = nil
    state.venusBeats = nil
    state.weatherState = nil
-- CR Venus weather <<
-- CR rendezvous convoy >>
    state.convoy = nil
-- CR rendezvous convoy <<
-- CR restored VO >>
    state.mine_ok = nil
    state.take0702 = nil
    state.cine_player = nil
    state.test_range_started = false
    state.test_range_after = 99999.0
    state.tr_unit = nil
    state.tr_hold = false
    state.tr_timeout = 99999.0
    state.tr_next = 0
    state.razor_unit = nil
    state.vo_last = nil
    state.ambushed = false
    state.proto = {}
    state.proto_start = nil
    state.proto_next = 0
    state.proto_order = 0
    state.ambush1 = nil
    state.ambush2 = nil
    state.utah_nag_time = 99999.0
    state.utah_nagged = false
-- CR restored VO <<
    return state
end
M = NewState()

-- Missing native handles returned an effectively infinite distance. Preserve
-- that behavior rather than interpreting nil as a path/position overload.
local function Distance(from, to)
    if from == nil or from == 0 or not IsValid(from) then return math.huge end
    if to == nil or to == 0 then return math.huge end
    if type(to) ~= "string" and not IsValid(to) then return math.huge end
    return GetDistance(from, to)
end

local function IsOdfBase(h, name)
    return IsValid(h) and (IsOdf(h, name) or IsOdf(h, name .. ".odf"))
end

-- Native helper checked object existence, not IsAlive; keep that distinction.
local function AliveButDamaged(h)
    if h == nil or h == 0 or not IsValid(h) then return false end
    return GetHealth(h) < 0.95
end

-- Co-op trigger helpers. Offline CRCoop iterates just the local player, so each
-- reproduces the DLL's single-player test exactly. Every distance goes through
-- the mission's Distance guard (never raw GetDistance).
local function AnyPlayerWithin(target, distance)
    return CRCoop.AnyPlayerSatisfies(function(h) return Distance(h, target) < distance end)
end

-- The first present player within `distance` of `target`, else nil.
local function FirstPlayerWithin(target, distance)
    local found = nil
    CRCoop.ForEachPlayerHandle(function(h)
        if found == nil and Distance(h, target) < distance then found = h end
    end)
    return found
end

-- True when every present player is farther than `distance` from `target`.
local function NoPlayerWithin(target, distance)
    local clear = true
    CRCoop.ForEachPlayerHandle(function(h)
        if not (Distance(h, target) > distance) then clear = false end
    end)
    return clear
end

-- The human craft nearest `from`; the leader's own craft when none is present.
local function NearestPlayer(from)
    local best, bestDistance = nil, math.huge
    CRCoop.ForEachPlayerHandle(function(h)
        local distance = Distance(from, h)
        if best == nil or distance < bestDistance then best, bestDistance = h, distance end
    end)
    return best or M.user
end

local function IsAnyPlayer(h)
    return h ~= nil and CRCoop.AnyPlayerSatisfies(function(player) return player == h end)
end

-- Per-player infiltration state is keyed by the CRCoop player id (nil offline).
local function PlayerKey(id) return id or 0 end

-- vehicle_stolen (co-op): every infiltrated player has taken a Soviet vehicle.
local function AllInfiltratorsStolen()
    local any, all = false, true
    for key in pairs(M.infiltrated) do
        any = true
        if not M.stolen[key] then all = false end
    end
    return any and all
end

local function PlanarDistance(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

local function AtGround(x, z)
    return SetVector(x, (GetTerrainHeightAndNormal(SetVector(x, 0, z))), z)
end

-- CR Venus weather >>
-- Venus atmosphere (Docs/VENUS_WEATHER.md). The leader (or offline play) runs the director's
-- automatic weather and the beats below; guests render the same sky from the seeded timeline
-- plus the host's state and strike/eruption events, which ride the ordered presentation
-- stream like any other event. The events carry no handles, so they bypass the marker
-- label/TTL logic. The director never damages anything (knockback and radar scramble only),
-- so the cinematics are left alone.
local venusStarted, venusAnnounced = false, false

local function InitVenusWeather()
    venusStarted = true
    local net = CRCoop.IsNetworkGame()
    local authority = (not net) or CRCoop.IsAuthority()
    Environment.Init()
    CRVenusWeather.Init({
        authority = authority,
        seed = M.venusSeed, -- nil: the leader/offline picks one, guests wait for the host's state
        sites = VenusSites,
        startLevel = 1,
        targetLevel = 2,
        -- The host queues straight onto the stream: its own Present() would apply the event again.
        send = net and function(op, ...)
            events[#events + 1] = { op = op, args = { ... }, n = select("#", ...), ttl = EVENT_TTL }
        end or nil,
        players = net and function()
            local list = {}
            CRCoop.ForEachPlayerHandle(function(h) list[#list + 1] = h end)
            return list
        end or nil,
    })
    if M.weatherState ~= nil and authority then
        CRVenusWeather.Load(M.weatherState)
        M.weatherState = nil
    end
    if authority then M.venusSeed = CRVenusWeather.Seed end -- survives a save
end

-- Every peer, every frame after the session is ready.
local function UpdateVenusWeather(dt)
    if not venusStarted then InitVenusWeather() end
    if CRCoop.IsNetworkGame() and CRCoop.IsAuthority() and not venusAnnounced and CRCoop.IsSessionReady() then
        venusAnnounced = true
        CRVenusWeather.AnnounceState()
    end
    CRVenusWeather.Update(dt)
    Environment.Update(dt)
end

local function ShutdownVenusWeather()
    if venusStarted then CRVenusWeather.Shutdown() end
    venusStarted, venusAnnounced = false, false
end

-- Host/offline only: the mission's arc drives the severity ladder, each beat once.
--   2 calm approach -> 3 when the infiltration starts (Razor One's ejection, the first
--   player inside, or the alarm) -> a 100 s level-5 burst when the CCA evacuation scrambles
--   (alarm soldiers spawn) -> 4 when the radar array falls -> 3 once the Utah is deployed.
local function UpdateVenusBeats()
    local beats = M.venusBeats
    if beats == nil then beats = {}; M.venusBeats = beats end
    if (not beats.rising) and (not M.first_objective) and (M.rookie_removed or M.out_of_car or M.alarm_on) then
        beats.rising = true
        CRVenusWeather.SetTargetLevel(3)
    end
    if (not beats.burst) and M.unit_spawn then
        beats.burst = true
        CRVenusWeather.ForceLevel(5, 100.0, 14.0)
    end
    if (not beats.storm) and M.first_objective then
        beats.storm = true
        CRVenusWeather.SetTargetLevel(4)
    end
    if (not beats.easing) and M.utah_found then
        beats.easing = true
        CRVenusWeather.SetTargetLevel(3)
    end
end
-- CR Venus weather <<

-- CR rendezvous convoy >>
-- The DLL parked two disguised NSDF tanks (avtank2/avtank3) at the rendezvous on
-- authored team 3, which co-op gives to a guest, so Build-CoopMap.py removes them.
-- The leader instead spawns two SUPPORT_TEAM avtanks (allied with every human,
-- perceived as NSDF below) at the NSDF-side map edge and drives them in once a
-- player comes near. They take the DLL handles M.wingtank2/M.wingtank3, so the
-- rendezvous test and the team-1 replacement below run unchanged.
--   * Spawn: edge_path in the converted BZN spans x 192..4106, z 97480..101299 (the
--     playable bounds). 15% in from the west edge (x = 779) at the rendezvous z is
--     about 660 m from cam3 and well clear of every CCA patrol route, out of view.
--   * Destinations: the authored avtank2/avtank3 positions (map objects removed).
--   * Trigger: first player within 600 m of cam3. A tank at ~10 m/s needs about a minute
--     for the 660 m; a player at 600 m needs a similar time to arrive.
local RENDEZVOUS_CONVOY = true
local CONVOY_TRIGGER_M = 600.0
local CONVOY_SPAWN = { { 779.0, 99505.0 }, { 779.0, 99525.0 } }
local CONVOY_DEST = { { 1426.3, 22.9489, 99546.5 }, { 1442.5, 21.613, 99570.4 } }
local CONVOY_REORDER_S = 10.0
local CONVOY_ARRIVE_M = 25.0

local function SpawnConvoy()
    M.convoy = { sent = false, nextOrder = 0 }
    for i, at in ipairs(CONVOY_SPAWN) do
        local tank = BuildObject("avtank", SUPPORT_TEAM, AtGround(at[1], at[2]))
        if i == 1 then M.wingtank2 = tank else M.wingtank3 = tank end
    end
end

-- Order the convoy in as a player nears; keep re-ordering until it arrives.
local function UpdateConvoy()
    local convoy = M.convoy
    if convoy == nil or M.rendezvous then return end
    if not convoy.sent then
        if M.nav3 == nil or not AnyPlayerWithin(M.nav3, CONVOY_TRIGGER_M) then return end
        convoy.sent = true
    end
    if convoy.nextOrder >= GetTime() then return end
    convoy.nextOrder = GetTime() + CONVOY_REORDER_S
    for i, tank in ipairs({ M.wingtank2, M.wingtank3 }) do
        local dest = CONVOY_DEST[i]
        if IsAlive(tank) and PlanarDistance(GetPosition(tank), { x = dest[1], z = dest[3] }) > CONVOY_ARRIVE_M then
            Goto(tank, SetVector(dest[1], dest[2], dest[3]), 1)
        end
    end
end
-- CR rendezvous convoy <<

-- CR Razor One infiltration >>
-- The DLL ejects Razor One (the rookie) at the overlook and the pilot wanders
-- home. Here he parachutes over the wall into the outpost, lands, steals an empty
-- Soviet vehicle and fights for the team. EjectPilot returns nothing in the BZR API,
-- so the pilot is captured from AddObject (the engine creates him synchronously)
-- or, failing that, by scanning for a person within 40 m of the rookie. The flight
-- is a velocity-steered glide; every phase has a time limit and any failure drops
-- the scripted behaviour. He never sets out_of_car or trips the alarm: only humans
-- are infiltrators, and the stolen vehicle's parked handle is cleared from the
-- CCA alarm code.
local RAZOR_ONE = true
local RK_LAND_OFFSET_M = 40.0
local RK_GLIDE_SPEED, RK_SINK, RK_LAND_RADIUS = 22.0, 5.0, 8.0
local RK_CAPTURE_S, RK_FLIGHT_S, RK_BOARD_S = 3.0, 60.0, 40.0
local RK_ASSIST_CLEARANCE, RK_ASSIST_RISE, RK_LOOKAHEAD, RK_LOOKAHEAD_STEP = 10.0, 10.0, 90.0, 15.0
local RK_FOLLOW_S = 10.0

local function RazorOneSlots()
    return { { name = "parked1", h = M.parked1 }, { name = "parked2", h = M.parked2 },
             { name = "parked3", h = M.parked3 } }
end

local function BeginRazorOneFlight()
    if not RAZOR_ONE or not IsValid(M.rookie) or not IsValid(M.camera_geyser) then return end
    local geyser = GetPosition(M.camera_geyser)
    -- Landing point: 40 m past the camera geyser toward the parked vehicles. It is
    -- >60 m from the huts, the APC and the parked tanks (radar array (2682,99710),
    -- hut1 (2787,99654), parked tanks (2830,99590), APC (2712,99485)).
    M.rk = { phase = "eject", t0 = GetTime(), from = GetPosition(M.rookie),
        land = SetVector(geyser.x + RK_LAND_OFFSET_M, geyser.y, geyser.z),
        tried = {}, slots = RazorOneSlots(), nextFollow = 0 }
end

local function RazorOneAdopt(h)
    local rk = M.rk
    if rk == nil or rk.phase ~= "eject" or rk.pilot ~= nil then return end
    if IsPerson(h) and GetTeamNum(h) == LEADER_TEAM and PlanarDistance(GetPosition(h), rk.from) < 40.0 then
        rk.pilot = h
    end
end

local function RazorOneGlide(rk, now)
    local pilot = rk.pilot
    local pos, vel = GetPosition(pilot), GetVelocity(pilot)
    rk.lastPos = pos
    local ground = (GetTerrainHeightAndNormal(pos))
    if now - rk.t0 > 1.5 and pos.y - ground < 1.5 then
        rk.phase = "board"
        return
    end
    local dx, dz = rk.land.x - pos.x, rk.land.z - pos.z
    local distance = math.sqrt(dx * dx + dz * dz)
    if distance <= RK_LAND_RADIUS then return end -- near the target: let him drop
    local ux, uz = dx / distance, dz / distance
    local speed = math.min(RK_GLIDE_SPEED, math.max(4.0, distance / 2.0))
    local vy = math.max(vel.y, -RK_SINK)
    -- Wall assist: climb just fast enough to clear the highest ground on the next 90 m
    -- by the safety margin, capped so it still reads as a glide.
    for ahead = RK_LOOKAHEAD_STEP, RK_LOOKAHEAD, RK_LOOKAHEAD_STEP do
        local height = (GetTerrainHeightAndNormal(SetVector(pos.x + ux * ahead, 0, pos.z + uz * ahead)))
        local needed = (height + RK_ASSIST_CLEARANCE - pos.y) / (ahead / speed)
        if needed > 0 then vy = math.max(vy, math.min(needed, RK_ASSIST_RISE)) end
    end
    SetVelocity(pilot, SetVector(ux * speed, vy, uz * speed))
end

-- The nearest empty parked Soviet vehicle he can still take.
local function RazorOneChooseRide(rk)
    local best, bestDistance = nil, math.huge
    local from = GetPosition(rk.pilot)
    for _, slot in ipairs(rk.slots) do
        local h = slot.h
        if h ~= nil and not rk.tried[h] and IsAlive(h) and not IsAnyPlayer(h) and
            GetTeamNum(h) == ENEMY_TEAM then
            local distance = PlanarDistance(from, GetPosition(h))
            if distance < bestDistance then best, bestDistance = slot, distance end
        end
    end
    return best
end

-- Hand a slot he gave up on back to the CCA alarm code.
local function RazorOneReleaseSlot(rk)
    if rk.slot ~= nil and M[rk.slot.name] == nil and IsAlive(rk.slot.h) then M[rk.slot.name] = rk.slot.h end
    rk.slot, rk.vehicle = nil, nil
end

local function RazorOneBoard(rk, now)
    if rk.vehicle == nil then
        local slot = RazorOneChooseRide(rk)
        if slot == nil then M.rk = nil; return end -- nothing left to take: leave him be
        rk.slot, rk.vehicle, rk.boardAt = slot, slot.h, now
        rk.tried[slot.h] = true
        -- Quiet theft: the CCA alarm code must not command or react to this vehicle.
        M[slot.name] = nil
        GetIn(rk.pilot, rk.vehicle, 1)
        return
    end
    if not IsAlive(rk.pilot) then
        -- Gone: he either boarded (last seen beside the vehicle) or died.
        if IsAlive(rk.vehicle) and rk.lastPos ~= nil and
            PlanarDistance(rk.lastPos, GetPosition(rk.vehicle)) < 15.0 then
            if GetTeamNum(rk.vehicle) ~= LEADER_TEAM then SetTeamNum(rk.vehicle, LEADER_TEAM) end
            SetPerceivedTeam(rk.vehicle, LEADER_TEAM)
            rk.phase, rk.nextFollow = "ride", 0
        else
            RazorOneReleaseSlot(rk)
            M.rk = nil
        end
        return
    end
    rk.lastPos = GetPosition(rk.pilot)
    local team = GetTeamNum(rk.vehicle)
    if not IsAlive(rk.vehicle) or (team ~= ENEMY_TEAM and team ~= LEADER_TEAM) or IsAnyPlayer(rk.vehicle) or
        now - rk.boardAt > RK_BOARD_S then
        -- Destroyed, taken or too slow: fall back to the next candidate.
        RazorOneReleaseSlot(rk)
    end
end

local function RazorOneRide(rk, now)
    if not IsAlive(rk.vehicle) then M.rk = nil; return end
    if M.tr_hold then return end -- he is on his way to the test range
    if rk.nextFollow > now then return end
    rk.nextFollow = now + RK_FOLLOW_S
    local leader = NearestPlayer(rk.vehicle)
    if IsValid(leader) then Follow(rk.vehicle, leader, 0) end
end

local function UpdateRazorOne()
    local rk = M.rk
    if rk == nil then return end
    local now = GetTime()
    -- Remember who Razor One is (pilot, then his vehicle) for the test-range trip.
    M.razor_unit = (rk.phase == "ride" and rk.vehicle) or rk.pilot or M.razor_unit
    if rk.phase == "eject" then
        if rk.pilot == nil then
            for h in ObjectsInRange(40.0, rk.from) do RazorOneAdopt(h) end
        end
        if rk.pilot ~= nil then
            rk.phase, rk.t0 = "glide", now
        elseif now - rk.t0 > RK_CAPTURE_S then
            M.rk = nil -- never found him: leave the DLL behaviour
        end
    elseif rk.phase == "glide" then
        if not IsAlive(rk.pilot) or now - rk.t0 > RK_FLIGHT_S then M.rk = nil; return end
        RazorOneGlide(rk, now)
    elseif rk.phase == "board" then
        if not IsAlive(rk.pilot) and rk.vehicle == nil then M.rk = nil; return end
        RazorOneBoard(rk, now)
    elseif rk.phase == "ride" then
        RazorOneRide(rk, now)
    end
end

-- Gradual healing for whatever Razor One is flying: his avfigh before the ejection and the
-- stolen Soviet vehicle afterwards (never the pilot on foot, never once dead). After
-- RK_HEAL_QUIET_S without his health dropping it restores RK_HEAL_PER_S of max health per
-- second, never above max and never while he is being hit. His weapons and AI are untouched.
local function RazorOneShip()
    if (not M.rookie_removed) and IsAlive(M.rookie) then return M.rookie end
    local rk = M.rk
    if rk ~= nil and rk.phase == "ride" and IsAlive(rk.vehicle) then return rk.vehicle end
    local unit = M.razor_unit
    if unit ~= nil and IsAlive(unit) and (not IsPerson(unit)) then return unit end
    return nil
end

local function UpdateRazorHeal()
    local ship = RazorOneShip()
    if ship == nil then M.rh = nil; return end
    local now, health = GetTime(), GetHealth(ship)
    local rh = M.rh
    if rh == nil or rh.ship ~= ship then
        M.rh = { ship = ship, last = health, hurt = now, at = now }
        return
    end
    local dt = math.min(now - rh.at, 0.5)
    rh.at = now
    if health < rh.last - 0.0005 then rh.hurt = now end -- taking damage
    if health < 1.0 and now - rh.hurt >= RK_HEAL_QUIET_S then
        local gain = math.min(RK_HEAL_PER_S * dt, 1.0 - health)
        if gain > 0 then
            AddHealth(ship, gain * GetMaxHealth(ship))
            health = GetHealth(ship)
        end
    end
    rh.last = health
end
-- CR Razor One infiltration <<

-- CR restored VO >>
-- Campaign Reimagined addition: the test-range arc cut from the stock mission (the
-- DLL keeps it as disabled C++ comments). Every use sits inside matching marker lines;
-- set RESTORED_VO=false for the stock mission. Only shipped ODFs, paths and subtitled
-- voice lines are used; 0711 (a developer joke) and 0717 (a duplicate of 0702) stay cut.
--
-- Sequence (phase 2 only): nothing starts before the radar array is down. Once the
-- Utah has deployed (or 150 s after 0714) and no dialogue is still playing, Razor One
-- (his stolen vehicle, or his pilot) drives to the test range at cam_spawn6; 0703 plays
-- when he arrives (or after 90 s, or at once if he is gone), the test tank and turret
-- spawn, and the Testing Range nav follows 15 s later. 120 s after that, if no player is
-- near the Mine Field spawn point, two CCA fighters ambush him (so 0704 is true), 0704
-- plays and the Mine Field nav drops; the Mine Path beacons follow when a player
-- reaches it. He returns to following the nearest player once a player reaches him or
-- the ambush is cleared.
local RESTORED_VO = true
local CUT_VO = {
    testRange = "misn0703.wav", underAttack = "misn0704.wav", utahReminder = "misn0719.wav",
    rookieTake = "misn0717.wav", -- the alternate take of 0702 (same subtitle intent, different read)
}
-- The MAG-cannon test objects no longer exist in the map. test_tank is an svtnk7
-- (the DLL's MAG tank) at test_tank_spawn. test_turret is a CCA-model turret (svturr)
-- on the support team: allied with every human so it never shoots players, hostile
-- to the CCA tank so the shot is a legitimate attack order. Position: the midpoint of
-- camera_path2 (x 3288.0..3249.33 at z 99037.6, the shot that films the turret)
-- moved 30 m south, toward the Testing Range nav (cam_spawn6 at 3260.8, 98985.3) and
-- away from the CCA factory at (3275.6, 99069.6): (3268.7, 99007.6).
local TEST_TURRET_AT = { 3268.7, 99007.6 }
local UTAH_NAG_DELAY_S = 120.0
local TEST_RANGE_HOLD_S = 150.0   -- after 0714, if the Utah is still not deployed
local TEST_RANGE_TIMEOUT_S = 90.0 -- Razor One's drive to cam_spawn6
local RAZOR_ARRIVE_M, RAZOR_RELEASE_M, RAZOR_REORDER_S = 60.0, 100.0, 10.0

-- The overlook call: the leader picks the original 0702 or the cut alternate 0717 once (50/50);
-- Play carries the chosen file to every peer's audio and subtitles.
local function PickRookieTake()
    if M.take0702 == nil then
        M.take0702 = (math.random(0, 1) == 0) and "misn0702.wav" or CUT_VO.rookieTake
    end
    return M.take0702
end

local function VoDone(handle)
    return handle == nil or handle == 0 or IsAudioMessageDone(handle)
end

-- Phase 2 has settled: radar down, Utah deployed (or 150 s), nothing still being said.
local function TestRangeOpen()
    return M.first_objective and (M.utah_found or M.test_range_after < GetTime()) and
        VoDone(M.audmsg) and VoDone(M.vo_last)
end

local function SpawnTestRange()
    M.test_tank = BuildObject("svtnk7", ENEMY_TEAM, "test_tank_spawn")
    SetIndependence(M.test_tank, 0)
    Stop(M.test_tank)
    M.test_turret = BuildObject("svturr", SUPPORT_TEAM, AtGround(TEST_TURRET_AT[1], TEST_TURRET_AT[2]))
    SetIndependence(M.test_turret, 0)
    M.test_tank_built = true
end

-- Razor One leaves the players for the test range, if there is still a Razor One.
local function BeginTestRangeTrip()
    M.test_range_started = true
    M.tr_timeout = GetTime() + TEST_RANGE_TIMEOUT_S
    M.tr_next = 0
    local unit = M.razor_unit
    if IsAlive(unit) then
        -- A pilot who never got a ride stops stealing and just goes.
        if M.rk ~= nil and M.rk.phase ~= "ride" then
            RazorOneReleaseSlot(M.rk)
            M.rk = nil
        end
        M.tr_unit, M.tr_hold = unit, true
    end
end

local function EndTestRangeTrip()
    M.tr_hold = false
    if IsAlive(M.tr_unit) then Follow(M.tr_unit, NearestPlayer(M.tr_unit), 0) end
end

-- 0703/0704 and the Testing Range, Mine Field and Mine Path beacons.
local function RestoredTestRange()
    if not M.first_objective then return end
    local now = GetTime()
    if (not M.test_range_started) and TestRangeOpen() then BeginTestRangeTrip() end
    if not M.test_range_started then return end
    local escorted = M.tr_hold and IsAlive(M.tr_unit)
    if (not M.recon_message2) then
        local arrived = (not escorted) or (Distance(M.tr_unit, "cam_spawn6") < RAZOR_ARRIVE_M) or
            (M.tr_timeout < now)
        if escorted and (not arrived) and (M.tr_next < now) then
            M.tr_next = now + RAZOR_REORDER_S
            Goto(M.tr_unit, "cam_spawn6", 1)
        end
        if arrived then
            M.vo_last = subtit.Play(CUT_VO.testRange) -- Razor One: Soviet test range beyond the minefield
            M.becon_build_time = now + 15.0
            M.check_range = now + 20.0
            M.recon_message2 = true
            SpawnTestRange()
        end
        return
    end
    -- He rejoins the players when one reaches him or the ambush is cleared.
    if M.tr_hold then
        if not escorted then
            M.tr_hold = false
        elseif AnyPlayerWithin(M.tr_unit, RAZOR_RELEASE_M) or
            (M.ambushed and (not IsAlive(M.ambush1)) and (not IsAlive(M.ambush2))) then
            EndTestRangeTrip()
        end
    end
    if (M.recon_message2) and (M.becon_build_time < now) and (not M.becon_build) then
        M.nav4 = BuildObject("apcamr", LEADER_TEAM, "cam_spawn6")
        SetObjectiveName(M.nav4, "Testing Range")
        M.rookie_rendezvous_time = now + 120.0
        M.becon_build = true
    end
    if (M.becon_build) and (M.rookie_rendezvous_time < now) and (not M.rookie_lost) then
        M.rookie_rendezvous_time = now + 21.0
        -- mine_geyz is gone from the map: the Mine Field beacon spawn point stands in.
        if NoPlayerWithin("cam_spawn1", 400.0) then
            -- The distress call is true: two CCA fighters hit him at the test range. With
            -- no Razor One left it is the DLL's radio-only call; if the players already
            -- reached him it is not made.
            local radio = not IsAlive(M.tr_unit)
            if M.tr_hold and (not M.ambushed) then
                M.ambush1 = BuildObject("svfigh", ENEMY_TEAM, "test_tank_spawn")
                M.ambush2 = BuildObject("svfigh", ENEMY_TEAM, "test_tank_spawn")
                Attack(M.ambush1, M.tr_unit)
                Attack(M.ambush2, M.tr_unit)
                M.ambushed = true
            end
            if M.ambushed or radio then
                M.vo_last = subtit.Play(CUT_VO.underAttack) -- under attack: meet Nav 5, follow the beacons
            end
            M.nav5 = BuildObject("apcamr", LEADER_TEAM, "cam_spawn1")
            SetObjectiveName(M.nav5, "Mine Field")
            M.reach_mine_time = now + 10.0
            M.rookie_lost = true
        end
    end
    if (M.rookie_lost) and (M.reach_mine_time < now) and (not M.mine_pathed) then
        M.reach_mine_time = now + 10.0
        if AnyPlayerWithin(M.nav5, 70.0) then
            M.becon1 = BuildObject("apcamr", LEADER_TEAM, "cam_spawn2")
            M.becon2 = BuildObject("apcamr", LEADER_TEAM, "cam_spawn3")
            M.becon3 = BuildObject("apcamr", LEADER_TEAM, "cam_spawn4")
            M.becon4 = BuildObject("apcamr", LEADER_TEAM, "cam_spawn5")
            SetObjectiveName(M.becon1, "Mine Path 1")
            SetObjectiveName(M.becon2, "Mine Path 2")
            SetObjectiveName(M.becon3, "Mine Path 3")
            SetObjectiveName(M.becon4, "Mine Path 4")
            M.mine_pathed = true
        end
    end
end

-- Streamed proximity mines: a node is live while any player is within 400 m.
-- m000 is not in the map, so nodes are checked for existence once. The nodes lie at
-- x 2671..3620, z 98393..98949; none is within 400 m of the start-to-rendezvous,
-- rendezvous-to-overlook or overlook-to-outpost routes (closest: m001, 420 m from the
-- start-to-overlook line), so they cannot spawn during the infiltration.
local function RestoredMineField()
    if M.mine_ok == nil then
        M.mine_ok = {}
        for index = 0, 110 do M.mine_ok[index] = GetPathPointCount(string.format("m%03d", index)) > 0 end
    end
    for index = M.mine_check, math.min(M.mine_check + 9, 110) do
        local name = M.mine[index]
        if name ~= nil and M.mine_ok[index] then
            if AnyPlayerWithin(name, 400.0) then
                if (not M.m_on[index]) and (not M.m_dead[index]) then
                    M.m[index] = BuildObject("proxmine", ENEMY_TEAM, name)
                    M.m_on[index] = true
                end
                if (M.m_on[index]) and (not IsAlive(M.m[index])) then
                    M.m_dead[index] = true
                end
            else
                if (M.m_on[index]) and (not M.m_dead[index]) then
                    if IsValid(M.m[index]) then RemoveObject(M.m[index]) end
                    M.m_on[index] = false
                end
            end
        end
    end
end

-- The MAG-cannon film. Shared timing on the leader; each player may skip their own view.
local function EndMagFilm()
    CameraFinish()
    M.camera_off = true
    if IsAlive(M.test_tank) then SetIndependence(M.test_tank, 1) end
end

local function SwapMagTank()
    RemoveObject(M.test_tank)
    M.test_tank = BuildObject("svtnk7", ENEMY_TEAM, "test_tank_spawn")
    Attack(M.test_tank, M.test_turret)
    M.tank_switch = true
end

local function RestoredMagCannon()
    local now = GetTime()
    -- The radar is down by now (the test objects exist only after 0703); one film at a time.
    if (M.recon_message2) and (not M.camera_ready) and (not M.game_over) and
        (cameraFrame == nil) and IsAlive(M.test_tank) and IsAlive(M.test_turret) then
        local who = FirstPlayerWithin(M.test_tank, 65.0)
        if who ~= nil then
            M.cine_player = who
            CameraReady()
            AddHealth(M.test_turret, -950.0)
            M.camera_ready = true
        end
    end
    if (not M.camera_ready) or M.camera_off then return end
    if CameraCancelled() or not IsAlive(M.test_turret) then
        -- Offline skip (or the turret is already down): resolve the unseen events.
        if (not M.tank_switch) and IsAlive(M.test_turret) then SwapMagTank() end
        EndMagFilm()
        return
    end
    local who = M.cine_player
    if not IsValid(who) then who = NearestPlayer(M.test_tank) end
    if not M.camera1_on then
        -- (0711, the developer joke line, is deliberately not played.)
        M.change_angle = now + 6.0
        M.camera1_on = true
    end
    if (M.camera1_on) and (M.change_angle >= now) and (not M.camera2_on) then
        CameraObject(M.test_tank, 2000, 800, 500, who)
    end
    if (M.camera1_on) and (M.change_angle < now) and (not M.camera3_on) then
        CameraPath("camera_path1", 250, 250, M.test_tank)
        M.camera2_on = true
    end
    if (M.camera2_on) and (not M.camera2_oned) then
        M.change_angle1 = now + 8.0
        M.camera2_oned = true
    end
    if (M.change_angle1 < now) and (not M.camera4_on) then
        CameraPath("camera_path2", 310, 500, M.test_turret)
        M.camera3_on = true
    end
    if (M.camera3_on) and (not M.camera3_oned) then
        M.change_angle2 = now + 6.0
        M.switch_tank = now + 5.0
        M.camera3_oned = true
    end
    if (M.switch_tank < now) and (not M.tank_switch) then
        SwapMagTank()
    end
    if (M.change_angle2 < now) and (not M.camera4_on) then
        M.change_angle3 = now + 10.0
        M.camera4_on = true
    end
    if M.camera4_on and (M.change_angle3 >= now) then
        CameraObject(M.test_turret, 1000, 300, 4700, M.test_turret)
    end
    if (M.camera4_on) and (M.change_angle3 < now) and (not M.camera_off) then
        EndMagFilm()
    end
end

-- 0719: Collins reminds the player about the Utah if it is still not deployed.
local function RestoredUtahReminder()
    if M.next_mission and (not M.utah_found) and (not M.utah_nagged) and (not M.game_over) and
        M.utah_nag_time < GetTime() then
        M.vo_last = subtit.Play(CUT_VO.utahReminder)
        M.utah_nagged = true
    end
end
-- Prototype svtnk7 production. When the MAG-cannon film ends (or is skipped), or the test
-- tank engages without one, the CCA starts fielding the prototype svtnk7 (weapon ga7stab:
-- charge6, 1450 ballistic damage, 75 m/s, 6 s reload). The stock misn07.aip cannot
-- express it: svmuf's buildItem list has no svtnk7 and the AIP is identical in 1.5 and
-- Redux. So the leader builds them at the CCA factory (M.ccamuf), charging team-5 scrap
-- like a real build, and sends them at the Utah (else the nearest player). Production
-- stops when the factory dies; tunables are at the top of the script.
local function PrototypeCap()
    local humans = CRCoop.ForEachHumanTeam(function() end)
    return math.min(PROTO_CAP_MAX, PROTO_CAP_BASE + PROTO_CAP_PER_PLAYER * math.max(0, humans - 1))
end

local function PrototypeTarget(from)
    if IsAlive(M.nsdfrecycle) then return M.nsdfrecycle end
    return NearestPlayer(from)
end

local function PrototypeTrigger()
    if M.camera_off then return true end -- the film finished or the leader skipped it
    if M.camera_ready or not M.recon_message2 then return false end
    -- No film: the test tank engaged (was hurt) or was destroyed.
    return M.test_tank ~= nil and ((not IsAlive(M.test_tank)) or GetHealth(M.test_tank) < 0.99)
end

local function RestoredPrototypeTanks()
    local now = GetTime()
    if M.proto_start == nil then
        if not PrototypeTrigger() then return end
        M.proto_start = now
        M.proto_next = now + PROTO_FIRST_DELAY_S
        M.proto_order = now + PROTO_FIRST_DELAY_S
    end
    local live = {}
    for _, tank in ipairs(M.proto) do
        if IsAlive(tank) then live[#live + 1] = tank end
    end
    M.proto = live
    if M.game_over then return end
    if M.proto_order < now then
        M.proto_order = now + PROTO_ORDER_S
        for _, tank in ipairs(live) do Attack(tank, PrototypeTarget(tank)) end
    end
    if not IsAlive(M.ccamuf) then return end -- no factory, no production
    if M.proto_next >= now then return end
    if #live >= PrototypeCap() or GetScrap(ENEMY_TEAM) < PROTO_SCRAP_COST then
        M.proto_next = now + PROTO_RETRY_S
        return
    end
    AddScrap(ENEMY_TEAM, -PROTO_SCRAP_COST)
    local tank = BuildObject("svtnk7", ENEMY_TEAM, M.ccamuf)
    M.proto[#M.proto + 1] = tank
    Attack(tank, PrototypeTarget(tank))
    M.proto_next = now + PROTO_INTERVAL_S
end
-- CR restored VO <<

local function InitializeCoop()
    CRCoop.Initialize({
        getLocalPlayerId = function() return exu.GetMyNetID and exu.GetMyNetID() end,
        leaderTeam = LEADER_TEAM, humanTeamMin = 1, humanTeamMax = 4,
        onOutOfLives = function() FailMission(GetTime() + 3.0) end,
        -- Respawns rally at the rendezvous nav (cam3) until the Utah deploys, then
        -- at the Utah (see the "Rally" presentation op).
        rallyPoints = { [0] = "cam3" },
    })
    ConfigureAlliances()
    ResetPresentation()
-- CR Venus weather >>
    ShutdownVenusWeather()
-- CR Venus weather <<
end

function Start()
    M = NewState()
    InitializeCoop()
    -- Here's where you set the values at the start.  
    M.mine_check=1
    M.x=6000
    M.units=1
    M.start_done=false
    M.out_of_car=false
    M.alarm_on=false
    M.start_evac=false
    M.ccaguntower1_down=false
    M.ccaguntower2_down=false
    M.radar_dead=false
    M.player_dead=false
    M.over_wall=false
    M.guntower_attacked=false
    M.fence_off=false
    M.unit_spawn=false
    M.recon_message1=false
    M.recon_message2=false
    M.build_scouts=false
    M.jump_cam_spawned=false
    M.rookie_moved=false
    M.rendezvous=false
    M.free1=false
    M.free2=false
    M.becon_build=false
    M.p1_retreat=false
    M.p2_retreat=false
    M.p3_retreat=false
    M.p4_retreat=false
    M.first_objective=false
    M.second_objective=false
    M.retreat_message_done=false
    M.turret_move=false
    M.next_mission=false
    M.rookie_lost=false
    M.mine_pathed=false
    M.getum=false
    M.detected=false
    M.patrola1=false
    M.patrola2=false
    M.patrolb1=false
    M.patrolb2=false
    M.patrolc1=false
    M.patrolc2=false
    M.retreat_success=false
    M.detected_message=false
    M.fighter_moved=false
    M.vehicle_stolen=false
    M.trigger1=false
    M.alarm_special=false
    M.alarm_sound=false
    M.rookie_removed=false
    M.forces_enroute=false
    M.test_tank_built=false
    M.camera_ready=false
    M.camera1_on=false
    M.camera2_on=false
    M.camera3_on=false
    M.camera4_on=false
    M.camera_off=false
    M.camera2_oned=false
    M.camera3_oned=false
    M.tank_switch=false
    M.sound_started=false
    M.test_found=false
    M.game_over=false
    M.first_camera_ready=false
    M.first_camera_off=false
    M.cute_camera_ready=false
    M.cute_camera_off=false
    M.radar_camera_off=false
    M.next_camera_on=false
    M.rookie_jumped=false
    M.tower_warning=false
    M.rookie_found=false
    M.opening_vo=false
    M.test=false
    M.utah_found=false
    M.shot1=false
    M.shot2=false
    for index = 0, 111 - 1 do
        M.count = index
        M.mine[M.count]=nil
        M.m_on[M.count]=false
        M.m_dead[M.count]=false
    end
    M.count = 111
    M.unit_spawn_time=99999.0
    M.recon_message_time=99999.0
    M.becon_build_time=99999.0
    M.rookie_move_time=99999.0
    M.getaway_message_time=99999.0
    M.rookie_rendezvous_time=99999.0
    M.patrol2_move_time=99999.0
    M.alarm_time=99999.0
    M.alarm_timer=99999.0
    M.rendezous_check=99999.0
    M.alarm_check=99999.0
    M.rookie_remove_time=99999.0
    M.runner_check=99999.0
    M.check_jump_geyser=99999.0
    M.reach_mine_time=99999.0
    M.check_range=99999.0
    M.change_angle=99999.0
    M.change_angle1=99999.0
    M.change_angle2=99999.0
    M.change_angle3=99999.0
    M.switch_tank=99999.0
    M.start_sound=99999.0
    M.recon_message2_time=99999.0
    M.first_camera_time=99999.0
    M.cute_camera_time=99999.0
    M.radar_camera_time=99999.0
    M.next_mission_time=99999.0
    M.next_shot_time=99999.0
    M.tower_check=99999.0
    M.turret1_spot=nil
    M.jump_geyz=GetHandle("volcano_geyz1")
    M.remove_geyz=GetHandle("volcano_geyz2")
    M.ccaguntower1=GetHandle("sgtower1")
    M.ccaguntower2=GetHandle("sgtower2")
    M.ccacomtower=GetHandle("radar_array")
    M.powrplnt1=GetHandle("power1")
    --	powrplnt2 = GetHandle ("power2");
    M.barrack1=GetHandle("hut1")
    M.barrack2=GetHandle("hut2")
    M.nav1=nil
    M.nav2=nil
    M.nav3=GetHandle("cam3")
    M.wingman1=GetHandle("avfigh1")
    M.wingman2=0
    M.wingtank1=GetHandle("avtank1")
-- CR rendezvous convoy >>
    -- The authored avtank2/avtank3 are gone from the map; the leader spawns the convoy.
    if not RENDEZVOUS_CONVOY then
-- CR rendezvous convoy <<
    M.wingtank2=GetHandle("avtank2")
    M.wingtank3=GetHandle("avtank3")
-- CR rendezvous convoy >>
    end
-- CR rendezvous convoy <<
    M.wingturret1=GetHandle("avturret1")
    M.wingturret2=GetHandle("avturret2")
    M.nsdfarmory=GetHandle("avslf")
    M.ccarecycle=GetHandle("svrecycler")
    M.ccamuf=GetHandle("svmuf")
    M.basepowrplnt1=GetHandle("svbasepower1")
    M.pbaseowrplnt2=GetHandle("svbasepower2")
    --	ccabaseguntower1 = GetHandle ("svbasetower1");
    --	ccabaseguntower2 = GetHandle ("svbasetower2");
    --	guard_tank1 = GetHandle ("svtank1");
    --	guard_tank2 = GetHandle ("svtank2");
    M.patrol1_1=GetHandle("svfigh1")
    M.patrol1_2=GetHandle("svfigh2")
    M.svpatrol1_1=GetHandle("svpatrol1_1")
    M.svpatrol1_2=GetHandle("svpatrol1_2")
    M.svpatrol2_1=GetHandle("svpatrol2_1")
    M.svpatrol2_2=GetHandle("svpatrol2_2")
    M.svpatrol3_1=GetHandle("svpatrol3_1")
    M.svpatrol3_2=GetHandle("svpatrol3_2")
    M.svpatrol4_1=GetHandle("svpatrol4_1")
    M.svpatrol4_2=GetHandle("svpatrol4_2")
    --	test_tank = GetHandle ("test_tank");
    M.guard_turret1=GetHandle("svturret1")
    M.guard_turret2=GetHandle("svturret2")
    M.parked1=GetHandle("parked1")
    M.parked2=GetHandle("parked2")
    M.parked3=GetHandle("parked3")
    M.parkturret1=GetHandle("pturret1")
    M.parkturret2=GetHandle("pturret2")
    M.svapc=GetHandle("parked_svapc")
    M.spawn_point=GetHandle("recycle_spawn_geyz")
    --	test_turret = GetHandle ("test_turret");
    --	mine_geyz = GetHandle("");
    --	tank_spawn = GetHandle ("test_tank_spawn");
    M.radar_geyser=GetHandle("radar_geyser")
    M.camera_geyser=GetHandle("camera_geyser")
    M.show_geyser=GetHandle("show_geyser")
    M.nsdfrecycle=nil
    M.nsdfmuf=nil
    M.jump_cam=nil
    M.rookie=nil
    M.nav4=nil
    M.nav5=nil
    M.nav6=nil
    M.nav7=nil
    M.audmsg=nil
    M.pilot1=nil
    M.pilot2=nil
    M.pilot3=nil
    M.pilot4=nil
    M.pilot5=nil
    M.spawn_turret1=nil
    M.spawn_turret2=nil
    M.becon1=nil
    M.becon2=nil
    M.becon3=nil
    M.becon4=nil
    M.new_tank1=nil
    M.new_tank2=nil
    subtit.Initialize()
end

function AddObject(h)
    -- Empty in the source.
-- CR Razor One infiltration >>
    RazorOneAdopt(h)
-- CR Razor One infiltration <<
-- CR Venus weather >>
    Environment.OnObjectCreated(h)
    CRVenusWeather.OnObjectCreated(h)
-- CR Venus weather <<
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

function Update(dt)
    subtit.Update()
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
-- CR Venus weather >>
    UpdateVenusWeather(dt)
-- CR Venus weather <<
    if not CRCoop.IsAuthority() then return end
    if CRCoop.IsNetworkGame() and not M.coopBootstrapped then
        M.coopBootstrapped = true
        -- The authored offline placeholder must not remain beside the humans.
        local offlinePlayer = GetHandle("player-1_hover")
        if IsValid(offlinePlayer) and not CRCoop.IsHumanCraft(offlinePlayer) then RemoveObject(offlinePlayer) end
    end
    -- Misn07Mission::Execute body (DLL order preserved below).
    -- START OF SCRIPT
    -- Here is where you put what happens  every frame.  
    M.user=GetPlayerHandle()
    --assigns the player a handle every frame
    M.mine_check=M.mine_check+10
-- CR rendezvous convoy >>
    UpdateConvoy()
-- CR rendezvous convoy <<
-- CR Razor One infiltration >>
    UpdateRazorOne()
    UpdateRazorHeal()
-- CR Razor One infiltration <<
-- CR Venus weather >>
    UpdateVenusBeats()
-- CR Venus weather <<
    if M.mine_check>110 then
        M.mine_check=1
    --[==[/*	if (!first_camera_ready)
	{
		CameraReady();
		audmsg = AudioMessage("misn0700.wav"); // General "mission breifing"
		first_camera_time = Get_Time() + 10.0f;
		first_camera_ready = true;
	}

	if ((first_camera_ready) && (!first_camera_off))
	{
		CameraPath("start_camera", x, 950, user);
		x = x - 100;
	}

	if ((first_camera_ready) && (!first_camera_off) && ((CameraCancelled()) || (first_camera_time < Get_Time())))
	{
		CameraFinish();
		first_camera_off = true;
	}

	if (CameraCancelled())
	{
		StopAudioMessage(audmsg);
	}
*/]==]
    end
    if not M.start_done then
        if M.nav3~=nil then
            SetObjectiveName(M.nav3,"Rendezvous Point")
        end
        SetScrap(1,10)
        SetObjectiveOff(M.ccacomtower)
        Patrol(M.patrol1_1,"patrol_path3")
        --
        Patrol(M.patrol1_2,"patrol_path3")
        --
        --		Patrol(guard_tank1, "guard_path");	//
        --		Patrol(guard_tank2, "guard_path");	// sets enemy units to their patrol routes
        Patrol(M.svpatrol3_1,"patrol_path1")
        --
        Patrol(M.svpatrol3_2,"patrol_path1")
        --
        Patrol(M.svpatrol4_1,"patrol_path2")
        --
        Patrol(M.svpatrol4_2,"patrol_path2")
        --
-- CR rendezvous convoy >>
        if RENDEZVOUS_CONVOY then SpawnConvoy() end
-- CR rendezvous convoy <<
        SetIndependence(M.wingtank2,0)
        Stop(M.wingtank2)
        SetPerceivedTeam(M.wingtank2,1)
        SetIndependence(M.wingtank3,0)
        Stop(M.wingtank3)
        SetPerceivedTeam(M.wingtank3,1)
        Stop(M.svpatrol2_1,1)
        Stop(M.svpatrol2_2,1)
        M.rendezous_check=GetTime()+9.0
        M.patrol2_move_time=GetTime()+121.0
        M.alarm_check=GetTime()+27.0
        M.turret1_spot="turret1_spot"
        for index = 0, 111 - 1 do
            M.count = index
            local name
            name = string.format("m%03d", M.count)
            M.mine[M.count]=name
        end
        M.count = 111
        M.start_done=true
    --	if (CameraCancelled())
    --	{
    --		Stopsubtit.Play(audmsg);
    --	}
    end
    if (not M.opening_vo) and (M.start_done) and (M.rendezous_check<GetTime()) then
        M.rendezous_check=GetTime()+15.0
        subtit.Play("misn0700.wav")
        -- General "mission breifing"
        ClearObjectives()
        AddObjective("misn0700.otf","white")
        M.opening_vo=true
    end
    if (M.start_done) and (M.patrol2_move_time<GetTime() and (not M.rendezvous)) and (IsAlive(M.svpatrol2_1)) and (IsAlive(M.svpatrol2_2)) and (not M.fighter_moved) then
        --		&& (GameObjectHandle::GetObj(svpatrol2_1)->GetHealth()<0.98f) // (GameObjectHandle::GetObj(svpatrol2_1)->GetLastEnemyShot()<0)
        --		&& (GameObjectHandle::GetObj(svpatrol2_2)->GetHealth()<0.98f)) //(GameObjectHandle::GetObj(svpatrol2_2)->GetLastEnemyShot()<0)) 
        Patrol(M.svpatrol2_1,"patrol_path1")
        -- sets enemy units to their patrol routes 
        Patrol(M.svpatrol2_2,"patrol_path1")
        -- sets enemy units to their patrol routes
        M.fighter_moved=true
    -- this is when the player rendezvous with the other tanks 
    end
    if not M.first_objective then
        if (M.rendezous_check<GetTime()) and (not M.rendezvous) and (not M.alarm_on) then
            M.rendezous_check=GetTime()+3.0
            if (IsAlive(M.wingtank2)) and (AnyPlayerWithin(M.wingtank2,150.0)) and (not M.rendezvous) or ((IsAlive(M.wingtank3)) and (AnyPlayerWithin(M.wingtank3,150.0)) and (not M.rendezvous)) then
                M.audmsg=subtit.Play("misn0701.wav")
                -- greetings comander "standby"
                if IsAlive(M.wingtank2) then
                    M.new_tank1=BuildObject("avtank",1,M.wingtank2)
                    RemoveObject(M.wingtank2)
                end
                if IsAlive(M.wingtank3) then
                    M.new_tank2=BuildObject("avtank",1,M.wingtank3)
                    RemoveObject(M.wingtank3)
                end
                ClearObjectives()
                AddObjective("misn0700.otf","green")
                AddObjective("misn0701.otf","white")
                M.recon_message_time=GetTime()+240.0
                M.runner_check=GetTime()+6.0
                M.patrol2_move_time=GetTime()+60.0
                M.nav1=BuildObject("apcamr",1,"cam1_spawn")
                --outpost cam
                if M.nav1~=nil then
                    SetObjectiveName(M.nav1,"CCA Outpost")
                end
                M.tower_check=GetTime()+10.0
                M.rendezvous=true
            end
        end
        if (M.rendezvous) and (M.patrol2_move_time<GetTime()) and (not M.fighter_moved) then
            if M.svpatrol2_1~=nil then
                Attack(M.svpatrol2_1,NearestPlayer(M.svpatrol2_1))
            end
            if M.svpatrol2_2~=nil then
                Attack(M.svpatrol2_2,NearestPlayer(M.svpatrol2_2))
            end
            M.fighter_moved=true
        --[==[/*	if ((rendezvous) && (IsAlive (wingtank3)) && (!free1))				
	{																		
		Stop(wingtank3, 0);												
		free1 = true;														
	}																			
																							
	if ((rendezvous) && (IsAlive (wingtank2)) && (!free2))									
	{																					
		Stop(wingtank2, 0);															
		free2 = true;																		
	}
*/]==]
        end
        if (IsAlive(M.nav1)) and (M.tower_check<GetTime()) and (not M.tower_warning) then
            M.tower_check=GetTime()+4.0
            if AnyPlayerWithin(M.nav1,90.0) then
                subtit.Play("misn0716.wav")
                M.tower_warning=true
            end
        end
    -- this is when the rookie tells the player about the overlook into the base and lays down a camera
    --////////////////////////////ROOKIE SCRIPT 1 HE JUMPS IN FRONT OF PLAYER ////////////////////////////	
    --[==[/*																										
if ((!first_objective) && (!alarm_on) && (!out_of_car))
{
	if ((rendezvous) && (!jump_cam_spawned) && (recon_message_time < Get_Time()))
	{
		recon_message_time = Get_Time() + 20.0f;

	    if ((GetDistance(user, jump_geyz) > 400.0f) && (GetDistance(user, ccacomtower) > 150.0f))
		{																											
//			AudioMessage("misn0702.wav"); // Rookie "I found an overlook"										
			AudioMessage("win.wav"); // Rookie trasmits a broken message saying he's found a way in and screams YAAAAAAAHHHHHHOOOOOO!
			jump_cam = BuildObject ("apcamr", 1, "jump_cam_spawn"); //Rookie drops camera			
			rookie = BuildObject ("avfigh", 1, jump_geyz);// spawn in rookie										
			Goto (rookie, jump_cam);//rookie goes to jump-cam to get in picture
			rookie_move_time = Get_Time() + 20.0f; // sets time to move rookie to secret spot
			recon_message2_time = Get_Time() + 480.0f;
			jump_cam_spawned = true;																				
		}																											
	}																																																						//
	
	if ((jump_cam_spawned) && (jump_cam!=NULL))
	{
		GameObjectHandle::GetObj(jump_cam)->SetName("Volcano Peak");
	}
	
	if ((jump_cam_spawned) && (rookie_move_time < Get_Time()) && (!rookie_moved))								
	{																											
		Defend(rookie, 1); 
		rookie_remove_time = Get_Time() + 15.0f;
		rookie_moved = true;																					
	}																							
	
	if ((rookie_moved) && (rookie_remove_time < Get_Time()) && (!rookie_removed))
	{
		rookie_remove_time = Get_Time() + 5.0f;

		if (IsAlive(rookie))
		{
			Defend(rookie, 1);

			if (GetDistance(user, rookie) < 70.0f)
			{
				audmsg = AudioMessage("win.wav");
				rookie_removed = true;
			}
		}
	}

	if ((rookie_removed) && (IsAudioMessageDone(audmsg)) && (!rookie_jumped))
	{
		Damage(rookie, 5000);
		rookie_jumped = true;
	}

//	if ((rookie_moved) && (rookie_remove_time < Get_Time()) && (!rookie_removed)) // rookie reaches secret spot
//	{																								
//		RemoveObject(rookie);// I take rookie away so that he is safe
//		rookie_removed = true;
//	}
}
*/]==]
    --////////////////////////////ROOKIE SCRIPT 2 HE JUMPS ON CAMERA ////////////////////////////
    end
    if (not M.first_objective) and (not M.alarm_on) and (not M.out_of_car) then
        if (M.rendezvous) and (not M.jump_cam_spawned) and ((M.recon_message_time<GetTime()) or (M.tower_warning)) then
            M.recon_message_time=GetTime()+5.0
            M.units=0
            CRCoop.ForEachPlayerHandle(function(h)
                M.units=M.units+CountUnitsNearObject(h,200.0,ENEMY_TEAM,"svfigh")
            end)
            if (NoPlayerWithin(M.jump_geyz,400.0)) and (M.units==0) then
-- CR restored VO >>
                if RESTORED_VO then subtit.Play(PickRookieTake()) else
-- CR restored VO <<
                subtit.Play("misn0702.wav")
-- CR restored VO >>
                end
-- CR restored VO <<
                -- Rookie trasmits a broken message saying player should look at camera
                M.jump_cam=BuildObject("apcamr",1,"jump_cam_spawn")
                M.rookie=BuildObject("avfigh",1,M.jump_geyz)
                Follow(M.rookie,M.jump_geyz)
                M.rookie_move_time=GetTime()+10.0
                --			recon_message2_time = Get_Time() + 480.0f;
                M.jump_cam_spawned=true
            end
        end
        if (M.jump_cam_spawned) and (M.jump_cam~=nil) then
            SetObjectiveName(M.jump_cam,"Volcano Peak")
        end
        if (M.jump_cam_spawned) and (M.rookie_move_time<GetTime()) and (not M.rookie_moved) then
            --		if (IsAlive(rookie))
            --		{
            --			Defend(rookie, 1);
            --		}
            M.rookie_remove_time=GetTime()+10.0
            M.rookie_moved=true
        end
        if (M.rookie_moved) and (M.rookie_remove_time<GetTime()) and (not M.rookie_found) then
            M.rookie_remove_time=GetTime()+3.0
            if IsAlive(M.rookie) then
                --			Defend(rookie);
                if AnyPlayerWithin(M.rookie,70.0) then
                    Defend(M.rookie,1)
                    subtit.Play("misn0718.wav")
                    -- rookie sends broken message he's found a way inside base
                    M.rookie_remove_time=GetTime()+10.0
                    M.rookie_found=true
                end
            end
        end
        if (M.rookie_found) and (M.rookie_remove_time<GetTime()) and (not M.rookie_removed) then
            if IsAlive(M.rookie) then
                subtit.Play("misn0715.wav")
                -- screams YAAAAAAAHHHHHHOOOOOO!
-- CR Razor One infiltration >>
                BeginRazorOneFlight()
-- CR Razor One infiltration <<
                EjectPilot(M.rookie)
                M.rookie_removed=true
            end
        end
    -- end rookie at overlook - he heads off to mine field //////////////////////////////////
    -- this is when the player tries to go into the radar array base w/out jumping in (in his tank) 
    end
    if (M.alarm_check<GetTime()) and (not M.alarm_on) then
        M.alarm_check=GetTime()+5.0
        --[==[/*		if ((!alarm_on) && (!out_of_car) && (GetDistance(user, turret1_spot) < 90.0f))// this is if the player attacks the gun towers around the solar array
		{
			AudioMessage("misn0710.wav");// you've tripped the alarm
			SetObjectiveOn(ccacomtower);
			SetObjectiveName(ccacomtower, "Radar Array");
			alarm_on = true;
		}
*/]==]
        -- Per-player: trips if ANY player who has not infiltrated is at the gun towers,
        -- even after a teammate has parachuted in.
        if (not M.alarm_on) and CRCoop.AnyPlayerSatisfies(function(h, id)
            return (not M.infiltrated[PlayerKey(id)]) and (Distance(h,M.turret1_spot)<70.0)
        end) then
            -- this is if the player attacks the gun towers around the solar array
            subtit.Play("misn0710.wav")
            -- you've tripped the alarm
            SetObjectiveOn(M.ccacomtower)
            SetObjectiveName(M.ccacomtower,"Radar Array")
            M.alarm_on=true
        end
    -- end of player trying to enter radar base in tank 
    -- now that the alarm is on the task will be more difficult
    end
    if not M.first_objective then
        if M.alarm_on then
            -- this code makes the alarm sound
            if (M.ccacomtower~=nil) and (AnyPlayerWithin(M.ccacomtower,170.0)) and (not M.alarm_sound) then
                subtit.Play("misn0708.wav")
                -- this is the alarm sound		
                M.alarm_timer=GetTime()+6.0
                M.alarm_sound=true
            end
            if (M.alarm_sound) and (M.alarm_timer<GetTime()) then
                M.alarm_sound=false
            end
            if not M.turret_move then
                SetObjectiveOn(M.ccacomtower)
                SetObjectiveName(M.ccacomtower,"Radar Array")
                Retreat(M.guard_turret1,M.ccacomtower,1)
                Retreat(M.guard_turret2,M.ccacomtower,1)
                M.turret_move=true
            end
            if not M.start_evac then
                --starts clock to spawn cca soldiers
                M.unit_spawn_time=GetTime()+20.0
                M.start_evac=true
            end
            if (M.start_evac) and (M.unit_spawn_time<GetTime()) and (not M.unit_spawn) and (not M.alarm_special) then
                -- spawns cca soldiers and tells them to go to their tanks
                M.pilot1=BuildObject("sspilo",ENEMY_TEAM,"hut2_spawn")
                M.pilot2=BuildObject("sspilo",ENEMY_TEAM,"hut2_spawn")
                M.pilot3=BuildObject("sspilo",ENEMY_TEAM,"hut2_spawn")
                M.pilot4=BuildObject("sspilo",ENEMY_TEAM,"hut1_spawn")
                M.pilot5=BuildObject("sspilo",ENEMY_TEAM,"hut1_spawn")
                if not IsAnyPlayer(M.parkturret1) then
                    M.spawn_turret1=BuildObject("svturr",ENEMY_TEAM,M.parkturret1)
                    Defend(M.spawn_turret1)
                    RemoveObject(M.parkturret1)
                end
                if not IsAnyPlayer(M.parkturret2) then
                    M.spawn_turret2=BuildObject("svturr",ENEMY_TEAM,M.parkturret2)
                    Defend(M.spawn_turret2)
                    RemoveObject(M.parkturret2)
                -- these lines tell the soviet pilots to get to their ships
                end
                if M.parked1~=nil then
                    Retreat(M.pilot1,M.parked1,1)
                end
                if M.parked2~=nil then
                    Retreat(M.pilot2,M.parked2,1)
                end
                if M.parked3~=nil then
                    Retreat(M.pilot3,M.parked3,1)
                end
                M.unit_spawn=true
            -- this is what happens when the player is in the base and sets off the alarm while out of a vehcile
            end
            if (M.start_evac) and (M.alarm_special) and (M.unit_spawn_time<GetTime()) and (not M.unit_spawn) then
                -- spawns cca soldiers and tells them to go to their tanks
                M.pilot1=BuildObject("sspilo",ENEMY_TEAM,"hut2_spawn")
                M.pilot2=BuildObject("sspilo",ENEMY_TEAM,"hut2_spawn")
                M.pilot3=BuildObject("sssold",ENEMY_TEAM,"hut2_spawn")
                M.pilot4=BuildObject("sspilo",ENEMY_TEAM,"hut1_spawn")
                M.pilot5=BuildObject("sssold",ENEMY_TEAM,"hut1_spawn")
                Attack(M.pilot3,NearestPlayer(M.pilot3))
                Attack(M.pilot5,NearestPlayer(M.pilot5))
                -- these lines tell the soviet pilots to get to their ships
                if M.parked1~=nil then
                    Retreat(M.pilot1,M.parked1,1)
                end
                if M.parked2~=nil then
                    Retreat(M.pilot2,M.parked2,1)
                end
                if M.parked3~=nil then
                    Retreat(M.pilot4,M.parkturret1,1)
                end
                M.unit_spawn=true
            -- this is an attempt to find out if a pilot has gotten to his ship and then give them orders
            end
            if (M.unit_spawn) and (not M.alarm_special) then
                if (not IsAlive(M.pilot1)) and (M.parked1~=nil) then
                    Attack(M.parked1,NearestPlayer(M.parked1))
                end
                if (not IsAlive(M.pilot2)) and (M.parked2~=nil) then
                    Attack(M.parked2,NearestPlayer(M.parked2))
                end
                if (not IsAlive(M.pilot3)) and (M.parked3~=nil) then
                    Attack(M.parked3,NearestPlayer(M.parked3))
                --[==[/*			if ((!IsAlive(pilot4)) && (parkturret1!=NULL))
			{
				Retreat(parkturret1, turret1_spot);		
			}
			if ((!IsAlive(pilot5)) && (parkturret2!=NULL))
			{
				Retreat(parkturret2, "turret2_spot");
			}
*/]==]
                end
            end
            if (M.unit_spawn) and (M.alarm_special) then
                if (not IsAlive(M.pilot1)) and (M.parked1~=nil) then
                    Goto(M.parked1,M.ccacomtower)
                end
                if (not IsAlive(M.pilot2)) and (M.parked2~=nil) then
                    Goto(M.parked2,M.ccacomtower)
                end
                if (not IsAlive(M.pilot4)) and (M.parkturret1~=nil) then
                    Retreat(M.parkturret1,"turret1_spot")
                end
            --		if (((!alarm_special) && (!IsAlive(ccaguntower1)) && (!forces_enroute)) || 
            --			((!alarm_special) && (!IsAlive(ccaguntower2)) && (!forces_enroute)))
            end
            if (IsAlive(M.ccacomtower)) and (GetHealth(M.ccacomtower)<0.50) and (not M.forces_enroute) then
                --			if (IsAlive(svpatrol1_1))
                --			{
                --				Goto(svpatrol1_1, ccacomtower, 1);
                --			}
                if IsAlive(M.svpatrol1_2) then
                    Goto(M.svpatrol1_2,M.ccacomtower,1)
                --			if (IsAlive(svpatrol2_1))
                --			{
                --				Goto(svpatrol2_1, ccacomtower, 1);
                --			}
                --			if (IsAlive(svpatrol2_2))
                --			{
                --				Goto(svpatrol2_2, ccacomtower, 1);
                --			}
                end
                if IsAlive(M.svpatrol3_1) then
                    Goto(M.svpatrol3_1,M.ccacomtower,1)
                --			if (IsAlive(svpatrol3_2))
                --			{
                --				Goto(svpatrol3_2, ccacomtower, 1);
                --			}
                end
                if IsAlive(M.svpatrol4_1) then
                    Goto(M.svpatrol4_1,M.ccacomtower,1)
                --			if (IsAlive(svpatrol4_2))
                --			{
                --				Goto(svpatrol4_2, ccacomtower, 1);
                --			}
                end
                M.forces_enroute=true
            end
        end
    -- this is what happens when the player parachutes into the base
    end
    if not M.first_objective then
        -- Per-player infiltration; out_of_car now means "any player has infiltrated".
        local newcomer = false
        if not M.alarm_on then
            CRCoop.ForEachPlayerHandle(function(h, id)
                local key = PlayerKey(id)
                if (not M.infiltrated[key]) and (Distance(h,M.camera_geyser)<160.0) then
                    M.infiltrated[key] = true
                    newcomer = true
                end
            end)
        end
        if newcomer then
            -- this indicates that the player has parachuted into the solar array
            if not M.out_of_car then
                SetObjectiveOn(M.ccacomtower)
                SetObjectiveName(M.ccacomtower,"Radar Array")
            end
            --		cute_camera_time = Get_Time() + 5.0f;
            M.out_of_car=true
        --[==[/*	// this will start the camera on the player
	if ((out_of_car) && (!cute_camera_ready) && (cute_camera_time < Get_Time()))
	{
		CameraReady();
		cute_camera_time = Get_Time() + 5.0f;
		cute_camera_ready = true;
	}

	if ((cute_camera_ready) && (!cute_camera_off))
	{
		CameraObject(user, 800, 800, 10, user);	
	}

	if ((cute_camera_ready) && (!cute_camera_off))
	{
		if (cute_camera_time < Get_Time())
		{
			CameraFinish();
			cute_camera_off = true;
		}
	}
*/]==]
        -- this indicates when the player has taken over a vehicle
        end
        -- Stolen-vehicle detection is latched per infiltrated player; vehicle_stolen means
        -- every infiltrator has taken a Soviet vehicle, so one player still on foot (or in
        -- an NSDF craft) earns the special soldier alarm.
        CRCoop.ForEachPlayerHandle(function(h, id)
            local key = PlayerKey(id)
            if M.infiltrated[key] and ((IsOdfBase(h,"svtank")) or (IsOdfBase(h,"svfigh")) or (IsOdfBase(h,"svturr"))) then
                M.stolen[key] = true
            end
        end)
        M.vehicle_stolen = AllInfiltratorsStolen()
        --		alarm_time = Get_Time() + 20.0f;
        -- this simply means that if the player fires on anything while in the base he will set off an alarm
        if not M.trigger1 and M.out_of_car then
            if AliveButDamaged(M.ccaguntower1) or AliveButDamaged(M.ccaguntower2) or AliveButDamaged(M.ccacomtower) or AliveButDamaged(M.powrplnt1) or AliveButDamaged(M.barrack1) or AliveButDamaged(M.barrack2) or AliveButDamaged(M.parked1) or AliveButDamaged(M.parked2) or AliveButDamaged(M.parked3) or AliveButDamaged(M.parkturret1) or AliveButDamaged(M.parkturret2) then
            --[==[// AliveButDamaged(powrplnt2) ||]==]
                M.trigger1=true
            end
        end
        if (M.trigger1) and (M.vehicle_stolen) and (not M.alarm_on) then
            M.alarm_on=true
        end
        if (M.trigger1) and (not M.vehicle_stolen) and (not M.alarm_on) then
            M.alarm_on=true
            M.alarm_special=true
        end
    -- end parachute into base
    -- the following code triggers the solar array alarm if the player orders ANY of his units to attack the gun towers protecting it
    end
    if not M.first_objective then
        if (not M.alarm_on) and (not M.out_of_car) and (Distance(M.wingman1,M.turret1_spot)<100.0) then
            subtit.Play("misn0709.wav")
            --I've tripped the alarm sir
            M.alarm_on=true
        end
        if (not M.alarm_on) and (not M.out_of_car) and (Distance(M.wingman2,M.turret1_spot)<100.0) then
            subtit.Play("misn0709.wav")
            --I've tripped the alarm sir
            M.alarm_on=true
        end
        if (not M.alarm_on) and (not M.out_of_car) and (Distance(M.wingtank1,M.turret1_spot)<100.0) then
            subtit.Play("misn0709.wav")
            --I've tripped the alarm sir
            M.alarm_on=true
        end
        if (not M.alarm_on) and (not M.out_of_car) and (Distance(M.new_tank1,M.turret1_spot)<100.0) then
            subtit.Play("misn0709.wav")
            --I've tripped the alarm sir
            M.alarm_on=true
        end
        if (not M.alarm_on) and (not M.out_of_car) and (Distance(M.new_tank2,M.turret1_spot)<100.0) then
            subtit.Play("misn0709.wav")
            --I've tripped the alarm sir
            M.alarm_on=true
        --[==[/*		if ((!alarm_on) && (!out_of_car) && (GetDistance(wingturret1, turret1_spot) < 100.0f))
		{
			AudioMessage("misn0709.wav"); //I've tripped the alarm sir
			alarm_on = true;
		}

		if ((!alarm_on) && (!out_of_car) && (GetDistance(wingturret2, turret1_spot) < 100.0f))
		{
			AudioMessage("misn0709.wav"); //I've tripped the alarm sir
			alarm_on = true;
		}

*/]==]
        end
    -- end of alarm trigger for other vehicles //////////////////////////////////////////////////////////
    -- this is an attempt to make the soviets retreat ///////////////////////////////////////////////////
    end
    if not M.first_objective then
        if not M.retreat_success then
            if IsAlive(M.svpatrol1_2) then
                if (not IsAlive(M.svpatrol1_1)) and (M.rendezvous) and (IsAlive(M.ccarecycle)) and (not M.first_objective) and (not M.mine_pathed) and (not M.alarm_on) and (AnyPlayerWithin(M.svpatrol1_2,50.0)) and (not M.p1_retreat) and (not M.p2_retreat) and (not M.p3_retreat) then
                    Retreat(M.svpatrol1_2,M.ccarecycle)
                    SetObjectiveOn(M.svpatrol1_2)
                    SetObjectiveName(M.svpatrol1_2,"Runner")
                    M.getaway_message_time=GetTime()+3.0
                    M.p1_retreat=true
                end
            end
            if IsAlive(M.svpatrol1_1) then
                if (not IsAlive(M.svpatrol1_2)) and (M.rendezvous) and (IsAlive(M.ccarecycle)) and (not M.first_objective) and (not M.mine_pathed) and (not M.alarm_on) and (AnyPlayerWithin(M.svpatrol1_1,50.0)) and (not M.p1_retreat) and (not M.p2_retreat) and (not M.p3_retreat) then
                    Retreat(M.svpatrol1_1,M.ccarecycle)
                    SetObjectiveOn(M.svpatrol1_1)
                    SetObjectiveName(M.svpatrol1_1,"Runner")
                    M.getaway_message_time=GetTime()+3.0
                    M.p1_retreat=true
                end
            --[==[/*		if ((!IsAlive (svpatrol2_1)) && (rendezvous) && (IsAlive(ccarecycle)) && (!first_objective) 
			&& (!mine_pathed) && (!alarm_on) && (GetDistance(user,svpatrol2_2) < 50.0f)  && (!p2_retreat)
			&& (!p1_retreat) && (!p3_retreat))
		{
			Retreat(svpatrol2_2, ccarecycle);
			SetObjectiveOn(svpatrol2_2);
			SetObjectiveName(svpatrol2_2, "Runner");
			getaway_message_time = Get_Time() + 3.0f;
			p2_retreat = true;
		}

		if ((!IsAlive (svpatrol2_2)) && (rendezvous) && (IsAlive(ccarecycle)) && (!first_objective) 
			&& (!mine_pathed) && (!alarm_on) && (GetDistance(user,svpatrol2_1) < 50.0f)  && (!p2_retreat)
			&& (!p1_retreat) && (!p3_retreat))
		{
			Retreat(svpatrol2_1, ccarecycle);
			SetObjectiveOn(svpatrol2_1);
			SetObjectiveName(svpatrol2_1, "Runner");
			getaway_message_time = Get_Time() + 3.0f;
			p2_retreat = true;
		}
*/]==]
            end
            if IsAlive(M.svpatrol3_2) then
                if (not IsAlive(M.svpatrol3_1)) and (M.rendezvous) and (IsAlive(M.ccarecycle)) and (not M.first_objective) and (not M.mine_pathed) and (not M.alarm_on) and (AnyPlayerWithin(M.svpatrol3_2,50.0)) and (not M.p2_retreat) and (not M.p1_retreat) and (not M.p3_retreat) then
                    Retreat(M.svpatrol3_2,M.ccarecycle)
                    SetObjectiveOn(M.svpatrol3_2)
                    SetObjectiveName(M.svpatrol3_2,"Runner")
                    M.getaway_message_time=GetTime()+3.0
                    M.p3_retreat=true
                end
            end
            if IsAlive(M.svpatrol3_1) then
                if (not IsAlive(M.svpatrol3_2)) and (M.rendezvous) and (IsAlive(M.ccarecycle)) and (not M.first_objective) and (not M.mine_pathed) and (not M.alarm_on) and (AnyPlayerWithin(M.svpatrol3_1,50.0)) and (not M.p2_retreat) and (not M.p1_retreat) and (not M.p3_retreat) then
                    Retreat(M.svpatrol3_1,M.ccarecycle)
                    SetObjectiveOn(M.svpatrol3_1)
                    SetObjectiveName(M.svpatrol3_1,"Runner")
                    M.getaway_message_time=GetTime()+3.0
                    M.p3_retreat=true
                end
            -- this is the player being warned when one is getting away.
            end
            if (not M.retreat_success) and (not M.getum) then
                if ((M.p1_retreat) and (M.getaway_message_time<GetTime()) and (IsAlive(M.new_tank1)) and (not M.getum)) or ((M.p1_retreat) and (M.getaway_message_time<GetTime()) and (IsAlive(M.new_tank2)) and (not M.getum)) then
                    subtit.Play("misn0705.wav")
                    -- one of'ms making a break for it!
                    M.getum=true
                end
                if ((M.p2_retreat) and (M.getaway_message_time<GetTime()) and (IsAlive(M.new_tank1)) and (not M.getum)) or ((M.p2_retreat) and (M.getaway_message_time<GetTime()) and (IsAlive(M.new_tank2)) and (not M.getum)) then
                    subtit.Play("misn0705.wav")
                    -- one of'ms making a break for it!
                    M.getum=true
                end
                if ((M.p3_retreat) and (M.getaway_message_time<GetTime()) and (IsAlive(M.new_tank1)) and (not M.getum)) or ((M.p3_retreat) and (M.getaway_message_time<GetTime()) and (IsAlive(M.new_tank2)) and (not M.getum)) then
                    subtit.Play("misn0705.wav")
                    -- one of'ms making a break for it!
                    M.getum=true
                end
            -- this is to set up the "that's gotum" message
            end
            if (M.p1_retreat) and (IsAlive(M.svpatrol1_1)) then
                M.patrola1=true
            end
            if (M.p1_retreat) and (IsAlive(M.svpatrol1_2)) then
                M.patrola2=true
            end
            if (M.p2_retreat) and (IsAlive(M.svpatrol2_1)) then
                M.patrolb1=true
            end
            if (M.p2_retreat) and (IsAlive(M.svpatrol2_2)) then
                M.patrolb2=true
            end
            if (M.p3_retreat) and (IsAlive(M.svpatrol3_1)) then
                M.patrolc1=true
            end
            if (M.p3_retreat) and (IsAlive(M.svpatrol3_2)) then
                M.patrolc2=true
            end
            if ((M.p1_retreat) and (M.patrola1) and (not IsAlive(M.svpatrol1_1)) and (IsAlive(M.new_tank1))) or ((M.p1_retreat) and (M.patrola1) and (not IsAlive(M.svpatrol1_1)) and (IsAlive(M.new_tank2))) then
                subtit.Play("misn0706.wav")
                -- that got'um!
                --			SetObjectiveOff(svpatrol1_1);
                M.p1_retreat=false
                M.patrola1=false
                M.getum=false
            end
            if ((M.p1_retreat) and (M.patrola2) and (not IsAlive(M.svpatrol1_2)) and (IsAlive(M.new_tank1))) or ((M.p1_retreat) and (M.patrola2) and (not IsAlive(M.svpatrol1_2)) and (IsAlive(M.new_tank2))) then
                subtit.Play("misn0706.wav")
                -- that got'um!
                --			SetObjectiveOff(svpatrol1_2);
                M.p1_retreat=false
                M.patrola2=false
                M.getum=false
            end
            if ((M.p2_retreat) and (M.patrolb1) and (not IsAlive(M.svpatrol2_1)) and (IsAlive(M.new_tank1))) or ((M.p2_retreat) and (M.patrolb1) and (not IsAlive(M.svpatrol2_1)) and (IsAlive(M.new_tank2))) then
                subtit.Play("misn0706.wav")
                -- that got'um!
                --			SetObjectiveOff(svpatrol2_1);
                M.p2_retreat=false
                M.patrolb1=false
                M.getum=false
            end
            if ((M.p2_retreat) and (M.patrolb2) and (not IsAlive(M.svpatrol2_2)) and (IsAlive(M.new_tank1))) or ((M.p2_retreat) and (M.patrolb2) and (not IsAlive(M.svpatrol2_2)) and (IsAlive(M.new_tank2))) then
                subtit.Play("misn0706.wav")
                -- that got'um!
                --			SetObjectiveOff(svpatrol2_2);
                M.p2_retreat=false
                M.patrolb2=false
                M.getum=false
            end
            if ((M.p3_retreat) and (M.patrolc1) and (not IsAlive(M.svpatrol3_1)) and (IsAlive(M.new_tank1))) or ((M.p3_retreat) and (M.patrolc1) and (not IsAlive(M.svpatrol3_1)) and (IsAlive(M.new_tank2))) then
                subtit.Play("misn0706.wav")
                -- that got'um!
                --			SetObjectiveOff(svpatrol3_1);
                M.p3_retreat=false
                M.patrolc1=false
                M.getum=false
            end
            if ((M.p3_retreat) and (M.patrolc2) and (not IsAlive(M.svpatrol3_2)) and (IsAlive(M.new_tank1))) or ((M.p3_retreat) and (M.patrolc2) and (not IsAlive(M.svpatrol3_2)) and (IsAlive(M.new_tank2))) then
                subtit.Play("misn0706.wav")
                -- that got'um!
                --			SetObjectiveOff(svpatrol3_2);
                M.p3_retreat=false
                M.patrolc2=false
                M.getum=false
            end
        -- this is what happens if an enemy unit gets away - tanks will come out
        end
        if (M.patrola1) and (not M.retreat_success) and (not M.alarm_on) and (Distance(M.svpatrol1_1,M.ccarecycle)<100.0) and (M.ccarecycle~=nil) and (IsAlive(M.ccarecycle)) then
            SetObjectiveOff(M.svpatrol1_1)
            M.retreat_success=true
        end
        if (M.patrola2) and (not M.retreat_success) and (not M.alarm_on) and (Distance(M.svpatrol1_2,M.ccarecycle)<100.0) and (M.ccarecycle~=nil) and (IsAlive(M.ccarecycle)) then
            SetObjectiveOff(M.svpatrol1_2)
            M.retreat_success=true
        end
        if (M.patrolb1) and (not M.retreat_success) and (not M.alarm_on) and (Distance(M.svpatrol2_1,M.ccarecycle)<100.0) and (M.ccarecycle~=nil) and (IsAlive(M.ccarecycle)) then
            SetObjectiveOff(M.svpatrol2_1)
            M.retreat_success=true
        end
        if (M.patrolb2) and (not M.retreat_success) and (not M.alarm_on) and (Distance(M.svpatrol2_2,M.ccarecycle)<100.0) and (M.ccarecycle~=nil) and (IsAlive(M.ccarecycle)) then
            SetObjectiveOff(M.svpatrol2_2)
            M.retreat_success=true
        end
        if (M.patrolc1) and (not M.retreat_success) and (not M.alarm_on) and (Distance(M.svpatrol3_1,M.ccarecycle)<100.0) and (M.ccarecycle~=nil) and (IsAlive(M.ccarecycle)) then
            SetObjectiveOff(M.svpatrol3_1)
            M.retreat_success=true
        end
        if (M.patrolc2) and (not M.retreat_success) and (not M.alarm_on) and (Distance(M.svpatrol3_2,M.ccarecycle)<100.0) and (M.ccarecycle~=nil) and (IsAlive(M.ccarecycle)) then
            SetObjectiveOff(M.svpatrol3_2)
            M.retreat_success=true
        -- this is the message that they were detected
        end
        if ((M.retreat_success) and (IsAlive(M.new_tank1)) and (not M.detected_message)) or ((M.retreat_success) and (IsAlive(M.new_tank2)) and (not M.detected_message)) then
            subtit.Play("misn0707.wav")
            -- one of the runers has made it back
            M.detected_message=true
        -- now that the player is detetected the soviets will send tanks out to scout
        end
        if (M.retreat_success) and (not IsAlive(M.svpatrol1_1)) and (not IsAlive(M.svpatrol1_2)) and (not IsAlive(M.svpatrol1_3)) and (IsAlive(M.ccarecycle)) then
            M.svpatrol1_1=BuildObject("svtank",ENEMY_TEAM,M.ccarecycle)
            M.svpatrol1_2=BuildObject("svtank",ENEMY_TEAM,M.ccarecycle)
            --				svpatrol1_3 = BuildObject("svtank", 2, ccarecycle);
            Patrol(M.svpatrol1_1,"patrol_path1")
            Patrol(M.svpatrol1_2,"patrol_path1")
            --				Patrol(svpatrol1_3, "patrol_path1");
        --[==[/*			if ((retreat_success) && (!IsAlive(svpatrol2_1)) && 
				(!IsAlive(svpatrol2_2)) && (!IsAlive(svpatrol2_3)) && (IsAlive(ccarecycle)))

			{																					
				svpatrol2_1 = BuildObject("svtank", 2, ccarecycle);
				svpatrol2_2 = BuildObject("svtank", 2, ccarecycle);
				svpatrol2_3 = BuildObject("svtank", 2, ccarecycle);
				Patrol(svpatrol2_1, "patrol_path1");	
				Patrol(svpatrol2_2, "patrol_path1");
				Patrol(svpatrol2_3, "patrol_path1");
			}																					
*/]==]
        end
        if (M.retreat_success) and (not IsAlive(M.svpatrol3_1)) and (not IsAlive(M.svpatrol3_2)) and (not IsAlive(M.svpatrol3_3)) and (IsAlive(M.ccarecycle)) then
            M.svpatrol3_1=BuildObject("svtank",ENEMY_TEAM,M.ccarecycle)
            M.svpatrol3_2=BuildObject("svtank",ENEMY_TEAM,M.ccarecycle)
            --				svpatrol3_3 = BuildObject("svtank", 2, ccarecycle);
            Patrol(M.svpatrol3_1,"patrol_path1")
            Patrol(M.svpatrol3_2,"patrol_path1")
            --				Patrol(svpatrol3_3, "patrol_path1");
        --			if ((retreat_success) && (!IsAlive(svpatrol4_1)) && 
        --				(!IsAlive(svpatrol4_2)) && (IsAlive(ccarecycle)))	
        --			{																				
        --				svpatrol4_1 = BuildObject("svtank", 2, ccarecycle);								
        --				svpatrol4_2 = BuildObject("svtank", 2, ccarecycle);								
        --				Patrol(svpatrol4_1, "patrol_path2");											
        --				Patrol(svpatrol4_2, "patrol_path2");											
        --			}
        end
    -- end of retreat code /////////////////////////////////////////
    -- building more patrol ships if patrol ships are lost /////////////////////////////////////
    end
    if not M.first_objective then
        if (not IsAlive(M.svpatrol1_1)) and (not IsAlive(M.svpatrol1_2)) and (IsAlive(M.ccarecycle)) and (not M.detected) then
            M.svpatrol1_1=BuildObject("svfigh",ENEMY_TEAM,M.ccarecycle)
            M.svpatrol1_2=BuildObject("svfigh",ENEMY_TEAM,M.ccarecycle)
            Patrol(M.svpatrol1_1,"patrol_path1")
            Patrol(M.svpatrol1_2,"patrol_path1")
            M.p1_retreat=false
            M.getum=false
            M.patrola1=false
            M.patrola2=false
        --[==[/*	if ((!IsAlive(svpatrol2_1)) && (!IsAlive(svpatrol2_2)) && (IsAlive(ccarecycle)) && (!detected))	
	{																					
		svpatrol2_1 = BuildObject("svfigh", 2, ccarecycle);								
		svpatrol2_2 = BuildObject("svfigh", 2, ccarecycle);						
		Patrol(svpatrol2_1, "patrol_path1");										
		Patrol(svpatrol2_2, "patrol_path1");
		p2_retreat = false;
		getum = false;
		patrolb1 = false;
		patrolb2 = false;
	}																					
*/]==]
        end
        if (not IsAlive(M.svpatrol3_1)) and (not IsAlive(M.svpatrol3_2)) and (IsAlive(M.ccarecycle)) and (not M.detected) then
            M.svpatrol3_1=BuildObject("svfigh",ENEMY_TEAM,M.ccarecycle)
            M.svpatrol3_2=BuildObject("svfigh",ENEMY_TEAM,M.ccarecycle)
            Patrol(M.svpatrol3_1,"patrol_path1")
            Patrol(M.svpatrol3_2,"patrol_path1")
            M.p3_retreat=false
            M.getum=false
            M.patrolc1=false
            M.patrolc2=false
        end
        if (not IsAlive(M.svpatrol4_1)) and (not IsAlive(M.svpatrol4_2)) and (IsAlive(M.ccarecycle)) then
            M.svpatrol4_1=BuildObject("svfigh",ENEMY_TEAM,M.ccarecycle)
            M.svpatrol4_2=BuildObject("svfigh",ENEMY_TEAM,M.ccarecycle)
            Patrol(M.svpatrol4_1,"patrol_path2")
            Patrol(M.svpatrol4_2,"patrol_path2")
        end
    -- end of scout building code ////////////////////////////////////////////////////////////////
    -- this is what happens when the player reaches the jump overlook - the rookie tells him about the test range
    --[==[/*
	if ((recon_message2_time < Get_Time()) && (!recon_message2))
	{
		recon_message2_time = Get_Time() + 20.0f;
		
		if ((!test_found) && (!recon_message2))
		{
			AudioMessage("misn0703.wav"); // rookie "I found a soviet test range
			becon_build_time = Get_Time() + 15.0f;
			check_range = Get_Time() + 20.0f;
			recon_message2 = true;
		}
	}
				
	if ((recon_message2) && (becon_build_time < Get_Time()) && (!becon_build))//rookie lays path through mines
	{
		nav4 = BuildObject ("apcamr", 1, "cam_spawn6");
		rookie_rendezvous_time = Get_Time() + 120.0f;
		becon_build = true;
	}

	if ((becon_build) && (nav4!=NULL))
	{
		GameObjectHandle::GetObj(nav4)->SetName("Testing Range");
	}

// this is how the rookie tells the player he's under attack

	if ((becon_build) && (rookie_rendezvous_time < Get_Time()) && (!rookie_lost))
	{
		rookie_rendezvous_time = Get_Time()	+ 21.0f;	

		if ((GetDistance (user, mine_geyz) > 400.0f) && (!rookie_lost))
		{
			AudioMessage("misn0704.wav"); // I'm under attack - I'll drop the a camera - goto to activate mine path
			nav5 = BuildObject ("apcamr", 1, "cam_spawn1");
			reach_mine_time = Get_Time() + 10.0f;
			rookie_lost = true;
		}
	}

	if ((rookie_lost) && (nav5!=NULL))
	{
		GameObjectHandle::GetObj(nav5)->SetName("Mine Field");
	}

	if ((rookie_lost) && (reach_mine_time < Get_Time()) && (!mine_pathed))
	{
		reach_mine_time = Get_Time() + 10.0f;
			
		if ((GetDistance(user, nav5) < 70.0f) && (!mine_pathed))
		{
			becon1 = BuildObject ("apcamr", 1, "cam_spawn2");
			becon2 = BuildObject ("apcamr", 1, "cam_spawn3");
			becon3 = BuildObject ("apcamr", 1, "cam_spawn4");
			becon4 = BuildObject ("apcamr", 1, "cam_spawn5");
			mine_pathed = true;
		}
	}

		if ((mine_pathed) && (becon1!=NULL))
		{
			GameObjectHandle::GetObj(becon1)->SetName("Mine Path 1");
		}
		if ((mine_pathed) && (becon2!=NULL))
		{
			GameObjectHandle::GetObj(becon2)->SetName("Mine Path 2");
		}
		if ((mine_pathed) && (becon3!=NULL))
		{
			GameObjectHandle::GetObj(becon3)->SetName("Mine Path 3");
		}
		if ((mine_pathed) && (becon4!=NULL))
		{
			GameObjectHandle::GetObj(becon4)->SetName("Mine Path 4");
		}

*/]==]
    -- end of rookie message about soviet test range /////////
    -- when the radar array is destroyed /////////////////////
    end
    if (not IsAlive(M.ccacomtower)) and (not M.first_objective) then
        M.audmsg=subtit.Play("misn0714.wav")
        M.radar_camera_time=GetTime()+10.0
        --		next_shot_time = Get_Time() + 20.0f;
        M.next_mission_time=GetTime()+7.5
        --		CameraReady();
        --		shot1 = true;
        M.first_objective=true
-- CR restored VO >>
        M.utah_nag_time = GetTime() + UTAH_NAG_DELAY_S
        M.test_range_after = GetTime() + TEST_RANGE_HOLD_S
-- CR restored VO <<
    --[==[/*	if (shot1)
	{
		CameraPath("radar_path", 4000, 1000, radar_geyser);
	}

	if ((shot1) && (radar_camera_time < Get_Time()))
	{
//		StopAudioMessage(audmsg);
//		audmsg = AudioMessage ("misn0714.wav");	
		shot1 = false;
		shot2 = true;
	}

	if (shot2)
	{
		CameraPath("movie_cam_spawn", 160, 0, show_geyser);
	}

	if ((!radar_camera_off) && (shot2) && (next_shot_time < Get_Time()))
	{
//		StopAudioMessage(audmsg);
		CameraFinish();
		shot2 = false;
		radar_camera_off = true;
	}

	if (((shot1) || (shot2)) && (!radar_camera_off))
	{
		if (CameraCancelled())
		{
			shot1 = false;
			shot2 = false;
//			StopAudioMessage(audmsg);
			CameraFinish();
			radar_camera_off = true;
		}
	}
*/]==]
    end
    if (M.first_objective) and (not M.next_mission) and (M.next_mission_time<GetTime()) then
        M.nsdfrecycle=BuildObject("avrec7",1,"recycle_spawn")
        M.nsdfmuf=BuildObject("avmu7",1,"muf_spawn")
        Goto(M.nsdfrecycle,"recycle_path",0)
        Goto(M.nsdfmuf,"muf_path",0)
        M.nav6=BuildObject("apcamr",1,"recycle_cam_spawn")
        M.nav7=BuildObject("apcamr",1,"recy_cam_spawn")
        if M.nav6~=nil then
            SetObjectiveName(M.nav6,"Utah Rendezvous")
        end
        if M.nav7~=nil then
            SetObjectiveName(M.nav7,"CCA BASE")
        end
        AddScrap(1,30)
        SetPilot(1,20)
        AddScrap(ENEMY_TEAM,60)
        SetPilot(ENEMY_TEAM,40)
        SetAIP("misn07.aip",ENEMY_TEAM)
        --		SetObjectiveOn(recycler);
        --		SetObjectiveName(recycler, "Utah");
        M.ccabaseguntower1=BuildObject("sbtowe",ENEMY_TEAM,"base_tower1_spawn")
        --		ccabaseguntower2 = BuildObject("sbtowe", 2, "base_tower2_spawn");
        ClearObjectives()
        AddObjective("misn0701.otf","green")
        AddObjective("misn0703.otf","white")
        AddObjective("misn0702.otf","white")
        M.next_mission=true
    end
    if (M.next_mission) and (not IsAlive(M.ccarecycle)) then
        M.second_objective=true
    end
    if (M.next_mission) and (not M.utah_found) then
        if IsAlive(M.nsdfrecycle) then
            local deployed = IsDeployed(M.nsdfrecycle)
            if deployed then
                ClearObjectives()
                AddObjective("misn0703.otf","green")
                AddObjective("misn0702.otf","white")
                M.utah_found=true
-- CR rendezvous convoy >>
                -- Respawn rally: the Utah once deployed (every peer sets its own service).
                Present("Rally", M.nsdfrecycle)
                CRCoop.SetMissionPhase(1)
-- CR rendezvous convoy <<
            end
        end
    -- here is an attempt at the mine code ////////////
    --[==[/*
	for (count = mine_check; count < mine_check + 10; count = count + 1)
	{
		if (GetDistance(user, mine[count]) < 400.0f)
		{
			if ((!m_on[count]) && (!m_dead[count]))
			{
				m[count] = BuildObject ("proxmine", 2, mine[count]);
				m_on[count] = true;
			}
			if ((m_on[count]) && (!IsAlive(m[count])))
			{
				m_dead[count] = true;
			}
		}
		else
		{
			if ((m_on[count]) && (!m_dead[count]))
			{
				RemoveObject(m[count]);
				m_on[count] = false;
			}
		}
	}
*/]==]
    -- this is the code that operates the MAG cannon and camera when the player encounters it
    --[==[/*
	if ((recon_message2) && (GetDistance(user, test_tank) < 65.0f) 
		&& (!camera_ready))
	{															
		CameraReady();
		GameObjectHandle:: GetObj(test_turret)->AddHealth(-950.0f); 
		camera_ready = true;									
	}															
																
	if ((camera_ready) && (!camera1_on))
	{															
		CameraObject(test_tank, 2000, 800, 500, user);
		AudioMessage("misn0711.wav");
		start_sound = Get_Time() + 8.0f;
		change_angle = Get_Time() + 6.0f;
		camera1_on = true;
	}

	if ((camera1_on) && (change_angle < Get_Time()) && (!camera3_on))
	{
		CameraPath("camera_path1", 250,  250, test_tank);
		camera2_on = true;
	}

	if ((camera2_on) && (!camera2_oned))
	{
		change_angle1 = Get_Time() + 8.0f;
		camera2_oned = true;
	}

	if ((change_angle1 < Get_Time()) && (!camera4_on))
	{
		CameraPath("camera_path2", 310, 500, test_turret);
		camera3_on = true;
	}

	if ((camera3_on) && (!camera3_oned))
	{
		change_angle2 = Get_Time() + 6.0f;
		switch_tank = Get_Time() + 5.0f;
		camera3_oned = true;
	}

	if ((switch_tank < Get_Time()) && (!tank_switch))
	{
		RemoveObject(test_tank);
		test_tank = BuildObject("svtnk7", 2, "test_tank_spawn");
		Attack(test_tank, test_turret);
		tank_switch = true;
	}
	
//	if ((change_angle2 < Get_Time()) && (!camera4_on))
//	{
//		CameraObject(test_tank, -300, 400,-750, test_turret);
//		change_angle3 = Get_Time() + 10.0f;
//		camera4_on = true;
//	}
	
	if ((change_angle2 < Get_Time()) && (!camera4_on))
	{
		CameraObject(test_turret, 1000, 300, 4700, test_turret);
		change_angle3 = Get_Time() + 10.0f;
		camera4_on = true;
	}

	if ((camera4_on) && (change_angle3 < Get_Time()) && (!camera_off))
	{
		CameraFinish();											
		camera_off = true;
	}
*/]==]
    -- win/loose conditions ///////////////////
    end
-- CR restored VO >>
    if RESTORED_VO then
        RestoredTestRange()
        RestoredMineField()
        RestoredMagCannon()
        RestoredUtahReminder()
        RestoredPrototypeTanks()
    end
-- CR restored VO <<
    if (M.next_mission) and (not IsAlive(M.nsdfrecycle)) and (not M.game_over) then
        subtit.Play("misn0712.wav")
        if not M.utah_found then
            ClearObjectives()
            AddObjective("misn0701.otf","green")
            AddObjective("misn0703.otf","red")
            AddObjective("misn0702.otf","white")
        end
        FailMission(GetTime()+15.0,"misn07f1.des")
        M.game_over=true
    end
    if (M.next_mission) and (not IsAlive(M.ccarecycle)) then
        M.second_objective=true
    end
    if (M.first_objective) and (M.second_objective) and (not M.game_over) then
        subtit.Play("misn0713.wav")
        SucceedMission(GetTime()+15.0,"misn07w1.des")
        M.game_over=true
    --////////////////////////////////////////////////////////
    -- END OF SCRIPT
    end
end

function Save()
-- CR Venus weather >>
    if venusStarted and ((not CRCoop.IsNetworkGame()) or CRCoop.IsAuthority()) then
        M.weatherState = CRVenusWeather.Save()
    end
-- CR Venus weather <<
    return M
end

function Load(state)
    M = state
end
