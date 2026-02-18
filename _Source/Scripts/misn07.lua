-- Misn07 Mission Script (Converted from Misn07Mission.cpp)

-- Compatibility for 1.5
SetLabel = SetLabel or SetLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({ "campaignReimagined", "3659600763" })
local exu = require("exu")
local aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")
local subtit = require("ScriptSubtitles")
local PersistentConfig = require("PersistentConfig")
local Environment = require("Environment")
local PhysicsImpact = require("PhysicsImpact")

-- Helper for AI
local function SetupAI()
    local caa = DiffUtils.SetupTeams(aiCore.Factions.NSDF, aiCore.Factions.CCA, 2)

    -- Legacy Features from Review
    caa:SetConfig("dynamicMinefields", true)
    caa:SetConfig("minefields", { "volcano_geyz1", "volcano_geyz2", "radar_geyser" })

    -- Configure Player Team (1) for Scavenger Assist
    if aiCore.ActiveTeams and aiCore.ActiveTeams[1] then
        aiCore.ActiveTeams[1]:SetConfig("scavengerAssist", PersistentConfig.Settings.ScavengerAssistEnabled)
        aiCore.ActiveTeams[1]:SetConfig("manageFactories", false)
        aiCore.ActiveTeams[1]:SetConfig("autoRepairWingmen", PersistentConfig.Settings.AutoRepairWingmen)
    end
end

-- Variables (Encapsulated for Save/Load)
local M = {
    -- State Booleans
    start_done = false,
    out_of_car = false,
    alarm_on = false,
    start_evac = false,
    unit_spawn = false,
    recon_message1 = false,
    recon_message2 = false,
    jump_cam_spawned = false,
    rookie_moved = false,
    rendezvous = false,
    first_objective = false,
    second_objective = false,
    turret_move = false,
    next_mission = false,
    rookie_lost = false,
    mine_pathed = false,
    retreat_success = false,
    detected_message = false,
    fighter_moved = false,
    vehicle_stolen = false,
    trigger1 = false,
    alarm_special = false,
    alarm_sound = false,
    rookie_removed = false,
    forces_enroute = false,
    camera_ready = false,
    camera1_on = false,
    camera2_on = false,
    camera3_on = false,
    camera4_on = false,
    camera_off = false,
    camera2_oned = false,
    camera3_oned = false,
    game_over = false,
    opening_vo = false,
    utah_found = false,
    rookie_found = false,
    tower_warning = false,
    alarm_loop = false,
    radar_shot1 = false,
    radar_shot2 = false,
    radar_camera_off = false,
    parachute_camera_ready = false,
    parachute_camera_off = false,
    test_range_found = false,
    mine_path_active = false,
    mag_show_started = false,
    mag_show_done = false,
    rookie_at_cinema = false,
    cinema_tank_spawned = false,
    cinema_turret_spawned = false,
    first_camera_ready = false,
    first_camera_off = false,
    rookie_flying = false,
    rookie_landed = false,

    -- Timers
    radar_next_shot_time = 0.0,
    parachute_camera_time = 0.0,
    first_camera_time = 99999.0,
    unit_spawn_time = 999999.0,
    recon_message_time = 999999.0,
    rookie_move_time = 999999.0,
    rookie_rendezvous_time = 999999.0,
    patrol2_move_time = 999999.0,
    alarm_time = 999999.0,
    alarm_timer = 999999.0,
    rendezous_check = 999999.0,
    alarm_check = 999999.0,
    rookie_remove_time = 999999.0,
    runner_check = 999999.0,
    radar_camera_time = 999999.0,
    next_mission_time = 999999.0,
    tower_check = 999999.0,
    camera_time = 999999.0,

    -- Handles
    user = nil,
    nsdfrecycle = nil,
    nsdfmuf = nil,
    rookie = nil,
    jump_cam = nil,
    jump_geyz = nil,
    remove_geyz = nil,
    mine_geyz = nil,
    pilot1 = nil,
    pilot2 = nil,
    pilot3 = nil,
    pilot4 = nil,
    pilot5 = nil,
    ccaguntower1 = nil,
    ccaguntower2 = nil,
    ccacomtower = nil,
    powrplnt1 = nil,
    powrplnt2 = nil,
    barrack1 = nil,
    barrack2 = nil,
    nav1 = nil,
    nav3 = nil,
    nav6 = nil,
    nav_mine = nil,
    wingman1 = nil,
    wingman2 = nil,
    wingtank1 = nil,
    wingtank2 = nil,
    wingtank3 = nil,
    wingturret1 = nil,
    wingturret2 = nil,
    nsdfarmory = nil,
    svapc = nil,
    ccarecycle = nil,
    ccamuf = nil,
    ccaslf = nil,
    basepowrplnt1 = nil,
    pbaseowrplnt2 = nil,
    ccabaseguntower1 = nil,
    ccabaseguntower2 = nil,
    patrol1_1 = nil,
    patrol1_2 = nil,
    svpatrol1_1 = nil,
    svpatrol1_2 = nil,
    svpatrol2_1 = nil,
    svpatrol2_2 = nil,
    svpatrol3_1 = nil,
    svpatrol3_2 = nil,
    svpatrol4_1 = nil,
    svpatrol4_2 = nil,
    guard_turret1 = nil,
    guard_turret2 = nil,
    spawn_turret1 = nil,
    spawn_turret2 = nil,
    parked1 = nil,
    parked2 = nil,
    parked3 = nil,
    parkturret1 = nil,
    parkturret2 = nil,
    spawn_point = nil,
    fence = nil,
    tank_spawn = nil,
    radar_geyser = nil,
    camera_geyser = nil,
    show_geyser = nil,
    new_tank1 = nil,
    new_tank2 = nil,
    test_range_cam = nil,
    mine_beacon1 = nil,
    mine_beacon2 = nil,
    mine_beacon3 = nil,
    mine_beacon4 = nil,
    mag_tank = nil,
    mag_turret = nil,
    mag_target = nil,
    mine_geyser = nil,
    rookie_pilot = nil,

    difficulty = 2,
    TPS = 20
}

