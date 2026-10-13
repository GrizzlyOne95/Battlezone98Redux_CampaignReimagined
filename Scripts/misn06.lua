-- NSDF misn06: source-faithful stock Battlezone 98 Redux / Lua 5.1 port.
-- Authority: BZ1/from_bz2_dll_src/Misn06Mission.cpp(DLL source only).
-- Original disabled C++ blocks are kept verbatim in Lua long comments.
-- No community Lua or Redux mission logic is used.
-- Preserve Execute order: several transitions intentionally occur in one update.
-- See Docs/MISN06_LUA_PORT.md for compatibility adaptations and runtime checks.

local M = {}

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})
local exu = require("exu")
-- Native MultST Init precedes Start; retain the authored Wyoming only.
if type(IsNetGame) == "function" and IsNetGame() then
    assert(exu.DisableStartingRecycler and exu.GetMyNetID,
        "misn06 co-op requires the bundled EXU multiplayer hooks")
    exu.DisableStartingRecycler()
end
local subtit = require("ScriptSubtitles")
local CRCoop = require("CRCoop")
local LEADER_TEAM, ENEMY_TEAM, SUPPORT_TEAM = 1, 5, 7

-- Co-op presentation uses the established misn03/misn05 E/A and C transport.
-- Only the campaign leader runs the mission body below; HUD/audio/removal/timer/
-- end calls are explicitly delivered to every peer.
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
    Play = subtit.Play, Queue = subtit.Queue, Stop = subtit.Stop,
}
local nativeIsInfo = IsInfo
local events, acknowledgements = {}, {}
local receivedEvent = 0
local nextEventSend, nextCameraSend = 0, 0
local cameraFrame, cameraGeneration, cameraSerial = nil, 0, 0
local remoteCameraSerial, localCameraGeneration = 0, 0
local cameraSkipped, localCameraActive = false, false
local remoteCamera
-- IsInfo is local UI state (the selected object's info panel). Guests relay
-- the five prefixes this mission reads; the leader honours a report for 1 s.
local INFO_PREFIXES = { "obheph", "obstp1", "obstp8", "obstp3", "sblpad" }
local isInfoPrefix = {}
for _, prefix in ipairs(INFO_PREFIXES) do isInfoPrefix[prefix] = true end
local remoteInfo, nextInfoSend = {}, 0

local function ResetPresentation()
    events, acknowledgements, receivedEvent = {}, {}, 0
    nextEventSend, nextCameraSend = 0, 0
    cameraFrame, cameraGeneration, cameraSerial = nil, 0, 0
    remoteCamera, remoteCameraSerial, localCameraGeneration = nil, 0, 0
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

local function Present(op, ...)
    if CRCoop.IsNetworkGame() then
        if not CRCoop.IsAuthority() then return end
        events[#events + 1] = { op = op, args = { ... }, n = select("#", ...), expires = GetTime() + 5 }
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
    end
    if cameraSkipped or not IsValid(cam.target) then return end
    if cam.kind == "O" then
        if not IsValid(cam.subject) then return end
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

-- Guests report which of the five IsInfo prefixes their own UI currently shows.
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
                    Send(id, "E", seq, event.op, event.expires, unpackArgs(event.args, 1, event.n))
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
    local seq, op, expires = ...
    if type(seq) ~= "number" or type(op) ~= "string" or type(expires) ~= "number" then return true end
    if seq == receivedEvent + 1 and (native[op] or op == "Resources") then
        local args = { select(4, ...) }
        -- Dynamic handles can arrive after the Lua packet. Withhold the ACK
        -- until the next retransmission resolves it, rather than losing markers.
        local missing = (op == "SetObjectiveOn" or op == "SetObjectiveName" or op == "SetUserTarget") and
            not IsValid(args[1])
        if missing and GetTime() < expires then return true end
        -- A target destroyed before its packet arrived must not block the
        -- stream (and the mission result) forever. Only that stale marker drops.
        if not missing then ApplyPresentation(op, unpackArgs(args, 1, select("#", ...) - 3)) end
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

-- BuildObject invokes AddObject synchronously; misn06's AddObject is native-neutral.

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

-- Absent handles must not satisfy range triggers or reach stock handle overloads.
local function MissionDistance(a, b)
    if not IsValid(a) then return math.huge end
    if type(b) ~= "string" and not IsValid(b) then return math.huge end
    return GetDistance(a, b)
end

local function EnemyWithin(h, distance)
    if not IsAlive(h) then return false end
    local enemy = GetNearestEnemy(h)
    return MissionDistance(h, enemy) < distance
end

local function AudioDone(message)
    return message == nil or IsAudioMessageDone(message)
end

local function StopAudio(message)
    if message == nil then return end
    -- Net games stop the shared subtitle/audio sequence on every peer.
    if CRCoop.IsNetworkGame() then subtit.Stop() else StopAudioMessage(message) end
end

local function NearestEnemy(h)
    if not IsValid(h) then return nil end
    return GetNearestEnemy(h)
end

-- Co-op trigger helpers. Offline CRCoop iterates just the local player, so each
-- reproduces the DLL's single-player test exactly.
local function AnyPlayerWithin(target, distance)
    return CRCoop.AnyPlayerSatisfies(function(h) return MissionDistance(h, target) < distance end)
end

-- Extraction: every player (a dead player blocks until respawned at Wyoming).
local function AllPlayersWithin(target, distance)
    return CRCoop.AllPlayersSatisfy(function(h) return MissionDistance(h, target) < distance end)
end

-- True when every present player is farther than `distance` from `target`.
local function NoPlayerWithin(target, distance)
    local clear = true
    CRCoop.ForEachPlayerHandle(function(h)
        if not (MissionDistance(h, target) > distance) then clear = false end
    end)
    return clear
end

-- True when no present player has an enemy within `distance` (the bogey gate).
local function NoPlayerEnemyWithin(distance)
    local clear = true
    CRCoop.ForEachPlayerHandle(function(h)
        if not (MissionDistance(NearestEnemy(h), h) > distance) then clear = false end
    end)
    return clear
end

-- The human craft nearest `from`; the leader's own craft when none is present.
local function NearestPlayer(from)
    local best, bestDistance = nil, math.huge
    CRCoop.ForEachPlayerHandle(function(h)
        local distance = MissionDistance(from, h)
        if best == nil or distance < bestDistance then best, bestDistance = h, distance end
    end)
    return best or M.player
end

-- CR restored VO >>
-- Campaign Reimagined addition: voice-over cut from the stock mission (the DLL
-- never plays these). Every use below sits inside matching marker lines and keeps
-- the original statements in an else branch; set RESTORED_VO=false for stock audio.
local RESTORED_VO = true
local CUT_VO = {
    blockade = "misn0609.wav", hephestus = "misn0610.wav",
    collins = "misn0615.wav", b2a = "misn0616.wav", b2b = "misn0617.wav",
    b2c = "misn0618.wav", b2d = "misn0619.wav", b2e = "misn0620.wav",
    b3a = "misn0621.wav", b3b = "misn0622.wav", touchdown = "misn0623.wav",
    b3c1 = "misn0624.wav", b4a = "misn0625.wav", b4b = "misn0626.wav",
    b5 = "misn0627.wav", late628 = "misn0628.wav", lateCorbett = "misn0637.wav",
    lateSuccess = "misn0639.wav", b3c2 = "misn0641.wav", yessir = "misn0652.wav",
    firstReminder = "misn0693.wav",
}
-- CR restored VO <<

local function ResetState()
    M = {}
    M.missionstart = false
    M.starportdisc = false
    M.star1recon = false
    M.star2recon = false
    M.star3recon = false
    M.star = false
    M.star4recon = false
    M.star5recon = false
    M.star6recon = false
    M.star7recon = false
    M.star8recon = false
    M.star9recon = false
    M.star10recon = false
    M.star11recon = false
    M.missionfail = false
    M.starportreconed = false
    M.surveystarport = false
    M.relicmissing = false
    M.haephestusdisc = false
    M.blockadefound = false
    M.ccabasedisc = false
    M.relicgone = false
    M.missionfail1 = false
    M.missionwon = false
    M.newobjective = false
    M.reconheaphestus = false
    M.recoverrelic = false
    M.neworders = false
    M.safebreak = false
    M.ccaattack = false
    M.hidob2 = false
    M.buildcam = false
    M.ccapullout = false
    M.transarrive = false
    M.touchdown = false
    M.lprecon = false
    M.fifteenmin = false
    M.economyccaplatoon = false
    M.tenmin = false
    M.threemin = false
    M.fivemin = false
    M.twomin = false
    M.platoonhere = false
    M.corbettalive = false
    M.lincolndes = false
    M.loopbreak1 = false
    M.opencamdone = false
    M.cam1done = false
    M.cam3done = false
    M.patrol1set = false
    M.patrol2set = false
    M.patrol3set = false
    M.startpat1 = false
    M.startpat2 = false
    M.startpat3 = false
    M.startpat4 = false
    M.wave1start = false
    M.wave2start = false
    M.wave3start = false
    M.launchpadreconed = false
    M.patrol1spawned = false
    M.breakme = false
    M.patrol2spawned = false
    M.patrol3spawned = false
    M.transgone = false
    M.bugout = false
    M.pickupset = false
    M.pickupreached = false
    M.hephikey = false
    M.reminder = false
    M.dustoff = false
    M.fail3 = false
    M.trigger1 = false
    M.ob1 = false
    M.ob2 = false
    M.ob3 = false
    M.ob4 = false
    M.timergone = false
    M.timerset = false
    M.respawn = false
    M.simcam = false
    M.removal = false
    M.breakout1 = false
    M.attack = false
    M.breaker = false
    M.death = false
    M.fifthplatoon = false
    M.breaker19 = false
    M.bustout = false
    M.doneaud1 = false
    M.doneaud2 = false
    M.endme = false
    M.doneaud3 = false
    M.missionfail3 = false
    M.missionfail4 = false
    M.doneaud4 = false
    M.doneaud5 = false
    M.loopbreaker = false
    M.transportgone = 99999.0
    M.searchtime = 99999.0
    M.processtime = 99999.0
    M.transportarrive = 99999.0
    M.oneminstrans = 99999.0
    M.transaway = 99999.0
    M.platoonarrive = 99999.0
    M.fifteenminsplatoon = 99999.0
    M.tenminsplatoon = 99999.0
    M.threeminsplatoon = 99999.0
    M.fiveminsplatoon = 99999.0
    M.check1 = 99999.0
    M.time1 = 99999.0
    M.twominsplatoon = 99999.0
    M.opencamtime = 99999.0
    M.cam1time = 99999.0
    M.cam3time = 99999.0
    M.wave1 = 99999.0
    M.wave2 = 99999.0
    M.wave3 = 99999.0
    M.lincolndestroyed = 99999.0
    M.patrol1time = 99999.0
    M.patrol2time = 99999.0
    M.patrol3time = 99999.0
    M.deathtime = 99999.0
    M.hephdisctime = 99999.0
    M.identtime = 99999.0
    M.discstar = 99999.0
    M.removetimer = 99999.0
    M.timerstart = 99999.0
    M.start1 = 99999.0
    M.spfail = 99999.0
    M.reconsptime = 99999.0
    M.endtime = 99999.0
    M.haephestus = nil
    M.sim1 = nil
    M.sim2 = nil
    M.sim3 = nil
    M.sim4 = nil
    M.sim5 = nil
    M.sim6 = nil
    M.sim7 = nil
    M.sim8 = nil
    M.sim9 = nil
    M.sim10 = nil
    M.simaud1 = nil
    M.simaud2 = nil
    M.simaud3 = nil
    M.simaud4 = nil
    M.simaud5 = nil
    M.heph1 = nil
    M.heph2 = nil
    M.enemy = nil
    M.aud500 = nil
    M.relic = nil
    M.spawnme = nil
    M.starport = nil
    M.player = nil
    M.nav1 = nil
    M.rendezvous = nil
    M.blockade1 = nil
    M.avrec = nil
    M.svrec = nil
    M.launchpad = nil
    M.starportcam = nil
    M.dustoffcam = nil
    M.art1 = nil
    M.w1u1 = nil
    M.w1u2 = nil
    M.w1u3 = nil
    M.aud1 = nil
    M.aud2 = nil
    M.aud3 = nil
    M.aud4 = nil
    M.aud5 = nil
    M.aud6 = nil
    M.aud7 = nil
-- CR restored VO >>
    M.aud610 = nil
    M.aud636 = nil
    M.vo609 = false
    M.vob1 = false
    M.vob3 = false
    M.vob3played = false
    M.vob3choice = nil
    M.vob3h = nil
    M.vob4 = false
    M.vob4played = false
    M.vob4h = nil
    M.vob5 = false
-- CR restored VO <<
    M.aud8 = nil
    M.aud9 = nil
    M.w2u1 = nil
    M.w2u2 = nil
    M.w2u3 = nil
    M.w3u1 = nil
    M.w3u2 = nil
    M.w3u3 = nil
    M.wAu1 = nil
    M.wAu2 = nil
    M.wAu3 = nil
    M.p5u1 = nil
    M.turret = nil
    M.trigger = nil
    M.star1 = nil
    M.star2 = nil
    M.star3 = nil
    M.star4 = nil
    M.star5 = nil
    M.star6 = nil
    M.star7 = nil
    M.star8 = nil
    M.star9 = nil
    M.star10 = nil
    M.star11 = nil
    M.p5u2 = nil
    M.p5u3 = nil
    M.p5u4 = nil
    M.p5u5 = nil
    M.p5u6 = nil
    M.p5u7 = nil
    M.p5u8 = nil
    M.p5u9 = nil
    M.p5u10 = nil
    M.p5u11 = nil
    M.p5u12 = nil
    M.aud20 = nil
    M.aud21 = nil
    M.pu1p1 = nil
    M.pu2p1 = nil
    M.pu3p1 = nil
    M.pu4p1 = nil
    M.pu1p2 = nil
    M.pu2p2 = nil
    M.pu3p2 = nil
    M.pu4p2 = nil
    M.pu1p3 = nil
    M.pu2p3 = nil
    M.pu3p3 = nil
    M.pu4p3 = nil
    M.pu1p4 = nil
    M.pu2p4 = nil
    M.pu3p4 = nil
    M.aud15 = nil
    M.aud16 = nil
    M.aud54 = nil
    M.svu1 = nil
    M.svu2 = nil
    M.svu3 = nil
    M.svu4 = nil
    M.bogey = nil
    M.ccap1 = nil
    M.ccap2 = nil
    M.ccap3 = nil
    M.ccap4 = nil
    M.ccap5 = nil
    M.ccap6 = nil
    M.ccap7 = nil
    M.ccap8 = nil
    M.ccap9 = nil
    M.ccap10 = nil
    M.ccap11 = nil
    M.ccap12 = nil
    M.ccap13 = nil
    M.ccap14 = nil
    M.ccap15 = nil
    M.cam1hgt = 0
    M.patrol1start = 0
    M.patrol2start = 0
    M.patrol3start = 0
    M.extractpoint = 0
    M.hephwarn = 0
    M.ident = 0
    M.stardisc = 0
    M.aud100 = nil
    M.aud101 = nil
    M.aud102 = nil
    M.aud103 = nil
    M.aud104 = nil
    M.aud105 = nil
    M.audmsg = nil
end

function Save()
    return M
end

function Load(state)
    if state ~= nil then M = state end
end

function Start()
    ResetState()
    CRCoop.Initialize({
        getLocalPlayerId = function() return exu.GetMyNetID and exu.GetMyNetID() end,
        leaderTeam = LEADER_TEAM, humanTeamMin = 1, humanTeamMax = 4,
        onOutOfLives = function() FailMission(GetTime() + 3.0) end,
        -- MultST consumes its spawn buoys during initialization. Rally at the
        -- persistent Wyoming instead of the removed team-start marker.
        rallyPoints = { [1] = "avrecy-1_recycler" },
    })
    ConfigureAlliances()
    ResetPresentation()
    --[=[ DLL source comment (inactive C++):
/*
	Here's where you
	set the values
	at the start.  
	*/
    ]=]
    M.discstar = 99999999999.0
    M.missionstart = true
    M.endtime = 999999999999.0
    M.corbettalive = true
    M.fifthplatoon = true
    M.reconsptime = 9999999999999999.0
    M.spfail = 0
    M.removetimer = 99999999.0
    M.processtime = 999999.0
    M.searchtime = 999999.0
    M.oneminstrans = 999999.0
    M.transaway = 999999.0
    M.platoonarrive = 999999.0
    M.fifteenminsplatoon = 999999.0
    M.tenminsplatoon = 999999.0
    M.threeminsplatoon = 999999.0
    M.twominsplatoon = 999999.0
    M.fiveminsplatoon = 999999.0
    M.opencamtime = 999999.0
    M.cam1time = 999999.0
    M.cam3time = 999999.0
    M.cam1hgt = 800
    M.wave1 = 999999.0
    M.wave2 = 999999.0
    M.wave3 = 999999.0
    M.start1 = 999999999.0
    M.lincolndestroyed = 999999.0
    M.patrol1start = math.random(0, 3)
    M.patrol2start = math.random(0, 3)
    M.patrol3start = math.random(0, 3)
    M.extractpoint = math.random(0, 3)
    M.patrol1time = 99999999.0
    M.patrol2time = 99999999.0
    M.patrol3time = 99999999.0
    M.check1 = 99999999.0
    M.time1 = 999999999.0
    M.hephdisctime = 9999999999.0
    M.identtime = 999999999.0
    M.timerstart = 999999999.0
    M.deathtime = 999999999999.0
    subtit.Initialize()
end

function AddObject(h)
    -- Native AddObject has no mission-specific behavior.
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
    if not CRCoop.IsAuthority() then return end
    if CRCoop.IsNetworkGame() and not M.coopBootstrapped then
        M.coopBootstrapped = true
        -- The authored offline placeholder must not remain beside the humans.
        local offlinePlayer = GetHandle("player0_hover")
        if IsValid(offlinePlayer) and not CRCoop.IsHumanCraft(offlinePlayer) then RemoveObject(offlinePlayer) end
    end
    -- Misn06Mission::Execute body (DLL order preserved below).
    --[=[ DLL source comment (inactive C++):
/*
		Here is where you 
		put what happens 
		every frame.  
	*/
    ]=]
    if M.missionstart == true then
        M.audmsg = subtit.Play("misn0601.wav")
        M.missionstart = false
        M.player = GetPlayerHandle()
        M.rendezvous = GetHandle("eggeizr1-1_geyser")
        SetObjectiveName(M.rendezvous, "5th Platoon")
        M.haephestus = GetHandle("obheph0_i76building")
        M.avrec = GetHandle("avrecy-1_recycler")
        M.svrec = GetHandle("svrecy-1_recycler")
        M.launchpad = GetHandle("sblpad0_i76building")
        M.wAu1 = GetHandle("svfigh568_wingman")
        M.wAu2 = GetHandle("svfigh566_wingman")
        M.turret = GetHandle("turret")
        --[=[ DLL source comment (inactive C++):
//wAu3 = GetHandle ("svfigh567_wingman");
        ]=]
        --[=[ Lua equivalent (disabled):
    M.wAu3 = GetHandle("svfigh567_wingman")
        ]=]
        --[=[ DLL source comment (inactive C++):
//star1 = GetHandle ("obstp34_i76building");
        ]=]
        --[=[ Lua equivalent (disabled):
    M.star1 = GetHandle("obstp34_i76building")
        ]=]
        M.star2 = GetHandle("obstp25_i76building")
        --[=[ DLL source comment (inactive C++):
//star4 = GetHandle ("obstp11_i76building");
        ]=]
        --[=[ Lua equivalent (disabled):
    M.star4 = GetHandle("obstp11_i76building")
        ]=]
        --[=[ DLL source comment (inactive C++):
//star5 = GetHandle ("obstp21_i76building");
        ]=]
        --[=[ Lua equivalent (disabled):
    M.star5 = GetHandle("obstp21_i76building")
        ]=]
        M.star6 = GetHandle("obstp10_i76building")
        --[=[ DLL source comment (inactive C++):
//star7 = GetHandle ("obstp23_i76building");
        ]=]
        --[=[ Lua equivalent (disabled):
    M.star7 = GetHandle("obstp23_i76building")
        ]=]
        M.star8 = GetHandle("obstp33_i76building")
        --[=[ DLL source comment (inactive C++):
//star9 = GetHandle ("obstp35_i76building");
        ]=]
        --[=[ Lua equivalent (disabled):
    M.star9 = GetHandle("obstp35_i76building")
        ]=]
        M.blockade1 = GetHandle("svturr649_turrettank")
        M.svu1 = GetHandle("svu1")
        M.svu2 = GetHandle("svu2")
        M.svu3 = GetHandle("svu3")
        M.svu4 = GetHandle("svu4")
        M.p5u3 = GetHandle("avtank13_wingman")
        M.p5u4 = GetHandle("avtank11_wingman")
        M.p5u6 = GetHandle("avtank12_wingman")
        M.p5u9 = GetHandle("avfigh7_wingman")
        M.p5u12 = GetHandle("avfigh10_wingman")
        M.patrol1time = GetTime() + 30.0
        M.patrol2time = GetTime() + 30.0
        M.patrol3time = GetTime() + 30.0
        SetObjectiveOn(M.rendezvous)
        AddObjective("misn0600.otf", "white")
        CameraReady()
        M.opencamtime = GetTime() + 28.0
        M.opencamdone = true
        M.newobjective = true
        SetScrap(1, 5)
        M.art1 = GetHandle("svartl648_howitzer")
        Defend(M.art1, 1)
        M.check1 = GetTime() + 20.0
    end
    M.player = GetPlayerHandle()
    AddHealth(M.star2, 1000)
    AddHealth(M.star6, 1000)
    AddHealth(M.star8, 1000)
    if M.trigger1 == false then
        M.trigger = NearestEnemy(M.turret)
        if (MissionDistance(M.trigger, M.turret) < 200.0) or (not IsAlive(M.turret)) then
            if M.patrol1set == false then
                if M.patrol1start == 0 then
                    M.pu1p1 = BuildObject("svfigh", ENEMY_TEAM, "pat1sp1")
                elseif M.patrol1start == 1 then
                    M.pu1p1 = BuildObject("svfigh", ENEMY_TEAM, "pat1sp2")
                elseif M.patrol1start == 2 then
                    M.pu1p1 = BuildObject("svtank", ENEMY_TEAM, "pat1sp3")
                elseif M.patrol1start == 3 then
                    M.pu1p1 = BuildObject("svfigh", ENEMY_TEAM, "pat1sp4")
                end
                M.patrol1set = true
            end
            if M.patrol2set == false then
                if M.patrol2start == 0 then
                    M.pu1p2 = BuildObject("svfigh", ENEMY_TEAM, "pat2sp1")
                elseif M.patrol2start == 1 then
                    M.pu1p2 = BuildObject("svfigh", ENEMY_TEAM, "pat2sp2")
                elseif M.patrol2start == 2 then
                    M.pu1p2 = BuildObject("svtank", ENEMY_TEAM, "pat2sp3")
                elseif M.patrol2start == 3 then
                    M.pu1p2 = BuildObject("svfigh", ENEMY_TEAM, "pat2sp4")
                end
                M.patrol2set = true
            end
            if M.patrol3set == false then
                if M.patrol3start == 0 then
                    M.pu1p3 = BuildObject("svfigh", ENEMY_TEAM, "pat3sp1")
                elseif M.patrol3start == 1 then
                    M.pu1p3 = BuildObject("svfigh", ENEMY_TEAM, "pat3sp2")
                elseif M.patrol3start == 2 then
                    M.pu1p3 = BuildObject("svtank", ENEMY_TEAM, "pat3sp3")
                elseif M.patrol3start == 3 then
                    M.pu1p3 = BuildObject("svfigh", ENEMY_TEAM, "pat3sp4")
                end
                M.patrol3set = true
            end
            if (M.patrol1set == true) and (M.startpat1 == false) then
                Patrol(M.pu1p1, "patrol1")
                M.startpat1 = true
            end
            if (M.patrol2set == true) and (M.startpat2 == false) then
                Patrol(M.pu1p2, "patrol2")
                M.startpat2 = true
            end
            if (M.patrol3set == true) and (M.startpat3 == false) then
                Patrol(M.pu1p3, "patrol3")
                M.startpat3 = true
            end
            if M.startpat4 == false then
                -- The DLL never sets this handle; preserve its native no-op.
        if IsValid(M.pu1p4) then Patrol(M.pu1p4, "patrol4") end
                -- The DLL never sets this handle; preserve its native no-op.
        if IsValid(M.pu2p4) then Patrol(M.pu2p4, "patrol4") end
                -- The DLL never sets this handle; preserve its native no-op.
        if IsValid(M.pu3p4) then Patrol(M.pu3p4, "patrol4") end
                M.startpat4 = true
            end
            M.trigger1 = true
        end
    end
    if M.trigger1 == true then
        if (M.patrol1time < GetTime()) and (M.patrol1spawned == false) then
            M.patrol1time = GetTime() + 2.0
            if (IsAlive(M.pu1p1)) and (EnemyWithin(M.pu1p1, 450.0)) then
                M.pu2p1 = BuildObject("svtank", ENEMY_TEAM, M.pu1p1)
                --[=[ DLL source comment (inactive C++):
//pu3p1 = BuildObject ("svtank",2, pu1p1);
                ]=]
                --[=[ Lua equivalent (disabled):
    M.pu3p1 = BuildObject("svtank", 2, M.pu1p1)
                ]=]
                --[=[ DLL source comment (inactive C++):
//pu4p1 = BuildObject ("svtank",2, pu1p1);
                ]=]
                --[=[ Lua equivalent (disabled):
    M.pu4p1 = BuildObject("svtank", 2, M.pu1p1)
                ]=]
                M.patrol1spawned = true
                Patrol(M.pu2p1, "patrol1")
            end
        end
        --[=[ DLL source comment (inactive C++):
//Patrol(pu3p1, "patrol1");
        ]=]
        --[=[ Lua equivalent (disabled):
    Patrol(M.pu3p1, "patrol1")
        ]=]
        --[=[ DLL source comment (inactive C++):
//Patrol(pu4p1, "patrol1");
        ]=]
        --[=[ Lua equivalent (disabled):
    Patrol(M.pu4p1, "patrol1")
        ]=]
        if (M.patrol2time < GetTime()) and (M.patrol2spawned == false) then
            M.patrol2time = GetTime() + 2.0
            --[=[ DLL source comment (inactive C++):
// added GEC, sometimes this guy is dead
            ]=]
            if (IsAlive(M.pu1p2)) and (EnemyWithin(M.pu1p2, 450.0)) then
                M.pu2p2 = BuildObject("svfigh", ENEMY_TEAM, M.pu1p2)
                --[=[ DLL source comment (inactive C++):
//pu3p2 = BuildObject ("svtank",2, pu1p2);
                ]=]
                --[=[ Lua equivalent (disabled):
    M.pu3p2 = BuildObject("svtank", 2, M.pu1p2)
                ]=]
                --[=[ DLL source comment (inactive C++):
//pu4p2 = BuildObject ("svtank",2, pu1p2);
                ]=]
                --[=[ Lua equivalent (disabled):
    M.pu4p2 = BuildObject("svtank", 2, M.pu1p2)
                ]=]
                M.patrol2spawned = true
                Patrol(M.pu2p2, "patrol2")
            end
        end
        --[=[ DLL source comment (inactive C++):
//Patrol(pu3p2, "patrol2");
        ]=]
        --[=[ Lua equivalent (disabled):
    Patrol(M.pu3p2, "patrol2")
        ]=]
        --[=[ DLL source comment (inactive C++):
//Patrol(pu4p2, "patrol2");
        ]=]
        --[=[ Lua equivalent (disabled):
    Patrol(M.pu4p2, "patrol2")
        ]=]
        if (M.patrol3time < GetTime()) and (M.patrol3spawned == false) then
            M.patrol3time = GetTime() + 2.0
            if EnemyWithin(M.pu1p3, 450.0) then
                M.pu2p3 = BuildObject("svfigh", ENEMY_TEAM, M.pu1p3)
                --[=[ DLL source comment (inactive C++):
//pu3p3 = BuildObject ("svtank",2, pu1p3);
                ]=]
                --[=[ Lua equivalent (disabled):
    M.pu3p3 = BuildObject("svtank", 2, M.pu1p3)
                ]=]
                --[=[ DLL source comment (inactive C++):
//pu4p3 = BuildObject ("svtank",2, pu1p3);
                ]=]
                --[=[ Lua equivalent (disabled):
    M.pu4p3 = BuildObject("svtank", 2, M.pu1p3)
                ]=]
                M.patrol3spawned = true
                Patrol(M.pu2p3, "patrol3")
            end
        end
    end
    --[=[ DLL source comment (inactive C++):
//Patrol(pu3p3, "patrol3");
    ]=]
    --[=[ Lua equivalent (disabled):
    Patrol(M.pu3p3, "patrol3")
    ]=]
    --[=[ DLL source comment (inactive C++):
//Patrol(pu4p3, "patrol3");
    ]=]
    --[=[ Lua equivalent (disabled):
    Patrol(M.pu4p3, "patrol3")
    ]=]
    if (not IsAlive(M.avrec)) and (M.missionfail1 == false) then
        M.aud20 = subtit.Play("misn0653.wav")
        M.aud21 = subtit.Queue("misn0651.wav")
        M.missionfail1 = true
    end
    if M.missionfail1 == true then
        if (AudioDone(M.aud20)) and (AudioDone(M.aud21)) then
            FailMission(GetTime(), "misn06l5.des")
        end
    end
    if M.opencamdone == true then
        CameraPath("openingcampath", 1000, 500, M.p5u3)
        AddHealth(M.p5u3, 50)
        AddHealth(M.p5u4, 50)
        AddHealth(M.p5u6, 50)
        AddHealth(M.p5u9, 50)
        AddHealth(M.p5u12, 50)
    end
    if (M.opencamdone == true) and ((M.opencamtime < GetTime()) or CameraCancelled()) then
        StopAudio(M.audmsg)
        M.audmsg = nil
        CameraFinish()
        M.opencamdone = false
        if IsAlive(M.svu1) then
            RemoveObject(M.svu1)
        end
        if IsAlive(M.svu2) then
            RemoveObject(M.svu2)
        end
        if IsAlive(M.svu3) then
            RemoveObject(M.svu3)
        end
        if IsAlive(M.svu4) then
            RemoveObject(M.svu4)
        end
        if IsAlive(M.p5u1) then
            RemoveObject(M.p5u1)
        end
        if IsAlive(M.p5u2) then
            RemoveObject(M.p5u2)
        end
        if IsAlive(M.p5u3) then
            RemoveObject(M.p5u3)
        end
        if IsAlive(M.p5u4) then
            RemoveObject(M.p5u4)
        end
        if IsAlive(M.p5u5) then
            RemoveObject(M.p5u5)
        end
        if IsAlive(M.p5u6) then
            RemoveObject(M.p5u6)
        end
        if IsAlive(M.p5u7) then
            RemoveObject(M.p5u7)
        end
        if IsAlive(M.p5u8) then
            RemoveObject(M.p5u8)
        end
        if IsAlive(M.p5u9) then
            RemoveObject(M.p5u9)
        end
        if IsAlive(M.p5u10) then
            RemoveObject(M.p5u10)
        end
        if IsAlive(M.p5u11) then
            RemoveObject(M.p5u11)
        end
        if IsAlive(M.p5u12) then
            RemoveObject(M.p5u12)
        end
    end
    if M.newobjective == true then
        ClearObjectives()
        if (M.bugout == true) and (M.missionwon == true) then
            AddObjective("misn0606.otf", "green")
            AddObjective("misn0605.otf", "green")
            AddObjective("misn0604.otf", "green")
        end
        --[=[ DLL source comment (inactive C++):
//AddObjective("misn0603.otf", GREEN);
        ]=]
        --[=[ Lua equivalent (disabled):
    AddObjective("misn0603.otf", "green")
        ]=]
        --[=[ DLL source comment (inactive C++):
//AddObjective("misn0602.otf", GREEN);
        ]=]
        --[=[ Lua equivalent (disabled):
    AddObjective("misn0602.otf", "green")
        ]=]
        --[=[ DLL source comment (inactive C++):
//AddObjective("misn0601.otf", GREEN);
        ]=]
        --[=[ Lua equivalent (disabled):
    AddObjective("misn0601.otf", "green")
        ]=]
        if (M.bugout == true) and (M.missionwon == false) then
            AddObjective("misn0606.otf", "white")
            AddObjective("misn0605.otf", "green")
            AddObjective("misn0604.otf", "green")
        end
        --[=[ DLL source comment (inactive C++):
//AddObjective("misn0603.otf", GREEN);
        ]=]
        --[=[ Lua equivalent (disabled):
    AddObjective("misn0603.otf", "green")
        ]=]
        --[=[ DLL source comment (inactive C++):
//AddObjective("misn0602.otf", GREEN);
        ]=]
        --[=[ Lua equivalent (disabled):
    AddObjective("misn0602.otf", "green")
        ]=]
        --[=[ DLL source comment (inactive C++):
//AddObjective("misn0601.otf", GREEN);
        ]=]
        --[=[ Lua equivalent (disabled):
    AddObjective("misn0601.otf", "green")
        ]=]
        if (M.lprecon == true) and (M.bugout == false) then
            AddObjective("misn0605.otf", "white")
            AddObjective("misn0604.otf", "green")
        end
        --[=[ DLL source comment (inactive C++):
//AddObjective("misn0603.otf", GREEN);
        ]=]
        --[=[ Lua equivalent (disabled):
    AddObjective("misn0603.otf", "green")
        ]=]
        --[=[ DLL source comment (inactive C++):
//AddObjective("misn0602.otf", GREEN);
        ]=]
        --[=[ Lua equivalent (disabled):
    AddObjective("misn0602.otf", "green")
        ]=]
        --[=[ DLL source comment (inactive C++):
//AddObjective("misn0601.otf", GREEN);
        ]=]
        --[=[ Lua equivalent (disabled):
    AddObjective("misn0601.otf", "green")
        ]=]
        --[=[ DLL source comment (inactive C++):
/*if
		(
		(transarrive == true) && (lprecon == false)
		)
	{
		AddObjective("misn0607.otf", WHITE);
		AddObjective("misn0604.otf", GREEN);
		//AddObjective("misn0603.otf", GREEN);
		//AddObjective("misn0602.otf", GREEN);
		//AddObjective("misn0601.otf", GREEN);
	}*/
        ]=]
        --[=[ Lua equivalent (disabled):
    if (M.transarrive == true) and (M.lprecon == false) then
        AddObjective("misn0607.otf", "white")
        AddObjective("misn0604.otf", "green")
    end
        ]=]
        if (M.starportreconed == true) and (M.transarrive == false) and (M.safebreak == false) then
            AddObjective("misn0604.otf", "white")
        end
        --[=[ DLL source comment (inactive C++):
//AddObjective("misn0603.otf", GREEN);
        ]=]
        --[=[ Lua equivalent (disabled):
    AddObjective("misn0603.otf", "green")
        ]=]
        --[=[ DLL source comment (inactive C++):
//AddObjective("misn0602.otf", GREEN);
        ]=]
        --[=[ Lua equivalent (disabled):
    AddObjective("misn0602.otf", "green")
        ]=]
        --[=[ DLL source comment (inactive C++):
//AddObjective("misn0601.otf", GREEN);
        ]=]
        --[=[ Lua equivalent (disabled):
    AddObjective("misn0601.otf", "green")
        ]=]
        if (M.neworders == true) and (M.starportreconed == false) then
            AddObjective("misn0603.otf", "white")
            AddObjective("misn0602.otf", "green")
            AddObjective("misn0601.otf", "green")
        end
        if (M.reconheaphestus == true) and (M.neworders == false) then
            AddObjective("misn0602.otf", "white")
            AddObjective("misn0601.otf", "green")
        end
        if (M.haephestusdisc == true) and (M.reconheaphestus == false) and (M.hephikey == false) then
            AddObjective("misn0601.otf", "white")
        end
        if M.fifthplatoon == true then
            AddObjective("misn0600.otf", "white")
        end
        M.newobjective = false
    end
    if (M.haephestusdisc == false) and (AnyPlayerWithin(M.haephestus, 1000.0)) then
        M.aud1 = subtit.Play("misn0602.wav")
        M.haephestusdisc = true
        M.hephdisctime = GetTime() + 60.0
    end
    if (M.loopbreaker == false) and (M.haephestusdisc == true) and (AudioDone(M.aud1)) then
        SetObjectiveOn(M.haephestus)
        SetObjectiveName(M.haephestus, "Object")
        M.newobjective = true
        M.loopbreaker = true
    end
    if (M.haephestusdisc == true) and (M.reconheaphestus == false) and (M.hephikey == false) and (M.hephdisctime < GetTime()) and (M.hephwarn < 2) then
        subtit.Play("misn0690.wav")
        M.hephdisctime = GetTime() + 20.0
        M.hephwarn = M.hephwarn + 1
    end
    if (M.hephwarn == 2) and (M.missionfail4 == false) and (M.hephdisctime < GetTime()) then
        M.aud105 = subtit.Play("misn0694.wav")
        M.missionfail4 = true
    end
    if (M.missionfail4 == true) and (AudioDone(M.aud105)) then
        FailMission(GetTime() + 0.0, "misn06l1.des")
    end
    if (M.reconheaphestus == false) and (AnyPlayerWithin(M.haephestus, 125.0)) and (M.hephikey == false) then
        M.heph1 = subtit.Play("misn0603.wav")
        M.heph2 = subtit.Queue("misn0604.wav")
        M.reconheaphestus = true
        SetObjectiveOff(M.haephestus)
        CameraReady()
        M.cam1time = GetTime() + 12.0
        M.cam1done = true
        M.identtime = GetTime() + 20.0
    end
    if (M.identtime < GetTime()) and (M.hephikey == false) and (M.ident < 2) then
        subtit.Play("misn0691.wav")
        M.ident = M.ident + 1
        M.identtime = GetTime() + 10.0
    end
    if (M.ident == 2) and (M.identtime < GetTime()) and (M.hephikey == false) and (M.missionfail == false) then
        M.aud100 = subtit.Play("misn0694.wav")
        M.missionfail = true
    end
    if (M.missionfail == true) and (AudioDone(M.aud100)) then
        FailMission(GetTime() + 0.0, "misn06l2.des")
    end
    if (IsInfo("obheph") == true) and (M.hephikey == false) then
        M.processtime = GetTime() + 5.0
        M.hephikey = true
-- CR restored VO >>
        if RESTORED_VO then M.aud610 = subtit.Play(CUT_VO.hephestus) end
-- CR restored VO <<
        M.reconheaphestus = true
        SetObjectiveOff(M.haephestus)
        M.newobjective = true
    end
-- CR restored VO >>
    if not (RESTORED_VO and not AudioDone(M.aud610)) then
-- CR restored VO <<
    if (M.neworders == false) and (M.processtime < GetTime()) then
        M.aud2 = subtit.Play("misn0605.wav")
        --[=[ DLL source comment (inactive C++):
//AudioMessage ("misn0606.wav");
        ]=]
        --[=[ Lua equivalent (disabled):
    AudioMessage("misn0606.wav")
        ]=]
        --[=[ DLL source comment (inactive C++):
//AudioMessage ("misn0607.wav");
        ]=]
        --[=[ Lua equivalent (disabled):
    AudioMessage("misn0607.wav")
        ]=]
        M.fifthplatoon = false
        M.neworders = true
        M.buildcam = true
        M.discstar = GetTime() + 80.0
    end
-- CR restored VO >>
    end
-- CR restored VO <<
    if (M.buildcam == true) and (AudioDone(M.aud2)) then
        SetObjectiveOff(M.rendezvous)
        M.starportcam = BuildObject("apcamr", 1, "cam1spawn")
        SetObjectiveName(M.starportcam, "Starport")
        M.buildcam = false
        M.newobjective = true
    end
    if (AnyPlayerWithin(M.blockade1, 420.0)) and (M.blockadefound == false) then
-- CR restored VO >>
        if RESTORED_VO then M.aud636 = subtit.Play("misn0636.wav") else
-- CR restored VO <<
        subtit.Play("misn0636.wav")
-- CR restored VO >>
        end
-- CR restored VO <<
        M.blockadefound = true
    end
-- CR restored VO >>
    if RESTORED_VO and M.blockadefound == true and M.vo609 == false and AudioDone(M.aud636) and NoPlayerEnemyWithin(300.0) then
        M.vo609 = true
        subtit.Play(CUT_VO.blockade)
    end
-- CR restored VO <<
    if (IsInfo("obstp1") == true) and (M.star1recon == false) then
        M.star1recon = true
    end
    if (IsInfo("obstp8") == true) and (M.star4recon == false) then
        M.star4recon = true
    end
    if (IsInfo("obstp3") == true) and (M.star6recon == false) then
        M.star6recon = true
    end
    if (M.fail3 == false) and (M.spfail == 4) then
        M.fail3 = true
        M.aud54 = subtit.Play("misn0694.wav")
    end
    if M.fail3 == true then
        if AudioDone(M.aud54) then
            FailMission(GetTime() + 0.0, "misn06l6.des")
        end
    end
    if (M.starportreconed == false) and (M.reconsptime < GetTime()) and (M.fail3 == false) and (M.spfail < 4) then
-- CR restored VO >>
        if RESTORED_VO and M.spfail == 0 then subtit.Play(CUT_VO.firstReminder) else
-- CR restored VO <<
        subtit.Play("misn0654.wav")
-- CR restored VO >>
        end
-- CR restored VO <<
        M.reconsptime = GetTime() + 15.0
        M.spfail = M.spfail + 1
    end
    if (M.star1recon == true) and (M.star4recon == true) and (M.star6recon == true) and (M.starportreconed == false) then
        M.aud3 = subtit.Play("misn0650.wav")
        M.aud4 = subtit.Queue("misn0606.wav")
        M.aud5 = subtit.Queue("misn0607.wav")
        M.starportreconed = true
        M.start1 = GetTime() + 15.0
    end
    if (M.star == false) and (M.starportreconed == true) and (AudioDone(M.aud3)) and (AudioDone(M.aud4)) and (AudioDone(M.aud5)) then
        M.newobjective = true
        M.star = true
    end
    if (M.starportdisc == false) and (AnyPlayerWithin(M.star8, 200.0)) then
        subtit.Play("misn0608.wav")
        M.searchtime = GetTime() + 15.0
        M.starportdisc = true
        M.reconsptime = GetTime() + 20.0
    end
    if (M.neworders == true) and (M.starportdisc == false) and (M.discstar < GetTime()) and (M.stardisc < 3) then
        subtit.Play("misn0695.wav")
        M.discstar = GetTime() + 40.0
        M.stardisc = M.stardisc + 1
    end
    if (M.stardisc == 3) and (M.discstar < GetTime()) and (M.missionfail3 == false) then
        M.missionfail3 = true
        M.aud101 = subtit.Play("misn0694.wav")
    end
    if (M.missionfail3 == true) and (AudioDone(M.aud101)) then
        FailMission(GetTime() + 0.0, "misn06l3.des")
    end
    if (M.ccaattack == false) and (M.check1 < GetTime()) then
        M.enemy = NearestEnemy(M.wAu1)
        if MissionDistance(M.enemy, M.wAu1) < 410.0 then
            Attack(M.wAu1, M.enemy)
            Attack(M.wAu2, M.enemy)
            --[=[ DLL source comment (inactive C++):
//Attack (wAu3, enemy);
            ]=]
            --[=[ Lua equivalent (disabled):
    Attack(M.wAu3, M.enemy)
            ]=]
            SetIndependence(M.wAu2, 1)
            --[=[ DLL source comment (inactive C++):
//SetIndependence(wAu3, 1);
            ]=]
            --[=[ Lua equivalent (disabled):
    SetIndependence(M.wAu3, 1)
            ]=]
            M.ccaattack = true
            M.start1 = GetTime() - 1
        end
        M.check1 = GetTime() + 1.5
    end
    if (M.starportreconed == true) and (M.ccaattack == false) then
        Attack(M.wAu1, NearestPlayer(M.wAu1))
        Attack(M.wAu2, NearestPlayer(M.wAu2))
        --[=[ DLL source comment (inactive C++):
//Attack (wAu3, player);
        ]=]
        --[=[ Lua equivalent (disabled):
    Attack(M.wAu3, M.player)
        ]=]
        SetIndependence(M.wAu1, 1)
        SetIndependence(M.wAu2, 1)
        --[=[ DLL source comment (inactive C++):
//SetIndependence(wAu3, 1);
        ]=]
        --[=[ Lua equivalent (disabled):
    SetIndependence(M.wAu3, 1)
        ]=]
        M.ccaattack = true
    end
    if ((MissionDistance(M.wAu1, "cam1spawn") < 400.0) or (MissionDistance(M.wAu2, "cam1spawn") < 400.0)) and (M.ccaattack == true) and (M.loopbreak1 == false) and (M.start1 < GetTime()) and (AudioDone(M.aud5)) then
        --[=[ DLL source comment (inactive C++):
//||
        ]=]
        --[=[ DLL source comment (inactive C++):
//(GetDistance (wAu3, "cam1spawn") < 400.0f)
        ]=]
        M.aud500 = subtit.Play("misn0611.wav")
        CameraReady()
        M.cam3time = GetTime() + 5.0
        M.cam3done = true
        M.ccaattack = false
        M.loopbreak1 = true
    end
    if M.cam1done == true then
        CameraPath("cam1path", M.cam1hgt, 1000, M.haephestus)
        M.cam1hgt = M.cam1hgt + 15
    end
    if M.cam1done == true then
        if ((AudioDone(M.heph1)) and (AudioDone(M.heph2))) or (CameraCancelled()) then
            CameraFinish()
            M.cam1done = false
            StopAudio(M.heph1)
            StopAudio(M.heph2)
            M.newobjective = true
        end
    end
    if M.cam3done == true then
        CameraObject(M.wAu1, 300, 100, - 900, M.wAu1)
    end
    if ((M.cam3done == true) and (AudioDone(M.aud500))) or (CameraCancelled()) then
        CameraFinish()
        M.cam3done = false
    end
    if M.ccapullout == false then
        IsAlive(M.wAu1)
        IsAlive(M.wAu1)
    end
    if (not IsAlive(M.wAu1)) and (not IsAlive(M.wAu2)) and (M.ccapullout == false) and (M.starportreconed == true) then
        --[=[ DLL source comment (inactive C++):
//&& (!IsAlive (wAu3))
        ]=]
        M.aud15 = subtit.Play("misn0612.wav")
        M.aud16 = subtit.Queue("misn0613.wav")
        M.transportarrive = GetTime() + 50.0
        M.transarrive = true
        M.safebreak = true
        M.ccapullout = true
        M.wave1 = GetTime() + 60.0
        M.wave2 = GetTime() + 180.0
        M.wave3 = GetTime() + 300.0
    end
    if (M.breaker19 == false) and (M.ccapullout == true) and (AudioDone(M.aud15)) and (AudioDone(M.aud16)) then
        --[=[ DLL source comment (inactive C++):
//newobjective = true;
        ]=]
        --[=[ Lua equivalent (disabled):
    M.newobjective = true
        ]=]
        M.breaker19 = true
    end
-- CR restored VO >>
    if RESTORED_VO and M.vob1 == false and M.ccapullout == true and AudioDone(M.aud15) and AudioDone(M.aud16) then
        M.vob1 = true
        if M.touchdown == false then
            subtit.Play(CUT_VO.touchdown)
            subtit.Queue(CUT_VO.collins)
            subtit.Queue(CUT_VO.yessir)
        end
    end
-- CR restored VO <<
    if (M.wave1 < GetTime()) and (M.wave1start == false) and (IsAlive(M.svrec)) then
        M.w1u1 = BuildObject("svfigh", ENEMY_TEAM, M.svrec)
        M.w1u2 = BuildObject("svtank", ENEMY_TEAM, M.svrec)
        M.w1u3 = BuildObject("svfigh", ENEMY_TEAM, M.svrec)
        Attack(M.w1u1, M.avrec)
        Attack(M.w1u2, M.avrec)
        Attack(M.w1u3, M.avrec)
        SetIndependence(M.w1u1, 1)
        SetIndependence(M.w1u2, 1)
        SetIndependence(M.w1u3, 1)
        M.wave1start = true
    end
    if (M.wave2 < GetTime()) and (M.wave2start == false) and (IsAlive(M.svrec)) then
        M.w2u1 = BuildObject("svfigh", ENEMY_TEAM, M.svrec)
        M.w2u2 = BuildObject("svtank", ENEMY_TEAM, M.svrec)
        M.w2u3 = BuildObject("svfigh", ENEMY_TEAM, M.svrec)
        Attack(M.w2u1, M.avrec)
        Attack(M.w2u2, M.avrec)
        Attack(M.w2u3, M.avrec)
        SetIndependence(M.w2u1, 1)
        SetIndependence(M.w2u2, 1)
        SetIndependence(M.w2u3, 1)
        M.wave2start = true
    end
    if (M.wave3 < GetTime()) and (M.wave3start == false) and (IsAlive(M.svrec)) then
        M.w3u1 = BuildObject("svfigh", ENEMY_TEAM, M.svrec)
        M.w3u2 = BuildObject("svtank", ENEMY_TEAM, M.svrec)
        M.w3u3 = BuildObject("svfigh", ENEMY_TEAM, M.svrec)
        Attack(M.w3u1, M.avrec)
        Attack(M.w3u2, M.avrec)
        Attack(M.w3u3, M.avrec)
        SetIndependence(M.w3u1, 1)
        SetIndependence(M.w3u2, 1)
        SetIndependence(M.w3u3, 1)
        M.wave3start = true
    end
    if (M.transportarrive < GetTime()) and (M.transarrive == true) then
-- CR restored VO >>
        if RESTORED_VO then
            M.aud6 = subtit.Play("misn0614.wav")
            subtit.Queue(CUT_VO.b2a)
            subtit.Queue(CUT_VO.b2b)
            subtit.Queue(CUT_VO.b2c)
            subtit.Queue(CUT_VO.b2d)
            M.aud7 = subtit.Queue(CUT_VO.b2e)
            M.vob3choice = (math.random(2) == 1) and CUT_VO.b3c1 or CUT_VO.b3c2
        else
-- CR restored VO <<
        M.aud6 = subtit.Play("misn0614.wav")
        M.aud7 = subtit.Queue("misn0628.wav")
-- CR restored VO >>
        end
-- CR restored VO <<
        M.lincolndestroyed = GetTime() + 60.0
        M.oneminstrans = GetTime() + 60.0
        M.transaway = GetTime() + 90.0
        M.platoonarrive = GetTime() + 1410.0
        M.threeminsplatoon = GetTime() + 390.0
        M.tenminsplatoon = GetTime() + 810.0
        M.fiveminsplatoon = GetTime() + 1110.0
        M.twominsplatoon = GetTime() + 1260.0
        M.transarrive = false
        M.touchdown = true
        M.threemin = true
        M.tenmin = true
        M.fivemin = true
        M.twomin = true
        M.platoonhere = true
        M.newobjective = true
        M.timerstart = GetTime() + 27.42
        M.lincolndes = true
    end
    --[=[ DLL source comment (inactive C++):
/*if 
		(
		(lincolndestroyed < GetTime()) && (lincolndes == false)
		)
	{
		aud8 = AudioMessage ("misn0626.wav");
		aud9 = AudioMessage ("misn0628.wav");
		lincolndes = true;
	}*/
    ]=]
    --[=[ Lua equivalent (disabled):
    if (M.lincolndestroyed < GetTime()) and (M.lincolndes == false) then
        M.aud8 = AudioMessage("misn0626.wav")
        M.aud9 = AudioMessage("misn0628.wav")
        M.lincolndes = true
    end
    ]=]
    if (M.lprecon == false) and (M.lincolndes == true) then
        if (AudioDone(M.aud6)) and (AudioDone(M.aud7)) then
            M.lprecon = true
            StartCockpitTimer(540.0, 362.0, 180.0)
            SetObjectiveOn(M.launchpad)
            M.newobjective = true
        end
    end
-- CR restored VO >>
    if RESTORED_VO and M.vob3 == false and M.oneminstrans < GetTime() then
        M.vob3 = true
        if M.launchpadreconed == false and M.bugout == false then
            M.vob3played = true
            subtit.Play(M.vob3choice or CUT_VO.b3c1)
            subtit.Queue(CUT_VO.b3a)
            M.vob3h = subtit.Queue(CUT_VO.b3b)
        end
    end
    if RESTORED_VO and M.vob3 == true and M.vob4 == false and M.transaway < GetTime() then
        if M.vob3played == false then
            M.vob4 = true
        elseif AudioDone(M.vob3h) then
            M.vob4 = true
            if M.launchpadreconed == false and M.bugout == false then
                M.vob4played = true
                subtit.Play(CUT_VO.b4a)
                M.vob4h = subtit.Queue(CUT_VO.b4b)
            end
        end
    end
    if RESTORED_VO and M.vob4played == true and M.vob5 == false and AudioDone(M.vob4h) then
        M.vob5 = true
        subtit.Play(CUT_VO.b5)
        if M.launchpadreconed == false then subtit.Queue(CUT_VO.late628) end
    end
-- CR restored VO <<
    if (M.threeminsplatoon < GetTime()) and (M.threemin == true) and (M.launchpadreconed == false) then
        M.bogey = NearestEnemy(M.player)
        if NoPlayerEnemyWithin(400.0) then
            M.sim1 = BuildObject("avtank", SUPPORT_TEAM, "sim1")
            M.sim2 = BuildObject("avtank", SUPPORT_TEAM, "sim2")
            M.sim3 = BuildObject("avtank", SUPPORT_TEAM, "sim3")
            M.sim4 = BuildObject("avtank", SUPPORT_TEAM, "sim4")
            M.sim5 = BuildObject("avtank", SUPPORT_TEAM, "sim5")
            M.sim6 = BuildObject("avfigh", SUPPORT_TEAM, "sim6")
            M.sim7 = BuildObject("avfigh", SUPPORT_TEAM, "sim7")
            M.sim8 = BuildObject("avfigh", SUPPORT_TEAM, "sim8")
            M.sim9 = BuildObject("avfigh", SUPPORT_TEAM, "sim9")
            M.sim10 = BuildObject("avfigh", SUPPORT_TEAM, "sim10")
            --[=[ DLL source comment (inactive C++):
/*
			Jens
			this cineractive now
			works except that there is
			no path point called
			sim5spot
			So they don't move.
		*/
            ]=]
            Goto(M.sim1, "simpoint5")
            Goto(M.sim2, "simpoint5")
            Goto(M.sim3, "simpoint5")
            Goto(M.sim4, "simpoint5")
            Goto(M.sim5, "simpoint5")
            Goto(M.sim6, "simpoint5")
            Goto(M.sim7, "simpoint5")
            Goto(M.sim8, "simpoint5")
            Goto(M.sim9, "simpoint5")
            Goto(M.sim10, "simpoint5")
            CameraReady()
            M.simaud1 = subtit.Play("misn0631.wav")
            M.simaud2 = subtit.Queue("misn0642.wav")
            M.simaud3 = subtit.Queue("misn0643.wav")
            M.simaud4 = subtit.Queue("misn0644.wav")
            M.simaud5 = subtit.Queue("misn0645.wav")
            M.simcam = true
            M.threemin = false
            HideCockpitTimer()
        end
    end
    if M.simcam == true then
        CameraObject(M.sim5, 0, 1000, - 4000, M.sim5)
        if (M.attack == false) and (AudioDone(M.simaud4)) then
            Goto(M.sim1, "simpoint1")
            Goto(M.sim2, "simpoint1")
            Goto(M.sim4, "simpoint1")
            Goto(M.sim7, "simpoint1")
            Goto(M.sim3, "simpoint3")
            Goto(M.sim6, "simpoint3")
            Goto(M.sim10, "simpoint3")
            Goto(M.sim5, "simpoint5")
            Goto(M.sim8, "simpoint5")
            Goto(M.sim9, "simpoint5")
            M.attack = true
        end
    end
    if (M.simcam == true) and (M.breakout1 == false) then
        if AudioDone(M.simaud1) then
            M.doneaud1 = true
        end
        if AudioDone(M.simaud2) then
            M.doneaud2 = true
        end
        if AudioDone(M.simaud3) then
            M.doneaud3 = true
        end
        if AudioDone(M.simaud4) then
            M.doneaud4 = true
        end
        if AudioDone(M.simaud5) then
            M.doneaud5 = true
        end
        if ((M.doneaud1) and (M.doneaud2) and (M.doneaud3) and (M.doneaud4) and (M.doneaud5)) or (CameraCancelled()) then
            CameraFinish()
            M.breakout1 = true
            M.simcam = false
            StopAudio(M.simaud1)
            StopAudio(M.simaud2)
            StopAudio(M.simaud3)
            StopAudio(M.simaud4)
            StopAudio(M.simaud5)
        end
    end
    --[=[ DLL source comment (inactive C++):
// this used to be breakout =, changed it to == so cineractive wouldn't last eternity
    ]=]
    if (M.breakout1 == true) and (M.removal == false) then
        RemoveObject(M.sim1)
        RemoveObject(M.sim2)
        RemoveObject(M.sim3)
        RemoveObject(M.sim4)
        RemoveObject(M.sim5)
        RemoveObject(M.sim6)
        RemoveObject(M.sim7)
        RemoveObject(M.sim8)
        RemoveObject(M.sim9)
        RemoveObject(M.sim10)
        M.removal = true
        StopCockpitTimer()
        HideCockpitTimer()
    end
    --[=[ DLL source comment (inactive C++):
/*if
		(
		(removal == true) && (timergone == false)
		)
	{
		StopCockpitTimer();
		timergone = true;
	}*/
    ]=]
    --[=[ Lua equivalent (disabled):
    if (M.removal == true) and (M.timergone == false) then
        StopCockpitTimer()
        M.timergone = true
    end
    ]=]
    if (M.tenminsplatoon < GetTime()) and (M.tenmin == true) and (M.launchpadreconed == false) and (M.reminder == false) then
        subtit.Play("misn0632.wav")
        M.tenmin = false
    end
    if (M.fiveminsplatoon < GetTime()) and (M.fivemin == true) and (M.launchpadreconed == false) and (M.reminder == false) then
        subtit.Play("misn0633.wav")
        M.fivemin = false
    end
    if (M.twominsplatoon < GetTime()) and (M.twomin == true) and (M.launchpadreconed == false) and (M.reminder == false) then
        subtit.Play("misn0634.wav")
        M.twomin = false
    end
    if (AnyPlayerWithin(M.svrec, 250.0)) and (M.reminder == false) and (M.launchpadreconed == false) then
        subtit.Play("misn0638.wav")
        M.reminder = true
        M.endtime = GetTime() + 120.0
    end
    if (M.reminder == true) and (NoPlayerWithin(M.launchpad, 400.0)) and (M.launchpadreconed == false) and (M.endtime < GetTime()) and (M.breaker == false) then
        M.aud102 = subtit.Play("misn0635.wav")
        M.aud103 = subtit.Queue("misn0646.wav")
        M.aud104 = subtit.Queue("misn0651.wav")
        M.platoonhere = false
        M.endme = true
        M.breaker = true
    end
    if (IsInfo("sblpad") == true) and (M.launchpadreconed == false) then
        M.time1 = GetTime() + 2.0
        M.bugout = true
        M.launchpadreconed = true
        HideCockpitTimer()
        SetObjectiveOff(M.launchpad)
    end
    --[=[ DLL source comment (inactive C++):
//newobjective = true;
    ]=]
    --[=[ Lua equivalent (disabled):
    M.newobjective = true
    ]=]
    if (M.bugout == true) and (M.corbettalive == true) and (M.time1 < GetTime()) and (M.threemin == true) and (M.bustout == false) then
        subtit.Play("misn0629.wav")
        subtit.Queue("misn0630.wav")
        subtit.Queue("misn0647.wav")
        M.ccap1 = BuildObject("svfigh", ENEMY_TEAM, "ccaplatoonspawn")
        Attack(M.ccap1, M.avrec)
        SetIndependence(M.ccap1, 1)
        --[=[ DLL source comment (inactive C++):
//bugout = false;
        ]=]
        --[=[ Lua equivalent (disabled):
    M.bugout = false
        ]=]
        M.platoonhere = false
        M.pickupset = true
        M.platoonarrive = 999999999999.0
        M.twominsplatoon = 999999999999.0
        M.tenminsplatoon = 999999999999.0
        M.fiveminsplatoon = 999999999999.0
        M.newobjective = true
        M.bustout = true
    end
    if (M.bugout == true) and (M.corbettalive == true) and (M.time1 < GetTime()) and (M.threemin == false) and (M.bustout == false) then
        subtit.Play("misn0629.wav")
        subtit.Queue("misn0630.wav")
        --[=[ DLL source comment (inactive C++):
//AudioMessage ("misn0647.wav");
        ]=]
        --[=[ Lua equivalent (disabled):
    AudioMessage("misn0647.wav")
        ]=]
        M.ccap1 = BuildObject("svfigh", ENEMY_TEAM, "ccaplatoonspawn")
        Attack(M.ccap1, M.avrec)
        SetIndependence(M.ccap1, 1)
        --[=[ DLL source comment (inactive C++):
//bugout = false;
        ]=]
        --[=[ Lua equivalent (disabled):
    M.bugout = false
        ]=]
        M.platoonhere = false
        M.pickupset = true
        M.platoonarrive = 999999999999.0
        M.twominsplatoon = 999999999999.0
        M.tenminsplatoon = 999999999999.0
        M.fiveminsplatoon = 999999999999.0
        M.newobjective = true
        M.bustout = true
    end
    if (M.breakme == false) and (M.bugout == true) and (M.corbettalive == false) and (M.time1 < GetTime()) then
-- CR restored VO >>
        if RESTORED_VO then subtit.Play(CUT_VO.lateCorbett) else
-- CR restored VO <<
        subtit.Play("misn0629.wav")
        subtit.Queue("misn0630.wav")
-- CR restored VO >>
        end
-- CR restored VO <<
        SetIndependence(M.ccap1, 1)
        M.platoonhere = false
        M.breakme = true
        M.pickupset = true
        M.platoonarrive = 999999999999.0
        M.twominsplatoon = 999999999999.0
        M.tenminsplatoon = 999999999999.0
        M.fiveminsplatoon = 999999999999.0
        M.newobjective = true
        M.deathtime = GetTime() + 30.0
    end
    if (M.deathtime < GetTime()) and (M.death == false) then
        M.death = true
        M.deathtime = 99999999999999.0
        subtit.Play("misn0635.wav")
        M.ccap1 = BuildObject("svfigh", ENEMY_TEAM, "ccaplatoonspawn")
        Attack(M.ccap1, M.avrec)
    end
    if M.pickupset == true then
        if M.extractpoint == 0 then
            M.dustoffcam = BuildObject("apcamr", 1, "bugout1")
        elseif M.extractpoint == 1 then
            M.dustoffcam = BuildObject("apcamr", 1, "bugout2")
        elseif M.extractpoint == 2 then
            M.dustoffcam = BuildObject("apcamr", 1, "bugout3")
        elseif M.extractpoint == 3 then
            M.dustoffcam = BuildObject("apcamr", 1, "bugout4")
        end
        SetObjectiveName(M.dustoffcam, "Dust Off")
        M.pickupset = false
        M.pickupreached = true
        SetObjectiveOff(M.launchpad)
    end
    if (M.bustout == true) and (not IsAlive(M.dustoffcam)) then
        M.pickupset = true
    end
    if (MissionDistance(M.avrec, M.dustoffcam) < 100.0) and (AllPlayersWithin(M.dustoffcam, 100.0)) and (M.pickupreached == true) then
-- CR restored VO >>
        if RESTORED_VO and M.corbettalive == false then subtit.Play(CUT_VO.lateSuccess) else
-- CR restored VO <<
        subtit.Play("misn0649.wav")
-- CR restored VO >>
        end
-- CR restored VO <<
        SucceedMission(GetTime() + 5.0, "misn06w1.des")
        M.pickupreached = false
        M.dustoff = true
        M.newobjective = true
    end
    if (M.platoonarrive < GetTime()) and (M.platoonhere == true) and (M.reminder == true) and (M.time1 < GetTime()) then
        subtit.Play("misn0635.wav")
        subtit.Queue("misn0648.wav")
        M.ccap1 = BuildObject("svfigh", ENEMY_TEAM, "ccaplatoonspawn")
        Attack(M.ccap1, M.avrec)
        SetIndependence(M.ccap1, 1)
        M.platoonhere = false
        M.twominsplatoon = 999999999999.0
        M.corbettalive = false
    end
    if IsAlive(M.ccap1) then
        M.spawnme = NearestEnemy(M.ccap1)
    end
    if (MissionDistance(M.ccap1, M.spawnme) < 410) and (M.economyccaplatoon == false) then
        M.ccap2 = BuildObject("svfigh", ENEMY_TEAM, M.ccap1)
        M.ccap3 = BuildObject("svfigh", ENEMY_TEAM, M.ccap1)
        M.ccap4 = BuildObject("svfigh", ENEMY_TEAM, M.ccap1)
        M.ccap5 = BuildObject("svfigh", ENEMY_TEAM, M.ccap1)
        M.ccap6 = BuildObject("svtank", ENEMY_TEAM, M.ccap1)
        M.ccap7 = BuildObject("svtank", ENEMY_TEAM, M.ccap1)
        M.ccap8 = BuildObject("svtank", ENEMY_TEAM, M.ccap1)
        M.ccap9 = BuildObject("svtank", ENEMY_TEAM, M.ccap1)
        --[=[ DLL source comment (inactive C++):
//ccap10 = BuildObject ("svtank",2,ccap1);
        ]=]
        --[=[ Lua equivalent (disabled):
    M.ccap10 = BuildObject("svtank", 2, M.ccap1)
        ]=]
        --[=[ DLL source comment (inactive C++):
//ccap11 = BuildObject ("svtank",2,ccap1);
        ]=]
        --[=[ Lua equivalent (disabled):
    M.ccap11 = BuildObject("svtank", 2, M.ccap1)
        ]=]
        --[=[ DLL source comment (inactive C++):
//ccap12 = BuildObject ("svturr",2,ccap1);
        ]=]
        --[=[ Lua equivalent (disabled):
    M.ccap12 = BuildObject("svturr", 2, M.ccap1)
        ]=]
        --[=[ DLL source comment (inactive C++):
//ccap13 = BuildObject ("svturr",2,ccap1);
        ]=]
        --[=[ Lua equivalent (disabled):
    M.ccap13 = BuildObject("svturr", 2, M.ccap1)
        ]=]
        --[=[ DLL source comment (inactive C++):
//ccap14 = BuildObject ("svartl",2,ccap1);
        ]=]
        --[=[ Lua equivalent (disabled):
    M.ccap14 = BuildObject("svartl", 2, M.ccap1)
        ]=]
        --[=[ DLL source comment (inactive C++):
//ccap15 = BuildObject ("svartl",2,ccap1);
        ]=]
        --[=[ Lua equivalent (disabled):
    M.ccap15 = BuildObject("svartl", 2, M.ccap1)
        ]=]
        Attack(M.ccap2, M.avrec)
        Attack(M.ccap3, M.avrec)
        Attack(M.ccap4, M.avrec)
        Attack(M.ccap5, M.avrec)
        Attack(M.ccap6, M.avrec)
        Attack(M.ccap7, M.avrec)
        Attack(M.ccap8, M.avrec)
        Attack(M.ccap9, M.avrec)
        --[=[ DLL source comment (inactive C++):
//Attack (ccap10, avrec);
        ]=]
        --[=[ Lua equivalent (disabled):
    Attack(M.ccap10, M.avrec)
        ]=]
        --[=[ DLL source comment (inactive C++):
//Attack (ccap11, avrec);
        ]=]
        --[=[ Lua equivalent (disabled):
    Attack(M.ccap11, M.avrec)
        ]=]
        --[=[ DLL source comment (inactive C++):
//Attack (ccap12, avrec);
        ]=]
        --[=[ Lua equivalent (disabled):
    Attack(M.ccap12, M.avrec)
        ]=]
        --[=[ DLL source comment (inactive C++):
//Attack (ccap13, avrec);
        ]=]
        --[=[ Lua equivalent (disabled):
    Attack(M.ccap13, M.avrec)
        ]=]
        --[=[ DLL source comment (inactive C++):
//Attack (ccap14, avrec);
        ]=]
        --[=[ Lua equivalent (disabled):
    Attack(M.ccap14, M.avrec)
        ]=]
        --[=[ DLL source comment (inactive C++):
//Attack (ccap15, avrec);
        ]=]
        --[=[ Lua equivalent (disabled):
    Attack(M.ccap15, M.avrec)
        ]=]
        SetIndependence(M.ccap2, 1)
        SetIndependence(M.ccap3, 1)
        SetIndependence(M.ccap4, 1)
        SetIndependence(M.ccap5, 1)
        SetIndependence(M.ccap6, 1)
        SetIndependence(M.ccap7, 1)
        SetIndependence(M.ccap8, 1)
        SetIndependence(M.ccap9, 1)
        --[=[ DLL source comment (inactive C++):
//SetIndependence (ccap10, 1);
        ]=]
        --[=[ Lua equivalent (disabled):
    SetIndependence(M.ccap10, 1)
        ]=]
        --[=[ DLL source comment (inactive C++):
//SetIndependence (ccap11, 1);
        ]=]
        --[=[ Lua equivalent (disabled):
    SetIndependence(M.ccap11, 1)
        ]=]
        --[=[ DLL source comment (inactive C++):
//SetIndependence (ccap12, 1);
        ]=]
        --[=[ Lua equivalent (disabled):
    SetIndependence(M.ccap12, 1)
        ]=]
        --[=[ DLL source comment (inactive C++):
//SetIndependence (ccap13, 1);
        ]=]
        --[=[ Lua equivalent (disabled):
    SetIndependence(M.ccap13, 1)
        ]=]
        --[=[ DLL source comment (inactive C++):
//SetIndependence (ccap14, 1);
        ]=]
        --[=[ Lua equivalent (disabled):
    SetIndependence(M.ccap14, 1)
        ]=]
        --[=[ DLL source comment (inactive C++):
//SetIndependence (ccap15, 1);
        ]=]
        --[=[ Lua equivalent (disabled):
    SetIndependence(M.ccap15, 1)
        ]=]
        M.economyccaplatoon = true
    end
    --[=[ DLL source comment (inactive C++):
/*
		Jens platoonarrive is a floating point number.
		Here you test to see if it is 'true', like a boolean.
		This will compile but probably never evaluate
		correctly.  
		For arcane reasons platoonarrive is probaly 'true'
		50 % of the time, completely at random unless you 
		set it to zero somewhere, which will make it false.
	*/
    ]=]
    if (M.platoonhere == true) and (M.respawn == false) then
        if (not IsAlive(M.ccap1)) and (not IsAlive(M.ccap2)) and (not IsAlive(M.ccap3)) and (not IsAlive(M.ccap4)) and (not IsAlive(M.ccap5)) and (not IsAlive(M.ccap6)) and (not IsAlive(M.ccap7)) and (not IsAlive(M.ccap8)) and (not IsAlive(M.ccap9)) then
            M.ccap1 = BuildObject("svfigh", ENEMY_TEAM, "ccaplatoonspawn")
            M.respawn = true
            M.economyccaplatoon = false
        end
    end
    if (M.twominsplatoon < GetTime()) and (M.corbettalive == true) then
        M.corbettalive = false
    end
    if (M.platoonarrive < GetTime()) and (M.platoonhere == true) and (M.reminder == false) then
        M.aud102 = subtit.Play("misn0635.wav")
        M.aud103 = subtit.Queue("misn0646.wav")
        M.aud104 = subtit.Queue("misn0651.wav")
        M.platoonhere = false
        M.endme = true
    end
    if (M.endme == true) and (AudioDone(M.aud102)) and (AudioDone(M.aud103)) and (AudioDone(M.aud104)) then
        FailMission(GetTime() + 0.0, "misn06l4.des")
    end
end

--[=[ DLL declarations/lifecycle comment (inactive C++):
/*
	Misn06Mission Event
*/
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
// bools
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
// doneauds created by GEC for cineractive control
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
// floats
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
// handles
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
//handle for haephestus 
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
//handle for starport that triggers starportdisc bool
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
//duh! 
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
//handle for cam where 5th platoon is supposed to be 
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
//handle of soviet turret in scrap field
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
//duh again!
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
//yet another duh
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
//where player nust go to get information on where database was taken 
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
// handle of navbeacon at starport 
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
//handle of camera where player must go to finish mission 
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
//these handles are for the waves that attack the player
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
//these are the handles of the starport buildings the player recons
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
//these are the handles of the fifth platoon used in the opening cineractive
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
//these are the handles for the units that patrol the canyons
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
//these are the handles for the cca platoon created at the end of the mission
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
// integers
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
// init bools
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
// init floats
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
// init handles
]=]

--[=[ DLL declarations/lifecycle comment (inactive C++):
// init ints
]=]
