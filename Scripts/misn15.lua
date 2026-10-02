-- Faithful stock misn15 port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misn15Mission.cpp
-- Source blob: 75974c4173246e540bf871eedc94cf09736989c8.
-- Disabled C++ is retained at its corresponding location below. The complete
-- original, including declarations and native serialization, is archived in
-- References/Misn15Source/. No EXU/OpenShim or campaign helper is required.

local function NewState()
    -- Native Load initializes every member before Setup, including unused state.
    local state = {
        found_group1 = false, found_group2 = false,
        got_dough = false, start_done = false, cca_here = false,
        found = false, won = false, lost = false,
        camera1 = false, camera2 = false, camera3 = false, alien3 = false,
        misn15b = false, silo_built = false, tartarus = false,
        camera_time = 99999.0, second_message = 99999.0, sav_timer = 99999.0,
        rendezvous1 = 99999.0, rendezvous2 = 99999.0,
        rcam1 = 99999.0, rcam2 = 99999.0,
        deny_time1 = 99999.0, deny_time2 = 99999.0,
        misl_time = 99999.0, check_time = 99999.0,
        savcount = 0, silocount = 0, savlist = {},
    }
    -- Handles start nil: tart, player, scav1/2/3, muf1, tur1, art1, scavcam,
    -- hov1, audmsg, sat1..sat6, goal, tank, recy, cam1..cam6, tank1/2,
    -- scav_du_jour, and the 100 savlist slots. Keep the source's zero-based list.
    return state
end

-- Initialize before map AddObject callbacks. Start must not erase silo counts
-- collected while the map loads; Execute still performs startup on first Update.
local M = NewState()

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function Distance(from, to)
    -- PORT FIX: absent native handle operands cannot satisfy a proximity test.
    -- Guard Lua's overloads so a missing/deleted map object cannot trigger a
    -- false rendezvous or invalid call. Valid-map distances are unchanged.
    if not Valid(from) or not Valid(to) then return math.huge end
    return GetDistance(from, to)
end

local function ShowStuff()
    ClearObjectives()
    -- PORT FIX: the source paints all four green at victory, but later objective
    -- refreshes can undo that during its ten-second delay. Keep that completed
    -- display after got_dough; no objective or victory prerequisite is added.
    AddObjective("misn1501.otf", (M.got_dough or M.cca_here) and "green" or "white")
    AddObjective("misn1502.otf", (M.got_dough or M.found_group1) and "green" or "white")
    AddObjective("misn1503.otf", (M.got_dough or M.silo_built) and "green" or "white")
    AddObjective("misn1504.otf", (M.got_dough or M.won) and "green" or "white")
end

function Start()
    -- NewState implements native Load/Setup; startup actions remain in Update.
end

function AddObject(h)
    --[[
		This has lost its relevence
		if it works at all.  
    ]]
    if not Valid(h) or GetTeamNum(h) ~= 1 then return end
    if IsOdf(h, "avscav") then
        M.found = true
        M.scav_du_jour = h
    elseif IsOdf(h, "absilo") then
        -- Source counts silos added, not currently surviving silos. Deliberately
        -- do not decrement on destruction or introduce a new victory gate.
        M.silocount = M.silocount + 1
    end
end

