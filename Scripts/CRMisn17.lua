-- Mission 17 ownership, concealed arrivals and shared presentation.
-- Ordered E/A + C transport adapted from Mission 16; gameplay stays in misn17.lua.
local Runtime = {}
function Runtime.Create(getState)
local M = getState()
local LEADER_TEAM = 1
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})
local exu = require("exu")
if type(IsNetGame)=="function" and IsNetGame() then
    assert(exu.DisableStartingRecycler and exu.GetMyNetID,"misn17 needs bundled EXU co-op hooks")
    exu.DisableStartingRecycler()
end
local CRCoop = require("CRCoop")
local subtit = require("ScriptSubtitles")
local pda = require("PersistentConfig")
local Environment = require("Environment")
local roster = require("CRFuryRoster")
local Jungle=require("CRJungle17").Create({exu=exu,state=function() return M end})
local Crystal
SetAIControl(6,true) -- startup only; never enable strategic AI on humans
local unpackArgs = unpack or table.unpack
-- "J" belongs to CRCoopComms; crystal reports use their own letter so comms still reach CRCoop.
local CRYSTAL_CHANNEL = "Y"
local OWN_CHANNELS = { E = true, C = true, A = true, [CRYSTAL_CHANNEL] = true }
-- Redux reads a Lua packet string's length through a signed byte (FUN_005059B0), so a
-- 128-255 byte string crashes every receiving peer. CRWire splits long strings.
local CRWire = require("CRWire")
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
    if op=="Jungle" then return Jungle.Apply(...) end
    if op=="CrystalCargo" then return Crystal.AddCargo(...) end
    if op == "Label" then
        local handle, label = ...
        if type(SetLabel) == "function" and IsValid(handle) and type(label) == "string" then
            pcall(SetLabel, handle, label)
        end
    elseif op == "SucceedMission" or op == "FailMission" then
        Jungle.Stop()
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
        pcall(SetLabel, handle, "crco17_" .. labelSerial)
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
        M.coopPendingResult = { op, when, description, ready = GetTime() + (op == "SucceedMission" and 3.5 or 0) }
    else
        -- Offline the DLL re-issues these every frame it holds; stay a pass-through.
        native[op](when, description)
    end
end
local function SucceedMission(...)
    if not M.cr17VictoryVoice then
        M.cr17VictoryVoice=true
        -- The stock imminence line is queued by the faithful body first.
        Present("Queue","misn1709.wav")
    end
    local when,description=...
    return EndMission("SucceedMission", math.max(when,GetTime()+18),description)
end
local function FailMission(...)
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
    if seq == receivedEvent + 1 and (native[op] or op == "Label" or op=="Jungle" or op=="CrystalCargo") then
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

local R = {}
local function State()
    M=getState()
    M.cr17=M.cr17 or {arrivals={},serial=0}
    return M.cr17
end
local function Valid(h) return h~=nil and h~=0 and IsValid(h) end
local function Ticket(h)
    if type(h)~="number" or h>=0 then return nil end
    return State().arrivals[-h]
end
function R.IsAlive(h)
    -- Negative request ids reserve an artillery-counter slot while entry is
    -- concealed. They never reach a native handle API or cross the network.
    if Ticket(h) then return true end
    return Valid(h) and IsAlive(h)
end
function R.GetCurrentCommand(h)
    if Ticket(h) then return AiCommand.NONE end
    return GetCurrentCommand(h)
end
local function ConfigureAlliances()
    for a=1,4 do
        for b=1,4 do if a~=b then Ally(a,b) end end
        Ally(a,7);Ally(7,a)
        UnAlly(a,6);UnAlly(6,a)
    end
end
local function Safe(where,point)
    if not point and type(where)~="string" and not Valid(where) then return false end
    local safe=true
    CRCoop.ForEachPlayerHandle(function(h)
        if Valid(h) and GetDistance(h,where)<460 then safe=false end
    end)
    return safe
end
local Trees=require("CRJungleTrees17").Create({state=function() return M end,
    authority=CRCoop.IsAuthority,safe=function(v) return Safe(v,true) end})
