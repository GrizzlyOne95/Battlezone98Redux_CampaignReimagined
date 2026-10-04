-- Chinese05Mission.cpp -> stock Battlezone 98 Redux Lua 5.1.
-- Source: GrizzlyOne95/Battlezone_Source, BZ1/from_bz2_dll_src/Chinese05Mission.cpp
-- Source blob: f3a5c27d42d28cabe38b96099e059745c7553354
-- No EXU dependency. All original code/comments are archived verbatim below.
-- Map integration: load this script from a LuaMission using the original ch05 labels,
-- paths, ODFs, audio, objectives and debrief files. No map/assets are changed here.
local MAX_MUST_KILL = 13
local NEVER = 999999.9
local S = {}

-- Native object-list removals translated to a snapshot, so removal cannot invalidate
-- AllObjects traversal. Preserve the source's TWO-character "ns" test, even though
-- its comment says nsp*: narrowing it would change the objects removed.
local function removeMatchingObjects(kind)
    local doomed = {}
    for h in AllObjects() do
        local sig = GetClassSig(h)
        if (kind == "scrap" and GetClassLabel(h) == "scrap") or
           (kind == "ns" and sig and string.lower(string.sub(sig, 1, 2)) == "ns") then
            doomed[#doomed + 1] = h
        end
    end
    for _, h in ipairs(doomed) do RemoveObject(h) end
end

-- The C++ fourth BuildObject argument is an altitude offset. Stock Lua's fourth
-- path argument is a POINT INDEX, so use a vector to preserve the 400 m offset.
local function buildAerialSoldier()
    local pos = GetPosition("aerial_1")
    return BuildObject("sssold", 2, SetVector(pos.x, pos.y + 400, pos.z))
end

local function getBase()
    local bases = {}
    if S.recycler and IsAlive(S.recycler) then bases[#bases + 1] = S.recycler end
    if S.factory and IsAlive(S.factory) then bases[#bases + 1] = S.factory end
    -- if (GetHealth(silo) > 0.0f) h[numH++] = silo; -- cut source target
    if #bases == 0 then return nil end
    return bases[math.random(1, #bases)]
end

function Start()
    S = { mustKill = {} }
    S.startDone = false
    S.objective1Complete = false
    S.objective2Complete = false
    S.objective3Complete = false
    S.mustStayWithin200MetresOfSilo = false
    S.scoutCloseToSilo = false
    S.trigger1 = false
    S.trigger2 = false
    S.tugSpawned = false
    S.tugGotScout = false
    S.closeToScout = false
    S.wave7Spawned = false
    S.scoutsSpawned = false
    S.stayTeam2 = false
    S.mustBeCloseToTug = false

    -- cameras
    S.doHaulCam = false

    -- units
    S.user = nil
    S.silo = GetHandle("silo")
    S.leadScout = nil
    S.followScout1 = nil
    S.followScout2 = nil
    S.followScout3 = nil
    S.neutralScout = nil
    S.tug = nil
    S.tugDefender1 = nil
    S.tugDefender2 = nil
    S.factory = nil
    S.recycler = GetHandle("recycler")
    S.constructor = nil
    S.scout1 = nil
    S.scout2 = nil
    S.artl1 = nil
    S.artl2 = nil

    -- navs
    S.nav1 = nil
    S.navBase = nil

    -- sounds
    S.openingSound = nil
    S.lose1Sound = nil
    S.lose2Sound = nil
    S.winSound = nil
    S.sound3 = nil
    S.sound4 = nil
    S.sound6 = nil
    S.betty6 = nil
    S.betty14 = nil

    -- times
    S.openingSoundTime = 999999.9
    S.sound3Time = 999999.9
    S.sound4Time = 999999.9
    S.sound6Time = 999999.9
    S.betty6Time = 999999.9
    S.betty14Time = 999999.9
    S.removeHaulTime = 999999.9
    S.wave1Time = 999999.9
    S.wave2Time = 999999.9
    S.wave3Time = 999999.9
    S.wave4Time = 999999.9
    S.wave5Time = 999999.9
    S.wave6Time = 999999.9
    S.day1Time = 999999.9
    S.day2Time = 999999.9
    S.day3Time = 999999.9
    S.day4Time = 999999.9
    S.day5Time = 999999.9
    S.day6Time = 999999.9
    S.day7Time = 999999.9
    S.day8Time = 999999.9
    S.annoy1Time = 999999.9
    S.pickupTime = 999999.9
    S.haulCamTime = 999999.9
    S.team1Time = 999999.9
    S.annoy2Time = 999999.9

    -- counters
    S.numMustKill = 0
    -- BUGFIX: source repeats wave6Time and omits wave7Time. Explicitly disable
    -- wave7 until removeHaulTime schedules it; normal mission timing is unchanged.
    S.wave7Time = NEVER
    -- Explicitly reset terminal flags, matching native Load zeroing before Setup.
    S.won, S.lost = false, false
end

-- LuaMission saves/remaps handles and audio message values in serializable tables;
-- retain every mission flag, timer, message, handle and final-wave entry together.
function Save() return S end
function Load(state) S = state end
function AddObject(h) end -- Source callback is empty.

function Update(timestep)

    S.user = GetPlayerHandle() --assigns the player a handle every frame

    if not S.startDone then
        SetPilot(1, 10)
        SetScrap(1, 0)

        -- don't do this part after the first shot
        S.startDone = true

        S.openingSoundTime = GetTime() + 3.0

        S.mustStayWithin200MetresOfSilo = true
        --[==[ Cut/debug block from source:
Handle h = BuildObject("apcamr", 1, "trigger_1");
SetObjectiveOn(h);

wave7Time = GetTime();
SetPerceivedTeam(user, 2);
BuildObject("cvtank", 1, user);
]==]
        ClearObjectives()
        AddObjective("ch05001.otf", "white")

        S.stayTeam2 = true
        Stop(S.recycler, 1)
    end

    if S.stayTeam2 then
        SetPerceivedTeam(S.user, 2)
    end

    if S.openingSoundTime < GetTime() then
        S.openingSoundTime = 999999.9

        S.openingSound = AudioMessage("ch05001.wav")
    end

    if S.openingSound ~= nil  and  IsAudioMessageDone(S.openingSound) then
        S.openingSound = nil
    end

    if S.mustStayWithin200MetresOfSilo  and  GetDistance(S.user, S.silo) > 250.0  and  not S.lost  and  not S.won then
        FailMission(GetTime() + 1.0, "ch05lsea.des")
        S.lost = true
    end

    -- do we have enough scrap?
    if not S.scoutsSpawned  and  GetScrap(1) >= 3 then
        S.scoutsSpawned = true
        S.leadScout = BuildObject("cvfighh", 1, "scout_1")
        SetPerceivedTeam(S.leadScout, 2)
        Goto(S.leadScout, "scout_path", 1)
        S.followScout1 = BuildObject("cvfighh", 1, "scout_2")
        SetPerceivedTeam(S.followScout1, 2)
        --Goto(leadScout, "scout_path", 1);
        Formation(S.followScout1, S.leadScout, 1)
        S.followScout2 = BuildObject("cvfighh", 1, "scout_2")
        SetPerceivedTeam(S.followScout2, 2)
        --Goto(leadScout, "scout_path", 1);
        Formation(S.followScout2, S.leadScout, 1)
        S.followScout3 = BuildObject("cvfighh", 1, "scout_2")
        SetPerceivedTeam(S.followScout3, 2)
        --Goto(leadScout, "scout_path", 1);
        Formation(S.followScout3, S.leadScout, 1)
    end

    if S.scoutsSpawned  and  GetDistance(S.leadScout, S.silo) < 300.0  and  not S.scoutCloseToSilo then
        S.scoutCloseToSilo = true

        AudioMessage("ch05002.wav")
    end

    if S.scoutsSpawned  and  GetDistance(S.leadScout, "trigger_1") < 30.0  and  not S.trigger1 then
        S.trigger1 = true


        RemoveObject(S.followScout1)
        RemoveObject(S.followScout2)
        RemoveObject(S.followScout3)
        RemoveObject(S.leadScout)

        S.sound3Time = GetTime() + 1.0
    end

    if S.sound3Time < GetTime() then
        S.sound3Time = 999999.9

        S.sound3 = AudioMessage("ch05003.wav")
    end

    if S.sound3 ~= nil  and  IsAudioMessageDone(S.sound3) then
        S.sound3 = nil
        S.sound4Time = GetTime() + 5.0
    end

    if S.sound4Time < GetTime() then
        S.sound4Time = 999999.9

        S.sound4 = AudioMessage("ch05004.wav")
        S.mustStayWithin200MetresOfSilo = false
    end

    if S.sound4 ~= nil  and  IsAudioMessageDone(S.sound4) then
        S.sound4 = nil

        -- spawn a nav
        S.nav1 = BuildObject("apcamr", 1, "nav_1")
        SetName(S.nav1, "Last GPS Fix")
        SetUserTarget(S.nav1)

        ClearObjectives()
        AddObjective("ch05001.otf", "green")
        AddObjective("ch05002.otf", "white")
        S.objective1Complete = true
    end

    if GetDistance(S.user, "trigger_1") < 400.0  and  not S.tugSpawned then
        S.tugSpawned = true

        S.neutralScout = BuildObject("cvfigh", 0, "haul_scout")
        RemovePilot(S.neutralScout)
        S.tug = BuildObject("svhaul", 2, "enemy_haul")
        --RemovePilot(smokingUnit);

        -- tug defenders
        S.tugDefender1 = BuildObject("svfigh", 2, "haul_defend")
        Defend2(S.tugDefender1, S.tug)
        RemovePilot(S.tugDefender1) -- native curPilot = 0; remove cleanly without a sniper kill
        S.tugDefender2 = BuildObject("svfigh", 2, "haul_defend")
        Defend2(S.tugDefender2, S.tug)
        RemovePilot(S.tugDefender2) -- native curPilot = 0; remove cleanly without a sniper kill

        S.pickupTime = GetTime() + 0.5
    end

    if S.pickupTime < GetTime() then
        -- time delay so that the scout can form
        S.pickupTime = 999999.9
        Pickup(S.tug, S.neutralScout, 1)

        -- start the haul cam
        S.doHaulCam = true
        S.haulCamTime = GetTime() + 15.0
        CameraReady()
    end

    if S.doHaulCam then
        CameraPath("haul_cam", 800, 0, S.tug)
        if CameraCancelled()  or  S.haulCamTime < GetTime() then
            S.doHaulCam = false
            CameraFinish()
            AudioMessage("ch05005.wav")

            ClearObjectives()
            AddObjective("ch05003.otf", "white")
            SetObjectiveOn(S.tug)

            -- remove all the scrap from the map
            removeMatchingObjects("scrap")
        end
    end

    if S.tugSpawned  and  GetTug(S.neutralScout) == S.tug  and  not S.tugGotScout then
        S.tugGotScout = true

        Goto(S.tug, "haul_path", 1)
        S.mustBeCloseToTug = true
    end

    -- too close to the tug stuff?
    if S.tugSpawned  and  GetDistance(S.user, S.tug) < 175.0  and  not S.lost  and  not S.won then
        S.lost = true
        FailMission(GetTime() + 1.0, "ch05lseb.des")
    end

    if S.mustBeCloseToTug  and  GetDistance(S.user, S.tug) > 500.0  and  not S.lost  and  not S.won then
        S.lost = true
        FailMission(GetTime() + 1.0, "ch05lsed.des")
    end

    if S.tugSpawned  and  GetDistance(S.tug, "trigger_2") < 200  and  not S.trigger2 then
        S.mustBeCloseToTug = false
        S.trigger2 = true
        S.betty6Time = GetTime() + 5.0
    end

    -- play a series of sounds
    if S.betty6Time < GetTime() then
        S.betty6Time = 999999.9

        S.betty6 = AudioMessage("abetty6.wav")
    end

    if S.betty6 ~= nil  and  IsAudioMessageDone(S.betty6) then
        S.betty6 = nil
        S.betty14Time = GetTime() + 5.0
    end

    if S.betty14Time < GetTime() then
        S.betty14Time = 999999.9

        S.betty14 = AudioMessage("abetty14.wav")
    end

    if S.betty14 ~= nil  and  IsAudioMessageDone(S.betty14) then
        S.betty14 = nil
        S.sound6Time = GetTime() + 2.0
    end

    if S.sound6Time < GetTime() then
        S.sound6Time = 999999.9

        S.sound6 = AudioMessage("ch05006.wav")

        ClearObjectives()
        AddObjective("ch05003.otf", "green")
        AddObjective("ch05004.otf", "white")
        S.stayTeam2 = false
        S.team1Time = GetTime() + 10.0
        S.annoy2Time = GetTime() + 4 * 60.0

        SetObjectiveOff(S.tug)
        S.navBase = BuildObject("apcamr", 1, "base_1")
        SetName(S.navBase, "Base")
        SetObjectiveOn(S.navBase)

        --recycler = BuildObject("cvrecy", 1, "convoy");
        Goto(S.recycler, "convoy_path")
        S.scout1 = BuildObject("cvfigh", 1, "convoy")
        S.scout2 = BuildObject("cvfigh", 1, "convoy")
        S.factory = BuildObject("cvmuf", 1, "convoy")
        Goto(S.factory, "convoy_path")
        Follow(S.scout1, S.factory)
        Follow(S.scout2, S.factory)
        S.constructor = BuildObject("cvcnst", 1, "convoy")
        Goto(S.constructor, "convoy_path")

        SetScrap(1, 50)

        -- ok, we want to go thru and remove all nsp*
        removeMatchingObjects("ns")
    end

    if S.annoy2Time < GetTime() then
        S.annoy2Time = GetTime() + 4 * 60.0

        for i = 0, 7 do
            local h = buildAerialSoldier()
            Attack(h, getBase())
        end
    end

    if S.team1Time < GetTime() then
        S.team1Time = 999999.9
        SetPerceivedTeam(S.user, 1)
    end

    if S.navBase ~= nil  and  GetDistance(S.navBase, S.user) < 100.0 then
        SetObjectiveOff(S.navBase)
        S.navBase = nil
    end

    if S.sound6 ~= nil  and  IsAudioMessageDone(S.sound6) then
        S.sound6 = nil

        S.removeHaulTime = GetTime() + 4 *60.0
    end

    if S.removeHaulTime < GetTime() then
        S.removeHaulTime = 999999.9

        RemoveObject(S.neutralScout)
        RemoveObject(S.tug)
        RemoveObject(S.tugDefender1)
        RemoveObject(S.tugDefender2)

        S.wave1Time = GetTime()
        S.wave2Time = GetTime() + 5 * 60.0
        S.wave3Time = GetTime() + 9 * 60.0
        S.wave4Time = GetTime() + 15 * 60.0
        S.wave5Time = GetTime() + 17 * 60.0
        S.wave6Time = GetTime() + 20 * 60.0
        S.wave7Time = GetTime() + 22 * 60.0

        S.day1Time = GetTime() + 2 * 60.0
        S.day2Time = GetTime() + 8 * 60.0
        S.day3Time = GetTime() + 12 * 60.0
        S.day4Time = GetTime() + 16 * 60.0
        S.day5Time = GetTime() + 17 * 60.0
        S.day6Time = GetTime() + 20 * 60.0

        S.annoy1Time = GetTime() + 240.0
    end

    -- wave 1
    if S.wave1Time < GetTime() then
        S.wave1Time = 999999.9

        local h
        h = BuildObject("svwalk", 2, "wave_1")
        Goto(h, "wave_1_path")
        h = BuildObject("svwalk", 2, "wave_1")
        Goto(h, "wave_1_path")
        h = BuildObject("svhraz", 2, "wave_1")
        Goto(h, "wave_1_path")
        h = BuildObject("svhraz", 2, "wave_1")
        Goto(h, "wave_1_path")
        h = BuildObject("svtank", 2, "wave_1")
        Goto(h, "wave_1_path")
        h = BuildObject("svtank", 2, "wave_1")
        Goto(h, "wave_1_path")
        h = BuildObject("svtank", 2, "wave_1")
        Goto(h, "wave_1_path")
    end

    -- wave 2
    if S.wave2Time < GetTime() then
        S.wave2Time = 999999.9

        local h
        h = BuildObject("svhraz", 2, "wave_2")
        Goto(h, "wave_2_path")
        h = BuildObject("svhraz", 2, "wave_2")
        Goto(h, "wave_2_path")
        h = BuildObject("svhraz", 2, "wave_2")
        Goto(h, "wave_2_path")
        h = BuildObject("svhraz", 2, "wave_2")
        Goto(h, "wave_2_path")
        h = BuildObject("svfigh", 2, "wave_2")
        Goto(h, "wave_2_path")
        h = BuildObject("svfigh", 2, "wave_2")
        Goto(h, "wave_2_path")
        h = BuildObject("svfigh", 2, "wave_2")
        Goto(h, "wave_2_path")
        h = BuildObject("svrckt", 2, "wave_2")
        Goto(h, "wave_2_path")
        h = BuildObject("svrckt", 2, "wave_2")
        Goto(h, "wave_2_path")
    end

    -- wave 3
    if S.wave3Time < GetTime() then
        S.wave3Time = 999999.9

        local h
        h = BuildObject("sssold", 2, "wave_3")
        Attack(h, getBase())
        h = BuildObject("sssold", 2, "wave_3")
        Attack(h, getBase())
        h = BuildObject("sssold", 2, "wave_3")
        Attack(h, getBase())
        h = BuildObject("sssold", 2, "wave_3")
        Attack(h, getBase())
        h = BuildObject("sssold", 2, "wave_3")
        Attack(h, getBase())
        h = BuildObject("ssuser", 2, "wave_3")
        Attack(h, S.user)
        h = BuildObject("ssuser", 2, "wave_3")
        Attack(h, S.user)
    end

    -- wave 4
    if S.wave4Time < GetTime() then
        S.wave4Time = 999999.9

        local h
        h = BuildObject("svtank", 2, "wave_4")
        Goto(h, "wave_4_path")
        h = BuildObject("svtank", 2, "wave_4")
        Goto(h, "wave_4_path")
        h = BuildObject("svtank", 2, "wave_4")
        Goto(h, "wave_4_path")
        h = BuildObject("svtank", 2, "wave_4")
        Goto(h, "wave_4_path")
        h = BuildObject("svtank", 2, "wave_4")
        Goto(h, "wave_4_path")
        h = BuildObject("svtank", 2, "wave_4")
        Goto(h, "wave_4_path")
        h = BuildObject("svtank", 2, "wave_4")
        Goto(h, "wave_4_path")
        h = BuildObject("svltnk", 2, "wave_4")
        Goto(h, "wave_4_path")
        h = BuildObject("svltnk", 2, "wave_4")
        Goto(h, "wave_4_path")
        h = BuildObject("svltnk", 2, "wave_4")
        Goto(h, "wave_4_path")
    end

    -- wave 5
    if S.wave5Time < GetTime() then
        S.wave5Time = 999999.9

        local h
        h = BuildObject("svwalk", 2, "wave_5")
        Goto(h, "wave_5_path")
        h = BuildObject("svwalk", 2, "wave_5")
        Goto(h, "wave_5_path")
        h = BuildObject("svwalk", 2, "wave_5")
        Goto(h, "wave_5_path")
        h = BuildObject("svwalk", 2, "wave_5")
        Goto(h, "wave_5_path")
        h = BuildObject("svfigh", 2, "wave_5")
        Goto(h, "wave_5_path")
        h = BuildObject("svfigh", 2, "wave_5")
        Goto(h, "wave_5_path")
        h = BuildObject("svfigh", 2, "wave_5")
        Goto(h, "wave_5_path")
        h = BuildObject("svfigh", 2, "wave_5")
        Goto(h, "wave_5_path")
        h = BuildObject("svrckt", 2, "wave_5")
        Goto(h, "wave_5_path")
        h = BuildObject("svrckt", 2, "wave_5")
        Goto(h, "wave_5_path")
        h = BuildObject("svtank", 2, "wave_5")
        Goto(h, "wave_5_path")
        h = BuildObject("svtank", 2, "wave_5")
        Goto(h, "wave_5_path")
        h = BuildObject("svtank", 2, "wave_5")
        Goto(h, "wave_5_path")
    end

    -- wave 6
    if S.wave6Time < GetTime() then
        S.wave6Time = 999999.9

        local h
        h = BuildObject("svltnk", 2, "wave_6")
        Goto(h, "wave_6_path")
        h = BuildObject("svltnk", 2, "wave_6")
        Goto(h, "wave_6_path")
        h = BuildObject("svltnk", 2, "wave_6")
        Goto(h, "wave_6_path")
        h = BuildObject("svltnk", 2, "wave_6")
        Goto(h, "wave_6_path")
        h = BuildObject("svltnk", 2, "wave_6")
        Goto(h, "wave_6_path")
        h = BuildObject("svltnk", 2, "wave_6")
        Goto(h, "wave_6_path")
        h = BuildObject("svltnk", 2, "wave_6")
        Goto(h, "wave_6_path")
        h = BuildObject("svltnk", 2, "wave_6")
        Goto(h, "wave_6_path")
    end

    -- wave 7
    if S.wave7Time < GetTime() then
        S.wave7Time = 999999.9

        S.mustKill[S.numMustKill] = BuildObject("svwalk", 2, "wave_7")
        Goto(S.mustKill[S.numMustKill], "wave_7_path")
        S.numMustKill = S.numMustKill + 1
        S.mustKill[S.numMustKill] = BuildObject("svwalk", 2, "wave_7")
        Goto(S.mustKill[S.numMustKill], "wave_7_path")
        S.numMustKill = S.numMustKill + 1
        S.mustKill[S.numMustKill] = BuildObject("svwalk", 2, "wave_7")
        Goto(S.mustKill[S.numMustKill], "wave_7_path")
        S.numMustKill = S.numMustKill + 1
        S.mustKill[S.numMustKill] = BuildObject("svwalk", 2, "wave_7")
        Goto(S.mustKill[S.numMustKill], "wave_7_path")
        S.numMustKill = S.numMustKill + 1
        S.mustKill[S.numMustKill] = BuildObject("svhraz", 2, "wave_7")
        Goto(S.mustKill[S.numMustKill], "wave_7_path")
        S.numMustKill = S.numMustKill + 1
        S.mustKill[S.numMustKill] = BuildObject("svhraz", 2, "wave_7")
        Goto(S.mustKill[S.numMustKill], "wave_7_path")
        S.numMustKill = S.numMustKill + 1
        S.mustKill[S.numMustKill] = BuildObject("svhraz", 2, "wave_7")
        Goto(S.mustKill[S.numMustKill], "wave_7_path")
        S.numMustKill = S.numMustKill + 1
        S.mustKill[S.numMustKill] = BuildObject("svhraz", 2, "wave_7")
        Goto(S.mustKill[S.numMustKill], "wave_7_path")
        S.numMustKill = S.numMustKill + 1
        S.mustKill[S.numMustKill] = BuildObject("svtank", 2, "wave_7")
        Goto(S.mustKill[S.numMustKill], "wave_7_path")
        S.numMustKill = S.numMustKill + 1
        S.mustKill[S.numMustKill] = BuildObject("svtank", 2, "wave_7")
        Goto(S.mustKill[S.numMustKill], "wave_7_path")
        S.numMustKill = S.numMustKill + 1
        S.mustKill[S.numMustKill] = BuildObject("svtank", 2, "wave_7")
        Goto(S.mustKill[S.numMustKill], "wave_7_path")
        S.numMustKill = S.numMustKill + 1
        S.mustKill[S.numMustKill] = BuildObject("svtank", 2, "wave_7")
        Goto(S.mustKill[S.numMustKill], "wave_7_path")
        S.numMustKill = S.numMustKill + 1
        S.mustKill[S.numMustKill] = BuildObject("svapc", 2, "wave_7")
        Goto(S.mustKill[S.numMustKill], "wave_7_path")
        S.numMustKill = S.numMustKill + 1
        assert(S.numMustKill <= MAX_MUST_KILL)

        S.wave7Spawned = true
    end

    -- daywrecker 1
    if S.day1Time < GetTime() then
        S.day1Time = 999999.9
        BuildObject("apwrck", 0, "day_1")
    end

    -- daywrecker 2
    if S.day2Time < GetTime() then
        S.day2Time = 999999.9
        BuildObject("apwrck", 0, "day_2")
    end

    -- daywrecker 3
    if S.day3Time < GetTime() then
        S.day3Time = 999999.9
        BuildObject("apwrck", 0, "day_3")
    end

    -- daywrecker 4
    if S.day4Time < GetTime() then
        S.day4Time = 999999.9
        BuildObject("apwrck", 0, "day_4")
    end

    -- daywrecker 5
    if S.day5Time < GetTime() then
        S.day5Time = 999999.9
        BuildObject("apwrck", 0, "day_5")

        -- spawn the artilary
        AudioMessage("ch05007.wav")
        S.artl1 = BuildObject("svartl", 2, "artl_1")
        S.artl2 = BuildObject("svartl", 2, "artl_2")
        local h
        h = BuildObject("svfigh", 2, "artl_defend")
        Defend2(h, S.artl1)
        h = BuildObject("svfigh", 2, "artl_defend")
        Defend2(h, S.artl1)
        h = BuildObject("svfigh", 2, "artl_defend")
        Defend2(h, S.artl2)
        h = BuildObject("svfigh", 2, "artl_defend")
        Defend2(h, S.artl2)

        S.day7Time = GetTime() + 5 * 60.0
        S.day8Time = GetTime() + 5 * 60.0 + 20.0
    end

    -- daywrecker 6
    if S.day6Time < GetTime() then
        S.day6Time = 999999.9
        BuildObject("apwrck", 0, "day_6")
    end

    -- daywrecker 7
    if S.day7Time < GetTime() then
        S.day7Time = 999999.9
        BuildObject("apwrck", 0, "day_7")
    end

    -- daywrecker 8
    if S.day8Time < GetTime() then
        S.day8Time = 999999.9
        BuildObject("apwrck", 0, "day_8")
    end

    -- Destroyed handles need no property query; IsAlive preserves the native <=0 test.
    if S.artl1 ~= nil  and  S.artl2 ~= nil  and  not IsAlive(S.artl1) and not IsAlive(S.artl2) then
        S.artl1 = nil
        S.artl2 = nil
        S.day1Time = 999999.9
        S.day2Time = 999999.9
        S.day3Time = 999999.9
        S.day4Time = 999999.9
        S.day5Time = 999999.9
        S.day6Time = 999999.9
        S.day7Time = 999999.9
        S.day8Time = 999999.9
    end

    if S.annoy1Time < GetTime() then
        S.annoy1Time = GetTime() + 240.0

        local paths = { "annoy_path_1", "annoy_path_2" }
        local p = paths[math.random(1, 2)]
        local h
        h = BuildObject("svltnk", 2, "annoy_1")
        Goto(h, p)
        h = BuildObject("svltnk", 2, "annoy_1")
        Goto(h, p)
        h = BuildObject("svtank", 2, "annoy_1")
        Goto(h, p)
        h = BuildObject("svtank", 2, "annoy_1")
        Goto(h, p)
        h = BuildObject("svrckt", 2, "annoy_1")
        Goto(h, p)
        h = BuildObject("svfigh", 2, "annoy_1")
        Goto(h, p)
    end

    -- Same native both-producers-destroyed failure, without querying dead properties.
    if S.recycler ~= nil  and  S.factory ~= nil  and  not IsAlive(S.recycler) and not IsAlive(S.factory)  and  not S.lost  and  not S.won then
        S.lost = true
        FailMission(GetTime() + 1.0, "ch05lsec.des")
    end

    if S.wave7Spawned  and  not S.won  and  not S.lost then
        S.won = true
        for i = 0, S.numMustKill - 1 do
            if IsAlive(S.mustKill[i]) then
                S.won = false
                break
            end
        end

        if S.won then
            SucceedMission(GetTime() + 1.0, "ch05win.des")
        end
    end
end


--[====[
Original C++ source, including every comment, disabled block and save/load wrapper.
#include "GameCommon.h"
#include "AiCommon.h"
#include "AiMission.h"
#include "AiProcess.h"
#include "PowerUp.h"
#include "ScriptUtils.h"
#include "Scrap.h"

#define MAX_MUST_KILL	13

/*
	Chinese05Mission
*/

class Chinese05Mission : public AiMission {
	DECLARE_RTIME(Chinese05Mission)
public:
	Chinese05Mission();
	~Chinese05Mission();

	virtual bool Load(file fp);
	virtual bool PostLoad(void);
	virtual bool Save(file fp);

	virtual void Update(void);

	virtual void AddObject(GameObject *gameObj);

private:
	void Setup();
	void Execute();
	void AddObject(Handle h);
	Handle getBase();
	
	// bools
	union {
		struct {
			bool
				// record whether the init code has been done
				startDone,

				// objectives
				objective1Complete,
				objective2Complete,
				objective3Complete,

				// cameras
				doHaulCam,
				
				// scouts spawned?
				scoutsSpawned,

				// limits?
				mustStayWithin200MetresOfSilo,

				// scout close to the silo?
				scoutCloseToSilo,
				trigger1,
				trigger2,

				// tug been spawned yet?
				tugSpawned,
				tugGotScout,
				mustBeCloseToTug,

				// got to the scout
				closeToScout,

				// last waves spawned?
				wave7Spawned,

				// Stay team 2
				stayTeam2,

				// won or lost?
				won, lost,
				
				b_last;
		};
		bool b_array[18];
	};

	// floats
	union {
		struct {
			float
				openingSoundTime,
				sound3Time,
				sound4Time,
				sound6Time,
				betty6Time,
				betty14Time,
				removeHaulTime,

				// wave times
				wave1Time,
				wave2Time,
				wave3Time,
				wave4Time,
				wave5Time,
				wave6Time,
				wave7Time,

				// day wrecker times
				day1Time,
				day2Time,
				day3Time,
				day4Time,
				day5Time,
				day6Time,
				day7Time,
				day8Time,

				annoy1Time,
				annoy2Time,

				pickupTime,
				haulCamTime,

				team1Time,
				f_last;
		};
		float f_array[27];
	};

	// handles
	union {
		struct {
			Handle
				// the user
				user,
				
				// units
				silo,
				leadScout,
				followScout1,
				followScout2,
				followScout3,
				neutralScout,
				tug, tugDefender1, tugDefender2,
				recycler, factory, scout1, scout2, constructor,
				artl1, artl2,
				mustKill[MAX_MUST_KILL],
				smokingUnit,
				
				// navs
				nav1,
				navBase,
				
				// place holder
				h_last;
		};
		Handle h_array[20 + MAX_MUST_KILL];
	};

	// integers
	union {
		struct {
			int
				// sounds
				openingSound,
				sound3, sound4,
				sound6, betty6, betty14,
				lose1Sound,
				lose2Sound,
				winSound,

				// counters
				numMustKill,
				
				i_last;
		};
		int i_array[10];
	};
};

IMPLEMENT_RTIME(Chinese05Mission)

Chinese05Mission::Chinese05Mission()
{
}

Chinese05Mission::~Chinese05Mission()
{
}

bool Chinese05Mission::Load(file fp)
{
	if (missionSave) 
	{
		int i;

		// init bools
		int b_count = &b_last - b_array;
		_ASSERTE(b_count == SIZEOF(b_array));
		for (i = 0; i < b_count; i++)
			b_array[i] = false;

		// init floats
		int f_count = &f_last - f_array;
		_ASSERTE(f_count == SIZEOF(f_array));
		for (i = 0; i < f_count; i++)
			f_array[i] = 99999.0f;

		// init handles
		int h_count = &h_last - h_array;
		_ASSERTE(h_count == SIZEOF(h_array));
		for (i = 0; i < h_count; i++)
			h_array[i] = 0;

		// init ints
		int i_count = &i_last - i_array;
		_ASSERTE(i_count == SIZEOF(i_array));
		for (i = 0; i < i_count; i++)
			i_array[i] = 0;

		Setup();
		return AiMission::Load(fp);
	}

	bool ret = true;

	// bools
	int b_count = &b_last - b_array;
	_ASSERTE(b_count == SIZEOF(b_array));
	ret = ret && in(fp, b_array, sizeof(b_array));

	// floats
	int f_count = &f_last - f_array;
	_ASSERTE(f_count == SIZEOF(f_array));
	ret = ret && in(fp, f_array, sizeof(f_array));

	// Handles
	int h_count = &h_last - h_array;
	_ASSERTE(h_count == SIZEOF(h_array));
	ret = ret && in(fp, h_array, sizeof(h_array));

	// ints
	int i_count = &i_last - i_array;
	_ASSERTE(i_count == SIZEOF(i_array));
	ret = ret && in(fp, i_array, sizeof(i_array));

	ret = ret && AiMission::Load(fp);
	return ret;
}

bool Chinese05Mission::PostLoad(void)
{
	if (missionSave)
		return AiMission::PostLoad();

	bool ret = true;

	int h_count = &h_last - h_array;
	for (int i = 0; i < h_count; i++)
		h_array[i] = ConvertHandle(h_array[i]);

	ret = ret && AiMission::PostLoad();

	return ret;
}

bool Chinese05Mission::Save(file fp)
{
	if (missionSave)
		return AiMission::Save(fp);

	bool ret = true;

	// bools
	int b_count = &b_last - b_array;
	_ASSERTE(b_count == SIZEOF(b_array));
	ret = ret && out(fp, b_array, sizeof(b_array), "b_array");

	// floats
	int f_count = &f_last - f_array;
	_ASSERTE(f_count == SIZEOF(f_array));
	ret = ret && out(fp, f_array, sizeof(f_array), "f_array");

	// Handles
	int h_count = &h_last - h_array;
	_ASSERTE(h_count == SIZEOF(h_array));
	ret = ret && out(fp, h_array, sizeof(h_array), "h_array");

	// ints
	int i_count = &i_last - i_array;
	_ASSERTE(i_count == SIZEOF(i_array));
	ret = ret && out(fp, i_array, sizeof(i_array), "i_array");

	ret = ret && AiMission::Save(fp);
	return ret;
}

void Chinese05Mission::AddObject(GameObject *gameObj)
{
	AddObject(gameObj->GetHandle());
	AiMission::AddObject(gameObj);
}

void Chinese05Mission::AddObject(Handle h)
{
}

void Chinese05Mission::Update(void)
{
	AiMission::Update();
	Execute();
}

void Chinese05Mission::Setup()
{
	int i = 0;
	startDone = FALSE;
	objective1Complete = FALSE;
	objective2Complete = FALSE;
	objective3Complete = FALSE;
	mustStayWithin200MetresOfSilo = FALSE;
	scoutCloseToSilo = FALSE;
	trigger1 = FALSE;
	trigger2 = FALSE;
	tugSpawned = FALSE;
	tugGotScout = FALSE;
	closeToScout = FALSE;
	wave7Spawned = FALSE;
	scoutsSpawned = FALSE;
	stayTeam2 = FALSE;
	mustBeCloseToTug = FALSE;
	
	// cameras
	doHaulCam = FALSE;
	
	// units
	user = NULL;
	silo = GetHandle("silo");
	leadScout = NULL;
	followScout1 = NULL;
	followScout2 = NULL;
	followScout3 = NULL;
	neutralScout = NULL;
	tug = NULL;
	tugDefender1 = NULL;
	tugDefender2 = NULL;
	factory = NULL;
	recycler = GetHandle("recycler");
	constructor = NULL;
	scout1 = NULL;
	scout2 = NULL;
	artl1 = NULL;
	artl2 = NULL;
	
	// navs
	nav1 = NULL;
	navBase = NULL;
	
	// sounds
	openingSound = NULL;
	lose1Sound = NULL;
	lose2Sound = NULL;
	winSound = NULL;
	sound3 = NULL;
	sound4 = NULL;
	sound6 = NULL;
	betty6 = NULL;
	betty14 = NULL;
	
	// times
	openingSoundTime = 999999.9f;
	sound3Time = 999999.9f;
	sound4Time = 999999.9f;
	sound6Time = 999999.9f;
	betty6Time = 999999.9f;
	betty14Time = 999999.9f;
	removeHaulTime = 999999.9f;
	wave1Time = 999999.9f;
	wave2Time = 999999.9f;
	wave3Time = 999999.9f;
	wave4Time = 999999.9f;
	wave5Time = 999999.9f;
	wave6Time = 999999.9f;
	wave6Time = 999999.9f;
	day1Time = 999999.9f;
	day2Time = 999999.9f;
	day3Time = 999999.9f;
	day4Time = 999999.9f;
	day5Time = 999999.9f;
	day6Time = 999999.9f;
	day7Time = 999999.9f;
	day8Time = 999999.9f;
	annoy1Time = 999999.9f;
	pickupTime = 999999.9f;
	haulCamTime = 999999.9f;
	team1Time = 999999.9f;
	annoy2Time = 999999.9f;

	// counters
	numMustKill = 0;
}

Handle Chinese05Mission::getBase()
{
	Handle h[3];
	int numH = 0;
	if (GetHealth(recycler) > 0.0f)
		h[numH++] = recycler;
	if (GetHealth(factory) > 0.0f)
		h[numH++] = factory;
//	if (GetHealth(silo) > 0.0f)
//		h[numH++] = silo;

	if (numH == 0)
		return NULL;
	else
		return h[rand() % numH];
}

void Chinese05Mission::Execute()
{
	int i = 0;
	user = GetPlayerHandle(); //assigns the player a handle every frame

	if (!startDone)
	{
		SetPilot(1, 10);
		SetScrap(1, 0);

		// don't do this part after the first shot
		startDone = TRUE;

		openingSoundTime = GetTime() + 3.0;
		
		mustStayWithin200MetresOfSilo = TRUE;
#if 0
		Handle h = BuildObject("apcamr", 1, "trigger_1");
		SetObjectiveOn(h);

		wave7Time = GetTime();		
		SetPerceivedTeam(user, 2);
		BuildObject("cvtank", 1, user);
#endif
		ClearObjectives();
		AddObjective("ch05001.otf", WHITE);

		stayTeam2 = TRUE;
		Stop(recycler, 1);
	}

	if (stayTeam2)
		SetPerceivedTeam(user, 2);

	if (openingSoundTime < GetTime())
	{
		openingSoundTime = 999999.9f;

		openingSound = AudioMessage("ch05001.wav");
	}

	if (openingSound != NULL && IsAudioMessageDone(openingSound))
	{
		openingSound = NULL;
	}

	if (mustStayWithin200MetresOfSilo && GetDistance(user, silo) > 250.0 && !lost && !won)
	{
		FailMission(GetTime() + 1.0f, "ch05lsea.des");
		lost = TRUE;
	}

	// do we have enough scrap?
	if (!scoutsSpawned && GetScrap(1) >= 3)
	{
		scoutsSpawned = TRUE;
		leadScout = BuildObject("cvfighh", 1, "scout_1");
		SetPerceivedTeam(leadScout, 2);
		Goto(leadScout, "scout_path", 1);
		followScout1 = BuildObject("cvfighh", 1, "scout_2");
		SetPerceivedTeam(followScout1, 2);
		//Goto(leadScout, "scout_path", 1);
		Formation(followScout1, leadScout, 1);
		followScout2 = BuildObject("cvfighh", 1, "scout_2");
		SetPerceivedTeam(followScout2, 2);
		//Goto(leadScout, "scout_path", 1);
		Formation(followScout2, leadScout, 1);
		followScout3 = BuildObject("cvfighh", 1, "scout_2");
		SetPerceivedTeam(followScout3, 2);
		//Goto(leadScout, "scout_path", 1);
		Formation(followScout3, leadScout, 1);
	}

	if (scoutsSpawned && GetDistance(leadScout, silo) < 300.0f &&
		!scoutCloseToSilo)
	{
		scoutCloseToSilo = TRUE;

		AudioMessage("ch05002.wav");
	}

	if (scoutsSpawned && GetDistance(leadScout, "trigger_1") < 30.0 &&
		!trigger1)
	{
		trigger1 = TRUE;

		
		RemoveObject(followScout1);
		RemoveObject(followScout2);
		RemoveObject(followScout3);
		RemoveObject(leadScout);

		sound3Time = GetTime() + 1.0f;
	}

	if (sound3Time < GetTime())
	{
		sound3Time = 999999.9f;

		sound3 = AudioMessage("ch05003.wav");
	}

	if (sound3 != NULL && IsAudioMessageDone(sound3))
	{
		sound3 = NULL;
		sound4Time = GetTime() + 5.0f;
	}

	if (sound4Time < GetTime())
	{
		sound4Time = 999999.9f;

		sound4 = AudioMessage("ch05004.wav");
		mustStayWithin200MetresOfSilo = FALSE;
	}

	if (sound4 != NULL && IsAudioMessageDone(sound4))
	{
		sound4 = NULL;

		// spawn a nav
		nav1 = BuildObject("apcamr", 1, "nav_1");
		SetName(nav1, "Last GPS Fix");
		SetUserTarget(nav1);
		
		ClearObjectives();
		AddObjective("ch05001.otf", GREEN);
		AddObjective("ch05002.otf", WHITE);
		objective1Complete = TRUE;
	}

	if (GetDistance(user, "trigger_1") < 400.0 &&
		!tugSpawned)
	{
		tugSpawned = TRUE;

		neutralScout = BuildObject("cvfigh", 0, "haul_scout");
		RemovePilot(neutralScout);
		tug = BuildObject("svhaul", 2, "enemy_haul");
		//RemovePilot(smokingUnit);

		// tug defenders
		tugDefender1 = BuildObject("svfigh", 2, "haul_defend");
		Defend2(tugDefender1, tug);
		GameObject *obj = GameObjectHandle::GetObj(tugDefender1);
		obj->curPilot = 0;
		tugDefender2 = BuildObject("svfigh", 2, "haul_defend");
		Defend2(tugDefender2, tug);
		obj = GameObjectHandle::GetObj(tugDefender2);
		obj->curPilot = 0;

		pickupTime = GetTime() + 0.5f;
	}

	if (pickupTime < GetTime())
	{
		// time delay so that the scout can form
		pickupTime = 999999.9f;
		Pickup(tug, neutralScout, 1);

		// start the haul cam
		doHaulCam = TRUE;
		haulCamTime = GetTime() + 15.0f;
		CameraReady();
	}

	if (doHaulCam)
	{
		CameraPath("haul_cam", 800, 0, tug);
		if (CameraCancelled() || haulCamTime < GetTime())
		{
			doHaulCam = FALSE;
			CameraFinish();
			AudioMessage("ch05005.wav");

			ClearObjectives();
			AddObjective("ch05003.otf", WHITE);
			SetObjectiveOn(tug);

			// remove all the scrap from the map
			ObjectList &list = *GameObject::objectList;
			for (ObjectList::iterator i = list.begin(); i != list.end(); i++) 
			{
				GameObject *o = *i;
				if (o->GetClass()->sig == CLASS_SCRAP)
				{
					o->Remove();
				}
			}
		}
	}

	if (tugSpawned && GetTug(neutralScout) == tug &&
		!tugGotScout)
	{
		tugGotScout = TRUE;

		Goto(tug, "haul_path", 1);
		mustBeCloseToTug = TRUE;
	}

	// too close to the tug stuff?
	if (tugSpawned && 
		GetDistance(user, tug) < 175.0f &&
		!lost && !won)
	{
		lost = TRUE;
		FailMission(GetTime() + 1.0, "ch05lseb.des");
	}

	if (mustBeCloseToTug &&
		GetDistance(user, tug) > 500.0f &&
		!lost && !won)
	{
		lost = TRUE;
		FailMission(GetTime() + 1.0, "ch05lsed.des");
	}

	if (tugSpawned && GetDistance(tug, "trigger_2") < 200 &&
		!trigger2)
	{
		mustBeCloseToTug = FALSE;
		trigger2 = TRUE;
		betty6Time = GetTime() + 5.0f;
	}

	// play a series of sounds
	if (betty6Time < GetTime())
	{
		betty6Time = 999999.9f;

		betty6 = AudioMessage("abetty6.wav");
	}

	if (betty6 != NULL && IsAudioMessageDone(betty6))
	{
		betty6 = NULL;
		betty14Time = GetTime() + 5.0f;
	}

	if (betty14Time < GetTime())
	{
		betty14Time = 999999.9f;

		betty14 = AudioMessage("abetty14.wav");
	}

	if (betty14 != NULL && IsAudioMessageDone(betty14))
	{
		betty14 = NULL;
		sound6Time = GetTime() + 2.0f;
	}

	if (sound6Time < GetTime())
	{
		sound6Time = 999999.9f;

		sound6 = AudioMessage("ch05006.wav");

		ClearObjectives();
		AddObjective("ch05003.otf", GREEN);
		AddObjective("ch05004.otf", WHITE);
		stayTeam2 = FALSE;
		team1Time = GetTime() + 10.0f;
		annoy2Time = GetTime() + 4 * 60.0f;
		
		SetObjectiveOff(tug);
		navBase = BuildObject("apcamr", 1, "base_1");
		SetName(navBase, "Base");
		SetObjectiveOn(navBase);

		//recycler = BuildObject("cvrecy", 1, "convoy");
		Goto(recycler, "convoy_path");
		scout1 = BuildObject("cvfigh", 1, "convoy");
		scout2 = BuildObject("cvfigh", 1, "convoy");
		factory = BuildObject("cvmuf", 1, "convoy");
		Goto(factory, "convoy_path");
		Follow(scout1, factory);
		Follow(scout2, factory);
		constructor = BuildObject("cvcnst", 1, "convoy");
		Goto(constructor, "convoy_path");

		SetScrap(1, 50);

		// ok, we want to go thru and remove all nsp*
		ObjectList &list = *GameObject::objectList;
		for (ObjectList::iterator i = list.begin(); i != list.end(); i++) 
		{
			GameObject *o = *i;
			char buf[16] = "";
			strcpy(buf, (char*)&o->GetClass()->sig);
			if (strnicmp(buf, "nsp", 2) == 0)
			{
				o->Remove();
			}

		}
	}

	if (annoy2Time < GetTime())
	{
		annoy2Time = GetTime() + 4 * 60.0f;

		for (i = 0; i < 8; i++)
		{
			Handle h = BuildObject("sssold", 2, "aerial_1", 400);
			Attack(h, getBase());
		}
	}

	if (team1Time < GetTime())
	{
		team1Time = 999999.9f;
		SetPerceivedTeam(user, 1);
	}

	if (navBase != NULL && GetDistance(navBase, user) < 100.0f)
	{
		SetObjectiveOff(navBase);
		navBase = NULL;
	}

	if (sound6 != NULL && IsAudioMessageDone(sound6))
	{
		sound6 = NULL;

		removeHaulTime = GetTime() + 4 *60.0f;
	}

	if (removeHaulTime < GetTime())
	{
		removeHaulTime = 999999.9f;

		RemoveObject(neutralScout);
		RemoveObject(tug);
		RemoveObject(tugDefender1);
		RemoveObject(tugDefender2);

		wave1Time = GetTime();
		wave2Time = GetTime() + 5 * 60.0f;
		wave3Time = GetTime() + 9 * 60.0f;
		wave4Time = GetTime() + 15 * 60.0f;
		wave5Time = GetTime() + 17 * 60.0f;
		wave6Time = GetTime() + 20 * 60.0f;
		wave7Time = GetTime() + 22 * 60.0f;

		day1Time = GetTime() + 2 * 60.0f;
		day2Time = GetTime() + 8 * 60.0f;
		day3Time = GetTime() + 12 * 60.0f;
		day4Time = GetTime() + 16 * 60.0f;
		day5Time = GetTime() + 17 * 60.0f;
		day6Time = GetTime() + 20 * 60.0f;

		annoy1Time = GetTime() + 240.0f;
	}

	// wave 1
	if (wave1Time < GetTime())
	{
		wave1Time = 999999.9f;

		Handle h;
		h = BuildObject("svwalk", 2, "wave_1");
		Goto(h, "wave_1_path");
		h = BuildObject("svwalk", 2, "wave_1");
		Goto(h, "wave_1_path");
		h = BuildObject("svhraz", 2, "wave_1");
		Goto(h, "wave_1_path");
		h = BuildObject("svhraz", 2, "wave_1");
		Goto(h, "wave_1_path");
		h = BuildObject("svtank", 2, "wave_1");
		Goto(h, "wave_1_path");
		h = BuildObject("svtank", 2, "wave_1");
		Goto(h, "wave_1_path");
		h = BuildObject("svtank", 2, "wave_1");
		Goto(h, "wave_1_path");
	}

	// wave 2
	if (wave2Time < GetTime())
	{
		wave2Time = 999999.9f;

		Handle h;
		h = BuildObject("svhraz", 2, "wave_2");
		Goto(h, "wave_2_path");
		h = BuildObject("svhraz", 2, "wave_2");
		Goto(h, "wave_2_path");
		h = BuildObject("svhraz", 2, "wave_2");
		Goto(h, "wave_2_path");
		h = BuildObject("svhraz", 2, "wave_2");
		Goto(h, "wave_2_path");
		h = BuildObject("svfigh", 2, "wave_2");
		Goto(h, "wave_2_path");
		h = BuildObject("svfigh", 2, "wave_2");
		Goto(h, "wave_2_path");
		h = BuildObject("svfigh", 2, "wave_2");
		Goto(h, "wave_2_path");
		h = BuildObject("svrckt", 2, "wave_2");
		Goto(h, "wave_2_path");
		h = BuildObject("svrckt", 2, "wave_2");
		Goto(h, "wave_2_path");
	}

	// wave 3
	if (wave3Time < GetTime())
	{
		wave3Time = 999999.9f;

		Handle h;
		h = BuildObject("sssold", 2, "wave_3");
		Attack(h, getBase());
		h = BuildObject("sssold", 2, "wave_3");
		Attack(h, getBase());
		h = BuildObject("sssold", 2, "wave_3");
		Attack(h, getBase());
		h = BuildObject("sssold", 2, "wave_3");
		Attack(h, getBase());
		h = BuildObject("sssold", 2, "wave_3");
		Attack(h, getBase());
		h = BuildObject("ssuser", 2, "wave_3");
		Attack(h, user);
		h = BuildObject("ssuser", 2, "wave_3");
		Attack(h, user);
	}

	// wave 4
	if (wave4Time < GetTime())
	{
		wave4Time = 999999.9f;

		Handle h;
		h = BuildObject("svtank", 2, "wave_4");
		Goto(h, "wave_4_path");
		h = BuildObject("svtank", 2, "wave_4");
		Goto(h, "wave_4_path");
		h = BuildObject("svtank", 2, "wave_4");
		Goto(h, "wave_4_path");
		h = BuildObject("svtank", 2, "wave_4");
		Goto(h, "wave_4_path");
		h = BuildObject("svtank", 2, "wave_4");
		Goto(h, "wave_4_path");
		h = BuildObject("svtank", 2, "wave_4");
		Goto(h, "wave_4_path");
		h = BuildObject("svtank", 2, "wave_4");
		Goto(h, "wave_4_path");
		h = BuildObject("svltnk", 2, "wave_4");
		Goto(h, "wave_4_path");
		h = BuildObject("svltnk", 2, "wave_4");
		Goto(h, "wave_4_path");
		h = BuildObject("svltnk", 2, "wave_4");
		Goto(h, "wave_4_path");
	}

	// wave 5
	if (wave5Time < GetTime())
	{
		wave5Time = 999999.9f;

		Handle h;
		h = BuildObject("svwalk", 2, "wave_5");
		Goto(h, "wave_5_path");
		h = BuildObject("svwalk", 2, "wave_5");
		Goto(h, "wave_5_path");
		h = BuildObject("svwalk", 2, "wave_5");
		Goto(h, "wave_5_path");
		h = BuildObject("svwalk", 2, "wave_5");
		Goto(h, "wave_5_path");
		h = BuildObject("svfigh", 2, "wave_5");
		Goto(h, "wave_5_path");
		h = BuildObject("svfigh", 2, "wave_5");
		Goto(h, "wave_5_path");
		h = BuildObject("svfigh", 2, "wave_5");
		Goto(h, "wave_5_path");
		h = BuildObject("svfigh", 2, "wave_5");
		Goto(h, "wave_5_path");
		h = BuildObject("svrckt", 2, "wave_5");
		Goto(h, "wave_5_path");
		h = BuildObject("svrckt", 2, "wave_5");
		Goto(h, "wave_5_path");
		h = BuildObject("svtank", 2, "wave_5");
		Goto(h, "wave_5_path");
		h = BuildObject("svtank", 2, "wave_5");
		Goto(h, "wave_5_path");
		h = BuildObject("svtank", 2, "wave_5");
		Goto(h, "wave_5_path");
	}

	// wave 6
	if (wave6Time < GetTime())
	{
		wave6Time = 999999.9f;

		Handle h;
		h = BuildObject("svltnk", 2, "wave_6");
		Goto(h, "wave_6_path");
		h = BuildObject("svltnk", 2, "wave_6");
		Goto(h, "wave_6_path");
		h = BuildObject("svltnk", 2, "wave_6");
		Goto(h, "wave_6_path");
		h = BuildObject("svltnk", 2, "wave_6");
		Goto(h, "wave_6_path");
		h = BuildObject("svltnk", 2, "wave_6");
		Goto(h, "wave_6_path");
		h = BuildObject("svltnk", 2, "wave_6");
		Goto(h, "wave_6_path");
		h = BuildObject("svltnk", 2, "wave_6");
		Goto(h, "wave_6_path");
		h = BuildObject("svltnk", 2, "wave_6");
		Goto(h, "wave_6_path");
	}

	// wave 7
	if (wave7Time < GetTime())
	{
		wave7Time = 999999.9f;

		mustKill[numMustKill] = BuildObject("svwalk", 2, "wave_7");
		Goto(mustKill[numMustKill++], "wave_7_path");
		mustKill[numMustKill] = BuildObject("svwalk", 2, "wave_7");
		Goto(mustKill[numMustKill++], "wave_7_path");
		mustKill[numMustKill] = BuildObject("svwalk", 2, "wave_7");
		Goto(mustKill[numMustKill++], "wave_7_path");
		mustKill[numMustKill] = BuildObject("svwalk", 2, "wave_7");
		Goto(mustKill[numMustKill++], "wave_7_path");
		mustKill[numMustKill] = BuildObject("svhraz", 2, "wave_7");
		Goto(mustKill[numMustKill++], "wave_7_path");
		mustKill[numMustKill] = BuildObject("svhraz", 2, "wave_7");
		Goto(mustKill[numMustKill++], "wave_7_path");
		mustKill[numMustKill] = BuildObject("svhraz", 2, "wave_7");
		Goto(mustKill[numMustKill++], "wave_7_path");
		mustKill[numMustKill] = BuildObject("svhraz", 2, "wave_7");
		Goto(mustKill[numMustKill++], "wave_7_path");
		mustKill[numMustKill] = BuildObject("svtank", 2, "wave_7");
		Goto(mustKill[numMustKill++], "wave_7_path");
		mustKill[numMustKill] = BuildObject("svtank", 2, "wave_7");
		Goto(mustKill[numMustKill++], "wave_7_path");
		mustKill[numMustKill] = BuildObject("svtank", 2, "wave_7");
		Goto(mustKill[numMustKill++], "wave_7_path");
		mustKill[numMustKill] = BuildObject("svtank", 2, "wave_7");
		Goto(mustKill[numMustKill++], "wave_7_path");
		mustKill[numMustKill] = BuildObject("svapc", 2, "wave_7");
		Goto(mustKill[numMustKill++], "wave_7_path");
		_ASSERTE(numMustKill <= MAX_MUST_KILL);

		wave7Spawned = TRUE;
	}

	// daywrecker 1
	if (day1Time < GetTime())
	{
		day1Time = 999999.9f;
		BuildObject("apwrck", 0, "day_1");
	}
	
	// daywrecker 2
	if (day2Time < GetTime())
	{
		day2Time = 999999.9f;
		BuildObject("apwrck", 0, "day_2");
	}

	// daywrecker 3
	if (day3Time < GetTime())
	{
		day3Time = 999999.9f;
		BuildObject("apwrck", 0, "day_3");
	}

	// daywrecker 4
	if (day4Time < GetTime())
	{
		day4Time = 999999.9f;
		BuildObject("apwrck", 0, "day_4");
	}

	// daywrecker 5
	if (day5Time < GetTime())
	{
		day5Time = 999999.9f;
		BuildObject("apwrck", 0, "day_5");

		// spawn the artilary
		AudioMessage("ch05007.wav");
		artl1 = BuildObject("svartl", 2, "artl_1");
		artl2 = BuildObject("svartl", 2, "artl_2");
		Handle h;
		h = BuildObject("svfigh", 2, "artl_defend");
		Defend2(h, artl1);
		h = BuildObject("svfigh", 2, "artl_defend");
		Defend2(h, artl1);
		h = BuildObject("svfigh", 2, "artl_defend");
		Defend2(h, artl2);
		h = BuildObject("svfigh", 2, "artl_defend");
		Defend2(h, artl2);

		day7Time = GetTime() + 5 * 60.0f;
		day8Time = GetTime() + 5 * 60.0f + 20.0f;
	}

	// daywrecker 6
	if (day6Time < GetTime())
	{
		day6Time = 999999.9f;
		BuildObject("apwrck", 0, "day_6");
	}

	// daywrecker 7
	if (day7Time < GetTime())
	{
		day7Time = 999999.9f;
		BuildObject("apwrck", 0, "day_7");
	}

	// daywrecker 8
	if (day8Time < GetTime())
	{
		day8Time = 999999.9f;
		BuildObject("apwrck", 0, "day_8");
	}

	if (artl1 != NULL && artl2 != NULL && 
		GetHealth(artl1) <= 0.0 && GetHealth(artl2) <= 0.0)
	{
		artl1 = NULL;
		artl2 = NULL;
		day1Time = 999999.9f;
		day2Time = 999999.9f;
		day3Time = 999999.9f;
		day4Time = 999999.9f;
		day5Time = 999999.9f;
		day6Time = 999999.9f;
		day7Time = 999999.9f;
		day8Time = 999999.9f;
	}

	if (annoy1Time < GetTime())
	{
		annoy1Time = GetTime() + 240.0f;

		char *paths[2] = { "annoy_path_1", "annoy_path_2" };
		char *p = paths[rand() % 2];
		Handle h;
		h = BuildObject("svltnk", 2, "annoy_1");
		Goto(h, p);
		h = BuildObject("svltnk", 2, "annoy_1");
		Goto(h, p);
		h = BuildObject("svtank", 2, "annoy_1");
		Goto(h, p);
		h = BuildObject("svtank", 2, "annoy_1");
		Goto(h, p);
		h = BuildObject("svrckt", 2, "annoy_1");
		Goto(h, p);
		h = BuildObject("svfigh", 2, "annoy_1");
		Goto(h, p);
	}

	if (recycler != NULL && factory != NULL &&
		GetHealth(recycler) <= 0.0f && GetHealth(factory) <= 0.0f &&
		!lost && !won)
	{
		lost = TRUE;
		FailMission(GetTime() + 1.0, "ch05lsec.des");
	}

	if (wave7Spawned && !won && !lost)
	{
		won = TRUE;
		for (i = 0; i < numMustKill; i++)
		{
			if (IsAlive(mustKill[i]))
			{
				won = FALSE;
				break;
			}
		}

		if (won)
		{
			SucceedMission(GetTime() + 1.0, "ch05win.des");
		}
	}
}


]====]
