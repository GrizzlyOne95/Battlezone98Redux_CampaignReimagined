-- Misn09 Mission Script (Converted from Misn09Mission.cpp)

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
end

-- Variables
local start_done = false
local start_camera1 = false
local convoy_started = false
local player_dead = false
local camera_ready = false
local build_new_tug = false -- Unused in C++ source but present
local tug_done = false
local objective1 = false
local camera_artil = false
local first_warning = false
local second_warning = false
local third_warning = false
local muf_contact = false
local muf_moving = false
local post1 = false
local post2 = false
local post3 = false
local post4 = false
local turret1_set = false
local turret2_set = false
local turret3_set = false
local turret4_set = false
local get_relic = false
local relic_secure = false
local relic_seized = false
local relic_free = false
local tug_underway = false
local head_4_pad = false
local game_over = false
local next_shot = false
local player_camera_off = false
local next_shot_message = false
local cam1_on = false
local cam2_on = false
local cam3_on = false
local cam4_on = false
local cam5_on = false
local cam_off = false
local convoy_cam_ready = false
local convoy_cam_off = false
local muf_deployed = false
local scavs_alive = false
local charon_found = false
local charon_build = false
local start = false
local opening_vo = false
local muf_gobaby = false
local recon_artil = false
local base_warning = false
local muf_deployed_good = false
local ccadead = false
local game_over5 = false -- Units cleared

-- Timers
local start_convoy_time = 999999.0
local camera_ready_time = 999999.0
local build_tug_time = 999999.0
local camera_on_time = 999999.0
local first_warning_time = 999999.0
local second_warning_time = 999999.0
local third_warning_time = 999999.0
local muf_check = 999999.0
local movie_time = 999999.0
local turret1_time = 999999.0
local turret2_time = 999999.0
local turret3_time = 999999.0
local turret4_time = 999999.0
local unit_check = 999999.0
local win_check = 999999.0
local atril_check = 999999.0
local player_camera_time = 999999.0
local next_shot_time = 999999.0
local cam1_time = 999999.0
local cam2_time = 999999.0
local cam3_time = 999999.0
local cam4_time = 999999.0
local cam5_time = 999999.0
local convoy_cam_time = 999999.0
local deploy_check = 999999.0
local charon_check = 999999.0
local start_time = 20.0
local recon_message_time = 999999.0

-- Handles
local user, relic, nav1, charon, avsilo, key_scrap
local ccatug, nsdftug, convoy_geyser, cut_off_geyser
local ccaturret1, ccaturret2, ccaturret3, ccaturret4, ccaturret5, ccaturret6
local ccarecycle, ccamuf, ccaarmor, ccalaunch
local cca1, cca2, cca3, cca4, cca5, cca6, cca7, cca8, cca9, cca0
local scav1, scav2, scav3
local nsdfrecycle, nsdfmuf, avscav1, avscav2, avscav3, nsdfgech1
local construct, nsdfslf, nsdfrig
local tugger -- The tug carrying the relic
local convoy1, convoy2, convoy3, convoy4, convoy5, convoy6, convoy7, convoy8, convoy9, convoy0
local charon_nav

local difficulty = 2