function ApplyQOL()
    if not exu then return end
    if exu.SetShotConvergence then exu.SetShotConvergence(true) end
    if exu.SetReticleRange then exu.SetReticleRange(500) end
    if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    PersistentConfig.Initialize()
    Environment.Init()
    PhysicsImpact.Init()
end

function Start()
    M.TPS = 20
    if exu then
        local ver = (type(exu.GetVersion) == "function" and exu.GetVersion()) or exu.version or "Unknown"
        print("EXU Version: " .. tostring(ver))
        M.difficulty = (exu.GetDifficulty and exu.GetDifficulty()) or 2
        print("Difficulty: " .. tostring(M.difficulty))

        if M.difficulty >= 3 then
            AddObjective("hard_diff", "yellow", 8.0, "High Difficulty: Enemy presence intensified.")
        elseif M.difficulty <= 1 then
            AddObjective("easy_diff", "blue", 8.0, "Low Difficulty: Enemy presence reduced.")
        end

        ApplyQOL()
    end

    SetupAI()
    aiCore.Bootstrap()
    subtit.Initialize()

    M.start_done = false
    M.opening_vo = false
    M.first_camera_ready = false
    M.first_camera_off = false
    M.first_camera_time = 99999.0
    M.rendezous_check = GetTime() + 10.0 -- Delayed to allow intro
end

function AddObject(h)
    local team = GetTeamNum(h)

    Environment.OnObjectCreated(h)
    PhysicsImpact.OnObjectCreated(h)

    if team == 2 then
        aiCore.AddObject(h)
    elseif team == 1 then
        aiCore.AddObject(h)
    end

    -- Unit Turbo based on difficulty
    if exu and exu.SetUnitTurbo and IsCraft(h) then
        if team == 1 then
            exu.SetUnitTurbo(h, true)
        elseif team ~= 0 then
            if M.difficulty >= 3 then exu.SetUnitTurbo(h, true) end
        end
    end
end

function DeleteObject(h)
end