local function Entry(request)
    -- Authored entry is preferred. Other intact factories/counter are fallback
    -- approaches; if every entrance is watched, retain the request and retry.
    if Safe(request.where) then return request.where end
    if Safe("counter") then return "counter" end
    for i=1,4 do
        local h=GetHandle("savfactory"..i)
        if Valid(h) and IsAlive(h) and Safe(h) then return h end
    end
end
local function ReplaceTickets(t,old,new)
    for k,v in pairs(t) do
        if v==old then t[k]=new
        elseif type(v)=="table" and k~="arrivals" then ReplaceTickets(v,old,new) end
    end
end
function R.Order(op,h,target,priority)
    local request=Ticket(h)
    if request then request.order={op,target,priority};return end
    if Valid(h) and Valid(target) then return _G[op](h,target,priority) end
end
function R.Spawn(odf,team,where)
    local s=State()
    if not CRCoop.IsAuthority() then return nil end
    if odf=="hbptow" then
        return GetHandle("cr17_tower"..tostring(where):match("(%d+)$"))
    end
    if odf=="boltmine2" then
        return GetHandle("cr17_mine"..tostring(where):match("(%d+)$"))
    end
    if team==3 then team=7 elseif team==2 then team=6 end
    if odf~="hvsav" and odf~="hvsat" then return BuildObject(odf,team,where) end
    if M.missionwon or M.missionfail or M.coopResult then return nil end
    s.serial=s.serial+1
    s.arrivals[s.serial]={odf=roster.Select(odf,M),team=team,where=where}
    return -s.serial
end
local function Arrivals()
    local s=State()
    if M.missionwon or M.missionfail or M.coopResult then s.arrivals={};return end
    if (M.missionstart and not M.openingcindone) or M.minecinstart then return end
    local built=0
    -- Saved request sequence, never pairs order, defines deterministic entry.
    for id=1,s.serial do
        local r=s.arrivals[id]
        if r and built<2 then
            local where=Entry(r)
            if where then
                local h=BuildObject(r.odf,r.team,where)
                if Valid(h) then
                    ReplaceTickets(M,-id,h)
                    if r.order then R.Order(r.order[1],h,r.order[2],r.order[3])
                    else R.Order("Attack",h,M.avrec,1) end
                    s.arrivals[id]=nil;built=built+1
                end
            end
        end
    end
end
local function Failure()
    if not CRCoop.IsAuthority() or M.missionwon or M.missionfail then return end
    M.missionfail=true
    AudioMessage("misn1704.wav")
    FailMission(GetTime()+20,"misn17l1.des")
end
function R.SetScrap(team,amount)
    -- One shared production base, with a bounded +10 starting scrap per guest.
    local count=0
    CRCoop.ForEachHumanTeam(function() count=count+1 end)
    return SetScrap(1,amount+10*math.max(0,math.min(4,count)-1))
end
function R.SetAIP(file) return SetAIP(file,6) end
function R.Start()
    State().started=nil
    CRCoop.Initialize({getLocalPlayerId=function() return exu.GetMyNetID and exu.GetMyNetID() end,
        leaderTeam=1,humanTeamMin=1,humanTeamMax=4,rallyPoints={[0]="avrecy18_recycler"},
        onOutOfLives=Failure})
    if localCameraActive then native.CameraFinish() end
    ConfigureAlliances();ResetPresentation();lastAudio=nil
    pda.Initialize();subtit.Initialize()
    Environment.Init({nativeBaseline=true})
    Jungle.Reset(State().jungle)
    Environment.BindWeatherSensors("Achilles",Jungle)
    Crystal.Reset()
end
function R.TrackArtillery(h)
    if Valid(h) then Environment.OnObjectCreated(h) end
    return CRCoop.IsAuthority() and Valid(h) and CRCoop.IsHumanTeam(GetTeamNum(h))
