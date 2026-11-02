-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/BDMISN08_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Ganymede weather); outside it this file is
-- the faithful port, byte for byte (Tools/Test-Bdmisn08CoopSourceParity.py).
-- CR co-op layer <<
-- BlackDog08Mission.cpp port for stock Battlezone 98 Redux 2.1+ / Lua 5.1.
-- Source blob: f0fbb7371b4a584a4852889e1f33f741ad11695a.
-- Complete original (all comments, TEST_PORTAL branches, native serialization):
-- References/BlackDog08Source/BlackDog08Mission.cpp.
-- No EXU/OpenShim or Campaign Reimagined helpers are required.

local NEVER = 999999.9
-- //#define TEST_PORTAL: disabled in the shipped source. Enable only for tests.
local TEST_PORTAL = false
local attackers = {
    "cvtnk", "cvtnk", "cvltnk", "cvfigh", "cvfigh",
    "cvfigh", "cvfigh", "cvfigh", "cvrckt", "cvhraz",
}

local function NewState()
    return {
        startDone = false,
        objective1Complete = false, objective2Complete = false,
        objective3Complete = false, -- unused source flags retained
        cameraReady = {[0] = false, [1] = false},
        cameraComplete = {[0] = false, [1] = false}, arrived = false,
        pilotSpawned1 = false, pilotSpawned2 = false,
        portalReprogrammed = false, apcHeadingBack = false,
        apcCommandeered = false,
        scheduleLose1 = false, scheduleLose2 = false, scheduleLose3 = false,
        lost = false, won = false,
        secondCameraTime = NEVER, activateTime = NEVER, attackWaveTime = NEVER,
        apcTime = NEVER, apcPilotTime1 = NEVER, apcPilotTime2 = NEVER,
        apcGoBackTime = NEVER, sound3Time = NEVER, waveCount = 0,
        -- Nil handles/audio IDs represent native NULL, including unused waveHandle.
        pilotBoarding = false, -- only additional state: asynchronous stock GetIn
    }
