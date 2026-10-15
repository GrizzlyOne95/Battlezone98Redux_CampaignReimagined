-- Faithful stock misn12 port for Battlezone 98 Redux / Lua 5.1, with the shared offline +
-- 2-4 player co-op layer of the misn06-11 ports (Docs/MISN12_COOP.md).
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misn12Mission.cpp.
-- Source blob: 547a9e0849cd16070060e31f26cf6aa8c4d14b61.
-- Original disabled C++ remains in comments at its corresponding locations.
-- Complete native source/serialization: References/Misn12Source/.
-- Everything the campaign adds lives between "-- CR ... >>" / "-- CR ... <<" marker lines
-- (Tools/Test-Misn12SourceParity.py strips them); each co-op substitution outside the markers
-- is an explicit delta in that test. Offline play reproduces the DLL; only the leader runs the
-- mission body, once per human for everything that is a human's own progress. Requires the stock
-- misn12 map labels, paths, OTF/audio. No AIP: the CCA is script-driven.
local M

local function NewState()
    local state = {}
    state.start_done = false
    state.check_point1_done = false
    state.check_point2_done = false
    state.check_point3_done = false
    state.check_point4_done = false
    state.check_point5_done = false
    state.check1 = false
    state.check2 = false
    state.check3 = false
    state.check4 = false
    state.objective1 = false
    state.out_of_order1 = false
    state.out_of_order2 = false
    state.out_of_order3 = false
    state.out_of_order4 = false
    state.out_of_order5 = false
    state.interface_connect = false
    state.link_broken = false
    state.interface_complete = false
    state.warning_message = false
    state.cca_message1 = false
    state.cca_message2 = false
    state.cca_message3 = false
    state.cca_message4 = false
    state.identify_message = false
    state.cca_warning_message = false
    state.better_message = false
    state.real_bad = false
    state.enter_base = false
    state.did_it_right = false
    state.straight_to_5 = false
    state.discovered = false
    state.noise = false
    state.camera_on = false
    state.camera_off = false
    state.camera1 = false
    state.camera2 = false
    state.camera3 = false
    state.camera4 = false
    state.camera5 = false
    state.key_captured = false
    state.over = false
    state.checked_in = false
    state.going_again = false
    state.key_gone = false
    state.game_blown = false
    state.final_warned = false
    state.last_warned = false
    state.follow_spawn = false
    state.good1 = false
    state.good2 = false
    state.good3 = false
    state.good1_off = false
    state.good2_off = false
    state.good3_off = false
    state.dead_meat = false
    state.patrol1_create = false
    state.patrol2_create = false
    state.patrol3_create = false
    state.patrol4_create = false
    state.patrol1_moved1 = false
    state.patrol2_moved1 = false
    state.patrol3_moved1 = false
    state.patrol4_moved1 = false
    state.patrol1_moved2 = false
    state.patrol2_moved2 = false
    state.patrol3_moved2 = false
    state.patrol4_moved2 = false
    state.patrol1_1_gone = false
    state.patrol1_2_gone = false
    state.patrol2_1_gone = false
    state.patrol2_2_gone = false
    state.patrol3_1_gone = false
    state.patrol3_2_gone = false
    state.patrol4_1_gone = false
    state.patrol4_2_gone = false
    state.p1_1center = false
    state.p2_1center = false
    state.p2_2center = false
    state.p3_1center = false
    state.p3_2center = false
    state.p4_1center = false
    state.p4_2center = false
    state.win = false
    state.game_over = false
    state.camera_swap1 = false
    state.camera_swap2 = false
    state.camera_swap_back = false
    state.out_of_ship = false
    state.camera_noise = false
    state.blown_otf = false
    state.grump = false
    state.countdown_time = 99999.0
    state.interface_time = 99999.0
    state.warning_repeat_time = 99999.0
    state.next_message_time = 99999.0
    state.next_noise_time = 99999.0
    state.camera_time = 99999.0
    state.camera_on_time = 99999.0
    state.win_check_time = 99999.0
    state.start_patrol = 99999.0
    state.key_check = 99999.0
    state.wait_time = 99999.0
    state.key_remove = 99999.0
    state.death_spawn = 99999.0
    state.final_warning = 99999.0
    state.last_warning = 99999.0
    state.remove_patrol1_2 = 99999.0
    state.patrol1_1_time = 99999.0
    state.patrol1_2_time = 99999.0
    state.patrol2_1_time = 99999.0
    state.patrol2_2_time = 99999.0
    state.patrol3_1_time = 99999.0
    state.patrol3_2_time = 99999.0
    state.patrol4_1_time = 99999.0
    state.patrol4_2_time = 99999.0
    state.swap_check = 99999.0
    state.next_second = 99999.0
    state.grump_time = 99999.0
    state.user = nil
    state.user_tank = nil
    state.center = nil
    state.center_cam = nil
    state.start_cam = nil
    state.check2_cam = nil
    state.check3_cam = nil
    state.check4_cam = nil
    state.goal_cam = nil
    state.nav1 = nil
    state.key_ship = nil
    state.spawn_geyser = nil
    state.choke_geyser = nil
    state.check2_geyser = nil
    state.center_geyser = nil
    state.checkpoint1 = nil
    state.checkpoint2 = nil
    state.checkpoint3 = nil
    state.checkpoint4 = nil
    state.ccacom_tower = nil
    state.ccasilo1 = nil
    state.ccasilo2 = nil
    state.ccasilo3 = nil
    state.ccasilo4 = nil
    state.guard1 = nil
    state.guard2 = nil
    state.guard3 = nil
    state.guard4 = nil
    state.spawn_point1 = nil
    state.spawn_point2 = nil
    state.guard_fighter = nil
    state.parked_fighter = nil
    state.parked_tank1 = nil
    state.parked_tank2 = nil
    state.guard_turret = nil
    state.pturret1 = nil
    state.pturret2 = nil
    state.pturret3 = nil
    state.pturret4 = nil
    state.pturret5 = nil
    state.pturret6 = nil
    state.patrol1_1 = nil
    state.patrol1_2 = nil
    state.patrol2_1 = nil
    state.patrol2_2 = nil
    state.patrol3_1 = nil
    state.patrol3_2 = nil
    state.patrol4_1 = nil
    state.patrol4_2 = nil
    state.guard_tank1 = nil
    state.guard_tank2 = nil
    state.death_squad1 = nil
    state.death_squad2 = nil
    state.death_squad3 = nil
    state.death_squad4 = nil
    state.follower = nil
    state.ccamuf = nil
    state.audmsg = 0
    return state
end
M = NewState()
-- CR co-op layer >>
-- EXU Initialization (the co-op layer needs the bundled multiplayer hooks).
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})
local exu = require("exu")
-- Native MultST Init precedes Start. The infiltration has no base: no human team keeps a starting
-- recycler.
if type(IsNetGame) == "function" and IsNetGame() then
    assert(exu.DisableStartingRecycler and exu.GetMyNetID,
        "misn12 co-op requires the bundled EXU multiplayer hooks")
    exu.DisableStartingRecycler()
