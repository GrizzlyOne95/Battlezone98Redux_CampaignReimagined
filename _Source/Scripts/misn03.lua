-- misn03mission.lua

-- Compatibility for 1.5
SetLabel = SetLabel or SettLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
local exu = require("exu")
aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")
local subtit = require("ScriptSubtitles")
local PersistentConfig = require("PersistentConfig")

-- Helper for AI
local function SetupAI()
    local playerTeam, enemyTeam = DiffUtils.SetupTeams(aiCore.Factions.NSDF, aiCore.Factions.CCA, 2)
    
    -- Disable factory management for player (prevent forced deployment)
    playerTeam:SetConfig("manageFactories", false)
    playerTeam:SetConfig("autoRepairWingmen", PersistentConfig.Settings.AutoRepairWingmen)
end

-- Mission State
local M = {
    -- Bools
    first_wave_done = false,
    second_wave_done = false,
    third_wave_done = false,
    fourth_wave_done = false,
    fifth_wave_done = false,
    turret_move_done = false,
    rescue_move_done = false,
    help_spawn = false,
    help_arrive = false,
    end_game = false,
    trans_underway = false,
    ambush_message = false,
    start_done = false,
    first_objective = false,
    second_objective = false,
    third_objective = false,
    final_objective = false,
    special_objective = false,
    start_retreat = false,
    done_retreat = false,
    new_message_start = false,
    dead1 = false,
    dead2 = false,
    dead3 = false,
    camera_on = false,
    camera_off = false,
    help_stop1 = false,
    help_stop2 = false,
    recycle_stop = false,
    message1 = false,
    scavhunt = false,
    scavhunt2 = false,
    lost = false,
    camera_ready = false,
    start_movie = false,
    movie_over = false,
    remove_props = false,
    more_show = false,
    tanks_go = false,
    camera_2 = false,
    show_tank_attack = false,
    tower_dead = false,
    climax1 = false,
    climax2 = false,
    clear_debis = false,
    last_blown = false,
    end_shot = false,
    clean_sweep = false,
    startfinishingmovie = false,
    turrets_set = false,
    speach2 = false,
    second_warning = false,
    last_warning = false,
    
    -- New Bools for Enhancements
    solar1_warned = false,
    solar2_warned = false,
    patrols_spawned = false,
    apc_arrived_at_base = false,
    patrol_soldiers = {nil, nil, nil},
    patrol_respawn_timers = {0, 0, 0},

    -- Floats
    next_second = 0.0,
    alarm_sound_timer = 0.0,
    retreat_timer = 0.0,
    next_wave = 99999.0,
    second_wave_time = 99999.0,
    ambush_message_time = 99999.0,
    new_message_time = 99999.0,
    apc_spawn_time = 99999.0,
    pull_out_time = 99999.0,
    third_wave_time = 99999.0,
    fourth_wave_time = 99999.0,
    fifth_wave_time = 99999.0,
    turret_move_time = 99999.0,
    wave3_time = 99999.0,
    wave4_time = 99999.0,
    camera_off_time = 99999.0,
    support_time = 99999.0,
    movie_time = 99999.0,
    new_unit_time = 99999.0,
    next_shot = 99999.0,
    kill_tower = 99999.0,
    clear_debis_time = 99999.0,
    unit_check = 99999.0,
    clean_sweep_time = 99999.0,
    final_check = 99999.0,

    -- Handles
    user = nil,
    avrecycler = nil,
    geyser = nil, cam_geyser = nil, shot_geyser = nil,
    scav1 = nil, scav2 = nil, scav3 = nil, scav4 = nil, scav5 = nil, scav6 = nil,
    crate1 = nil, crate2 = nil, crate3 = nil,
    rescue1 = nil, rescue2 = nil, rescue3 = nil,
    wave1_1 = nil, wave1_2 = nil, wave1_3 = nil,
    wave2_1 = nil, wave2_2 = nil, wave2_3 = nil,
    wave3_1 = nil, wave3_2 = nil, wave3_3 = nil,
    wave4_1 = nil, wave4_2 = nil, wave4_3 = nil,
    wave5_1 = nil, wave5_2 = nil, wave5_3 = nil,
    wave6_1 = nil, wave6_2 = nil, wave6_3 = nil,
    wave7_1 = nil, wave7_2 = nil, wave7_3 = nil, wave7_4 = nil, wave7_5 = nil, wave7_6 = nil,
    turret1 = nil, turret2 = nil, turret3 = nil, turret4 = nil,
    spawn_point1 = nil, spawn_point2 = nil,
    launch = nil, nest = nil, solar1 = nil, solar2 = nil, solar3 = nil, solar4 = nil,
    help1 = nil, help2 = nil,
    build1 = nil, build2 = nil, build3 = nil, build4 = nil, build5 = nil, hanger = nil,
    prop1 = nil, prop2 = nil, prop3 = nil, prop4 = nil, prop5 = nil, prop6 = nil, prop7 = nil, prop8 = nil, prop9 = nil, prop0 = nil,
    guy1 = nil, guy2 = nil, guy3 = nil, guy4 = nil, box1 = nil, sucker = nil,
    avturret1 = nil, avturret2 = nil, avturret3 = nil, avturret4 = nil, avturret5 = nil,
    avturret6 = nil, avturret7 = nil, avturret8 = nil, avturret9 = nil, avturret10 = nil,

    -- Integers
    x = 4000,
    z = 1,
    y = 1,
    audmsg = nil,
    
    -- Tables
    solar_list = {false, false, false}, -- Track objective status for solar2, solar3, solar4

    -- Input State Logic is now handled by PersistentConfig module
}

function Save()
    return M, aiCore.Save()
end

function Load(data, aiData)
    if data then M = data end
    if aiData then aiCore.Load(aiData) end
    aiCore.Bootstrap() -- Refresh/Capture units
    ApplyQOL() -- Reapply engine settings
end

-- EXU/QOL Persistence Helper
function ApplyQOL()
    if not exu then return end
    
    if exu.SetShotConvergence then exu.SetShotConvergence(true) end
    if exu.SetReticleRange then exu.SetReticleRange(600) end
    if exu.SetOrdnanceVelocInheritance then exu.SetOrdnanceVelocInheritance(true) end

    -- Initialize Persistent Config (Loads, Applies, and Greets)
    PersistentConfig.Initialize()
