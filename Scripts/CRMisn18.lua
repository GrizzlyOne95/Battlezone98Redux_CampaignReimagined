-- Mission 18 (The Ultimate Quake) ownership, concealed Fury arrivals, shared presentation and
-- the optional storm hook. Ordered E/A + C transport adapted from Mission 17 (itself from 16);
-- gameplay stays in misn18.lua. Docs/MISN18_COOP.md is the contract for everything below.
local Runtime = {}
function Runtime.Create(getState)
local M = getState()
local LEADER_TEAM, FURY_TEAM = 1, 6
local LIVE_CAP = 12          -- live scripted Furies; only the co-op extras are ever dropped for it
local SAFE_RADIUS = 460      -- nothing is built this close to any human (fog is typically 250 m)
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})
local exu = require("exu")
if type(IsNetGame)=="function" and IsNetGame() then
    assert(exu.DisableStartingRecycler and exu.GetMyNetID,"misn18 needs bundled EXU co-op hooks")
    exu.DisableStartingRecycler()
end
local CRCoop = require("CRCoop")
local subtit = require("ScriptSubtitles")
local pda = require("PersistentConfig")
local Environment = require("Environment")
local roster = require("CRFuryRoster")
SetAIControl(FURY_TEAM,true) -- startup only; never enable strategic AI on humans
local unpackArgs = unpack or table.unpack
local OWN_CHANNELS = { E = true, C = true, A = true }
-- Redux reads a Lua packet string's length through a signed byte (FUN_005059B0), so a
-- 128-255 byte string crashes every receiving peer. CRWire splits long strings.
local CRWire = require("CRWire")
-- The faithful body calls GetPlayerHandle() once per update; in this runtime it receives this token and
-- the Distance wrapper turns it into "the humans" (nearest for approach triggers, farthest for the
-- recycler gates). It is also the camera subject of the left-behind shot: every peer films its own ship.
local PLAYERS = "crco18_players"
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
    StopAudioMessage = StopAudioMessage, GetPlayerHandle = GetPlayerHandle,
    StartCockpitTimer = StartCockpitTimer, StopCockpitTimer = StopCockpitTimer, HideCockpitTimer = HideCockpitTimer,
    StartEarthquake = StartEarthquake, UpdateEarthQuake = UpdateEarthQuake,
    Play = subtit.Play, Queue = subtit.Queue, Stop = subtit.Stop,
}

-- Optional storm director (Scripts/CRStorm18.lua, built separately). Absent, broken or partial: every call
-- below is a no-op and the mission is unchanged. Same shape as the CRJungle17 wiring in CRMisn17.
local Storm
local stormFailed = {}
do
    local okModule, module = pcall(require, "CRStorm18")
    if okModule and type(module) == "table" then
        if type(module.Create) == "function" then
            local okCreate, director = pcall(module.Create, { exu = exu, state = function() return M end,
                -- Leader targeting for the tornado: where every human currently is.
                players = function()
                    local list = {}
                    CRCoop.ForEachPlayerHandle(function(h)
                        if IsValid(h) then list[#list + 1] = GetPosition(h) end
                    end)
                    return list
                end })
            if okCreate and type(director) == "table" then Storm = director
            else print("[misn18] CRStorm18.Create failed: " .. tostring(director)) end
        else
            Storm = module
        end
    end
end
local function StormCall(name, ...)
    if not Storm or type(Storm[name]) ~= "function" then return nil end
    local ok, result = pcall(Storm[name], ...)
    if not ok then
        if not stormFailed[name] then
            stormFailed[name] = true
            print("[misn18] CRStorm18." .. name .. " failed: " .. tostring(result))
        end
        return nil
    end
    return result
end

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

-- The extraction ending's choreography (Scripts/CRDrop18.lua). Absent or broken: the win ends the mission at once.
local okDrop, Drop = pcall(require, "CRDrop18")
if not okDrop or type(Drop) ~= "table" then Drop = nil end
-- Implemented with the extraction section below; the presentation adapter dispatches to them.
local ExtractShipEvent, ExtractGoEvent, ExtractStop
local EXTRACT_OPS = { ExtractShip = true, ExtractGo = true, StopCockpitTimer = true }

local function ApplyPresentation(op, ...)
    if op == "Storm" then return StormCall("Apply", ...) end
    if op == "ExtractShip" then return ExtractShipEvent(...) end
    if op == "ExtractGo" then return ExtractGoEvent(...) end
    if op == "StopCockpitTimer" then
        -- The ending ends the countdown: the result is the extraction, whatever the clock says.
        if type(native.StopCockpitTimer) == "function" then pcall(native.StopCockpitTimer) end
        if type(native.HideCockpitTimer) == "function" then pcall(native.HideCockpitTimer) end
        return
    end
    if op == "Label" then
        local handle, label = ...
        if type(SetLabel) == "function" and IsValid(handle) and type(label) == "string" then
            pcall(SetLabel, handle, label)
        end
    elseif op == "StartEarthquake" or op == "UpdateEarthQuake" then
        -- While the storm runs it owns the native earthquake: the mission's request (the stock
        -- discovery quake and the restored pulse) becomes one of its envelopes and the strongest wins.
        -- Without a storm (absent, stopped, failed) the mission shakes the engine itself, as before.
        if not StormCall("Quake", (...)) then return native[op](...) end
    elseif op == "SucceedMission" or op == "FailMission" then
        StormCall("Stop")
        ExtractStop()
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
        pcall(SetLabel, handle, "crco18_" .. labelSerial)
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
    -- "L" (left behind) carries only the climb height: each peer's subject is its own ship.
    if frame[1] == "L" then return { "L", frame[2] } end
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
-- The quake and the countdown are shared presentation: every peer shakes and shows the leader's timer.
local function StartEarthquake(...) return Present("StartEarthquake", ...) end
local function UpdateEarthQuake(...) return Present("UpdateEarthQuake", ...) end
local function NativeCountdown(...) return Present("StartCockpitTimer", ...) end
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
        M.coopPendingResult = { op, when, description, ready = GetTime() + (op == "SucceedMission" and 3.5 or 0) }
    else
        -- Offline the DLL re-issues these every frame it holds; stay a pass-through.
        native[op](when, description)
    end
