-- Misn16 Mission Script (Converted from Misn16Mission.cpp)

-- Compatibility for 1.5
SetLabel = SetLabel or SetLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
local exu = require("exu")
local aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")

-- Helper for AI
local function SetupAI()
    DiffUtils.SetupTeams(aiCore.Factions.NSDF, aiCore.Factions.CCA, 2)
end

-- Variables
local counter = false
local start_done = false
local rcam = false
local won = false
local lost = false
local camera1 = false

-- Timers
local next_reinforcement = 99999.0
local rcam_time = 99999.0
local start_time = 99999.0
local alien_wave = 99999.0
local counter_strike2 = 99999.0
local wave_gap = 150.0
local cam_time1 = 99999.0
local alien_wave1 = 99999.0
local finish_cam = 99999.0

-- Handles
local base1, base2
local newbie -- Latest reinforcement for camera tracking
local recy, muf
local cam1, cam2, cam3, cam4
local sat1, sat2, sat3
local tow1, tow2, tow3, tow4

local rtype = 0
local rcount = 0
local difficulty = 2

function Start()
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    
    start_done = false
    camera1 = false
    rcount = 0
    wave_gap = 150.0
end

local function SendToAttack(h)
    if not IsAlive(h) then return end
    -- Randomly attack base1 or base2 if Team 1 combat unit
    local target = base1
    if math.random(0, 1) == 1 then target = base2 end
    
    if IsAlive(target) then
        Attack(h, target)
        newbie = h -- Track for cinematics
    else
        -- If random target dead, try the other
        if IsAlive(base1) then Attack(h, base1); newbie = h
        elseif IsAlive(base2) then Attack(h, base2); newbie = h end
    end
end

