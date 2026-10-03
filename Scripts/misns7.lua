-- Faithful misns7 DLL-source port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misns7Mission.cpp
-- Original source and native serialization are preserved byte-for-byte in
-- References/Misns7Source. Every disabled gameplay statement remains inline.
-- Single player; stock BZR APIs only. See Docs/MISNS7_SOURCE_PORT.md.

local NEVER = 99999.0
local function NewState()
    return {
        -- Native bool fields (including unused cut-content state).
        start_done = false,
        get_recycle = false,
        camera_on_recycle = false,
        camera_off_recycle = false,
        svrecycle_unit_spawn = false,
        svrecycle_on = false,
        jail_unit_spawn = false,
        jail_camera_on = false,
        jail_camera_off = false,
        mission_fail = false,
        con_pickup = false,
        con_camera_on = false,
        con_camera_off = false,
        jail_dead = false,
        con1_in_apc = false,
        con2_in_apc = false,
        con3_in_apc = false,
        fully_loaded = false,
        two_loaded = false,
        one_loaded = false,
        apc_empty = false,
        going_to_recycle = false,
        get_muf = false,
        camera_on_muf = false,
        svmuf_unit_spawn = false,
        svmuf_on = false,
        camera_off_muf = false,
        get_supply = false,
        camera_on_supply = false,
        supply_unit_spawn = false,
        supply_on = false,
        camera_off_supply = false,
        supply_message = false,
        con1_safe = false,
        con2_safe = false,
        con3_safe = false,
        con1_dead = false,
        con2_dead = false,
        con3_dead = false,
        first_message_done = false,
        down_to_two = false,
        down_to_one = false,
        game_over = false,
        supplies_spawned = false,
        build_scav = false,
        fight1_built = false,
        fight2_built = false,
        fight3_built = false,
        fight4_built = false,
        nsdf_adjust = false,
        avmuf_built = false,
        pick_up = false,
        supply_first = false,
        jail_found = false,
        turret_move1 = false,
        build_turret = false,
        closer_message = false,
        muf_message = false,
        in_base = false,
        plan_a = false,
        plan_b = false,
        plan_c = false,
        plan_d = false,
        muf_found = false,
        gech_sent = false,
        muf_located = false,
        gech_adjust = false,
        rig_underway1 = false,
        build_tower1 = false,
        build_power1 = false,
        build_tower2 = false,
        muf_deployed = false,
        muf_redirect = false,
        new_rig = false,
        rig_show = false,
        rig_show2 = false,
        rig_show3 = false,
        rig_stop1 = false,
        rig_stop2 = false,
        main_off = false,
        main_on = false,
        main_build = false,
        last_tower = false,
        turret4_defend = false,
        maint_off = false,
        maint_on = false,
        maint_build = false,
        new_muf = false,
        silo_message = false,
        silo_message2 = false,
        turret_message = false,
        supply2_message = false,
        blah = false,
        apc_panic_message = false,
        muf_message2 = false,
        -- Native float fields (including unused cut-content state).
        unit_spawn_time1 = NEVER,
        con_spawn_time = NEVER,
        camera_off_time = NEVER,
        con_camera_time = NEVER,
        supply_spawn_time = NEVER,
        con1_pickup_time = NEVER,
        con2_pickup_time = NEVER,
        con3_pickup_time = NEVER,
        supply_message_time = NEVER,
        avfigh1_time = NEVER,
        avfigh2_time = NEVER,
        avfigh3_time = NEVER,
        avfigh4_time = NEVER,
        build_scav_time = NEVER,
        adjust_timer = NEVER,
        muf_message_time = NEVER,
        muf_scan_time = NEVER,
        tower1_timer = NEVER,
        rig_check = NEVER,
        turret_check = NEVER,
        bm_time = NEVER,
        b1_time = NEVER,
        b2_time = NEVER,
        b3_time = NEVER,
        b4_time = NEVER,
        b5_time = NEVER,
        b6_time = NEVER,
        b7_time = NEVER,
        check_a = NEVER,
        check_b = NEVER,
        check_c = NEVER,
        silo_check = NEVER,
        muf_build_time = NEVER,
        goo_time = NEVER,
        bturret_time = NEVER,
        -- Native Handle fields (including unused cut-content state).
        user = nil,
        temp = nil,
        fed_up_scrap = nil,
        svrecycle = nil,
        svmuf = nil,
        apc = nil,
        svsilo = nil,
        guntower1 = nil,
        guntower2 = nil,
        avrecycle = nil,
        avmuf = nil,
        avscav1 = nil,
        avscav2 = nil,
        avsilo = nil,
        hanger = nil,
        avtower1 = nil,
        avtower2 = nil,
        avtower3 = nil,
        avbarrack = nil,
        main_tower = nil,
        main_power = nil,
        geyser1 = nil,
        geyser2 = nil,
        geyser3 = nil,
        field_geyser1 = nil,
        jail = nil,
        supply = nil,
        avpower1 = nil,
        avpower2 = nil,
        con1 = nil,
        con2 = nil,
        con3 = nil,
        boxes = nil,
        svsilo2 = nil,
        supply1 = nil,
        supply2 = nil,
        supply3 = nil,
        supply4 = nil,
        supply5 = nil,
        supply6 = nil,
        supply7 = nil,
        supply8 = nil,
        supply9 = nil,
        avfight1 = nil,
        avfight2 = nil,
        avfight3 = nil,
        avfight4 = nil,
        avtank1 = nil,
        avtank2 = nil,
        avltnk1 = nil,
        avltnk2 = nil,
        avgech = nil,
        avturr1 = nil,
        avturr2 = nil,
        avturr3 = nil,
        avturr4 = nil,
        avrig = nil,
        b1 = false,
        b2 = false,
        b3 = false,
        b4 = false,
        b5 = false,
        b6 = false,
        b7 = false,
        b8 = false,
        b9 = false,
        b0 = false,
        newmuf = nil,
        engineer = nil,
        con_geyser = nil,
        bturret1 = nil,
        bturret2 = nil,
        bturret3 = nil,
        bturret4 = nil,
        bvrig = nil,
        bvrecycle = nil,
        -- Native int fields (including unused cut-content state).
        stuff = 0,
        stuff2 = 0,
        stuff4 = 0,
        scrap = 0,
    }
end
local M = NewState()

-- BUGFIX / Lua adaptation: native null handles behave as absent objects.
-- Lua treats numeric 0 as true and nil can select the wrong distance overload.
-- An absent object is far away, so it cannot trigger pickups or deliveries.
-- All live-object distances and the source thresholds/order are unchanged.
local function Distance(a, b)
    if not IsValid(a) or not IsValid(b) then return math.huge end
    return GetDistance(a, b)
end

-- Stock IsOdf accepts engine ODF names; keep the native short basenames.
local function IsOdfBase(h, name)
    return IsValid(h) and (IsOdf(h, name) or IsOdf(h, name .. ".odf"))
