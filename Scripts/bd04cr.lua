-- BlackDog04Mission.cpp faithfully ported to stock BZR 2.1+ / Lua 5.1.
-- Source: GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/BlackDog04Mission.cpp
-- Source blob: d3d0ee442c4140050186402965d851e19a5ea7a1.
-- Complete native source, including every comment and serialization member:
-- References/BlackDog04Source/BlackDog04Mission.cpp. No EXU/helper dependency.
-- Original zero-based arrays, update order, priorities, timers, and unused
-- members are retained. Attach as the Lua mission for the original bd04 map.

-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/BDMISN04_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Ganymede weather); outside it this file is
-- the faithful port above, byte for byte (Tools/Test-Bdmisn04CoopSourceParity.py).
-- CR co-op layer <<
local function NewState()
    return {
        startDone = false,
        cameraReady = {[0] = false, false, false},
        cameraComplete = {[0] = false, false, false},
        gotoScav = false,
        objective1Complete = false, objective2Complete = false,
        objective3Complete = false,
        inBaseArea = false, doAttack = false, startAttack = false,
        outOfScav = false, fightersSpawned = false, trigger1 = false,
        idFragment = false, gotFragment = false,
        returnAttack = {[0] = false, false, false, false},
        lost = false, won = false,
        cameraCompleteDelay = 999999.9, getInScavTimeout = 999999.0,
        portalCamTime = 999999.9, portalOffTime = 999999.9,
        portalUnitTime = {[0] = 999999.9, 999999.9},
        portalSoundTime = 99999.0, inBaseSoundTime = 999999.9,
        sound4Time = 99999.0, bomberTime = 999999.9,
        turret = {}, portalUnit = {},
        -- Native handles and audio IDs start null; Lua represents them as nil:
        -- user, lastUser, pilot, nav1/2, silo, portal, fragment, navBeacon,
        -- hauler, scav1/2/3, scavMessage, introSound, sound4/5/6,
        -- portalSound, congrats, inBaseSound1/2.
        timeoutWarningStarted = false, dropZoneReady = false,
    }
end

