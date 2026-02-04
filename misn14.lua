-- Misn14 Mission Script (Converted from Misn14Mission.cpp)

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
    DiffUtils.SetupTeams(aiCore.Factions.NSDF, aiCore.Factions.CCA, 2)
    -- Aliens setup (Manually if needed, but SetupTeams covers standard hostile teams)
end

-- Variables
local start_done = false
local camera1 = false
local camera2 = false
local camera3 = false
local alien_attack = false
local alien_warning = false
local cca_surrender = false
local gen_message = false
local rescue_reminder = false
local rescue_message = false
local rescue_start = false
local found = false
local rescue1 = false
local rescue2 = false
local rescue3 = false
local won = false
local lost = false
local pick_up = false
local rescuecam1 = false
local rescuecam2 = false
local rescuecam3 = false -- Not used in C++ snippet for 2/3 but declared
local finishcam1 = false
local finishcam2 = false
local finishcam3 = false

-- Timers
local camera_time = 99999.0
local alien_time = 99999.0
local pick_up_time = 99999.0
local beacon_time1 = 99999.0
local beacon_time2 = 99999.0
local beacon_time3 = 99999.0
local rescue_finish1 = 99999.0
local rescue_finish2 = 99999.0
local rescue_finish3 = 99999.0
local next_second = 0.0

-- Handles
local beacon1, beacon2, beacon3
local player, recy, erecy, base, apc
local cam1, cam2, cam3, cam4
local guy1, guy2, guy3
local tow1, tow2, tow3, tow4

local wave_count = 0
local difficulty = 2

