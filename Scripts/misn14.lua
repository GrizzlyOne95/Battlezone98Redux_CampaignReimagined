-- Campaign Reimagined misn14 "The Three Beacons" for Battlezone 98 Redux / Lua 5.1: shared offline +
-- 2-4 player co-op, rebuilt around the NSDF's own Furies (Concept C, Docs/MISN14_COOP.md).
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misn14Mission.cpp (References/Misn14Source/),
-- plus the shipped 1.5 behaviour (BZ1/1.5 Misn14Mission::Execute): the two power plants surrender with
-- the base, rescued pilots get SetIndependence(guy, 0) before Defend, SetAIP names the CCA team.
-- All disabled statements remain below as original C++ comments.
-- Everything the campaign adds lives between "-- CR <name> >>" / "-- CR <name> <<" marker lines
-- (Tools/Test-Misn14SourceParity.py strips them); each substitution outside the markers is an explicit
-- delta in that test. Only the campaign leader (or offline play) runs the mission body.

local NEVER = 99999.0
local function NewState()
    return {
        -- bools (including unused source fields, for cut-content reconstruction)
        start_done = false, camera1 = false, camera2 = false, camera3 = false,
        alien_warning = false, alien_attack = false, cca_surrender = false,
        gen_message = false, rescue_message = false, rescue_start = false,
        rescue_reminder = false, found = false, pick_up = false,
        won = false, lost = false,
        finishcam1 = false, finishcam2 = false, finishcam3 = false,
        rescuecam1 = false, rescuecam2 = false, rescuecam3 = false,
        rescue1 = false, rescue2 = false, rescue3 = false,
        -- floats. Native Load initializes even the two not assigned in Setup.
        camera_time = NEVER, alien_time = NEVER, pick_up_time = NEVER,
        beacon_time1 = NEVER, beacon_time2 = NEVER, beacon_time3 = NEVER,
        rescue_finish1 = NEVER, rescue_finish2 = NEVER, rescue_finish3 = NEVER,
        next_second = NEVER,
        -- Initialize the darned handles. audmsg is an audio message in Lua,
        -- not an object handle; nil represents native NULL for all of these.
        beacon1 = nil, beacon2 = nil, beacon3 = nil, audmsg = nil,
        player = nil, recy = nil, cam1 = nil, cam2 = nil, cam3 = nil, cam4 = nil,
        erecy = nil, base = nil, apc = nil, guy1 = nil, guy2 = nil, guy3 = nil,
        tow1 = nil, tow2 = nil, tow3 = nil, tow4 = nil,
        -- integers
        wave_count = 0,
    }
end
local M = NewState()

-- Native distance queries with nonexistent objects return a very large distance.
-- BUGFIX / Lua adaptation: never feed nil/removed/dead objects to the overloaded
-- Lua GetDistance. Otherwise an absent APC can trigger a pickup or raise an error.
-- Live-object thresholds and their order are unchanged; absent objects are far away.
local function Distance(a, b)
    if a == nil or a == 0 or b == nil or b == 0 then return math.huge end
    if type(b) == "string" then
        if not IsAlive(a) then return math.huge end
        return GetDistance(a, b)
    end
    if not IsAlive(a) or not IsAlive(b) then return math.huge end
    return GetDistance(a, b)
end

local function IsOdfBase(h, name)
    return IsValid(h) and (IsOdf(h, name) or IsOdf(h, name .. ".odf"))
end

-- CR co-op layer >>
-- EXU Initialization (the co-op layer needs the bundled multiplayer hooks).
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})
local exu = require("exu")
-- Native MultST Init precedes Start. The authored base is the Recycler Texas (team 1), so no human team
-- keeps a starting recycler: the base is shared and host-authoritative.
if type(IsNetGame) == "function" and IsNetGame() then
    assert(exu.DisableStartingRecycler and exu.GetMyNetID,
        "misn14 co-op requires the bundled EXU multiplayer hooks")
    exu.DisableStartingRecycler()
end
local subtit = require("ScriptSubtitles")
-- CR PDA >>
-- PersistentConfig owns the PDA (X), subtitle/UI settings and AutoSave. Script
-- locals reset when a save loads, so Update initializes it once per Lua state.
-- One table local keeps the main chunk under Lua 5.1's 200-local limit.
local missionPda = { config = require("PersistentConfig"), ready = false }
function missionPda.Init()
    missionPda.ready = true
    missionPda.config.Initialize()
end
function missionPda.Update(cinematicActive)
    if not missionPda.ready then missionPda.Init() end
    missionPda.config.UpdateInputs(cinematicActive)
    missionPda.config.UpdateHeadlights()
end
function missionPda.Object(h)
    if missionPda.ready and h ~= nil then missionPda.config.OnObjectCreated(h) end
end
-- CR PDA <<
local CRCoop = require("CRCoop")
local CRWire = require("CRWire")
-- CR co-op layer <<
-- CR team map >>
-- Humans occupy teams 1-4 in co-op, so every DLL team that is not the player's moves off them:
--   CCA (DLL team 2)                         -> ENEMY_TEAM 5 (Build-CoopMap.py moved the authored base)
--   Furies (DLL team 3)                      -> FURY_TEAM 6
--   rescued NSDF pilots, the surrendered CCA -> SURVIVOR_TEAM 7 (allied with every human, never with 5)
-- The DLL gave the surrendered base and towers to team 1; they now go to team 7 (owner decision).
local LEADER_TEAM, ENEMY_TEAM, FURY_TEAM, SURVIVOR_TEAM = 1, 5, 6, 7
-- The native AiMission supplies the CCA strategic AI (misn14.aip). LuaMission must enable it at chunk
-- load, before the engine runs DR_AI_Init: a later SetAIControl (Start runs after it) leaves the team
-- flagged but without an AI team record and kills the host (misn08 co-op live run). SetAIP stays in
-- Update, like the DLL, and names the team (the shipped 1.5 exe passes 2).
SetAIControl(ENEMY_TEAM, true)
-- CR team map <<
-- CR Titan weather hook >>
-- The single wiring point for the Titan weather director (built separately; this file never edits it).
-- When a module named CRTitanWeather exists and exports MissionHook(event, ...), it receives:
--   "init"  (context)   once on every peer: { authority = bool, mission = "misn14",
--                       send = function(op, ...) or nil (host only; op must start with "Titan") }
--   "update"(dt)        every frame on every peer once the session is ready
--   "beat"  (name)      host/offline only: "start", "activation", "rogue", "wave", "surrender",
--                       "rescue_cca", "win", "lose"
--   "net"   (op, ...)   a guest received a host "Titan*" presentation event
--   "save"  ()          host/offline: returns a value stored in M.titanWeather
--   "load"  (value)     host/offline: the stored value after a load
--   "object"(handle)    every AddObject
--   "shutdown"()        before a co-op re-initialization
-- Every call is pcall-protected: a missing or broken director can never stop the mission.
local Environment = require("Environment")
local TitanWeather, TitanSensorDirector
do
    local ok, mod = pcall(require, "CRTitanWeather")
    if ok and type(mod) == "table" then
        TitanSensorDirector = mod
        if type(mod.MissionHook) == "function" then
            TitanWeather = mod
        elseif type(mod.Init) == "function" and type(mod.Update) == "function" then
            -- The director on main (Docs/TITAN_WEATHER.md) exposes Init/Update/ApplyNetEvent rather than a
            -- MissionHook: adapt the hook events onto its API here, so the mission logic stays untouched.
            local sitesOk, sites = pcall(require, "CRTitanSites14")
            if not sitesOk then sites = nil end
            local seedHolder = {}
            local announced = false
            local function call(name, ...)
                if type(mod[name]) == "function" then return mod[name](...) end
            end
            local BEATS = {
                start = function() call("SetTargetLevel", 2) end,
                activation = function() call("Roll", 70, 0.9) end,         -- a haze bank as the Furies wake
                rogue = function() call("ForceLevel", 3, 120, 15) end,    -- drizzle over the turn
                surrender = function() call("SetTargetLevel", 3) end,
                rescue_cca = function() call("ReleaseForcedLevel"); call("SetTargetLevel", 2) end,
                win = function() call("ReleaseForcedLevel"); call("SetTargetLevel", 1) end,
            }
            TitanWeather = { MissionHook = function(event, a, b, ...)
                if event == "init" then
                    local context = a or {}
                    seedHolder.authority = context.authority
                    call("Init", { authority = context.authority, seed = seedHolder.seed, sites = sites,
                        startLevel = 1, targetLevel = 2, send = context.send })
                    if context.authority then seedHolder.seed = mod.Seed end
                elseif event == "update" then
                    if seedHolder.authority and not announced and CRCoop.IsNetworkGame() and CRCoop.IsSessionReady() then
                        announced = true
                        call("AnnounceState")
                    end
                    call("Update", a)
                elseif event == "net" then
                    return call("ApplyNetEvent", a, b, ...)
                elseif event == "beat" then
                    if BEATS[a] then BEATS[a]() end
                elseif event == "save" then
                    return { seed = mod.Seed, state = call("Save") }
                elseif event == "load" then
                    if type(a) == "table" then
                        seedHolder.seed = a.seed
                        if a.state ~= nil then call("Load", a.state) end
                    end
                elseif event == "object" then
                    call("OnObjectCreated", a)
                elseif event == "shutdown" then
                    announced = false
                    call("Shutdown")
                end
            end }
        end
    end
