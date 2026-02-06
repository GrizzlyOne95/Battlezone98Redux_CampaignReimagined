-- Misn15 Mission Script (Converted from Misn15Mission.cpp)

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
    DiffUtils.SetupTeams(aiCore.Factions.NSDF, aiCore.Factions.Xenomites, 2)
end

-- Variables
local found_group1 = false
local found_group2 = false -- Commented out in C++, possibly unused
local got_dough = false
local start_done = false
local cca_here = false
local found = false
local won = false
local lost = false
local camera1 = false
local camera2 = false
local camera3 = false
local alien3 = false
local misn15b = false
local silo_built = false
local tartarus = false

-- Timers
local camera_time = 99999.0
local second_message = 99999.0
local sav_timer = 99999.0
local rendezvous1 = 99999.0
local rendezvous2 = 99999.0
local rcam1 = 99999.0
local rcam2 = 99999.0
local deny_time1 = 99999.0
local deny_time2 = 99999.0
local misl_time = 99999.0
local check_time = 99999.0

-- Handles
local tart
local player, recy
local cam1, cam2, cam3, cam4, cam5, cam6
local tank1, tank2, hov1
local goal
local scavcam
local sat1, sat2
local scav_du_jour
local savlist = {}

local silocount = 0
local difficulty = 2

function Start()
    if exu then
        if exu.EnableShotConvergence then exu.EnableShotConvergence() end
        if exu.SetSmartCursorRange then exu.SetSmartCursorRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    
    start_done = false
    camera1 = false
    silocount = 0
end

local function UpdateObjectives()
    ClearObjectives()
    if cca_here then AddObjective("misn1501.otf", "green") else AddObjective("misn1501.otf", "white") end
    if found_group1 then AddObjective("misn1502.otf", "green") else AddObjective("misn1502.otf", "white") end
    if silo_built then AddObjective("misn1503.otf", "green") else AddObjective("misn1503.otf", "white") end
    if won then AddObjective("misn1504.otf", "green") else AddObjective("misn1504.otf", "white") end
end

function AddObject(h)
    local team = GetTeamNum(h)
    
    if team == 1 then
        local odf = GetOdf(h); if odf then odf = string.gsub(odf, "%z", "") end
        if odf == "avscav" then
            found = true
            scav_du_jour = h
        elseif odf == "absilo" then
            silocount = silocount + 1
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
    local odf = GetOdf(h); if odf then odf = string.gsub(odf, "%z", "") end
    if GetTeamNum(h) == 1 and odf == "absilo" then
        silocount = silocount - 1
    end
end

