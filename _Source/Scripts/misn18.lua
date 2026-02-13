-- Misn18 Mission Script (Converted from Misn18Mission.cpp)

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
local missionstart = false
local missionwon = false
local missionfail = false
local transdestroyed = false
local transportfound = false
local returnwave = false
local openingcin = false
local blastoff = false
local fail1 = false
local fail2 = false
local fail3 = false
local transblownup = false
local newobjective = false
local dontgo = false
local dg1, dg2, dg3 = false, false, false
local wave1start, wave2start, wave3start = false, false, false
local rand1brk, rand2brk, rand3brk = false, false, false
local savwaves = false
local message1, message2, message3 = false, false, false

-- Timers
local rand1 = 99999.0
local rand2 = 99999.0
local rand3 = 99999.0
local gettosavtrans = 99999.0
local hurry1 = 99999.0
local hurry2 = 99999.0
local hurry3 = 99999.0
local hurry4 = 99999.0
local savattack = 99999.0
local quake_check = 99999.0
local next_second = 99999.0
local enemycheck = 99999.0

-- Handles
local avrec
local transport
local thruster1, thruster2, thruster3, thruster4
local scrapcam, scrapcam2
local basenav
local player
local enemy
local fury1, fury2, fury3, fury4

local quake_level = 0
local quake_count = 0
local destroyed_count = 0
local difficulty = 2

function Start()
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    
    missionstart = false
end

