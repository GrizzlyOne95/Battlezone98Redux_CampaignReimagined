-- Faithful stock misn11 port for Battlezone 98 Redux / Lua 5.1, with the shared offline +
-- 2-4 player co-op layer of the misn06-10 ports (Docs/MISN11_COOP.md).
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misn11Mission.cpp.
-- Source blob: 127e2f66fe3de1c79434a4c1a7b284601909ee7c.
-- All original disabled gameplay code remains disabled at its source location.
-- Complete C++/header, including declaration/serialization comments:
-- References/Misn11Source/.
-- Everything the campaign adds lives between "-- CR ... >>" / "-- CR ... <<" marker lines
-- (Tools/Test-Misn11SourceParity.py strips them); each co-op substitution outside the markers
-- is an explicit delta in that test. Offline play reproduces the DLL; only the leader runs the
-- mission body. Requires the stock misn11 map labels, paths, OTF/audio. No AIP, no SetAIControl:
-- the CCA is script-driven.

local function NewState()
    return {
        won = false, lost = false,
        launch_gone = false, escape_start = false, last_wave = false,
        got_there1 = false, got_there2 = false, got_there3 = false,
        escape_path = false, start_done = false, betrayal = false,
        pursuit_warning = false, betrayal_message = false,
        check1 = false, check2 = false, restart = false, launch_attack = false,
        escape_time = 99999.0, last_wave_time = 99999.0,
        camera_time = 99999.0, betrayal_time = 99999.0, start_delay = 99999.0,
        player = nil, recy = nil, cam1 = nil, cam2 = nil, cam3 = nil, cam4 = nil,
        tug1 = nil, tug2 = nil, turr1 = nil, turr2 = nil, turr3 = nil,
        openh = nil, launch = nil, launch2 = nil, tank1 = nil, tank2 = nil,
        audmsg = 0,
    }
end

local M = NewState()
-- CR co-op layer >>
-- EXU Initialization (the co-op layer needs the bundled multiplayer hooks).
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})
local exu = require("exu")
-- Native MultST Init precedes Start. The authored base is the convoy and its escorts, so no human
-- team keeps a starting recycler.
if type(IsNetGame) == "function" and IsNetGame() then
    assert(exu.DisableStartingRecycler and exu.GetMyNetID,
        "misn11 co-op requires the bundled EXU multiplayer hooks")
    exu.DisableStartingRecycler()
end
local subtit = require("ScriptSubtitles")
local CRCoop = require("CRCoop")
-- The DLL's CCA is team 2 (a guest slot in co-op): every CCA object and spawn is team 5. The mission
-- has no AIP and no strategic AI: every CCA unit is driven by the script below.
local LEADER_TEAM, ENEMY_TEAM = 1, 5
-- CR co-op layer <<
-- CR Io weather >>
local CRIoWeather = require("CRIoWeather")
local IoSites = require("CRIoSites11")
local Environment = require("Environment")
local IO_OPS = { IoState = true, IoErupt = true, IoQuake = true }
-- The launch pad's loss shakes Io once (the director replicates the quake to every peer).
local PAD_QUAKE_STRENGTH, PAD_QUAKE_SECONDS = 0.9, 8.0
-- CR Io weather <<
-- CR co-op layer >>
-- Co-op presentation uses the established misn03/misn05 E/A transport.
-- Only the campaign leader runs the mission body below; HUD/audio/removal/timer/
-- end calls are explicitly delivered to every peer.
-- E/A are an ordered, acknowledged event stream (eight small packets in flight,
-- retried every 0.2s). No tables go on wire. These types do not collide with CRCoop's
-- H/Q/K/P/L protocol. Join-in-progress still requires a restart: native world
-- reconstruction is not available here.
local unpackArgs = unpack or table.unpack
local native = {
    ClearObjectives = ClearObjectives, AddObjective = AddObjective,
    UpdateObjective = UpdateObjective, SetObjectiveOn = SetObjectiveOn,
    SetObjectiveOff = SetObjectiveOff, SetObjectiveName = SetObjectiveName,
    SetUserTarget = SetUserTarget, RemoveObject = RemoveObject,
    SucceedMission = SucceedMission, FailMission = FailMission,
    Play = subtit.Play, Queue = subtit.Queue, Stop = subtit.Stop,
}
local events, acknowledgements = {}, {}
local receivedEvent = 0
local pendingSeq, pendingSince
local nextEventSend = 0

local function ResetPresentation()
    events, acknowledgements, receivedEvent = {}, {}, 0
    pendingSeq, pendingSince = nil, nil
    nextEventSend = 0
