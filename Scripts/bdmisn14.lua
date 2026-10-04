-- BlackDog14Mission.cpp port for stock Battlezone 98 Redux 2.1+ / Lua 5.1.
-- Source blob: 5217e98a56da2b57a53f32b9e3fdad6e788b1a18.
-- Complete source (including declarations, comments, and native serialization):
-- References/BlackDog14Source/BlackDog14Mission.cpp.
-- Requires the original mission's labels, paths, ODFs, AIP, WAV, OTF, and DES
-- assets. Map mission-class wiring is a separate integration step.
-- No EXU/OpenShim or Campaign Reimagined helper is required.

local function NewState()
    return {
        -- bools: record whether the init code has been done
        startDone = false,
        -- objective complete? (objective1Complete is unused in the source)
        objective1Complete = false, objective2Complete = false,
        objective3Complete = false,
        -- camera info (unused); preserve the source's zero-based array indices
        cameraReady = { [0] = false, [1] = false },
        cameraComplete = { [0] = false, [1] = false },
        -- attacks
        attack1 = false, attack2 = false,
        -- have we won/lost?
        wonLost = false,
        -- times: Setup overrides the native Load initialization (99999.0f)
        initialTime = 999999.9, sound2Time = 999999.9,
        sound3Time = 999999.9, sound4Time = 999999.9,
        wavesTime = 999999.9, scavTime = 999999.9,
        -- handles: User stuff, Units, and nav beacons (none in this mission)
        user = nil, lastUser = nil, recycler = nil, chinRecycler = nil, apc = nil,
        -- Sounds: native int IDs become Lua audio-message userdata
        sound1 = nil, sound6 = nil, sound7 = nil, sound8 = nil,
    }
end

local M = NewState()

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function Health(h)
    -- PORT ADAPTATION: an absent/deleted native object has zero health.
    -- Preserve destruction conditions without querying a missing Lua handle.
    if not Valid(h) then return 0.0 end
    return GetHealth(h)
end

local function AtEndOfPath(h, path)
    -- PORT ADAPTATION: isAtEndOfPath is a native helper, not a stock Lua API.
    -- Stock Redux does expose path queries; use the final zero-based waypoint.
    -- UNKNOWN: the supplied source does not define the native arrival radius.
    -- 25 m follows bd03.lua's provisional convention and requires map testing;
    -- this is an explicit approximation, not a recovered native constant.
    if not Valid(h) or Health(h) <= 0.0 then return false end
    local count = GetPathPointCount(path)
    return count > 0 and GetDistance(h, path, count - 1) < 25.0
end

function Start()
    -- Native Load/Setup defaults. LuaMission manages handle conversion on Load.
    M = NewState()
    M.recycler = GetHandle("recycler")
    M.chinRecycler = GetHandle("chin_recycler")
end

function AddObject(h)
    -- Native AddObject(Handle h) is empty; engine bookkeeping is automatic.
end

