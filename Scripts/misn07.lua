-- Faithful stock misn07 port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misn07Mission.cpp.
-- Original disabled C++ remains in long comments at its original locations.
-- Full source, including native serialization, is in References/Misn07Source/.
-- Single-player mission; no EXU/OpenShim or Campaign Reimagined helpers required.
local M

local function NewState()
    local state = {}
    state.test = false
    state.utah_found = false
    state.start_done = false
    state.out_of_car = false
    state.alarm_on = false
    state.start_evac = false
    state.ccaguntower1_down = false
    state.ccaguntower2_down = false
    state.radar_dead = false
    state.player_dead = false
    state.over_wall = false
    state.guntower_attacked = false
    state.fence_off = false
    state.rendezvous = false
    state.recon_message1 = false
    state.recon_message2 = false
    state.build_scouts = false
    state.jump_cam_spawned = false
    state.rookie_moved = false
    state.becon_build = false
    state.free1 = false
    state.free2 = false
    state.p1_retreat = false
    state.p2_retreat = false
    state.p3_retreat = false
    state.p4_retreat = false
    state.retreat_message_done = false
    state.first_objective = false
    state.second_objective = false
    state.turret_move = false
    state.next_mission = false
    state.rookie_lost = false
    state.mine_pathed = false
    state.detected = false
    state.getum = false
    state.patrola1 = false
    state.patrola2 = false
    state.patrolb1 = false
    state.patrolb2 = false
    state.patrolc1 = false
    state.patrolc2 = false
    state.retreat_success = false
    state.detected_message = false
    state.fighter_moved = false
    state.unit_spawn = false
    state.vehicle_stolen = false
    state.trigger1 = false
    state.alarm_special = false
    state.m_on = {}
    for index = 0, 110 do state.m_on[index] = false end
    state.m_dead = {}
    for index = 0, 110 do state.m_dead[index] = false end
    state.alarm_sound = false
    state.rookie_removed = false
    state.forces_enroute = false
    state.test_tank_built = false
    state.camera1_on = false
    state.camera2_on = false
    state.camera3_on = false
    state.camera4_on = false
    state.camera_off = false
    state.camera2_oned = false
    state.camera3_oned = false
    state.camera_ready = false
    state.tank_switch = false
    state.sound_started = false
    state.test_found = false
    state.game_over = false
    state.first_camera_ready = false
    state.first_camera_off = false
    state.cute_camera_ready = false
    state.cute_camera_off = false
    state.radar_camera_off = false
    state.next_camera_on = false
    state.rookie_jumped = false
    state.tower_warning = false
    state.rookie_found = false
    state.opening_vo = false
    state.shot1 = false
    state.shot2 = false
    state.unit_spawn_time = 99999.0
    state.recon_message_time = 99999.0
    state.becon_build_time = 99999.0
    state.rookie_rendezvous_time = 99999.0
    state.getaway_message_time = 99999.0
    state.patrol2_move_time = 99999.0
    state.rookie_move_time = 99999.0
    state.alarm_time = 99999.0
    state.alarm_timer = 99999.0
    state.rendezous_check = 99999.0
    state.alarm_check = 99999.0
    state.rookie_remove_time = 99999.0
    state.runner_check = 99999.0
    state.check_jump_geyser = 99999.0
    state.reach_mine_time = 99999.0
    state.check_range = 99999.0
    state.change_angle = 99999.0
    state.change_angle1 = 99999.0
    state.change_angle2 = 99999.0
    state.change_angle3 = 99999.0
    state.switch_tank = 99999.0
    state.start_sound = 99999.0
    state.recon_message2_time = 99999.0
    state.first_camera_time = 99999.0
    state.radar_camera_time = 99999.0
    state.next_mission_time = 99999.0
    state.cute_camera_time = 99999.0
    state.next_shot_time = 99999.0
    state.tower_check = 99999.0
    state.user = nil
    state.nsdfrecycle = nil
    state.nsdfmuf = nil
    state.rookie = nil
    state.jump_cam = nil
    state.jump_geyz = nil
    state.remove_geyz = nil
    state.mine_geyz = nil
    state.pilot1 = nil
    state.pilot2 = nil
    state.pilot3 = nil
    state.pilot4 = nil
    state.pilot5 = nil
    state.ccaguntower1 = nil
    state.ccaguntower2 = nil
    state.ccacomtower = nil
    state.powrplnt1 = nil
    state.powrplnt2 = nil
    state.parkedtank1 = nil
    state.parkedtank2 = nil
    state.parkedtank3 = nil
    state.parkedtank4 = nil
    state.barrack1 = nil
    state.barrack2 = nil
    state.nav1 = nil
    state.nav2 = nil
    state.nav3 = nil
    state.nav4 = nil
    state.nav5 = nil
    state.nav6 = nil
    state.nav7 = nil
    state.becon1 = nil
    state.becon2 = nil
    state.becon3 = nil
    state.becon4 = nil
    state.wingman1 = nil
    state.wingman2 = nil
    state.wingtank1 = nil
    state.wingtank2 = nil
    state.wingtank3 = nil
    state.wingturret1 = nil
    state.wingturret2 = nil
    state.nsdfarmory = nil
    state.svapc = nil
    state.m = {}
    for index = 0, 110 do state.m[index] = nil end
    state.ccarecycle = nil
    state.ccamuf = nil
    state.ccaslf = nil
    state.basepowrplnt1 = nil
    state.pbaseowrplnt2 = nil
    state.ccabaseguntower1 = nil
    state.ccabaseguntower2 = nil
    state.guard_tank1 = nil
    state.guard_tank2 = nil
    state.guard_tank3 = nil
    state.test_tank = nil
    state.patrol1_1 = nil
    state.patrol1_2 = nil
    state.patrol1_3 = nil
    state.svpatrol1_1 = nil
    state.svpatrol1_2 = nil
    state.svpatrol1_3 = nil
    state.svpatrol2_1 = nil
    state.svpatrol2_2 = nil
    state.svpatrol2_3 = nil
    state.svpatrol3_1 = nil
    state.svpatrol3_2 = nil
    state.svpatrol3_3 = nil
    state.svpatrol4_1 = nil
    state.svpatrol4_2 = nil
    state.guard_turret1 = nil
    state.guard_turret2 = nil
    state.spawn_turret1 = nil
    state.spawn_turret2 = nil
    state.parked1 = nil
    state.parked2 = nil
    state.parked3 = nil
    state.parkturret1 = nil
    state.parkturret2 = nil
    state.spawn_point = nil
    state.fence = nil
    state.test_turret = nil
    state.tank_spawn = nil
    state.power1_geyser = nil
    state.power2_geyser = nil
    state.radar_geyser = nil
    state.camera_geyser = nil
    state.show_geyser = nil
    state.new_tank1 = nil
    state.new_tank2 = nil
    state.turret1_spot = nil
    state.mine = {}
    for index = 0, 110 do state.mine[index] = nil end
    state.count = 0
    state.mine_check = 0
    state.x = 0
    state.units = 0
    state.audmsg = 0
    return state
end
M = NewState()

-- Missing native handles returned an effectively infinite distance. Preserve
-- that behavior rather than interpreting nil as a path/position overload.
local function Distance(from, to)
    if from == nil or from == 0 or not IsValid(from) then return math.huge end
    if to == nil or to == 0 then return math.huge end
    if type(to) ~= "string" and not IsValid(to) then return math.huge end
    return GetDistance(from, to)
end

local function IsOdfBase(h, name)
    return IsValid(h) and (IsOdf(h, name) or IsOdf(h, name .. ".odf"))
end

-- Native helper checked object existence, not IsAlive; keep that distinction.
local function AliveButDamaged(h)
    if h == nil or h == 0 or not IsValid(h) then return false end
    return GetHealth(h) < 0.95
end