end

local function FromLeader(from)
    local player = CRCoop.GetPlayers()[from]
    return player and player.team == LEADER_TEAM
end

local function ApplyPresentation(op, ...)
-- CR Io weather >>
    if IO_OPS[op] then
        -- Weather events carry no handles: never labelled, never waited on.
        return CRIoWeather.ApplyNetEvent(op, ...)
    end
-- CR Io weather <<
    if op == "Label" then
        local handle, label = ...
        if type(SetLabel) == "function" and IsValid(handle) and type(label) == "string" then
            pcall(SetLabel, handle, label)
        end
    elseif op == "SucceedMission" or op == "FailMission" then
        local when, description = ...
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

-- Lexical wrappers affect this mission only; shared modules retain stock APIs.
local function ClearObjectives(...) return Present("ClearObjectives", ...) end
local function AddObjective(...) return Present("AddObjective", ...) end
local function UpdateObjective(...) return Present("UpdateObjective", ...) end
local function SetObjectiveOn(...) return Present("SetObjectiveOn", ...) end
local function SetObjectiveOff(...) return Present("SetObjectiveOff", ...) end
local function SetObjectiveName(...) return Present("SetObjectiveName", ...) end
local function SetUserTarget(...) return Present("SetUserTarget", ...) end
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
local function SucceedMission(...) return EndMission("SucceedMission", ...) end
local function FailMission(...) return EndMission("FailMission", ...) end

local function UpdatePresentationTransport()
    if not CRCoop.IsNetworkGame() then return end
    -- Read by the harness probe (numbers in M appear in its snapshots): must stay 0.
    if M.coopUnresolved == nil then M.coopUnresolved = 0 end
    if not CRCoop.IsAuthority() then return end
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
    if kind ~= "E" then return false end
    if CRCoop.IsAuthority() or not FromLeader(from) then return true end
    local seq, op, ttl = ...
    if type(seq) ~= "number" or type(op) ~= "string" or type(ttl) ~= "number" then return true end
    if seq == receivedEvent + 1 and (native[op] or IO_OPS[op] or op == "Label") then
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

-- Victory eases the sky back to calm while the result screen counts down. EndMission has
-- already queued the result; this only nudges the director (leader/offline).
local presentSucceed = SucceedMission
local function SucceedMission(...)
    if (not M.ioCalm) and ((not CRCoop.IsNetworkGame()) or CRCoop.IsAuthority()) then
        M.ioCalm = true
        CRIoWeather.ReleaseForcedLevel()
        CRIoWeather.SetTargetLevel(1)
    end
    return presentSucceed(...)
end

-- The DLL's AudioMessage(file) is the shared radio line: the leader plays it and every peer hears
-- it with its subtitle (Play returns the native audio handle on the leader, nil offline-safe).
local function AudioMessage(file) return subtit.Play(file) end
-- CR co-op layer <<


