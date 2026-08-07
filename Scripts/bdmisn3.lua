-- bdmisn3.lua (Converted from BlackDog03Mission.cpp)
-- Source terminology note: its recycler followers are called the "excort"
-- (source typo for escort) in the original inline comment.

-- Compatibility
SetLabel = SetLabel or SetLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})
local exu = require("exu")
local aiCore = require("aiCore")

-- Helper for AI
local function SetupAI()
    -- Team 1: Black Dogs (Player)
    -- Team 2: CAA (Enemy)
    local caa = aiCore.AddTeam(2, aiCore.Factions.CCA)

    local diff = (exu and exu.GetDifficulty and exu.GetDifficulty()) or 2
    if diff <= 1 then
        caa:SetConfig("pilotZeal", 0.1)
    elseif diff >= 3 then
        caa:SetConfig("pilotZeal", 0.9)
    else
        caa:SetConfig("pilotZeal", 0.4)
    end
end

-- Variables
local start_done = false
local objective1_complete = false
local objective2_complete = false
local objective3_complete = false
local activate_stuff = false
local apc_spawned = false
local first_random_attack_done = false
local recycler_on_path = false
local recycler_deployed = false
local sound8_played = false
local trigger_ambush = false
local lost = false
local won = false

local sound_complete = {false, false, false, false, false, false, false, false, false, false}
local sound_handle = {}

-- Timers
local sound1_delay = 99999.0
local sound2_delay = 99999.0
local sound3_delay = 99999.0
local sound4_delay = 99999.0
local random_delay = 99999.0
local spawn_recycler_attack_time1 = 99999.0
local spawn_recycler_attack_time2 = 99999.0
local spawn_recycler_attack_time3 = 99999.0
local apc_attack_time = 99999.0

-- Handles
local user, recycler, nav_delta, apc, geyser1
local kill_me_now = {} -- 1, 2
local evil_guys = {} -- 1..4
local enemies = {} -- Random spawns

-- Random Unit Choices
local random_units_choices = {
    "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvfigh",
    "cvltnk", "cvltnk", "cvtnk", "cvtnk", "cvrckt"
}

-- Difficulty
local difficulty = 2

-- Preserve native mission state across save/load.
function Save()
    return {
        start_done = start_done,
        objective1_complete = objective1_complete,
        objective2_complete = objective2_complete,
        objective3_complete = objective3_complete,
        activate_stuff = activate_stuff,
        apc_spawned = apc_spawned,
        first_random_attack_done = first_random_attack_done,
        recycler_on_path = recycler_on_path,
        recycler_deployed = recycler_deployed,
        sound8_played = sound8_played,
        trigger_ambush = trigger_ambush,
        lost = lost,
        won = won,
        sound_complete = sound_complete,
        sound_handle = sound_handle,
        sound1_delay = sound1_delay,
        sound2_delay = sound2_delay,
        sound3_delay = sound3_delay,
        sound4_delay = sound4_delay,
        random_delay = random_delay,
        spawn_recycler_attack_time1 = spawn_recycler_attack_time1,
        spawn_recycler_attack_time2 = spawn_recycler_attack_time2,
        spawn_recycler_attack_time3 = spawn_recycler_attack_time3,
        apc_attack_time = apc_attack_time,
        user = user,
        recycler = recycler,
        nav_delta = nav_delta,
        apc = apc,
        geyser1 = geyser1,
        kill_me_now = kill_me_now,
        evil_guys = evil_guys,
        enemies = enemies,
        random_units_choices = random_units_choices,
        difficulty = difficulty,
    }
end