local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/BDMISN04_COOP.md lists every wrapped call and restoration.
-- Each RESTORED_* flag switches one restoration off (Docs/BDMISN04_COOP.md, "Restored content").
local RESTORED_USER_TARGET = true -- the two cut SetUserTarget(navBeacon) lines
local RESTORED_VOICE_LINES = true -- the unused shipped line bd04009
local Restored = {}
-- The Chinese craft the body sends at the hauler become concealed, head-count-scaled tickets. The two portal
-- fighters of the opening film (BuildObjectAtPortal) are stage props and stay direct.
local SCALED_ODFS = { cvfigh = true, cvfighg = true, cvtnk = true }
-- IsInfo is local UI state: guests report it to the host (Restored.RelayInfo), the host keeps it for a second.
local INFO_PREFIXES = { cbport = true, obdataa = true }
local remoteInfo = {}
if not CR_TEST_FAITHFUL then require("RequireFix").Initialize({"campaignReimagined", "3686673790"}) end -- the asset searcher cuts module names to 11 chars
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "bdmisn04", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2,
    rallyPoints = { [0] = "pilot" }, -- no base in this mission: respawn at the crater rim where everyone starts
    scaledOdfs = SCALED_ODFS,
    liveCap = 26, -- the extraction strike is 15 primaries; four humans add two extras to each of its four groups
    -- A group whose entry has a human within 460 m comes from the next hidden Chinese approach instead.
    fallbackEntries = { "chinese_scout_x6_spawn_point", "attack_2", "attack_3", "return_2", "return_4", "return_3",
        "return_1", "attack_1" },
    failDes = "bd04lose.des",
    wonFlags = { "won" },
    endedFlags = { "won", "lost" },
    -- Local-only engine state (hide, perceived team, portal, user target) runs on every peer through the stream.
    presentationOps = {
        BD4Hide = function(on) Restored.OpHide(on) end,
        BD4Disguise = function(team) Restored.OpDisguise(team) end,
        BD4Portal = function(on) Restored.OpPortal(on) end,
        BD4Target = function(label) Restored.OpTarget(label) end,
    },
    weather = { module = "CREuropaWeather", sites = "CRGanymedeSitesBD04", glassFrost = 0.15, startLevel = 1, targetLevel = 1,
        environment = { lightingMode = "orbit", orbit = { period = 1800, startHour = -40 } },
        ops = { "EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge" },
        beats = function(europa, state, s)
            local beats = s.ganymedeBeats
            if beats == nil then beats = {}; s.ganymedeBeats = beats end
            local function raise(level)
                if europa.GetTargetLevel() < level then europa.SetTargetLevel(level) end
            end
            -- "What was that?": the portal tears open over the base and the ice shudders.
            if (not beats.portal) and state.cameraReady[1] then
                beats.portal = true
                raise(2)
                europa.Quake(0.3, 3.0)
            end
            -- The alarm: the turrets lock on and the radiation belt flares.
            if (not beats.alarm) and state.doAttack then
                beats.alarm = true
                raise(3)
                europa.Surge(6.0, 0.8)
            end
            -- The fragment leaves the ground.
            if (not beats.fragment) and state.gotFragment then
                beats.fragment = true
                raise(3)
                europa.Quake(0.4, 4.0)
            end
            -- The strike: bombers overhead, the Chinese fleet inbound. This map's site table has no vents.
            if (not beats.strike) and state.dropZoneReady then
                beats.strike = true
                raise(4)
                europa.Quake(0.35, 3.0)
                europa.Surge(6.0, 0.8)
                if #europa.GetVentSites() > 0 then europa.TriggerPlume(1) end
            end
            -- Everything calms while the result counts down; a loss leaves the ice restless.
            if (not beats.calm) and state.won then
                beats.calm = true
                europa.ReleaseForcedLevel()
                europa.SetTargetLevel(1)
            end
            if (not beats.lost) and state.lost and not state.won then
                beats.lost = true
                raise(4)
            end
        end },
    hooks = {
        start = function() Restored.OnStart() end,
        load = function() Restored.OnLoad() end,
        update = function(_, _, authority) Restored.OnUpdate(authority) end,
    },
})
local NativeBuildObjectAtPortal, NativeGetPlayerHandle, NativeGetCockpitTimer = BuildObjectAtPortal, GetPlayerHandle, GetCockpitTimer
local NativeHide, NativeUnHide, NativeSetPerceivedTeam = Hide, UnHide, SetPerceivedTeam
local NativePortalOut, NativeDeactivatePortal, NativeSetUserTarget, NativeIsInfo = PortalOut, DeactivatePortal, SetUserTarget, IsInfo
local IsValid = campaignRuntime and campaignRuntime.IsValid or IsValid
local AudioMessage = campaignRuntime and campaignRuntime.AudioMessage or AudioMessage
local StopAudioMessage = campaignRuntime and campaignRuntime.StopAudioMessage or StopAudioMessage
local CameraReady = campaignRuntime and campaignRuntime.CameraReady or CameraReady
local CameraFinish = campaignRuntime and campaignRuntime.CameraFinish or CameraFinish
local CameraCancelled = campaignRuntime and campaignRuntime.CameraCancelled or CameraCancelled
local ClearObjectives = campaignRuntime and campaignRuntime.ClearObjectives or ClearObjectives
local AddObjective = campaignRuntime and campaignRuntime.AddObjective or AddObjective
local SetObjectiveName = campaignRuntime and campaignRuntime.SetObjectiveName or SetObjectiveName
local SetObjectiveOn = campaignRuntime and campaignRuntime.SetObjectiveOn or SetObjectiveOn
local SetObjectiveOff = campaignRuntime and campaignRuntime.SetObjectiveOff or SetObjectiveOff
local RemoveObject = campaignRuntime and campaignRuntime.RemoveObject or RemoveObject
local SucceedMission = campaignRuntime and campaignRuntime.SucceedMission or SucceedMission
local FailMission = campaignRuntime and campaignRuntime.FailMission or FailMission
local SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
-- A line whose audio handle is absent counts as finished, so no gate can wait on it for ever.
local nativeAudioDone = IsAudioMessageDone
local function IsAudioMessageDone(message)
    if message == nil or message == 0 then return true end
    return nativeAudioDone(message)
end
-- Team 1 is the one shared Black Dog side: its pilots go to every human team (each human respawns from its own
-- pool). Team 2 is the DLL's enemy and a guest's team here: team 2 -> 5.
local SetPilot = campaignRuntime and function(team, count)
    if team == 1 then
        campaignRuntime.Coop.ForEachHumanTeam(function(humanTeam) if humanTeam ~= 1 then SetPilot(humanTeam, count) end end)
        return SetPilot(1, count)
    end
    if team == 2 then team = 5 end
    return SetPilot(team, count)
end or SetPilot
-- Every Chinese craft is built on the enemy team 5 (the runtime maps the body's team 2); a new scripted group (a new
-- frame or a new entry path) is a new scaling event: the first unit of each group is mirrored by
-- min(floor(humans / 2), 2) extras with its orders.
local eventFrame, eventWhere
local BuildObject = campaignRuntime and function(odf, team, where)
    if SCALED_ODFS[odf] then
        local now = GetTime()
        if eventFrame ~= now or eventWhere ~= where then
            eventFrame, eventWhere = now, where
            campaignRuntime.BeginEvent()
        end
    end
    return campaignRuntime.Spawn(odf, team, where)
end or BuildObject
local BuildObjectAtPortal = campaignRuntime and function(odf, team, portal)
    return NativeBuildObjectAtPortal(odf, team == 2 and 5 or team, portal)
