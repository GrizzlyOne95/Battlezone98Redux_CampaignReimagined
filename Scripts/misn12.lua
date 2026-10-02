-- Faithful stock misn12 port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misn12Mission.cpp.
-- Source blob: 547a9e0849cd16070060e31f26cf6aa8c4d14b61.
-- Original disabled C++ remains in comments at its corresponding locations.
-- Complete native source/serialization: References/Misn12Source/.
-- Single-player mission; no EXU/OpenShim or campaign helpers required.
local M

local function NewState()
    local state = {}
    state.start_done = false
    state.check_point1_done = false
    state.check_point2_done = false
    state.check_point3_done = false
    state.check_point4_done = false
    state.check_point5_done = false
    state.check1 = false
    state.check2 = false
    state.check3 = false
    state.check4 = false
    state.objective1 = false
    state.out_of_order1 = false
    state.out_of_order2 = false
    state.out_of_order3 = false
    state.out_of_order4 = false
    state.out_of_order5 = false
    state.interface_connect = false
    state.link_broken = false
    state.interface_complete = false
    state.warning_message = false
    state.cca_message1 = false
    state.cca_message2 = false
    state.cca_message3 = false
    state.cca_message4 = false
    state.identify_message = false
    state.cca_warning_message = false
    state.better_message = false
    state.real_bad = false
    state.enter_base = false
    state.did_it_right = false
    state.straight_to_5 = false
    state.discovered = false
    state.noise = false
    state.camera_on = false
    state.camera_off = false
    state.camera1 = false
    state.camera2 = false
    state.camera3 = false
    state.camera4 = false
    state.camera5 = false
    state.key_captured = false
    state.over = false
    state.checked_in = false
    state.going_again = false
    state.key_gone = false
    state.game_blown = false
    state.final_warned = false
    state.last_warned = false
    state.follow_spawn = false
    state.good1 = false
    state.good2 = false
    state.good3 = false
    state.good1_off = false
    state.good2_off = false
    state.good3_off = false
    state.dead_meat = false
    state.patrol1_create = false
    state.patrol2_create = false
    state.patrol3_create = false
    state.patrol4_create = false
    state.patrol1_moved1 = false
    state.patrol2_moved1 = false
    state.patrol3_moved1 = false
    state.patrol4_moved1 = false
    state.patrol1_moved2 = false
    state.patrol2_moved2 = false
    state.patrol3_moved2 = false
    state.patrol4_moved2 = false
    state.patrol1_1_gone = false
    state.patrol1_2_gone = false
    state.patrol2_1_gone = false
    state.patrol2_2_gone = false
    state.patrol3_1_gone = false
    state.patrol3_2_gone = false
    state.patrol4_1_gone = false
    state.patrol4_2_gone = false
    state.p1_1center = false
    state.p2_1center = false
    state.p2_2center = false
    state.p3_1center = false
    state.p3_2center = false
    state.p4_1center = false
    state.p4_2center = false
    state.win = false
    state.game_over = false
    state.camera_swap1 = false
    state.camera_swap2 = false
    state.camera_swap_back = false
    state.out_of_ship = false
    state.camera_noise = false
    state.blown_otf = false
    state.grump = false
    state.countdown_time = 99999.0
    state.interface_time = 99999.0
    state.warning_repeat_time = 99999.0
    state.next_message_time = 99999.0
    state.next_noise_time = 99999.0
    state.camera_time = 99999.0
    state.camera_on_time = 99999.0
    state.win_check_time = 99999.0
    state.start_patrol = 99999.0
    state.key_check = 99999.0
    state.wait_time = 99999.0
    state.key_remove = 99999.0
    state.death_spawn = 99999.0
    state.final_warning = 99999.0
    state.last_warning = 99999.0
    state.remove_patrol1_2 = 99999.0
    state.patrol1_1_time = 99999.0
    state.patrol1_2_time = 99999.0
    state.patrol2_1_time = 99999.0
    state.patrol2_2_time = 99999.0
    state.patrol3_1_time = 99999.0
    state.patrol3_2_time = 99999.0
    state.patrol4_1_time = 99999.0
    state.patrol4_2_time = 99999.0
    state.swap_check = 99999.0
    state.next_second = 99999.0
    state.grump_time = 99999.0
    state.user = nil
    state.user_tank = nil
    state.center = nil
    state.center_cam = nil
    state.start_cam = nil
    state.check2_cam = nil
    state.check3_cam = nil
    state.check4_cam = nil
    state.goal_cam = nil
    state.nav1 = nil
    state.key_ship = nil
    state.spawn_geyser = nil
    state.choke_geyser = nil
    state.check2_geyser = nil
    state.center_geyser = nil
    state.checkpoint1 = nil
    state.checkpoint2 = nil
    state.checkpoint3 = nil
    state.checkpoint4 = nil
    state.ccacom_tower = nil
    state.ccasilo1 = nil
    state.ccasilo2 = nil
    state.ccasilo3 = nil
    state.ccasilo4 = nil
    state.guard1 = nil
    state.guard2 = nil
    state.guard3 = nil
    state.guard4 = nil
    state.spawn_point1 = nil
    state.spawn_point2 = nil
    state.guard_fighter = nil
    state.parked_fighter = nil
    state.parked_tank1 = nil
    state.parked_tank2 = nil
    state.guard_turret = nil
    state.pturret1 = nil
    state.pturret2 = nil
    state.pturret3 = nil
    state.pturret4 = nil
    state.pturret5 = nil
    state.pturret6 = nil
    state.patrol1_1 = nil
    state.patrol1_2 = nil
    state.patrol2_1 = nil
    state.patrol2_2 = nil
    state.patrol3_1 = nil
    state.patrol3_2 = nil
    state.patrol4_1 = nil
    state.patrol4_2 = nil
    state.guard_tank1 = nil
    state.guard_tank2 = nil
    state.death_squad1 = nil
    state.death_squad2 = nil
    state.death_squad3 = nil
    state.death_squad4 = nil
    state.follower = nil
    state.ccamuf = nil
    state.audmsg = 0
    return state
end
M = NewState()