function Load(state)
    if not state then return end
    start_done = state.start_done
    objective1_complete = state.objective1_complete
    objective2_complete = state.objective2_complete
    objective3_complete = state.objective3_complete
    activate_stuff = state.activate_stuff
    apc_spawned = state.apc_spawned
    first_random_attack_done = state.first_random_attack_done
    recycler_on_path = state.recycler_on_path
    recycler_deployed = state.recycler_deployed
    sound8_played = state.sound8_played
    trigger_ambush = state.trigger_ambush
    lost = state.lost
    won = state.won
    sound_complete = state.sound_complete
    sound_handle = state.sound_handle
    sound1_delay = state.sound1_delay
    sound2_delay = state.sound2_delay
    sound3_delay = state.sound3_delay
    sound4_delay = state.sound4_delay
    random_delay = state.random_delay
    spawn_recycler_attack_time1 = state.spawn_recycler_attack_time1
    spawn_recycler_attack_time2 = state.spawn_recycler_attack_time2
    spawn_recycler_attack_time3 = state.spawn_recycler_attack_time3
    apc_attack_time = state.apc_attack_time
    user = state.user
    recycler = state.recycler
    nav_delta = state.nav_delta
    apc = state.apc
    geyser1 = state.geyser1
    kill_me_now = state.kill_me_now
    evil_guys = state.evil_guys
    enemies = state.enemies
    random_units_choices = state.random_units_choices
    difficulty = state.difficulty
end
function Start()
    if exu then
        difficulty = (exu.GetDifficulty and exu.GetDifficulty()) or 2
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
    end
    SetupAI()
    start_done = false
end

local function ManageAudio(idx, file)
    if not sound_complete[idx] then
        if not sound_handle[idx] then
            sound_handle[idx] = AudioMessage(file)
        end

        if sound_handle[idx] and IsAudioMessageDone(sound_handle[idx]) then
            sound_handle[idx] = nil
            sound_complete[idx] = true
            return true
        end
    end
    return false
end

local function IsAtPathEnd(handle, path, radius)
    local count = GetPathPointCount(path) or 0
    if count < 1 then return false end
    return GetDistance(handle, GetPosition(path, count - 1)) < (radius or 50.0)
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then
        aiCore.AddObject(h)
    end
end

function DeleteObject(h)
end