function Start()
    M = NewState()
    -- Here's where you set the values at the start.  
    M.mine_check=1
    M.x=6000
    M.units=1
    M.start_done=false
    M.out_of_car=false
    M.alarm_on=false
    M.start_evac=false
    M.ccaguntower1_down=false
    M.ccaguntower2_down=false
    M.radar_dead=false
    M.player_dead=false
    M.over_wall=false
    M.guntower_attacked=false
    M.fence_off=false
    M.unit_spawn=false
    M.recon_message1=false
    M.recon_message2=false
    M.build_scouts=false
    M.jump_cam_spawned=false
    M.rookie_moved=false
    M.rendezvous=false
    M.free1=false
    M.free2=false
    M.becon_build=false
    M.p1_retreat=false
    M.p2_retreat=false
    M.p3_retreat=false
    M.p4_retreat=false
    M.first_objective=false
    M.second_objective=false
    M.retreat_message_done=false
    M.turret_move=false
    M.next_mission=false
    M.rookie_lost=false
    M.mine_pathed=false
    M.getum=false
    M.detected=false
    M.patrola1=false
    M.patrola2=false
    M.patrolb1=false
    M.patrolb2=false
    M.patrolc1=false
    M.patrolc2=false
    M.retreat_success=false
    M.detected_message=false
    M.fighter_moved=false
    M.vehicle_stolen=false
    M.trigger1=false
    M.alarm_special=false
    M.alarm_sound=false
    M.rookie_removed=false
    M.forces_enroute=false
    M.test_tank_built=false
    M.camera_ready=false
    M.camera1_on=false
    M.camera2_on=false
    M.camera3_on=false
    M.camera4_on=false
    M.camera_off=false
    M.camera2_oned=false
    M.camera3_oned=false
    M.tank_switch=false
    M.sound_started=false
    M.test_found=false
    M.game_over=false
    M.first_camera_ready=false
    M.first_camera_off=false
    M.cute_camera_ready=false
    M.cute_camera_off=false
    M.radar_camera_off=false
    M.next_camera_on=false
    M.rookie_jumped=false
    M.tower_warning=false
    M.rookie_found=false
    M.opening_vo=false
    M.test=false
    M.utah_found=false
    M.shot1=false
    M.shot2=false
    for index = 0, 111 - 1 do
        M.count = index
        M.mine[M.count]=nil
        M.m_on[M.count]=false
        M.m_dead[M.count]=false
    end
    M.count = 111
    M.unit_spawn_time=99999.0
    M.recon_message_time=99999.0
    M.becon_build_time=99999.0
    M.rookie_move_time=99999.0
    M.getaway_message_time=99999.0
    M.rookie_rendezvous_time=99999.0
    M.patrol2_move_time=99999.0
    M.alarm_time=99999.0
    M.alarm_timer=99999.0
    M.rendezous_check=99999.0
    M.alarm_check=99999.0
    M.rookie_remove_time=99999.0
    M.runner_check=99999.0
    M.check_jump_geyser=99999.0
    M.reach_mine_time=99999.0
    M.check_range=99999.0
    M.change_angle=99999.0
    M.change_angle1=99999.0
    M.change_angle2=99999.0
    M.change_angle3=99999.0
    M.switch_tank=99999.0
    M.start_sound=99999.0
    M.recon_message2_time=99999.0
    M.first_camera_time=99999.0
    M.cute_camera_time=99999.0
    M.radar_camera_time=99999.0
    M.next_mission_time=99999.0
    M.next_shot_time=99999.0
    M.tower_check=99999.0
    M.turret1_spot=nil
    M.jump_geyz=GetHandle("volcano_geyz1")
    M.remove_geyz=GetHandle("volcano_geyz2")
    M.ccaguntower1=GetHandle("sgtower1")
    M.ccaguntower2=GetHandle("sgtower2")
    M.ccacomtower=GetHandle("radar_array")
    M.powrplnt1=GetHandle("power1")
    --	powrplnt2 = GetHandle ("power2");
    M.barrack1=GetHandle("hut1")
    M.barrack2=GetHandle("hut2")
    M.nav1=nil
    M.nav2=nil
    M.nav3=GetHandle("cam3")
    M.wingman1=GetHandle("avfigh1")
    M.wingman2=0
    M.wingtank1=GetHandle("avtank1")
    M.wingtank2=GetHandle("avtank2")
    M.wingtank3=GetHandle("avtank3")
    M.wingturret1=GetHandle("avturret1")
    M.wingturret2=GetHandle("avturret2")
    M.nsdfarmory=GetHandle("avslf")
    M.ccarecycle=GetHandle("svrecycler")
    M.ccamuf=GetHandle("svmuf")
    M.basepowrplnt1=GetHandle("svbasepower1")
    M.pbaseowrplnt2=GetHandle("svbasepower2")
    --	ccabaseguntower1 = GetHandle ("svbasetower1");
    --	ccabaseguntower2 = GetHandle ("svbasetower2");
    --	guard_tank1 = GetHandle ("svtank1");
    --	guard_tank2 = GetHandle ("svtank2");
    M.patrol1_1=GetHandle("svfigh1")
    M.patrol1_2=GetHandle("svfigh2")
    M.svpatrol1_1=GetHandle("svpatrol1_1")
    M.svpatrol1_2=GetHandle("svpatrol1_2")
    M.svpatrol2_1=GetHandle("svpatrol2_1")
    M.svpatrol2_2=GetHandle("svpatrol2_2")
    M.svpatrol3_1=GetHandle("svpatrol3_1")
    M.svpatrol3_2=GetHandle("svpatrol3_2")
    M.svpatrol4_1=GetHandle("svpatrol4_1")
    M.svpatrol4_2=GetHandle("svpatrol4_2")
    --	test_tank = GetHandle ("test_tank");
    M.guard_turret1=GetHandle("svturret1")
    M.guard_turret2=GetHandle("svturret2")
    M.parked1=GetHandle("parked1")
    M.parked2=GetHandle("parked2")
    M.parked3=GetHandle("parked3")
    M.parkturret1=GetHandle("pturret1")
    M.parkturret2=GetHandle("pturret2")
    M.svapc=GetHandle("parked_svapc")
    M.spawn_point=GetHandle("recycle_spawn_geyz")
    --	test_turret = GetHandle ("test_turret");
    --	mine_geyz = GetHandle("");
    --	tank_spawn = GetHandle ("test_tank_spawn");
    M.radar_geyser=GetHandle("radar_geyser")
    M.camera_geyser=GetHandle("camera_geyser")
    M.show_geyser=GetHandle("show_geyser")
    M.nsdfrecycle=nil
    M.nsdfmuf=nil
    M.jump_cam=nil
    M.rookie=nil
    M.nav4=nil
    M.nav5=nil
    M.nav6=nil
    M.nav7=nil
    M.audmsg=nil
    M.pilot1=nil
    M.pilot2=nil
    M.pilot3=nil
    M.pilot4=nil
    M.pilot5=nil
    M.spawn_turret1=nil
    M.spawn_turret2=nil
    M.becon1=nil
    M.becon2=nil
    M.becon3=nil
    M.becon4=nil
    M.new_tank1=nil
    M.new_tank2=nil
end

function AddObject(h)
    -- Empty in the source.
end

