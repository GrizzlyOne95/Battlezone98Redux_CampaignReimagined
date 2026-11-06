-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/BDMISN03_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Ganymede weather); outside it this file is
-- the faithful port, byte for byte (Tools/Test-Bdmisn03CoopSourceParity.py).
-- CR co-op layer <<
-- Faithful BlackDog03Mission port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/BlackDog03Mission.cpp
-- Source blob: e7d4bd8942dec9f636b9d7168dca155aedcf47d4.
-- Complete original declarations, comments, and native serialization are archived
-- in References/BlackDog03Source/BlackDog03Mission.cpp. Disabled code is also
-- retained in place below. No EXU/OpenShim or campaign helper is required.
-- Use bd03.lua with the original mission's labels, paths, ODFs, audio, OTFs,
-- and debrief files. This port does not change map mission-class configuration.

-- Preserve C++ array indices. TRO 1.3 pool: 7 cvfigh + 3 cvtnk (70/30) in the random waves.
local randomUnits = {
    [0] = "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvfigh",
    "cvfigh", "cvfigh", "cvtnk", "cvtnk", "cvtnk",
}

local function NewState()
    -- Native Load clears the state before Setup, including unused members.
    return {
        startDone = false,
        objective1Complete = false, objective2Complete = false,
        objective3Complete = false,
        soundComplete = {}, soundHandle = {},
        activateStuff = false, apcSpawned = false, triggerAmbush = false,
        recyclerOnPath = false, recyclerDeployed = false,
        firstRandomAttackDone = false, sound8Played = false,
        lost = false, won = false,
        sound1Delay = 99999.0, sound2Delay = 99999.0,
        sound3Delay = 99999.0, sound4Delay = 99999.0,
        randomDelay = 99999.0,
        spawnRecyclerAttackTime1 = 99999.0,
        spawnRecyclerAttackTime2 = 99999.0,
        spawnRecyclerAttackTime3 = 99999.0, apcAttackTime = 99999.0,
        killMeNow = {}, evilGuys = {},
    }
end

