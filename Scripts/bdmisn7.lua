-- bdmisn7.lua (Converted from BlackDog07Mission.cpp)

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
local waves_spawned = false
local lost = false
local won = false

-- Timers
local sound1_time = 99999.0
local sound2_time = 99999.0
local sound3_time = 99999.0
local wave_delay = {99999.0, 99999.0}
local annoy_time = 99999.0

-- Handles
local user
local must_destroy = {} -- 1..11
local must_save = {} -- 1..3
local wave_units1 = {} -- 1..3
local wave_units2 = {} -- 1..8

-- Audio
local sound1, sound2, sound3

-- Difficulty
local difficulty = 2

-- Preserve native mission state across save/load.
function Save()
    return {
        start_done = start_done,
        objective1_complete = objective1_complete,
        objective2_complete = objective2_complete,
        waves_spawned = waves_spawned,
        lost = lost,
        won = won,
        sound1_time = sound1_time,
        sound2_time = sound2_time,
        sound3_time = sound3_time,
        wave_delay = wave_delay,
        annoy_time = annoy_time,
        user = user,
        must_destroy = must_destroy,
        must_save = must_save,
        wave_units1 = wave_units1,
        wave_units2 = wave_units2,
        sound1 = sound1,
        sound2 = sound2,
        sound3 = sound3,
        difficulty = difficulty,
    }
end

function Load(state)
    if not state then return end
    start_done = state.start_done
    objective1_complete = state.objective1_complete
    objective2_complete = state.objective2_complete
    waves_spawned = state.waves_spawned
    lost = state.lost
    won = state.won
    sound1_time = state.sound1_time
    sound2_time = state.sound2_time
    sound3_time = state.sound3_time
    wave_delay = state.wave_delay
    annoy_time = state.annoy_time
    user = state.user
    must_destroy = state.must_destroy
    must_save = state.must_save
    wave_units1 = state.wave_units1
    wave_units2 = state.wave_units2
    sound1 = state.sound1
    sound2 = state.sound2
    sound3 = state.sound3
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
        SetAIP("bdmisn07.aip")
        SetScrap(1, 8)
        SetPilot(1, 10)

        must_save[1] = GetHandle("recycler")
        must_save[2] = GetHandle("myfactory")
        must_save[3] = GetHandle("my_hq")

        must_destroy[1] = GetHandle("chin_recycler")
        must_destroy[2] = GetHandle("chin_factory")
        must_destroy[3] = GetHandle("chin_solar1")
        must_destroy[4] = GetHandle("chin_solar2")
        must_destroy[5] = GetHandle("chin_solar3")
        must_destroy[6] = GetHandle("chin_tower1")
        must_destroy[7] = GetHandle("chin_tower2")
        must_destroy[8] = GetHandle("chin_tower3")
        must_destroy[9] = GetHandle("chin_supply")
        must_destroy[10] = GetHandle("chin_hq")
        must_destroy[11] = GetHandle("chin_hangar")

        wave_units1[1] = GetHandle("chin_scout1")
        wave_units1[2] = GetHandle("chin_scout2")
        wave_units1[3] = GetHandle("chin_scout3")

        wave_units2[1] = GetHandle("chin_scout4")
        wave_units2[2] = GetHandle("chin_scout5")
        wave_units2[3] = GetHandle("chin_scout6")
        wave_units2[4] = GetHandle("chin_ltnk1")
        wave_units2[5] = GetHandle("chin_ltnk2")
        wave_units2[6] = GetHandle("chin_tank1")
        wave_units2[7] = GetHandle("chin_bomber1")
        wave_units2[8] = GetHandle("chin_bomber2")

        local nm = GetHandle("nav_mybase"); if nm then SetName(nm, "Black Dog Base") end
        local nc = GetHandle("nav_chinbase"); if nc then SetName(nc, "Chinese Base") end

        sound1_time = GetTime() + 5.0
        start_done = true
    end

    if lost or won then return end

    -- Audio Sequence
    if GetTime() > sound1_time then
        sound1_time = 99999.0
        sound1 = AudioMessage("bd07001.wav")
    end
    if sound1 and IsAudioMessageDone(sound1) then
        sound1 = nil
        sound2_time = GetTime() + 1.0
    end

    if GetTime() > sound2_time then
        sound2_time = 99999.0
        sound2 = AudioMessage("bd07002.wav")
    end
    if sound2 and IsAudioMessageDone(sound2) then
        sound2 = nil
        sound3_time = GetTime() + 2.0
    end

    if GetTime() > sound3_time then
        sound3_time = 99999.0
        sound3 = AudioMessage("bd07003.wav")
    end
    if sound3 and IsAudioMessageDone(sound3) then
        sound3 = nil
        ClearObjectives()
        AddObjective("bd07001.otf", "white")
        -- BlackDog07Mission.cpp initializes both waveDelay values to infinity
        -- and never arms the first one, making its wave/objective chain
        -- unreachable. Arm it after the briefing to restore the evident flow.
        wave_delay[1] = GetTime() + 2.0
    end

    -- Waves
    if GetTime() > wave_delay[1] then
        wave_delay[1] = 99999.0
        wave_delay[2] = GetTime() + 30.0
        for i=1,3 do if IsAlive(wave_units1[i]) then Goto(wave_units1[i], "attack_path1", 1) end end
    end

    if GetTime() > wave_delay[2] then
        wave_delay[2] = 99999.0
        for i=1,8 do if IsAlive(wave_units2[i]) then Goto(wave_units2[i], "attack_path2", 1) end end
        waves_spawned = true
    end

    -- Objective 1 Check (Defeat Initial Waves)
    if waves_spawned and not objective1_complete then
        local any_alive = false
        for i=1,3 do if IsAlive(wave_units1[i]) then any_alive = true break end end
        if not any_alive then
            for i=1,8 do if IsAlive(wave_units2[i]) then any_alive = true break end end
        end

        if not any_alive then
            objective1_complete = true
            ClearObjectives()
            AddObjective("bd07002.otf", "white")
            AudioMessage("bd07004.wav")
            annoy_time = GetTime() + 1.0

            -- Boost Enemy Scrap if low
            local scrap = GetScrap(2)
            if scrap < 40 then SetScrap(2, 40) end
        end
    end

    -- Annoy Waves
    if GetTime() > annoy_time then
        annoy_time = GetTime() + 5 * 60.0 -- 5 Mins

        -- C++: 3 Fighters, 2 Light Tanks
        for i=1,3 do
            local h = BuildObject("cvfigh", 2, "annoy_1")
            Attack(h, user)
        end
        for i=1,2 do
            local h = BuildObject("cvltnk", 2, "annoy_1")
            Attack(h, user)
        end
    end

    -- Win Condition
    if not won and not lost then
        local enemy_alive = false
        for i=1,11 do
            if IsAlive(must_destroy[i]) then
                enemy_alive = true
                break
            end
        end

        if not enemy_alive then
            won = true
            ClearObjectives()
            AddObjective("bd07002.otf", "green")
            SucceedMission(GetTime() + 1.0, "bd07win.des")
        end
    end

    -- Lose Condition
    if not won and not lost then
        local friend_alive = false
        for i=1,3 do
            if IsAlive(must_save[i]) then -- C++ checks GetHealth > 0.0
                friend_alive = true
                break
            end
        end

        if not friend_alive then
            lost = true
            FailMission(GetTime() + 1.0, "bd07lose.des")
        end
    end
end

