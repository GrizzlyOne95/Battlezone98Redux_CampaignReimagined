-- cmisn05.lua (Converted from Chinese05Mission.cpp)
-- Source-disabled notes: leadScout had three alternate Goto("scout_path")
-- points, and the convoy could build a replacement cvrecy instead of moving
-- the existing recycler. Active source moves the existing unit.
-- Exact disabled variants: recycler = BuildObject("cvrecy", 1, "convoy"); and
-- the TEST_INFILTRATE setup built "cvtank" at the player after changing the
-- perceived team. The latter is test scaffolding, not campaign restoration.

-- Compatibility
SetLabel = SetLabel or SetLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})
local exu = require("exu")
local aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")

-- Helper for AI
local function SetupAI()
    DiffUtils.SetupTeams(aiCore.Factions.CRA, aiCore.Factions.CCA, 2)
end

-- Variables
local start_done = false
local objective1_complete = false
local objective2_complete = false
local objective3_complete = false
local must_stay_near_silo = false
local scout_close_to_silo = false
local scouts_spawned = false
local trigger1 = false
local trigger2 = false
local tug_spawned = false
local tug_got_scout = false
local must_be_close_to_tug = false
local do_haul_cam = false
local wave7_spawned = false
local stay_team2 = false
local won = false
local lost = false

-- Timers
local opening_sound_time = 99999.0
local sound3_time = 99999.0
local sound4_time = 99999.0
local sound6_time = 99999.0
local betty6_time = 99999.0
local betty14_time = 99999.0
local remove_haul_time = 99999.0
local wave_times = {99999.0, 99999.0, 99999.0, 99999.0, 99999.0, 99999.0, 99999.0}
local day_times = {99999.0, 99999.0, 99999.0, 99999.0, 99999.0, 99999.0, 99999.0, 99999.0}
local annoy1_time = 99999.0
local annoy2_time = 99999.0
local pickup_time = 99999.0
local haul_cam_time = 99999.0
local team1_time = 99999.0

-- Handles
local user
local silo
local lead_scout, follow_scout1, follow_scout2, follow_scout3
local neutral_scout, tug, tug_defender1, tug_defender2
local recycler, factory, scout1, scout2, constructor
local artl1, artl2
local must_kill = {} -- 13 max
local num_must_kill = 0
local nav1, nav_base
local opening_sound, sound3, sound4, sound6, betty6, betty14, lose1_sound

-- Difficulty
local difficulty = 2

-- Preserve native mission state across save/load.
function Save()
    return {
        start_done = start_done,
        objective1_complete = objective1_complete,
        objective2_complete = objective2_complete,
        objective3_complete = objective3_complete,
        must_stay_near_silo = must_stay_near_silo,
        scout_close_to_silo = scout_close_to_silo,
        scouts_spawned = scouts_spawned,
        trigger1 = trigger1,
        trigger2 = trigger2,
        tug_spawned = tug_spawned,
        tug_got_scout = tug_got_scout,
        must_be_close_to_tug = must_be_close_to_tug,
        do_haul_cam = do_haul_cam,
        wave7_spawned = wave7_spawned,
        stay_team2 = stay_team2,
        won = won,
        lost = lost,
        opening_sound_time = opening_sound_time,
        sound3_time = sound3_time,
        sound4_time = sound4_time,
        sound6_time = sound6_time,
        betty6_time = betty6_time,
        betty14_time = betty14_time,
        remove_haul_time = remove_haul_time,
        wave_times = wave_times,
        day_times = day_times,
        annoy1_time = annoy1_time,
        annoy2_time = annoy2_time,
        pickup_time = pickup_time,
        haul_cam_time = haul_cam_time,
        team1_time = team1_time,
        user = user,
        silo = silo,
        lead_scout = lead_scout,
        follow_scout1 = follow_scout1,
        follow_scout2 = follow_scout2,
        follow_scout3 = follow_scout3,
        neutral_scout = neutral_scout,
        tug = tug,
        tug_defender1 = tug_defender1,
        tug_defender2 = tug_defender2,
        recycler = recycler,
        factory = factory,
        scout1 = scout1,
        scout2 = scout2,
        constructor = constructor,
        artl1 = artl1,
        artl2 = artl2,
        must_kill = must_kill,
        num_must_kill = num_must_kill,
        nav1 = nav1,
        nav_base = nav_base,
        opening_sound = opening_sound,
        sound3 = sound3,
        sound4 = sound4,
        sound6 = sound6,
        betty6 = betty6,
        betty14 = betty14,
        lose1_sound = lose1_sound,
        difficulty = difficulty,
    }
