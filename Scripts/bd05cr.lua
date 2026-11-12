-- BlackDog05Mission.cpp port for stock Battlezone 98 Redux 2.1+ / Lua 5.1.
-- Source: GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/BlackDog05Mission.cpp
-- Source blob: 4446a98596a903f1f7764a0a65ff909645913061.
-- Complete native source, all comments, and serialization scaffolding:
-- References/BlackDog05Source/BlackDog05Mission.cpp.
-- No EXU/OpenShim/project helper dependency. Attach to the original bd05 map.
-- Zero-based arrays, Execute ordering, strict timers and priorities are kept.
-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/BDMISN05_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Ganymede weather); outside it this file is
-- the faithful port above, byte for byte (Tools/Test-Bdmisn05CoopSourceParity.py).
-- CR co-op layer <<

local function NewState()
    return {
        -- record whether the init code has been done
        startDone = false,
        -- have we lost?
        lost = false, won = false,
        -- met the objectives?
        objective1Complete = false, objective2Complete = false,
        -- cameras
        cameraReady = false, cameraComplete = {[0] = false, false},
        -- wait
        waitsInitialized = false,
        waitOver = {[0] = false, false, false, false, false},
        waitTime = {[0] = 99999.0, 99999.0, 99999.0, 99999.0, 99999.0},
        -- quitters
        quittersSpawned = false, quitterMovieDone = false,
        rearAttackTime1 = 999999.9, rearAttackTime2 = 999999.9,
        howitzerTime = 999999.9, quitterDelay = 999999.0,
        bomberTime = 999999.9, portalTime = -1, quitterCamTime = 999999.9,
        -- the user, recycler, portal and audio-message handles start nil.
        -- badguys (0-14 = units, 15-18 = attack1,
        -- 19-22 = attack2, 23-27 = attack3,
        -- 28-33 = attack4
        -- 34-38 = rear_attack 1
        -- 39-43 = rear_attack 2
        -- 44-45 = howit
        units = {},
        -- quiters
        quitters = {},
        numBombers = 0, whichTimer = 0, portalStage = 0,
    }
end

local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/BDMISN05_COOP.md lists every wrapped call and restoration.
-- RESTORED_VOICE_LINES switches the two unused voice lines off (Docs/BDMISN05_COOP.md, "Restored content").
local RESTORED_VOICE_LINES = true
local Restored
-- Every Chinese combat craft of the five waves becomes a concealed, head-count-scaled ticket.
local SCALED_ODFS = { cvfigh = true, cvltnk = true, cvtnk = true, cvhraz = true, cvwalk = true, cvartl = true }
if not CR_TEST_FAITHFUL then require("RequireFix").Initialize({"campaignReimagined", "3686673790"}) end -- the asset searcher cuts module names to 11 chars
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "bdmisn05", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2,
    rallyPoints = { [0] = "recycler" }, -- the shared Black Dog base is the recycler
    scaledOdfs = SCALED_ODFS,
    -- A wave whose entry has a human within 460 m (the artillery and rear-attack points sit next to the base)
    -- comes from the next hidden Chinese approach instead.
    fallbackEntries = { "first_wave", "fourth_wave", "third_wave", "second_wave" },
    liveCap = 20, -- the late waves overlap (a wave every five minutes, rear attacks and artillery on top)
    scrapPerGuest = 10,
    -- No failDes: the game ships no bd05 loss debrief (the mission has no loss of its own; only out of lives fails).
    wonFlags = { "won" },
    endedFlags = { "won" },
    -- The portal's inward pulse is a local effect of the object: every peer starts it on its own copy.
    presentationOps = { PortalIn = function()
        local portal = GetHandle("portal")
        if portal ~= nil and IsValid(portal) then PortalIn(portal) end
    end },
    -- Ganymede: CREuropaWeather over the generated BD05 sites (three geyser vents next to the Black Dog base).
    weather = { module = "CREuropaWeather", sites = "CRGanymedeSitesBD05", glassFrost = 0.5,
        environment = { lightingMode = "orbit", orbit = { period = 1800, startHour = -40 } },
        ops = { "EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge" },
        startLevel = 1, targetLevel = 1,
        beats = function(ganymede, state, s)
            local beats = s.ganymedeBeats
            if beats == nil then beats = {}; s.ganymedeBeats = beats end
            local over = state.waitOver or {}
            local function plume(label)
                for index, site in ipairs(ganymede.GetVentSites()) do
                    if site.label == label then return ganymede.TriggerPlume(index) end
                end
            end
            -- The first Chinese wave breaks the silence: the quiet moon begins to stir.
            if (not beats.stirring) and over[1] then
                beats.stirring = true
                ganymede.SetTargetLevel(2)
            end
            -- The second wave attacks the base: the ice shell flexes and a vent opens under the Black Dogs.
            if (not beats.second) and over[2] then
                beats.second = true
                ganymede.SetTargetLevel(3)
                ganymede.Quake(0.35, 3.0)
                plume("eggeizr14_geyser")
            end
            -- The heavy third wave: another vent answers.
            if (not beats.third) and over[3] then
                beats.third = true
                plume("eggeizr15_geyser")
            end
            -- The last wave: the worst of the sky, Jupiter's radiation surging over the column.
            if (not beats.last) and over[4] then
                beats.last = true
                ganymede.SetTargetLevel(4)
                ganymede.Quake(0.5, 3.5)
                ganymede.Surge(5.0, 0.9)
            end
            -- The base is clear and the portal pulses ("strong electromagnetic pulses"): a surge and a quake.
            if (not beats.pulse) and state.objective2Complete then
                beats.pulse = true
                ganymede.Surge(6.0, 0.8)
                ganymede.Quake(0.35, 3.0)
                plume("eggeizr12_geyser")
            end
            -- The Chinese flee and the sky eases for the debrief.
            if (not beats.easing) and state.won then
                beats.easing = true
                ganymede.SetTargetLevel(2)
            end
        end },
    hooks = {
        built = function(_, h, request, id) if Restored then Restored.Built(h, request, id) end end,
        load = function() if Restored then Restored.OnLoad() end end,
        update = function(R, _, authority) if Restored then Restored.Update(R, authority) end end,
    },
})
local NativeBuildObject, NativeSetCloaked = BuildObject, SetCloaked
local IsValid = campaignRuntime and campaignRuntime.IsValid or IsValid
local IsAlive = campaignRuntime and campaignRuntime.IsAlive or IsAlive
local Goto = campaignRuntime and campaignRuntime.Goto or Goto
local Attack = campaignRuntime and campaignRuntime.Attack or Attack
local Retreat = campaignRuntime and campaignRuntime.Retreat or Retreat
local SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
local AudioMessage = campaignRuntime and campaignRuntime.AudioMessage or AudioMessage
local StopAudioMessage = campaignRuntime and campaignRuntime.StopAudioMessage or StopAudioMessage
-- A line whose audio handle is absent counts as finished, so no gate can wait on it for ever.
local nativeAudioDone = IsAudioMessageDone
local function IsAudioMessageDone(message)
    if message == nil or message == 0 then return true end
    return nativeAudioDone(message)
