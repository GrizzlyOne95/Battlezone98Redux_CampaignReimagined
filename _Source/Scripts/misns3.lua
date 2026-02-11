-- Misns3 Mission Script (Converted from Misns3Mission.cpp)

-- Compatibility for 1.5
SetLabel = SetLabel or SettLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
local exu = require("exu")
local aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")

-- Helper for AI
local function SetupAI()
    DiffUtils.SetupTeams(aiCore.Factions.CCA, aiCore.Factions.NSDF, 2)
end

-- Variables
local missionstart = false
local missionwon = false
local missionfail = false
local newobjective = false
local recyclerdestroyed = false
local bdspawned = false
local bdspawned2 = false
local economy1 = false
local economy2 = false
local economy3 = false
local economy4 = false
local unit1spawned = false
local unit2spawned = false
local unit3spawned = false
local unit4spawned = false
local plea1 = false
local plea2 = false
local plea3 = false
local warn1 = false
local warn2 = false
local minefield1 = false
local minefield2 = false
local minefield3 = false
local patrolspawned = false
local mark1 = false
local play = false

-- Timers
local withdraw = 99999999.0
local help1 = 99999999.0
local help2 = 99999999.0
local help3 = 99999999.0
local Checkdist = 99999999.0
local Checkdist2 = 99999999.0
local Checkalive = 99999999.0

-- Handles
local player, avrec
local bd1, bd2, bd3, bd4, bd5 -- Initial defense wave
local bd50, bd60, bd70, bd80 -- Convoy leaders
local bd51, bd52, bd61, bd62, bd71, bd72, bd81, bd82 -- Convoy followers
local bomb1, bomb2, bomb3, bomb4
local pat1, pat2
local cam1, cam2

-- Config
local difficulty = 2

function Start()
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    
    player = GetPlayerHandle()
    missionstart = false
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then
        aiCore.AddObject(h)
    end
    -- Unit Turbo based on difficulty
    if exu and exu.SetUnitTurbo and IsCraft(h) then
        if team ~= 0 then
             if difficulty >= 3 then exu.SetUnitTurbo(h, true) end
        end
    end
end

function DeleteObject(h)
end