end

function Load(state)
    if not state then return end
    start_done = state.start_done
    objective1_complete = state.objective1_complete
    objective2_complete = state.objective2_complete
    objective3_complete = state.objective3_complete
    must_stay_near_silo = state.must_stay_near_silo
    scout_close_to_silo = state.scout_close_to_silo
    scouts_spawned = state.scouts_spawned
    trigger1 = state.trigger1
    trigger2 = state.trigger2
    tug_spawned = state.tug_spawned
    tug_got_scout = state.tug_got_scout
    must_be_close_to_tug = state.must_be_close_to_tug
    do_haul_cam = state.do_haul_cam
    wave7_spawned = state.wave7_spawned
    stay_team2 = state.stay_team2
    won = state.won
    lost = state.lost
    opening_sound_time = state.opening_sound_time
    sound3_time = state.sound3_time
    sound4_time = state.sound4_time
    sound6_time = state.sound6_time
    betty6_time = state.betty6_time
    betty14_time = state.betty14_time
    remove_haul_time = state.remove_haul_time
    wave_times = state.wave_times
    day_times = state.day_times
    annoy1_time = state.annoy1_time
    annoy2_time = state.annoy2_time
    pickup_time = state.pickup_time
    haul_cam_time = state.haul_cam_time
    team1_time = state.team1_time
    user = state.user
    silo = state.silo
    lead_scout = state.lead_scout
    follow_scout1 = state.follow_scout1
    follow_scout2 = state.follow_scout2
    follow_scout3 = state.follow_scout3
    neutral_scout = state.neutral_scout
    tug = state.tug
    tug_defender1 = state.tug_defender1
    tug_defender2 = state.tug_defender2
    recycler = state.recycler
    factory = state.factory
    scout1 = state.scout1
    scout2 = state.scout2
    constructor = state.constructor
    artl1 = state.artl1
    artl2 = state.artl2
    must_kill = state.must_kill
    num_must_kill = state.num_must_kill
    nav1 = state.nav1
    nav_base = state.nav_base
    opening_sound = state.opening_sound
    sound3 = state.sound3
    sound4 = state.sound4
    sound6 = state.sound6
    betty6 = state.betty6
    betty14 = state.betty14
    lose1_sound = state.lose1_sound
    difficulty = state.difficulty
end
function Start()
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    start_done = false
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then
        aiCore.AddObject(h)
    end
end

function DeleteObject(h)
end

