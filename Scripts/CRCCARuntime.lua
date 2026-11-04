-- CRCCARuntime: the shared co-op / offline runtime for the Soviet-side CCA campaign (misns1..misns8).
-- Mission-agnostic: everything mission specific arrives in the CONFIG table given to Create
-- (Docs/CCA_COOP_RUNTIME.md is the contract). The thin mission wrapper (Scripts/misns1cr.lua) keeps the
-- faithful DLL port byte-for-byte, shadows the natives it calls with this runtime's R.* functions inside
-- marked "-- CR ..." regions, and forwards Start/Update/Save/Load/Receive.
--
-- The generic parts were extracted from Scripts/CRMisn18.lua (which is left untouched): ordered, acknowledged
-- E/A event stream and C camera stream over CRWire, label resolution, subtitle audio, objective replication,
-- the PLAYERS token with nearest/farthest distance semantics, concealed spawn tickets, per-event co-op extras,
-- scrap per guest, leader-departed failure, Venus (or any) weather, Save/Load.
--
-- Rules it enforces: only the authority (host or the offline player) runs gameplay; guests only present;
-- nothing scripted is built within SAFE_RADIUS of any human; Lua packet strings stay < 128 bytes (CRWire);
-- every optional subsystem (weather, sites, hooks) is pcall'd, because any Lua error can close the host.
local Runtime = {}

local unpackArgs = unpack or table.unpack
local OWN_CHANNELS = { E = true, C = true, A = true }
local GONE = "!"
-- Guests WAIT for the real object. Only a never-hang guard: it logs "[coop] unresolved ..." and counts it in
-- M.coopUnresolved (the harness expects zero).
local RESOLVE_TIMEOUT = 15

local function Log(id, text) print("[" .. tostring(id) .. "] " .. tostring(text)) end

function Runtime.Create(getState, config)
config = config or {}
local ID = config.id or "cca"
local M = getState()
local LEADER_TEAM = config.leaderTeam or 1
local ENEMY_TEAM = config.enemyTeam or 5
local MAP_ENEMY_TEAM = config.mapEnemyTeam or 2
local SUPPORT_TEAM = config.supportTeam or 7
local SAFE_RADIUS = config.safeRadius or 460
local LIVE_CAP = config.liveCap or 12
local MAX_EXTRAS = config.maxExtrasPerEvent or 2
local SCRAP_PER_GUEST = config.scrapPerGuest or 10
local BUILDS_PER_FRAME = config.buildsPerFrame or 2
local SCALED = config.scaledOdfs or {}
local FALLBACK_ENTRIES = config.fallbackEntries or {}
local AUDIO_SUBSTITUTE = config.audioSubstitute or {}
local FAIL_DES = config.failDes
local hooks = config.hooks or {}
local PLAYERS = "crcca_players"

local RequireFix = require("RequireFix")
RequireFix.Initialize(config.requireFix or { "campaignReimagined", "3686673790" })
local exu = require("exu")
if type(IsNetGame) == "function" and IsNetGame() then
    assert(exu.DisableStartingRecycler and exu.GetMyNetID, ID .. " needs bundled EXU co-op hooks")
    exu.DisableStartingRecycler()
end
local CRCoop = require("CRCoop")
local subtit = require("ScriptSubtitles")
local pda = require("PersistentConfig")
local Environment = require("Environment")
local CRWire = require("CRWire")
-- Single-player difficulty (co-op locks it to Medium). Optional: without DiffUtils nothing is scaled.
local hasDiff, DiffUtils = pcall(require, "DiffUtils")
if not hasDiff then DiffUtils = nil end
-- Enemy strategic AI: startup only (chunk root). Never enable it on a human team.
SetAIControl(ENEMY_TEAM, true)

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
    StartCockpitTimerUp = StartCockpitTimerUp,
    StartEarthquake = StartEarthquake, UpdateEarthQuake = UpdateEarthQuake,
    Play = subtit.Play, Queue = subtit.Queue, Stop = subtit.Stop,
}
-- Mission specific presentation ops: config.presentationOps = { Name = function(...) end } run on every peer.
local EXTRA_OPS = config.presentationOps or {}