local function Exists(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

-- BZR adaptation: a missing object cannot satisfy a proximity trigger.
-- Guard both handle operands so nil/zero is never passed to a position overload.
-- Keep the explicit path-point argument (notably "check2", 1) intact.
local function Distance(from, to, point)
    if not Exists(from) then return math.huge end
    if type(to) ~= "string" and not Exists(to) then return math.huge end
    if point ~= nil then return GetDistance(from, to, point) end
    return GetDistance(from, to)
end

-- BUG FIX (native null dereferences): Setup's Execute block called SetName /
-- SetObjective through unchecked GetObj pointers. Skip only absent objects;
-- present objects receive the same names/markers, and no timers or transitions
-- change. Missing transports still enter the original failure branch below.
local function NameObject(h, name, objective)
    if Exists(h) then
        if objective then SetObjectiveOn(h) end
        SetObjectiveName(h, name)
    end
end

-- Native IsOdf matched an ODF basename. Accept the equivalent .odf spelling
-- too, as in the existing source ports; do not add any team/ownership filter.
local function IsOdfBase(h, name)
    return Exists(h) and (IsOdf(h, name) or IsOdf(h, name .. ".odf"))
end

-- CR co-op layer >>
local function ConfigureAlliances()
    CRCoop.ApplyCoopAlliances(ENEMY_TEAM)
end

-- Co-op trigger helpers. Offline CRCoop iterates just the local player, so each
-- reproduces the DLL's single-player test exactly. Every distance goes through
-- the mission's Distance guard (never raw GetDistance).
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

-- Human teams in the session (1 offline): the way misn07-10 size their reinforcements.
local function HumanCount()
    return CRCoop.ForEachHumanTeam(function() end)
end

-- The DLL's "the player reached the pad" latch, per human player: every human must have been
-- within the arrival radius at some point (a player who has left the session is not waited for).
local function AllPlayersArrived(target, radius)
    M.arrived = M.arrived or {}
    CRCoop.ForEachPlayerHandle(function(h, id)
        if Distance(h, target) < radius then M.arrived[id or 0] = true end
    end)
    local players, required = CRCoop.GetPlayers(), 0
    if CRCoop.IsNetworkGame() then
        for id, player in pairs(players) do
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
-- CR co-op layer <<
-- CR CCA scaling >>
-- The DLL's CCA is sized for one player. Each extra human team (up to four players) adds one
-- svfigh to each strike wave and to the final wave, and one svtank to the launch-pad ambush.
local EXTRA_MAX = 3
local function ExtraHumans()
    return math.min(EXTRA_MAX, math.max(0, HumanCount() - 1))
end

-- The extra units of a wave, built where the wave spawns (before the DLL's fighter scan, so they
-- take the same orders). Returns the handles.
local function BuildExtras(odf, where)
    local units = {}
    for _ = 1, ExtraHumans() do units[#units + 1] = BuildObject(odf, ENEMY_TEAM, where) end
    return units
end
-- CR CCA scaling <<
-- CR ambush >>
-- The map's idle CCA units go hostile (Docs/MISN11_COOP.md "Ambush"):
--   pickets   svturr0/svturr1, beside the convoy road: wake when a convoy tug or any human comes
--             within PICKET_WAKE_M, then hunt the nearest human or convoy tug
--   walker    svwalk, beside the second blockade: wakes when the convoy halts at check2 and
--             advances on the nearest human or convoy tug (the convoy restarts only when it and the
--             blockade turret are both dead)
--   artillery svartl x2, beside the openheimer path: shell any human within ART_RANGE_M once the
--             transport has defected
local PICKET_WAKE_M, PICKET_HUNT_M, WALKER_HUNT_M, ART_RANGE_M = 380.0, 700.0, 1500.0, 650.0
local HUNT_INTERVAL_S, HUNT_REISSUE_S = 3.0, 6.0

local function NearestHuntTarget(from, radius, includeConvoy)
    local best, bestDistance = nil, radius
    CRCoop.ForEachPlayerHandle(function(h)
        local distance = Distance(from, h)
        if distance < bestDistance then best, bestDistance = h, distance end
    end)
    if includeConvoy then
        for _, tug in ipairs({ M.tug1, M.tug2 }) do
            if IsAlive(tug) then
                local distance = Distance(from, tug)
                if distance < bestDistance then best, bestDistance = tug, distance end
            end
        end
    end
    return best
end

local function Hunt(unit, radius, includeConvoy)
    if not IsAlive(unit) then return end
    local target = NearestHuntTarget(unit, radius, includeConvoy)
    if target == nil then return end
    local last = M.hunt[unit]
    local now = GetTime()
    if last == nil or last.target ~= target or now - last.time >= HUNT_REISSUE_S then
        Attack(unit, target, 1)
        M.hunt[unit] = { target = target, time = now }
    end
end

local function ConvoyWithin(unit, distance)
    return Distance(unit, M.tug1) < distance or Distance(unit, M.tug2) < distance
        or AnyPlayerWithin(unit, distance)
end

local function UpdateAmbush()
    local now = GetTime()
    if now < M.next_hunt then return end
    M.next_hunt = now + HUNT_INTERVAL_S
    for _, picket in ipairs({ M.picket1, M.picket2 }) do
        if IsAlive(picket) then
            if not M.woken[picket] and ConvoyWithin(picket, PICKET_WAKE_M) then M.woken[picket] = true end
            if M.woken[picket] then Hunt(picket, PICKET_HUNT_M, true) end
        end
    end
    if M.check2 then Hunt(M.walker, WALKER_HUNT_M, true) end
    if M.betrayal_message then
        Hunt(M.art1, ART_RANGE_M, false)
        Hunt(M.art2, ART_RANGE_M, false)
    end
end
-- CR ambush <<
-- CR betrayal >>
-- The defection, reworked (Docs/MISN11_COOP.md "Betrayal"). Before the tug breaks off, a CCA backup
-- squad drives in from the far (west) end of the openheimer path to the CCA outpost beside the
-- artillery; at the defection it forms up on the tug and engages anyone who chases it. Collins
-- (misn1114) warns any human who nears the defector; Corbett (misn1115) logs the intel once every
-- human has broken contact.
local BACKUP_SPAWN_X, BACKUP_SPAWN_Z, BACKUP_SPREAD_M = 906.0, 98614.0, 24.0
local BACKUP_CALL_M, CHASE_M, WARN_M, BREAK_M, BREAK_S, WARN_GAP_S = 250.0, 350.0, 450.0, 700.0, 8.0, 12.0
local SQUAD_INTERVAL_S = 2.0

local function CallBackup()
    M.backup_called = true
    local odfs = { "svtank", "svtank", "svfigh" }
    for _ = 1, ExtraHumans() do odfs[#odfs + 1] = "svfigh" end
    for index, odf in ipairs(odfs) do
        local px, pz = BACKUP_SPAWN_X + BACKUP_SPREAD_M * (index - 1), BACKUP_SPAWN_Z + 14.0 * (index % 2)
        local py = GetTerrainHeightAndNormal(SetVector(px, 0.0, pz))
        local unit = BuildObject(odf, ENEMY_TEAM, SetVector(px, py, pz))
        M.backup[#M.backup + 1] = unit
        -- Rendezvous at the outpost's artillery until the tug breaks off.
        if IsAlive(M.art1) then Goto(unit, M.art1, 1) end
    end
end

-- The squad belongs to the defector; the DLL's strike-wave fighter scans must not take it.
local function IsBackupUnit(h)
    for _, unit in ipairs(M.backup) do
        if unit == h then return true end
    end
    return false
end

local function SquadAlive()
    local alive = 0
    for _, unit in ipairs(M.backup) do
        if IsAlive(unit) then alive = alive + 1 end
    end
    return alive
end

-- The human closest to the defecting tug, within `radius` (handle) or nil.
local function NearestChaser(radius)
    local best, bestDistance = nil, radius
    CRCoop.ForEachPlayerHandle(function(h)
        local distance = Distance(h, M.openh)
        if distance < bestDistance then best, bestDistance = h, distance end
    end)
    return best
end

local function UpdateBackup()
    local now = GetTime()
    if not M.backup_called and (M.betrayal_message
        or (not M.betrayal and M.start_delay == 99999.0
            and Distance(M.openh, M.cam1) < BACKUP_CALL_M)) then
        CallBackup()
    end
    if not M.betrayal_message then return end
    if not M.backup_formed then
        M.backup_formed = true
        for _, unit in ipairs(M.backup) do
            if IsAlive(unit) and IsAlive(M.openh) then Formation(unit, M.openh, 1) end
        end
    end
    if now >= M.next_squad then
        M.next_squad = now + SQUAD_INTERVAL_S
        local chaser = NearestChaser(CHASE_M)
        for _, unit in ipairs(M.backup) do
            if IsAlive(unit) then
                if chaser ~= nil then
                    if M.squad_order[unit] ~= chaser then
                        Attack(unit, chaser, 1)
                        M.squad_order[unit] = chaser
                    end
                elseif M.squad_order[unit] ~= nil then
                    M.squad_order[unit] = nil
                    if IsAlive(M.openh) then Formation(unit, M.openh, 1) end
                end
            end
        end
    end
    if not M.warned_massive and AnyPlayerWithin(M.openh, WARN_M) then
        M.warned_massive = true
        M.warned_massive_time = now
        AudioMessage("misn1114.wav")
    end
    if M.warned_massive and not M.intel_logged and now - M.warned_massive_time >= WARN_GAP_S then
        local broken = (not IsAlive(M.openh)) or (not AnyPlayerWithin(M.openh, BREAK_M))
        if broken or SquadAlive() == 0 then
            M.clear_since = M.clear_since or now
            if now - M.clear_since >= BREAK_S then
                M.intel_logged = true
                AudioMessage("misn1115.wav")
            end
        else
            M.clear_since = nil
        end
    end
end
-- CR betrayal <<
-- CR Io weather >>
-- Io atmosphere (Docs/IO_WEATHER.md). The leader (or offline play) runs the director's
-- automatic weather and the beats below; guests render the same sky from the seeded timeline
-- plus the host's state and eruption/quake events, which ride the ordered presentation stream
-- like any other event. The events carry no handles, so they bypass the marker label/TTL logic.
-- The director is cosmetic: it never damages, shoves or scrambles anything.
local ioStarted, ioAnnounced = false, false

local function InitIoWeather()
    ioStarted = true
    local net = CRCoop.IsNetworkGame()
    local authority = (not net) or CRCoop.IsAuthority()
    Environment.Init()
    CRIoWeather.Init({
        authority = authority,
        seed = M.ioSeed, -- nil: the leader/offline picks one, guests wait for the host's state
        sites = IoSites,
        startLevel = 1,
        targetLevel = 1,
        -- The host queues straight onto the stream: its own Present() would apply the event again.
        send = net and function(op, ...)
            events[#events + 1] = { op = op, args = { ... }, n = select("#", ...), ttl = RESOLVE_TIMEOUT }
        end or nil,
    })
    if M.weatherState ~= nil and authority then
        CRIoWeather.Load(M.weatherState)
        M.weatherState = nil
    end
    if authority then M.ioSeed = CRIoWeather.Seed end -- survives a save
end

-- Every peer, every frame after the session is ready.
local function UpdateIoWeather(dt)
    if not ioStarted then InitIoWeather() end
    if CRCoop.IsNetworkGame() and CRCoop.IsAuthority() and not ioAnnounced and CRCoop.IsSessionReady() then
        ioAnnounced = true
        CRIoWeather.AnnounceState()
    end
    CRIoWeather.Update(dt)
    Environment.Update(dt)
end

local function ShutdownIoWeather()
    if ioStarted then CRIoWeather.Shutdown() end
    ioStarted, ioAnnounced = false, false
end

-- Host/offline only: the severity ladder follows the mission, each beat once.
--   2 at the start -> 3 on the betrayal -> 4 on the second strike -> a 60 s level-5 burst plus a
--   quake when the launch pad dies -> calm on the win (SucceedMission).
local function UpdateIoBeats()
    local beats = M.ioBeats
    if beats == nil then beats = {}; M.ioBeats = beats end
    if (not beats.start) and M.start_done then
        beats.start = true
        CRIoWeather.SetTargetLevel(2)
    end
    if (not beats.betrayal) and M.betrayal_message then
        beats.betrayal = true
        CRIoWeather.SetTargetLevel(3)
    end
    if (not beats.strike2) and M.check2 then
        beats.strike2 = true
        CRIoWeather.SetTargetLevel(4)
    end
    if (not beats.pad) and M.launch_gone then
        beats.pad = true
        CRIoWeather.ForceLevel(5, 60.0, 10.0)
        CRIoWeather.Quake(PAD_QUAKE_STRENGTH, PAD_QUAKE_SECONDS)
    end
end
-- CR Io weather <<
-- CR rally >>
-- Respawns rally at the start (the head of the convoy road) until the convoy departs (mission
-- phase 1), then at the lead tug. Its loss fails the mission, but until the result lands a
-- respawn must not rally at a corpse: drop the rally point and the native MultST spawn (the
-- player start buoys' team start) takes over.
local rallyDropped = false
local function UpdateRally()
    if rallyDropped or CRCoop.GetMissionPhase() < 1 then return end
    -- Every peer resolves the authored lead tug itself (the mission body only runs on the leader).
    local tug = GetHandle("avhaul0_tug")
    if tug == nil or not IsAlive(tug) then
        rallyDropped = true
        local respawn = CRCoop.GetRespawn()
        if respawn then respawn.SetRallyPoints({}) end
    end
end
-- CR rally <<
-- CR co-op layer >>
local function InitializeCoop()
    CRCoop.Initialize({
        getLocalPlayerId = function() return exu.GetMyNetID and exu.GetMyNetID() end,
        leaderTeam = LEADER_TEAM, humanTeamMin = 1, humanTeamMax = 4,
        onOutOfLives = function() FailMission(GetTime() + 3.0) end,
        -- The start of the convoy road until the convoy moves out (phase 1), then the lead tug.
        rallyPoints = { [0] = "base1", [1] = "avhaul0_tug" },
    })
    ConfigureAlliances()
    ResetPresentation()
    rallyDropped = false
    ShutdownIoWeather()
end

-- Co-op state outside the DLL's serialized fields.
local function InitializeCoopState()
    M.picket1 = GetHandle("svturr0_turrettank")
    M.picket2 = GetHandle("svturr1_turrettank")
    M.walker = GetHandle("svwalk0_walker")
    M.art1 = GetHandle("svartl0_howitzer")
    M.art2 = GetHandle("svartl0(1)_howitzer")
    M.hunt, M.woken, M.next_hunt = {}, {}, 0.0
    M.backup, M.squad_order, M.next_squad = {}, {}, 0.0
    M.backup_called, M.backup_formed = false, false
    M.warned_massive, M.intel_logged = false, false
    M.arrived = {}
end
-- CR co-op layer <<

function Start()
-- CR co-op layer >>
    InitializeCoop()
-- CR co-op layer <<
    -- The source initializes every member before Setup. Keep unused members
    -- (escape_path, camera_time, recy, cam4, audmsg) for cut-content work.
    M = NewState()
-- CR co-op layer >>
    InitializeCoopState()
    subtit.Initialize()
-- CR co-op layer <<
end

-- CR Io weather >>
function AddObject(h)
    if not IsValid(h) then return end
    Environment.OnObjectCreated(h)
    CRIoWeather.OnObjectCreated(h)
end

-- CR Io weather <<
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


function Update(timestep)
-- CR co-op layer >>
    subtit.Update()
    CRCoop.Update()
    UpdatePresentationTransport()
    if M.coopResult or M.coopPendingResult then
-- CR co-op layer <<
-- CR Io weather >>
        -- The sky keeps easing while the result screen counts down.
        UpdateIoWeather(timestep)
-- CR Io weather <<
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
-- CR Io weather >>
    UpdateIoWeather(timestep)
-- CR Io weather <<
-- CR rally >>
    UpdateRally()
-- CR rally <<
-- CR co-op layer >>
    if not CRCoop.IsAuthority() then return end
    if CRCoop.IsNetworkGame() and not M.coopBootstrapped then
        M.coopBootstrapped = true
        -- The authored offline placeholder must not remain beside the humans.
        local offlinePlayer = GetHandle("player-1_hover")
        if IsValid(offlinePlayer) and not CRCoop.IsHumanCraft(offlinePlayer) then RemoveObject(offlinePlayer) end
    end
-- CR co-op layer <<
    if not M.start_done then
        --[[
            -paths
            base
            openheimer
            escape
            units
            avhaul0_tug
            avhaul1_tug
            avhaul2_tug
            -camera
            apcamr3_camerapod
            apcamr4_camerapod
            apcamr5_camerapod
        ]]
        --[[
            misn1501.wav
            Now that we've captured the SAV relics
            we need to ransport this key technology
            off of Io.  This could win the war for us.
        ]]
        M.tug1 = GetHandle("avhaul0_tug")
        M.tug2 = GetHandle("avhaul1_tug")
        M.openh = GetHandle("avhaul2_tug")
        M.turr1 = GetHandle("svturr2_turrettank")
        M.turr2 = GetHandle("second_blockade")
        M.turr3 = GetHandle("svturr3_turrettank")
        M.cam1 = GetHandle("apcamr3_camerapod")
        M.cam2 = GetHandle("apcamr4_camerapod")
        M.cam3 = GetHandle("apcamr5_camerapod")
        M.launch = GetHandle("launch_pad")
        M.launch2 = GetHandle("launch_pad2")
        NameObject(M.cam1, "Waypoint 1")
        NameObject(M.cam2, "Waypoint 2")
        NameObject(M.cam3, "Launch Pad")
        NameObject(M.tug1, "Transport 1", true)
        NameObject(M.tug2, "Transport 2", true)
        NameObject(M.openh, "Transport 3", true)

        SetUserTarget(M.cam1)
        SetScrap(1, 50)
        AudioMessage("misn1101.wav")
        ClearObjectives()
        AddObjective("misn1101.otf", "white")
        M.start_delay = GetTime() + 15.0
        M.start_done = true
    end
    --[[
        Mad Dr. Openheimer
        has magic shields that
        prevent him from being killer.
    ]]
    -- Preserve the original +300 health EACH Execute, including after betrayal;
    -- multiplying by timestep or making this full invulnerability changes play.
    if IsAlive(M.openh) then AddHealth(M.openh, 300.0) end

    if GetTime() > M.start_delay then
        --[[
            Moving out!
        ]]
        AudioMessage("misn1102.wav")
        M.start_delay = 99999.0
        Goto(M.tug1, "base1", 1)
        Goto(M.tug2, "base1", 1)
        Goto(M.openh, "base1", 0)
-- CR rally >>
        CRCoop.SetMissionPhase(1)
-- CR rally <<
    end
    --[[
        if (isDamaged(tug1) || is damaged(tug2)
        AudioMessage(misn1402)
        get your ass up here and help us out, etc.
    ]]
-- CR betrayal >>
    UpdateBackup()
-- CR betrayal <<
    if not M.betrayal and Distance(M.cam1, M.openh) < 50.0 then
        M.betrayal_time = GetTime() + 15.0 -- when we announce it
        Goto(M.openh, "openheimer", 1)
        M.betrayal = true
    end
    if GetTime() > M.betrayal_time then
        M.betrayal_time = 99999.0
        AudioMessage("misn1103.wav") -- transport 3 seems to be braking off
        AudioMessage("misn1104.wav") -- farewell capitalist pigs!!
        -- BUG FIX: GetObj(openh)->SetTeam(2) could dereference an object killed
        -- after betrayal started. Skip the team write only if it no longer
        -- exists; keep the announcement, reinforcements, and objectives on the
        -- same schedule. A present transport still changes to team 2 here.
        if Exists(M.openh) then SetTeamNum(M.openh, ENEMY_TEAM) end
        Defend(M.turr1, 0)
        Defend(M.turr3, 0)
        AudioMessage("misn1105.wav")
        BuildObject("svfigh", ENEMY_TEAM, "strike1")
-- CR CCA scaling >>
        BuildExtras("svfigh", "strike1")
-- CR CCA scaling <<
        -- Preserve the source's complete object-list scan, including existing
        -- fighters. CR: only CCA fighters (team 5) are re-tasked, never a guest's or an ally's.
        for h in AllObjects() do
            if IsOdfBase(h, "svfigh") and GetTeamNum(h) == ENEMY_TEAM and not IsBackupUnit(h) then Goto(h, "strike_path1", 0) end
        end
        M.betrayal_message = true
        ClearObjectives()
        AddObjective("misn1102.otf", "white")
    end
    -- The original condition has no distance threshold: GetDistance alone is
    -- a C++ boolean conversion. Explicit ~= 0 preserves it (Lua treats 0 as
    -- true). Guessing a pursuit radius would change the warning's timing.
    if M.betrayal_message and not M.pursuit_warning
        and IsAlive(M.turr1)
        and CRCoop.AnyPlayerSatisfies(function(h) return Distance(M.turr1, h) ~= 0 end) then
        AudioMessage("misn1106.wav") -- do not pursue..
        M.pursuit_warning = true
    end
    if (Distance(M.cam1, M.tug1) < 50.0
        or AnyPlayerWithin(M.cam1, 50.0)) and not M.check1 then
        M.check1 = true
        SetUserTarget(M.cam2)
    end
    if Distance(M.tug1, "check2", 1) < 50.0 and not M.check2 then -- was cam2
        --[[
            At this point openheimer
            has escaped..
        ]]
        if Exists(M.openh) then SetObjectiveOff(M.openh) end
        M.check2 = true
        SetUserTarget(M.cam3)
        AudioMessage("misn1107.wav")
        --[[
            Now send another enemy
        ]]
        BuildObject("svfigh", ENEMY_TEAM, "strike2")
-- CR CCA scaling >>
        BuildExtras("svfigh", "strike2")
-- CR CCA scaling <<
        for h in AllObjects() do
            if IsOdfBase(h, "svfigh") and GetTeamNum(h) == ENEMY_TEAM and not IsBackupUnit(h) then Goto(h, "strike_path2", 0) end
        end
    end
    -- CR: the walker beside the blockade must be dead too (it is woken by check2, see CR ambush).
    if M.check2 and not M.restart and not IsAlive(M.turr2) and not IsAlive(M.walker) then
        AudioMessage("misn1102.wav")
        Goto(M.tug1, "base2", 1)
        Goto(M.tug2, "base2", 1)
        M.restart = true
    end
    if M.restart and not M.launch_attack
        and (AnyPlayerWithin(M.launch, 450.0)
            or Distance(M.launch, M.tug1) < 450.0) then
        M.tank1 = BuildObject("svtank", ENEMY_TEAM, "launch_attack")
        M.tank2 = BuildObject("svtank", ENEMY_TEAM, "launch_attack")
        -- Preserve the literal native health delta -0.90, not a guessed 90%
        -- damage conversion. The later two-tank-death branch guarantees the
        -- scripted loss of the pad even if this tiny delta leaves it standing.
        -- BUG FIX: guard the source's unchecked GetObj(launch) dereference;
        -- an absent pad needs no health write. Intact-pad behavior is identical.
        if Exists(M.launch) then AddHealth(M.launch, -0.90) end
        AudioMessage("misn1108.wav")
        Attack(M.tank1, M.launch, 1)
        Attack(M.tank2, M.launch, 1)
-- CR CCA scaling >>
        -- One more tank per extra human joins the ambush. They are not part of the DLL's
        -- "both tanks died" test (M.tank1/M.tank2 only).
        for _, tank in ipairs(BuildExtras("svtank", "launch_attack")) do Attack(tank, M.launch, 1) end
-- CR CCA scaling <<
        --[[
        ObjectList &list = *GameObject::objectList;
        for (ObjectList::iterator i = list.begin(); i != list.end(); i++)
        {
            GameObject *o=*i;
            Handle h=GameObjectHandle::Find(o);
            if (IsOdf(h,"svtank"))
            {
                Attack(h,launch,1); // attack the launch pad
            }

        }
        ]]
        M.launch_attack = true
    end
    if M.launch_attack and not IsAlive(M.launch) and not M.launch_gone then
        AudioMessage("misn1109.wav")
        M.launch_gone = true
        M.escape_time = GetTime() + 40.0
    end
    --[[
        If both tanks die
        and somehow
        the launch pad is ok..
        It's not!
    ]]
    if M.launch_attack and not IsAlive(M.tank1) and not IsAlive(M.tank2)
        and IsAlive(M.launch) then
        RemoveObject(M.launch)
        M.launch_gone = true
        M.escape_time = GetTime() + 10.0
    end
    if M.launch_gone and GetTime() > M.escape_time then
        Goto(M.tug1, "escape")
        Goto(M.tug2, "escape")
        AudioMessage("misn1110.wav")
        SetObjectiveOn(M.launch2)
        ClearObjectives()
        AddObjective("misn1103.otf", "white")
        SetObjectiveName(M.launch2, "Launch Pad 2")
        M.escape_time = 99999.0
    end
    if M.launch_gone and (Distance(M.tug2, M.cam3) < 50.0
        or not IsAlive(M.cam3)) and not M.escape_start then -- in case cam3 is shot
        M.escape_start = true
        M.last_wave_time = GetTime() + 15.0
        M.launch_gone = true
    end
    if not M.last_wave and M.last_wave_time < GetTime() then
        BuildObject("svfigh", ENEMY_TEAM, "strike2")
        BuildObject("svfigh", ENEMY_TEAM, "strike2")
-- CR CCA scaling >>
        BuildExtras("svfigh", "strike2")
-- CR CCA scaling <<
        for h in AllObjects() do
            if IsOdfBase(h, "svfigh") and GetTeamNum(h) == ENEMY_TEAM and not IsBackupUnit(h) then
                Attack(h, M.tug2, 1) -- attack the launch pad
            end
        end
        -- we put this one in later
        -- cuz we want it to wait
        local last_guy = BuildObject("svfigh", ENEMY_TEAM, M.launch2)
        local victim = NearestPlayer(M.launch2)
        if victim ~= nil then Attack(last_guy, victim) end
        BuildObject("avcamr", 1, "last_camera")
        M.last_wave = true
        M.last_wave_time = 99999.0
    end
    if not M.lost and (not IsAlive(M.tug1) or not IsAlive(M.tug2)
        or (not M.betrayal and not IsAlive(M.openh))) then
        if M.betrayal then
            ClearObjectives()
            AddObjective("misn1102.otf", "white")
        end
        AudioMessage("misn1111.wav")
        AudioMessage("misn1112.wav")
        M.lost = true
        FailMission(GetTime() + 15, "misn11l1.des")
    end
    if M.last_wave and not M.got_there1 and AllPlayersArrived(M.launch2, 200.0) then
        M.got_there1 = true
        -- we do each check seperately in case
        -- the vehicles get to safety & leave
    end
    if M.last_wave and not M.got_there2 and Distance(M.tug1, M.launch2) < 200.0 then
        M.got_there2 = true
    end
    if M.last_wave and not M.got_there3 and Distance(M.tug2, M.launch2) < 200.0 then
        M.got_there3 = true
    end
    if not M.won and M.last_wave and IsAlive(M.tug1) and IsAlive(M.tug2)
        and M.got_there1 and M.got_there2 and M.got_there3 then
        AudioMessage("misn1113.wav")
        M.won = true
        SucceedMission(GetTime() + 15, "misn11w1.des")
    end
-- CR ambush >>
    UpdateAmbush()
-- CR ambush <<
-- CR Io weather >>
    UpdateIoBeats()
-- CR Io weather <<
end

function Save()
-- CR Io weather >>
    if ioStarted and ((not CRCoop.IsNetworkGame()) or CRCoop.IsAuthority()) then
        M.weatherState = CRIoWeather.Save()
    end
-- CR Io weather <<
    return M
end

function Load(state)
    -- LuaMission restores serialized game handles. Do not call Start / replay
    -- initialization here; the source's native ConvertHandle loop is unnecessary.
    M = state
end
