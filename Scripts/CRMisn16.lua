-- Mission 16 campaign runtime. The faithful port remains in misn16.lua.
-- Presentation transport adapted from misn14's validated ordered E/A and C stream.
local Runtime = {}
function Runtime.Create(getState)
local M = getState()
local function Valid(h) return h ~= nil and h ~= 0 and IsValid(h) end
local function Alive(h) return Valid(h) and IsAlive(h) end
local function Distance(a,b)
    if not Alive(a) or (type(b) ~= "string" and not Alive(b)) then return math.huge end
    return GetDistance(a,b)
end
local function IsOdfBase(h,name) return Valid(h) and (IsOdf(h,name) or IsOdf(h,name..".odf")) end
local LEADER_TEAM, ENEMY_TEAM, FURY_TEAM, SURVIVOR_TEAM = 1, 5, 6, 7
-- CR co-op layer >>
-- EXU Initialization (the co-op layer needs the bundled multiplayer hooks).
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})
local exu = require("exu")
-- Native MultST Init precedes Start. The authored base is the Recycler Texas (team 1), so no human team
-- keeps a starting recycler: the base is shared and host-authoritative.
if type(IsNetGame) == "function" and IsNetGame() then
    assert(exu.DisableStartingRecycler and exu.GetMyNetID,
        "misn16 co-op requires the bundled EXU multiplayer hooks")
    exu.DisableStartingRecycler()
end
local subtit = require("ScriptSubtitles")
local CRCoop = require("CRCoop")
local CRWire = require("CRWire")
-- Native strategic AI startup configuration, before Start; human teams never get AI.
SetAIControl(FURY_TEAM, true)
-- CR co-op layer <<

-- CR Titan weather hook >>
-- The single wiring point for the Titan weather director (built separately; this file never edits it).
-- When a module named CRTitanWeather exists and exports MissionHook(event, ...), it receives:
--   "init"  (context)   once on every peer: { authority = bool, mission = "misn16",
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
    if not ok then
        M.titanModuleError=tostring(mod)
        print("[misn16] Titan director unavailable: "..tostring(mod))
    end
    if ok and type(mod) == "table" then
        TitanSensorDirector = mod
        if type(mod.MissionHook) == "function" then
            TitanWeather = mod
        elseif type(mod.Init) == "function" and type(mod.Update) == "function" then
            -- The director on main (Docs/TITAN_WEATHER.md) exposes Init/Update/ApplyNetEvent rather than a
            -- MissionHook: adapt the hook events onto its API here, so the mission logic stays untouched.
            local sitesOk, sites = pcall(require, "CRTitanSites16")
            if not sitesOk then
                M.titanSitesError=tostring(sites)
                print("[misn16] Titan map data unavailable: "..tostring(sites))
                sites = nil
            end
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
    if event=="init" then
        Environment.Init({nativeBaseline=true})
        Environment.BindWeatherSensors("Titan",TitanSensorDirector)
    end
    if not TitanWeather then return nil end
    local ok, result = pcall(TitanWeather.MissionHook, event, ...)
    if ok then
        if event=="update" then Environment.Update((...)) end
        if event=="load" and Environment.InvalidateRenderer then Environment.InvalidateRenderer() end
        if event=="object" then Environment.OnObjectCreated((...)) end
        return result
    end
    if not M.titanHookError then
        M.titanHookError = true
        print("[misn16] Titan weather hook failed: " .. tostring(result))
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
    RemoveObject = RemoveObject,
    -- Resolve result hooks after PersistentConfig.Initialize installs cleanup.
    SucceedMission = function(...) return _G.SucceedMission(...) end,
    FailMission = function(...) return _G.FailMission(...) end,
    CameraReady = CameraReady, CameraPath = CameraPath, CameraObject = CameraObject,
    CameraFinish = CameraFinish, CameraCancelled = CameraCancelled,
    StopAudioMessage = StopAudioMessage,
    Play = subtit.Play, Queue = subtit.Queue, Stop = subtit.Stop,
}
local events, acknowledgements = {}, {}
local StartLift
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
    if op == "EvacLaunch" then return StartLift(...) end
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
    RemoveObject = true, Label = true }
