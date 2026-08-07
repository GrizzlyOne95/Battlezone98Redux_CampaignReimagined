-- bdmisn11.lua (Converted from BlackDog11Mission.cpp)
-- Source-disabled notes: the recycler was once redirected to "geyser_1", and
-- navEnd could be spawned as apcamr at "nav_end" instead of using the map nav.
-- The TEST_EXPLOSION-only SetPerceivedTeam experiment is also intentionally
-- inactive: it was compile-time test code, not part of the campaign flow.
-- The source calls the APC/recycler rendezvous the "pilot transfer point".

-- Compatibility
SetLabel = SetLabel or SetLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({ "campaignReimagined", "3686673790" })
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
local camera_ready = { false, false, false }
local camera_complete = { false, false, false }
local apc_wants_to_transfer = false
local pilot_transferring = false
local told_to_go = false
local attacks_sent = false
local nav_distance_ok = false
local retreat_spawned = false
local sound4_played = false
local sound5_played = false
local sound6_played = false
local cockpit_timer_active = false
local explode_portal = false
local arried = false
local lost = false
local won = false

-- Timers
local recycler_go_time = 99999.0
local drive1_time = 99999.0
local attack_times = { 99999.0, 99999.0, 99999.0, 99999.0, 99999.0, 99999.0 }
local go_to_portal_time = 99999.0
local camera_destruct_time = 99999.0
local explode_time = 99999.0
local explode_delay = 99999.0
local explode_seq_times = { 99999.0, 99999.0, 99999.0, 99999.0 } -- 1-4
local aerial1_time = 99999.0
local aerial2_time = 99999.0
local sound8_time = 99999.0
local sound9_time = 99999.0
local sound12_time = 99999.0

-- Handles
local user
local recycler, apc, pilot
local portal
local nav_recycler, nav_end
local sound4, sound5, sound6
local enemy = {} -- Up to 71

-- Logic Data
local attacks = { 0, 2, 4, 8, 11, 14, 23 } -- Index offsets
local defends = { 0, 4, 9, 14, 21, 30, 42 }
local attack_spawns = { "attack_1", "attack_2", "attack_3", "attack_4", "attack_5", "attack_6" }
local defend_spawns = { "defend_1", "defend_2", "defend_3", "defend_4", "defend_5", "defend_6" }

local attack_units_list = {
    "cvhraz", "cvhraz",                                                                      -- 1
    "cvhtnk", "cvhraz",                                                                      -- 2
    "cvhraz", "cvhraz", "cvhtnk", "cvhtnk",                                                  -- 3
    "cvhtnk", "cvhtnk", "cvhtnk",                                                            -- 4
    "cvhraz", "cvhraz", "cvhraz",                                                            -- 5
    "cvhtnk", "cvhtnk", "cvhtnk", "cvfigh", "cvfigh", "cvfigh", "cvhraz", "cvhraz", "cvhraz" -- 6
}

local defend_units_list = {
    "cvtnk", "cvtnk", "cvfigh", "cvfigh",                                                                              -- 1
    "cvfigh", "cvfigh", "cvfigh", "cvhtnk", "cvltnk",                                                                  -- 2
    "cvtnk", "cvtnk", "cvtnk", "cvfigh", "cvfigh",                                                                     -- 3
    "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvtnk", "cvtnk", "cvtnk",                                                 -- 4
    "cvhtnk", "cvhtnk", "cvhtnk", "cvhtnk", "cvtnk", "cvtnk", "cvtnk", "cvfigh", "cvfigh",                             -- 5
    "cvhtnk", "cvhtnk", "cvhtnk", "cvhtnk", "cvtnk", "cvtnk", "cvtnk", "cvtnk", "cvfigh", "cvfigh", "cvfigh",
    "cvfigh"                                                                                                           -- 6
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
        camera_ready = camera_ready,
        camera_complete = camera_complete,
        apc_wants_to_transfer = apc_wants_to_transfer,
        pilot_transferring = pilot_transferring,
        told_to_go = told_to_go,
        attacks_sent = attacks_sent,
        nav_distance_ok = nav_distance_ok,
        retreat_spawned = retreat_spawned,
        sound4_played = sound4_played,
        sound5_played = sound5_played,
        sound6_played = sound6_played,
        cockpit_timer_active = cockpit_timer_active,
        explode_portal = explode_portal,
        arried = arried,
        lost = lost,
        won = won,
        recycler_go_time = recycler_go_time,
        drive1_time = drive1_time,
        attack_times = attack_times,
        go_to_portal_time = go_to_portal_time,
        camera_destruct_time = camera_destruct_time,
        explode_time = explode_time,
        explode_delay = explode_delay,
        explode_seq_times = explode_seq_times,
        aerial1_time = aerial1_time,
        aerial2_time = aerial2_time,
        sound8_time = sound8_time,
        sound9_time = sound9_time,
        sound12_time = sound12_time,
        user = user,
        recycler = recycler,
        apc = apc,
        pilot = pilot,
        portal = portal,
        nav_recycler = nav_recycler,
        nav_end = nav_end,
        sound4 = sound4,
        sound5 = sound5,
        sound6 = sound6,
        enemy = enemy,
        attacks = attacks,
        defends = defends,
        attack_spawns = attack_spawns,
        defend_spawns = defend_spawns,
        attack_units_list = attack_units_list,
        defend_units_list = defend_units_list,
        difficulty = difficulty,
    }