end
function R.CreatePlayer(id,name,team) CRCoop.CreatePlayer(id,name,team);ConfigureAlliances() end
function R.AddPlayer(id,name,team) CRCoop.AddPlayer(id,name,team);ConfigureAlliances() end
function R.DeletePlayer(id) CRCoop.DeletePlayer(id) end
local function ReceiveOwn(from,kind,...)
    if ReceivePresentation(from,kind,...) then return true end
    if kind==CRYSTAL_CHANNEL then
        local player=CRCoop.GetPlayers()[from]
        local label,towing=...
        if CRCoop.IsAuthority() and player and CRCoop.IsHumanTeam(player.team)
            and type(label)=="string" and type(towing)=="boolean" then
            Crystal.Report(player.team,label,towing)
        end
        return true
    end
end
function R.Receive(from,kind,...)
    State()
    -- Only this file's channels are wire-encoded; CRCoop's own packets pass through untouched.
    if OWN_CHANNELS[kind] and ReceiveOwn(from,kind,CRWire.Unpack(...)) then return true end
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
    Crystal.Poll(CRCoop.IsAuthority(),function(label,towing) Send(0, CRYSTAL_CHANNEL, CRWire.Pack(label,towing)) end)
    if not M.coopResult then
        Jungle.Update(dt,CRCoop.IsAuthority(),function(...)
            Present("Jungle",...)
        end)
        M.cr17Jungle=Jungle.Describe()
    end
    if not CRCoop.IsAuthority() or M.coopResult or M.missionfail then return false end
    Trees.Update()
    if not s.fieldBound then
        for i=1,53 do M.MINE[i]=GetHandle("cr17_mine"..i) end
        M.minesmade=true;s.fieldBound=true
    end
    Arrivals()
    -- The 1.5 field includes mine54 in addition to the DLL's 53 slots.
    -- Collapse it on the final sweep update; there is no unaddressed live mine.
    if M.minesdestroyed and M.minecount==53 then
        local h=GetHandle("cr17_mine54")
        if Valid(h) and IsAlive(h) then Damage(h,10000) end
    end
    -- A host skip is local; cap the shared intro at its authored unused 35 s
    -- timer if native path completion no longer advances after that skip.
    if M.missionstart and not M.openingcindone and GetTime()>M.camdone then
        M.openingcindone=true
        for i=1,7 do M["camera"..i]=false end
        CameraFinish();StopAudioMessage(M.aud1)
    end
    return true
end
function R.Save() State().jungle=Jungle.Save() end
function R.Load() M=getState();R.Start() end
R.Coop,R.Exu,R.Native=CRCoop,exu,native
R.Jungle=Jungle
Crystal=require("CRCrystals17").Create({state=function() return M end,human=CRCoop.IsHumanTeam,
    voice=AudioMessage,off=SetObjectiveOff,remove=RemoveObject,mark=SetObjectiveOn,name=SetObjectiveName,
    anyNear=function(h,r) return Valid(h) and CRCoop.AnyPlayerSatisfies(function(p) return Valid(p) and GetDistance(p,h)<r end) end,
    cargo=function(...) Present("CrystalCargo",...) end,
    objective=function(name,color,duration,text,create)
        if create then return AddObjective(name,color,duration,text) end
        return UpdateObjective(name,color,duration,text)
    end})
R.Crystal=Crystal
function R.AfterUpdate() Crystal.Update() end
R.AudioMessage,R.StopAudioMessage=AudioMessage,StopAudioMessage
R.CameraReady,R.CameraPath,R.CameraObject=CameraReady,CameraPath,CameraObject
R.CameraFinish,R.CameraCancelled=CameraFinish,CameraCancelled
R.SetObjectiveName,R.SetObjectiveOn=SetObjectiveName,SetObjectiveOn
R.ClearObjectives=function(...)
    M.cr17ObjectiveRevision=(M.cr17ObjectiveRevision or 0)+1
    return ClearObjectives(...)
end
R.AddObjective=AddObjective
R.SucceedMission,R.FailMission=SucceedMission,FailMission
return R
end
return Runtime