local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/BDMISN03_COOP.md lists every wrapped call and restoration.
-- Each RESTORED_* flag switches one cut-content restoration off (Docs/BDMISN03_COOP.md, "Restored content").
local RESTORED_BASE_START = true -- the cut scavenger and turret at the deployed recycler
local Restored = {}
-- The enemy craft the waves are made of become concealed, head-count-scaled tickets. Static turrets are not.
local SCALED_ODFS = { cvfigh = true, cvfighf = true, cvltnk = true, cvtnk = true }
local sensorsBound = false
if not CR_TEST_FAITHFUL then require("RequireFix").Initialize({"campaignReimagined", "3686673790"}) end -- the asset searcher cuts module names to 11 chars
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "bdmisn03", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2,
    rallyPoints = { [0] = "recycler" }, -- the shared base is wherever the recycler is
    scaledOdfs = SCALED_ODFS,
    liveCap = 16, -- the guards, the first waves and the 90 second raids overlap
    -- A raid whose entry has a human within 460 m comes from the next authored enemy approach instead.
    fallbackEntries = { "spawn_attack_apc", "spawn_random_1", "spawn_random_4", "spawn_random_2", "spawn_random_3" },
    failDes = "bd03lose.des", -- out of lives (every human out): the stock generic debrief
    wonFlags = { "won" },
    endedFlags = { "won", "lost" },
    -- The body also orders Hunt and SetCloaked on units that may still be tickets.
    orders = { "Goto", "Follow", "Attack", "Defend", "Defend2", "SetIndependence", "Retreat", "Hunt", "SetCloaked" },
    weather = { module = "CREuropaWeather", sites = "CRGanymedeSitesBD03", startLevel = 1, targetLevel = 1,
        -- Ganymede under Jupiter: the sun's real path, a short eclipse, Jupiter-shine at night.
        environment = { lightingMode = "orbit", orbit = { period = 1800, startHour = -40 } },
        ops = { "EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge" },
        beats = function(europa, state, s)
            local beats = s.europaBeats
            if beats == nil then beats = {}; s.europaBeats = beats end
            -- The recycler settles on the geyser: the vent wakes, the sky stirs.
            if (not beats.deployed) and state.recyclerDeployed then
                beats.deployed = true
                europa.SetTargetLevel(2)
                for index, site in ipairs(europa.GetVentSites()) do
                    if site.label == "geyser1" then europa.TriggerPlume(index) end
                end
            end
            -- The APC sets out.
            if (not beats.convoy) and state.apcSpawned then
                beats.convoy = true
                europa.SetTargetLevel(3)
            end
            -- The APC is hit or ambushed: the moon flexes.
            if (not beats.assault) and (state.sound8Played or state.triggerAmbush) then
                beats.assault = true
                europa.SetTargetLevel(4)
                europa.Quake(0.35, 3.0)
                europa.Surge(6.0, 0.8)
            end
            -- The APC is home: calm.
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
local GetPlayerHandle = campaignRuntime and campaignRuntime.GetPlayerHandle or GetPlayerHandle
local Goto = campaignRuntime and campaignRuntime.Goto or Goto
local Follow = campaignRuntime and campaignRuntime.Follow or Follow
local Attack = campaignRuntime and campaignRuntime.Attack or Attack
local Defend2 = campaignRuntime and campaignRuntime.Defend2 or Defend2
local Hunt = campaignRuntime and campaignRuntime.Hunt or Hunt
local SetCloaked = campaignRuntime and campaignRuntime.SetCloaked or SetCloaked
local SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
local AudioMessage = campaignRuntime and campaignRuntime.AudioMessage or AudioMessage
local StopAudioMessage = campaignRuntime and campaignRuntime.StopAudioMessage or StopAudioMessage
local CameraReady = campaignRuntime and campaignRuntime.CameraReady or CameraReady
local CameraFinish = campaignRuntime and campaignRuntime.CameraFinish or CameraFinish
local CameraCancelled = campaignRuntime and campaignRuntime.CameraCancelled or CameraCancelled
local SetObjectiveName = campaignRuntime and campaignRuntime.SetObjectiveName or SetObjectiveName
local SetObjectiveOn = campaignRuntime and campaignRuntime.SetObjectiveOn or SetObjectiveOn
local ClearObjectives = campaignRuntime and campaignRuntime.ClearObjectives or ClearObjectives
local AddObjective = campaignRuntime and campaignRuntime.AddObjective or AddObjective
local RemoveObject = campaignRuntime and campaignRuntime.RemoveObject or RemoveObject
local SucceedMission = campaignRuntime and campaignRuntime.SucceedMission or SucceedMission
local FailMission = campaignRuntime and campaignRuntime.FailMission or FailMission
-- The intro shot looks at "the player": that is the nearest-human token, not an object a camera can target.
local CameraPath = campaignRuntime and function(path, height, speed, target)
    if target == campaignRuntime.PLAYERS then target = Restored.CameraTarget() end
    return campaignRuntime.CameraPath(path, height, speed, target)
end or CameraPath
-- A new frame is a new scaling event: the first scaled unit of each scripted group (the guards, a raid, the
-- ambush pair, the random patrols) is mirrored by min(floor(humans / 2), 2) extras of the same kind and orders.
local eventFrame
local BuildObject = campaignRuntime and function(odf, team, where)
    if SCALED_ODFS[odf] then
        local now = GetTime()
        if eventFrame ~= now then
            eventFrame = now
            campaignRuntime.BeginEvent()
        end
    end
    return campaignRuntime.Spawn(odf, team, where)
end or BuildObject
-- CR co-op runtime <<

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function Distance(from, to, point)
    -- PORT FIX: an absent/deleted handle cannot satisfy a proximity trigger.
    -- Protect Lua's overloads; all valid-object distances remain unchanged.
    if not Valid(from) or (type(to) ~= "string" and not Valid(to)) then
        return math.huge
    end
    if point ~= nil then return GetDistance(from, to, point) end
    return GetDistance(from, to)
end

local function Health(h)
    -- Native GetHealth returns zero for an absent object. Preserve that loss
    -- behavior without passing nil through the Lua health binding.
    if not Valid(h) then return 0.0 end
    return GetHealth(h)
end

local function AtEndOfPath(h, path)
    -- PORT ADAPTATION: stock Lua exposes path-point queries rather than the
    -- C++ isAtEndOfPath helper. Path indices are zero based; check the final
    -- waypoint, never the first/default point. A missing path is not arrival.
    -- TRO 1.3: arrival is within 12 m of the last waypoint, measured in 2D (x,z) (FUN_0042b850).
    if not Valid(h) then return false end
    local count = GetPathPointCount(path)
    if count <= 0 then return false end
    local a, b = GetPosition(h), GetPosition(path, count - 1)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz) < 12.0