end
local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/BDMISN08_COOP.md lists every wrapped call and restoration.
-- Each RESTORED_* flag switches one cut-content restoration off (Docs/BDMISN08_COOP.md, "Restored content").
local RESTORED_APC_LOSS_VOICE = true -- the unused bd08005 reprimand when the APC is shot down
local Restored = {}
-- The portal attackers are head-count scaled. They arrive through the portal itself (BuildObjectAtPortal), a
-- staged, visible event, so they are not concealed tickets: the extras are staggered at the portal instead.
local SCALED_ODFS = { cvtnk = true, cvltnk = true, cvfigh = true, cvrckt = true, cvhraz = true }
local sensorsBound = false
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "bdmisn08", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2,
    rallyPoints = { [0] = "recycler" }, -- the shared base is wherever the recycler is
    failDes = "bd08lose.des", -- out of lives (every human out): the stock generic debrief
    wonFlags = { "won" },
    endedFlags = { "won", "lost" },
    weather = { module = "CREuropaWeather", sites = "CRGanymedeSitesBD08", startLevel = 1, targetLevel = 1,
        -- Ganymede under Jupiter: the sun's real path, a short eclipse, Jupiter-shine at night.
        environment = { lightingMode = "orbit", orbit = { period = 1800, startHour = -40 } },
        ops = { "EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge" },
        beats = function(europa, state, s)
            local beats = s.europaBeats
            if beats == nil then beats = {}; s.europaBeats = beats end
            -- The portal is powered up for the Chinese: electromagnetic activity, the sky stirs, a vent wakes.
            if (not beats.portal) and state.cameraReady and state.cameraReady[1] then
                beats.portal = true
                europa.SetTargetLevel(2)
                europa.Surge(4.0, 0.5)
                europa.TriggerPlume(1)
            end
            -- The engineers' APC comes through the portal.
            if (not beats.convoy) and state.apc ~= nil then
                beats.convoy = true
                europa.SetTargetLevel(3)
            end
            -- The portal is reprogrammed: the moon flexes.
            if (not beats.reprogrammed) and state.portalReprogrammed then
                beats.reprogrammed = true
                europa.SetTargetLevel(4)
                europa.Quake(0.35, 3.0)
                europa.Surge(6.0, 0.8)
                for index = 2, #europa.GetVentSites() do europa.TriggerPlume(index) end
            end
            -- The captured APC is home (or the mission is decided): calm.
            if (not beats.easing) and state.won then
                beats.easing = true
                europa.ReleaseForcedLevel()
                europa.SetTargetLevel(1)
            end
        end },
    hooks = {
        start = function() sensorsBound = false end,
        -- The weather director slows radar and scrambles velocity jammers as it intensifies (every peer).
        update = function(runtime)
            if not sensorsBound and runtime.Weather then
                sensorsBound = true
                require("Environment").BindWeatherSensors("Ganymede", runtime.Weather.module)
            end
        end,
        load = function() if Restored.OnLoad then Restored.OnLoad() end end,
    },
})
local NativeIsValid, NativeGetHealth, NativeGetTeamNum = IsValid, GetHealth, GetTeamNum
local NativeSetPerceivedTeam, NativeBuildObjectAtPortal = SetPerceivedTeam, BuildObjectAtPortal
local PLAYERS = campaignRuntime and campaignRuntime.PLAYERS
local GetPlayerHandle = campaignRuntime and campaignRuntime.GetPlayerHandle or GetPlayerHandle
local Retreat = campaignRuntime and campaignRuntime.Retreat or Retreat
local SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
local StopAudioMessage = campaignRuntime and campaignRuntime.StopAudioMessage or StopAudioMessage
local CameraFinish = campaignRuntime and campaignRuntime.CameraFinish or CameraFinish
local CameraCancelled = campaignRuntime and campaignRuntime.CameraCancelled or CameraCancelled
local SetObjectiveName = campaignRuntime and campaignRuntime.SetObjectiveName or SetObjectiveName
local SetObjectiveOn = campaignRuntime and campaignRuntime.SetObjectiveOn or SetObjectiveOn
local ClearObjectives = campaignRuntime and campaignRuntime.ClearObjectives or ClearObjectives
local AddObjective = campaignRuntime and campaignRuntime.AddObjective or AddObjective
local RemoveObject = campaignRuntime and campaignRuntime.RemoveObject or RemoveObject
local SucceedMission = campaignRuntime and campaignRuntime.SucceedMission or SucceedMission
local FailMission = campaignRuntime and campaignRuntime.FailMission or FailMission
-- The pilots are not scaled: the runtime only maps the map's enemy team 2 to the co-op enemy 5.
local BuildObject = campaignRuntime and campaignRuntime.Spawn or BuildObject
-- The body's "player" (M.user) is the runtime's nearest-human token. It is a valid, healthy object while any
-- human lives; orders aimed at it go to the nearest human, the intro shot looks at the host's ship.
local IsValid = campaignRuntime and function(h)
    if h == PLAYERS then return true end
    return NativeIsValid(h)
end or IsValid
local GetHealth = campaignRuntime and function(h)
    if h == PLAYERS then return Restored.HumanHealth() end
    return NativeGetHealth(h)
end or GetHealth
local Attack = campaignRuntime and function(h, target, ...)
    if target == PLAYERS then
        target = Restored.NearestHuman(h)
        if target == nil then return end
    end
    return campaignRuntime.Attack(h, target, ...)
end or Attack
local CameraReady = campaignRuntime and function()
    Restored.ShotBegan()
    return campaignRuntime.CameraReady()
end or CameraReady
local CameraPath = campaignRuntime and function(path, height, speed, target)
    if target == PLAYERS then target = Restored.CameraTarget() end
    local arrived = campaignRuntime.CameraPath(path, height, speed, target)
    if arrived then return arrived end
    return Restored.ArrivedAfterSkip() or arrived
end or CameraPath
-- Humans are teams 1-4; the body's test for "the player owns the APC" is team 1.
local GetTeamNum = campaignRuntime and function(h)
    local team = NativeGetTeamNum(h)
    if type(team) == "number" and team >= 1 and team <= 4 then return 1 end
    return team
end or GetTeamNum
-- The body's enemy is the map's team 2; in co-op team 2 is a human slot, so the disguise is the co-op enemy 5.
local SetPerceivedTeam = campaignRuntime and function(h, team)
    if team == 2 then team = 5 end
    if h == PLAYERS then -- only the TEST_PORTAL debug branch names the token: disguise the host's ship
        h = Restored.CameraTarget()
        if h == M.portal or not NativeIsValid(h) then return end
    end
    return NativeSetPerceivedTeam(h, team)