-- ---------------------------------------------------------------- weather (optional, never fatal)
-- config.weather = { module = "CRVenusWeather", sites = "CRVenusSitesS1", environment = {...},
--   startLevel = 1, targetLevel = 2, ops = {"VenusState",...}, beats = function(W, M, authority) end }
local Weather, weatherFailed = nil, {}
local WEATHER_OPS = {}
local weatherStarted, weatherAnnounced, envStarted = false, false, false
do
    local w = config.weather
    if type(w) == "table" then
        local okModule, module = pcall(require, w.module or "CRVenusWeather")
        local okSites, sites = pcall(require, w.sites or "")
        if okModule and type(module) == "table" and okSites and type(sites) == "table" then
            Weather = { module = module, sites = sites, config = w }
            for _, op in ipairs(w.ops or { "VenusState", "VenusStrike", "VenusErupt", "VenusFog" }) do WEATHER_OPS[op] = true end
        else
            Log(ID, "weather disabled (module or sites missing)")
        end
    end
end
local function WeatherCall(name, ...)
    if not Weather or type(Weather.module[name]) ~= "function" then return nil end
    local ok, result = pcall(Weather.module[name], ...)
    if not ok then
        if not weatherFailed[name] then
            weatherFailed[name] = true
            Log(ID, "weather " .. name .. " failed: " .. tostring(result))
        end
        return nil
    end
    return result
end

-- ---------------------------------------------------------------- presentation transport
local events, acknowledgements = {}, {}
local receivedEvent = 0
local pendingSeq, pendingSince
local cameraWaitSince, cameraGaveUp, cameraLast
local labelSerial, announced = 0, {}
local gaveUp = {}
local nextEventSend, nextCameraSend = 0, 0
local cameraFrame, cameraGeneration, cameraSerial = nil, 0, 0
local remoteCameraSerial, localCameraGeneration = 0, 0
local cameraSkipped, localCameraActive = false, false
local remoteCamera
local objectiveBuffer, lastObjectiveKey

local function ResetPresentation()
    events, acknowledgements, receivedEvent = {}, {}, 0
    pendingSeq, pendingSince = nil, nil
    nextEventSend, nextCameraSend = 0, 0
    cameraFrame, cameraGeneration, cameraSerial = nil, 0, 0
    remoteCamera, remoteCameraSerial, localCameraGeneration = nil, 0, 0
    cameraWaitSince, cameraGaveUp, cameraLast = nil, false, nil
    announced, gaveUp = {}, {}
    cameraSkipped, localCameraActive = false, false
    objectiveBuffer, lastObjectiveKey = nil, nil
end

local function FromLeader(from)
    local player = CRCoop.GetPlayers()[from]
    return player and player.team == LEADER_TEAM
end

local function ApplyPresentation(op, ...)
    if WEATHER_OPS[op] then
        -- Weather events carry no handles: never labelled, never waited on.
        return WeatherCall("ApplyNetEvent", op, ...)
    end
    if EXTRA_OPS[op] then
        local ok, err = pcall(EXTRA_OPS[op], ...)
        if not ok then Log(ID, "presentation op " .. op .. " failed: " .. tostring(err)) end
        return
    end
    if op == "Label" then
        local handle, label = ...
        if type(SetLabel) == "function" and IsValid(handle) and type(label) == "string" then
            pcall(SetLabel, handle, label)
        end
    elseif op == "StopCockpitTimer" then
        if type(native.StopCockpitTimer) == "function" then pcall(native.StopCockpitTimer) end
        if type(native.HideCockpitTimer) == "function" then pcall(native.HideCockpitTimer) end
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

-- Ops whose first argument is a game object travel by identity, never by a bare handle:
-- "@handle@label" (a guest resolves the label first, then the replicated handle), or "!" = gone.
local HANDLE_OPS = { SetObjectiveOn = true, SetObjectiveOff = true, SetObjectiveName = true,
    RemoveObject = true, Label = true }
local WAIT_OPS = { SetObjectiveOn = true, SetObjectiveName = true, Label = true }

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

local function AnnounceLabel(handle, label)
    if announced[handle] == label then return end
    announced[handle] = label
    events[#events + 1] = { op = "Label", args = { "@" .. HandleText(handle) .. "@" .. label, label },
        n = 2, ttl = RESOLVE_TIMEOUT, handle = handle }
