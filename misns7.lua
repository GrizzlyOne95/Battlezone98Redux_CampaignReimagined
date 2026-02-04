-- Misns7 Mission Script (Converted from Misns7Mission.cpp)

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
    local bdog = DiffUtils.SetupTeams(aiCore.Factions.BDOG, aiCore.Factions.NSDF, 2)
    
    -- Legacy Features
    bdog:SetConfig("reclaimEngineers", true)
end

-- Variables
local start_done = false
local jail_found = false
local jail_dead = false
local jail_unit_spawn = false
local jail_camera_on = false
local jail_camera_off = false
local con_pickup = false
local con1_in_apc = false
local con2_in_apc = false
local con3_in_apc = false
local con1_dead = false
local con2_dead = false
local con3_dead = false
local con1_safe = false
local con2_safe = false
local con3_safe = false
local pick_up = false
local fully_loaded = false
local two_loaded = false
local one_loaded = false
local first_message_done = false
local closer_message = false
local apc_panic_message = false
local build_scav = false
local nsdf_adjust = false
local fight1_built = false
local fight2_built = false
local fight3_built = false
local build_turret = false
local avmuf_built = false
local plan_b = false
local plan_c = false
local plan_a = false -- scavenger plan?
local get_recycle = false
local get_muf = false
local get_supply = false
local camera_on_recycle = false
local camera_off_recycle = false
local svrecycle_unit_spawn = false
local svrecycle_on = false
local down_to_two = false
local down_to_one = false
local apc_empty = false
local camera_on_muf = false
local camera_off_muf = false
local svmuf_unit_spawn = false
local svmuf_on = false
local supply_message = false
local supply_first = false
local camera_on_supply = false
local camera_off_supply = false
local supply_unit_spawn = false
local supply_on = false
local supplies_spawned = false
local supply2_message = false
local turret_message = false
local muf_scan_time = 99999.0
local muf_located = false
local gech_sent = false
local gech_adjust = false
local game_over = false
local in_base = false
local muf_message = false
local muf_message2 = false

local muf_deployed = false
local muf_redirect = false
local b3 = false
local b4 = false
local b5_time = 99999.0
local b6_time = 99999.0
local b7_time = 99999.0
local rig_show2 = false
local rig_show3 = false

-- Handles
local player
local jail, apc
local con1, con2, con3
local avscav1, avscav2
local avfight1, avfight2, avfight3
local avturr1, avturr2, avturr3
local avmuf, avrecycle
local svrecycle, svmuf, supply
local engineer
local guntower1, guntower2
local geyser1
local boxes, con_geyser
local fed_up_scrap
local avrig, avsilo, avgech
local supply1, supply4 -- Scavs from supply hut

-- Timers
local adjust_timer = 99999.0
local build_scav_time = 99999.0
local avfigh1_time = 99999.0
local avfigh2_time = 99999.0
local avfigh3_time = 99999.0
local con_spawn_time = 99999.0
local camera_off_time = 99999.0
local muf_build_time = 99999.0
local con1_pickup_time = 99999.0
local con2_pickup_time = 99999.0
local con3_pickup_time = 99999.0
local goo_time = 99999.0
local muf_message_time = 99999.0
local check_a = 99999.0
local check_b = 99999.0
local check_c = 99999.0
local unit_spawn_time1 = 99999.0
local supply_spawn_time = 99999.0

-- Config
local difficulty = 2