end
local CameraReady = campaignRuntime and campaignRuntime.CameraReady or CameraReady
-- The opening ends when the shot arrives. The runtime stops driving a shot the host skipped (it releases only the
-- host's own camera), so in a network game that shot would never arrive and the film, the retreat movie and the
-- victory behind them would stall for everyone: a host skip ends the shared opening instead.
local CameraPath = campaignRuntime and function(path, height, speed, target)
    local arrived = campaignRuntime.CameraPath(path, height, speed, target)
    if not arrived and campaignRuntime.Coop.IsNetworkGame() and campaignRuntime.Native.CameraCancelled() then return true end
    return arrived
end or CameraPath
local CameraFinish = campaignRuntime and campaignRuntime.CameraFinish or CameraFinish
local CameraCancelled = campaignRuntime and campaignRuntime.CameraCancelled or CameraCancelled
local ClearObjectives = campaignRuntime and campaignRuntime.ClearObjectives or ClearObjectives
local AddObjective = campaignRuntime and campaignRuntime.AddObjective or AddObjective
local RemoveObject = campaignRuntime and campaignRuntime.RemoveObject or RemoveObject
local SucceedMission = campaignRuntime and campaignRuntime.SucceedMission or SucceedMission
-- The body's team 1 is the one shared Black Dog side: its 10 pilots go to every human team (each human respawns
-- from its own pool); the Chinese are team 2 in the DLL and team 5 here.
local SetPilot = campaignRuntime and function(team, count)
    if team == 1 then
        campaignRuntime.Coop.ForEachHumanTeam(function(humanTeam) if humanTeam ~= 1 then SetPilot(humanTeam, count) end end)
        return SetPilot(1, count)
    end
    if team == 2 then team = 5 end
    return SetPilot(team, count)
