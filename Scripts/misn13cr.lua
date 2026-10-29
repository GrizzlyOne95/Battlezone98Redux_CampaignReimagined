-- Faithful NSDF misn13 port for stock Battlezone 98 Redux / Lua 5.1, with the shared offline +
-- 2-4 player co-op layer of the misn06-11 ports (Docs/MISN13_COOP.md).
-- Authority: Battlezone_Source/BZ1/from_bz2_dll_src/Misn13Mission.cpp.
-- Every original source comment is retained verbatim in long comments.
-- Complete native source and serialization: References/Misn13Source/.
-- Preserve Execute ordering, strict timer comparisons, and command priorities.
-- See Docs/MISN13_LUA_PORT.md for adaptations and validation.
-- Everything the campaign adds lives between "-- CR ... >>" / "-- CR ... <<" marker lines
-- (Tools/Test-Misn13SourceParity.py strips them); each co-op substitution outside the markers
-- is an explicit delta in that test. Offline play reproduces the DLL; only the leader runs the
-- mission body. Requires the stock misn13 map labels, paths, AIPs (misn13/a/c), OTF/audio.

local function NewState()
    local state = {}
    state.start_done = false
    state.silos_gone = false
    state.turret_move = false
    state.first_wave = false
    state.second_wave = false
    state.turret1_set = false
    state.turret2_set = false
    state.artil_move = false
    state.artil_move2 = false
    state.artil_set = false
    state.wave2 = false
    state.wave2_done = false
    state.wave2_move = false
    state.wave3 = false
    state.wave3_done = false
    state.wave3_move = false
    state.wave4 = false
    state.wave4_done = false
    state.wave4_move = false
    state.a = false
    state.b = false
    state.c = false
    state.d = false
    state.silo1_lost = false
    state.silo2_lost = false
    state.silo3_lost = false
    state.silo4_lost = false
    state.make_bomber = false
    state.bomber_attack = false
    state.new_target = false
    state.bomber_retreat = false
    state.sv1_wait = false
    state.sv4_wait = false
    state.sv3_wait = false
    state.sv1_reload = false
    state.sv2_reload = false
    state.sv3_reload = false
    state.sv4_reload = false
    state.set_aip = false
    state.hold_aip = false
    state.bomber_reload = false
    state.assign_tank1 = false
    state.assign_tank2 = false
    state.assign_tank3 = false
    state.assign_tank4 = false
    state.silos_attacked = false
    state.silo_defend = false
    state.muf_attacked = false
    state.muf_safe = false
    state.turret1_muf = false
    state.turret2_muf = false
    state.turret5_muf = false
    state.turret6_muf = false
    state.player_center = false
    state.apc_sent = false
    state.artil_lost = false
    state.game_over = false
    state.scav_swap = false
    state.artil_message = false
    state.first_wave_time = 99999.0
    state.second_wave_time = 99999.0
    state.next_wave_time = 99999.0
    state.artil_move_time = 99999.0
    state.artil_set_time = 99999.0
    state.set_aip_time = 99999.0
    state.bomber_retreat_time = 99999.0
    state.turret_move_time = 99999.0
    state.new_orders_time = 99999.0
    state.safe_time_check = 99999.0
    state.scrap_check = 99999.0
    state.user = nil
    state.nsdfrecycle = nil
    state.nsdfmuf = nil
    state.nav1 = nil
    state.checkpoint1 = nil
    state.checkpoint2 = nil
    state.checkpoint3 = nil
    state.checkpoint4 = nil
    state.ccacom_tower = nil
    state.ccasilo1 = nil
    state.ccasilo2 = nil
    state.ccasilo3 = nil
    state.ccasilo4 = nil
    state.spawn_point1 = nil
    state.spawn_point2 = nil
    state.check1 = nil
    state.check2 = nil
    state.check3 = nil
    state.ccamuf = nil
    state.ccaslf = nil
    state.ccaapc = nil
    state.turret1 = nil
    state.turret2 = nil
    state.turret3 = nil
    state.turret4 = nil
    state.turret5 = nil
    state.turret6 = nil
    state.artil1 = nil
    state.artil2 = nil
    state.artil3 = nil
    state.artil4 = nil
    state.fighter1 = nil
    state.fighter2 = nil
    state.fighter3 = nil
    state.fighter4 = nil
    state.fighter5 = nil
    state.fighter6 = nil
    state.sv1 = nil
    state.sv2 = nil
    state.sv3 = nil
    state.sv4 = nil
    state.sv5 = nil
    state.sv6 = nil
    state.sv7 = nil
    state.sv8 = nil
    state.sv9 = nil
    state.sv0 = nil
    state.tank1 = nil
    state.tank2 = nil
    state.tank3 = nil
    state.tank4 = nil
    state.tank5 = nil
    state.tank6 = nil
    state.tank7 = nil
    state.tank8 = nil
    state.key_geyser1 = nil
    state.key_geyser2 = nil
    state.split_geyser = nil
    state.center_geyser = nil
    state.choke_bridged = false
    state.guntower1 = nil
    state.controltower = nil
    state.center = nil
    state.svscav1 = nil
    state.svscav2 = nil
    state.svscav3 = nil
    state.svscav4 = nil
    state.svscav5 = nil
    state.svscav6 = nil
    state.svscav7 = nil
    state.svscav8 = nil
    state.escort_tank = nil
    state.nsdfrig = nil
    state.avscav1 = nil
    state.avscav2 = nil
    state.avscav3 = nil
    state.check = 0
    state.scrap = 0
    -- shot_by was a native int used as a handle. Retain the returned handle
    -- itself for Redux save/load remapping, rather than coercing it to a number.
    state.shot_by = nil
    return state
end

local M = NewState()
local started = false
local pendingObjects = {}

-- Invalid native handles must not become Lua position/path overloads or meet
-- a range trigger. Live-object distances and thresholds are unchanged.
local function MissionDistance(a, b)
    if not IsValid(a) then return math.huge end
    if type(b) ~= "string" and not IsValid(b) then return math.huge end
    return GetDistance(a, b)
end

-- Native IsOdf accepts ODF basenames; Redux builds may expose the extension.
local function IsOdfBase(h, name)
    return IsValid(h) and (IsOdf(h, name) or IsOdf(h, name .. ".odf"))
end

-- CR co-op layer >>
-- EXU Initialization (the co-op layer needs the bundled multiplayer hooks).
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})
local exu = require("exu")
-- Native MultST Init precedes Start. The authored base is the Texas Recycler (avrecycle, team 1),
-- so no human team keeps a starting recycler: the base is shared and host-authoritative.
if type(IsNetGame) == "function" and IsNetGame() then
    assert(exu.DisableStartingRecycler and exu.GetMyNetID,
        "misn13 co-op requires the bundled EXU multiplayer hooks")
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
-- The DLL's CCA is team 2, a guest slot in co-op: every CCA object, spawn, AIP and scrap/pilot count
-- is team 5. Teams 6 (mines) and 7 (support) are the campaign's standard slots; this mission uses
-- neither (it has no mines and no allied reinforcements).
local LEADER_TEAM, ENEMY_TEAM = 1, 5
-- The native AiMission supplies the CCA strategic AI (misn13*.aip). LuaMission must enable it at chunk
-- load, before the engine runs DR_AI_Init: a later SetAIControl (Start runs after it) leaves the team
-- flagged but without an AI team record and kills the host (misn08 co-op live run). SetAIP stays in
-- Update, like the DLL.
SetAIControl(ENEMY_TEAM, true)
-- CR co-op layer <<
-- CR Europa weather >>
local CREuropaWeather = require("CREuropaWeather")
local EuropaSites = require("CREuropaSites13")
local Environment = require("Environment")
local EUROPA_OPS = { EuropaState = true, EuropaPlume = true, EuropaQuake = true, EuropaSurge = true }
-- The CCA factory falling shakes Europa once (the director replicates the quake to every peer).
local FACTORY_QUAKE_STRENGTH, FACTORY_QUAKE_SECONDS = 0.7, 5.0
-- CR Europa weather <<
-- CR co-op layer >>
-- Co-op presentation uses the established misn03/misn05/misn11 E/A transport.
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
    -- Resolve result hooks after PersistentConfig.Initialize installs cleanup.
    SucceedMission = function(...) return _G.SucceedMission(...) end,
    FailMission = function(...) return _G.FailMission(...) end,
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
-- CR Europa weather >>
    if EUROPA_OPS[op] then
        -- Weather events carry no handles: never labelled, never waited on.
        return CREuropaWeather.ApplyNetEvent(op, ...)
    end
-- CR Europa weather <<
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
    if kind ~= "E" then return false end
    if CRCoop.IsAuthority() or not FromLeader(from) then return true end
    local seq, op, ttl = ...
    if type(seq) ~= "number" or type(op) ~= "string" or type(ttl) ~= "number" then return true end
    if seq == receivedEvent + 1 and (native[op] or EUROPA_OPS[op] or op == "Label") then
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

-- The DLL's AudioMessage(file) is the shared radio line: the leader plays it and every peer hears
-- it with its subtitle (Play returns the native audio handle on the leader, nil offline-safe).
local function AudioMessage(file) return subtit.Play(file) end
-- CR co-op layer <<
-- CR Europa weather >>
-- Europa atmosphere (Docs/EUROPA_WEATHER.md). The leader (or offline play) runs the director automatic
-- weather and the beats below; guests render the same sky from the seeded timeline plus the host state and
-- plume/quake/surge events, which ride the ordered presentation stream like any other event. The events carry
-- no handles, so they bypass the marker label/TTL logic. The director is cosmetic: it never damages, shoves,
-- scrambles or re-teams anything.
local europaStarted, europaAnnounced = false, false