function AddObject(h)
    local team = GetTeamNum(h)
    
    if team == 1 then
        local odf = GetOdf(h); if odf then odf = string.gsub(odf, "%z", "") end
        if odf == "svtank" or odf == "svturr" or odf == "svfigh" or odf == "svwalk" then
            SendToAttack(h)
        elseif odf == "svscav" or odf == "svhaul" then
            -- Non-combatants just Goto? C++ says Goto.
            local target = base1
            if math.random(0,1) == 1 then target = base2 end
            if IsAlive(target) then Goto(h, target); newbie = h
            elseif IsAlive(base1) then Goto(h, base1); newbie = h
            elseif IsAlive(base2) then Goto(h, base2); newbie = h end
        end
    end
    
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
    local player = GetPlayerHandle()
    aiCore.Update()
    
    if not start_done then
        AudioMessage("misn1601.wav")
        AudioMessage("misn1602.wav")
        
        recy = GetHandle("avrecy0_recycler")
        
        next_reinforcement = GetTime() + DiffUtils.ScaleTimer(120.0)
        rtype = math.random(1, 2) -- Initial logic: rand()%2 + 1
        
        base1 = GetHandle("alien_hq")
        base2 = GetHandle("alien_hangar")
        
        SetScrap(1, DiffUtils.ScaleRes(50))
        SetAIP("misn16.aip")
        
        ClearObjectives()
        AddObjective("misn1601.otf", "white")
        
        alien_wave = GetTime() + DiffUtils.ScaleTimer(60.0)
        alien_wave1 = GetTime() + DiffUtils.ScaleTimer(90.0)
        
        cam1 = GetHandle("apcamr12_camerapod")
        cam2 = GetHandle("apcamr15_camerapod")
        cam3 = GetHandle("apcamr13_camerapod")
        cam4 = GetHandle("apcamr11_camerapod")
        
        if cam1 then SetObjectiveName(cam1, "NW Geyser") end
        if cam2 then SetObjectiveName(cam2, "Foothill Geysers") end
        if cam3 then SetObjectiveName(cam3, "Geyser Site") end
        if cam4 then SetObjectiveName(cam4, "Alien HQ") end
        
        tow1 = GetHandle("sbtowe0_turret")
        tow2 = GetHandle("sbtowe1_turret")
        tow3 = GetHandle("sbtowe2_turret")
        tow4 = GetHandle("sbtowe3_turret")
        
        sat1 = GetHandle("hvsat0_wingman")
        sat2 = GetHandle("hvsat1_wingman")
        sat3 = GetHandle("hvsat2_wingman")
        
        local sats = {sat1, sat2, sat3}
        for _, s in ipairs(sats) do if IsAlive(s) then Defend(s) end end
        
        muf = GetHandle("avmuf26_factory")
        
        camera1 = true
        cam_time1 = GetTime() + 20.0
        CameraReady()
        
        start_done = true
    end
    
    -- Intro Camera
    if camera1 then
        CameraPath("camera_path1", 4000, 500, base2)
    end
    
    if camera1 and (CameraCancelled() or (GetTime() > cam_time1)) then -- Audio check removed for simplicity
        camera1 = false
        CameraFinish()
    end
    
    -- Reinforcements
    if GetTime() > next_reinforcement then
        rcount = rcount + 1
        if rcount < 10 then
            if rtype == 1 then
                AudioMessage("misn1603.wav")
                BuildObject("svfigh", 1, "starta"); BuildObject("svhaul", 1, "starta2"); BuildObject("svhaul", 1, "starta3")
            elseif rtype == 2 then
                AudioMessage("misn1604.wav")
                BuildObject("svscav", 1, "startb"); BuildObject("svscav", 1, "startb2"); BuildObject("svfigh", 1, "startb3")
            elseif rtype == 3 then
                AudioMessage("misn1605.wav")
                BuildObject("svscav", 1, "starta"); BuildObject("svturr", 1, "starta2"); BuildObject("svfigh", 1, "starta3")
            elseif rtype == 4 then
                AudioMessage("misn1606.wav")
                BuildObject("svfigh", 1, "startb"); BuildObject("svfigh", 1, "startb2")
            elseif rtype == 5 then
                AudioMessage("misn1607.wav")
                BuildObject("svfigh", 1, "starta"); BuildObject("svfigh", 1, "starta2"); BuildObject("svtank", 1, "starta3")
            elseif rtype == 6 then
                AudioMessage("misn1607.wav") -- Duplicate audio in C++?
                BuildObject("svtank", 1, "startb"); BuildObject("svtank", 1, "startb2"); BuildObject("svtank", 1, "startb3")
            elseif rtype == 7 then
                AudioMessage("misn1608.wav")
                BuildObject("svwalk", 1, "starta"); BuildObject("svwalk", 1, "starta2"); BuildObject("svwalk", 1, "starta3")
            end
            
            rtype = math.random(1, 7)
            next_reinforcement = GetTime() + DiffUtils.ScaleTimer(180.0)
            start_time = GetTime() + DiffUtils.ScaleTimer(2.0) -- Trigger camera check for new reinforcements
        end
    end
    
    -- Cinematic for reinforcements
    if GetTime() > start_time then
        local enemy = GetNearestEnemy(player)
        if IsAlive(player) and (GetDistance(player, enemy) > 150.0) then -- Only if safe
            rcam = true
            rcam_time = GetTime() + 4.0
            CameraReady()
        end
        start_time = 99999.0
    end
    
    if rcam and IsAlive(newbie) then
        CameraObject(newbie, 0, 2000, 3000, newbie)
    end
    if rcam and ((rcam_time < GetTime()) or CameraCancelled()) then
        rcam = false
        CameraFinish()
        rcam_time = 99999.0
    end
    
    -- Alien Waves
    if GetTime() > alien_wave then
        BuildObject("hvsav", 2, base2)
        alien_wave = GetTime() + wave_gap
        if wave_gap > 60.0 then wave_gap = wave_gap - 5.0 end
    end
    
    if GetTime() > alien_wave1 then
        local sat = BuildObject("hvsat", 2, "sat1")
        Goto(sat, "strike1")
        sat = BuildObject("hvsat", 2, "sat2")
        Goto(sat, "strike2")
        alien_wave1 = alien_wave + 90.0
    end
    
    -- Counter-Attack
    if (not won) and (not lost) and (not counter) and (((not IsAlive(tow1)) and (not IsAlive(tow2))) or ((not IsAlive(tow3)) and (not IsAlive(tow4))) or (not IsAlive(base1)) or (not IsAlive(base2))) then
        local sav1 = BuildObject("hvsav", 2, base2)
        local sav2 = BuildObject("hvsav", 2, base2)
        if IsAlive(muf) then
            Attack(sav1, muf)
            Attack(sav2, muf)
        end
        counter = true
        counter_strike2 = GetTime() + DiffUtils.ScaleTimer(120.0)
    end
    
    if GetTime() > counter_strike2 then
        local sav1 = BuildObject("hvsav", 2, base2)
        local sav2 = BuildObject("hvsav", 2, base2)
        if IsAlive(recy) then
            Attack(sav1, recy)
            Attack(sav2, recy)
        end
        counter_strike2 = 99999.0
    end
    
    -- Win/Loss
    if (not won) and (not IsAlive(base1)) and (not IsAlive(base2)) then
        AudioMessage("misn1613.wav")
        won = true
        SucceedMission(GetTime() + 15.0, "misn16w1.des")
    end
    
    if (not lost) and (not IsAlive(recy)) then
        AudioMessage("misn1612.wav")
        lost = true
        FailMission(GetTime() + 15.0, "misn16l1.des")
    end
end