end

function Load(state)
    if not state then return end
    start_done = state.start_done
    objective1_complete = state.objective1_complete
    objective2_complete = state.objective2_complete
    objective3_complete = state.objective3_complete
    camera_ready = state.camera_ready
    camera_complete = state.camera_complete
    apc_wants_to_transfer = state.apc_wants_to_transfer
    pilot_transferring = state.pilot_transferring
    told_to_go = state.told_to_go
    attacks_sent = state.attacks_sent
    nav_distance_ok = state.nav_distance_ok
    retreat_spawned = state.retreat_spawned
    sound4_played = state.sound4_played
    sound5_played = state.sound5_played
    sound6_played = state.sound6_played
    cockpit_timer_active = state.cockpit_timer_active
    explode_portal = state.explode_portal
    arried = state.arried
    lost = state.lost
    won = state.won
    recycler_go_time = state.recycler_go_time
    drive1_time = state.drive1_time
    attack_times = state.attack_times
    go_to_portal_time = state.go_to_portal_time
    camera_destruct_time = state.camera_destruct_time
    explode_time = state.explode_time
    explode_delay = state.explode_delay
    explode_seq_times = state.explode_seq_times
    aerial1_time = state.aerial1_time
    aerial2_time = state.aerial2_time
    sound8_time = state.sound8_time
    sound9_time = state.sound9_time
    sound12_time = state.sound12_time
    user = state.user
    recycler = state.recycler
    apc = state.apc
    pilot = state.pilot
    portal = state.portal
    nav_recycler = state.nav_recycler
    nav_end = state.nav_end
    sound4 = state.sound4
    sound5 = state.sound5
    sound6 = state.sound6
    enemy = state.enemy
    attacks = state.attacks
    defends = state.defends
    attack_spawns = state.attack_spawns
    defend_spawns = state.defend_spawns
    attack_units_list = state.attack_units_list
    defend_units_list = state.defend_units_list
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

local function IsAtPathEnd(handle, path, radius)
    local count = GetPathPointCount(path) or 0
    if count < 1 then return false end
    return GetDistance(handle, GetPosition(path, count - 1)) < (radius or 50.0)
end

