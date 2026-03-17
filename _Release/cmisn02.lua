-- cmisn02.lua (Converted from Chinese02Mission.cpp)

-- Compatibility
SetLabel = SetLabel or SetLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
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
local camera_arrived = false
local camera_complete = {false, false}
local camera_ready = {false, false}
local attack3_destroyed = false
local attack5_destroyed = false
local apc_spawned = false
local apc_damaged = false
local apc_arrived = {false, false, false}
local apc_trigger1 = false
local apc_trigger2 = false
local apc_at_hangar = false
local walker_attack1 = false -- commented in C++
local walker_attack2 = false
local walker_attack3 = false
local won = false
local lost = false

-- Timers
local opening_sound_time = 99999.0
local camera_pause_time = 99999.0
local sound2_time = 99999.0
local attack5_destroyed_spawn_time = 99999.0
local attack8_time = 99999.0
local convoy_time = 99999.0
local convoy_attack1_time = 99999.0
local walker_time = 99999.0
local hangar_attack5_time = 99999.0
local hangar_attack6_time = 99999.0
local annoy_time = 99999.0

-- Handles
local user
local recycler, hangar, factory, armoury, comm_tower
local attack3 = {} -- 1-5
local attack5 = {} -- 1-5
local apc = {} -- 1-3
local walker
local convoy_intercept
local opening_sound, lose1_sound, lose2_sound, win_sound

-- Difficulty
local difficulty = 2

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