end or BuildObjectAtPortal
-- The body's "player" is one handle (M.user). Co-op answers with the human the current step is about
-- (Restored.Focus): the one entering the base, carrying the fragment or sitting in the scav, else the host.
local GetPlayerHandle = campaignRuntime and function() return Restored.Focus() end or GetPlayerHandle
-- The turrets' order aimed at the player goes to the human nearest to that turret (a human may also be the
-- hauler the strikers are sent after: only a turret's target is reinterpreted). Tickets (units still waiting for
-- a concealed entry) are ordered through the runtime, which replays the order on the real unit.
local Attack = campaignRuntime and function(h, target, priority)
    if target ~= nil and target == M.user and Restored.IsTurret(h) then
        target = Restored.NearestHuman(h) or target
    end
    return campaignRuntime.Attack(h, target, priority)
end or Attack
-- Hide, the disguise, the portal and the user target are engine state each peer must apply to its own copy.
local Hide = campaignRuntime and function() return campaignRuntime.Present("BD4Hide", 1) end or Hide
local UnHide = campaignRuntime and function() return campaignRuntime.Present("BD4Hide", 0) end or UnHide
local SetPerceivedTeam = campaignRuntime and function(_, team) return Restored.Disguise(team == 2 and 5 or team) end or SetPerceivedTeam
local PortalOut = campaignRuntime and function() return campaignRuntime.Present("BD4Portal", 1) end or PortalOut
local DeactivatePortal = campaignRuntime and function() return campaignRuntime.Present("BD4Portal", 0) end or DeactivatePortal
local SetUserTarget = campaignRuntime and function(h) return Restored.ShareTarget(h) end or SetUserTarget
-- A guest's inspection counts: native IsInfo OR a guest report within the last second.
local IsInfo = campaignRuntime and function(prefix)
    if NativeIsInfo(prefix) then return true end
    local reported = remoteInfo[prefix]
    return reported ~= nil and GetTime() - reported <= 1.0
end or IsInfo
-- The cockpit countdown is presentation: every peer shows the host's timer. The engine cannot keep the clock
-- (the map runs MultSTMission, which restarts the timer upward every frame), so the host counts the minute itself.
local StartCockpitTimer = campaignRuntime and function(seconds, ...)
    Restored.TimerStart(seconds)
    return campaignRuntime.Present("StartCockpitTimer", seconds, ...)
end or StartCockpitTimer
local StopCockpitTimer = campaignRuntime and function()
    Restored.TimerStop()
    return campaignRuntime.Present("StopCockpitTimer")
end or StopCockpitTimer
local HideCockpitTimer = campaignRuntime and function() return campaignRuntime.Present("HideCockpitTimer") end or HideCockpitTimer
local GetCockpitTimer = campaignRuntime and function() return Restored.TimerLeft() end or GetCockpitTimer
-- A save during a shot cannot resume it (the cameras are gone): the shot reports arrival until the body ends it.
local CameraPath = campaignRuntime and function(path, height, speed, target)
    if Restored.SkipCamera() then return true end
    return campaignRuntime.CameraPath(path, height, speed, target)
end or CameraPath
-- CR co-op runtime <<

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function Distance(from, to, point)
    -- PORT FIX: null/deleted handles must not satisfy proximity checks or
    -- select the wrong Lua overload. Valid-map distances are unchanged.
    if not Valid(from) then return math.huge end
    if type(to) ~= "string" and not Valid(to) then return math.huge end
    if point ~= nil then return GetDistance(from, to, point) end
    return GetDistance(from, to)
end

local function Go(h, where, priority)
    if Valid(h) then Goto(h, where, priority) end
end

local function Strike(h, target, priority)
    -- Destroyed turrets/spawn failures cannot receive orders; do not substitute
    -- targets or change the source's explicit/default command priorities.
    if Valid(h) and Valid(target) then Attack(h, target, priority) end
end

local function Done(message)
    return message ~= nil and IsAudioMessageDone(message)
end

local function StopMessage(message)
    if message ~= nil then StopAudioMessage(message) end
end