end or SetPerceivedTeam
-- Remember the path a portal attacker was sent down, so its extras take the same one (Restored.NotePath).
local Goto = campaignRuntime and function(h, path, priority)
    Restored.NotePath(h, path)
    return campaignRuntime.Goto(h, path, priority)
end or Goto
-- The win and lose gates test `sound ~= nil and Done(sound)`; a nil handle (no line played) would strand the
-- mission, so it becomes 0, which Done already counts as finished. The body treats nil and 0 alike elsewhere.
local AudioMessage = campaignRuntime and function(file)
    local handle = campaignRuntime.AudioMessage(Restored.AudioLine(file))
    if handle == nil then return 0 end
    return handle
end or AudioMessage
-- A portal attacker is mirrored by min(floor(humans / 2), 2) extras, built a moment later at the same portal.
local BuildObjectAtPortal = campaignRuntime and function(odf, team, portal)
    if team == 2 then team = 5 end
    local h = NativeBuildObjectAtPortal(odf, team, portal)
    if SCALED_ODFS[odf] and h ~= nil and h ~= 0 then Restored.QueueExtras(odf, team, portal, h) end
    return h
end or BuildObjectAtPortal
-- CR co-op runtime <<

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end
local function Healthy(h)
    -- PORT FIX: native pointer assertions do not prevent release-build crashes
    -- after APC/pilot destruction. Never query or mutate a missing Lua handle.
    -- Missing objects count as zero health; normal health-based loss gates and
    -- all timer values remain unchanged. Empty vehicles still count as healthy.
    return Valid(h) and GetHealth(h) > 0.0
end
local function Touching(a, b)
    return Healthy(a) and Healthy(b) and IsTouching(a, b)
end
local function Team(h)
    if Valid(h) then return GetTeamNum(h) end
    return nil
end
local function Activate(inward)
    if Healthy(M.portal) then
        -- Native activatePortal(portal, false/true) combines these operations.
        if inward then PortalIn(M.portal) else PortalOut(M.portal) end
        ActivatePortal(M.portal)
    end
end
local function Done(sound)
    return sound == nil or sound == 0 or IsAudioMessageDone(sound)
end