-- The native helper checks object existence, rather than life or pilot status.
-- Preserve that exact test for the key ship with the stock IsValid API.
local function IsVehicleAlive(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

-- Preserve native invalid-handle distance behavior without selecting a nil
-- position overload. This only affects missing/removed objects, not thresholds.
local function Distance(from, to)
    if from == nil or from == 0 or not IsValid(from) then return math.huge end
    if to == nil or to == 0 then return math.huge end
    if type(to) ~= "string" and not IsValid(to) then return math.huge end
    return GetDistance(from, to)
end

function Start()
    M = NewState()
    --[==[ Here's where you set the values at the start. ]==]
    M.start_done = false
    M.key_captured = false
    M.check_point1_done = false
    M.check_point2_done = false
    M.check_point3_done = false
    M.check_point4_done = false
    M.check_point5_done = false
    M.check1 = false
    M.check2 = false
    M.check3 = false
    M.check4 = false
    M.objective1 = false
    M.out_of_order1 = false
    M.out_of_order2 = false
    M.out_of_order3 = false
    M.out_of_order4 = false
    M.out_of_order5 = false
    M.interface_connect = false
    M.link_broken = false
    M.interface_complete = false
    M.warning_message = false
    M.cca_message1 = false
    M.cca_message2 = false
    M.cca_message3 = false
    M.cca_message4 = false
    M.enter_base = false
    M.did_it_right = false
    M.discovered = false
    M.straight_to_5 = false
    M.noise = false
    M.camera_on = false
    M.camera_off = false
    M.camera1 = false
    M.camera2 = false
    M.camera3 = false
    M.camera4 = false
    M.camera5 = false
    M.win = false
    M.checked_in = false
    M.identify_message = false
    M.cca_warning_message = false
    M.better_message = false
    M.real_bad = false
    M.over = false
    M.going_again = false
    M.key_gone = false
    M.game_blown = false
    M.final_warned = false
    M.last_warned = false
    M.follow_spawn = false
    M.good1 = false
    M.good2 = false
    M.good3 = false
    M.good1_off = false
    M.good2_off = false
    M.good3_off = false
    M.dead_meat = false
    M.patrol1_create = false
    M.patrol2_create = false
    M.patrol3_create = false
    M.patrol4_create = false
    M.patrol1_moved1 = false
    M.patrol2_moved1 = false
    M.patrol3_moved1 = false
    M.patrol4_moved1 = false
    M.patrol1_moved2 = false
    M.patrol2_moved2 = false
    M.patrol3_moved2 = false
    M.patrol4_moved2 = false
    M.patrol1_1_gone = false
    M.patrol1_2_gone = false
    M.patrol2_1_gone = false
    M.patrol2_2_gone = false
    M.patrol3_1_gone = false
    M.patrol3_2_gone = false
    M.patrol4_1_gone = false
    M.patrol4_2_gone = false
    M.p1_1center = false
    M.p2_1center = false
    M.p2_2center = false
    M.p3_1center = false
    M.p3_2center = false
    M.p4_1center = false
    M.p4_2center = false
    M.game_over = false
    M.camera_swap1 = false
    M.camera_swap2 = false
    M.camera_swap_back = false
    M.camera_noise = false
    M.out_of_ship = false
    M.blown_otf = false
    M.grump = false
    M.warning_repeat_time = 99999.0
    M.countdown_time = 99999.0
    M.camera_on_time = 99999.0
    M.interface_time = 99999.0
    M.next_noise_time = 99999.0
    M.camera_time = 99999.0
    M.next_message_time = 99999.0
    M.win_check_time = 99999.0
    M.start_patrol = 99999.0
    M.key_check = 99999.0
    M.wait_time = 99999.0
    M.key_remove = 99999.0
    M.death_spawn = 99999.0
    M.final_warning = 99999.0
    M.last_warning = 99999.0
    M.remove_patrol1_2 = 99999.0
    M.patrol1_1_time = 99999.0
    M.patrol1_2_time = 99999.0
    M.patrol2_1_time = 99999.0
    M.patrol2_2_time = 99999.0
    M.patrol3_1_time = 99999.0
    M.patrol3_2_time = 99999.0
    M.patrol4_1_time = 99999.0
    M.patrol4_2_time = 99999.0
    M.swap_check = 99999.0
    M.grump_time = 99999.0
    M.next_second = 0
    M.key_ship = nil
    M.checkpoint1 = GetHandle("checktower1")
    M.checkpoint2 = GetHandle("svguntower2")
    M.checkpoint3 = GetHandle("svmuf")
    M.checkpoint4 = GetHandle("svsilo1")
    M.center = GetHandle("center")
    --	ccasilo1 = GetHandle ("svsilo1");
    M.ccasilo2 = GetHandle("svsilo2")
    M.ccasilo3 = GetHandle("svsilo3")
    M.ccasilo4 = GetHandle("svsilo4")
    M.ccamuf = GetHandle("svmuf")
    M.ccacom_tower = GetHandle("svcom_tower")
    M.spawn_point1 = GetHandle("spawn_geyser1")
    M.spawn_point2 = GetHandle("spawn_geyser2")
    M.nav1 = GetHandle("apcamr20_camerapod")
    M.spawn_geyser = GetHandle("spawn_geyser")
    M.choke_geyser = GetHandle("choke_geyser")
    M.check2_geyser = GetHandle("check2_geyser")
    M.center_geyser = GetHandle("center_geyser")
    M.guard_fighter = GetHandle("pfighter2")
    M.parked_fighter = GetHandle("pfighter1")
    M.parked_tank2 = GetHandle("ptank2")
    M.parked_tank1 = GetHandle("ptank1")
    M.guard_turret = GetHandle("turret6")
    M.pturret1 = GetHandle("turret1")
    M.pturret2 = GetHandle("turret2")
    M.pturret3 = GetHandle("turret3")
    M.pturret4 = GetHandle("turret4")
    M.pturret5 = GetHandle("turret5")
    M.pturret6 = GetHandle("turret6")
    M.patrol1_1 = GetHandle("svfigh1_1")
    M.patrol1_2 = GetHandle("svfigh1_2")
    M.patrol2_1 = GetHandle("svfigh2_1")
    M.patrol2_2 = GetHandle("svfigh2_2")
    M.patrol3_1 = GetHandle("svfigh3_1")
    M.patrol3_2 = GetHandle("svfigh3_2")
    M.patrol4_1 = GetHandle("svfigh4_1")
    M.patrol4_2 = GetHandle("svfigh4_2")
    M.guard_tank1 = GetHandle("gtank1")
    M.guard_tank2 = GetHandle("gtank2")
    M.follower = nil
    M.death_squad1 = nil
    M.death_squad2 = nil
    M.death_squad3 = nil
    M.death_squad4 = nil
    M.guard1 = nil
    M.guard2 = nil
    M.guard3 = nil
    M.guard4 = nil
    M.center_cam = nil
    M.start_cam = nil
    M.check2_cam = nil
    M.check3_cam = nil
    M.check4_cam = nil
    M.goal_cam = nil
end

function AddObject(h)
    -- Original AddObject(Handle h) is empty.
end

function Update(dt)
    -- START OF SCRIPT
    M.user = GetPlayerHandle()
    --assigns the player a handle every frame
    if not M.start_done then
        AudioMessage("misn1200.wav")
        M.user_tank = GetPlayerHandle()
        -- this assigns the tank a handle
        --		Defend(key_ship);
        ClearObjectives()
        AddObjective("misn1200.otf", "white")
        Defend(M.guard_tank1)
        Defend(M.guard_tank2)
        Defend(M.patrol1_1)
        Defend(M.patrol1_2)
        Defend(M.patrol2_1)
        Defend(M.patrol2_2)
        Defend(M.patrol3_1)
        Defend(M.patrol3_2)
        Defend(M.patrol4_1)
        Defend(M.patrol4_2)
        StartCockpitTimer(1200, 300, 120)
        SetObjectiveOn(M.checkpoint1)
        SetObjectiveName(M.checkpoint1, "Check Point")
        M.center_cam = BuildObject("apcamr", 3, "center_cam")
        M.start_cam = BuildObject("apcamr", 3, "start_cam")
        M.check2_cam = BuildObject("apcamr", 3, "check2_cam")
        M.check3_cam = BuildObject("apcamr", 3, "check3_cam")
        M.check4_cam = BuildObject("apcamr", 3, "check4_cam")
        M.goal_cam = BuildObject("apcamr", 3, "goal_cam")
        M.key_ship = BuildObject("svfi12", 2, M.spawn_geyser)
        SetWeaponMask(M.key_ship, 3)
        Goto(M.key_ship, "first_path")
        -- gets the patrol ship to move towards checkpoint1
        M.key_check = GetTime() + 2.0
        CameraReady()
        M.camera_time = GetTime() + 12.0
        -- Port safety: validate the object before the native SetName equivalent;
        -- missing/deleted nav objects are skipped without changing mission flags or timing.
        if IsValid(M.nav1) then
            SetObjectiveName(M.nav1, "Drop Zone")
        end
        M.start_done = true
    end
    if IsAlive(M.ccacom_tower) then
        if GetTime() > M.next_second then
            AddHealth(M.ccacom_tower, 200.0)
            M.next_second = GetTime() + 1.0
        end
    end
    -- this what happens if the player is discovered before taking over the ship
    if (not M.game_blown) and (not M.key_captured) then
        if (IsAlive(M.user_tank)) and (GetHealth(M.user_tank) < 0.90) then
            AudioMessage("misn1213.wav")
            M.death_spawn = GetTime() + 5.0
            M.game_blown = true
        end
    end
    if IsVehicleAlive(M.key_ship) then
        if (not M.game_blown) and (not M.key_captured) and (GetHealth(M.key_ship) < 0.50) then
            AudioMessage("misn1228.wav")
            M.death_spawn = GetTime() + 5.0
            M.game_blown = true
        end
    end
    -- this is what happens is the player tries to get in with his tank
    if (IsAlive(M.user_tank)) and (Distance(M.user_tank, M.checkpoint1) < 75.0) and (not M.key_captured) and (not M.game_blown) then
        AudioMessage("misn1213.wav")
        M.death_spawn = GetTime() + 5.0
        ClearObjectives()
        AddObjective("misn1200.otf", "red")
        M.game_blown = true
    end
    -- this is game_blown code
    if (M.game_blown) and (M.death_spawn < GetTime()) then
        M.death_spawn = GetTime() + 120.0
        M.death_squad1 = BuildObject("svfigh", 2, M.spawn_geyser)
        M.death_squad2 = BuildObject("svfigh", 2, M.spawn_geyser)
        M.death_squad3 = BuildObject("svltnk", 2, M.spawn_geyser)
        M.death_squad4 = BuildObject("svltnk", 2, M.spawn_geyser)
        Attack(M.death_squad1, M.user)
        Attack(M.death_squad2, M.user)
        Attack(M.death_squad3, M.user)
        Attack(M.death_squad4, M.user)
    end
    if (M.game_blown) and (not IsAlive(M.user_tank)) and (not M.dead_meat) then
        SetPerceivedTeam(M.user, 1)
        M.dead_meat = true
    end
    -- this is the start of the camera during the players briefing
    if (M.start_done) and (not M.camera4) then
        CameraPath("start_camera_path", 4000, 900, M.ccacom_tower)
    end
    if ((CameraCancelled()) or (M.camera_time < GetTime())) and (not M.camera4) then
        CameraFinish()
        M.camera4 = true
    end
    -- this is the start of patroling the cca ships
    if (M.camera_off) and (not M.patrol1_create) then
        -- change start_done to key_captured
        Goto(M.patrol1_1, "path1_to")
        Goto(M.patrol1_2, "path1_to")
        M.patrol1_create = true
    end
    if (M.patrol1_create) and (IsAlive(M.patrol1_1)) and (Distance(M.patrol1_1, M.checkpoint1) < 50.0) and (not M.patrol1_moved1) then
        if (IsAlive(M.patrol1_2) and (Distance(M.patrol1_2, M.checkpoint1) < 70.0)) then
            Goto(M.patrol1_1, "path1_from")
            Goto(M.patrol1_2, "path1_from")
            M.patrol1_moved1 = true
        end
    end
    if (M.patrol1_moved1) and (IsAlive(M.patrol1_1)) and (Distance(M.patrol1_1, M.center_geyser) < 50.0) and (not M.patrol1_moved2) then
        if (IsAlive(M.patrol1_2) and (Distance(M.patrol1_2, M.center_geyser) < 50.0)) then
            Goto(M.patrol1_1, "path2")
            Patrol(M.patrol1_2, "path5")
            Goto(M.patrol2_1, "path3")
            M.patrol2_1_time = GetTime() + 15.0
            M.patrol1_moved2 = true
        end
    end
    -- move 2_2
    if (M.patrol1_moved2) and (IsAlive(M.patrol1_1)) and (Distance(M.patrol1_1, M.check2_geyser) < 400.0) and (not M.patrol2_moved1) then
        Goto(M.patrol2_2, "path2")
        Goto(M.patrol4_1, "path4")
        M.p4_1center = true
        M.patrol2_2_time = GetTime() + 11.0
        M.patrol1_1_time = GetTime() + 10.0
        M.patrol4_1_time = GetTime() + 12.0
        M.patrol2_moved1 = true
    end
    -- send 3_1 on route
    if (IsAlive(M.patrol2_1)) and (Distance(M.patrol2_1, M.ccamuf) < 400.0) and (not M.patrol3_moved1) then
        Goto(M.patrol3_1, "path4")
        M.patrol3_1_time = GetTime() + 5.0
        M.p3_1center = true
        M.patrol3_moved1 = true
    end
    -- send 3_2 on route
    if (IsAlive(M.patrol2_2)) and (Distance(M.patrol2_2, M.ccamuf) < 400.0) and (not M.patrol3_moved2) then
        Goto(M.patrol3_2, "path4")
        M.p3_2center = true
        M.patrol3_2_time = GetTime() + 10.0
        M.patrol3_moved2 = true
    end
    -- send 4_2
    if (IsAlive(M.patrol3_1)) and (Distance(M.patrol3_1, M.checkpoint4) < 400.0) and (not M.patrol4_moved2) then
        Goto(M.patrol4_2, "path4")
        M.patrol4_2_time = GetTime() + 5.0
        M.p4_2center = true
        M.patrol4_moved2 = true
    end
    -- check patrols
    if (not M.real_bad) or (not M.game_blown) then
        -- 1_1
        if (IsAlive(M.patrol1_1)) and (M.patrol1_1_time < GetTime()) then
            M.patrol1_1_time = GetTime() + 10.0
            if (not M.p1_1center) and (Distance(M.patrol1_1, M.center_geyser) < 50.0) then
                Goto(M.patrol1_1, "path3")
                M.p1_1center = true
            else
                if Distance(M.patrol1_1, M.center_geyser) < 50.0 then
                    Goto(M.patrol1_1, "path2")
                    M.p1_1center = false
                else
                    if Distance(M.patrol1_1, M.ccamuf) < 70.0 then
                        Goto(M.patrol1_1, "path4")
                    end
                end
            end
        end
        -- 2_1
        if (IsAlive(M.patrol2_1)) and (M.patrol2_1_time < GetTime()) then
            M.patrol2_1_time = GetTime() + 10.0
            if (not M.p2_1center) and (Distance(M.patrol2_1, M.center_geyser) < 50.0) then
                -- BUGFIX: source commands patrol1_1 inside patrol2_1's route check.
                -- Command patrol2_1 so this pair follows its own path3 leg. The same
                -- route, distance gate, 10-second poll, and state transition remain;
                -- checkpoint/warning/uplink progression and spawn timing are unchanged.
                -- Original: Goto(patrol1_1, "path3");
                Goto(M.patrol2_1, "path3")
                M.p2_1center = true
            else
                if Distance(M.patrol2_1, M.center_geyser) < 50.0 then
                    Goto(M.patrol2_1, "path2")
                    M.p2_1center = false
                else
                    if Distance(M.patrol2_1, M.ccamuf) < 70.0 then
                        Goto(M.patrol2_1, "path4")
                    end
                end
            end
        end
        -- 2_2
        if (IsAlive(M.patrol2_2)) and (M.patrol2_2_time < GetTime()) then
            M.patrol2_2_time = GetTime() + 10.0
            if (not M.p2_2center) and (Distance(M.patrol2_2, M.center_geyser) < 50.0) then
                Goto(M.patrol2_2, "path3")
                M.p2_2center = true
            else
                if Distance(M.patrol2_2, M.center_geyser) < 50.0 then
                    Goto(M.patrol2_2, "path2")
                    M.p2_2center = false
                else
                    if Distance(M.patrol2_2, M.ccamuf) < 70.0 then
                        Goto(M.patrol2_2, "path4")
                    end
                end
            end
        end
        --3_1
        if (IsAlive(M.patrol3_1)) and (M.patrol3_1_time < GetTime()) then
            M.patrol3_1_time = GetTime() + 10.0
            if (not M.p3_1center) and (Distance(M.patrol3_1, M.center_geyser) < 50.0) then
                Goto(M.patrol3_1, "path3")
                M.p3_1center = true
            else
                if Distance(M.patrol3_1, M.center_geyser) < 50.0 then
                    Goto(M.patrol3_1, "path2")
                    M.p3_1center = false
                else
                    if Distance(M.patrol3_1, M.ccamuf) < 70.0 then
                        Goto(M.patrol3_1, "path4")
                    end
                end
            end
        end
        --3_2
        if (IsAlive(M.patrol3_2)) and (M.patrol3_2_time < GetTime()) then
            M.patrol3_2_time = GetTime() + 10.0
            if (not M.p3_2center) and (Distance(M.patrol3_2, M.center_geyser) < 50.0) then
                Goto(M.patrol3_2, "path3")
                M.p3_2center = true
            else
                if Distance(M.patrol3_2, M.center_geyser) < 50.0 then
                    Goto(M.patrol3_2, "path2")
                    M.p3_2center = false
                else
                    if Distance(M.patrol3_2, M.ccamuf) < 70.0 then
                        Goto(M.patrol3_2, "path4")
                    end
                end
            end
        end
        --4_1
        if (IsAlive(M.patrol4_1)) and (M.patrol4_1_time < GetTime()) then
            M.patrol4_1_time = GetTime() + 10.0
            if (not M.p4_1center) and (Distance(M.patrol4_1, M.center_geyser) < 50.0) then
                Goto(M.patrol4_1, "path3")
                M.p4_1center = true
            else
                if Distance(M.patrol4_1, M.center_geyser) < 50.0 then
                    Goto(M.patrol4_1, "path2")
                    M.p4_1center = false
                else
                    if Distance(M.patrol4_1, M.ccamuf) < 70.0 then
                        Goto(M.patrol4_1, "path4")
                    end
                end
            end
        end
        --4_2
        if (IsAlive(M.patrol4_2)) and (M.patrol4_2_time < GetTime()) then
            M.patrol4_2_time = GetTime() + 10.0
            if (not M.p4_2center) and (Distance(M.patrol4_2, M.center_geyser) < 50.0) then
                Goto(M.patrol4_2, "path3")
                M.p4_2center = true
            else
                if Distance(M.patrol4_2, M.center_geyser) < 50.0 then
                    Goto(M.patrol4_2, "path2")
                    M.p4_2center = false
                else
                    if Distance(M.patrol4_2, M.ccamuf) < 70.0 then
                        Goto(M.patrol4_2, "path4")
                    end
                end
            end
        end
    end
    --//////////// THIS ALL FALLS UNDER GAME BLOWN /////////////////////////////////////
    if not M.game_blown then
        -- this makes the key_ship stop at checkpoint1
        if (M.start_done) and (not M.key_captured) and (not M.checked_in) then
            if IsVehicleAlive(M.key_ship) then
                if (Distance(M.key_ship, M.checkpoint1) < 80.0) then
                    Stop(M.key_ship, 1)
                    M.wait_time = GetTime() + 20.0
                    M.checked_in = true
                end
            end
        end
        if (M.checked_in) and (M.wait_time < GetTime()) and (not M.going_again) and (not M.key_captured) then
            Goto(M.key_ship, "first_path")
            M.key_remove = GetTime() + 10.0
            M.going_again = true
        end
        if (M.going_again) and (M.key_remove < GetTime()) and (not M.key_captured) then
            M.key_remove = GetTime() + 3.0
            if Distance(M.key_ship, M.spawn_geyser) < 100.0 then
                RemoveObject(M.key_ship)
                M.key_ship = BuildObject("svfi12", 2, M.spawn_geyser)
                SetWeaponMask(M.key_ship, 3)
                Goto(M.key_ship, "first_path")
                M.checked_in = false
                M.going_again = false
            end
        end
        -- this will indicate when the player has taken over the cca fighter
        if (IsOdf(M.user, "svfi12")) and (not M.key_captured) then
            if IsAlive(M.user) then
                AddAmmo(M.user, 2000.0)
            end
            ClearObjectives()
            AddObjective("misn1200.otf", "green")
            AddObjective("misn1201.otf", "white")
            AddObjective("misn1202.otf", "white")
            AddObjective("misn1203.otf", "white")
            AddObjective("misn1204.otf", "white")
            AudioMessage("misn1217.wav")
            M.camera_time = GetTime() + 10.0
            if IsAlive(M.checkpoint1) then
                SetObjectiveOff(M.checkpoint1)
            end
            M.key_captured = true
        end
        if (M.key_captured) and ((IsOdf(M.user, "svfigh")) or (IsOdf(M.user, "svtank"))) and (not M.out_of_ship) then
            M.out_of_ship = true
        end
        if (M.out_of_ship) and (not M.grump) then
            if IsAlive(M.patrol1_1) then
                Attack(M.patrol1_1, M.user)
            end
            if IsAlive(M.patrol1_2) then
                Attack(M.patrol1_2, M.user)
            end
            if IsAlive(M.patrol2_1) then
                Attack(M.patrol2_1, M.user)
            end
            if IsAlive(M.patrol2_2) then
                Attack(M.patrol2_2, M.user)
            end
            if IsAlive(M.patrol3_1) then
                Attack(M.patrol3_1, M.user)
            end
            if IsAlive(M.patrol3_2) then
                Attack(M.patrol3_2, M.user)
            end
            if IsAlive(M.patrol4_1) then
                Attack(M.patrol4_1, M.user)
            end
            if IsAlive(M.patrol4_2) then
                Attack(M.patrol4_2, M.user)
            end
            if IsAlive(M.guard_tank1) then
                Attack(M.guard_tank1, M.user)
            end
            if IsAlive(M.guard_tank2) then
                Attack(M.guard_tank2, M.user)
            end
            if (not M.interface_complete) and (not M.blown_otf) then
                ClearObjectives()
                AddObjective("misn1206.otf", "white")
                M.blown_otf = true
            end
            M.grump_time = GetTime() + 180.0
            M.grump = true
        end
        if M.grump_time < GetTime() then
            M.grump = false
        end
        -- heres where we start the big movie
        if (M.key_captured) and (M.camera_time < GetTime()) and (not M.camera_on) and (not M.camera_off) then
            CameraReady()
            M.camera_on = true
        end
        if (M.camera_on) and (not M.camera1) and (not M.camera2) and (not M.camera3) and (not M.camera_off) then
            CameraObject(M.checkpoint2, 0, 1000, 6000, M.checkpoint2)
            M.audmsg = AudioMessage("misn1218.wav")
            M.camera_time = GetTime() + 6.0
            M.camera1 = true
        end
        if ((M.camera1) and (not M.camera2) and (not M.camera3) and (not M.camera_off)) and ((M.camera_time < GetTime()) or (CameraCancelled())) then
            StopAudioMessage(M.audmsg)
            CameraObject(M.checkpoint3, 3000, 3000, 3000, M.checkpoint3)
            M.audmsg = AudioMessage("misn1219.wav")
            M.camera_time = GetTime() + 6.0
            M.camera2 = true
        end
        if ((M.camera2) and (not M.camera3) and (not M.camera_off)) and ((M.camera_time < GetTime()) or (CameraCancelled())) then
            StopAudioMessage(M.audmsg)
            CameraObject(M.checkpoint4, - 1000, 1500, 4000, M.checkpoint4)
            M.audmsg = AudioMessage("misn1220.wav")
            M.camera_time = GetTime() + 6.0
            M.camera3 = true
        end
        if ((M.camera3) and (not M.camera_off)) and ((M.camera_time < GetTime()) or (CameraCancelled())) then
            StopAudioMessage(M.audmsg)
            AudioMessage("misn1221.wav")
            AudioMessage("misn1222.wav")
            CameraFinish()
            M.camera_off = true
        end
        -- this is where I script the how the player must check in at each check point
        --	if (!check2)
        --	{
        if Distance(M.user, M.checkpoint2) < 150.0 then
            M.check_point2_done = true
        end
        if (M.check_point2_done) and (Distance(M.user, M.checkpoint2) > 150.0) then
            M.check_point2_done = false
        end
        --	}
        --	if (!check3)
        --	{
        if Distance(M.user, M.checkpoint3) < 150.0 then
            M.check_point3_done = true
        end
        if (M.check_point3_done) and (Distance(M.user, M.checkpoint3) > 150.0) then
            M.check_point3_done = false
        end
        --	}
        --	if (!check4)
        --	{
        if Distance(M.user, M.checkpoint4) < 150.0 then
            M.check_point4_done = true
        end
        if (M.check_point4_done) and (Distance(M.user, M.checkpoint4) > 150.0) then
            M.check_point4_done = false
        end
        --	}
        if Distance(M.user, M.ccacom_tower) < 150.0 then
            M.check_point5_done = true
        end
        if (M.check_point5_done) and (Distance(M.user, M.ccacom_tower) > 150.0) then
            M.check_point5_done = false
        end
        -- the following is if the player does it right
        if not M.interface_complete then
            if (Distance(M.user, M.checkpoint2) < 70.0) and (not M.cca_warning_message) and (not M.identify_message) and (not M.check2) then
                CameraReady()
                M.good1 = true
                if M.good1 then
                    CameraObject(M.user, 0, 700, - 1500, M.user)
                    M.camera_time = GetTime() + 5.0
                    AudioMessage("misn1207.wav")
                    -- soviet voice that is calm
                    ClearObjectives()
                    AddObjective("misn1200.otf", "green")
                    AddObjective("misn1201.otf", "green")
                    AddObjective("misn1202.otf", "white")
                    AddObjective("misn1203.otf", "white")
                    AddObjective("misn1204.otf", "white")
                    M.check2 = true
                end
            end
            if (M.good1) and (M.camera_time < GetTime()) and (not M.good1_off) then
                CameraFinish()
                M.good1_off = true
            end
            if (M.check2) and (Distance(M.user, M.checkpoint3) < 70.0) and (not M.cca_warning_message) and (not M.identify_message) and (not M.check3) then
                CameraReady()
                M.good2 = true
                if M.good2 then
                    CameraObject(M.user, 0, 700, - 1500, M.user)
                    M.camera_time = GetTime() + 6.0
                    AudioMessage("misn1208.wav")
                    -- soviet voice that is calm
                    ClearObjectives()
                    AddObjective("misn1200.otf", "green")
                    AddObjective("misn1201.otf", "green")
                    AddObjective("misn1202.otf", "green")
                    AddObjective("misn1203.otf", "white")
                    AddObjective("misn1204.otf", "white")
                    M.check3 = true
                end
            end
            if (M.good2) and (M.camera_time < GetTime()) and (not M.good2_off) then
                CameraFinish()
                M.good2_off = true
            end
            if (Distance(M.user, M.checkpoint4) < 70.0) and (M.check3) and (not M.check4) and (not M.cca_warning_message) and (not M.identify_message) then
                CameraReady()
                M.good3 = true
                if M.good3 then
                    CameraObject(M.user, 0, 700, - 1500, M.user)
                    M.camera_time = GetTime() + 6.0
                    AudioMessage("misn1209.wav")
                    -- soviet voice that is calm
                    ClearObjectives()
                    AddObjective("misn1200.otf", "green")
                    AddObjective("misn1201.otf", "green")
                    AddObjective("misn1202.otf", "green")
                    AddObjective("misn1203.otf", "green")
                    AddObjective("misn1204.otf", "white")
                    M.check4 = true
                end
            end
            if (M.good3) and (M.camera_time < GetTime()) and (not M.good3_off) then
                CameraFinish()
                M.good3_off = true
            end
        end
        --/////////////////////////////////////////////////////////////////////////////////////
        -- the TWOS
        -- if he goes to 2 and then straight to 4
        if (M.check2) and (not M.check3) and (M.check_point4_done) and (not M.cca_warning_message) and (not M.identify_message) and (not M.real_bad) then
            AudioMessage("misn1205.wav")
            -- your out of order scout - return to you posts
            ClearObjectives()
            AddObjective("misn1200.otf", "green")
            AddObjective("misn1201.otf", "green")
            AddObjective("misn1202.otf", "white")
            AddObjective("misn1203.otf", "yellow")
            AddObjective("misn1204.otf", "white")
            M.cca_warning_message = true
        end
        -- if he goes to 2 and then 4 and then back to 3 (recovers)
        if (M.check2) and (M.cca_warning_message) and (Distance(M.user, M.checkpoint3) < 70.0) and (not M.identify_message) and (not M.real_bad) and (not M.check4) then
            CameraReady()
            M.good2 = true
            if M.good2 then
                CameraObject(M.user, 0, 700, - 1500, M.user)
                M.camera_time = GetTime() + 6.0
                AudioMessage("misn1210.wav")
                -- soviet guy should laugh "you better now"
                ClearObjectives()
                AddObjective("misn1200.otf", "green")
                AddObjective("misn1201.otf", "green")
                AddObjective("misn1202.otf", "green")
                AddObjective("misn1203.otf", "green")
                AddObjective("misn1204.otf", "white")
                M.better_message = true
                M.check4 = true
            end
        end
        -- if he goes to 2 and then 4 and then back to 2
        if (M.check2) and (M.cca_warning_message) and (not M.check4) and (M.check_point2_done) and (not M.identify_message) and (not M.real_bad) then
            AudioMessage("misn1206.wav")
            -- identify yourself!
            M.next_message_time = GetTime() + 20.0
            ClearObjectives()
            AddObjective("misn1200.otf", "green")
            AddObjective("misn1201.otf", "green")
            AddObjective("misn1202.otf", "white")
            AddObjective("misn1203.otf", "red")
            AddObjective("misn1204.otf", "white")
            M.identify_message = true
        end
        -- this is when he goes to 2 and then 4 and then 5
        if (M.check2) and (M.cca_warning_message) and (not M.check4) and (M.check_point5_done) and (not M.identify_message) and (not M.real_bad) and (not M.check4) then
            AudioMessage("misn1206.wav")
            -- identify yourself!
            M.next_message_time = GetTime() + 20.0
            ClearObjectives()
            AddObjective("misn1200.otf", "green")
            AddObjective("misn1201.otf", "green")
            AddObjective("misn1202.otf", "white")
            AddObjective("misn1203.otf", "yellow")
            AddObjective("misn1204.otf", "red")
            M.identify_message = true
        end
        -- if he goes to 2 and then straigh to 5
        if (M.check2) and (M.check_point5_done) and (not M.check3) and (not M.cca_warning_message) and (not M.identify_message) and (not M.real_bad) then
            AudioMessage("misn1206.wav")
            -- identify yourself!
            M.next_message_time = GetTime() + 20.0
            ClearObjectives()
            AddObjective("misn1200.otf", "green")
            AddObjective("misn1201.otf", "green")
            AddObjective("misn1202.otf", "white")
            AddObjective("misn1203.otf", "white")
            AddObjective("misn1204.otf", "yellow")
            M.identify_message = true
        end
        -- if he goes to 2 and then 3 and then 5
        if (M.check3) and (not M.check4) and (M.check_point5_done) and (not M.cca_warning_message) and (not M.identify_message) and (not M.real_bad) then
            AudioMessage("misn1206.wav")
            -- identify yourself!
            M.next_message_time = GetTime() + 20.0
            ClearObjectives()
            AddObjective("misn1200.otf", "green")
            AddObjective("misn1201.otf", "green")
            AddObjective("misn1202.otf", "green")
            AddObjective("misn1203.otf", "white")
            AddObjective("misn1204.otf", "yellow")
            M.identify_message = true
        end
        --/ the THREES
        -- if he goes to 3 before going to 2
        if (M.check_point3_done) and (not M.check2) and (not M.cca_warning_message) and (not M.identify_message) and (not M.better_message) and (not M.real_bad) then
            AudioMessage("misn1205.wav")
            -- your out of order scout - return to you posts
            ClearObjectives()
            AddObjective("misn1200.otf", "green")
            AddObjective("misn1201.otf", "white")
            AddObjective("misn1202.otf", "yellow")
            AddObjective("misn1203.otf", "white")
            AddObjective("misn1204.otf", "white")
            M.cca_warning_message = true
        end
        -- if he goes to 3 and then goes back to 2 (recovers)	
        if (not M.check2) and (M.cca_warning_message) and (not M.identify_message) and (Distance(M.user, M.checkpoint2) < 70.0) and (not M.better_message) then
            -- doing better 
            CameraReady()
            M.good1 = true
            if M.good1 then
                CameraObject(M.user, 0, 700, - 1500, M.user)
                M.camera_time = GetTime() + 7.0
                AudioMessage("misn1210.wav")
                -- soviet guy should laugh "you better now"
                ClearObjectives()
                AddObjective("misn1200.otf", "green")
                AddObjective("misn1201.otf", "green")
                AddObjective("misn1202.otf", "green")
                AddObjective("misn1203.otf", "white")
                AddObjective("misn1204.otf", "white")
                M.better_message = true
            end
        end
        -- if he goes to 3 and then recovers to 2 then goes back to 3
        if (M.better_message) and (not M.check4) and (M.check_point3_done) and (not M.identify_message) and (not M.real_bad) then
            AudioMessage("misn1206.wav")
            -- identify yourself!
            M.next_message_time = GetTime() + 20.0
            ClearObjectives()
            AddObjective("misn1200.otf", "green")
            AddObjective("misn1201.otf", "green")
            AddObjective("misn1202.otf", "red")
            AddObjective("misn1203.otf", "white")
            AddObjective("misn1204.otf", "white")
            M.identify_message = true
        end
        -- if he goes to 3 and then recovers to 2 then goes to 5
        if (M.better_message) and (M.check_point5_done) and (not M.check4) and (not M.identify_message) and (not M.real_bad) then
            AudioMessage("misn1206.wav")
            -- identify yourself!
            M.next_message_time = GetTime() + 20.0
            ClearObjectives()
            AddObjective("misn1200.otf", "green")
            AddObjective("misn1201.otf", "green")
            AddObjective("misn1202.otf", "green")
            AddObjective("misn1203.otf", "white")
            AddObjective("misn1204.otf", "yellow")
            M.identify_message = true
        end
        -- if her goes to 3 and then to 4 without recovering
        if (not M.check2) and (M.check_point4_done) and (M.cca_warning_message) and (not M.better_message) and (not M.identify_message) and (not M.real_bad) then
            ClearObjectives()
            AddObjective("misn1200.otf", "green")
            AddObjective("misn1201.otf", "white")
            AddObjective("misn1202.otf", "yellow")
            AddObjective("misn1203.otf", "red")
            AddObjective("misn1204.otf", "white")
            M.real_bad = true
        end
        -- if her goes to 3 and then to 5 without recovering
        if (M.check_point5_done) and (M.cca_warning_message) and (not M.better_message) and (not M.identify_message) and (not M.real_bad) and (not M.check4) then
            ClearObjectives()
            AddObjective("misn1200.otf", "green")
            AddObjective("misn1201.otf", "white")
            AddObjective("misn1202.otf", "yellow")
            AddObjective("misn1203.otf", "white")
            AddObjective("misn1204.otf", "red")
            M.real_bad = true
        end
        -- if he goes to 3 and then recovers and then goes to 4
        if (M.better_message) and (Distance(M.user, M.checkpoint4) < 70.0) and (not M.identify_message) and (not M.real_bad) and (not M.check4) then
            CameraReady()
            M.good3 = true
            if M.good3 then
                CameraObject(M.user, 0, 700, - 1500, M.user)
                M.camera_time = GetTime() + 6.0
                AudioMessage("misn1209.wav")
                -- soviet voice that is calm
                ClearObjectives()
                AddObjective("misn1200.otf", "green")
                AddObjective("misn1201.otf", "green")
                AddObjective("misn1202.otf", "green")
                AddObjective("misn1203.otf", "green")
                AddObjective("misn1204.otf", "white")
                M.check4 = true
            end
        end
        -- the FOURS
        --if he goes straight to 4
        if (M.check_point4_done) and (not M.check2) and (not M.cca_warning_message) and (not M.identify_message) and (not M.real_bad) then
            AudioMessage("misn1206.wav")
            -- identify yourself!
            M.next_message_time = GetTime() + 20.0
            ClearObjectives()
            AddObjective("misn1200.otf", "green")
            AddObjective("misn1201.otf", "white")
            AddObjective("misn1202.otf", "white")
            AddObjective("misn1203.otf", "yellow")
            AddObjective("misn1204.otf", "white")
            M.identify_message = true
        end
        -- the FIVES
        -- new line for ccacom_tower - this is what happens when the player reaches the ccacomtower
        --if he goes straight to 5
        if (M.check_point5_done) and (not M.cca_warning_message) and (not M.check2) and (not M.identify_message) and (not M.real_bad) and (not M.straight_to_5) then
            AudioMessage("misn1206.wav")
            -- identify yourself!
            M.next_message_time = GetTime() + 15.0
            ClearObjectives()
            AddObjective("misn1200.otf", "green")
            AddObjective("misn1201.otf", "white")
            AddObjective("misn1202.otf", "white")
            AddObjective("misn1203.otf", "white")
            AddObjective("misn1204.otf", "yellow")
            M.identify_message = true
            M.straight_to_5 = true
        end
        -- if he goes to 5 with some slip ups
        if (M.check_point5_done) and (M.cca_warning_message) and (M.check4) and (not M.identify_message) and (not M.real_bad) and (not M.final_warned) then
            AudioMessage("misn1214.wav")
            -- explain yourself!
            M.final_warning = GetTime() + 20.0
            ClearObjectives()
            AddObjective("misn1200.otf", "green")
            AddObjective("misn1201.otf", "green")
            AddObjective("misn1202.otf", "green")
            AddObjective("misn1203.otf", "green")
            AddObjective("misn1204.otf", "yellow")
            M.final_warned = true
        end
        -- if he does it exactly right	
        if (M.check_point5_done) and (M.check4) and (not M.cca_warning_message) and (not M.identify_message) and (not M.real_bad) and (not M.did_it_right) then
            AudioMessage("misn1205.wav")
            -- can we help you scout
            M.last_warning = GetTime() + 30.0
            ClearObjectives()
            AddObjective("misn1200.otf", "green")
            AddObjective("misn1201.otf", "green")
            AddObjective("misn1202.otf", "green")
            AddObjective("misn1203.otf", "green")
            AddObjective("misn1204.otf", "green")
            M.did_it_right = true
        end
        if (M.did_it_right) and (M.last_warning < GetTime()) and (not M.final_warned) then
            AudioMessage("misn1214.wav")
            -- explain yourself!
            M.final_warning = GetTime() + 20.0
            M.final_warned = true
        end
        -- these are constants /////////////////////////////////////////////////////////////////
        -- this defines what happens under "cca_warning_message" conditions (if he goes out of order and then dilly-dallys)
        if (M.cca_warning_message) and (not M.better_message) and (not M.check4) and (not M.identify_message) and (not M.last_warned) then
            M.last_warning = GetTime() + 100.0
            M.last_warned = true
        end
        if (M.last_warned) and (M.last_warning < GetTime()) and (not M.better_message) and (not M.check4) and (not M.final_warned) then
            AudioMessage("misn1214.wav")
            -- explain yourself!
            M.final_warning = GetTime() + 40.0
            M.final_warned = true
        end
        if (M.final_warned) and (M.final_warning < GetTime()) and (not M.identify_message) then
            AudioMessage("misn1206.wav")
            -- identify yourself!
            M.next_message_time = GetTime() + 10.0
            M.identify_message = true
        end
        -- this defines what happens under "identify_message" conditions (if he is warned and does not recover in time)
        if (M.identify_message) and (M.next_message_time < GetTime()) and (not M.real_bad) then
            M.real_bad = true
        end
        if (M.identify_message) and (not M.real_bad) then
            if M.check_point5_done then
                Follow(M.guard_tank1, M.user)
                Follow(M.guard_tank2, M.user)
            else
                Goto(M.guard_tank1, M.ccacom_tower)
                Goto(M.guard_tank2, M.ccacom_tower)
            end
        end
        -- this defines what happens under "real_bad" conditions
        if (M.real_bad) and (not M.discovered) then
            AudioMessage("misn1211.wav")
            if not M.interface_connect then
                ClearObjectives()
                AddObjective("misn1206.otf", "white")
            end
            SetPerceivedTeam(M.user, 1)
            M.guard1 = BuildObject("svtank", 2, M.spawn_point1)
            M.guard2 = BuildObject("svtank", 2, M.spawn_point1)
            M.guard3 = BuildObject("svtank", 2, M.spawn_point2)
            M.guard4 = BuildObject("svtank", 2, M.spawn_point2)
            Goto(M.parked_tank2, M.ccacom_tower)
            Goto(M.parked_tank1, M.ccacom_tower)
            Attack(M.guard1, M.user, 1)
            Attack(M.guard2, M.user, 1)
            Attack(M.guard3, M.user, 1)
            Attack(M.guard4, M.user, 1)
            Attack(M.patrol1_1, M.user, 1)
            Attack(M.patrol1_2, M.user, 1)
            Attack(M.patrol2_1, M.user, 1)
            Attack(M.patrol2_2, M.user, 1)
            --		Attack (patrol3_1, user, 1);
            --		Attack (patrol3_2, user, 1);
            M.discovered = true
        end
        if (M.discovered) and (not IsAlive(M.guard1)) and (not IsAlive(M.guard2)) and (not IsAlive(M.guard3)) then
            M.guard1 = BuildObject("svtank", 2, M.spawn_point1)
            M.guard2 = BuildObject("svtank", 2, M.spawn_point1)
            M.guard3 = BuildObject("svtank", 2, M.spawn_point2)
            M.guard4 = BuildObject("svtank", 2, M.spawn_point2)
            Attack(M.guard1, M.user, 1)
            Attack(M.guard2, M.user, 1)
            Attack(M.guard3, M.user, 1)
            Attack(M.guard4, M.user, 1)
            if not M.follow_spawn then
                if IsAlive(M.pturret1) then
                    Goto(M.pturret1, "turret1_path")
                end
                if IsAlive(M.pturret6) then
                    Goto(M.pturret6, "turret2_path")
                end
            end
        end
        -- this is what happens when the player gets a warning message
        if (M.cca_warning_message) and (not M.follow_spawn) then
            Goto(M.pturret1, "turret1_path")
            Goto(M.pturret6, "turret2_path")
            if (Distance(M.user, M.checkpoint4)) > (Distance(M.user, M.checkpoint3)) then
                -- he's at 3
                M.follower = BuildObject("svfigh", 2, "3spawn")
                Follow(M.follower, M.user)
            else
                M.follower = BuildObject("svfigh", 2, "4spawn")
                Follow(M.follower, M.user)
            end
            M.follow_spawn = true
        end
        -- this is what happens when the player interfaces with the ccacomtower
        if (Distance(M.user, M.ccacom_tower) < 60.0) and (not M.interface_connect) and (not M.interface_complete) then
            AudioMessage("misn1201.wav")
            --uplink sound
            M.interface_connect = true
            M.interface_time = GetTime() + 45.0
        end
        if (Distance(M.user, M.ccacom_tower) > 75.0) and (M.interface_connect) and (not M.interface_complete) and (not M.warning_message) then
            AudioMessage("misn1202.wav")
            -- loosing data uplink
            M.warning_repeat_time = GetTime() + 5.0
            M.warning_message = true
        end
        if (M.warning_message) and (Distance(M.user, M.ccacom_tower) > 75.0) and (M.warning_repeat_time < GetTime()) and (M.interface_connect) then
            M.warning_message = false
        end
        if (M.warning_message) and (Distance(M.user, M.ccacom_tower) < 75.0) and (M.interface_connect) then
            M.warning_message = false
        end
        if (M.interface_connect) and (Distance(M.user, M.ccacom_tower) > 85.0) and (not M.interface_complete) then
            AudioMessage("misn1203.wav")
            -- interface broken
            M.interface_connect = false
        end
        if (M.interface_connect) and (M.interface_time < GetTime()) and (not M.interface_complete) then
            AudioMessage("misn1204.wav")
            -- interface complete
            ClearObjectives()
            AddObjective("misn1205.otf", "white")
            M.win_check_time = GetTime() + 120.0
            StopCockpitTimer()
            HideCockpitTimer()
            AudioMessage("misn1223.wav")
            -- get back to nav 1
            M.interface_complete = true
        end
        if (M.interface_complete) and (not M.discovered) then
            if IsAlive(M.patrol1_1) then
                Attack(M.patrol1_1, M.user)
            end
            if IsAlive(M.patrol1_2) then
                Attack(M.patrol1_2, M.user)
            end
            if IsAlive(M.patrol2_1) then
                Attack(M.patrol2_1, M.user)
            end
            if IsAlive(M.patrol2_2) then
                Attack(M.patrol2_2, M.user)
            end
            if IsAlive(M.patrol3_1) then
                Attack(M.patrol3_1, M.user)
            end
            if IsAlive(M.patrol3_2) then
                Attack(M.patrol3_2, M.user)
            end
            if IsAlive(M.patrol4_1) then
                Attack(M.patrol4_1, M.user)
            end
            if IsAlive(M.patrol4_2) then
                Attack(M.patrol4_2, M.user)
            end
            if IsAlive(M.guard_tank1) then
                Attack(M.guard_tank1, M.user)
            end
            if IsAlive(M.guard_tank2) then
                Attack(M.guard_tank2, M.user)
            end
            M.discovered = true
        end
        if (M.interface_connect) and (not M.interface_complete) and (not M.noise) then
            AudioMessage("misn1212.wav")
            M.next_noise_time = GetTime() + 3.0
            M.noise = true
        end
        if (M.interface_connect) and (not M.interface_complete) and (M.noise) and (M.next_noise_time < GetTime()) then
            M.noise = false
        end
        -- this is the Nav camera code
        if M.key_captured then
            if ((IsInfo("sbhqt1") == true) or (IsInfo("sbhqt2") == true)) and ((not M.camera_swap1) or (not M.camera_swap2)) then
                if (Distance(M.user, M.center) < 100.0) then
                    --			if (IsAlive(center_cam))
                    --			{
                    --				RemoveObject(center_cam);
                    --			}
                    if IsAlive(M.start_cam) then
                        SetTeamNum(M.start_cam, 1)
                        --					RemoveObject(start_cam);
                    end
                    if IsAlive(M.check2_cam) then
                        SetTeamNum(M.check2_cam, 1)
                        --					RemoveObject(check2_cam);
                    end
                    if IsAlive(M.check3_cam) then
                        SetTeamNum(M.check3_cam, 1)
                        --					RemoveObject(check3_cam);
                    end
                    if IsAlive(M.check4_cam) then
                        SetTeamNum(M.check4_cam, 1)
                        --					RemoveObject(check4_cam);
                    end
                    if IsAlive(M.goal_cam) then
                        SetTeamNum(M.goal_cam, 1)
                        --					RemoveObject(goal_cam);
                    end
                    --			center_cam = BuildObject ("apcamr", 1, "center_cam");
                    --				start_cam = BuildObject ("apcamr", 1, "start_cam");
                    -- Port safety: validate the object before the native SetName equivalent;
                    -- missing/deleted camera pods are skipped without changing mission flags or timing.
                    if IsValid(M.start_cam) then
                        SetObjectiveName(M.start_cam, "Check Point")
                    end
                    --				check2_cam = BuildObject ("apcamr", 1, "check2_cam");
                    -- Port safety: validate the object before the native SetName equivalent;
                    -- missing/deleted camera pods are skipped without changing mission flags or timing.
                    if IsValid(M.check2_cam) then
                        SetObjectiveName(M.check2_cam, "Check Point")
                    end
                    --				check3_cam = BuildObject ("apcamr", 1, "check3_cam");
                    -- Port safety: validate the object before the native SetName equivalent;
                    -- missing/deleted camera pods are skipped without changing mission flags or timing.
                    if IsValid(M.check3_cam) then
                        SetObjectiveName(M.check3_cam, "Check Point")
                    end
                    --				check4_cam = BuildObject ("apcamr", 1, "check4_cam");
                    -- Port safety: validate the object before the native SetName equivalent;
                    -- missing/deleted camera pods are skipped without changing mission flags or timing.
                    if IsValid(M.check4_cam) then
                        SetObjectiveName(M.check4_cam, "Check Point")
                    end
                    --				goal_cam = BuildObject ("apcamr", 1, "goal_cam");
                    M.swap_check = GetTime() + 1.0
                    M.camera_swap1 = true
                    M.camera_swap_back = false
                end
                if (Distance(M.user, M.checkpoint1) < 100.0) then
                    if IsAlive(M.center_cam) then
                        SetTeamNum(M.center_cam, 1)
                        --					RemoveObject(center_cam);
                    end
                    --			if (IsAlive(start_cam))
                    --			{
                    --				RemoveObject(start_cam);
                    --			}
                    --[==[			if (IsAlive(check2_cam))
				{
					RemoveObject(check2_cam);
				}
				if (IsAlive(check3_cam))
				{
					RemoveObject(check3_cam);
				}
				if (IsAlive(check4_cam))
				{
					RemoveObject(check4_cam);
				}
				if (IsAlive(goal_cam))
				{
					RemoveObject(goal_cam);
				}
	]==]
                    --				center_cam = BuildObject ("apcamr", 1, "center_cam");
                    --			start_cam = BuildObject ("apcamr", 1, "start_cam");
                    --			check2_cam = BuildObject ("apcamr", 1, "check2_cam");
                    --			check3_cam = BuildObject ("apcamr", 1, "check3_cam");
                    --			check4_cam = BuildObject ("apcamr", 1, "check4_cam");
                    --			goal_cam = BuildObject ("apcamr", 1, "goal_cam");
                    M.swap_check = GetTime() + 1.0
                    M.camera_swap2 = true
                    M.camera_swap_back = false
                end
            end
        end
        if ((M.camera_swap1) or (M.camera_swap2)) and (not M.camera_noise) then
            AudioMessage("misn1229.wav")
            M.camera_noise = true
        end
        if (not M.camera_swap_back) and (M.swap_check < GetTime()) and ((M.camera_swap1) or (M.camera_swap2)) then
            M.swap_check = GetTime() + 1.0
            if (M.camera_swap1) and (Distance(M.user, M.center) > 300.0) then
                AudioMessage("misn1230.wav")
                --			if (IsAlive(center_cam))
                --			{
                --				RemoveObject(center_cam);
                --			}
                if IsAlive(M.start_cam) then
                    SetTeamNum(M.start_cam, 3)
                    --				RemoveObject(start_cam);
                end
                if IsAlive(M.check2_cam) then
                    SetTeamNum(M.check2_cam, 3)
                    --				RemoveObject(check2_cam);
                end
                if IsAlive(M.check3_cam) then
                    SetTeamNum(M.check3_cam, 3)
                    --				RemoveObject(check3_cam);
                end
                if IsAlive(M.check4_cam) then
                    SetTeamNum(M.check4_cam, 3)
                    --				RemoveObject(check4_cam);
                end
                if IsAlive(M.goal_cam) then
                    SetTeamNum(M.goal_cam, 3)
                    --				RemoveObject(goal_cam);
                end
                --			center_cam = BuildObject ("apcamr", 3, "center_cam");
                --			start_cam = BuildObject ("apcamr", 3, "start_cam");
                --			check2_cam = BuildObject ("apcamr", 3, "check2_cam");
                --			check3_cam = BuildObject ("apcamr", 3, "check3_cam");
                --			check4_cam = BuildObject ("apcamr", 3, "check4_cam");
                --			goal_cam = BuildObject ("apcamr", 3, "goal_cam");
                M.swap_check = 99999.0
                M.camera_swap1 = false
                M.camera_noise = false
                M.camera_swap_back = true
            end
            if (M.camera_swap2) and (Distance(M.user, M.checkpoint1) > 300.0) then
                AudioMessage("misn1230.wav")
                if IsAlive(M.center_cam) then
                    SetTeamNum(M.center_cam, 3)
                    --				RemoveObject(center_cam);
                end
                --			if (IsAlive(start_cam))
                --			{
                --				RemoveObject(start_cam);
                --			}
                --			if (IsAlive(check2_cam))
                --[==[			{
				RemoveObject(check2_cam);
			}
			if (IsAlive(check3_cam))
			{
				RemoveObject(check3_cam);
			}
			if (IsAlive(check4_cam))
			{
				RemoveObject(check4_cam);
			}
			if (IsAlive(goal_cam))
			{
				RemoveObject(goal_cam);
			}
]==]
                --			center_cam = BuildObject ("apcamr", 3, "center_cam");
                --			start_cam = BuildObject ("apcamr", 3, "start_cam");
                --			check2_cam = BuildObject ("apcamr", 3, "check2_cam");
                --			check3_cam = BuildObject ("apcamr", 3, "check3_cam");
                --			check4_cam = BuildObject ("apcamr", 3, "check4_cam");
                --			goal_cam = BuildObject ("apcamr", 3, "goal_cam");
                M.swap_check = 99999.0
                M.camera_swap2 = false
                M.camera_noise = false
                M.camera_swap_back = true
            end
        end
    end
    --/////////////////// THIS MARKS THE END OF GAME BLOWN //////////////////////////////////////
    -- win condition
    if (M.game_blown) and (not M.game_over) then
        FailMission(GetTime() + 10.0)
        M.game_over = true
    end
    if (M.interface_complete) and (M.win_check_time < GetTime()) then
        M.win_check_time = GetTime() + 5.0
        if (Distance(M.user, M.nav1) < 75.0) and (not M.win) then
            AudioMessage("misn1216.wav")
            SucceedMission(GetTime() + 7.0, "misn12w1.des")
            M.win = true
        end
    end
    if (not M.interface_complete) and (GetCockpitTimer() == 0) and (not M.game_over) then
        AudioMessage("misn1215.wav")
        FailMission(GetTime() + 15.0, "misn12f1.des")
        M.game_over = true
    end
    -- END OF SCRIPT
end

function Save()
    return M
end

function Load(state)
    M = state
end