end

local function EnsureLabel(handle)
    local label = KnownLabel(handle)
    if not label and type(SetLabel) == "function" then
        labelSerial = labelSerial + 1
        pcall(SetLabel, handle, "crcca_" .. labelSerial)
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

-- Objectives: ClearObjectives + AddObjective... rebuild the whole list. Several missions re-request the same
-- rebuild every frame (misns1 after both outpost buildings fall); on the stream that would grow without bound,
-- so a rebuild is buffered and published at the end of the frame only if the list actually changed.
local function FlushObjectives()
    local buffer = objectiveBuffer
    if not buffer then return end
    objectiveBuffer = nil
    local parts = {}
    for i, entry in ipairs(buffer) do parts[i] = tostring(entry[1]) .. "/" .. tostring(entry[2]) end
    local key = table.concat(parts, "|")
    if key == lastObjectiveKey then return end
    lastObjectiveKey = key
    Present("ClearObjectives")
    for _, entry in ipairs(buffer) do Present("AddObjective", entry[1], entry[2]) end
end
local function ClearObjectives()
    FlushObjectives()
    objectiveBuffer = {}
end
local function AddObjective(text, color)
    if objectiveBuffer then objectiveBuffer[#objectiveBuffer + 1] = { text, color }; return end
    lastObjectiveKey = nil
    return Present("AddObjective", text, color)
end
local function UpdateObjective(...) FlushObjectives(); lastObjectiveKey = nil; return Present("UpdateObjective", ...) end
local function SetObjectiveOn(...) return Present("SetObjectiveOn", ...) end
local function SetObjectiveOff(...) return Present("SetObjectiveOff", ...) end
local function SetObjectiveName(...) return Present("SetObjectiveName", ...) end
local function RemoveObject(...) return Present("RemoveObject", ...) end

-- Subtitle audio: Play stops whatever line is still playing, native AudioMessage queued, so a line that starts
-- while the previous one talks is queued behind it. Returns the native audio handle on the leader.
subtit = setmetatable({
    Play = function(...) return Present("Play", ...) end,
    Queue = function(...) return Present("Queue", ...) end,
    Stop = function(...) return Present("Stop", ...) end,
}, { __index = subtit })

local function EndMission(op, when, description)
    if M.coopResult or M.coopPendingResult then return end
    FlushObjectives()
    if CRCoop.IsNetworkGame() then
        -- Flush preceding narrative before publishing the result; keep a few seconds for result retries.
        M.coopPendingResult = { op, when, description, ready = GetTime() + (op == "SucceedMission" and 3.5 or 0) }
    else
        -- Offline the DLL re-issues these every frame it holds; stay a pass-through.
        native[op](when, description)
    end
end
local function WonLatched()
    for _, flag in ipairs(config.wonFlags or {}) do
        if M[flag] then return true end
    end
    return false
end
local function SucceedMission(when, description) return EndMission("SucceedMission", when, description) end
local function FailMission(...)
    if WonLatched() then return end
    return EndMission("FailMission", ...)
end

-- ---------------------------------------------------------------- cameras
local function CameraReady()
    cameraGeneration = cameraGeneration + 1
    cameraSkipped = false
    -- One shot at a time: a new shared shot replaces the old one, so the native camera stack stays balanced.
    if localCameraActive then native.CameraFinish() end
    localCameraActive = true
    return native.CameraReady()
end
local function SkipCheck()
    if native.CameraCancelled() then
        cameraSkipped = true
        local wasActive = localCameraActive
        localCameraActive = false
        if wasActive then native.CameraFinish() end
    end
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
    cameraFrame = { "O", subject, x, y, z, target }
    if cameraSkipped then return end
    local done = native.CameraObject(subject, x, y, z, target)
    SkipCheck()
    return done
end
local function CameraCancelled(clear)
    -- A player's skip releases only their own camera and never skips shared timing: unskippable in a network
    -- game (cutscenes are shared), skippable offline.
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

-- A one-shot CameraObject (the DLL calls it once and the engine does not hold it) is re-issued every frame
-- while config.holdCamera is on, so every peer sees the same held shot until the result/CameraFinish.
local function HoldCamera()
    if not config.holdCamera or cameraSkipped or not localCameraActive then return end
    local frame = cameraFrame
    if not frame or frame[1] ~= "O" then return end
    if not (IsValid(frame[2]) and IsValid(frame[6])) then return end
    if not CRCoop.IsNetworkGame() and native.CameraCancelled() then
        cameraSkipped = true
        localCameraActive = false
        native.CameraFinish()
        return
    end
    native.CameraObject(frame[2], frame[3], frame[4], frame[5], frame[6])
end

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
    if M.coopUnresolved == nil then M.coopUnresolved = 0 end
    if not CRCoop.IsAuthority() then
        UpdateRemoteCamera()
        return
    end
    local now, allDelivered = GetTime(), true
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

local function KnownOp(op)
    return native[op] ~= nil or op == "Label" or WEATHER_OPS[op] or EXTRA_OPS[op] ~= nil
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
    if seq == receivedEvent + 1 and KnownOp(op) then
        local args = { select(4, ...) }
        local count = select("#", ...) - 3
        local apply, unresolved = true, false
        if HANDLE_OPS[op] then
            local sent, described = args[1], args[1]
            if sent == GONE then
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

-- ---------------------------------------------------------------- audio
local lastAudio
local function AudioMessage(file)
    file = AUDIO_SUBSTITUTE[file] or file
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

-- ---------------------------------------------------------------- humans as one trigger
local R = {}
local function State()
    M = getState()
    M.crcca = M.crcca or { arrivals = {}, serial = 0, live = {} }
    return M.crcca
end
local function Valid(h) return h ~= nil and h ~= 0 and IsValid(h) end
local function Ticket(h)
    if type(h) ~= "number" or h >= 0 then return nil end
    return State().arrivals[-h]
end
-- Tickets are negative request ids that reserve a concealed spawn. They never reach a native handle API or
-- the network; the mission wrapper shadows the natives so the faithful body can hold and test them.
function R.IsAlive(h)
    if Ticket(h) then return true end
    return Valid(h) and IsAlive(h)
end
function R.IsValid(h)
    if Ticket(h) then return true end
    return IsValid(h)
end
function R.GetDistance(a, b)
    if Ticket(a) or Ticket(b) then return math.huge end
    return GetDistance(a, b)
end
function R.GetNearestEnemy(h)
    if Ticket(h) then return nil end
    return GetNearestEnemy(h)
end

local function ConfigureAlliances()
    local hostile = config.hostileTeams or { ENEMY_TEAM }
    for a = 1, 4 do
        for b = 1, 4 do if a ~= b then Ally(a, b) end end
        Ally(a, SUPPORT_TEAM); Ally(SUPPORT_TEAM, a)
        for _, enemy in ipairs(hostile) do UnAlly(a, enemy); UnAlly(enemy, a) end
    end
end
local function HumanCount()
    local count = 0
    CRCoop.ForEachHumanTeam(function() count = count + 1 end)
    return math.max(1, math.min(4, count))
end
R.HumanCount = HumanCount

-- Nearest human for approach triggers (AnyPlayerSatisfies), farthest for reach gates (AllPlayersNear). A human
-- with no live ship counts as far; no live human at all is infinitely far.
local function HumanSpread(to, farthest)
    local best
    CRCoop.ForEachPlayerHandle(function(h)
        local d = GetDistance(h, to)
        if best == nil or (farthest and d > best) or (not farthest and d < best) then best = d end
    end)
    if best == nil then return math.huge end
    if farthest and CRCoop.IsNetworkGame() and not CRCoop.HasAllPlayerHandles() then return math.huge end
    return best
end
local function IsFarthestTarget(to)
    for _, entry in ipairs(config.farthestTargets or {}) do
        if to == entry or (type(entry) == "string" and M[entry] ~= nil and to == M[entry]) then return true end
    end
    return false
end
function R.WrapDistance(original)
    return function(from, to)
        if from ~= PLAYERS then return original(from, to) end
        if to == nil or to == 0 then return math.huge end
        if type(to) ~= "string" and not Valid(to) then return math.huge end
        return HumanSpread(to, IsFarthestTarget(to))
    end
end
function R.GetPlayerHandle() return PLAYERS end
R.PLAYERS = PLAYERS

-- ---------------------------------------------------------------- concealed arrivals
-- Entry is the authored spawn when no human is within SAFE_RADIUS; otherwise another authored approach;
-- otherwise the request waits. A spawn at an existing object (a factory) is production, not pop-in, and is
-- always allowed. Requests are saved in M.crcca, so a load neither loses nor duplicates them.
local function Safe(where)
    if type(where) ~= "string" and not Valid(where) then return false end
    local safe = true
    CRCoop.ForEachPlayerHandle(function(h)
        if Valid(h) and GetDistance(h, where) < SAFE_RADIUS then safe = false end
    end)
    return safe
end
local function Entry(request)
    if type(request.where) ~= "string" then
        if Valid(request.where) then return request.where end
        return nil, true -- the object is gone: drop the request
    end
    if Safe(request.where) then return request.where end
    for _, path in ipairs(FALLBACK_ENTRIES) do
        if Safe(path) then return path end
    end
end
local function ReplaceTickets(t, old, new)
    for k, v in pairs(t) do
        if v == old then t[k] = new
        elseif type(v) == "table" and k ~= "arrivals" and k ~= "crcca" then ReplaceTickets(v, old, new) end
    end
end
local ORDER_TARGET_OPS = { Attack = true, Defend2 = true, Follow = true }
local function Issue(op, h, a, b)
    if not Valid(h) then return end
    if ORDER_TARGET_OPS[op] and not Valid(a) then return end
    if op == "Goto" and type(a) ~= "string" and not Valid(a) then return end
    if b == nil then return _G[op](h, a) end
    return _G[op](h, a, b)
end
function R.Order(op, h, a, b)
    local request = Ticket(h)
    if request then
        request.orders[#request.orders + 1] = { op, a, b }
        for _, id in ipairs(request.extras or {}) do
            local extra = State().arrivals[id]
            if extra then extra.orders[#extra.orders + 1] = { op, a, b } end
        end
        return
    end
    return Issue(op, h, a, b)
end
for _, op in ipairs(config.orders or { "Goto", "Follow", "Attack", "Defend", "Defend2", "SetIndependence", "Retreat" }) do
    R[op] = function(h, a, b) return R.Order(op, h, a, b) end
end

local function Ended()
    for _, flag in ipairs(config.endedFlags or {}) do
        if M[flag] then return true end
    end
    return M.coopResult or M.coopFailed or M.coopPendingResult
end
-- A scripted spawn event opens with BeginEvent; the first scaled unit the body then builds is mirrored by
-- min(floor(humans/2), maxExtrasPerEvent) extras of the same kind, orders and entry. Extras queue behind it
-- and are the only requests dropped by the live cap. The event closes at the end of the frame.
function R.BeginEvent()
    local s = State()
    s.event = { extras = math.min(math.floor(HumanCount() / 2), MAX_EXTRAS), made = false }
end
local function ChooseOdf(odf)
    if type(hooks.chooseOdf) == "function" then
        local ok, chosen = pcall(hooks.chooseOdf, odf, M)
        if ok and type(chosen) == "string" then return chosen end
    end
    return odf
end
function R.PathExists(name)
    if type(GetPathPointCount) ~= "function" or type(name) ~= "string" then return false end
    local ok, count = pcall(GetPathPointCount, name)
    return ok and type(count) == "number" and count > 0
end
-- lift is an optional drop height (a paratrooper wave): the unit is built that far above a scatter round the
-- path's first point, on whichever entry the arrival uses.
local function Aloft(where, lift)
    if not lift or type(where) ~= "string" then return where end
    local p = GetPosition(where)
    local a, r = math.random() * 2 * math.pi, 10 + math.random() * 40
    return SetVector(p.x + r * math.cos(a), p.y + lift, p.z + r * math.sin(a))
end
-- Offline Hard/Very Hard: each scaled unit brings (enemy multiplier - 1) extras on average (Hard 0.5, Very
-- Hard 1). Easier settings never remove units, since the body tracks their handles; they scale scrap instead.
local function DifficultyExtras()
    if not DiffUtils or CRCoop.IsNetworkGame() then return 0 end
    local surplus = DiffUtils.Get().enemy - 1
    if surplus <= 0 then return 0 end
    local n = math.floor(surplus)
    if math.random() < surplus - n then n = n + 1 end
    return n
end
function R.Spawn(odf, team, where, lift)
    local s = State()
    if not CRCoop.IsAuthority() then return nil end
    if team == MAP_ENEMY_TEAM then team = ENEMY_TEAM end
    if not SCALED[odf] then return BuildObject(odf, team, Aloft(where, lift)) end
    if Ended() then return nil end
    s.serial = s.serial + 1
    local id = s.serial
    s.arrivals[id] = { odf = ChooseOdf(odf), team = team, where = where, lift = lift, orders = {} }
    local extras = team == ENEMY_TEAM and DifficultyExtras() or 0
    local event = s.event
    if event and not event.made then
        event.made = true
        extras = extras + event.extras
    end
    if extras > 0 then
        local primary = s.arrivals[id]
        primary.extras = {}
        for _ = 1, extras do
            s.serial = s.serial + 1
            s.arrivals[s.serial] = { odf = ChooseOdf(odf), team = team, where = where, lift = lift, orders = {}, extra = true,
                primary = id }
            primary.extras[#primary.extras + 1] = s.serial
        end
    end
    return -id
end
local function LiveCount(s)
    local alive = {}
    for _, h in ipairs(s.live) do
        if Valid(h) and IsAlive(h) then alive[#alive + 1] = h end
    end
    s.live = alive
    return #alive
end
local function Arrivals()
    local s = State()
    if Ended() then s.arrivals = {}; return end
    if type(hooks.heldArrivals) == "function" then
        local ok, held = pcall(hooks.heldArrivals, M)
        if ok and held then return end
    end
    local live, built = LiveCount(s), 0
    -- Saved request sequence, never pairs order, defines deterministic entry.
    for id = 1, s.serial do
        local r = s.arrivals[id]
        if r and built < BUILDS_PER_FRAME then
            if r.extra and live >= LIVE_CAP then
                s.arrivals[id] = nil
            else
                local where, drop = Entry(r)
                if drop then
                    s.arrivals[id] = nil
                elseif where then
                    local h = BuildObject(r.odf, r.team, Aloft(where, r.lift))
                    if Valid(h) then
                        ReplaceTickets(M, -id, h)
                        -- Queued orders of later arrivals may target this ticket.
                        for _, other in pairs(s.arrivals) do ReplaceTickets(other.orders, -id, h) end
                        for _, order in ipairs(r.orders) do Issue(order[1], h, order[2], order[3]) end
                        s.live[#s.live + 1] = h
                        live = live + 1
                        s.arrivals[id] = nil; built = built + 1
                        if type(hooks.built) == "function" then
                            local ok, err = pcall(hooks.built, R, h, r, id)
                            if not ok then Log(ID, "built hook failed: " .. tostring(err)) end
                        end
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------- results and scaling
local function RunBeats()
    if not (Weather and weatherStarted) or type(Weather.config.beats) ~= "function" then return end
    -- A runtime defeat (out of lives) skips the body's own FailMission, so its lost flag stays false:
    -- the beats see it as lost, so the defeat beat and the closing calm still fire.
    local state = M
    if M.coopFailed and not M.lost then state = setmetatable({ lost = true }, { __index = M }) end
    local ok, err = pcall(Weather.config.beats, Weather.module, state, State())
    if not ok and not weatherFailed.beats then
        weatherFailed.beats = true
        Log(ID, "weather beats failed: " .. tostring(err))
    end
end
local function Failure()
    if not CRCoop.IsAuthority() or WonLatched() or Ended() then return end
    M.coopFailed = true
    RunBeats() -- the last beats before the result stops the weather updates
    FailMission(GetTime() + 7, FAIL_DES)
end
function R.SetScrap(team, amount)
    if DiffUtils and not CRCoop.IsNetworkGame() then
        -- Offline difficulty: player scrap scales with the setting, but a fill to capacity stays a fill and never
        -- overflows it. Enemy scrap only grows (harder settings), so a body's "at least N" top-up still holds.
        if team == LEADER_TEAM then
            local max = type(GetMaxScrap) == "function" and GetMaxScrap(LEADER_TEAM) or nil
            if max and amount >= max then return SetScrap(LEADER_TEAM, amount) end
            local scaled = DiffUtils.ScaleRes(amount)
            if max then scaled = math.min(scaled, max) end
            return SetScrap(LEADER_TEAM, scaled)
        end
        if team == MAP_ENEMY_TEAM or team == ENEMY_TEAM then
            return SetScrap(ENEMY_TEAM, math.max(amount, DiffUtils.ScaleEnemy(amount)))
        end
    end
    if team == LEADER_TEAM then
        -- One shared production base, with a bounded bonus starting scrap per guest.
        return SetScrap(LEADER_TEAM, amount + SCRAP_PER_GUEST * (HumanCount() - 1))
    end
    if team == MAP_ENEMY_TEAM then team = ENEMY_TEAM end
    return SetScrap(team, amount)
end
-- The DLL's AIP calls name the enemy implicitly (default team 2): always the co-op enemy team.
function R.SetAIP(name, team)
    if team == nil or team == MAP_ENEMY_TEAM then team = ENEMY_TEAM end
    return SetAIP(name, team)
end

-- ---------------------------------------------------------------- weather lifecycle
local function InitWeather()
    weatherStarted = true
    local w = Weather.config
    local net = CRCoop.IsNetworkGame()
    local authority = (not net) or CRCoop.IsAuthority()
    local s = State()
    if w.environment ~= false then
        envStarted = pcall(Environment.Init, w.environment or { lightingMode = "subtle", nativeBaseline = true,
            subtlePeriod = 3600, subtleDimming = 0.04, subtleSunAngle = 2 })
    end
    WeatherCall("Init", {
        authority = authority,
        seed = s.weatherSeed, -- nil: the leader/offline picks one, guests wait for the host's state
        sites = Weather.sites,
        startLevel = w.startLevel or 1,
        targetLevel = w.targetLevel or 2,
        send = net and function(op, ...)
            events[#events + 1] = { op = op, args = { ... }, n = select("#", ...), ttl = RESOLVE_TIMEOUT }
        end or nil,
        players = net and function()
            local list = {}
            CRCoop.ForEachPlayerHandle(function(h) list[#list + 1] = h end)
            return list
        end or nil,
    })
    if s.weatherState ~= nil and authority then
        WeatherCall("Load", s.weatherState)
        s.weatherState = nil
    end
    if authority then s.weatherSeed = Weather.module.Seed end -- survives a save
end
local function UpdateWeather(dt)
    if not Weather then
        if envStarted then pcall(Environment.Update, dt) end
        return
    end
    if not weatherStarted then InitWeather() end
    if CRCoop.IsNetworkGame() and CRCoop.IsAuthority() and not weatherAnnounced and CRCoop.IsSessionReady() then
        weatherAnnounced = true
        WeatherCall("AnnounceState")
    end
    WeatherCall("Update", dt)
    if envStarted then pcall(Environment.Update, dt) end
    local authority = (not CRCoop.IsNetworkGame()) or CRCoop.IsAuthority()
    if authority then RunBeats() end
end
local function ShutdownWeather()
    if weatherStarted then WeatherCall("Shutdown") end
    weatherStarted, weatherAnnounced, envStarted = false, false, false
end

local function Hook(name, ...)
    if type(hooks[name]) ~= "function" then return nil end
    local ok, result = pcall(hooks[name], R, ...)
    if not ok then
        if not weatherFailed["hook:" .. name] then
            weatherFailed["hook:" .. name] = true
            Log(ID, "hook " .. name .. " failed: " .. tostring(result))
        end
        return nil
    end
    return result
end

-- ---------------------------------------------------------------- engine callbacks
function R.Start()
    State().started = nil
    CRCoop.Initialize({ getLocalPlayerId = function() return exu.GetMyNetID and exu.GetMyNetID() end,
        leaderTeam = LEADER_TEAM, humanTeamMin = 1, humanTeamMax = 4,
        rallyPoints = config.rallyPoints,
        -- A mission whose own ending is not a plain FailMission (evolve always SucceedMission-s with a
        -- score-chosen debrief) overrides this; Failure() is the default for every other CCA mission.
        onOutOfLives = type(hooks.outOfLives) == "function" and function()
            local ok, err = pcall(hooks.outOfLives)
            if not ok then Log(ID, "hook outOfLives failed: " .. tostring(err)); Failure() end
        end or Failure })
    if localCameraActive then native.CameraFinish() end
    ConfigureAlliances(); ResetPresentation(); lastAudio = nil
    pda.Initialize(); subtit.Initialize()
    ShutdownWeather()
    if not Weather and type(config.environment) == "table" then
        envStarted = pcall(Environment.Init, config.environment)
    end
    Hook("start")
end
function R.AddObject(h)
    if Valid(h) then
        pcall(Environment.OnObjectCreated, h)
        if Weather then WeatherCall("OnObjectCreated", h) end
    end
    Hook("addObject", h)
end
function R.CreatePlayer(id, name, team) CRCoop.CreatePlayer(id, name, team); ConfigureAlliances() end
function R.AddPlayer(id, name, team) CRCoop.AddPlayer(id, name, team); ConfigureAlliances() end
function R.DeletePlayer(id) CRCoop.DeletePlayer(id) end
function R.Receive(from, kind, ...)
    State()
    -- Only this runtime's channels are wire-encoded; CRCoop's own packets pass through untouched.
    if OWN_CHANNELS[kind] and ReceivePresentation(from, kind, CRWire.Unpack(...)) then return true end
    return CRCoop.Receive(from, kind, ...)
end
-- Returns true when the faithful body should run this frame (authority only).
function R.Update(dt)
    local s = State()
    subtit.Update(); CRCoop.Update(); UpdatePresentationTransport()
    pda.UpdateInputs(localCameraActive); pda.UpdateHeadlights()
    if CRCoop.IsNetworkGame() then
        if CRCoop.HasLeaderDeparted() then
            if not M.coopResult then
                M.coopResult = true
                if localCameraActive then native.CameraFinish(); localCameraActive = false end
                native.FailMission(GetTime() + 1)
            end
            return false
        end
        if CRCoop.HasUnsupportedPlayerTeam() or CRCoop.HasLateJoiners() or not CRCoop.IsSessionReady() then return false end
    end
    if not s.started then CRCoop.MarkMissionStarted(); s.started = true end
    M.coopMissionStarted = true
    if not M.coopResult then UpdateWeather(dt) end
    Hook("update", dt, CRCoop.IsAuthority())
    if not CRCoop.IsAuthority() or M.coopResult then return false end
    HoldCamera()
    Arrivals()
    return true
end
function R.AfterUpdate()
    FlushObjectives()
    State().event = nil
    Hook("afterUpdate")
end
function R.Save()
    local s = State()
    if weatherStarted and ((not CRCoop.IsNetworkGame()) or CRCoop.IsAuthority()) then
        s.weatherState = WeatherCall("Save")
    end
    Hook("save", s)
end
function R.Load()
    M = getState()
    ShutdownWeather()
    if Weather and Environment.InvalidateRenderer then pcall(Environment.InvalidateRenderer) end
    R.Start()
    Hook("load")
end

R.Coop, R.Exu, R.Native, R.Weather = CRCoop, exu, native, Weather
R.State = State
R.Present = Present
R.AudioMessage, R.StopAudioMessage = AudioMessage, StopAudioMessage
R.CameraReady, R.CameraPath, R.CameraObject = CameraReady, CameraPath, CameraObject
R.CameraFinish, R.CameraCancelled = CameraFinish, CameraCancelled
R.SetObjectiveName, R.SetObjectiveOn, R.SetObjectiveOff = SetObjectiveName, SetObjectiveOn, SetObjectiveOff
R.ClearObjectives, R.AddObjective, R.UpdateObjective, R.RemoveObject = ClearObjectives, AddObjective, UpdateObjective, RemoveObject
R.SucceedMission, R.FailMission = SucceedMission, FailMission
R.SAFE_RADIUS, R.LIVE_CAP = SAFE_RADIUS, LIVE_CAP
return R
end

return Runtime