function Update()
    user = GetPlayerHandle()
    aiCore.Update()

    if not start_done then
        SetScrap(1, 8)
        SetPilot(1, 10)

        recycler = GetHandle("recycler")
        nav_delta = GetHandle("nav_delta")
        if nav_delta then SetLabel(nav_delta, "Nav Delta") end

        kill_me_now[1] = GetHandle("bobcat_kill_me_now")
        kill_me_now[2] = GetHandle("scout_kill_me_now")
        geyser1 = GetHandle("geyser1")

        evil_guys[1] = GetHandle("evil_scout1")
        evil_guys[2] = GetHandle("evil_scout2")
        evil_guys[3] = GetHandle("evil_scout3")
        evil_guys[4] = GetHandle("evil_tank1")

        ClearObjectives()
        AddObjective("bd03001.otf", "white")

        spawn_recycler_attack_time2 = GetTime() + 7 * 60.0
        spawn_recycler_attack_time3 = GetTime() + 11 * 60.0
        apc_attack_time = GetTime() + 9 * 60.0
        sound4_delay = GetTime() + 7 * 60.0
        random_delay = GetTime() + 10 * 60.0

        -- Cloak initial enemies
        for i=1,4 do if evil_guys[i] then SetCloaked(evil_guys[i], true) end end
        local es4 = GetHandle("evil_scout4"); if es4 then SetCloaked(es4, true) end
        local es5 = GetHandle("evil_scout5"); if es5 then SetCloaked(es5, true) end

        start_done = true
    end

    -- Intro Audio/Cam
    if not sound_complete[1] then -- Index 1 for bd03001
        if not sound_handle[1] then
            CameraReady()
        end

        CameraPath("camera_intro", 1000, 0, user)

        if CameraCancelled() then
            if sound_handle[1] then StopAudioMessage(sound_handle[1]) end
        end

        if ManageAudio(1, "bd03001.wav") then
            CameraFinish()
        end
    end

    -- Recycler Move
    if sound_complete[1] and not sound_complete[2] then
        if not sound_handle[2] then
            CameraReady()
            Goto(recycler, "path_recycler_travel", 1)
            recycler_on_path = true
            if IsAlive(kill_me_now[1]) then Follow(kill_me_now[1], recycler, 1) end
            if IsAlive(kill_me_now[2]) then Follow(kill_me_now[2], recycler, 1) end
        end

        CameraPath("camera_recycler", 400, 200, recycler)

        if CameraCancelled() then
            if sound_handle[2] then StopAudioMessage(sound_handle[2]) end
        end

        if ManageAudio(2, "bd03002.wav") then
            CameraFinish()
            RemoveObject(kill_me_now[1]) -- Remove escort
            RemoveObject(kill_me_now[2])
            sound1_delay = GetTime() + 60.0
        end
    end

    -- Recycler Path Logic
    if recycler_on_path and IsAtPathEnd(recycler, "path_recycler_travel", 50.0) then
        recycler_on_path = false
        Goto(recycler, geyser1, 1)

        -- Geyser Ambush Spawn
        local t1 = BuildObject("cvturr", 2, "spawn_turret_1")
        local t2 = BuildObject("cvturr", 2, "spawn_turret_2")
        local h = BuildObject("cvfigh", 2, "spawn_turret_guard1"); SetCloaked(h, true); Defend2(h, t1)
        h = BuildObject("cvfigh", 2, "spawn_turret_guard1"); SetCloaked(h, true); Defend2(h, t2)
        h = BuildObject("cvfigh", 2, "spawn_turret_guard2"); SetCloaked(h, true); Defend2(h, t1)
        h = BuildObject("cvfigh", 2, "spawn_turret_guard2"); SetCloaked(h, true); Defend2(h, t2)
    end

    -- Deploy
    if not recycler_deployed and IsDeployed(recycler) then
        recycler_deployed = true

        -- Restored Cut Content: Friendly Spawns (C++ lines 440-441 commented out)
        BuildObject("bvscav", 1, "spawn_scav")
        BuildObject("bvturr", 1, "spawn_turret")

        spawn_recycler_attack_time1 = GetTime() + 30.0
    end

    -- Attacks
    if GetTime() > spawn_recycler_attack_time1 then
        spawn_recycler_attack_time1 = 99999.0
        local h = BuildObject("cvfigh", 2, "spawn_recycler_attack"); Attack(h, recycler, 1)
        h = BuildObject("cvfigh", 2, "spawn_recycler_attack"); Attack(h, recycler, 1)
    end

    if GetTime() > spawn_recycler_attack_time2 then
        spawn_recycler_attack_time2 = 99999.0
        -- Cloaked wave 2
        local function SpawnAttack(odf)
            local h = BuildObject(odf, 2, "spawn_recycler_attack")
            SetCloaked(h, true)
            Goto(h, "path_recycler_attack")
        end
        SpawnAttack("cvfigh"); SpawnAttack("cvfigh"); SpawnAttack("cvfigh")
        SpawnAttack("cvtnk"); SpawnAttack("cvtnk")
    end

    if GetTime() > spawn_recycler_attack_time3 then
        spawn_recycler_attack_time3 = 99999.0
        local h = BuildObject("cvfigh", 2, "spawn_recycler_attack"); Goto(h, "path_recycler_attack", 1)
        h = BuildObject("cvfigh", 2, "spawn_recycler_attack"); Goto(h, "path_recycler_attack", 1)
    end

    -- Activate Hunt (Restored Cut Content)
    if sound_complete[2] and not activate_stuff then
        activate_stuff = true
        -- Restored #if 0 block (C++ Lines 490-494)
        for i=1,4 do
            if IsAlive(evil_guys[i]) then Attack(evil_guys[i], user) end
        end
    end

    -- Audio Sequence
    if GetTime() > sound1_delay and not sound_complete[3] then
        if ManageAudio(3, "bd03003.wav") then
            sound1_delay = 99999.0
            sound2_delay = GetTime() + 30.0
        end
    end

    if GetTime() > sound2_delay and not sound_complete[4] then
        if ManageAudio(4, "bd03004.wav") then
            sound2_delay = 99999.0
            sound3_delay = GetTime() + 10.0
            ClearObjectives()
            AddObjective("bd03001.otf", "white")
            AddObjective("bd03002.otf", "white")
        end
    end

    if GetTime() > sound3_delay and not sound_complete[5] then
        if ManageAudio(5, "bd03005.wav") then
            sound3_delay = 99999.0
        end
    end

    -- Arrive at Recycler Check
    if IsAlive(recycler) and GetDistance(user, recycler) < 75.0 and not (objective1_complete and objective2_complete) then
        objective1_complete = true; objective2_complete = true
        AudioMessage("bd03006.wav")
        ClearObjectives()
        AddObjective("bd03001.otf", "green")
        AddObjective("bd03002.otf", "green")
    end

    -- APC Spawn
    if GetTime() > sound4_delay and not sound_complete[6] then
        if not sound_handle[6] then
            ClearObjectives()
            AddObjective("bd03003.otf", "white")
        end

        if ManageAudio(6, "bd03007.wav") then
            sound4_delay = 99999.0

            -- Spawn APC
            apc = BuildObject("bvapcb", 1, "spawn_apc")
            Goto(apc, "path_apc_travel", 1)
            SetObjectiveOn(apc)
            local h = BuildObject("bvraz", 1, "spawn_apc"); Defend2(h, apc)
            h = BuildObject("bvraz", 1, "spawn_apc"); Defend2(h, apc)
            apc_spawned = true
        end
    end

    -- APC Attack
    if GetTime() > apc_attack_time then
        apc_attack_time = 99999.0
        local h = BuildObject("cvfighf", 2, "spawn_attack_apc") -- cvfighf = fighter?
        Attack(h, apc)
    end

    -- Random Attacks
    if GetTime() > random_delay then
        random_delay = GetTime() + 90.0
        local choices = random_units_choices
        local function RandUnit(pt, order)
            local u = choices[math.random(1, 10)]
            local h = BuildObject(u, 2, pt)
            if order == "attack" then Attack(h, apc) else Hunt(h, 1) end
        end
        RandUnit("spawn_random_1", "attack")
        RandUnit("spawn_random_2", "hunt")
        RandUnit("spawn_random_3", "attack")
        RandUnit("spawn_random_4", "hunt")
    end

    -- APC Damage Audio
    if apc_spawned and IsAlive(apc) and GetHealth(apc) < 0.98 and not sound8_played then
        AudioMessage("bd03008.wav")
        sound8_played = true
    end

    -- Win
    if apc_spawned and IsAlive(apc) and GetDistance(apc, nav_delta) < 75.0 and not won and not lost then
        won = true
        sound_handle[8] = AudioMessage("bd03009.wav")
    end

    if won and sound_handle[8] and IsAudioMessageDone(sound_handle[8]) then
        sound_handle[8] = nil
        sound_complete[8] = true
        SucceedMission(GetTime() + 2.0, "bd03win.des")
    end

    -- Ambush Trigger
    if apc_spawned and IsAlive(apc) and GetDistance(apc, "trigger_ambush") < 50.0 and not trigger_ambush then
        trigger_ambush = true
        local variants = {"cvfigh", "cvltnk", "cvtnk"}
        local function AmbushUnit()
            local h = BuildObject(variants[math.random(1,3)], 2, "spawn_recycler_attack")
            SetCloaked(h, true)
            Follow(h, apc, 0)
        end
        AmbushUnit(); AmbushUnit()
    end

    -- Recycler Lost
    if GetHealth(recycler) <= 0.0 and not lost and not won then
        lost = true
        sound_handle[7] = AudioMessage("bd03012.wav")
    end
    if sound_handle[7] and IsAudioMessageDone(sound_handle[7]) then
        sound_handle[7] = nil
        sound_complete[7] = true
        FailMission(GetTime() + 2.0, "bd03lsea.des")
    end

    -- APC Lost
    if apc_spawned and GetHealth(apc) <= 0.0 and not lost and not won then
        lost = true
        sound_handle[9] = AudioMessage("bd03010.wav")
    end
    if sound_handle[9] and IsAudioMessageDone(sound_handle[9]) then
        sound_handle[9] = nil
        sound_complete[9] = true
        sound_handle[10] = AudioMessage("bd03011.wav")
    end
    if sound_handle[10] and IsAudioMessageDone(sound_handle[10]) then
        sound_handle[10] = nil
        sound_complete[10] = true
        FailMission(GetTime() + 2.0, "bd03lseb.des")
    end
end