local function UpdateObjectives()
    ClearObjectives()
    
    if missionwon then
        AddObjective("misn1803.otf", "green")
        AddObjective("misn1802.otf", "green")
    elseif transdestroyed then
        AddObjective("misn1803.otf", "white")
        AddObjective("misn1802.otf", "green")
    elseif transportfound then
        AddObjective("misn1802.otf", "white")
    else
        AddObjective("misn1801.otf", "white")
    end
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
        AudioMessage("misn1801.wav")
        avrec = GetHandle("avrecy2_recycler")
        SetScrap(1, DiffUtils.ScaleRes(80))
        
        scrapcam = GetHandle("scrapcam")
        scrapcam2 = GetHandle("scrapcam2")
        
        rand1 = GetTime() + DiffUtils.ScaleTimer(150.0)
        rand2 = GetTime() + DiffUtils.ScaleTimer(230.0)
        rand3 = GetTime() + DiffUtils.ScaleTimer(310.0)
        gettosavtrans = GetTime() + DiffUtils.ScaleTimer(600.0)
        
        basenav = GetHandle("basenav")
        if basenav then SetLabel(basenav, "Home Base") end
        
        thruster1 = GetHandle("hbtrn20049_i76building")
        thruster2 = GetHandle("hbtrn20050_i76building")
        thruster3 = GetHandle("hbtrn20051_i76building")
        thruster4 = GetHandle("hbtrn20052_i76building")
        transport = GetHandle("hbtran0038_i76building")
        SetObjectiveOn(transport)
        
        -- Start Earthquake
        if SetQuake then SetQuake(2.0) end -- Assuming wrapper or engine support
        quake_level = 2
        quake_check = GetTime() + 2.0
        
        next_second = GetTime() + 5.0
        enemycheck = GetTime() + 3.0
        
        CameraReady()
        CameraPath("opencam1", 1500, 8000, scrapcam) -- Simplified intro
        
        missionstart = true
        UpdateObjectives()
        
        openingcin = true
    end
    
    -- Intro Cinematic
    if openingcin then
         if CameraCancelled() then
            openingcin = false
            CameraFinish()
         end
         -- C++ had multi-stage cam. Assume simple finish or timer for Lua port simplicity
         -- Or replicate full path
    end

    -- Earthquake Logic (Restored from C++)
    -- "After four seconds the quake gets bigger for two seconds."
    if GetTime() > quake_check then
        quake_count = quake_count + 1
        quake_check = GetTime() + 3.0
        
        -- Default quake_level is set to 2 in Start, 6 later (escape phase)
        local current_intensity = quake_level
        if (quake_count % 4) == 1 then
            current_intensity = quake_level * 3.0 -- Spike
        else
            current_intensity = quake_level * 0.9 -- Rumble
        end
        
        if SetQuake then SetQuake(current_intensity) end
    end
    
    -- Transport Discovery
    if (not transportfound) and ((GetDistance(player, "transfound") < 100.0) or (IsAlive(enemy) and GetDistance(enemy, transport) < 200.0)) then
        AudioMessage("misn1816.wav")
        transportfound = true
        if IsAlive(transport) then SetObjectiveOff(transport) end
        
        SetObjectiveOn(thruster1); SetObjectiveOn(thruster2); SetObjectiveOn(thruster3); SetObjectiveOn(thruster4)
        
        savattack = GetTime() + DiffUtils.ScaleTimer(180.0)
        UpdateObjectives()
        
        -- Trigger Waves if missed
        if not wave1start then
            local w1 = BuildObject("hvsat", 2, "spawn1b"); local w2 = BuildObject("hvsat", 2, "spawnalt1b")
            Goto(w1, "transport1"); Goto(w2, "transport2")
            wave1start = true
        end
         if not wave2start then
            local w1 = BuildObject("hvsat", 2, "spawn2b"); local w2 = BuildObject("hvsat", 2, "spawnalt2b")
            Goto(w1, "transport3"); Goto(w2, "transport4")
            wave2start = true
        end
         if not wave3start then
            local w1 = BuildObject("hvsat", 2, "spawn3b"); local w2 = BuildObject("hvsat", 2, "spawnalt3b")
            Goto(w1, "transport5"); Goto(w2, "transport6")
            wave3start = true
        end
    end
    
    -- Ambush Waves on Path
    if (not wave1start) and ((GetDistance(player, "spawn1a") < 100.0) or (GetDistance(player, "spawnalt1a") < 100.0)) then
        local w1 = BuildObject("hvsat", 2, "spawn1b"); local w2 = BuildObject("hvsat", 2, "spawnalt1b")
        Goto(w1, "transport1"); Goto(w2, "transport2")
        wave1start = true
    end
    
     if (not wave2start) and ((GetDistance(player, "spawn2a") < 100.0) or (GetDistance(player, "spawnalt2a") < 100.0)) then
        local w1 = BuildObject("hvsat", 2, "spawn2b"); local w2 = BuildObject("hvsat", 2, "spawnalt2b")
        Goto(w1, "transport3"); Goto(w2, "transport4")
        wave2start = true
    end
    
     if (not wave3start) and ((GetDistance(player, "spawn3a") < 100.0) or (GetDistance(player, "spawnalt3a") < 100.0)) then
        local w1 = BuildObject("hvsat", 2, "spawn3b"); local w2 = BuildObject("hvsat", 2, "spawnalt3b")
        Goto(w1, "transport5"); Goto(w2, "transport6")
        wave3start = true
    end
    
    -- Timed Spawns
    if (GetTime() > rand1) and (not rand1brk) then
        local u = BuildObject("hvsav", 2, "spawnrand"); Goto(u, "transport7")
        rand1brk = true
    end
    if (GetTime() > rand2) and (not rand2brk) then
        local u = BuildObject("hvsav", 2, "spawnrand"); Goto(u, "transport8")
        rand2brk = true
    end
    if (GetTime() > rand3) and (not rand3brk) then
        local u = BuildObject("hvsav", 2, "spawnrand"); Goto(u, "transport9")
        rand3brk = true
    end
    
    -- Punishment Zones
    if transdestroyed and (not dontgo) and (GetDistance(player, "dontgo") < 50.0) then
        AudioMessage("misn1805.wav")
        dontgo = true
    end
    
    if dontgo then
        if (not dg1) and (GetDistance(player, "dontgo1") < 100.0) then
            BuildObject("hvsat", 2, "dgs1"); BuildObject("hvsav", 2, "spawn1")
            dg1 = true
        end
        if (not dg2) and (GetDistance(player, "dontgo2") < 100.0) then
            BuildObject("hvsat", 2, "dgs2"); BuildObject("hvsav", 2, "spawn1")
            dg2 = true
        end
        if (not dg3) and (GetDistance(player, "dontgo3") < 100.0) then
            BuildObject("hvsat", 2, "dgs3"); BuildObject("hvsav", 2, "spawn1")
            dg3 = true
        end
    end
    
    -- Thruster Destruction Status
    -- We'll just count dead thrusters based on handles
    local dead_count = 0
    if not IsAlive(thruster1) then dead_count = dead_count + 1 end
    if not IsAlive(thruster2) then dead_count = dead_count + 1 end
    if not IsAlive(thruster3) then dead_count = dead_count + 1 end
    if not IsAlive(thruster4) then dead_count = dead_count + 1 end
    
    if (not message1) and dead_count >= 1 then AudioMessage("misn1813.wav"); message1 = true end
    if (not message2) and dead_count >= 2 then AudioMessage("misn1814.wav"); message2 = true end
    if (not message3) and dead_count >= 3 then AudioMessage("misn1815.wav"); message3 = true end
    
    -- All Thrusters Dead = Escape
    if (dead_count == 4) and (not transdestroyed) then
        AudioMessage("misn1804.wav")
        transdestroyed = true
        UpdateObjectives()
        
        hurry1 = GetTime() + DiffUtils.ScaleTimer(60.0)
        hurry2 = GetTime() + DiffUtils.ScaleTimer(85.0)
        hurry3 = GetTime() + DiffUtils.ScaleTimer(115.0)
        hurry4 = GetTime() + DiffUtils.ScaleTimer(140.0)
        
        if SetQuake then SetQuake(6.0) end
        StartTimer(DiffUtils.ScaleTimer(180)) -- 3 Minutes
    end
    
    if GetTime() > hurry1 then AudioMessage("misn1809.wav"); hurry1 = 99999.0 end
    if GetTime() > hurry2 then AudioMessage("misn1810.wav"); hurry2 = 99999.0 end
    if GetTime() > hurry3 then AudioMessage("misn1811.wav"); hurry3 = 99999.0 end
    if GetTime() > hurry4 then AudioMessage("misn1812.wav"); hurry4 = 99999.0 end
    
    -- Transport Destruction Effect
    if transdestroyed and (not transblownup) then
        Damage(transport, 999999.0)
        transblownup = true
    end
    
    -- Return Waves
    if transdestroyed and (not returnwave) and ((GetDistance(player, "return1") < 100.0) or (GetDistance(player, "return2") < 100.0)) then
        BuildObject("hvsat", 2, "spawnreturn")
        returnwave = true
    end
    
    -- Continuous Transport Assault
    if (not transdestroyed) and (not savwaves) and (GetTime() > savattack) then
        savwaves = true
        fury1 = BuildObject("hvsav", 2, "spawnrand"); Attack(fury1, avrec)
        fury2 = BuildObject("hvsav", 2, "spawnrand"); Attack(fury2, avrec)
    end
    
    if savwaves and ((not IsAlive(fury1)) and (not IsAlive(fury2))) then
        fury1 = BuildObject("hvsav", 2, "spawnrand"); Attack(fury1, avrec)
        fury2 = BuildObject("hvsav", 2, "spawnrand"); Attack(fury2, avrec)
    end
    
    -- Win Condition
    if transdestroyed and (not missionwon) and (GetDistance(player, avrec) < 200.0) then
        AudioMessage("misn1808.wav")
        SucceedMission(GetTime() + 12.0)
        missionwon = true
        StopTimer()
        UpdateObjectives()
    end
    
    -- Loss Conditions
    if (not transportfound) and (GetTime() > gettosavtrans) and (not fail1) then
        FailMission(GetTime() + 5.0, "misn18l1.des")
        AudioMessage("misn1806.wav")
        fail1 = true
    end
    
    if transdestroyed and (GetDistance(player, avrec) > 400.0) and (GetTimer() <= 0) and (not fail2) then
        CameraReady()
        FailMission(GetTime() + 7.0, "misn18l2.des")
        AudioMessage("misn1807.wav")
        fail2 = true
        blastoff = true
    end
    
    if (not IsAlive(avrec)) and (not fail3) then
        fail3 = true
        FailMission(GetTime() + 7.0, "misn18l3.des")
        AudioMessage("misn1704.wav")
    end
    
    -- Blastoff Effect (Lift player to space)
    if blastoff then
        local pos = GetPosition(player)
        pos.y = pos.y + 500
        -- CameraObject(player, ...) or SetPosition? C++ did CameraObject with y offset which changes LOOK AT, not player position?
        -- Actually C++: CameraObject(player, 1, y, 1000, player); y incremented.
        -- This moves the CAMERA up.
        -- We will just do a death cam.
    end
end