function Update()
    player = GetPlayerHandle()
    aiCore.Update()
    
    if not start_done then
        AddScrap(1, DiffUtils.ScaleRes(10))
        UpdateObjectives()
        
        if GetHandle("misn15b") then misn15b = true else misn15b = false end
        
        tart = GetHandle("ubtart0_i76building")
        recy = GetHandle("avrecy0_recycler")
        
        cam1 = GetHandle("apcamr0_camerapod")
        cam2 = GetHandle("apcamr1_camerapod")
        cam3 = GetHandle("apcamr2_camerapod")
        cam4 = GetHandle("apcamr3_camerapod")
        cam5 = GetHandle("apcamr4_camerapod")
        cam6 = GetHandle("apcamr5_camerapod")
        
        tank1 = GetHandle("svtank0_wingman")
        tank2 = GetHandle("svtank1_wingman")
        hov1 = GetHandle("svapc0_apc")
        
        goal = GetHandle("eggeizr15_geyser")
        
        rendezvous1 = GetTime() + DiffUtils.ScaleTimer(180.0)
        rendezvous2 = GetTime() + DiffUtils.ScaleTimer(240.0) -- Restored C++ logic
        deny_time1 = GetTime() + DiffUtils.ScaleTimer(300.0)
        deny_time2 = GetTime() + DiffUtils.ScaleTimer(400.0)
        check_time = GetTime() + DiffUtils.ScaleTimer(5.0)
        
        if cam1 then SetLabel(cam1, "Geyser Site") end
        if cam2 then SetLabel(cam2, "NW Geyser") end
        if cam3 then SetLabel(cam3, "NE Geyser") end
        if cam4 then SetLabel(cam4, "Geyser Site") end
        if cam5 then SetLabel(cam5, "Supply") end
        if cam6 then SetLabel(cam6, "Nav Beta") end
        
        Goto(tank1, "tank_path"); Goto(tank2, "tank_path"); Goto(hov1, "tank_path")
        
        AudioMessage("misn1501.wav")
        second_message = GetTime() + 2.0
        sav_timer = GetTime() + DiffUtils.ScaleTimer(120.0)
        misl_time = DiffUtils.ScaleTimer(40.0)
        scav_du_jour = recy
        
        
        start_done = true
        
        -- Wasp Missile Jump Scare (Restored from C++)
        -- "Hot Landing": Spawn a missile flying at the player immediately.
        local misl = BuildObject("waspmsl", 2, cam1) -- Spawn at camera/spawn point
        if IsAlive(misl) then
            local p_pos = GetPosition(player)
            local m_pos = GetPosition(misl)
            
            -- Calculate Direction Vector
            local dir = {x = p_pos.x - m_pos.x, y = p_pos.y - m_pos.y, z = p_pos.z - m_pos.z}
            
            -- Normalize (Simple Lua normalization)
            local len = math.sqrt(dir.x*dir.x + dir.y*dir.y + dir.z*dir.z)
            if len > 0 then
                dir.x = dir.x / len
                dir.y = dir.y / len
                dir.z = dir.z / len
            end
            
            -- Apply Velocity (Speed 150)
            SetVelocity(misl, {x = dir.x * 150, y = dir.y * 150, z = dir.z * 150})
            -- Orient it (If SetFrontVector available, or just velocity usually orients ODFs)
            SetFront(misl, dir) 
        end
    end
    
    -- Intro Camera (Reinforcements arrival)
    if (GetTime() > second_message) and (second_message ~= 99999.0) then
        AudioMessage("misn1502.wav")
        CameraReady()
        camera_time = GetTime() + 8.0
        second_message = 99999.0
        camera1 = true
    end
    
    if camera1 then
        CameraObject(tank1, 800, 600, 1200, tank1)
    end
    
    if camera1 and ((GetTime() > camera_time) or CameraCancelled()) then
        camera1 = false
        CameraFinish()
    end
    
    -- Meetup at Nav Beta
    if (not cca_here) and ((GetDistance(cam6, tank1) < 100.0) or (GetDistance(cam4, tank1) < 100.0)) then
        cca_here = true
        AudioMessage("misn1503.wav")
        UpdateObjectives()
    end
    
    -- Reinforcements Group 1
    if (not found_group1) and (GetTime() > rendezvous1) and (rendezvous1 ~= 99999.0) then
        -- SetUserTarget(cam2) -- Point player to NW Geyser
        AudioMessage("misn1511.wav")
        rendezvous1 = 99999.0
    end
    
    if (not found_group1) and (GetDistance(cam2, player) < 150.0) then
        AudioMessage("misn1518.wav")
        scavcam = BuildObject("avscav", 1, "scav3here")
        BuildObject("avapc", 1, "mufhere")
        BuildObject("avturr", 1, "turhere")
        found_group1 = true
        UpdateObjectives()
        camera2 = true
        rcam1 = GetTime() + 3.0
        CameraReady()
    end
    
    if camera2 then
        CameraPath("rescue_cam1", 1000, 0, scavcam)
    end
    
    if found_group1 and (GetTime() > rcam1) and (rcam1 ~= 99999.0) then
        camera2 = false
        rcam1 = 99999.0
        CameraFinish()
    end
    
    if found_group1 and (GetTime() > rcam1) and (rcam1 ~= 99999.0) then
        camera2 = false
        rcam1 = 99999.0
        CameraFinish()
    end

    -- Reinforcements Group 2 (Restored from C++ lines 291-323)
    if (not found_group2) and (GetTime() > rendezvous2) and (rendezvous2 ~= 99999.0) then
        -- SetUserTarget(cam3) -- Guide to NE Geyser
        AudioMessage("misn1512.wav")
        rendezvous2 = 99999.0
    end

    if (not found_group2) and (GetDistance(cam3, player) < 150.0) then
        AudioMessage("misn1514.wav") -- "Commander, over here!"
        scavcam = BuildObject("avscav", 1, "scav1here")
        BuildObject("avscav", 1, "scav2here")
        BuildObject("avartl", 1, "arthere")
        found_group2 = true
        camera3 = true
        rcam2 = GetTime() + 3.0
        CameraReady()
    end

    if camera3 then
        CameraPath("rescue_cam2", 1000, 0, scavcam)
    end

    if found_group2 and (GetTime() > rcam2) and (rcam2 ~= 99999.0) then
        camera3 = false
        rcam2 = 99999.0
        CameraFinish()
    end
    
    -- Tartarus Relic
    if (not tartarus) and (GetDistance(player, tart) < 150.0) then
        tartarus = true
        AudioMessage("misn1513.wav")
        AudioMessage("misn1514.wav")
    end
    
    -- Alien Attacks on Scavengers
    if (GetTime() > sav_timer) and (#savlist < 50) then
        local sav
        if math.random(0,1) == 1 then
            sav = BuildObject("hvsav", 2, "alien1")
        else
            sav = BuildObject("hvsav", 2, "alien2")
        end
        if IsAlive(scav_du_jour) then Attack(sav, scav_du_jour) end
        
        sav_timer = GetTime() + DiffUtils.ScaleTimer(240.0)
        table.insert(savlist, sav)
    end
    
    -- Alien Scheduler (Keep them moving)
    if GetTime() > check_time then
        for i, sav in pairs(savlist) do
            if IsAlive(sav) and (GetCurrentCommand(sav) == 0) then -- CMD_NONE
                Goto(sav, "alien_path")
            end
        end
        check_time = GetTime() + DiffUtils.ScaleTimer(5.0)
    end
    
    -- Resource Denial (Satellites)
    if misn15b and (GetTime() > deny_time1) then
        sat1 = BuildObject("hvsat", 2, "alien1")
        sat2 = BuildObject("hvsat", 2, "alien1")
        Goto(sat1, "deny1")
        Goto(sat2, "deny1")
        deny_time1 = 99999.0
    end
    
    if misn15b and (GetTime() > deny_time2) then
        sat1 = BuildObject("hvsat", 2, "alien2")
        sat2 = BuildObject("hvsat", 2, "alien2")
        Goto(sat1, "deny2")
        Goto(sat2, "deny2")
        deny_time2 = 99999.0
    end
    
    -- Win/Loss
    if (not lost) and (not IsAlive(recy)) then
        AudioMessage("misn1414.wav") -- Reused audio?
        lost = true
        FailMission(GetTime() + 10.0, "misn15l1.des")
    end
    
    if (silocount > 1) and (not silo_built) then
        silo_built = true
        UpdateObjectives()
    end
    
    if (not got_dough) and (GetScrap(1) > 74) then
        -- C++ checks Silo condition separately but marks 'got_dough' for scrap?
        -- Actually, logic in C++: Win if Scrap > 74. Silo objective is secondary/helper?
        -- Wait, looking at C++:
        -- if (!got_dough && GetScrap>74) -> Win.
        -- BUT objectives show silos need building.
        -- To be safe, usually mission 15 requires silos.
        -- C++ snippet shows WIN on scrap > 74.
        
        UpdateObjectives()
        got_dough = true
        AudioMessage("misn1510.wav")
        SucceedMission(GetTime() + 10.0, "misn15w1.des")
    end
end