end
local subtit = require("ScriptSubtitles")
local CRCoop = require("CRCoop")
-- The DLL's CCA is team 2 (a guest slot in co-op): every CCA object and spawn is team 5. The DLL's
-- camera pods sit on team 3 (a guest slot too) while hidden: they hide on the support team 7, which no
-- human is allied with, and are revealed to team 1 (allied with every human) exactly as the DLL does.
local LEADER_TEAM, ENEMY_TEAM, HIDDEN_TEAM = 1, 5, 7
-- CR co-op layer <<
-- CR Europa weather >>
local CREuropaWeather = require("CREuropaWeather")
local EuropaSites = require("CREuropaSites12")
local Environment = require("Environment")
local EUROPA_OPS = { EuropaState = true, EuropaPlume = true, EuropaQuake = true, EuropaSurge = true }
-- CR Europa weather <<
-- CR co-op layer >>
-- Co-op presentation uses the established misn03/misn05/misn06 E/A and C transport.
-- Only the campaign leader runs the mission body below; HUD/audio/removal/timer/camera/
-- end calls are explicitly delivered to every peer. Objective-panel calls made while a human's
-- own progress is being processed are delivered to that human only (the E stream carries a
-- target team; 0 = everyone).
-- E/A are an ordered, acknowledged event stream (eight small packets in flight,
-- retried every 0.2s). C is a replaceable camera snapshot carrying a kind: "P"
-- (CameraPath), "O" (CameraObject) or "" (no camera). I relays a guest's
-- native IsInfo selection state to the leader. No tables go on wire.
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
    AddAmmo = AddAmmo, StopAudioMessage = StopAudioMessage,
    Play = subtit.Play, Queue = subtit.Queue, Stop = subtit.Stop,
}
local nativeIsInfo = IsInfo
local events, acknowledgements = {}, {}
local receivedEvent = 0
local pendingSeq, pendingSince
-- Declared before ResetPresentation, which resets them.
local cameraWaitSince, cameraGaveUp, cameraLast
local labelSerial, announced = 0, {}
-- Targets a guest already gave up on (logged once): later events for them skip at once.
local gaveUp = {}
local nextEventSend, nextCameraSend = 0, 0
local cameraFrame, cameraGeneration, cameraSerial = nil, 0, 0
local remoteCameraSerial, localCameraGeneration = 0, 0
local cameraSkipped, localCameraActive = false, false
local remoteCamera
-- IsInfo is local UI state (the selected object's info panel). Guests relay the two nav-console
-- prefixes this mission reads; the leader honours a report from that player for 1 s.
local INFO_PREFIXES = { "sbhqt1", "sbhqt2" }
local isInfoPrefix = {}
for _, prefix in ipairs(INFO_PREFIXES) do isInfoPrefix[prefix] = true end
local remoteInfo, nextInfoSend = {}, 0
-- The human whose progress the mission body is processing (nil in shared code). Objective-panel
-- calls follow it; everything else is shared.
local focusTeam, focusId, focusLocal = 0, nil, true

local function ResetPresentation()
    events, acknowledgements, receivedEvent = {}, {}, 0
    pendingSeq, pendingSince = nil, nil
    nextEventSend, nextCameraSend = 0, 0
    cameraFrame, cameraGeneration, cameraSerial = nil, 0, 0
    remoteCamera, remoteCameraSerial, localCameraGeneration = nil, 0, 0
    cameraWaitSince, cameraGaveUp, cameraLast = nil, false, nil
    announced, gaveUp = {}, {}
    cameraSkipped, localCameraActive = false, false
    remoteInfo, nextInfoSend = {}, 0
    focusTeam, focusId, focusLocal = 0, nil, true
end

local function FromLeader(from)
    local player = CRCoop.GetPlayers()[from]
    return player and player.team == LEADER_TEAM
end

-- Per-human ops: the panel the player reads and their own markers.
local TARGETED_OPS = { ClearObjectives = true, AddObjective = true, UpdateObjective = true,
    SetObjectiveOn = true, SetObjectiveOff = true, SetUserTarget = true, TopUpAmmo = true }

local function ApplyPresentation(op, ...)
-- CR Europa weather >>
    if EUROPA_OPS[op] then
        -- Weather events carry no handles: never labelled, never waited on.
        return CREuropaWeather.ApplyNetEvent(op, ...)
    end
-- CR Europa weather <<
    if op == "Label" then
        local handle, label = ...
        if type(SetLabel) == "function" and IsValid(handle) and type(label) == "string" then
            pcall(SetLabel, handle, label)
        end
    elseif op == "TopUpAmmo" then
        -- The owning peer tops its own craft up (the key ship's cannon is stock-empty for a hijacker).
        local amount = ...
        local own = GetPlayerHandle()
        if IsValid(own) then native.AddAmmo(own, amount) end
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

-- Ops whose first argument is a game object. Objects travel by identity, never by a bare
-- handle the engine may not carry: "@handle@label" (a guest resolves the label first, then
-- the replicated handle), or "!" when the leader reports the object gone. Label is the
-- event that makes a leader-side SetLabel on a spawned object true on every guest.
local HANDLE_OPS = { SetObjectiveOn = true, SetObjectiveOff = true, SetObjectiveName = true,
    SetUserTarget = true, RemoveObject = true, Label = true }
local WAIT_OPS = { SetObjectiveOn = true, SetObjectiveName = true, SetUserTarget = true, Label = true }
local GONE = "!"
-- Guests WAIT for the real object. This is only a never-hang guard: when it fires the
-- guest logs "[coop] unresolved ..." and counts it in M.coopUnresolved (the harness probe
-- reads that and expects zero).
local RESOLVE_TIMEOUT = 15
local RESULT_HOLD_LEAD = 4.5

local function HandleText(handle)
    return type(handle) == "number" and string.format("%d", handle) or tostring(handle)
end

local function KnownLabel(handle)
    local ok, label = pcall(GetLabel, handle)
    if ok and type(label) == "string" and label ~= "" and #label <= 126 then
        local found, resolved = pcall(GetHandle, label)
        if found and resolved == handle then return label end
    end
end

-- Leader: tell every guest "this replicated handle carries this label" once.
local function AnnounceLabel(handle, label)
    if announced[handle] == label then return end
    announced[handle] = label
    events[#events + 1] = { op = "Label", args = { "@" .. HandleText(handle) .. "@" .. label, label },
        n = 2, ttl = RESOLVE_TIMEOUT, handle = handle, target = 0 }
end

-- Leader: the label for a target, assigning a deterministic unique one to an unlabelled
-- spawned object.
local function EnsureLabel(handle)
    local label = KnownLabel(handle)
    if not label and type(SetLabel) == "function" then
        labelSerial = labelSerial + 1
        pcall(SetLabel, handle, "crco_" .. labelSerial)
        label = KnownLabel(handle)
    end
    if label then AnnounceLabel(handle, label) end
    return label
end

local function WireHandle(handle)
    if handle == nil then return nil end
    if not IsValid(handle) then return GONE end
    local label = EnsureLabel(handle)
    if label then return "@" .. HandleText(handle) .. "@" .. label end
    return handle
end

-- Retransmissions re-check the leader's view: a marker/label target that has since died
-- is reported gone so a guest that never got it does not wait for it.
local function EventArgs(event)
    if event.handle ~= nil and WAIT_OPS[event.op] and not IsValid(event.handle) then
        local args = { unpackArgs(event.args, 1, event.n) }
        args[1] = GONE
        return args
    end
    return event.args
end

local function Present(op, ...)
    local target = TARGETED_OPS[op] and focusTeam or 0
    if CRCoop.IsNetworkGame() then
        if not CRCoop.IsAuthority() then return end
        local wire, handle = { ... }, nil
        if HANDLE_OPS[op] and wire[1] ~= nil then handle = wire[1]; wire[1] = WireHandle(handle) end
        events[#events + 1] = { op = op, args = wire, n = select("#", ...), ttl = RESOLVE_TIMEOUT,
            handle = handle, target = target }
        -- The leader applies only what concerns its own player.
        if target ~= 0 and target ~= CRCoop.GetLocalTeam() then return end
    end
    return ApplyPresentation(op, ...)
end

local function WireCameraFrame(frame)
    if frame[1] == "O" then
        return { "O", WireHandle(frame[2]), frame[3], frame[4], frame[5], WireHandle(frame[6]) }
    end
    return { frame[1], frame[2], frame[3], frame[4], WireHandle(frame[5]) }
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
    cameraFrame = { "P", path, height, speed, target }
    if CRCoop.IsNetworkGame() and native.CameraCancelled() then
        cameraSkipped = true
        if localCameraActive then native.CameraFinish() end
        localCameraActive = false
    end
    if not cameraSkipped then return native.CameraPath(path, height, speed, target) end
end
local function CameraObject(subject, x, y, z, target)
    cameraFrame = { "O", subject, x, y, z, target }
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
    -- timing, so the cutscenes keep the DLL's clock for everyone else.
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

-- Camera frames carry their subject/target as "@handle@label" (or "!" when the leader
-- reports it gone). A guest holds the film's start until the REAL objects resolve. Only a
-- gone flag, or the never-hang guard (loudly logged and counted), lets it play with
-- whatever remains valid.

-- handle (or nil), gone
local function ResolveCameraHandle(sent)
    if sent == nil or sent == GONE then return nil, true end
    if type(sent) ~= "string" or sent:sub(1, 1) ~= "@" then return sent, false end
    local sentHandle, sentLabel = sent:match("^@([^@]*)@(.*)$")
    local resolved = sentLabel and GetHandle(sentLabel)
    if not IsValid(resolved) and sentHandle and sentHandle ~= "" then
        local candidate = tonumber(sentHandle) or sentHandle
        if IsValid(candidate) then resolved = candidate end
    end
    return resolved, (not IsValid(resolved)) and sentLabel ~= nil and gaveUp[sentLabel] == true
end

local function NativeCameraPath(path, height, speed, target)
    if target == nil then return pcall(native.CameraPath, path, height, speed, nil) end
    return native.CameraPath(path, height, speed, target)
end

-- ready, subject, target. sentSubject == nil means the kind carries none (path cameras).
local function ResolveCameraHandles(sentSubject, sentTarget)
    local needSubject = sentSubject ~= nil
    local subject, subjectGone = ResolveCameraHandle(sentSubject)
    local target, targetGone = ResolveCameraHandle(sentTarget)
    if (not needSubject or IsValid(subject)) and IsValid(target) then
        cameraWaitSince, cameraLast = nil, { subject, target }
        return true, subject, target
    end
    local settled = (not needSubject or IsValid(subject) or subjectGone) and (IsValid(target) or targetGone)
    if not settled then
        if localCameraActive and cameraLast then return true, cameraLast[1], cameraLast[2] end
        if localCameraActive or not cameraGaveUp then
            local now = GetTime()
            if not cameraWaitSince or now < cameraWaitSince then cameraWaitSince = now end
            if now - cameraWaitSince < RESOLVE_TIMEOUT then return false end
            if not cameraGaveUp then
                cameraGaveUp = true
                for _, sent in ipairs({ sentSubject or false, sentTarget or false }) do
                    local label = type(sent) == "string" and sent:match("^@[^@]*@(.*)$")
                    if label then gaveUp[label] = true end
                end
                M.coopUnresolved = (M.coopUnresolved or 0) + 1
                print("[coop] unresolved camera " .. tostring(sentSubject) .. " " .. tostring(sentTarget))
            end
        end
    end
    -- Settled (gone flag) or guard fired: play with whatever remains valid.
    if not IsValid(target) then target = IsValid(subject) and subject or nil end
    if needSubject and not IsValid(subject) then subject = target end
    if needSubject and subject == nil then return false end
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
        cameraWaitSince, cameraGaveUp, cameraLast = nil, false, nil
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
        NativeCameraPath(cam.path, cam.height, cam.speed, cam.target)
    end
end

-- Guests report which nav-console prefix their own UI currently shows.
local function UpdateInfoRelay()
    if not CRCoop.IsNetworkGame() or CRCoop.IsAuthority() then return end
    local now = GetTime()
    if now < nextInfoSend then return end
    local leaderId = 0
    for id, player in pairs(CRCoop.GetPlayers()) do
        if player.team == LEADER_TEAM then leaderId = id; break end
    end
    for _, prefix in ipairs(INFO_PREFIXES) do
        if nativeIsInfo(prefix) then
            Send(leaderId, "I", prefix)
            nextInfoSend = now + 0.25
        end
    end
end

local function UpdatePresentationTransport()
    if not CRCoop.IsNetworkGame() then return end
    -- Read by the harness probe (numbers in M appear in its snapshots): must stay 0.
    if M.coopUnresolved == nil then M.coopUnresolved = 0 end
    if not CRCoop.IsAuthority() then
        UpdateRemoteCamera()
        UpdateInfoRelay()
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
                    Send(id, "E", seq, event.op, event.ttl, event.target or 0, unpackArgs(EventArgs(event), 1, event.n))
                end
            end
        end
    end
    if now >= nextEventSend then nextEventSend = now + 0.2 end
    -- A result is held until 4.5 s before its time, so the DLL's last scheduled beats (the death squad
    -- five seconds after cover is blown) still run while the countdown is pending.
    if M.coopPendingResult and allDelivered and now >= (M.coopPendingResult[2] or 0) - RESULT_HOLD_LEAD then
        local result = M.coopPendingResult
        M.coopPendingResult = nil
        Present(result[1], math.max(now + 5, result[2] or 0), result[3])
    end
    if now >= nextCameraSend then
        nextCameraSend = now + 0.2
        cameraSerial = cameraSerial + 1
        if cameraFrame then
            Send(0, "C", cameraSerial, cameraGeneration, unpackArgs(WireCameraFrame(cameraFrame)))
        else
            Send(0, "C", cameraSerial, cameraGeneration, "")
        end
    end
end

local function ReceivePresentation(from, kind, ...)
    if not CRCoop.IsNetworkGame() then return false end
    if kind == "I" then
        -- Leader only: a human's report that their UI shows one of our prefixes.
        local prefix = ...
        local player = CRCoop.GetPlayers()[from]
        if CRCoop.IsAuthority() and player and CRCoop.IsHumanTeam(player.team) and
            type(prefix) == "string" and isInfoPrefix[prefix] then
            remoteInfo[from] = remoteInfo[from] or {}
            remoteInfo[from][prefix] = GetTime()
        end
        return true
    end
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
    local seq, op, ttl, target = ...
    if type(seq) ~= "number" or type(op) ~= "string" or type(ttl) ~= "number" or type(target) ~= "number" then
        return true
    end
    if seq == receivedEvent + 1 and (native[op] or EUROPA_OPS[op] or op == "Label" or op == "TopUpAmmo") then
        local args = { select(5, ...) }
        local count = select("#", ...) - 4
        local apply, unresolved = true, false
        if target ~= 0 and target ~= CRCoop.GetLocalTeam() then
            -- Another human's panel/markers: acknowledge, never wait for objects we do not show.
            apply = false
        elseif HANDLE_OPS[op] then
            local sent, described = args[1], args[1]
            if sent == GONE then
                -- The leader reports the object gone: skip this marker, never wait.
                apply = false
            elseif type(sent) == "string" and sent:sub(1, 1) == "@" then
                local sentHandle, sentLabel = sent:match("^@([^@]*)@(.*)$")
                local resolved = sentLabel and GetHandle(sentLabel)
                if not IsValid(resolved) and sentHandle and sentHandle ~= "" then
                    local candidate = tonumber(sentHandle) or sentHandle
                    if IsValid(candidate) then resolved = candidate end
                end
                args[1], described = resolved, sentLabel or sent
                if not IsValid(args[1]) then apply, unresolved = false, true end
            elseif not IsValid(sent) then
                unresolved = true
            end
            if unresolved and WAIT_OPS[op] and gaveUp[described] then
                apply = false
            elseif unresolved and WAIT_OPS[op] then
                -- The real object may replicate after the Lua packet: withhold the ACK so
                -- the retransmission retries. Only the never-hang guard ends the wait.
                local now = GetTime()
                if pendingSeq ~= seq or now < pendingSince then pendingSeq, pendingSince = seq, now end
                if now - pendingSince < math.min(ttl, 60) then return true end
                gaveUp[described] = true
                M.coopUnresolved = (M.coopUnresolved or 0) + 1
                print("[coop] unresolved " .. tostring(described) .. " (" .. op .. ")")
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

-- Native IsInfo reads the LOCAL player's panel. For the human being processed: the leader's own
-- panel, or the report that player's peer relayed within the last second.
local function IsInfo(prefix)
    if focusLocal then return nativeIsInfo(prefix) end
    local reported = remoteInfo[focusId] and remoteInfo[focusId][prefix]
    return reported ~= nil and GetTime() - reported <= 1.0
end

-- Presentation adapter ends.

-- The DLL's AudioMessage(file) is the shared radio line: the leader plays it and every peer hears
-- it with its subtitle (Play returns the native audio handle on the leader, nil offline-safe).
local function AudioMessage(file) return subtit.Play(file) end
-- StopAudioMessage on a shared line stops the subtitle/audio sequence on every peer.
local function StopAudioMessage(message)
    if message == nil then return end
    if CRCoop.IsNetworkGame() then subtit.Stop() else native.StopAudioMessage(message) end
end
-- CR co-op layer <<

-- The native helper checks object existence, rather than life or pilot status.
-- Preserve that exact test for the key ship with the stock IsValid API.
local function IsVehicleAlive(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

-- Preserve native invalid-handle distance behavior without selecting a nil
-- position overload. This only affects missing/removed objects, not thresholds.
local function Distance(from, to)
    if from == nil or from == 0 or not IsValid(from) then return math.huge end
    if to == nil or to == 0 then return math.huge end
    if type(to) ~= "string" and not IsValid(to) then return math.huge end
    return GetDistance(from, to)
end
-- CR co-op layer >>
-- Per-human mission state. The DLL keeps ONE player's progress in M; with several humans each
-- keeps their own copy of these fields. M always holds the values of the human named by M.hcur
-- (the leader, outside the per-human loops), so the DLL logic below reads and writes the same
-- field names it always did and a single player behaves exactly as the DLL. Everything not listed
-- here (cover state of the mission, patrols, cameras, uplink completion, the timer) is shared.
local HUMAN_KEYS = {
    "user_tank", "key_captured", "out_of_ship",
    "check_point2_done", "check_point3_done", "check_point4_done", "check_point5_done",
    "check2", "check3", "check4", "good1", "good2", "good3", "good1_off", "good2_off", "good3_off",
    "cca_warning_message", "identify_message", "better_message", "straight_to_5", "did_it_right",
    "final_warned", "last_warned", "real_bad", "follow_spawn", "follower", "dead_meat",
    "interface_connect", "warning_message", "noise",
    "final_warning", "last_warning", "next_message_time", "interface_time",
    "warning_repeat_time", "next_noise_time",
}
-- One key ship per human: the DLL's single ship cycle (arrive at checkpoint 1, wait, return, be
-- rebuilt) runs for each slot.
local SLOT_KEYS = { "key_ship", "checked_in", "going_again", "wait_time", "key_remove",
    "slot_captured", "slot_spawn_at" }
local KEY_STAGGER_S = 25.0   -- seconds between two key ships leaving the spawn geyser
local MAX_PLAYERS = 4

local function HumanDefaults()
    local fresh, defaults = NewState(), {}
    for _, key in ipairs(HUMAN_KEYS) do defaults[key] = fresh[key] end
    return defaults
end

local function SlotDefaults()
    local fresh, defaults = NewState(), {}
    for _, key in ipairs(SLOT_KEYS) do defaults[key] = fresh[key] end
    return defaults
end

local function PrimaryId()
    if not CRCoop.IsNetworkGame() then return 0 end
    for id, player in pairs(CRCoop.GetPlayers()) do
        if player.team == LEADER_TEAM then return id end
    end
    return 0
end

-- The humans that currently have a craft, leader first.
local function HumanList()
    local list = {}
    CRCoop.ForEachPlayerHandle(function(h, id, isLocal)
        local player = id ~= nil and CRCoop.GetPlayers()[id] or nil
        list[#list + 1] = { id = id or 0, handle = h, team = player and player.team or LEADER_TEAM,
            isLocal = isLocal ~= false }
    end)
    table.sort(list, function(a, b)
        if a.team ~= b.team then return a.team < b.team end
        return a.id < b.id
    end)
    return list
end

-- Human teams in the session (1 offline): the way misn07-11 size their reinforcements.
local function HumanCount()
    return CRCoop.ForEachHumanTeam(function() end)
end

local function SwitchHuman(id)
    local current = M.hcur
    if current == nil then current = PrimaryId(); M.hcur = current end
    if current == id then return end
    local saved = {}
    for _, key in ipairs(HUMAN_KEYS) do saved[key] = M[key] end
    M.hstore[current] = saved
    local loaded = M.hstore[id] or HumanDefaults()
    for _, key in ipairs(HUMAN_KEYS) do M[key] = loaded[key] end
    M.hcur = id
end

local function SwitchSlot(index)
    local current = M.scur or 1
    if current == index then return end
    local saved = {}
    for _, key in ipairs(SLOT_KEYS) do saved[key] = M[key] end
    M.sstore[current] = saved
    local loaded = M.sstore[index] or SlotDefaults()
    for _, key in ipairs(SLOT_KEYS) do M[key] = loaded[key] end
    M.scur = index
end

-- A respawned human arrives in a fresh NSDF craft: they must infiltrate again.
local function CheckRespawn(entry)
    local last = M.hcraft[entry.id]
    M.hcraft[entry.id] = entry.handle
    if last == nil or last == entry.handle or not M.key_captured then return end
    if IsAlive(last) then return end
    if type(IsPerson) == "function" and IsPerson(entry.handle) then return end
    if IsOdf(entry.handle, "svfi12") or IsOdf(entry.handle, "svfigh") or IsOdf(entry.handle, "svtank") then return end
    M.key_captured, M.out_of_ship, M.user_tank = false, false, entry.handle
end

local function EnterHuman(entry)
    SwitchHuman(entry.id)
    M.user = entry.handle
    focusId, focusLocal = entry.id, entry.isLocal
    focusTeam = M.multi and entry.team or 0
    CheckRespawn(entry)
    if M.user_tank == nil then M.user_tank = entry.handle end
end

local function LeaveHumans()
    SwitchHuman(PrimaryId())
    focusTeam, focusId, focusLocal = 0, nil, true
end

-- Runs fn(entry) with M holding that human's state; M holds the leader's again afterwards.
local function ForEachHuman(fn)
    for _, entry in ipairs(HumanList()) do
        EnterHuman(entry)
        fn(entry)
    end
    LeaveHumans()
end

local function ForEachSlot(fn)
    for index = 1, M.slots do
        SwitchSlot(index)
        fn(index)
    end
    SwitchSlot(1)
end

-- Broadcast fn's presentation to every human even while a human is being processed.
local function Broadcast(fn)
    local team = focusTeam
    focusTeam = 0
    fn()
    focusTeam = team
end

-- The human nearest `from` (handle, distance); nil when no human has a craft.
local function NearestPlayer(from)
    local best, bestDistance = nil, math.huge
    CRCoop.ForEachPlayerHandle(function(h)
        local distance = Distance(h, from)
        if best == nil or distance < bestDistance then best, bestDistance = h, distance end
    end)
    return best, bestDistance
end

-- Whom a CCA unit hunts: the nearest human (the DLL's lone player offline).
local function TargetFor(unit)
    return NearestPlayer(unit) or M.user
end

-- True when every human with a craft is farther than `distance` from `target`.
local function AllHumansBeyond(target, distance)
    local beyond = true
    CRCoop.ForEachPlayerHandle(function(h)
        if not (Distance(h, target) > distance) then beyond = false end
    end)
    return beyond
end

-- The DLL's win test, per human: every human must have been within the radius at a poll (a player
-- who has left the session is not waited for).
local function AllHumansArrived(target, radius)
    M.arrived = M.arrived or {}
    CRCoop.ForEachPlayerHandle(function(h, id)
        if Distance(h, target) < radius then M.arrived[id or 0] = true end
    end)
    local required = 0
    if CRCoop.IsNetworkGame() then
        for id, player in pairs(CRCoop.GetPlayers()) do
            if CRCoop.IsHumanTeam(player.team) then
                required = required + 1
                if not M.arrived[id] then return false end
            end
        end
    else
        required = 1
        if not M.arrived[0] then return false end
    end
    return required > 0
end

-- True while another cinematic owns the shared screen. Only matters with several humans; a lone
-- player sees every shot, as in the DLL.
local function CameraBusy()
    if not M.multi then return false end
    return (not M.camera4) or (M.camera_on and not M.camera_off) or GetTime() < (M.shot_until or 0)
end

-- A checkpoint acknowledgement shot (the human who passed): true when this one may play.
local function CheckpointShotReady()
    if CameraBusy() then return false end
    CameraReady()
    return true
end

-- Cover blown for everyone (several humans): every human is perceived hostile and the DLL's
-- game_blown failure path runs. `voice` is the line to play when nothing else announced it.
local function CoverBlown(voice)
    CRCoop.ForEachPlayerHandle(function(h) SetPerceivedTeam(h, 1) end)
    if not M.game_blown then
        if voice then AudioMessage(voice) end
        M.death_spawn = GetTime() + 5.0
        M.game_blown = true
    end
end

-- The key ship's 2000 rounds for whoever just captured one (the owning peer applies it).
local function TopUpAmmo(entry)
    if entry.isLocal then
        AddAmmo(entry.handle, 2000.0)
    else
        Present("TopUpAmmo", 2000.0)
    end
end

-- Scaling: each extra human (cap 4 players, so at most +3) adds a patrol fighter and a hunter.
local EXTRA_MAX = MAX_PLAYERS - 1
local function ExtraHumans()
    return math.min(EXTRA_MAX, math.max(0, HumanCount() - 1))
end
-- CR co-op layer <<
-- CR Razor One >>
-- Restored cut content (INFERRED; Docs/MISN12_COOP.md "Razor One"). The DLL never plays misn1224
-- ("This is Razor One. Thanks for rescuing me. I was captured on Venus. I know a fast way out of
-- here. Follow me.") and the map carries an unused, hand-sculpted one-way route on its east side:
-- a 20-35 m channel from the checkpoint-2 compound, a flat 66.4 m shelf, a launch lip at 80.9 m, a
-- 100 m jump over the main channel onto a 45.4 m ledge, then the floor 1.2 km from the drop zone
-- (Tools/Preview-Misn12Map.py, Docs/MISN12_ROUTE_PREVIEW.png). Ground AI cannot follow the jump.
-- Razor One is an emergency exit, not a quest giver. He appears only the FIRST time the hunters
-- (the ordered patrols, the guard tanks, the scaled extra hunters) actually catch up with a human:
-- a human craft is damaged by a CCA unit, or a hunter closes to within RAZOR_CATCH_M of a human.
-- A team that gets home clean never sees him. Then his scout is built at the compound
-- (check2_geyser), marked "Razor One" for everyone, misn1224 is played to every player as a radio
-- call, and he drives to the head of the east channel (route point 2) and waits there for the humans
-- (RAZOR_MEET_M, or RAZOR_WAIT_TIMEOUT_S), then leads the way out over the jump to the drop zone,
-- waiting for the group at the foot of the lip. Following him is optional; the win is unchanged.
-- Once Razor has cleared the jump, hunters whose humans have got away lose the scent and return to
-- patrol (RazorBreakOff). He is the players' guide, never a target: perceived as CCA, he cannot blow
-- cover (the stealth part of the mission is over by then), and he takes no part in the DLL's checks.
-- The jump is a scripted velocity (ground AI would refuse the gap) with a teleport fallback; he is
-- protected through the jump and heals.
-- Set RAZOR_ONE to false for the DLL's route only.
local RAZOR_ONE = true
local RAZOR_ODF = "avfigh"
local RAZOR_MEET_M, RAZOR_WAIT_M = 120.0, 150.0
local RAZOR_ARRIVE_M, RAZOR_LIP_M = 45.0, 30.0
local RAZOR_REORDER_S, RAZOR_WAIT_TIMEOUT_S, RAZOR_STUCK_S = 8.0, 45.0, 25.0
local RAZOR_JUMP_SPEED, RAZOR_JUMP_LIFT, RAZOR_JUMP_TIMEOUT_S, RAZOR_LAND_M = 32.0, 12.0, 9.0, 40.0
local RAZOR_HEAL_QUIET_S, RAZOR_HEAL_PER_S = 4.0, 0.02
-- Trigger: a hunter this close to any human (m) has caught up. Break-off: past the jump, a hunter
-- keeps attacking while any human is within RAZOR_KEEP_M, or in sight within RAZOR_LOSE_M; "in
-- sight" is a terrain line (GetTerrainHeightAndNormal sampled along hunter -> human; the BZ Lua API
-- has no line-of-sight native). A human within RAZOR_CORRIDOR_M of the landing-side route took it.
local RAZOR_CATCH_M, RAZOR_KEEP_M, RAZOR_LOSE_M, RAZOR_CORRIDOR_M = 200.0, 100.0, 300.0, 80.0
local RAZOR_POLL_S, RAZOR_SIGHT_STEPS, RAZOR_EYE_M = 1.0, 16, 3.0
local RAZOR_HUNTER_KEYS = { "patrol1_1", "patrol1_2", "patrol2_1", "patrol2_2", "patrol3_1", "patrol3_2",
    "patrol4_1", "patrol4_2" }
local RAZOR_GUARD_KEYS = { "guard_tank1", "guard_tank2" }
local RAZOR_PATROL_PATH = "path5"   -- the file's own loop for the fighters it hands to Patrol()
-- (x, z) metres, from the unsmoothed 1.5 heightmap. Entry 1 is the compound, entry 14 the foot of the
-- lip (he waits for the group), 15 the lip crest (launch), 16 the landing, 27 the drop zone.
local RAZOR_ROUTE = {
    { 2942, 100812 }, { 3005, 100842 }, { 3132, 100833 }, { 3142, 100825 }, { 3192, 100696 },
    { 3202, 100550 }, { 3242, 100327 }, { 3243, 100267 }, { 3302, 100142 }, { 3358, 99984 },
    { 3352, 99912 }, { 3328, 99877 }, { 3328, 99772 }, { 3338, 99746 }, { 3343, 99632 },
    { 3347, 99518 }, { 3388, 99109 }, { 3688, 98827 }, { 3708, 98754 }, { 3682, 98645 },
    { 3681, 98529 }, { 3812, 98343 }, { 3832, 98032 }, { 3768, 97858 }, { 3738, 97832 },
    { 3698, 97832 }, { 3562, 97862 },
}
local RAZOR_WAIT_LEG, RAZOR_LIP_LEG, RAZOR_LAND_LEG = 14, 15, 16

local function InitializeRazorState()
    M.razor, M.razor_state, M.razor_leg = nil, "none", 2
    M.razor_next, M.razor_wait_since, M.razor_jump_at = 0.0, nil, nil
    M.razor_best, M.razor_best_at = nil, 0.0
    M.razor_health = nil
    M.razor_hp, M.razor_armed, M.razor_broke, M.razor_home = {}, {}, {}, nil
    M.razor_past, M.razor_poll = false, 0.0
end

local function RazorPoint(index)
    local point = RAZOR_ROUTE[index]
    local height = (GetTerrainHeightAndNormal(SetVector(point[1], 0.0, point[2])))
    return SetVector(point[1], height or 0.0, point[2])
end

local function RazorDistance(unit, index)
    local pos, point = GetPosition(unit), RAZOR_ROUTE[index]
    local dx, dz = pos.x - point[1], pos.z - point[2]
    return math.sqrt(dx * dx + dz * dz)
end

-- Gradual healing for the guide (misn07's idiom): 2% of max health per second after 4 s unhurt.
-- Through the jump he is held at full health: the 38 m fall is untested.
local function UpdateRazorHeal(unit, now, jumping)
    if jumping then
        AddHealth(unit, GetMaxHealth(unit))
        M.razor_health = nil
        return
    end
    local health = GetHealth(unit)
    local rh = M.razor_health
    if rh == nil then
        M.razor_health = { last = health, hurt = now, at = now }
        return
    end
    local dt = math.min(now - rh.at, 0.5)
    rh.at = now
    if health < rh.last - 0.0005 then rh.hurt = now end
    if health < 1.0 and now - rh.hurt >= RAZOR_HEAL_QUIET_S then
        local gain = math.min(RAZOR_HEAL_PER_S * dt, 1.0 - health)
        if gain > 0 then
            AddHealth(unit, gain * GetMaxHealth(unit))
            health = GetHealth(unit)
        end
    end
    rh.last = health
end

local function RazorGoto(index)
    Goto(M.razor, RazorPoint(index), 1)
end

-- The hunters ordered after the uplink: the stock patrols and guard tanks plus the scaled extras.
local function RazorHunters()
    local list = {}
    for _, keys in ipairs({ RAZOR_HUNTER_KEYS, RAZOR_GUARD_KEYS }) do
        for _, key in ipairs(keys) do
            local unit = M[key]
            if unit ~= nil and IsAlive(unit) then list[#list + 1] = unit end
        end
    end
    for _, unit in ipairs(M.hunters or {}) do
        if IsAlive(unit) then list[#list + 1] = unit end
    end
    return list
end

-- The guard tanks' posts, noted while they still stand on them (before the uplink sends them out).
local function RazorNoteHomes()
    if M.razor_home ~= nil or not M.start_done then return end
    M.razor_home = {}
    for _, key in ipairs(RAZOR_GUARD_KEYS) do
        local unit = M[key]
        if unit ~= nil and IsAlive(unit) then
            local pos = GetPosition(unit)
            M.razor_home[key] = { pos.x, pos.y, pos.z }
        end
    end
end

-- True when the first catch-up has happened. Health is sampled every tick so a hit taken during the
-- stealth phase can never count; a hunter only counts once it has been seen OUTSIDE the catch radius
-- (the guard tanks beside the tower must close in on a human, not merely stand there).
local function RazorCaughtUp()
    local hit = false
    M.razor_hp = M.razor_hp or {}
    CRCoop.ForEachPlayerHandle(function(h, id)
        id = id or 0
        local health = GetHealth(h)
        local last = M.razor_hp[id]
        if last ~= nil and last.handle == h and health < last.health - 0.0005 then
            local shooter = GetWhoShotMe and GetWhoShotMe(h) or nil
            if shooter ~= nil and IsValid(shooter) and GetTeamNum(shooter) == ENEMY_TEAM then hit = true end
        end
        M.razor_hp[id] = { handle = h, health = health }
    end)
    if not (M.interface_complete and not M.game_blown) then return false end
    M.razor_armed = M.razor_armed or {}
    local close = false
    for _, unit in ipairs(RazorHunters()) do
        local near, distance = NearestPlayer(unit)
        if near ~= nil then
            if distance >= RAZOR_CATCH_M then
                M.razor_armed[unit] = true
            elseif M.razor_armed[unit] then
                close = true
            end
        end
    end
    return hit or close
end

-- Terrain line of sight between two objects (true when the ground rises into the line).
local function RazorBlocked(from, to)
    local a, b = GetPosition(from), GetPosition(to)
    for step = 1, RAZOR_SIGHT_STEPS - 1 do
        local t = step / RAZOR_SIGHT_STEPS
        local x, z = a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t
        local line = a.y + (b.y - a.y) * t + RAZOR_EYE_M
        local ground = (GetTerrainHeightAndNormal(SetVector(x, 0.0, z)))
        if ground ~= nil and ground > line then return true end
    end
    return false
end

-- Distance (x, z) from a point to the landing-side route (legs RAZOR_LAND_LEG .. last).
local function RazorRouteDistance(pos)
    local best = math.huge
    for index = RAZOR_LAND_LEG, #RAZOR_ROUTE - 1 do
        local p, q = RAZOR_ROUTE[index], RAZOR_ROUTE[index + 1]
        local dx, dz = q[1] - p[1], q[2] - p[2]
        local length2 = math.max(1.0, dx * dx + dz * dz)
        local t = math.max(0.0, math.min(1.0, ((pos.x - p[1]) * dx + (pos.z - p[2]) * dz) / length2))
        local ex, ez = pos.x - (p[1] + dx * t), pos.z - (p[2] + dz * t)
        best = math.min(best, math.sqrt(ex * ex + ez * ez))
    end
    return best
end

local function RazorLoseScent(unit, key)
    M.razor_broke[unit] = true
    local home = key ~= nil and M.razor_home ~= nil and M.razor_home[key] or nil
    if home ~= nil then
        Goto(unit, SetVector(home[1], home[2], home[3]), 1)   -- a guard tank returns to its post
    else
        Patrol(unit, RAZOR_PATROL_PATH, 1)
    end
end

-- After the jump: a hunter breaks off when no human is close (RAZOR_KEEP_M), none is in sight within
-- RAZOR_LOSE_M, and it is not chasing a human who stayed off the route. Nothing happens until a human
-- is actually on the landing side of the route.
local function RazorBreakOff(now)
    if now < M.razor_poll then return end
    M.razor_poll = now + RAZOR_POLL_S
    local humans, routeHuman, anyRoute = {}, {}, false
    CRCoop.ForEachPlayerHandle(function(h)
        humans[#humans + 1] = h
        local pos = GetPosition(h)
        if RazorRouteDistance(pos) < RAZOR_CORRIDOR_M and pos.z < RAZOR_ROUTE[RAZOR_LAND_LEG][2] + RAZOR_CORRIDOR_M then
            routeHuman[h] = true
            anyRoute = true
        end
    end)
    if not anyRoute then return end
    local guards = {}
    for _, key in ipairs(RAZOR_GUARD_KEYS) do
        if M[key] ~= nil then guards[M[key]] = key end
    end
    for _, unit in ipairs(RazorHunters()) do
        if not M.razor_broke[unit] then
            local keep = false
            local prey = GetCurrentWho and GetCurrentWho(unit) or nil
            for _, h in ipairs(humans) do
                if h == prey and not routeHuman[h] then keep = true end
                if not keep then
                    local d = Distance(h, unit)
                    if d <= RAZOR_KEEP_M or (d <= RAZOR_LOSE_M and not RazorBlocked(unit, h)) then keep = true end
                end
            end
            if not keep then RazorLoseScent(unit, guards[unit]) end
        end
    end
end

local function UpdateRazor()
    if not RAZOR_ONE then return end
    local now = GetTime()
    local state = M.razor_state
    RazorNoteHomes()
    if M.razor_past then RazorBreakOff(now) end
    if state == "none" then
        -- The hunters have caught up for the first time: the exit appears at the compound, disguised
        -- and marked, calls everyone on the radio and goes to the head of the channel to wait.
        if RazorCaughtUp() then
            local unit = BuildObject(RAZOR_ODF, LEADER_TEAM, M.check2_geyser)
            M.razor, M.razor_state = unit, "held"
            SetPerceivedTeam(unit, ENEMY_TEAM)
            SetObjectiveOn(unit)
            SetObjectiveName(unit, "Razor One")
            AudioMessage("misn1224.wav")
            M.razor_wait_since, M.razor_next = now, now + RAZOR_REORDER_S
            Goto(unit, RazorPoint(2), 1)
        end
        return
    end
    if state == "gone" or state == "done" then return end
    local unit = M.razor
    if not IsAlive(unit) then
        M.razor_state = "gone"
        return
    end
    UpdateRazorHeal(unit, now, state == "jump")
    if state == "held" then
        -- Waiting at the head of the channel: the first human to come near, or the timeout, starts the run.
        local near, distance = NearestPlayer(unit)
        if (near ~= nil and distance < RAZOR_MEET_M) or now - M.razor_wait_since >= RAZOR_WAIT_TIMEOUT_S then
            M.razor_state, M.razor_leg, M.razor_next, M.razor_best = "lead", 2, 0.0, nil
        elseif now >= M.razor_next then
            M.razor_next = now + RAZOR_REORDER_S
            Goto(unit, RazorPoint(2), 1)
        end
        return
    end
    if state == "jump" then
        local landed = RazorDistance(unit, RAZOR_LAND_LEG) < RAZOR_LAND_M
        if landed or now - M.razor_jump_at >= RAZOR_JUMP_TIMEOUT_S then
            if not landed then
                -- The gap was not cleared: put him on the ledge rather than strand the guide.
                local point = RazorPoint(RAZOR_LAND_LEG)
                SetPosition(unit, SetVector(point.x, point.y + 6.0, point.z))
                SetVelocity(unit, SetVector(0.0, 0.0, 0.0))
            end
            M.razor_state, M.razor_leg, M.razor_next, M.razor_best = "lead", RAZOR_LAND_LEG + 1, 0.0, nil
            M.razor_past = true   -- Razor has cleared the jump: the pursuit may lose the scent
        end
        return
    end
    -- state == "lead"
    local leg = M.razor_leg
    local distance = RazorDistance(unit, leg)
    if leg == RAZOR_WAIT_LEG and distance < RAZOR_ARRIVE_M then
        -- The foot of the lip: a leader who outruns the group stops being one.
        M.razor_wait_since = M.razor_wait_since or now
        local near, nearest = NearestPlayer(unit)
        if (near ~= nil and nearest < RAZOR_WAIT_M) or now - M.razor_wait_since >= RAZOR_WAIT_TIMEOUT_S then
            M.razor_leg, M.razor_next, M.razor_best = RAZOR_LIP_LEG, 0.0, nil
        end
        return
    end
    if leg == RAZOR_LIP_LEG and distance < RAZOR_LIP_M then
        -- Launch: ground AI would refuse the gap, so he is thrown at the landing.
        local pos, landing = GetPosition(unit), RAZOR_ROUTE[RAZOR_LAND_LEG]
        local dx, dz = landing[1] - pos.x, landing[2] - pos.z
        local length = math.max(1.0, math.sqrt(dx * dx + dz * dz))
        SetVelocity(unit, SetVector(dx / length * RAZOR_JUMP_SPEED, RAZOR_JUMP_LIFT, dz / length * RAZOR_JUMP_SPEED))
        M.razor_state, M.razor_jump_at = "jump", now
        return
    end
    if distance < RAZOR_ARRIVE_M then
        if leg >= #RAZOR_ROUTE then
            M.razor_state = "done"
            Goto(unit, M.nav1, 1)
            return
        end
        M.razor_leg, M.razor_next, M.razor_best = leg + 1, 0.0, nil
        leg = M.razor_leg
    end
    -- Progress watchdog: a leg that does not shorten for RAZOR_STUCK_S is skipped by teleport.
    if M.razor_best == nil or distance < M.razor_best - 10.0 then
        M.razor_best, M.razor_best_at = distance, now
    elseif now - M.razor_best_at >= RAZOR_STUCK_S and leg ~= RAZOR_WAIT_LEG then
        local point = RazorPoint(leg)
        SetPosition(unit, SetVector(point.x, point.y + 4.0, point.z))
        SetVelocity(unit, SetVector(0.0, 0.0, 0.0))
        M.razor_best, M.razor_best_at = nil, now
    end
    if now >= M.razor_next then
        M.razor_next = now + RAZOR_REORDER_S
        RazorGoto(leg)
    end
end
-- CR Razor One <<
-- CR Europa weather >>
local europaStarted, europaAnnounced = false, false

local function InitEuropaWeather()
    europaStarted = true
    local net = CRCoop.IsNetworkGame()
    local authority = (not net) or CRCoop.IsAuthority()
    Environment.Init()
    Environment.BindWeatherSensors("Europa", CREuropaWeather)
    CREuropaWeather.Init({
        authority = authority,
        seed = M.europaSeed, -- nil: the leader/offline picks one, guests wait for the host's state
        sites = EuropaSites,
        startLevel = 1,
        targetLevel = 1,
        -- The host queues straight onto the stream: its own Present() would apply the event again.
        send = net and function(op, ...)
            events[#events + 1] = { op = op, args = { ... }, n = select("#", ...), ttl = RESOLVE_TIMEOUT, target = 0 }
        end or nil,
    })
    if M.weatherState ~= nil and authority then
        CREuropaWeather.Load(M.weatherState)
        M.weatherState = nil
    end
    if authority then M.europaSeed = CREuropaWeather.Seed end -- survives a save
end

-- Every peer, every frame after the session is ready.
local function UpdateEuropaWeather(dt)
    if not europaStarted then InitEuropaWeather() end
    if CRCoop.IsNetworkGame() and CRCoop.IsAuthority() and not europaAnnounced and CRCoop.IsSessionReady() then
        europaAnnounced = true
        CREuropaWeather.AnnounceState()
    end
    CREuropaWeather.Update(dt)
    Environment.Update(dt)
end

local function ShutdownEuropaWeather()
    if europaStarted then CREuropaWeather.Shutdown() end
    europaStarted, europaAnnounced = false, false
end

-- Victory eases the sky back to calm while the result screen counts down. EndMission has
-- already queued the result; this only nudges the director (leader/offline).
local presentSucceed = SucceedMission
local function SucceedMission(...)
    if (not M.europaCalm) and ((not CRCoop.IsNetworkGame()) or CRCoop.IsAuthority()) then
        M.europaCalm = true
        CREuropaWeather.ReleaseForcedLevel()
        CREuropaWeather.SetTargetLevel(1)
    end
    return presentSucceed(...)
end

-- The index of a named vent in the director's site list (nil when absent).
local function VentIndex(label)
    for index, site in ipairs(CREuropaWeather.GetVentSites()) do
        if site.label == label then return index end
    end
end

-- Host/offline only, each beat once. The weather is cosmetic: it never changes who sees whom, never
-- damages, never touches perception; these beats only follow the mission's mood.
--   1 (quiet) while the infiltrators work -> 2 once a ship is stolen -> 3 with a plume, a brief ice
--   quake and a radiation surge when the uplink completes (the escape) -> 4 if cover is blown ->
--   calm on the win.
local function UpdateEuropaBeats()
    local beats = M.europaBeats
    if beats == nil then beats = {}; M.europaBeats = beats end
    if (not beats.stolen) and M.captured_any then
        beats.stolen = true
        CREuropaWeather.SetTargetLevel(2)
    end
    if (not beats.uplink) and M.interface_complete then
        beats.uplink = true
        CREuropaWeather.SetTargetLevel(3)
        CREuropaWeather.TriggerPlume(VentIndex("center_geyser"))
        CREuropaWeather.Quake(0.35, 3.0)
        CREuropaWeather.Surge(6.0, 0.8)
    end
    if (not beats.blown) and M.game_blown then
        beats.blown = true
        CREuropaWeather.SetTargetLevel(4)
    end
end
-- CR Europa weather <<
-- CR artillery >>
-- The four CCA howitzers the DLL never orders. They shell a human only once that human is
-- exposed (not wearing the key ship's disguise): a disguised infiltrator is a friendly to them,
-- so the stealth route stays quiet. Re-evaluated every 3 s, re-issued every 6 s.
local ART_RANGE_M = 650.0

-- The authored labels artil1-artil4 (Missions/misn12.bzn).
local function FindArtillery()
    local found = {}
    for _, label in ipairs({ "artil1", "artil2", "artil3", "artil4" }) do
        local h = GetHandle(label)
        if h ~= nil and IsAlive(h) then found[#found + 1] = h end
    end
    return found
end

local function UpdateArtillery()
    if GetTime() < (M.next_arty or 0) then return end
    M.next_arty = GetTime() + 3.0
    for _, art in ipairs(M.arty or {}) do
        if IsAlive(art) then
            local victim, bestDistance = nil, ART_RANGE_M
            CRCoop.ForEachPlayerHandle(function(h, id)
                if M.exposed and M.exposed[id or 0] then
                    local distance = Distance(h, art)
                    if distance < bestDistance then victim, bestDistance = h, distance end
                end
            end)
            if victim ~= nil then
                if M.arty_target[art] ~= victim or GetTime() >= (M.arty_reissue[art] or 0) then
                    M.arty_target[art], M.arty_reissue[art] = victim, GetTime() + 6.0
                    Attack(art, victim, 1)
                end
            elseif M.arty_target[art] ~= nil then
                M.arty_target[art] = nil
                Stop(art, 1)
            end
        end
    end
end
-- CR artillery <<
-- CR co-op layer >>
local function ConfigureAlliances()
    CRCoop.ApplyCoopAlliances(ENEMY_TEAM)
end

local function InitializeCoop()
    CRCoop.Initialize({
        getLocalPlayerId = function() return exu.GetMyNetID and exu.GetMyNetID() end,
        leaderTeam = LEADER_TEAM, humanTeamMin = 1, humanTeamMax = 4,
        onOutOfLives = function() FailMission(GetTime() + 3.0) end,
        -- A respawned human arrives at the drop zone, where the mission begins.
        rallyPoints = { [0] = "apcamr20_camerapod" },
    })
    ConfigureAlliances()
    ResetPresentation()
    ShutdownEuropaWeather()
end

-- Co-op state outside the DLL's serialized fields.
local function InitializeCoopState()
    M.hstore, M.sstore, M.hcraft, M.exposed, M.arrived = {}, {}, {}, {}, {}
    M.hcur, M.scur, M.slots = nil, 1, 1
    M.multi, M.strict, M.captured_any, M.shot_until = false, false, false, 0.0
    M.arty, M.arty_target, M.arty_reissue, M.next_arty = {}, {}, {}, 0.0
    InitializeRazorState()
end

-- The mission's player count, fixed when the mission starts: several humans means stealth is
-- shared (one exposure fails everyone), one ship per human, scaled patrols.
local function StartCoopBookkeeping()
    local count = HumanCount()
    M.multi = count > 1
    M.strict = M.multi
    M.slots = math.min(MAX_PLAYERS, math.max(1, count))
    M.arty = FindArtillery()
    for index = 2, M.slots do
        local defaults = SlotDefaults()
        defaults.slot_spawn_at = GetTime() + (index - 1) * KEY_STAGGER_S
        M.sstore[index] = defaults
    end
end

-- Slot k > 1: the staggered key ship leaves the spawn geyser on its own schedule.
local function SpawnStaggeredKeyShip()
    if (M.scur or 1) <= 1 or M.key_ship ~= nil or not M.start_done then return end
    if M.slot_spawn_at == nil or GetTime() < M.slot_spawn_at then return end
    M.key_ship = BuildObject("svfi12", ENEMY_TEAM, M.spawn_geyser)
    SetWeaponMask(M.key_ship, 3)
    Goto(M.key_ship, "first_path")
end

-- A key ship is taken the moment a human's craft IS that ship; it then leaves the checkpoint cycle.
local function LatchSlotCapture()
    if M.slot_captured or not IsVehicleAlive(M.key_ship) then return end
    CRCoop.ForEachPlayerHandle(function(h)
        if h == M.key_ship then M.slot_captured = true end
    end)
end

-- Whether this human is currently a target for the howitzers.
local function RecordExposure(entry)
    M.exposed[entry.id] = (not M.key_captured) or M.out_of_ship or M.real_bad or M.game_blown or false
end

-- The first capture starts the shared tour; in a network game the hijacked ship must keep the
-- CCA's face (the owning team differs).
local function Disguise(entry)
    M.captured_any = true
    if CRCoop.IsNetworkGame() then SetPerceivedTeam(entry.handle, ENEMY_TEAM) end
end

-- Extra patrol fighters, one per extra human, on the centre loop.
local function BuildExtraPatrols()
    M.extra_patrols = M.extra_patrols or {}
    for _ = 1, ExtraHumans() do
        local unit = BuildObject("svfigh", ENEMY_TEAM, M.spawn_point1)
        Patrol(unit, "path5")
        M.extra_patrols[#M.extra_patrols + 1] = unit
    end
end

-- Extra hunters once the uplink is done and the escape begins, one per extra human.
local function BuildHunters()
    M.hunters = M.hunters or {}
    for index = 1, ExtraHumans() do
        local unit = BuildObject("svfigh", ENEMY_TEAM, (index % 2 == 1) and M.spawn_point2 or M.spawn_point1)
        Attack(unit, TargetFor(unit))
        M.hunters[#M.hunters + 1] = unit
    end
end
-- CR co-op layer <<
function Start()
-- CR co-op layer >>
    InitializeCoop()
-- CR co-op layer <<
    M = NewState()
-- CR co-op layer >>
    InitializeCoopState()
    subtit.Initialize()
-- CR co-op layer <<
    --[==[ Here's where you set the values at the start. ]==]
    M.start_done = false
    M.key_captured = false
    M.check_point1_done = false
    M.check_point2_done = false
    M.check_point3_done = false
    M.check_point4_done = false
    M.check_point5_done = false
    M.check1 = false
    M.check2 = false
    M.check3 = false
    M.check4 = false
    M.objective1 = false
    M.out_of_order1 = false
    M.out_of_order2 = false
    M.out_of_order3 = false
    M.out_of_order4 = false
    M.out_of_order5 = false
    M.interface_connect = false
    M.link_broken = false
    M.interface_complete = false
    M.warning_message = false
    M.cca_message1 = false
    M.cca_message2 = false
    M.cca_message3 = false
    M.cca_message4 = false
    M.enter_base = false
    M.did_it_right = false
    M.discovered = false
    M.straight_to_5 = false
    M.noise = false
    M.camera_on = false
    M.camera_off = false
    M.camera1 = false
    M.camera2 = false
    M.camera3 = false
    M.camera4 = false
    M.camera5 = false
    M.win = false
    M.checked_in = false
    M.identify_message = false
    M.cca_warning_message = false
    M.better_message = false
    M.real_bad = false
    M.over = false
    M.going_again = false
    M.key_gone = false
    M.game_blown = false
    M.final_warned = false
    M.last_warned = false
    M.follow_spawn = false
    M.good1 = false
    M.good2 = false
    M.good3 = false
    M.good1_off = false
    M.good2_off = false
    M.good3_off = false
    M.dead_meat = false
    M.patrol1_create = false
    M.patrol2_create = false
    M.patrol3_create = false
    M.patrol4_create = false
    M.patrol1_moved1 = false
    M.patrol2_moved1 = false
    M.patrol3_moved1 = false
    M.patrol4_moved1 = false
    M.patrol1_moved2 = false
    M.patrol2_moved2 = false
    M.patrol3_moved2 = false
    M.patrol4_moved2 = false
    M.patrol1_1_gone = false
    M.patrol1_2_gone = false
    M.patrol2_1_gone = false
    M.patrol2_2_gone = false
    M.patrol3_1_gone = false
    M.patrol3_2_gone = false
    M.patrol4_1_gone = false
    M.patrol4_2_gone = false
    M.p1_1center = false
    M.p2_1center = false
    M.p2_2center = false
    M.p3_1center = false
    M.p3_2center = false
    M.p4_1center = false
    M.p4_2center = false
    M.game_over = false
    M.camera_swap1 = false
    M.camera_swap2 = false
    M.camera_swap_back = false
    M.camera_noise = false
    M.out_of_ship = false
    M.blown_otf = false
    M.grump = false
    M.warning_repeat_time = 99999.0
    M.countdown_time = 99999.0
    M.camera_on_time = 99999.0
    M.interface_time = 99999.0
    M.next_noise_time = 99999.0
    M.camera_time = 99999.0
    M.next_message_time = 99999.0
    M.win_check_time = 99999.0
    M.start_patrol = 99999.0
    M.key_check = 99999.0
    M.wait_time = 99999.0
    M.key_remove = 99999.0
    M.death_spawn = 99999.0
    M.final_warning = 99999.0
    M.last_warning = 99999.0
    M.remove_patrol1_2 = 99999.0
    M.patrol1_1_time = 99999.0
    M.patrol1_2_time = 99999.0
    M.patrol2_1_time = 99999.0
    M.patrol2_2_time = 99999.0
    M.patrol3_1_time = 99999.0
    M.patrol3_2_time = 99999.0
    M.patrol4_1_time = 99999.0
    M.patrol4_2_time = 99999.0
    M.swap_check = 99999.0
    M.grump_time = 99999.0
    M.next_second = 0
    M.key_ship = nil
    M.checkpoint1 = GetHandle("checktower1")
    M.checkpoint2 = GetHandle("svguntower2")
    M.checkpoint3 = GetHandle("svmuf")
    M.checkpoint4 = GetHandle("svsilo1")
    M.center = GetHandle("center")
    --	ccasilo1 = GetHandle ("svsilo1");
    M.ccasilo2 = GetHandle("svsilo2")
    M.ccasilo3 = GetHandle("svsilo3")
    M.ccasilo4 = GetHandle("svsilo4")
    M.ccamuf = GetHandle("svmuf")
    M.ccacom_tower = GetHandle("svcom_tower")
    M.spawn_point1 = GetHandle("spawn_geyser1")
    M.spawn_point2 = GetHandle("spawn_geyser2")
    M.nav1 = GetHandle("apcamr20_camerapod")
    M.spawn_geyser = GetHandle("spawn_geyser")
    M.choke_geyser = GetHandle("choke_geyser")
    M.check2_geyser = GetHandle("check2_geyser")
    M.center_geyser = GetHandle("center_geyser")
    M.guard_fighter = GetHandle("pfighter2")
    M.parked_fighter = GetHandle("pfighter1")
    M.parked_tank2 = GetHandle("ptank2")
    M.parked_tank1 = GetHandle("ptank1")
    M.guard_turret = GetHandle("turret6")
    M.pturret1 = GetHandle("turret1")
    M.pturret2 = GetHandle("turret2")
    M.pturret3 = GetHandle("turret3")
    M.pturret4 = GetHandle("turret4")
    M.pturret5 = GetHandle("turret5")
    M.pturret6 = GetHandle("turret6")
    M.patrol1_1 = GetHandle("svfigh1_1")
    M.patrol1_2 = GetHandle("svfigh1_2")
    M.patrol2_1 = GetHandle("svfigh2_1")
    M.patrol2_2 = GetHandle("svfigh2_2")
    M.patrol3_1 = GetHandle("svfigh3_1")
    M.patrol3_2 = GetHandle("svfigh3_2")
    M.patrol4_1 = GetHandle("svfigh4_1")
    M.patrol4_2 = GetHandle("svfigh4_2")
    M.guard_tank1 = GetHandle("gtank1")
    M.guard_tank2 = GetHandle("gtank2")
    M.follower = nil
    M.death_squad1 = nil
    M.death_squad2 = nil
    M.death_squad3 = nil
    M.death_squad4 = nil
    M.guard1 = nil
    M.guard2 = nil
    M.guard3 = nil
    M.guard4 = nil
    M.center_cam = nil
    M.start_cam = nil
    M.check2_cam = nil
    M.check3_cam = nil
    M.check4_cam = nil
    M.goal_cam = nil
end
function AddObject(h)
    -- Original AddObject(Handle h) is empty.
-- CR Europa weather >>
    if not IsValid(h) then return end
    Environment.OnObjectCreated(h)
    CREuropaWeather.OnObjectCreated(h)
-- CR Europa weather <<
end

-- CR co-op layer >>
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
-- CR co-op layer <<
local function UpdateStart()
    if not M.start_done then
        AudioMessage("misn1200.wav")
        M.user_tank = GetPlayerHandle()
        -- this assigns the tank a handle
        --		Defend(key_ship);
        ClearObjectives()
        AddObjective("misn1200.otf", "white")
        Defend(M.guard_tank1)
        Defend(M.guard_tank2)
        Defend(M.patrol1_1)
        Defend(M.patrol1_2)
        Defend(M.patrol2_1)
        Defend(M.patrol2_2)
        Defend(M.patrol3_1)
        Defend(M.patrol3_2)
        Defend(M.patrol4_1)
        Defend(M.patrol4_2)
        StartCockpitTimer(1200, 300, 120)
        SetObjectiveOn(M.checkpoint1)
        SetObjectiveName(M.checkpoint1, "Check Point")
        M.center_cam = BuildObject("apcamr", HIDDEN_TEAM, "center_cam")
        M.start_cam = BuildObject("apcamr", HIDDEN_TEAM, "start_cam")
        M.check2_cam = BuildObject("apcamr", HIDDEN_TEAM, "check2_cam")
        M.check3_cam = BuildObject("apcamr", HIDDEN_TEAM, "check3_cam")
        M.check4_cam = BuildObject("apcamr", HIDDEN_TEAM, "check4_cam")
        M.goal_cam = BuildObject("apcamr", HIDDEN_TEAM, "goal_cam")
        M.key_ship = BuildObject("svfi12", ENEMY_TEAM, M.spawn_geyser)
        SetWeaponMask(M.key_ship, 3)
        Goto(M.key_ship, "first_path")
        -- gets the patrol ship to move towards checkpoint1
        M.key_check = GetTime() + 2.0
        CameraReady()
        M.camera_time = GetTime() + 12.0
        -- Port safety: validate the object before the native SetName equivalent;
        -- missing/deleted nav objects are skipped without changing mission flags or timing.
        if IsValid(M.nav1) then
            SetObjectiveName(M.nav1, "Drop Zone")
        end
-- CR co-op layer >>
        StartCoopBookkeeping()
-- CR co-op layer <<
        M.start_done = true
    end
    if IsAlive(M.ccacom_tower) then
        if GetTime() > M.next_second then
            AddHealth(M.ccacom_tower, 200.0)
            M.next_second = GetTime() + 1.0
        end
    end
end
local function UpdateBlownTank()
    -- this what happens if the player is discovered before taking over the ship
    if (not M.game_blown) and (not M.key_captured) then
        if (IsAlive(M.user_tank)) and (GetHealth(M.user_tank) < 0.90) then
            AudioMessage("misn1213.wav")
            M.death_spawn = GetTime() + 5.0
            M.game_blown = true
        end
    end
end
local function UpdateBlownKeyShip()
-- CR co-op layer >>
    LatchSlotCapture()
-- CR co-op layer <<
    if IsVehicleAlive(M.key_ship) then
        if (not M.game_blown) and (not M.slot_captured) and (GetHealth(M.key_ship) < 0.50) then
            AudioMessage("misn1228.wav")
            M.death_spawn = GetTime() + 5.0
            M.game_blown = true
        end
    end
end
local function UpdateBlownTankNearCheckpoint()
    -- this is what happens is the player tries to get in with his tank
    if (IsAlive(M.user_tank)) and (Distance(M.user_tank, M.checkpoint1) < 75.0) and (not M.key_captured) and (not M.game_blown) then
        AudioMessage("misn1213.wav")
        M.death_spawn = GetTime() + 5.0
        ClearObjectives()
        AddObjective("misn1200.otf", "red")
        M.game_blown = true
    end
end
local function UpdateDeathSquad()
    -- this is game_blown code
    if (M.game_blown) and (M.death_spawn < GetTime()) then
        M.death_spawn = GetTime() + 120.0
        M.death_squad1 = BuildObject("svfigh", ENEMY_TEAM, M.spawn_geyser)
        M.death_squad2 = BuildObject("svfigh", ENEMY_TEAM, M.spawn_geyser)
        M.death_squad3 = BuildObject("svltnk", ENEMY_TEAM, M.spawn_geyser)
        M.death_squad4 = BuildObject("svltnk", ENEMY_TEAM, M.spawn_geyser)
        Attack(M.death_squad1, TargetFor(M.death_squad1))
        Attack(M.death_squad2, TargetFor(M.death_squad2))
        Attack(M.death_squad3, TargetFor(M.death_squad3))
        Attack(M.death_squad4, TargetFor(M.death_squad4))
    end
end
local function UpdateDeadMeat()
    if (M.game_blown) and (not IsAlive(M.user_tank)) and (not M.dead_meat) then
        SetPerceivedTeam(M.user, 1)
        M.dead_meat = true
    end
end
local function UpdateOpening()
    -- this is the start of the camera during the players briefing
    if (M.start_done) and (not M.camera4) then
        CameraPath("start_camera_path", 4000, 900, M.ccacom_tower)
    end
    if ((CameraCancelled()) or (M.camera_time < GetTime())) and (not M.camera4) then
        CameraFinish()
        M.camera4 = true
    end
end
local function UpdatePatrols()
    -- this is the start of patroling the cca ships
    if (M.camera_off) and (not M.patrol1_create) then
        -- change start_done to key_captured
        Goto(M.patrol1_1, "path1_to")
        Goto(M.patrol1_2, "path1_to")
        M.patrol1_create = true
-- CR scaling >>
        BuildExtraPatrols()
-- CR scaling <<
    end
    if (M.patrol1_create) and (IsAlive(M.patrol1_1)) and (Distance(M.patrol1_1, M.checkpoint1) < 50.0) and (not M.patrol1_moved1) then
        if (IsAlive(M.patrol1_2) and (Distance(M.patrol1_2, M.checkpoint1) < 70.0)) then
            Goto(M.patrol1_1, "path1_from")
            Goto(M.patrol1_2, "path1_from")
            M.patrol1_moved1 = true
        end
    end
    if (M.patrol1_moved1) and (IsAlive(M.patrol1_1)) and (Distance(M.patrol1_1, M.center_geyser) < 50.0) and (not M.patrol1_moved2) then
        if (IsAlive(M.patrol1_2) and (Distance(M.patrol1_2, M.center_geyser) < 50.0)) then
            Goto(M.patrol1_1, "path2")
            Patrol(M.patrol1_2, "path5")
            Goto(M.patrol2_1, "path3")
            M.patrol2_1_time = GetTime() + 15.0
            M.patrol1_moved2 = true
        end
    end
    -- move 2_2
    if (M.patrol1_moved2) and (IsAlive(M.patrol1_1)) and (Distance(M.patrol1_1, M.check2_geyser) < 400.0) and (not M.patrol2_moved1) then
        Goto(M.patrol2_2, "path2")
        Goto(M.patrol4_1, "path4")
        M.p4_1center = true
        M.patrol2_2_time = GetTime() + 11.0
        M.patrol1_1_time = GetTime() + 10.0
        M.patrol4_1_time = GetTime() + 12.0
        M.patrol2_moved1 = true
    end
    -- send 3_1 on route
    if (IsAlive(M.patrol2_1)) and (Distance(M.patrol2_1, M.ccamuf) < 400.0) and (not M.patrol3_moved1) then
        Goto(M.patrol3_1, "path4")
        M.patrol3_1_time = GetTime() + 5.0
        M.p3_1center = true
        M.patrol3_moved1 = true
    end
    -- send 3_2 on route
    if (IsAlive(M.patrol2_2)) and (Distance(M.patrol2_2, M.ccamuf) < 400.0) and (not M.patrol3_moved2) then
        Goto(M.patrol3_2, "path4")
        M.p3_2center = true
        M.patrol3_2_time = GetTime() + 10.0
        M.patrol3_moved2 = true
    end
    -- send 4_2
    if (IsAlive(M.patrol3_1)) and (Distance(M.patrol3_1, M.checkpoint4) < 400.0) and (not M.patrol4_moved2) then
        Goto(M.patrol4_2, "path4")
        M.patrol4_2_time = GetTime() + 5.0
        M.p4_2center = true
        M.patrol4_moved2 = true
    end
    -- check patrols
    if (not M.real_bad) or (not M.game_blown) then
        -- 1_1
        if (IsAlive(M.patrol1_1)) and (M.patrol1_1_time < GetTime()) then
            M.patrol1_1_time = GetTime() + 10.0
            if (not M.p1_1center) and (Distance(M.patrol1_1, M.center_geyser) < 50.0) then
                Goto(M.patrol1_1, "path3")
                M.p1_1center = true
            else
                if Distance(M.patrol1_1, M.center_geyser) < 50.0 then
                    Goto(M.patrol1_1, "path2")
                    M.p1_1center = false
                else
                    if Distance(M.patrol1_1, M.ccamuf) < 70.0 then
                        Goto(M.patrol1_1, "path4")
                    end
                end
            end
        end
        -- 2_1
        if (IsAlive(M.patrol2_1)) and (M.patrol2_1_time < GetTime()) then
            M.patrol2_1_time = GetTime() + 10.0
            if (not M.p2_1center) and (Distance(M.patrol2_1, M.center_geyser) < 50.0) then
                -- BUGFIX: source commands patrol1_1 inside patrol2_1's route check.
                -- Command patrol2_1 so this pair follows its own path3 leg. The same
                -- route, distance gate, 10-second poll, and state transition remain;
                -- checkpoint/warning/uplink progression and spawn timing are unchanged.
                -- Original: Goto(patrol1_1, "path3");
                Goto(M.patrol2_1, "path3")
                M.p2_1center = true
            else
                if Distance(M.patrol2_1, M.center_geyser) < 50.0 then
                    Goto(M.patrol2_1, "path2")
                    M.p2_1center = false
                else
                    if Distance(M.patrol2_1, M.ccamuf) < 70.0 then
                        Goto(M.patrol2_1, "path4")
                    end
                end
            end
        end
        -- 2_2
        if (IsAlive(M.patrol2_2)) and (M.patrol2_2_time < GetTime()) then
            M.patrol2_2_time = GetTime() + 10.0
            if (not M.p2_2center) and (Distance(M.patrol2_2, M.center_geyser) < 50.0) then
                Goto(M.patrol2_2, "path3")
                M.p2_2center = true
            else
                if Distance(M.patrol2_2, M.center_geyser) < 50.0 then
                    Goto(M.patrol2_2, "path2")
                    M.p2_2center = false
                else
                    if Distance(M.patrol2_2, M.ccamuf) < 70.0 then
                        Goto(M.patrol2_2, "path4")
                    end
                end
            end
        end
        --3_1
        if (IsAlive(M.patrol3_1)) and (M.patrol3_1_time < GetTime()) then
            M.patrol3_1_time = GetTime() + 10.0
            if (not M.p3_1center) and (Distance(M.patrol3_1, M.center_geyser) < 50.0) then
                Goto(M.patrol3_1, "path3")
                M.p3_1center = true
            else
                if Distance(M.patrol3_1, M.center_geyser) < 50.0 then
                    Goto(M.patrol3_1, "path2")
                    M.p3_1center = false
                else
                    if Distance(M.patrol3_1, M.ccamuf) < 70.0 then
                        Goto(M.patrol3_1, "path4")
                    end
                end
            end
        end
        --3_2
        if (IsAlive(M.patrol3_2)) and (M.patrol3_2_time < GetTime()) then
            M.patrol3_2_time = GetTime() + 10.0
            if (not M.p3_2center) and (Distance(M.patrol3_2, M.center_geyser) < 50.0) then
                Goto(M.patrol3_2, "path3")
                M.p3_2center = true
            else
                if Distance(M.patrol3_2, M.center_geyser) < 50.0 then
                    Goto(M.patrol3_2, "path2")
                    M.p3_2center = false
                else
                    if Distance(M.patrol3_2, M.ccamuf) < 70.0 then
                        Goto(M.patrol3_2, "path4")
                    end
                end
            end
        end
        --4_1
        if (IsAlive(M.patrol4_1)) and (M.patrol4_1_time < GetTime()) then
            M.patrol4_1_time = GetTime() + 10.0
            if (not M.p4_1center) and (Distance(M.patrol4_1, M.center_geyser) < 50.0) then
                Goto(M.patrol4_1, "path3")
                M.p4_1center = true
            else
                if Distance(M.patrol4_1, M.center_geyser) < 50.0 then
                    Goto(M.patrol4_1, "path2")
                    M.p4_1center = false
                else
                    if Distance(M.patrol4_1, M.ccamuf) < 70.0 then
                        Goto(M.patrol4_1, "path4")
                    end
                end
            end
        end
        --4_2
        if (IsAlive(M.patrol4_2)) and (M.patrol4_2_time < GetTime()) then
            M.patrol4_2_time = GetTime() + 10.0
            if (not M.p4_2center) and (Distance(M.patrol4_2, M.center_geyser) < 50.0) then
                Goto(M.patrol4_2, "path3")
                M.p4_2center = true
            else
                if Distance(M.patrol4_2, M.center_geyser) < 50.0 then
                    Goto(M.patrol4_2, "path2")
                    M.p4_2center = false
                else
                    if Distance(M.patrol4_2, M.ccamuf) < 70.0 then
                        Goto(M.patrol4_2, "path4")
                    end
                end
            end
        end
    end
end
local function UpdateKeyCycle()
-- CR co-op layer >>
    SpawnStaggeredKeyShip()
-- CR co-op layer <<
    if (M.start_done) and (not M.slot_captured) and (not M.checked_in) then
        if IsVehicleAlive(M.key_ship) then
            if (Distance(M.key_ship, M.checkpoint1) < 80.0) then
                Stop(M.key_ship, 1)
                M.wait_time = GetTime() + 20.0
                M.checked_in = true
            end
        end
    end
    if (M.checked_in) and (M.wait_time < GetTime()) and (not M.going_again) and (not M.slot_captured) then
        Goto(M.key_ship, "first_path")
        M.key_remove = GetTime() + 10.0
        M.going_again = true
    end
    if (M.going_again) and (M.key_remove < GetTime()) and (not M.slot_captured) then
        M.key_remove = GetTime() + 3.0
        if Distance(M.key_ship, M.spawn_geyser) < 100.0 then
            RemoveObject(M.key_ship)
            M.key_ship = BuildObject("svfi12", ENEMY_TEAM, M.spawn_geyser)
            SetWeaponMask(M.key_ship, 3)
            Goto(M.key_ship, "first_path")
            M.checked_in = false
            M.going_again = false
        end
    end
end
local function UpdateCapture(entry)
    if (IsOdf(M.user, "svfi12")) and (not M.key_captured) then
        if IsAlive(M.user) then
-- CR co-op layer >>
            TopUpAmmo(entry)
-- CR co-op layer <<
        end
        ClearObjectives()
        AddObjective("misn1200.otf", "green")
        AddObjective("misn1201.otf", "white")
        AddObjective("misn1202.otf", "white")
        AddObjective("misn1203.otf", "white")
        AddObjective("misn1204.otf", "white")
        AudioMessage("misn1217.wav")
-- CR co-op layer >>
        if not M.captured_any then
-- CR co-op layer <<
        M.camera_time = GetTime() + 10.0
-- CR co-op layer >>
        end
-- CR co-op layer <<
        if IsAlive(M.checkpoint1) then
            SetObjectiveOff(M.checkpoint1)
        end
        M.key_captured = true
-- CR co-op layer >>
        Disguise(entry)
-- CR co-op layer <<
    end
    if (M.key_captured) and ((IsOdf(M.user, "svfigh")) or (IsOdf(M.user, "svtank"))) and (not M.out_of_ship) then
        M.out_of_ship = true
-- CR co-op layer >>
        if M.strict and not M.interface_complete then CoverBlown("misn1213.wav") end
-- CR co-op layer <<
    end
    if (M.out_of_ship) and (not M.grump) then
        if IsAlive(M.patrol1_1) then
            Attack(M.patrol1_1, M.user)
        end
        if IsAlive(M.patrol1_2) then
            Attack(M.patrol1_2, M.user)
        end
        if IsAlive(M.patrol2_1) then
            Attack(M.patrol2_1, M.user)
        end
        if IsAlive(M.patrol2_2) then
            Attack(M.patrol2_2, M.user)
        end
        if IsAlive(M.patrol3_1) then
            Attack(M.patrol3_1, M.user)
        end
        if IsAlive(M.patrol3_2) then
            Attack(M.patrol3_2, M.user)
        end
        if IsAlive(M.patrol4_1) then
            Attack(M.patrol4_1, M.user)
        end
        if IsAlive(M.patrol4_2) then
            Attack(M.patrol4_2, M.user)
        end
        if IsAlive(M.guard_tank1) then
            Attack(M.guard_tank1, M.user)
        end
        if IsAlive(M.guard_tank2) then
            Attack(M.guard_tank2, M.user)
        end
        if (not M.interface_complete) and (not M.blown_otf) then
            ClearObjectives()
            AddObjective("misn1206.otf", "white")
            M.blown_otf = true
        end
        M.grump_time = GetTime() + 180.0
        M.grump = true
    end
end
local function UpdateMovie()
    if M.grump_time < GetTime() then
        M.grump = false
    end
    -- heres where we start the big movie
    if (M.captured_any) and (M.camera_time < GetTime()) and (not M.camera_on) and (not M.camera_off) then
        CameraReady()
        M.camera_on = true
    end
    if (M.camera_on) and (not M.camera1) and (not M.camera2) and (not M.camera3) and (not M.camera_off) then
        CameraObject(M.checkpoint2, 0, 1000, 6000, M.checkpoint2)
        M.audmsg = AudioMessage("misn1218.wav")
        M.camera_time = GetTime() + 6.0
        M.camera1 = true
    end
    if ((M.camera1) and (not M.camera2) and (not M.camera3) and (not M.camera_off)) and ((M.camera_time < GetTime()) or (CameraCancelled())) then
        StopAudioMessage(M.audmsg)
        CameraObject(M.checkpoint3, 3000, 3000, 3000, M.checkpoint3)
        M.audmsg = AudioMessage("misn1219.wav")
        M.camera_time = GetTime() + 6.0
        M.camera2 = true
    end
    if ((M.camera2) and (not M.camera3) and (not M.camera_off)) and ((M.camera_time < GetTime()) or (CameraCancelled())) then
        StopAudioMessage(M.audmsg)
        CameraObject(M.checkpoint4, - 1000, 1500, 4000, M.checkpoint4)
        M.audmsg = AudioMessage("misn1220.wav")
        M.camera_time = GetTime() + 6.0
        M.camera3 = true
    end
    if ((M.camera3) and (not M.camera_off)) and ((M.camera_time < GetTime()) or (CameraCancelled())) then
        StopAudioMessage(M.audmsg)
        AudioMessage("misn1221.wav")
        AudioMessage("misn1222.wav")
        CameraFinish()
        M.camera_off = true
    end
end
local function UpdateProgress(entry)
    -- this is where I script the how the player must check in at each check point
    --	if (!check2)
    --	{
    if Distance(M.user, M.checkpoint2) < 150.0 then
        M.check_point2_done = true
    end
    if (M.check_point2_done) and (Distance(M.user, M.checkpoint2) > 150.0) then
        M.check_point2_done = false
    end
    --	}
    --	if (!check3)
    --	{
    if Distance(M.user, M.checkpoint3) < 150.0 then
        M.check_point3_done = true
    end
    if (M.check_point3_done) and (Distance(M.user, M.checkpoint3) > 150.0) then
        M.check_point3_done = false
    end
    --	}
    --	if (!check4)
    --	{
    if Distance(M.user, M.checkpoint4) < 150.0 then
        M.check_point4_done = true
    end
    if (M.check_point4_done) and (Distance(M.user, M.checkpoint4) > 150.0) then
        M.check_point4_done = false
    end
    --	}
    if Distance(M.user, M.ccacom_tower) < 150.0 then
        M.check_point5_done = true
    end
    if (M.check_point5_done) and (Distance(M.user, M.ccacom_tower) > 150.0) then
        M.check_point5_done = false
    end
    -- the following is if the player does it right
    if not M.interface_complete then
        if (Distance(M.user, M.checkpoint2) < 70.0) and (not M.cca_warning_message) and (not M.identify_message) and (not M.check2) then
            -- CR co-op layer >>
            local shot = CheckpointShotReady()
            -- CR co-op layer <<
            M.good1 = true
            if M.good1 then
                -- CR co-op layer >>
                if shot then
                    CameraObject(M.user, 0, 700, - 1500, M.user)
                    M.camera_time = GetTime() + 5.0
                    M.shot_until = M.camera_time
                else
                    M.good1_off = true
                end
                -- CR co-op layer <<
                AudioMessage("misn1207.wav")
                -- soviet voice that is calm
                ClearObjectives()
                AddObjective("misn1200.otf", "green")
                AddObjective("misn1201.otf", "green")
                AddObjective("misn1202.otf", "white")
                AddObjective("misn1203.otf", "white")
                AddObjective("misn1204.otf", "white")
                M.check2 = true
            end
        end
        if (M.good1) and (M.camera_time < GetTime()) and (not M.good1_off) then
            CameraFinish()
            M.good1_off = true
        end
        if (M.check2) and (Distance(M.user, M.checkpoint3) < 70.0) and (not M.cca_warning_message) and (not M.identify_message) and (not M.check3) then
            -- CR co-op layer >>
            local shot = CheckpointShotReady()
            -- CR co-op layer <<
            M.good2 = true
            if M.good2 then
                -- CR co-op layer >>
                if shot then
                    CameraObject(M.user, 0, 700, - 1500, M.user)
                    M.camera_time = GetTime() + 6.0
                    M.shot_until = M.camera_time
                else
                    M.good2_off = true
                end
                -- CR co-op layer <<
                AudioMessage("misn1208.wav")
                -- soviet voice that is calm
                ClearObjectives()
                AddObjective("misn1200.otf", "green")
                AddObjective("misn1201.otf", "green")
                AddObjective("misn1202.otf", "green")
                AddObjective("misn1203.otf", "white")
                AddObjective("misn1204.otf", "white")
                M.check3 = true
            end
        end
        if (M.good2) and (M.camera_time < GetTime()) and (not M.good2_off) then
            CameraFinish()
            M.good2_off = true
        end
        if (Distance(M.user, M.checkpoint4) < 70.0) and (M.check3) and (not M.check4) and (not M.cca_warning_message) and (not M.identify_message) then
            -- CR co-op layer >>
            local shot = CheckpointShotReady()
            -- CR co-op layer <<
            M.good3 = true
            if M.good3 then
                -- CR co-op layer >>
                if shot then
                    CameraObject(M.user, 0, 700, - 1500, M.user)
                    M.camera_time = GetTime() + 6.0
                    M.shot_until = M.camera_time
                else
                    M.good3_off = true
                end
                -- CR co-op layer <<
                AudioMessage("misn1209.wav")
                -- soviet voice that is calm
                ClearObjectives()
                AddObjective("misn1200.otf", "green")
                AddObjective("misn1201.otf", "green")
                AddObjective("misn1202.otf", "green")
                AddObjective("misn1203.otf", "green")
                AddObjective("misn1204.otf", "white")
                M.check4 = true
            end
        end
        if (M.good3) and (M.camera_time < GetTime()) and (not M.good3_off) then
            CameraFinish()
            M.good3_off = true
        end
    end
    --/////////////////////////////////////////////////////////////////////////////////////
    -- the TWOS
    -- if he goes to 2 and then straight to 4
    if (M.check2) and (not M.check3) and (M.check_point4_done) and (not M.cca_warning_message) and (not M.identify_message) and (not M.real_bad) then
        AudioMessage("misn1205.wav")
        -- your out of order scout - return to you posts
        ClearObjectives()
        AddObjective("misn1200.otf", "green")
        AddObjective("misn1201.otf", "green")
        AddObjective("misn1202.otf", "white")
        AddObjective("misn1203.otf", "yellow")
        AddObjective("misn1204.otf", "white")
        M.cca_warning_message = true
    end
    -- if he goes to 2 and then 4 and then back to 3 (recovers)
    if (M.check2) and (M.cca_warning_message) and (Distance(M.user, M.checkpoint3) < 70.0) and (not M.identify_message) and (not M.real_bad) and (not M.check4) then
        -- CR co-op layer >>
        local shot = CheckpointShotReady()
        -- CR co-op layer <<
        M.good2 = true
        if M.good2 then
            -- CR co-op layer >>
            if shot then
                CameraObject(M.user, 0, 700, - 1500, M.user)
                M.camera_time = GetTime() + 6.0
                M.shot_until = M.camera_time
            else
                M.good2_off = true
            end
            -- CR co-op layer <<
            AudioMessage("misn1210.wav")
            -- soviet guy should laugh "you better now"
            ClearObjectives()
            AddObjective("misn1200.otf", "green")
            AddObjective("misn1201.otf", "green")
            AddObjective("misn1202.otf", "green")
            AddObjective("misn1203.otf", "green")
            AddObjective("misn1204.otf", "white")
            M.better_message = true
            M.check4 = true
        end
    end
    -- if he goes to 2 and then 4 and then back to 2
    if (M.check2) and (M.cca_warning_message) and (not M.check4) and (M.check_point2_done) and (not M.identify_message) and (not M.real_bad) then
        AudioMessage("misn1206.wav")
        -- identify yourself!
        M.next_message_time = GetTime() + 20.0
        ClearObjectives()
        AddObjective("misn1200.otf", "green")
        AddObjective("misn1201.otf", "green")
        AddObjective("misn1202.otf", "white")
        AddObjective("misn1203.otf", "red")
        AddObjective("misn1204.otf", "white")
        M.identify_message = true
    end
    -- this is when he goes to 2 and then 4 and then 5
    if (M.check2) and (M.cca_warning_message) and (not M.check4) and (M.check_point5_done) and (not M.identify_message) and (not M.real_bad) and (not M.check4) then
        AudioMessage("misn1206.wav")
        -- identify yourself!
        M.next_message_time = GetTime() + 20.0
        ClearObjectives()
        AddObjective("misn1200.otf", "green")
        AddObjective("misn1201.otf", "green")
        AddObjective("misn1202.otf", "white")
        AddObjective("misn1203.otf", "yellow")
        AddObjective("misn1204.otf", "red")
        M.identify_message = true
    end
    -- if he goes to 2 and then straigh to 5
    if (M.check2) and (M.check_point5_done) and (not M.check3) and (not M.cca_warning_message) and (not M.identify_message) and (not M.real_bad) then
        AudioMessage("misn1206.wav")
        -- identify yourself!
        M.next_message_time = GetTime() + 20.0
        ClearObjectives()
        AddObjective("misn1200.otf", "green")
        AddObjective("misn1201.otf", "green")
        AddObjective("misn1202.otf", "white")
        AddObjective("misn1203.otf", "white")
        AddObjective("misn1204.otf", "yellow")
        M.identify_message = true
    end
    -- if he goes to 2 and then 3 and then 5
    if (M.check3) and (not M.check4) and (M.check_point5_done) and (not M.cca_warning_message) and (not M.identify_message) and (not M.real_bad) then
        AudioMessage("misn1206.wav")
        -- identify yourself!
        M.next_message_time = GetTime() + 20.0
        ClearObjectives()
        AddObjective("misn1200.otf", "green")
        AddObjective("misn1201.otf", "green")
        AddObjective("misn1202.otf", "green")
        AddObjective("misn1203.otf", "white")
        AddObjective("misn1204.otf", "yellow")
        M.identify_message = true
    end
    --/ the THREES
    -- if he goes to 3 before going to 2
    if (M.check_point3_done) and (not M.check2) and (not M.cca_warning_message) and (not M.identify_message) and (not M.better_message) and (not M.real_bad) then
        AudioMessage("misn1205.wav")
        -- your out of order scout - return to you posts
        ClearObjectives()
        AddObjective("misn1200.otf", "green")
        AddObjective("misn1201.otf", "white")
        AddObjective("misn1202.otf", "yellow")
        AddObjective("misn1203.otf", "white")
        AddObjective("misn1204.otf", "white")
        M.cca_warning_message = true
    end
    -- if he goes to 3 and then goes back to 2 (recovers)	
    if (not M.check2) and (M.cca_warning_message) and (not M.identify_message) and (Distance(M.user, M.checkpoint2) < 70.0) and (not M.better_message) then
        -- doing better 
        -- CR co-op layer >>
        local shot = CheckpointShotReady()
        -- CR co-op layer <<
        M.good1 = true
        if M.good1 then
            -- CR co-op layer >>
            if shot then
                CameraObject(M.user, 0, 700, - 1500, M.user)
                M.camera_time = GetTime() + 7.0
                M.shot_until = M.camera_time
            else
                M.good1_off = true
            end
            -- CR co-op layer <<
            AudioMessage("misn1210.wav")
            -- soviet guy should laugh "you better now"
            ClearObjectives()
            AddObjective("misn1200.otf", "green")
            AddObjective("misn1201.otf", "green")
            AddObjective("misn1202.otf", "green")
            AddObjective("misn1203.otf", "white")
            AddObjective("misn1204.otf", "white")
            M.better_message = true
        end
    end
    -- if he goes to 3 and then recovers to 2 then goes back to 3
    if (M.better_message) and (not M.check4) and (M.check_point3_done) and (not M.identify_message) and (not M.real_bad) then
        AudioMessage("misn1206.wav")
        -- identify yourself!
        M.next_message_time = GetTime() + 20.0
        ClearObjectives()
        AddObjective("misn1200.otf", "green")
        AddObjective("misn1201.otf", "green")
        AddObjective("misn1202.otf", "red")
        AddObjective("misn1203.otf", "white")
        AddObjective("misn1204.otf", "white")
        M.identify_message = true
    end
    -- if he goes to 3 and then recovers to 2 then goes to 5
    if (M.better_message) and (M.check_point5_done) and (not M.check4) and (not M.identify_message) and (not M.real_bad) then
        AudioMessage("misn1206.wav")
        -- identify yourself!
        M.next_message_time = GetTime() + 20.0
        ClearObjectives()
        AddObjective("misn1200.otf", "green")
        AddObjective("misn1201.otf", "green")
        AddObjective("misn1202.otf", "green")
        AddObjective("misn1203.otf", "white")
        AddObjective("misn1204.otf", "yellow")
        M.identify_message = true
    end
    -- if her goes to 3 and then to 4 without recovering
    if (not M.check2) and (M.check_point4_done) and (M.cca_warning_message) and (not M.better_message) and (not M.identify_message) and (not M.real_bad) then
        ClearObjectives()
        AddObjective("misn1200.otf", "green")
        AddObjective("misn1201.otf", "white")
        AddObjective("misn1202.otf", "yellow")
        AddObjective("misn1203.otf", "red")
        AddObjective("misn1204.otf", "white")
        M.real_bad = true
    end
    -- if her goes to 3 and then to 5 without recovering
    if (M.check_point5_done) and (M.cca_warning_message) and (not M.better_message) and (not M.identify_message) and (not M.real_bad) and (not M.check4) then
        ClearObjectives()
        AddObjective("misn1200.otf", "green")
        AddObjective("misn1201.otf", "white")
        AddObjective("misn1202.otf", "yellow")
        AddObjective("misn1203.otf", "white")
        AddObjective("misn1204.otf", "red")
        M.real_bad = true
    end
    -- if he goes to 3 and then recovers and then goes to 4
    if (M.better_message) and (Distance(M.user, M.checkpoint4) < 70.0) and (not M.identify_message) and (not M.real_bad) and (not M.check4) then
        -- CR co-op layer >>
        local shot = CheckpointShotReady()
        -- CR co-op layer <<
        M.good3 = true
        if M.good3 then
            -- CR co-op layer >>
            if shot then
                CameraObject(M.user, 0, 700, - 1500, M.user)
                M.camera_time = GetTime() + 6.0
                M.shot_until = M.camera_time
            else
                M.good3_off = true
            end
            -- CR co-op layer <<
            AudioMessage("misn1209.wav")
            -- soviet voice that is calm
            ClearObjectives()
            AddObjective("misn1200.otf", "green")
            AddObjective("misn1201.otf", "green")
            AddObjective("misn1202.otf", "green")
            AddObjective("misn1203.otf", "green")
            AddObjective("misn1204.otf", "white")
            M.check4 = true
        end
    end
    -- the FOURS
    --if he goes straight to 4
    if (M.check_point4_done) and (not M.check2) and (not M.cca_warning_message) and (not M.identify_message) and (not M.real_bad) then
        AudioMessage("misn1206.wav")
        -- identify yourself!
        M.next_message_time = GetTime() + 20.0
        ClearObjectives()
        AddObjective("misn1200.otf", "green")
        AddObjective("misn1201.otf", "white")
        AddObjective("misn1202.otf", "white")
        AddObjective("misn1203.otf", "yellow")
        AddObjective("misn1204.otf", "white")
        M.identify_message = true
    end
    -- the FIVES
    -- new line for ccacom_tower - this is what happens when the player reaches the ccacomtower
    --if he goes straight to 5
    if (M.check_point5_done) and (not M.cca_warning_message) and (not M.check2) and (not M.identify_message) and (not M.real_bad) and (not M.straight_to_5) then
        AudioMessage("misn1206.wav")
        -- identify yourself!
        M.next_message_time = GetTime() + 15.0
        ClearObjectives()
        AddObjective("misn1200.otf", "green")
        AddObjective("misn1201.otf", "white")
        AddObjective("misn1202.otf", "white")
        AddObjective("misn1203.otf", "white")
        AddObjective("misn1204.otf", "yellow")
        M.identify_message = true
        M.straight_to_5 = true
    end
    -- if he goes to 5 with some slip ups
    if (M.check_point5_done) and (M.cca_warning_message) and (M.check4) and (not M.identify_message) and (not M.real_bad) and (not M.final_warned) then
        AudioMessage("misn1214.wav")
        -- explain yourself!
        M.final_warning = GetTime() + 20.0
        ClearObjectives()
        AddObjective("misn1200.otf", "green")
        AddObjective("misn1201.otf", "green")
        AddObjective("misn1202.otf", "green")
        AddObjective("misn1203.otf", "green")
        AddObjective("misn1204.otf", "yellow")
        M.final_warned = true
    end
    -- if he does it exactly right	
    if (M.check_point5_done) and (M.check4) and (not M.cca_warning_message) and (not M.identify_message) and (not M.real_bad) and (not M.did_it_right) then
        AudioMessage("misn1205.wav")
        -- can we help you scout
        M.last_warning = GetTime() + 30.0
        ClearObjectives()
        AddObjective("misn1200.otf", "green")
        AddObjective("misn1201.otf", "green")
        AddObjective("misn1202.otf", "green")
        AddObjective("misn1203.otf", "green")
        AddObjective("misn1204.otf", "green")
        M.did_it_right = true
    end
    if (M.did_it_right) and (M.last_warning < GetTime()) and (not M.final_warned) then
        AudioMessage("misn1214.wav")
        -- explain yourself!
        M.final_warning = GetTime() + 20.0
        M.final_warned = true
    end
    -- these are constants /////////////////////////////////////////////////////////////////
    -- this defines what happens under "cca_warning_message" conditions (if he goes out of order and then dilly-dallys)
    if (M.cca_warning_message) and (not M.better_message) and (not M.check4) and (not M.identify_message) and (not M.last_warned) then
        M.last_warning = GetTime() + 100.0
        M.last_warned = true
    end
    if (M.last_warned) and (M.last_warning < GetTime()) and (not M.better_message) and (not M.check4) and (not M.final_warned) then
        AudioMessage("misn1214.wav")
        -- explain yourself!
        M.final_warning = GetTime() + 40.0
        M.final_warned = true
    end
    if (M.final_warned) and (M.final_warning < GetTime()) and (not M.identify_message) then
        AudioMessage("misn1206.wav")
        -- identify yourself!
        M.next_message_time = GetTime() + 10.0
        M.identify_message = true
    end
    -- this defines what happens under "identify_message" conditions (if he is warned and does not recover in time)
    if (M.identify_message) and (M.next_message_time < GetTime()) and (not M.real_bad) then
        M.real_bad = true
    end
    if (M.identify_message) and (not M.real_bad) then
        if M.check_point5_done then
            Follow(M.guard_tank1, M.user)
            Follow(M.guard_tank2, M.user)
        else
            Goto(M.guard_tank1, M.ccacom_tower)
            Goto(M.guard_tank2, M.ccacom_tower)
        end
    end
    -- this defines what happens under "real_bad" conditions
    if (M.real_bad) and (not M.discovered) then
        AudioMessage("misn1211.wav")
        if not M.interface_connect then
            ClearObjectives()
            AddObjective("misn1206.otf", "white")
        end
        SetPerceivedTeam(M.user, 1)
        M.guard1 = BuildObject("svtank", ENEMY_TEAM, M.spawn_point1)
        M.guard2 = BuildObject("svtank", ENEMY_TEAM, M.spawn_point1)
        M.guard3 = BuildObject("svtank", ENEMY_TEAM, M.spawn_point2)
        M.guard4 = BuildObject("svtank", ENEMY_TEAM, M.spawn_point2)
        Goto(M.parked_tank2, M.ccacom_tower)
        Goto(M.parked_tank1, M.ccacom_tower)
        Attack(M.guard1, TargetFor(M.guard1), 1)
        Attack(M.guard2, TargetFor(M.guard2), 1)
        Attack(M.guard3, TargetFor(M.guard3), 1)
        Attack(M.guard4, TargetFor(M.guard4), 1)
        Attack(M.patrol1_1, M.user, 1)
        Attack(M.patrol1_2, M.user, 1)
        Attack(M.patrol2_1, M.user, 1)
        Attack(M.patrol2_2, M.user, 1)
        --		Attack (patrol3_1, user, 1);
        --		Attack (patrol3_2, user, 1);
        M.discovered = true
    end
-- CR co-op layer >>
    if M.strict and M.real_bad and not M.interface_complete then CoverBlown() end
-- CR co-op layer <<
    if (M.discovered) and (not IsAlive(M.guard1)) and (not IsAlive(M.guard2)) and (not IsAlive(M.guard3)) then
        M.guard1 = BuildObject("svtank", ENEMY_TEAM, M.spawn_point1)
        M.guard2 = BuildObject("svtank", ENEMY_TEAM, M.spawn_point1)
        M.guard3 = BuildObject("svtank", ENEMY_TEAM, M.spawn_point2)
        M.guard4 = BuildObject("svtank", ENEMY_TEAM, M.spawn_point2)
        Attack(M.guard1, TargetFor(M.guard1), 1)
        Attack(M.guard2, TargetFor(M.guard2), 1)
        Attack(M.guard3, TargetFor(M.guard3), 1)
        Attack(M.guard4, TargetFor(M.guard4), 1)
        if not M.follow_spawn then
            if IsAlive(M.pturret1) then
                Goto(M.pturret1, "turret1_path")
            end
            if IsAlive(M.pturret6) then
                Goto(M.pturret6, "turret2_path")
            end
        end
    end
    -- this is what happens when the player gets a warning message
    if (M.cca_warning_message) and (not M.follow_spawn) then
        Goto(M.pturret1, "turret1_path")
        Goto(M.pturret6, "turret2_path")
        if (Distance(M.user, M.checkpoint4)) > (Distance(M.user, M.checkpoint3)) then
            -- he's at 3
            M.follower = BuildObject("svfigh", ENEMY_TEAM, "3spawn")
            Follow(M.follower, M.user)
        else
            M.follower = BuildObject("svfigh", ENEMY_TEAM, "4spawn")
            Follow(M.follower, M.user)
        end
        M.follow_spawn = true
    end
    -- this is what happens when the player interfaces with the ccacomtower
    if (Distance(M.user, M.ccacom_tower) < 60.0) and (not M.interface_connect) and (not M.interface_complete) then
        AudioMessage("misn1201.wav")
        --uplink sound
        M.interface_connect = true
        M.interface_time = GetTime() + 45.0
    end
    if (Distance(M.user, M.ccacom_tower) > 75.0) and (M.interface_connect) and (not M.interface_complete) and (not M.warning_message) then
        AudioMessage("misn1202.wav")
        -- loosing data uplink
        M.warning_repeat_time = GetTime() + 5.0
        M.warning_message = true
    end
    if (M.warning_message) and (Distance(M.user, M.ccacom_tower) > 75.0) and (M.warning_repeat_time < GetTime()) and (M.interface_connect) then
        M.warning_message = false
    end
    if (M.warning_message) and (Distance(M.user, M.ccacom_tower) < 75.0) and (M.interface_connect) then
        M.warning_message = false
    end
    if (M.interface_connect) and (Distance(M.user, M.ccacom_tower) > 85.0) and (not M.interface_complete) then
        AudioMessage("misn1203.wav")
        -- interface broken
        M.interface_connect = false
    end
    if (M.interface_connect) and (M.interface_time < GetTime()) and (not M.interface_complete) then
        AudioMessage("misn1204.wav")
        -- interface complete
-- CR co-op layer >>
        Broadcast(function()
-- CR co-op layer <<
        ClearObjectives()
        AddObjective("misn1205.otf", "white")
-- CR co-op layer >>
        end)
-- CR co-op layer <<
        M.win_check_time = GetTime() + 120.0
        StopCockpitTimer()
        HideCockpitTimer()
        AudioMessage("misn1223.wav")
        -- get back to nav 1
        M.interface_complete = true
    end
    if (M.interface_connect) and (not M.interface_complete) and (not M.noise) then
        AudioMessage("misn1212.wav")
        M.next_noise_time = GetTime() + 3.0
        M.noise = true
    end
    if (M.interface_connect) and (not M.interface_complete) and (M.noise) and (M.next_noise_time < GetTime()) then
        M.noise = false
    end
    -- this is the Nav camera code
    if M.key_captured then
        if ((IsInfo("sbhqt1") == true) or (IsInfo("sbhqt2") == true)) and ((not M.camera_swap1) or (not M.camera_swap2)) then
            if (Distance(M.user, M.center) < 100.0) then
                --			if (IsAlive(center_cam))
                --			{
                --				RemoveObject(center_cam);
                --			}
                if IsAlive(M.start_cam) then
                    SetTeamNum(M.start_cam, 1)
                    --					RemoveObject(start_cam);
                end
                if IsAlive(M.check2_cam) then
                    SetTeamNum(M.check2_cam, 1)
                    --					RemoveObject(check2_cam);
                end
                if IsAlive(M.check3_cam) then
                    SetTeamNum(M.check3_cam, 1)
                    --					RemoveObject(check3_cam);
                end
                if IsAlive(M.check4_cam) then
                    SetTeamNum(M.check4_cam, 1)
                    --					RemoveObject(check4_cam);
                end
                if IsAlive(M.goal_cam) then
                    SetTeamNum(M.goal_cam, 1)
                    --					RemoveObject(goal_cam);
                end
                --			center_cam = BuildObject ("apcamr", 1, "center_cam");
                --				start_cam = BuildObject ("apcamr", 1, "start_cam");
                -- Port safety: validate the object before the native SetName equivalent;
                -- missing/deleted camera pods are skipped without changing mission flags or timing.
                if IsValid(M.start_cam) then
                    SetObjectiveName(M.start_cam, "Check Point")
                end
                --				check2_cam = BuildObject ("apcamr", 1, "check2_cam");
                -- Port safety: validate the object before the native SetName equivalent;
                -- missing/deleted camera pods are skipped without changing mission flags or timing.
                if IsValid(M.check2_cam) then
                    SetObjectiveName(M.check2_cam, "Check Point")
                end
                --				check3_cam = BuildObject ("apcamr", 1, "check3_cam");
                -- Port safety: validate the object before the native SetName equivalent;
                -- missing/deleted camera pods are skipped without changing mission flags or timing.
                if IsValid(M.check3_cam) then
                    SetObjectiveName(M.check3_cam, "Check Point")
                end
                --				check4_cam = BuildObject ("apcamr", 1, "check4_cam");
                -- Port safety: validate the object before the native SetName equivalent;
                -- missing/deleted camera pods are skipped without changing mission flags or timing.
                if IsValid(M.check4_cam) then
                    SetObjectiveName(M.check4_cam, "Check Point")
                end
                --				goal_cam = BuildObject ("apcamr", 1, "goal_cam");
                M.swap_check = GetTime() + 1.0
                M.camera_swap1 = true
                M.camera_swap_back = false
            end
            if (Distance(M.user, M.checkpoint1) < 100.0) then
                if IsAlive(M.center_cam) then
                    SetTeamNum(M.center_cam, 1)
                    --					RemoveObject(center_cam);
                end
                --			if (IsAlive(start_cam))
                --			{
                --				RemoveObject(start_cam);
                --			}
                --[==[			if (IsAlive(check2_cam))
				{
					RemoveObject(check2_cam);
				}
				if (IsAlive(check3_cam))
				{
					RemoveObject(check3_cam);
				}
				if (IsAlive(check4_cam))
				{
					RemoveObject(check4_cam);
				}
				if (IsAlive(goal_cam))
				{
					RemoveObject(goal_cam);
				}
	]==]
                --				center_cam = BuildObject ("apcamr", 1, "center_cam");
                --			start_cam = BuildObject ("apcamr", 1, "start_cam");
                --			check2_cam = BuildObject ("apcamr", 1, "check2_cam");
                --			check3_cam = BuildObject ("apcamr", 1, "check3_cam");
                --			check4_cam = BuildObject ("apcamr", 1, "check4_cam");
                --			goal_cam = BuildObject ("apcamr", 1, "goal_cam");
                M.swap_check = GetTime() + 1.0
                M.camera_swap2 = true
                M.camera_swap_back = false
            end
        end
    end
-- CR co-op layer >>
    RecordExposure(entry)
-- CR co-op layer <<
end
local function UpdateUplinkAftermath()
    if (M.interface_complete) and (not M.discovered) then
        if IsAlive(M.patrol1_1) then
            Attack(M.patrol1_1, TargetFor(M.patrol1_1))
        end
        if IsAlive(M.patrol1_2) then
            Attack(M.patrol1_2, TargetFor(M.patrol1_2))
        end
        if IsAlive(M.patrol2_1) then
            Attack(M.patrol2_1, TargetFor(M.patrol2_1))
        end
        if IsAlive(M.patrol2_2) then
            Attack(M.patrol2_2, TargetFor(M.patrol2_2))
        end
        if IsAlive(M.patrol3_1) then
            Attack(M.patrol3_1, TargetFor(M.patrol3_1))
        end
        if IsAlive(M.patrol3_2) then
            Attack(M.patrol3_2, TargetFor(M.patrol3_2))
        end
        if IsAlive(M.patrol4_1) then
            Attack(M.patrol4_1, TargetFor(M.patrol4_1))
        end
        if IsAlive(M.patrol4_2) then
            Attack(M.patrol4_2, TargetFor(M.patrol4_2))
        end
        if IsAlive(M.guard_tank1) then
            Attack(M.guard_tank1, TargetFor(M.guard_tank1))
        end
        if IsAlive(M.guard_tank2) then
            Attack(M.guard_tank2, TargetFor(M.guard_tank2))
        end
        M.discovered = true
-- CR scaling >>
        BuildHunters()
-- CR scaling <<
    end
end
local function UpdateSwapBack()
    if ((M.camera_swap1) or (M.camera_swap2)) and (not M.camera_noise) then
        AudioMessage("misn1229.wav")
        M.camera_noise = true
    end
    if (not M.camera_swap_back) and (M.swap_check < GetTime()) and ((M.camera_swap1) or (M.camera_swap2)) then
        M.swap_check = GetTime() + 1.0
        if (M.camera_swap1) and (AllHumansBeyond(M.center, 300.0)) then
            AudioMessage("misn1230.wav")
            --			if (IsAlive(center_cam))
            --			{
            --				RemoveObject(center_cam);
            --			}
            if IsAlive(M.start_cam) then
                SetTeamNum(M.start_cam, HIDDEN_TEAM)
                --				RemoveObject(start_cam);
            end
            if IsAlive(M.check2_cam) then
                SetTeamNum(M.check2_cam, HIDDEN_TEAM)
                --				RemoveObject(check2_cam);
            end
            if IsAlive(M.check3_cam) then
                SetTeamNum(M.check3_cam, HIDDEN_TEAM)
                --				RemoveObject(check3_cam);
            end
            if IsAlive(M.check4_cam) then
                SetTeamNum(M.check4_cam, HIDDEN_TEAM)
                --				RemoveObject(check4_cam);
            end
            if IsAlive(M.goal_cam) then
                SetTeamNum(M.goal_cam, HIDDEN_TEAM)
                --				RemoveObject(goal_cam);
            end
            --			center_cam = BuildObject ("apcamr", 3, "center_cam");
            --			start_cam = BuildObject ("apcamr", 3, "start_cam");
            --			check2_cam = BuildObject ("apcamr", 3, "check2_cam");
            --			check3_cam = BuildObject ("apcamr", 3, "check3_cam");
            --			check4_cam = BuildObject ("apcamr", 3, "check4_cam");
            --			goal_cam = BuildObject ("apcamr", 3, "goal_cam");
            M.swap_check = 99999.0
            M.camera_swap1 = false
            M.camera_noise = false
            M.camera_swap_back = true
        end
        if (M.camera_swap2) and (AllHumansBeyond(M.checkpoint1, 300.0)) then
            AudioMessage("misn1230.wav")
            if IsAlive(M.center_cam) then
                SetTeamNum(M.center_cam, HIDDEN_TEAM)
                --				RemoveObject(center_cam);
            end
            --			if (IsAlive(start_cam))
            --			{
            --				RemoveObject(start_cam);
            --			}
            --			if (IsAlive(check2_cam))
            --[==[			{
				RemoveObject(check2_cam);
			}
			if (IsAlive(check3_cam))
			{
				RemoveObject(check3_cam);
			}
			if (IsAlive(check4_cam))
			{
				RemoveObject(check4_cam);
			}
			if (IsAlive(goal_cam))
			{
				RemoveObject(goal_cam);
			}
]==]
            --			center_cam = BuildObject ("apcamr", 3, "center_cam");
            --			start_cam = BuildObject ("apcamr", 3, "start_cam");
            --			check2_cam = BuildObject ("apcamr", 3, "check2_cam");
            --			check3_cam = BuildObject ("apcamr", 3, "check3_cam");
            --			check4_cam = BuildObject ("apcamr", 3, "check4_cam");
            --			goal_cam = BuildObject ("apcamr", 3, "goal_cam");
            M.swap_check = 99999.0
            M.camera_swap2 = false
            M.camera_noise = false
            M.camera_swap_back = true
        end
    end
end
local function UpdateEnd()
    --/////////////////// THIS MARKS THE END OF GAME BLOWN //////////////////////////////////////
    -- win condition
    if (M.game_blown) and (not M.game_over) then
        FailMission(GetTime() + 10.0)
        M.game_over = true
    end
    if (M.interface_complete) and (M.win_check_time < GetTime()) then
        M.win_check_time = GetTime() + 5.0
        if AllHumansArrived(M.nav1, 75.0) and (not M.win) then
            AudioMessage("misn1216.wav")
            SucceedMission(GetTime() + 7.0, "misn12w1.des")
            M.win = true
        end
    end
    if (not M.interface_complete) and (GetCockpitTimer() == 0) and (not M.game_over) then
        AudioMessage("misn1215.wav")
        FailMission(GetTime() + 15.0, "misn12f1.des")
        M.game_over = true
    end
    -- END OF SCRIPT
end
function Update(dt)
-- CR co-op layer >>
    subtit.Update()
    CRCoop.Update()
    UpdatePresentationTransport()
    if M.coopResult then
-- CR co-op layer <<
-- CR Europa weather >>
        -- The sky keeps easing while the result screen counts down.
        UpdateEuropaWeather(dt)
-- CR Europa weather <<
-- CR co-op layer >>
        return
    end
    if CRCoop.IsNetworkGame() then
        if CRCoop.HasLeaderDeparted() then
            M.coopResult = true
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
-- CR co-op layer <<
-- CR Europa weather >>
    UpdateEuropaWeather(dt)
-- CR Europa weather <<
-- CR co-op layer >>
    if not CRCoop.IsAuthority() then return end
    if CRCoop.IsNetworkGame() and not M.coopBootstrapped then
        M.coopBootstrapped = true
        -- The authored offline placeholder must not remain beside the humans.
        local offlinePlayer = GetHandle("player0_hover")
        if IsValid(offlinePlayer) and not CRCoop.IsHumanCraft(offlinePlayer) then RemoveObject(offlinePlayer) end
    end
-- CR co-op layer <<
    -- START OF SCRIPT
    M.user = GetPlayerHandle()
    --assigns the player a handle every frame
    UpdateStart()
    -- this what happens if the player is discovered before taking over the ship
    ForEachHuman(UpdateBlownTank)
    ForEachSlot(UpdateBlownKeyShip)
    -- this is what happens is the player tries to get in with his tank
    ForEachHuman(UpdateBlownTankNearCheckpoint)
    -- this is game_blown code
    UpdateDeathSquad()
    ForEachHuman(UpdateDeadMeat)
    -- this is the start of the camera during the players briefing
    UpdateOpening()
    -- this is the start of patroling the cca ships
    UpdatePatrols()
    --//////////// THIS ALL FALLS UNDER GAME BLOWN /////////////////////////////////////
    if not M.game_blown then
        ForEachSlot(UpdateKeyCycle)
        ForEachHuman(UpdateCapture)
        UpdateMovie()
        ForEachHuman(UpdateProgress)
        UpdateUplinkAftermath()
        UpdateSwapBack()
    end
    --/////////////////// THIS MARKS THE END OF GAME BLOWN //////////////////////////////////////
-- CR Razor One >>
    UpdateRazor()
-- CR Razor One <<
-- CR artillery >>
    UpdateArtillery()
-- CR artillery <<
    UpdateEnd()
-- CR Europa weather >>
    if CRCoop.IsAuthority() then UpdateEuropaBeats() end
-- CR Europa weather <<
end
function Save()
-- CR Europa weather >>
    if europaStarted and ((not CRCoop.IsNetworkGame()) or CRCoop.IsAuthority()) then
        M.weatherState = CREuropaWeather.Save()
    end
-- CR Europa weather <<
    return M
end

function Load(state)
-- CR Europa weather >>
    ShutdownEuropaWeather()
    if Environment.InvalidateRenderer then Environment.InvalidateRenderer() end
-- CR Europa weather <<
    M = state
end