local WAIT_OPS = { SetObjectiveOn = true, SetObjectiveName = true, Label = true }
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
        pcall(SetLabel, handle, "crco16_" .. labelSerial)
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
    if native.CameraCancelled() then
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
    if native.CameraCancelled() then
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
    if seq == receivedEvent + 1 and (native[op] or IsTitanOp(op) or op == "Label" or op == "EvacLaunch") then
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
-- CR Mission 16 gameplay >>
local pda = require("PersistentConfig")
local R = {}
local startedWeather = false
local PARTS = {"cr16_transport","cr16_engine1","cr16_engine2","cr16_engine3","cr16_engine4"}
local function State()
    M=getState()
    if not M.cr16 then
        M.cr16={pending={}, nextWave=120, nextSav=60, nextSat=90, gap=150,
            count=0, manifest=0, evac={}, boarded=0, shots={}, approach={}}
    end
    return M.cr16
end
local function Point(x,y,z) return SetVector(x,y,z) end
local function NearAny(where,radius)
    return CRCoop.AnyPlayerSatisfies(function(h) return Distance(h,where)<radius end)
end
local function SafeSite(kind)
    -- Every new group appears beyond edge_path, outside the capped 250 m fog
    -- horizon of every human. No new units are built during a shared camera.
    if cameraFrame then return nil end
    local names=kind=="ally" and {"cr16_ally_a","cr16_ally_b"} or {"cr16_enemy_a","cr16_enemy_b"}
    for _,name in ipairs(names) do if not NearAny(name,460) then return name end end
end
local function ConfigureAlliances()
    CRCoop.ApplyCoopAlliances(FURY_TEAM)
    for team=1,4 do
        Ally(team,SURVIVOR_TEAM);Ally(SURVIVOR_TEAM,team)
        UnAlly(team,FURY_TEAM);UnAlly(FURY_TEAM,team)
    end
end
local function Objective(done)
    ClearObjectives()
    AddObjective("Destroy the corrupted CCA command building and hangar.",done and "green" or "white")
end
local function Failure()
    local s=State()
    if M.lost or M.won then return end
    M.lost=true;s.finale=nil
    if localCameraActive then CameraFinish() end
    AudioMessage("misn1612.wav")
    FailMission(GetTime()+15,"misn16l1.des")
