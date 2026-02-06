-- Misn07 Mission Script (Converted from Misn07Mission.cpp)

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
    local caa = DiffUtils.SetupTeams(aiCore.Factions.NSDF, aiCore.Factions.CCA, 2)
    
    -- Legacy Features from Review
    caa:SetConfig("dynamicMinefields", true)
    caa:SetConfig("minefields", {"volcano_geyz1", "volcano_geyz2", "radar_geyser"})
end

-- Variables
local start_done = false
local out_of_car = false
local alarm_on = false
local start_evac = false
local unit_spawn = false
local recon_message1 = false
local recon_message2 = false
local jump_cam_spawned = false
local rookie_moved = false
local rendezvous = false
local first_objective = false
local second_objective = false
local turret_move = false
local next_mission = false
local rookie_lost = false -- Used slightly differently in Lua, aligned w/ keeping Rookie safe
local mine_pathed = false
local retreat_success = false
local detected_message = false
local fighter_moved = false
local vehicle_stolen = false
local trigger1 = false
local alarm_special = false
local alarm_sound = false
local rookie_removed = false
local forces_enroute = false
local camera_ready = false
local camera1_on = false
local camera2_on = false
local camera3_on = false
local camera4_on = false
local camera_off = false
local camera2_oned = false
local camera3_oned = false
local game_over = false
local opening_vo = false
local utah_found = false
local rookie_found = false
local rookie_found = false
local tower_warning = false
local tower_warning = false
local alarm_loop = false
local radar_shot1 = false
local radar_shot2 = false
local radar_camera_off = false
local radar_next_shot_time = 0.0
local parachute_camera_ready = false
local parachute_camera_off = false
local parachute_camera_time = 0.0
local test_range_found = false
local mine_path_active = false
local mag_show_started = false
local mag_show_done = false
local rookie_at_cinema = false
local cinema_tank_spawned = false
local cinema_turret_spawned = false
local first_camera_ready = false
local first_camera_off = false
local first_camera_time = 99999.0

-- Timers
local unit_spawn_time = 999999.0
local recon_message_time = 999999.0
local rookie_move_time = 999999.0
local rookie_rendezvous_time = 999999.0
local patrol2_move_time = 999999.0
local alarm_time = 999999.0
local alarm_timer = 999999.0
local rendezous_check = 999999.0
local alarm_check = 999999.0
local rookie_remove_time = 999999.0
local runner_check = 999999.0
local radar_camera_time = 999999.0
local next_mission_time = 999999.0
local tower_check = 999999.0

-- Handles
local user, nsdfrecycle, nsdfmuf, rookie, jump_cam
local jump_geyz, remove_geyz, mine_geyz
local pilot1, pilot2, pilot3, pilot4, pilot5
local ccaguntower1, ccaguntower2, ccacomtower
local powrplnt1, powrplnt2, barrack1, barrack2
local nav1, nav3 -- nav1 = Outpost Cam, nav3 = Rendezvous Point
local wingman1, wingman2, wingtank1, wingtank2, wingtank3, wingturret1, wingturret2
local nsdfarmory, svapc
local ccarecycle, ccamuf, ccaslf, basepowrplnt1, pbaseowrplnt2
local ccabaseguntower1, ccabaseguntower2
local patrol1_1, patrol1_2
local svpatrol1_1, svpatrol1_2, svpatrol2_1, svpatrol2_2, svpatrol3_1, svpatrol3_2, svpatrol4_1, svpatrol4_2
local guard_turret1, guard_turret2
local spawn_turret1, spawn_turret2
local parked1, parked2, parked3, parkturret1, parkturret2
local spawn_point, fence, tank_spawn
local radar_geyser, camera_geyser, show_geyser
local new_tank1, new_tank2
local turret1_spot -- Path point
local test_range_cam, mine_beacon1, mine_beacon2, mine_beacon3, mine_beacon4
local mag_tank, mag_turret, mag_target
local mine_geyser, nav_mine

local difficulty = 2

