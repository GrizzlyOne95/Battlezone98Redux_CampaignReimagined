-- misn08: faithful BZ1 DLL mission port for stock Battlezone 98 Redux / Lua 5.1,
-- with the shared offline + 2-4 player co-op layer of the misn06/07 ports
-- (Docs/MISN08_COOP.md).
-- Authority: Battlezone_Source/BZ1/from_bz2_dll_src/Misn08Mission.cpp
-- Source blob: d1581e4d62251a9a452e26c30fee162a90cf9571
-- Full source, including native serialization, is in References/Misn08Source/.
-- No community/Lua mission used as behavioral evidence.
-- Disabled code is translated in place. Intentional source quirks (timers,
-- duplicate spawn assignment, outcome ordering) remain unchanged; two AddObject
-- copy/paste typos are explicitly repaired. Everything the campaign adds lives
-- between "-- CR ... >>" / "-- CR ... <<" marker lines (Tools/Test-Misn08SourceParity.py).
-- Offline play reproduces the DLL; only the leader runs the mission body.
-- Requires stock misn08 map labels, paths, AIPs, OTF/audio/debrief assets.
local M = {}

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})
local exu = require("exu")
-- Native MultST Init precedes Start; retain the authored Utah (avrecycle) only.
if type(IsNetGame) == "function" and IsNetGame() then
    assert(exu.DisableStartingRecycler and exu.GetMyNetID,
        "misn08 co-op requires the bundled EXU multiplayer hooks")
    exu.DisableStartingRecycler()
end
local subtit = require("ScriptSubtitles")
local CRCoop = require("CRCoop")
local LEADER_TEAM, ENEMY_TEAM, SUPPORT_TEAM = 1, 5, 7
-- CR Venus weather >>
local CRVenusWeather = require("CRVenusWeather")
local VenusSites = require("CRVenusSites08")
local Environment = require("Environment")
local VENUS_OPS = { VenusState = true, VenusStrike = true, VenusErupt = true }
-- CR Venus weather <<
-- CR Colorado massacre >>
-- The Colorado (map label "colorado", team 7 perceived NSDF) is destroyed on screen:
-- walker 3 (spawned beside it) and the CCA strike units attack it once the DLL's
-- scripted heal stops. The DLL's Damage(colorado, 20000) survives only as a fallback
-- if it is still alive COLORADO_FALLBACK_S after the heal stopped.
local COLORADO_FALLBACK_S = 120.0
local COLORADO_ORDER_S = 10.0
local COLORADO_WARN_M = 400.0
-- CR Colorado massacre <<
-- CR restored walker content >>
-- If walker 3 never passes within 30 m of stop_geyser2, the restored base advance
-- (disabled in the DLL) starts anyway this long after the Colorado fell.
local GECH3_FALLBACK_S = 150.0
-- CR restored walker content <<
-- CR Colorado base >>
-- The Colorado starts allied (team 7) with a small escort and a modest base that the leader
-- builds in Lua (see the helper block): recycler-style scavenger, a factory, two turrets (hilly ground)
-- and a capped stream of APCs, charged against team-7 scrap. Costs are the ODFs' scrapCost.
local COLORADO_SCRAP = 60
local COLORADO_ESCORT = { { "avtank", -45.0, 35.0 }, { "avtank", 45.0, 40.0 }, { "avfigh", 0.0, -50.0 } }
local COLORADO_BUILDS = {
    { at = 15.0, odf = "avscav", dx = -30.0, dz = 40.0 },
    { at = 40.0, odf = "avmuf", dx = 50.0, dz = -40.0 },
    { at = 70.0, odf = "avturr", dx = 70.0, dz = 30.0 },
    { at = 100.0, odf = "avturr", dx = -60.0, dz = -20.0 },
}
local COLORADO_COST = { avscav = 4, avmuf = 10, avturr = 6, avapc = 5 }
local COLORADO_APC_CAP, COLORADO_APC_FIRST_S, COLORADO_APC_INTERVAL_S = 3, 90.0, 40.0
-- CR Colorado base <<
-- CR CCA walkers >>
-- After the scripted walker story the CCA fields ordinary svwalk (two gblast cannons and a
-- popgun): one per 150 s, 1 solo +1 per extra human team (max 3), charged to team-5 scrap
-- (svwalk.odf scrapCost 12), until the CCA factory or base falls.
local WALKER_CAP_BASE, WALKER_CAP_PER_PLAYER, WALKER_CAP_MAX = 1, 1, 3
local WALKER_INTERVAL_S, WALKER_FIRST_DELAY_S, WALKER_RETRY_S, WALKER_ORDER_S = 150.0, 60.0, 15.0, 30.0
local WALKER_SCRAP_COST = 12
-- CR CCA walkers <<

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
-- the two prefixes this mission reads; the leader honours a report for 1 s.
local INFO_PREFIXES = { "hbblde", "hbbldf" }
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
-- CR failure VO >>
-- The DLL plays misn0421 ("We've lost the Recycler!") when the Utah is lost; the
-- campaign has the dedicated abort line misn0823 for that moment. The mission body
-- still plays the DLL's file; this adapter substitutes it for every peer.
local VO_SUBSTITUTE = { ["misn0421.wav"] = "misn0823.wav" }
local presentPlay = subtit.Play
subtit.Play = function(wav, ...) return presentPlay(VO_SUBSTITUTE[wav] or wav, ...) end
-- CR failure VO <<

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

-- Lexical SetScrap: the DLL's SetScrap(1, 30) means every human's starting scrap
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

-- Missing native handles returned an effectively infinite distance. Preserve
-- that behavior rather than interpreting nil as a path/position overload.
local function Distance(from, to)
    if from == nil or from == 0 or not IsValid(from) then return math.huge end
    if to == nil or to == 0 then return math.huge end
    if type(to) ~= "string" and not IsValid(to) then return math.huge end
    return GetDistance(from, to)
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

-- The human craft nearest `from`; the leader's own craft when none is present.
local function NearestPlayer(from)
    local best, bestDistance = nil, math.huge
    CRCoop.ForEachPlayerHandle(function(h)
        local distance = Distance(from, h)
        if best == nil or distance < bestDistance then best, bestDistance = h, distance end
    end)
    return best or M.user
end

-- The DLL counted team-1 units only; in co-op every human team's units count.
local function CountHumanUnits(target, range, odf)
    local total = 0
    CRCoop.ForEachHumanTeam(function(team)
        total = total + CountUnitsNearObject(target, range, team, odf)
    end)
    return total
end

-- CR team filter >>
-- The DLL's AddObject had no team filter. It tracks the player's factory and gun
-- towers (any human team) and the CCA APC (team 5) only.
local function AddObjectTeamAllowed(h)
    local team = GetTeamNum(h)
    if IsOdf(h, "svapc") then return team == ENEMY_TEAM end
    if IsOdf(h, "avmu8") or IsOdf(h, "abtowe") then return CRCoop.IsHumanTeam(team) end
    return true
end
-- CR team filter <<

-- CR Colorado base >>
local function AtGround(x, z)
    return SetVector(x, (GetTerrainHeightAndNormal(SetVector(x, 0, z))), z)
end