function Update(dt)
    -- START OF SCRIPT
    -- Here is where you put what happens  every frame.  
    M.user=GetPlayerHandle()
    --assigns the player a handle every frame
    M.mine_check=M.mine_check+10
    if M.mine_check>110 then
        M.mine_check=1
    --[==[/*	if (!first_camera_ready)
	{
		CameraReady();
		audmsg = AudioMessage("misn0700.wav"); // General "mission breifing"
		first_camera_time = Get_Time() + 10.0f;
		first_camera_ready = true;
	}

	if ((first_camera_ready) && (!first_camera_off))
	{
		CameraPath("start_camera", x, 950, user);
		x = x - 100;
	}

	if ((first_camera_ready) && (!first_camera_off) && ((CameraCancelled()) || (first_camera_time < Get_Time())))
	{
		CameraFinish();
		first_camera_off = true;
	}

	if (CameraCancelled())
	{
		StopAudioMessage(audmsg);
	}
*/]==]
    end
    if not M.start_done then
        if M.nav3~=nil then
            SetObjectiveName(M.nav3,"Rendezvous Point")
        end
        SetScrap(1,10)
        SetObjectiveOff(M.ccacomtower)
        Patrol(M.patrol1_1,"patrol_path3")
        --
        Patrol(M.patrol1_2,"patrol_path3")
        --
        --		Patrol(guard_tank1, "guard_path");	//
        --		Patrol(guard_tank2, "guard_path");	// sets enemy units to their patrol routes
        Patrol(M.svpatrol3_1,"patrol_path1")
        --
        Patrol(M.svpatrol3_2,"patrol_path1")
        --
        Patrol(M.svpatrol4_1,"patrol_path2")
        --
        Patrol(M.svpatrol4_2,"patrol_path2")
        --
        SetIndependence(M.wingtank2,0)
        Stop(M.wingtank2)
        SetPerceivedTeam(M.wingtank2,1)
        SetIndependence(M.wingtank3,0)
        Stop(M.wingtank3)
        SetPerceivedTeam(M.wingtank3,1)
        Stop(M.svpatrol2_1,1)
        Stop(M.svpatrol2_2,1)
        M.rendezous_check=GetTime()+9.0
        M.patrol2_move_time=GetTime()+121.0
        M.alarm_check=GetTime()+27.0
        M.turret1_spot="turret1_spot"
        for index = 0, 111 - 1 do
            M.count = index
            local name
            name = string.format("m%03d", M.count)
            M.mine[M.count]=name
        end
        M.count = 111
        M.start_done=true
    --	if (CameraCancelled())
    --	{
    --		StopAudioMessage(audmsg);
    --	}
    end
    if (not M.opening_vo) and (M.start_done) and (M.rendezous_check<GetTime()) then
        M.rendezous_check=GetTime()+15.0
        AudioMessage("misn0700.wav")
        -- General "mission breifing"
        ClearObjectives()
        AddObjective("misn0700.otf","white")
        M.opening_vo=true
    end
    if (M.start_done) and (M.patrol2_move_time<GetTime() and (not M.rendezvous)) and (IsAlive(M.svpatrol2_1)) and (IsAlive(M.svpatrol2_2)) and (not M.fighter_moved) then
        --		&& (GameObjectHandle::GetObj(svpatrol2_1)->GetHealth()<0.98f) // (GameObjectHandle::GetObj(svpatrol2_1)->GetLastEnemyShot()<0)
        --		&& (GameObjectHandle::GetObj(svpatrol2_2)->GetHealth()<0.98f)) //(GameObjectHandle::GetObj(svpatrol2_2)->GetLastEnemyShot()<0)) 
        Patrol(M.svpatrol2_1,"patrol_path1")
        -- sets enemy units to their patrol routes 
        Patrol(M.svpatrol2_2,"patrol_path1")
        -- sets enemy units to their patrol routes
        M.fighter_moved=true
    -- this is when the player rendezvous with the other tanks 
    end
    if not M.first_objective then
        if (M.rendezous_check<GetTime()) and (not M.rendezvous) and (not M.alarm_on) then
            M.rendezous_check=GetTime()+3.0
            if (IsAlive(M.wingtank2)) and (Distance(M.user,M.wingtank2)<150.0) and (not M.rendezvous) or ((IsAlive(M.wingtank3)) and (Distance(M.user,M.wingtank3)<150.0) and (not M.rendezvous)) then
                M.audmsg=AudioMessage("misn0701.wav")
                -- greetings comander "standby"
                if IsAlive(M.wingtank2) then
                    M.new_tank1=BuildObject("avtank",1,M.wingtank2)
                    RemoveObject(M.wingtank2)
                end
                if IsAlive(M.wingtank3) then
                    M.new_tank2=BuildObject("avtank",1,M.wingtank3)
                    RemoveObject(M.wingtank3)
                end
                ClearObjectives()
                AddObjective("misn0700.otf","green")
                AddObjective("misn0701.otf","white")
                M.recon_message_time=GetTime()+240.0
                M.runner_check=GetTime()+6.0
                M.patrol2_move_time=GetTime()+60.0
                M.nav1=BuildObject("apcamr",1,"cam1_spawn")
                --outpost cam
                if M.nav1~=nil then
                    SetObjectiveName(M.nav1,"CCA Outpost")
                end
                M.tower_check=GetTime()+10.0
                M.rendezvous=true
            end
        end
        if (M.rendezvous) and (M.patrol2_move_time<GetTime()) and (not M.fighter_moved) then
            if M.svpatrol2_1~=nil then
                Attack(M.svpatrol2_1,M.user)
            end
            if M.svpatrol2_2~=nil then
                Attack(M.svpatrol2_2,M.user)
            end
            M.fighter_moved=true
        --[==[/*	if ((rendezvous) && (IsAlive (wingtank3)) && (!free1))				
	{																		
		Stop(wingtank3, 0);												
		free1 = true;														
	}																			
																							
	if ((rendezvous) && (IsAlive (wingtank2)) && (!free2))									
	{																					
		Stop(wingtank2, 0);															
		free2 = true;																		
	}
*/]==]
        end
        if (IsAlive(M.nav1)) and (M.tower_check<GetTime()) and (not M.tower_warning) then
            M.tower_check=GetTime()+4.0
            if Distance(M.user,M.nav1)<90.0 then
                AudioMessage("misn0716.wav")
                M.tower_warning=true
            end
        end
    -- this is when the rookie tells the player about the overlook into the base and lays down a camera
    --////////////////////////////ROOKIE SCRIPT 1 HE JUMPS IN FRONT OF PLAYER ////////////////////////////	
    --[==[/*																										
if ((!first_objective) && (!alarm_on) && (!out_of_car))
{
	if ((rendezvous) && (!jump_cam_spawned) && (recon_message_time < Get_Time()))
	{
		recon_message_time = Get_Time() + 20.0f;

	    if ((GetDistance(user, jump_geyz) > 400.0f) && (GetDistance(user, ccacomtower) > 150.0f))
		{																											
//			AudioMessage("misn0702.wav"); // Rookie "I found an overlook"										
			AudioMessage("win.wav"); // Rookie trasmits a broken message saying he's found a way in and screams YAAAAAAAHHHHHHOOOOOO!
			jump_cam = BuildObject ("apcamr", 1, "jump_cam_spawn"); //Rookie drops camera			
			rookie = BuildObject ("avfigh", 1, jump_geyz);// spawn in rookie										
			Goto (rookie, jump_cam);//rookie goes to jump-cam to get in picture
			rookie_move_time = Get_Time() + 20.0f; // sets time to move rookie to secret spot
			recon_message2_time = Get_Time() + 480.0f;
			jump_cam_spawned = true;																				
		}																											
	}																																																						//
	
	if ((jump_cam_spawned) && (jump_cam!=NULL))
	{
		GameObjectHandle::GetObj(jump_cam)->SetName("Volcano Peak");
	}
	
	if ((jump_cam_spawned) && (rookie_move_time < Get_Time()) && (!rookie_moved))								
	{																											
		Defend(rookie, 1); 
		rookie_remove_time = Get_Time() + 15.0f;
		rookie_moved = true;																					
	}																							
	
	if ((rookie_moved) && (rookie_remove_time < Get_Time()) && (!rookie_removed))
	{
		rookie_remove_time = Get_Time() + 5.0f;

		if (IsAlive(rookie))
		{
			Defend(rookie, 1);

			if (GetDistance(user, rookie) < 70.0f)
			{
				audmsg = AudioMessage("win.wav");
				rookie_removed = true;
			}
		}
	}

	if ((rookie_removed) && (IsAudioMessageDone(audmsg)) && (!rookie_jumped))
	{
		Damage(rookie, 5000);
		rookie_jumped = true;
	}

//	if ((rookie_moved) && (rookie_remove_time < Get_Time()) && (!rookie_removed)) // rookie reaches secret spot
//	{																								
//		RemoveObject(rookie);// I take rookie away so that he is safe
//		rookie_removed = true;
//	}
}
*/]==]
    --////////////////////////////ROOKIE SCRIPT 2 HE JUMPS ON CAMERA ////////////////////////////
    end
    if (not M.first_objective) and (not M.alarm_on) and (not M.out_of_car) then
        if (M.rendezvous) and (not M.jump_cam_spawned) and ((M.recon_message_time<GetTime()) or (M.tower_warning)) then
            M.recon_message_time=GetTime()+5.0
            M.units=CountUnitsNearObject(M.user,200.0,2,"svfigh")
            if (Distance(M.user,M.jump_geyz)>400.0) and (M.units==0) then
                AudioMessage("misn0702.wav")
                -- Rookie trasmits a broken message saying player should look at camera
                M.jump_cam=BuildObject("apcamr",1,"jump_cam_spawn")
                M.rookie=BuildObject("avfigh",1,M.jump_geyz)
                Follow(M.rookie,M.jump_geyz)
                M.rookie_move_time=GetTime()+10.0
                --			recon_message2_time = Get_Time() + 480.0f;
                M.jump_cam_spawned=true
            end
        end
        if (M.jump_cam_spawned) and (M.jump_cam~=nil) then
            SetObjectiveName(M.jump_cam,"Volcano Peak")
        end
        if (M.jump_cam_spawned) and (M.rookie_move_time<GetTime()) and (not M.rookie_moved) then
            --		if (IsAlive(rookie))
            --		{
            --			Defend(rookie, 1);
            --		}
            M.rookie_remove_time=GetTime()+10.0
            M.rookie_moved=true
        end
        if (M.rookie_moved) and (M.rookie_remove_time<GetTime()) and (not M.rookie_found) then
            M.rookie_remove_time=GetTime()+3.0
            if IsAlive(M.rookie) then
                --			Defend(rookie);
                if Distance(M.user,M.rookie)<70.0 then
                    Defend(M.rookie,1)
                    AudioMessage("misn0718.wav")
                    -- rookie sends broken message he's found a way inside base
                    M.rookie_remove_time=GetTime()+10.0
                    M.rookie_found=true
                end
            end
        end
        if (M.rookie_found) and (M.rookie_remove_time<GetTime()) and (not M.rookie_removed) then
            if IsAlive(M.rookie) then
                AudioMessage("misn0715.wav")
                -- screams YAAAAAAAHHHHHHOOOOOO!
                EjectPilot(M.rookie)
                M.rookie_removed=true
            end
        end
    -- end rookie at overlook - he heads off to mine field //////////////////////////////////
    -- this is when the player tries to go into the radar array base w/out jumping in (in his tank) 
    end
    if (M.alarm_check<GetTime()) and (not M.alarm_on) then
        M.alarm_check=GetTime()+5.0
        --[==[/*		if ((!alarm_on) && (!out_of_car) && (GetDistance(user, turret1_spot) < 90.0f))// this is if the player attacks the gun towers around the solar array
		{
			AudioMessage("misn0710.wav");// you've tripped the alarm
			SetObjectiveOn(ccacomtower);
			SetObjectiveName(ccacomtower, "Radar Array");
			alarm_on = true;
		}
*/]==]
        if (not M.alarm_on) and (not M.out_of_car) and (Distance(M.user,M.turret1_spot)<70.0) then
            -- this is if the player attacks the gun towers around the solar array
            AudioMessage("misn0710.wav")
            -- you've tripped the alarm
            SetObjectiveOn(M.ccacomtower)
            SetObjectiveName(M.ccacomtower,"Radar Array")
            M.alarm_on=true
        end
    -- end of player trying to enter radar base in tank 
    -- now that the alarm is on the task will be more difficult
    end
    if not M.first_objective then
        if M.alarm_on then
            -- this code makes the alarm sound
            if (M.ccacomtower~=nil) and (Distance(M.user,M.ccacomtower)<170.0) and (not M.alarm_sound) then
                AudioMessage("misn0708.wav")
                -- this is the alarm sound		
                M.alarm_timer=GetTime()+6.0
                M.alarm_sound=true
            end
            if (M.alarm_sound) and (M.alarm_timer<GetTime()) then
                M.alarm_sound=false
            end
            if not M.turret_move then
                SetObjectiveOn(M.ccacomtower)
                SetObjectiveName(M.ccacomtower,"Radar Array")
                Retreat(M.guard_turret1,M.ccacomtower,1)
                Retreat(M.guard_turret2,M.ccacomtower,1)
                M.turret_move=true
            end
            if not M.start_evac then
                --starts clock to spawn cca soldiers
                M.unit_spawn_time=GetTime()+20.0
                M.start_evac=true
            end
            if (M.start_evac) and (M.unit_spawn_time<GetTime()) and (not M.unit_spawn) and (not M.alarm_special) then
                -- spawns cca soldiers and tells them to go to their tanks
                M.pilot1=BuildObject("sspilo",2,"hut2_spawn")
                M.pilot2=BuildObject("sspilo",2,"hut2_spawn")
                M.pilot3=BuildObject("sspilo",2,"hut2_spawn")
                M.pilot4=BuildObject("sspilo",2,"hut1_spawn")
                M.pilot5=BuildObject("sspilo",2,"hut1_spawn")
                if M.parkturret1~=M.user then
                    M.spawn_turret1=BuildObject("svturr",2,M.parkturret1)
                    Defend(M.spawn_turret1)
                    RemoveObject(M.parkturret1)
                end
                if M.parkturret2~=M.user then
                    M.spawn_turret2=BuildObject("svturr",2,M.parkturret2)
                    Defend(M.spawn_turret2)
                    RemoveObject(M.parkturret2)
                -- these lines tell the soviet pilots to get to their ships
                end
                if M.parked1~=nil then
                    Retreat(M.pilot1,M.parked1,1)
                end
                if M.parked2~=nil then
                    Retreat(M.pilot2,M.parked2,1)
                end
                if M.parked3~=nil then
                    Retreat(M.pilot3,M.parked3,1)
                end
                M.unit_spawn=true
            -- this is what happens when the player is in the base and sets off the alarm while out of a vehcile
            end
            if (M.start_evac) and (M.alarm_special) and (M.unit_spawn_time<GetTime()) and (not M.unit_spawn) then
                -- spawns cca soldiers and tells them to go to their tanks
                M.pilot1=BuildObject("sspilo",2,"hut2_spawn")
                M.pilot2=BuildObject("sspilo",2,"hut2_spawn")
                M.pilot3=BuildObject("sssold",2,"hut2_spawn")
                M.pilot4=BuildObject("sspilo",2,"hut1_spawn")
                M.pilot5=BuildObject("sssold",2,"hut1_spawn")
                Attack(M.pilot3,M.user)
                Attack(M.pilot5,M.user)
                -- these lines tell the soviet pilots to get to their ships
                if M.parked1~=nil then
                    Retreat(M.pilot1,M.parked1,1)
                end
                if M.parked2~=nil then
                    Retreat(M.pilot2,M.parked2,1)
                end
                if M.parked3~=nil then
                    Retreat(M.pilot4,M.parkturret1,1)
                end
                M.unit_spawn=true
            -- this is an attempt to find out if a pilot has gotten to his ship and then give them orders
            end
            if (M.unit_spawn) and (not M.alarm_special) then
                if (not IsAlive(M.pilot1)) and (M.parked1~=nil) then
                    Attack(M.parked1,M.user)
                end
                if (not IsAlive(M.pilot2)) and (M.parked2~=nil) then
                    Attack(M.parked2,M.user)
                end
                if (not IsAlive(M.pilot3)) and (M.parked3~=nil) then
                    Attack(M.parked3,M.user)
                --[==[/*			if ((!IsAlive(pilot4)) && (parkturret1!=NULL))
			{
				Retreat(parkturret1, turret1_spot);		
			}
			if ((!IsAlive(pilot5)) && (parkturret2!=NULL))
			{
				Retreat(parkturret2, "turret2_spot");
			}
*/]==]
                end
            end
            if (M.unit_spawn) and (M.alarm_special) then
                if (not IsAlive(M.pilot1)) and (M.parked1~=nil) then
                    Goto(M.parked1,M.ccacomtower)
                end
                if (not IsAlive(M.pilot2)) and (M.parked2~=nil) then
                    Goto(M.parked2,M.ccacomtower)
                end
                if (not IsAlive(M.pilot4)) and (M.parkturret1~=nil) then
                    Retreat(M.parkturret1,"turret1_spot")
                end
            --		if (((!alarm_special) && (!IsAlive(ccaguntower1)) && (!forces_enroute)) || 
            --			((!alarm_special) && (!IsAlive(ccaguntower2)) && (!forces_enroute)))
            end
            if (IsAlive(M.ccacomtower)) and (GetHealth(M.ccacomtower)<0.50) and (not M.forces_enroute) then
                --			if (IsAlive(svpatrol1_1))
                --			{
                --				Goto(svpatrol1_1, ccacomtower, 1);
                --			}
                if IsAlive(M.svpatrol1_2) then
                    Goto(M.svpatrol1_2,M.ccacomtower,1)
                --			if (IsAlive(svpatrol2_1))
                --			{
                --				Goto(svpatrol2_1, ccacomtower, 1);
                --			}
                --			if (IsAlive(svpatrol2_2))
                --			{
                --				Goto(svpatrol2_2, ccacomtower, 1);
                --			}
                end
                if IsAlive(M.svpatrol3_1) then
                    Goto(M.svpatrol3_1,M.ccacomtower,1)
                --			if (IsAlive(svpatrol3_2))
                --			{
                --				Goto(svpatrol3_2, ccacomtower, 1);
                --			}
                end
                if IsAlive(M.svpatrol4_1) then
                    Goto(M.svpatrol4_1,M.ccacomtower,1)
                --			if (IsAlive(svpatrol4_2))
                --			{
                --				Goto(svpatrol4_2, ccacomtower, 1);
                --			}
                end
                M.forces_enroute=true
            end
        end
    -- this is what happens when the player parachutes into the base
    end
    if not M.first_objective then
        if (not M.alarm_on) and (not M.out_of_car) and (Distance(M.user,M.camera_geyser)<160.0) then
            -- this indicates that the player has parachuted into the solar array
            SetObjectiveOn(M.ccacomtower)
            SetObjectiveName(M.ccacomtower,"Radar Array")
            --		cute_camera_time = Get_Time() + 5.0f;
            M.out_of_car=true
        --[==[/*	// this will start the camera on the player
	if ((out_of_car) && (!cute_camera_ready) && (cute_camera_time < Get_Time()))
	{
		CameraReady();
		cute_camera_time = Get_Time() + 5.0f;
		cute_camera_ready = true;
	}

	if ((cute_camera_ready) && (!cute_camera_off))
	{
		CameraObject(user, 800, 800, 10, user);	
	}

	if ((cute_camera_ready) && (!cute_camera_off))
	{
		if (cute_camera_time < Get_Time())
		{
			CameraFinish();
			cute_camera_off = true;
		}
	}
*/]==]
        -- this indicates when the player has taken over a vehicle
        end
        if ((M.out_of_car) and (IsOdfBase(M.user,"svtank"))) or ((M.out_of_car) and (IsOdfBase(M.user,"svfigh"))) or ((M.out_of_car) and (IsOdfBase(M.user,"svturr"))) and (not M.vehicle_stolen) then
            --		alarm_time = Get_Time() + 20.0f;
            M.vehicle_stolen=true
        -- this simply means that if the player fires on anything while in the base he will set off an alarm
        end
        if not M.trigger1 and M.out_of_car then
            if AliveButDamaged(M.ccaguntower1) or AliveButDamaged(M.ccaguntower2) or AliveButDamaged(M.ccacomtower) or AliveButDamaged(M.powrplnt1) or AliveButDamaged(M.barrack1) or AliveButDamaged(M.barrack2) or AliveButDamaged(M.parked1) or AliveButDamaged(M.parked2) or AliveButDamaged(M.parked3) or AliveButDamaged(M.parkturret1) or AliveButDamaged(M.parkturret2) then
            --[==[// AliveButDamaged(powrplnt2) ||]==]
                M.trigger1=true
            end
        end
        if (M.trigger1) and (M.vehicle_stolen) and (not M.alarm_on) then
            M.alarm_on=true
        end
        if (M.trigger1) and (not M.vehicle_stolen) and (not M.alarm_on) then
            M.alarm_on=true
            M.alarm_special=true
        end
    -- end parachute into base
    -- the following code triggers the solar array alarm if the player orders ANY of his units to attack the gun towers protecting it
    end
    if not M.first_objective then
        if (not M.alarm_on) and (not M.out_of_car) and (Distance(M.wingman1,M.turret1_spot)<100.0) then
            AudioMessage("misn0709.wav")
            --I've tripped the alarm sir
            M.alarm_on=true
        end
        if (not M.alarm_on) and (not M.out_of_car) and (Distance(M.wingman2,M.turret1_spot)<100.0) then
            AudioMessage("misn0709.wav")
            --I've tripped the alarm sir
            M.alarm_on=true
        end
        if (not M.alarm_on) and (not M.out_of_car) and (Distance(M.wingtank1,M.turret1_spot)<100.0) then
            AudioMessage("misn0709.wav")
            --I've tripped the alarm sir
            M.alarm_on=true
        end
        if (not M.alarm_on) and (not M.out_of_car) and (Distance(M.new_tank1,M.turret1_spot)<100.0) then
            AudioMessage("misn0709.wav")
            --I've tripped the alarm sir
            M.alarm_on=true
        end
        if (not M.alarm_on) and (not M.out_of_car) and (Distance(M.new_tank2,M.turret1_spot)<100.0) then
            AudioMessage("misn0709.wav")
            --I've tripped the alarm sir
            M.alarm_on=true
        --[==[/*		if ((!alarm_on) && (!out_of_car) && (GetDistance(wingturret1, turret1_spot) < 100.0f))
		{
			AudioMessage("misn0709.wav"); //I've tripped the alarm sir
			alarm_on = true;
		}

		if ((!alarm_on) && (!out_of_car) && (GetDistance(wingturret2, turret1_spot) < 100.0f))
		{
			AudioMessage("misn0709.wav"); //I've tripped the alarm sir
			alarm_on = true;
		}

*/]==]
        end
    -- end of alarm trigger for other vehicles //////////////////////////////////////////////////////////
    -- this is an attempt to make the soviets retreat ///////////////////////////////////////////////////
    end
    if not M.first_objective then
        if not M.retreat_success then
            if IsAlive(M.svpatrol1_2) then
                if (not IsAlive(M.svpatrol1_1)) and (M.rendezvous) and (IsAlive(M.ccarecycle)) and (not M.first_objective) and (not M.mine_pathed) and (not M.alarm_on) and (Distance(M.user,M.svpatrol1_2)<50.0) and (not M.p1_retreat) and (not M.p2_retreat) and (not M.p3_retreat) then
                    Retreat(M.svpatrol1_2,M.ccarecycle)
                    SetObjectiveOn(M.svpatrol1_2)
                    SetObjectiveName(M.svpatrol1_2,"Runner")
                    M.getaway_message_time=GetTime()+3.0
                    M.p1_retreat=true
                end
            end
            if IsAlive(M.svpatrol1_1) then
                if (not IsAlive(M.svpatrol1_2)) and (M.rendezvous) and (IsAlive(M.ccarecycle)) and (not M.first_objective) and (not M.mine_pathed) and (not M.alarm_on) and (Distance(M.user,M.svpatrol1_1)<50.0) and (not M.p1_retreat) and (not M.p2_retreat) and (not M.p3_retreat) then
                    Retreat(M.svpatrol1_1,M.ccarecycle)
                    SetObjectiveOn(M.svpatrol1_1)
                    SetObjectiveName(M.svpatrol1_1,"Runner")
                    M.getaway_message_time=GetTime()+3.0
                    M.p1_retreat=true
                end
            --[==[/*		if ((!IsAlive (svpatrol2_1)) && (rendezvous) && (IsAlive(ccarecycle)) && (!first_objective) 
			&& (!mine_pathed) && (!alarm_on) && (GetDistance(user,svpatrol2_2) < 50.0f)  && (!p2_retreat)
			&& (!p1_retreat) && (!p3_retreat))
		{
			Retreat(svpatrol2_2, ccarecycle);
			SetObjectiveOn(svpatrol2_2);
			SetObjectiveName(svpatrol2_2, "Runner");
			getaway_message_time = Get_Time() + 3.0f;
			p2_retreat = true;
		}

		if ((!IsAlive (svpatrol2_2)) && (rendezvous) && (IsAlive(ccarecycle)) && (!first_objective) 
			&& (!mine_pathed) && (!alarm_on) && (GetDistance(user,svpatrol2_1) < 50.0f)  && (!p2_retreat)
			&& (!p1_retreat) && (!p3_retreat))
		{
			Retreat(svpatrol2_1, ccarecycle);
			SetObjectiveOn(svpatrol2_1);
			SetObjectiveName(svpatrol2_1, "Runner");
			getaway_message_time = Get_Time() + 3.0f;
			p2_retreat = true;
		}
*/]==]
            end
            if IsAlive(M.svpatrol3_2) then
                if (not IsAlive(M.svpatrol3_1)) and (M.rendezvous) and (IsAlive(M.ccarecycle)) and (not M.first_objective) and (not M.mine_pathed) and (not M.alarm_on) and (Distance(M.user,M.svpatrol3_2)<50.0) and (not M.p2_retreat) and (not M.p1_retreat) and (not M.p3_retreat) then
                    Retreat(M.svpatrol3_2,M.ccarecycle)
                    SetObjectiveOn(M.svpatrol3_2)
                    SetObjectiveName(M.svpatrol3_2,"Runner")
                    M.getaway_message_time=GetTime()+3.0
                    M.p3_retreat=true
                end
            end
            if IsAlive(M.svpatrol3_1) then
                if (not IsAlive(M.svpatrol3_2)) and (M.rendezvous) and (IsAlive(M.ccarecycle)) and (not M.first_objective) and (not M.mine_pathed) and (not M.alarm_on) and (Distance(M.user,M.svpatrol3_1)<50.0) and (not M.p2_retreat) and (not M.p1_retreat) and (not M.p3_retreat) then
                    Retreat(M.svpatrol3_1,M.ccarecycle)
                    SetObjectiveOn(M.svpatrol3_1)
                    SetObjectiveName(M.svpatrol3_1,"Runner")
                    M.getaway_message_time=GetTime()+3.0
                    M.p3_retreat=true
                end
            -- this is the player being warned when one is getting away.
            end
            if (not M.retreat_success) and (not M.getum) then
                if ((M.p1_retreat) and (M.getaway_message_time<GetTime()) and (IsAlive(M.new_tank1)) and (not M.getum)) or ((M.p1_retreat) and (M.getaway_message_time<GetTime()) and (IsAlive(M.new_tank2)) and (not M.getum)) then
                    AudioMessage("misn0705.wav")
                    -- one of'ms making a break for it!
                    M.getum=true
                end
                if ((M.p2_retreat) and (M.getaway_message_time<GetTime()) and (IsAlive(M.new_tank1)) and (not M.getum)) or ((M.p2_retreat) and (M.getaway_message_time<GetTime()) and (IsAlive(M.new_tank2)) and (not M.getum)) then
                    AudioMessage("misn0705.wav")
                    -- one of'ms making a break for it!
                    M.getum=true
                end
                if ((M.p3_retreat) and (M.getaway_message_time<GetTime()) and (IsAlive(M.new_tank1)) and (not M.getum)) or ((M.p3_retreat) and (M.getaway_message_time<GetTime()) and (IsAlive(M.new_tank2)) and (not M.getum)) then
                    AudioMessage("misn0705.wav")
                    -- one of'ms making a break for it!
                    M.getum=true
                end
            -- this is to set up the "that's gotum" message
            end
            if (M.p1_retreat) and (IsAlive(M.svpatrol1_1)) then
                M.patrola1=true
            end
            if (M.p1_retreat) and (IsAlive(M.svpatrol1_2)) then
                M.patrola2=true
            end
            if (M.p2_retreat) and (IsAlive(M.svpatrol2_1)) then
                M.patrolb1=true
            end
            if (M.p2_retreat) and (IsAlive(M.svpatrol2_2)) then
                M.patrolb2=true
            end
            if (M.p3_retreat) and (IsAlive(M.svpatrol3_1)) then
                M.patrolc1=true
            end
            if (M.p3_retreat) and (IsAlive(M.svpatrol3_2)) then
                M.patrolc2=true
            end
            if ((M.p1_retreat) and (M.patrola1) and (not IsAlive(M.svpatrol1_1)) and (IsAlive(M.new_tank1))) or ((M.p1_retreat) and (M.patrola1) and (not IsAlive(M.svpatrol1_1)) and (IsAlive(M.new_tank2))) then
                AudioMessage("misn0706.wav")
                -- that got'um!
                --			SetObjectiveOff(svpatrol1_1);
                M.p1_retreat=false
                M.patrola1=false
                M.getum=false
            end
            if ((M.p1_retreat) and (M.patrola2) and (not IsAlive(M.svpatrol1_2)) and (IsAlive(M.new_tank1))) or ((M.p1_retreat) and (M.patrola2) and (not IsAlive(M.svpatrol1_2)) and (IsAlive(M.new_tank2))) then
                AudioMessage("misn0706.wav")
                -- that got'um!
                --			SetObjectiveOff(svpatrol1_2);
                M.p1_retreat=false
                M.patrola2=false
                M.getum=false
            end
            if ((M.p2_retreat) and (M.patrolb1) and (not IsAlive(M.svpatrol2_1)) and (IsAlive(M.new_tank1))) or ((M.p2_retreat) and (M.patrolb1) and (not IsAlive(M.svpatrol2_1)) and (IsAlive(M.new_tank2))) then
                AudioMessage("misn0706.wav")
                -- that got'um!
                --			SetObjectiveOff(svpatrol2_1);
                M.p2_retreat=false
                M.patrolb1=false
                M.getum=false
            end
            if ((M.p2_retreat) and (M.patrolb2) and (not IsAlive(M.svpatrol2_2)) and (IsAlive(M.new_tank1))) or ((M.p2_retreat) and (M.patrolb2) and (not IsAlive(M.svpatrol2_2)) and (IsAlive(M.new_tank2))) then
                AudioMessage("misn0706.wav")
                -- that got'um!
                --			SetObjectiveOff(svpatrol2_2);
                M.p2_retreat=false
                M.patrolb2=false
                M.getum=false
            end
            if ((M.p3_retreat) and (M.patrolc1) and (not IsAlive(M.svpatrol3_1)) and (IsAlive(M.new_tank1))) or ((M.p3_retreat) and (M.patrolc1) and (not IsAlive(M.svpatrol3_1)) and (IsAlive(M.new_tank2))) then
                AudioMessage("misn0706.wav")
                -- that got'um!
                --			SetObjectiveOff(svpatrol3_1);
                M.p3_retreat=false
                M.patrolc1=false
                M.getum=false
            end
            if ((M.p3_retreat) and (M.patrolc2) and (not IsAlive(M.svpatrol3_2)) and (IsAlive(M.new_tank1))) or ((M.p3_retreat) and (M.patrolc2) and (not IsAlive(M.svpatrol3_2)) and (IsAlive(M.new_tank2))) then
                AudioMessage("misn0706.wav")
                -- that got'um!
                --			SetObjectiveOff(svpatrol3_2);
                M.p3_retreat=false
                M.patrolc2=false
                M.getum=false
            end
        -- this is what happens if an enemy unit gets away - tanks will come out
        end
        if (M.patrola1) and (not M.retreat_success) and (not M.alarm_on) and (Distance(M.svpatrol1_1,M.ccarecycle)<100.0) and (M.ccarecycle~=nil) and (IsAlive(M.ccarecycle)) then
            SetObjectiveOff(M.svpatrol1_1)
            M.retreat_success=true
        end
        if (M.patrola2) and (not M.retreat_success) and (not M.alarm_on) and (Distance(M.svpatrol1_2,M.ccarecycle)<100.0) and (M.ccarecycle~=nil) and (IsAlive(M.ccarecycle)) then
            SetObjectiveOff(M.svpatrol1_2)
            M.retreat_success=true
        end
        if (M.patrolb1) and (not M.retreat_success) and (not M.alarm_on) and (Distance(M.svpatrol2_1,M.ccarecycle)<100.0) and (M.ccarecycle~=nil) and (IsAlive(M.ccarecycle)) then
            SetObjectiveOff(M.svpatrol2_1)
            M.retreat_success=true
        end
        if (M.patrolb2) and (not M.retreat_success) and (not M.alarm_on) and (Distance(M.svpatrol2_2,M.ccarecycle)<100.0) and (M.ccarecycle~=nil) and (IsAlive(M.ccarecycle)) then
            SetObjectiveOff(M.svpatrol2_2)
            M.retreat_success=true
        end
        if (M.patrolc1) and (not M.retreat_success) and (not M.alarm_on) and (Distance(M.svpatrol3_1,M.ccarecycle)<100.0) and (M.ccarecycle~=nil) and (IsAlive(M.ccarecycle)) then
            SetObjectiveOff(M.svpatrol3_1)
            M.retreat_success=true
        end
        if (M.patrolc2) and (not M.retreat_success) and (not M.alarm_on) and (Distance(M.svpatrol3_2,M.ccarecycle)<100.0) and (M.ccarecycle~=nil) and (IsAlive(M.ccarecycle)) then
            SetObjectiveOff(M.svpatrol3_2)
            M.retreat_success=true
        -- this is the message that they were detected
        end
        if ((M.retreat_success) and (IsAlive(M.new_tank1)) and (not M.detected_message)) or ((M.retreat_success) and (IsAlive(M.new_tank2)) and (not M.detected_message)) then
            AudioMessage("misn0707.wav")
            -- one of the runers has made it back
            M.detected_message=true
        -- now that the player is detetected the soviets will send tanks out to scout
        end
        if (M.retreat_success) and (not IsAlive(M.svpatrol1_1)) and (not IsAlive(M.svpatrol1_2)) and (not IsAlive(M.svpatrol1_3)) and (IsAlive(M.ccarecycle)) then
            M.svpatrol1_1=BuildObject("svtank",2,M.ccarecycle)
            M.svpatrol1_2=BuildObject("svtank",2,M.ccarecycle)
            --				svpatrol1_3 = BuildObject("svtank", 2, ccarecycle);
            Patrol(M.svpatrol1_1,"patrol_path1")
            Patrol(M.svpatrol1_2,"patrol_path1")
            --				Patrol(svpatrol1_3, "patrol_path1");
        --[==[/*			if ((retreat_success) && (!IsAlive(svpatrol2_1)) && 
				(!IsAlive(svpatrol2_2)) && (!IsAlive(svpatrol2_3)) && (IsAlive(ccarecycle)))

			{																					
				svpatrol2_1 = BuildObject("svtank", 2, ccarecycle);
				svpatrol2_2 = BuildObject("svtank", 2, ccarecycle);
				svpatrol2_3 = BuildObject("svtank", 2, ccarecycle);
				Patrol(svpatrol2_1, "patrol_path1");	
				Patrol(svpatrol2_2, "patrol_path1");
				Patrol(svpatrol2_3, "patrol_path1");
			}																					
*/]==]
        end
        if (M.retreat_success) and (not IsAlive(M.svpatrol3_1)) and (not IsAlive(M.svpatrol3_2)) and (not IsAlive(M.svpatrol3_3)) and (IsAlive(M.ccarecycle)) then
            M.svpatrol3_1=BuildObject("svtank",2,M.ccarecycle)
            M.svpatrol3_2=BuildObject("svtank",2,M.ccarecycle)
            --				svpatrol3_3 = BuildObject("svtank", 2, ccarecycle);
            Patrol(M.svpatrol3_1,"patrol_path1")
            Patrol(M.svpatrol3_2,"patrol_path1")
            --				Patrol(svpatrol3_3, "patrol_path1");
        --			if ((retreat_success) && (!IsAlive(svpatrol4_1)) && 
        --				(!IsAlive(svpatrol4_2)) && (IsAlive(ccarecycle)))	
        --			{																				
        --				svpatrol4_1 = BuildObject("svtank", 2, ccarecycle);								
        --				svpatrol4_2 = BuildObject("svtank", 2, ccarecycle);								
        --				Patrol(svpatrol4_1, "patrol_path2");											
        --				Patrol(svpatrol4_2, "patrol_path2");											
        --			}
        end
    -- end of retreat code /////////////////////////////////////////
    -- building more patrol ships if patrol ships are lost /////////////////////////////////////
    end
    if not M.first_objective then
        if (not IsAlive(M.svpatrol1_1)) and (not IsAlive(M.svpatrol1_2)) and (IsAlive(M.ccarecycle)) and (not M.detected) then
            M.svpatrol1_1=BuildObject("svfigh",2,M.ccarecycle)
            M.svpatrol1_2=BuildObject("svfigh",2,M.ccarecycle)
            Patrol(M.svpatrol1_1,"patrol_path1")
            Patrol(M.svpatrol1_2,"patrol_path1")
            M.p1_retreat=false
            M.getum=false
            M.patrola1=false
            M.patrola2=false
        --[==[/*	if ((!IsAlive(svpatrol2_1)) && (!IsAlive(svpatrol2_2)) && (IsAlive(ccarecycle)) && (!detected))	
	{																					
		svpatrol2_1 = BuildObject("svfigh", 2, ccarecycle);								
		svpatrol2_2 = BuildObject("svfigh", 2, ccarecycle);						
		Patrol(svpatrol2_1, "patrol_path1");										
		Patrol(svpatrol2_2, "patrol_path1");
		p2_retreat = false;
		getum = false;
		patrolb1 = false;
		patrolb2 = false;
	}																					
*/]==]
        end
        if (not IsAlive(M.svpatrol3_1)) and (not IsAlive(M.svpatrol3_2)) and (IsAlive(M.ccarecycle)) and (not M.detected) then
            M.svpatrol3_1=BuildObject("svfigh",2,M.ccarecycle)
            M.svpatrol3_2=BuildObject("svfigh",2,M.ccarecycle)
            Patrol(M.svpatrol3_1,"patrol_path1")
            Patrol(M.svpatrol3_2,"patrol_path1")
            M.p3_retreat=false
            M.getum=false
            M.patrolc1=false
            M.patrolc2=false
        end
        if (not IsAlive(M.svpatrol4_1)) and (not IsAlive(M.svpatrol4_2)) and (IsAlive(M.ccarecycle)) then
            M.svpatrol4_1=BuildObject("svfigh",2,M.ccarecycle)
            M.svpatrol4_2=BuildObject("svfigh",2,M.ccarecycle)
            Patrol(M.svpatrol4_1,"patrol_path2")
            Patrol(M.svpatrol4_2,"patrol_path2")
        end
    -- end of scout building code ////////////////////////////////////////////////////////////////
    -- this is what happens when the player reaches the jump overlook - the rookie tells him about the test range
    --[==[/*
	if ((recon_message2_time < Get_Time()) && (!recon_message2))
	{
		recon_message2_time = Get_Time() + 20.0f;
		
		if ((!test_found) && (!recon_message2))
		{
			AudioMessage("misn0703.wav"); // rookie "I found a soviet test range
			becon_build_time = Get_Time() + 15.0f;
			check_range = Get_Time() + 20.0f;
			recon_message2 = true;
		}
	}
				
	if ((recon_message2) && (becon_build_time < Get_Time()) && (!becon_build))//rookie lays path through mines
	{
		nav4 = BuildObject ("apcamr", 1, "cam_spawn6");
		rookie_rendezvous_time = Get_Time() + 120.0f;
		becon_build = true;
	}

	if ((becon_build) && (nav4!=NULL))
	{
		GameObjectHandle::GetObj(nav4)->SetName("Testing Range");
	}

// this is how the rookie tells the player he's under attack

	if ((becon_build) && (rookie_rendezvous_time < Get_Time()) && (!rookie_lost))
	{
		rookie_rendezvous_time = Get_Time()	+ 21.0f;	

		if ((GetDistance (user, mine_geyz) > 400.0f) && (!rookie_lost))
		{
			AudioMessage("misn0704.wav"); // I'm under attack - I'll drop the a camera - goto to activate mine path
			nav5 = BuildObject ("apcamr", 1, "cam_spawn1");
			reach_mine_time = Get_Time() + 10.0f;
			rookie_lost = true;
		}
	}

	if ((rookie_lost) && (nav5!=NULL))
	{
		GameObjectHandle::GetObj(nav5)->SetName("Mine Field");
	}

	if ((rookie_lost) && (reach_mine_time < Get_Time()) && (!mine_pathed))
	{
		reach_mine_time = Get_Time() + 10.0f;
			
		if ((GetDistance(user, nav5) < 70.0f) && (!mine_pathed))
		{
			becon1 = BuildObject ("apcamr", 1, "cam_spawn2");
			becon2 = BuildObject ("apcamr", 1, "cam_spawn3");
			becon3 = BuildObject ("apcamr", 1, "cam_spawn4");
			becon4 = BuildObject ("apcamr", 1, "cam_spawn5");
			mine_pathed = true;
		}
	}

		if ((mine_pathed) && (becon1!=NULL))
		{
			GameObjectHandle::GetObj(becon1)->SetName("Mine Path 1");
		}
		if ((mine_pathed) && (becon2!=NULL))
		{
			GameObjectHandle::GetObj(becon2)->SetName("Mine Path 2");
		}
		if ((mine_pathed) && (becon3!=NULL))
		{
			GameObjectHandle::GetObj(becon3)->SetName("Mine Path 3");
		}
		if ((mine_pathed) && (becon4!=NULL))
		{
			GameObjectHandle::GetObj(becon4)->SetName("Mine Path 4");
		}

*/]==]
    -- end of rookie message about soviet test range /////////
    -- when the radar array is destroyed /////////////////////
    end
    if (not IsAlive(M.ccacomtower)) and (not M.first_objective) then
        M.audmsg=AudioMessage("misn0714.wav")
        M.radar_camera_time=GetTime()+10.0
        --		next_shot_time = Get_Time() + 20.0f;
        M.next_mission_time=GetTime()+7.5
        --		CameraReady();
        --		shot1 = true;
        M.first_objective=true
    --[==[/*	if (shot1)
	{
		CameraPath("radar_path", 4000, 1000, radar_geyser);
	}

	if ((shot1) && (radar_camera_time < Get_Time()))
	{
//		StopAudioMessage(audmsg);
//		audmsg = AudioMessage ("misn0714.wav");	
		shot1 = false;
		shot2 = true;
	}

	if (shot2)
	{
		CameraPath("movie_cam_spawn", 160, 0, show_geyser);
	}

	if ((!radar_camera_off) && (shot2) && (next_shot_time < Get_Time()))
	{
//		StopAudioMessage(audmsg);
		CameraFinish();
		shot2 = false;
		radar_camera_off = true;
	}

	if (((shot1) || (shot2)) && (!radar_camera_off))
	{
		if (CameraCancelled())
		{
			shot1 = false;
			shot2 = false;
//			StopAudioMessage(audmsg);
			CameraFinish();
			radar_camera_off = true;
		}
	}
*/]==]
    end
    if (M.first_objective) and (not M.next_mission) and (M.next_mission_time<GetTime()) then
        M.nsdfrecycle=BuildObject("avrec7",1,"recycle_spawn")
        M.nsdfmuf=BuildObject("avmu7",1,"muf_spawn")
        Goto(M.nsdfrecycle,"recycle_path",0)
        Goto(M.nsdfmuf,"muf_path",0)
        M.nav6=BuildObject("apcamr",1,"recycle_cam_spawn")
        M.nav7=BuildObject("apcamr",1,"recy_cam_spawn")
        if M.nav6~=nil then
            SetObjectiveName(M.nav6,"Utah Rendezvous")
        end
        if M.nav7~=nil then
            SetObjectiveName(M.nav7,"CCA BASE")
        end
        AddScrap(1,30)
        SetPilot(1,20)
        AddScrap(2,60)
        SetPilot(2,40)
        SetAIP("misn07.aip")
        --		SetObjectiveOn(recycler);
        --		SetObjectiveName(recycler, "Utah");
        M.ccabaseguntower1=BuildObject("sbtowe",2,"base_tower1_spawn")
        --		ccabaseguntower2 = BuildObject("sbtowe", 2, "base_tower2_spawn");
        ClearObjectives()
        AddObjective("misn0701.otf","green")
        AddObjective("misn0703.otf","white")
        AddObjective("misn0702.otf","white")
        M.next_mission=true
    end
    if (M.next_mission) and (not IsAlive(M.ccarecycle)) then
        M.second_objective=true
    end
    if (M.next_mission) and (not M.utah_found) then
        if IsAlive(M.nsdfrecycle) then
            local deployed = IsDeployed(M.nsdfrecycle)
            if deployed then
                ClearObjectives()
                AddObjective("misn0703.otf","green")
                AddObjective("misn0702.otf","white")
                M.utah_found=true
            end
        end
    -- here is an attempt at the mine code ////////////
    --[==[/*
	for (count = mine_check; count < mine_check + 10; count = count + 1)
	{
		if (GetDistance(user, mine[count]) < 400.0f)
		{
			if ((!m_on[count]) && (!m_dead[count]))
			{
				m[count] = BuildObject ("proxmine", 2, mine[count]);
				m_on[count] = true;
			}
			if ((m_on[count]) && (!IsAlive(m[count])))
			{
				m_dead[count] = true;
			}
		}
		else
		{
			if ((m_on[count]) && (!m_dead[count]))
			{
				RemoveObject(m[count]);
				m_on[count] = false;
			}
		}
	}
*/]==]
    -- this is the code that operates the MAG cannon and camera when the player encounters it
    --[==[/*
	if ((recon_message2) && (GetDistance(user, test_tank) < 65.0f) 
		&& (!camera_ready))
	{															
		CameraReady();
		GameObjectHandle:: GetObj(test_turret)->AddHealth(-950.0f); 
		camera_ready = true;									
	}															
																
	if ((camera_ready) && (!camera1_on))
	{															
		CameraObject(test_tank, 2000, 800, 500, user);
		AudioMessage("misn0711.wav");
		start_sound = Get_Time() + 8.0f;
		change_angle = Get_Time() + 6.0f;
		camera1_on = true;
	}

	if ((camera1_on) && (change_angle < Get_Time()) && (!camera3_on))
	{
		CameraPath("camera_path1", 250,  250, test_tank);
		camera2_on = true;
	}

	if ((camera2_on) && (!camera2_oned))
	{
		change_angle1 = Get_Time() + 8.0f;
		camera2_oned = true;
	}

	if ((change_angle1 < Get_Time()) && (!camera4_on))
	{
		CameraPath("camera_path2", 310, 500, test_turret);
		camera3_on = true;
	}

	if ((camera3_on) && (!camera3_oned))
	{
		change_angle2 = Get_Time() + 6.0f;
		switch_tank = Get_Time() + 5.0f;
		camera3_oned = true;
	}

	if ((switch_tank < Get_Time()) && (!tank_switch))
	{
		RemoveObject(test_tank);
		test_tank = BuildObject("svtnk7", 2, "test_tank_spawn");
		Attack(test_tank, test_turret);
		tank_switch = true;
	}
	
//	if ((change_angle2 < Get_Time()) && (!camera4_on))
//	{
//		CameraObject(test_tank, -300, 400,-750, test_turret);
//		change_angle3 = Get_Time() + 10.0f;
//		camera4_on = true;
//	}
	
	if ((change_angle2 < Get_Time()) && (!camera4_on))
	{
		CameraObject(test_turret, 1000, 300, 4700, test_turret);
		change_angle3 = Get_Time() + 10.0f;
		camera4_on = true;
	}

	if ((camera4_on) && (change_angle3 < Get_Time()) && (!camera_off))
	{
		CameraFinish();											
		camera_off = true;
	}
*/]==]
    -- win/loose conditions ///////////////////
    end
    if (M.next_mission) and (not IsAlive(M.nsdfrecycle)) and (not M.game_over) then
        AudioMessage("misn0712.wav")
        if not M.utah_found then
            ClearObjectives()
            AddObjective("misn0701.otf","green")
            AddObjective("misn0703.otf","red")
            AddObjective("misn0702.otf","white")
        end
        FailMission(GetTime()+15.0,"misn07f1.des")
        M.game_over=true
    end
    if (M.next_mission) and (not IsAlive(M.ccarecycle)) then
        M.second_objective=true
    end
    if (M.first_objective) and (M.second_objective) and (not M.game_over) then
        AudioMessage("misn0713.wav")
        SucceedMission(GetTime()+15.0,"misn07w1.des")
        M.game_over=true
    --////////////////////////////////////////////////////////
    -- END OF SCRIPT
    end
end

function Save()
    return M
end

function Load(state)
    M = state
end