local function GetBase()
    local targets = {}
    if recycler and IsAlive(recycler) then table.insert(targets, recycler) end
    if factory and IsAlive(factory) then table.insert(targets, factory) end
    if #targets == 0 then return nil end
    return targets[math.random(1, #targets)]
end

function Update()
    user = GetPlayerHandle()
    aiCore.Update()

    if not start_done then
        SetPilot(1, 10)
        SetScrap(1, 0)

        silo = GetHandle("silo")
        recycler = GetHandle("recycler")

        opening_sound_time = GetTime() + 3.0
        must_stay_near_silo = true
        stay_team2 = true
        Stop(recycler, 1)

        ClearObjectives()
        AddObjective("ch05001.otf", "white")

        start_done = true
    end

    if won or lost then return end

    if stay_team2 then
        SetPerceivedTeam(user, 2)
    end

    -- Sound Intro
    if GetTime() > opening_sound_time then
        opening_sound_time = 99999.0
        opening_sound = AudioMessage("ch05001.wav")
    end

    -- Phase 1: Observation
    if must_stay_near_silo and GetDistance(user, silo) > 250.0 and not lost then
        lost = true
        FailMission(GetTime() + 1.0, "ch05lsea.des")
    end

    if not scouts_spawned and GetScrap(1) >= 3 then
        scouts_spawned = true
        lead_scout = BuildObject("cvfighh", 1, "scout_1")
        SetPerceivedTeam(lead_scout, 2)
        Goto(lead_scout, "scout_path", 1)

        for i=1, 3 do
            local h = BuildObject("cvfighh", 1, "scout_2"); SetPerceivedTeam(h, 2); Formation(h, lead_scout, 1)
        end
    end

    if scouts_spawned and not scout_close_to_silo and GetDistance(lead_scout, silo) < 300.0 then
        scout_close_to_silo = true
        AudioMessage("ch05002.wav")
    end

    if scouts_spawned and not trigger1 and GetDistance(lead_scout, "trigger_1") < 30.0 then
        trigger1 = true
        RemoveObject(follow_scout1)
        RemoveObject(follow_scout2)
        RemoveObject(follow_scout3)
        RemoveObject(lead_scout)
        sound3_time = GetTime() + 1.0
    end

    if GetTime() > sound3_time then
        sound3_time = 99999.0
        sound3 = AudioMessage("ch05003.wav")
    end

    if sound3 and IsAudioMessageDone(sound3) then
        sound3 = nil
        sound4_time = GetTime() + 5.0
    end

    if GetTime() > sound4_time then
        sound4_time = 99999.0
        sound4 = AudioMessage("ch05004.wav")
        must_stay_near_silo = false
    end

    if sound4 and IsAudioMessageDone(sound4) then
        sound4 = nil
        nav1 = BuildObject("apcamr", 1, "nav_1")
        SetName(nav1, "Last GPS Fix")
        SetUserTarget(nav1)

        ClearObjectives()
        AddObjective("ch05001.otf", "green")
        AddObjective("ch05002.otf", "white")
        objective1_complete = true
    end

    -- Phase 2: Tug Tail
    if not tug_spawned and GetDistance(user, "trigger_1") < 400.0 then
        tug_spawned = true
        neutral_scout = BuildObject("cvfigh", 0, "haul_scout")
        RemovePilot(neutral_scout)
        tug = BuildObject("svhaul", 2, "enemy_haul")

        tug_defender1 = BuildObject("svfigh", 2, "haul_defend"); Defend2(tug_defender1, tug, 1)
        tug_defender2 = BuildObject("svfigh", 2, "haul_defend"); Defend2(tug_defender2, tug, 1)

        pickup_time = GetTime() + 0.5
    end

    if GetTime() > pickup_time then
        pickup_time = 99999.0
        Pickup(tug, neutral_scout, 1)
        do_haul_cam = true
        haul_cam_time = GetTime() + 15.0
        CameraReady()
    end

    if do_haul_cam then
        CameraPath("haul_cam", 800, 0, tug)
        if CameraCancelled() or GetTime() > haul_cam_time then
            do_haul_cam = false
            CameraFinish()
            AudioMessage("ch05005.wav")
            ClearObjectives()
            AddObjective("ch05003.otf", "white")
            SetObjectiveOn(tug)
            -- Clean scrap
            -- (Note: Standard Lua API doesn't have easy mass scrap removal, we rely on natural cleanup or ignore it)
        end
    end

    if tug_spawned and not tug_got_scout and GetTug(neutral_scout) == tug then
        tug_got_scout = true
        Goto(tug, "haul_path", 1)
        must_be_close_to_tug = true
    end

    if tug_spawned and GetDistance(user, tug) < 175.0 and not lost then
        lost = true
        FailMission(GetTime() + 1.0, "ch05lseb.des")
    end

    if must_be_close_to_tug and GetDistance(user, tug) > 500.0 and not lost then
        lost = true
        FailMission(GetTime() + 1.0, "ch05lsed.des")
    end

    if tug_spawned and not trigger2 and GetDistance(tug, "trigger_2") < 200.0 then
        trigger2 = true
        must_be_close_to_tug = false
        betty6_time = GetTime() + 5.0
    end

    -- Phase 3 Transition Sounds
    if GetTime() > betty6_time then
        betty6_time = 99999.0
        betty6 = AudioMessage("abetty6.wav")
    end
    if betty6 and IsAudioMessageDone(betty6) then
        betty6 = nil
        betty14_time = GetTime() + 5.0
    end
    if GetTime() > betty14_time then
        betty14_time = 99999.0
        betty14 = AudioMessage("abetty14.wav")
    end
    if betty14 and IsAudioMessageDone(betty14) then
        betty14 = nil
        sound6_time = GetTime() + 2.0
    end

    if GetTime() > sound6_time then
        sound6_time = 99999.0
        sound6 = AudioMessage("ch05006.wav")
        ClearObjectives()
        AddObjective("ch05003.otf", "green")
        AddObjective("ch05004.otf", "white")
        stay_team2 = false
        team1_time = GetTime() + 10.0
        annoy2_time = GetTime() + 240.0
        SetObjectiveOff(tug)

        nav_base = BuildObject("apcamr", 1, "base_1")
        SetName(nav_base, "Base")
        SetObjectiveOn(nav_base)

        Goto(recycler, "convoy_path")
        factory = BuildObject("cvmuf", 1, "convoy"); Goto(factory, "convoy_path")
        scout1 = BuildObject("cvfigh", 1, "convoy"); Follow(scout1, factory, 1)
        scout2 = BuildObject("cvfigh", 1, "convoy"); Follow(scout2, factory, 1)
        constructor = BuildObject("cvcnst", 1, "convoy"); Goto(constructor, "convoy_path")
        SetScrap(1, 50)
        -- Preserve the source cleanup pass that removes temporary nsp* objects
        -- when the convoy changes allegiance.
        for h in AllObjects() do
            local odf = GetOdf(h)
            if odf and odf:sub(1, 3):lower() == "nsp" then RemoveObject(h) end
        end
    end

    if GetTime() > annoy2_time then
        annoy2_time = GetTime() + 240.0
        local target = GetBase()
        if target then
            for i=1, 8 do local h = BuildObject("sssold", 2, "aerial_1"); Attack(h, target, 1) end
        end
    end

    if GetTime() > team1_time then
        team1_time = 99999.0
        SetPerceivedTeam(user, 1)
    end

    if nav_base and GetDistance(nav_base, user) < 100.0 then
        SetObjectiveOff(nav_base)
        nav_base = nil
    end

    if sound6 and IsAudioMessageDone(sound6) then
        sound6 = nil
        remove_haul_time = GetTime() + 240.0
    end

    -- Phase 4: Assault Waves
    if GetTime() > remove_haul_time then
        remove_haul_time = 99999.0
        RemoveObject(neutral_scout)
        if IsAlive(tug) then RemoveObject(tug) end

        wave_times[1] = GetTime()
        wave_times[2] = GetTime() + 300
        wave_times[3] = GetTime() + 540
        wave_times[4] = GetTime() + 900
        wave_times[5] = GetTime() + 1020
        wave_times[6] = GetTime() + 1200
        wave_times[7] = GetTime() + 1320

        day_times[1] = GetTime() + 120
        day_times[2] = GetTime() + 480
        day_times[3] = GetTime() + 720
        day_times[4] = GetTime() + 960
        day_times[5] = GetTime() + 1020
        day_times[6] = GetTime() + 1200

        annoy1_time = GetTime() + 240.0
    end

    -- Wave 1
    if GetTime() > wave_times[1] then
        wave_times[1] = 99999.0
        local function Sp(odf, n) for i=1, n do local h = BuildObject(odf, 2, "wave_1"); Goto(h, "wave_1_path") end end
        Sp("svwalk", 2); Sp("svhraz", 2); Sp("svtank", 3)
    end
    -- Wave 2
    if GetTime() > wave_times[2] then
        wave_times[2] = 99999.0
        local function Sp(odf, n) for i=1, n do local h = BuildObject(odf, 2, "wave_2"); Goto(h, "wave_2_path") end end
        Sp("svhraz", 4); Sp("svfigh", 3); Sp("svrckt", 2)
    end
    -- Wave 3
    if GetTime() > wave_times[3] then
        wave_times[3] = 99999.0
        local target = GetBase()
        if target then
            for i=1, 5 do local h = BuildObject("sssold", 2, "wave_3"); Attack(h, target, 1) end
            for i=1, 2 do local h = BuildObject("ssuser", 2, "wave_3"); Attack(h, user, 1) end
        end
    end
    -- Wave 4
    if GetTime() > wave_times[4] then
        wave_times[4] = 99999.0
        local function Sp(odf, n) for i=1, n do local h = BuildObject(odf, 2, "wave_4"); Goto(h, "wave_4_path") end end
        Sp("svtank", 7); Sp("svltnk", 3)
    end
    -- Wave 5
    if GetTime() > wave_times[5] then
        wave_times[5] = 99999.0
        local function Sp(odf, n) for i=1, n do local h = BuildObject(odf, 2, "wave_5"); Goto(h, "wave_5_path") end end
        Sp("svwalk", 4); Sp("svfigh", 4); Sp("svrckt", 2); Sp("svtank", 3)
    end
    -- Wave 6
    if GetTime() > wave_times[6] then
        wave_times[6] = 99999.0
        local function Sp(odf, n) for i=1, n do local h = BuildObject(odf, 2, "wave_6"); Goto(h, "wave_6_path") end end
        Sp("svltnk", 8)
    end
    -- Wave 7 (Must Kill)
    if GetTime() > wave_times[7] then
        wave_times[7] = 99999.0
        local function Sp(odf, n)
            for i=1, n do
                local h = BuildObject(odf, 2, "wave_7"); Goto(h, "wave_7_path")
                table.insert(must_kill, h)
            end
        end
        Sp("svwalk", 4); Sp("svhraz", 4); Sp("svtank", 4); Sp("svapc", 1)
        num_must_kill = #must_kill
        wave7_spawned = true
    end

    -- Day Wreckers (Artillery)
    for i=1,8 do
        if GetTime() > day_times[i] then
            day_times[i] = 99999.0
            BuildObject("apwrck", 0, "day_"..i) -- Powerups/Wreckers spawn
            if i == 5 then
                AudioMessage("ch05007.wav")
                artl1 = BuildObject("svartl", 2, "artl_1")
                artl2 = BuildObject("svartl", 2, "artl_2")
                for j=1,2 do
                    local h = BuildObject("svfigh", 2, "artl_defend")
                    Defend2(h, artl1, 1)
                end
                for j=1,2 do
                    local h = BuildObject("svfigh", 2, "artl_defend")
                    Defend2(h, artl2, 1)
                end
                day_times[7] = GetTime() + 300.0
                day_times[8] = GetTime() + 320.0
            end
        end
    end

    if artl1 and artl2 and GetHealth(artl1) <= 0.0 and GetHealth(artl2) <= 0.0 then
        artl1, artl2 = nil, nil
        for i=1,8 do day_times[i] = 99999.0 end
    end

    -- Annoy 1
    if GetTime() > annoy1_time then
        annoy1_time = GetTime() + 240.0
        local path = (math.random(1,2) == 1) and "annoy_path_1" or "annoy_path_2"
        local function Sp(odf, n) for i=1, n do local h = BuildObject(odf, 2, "annoy_1"); Goto(h, path) end end
        Sp("svltnk", 2); Sp("svtank", 2); Sp("svrckt", 1); Sp("svfigh", 1)
    end

    -- Assets Failure
    if recycler and factory and not IsAlive(recycler) and not IsAlive(factory) and not lost then
        lost = true
        FailMission(GetTime() + 1.0, "ch05lsec.des")
    end

    -- Win Condition
    if wave7_spawned and not won and not lost then
        local all_dead = true
        for i=1,num_must_kill do if IsAlive(must_kill[i]) then all_dead = false; break end end
        if all_dead then
            won = true
            SucceedMission(GetTime() + 1.0, "ch05win.des")
        end
    end
end