end

-- CR restored content >>
-- Content the DLL cut, restored in the CR layer only (Docs/BDMISN03_COOP.md quotes the cut block), plus the
-- co-op fixes that need state. Each restoration is gated by a RESTORED_* flag and by the map carrying the path.
if campaignRuntime then
    local runtime = campaignRuntime
    local function RState()
        local s = runtime.State()
        s.r = s.r or {}
        return s.r
    end
    -- M.user is the nearest-human token: the recycler gate fires for ANY human (an approach trigger).
    local faithfulDistance = Distance
    local humanDistance = runtime.WrapDistance(faithfulDistance)
    Distance = function(from, to, point)
        if from == runtime.PLAYERS then return humanDistance(from, to) end
        return faithfulDistance(from, to, point)
    end
    -- The intro camera needs a real object: the host's ship (the authority), else any human, else the recycler.
    function Restored.CameraTarget()
        local host = runtime.Native.GetPlayerHandle()
        if Valid(host) then return host end
        local found
        runtime.Coop.ForEachPlayerHandle(function(h) if found == nil and Valid(h) then found = h end end)
        return found or M.recycler
    end
    -- A load cannot resume a cinematic (the cameras are gone): finish the one that was running, as the body would.
    function Restored.OnLoad()
        if not runtime.Coop.IsAuthority() then return end
        if not M.soundComplete[0] and M.soundHandle[0] ~= nil then
            M.soundHandle[0] = nil
            M.soundComplete[0] = true
        end
        if M.soundComplete[0] and not M.soundComplete[1] and M.soundHandle[1] ~= nil then
            M.soundHandle[1] = nil
            M.soundComplete[1] = true
            RemoveObject(M.killMeNow[0])
            RemoveObject(M.killMeNow[1])
            M.sound1Delay = GetTime() + 60.0
        end
    end
    -- Runs at the end of the body's Update, in the frame the triggering block ran.
    function Restored.Step()
        if not M.startDone or M.won or M.lost then return end
        local r = RState()
        -- Cut: BuildObject("bvscav", 1, "spawn_scav"); BuildObject("bvturr", 1, "spawn_turret"); when the recycler
        -- deploys. Friendly units of the shared team 1, never scaled.
        if RESTORED_BASE_START and M.recyclerDeployed and not r.base then
            r.base = true
            if runtime.PathExists("spawn_scav") then BuildObject("bvscav", 1, "spawn_scav") end
            if runtime.PathExists("spawn_turret") then BuildObject("bvturr", 1, "spawn_turret") end
        end
    end
    local failed
    function Restored.Run()
        local ok, err = pcall(Restored.Step)
        if not ok and not failed then
            failed = true
            print("[bdmisn03] restored content failed: " .. tostring(err))
        end
    end
end
-- CR restored content <<
local function Setup()
    M.startDone = false
    M.objective1Complete = false
    M.objective2Complete = false
    M.objective3Complete = false
    M.activateStuff = false
    M.apcSpawned = false
    M.firstRandomAttackDone = false
    M.recyclerOnPath = false
    M.recyclerDeployed = false
    M.sound8Played = false
    M.triggerAmbush = false

    for i = 0, 9 do
        M.soundComplete[i] = false
        M.soundHandle[i] = nil
    end

    -- handles
    M.recycler = GetHandle("recycler")
    M.navDelta = GetHandle("nav_delta")
    if Valid(M.navDelta) then SetObjectiveName(M.navDelta, "Nav Delta") end
    M.apc = nil
    M.killMeNow[0] = GetHandle("bobcat_kill_me_now")
    M.killMeNow[1] = GetHandle("scout_kill_me_now")
    M.geyser1 = GetHandle("geyser1")
    M.evilGuys[0] = GetHandle("evil_scout1")
    M.evilGuys[1] = GetHandle("evil_scout2")
    M.evilGuys[2] = GetHandle("evil_scout3")
    --evilGuys[3] = GetHandle("evil_scout4");
    --evilGuys[2] = GetHandle("evil_scout5");
    M.evilGuys[3] = GetHandle("evil_tank1")

    -- delays
    M.sound1Delay = 999999.9
    M.sound2Delay = 999999.9
    M.sound3Delay = 999999.9
    M.sound4Delay = 999999.9
    M.randomDelay = 999999.9
    M.spawnRecyclerAttackTime1 = 999999.9
    M.spawnRecyclerAttackTime2 = 999999.9
    M.spawnRecyclerAttackTime3 = 999999.9
    M.apcAttackTime = 999999.9
