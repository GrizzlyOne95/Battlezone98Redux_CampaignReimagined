-- BlackDog01 Mission Script
-- Restores "Dual Scavenger" Defense Logic

local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
local exu = require("exu")
local aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")

-- Helper for AI
local function SetupAI()
    DiffUtils.SetupTeams(aiCore.Factions.BDOG, aiCore.Factions.CCA, 2)
end

-- Variables
local start_done = false
local objective1_complete = false
local objective2_complete = false
local objective3_complete = false
local camera_ready = false
local camera_complete = {false, false}
local scavengers_created = false
local sound_started = {}
local sound_played = {}
local beacon_spawned1 = false
local beacon_spawned2 = false
local ambush_retreat = false
local wave1_ready = false
local wave2_ready = false
local game_over = false

-- Timers
local wave2_delay = 999999.0
local delay_time1 = 999999.0
local delay_time2 = 999999.0
local delay_time3 = 999999.0
local sound6_time = 999999.9
local sound7_time = 999999.9
local sound8_time = 999999.9
local sound9_time = 999999.9

-- Handles
local user, recycler, wingman1, wingman2
local scavengers = {nil, nil} -- Array for dual scavengers
local badguy1_ambush, badguy2_ambush
local badguy1_wave1, badguy2_wave1, badguy3_wave1, badguy4_wave1
local badguy1_wave2, badguy2_wave2, badguy3_wave2, badguy4_wave2, badguy5_wave2
local beacon

local difficulty = 2

function Start()
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    start_done = false
    -- Initialize Sound Arrays
    for i=0, 4 do sound_started[i] = false; sound_played[i] = false end
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then aiCore.AddObject(h) end
    
    -- Capture Scavengers
    if (not scavengers_created) and IsOdf(h, "bvscav") and (team == 1) then
        if not scavengers[1] then scavengers[1] = h
        elseif not scavengers[2] then scavengers[2] = h end
    end
end

function DeleteObject(h)
end