end
local function TitanHook(event, ...)
    if event == "init" then
        -- Keep native Titan lighting/daylight while sharing atmosphere/sensors.
        Environment.Init({ nativeBaseline = true })
        Environment.BindWeatherSensors("Titan", TitanSensorDirector)
    end
    if not TitanWeather then return nil end
    local ok, result = pcall(TitanWeather.MissionHook, event, ...)
    if ok then
        if event == "update" then Environment.Update((...)) end
        if event == "load" and Environment.InvalidateRenderer then Environment.InvalidateRenderer() end
        if event == "object" then Environment.OnObjectCreated((...)) end
        return result
    end
    if not M.titanHookError then
        M.titanHookError = true
        print("[misn14] Titan weather hook failed: " .. tostring(result))
    end
end
local function IsTitanOp(op) return type(op) == "string" and op:sub(1, 5) == "Titan" end
-- CR Titan weather hook <<
-- CR co-op layer >>
-- Co-op presentation uses the established misn03/misn12 E/A and C transport.
-- Only the campaign leader runs the mission body below; HUD/audio/removal/timer/camera/
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
    RemoveObject = RemoveObject, SetTeamNum = SetTeamNum,
    -- Resolve result hooks after PersistentConfig.Initialize installs cleanup.
    SucceedMission = function(...) return _G.SucceedMission(...) end,
    FailMission = function(...) return _G.FailMission(...) end,
    CameraReady = CameraReady, CameraPath = CameraPath, CameraObject = CameraObject,
    CameraFinish = CameraFinish, CameraCancelled = CameraCancelled,
    StopAudioMessage = StopAudioMessage,
    Play = subtit.Play, Queue = subtit.Queue, Stop = subtit.Stop,
}
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

local function ResetPresentation()
    events, acknowledgements, receivedEvent = {}, {}, 0
    pendingSeq, pendingSince = nil, nil
    nextEventSend, nextCameraSend = 0, 0
    cameraFrame, cameraGeneration, cameraSerial = nil, 0, 0
    remoteCamera, remoteCameraSerial, localCameraGeneration = nil, 0, 0
    cameraWaitSince, cameraGaveUp, cameraLast = nil, false, nil
    announced, gaveUp = {}, {}
    cameraSkipped, localCameraActive = false, false
end

local function FromLeader(from)
    local player = CRCoop.GetPlayers()[from]
    return player and player.team == LEADER_TEAM
end

local function ApplyPresentation(op, ...)
    if IsTitanOp(op) then
        -- Weather events carry no handles: never labelled, never waited on.
        return TitanHook("net", op, ...)
    end
    if op == "Label" then
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
    RemoveObject = true, Label = true, SetTeamNum = true }
local WAIT_OPS = { SetObjectiveOn = true, SetObjectiveName = true, Label = true, SetTeamNum = true }
local GONE = "!"
-- Guests WAIT for the real object. This is only a never-hang guard: when it fires the
-- guest logs "[coop] unresolved ..." and counts it in M.coopUnresolved (the harness probe
-- reads that and expects zero).
local RESOLVE_TIMEOUT = 15

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
        pcall(SetLabel, handle, "crco14_" .. labelSerial)
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
local function RemoveObject(...) return Present("RemoveObject", ...) end
-- Authored buildings are local map objects, so their team changes must be
-- applied explicitly on each peer. Dynamic craft keep native replication.
local function SetSurrenderTeam(handle) return Present("SetTeamNum", handle, SURVIVOR_TEAM) end
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
local function SucceedMission(...)
    TitanHook("beat", "win")
    return EndMission("SucceedMission", ...)
end
local function FailMission(...)
    TitanHook("beat", "lose")
    return EndMission("FailMission", ...)
end

local function CameraReady()
    cameraGeneration = cameraGeneration + 1
    cameraSkipped = false
    -- One shot at a time: a new shared shot (a rescue camera over the Fury scene) replaces the old one,
    -- so the native camera stack stays balanced offline too.
    if localCameraActive then native.CameraFinish() end
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
        -- Hold the last resolved frame only while its objects still exist (a target that died since
        -- must never reach a native camera call).
        if localCameraActive and cameraLast and (cameraLast[1] == nil or IsValid(cameraLast[1]))
            and IsValid(cameraLast[2]) then
            return true, cameraLast[1], cameraLast[2]
        end
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
    -- Use the resolved objects only: a nil target must never fall back to the wire text.
    if cam.kind == "O" then
        if not localCameraActive then
            native.CameraReady()
            localCameraActive = true
        end
        native.CameraObject(subject, cam.x, cam.y, cam.z, target)
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
        NativeCameraPath(cam.path, cam.height, cam.speed, target)
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
                    Send(id, "E", CRWire.Pack(seq, event.op, event.ttl, unpackArgs(EventArgs(event), 1, event.n)))
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
            Send(0, "C", CRWire.Pack(cameraSerial, cameraGeneration, unpackArgs(WireCameraFrame(cameraFrame))))
        else
            Send(0, "C", cameraSerial, cameraGeneration, "")
        end
    end
end

local ReceivePresentationDecoded = nil
-- Presentation packets are CRWire-packed: reassemble chunked strings first.
local function ReceivePresentation(from, kind, ...)
    return ReceivePresentationDecoded(from, kind, CRWire.Unpack(...))
end
function ReceivePresentationDecoded(from, kind, ...)
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
    if seq == receivedEvent + 1 and (native[op] or IsTitanOp(op) or op == "Label") then
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

-- Presentation adapter ends.

-- The DLL's AudioMessage(file) is the shared radio line: the leader plays it and every peer hears it with
-- its subtitle. ScriptSubtitles.Play stops whatever line is still playing, while native AudioMessage
-- queued; so a line that starts while the previous one is still talking is queued behind it (the leader
-- decides, guests follow the same op). Returns the native audio handle on the leader.
local lastAudio
local function AudioMessage(file)
    local busy = lastAudio ~= nil and type(IsAudioMessageDone) == "function" and not IsAudioMessageDone(lastAudio)
    local handle = busy and subtit.Queue(file) or subtit.Play(file)
    if handle ~= nil then lastAudio = handle end
    return handle
