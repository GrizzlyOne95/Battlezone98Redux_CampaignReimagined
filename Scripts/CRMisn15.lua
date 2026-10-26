-- Mission 15 campaign runtime. The faithful port remains in misn15.lua.
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
        "misn15 co-op requires the bundled EXU multiplayer hooks")
    exu.DisableStartingRecycler()
end
local subtit = require("ScriptSubtitles")
local CRCoop = require("CRCoop")
local CRWire = require("CRWire")
-- CR co-op layer <<
-- CR Titan weather hook >>
-- The single wiring point for the Titan weather director (built separately; this file never edits it).
-- When a module named CRTitanWeather exists and exports MissionHook(event, ...), it receives:
--   "init"  (context)   once on every peer: { authority = bool, mission = "misn15",
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
        print("[misn15] Titan director unavailable: "..tostring(mod))
    end
    if ok and type(mod) == "table" then
        TitanSensorDirector = mod
        if type(mod.MissionHook) == "function" then
            TitanWeather = mod
        elseif type(mod.Init) == "function" and type(mod.Update) == "function" then
            -- The director on main (Docs/TITAN_WEATHER.md) exposes Init/Update/ApplyNetEvent rather than a
            -- MissionHook: adapt the hook events onto its API here, so the mission logic stays untouched.
            local sitesOk, sites = pcall(require, "CRTitanSites15")
            if not sitesOk then
                M.titanSitesError=tostring(sites)
                print("[misn15] Titan map data unavailable: "..tostring(sites))
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
        -- Titan night: the sun is below the horizon opposite Saturn, which is
        -- nearly full and lights the base through the haze. Visual only;
        -- sensors keep their day ranges.
        Environment.Init({lightingMode="night",nativeBaseline=true,nightGameplay=false,
            skySun={azimuth=20,elevation=-25}})
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
        print("[misn15] Titan weather hook failed: " .. tostring(result))
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
        pcall(SetLabel, handle, "crco15_" .. labelSerial)
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
-- The campaign gameplay body is kept separate from the preserved source port.
local pda = require("PersistentConfig")
local R = {}
local startedWeather = false
local GROUPS = {
    nw = { "cr15_nw_scav", "cr15_nw_apc", "cr15_nw_turret" },
    ne = { "cr15_ne_scav1", "cr15_ne_scav2", "cr15_ne_artillery" },
}
local function State()
    M = getState()
    if not M.cr15 then
        M.cr15 = { scavengers = {}, stores = {}, furies = {}, shots = {}, reports = {},
            nextHunter = 120, denial = { false, false }, nextDenial = { 300, 400 },
            nextTargets = 0, nextObjectives = 0 }
    end
    return M.cr15
end
local function NearAny(target, radius)
    return CRCoop.AnyPlayerSatisfies(function(h) return Distance(h,target) < radius end)
end
local function NearPosition(point,radius)
    if not point then return false end
    return CRCoop.AnyPlayerSatisfies(function(h)
        if not Alive(h) then return false end
        local p=GetPosition(h)
        return (p.x-point.x)^2+(p.z-point.z)^2<radius^2
    end)
end
local function NearAll(target, radius)
    return CRCoop.AllPlayersSatisfy(function(h)
        return Alive(h) and Distance(h,target) < radius
    end)
end
local function HumanCount()
    return math.max(1, CRCoop.ForEachHumanTeam(function() end))
end
local function Remember(list,h)
    for _,old in ipairs(list) do if old == h then return end end
    list[#list+1] = h
end
local function ConfigureAlliances()
    CRCoop.ApplyCoopAlliances(FURY_TEAM)
    for team=1,4 do
        Ally(team,SURVIVOR_TEAM); Ally(SURVIVOR_TEAM,team)
        UnAlly(team,FURY_TEAM); UnAlly(FURY_TEAM,team)
    end
    UnAlly(SURVIVOR_TEAM,FURY_TEAM); UnAlly(FURY_TEAM,SURVIVOR_TEAM)
end
local function LivingGroup(name)
    local list = {}
    for _,label in ipairs(GROUPS[name]) do
        local h=GetHandle(label)
        if Alive(h) then list[#list+1]=h end
    end
    return list
end
local function Objective(key,text,done)
    local s=State()
    local color=done and "green" or "white"
    local value=color..text
    s.objectives=s.objectives or {}
    if s.objectives[key]==value then return end
    s.objectives[key]=value
    -- Plain text with a newline is supported by the stock objective API.
    AddObjective(text.."\n",color,8)
end
local function Capacity()
    if type(GetMaxScrap)=="function" then return GetMaxScrap(LEADER_TEAM) end
    local n=Alive(M.recy) and 30 or 0
    for _,h in ipairs(State().stores) do
        if Alive(h) and GetTeamNum(h)==LEADER_TEAM then
            n=n+(IsOdfBase(h,"absilo") and 20 or 10)
        end
    end
    return n
end
local function UpdateObjectives(force)
    local s=State()
    if not force and GetTime()<s.nextObjectives then return end
    s.nextObjectives=GetTime()+1
    CRCoop.SetMissionPhase(M.lost and 9 or M.won and 8 or s.withdraw and 4 or s.nw and 3 or s.cca and 2 or 1)
    local reserve=GetScrap(LEADER_TEAM)
    -- Rebuild only on meaningful changes; never append endlessly to the ten-slot panel.
    local key=table.concat({tostring(s.cca),tostring(s.nw),tostring(s.ne),tostring(s.neLost),
        tostring(Capacity()),tostring(reserve),tostring(s.withdraw),tostring(M.lost),tostring(M.won)},":")
    if key==s.objectiveKey and not force then return end
    s.objectiveKey=key
    ClearObjectives(); s.objectives={}
    Objective("cca","Rendezvous with the CCA contingent",s.cca)
    Objective("nw","Recover Massachusetts survivors",s.nw)
    Objective("ne",s.neLost and "Optional: Alaska survivors lost" or "Optional: recover Alaska survivors",s.ne)
    Objective("capacity",string.format("Storage capacity: %d / 75",Capacity()),Capacity()>=75)
    Objective("reserve",string.format("Shared reserve: %d / 75 scrap",reserve),reserve>=75)
    if s.withdraw then
        Objective("withdraw","Escort Texas to Supply; assemble the whole squad",M.won)
    end
    if M.lost then Objective("failure",s.failure or "Mission failed",false) end
    if s.tartarusAlert then Objective("tartarus","Tartarus disturbed: Fury response incoming",false) end
    if s.tartarusMinesPending or s.tartarusMinesComplete then
        Objective("mines","Tartarus deploying arc-mine grid: withdraw from the structure",false)
    end
end
local function FinishFailure(reason,description,voice)
    if M.lost or M.won then return end
    M.lost=true; State().failure=reason
    if voice then AudioMessage(voice) end
    UpdateObjectives(true)
    TitanHook("beat","lose")
    FailMission(GetTime()+10,description or "misn15l1.des")
end
local function QueueShot(kind,subject)
    State().shots[#State().shots+1]={kind=kind,subject=subject}
end
local function UpdateShots()
    local s=State()
    if s.shot then
        local shot=s.shot
        if Alive(shot.subject) and not localCameraActive then CameraReady() end
        if not Alive(shot.subject) or GetTime()>shot.untilTime or CameraCancelled() then
            CameraFinish();s.shot=nil
        elseif shot.kind=="cca" then CameraObject(shot.subject,800,600,1200,shot.subject)
        else CameraPath(shot.kind=="nw" and "rescue_cam1" or "rescue_cam2",1000,0,shot.subject) end
    elseif #s.shots>0 then
        local shot=table.remove(s.shots,1)
        if Alive(shot.subject) then
            shot.untilTime=GetTime()+(shot.kind=="cca" and 8 or 3)
            s.shot=shot; CameraReady()
        end
    end
end
local function Recover(name,pod)
    local s=State()
    if s[name] or s[name.."Lost"] or not NearAny(pod,150) then return end
    local group=LivingGroup(name)
    if #group==0 then return end
    s[name]=true
    for _,h in ipairs(group) do
        SetTeamNum(h,LEADER_TEAM); Stop(h,0)
        R.AddObject(h)
    end
    if name=="nw" then AudioMessage("misn1518.wav") end
    QueueShot(name,group[1])
end
local function Target()
    local s=State()
    for _,h in ipairs(s.scavengers) do
        if Alive(h) and GetTeamNum(h)==LEADER_TEAM then return h end
    end
    return Alive(M.recy) and M.recy or nil
end
local function LiveFuries()
    local n=0
    for _,h in ipairs(State().furies) do if Alive(h) then n=n+1 end end
    return n
end
local function SafeSpawn(preferred)
    for _,point in ipairs({preferred,preferred=="alien1" and "alien2" or "alien1"}) do
        if not NearAny(point,400) then return point end
    end
end
local function BuildWave(odf,count,preferred,destination)
    if LiveFuries()+count>10 then return false end
    local where=SafeSpawn(preferred)
    if not where then return false end
    for _=1,count do
        local h=BuildObject(odf,FURY_TEAM,where)
        if Alive(h) then
            Remember(State().furies,h)
            if destination then Goto(h,destination,1)
            else local target=Target(); if target then Attack(h,target,1) end end
        end
    end
    return true
end
local function UpdateFuries()
    local s=State();local now=GetTime()-s.started
    -- Reserve four slots until both authored denial encounters have spawned.
    local reserved=(s.denial[1] and 0 or 2)+(s.denial[2] and 0 or 2)
    for i=1,2 do
        if not s.denial[i] and now>s.nextDenial[i] then
            if BuildWave("crfraz",2,i==1 and "alien1" or "alien2","deny"..i) then s.denial[i]=true
            else s.nextDenial[i]=now+15 end
        end
    end
    if now>s.nextHunter and (s.hunters or 0)<50 then
        local count=HumanCount()==1 and 1 or HumanCount()<4 and 2 or 3
        -- Two light patrols per heavy SAV patrol, using the existing saved counter.
        local odf=(s.hunters or 0)%3==2 and "hvsav" or "crfraz"
        if LiveFuries()+count<=10-reserved and BuildWave(odf,count,math.random(1,2)==1 and "alien1" or "alien2") then
            s.hunters=(s.hunters or 0)+1;s.nextHunter=now+240
        else s.nextHunter=now+15 end
    end
    if now>s.nextTargets then
        s.nextTargets=now+5
        for _,h in ipairs(s.furies) do
            if Alive(h) and (IsOdfBase(h,"hvsav") or IsOdfBase(h,"crfraz")) then
                local target=type(GetCurrentWho)=="function" and GetCurrentWho(h) or nil
                if not Alive(target) then
                    target=Target()
                    if target then Attack(h,target,1) else Goto(h,"alien_path",1) end
                end
            end
        end
    end
end
local function UpdateReports()
    local s=State();local scrap=GetScrap(LEADER_TEAM)
    if scrap>=75 then
        s.reports[40]=true;s.reports[65]=true
    elseif scrap>=65 and not s.reports[65] then
        s.reports[40]=true;s.reports[65]=true;AudioMessage("misn1507.wav")
    elseif scrap>=40 and not s.reports[40] then
        s.reports[40]=true;AudioMessage("misn1505.wav")
    end
    if scrap>=50 and not s.withdraw then
        s.withdraw=true;AudioMessage("misn1506.wav");AudioMessage("misn1508.wav")
        if Alive(M.cam5) then SetObjectiveOn(M.cam5) end
        TitanHook("beat","surrender")
    end
    if not s.threatReport then
        for _,h in ipairs(s.furies) do
            if Alive(h) and NearAny(h,200) then s.threatReport=true;AudioMessage("misn1504.wav");break end
        end
    end
end
-- Provisional Tartarus encounter: a warning is actionable, never a win prerequisite.
-- No invented relic activation/research technology; the response uses existing Furies.
local function UpdateTartarus()
    local s=State()
    local health=Alive(M.tart) and type(GetCurHealth)=="function" and GetCurHealth(M.tart) or 0
    local damaged=s.tartarusHealth and health<s.tartarusHealth
    if Alive(M.tart) and NearAny(M.tart,150) and not s.tartarusWarning then
        s.tartarusWarning=GetTime();AudioMessage("misn1513.wav");AudioMessage("misn1514.wav")
    end
    if not s.tartarusAlert then
        if damaged then
            s.tartarusAlert=true
        elseif s.tartarusWarning and GetTime()>s.tartarusWarning+15 and NearPosition(s.tartarusPoint,80) then
            s.tartarusClose=s.tartarusClose or GetTime()
            if GetTime()>s.tartarusClose+6 then s.tartarusAlert=true end
        else s.tartarusClose=nil end
        if s.tartarusAlert then
            s.tartarusResponsePending=true;s.nextTartarusTry=0
            s.objectiveKey=nil;TitanHook("beat","rogue")
        end
    end
    s.tartarusHealth=health
    if s.tartarusResponsePending and GetTime()>s.nextTartarusTry then
        local reserved=(s.denial[1] and 0 or 2)+(s.denial[2] and 0 or 2)
        if LiveFuries()+2<=10-reserved and BuildWave("crfraz",2,"alien2") then
            s.tartarusResponsePending=false;s.tartarusResponseSpawned=true
        else s.nextTartarusTry=GetTime()+15 end
    end
    -- Owner-requested second escalation. Persistent intrusion arms a compact
    -- 7x7 grid with a 3x3 central clearance: forty arc mines, 18 m spacing.
    -- This explicitly signposted local trap is the exception to enemy-wave
    -- 400 m placement; never materialize a mine directly under a human.
    if s.tartarusAlert and not s.tartarusMinesPending and not s.tartarusMinesComplete then
        if NearPosition(s.tartarusPoint,80) then
            s.tartarusPersistSince=s.tartarusPersistSince or GetTime()
            if GetTime()>s.tartarusPersistSince+12 then
                local center=s.tartarusPoint
                s.tartarusMinesPending={};s.tartarusMines={};s.nextMineDeploy=GetTime()+4
                for row=-3,3 do
                    for col=-3,3 do
                        if math.abs(row)>1 or math.abs(col)>1 then
                            s.tartarusMinesPending[#s.tartarusMinesPending+1]={x=center.x+col*18,z=center.z+row*18}
                        end
                    end
                end
                s.objectiveKey=nil
            end
        else s.tartarusPersistSince=nil end
    end
    if type(s.tartarusMinesPending)=="table" and GetTime()>=s.nextMineDeploy then
        s.nextMineDeploy=GetTime()+0.25
        local deployed=0
        for i=#s.tartarusMinesPending,1,-1 do
            if deployed>=2 then break end
            local point=s.tartarusMinesPending[i]
            local occupied=false
            CRCoop.ForEachPlayerHandle(function(h)
                if Alive(h) then
                    local p=GetPosition(h)
                    if (p.x-point.x)^2+(p.z-point.z)^2<12^2 then occupied=true end
                end
            end)
            if not occupied then
                local position=SetVector(point.x,0,point.z)
                local y=GetTerrainHeightAndNormal(position)
                position.y=y+0.5
                local mine=BuildObject("crfmine",FURY_TEAM,position)
                if Valid(mine) then
                    s.tartarusMines[#s.tartarusMines+1]=mine
                    table.remove(s.tartarusMinesPending,i);deployed=deployed+1
                end
            end
        end
        if #s.tartarusMinesPending==0 then
            s.tartarusMinesPending=nil;s.tartarusMinesComplete=true;s.objectiveKey=nil
        end
    end
end
local function Bootstrap()
    local s=State()
    M.recy=GetHandle("avrecy0_recycler");M.tart=GetHandle("ubtart0_i76building")
    for i=1,6 do M["cam"..i]=GetHandle("apcamr"..(i-1).."_camerapod") end
    if not Alive(M.recy) or not Valid(GetHandle("misn15b")) then
        FinishFailure("Mission 15 requires the CR misn15b-derived map")
        return
    end
    s.started=GetTime();M.start_done=true
    s.tartarusPoint=Alive(M.tart) and GetPosition(M.tart) or nil
    s.tartarusHealth=Alive(M.tart) and type(GetCurHealth)=="function" and GetCurHealth(M.tart) or nil
    AddScrap(LEADER_TEAM,10)
    SetObjectiveName(M.recy,"Recycler Texas")
    for i,name in ipairs({"Geyser Site","Massachusetts survivors","Alaska survivors","Geyser Site","Supply","Nav Bravo"}) do
        if Alive(M["cam"..i]) then SetObjectiveName(M["cam"..i],name) end
    end
    s.convoy={GetHandle("svtank0_wingman"),GetHandle("svtank1_wingman"),GetHandle("svapc0_apc")}
    for _,h in ipairs(s.convoy) do if Alive(h) then SetTeamNum(h,SURVIVOR_TEAM);Goto(h,"tank_path",1) end end
    for name in pairs(GROUPS) do
        for _,h in ipairs(LivingGroup(name)) do Stop(h,1) end
    end
    if CRCoop.IsNetworkGame() then
        local placeholder=GetHandle("player0_hover")
        if Valid(placeholder) and not CRCoop.IsHumanCraft(placeholder) then RemoveObject(placeholder) end
    end
    s.briefing=AudioMessage("misn1501.wav")
    if Alive(M.cam6) then SetObjectiveOn(M.cam6) end
    UpdateObjectives(true)
end
local function UpdateStory()
    local s=State();local age=GetTime()-s.started
    if not Alive(M.recy) then FinishFailure("Recycler Texas destroyed","misn15l1.des","misn1509.wav");return end
    if not s.ccaIntro and age>2 and IsAudioMessageDone(s.briefing) then
        s.ccaIntro=true;AudioMessage("misn1502.wav")
        for _,h in ipairs(s.convoy) do if Alive(h) then QueueShot("cca",h);break end end
    end
    if not s.cca then
        local live=0
        for _,h in ipairs(s.convoy) do
            if Alive(h) then
                live=live+1
                if Distance(h,M.cam6)<100 or Distance(h,M.cam4)<100 then s.cca=true end
            end
        end
        if live==0 then FinishFailure("CCA contingent lost before rendezvous","misn15l2.des");return end
        if s.cca then
            for _,h in ipairs(s.convoy) do if Alive(h) then SetTeamNum(h,LEADER_TEAM);Stop(h,0) end end
            AudioMessage("misn1503.wav")
        end
    end
    for _,name in ipairs({"nw","ne"}) do
        if not s[name] and not s[name.."Lost"] and #LivingGroup(name)==0 then
            if name=="nw" then FinishFailure("Massachusetts survivors lost before recovery","misn15l3.des");return
            else s.neLost=true end
        end
    end
    Recover("nw",M.cam2);Recover("ne",M.cam3)
    if age>180 and not s.nw and not s.nwReminder then s.nwReminder=true;AudioMessage("misn1511.wav");SetObjectiveOn(M.cam2) end
    if age>240 and not s.ne and not s.neLost and not s.neReminder then s.neReminder=true;AudioMessage("misn1512.wav");SetObjectiveOn(M.cam3) end
    UpdateTartarus();UpdateReports();UpdateFuries();UpdateShots();UpdateObjectives()
    if Alive(M.recy) and s.cca and s.nw and GetScrap(LEADER_TEAM)>=75 and Distance(M.recy,M.cam5)<200 and NearAll(M.cam5,300) then
        M.won=true;AudioMessage("misn1510.wav");UpdateObjectives(true)
        TitanHook("beat","win");SucceedMission(GetTime()+10,"misn15w1.des")
    end
end
function R.Start()
    State()
    CRCoop.Initialize({getLocalPlayerId=function() return exu.GetMyNetID and exu.GetMyNetID() end,
        leaderTeam=1,humanTeamMin=1,humanTeamMax=4,rallyPoints={[0]="avrecy0_recycler"},
        onOutOfLives=function() FinishFailure("A squad member is out of lives") end})
    ConfigureAlliances();ResetPresentation();lastAudio=nil
    if startedWeather then TitanHook("shutdown") end
    startedWeather=false
    pda.Initialize()
    subtit.Initialize()
end
function R.AddObject(h)
    if not Valid(h) then return end
    local s=State()
    if IsOdfBase(h,"avscav") then Remember(s.scavengers,h) end
    if IsOdfBase(h,"absilo") or IsOdfBase(h,"avmuf") then Remember(s.stores,h) end
    TitanHook("object",h)
end
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
    subtit.Update();CRCoop.Update();UpdatePresentationTransport()
    pda.UpdateInputs(localCameraActive);pda.UpdateHeadlights()
    if CRCoop.IsNetworkGame() then
        if CRCoop.HasLeaderDeparted() then
            if not M.coopResult then M.coopResult=true;native.FailMission(GetTime()+1) end
            return
        end
        if CRCoop.HasUnsupportedPlayerTeam() or CRCoop.HasLateJoiners() then
            if not s.restartWarned then
                s.restartWarned=true;DisplayMessage("Use distinct teams 1-4 and start together. Late join/rejoin requires a restart.")
            end
            return
        end
        if not CRCoop.IsSessionReady() then return end
    end
    if not s.missionStarted then CRCoop.MarkMissionStarted();s.missionStarted=true end
    M.coopMissionStarted=true
    if not startedWeather then
        startedWeather=true
        TitanHook("init",{authority=CRCoop.IsAuthority(),mission="misn15",
            send=CRCoop.IsAuthority() and function(op,...)
                if IsTitanOp(op) then events[#events+1]={op=op,args={...},n=select("#",...),ttl=RESOLVE_TIMEOUT} end
            end or nil})
        if CRCoop.IsAuthority() and M.titanWeather then TitanHook("load",M.titanWeather) end
        if CRCoop.IsAuthority() then TitanHook("beat","start") end
    end
    TitanHook("update",dt)
    if not CRCoop.IsAuthority() or M.coopResult or M.coopPendingResult or M.lost or M.won then return end
    if not M.start_done then Bootstrap() end
    if M.start_done and not M.lost then UpdateStory() end
    if not Alive(M.recy) then
        local respawn=CRCoop.GetRespawn()
        if respawn then respawn.SetRallyPoints({}) end
    end
end
function R.Save()
    State()
    if startedWeather and CRCoop.IsAuthority() then M.titanWeather=TitanHook("save") end
end
function R.Load()
    local s=State()
    -- A new Lua state is used by native loads; also handle in-state fixture loads.
    if startedWeather then TitanHook("shutdown") end
    startedWeather=false
    s.objectiveKey=nil;s.nextObjectives=0
    R.Start()
end
R.Coop, R.Exu, R.Native = CRCoop, exu, native
return R
end
return Runtime