end

-- BUGFIX: b0..b9 were declared as native Handles but used as construction
-- booleans (b1/b2 active, b3/b4 disabled). Store them as booleans, never 0/1
-- handles. This avoids Lua's truthy zero and save-load handle conversion while
-- keeping the same build steps, five-second delays, and disabled content.

local function Setup()
    M.stuff = 10
    M.stuff2 = 0
    M.stuff4 = 10
    M.scrap = 0
    M.main_on = true
    M.maint_on = true
    --	svrecycle = GetHandle ("svrecycle");
    --	svmuf = GetHandle ("svmuf");
    -- Native camera_off_supply = NULL initializes a bool to false, not a handle.
    M.camera_off_supply = false
    M.apc = GetHandle("svapc")
    M.avrecycle = GetHandle("avrecycle")
    M.jail = GetHandle("jail")
    M.supply = GetHandle("supply")
    M.geyser1 = GetHandle("geyser1")
    M.geyser2 = GetHandle("geyser2")
    M.geyser3 = GetHandle("geyser3")
    M.boxes = GetHandle("boxes")
    M.fed_up_scrap = GetHandle("getum_started")
    M.svsilo = GetHandle("svsilo")
    M.guntower1 = GetHandle("guntower1")
    M.guntower2 = GetHandle("guntower2")
    M.field_geyser1 = GetHandle("field_geyser1")
    M.avsilo = GetHandle("avsilo")
    M.hanger = GetHandle("hanger")
    M.avrig = GetHandle("rig")
    M.main_power = GetHandle("wind_power1")
    M.con_geyser = GetHandle("con_geyser")
    M.bturret1 = GetHandle("bturret1")
    M.bturret2 = GetHandle("bturret2")
    M.svrecycle = GetHandle("svrecycle")
    M.svmuf = GetHandle("svmuf")
    M.main_tower = GetHandle("main_tower")
    M.avmuf = nil
    M.bturret3 = nil
    M.bturret4 = nil
    M.bvrig = nil
    M.bvrecycle = nil
end

function Start()
    -- AiMission enables the enemy strategic AI in native code. LuaMission
    -- requires this startup configuration; never toggle AI in Update/Load.
    SetAIControl(2, true)
    Setup()
end

function AddObject(h)
    -- BUGFIX: native main_tower/main_power were filled only when NULL.
    -- Destroyed handles are non-nil in Lua, so the existing maintenance loop
    -- could never observe their replacements. Accept a replacement only while
    -- its predecessor is dead; live slots and build order remain unchanged.
    if (M.avscav1 == nil) and (IsOdfBase(h,"bvscav")) then
        M.avscav1 = h
    elseif (M.avscav2 == nil) and (IsOdfBase(h,"bvscav")) then
        M.avscav2 = h
    elseif (M.avfight1 == nil) and (IsOdfBase(h,"bvraz")) then
        M.avfight1 = h
    elseif (M.avfight2 == nil) and (IsOdfBase(h,"bvraz")) then
        M.avfight2 = h
    elseif (M.avtank1 == nil) and (IsOdfBase(h,"bvtank")) then
        M.avtank1 = h
    elseif (M.avtank2 == nil) and (IsOdfBase(h,"bvtank")) then
        M.avtank2 = h
    elseif (M.avltnk1 == nil) and (IsOdfBase(h,"bvltnk")) then
        M.avltnk1 = h
    elseif (M.avltnk2 == nil) and (IsOdfBase(h,"bvltnk")) then
        M.avltnk2 = h
    elseif (M.avgech == nil) and (IsOdfBase(h,"bvwalk")) then
        M.avgech = h
    elseif (M.avturr1 == nil) and (IsOdfBase(h,"bvturr")) then
        M.avturr1 = h
    elseif (M.avturr2 == nil) and (IsOdfBase(h,"bvturr")) then
        M.avturr2 = h
    elseif (not IsAlive(M.main_tower)) and (IsOdfBase(h,"abtowe")) then
        M.main_tower = h
    elseif (M.avtower1 == nil) and (IsOdfBase(h,"abtowe")) then
        M.avtower1 = h
    elseif (M.avtower2 == nil) and (IsOdfBase(h,"abtowe")) then
        M.avtower2 = h
    elseif (not IsAlive(M.main_power)) and (IsOdfBase(h,"abwpow")) then
        M.main_power = h
    elseif (M.avpower1 == nil) and (IsOdfBase(h,"abwpow")) then
        M.avpower1 = h
    elseif (M.avpower2 == nil) and (IsOdfBase(h,"abwpow")) then
        M.avpower2 = h
    elseif (IsAlive(M.svmuf)) and (M.newmuf == nil) and (IsOdfBase(h,"svmuf")) then
        M.newmuf = h
    elseif (not IsAlive(M.avmuf)) and (IsOdfBase(h,"bvmuf")) then
        M.avmuf = h
    end
end