function Update()
    user = GetPlayerHandle()
    aiCore.Update()
    
    if not start_done then
        SetScrap(1, DiffUtils.ScaleRes(12))
        SetPilot(1, 10)
        
        recycler = GetHandle("recycler")
        wingman1 = GetHandle("wingman1_bobcat")
        wingman2 = GetHandle("wingman2_bobcat")
        Goto(recycler, "start_path_recycler")
        Goto(wingman1, "start_path_wingman1")
        Goto(wingman2, "start_path_wingman2")
        
        AudioMessage("bd01001.wav")
        ClearObjectives()
        AddObjective("bd01001.otf", "white")
        
        start_done = true
    end
    
    -- Recycler Death Check
    if IsAlive(recycler) and (GetHealth(recycler) <= 0) and (not sound_started[3]) then
        sound_started[3] = true
        AudioMessage("bd01005.wav")
        FailMission(GetTime() + 4.0, "bd01lsea.des")
    end
    
    -- Camera Intro
    if not camera_complete[1] then
        if not camera_ready then
            CameraReady()
            camera_ready = true
        end
        local arrived = CameraPath("camera_start_arc", 3000, 3500, recycler)
        if CameraCancelled() or arrived then
            CameraFinish()
            camera_complete[1] = true
            camera_ready = false
            sound8_time = GetTime() + 90.0
        end
    end
    
    -- Deploy Reminders
    if (sound8_time < GetTime()) then
        sound8_time = 999999.0
        -- Check logic: isDeployed(recycler)? Lua doesn't have isDeployed.
        -- Assuming if scavengers created, it's deployed.
        if (not scavengers_created) then AudioMessage("bd01008.wav") end
    end
    
    -- Scavenger Creation Check
    if not scavengers_created then
        -- We detect scavengers in AddObject.
        -- But allow logic flow: if we have 2 scavengers (Restored Logic!)
        local s1 = scavengers[1]; local s2 = scavengers[2]
        
        -- Modified condition: Require 2 scavengers if possible, or loosen?
        -- C++ just checked "isDeployed" then set scavengersCreated.
        -- We'll check if any scavengers exist.
        if IsAlive(s1) or IsAlive(s2) then
            scavengers_created = true
            delay_time1 = GetTime() + 20.0
            objective1_complete = true
            
            -- Objective update
            ClearObjectives()
            AddObjective("bd01001.otf", "green")
            AddObjective("bd01001.otf", "white") -- ? Logic in C++ resetObjectives calls same OTF
        end
    end
    
    if not scavengers_created then return end
    if GetTime() < delay_time1 then return end
    
    -- Ambush Phase
    if not beacon_spawned1 then
        beacon_spawned1 = true
        beacon = BuildObject("apcamr", 1, "spawn_nav_beacon")
        SetLabel(beacon, "Nav Alpha")
        
        badguy1_ambush = BuildObject("cvfigh", 2, "spawn_attack_ambush")
        Patrol(badguy1_ambush, "ambush_patrol_path")
        -- Cloak(badguy1_ambush) -- Lua: SetCloaked?
        
        badguy2_ambush = BuildObject("cvfigh", 2, "spawn_attack_ambush")
        Patrol(badguy2_ambush, "ambush_patrol_path")
        -- Cloak?
    end
    
    -- Play Audio 2
    if not sound_started[0] then
        AudioMessage("bd01002.wav")
        sound_started[0] = true
    end
    
    if not beacon_spawned2 then
        beacon_spawned2 = true
        SetObjectiveOn(beacon)
        ClearObjectives()
        AddObjective("bd01001.otf", "green")
        AddObjective("bd01002.otf", "white")
        sound6_time = GetTime() + 60.0
    end
    
    -- Objective 2 Config
    if (sound6_time < GetTime() + 60.0) or (sound7_time < GetTime() + 30.0) then
        local dist = GetDistance(user, beacon) -- Simplified logic
        -- C++: GetNearestUnitOnTeam... dist < 100.
        if dist < 100.0 then
            objective2_complete = true
            sound6_time = 999999.0
            sound7_time = 999999.0
            ClearObjectives()
            AddObjective("bd01001.otf", "green")
            AddObjective("bd01002.otf", "green")
            AddObjective("bd01003.otf", "white")
        end
    end
    
    -- Ambush Retreat
    if not ambush_retreat then
        if (not IsAlive(badguy1_ambush)) or (not IsAlive(badguy2_ambush)) then
            -- One dead, retreat the other
            if IsAlive(badguy1_ambush) then Retreat(badguy1_ambush, "ambush_retreat_path"); end
            if IsAlive(badguy2_ambush) then Retreat(badguy2_ambush, "ambush_retreat_path"); end
            delay_time2 = GetTime() + 5.0
            ambush_retreat = true
        end
    end
    
    if not ambush_retreat then return end
    if GetTime() < delay_time2 then return end
    
    -- Wave 1
    if not wave1_ready then
        wave1_ready = true
        badguy1_wave1 = BuildObject("cvfigh", 2, "spawn_attack_wave1")
        Attack(badguy1_wave1, recycler)
        badguy2_wave1 = BuildObject("cvfigh", 2, "spawn_attack_wave1")
        Attack(badguy2_wave1, recycler)
        
        -- Double Scavenger Threat: Attack Scavengers specifically?
        -- C++ attacked Recycler. But now we have Dual Scavengers.
        -- Let's make them split targets!
        if IsAlive(scavengers[1]) then Attack(badguy1_wave1, scavengers[1]) end
        if IsAlive(scavengers[2]) then Attack(badguy2_wave1, scavengers[2]) end
        
        wave2_delay = GetTime() + 60.0
    end
    
    -- Wave 1 Reinforcements
    if not camera_complete[2] then
        if not camera_ready then
            CameraReady()
            camera_ready = true
            AudioMessage("bd01003.wav")
        end
        local arrived = CameraPath("camera_attack_view", 2000, 1000, badguy1_wave1)
        if CameraCancelled() or arrived then
            CameraFinish()
            camera_complete[2] = true
            camera_ready = false
            
            badguy3_wave1 = BuildObject("cvfigh", 2, "spawn_attack_wave1a")
            Attack(badguy3_wave1, recycler)
            badguy4_wave1 = BuildObject("cvfigh", 2, "spawn_attack_wave1a")
            Attack(badguy4_wave1, recycler)
        end
    end
    
    if GetTime() < wave2_delay then return end
    
    -- Wave 2
    if not wave2_ready then
        wave2_ready = true
        badguy1_wave2 = BuildObject("cvfigh", 2, "spawn_attack_wave2"); Attack(badguy1_wave2, recycler)
        badguy2_wave2 = BuildObject("cvfigh", 2, "spawn_attack_wave2"); Attack(badguy2_wave2, recycler)
        badguy3_wave2 = BuildObject("cvltnk", 2, "spawn_attack_wave2"); Attack(badguy3_wave2, recycler)
        badguy4_wave2 = BuildObject("cvfigh", 2, "spawn_attack_wave2a"); Attack(badguy4_wave2, recycler)
        badguy5_wave2 = BuildObject("cvfigh", 2, "spawn_attack_wave2a"); Attack(badguy5_wave2, recycler)
        
        -- Target Scavengers with Light Tank
        if IsAlive(scavengers[1]) then Attack(badguy3_wave2, scavengers[1]) end
    end
    
    -- Win Condition
    local all_bad = {badguy1_wave1, badguy2_wave1, badguy3_wave1, badguy4_wave1,
                     badguy1_wave2, badguy2_wave2, badguy3_wave2, badguy4_wave2, badguy5_wave2,
                     badguy1_ambush, badguy2_ambush}
    local all_dead = true
    for _, h in ipairs(all_bad) do if IsAlive(h) then all_dead = false; break end end
    
    if all_dead and (not sound_started[2]) then
        sound_started[2] = true
        AudioMessage("bd01004.wav")
        objective3_complete = true
        SucceedMission(GetTime() + 4.0, "bd01win.des")
    end
end