function Update(dt)
    M.player = GetPlayerHandle()
    if not M.start_done then
        -- SetAIP("misn15.aip");
        AddScrap(1, 10)
        ShowStuff()
        M.misn15b = Valid(GetHandle("misn15b")) -- is this that map.
        M.tart = GetHandle("ubtart0_i76building")
        M.recy = GetHandle("avrecy0_recycler")
        M.cam1 = GetHandle("apcamr0_camerapod")
        M.cam2 = GetHandle("apcamr1_camerapod")
        M.cam3 = GetHandle("apcamr2_camerapod")
        M.cam4 = GetHandle("apcamr3_camerapod")
        M.cam5 = GetHandle("apcamr4_camerapod")
        M.cam6 = GetHandle("apcamr5_camerapod")
        M.tank1 = GetHandle("svtank0_wingman")
        M.tank2 = GetHandle("svtank1_wingman")
        M.hov1 = GetHandle("svapc0_apc")
        M.goal = GetHandle("eggeizr15_geyser")
        M.rendezvous1 = GetTime() + 180.0
        M.rendezvous2 = GetTime() + 240.0
        M.deny_time1 = GetTime() + 300.0
        M.deny_time2 = GetTime() + 400.0
        M.check_time = GetTime() + 5.0
        --[[
			Handle misl=BuildObject("waspmsl",2,cam1);
			VECTOR_3D from_vec,to_vec;
			from_vec=GameObjectHandle::GetObj(misl)->GetOrigin();
			to_vec=GameObjectHandle::GetObj(player)->GetOrigin();
			VECTOR_3D dir=SubVectors(to_vec,from_vec);
			GameObjectHandle::GetObj(misl)->SetFrontVector(dir);
        ]]
        --[[ 
			All the units below
			start frozen
			until you go to 
			them.  
        ]]
        --[[
			scav1=GetHandle("avscav6_scavenger");
			scav2=GetHandle("avscav7_scavenger");
			scav3=GetHandle("avscav8_scavenger");
			muf1=GetHandle("avmuf0_factory");
			art1=GetHandle("avartl0_howitzer");
			tur1=GetHandle("avturr0_turrettank");
        ]]
        -- SetObjectiveName is the stock Lua alias for native SetName.
        if Valid(M.cam1) then SetObjectiveName(M.cam1, "Geyser Site") end
        if Valid(M.cam2) then SetObjectiveName(M.cam2, "NW Geyser") end
        if Valid(M.cam3) then SetObjectiveName(M.cam3, "NE Geyser") end
        if Valid(M.cam4) then SetObjectiveName(M.cam4, "Geyser Site") end
        if Valid(M.cam5) then SetObjectiveName(M.cam5, "Supply") end
        if Valid(M.cam6) then SetObjectiveName(M.cam6, "Nav Beta") end
        if Valid(M.tank1) then Goto(M.tank1, "tank_path", 0) end
        if Valid(M.tank2) then Goto(M.tank2, "tank_path", 0) end
        if Valid(M.hov1) then Goto(M.hov1, "tank_path", 0) end
        M.audmsg = AudioMessage("misn1501.wav")
        M.second_message = GetTime() + 2.0 -- was 20.0f
        M.sav_timer = GetTime() + 120.0
        M.misl_time = 40.0
        -- so that missiles always have a target
        M.scav_du_jour = M.recy
        M.start_done = true
        if Valid(M.cam6) then SetUserTarget(M.cam6) end
    end

    if IsAudioMessageDone(M.audmsg) and GetTime() > M.second_message then
        --[[
			The workers tank
			battalion will help you out. 
        ]]
        AudioMessage("misn1502.wav")
        CameraReady()
        M.camera_time = GetTime() + 8.0
        M.second_message = 99999.0
        M.camera1 = true
    end
    if M.camera1 and Valid(M.tank1) then
        -- Stock Lua retains the source's centimeter offsets.
        CameraObject(M.tank1, 800, 600, 1200, M.tank1)
    end
    if M.camera1 and (GetTime() > M.camera_time or CameraCancelled() or not Valid(M.tank1)) then
        -- PORT FIX: release a shot whose subject has disappeared. This only
        -- ends an unusable camera; the Soviet march and all timers continue.
        M.camera1 = false
        CameraFinish()
    end

    if not M.cca_here and (Distance(M.cam6, M.tank1) < 100.0 or Distance(M.cam4, M.tank1) < 100.0) then
        M.cca_here = true
        AudioMessage("misn1503.wav")
        ShowStuff()
    end
    if not M.found_group1 and GetTime() > M.rendezvous1 then
        if Valid(M.cam2) then SetUserTarget(M.cam2) end
        AudioMessage("misn1511.wav")
        M.rendezvous1 = 99999.0
    end

    if not M.found_group1 and Distance(M.cam2, M.player) < 150.0 then -- was 200.0
        --[[
			Play a wave that you
			got reinforcements
        ]]
        AudioMessage("misn1518.wav")
        M.scavcam = BuildObject("avscav", 1, "scav3here")
        BuildObject("avapc", 1, "mufhere")
        BuildObject("avturr", 1, "turhere")
        M.found_group1 = true
        ShowStuff()
        M.camera2 = true
        M.rcam1 = GetTime() + 3.0
        CameraReady()
    end
    if M.camera2 and Valid(M.scavcam) then
        CameraPath("rescue_cam1", 1000, 0, M.scavcam)
    end
    if M.camera2 and (GetTime() > M.rcam1 or CameraCancelled() or not Valid(M.scavcam)) then
        -- PORT FIX: native rescue camera ignores cancellation and checks only
        -- found_group1 when finishing. Require the active shot, honor cancel,
        -- and release a missing subject. The rescue spawns/flag and three-second
        -- normal duration are unchanged; only camera control is released sooner.
        M.camera2 = false
        M.rcam1 = 99999.0
        CameraFinish()
    end
    --[[
	if ((!found_group2) && (GetTime()>rendezvous2))
	{
		SetUserTarget(cam3);
		AudioMessage("misn1512.wav");
		rendezvous2=99999.0f;
	}
	if ((!found_group2) && (GetDistance(cam3,player)<150.0f)) // was 200.0
	{
		
		//	Play a wave that you
		//	got reinforcements
		
		AudioMessage("misn1514.wav");
		scavcam=BuildObject("avscav",1,"scav1here");
		BuildObject("avscav",1,"scav2here");
		BuildObject("avartl",1,"arthere");
		found_group2=true;
		camera3=true;
		rcam2=GetTime()+3.0f;
		CameraReady();
	}
	if (camera3)
	{
		CameraPath("rescue_cam2",1000,0,scavcam);
	}
	
	if ((found_group2) && (GetTime()>rcam2))
	{
		camera3=false;
		rcam2=99999.0f;
		CameraFinish();
	}
    ]]
    --[[
		if titan relic found
		and NOT played warning
		AudioMessage("misn1513.wav");
    ]]
    if not M.tartarus and Distance(M.player, M.tart) < 150.0 then
        M.tartarus = true
        AudioMessage("misn1513.wav")
        AudioMessage("misn1514.wav")
    end

    if GetTime() > M.sav_timer and M.savcount < 50 then -- 50 is the max in case
        local sav
        -- math.random(0, 1) preserves rand()%2's two equally likely branches;
        -- leave the engine's Lua RNG seed alone rather than reseeding per frame.
        if math.random(0, 1) == 1 then
            sav = BuildObject("hvsav", 2, "alien1")
        else
            sav = BuildObject("hvsav", 2, "alien2")
        end
        if Valid(sav) and Valid(M.scav_du_jour) then Attack(sav, M.scav_du_jour) end
        M.sav_timer = GetTime() + 240.0 -- was (rand()%5+9)*10.0f;
        M.savlist[M.savcount] = sav
        M.savcount = M.savcount + 1
    end
    --[[
		My scheduler
		All the features of the
		Dark Rein AI
		at a fraction of the CPU
		cost.
    ]]
    if GetTime() > M.check_time then
        for count = 0, M.savcount - 1 do
            local sav = M.savlist[count]
            if Valid(sav) and IsAlive(sav) and GetCurrentCommand(sav) == AiCommand.NONE then
                Goto(sav, "alien_path")
            end
        end
        M.check_time = GetTime() + 5.0
    end
    --[[
		Deny the main scrap
		fields to the 
		enemy.
    ]]
    if M.misn15b and GetTime() > M.deny_time1 then
        M.sat1 = BuildObject("hvsat", 2, "alien1")
        M.sat2 = BuildObject("hvsat", 2, "alien1")
        if Valid(M.sat1) then Goto(M.sat1, "deny1") end
        if Valid(M.sat2) then Goto(M.sat2, "deny1") end
        M.deny_time1 = 99999.0
    end
    --[[
		Deny the main scrap
		fields to the 
		enemy.
    ]]
    if M.misn15b and GetTime() > M.deny_time2 then
        M.sat1 = BuildObject("hvsat", 2, "alien2")
        M.sat2 = BuildObject("hvsat", 2, "alien2")
        if Valid(M.sat1) then Goto(M.sat1, "deny2") end
        if Valid(M.sat2) then Goto(M.sat2, "deny2") end
        M.deny_time2 = 99999.0
    end

    if not M.lost and not IsAlive(M.recy) then
        --[[
			Message:
			Without the resources,
			Titan is lost.
        ]]
        AudioMessage("misn1414.wav")
        M.lost = true
        FailMission(GetTime() + 10.0, "misn15l1.des")
    end
    if M.silocount > 1 and not M.silo_built then
        M.silo_built = true
        ShowStuff()
    end
    -- PORT FIX: native success runs after recycler failure in the same frame,
    -- so 75 scrap can overwrite a defeat. Give the explicit loss precedence;
    -- every living-recycler success still uses the original >74 threshold and
    -- ten-second delay. Silos, rescue, and Soviet arrival are not victory gates.
    if not M.lost and not M.got_dough and GetScrap(1) > 74 then
        M.got_dough = true
        -- PORT FIX: native won is never set. Record the already-earned outcome
        -- so later ShowStuff calls retain its green final objective.
        M.won = true
        ShowStuff()
        AudioMessage("misn1510.wav")
        --[[
				Congratulations
        ]]
        SucceedMission(GetTime() + 10.0, "misn15w1.des")
    end
end

function Save()
    return M
end

function Load(state)
    -- LuaMission serializes the table and restores engine handle values. Do not
    -- replay Setup/Execute, reset timers, rebuild units, or recount loaded silos.
    M = state
end