end or SetPilot
-- The retreating Chinese column (path "quitters") is the stage of the retreat film: built directly on the enemy
-- team, never as a concealed ticket (the body tests them with IsTouching). Every other Chinese craft is a ticket,
-- and a new scripted wave (a new frame or a new entry path) is a new scaling event: the first unit of each wave
-- is mirrored by min(floor(humans / 2), 2) extras with its orders.
local eventFrame, eventWhere
local BuildObject = campaignRuntime and function(odf, team, where)
    if where == "quitters" then return NativeBuildObject(odf, team == 2 and 5 or team, where) end
    if SCALED_ODFS[odf] then
        local now = GetTime()
        if eventFrame ~= now or eventWhere ~= where then
            eventFrame, eventWhere = now, where
            campaignRuntime.BeginEvent()
        end
    end
    return campaignRuntime.Spawn(odf, team, where)
end or BuildObject
-- The wave units are cloaked: a unit that is still a ticket is cloaked when the real unit is built (Restored.Built).
local SetCloaked = campaignRuntime and function(h)
    if type(h) == "number" and h < 0 then
        if Restored then Restored.DeferCloak(-h) end
        return
    end
    return NativeSetCloaked(h)
end or SetCloaked
local PortalIn = campaignRuntime and function() return campaignRuntime.Present("PortalIn") end or PortalIn
-- CR co-op runtime <<

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function Alive(h)
    return Valid(h) and IsAlive(h)
end

local function SpawnUnit(index, odf, path, command)
    local h = BuildObject(odf, 2, path)
    M.units[index] = h
    -- PORT FIX: failed spawns/deleted targets cannot receive Lua handle calls.
    -- Successful spawns retain the source's cloak and priority-1 commands.
    if Valid(h) then
        SetCloaked(h)
        if Valid(M.recycler) then command(h, M.recycler, 1) end
    end
end

local function resetObjectives()
    ClearObjectives()
    -- objective 1
    if M.objective1Complete then
        AddObjective("bd05001.otf", "green")
    else
        AddObjective("bd05001.otf", "white")
    end
end

