-- misn09: faithful BZ1 DLL source port for Battlezone 98 Redux / Lua 5.1, with the shared
-- offline + 2-4 player co-op layer of the misn06/07/08 ports (Docs/MISN09_COOP.md).
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misn09Mission.cpp.
-- Source blob: 888ee877b4b56348ddf3e9717f01aed95fc0f066.
-- Disabled C++ stays inactive at its original location; the complete verbatim
-- source/header, including serialization comments, is in References/Misn09Source/.
-- Everything the campaign adds lives between "-- CR ... >>" / "-- CR ... <<" marker lines
-- (Tools/Test-Misn09SourceParity.py strips them); each co-op substitution outside the markers
-- is an explicit API-count delta in that test. Offline play reproduces the DLL; only the
-- leader runs the mission body. Requires the stock misn09 map labels, paths, AIPs, OTF/audio.

local function NewState()
    local state = {}
    state.start_done = false
    state.convoy_started = false
    state.camera_ready = false
    state.camera_artil = false
    state.build_new_tug = false
    state.tug_done = false
    state.objective1 = false
    state.first_warning = false
    state.second_warning = false
    state.third_warning = false
    state.player_dead = false
    state.muf_contact = false
    state.muf_moving = false
    state.post1 = false
    state.post2 = false
    state.post3 = false
    state.post4 = false
    state.guard1 = false
    state.guard2 = false
    state.turret1_set = false
    state.turret2_set = false
    state.turret3_set = false
    state.turret4_set = false
    state.get_relic = false
    state.relic_secure = false
    state.relic_seized = false
    state.relic_free = false
    state.tug_underway = false
    state.head_4_pad = false
    state.game_over = false
    state.next_shot = false
    state.player_camera_off = false
    state.next_shot_message = false
    state.cam1_on = false
    state.cam2_on = false
    state.cam3_on = false
    state.cam4_on = false
    state.cam5_on = false
    state.cam_off = false
    state.convoy_cam_ready = false
    state.convoy_cam_off = false
    state.muf_deployed = false
    state.scavs_alive = false
    state.charon_found = false
    state.charon_build = false
    state.start = false
    state.opening_vo = false
    state.muf_gobaby = false
    state.recon_artil = false
    state.base_warning = false
    state.muf_deployed_good = false
    state.ccadead = false
    state.start_camera1 = false
    state.game_over5 = false
    state.start_convoy_time = 99999.0
    state.camera_ready_time = 99999.0
    state.build_tug_time = 99999.0
    state.first_warning_time = 99999.0
    state.second_warning_time = 99999.0
    state.third_warning_time = 99999.0
    state.camera_on_time = 99999.0
    state.muf_check = 99999.0
    state.movie_time = 99999.0
    state.unit_check = 99999.0
    state.turret1_time = 99999.0
    state.turret2_time = 99999.0
    state.turret3_time = 99999.0
    state.turret4_time = 99999.0
    state.win_check = 99999.0
    state.atril_check = 99999.0
    state.player_camera_time = 99999.0
    state.next_shot_time = 99999.0
    state.cam1_time = 99999.0
    state.cam2_time = 99999.0
    state.cam3_time = 99999.0
    state.cam4_time = 99999.0
    state.cam5_time = 99999.0
    state.convoy_cam_time = 99999.0
    state.deploy_check = 99999.0
    state.charon_check = 99999.0
    state.start_time = 99999.0
    state.recon_message_time = 99999.0
    state.user = nil
    state.relic = nil
    state.nav1 = nil
    state.charon = nil
    state.avsilo = nil
    state.key_scrap = nil
    state.ccatug = nil
    state.nsdftug = nil
    state.convoy_geyser = nil
    state.cut_off_geyser = nil
    state.ccaturret1 = nil
    state.ccaturret2 = nil
    state.ccaturret3 = nil
    state.ccaturret4 = nil
    state.ccaturret5 = nil
    state.ccaturret6 = nil
    state.ccarecycle = nil
    state.ccamuf = nil
    state.ccaarmor = nil
    state.ccalaunch = nil
    state.cca1 = nil
    state.cca2 = nil
    state.cca3 = nil
    state.cca4 = nil
    state.cca5 = nil
    state.cca6 = nil
    state.cca7 = nil
    state.cca8 = nil
    state.cca9 = nil
    state.cca0 = nil
    state.scav1 = nil
    state.scav2 = nil
    state.scav3 = nil
    state.nsdfrecycle = nil
    state.nsdfmuf = nil
    state.avscav1 = nil
    state.avscav2 = nil
    state.avscav3 = nil
    state.nsdfgech1 = nil
    state.construct = nil
    state.nsdfslf = nil
    state.nsdfrig = nil
    state.tugger = nil
    state.convoy1 = nil
    state.convoy2 = nil
    state.convoy3 = nil
    state.convoy4 = nil
    state.convoy5 = nil
    state.convoy6 = nil
    state.convoy7 = nil
    state.convoy8 = nil
    state.convoy9 = nil
    state.convoy0 = nil
    state.charon_nav = nil
    state.stuff = 0
    state.x = 0
    state.y = 0
    state.scrap = 0
    state.audmsg = nil
    return state
end
local M = NewState()

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})
local exu = require("exu")
-- Native MultST Init precedes Start. The authored base is the team-1 Unit Factory (avmuf) and
-- its convoy, so no human team keeps a starting recycler.
if type(IsNetGame) == "function" and IsNetGame() then
    assert(exu.DisableStartingRecycler and exu.GetMyNetID,
        "misn09 co-op requires the bundled EXU multiplayer hooks")
    exu.DisableStartingRecycler()
end
local subtit = require("ScriptSubtitles")
local CRCoop = require("CRCoop")
local LEADER_TEAM, ENEMY_TEAM, SUPPORT_TEAM = 1, 5, 7
-- The DLL built the relic (obdata) on team 3, which is a guest slot in co-op. Neutral (0) keeps it
-- off every human team and off the CCA's target lists, and a tug's cargo does not depend on its team.
local RELIC_TEAM = 0
-- CR Venus weather >>
local CRVenusWeather = require("CRVenusWeather")
local VenusSites = require("CRVenusSites09")
local Environment = require("Environment")
local VENUS_OPS = { VenusState = true, VenusStrike = true, VenusErupt = true }
-- CR Venus weather <<
-- CR convoy scaling >>
-- The DLL's convoy (4 svfigh, 4 svtank, 2 svapc and the tug) is for one player. Each extra
-- human team adds one svtank and one svfigh, up to this many extras (four players).
local CONVOY_EXTRA_MAX = 3
-- CR convoy scaling <<
-- CR Prescott platoon >>
-- misn0901/misn0903 have Commander Prescott flushing the convoy out and sealing its retreat.
-- When the convoy's lead is this close to the cutoff geyser the players get PRESCOTT_DELAY_S of
-- first crack, then an allied avtank platoon (team 7) spawns PRESCOTT_BEHIND_M behind the convoy's
-- rearmost living unit, along its route, and hunts its combat units. Solo it is PRESCOTT_BASE tanks,
-- +1 per extra human, max PRESCOTT_MAX. The tanks are spread PRESCOTT_SPREAD_M apart sideways.
local PRESCOTT_TRIGGER_M, PRESCOTT_DELAY_S, PRESCOTT_RETARGET_S = 350.0, 45.0, 4.0
local PRESCOTT_BASE, PRESCOTT_MAX = 3, 5
local PRESCOTT_BEHIND_M = 250
local PRESCOTT_SPREAD_M = 20.0
local CONVOY_ROUTE = "soviet_path"
-- CR Prescott platoon <<
-- CR cut VO >>
-- Restored cut radio: misn0917 when a human combat unit leaves the Unit Factory before the
-- artillery is down, misn0910 when a walker is built farther than WALKER_FAR_M from the cutoff geyser.
local FACTORY_BUILD_RADIUS_M, WALKER_FAR_M = 120.0, 600.0
local FACTORY_COMBAT_ODFS = { "avtank", "avltnk", "avrckt", "avhraz", "avartl", "avfigh", "avwalk" }
-- CR cut VO <<
-- CR tug rebuild >>
-- The DLL's cut replacement-tug block, restored: the CCA factory (svmuf) builds a new svhaul.
local TUG_REBUILD_DELAY_S, TUG_REBUILD_MAX = 90.0, 2
-- CR tug rebuild <<