function Update()
    M.user = GetPlayerHandle()
    if exu and exu.UpdateOrdnance then exu.UpdateOrdnance() end
    aiCore.Update()
    Environment.Update(1.0 / M.TPS)
    PhysicsImpact.Update(1.0 / M.TPS)
    subtit.Update()
    PersistentConfig.UpdateInputs()
    PersistentConfig.UpdateHeadlights()

    -- Initial Setup
    if not M.start_done then
        M.nav3 = GetHandle("cam3")
        SetLabel(M.nav3, "Rendezvous Point")

        SetScrap(1, DiffUtils.ScaleRes(10))

        M.ccacomtower = GetHandle("radar_array")
        SetObjectiveOff(M.ccacomtower)

        M.patrol1_1 = GetHandle("svfigh1")
        M.patrol1_2 = GetHandle("svfigh2")
        Patrol(M.patrol1_1, "patrol_path3")
        Patrol(M.patrol1_2, "patrol_path3")

        M.svpatrol3_1 = GetHandle("svpatrol3_1")
        M.svpatrol3_2 = GetHandle("svpatrol3_2")
        Patrol(M.svpatrol3_1, "patrol_path1")
        Patrol(M.svpatrol3_2, "patrol_path1")

        M.svpatrol4_1 = GetHandle("svpatrol4_1")
        M.svpatrol4_2 = GetHandle("svpatrol4_2")
        Patrol(M.svpatrol4_1, "patrol_path2")
        Patrol(M.svpatrol4_2, "patrol_path2")

        M.wingtank2 = GetHandle("avtank2")
        M.wingtank3 = GetHandle("avtank3")
        SetIndependence(M.wingtank2, 0)
        Stop(M.wingtank2)
        SetPerceivedTeam(M.wingtank2, 1) -- Set perceived team to player
        SetIndependence(M.wingtank3, 0)
        Stop(M.wingtank3)
        SetPerceivedTeam(M.wingtank3, 1)

        M.svpatrol2_1 = GetHandle("svpatrol2_1")
        M.svpatrol2_2 = GetHandle("svpatrol2_2")
        Stop(M.svpatrol2_1, 1)
        Stop(M.svpatrol2_2, 1)

        M.rendezous_check = GetTime() + DiffUtils.ScaleTimer(9.0)
        M.patrol2_move_time = GetTime() + DiffUtils.ScaleTimer(121.0)
        M.alarm_check = GetTime() + DiffUtils.ScaleTimer(27.0)

        -- Handles
        M.jump_geyz = GetHandle("volcano_geyz1")
        M.remove_geyz = GetHandle("volcano_geyz2")
        M.ccaguntower1 = GetHandle("sgtower1")
        M.ccaguntower2 = GetHandle("sgtower2")

        M.powrplnt1 = GetHandle("power1")
        M.barrack1 = GetHandle("hut1")
        M.barrack2 = GetHandle("hut2")

        M.wingman1 = GetHandle("avfigh1")
        M.wingtank1 = GetHandle("avtank1")
        M.wingturret1 = GetHandle("avturret1")
        M.wingturret2 = GetHandle("avturret2")

        M.ccarecycle = GetHandle("svrecycler")
        M.ccamuf = GetHandle("svmuf")
        M.basepowrplnt1 = GetHandle("svbasepower1")

        M.guard_turret1 = GetHandle("svturret1")
        M.guard_turret2 = GetHandle("svturret2")

        M.parked1 = GetHandle("parked1")
        M.parked2 = GetHandle("parked2")
        M.parked3 = GetHandle("parked3")
        M.parkturret1 = GetHandle("pturret1")
        M.parkturret2 = GetHandle("pturret2")
        M.svapc = GetHandle("parked_svapc")

        M.radar_geyser = GetHandle("radar_geyser")
        M.camera_geyser = GetHandle("camera_geyser")
        -- M.show_geyser = GetHandle("show_geyser")

        M.start_done = true
    end

    -- Cut Intro Cinematic
    if not M.first_camera_ready then
        CameraReady()
        subtit.Play("misn0700.wav") -- Moved here from below
        M.opening_vo = true         -- Handled here
        M.first_camera_time = GetTime() + 10.0
        M.first_camera_ready = true

        -- Try to play the path if it exists, otherwise orbit
        CameraPath("start_camera", 2000, 950, M.user)
    end

    if M.first_camera_ready and (not M.first_camera_off) and ((M.first_camera_time < GetTime()) or CameraCancelled()) then
        CameraFinish()
        M.first_camera_off = true
    end

    -- Opening VO (Fallback if intro skipped or logic flows through)
    -- Modified to respect intro
    if (not M.opening_vo) and M.start_done and (M.rendezous_check < GetTime()) then
        M.rendezous_check = GetTime() + 15.0
        subtit.Play("misn0700.wav")
        ClearObjectives()
        AddObjective("misn0700.otf", "white")
        M.opening_vo = true
    end

    -- Patrol 2 Move logic
    if M.start_done and (M.patrol2_move_time < GetTime()) and (not M.rendezvous) and IsAlive(M.svpatrol2_1) and IsAlive(M.svpatrol2_2) and (not M.fighter_moved) then
        Patrol(M.svpatrol2_1, "patrol_path1")
        Patrol(M.svpatrol2_2, "patrol_path1")
        M.fighter_moved = true
    end

    -- Rendezvous Logic
    if not M.first_objective then
        if (M.rendezous_check < GetTime()) and (not M.rendezvous) and (not M.alarm_on) then
            M.rendezous_check = GetTime() + 3.0

            local dist2 = (IsAlive(M.wingtank2) and GetDistance(M.user, M.wingtank2)) or 9999.0
            local dist3 = (IsAlive(M.wingtank3) and GetDistance(M.user, M.wingtank3)) or 9999.0

            if (dist2 < 150.0) or (dist3 < 150.0) then
                subtit.Play("misn0701.wav")

                if IsAlive(M.wingtank2) then
                    M.new_tank1 = BuildObject("avtank", 1, M.wingtank2)
                    RemoveObject(M.wingtank2) -- Replace dummy with real unit
                end
                if IsAlive(M.wingtank3) then
                    M.new_tank2 = BuildObject("avtank", 1, M.wingtank3)
                    RemoveObject(M.wingtank3)
                end

                ClearObjectives()
                AddObjective("misn0700.otf", "green")
                AddObjective("misn0701.otf", "white")

                M.recon_message_time = GetTime() + DiffUtils.ScaleTimer(240.0)
                M.runner_check = GetTime() + DiffUtils.ScaleTimer(6.0)
                M.patrol2_move_time = GetTime() + DiffUtils.ScaleTimer(60.0) -- Delay patrol movement

                M.nav1 = BuildObject("apcamr", 1, "cam1_spawn")
                SetLabel(M.nav1, "CCA Outpost")
                M.tower_check = GetTime() + 10.0
                M.rendezvous = true
            end
        end

        if M.rendezvous and (M.patrol2_move_time < GetTime()) and (not M.fighter_moved) then
            if IsAlive(M.svpatrol2_1) then Attack(M.svpatrol2_1, M.user) end
            if IsAlive(M.svpatrol2_2) then Attack(M.svpatrol2_2, M.user) end
            M.fighter_moved = true
        end

        -- Tower Warning
        if IsAlive(M.nav1) and (M.tower_check < GetTime()) and (not M.tower_warning) then
            M.tower_check = GetTime() + 4.0
            if GetDistance(M.user, M.nav1) < 90.0 then
                subtit.Play("misn0716.wav")
                M.tower_warning = true
            end
        end
    end

    -- Rookie Script
    if (not M.first_objective) and (not M.alarm_on) and (not M.out_of_car) then
        -- Rookie Script: Phase 1 - Test Range & Mines
        if M.rendezvous and (not M.test_range_found) and (not M.jump_cam_spawned) and ((M.recon_message_time < GetTime()) or M.tower_warning) then
            M.recon_message_time = GetTime() + 10.0
            M.mine_geyser = "volcano_geyz2" -- "mine_geyz" in C++

            -- Trigger Test Range Discovery (Delayed start)
            if (GetDistance(M.user, M.mine_geyser) > 300.0) then
                subtit.Play("misn0703.wav") -- "Found a Soviet Test Range"

                -- Spawn Rookie at Test Range Entrance if not exists
                if not IsAlive(M.rookie) then
                    M.rookie = BuildObject("avfigh", 1, "volcano_geyz1") -- Spawn near start
                    SetLabel(M.rookie, "Rookie")
                end

                -- He drops a beacon for the test range
                M.test_range_cam = BuildObject("apcamr", 1, "cam_spawn6")
                SetLabel(M.test_range_cam, "Testing Range")

                M.test_range_found = true
                M.rookie_move_time = GetTime() + 5.0
            end
        end

        -- Phase 2: Mine Path Guidance
        if M.test_range_found and (not M.mine_path_active) and (M.rookie_move_time < GetTime()) then
            if GetDistance(M.user, M.rookie) < 150.0 then
                subtit.Play("misn0704.wav")     -- "I'll drop a camera" / "Follow me"
                Goto(M.rookie, "volcano_geyz2") -- Move into mines

                M.nav_mine = BuildObject("apcamr", 1, "cam_spawn1")
                SetLabel(M.nav_mine, "Mine Field")

                -- Spawn Safe Path Beacons
                M.mine_beacon1 = BuildObject("apcamr", 1, "cam_spawn2"); SetLabel(M.mine_beacon1, "Mine Path 1")
                M.mine_beacon2 = BuildObject("apcamr", 1, "cam_spawn3"); SetLabel(M.mine_beacon2, "Mine Path 2")
                M.mine_beacon3 = BuildObject("apcamr", 1, "cam_spawn4"); SetLabel(M.mine_beacon3, "Mine Path 3")
                M.mine_beacon4 = BuildObject("apcamr", 1, "cam_spawn5"); SetLabel(M.mine_beacon4, "Mine Path 4")

                M.mine_path_active = true
                M.rookie_move_time = GetTime() + 20.0
            end
        end

        if M.mag_show_started and (not M.mag_show_done) then
            if not M.camera1_on then
                CameraReady()
                subtit.Play("misn0711.wav") -- "Check this out!"

                -- Spawn Cinematic Actors
                M.mag_tank = BuildObject("svtnk7", 2, "test_tank_spawn")
                M.mag_turret = BuildObject("test_turret", 2, "test_turret_spot")
                if not IsAlive(M.mag_turret) then M.mag_turret = BuildObject("avtest", 2, "test_turret_spot") end

                CameraObject(M.mag_tank, 2000, 800, 500, M.user)
                M.camera_time = GetTime() + 8.0
                M.camera1_on = true
            end

            if M.camera1_on and (not M.camera2_on) and ((M.camera_time < GetTime()) or CameraCancelled()) then
                CameraPath("camera_path1", 250, 250, M.mag_tank)
                M.camera_time = GetTime() + 8.0
                M.camera2_on = true
            end
            if M.camera2_on and (not M.camera3_on) and ((M.camera_time < GetTime()) or CameraCancelled()) then
                CameraPath("camera_path2", 310, 500, M.mag_turret)
                -- Trigger Attack
                Attack(M.mag_tank, M.mag_turret)
                M.camera_time = GetTime() + 5.0
                M.camera3_on = true
            end
            if M.camera3_on and ((M.camera_time < GetTime()) or CameraCancelled()) then
                CameraFinish()
                M.mag_show_done = true

                -- Cleanup Actors
                RemoveObject(M.mag_tank)
                Damage(M.mag_turret, 10000)
            end
        end

        -- Phase 4: Volcano Peak Scout & Ejection (The Finale)
        if M.mag_show_done and (not M.jump_cam_spawned) then
            -- Trigger Overlook Sequence
            if (not M.rookie_at_cinema) then
                subtit.Play("misn0702.wav") -- "I found an overlook"

                M.jump_cam = BuildObject("apcamr", 1, "jump_cam_spawn")
                SetLabel(M.jump_cam, "Volcano Peak")

                -- Move Rookie to Peak
                Follow(M.rookie, M.jump_geyz)
                M.rookie_move_time = GetTime() + 10.0

                M.jump_cam_spawned = true
            end
        end

        if M.jump_cam_spawned and (M.rookie_move_time < GetTime()) and (not M.rookie_moved) then
            M.rookie_remove_time = GetTime() + 10.0
            M.rookie_moved = true
        end

        if M.rookie_moved and (M.rookie_remove_time < GetTime()) and (not M.rookie_found) then
            M.rookie_remove_time = GetTime() + 3.0
            if IsAlive(M.rookie) then
                if GetDistance(M.user, M.rookie) < 70.0 then
                    Defend(M.rookie, 1)
                    subtit.Play("misn0718.wav")
                    M.rookie_remove_time = GetTime() + 10.0
                    M.rookie_found = true
                end
            end
        end

        if M.rookie_found and (M.rookie_remove_time < GetTime()) and (not M.rookie_removed) then
            if IsAlive(M.rookie) then
                subtit.Play("misn0715.wav")
                -- Custom Ejection Logic
                local pos = GetPosition(M.rookie)
                RemovePilot(M.rookie)
                Damage(M.rookie, 10000)

                M.rookie_pilot = BuildObject("aspilo", 1, pos)
                SetLabel(M.rookie_pilot, "Rookie")
                -- Initial Kick Up
                SetVelocity(M.rookie_pilot, { x = 0, y = 50, z = 0 })

                M.rookie_removed = true
                M.rookie_flying = true
            end
        end

        -- Rookie Flying Logic
        if M.rookie_flying and IsAlive(M.rookie_pilot) then
            local dest = M.ccacomtower
            if not IsAlive(dest) then dest = "radar_geyser" end -- Fallback

            local my_pos = GetPosition(M.rookie_pilot)
            local target_pos = GetPosition(dest)
            local dist = GetDistance(M.rookie_pilot, dest)

            -- Direction towards tower, ignore Y first
            local dir = Normalize({ x = target_pos.x - my_pos.x, y = 0, z = target_pos.z - my_pos.z })

            if dist > 40.0 then
                local speed = 15.0
                local target_h, _ = GetTerrainHeightAndNormal(my_pos.x, my_pos.z)
                target_h = target_h + 40.0
                local current_h = my_pos.y

                local vertical_push = 0
                if current_h < target_h then
                    vertical_push = 10.0
                elseif current_h > target_h + 10 then
                    vertical_push = -5.0
                end

                -- Override Velocity
                SetVelocity(M.rookie_pilot, { x = dir.x * speed, y = vertical_push, z = dir.z * speed })
            else
                -- Near target, let drop
                -- Check if grounded
                local ground_h, _ = GetTerrainHeightAndNormal(my_pos.x, my_pos.z)
                if (my_pos.y - ground_h) < 2.0 then
                    M.rookie_flying = false
                    M.rookie_landed = true
                end
            end
        end

        -- Rookie Steal Logic
        if M.rookie_landed and IsAlive(M.rookie_pilot) then
            -- Find empty enemy vehicle
            local target_veh = nil

            for h in ObjectsInRange(150.0, M.rookie_pilot) do
                if IsCraft(h) and (GetTeamNum(h) ~= 1) and (GetTeamNum(h) ~= 0) then
                    if (h == M.parked1) or (h == M.parked2) or (h == M.parked3) or (h == M.parkturret1) or (h == M.parkturret2) then
                        if IsAlive(h) then
                            target_veh = h
                            break
                        end
                    end
                end
            end

            if target_veh then
                GetIn(M.rookie_pilot, target_veh)
                M.rookie_landed = false            -- Stop checking
                SetLabel(M.rookie_pilot, "Rookie") -- Keep label
            else
                -- No vehicle found? Wander?
                Goto(M.rookie_pilot, M.ccacomtower)
            end
        end
    end

    -- Alarm Logic & Stealth
    if (M.alarm_check < GetTime()) and (not M.alarm_on) then
        M.alarm_check = GetTime() + 5.0

        -- Distance check to turret spot
        local turret_detected = false
        if (not M.out_of_car) and IsValid("turret1_spot") then -- path point check
            if GetDistance(M.user, "turret1_spot") < 70.0 then turret_detected = true end
        end

        if turret_detected then
            subtit.Play("misn0710.wav")
            SetObjectiveOn(M.ccacomtower)
            SetLabel(M.ccacomtower, "Radar Array")
            M.alarm_on = true
        end
    end

    if not M.first_objective then
        if M.alarm_on then
            -- Alarm Sound
            if IsAlive(M.ccacomtower) and (GetDistance(M.user, M.ccacomtower) < 170.0) and (not M.alarm_sound) then
                subtit.Play("misn0708.wav")
                M.alarm_timer = GetTime() + 6.0
                M.alarm_sound = true
            end
            if M.alarm_sound and (M.alarm_timer < GetTime()) then
                M.alarm_sound = false
            end

            -- Turret Move
            if not M.turret_move then
                SetObjectiveOn(M.ccacomtower)
                SetLabel(M.ccacomtower, "Radar Array")
                Retreat(M.guard_turret1, M.ccacomtower)
                Retreat(M.guard_turret2, M.ccacomtower)
                M.turret_move = true
            end

            -- Evac Logic / Spawn Pilots
            if not M.start_evac then
                M.unit_spawn_time = GetTime() + DiffUtils.ScaleTimer(20.0)
                M.start_evac = true
            end

            if M.start_evac and (M.unit_spawn_time < GetTime()) and (not M.unit_spawn) then
                -- Spawn pilots
                M.pilot1 = BuildObject("sspilo", 2, "hut2_spawn")
                M.pilot2 = BuildObject("sspilo", 2, "hut2_spawn")
                M.pilot3 = BuildObject("sspilo", 2, "hut2_spawn")
                M.pilot4 = BuildObject("sspilo", 2, "hut1_spawn")
                M.pilot5 = BuildObject("sspilo", 2, "hut1_spawn")

                -- Convert parked turrets
                if M.parkturret1 ~= M.user then
                    M.spawn_turret1 = BuildObject("svturr", 2, M.parkturret1)
                    Defend(M.spawn_turret1)
                    RemoveObject(M.parkturret1)
                end
                if M.parkturret2 ~= M.user then
                    M.spawn_turret2 = BuildObject("svturr", 2, M.parkturret2)
                    Defend(M.spawn_turret2)
                    RemoveObject(M.parkturret2)
                end

                -- Pilots retreat to tanks
                if IsAlive(M.parked1) then Retreat(M.pilot1, M.parked1) end
                if IsAlive(M.parked2) then Retreat(M.pilot2, M.parked2) end
                if IsAlive(M.parked3) then Retreat(M.pilot3, M.parked3) end

                M.unit_spawn = true
            end

            -- Check if pilots reached vehicles (Lua simplification: just check aliveness/proximity)
            if M.unit_spawn and (not M.alarm_special) then -- alarm_special means caused by damage not proximity (mostly)
                if (not IsAlive(M.pilot1)) and IsAlive(M.parked1) then Attack(M.parked1, M.user) end
                if (not IsAlive(M.pilot2)) and IsAlive(M.parked2) then Attack(M.parked2, M.user) end
                if (not IsAlive(M.pilot3)) and IsAlive(M.parked3) then Attack(M.parked3, M.user) end
            end

            -- Forces Enroute condition (Tower health)
            if IsAlive(M.ccacomtower) and (GetHealth(M.ccacomtower) < 0.5) and (not M.forces_enroute) then
                if IsAlive(M.svpatrol1_2) then Goto(M.svpatrol1_2, M.ccacomtower) end
                if IsAlive(M.svpatrol3_1) then Goto(M.svpatrol3_1, M.ccacomtower) end
                if IsAlive(M.svpatrol4_1) then Goto(M.svpatrol4_1, M.ccacomtower) end
                M.forces_enroute = true
            end
        end
    end

    -- Parachute / Commando Logic
    if not M.first_objective then
        if (not M.alarm_on) and (not M.out_of_car) and (GetDistance(M.user, "camera_geyser") < 160.0) then
            SetObjectiveOn(M.ccacomtower)
            SetLabel(M.ccacomtower, "Radar Array")
            M.out_of_car = true

            -- Restored Parachute Camera
            M.parachute_camera_time = GetTime() + 5.0
        end

        -- Parachute Cinematic (C++: cute_camera)
        if M.out_of_car and (not M.parachute_camera_ready) and (M.parachute_camera_time < GetTime()) then
            CameraReady()
            M.parachute_camera_time = GetTime() + 5.0
            M.parachute_camera_ready = true
        end

        if M.parachute_camera_ready and (not M.parachute_camera_off) then
            CameraObject(M.user, 800, 800, 10, M.user)
            if (M.parachute_camera_time < GetTime()) or CameraCancelled() then
                CameraFinish()
                M.parachute_camera_off = true
            end
        end

        if M.out_of_car and (not M.vehicle_stolen) then
            if IsOdf(M.user, "svtank") or IsOdf(M.user, "svfigh") or IsOdf(M.user, "svturr") then
                M.vehicle_stolen = true
            end
        end

        -- Trigger 1: Damage Check
        if (not M.trigger1) and M.out_of_car then
            local function Damaged(h) return IsAlive(h) and (GetHealth(h) < 0.95) end
            if Damaged(M.ccaguntower1) or Damaged(M.ccaguntower2) or Damaged(M.ccacomtower) or
                Damaged(M.powrplnt1) or Damaged(M.barrack1) or Damaged(M.barrack2) or
                Damaged(M.parked1) or Damaged(M.parked2) or Damaged(M.parked3) or
                Damaged(M.parkturret1) or Damaged(M.parkturret2) then
                M.trigger1 = true
            end
        end

        if M.trigger1 and (not M.alarm_on) then
            M.alarm_on = true
            if not M.vehicle_stolen then M.alarm_special = true end
        end

        -- External Alarm Trigger (from vehicles attacking)
        if (not M.alarm_on) and (not M.out_of_car) then
            local function NearTower(h) return IsAlive(h) and (GetDistance(h, "turret1_spot") < 100.0) end
            if NearTower(M.wingman1) or NearTower(M.wingman2) or NearTower(M.wingtank1) or NearTower(M.new_tank1) or NearTower(M.new_tank2) then
                subtit.Play("misn0709.wav")
                M.alarm_on = true
            end
        end
    end

    -- Stealth Reinforcements (Rebuild Fighters if undetected)
    if (not M.first_objective) and (not M.retreat_success) and (not M.detected_message) then
        if IsAlive(M.ccarecycle) then
            -- Patrol 1
            if (not IsAlive(M.svpatrol1_1)) and (not IsAlive(M.svpatrol1_2)) then
                M.svpatrol1_1 = BuildObject("svfigh", 2, M.ccarecycle); Patrol(M.svpatrol1_1, "patrol_path3")
                M.svpatrol1_2 = BuildObject("svfigh", 2, M.ccarecycle); Patrol(M.svpatrol1_2, "patrol_path3")
            end
            -- Patrol 3
            if (not IsAlive(M.svpatrol3_1)) and (not IsAlive(M.svpatrol3_2)) then
                M.svpatrol3_1 = BuildObject("svfigh", 2, M.ccarecycle); Patrol(M.svpatrol3_1, "patrol_path1")
                M.svpatrol3_2 = BuildObject("svfigh", 2, M.ccarecycle); Patrol(M.svpatrol3_2, "patrol_path1")
            end
            -- Patrol 4
            if (not IsAlive(M.svpatrol4_1)) and (not IsAlive(M.svpatrol4_2)) then
                M.svpatrol4_1 = BuildObject("svfigh", 2, M.ccarecycle); Patrol(M.svpatrol4_1, "patrol_path2")
                M.svpatrol4_2 = BuildObject("svfigh", 2, M.ccarecycle); Patrol(M.svpatrol4_2, "patrol_path2")
            end
        end
    end

    -- Retreat Logic (Runner System)
    if (not M.first_objective) and (not M.retreat_success) and IsAlive(M.ccarecycle) and (not M.alarm_on) then
        local patrols = { M.svpatrol1_1, M.svpatrol1_2, M.svpatrol2_1, M.svpatrol2_2, M.svpatrol3_1, M.svpatrol3_2 }

        for i, p in ipairs(patrols) do
            if IsAlive(p) then
                local is_runner = (GetLabel(p) == "Runner")

                if (not is_runner) and (GetDistance(M.user, p) < 50.0) then
                    Retreat(p, M.ccarecycle)
                    SetLabel(p, "Runner")
                    is_runner = true
                end

                if is_runner then
                    -- Check Success (Reached Base)
                    if GetDistance(p, M.ccarecycle) < 100.0 then
                        M.retreat_success = true
                        SetLabel(p, "Runner (Safe)")
                    end
                end
            elseif (not IsAlive(p)) and (aiCore.param and aiCore.param[p] == "Runner") then
                -- Logic for runner killed if needed
            end
        end
    end

    if M.retreat_success and (not M.detected_message) then
        subtit.Play("misn0707.wav") -- "One of the runners made it back"
        M.detected_message = true

        -- Spawn Tanks Layout (Replacing Fighters)
        if IsAlive(M.ccarecycle) then
            local function SpawnTankPatrol(path)
                local t1 = BuildObject("svtank", 2, M.ccarecycle); Patrol(t1, path)
                local t2 = BuildObject("svtank", 2, M.ccarecycle); Patrol(t2, path)
                return t1, t2
            end

            M.svpatrol1_1, M.svpatrol1_2 = SpawnTankPatrol("patrol_path1")
            M.svpatrol3_1, M.svpatrol3_2 = SpawnTankPatrol("patrol_path1")
        end
    end

    -- Final Phase: Radar Destroyed
    if (not IsAlive(M.ccacomtower)) and (not M.first_objective) then
        subtit.Play("misn0714.wav")
        M.radar_camera_time = GetTime() + 10.0
        M.radar_next_shot_time = GetTime() + 20.0
        M.next_mission_time = GetTime() + 7.5

        -- Start Cinematic
        CameraReady()
        M.radar_shot1 = true

        M.first_objective = true
    end

    -- Radar Cinematic Logic (Restored C++ shot1/shot2)
    if M.radar_shot1 then
        CameraPath("radar_path", 4000, 1000, "radar_geyser")
        if (M.radar_camera_time < GetTime()) then
            M.radar_shot1 = false
            M.radar_shot2 = true
        end
    end

    if M.radar_shot2 then
        CameraPath("movie_cam_spawn", 160, 0, "show_geyser")
        if (not M.radar_camera_off) and (M.radar_next_shot_time < GetTime()) then
            CameraFinish()
            M.radar_shot2 = false
            M.radar_camera_off = true
        end
    end

    if (M.radar_shot1 or M.radar_shot2) and (not M.radar_camera_off) then
        if CameraCancelled() then
            M.radar_shot1 = false
            M.radar_shot2 = false
            CameraFinish()
            M.radar_camera_off = true
        end
    end

    if M.first_objective and (not M.next_mission) and (M.next_mission_time < GetTime()) then
        M.nsdfrecycle = BuildObject("avrec", 1, "recycle_spawn")
        M.nsdfmuf = BuildObject("avfact", 1, "muf_spawn")
        Goto(M.nsdfrecycle, "recycle_path")
        Goto(M.nsdfmuf, "muf_path")

        M.nav6 = BuildObject("apcamr", 1, "recycle_cam_spawn")
        SetLabel(M.nav6, "Utah Rendezvous")

        AddScrap(1, DiffUtils.ScaleRes(30))
        SetScrap(2, DiffUtils.ScaleRes(60))
        SetAIP("misn07.aip")

        M.ccabaseguntower1 = BuildObject("sbtowe", 2, "base_tower1_spawn")

        ClearObjectives()
        AddObjective("misn0701.otf", "green")
        AddObjective("misn0703.otf", "white")
        AddObjective("misn0702.otf", "white")

        M.next_mission = true
    end

    if M.next_mission and (not IsAlive(M.ccarecycle)) then
        M.second_objective = true
    end

    if M.next_mission and (not M.utah_found) and IsAlive(M.nsdfrecycle) then
        if GetDistance(M.user, M.nsdfrecycle) < 200.0 then
            ClearObjectives()
            AddObjective("misn0703.otf", "green")
            AddObjective("misn0702.otf", "white")
            M.utah_found = true
        end
    end

    -- Win/Loss
    if M.next_mission and (not IsAlive(M.nsdfrecycle)) and (not M.game_over) then
        subtit.Play("misn0712.wav")
        if not M.utah_found then
            ClearObjectives()
            AddObjective("misn0701.otf", "green")
            AddObjective("misn0703.otf", "red")
            AddObjective("misn0702.otf", "white")
        end
        FailMission(GetTime() + 15.0, "misn07f1.des")
        M.game_over = true
    end

    if M.first_objective and M.second_objective and (not M.game_over) then
        subtit.Play("misn0713.wav")
        SucceedMission(GetTime() + 15.0, "misn07w1.des")
        M.game_over = true
    end
end

function Save()
    return M, aiCore.Save()
end

function Load(missionData, aiData)
    M = missionData
    if aiData then aiCore.Load(aiData) end
    aiCore.Bootstrap()
    ApplyQOL()
    subtit.Initialize()
end