function Start()
    if exu then
        if exu.EnableShotConvergence then exu.EnableShotConvergence() end
        if exu.SetSmartCursorRange then exu.SetSmartCursorRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    
    start_done = false
    camera1 = true -- Start with camera
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then
        aiCore.AddObject(h)
    end
    if team == 3 then
        -- Aliens
        aiCore.AddObject(h)
    end
    
    local odf = GetOdf(h); if odf then odf = string.gsub(odf, "%z", "") end
    if (odf == "avapc") and (team == 1) then
        found = true
        apc = h
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
    
    if not start_done then
        recy = GetHandle("avrecy-1_recycler")
        erecy = GetHandle("svrecy-1_recycler")
        base = GetHandle("sbbarr0_i76building")
        
        SetAIP("misn14.aip")
        SetPilot(1, DiffUtils.ScaleRes(10)); SetPilot(2, DiffUtils.ScaleRes(30))
        SetScrap(1, DiffUtils.ScaleRes(30)); SetScrap(2, DiffUtils.ScaleRes(45))
        
        cam1 = GetHandle("apcamr0_camerapod")
        cam2 = GetHandle("apcamr1_camerapod")
        cam3 = GetHandle("apcamr2_camerapod")
        cam4 = GetHandle("apcamr3_camerapod")
        
        tow1 = GetHandle("sbtowe0_turret")
        tow2 = GetHandle("sbtowe1_turret")
        tow3 = GetHandle("sbtowe55_turret")
        tow4 = GetHandle("sbtowe56_turret")
        
        if cam1 then SetLabel(cam1, "Foothill Geysers") end
        if cam2 then SetLabel(cam2, "Canyon Geysers") end
        if cam3 then SetLabel(cam3, "CCA Base") end
        if cam4 then SetLabel(cam4, "Plateau Geysers") end
        
        start_done = true
        next_second = GetTime() + 1.0
        
        CameraReady()
        camera_time = GetTime() + 12.0
        AudioMessage("misn1401.wav")
        
        if IsAlive(base) then
            SetMaxHealth(base, 100000)
            next_second = GetTime() + 1.0
        end
    end
    
    -- Cam 1
    if camera1 then
        CameraPath("cam_path1", 2000, 1000, recy)
    end
    if camera1 and ((GetTime() > camera_time) or CameraCancelled()) then
        camera1 = false
        camera2 = true
        camera_time = GetTime() + 15.0
    end
    
    -- Cam 2
    if camera2 then
        CameraPath("cam_path2", 2000, 500, recy)
    end
    if camera2 and ((GetTime() > camera_time) or CameraCancelled()) then
        camera2 = false
        CameraFinish()
        ClearObjectives()
        AddObjective("misn1401.otf", "white")
        alien_time = GetTime() + DiffUtils.ScaleTimer(720.0)
        beacon_time1 = GetTime() + DiffUtils.ScaleTimer(15.0)
    end
    
    -- Beacon 1
    if (GetTime() > beacon_time1) and (beacon_time1 ~= 99999.0) then
        AudioMessage("misn1416.wav")
        beacon_time1 = 99999.0
        beacon1 = BuildObject("apcamr", 1, "rescue1")
        guy1 = BuildObject("aspilo", 1, "help1")
        guy2 = BuildObject("aspilo", 1, "help2")
        guy3 = BuildObject("aspilo", 1, "help3")
        Defend(guy1); Defend(guy2); Defend(guy3)
        SetLabel(beacon1, "Rescue 1")
        SetObjectiveOn(beacon1)
    end
    
    -- Checkpoint Distance + APC Reminder
    if IsAlive(beacon1) and (GetDistance(player, beacon1) < 200.0) and (not rescue_reminder) and IsAlive(apc) and (GetDistance(apc, beacon1) > 300.0) then
        AudioMessage("misn1415.wav")
        rescue_reminder = true
    end
    
    -- Loss Check (Pilots Dead)
    if (not lost) and IsAlive(beacon1) and (not rescue1) and ((not IsAlive(guy1)) or (not IsAlive(guy2)) or (not IsAlive(guy3))) then
        AudioMessage("misn1421.wav")
        FailMission(GetTime() + 15.0, "misn14l2.des")
        lost = true
    end
    
    -- Rescue 1 Start
    if IsAlive(beacon1) and IsAlive(apc) and (not rescue1) and (GetDistance(apc, beacon1) < 100.0) then
        rescue1 = true
        if IsAlive(guy1) then Goto(guy1, beacon1) end -- Actually APC? C++ says beacon1. Pilots run to beacon to simulate loading?
        if IsAlive(guy2) then Goto(guy2, beacon1) end -- Usually they should Enter(apc). C++ Logic: "Goto(guy1,beacon1)".
        if IsAlive(guy3) then Goto(guy3, beacon1) end -- We will replicate moving to beacon. Maybe removing them simulates entering?
        rescue_finish1 = GetTime() + DiffUtils.ScaleTimer(25.0)
        AudioMessage("misn1409.wav")
        camera_time = GetTime() + DiffUtils.ScaleTimer(3.0)
        CameraReady()
        rescuecam1 = true
    end
    
    if rescuecam1 then
        CameraObject(apc, 1000, 1000, 1000, apc)
        if CameraCancelled() or (GetTime() > camera_time) then
            CameraFinish()
            rescuecam1 = false
        end
    end
    
    -- Rescue 1 Finish
    if IsAlive(beacon1) and rescue1 and (rescue_finish1 < GetTime()) then
        if IsAlive(guy1) then RemoveObject(guy1) end
        if IsAlive(guy2) then RemoveObject(guy2) end
        if IsAlive(guy3) then RemoveObject(guy3) end
        if IsAlive(beacon1) then RemoveObject(beacon1) end
        beacon_time2 = GetTime() + DiffUtils.ScaleTimer(10.0)
        CameraReady()
        AudioMessage("misn1417.wav")
        finishcam1 = true
        rescue_finish1 = 99999.0
        camera_time = GetTime() + 3.0
    end
    
    if finishcam1 then
        CameraObject(apc, 1000, 1000, 1000, apc)
        if CameraCancelled() or (GetTime() > camera_time) then
            CameraFinish()
            finishcam1 = false
        end
    end
    
    -- Beacon 2
    if (GetTime() > beacon_time2) and (beacon_time2 ~= 99999.0) then
       beacon_time2 = 99999.0
       beacon2 = BuildObject("apcamr", 1, "rescue2")
       guy1 = BuildObject("aspilo", 1, "help4")
       guy2 = BuildObject("aspilo", 1, "help5")
       guy3 = BuildObject("aspilo", 1, "help6")
       Defend(guy1); Defend(guy2); Defend(guy3)
       SetLabel(beacon2, "Rescue 2")
       SetObjectiveOn(beacon2)
    end
    
    if (not lost) and IsAlive(beacon2) and (not rescue2) and ((not IsAlive(guy1)) or (not IsAlive(guy2)) or (not IsAlive(guy3))) then
       lost = true
       AudioMessage("misn1421.wav")
       FailMission(GetTime() + 15.0, "misn14l2.des")
    end
    
    if IsAlive(beacon2) and IsAlive(apc) and (not rescue2) and (GetDistance(apc, beacon2) < 100.0) then
        rescue2 = true
        Goto(guy1, beacon2); Goto(guy2, beacon2); Goto(guy3, beacon2)
        rescue_finish2 = GetTime() + DiffUtils.ScaleTimer(25.0)
        AudioMessage("misn1409.wav")
    end
    
    if IsAlive(beacon2) and rescue2 and (rescue_finish2 < GetTime()) then
        if IsAlive(guy1) then RemoveObject(guy1) end
        if IsAlive(guy2) then RemoveObject(guy2) end
        if IsAlive(guy3) then RemoveObject(guy3) end
        if IsAlive(beacon2) then RemoveObject(beacon2) end
        AudioMessage("misn1418.wav")
        rescue_finish2 = 99999.0
        beacon_time3 = GetTime() + DiffUtils.ScaleTimer(10.0)
    end
    
    -- Beacon 3
    if (GetTime() > beacon_time3) and (beacon_time3 ~= 99999.0) then
        beacon_time3 = 99999.0
        beacon3 = BuildObject("apcamr", 1, "rescue3")
        guy1 = BuildObject("aspilo", 1, "help7")
        guy2 = BuildObject("aspilo", 1, "help8")
        guy3 = BuildObject("aspilo", 1, "help9")
        Defend(guy1); Defend(guy2); Defend(guy3)
        SetLabel(beacon3, "Rescue 3")
        SetObjectiveOn(beacon3)
    end
    
    if (not lost) and IsAlive(beacon3) and (not rescue3) and ((not IsAlive(guy1)) or (not IsAlive(guy2)) or (not IsAlive(guy3))) then
       lost = true
       AudioMessage("misn1421.wav")
       FailMission(GetTime() + 15.0, "misn14l2.des")
    end
    
    if IsAlive(beacon3) and IsAlive(apc) and (not rescue3) and (GetDistance(apc, beacon3) < 100.0) then
        rescue3 = true
        Goto(guy1, beacon3); Goto(guy2, beacon3); Goto(guy3, beacon3)
        rescue_finish3 = GetTime() + DiffUtils.ScaleTimer(25.0)
        AudioMessage("misn1409.wav")
    end
    
    if IsAlive(beacon3) and rescue3 and (rescue_finish3 < GetTime()) then
        if IsAlive(guy1) then RemoveObject(guy1) end
        if IsAlive(guy2) then RemoveObject(guy2) end
        if IsAlive(guy3) then RemoveObject(guy3) end
        if IsAlive(beacon3) then RemoveObject(beacon3) end
        AudioMessage("misn1419.wav")
        rescue_finish3 = 99999.0
    end
    
    -- Keep Base Alive
    if IsAlive(base) and (GetTime() > next_second) then
        AddHealth(base, 5000)
        next_second = GetTime() + 1.0
    end
    
    -- Alien Waves
    if GetTime() > alien_time then
        alien_attack = true
        wave_count = wave_count + 1
        local x = math.random(0, 2)
        if x == 0 then
            BuildObject("hvsav", 3, "alien1"); BuildObject("hvsav", 3, "alien2"); BuildObject("hvsav", 3, "alien5")
        elseif x == 1 then
            BuildObject("hvsav", 3, "alien3"); BuildObject("hvsav", 3, "alien4"); BuildObject("hvsav", 3, "alien1")
        else
            BuildObject("hvsav", 3, "alien5"); BuildObject("hvsav", 3, "alien6"); BuildObject("hvsav", 3, "alien3")
        end
        alien_time = GetTime() + DiffUtils.ScaleTimer(180.0)
    end
    
    if alien_attack and (not alien_warning) then
        AudioMessage("misn1403.wav")
        alien_warning = true
    end
    
    -- CCA Surrender
    if (wave_count > 2) and (not cca_surrender) then
        AudioMessage("misn1404.wav")
        AudioMessage("misn1405.wav")
        cca_surrender = true
        
        -- Switch Sides Logic
        -- We scan area as we can't iterate global list. Center of map with large radius.
        local units = GetObjectsInRange(player, 5000.0, "any") -- Scan large area
        for _, o in ipairs(units) do
            if GetTeamNum(o) == 2 and IsCraft(o) then
                SetTeam(o, 0)
                Retreat(o, "escape")
            end
        end
        
        if IsAlive(base) then SetTeam(base, 1) end
        if IsAlive(tow1) then SetTeam(tow1, 1) end
        if IsAlive(tow2) then SetTeam(tow2, 1) end
        if IsAlive(tow3) then SetTeam(tow3, 1) end
        if IsAlive(tow4) then SetTeam(tow4, 1) end
    end
    
    -- Post-Rescue 3 events
    if (wave_count > 3) and (not gen_message) and rescue3 then
        SetScrap(2, 0)
        AudioMessage("misn1406.wav")
        gen_message = true
        local foe = GetNearestEnemy(player)
        if IsAlive(foe) and (GetDistance(player, foe) > 150.0) then
            camera3 = true
            camera_time = GetTime() + 20.0
            CameraReady()
        else
            camera3 = false
        end
    end
    
    if camera3 then
        CameraPath("camera_path", 2500, 300, base)
    end
    if camera3 and ((GetTime() > camera_time) or CameraCancelled()) then
        camera3 = false
        CameraFinish()
    end
    
    -- Rescue CCA
    if (wave_count > 4) and (not rescue_message) and rescue3 then
        SetScrap(2, 0)
        AudioMessage("misn1407.wav")
        rescue_message = true
        if IsAlive(base) then
            SetObjectiveOn(base)
            SetLabel(base, "Rescue CCA")
        else
            FailMission(GetTime() + 5.0, "misn14l.des")
        end
    end
    
    if (wave_count > 4) and found and (not rescue_start) and rescue3 then
        AudioMessage("misn1408.wav")
        rescue_start = true
    end
    
    if (not pick_up) and rescue_start and IsAlive(apc) and IsAlive(base) and (GetDistance(apc, base) < 200.0) then
        pick_up = true
        pick_up_time = GetTime() + DiffUtils.ScaleTimer(15.0)
        AudioMessage("misn1409.wav")
    end
    
    if pick_up and (GetTime() > pick_up_time) and (pick_up_time ~= 99999.0) then
        pick_up_time = 99999.0
        AudioMessage("misn1410.wav")
    end
    
    if (not lost) and pick_up and (not IsAlive(apc)) then
        AudioMessage("misn1412.wav")
        AudioMessage("misn1413.wav")
        FailMission(GetTime() + 10.0, "misn14l3.des")
        lost = true
    end
    
    if (not won) and pick_up and IsAlive(recy) and IsAlive(apc) and (GetDistance(recy, apc) < 300.0) then
        won = true
        SucceedMission(GetTime() + 10.0, "misn14w1.des")
        AudioMessage("misn1411.wav")
    end
    
    if (not lost) and (not IsAlive(recy)) then
        AudioMessage("misn1414.wav")
        FailMission(GetTime() + 10.0, "misn14l1.des")
        lost = true
    end
    
end