-- Co-op presentation uses the established misn03/misn05 E/A and C transport.
-- Only the campaign leader runs the mission body below; HUD/audio/removal/timer/
-- end calls are explicitly delivered to every peer.
-- E/A are an ordered, acknowledged event stream (eight small packets in flight,
-- retried every 0.2s). C is a replaceable camera snapshot carrying a kind: "P"
-- (CameraPath), "O" (CameraObject) or "" (no camera). I relays a guest's native
-- IsInfo selection state to the leader. No tables go on wire.
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
local nativeIsInfo = IsInfo
local events, acknowledgements = {}, {}
local receivedEvent = 0
local pendingSeq, pendingSince
local nextEventSend, nextCameraSend = 0, 0
local cameraFrame, cameraGeneration, cameraSerial = nil, 0, 0
local remoteCameraSerial, localCameraGeneration = 0, 0
local cameraSkipped, localCameraActive = false, false
local remoteCamera
local cameraWaitSince, cameraGaveUp, cameraLast
-- IsInfo is local UI state (the selected object's info panel). Guests relay
-- the prefix this mission reads (the Charon scan); the leader honours a report for 1 s.
local INFO_PREFIXES = { "hbchar" }
local isInfoPrefix = {}
for _, prefix in ipairs(INFO_PREFIXES) do isInfoPrefix[prefix] = true end
local remoteInfo, nextInfoSend = {}, 0

local function ResetPresentation()
    events, acknowledgements, receivedEvent = {}, {}, 0
    pendingSeq, pendingSince = nil, nil
    nextEventSend, nextCameraSend = 0, 0
    cameraFrame, cameraGeneration, cameraSerial = nil, 0, 0
    remoteCamera, remoteCameraSerial, localCameraGeneration = nil, 0, 0
    cameraWaitSince, cameraGaveUp, cameraLast = nil, false, nil
    cameraSkipped, localCameraActive = false, false
    remoteInfo, nextInfoSend = {}, 0
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
    elseif op == "Label" then
        local handle, label = ...
        if type(SetLabel) == "function" and IsValid(handle) and type(label) == "string" then
            pcall(SetLabel, handle, label)
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
local labelSerial, announced = 0, {}
-- Targets a guest already gave up on (logged once): later events for them skip at once.
local gaveUp = {}

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
        n = 2, ttl = RESOLVE_TIMEOUT, handle = handle }
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
    if CRCoop.IsNetworkGame() then
        if not CRCoop.IsAuthority() then return end
        local wire, handle = { ... }, nil
        if HANDLE_OPS[op] and wire[1] ~= nil then handle = wire[1]; wire[1] = WireHandle(handle) end
        events[#events + 1] = { op = op, args = wire, n = select("#", ...), ttl = RESOLVE_TIMEOUT,
            handle = handle }
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

-- Guests report which of the two IsInfo prefixes their own UI currently shows.
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
                    Send(id, "E", seq, event.op, event.ttl, unpackArgs(EventArgs(event), 1, event.n))
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
            remoteInfo[prefix] = GetTime()
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
    local seq, op, ttl = ...
    if type(seq) ~= "number" or type(op) ~= "string" or type(ttl) ~= "number" then return true end
    if seq == receivedEvent + 1 and (native[op] or VENUS_OPS[op] or op == "Label" or op == "Resources") then
        local args = { select(4, ...) }
        local count = select("#", ...) - 3
        local apply, unresolved = true, false
        if HANDLE_OPS[op] then
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

-- Leader: native IsInfo OR a guest report within the last second.
local function IsInfo(prefix)
    if nativeIsInfo(prefix) then return true end
    local reported = remoteInfo[prefix]
    return reported ~= nil and GetTime() - reported <= 1.0
end

-- Presentation adapter ends. BuildObject invokes AddObject synchronously.

-- CR Venus weather >>
-- Victory eases the storm back to clear while the result screen counts down. EndMission has
-- already queued the result; this only nudges the director (leader/offline).
local presentSucceed = SucceedMission
local function SucceedMission(...)
    if (not M.venusCalm) and ((not CRCoop.IsNetworkGame()) or CRCoop.IsAuthority()) then
        M.venusCalm = true
        CRVenusWeather.SetTargetLevel(1)
    end
    return presentSucceed(...)
end
-- CR Venus weather <<

-- The DLL's AudioMessage(file) is the shared radio line: the leader plays it and every peer hears
-- it with its subtitle (Play returns the native audio handle on the leader, nil offline-safe).
local function AudioMessage(file) return subtit.Play(file) end


-- Native null/removed objects do not satisfy proximity checks. Avoid passing
-- nil through stock Lua's overloaded GetDistance handle/path interface.
local function Distance(from, to)
    if from == nil or from == 0 or not IsValid(from) then return math.huge end
    if to == nil or to == 0 then return math.huge end
    if type(to) ~= "string" and not IsValid(to) then return math.huge end
    return GetDistance(from, to)
end

local function IsOdfBase(h, name)
    return IsValid(h) and (IsOdf(h, name) or IsOdf(h, name .. ".odf"))
end

-- Native audmsg=0 meant no audio. Lua messages are userdata or nil.
local function AudioDone(message)
    return message == nil or IsAudioMessageDone(message)
end
local function StopAudio(message)
    if message ~= nil then StopAudioMessage(message) end
end

local function ConfigureAlliances()
    CRCoop.ApplyCoopAlliances(ENEMY_TEAM)
    for team = 1, 4 do
        Ally(team, SUPPORT_TEAM); Ally(SUPPORT_TEAM, team)
    end
    UnAlly(ENEMY_TEAM, SUPPORT_TEAM); UnAlly(SUPPORT_TEAM, ENEMY_TEAM)
end

-- Co-op trigger helpers. Offline CRCoop iterates just the local player, so each
-- reproduces the DLL's single-player test exactly. Every distance goes through
-- the mission's Distance guard (never raw GetDistance).
local function AnyPlayerWithin(target, distance)
    return CRCoop.AnyPlayerSatisfies(function(h) return Distance(h, target) < distance end)
end

-- True when every present player is farther than `distance` from `target`.
local function NoPlayerWithin(target, distance)
    local clear = true
    CRCoop.ForEachPlayerHandle(function(h)
        if not (Distance(h, target) > distance) then clear = false end
    end)
    return clear
end

-- Human teams in the session (1 offline): the way misn07/misn08 size their reinforcements.
local function HumanCount()
    return CRCoop.ForEachHumanTeam(function() end)
end

-- CR team filter >>
-- The DLL's AddObject had no team filter. The CCA's units (turrets, fighters, tanks,
-- scavengers, the tug) must be team 5 and the walker and silo any human team's, so an
-- allied or spawned look-alike never takes a tracked slot.
local ENEMY_TRACKED = { "svturr", "svfigh", "svtank", "svscav", "svhaul" }
local HUMAN_TRACKED = { "avwalk", "absilo" }
local function AddObjectTeamAllowed(h)
    if not IsValid(h) then return false end
    local team = GetTeamNum(h)
    for _, odf in ipairs(ENEMY_TRACKED) do
        if IsOdfBase(h, odf) then return team == ENEMY_TEAM end
    end
    for _, odf in ipairs(HUMAN_TRACKED) do
        if IsOdfBase(h, odf) then return CRCoop.IsHumanTeam(team) end
    end
    return true
end
-- CR team filter <<

-- CR convoy scaling >>
local function ConvoyExtraCount()
    return math.min(CONVOY_EXTRA_MAX, math.max(0, HumanCount() - 1))
end