-- CR restored content >>
-- The co-op fixes that need state, the weather sensor binding and the unused voice lines
-- (Docs/BDMISN05_COOP.md lists each). The voice lines are gated by RESTORED_VOICE_LINES.
Restored = {}
if campaignRuntime then
    local runtime = campaignRuntime
    local function RState()
        local s = runtime.State()
        s.r = s.r or {}
        return s.r
    end
    local function IsTicket(h) return type(h) == "number" and h < 0 end
    local function NearestHuman(unit)
        local best, bestDistance
        runtime.Coop.ForEachPlayerHandle(function(human)
            if Valid(human) then
                local distance = GetDistance(human, unit)
                if bestDistance == nil or distance < bestDistance then best, bestDistance = human, distance end
            end
        end)
        return best
    end
    -- The body cloaks every wave unit right after building it; for a ticket the cloak waits for the real unit
    -- (and for the extras that mirror it).
    function Restored.DeferCloak(id)
        local r = RState()
        r.cloak = r.cloak or {}
        r.cloak[id] = true
    end
    function Restored.Built(h, request, id)
        local r = RState()
        local key = (request and request.primary) or id
        if r.cloak and r.cloak[key] then NativeSetCloaked(h) end
    end
    local sensorsBound = false
    function Restored.OnLoad()
        sensorsBound = false
        RState().afterLoad = true
    end
    -- A load cannot resume a camera (the shots are gone): a film that was running opens its camera again; the
    -- body keeps calling its CameraPath every frame and ends the film itself.
    function Restored.AfterLoad()
        if M.cameraReady then CameraReady() end
        -- The runtime's Load resets the presentation; republish the objective once the opening is over.
        if M.cameraComplete[0] then resetObjectives() end
    end
    -- Every peer, every frame. The weather director's sensor modifier follows the director once both exist.
    -- Unused voice line bd05007 ("you've blown it!"): the one failure this mission can have is the co-op
    -- out-of-lives result; the line plays once during the seven seconds before the result.
    function Restored.Update(R, authority)
        if not sensorsBound and R.Weather and R.Weather.module.Initialized then
            sensorsBound = true
            pcall(function() require("Environment").BindWeatherSensors("Ganymede", R.Weather.module) end)
        end
        local r = RState()
        if authority and RESTORED_VOICE_LINES and M.coopFailed and not M.won and not r.blown then
            r.blown = true
            AudioMessage("bd05007.wav")
        end
    end
    -- The enemies the body does not track: the co-op extras that mirror each wave and the requests still waiting
    -- for a hidden entry. The body's "everything beaten" test must wait for them too.
    function Restored.EnemiesLeft()
        local s = runtime.State()
        for _, h in ipairs(s.live) do
            if Alive(h) then return true end
        end
        return next(s.arrivals) ~= nil
    end
    -- Stock bug: the waves are ordered against the recycler only while it stands. Once it is gone (or a human built
    -- a new one) every wave unit sits idle where it was built and the mission cannot be finished without a hunt.
    -- They attack the nearest human instead, re-issued every 20 s.
    local function WaveUnits()
        local list, seen = {}, {}
        for i = 15, 45 do
            local h = M.units[i]
            if h ~= nil and not seen[h] then seen[h] = true; list[#list + 1] = h end
        end
        for _, h in ipairs(runtime.State().live) do
            if not seen[h] then seen[h] = true; list[#list + 1] = h end
        end
        return list
    end
    function Restored.Retarget(r)
        if M.recycler == nil or Valid(M.recycler) or M.won then return end
        local now = GetTime()
        if now < (r.retargetAt or 0) then return end
        r.retargetAt = now + 20
        for _, h in ipairs(WaveUnits()) do
            if not IsTicket(h) and Alive(h) then
                local human = NearestHuman(h)
                if human ~= nil then Attack(h, human, 1) end
            end
        end
    end
    -- Unused voice line bd05003 ("Woohoo! Paydirt, time for some action."): the first wave, held back after
    -- bd05002 ("Where are they?"), shows itself: once, when one of its units is within 600 m of a human, or
    -- 90 s after the wave was sent.
    function Restored.FirstWaveLine(r)
        if not RESTORED_VOICE_LINES or r.paydirt or not M.waitOver[1] or M.won then return end
        local now = GetTime()
        r.wave1At = r.wave1At or now
        local contact = false
        for i = 15, 18 do
            local h = M.units[i]
            if h ~= nil and not IsTicket(h) and Alive(h) then
                runtime.Coop.ForEachPlayerHandle(function(human)
                    if Valid(human) and GetDistance(human, h) < 600 then contact = true end
                end)
            end
        end
        if contact or now - r.wave1At >= 90 then
            r.paydirt = true
            AudioMessage("bd05003.wav")
        end
    end
    -- Runs at the end of the body's Update.
    function Restored.Step()
        if not M.startDone then return end
        local r = RState()
        if r.afterLoad then r.afterLoad = nil; Restored.AfterLoad() end
        Restored.Retarget(r)
        Restored.FirstWaveLine(r)
    end
    local failed
    function Restored.Run()
        local ok, err = pcall(Restored.Step)
        if not ok and not failed then
            failed = true
            print("[bdmisn05] restored content failed: " .. tostring(err))
        end
    end
end
-- CR restored content <<
function Start()
    M = NewState()
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Start() end
-- CR co-op callback <<
    -- handles
    M.recycler = GetHandle("recycler")
    M.portal = GetHandle("portal")
    for i = 0, 14 do M.units[i] = GetHandle("unit_" .. (i + 1)) end
    -- Native slots 15..45 and all message handles are null until assigned.
    -- number of bombers built; remaining Setup defaults are in NewState().
end

function AddObject(h)
    -- Native AddObject(Handle) has no active body. Do not enable the cut gate.
    --[==[
#if 0
    if (numBombers >= 7)
        return;

    GameObject *obj = GameObjectHandle::GetObj(h);
    if (obj->GetTeam() == GameObject::GetUserTeam())
    {
        // get the object's team slot
        int slot = obj->GetTeamSlot();

        // get the object's class
        GameObjectClass *c = obj->GetClass();
        _ASSERTE(c != NULL);

        if ((slot >= TEAM_SLOT_MIN_OFFENSE) && (slot <= TEAM_SLOT_MAX_OFFENSE))
        {
            // offensive unit built
            numBombers++;
            if (numBombers == 7)
            {
                objective1Complete = TRUE;
                resetObjectives();

                // start the new counter
                StopCockpitTimer();
                StartCockpitTimer(40 * 60, 60, 10);
                whichTimer = 2;
            }
        }
    }
#endif
    ]==]
end

function Update(dt)
-- CR co-op callback >>
    if campaignRuntime and not campaignRuntime.Update(dt) then return end
-- CR co-op callback <<
    M.user = GetPlayerHandle() -- assigns the player a handle every frame

    if not M.startDone then
        SetScrap(1, 8)
        SetPilot(1, 10)
        -- setup the initial objectives
        ClearObjectives()
        -- portal = BuildObject("cbport", 0, "portal");
        -- don't do this part after the first shot
        M.startDone = true
        --[==[
#if 0
        // debugging stuff
        cameraComplete[0] = TRUE;
        objective1Complete = TRUE;
        objective2Complete = TRUE;
#endif
        ]==]
    end

    -- start the camera going
    if not M.cameraComplete[0] then
        if not M.cameraReady then
            -- get the camera ready
            CameraReady()
            -- start the audio
            M.introSound = AudioMessage("bd05001.wav")
            resetObjectives()
            M.cameraReady = true
        end

        -- PORT FIX: a missing/deleted subject ends the same shot rather than
        -- passing a null handle to CameraPath. Normal arrival is unchanged.
        local arrived = not Valid(M.recycler)
        if not arrived then
            arrived = CameraPath("camera_start_arc", 3000, 2000, M.recycler)
        end
        if CameraCancelled() then
            arrived = true
            if M.introSound ~= nil then StopAudioMessage(M.introSound) end
        end
        if arrived then
            -- if the audio is complete (source actually checks arrival)
            CameraFinish()
            M.cameraComplete[0] = true
            M.cameraReady = false
            ClearObjectives()
            AddObjective("bd05001.otf", "white")
        end
    end

    -- setup the time delays (these run during the intro, as in Execute)
    if not M.waitsInitialized then
        M.waitTime[0] = GetTime() + 240.0
        M.waitTime[1] = GetTime() + 300.0
        M.waitTime[2] = GetTime() + 540.0
        M.waitTime[3] = GetTime() + 840.0
        M.waitTime[4] = GetTime() + 1140.0
        M.howitzerTime = GetTime() + 420
        M.rearAttackTime1 = GetTime() + 450
        M.rearAttackTime2 = GetTime() + 660
        M.waitsInitialized = true
    end

    -- check each of the time delays
    if not M.waitOver[0] and M.waitTime[0] < GetTime() then
        AudioMessage("bd05002.wav")
        M.waitOver[0] = true
    end

    if not M.waitOver[1] and M.waitTime[1] < GetTime() then
        -- spawn first wave
        SpawnUnit(15, "cvfigh", "first_wave", Goto)
        SpawnUnit(16, "cvfigh", "first_wave", Goto)
        SpawnUnit(17, "cvltnk", "first_wave", Goto)
        SpawnUnit(18, "cvltnk", "first_wave", Goto)
        -- these guys should just attack the general base area
        M.waitOver[1] = true
    end

    if not M.waitOver[2] and M.waitTime[2] < GetTime() then
        -- spawn first wave (native comment; this is the second wave)
        SpawnUnit(19, "cvltnk", "second_wave", Attack)
        SpawnUnit(20, "cvltnk", "second_wave", Attack)
        SpawnUnit(21, "cvtnk", "second_wave", Attack)
        SpawnUnit(22, "cvtnk", "second_wave", Attack)
        M.waitOver[2] = true
    end

    if not M.waitOver[3] and M.waitTime[3] < GetTime() then
        SpawnUnit(23, "cvtnk", "third_wave", Goto)
        SpawnUnit(24, "cvtnk", "third_wave", Goto)
        SpawnUnit(25, "cvhraz", "third_wave", Goto)
        SpawnUnit(26, "cvhraz", "third_wave", Goto)
        SpawnUnit(27, "cvwalk", "third_wave", Goto)
        -- attack general base area
        M.waitOver[3] = true
    end

    if not M.waitOver[4] and M.waitTime[4] < GetTime() then
        SpawnUnit(28, "cvtnk", "fourth_wave", Goto)
        SpawnUnit(29, "cvtnk", "fourth_wave", Goto)
        SpawnUnit(30, "cvhraz", "fourth_wave", Goto)
        SpawnUnit(31, "cvhraz", "fourth_wave", Goto)
        SpawnUnit(32, "cvwalk", "fourth_wave", Goto)
        SpawnUnit(33, "cvwalk", "fourth_wave", Goto)
        -- attack anything blackdog
        M.waitOver[4] = true
    end

    if M.rearAttackTime1 < GetTime() then
        M.rearAttackTime1 = 999999.9
        SpawnUnit(34, "cvtnk", "rear_attack", Attack)
        SpawnUnit(35, "cvtnk", "rear_attack", Attack)
        SpawnUnit(36, "cvtnk", "rear_attack", Attack)
        SpawnUnit(37, "cvtnk", "rear_attack", Attack)
        SpawnUnit(38, "cvtnk", "rear_attack", Attack)
    end

    if M.rearAttackTime2 < GetTime() then
        M.rearAttackTime2 = 999999.9
        SpawnUnit(39, "cvtnk", "rear_attack", Attack)
        SpawnUnit(40, "cvtnk", "rear_attack", Attack)
        SpawnUnit(41, "cvtnk", "rear_attack", Attack)
        SpawnUnit(42, "cvtnk", "rear_attack", Attack)
        SpawnUnit(43, "cvtnk", "rear_attack", Attack)
    end

    if M.howitzerTime < GetTime() then
        M.howitzerTime = 999999.9
        SpawnUnit(44, "cvartl", "howit", Goto)
        SpawnUnit(45, "cvartl", "howit", Goto)
    end

    if not M.objective2Complete and M.waitOver[4] then
        -- test to see if everything has been beaten
        local allDead = true
        for i = 0, 45 do
            if Alive(M.units[i]) then
                allDead = false
                break
            end
        end
-- CR co-op gate >>
        if campaignRuntime and allDead and Restored.EnemiesLeft() then allDead = false end
-- CR co-op gate <<
        M.objective2Complete = allDead
        if M.objective2Complete then
            -- SOURCE BUG FIX: objective1Complete's only true assignment is in
            -- disabled AddObject/debug code, but victory still requires it.
            -- Complete the orphaned flag at the existing all-46-dead event.
            -- This repairs the unwinnable gate and green objective display;
            -- no wave, retreat, movie, timing or seven-unit build gate changes.
            M.objective1Complete = true
            AudioMessage("bd05004.wav")
            resetObjectives()
        end
    end

    if M.objective2Complete and not M.quittersSpawned then
        M.quitters[0] = BuildObject("cvtnk", 2, "quitters")
        M.quitters[1] = BuildObject("cvtnk", 2, "quitters")
        M.quitters[2] = BuildObject("cvwalk", 2, "quitters")
        M.quitters[3] = BuildObject("cvwalk", 2, "quitters")
        M.quitters[4] = BuildObject("cspilo", 2, "quitters")
        M.quitters[5] = BuildObject("cvltnk", 2, "quitters")
        -- have these bastards head towards the portal
        for i = 0, 5 do
            if Valid(M.quitters[i]) then Retreat(M.quitters[i], "portal_in", 1) end
        end
        M.quittersSpawned = true
        -- Native activatePortal(portal, true) selects inward activation.
        if Valid(M.portal) then PortalIn(M.portal) end
    end

    if M.quittersSpawned then
        -- Native allGone was always true and its branch was empty. Retained
        -- as inert scaffolding; do not invent an all-six-escaped victory gate.
        local allGone = true
        for i = 0, 5 do
            local h = M.quitters[i]
            if h ~= nil then
                if not Alive(h) then
                    M.quitters[i] = nil
                elseif Valid(M.portal) and IsTouching(h, M.portal) then
                    RemoveObject(h)
                    M.quitters[i] = nil
                end
            end
        end
        if allGone then
            -- empty in the native source
        end
    end

    if M.quittersSpawned and M.cameraComplete[0] and not M.cameraComplete[1] then
        if not M.cameraReady then
            -- get the camera ready
            CameraReady()
            -- start the audio
            M.quitterSound = AudioMessage("bd05005.wav")
            M.quitterCamTime = GetTime() + 15.0
            -- PORT FIX: a failed AudioMessage returns nil, so its completion
            -- branch can never arm the 3-second delay. Treat absent audio as
            -- complete while retaining the 15-second minimum movie duration.
            -- Successful narration still arms the delay only when it ends.
            if M.quitterSound == nil then M.quitterDelay = GetTime() + 3.0 end
            M.cameraReady = true
        end

        local seqDone = false
        if Valid(M.portal) then CameraPath("camera_retreat", 3000, 0, M.portal) end
        -- if we're done the sound, start the time delay
        if M.quitterSound ~= nil and IsAudioMessageDone(M.quitterSound) then
            M.quitterDelay = GetTime() + 3.0
            M.quitterSound = nil
        end
        if M.quitterDelay < GetTime() and M.quitterCamTime < GetTime() then
            seqDone = true
        end
        -- cancelled or out of time?
        -- PORT FIX: absent portal releases an invalid shot via the same exit.
        if seqDone or CameraCancelled() or not Valid(M.portal) then
            -- if the audio is complete (cancellation need not await narration)
            CameraFinish()
            M.cameraComplete[1] = true
            M.cameraReady = false
            M.quitterMovieDone = true
        end
    end

    if M.objective1Complete and M.objective2Complete and M.quitterMovieDone
        and not M.won and not M.lost then
        M.sound6 = AudioMessage("bd05006.wav")
        M.won = true
        -- PORT FIX: absent congratulations audio must not stall success.
        -- Normal playback still waits for the same completion check below.
        if M.sound6 == nil then SucceedMission(GetTime() + 0.1, "bd05win.des") end
    end

    if M.sound6 ~= nil and IsAudioMessageDone(M.sound6) then
        M.sound6 = nil
        -- PORT FIX: the stock Lua API takes absolute mission time; native
        -- SucceedMission(0.1f, ...) is already in the past at this point.
        -- Schedule its intended 0.1-second delay after the same final audio.
        SucceedMission(GetTime() + 0.1, "bd05win.des")
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
    -- LuaMission serializes tables and remaps game handles. Do not rerun
    -- Setup, restart delays, or replay any camera/audio/spawn when loading.
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
