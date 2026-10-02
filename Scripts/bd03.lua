-- Faithful BlackDog03Mission port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/BlackDog03Mission.cpp
-- Source blob: e7d4bd8942dec9f636b9d7168dca155aedcf47d4.
-- Complete original declarations, comments, and native serialization are archived
-- in References/BlackDog03Source/BlackDog03Mission.cpp. Disabled code is also
-- retained in place below. No EXU/OpenShim or campaign helper is required.
-- Use bd03.lua with the original mission's labels, paths, ODFs, audio, OTFs,
-- and debrief files. This port does not change map mission-class configuration.

-- Preserve C++ array indices and the weighted 50/20/20/10 percent unit pool.
local randomUnits = {
    [0] = "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvfigh",
    "cvltnk", "cvltnk", "cvtnk", "cvtnk", "cvrckt",
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
    -- The supplied mission source does not define the native helper's radius.
    -- This explicit 25 m arrival tolerance needs validation on the stock map;
    -- it is an approximation, not a claimed recovered native constant.
    if not Valid(h) then return false end
    local count = GetPathPointCount(path)
    return count > 0 and GetDistance(h, path, count - 1) < 25.0
end

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
    Setup()
end

function AddObject(h)
    -- Source AddObject(Handle h) is intentionally empty.
end

function Update(dt)
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
end

function Save()
    return M
end

function Load(state)
    -- LuaMission restores engine handles and audio-message userdata in tables.
    -- Do not replay Setup, startup spawns, resources, cameras, or timers.
    M = state
end