end


function Start()
    M.x = 4000
    M.z = 1
    M.y = 1

    M.avrecycler = GetHandle("avrec3-1_recycler")
    M.scav1 = GetHandle("scav1")
    M.scav2 = GetHandle("scav2")
    M.wave1_1 = GetHandle("svfigh1")
    M.wave1_2 = GetHandle("svfigh2")
    M.wave1_3 = nil -- 0 in C++
    M.turret1 = GetHandle("enemyturret_1")
    M.turret2 = GetHandle("enemyturret_2")
    M.turret3 = GetHandle("enemyturret_3")
    M.turret4 = GetHandle("enemyturret_4")
    M.geyser = GetHandle("geyser1")
    M.solar1 = GetHandle("solar1")
    M.solar2 = GetHandle("solar2")
    M.solar3 = GetHandle("solar3")
    M.solar4 = GetHandle("solar4")
    M.launch = GetHandle("launch_pad")
    M.build1 = GetHandle("build1")
    M.build3 = GetHandle("build3")
    M.build4 = GetHandle("build4")
    M.build5 = GetHandle("build5")
    M.hanger = GetHandle("hanger")
    M.cam_geyser = GetHandle("cam_geyser")
    M.shot_geyser = GetHandle("shot_geyser")
    M.box1 = GetHandle("box1")
    M.crate1 = GetHandle("crate1")
    M.crate2 = GetHandle("crate2")
    M.crate3 = GetHandle("crate3")
    M.guy1 = GetHandle("guy1")
    M.guy2 = GetHandle("guy2")
    M.sucker = GetHandle("sucker")
    
    if exu then
        -- ApplyQOL() -- This is now handled by PersistentConfig.Initialize() which is called in ApplyQOL()
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI() -- Initialize AI on Start
    aiCore.Bootstrap() -- Capture pre-placed units

    local difficulty = (exu and exu.GetDifficulty and exu.GetDifficulty()) or 2
    if difficulty >= 3 then
        AddObjective("hard_diff", "yellow", 8.0, "High Difficulty: Enemy presence intensified.")
    elseif difficulty <= 1 then
        AddObjective("easy_diff", "blue", 8.0, "Low Difficulty: Enemy presence reduced.")
    end
end

function AddObject(h)
    local team = GetTeamNum(h)

    -- Apply turbo to new enemy units on Very Hard difficulty
    if exu and exu.SetUnitTurbo and IsCraft(h) then
        if team == 1 then
            exu.SetUnitTurbo(h, true)
        elseif team ~= 0 then
            local diff = (exu.GetDifficulty and exu.GetDifficulty()) or 2
            if diff > 3 then
                exu.SetUnitTurbo(h, true)
            end
        end
    end

    if IsOdf(h, "avturr") then
        if M.avturret1 == nil then M.avturret1 = h
        elseif M.avturret2 == nil then M.avturret2 = h
        elseif M.avturret3 == nil then M.avturret3 = h
        elseif M.avturret4 == nil then M.avturret4 = h
        elseif M.avturret5 == nil then M.avturret5 = h
        elseif M.avturret6 == nil then M.avturret6 = h
        elseif M.avturret7 == nil then M.avturret7 = h
        elseif M.avturret8 == nil then M.avturret8 = h
        elseif M.avturret9 == nil then M.avturret9 = h
        elseif M.avturret10 == nil then M.avturret10 = h
        end
    elseif IsOdf(h, "avscav") then
        if M.scav3 == nil then M.scav3 = h
        elseif M.scav4 == nil then M.scav4 = h
        elseif M.scav5 == nil then M.scav5 = h
        elseif M.scav6 == nil then M.scav6 = h
        end
    end
    
    -- Only register units with aiCore if they are produced by the AI (near factory/recycler)
    -- Scripted waves spawn far away and should be ignored to prevent Squad hijacking
    if team == 2 or team == 1 then
        local register = false
        
        if team == 2 then
            local prod = {GetRecyclerHandle(2), GetFactoryHandle(2)}
            for _, p in ipairs(prod) do
                if IsValid(p) and GetDistance(h, p) < 150 then
                    register = true
                    break
                end
            end
            
            -- Also check if it IS the recycler/factory/constructor itself
            if h == GetRecyclerHandle(team) or h == GetFactoryHandle(team) or h == GetConstructorHandle(team) or h == GetArmoryHandle(team) then
                register = true
            end
        else
            -- Always register player-team scavengers for assist
            if IsOdf(h, "avscav") then register = true end
        end

        if register then
            aiCore.AddObject(h)
        end
    end

end