end
local BeginExtraction -- the extraction ending (below): called with the win, returns true when it took over
local function SucceedMission(when, description)
    if BeginExtraction and BeginExtraction(when, description) then return end
    return EndMission("SucceedMission", when, description)
end
-- Once the win has latched nothing can fail the mission (the extraction is under way).
local function FailMission(...)
    if M.missionwon then return end
    return EndMission("FailMission", ...)
end

local function CameraReady()
    cameraGeneration = cameraGeneration + 1
    cameraSkipped = false
    -- One shot at a time: a new shared shot replaces the old one,
    -- so the native camera stack stays balanced offline too.
    if localCameraActive then native.CameraFinish() end
    localCameraActive = true
    return native.CameraReady()
end
local function CameraPath(path, height, speed, target)
    if not IsValid(target) then target = nil end
    cameraFrame = { "P", path, height, speed, target }
    if native.CameraCancelled() then
        cameraSkipped = true
        if localCameraActive then native.CameraFinish() end
        localCameraActive = false
    end
    if not cameraSkipped then return native.CameraPath(path, height, speed, target) end
end
local function CameraObject(subject, x, y, z, target)
    if subject == PLAYERS then
        -- Left behind [owner]: no replicated shot. The leader streams only the height; this peer
        -- and every guest film their own ship.
        cameraFrame = { "L", y }
        if cameraSkipped then return end
        local me = native.GetPlayerHandle()
        if not IsValid(me) then return false end
        local done = native.CameraObject(me, x, y, z, me)
        if native.CameraCancelled() then
            cameraSkipped = true
            local wasActive = localCameraActive
            localCameraActive = false
            if wasActive then native.CameraFinish() end
        end
        return done
    end
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
    if wasActive then return native.CameraFinish() end
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
    if cam.kind == "L" then
        -- Left behind: this peer's own ship, at the leader's height.
        local me = native.GetPlayerHandle()
        if not IsValid(me) then return end
        if not localCameraActive then
            native.CameraReady()
            localCameraActive = true
        end
        native.CameraObject(me, 1, cam.y, 1000, me)
        if native.CameraCancelled() then
            cameraSkipped = true
            localCameraActive = false
            native.CameraFinish()
        end
        return
    end
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
    -- Only the events queued up to the first pass after the result was requested must be acknowledged; a storm that
    -- keeps sending (the ascent strikes every few tenths of a second) must never hold the result back.
    local pending = M.coopPendingResult
    if pending and not pending.upto then pending.upto = #events end
    for id, player in pairs(CRCoop.GetPlayers()) do
        if CRCoop.IsHumanTeam(player.team) and id ~= CRCoop.GetLocalPlayerId() then
            local ack = acknowledgements[id] or 0
            if ack < (pending and pending.upto or #events) then allDelivered = false end
            if now >= nextEventSend then
                for seq = ack + 1, math.min(ack + 8, #events) do
                    local event = events[seq]
                    Send(id, "E", CRWire.Pack(seq, event.op, event.ttl, unpackArgs(EventArgs(event), 1, event.n)))
                end
            end
        end
    end
    if now >= nextEventSend then nextEventSend = now + 0.2 end
    if M.coopPendingResult and allDelivered and now >= M.coopPendingResult.ready then
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
            Send(0, "C", CRWire.Pack(cameraSerial, cameraGeneration, ""))
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
            elseif camKind == "L" and type(a) == "number" then
                cam = { generation = generation, kind = "L", y = a }
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
    if seq == receivedEvent + 1 and (native[op] or op == "Label" or op == "Storm" or EXTRACT_OPS[op]) then
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
    Send(from, "A", CRWire.Pack(receivedEvent))
    return true
end

-- Presentation adapter ends.

-- The DLL's AudioMessage(file) is the shared radio line: the leader plays it and every peer hears it with
-- its subtitle. ScriptSubtitles.Play stops whatever line is still playing, while native AudioMessage
-- queued; so a line that starts while the previous one is still talking is queued behind it (the leader
-- decides, guests follow the same op). Returns the native audio handle on the leader.
-- The DLL really names misn1704.wav for the Texas loss; Redux ships the dedicated misn1818.wav ("the Texas has
-- been destroyed"), restored here by substituting the file (the faithful body keeps the original line).
local AUDIO_SUBSTITUTE = { ["misn1704.wav"] = "misn1818.wav" }
local lastAudio
local function AudioMessage(file)
    file = AUDIO_SUBSTITUTE[file] or file
    if M.missionwon and file == "misn1818.wav" then return nil end -- nothing may report a loss after the win
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

local R = {}
local function State()
    M=getState()
    M.cr18=M.cr18 or {arrivals={},serial=0,live={}}
    return M.cr18
end
local function Valid(h) return h~=nil and h~=0 and IsValid(h) end
local function Ticket(h)
    if type(h)~="number" or h>=0 then return nil end
    return State().arrivals[-h]
end
function R.IsAlive(h)
    -- Negative request ids reserve a Fury slot while its entry is concealed. They never reach a native
    -- handle API or cross the network.
    if Ticket(h) then return true end
    return Valid(h) and IsAlive(h)
end
local function ConfigureAlliances()
    for a=1,4 do
        for b=1,4 do if a~=b then Ally(a,b) end end
        Ally(a,7);Ally(7,a)
        UnAlly(a,FURY_TEAM);UnAlly(FURY_TEAM,a)
    end
end
local function HumanCount()
    local count=0
    CRCoop.ForEachHumanTeam(function() count=count+1 end)
    return math.max(1,math.min(4,count))
end

-- ---------------------------------------------------------------- humans as one trigger
-- Nearest human for the approach triggers (AnyPlayerSatisfies), farthest human for the recycler gates
-- (AllPlayersNear): the win needs every human inside 200 m, the countdown failure fires when any is past
-- 400 m. A human with no live ship counts as far; no live human at all is infinitely far.
local function HumanSpread(to,farthest)
    local best
    CRCoop.ForEachPlayerHandle(function(h)
        local d=GetDistance(h,to)
        if best==nil or (farthest and d>best) or (not farthest and d<best) then best=d end
    end)
    if best==nil then return math.huge end
    if farthest and CRCoop.IsNetworkGame() and not CRCoop.HasAllPlayerHandles() then return math.huge end
    return best
end
function R.WrapDistance(original)
    return function(from,to)
        if from~=PLAYERS then return original(from,to) end
        if to==nil or to==0 then return math.huge end
        if type(to)~="string" and not Valid(to) then return math.huge end
        return HumanSpread(to,to~=nil and to==getState().avrec)
    end
end
function R.GetPlayerHandle() return PLAYERS end

-- ---------------------------------------------------------------- concealed Fury arrivals
-- Entry is the authored spawn when no human is within SAFE_RADIUS; otherwise another authored approach;
-- otherwise the request waits. Requests are saved in M.cr18, so a load neither loses nor duplicates them.
local FALLBACK_ENTRIES={"spawnrand","spawnrand2","spawn1b","spawn2b","spawn3b","spawnalt2b","spawnalt3b"}
local function Safe(where)
    if type(where)~="string" and not Valid(where) then return false end
    local safe=true
    CRCoop.ForEachPlayerHandle(function(h)
        if Valid(h) and GetDistance(h,where)<SAFE_RADIUS then safe=false end
    end)
    return safe
end
local function Entry(request)
    if Safe(request.where) then return request.where end
    for _,path in ipairs(FALLBACK_ENTRIES) do
        if Safe(path) then return path end
    end
end
local function ReplaceTickets(t,old,new)
    for k,v in pairs(t) do
        if v==old then t[k]=new
        elseif type(v)=="table" and k~="arrivals" and k~="cr18" then ReplaceTickets(v,old,new) end
    end
end
local function Issue(op,h,a,b)
    if not Valid(h) then return end
    if op=="Attack" or op=="Defend2" then
        if not Valid(a) then return end
    end
    if b==nil then return _G[op](h,a) end
    return _G[op](h,a,b)
end
function R.Order(op,h,a,b)
    local request=Ticket(h)
    if request then
        request.orders[#request.orders+1]={op,a,b}
        for _,id in ipairs(request.extras or {}) do
            local extra=State().arrivals[id]
            if extra then extra.orders[#extra.orders+1]={op,a,b} end
        end
        return
    end
    return Issue(op,h,a,b)
end
local function Ended()
    return M.missionwon or M.fail1 or M.fail2 or M.fail3 or M.coopResult or M.coopFailed
end
-- A scripted spawn event (wave, timed raid, don't-go ambush, recycler assault, return wave) opens with
-- BeginEvent; the first Fury the body then builds is mirrored by floor(humans/2) extras of the same kind,
-- orders and entry [owner]. Extras queue behind it and are the only requests dropped by the live cap.
function R.BeginEvent()
    local s=State()
    s.event={extras=math.floor(HumanCount()/2),made=false}
end
function R.Spawn(odf,team,where)
    local s=State()
    if not CRCoop.IsAuthority() then return nil end
    if team==2 then team=FURY_TEAM end
    -- The DLL names a path "spawn1" the 1.5 map never contained; spawn1b is the same approach.
    if where=="spawn1" then where="spawn1b" end
    if odf~="hvsav" and odf~="hvsat" then return BuildObject(odf,team,where) end
    if Ended() then return nil end
    s.serial=s.serial+1
    local id=s.serial
    s.arrivals[id]={odf=roster.Select(odf,M),team=team,where=where,orders={}}
    local event=s.event
    if event and not event.made then
        event.made=true
        local primary=s.arrivals[id]
        primary.extras={}
        for _=1,event.extras do
            s.serial=s.serial+1
            s.arrivals[s.serial]={odf=roster.Select(odf,M),team=team,where=where,orders={},extra=true}
            primary.extras[#primary.extras+1]=s.serial
        end
    end
    return -id
end
local function LiveCount(s)
    local alive={}
    for _,h in ipairs(s.live) do
        if Valid(h) and IsAlive(h) then alive[#alive+1]=h end
    end
    s.live=alive
    return #alive
end
local function Arrivals()
    local s=State()
    if Ended() then s.arrivals={};return end
    if M.missionstart and not M.openingcindone then return end
    if s.cin then return end
    local live,built=LiveCount(s),0
    -- Saved request sequence, never pairs order, defines deterministic entry.
    for id=1,s.serial do
        local r=s.arrivals[id]
        if r and built<2 then
            if r.extra and live>=LIVE_CAP then
                s.arrivals[id]=nil
            else
                local where=Entry(r)
                if where then
                    local h=BuildObject(r.odf,r.team,where)
                    if Valid(h) then
                        ReplaceTickets(M,-id,h)
                        for _,order in ipairs(r.orders) do Issue(order[1],h,order[2],order[3]) end
                        s.live[#s.live+1]=h
                        live=live+1
                        s.arrivals[id]=nil;built=built+1
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------- transport-destroyed shot
-- The DLL authors a path "transdestroyedcam" (four points circling the transport) and never films it. The
-- body starts the 180 s countdown the moment the fourth thruster dies; here that call opens the shot instead
-- and the countdown starts when it ends [owner]. Timings, height and speed are CR inferences. The transport
-- (which the body wants dead one tick later) is kept alive for the first part of the shot and blown up on
-- camera; the shot then holds on the path without a target. Everyone sees it; nobody can skip it in a network
-- game (CameraCancelled is false), arrivals are held, and a load mid-shot ends it at once.
local CIN_SECONDS, CIN_BLOW_AT = 8, 4
local CIN_HEIGHT, CIN_SPEED = 1500, 600
local function StartCountdown(c)
    local s=State()
    s.timerStarted=true
    -- The engine cannot keep this clock: MultSTMission calls StartCockpitTimerUp every frame, so GetCockpitTimer reads the
    -- mission clock whatever StartCockpitTimer asked for (live 2026-10-19). The leader counts the 180 s itself.
    s.timerEnd=GetTime()+(tonumber(c.timer and c.timer[1]) or 180)
    NativeCountdown(unpackArgs(c.timer,1,3))
end
local function FinishShot()
    local s=State()
    local c=s.cin
    if not c then return end
    s.cin=nil
    if Valid(M.transport) and IsAlive(M.transport) then Damage(M.transport,999999999.0) end
    CameraFinish()
    StartCountdown(c)
end
function R.StartCockpitTimer(...)
    local s=State()
    if s.cin or s.timerStarted then return end
    local now=GetTime()
    s.cin={start=now,blow=now+CIN_BLOW_AT,over=now+CIN_SECONDS,timer={...}}
    CameraReady()
end
function R.GetCockpitTimer()
    -- Until the countdown starts the gates must see a full clock, not the engine's idle zero.
    local s=State()
    if s.cin then return 180 end
    if s.timerEnd then return math.max(0,s.timerEnd-GetTime()) end
    return GetCockpitTimer()
end
function R.Damage(h,amount)
    local c=State().cin
    if c and h~=nil and h==M.transport and not c.blown then c.deferred=true;return end
    return Damage(h,amount)
end
local function Shot()
    local s=State()
    local c=s.cin
    if not c then return end
    local now=GetTime()
    if now>=c.blow and not c.blown then
        c.blown=true
        if Valid(M.transport) and IsAlive(M.transport) then Damage(M.transport,999999999.0) end
    end
    if now>=c.over then FinishShot();return end
    local target=Valid(M.transport) and IsAlive(M.transport) and M.transport or nil
    CameraPath("transdestroyedcam",CIN_HEIGHT,CIN_SPEED,target)
end

-- ---------------------------------------------------------------- extraction ending
-- The win does not end the mission at once. The leader plans the ending (Scripts/CRDrop18.lua): one NSDF
-- dropship per human ship plus one for the Recycler and Factory when either lives, on a ring around the Texas
-- (inside the storm's tornado keep-clear zone). Shot 1 films them land, load and lift; shot 2 follows one
-- climbing through the storm. Only then does the mission succeed and the normal outro play.
--
-- Replication: the plan goes out as numbers (one ExtractShip event per ship, then ExtractGo), the camera is the
-- streamed shot kind "O" (labels resolved on guests, CameraCancelled is false in network games). The LEADER
-- builds and moves the dropship objects and the base cargo (Recycler, Factory, which it owns); EVERY peer pins
-- its OWN ship aboard from the same clock (the pose is a pure function of the plan and the seconds since
-- ExtractGo, so no pose is ever sent). Each peer starts its clock when it applies ExtractGo, so a guest can
-- trail the leader by the stream latency. Timings, offsets and camera numbers are CR inferences.
-- A save/load mid-ending cannot resume it: the load goes straight to success.
local X = { ships = {}, cargo = {}, hulls = {} }
local function Ground(px, pz)
    local ok, h = pcall(GetTerrainHeightAndNormal, SetVector(px, 0, pz))
    return ok and type(h) == "number" and h or 0
end
local function Num(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end
local function MyTeam()
    local player = CRCoop.GetPlayers()[CRCoop.GetLocalPlayerId()]
    return player and player.team or 1
end
local function Facing(ship) return SetVector(-ship.sx, 0, -ship.sz) end -- the bow faces away from the ramp exit

function ExtractShipEvent(i, n, kind, team, x, z, y, sx, sz)
    if not (Num(i) and Num(n) and Num(kind) and Num(team) and Num(x) and Num(z) and Num(y) and Num(sx) and Num(sz)) then return end
    if i < 1 or i > 5 or n < 1 or n > 5 then return end
    if X.go then return end -- a repeat after the clock started changes nothing
    X.n = n
    X.ships[i] = { kind = kind, team = team, x = x, y = y, z = z, sx = sx, sz = sz, lx = -sz, lz = sx }
end

-- Where this peer's pinned craft stood when the ending began. A craft carried by a ship keeps its heading.
local function Cargo(h, slot, i)
    if not Valid(h) then return end
    local p = GetPosition(h)
    local f = type(GetFront) == "function" and GetFront(h) or nil
    X.cargo[#X.cargo + 1] = { h = h, slot = slot, ship = i,
        start = { x = p.x, y = p.y, z = p.z, dx = f and f.x or 0, dz = f and f.z or 1 } }
end

function ExtractGoEvent()
    if X.go or not Drop then return end
    for i = 1, X.n or 0 do if not X.ships[i] then return end end -- incomplete plan: do nothing
    X.go, X.t0, X.cargo = true, GetTime(), {}
    local team = MyTeam()
    for i = 1, X.n do
        local ship = X.ships[i]
        if ship.kind == 1 and ship.team == team then
            Cargo(native.GetPlayerHandle(), Drop.SLOTS.human, i)
        elseif ship.kind == 0 and CRCoop.IsAuthority() then
            Cargo(M.avrec, Drop.SLOTS.recycler, i)
            Cargo(GetHandle("avmuf2_factory"), Drop.SLOTS.factory, i)
        end
    end
end

function ExtractStop()
    X.go = false
    X.cargo = {}
end

-- Pin this peer's own craft to the ship pose, and keep it whole (nothing may fail the mission now).
local function PinCargo(t)
    for _, c in ipairs(X.cargo) do
        if Valid(c.h) then
            local x, y, z, dx, dz = Drop.CargoPos(X.ships[c.ship], c.ship, c.slot, c.start, t, Ground)
            pcall(SetTransform, c.h, BuildDirectionalMatrix(SetVector(x, y, z), SetVector(dx, 0, dz)))
            if type(IsCraft) == "function" and IsCraft(c.h) then pcall(SetVelocity, c.h, SetVector(0, 0, 0)) end
            if type(SetCurHealth) == "function" and type(GetMaxHealth) == "function" then
                pcall(SetCurHealth, c.h, GetMaxHealth(c.h))
            end
        end
    end
end

-- Leader: the dropship objects. A stage change swaps the object (floor collision is snapshotted at creation).
local function DriveHulls(t)
    for i = 1, X.n do
        local ship = X.ships[i]
        local stage = Drop.Stage(i, t)
        local odf = Drop.Odf(stage)
        local hull = X.hulls[i]
        local px, py, pz = Drop.HullPos(ship, i, t)
        local matrix = BuildDirectionalMatrix(SetVector(px, py, pz), Facing(ship))
        if not hull or hull.odf ~= odf or not Valid(hull.h) then
            if hull and Valid(hull.h) then native.RemoveObject(hull.h) end
            local h = BuildObject(odf, 1, matrix)
            X.hulls[i] = { odf = odf, h = h }
        else
            pcall(SetTransform, hull.h, matrix)
        end
    end
end

local function FinishExtraction(s)
    if s.extractDone then return end
    s.extractDone = true
    if X.pod and Valid(X.pod) then native.RemoveObject(X.pod) end
    X.pod = nil
    CameraFinish()
    EndMission("SucceedMission", GetTime() + 2.0, s.ext and s.ext.desc)
end

function BeginExtraction(when, description)
    local s = State()
    if not Drop or s.ext or s.extractDone or not CRCoop.IsAuthority() then return false end
    local humans = {}
    CRCoop.ForEachPlayerHandle(function(h, id)
        local player = CRCoop.GetPlayers()[id]
        if Valid(h) then humans[#humans + 1] = { team = player and player.team or 1, h = h } end
    end)
    if #humans == 0 then
        local me = native.GetPlayerHandle()
        if Valid(me) then humans[1] = { team = 1, h = me } end
    end
    if #humans == 0 then return false end
    table.sort(humans, function(a, b) return a.team < b.team end)
    local factory = GetHandle("avmuf2_factory")
    local base = (Valid(M.avrec) and IsAlive(M.avrec)) or (Valid(factory) and IsAlive(factory))
    local count = math.min(Drop.MAX_SHIPS, #humans + (base and 1 or 0))
    local center = Valid(M.avrec) and GetPosition(M.avrec) or GetPosition(humans[1].h)
    local sites = Drop.Sites(center.x, center.z, count, Ground)
    s.ext = { t0 = GetTime(), desc = description, n = count }
    X = { ships = {}, cargo = {}, hulls = {} }
    -- The threats are gone, the countdown is over and the humans cannot be hurt: the win is final.
    s.arrivals = {}
    if type(AllCraft) == "function" then
        for h in AllCraft() do
            if GetTeamNum(h) == FURY_TEAM then native.RemoveObject(h) end
        end
    end
    Present("StopCockpitTimer")
    for i = 1, count do
        local ship, human = sites[i], humans[i]
        Present("ExtractShip", i, count, human and 1 or 0, human and human.team or 0, ship.x, ship.z, ship.y, ship.sx, ship.sz)
    end
    Present("ExtractGo")
    -- The camera pod stands outside the ring in a gap between two ships, looking at the Texas.
    local phi = math.atan2(sites[1].z - center.z, sites[1].x - center.x) + math.pi / count
    local px, pz = center.x + math.cos(phi) * 330, center.z + math.sin(phi) * 330
    X.pod = BuildObject(Drop.POD, 0, SetVector(px, Ground(px, pz), pz))
    CameraReady()
    s.phase = "extract"
    StormCall("SetPhase", "extract")
    return true
end

local function Extraction()
    local s = State()
    if not s.ext or s.extractDone then return end
    if not X.go then
        -- A load, or a plan that could not start: straight to success.
        FinishExtraction(s)
        return
    end
    local t = GetTime() - X.t0
    DriveHulls(t)
    local lead = X.hulls[1] and X.hulls[1].h
    if t < Drop.SHOT1 then
        -- Shot 1: from outside the ring, on the Texas the ships gather round.
        local target = Valid(M.avrec) and M.avrec or lead
        if Valid(X.pod) and Valid(target) then CameraObject(X.pod, 0, 4000, 0, target) end
    else
        if s.phase ~= "ascent" then
            s.phase = "ascent"
            StormCall("SetPhase", "ascent")
        end
        -- Shot 2: beside and below the lead ship as it climbs into the clouds.
        if Valid(lead) then CameraObject(lead, 4000, -1000, 7000, lead) end
    end
    if t >= Drop.Total() then FinishExtraction(s) end
end

-- ---------------------------------------------------------------- results and scaling
local function Failure()
    if not CRCoop.IsAuthority() or M.missionwon or Ended() then return end
    M.coopFailed=true
    FailMission(GetTime()+7,"misn18l2.des")
end
function R.SetScrap(team,amount)
    -- One shared production base, with a bounded +10 starting scrap per guest.
    return SetScrap(1,amount+10*(HumanCount()-1))
end

-- ---------------------------------------------------------------- storm phases
-- Phases are derived from the leader's mission flags, emitted once each and strictly in this order. A phase
-- whose moment passed is skipped, never replayed late. "won"/"lost" end the sequence.
local PHASES={
    {"opening",function() return true end},
    {"search",function() return M.openingcindone end},
    {"found",function() return M.transportfound end},
    {"core1",function() return (M.z or 0)>=1 end},
    {"core2",function() return (M.z or 0)>=2 end},
    {"core3",function() return (M.z or 0)>=3 end},
    {"collapse",function() return M.transdestroyed end},
    {"final",function() return M.transdestroyed and State().timerStarted and not M.missionwon and R.GetCockpitTimer()<=30 end},
}
local function EmitPhase(s,name)
    s.phase=name
    StormCall("SetPhase",name)
end
local function Phases()
    local s=State()
    s.phases=s.phases or {}
    if s.terminal then return end
    if M.missionwon then
        -- The ending (extract, ascent) runs first; the storm settles into "won" when it has finished.
        if s.ext and not s.extractDone then return end
        s.terminal=true;EmitPhase(s,"won");return
    end
    if M.fail1 or M.fail3 or M.blastoff or M.coopFailed then s.terminal=true;EmitPhase(s,"lost");return end
    for rank,entry in ipairs(PHASES) do
        local name=entry[1]
        if rank>(s.phaseRank or 0) and entry[2]() then
            s.phaseRank=rank
            EmitPhase(s,name)
        end
    end
end
R.Phases=Phases

-- ---------------------------------------------------------------- engine callbacks
function R.Start()
    State().started=nil
    CRCoop.Initialize({getLocalPlayerId=function() return exu.GetMyNetID and exu.GetMyNetID() end,
        leaderTeam=1,humanTeamMin=1,humanTeamMax=4,rallyPoints={[0]="avrecy2_recycler"},
        onOutOfLives=Failure})
    if localCameraActive then native.CameraFinish() end
    ConfigureAlliances();ResetPresentation();ExtractStop();lastAudio=nil
    pda.Initialize();subtit.Initialize()
    -- Night on Achilles: the sun is down behind the moon and a gibbous Uranus
    -- lights the valley until the storm closes over it (CRStorm18 keeps the CR
    -- dome up to the found phase). Visual only; sensors keep their day ranges.
    Environment.Init({nativeBaseline=true,lightingMode="night",nightGameplay=false,
        skySun={azimuth=55,elevation=-28}})
    StormCall("Reset",State().storm)
    if Storm then pcall(Environment.BindWeatherSensors,"Achilles",Storm) end
    -- After a load the leader tells the (idempotent) director where the mission stands.
    if State().phase and CRCoop.IsAuthority() then StormCall("SetPhase",State().phase) end
    -- A load mid-shot cannot resume it (the cameras are gone): the transport falls and the countdown starts now.
    if State().cin and CRCoop.IsAuthority() then FinishShot() end
end
function R.AddObject(h)
    if Valid(h) then Environment.OnObjectCreated(h) end
    StormCall("AddObject",h)
end
function R.CreatePlayer(id,name,team) CRCoop.CreatePlayer(id,name,team);ConfigureAlliances() end
function R.AddPlayer(id,name,team) CRCoop.AddPlayer(id,name,team);ConfigureAlliances() end
function R.DeletePlayer(id) CRCoop.DeletePlayer(id) end
function R.Receive(from,kind,...)
    State()
    -- Only this file's channels are wire-encoded; CRCoop's own packets pass through untouched.
    if OWN_CHANNELS[kind] and ReceivePresentation(from,kind,CRWire.Unpack(...)) then return true end
    return CRCoop.Receive(from,kind,...)
end
function R.Update(dt)
    local s=State()
    subtit.Update();CRCoop.Update();UpdatePresentationTransport()
    pda.UpdateInputs(localCameraActive);pda.UpdateHeadlights()
    if CRCoop.IsNetworkGame() then
        if CRCoop.HasLeaderDeparted() then
            if not M.coopResult then
                M.coopResult=true
                if localCameraActive then native.CameraFinish();localCameraActive=false end
                native.FailMission(GetTime()+1)
            end
            return false
        end
        if CRCoop.HasUnsupportedPlayerTeam() or CRCoop.HasLateJoiners() or not CRCoop.IsSessionReady() then return false end
    end
    Environment.Update(dt)
    if not s.started then CRCoop.MarkMissionStarted();s.started=true end
    M.coopMissionStarted=true
    if not M.coopResult then
        StormCall("Update",dt,CRCoop.IsAuthority(),function(...) Present("Storm",...) end)
        M.cr18Storm=StormCall("Describe")
    end
    if X.go and Drop and not M.coopResult then PinCargo(GetTime()-X.t0) end
    if not CRCoop.IsAuthority() or M.coopResult then return false end
    if not s.phase then Phases() end -- "opening" before the body's first frame
    Shot()
    Extraction()
    Arrivals()
    return true
end
function R.AfterUpdate()
    if CRCoop.IsAuthority() then Phases() end
end
function R.Save() State().storm=StormCall("Save") end
function R.Load() M=getState();R.Start() end
R.Coop,R.Exu,R.Native=CRCoop,exu,native
R.Storm=Storm
R.AudioMessage,R.StopAudioMessage=AudioMessage,StopAudioMessage
R.CameraReady,R.CameraPath,R.CameraObject=CameraReady,CameraPath,CameraObject
R.CameraFinish,R.CameraCancelled=CameraFinish,CameraCancelled
R.SetObjectiveName,R.SetObjectiveOn,R.SetObjectiveOff=SetObjectiveName,SetObjectiveOn,SetObjectiveOff
R.ClearObjectives,R.AddObjective,R.RemoveObject=ClearObjectives,AddObjective,RemoveObject
R.StartEarthquake,R.UpdateEarthQuake=StartEarthquake,UpdateEarthQuake
R.SucceedMission,R.FailMission=SucceedMission,FailMission
function R.Goto(h,path,priority) return R.Order("Goto",h,path,priority) end
function R.SetIndependence(h,value) return R.Order("SetIndependence",h,value) end
function R.Attack(h,target,priority) return R.Order("Attack",h,target,priority) end
R.QUAKE_CAP=12
return R
end
return Runtime