function Start()
    if exu then
        if exu.EnableShotConvergence then exu.EnableShotConvergence() end
        if exu.SetSmartCursorRange then exu.SetSmartCursorRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    
    start_done = false
    opening_vo = false
    -- Cut Intro Cinematic
    first_camera_ready = false
    first_camera_off = false
    first_camera_time = 99999.0
    rendezous_check = GetTime() + 10.0 -- Delayed to allow intro
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
    
    -- Initial Setup
    if not start_done then
        nav3 = GetHandle("cam3")
        SetLabel(nav3, "Rendezvous Point")
        
        SetScrap(1, DiffUtils.ScaleRes(10))
        
        ccacomtower = GetHandle("radar_array")
        SetObjectiveOff(ccacomtower)
        
        patrol1_1 = GetHandle("svfigh1")
        patrol1_2 = GetHandle("svfigh2")
        Patrol(patrol1_1, "patrol_path3")
        Patrol(patrol1_2, "patrol_path3")
        
        svpatrol3_1 = GetHandle("svpatrol3_1")
        svpatrol3_2 = GetHandle("svpatrol3_2")
        Patrol(svpatrol3_1, "patrol_path1")
        Patrol(svpatrol3_2, "patrol_path1")
        
        svpatrol4_1 = GetHandle("svpatrol4_1")
        svpatrol4_2 = GetHandle("svpatrol4_2")
        Patrol(svpatrol4_1, "patrol_path2")
        Patrol(svpatrol4_2, "patrol_path2")
        
        wingtank2 = GetHandle("avtank2")
        wingtank3 = GetHandle("avtank3")
        SetIndependence(wingtank2, 0)
        Stop(wingtank2)
        SetPerceivedTeam(wingtank2, 1) -- Set perceived team to player
        SetIndependence(wingtank3, 0)
        Stop(wingtank3)
        SetPerceivedTeam(wingtank3, 1)
        
        svpatrol2_1 = GetHandle("svpatrol2_1")
        svpatrol2_2 = GetHandle("svpatrol2_2")
        Stop(svpatrol2_1, 1)
        Stop(svpatrol2_2, 1)
        
        rendezous_check = GetTime() + DiffUtils.ScaleTimer(9.0)
        patrol2_move_time = GetTime() + DiffUtils.ScaleTimer(121.0)
        alarm_check = GetTime() + DiffUtils.ScaleTimer(27.0)
        
        -- Handles
        jump_geyz = GetHandle("volcano_geyz1")
        remove_geyz = GetHandle("volcano_geyz2")
        ccaguntower1 = GetHandle("sgtower1")
        ccaguntower2 = GetHandle("sgtower2")
        
        powrplnt1 = GetHandle("power1")
        barrack1 = GetHandle("hut1")
        barrack2 = GetHandle("hut2")
        
        wingman1 = GetHandle("avfigh1")
        wingtank1 = GetHandle("avtank1")
        wingturret1 = GetHandle("avturret1")
        wingturret2 = GetHandle("avturret2")
        
        ccarecycle = GetHandle("svrecycler")
        ccamuf = GetHandle("svmuf")
        basepowrplnt1 = GetHandle("svbasepower1")
        
        guard_turret1 = GetHandle("svturret1")
        guard_turret2 = GetHandle("svturret2")
        
        parked1 = GetHandle("parked1")
        parked2 = GetHandle("parked2")
        parked3 = GetHandle("parked3")
        parkturret1 = GetHandle("pturret1")
        parkturret2 = GetHandle("pturret2")
        svapc = GetHandle("parked_svapc")
        
        radar_geyser = GetHandle("radar_geyser")
        camera_geyser = GetHandle("camera_geyser")
        -- show_geyser = GetHandle("show_geyser")
        
        -- Path points handled implicitly by string in Lua
        turret1_spot = "turret1_spot"
        
        start_done = true
    end
    
    -- Cut Intro Cinematic
    if not first_camera_ready then
        CameraReady()
        AudioMessage("misn0700.wav") -- Moved here from below
        opening_vo = true -- Handled here
        first_camera_time = GetTime() + 10.0
        first_camera_ready = true
        
        -- Try to play the path if it exists, otherwise orbit
        -- C++: CameraPath("start_camera", x, 950, user)
        -- We'll try a single clean call
        CameraPath("start_camera", 2000, 950, user)
    end
    
    if first_camera_ready and (not first_camera_off) and ((first_camera_time < GetTime()) or CameraCancelled()) then
        CameraFinish()
        first_camera_off = true
    end
    
    -- Opening VO (Fallback if intro skipped or logic flows through)
    -- Modified to respect intro
    if (not opening_vo) and start_done and (rendezous_check < GetTime()) then
        rendezous_check = GetTime() + 15.0
        AudioMessage("misn0700.wav")
        ClearObjectives()
        AddObjective("misn0700.otf", "white")
        opening_vo = true
    end
    
    -- Patrol 2 Move logic
    if start_done and (patrol2_move_time < GetTime()) and (not rendezvous) and IsAlive(svpatrol2_1) and IsAlive(svpatrol2_2) and (not fighter_moved) then
        Patrol(svpatrol2_1, "patrol_path1")
        Patrol(svpatrol2_2, "patrol_path1")
        fighter_moved = true
    end
    
    -- Rendezvous Logic
    if not first_objective then
        if (rendezous_check < GetTime()) and (not rendezvous) and (not alarm_on) then
            rendezous_check = GetTime() + 3.0
            
            local dist2 = (IsAlive(wingtank2) and GetDistance(user, wingtank2)) or 9999.0
            local dist3 = (IsAlive(wingtank3) and GetDistance(user, wingtank3)) or 9999.0
            
            if (dist2 < 150.0) or (dist3 < 150.0) then
                AudioMessage("misn0701.wav")
                
                if IsAlive(wingtank2) then
                    new_tank1 = BuildObject("avtank", 1, wingtank2)
                    RemoveObject(wingtank2) -- Replace dummy with real unit
                end
                if IsAlive(wingtank3) then
                    new_tank2 = BuildObject("avtank", 1, wingtank3)
                    RemoveObject(wingtank3)
                end
                
                ClearObjectives()
                AddObjective("misn0700.otf", "green")
                AddObjective("misn0701.otf", "white")
                
                recon_message_time = GetTime() + DiffUtils.ScaleTimer(240.0)
                runner_check = GetTime() + DiffUtils.ScaleTimer(6.0)
                patrol2_move_time = GetTime() + DiffUtils.ScaleTimer(60.0) -- Delay patrol movement
                
                nav1 = BuildObject("apcamr", 1, "cam1_spawn")
                SetLabel(nav1, "CCA Outpost")
                tower_check = GetTime() + 10.0
                rendezvous = true
            end
        end
        
        if rendezvous and (patrol2_move_time < GetTime()) and (not fighter_moved) then
            if IsAlive(svpatrol2_1) then Attack(svpatrol2_1, user) end
            if IsAlive(svpatrol2_2) then Attack(svpatrol2_2, user) end
            fighter_moved = true
        end
        
        -- Tower Warning
        if IsAlive(nav1) and (tower_check < GetTime()) and (not tower_warning) then
            tower_check = GetTime() + 4.0
            if GetDistance(user, nav1) < 90.0 then
                AudioMessage("misn0716.wav")
                tower_warning = true
            end
        end
    end
    
    -- Rookie Script
    if (not first_objective) and (not alarm_on) and (not out_of_car) then
        -- Rookie Script: Phase 1 - Test Range & Mines
        if rendezvous and (not test_range_found) and (not jump_cam_spawned) and ((recon_message_time < GetTime()) or tower_warning) then
            recon_message_time = GetTime() + 10.0
            mine_geyser = "volcano_geyz2" -- "mine_geyz" in C++
            
            -- Trigger Test Range Discovery (Delayed start)
            if (GetDistance(user, mine_geyz) > 300.0) then 
                AudioMessage("misn0703.wav") -- "Found a Soviet Test Range"
                
                -- Spawn Rookie at Test Range Entrance if not exists
                if not IsAlive(rookie) then
                    rookie = BuildObject("avfigh", 1, "volcano_geyz1") -- Spawn near start
                    SetLabel(rookie, "Rookie")
                end
                
                -- He drops a beacon for the test range
                test_range_cam = BuildObject("apcamr", 1, "cam_spawn6")
                SetLabel(test_range_cam, "Testing Range")
                
                test_range_found = true
                rookie_move_time = GetTime() + 5.0
            end
        end

        -- Phase 2: Mine Path Guidance
        if test_range_found and (not mine_path_active) and (rookie_move_time < GetTime()) then
            -- Check if player is near Mine Field entrance
            -- C++ checks distance to mine_geyz > 400? Logic inverted? 
            -- "if ((GetDistance (user, mine_geyz) > 400.0f) && (!rookie_lost))" -> Audio "I'm under attack"
            -- We'll simplify: Rookie guides player.
            
            if GetDistance(user, rookie) < 150.0 then
                AudioMessage("misn0704.wav") -- "I'll drop a camera" / "Follow me"
                Goto(rookie, "volcano_geyz2") -- Move into mines
                
                nav_mine = BuildObject("apcamr", 1, "cam_spawn1")
                SetLabel(nav_mine, "Mine Field")
                
                -- Spawn Safe Path Beacons
                mine_beacon1 = BuildObject("apcamr", 1, "cam_spawn2"); SetLabel(mine_beacon1, "Mine Path 1")
                mine_beacon2 = BuildObject("apcamr", 1, "cam_spawn3"); SetLabel(mine_beacon2, "Mine Path 2")
                mine_beacon3 = BuildObject("apcamr", 1, "cam_spawn4"); SetLabel(mine_beacon3, "Mine Path 3")
                mine_beacon4 = BuildObject("apcamr", 1, "cam_spawn5"); SetLabel(mine_beacon4, "Mine Path 4")
                
                mine_path_active = true
                rookie_move_time = GetTime() + 20.0
            end
        end
        
        if mag_show_started and (not mag_show_done) then
            if not camera1_on then
                CameraReady()
                AudioMessage("misn0711.wav") -- "Check this out!"
                
                -- Spawn Cinematic Actors
                mag_tank = BuildObject("svtnk7", 2, "test_tank_spawn")
                mag_turret = BuildObject("test_turret", 2, "test_turret_spot") -- Assuming spot exists or use coordinates
                -- If test_turret ODF missing, use 'sbtowe'
                if not IsAlive(mag_turret) then mag_turret = BuildObject("avtest", 2, "test_turret_spot") end
                
                CameraObject(mag_tank, 2000, 800, 500, user)
                camera_time = GetTime() + 8.0
                camera1_on = true
            end
            
            if camera1_on and (not camera2_on) and ((camera_time < GetTime()) or CameraCancelled()) then
                CameraPath("camera_path1", 250, 250, mag_tank)
                camera_time = GetTime() + 8.0
                camera2_on = true
            end
            if camera2_on and (not camera3_on) and ((camera_time < GetTime()) or CameraCancelled()) then
                CameraPath("camera_path2", 310, 500, mag_turret)
                -- Trigger Attack
                Attack(mag_tank, mag_turret)
                camera_time = GetTime() + 5.0
                camera3_on = true
            end
            if camera3_on and ((camera_time < GetTime()) or CameraCancelled()) then
                -- Tank switch effect from C++ (Remove/Respawn for visual reset? Or effects?)
                -- C++ did: Remove/Build svtnk7 again. Just keep attacking.
                CameraFinish()
                mag_show_done = true
                
                -- Cleanup Actors
                RemoveObject(mag_tank)
                -- Leave turret as wreckage?
                Damage(mag_turret, 10000)
            end
        end

        -- Phase 4: Volcano Peak Scout & Ejection (The Finale)
        if mag_show_done and (not jump_cam_spawned) then
            -- Trigger Overlook Sequence
            if (not rookie_at_cinema) then
                AudioMessage("misn0702.wav") -- "I found an overlook"
                
                jump_cam = BuildObject("apcamr", 1, "jump_cam_spawn")
                SetLabel(jump_cam, "Volcano Peak")
                
                -- Move Rookie to Peak
                Follow(rookie, jump_geyz) 
                rookie_move_time = GetTime() + 10.0
                
                jump_cam_spawned = true
            end
        end
        
        if jump_cam_spawned and (rookie_move_time < GetTime()) and (not rookie_moved) then
            rookie_remove_time = GetTime() + 10.0
            rookie_moved = true
        end
        
        if rookie_moved and (rookie_remove_time < GetTime()) and (not rookie_found) then
            rookie_remove_time = GetTime() + 3.0
            if IsAlive(rookie) then
                if GetDistance(user, rookie) < 70.0 then
                    Defend(rookie, 1)
                    AudioMessage("misn0718.wav")
                    rookie_remove_time = GetTime() + 10.0
                    rookie_found = true
                end
            end
        end
        
        if rookie_found and (rookie_remove_time < GetTime()) and (not rookie_removed) then
            if IsAlive(rookie) then
                AudioMessage("misn0715.wav")
                -- Custom Ejection Logic
                local pos = GetPosition(rookie)
               --RemoveObject(rookie) -- Destroy ship immediately / or Eject then delete. Remove is cleaner for custom spawn.
                -- Spawn Explosion?
               --  BuildObject("avexpl", 1, pos)
               RemovePilot(rookie)
               Damage(rookie, 10000)
                
                rookie_pilot = BuildObject("aspilo", 1, pos)
                SetLabel(rookie_pilot, "Rookie")
                -- Initial Kick Up
                SetVelocity(rookie_pilot, Vector(0, 50, 0)) 
                
                rookie_removed = true
                rookie_flying = true
            end
        end
        
        -- Rookie Flying Logic
        if rookie_flying and IsAlive(rookie_pilot) then
            local dest = ccacomtower
            if not IsAlive(dest) then dest = "radar_geyser" end -- Fallback
            
            local my_pos = GetPosition(rookie_pilot)
            local target_pos = GetPosition(dest)
            local dist = GetDistance(rookie_pilot, dest)
            
            -- Direction towards tower, ignore Y first
            local dir = Normalize(Vector(target_pos.x - my_pos.x, 0, target_pos.z - my_pos.z))
            
            if dist > 40.0 then
                -- Float over wall: Keep Y at least Terrain + 30 or fixed height?
                -- Wall is high. Let's aim for absolute height ~ 100?
                -- Or just add upward velocity if dropping?
                
                local speed = 15.0
                local target_h = GetTerrainHeight(my_pos) + 40.0
                local current_h = my_pos.y
                
                local vertical_push = 0
                if current_h < target_h then vertical_push = 10.0 
                elseif current_h > target_h + 10 then vertical_push = -5.0 end
                
                -- Override Velocity
                SetVelocity(rookie_pilot, Vector(dir.x * speed, vertical_push, dir.z * speed))
            else
                -- Near target, let drop
                -- Check if grounded
                if (my_pos.y - GetTerrainHeight(my_pos)) < 2.0 then
                    rookie_flying = false
                    rookie_landed = true
                end
            end
        end
        
        -- Rookie Steal Logic
        if rookie_landed and IsAlive(rookie_pilot) then
            -- Find empty enemy vehicle
            local nearby = GetObjectsInRange(rookie_pilot, 150.0, "craft")
            local target_veh = nil
            
            for _, h in ipairs(nearby) do
                if (GetTeamNum(h) ~= 1) and (GetTeamNum(h) ~= 0) then -- Enemy (2) or Neutral? Enemy usually.
                    -- Check if Empty? "craft" includes empty ones. IsPilot(h)?
                    -- IsOdf(h, "sspilo") check? No, check if it has a pilot.
                    -- GetPilot(h)? Not standard API.
                    -- Empty craft are usually Team 0 or Neutral?
                    -- In this mission parked vehicles might be Team 2 but empty (waiting for pilots).
                    -- Let's assume parked1..3 handles.
                    if (h == parked1) or (h == parked2) or (h == parked3) or (h == parkturret1) or (h == parkturret2) then
                         if IsAlive(h) then
                            -- How to check if empty? If it's parked, it might be.
                            -- Also check if pilot is inside?
                            target_veh = h
                            break
                         end
                    end
                end
            end
            
            if target_veh then
                Enter(rookie_pilot, target_veh)
                rookie_landed = false -- Stop checking
                SetLabel(rookie_pilot, "Rookie") -- Keep label
            else
                -- No vehicle found? Wander?
                Goto(rookie_pilot, ccacomtower)
            end
        end
    end
    
    -- Alarm Logic & Stealth
    if (alarm_check < GetTime()) and (not alarm_on) then
        alarm_check = GetTime() + 5.0
        
        -- Distance check to turret spot
        local turret_detected = false
        if (not out_of_car) and IsAlive(turret1_spot) and IsValid("turret1_spot") then -- path point check
             -- C++ uses GetDistance(user, turret1_spot). 'turret1_spot' is AiPath*. 
             -- Lua GetDistance supports path names string.
             if GetDistance(user, "turret1_spot") < 70.0 then turret_detected = true end
        end
        -- Since turret1_spot is just a point, we can assume manual distance check to 'ccacomtower' handles similar too
        
        if turret_detected then
            AudioMessage("misn0710.wav")
            SetObjectiveOn(ccacomtower)
            SetLabel(ccacomtower, "Radar Array")
            alarm_on = true
        end
    end
    
    if not first_objective then
        if alarm_on then
            -- Alarm Sound
            if IsAlive(ccacomtower) and (GetDistance(user, ccacomtower) < 170.0) and (not alarm_sound) then
                AudioMessage("misn0708.wav")
                alarm_timer = GetTime() + 6.0
                alarm_sound = true
            end
            if alarm_sound and (alarm_timer < GetTime()) then
                alarm_sound = false
            end
            
            -- Turret Move
            if not turret_move then
                SetObjectiveOn(ccacomtower)
                SetLabel(ccacomtower, "Radar Array")
                Retreat(guard_turret1, ccacomtower)
                Retreat(guard_turret2, ccacomtower)
                turret_move = true
            end
            
            -- Evac Logic / Spawn Pilots
            if not start_evac then
                unit_spawn_time = GetTime() + DiffUtils.ScaleTimer(20.0)
                start_evac = true
            end
            
            if start_evac and (unit_spawn_time < GetTime()) and (not unit_spawn) then
                -- Spawn pilots
                pilot1 = BuildObject("sspilo", 2, "hut2_spawn")
                pilot2 = BuildObject("sspilo", 2, "hut2_spawn")
                pilot3 = BuildObject("sspilo", 2, "hut2_spawn")
                pilot4 = BuildObject("sspilo", 2, "hut1_spawn")
                pilot5 = BuildObject("sspilo", 2, "hut1_spawn")
                
                -- Convert parked turrets
                if parkturret1 ~= user then
                    spawn_turret1 = BuildObject("svturr", 2, parkturret1)
                    Defend(spawn_turret1)
                    RemoveObject(parkturret1)
                end
                if parkturret2 ~= user then
                    spawn_turret2 = BuildObject("svturr", 2, parkturret2)
                    Defend(spawn_turret2)
                    RemoveObject(parkturret2)
                end
                
                -- Pilots retreat to tanks
                if IsAlive(parked1) then Retreat(pilot1, parked1) end
                if IsAlive(parked2) then Retreat(pilot2, parked2) end
                if IsAlive(parked3) then Retreat(pilot3, parked3) end
                
                unit_spawn = true
            end
            
            -- Check if pilots reached vehicles (Lua simplification: just check aliveness/proximity)
            if unit_spawn and (not alarm_special) then -- alarm_special means caused by damage not proximity (mostly)
                if (not IsAlive(pilot1)) and IsAlive(parked1) then Attack(parked1, user) end
                if (not IsAlive(pilot2)) and IsAlive(parked2) then Attack(parked2, user) end
                if (not IsAlive(pilot3)) and IsAlive(parked3) then Attack(parked3, user) end
            end
            
            -- Forces Enroute condition (Tower health)
            if IsAlive(ccacomtower) and (GetHealth(ccacomtower) < 0.5) and (not forces_enroute) then
                if IsAlive(svpatrol1_2) then Goto(svpatrol1_2, ccacomtower) end
                if IsAlive(svpatrol3_1) then Goto(svpatrol3_1, ccacomtower) end
                if IsAlive(svpatrol4_1) then Goto(svpatrol4_1, ccacomtower) end
                forces_enroute = true
            end
        end
    end
    
    -- Parachute / Commando Logic
    if not first_objective then
        if (not alarm_on) and (not out_of_car) and (GetDistance(user, "camera_geyser") < 160.0) then
            SetObjectiveOn(ccacomtower)
            SetLabel(ccacomtower, "Radar Array")
            out_of_car = true
            
            -- Restored Parachute Camera
            parachute_camera_time = GetTime() + 5.0
        end
        
        -- Parachute Cinematic (C++: cute_camera)
        if out_of_car and (not parachute_camera_ready) and (parachute_camera_time < GetTime()) then
            CameraReady()
            parachute_camera_time = GetTime() + 5.0
            parachute_camera_ready = true
        end
        
        if parachute_camera_ready and (not parachute_camera_off) then
            CameraObject(user, 800, 800, 10, user)
            if (parachute_camera_time < GetTime()) or CameraCancelled() then
                CameraFinish()
                parachute_camera_off = true
            end
        end
        
        if out_of_car and (not vehicle_stolen) then
            if IsOdf(user, "svtank") or IsOdf(user, "svfigh") or IsOdf(user, "svturr") then
                vehicle_stolen = true
            end
        end
        
        -- Trigger 1: Damage Check
        if (not trigger1) and out_of_car then
            local function Damaged(h) return IsAlive(h) and (GetHealth(h) < 0.95) end
            if Damaged(ccaguntower1) or Damaged(ccaguntower2) or Damaged(ccacomtower) or 
               Damaged(powrplnt1) or Damaged(barrack1) or Damaged(barrack2) or
               Damaged(parked1) or Damaged(parked2) or Damaged(parked3) or
               Damaged(parkturret1) or Damaged(parkturret2) then
               trigger1 = true
            end
        end
        
        if trigger1 and (not alarm_on) then
            alarm_on = true
            if not vehicle_stolen then alarm_special = true end
        end
        
        -- External Alarm Trigger (from vehicles attacking)
        if (not alarm_on) and (not out_of_car) then
            local function NearTower(h) return IsAlive(h) and (GetDistance(h, "turret1_spot") < 100.0) end
            if NearTower(wingman1) or NearTower(wingman2) or NearTower(wingtank1) or NearTower(new_tank1) or NearTower(new_tank2) then
                AudioMessage("misn0709.wav")
                alarm_on = true
            end
        end
    end
    
    end
    
    -- Stealth Reinforcements (Rebuild Fighters if undetected)
    if (not first_objective) and (not retreat_success) and (not detected_message) then
        if IsAlive(ccarecycle) then
            -- Patrol 1
            if (not IsAlive(svpatrol1_1)) and (not IsAlive(svpatrol1_2)) then
                svpatrol1_1 = BuildObject("svfigh", 2, ccarecycle); Patrol(svpatrol1_1, "patrol_path3")
                svpatrol1_2 = BuildObject("svfigh", 2, ccarecycle); Patrol(svpatrol1_2, "patrol_path3")
            end
            -- Patrol 3
            if (not IsAlive(svpatrol3_1)) and (not IsAlive(svpatrol3_2)) then
                svpatrol3_1 = BuildObject("svfigh", 2, ccarecycle); Patrol(svpatrol3_1, "patrol_path1")
                svpatrol3_2 = BuildObject("svfigh", 2, ccarecycle); Patrol(svpatrol3_2, "patrol_path1")
            end
            -- Patrol 4
            if (not IsAlive(svpatrol4_1)) and (not IsAlive(svpatrol4_2)) then
                svpatrol4_1 = BuildObject("svfigh", 2, ccarecycle); Patrol(svpatrol4_1, "patrol_path2")
                svpatrol4_2 = BuildObject("svfigh", 2, ccarecycle); Patrol(svpatrol4_2, "patrol_path2")
            end
        end
    end

    -- Retreat Logic (Runner System)
    if (not first_objective) and (not retreat_success) and IsAlive(ccarecycle) and (not alarm_on) then
        local patrols = {svpatrol1_1, svpatrol1_2, svpatrol2_1, svpatrol2_2, svpatrol3_1, svpatrol3_2}
        
        for i, p in ipairs(patrols) do
            if IsAlive(p) then
                -- Check for Fleeing Condition
                -- Using a custom property or checking current command would be ideal, but we'll use a table/flag if needed. 
                -- For simplicity, we just check distance and order retreat.
                local is_runner = (GetLabel(p) == "Runner")
                
                if (not is_runner) and (GetDistance(user, p) < 50.0) then
                    Retreat(p, ccarecycle)
                    SetLabel(p, "Runner")
                    is_runner = true
                    -- C++ sets getaway_message_time here
                end
                
                if is_runner then
                    -- Check Success (Reached Base)
                    if GetDistance(p, ccarecycle) < 100.0 then
                        retreat_success = true
                        SetLabel(p, "Runner (Safe)")
                        -- Stop(p) ?
                    end
                end
            elseif (not IsAlive(p)) and (aiCore.param and aiCore.param[p] == "Runner") then
                 -- This requires tracking who was a runner. 
                 -- Let's stick to the simpler C++ "that got um" check which was complex boolean logic.
                 -- Simplified: If we kill a runner, play sound.
                 -- We can check if it was labeled "Runner" before death? Lua handles are ints, so need state.
                 -- We'll skip the audio for now to avoid complexity or use a global 'runner_killed' flag if needed.
            end
        end
    end
    
    -- Runner Killed Audio (Simplified logic)
    -- We can just check if any *dead* unit was a runner? No.
    -- Alternative: Check if we had a runner last frame and now it's dead.
    -- Moving on to the *Consequence* of retreat_success
    
    if retreat_success and (not detected_message) then
        AudioMessage("misn0707.wav") -- "One of the runners made it back"
        detected_message = true
        
        -- Spawn Tanks Layout (Replacing Fighters)
        if IsAlive(ccarecycle) then
            -- Replace/augment patrols with Tanks
            -- C++ logic: if !IsAlive(figh) -> Build("svtank")
            -- We'll just force spawn/replace logic here
            local function SpawnTankPatrol(path)
                local t1 = BuildObject("svtank", 2, ccarecycle); Patrol(t1, path)
                local t2 = BuildObject("svtank", 2, ccarecycle); Patrol(t2, path)
                return t1, t2
            end
            
            svpatrol1_1, svpatrol1_2 = SpawnTankPatrol("patrol_path1")
            svpatrol3_1, svpatrol3_2 = SpawnTankPatrol("patrol_path1")
            -- svpatrol2 series was handled by rendezvous logic usually
        end
    end
    
    -- Final Phase: Radar Destroyed
    if (not IsAlive(ccacomtower)) and (not first_objective) then
        AudioMessage("misn0714.wav")
        radar_camera_time = GetTime() + 10.0
        radar_next_shot_time = GetTime() + 20.0
        next_mission_time = GetTime() + 7.5
        
        -- Start Cinematic
        CameraReady()
        radar_shot1 = true
        
        first_objective = true
    end
    
    -- Radar Cinematic Logic (Restored C++ shot1/shot2)
    if radar_shot1 then
        CameraPath("radar_path", 4000, 1000, "radar_geyser")
        if (radar_camera_time < GetTime()) then
            radar_shot1 = false
            radar_shot2 = true
        end
    end
    
    if radar_shot2 then
        CameraPath("movie_cam_spawn", 160, 0, "show_geyser")
        if (not radar_camera_off) and (radar_next_shot_time < GetTime()) then
            CameraFinish()
            radar_shot2 = false
            radar_camera_off = true
        end
    end
    
    if (radar_shot1 or radar_shot2) and (not radar_camera_off) then
        if CameraCancelled() then
            radar_shot1 = false
            radar_shot2 = false
            CameraFinish()
            radar_camera_off = true
        end
    end
    
    if first_objective and (not next_mission) and (next_mission_time < GetTime()) then
        nsdfrecycle = BuildObject("avrec", 1, "recycle_spawn") -- C++ uses avrec7?
        nsdfmuf = BuildObject("avfact", 1, "muf_spawn") -- C++ avmu7
        Goto(nsdfrecycle, "recycle_path")
        Goto(nsdfmuf, "muf_path")
        
        nav6 = BuildObject("apcamr", 1, "recycle_cam_spawn")
        SetLabel(nav6, "Utah Rendezvous")
        
        AddScrap(1, DiffUtils.ScaleRes(30))
        SetScrap(2, DiffUtils.ScaleRes(60))
        SetAIP("misn07.aip")
        
        ccabaseguntower1 = BuildObject("sbtowe", 2, "base_tower1_spawn")
        
        ClearObjectives()
        AddObjective("misn0701.otf", "green")
        AddObjective("misn0703.otf", "white")
        AddObjective("misn0702.otf", "white")
        
        next_mission = true
    end
    
    if next_mission and (not IsAlive(ccarecycle)) then
        second_objective = true
    end
    
    if next_mission and (not utah_found) and IsAlive(nsdfrecycle) then
        -- Check logic if deployed? C++ checks IsDeployed(). Lua might allow checking ODF or state?
        -- Assuming timer or just alive is enough for now, or check velocity
        -- C++: "test" boolean check.
        -- We'll just assume finding it is enough or distance?
        if GetDistance(user, nsdfrecycle) < 200.0 then
            ClearObjectives()
            AddObjective("misn0703.otf", "green")
            AddObjective("misn0702.otf", "white")
            utah_found = true
        end
    end
    
    -- Win/Loss
    if next_mission and (not IsAlive(nsdfrecycle)) and (not game_over) then
        AudioMessage("misn0712.wav")
        if not utah_found then
            ClearObjectives()
            AddObjective("misn0701.otf", "green")
            AddObjective("misn0703.otf", "red")
            AddObjective("misn0702.otf", "white")
        end
        FailMission(GetTime() + 15.0, "misn07f1.des")
        game_over = true
    end
    
    if first_objective and second_objective and (not game_over) then
        AudioMessage("misn0713.wav")
        SucceedMission(GetTime() + 15.0, "misn07w1.des")
        game_over = true
    end
end
