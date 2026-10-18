-- Faithful stock misn10 port for Battlezone 98 Redux / Lua 5.1, with the shared offline +
-- 2-4 player co-op layer of the misn06-09 ports (Docs/MISN10_COOP.md).
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misn10Mission.cpp.
-- Source blob: 1e000fdc8e95fa7c58009b249031bb420c789980.
-- Disabled C++ is retained in place; full source and native serialization are
-- archived in References/Misn10Source/. See Docs/MISN10_SOURCE_PORT.md.
-- Everything the campaign adds lives between "-- CR ... >>" / "-- CR ... <<" marker lines
-- (Tools/Test-Misn10SourceParity.py strips them); each co-op substitution outside the markers
-- is an explicit delta in that test. Offline play reproduces the DLL; only the leader runs the
-- mission body. Requires the stock misn10 map labels, paths, AIPs, OTF/audio.
local M

local function NewState()
    local state = {}
    state.start_done = false
    state.sav_moved = false
    state.base_dead = false
    state.build_tug = false
    state.making_another_tug = false
    state.made_another_tug = false
    state.position1 = false
    state.position2 = false
    state.position3 = false
    state.position4 = false
    state.position5 = false
    state.position6 = false
    state.position7 = false
    state.sav_seized = false
    state.sav_free = false
    state.sav_secure = false
    state.tug_underway1 = false
    state.tug_underway2 = false
    state.tug_underway3 = false
    state.tug_underway4 = false
    state.tug_underway5 = false
    state.tug_underway6 = false
    state.tug_underway7 = false
    state.tug_wait_center = false
    state.tug_wait2 = false
    state.tug_wait3 = false
    state.tug_wait4 = false
    state.tug_wait5 = false
    state.tug_wait6 = false
    state.tug_wait7 = false
    state.tug_wait_base = false
    state.return_to_base = false
    state.tug_after_sav = false
    state.objective_on = false
    state.tug_at_wait_center = false
    state.relic_free = false
    state.new_aipa = false
    state.new_aipb = false
    state.fighters_underway = false
    state.sav_protected = false
    state.turret1_underway = false
    state.turret2_underway = false
    state.turret3_underway = false
    state.turret1_stop = false
    state.turret2_stop = false
    state.artil1_stop = false
    state.artil2_stop = false
    state.artil3_stop = false
    state.artil1_underway = false
    state.artil2_underway = false
    state.artil3_underway = false
    state.got_position = false
    state.fighter1_underway = false
    state.fighter2_underway = false
    state.tank1_follow = false
    state.tank2_follow = false
    state.tank1_stop = false
    state.tank2_stop = false
    state.plan_a = false
    state.plan_b = false
    state.new_sav_built = false
    state.game_over = false
    state.chase_tug = false
    state.sav_warning = false
    state.player_dead = false
    state.quake = false
    state.gech_warning_message = 99999.0
    state.relic_check = 99999.0
    state.build_sav_time = 99999.0
    state.quake_time = 99999.0
    state.build_another_tug_time = 99999.0
    state.fighter_time = 99999.0
    state.artil1_check = 99999.0
    state.artil2_check = 99999.0
    state.artil3_check = 99999.0
    state.turret1_check = 99999.0
    state.turret2_check = 99999.0
    state.next_second = 99999.0
    state.geys1check = 99999.0
    state.user = nil
    state.ccatug = nil
    state.tugger = nil
    state.sav = nil
    state.nav1 = nil
    state.nav2 = nil
    state.nav3 = nil
    state.ccaartil1 = nil
    state.ccaartil2 = nil
    state.ccaartil3 = nil
    state.ccaturret1 = nil
    state.ccaturret2 = nil
    state.ccaturret3 = nil
    state.ccarecycle = nil
    state.ccamuf = nil
    state.nsdfrecycle = nil
    state.ccafighter1 = nil
    state.ccafighter2 = nil
    state.ccatank1 = nil
    state.ccatank2 = nil
    state.post1_geyser = nil
    state.post3_geyser = nil
    state.geys1 = nil
    state.geys2 = nil
    state.geys3 = nil
    state.geys4 = nil
    state.geys5 = nil
    state.geys6 = nil
    state.geys7 = nil
    state.svartil1 = nil
    state.svartil2 = nil
    state.audmsg = 0
    return state
end
M = NewState()

-- EXU Initialization (the co-op layer needs the bundled multiplayer hooks).
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})
local exu = require("exu")
-- Native MultST Init precedes Start. The authored base is the team-1 recycler (Utah, avrecycler), so
-- no human team keeps a starting recycler.
if type(IsNetGame) == "function" and IsNetGame() then
    assert(exu.DisableStartingRecycler and exu.GetMyNetID,
        "misn10 co-op requires the bundled EXU multiplayer hooks")
    exu.DisableStartingRecycler()