function Update(dt)

    M.lastUser = M.user
    M.user = GetPlayerHandle() --assigns the player a handle every frame

    -- SOE #1
    if not M.startDone then
        SetAIP("bdmisn14.aip")
        SetScrap(1,4)
        SetPilot(1,10)
        SetScrap(2, 0)
        SetPilot(2, 100)

         -- don't do this part after the first shot
        M.startDone = true

        M.sound1 = AudioMessage("bd14001.wav")

        M.initialTime = GetTime()

         -- cloak some of the units
        SetCloaked(GetHandle("start1_1"))
        SetCloaked(GetHandle("start1_2"))
        SetCloaked(GetHandle("start1_3"))
        SetCloaked(GetHandle("start2_1"))
        SetCloaked(GetHandle("start2_2"))
        SetCloaked(GetHandle("start2_3"))
    end

    if M.sound1 ~= nil and IsAudioMessageDone(M.sound1) then
        M.sound1 = nil
    end

    if M.initialTime < GetTime() then
        M.initialTime = 999999.9

        local h
        h = BuildObject("cvfigh", 2, "spawn_initial_attack")
        SetCloaked(h)
        Goto(h, "path_initial_attack")
        h = BuildObject("cvfigh", 2, "spawn_initial_attack")
        SetCloaked(h)
        Goto(h, "path_initial_attack")
        h = BuildObject("cvfigh", 2, "spawn_initial_attack")
        SetCloaked(h)
        Goto(h, "path_initial_attack")
        h = BuildObject("cvhraz", 2, "spawn_initial_attack")
        SetCloaked(h)
        Goto(h, "path_initial_attack")
        h = BuildObject("cvhraz", 2, "spawn_initial_attack")
        SetCloaked(h)
        Goto(h, "path_initial_attack")

        ClearObjectives()
        AddObjective("bd14001.otf", "white")

        M.sound2Time = GetTime() + 120.0
        M.wavesTime = GetTime() + 240.0
    end

    -- SOE #2
    if M.sound2Time < GetTime() then
        M.sound2Time = 999999.9
        AudioMessage("bd14002.wav")
        ClearObjectives()
        AddObjective("bd14001.otf", "white")
        AddObjective("bd14002.otf", "white")
    end

    -- SOE #3
    if M.wavesTime < GetTime() then
        M.wavesTime = 999999.9

        local h
        h = BuildObject("cvhtnk", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvhtnk", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvfigh", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvfigh", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvfigh", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvfigh", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvltnk", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvltnk", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvltnk", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")

        M.sound3Time = GetTime() + 5 * 60.0
    end

    -- SOE #4 (missing)

    -- SOE #5
    if M.sound3Time < GetTime() then
        M.sound3Time = 999999.9

        AudioMessage("bd14003.wav")

        local h
        M.apc = BuildObject("cvapcc", 2, "spawn_apc")
        SetObjectiveOn(M.apc)
        Goto(M.apc, "path_apc_travel")
        h = BuildObject("cvtnk", 2, "spawn_apc")
        Defend2(h, M.apc)
        h = BuildObject("cvtnk", 2, "spawn_apc")
        Defend2(h, M.apc)
        h = BuildObject("cvtnk", 2, "spawn_apc")
        Defend2(h, M.apc)
        h = BuildObject("cvtnk", 2, "spawn_apc")
        Defend2(h, M.apc)

        --[[ #if 0 (cut content; intentionally inactive)
		// turrets
		h = BuildObject("cvturr", 2, "spawn_turrets");
		Goto(h, "path_turrets");
		h = BuildObject("cvturr", 2, "spawn_turrets");
		Goto(h, "path_turrets");
		h = BuildObject("cvturr", 2, "spawn_turrets");
		Goto(h, "path_turrets");
        #endif ]]
         -- attackers
        h = BuildObject("cvhraz", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvhraz", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvhraz", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvhraz", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvltnk", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvltnk", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvltnk", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvltnk", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        -- SOURCE BUG FIX: each native walker spawn calls SetCloaked(h), where
        -- h still names the last light tank. Cloak w1/w2/w3 instead so the
        -- walkers match their cloaked wave. Unit counts, spawn order, routes,
        -- followers, event conditions, and timers are unchanged; only the
        -- intended cloak state changes (which can affect detection/combat).
        local w1 = BuildObject("cvwalk", 2, "spawn_attack_waves")
        SetCloaked(w1)
        Goto(w1, "path_attack_waves")
        local w2 = BuildObject("cvwalk", 2, "spawn_attack_waves")
        SetCloaked(w2)
        Goto(w2, "path_attack_waves")
        local w3 = BuildObject("cvwalk", 2, "spawn_attack_waves")
        SetCloaked(w3)
        Goto(w3, "path_attack_waves")
        h = BuildObject("cvtnkc", 2, "spawn_attack_waves")
        Follow(h, w1)
        h = BuildObject("cvtnkc", 2, "spawn_attack_waves")
        Follow(h, w2)
        h = BuildObject("cvtnkc", 2, "spawn_attack_waves")
        Follow(h, w3)


        M.sound4Time = GetTime() + 50.0
    end

    -- SOE #6
    if M.sound4Time < GetTime() then
        M.sound4Time = 999999.9

        AudioMessage("bd14004.wav")
    end

    -- SOE #7
    if not M.objective2Complete and M.apc ~= nil and Health(M.apc) <= 0.0 then
        -- PORT ADAPTATION: a deleted APC still completes the intercept, but
        -- its vanished marker needs no mutation through an invalid handle.
        if Valid(M.apc) then SetObjectiveOff(M.apc) end
        M.objective2Complete = true

        AudioMessage("bd14005.wav")

        ClearObjectives()
        AddObjective("bd14002.otf", "green")
        AddObjective("bd14003.otf", "white")

        M.scavTime = GetTime() + 4 * 60.0
    end

    if M.scavTime < GetTime() then
        M.scavTime = 999999.9

        BuildObject("cvscav", 2, "spawn_scav")
        BuildObject("cvscav", 2, "spawn_scav")
    end

    -- SOE #8
    if not M.objective3Complete and Health(M.chinRecycler) <= 0.0 and not M.wonLost then
        M.wonLost = true
        M.objective3Complete = true

        ClearObjectives()
        AddObjective("bd14002.otf", "green")
        AddObjective("bd14003.otf", "green")

        M.sound6 = AudioMessage("bd14006.wav")
    end

    if M.sound6 ~= nil and IsAudioMessageDone(M.sound6) then
        M.sound6 = nil
        SucceedMission(GetTime(), "bd14win.des")
    end

    -- SOE #9
    -- SOURCE BUG FIX: the native test has no APC existence/death guard, even
    -- after SOE #7 records its destruction. A wreck at the endpoint must not
    -- lose an already completed intercept. This only excludes absent/dead APCs;
    -- the living APC's arrival loss and the source's win/loss precedence remain.
    if not M.objective2Complete and not M.objective3Complete and AtEndOfPath(M.apc, "path_apc_travel") and not M.wonLost then
        M.wonLost = true
        M.sound7 = AudioMessage("bd14007.wav")

        ClearObjectives()
        AddObjective("bd14001.otf", "red")
        AddObjective("bd14002.otf", "red")
    end

    if M.sound7 ~= nil and IsAudioMessageDone(M.sound7) then
        M.sound7 = nil
        FailMission(GetTime(), "bd14lsea.des")
    end

    -- SOE #10
    if Health(M.recycler) <= 0.0 and not M.wonLost then
        M.wonLost = true
        M.sound8 = AudioMessage("bd14008.wav")
    end

    if M.sound8 ~= nil and IsAudioMessageDone(M.sound8) then
        M.sound8 = nil
        FailMission(GetTime(), "bd14lseb.des")
    end

    -- PORT FIX: an absent player handle cannot trigger proximity ambushes.
    -- Valid-player distances, thresholds, and one-shot timing are unchanged.
    if not M.attack1 and Valid(M.user) and GetDistance(M.user, "trigger_attack_1") < 150.0 then
        M.attack1 = true

        for i = 0, 3 do
            local h = BuildObject("cvhraz", 2, "spawn_attack_1")
            Goto(h, "path_attack_1")
            SetCloaked(h)
        end
        for i = 0, 3 do
            local h = BuildObject("cvltnk", 2, "spawn_attack_1")
            Goto(h, "path_attack_1")
            SetCloaked(h)
        end
        for i = 0, 1 do
            local h = BuildObject("cvwalk", 2, "spawn_defend")
            Goto(h, "path_defend")
        end
        for i = 0, 4 do
            local h = BuildObject("cvltnk", 2, "spawn_defend")
            Goto(h, "path_defend")
        end
    end

    if not M.attack2 and Valid(M.user) and GetDistance(M.user, "trigger_attack_2") < 150.0 then
        M.attack2 = true

        for i = 0, 5 do
            local h = BuildObject("cvhraz", 2, "spawn_attack_2")
            Goto(h, "path_attack_2")
            SetCloaked(h)
        end
    end
end

function Save()
    -- All mission state, including unused fields and audio handles, is saved.
    return M
end

function Load(state)
    -- Do not replay Setup, resources, audio, or spawns after restoring a game.
    M = state
end