-- CR restored content >>
-- The co-op state the single-player body keeps in one handle (M.user, the DLL's player), the stock-bug fixes that
-- need state, and the restorations (Docs/BDMISN04_COOP.md). Each restoration has a RESTORED_* flag. Only the
-- authority runs the body; every peer runs the ops and the update hook.
if campaignRuntime then
    local runtime = campaignRuntime
    local coop = runtime.Coop
    local seen, attackSig, nextInfoSend, sensorsBound = {}, nil, 0, false -- per-peer, not saved
    local function Real(h) return h ~= nil and h ~= 0 and IsValid(h) end
    local function RState()
        local s = runtime.State()
        s.r = s.r or {}
        return s.r
    end
    -- Every human with a usable handle (offline: the player). A guest inside an authored craft (the scav, the
    -- hauler) is known by the label-derived id the OpenShim hooks give authored objects (Docs/BDMISN04_COOP.md).
    local function Humans()
        local list = {}
        coop.ForEachPlayerHandle(function(h) list[#list + 1] = h end)
        return list
    end
    local function Inside(h)
        local ok, inside = pcall(IsInsideArea, "base_limit", h)
        return ok and inside == true
    end

    -- ---------------------------------------------------------------- the player
    -- M.user. Offline it is the player, exactly as in the body. In a network game it is the human the step is
    -- about: 1. one entering the base (a human outside the scav first: on foot is what sets the alarm off),
    -- 2. the one carrying the fragment, 3. the one in the commandeered scav, 4. the host.
    function Restored.Focus()
        local own = NativeGetPlayerHandle()
        if not coop.IsNetworkGame() then return own end
        local humans = Humans()
        if #humans == 0 then return own end
        if not M.inBaseArea then
            local inScav
            for _, h in ipairs(humans) do
                if Inside(h) then
                    if h ~= M.scav3 then return h end
                    inScav = h
                end
            end
            if inScav then return inScav end
        end
        if not M.gotFragment and Real(M.fragment) then
            local ok, tug = pcall(GetTug, M.fragment)
            if ok and tug ~= nil then
                for _, h in ipairs(humans) do
                    if h == tug then return h end
                end
            end
        end
        if Real(M.scav3) then
            for _, h in ipairs(humans) do
                if h == M.scav3 then return h end
            end
        end
        if Real(own) then return own end
        return humans[1]
    end
    function Restored.IsTurret(h)
        if h == nil then return false end
        for i = 0, 8 do
            if M.turret[i] == h then return true end
        end
        return false
    end
    function Restored.NearestHuman(from)
        local best, bestDistance
        for _, h in ipairs(Humans()) do
            local ok, distance = pcall(GetDistance, from, h)
            if ok and type(distance) == "number" and (bestDistance == nil or distance < bestDistance) then
                best, bestDistance = h, distance
            end
        end
        return best
    end

    -- ---------------------------------------------------------------- hide and the disguise
    function Restored.OpHide(on)
        coop.ForEachPlayerHandle(function(h)
            if on == 1 then NativeHide(h) else NativeUnHide(h) end
        end)
    end
    -- The body disguises its one player once, when the intro ends, and never lifts it. Every human gets the same
    -- perceived team (the DLL's 2, mapped to 5); a human whose pilot died and respawned as a new pilot gets it
    -- again. Ejecting from a craft is not a respawn: as in the body, that pilot is not disguised.
    function Restored.OpDisguise(team)
        coop.ForEachPlayerHandle(function(h) NativeSetPerceivedTeam(h, team) end)
    end
    local function Track()
        local respawned = false
        coop.ForEachPlayerHandle(function(h, id)
            local key = id or "local"
            local before = seen[key]
            local person = type(IsPerson) == "function" and IsPerson(h) or false
            if before ~= nil and before.handle ~= h and person and not Real(before.handle) then
                respawned = true
            end
            seen[key] = { handle = h, person = person }
        end)
        return respawned
    end
    function Restored.Disguise(team)
        RState().disguise = team
        Track()
        return runtime.Present("BD4Disguise", team)
    end
    local function Redisguise(r)
        if Track() then runtime.Present("BD4Disguise", r.disguise) end
    end

    -- ---------------------------------------------------------------- portal and user target
    function Restored.OpPortal(on)
        local portal = GetHandle("portal")
        if not Real(portal) then return end
        if on == 1 then NativePortalOut(portal) else NativeDeactivatePortal(portal) end
    end
    function Restored.OpTarget(label)
        local h = GetHandle(label)
        if Real(h) then NativeSetUserTarget(h) end
    end
    -- SetUserTarget is the local player's target: a network game targets it for every human. The object travels by
    -- label (its own, else the one given here).
    function Restored.ShareTarget(h, name)
        if not Real(h) then return end
        if not coop.IsNetworkGame() then return NativeSetUserTarget(h) end
        local label = GetLabel(h)
        if label == nil or label == "" then
            if name == nil then return NativeSetUserTarget(h) end
            label = name
            runtime.Present("Label", h, label)
        end
        return runtime.Present("BD4Target", label)
    end

    -- ---------------------------------------------------------------- the one-minute check-in
    function Restored.TimerStart(seconds) RState().timerEnd = GetTime() + seconds end
    function Restored.TimerStop() RState().timerEnd = nil end
    function Restored.TimerLeft()
        local finish = RState().timerEnd
        if finish ~= nil then return math.max(0, finish - GetTime()) end
        return NativeGetCockpitTimer()
    end

    -- ---------------------------------------------------------------- loads
    function Restored.OnStart()
        seen, attackSig, sensorsBound = {}, nil, false
    end
    function Restored.OnLoad()
        RState().skipShot = (M.cameraReady[0] or M.cameraReady[1]) and true or nil
        RState().afterLoad = true
    end
    -- The runtime's Load resets the presentation: rebuild the objective list from the saved flags, the minute
    -- and the disguise (the body only issues them at their events).
    function Restored.AfterLoad(r)
        if M.cameraComplete[1] then
            if M.won then
                ClearObjectives()
                AddObjective("bd04003.otf", "green")
            elseif M.objective3Complete then
                ClearObjectives()
                AddObjective("bd04003.otf", "white")
            elseif M.objective2Complete then
                ClearObjectives()
                AddObjective("bd04004.otf", "white")
            elseif M.objective1Complete then
                ClearObjectives()
                AddObjective("bd04001.otf", "green")
                AddObjective("bd04002.otf", "white")
            elseif M.gotoScav then
                ClearObjectives()
                AddObjective("bd04001.otf", "white")
            end
        end
        if r.timerEnd ~= nil then
            local remaining = r.timerEnd - GetTime()
            if remaining > 0 then runtime.Present("StartCockpitTimer", remaining, 15, 5) end
        end
        if r.disguise then runtime.Present("BD4Disguise", r.disguise) end
    end
    function Restored.SkipCamera()
        local r = RState()
        if not r.skipShot then return false end
        if M.cameraReady[0] or M.cameraReady[1] then return true end
        r.skipShot = nil
        return false
    end

    -- ---------------------------------------------------------------- the inspection relay
    function Restored.OnInfo(from, prefix)
        local player = coop.GetPlayers()[from]
        if coop.IsNetworkGame() and coop.IsAuthority() and player and coop.IsHumanTeam(player.team)
            and type(prefix) == "string" and INFO_PREFIXES[prefix] then
            remoteInfo[prefix] = GetTime()
        end
    end
    -- A guest reports which inspection its info panel shows.
    local function RelayInfo()
        local now = GetTime()
        if now < nextInfoSend then return end
        local leaderId = 0
        for id, player in pairs(coop.GetPlayers()) do
            if player.team == coop.GetLeaderTeam() then leaderId = id; break end
        end
        for prefix in pairs(INFO_PREFIXES) do
            if NativeIsInfo(prefix) then
                Send(leaderId, "I", prefix)
                nextInfoSend = now + 0.25
            end
        end
    end
    -- Every peer, every frame after the session is ready.
    function Restored.OnUpdate(authority)
        if not sensorsBound and runtime.Weather then
            sensorsBound = true
            local ok, Environment = pcall(require, "Environment")
            if ok and type(Environment) == "table" and Environment.BindWeatherSensors then
                pcall(Environment.BindWeatherSensors, "Ganymede", runtime.Weather.module)
            end
        end
        if coop.IsNetworkGame() and not authority then RelayInfo() end
    end

    -- ---------------------------------------------------------------- the authority's step (after the body)
    local function Signature()
        local parts = {}
        for _, h in ipairs(Humans()) do parts[#parts + 1] = tostring(h) end
        table.sort(parts)
        return table.concat(parts, ",")
    end
    function Restored.Step()
        if not M.startDone then return end
        local r = RState()
        if r.afterLoad then r.afterLoad = nil; Restored.AfterLoad(r) end
        if r.disguise then Redisguise(r) end
        -- Stock: the turrets are ordered onto the one player once (and again when that player changes craft). A
        -- human who dies, respawns or changes craft would leave them on a dead handle: order them again.
        if M.doAttack and M.startAttack then
            local sig = Signature()
            if attackSig ~= nil and sig ~= attackSig then
                for i = 0, 8 do
                    if Real(M.turret[i]) and Real(M.user) then Attack(M.turret[i], M.user, 1) end
                end
            end
            attackSig = sig
        end
        -- Cut: `//SetUserTarget(navBeacon);` after the rendezvous pod (rv_scout) and after the Drop Zone pod.
        if RESTORED_USER_TARGET and M.gotFragment and not r.targetRv and Real(M.navBeacon) then
            r.targetRv = true
            Restored.ShareTarget(M.navBeacon, "bd04rv")
        end
        if RESTORED_USER_TARGET and M.dropZoneReady and not r.targetDz and Real(M.navBeacon) then
            r.targetDz = true
            Restored.ShareTarget(M.navBeacon, "bd04dz")
        end
        -- Unused shipped line bd04009 "Careful, Lieutenant. There aren't many of those." as the fragment lifts.
        if RESTORED_VOICE_LINES and M.gotFragment and not r.l409 then
            r.l409 = true
            AudioMessage("bd04009.wav")
        end
    end
    local failed
    function Restored.Run()
        local ok, err = pcall(Restored.Step)
        if not ok and not failed then
            failed = true
            print("[bdmisn04] restored content failed: " .. tostring(err))
        end
    end
end
-- CR restored content <<
function Start()
    M = NewState()
    M.silo = GetHandle("silo")
    M.portal = GetHandle("portal")
    M.scav1 = GetHandle("scav_1")
    M.scav2 = GetHandle("scav_2")
    M.scav3 = GetHandle("scav_3")
    M.fragment = GetHandle("fragment")
    M.hauler = GetHandle("hauler_1")
    for i = 0, 8 do M.turret[i] = GetHandle("turret_" .. (i + 1)) end
end

function AddObject(h)
    -- Native AddObject(Handle) is empty.
end

function Update(dt)
    M.lastUser = M.user
    M.user = GetPlayerHandle() -- assigns the player a handle every frame

    if not M.startDone then
        SetScrap(1, 8)
        SetPilot(1, 10)
        -- setup the initial objectives
        ClearObjectives()
        -- don't do this part after the first shot
        M.startDone = true
    end

    -- SOE #1: start the camera going
    if not M.cameraComplete[0] then
        if not M.cameraReady[0] then
            CameraReady()
            -- spawn the pilot
            M.pilot = BuildObject("aspilo", 1, "pilot")
            Go(M.pilot, "pilot_path", 1)
            if Valid(M.user) then Hide(M.user) end
            M.introSound = AudioMessage("bd04001.wav")
            M.cameraReady[0] = true
        end

        -- PORT FIX: release a shot if its spawned subject is missing; this
        -- avoids a stuck/invalid camera and runs the same completion actions.
        local arrived = not Valid(M.pilot)
        if not arrived then
            arrived = CameraPath("camera_start_up", 750, 400, M.pilot)
        end
        -- should we spawn the beacons?
        if M.nav1 == nil and Distance(M.pilot, "nav_1", 0) < 1.0 then
            M.nav1 = BuildObject("bpcamr", 0, "nav_1")
        end
        if M.nav2 == nil and Distance(M.pilot, "nav_2", 0) < 1.0 then
            M.nav2 = BuildObject("bpcamr", 0, "nav_2")
            M.cameraCompleteDelay = GetTime() + 2.0
        end
        if CameraCancelled() then
            arrived = true
            StopMessage(M.introSound)
        end
        if arrived or M.cameraCompleteDelay < GetTime() then
            -- if the audio is complete (source checks arrival/delay, not audio)
            CameraFinish()
            M.cameraComplete[0] = true
            M.cameraReady[0] = false
            M.cameraCompleteDelay = 999999.9
            -- remove the pilot
            if Valid(M.pilot) then RemoveObject(M.pilot) end
            M.pilot = nil
            if Valid(M.user) then UnHide(M.user) end
            -- if the nav's don't exist, add them
            if M.nav1 == nil then M.nav1 = BuildObject("bpcamr", 0, "nav_1") end
            if M.nav2 == nil then M.nav2 = BuildObject("bpcamr", 0, "nav_2") end
            if Valid(M.user) then SetPerceivedTeam(M.user, 2) end
        end
    end

    -- SOE #2
    if M.cameraComplete[0] and not M.cameraComplete[1] then
        if not M.cameraReady[1] then
            M.cameraReady[1] = true
            M.cameraComplete[1] = false
            CameraReady()
            -- Native activatePortal(portal, false): outward portal activation.
            if Valid(M.portal) then PortalOut(M.portal) end
            M.portalCamTime = GetTime() + 6.0
            M.portalSoundTime = GetTime() + 4.0 -- 2 seconds before the sound
            M.portalUnitTime[0] = GetTime() + 1.5
            M.portalUnitTime[1] = GetTime() + 4.0
            M.portalOffTime = GetTime() + 7.0
        end
        if Valid(M.portal) then CameraPath("camera_portal", 3000, 0, M.portal) end
        if CameraCancelled() or not Valid(M.portal) then
            M.portalCamTime = -1
            StopMessage(M.portalSound)
        end
        if M.portalCamTime < GetTime() then
            M.portalCamTime = 999999.9
            M.cameraReady[1] = false
            M.cameraComplete[1] = true
            CameraFinish()
        elseif M.portalSoundTime < GetTime() then
            M.portalSoundTime = 999999.9
            M.portalSound = AudioMessage("bd04002.wav")
        end
    end

    for i = 0, 1 do
        if M.portalUnitTime[i] < GetTime() then
            M.portalUnitTime[i] = 999999.9
            if Valid(M.portal) then
                M.portalUnit[i] = BuildObjectAtPortal("cvfigh", 2, M.portal)
                -- Native assertion: "Failed to create Portal Unit %i", i.
                Go(M.portalUnit[i], "unit_path", 1)
            end
        end
    end
    if M.portalOffTime < GetTime() then
        M.portalOffTime = 999999.9
        if Valid(M.portal) then DeactivatePortal(M.portal) end
    end

    -- SOE #3
    if M.cameraComplete[1] and not M.gotoScav then
        M.scavMessage = AudioMessage("bd04003.wav")
        ClearObjectives()
        AddObjective("bd04001.otf", "white")
        if Valid(M.scav3) then
            SetObjectiveOn(M.scav3)
            SetObjectiveName(M.scav3, "Scavenger")
            SetUserTarget(M.scav3)
        end
        M.gotoScav = true
        M.getInScavTimeout = GetTime() + 120.0
    end
    -- time out and play message again
    if not M.objective1Complete and M.getInScavTimeout < GetTime() then
        M.getInScavTimeout = GetTime() + 120.0
        M.scavMessage = AudioMessage("bd04003.wav")
    end
    -- are we in the scav?
    if Valid(M.user) and M.user == M.scav3 then
        if not M.objective1Complete and not M.objective2Complete then
            -- stop the "goto scav" message if it's still playing
            if M.scavMessage ~= nil and not Done(M.scavMessage) then
                StopMessage(M.scavMessage)
            end
            ClearObjectives()
            AddObjective("bd04001.otf", "green")
            AddObjective("bd04002.otf", "white")
            M.objective1Complete = true
            SetObjectiveOff(M.scav3)
            M.getInScavTimeout = 999999.0
            Go(M.scav1, "scav_path")
            Go(M.scav2, "scav_path")
            AudioMessage("bd04010.wav")
            if Valid(M.portal) then SetObjectiveOn(M.portal) end
        end
    end

    -- SOE #4
    if not M.trigger1 and M.scav3 == M.user and Distance(M.scav3, "trigger_1") < 400.0 then
        M.trigger1 = true
    end
    -- Native isIn(user, "base_limit") is an area query, NOT portal IsIn.
    if Valid(M.user) and IsInsideArea("base_limit", M.user) and not M.inBaseArea then
        M.inBaseArea = true
        if M.trigger1 then
            -- we're safe since we went by trigger_1
        elseif M.user == M.scav3 then
            M.inBaseSound1 = AudioMessage("bd04005.wav")
        else
            M.doAttack = true
        end
    end
    if Done(M.inBaseSound1) then
        M.inBaseSound1 = nil
        M.inBaseSoundTime = GetTime() + 1.0
    end
    if M.inBaseSoundTime < GetTime() then
        M.inBaseSoundTime = 999999.9
        M.inBaseSound2 = AudioMessage("bd04006.wav")
    end
    if Done(M.inBaseSound2) then
        M.inBaseSound2 = nil
        M.doAttack = true
    end
    if M.doAttack then
        --doAttack = FALSE;
        if not M.startAttack or M.lastUser ~= M.user then
            M.startAttack = true
            -- turrets lock on and attack
            for i = 0, 8 do Strike(M.turret[i], M.user, 1) end
        end
    end

    if not M.objective2Complete and IsInfo("cbport") then
        ClearObjectives()
        AddObjective("bd04004.otf", "white")
        M.sound4Time = GetTime() + 2.0
        M.objective2Complete = true
        if Valid(M.portal) then SetObjectiveOff(M.portal) end
        StartCockpitTimer(60, 15, 5)
    end
    -- play the audio message after a 2 second delay
    if M.sound4Time < GetTime() then
        M.sound4Time = 999999.9
        M.sound4 = AudioMessage("bd04004.wav")
    end
    -- once played
    if Done(M.sound4) then M.sound4 = nil end

    if M.objective2Complete and not M.idFragment and not M.timeoutWarningStarted
        and GetCockpitTimer() <= 0.0 then
        -- PORT FIX: native code starts bd04005 every frame after expiry,
        -- replacing sound5 so bd04006/attack may never follow. Latch the
        -- existing timeout once; the 60-second deadline and warning/attack
        -- sequence remain unchanged. Save this latch with the mission state.
        M.timeoutWarningStarted = true
        HideCockpitTimer()
        M.sound5 = AudioMessage("bd04005.wav")
    end
    -- once played
    if Done(M.sound5) then
        M.sound5 = nil
        M.sound6 = AudioMessage("bd04006.wav")
    end
    -- once played
    if Done(M.sound6) then
        M.sound6 = nil
        M.doAttack = true
    end

    -- SOE #4a
    if M.objective2Complete and not M.idFragment and IsInfo("obdataa") then
        StopCockpitTimer()
        HideCockpitTimer()
        M.idFragment = true
        AudioMessage("bd04007.wav")
        ClearObjectives()
        AddObjective("bd04003.otf", "white")
        M.objective3Complete = true
    end
    if M.objective3Complete and not M.outOfScav then
        if M.user ~= M.scav3 then
            M.outOfScav = true
            M.doAttack = true
        end
    end

    -- SOE #4b
    if not M.gotFragment then
        -- PORT FIX: absent cargo/player handles must not count as pickup
        -- through nil == nil. Actual tug/player equality is unchanged.
        if Valid(M.fragment) and Valid(M.user) and GetTug(M.fragment) == M.user then
            M.gotFragment = true
            -- TRO 1.3: towing the fragment also completes objective 3 when it has not been scanned
            if not M.idFragment then
                StopCockpitTimer()
                HideCockpitTimer()
                M.idFragment = true
                AudioMessage("bd04007.wav")
                ClearObjectives()
                AddObjective("bd04003.otf", "white")
                M.objective3Complete = true
            end
            M.navBeacon = BuildObject("bpcamr", 1, "rv_scout")
            --SetUserTarget(navBeacon);
            -- Native repeatedly overwrites a local h; these escorts receive
            -- no scripted command. Keep their original default AI behavior.
            BuildObject("bvfigh", 1, "escort_units")
            BuildObject("bvfigh", 1, "escort_units")
            BuildObject("bvfigh", 1, "escort_units")
            BuildObject("bvtank", 1, "escort_units")
            BuildObject("bvtank", 1, "escort_units")
            BuildObject("bvtank", 1, "escort_units")
            M.bomberTime = GetTime() + 30.0
        end
    end
    if M.bomberTime < GetTime() then
        M.bomberTime = 999999.9
        for i = 1, 5 do
            local h = BuildObject("bvhraza", 1, "bomber_wing_x5_spawn_point")
            -- Native assertion: "bomber not created @ bomber_wing_x5_spawn_point".
            Go(h, "trigger_1")
        end
        M.navBeacon = BuildObject("bpcamr", 1, "proposed_end_area")
        if Valid(M.navBeacon) then
            SetObjectiveName(M.navBeacon, "Drop Zone") -- native SetName alias
            SetObjectiveOn(M.navBeacon)
        end
        M.dropZoneReady = true
        --SetUserTarget(navBeacon);

        -- spawn the fighers to kill the player here (source targets hauler)
        for i = 1, 6 do
            local h = BuildObject("cvfighg", 2, "chinese_scout_x6_spawn_point")
            Strike(h, M.hauler, 1)
        end
        for i = 1, 2 do
            local h = BuildObject("cvfighg", 2, "attack_1")
            Strike(h, M.hauler, 1)
        end
        for i = 1, 4 do
            local h = BuildObject("cvfighg", 2, "attack_2")
            Strike(h, M.hauler, 1)
        end
        for i = 1, 3 do
            local h = BuildObject("cvtnk", 2, "attack_3")
            Strike(h, M.hauler, 1)
        end
    end
    for i = 0, 3 do
        local spot = "return_" .. (i + 1)
        -- Preserve ungated route ambushes: proximity alone triggers each one.
        if not M.returnAttack[i] and Distance(M.hauler, spot) < 300.0 then
            M.returnAttack[i] = true
            for j = 1, 3 do
                local h = BuildObject("cvfigh", 2, spot)
                Strike(h, M.hauler)
            end
        end
    end

    if (not Valid(M.hauler) or GetHealth(M.hauler) <= 0.0) and not M.lost and not M.won then
        FailMission(GetTime() + 1.0, "bd04lose.des")
        M.lost = true
    end

    -- SOE #5
    -- PORT FIX: native navBeacon is null before pickup, then rv_scout until
    -- bomberTime replaces it. Only test the final Drop Zone after that source
    -- event. This prevents null-handle/temporary-rendezvous victories while
    -- keeping the intended extraction route, 30-second event, and 50m radius.
    if M.objective3Complete and M.dropZoneReady and Distance(M.fragment, M.navBeacon) < 50.0
        and not M.won and not M.lost then
        ClearObjectives()
        AddObjective("bd04003.otf", "green")
        M.won = true
        M.congrats = AudioMessage("bd04008.wav")
    end
    if Done(M.congrats) then
        M.congrats = nil
        -- PORT FIX: SucceedMission takes an absolute mission time. Native 0.1
        -- is already in the past here; schedule its intended 0.1-second delay
        -- after the same congratulations audio, with no new victory gate.
        SucceedMission(GetTime() + 0.1, "bd04win.des")
    end
    -- what if the portal is destroyed?
    if (not Valid(M.portal) or GetHealth(M.portal) <= 0.0) and not M.won and not M.lost then
        M.lost = true
        FailMission(GetTime() + 1.0, "bd04lose.des")
    end
end

function Save()
    return M
end

function Load(state)
    -- LuaMission restores table values and engine handles. Do not rerun Setup
    -- or replay cameras, audio, spawns, countdowns, or ambushes after loading.
    M = state
end
-- CR co-op callbacks >>
-- The body is never edited: the runtime's per-frame calls wrap its callbacks here.
local BodyStart, BodyAddObject, BodyUpdate, BodySave, BodyLoad = Start, AddObject, Update, Save, Load
function Start()
    BodyStart()
    if campaignRuntime then campaignRuntime.Start() end
end
function AddObject(h)
    BodyAddObject(h)
    if campaignRuntime then return campaignRuntime.AddObject(h) end
end
function Update(dt)
    if campaignRuntime and not campaignRuntime.Update(dt) then return end
    BodyUpdate(dt)
    if campaignRuntime then
        Restored.Run()
        campaignRuntime.AfterUpdate()
    end
end
function Save()
    if campaignRuntime then campaignRuntime.Save() end
    return BodySave()
end
function Load(state)
    BodyLoad(state)
    if campaignRuntime then campaignRuntime.Load() end
end
function CreatePlayer(id,name,team) if campaignRuntime then return campaignRuntime.CreatePlayer(id,name,team) end end
function AddPlayer(id,name,team) if campaignRuntime then return campaignRuntime.AddPlayer(id,name,team) end end
function DeletePlayer(id) if campaignRuntime then return campaignRuntime.DeletePlayer(id) end end
function Receive(from,kind,...)
    if campaignRuntime then
        -- "I": a guest's report of the object its info panel shows (the only packet kind this mission adds).
        if kind == "I" then return Restored.OnInfo(from, ...) or true end
        return campaignRuntime.Receive(from,kind,...)
    end
end
-- CR co-op callbacks <<