function Update()
    player = GetPlayerHandle()
    aiCore.Update()
    
    if not missionstart then
        AudioMessage("misns301.wav")
        newobjective = true
        missionstart = true
        
        avrec = GetHandle("avrecy1_recycler")
        
        withdraw = GetTime() + DiffUtils.ScaleTimer(600.0)
        help1 = GetTime() + DiffUtils.ScaleTimer(120.0)
        help2 = GetTime() + DiffUtils.ScaleTimer(280.0)
        help3 = GetTime() + DiffUtils.ScaleTimer(380.0)
        Checkdist = GetTime() + 5.0
        Checkdist2 = GetTime() + 5.0
        Checkalive = GetTime() + 15.0
        
        bomb1 = GetHandle("bomb1")
        bomb2 = GetHandle("bomb2")
        bomb3 = GetHandle("bomb3")
        bomb4 = GetHandle("bomb4")
        
        cam1 = GetHandle("basenav")
        if IsAlive(cam1) then SetLabel(cam1, "Home Base") end
        
        cam2 = GetHandle("avrecy") -- Is this the recycler or a nav near it? C++ implies a handle distinct from avrec usually
        if IsAlive(cam2) then SetLabel(cam2, "Black Dog Outpost") end
    end
    
    -- Objective Logic
    if newobjective then
        ClearObjectives()
        if recyclerdestroyed then
            AddObjective("misns302.otf", "white") -- Return home
            AddObjective("misns301.otf", "green") -- Destroy Rec (Done)
        else
            AddObjective("misns301.otf", "white") -- Destroy Rec
        end
        
        if missionwon then
            AddObjective("misns302.otf", "green")
        end
        newobjective = false
    end
    
    -- Audio Pleas
    if (help1 < GetTime()) and (not plea1) and (not recyclerdestroyed) then AudioMessage("misns307.wav"); plea1 = true end
    if (help2 < GetTime()) and (not plea2) and (not recyclerdestroyed) then AudioMessage("misns308.wav"); plea2 = true end
    if (help3 < GetTime()) and (not plea3) and (not recyclerdestroyed) then AudioMessage("misns309.wav"); plea3 = true end
    
    -- Base Defense Spawn (Infinite Wave)
    if IsAlive(avrec) and (GetDistance(player, "bdspawntrig") < 200.0) and (not bdspawned) then
        bd1 = BuildObject("avtank", 2, "bdspawn1")
        bd2 = BuildObject("avtank", 2, "bdspawn1")
        bd3 = BuildObject("avtank", 2, "bdspawn1")
        bd4 = BuildObject("avfigh", 2, "bdspawn1")
        bd5 = BuildObject("avfigh", 2, "bdspawn1")
        
        Attack(bd1, player)
        Attack(bd2, player)
        Attack(bd3, player)
        Attack(bd4, player)
        Attack(bd5, player)
        
        bdspawned = true
        AudioMessage("misns310.wav")
    end
    
    -- Infinite Wave Respawn Logic
    if bdspawned and (Checkalive < GetTime()) then
        -- Re-issue attacks if alive (C++ does this every check)
        if IsAlive(bd1) then Attack(bd1, player) end
        if IsAlive(bd2) then Attack(bd2, player) end
        if IsAlive(bd3) then Attack(bd3, player) end
        if IsAlive(bd4) then Attack(bd4, player) end
        if IsAlive(bd5) then Attack(bd5, player) end
        
        -- Respawn if ALL dead
        if (not IsAlive(bd1)) and (not IsAlive(bd2)) and (not IsAlive(bd3)) and (not IsAlive(bd4)) and (not IsAlive(bd5)) then
            bd1 = BuildObject("avtank", 2, "bdspawn1")
            bd2 = BuildObject("avtank", 2, "bdspawn1")
            bd3 = BuildObject("avtank", 2, "bdspawn1")
            bd4 = BuildObject("avfigh", 2, "bdspawn1")
            bd5 = BuildObject("avfigh", 2, "bdspawn1")
            -- Attack commands will follow on next loop tick
        end
        Checkalive = GetTime() + DiffUtils.ScaleTimer(8.0)
    end
    
    -- Recycler Destruction / Convoy Trigger
    if (not IsAlive(avrec)) and (not recyclerdestroyed) then
        AudioMessage("misns302.wav")
        if not bdspawned2 then
            bd50 = BuildObject("avtank", 2, "bdspawn1"); Goto(bd50, "bdpath1")
            bd60 = BuildObject("avfigh", 2, "bdspawn1"); Goto(bd60, "bdpath2")
            bd70 = BuildObject("avfigh", 2, "bdspawn1"); Goto(bd70, "bdpath3")
            bd80 = BuildObject("avtank", 2, "bdspawn1"); Goto(bd80, "bdpath4")
            
            bdspawned2 = true
            bdspawned = false -- Stop infinite wave logic? C++ sets this false.
        end
        economy1 = true; economy2 = true; economy3 = true; economy4 = true
        recyclerdestroyed = true
        newobjective = true
    end
    
    -- Convoy Followers Spawn Logic
    if economy1 and (not unit1spawned) and IsAlive(bd50) and (GetDistance(player, bd50) < 410.0) then
        bd51 = BuildObject("avtank", 2, bd50); Follow(bd51, bd50)
        bd52 = BuildObject("avtank", 2, bd50); Follow(bd52, bd50)
        unit1spawned = true
    end
    if economy2 and (not unit2spawned) and IsAlive(bd60) and (GetDistance(player, bd60) < 410.0) then
        bd61 = BuildObject("avfigh", 2, bd60); Follow(bd61, bd60)
        bd62 = BuildObject("avfigh", 2, bd60); Follow(bd62, bd60)
        unit2spawned = true
    end
    if economy3 and (not unit3spawned) and IsAlive(bd70) and (GetDistance(player, bd70) < 410.0) then
        bd71 = BuildObject("avfigh", 2, bd70); Follow(bd71, bd70)
        bd72 = BuildObject("avtank", 2, bd70); Follow(bd72, bd70)
        unit3spawned = true
    end
    if economy4 and (not unit4spawned) and IsAlive(bd80) and (GetDistance(player, bd80) < 410.0) then
        bd81 = BuildObject("avtank", 2, bd80); Follow(bd81, bd80)
        bd82 = BuildObject("avtank", 2, bd80); Follow(bd82, bd80)
        unit4spawned = true
    end
    
    -- Win Condition
    if (GetDistance(player, "homesweethome") < 200.0) and (not missionwon) and recyclerdestroyed then
        AudioMessage("misns303.wav")
        missionwon = true
        SucceedMission(GetTime(), "misns3w1.des")
    end
    
    -- Lose Conditions
    -- Time Limit
    if (withdraw < GetTime()) and (not recyclerdestroyed) and (not missionfail) then
        AudioMessage("misns304.wav")
        missionfail = true
        FailMission(GetTime(), "misns3l1.des")
    end
    
    -- Restricted Zones
    if (GetDistance(player, "don'tgohere") < 50.0) and (not warn1) and (not recyclerdestroyed) then
        AudioMessage("misns305.wav"); warn1 = true
    end
    if (GetDistance(player, "iwarnedyou") < 50.0) and (not warn2) and (not recyclerdestroyed) then
        AudioMessage("misns306.wav"); warn2 = true
        FailMission(GetTime(), "misns3l2.des")
    end
    
    -- Patrol Logic
    if (not patrolspawned) and (not bdspawned) and IsAlive(avrec) and (Checkdist < GetTime()) then
        local trig1 = false
        -- C++ checks all Bombs + Player vs patroltrig1
        -- Lua helper function?
        local function InTrig(pt)
            if GetDistance(player, pt) < 100.0 then return true end
            if IsAlive(bomb1) and GetDistance(bomb1, pt) < 100.0 then return true end
            if IsAlive(bomb2) and GetDistance(bomb2, pt) < 100.0 then return true end
            if IsAlive(bomb3) and GetDistance(bomb3, pt) < 100.0 then return true end
            if IsAlive(bomb4) and GetDistance(bomb4, pt) < 100.0 then return true end
            return false
        end
        
        if InTrig("patroltrig1") then
            pat1 = BuildObject("bvraz", 2, "patrolspawn1"); Goto(pat1, "patrolpath1"); SetIndependence(pat1, 0)
            pat2 = BuildObject("bvraz", 2, "patrolspawn1"); Goto(pat2, "patrolpath1"); SetIndependence(pat2, 0)
            AudioMessage("misns219.wav")
            patrolspawned = true
        end
        if InTrig("patroltrig2") then
            pat1 = BuildObject("bvraz", 2, "patrolspawn2"); Goto(pat1, "patrolpath2"); SetIndependence(pat1, 0)
            pat2 = BuildObject("bvraz", 2, "patrolspawn2"); Goto(pat2, "patrolpath2"); SetIndependence(pat2, 0)
            AudioMessage("misns219.wav")
            patrolspawned = true
        end
        Checkdist = GetTime() + 3.0
    end
    
    -- Patrol Ambush / Mark1
    if (not mark1) and patrolspawned and (not bdspawned) and (Checkdist2 < GetTime()) then
        -- GetNearestEnemy calls in C++: GetNearestEnemy(pat1)
        -- We can mimic using GetNearestVehicle(..., enemyTeam)
        -- Actually, usually patrols attack player.
        local enemy1 = GetNearestEnemy(pat1)
        local enemy2 = GetNearestEnemy(pat2)
        
        local triggered = false
        if IsAlive(enemy1) and (GetDistance(pat1, enemy1) < 180.0) then
            bdspawned = true -- Sets this flag true? C++ logic reuses this flag to stop patrols logic?
            Attack(pat1, enemy1); Attack(pat2, enemy1)
            play = true
        end
        if IsAlive(enemy2) and (GetDistance(pat2, enemy2) < 180.0) then
            bdspawned = true
            Attack(pat2, enemy2); Attack(pat1, enemy2)
            play = true
        end
        
        if play and (not mark1) then
            AudioMessage("misns220.wav")
            mark1 = true
        end
        Checkdist2 = GetTime() + 3.0
    end
    
    -- Minefields
    if (not minefield1) and ((GetDistance(player, "minetrig1") < 200.0) or (GetDistance(player, "minetrig1b") < 200.0)) then
        for i=1, 11 do BuildObject("proxmine", 2, "path_"..i) end
        minefield1 = true
    end
    if (not minefield2) and ((GetDistance(player, "minetrig2") < 200.0) or (GetDistance(player, "minetrig2b") < 200.0)) then
        for i=12, 22 do BuildObject("proxmine", 2, "path_"..i) end
        minefield2 = true
    end
    if (not minefield3) and ((GetDistance(player, "minetrig3") < 200.0) or (GetDistance(player, "minetrig3b") < 200.0)) then
        for i=23, 34 do BuildObject("proxmine", 2, "path_"..i) end
        minefield3 = true
    end
end