end
local function Enqueue(kind,units,voice,target,route)
    local s=State()
    s.pending[#s.pending+1]={kind=kind,units=units,voice=voice,target=target,route=route}
end
local function UpdateArrivals()
    local s=State();local group=s.pending[1]
    if not group then return end
    local site=SafeSite(group.kind)
    if not site then return end
    local origin=GetPosition(site)
    for i,odf in ipairs(group.units) do
        local pos=Point(origin.x+(i-1)*12,origin.y+2,origin.z)
        local h=BuildObject(odf,group.kind=="ally" and 1 or FURY_TEAM,pos)
        if Valid(h) then
            if group.kind=="ally" then
                local target=Alive(M.base1) and M.base1 or M.base2
                if Alive(target) then
                    if odf=="svscav" or odf=="svhaul" then Goto(h,target,0) else Attack(h,target,0) end
                end
                M.newbie=h
            elseif group.target and Alive(group.target) then Attack(h,group.target,1)
            elseif group.route then Goto(h,group.route,1)
            elseif Alive(M.recy) then Attack(h,M.recy,0) end
        end
    end
    if group.voice then AudioMessage(group.voice);if group.doubleVoice then AudioMessage(group.voice) end end
    table.remove(s.pending,1)
end
local MANIFESTS={
    {"svfigh","svhaul","svhaul"},{"svscav","svscav","svfigh"},
    {"svscav","svturr","svfigh"},{"svfigh","svfigh"},
    {"svfigh","svfigh","svtank","svtank","svtank","svtank"},
    {"svtank","svtank","svtank"},{"svwalk","svwalk","svwalk"},
}
local VO={"misn1603.wav","misn1604.wav","misn1605.wav","misn1606.wav","misn1607.wav","misn1607.wav","misn1608.wav"}
local function Bootstrap()
    local s=State();s.started=GetTime()
    -- Publish authored identities while every scene object is still present,
    -- before a later removal can race its initial label acknowledgement.
    for _,label in ipairs(PARTS) do local h=GetHandle(label);if Valid(h) then EnsureLabel(h) end end
    for _,label in ipairs({"cr16_evac1","cr16_evac2","cr16_pad_look"}) do
        local h=GetHandle(label);if Valid(h) then EnsureLabel(h) end
    end
    M.recy=GetHandle("avrecy0_recycler");M.muf=GetHandle("avmuf26_factory")
    M.base1=GetHandle("alien_hq");M.base2=GetHandle("alien_hangar")
    for i=1,4 do M["tow"..i]=GetHandle("sbtowe"..(i-1).."_turret") end
    for i=1,3 do local h=GetHandle("hvsat"..(i-1).."_wingman");if Alive(h) then Defend(h,1) end end
    for i=1,2 do
        local h=GetHandle("cr16_evac"..i);s.evac[i]=h
        -- Only these known SAT craft get unit AI orders; the hull/engines/pod do not.
        if Alive(h) then SetIndependence(h,0);Stop(h,1) end
    end
    s.manifest=math.random(1,2)
    SetScrap(1,50);SetAIP("misn16.aip",FURY_TEAM)
    Objective(false)
    AudioMessage("misn1601.wav");s.briefing=AudioMessage("misn1602.wav")
    M.start_done=true
    CameraReady();s.introUntil=GetTime()+20
end
local function BeginEvacuation()
    local s=State()
    if s.evacuating then return end
    s.evacuating=true;s.evacStarted=GetTime()
    for _,h in ipairs(s.evac) do if Alive(h) then Goto(h,"cr16_evac_route",1) end end
end
local function UpdateBoarding()
    local s=State()
    local hull=GetHandle("cr16_transport")
    if not Alive(hull) then return end
    if s.finale and s.finale~="boarding" then
        for _,h in pairs(s.evac) do if Alive(h) then SetVelocity(h,Point(0,0,0)) end end
        return -- a stranded actor is never absorbed by the departing ship
    end
    s.evacLeg=s.evacLeg or {}
    for i,h in pairs(s.evac) do
        if Alive(h) then
            local p=GetPosition(h)
            local board=GetPosition("cr16_board")
            board=Point(board.x,board.y,board.z)
            local centre=GetPosition(hull)
            -- A pocket behind the north engines are outside all
            -- collision hulls. From the south camera the broad skirt hides
            -- the entire arriving craft; nearby humans still block removal.
            local inside=(p.x-board.x)^2+(p.z-board.z)^2<16 and p.y<centre.y+20
            local ready=s.finale=="boarding" and (i==1 or GetTime()-(s.voiceAt or GetTime())>=8)
            if ready and inside and not NearAny(h,400) then
                RemoveObject(h);s.evac[i]=false;s.boarded=s.boarded+1
            else
                -- The native AIP can supersede enemy Goto orders. These two
                -- known SAT actors follow the authored route with synchronized
                -- ground velocity, then hold until the final boarding shot.
                local goal=p
                if s.evacuating then
                    local leg=s.evacLeg[i] or 0
                    goal=GetPosition("cr16_evac_route",leg)
                    goal=Point(goal.x,goal.y,goal.z+(i-1)*16)
                    if (p.x-goal.x)^2+(p.z-goal.z)^2<100 and leg<2 then
                        leg=leg+1;goal=GetPosition("cr16_evac_route",leg)
                        goal=Point(goal.x,goal.y,goal.z+(i-1)*16)
                    end
                    s.evacLeg[i]=leg
                    if ready then goal=board end
                end
                local dx,dz=goal.x-p.x,goal.z-p.z
                local length=math.sqrt(dx*dx+dz*dz)
                if length>2 then SetVelocity(h,Point(dx/length*12,0,dz/length*12))
                else SetVelocity(h,Point(0,0,0)) end
            end
        end
    end
end

StartLift=function(age)
    State()
    if M.evacVisual then return end
    M.evacVisual={started=GetTime()-(tonumber(age) or 0),parts={}}
    for _,label in ipairs(PARTS) do
        local h=GetHandle(label)
        if Valid(h) then
            local p=GetPosition(h)
            M.evacVisual.parts[label]={x=p.x,y=p.y,z=p.z}
        end
    end
end
local function UpdateLift()
    -- Static map buildings do not get a vehicle Goto command. Each peer applies
    -- the same local visual translation after the acknowledged launch event;
    -- the leader alone decides boarding, launch time, removal and mission result.
    local v=M.evacVisual
    if not v then return end
    local age=math.max(0,GetTime()-v.started)
    local rise=math.min(900,age*age)
    for label,p in pairs(v.parts) do
        local h=GetHandle(label)
        if Valid(h) then SetPosition(h,Point(p.x,p.y+rise,p.z)) end
    end
end
local function CameraSafe()
    -- Inert enemy mines/markers must not suppress the film forever. Check the
    -- actual Fury combat craft and gun towers around every human instead.
    return not CRCoop.AnyPlayerSatisfies(function(h)
        if not Alive(h) then return false end
        for enemy in AllCraft() do
            if Alive(enemy) and GetTeamNum(enemy)==FURY_TEAM and Distance(h,enemy)<150
                    and (IsOdfBase(enemy,"hvsav") or IsOdfBase(enemy,"hvsat")
                         or IsOdfBase(enemy,"cr16tow")) then return true end
        end
        return false
    end)
end

local function UpdateFinale()
    local s=State();local now=GetTime()
    if not s.finale then return end
    if not Alive(GetHandle("cr16_transport")) then
        -- Destroying the optional scene prop must not softlock the earned win.
        M.won=true;if localCameraActive then CameraFinish() end
        SucceedMission(now+5,"misn16w1.des");return
    end
    if s.finale=="boarding" then
        if not s.evacVoice then
            s.evacVoice=AudioMessage("misn1615.wav");s.voiceAt=now
        end
        if not s.sceneCamera and CameraSafe() then
            s.sceneCamera=true;CameraReady()
        end
        if s.sceneCamera then
            CameraPath("cr16_evac_cam",10000,450,GetHandle("cr16_pad_look"))
        end
        local pending=false
        for _,h in pairs(s.evac) do if Alive(h) then pending=true end end
        -- No mandatory chase / boarding gate: a stranded SAT remains on the
        -- terrain. It is never teleported into the ship or deleted by a timeout.
        if now-s.voiceAt>=15 and (not pending or now-s.voiceAt>=50)
                and (not lastAudio or IsAudioMessageDone(lastAudio) or now-s.voiceAt>=65) then
            if s.sceneCamera then CameraFinish() end
            local pod=GetHandle("cr16_pad_look")
            if Valid(pod) then RemoveObject(pod) end -- still occluded by the grounded hull
            s.finale="launch";s.launchAt=now
            Present("EvacLaunch",0)
            if CameraSafe() then CameraReady();s.launchCamera=true end
        end
    elseif s.finale=="launch" then
        local age=now-s.launchAt
        if s.launchCamera and age<17 then
            CameraPath("cr16_launch_cam",8500,450,GetHandle("cr16_transport"))
        elseif s.launchCamera then CameraFinish();s.launchCamera=false end
        if age>=30 then
            -- Above 900 m: beyond the 250 m horizon from the ground-level
            -- cinematic and the bounded playable map. Removal is shared.
            for _,label in ipairs(PARTS) do local h=GetHandle(label);if Valid(h) then RemoveObject(h) end end
            s.finale="departed";M.won=true
            SucceedMission(now+5,"misn16w1.des")
        end
    end
end
local function UpdateStory()
    local s=State();local now=GetTime();local age=now-s.started
    -- Texas loss wins the same-update tie, until the combat objective is latched.
    if not s.victory and not Alive(M.recy) then Failure();return end
    if s.finale then UpdateBoarding();UpdateFinale();return end
    if s.introUntil then
        if now<s.introUntil and Alive(M.base2) then CameraPath("camera_path1",4000,500,M.base2)
        else CameraFinish();s.introUntil=nil end
    end
    local hq,hangar=Alive(M.base1),Alive(M.base2)
    if not hq or not hangar then BeginEvacuation() end
    UpdateBoarding()
    if not hangar and not s.hangarReported then s.hangarReported=true;AudioMessage("misn1616.wav") end
    if not hq and not hangar then
        s.victory=true;s.pending={};s.finale="boarding"
        if localCameraActive then CameraFinish() end
        Objective(true);AudioMessage("misn1613.wav")
        UpdateFinale();return
    end
    if age>=s.nextWave and s.count<10 then
        s.count=s.count+1
        if s.count<10 then
            Enqueue("ally",MANIFESTS[s.manifest],VO[s.manifest])
            -- Preserve source type-5 fallthrough's second copy of the radio.
            if s.manifest==5 then s.pending[#s.pending].doubleVoice=true end
            s.manifest=math.random(1,7);s.nextWave=age+180
        else AudioMessage("misn1614.wav") end
    end
    if age>=s.nextSav then
        Enqueue("enemy",{"hvsav"});s.nextSav=age+s.gap;s.gap=math.max(60,s.gap-5)
    end
    if age>=s.nextSat then
        Enqueue("enemy",{"hvsat"},nil,nil,"strike1")
        Enqueue("enemy",{"hvsat"},nil,nil,"strike2")
        s.nextSat=s.nextSav+90
    end
    if not s.counter and ((not Alive(M.tow1) and not Alive(M.tow2))
        or (not Alive(M.tow3) and not Alive(M.tow4)) or not hq or not hangar) then
        s.counter=true;s.counterAt=age+120
        Enqueue("enemy",{"hvsav","hvsav"},"misn1609.wav",M.muf)
    end
    if s.counterAt and age>=s.counterAt then
        s.counterAt=nil;Enqueue("enemy",{"hvsav","hvsav"},"misn1610.wav",M.recy)
    end
    if age>=720 and hq and hangar and not s.flankHint then
        s.flankHint=true;AudioMessage("misn1611.wav")
    end
    UpdateArrivals()
end
function R.Start()
    State()
    CRCoop.Initialize({getLocalPlayerId=function() return exu.GetMyNetID and exu.GetMyNetID() end,
        leaderTeam=1,humanTeamMin=1,humanTeamMax=4,rallyPoints={[0]="avrecy0_recycler"},
        onOutOfLives=Failure})
    ConfigureAlliances();ResetPresentation();lastAudio=nil
    if startedWeather then TitanHook("shutdown") end
    startedWeather=false;pda.Initialize();subtit.Initialize()
end
function R.AddObject(h) if Valid(h) then TitanHook("object",h) end end
function R.CreatePlayer(id,name,team) CRCoop.CreatePlayer(id,name,team);ConfigureAlliances() end
function R.AddPlayer(id,name,team) CRCoop.AddPlayer(id,name,team);ConfigureAlliances() end
function R.DeletePlayer(id) CRCoop.DeletePlayer(id) end
function R.Receive(from,kind,...)
    State()
    if ReceivePresentation(from,kind,...) then return true end
    return CRCoop.Receive(from,kind,...)
end
function R.Update(dt)
    local s=State()
    subtit.Update();CRCoop.Update();UpdatePresentationTransport();UpdateLift()
    pda.UpdateInputs(localCameraActive);pda.UpdateHeadlights()
    if CRCoop.IsNetworkGame() then
        if CRCoop.HasLeaderDeparted() then
            if not M.coopResult then M.coopResult=true;native.FailMission(GetTime()+1) end
            return
        end
        if CRCoop.HasUnsupportedPlayerTeam() or CRCoop.HasLateJoiners() then return end
        if not CRCoop.IsSessionReady() then return end
    end
    if not s.missionStarted then CRCoop.MarkMissionStarted();s.missionStarted=true end
    M.coopMissionStarted=true
    if not startedWeather then
        startedWeather=true
        TitanHook("init",{authority=CRCoop.IsAuthority(),mission="misn16",
            send=CRCoop.IsAuthority() and function(op,...)
                if IsTitanOp(op) then events[#events+1]={op=op,args={...},n=select("#",...),ttl=RESOLVE_TIMEOUT} end
            end or nil})
        if CRCoop.IsAuthority() and M.titanWeather then TitanHook("load",M.titanWeather) end
    end
    TitanHook("update",dt)
    if not CRCoop.IsAuthority() or M.coopResult or M.coopPendingResult or M.lost or M.won then return end
    if not M.start_done then Bootstrap() end
    UpdateStory()
end
function R.Save()
    State();if startedWeather and CRCoop.IsAuthority() then M.titanWeather=TitanHook("save") end
end
function R.Load()
    State();if startedWeather then TitanHook("shutdown") end
    startedWeather=false;R.Start()
end
R.Coop,R.Exu,R.Native=CRCoop,exu,native
return R
end
return Runtime
-- CR Mission 16 gameplay <<