local function GetLiveApc()
    local live = {}
    for i=1,3 do
        if apc[i] and IsAlive(apc[i]) then table.insert(live, apc[i]) end
    end
    if #live == 0 then return nil end
    return live[math.random(1, #live)]
end

local function GetBase()
    local targets = {}
    if hangar and IsAlive(hangar) then table.insert(targets, hangar) end
    if recycler and IsAlive(recycler) then table.insert(targets, recycler) end
    if armoury and IsAlive(armoury) then table.insert(targets, armoury) end
    if comm_tower and IsAlive(comm_tower) then table.insert(targets, comm_tower) end
    if #targets == 0 then return user end
    return targets[math.random(1, #targets)]
end

function Update()
    user = GetPlayerHandle()
    aiCore.Update()
    
    if not start_done then
        SetScrap(1, DiffUtils.ScaleRes(30))
        SetPilot(1, DiffUtils.ScaleRes(10))
        
        EnableAllCloaking(false)
        
        recycler = GetHandle("recycler")
        hangar = GetHandle("hanger") -- C++ uses "hanger" typo
        comm_tower = GetHandle("comm_tower")
        armoury = GetHandle("armory")
        
        for i=1,5 do attack3[i] = GetHandle("attack_3_"..i) end
        for i=1,5 do attack5[i] = GetHandle("attack_5_"..i) end
        
        opening_sound_time = GetTime() + 1.0
        start_done = true
    end
    
    if won or lost then return end
    
    -- Intro
    if not camera_complete[1] then
        if not camera_ready[1] then
            camera_ready[1] = true
            CameraReady()
        end
        
        if not camera_arrived then
            camera_arrived = CameraPath("camera_start", 800, 2000, hangar)
            if camera_arrived then
                camera_pause_time = GetTime() + 2.0
            end
        elseif GetTime() > camera_pause_time then
            CameraFinish()
            camera_complete[1] = true
            ClearObjectives()
            AddObjective("ch02001.otf", "white")
            sound2_time = GetTime() + 60.0
            annoy_time = GetTime() + 120.0
            opening_sound_time = 99999.0
        end
        
        if CameraCancelled() then
            if opening_sound then StopAudioMessage(opening_sound) end
            CameraFinish()
            camera_complete[1] = true
            ClearObjectives()
            AddObjective("ch02001.otf", "white")
            sound2_time = GetTime() + 60.0
            annoy_time = GetTime() + 120.0
            opening_sound_time = 99999.0
        end
    end
    
    -- Sounds
    if GetTime() > opening_sound_time then
        opening_sound_time = 99999.0
        opening_sound = AudioMessage("ch02001.wav")
    end
    
    if GetTime() > sound2_time then
        sound2_time = 99999.0
        AudioMessage("ch02002.wav")
    end
    
    -- Annoy Waves
    if GetTime() > annoy_time then
        annoy_time = GetTime() + 120.0
        local function Sp(odf, n) for i=1, DiffUtils.ScaleEnemy(n) do local h = BuildObject(odf, 2, "annoy_1"); Hunt(h, 1) end end
        Sp("svltnk", 2); Sp("svfigh", 2)
    end
    
    -- Failure: Hangar Dead
    if not IsAlive(hangar) and not lost and not won then
        lost = true
        lose1_sound = AudioMessage("ch02006.wav")
    end
    
    if lose1_sound and IsAudioMessageDone(lose1_sound) then
        lose1_sound = nil
        FailMission(GetTime() + 1.0, "ch02lsea.des")
    end
    
    -- Failure: APCs lost
    if apc_spawned and not lost and not won then
        local dead = 0
        for i=1,3 do
            if not IsAlive(apc[i]) and not apc_arrived[i] then dead = dead + 1 end
        end
        if dead >= 2 then
            lost = true
            lose2_sound = AudioMessage("ch02006.wav")
        end
    end
    
    if lose2_sound and IsAudioMessageDone(lose2_sound) then
        lose2_sound = nil
        FailMission(GetTime() + 1.0, "ch02lseb.des")
    end
    
    -- Group Attack 3
    if not attack3_destroyed then
        attack3_destroyed = true
        for i=1,5 do if IsAlive(attack3[i]) then attack3_destroyed = false; break end end
        if attack3_destroyed then
            local h = BuildObject("svartl", 2, "hanger_attack_2")
            Attack(h, hangar, 1)
        end
    end
    
    -- Group Attack 5
    if not attack5_destroyed then
        attack5_destroyed = true
        for i=1,5 do if IsAlive(attack5[i]) then attack5_destroyed = false; break end end
        if attack5_destroyed then
            attack5_destroyed_spawn_time = GetTime() + 60.0
        end
    end
    
    if GetTime() > attack5_destroyed_spawn_time then
        attack5_destroyed_spawn_time = 99999.0
        local function Sp6(odf, n) for i=1, DiffUtils.ScaleEnemy(n) do local h = BuildObject(odf, 2, "attack_6"); Goto(h, "attack_6_path", 1) end end
        Sp6("svfigh", 3); Sp6("svtank", 3); Sp6("svwalk", 3)
        
        local function Sp7(odf, n) for i=1, DiffUtils.ScaleEnemy(n) do local h = BuildObject(odf, 2, "attack_7"); Goto(h, GetBase(), 1) end end
        Sp7("svfigh", 3); Sp7("svtank", 3); Sp7("svwalk", 3)
        
        local h = BuildObject("svhraz", 2, "hanger_attack_3"); Attack(h, hangar, 1)
        h = BuildObject("svhraz", 2, "hanger_attack_3"); Attack(h, hangar, 1)
        
        walker_time = GetTime() + 240.0
    end
    
    -- Walker Phase
    if GetTime() > walker_time then
        walker_time = 99999.0
        walker = BuildObject("svwalk", 1, "walker_spawn") -- C++ uses team 0 but sets to 1 at end? briefing says escort.
        SetObjectiveOn(walker)
        SetPerceivedTeam(walker, 1)
        Retreat(walker, "walker_path")
        AudioMessage("ch02007.wav")
        hangar_attack5_time = GetTime() + 10.0
        attack8_time = GetTime() + 300.0
        
        ClearObjectives()
        AddObjective("ch02001.otf", "white")
        AddObjective("ch02003.otf", "white")
    end
    
    if walker and IsAlive(walker) then
        if not walker_attack2 and GetDistance(walker, "walker_attack_2") < 200.0 then
            walker_attack2 = true
            local function Sp(odf, n) for i=1, DiffUtils.ScaleEnemy(n) do local h = BuildObject(odf, 2, "walker_attack_2"); Attack(h, walker, 1) end end
            Sp("svfigh", 2); Sp("svltnk", 2); Sp("svtank", 2)
        end
        
        if not walker_attack3 and GetDistance(walker, "walker_attack_3") < 200.0 then
            walker_attack3 = true
            local function Sp(odf, n) for i=1, DiffUtils.ScaleEnemy(n) do local h = BuildObject(odf, 2, "walker_attack_3"); Attack(h, walker, 1) end end
            Sp("svltnk", 2); Sp("svtank", 2)
        end
        
        -- isAtEndOfPath check
        if GetDistance(walker, "walker_path") < 50.0 then
           -- Check if at last point? Hard without point access in simple loop.
           -- But Goto stops at end point.
           SetTeamNum(walker, 1)
           Recycle(walker)
           walker = nil
           AudioMessage("ch02008.wav")
        end
    end
    
    if walker and not IsAlive(walker) and not lost and not won then
        lost = true
        FailMission(GetTime() + 1.0, "ch02lsec.des")
    end
    
    -- Hangar Defense Escalation
    if GetTime() > hangar_attack5_time then
        hangar_attack5_time = 99999.0
        local h = BuildObject("svartl", 2, "hanger_attack_5")
        Attack(h, hangar, 1)
    end
    
    -- Attack 8 & Convoy Trigger
    if GetTime() > attack8_time then
        attack8_time = 99999.0
        local function Sp(odf, n) for i=1, DiffUtils.ScaleEnemy(n) do local h = BuildObject(odf, 2, "attack_8"); Goto(h, GetBase(), 1) end end
        Sp("svtank", 3); Sp("svwalk", 4)
        convoy_time = GetTime() + 270.0
    end
    
    -- Convoy Spawn
    if GetTime() > convoy_time then
        convoy_time = 99999.0
        AudioMessage("ch02003.wav")
        apc_spawned = true
        for i=1,3 do
            apc[i] = BuildObject("cvapcb", 1, "convoy_units")
            Goto(apc[i], "convoy_path")
            SetObjectiveOn(apc[i])
            local h = BuildObject("cvfighc", 1, "convoy_defend")
            Defend2(h, apc[i], 1)
            h = BuildObject("cvfighc", 1, "convoy_defend")
            Defend2(h, apc[i], 1)
        end
        convoy_attack1_time = GetTime() + 60.0
        hangar_attack6_time = GetTime() + 300.0
    end
    
    if GetTime() > hangar_attack6_time then
        hangar_attack6_time = 99999.0
        for i=1,2 do local h = BuildObject("svartl", 2, "hanger_attack_6"); Attack(h, hangar, 1) end
    end
    
    if GetTime() > convoy_attack1_time then
        convoy_attack1_time = 99999.0
        local live = GetLiveApc()
        if live then
            for i=1,4 do local h = BuildObject("svfigh", 2, "convoy_attack_1"); Goto(h, live, 1) end
            for i=2,8 do local h = BuildObject("svartl", 2, "convoy_attack_"..i); Goto(h, live, 1) end
            local h = BuildObject("svartl", 2, "convoy_attack_9"); Goto(h, live, 1)
        end
    end
    
    -- Convoy Health / Nav
    if apc_spawned and not apc_damaged then
        for i=1,3 do
            if apc[i] and IsAlive(apc[i]) and GetHealth(apc[i]) < 1.0 then
                apc_damaged = true
                break
            end
        end
        if apc_damaged then
            AudioMessage("ch02004.wav")
            convoy_intercept = BuildObject("cpcamr", 1, "nav_convoy")
            SetName(convoy_intercept, "Convoy Intercept")
            ClearObjectives()
            AddObjective("ch02001.otf", "white")
            AddObjective("ch02002.otf", "white")
        end
    end
    
    -- Trrigers
    if apc_spawned and not apc_trigger1 then
        for i=1,3 do
            if apc[i] and IsAlive(apc[i]) and GetDistance(apc[i], "trigger_point_1") < 30.0 then
                apc_trigger1 = true
                break
            end
        end
        if apc_trigger1 then
            local live = GetLiveApc()
            if live then for i=1,6 do local h = BuildObject("svfigh", 2, "convoy_attack_10"); Goto(h, live, 1) end end
            for i=1,3 do local h = BuildObject("svhraz", 2, "hanger_attack_3"); Attack(h, hangar, 1) end
        end
    end
    
    if apc_spawned and not apc_trigger2 then
        for i=1,3 do
            if apc[i] and IsAlive(apc[i]) and GetDistance(apc[i], "trigger_point_2") < 40.0 then
                apc_trigger2 = true
                break
            end
        end
        if apc_trigger2 then
            local function SpAtk(odf, loc) local h = BuildObject(odf, 2, loc); Goto(h, GetBase(), 1) end
            for i=1,4 do SpAtk("svtank", "attack_9") end
            for i=1,2 do SpAtk("svltnk", "attack_9") end
            for i=1,2 do SpAtk("svtank", "attack_10") end
            for i=1,2 do SpAtk("svltnk", "attack_10") end
            for i=1,2 do SpAtk("svrckt", "attack_10") end
            for i=1,3 do local h = BuildObject("svhraz", 2, "hanger_attack_4"); Attack(h, hangar, 1) end
        end
    end
    
    -- Finale
    if apc_spawned and not apc_at_hangar then
        for i=1,3 do
            if apc[i] and IsAlive(apc[i]) and GetDistance(apc[i], hangar) < 30.0 then
                apc_at_hangar = true
                apc_arrived[i] = true
                break
            end
        end
        if apc_at_hangar then
            StartCockpitTimer(30)
            won = true
            win_sound = AudioMessage("ch02005.wav")
        end
    end
    
    if win_sound and IsAudioMessageDone(win_sound) then
        win_sound = nil
        SucceedMission(GetTime() + 1.0, "ch02win.des")
    end
end