function Update(dt)
    -- START OF SCRIPT
    M.user = GetPlayerHandle()
    --assigns the player a handle every frame
    --	scrap = GetScrap(2);// gets the american's scrap
    --	if ((scrap < 19) && (IsAlive(avrig)))
    --	{
    --		SetScrap(2, 20);
    --	}
    if not M.start_done then
        SetPilot(1,8)
        SetScrap(2,40)
        SetPilot(2,40)
        SetObjectiveOn(M.jail)
        SetObjectiveName(M.jail,"Military Prison")
        AudioMessage("misns700.wav")
        -- General "mission breifing"
        ClearObjectives()
        AddObjective("misns700.otf","white")
        M.build_scav_time = GetTime()+ 8.0
        Defend(M.svmuf)
        Defend(M.avrig)
        Defend(M.bturret1)
        Defend(M.bturret2)
        M.bturret_time = GetTime()+ 60.0
        SetPerceivedTeam(M.guntower1,2)
        SetPerceivedTeam(M.guntower2,2)
        SetPerceivedTeam(M.svrecycle,2)
        M.muf_scan_time = GetTime()+ 240.0
        Build(M.avrig,"abtowe")
        M.start_done = true
    end
    if M.bturret_time < GetTime() then
        M.bturret_time = GetTime()+ 180.0
        if IsAlive(M.bturret1) then
            Defend(M.bturret1)
        end
        if IsAlive(M.bturret2) then
            Defend(M.bturret2)
        end
    end
    if (M.start_done) and (Distance(M.user,M.jail)< 150.0) and (not M.jail_found) then
        AudioMessage("misns722.wav")
        M.adjust_timer = GetTime()+ 120.0
        M.jail_found = true
    end
    if (M.start_done) and (M.build_scav_time < GetTime()) and (not M.build_scav) then
        M.avscav1 = BuildObject("bvscav",2,"muf_point")
        M.avscav2 = BuildObject("bvscav",2,"muf_point")
        --		main_tower = BuildObject("abtowe", 2, "main_tower");
        Goto(M.avscav1,M.fed_up_scrap,0)
        Goto(M.avscav2,M.fed_up_scrap,0)
        M.silo_check = GetTime()+ 10.0
        M.build_scav = true
    end
    -- this is what happens if the player attacks the american scavengers right away
    if not M.jail_dead then
        if (((IsAlive(M.avscav1)) and (GetHealth(M.avscav1)< 0.91)) or ((IsAlive(M.avscav2)) and (GetHealth(M.avscav2)< 0.91)) or ((IsAlive(M.main_power)) and (GetHealth(M.main_power)< 0.95)) or ((IsAlive(M.avrecycle)) and (GetHealth(M.avrecycle)< 0.95)) or ((IsAlive(M.avrig)) and (GetHealth(M.avrig)< 0.95))) and (not M.nsdf_adjust) then
            M.nsdf_adjust = true
        end
    end
    if (IsAlive(M.jail)) and (not M.in_base) and (GetHealth(M.jail)< 0.50) then
        M.in_base = true
    end
    if (M.jail_found) and (M.adjust_timer < GetTime()) and (not M.nsdf_adjust) and (not M.jail_dead) then
        M.nsdf_adjust = true
    end
    -- the nsdf adjusts by building fighters and sending them after the player
    if (M.nsdf_adjust) and (not M.fight1_built) then
        M.avfight1 = BuildObject("bvraz",2,"muf_point")
        Attack(M.avfight1,M.user)
        M.avfigh2_time = GetTime()+ 20.0
        M.fight1_built = true
    end
    if (M.nsdf_adjust) and (M.fight1_built) and (M.avfigh2_time < GetTime()) and (not M.fight2_built) then
        M.avfight2 = BuildObject("bvraz",2,"muf_point")
        Attack(M.avfight2,M.user)
        M.avfigh3_time = GetTime()+ 20.0
        M.fight2_built = true
    end
    if (M.nsdf_adjust) and (M.fight2_built) and (M.avfigh3_time < GetTime()) and (not M.fight3_built) then
        M.avfight3 = BuildObject("bvraz",2,"muf_point")
        -- this is going to send the third fighter after the apc if the 
        -- second fighter is still alive and the apc is within radar range
        if IsAlive(M.avfight2) then
            Attack(M.avfight3,M.apc)
        else
            Attack(M.avfight3,M.user)
        end
        SetScrap(2,40)
        M.fight3_built = true
    end
    if (M.nsdf_adjust) and (IsAlive(M.avfight3)) and (not M.jail_dead) and (not M.build_turret) then
        M.avturr1 = BuildObject("bvturr",2,"muf_point")
        M.build_turret = true
    end
    -- this is when the player destroys the jail
    if (not IsAlive(M.jail)) and (not M.jail_dead) then
        CameraReady()
        M.con_spawn_time = GetTime()+ 1.5
        M.jail_dead = true
    end
    if (M.jail_dead) and (not M.jail_camera_on) then
        CameraObject(M.geyser1,- 1500,1000,- 5000,M.boxes)
        M.camera_off_time = GetTime()+ 3.5
        M.jail_camera_on = true
    end
    if (M.jail_dead) and (M.con_spawn_time < GetTime()) and (not M.jail_unit_spawn) then
        M.con1 = BuildObject("sssold",1,"con1_spot")
        M.con2 = BuildObject("sssold",1,"con2_spot")
        M.con3 = BuildObject("sssold",1,"con3_spot")
        SetIndependence(M.con1,0)
        SetIndependence(M.con2,0)
        SetIndependence(M.con3,0)
        GetIn(M.con1,M.apc,1)
        GetIn(M.con2,M.apc,1)
        GetIn(M.con3,M.apc,1)
        M.jail_unit_spawn = true
    end
    if (M.jail_camera_on) and (M.camera_off_time < GetTime()) and (not M.jail_camera_off) then
        CameraFinish()
        M.muf_build_time = GetTime()+ 5.0
        M.jail_camera_off = true
    end
    -- tells the player to move the apc in if it is too far away
    if (M.jail_camera_off) and (not M.closer_message) then
        if Distance(M.apc,M.boxes)> 70.0 then
            AudioMessage("misns710.wav")
            M.closer_message = true
        else
            M.closer_message = true
        end
    end
    -- this is the apc telling the player to get him out of there
    if (M.jail_camera_off) and (IsAlive(M.apc)) and (M.avfigh2_time < GetTime()) and (not M.fully_loaded) and (GetHealth(M.apc)< 0.80) and (not M.apc_panic_message) then
        AudioMessage("misns723.wav")
        M.apc_panic_message = true
    end
    -- now that the jail is down the nsdf builds its muf
    if (M.jail_camera_off) and (M.muf_build_time < GetTime()) and (not M.avmuf_built) then
        M.avmuf = BuildObject("bvmuf",2,"muf_point")
        Defend(M.avmuf)
        Goto(M.avmuf,M.geyser1)
        M.avfigh1_time = GetTime()+ 30.0
        M.avmuf_built = true
    end
    -- this is just seeing if the avmuf is deployed
    if IsAlive(M.avtank1) then
        M.muf_deployed = true
    end
    -- if the muf is attacked it will redirect
    --[[	if ((avmuf_built) && (IsAlive(avmuf)) && (GameObjectHandle::GetObj(avmuf)->GetHealth()<0.50f) 
		&& (!muf_redirect) && (!muf_deployed))
	{
		Goto(avmuf, geyser3);
		muf_redirect = true;
	}
]]
    -- now that the nsdf has built an muf it will start building fighters
    if (M.avmuf_built) and (M.avfigh1_time < GetTime()) and (not M.fight1_built) then
        M.avfight1 = BuildObject("bvraz",2,"muf_point")
        SetPerceivedTeam(M.guntower1,2)
        SetPerceivedTeam(M.guntower2,2)
        SetPerceivedTeam(M.svrecycle,2)
        M.avfigh2_time = GetTime()+ 30.0
        M.fight1_built = true
    end
    if (M.avmuf_built) and (M.fight1_built) and (M.avfigh2_time < GetTime()) and (not M.fight2_built) then
        M.avfight2 = BuildObject("bvraz",2,"muf_point")
        -- this is going to send the second fighter after the apc if the first fighter is still alive and the apc is within radar range 
        if (IsAlive(M.avfight1)) and (Distance(M.apc,M.boxes)< 200.0) then
            Attack(M.avfight2,M.apc)
        end
        SetAIP("misns7.aip")
        SetPerceivedTeam(M.guntower1,2)
        SetPerceivedTeam(M.guntower2,2)
        SetPerceivedTeam(M.svrecycle,2)
        AddScrap(2,40)
        M.fight2_built = true
    end
    if (IsAlive(M.avturr1)) and (not M.turret_move1) then
        Goto(M.avturr1,"turret_spot")
        M.turret_move1 = true
    end
    -- this what happens if the muf is destroyed
    if (M.avmuf_built) and (not IsAlive(M.avmuf)) and (not M.plan_b) then
        AddScrap(2,20)
        SetAIP("misns7c.aip")
        SetPerceivedTeam(M.guntower1,2)
        SetPerceivedTeam(M.guntower2,2)
        SetPerceivedTeam(M.svrecycle,2)
        M.plan_c = false
        M.plan_b = true
    end
    if (M.plan_b) and (IsAlive(M.avmuf)) and (not M.plan_c) then
        if M.plan_a then
            -- if the player has already gotten his muf
            SetAIP("misns7a.aip")
            -- this has scavs
            SetPerceivedTeam(M.guntower1,2)
            SetPerceivedTeam(M.guntower2,2)
            SetPerceivedTeam(M.svrecycle,2)
        else
            SetAIP("misns7.aip")
            SetPerceivedTeam(M.guntower1,2)
            SetPerceivedTeam(M.guntower2,2)
            SetPerceivedTeam(M.svrecycle,2)
        end
        --		AddScrap(2, 20);
        Goto(M.avmuf,M.geyser1)
        M.plan_b = false
        M.plan_c = true
    end
    -- this determines if the cons are killed BEFORE they get into the apc (since getting into an apc techincally "kills" them
    if (M.jail_unit_spawn) and (not IsAlive(M.con1)) and (not M.con1_in_apc) then
        M.con1_dead = true
    end
    if (M.jail_unit_spawn) and (not IsAlive(M.con2)) and (not M.con2_in_apc) then
        M.con2_dead = true
    end
    if (M.jail_unit_spawn) and (not IsAlive(M.con3)) and (not M.con3_in_apc) then
        M.con3_dead = true
    end
    -- now that the cons are free the player has to pick them up
    --	if ((jail_unit_spawn) && (!con_pickup) && (GetDistance(apc,boxes) < 30.0f))
    --	{
    --//	Stop(apc, 0);
    --//	CameraReady();
    --		Retreat(con1, apc);
    --		Retreat(con2, apc);
    --		Retreat(con3, apc);
    --		con_pickup = true;
    --	}
    -- this is instructing the apc to stop when in close proximity to a con
    --[[	
		if ((jail_unit_spawn) && (con1!= NULL) && (GetDistance(con1, apc) < 25.0f) && (!pick_up))
		{
			Stop(apc, 0);
			pick_up = true;
		}

		if((jail_unit_spawn) && (con2!= NULL) && (GetDistance(con2, apc) < 25.0f) && (!pick_up))
		{
			Stop(apc, 0);
			pick_up = true;
		}

		if((jail_unit_spawn) && (con3!= NULL) && (GetDistance(con3, apc) < 25.0f) && (!pick_up))
		{
			Stop(apc, 0);
			pick_up = true;
		}
		
		if ((pick_up) && (con1!= NULL) && (GetDistance(con1, apc) < 50.0f))
		{
			pick_up = false;
		}

		if ((pick_up) && (con2!= NULL) && (GetDistance(con2, apc) < 50.0f))
		{
			pick_up = false;
		}

		if ((pick_up) && (con3!= NULL) && (GetDistance(con3, apc) < 50.0f))
		{
			pick_up = false;
		}
]]
    --	if ((con_pickup) && (!con_camera_on))
    --	{
    --		CameraObject(geyser1, -2000, 2000, -4000, boxes);
    --		con_camera_time = Get_Time() + 7.0f;
    --		con_camera_on = true;
    --	}
    if (M.jail_unit_spawn) and (Distance(M.con1,M.apc)< 20.0) and (not M.con1_dead) and (not M.con1_in_apc) then
        M.con1_pickup_time = GetTime()+ 0.2
        M.con1_in_apc = true
    end
    if (M.con1_in_apc) and (M.con1_pickup_time < GetTime()) and (not M.con1_safe) then
        RemoveObject(M.con1)
        AddPilot(1,1)
        AudioMessage("misns702.wav")
        -- con 1 on board sir! 726
        M.goo_time = GetTime()+ 5.0
        M.pick_up = true
        M.con1_safe = true
    end
    if (M.jail_unit_spawn) and (Distance(M.con2,M.apc)< 20.0) and (not M.con2_dead) and (not M.con2_in_apc) then
        M.con2_pickup_time = GetTime()+ 0.2
        M.con2_in_apc = true
    end
    if (M.con2_in_apc) and (M.con2_pickup_time < GetTime()) and (not M.con2_safe) then
        RemoveObject(M.con2)
        AddPilot(1,1)
        AudioMessage("misns702.wav")
        -- con 2 on board sir! 726
        M.goo_time = GetTime()+ 5.0
        M.pick_up = true
        M.con2_safe = true
    end
    if (M.jail_unit_spawn) and (Distance(M.con3,M.apc)< 20.0) and (not M.con3_dead) and (not M.con3_in_apc) then
        M.con3_pickup_time = GetTime()+ 0.2
        M.con3_in_apc = true
    end
    if (M.con3_in_apc) and (M.con3_pickup_time < GetTime()) and (not M.con3_safe) then
        RemoveObject(M.con3)
        AddPilot(1,1)
        AudioMessage("misns702.wav")
        -- con 3 on board sir! 726
        M.goo_time = GetTime()+ 5.0
        M.pick_up = true
        M.con3_safe = true
    end
    -- here is where I set the "loaded" apc parameters (depending on how many cons get into the apc
    if (M.con1_safe) and (M.con2_safe) and (M.con3_safe) and (not M.fully_loaded) and (not M.first_message_done) and (not M.get_recycle) and (not M.get_muf) and (not M.get_supply) then
        AudioMessage("misns704.wav")
        M.fully_loaded = true
        M.muf_message_time = GetTime()+ 3.0
        M.check_a = GetTime()+ 1.0
        M.check_b = GetTime()+ 2.0
        M.check_c = GetTime()+ 3.0
        M.first_message_done = true
    end
    -- BUGFIX: C++ && bound the delivery guards only to the last OR arm.
    -- Apply them to every survivor permutation; the same one-shot message and
    -- deadlines still occur before the first engineer delivery.
    if (((M.con1_safe) and (M.con2_safe) and (M.con3_dead) and (not M.two_loaded)) or ((M.con1_safe) and (M.con2_dead) and (M.con3_safe) and (not M.two_loaded)) or ((M.con1_dead) and (M.con2_safe) and (M.con3_safe) and (not M.two_loaded))) and (not M.first_message_done) and (not M.get_recycle) and (not M.get_muf) and (not M.get_supply) then
        AudioMessage("misns705.wav")
        -- only two of us made it sir lets get the fuck outta here
        M.two_loaded = true
        M.muf_message_time = GetTime()+ 3.0
        M.check_a = GetTime()+ 1.0
        M.check_b = GetTime()+ 2.0
        M.check_c = GetTime()+ 3.0
        M.first_message_done = true
    end
    -- BUGFIX: C++ && bound the delivery guards only to the last OR arm.
    -- Apply them to every survivor permutation; the same one-shot message and
    -- deadlines still occur before the first engineer delivery.
    if (((M.con1_safe) and (M.con2_dead) and (M.con3_dead) and (not M.one_loaded)) or ((M.con1_dead) and (M.con2_safe) and (M.con3_dead) and (not M.one_loaded)) or ((M.con1_dead) and (M.con2_dead) and (M.con3_safe) and (not M.one_loaded))) and (not M.first_message_done) and (not M.get_recycle) and (not M.get_muf) and (not M.get_supply) then
        AudioMessage("misns706.wav")
        -- only one of us made it sir lets get the fuck outta here
        M.one_loaded = true
        M.muf_message_time = GetTime()+ 3.0
        M.check_a = GetTime()+ 1.0
        M.check_b = GetTime()+ 2.0
        M.check_c = GetTime()+ 3.0
        M.first_message_done = true
    end
    -- this is where the apc pilot tells the player about the muf
    if (IsAlive(M.apc)) and (M.pick_up) and (M.goo_time < GetTime()) and (not M.first_message_done) then
        M.goo_time = GetTime()+ 5.0
        M.stuff = CountUnitsNearObject(M.apc,200.0,2,nil)
        if M.stuff == 0 then
            if IsAlive(M.con1) then
                RemoveObject(M.con1)
            end
            if IsAlive(M.con2) then
                RemoveObject(M.con2)
            end
            if IsAlive(M.con3) then
                RemoveObject(M.con3)
            end
        end
    end
    if (IsAlive(M.apc)) and (M.first_message_done) and (M.muf_message_time < GetTime()) and (not M.muf_message) then
        M.muf_message_time = GetTime()+ 3.0
        M.stuff4 = CountUnitsNearObject(M.apc,200.0,2,nil)
        if M.stuff4 == 0 then
            if M.fully_loaded then
                AudioMessage("misns724.wav")
                AudioMessage("misns717.wav")
                M.muf_message_time = GetTime()+ 30.0
            else
                if M.two_loaded then
                    AudioMessage("misns725.wav")
                    AudioMessage("misns718.wav")
                    M.muf_message_time = GetTime()+ 30.0
                else
                    if M.one_loaded then
                        AudioMessage("misns725.wav")
                        AudioMessage("misns708.wav")
                        M.muf_message_time = GetTime()+ 30.0
                    end
                end
            end
            ClearObjectives()
            AddObjective("misns703.otf","green")
            AddObjective("misns701.otf","white")
            --			AddObjective("misns702.otf", WHITE);
            M.muf_message = true
        end
    end
    if (not M.muf_message2) and (M.muf_message) and (M.muf_message_time < GetTime()) then
        ClearObjectives()
        AddObjective("misns703.otf","green")
        AddObjective("misns701.otf","white")
        AddObjective("misns702.otf","white")
        M.muf_message2 = true
    end
    --	if ((con_camera_on) && (cons_loaded) && (!con_camera_off))
    --	{
    --		CameraFinish();
    --		con_camera_off = true;
    --	}
    -- this is the apc dropping off the engineer at the svrecycler
    if (M.first_message_done) and (not M.get_recycle) and (M.check_a < GetTime()) and (Distance(M.apc,M.svrecycle)< 50.0) then
        M.check_a = GetTime()+ 3.0
        --[[ && (GetDistance(apc, svrecycle) < 50.0f)]]
        if (not M.apc_empty) and (M.fully_loaded) and (not M.get_recycle) and (not M.down_to_two) then
            M.get_recycle = true
            CameraReady()
            Stop(M.apc,0)
            M.unit_spawn_time1 = GetTime()+ 2.0
            M.down_to_two = true
        end
        --[[ && (GetDistance(apc, svrecycle) < 50.0f)]]
        if (not M.apc_empty) and (M.two_loaded) and (not M.get_recycle) and (not M.down_to_one) then
            M.get_recycle = true
            CameraReady()
            Stop(M.apc,0)
            M.unit_spawn_time1 = GetTime()+ 2.0
            M.down_to_one = true
        end
        --[[ && (GetDistance(apc, svrecycle) < 50.0f)]]
        if (not M.apc_empty) and (M.one_loaded) and (not M.get_recycle) then
            M.get_recycle = true
            CameraReady()
            Stop(M.apc,0)
            M.unit_spawn_time1 = GetTime()+ 2.0
            M.apc_empty = true
        end
        --[[ && (GetDistance(apc, svrecycle) < 50.0f)]]
        if (not M.apc_empty) and (M.down_to_two) and (not M.get_recycle) and (not M.down_to_one) then
            M.get_recycle = true
            CameraReady()
            Stop(M.apc,0)
            M.unit_spawn_time1 = GetTime()+ 2.0
            M.down_to_one = true
        end
        --[[ && (GetDistance(apc, svrecycle) < 50.0f)]]
        if (not M.apc_empty) and (M.down_to_one) and (not M.get_recycle) then
            M.get_recycle = true
            CameraReady()
            Stop(M.apc,0)
            M.unit_spawn_time1 = GetTime()+ 2.0
            M.apc_empty = true
        end
    end
    if (M.get_recycle) and (not M.camera_off_recycle) then
        CameraObject(M.svrecycle,- 4000,1000,2000,M.svrecycle)
        --			camera_off_time = Get_Time + 8.0f;
        M.camera_on_recycle = true
    end
    if (M.camera_on_recycle) and (M.unit_spawn_time1 < GetTime()) and (not M.svrecycle_unit_spawn) then
        M.engineer = BuildObject("sssold",1,M.apc)
        Retreat(M.engineer,M.svrecycle,1)
        AddPilot(1,- 1)
        M.svrecycle_unit_spawn = true
    end
    if (M.svrecycle_unit_spawn) and (not M.svrecycle_on) and (Distance(M.engineer,M.svrecycle)< 25.0) then
        RemoveObject(M.engineer)
        M.svrecycle_on = true
    end
    if (M.svrecycle_unit_spawn) and (not M.camera_off_recycle) and ((M.svrecycle_on) or (CameraCancelled())) then
        CameraFinish()
        if IsAlive(M.engineer) then
            RemoveObject(M.engineer)
        end
        M.temp = BuildObject("svmine",0,M.svrecycle)
        Defend(M.temp)
        RemoveObject(M.svrecycle)
        M.svrecycle = BuildObject("svrecy",1,M.temp)
        RemoveObject(M.temp)
        --			if (IsAlive(guntower1))
        --			{
        --				SetPerceivedTeam(guntower1, 1);
        --			}
        --			if (IsAlive(guntower2))
        --			{
        --				SetPerceivedTeam(guntower2, 1);
        --			}
        if (not M.camera_off_muf) and (not M.camera_off_supply) then
            ClearObjectives()
            AddObjective("misns708.otf","white")
        else
            if (M.camera_off_muf) and (not M.camera_off_supply) then
                ClearObjectives()
                AddObjective("misns708.otf","white")
                AddObjective("misns704.otf","green")
                AddObjective("misns705.otf","white")
            else
                if (M.camera_off_muf) and (M.camera_off_supply) then
                    ClearObjectives()
                    AddObjective("misns708.otf","white")
                    AddObjective("misns704.otf","green")
                    AddObjective("misns706.otf","green")
                end
            end
        end
        AudioMessage("misns727.wav")
        AddScrap(1,20)
        SetAIP("misns7a.aip")
        SetPerceivedTeam(M.guntower1,2)
        SetPerceivedTeam(M.guntower2,2)
        SetPerceivedTeam(M.svrecycle,2)
        M.camera_off_recycle = true
    end
    -- this is when the player retakes his muf
    if not M.new_muf then
        if (M.first_message_done) and (not M.get_muf) and (M.check_b < GetTime()) and (Distance(M.apc,M.svmuf)< 40.0) then
            M.check_b = GetTime()+ 3.0
            --[[ && (GetDistance(apc, svmuf) < 50.0f)]]
            if (not M.apc_empty) and (M.fully_loaded) and (not M.get_muf) and (not M.down_to_two) then
                M.get_muf = true
                CameraReady()
                Stop(M.apc,0)
                M.unit_spawn_time1 = GetTime()+ 2.0
                M.down_to_two = true
            end
            --[[ && (GetDistance(apc, svmuf) < 50.0f)]]
            if (not M.apc_empty) and (M.two_loaded) and (not M.get_muf) and (not M.down_to_one) then
                M.get_muf = true
                CameraReady()
                Stop(M.apc,0)
                M.unit_spawn_time1 = GetTime()+ 2.0
                M.down_to_one = true
            end
            --[[ && (GetDistance(apc, svmuf) < 50.0f)]]
            if (not M.apc_empty) and (M.one_loaded) and (not M.get_muf) then
                M.get_muf = true
                CameraReady()
                Stop(M.apc,0)
                M.unit_spawn_time1 = GetTime()+ 2.0
                M.apc_empty = true
            end
            --[[ && (GetDistance(apc, svmuf) < 50.0f)]]
            if (not M.apc_empty) and (M.down_to_two) and (not M.get_muf) and (not M.down_to_one) then
                M.get_muf = true
                CameraReady()
                Stop(M.apc,0)
                M.unit_spawn_time1 = GetTime()+ 2.0
                M.down_to_one = true
            end
            --[[ && (GetDistance(apc, svmuf) < 50.0f)]]
            if (not M.apc_empty) and (M.down_to_one) and (not M.get_muf) then
                M.get_muf = true
                CameraReady()
                Stop(M.apc,0)
                M.unit_spawn_time1 = GetTime()+ 2.0
                M.apc_empty = true
            end
        end
        if (M.get_muf) and (not M.camera_off_muf) then
            CameraObject(M.svmuf,- 3000,1000,4000,M.svmuf)
            M.camera_on_muf = true
        end
        if (M.camera_on_muf) and (M.unit_spawn_time1 < GetTime()) and (not M.svmuf_unit_spawn) then
            M.engineer = BuildObject("sssold",1,M.apc)
            Retreat(M.engineer,M.svmuf,1)
            AddPilot(1,- 1)
            M.svmuf_unit_spawn = true
        end
        if (M.svmuf_unit_spawn) and (not M.svmuf_on) and (Distance(M.engineer,M.svmuf)< 20.0) then
            RemoveObject(M.engineer)
            M.svmuf_on = true
        end
        if (M.svmuf_unit_spawn) and (not M.camera_off_muf) and ((M.svmuf_on) or (CameraCancelled())) then
            if IsAlive(M.engineer) then
                RemoveObject(M.engineer)
            end
            M.temp = BuildObject("svmine",0,M.svmuf)
            Defend(M.temp)
            RemoveObject(M.svmuf)
            M.svmuf = BuildObject("svmuf",1,M.temp)
            RemoveObject(M.temp)
            AddScrap(1,20)
            CameraFinish()
            M.camera_off_muf = true
        end
        -- this is the message from the muf
        if (M.camera_off_muf) and (not M.supply_message) then
            if M.supply_first then
                AudioMessage("misns709.wav")
                -- found the key to open the lock to the silo
            end
            if not M.supply_first then
                AudioMessage("misns714.wav")
                -- found a key and map to the "devil's crown in north
            end
            if not M.camera_off_recycle then
                ClearObjectives()
                AddObjective("misns703.otf","green")
                AddObjective("misns701.otf","white")
                AddObjective("misns704.otf","green")
                AddObjective("misns705.otf","white")
            end
            M.supply_message = true
        end
    end
    -- this is when the player reaches the supply hut
    if M.camera_off_muf then
        if (M.first_message_done) and (not M.get_supply) and (M.check_c < GetTime()) and (Distance(M.apc,M.supply)< 70.0) then
            M.check_c = GetTime()+ 3.0
            --[[ && (GetDistance(apc, supply) < 50.0f)]]
            if (not M.apc_empty) and (M.fully_loaded) and (not M.get_supply) and (not M.down_to_two) then
                M.get_supply = true
                CameraReady()
                Stop(M.apc,0)
                M.unit_spawn_time1 = GetTime()+ 2.0
                M.down_to_two = true
            end
            --[[ && (GetDistance(apc, supply) < 50.0f)]]
            if (not M.apc_empty) and (M.two_loaded) and (not M.get_supply) and (not M.down_to_one) then
                M.get_supply = true
                CameraReady()
                Stop(M.apc,0)
                M.unit_spawn_time1 = GetTime()+ 2.0
                M.down_to_one = true
            end
            --[[ && (GetDistance(apc, supply) < 50.0f)]]
            if (not M.apc_empty) and (M.one_loaded) and (not M.get_supply) then
                M.get_supply = true
                CameraReady()
                Stop(M.apc,0)
                M.unit_spawn_time1 = GetTime()+ 2.0
                M.apc_empty = true
            end
            --[[ && (GetDistance(apc, supply) < 50.0f)]]
            if (not M.apc_empty) and (M.down_to_two) and (not M.get_supply) and (not M.down_to_one) then
                M.get_supply = true
                CameraReady()
                Stop(M.apc,0)
                M.unit_spawn_time1 = GetTime()+ 2.0
                M.down_to_one = true
            end
            --[[ && (GetDistance(apc, supply) < 50.0f)]]
            if (not M.apc_empty) and (M.down_to_one) and (not M.get_supply) then
                M.get_supply = true
                CameraReady()
                Stop(M.apc,0)
                M.unit_spawn_time1 = GetTime()+ 2.0
                M.apc_empty = true
            end
        end
        if (M.get_supply) and (not M.camera_off_supply) then
            CameraObject(M.supply,1000,1000,8000,M.supply)
            M.camera_on_supply = true
        end
        if (M.camera_on_supply) and (M.unit_spawn_time1 < GetTime()) and (not M.supply_unit_spawn) then
            M.engineer = BuildObject("sssold",1,M.apc)
            Retreat(M.engineer,"con_path",1)
            AddPilot(1,- 1)
            M.supply_unit_spawn = true
        end
        if (M.supply_unit_spawn) and (IsAlive(M.engineer)) and (not M.supply_on) and (Distance(M.engineer,M.con_geyser)< 30.0) then
            RemoveObject(M.engineer)
            --			supply_message_time = Get_Time() + 3.0f;
            M.supply_on = true
        end
        if (M.supply_unit_spawn) and (not M.camera_off_supply) and ((M.supply_on) or (CameraCancelled())) then
            if IsAlive(M.engineer) then
                RemoveObject(M.engineer)
            end
            if not M.camera_off_recycle then
                ClearObjectives()
                AddObjective("misns703.otf","green")
                AddObjective("misns701.otf","white")
                AddObjective("misns704.otf","green")
                AddObjective("misns706.otf","green")
            else
                ClearObjectives()
                AddObjective("misns708.otf","white")
                AddObjective("misns704.otf","green")
                AddObjective("misns706.otf","green")
            end
            M.camera_off_supply = true
            CameraFinish()
        end
        -- now that the player has an engineer in the supply shed he willl be given the goods
        --[[(supply_message_time < Get_Time()) && ]]
        if (M.camera_off_supply) and (not M.supply2_message) then
            AudioMessage("misns707.wav")
            -- I found some supplies in here
            M.supply_spawn_time = GetTime()+ 15.0
            M.supply2_message = true
        end
        if (M.supply_message) and (M.supply_spawn_time < GetTime()) and (not M.supplies_spawned) then
            M.supply1 = BuildObject("svscav",1,"supply1")
            M.supply2 = BuildObject("svturr",1,"supply2")
            M.supply3 = BuildObject("svturr",1,"supply3")
            M.supply4 = BuildObject("svscav",1,"supply4")
            M.supply5 = BuildObject("spammo",1,"supply5")
            M.supply6 = BuildObject("spammo",1,"supply6")
            M.supply7 = BuildObject("spammo",1,"supply7")
            M.supply8 = BuildObject("sprepa",1,"supply8")
            M.supply9 = BuildObject("sprepa",1,"supply9")
            Stop(M.supply1,0)
            Stop(M.supply4,0)
            M.supplies_spawned = true
        end
        if (M.supplies_spawned) and (not M.turret_message) then
            AudioMessage("misns721.wav")
            Stop(M.supply1,0)
            Stop(M.supply4,0)
            M.turret_message = true
        end
    end
    if (IsAlive(M.supply)) and (not M.camera_off_muf) and (Distance(M.user,M.supply)< 70.0) and (not M.supply_first) then
        AudioMessage("misns715.wav")
        -- tells the player that the hut is locked
        M.supply_first = true
    end
    -- this is sending the nsdf scavengers to their silo
    if ((M.supply_first) or (M.camera_off_muf)) and (not M.plan_a) then
        if IsAlive(M.avsilo) then
            if IsAlive(M.avscav1) then
                Goto(M.avscav1,M.avsilo)
            end
            if IsAlive(M.avscav2) then
                Goto(M.avscav2,M.avsilo)
            end
            if IsAlive(M.avturr1) then
                Goto(M.avturr1,"avsilo_spot1",1)
            end
            if IsAlive(M.avturr2) then
                Goto(M.avturr2,"avsilo_spot2",1)
            end
            if IsAlive(M.avfight1) then
                Goto(M.avfight1,M.avsilo,0)
            end
            if IsAlive(M.avfight2) then
                Goto(M.avfight2,M.avsilo,0)
            end
        end
        SetAIP("misns7b.aip")
        -- this has scavs
        SetPerceivedTeam(M.guntower1,2)
        SetPerceivedTeam(M.guntower2,2)
        SetPerceivedTeam(M.svrecycle,2)
        if IsAlive(M.avrig) then
            Defend(M.avrig)
        end
        M.plan_a = true
    end
    --	if ((plan_a) && (!IsAlive(avrig)) && (!plan_d))
    --	{
    --		SetAIP("misns7a.aip");// this has scavs
    --
    --		if ((!IsAlive(avscav1)) && (!IsAlive(avscav2)))
    --		{
    --			AddScrap(2, 20);
    --		}
    --
    --		plan_d = true;
    --	}
    -- this is checking to see if a gech is build and what to do with it
    if (M.muf_scan_time < GetTime()) and (not M.muf_located) then
        M.muf_scan_time = GetTime()+ 3.0
        if IsAlive(M.svmuf) then
            M.stuff2 = CountUnitsNearObject(M.svmuf,200.0,2,nil)
            if M.stuff2 > 0 then
                M.muf_located = true
            end
        end
    end
    if (IsAlive(M.avgech)) and (not M.gech_sent) then
        if M.muf_located then
            if IsAlive(M.svmuf) then
                Attack(M.avgech,M.svmuf)
            end
        else
            if IsAlive(M.avsilo) then
                Goto(M.avgech,M.avsilo,0)
            end
        end
        M.gech_sent = true
    end
    if (M.gech_sent) and (M.muf_located) and (not M.gech_adjust) then
        if (IsAlive(M.avgech)) and (IsAlive(M.svmuf)) then
            Attack(M.avgech,M.svmuf)
            M.gech_adjust = true
        end
    end
    -- this is the script that tells the rig to build a base
    -- this sends the rig to build the first guntower
    if (M.in_base) and (not M.build_tower1) then
        if IsAlive(M.avrig) then
            Dropoff(M.avrig,"tower1_spot")
            M.build_tower1 = true
        end
    end
    -- this sends the rig to build the third powerplant
    if (M.build_tower1) and (IsAlive(M.avtower1)) and (not M.b1) then
        if IsAlive(M.avrig) then
            Build(M.avrig,"abwpow")
            -- this is avpower1
            M.b1_time = GetTime()+ 5.0
            M.b1 = true
        end
    end
    if (M.b1) and (M.b1_time < GetTime()) and (not M.build_power1) then
        if IsAlive(M.avrig) then
            AddScrap(2,20)
            Dropoff(M.avrig,"power1_spot")
            M.b2_time = GetTime()+ 5.0
            M.build_power1 = true
        end
    end
    -- this sends the rig to build the next guntower
    if (M.build_power1) and (not M.main_off) and (not M.maint_off) and (IsAlive(M.avpower1)) and (not M.b2) then
        if (M.b2_time < GetTime()) and (IsAlive(M.avrig)) then
            Build(M.avrig,"abtowe")
            -- this is avtower2
            M.b3_time = GetTime()+ 5.0
            M.b2 = true
        end
    end
    if (M.b2) and (M.b3_time < GetTime()) and (not M.build_tower2) then
        if IsAlive(M.avrig) then
            Dropoff(M.avrig,"tower2_spot")
            M.b4_time = GetTime()+ 5.0
            M.build_tower2 = true
        end
    end
    -- this removes the rig and builds it again at the barracks spot
    if (IsAlive(M.avtower2)) and (IsAlive(M.avrig)) and (not M.new_rig) and (Distance(M.user,M.avrig)> 400.0) and (M.b4_time < GetTime()) then
        RemoveObject(M.avrig)
        --		avrig = BuildObject("avcnst", 2, "barrack_spot");
        --		Defend(avrig);
        --		Build(avrig, "abbarr");
        M.rig_check = GetTime()+ 10.0
        --		bm_time = Get_Time() + 5.0f;
        M.new_rig = true
    end
    -- this waits until the player is close and then builds a barracks, a turret and moves the rig
    if M.rig_show then
        -- this has the rig trying to maintain the main power and guntower
        --[[ && (bm_time < Get_Time())]]
        if (IsAlive(M.avrig)) and (not IsAlive(M.main_power)) and (not M.main_off) then
            Build(M.avrig,"abwpow")
            M.bm_time = GetTime()+ 10.0
            --		main_on = false;
            M.main_off = true
        end
        if (M.main_off) and (M.bm_time < GetTime()) and (not M.main_build) then
            if IsAlive(M.avrig) then
                Dropoff(M.avrig,"main_power")
                --				bm_time = Get_Time() + 5.0f;
                M.main_build = true
            end
        end
        if (M.main_build) and (IsAlive(M.main_power)) then
            --			bm_time = Get_Time() + 5.0f;
            M.main_build = false
            M.main_off = false
        end
        if (IsAlive(M.avrig)) and (not IsAlive(M.main_tower)) and (not M.main_off) and (not M.maint_off) then
            Build(M.avrig,"abtowe")
            M.bm_time = GetTime()+ 10.0
            --		maint_on = false;
            M.maint_off = true
        end
        if (M.maint_off) and (not M.maint_build) and (M.bm_time < GetTime()) then
            if IsAlive(M.avrig) then
                --				bm_time = Get_Time() + 5.0f;
                Dropoff(M.avrig,"main_tower")
                M.maint_build = true
            end
        end
        if (M.maint_build) and (IsAlive(M.main_tower)) then
            --			bm_time = Get_Time() + 5.0f;
            --			maint_on = true;
            M.maint_build = false
            M.maint_off = false
        end
    end
    -- this happens immediately after the player returns to the american base
    if (not M.rig_show) and (M.rig_check < GetTime()) then
        M.rig_check = GetTime()+ 5.0
        if Distance(M.user,M.avrecycle)< 400.0 then
            M.avrig = BuildObject("avcns7",2,"barrack_spot")
            Defend(M.avrig)
            Build(M.avrig,"abbarr")
            M.rig_check = GetTime()+ 20.0
            M.rig_show = true
        end
    end
    if (M.rig_show) and (IsAlive(M.avrig)) and (M.rig_check < GetTime()) and (not M.blah) then
        Dropoff(M.avrig,"barrack_spot")
        -- this is avbarrack
        M.avturr4 = BuildObject("bvturr",2,"muf_point")
        Goto(M.avturr4,"base_turret_spot1",1)
        M.turret_check = GetTime()+ 60.0
        M.blah = true
    end
    -- this stops the turret when its at its post
    if (IsAlive(M.avturr4)) and (M.turret_check < GetTime()) and (not M.turret4_defend) then
        Defend(M.avturr4,1)
        if IsAlive(M.avrig) then
            Defend(M.avrig,1)
        end
        M.turret4_defend = true
    end
    --[[	// this tells the rig to build the power plant in the center of the base
	if ((camera_off_recycle) && (IsAlive(avrig)) && (!main_off) && (!maint_off) && (!b3))
	{
		Build(avrig, "abwpow");// this is avpower2
		b5_time = Get_Time() + 5.0f;
		b3 = true;
	}

	if ((b3) && (!rig_show2) && (b5_time < Get_Time()))
	{
		if (IsAlive(avrig))
		{
			Dropoff(avrig, "power2_spot");
			b6_time = Get_Time() + 5.0f;
			rig_show2 = true;
		}
	}

	// this tells the rig to build the last guntower
	if ((rig_show2) && (IsAlive(avrig)) && ((IsAlive(avpower2)) || (IsAlive(avpower1)))
		&& (!main_off) && (!maint_off) && (!b4) && (b6_time < Get_Time()))
	{
		Build(avrig, "abtowe");// this is nothing
		b7_time = Get_Time() + 5.0f;
		b4 = true;
	}

	if ((b4) && (!rig_show3) && (b7_time < Get_Time()))
	{
		if (IsAlive(avrig))
		{
			Dropoff(avrig, "tower3_spot");
			rig_show3 = true;
		}
	}
]]
    -- this is determining if the player has got the the recycler before the muf
    if (M.camera_off_recycle) and (not M.camera_off_muf) and (IsAlive(M.newmuf)) and (not M.new_muf) then
        M.new_muf = true
    end
    --/ this is the message when the player reaches his silo
    if (not M.silo_message) and (IsAlive(M.svsilo)) and (M.silo_check < GetTime()) then
        M.silo_check = GetTime()+ 5.0
        if Distance(M.user,M.svsilo)< 90.0 then
            AudioMessage("misns720.wav")
            -- looks like one of ours
            M.silo_message = true
        end
    end
    -- win/loose conditions
    if (not IsAlive(M.avrecycle)) and (not M.game_over) then
        AudioMessage("misns712.wav")
        -- congradulations
        SucceedMission(GetTime()+ 10.0,"misns7w1.des")
        M.game_over = true
    end
    if (((M.con1_dead) and (M.con2_dead) and (M.con3_dead) and (not M.fully_loaded)) or ((M.con1_dead) and (M.con2_dead) and (M.con3_dead) and (not M.two_loaded)) or ((M.con1_dead) and (M.con2_dead) and (M.con3_dead) and (not M.one_loaded))) and (not M.game_over) then
        AudioMessage("misns711.wav")
        -- our comrades are dead
        FailMission(GetTime()+ 10.0,"misns7f1.des")
        M.game_over = true
    end
    if (not IsAlive(M.apc)) and (not M.camera_off_recycle) and (not M.camera_off_muf) and (not M.game_over) then
        AudioMessage("misns716.wav")
        -- you lost the apc
        FailMission(GetTime()+ 10.0,"misns7f2.des")
        M.game_over = true
    end
    -- END OF SCRIPT
end

function Save()
    return M
end

function Load(state)
    -- BZR remaps serialized handle values. Never rerun Setup, replay cameras,
    -- reset deadlines, or duplicate spawns when restoring the state table.
    M = state
end