-- CR restored content >>
-- Content the DLL cut, restored in the CR layer only (Docs/BDMISN08_COOP.md quotes the cut block), plus the
-- co-op fixes that need state. Each restoration is gated by a RESTORED_* flag.
if campaignRuntime then
    local runtime = campaignRuntime
    local EXTRA_GAP = 2.0 -- seconds between the portal's units
    local SKIP_ARRIVAL = 12.0 -- seconds of shot after a host skip
    local function RState()
        local s = runtime.State()
        s.r = s.r or {}
        return s.r
    end
    local function ForEachHuman(fn)
        runtime.Coop.ForEachPlayerHandle(function(h) if Healthy(h) then fn(h) end end)
    end
    -- The intro camera needs a real object: the host's ship (the authority), else any human, else the portal.
    function Restored.CameraTarget()
        local host = runtime.Native.GetPlayerHandle()
        if Valid(host) then return host end
        local found
        runtime.Coop.ForEachPlayerHandle(function(h) if found == nil and Valid(h) then found = h end end)
        return found or M.portal
    end
    -- Orders at "the player" go to the human nearest the unit.
    function Restored.NearestHuman(from)
        local best, bestDistance
        ForEachHuman(function(h)
            local d = GetDistance(from, h)
            if bestDistance == nil or d < bestDistance then best, bestDistance = h, d end
        end)
        return best
    end
    -- The token is healthy while any human has a living ship.
    function Restored.HumanHealth()
        local alive = 0.0
        ForEachHuman(function() alive = 1.0 end)
        return alive
    end
    -- Stock bug: both shots end on the path's arrival. A host's own skip releases only the host's camera and the
    -- runtime then never reports an arrival again, so the shared film would hang the whole mission (the intro is
    -- what arms the portal). After a host skip in a network game the shot counts as arrived once it has run SKIP_ARRIVAL
    -- seconds; the intro still waits for its briefing line, and the guests keep their streamed shot until then.
    -- A cancel still latched when a shot begins (the intro's skip) is not a skip of this shot: only a cancel that
    -- rises after the shot began counts (edge-detected; the latch is sampled when the shot begins).
    local shotStart, skippedAt, latched
    function Restored.ShotBegan()
        shotStart, skippedAt = GetTime(), nil
        latched = runtime.Native.CameraCancelled() and true or false
    end
    function Restored.ArrivedAfterSkip()
        if not runtime.Coop.IsNetworkGame() then return false end
        if not runtime.Native.CameraCancelled() then
            latched = false
        elseif not latched then
            skippedAt = skippedAt or GetTime()
        end
        return skippedAt ~= nil and GetTime() - (shotStart or skippedAt) >= SKIP_ARRIVAL
    end
    -- A load cannot resume a cinematic (the cameras are gone): finish the one that was running, as the body would.
    function Restored.OnLoad()
        if not runtime.Coop.IsAuthority() then return end
        RState().afterLoad = true
        if M.cameraReady[0] and not M.cameraComplete[0] then
            M.introSound = nil
            M.arrived = false
            M.cameraComplete[0] = true
            M.secondCameraTime = GetTime() + 25.0
        end
        if M.cameraReady[1] and not M.cameraComplete[1] then
            M.arrived = false
            M.cameraComplete[1] = true
        end
    end
    -- The runtime's Load resets the presentation (objective list, nav names, APC marker), and the body only
    -- publishes them at the moment a stage begins. Republish what the current stage shows, with the body's own
    -- names and colours, once the opening is over (the body's second shot clears and builds the list itself).
    function Restored.AfterLoad()
        if Valid(M.navPortal) then SetObjectiveName(M.navPortal, "Portal") end
        if Valid(M.navBase) then SetObjectiveName(M.navBase, "Black Dog Base") end
        if M.cameraReady[1] then
            ClearObjectives()
            if M.portalReprogrammed then
                AddObjective("bd08002.otf", "green")
                AddObjective("bd08003.otf", "white")
            elseif M.pilotSpawned1 or M.apcPilotTime2 < NEVER then
                AddObjective("bd08001.otf", "white")
                AddObjective("bd08002.otf", "white")
            else
                AddObjective("bd08001.otf", "white")
            end
            if (M.pilotSpawned1 or M.apcPilotTime2 < NEVER or M.portalReprogrammed) and Healthy(M.apc) then
                SetObjectiveOn(M.apc)
            end
        end
    end
    -- Runs first in the body's Update: an APC that is already dead this frame was shot down, not driven home
    -- (a driven-home APC is removed and forgotten by the body in the same frame it ends the mission).
    function Restored.Before()
        if not M.lost and not M.won and M.apc ~= nil and not Healthy(M.apc) then RState().apcShot = true end
    end
    -- Cut: no line of the DLL plays the reprimand bd08005. The APC loss reuses the base-loss line bd08006
    -- ("wasting resources ... Phobos"); the APC loss, and only it, gets bd08005 instead.
    function Restored.AudioLine(file)
        if RESTORED_APC_LOSS_VOICE and file == "bd08006.wav" and RState().apcShot
            and Healthy(M.recycler) and Healthy(M.command) then
            return "bd08005.wav"
        end
        return file
    end
    function Restored.NotePath(h, path)
        local r = RState()
        if type(path) ~= "string" or r.extras == nil then return end
        for _, extra in ipairs(r.extras) do
            if extra.primary == h then extra.path = path end
        end
    end
    function Restored.QueueExtras(odf, team, portal, primary)
        local count = math.min(math.floor(runtime.HumanCount() / 2), 2)
        if count == 0 then return end
        local r = RState()
        r.extras = r.extras or {}
        for k = 1, count do
            r.extras[#r.extras + 1] = { odf = odf, team = team, portal = portal, primary = primary,
                due = GetTime() + EXTRA_GAP * k }
        end
    end
    -- Runs at the end of the body's Update.
    function Restored.Step()
        if not M.startDone then return end
        local r = RState()
        if r.afterLoad and M.cameraComplete[0] then r.afterLoad = nil; Restored.AfterLoad() end
        -- Nothing more comes through once the portal is reprogrammed, the mission is decided or the portal is lost.
        if M.won or M.lost or M.portalReprogrammed or not Healthy(M.portal) then r.extras = nil; return end
        if r.extras == nil then return end
        local live = {}
        for _, h in ipairs(r.live or {}) do if Healthy(h) then live[#live + 1] = h end end
        r.live = live
        local now, waiting = GetTime(), {}
        for _, extra in ipairs(r.extras) do
            if extra.due > now then
                waiting[#waiting + 1] = extra
            elseif #live < runtime.LIVE_CAP then
                local h = NativeBuildObjectAtPortal(extra.odf, extra.team, M.portal)
                if Valid(h) then
                    live[#live + 1] = h
                    if extra.path then runtime.Goto(h, extra.path, 1) end
                end
            end
        end
        r.extras = waiting
    end
    local failed
    local function Guard(step)
        local ok, err = pcall(step)
        if not ok and not failed then
            failed = true
            print("[bdmisn08] restored content failed: " .. tostring(err))
        end
    end
    function Restored.Run() Guard(Restored.Step) end
    function Restored.BeforeRun() Guard(Restored.Before) end
end
-- CR restored content <<
function Start()
    M = NewState()
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Start() end
-- CR co-op callback <<
    M.recycler = GetHandle("recycler")
    M.portal = GetHandle("portal")
    M.command = GetHandle("command")
    M.factory = GetHandle("factory")
    M.navPortal = GetHandle("nav_portal")
    M.navBase = GetHandle("nav_base")
    if Valid(M.navPortal) then SetObjectiveName(M.navPortal, "Portal") end
    if Valid(M.navBase) then SetObjectiveName(M.navBase, "Black Dog Base") end
end

function AddObject(h)
    -- Native AddObject(Handle h) is empty.
end

function Update(dt)
-- CR co-op callback >>
    if campaignRuntime and not campaignRuntime.Update(dt) then return end
    if campaignRuntime then Restored.BeforeRun() end
-- CR co-op callback <<
    M.user = GetPlayerHandle() -- assigns the player a handle every frame
    local now = GetTime()
    if not M.startDone then
        SetScrap(1, 100)
        SetPilot(1, 10)
        -- don't do this part after the first shot
        M.startDone = true
        -- #ifdef TEST_PORTAL / SetPerceivedTeam(user, 2); / #endif
        if TEST_PORTAL and Valid(M.user) then SetPerceivedTeam(M.user, 2) end
    end

    if not M.cameraComplete[0] then
        if not M.cameraReady[0] then
            M.cameraReady[0] = true
            CameraReady()
            M.introSound = AudioMessage("bd08001.wav")
        end
        if not M.arrived and Valid(M.user) then
            M.arrived = CameraPath("path_camera_intro", 800, 1500, M.user)
        end
        local seqDone = M.arrived and Done(M.introSound)
        if CameraCancelled() then
            seqDone = true
            if M.introSound ~= nil and M.introSound ~= 0 then
                StopAudioMessage(M.introSound)
            end
        end
        if seqDone then
            M.arrived = false
            CameraFinish()
            M.cameraComplete[0] = true
            M.secondCameraTime = now + 25.0
        end
    end

    if M.secondCameraTime < now and not M.cameraComplete[1] then
        if not M.cameraReady[1] then
            M.cameraReady[1] = true
            CameraReady()
            M.intro2Sound = AudioMessage("bd08002.wav")
            ClearObjectives()
            AddObjective("bd08001.otf", "white")
            M.activateTime = now + 0.5
            -- #ifndef TEST_PORTAL: +90.0f; #else: +15.0f; #endif
            M.apcTime = now + (TEST_PORTAL and 15.0 or 90.0)
        end
        if Valid(M.portal) then
            M.arrived = CameraPath("path_portalcam", 4000, 1000, M.portal)
        end
        if M.arrived or CameraCancelled() or not Valid(M.portal) then
            CameraFinish()
            M.cameraComplete[1] = true
            --StopAudioMessage(M.intro2Sound);
            --M.sound3Time = GetTime() + 5.0;
        end
    end

    if M.activateTime < now then
        Activate(false)
        if Healthy(M.portal) and isPortalActive(M.portal) then
            M.attackWaveTime = now + 1.0
            M.activateTime = NEVER
        end
    end
    -- #ifndef TEST_PORTAL: entire attack-wave block disabled in debug mode.
    if not TEST_PORTAL and M.attackWaveTime < now then
        if M.apcTime < now + 45.0 then
            -- temporarily disable the attack wave so that the apc can arrive
            M.attackWaveTime = NEVER
        else
            local h
            if Healthy(M.portal) then
                h = BuildObjectAtPortal(attackers[math.random(0, 9) + 1], 2, M.portal)
            end
            local path = math.random(0, 99) < 50 and "attack_path1" or "attack_path2"
            if Valid(h) then Goto(h, path, 1) end
            M.waveCount = M.waveCount + 1
            if M.waveCount < 4 then
                M.attackWaveTime = now + 4.0
            else
                M.waveCount = 0
                M.attackWaveTime = now + 30.0
            end
        end
    end

    if M.apcTime < now then
        M.apcTime = NEVER
        if Healthy(M.portal) then M.apc = BuildObjectAtPortal("cvapc", 2, M.portal) end
        -- PORT FIX: native _ASSERTMSG0(apc != NULL, "Failed to create APC")
        -- cannot recover from a failed build. Use the existing APC-loss outcome
        -- rather than continuing with an impossible objective/invalid handle.
        if Healthy(M.apc) then
            Goto(M.apc, "portal_out", 1)
            M.attackWaveTime = now + 30.0
            M.apcPilotTime1 = now + 20.0
            M.sound3Time = now + 1.0
        elseif not M.lost and not M.won then
            M.scheduleLose3 = true
        end
    end

    if M.sound3Time < now then
        M.sound3Time = NEVER
        AudioMessage("bd08003.wav")
    end
    if M.apcPilotTime1 < now then
        M.apcPilotTime1 = NEVER
        if Healthy(M.apc) then
            Stop(M.apc, 1)
            -- Native: o->curPilot = 0;
            -- PORT ADAPTATION: RemovePilot is the stock clean removal API.
            -- It also detaches the now-idle AI, so the later handoff uses GetIn
            -- to restore both the pilot and AI. No HopOut/ejection or extra pilot.
            RemovePilot(M.apc)
            M.pilot = BuildObject("cspilo", 2, M.apc) --PilotGetOut(apc);
            SetPerceivedTeam(M.apc, 0)
            if Healthy(M.pilot) and Healthy(M.portal) then
                Retreat(M.pilot, M.portal, 1)
            end
            M.pilotSpawned1 = true
            ClearObjectives()
            AddObjective("bd08001.otf", "white")
            AddObjective("bd08002.otf", "white")
            SetObjectiveOn(M.apc)
        end
    end

    if M.pilotSpawned1 then
        if Touching(M.pilot, M.portal) then
            RemoveObject(M.pilot)
            M.pilotSpawned1 = false
            -- #ifndef TEST_PORTAL: +9*60.0; #else: +15.0f; #endif
            M.apcPilotTime2 = now + (TEST_PORTAL and 15.0 or 9 * 60.0)
        elseif not Healthy(M.pilot) then
            -- pilot killed before reprogramming the portal
            M.scheduleLose2 = true
            M.pilotSpawned1 = false
        end
    end

    if M.apcPilotTime2 < now then
        M.apcPilotTime2 = NEVER
        M.pilot = BuildObject("cspilo", 2, "spawn_pilot")
        if Healthy(M.apc) then RemovePilot(M.apc) end
        if Healthy(M.pilot) and Healthy(M.apc) then Retreat(M.pilot, M.apc, 1) end
        M.pilotSpawned2 = true
        M.portalReprogrammed = true
        AudioMessage("bd08004.wav")
        if Healthy(M.portal) then DeactivatePortal(M.portal) end
        ClearObjectives()
        AddObjective("bd08002.otf", "green")
        AddObjective("bd08003.otf", "white")
        M.attackWaveTime = NEVER
    end

    if M.pilotSpawned2 and Team(M.apc) == 1 then
        M.pilotSpawned2 = false
        if Healthy(M.pilot) and Healthy(M.apc) then Attack(M.pilot, M.apc) end
    end
    if M.pilotSpawned2 and not Healthy(M.pilot) then
        M.pilot = nil
        M.pilotSpawned2 = false
    end
    if M.pilotSpawned2 and Touching(M.pilot, M.apc) then
        M.pilotSpawned2 = false
        M.apcGoBackTime = now + 25.0
        if GetPilotClass(M.apc) == nil or GetPilotClass(M.apc) == "" then
            -- Native: AiProcess::Attach(this, o); o->curPilot = *(PrjID*)"cspilo";
            -- RemoveObject(pilot); pilot = NULL; SetPerceivedTeam(apc, 2);
            -- PORT ADAPTATION: GetIn performs real boarding and reattaches AI,
            -- which SetPilotClass alone cannot do. Keep the 25-second timer
            -- anchored to contact, not boarding completion. The engine consumes
            -- the pilot; removing it here would cancel the boarding command.
            GetIn(M.pilot, M.apc, 1)
            M.pilotBoarding = true
        elseif Healthy(M.user) then
            Attack(M.pilot, M.user)
        end
    end
    if M.pilotBoarding then
        if Team(M.apc) == 1 then
            -- A capture between command and boarding must not be overwritten.
            M.pilotBoarding = false
            if Healthy(M.pilot) and Healthy(M.apc) then Attack(M.pilot, M.apc) end
        elseif not Valid(M.pilot) and Healthy(M.apc) and IsAliveAndPilot(M.apc) then
            M.pilotBoarding = false
            M.pilot = nil
            SetPerceivedTeam(M.apc, 2)
        elseif not Healthy(M.pilot) or not Healthy(M.apc) then
            M.pilotBoarding = false
        end
    end

    if M.apcGoBackTime < now then
        M.apcGoBackTime = NEVER
        if Healthy(M.apc) and IsAliveAndPilot(M.apc) then
            M.apcHeadingBack = true
            Activate(true)
            Retreat(M.apc, "portal_in", 1)
        end
    end
    if M.apcHeadingBack and Team(M.apc) == 1 then M.apcHeadingBack = false end
    if M.apcHeadingBack and not M.lost and not M.won then
        if Touching(M.apc, M.portal) then
            RemoveObject(M.apc)
            M.apc = nil
            M.apcHeadingBack = false
            -- the player has lost
            M.scheduleLose2 = true
        end
    end

    -- have we lost any significant units?
    if (not Healthy(M.recycler) or
        --GetHealth(factory) <= 0.0f ||
        not Healthy(M.command)) and not M.lost and not M.won then
        M.scheduleLose2 = true
    elseif M.apc ~= nil and not Healthy(M.apc) and not M.lost and not M.won then
        M.apc = nil
        M.scheduleLose3 = true
    end
    if M.scheduleLose2 then
        M.scheduleLose2 = false
        M.loseSound2 = AudioMessage("bd08006.wav")
        M.lost = true
    end
    if M.loseSound2 ~= nil and Done(M.loseSound2) then
        M.loseSound2 = nil
        FailMission(now + 1.0, "bd08lsea.des")
    end
    if M.scheduleLose3 then
        M.scheduleLose3 = false
        M.loseSound3 = AudioMessage("bd08006.wav")
        M.lost = true
    end
    if M.loseSound3 ~= nil and Done(M.loseSound3) then
        M.loseSound3 = nil
        FailMission(now + 1.0, "bd08lseb.des")
    end
    if M.apc ~= nil and not M.apcCommandeered then
        if Team(M.apc) == 1 then M.apcCommandeered = true end
    end
    -- SOURCE QUIRK PRESERVED: capture is a historical latch, not a continuous
    -- ownership test. Do not add a base-return requirement or move this gate.
    if M.apcCommandeered and M.portalReprogrammed and M.winSound == nil
        and not M.won and not M.lost then
        M.won = true
        M.winSound = AudioMessage("bd08007.wav")
    end
    if M.winSound ~= nil and Done(M.winSound) then
        M.winSound = nil
        SucceedMission(now + 1.0, "bd08win.des")
    end
    -- has the portal been destroyed? Source checks this AFTER the victory gate.
    if not Healthy(M.portal) and not M.won and not M.lost then
        M.lost = true
        FailMission(now + 1.0, "bd08lsec.des")
    end
-- CR restored content >>
    if campaignRuntime then Restored.Run() end
-- CR restored content <<
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.AfterUpdate() end
-- CR co-op callback <<
end

function Save()
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Save() end
-- CR co-op callback <<
    return M
end
function Load(state)
    -- LuaMission serializes tables and remaps handles. Native ConvertHandle /
    -- PostLoad is unnecessary; never rerun Setup or replay startup resources.
    M = state
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Load() end
-- CR co-op callback <<
end
-- CR co-op callbacks >>
function AddObject(h) if campaignRuntime then return campaignRuntime.AddObject(h) end end
function CreatePlayer(id,name,team) if campaignRuntime then return campaignRuntime.CreatePlayer(id,name,team) end end
function AddPlayer(id,name,team) if campaignRuntime then return campaignRuntime.AddPlayer(id,name,team) end end
function DeletePlayer(id) if campaignRuntime then return campaignRuntime.DeletePlayer(id) end end
function Receive(from,kind,...) if campaignRuntime then return campaignRuntime.Receive(from,kind,...) end end
-- CR co-op callbacks <<