local function InitEuropaWeather()
    europaStarted = true
    local net = CRCoop.IsNetworkGame()
    local authority = (not net) or CRCoop.IsAuthority()
    -- Europa under Jupiter: the sun's real path, a short eclipse, Jupiter-shine at night.
    Environment.Init({ lightingMode = "orbit", orbit = { period = 1800, startHour = -40 } })
    Environment.BindWeatherSensors("Europa", CREuropaWeather)
    CREuropaWeather.Init({
        authority = authority,
        seed = M.europaSeed, -- nil: the leader/offline picks one, guests wait for the host state
        sites = EuropaSites,
        startLevel = 1,
        targetLevel = 1,
        -- The host queues straight onto the stream: its own Present() would apply the event again.
        send = net and function(op, ...)
            events[#events + 1] = { op = op, args = { ... }, n = select("#", ...), ttl = RESOLVE_TIMEOUT }
        end or nil,
    })
    if M.weatherState ~= nil and authority then
        CREuropaWeather.Load(M.weatherState)
        M.weatherState = nil
    end
    if authority then M.europaSeed = CREuropaWeather.Seed end -- survives a save
end

-- Every peer, every frame after the session is ready.
local function UpdateEuropaWeather(dt)
    if not europaStarted then InitEuropaWeather() end
    if CRCoop.IsNetworkGame() and CRCoop.IsAuthority() and not europaAnnounced and CRCoop.IsSessionReady() then
        europaAnnounced = true
        CREuropaWeather.AnnounceState()
    end
    CREuropaWeather.Update(dt)
    Environment.Update(dt)
end

local function ShutdownEuropaWeather()
    if europaStarted then CREuropaWeather.Shutdown() end
    europaStarted, europaAnnounced = false, false
end

-- Victory eases the sky back to calm while the result screen counts down. EndMission has already queued the
-- result; this only nudges the director (leader/offline).
local function SucceedMission(...)
    if (not M.europaCalm) and ((not CRCoop.IsNetworkGame()) or CRCoop.IsAuthority()) then
        M.europaCalm = true
        CREuropaWeather.ReleaseForcedLevel()
        CREuropaWeather.SetTargetLevel(1)
    end
    return EndMission("SucceedMission", ...)
end
-- CR Europa weather <<
-- CR co-op layer >>
local function ConfigureAlliances()
    CRCoop.ApplyCoopAlliances(ENEMY_TEAM)
end

-- Co-op trigger helpers. Offline CRCoop iterates just the local player, so each reproduces the DLL's
-- single-player test exactly. Every distance goes through the mission's MissionDistance guard.
local function AnyPlayerWithin(target, distance)
    return CRCoop.AnyPlayerSatisfies(function(h) return MissionDistance(h, target) < distance end)
end

-- The player closest to `from` (handle, distance), or nil when no player has a usable handle.
local function NearestPlayer(from)
    local best, bestDistance = nil, math.huge
    CRCoop.ForEachPlayerHandle(function(h)
        local distance = MissionDistance(h, from)
        if best == nil or distance < bestDistance then best, bestDistance = h, distance end
    end)
    return best, bestDistance
end

-- Human teams in the session (1 offline): the way misn09-11 size their reinforcements.
local function HumanCount()
    return math.max(1, CRCoop.ForEachHumanTeam(function() end))
end

-- Units of every human team within `radius` of `target`. The DLL counted team 1 only, which in
-- co-op is the host and the shared base; guests fly teams 2-4.
local function HumanUnitsNear(target, radius)
    local total = 0
    CRCoop.ForEachHumanTeam(function(team)
        total = total + (CountUnitsNearObject(target, radius, team, nil) or 0)
    end)
    return total
end
-- CR co-op layer <<
-- CR CCA scaling >>
-- The DLL's CCA is sized for one player. Each extra human team (up to four players) adds one svtank and
-- one svfigh to the opening rush and to every restored reinforcement wave.
local EXTRA_MAX = 3
local function ExtraHumans()
    return math.min(EXTRA_MAX, math.max(0, HumanCount() - 1))
end
-- CR CCA scaling <<
-- CR team filter >>
-- The DLL's AddObject had no team filter. The AIP's bombers/escorts (svapc13, svhr13, svtk13) must be the
-- CCA's (team 5); the player-built structures and craft it targets (abtowe, abcomm, avmuf, avcnst, avscav)
-- must belong to a human team, so an enemy or allied look-alike never takes a tracked slot.
local ENEMY_TRACKED = { "svapc13", "svhr13", "svtk13" }
local HUMAN_TRACKED = { "abtowe", "abcomm", "avmuf", "avcnst", "avscav" }
local function AddObjectTeamAllowed(h)
    if not IsValid(h) then return false end
    local team = GetTeamNum(h)
    if team == nil then return false end
    for _, odf in ipairs(ENEMY_TRACKED) do
        if IsOdfBase(h, odf) then return team == ENEMY_TEAM end
    end
    for _, odf in ipairs(HUMAN_TRACKED) do
        if IsOdfBase(h, odf) then return CRCoop.IsHumanTeam(team) end
    end
    return true
end
-- CR team filter <<
-- CR win >>
-- The DLL won when the Unit Factory fell. The briefing (misn13cr.mpdes) asks for the whole CCA base and every
-- escape hatch / supply line: the Unit Factory, the hangar (map label svguntower2, an sbhang) and all four
-- silos. The silo scrap clamp and the factory's +40 scrap under attack are the DLL's and stay.
local SILO_COUNT = 4
local function SilosDestroyed()
    local dead = 0
    for i = 1, SILO_COUNT do
        if not IsAlive(M["ccasilo" .. i]) then dead = dead + 1 end
    end
    return dead
end

local function CCABaseDestroyed()
    return (not IsAlive(M.ccamuf)) and (not IsAlive(M.hangar)) and SilosDestroyed() == SILO_COUNT
end
-- CR win <<
-- CR objectives >>
-- The stock objective (misn1300.otf: "Destroy soviet Unit Factory / Defend your Recycler") no longer
-- describes the win, so the leader replaces it with a progress list that every peer shows.
local OBJECTIVE_SECONDS = 8.0
local function ObjectiveLines()
    local silos = SilosDestroyed()
    return {
        { "misn13_recycler", IsAlive(M.nsdfrecycle) and "white" or "red", "Defend your Recycler" },
        { "misn13_factory", IsAlive(M.ccamuf) and "white" or "green", "Destroy the CCA Unit Factory" },
        { "misn13_hangar", IsAlive(M.hangar) and "white" or "green", "Destroy the CCA hangar" },
        { "misn13_silos", silos >= SILO_COUNT and "green" or "white",
            "Destroy the CCA silos (" .. silos .. "/" .. SILO_COUNT .. ")" },
    }
end

local function UpdateObjectives()
    if not M.start_done then return end
    local lines = ObjectiveLines()
    if not M.objectives_added then
        M.objectives_added = true
        ClearObjectives()
        M.objective_state = {}
        for _, line in ipairs(lines) do
            AddObjective(line[1], line[2], OBJECTIVE_SECONDS, line[3])
            M.objective_state[line[1]] = line[2] .. "|" .. line[3]
        end
        return
    end
    for _, line in ipairs(lines) do
        local state = line[2] .. "|" .. line[3]
        if M.objective_state[line[1]] ~= state then
            M.objective_state[line[1]] = state
            UpdateObjective(line[1], line[2], OBJECTIVE_SECONDS, line[3])
        end
    end
end
-- CR objectives <<
-- CR cut VO >>
-- misn1301 (Collins: you provoked the CCA army, the Texas is the finest Recycler in the fleet, use her to
-- build a base and take out that Unit Factory) is unused in the DLL. It plays once, COLLINS_DELAY_S after
-- the first attack, i.e. after the 22 s opening briefing (misn1300) has ended.
local COLLINS_DELAY_S = 25.0
local function UpdateCollins()
    if M.collins_done or not M.first_wave then return end
    if M.collins_time == 99999.0 then M.collins_time = GetTime() + COLLINS_DELAY_S end
    if GetTime() > M.collins_time and not M.game_over then
        M.collins_done = true
        AudioMessage("misn1301.wav")
    end
end
-- CR cut VO <<
-- CR restored waves >>
-- The DLL declares reinforcement waves 2-4 (wave2/3/4, *_done, *_move, next_wave_time +300 s at the start,
-- the unused spawn_geyser1/2, choke_point2/3 and turret_path3) and never uses them. They are restored here
-- behind RESTORED_WAVES: every WAVE_PERIOD_S a CCA squad is built at a spawn geyser, drives to a choke point,
-- then along turret_path3 toward the east tower, and finally attacks the Recycler (the DLL's own first-wave
-- target). Each extra human adds one svtank and one svfigh. Waves stop when the Unit Factory is gone and
-- wait while WAVE_LIVE_CAP reinforcement units are alive.
local RESTORED_WAVES = true
local WAVE_PERIOD_S, WAVE_RETRY_S, WAVE_LIVE_CAP = 300.0, 30.0, 16
local WAVE_POLL_S, WAVE_ARRIVE_M = 2.0, 150.0
local WAVE_CHOKE_TIMEOUT_S, WAVE_PATH_TIMEOUT_S = 120.0, 240.0
local WAVE_ROUTE_PATH = "turret_path3"
-- No pop-in: a squad is only built where no human is within WAVE_CLEAR_M (misn13.trn VisibilityRange is 250,
-- so the spawn is past the fog). A blocked geyser falls back to the other one; if both are watched the wave
-- waits WAVE_RETRY_S and tries again.
local WAVE_CLEAR_M = 400.0
local WAVES = {
    { flag = "wave2", move = "wave2_move", done = "wave2_done", spawn = "spawn_point1", choke = "choke_point3",
      odfs = { "svtank", "svtank", "svfigh" } },
    { flag = "wave3", move = "wave3_move", done = "wave3_done", spawn = "spawn_point2", choke = "choke_point2",
      odfs = { "svtank", "svtank", "svfigh", "svfigh" } },
    { flag = "wave4", move = "wave4_move", done = "wave4_done", spawn = "spawn_point2", choke = "choke_point3",
      odfs = { "svtank", "svtank", "svtank", "svfigh", "svfigh" } },
}

local function WaveLead(index)
    for _, unit in ipairs(M.wave_units[index] or {}) do
        if IsAlive(unit) then return unit end
    end
end

local function LiveWaveUnits()
    local total = 0
    for _, units in pairs(M.wave_units) do
        for _, unit in ipairs(units) do
            if IsAlive(unit) then total = total + 1 end
        end
    end
    return total
end

-- The first of `candidates` (handles or path names) that exists and has no human within WAVE_CLEAR_M.
local function UnwatchedSpawn(candidates)
    for _, where in ipairs(candidates) do
        if type(where) == "string" or IsValid(where) then
            local _, distance = NearestPlayer(where)
            if distance >= WAVE_CLEAR_M then return where end
        end
    end
end

local function SpawnWave(index)
    local wave = WAVES[index]
    local other = (wave.spawn == "spawn_point1") and "spawn_point2" or "spawn_point1"
    local where = UnwatchedSpawn({ M[wave.spawn], M[other] })
    if where == nil then return false end
    local odfs = {}
    for _, odf in ipairs(wave.odfs) do odfs[#odfs + 1] = odf end
    for _ = 1, ExtraHumans() do
        odfs[#odfs + 1] = "svtank"
        odfs[#odfs + 1] = "svfigh"
    end
    local units = {}
    for _, odf in ipairs(odfs) do
        local unit = BuildObject(odf, ENEMY_TEAM, where)
        units[#units + 1] = unit
        Goto(unit, wave.choke, 1)
    end
    M.wave_units[index] = units
    M.wave_time[index] = GetTime()
    M[wave.flag] = true
    return true
end

local function WaveTarget()
    if IsAlive(M.nsdfrecycle) then return M.nsdfrecycle end
    return NearestPlayer(M.ccamuf)
end

local function UpdateWaves()
    if not RESTORED_WAVES or not M.start_done or M.game_over then return end
    local now = GetTime()
    -- Spawn: the DLL's next_wave_time is the schedule.
    local index
    for i = 1, #WAVES do
        if not M[WAVES[i].flag] then index = i; break end
    end
    if index == nil then
        M.next_wave_time = 99999.0
    elseif M.next_wave_time < now and IsAlive(M.ccamuf) then
        if LiveWaveUnits() >= WAVE_LIVE_CAP or not SpawnWave(index) then
            M.next_wave_time = now + WAVE_RETRY_S
        else
            M.next_wave_time = now + WAVE_PERIOD_S
        end
    end
    -- Orders: choke point -> turret_path3 -> the Recycler.
    if now < M.wave_poll then return end
    M.wave_poll = now + WAVE_POLL_S
    for i, wave in ipairs(WAVES) do
        if M[wave.flag] and not M[wave.done] then
            local lead = WaveLead(i)
            if lead == nil then
                M[wave.done] = true
            elseif not M[wave.move] then
                if MissionDistance(lead, wave.choke) < WAVE_ARRIVE_M or now - M.wave_time[i] > WAVE_CHOKE_TIMEOUT_S then
                    for _, unit in ipairs(M.wave_units[i]) do
                        if IsAlive(unit) then Goto(unit, WAVE_ROUTE_PATH, 1) end
                    end
                    M[wave.move] = true
                    M.wave_time[i] = now
                end
            elseif MissionDistance(lead, M.checkpoint1) < WAVE_ARRIVE_M * 1.5 or now - M.wave_time[i] > WAVE_PATH_TIMEOUT_S then
                local target = WaveTarget()
                if target ~= nil then
                    for _, unit in ipairs(M.wave_units[i]) do
                        if IsAlive(unit) then Attack(unit, target, 1) end
                    end
                end
                M[wave.done] = true
            end
        end
    end
end

-- The opening rush: one svtank and one svfigh per extra human join the DLL's first attack.
local function UpdateRushExtras()
    if M.rush_extras or not M.first_wave then return end
    if ExtraHumans() == 0 then M.rush_extras = true; return end
    -- Same no-pop-in rule as the waves; if every point is watched, try again next tick.
    local where = UnwatchedSpawn({ "choke_point1", M.spawn_point2, M.spawn_point1 })
    if where == nil then return end
    M.rush_extras = true
    for _ = 1, ExtraHumans() do
        Attack(BuildObject("svtank", ENEMY_TEAM, where), M.nsdfrecycle, 1)
        Attack(BuildObject("svfigh", ENEMY_TEAM, where), M.nsdfrecycle, 1)
    end
end
-- CR restored waves <<
-- CR escort >>
-- Three CCA tanks stand on DEFEND beside the four artillery pieces in the map. They escort the march: they
-- take the same artil_path1 as the artillery (and the DLL's escort_tank), then each follows a howitzer
-- (the first living one if its own is dead) once the artillery splits at the geyser.
local ESCORT_POLL_S = 5.0
local function UpdateEscorts()
    for i, unit in ipairs(M.escorts) do
        if IsAlive(unit) then
            if not M.escort_defend then Defend(unit) end
            if M.artil_move and not M.escort_march[i] then
                M.escort_march[i] = true
                Retreat(unit, "artil_path1")
            end
        end
    end
    M.escort_defend = true
    if not M.artil_move2 or GetTime() < M.escort_next then return end
    M.escort_next = GetTime() + ESCORT_POLL_S
    for i, unit in ipairs(M.escorts) do
        if IsAlive(unit) then
            local leader = M["artil" .. i]
            if not IsAlive(leader) then
                for n = 1, 4 do
                    if IsAlive(M["artil" .. n]) then leader = M["artil" .. n]; break end
                end
            end
            if IsAlive(leader) and M.escort_order[i] ~= leader then
                M.escort_order[i] = leader
                Follow(unit, leader)
            end
        end
    end
end
-- CR escort <<
-- CR reserve >>
-- Two more CCA tanks idle beside the artillery pad in the map, frozen mid-"get bomb" (AI command 14 in the
-- snapshot; the DLL never orders them and no bomb exists on this map). They are the factory reserve: they
-- guard, race to the Unit Factory when it is attacked and to silo_spot when a silo is, hold the spot, and
-- return to guard after RESERVE_HOLD_S so a later alarm calls them again.
local RESERVE_ARRIVE_M, RESERVE_HOLD_S = 60.0, 90.0
local function UpdateReserve()
    local now = GetTime()
    for i, unit in ipairs(M.reserves) do
        if IsAlive(unit) then
            local state = M.reserve_state[i]
            if state == nil then
                Defend(unit)
                M.reserve_state[i] = "guard"
            elseif state == "guard" then
                if M.muf_attacked and IsAlive(M.ccamuf) then
                    Goto(unit, M.ccamuf, 1)
                    M.reserve_state[i] = "muf"
                elseif M.silos_attacked then
                    Goto(unit, "silo_spot", 1)
                    M.reserve_state[i] = "silo"
                end
            elseif state == "muf" or state == "silo" then
                local arrived = state == "muf" and MissionDistance(unit, M.ccamuf) < RESERVE_ARRIVE_M
                    or state == "silo" and MissionDistance(unit, "silo_spot") < RESERVE_ARRIVE_M
                if state == "muf" and not IsAlive(M.ccamuf) then arrived = true end
                if arrived then
                    Defend(unit)
                    M.reserve_state[i] = "held"
                    M.reserve_time[i] = now
                end
            elseif state == "held" and now - M.reserve_time[i] >= RESERVE_HOLD_S then
                M.reserve_state[i] = "guard"
            end
        end
    end
end
-- CR reserve <<
-- CR GetWhoShotMe >>
-- misn1302 (artillery is shelling you) fired only for the first player's recycler/factory/scavengers. It now
-- also fires when a tracked howitzer shoots any human's craft.
local function ArtilleryShot(target)
    if not IsAlive(target) then return false end
    local shooter = GetWhoShotMe(target)
    if shooter == nil or shooter == 0 then return false end
    return M.artil1 == shooter or M.artil2 == shooter or M.artil3 == shooter or M.artil4 == shooter
end

local function UpdateArtilleryWarning()
    if not M.artil_move2 or M.artil_message then return end
    CRCoop.ForEachPlayerHandle(function(h)
        if not M.artil_message and ArtilleryShot(h) then
            M.artil_message = true
            AudioMessage("misn1302.wav")
        end
    end)
end
-- CR GetWhoShotMe <<
-- CR rally >>
-- Respawns rally at the Texas Recycler. Its loss fails the mission (misn1304), but until the result lands a
-- respawn must not rally at a corpse: drop the rally point and the native MultST spawn (the team-start buoys)
-- takes over.
local rallyDropped = false
local function UpdateRally()
    if rallyDropped then return end
    local recycler = GetHandle("avrecycle")
    if recycler == nil or not IsAlive(recycler) then
        rallyDropped = true
        local respawn = CRCoop.GetRespawn()
        if respawn then respawn.SetRallyPoints({}) end
    end
end
-- CR rally <<
-- CR Europa weather >>
-- Host/offline only, each beat once. The severity ladder follows the battle: 2 at the start -> 3 when the
-- artillery marches (15 minutes in) or the third reinforcement wave lands -> a 60 s level-5 burst, an ice quake
-- and a radiation surge when the CCA Unit Factory falls -> calm on the win (SucceedMission).
local function UpdateEuropaBeats()
    local beats = M.europaBeats
    if beats == nil then beats = {}; M.europaBeats = beats end
    if (not beats.start) and M.start_done then
        beats.start = true
        CREuropaWeather.SetTargetLevel(2)
    end
    if (not beats.siege) and (M.artil_move or M.wave3) then
        beats.siege = true
        CREuropaWeather.SetTargetLevel(3)
    end
    if (not beats.factory) and M.start_done and not IsAlive(M.ccamuf) then
        beats.factory = true
        CREuropaWeather.ForceLevel(5, 60.0, 10.0)
        CREuropaWeather.Quake(FACTORY_QUAKE_STRENGTH, FACTORY_QUAKE_SECONDS)
        CREuropaWeather.Surge(6.0, 0.8)
    end
end
-- CR Europa weather <<
-- CR co-op layer >>
local function InitializeCoop()
    CRCoop.Initialize({
        getLocalPlayerId = function() return exu.GetMyNetID and exu.GetMyNetID() end,
        leaderTeam = LEADER_TEAM, humanTeamMin = 1, humanTeamMax = 4,
        onOutOfLives = function() FailMission(GetTime() + 3.0) end,
        -- The Texas Recycler while it lives; UpdateRally drops the point when it dies.
        rallyPoints = { [0] = "avrecycle" },
    })
    ConfigureAlliances()
    ResetPresentation()
    rallyDropped = false
    ShutdownEuropaWeather()
end

-- Co-op state outside the DLL's serialized fields.
local function InitializeCoopState()
    M.hangar = GetHandle("svguntower2")
    M.escorts = { GetHandle("artil_escort1"), GetHandle("artil_escort2"), GetHandle("artil_escort3") }
    M.reserves = { GetHandle("cca_reserve1"), GetHandle("cca_reserve2") }
    M.escort_march, M.escort_order, M.escort_next, M.escort_defend = {}, {}, 0.0, false
    M.reserve_state, M.reserve_time = {}, {}
    M.wave_units, M.wave_time, M.wave_poll = {}, {}, 0.0
    M.collins_time, M.collins_done = 99999.0, false
    M.rush_extras, M.objectives_added, M.objective_state = false, false, {}
end
-- CR co-op layer <<
-- Keep the source's first-captured slots, including unused sv2/tank8. Reusing
-- dead slots would change later AIP waves; that needs a separate gameplay decision.
local function RegisterObject(h)
    if not IsValid(h) then return end
-- CR team filter >>
    if not AddObjectTeamAllowed(h) then return end
-- CR team filter <<
    if M.sv1 == nil and IsOdfBase(h, "svapc13") then
        M.sv1 = h
    elseif M.sv2 == nil and IsOdfBase(h, "svapc13") then
        M.sv2 = h
    elseif M.sv3 == nil and IsOdfBase(h, "svhr13") then
        M.sv3 = h
    elseif M.sv4 == nil and IsOdfBase(h, "svhr13") then
        M.sv4 = h
    elseif IsOdfBase(h, "abtowe") then
        M.guntower1 = h
    elseif M.controltower == nil and IsOdfBase(h, "abcomm") then
        M.controltower = h
    elseif M.tank5 == nil and IsOdfBase(h, "svtk13") then
        M.tank5 = h
    elseif M.tank6 == nil and IsOdfBase(h, "svtk13") then
        M.tank6 = h
    elseif M.tank7 == nil and IsOdfBase(h, "svtk13") then
        M.tank7 = h
    elseif M.tank8 == nil and IsOdfBase(h, "svtk13") then
        M.tank8 = h
    elseif M.nsdfmuf == nil and IsOdfBase(h, "avmuf") then
        M.nsdfmuf = h
    elseif M.nsdfrig == nil and IsOdfBase(h, "avcnst") then
        M.nsdfrig = h
    elseif M.avscav1 == nil and IsOdfBase(h, "avscav") then
        M.avscav1 = h
    elseif M.avscav2 == nil and IsOdfBase(h, "avscav") then
        M.avscav2 = h
    elseif M.avscav3 == nil and IsOdfBase(h, "avscav") then
        M.avscav3 = h
    end
end

function Start()
-- CR co-op layer >>
    InitializeCoop()
-- CR co-op layer <<
    M = NewState()
    --[=[
/* Here's where you set the values at the start. */
]=]
    M.check = 0
    M.scrap = 100
    M.shot_by = 0
    M.start_done = false
    M.silos_gone = false
    M.turret_move = false
    M.first_wave = false
    M.second_wave = false
    M.artil_move = false
    M.artil_move2 = false
    M.turret1_set = false
    M.turret2_set = false
    M.artil_set = false
    M.wave2 = false
    M.wave2_done = false
    M.wave2_move = false
    M.wave3 = false
    M.wave3_done = false
    M.wave3_move = false
    M.wave4 = false
    M.wave4_done = false
    M.wave4_move = false
    M.a = false
    M.b = false
    M.c = false
    M.d = false
    M.silo1_lost = false
    M.silo2_lost = false
    M.silo3_lost = false
    M.silo4_lost = false
    M.make_bomber = false
    M.bomber_attack = false
    M.new_target = false
    M.bomber_retreat = false
    M.set_aip = false
    M.sv1_wait = false
    M.sv4_wait = false
    M.sv3_wait = false
    M.sv1_reload = false
    M.sv2_reload = false
    M.sv3_reload = false
    M.sv4_reload = false
    M.bomber_reload = false
    M.hold_aip = false
    M.assign_tank1 = false
    M.assign_tank2 = false
    M.assign_tank3 = false
    M.assign_tank4 = false
    M.silos_attacked = false
    M.silo_defend = false
    M.muf_attacked = false
    M.muf_safe = false
    M.turret1_muf = false
    M.turret2_muf = false
    M.turret5_muf = false
    M.turret6_muf = false
    M.choke_bridged = false
    M.artil_lost = true
    M.apc_sent = false
    M.game_over = false
    M.scav_swap = false
    M.artil_message = false
    M.first_wave_time = 99999.0
    M.second_wave_time = 99999.0
    M.next_wave_time = 99999.0
    M.artil_move_time = 99999.0
    M.artil_set_time = 99999.0
    M.set_aip_time = 99999.0
    M.bomber_retreat_time = 99999.0
    M.turret_move_time = 99999.0
    M.new_orders_time = 99999.0
    M.safe_time_check = 99999.0
    M.scrap_check = 60.0
    M.checkpoint1 = GetHandle("svguntower1")
    --[=[
//	checkpoint2 = GetHandle("svcontroltower");
]=]
    M.checkpoint3 = GetHandle("svmuf")
    M.checkpoint4 = GetHandle("svsilo1")
    M.ccasilo1 = GetHandle("svsilo1")
    M.ccasilo2 = GetHandle("svsilo2")
    M.ccasilo3 = GetHandle("svsilo3")
    M.ccasilo4 = GetHandle("svsilo4")
    M.ccamuf = GetHandle("svmuf")
    M.ccaslf = GetHandle("svslf")
    M.ccacom_tower = GetHandle("svcom_tower")
    M.spawn_point1 = GetHandle("spawn_geyser1")
    M.spawn_point2 = GetHandle("spawn_geyser2")
    M.nav1 = GetHandle("apcamr20_camerapod")
    M.turret1 = GetHandle("turret1")
    M.turret2 = GetHandle("turret2")
    M.turret3 = GetHandle("turret3")
    M.turret4 = GetHandle("turret4")
    M.turret5 = GetHandle("turret5")
    M.turret6 = GetHandle("turret6")
    M.artil1 = GetHandle("artil1")
    M.artil2 = GetHandle("artil2")
    M.artil3 = GetHandle("artil3")
    M.artil4 = GetHandle("artil4")
    M.fighter1 = GetHandle("fighter1")
    M.fighter2 = GetHandle("fighter2")
    M.fighter3 = GetHandle("fighter3")
    M.fighter4 = GetHandle("fighter4")
    M.fighter5 = GetHandle("fighter5")
    M.fighter6 = GetHandle("fighter6")
    M.tank1 = GetHandle("tank1")
    M.tank2 = GetHandle("tank2")
    M.tank3 = GetHandle("tank3")
    M.tank4 = GetHandle("tank4")
    M.key_geyser1 = GetHandle("key_geyser1")
    M.key_geyser2 = GetHandle("key_geyser2")
    M.center_geyser = GetHandle("center_geyser")
    M.split_geyser = GetHandle("split_geyser")
    M.nsdfrecycle = GetHandle("avrecycle")
    --[=[
//	ccaapc = GetHandle("svapc");
]=]
    M.svscav1 = GetHandle("svscav1")
    M.svscav2 = GetHandle("svscav2")
    M.svscav3 = GetHandle("svscav3")
    M.svscav4 = GetHandle("svscav4")
    M.svscav5 = nil
    M.svscav6 = nil
    M.svscav7 = nil
    M.svscav8 = nil
    M.sv1 = nil
    M.sv2 = nil
    M.sv3 = nil
    M.sv4 = nil
    M.guntower1 = nil
    M.controltower = nil
    M.tank5 = nil
    M.tank6 = nil
    M.tank7 = nil
    M.tank8 = nil
    M.nsdfmuf = nil
    M.nsdfrig = nil
    M.avscav1 = nil
    M.avscav2 = nil
    M.avscav3 = nil
    M.center = GetHandle("center")
-- CR co-op layer >>
    InitializeCoopState()
    subtit.Initialize()
    missionPda.Init()
-- CR co-op layer <<
    -- LuaMission can report map objects before Start; native Setup preceded
    -- those callbacks. Replay them after Setup so producer handles are retained.
    started = true
    for _, h in ipairs(pendingObjects) do RegisterObject(h) end
    pendingObjects = {}
end

--[=[
// this is the handle thing brad made for me
]=]
function AddObject(h)
-- CR PDA >>
    missionPda.Object(h)
-- CR PDA <<
-- CR Europa weather >>
    if IsValid(h) then
        Environment.OnObjectCreated(h)
        CREuropaWeather.OnObjectCreated(h)
    end
-- CR Europa weather <<
    if started then
        RegisterObject(h)
    else
        pendingObjects[#pendingObjects + 1] = h
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
    missionPda.Update()
    CRCoop.Update()
    UpdatePresentationTransport()
    if M.coopResult or M.coopPendingResult then
-- CR Europa weather >>
        -- The sky keeps easing while the result screen counts down.
        UpdateEuropaWeather(dt)
-- CR Europa weather <<
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
-- CR Europa weather >>
    UpdateEuropaWeather(dt)
-- CR Europa weather <<
    UpdateRally()
    if not CRCoop.IsAuthority() then return end
    if CRCoop.IsNetworkGame() and not M.coopBootstrapped then
        M.coopBootstrapped = true
        -- The authored offline placeholder must not remain beside the humans.
        local offlinePlayer = GetHandle("player0_hover")
        if IsValid(offlinePlayer) and not CRCoop.IsHumanCraft(offlinePlayer) then RemoveObject(offlinePlayer) end
    end
-- CR co-op layer <<
    --[=[
// START OF SCRIPT
]=]
    M.user = GetPlayerHandle()
    --[=[
//assigns the player a handle every frame
]=]
    --[=[
// these are constants
]=]
    if M.bomber_attack then
        if not IsAlive(M.sv1) then
            M.sv1_wait = false
        end
        if not IsAlive(M.sv4) then
            M.sv4_wait = false
        end
        if not IsAlive(M.sv3) then
            M.sv3_wait = false
        end
        if (not IsAlive(M.sv3)) and (not IsAlive(M.sv4)) then
            M.make_bomber = false
            M.bomber_attack = false
            M.new_target = false
            M.bomber_retreat = false
            M.bomber_retreat_time = 99999.0
            M.bomber_reload = false
            --[=[
//			sv1_reload = false;
]=]
            --[=[
//			sv2_reload = false;
]=]
            --[=[
//			sv3_reload = false;
]=]
            --[=[
//			sv4_reload = false;
]=]
        end
    end
    if not IsAlive(M.tank1) then
        M.assign_tank1 = false
    end
    if not IsAlive(M.tank2) then
        M.assign_tank2 = false
    end
    if not IsAlive(M.tank3) then
        M.assign_tank3 = false
    end
    if not IsAlive(M.tank4) then
        M.assign_tank4 = false
    --[=[
// end of constants ///////////////////////////////////////////////////////////////////
]=]
    end
    if not M.start_done then
        AudioMessage("misn1300.wav")
        ClearObjectives()
        AddObjective("misn1300.otf", "white")
        SetPilot(1, 10)
        SetPilot(ENEMY_TEAM, 40)
        SetScrap(1, 40)
        SetScrap(ENEMY_TEAM, 200)
        Defend(M.tank1)
        Defend(M.tank2)
        Defend(M.artil1)
        Defend(M.artil2)
        Defend(M.artil3)
        Defend(M.artil4)
        --[=[
//		Defend(ccaapc);
]=]
        M.escort_tank = BuildObject("svtank", ENEMY_TEAM, M.artil1)
        if M.nav1~=nil then
            SetObjectiveName(M.nav1, "Drop Zone")
        end
        Defend(M.escort_tank)
        M.first_wave_time = GetTime() +5.0
        M.next_wave_time = GetTime() +300.0
        M.artil_move_time = GetTime() + 900.0
        --[=[
// this may move
]=]
        M.start_done = true
    --[=[
// this is going to subtract scrap from the soviets if the silos are destroyed
]=]
    end
    if (not IsAlive(M.ccasilo1)) and (GetScrap(ENEMY_TEAM)> 150) and (not M.silo1_lost) then
        SetScrap(ENEMY_TEAM, 150)
        M.silo1_lost = true
    end
    if (not IsAlive(M.ccasilo2)) and (GetScrap(ENEMY_TEAM)> 150) and (not M.silo1_lost) then
        SetScrap(ENEMY_TEAM, 150)
        M.silo1_lost = true
    end
    if (not IsAlive(M.ccasilo3)) and (GetScrap(ENEMY_TEAM)> 150) and (not M.silo1_lost) then
        SetScrap(ENEMY_TEAM, 150)
        M.silo1_lost = true
    end
    if (not IsAlive(M.ccasilo4)) and (GetScrap(ENEMY_TEAM)> 150) and (not M.silo1_lost) then
        SetScrap(ENEMY_TEAM, 150)
        M.silo1_lost = true
    end
    if (not IsAlive(M.ccasilo1)) and (not IsAlive(M.ccasilo2)) and (GetScrap(ENEMY_TEAM)> 100) and (not M.silo2_lost) then
        SetScrap(ENEMY_TEAM, 100)
        M.silo2_lost = true
    end
    if (not IsAlive(M.ccasilo1)) and (not IsAlive(M.ccasilo3)) and (GetScrap(ENEMY_TEAM)> 100) and (not M.silo2_lost) then
        SetScrap(ENEMY_TEAM, 100)
        M.silo2_lost = true
    end
    if (not IsAlive(M.ccasilo1)) and (not IsAlive(M.ccasilo4)) and (GetScrap(ENEMY_TEAM)> 100) and (not M.silo2_lost) then
        SetScrap(ENEMY_TEAM, 100)
        M.silo2_lost = true
    end
    if (not IsAlive(M.ccasilo2)) and (not IsAlive(M.ccasilo3)) and (GetScrap(ENEMY_TEAM)> 100) and (not M.silo2_lost) then
        SetScrap(ENEMY_TEAM, 100)
        M.silo2_lost = true
    end
    if (not IsAlive(M.ccasilo2)) and (not IsAlive(M.ccasilo4)) and (GetScrap(ENEMY_TEAM)> 100) and (not M.silo2_lost) then
        SetScrap(ENEMY_TEAM, 100)
        M.silo2_lost = true
    end
    if (not IsAlive(M.ccasilo3)) and (not IsAlive(M.ccasilo4)) and (GetScrap(ENEMY_TEAM)> 100) and (not M.silo2_lost) then
        SetScrap(ENEMY_TEAM, 100)
        M.silo2_lost = true
    end
    if (not IsAlive(M.ccasilo1)) and (not IsAlive(M.ccasilo2)) and (not IsAlive(M.ccasilo3)) and (GetScrap(ENEMY_TEAM)> 50) and (not M.silo3_lost) then
        SetScrap(ENEMY_TEAM, 50)
        M.silo3_lost = true
    end
    if (not IsAlive(M.ccasilo1)) and (not IsAlive(M.ccasilo2)) and (not IsAlive(M.ccasilo4)) and (GetScrap(ENEMY_TEAM)> 50) and (not M.silo3_lost) then
        SetScrap(ENEMY_TEAM, 50)
        M.silo3_lost = true
    end
    if (not IsAlive(M.ccasilo1)) and (not IsAlive(M.ccasilo3)) and (not IsAlive(M.ccasilo4)) and (GetScrap(ENEMY_TEAM)> 50) and (not M.silo3_lost) then
        SetScrap(ENEMY_TEAM, 50)
        M.silo3_lost = true
    end
    if (not IsAlive(M.ccasilo2)) and (not IsAlive(M.ccasilo3)) and (not IsAlive(M.ccasilo4)) and (GetScrap(ENEMY_TEAM)> 50) and (not M.silo3_lost) then
        SetScrap(ENEMY_TEAM, 50)
        M.silo3_lost = true
    end
    if (not IsAlive(M.ccasilo1)) and (not IsAlive(M.ccasilo2)) and (not IsAlive(M.ccasilo3)) and (not IsAlive(M.ccasilo4)) and (GetScrap(ENEMY_TEAM)> 0) and (not M.silos_gone) then
        M.silos_gone = true
        SetScrap(ENEMY_TEAM, 0)
    --[=[
// now I'm going to start the battle by sending the turrets to smart locations
]=]
    --[=[
// this immediately sends turrets to key locations
]=]
    end
    if (M.start_done) and (not M.turret_move) then
        Retreat(M.turret1, "turret_path1")
        --[=[
// a scrap field vital to americans
]=]
        Retreat(M.turret2, "turret_path1")
        --[=[
// a scrap field vital to americans
]=]
        Defend(M.turret3)
        --[=[
// the main choke point where americans must come through
]=]
        Defend(M.turret4)
        --[=[
// the main choke point where americans must come through
]=]
        Retreat(M.turret5, "turret_path2")
        --[=[
// the scrap silos
]=]
        Retreat(M.turret6, "turret_path2")
        --[=[
// the scrap silos
]=]
        Goto(M.ccaslf, "slf_path")
        M.turret_move_time = GetTime() + 120.0
        M.turret_move = true
    end
    if (M.turret_move) and (M.turret_move_time < GetTime()) and (not M.silo_defend) then
        M.turret_move_time = GetTime() + 3.0
        if (MissionDistance(M.turret5, M.ccasilo1) < 60.0) and (MissionDistance(M.turret6, M.ccasilo1) < 60.0) then
            Defend(M.turret5)
            Defend(M.turret6)
            M.silo_defend = true
        end
    end
    if (M.turret_move) and (M.turret_move_time < GetTime()) and (not M.turret1_set) then
        if MissionDistance(M.turret1, M.key_geyser1) < 100.0 then
            Goto(M.turret1, M.key_geyser1)
            M.turret1_set = true
        end
    end
    if (M.turret_move) and (M.turret_move_time < GetTime()) and (not M.turret2_set) then
        if MissionDistance(M.turret2, M.key_geyser1) < 100.0 then
            Goto(M.turret2, M.key_geyser2)
            M.turret2_set = true
        end
    --[=[
// sending the tanks that would have been following the player in for the first attack
]=]
    end
    if (M.start_done) and (M.first_wave_time < GetTime()) and (not M.first_wave) then
        Attack(M.tank3, M.nsdfrecycle, 1)
        Attack(M.tank4, M.nsdfrecycle, 1)
        Attack(M.fighter5, M.nsdfrecycle, 1)
        Attack(M.fighter6, M.nsdfrecycle, 1)
        M.second_wave_time = GetTime() + 5.0
        M.first_wave = true
    end
    if (M.first_wave) and (M.second_wave_time < GetTime()) and (not M.second_wave) then
        Goto(M.fighter1, "choke_point1")
        Goto(M.fighter2, "choke_point1")
        Goto(M.fighter3, M.key_geyser1)
        Goto(M.fighter4, M.key_geyser2)
        M.set_aip_time = GetTime() + 60.0
        M.second_wave = true
    end
    if (not M.set_aip) and (M.set_aip_time < GetTime()) and (not M.hold_aip) and (not M.muf_attacked) then
        M.set_aip_time = GetTime() + 240.0
        SetAIP("misn13.aip", ENEMY_TEAM)
        --[=[
//		set_aip = true;
]=]
    --[=[
//	if (set_aip)
]=]
    --[=[
//	{
]=]
    --[=[
//		set_aip = false;
]=]
    --[=[
//	}
]=]
    --[=[
// tank code
]=]
    end
    if (IsAlive(M.tank1)) and (not M.assign_tank1) then
        Follow(M.tank1, M.ccamuf)
        M.assign_tank1 = true
    end
    if (IsAlive(M.tank2)) and (not M.assign_tank2) then
        Follow(M.tank2, M.ccamuf)
        M.assign_tank2 = true
    end
    if (IsAlive(M.tank3)) and (not M.assign_tank3) then
        Follow(M.tank3, M.center)
        M.assign_tank3 = true
    end
    if (IsAlive(M.tank4)) and (not M.assign_tank4) then
        Follow(M.tank4, M.center)
        M.assign_tank4 = true
    --[=[
// this sends the first apc after the player's comtower
]=]
    --[=[
//	if ((IsAlive(controltower)) && (!apc_sent))
]=]
    --[=[
//	{
]=]
    --[=[
//		Attack(ccaapc, controltower, 1);
]=]
    --[=[
//		apc_sent = true;
]=]
    --[=[
//	}
]=]
    --[=[
// this is bomber code ////////////////////////////////////////////////////////////////////////////
]=]
    end
    if ((IsAlive(M.guntower1)) or (IsAlive(M.controltower))) and (not M.make_bomber) and (not M.muf_attacked) then
        SetAIP("misn13a.aip", ENEMY_TEAM)
        M.hold_aip = true
        M.make_bomber = true
    end
    if (M.make_bomber) and (not M.bomber_attack) then
        if (IsAlive(M.sv4)) and (not M.sv4_wait) then
            if IsAlive(M.guntower1) then
                Attack(M.sv4, M.guntower1)
            else
                if IsAlive(M.nsdfmuf) then
                    Attack(M.sv4, M.nsdfmuf)
                else
                    if IsAlive(M.controltower) then
                        Attack(M.sv4, M.controltower)
                    end
                end
                if IsAlive(M.tank5) then
                    Follow(M.tank5, M.sv4)
                end
            end
            M.sv4_wait = true
        end
        if (IsAlive(M.sv1)) and (not M.sv1_wait) then
            if IsAlive(M.controltower) then
                Attack(M.sv1, M.controltower)
            else
                if IsAlive(M.guntower1) then
                    Attack(M.sv1, M.guntower1)
                else
                    if IsAlive(M.nsdfmuf) then
                        Attack(M.sv1, M.nsdfmuf)
                    end
                end
            end
            if IsAlive(M.tank6) then
                Follow(M.tank6, M.sv1)
            end
            M.sv1_wait = true
        end
        if (IsAlive(M.sv3)) and (not M.sv3_wait) then
            if IsAlive(M.guntower1) then
                Attack(M.sv3, M.guntower1)
            else
                if IsAlive(M.nsdfmuf) then
                    Attack(M.sv3, M.nsdfmuf)
                else
                    if IsAlive(M.controltower) then
                        Attack(M.sv3, M.controltower)
                    end
                end
                if IsAlive(M.tank7) then
                    Follow(M.tank7, M.sv3)
                end
            end
            M.sv3_wait = true
        end
    end
    if (M.sv1_wait) and (M.sv3_wait) and (M.sv4_wait) and (not M.bomber_attack) then
        M.hold_aip = false
        --[=[
//		bomber_reload = false;
]=]
        M.bomber_attack = true
    end
    if (M.bomber_attack) and (not IsAlive(M.guntower1)) and (not M.new_target) then
        if IsAlive(M.controltower) then
            if IsAlive(M.sv1) then
                Attack(M.sv1, M.controltower)
            end
            if IsAlive(M.sv3) then
                Attack(M.sv3, M.controltower)
            end
            if IsAlive(M.sv4) then
                Attack(M.sv4, M.controltower)
            end
            M.new_target = true
        else
            if IsAlive(M.nsdfmuf) then
                if IsAlive(M.sv1) then
                    Attack(M.sv1, M.nsdfmuf)
                end
                if IsAlive(M.sv3) then
                    Attack(M.sv3, M.nsdfmuf)
                end
                if IsAlive(M.sv4) then
                    Attack(M.sv4, M.nsdfmuf)
                end
                M.new_target = true
            end
        end
        --[=[
/*			else
			{
				if (IsAlive(sv1))
				{
					Retreat(sv1, ccamuf);
				}
				if (IsAlive(sv3))
				{
					Retreat(sv3, ccamuf);
				}
				if (IsAlive(sv4))
				{
					Retreat(sv4, ccamuf);
				}
			}
*/
]=]
        --[=[
//		bomber_retreat_time = Get_Time() + 15.0f;
]=]
        --[=[
//		bomber_retreat = true;
]=]
    --[=[
/*
	if ((new_target) && ((!IsAlive(controltower)) || (!IsAlive(nsdfmuf))) && (!bomber_retreat))
	{
		if(IsAlive(sv1))
		{
			Retreat(sv1, ccamuf);
		}
//		if(IsAlive(sv2))
//		{
//			Retreat(sv2, ccamuf);
//		}
		if(IsAlive(sv3))
		{
			Retreat(sv3, ccamuf);
		}
		if(IsAlive(sv4))
		{
			Retreat(sv4, ccamuf);
		}
		
		bomber_retreat_time = Get_Time() + 15.0f;
		bomber_retreat = true;
	}

*/
]=]
    --[=[
/*
	if ((bomber_retreat) && (bomber_retreat_time < Get_Time()) && (!bomber_reload))
	{
		bomber_retreat_time = Get_Time() + 15.0f;

		if (GetDistance(user, ccamuf) > 500.0f)
		{
			if ((IsAlive(sv1)) && (GetDistance(sv1, ccamuf) < 100.0f) && (!sv1_reload))
			{
				RemoveObject(sv1);
				sv1 = BuildObject("avhraz", 2, ccamuf);
				AddScrap(2, -2);
				sv1_reload = true;
			}
//			if ((IsAlive(sv2)) && (GetDistance(sv2, ccamuf) < 50.0f) && (!sv2_reload))
//			{
//				RemoveObject(sv2);
//				sv2 = BuildObject("avhraz", 2, ccamuf);
//				AddScrap(2, -2);
//				sv2_reload = true;
//			}
			if ((IsAlive(sv3)) && (GetDistance(sv3, ccamuf) < 100.0f) && (!sv3_reload))
			{
				RemoveObject(sv3);
				sv3 = BuildObject("avhraz", 2, ccamuf);
				AddScrap(2, -2);
				sv3_reload = true;
			}
			if ((IsAlive(sv4)) && (GetDistance(sv4, ccamuf) < 100.0f) && (!sv4_reload))
			{
				RemoveObject(sv4);
				sv4 = BuildObject("avhraz", 2, ccamuf);
				AddScrap(2, -2);
				sv4_reload = true;
			}
		}
*/
]=]
    --[=[
//		if (((sv1_reload) && /*(sv2_reload) && */(sv3_reload) && (sv4_reload)) ||
]=]
    --[=[
//			((!IsAlive(sv1)) && /*(sv2_reload) && */(sv3_reload) && (sv4_reload)) ||
]=]
    --[=[
//			(/*(!IsAlive(sv2)) && */(sv1_reload) && (sv3_reload) && (sv4_reload)) ||
]=]
    --[=[
//			((!IsAlive(sv3)) && (sv1_reload) && /*(sv2_reload) && */(sv4_reload)) ||
]=]
    --[=[
//			((!IsAlive(sv4)) && (sv1_reload) && /*(sv2_reload) && */(sv3_reload)) ||
]=]
    --[=[
//			((!IsAlive(sv1)) && /*(!IsAlive(sv2)) && */(sv3_reload) && (sv4_reload)) ||
]=]
    --[=[
//			((!IsAlive(sv1)) && (!IsAlive(sv3)) && /*(sv2_reload) && */(sv4_reload)) ||
]=]
    --[=[
//			((!IsAlive(sv1)) && (!IsAlive(sv4)) && /*(sv2_reload) && */(sv3_reload)) ||
]=]
    --[=[
//			(/*(!IsAlive(sv2)) && */(!IsAlive(sv3)) && (sv1_reload) && (sv4_reload)) ||
]=]
    --[=[
//			(/*(!IsAlive(sv2)) && */(!IsAlive(sv4)) && (sv1_reload) && (sv3_reload)) ||
]=]
    --[=[
//			((!IsAlive(sv3)) && (!IsAlive(sv4)) && (sv1_reload)/* && (sv2_reload) */) ||
]=]
    --[=[
//			((!IsAlive(sv1)) && /*(!IsAlive(sv2)) && */(!IsAlive(sv3)) && (sv4_reload)) ||
]=]
    --[=[
//			((!IsAlive(sv1)) && /*(!IsAlive(sv2)) && */(!IsAlive(sv4)) && (sv3_reload)) ||
]=]
    --[=[
//			((!IsAlive(sv1)) && (!IsAlive(sv3)) && (!IsAlive(sv4))/* && (sv2_reload) */) ||
]=]
    --[=[
//			(/*(!IsAlive(sv2)) && */(!IsAlive(sv3)) && (!IsAlive(sv4)) && (sv1_reload)))
]=]
    --[=[
//		{
]=]
    --[=[
/*(			if (!IsAlive(sv1))
			{
				Defend(sv1);
			}
			if (!IsAlive(sv2))
			{
				Defend(sv2);
			}
			if (!IsAlive(sv3))
			{
				Defend(sv3);
			}
			if (!IsAlive(sv4))
			{
				Defend(sv4);
			}
*/
]=]
    --[=[
//			make_bomber = false;
]=]
    --[=[
//			bomber_attack = false;
]=]
    --[=[
//			sv1_wait = false;
]=]
    --[=[
//			sv3_wait = false;
]=]
    --[=[
//			sv4_wait = false;
]=]
    --[=[
//			new_target = false;
]=]
    --[=[
//			bomber_retreat = false;
]=]
    --[=[
//			bomber_retreat_time = 99999.0f;
]=]
    --[=[
//			sv1_reload = false;
]=]
    --[=[
//			sv2_reload = false;
]=]
    --[=[
//			sv3_reload = false;
]=]
    --[=[
//			sv4_reload = false;
]=]
    --[=[
//			bomber_reload = true;
]=]
    --[=[
//		}
]=]
    --[=[
//	}
]=]
    --[=[
// end bomber code ////////////////////////////////////////////////////////////////////////////
]=]
    --[=[
// this is what happens if the silos get attacked
]=]
    end
    if (IsAlive(M.ccasilo1)) and (not M.silos_attacked) and (GetHealth(M.ccasilo1) < 0.95) then
        M.new_orders_time = GetTime() + 2.0
        M.silos_attacked = true
    end
    if (IsAlive(M.ccasilo2)) and (not M.silos_attacked) and (GetHealth(M.ccasilo2) < 0.95) then
        M.new_orders_time = GetTime() + 2.0
        M.silos_attacked = true
    end
    if (IsAlive(M.ccasilo3)) and (not M.silos_attacked) and (GetHealth(M.ccasilo3) < 0.95) then
        M.new_orders_time = GetTime() + 2.0
        M.silos_attacked = true
    end
    if (IsAlive(M.ccasilo4)) and (not M.silos_attacked) and (GetHealth(M.ccasilo4) < 0.95) then
        M.new_orders_time = GetTime() + 2.0
        M.silos_attacked = true
    end
    if (M.silos_attacked) and (M.new_orders_time < GetTime()) then
        M.new_orders_time = GetTime() + 120.0
        if IsAlive(M.tank1) then
            Goto(M.tank1, "silo_spot")
        end
        if IsAlive(M.tank2) then
            Goto(M.tank2, "silo_spot")
        end
        if IsAlive(M.tank3) then
            Goto(M.tank3, "silo_spot")
        end
        if IsAlive(M.tank4) then
            Goto(M.tank4, "silo_spot")
        end
        if IsAlive(M.turret1) then
            Goto(M.turret1, "silo_spot")
        end
        if IsAlive(M.turret2) then
            Goto(M.turret2, "silo_spot")
        end
        if IsAlive(M.turret5) then
            Goto(M.turret5, "silo_spot")
        end
        if IsAlive(M.turret6) then
            Goto(M.turret6, "silo_spot")
        end
        if IsAlive(M.tank4) then
            Goto(M.tank4, "silo_spot")
        end
        if (M.bomber_reload) or (M.bomber_attack) then
            if IsAlive(M.sv1) then
                Goto(M.sv1, "silo_spot")
            --[=[
//			if (IsAlive(sv2))
]=]
            --[=[
//			{
]=]
            --[=[
//				Goto(sv2, "silo_spot");
]=]
            --[=[
//			}
]=]
            end
            if IsAlive(M.sv3) then
                Goto(M.sv3, "silo_spot")
            end
            if IsAlive(M.sv4) then
                Goto(M.sv4, "silo_spot")
            end
        end
    --[=[
// this is what happens if the muf is under attack
]=]
    end
    if (IsAlive(M.ccamuf)) and (not M.muf_attacked) and (GetHealth(M.ccamuf) < 0.90) and (not M.muf_safe) then
        if IsAlive(M.turret1) then
            Goto(M.turret1, M.ccamuf)
        end
        if IsAlive(M.turret2) then
            Goto(M.turret2, M.ccamuf)
        end
        if IsAlive(M.turret5) then
            Goto(M.turret5, M.ccamuf)
        end
        if IsAlive(M.turret6) then
            Goto(M.turret6, M.ccamuf)
        end
        AddScrap(ENEMY_TEAM, 40)
        M.safe_time_check = GetTime() + 120.0
        SetAIP("misn13c.aip", ENEMY_TEAM)
        M.muf_attacked = true
    end
    if (M.muf_attacked) and (IsAlive(M.turret1)) and (not M.turret1_muf) and MissionDistance(M.turret1, M.ccamuf) < 60.0 then
        Defend(M.turret1)
        M.turret1_muf = true
    end
    if (M.muf_attacked) and (IsAlive(M.turret2)) and (not M.turret2_muf) and MissionDistance(M.turret2, M.ccamuf) < 60.0 then
        Defend(M.turret2)
        M.turret2_muf = true
    end
    if (M.muf_attacked) and (IsAlive(M.turret5)) and (not M.turret5_muf) and MissionDistance(M.turret5, M.ccamuf) < 60.0 then
        Defend(M.turret5)
        M.turret5_muf = true
    end
    if (M.muf_attacked) and (IsAlive(M.turret6)) and (not M.turret6_muf) and MissionDistance(M.turret6, M.ccamuf) < 60.0 then
        Defend(M.turret6)
        M.turret6_muf = true
    --[=[
// this checks to see of the coast is clear after the muf is attacked
]=]
    end
    if (not M.game_over) and (M.muf_attacked) and (M.safe_time_check < GetTime()) and (not M.muf_safe) and IsAlive(M.ccamuf) then
        -- BUGFIX: do not count units around a destroyed factory. Its destruction
        -- still wins at the source's end-of-update check; live defense is unchanged.
        -- BUGFIX / fidelity: the native line below discards a comparison result.
        -- Lua cannot use a bare comparison as a statement, so omit the no-op.
        -- Do NOT turn it into an assignment: that would delay the original
        -- every-update coast-clear check by up to 60 seconds and alter AIP flow.
        --[=[
        safe_time_check < Get_Time() + 60.0f;
        ]=]
        M.check = HumanUnitsNear(M.ccamuf, 400.0) - (HumanCount() - 1)
        if M.check < 2.0 then
            M.muf_safe = true
            M.muf_attacked = false
        end
    --[=[
// this checks to see if the player has broken through the main chokepoint
]=]
    end
    if (not M.choke_bridged) and (not IsAlive(M.turret3)) and (not IsAlive(M.turret4)) then
        M.choke_bridged = true
    --[=[
// this is the section that moves the first wave of soviet artillery units
]=]
    end
    if (M.artil_move_time < GetTime()) and (not M.artil_move) then
        M.artil_move_time = GetTime() + 10.0
        if IsAlive(M.artil1) then
            Retreat(M.artil1, "artil_path1")
        end
        if IsAlive(M.artil2) then
            Retreat(M.artil2, "artil_path1")
        end
        if IsAlive(M.artil3) then
            Retreat(M.artil3, "artil_path1")
        end
        if IsAlive(M.artil4) then
            Retreat(M.artil4, "artil_path1")
        end
        if IsAlive(M.escort_tank) then
            Retreat(M.escort_tank, "artil_path1")
        end
        M.artil_move = true
    end
    if (M.artil_move) and (M.artil_move_time < GetTime()) and (not M.artil_move2) then
        M.artil_move_time = GetTime() + 5.0
        if MissionDistance(M.artil4, M.split_geyser) < 20.0 then
            if IsAlive(M.artil1) then
                Goto(M.artil1, "artil_point1")
                SetIndependence(M.artil1, 1)
            end
            if IsAlive(M.artil2) then
                Goto(M.artil2, "artil_point2")
                SetIndependence(M.artil2, 1)
            end
            if IsAlive(M.artil3) then
                Goto(M.artil3, "artil_point3")
                SetIndependence(M.artil3, 1)
            end
            if IsAlive(M.artil4) then
                Goto(M.artil4, "artil_point4")
                SetIndependence(M.artil4, 1)
            end
            if IsAlive(M.escort_tank) then
                Follow(M.escort_tank, M.artil1)
            end
            M.artil_set_time = GetTime() + 120.0
            M.artil_move2 = true
        end
    end
    if (M.artil_set_time < GetTime()) and (not M.artil_set) then
        if IsAlive(M.artil1) then
            if IsAlive(M.avscav1) then
                Attack(M.artil1, M.avscav1)
            else
                if IsAlive(M.avscav2) then
                    Attack(M.artil1, M.avscav2)
                else
                    if IsAlive(M.avscav3) then
                        Attack(M.artil1, M.avscav3)
                    end
                end
            end
        end
        if IsAlive(M.artil2) then
            if IsAlive(M.avscav3) then
                Attack(M.artil2, M.avscav3)
            else
                if IsAlive(M.avscav2) then
                    Attack(M.artil2, M.avscav2)
                else
                    if IsAlive(M.avscav1) then
                        Attack(M.artil2, M.avscav1)
                    end
                end
            end
        end
        M.artil_set = true
    end
    if (not IsAlive(M.artil1)) and (not IsAlive(M.artil2)) and (not IsAlive(M.artil3)) and (not IsAlive(M.artil4)) then
        M.artil_lost = true
    end
    if (M.artil_move2) and (not M.artil_message) then
        -- Redux uses nil for no shooter; native code used 0. Check both so
        -- absent artillery handles cannot spuriously match an absent shooter.
        if IsAlive(M.nsdfrecycle) then
            M.shot_by = GetWhoShotMe(M.nsdfrecycle)
            if M.shot_by ~= nil and M.shot_by ~= 0 then
                if (M.artil1 == M.shot_by) or (M.artil2 == M.shot_by) or (M.artil3 == M.shot_by) or (M.artil4 == M.shot_by) then
                    AudioMessage("misn1302.wav")
                    M.artil_message = true
                end
            end
        end
        if (IsAlive(M.nsdfmuf)) and (not M.artil_message) then
            M.shot_by = GetWhoShotMe(M.nsdfmuf)
            if M.shot_by ~= nil and M.shot_by ~= 0 then
                if (M.artil1 == M.shot_by) or (M.artil2 == M.shot_by) or (M.artil3 == M.shot_by) or (M.artil4 == M.shot_by) then
                    AudioMessage("misn1302.wav")
                    M.artil_message = true
                end
            end
        end
        if (IsAlive(M.avscav1)) and (not M.artil_message) then
            M.shot_by = GetWhoShotMe(M.avscav1)
            if M.shot_by ~= nil and M.shot_by ~= 0 then
                if (M.artil1 == M.shot_by) or (M.artil2 == M.shot_by) or (M.artil3 == M.shot_by) or (M.artil4 == M.shot_by) then
                    AudioMessage("misn1302.wav")
                    M.artil_message = true
                end
            end
        end
        if (IsAlive(M.avscav2)) and (not M.artil_message) then
            M.shot_by = GetWhoShotMe(M.avscav2)
            if M.shot_by ~= nil and M.shot_by ~= 0 then
                if (M.artil1 == M.shot_by) or (M.artil2 == M.shot_by) or (M.artil3 == M.shot_by) or (M.artil4 == M.shot_by) then
                    AudioMessage("misn1302.wav")
                    M.artil_message = true
                end
            end
        end
        if (IsAlive(M.avscav3)) and (not M.artil_message) then
            M.shot_by = GetWhoShotMe(M.avscav3)
            if M.shot_by ~= nil and M.shot_by ~= 0 then
                if (M.artil1 == M.shot_by) or (M.artil2 == M.shot_by) or (M.artil3 == M.shot_by) or (M.artil4 == M.shot_by) then
                    AudioMessage("misn1302.wav")
                    M.artil_message = true
                end
            end
        end
    --[=[
// this wakes up the scavengers
]=]
    end
    if (M.scrap_check < GetTime()) and (not M.scav_swap) then
        M.scrap_check = GetTime() + 60.0
        M.scrap = GetScrap(ENEMY_TEAM)
        if M.scrap < 40 then
            -- BUGFIX: a non-null native handle can outlive its scavenger. Build
            -- only from surviving scavengers, avoiding an invalid spawn location
            -- and resurrecting killed units. The timer, scrap threshold, swap
            -- order, and commands for surviving units are exactly as in source.
            if IsAlive(M.svscav1) then
                M.svscav5 = BuildObject("svscav", ENEMY_TEAM, M.svscav1)
                RemoveObject(M.svscav1)
                Goto(M.svscav5, M.center_geyser)
            end
            if IsAlive(M.svscav2) then
                M.svscav6 = BuildObject("svscav", ENEMY_TEAM, M.svscav2)
                RemoveObject(M.svscav2)
                Goto(M.svscav6, M.center_geyser)
            end
            if IsAlive(M.svscav3) then
                M.svscav7 = BuildObject("svscav", ENEMY_TEAM, M.svscav3)
                RemoveObject(M.svscav3)
                Goto(M.svscav7, M.center_geyser)
            end
            if IsAlive(M.svscav4) then
                M.svscav8 = BuildObject("svscav", ENEMY_TEAM, M.svscav4)
                RemoveObject(M.svscav4)
                Goto(M.svscav8, M.center_geyser)
            end
            M.scav_swap = true
        end
    --[=[
// win/loose conditions
]=]
    end
    if (not IsAlive(M.nsdfrecycle)) and (not M.game_over) then
        AudioMessage("misn1304.wav")
        FailMission(GetTime() + 15.0, "misn13f1.des")
        M.game_over = true
    end
    if (not IsAlive(M.ccamuf)) and (not M.game_over) and CCABaseDestroyed() then
        AudioMessage("misn1303.wav")
        SucceedMission(GetTime() + 15.0, "misn13w1.des")
        M.game_over = true
    --[=[
// end of scrap reduction
]=]
    --[=[
// END OF SCRIPT
]=]
    end
-- CR co-op layer >>
    UpdateRushExtras()
    UpdateWaves()
    UpdateEscorts()
    UpdateReserve()
    UpdateArtilleryWarning()
    UpdateCollins()
    UpdateObjectives()
-- CR co-op layer <<
-- CR Europa weather >>
    UpdateEuropaBeats()
-- CR Europa weather <<
end

function Save()
-- CR Europa weather >>
    if europaStarted and ((not CRCoop.IsNetworkGame()) or CRCoop.IsAuthority()) then
        M.weatherState = CREuropaWeather.Save()
    end
-- CR Europa weather <<
    return M
end

function Load(state)
-- CR Europa weather >>
    ShutdownEuropaWeather()
    if Environment.InvalidateRenderer then Environment.InvalidateRenderer() end
-- CR Europa weather <<
    M = state
    started = true
    pendingObjects = {}
end

-- Native declaration/serialization comments (full methods in snapshot).
--[=[
/*
	Misn13Mission
*/
]=]
--[=[
// bools
]=]
--[=[
// floats
]=]
--[=[
// handles
]=]
--[=[
// integers
]=]
--[=[
// init bools
]=]
--[=[
// init floats
]=]
--[=[
// init handles
]=]
--[=[
// init ints
]=]
--[=[
// bools
]=]
--[=[
// floats
]=]
--[=[
// Handles
]=]
--[=[
// ints
]=]
--[=[
// bools
]=]
--[=[
// floats
]=]
--[=[
// Handles
]=]
--[=[
// ints
]=]