-- Colorado-team objects the script built (escort, scavenger, factory, turrets, APCs).
local function ColoradoForce()
    local live = {}
    if M.cbase then
        for _, h in ipairs(M.cbase.force) do
            if IsAlive(h) then live[#live + 1] = h end
        end
    end
    return live
end

local function ColoradoSpawn(odf, where)
    local h = BuildObject(odf, SUPPORT_TEAM, where)
    SetPerceivedTeam(h, LEADER_TEAM)
    M.cbase.force[#M.cbase.force + 1] = h
    return h
end

local function ColoradoCharge(odf)
    local cost = COLORADO_COST[odf] or 0
    if GetScrap(SUPPORT_TEAM) < cost then return false end
    AddScrap(SUPPORT_TEAM, -cost)
    return true
end

-- Chosen route: Lua on the leader, not an AIP. A non-slot team's strategic AI is unproven in
-- MultSTMission, CR ships no AIP of its own (all come from bzone.zfs) and SetAIControl is
-- startup-only, so the Colorado's base is a timed build list that mirrors misn07's svtnk7
-- production: units appear at the Colorado, are charged team-7 scrap, and are capped.
-- Runs until the CCA attack begins; the Colorado is the DLL's own map object.
local function UpdateColoradoBase()
    if M.colorado_under_attack or not IsAlive(M.colorado) then return end
    local now = GetTime()
    local base = M.cbase
    if base == nil then
        M.cbase = { t0 = now, step = 1, apc_next = now + COLORADO_APC_FIRST_S, force = {}, apcs = {} }
        base = M.cbase
        SetScrap(SUPPORT_TEAM, COLORADO_SCRAP)
        local pos = GetPosition(M.colorado)
        for _, escort in ipairs(COLORADO_ESCORT) do
            ColoradoSpawn(escort[1], AtGround(pos.x + escort[2], pos.z + escort[3]))
        end
        return
    end
    local build = COLORADO_BUILDS[base.step]
    if build and now - base.t0 >= build.at and ColoradoCharge(build.odf) then
        local pos = GetPosition(M.colorado)
        local h = ColoradoSpawn(build.odf, AtGround(pos.x + build.dx, pos.z + build.dz))
        if build.odf == "avmuf" then base.factory, base.deploy_at = h, now + 1.0 end
        base.step = base.step + 1
    end
    if base.factory and base.deploy_at and now >= base.deploy_at and IsAlive(base.factory) then
        base.deploy_at = nil
        Deploy(base.factory)
    end
    if IsAlive(base.factory) and now >= base.apc_next then
        local live = {}
        for _, apc in ipairs(base.apcs) do
            if IsAlive(apc) then live[#live + 1] = apc end
        end
        base.apcs = live
        base.apc_next = now + COLORADO_APC_INTERVAL_S
        if #live < COLORADO_APC_CAP and ColoradoCharge("avapc") then
            base.apcs[#base.apcs + 1] = ColoradoSpawn("avapc", base.factory)
        end
    end
end
-- CR Colorado base <<

-- CR Colorado massacre >>
local function ColoradoStrikeUnits()
    local strike = M.strike or {}
    local units = { M.ccagech3, strike.figh, strike.ltnk }
    for _, extra in ipairs(strike.extra or {}) do units[#units + 1] = extra end
    return units
end

-- The Colorado first, then the nearest surviving piece of its base.
local function ColoradoTarget(from)
    if IsAlive(M.colorado) then return M.colorado end
    local best, bestDistance = nil, math.huge
    for _, h in ipairs(ColoradoForce()) do
        local distance = Distance(from, h)
        if best == nil or distance < bestDistance then best, bestDistance = h, distance end
    end
    return best
end

-- Called once when the heal stops: a bigger base gets extra CCA strike units, spawned on
-- the walker's approach path so they arrive within seconds (team 5, ordered like the rest).
local COLORADO_EXTRA_MAX = 4
local function ColoradoExtraStrike()
    local strike = M.strike
    if strike == nil or strike.extra ~= nil then return end
    strike.extra = {}
    local wanted = math.min(COLORADO_EXTRA_MAX, #ColoradoForce())
    for index = 1, wanted do
        strike.extra[index] = BuildObject(index % 2 == 1 and "svtank" or "svfigh", ENEMY_TEAM, "gech_spawn")
    end
end

-- Runs every frame after the Colorado radio timeline: keeps the walker and the CCA strike
-- units on the Colorado and then its base, warns players who walk into it (0824, once),
-- sweeps whatever survives a generous timeout, and sends the strike units on to the Drop
-- Zone (the DLL's own order) once the whole force fell.
local COLORADO_CLEANUP_S = 150.0
local function UpdateColoradoMassacre()
    local strike = M.strike
    if strike == nil or M.colorado_cleaned then return end
    local now = GetTime()
    local force = ColoradoForce()
    if IsAlive(M.colorado) or #force > 0 then
        if IsAlive(M.colorado) and not M.colorado_warned and AnyPlayerWithin(M.colorado, COLORADO_WARN_M) then
            M.colorado_warned = true
            subtit.Play("misn0824.wav")
        end
        if M.colorado_cleanup ~= nil and now >= M.colorado_cleanup then
            -- Fallback: the story beat must hold even if the attackers stall.
            for _, h in ipairs(force) do Damage(h, 20000) end
            M.colorado_cleaned = true
            return
        end
        if now >= strike.next_order then
            strike.next_order = now + COLORADO_ORDER_S
            for _, unit in ipairs(ColoradoStrikeUnits()) do
                if IsAlive(unit) then
                    local target = ColoradoTarget(unit)
                    if target ~= nil then Attack(unit, target, 1) end
                end
            end
        end
    elseif not strike.released then
        strike.released = true
        M.colorado_cleaned = true
        local resume = { strike.figh, strike.ltnk }
        for _, extra in ipairs(strike.extra or {}) do resume[#resume + 1] = extra end
        for _, unit in ipairs(resume) do
            if IsAlive(unit) then Goto(unit, M.nav1) end
        end
    end
end

-- The DLL's Damage(colorado, 20000) block runs once the Colorado is gone or the
-- fallback deadline passed (then it still destroys it).
local function ColoradoMassacreDone()
    if not IsAlive(M.colorado) then return true end
    return M.colorado_deadline ~= nil and GetTime() >= M.colorado_deadline
end
-- CR Colorado massacre <<

-- CR CCA walkers >>
local function WalkerCap()
    local humans = CRCoop.ForEachHumanTeam(function() end)
    return math.min(WALKER_CAP_MAX, WALKER_CAP_BASE + WALKER_CAP_PER_PLAYER * math.max(0, humans - 1))
end

local function WalkerTarget(from)
    if IsAlive(M.nsdfrecycle) then return M.nsdfrecycle end
    return NearestPlayer(from)
end

-- Once the scripted walker story has played out (the CCA recycler spawn marks Walker 3
-- heading for the base), build ordinary walkers at the CCA factory (svmuf lists svwalk) on
-- a timer until that factory or the CCA base is destroyed. Leader-only.
local function UpdateCcaWalkers()
    if not M.ccarecycle_spawned or M.game_over then return end
    local now = GetTime()
    if M.cw == nil then M.cw = { list = {}, next = now + WALKER_FIRST_DELAY_S, order = now + WALKER_FIRST_DELAY_S } end
    local live = {}
    for _, walker in ipairs(M.cw.list) do
        if IsAlive(walker) then live[#live + 1] = walker end
    end
    M.cw.list = live
    if not IsAlive(M.ccamuf) or M.base_dead then return end
    if M.cw.order < now then
        M.cw.order = now + WALKER_ORDER_S
        for _, walker in ipairs(live) do Attack(walker, WalkerTarget(walker)) end
    end
    if M.cw.next >= now then return end
    if #live >= WalkerCap() or GetScrap(ENEMY_TEAM) < WALKER_SCRAP_COST then
        M.cw.next = now + WALKER_RETRY_S
        return
    end
    AddScrap(ENEMY_TEAM, -WALKER_SCRAP_COST)
    local walker = BuildObject("svwalk", ENEMY_TEAM, M.ccamuf)
    M.cw.list[#M.cw.list + 1] = walker
    Attack(walker, WalkerTarget(walker))
    M.cw.next = now + WALKER_INTERVAL_S
end
-- CR CCA walkers <<

-- CR restored walker content >>
-- The DLL's disabled third-walker block (translated in place in Update): after the
-- Colorado, walker 3 follows gech_path2 on to the player base and then attacks it
-- like walkers 1 and 2 (the base-arrival block reads gech3_there_time).
local function RestoredWalkerAdvance()
    if not M.ccarecycle_spawned or M.gech3_move or not (M.gech_check_time < GetTime()) then return end
    if M.gech3_fallback == nil then M.gech3_fallback = GetTime() + GECH3_FALLBACK_S end
    if IsAlive(M.ccagech3) and (Distance(M.ccagech3, M.stop_geyser2) < 30.0 or GetTime() >= M.gech3_fallback) then
        Goto(M.ccagech3, "gech_path2")
        M.gech3_there_time = GetTime() + 97.0
        M.gech3_move = true
    end
end

-- The DLL's disabled close-range block: any player within 75 m of a walker.
local function RestoredCloseWarning()
    if not (M.gech_found or M.gech_at_nav) or M.too_close_message then return end
    for _, walker in ipairs({ M.ccagech1, M.ccagech2, M.ccagech3 }) do
        if IsAlive(walker) and AnyPlayerWithin(walker, 75.0) then
            subtit.Play("misn0816.wav") -- pull out!! what the hell is that!
            M.too_close_message = true
            return
        end
    end
end
-- CR restored walker content <<

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
--   2 calm while the Colorado is still talking -> 3 when the scripted walkers begin their
--   attacks (walker 3 hits the Colorado, or the base walkers set off) -> a 60 s level-5
--   spike when the Colorado's heal stops and the massacre begins -> a steady 3 once the
--   CCA has its recycler and svwalk production runs.
local function UpdateVenusBeats()
    local beats = M.venusBeats
    if beats == nil then beats = {}; M.venusBeats = beats end
    if (not beats.rising) and (M.colorado_under_attack or M.gech_started) then
        beats.rising = true
        CRVenusWeather.SetTargetLevel(3)
    end
    if (not beats.massacre) and M.kill_colorado then
        beats.massacre = true
        CRVenusWeather.ForceLevel(5, 60.0, 10.0)
    end
    if (not beats.production) and M.ccarecycle_spawned then
        beats.production = true
        CRVenusWeather.SetTargetLevel(3)
    end
end
-- CR Venus weather <<

local function ResetState()
    M = {
        -- Original bool save fields, including dormant cut-content state.
        start_done = false,
        gech_found = false,
        gech_found1 = false,
        gech_found2 = false,
        base_dead = false,
        player_dead = false,
        unit_spawn = false,
        gech_at_nav = false,
        gech_at_nav2 = false,
        gech_at_nav3 = false,
        player_warned_ofgech = false,
        colorado_under_attack = false,
        colorado_destroyed = false,
        followup_message = false,
        colorado_message2 = false,
        colorado_message3 = false,
        colorado_message4 = false,
        second_gech_warning = false,
        run_into_other_gech = false,
        too_close_message = false,
        bad_news = false,
        base_exposed = false,
        bump_into_gech = false,
        ccarecycle_spawned = false,
        gech_started = false,
        gech3_move = false,
        first_wave = false,
        second_wave = false,
        next_wave = false,
        gech1_at_base = false,
        gech2_at_base = false,
        gech3_at_base = false,
        gech1_blossom = false,
        gech2_blossom = false,
        gech3_blossom = false,
        fresh_meat = false,
        fighter_message = false,
        apc_attack = false,
        base_set = false,
        game_over = false,
        cerb_found = false,
        relic_message = false,
        kill_colorado = false,
        gen_message = false,
        -- Original float save fields, including dormant cut-content state.
        unit_spawn_time = 99999.0,
        followup_message_time = 99999.0,
        colorado_message2_time = 99999.0,
        colorado_message3_time = 99999.0,
        colorado_message4_time = 99999.0,
        bad_news_time = 99999.0,
        gech_warning_message = 99999.0,
        remove_nav5_time = 99999.0,
        gech_spawn_time = 99999.0,
        gech_check = 99999.0,
        gech_check2 = 99999.0,
        stumble1_check = 99999.0,
        stumble2_check = 99999.0,
        trigger_check = 99999.0,
        no_stumble_check = 99999.0,
        time_waist = 99999.0,
        start_gech_time = 99999.0,
        gech_check_time = 99999.0,
        first_wave_time = 99999.0,
        second_wave_time = 99999.0,
        next_wave_time = 99999.0,
        gech1_there_time = 99999.0,
        gech2_there_time = 99999.0,
        gech3_there_time = 99999.0,
        new_aip_time = 99999.0,
        fresh_meat_time = 99999.0,
        fighter_message_time = 99999.0,
        player_nosey_time = 99999.0,
        pull_out_message = 99999.0,
        base_check = 99999.0,
        cerb_check = 99999.0,
        next_second = 99999.0,
        next_second2 = 99999.0,
        -- Original Handle save fields, including dormant cut-content state.
        user = nil,
        death_scrap = nil,
        death_scrap2 = nil,
        death_scrap3 = nil,
        nav1 = nil,
        nav2 = nil,
        nav3 = nil,
        nav4 = nil,
        nav5 = nil,
        ccagech1 = nil,
        ccagech2 = nil,
        ccagech3 = nil,
        colorado = nil,
        drop = nil,
        ccarecycle = nil,
        ccamuf = nil,
        ccaarmor = nil,
        gech_trigger2 = nil,
        gech_trigger3 = nil,
        nsdfrecycle = nil,
        nsdfmuf = nil,
        attack_geys = nil,
        ccarecycle_geyser = nil,
        stop_geyser1 = nil,
        stop_geyser2 = nil,
        stop_geyser3 = nil,
        svpatrol1_1 = nil,
        svpatrol1_2 = nil,
        svpatrol1_3 = nil,
        svpatrol2_1 = nil,
        svpatrol2_2 = nil,
        svpatrol2_3 = nil,
        cannon_fodder1 = nil,
        cannon_fodder2 = nil,
        cannon_fodder3 = nil,
        ccaapc = nil,
        guntower1 = nil,
        guntower2 = nil,
        relic1 = nil,
        relic2 = nil,
        main_relic = nil,
        -- Original int save fields, including dormant cut-content state.
        units1 = 0,
        units2 = 0,
-- CR Colorado massacre >>
        strike = nil,
        colorado_warned = false,
        colorado_deadline = nil,
        colorado_cleanup = nil,
        colorado_cleaned = false,
        cbase = nil,
-- CR Colorado massacre <<
-- CR CCA walkers >>
        cw = nil,
-- CR CCA walkers <<
-- CR restored walker content >>
        gech3_fallback = nil,
-- CR restored walker content <<
    }
end


ResetState()

local function Setup()


    --[=[

Here's where you set the values at the start.  

]=]

    M.units1 = 0.0
    M.units2 = 0.0

    M.start_done = false
    M.gech_found = false
    M.gech_found1 = false
    M.gech_found2 = false
    M.base_dead = false
    M.player_dead = false
    M.unit_spawn = false
    M.gech_at_nav = false
    M.gech_at_nav2 = false
    M.gech_at_nav3 = false
    M.followup_message = false
    M.player_warned_ofgech = false
    M.colorado_under_attack = false
    M.colorado_destroyed = false
    M.colorado_message2 = false
    M.colorado_message3 = false
    M.colorado_message4 = false
    M.second_gech_warning = false
    M.bad_news = false
    M.run_into_other_gech = false
    M.too_close_message =false
    M.base_exposed = false
    M.bump_into_gech = false
    M.ccarecycle_spawned = false
    M.gech_started = false
    M.gech3_move = false
    M.first_wave = false
    M.second_wave = false
    M.next_wave = false
    M.gech1_at_base = false
    M.gech2_at_base = false
    M.gech3_at_base = false
    M.fresh_meat = false
    M.fighter_message = false
    M.gech1_blossom = false
    M.gech2_blossom = false
    M.gech3_blossom = false
    M.apc_attack = false
    M.game_over = false
    M.base_set = false
    M.cerb_found = false
    M.relic_message = false
    M.kill_colorado = false
    M.gen_message = false


    M.followup_message_time = 99999.0
    M.gech_warning_message = 99999.0
    M.colorado_message2_time = 99999.0
    M.colorado_message3_time = 99999.0
    M.colorado_message4_time = 99999.0
    M.bad_news_time = 99999.0
    M.remove_nav5_time = 99999.0
    M.gech_spawn_time = 99999.0
    M.gech_check = 99999.0
    M.gech_check2 = 99999.0
    M.stumble2_check = 99999.0
    M.stumble1_check = 99999.0
    M.trigger_check = 99999.0
    M.no_stumble_check = 99999.0
    M.time_waist = 99999.0
    M.start_gech_time = 99999.0
    M.gech_check_time = 10.0
    M.first_wave_time = 99999.0
    M.second_wave_time = 99999.0
    M.next_wave_time = 99999.0
    M.gech1_there_time = 99999.0
    M.gech2_there_time = 99999.0
    M.gech3_there_time = 99999.0
    M.new_aip_time = 99999.0
    M.fresh_meat_time = 99999.0
    M.fighter_message_time = 200.0
    M.player_nosey_time = 45.0
    M.pull_out_message = 99999.0
    M.base_check = 99999.0
    M.cerb_check = 30.0
    M.next_second = 99999.0
    M.next_second2 = 99999.0

    M.death_scrap = GetHandle("death_scrap")
    M.death_scrap2 = GetHandle("death_scrap2")
    M.death_scrap3 = GetHandle("death_scrap3")
    M.nsdfrecycle = GetHandle("avrecycle")
    M.ccarecycle = GetHandle("svrecycle")
    M.ccamuf = GetHandle("svmuf")
    M.ccagech1 = GetHandle("sovgech1")
    M.ccagech2 = GetHandle("sovgech2")
    M.nav1 = GetHandle("cam1")
    M.nav4 = GetHandle("cam2")
    M.nav5 = GetHandle("cam5")
    M.gech_trigger2 = GetHandle("giez_spawn2")
    M.gech_trigger3 = GetHandle("giez_spawn3")
    M.colorado = GetHandle("colorado")
    -- M.drop = GetHandle("dropoff57_dropoff")
    M.attack_geys = GetHandle("attack_geyser")
    M.ccarecycle_geyser = GetHandle("ccarecycle_geyser")
    M.stop_geyser1 = GetHandle("stop_geyser1")
    M.stop_geyser2 = GetHandle("stop_geyser2")
    M.stop_geyser3 = GetHandle("stop_geyser3")
    M.svpatrol1_1 = GetHandle("svpatrol1_1")
    M.svpatrol1_2 = GetHandle("svpatrol1_2")
    M.svpatrol1_3 = GetHandle("svpatrol1_3")
    M.svpatrol2_1 = GetHandle("svpatrol2_1")
    M.svpatrol2_2 = GetHandle("svpatrol2_2")
    M.svpatrol2_3 = GetHandle("svpatrol2_3")
    M.relic1 = GetHandle("hbblde1_i76building")
    M.relic2 = GetHandle("hbbldf1_i76building")
    M.main_relic = GetHandle("hbcerb1_i76building")
    M.nsdfmuf = nil
    M.ccaapc = nil
    M.guntower1 = nil
    M.guntower2 = nil
    M.ccagech3 = nil
end

function AddObject(h)
-- CR Venus weather >>
    Environment.OnObjectCreated(h)
    CRVenusWeather.OnObjectCreated(h)
-- CR Venus weather <<
-- CR team filter >>
    if not AddObjectTeamAllowed(h) then return end
-- CR team filter <<
    if ((M.nsdfmuf == nil) and (IsOdf(h,"avmu8"))) then
        M.nsdfmuf = h
    else
        if ((M.ccaapc == nil) and (IsOdf(h,"svapc"))) then
            -- Source typo: nsdfmuf = h; the svapc belongs in ccaapc.
            M.ccaapc = h
        else
            if ((M.guntower1 == nil) and (IsOdf(h,"abtowe"))) then
                M.guntower1 = h
            else
                if ((M.guntower2 == nil) and (IsOdf(h,"abtowe"))) then
                    -- Source typo: guntower1 = h; this is the second tower slot.
                    M.guntower2 = h
                end
            end
        end
    end
end

local function InitializeCoop()
    CRCoop.Initialize({
        getLocalPlayerId = function() return exu.GetMyNetID and exu.GetMyNetID() end,
        leaderTeam = LEADER_TEAM, humanTeamMin = 1, humanTeamMax = 4,
        onOutOfLives = function() FailMission(GetTime() + 3.0) end,
        -- MultST consumes its spawn buoys during initialization. Rally at the
        -- persistent Utah (avrecycle) instead of the removed team-start marker.
        rallyPoints = { [0] = "avrecycle" },
    })
    ConfigureAlliances()
    ResetPresentation()
-- CR Venus weather >>
    ShutdownVenusWeather()
-- CR Venus weather <<
end

-- The native AiMission supplies the CCA strategic AI. LuaMission must enable it at chunk load,
-- before the engine runs DR_AI_Init: a later SetAIControl (Start runs after it) leaves the team
-- flagged but without an AI team record, and the first team-5 unit removal in AI_UnitRemove then
-- dereferences null and kills the host (misn08 co-op live run). Same rule as misn10/misn14.
SetAIControl(ENEMY_TEAM, true)

function Start()
    ResetState()
    InitializeCoop()
    Setup()
    -- C++ Setup precedes AiMission::Load and its AddObject notifications.
    -- Redux may create map objects before Start; recover the four tracked slots
    -- after Setup so those earlier notifications cannot be discarded.
    for h in AllObjects() do
        AddObject(h)
    end
-- CR relic heal fix >>
    -- next_second / next_second2 start at the 99999 "never" sentinel in the DLL, so
    -- the 500 hp/s heals that guard the Colorado (until its scripted fall) and the
    -- Cerberus relic never ran. Arm both: the first pass heals at once, then each second.
    M.next_second = 0.0
    M.next_second2 = 0.0
-- CR relic heal fix <<
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
    UpdateInfoRelay()
-- CR Venus weather >>
    UpdateVenusWeather(dt)
-- CR Venus weather <<
    if not CRCoop.IsAuthority() then return end
    if CRCoop.IsNetworkGame() and not M.coopBootstrapped then
        M.coopBootstrapped = true
        -- The authored offline placeholder must not remain beside the humans.
        local offlinePlayer = GetHandle("player0_hover")
        if IsValid(offlinePlayer) and not CRCoop.IsHumanCraft(offlinePlayer) then RemoveObject(offlinePlayer) end
    end
    -- Misn08Mission::Execute body (DLL order preserved below).

    --[=[

Here is where you put what happens every frame.  

]=]

    M.user = GetPlayerHandle() --assigns the player a handle every frame
-- CR Venus weather >>
    UpdateVenusBeats()
-- CR Venus weather <<
-- CR Colorado base >>
    UpdateColoradoBase()
-- CR Colorado base <<
-- CR CCA walkers >>
    UpdateCcaWalkers()
-- CR CCA walkers <<

    if (not M.start_done) then
        subtit.Play("misn0800.wav") --starts opeing V.O.
        ClearObjectives()
        AddObjective("misn0800.otf", "white")
        AddObjective("misn0801.otf", "white")
        -- SetPilot(1, 30)
        SetScrap(1,30)
        Defend(M.ccagech1)
        Defend(M.ccagech2)
        M.start_gech_time = GetTime() + 329.0 -- starts the gechs towards the base
        M.gech_spawn_time = GetTime() + 280.0 -- starts attack on colorado
        M.trigger_check = GetTime() + 285.0
        M.fresh_meat_time = 100.0 -- build more units to send after player
        M.gech_check = GetTime() + 61.0 -- searches to see if the player encounters a gech
        M.first_wave_time = GetTime() + 20.0 -- starts the first wave of fighters
        SetWeaponMask(M.ccagech1, 1)
        SetWeaponMask(M.ccagech2, 1)
        if (M.nav1~=nil) then SetObjectiveName(M.nav1, "Drop Zone") end
        if (M.nav5~=nil) then SetObjectiveName(M.nav5, "Colorado Base") end
        if (M.nav4~=nil) then SetObjectiveName(M.nav4, "CCA Main Base") end
        M.base_check = GetTime() + 5.0
        M.start_done = true
    end

    if ((M.start_done) and (M.start_gech_time < GetTime()) and (not M.gech_started)) then --sets gechs into motion
        Goto(M.ccagech1, "gech_path1")
        Goto(M.ccagech2, "gech_path2")
        M.gech_started = true
    end
    -- this sends the first soviets into the user's base
    if ((M.first_wave_time < GetTime()) and (not M.first_wave)) then
        Goto(M.svpatrol2_2, M.nsdfrecycle)
        Goto(M.svpatrol2_3, M.nsdfrecycle)
        M.first_wave = true
    end

    if ((M.fresh_meat_time < GetTime()) and (not M.colorado_under_attack) and (not M.fresh_meat)) then
        M.cannon_fodder1 = BuildObject("svfigh", ENEMY_TEAM, M.ccarecycle)
        M.cannon_fodder2 = BuildObject("svfigh", ENEMY_TEAM, M.ccarecycle)
        M.cannon_fodder3 = BuildObject("svfigh", ENEMY_TEAM, M.ccarecycle)
        Goto(M.cannon_fodder1, "gech_path2")
        Goto(M.cannon_fodder2, "gech_path2")
        Goto(M.cannon_fodder3, "gech_path2")
        M.fresh_meat = true
    end

    if ((M.fighter_message_time < GetTime()) and (not M.colorado_under_attack) and (not M.fighter_message)) then
        subtit.Play("misn0817.wav") -- colorado: we're experiencing a lot of fighters - they know we're here - wonder what the main forces is waiting for
        M.fighter_message = true
    end


    -- colorado gets attacked by gech //////////////////////////////////////////////////////////////////////////

    if ((M.gech_spawn_time < GetTime()) and (not M.colorado_under_attack)) then --gech attacks colorado
        M.gech_spawn_time = GetTime() + 10.0

        if (NoPlayerWithin(M.nav5, 400.0)) then
            M.svpatrol2_2 = BuildObject("svfigh", ENEMY_TEAM, M.ccarecycle)
-- CR Colorado massacre >>
            -- The next line overwrites this slot (retained DLL quirk); keep the fighter for the strike.
            M.strike = { figh = M.svpatrol2_2, next_order = 0, released = false }
-- CR Colorado massacre <<
            M.svpatrol2_2 = BuildObject("svltnk", ENEMY_TEAM, M.ccarecycle)
            M.ccagech3 = BuildObject("svwalk", ENEMY_TEAM, "gech_spawn")
            SetWeaponMask(M.ccagech3, 1)
            Attack(M.ccagech3, M.colorado, 1)
            subtit.Play("misn0801.wav") -- player gets message that colorado is encountering hostiles "standby"
            M.colorado_message2_time = GetTime() + 10.0

            if (IsAlive(M.svpatrol2_1)) then
                Goto(M.svpatrol2_1, M.nav1)
            end
            if (IsAlive(M.svpatrol2_2)) then
                Goto(M.svpatrol2_2, M.nav1)
            end
            if (IsAlive(M.svpatrol2_3)) then
                Goto(M.svpatrol2_3, M.nav1)
            end

-- CR Colorado massacre >>
            M.strike.ltnk = M.svpatrol2_2
            for _, unit in ipairs(ColoradoStrikeUnits()) do
                if IsAlive(unit) then Attack(unit, M.colorado, 1) end
            end
-- CR Colorado massacre <<
            M.colorado_under_attack = true
        end
    end

    -- this is what happens if the player tries to get to the colorado before the attack - it speeds things up
    if ((M.player_nosey_time < GetTime()) and (not M.colorado_under_attack)) then
        M.player_nosey_time = GetTime() + 32.0

        if (AnyPlayerWithin(M.nav5, 700.0)) then
            M.gech_spawn_time = GetTime() + 10.0
-- CR Colorado massacre >>
            if not M.colorado_warned then
                M.colorado_warned = true
                subtit.Play("misn0824.wav") -- Collins: stay clear of the Colorado
            end
-- CR Colorado massacre <<

            if (IsAlive(M.svpatrol1_1)) then
                Attack(M.svpatrol1_1, NearestPlayer(M.svpatrol1_1))
            end
            if (IsAlive(M.svpatrol1_2)) then
                Attack(M.svpatrol1_2, NearestPlayer(M.svpatrol1_2))
            end
            if (IsAlive(M.svpatrol1_3)) then
                Attack(M.svpatrol1_3, NearestPlayer(M.svpatrol1_3))
            end
            if (IsAlive(M.svpatrol2_1)) then
                Attack(M.svpatrol2_1, M.nsdfrecycle)
            end
            if (IsAlive(M.svpatrol2_2)) then
                Attack(M.svpatrol2_2, M.nsdfrecycle)
            end
            if (IsAlive(M.svpatrol2_3)) then
                Attack(M.svpatrol2_3, M.nsdfrecycle)
            end
        end
    end

    if ((M.colorado_under_attack) and (M.colorado_message2_time < GetTime()) and (not M.colorado_message2)) then

        subtit.Play("misn0803.wav") --second message from colorado
        M.colorado_message3_time = GetTime() + 7.0
        M.colorado_message2 = true
    end

    if ((M.colorado_message2) and (M.colorado_message3_time < GetTime()) and (not M.colorado_message3)) then

        subtit.Play("misn0802.wav") --third message from colorado
        subtit.Queue("misn0804.wav") --final message from colorado
        M.colorado_message4_time = GetTime() + 10.0
        M.colorado_message3 = true
    end

    if ((M.colorado_message4_time < GetTime()) and (not M.kill_colorado)) then
        M.kill_colorado = true
    end

    if ((IsAlive(M.colorado)) and (not M.kill_colorado)) then
        if (GetTime()>M.next_second) then
            AddHealth(M.colorado, 500.0)
            M.next_second = GetTime() + 1.0
        end
    end

-- CR Colorado massacre >>
    if M.kill_colorado and M.colorado_deadline == nil then
        M.colorado_deadline = GetTime() + COLORADO_FALLBACK_S
        M.colorado_cleanup = GetTime() + COLORADO_CLEANUP_S
        ColoradoExtraStrike()
    end
    UpdateColoradoMassacre()
    if ColoradoMassacreDone() then
-- CR Colorado massacre <<
    if ((M.colorado_message3) and (M.kill_colorado) and (not M.colorado_message4)) then
        if (IsAlive(M.colorado)) then
            Damage(M.colorado, 20000)
        end
        M.remove_nav5_time = GetTime() + 15.0
        M.colorado_message4 = true
    end
-- CR Colorado massacre >>
    end
-- CR Colorado massacre <<

    if ((M.colorado_message4) and (M.remove_nav5_time < GetTime()) and (not M.colorado_destroyed)) then
        -- RemoveObject (M.colorado)
        RemoveObject (M.nav5)
        -- RemoveObject (M.drop)
        M.bad_news_time = GetTime() + 5.0
        M.colorado_destroyed = true
    end

    if ((M.colorado_destroyed) and (not M.bad_news) and (M.bad_news_time < GetTime())) then
        subtit.Play("misn0805.wav") --Corbett give player news of colorado fate
        M.bad_news_time = GetTime() + 30.0
        M.bad_news = true
    end

    if ((M.bad_news) and (M.bad_news_time < GetTime()) and (not M.gen_message)) then
        subtit.Play("misn0810.wav") --Gen Collins give player news of colorado fate
        M.gen_message = true
    end

    -- end soviet attack on colorado ///////////////////////////////////////////////////////////////////////////////


    -- this is going to give the soviets a recycler and start them attacking

    if ((M.bad_news) and (not M.ccarecycle_spawned)) then
        SetAIP("misn08.aip", ENEMY_TEAM)
        SetScrap(ENEMY_TEAM, 40)
        SetPilot(ENEMY_TEAM, 40)
        M.new_aip_time = GetTime() + 420.0
        if (IsAlive(M.ccagech3)) then
            Goto(M.ccagech3, "gech_path2")
        end

        if (IsAlive(M.svpatrol1_1)) then
            Goto(M.svpatrol1_1, "cam3_spawn")
        end
        if (IsAlive(M.svpatrol1_2)) then
            Goto(M.svpatrol1_2, "cam3_spawn")
        end
        if (IsAlive(M.svpatrol1_3)) then
            Goto(M.svpatrol1_3, "cam3_spawn")
        end

        M.ccarecycle_spawned = true
    end

    -- this is sending the third gech down the gech path when it gets to a certain point

    --[=[
    if ((M.ccarecycle_spawned) and (not M.gech3_move) and (M.gech_check_time < GetTime())) then
        if (GetDistance(M.ccagech3, M.stop_geyser2) < 30.0) then
            Goto(M.ccagech3, "gech_path2")
            M.gech3_there_time = GetTime() + 97.0
            M.gech3_move = true
        end
    end

]=]
-- CR restored walker content >>
    RestoredWalkerAdvance()
-- CR restored walker content <<


    -- this is what happens when the player encounters the gech before it reaches the nav point ////////////////////

    if ((M.gech_check < GetTime()) and (not M.gech_found) and (not M.gech_at_nav)) then
        M.gech_check = GetTime() + 6.0

        if ((AnyPlayerWithin(M.ccagech1, 400.0)) and (not M.gech_found1) and (not M.gech_found) and (not M.gech_at_nav)) then --if player reaches gech before gech reaches nav
            subtit.Play("misn0806.wav") -- "we're picking up something big on your radar, you may want to check it out"
            M.followup_message_time = GetTime() + 20.0 -- setting up follow up message about cca gech
            M.stumble2_check = GetTime() + 10.0
            M.no_stumble_check = GetTime() + 13.0
            M.gech1_there_time = 100.0
            M.gech2_there_time = 105.0
            M.gech_found1 = true
            M.gech_found = true
        end

        if ((AnyPlayerWithin(M.ccagech2, 400.0)) and (not M.gech_found) and (not M.gech_found2) and (not M.gech_at_nav)) then --if player reaches gech before gech reaches nav
            subtit.Play("misn0806.wav") -- "we're picking up something big on your radar, you may want to check it out"
            M.followup_message_time = GetTime() + 5.0 -- setting up follow up message about cca gech
            M.stumble2_check = GetTime() + 60.0
            M.no_stumble_check = GetTime() + 13.0
            M.gech1_there_time = 100.0
            M.gech2_there_time = 105.0
            M.gech_found2 = true
            M.gech_found = true
        end
    end

    if ((M.gech_found) and (M.followup_message_time < GetTime()) and (not M.followup_message)) then
        subtit.Play("misn0807.wav") -- "what the hell is that thing - approach with caution!"
        M.followup_message = true
    end


    if ((M.base_check < GetTime()) and (not M.base_set)) then
        M.base_check = GetTime() + 2.0

        if (IsAlive(M.nsdfmuf)) then
            local test = IsDeployed(M.nsdfmuf)

            if (test) then
                ClearObjectives()
                AddObjective("misn0800.otf", "green")
                AddObjective("misn0801.otf", "white")
                M.base_set = true
            end
        end
    end



    -- this is what happens when the player goes and sees the gech after the first nav is dropped

    if ((M.gech_found) and (M.stumble2_check < GetTime()) and (not M.second_gech_warning) and (not M.run_into_other_gech)) then
        M.stumble2_check = GetTime() + 21.0

        if ((M.gech_found1) and (AnyPlayerWithin(M.ccagech2, 100.0)) and (not M.run_into_other_gech)) then
            subtit.Play("misn0813.wav") --Oh no! Looks like you've found another one!
            M.run_into_other_gech = true
        end

        if ((M.gech_found2) and (AnyPlayerWithin(M.ccagech1, 100.0)) and (not M.run_into_other_gech)) then
            subtit.Play("misn0813.wav") --Oh no! Looks like you've found another one!
            M.run_into_other_gech = true
        end
    end

    -- this is when the player runs into one gech but the other gech gets half-way to base before being discovered

    if ((M.gech_found) and (M.no_stumble_check < GetTime()) and (not M.run_into_other_gech) and (not M.second_gech_warning)) then
        M.no_stumble_check = GetTime() + 9.0

        if ((M.gech_found1) and (Distance(M.gech_trigger2, M.ccagech2) < 100.0) and (not M.second_gech_warning)) then
            subtit.Play("misn0815.wav") --V.O. looks like we've got another one coming out of the west
            M.nav2 = BuildObject ("apcamr", 1, "cam2_spawn") -- builds camera near gech
            if (M.nav2~=nil) then SetObjectiveName(M.nav2, "Nav Alpha 1") end
            M.second_gech_warning = true
        end

        if ((M.gech_found2) and (Distance(M.gech_trigger3,M.ccagech1) < 100.0) and (not M.second_gech_warning)) then
            subtit.Play("misn0814.wav") --V.O. warns player of second gech
            M.nav3 = BuildObject ("apcamr", 1, "cam3_spawn") -- builds camera near gech
            if (M.nav3~=nil) then SetObjectiveName(M.nav3, "Nav Alpha 2") end
            M.second_gech_warning = true
        end
    end


    -- the following occurs when the approaching gechs get half-way to the player's base

    if ((M.colorado_under_attack) and (M.trigger_check < GetTime()) and (not M.gech_at_nav) and (not M.gech_found)) then
        M.trigger_check = GetTime() + 19.0

        if ((not M.gech_found) and (Distance(M.gech_trigger2, M.ccagech2) < 100.0) and (not M.gech_at_nav)) then --if gech reaches nav before player reaches gech
            subtit.Play("misn0809.wav") -- "We've detected something strange on approach from the east - standby"
            M.gech_warning_message = GetTime() + 20.0
            M.gech1_there_time = 100.0
            M.gech2_there_time = 105.0
            M.gech_at_nav = true
            M.gech_at_nav2 = true
        end

        if ((not M.gech_found) and (Distance(M.gech_trigger3,M.ccagech1) < 100.0) and (not M.gech_at_nav)) then --if gech reaches nav before player reaches gech
            subtit.Play("misn0808.wav") -- "We've detected something strange on approach from the west - standby"
            M.gech_warning_message = GetTime() + 20.0
            M.gech1_there_time = 100.0
            M.gech2_there_time = 105.0
            M.gech_at_nav = true
            M.gech_at_nav3 = true
        end
    end

    if ((M.gech_at_nav2) and (M.gech_warning_message < GetTime()) and (not M.player_warned_ofgech)) then --if player ignores gech_at_nav message
        subtit.Play("misn0814.wav") -- Check it out - we're dropping a nav camera there now
        M.nav2 = BuildObject ("apcamr", 1, "cam2_spawn") -- builds camera near gech
        if (M.nav2~=nil) then SetObjectiveName(M.nav2, "Nav Alpha 1") end
        M.time_waist = GetTime() + 14.0
        M.stumble1_check = GetTime() + 100.0
        M.player_warned_ofgech = true
    end

    if ((M.gech_at_nav3) and (M.gech_warning_message < GetTime()) and (not M.player_warned_ofgech)) then --if player ignores gech_at_nav message
        subtit.Play("misn0815.wav") -- Check it out - we're dropping a nav camera there now
        M.nav3 = BuildObject ("apcamr", 1, "cam3_spawn") -- builds camera near gech
        if (M.nav3~=nil) then SetObjectiveName(M.nav3, "Nav Alpha 2") end
        M.time_waist = GetTime() + 14.0
        M.stumble1_check = GetTime() + 100.0
        M.player_warned_ofgech = true
    end

    -- this is the player getting warned of the second gech if he hasn't gone to see the first one yet //////////////////

    if ((M.player_warned_ofgech) and (M.time_waist < GetTime()) and (not M.second_gech_warning) and (not M.bump_into_gech)) then
        M.time_waist = GetTime() + 14.0

        if ((M.gech_at_nav2) and (Distance(M.gech_trigger3,M.ccagech1) < 75.0) and (not M.second_gech_warning)) then --second gech found
            subtit.Play("misn0812.wav") --looks like we've got another one coming out of the east
            M.nav3 = BuildObject ("apcamr", 1, "cam3_spawn") -- builds camera near gech
            if (M.nav3~=nil) then SetObjectiveName(M.nav3, "Nav Alpha 2") end
            M.second_gech_warning = true
        end

        if ((M.gech_at_nav3) and (Distance(M.gech_trigger2, M.ccagech2) < 75.0) and (not M.second_gech_warning)) then --second gech found
            subtit.Play("misn0811.wav") --looks like we've got another one coming out of the west
            M.nav2 = BuildObject ("apcamr", 1, "cam2_spawn") -- builds camera near gech
            if (M.nav2~=nil) then SetObjectiveName(M.nav2, "Nav Alpha 1") end
            M.second_gech_warning = true
        end
    end

    -- this is what happens when the player goes and sees the gech after the first nav is dropped

    if ((M.player_warned_ofgech) and (M.stumble1_check < GetTime()) and (not M.second_gech_warning) and (not M.bump_into_gech)) then
        M.stumble1_check = GetTime() + 23.0

        if ((M.gech_at_nav2) and (AnyPlayerWithin(M.ccagech1, 100.0)) and (not M.bump_into_gech)) then
            subtit.Play("misn0813.wav") --Oh no! Looks like you've found another one!
            M.bump_into_gech = true
        end

        if ((M.gech_at_nav3) and (AnyPlayerWithin(M.ccagech2, 100.0)) and (not M.bump_into_gech)) then
            subtit.Play("misn0813.wav") --Oh no! Looks like you've found another one!
            M.bump_into_gech = true
        end
    end


    -- this makes the gechs attack the player's base when they get close enough

    if ((M.gech_found) or (M.gech_at_nav)) then
        if ((M.gech1_there_time < GetTime()) and (not M.gech1_at_base)) then
            M.gech1_there_time = GetTime() + 30.0

            if ((IsAlive(M.ccagech1)) and (Distance(M.ccagech1, M.stop_geyser3) < 100.0)) then
                if (IsAlive(M.nsdfrecycle)) then
                    Attack(M.ccagech1, M.nsdfrecycle)
                    if (M.gech1_blossom) then
                        SetWeaponMask(M.ccagech1, 5)
                    end
                    M.gech1_at_base = true
                else
                    if (IsAlive(M.nsdfmuf)) then
                        Attack(M.ccagech1, M.nsdfmuf)
                        if (M.gech1_blossom) then
                            SetWeaponMask(M.ccagech1, 5)
                        end
                        M.gech1_at_base = true
                    end
                end
            end
        end

        if ((M.gech2_there_time < GetTime()) and (not M.gech2_at_base)) then
            M.gech2_there_time = GetTime() + 30.0

            if ((IsAlive(M.ccagech2)) and (Distance(M.ccagech2, M.stop_geyser3) < 100.0)) then
                if (IsAlive(M.nsdfrecycle)) then
                    Attack(M.ccagech2, M.nsdfrecycle)
                    if (M.gech2_blossom) then
                        SetWeaponMask(M.ccagech2, 5)
                    end
                    M.gech2_at_base = true
                else
                    if (IsAlive(M.nsdfmuf)) then
                        Attack(M.ccagech2, M.nsdfmuf)
                        if (M.gech2_blossom) then
                            SetWeaponMask(M.ccagech2, 5)
                        end
                        M.gech2_at_base = true
                    end
                end
            end
        end

        if ((M.gech3_there_time < GetTime()) and (not M.gech3_at_base)) then
            M.gech3_there_time = GetTime() + 30.0

            if ((IsAlive(M.ccagech3)) and (Distance(M.ccagech3, M.stop_geyser3) < 100.0)) then
                if (IsAlive(M.nsdfrecycle)) then
                    Attack(M.ccagech3, M.nsdfrecycle)
                    if (M.gech3_blossom) then
                        SetWeaponMask(M.ccagech3, 5)
                    end
                    M.gech3_at_base = true
                else
                    if (IsAlive(M.nsdfmuf)) then
                        Attack(M.ccagech3, M.nsdfmuf)
                        if (M.gech3_blossom) then
                            SetWeaponMask(M.ccagech3, 5)
                        end
                        M.gech3_at_base = true
                    end
                end
            end
        end

    end

    -- now I'm loading the new attack aips if the correct amount of time has passed

    if (M.new_aip_time < GetTime()) then
        M.new_aip_time = GetTime() + 420.0

        M.units1 = CountHumanUnits(M.stop_geyser2, 5000.0, "avfigh")
        M.units2 = CountHumanUnits(M.stop_geyser2, 5000.0, "avtank")

        if (M.units1 > M.units2) then
            SetAIP("misn08b.aip", ENEMY_TEAM)
        else
            SetAIP("misn08a.aip", ENEMY_TEAM)
        end
    end

    -- this is apc code

    if ((IsAlive(M.ccaapc)) and (not M.apc_attack)) then
        if (IsAlive(M.guntower1)) then
            Attack(M.ccaapc, M.guntower1)
        else
            if (IsAlive(M.guntower2)) then
                Attack(M.ccaapc, M.guntower2)
            else
                if (IsAlive(M.nsdfmuf)) then
                    Attack(M.ccaapc, M.nsdfmuf)
                else
                    if (IsAlive(M.nsdfrecycle)) then
                        Attack(M.ccaapc, M.nsdfrecycle)
                    end
                end
            end
        end

        M.apc_attack = true
    end

    if ((M.apc_attack) and (not IsAlive(M.ccaapc))) then
        M.apc_attack = false
    end


    -- This is another radar comment when the player gets extrememly close to the gech

    --[=[
    if ((M.gech_found) and (not M.too_close_message) or (M.gech_at_nav) and (not M.too_close_message)) then
        if ((GetDistance(M.user, M.ccagech1) < 75.0) and (not M.too_close_message)) then
            AudioMessage("misn0816.wav") -- pull out!! what the hell is that!
            M.too_close_message = true
        end

        if ((GetDistance(M.user, M.ccagech2) < 75.0) and (not M.too_close_message)) then
            AudioMessage("misn0816.wav") -- pull out!! what the hell is that!
            M.too_close_message = true
        end
    end
]=]
-- CR restored walker content >>
    RestoredCloseWarning()
-- CR restored walker content <<


    if ((M.pull_out_message < GetTime()) and (not M.too_close_message)) then
        subtit.Play("misn0816.wav") -- pull out!! what the hell is that!
        M.too_close_message = true
    end


    -- this will make the gechs use the popper

    if ((IsAlive(M.ccagech1)) and (not M.gech1_blossom) and (GetHealth(M.ccagech1) < 0.25)) then
        SetWeaponMask(M.ccagech1, 4)
        M.pull_out_message = GetTime() + 6.0
        M.gech1_blossom = true
    end

    if ((IsAlive(M.ccagech2)) and (not M.gech2_blossom) and (GetHealth(M.ccagech2) < 0.25)) then
        SetWeaponMask(M.ccagech2, 4)
        M.pull_out_message = GetTime() + 6.0
        M.gech2_blossom = true
    end

    if ((IsAlive(M.ccagech3)) and (not M.gech3_blossom) and (GetHealth(M.ccagech3) < 0.25)) then
        SetWeaponMask(M.ccagech3, 4)
        M.pull_out_message = GetTime() + 6.0
        M.gech3_blossom = true
    end

    -- this is the relic code

    if ((not M.cerb_found) and (not M.relic_message) and ((IsInfo("hbblde") == true) or (IsInfo("hbbldf") == true))) then
        if (M.base_dead) then
            subtit.Play("misn0821.wav") -- that's not it, the ruins will be much larger
            M.relic_message = true
        else
            subtit.Play("misn0822.wav") -- this area is crawling with relics recon as many as possible
            M.relic_message = true
        end
    end

    if ((not M.cerb_found) and (M.cerb_check < GetTime())) then
        M.cerb_check = GetTime() + 3.0

        if (AnyPlayerWithin(M.main_relic, 70.0)) then
            if (M.base_dead) then
                subtit.Play("misn0818.wav") -- well done
                subtit.Queue("misn0826.wav")
                SucceedMission(GetTime() + 30.0, "misn08w1.des") --well done
                M.cerb_found = true
            else
                subtit.Play("misn0819.wav") -- this must be how they built gechs - find base
                M.cerb_found = true
            end
        end
    end

    if (IsAlive(M.main_relic)) then
        if (GetTime()>M.next_second2) then
            AddHealth(M.main_relic, 500.0)
            M.next_second2 = GetTime() + 1.0
        end
    end


    -- win/loose conditions /////////////////////////////

    if ((not IsAlive(M.ccarecycle)) and (not IsAlive(M.ccamuf)) and (not M.base_dead)) then
        if (M.cerb_found) then
            subtit.Play("misn0818.wav")
            subtit.Queue("misn0826.wav")
            SucceedMission(GetTime() + 30.0, "misn08w1.des") --well done
            M.base_dead = true
        else
            ClearObjectives()
            AddObjective("misn0801.otf", "green")
            AddObjective("misn0802.otf", "white")
            subtit.Play("misn0820.wav") -- find cerbeus
            SetObjectiveOn(M.main_relic)
            SetObjectiveName(M.main_relic, "Relic Site")
            M.base_dead = true
        end
    end

    if ((not IsAlive(M.nsdfrecycle)) and (not M.game_over)) then
        subtit.Play("misn0421.wav")
        FailMission(GetTime() + 15.0, "misn08f1.des") --lost recycler
        M.game_over = true
    end
end

-- Redux serializes this table's primitive/game values, including handles.
-- Load must not rerun Setup or replay opening events. LuaMission handles remapping.
function Save()
-- CR Venus weather >>
    if venusStarted and ((not CRCoop.IsNetworkGame()) or CRCoop.IsAuthority()) then
        M.weatherState = CRVenusWeather.Save()
    end
-- CR Venus weather <<
    return M
end

function Load(saved)
    assert(type(saved) == "table", "misn08: missing mission save state")
    M = saved
end