end

function Start()
    M = NewState()
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Start() end
-- CR co-op callback <<
    Setup()
end

function AddObject(h)
    -- Source AddObject(Handle h) is intentionally empty.
end

function Update(dt)
-- CR co-op callback >>
    if campaignRuntime and not campaignRuntime.Update(dt) then return end
-- CR co-op callback <<
    M.user = GetPlayerHandle() --assigns the player a handle every frame

    if not M.startDone then
        SetScrap(1,8)
        SetPilot(1,10)

        -- don't do this part after the first shot
        M.startDone = true

        ClearObjectives()
        AddObjective("bd03001.otf", "white")

        M.spawnRecyclerAttackTime2 = GetTime() + 7 * 60.0
        M.spawnRecyclerAttackTime3 = GetTime() + 11 * 60.0

        M.apcAttackTime = GetTime() + 9 * 60.0
        M.sound4Delay = GetTime() + 7 * 60.0
        M.randomDelay = GetTime() + 10 * 60.0

        -- get the evil guys to be cloaked
        for i = 0, 3 do
            SetCloaked(M.evilGuys[i])
        end

        SetCloaked(GetHandle("evil_scout4"))
        SetCloaked(GetHandle("evil_scout5"))
    end

    if not M.soundComplete[0] then
        if M.soundHandle[0] == nil then
            -- start the sound
            M.soundHandle[0] = AudioMessage("bd03001.wav")

            CameraReady()
        end

        CameraPath("camera_intro", 1000, 0, M.user)

        if CameraCancelled() then
            StopAudioMessage(M.soundHandle[0])
        end

        if IsAudioMessageDone(M.soundHandle[0]) then
            -- complete
            M.soundHandle[0] = nil
            M.soundComplete[0] = true

            CameraFinish()
        end
    end

    if M.soundComplete[0] and not M.soundComplete[1] then
        if M.soundHandle[1] == nil then
            -- start the sound
            M.soundHandle[1] = AudioMessage("bd03002.wav")

            CameraReady()

            -- get the recycler moving
            Goto(M.recycler, "path_recycler_travel", 1)
            M.recyclerOnPath = true

            -- get the "excort" to follow
            Follow(M.killMeNow[0], M.recycler, 1)
            Follow(M.killMeNow[1], M.recycler, 1)
        end

        CameraPath("camera_recycler", 400, 200, M.recycler)

        if CameraCancelled() then
            StopAudioMessage(M.soundHandle[1])
        end
        if IsAudioMessageDone(M.soundHandle[1]) then
            -- complete
            M.soundHandle[1] = nil
            M.soundComplete[1] = true

            CameraFinish()

            -- remove the stuff
            RemoveObject(M.killMeNow[0])
            RemoveObject(M.killMeNow[1])

            M.sound1Delay = GetTime() + 60.0
        end
    end

    if M.recyclerOnPath and AtEndOfPath(M.recycler, "path_recycler_travel") then
        M.recyclerOnPath = false
        Goto(M.recycler, M.geyser1, 1)

        local t1 = BuildObject("cvturr", 2, "spawn_turret_1")
        local t2 = BuildObject("cvturr", 2, "spawn_turret_2")
        local h = BuildObject("cvfigh", 2, "spawn_turret_guard1")
        SetCloaked(h)
        Defend2(h, t1)
        h = BuildObject("cvfigh", 2, "spawn_turret_guard1")
        SetCloaked(h)
        Defend2(h, t2)
        h = BuildObject("cvfigh", 2, "spawn_turret_guard2")
        SetCloaked(h)
        Defend2(h, t1)
        h = BuildObject("cvfigh", 2, "spawn_turret_guard2")
        SetCloaked(h)
        Defend2(h, t2)
    end

    if not M.recyclerDeployed and Valid(M.recycler) and IsDeployed(M.recycler) then
        M.recyclerDeployed = true
        --BuildObject("bvscav", 1, "spawn_scav");
        --BuildObject("bvturr", 1, "spawn_turret");
        M.spawnRecyclerAttackTime1 = GetTime() + 30.0
    end

    -- recycler attack
    if M.spawnRecyclerAttackTime1 < GetTime() then
        M.spawnRecyclerAttackTime1 = 999999.9

        local h = BuildObject("cvfigh", 2, "spawn_recycler_attack")
        Attack(h, M.recycler, 1)
        h = BuildObject("cvfigh", 2, "spawn_recycler_attack")
        Attack(h, M.recycler, 1)
    end

    if M.spawnRecyclerAttackTime2 < GetTime() then
        M.spawnRecyclerAttackTime2 = 999999.9

        local h = BuildObject("cvfigh", 2, "spawn_recycler_attack")
        SetCloaked(h)
        Goto(h, "path_recycler_attack",0)
        h = BuildObject("cvfigh", 2, "spawn_recycler_attack")
        SetCloaked(h)
        Goto(h, "path_recycler_attack",0)
        h = BuildObject("cvfigh", 2, "spawn_recycler_attack")
        SetCloaked(h)
        Goto(h, "path_recycler_attack",0)
        h = BuildObject("cvtnk", 2, "spawn_recycler_attack")
        SetCloaked(h)
        Goto(h, "path_recycler_attack",0)
        h = BuildObject("cvtnk", 2, "spawn_recycler_attack")
        SetCloaked(h)
        Goto(h, "path_recycler_attack",0)
    end

    if M.spawnRecyclerAttackTime3 < GetTime() then
        M.spawnRecyclerAttackTime3 = 999999.9

        local h = BuildObject("cvfigh", 2, "spawn_recycler_attack")
        Goto(h, "path_recycler_attack", 1)
        h = BuildObject("cvfigh", 2, "spawn_recycler_attack")
        Goto(h, "path_recycler_attack", 1)
    end

    if M.soundComplete[1] and not M.activateStuff then
        M.activateStuff = true
        --[[ #if 0 (cut content; intentionally inactive)
		// get the enemies into hunt mode
		for (i = 0; i < 4; i++)
			Attack(evilGuys[i], user);
        #endif ]]
    end

    if M.sound1Delay < GetTime() and not M.soundComplete[2] then
        if M.soundHandle[2] == nil then
            -- start the sound
            M.soundHandle[2] = AudioMessage("bd03003.wav")

        end

        if IsAudioMessageDone(M.soundHandle[2]) then
            -- complete
            M.soundHandle[2] = nil
            M.soundComplete[2] = true

            M.sound1Delay = 999999.9
            M.sound2Delay = GetTime() + 30.0
        end
    end

    if M.sound2Delay < GetTime() and not M.soundComplete[3] then
        if M.soundHandle[3] == nil then
            -- start the sound
            M.soundHandle[3] = AudioMessage("bd03004.wav")

        end

        if IsAudioMessageDone(M.soundHandle[3]) then
            -- complete
            M.soundHandle[3] = nil
            M.soundComplete[3] = true

            M.sound2Delay = 999999.9
            M.sound3Delay = GetTime() + 10.0

            ClearObjectives()
            AddObjective("bd03001.otf", "white")
            AddObjective("bd03002.otf", "white")
        end
    end

    if M.sound3Delay < GetTime() and not M.soundComplete[4] then
        if M.soundHandle[4] == nil then
            -- start the sound
            M.soundHandle[4] = AudioMessage("bd03005.wav")

        end

        if IsAudioMessageDone(M.soundHandle[4]) then
            -- complete
            M.soundHandle[4] = nil
            M.soundComplete[4] = true

            M.sound3Delay = 999999.9
        end
    end

    -- when the player reaches the reycler by the nav
    if Distance(M.user, M.recycler) < 75.0 and not (M.objective1Complete and M.objective2Complete) then
        M.objective1Complete = true
        M.objective2Complete = true

        -- play the message
        AudioMessage("bd03006.wav")

        ClearObjectives()
        AddObjective("bd03001.otf", "green")
        AddObjective("bd03002.otf", "green")
    end

    if M.sound4Delay < GetTime() and not M.soundComplete[5] then
        if M.soundHandle[5] == nil then
            -- start the sound
            M.soundHandle[5] = AudioMessage("bd03007.wav")

            ClearObjectives()
            AddObjective("bd03003.otf", "white")
        end

        if IsAudioMessageDone(M.soundHandle[5]) then
            -- complete
            M.soundHandle[5] = nil
            M.soundComplete[5] = true

            M.sound4Delay = 999999.9

            M.apc = BuildObject("bvapcb", 1, "spawn_apc")
            Goto(M.apc, "path_apc_travel", 1)
            SetObjectiveOn(M.apc)
            local h = BuildObject("bvraz", 1, "spawn_apc")
            Defend2(h, M.apc)
            h = BuildObject("bvraz", 1, "spawn_apc")
            Defend2(h, M.apc)
            M.apcSpawned = true
        end
    end

    if M.apcAttackTime < GetTime() then
        M.apcAttackTime = 999999.9
        local h
        h = BuildObject("cvfighf", 2, "spawn_attack_apc")
        Attack(h, M.apc)
    end

    if M.randomDelay < GetTime() then
        M.randomDelay = GetTime() + 90.0 -- 1.5 minutes later

        -- spawn random units
        local h
        h = BuildObject(randomUnits[math.random(0, 10 - 1)], 2, "spawn_random_1")
        Attack(h, M.apc)
        h = BuildObject(randomUnits[math.random(0, 10 - 1)], 2, "spawn_random_2")
        Hunt(h, 1)
        h = BuildObject(randomUnits[math.random(0, 10 - 1)], 2, "spawn_random_3")
        Attack(h, M.apc)
        h = BuildObject(randomUnits[math.random(0, 10 - 1)], 2, "spawn_random_4")
        Hunt(h, 1)
    end

    -- has the apc been damaged yet?
    if M.apcSpawned and Health(M.apc) < 0.98 and not M.sound8Played then
        AudioMessage("bd03008.wav")
        M.sound8Played = true
    end

    -- has the apc arrived safely?
    -- SOURCE BUG FIX: arrival is tested before APC death in C++. A wreck still
    -- within 75 m can set won and suppress its own loss. Require positive APC
    -- health here so a destroyed APC takes the original two-message loss chain.
    -- Living APCs retain the same arrival radius, audio, and two-second delay.
    -- Recycler-vs-arrival ordering is otherwise preserved from the source.
    if M.apcSpawned and Health(M.apc) > 0.0 and Distance(M.apc, M.navDelta) < 75.0 and not M.won and not M.lost then
        M.won = true
        M.soundHandle[7] = AudioMessage("bd03009.wav")
    end

    if M.apcSpawned and Distance(M.apc, "trigger_ambush") < 50.0 and not M.triggerAmbush then
        local choices = { [0] = "cvfigh", "cvltnk", "cvtnk" }
        M.triggerAmbush = true

        local h1 = BuildObject(choices[math.random(0, 3 - 1)], 2, "spawn_recycler_attack")
        SetCloaked(h1)
        Follow(h1, M.apc, 0)
        local h2 = BuildObject(choices[math.random(0, 3 - 1)], 2, "spawn_recycler_attack")
        SetCloaked(h2)
        Follow(h2, M.apc, 0)
    end

    if not M.soundComplete[7] and M.soundHandle[7] ~= nil then
        if IsAudioMessageDone(M.soundHandle[7]) then
            M.soundComplete[7] = true
            M.soundHandle[7] = nil
            SucceedMission(GetTime() + 2.0, "bd03win.des")
        end
    end

    -- is the recycler dead?
    if Health(M.recycler) <= 0.0 and not M.lost and not M.won then
        M.lost = true
        M.soundHandle[6] = AudioMessage("bd03012.wav")
    end

    if not M.soundComplete[6] and M.soundHandle[6] ~= nil then
        if IsAudioMessageDone(M.soundHandle[6]) then
            M.soundComplete[6] = true
            M.soundHandle[6] = nil
            FailMission(GetTime() + 2.0, "bd03lsea.des")
        end
    end

    -- is the apc dead?
    if M.apcSpawned and Health(M.apc) <= 0.0 and not M.lost and not M.won then
        M.soundHandle[8] = AudioMessage("bd03010.wav")
        M.lost = true
    end

    if not M.soundComplete[8] and M.soundHandle[8] ~= nil then
        if IsAudioMessageDone(M.soundHandle[8]) then
            M.soundComplete[8] = true
            M.soundHandle[8] = nil
            M.soundHandle[9] = AudioMessage("bd03011.wav")
        end
    end

    if not M.soundComplete[9] and M.soundHandle[9] ~= nil then
        if IsAudioMessageDone(M.soundHandle[9]) then
            M.soundComplete[9] = true
            M.soundHandle[9] = nil
            FailMission(GetTime() + 2.0, "bd03lseb.des")
        end
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
    -- LuaMission restores engine handles and audio-message userdata in tables.
    -- Do not replay Setup, startup spawns, resources, cameras, or timers.
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