function Update()
    user = GetPlayerHandle()
    aiCore.Update()

    if not start_done then
        SetScrap(1, 100)
        SetPilot(1, 10)

        ClearObjectives()
        AddObjective("bd11001.otf", "white")

        recycler = GetHandle("recycler")
        portal = GetHandle("portal")
        apc = GetHandle("apc")

        nav_recycler = BuildObject("apcamr", 1, "recy_nav")
        SetLabel(nav_recycler, "Recycler")

        start_done = true
    end

    if lost or won then return end

    -- Lose Logic
    if not IsAlive(recycler) and not won and not lost then
        lost = true
        if nav_distance_ok then
            FailMission(GetTime() + 1.0, "bd11lseb.des")
        else
            FailMission(GetTime() + 1.0, "bd11lsed.des")
        end
    end

    if not objective1_complete and not IsAlive(apc) and not won and not lost then
        lost = true
        FailMission(GetTime() + 1.0, "bd11lsea.des")
    end

    -- Intro
    if not camera_complete[1] then
        if not camera_ready[1] then
            camera_ready[1] = true
            CameraReady()
            AudioMessage("bd11001.wav")
        end

        local arrived_camera = CameraPath("camera_start", 1000, 1600, recycler)

        if arrived_camera or CameraCancelled() then
            CameraFinish()
            camera_complete[1] = true
        end
    end

    -- Pilot Transfer
    if not objective1_complete and not pilot_transferring then
        local dist = GetDistance(apc, recycler)
        local enemy = GetNearestEnemy(apc)
        if dist < 50.0 and (not enemy or GetDistance(apc, enemy) > 200.0) then
            Stop(apc, 1)
            pilot_transferring = true
            pilot = BuildObject("aspilo", 1, apc)
            Retreat(pilot, recycler, 1)
        end
    end

    if pilot_transferring then
        if IsAlive(pilot) then GiveMaxHealth(pilot) end
        if not IsAlive(pilot) and not won and not lost then
            lost = true
            FailMission(GetTime() + 1.0, "bd11lsec.des")
        end

        if IsAlive(pilot) and GetDistance(pilot, recycler) < 15.0 then
            pilot_transferring = false
            objective1_complete = true
            RemoveObject(pilot)
            pilot = nil

            SetPilotClass(recycler, "bspilo")

            recycler_go_time = GetTime() + 2.0
            AudioMessage("bd11002.wav")
        end
    end

    -- Recycler Move
    if GetTime() > recycler_go_time then
        told_to_go = true
        SetTeamNum(recycler, 1)
        recycler_go_time = 99999.0
        Goto(recycler, "recycler_path", 1)
        drive1_time = GetTime() + 20.0
    end

    if told_to_go and IsAtPathEnd(recycler, "recycler_path", 50.0) then
        told_to_go = false                                               -- Deployed presumably?
        ClearObjectives()
        AddObjective("bd11001.otf", "green")
        AddObjective("bd11002.otf", "white")
    end

    -- Independent of the six timed waves, the source sends this drive_1 force
    -- twenty seconds after the recycler starts moving.
    if GetTime() > drive1_time then
        drive1_time = 99999.0
        for _ = 1, 2 do
            local h = BuildObject("cvwalk", 2, "drive_1")
            Attack(h, recycler, 1)
        end
        for _ = 1, 2 do
            local h = BuildObject("cvltnk", 2, "drive_1")
            Attack(h, recycler, 1)
        end
    end

    -- Wave Triggers
    if not attacks_sent and GetDistance(recycler, "wave_trigger") < 50.0 then
        attacks_sent = true
        local t = GetTime()
        attack_times[1] = t + 2 * 60.0
        attack_times[2] = t + 5 * 60.0
        attack_times[3] = t + 9 * 60.0
        attack_times[4] = t + 14 * 60.0
        attack_times[5] = t + 18 * 60.0
        attack_times[6] = t + 21 * 60.0

        go_to_portal_time = t + 26 * 60.0 -- 26 mins?
        aerial1_time = t + 8 * 60.0
        aerial2_time = t + 13 * 60.0

        -- Initial Trigger Spawns
        local function AttackRecy(odf)
            local h = BuildObject(odf, 2, "drive_2"); Attack(h, recycler)
        end
        AttackRecy("cvltnk"); AttackRecy("cvltnk"); AttackRecy("cvltnk")
        AttackRecy("cvhraz"); AttackRecy("cvhraz")
    end

    -- Preserve the original escalating recycler-damage warnings. Each lower
    -- threshold stops the earlier line so the three messages cannot overlap.
    if objective1_complete and IsAlive(recycler) then
        local health = GetHealth(recycler)
        if health <= 0.5 and health > 0.25 and not sound4_played then
            sound4_played = true
            sound4 = AudioMessage("bd11004.wav")
        elseif health <= 0.25 and health > 0.15 and not sound5_played then
            if sound4 then StopAudioMessage(sound4) end
            sound5_played = true
            sound5 = AudioMessage("bd11005.wav")
        elseif health <= 0.15 and health > 0.0 and not sound6_played then
            if sound4 then StopAudioMessage(sound4) end
            if sound5 then StopAudioMessage(sound5) end
            sound6_played = true
            sound6 = AudioMessage("bd11006.wav")
        end
    end

    -- Process Waves
    for i = 1, 6 do
        if GetTime() > attack_times[i] then
            attack_times[i] = 99999.0

            -- Attackers
            -- Logic: attacks[i] to attacks[i+1]
            local start_idx = attacks[i] + 1
            local end_idx = attacks[i + 1]
            if not end_idx then end_idx = #attack_units_list end -- Fallback

            local wave_attackers = {}
            for j = start_idx, end_idx do
                local u = attack_units_list[j]
                if u then
                    local h = BuildObject(u, 2, attack_spawns[i])
                    SetCloaked(h)
                    Attack(h, recycler)
                    wave_attackers[#wave_attackers + 1] = h
                end
            end

            -- Defenders
            start_idx = defends[i] + 1
            end_idx = defends[i + 1]
            for j = start_idx, end_idx do
                local u = defend_units_list[j]
                if u then
                    local h = BuildObject(u, 2, defend_spawns[i])
                    SetCloaked(h)
                    -- BlackDog11Mission.cpp assigns each defender to an attacker
                    -- from the same wave, wrapping with j % numAttackers.
                    if #wave_attackers > 0 then
                        local target = wave_attackers[((j - start_idx) % #wave_attackers) + 1]
                        Defend2(h, target, 1)
                    end
                end
            end
        end
    end

    -- Aerials
    if GetTime() > aerial1_time then
        aerial1_time = 99999.0
        for i = 1, 8 do
            local h = BuildObject("cssold", 2, "aerial_1"); Attack(h, recycler)
        end
        -- Source passes 400 as BuildObject's aerial height. The Lua binding has
        -- no equivalent height parameter; the authored aerial_1 path supplies
        -- the spawn location while preserving the source unit count and orders.
    end
    if GetTime() > aerial2_time then
        aerial2_time = 99999.0
        for i = 1, 8 do
            local h = BuildObject("cssold", 2, "aerial_1"); Attack(h, recycler)
        end
    end

    -- Portal Phase
    if GetTime() > go_to_portal_time then
        go_to_portal_time = 99999.0
        ClearObjectives()
        AddObjective("bd11002.otf", "green")
        AudioMessage("bd11007.wav")
        sound8_time = GetTime() + 3.0
    end

    if GetTime() > sound8_time then
        sound8_time = 99999.0
        AudioMessage("bd11008.wav")
        sound9_time = GetTime() + 5.0
    end

    if GetTime() > sound9_time then
        sound9_time = 99999.0
        AudioMessage("bd11009.wav")
        AudioMessage("bd11010.wav")
        sound12_time = GetTime() + 5.0
    end

    if GetTime() > sound12_time then
        sound12_time = 99999.0
        AudioMessage("bd11012.wav")
        ClearObjectives()
        AddObjective("bd11003.otf", "white")
        SetObjectiveOn(portal)
        StartCockpitTimer(90, 30, 10)
        cockpit_timer_active = true
    end

    -- End Sequence
    if cockpit_timer_active and GetCockpitTimer() <= 0.0 then
        cockpit_timer_active = false
        HideCockpitTimer()
        local t = GetTime()
        explode_seq_times[1] = t
        explode_seq_times[2] = t + 2.0
        explode_seq_times[3] = t + 4.0
        explode_seq_times[4] = t + 6.0
        explode_time = t + 18.0
        camera_destruct_time = t + 17.0
        nav_distance_ok = true -- Won basically
    end

    for i = 1, 4 do
        if GetTime() > explode_seq_times[i] then
            explode_seq_times[i] = 99999.0
            MakeExplosion("xpltrsk", "dw_" .. i)
        end
    end

    if GetTime() > camera_destruct_time then
        camera_destruct_time = 99999.0
        CameraReady()
        CameraPath("camera_destruct", 1000, 0, portal)
    end

    if GetTime() > explode_time then
        explode_time = 99999.0
        explode_delay = GetTime() + 3.0
        explode_portal = true
        MakeExplosion("xpltrso", portal)
    end

    if GetTime() > explode_delay then
        explode_delay = 99999.0
        CameraFinish()
        AudioMessage("bd11011.wav") -- Victory words
        ClearObjectives()
        AddObjective("bd11003.otf", "green")

        -- Win
        won = true
        SucceedMission(GetTime() + 3.0, "bd11win.des")
    end

    -- Safety Fail
    if IsAlive(portal) and GetHealth(portal) <= 0.0 and not explode_portal and not won and not lost then
        lost = true
        FailMission(GetTime() + 1.0, "bd11lsee.des") -- Destroyed too early?
    end
end