end
local subtit = require("ScriptSubtitles")
local CRCoop = require("CRCoop")
local CRWire = require("CRWire")
-- The DLL's CCA is team 2 (a guest slot in co-op): every CCA object, spawn, resource and AIP is team 5.
-- The relic (hvsrb, label "relic") is authored on team 0 (neutral) and stays there: a tug carries cargo
-- of any team (GetTug and the seized/secured test read the *tug's* team).
local LEADER_TEAM, ENEMY_TEAM, SUPPORT_TEAM = 1, 5, 7
-- CR Io weather >>
local CRIoWeather = require("CRIoWeather")
local IoSites = require("CRIoSites10")
local Environment = require("Environment")
local IO_OPS = { IoState = true, IoErupt = true, IoQuake = true }
-- The relic pickup quake (the DLL's cut earthquake block, wired to the weather director).
local PICKUP_QUAKE_STRENGTH, PICKUP_QUAKE_SECONDS = 0.85, 6.0
-- CR Io weather <<
-- CR CCA scaling >>
-- The DLL's CCA is sized for one player. Each extra human team (up to four players) gives it
-- CCA_SCRAP_PER_EXTRA more starting scrap and one more relic-carrier hunter.
local CCA_START_SCRAP, CCA_SCRAP_PER_EXTRA, CCA_EXTRA_MAX = 40, 10, 3
local HUNTER_ODF, HUNTER_SPREAD_M = "svfigh", 25.0
-- CR CCA scaling <<
-- CR tug rebuild >>
-- The DLL's cut tug-rebuild block, restored: a replacement svhaul after the CCA tug dies.
local TUG_REBUILD_DELAY_S, TUG_REBUILD_MAX = 30.0, 2
-- CR tug rebuild <<
-- CR plan B >>
-- The DLL's cut "plan B": once the CCA has its tug and both tanks it swaps to the aggressive misn10b.aip.
local PLAN_B_AIP = "misn10b.aip"
-- CR plan B <<

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
    StartCockpitTimer = StartCockpitTimer, StopCockpitTimer = StopCockpitTimer,
    HideCockpitTimer = HideCockpitTimer,
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

-- Presentation adapter ends. BuildObject invokes AddObject synchronously.

-- CR Io weather >>
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
-- CR Io weather <<

-- The DLL's AudioMessage(file) is the shared radio line: the leader plays it and every peer hears
-- it with its subtitle (Play returns the native audio handle on the leader, nil offline-safe).
local function AudioMessage(file) return subtit.Play(file) end

-- The native AiMission supplies strategic AI. LuaMission must enable it at chunk load, before the
-- engine runs DR_AI_Init: a later SetAIControl (Start runs after it) leaves the team flagged but
-- without an AI team record and crashes the host (misn08 co-op live run). Single chunk-root call.
SetAIControl(ENEMY_TEAM, true)

-- Lua handle/position overloads must not receive an absent object. Infinity
-- keeps missing references outside every proximity trigger without changing
-- any comparison between valid objects.
local function Distance(from, to)
    if from == nil or from == 0 or not IsValid(from) then return math.huge end
    if to == nil or to == 0 or not IsValid(to) then return math.huge end
    return GetDistance(from, to)
end

local function IsOdfBase(h, name)
    return IsValid(h) and (IsOdf(h, name) or IsOdf(h, name .. ".odf"))
end

local function ConfigureAlliances()
    CRCoop.ApplyCoopAlliances(ENEMY_TEAM)
    for team = 1, 4 do
        Ally(team, SUPPORT_TEAM); Ally(SUPPORT_TEAM, team)
    end
    UnAlly(ENEMY_TEAM, SUPPORT_TEAM); UnAlly(SUPPORT_TEAM, ENEMY_TEAM)
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

-- Human teams in the session (1 offline): the way misn07/08/09 size their reinforcements.
local function HumanCount()
    return CRCoop.ForEachHumanTeam(function() end)
end

-- CR team filter >>
-- The DLL's AddObject had no team filter. The CCA's units must be team 5, so an allied or
-- spawned look-alike (or a relic-carrier hunter, see CR CCA scaling) never takes a tracked slot.
local ENEMY_TRACKED = { "svturr", "svartl", "svfigh", "svltnk", "svhaul", "svmuf" }
local function AddObjectTeamAllowed(h)
    if M.spawningHunter then return false end
    local team = GetTeamNum(h)
    for _, odf in ipairs(ENEMY_TRACKED) do
        if IsOdfBase(h, odf) then return team == ENEMY_TEAM end
    end
    return true
end
-- CR team filter <<

-- CR CCA scaling >>
local function CCAExtraCount()
    return math.min(CCA_EXTRA_MAX, math.max(0, HumanCount() - 1))
end

-- One relic-carrier hunter (svfigh) per extra human team, beside the CCA recycler. They are not
-- tracked in the DLL's fighter slots (the AIP's own fighters keep those) and they sit at the base
-- until a human team's tug has the relic, when they join the chase (see the chase block).
local function SpawnHunters()
    M.hunters = M.hunters or {}
    local extra = CCAExtraCount()
    if extra == 0 or not IsAlive(M.ccarecycle) then return end
    SetScrap(ENEMY_TEAM, CCA_START_SCRAP + CCA_SCRAP_PER_EXTRA * extra)
    local base = GetPosition(M.ccarecycle)
    M.spawningHunter = true
    for index = 1, extra do
        local px, pz = base.x + HUNTER_SPREAD_M * index, base.z + HUNTER_SPREAD_M
        local py = GetTerrainHeightAndNormal(SetVector(px, 0.0, pz))
        local unit = BuildObject(HUNTER_ODF, ENEMY_TEAM, SetVector(px, py, pz))
        Defend(unit)
        M.hunters[#M.hunters + 1] = unit
    end
    M.spawningHunter = false
end

-- Hunters join the chase for a human team's tug (called once per carrier).
local function SendHunters(target)
    for _, unit in ipairs(M.hunters or {}) do
        if IsAlive(unit) then Attack(unit, target, 1) end
    end
end
-- CR CCA scaling <<

-- CR tug rebuild >>
-- The DLL's cut block rebuilt the CCA tug TUG_REBUILD_DELAY_S after it died (build_tug,
-- making_another_tug, build_another_tug_time). Restored, at most TUG_REBUILD_MAX times and only
-- while the relic exists and the CCA still has its recycler (else its factory): the AIP's own
-- svhaul replaces a lost tug too, so a replacement the AIP got in first is left alone.
local function UpdateTugRebuild()
    if M.game_over then return end
    local now = GetTime()
    if IsAlive(M.ccatug) then M.build_tug = true end
    if M.build_tug and (not IsAlive(M.ccatug)) and (not M.making_another_tug) and IsAlive(M.sav)
        and (M.tug_rebuilds or 0) < TUG_REBUILD_MAX then
        M.build_another_tug_time = now + TUG_REBUILD_DELAY_S
        M.making_another_tug = true
    end
    if M.making_another_tug and M.build_another_tug_time < now then
        M.making_another_tug = false
        M.build_tug = false
        local factory = IsAlive(M.ccarecycle) and M.ccarecycle or (IsAlive(M.ccamuf) and M.ccamuf or nil)
        if (not IsAlive(M.ccatug)) and factory ~= nil and IsAlive(M.sav) then
            BuildObject("svhaul", ENEMY_TEAM, factory)
            M.tug_rebuilds = (M.tug_rebuilds or 0) + 1
            M.made_another_tug = true
        end
    end
end
-- CR tug rebuild <<

-- CR plan B >>
-- The DLL's cut escalation: tug and both tanks alive -> restock the CCA and load the aggressive AIP.
-- The AIP builds from the CCA recycler/factory with this scrap, so it only helps while the base lives.
local function UpdatePlanB()
    if M.plan_b or M.game_over then return end
    if IsAlive(M.ccatug) and IsAlive(M.ccatank1) and IsAlive(M.ccatank2) then
        SetScrap(ENEMY_TEAM, CCA_START_SCRAP + CCA_SCRAP_PER_EXTRA * CCAExtraCount())
        SetAIP(PLAN_B_AIP, ENEMY_TEAM)
        M.plan_b = true
    end
end
-- CR plan B <<

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
    Environment.BindWeatherSensors("Io", CRIoWeather)
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

-- Host/offline only: the race drives the severity ladder, each beat once.
--   1 calm at the start -> 2 when the race begins (the CCA tug is out) -> 3 when the CCA tug closes
--   on the relic (RACE_CLOSE_M) or anyone first picks the relic up (with the quake) -> a 60 s level-5
--   burst when the carrier nears its destination (CLIMAX_M) -> calm (1) on the win (SucceedMission).
local RACE_CLOSE_M, CLIMAX_M = 400.0, 500.0
local function UpdateIoBeats()
    local beats = M.ioBeats
    if beats == nil then beats = {}; M.ioBeats = beats end
    if (not beats.race) and IsAlive(M.ccatug) then
        beats.race = true
        CRIoWeather.SetTargetLevel(2)
    end
    if (not beats.close) and (M.sav_secure or M.sav_seized
        or (M.sav_free and IsAlive(M.ccatug) and Distance(M.ccatug, M.sav) < RACE_CLOSE_M)) then
        beats.close = true
        CRIoWeather.SetTargetLevel(3)
    end
    if (not beats.burst) and (M.sav_secure or M.sav_seized) and IsAlive(M.tugger) then
        local home = M.sav_seized and M.ccarecycle or M.nsdfrecycle
        if IsAlive(home) and Distance(M.tugger, home) < CLIMAX_M then
            beats.burst = true
            CRIoWeather.ForceLevel(5, 60.0, 10.0)
        end
    end
end

-- The DLL's cut earthquake (StartEarthquake(2.0) on a timer, the quake/quake_time state) restored as a
-- single quake on the FIRST relic pickup by anyone. The director does the engine shake itself
-- (StartEarthquake/UpdateEarthQuake/StopEarthquake on an envelope) and replicates it to every peer.
local function UpdatePickupQuake()
    if M.quake then return end
    if M.sav_secure or M.sav_seized then
        M.quake = true
        M.quake_time = GetTime()
        CRIoWeather.Quake(PICKUP_QUAKE_STRENGTH, PICKUP_QUAKE_SECONDS)
    end
end
-- CR Io weather <<

-- CR rally >>
-- Respawns rally at Utah (avrecycler) while it lives. Its loss fails the mission (misn1004), but
-- until the result lands a respawn must not rally at a corpse: drop the rally point and the
-- native MultST spawn (the player start buoys' team start) takes over.
local rallyDropped = false
local function UpdateRally()
    if rallyDropped then return end
    local utah = GetHandle("avrecycler")
    if utah == nil or not IsAlive(utah) then
        rallyDropped = true
        local respawn = CRCoop.GetRespawn()
        if respawn then respawn.SetRallyPoints({}) end
    end
end
-- CR rally <<

local function InitializeCoop()
    CRCoop.Initialize({
        getLocalPlayerId = function() return exu.GetMyNetID and exu.GetMyNetID() end,
        leaderTeam = LEADER_TEAM, humanTeamMin = 1, humanTeamMax = 4,
        onOutOfLives = function() FailMission(GetTime() + 3.0) end,
        -- Rally at Utah (avrecycler) while it lives; the rally watcher drops the point when it
        -- dies and the native MultST team start takes over.
        rallyPoints = { [0] = "avrecycler" },
    })
    ConfigureAlliances()
    ResetPresentation()
-- CR rally >>
    rallyDropped = false
-- CR rally <<
-- CR Io weather >>
    ShutdownIoWeather()
-- CR Io weather <<
end

-- BUGFIX: native AddObject tests only NULL and never clears these slots here.
-- Lua retains dead handles, so later AIP-built replacements would be ignored.
-- Reset each dead unit's command flags before assigning its replacement. This
-- preserves living-unit selection/order and the existing AIP production flow;
-- it also handles deletion and replacement between two Update callbacks.
local function ResetUnit(slot)
    if slot == "ccatug" then
        for index = 1, 7 do M["tug_underway" .. index] = false end
        for index = 2, 7 do M["tug_wait" .. index] = false end
        M.tug_after_sav = false
        M.return_to_base = false
        M.tug_wait_center = false
        M.tug_wait_base = false
        M.tug_at_wait_center = false
        M.got_position = false
        M.sav_warning = false
        -- Each new carrier needs fresh escort orders; the source leaves the
        -- surviving tanks' old follow flags set after their carrier is lost.
        M.tank1_follow = false
        M.tank2_follow = false
        if M.sav_seized then
            if IsAlive(M.ccatank1) and IsAlive(M.sav) then Goto(M.ccatank1, M.sav) end
            if IsAlive(M.ccatank2) and IsAlive(M.sav) then Goto(M.ccatank2, M.sav) end
            M.sav_seized = false
            M.sav_free = true
        end
    elseif slot == "ccaturret3" then
        -- The third turret otherwise keeps its old underway flag forever.
        M.turret3_underway = false
    else
        local kind, index = string.match(slot, "^cca(%a+)(%d)$")
        if kind == "turret" or kind == "artil" then
            M[kind .. index .. "_underway"] = false
            M[kind .. index .. "_stop"] = false
        elseif kind == "fighter" then
            M["fighter" .. index .. "_underway"] = false
            M.chase_tug = false
        elseif kind == "tank" then
            M["tank" .. index .. "_follow"] = false
            M["tank" .. index .. "_stop"] = false
            M.chase_tug = false
        end
    end
end

local trackedSlots = {
    {"ccatug", "svhaul"},
    {"ccaartil1", "svartl"}, {"ccaartil2", "svartl"}, {"ccaartil3", "svartl"},
    {"ccaturret1", "svturr"}, {"ccaturret2", "svturr"}, {"ccaturret3", "svturr"},
    {"ccafighter1", "svfigh"}, {"ccafighter2", "svfigh"},
    {"ccatank1", "svltnk"}, {"ccatank2", "svltnk"}, {"ccamuf", "svmuf"},
}

function Start()
-- CR co-op layer >>
    InitializeCoop()
-- CR co-op layer <<
    M = NewState()
    --[==[/*
Here's where you set the values at the start.  
*/]==]
    M.start_done = false
    M.sav_moved = false
    M.base_dead = false
    M.player_dead = false
    M.making_another_tug = false
    M.made_another_tug = false
    M.build_tug = false
    M.position1 = false
    M.position2 = false
    M.position3 = false
    M.position4 = false
    M.position5 = false
    M.position6 = false
    M.position7 = false
    M.tug_underway1 = false
    M.tug_underway2 = false
    M.tug_underway3 = false
    M.tug_underway4 = false
    M.tug_underway5 = false
    M.tug_underway6 = false
    M.tug_underway7 = false
    M.tug_after_sav = false
    M.sav_seized = false
    M.sav_free = true
    M.sav_secure = false
    M.return_to_base = false
    M.tug_wait_center = false
    M.tug_wait2 = false
    M.tug_wait3 = false
    M.tug_wait4 = false
    M.tug_wait5 = false
    M.tug_wait6 = false
    M.tug_wait7 = false
    M.tug_wait_base = false
    M.tug_at_wait_center = false
    M.objective_on = false
    M.new_aipa = false
    M.new_aipb = false
    M.relic_free = true
    M.fighters_underway = false
    M.sav_protected = false
    M.turret1_underway = false
    M.turret2_underway = false
    M.turret3_underway = false
    M.turret1_stop = false
    M.turret2_stop = false
    M.artil1_stop = false
    M.artil2_stop = false
    M.artil3_stop = false
    M.got_position = false
    M.fighter1_underway = false
    M.fighter2_underway = false
    M.tank1_follow = false
    M.tank2_follow = false
    M.tank1_stop = false
    M.tank2_stop = false
    M.plan_a = false
    M.plan_b = false
    M.artil1_underway = false
    M.artil2_underway = false
    M.artil3_underway = false
    M.game_over = false
    M.chase_tug = false
    M.sav_warning = false
    M.quake = false
    M.new_sav_built = false
    --temp
    M.gech_warning_message = 99999.0
    M.build_sav_time = 99999.0
    --temp
    M.build_another_tug_time = 99999.0
    M.relic_check = 99999.0
    M.fighter_time = 99999.0
    M.turret1_check = 99999.0
    M.turret2_check = 99999.0
    M.artil1_check = 99999.0
    M.artil2_check = 99999.0
    M.artil3_check = 99999.0
    M.geys1check = 180.0
    M.quake_time = 4.0
    M.next_second = 0
    M.sav = GetHandle("relic")
    M.nav1 = GetHandle("cam1")
    M.nav2 = GetHandle("cam2")
    M.nav3 = GetHandle("cam3")
    M.ccarecycle = GetHandle("svrecycler")
    M.nsdfrecycle = GetHandle("avrecycler")
    M.post1_geyser = GetHandle("post1_geyser")
    M.post3_geyser = GetHandle("post3_geyser")
    M.geys1 = GetHandle("geyser1")
    M.geys2 = GetHandle("geyser2")
    M.geys3 = GetHandle("geyser3")
    M.geys4 = GetHandle("geyser4")
    M.geys5 = GetHandle("geyser5")
    M.geys6 = GetHandle("geyser6")
    M.geys7 = GetHandle("geyser7")
    M.svartil1 = GetHandle("svartil1")
    M.svartil2 = GetHandle("svartil2")
    M.ccatug = nil
    M.ccaartil1 = nil
    M.ccaartil2 = nil
    M.ccaartil3 = nil
    M.ccaturret1 = nil
    M.ccaturret2 = nil
    M.ccaturret3 = nil
    M.ccafighter1 = nil
    M.ccafighter2 = nil
    M.ccatank1 = nil
    M.ccatank2 = nil
    M.ccamuf = GetHandle("svmuf")
    M.tugger = nil
-- CR co-op layer >>
    -- The DLL's Setup precedes AiMission::Load and its AddObject notifications; Redux may create
    -- map objects before Start, so recover the tracked slots now (the duplicate guard keeps this idempotent).
    for h in AllObjects() do
        AddObject(h)
    end
    subtit.Initialize()
-- CR co-op layer <<
end

function AddObject(h)
    if not IsValid(h) then return end
-- CR Io weather >>
    Environment.OnObjectCreated(h)
    CRIoWeather.OnObjectCreated(h)
-- CR Io weather <<
-- CR team filter >>
    if not AddObjectTeamAllowed(h) then return end
-- CR team filter <<
    -- Preserve the native ODF-only admission rule and first vacant slot order.
    -- Duplicate notifications must not occupy two slots with the same unit.
    for _, entry in ipairs(trackedSlots) do
        if M[entry[1]] == h then return end
    end
    for _, entry in ipairs(trackedSlots) do
        local slot, odf = entry[1], entry[2]
        if not IsAlive(M[slot]) and IsOdfBase(h, odf) then
            ResetUnit(slot)
            M[slot] = h
            return
        end
    end
end

function DeleteObject(h)
    -- Compare cached handles only; destroyed-object properties are unsafe here.
    for _, entry in ipairs(trackedSlots) do
        local slot = entry[1]
        if M[slot] == h then
            ResetUnit(slot)
            M[slot] = nil
        end
    end
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
-- CR co-op layer >>
    subtit.Update()
    CRCoop.Update()
    UpdatePresentationTransport()
    if M.coopResult or M.coopPendingResult then
-- CR co-op layer <<
-- CR Io weather >>
        -- The sky keeps easing while the result screen counts down.
        UpdateIoWeather(dt)
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
    UpdateIoWeather(dt)
-- CR Io weather <<
-- CR rally >>
    UpdateRally()
-- CR rally <<
-- CR co-op layer >>
    if not CRCoop.IsAuthority() then return end
    if CRCoop.IsNetworkGame() and not M.coopBootstrapped then
        M.coopBootstrapped = true
        -- The authored offline placeholder must not remain beside the humans.
        local offlinePlayer = GetHandle("player0_hover")
        if IsValid(offlinePlayer) and not CRCoop.IsHumanCraft(offlinePlayer) then RemoveObject(offlinePlayer) end
    end
-- CR co-op layer <<
    --[==[/*
Here is where you put what happens every frame.  
*/]==]
    if (M.sav_free) and (IsAlive(M.sav)) then
        M.tugger = GetTug(M.sav)
        if IsAlive(M.tugger) then
            if GetTeamNum(M.tugger) ~= ENEMY_TEAM then
                M.sav_free = false
                M.sav_secure = true
            else
                M.sav_free = false
                M.sav_seized = true
                M.tugger = M.ccatug
            end
        end
    end
    if (M.sav_secure) and (not IsAlive(M.tugger)) then
        if not M.sav_seized then
            M.sav_free = true
            M.chase_tug = false
            M.got_position = false
            M.sav_secure = false
            M.fighter1_underway = false
            M.fighter2_underway = false
        end
    end
    --[==[/*	if (IsAlive(sav))
	{
		if (IsAlive(ccatug))
		{
			if (HasCargo(ccatug))
			{
				sav_free = false;
				sav_seized = true;
			}
			else
			{
				if (!sav_secure)
				{
					sav_free = true;
					sav_seized = false;
				}
			}
		}

		if (!sav_seized)
		{
			tugger = GetTug(sav);

			if (tugger !=0)
			{
				if (GetTeamNum(tugger) == 1)
				{
					sav_free = false;
					sav_secure = true;
				}
				else
				{
					sav_free = false;
					sav_seized = true;
					tugger = ccatug;
				}
			}
		}

		if ((sav_secure) && (!IsAlive(tugger)))
		{
			if (!sav_seized)
			{
				sav_free = true;
				chase_tug = false;
				got_position = false;
				sav_secure = false;
				fighter1_underway = false;
				fighter2_underway = false;
			}
		}
	}
*/]==]
    if (M.sav_seized) and (not IsAlive(M.ccatug)) then
        if (IsAlive(M.ccatank1)) and (IsAlive(M.sav)) then
            Goto(M.ccatank1, M.sav)
        end
        if (IsAlive(M.ccatank2)) and (IsAlive(M.sav)) then
            Goto(M.ccatank2, M.sav)
        end
        M.sav_seized = false
        M.got_position = false
        M.sav_free = true
    end
    if not IsAlive(M.ccatug) then
        --////////////////////////
        M.tug_underway1 = false
        M.tug_underway2 = false
        M.tug_underway3 = false
        M.tug_underway4 = false
        M.tug_underway5 = false
        M.tug_underway6 = false
        M.tug_underway7 = false
        M.tug_after_sav = false
        --all tug settings reset because the last tug was destroyed
        M.return_to_base = false
        M.tug_wait_center = false
        M.tug_wait2 = false
        M.tug_wait3 = false
        M.tug_wait4 = false
        M.tug_wait5 = false
        M.tug_wait6 = false
        M.tug_wait7 = false
        M.tug_wait_base = false
        M.tug_at_wait_center = false
        M.got_position = false
        M.sav_warning = false
        -- BUGFIX: allow the surviving tanks to follow the next AIP-built tug.
        -- This only resets stale orders after carrier death, preserving the
        -- original escort behavior for every living carrier.
        M.tank1_follow = false
        M.tank2_follow = false
        --////////////////////////
    end
    if (M.sav_seized) and (not M.sav_warning) then
        AudioMessage("misn1005.wav")
        -- the sav is being taken sir
        M.sav_warning = true
    end
    M.user = GetPlayerHandle()
    --assigns the player a handle every frame
    -- constant variables
    if not IsAlive(M.ccaturret1) then
        M.turret1_underway = false
        M.turret1_stop = false
    end
    if not IsAlive(M.ccaturret2) then
        M.turret2_underway = false
        M.turret2_stop = false
    end
    if not IsAlive(M.ccaartil1) then
        M.artil1_stop = false
        M.artil1_underway = false
    end
    if not IsAlive(M.ccaartil2) then
        M.artil2_stop = false
        M.artil2_underway = false
    end
    if not IsAlive(M.ccaartil3) then
        M.artil3_stop = false
        M.artil3_underway = false
    end
    if not IsAlive(M.ccafighter1) then
        M.fighter1_underway = false
        M.chase_tug = false
    end
    if not IsAlive(M.ccafighter2) then
        M.fighter2_underway = false
        M.chase_tug = false
    end
    if not IsAlive(M.ccatank1) then
        M.tank1_follow = false
        M.tank1_stop = false
        M.chase_tug = false
    end
    if not IsAlive(M.ccatank2) then
        M.tank2_follow = false
        M.tank2_stop = false
        M.chase_tug = false
    end
    -- the first thing I want to do is get the position of the sav
    if (IsAlive(M.ccatug)) and (M.sav_free) and (not M.got_position) then
        local route_found = false
        if ((Distance(M.sav, M.geys1)) < (Distance(M.sav, M.geys2))) and ((Distance(M.sav, M.geys1)) < (Distance(M.sav, M.geys3))) and ((Distance(M.sav, M.geys1)) < (Distance(M.sav, M.geys4))) and ((Distance(M.sav, M.geys1)) < (Distance(M.sav, M.geys5))) and ((Distance(M.sav, M.geys1)) < (Distance(M.sav, M.geys6))) and ((Distance(M.sav, M.geys1)) < (Distance(M.sav, M.geys7))) then
            M.position1 = true
            route_found = true
            --
            M.position2 = false
            --
            M.position3 = false
            -- this code gets the position of the relic so I can determine 
            M.position4 = false
            -- which path to send the cca tug down and back
            M.position5 = false
            --
            M.position6 = false
            --
            M.position7 = false
            --
        else
            if ((Distance(M.sav, M.geys2)) < (Distance(M.sav, M.geys1))) and ((Distance(M.sav, M.geys2)) < (Distance(M.sav, M.geys3))) and ((Distance(M.sav, M.geys2)) < (Distance(M.sav, M.geys4))) and ((Distance(M.sav, M.geys2)) < (Distance(M.sav, M.geys5))) and ((Distance(M.sav, M.geys2)) < (Distance(M.sav, M.geys6))) and ((Distance(M.sav, M.geys2)) < (Distance(M.sav, M.geys7))) then
                M.position1 = false
                --
                M.position2 = true
                route_found = true
                --
                M.position3 = false
                -- this code gets the position of the relic so I can determine 
                M.position4 = false
                -- which path to send the cca tug down and back
                M.position5 = false
                --
                M.position6 = false
                --
                M.position7 = false
                --
            else
                if ((Distance(M.sav, M.geys3)) < (Distance(M.sav, M.geys1))) and ((Distance(M.sav, M.geys3)) < (Distance(M.sav, M.geys2))) and ((Distance(M.sav, M.geys3)) < (Distance(M.sav, M.geys4))) and ((Distance(M.sav, M.geys3)) < (Distance(M.sav, M.geys5))) and ((Distance(M.sav, M.geys3)) < (Distance(M.sav, M.geys6))) and ((Distance(M.sav, M.geys3)) < (Distance(M.sav, M.geys7))) then
                    M.position1 = false
                    --
                    M.position2 = false
                    --
                    M.position3 = true
                    route_found = true
                    -- this code gets the position of the relic so I can determine 
                    M.position4 = false
                    -- which path to send the cca tug down and back
                    M.position5 = false
                    --
                    M.position6 = false
                    --
                    M.position7 = false
                    --
                else
                    if (not M.sav_seized) and ((Distance(M.sav, M.geys4)) < (Distance(M.sav, M.geys1))) and ((Distance(M.sav, M.geys4)) < (Distance(M.sav, M.geys2))) and ((Distance(M.sav, M.geys4)) < (Distance(M.sav, M.geys3))) and ((Distance(M.sav, M.geys4)) < (Distance(M.sav, M.geys5))) and ((Distance(M.sav, M.geys4)) < (Distance(M.sav, M.geys6))) and ((Distance(M.sav, M.geys4)) < (Distance(M.sav, M.geys7))) then
                        M.position1 = false
                        --
                        M.position2 = false
                        --
                        M.position3 = false
                        -- this code gets the position of the relic so I can determine 
                        M.position4 = true
                        route_found = true
                        -- which path to send the cca tug down and back
                        M.position5 = false
                        --
                        M.position6 = false
                        --
                        M.position7 = false
                        --
                    else
                        if ((Distance(M.sav, M.geys5)) < (Distance(M.sav, M.geys1))) and ((Distance(M.sav, M.geys5)) < (Distance(M.sav, M.geys2))) and ((Distance(M.sav, M.geys5)) < (Distance(M.sav, M.geys3))) and ((Distance(M.sav, M.geys5)) < (Distance(M.sav, M.geys4))) and ((Distance(M.sav, M.geys5)) < (Distance(M.sav, M.geys6))) and ((Distance(M.sav, M.geys5)) < (Distance(M.sav, M.geys7))) then
                            M.position1 = false
                            --
                            M.position2 = false
                            --
                            M.position3 = false
                            --
                            M.position4 = false
                            -- this code gets the position of the relic so I can determine 
                            M.position5 = true
                            route_found = true
                            -- which path to send the cca tug down and back
                            M.position6 = false
                            --
                            M.position7 = false
                            --
                        else
                            if ((Distance(M.sav, M.geys6)) < (Distance(M.sav, M.geys1))) and ((Distance(M.sav, M.geys6)) < (Distance(M.sav, M.geys2))) and ((Distance(M.sav, M.geys6)) < (Distance(M.sav, M.geys3))) and ((Distance(M.sav, M.geys6)) < (Distance(M.sav, M.geys4))) and ((Distance(M.sav, M.geys6)) < (Distance(M.sav, M.geys5))) and ((Distance(M.sav, M.geys6)) < (Distance(M.sav, M.geys7))) then
                                M.position1 = false
                                --
                                M.position2 = false
                                --
                                M.position3 = false
                                -- this code gets the position of the relic so I can determine 
                                M.position4 = false
                                -- which path to send the cca tug down and back
                                M.position5 = false
                                --
                                M.position6 = true
                                route_found = true
                                --
                                M.position7 = false
                                --
                            else
                                if ((Distance(M.sav, M.geys7)) < (Distance(M.sav, M.geys1))) and ((Distance(M.sav, M.geys7)) < (Distance(M.sav, M.geys2))) and ((Distance(M.sav, M.geys7)) < (Distance(M.sav, M.geys3))) and ((Distance(M.sav, M.geys7)) < (Distance(M.sav, M.geys4))) and ((Distance(M.sav, M.geys7)) < (Distance(M.sav, M.geys5))) and ((Distance(M.sav, M.geys7)) < (Distance(M.sav, M.geys6))) then
                                    M.position1 = false
                                    --
                                    M.position2 = false
                                    --
                                    M.position3 = false
                                    -- this code gets the position of the relic so I can determine 
                                    M.position4 = false
                                    -- which path to send the cca tug down and back
                                    M.position5 = false
                                    --
                                    M.position6 = false
                                    --
                                    M.position7 = true
                                    route_found = true
                                    --
                                end
                            end
                        end
                    end
                end
            end
        end
        -- BUGFIX: every original comparison is strict, so an exact nearest
        -- geyser tie selects no route yet sets got_position permanently. Keep
        -- all unique-nearest decisions above. Only when tied, use the lowest
        -- numbered finite minimum; the same seven lava-avoiding paths apply.
        if not route_found and not M.sav_seized then
            local nearest, shortest = nil, math.huge
            for index = 1, 7 do
                local distance = Distance(M.sav, M["geys" .. index])
                if distance < shortest then nearest, shortest = index, distance end
            end
            if nearest then
                for index = 1, 7 do M["position" .. index] = index == nearest end
                route_found = true
            end
        end
        -- Retry rather than commit an empty route if required map labels are absent.
        M.got_position = route_found
    end
    -- now I'll start the mission
    if not M.start_done then
        AudioMessage("misn1000.wav")
        -- player briefing
        ClearObjectives()
        AddObjective("misn1000.otf", "white")
        SetIndependence(M.svartil1, 1)
        SetIndependence(M.svartil2, 1)
        SetScrap(1, 30)
        SetPilot(1, 10)
        SetScrap(ENEMY_TEAM, 40)
        SetPilot(ENEMY_TEAM, 40)
        SetAIP("misn10.aip", ENEMY_TEAM)
-- CR CCA scaling >>
        SpawnHunters()
-- CR CCA scaling <<
        -- this sets the soviets into action
        --[==[//		build_sav_time = Get_Time() + 120.0f;//temp]==]
        --[==[//		relic_check = Get_Time() + 5.0f;]==]
        M.turret1_check = GetTime() + 19.0
        M.turret2_check = GetTime() + 20.0
        M.artil1_check = GetTime() + 21.0
        M.artil2_check = GetTime() + 22.0
        M.artil3_check = GetTime() + 23.0
        if M.nav1 ~= nil then
            SetObjectiveName(M.nav1, "Relic Site")
        end
        if M.nav2 ~= nil then
            SetObjectiveName(M.nav2, "CCA Base")
        end
        if M.nav3 ~= nil then
            SetObjectiveName(M.nav3, "Drop Zone")
        end
        M.relic_free = true
        M.start_done = true
    end
    if (AnyPlayerWithin(M.sav, 100.0)) and (not M.objective_on) then
        SetObjectiveOn(M.sav)
        SetObjectiveName(M.sav, "Alien Relic")
        M.objective_on = true
    end
    --[==[/*	if ((!quake) && (quake_time < Get_Time()))
	{
		quake_time = Get_Time() + 10.0f;
		StartEarthquake(2.0f);
		quake = true;
	}

	if ((quake) && (quake_time < Get_Time()))
	{
		StopEarthquake();
		quake_time = Get_Time() + 120.0f;
		quake = false;
	}
*/]==]
-- CR Io weather >>
    UpdatePickupQuake()
-- CR Io weather <<
    -- The first thing the soviets do is secure the sav with fighters
    if (M.relic_free) and (IsAlive(M.ccafighter1)) and (not M.fighter1_underway) then
        Follow(M.ccafighter1, M.sav)
        M.fighter1_underway = true
    end
    if (M.relic_free) and (IsAlive(M.ccafighter2)) and (not M.fighter2_underway) then
        Follow(M.ccafighter2, M.sav)
        M.fighter2_underway = true
    end
    -- now that fighters are protecting the sav the soviets position turrets to assist
    if (IsAlive(M.ccaturret1)) and (not M.turret1_underway) then
        Goto(M.ccaturret1, "relic_path1")
        M.turret1_underway = true
    end
    if (IsAlive(M.ccaturret2)) and (not M.turret2_underway) then
        Goto(M.ccaturret2, "relic_path1")
        M.turret2_underway = true
    end
    if (IsAlive(M.ccaturret3)) and (not M.turret3_underway) then
        if (IsAlive(M.ccarecycle)) and (Distance(M.ccaturret3, M.ccarecycle) > 30.0) then
            Defend(M.ccaturret3)
            M.turret3_underway = true
        end
    end
    -- gets the turrets to stop
    if (M.turret1_underway) and (M.turret1_check < GetTime()) then
        M.turret1_check = GetTime() + 3.0
        if (IsAlive(M.ccaturret1)) and (not M.turret1_stop) and (Distance(M.ccaturret1, M.geys1) < 50.0) then
            Defend(M.ccaturret1)
            M.turret1_stop = true
        end
    end
    if (M.turret2_underway) and (M.turret2_check < GetTime()) then
        M.turret2_check = GetTime() + 3.0
        if (IsAlive(M.ccaturret2)) and (not M.turret2_stop) and (Distance(M.ccaturret2, M.geys2) < 50.0) then
            Defend(M.ccaturret2)
            M.turret2_stop = true
        end
    end
    -- now the soviets will check to see if they can change their first aip
    if (IsAlive(M.ccafighter1)) and (IsAlive(M.ccafighter2)) and (IsAlive(M.ccaturret1)) and (IsAlive(M.ccaturret2)) and (not M.plan_a) then
        if GetScrap(ENEMY_TEAM) > 15.0 then
            SetAIP("misn10a.aip", ENEMY_TEAM)
            M.plan_a = true
        end
    end
    --[==[/*	if ((IsAlive(ccatank1)) && (!IsAlive(ccatug)) && (!tank1_stop))
	{
		Stop(ccatank1);
		tank1_stop = true;
	}

	if ((IsAlive(ccatank2)) && (!IsAlive(ccatug)) && (!tank2_stop))
	{
		Stop(ccatank2);
		tank2_stop = true;
	}
*/]==]
    -- now they check to see if they can load their next aip
    --[==[//	if ((IsAlive(ccatug)) && (IsAlive(ccatank1)) ]==]
    --		&& (IsAlive(ccatank2)) && (!plan_b))
    --[==[//	{]==]
    --[==[//		SetScrap(2, 40);]==]
    --[==[//		SetAIP("misn10b.aip");]==]
    --[==[//		plan_b = true;]==]
    --[==[//	}]==]
-- CR plan B >>
    UpdatePlanB()
-- CR plan B <<
    -- this sets the artillery into motion
    if (IsAlive(M.ccaartil1)) and (not M.artil1_underway) then
        Goto(M.ccaartil1, "artil1_path", 1)
        M.artil1_underway = true
    end
    if (IsAlive(M.ccaartil2)) and (not M.artil2_underway) then
        Goto(M.ccaartil2, "artil2_path", 1)
        M.artil2_underway = true
    end
    if (IsAlive(M.ccaartil3)) and (not M.artil3_underway) then
        Goto(M.ccaartil3, "relic_path1")
        M.artil3_underway = true
    end
    -- this is checking to see if the soviet artil has reached it's spot
    if M.artil1_check < GetTime() then
        M.artil1_check = GetTime() + 3.0
        if (IsAlive(M.ccaartil1)) and (not M.artil1_stop) and (Distance(M.ccaartil1, M.post1_geyser) < 20.0) then
            Defend(M.ccaartil1)
            M.artil1_stop = true
        end
    end
    if M.artil2_check < GetTime() then
        M.artil2_check = GetTime() + 3.0
        if (IsAlive(M.ccaartil2)) and (not M.artil2_stop) and (Distance(M.ccaartil2, M.post3_geyser) < 20.0) then
            Defend(M.ccaartil2)
            M.artil2_stop = true
        end
    end
    if M.artil3_check < GetTime() then
        M.artil3_check = GetTime() + 3.0
        if (IsAlive(M.ccaartil3)) and (not M.artil3_stop) and (Distance(M.ccaartil3, M.geys2) < 50.0) then
            Defend(M.ccaartil3)
            M.artil3_stop = true
        end
    end
    --[==[/*
	if ((build_sav_time < Get_Time()) && (!new_sav_built)) //this will be replaced by "sav_free"
	{
		sav = BuildObject ("abstor", 1, geys7);

		tug_underway1 = false;
		tug_underway2 = false;
		tug_underway3 = false;
		tug_underway4 = false;
		tug_underway5 = false;
		tug_underway6 = false;
		tug_underway7 = false;
		tug_after_sav = false;
		tug_wait_center = false;
		tug_wait2 = false;
		tug_wait3 = false;
		tug_wait4 = false;
		tug_wait5 = false;
		tug_wait6 = false;
		tug_wait7 = false;
		tug_wait_base = false;		
		sav_seized = false;
		new_sav_built = true;
	}
*/]==]
    -- hopefully, the following code will build a cca tug every 30 seconds after the last cca tug is destoyed
    --[==[/*
		if ((!build_tug) && (IsAlive(ccarecycle)))
		{
			ccatug = BuildObject("svhaul", 2, ccarecycle);
			build_tug = true;
		}
		
		if ((build_tug) && (!IsAlive(ccatug)) && (!making_another_tug))
		{
			build_another_tug_time = Get_Time() + 30.0f;
			//////////////////////////
			tug_underway1 = false;	//
			tug_underway2 = false;	//
			tug_underway3 = false;	//
			tug_underway4 = false;	//
			tug_underway5 = false;	// 
			tug_underway6 = false;	//
			tug_underway7 = false;	//
			tug_after_sav = false;	//all tug settings reset because the last tug was destroyed
			return_to_base = false;	//
			tug_wait_center = false;//
			tug_wait2 = false;		//
			tug_wait3 = false;		//
			tug_wait4 = false;		//
			tug_wait5 = false;		//
			tug_wait6 = false;		//
			tug_wait7 = false;		//
			tug_wait_base = false;	//
			tug_at_wait_center = false;
			//////////////////////////
			making_another_tug = true;
		}

		if ((making_another_tug) && (build_another_tug_time < Get_Time()) && (build_tug))
		{
			making_another_tug = false;
			build_tug = false;
		}
*/]==]
-- CR tug rebuild >>
    UpdateTugRebuild()
-- CR tug rebuild <<
    -- now I'm attempting to send the cca tug to the relic in the smartest path /////////////////////////////////////////////////////////////////////////////////////////////////////////
    -- first I determine where the relic on the map by dertermining which geyser its closest to /////////////////////////////////////////////////////////////////////////////////////////
    -- now that I know which geyser the relic closest to I'll send the cca tug down the appropriate path (to keep it out of the lava fields as much as possible //////////////////////////////
    if (IsAlive(M.ccatug)) and (M.got_position) then
        if (IsAlive(M.ccatank1)) and (not M.tank1_follow) then
            Follow(M.ccatank1, M.ccatug, 1)
            M.tank1_follow = true
        end
        if (IsAlive(M.ccatank2)) and (not M.tank2_follow) then
            Follow(M.ccatank2, M.ccatug, 1)
            M.tank2_follow = true
        end
        if (not M.tug_underway1) and (M.sav_free) and (M.position1) and (not M.tug_after_sav) then
            Goto(M.ccatug, "relic_path1", 1)
            M.tug_underway1 = true
        end
        if (M.tug_underway1) and (M.sav_free) and (Distance(M.ccatug, M.sav) < Distance(M.ccatug, M.geys1)) and (Distance(M.ccatug, M.sav) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            if IsAlive(M.ccatank1) then
                Follow(M.ccatank1, M.ccatug, 0)
            end
            if IsAlive(M.ccatank2) then
                Follow(M.ccatank2, M.ccatug, 0)
            end
            M.tug_after_sav = true
        end
        if (M.tug_underway1) and (M.sav_free) and (Distance(M.ccatug, M.geys1) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.sav_free) and (M.position2) and (not M.tug_underway2) and (not M.tug_after_sav) then
            Goto(M.ccatug, "relic_path1", 1)
            M.tug_underway2 = true
        end
        if (M.tug_underway2) and (M.sav_free) and (Distance(M.ccatug, M.sav) < Distance(M.ccatug, M.geys2)) and (Distance(M.ccatug, M.sav) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.tug_underway2) and (M.sav_free) and (Distance(M.ccatug, M.geys2) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.sav_free) and (M.position3) and (not M.tug_underway3) and (not M.tug_after_sav) then
            Goto(M.ccatug, "attack_path_central", 1)
            M.tug_underway3 = true
        end
        if (M.tug_underway3) and (M.sav_free) and (Distance(M.ccatug, M.sav) < Distance(M.ccatug, M.geys3)) and (Distance(M.ccatug, M.sav) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.tug_underway3) and (M.sav_free) and (Distance(M.ccatug, M.geys3) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.sav_free) and (M.position4) and (not M.tug_underway4) and (not M.tug_after_sav) then
            Goto(M.ccatug, "attack_path_central", 1)
            M.tug_underway4 = true
        end
        if (M.tug_underway4) and (M.sav_free) and (Distance(M.ccatug, M.sav) < Distance(M.ccatug, M.geys4)) and (Distance(M.ccatug, M.sav) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.tug_underway4) and (M.sav_free) and (Distance(M.ccatug, M.geys4) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.sav_free) and (M.position5) and (not M.tug_underway5) and (not M.tug_after_sav) then
            Goto(M.ccatug, "attack_path_south", 1)
            M.tug_underway5 = true
        end
        if (M.tug_underway5) and (M.sav_free) and (Distance(M.ccatug, M.sav) < Distance(M.ccatug, M.geys5)) and (Distance(M.ccatug, M.sav) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.tug_underway5) and (M.sav_free) and (Distance(M.ccatug, M.geys5) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.sav_free) and (M.position6) and (not M.tug_underway6) and (not M.tug_after_sav) then
            Goto(M.ccatug, "attack_path_north", 1)
            M.tug_underway6 = true
        end
        if (M.tug_underway6) and (M.sav_free) and (Distance(M.ccatug, M.sav) < Distance(M.ccatug, M.geys6)) and (Distance(M.ccatug, M.sav) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.tug_underway6) and (M.sav_free) and (Distance(M.ccatug, M.geys6) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.sav_free) and (M.position7) and (not M.tug_underway7) and (not M.tug_after_sav) then
            Goto(M.ccatug, "attack_path_south", 1)
            M.tug_underway7 = true
        end
        if (M.tug_underway7) and (M.sav_free) and (Distance(M.ccatug, M.sav) < Distance(M.ccatug, M.geys7)) and (Distance(M.ccatug, M.sav) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.tug_underway7) and (M.sav_free) and (Distance(M.ccatug, M.geys7) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        -- now that the tug has picked the correct path I'll have the tug pick up the sav and pick a path home //////////////////////////////////
        if (M.tug_after_sav) and (M.tug_underway1) and (M.sav_seized) and (not M.return_to_base) then
            Goto(M.ccatug, "main_return_path", 1)
            M.return_to_base = true
        end
        if (M.tug_after_sav) and (M.tug_underway2) and (M.sav_seized) and (not M.return_to_base) then
            Goto(M.ccatug, M.ccarecycle, 1)
            M.return_to_base = true
        end
        if (M.tug_after_sav) and (M.tug_underway3) and (M.sav_seized) and (not M.return_to_base) then
            Goto(M.ccatug, "lsouth_return_path", 1)
            M.return_to_base = true
        end
        if (M.tug_after_sav) and (M.tug_underway4) and (M.sav_seized) and (not M.return_to_base) then
            Goto(M.ccatug, "main_return_path", 1)
            M.return_to_base = true
        end
        if (M.tug_after_sav) and (M.tug_underway5) and (M.sav_seized) and (not M.return_to_base) then
            Goto(M.ccatug, "ssouth_return_path", 1)
            M.return_to_base = true
        end
        if (M.tug_after_sav) and (M.tug_underway6) and (M.sav_seized) and (not M.return_to_base) then
            Goto(M.ccatug, "main_return_path", 1)
            M.return_to_base = true
        end
        if (M.tug_after_sav) and (M.tug_underway7) and (M.sav_seized) and (not M.return_to_base) then
            Goto(M.ccatug, "msouth_return_path", 1)
            M.return_to_base = true
        end
    end
    -- this is what happens if the player aquires the relic before the cca and a cca tug exits //////////////////
    if not IsAlive(M.sav) then
        if (M.sav_secure) and (not M.tug_underway1) then
            M.tug_wait_base = true
        end
        if (M.sav_secure) and (M.tug_underway1) then
            M.tug_underway1 = false
            M.tug_wait_center = true
        end
        if (M.sav_secure) and (not M.tug_underway2) then
            M.tug_wait_base = true
        end
    end
    if (M.sav_secure) and (M.tug_underway2) and (Distance(M.ccatug, M.geys2) < 50.0) and (not M.tug_wait2) then
        Goto(M.ccatug, M.geys2, 1)
        M.tug_underway2 = false
        M.tug_wait2 = true
    end
    if (M.sav_secure) and (M.tug_underway2) and (M.tug_after_sav) and (not M.tug_wait2) then
        Goto(M.ccatug, M.geys2, 1)
        M.tug_underway2 = false
        M.tug_after_sav = false
        M.tug_wait2 = true
    end
    if (not IsAlive(M.sav)) and (M.sav_secure) and (not M.tug_underway3) then
        M.tug_wait_base = true
    end
    if (M.sav_secure) and (M.tug_underway3) and (Distance(M.ccatug, M.geys3) < 50.0) and (not M.tug_wait3) then
        Goto(M.ccatug, M.geys3, 1)
        M.tug_underway3 = false
        M.tug_wait3 = true
    end
    if (M.sav_secure) and (M.tug_underway3) and (M.tug_after_sav) and (not M.tug_wait3) then
        Goto(M.ccatug, M.geys3, 1)
        M.tug_underway3 = false
        M.tug_after_sav = false
        M.tug_wait3 = true
    end
    if (not IsAlive(M.sav)) and (M.sav_secure) and (not M.tug_underway4) then
        M.tug_wait_base = true
    end
    if (M.sav_secure) and (M.tug_underway4) and (Distance(M.ccatug, M.geys4) < 50.0) and (not M.tug_wait4) then
        Goto(M.ccatug, M.geys4, 1)
        M.tug_underway4 = false
        M.tug_wait4 = true
    end
    if (M.sav_secure) and (M.tug_underway4) and (M.tug_after_sav) and (not M.tug_wait4) then
        Goto(M.ccatug, M.geys4, 1)
        M.tug_underway4 = false
        M.tug_after_sav = false
        M.tug_wait4 = true
    end
    if (not IsAlive(M.sav)) and (M.sav_secure) and (not M.tug_underway5) then
        M.tug_wait_base = true
    end
    if (M.sav_secure) and (M.tug_underway5) and (Distance(M.ccatug, M.geys5) < 50.0) and (not M.tug_wait5) then
        Goto(M.ccatug, M.geys5, 1)
        M.tug_underway5 = false
        M.tug_wait5 = true
    end
    if (M.sav_secure) and (M.tug_underway5) and (M.tug_after_sav) and (not M.tug_wait5) then
        Goto(M.ccatug, M.geys5, 1)
        M.tug_underway5 = false
        M.tug_after_sav = false
        M.tug_wait5 = true
    end
    if (not IsAlive(M.sav)) and (M.sav_secure) and (not M.tug_underway6) then
        M.tug_wait_base = true
    end
    if (M.sav_secure) and (M.tug_underway6) and (Distance(M.ccatug, M.geys6) < 50.0) and (not M.tug_wait6) then
        Goto(M.ccatug, M.geys6, 1)
        M.tug_underway6 = false
        M.tug_wait6 = true
    end
    if (M.sav_secure) and (M.tug_underway6) and (M.tug_after_sav) and (not M.tug_wait6) then
        Goto(M.ccatug, M.geys6, 1)
        M.tug_underway6 = false
        M.tug_after_sav = false
        M.tug_wait6 = true
    end
    if (not IsAlive(M.sav)) and (M.sav_secure) and (not M.tug_underway7) then
        M.sav_seized = true
        M.tug_wait_base = true
    end
    if (M.sav_secure) and (M.tug_underway7) and (Distance(M.ccatug, M.geys7) < 50.0) and (not M.tug_wait7) then
        Goto(M.ccatug, M.geys7, 1)
        M.tug_underway7 = false
        M.tug_wait7 = true
    end
    if (M.sav_secure) and (M.tug_underway7) and (M.tug_after_sav) and (not M.tug_wait7) then
        Goto(M.ccatug, M.geys7, 1)
        M.tug_underway7 = false
        M.tug_after_sav = false
        M.tug_wait7 = true
    end
    -- this is going to make the cca go after the american tug
    -- BUGFIX: C++ only checks tugger != 0, but assigns the Soviet tug to
    -- tugger on CCA pickup. Priority-1 Attack can then make the CCA shoot its
    -- own carrier. Require a living team-1 carrier for the intended American
    -- tug pursuit. The original pursuit orders, priorities, and timing remain
    -- unchanged for player pickup; nil is also excluded (nil ~= 0 in Lua).
    if M.sav_secure and IsAlive(M.tugger) and CRCoop.IsHumanTeam(GetTeamNum(M.tugger))
        and not M.chase_tug then
        if IsAlive(M.ccafighter1) then
            Attack(M.ccafighter1, M.tugger, 1)
        end
        if IsAlive(M.ccafighter2) then
            Attack(M.ccafighter2, M.tugger, 1)
        end
        if IsAlive(M.ccatank1) then
            Attack(M.ccatank1, M.tugger, 1)
        end
        if IsAlive(M.ccatank2) then
            Attack(M.ccatank2, M.tugger, 1)
        end
        if IsAlive(M.svartil1) then
            Attack(M.svartil1, M.tugger, 1)
        end
        if IsAlive(M.svartil2) then
            Attack(M.svartil2, M.tugger, 1)
        end
        if IsAlive(M.ccaartil1) then
            Attack(M.ccaartil1, M.tugger, 1)
        end
        if IsAlive(M.ccaartil2) then
            Attack(M.ccaartil2, M.tugger, 1)
        end
        if IsAlive(M.ccaartil3) then
            Attack(M.ccaartil3, M.tugger, 1)
        end
-- CR CCA scaling >>
        SendHunters(M.tugger)
-- CR CCA scaling <<
        M.chase_tug = true
    end
    -- this make the artil sheel the relic
    if (M.geys1check < GetTime()) and (not M.chase_tug) then
        M.geys1check = GetTime() + 150.0
        local nearest, nearestDistance = NearestPlayer(M.geys1)
        if nearest ~= nil and nearestDistance < 200.0 then
            if IsAlive(M.svartil1) then
                Attack(M.svartil1, nearest)
            end
            if IsAlive(M.svartil2) then
                Attack(M.svartil2, nearest)
            end
        else
            if IsAlive(M.svartil1) then
                Attack(M.svartil1, M.geys1)
            end
            if IsAlive(M.svartil2) then
                Attack(M.svartil2, M.geys1)
            end
        end
    end
    -- this is making sure the sav doesn't die
    if IsAlive(M.sav) then
        if GetTime() > M.next_second then
            AddHealth(M.sav, 100.0)
            M.next_second = GetTime() + 1.0
        end
    end
-- CR Io weather >>
    UpdateIoBeats()
-- CR Io weather <<
    -- win/victory conditions ////////////////////////////////////////////
    if (M.sav_secure) and (Distance(M.sav, M.nsdfrecycle) < 100.0) and (not M.game_over) then
        AudioMessage("misn1001.wav")
        --well done
        SucceedMission(GetTime() + 15.0, "misn10w1.des")
        M.game_over = true
    end
    if (M.sav_seized) and (not M.game_over) and (Distance(M.sav, M.ccarecycle) < 100.0) then
        AudioMessage("misn1002.wav")
        -- you lost
        FailMission(GetTime() + 15.0, "misn10f1.des")
        M.game_over = true
    end
    if (not IsAlive(M.sav)) and (not M.game_over) then
        AudioMessage("misn1003.wav")
        -- we lost the sav
        FailMission(GetTime() + 15.0, "misn10f2.des")
        M.game_over = true
    end
    if (not IsAlive(M.nsdfrecycle)) and (not M.game_over) then
        AudioMessage("misn1004.wav")
        -- we lost the Utah
        FailMission(GetTime() + 15.0, "misn10f3.des")
        M.game_over = true
    end
    -- END OF SCRIPT
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
-- CR Io weather >>
    ShutdownIoWeather()
    if Environment.InvalidateRenderer then Environment.InvalidateRenderer() end
-- CR Io weather <<
    M = state
end