end
-- StopAudioMessage on a shared line stops the subtitle/audio sequence on every peer.
local function StopAudioMessage(message)
    if message == nil then return end
    if CRCoop.IsNetworkGame() then subtit.Stop() else native.StopAudioMessage(message) end
end
-- CR co-op layer <<
-- CR co-op layer >>
local function ConfigureAlliances()
    CRCoop.ApplyCoopAlliances(ENEMY_TEAM)
    -- Survivors and the surrendered base fight beside every human; the Furies are nobody's friend.
    for team = 1, 4 do
        Ally(team, SURVIVOR_TEAM); Ally(SURVIVOR_TEAM, team)
        UnAlly(team, FURY_TEAM); UnAlly(FURY_TEAM, team)
    end
    UnAlly(ENEMY_TEAM, SURVIVOR_TEAM); UnAlly(SURVIVOR_TEAM, ENEMY_TEAM)
    UnAlly(ENEMY_TEAM, FURY_TEAM); UnAlly(FURY_TEAM, ENEMY_TEAM)
    UnAlly(SURVIVOR_TEAM, FURY_TEAM); UnAlly(FURY_TEAM, SURVIVOR_TEAM)
end

local function IsHumanTeamNumber(team)
    return type(team) == "number" and team >= 1 and team <= 4
end

-- Co-op trigger helpers. Offline CRCoop iterates just the local player, so each reproduces the DLL's
-- single-player test exactly. Every distance goes through the mission's Distance guard.
local function AnyPlayerWithin(target, distance)
    return CRCoop.AnyPlayerSatisfies(function(h) return Distance(h, target) < distance end)
end

-- The player closest to `from` (handle, distance), or nil when no player has a usable handle.
local function NearestPlayer(from)
    local best, bestDistance = nil, math.huge
    CRCoop.ForEachPlayerHandle(function(h)
        local distance = Distance(h, from)
        if best == nil or distance < bestDistance then best, bestDistance = h, distance end
    end)
    return best, bestDistance
end

-- Human teams in the session (1 offline).
local function HumanCount()
    return math.max(1, CRCoop.ForEachHumanTeam(function() end))
end
local EXTRA_MAX = 3
local function ExtraHumans()
    return math.min(EXTRA_MAX, math.max(0, HumanCount() - 1))
end
-- CR co-op layer <<
-- CR rescue >>
-- The DLL tracked the last team-1 APC. In co-op the base is the host's team 1 (guests have no factory),
-- but a guest can drive an APC too, so a rescue carrier is the tracked APC or any human piloting an avapc.
-- The DLL froze nothing; the port froze the carrier at pickup. Here the carrier that reaches the CCA
-- base becomes M.apc (and must bring the scientists home).
local function CarrierNear(target, distance)
    if Distance(M.apc, target) < distance then return M.apc end
    local found
    CRCoop.ForEachPlayerHandle(function(h)
        if found == nil and IsOdfBase(h, "avapc") and Distance(h, target) < distance then found = h end
    end)
    return found
end

local function HasCarrier()
    if M.apc ~= nil then return true end
    return CRCoop.AnyPlayerSatisfies(function(h) return IsOdfBase(h, "avapc") end)
end

-- The shipped 1.5 exe gives every rescued pilot SetIndependence(guy, 0) before Defend(guy, 1) so they hold
-- at the beacon; the BZ2-source port lost it. Only the stock aspilo (PersonFriend/PersonEnemy unit AI) is
-- ever passed here (SetIndependence on non-unit AI corrupts the heap: Docs/BZR_LUA_AGENT_REFERENCE.md).
local function HoldSurvivor(guy)
    if IsAlive(guy) and IsOdfBase(guy, "aspilo") then
        SetIndependence(guy, 0)
    end
end
-- CR rescue <<
-- CR fury squad >>
-- Concept C (owner decision): the NSDF brought the Fury relics recovered on Io (misn10/11) to Titan. A
-- dormant squad of NSDF Furies stands beside the Texas from the start (two per human team, on that team).
-- FURY_ACTIVATE_S after the opening briefing the host runs the activation scene for everyone (Collins
-- 1402, Buzz 1423/1424) and hands the squad over: each Fury follows its human at priority 0, so the
-- player can command it. FURY_CONTROL_S later control fails (Buzz 1425, Collins 1426): the squad switches
-- to FURY_TEAM 6 and turns on whatever is nearest, NSDF or CCA.
-- The squad is the cut stock NSDF Fury avsav (owner decision), shipped as the CR copy ODF/avsav14.odf:
-- stock avsav names aiName "SAVFriend", which Redux does not register, so it has no AI on a human team;
-- the copy is a wingman with TankFriend/TankEnemy AI on the stock avsav mesh. Loss of control re-teams
-- the same units (SetTeamNum) instead of swapping in hostile hvsav: the Furies the players just commanded
-- are the ones that turn, keep their damage, and nothing pops in under the camera; their attacks are
-- driven by UpdateRogueSquad because a re-teamed unit keeps the AI process it was built with.
local FURY_SQUAD_ODF = "avsav14"
local FURY_SQUAD_PER_HUMAN = 2
local FURY_ACTIVATE_S = 40.0     -- after the opening objective (beacon 1 is up 15 s after it)
local FURY_SCENE_S = 15.0        -- 1402 (4.4 s) + 1423 (5.5 s) + 1424 (3.6 s), queued
local FURY_CONTROL_S = 75.0      -- the brief command window
local FURY_LOSS_SCENE_S = 7.0    -- 1425 (6.4 s) over a shot of the squad turning
local FURY_RETARGET_S = 6.0
local FURY_REPICK_S = 30.0
local FURY_CAM_X, FURY_CAM_Y, FURY_CAM_Z = 1500, 700, 1500
-- Offsets (m) of the dormant pad from the Texas, in its local frame-free world axes: east and north of the
-- authored start, clear of the drop-zone buoys (west) and the turret tank (south).
local FURY_PAD = { { 45, 35 }, { 65, 35 }, { 85, 35 }, { 45, 60 }, { 65, 60 }, { 85, 60 }, { 105, 35 }, { 105, 60 } }

local function TerrainY(x, z, fallback)
    if type(GetTerrainHeightAndNormal) == "function" then
        local ok, height = pcall(GetTerrainHeightAndNormal, SetVector(x, 0, z))
        if ok and type(height) == "number" then return height end
    end
    return fallback or 0
end