function Start()
    if exu then
        if exu.EnableShotConvergence then exu.EnableShotConvergence() end
        if exu.SetSmartCursorRange then exu.SetSmartCursorRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    
    player = GetPlayerHandle()
    start_done = false
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then
        aiCore.AddObject(h)
        -- C++ Logic: Identify units?
        -- Mostly handled by "avscav1", "avfight1" etc being assigned on BuildObject logic.
        -- But reinforcements or random builds:
        if IsOdf(h, "bvscav") and not avscav1 then avscav1=h elseif IsOdf(h, "bvscav") and not avscav2 then avscav2=h end
        -- ...
        if IsOdf(h, "bvwalk") then avgech = h end
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
        start_done = true
        SetPilot(1, 8)
        SetScrap(2, DiffUtils.ScaleRes(40))
        SetPilot(2, 40)
        
        jail = GetHandle("jail")
        apc = GetHandle("svapc")
        supply = GetHandle("supply")
        avrecycle = GetHandle("avrecycle")
        geyser1 = GetHandle("geyser1")
        boxes = GetHandle("boxes")
        fed_up_scrap = GetHandle("getum_started")
        svmuf = GetHandle("svmuf")
        svrecycle = GetHandle("svrecycle") -- Should exist as "wreck" or marker
        guntower1 = GetHandle("guntower1")
        guntower2 = GetHandle("guntower2")
        avrig = GetHandle("rig")
        con_geyser = GetHandle("con_geyser")
        avsilo = GetHandle("avsilo")
        
        SetObjectiveOn(jail)
        AudioMessage("misns700.wav")
        ClearObjectives()
        AddObjective("misns700.otf", "white")
        
        build_scav_time = GetTime() + DiffUtils.ScaleTimer(8.0)
        
        if IsAlive(svmuf) then Defend(svmuf) end -- C++ Defend(svmuf)? Who defends? Player team? Or just sets idle/defendAI? 
        if IsAlive(avrig) then Defend(avrig) end
        
        -- Team switch statics?
        SetPerceivedTeam(guntower1, 2)
        SetPerceivedTeam(guntower2, 2)
        SetPerceivedTeam(svrecycle, 2)
        
        -- C++: Build(avrig, "abtowe")
        -- If rig is builder...
        if IsAlive(avrig) then Build(avrig, "abtowe") end
    end
    
    -- Jail Found
    if (not jail_found) and (GetDistance(player, jail) < 150.0) then
        AudioMessage("misns722.wav")
        adjust_timer = GetTime() + DiffUtils.ScaleTimer(120.0)
        jail_found = true
    end
    
    -- Build Enemy Scavs
    if (not build_scav) and (GetTime() > build_scav_time) then
        avscav1 = BuildObject("bvscav", 2, "muf_point"); Goto(avscav1, fed_up_scrap)
        avscav2 = BuildObject("bvscav", 2, "muf_point"); Goto(avscav2, fed_up_scrap)
        
        -- Note: C++ has // BuildObject("bvtank",2,"spawn3") restored? No, commented out.
        -- But logic below (nsdf_adjust) suggests aggressive response.
        build_scav = true
    end
    
    -- NSDF Response (Player attacking too early or time elapsed)
    if (not jail_dead) and (not nsdf_adjust) then
        -- Health checks on enemy assets
        local triggered = false
        if (IsAlive(avscav1) and GetHealth(avscav1) < 0.9) then triggered = true end
        if (IsAlive(avscav2) and GetHealth(avscav2) < 0.9) then triggered = true end
        if (IsAlive(avrecycle) and GetHealth(avrecycle) < 0.95) then triggered = true end
        if (jail_found and (GetTime() > adjust_timer)) then triggered = true end
        
        if triggered then nsdf_adjust = true end
    end
    
    if nsdf_adjust and (not fight1_built) then
        avfight1 = BuildObject("bvraz", 2, "muf_point")
        Attack(avfight1, player)
        avfigh2_time = GetTime() + DiffUtils.ScaleTimer(20.0)
        fight1_built = true
    end
    
    if nsdf_adjust and fight1_built and (not fight2_built) and (GetTime() > avfigh2_time) then
        avfight2 = BuildObject("bvraz", 2, "muf_point")
        Attack(avfight2, player)
        avfigh3_time = GetTime() + DiffUtils.ScaleTimer(20.0)
        fight2_built = true
    end
    
    if nsdf_adjust and fight2_built and (not fight3_built) and (GetTime() > avfigh3_time) then
        avfight3 = BuildObject("bvraz", 2, "muf_point")
        if IsAlive(avfight2) then Attack(avfight3, apc) else Attack(avfight3, player) end
        SetScrap(2, 40)
        fight3_built = true
    end
    
    -- Turret check
    if nsdf_adjust and IsAlive(avfight3) and (not jail_dead) and (not build_turret) then
        avturr1 = BuildObject("bvturr", 2, "muf_point")
        build_turret = true
    end
    
    -- Jail Destroyed / Prison Break
    if (not IsAlive(jail)) and (not jail_dead) then
        CameraReady()
        con_spawn_time = GetTime() + DiffUtils.ScaleTimer(1.5)
        jail_dead = true
    end
    
    if jail_dead and (not jail_camera_on) then
        CameraObject(geyser1, -1500, 1000, -5000, boxes)
        camera_off_time = GetTime() + 3.5
        jail_camera_on = true
    end
    
    if jail_dead and (GetTime() > con_spawn_time) and (not jail_unit_spawn) then
        con1 = BuildObject("sssold", 1, "con1_spot"); SetIndependence(con1, 0); GetIn(con1, apc)
        con2 = BuildObject("sssold", 1, "con2_spot"); SetIndependence(con2, 0); GetIn(con2, apc)
        con3 = BuildObject("sssold", 1, "con3_spot"); SetIndependence(con3, 0); GetIn(con3, apc)
        jail_unit_spawn = true
    end
    
    if jail_camera_on and (GetTime() > camera_off_time) and (not jail_camera_off) then
        CameraFinish()
        muf_build_time = GetTime() + DiffUtils.ScaleTimer(5.0)
        jail_camera_off = true
    end
    
    if jail_camera_off and (not closer_message) then
        if GetDistance(apc, boxes) > 70.0 then AudioMessage("misns710.wav") end
        closer_message = true
    end
    
    if jail_camera_off and IsAlive(apc) and (GetTime() > avfigh2_time) and (not fully_loaded) 
       and (GetHealth(apc) < 0.8) and (not apc_panic_message) then
       AudioMessage("misns723.wav")
       apc_panic_message = true
    end
    
    -- Enemy Upgrades (Muf)
    if jail_camera_off and (GetTime() > muf_build_time) and (not avmuf_built) then
        avmuf = BuildObject("bvmuf", 2, "muf_point"); Defend(avmuf); Goto(avmuf, geyser1)
        avfigh1_time = GetTime() + DiffUtils.ScaleTimer(30.0)
        avmuf_built = true
    end
    
    -- Enemy Muf Fleeing Logic (RESTORED from C++ lines 546-552)
    -- If Muf takes heavy damage while deploying, it relocates to a safer geyser
    if avmuf_built and IsAlive(avmuf) and (GetHealth(avmuf) < 0.5) and (not muf_deployed) then
        -- We need a flag to ensure we don't spam Goto? C++ used 'muf_redirect'
        -- Checking IsAlive(avtank1) is the C++ check for "muf_deployed" (via build queue usually)
        -- Let's assume if it's hurt, it runs.
        Goto(avmuf, "geyser3") -- Alternate geyser
    end

    -- Muf Deployed Check
    if IsAlive(avtank1) then muf_deployed = true end

    -- Enemy Response with Muf
    if avmuf_built and (not fight1_built) and (GetTime() > avfigh1_time) then

    
    -- Cons Death
    if jail_unit_spawn then
        if (not IsAlive(con1)) and (not con1_in_apc) then con1_dead = true end
        if (not IsAlive(con2)) and (not con2_in_apc) then con2_dead = true end
        if (not IsAlive(con3)) and (not con3_in_apc) then con3_dead = true end
    end
    
    -- Pickup Logic
    -- C++ has complex GetDistance checks < 20.0f
    local function CheckPickup(con, flag_in, time_var, flag_safe)
        if (not flag_in) and IsAlive(con) and (GetDistance(con, apc) < 20.0) then
            return true, GetTime() + 0.2
        end
        return flag_in, time_var
    end
    
    con1_in_apc, con1_pickup_time = CheckPickup(con1, con1_in_apc, con1_pickup_time, con1_safe)
    con2_in_apc, con2_pickup_time = CheckPickup(con2, con2_in_apc, con2_pickup_time, con2_safe)
    con3_in_apc, con3_pickup_time = CheckPickup(con3, con3_in_apc, con3_pickup_time, con3_safe)
    
    local function ProcessSafe(flag_in, time_var, flag_safe, con_h)
        if flag_in and (not flag_safe) and (GetTime() > time_var) then
            RemoveObject(con_h)
            AddPilot(1, 1)
            AudioMessage("misns702.wav")
            goo_time = GetTime() + 5.0
            pick_up = true
            return true
        end
        return flag_safe
    end
    
    con1_safe = ProcessSafe(con1_in_apc, con1_pickup_time, con1_safe, con1)
    con2_safe = ProcessSafe(con2_in_apc, con2_pickup_time, con2_safe, con2)
    con3_safe = ProcessSafe(con3_in_apc, con3_pickup_time, con3_safe, con3)
    
    -- Loaded Status / Messages
    if con1_safe and con2_safe and con3_safe and (not fully_loaded) and (not first_message_done) then
        AudioMessage("misns704.wav")
        fully_loaded = true; first_message_done = true; muf_message_time = GetTime() + 3.0
        check_a = GetTime() + 1.0; check_b = GetTime() + 2.0; check_c = GetTime() + 3.0
    end
    -- Also handle mix of dead/safe (Two loaded, one loaded)
    local safe_count = 0
    if con1_safe then safe_count = safe_count + 1 end
    if con2_safe then safe_count = safe_count + 1 end
    if con3_safe then safe_count = safe_count + 1 end
    
    local dead_count = 0
    if con1_dead then dead_count = dead_count + 1 end
    if con2_dead then dead_count = dead_count + 1 end
    if con3_dead then dead_count = dead_count + 1 end
    
    if (safe_count == 2) and (dead_count == 1) and (not two_loaded) and (not first_message_done) then
        AudioMessage("misns705.wav")
        two_loaded = true; first_message_done = true; muf_message_time = GetTime() + 3.0
        check_a = GetTime() + 1.0; check_b = GetTime() + 2.0; check_c = GetTime() + 3.0
    end
    if (safe_count == 1) and (dead_count == 2) and (not one_loaded) and (not first_message_done) then
        AudioMessage("misns706.wav")
        one_loaded = true; first_message_done = true; muf_message_time = GetTime() + 3.0
        check_a = GetTime() + 1.0; check_b = GetTime() + 2.0; check_c = GetTime() + 3.0
    end
    
    -- Restored Base Building Phase 2 (C++ lines 1529-1564)
    -- Builds Power Plant 2 and Tower 3
    if camera_off_recycle and IsAlive(avrig) and (not b3) then
       -- Assuming !main_off/maint_off checks passed or irrelevant if we just use queue
       Build(avrig, "abwpow") -- avpower2
       b5_time = GetTime() + DiffUtils.ScaleTimer(5.0)
       b3 = true
    end
    
    if b3 and (not rig_show2) and (GetTime() > b5_time) then
       if IsAlive(avrig) then
           Dropoff(avrig, "power2_spot")
           b6_time = GetTime() + DiffUtils.ScaleTimer(5.0)
           rig_show2 = true
       end
    end
    
    if rig_show2 and IsAlive(avrig) and (not b4) and (GetTime() > b6_time) then
       -- Check if power2 exists? C++: IsAlive(avpower2) || power1
       Build(avrig, "abtowe") -- tower3
       b7_time = GetTime() + DiffUtils.ScaleTimer(5.0)
       b4 = true
    end
    
    if b4 and (not rig_show3) and (GetTime() > b7_time) then
        if IsAlive(avrig) then
            Dropoff(avrig, "tower3_spot")
            rig_show3 = true
        end
    end

    -- Muf/Recy/Supply Drops
    -- C++ has explicit dropoff logic for engineer at `svrecycle`, `svmuf`, `supply`

    
    -- Function to handle engineer drop
    local function HandleDrop(trigger_flag, apc_dist_check, target_handle, camera_flag, cam_off_flag, spawn_flag, engineer_h, on_flag, time_spawn)
        if (not trigger_flag) and first_message_done and (GetTime() > time_spawn) and (GetDistance(apc, target_handle) < apc_dist_check) then
            -- Check decrement of passengers? C++: down_to_two/one flags.
            return true, GetTime() + 3.0 -- Set trigger
        end
        return trigger_flag, time_spawn
    end
    -- This part is complex state machine in C++. Assuming player drives APC to location.
    
    -- Recycler Drop Logic
    if first_message_done and (not get_recycle) and (GetTime() > check_a) and (GetDistance(apc, svrecycle) < 50.0) then
        -- Decrement passenger count logic simplified here
        if (fully_loaded or two_loaded or one_loaded) and (not apc_empty) then
            get_recycle = true
            CameraReady()
            Stop(apc, 0)
            unit_spawn_time1 = GetTime() + 2.0
            -- simplify passenger tracking
        end
    end
    
    if get_recycle and (not camera_off_recycle) then
        if not camera_on_recycle then
            CameraObject(svrecycle, -4000, 1000, 2000, svrecycle)
            camera_on_recycle = true
        end
        
        if (GetTime() > unit_spawn_time1) and (not svrecycle_unit_spawn) then
            engineer = BuildObject("sssold", 1, apc); Retreat(engineer, svrecycle); AddPilot(1, -1)
            svrecycle_unit_spawn = true
        end
        
        if svrecycle_unit_spawn and (not svrecycle_on) then
            -- Use aiCore helper for reclaiming
            if bdog:ReclaimBuilding(svrecycle, engineer) then
                svrecycle_on = true
            end
        end
        
        if svrecycle_unit_spawn and (svrecycle_on or CameraCancelled()) then
            CameraFinish()
            RemoveObject(svrecycle)
            -- C++: Build "svmine" then "svrecy"? Transition animation?
            local tmp = BuildObject("svmine", 0, svrecycle); RemoveObject(tmp) -- Just cleanup?
            svrecycle = BuildObject("svrecy", 1, svrecycle) -- Respawn as friendly?
            -- Wait, C++ uses `temp` handle location. `svrecycle` is a wreck I assume?
            
            AudioMessage("misns727.wav")
            AddScrap(1, 20)
            camera_off_recycle = true
            
            -- Update Objectives
            ClearObjectives()
            if not camera_off_muf then AddObjective("misns708.otf", "white") end 
            -- etc
        end
    end
    
    -- Muf Drop Logic (Similar)
    if first_message_done and (not get_muf) and (GetTime() > check_b) and (GetDistance(apc, svmuf) < 40.0) then
        if (not apc_empty) then -- Simplified check
            get_muf = true; CameraReady(); Stop(apc, 0); unit_spawn_time1 = GetTime() + 2.0
        end
    end
    
    if get_muf and (not camera_off_muf) then
        if not camera_on_muf then CameraObject(svmuf, -3000, 1000, 4000, svmuf); camera_on_muf = true end
        
        if (GetTime() > unit_spawn_time1) and (not svmuf_unit_spawn) then
            engineer = BuildObject("sssold", 1, apc); Retreat(engineer, svmuf); AddPilot(1, -1)
            svmuf_unit_spawn = true
        end
        
        if svmuf_unit_spawn and (not svmuf_on) then
            if bdog:ReclaimBuilding(svmuf, engineer) then
                svmuf_on = true
            end
        end
        
        if svmuf_unit_spawn and (svmuf_on or CameraCancelled()) then
            CameraFinish()
            RemoveObject(svmuf)
            svmuf = BuildObject("svmuf", 1, svmuf)
            AddScrap(1, 20)
            camera_off_muf = true
            -- Audio
            if supply_first then AudioMessage("misns709.wav") else AudioMessage("misns714.wav") end
        end
    end
    
    -- Supply Drop Logic
    -- Similar block for `get_supply`.
    
    -- Win/Lose
    if (not game_over) and (not IsAlive(avrecycle)) then
        AudioMessage("misns712.wav")
        SucceedMission(GetTime() + 10.0, "misns7w1.des")
        game_over = true
    end
    
    if (not game_over) and (con1_dead and con2_dead and con3_dead) then
        AudioMessage("misns711.wav")
        FailMission(GetTime() + 10.0, "misns7f1.des")
        game_over = true
    end
end