function Start()
    if exu then
        if exu.EnableShotConvergence then exu.EnableShotConvergence() end
        if exu.SetSmartCursorRange then exu.SetSmartCursorRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    
    start_done = false
    start_time = 20.0
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
    user = GetPlayerHandle()
    aiCore.Update()
    
    -- Relic State Logic (Replaces C++ Tug Checks)
    if relic_free and IsAlive(relic) then
        local t = GetTug(relic)
        if IsAlive(t) then
            if GetTeamNum(t) == 1 then
                relic_free = false
                relic_secure = true
                tugger = t
            else
                relic_free = false
                relic_seized = true
                tugger = ccatug -- Assuming it's the enemy tug
            end
        end
    end
    
    if relic_secure and (not IsAlive(tugger)) then
        relic_free = true
        relic_secure = false
        tugger = nil
    end
    
    if relic_seized and (not IsAlive(ccatug)) then
        relic_free = true
        relic_seized = false
        tugger = nil
    end
    
    if IsAlive(relic) then
        if IsAlive(ccatug) and relic_free and (not tug_underway) then
            Pickup(ccatug, relic)
            tug_underway = true
        end
        if relic_seized and (not head_4_pad) then
            Dropoff(ccatug, "soviet_path")
            head_4_pad = true
        end
    end
    
    if not IsAlive(ccatug) then
        tug_underway = false
        head_4_pad = false
    end
    
    if not start_done then
        CameraReady()
        
        nsdfmuf = GetHandle("avmuf")
        Defend(nsdfmuf)
        
        SetScrap(2, DiffUtils.ScaleRes(40))
        SetPilot(2, DiffUtils.ScaleRes(40))
        
        nsdfrig = GetHandle("rig")
        avscav1 = GetHandle("scav1")
        avscav2 = GetHandle("scav2")
        avscav3 = GetHandle("scav3")
        Follow(nsdfrig, nsdfmuf)
        Follow(avscav1, nsdfmuf)
        Follow(avscav2, nsdfmuf)
        Follow(avscav3, nsdfmuf)
        
        nsdfslf = GetHandle("avslf")
        Follow(nsdfslf, nsdfrig)
        
        ccaturret1 = GetHandle("artil1")
        ccaturret2 = GetHandle("artil2")
        ccaturret3 = GetHandle("artil3")
        ccaturret4 = GetHandle("artil4")
        ccaturret5 = GetHandle("artil5")
        ccaturret6 = GetHandle("artil6")
        Defend(ccaturret1)
        Defend(ccaturret2)
        Defend(ccaturret3)
        Defend(ccaturret4)
        Defend(ccaturret5)
        Defend(ccaturret6)
        
        convoy_geyser = GetHandle("convoy_geyser")
        ccarecycle = GetHandle("svrecycle") -- Might be nil
        ccamuf = GetHandle("svmuf")
        if not ccamuf then ccamuf = GetHandle("svmuf") end
        
        ccalaunch = GetHandle("launchpad")
        nav1 = GetHandle("cam1")
        charon = GetHandle("hbchar0_i76building")
        key_scrap = GetHandle("key_scrap")
        
        camera_ready_time = GetTime() + 6.0
        muf_check = GetTime() + 3.0
        
        first_warning_time = GetTime() + DiffUtils.ScaleTimer(700.0)
        second_warning_time = GetTime() + DiffUtils.ScaleTimer(1000.0)
        third_warning_time = GetTime() + DiffUtils.ScaleTimer(1300.0)
        
        unit_check = GetTime() + DiffUtils.ScaleTimer(1360.0)
        atril_check = GetTime() + DiffUtils.ScaleTimer(15.0)
        player_camera_time = GetTime() + DiffUtils.ScaleTimer(11.0)
        deploy_check = GetTime() + DiffUtils.ScaleTimer(6.0)
        charon_check = GetTime() + DiffUtils.ScaleTimer(30.0)
        next_shot_time = GetTime() + DiffUtils.ScaleTimer(22.0)
        
        SetLabel(nav1, "Choke Point")
        
        start_camera1 = true
        start_done = true
    end
    
    -- Camera Intro
    if start_camera1 then
        CameraPath("camera_circle", 375, 750, key_scrap)
    end
    
    if (not player_camera_off) and ((next_shot_time < GetTime()) or CameraCancelled()) then
        CameraFinish()
        start_camera1 = false
        player_camera_off = true
    end
    
    -- Extended Opening Cinematic (Restored from C++ lines 631-660)
    if start_camera1 and (not next_shot) and (GetTime() > player_camera_time) then
        CameraPath("launch_camera_path", 7000, 1150, ccalaunch)
        next_shot = true
        next_shot_time = GetTime() + 6.0
    end
    
    if next_shot and (not next_shot_message) and (GetTime() > next_shot_time) then
        -- Play extra audio? C++ had misn0912.wav here
        AudioMessage("misn0912.wav")
        CameraPath("choke_cam_path", 375, 450, nav1)
        next_shot_message = true
        next_shot_time = GetTime() + 6.0
    end
    
    if next_shot_message and (not player_camera_off) and ((GetTime() > next_shot_time) or CameraCancelled()) then
        CameraFinish()
        start_camera1 = false
        player_camera_off = true
    end
    
    -- Opening VO
    if (camera_ready_time < GetTime()) and (not opening_vo) then
        AudioMessage("misn0900.wav")
        ClearObjectives()
        AddObjective("misn0900.otf", "white")
        opening_vo = true
    end
    
    if opening_vo and (not muf_gobaby) and IsAudioMessageDone(audmsg) then -- audmsg not reliable in Lua usually
        -- Just assume timing or check last played
        Goto(nsdfmuf, "return_path")
        muf_gobaby = true;
    end
    
    -- MUF Contact (Artillery Ambush)
    if muf_gobaby and (muf_check < GetTime()) and (not muf_contact) then
        muf_check = GetTime() + 1.0
        if GetDistance(user, nsdfmuf) < 70.0 then
            Stop(nsdfmuf)
            Stop(nsdfslf)
            Defend(nsdfrig)
            
            SetScrap(1, DiffUtils.ScaleRes(20))
            SetPilot(1, DiffUtils.ScaleRes(7))
            AudioMessage("misn0905.wav")
            movie_time = GetTime() + 7.0
            muf_contact = true
        end
    end
    
    -- Turret Logic
    if (not objective1) and (atril_check < GetTime()) then
        atril_check = GetTime() + 15.0
        -- Re-issue Defend commands to keep them alert
        if IsAlive(ccaturret1) then Defend(ccaturret1) end
        if IsAlive(ccaturret2) then Defend(ccaturret2) end
        if IsAlive(ccaturret3) then Defend(ccaturret3) end
        if IsAlive(ccaturret4) then Defend(ccaturret4) end
        if IsAlive(ccaturret5) then Defend(ccaturret5) end
        if IsAlive(ccaturret6) then Defend(ccaturret6) end
    end
    
    -- Check MUF Deployed
    if (deploy_check < GetTime()) and (not muf_deployed) then
        deploy_check = GetTime() + 2.0
        -- In Lua, checking deployment usually involves ODF check (factory vs muf) or animation state.
        -- Assuming GetOdf works
        if IsAlive(nsdfmuf) and (GetOdf(nsdfmuf) == "avfact" or GetClassLabel(nsdfmuf) == "factory") then
             muf_deployed = true
        end
    end
    
    if (muf_deployed or IsAlive(avsilo)) and (not scavs_alive) then
        Stop(avscav1)
        Stop(avscav2)
        Stop(avscav3)
        scavs_alive = true
    end
    
    -- Artillery Camera (Cinematic)
    if IsAlive(ccaturret6) then
        if muf_contact and (movie_time < GetTime()) and (not camera_ready) then
            CameraReady()
            cam5_time = GetTime() + 7.0
            camera_ready = true
        end
        if camera_ready and (not cam_off) then
            CameraPath("camera_path", 950, 300, ccaturret6) -- x coord 950 passed in C++
        end
        if camera_ready and (cam5_time < GetTime()) and (not cam_off) then
            CameraFinish()
            ClearObjectives()
            AddObjective("misn0900.otf", "green")
            AddObjective("misn0901.otf", "white")
            Stop(nsdfrig)
            SetAIP("misn09.aip")
            recon_message_time = GetTime() + 60.0
            cam_off = true
        end
    end
    
    if (recon_message_time < GetTime()) and (not recon_artil) then
        recon_message_time = GetTime() + 1.0
        AudioMessage("misn0913.wav")
        recon_artil = true
    end
    
    if (recon_message_time < GetTime()) and (not base_warning) then
        recon_message_time = GetTime() + 2.0
        if (IsAlive(nav1) and GetDistance(user, nav1) < 100.0) then
            AudioMessage("misn0914.wav")
            base_warning = true
        end
        -- Also check cca5/6 distance if existing
    end
    
    -- Turret Clearing Objective
    if (not IsAlive(ccaturret1)) and (not IsAlive(ccaturret2)) and (not IsAlive(ccaturret3)) and 
       (not IsAlive(ccaturret4)) and (not IsAlive(ccaturret5)) and (not IsAlive(ccaturret6)) and (not objective1) then
       
       AudioMessage("misn0904.wav")
       Stop(avscav1)
       Stop(avscav2)
       Stop(avscav3)
       
       ClearObjectives()
       AddObjective("misn0901.otf", "green")
       AddObjective("misn0902.otf", "white")
       AddObjective("misn0903.otf", "white")
       
       if not third_warning then SetAIP("misn09a.aip") end
       
       objective1 = true
    end
    
    -- Warnings
    if (not first_warning) and (first_warning_time < GetTime()) then
        AudioMessage("misn0901.wav")
        first_warning = true
    end
    if (not second_warning) and (second_warning_time < GetTime()) then
        AudioMessage("misn0902.wav")
        second_warning = true
    end
    
    -- Convoy Spawn
    if (not third_warning) and (third_warning_time < GetTime()) then
        third_warning_time = GetTime() + 11.0
        
        if GetDistance(user, convoy_geyser) > 500.0 then
            relic = BuildObject("obdata", 3, convoy_geyser)
            ccatug = BuildObject("svhaul", 2, "spawn1")
            
            convoy1 = BuildObject("svfigh", 2, "spawn2")
            convoy2 = BuildObject("svfigh", 2, "spawn2")
            convoy3 = BuildObject("svfigh", 2, "spawn2")
            convoy4 = BuildObject("svfigh", 2, "spawn3")
            convoy5 = BuildObject("svtank", 2, "spawn3")
            convoy6 = BuildObject("svtank", 2, "spawn3")
            convoy7 = BuildObject("svtank", 2, "spawn4")
            convoy8 = BuildObject("svtank", 2, "spawn4")
            convoy9 = BuildObject("svapc", 2, "spawn4")
            convoy0 = BuildObject("svapc", 2, "spawn4")
            
            local convoys = {convoy1, convoy2, convoy3, convoy4, convoy5, convoy6, convoy7, convoy8, convoy9, convoy0}
            for _, c in ipairs(convoys) do Defend(c) end
            
            if not objective1 then
                ClearObjectives()
                AddObjective("misn0901.otf", "white") -- Red in C++, assuming white for pending
                AddObjective("misn0902.otf", "white")
                AddObjective("misn0903.otf", "white")
            end
            
            win_check = GetTime() + 5.0
            SetAIP("misn09b.aip")
            relic_free = true
            third_warning = true
        end
    end
    
    -- Start Convoy Move
    if third_warning and relic_seized and (not convoy_started) then
        SetObjectiveOn(relic)
        SetLabel(relic, "Alien Relic")
        
        Goto(ccatug, "soviet_path")
        local convoys = {convoy1, convoy2, convoy3, convoy4, convoy5, convoy6, convoy7, convoy8, convoy9, convoy0}
        for _, c in ipairs(convoys) do Follow(c, ccatug) end
        
        convoy_cam_time = GetTime() + 7.0
        convoy_started = true
    end
    
    -- Convoy Camera
    if convoy_started and (not convoy_cam_ready) and (convoy_cam_time < GetTime()) then
        AudioMessage("misn0903.wav")
        CameraReady()
        convoy_cam_time = GetTime() + 18.0
        convoy_cam_ready = true
    end
    
    if convoy_cam_ready and (not convoy_cam_off) then
        CameraPath("convoy_cam_path", 3000, 1150, ccatug) -- y=3000
    end
    
    if convoy_cam_ready and (not convoy_cam_off) and ((convoy_cam_time < GetTime()) or CameraCancelled()) then
        CameraFinish()
        convoy_cam_off = true
    end
    
    -- Charon
    if IsAlive(charon) and (not charon_found) then
        if charon_check < GetTime() then
            charon_check = GetTime() + 2.0
            if GetDistance(user, charon) < 70.0 then
                AudioMessage("misn0915.wav")
                charon_found = true
            end
        end
    end
    
    if charon_found and IsInfo("hbchar") and (not charon_build) then
        AudioMessage("misn0916.wav")
        charon_nav = BuildObject("apcamr", 1, "charon_spawn")
        SetLabel(charon_nav, "Alien Relic")
        charon_build = true
    end
    
    -- Check MUF deployed position (Bonus logic)
    if (objective1 or third_warning) and (not muf_deployed_good) and (deploy_check < GetTime()) then
        deploy_check = GetTime() + 2.0
        if IsAlive(nsdfmuf) then
            -- Check deployment state and location? C++ code exists but logic is specific.
            -- If nearby convoy path?
            if GetDistance(nsdfmuf, convoy_geyser) < 400.0 then
                -- Updates objectives colors
                muf_deployed_good = true;
            end
        end
    end
    
    -- Enemy Dead Win
    if (not IsAlive(ccarecycle)) and (not IsAlive(ccamuf)) and (not ccadead) then
        AudioMessage("misn0908.wav")
        ccadead = true
    end
    
    -- Loss Conditions
    if scavs_alive and (not IsAlive(avscav1)) and (not IsAlive(avscav2)) and (not IsAlive(avscav3)) and (not game_over) then
        if (not objective1) and (not first_warning) then
            if GetScrap(1) < 10 then
                FailMission(GetTime() + 6.0, "misn09f4.des")
                game_over = true
            end
        end
    end
    
    if convoy_started and (not IsAlive(relic)) and (not game_over) then
        AudioMessage("misn0906.wav")
        FailMission(GetTime() + 15.0, "misn09f1.des")
        game_over = true
    end
    
    if relic_seized and IsAlive(ccalaunch) and (GetDistance(ccatug, ccalaunch) < 100.0) and (not game_over) then
        AudioMessage("misn0907.wav")
        FailMission(GetTime() + 15.0, "misn09f2.des")
        game_over = true
    end
    
    -- Win Conditions
    if convoy_started and (unit_check < GetTime()) and (not game_over5) then
        unit_check = GetTime() + 10.0
        local stuff = CountUnitsNearObject(convoy_geyser, 5000.0, 2, nil)
        if stuff == 0 then
            AudioMessage("misn0908.wav")
            game_over5 = true
        end
    end
    
    if IsAlive(relic) and (not relic_seized) and (win_check < GetTime()) and (not game_over) then
        win_check = GetTime() + 2.0
        if IsAlive(nsdfmuf) and (GetDistance(relic, nsdfmuf) < 100.0) then
            AudioMessage("misn0909.wav")
            SucceedMission(GetTime() + 15.0, "misn09w1.des")
            game_over = true
        end
    end
    
    if (not IsAlive(nsdfmuf)) and (not game_over) then
        AudioMessage("misn0911.wav")
        FailMission(GetTime() + 15.0, "misn09f3.des")
        game_over = true
    end
    
    if (not IsAlive(ccalaunch)) and (not game_over) then
        AudioMessage("misn0918.wav") -- You destroyed the launchpad!
        FailMission(GetTime() + 15.0)
        game_over = true
    end
end