-- One svtank and one svfigh per extra human, from the same spawn paths as the DLL's convoy.
local function SpawnConvoyExtras()
    local list = {}
    for _ = 1, ConvoyExtraCount() do
        local tank = BuildObject("svtank", ENEMY_TEAM, "spawn4")
        local fighter = BuildObject("svfigh", ENEMY_TEAM, "spawn2")
        Defend(tank)
        Defend(fighter)
        list[#list + 1] = tank
        list[#list + 1] = fighter
    end
    return list
end

local function FollowConvoyExtras()
    for _, unit in ipairs(M.convoy_extra or {}) do
        if IsAlive(unit) then Follow(unit, M.ccatug) end
    end
end

-- The convoy's armed escort: the DLL's four svfigh and four svtank plus the extras. The two
-- svapc and the tug are not combat units.
local function ConvoyCombatUnits()
    local list = {}
    for _, unit in ipairs({ M.convoy1, M.convoy2, M.convoy3, M.convoy4, M.convoy5, M.convoy6, M.convoy7, M.convoy8 }) do
        if unit ~= nil and IsAlive(unit) then list[#list + 1] = unit end
    end
    for _, unit in ipairs(M.convoy_extra or {}) do
        if IsAlive(unit) then list[#list + 1] = unit end
    end
    return list
end
-- CR convoy scaling <<

-- CR Prescott platoon >>
local function PrescottCount()
    return math.min(PRESCOTT_MAX, PRESCOTT_BASE + math.max(0, HumanCount() - 1))
end

local function ConvoyLead()
    if IsAlive(M.ccatug) then return M.ccatug end
    return ConvoyCombatUnits()[1]
end

local function NearestConvoyTarget(from)
    local best, bestDistance = nil, math.huge
    for _, target in ipairs(ConvoyCombatUnits()) do
        local distance = Distance(from, target)
        if best == nil or distance < bestDistance then best, bestDistance = target, distance end
    end
    return best
end

-- Orders only ever name a convoy combat unit: never the tug (it may carry the relic) and
-- never the launch pad. Independence 0 keeps them from picking their own targets.
local function OrderPrescott(platoon)
    platoon.next = GetTime() + PRESCOTT_RETARGET_S
    for index, unit in ipairs(platoon.units) do
        if IsAlive(unit) then
            local target = NearestConvoyTarget(unit)
            if target ~= nil then
                if platoon.orders[index] ~= target then
                    Attack(unit, target, 1)
                    platoon.orders[index] = target
                end
            elseif platoon.orders[index] ~= false then
                Stop(unit, 0)
                platoon.orders[index] = false
            end
        end
    end
end

-- Every living unit of the convoy: tug, escort, APCs and the scaling extras.
local function LivingConvoyUnits()
    local list = ConvoyCombatUnits()
    for _, unit in ipairs({ M.ccatug, M.convoy9, M.convoy0 }) do
        if unit ~= nil and IsAlive(unit) then list[#list + 1] = unit end
    end
    return list
end

local function PlanarDistance(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

-- The rearmost living convoy unit is the one farthest from the cutoff geyser.
local function RearConvoyUnit()
    local geyser = GetPosition(M.cut_off_geyser)
    local rear, rearDistance = nil, -1
    for _, unit in ipairs(LivingConvoyUnits()) do
        local distance = PlanarDistance(GetPosition(unit), geyser)
        if distance > rearDistance then rear, rearDistance = unit, distance end
    end
    return rear
end

-- Returns x, z and a unit travel direction (x, z) for the point PRESCOTT_BEHIND_M back along the
-- convoy's route from the path point nearest the rear unit, or nil when the path is unusable.
local function PointBehindOnRoute(rearPos)
    if type(GetPathPointCount) ~= "function" then return nil end
    local ok, count = pcall(GetPathPointCount, CONVOY_ROUTE)
    if not ok or type(count) ~= "number" or count < 2 then return nil end
    local points = {}
    for i = 0, count - 1 do
        local okPoint, p = pcall(GetPosition, CONVOY_ROUTE, i)
        if not okPoint or type(p) ~= "table" or type(p.x) ~= "number" then return nil end
        points[i] = p
    end
    local nearest, nearestDistance = 0, math.huge
    for i = 0, count - 1 do
        local distance = PlanarDistance(points[i], rearPos)
        if distance < nearestDistance then nearest, nearestDistance = i, distance end
    end
    local remaining, j = PRESCOTT_BEHIND_M, nearest
    while j > 0 do
        local from, back = points[j], points[j - 1]
        local segment = PlanarDistance(from, back)
        if segment >= remaining and segment > 0 then
            local t = remaining / segment
            return from.x + (back.x - from.x) * t, from.z + (back.z - from.z) * t,
                (from.x - back.x) / segment, (from.z - back.z) / segment
        end
        remaining = remaining - segment
        j = j - 1
    end
    -- Ran off the start of the route: extend backwards along its first leg.
    local first, second = points[0], points[1]
    local segment = PlanarDistance(first, second)
    if segment <= 0 then return nil end
    local dx, dz = (second.x - first.x) / segment, (second.z - first.z) / segment
    return first.x - dx * remaining, first.z - dz * remaining, dx, dz
end

local function PrescottSpawnPoint(rear)
    local rearPos = GetPosition(rear)
    local x, z, dx, dz = PointBehindOnRoute(rearPos)
    if x == nil then
        local okFront, front = pcall(GetFront, rear)
        if not okFront or type(front) ~= "table" then return nil end
        local length = math.sqrt(front.x * front.x + front.z * front.z)
        if length <= 0 then return nil end
        dx, dz = front.x / length, front.z / length
        x, z = rearPos.x - dx * PRESCOTT_BEHIND_M, rearPos.z - dz * PRESCOTT_BEHIND_M
    end
    return x, z, dx, dz
end

local function SpawnPrescott(platoon)
    local rear = RearConvoyUnit()
    if rear == nil then
        platoon.cancelled = true
        return
    end
    local x, z, dx, dz = PrescottSpawnPoint(rear)
    if x == nil then
        platoon.cancelled = true
        return
    end
    platoon.spawned = true
    local count = PrescottCount()
    for index = 1, count do
        local offset = (index - (count + 1) / 2) * PRESCOTT_SPREAD_M
        local px, pz = x - dz * offset, z + dx * offset
        local py = GetTerrainHeightAndNormal(SetVector(px, 0.0, pz))
        local unit = BuildObject("avtank", SUPPORT_TEAM, SetVector(px, py, pz))
        SetPerceivedTeam(unit, LEADER_TEAM)
        if SetIndependence ~= nil then SetIndependence(unit, 0) end
        platoon.units[#platoon.units + 1] = unit
    end
    platoon.next = 0
end

-- Leader only (the body runs nowhere else).
local function UpdatePrescott()
    if (not M.convoy_started) or M.game_over then return end
    local now = GetTime()
    local platoon = M.prescott
    if platoon == nil then
        local lead = ConvoyLead()
        if lead ~= nil and Distance(lead, M.cut_off_geyser) < PRESCOTT_TRIGGER_M then
            M.prescott = { due = now + PRESCOTT_DELAY_S, spawned = false, units = {}, orders = {}, next = 0 }
        end
        return
    end
    if (not platoon.spawned) and (not platoon.cancelled) and platoon.due < now then SpawnPrescott(platoon) end
    if platoon.spawned and platoon.next < now then OrderPrescott(platoon) end
end

local function PrescottArrived()
    return M.prescott ~= nil and M.prescott.spawned == true
end
-- CR Prescott platoon <<

-- CR cut VO >>
-- Called from AddObject on every peer; only the leader reacts.
local function NoteBuiltUnit(h)
    if not (M.start_done and not M.game_over and CRCoop.IsAuthority()) then return end
    if not IsValid(h) or not CRCoop.IsHumanTeam(GetTeamNum(h)) then return end
    if not IsAlive(M.nsdfmuf) or Distance(h, M.nsdfmuf) > FACTORY_BUILD_RADIUS_M then return end
    local combat = false
    for _, odf in ipairs(FACTORY_COMBAT_ODFS) do
        if IsOdfBase(h, odf) then combat = true end
    end
    if not combat then return end
    if not M.objective1 and not M.vo0917_done then M.vo0917_due = true end
    if IsOdfBase(h, "avwalk") and not M.vo0910_done and Distance(h, M.cut_off_geyser) > WALKER_FAR_M then
        M.vo0910_due = true
    end
end

-- One restored line at a time, each once.
local function UpdateCutVo()
    if not (M.vo0917_due or M.vo0910_due) then return end
    if not AudioDone(M.cutvo_msg) then return end
    if M.vo0917_due and not M.vo0917_done then
        M.cutvo_msg = AudioMessage("misn0917.wav")
        M.vo0917_done = true
        M.vo0917_due = false
    elseif M.vo0910_due and not M.vo0910_done then
        M.cutvo_msg = AudioMessage("misn0910.wav")
        M.vo0910_done = true
        M.vo0910_due = false
    else
        M.vo0917_due, M.vo0910_due = false, false
    end
end
-- CR cut VO <<

-- CR tug rebuild >>
-- The DLL's cut block rebuilt the tug at the CCA recycler 60 s after it died; this builds it at
-- the CCA factory after TUG_REBUILD_DELAY_S, at most TUG_REBUILD_MAX times, while the relic exists
-- and the factory lives. The existing tug logic (Pickup / Dropoff) then resumes the seizure.
local function UpdateTugRebuild()
    if (not M.convoy_started) or M.game_over then return end
    local now = GetTime()
    if (not IsAlive(M.ccatug)) and IsAlive(M.relic) and IsAlive(M.ccamuf) and (not M.build_new_tug)
        and (M.tug_rebuilds or 0) < TUG_REBUILD_MAX then
        M.build_tug_time = now + TUG_REBUILD_DELAY_S
        M.tug_done = false
        M.build_new_tug = true
    end
    if M.build_new_tug and M.build_tug_time < now and not M.tug_done then
        M.build_new_tug = false
        if IsAlive(M.ccamuf) and IsAlive(M.relic) then
            M.ccatug = BuildObject("svhaul", ENEMY_TEAM, M.ccamuf)
            M.tug_rebuilds = (M.tug_rebuilds or 0) + 1
            M.tug_done = true
            M.tug_escort_due = true
        else
            M.tug_done = true
        end
    end
    -- The surviving escort follows the new tug once it has the relic again.
    if M.tug_escort_due and M.relic_seized and IsAlive(M.ccatug) then
        M.tug_escort_due = false
        for _, unit in ipairs(ConvoyCombatUnits()) do Follow(unit, M.ccatug) end
        for _, unit in ipairs({ M.convoy9, M.convoy0 }) do
            if unit ~= nil and IsAlive(unit) then Follow(unit, M.ccatug) end
        end
    end
end
-- CR tug rebuild <<

-- CR Venus weather >>
-- Venus atmosphere (Docs/VENUS_WEATHER.md). The leader (or offline play) runs the director's
-- automatic weather and the beats below; guests render the same sky from the seeded timeline
-- plus the host's state and strike/eruption events, which ride the ordered presentation
-- stream like any other event. The events carry no handles, so they bypass the marker
-- label/TTL logic. The director never damages anything (knockback and radar scramble only).
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
            events[#events + 1] = { op = op, args = { ... }, n = select("#", ...), ttl = RESOLVE_TIMEOUT }
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
--   2 calm while the base is set up and the artillery falls -> 3 when the convoy launches (the
--   tug has the relic) or the cutoff warning (misn0903) fires -> a 60 s level-5 burst when
--   Prescott's platoon arrives or the tug makes its final run on the launch pad -> calm (1) on
--   the win (see SucceedMission above).
local FINAL_FIGHT_M = 500.0
local function UpdateVenusBeats()
    local beats = M.venusBeats
    if beats == nil then beats = {}; M.venusBeats = beats end
    if (not beats.convoy) and (M.convoy_started or M.convoy_cam_ready) then
        beats.convoy = true
        CRVenusWeather.SetTargetLevel(3)
    end
    if (not beats.burst) and (PrescottArrived() or (M.relic_seized and IsAlive(M.ccatug) and IsAlive(M.ccalaunch)
        and Distance(M.ccatug, M.ccalaunch) < FINAL_FIGHT_M)) then
        beats.burst = true
        CRVenusWeather.ForceLevel(5, 60.0, 10.0)
    end
end
-- CR Venus weather <<

-- CR rally >>
-- Respawns rally at the Unit Factory (avmuf) while it lives. Its loss fails the mission (misn0911),
-- but until the result lands a respawn must not rally at a corpse: drop the rally point and the
-- native MultST spawn (the player start buoys' team start) takes over.
local rallyDropped = false
local function UpdateRally()
    if rallyDropped then return end
    local factory = GetHandle("avmuf")
    if factory == nil or not IsAlive(factory) then
        rallyDropped = true
        local respawn = CRCoop.GetRespawn()
        if respawn then respawn.SetRallyPoints({}) end
    end
end
-- CR rally <<

-- Misn09Mission::Setup body (every peer runs it; only the leader acts on the state).
local function Setup()
    M = NewState()
    --[==[ Original C++ comment (inactive):
/*
Here's where you set the values at the start.  
*/
    ]==]
    M.stuff = 0
    M.x = 950
    M.y = 3000
    M.scrap = 100
    M.start_done = false
    M.start_camera1 = false
    M.convoy_started = false
    M.player_dead = false
    M.camera_ready = false
    M.build_new_tug = false
    M.tug_done = false
    M.objective1 = false
    M.camera_artil = false
    M.first_warning = false
    M.second_warning = false
    M.third_warning = false
    M.muf_contact = false
    M.muf_moving = false
    M.post1 = false
    M.post2 = false
    M.post3 = false
    M.post4 = false
    M.guard1 = false
    M.guard2 = false
    M.turret1_set = false
    M.turret2_set = false
    M.turret3_set = false
    M.turret4_set = false
    M.get_relic = false
    M.relic_secure = false
    M.relic_seized = false
    M.relic_free = false
    M.tug_underway = false
    M.game_over = false
    M.head_4_pad = false
    M.next_shot = false
    M.player_camera_off = false
    M.next_shot_message = false
    M.cam1_on = false
    M.cam2_on = false
    M.cam3_on = false
    M.cam4_on = false
    M.cam5_on = false
    M.cam_off = false
    M.convoy_cam_ready = false
    M.convoy_cam_off = false
    M.muf_deployed = false
    M.scavs_alive = false
    M.charon_found = false
    M.charon_build = false
    M.start = false
    M.opening_vo = false
    M.muf_gobaby = false
    M.recon_artil = false
    M.base_warning = false
    M.muf_deployed_good = false
    M.ccadead = false
    M.game_over5 = false
    M.start_convoy_time = 99999.0
    M.camera_ready_time = 99999.0
    M.build_tug_time = 99999.0
    M.camera_on_time = 99999.0
    M.first_warning_time = 99999.0
    M.second_warning_time = 99999.0
    M.third_warning_time = 99999.0
    M.muf_check = 99999.0
    M.movie_time = 99999.0
    M.turret1_time = 99999.0
    M.turret2_time = 99999.0
    M.turret3_time = 99999.0
    M.turret4_time = 99999.0
    M.unit_check = 99999.0
    M.win_check = 99999.0
    M.atril_check = 99999.0
    M.player_camera_time = 99999.0
    M.next_shot_time = 99999.0
    M.cam1_time = 99999.0
    M.cam2_time = 99999.0
    M.cam3_time = 99999.0
    M.cam4_time = 99999.0
    M.cam5_time = 99999.0
    M.convoy_cam_time = 99999.0
    M.deploy_check = 99999.0
    M.charon_check = 99999.0
    M.start_time = 20.0
    M.recon_message_time = 99999.0
    M.ccatug = nil
    M.ccaturret1 = GetHandle("artil1")
    M.ccaturret2 = GetHandle("artil2")
    M.ccaturret3 = GetHandle("artil3")
    M.ccaturret4 = GetHandle("artil4")
    M.ccaturret5 = GetHandle("artil5")
    M.ccaturret6 = GetHandle("artil6")
    M.ccarecycle = GetHandle("svrecycle")
    M.avscav1 = GetHandle("scav1")
    M.avscav2 = GetHandle("scav2")
    M.avscav3 = GetHandle("scav3")
    M.nsdfrig = GetHandle("rig")
    M.nsdfslf = GetHandle("avslf")
    M.ccamuf = GetHandle("svmuf")
    M.nsdfmuf = GetHandle("avmuf")
    M.convoy_geyser = GetHandle("convoy_geyser")
    M.ccalaunch = GetHandle("launchpad")
    M.nav1 = GetHandle("cam1")
    M.charon = GetHandle("hbchar0_i76building")
    M.cut_off_geyser = GetHandle("cut_off_geyser")
    M.key_scrap = GetHandle("key_scrap")
    M.cca1 = nil
    M.cca2 = nil
    M.cca3 = nil
    M.cca4 = nil
    M.cca5 = nil
    M.cca6 = nil
    M.cca7 = nil
    M.cca8 = nil
    M.cca9 = nil
    M.cca0 = nil
    M.scav1 = nil
    M.scav2 = nil
    M.scav3 = nil
    M.nsdfgech1 = nil
    M.nsdftug = nil
    M.convoy1 = nil
    M.convoy2 = nil
    M.convoy3 = nil
    M.convoy4 = nil
    M.convoy5 = nil
    M.convoy6 = nil
    M.convoy7 = nil
    M.convoy8 = nil
    M.convoy9 = nil
    M.convoy0 = nil
    M.relic = nil
    M.tugger = nil
    M.audmsg = nil
    M.avsilo = nil
    M.charon_nav = nil
end

-- Preserve the native first-empty-slot order and ODF-only matching: there is
-- deliberately no dead-slot reuse or convoy exclusion. The only addition is the marked
-- co-op team filter at the top of AddObject.
local trackedObjects = {
    {"cca1", "svturr"}, {"cca2", "svturr"},
    {"cca3", "svturr"}, {"cca4", "svturr"},
    {"cca5", "svfigh"}, {"cca6", "svfigh"},
    {"cca7", "svfigh"}, {"cca8", "svfigh"},
    {"cca9", "svtank"}, {"cca0", "svtank"},
    {"scav1", "svscav"}, {"scav2", "svscav"}, {"scav3", "svscav"},
    {"nsdfgech1", "avwalk"}, {"ccatug", "svhaul"}, {"avsilo", "absilo"},
}
function AddObject(h)
-- CR Venus weather >>
    if h == nil then return end
    Environment.OnObjectCreated(h)
    CRVenusWeather.OnObjectCreated(h)
-- CR Venus weather <<
-- CR team filter >>
    if not AddObjectTeamAllowed(h) then return end
-- CR team filter <<
-- CR cut VO >>
    NoteBuiltUnit(h)
-- CR cut VO <<
    for _, entry in ipairs(trackedObjects) do
        if M[entry[1]] == nil and IsOdfBase(h, entry[2]) then
            M[entry[1]] = h
            return
        end
    end
end

local function InitializeCoop()
    CRCoop.Initialize({
        getLocalPlayerId = function() return exu.GetMyNetID and exu.GetMyNetID() end,
        leaderTeam = LEADER_TEAM, humanTeamMin = 1, humanTeamMax = 4,
        onOutOfLives = function() FailMission(GetTime() + 3.0) end,
        -- Rally at the Unit Factory (avmuf) while it lives; the rally watcher drops the point when it
        -- dies and the native MultST team start takes over.
        rallyPoints = { [0] = "avmuf" },
    })
    ConfigureAlliances()
    ResetPresentation()
-- CR rally >>
    rallyDropped = false
-- CR rally <<
-- CR Venus weather >>
    ShutdownVenusWeather()
-- CR Venus weather <<
end

function Start()
    InitializeCoop()
    SetAIControl(ENEMY_TEAM, true)
    Setup()
    -- C++ Setup precedes AiMission::Load and its AddObject notifications.
    -- Redux may create map objects before Start; recover the tracked slots
    -- after Setup so those earlier notifications cannot be discarded.
    for h in AllObjects() do
        AddObject(h)
    end
    subtit.Initialize()
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
    if M.coopResult or M.coopPendingResult then
-- CR Venus weather >>
        -- The storm keeps easing while the result screen counts down.
        UpdateVenusWeather(dt)
-- CR Venus weather <<
        return
    end
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
    UpdateInfoRelay()
-- CR Venus weather >>
    UpdateVenusWeather(dt)
-- CR Venus weather <<
-- CR rally >>
    UpdateRally()
-- CR rally <<
    if not CRCoop.IsAuthority() then return end
    if CRCoop.IsNetworkGame() and not M.coopBootstrapped then
        M.coopBootstrapped = true
        -- The authored offline placeholder must not remain beside the humans.
        local offlinePlayer = GetHandle("player0_hover")
        if IsValid(offlinePlayer) and not CRCoop.IsHumanCraft(offlinePlayer) then RemoveObject(offlinePlayer) end
    end
    -- Misn09Mission::Execute body (DLL order preserved below).
    --[==[ Original C++ comment (inactive):
/*
Here is where you put what happens every frame.  
*/
    ]==]
    --[==[ Original C++ comment (inactive):
// START OF SCRIPT
    ]==]
    if (M.relic_free) and (IsAlive(M.relic)) then
        M.tugger = GetTug(M.relic)
        if IsAlive(M.tugger) then
            if GetTeamNum(M.tugger) ~= ENEMY_TEAM then
                M.relic_free = false
                M.relic_secure = true
            else
                M.relic_free = false
                M.relic_seized = true
                M.tugger = M.ccatug
            end
        end
    end
    if (M.relic_secure) and (not IsAlive(M.tugger)) then
        M.relic_free = true
        M.relic_secure = false
    end
    if (M.relic_seized) and (not IsAlive(M.ccatug)) then
        M.relic_free = true
        M.relic_seized = false
    end
    if IsAlive(M.relic) then
        if (IsAlive(M.ccatug)) and (M.relic_free) and (not M.tug_underway) then
            Pickup(M.ccatug, M.relic)
            M.tug_underway = true
        end
        if (M.relic_seized) and (not M.head_4_pad) then
            Dropoff(M.ccatug, "soviet_path", 1)
            M.head_4_pad = true
        end
    end
    if not IsAlive(M.ccatug) then
        M.tug_underway = false
        M.head_4_pad = false
    end
    --[==[ Original C++ comment (inactive):
/*	if (IsAlive(nsdftug))
	{
		if (HasCargo(nsdftug))
		{
			relic_free = false;
			relic_secure = true;
		}
		else
		{
			if (!relic_seized)
			{
				relic_free = true;
				relic_secure = false;
			}
		}
	}

*/
    ]==]
    M.user = GetPlayerHandle()
-- CR Venus weather >>
    UpdateVenusBeats()
-- CR Venus weather <<
    --[==[ Original C++ comment (inactive):
//assigns the player a handle every frame
    ]==]
    --[==[ Original C++ comment (inactive):
//	if ((start_time < Get_Time()) && (!start))
    ]==]
    --[==[ Original C++ comment (inactive):
//	{
    ]==]
    --[==[ Original C++ comment (inactive):
//		start = true;
    ]==]
    --[==[ Original C++ comment (inactive):
//	}
    ]==]
    if not M.start_done then
        CameraReady()
        Defend(M.nsdfmuf)
        SetScrap(ENEMY_TEAM, 40)
        SetPilot(ENEMY_TEAM, 40)
        Follow(M.nsdfrig, M.nsdfmuf, 1)
        Follow(M.avscav1, M.nsdfmuf, 1)
        Follow(M.avscav2, M.nsdfmuf, 1)
        Follow(M.avscav3, M.nsdfmuf, 1)
        Follow(M.nsdfslf, M.nsdfrig, 0)
        Defend(M.ccaturret1)
        Defend(M.ccaturret2)
        Defend(M.ccaturret3)
        Defend(M.ccaturret4)
        Defend(M.ccaturret5)
        Defend(M.ccaturret6)
        --[==[ Original C++ comment (inactive):
//		start_convoy_time = Get_Time() + 900.0f;		
        ]==]
        M.camera_ready_time = GetTime() + 6.0
        M.muf_check = GetTime() + 3.0
        M.first_warning_time = GetTime() + 700.0
        M.second_warning_time = GetTime() + 1000.0
        M.third_warning_time = GetTime() + 1300.0
        --[==[ Original C++ comment (inactive):
// was 900.0f
        ]==]
        M.unit_check = GetTime() + 1360.0
        M.atril_check = GetTime() + 15.0
        M.player_camera_time = GetTime() + 11.0
        M.deploy_check = GetTime() + 6.0
        M.charon_check = GetTime() + 30.0
        M.next_shot_time = GetTime() + 22.0
        if M.nav1 ~= nil then
            SetObjectiveName(M.nav1, "Choke Point")
        end
        M.start_camera1 = true
        M.start_done = true
    end
    if M.start_camera1 then
        CameraPath("camera_circle", 375, 750, M.key_scrap)
    end
    --[==[ Original C++ comment (inactive):
/*
	if ((!next_shot_message) && ((player_camera_time < Get_Time()) || (CameraCancelled())))
	{
		CameraPath("launch_camera_path", 7000, 1150, ccalaunch);

		if (x > 6000.0f)
		{
			x = x - 150;
		}
		else
		{
			x = x + 50;
		}
		y = y - 20;
*/
    ]==]
    --[==[ Original C++ comment (inactive):
/*		next_shot = true;
	}

	if ((!next_shot_message) && (IsAudioMessageDone(audmsg)))
	{
		audmsg = AudioMessage("misn0912.wav");
		next_shot_time = Get_Time() + 6.0f;
		next_shot_message = true;
	}

	if ((next_shot_message) && (!player_camera_off)) 
	{
		CameraPath("choke_cam_path", 375, 450, nav1);
	}
*/
    ]==]
    if (not M.player_camera_off) and ((M.next_shot_time < GetTime()) or (CameraCancelled())) then
        CameraFinish()
        M.start_camera1 = false
        M.player_camera_off = true
    end
    if CameraCancelled() then
        StopAudio(M.audmsg)
    end
    --[==[ Original C++ comment (inactive):
// this starts the opening voice-over
    ]==]
    if ((M.camera_ready_time < GetTime()) and (not M.opening_vo)) then
        M.audmsg = AudioMessage("misn0900.wav")
        --[==[ Original C++ comment (inactive):
//starts opening V.O.5
        ]==]
        ClearObjectives()
        AddObjective("misn0900.otf", "white")
        M.opening_vo = true
    end
    if (M.opening_vo) and (not M.muf_gobaby) and (AudioDone(M.audmsg)) then
        Goto(M.nsdfmuf, "return_path", 1)
        M.muf_gobaby = true
    end
    --[==[ Original C++ comment (inactive):
// this tells the muf to stop when the player gets close & plays the artillery message
    ]==]
    if (M.muf_gobaby) and (M.muf_check < GetTime()) and (not M.muf_contact) then
        M.muf_check = GetTime() + 1.0
        if AnyPlayerWithin(M.nsdfmuf, 70.0) then
            Stop(M.nsdfmuf, 0)
            Stop(M.nsdfslf, 0)
            Defend(M.nsdfrig, 0)
            SetScrap(1, 20)
            SetPilot(1, 7)
            AudioMessage("misn0905.wav")
            --[==[ Original C++ comment (inactive):
// message from muf "we took a beating out there"
            ]==]
            M.movie_time = GetTime() + 7.0
            M.muf_contact = true
        end
    end
    if (not M.objective1) and (M.atril_check < GetTime()) then
        M.atril_check = GetTime() + 15.0
        if IsAlive(M.ccaturret1) then
            Defend(M.ccaturret1)
        end
        if IsAlive(M.ccaturret2) then
            Defend(M.ccaturret2)
        end
        if IsAlive(M.ccaturret3) then
            Defend(M.ccaturret3)
        end
        if IsAlive(M.ccaturret4) then
            Defend(M.ccaturret4)
        end
        if IsAlive(M.ccaturret5) then
            Defend(M.ccaturret5)
        end
        if IsAlive(M.ccaturret6) then
            Defend(M.ccaturret6)
        end
    end
    --[==[ Original C++ comment (inactive):
// this starts the muf towards the player
    ]==]
    --[==[ Original C++ comment (inactive):
/*	if ((player_camera_off) && (!muf_moving))
	{
		Goto(nsdfmuf, "return_path", 1);
		Follow(nsdfrig, nsdfmuf, 1);
		Follow(avscav1, nsdfmuf, 1);
		Follow(avscav2, nsdfmuf, 1);
		Follow(avscav3, nsdfmuf, 1);
		Follow(nsdfslf, nsdfrig, 1);
		muf_moving = true;
	}
*/
    ]==]
    --[==[ Original C++ comment (inactive):
// this checks to see if the muf is deployed
    ]==]
    if (M.deploy_check < GetTime()) and (not M.muf_deployed) then
        M.deploy_check = GetTime() + 2.0
        if IsAlive(M.nsdfmuf) then
            local test = IsDeployed(M.nsdfmuf)
            if test then
                M.muf_deployed = true
            end
        end
    end
    if ((M.muf_deployed) or (IsAlive(M.avsilo))) and (not M.scavs_alive) then
        Stop(M.avscav1, 0)
        Stop(M.avscav2, 0)
        Stop(M.avscav3, 0)
        M.scavs_alive = true
    end
    --[==[ Original C++ comment (inactive):
// This turns the camera over the artilery units on/off ////////
    ]==]
    if IsAlive(M.ccaturret6) then
        if (M.muf_contact) and (M.movie_time < GetTime()) and (not M.camera_ready) then
            CameraReady()
            M.cam5_time = GetTime() + 7.0
            M.camera_ready = true
        end
        if (M.camera_ready) and (not M.cam_off) then
            CameraPath("camera_path", M.x, 300, M.ccaturret6)
            M.x = M.x + 90
        end
        if (M.camera_ready) and (M.cam5_time < GetTime()) and (not M.cam_off) then
            CameraFinish()
            ClearObjectives()
            AddObjective("misn0900.otf", "green")
            AddObjective("misn0901.otf", "white")
            Stop(M.nsdfrig, 0)
            SetAIP("misn09.aip", ENEMY_TEAM)
            M.recon_message_time = GetTime() + 60.0
            M.cam_off = true
        end
    end
    if (M.recon_message_time < GetTime()) and (not M.recon_artil) then
        M.recon_message_time = GetTime() + 1.0
        AudioMessage("misn0913.wav")
        M.recon_artil = true
    end
    if (M.recon_message_time < GetTime()) and (not M.base_warning) then
        M.recon_message_time = GetTime() + 2.0
        if ((IsAlive(M.nav1)) and (AnyPlayerWithin(M.nav1, 100.0))) or ((IsAlive(M.cca5)) and (AnyPlayerWithin(M.cca5, 400.0))) or ((IsAlive(M.cca6)) and (AnyPlayerWithin(M.cca6, 400.0))) then
            AudioMessage("misn0914.wav")
            M.base_warning = true
        end
    end
    --[==[ Original C++ comment (inactive):
/*	
	if ((camera_ready) && (!cam2_on))	
	{
		CameraObject(ccaturret6, 650, 650, 650, ccaturret6);
		if (!cam1_on)
		{
			cam1_time = Get_Time() + 2.0f;
			cam1_on = true;
		}
	}

	if ((cam1_on) && (cam1_time < Get_Time()) && (!cam3_on))
	{
		CameraObject(ccaturret5, -650, 350, 300, ccaturret5);
		if (!cam2_on)
		{
			cam2_time = Get_Time() + 2.0f;
			cam2_on = true;
		}
	}

	if ((cam2_on) && (cam2_time < Get_Time()) && (!cam4_on))
	{
		CameraObject(ccaturret4, 1000, 1350, 600, ccaturret4);
		if (!cam3_on)
		{
			cam3_time = Get_Time() + 2.0f;
			cam3_on = true;
		}
	}

	if ((cam3_on) && (cam3_time < Get_Time()) && (!cam5_on))
	{
		CameraObject(ccaturret3, -90, -250, 1000, ccaturret3);
		if (!cam4_on)
		{
			cam4_time = Get_Time() + 2.0f;
			cam4_on = true;
		}
	}

	if ((cam4_on) && (cam4_time < Get_Time()) && (!cam_off))
	{
		CameraObject(ccaturret2, 500, 900, 90, ccaturret2);
		if (!cam5_on)
		{
			cam5_time = Get_Time() + 2.0f;
			cam5_on = true;
		}
	}

	if ((cam5_on) && (cam5_time < Get_Time()) && (!cam_off))		
	{															
		CameraFinish();
		ClearObjectives();
		AddObjective("misn0900.otf", GREEN);
		AddObjective("misn0901.otf", WHITE);
		cam_off = true;									
	}

*/
    ]==]
    --[==[ Original C++ comment (inactive):
// end of camera script for artiliery units ////////////////////
    ]==]
    --[==[ Original C++ comment (inactive):
// this is going to set up a fortification of turrets
    ]==]
    if (IsAlive(M.cca1)) and (not M.post1) then
        Goto(M.cca1, "post1", 1)
        M.turret1_time = GetTime() + 10.0
        M.post1 = true
    end
    if (M.post1) and (M.turret1_time < GetTime()) then
        M.turret1_time = GetTime() + 15.0
        if IsAlive(M.cca1) then
            Defend(M.cca1)
        end
    end
    if (IsAlive(M.cca2)) and (not M.post2) then
        Goto(M.cca2, "post2", 1)
        M.turret2_time = GetTime() + 10.0
        M.post2 = true
    end
    if (M.post2) and (M.turret2_time < GetTime()) then
        M.turret2_time = GetTime() + 15.0
        if IsAlive(M.cca2) then
            Defend(M.cca2)
        end
    end
    if (IsAlive(M.cca3)) and (not M.post3) then
        Goto(M.cca3, "post3", 1)
        M.turret3_time = GetTime() + 10.0
        -- PORT FIX: Source set post1 here, so post3 stayed false, Goto repeated
        -- every frame, and the ten-second defense timer never ran. Set post3
        -- to latch the same post3 move once, matching the other three posts.
        -- No spawn, objective, convoy, or outcome gate depends on this flag.
        M.post3 = true
    end
    if (M.post3) and (M.turret3_time < GetTime()) then
        M.turret3_time = GetTime() + 15.0
        if IsAlive(M.cca3) then
            Defend(M.cca3)
        end
    end
    if (IsAlive(M.cca4)) and (not M.post4) then
        Goto(M.cca4, "post4", 1)
        M.turret4_time = GetTime() + 10.0
        M.post4 = true
    end
    if (M.post4) and (M.turret4_time < GetTime()) then
        M.turret4_time = GetTime() + 15.0
        if IsAlive(M.cca4) then
            Defend(M.cca4)
        end
    end
    --[==[ Original C++ comment (inactive):
// this is to insure that the soviets keep trying to get the database relic	
    ]==]
    --[==[ Original C++ comment (inactive):
/*																			
	if ((convoy_started) && (!IsAlive (ccatug)) && (IsAlive(ccarecycle)) && (!build_new_tug))	
	{																		
		build_tug_time = Get_Time () + 60.0f;// was 60 seconds
		tug_done = false;
		build_new_tug = true;												
	}																		
																			
	if ((build_new_tug) && (build_tug_time < Get_Time()) && (!tug_done))	
	{																		
		ccatug = BuildObject("svhaul", 2, ccarecycle);
//		convoy_started = false; // should change this to somthing else
		build_new_tug = false;
		tug_done = true;
	}																								
*/
    ]==]
-- CR tug rebuild >>
    UpdateTugRebuild()
-- CR tug rebuild <<
    --[==[ Original C++ comment (inactive):
// if player destroys all the cca turrets///////////////////////////////////////////////
    ]==]
    if (not IsAlive(M.ccaturret1)) and (not IsAlive(M.ccaturret2)) and (not IsAlive(M.ccaturret3)) and (not IsAlive(M.ccaturret4)) and (not IsAlive(M.ccaturret5)) and (not IsAlive(M.ccaturret6)) and (not M.objective1) then
        AudioMessage("misn0904.wav")
        --[==[ Original C++ comment (inactive):
//congradulations you killed the turrets
        ]==]
        Stop(M.avscav1, 0)
        Stop(M.avscav2, 0)
        Stop(M.avscav3, 0)
        ClearObjectives()
        AddObjective("misn0901.otf", "green")
        AddObjective("misn0902.otf", "white")
        AddObjective("misn0903.otf", "white")
        if not M.third_warning then
            SetAIP("misn09a.aip", ENEMY_TEAM)
            --[==[ Original C++ comment (inactive):
// causes the soviets to get more aggresive
            ]==]
        end
        M.objective1 = true
    end
    --[==[ Original C++ comment (inactive):
// this is the general warning of the approaching convoy ////////////////////////////////
    ]==]
    if (not M.first_warning) and (M.first_warning_time < GetTime()) then
        AudioMessage("misn0901.wav")
        --[==[ Original C++ comment (inactive):
// the soviets convey will be here in less than 10 minutes
        ]==]
        M.first_warning = true
    end
    if (not M.second_warning) and (M.second_warning_time < GetTime()) then
        AudioMessage("misn0902.wav")
        --[==[ Original C++ comment (inactive):
// the soviets convey will be here in less than 5 minutes
        ]==]
        M.second_warning = true
    end
    if (not M.third_warning) and (M.third_warning_time < GetTime()) then
        M.third_warning_time = GetTime() + 11.0
        if NoPlayerWithin(M.convoy_geyser, 500.0) then
            M.relic = BuildObject("obdata", RELIC_TEAM, M.convoy_geyser)
            M.ccatug = BuildObject("svhaul", ENEMY_TEAM, "spawn1")
            M.convoy1 = BuildObject("svfigh", ENEMY_TEAM, "spawn2")
            M.convoy2 = BuildObject("svfigh", ENEMY_TEAM, "spawn2")
            M.convoy3 = BuildObject("svfigh", ENEMY_TEAM, "spawn2")
            M.convoy4 = BuildObject("svfigh", ENEMY_TEAM, "spawn3")
            M.convoy5 = BuildObject("svtank", ENEMY_TEAM, "spawn3")
            M.convoy6 = BuildObject("svtank", ENEMY_TEAM, "spawn3")
            M.convoy7 = BuildObject("svtank", ENEMY_TEAM, "spawn4")
            M.convoy8 = BuildObject("svtank", ENEMY_TEAM, "spawn4")
            M.convoy9 = BuildObject("svapc", ENEMY_TEAM, "spawn4")
            M.convoy0 = BuildObject("svapc", ENEMY_TEAM, "spawn4")
            Defend(M.convoy1)
            Defend(M.convoy2)
            Defend(M.convoy3)
            Defend(M.convoy4)
            Defend(M.convoy5)
            Defend(M.convoy6)
            Defend(M.convoy7)
            Defend(M.convoy8)
            Defend(M.convoy9)
            Defend(M.convoy0)
-- CR convoy scaling >>
            M.convoy_extra = SpawnConvoyExtras()
-- CR convoy scaling <<
            --[==[ Original C++ comment (inactive):
//			Pickup(ccatug, relic); // should do automatically
            ]==]
            if not M.objective1 then
                ClearObjectives()
                AddObjective("misn0901.otf", "red")
                AddObjective("misn0902.otf", "white")
                AddObjective("misn0903.otf", "white")
            end
            M.win_check = GetTime() + 5.0
            SetAIP("misn09b.aip", ENEMY_TEAM)
            --[==[ Original C++ comment (inactive):
// causes the soviets to get more reserved
            ]==]
            M.relic_free = true
            M.third_warning = true
        end
    end
    --[==[ Original C++ comment (inactive):
// this starts the convoy towards the launch pad ////////////////////////////////////
    ]==]
    if (M.third_warning) and (M.relic_seized) and (not M.convoy_started) then
        SetObjectiveOn(M.relic)
        SetObjectiveName(M.relic, "Alien Relic")
        Goto(M.ccatug, "soviet_path", 1)
        Follow(M.convoy1, M.ccatug)
        Follow(M.convoy2, M.ccatug)
        Follow(M.convoy3, M.ccatug)
        Follow(M.convoy4, M.ccatug)
        Follow(M.convoy5, M.ccatug)
        Follow(M.convoy6, M.ccatug)
        Follow(M.convoy7, M.ccatug)
        Follow(M.convoy8, M.ccatug)
        Follow(M.convoy9, M.ccatug)
        Follow(M.convoy0, M.ccatug)
-- CR convoy scaling >>
        FollowConvoyExtras()
-- CR convoy scaling <<
        M.convoy_cam_time = GetTime() + 7.0
        M.convoy_started = true
    end
    if (M.convoy_started) and (not M.convoy_cam_ready) and (M.convoy_cam_time < GetTime()) then
        AudioMessage("misn0903.wav")
        --[==[ Original C++ comment (inactive):
// the soviets convey is within radar range "I'm picking up the soviet convoy"
        ]==]
        CameraReady()
        M.convoy_cam_time = GetTime() + 18.0
        M.convoy_cam_ready = true
    end
    if (M.convoy_cam_ready) and (not M.convoy_cam_off) then
        CameraPath("convoy_cam_path", M.y, 1150, M.ccatug)
        M.y = M.y - 10
    end
    -- PORT FIX: Source used the CameraCancelled function address without ().
    -- A function address is always true, ending this shot on its first frame.
    -- Call the predicate so the existing 18-second duration/cancel rule works.
    -- Camera completion is not a mission progression or outcome gate.
    if (M.convoy_cam_ready) and (not M.convoy_cam_off) and ((M.convoy_cam_time < GetTime()) or (CameraCancelled())) then
        CameraFinish()
        M.convoy_cam_off = true
    end
    --[==[ Original C++ comment (inactive):
// this is the charon code
    ]==]
    if (IsAlive(M.charon)) and (not M.charon_found) then
        if M.charon_check < GetTime() then
            M.charon_check = GetTime() + 2.0
            if AnyPlayerWithin(M.charon, 70.0) then
                AudioMessage("misn0915.wav")
                --[==[ Original C++ comment (inactive):
// told to check out the charon
                ]==]
                M.charon_found = true
            end
        end
    end
    if (M.charon_found) and (IsInfo("hbchar") == true) and (not M.charon_build) then
        AudioMessage("misn0916.wav")
        --[==[ Original C++ comment (inactive):
// well done, we'll drop a nav camera here to come back to this, this looks like a good spot to go after artils
        ]==]
        M.charon_nav = BuildObject("apcamr", 1, "charon_spawn")
        if M.charon_nav ~= nil then
            SetObjectiveName(M.charon_nav, "Alien Relic")
        end
        M.charon_build = true
    end
    --[==[ Original C++ comment (inactive):
// this is to check and see if the muf is deployed correctly
    ]==]
    if (M.objective1) or (M.third_warning) then
        if (not M.muf_deployed_good) and (M.deploy_check < GetTime()) then
            M.deploy_check = GetTime() + 2.0
            if IsAlive(M.nsdfmuf) then
                local test1 = IsDeployed(M.nsdfmuf)
                -- PORT FIX: Removed the source's stray semicolon after this if.
                -- It made the following objective update unconditional for a
                -- living factory. Require the already-authored deployed/400m
                -- check. muf_deployed_good only latches this display update;
                -- no convoy timing, relic logic, or outcome uses this flag.
                if (test1) and (Distance(M.nsdfmuf, M.convoy_geyser) < 400.0) then
                    if M.objective1 then
                        ClearObjectives()
                        AddObjective("misn0901.otf", "green")
                        AddObjective("misn0902.otf", "green")
                        AddObjective("misn0903.otf", "white")
                        M.muf_deployed_good = true
                    else
                        ClearObjectives()
                        AddObjective("misn0901.otf", "red")
                        AddObjective("misn0902.otf", "green")
                        AddObjective("misn0903.otf", "white")
                        M.muf_deployed_good = true
                    end
                end
            end
        end
    end
    if (not IsAlive(M.ccarecycle)) and (not IsAlive(M.ccamuf)) and (not M.ccadead) then
        AudioMessage("misn0908.wav")
        --[==[ Original C++ comment (inactive):
// you've cleared the area of the enemy well done
        ]==]
        M.ccadead = true
    end
    --[==[ Original C++ comment (inactive):
// end of general's warings /////////////////////////////////////////////////////////////
    ]==]
-- CR Prescott platoon >>
    UpdatePrescott()
-- CR Prescott platoon <<
-- CR cut VO >>
    UpdateCutVo()
-- CR cut VO <<
    --[==[ Original C++ comment (inactive):
// win/victory conditions  
    ]==]
    if (M.scavs_alive) and (not IsAlive(M.avscav1)) and (not IsAlive(M.avscav2)) and (not IsAlive(M.avscav3)) and (not M.game_over) then
        if (not M.objective1) and (not M.first_warning) then
            M.scrap = GetScrap(1)
            if M.scrap < 10 then
                FailMission(GetTime() + 6.0, "misn09f4.des")
                M.game_over = true
            end
        end
    end
    if (M.convoy_started) and (not IsAlive(M.relic)) and (not M.game_over) then
        AudioMessage("misn0906.wav")
        --[==[ Original C++ comment (inactive):
// the relic has been destroyed commander
        ]==]
        FailMission(GetTime() + 15.0, "misn09f1.des")
        M.game_over = true
    end
    if (M.relic_seized) and (IsAlive(M.ccalaunch)) and (Distance(M.ccatug, M.ccalaunch) < 100.0) and (not M.game_over) then
        AudioMessage("misn0907.wav")
        --[==[ Original C++ comment (inactive):
// the tug has reached the launch pad
        ]==]
        FailMission(GetTime() + 15.0, "misn09f2.des")
        M.game_over = true
    end
    if (M.convoy_started) and (M.unit_check < GetTime()) and (not M.game_over5) then
        M.unit_check = GetTime() + 10.0
        M.stuff = CountUnitsNearObject(M.convoy_geyser, 5000.0, ENEMY_TEAM, nil)
        if M.stuff == 0 then
            AudioMessage("misn0908.wav")
            --[==[ Original C++ comment (inactive):
// you've cleared the area of the enemy well done
            ]==]
            --[==[ Original C++ comment (inactive):
//			SucceedMission(Get_Time() + 15.0f, "misn09w1.des");
            ]==]
            M.game_over5 = true
-- CR geyser-clear win >>
            -- The DLL cut SucceedMission here; clearing every CCA unit near the geyser wins.
            if not M.game_over then
                SucceedMission(GetTime() + 15.0, "misn09w1.des")
                M.game_over = true
            end
-- CR geyser-clear win <<
        end
    end
    if (IsAlive(M.relic)) and (not M.relic_seized) and (M.win_check < GetTime()) and (not M.game_over) then
        M.win_check = GetTime() + 2.0
        if (IsAlive(M.nsdfmuf)) and (Distance(M.relic, M.nsdfmuf) < 100.0) then
            AudioMessage("misn0909.wav")
            --[==[ Original C++ comment (inactive):
// you've won
            ]==]
            SucceedMission(GetTime() + 15.0, "misn09w1.des")
            M.game_over = true
        end
    end
    if (not IsAlive(M.nsdfmuf)) and (not M.game_over) then
        AudioMessage("misn0911.wav")
        --[==[ Original C++ comment (inactive):
// you've lost your muf
        ]==]
        FailMission(GetTime() + 15.0, "misn09f3.des")
        M.game_over = true
    end
    if (not IsAlive(M.ccalaunch)) and (not M.game_over) then
        AudioMessage("misn0918.wav")
        --[==[ Original C++ comment (inactive):
// you've destroyed the launchpad
        ]==]
        FailMission(GetTime() + 15.0)
        M.game_over = true
    end
    --[==[ Original C++ comment (inactive):
// END OF SCRIPT
    ]==]
end

-- BZR serializes this table's primitive/game types and restores object handles.
-- Load must not run Setup/Start or replay any spawns, commands, or cameras.
function Save()
-- CR Venus weather >>
    if venusStarted and ((not CRCoop.IsNetworkGame()) or CRCoop.IsAuthority()) then
        M.weatherState = CRVenusWeather.Save()
    end
-- CR Venus weather <<
    return M
end
function Load(state)
    if state ~= nil then M = state end
end