function Update()
    M.user = GetPlayerHandle()
    if exu and exu.UpdateOrdnance then exu.UpdateOrdnance() end
    
    -- Get difficulty for dynamic adjustments (0=Very Easy, 1=Easy, 2=Medium, 3=Hard, 4=Very Hard)
    local diff = 2
    if exu and exu.GetDifficulty then diff = exu.GetDifficulty() end
    
    aiCore.Update()
    subtit.Update()
    PersistentConfig.UpdateInputs()
    PersistentConfig.UpdateHeadlights()


    -- Update Objective Health Status
    if IsAlive(M.solar1) then
        SetObjectiveName(M.solar1, "Command Tower: " .. math.floor(GetHealth(M.solar1) * 100) .. "%")
    end
    if IsAlive(M.solar2) then
        SetObjectiveName(M.solar2, "Solar Array: " .. math.floor(GetHealth(M.solar2) * 100) .. "%")
    end
    if IsAlive(M.solar3) then
        SetObjectiveName(M.solar3, "Solar Array: " .. math.floor(GetHealth(M.solar3) * 100) .. "%")
    end
    if IsAlive(M.solar4) then
        SetObjectiveName(M.solar4, "Solar Array: " .. math.floor(GetHealth(M.solar4) * 100) .. "%")
    end

    if not M.start_done then
        ApplyQOL()

        -- Dynamic Starting Resources
        SetScrap(1, math.max(4, DiffUtils.ScaleRes(10)))
        SetPilot(1, DiffUtils.ScaleRes(10))
        SetScrap(2, 40) -- Give AI Team 2 starting scrap

        subtit.Initialize("durations.csv")

        -- Steam Integration: Personalized Greeting
        if exu and exu.GetSteam64 then
            local steamID = exu.GetSteam64()
            if steamID and steamID ~= "" then
                print("Welcome back, Commander. SteamID: " .. steamID)
                -- We could also use this for specific rewards or greetings if we had a mapping
            end
        end

        SetObjectiveOn(M.solar1)
        SetObjectiveName(M.solar1, "Command Tower")
        SetCritical(M.solar1, true)

        -- Solar Array Objectives (Difficulty Based)
        -- We only mark the number we are required to save
        local diff = (exu and exu.GetDifficulty and exu.GetDifficulty()) or 2
        local required = 1
        if diff == 3 then required = 2
        elseif diff > 3 then required = 3 end

        SetObjectiveOn(M.solar2)
        SetObjectiveName(M.solar2, "Solar Array")
        SetCritical(M.solar2, false)
        M.solar_list[1] = true

        if required >= 2 and IsAlive(M.solar3) then
             SetObjectiveOn(M.solar3)
             SetObjectiveName(M.solar3, "Solar Array")
             SetCritical(M.solar3, false)
             M.solar_list[2] = true
        end
        if required >= 3 and IsAlive(M.solar4) then
             SetObjectiveOn(M.solar4)
             SetObjectiveName(M.solar4, "Solar Array")
             SetCritical(M.solar4, false)
             M.solar_list[3] = true
        end

        -- Difficulty Health Scaling for Critical Buildings
        local m = DiffUtils.Get()
        local health_mod = m.res -- reuse resource mult for simplicity or inverse?
        -- User didn't specify health but keep it scaled.
        
        if IsAlive(M.solar1) then
            SetMaxHealth(M.solar1, GetMaxHealth(M.solar1) * health_mod)
            SetCurHealth(M.solar1, GetMaxHealth(M.solar1))
        end
        if IsAlive(M.solar2) then
            SetMaxHealth(M.solar2, GetMaxHealth(M.solar2) * health_mod)
            SetCurHealth(M.solar2, GetMaxHealth(M.solar2))
        end

        Goto(M.avrecycler, "recycle_point")
        ClearObjectives()
        AddObjective("misn0301.otf", "white")
        
        M.second_wave_time = GetTime() + DiffUtils.ScaleTimer(200.0) + math.random(-10, 20)
        M.third_wave_time = GetTime() + DiffUtils.ScaleTimer(310.0) + math.random(-15, 30)
        M.fourth_wave_time = GetTime() + DiffUtils.ScaleTimer(430.0) + math.random(-20, 40)
        
        M.apc_spawn_time = GetTime() + 530.0
        M.support_time = GetTime() + 430.0
        M.next_second = GetTime() + 1.0
        M.unit_check = GetTime() + 60.0
        M.start_done = true
    end

    -- Alarm for Command Tower
    if IsAlive(M.solar1) and GetHealth(M.solar1) < 1.0 then
        if not M.alarm_sound_timer or GetTime() > M.alarm_sound_timer then
            StartSound("misn0708.wav", M.solar1)
            M.alarm_sound_timer = GetTime() + 2.0
        end
    end

    -- Dynamic Health Warnings
    if IsAlive(M.solar1) and not M.solar1_warned then
        if GetHealth(M.solar1) < 0.4 then
            -- Using a generic warning sound or reusing a mission sound
            subtit.Play("misn0708.wav") 
            UpdateObjective("misn0301.otf", "yellow")
            M.solar1_warned = true
        end
    end

    if IsAlive(M.solar2) and not M.solar2_warned then
        if GetHealth(M.solar2) < 0.4 then
            subtit.Play("misn0708.wav")
            UpdateObjective("misn0301.otf", "yellow")
            M.solar2_warned = true
        end
    end

    -- Solar Array Defense Logic (Count Check)
    local solarCount = 0
    if IsAlive(M.solar2) then solarCount = solarCount + 1 end
    if IsAlive(M.solar3) then solarCount = solarCount + 1 end
    if IsAlive(M.solar4) then solarCount = solarCount + 1 end
    
    local required = 1
    if diff == 3 then required = 2 -- Hard
    elseif diff > 3 then required = 3 end -- Very Hard

    -- Dynamic Objective Update: Ensure we always show 'required' number of living arrays
    -- If S2 dies (and was marked), reveal S3, etc.
    local visibleCount = 0
    local arrays = {M.solar2, M.solar3, M.solar4}
    
    for i, h in ipairs(arrays) do
        if IsAlive(h) and M.solar_list[i] then
            visibleCount = visibleCount + 1
        end
    end
    
    if visibleCount < required then
        -- Find a hidden survivor and mark it
        for i, h in ipairs(arrays) do
            if IsAlive(h) and not M.solar_list[i] then
                SetObjectiveOn(h)
                SetObjectiveName(h, "Solar Array")
                SetCritical(h, false)
                M.solar_list[i] = true
                visibleCount = visibleCount + 1
                if visibleCount >= required then break end
            end
        end
    end

    if solarCount < required and not M.lost and not M.final_objective then
        -- Trigger Failure
        FailMission(GetTime() + 5.0)
        M.lost = true
    end

    -- Foot Soldier Patrols
    if M.start_done and IsAlive(M.build5) then
        M.patrol_soldiers = M.patrol_soldiers or {nil, nil, nil}
        M.patrol_respawn_timers = M.patrol_respawn_timers or {0, 0, 0}

        for i = 1, 3 do
            local soldier = M.patrol_soldiers[i]
            
            if not IsAlive(soldier) then
                if M.patrol_respawn_timers[i] == 0 then
                    -- Schedule spawn
                    local delay = 30.0
                    if not M.patrols_spawned then delay = 1.0 + (i * 2.0) end -- Initial spawn staggered
                    M.patrol_respawn_timers[i] = GetTime() + delay
                elseif GetTime() > M.patrol_respawn_timers[i] then
                    -- Spawn now
                    local pos = GetPositionNear(GetPosition(M.build5), 0, 10)
                    local new_soldier = BuildObject("aspilop", 1, pos)
                    if IsAlive(new_soldier) then
                        -- Jump!
                        local vel = GetVelocity(new_soldier)
                        vel.y = vel.y + 15.0
                        SetVelocity(new_soldier, vel)
                        
                        -- Orders
                        if i == 1 then
                            SetPathLoop("footpatrol", true)
                            Patrol(new_soldier, "footpatrol", 1)
                        elseif i == 2 then
                            Defend2(new_soldier, M.solar1)
                        elseif i == 3 then
                            Defend2(new_soldier, M.solar2)
                        end
                        
                        M.patrol_soldiers[i] = new_soldier
                        M.patrol_respawn_timers[i] = 0
                    end
                end
            end
        end
        M.patrols_spawned = true
    end

    if IsAlive(M.solar1) and not M.show_tank_attack then
        if GetTime() > M.next_second then
            AddHealth(M.solar1, 50)
            if IsAlive(M.solar2) then AddHealth(M.solar2, 50) end
            if IsAlive(M.solar3) then AddHealth(M.solar3, 50) end
            if IsAlive(M.solar4) then AddHealth(M.solar4, 50) end
            M.next_second = GetTime() + 1.0
        end
    end

    if not M.message1 and M.start_done then
        M.audmsg = subtit.Play("misn0311.wav")
        M.message1 = true
    end

    if M.start_done and GetDistance(M.avrecycler, "recycle_point") < 50.0 and not M.recycle_stop then
        Stop(M.avrecycler, 0)
        M.recycle_stop = true
    end

    if not M.first_wave_done then
        Attack(M.wave1_1, M.solar1, 1)
        Attack(M.wave1_2, M.solar1, 1)
        M.first_wave_done = true
    end

    if M.first_wave_done and not M.start_retreat then
        if diff < 3 then
            if not IsAlive(M.wave1_1) then
                Retreat(M.wave1_2, "retreat_path", 1)
                M.new_message_time = GetTime() + 13.0
                M.start_retreat = true
            elseif not IsAlive(M.wave1_2) then
                Retreat(M.wave1_1, "retreat_path", 1)
                M.new_message_time = GetTime() + 10.0
                M.start_retreat = true
            end
            end
        end

        -- If all enemies are dead (regardless of difficulty), advance the plot
        if not IsAlive(M.wave1_1) and not IsAlive(M.wave1_2) then
            -- Only set if not already retreating (to avoid overriding timer if one died earlier)
            if not M.start_retreat then
                M.new_message_time = GetTime() + 2.0
                M.start_retreat = true
            end
        end
    if M.start_retreat and M.new_message_time < GetTime() and not M.done_retreat then
        subtit.Play("misn0312.wav")
        ClearObjectives()
        AddObjective("misn0302.otf", "white")
        AddObjective("misn0301.otf", "white")
        M.done_retreat = true
    end

    if not M.turrets_set and IsAlive(M.solar1) and M.unit_check < GetTime() then
        M.unit_check = GetTime() + 5.0
        M.z = CountUnitsNearObject(M.solar1, 200.0, 1, "avturr")

        if M.z > 3 then
            ClearObjectives()
            AddObjective("misn0302.otf", "green")
            AddObjective("misn0301.otf", "white")
            M.turrets_set = true
        end
    end

    local spawns = {"nspawn", "wspawn", "spawn_scrap1"}

    -- Randomized Enemy Spawns for Wave 2
    if not M.second_wave_done and M.second_wave_time < GetTime() then
        -- Randomize unit types
        local type1 = "svfigh"
        local type2 = "svfigh"
        
        if diff >= 2 then -- Medium: Chance for light tanks
            if math.random() > 0.5 then type1 = "svltnk" end
            if math.random() > 0.5 then type2 = "svltnk" end
        end
        if diff >= 3 then -- Hard: Guaranteed light tanks
            type1 = "svltnk"
            type2 = "svtank"
            -- Extra unit for hard difficulty
            local pos = GetPositionNear(GetPosition(spawns[math.random(1,3)]), 0, 40)
            local extra = BuildObject("svfigh", 2, pos)
            Attack(extra, M.solar1)
        end

        local p1 = spawns[math.random(1,3)]
        local p2 = spawns[math.random(1,3)]
        M.wave2_1 = BuildObject(type1, 2, GetPositionNear(GetPosition(p1), 0, 40))
        M.wave2_2 = BuildObject(type2, 2, GetPositionNear(GetPosition(p2), 0, 40))
        
        Attack(M.wave2_1, M.solar1)
        Goto(M.wave2_2, M.solar1)
        
        M.second_wave_done = true
    end

    if not M.third_wave_done and M.third_wave_time < GetTime() then
        local type3 = "svfigh"
        if diff >= 3 then type3 = "svltnk" end

        local p1 = spawns[math.random(1,3)]
        local p2 = spawns[math.random(1,3)]
        M.wave3_1 = BuildObject(type3, 2, GetPositionNear(GetPosition(p1), 0, 40))
        M.wave3_2 = BuildObject("svfigh", 2, GetPositionNear(GetPosition(p2), 0, 40))
        
        Attack(M.wave3_1, M.solar1, 1)
        Attack(M.wave3_2, M.solar1, 1)
        
        M.third_wave_done = true
    end

    if not M.scavhunt and M.third_wave_done then
        if IsAlive(M.wave1_1) then
            Attack(M.wave1_1, M.scav1, 1)
        end
        if IsAlive(M.wave1_2) then
            Attack(M.wave1_2, M.scav1, 1)
        end
        M.scavhunt = true
    end

    if not M.fourth_wave_done and M.fourth_wave_time < GetTime() then
        local p1 = spawns[math.random(1,3)]
        local p2 = spawns[math.random(1,3)]
        local p3 = spawns[math.random(1,3)]
        M.wave4_1 = BuildObject("svapc", 2, GetPositionNear(GetPosition(p1), 0, 40))
        M.wave4_2 = BuildObject("svtank", 2, GetPositionNear(GetPosition(p2), 0, 40))
        M.wave5_1 = BuildObject("svfigh", 2, GetPositionNear(GetPosition(p3), 0, 40))

        if diff >= 3 then
            local p_extra = spawns[math.random(1,3)]
            local extra_tank = BuildObject("svtank", 2, GetPositionNear(GetPosition(p_extra), 0, 40))
            Attack(extra_tank, M.solar2, 1)
        end

        if IsAlive(M.avrecycler) then
            Attack(M.wave4_1, M.avrecycler, 1)
        elseif IsAlive(M.solar3) then
            Attack(M.wave4_1, M.solar3, 1)
        elseif IsAlive(M.solar4) then
            Attack(M.wave4_1, M.solar4, 1)
        end

        Attack(M.wave4_2, M.solar2, 1)
        M.fourth_wave_done = true
    end

    if not M.scavhunt2 and M.fourth_wave_done and IsAlive(M.wave5_1) then
        if IsAlive(M.scav1) then
            Attack(M.wave5_1, M.scav1, 1)
        elseif not IsAlive(M.scav2) then
            Attack(M.wave5_1, M.scav2, 1)
        end
        M.scavhunt2 = true
    end

    if not M.help_spawn and M.support_time < GetTime() then
        -- MODIFIED: Spawn APCs and Escorts early (Reinforcements)
        local lpos = GetPosition("lpadspawn")
        M.rescue1 = BuildObject("avapc2", 1, GetPositionNear(lpos, 0, 30))
        M.rescue2 = BuildObject("avapc2", 1, GetPositionNear(lpos, 0, 30))
        SetCritical(M.rescue1, true)
        SetCritical(M.rescue2, true)
        -- Don't show on map yet, but help player find one
        SetUserTarget(M.rescue1)
        SetObjectiveName(M.rescue1, "Transport 1")
        SetObjectiveName(M.rescue2, "Transport 2")
        -- Use ID misn0303.otf so we can update it later
        AddObjective("misn0303.otf", "white", 8.0, "Protect Transport APCs") 

        M.help1 = BuildObject("avfigh", 1, GetPositionNear(lpos, 0, 30)) -- Scout
        M.help2 = BuildObject("avtank", 1, GetPositionNear(lpos, 0, 30)) -- Tank
        
        subtit.Play("misn0314.wav")
        
        -- Convoy to base
        Goto(M.rescue1, "apc1_spawn")
        Goto(M.rescue2, "apc2_spawn")
        
        -- Escorts guard APCs (Player controllable: priority 0)
        Follow(M.help1, M.rescue2, 0)
        Follow(M.help2, M.rescue1, 0)
        
        M.help_spawn = true
    end



    if not M.second_objective and M.apc_spawn_time < GetTime() then
        M.apc_spawn_time = GetTime() + 1.0
        M.z = CountUnitsNearObject(M.user, 500.0, 2, "svtank")
        M.y = CountUnitsNearObject(M.user, 500.0, 2, "svfigh")

        if M.z == 0 and M.y == 0 then
            M.audmsg = subtit.Play("misn0305.wav")
            M.second_objective = true
        end
    end

    if not M.camera_ready and M.second_objective then
        CameraReady()
        M.movie_time = GetTime() + 14.5
        M.new_unit_time = GetTime() + 7.5
        M.prop1 = BuildObject("svrecy", 2, "recy_spawn")
        M.prop2 = BuildObject("svmuf", 2, "muf_spawn")
        M.prop3 = BuildObject("svtank", 2, "tank1_spawn")
        M.prop4 = BuildObject("svtank", 2, "tank2_spawn")
        M.prop5 = BuildObject("svfigh", 2, "fighter1_spawn")
        M.guy1 = BuildObject("sssold", 2, GetPositionNear(GetPosition("guy1_spawn"), 0, 10))
        M.guy2 = BuildObject("sssold", 2, GetPositionNear(GetPosition("guy2_spawn"), 0, 10))
        M.guy3 = BuildObject("sssold", 2, GetPositionNear(GetPosition("guy1_spawn"), 0, 10))
        M.guy4 = BuildObject("sssold", 2, GetPositionNear(GetPosition("guy2_spawn"), 0, 10))

        Defend(M.prop1, 1)
        Goto(M.prop2, "tank1_spawn", 1)
        Goto(M.prop3, "that_path", 1)
        Goto(M.prop4, "cool_path", 1)
        Goto(M.prop5, "cool_path", 1)
        Goto(M.guy1, "guy_spot", 1)
        Goto(M.guy2, "guy_spot", 1)
        Goto(M.guy3, "guy_spot", 1)
        Goto(M.guy4, "guy_spot", 1)
        M.camera_ready = true
    end

    if M.camera_ready and not M.movie_over then
        CameraPath("movie_path", 175, 850, M.prop1)
        Defend(M.prop1, 1)
        M.start_movie = true
    end

    if M.camera_ready and not M.more_show and not M.movie_over then
        if M.new_unit_time < GetTime() then
            local mpos = GetPosition("muf_spawn")
            M.prop8 = BuildObject("svfigh", 2, GetPositionNear(mpos, 0, 20))
            M.prop9 = BuildObject("svfigh", 2, GetPositionNear(mpos, 0, 20))
            Goto(M.prop8, "tank2_spawn", 1)
            Goto(M.prop9, "fighter1_spawn", 1)
            M.more_show = true
        end
    end

    if M.start_movie and not M.movie_over and (CameraCancelled() or M.movie_time < GetTime()) then
        CameraFinish()
        -- Only stop subtitles if the user skipped the cinematic
        if CameraCancelled() then
            subtit.Stop()
        end
        
        -- Delay the pull out time until they actually arrive
        M.pull_out_time = 999999.0 
        M.turret_move_time = GetTime() + 15.0

        SetObjectiveOff(M.solar1)
        SetObjectiveOff(M.solar2)
        SetObjectiveOff(M.solar3)
        SetObjectiveOff(M.solar4)

        if IsAlive(M.rescue1) then
            SetObjectiveOn(M.rescue1)
            SetObjectiveName(M.rescue1, "Transport 1")
        end
        if IsAlive(M.rescue2) then
            SetObjectiveOn(M.rescue2)
            SetObjectiveName(M.rescue2, "Transport 2")
        end
        SetObjectiveOn(M.launch)
        SetObjectiveName(M.launch, "Launch Pad")

        -- Lockdown Player Recycler immediately
        if IsAlive(M.avrecycler) then
             SetCommand(M.avrecycler, 9) -- AiCommand.NO_DROPOFF
        end

        ClearObjectives()
        AddObjective("misn0311.otf", "green")
        AddObjective("misn0312.otf", "green")
        AddObjective("misn0303.otf", "white")

        --Goto(M.rescue1, "rescue_path", 1)
        --Goto(M.rescue2, "rescue_path", 1)

        Defend2(M.help1, M.rescue1, 0)
        Defend2(M.help2, M.rescue2, 0)

        M.movie_over = true
    end

    if M.movie_over and not M.remove_props then
        M.audmsg = subtit.Play("misn0306.wav")
        M.cca_delay_timer = GetTime() + 60.0 -- Set delay
        M.remove_props = true
        
    end
    
    -- MODIFIED: Check delay before deploying
    if M.remove_props and not M.cca_deployed then
        if GetTime() < M.cca_delay_timer then
             -- FORCE STOP to prevent auto-deploy
             if IsAlive(M.prop1) then Stop(M.prop1, 1) end
             if IsAlive(M.prop2) then Stop(M.prop2, 1) end
        else
            -- Order enemy production to invade base
            -- Use SetCommand for GO_TO_GEYSER (16)
            if IsAlive(M.prop1) then SetCommand(M.prop1, 16, 1) end 
            if IsAlive(M.prop2) then SetCommand(M.prop2, 16, 1) end
            
            -- Spawn attack force handled in ambush block
            RemoveObject(M.prop3)
            RemoveObject(M.prop4)
            RemoveObject(M.prop5)
            if IsAlive(M.prop8) then RemoveObject(M.prop8) end
            if IsAlive(M.prop9) then RemoveObject(M.prop9) end
            if IsAlive(M.guy1) then RemoveObject(M.guy1) end
            if IsAlive(M.guy2) then RemoveObject(M.guy2) end
            if IsAlive(M.guy3) then RemoveObject(M.guy3) end
            if IsAlive(M.guy4) then RemoveObject(M.guy4) end
            
            M.cca_deployed = true
        end
    end

    -- ... (skip APC check block as it remains same) ...

    if M.startfinishingmovie and not M.tanks_go then
        if M.new_unit_time < GetTime() then
             -- MODIFIED: Outro Swarm & Invincibility (Fixed Health Bug)
             local function PrepOutroUnit(h)
                if IsAlive(h) then
                    SetMaxHealth(h, 50000) -- Massive Health for "Invincibility"
                    SetCurHealth(h, 50000) 
                    SetWeaponMask(h, 3) -- Double Weapons
                end
             end
             
            Goto(M.prop1, "line1", 1)
            Goto(M.prop2, "line2", 1)
            Goto(M.prop3, "line3", 1)
            PrepOutroUnit(M.prop1)
            PrepOutroUnit(M.prop2)
            PrepOutroUnit(M.prop3)
            
            -- Spawn Massive Swarm
            for i=1, 10 do
                local sp = spawns[math.random(1,3)]
                local s = BuildObject("svtank", 2, GetPositionNear(GetPosition(sp), 0, 50))
                PrepOutroUnit(s)
                Goto(s, "line" .. math.random(1,3), 1)
            end
            
            M.tanks_go = true
        else
            Defend(M.prop1)
            Defend(M.prop2)
            Defend(M.prop3)
        end
    end

    -- NEW: Check if APCs have arrived at base to "load up"
    if M.movie_over and not M.apc_arrived_at_base then
        -- Increased tolerance to 150.0 to ensure trigger
        if GetDistance(M.rescue1, "apc1_spawn") < 150.0 and GetDistance(M.rescue2, "apc2_spawn") < 150.0 then
            M.apc_arrived_at_base = true
            -- Set timer to leave after loading (5 seconds)
            M.pull_out_time = GetTime() + 2.0 
        end
    end

    if M.remove_props then
        if not M.trans_underway and M.pull_out_time < GetTime() then
            -- MODIFIED: Follow path to launch pad, escorts follow transports
            Goto(M.rescue1, "rescue_path")
            Goto(M.rescue2, "rescue_path")
            Follow(M.help1, M.rescue2, 0)
            Follow(M.help2, M.rescue1, 0)
            
            -- Enable Objectives on departure
            SetObjectiveOn(M.rescue1)
            SetObjectiveOn(M.rescue2)
            -- Update existing objective instead of adding new one
            UpdateObjective("misn0303.otf", "white", 8.0, "Escort to Launch Pad") 
            
            -- Clear old objectives (Command Tower / Arrays)
            SetObjectiveOff(M.solar1)
            SetObjectiveOff(M.solar2)
            SetObjectiveOff(M.solar3)
            SetObjectiveOff(M.solar4)
            SetObjectiveOff(M.solar5)
            
            M.ambush_message_time = GetTime() + 15.0
            M.trans_underway = true
            M.rescue_move_done = true
        end
    end

    if M.remove_props then
        if not M.turret_move_done and M.turret_move_time < GetTime() then
            Retreat(M.turret1, "turret_path1")
            Retreat(M.turret2, "turret_path2")
            Retreat(M.turret3, "turret_path3")
            Retreat(M.turret4, "base")
            
            -- Spawn fighters to help turrets on Hard/Very Hard
            if exu and exu.GetDifficulty and exu.GetDifficulty() >= 2 then -- Hard+
                 -- MODIFIED: Enemy forces follow the blocking turrets
                local b1 = BuildObject("svtank", 2, "turret_path1")
                local b2 = BuildObject("svfigh", 2, "turret_path2")
                Follow(b1, M.turret1)
                Follow(b2, M.turret2)
            end

            M.turret_move_done = true
        end
        -- ... existing attack logic preserved ...
        if IsAlive(M.wave1_1) then Attack(M.wave1_1, M.rescue1, 1) end
        if IsAlive(M.wave1_2) then Attack(M.wave1_2, M.rescue1, 1) end
        if IsAlive(M.wave5_1) then Attack(M.wave5_1, M.rescue2, 1) end
        if IsAlive(M.wave5_2) then Attack(M.wave5_2, M.rescue1, 1) end
        if IsAlive(M.wave5_3) then Attack(M.wave5_3, M.rescue2, 1) end
    end

    if M.trans_underway and M.ambush_message_time < GetTime() and not M.ambush_message then
        subtit.Play("misn0315.wav")
        -- MODIFIED: Split Spawns (Recycler locked down earlier)
        
        local wsp = GetPosition("wspawn")
        local ssp = GetPosition(spawns[2])
        M.wave6_1 = BuildObject("svtank", 2, GetPositionNear(wsp, 0, 40)) -- West
        M.wave6_2 = BuildObject("svtank", 2, GetPositionNear(ssp, 0, 40)) -- South
        M.wave6_3 = BuildObject("svtank", 2, GetPositionNear(wsp, 0, 40)) 
        local w4 = BuildObject("svtank", 2, GetPositionNear(ssp, 0, 40))
        local w5 = BuildObject("svtank", 2, GetPositionNear(wsp, 0, 40))
        
        if IsAlive(M.avrecycler) then
            Attack(M.wave6_1, M.avrecycler)
            Attack(M.wave6_2, M.avrecycler)
            Attack(M.wave6_3, M.avrecycler)
            Attack(w4, M.avrecycler)
            Attack(w5, M.avrecycler)
        end
        
        M.ambush_message = true
    end

    if M.remove_props and not M.lost and not M.third_objective and
       GetDistance(M.rescue1, M.launch) < 100.0 and GetDistance(M.rescue2, M.launch) < 100.0 then
        
        subtit.Play("misn0310.wav")
        if IsAlive(M.rescue1) then SetObjectiveOff(M.rescue1) end
        if IsAlive(M.rescue2) then SetObjectiveOff(M.rescue2) end

        Follow (M.rescue1, M.launch, 1)
        Follow (M.rescue2, M.launch, 1)
        
        ClearObjectives()
        AddObjective("misn0313.otf", "green")
        AddObjective("misn0304.otf", "white")
        local p1 = spawns[math.random(1,3)]
        local p2 = spawns[math.random(1,3)]
        local p3 = spawns[math.random(1,3)]
        M.wave7_1 = BuildObject("svtank", 2, GetPositionNear(GetPosition(p1), 0, 40))
        M.wave7_2 = BuildObject("svtank", 2, GetPositionNear(GetPosition(p2), 0, 40))
        M.wave7_3 = BuildObject("svtank", 2, GetPositionNear(GetPosition(p3), 0, 40))
        Goto(M.wave7_1, "base", 1)
        Goto(M.wave7_2, "base", 1)
        Goto(M.wave7_3, "base", 1)
        M.final_check = GetTime() + 120.0
        M.third_objective = true
    end

    if not M.final_objective and not M.second_warning and M.final_check < GetTime() then
        M.final_check = GetTime() + 120.0
        ClearObjectives()
        AddObjective("misn0313.otf", "green")
        AddObjective("misn0304.otf", "white")
        subtit.Play("misn0310.wav")
        M.second_warning = true
    end

    if not M.final_objective and M.second_warning and not M.last_warning and M.final_check < GetTime() then
        M.final_check = GetTime() + 120.0
        ClearObjectives()
        AddObjective("misn0313.otf", "green")
        AddObjective("misn0304.otf", "white")
        subtit.Play("misn0310.wav")
        M.last_warning = true
    end

    if not M.final_objective and M.third_objective and CountUnitsNearObject(M.geyser, 5000.0, 2, "svtank") < 5 then
        local p4 = spawns[math.random(1,3)]
        local p5 = spawns[math.random(1,3)]
        M.wave7_4 = BuildObject("svtank", 2, GetPositionNear(GetPosition(p4), 0, 40))
        M.wave7_5 = BuildObject("svtank", 2, GetPositionNear(GetPosition(p5), 0, 40))
        Goto(M.wave7_4, "base", 1)
        Goto(M.wave7_5, "base", 1)
    end

    if M.third_objective and GetDistance(M.user, M.launch) < 100.0 and not M.lost and not M.final_objective then
        M.final_objective = true
    end

    if not M.startfinishingmovie and M.final_objective then
        if IsAlive(M.avrecycler) then RemoveObject(M.avrecycler) end
        if IsAlive(M.scav1) then RemoveObject(M.scav1) end
        if IsAlive(M.scav2) then RemoveObject(M.scav2) end
        if IsAlive(M.scav3) then RemoveObject(M.scav3) end
        if IsAlive(M.scav4) then RemoveObject(M.scav4) end
        if IsAlive(M.scav5) then RemoveObject(M.scav5) end
        if IsAlive(M.scav6) then RemoveObject(M.scav6) end
        if IsAlive(M.help1) then RemoveObject(M.help1) end
        if IsAlive(M.help2) then RemoveObject(M.help2) end
        if IsAlive(M.wave4_1) then RemoveObject(M.wave4_1) end
        if IsAlive(M.wave4_2) then RemoveObject(M.wave4_2) end
        if IsAlive(M.wave6_1) then RemoveObject(M.wave6_1) end
        if IsAlive(M.wave6_2) then RemoveObject(M.wave6_2) end
        if IsAlive(M.wave6_3) then RemoveObject(M.wave6_3) end
        if IsAlive(M.wave7_1) then RemoveObject(M.wave7_1) end
        if IsAlive(M.wave7_2) then RemoveObject(M.wave7_2) end
        if IsAlive(M.wave7_3) then RemoveObject(M.wave7_3) end
        if IsAlive(M.wave7_4) then RemoveObject(M.wave7_4) end
        if IsAlive(M.wave7_5) then RemoveObject(M.wave7_5) end

        M.clean_sweep_time = GetTime() + 14.0
        M.next_shot = GetTime() + 18.5
        M.new_unit_time = GetTime() + 2.0
        M.audmsg = subtit.Play("misn0316.wav")
        M.prop1 = BuildObject("svtank", 2, GetPositionNear(GetPosition("spawna"), 0, 40))
        M.prop2 = BuildObject("svtank", 2, GetPositionNear(GetPosition("spawnb"), 0, 40))
        M.prop3 = BuildObject("svtank", 2, GetPositionNear(GetPosition("spawnc"), 0, 40))
        CameraReady()
        M.startfinishingmovie = true
    end

    if M.startfinishingmovie and not M.camera_2 then
        CameraPath("camera_path", M.x, 3500, M.cam_geyser)
        M.x = M.x - 15
        M.camera_on = true
    end





    if M.startfinishingmovie and M.clean_sweep_time < GetTime() and not M.clean_sweep then
        M.clean_sweep = true
    end

    if M.startfinishingmovie and M.next_shot < GetTime() and not M.camera_off then
        CameraPath("inbase_path", 160, 90, M.prop1)
        M.camera_2 = true
    end

    if M.camera_2 and not M.speach2 then
        M.audmsg = subtit.Play("misn0317.wav")
        M.speach2 = true
    end

    if M.camera_2 and not M.show_tank_attack then
        -- MODIFIED: Increased distance to 80.0 to prevent softlock from traffic jams (swarm)
        -- Added fail-safe for dead prop
        if not IsAlive(M.prop1) or GetDistance(M.prop1, M.shot_geyser) < 80.0 then
            
            if IsAlive(M.prop1) then
                Attack(M.prop1, M.solar1)
            end
            if IsAlive(M.prop2) then
                Attack(M.prop2, M.solar1)
            end

            if IsAlive(M.solar1) then
                if IsAlive(M.solar2) then Damage(M.solar2, 20000) end
                if IsAlive(M.solar3) then Damage(M.solar3, 20000) end
                if IsAlive(M.solar4) then Damage(M.solar4, 20000) end
                M.kill_tower = GetTime() + 7.0
                M.show_tank_attack = true
            end
        end
    end

    if M.show_tank_attack and not M.tower_dead and M.kill_tower < GetTime() then
        if IsAlive(M.solar1) then
            Damage(M.solar1, 25000)
            M.tower_dead = true
        end
    end

    if M.tower_dead and not M.climax1 then
        Retreat(M.prop1, "climax_path1", 1)
        Retreat(M.prop2, "spawn_scrap1", 1)
        Retreat(M.prop3, "spawn_scrap1", 1)
        M.clear_debis_time = GetTime() + 6.0
        M.audmsg = subtit.Play("misn0318.wav")
        M.climax1 = true
    end

    if M.climax1 and not M.clear_debis and M.clear_debis_time < GetTime() then
        if IsAlive(M.build3) then Damage(M.build3, 20000) end
        M.prop8 = BuildObject("svtank", 2, GetPositionNear(GetPosition(M.cam_geyser), 0, 20))
        Retreat(M.prop8, "climax_path2", 1)
        M.clear_debis = true
    end

    if M.climax1 and not M.climax2 then
        if GetDistance(M.prop1, M.cam_geyser) < 100.0 then
            Retreat(M.prop1, "climax_path2", 1)
            local s_pos = GetPosition("solar_spot")
            M.prop9 = BuildObject("svfigh", 2, GetPositionNear(s_pos, 0, 20))
            M.prop0 = BuildObject("svfigh", 2, GetPositionNear(s_pos, 0, 20))
            Retreat(M.prop9, "camera_pass", 1)
            Retreat(M.prop0, "camera_pass", 1)
            if IsAlive(M.hanger) then Damage(M.hanger, 20000) end
            M.clear_debis_time = GetTime() + 3.0
            M.climax2 = true
        end
    end

    if M.climax2 and not M.last_blown and M.clear_debis_time < GetTime() then
        if IsAlive(M.box1) then Damage(M.box1, 20000) end
        if IsAlive(M.build1) then Damage(M.build1, 20000) end
        if IsAlive(M.crate1) then Damage(M.crate1, 20000) end
        if IsAlive(M.crate2) then Damage(M.crate2, 20000) end
        if IsAlive(M.crate3) then Damage(M.crate3, 20000) end

        Retreat(M.prop2, "solar_spot")
        Retreat(M.prop8, "spawn_scrap1", 1)
        M.sucker = BuildObject("abwpow", 1, GetPositionNear(GetPosition("sucker_spot"), 0, 10))
        M.last_blown = true
    end

    if M.last_blown and not M.end_shot and GetDistance(M.prop1, M.sucker) < 65.0 then
        Attack(M.prop1, M.sucker, 1)
        M.camera_off_time = GetTime() + 6.0 -- MODIFIED: Increased from 1.5s to 6.0s
        M.end_shot = true
    end

    if M.camera_on and not M.camera_off and (CameraCancelled() or M.camera_off_time < GetTime()) then
        M.startfinishingmovie = false
        CameraFinish()
        -- Only stop subtitles if the user skipped the cinematic
        if CameraCancelled() then
            subtit.Stop()
        end
        SucceedMission(0.1, "misn03w1.des")
        M.camera_off = true
    end

    if M.last_warning and M.final_check < GetTime() and not M.final_objective and not M.lost then
        FailMission(GetTime() + 1.0, "misn03f5.des")
        M.lost = true
    end

    if not M.dead1 and not M.show_tank_attack and not M.second_objective and not IsAlive(M.solar1) then
        subtit.Play("misn0302.wav")
        ClearObjectives()
        AddObjective("misn0311.otf", "red")
        AddObjective("misn0312.otf", "white")
        M.lost = true
        M.dead1 = true
        if not M.turrets_set then
            FailMission(GetTime() + 10.0, "misn03f1.des")
        else
            FailMission(GetTime() + 10.0, "misn03f2.des")
        end
    end

    if not M.dead2 and not M.tanks_go and not IsAlive(M.solar2) and not M.second_objective then
        subtit.Play("misn0303.wav")
        ClearObjectives()
        AddObjective("misn0311.otf", "red")
        AddObjective("misn0312.otf", "white")
        M.lost = true
        M.dead2 = true
        if not M.turrets_set then
            FailMission(GetTime() + 10.0, "misn03f3.des")
        else
            FailMission(GetTime() + 10.0, "misn03f3.des")
        end
    end

    if M.movie_over and not M.dead3 and not IsAlive(M.rescue1) and not M.third_objective then
        subtit.Play("misn0304.wav")
        ClearObjectives()
        AddObjective("misn0311.otf", "green")
        AddObjective("misn0312.otf", "green")
        AddObjective("misn0303.otf", "red")
        M.lost = true
        M.dead3 = true
        FailMission(GetTime() + 10.0, "misn03f4.des")
    end
    if M.movie_over and not M.dead3 and not IsAlive(M.rescue2) and not M.third_objective then
        subtit.Play("misn0304.wav")
        ClearObjectives()
        AddObjective("misn0311.otf", "green")
        AddObjective("misn0312.otf", "green")
        AddObjective("misn0303.otf", "red")
        M.lost = true
        M.dead3 = true
        FailMission(GetTime() + 10.0, "misn03f4.des")
    end

-- Local settings logic has been moved to PersistentConfig.lua
end