local function LiveSquad()
    local live = {}
    for _, entry in ipairs(M.fury_squad or {}) do
        if IsAlive(entry.unit) then live[#live + 1] = entry end
    end
    return live
end

local function SquadLead()
    for _, entry in ipairs(M.fury_squad or {}) do
        if IsAlive(entry.unit) then return entry.unit end
    end
end

-- Host: build the dormant squad (locked at priority 1 so nobody orders it yet) a few seconds in, never in
-- the load frame (the load frame's shared GEO table can be full; Docs/BZR_LUA_AGENT_REFERENCE.md rule 13).
local FURY_BUILD_AFTER_S = 3.0
local function BuildFurySquad()
    if M.fury_built or GetTime() < FURY_BUILD_AFTER_S then return end
    M.fury_built = true
    M.fury_squad = {}
    if not IsAlive(M.recy) then return end
    local origin = GetPosition(M.recy)
    local slot = 0
    CRCoop.ForEachHumanTeam(function(team)
        for _ = 1, FURY_SQUAD_PER_HUMAN do
            slot = slot + 1
            local pad = FURY_PAD[slot]
            if pad then
                local x, z = origin.x + pad[1], origin.z + pad[2]
                local unit = BuildObject(FURY_SQUAD_ODF, team, SetVector(x, TerrainY(x, z, origin.y), z))
                if IsValid(unit) then
                    Stop(unit, 1)
                    M.fury_squad[#M.fury_squad + 1] = { unit = unit, team = team }
                end
            end
        end
    end)
end

local function PlayerHandleOnTeam(team)
    local found
    CRCoop.ForEachPlayerHandle(function(h)
        if found == nil and IsValid(h) and GetTeamNum(h) == team then found = h end
    end)
    return found
end

-- Transfer: each Fury follows its own human at priority 0 (commandable).
local function HandOverSquad()
    for _, entry in ipairs(LiveSquad()) do
        local human = PlayerHandleOnTeam(entry.team)
        if human then Follow(entry.unit, human, 0) else Stop(entry.unit, 0) end
    end
end

-- Rogue targeting. Odd squad slots hunt the CCA first, even slots the NSDF, so the Furies fall on both
-- sides as the design asks. Rescued pilots are never picked on purpose (they are not craft targets
-- here), and the invulnerable surrendered barracks only draws them when nothing else is left.
local function NearestOf(unit, wantCca)
    local best, bestDistance
    local function consider(h)
        if IsAlive(h) and not IsOdfBase(h, "aspilo") then
            local d = Distance(unit, h)
            if d < math.huge and (best == nil or d < bestDistance) then best, bestDistance = h, d end
        end
    end
    if wantCca then
        for h in AllCraft() do
            if GetTeamNum(h) == ENEMY_TEAM then consider(h) end
        end
        if M.cca_surrender then
            for _, h in ipairs({ M.tow1, M.tow2, M.tow3, M.tow4, M.pow1, M.pow2 }) do consider(h) end
        end
    else
        CRCoop.ForEachPlayerHandle(function(h) consider(h) end)
        for h in AllCraft() do
            if IsHumanTeamNumber(GetTeamNum(h)) then consider(h) end
        end
    end
    return best
end

local function RogueTarget(unit, slot)
    local wantCca = (slot % 2) == 1
    return NearestOf(unit, wantCca) or NearestOf(unit, not wantCca)
end

local function TurnSquadRogue()
    for i, entry in ipairs(M.fury_squad or {}) do
        if IsAlive(entry.unit) then
            SetTeamNum(entry.unit, FURY_TEAM)
            entry.target = nil
            entry.picked = 0
            local target = RogueTarget(entry.unit, i)
            if target then
                Attack(entry.unit, target, 1)
                entry.target = target
                entry.picked = GetTime()
            end
        end
    end
end

local function UpdateRogueSquad()
    if not M.fury_rogue or GetTime() < (M.fury_retarget or 0) then return end
    M.fury_retarget = GetTime() + FURY_RETARGET_S
    for i, entry in ipairs(M.fury_squad or {}) do
        if IsAlive(entry.unit) then
            if not IsAlive(entry.target) or GetTime() - (entry.picked or 0) > FURY_REPICK_S then
                local target = RogueTarget(entry.unit, i)
                if target and target ~= entry.target then Attack(entry.unit, target, 1) end
                entry.target, entry.picked = target, GetTime()
            end
        end
    end
end

-- Host/offline: the activation -> control -> loss sequence. Runs only after the opening briefing.
local function UpdateFurySquad()
    if not M.start_done then return end
    BuildFurySquad()
    -- A stock shared shot (rescue APC, CCA base) that started this frame replaced the Fury shot.
    if M.fury_scene and (M.rescuecam1 or M.finishcam1 or M.camera3) then M.fury_scene = false end
    if M.fury_phase == nil then
        if M.objective_time ~= nil then
            M.fury_phase = "waiting"
            M.fury_time = M.objective_time + FURY_ACTIVATE_S
        end
        return
    end
    local now = GetTime()
    if M.fury_phase == "waiting" then
        -- Never stack the activation on top of another shared shot (the rescue APC cameras).
        if now > M.fury_time and not M.camera1 and not M.camera2 and not M.camera3
            and not M.rescuecam1 and not M.finishcam1 then
            M.fury_phase = "activating"
            M.fury_time = now + FURY_SCENE_S
            local lead = SquadLead()
            if lead then
                CameraReady()
                M.fury_scene = true
            end
            M.audmsg = AudioMessage("misn1402.wav")
            AudioMessage("misn1423.wav")
            AudioMessage("misn1424.wav")
            TitanHook("beat", "activation")
        end
    elseif M.fury_phase == "activating" then
        local lead = SquadLead()
        if M.fury_scene and lead then CameraObject(lead, FURY_CAM_X, FURY_CAM_Y, FURY_CAM_Z, lead) end
        if now > M.fury_time or (M.fury_scene and (CameraCancelled() or lead == nil)) then
            if M.fury_scene then
                CameraFinish()
                M.fury_scene = false
            end
            HandOverSquad()
            M.fury_phase = "control"
            M.fury_time = now + FURY_CONTROL_S
            M.fury_control_started = now
        end
    elseif M.fury_phase == "control" then
        if now > M.fury_time and not M.rescuecam1 and not M.finishcam1 and not M.camera3 then
            M.fury_phase = "losing"
            M.fury_time = now + FURY_LOSS_SCENE_S
            local lead = SquadLead()
            if lead then
                CameraReady()
                M.fury_scene = true
            end
            AudioMessage("misn1425.wav")
        end
    elseif M.fury_phase == "losing" then
        local lead = SquadLead()
        if M.fury_scene and lead then CameraObject(lead, FURY_CAM_X, FURY_CAM_Y, FURY_CAM_Z, lead) end
        if now > M.fury_time or (M.fury_scene and (CameraCancelled() or lead == nil)) then
            if M.fury_scene then
                CameraFinish()
                M.fury_scene = false
            end
            TurnSquadRogue()
            M.fury_rogue = true
            M.fury_rogue_time = now
            M.fury_phase = "rogue"
            AudioMessage("misn1426.wav")
            TitanHook("beat", "rogue")
        end
    end
    UpdateRogueSquad()
end
-- CR fury squad <<
-- CR fury waves >>
-- The DLL sent three hvsav Furies from one of three spawn triplets every 180 s from 720 s after the
-- intro. Concept C keeps the triplets and the cadence and makes them the rogue Fury onslaught:
--   * the first wave comes FURY_FIRST_WAVE_S after the intro (after the squad has turned), on FURY_TEAM;
--   * +1 hvsav per extra human (owner decision), from the spare alien points;
--   * from wave 4, hvsat Fury Tanks join (1, +1 with 3+ humans) (owner decision);
--   * never more than FURY_LIVE_CAP live Furies of either kind, squad included (owner decision: 12);
--   * no pop-in: a Fury is only built at a point no human is within FURY_CLEAR_M of (alien1/3/5 sit in the
--     CCA base, alien2/4/6 near the NSDF drop zone); otherwise at the farthest unwatched corner of the play
--     area; if every candidate is watched the wave waits FURY_RETRY_S;
--   * each wave splits its targets between the CCA and the nearest NSDF (priority 0: the Fury AI keeps the
--     initiative), which is what breaks the CCA (see CR surrender).
local FURY_WAVES = true
local FURY_FIRST_WAVE_S = 420.0
local FURY_WAVE_PERIOD_S = 180.0
local FURY_RETRY_S = 30.0
local FURY_LIVE_CAP = 12
local FURY_CLEAR_M = 400.0
local FURY_TANK_FROM_WAVE = 4
local FURY_TRIPLETS = {
    { "alien1", "alien2", "alien5" },
    { "alien3", "alien4", "alien1" },
    { "alien5", "alien6", "alien3" },
}
local FURY_ALL_POINTS = { "alien1", "alien2", "alien3", "alien4", "alien5", "alien6" }
-- The "world" AOI polygon corners pulled 150 m inward (Missions/misn14.bzn): the far fallback spawns.
local FURY_CORNERS = { { 1550, 101130 }, { 3620, 101150 }, { 3790, 98880 }, { 1480, 98800 } }

local function LiveFuries()
    local total = 0
    for _, entry in ipairs(M.fury_squad or {}) do
        if M.fury_rogue and IsAlive(entry.unit) then total = total + 1 end
    end
    for _, unit in ipairs(M.fury_wave_units or {}) do
        if IsAlive(unit) then total = total + 1 end
    end
    return total
end

local function Watched(where)
    local _, distance = NearestPlayer(where)
    return distance < FURY_CLEAR_M
end

-- Distance from the nearest human to a world position (a vector, not a handle or path).
local function NearestPlayerToPosition(position)
    local best = math.huge
    CRCoop.ForEachPlayerHandle(function(h)
        if IsAlive(h) then best = math.min(best, GetDistance(h, position)) end
    end)
    return best
end

local function CornerSpawn(used)
    local best, bestDistance
    for i, corner in ipairs(FURY_CORNERS) do
        if not used["corner" .. i] then
            local position = SetVector(corner[1], TerrainY(corner[1], corner[2], 0), corner[2])
            local distance = NearestPlayerToPosition(position)
            if distance >= FURY_CLEAR_M and (best == nil or distance > bestDistance) then
                best, bestDistance = { key = "corner" .. i, where = position }, distance
            end
        end
    end
    return best
end

-- The spawn list for `count` Furies: the wave's own triplet first, then the spare alien points, then the
-- corners; each unwatched, each used once (corners may be reused once every point is taken).
local function FurySpawns(triplet, count)
    local spawns, used = {}, {}
    local function try(name)
        if #spawns < count and not used[name] and not Watched(name) then
            used[name] = true
            spawns[#spawns + 1] = name
        end
    end
    for _, name in ipairs(triplet) do try(name) end
    for _, name in ipairs(FURY_ALL_POINTS) do try(name) end
    while #spawns < count do
        -- Corners are used once each, then reused (several Furies at one far corner is fine: nobody sees it).
        local corner = CornerSpawn(used) or CornerSpawn({})
        if corner == nil then break end
        used[corner.key] = true
        spawns[#spawns + 1] = corner.where
    end
    return spawns
end

local function FuryWaveOdfs(wave)
    -- The restored light fighter is the main wave unit; retain one heavy SAV.
    local odfs = { "hvsav", "crfraz", "crfraz" }
    for _ = 1, ExtraHumans() do odfs[#odfs + 1] = "crfraz" end
    if wave >= FURY_TANK_FROM_WAVE then
        odfs[#odfs + 1] = "hvsat"
        if HumanCount() >= 3 then odfs[#odfs + 1] = "hvsat" end
    end
    return odfs
end

-- true when the wave happened (even if the cap let only part of it, or none, of it be built).
local function SpawnFuryWave(wave)
    M.fury_wave_units = M.fury_wave_units or {}
    local odfs = FuryWaveOdfs(wave)
    local room = math.max(0, FURY_LIVE_CAP - LiveFuries())
    local count = math.min(room, #odfs)
    if count == 0 then return true end
    local spawns = FurySpawns(FURY_TRIPLETS[math.random(1, #FURY_TRIPLETS)], count)
    if #spawns == 0 then return false end
    -- Tanks are the last entries; keep them when the cap trims the wave.
    local built = {}
    for i = 1, #spawns do
        local odf = odfs[#odfs - #spawns + i] or "crfraz"
        local unit = BuildObject(odf, FURY_TEAM, spawns[i])
        if IsValid(unit) then
            M.fury_wave_units[#M.fury_wave_units + 1] = unit
            built[#built + 1] = unit
        end
    end
    for i, unit in ipairs(built) do
        local target = NearestOf(unit, (i % 2) == 1) or NearestOf(unit, (i % 2) ~= 1)
        if target then Attack(unit, target, 0) end
    end
    -- Forget dead units so the list stays short over a long mission.
    local live = {}
    for _, unit in ipairs(M.fury_wave_units) do if IsAlive(unit) then live[#live + 1] = unit end end
    M.fury_wave_units = live
    TitanHook("beat", "wave")
    return true
end
-- CR fury waves <<
-- CR surrender >>
-- Concept C: the CCA surrender is a consequence of the Fury onslaught. Besides the DLL's third wave, the CCA
-- also surrenders as soon as the rogue Furies have broken its production (its Recycler, the DLL's unused
-- erecy, or its Unit Factory is destroyed after the squad turned).
local function CcaBroken()
    if not M.fury_rogue then return false end
    return (M.erecy ~= nil and not IsAlive(M.erecy)) or (M.ccamuf ~= nil and not IsAlive(M.ccamuf))
end
-- CR surrender <<
-- CR cut VO >>
-- Restored lines (all unused by the DLL and the exe; every Redux language archive ships them):
--   1402/1423/1424 activation scene, 1425/1426 loss of control (CR fury squad);
--   1427 Collins "I know you have a situation on your hands, but rescue those survivors": once,
--        NAG_1427_S after the squad turned, while a beacon is still waiting;
--   1420 Collins "Get those men, Commander": once per beacon left waiting NAG_1420_S.
local NAG_1427_S, NAG_1420_S = 120.0, 180.0

local function PendingBeacon()
    if M.beacon1 ~= nil and not M.rescue1 and IsAlive(M.beacon1) then return 1 end
    if M.beacon2 ~= nil and not M.rescue2 and IsAlive(M.beacon2) then return 2 end
    if M.beacon3 ~= nil and not M.rescue3 and IsAlive(M.beacon3) then return 3 end
end

local function UpdateRescueNags()
    if M.lost or M.won then return end
    local now = GetTime()
    local pending = PendingBeacon()
    if pending and M.fury_rogue and not M.nag1427 and now - M.fury_rogue_time > NAG_1427_S then
        M.nag1427 = true
        AudioMessage("misn1427.wav")
        return
    end
    M.beacon_seen = M.beacon_seen or {}
    M.nag1420 = M.nag1420 or {}
    if pending then
        if M.beacon_seen[pending] == nil then M.beacon_seen[pending] = now end
        if not M.nag1420[pending] and now - M.beacon_seen[pending] > NAG_1420_S then
            M.nag1420[pending] = true
            AudioMessage("misn1420.wav")
        end
    end
end
-- CR cut VO <<
-- CR objectives >>
-- The stock objective (misn1401.otf: establish a base, pick up survivors) stays; one CR line follows the
-- Fury squad and is updated on every peer when its state changes.
local OBJECTIVE_SECONDS = 8.0
local function FuryObjective()
    if M.fury_phase == "control" or M.fury_phase == "losing" then
        return "green", "Fury squad online: command your Furies."
    elseif M.fury_phase == "rogue" then
        return "red", "The Furies have gone rogue: they attack NSDF and CCA alike."
    end
end

local function UpdateObjectives()
    local color, text = FuryObjective()
    if color == nil then return end
    local state = color .. "|" .. text
    if M.objective_state == state then return end
    if M.objective_state == nil then
        AddObjective("misn14_furies", color, OBJECTIVE_SECONDS, text)
    else
        UpdateObjective("misn14_furies", color, OBJECTIVE_SECONDS, text)
    end
    M.objective_state = state
end
-- CR objectives <<
-- CR rally >>
-- Respawns rally at the Texas. Its loss fails the mission (misn1414), but until the result lands a respawn
-- must not rally at a corpse: drop the rally point and the native MultST spawn takes over.
local rallyDropped = false
local function UpdateRally()
    if rallyDropped then return end
    local recycler = GetHandle("avrecy-1_recycler")
    if recycler == nil or not IsAlive(recycler) then
        rallyDropped = true
        local respawn = CRCoop.GetRespawn()
        if respawn then respawn.SetRallyPoints({}) end
    end
end
-- CR rally <<
-- CR co-op layer >>
local titanStarted = false
local function InitializeCoop()
    CRCoop.Initialize({
        getLocalPlayerId = function() return exu.GetMyNetID and exu.GetMyNetID() end,
        leaderTeam = LEADER_TEAM, humanTeamMin = 1, humanTeamMax = 4,
        onOutOfLives = function() FailMission(GetTime() + 3.0) end,
        -- The Texas while it lives; UpdateRally drops the point when it dies.
        rallyPoints = { [0] = "avrecy-1_recycler" },
    })
    ConfigureAlliances()
    ResetPresentation()
    rallyDropped = false
    lastAudio = nil
    if titanStarted then TitanHook("shutdown") end
    titanStarted = false
end

-- Every peer, once the session is ready.
local function UpdateTitanWeather(dt)
    if not TitanWeather then return end
    if not titanStarted then
        titanStarted = true
        local net = CRCoop.IsNetworkGame()
        local authority = (not net) or CRCoop.IsAuthority()
        TitanHook("init", {
            authority = authority, mission = "misn14",
            send = (net and authority) and function(op, ...)
                if IsTitanOp(op) then
                    events[#events + 1] = { op = op, args = { ... }, n = select("#", ...), ttl = RESOLVE_TIMEOUT }
                end
            end or nil,
        })
        if authority and M.titanWeather ~= nil then TitanHook("load", M.titanWeather) end
        if authority then TitanHook("beat", "start") end
    end
    TitanHook("update", dt)
end
-- CR co-op layer <<

local function ApcCamera()
    -- BUGFIX: the native script blindly uses an APC destroyed during a short
    -- rescue shot. Release the camera if it disappears; rescue timers still run.
    local carrier = M.rescue_carrier or M.apc
    if IsAlive(carrier) then
        CameraObject(carrier, 1000, 1000, 1000, carrier)
    end
    return not IsAlive(carrier) or CameraCancelled() or GetTime() > M.camera_time
end

function Start()
    -- M is initialized at chunk load, before AddObject can discover a map APC.
    -- Do not reset it here and erase objects reported before Start.
-- CR co-op layer >>
    -- (The DLL port called SetAIControl here; it is a chunk-root call now, see CR team map.)
    InitializeCoop()
    subtit.Initialize()
    missionPda.Init()
-- CR co-op layer <<
end

function AddObject(h)
-- CR PDA >>
    missionPda.Object(h)
-- CR PDA <<
-- CR Titan weather hook >>
    if IsValid(h) then TitanHook("object", h) end
-- CR Titan weather hook <<
    -- The DLL kept the last team-1 APC. Co-op: any human team's APC (the shared base is team 1).
    if IsOdfBase(h, "avapc") and IsHumanTeamNumber(GetTeamNum(h)) then
        M.found = true
        -- BUGFIX: original `apc = h` replaced the scientist carrier every time
        -- another APC was built. Freeze the selected handle once pick_up begins:
        -- the same carrier must return home or die. Selection before pickup and
        -- the normal one-APC gameplay flow remain exactly as in the source.
        if not M.pick_up then M.apc = h end
    end
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

function Update(dt)
-- CR co-op layer >>
    subtit.Update()
    missionPda.Update(localCameraActive)
    CRCoop.Update()
    UpdatePresentationTransport()
    if M.coopResult or M.coopPendingResult then
        UpdateTitanWeather(dt)
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
    UpdateTitanWeather(dt)
    UpdateRally()
    if not CRCoop.IsAuthority() then return end
    if CRCoop.IsNetworkGame() and not M.coopBootstrapped then
        M.coopBootstrapped = true
        -- The authored offline placeholder must not remain beside the humans.
        local offlinePlayer = GetHandle("player0_wingman")
        if IsValid(offlinePlayer) and not CRCoop.IsHumanCraft(offlinePlayer) then RemoveObject(offlinePlayer) end
    end
-- CR co-op layer <<
    -- Original disabled native pointer declaration:
    --GameObject *fcycler,*ecycler;
    M.player = GetPlayerHandle()
    if not M.start_done then
        M.recy = GetHandle("avrecy-1_recycler")
        M.erecy = GetHandle("svrecy-1_recycler")
        M.base = GetHandle("sbbarr0_i76building")
        SetAIP("misn14.aip", ENEMY_TEAM)
        --AddPilot(1,10);
        AddPilot(ENEMY_TEAM, 30)
        SetScrap(1, 30)
        SetScrap(ENEMY_TEAM, 45)
        M.cam1 = GetHandle("apcamr0_camerapod")
        M.cam2 = GetHandle("apcamr1_camerapod")
        M.cam3 = GetHandle("apcamr2_camerapod")
        M.cam4 = GetHandle("apcamr3_camerapod")
        M.tow1 = GetHandle("sbtowe0_turret")
        M.tow2 = GetHandle("sbtowe1_turret")
        M.tow3 = GetHandle("sbtowe55_turret")
        M.tow4 = GetHandle("sbtowe56_turret")
-- CR surrender >>
        -- Shipped 1.5: the two power plants are fetched here and surrender with the base.
        M.pow1 = GetHandle("sblpow1_powerplant")
        M.pow2 = GetHandle("sblpow55_powerplant")
        M.ccamuf = GetHandle("svmuf0_factory")
-- CR surrender <<
        if IsValid(M.cam1) then SetObjectiveName(M.cam1, "Foothill Geysers") end
        if IsValid(M.cam2) then SetObjectiveName(M.cam2, "Canyon Geysers") end
        if IsValid(M.cam3) then SetObjectiveName(M.cam3, "CCA Base") end
        if IsValid(M.cam4) then SetObjectiveName(M.cam4, "Plateau Geysers") end
        M.start_done = true
        M.next_second = GetTime() + 1.0
        M.camera1 = true
        CameraReady()
        M.camera_time = GetTime() + 12.0
        M.audmsg = AudioMessage("misn1401.wav")
        if IsAlive(M.base) then
            SetMaxHealth(M.base, 100000.0)
            M.next_second = GetTime() + 1.0
        end
    end
    if M.camera1 then
        if IsValid(M.recy) then CameraPath("cam_path1", 2000, 1000, M.recy) end
    end
    if M.camera1 and (GetTime() > M.camera_time or CameraCancelled()) then
        -- Original disabled statement (the briefing was combined):
        -- StopAudioMessage(audmsg);
        -- Now the message is longer and see below
        M.camera1 = false
        M.camera2 = true
        M.camera_time = GetTime() + 15.0
        -- audmsg=AudioMessage("misn1402.wav");
        -- The above message is part of the first..
        -- (CR: misn1402 now opens the Fury activation scene, see CR fury squad.)
    end
    if M.camera2 then
        if IsValid(M.recy) then CameraPath("cam_path2", 2000, 500, M.recy) end
    end
    if M.camera2 and (GetTime() > M.camera_time or CameraCancelled()) then
        if M.audmsg ~= nil then StopAudioMessage(M.audmsg) end
        M.camera2 = false
        CameraFinish()
        ClearObjectives()
        AddObjective("misn1401.otf", "white")
        M.alien_time = GetTime() + 720.0 -- six minutes to alien arrival
        -- Source comment says six minutes, but the active value is 720 (twelve).
        -- Preserve the numeric value; do not restore an earlier shorter delay.
-- CR fury waves >>
        -- Concept C: the onslaught starts earlier, after the squad has turned (see CR fury waves).
        if FURY_WAVES then M.alien_time = GetTime() + FURY_FIRST_WAVE_S end
        M.objective_time = GetTime()
-- CR fury waves <<
        M.beacon_time1 = GetTime() + 15.0
    end
    --[[
        Rescue the
        NSDF
    ]]
    if GetTime() > M.beacon_time1 then
        AudioMessage("misn1416.wav")
        M.beacon_time1 = NEVER
        M.beacon1 = BuildObject("apcamr", 1, "rescue1")
        M.guy1 = BuildObject("aspilo", SURVIVOR_TEAM, "help1")
        M.guy2 = BuildObject("aspilo", SURVIVOR_TEAM, "help2")
        M.guy3 = BuildObject("aspilo", SURVIVOR_TEAM, "help3")
-- CR rescue >>
        HoldSurvivor(M.guy1); HoldSurvivor(M.guy2); HoldSurvivor(M.guy3)
-- CR rescue <<
        Defend(M.guy1, 1)
        Defend(M.guy2, 1)
        Defend(M.guy3, 1)
        SetObjectiveName(M.beacon1, "Rescue 1")
        SetObjectiveOn(M.beacon1)
    end
    if M.beacon1 ~= nil and AnyPlayerWithin(M.beacon1, 200.0)
        and not M.rescue_reminder and Distance(M.apc, M.beacon1) > 300.0 then
        --[[
            Bring in an APC to
            rescue the survivors.
        ]]
        AudioMessage("misn1415.wav")
        M.rescue_reminder = true
    end
    if not M.lost and M.beacon1 ~= nil and not M.rescue1
        and (not IsAlive(M.guy1) or not IsAlive(M.guy2) or not IsAlive(M.guy3)) then
        AudioMessage("misn1421.wav")
        FailMission(GetTime() + 15.0, "misn14l2.des")
        M.lost = true
    end
    if M.beacon1 ~= nil and HasCarrier() and not M.rescue1
        and CarrierNear(M.beacon1, 100.0) then
        M.rescue1 = true
-- CR rescue >>
        -- The camera follows the carrier that actually arrived (a guest-driven APC counts too).
        M.rescue_carrier = CarrierNear(M.beacon1, 100.0)
-- CR rescue <<
        Goto(M.guy1, M.beacon1)
        Goto(M.guy2, M.beacon1)
        Goto(M.guy3, M.beacon1)
        M.rescue_finish1 = GetTime() + 25.0
        AudioMessage("misn1409.wav")
        M.camera_time = GetTime() + 3.0
        CameraReady()
        M.rescuecam1 = true
    end
    if M.rescuecam1 then
        if ApcCamera() then
            CameraFinish()
            M.rescuecam1 = false
        end
    end
    if M.beacon1 ~= nil and M.rescue1 and M.rescue_finish1 < GetTime() then
        --[[
            We're done here
        ]]
        if IsAlive(M.guy1) then RemoveObject(M.guy1) end
        if IsAlive(M.guy2) then RemoveObject(M.guy2) end
        if IsAlive(M.guy3) then RemoveObject(M.guy3) end
        if IsAlive(M.beacon1) then RemoveObject(M.beacon1) end
        M.beacon_time2 = GetTime() + 10.0
        CameraReady()
        AudioMessage("misn1417.wav")
        M.finishcam1 = true
        M.rescue_finish1 = NEVER
        M.camera_time = GetTime() + 3.0
    end
    if M.finishcam1 then
        if ApcCamera() then
            CameraFinish()
            M.finishcam1 = false
        end
    end
    if GetTime() > M.beacon_time2 then
        M.beacon_time2 = NEVER
        M.beacon2 = BuildObject("apcamr", 1, "rescue2")
        M.guy1 = BuildObject("aspilo", SURVIVOR_TEAM, "help4")
        M.guy2 = BuildObject("aspilo", SURVIVOR_TEAM, "help5")
        M.guy3 = BuildObject("aspilo", SURVIVOR_TEAM, "help6")
-- CR rescue >>
        HoldSurvivor(M.guy1); HoldSurvivor(M.guy2); HoldSurvivor(M.guy3)
        -- Light tie to misn12 (owner decision): the second beacon is Razor flight's. Razor One got out of
        -- Europa; his wingman, Razor Two, went down here and is the pilot who speaks misn1418.
        if IsAlive(M.guy1) then SetObjectiveName(M.guy1, "Razor Two") end
-- CR rescue <<
        Defend(M.guy1, 1)
        Defend(M.guy2, 1)
        Defend(M.guy3, 1)
        SetObjectiveName(M.beacon2, "Rescue 2")
        SetObjectiveOn(M.beacon2)
    end
    if not M.lost and M.beacon2 ~= nil and not M.rescue2
        and (not IsAlive(M.guy1) or not IsAlive(M.guy2) or not IsAlive(M.guy3)) then
        M.lost = true
        AudioMessage("misn1421.wav")
        FailMission(GetTime() + 15.0, "misn14l2.des")
    end
    if M.beacon2 ~= nil and HasCarrier() and not M.rescue2
        and CarrierNear(M.beacon2, 100.0) then
        M.rescue2 = true
        Goto(M.guy1, M.beacon2)
        Goto(M.guy2, M.beacon2)
        Goto(M.guy3, M.beacon2)
        M.rescue_finish2 = GetTime() + 25.0
        AudioMessage("misn1409.wav")
    end
    if M.beacon2 ~= nil and M.rescue2 and M.rescue_finish2 < GetTime() then
        --[[
            We're done here
        ]]
        if IsAlive(M.guy1) then RemoveObject(M.guy1) end
        if IsAlive(M.guy2) then RemoveObject(M.guy2) end
        if IsAlive(M.guy3) then RemoveObject(M.guy3) end
        if IsAlive(M.beacon2) then RemoveObject(M.beacon2) end
        AudioMessage("misn1418.wav")
        M.rescue_finish2 = NEVER
        M.beacon_time3 = GetTime() + 10.0
    end
    if GetTime() > M.beacon_time3 then
        M.beacon_time3 = NEVER
        M.beacon3 = BuildObject("apcamr", 1, "rescue3")
        M.guy1 = BuildObject("aspilo", SURVIVOR_TEAM, "help7")
        M.guy2 = BuildObject("aspilo", SURVIVOR_TEAM, "help8")
        M.guy3 = BuildObject("aspilo", SURVIVOR_TEAM, "help9")
-- CR rescue >>
        HoldSurvivor(M.guy1); HoldSurvivor(M.guy2); HoldSurvivor(M.guy3)
-- CR rescue <<
        Defend(M.guy1, 1)
        Defend(M.guy2, 1)
        Defend(M.guy3, 1)
        SetObjectiveName(M.beacon3, "Rescue 3")
        SetObjectiveOn(M.beacon3)
    end
    if not M.lost and M.beacon3 ~= nil and not M.rescue3
        and (not IsAlive(M.guy1) or not IsAlive(M.guy2) or not IsAlive(M.guy3)) then
        M.lost = true
        AudioMessage("misn1421.wav")
        FailMission(GetTime() + 15.0, "misn14l2.des")
    end
    if M.beacon3 ~= nil and HasCarrier() and not M.rescue3
        and CarrierNear(M.beacon3, 100.0) then
        M.rescue3 = true
        Goto(M.guy1, M.beacon3)
        Goto(M.guy2, M.beacon3)
        Goto(M.guy3, M.beacon3)
        M.rescue_finish3 = GetTime() + 25.0
        AudioMessage("misn1409.wav")
    end
    if M.beacon3 ~= nil and M.rescue3 and M.rescue_finish3 < GetTime() then
        --[[
            We're done here
        ]]
        if IsAlive(M.guy1) then RemoveObject(M.guy1) end
        if IsAlive(M.guy2) then RemoveObject(M.guy2) end
        if IsAlive(M.guy3) then RemoveObject(M.guy3) end
        if IsAlive(M.beacon3) then RemoveObject(M.beacon3) end
        AudioMessage("misn1419.wav")
        M.rescue_finish3 = NEVER
    end
    --[[
        We need to keep the base
        alive so the game can finish.
    ]]
    if IsAlive(M.base) then
        if GetTime() > M.next_second then
            AddHealth(M.base, 5000.0)
            M.next_second = GetTime() + 1.0
        end
    end
    --[[
        The aliens are on
        the way and ready to
        give us grief.
    ]]
    if GetTime() > M.alien_time then
-- CR fury waves >>
      if FURY_WAVES then
        if SpawnFuryWave(M.wave_count + 1) then
            M.alien_attack = true
            M.wave_count = M.wave_count + 1
            M.alien_time = GetTime() + FURY_WAVE_PERIOD_S
        else
            M.alien_time = GetTime() + FURY_RETRY_S
        end
      else
-- CR fury waves <<
        M.alien_attack = true
        M.wave_count = M.wave_count + 1
        -- rand()%3 chooses one of three native branches. Lua 5.1 math.random
        -- provides the same alternatives; no BZ2-only random API is assumed.
        local x = math.random(0, 2)
        if x == 0 then
            BuildObject("hvsav", FURY_TEAM, "alien1")
            BuildObject("hvsav", FURY_TEAM, "alien2")
            BuildObject("hvsav", FURY_TEAM, "alien5")
        elseif x == 1 then
            BuildObject("hvsav", FURY_TEAM, "alien3")
            BuildObject("hvsav", FURY_TEAM, "alien4")
            BuildObject("hvsav", FURY_TEAM, "alien1")
        else
            BuildObject("hvsav", FURY_TEAM, "alien5")
            BuildObject("hvsav", FURY_TEAM, "alien6")
            BuildObject("hvsav", FURY_TEAM, "alien3")
        end
        M.alien_time = GetTime() + 180.0 -- was 70.0, now we explore
-- CR fury waves >>
      end
-- CR fury waves <<
    end
    if M.alien_attack and not M.alien_warning then
        AudioMessage("misn1403.wav")
        M.alien_warning = true
    end
    if (M.wave_count > 2 or CcaBroken()) and not M.cca_surrender then
        AudioMessage("misn1404.wav")
        AudioMessage("misn1405.wav") -- it's a trick!
        M.cca_surrender = true
        --[[
            Here is where we should
            switch sides or destroy people.
        ]]
        for h in AllCraft() do
            if GetTeamNum(h) == ENEMY_TEAM then
                SetTeamNum(h, 0) -- crazy!!  team 0 now
                if IsOdfBase(h, "svtank") or IsOdfBase(h, "svturr")
                    or IsOdfBase(h, "svfigh") then
                    Retreat(h, "escape", 1) --run away
                end
            end
        end
        --[[
            Convert the russian base
        ]]
        if IsAlive(M.base) then SetSurrenderTeam(M.base) end
-- CR surrender >>
        -- Shipped 1.5: both power plants surrender with the base.
        if IsAlive(M.pow1) then SetSurrenderTeam(M.pow1) end
        if IsAlive(M.pow2) then SetSurrenderTeam(M.pow2) end
        TitanHook("beat", "surrender")
-- CR surrender <<
        if IsAlive(M.tow1) then SetSurrenderTeam(M.tow1) end
        if IsAlive(M.tow2) then SetSurrenderTeam(M.tow2) end
        if IsAlive(M.tow3) then SetSurrenderTeam(M.tow3) end
        if IsAlive(M.tow4) then SetSurrenderTeam(M.tow4) end
    end
    if M.wave_count > 3 and not M.gen_message and M.rescue3 then
        SetScrap(ENEMY_TEAM, 0)
        M.audmsg = AudioMessage("misn1406.wav")
        M.gen_message = true
-- CR co-op layer >>
        -- The DLL measured the single player's nearest enemy: the shot only plays when no human is in a
        -- fight (every human's nearest enemy is beyond 150 m).
        local quiet = CRCoop.AllPlayersSatisfy(function(h)
            return Distance(h, GetNearestEnemy(h)) > 150.0
        end)
        if quiet then
-- CR co-op layer <<
            M.camera3 = true
            M.camera_time = GetTime() + 20.0
            CameraReady()
        else
            M.camera3 = false
        end
    end
    if M.camera3 then
        -- BUGFIX: a missing base must not become a nil camera target. Finish the
        -- existing shot; the source's subsequent missing-base failure still applies.
        if IsAlive(M.base) then
            CameraPath("camera_path", 2500, 300, M.base)
        end
    end
    if M.camera3 and (GetTime() > M.camera_time or CameraCancelled()
        or not IsAlive(M.base)) then
        if M.audmsg ~= nil then StopAudioMessage(M.audmsg) end
        M.camera3 = false
        CameraFinish()
    end
    --[[
        Now we need you
        to rescue CCA personel
    ]]
    if M.wave_count > 4 and not M.rescue_message and M.rescue3 then
        SetScrap(ENEMY_TEAM, 0)
        AudioMessage("misn1407.wav")
        M.rescue_message = true
        if IsAlive(M.base) then
            SetObjectiveOn(M.base)
            SetObjectiveName(M.base, "Rescue CCA")
-- CR co-op layer >>
            TitanHook("beat", "rescue_cca")
-- CR co-op layer <<
        else
            -- just in case its not there
            -- BUGFIX: source FailMission(5.0,"misn14l.des") uses absolute
            -- simulation time, already past after five waves. Keep its intended
            -- five-second delay and mark lost so success cannot override failure.
            FailMission(GetTime() + 5.0, "misn14l.des")
            M.lost = true
        end
    end
    if M.wave_count > 4 and M.found and not M.rescue_start and M.rescue3 then
        --[[
            Now that you've built
            an APC, get it to the
            base to rescue the soviet scientists
            AudioMessage
        ]]
        AudioMessage("misn1408.wav")
        M.rescue_start = true
    end
    if not M.pick_up and M.rescue_start and CarrierNear(M.base, 200.0) then
        --[[
            AudioMessage ..
            We're picking up the
            key personel..
        ]]
-- CR rescue >>
        M.apc = CarrierNear(M.base, 200.0)
-- CR rescue <<
        M.pick_up = true
        M.pick_up_time = GetTime() + 15.0
        AudioMessage("misn1409.wav")
    end
    if M.pick_up and GetTime() > M.pick_up_time then
        --[[
            Audio Message
            Ready to go.
        ]]
        M.pick_up_time = NEVER
        AudioMessage("misn1410.wav")
    end
    if not M.lost and M.pick_up and not IsAlive(M.apc) then
        --[[
            Lost the APC with the
            Russian scientists-- you
            lose.
        ]]
        AudioMessage("misn1412.wav")
        AudioMessage("misn1413.wav")
        FailMission(GetTime() + 10.0, "misn14l3.des")
        M.lost = true
    end
    -- BUGFIX: require a live carrier/recycler and no pending failure. The native
    -- victory block could override APC/survivor failure (or win on a dead recycler)
    -- in the same frame. Normal successful returns keep the 300 m / 10 s trigger.
    -- Source permits returning during the 15 s pickup VO delay; retain that flow.
    if not M.won and not M.lost and M.pick_up and Distance(M.recy, M.apc) < 300.0 then
        --[[
            You won..
        ]]
        M.won = true
        SucceedMission(GetTime() + 10.0, "misn14w1.des")
        AudioMessage("misn1411.wav")
    end
    if not M.lost and not IsAlive(M.recy) then
        AudioMessage("misn1414.wav")
        FailMission(GetTime() + 10.0, "misn14l1.des")
        M.lost = true
    end
-- CR co-op layer >>
    UpdateFurySquad()
    UpdateRescueNags()
    UpdateObjectives()
-- CR co-op layer <<
end

function Save()
-- CR Titan weather hook >>
    if titanStarted and ((not CRCoop.IsNetworkGame()) or CRCoop.IsAuthority()) then
        M.titanWeather = TitanHook("save")
    end
-- CR Titan weather hook <<
    -- BZR serializes the state table and supported game values. Native b/f/h/i
    -- arrays and object-handle conversion are engine-managed in LuaMission.
    return M
end

function Load(state)
    M = state
end
