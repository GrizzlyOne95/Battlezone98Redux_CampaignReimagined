-- Faithful misn09 DLL source port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misn09Mission.cpp.
-- Source blob: 888ee877b4b56348ddf3e9717f01aed95fc0f066.
-- Disabled C++ stays inactive at its original location; the complete verbatim
-- source/header, including serialization comments, is in References/Misn09Source/.
-- Single-player stock API only; no EXU/OpenShim/campaign helper dependency.

local function NewState()
    local state = {}
    state.start_done = false
    state.convoy_started = false
    state.camera_ready = false
    state.camera_artil = false
    state.build_new_tug = false
    state.tug_done = false
    state.objective1 = false
    state.first_warning = false
    state.second_warning = false
    state.third_warning = false
    state.player_dead = false
    state.muf_contact = false
    state.muf_moving = false
    state.post1 = false
    state.post2 = false
    state.post3 = false
    state.post4 = false
    state.guard1 = false
    state.guard2 = false
    state.turret1_set = false
    state.turret2_set = false
    state.turret3_set = false
    state.turret4_set = false
    state.get_relic = false
    state.relic_secure = false
    state.relic_seized = false
    state.relic_free = false
    state.tug_underway = false
    state.head_4_pad = false
    state.game_over = false
    state.next_shot = false
    state.player_camera_off = false
    state.next_shot_message = false
    state.cam1_on = false
    state.cam2_on = false
    state.cam3_on = false
    state.cam4_on = false
    state.cam5_on = false
    state.cam_off = false
    state.convoy_cam_ready = false
    state.convoy_cam_off = false
    state.muf_deployed = false
    state.scavs_alive = false
    state.charon_found = false
    state.charon_build = false
    state.start = false
    state.opening_vo = false
    state.muf_gobaby = false
    state.recon_artil = false
    state.base_warning = false
    state.muf_deployed_good = false
    state.ccadead = false
    state.start_camera1 = false
    state.game_over5 = false
    state.start_convoy_time = 99999.0
    state.camera_ready_time = 99999.0
    state.build_tug_time = 99999.0
    state.first_warning_time = 99999.0
    state.second_warning_time = 99999.0
    state.third_warning_time = 99999.0
    state.camera_on_time = 99999.0
    state.muf_check = 99999.0
    state.movie_time = 99999.0
    state.unit_check = 99999.0
    state.turret1_time = 99999.0
    state.turret2_time = 99999.0
    state.turret3_time = 99999.0
    state.turret4_time = 99999.0
    state.win_check = 99999.0
    state.atril_check = 99999.0
    state.player_camera_time = 99999.0
    state.next_shot_time = 99999.0
    state.cam1_time = 99999.0
    state.cam2_time = 99999.0
    state.cam3_time = 99999.0
    state.cam4_time = 99999.0
    state.cam5_time = 99999.0
    state.convoy_cam_time = 99999.0
    state.deploy_check = 99999.0
    state.charon_check = 99999.0
    state.start_time = 99999.0
    state.recon_message_time = 99999.0
    state.user = nil
    state.relic = nil
    state.nav1 = nil
    state.charon = nil
    state.avsilo = nil
    state.key_scrap = nil
    state.ccatug = nil
    state.nsdftug = nil
    state.convoy_geyser = nil
    state.cut_off_geyser = nil
    state.ccaturret1 = nil
    state.ccaturret2 = nil
    state.ccaturret3 = nil
    state.ccaturret4 = nil
    state.ccaturret5 = nil
    state.ccaturret6 = nil
    state.ccarecycle = nil
    state.ccamuf = nil
    state.ccaarmor = nil
    state.ccalaunch = nil
    state.cca1 = nil
    state.cca2 = nil
    state.cca3 = nil
    state.cca4 = nil
    state.cca5 = nil
    state.cca6 = nil
    state.cca7 = nil
    state.cca8 = nil
    state.cca9 = nil
    state.cca0 = nil
    state.scav1 = nil
    state.scav2 = nil
    state.scav3 = nil
    state.nsdfrecycle = nil
    state.nsdfmuf = nil
    state.avscav1 = nil
    state.avscav2 = nil
    state.avscav3 = nil
    state.nsdfgech1 = nil
    state.construct = nil
    state.nsdfslf = nil
    state.nsdfrig = nil
    state.tugger = nil
    state.convoy1 = nil
    state.convoy2 = nil
    state.convoy3 = nil
    state.convoy4 = nil
    state.convoy5 = nil
    state.convoy6 = nil
    state.convoy7 = nil
    state.convoy8 = nil
    state.convoy9 = nil
    state.convoy0 = nil
    state.charon_nav = nil
    state.stuff = 0
    state.x = 0
    state.y = 0
    state.scrap = 0
    state.audmsg = nil
    return state
end
local M = NewState()

-- Native null/removed objects do not satisfy proximity checks. Avoid passing
-- nil through stock Lua's overloaded GetDistance handle/path interface.
local function Distance(from, to)
    if from == nil or from == 0 or not IsValid(from) then return math.huge end
    if to == nil or to == 0 then return math.huge end
    if type(to) ~= "string" and not IsValid(to) then return math.huge end
    return GetDistance(from, to)
end

local function IsOdfBase(h, name)
    return IsValid(h) and (IsOdf(h, name) or IsOdf(h, name .. ".odf"))
end

-- Native audmsg=0 meant no audio. Lua messages are userdata or nil.
local function AudioDone(message)
    return message == nil or IsAudioMessageDone(message)
end
local function StopAudio(message)
    if message ~= nil then StopAudioMessage(message) end
end

function Start()
    M = NewState()
    --[==[ Original C++ comment (inactive):
/*
Here's where you set the values at the start.  
*/
    ]==]
    M.stuff = 0
    M.x = 950
    M.y = 3000
    M.scrap = 100
    M.start_done = false
    M.start_camera1 = false
    M.convoy_started = false
    M.player_dead = false
    M.camera_ready = false
    M.build_new_tug = false
    M.tug_done = false
    M.objective1 = false
    M.camera_artil = false
    M.first_warning = false
    M.second_warning = false
    M.third_warning = false
    M.muf_contact = false
    M.muf_moving = false
    M.post1 = false
    M.post2 = false
    M.post3 = false
    M.post4 = false
    M.guard1 = false
    M.guard2 = false
    M.turret1_set = false
    M.turret2_set = false
    M.turret3_set = false
    M.turret4_set = false
    M.get_relic = false
    M.relic_secure = false
    M.relic_seized = false
    M.relic_free = false
    M.tug_underway = false
    M.game_over = false
    M.head_4_pad = false
    M.next_shot = false
    M.player_camera_off = false
    M.next_shot_message = false
    M.cam1_on = false
    M.cam2_on = false
    M.cam3_on = false
    M.cam4_on = false
    M.cam5_on = false
    M.cam_off = false
    M.convoy_cam_ready = false
    M.convoy_cam_off = false
    M.muf_deployed = false
    M.scavs_alive = false
    M.charon_found = false
    M.charon_build = false
    M.start = false
    M.opening_vo = false
    M.muf_gobaby = false
    M.recon_artil = false
    M.base_warning = false
    M.muf_deployed_good = false
    M.ccadead = false
    M.game_over5 = false
    M.start_convoy_time = 99999.0
    M.camera_ready_time = 99999.0
    M.build_tug_time = 99999.0
    M.camera_on_time = 99999.0
    M.first_warning_time = 99999.0
    M.second_warning_time = 99999.0
    M.third_warning_time = 99999.0
    M.muf_check = 99999.0
    M.movie_time = 99999.0
    M.turret1_time = 99999.0
    M.turret2_time = 99999.0
    M.turret3_time = 99999.0
    M.turret4_time = 99999.0
    M.unit_check = 99999.0
    M.win_check = 99999.0
    M.atril_check = 99999.0
    M.player_camera_time = 99999.0
    M.next_shot_time = 99999.0
    M.cam1_time = 99999.0
    M.cam2_time = 99999.0
    M.cam3_time = 99999.0
    M.cam4_time = 99999.0
    M.cam5_time = 99999.0
    M.convoy_cam_time = 99999.0
    M.deploy_check = 99999.0
    M.charon_check = 99999.0
    M.start_time = 20.0
    M.recon_message_time = 99999.0
    M.ccatug = nil
    M.ccaturret1 = GetHandle("artil1")
    M.ccaturret2 = GetHandle("artil2")
    M.ccaturret3 = GetHandle("artil3")
    M.ccaturret4 = GetHandle("artil4")
    M.ccaturret5 = GetHandle("artil5")
    M.ccaturret6 = GetHandle("artil6")
    M.ccarecycle = GetHandle("svrecycle")
    M.avscav1 = GetHandle("scav1")
    M.avscav2 = GetHandle("scav2")
    M.avscav3 = GetHandle("scav3")
    M.nsdfrig = GetHandle("rig")
    M.nsdfslf = GetHandle("avslf")
    M.ccamuf = GetHandle("svmuf")
    M.nsdfmuf = GetHandle("avmuf")
    M.convoy_geyser = GetHandle("convoy_geyser")
    M.ccalaunch = GetHandle("launchpad")
    M.nav1 = GetHandle("cam1")
    M.charon = GetHandle("hbchar0_i76building")
    M.cut_off_geyser = GetHandle("cut_off_geyser")
    M.key_scrap = GetHandle("key_scrap")
    M.cca1 = nil
    M.cca2 = nil
    M.cca3 = nil
    M.cca4 = nil
    M.cca5 = nil
    M.cca6 = nil
    M.cca7 = nil
    M.cca8 = nil
    M.cca9 = nil
    M.cca0 = nil
    M.scav1 = nil
    M.scav2 = nil
    M.scav3 = nil
    M.nsdfgech1 = nil
    M.nsdftug = nil
    M.convoy1 = nil
    M.convoy2 = nil
    M.convoy3 = nil
    M.convoy4 = nil
    M.convoy5 = nil
    M.convoy6 = nil
    M.convoy7 = nil
    M.convoy8 = nil
    M.convoy9 = nil
    M.convoy0 = nil
    M.relic = nil
    M.tugger = nil
    M.audmsg = nil
    M.avsilo = nil
    M.charon_nav = nil
end

-- Preserve the native first-empty-slot order and ODF-only matching: there is
-- deliberately no additional team filter, dead-slot reuse, or convoy exclusion.
local trackedObjects = {
    {"cca1", "svturr"}, {"cca2", "svturr"},
    {"cca3", "svturr"}, {"cca4", "svturr"},
    {"cca5", "svfigh"}, {"cca6", "svfigh"},
    {"cca7", "svfigh"}, {"cca8", "svfigh"},
    {"cca9", "svtank"}, {"cca0", "svtank"},
    {"scav1", "svscav"}, {"scav2", "svscav"}, {"scav3", "svscav"},
    {"nsdfgech1", "avwalk"}, {"ccatug", "svhaul"}, {"avsilo", "absilo"},
}
function AddObject(h)
    for _, entry in ipairs(trackedObjects) do
        if M[entry[1]] == nil and IsOdfBase(h, entry[2]) then
            M[entry[1]] = h
            return
        end
    end
end

function Update(dt)
    --[==[ Original C++ comment (inactive):
/*
Here is where you put what happens every frame.  
*/
    ]==]
    --[==[ Original C++ comment (inactive):
// START OF SCRIPT
    ]==]
    if (M.relic_free) and (IsAlive(M.relic)) then
        M.tugger = GetTug(M.relic)
        if IsAlive(M.tugger) then
            if GetTeamNum(M.tugger) == 1 then
                M.relic_free = false
                M.relic_secure = true
            else
                M.relic_free = false
                M.relic_seized = true
                M.tugger = M.ccatug
            end
        end
    end
    if (M.relic_secure) and (not IsAlive(M.tugger)) then
        M.relic_free = true
        M.relic_secure = false
    end
    if (M.relic_seized) and (not IsAlive(M.ccatug)) then
        M.relic_free = true
        M.relic_seized = false
    end
    if IsAlive(M.relic) then
        if (IsAlive(M.ccatug)) and (M.relic_free) and (not M.tug_underway) then
            Pickup(M.ccatug, M.relic)
            M.tug_underway = true
        end
        if (M.relic_seized) and (not M.head_4_pad) then
            Dropoff(M.ccatug, "soviet_path", 1)
            M.head_4_pad = true
        end
    end
    if not IsAlive(M.ccatug) then
        M.tug_underway = false
        M.head_4_pad = false
    end
    --[==[ Original C++ comment (inactive):
/*	if (IsAlive(nsdftug))
	{
		if (HasCargo(nsdftug))
		{
			relic_free = false;
			relic_secure = true;
		}
		else
		{
			if (!relic_seized)
			{
				relic_free = true;
				relic_secure = false;
			}
		}
	}

*/
    ]==]
    M.user = GetPlayerHandle()
    --[==[ Original C++ comment (inactive):
//assigns the player a handle every frame
    ]==]
    --[==[ Original C++ comment (inactive):
//	if ((start_time < Get_Time()) && (!start))
    ]==]
    --[==[ Original C++ comment (inactive):
//	{
    ]==]
    --[==[ Original C++ comment (inactive):
//		start = true;
    ]==]
    --[==[ Original C++ comment (inactive):
//	}
    ]==]
    if not M.start_done then
        CameraReady()
        Defend(M.nsdfmuf)
        SetScrap(2, 40)
        SetPilot(2, 40)
        Follow(M.nsdfrig, M.nsdfmuf, 1)
        Follow(M.avscav1, M.nsdfmuf, 1)
        Follow(M.avscav2, M.nsdfmuf, 1)
        Follow(M.avscav3, M.nsdfmuf, 1)
        Follow(M.nsdfslf, M.nsdfrig, 0)
        Defend(M.ccaturret1)
        Defend(M.ccaturret2)
        Defend(M.ccaturret3)
        Defend(M.ccaturret4)
        Defend(M.ccaturret5)
        Defend(M.ccaturret6)
        --[==[ Original C++ comment (inactive):
//		start_convoy_time = Get_Time() + 900.0f;		
        ]==]
        M.camera_ready_time = GetTime() + 6.0
        M.muf_check = GetTime() + 3.0
        M.first_warning_time = GetTime() + 700.0
        M.second_warning_time = GetTime() + 1000.0
        M.third_warning_time = GetTime() + 1300.0
        --[==[ Original C++ comment (inactive):
// was 900.0f
        ]==]
        M.unit_check = GetTime() + 1360.0
        M.atril_check = GetTime() + 15.0
        M.player_camera_time = GetTime() + 11.0
        M.deploy_check = GetTime() + 6.0
        M.charon_check = GetTime() + 30.0
        M.next_shot_time = GetTime() + 22.0
        if M.nav1 ~= nil then
            SetObjectiveName(M.nav1, "Choke Point")
        end
        M.start_camera1 = true
        M.start_done = true
    end
    if M.start_camera1 then
        CameraPath("camera_circle", 375, 750, M.key_scrap)
    end
    --[==[ Original C++ comment (inactive):
/*
	if ((!next_shot_message) && ((player_camera_time < Get_Time()) || (CameraCancelled())))
	{
		CameraPath("launch_camera_path", 7000, 1150, ccalaunch);

		if (x > 6000.0f)
		{
			x = x - 150;
		}
		else
		{
			x = x + 50;
		}
		y = y - 20;
*/
    ]==]
    --[==[ Original C++ comment (inactive):
/*		next_shot = true;
	}

	if ((!next_shot_message) && (IsAudioMessageDone(audmsg)))
	{
		audmsg = AudioMessage("misn0912.wav");
		next_shot_time = Get_Time() + 6.0f;
		next_shot_message = true;
	}

	if ((next_shot_message) && (!player_camera_off)) 
	{
		CameraPath("choke_cam_path", 375, 450, nav1);
	}
*/
    ]==]
    if (not M.player_camera_off) and ((M.next_shot_time < GetTime()) or (CameraCancelled())) then
        CameraFinish()
        M.start_camera1 = false
        M.player_camera_off = true
    end
    if CameraCancelled() then
        StopAudio(M.audmsg)
    end
    --[==[ Original C++ comment (inactive):
// this starts the opening voice-over
    ]==]
    if ((M.camera_ready_time < GetTime()) and (not M.opening_vo)) then
        M.audmsg = AudioMessage("misn0900.wav")
        --[==[ Original C++ comment (inactive):
//starts opening V.O.5
        ]==]
        ClearObjectives()
        AddObjective("misn0900.otf", "white")
        M.opening_vo = true
    end
    if (M.opening_vo) and (not M.muf_gobaby) and (AudioDone(M.audmsg)) then
        Goto(M.nsdfmuf, "return_path", 1)
        M.muf_gobaby = true
    end
    --[==[ Original C++ comment (inactive):
// this tells the muf to stop when the player gets close & plays the artillery message
    ]==]
    if (M.muf_gobaby) and (M.muf_check < GetTime()) and (not M.muf_contact) then
        M.muf_check = GetTime() + 1.0
        if Distance(M.user, M.nsdfmuf) < 70.0 then
            Stop(M.nsdfmuf, 0)
            Stop(M.nsdfslf, 0)
            Defend(M.nsdfrig, 0)
            SetScrap(1, 20)
            SetPilot(1, 7)
            AudioMessage("misn0905.wav")
            --[==[ Original C++ comment (inactive):
// message from muf "we took a beating out there"
            ]==]
            M.movie_time = GetTime() + 7.0
            M.muf_contact = true
        end
    end
    if (not M.objective1) and (M.atril_check < GetTime()) then
        M.atril_check = GetTime() + 15.0
        if IsAlive(M.ccaturret1) then
            Defend(M.ccaturret1)
        end
        if IsAlive(M.ccaturret2) then
            Defend(M.ccaturret2)
        end
        if IsAlive(M.ccaturret3) then
            Defend(M.ccaturret3)
        end
        if IsAlive(M.ccaturret4) then
            Defend(M.ccaturret4)
        end
        if IsAlive(M.ccaturret5) then
            Defend(M.ccaturret5)
        end
        if IsAlive(M.ccaturret6) then
            Defend(M.ccaturret6)
        end
    end
    --[==[ Original C++ comment (inactive):
// this starts the muf towards the player
    ]==]
    --[==[ Original C++ comment (inactive):
/*	if ((player_camera_off) && (!muf_moving))
	{
		Goto(nsdfmuf, "return_path", 1);
		Follow(nsdfrig, nsdfmuf, 1);
		Follow(avscav1, nsdfmuf, 1);
		Follow(avscav2, nsdfmuf, 1);
		Follow(avscav3, nsdfmuf, 1);
		Follow(nsdfslf, nsdfrig, 1);
		muf_moving = true;
	}
*/
    ]==]
    --[==[ Original C++ comment (inactive):
// this checks to see if the muf is deployed
    ]==]
    if (M.deploy_check < GetTime()) and (not M.muf_deployed) then
        M.deploy_check = GetTime() + 2.0
        if IsAlive(M.nsdfmuf) then
            local test = IsDeployed(M.nsdfmuf)
            if test then
                M.muf_deployed = true
            end
        end
    end
    if ((M.muf_deployed) or (IsAlive(M.avsilo))) and (not M.scavs_alive) then
        Stop(M.avscav1, 0)
        Stop(M.avscav2, 0)
        Stop(M.avscav3, 0)
        M.scavs_alive = true
    end
    --[==[ Original C++ comment (inactive):
// This turns the camera over the artilery units on/off ////////
    ]==]
    if IsAlive(M.ccaturret6) then
        if (M.muf_contact) and (M.movie_time < GetTime()) and (not M.camera_ready) then
            CameraReady()
            M.cam5_time = GetTime() + 7.0
            M.camera_ready = true
        end
        if (M.camera_ready) and (not M.cam_off) then
            CameraPath("camera_path", M.x, 300, M.ccaturret6)
            M.x = M.x + 90
        end
        if (M.camera_ready) and (M.cam5_time < GetTime()) and (not M.cam_off) then
            CameraFinish()
            ClearObjectives()
            AddObjective("misn0900.otf", "green")
            AddObjective("misn0901.otf", "white")
            Stop(M.nsdfrig, 0)
            SetAIP("misn09.aip")
            M.recon_message_time = GetTime() + 60.0
            M.cam_off = true
        end
    end
    if (M.recon_message_time < GetTime()) and (not M.recon_artil) then
        M.recon_message_time = GetTime() + 1.0
        AudioMessage("misn0913.wav")
        M.recon_artil = true
    end
    if (M.recon_message_time < GetTime()) and (not M.base_warning) then
        M.recon_message_time = GetTime() + 2.0
        if ((IsAlive(M.nav1)) and (Distance(M.user, M.nav1) < 100.0)) or ((IsAlive(M.cca5)) and (Distance(M.user, M.cca5) < 400.0)) or ((IsAlive(M.cca6)) and (Distance(M.user, M.cca6) < 400.0)) then
            AudioMessage("misn0914.wav")
            M.base_warning = true
        end
    end
    --[==[ Original C++ comment (inactive):
/*	
	if ((camera_ready) && (!cam2_on))	
	{
		CameraObject(ccaturret6, 650, 650, 650, ccaturret6);
		if (!cam1_on)
		{
			cam1_time = Get_Time() + 2.0f;
			cam1_on = true;
		}
	}

	if ((cam1_on) && (cam1_time < Get_Time()) && (!cam3_on))
	{
		CameraObject(ccaturret5, -650, 350, 300, ccaturret5);
		if (!cam2_on)
		{
			cam2_time = Get_Time() + 2.0f;
			cam2_on = true;
		}
	}

	if ((cam2_on) && (cam2_time < Get_Time()) && (!cam4_on))
	{
		CameraObject(ccaturret4, 1000, 1350, 600, ccaturret4);
		if (!cam3_on)
		{
			cam3_time = Get_Time() + 2.0f;
			cam3_on = true;
		}
	}

	if ((cam3_on) && (cam3_time < Get_Time()) && (!cam5_on))
	{
		CameraObject(ccaturret3, -90, -250, 1000, ccaturret3);
		if (!cam4_on)
		{
			cam4_time = Get_Time() + 2.0f;
			cam4_on = true;
		}
	}

	if ((cam4_on) && (cam4_time < Get_Time()) && (!cam_off))
	{
		CameraObject(ccaturret2, 500, 900, 90, ccaturret2);
		if (!cam5_on)
		{
			cam5_time = Get_Time() + 2.0f;
			cam5_on = true;
		}
	}

	if ((cam5_on) && (cam5_time < Get_Time()) && (!cam_off))		
	{															
		CameraFinish();
		ClearObjectives();
		AddObjective("misn0900.otf", GREEN);
		AddObjective("misn0901.otf", WHITE);
		cam_off = true;									
	}

*/
    ]==]
    --[==[ Original C++ comment (inactive):
// end of camera script for artiliery units ////////////////////
    ]==]
    --[==[ Original C++ comment (inactive):
// this is going to set up a fortification of turrets
    ]==]
    if (IsAlive(M.cca1)) and (not M.post1) then
        Goto(M.cca1, "post1", 1)
        M.turret1_time = GetTime() + 10.0
        M.post1 = true
    end
    if (M.post1) and (M.turret1_time < GetTime()) then
        M.turret1_time = GetTime() + 15.0
        if IsAlive(M.cca1) then
            Defend(M.cca1)
        end
    end
    if (IsAlive(M.cca2)) and (not M.post2) then
        Goto(M.cca2, "post2", 1)
        M.turret2_time = GetTime() + 10.0
        M.post2 = true
    end
    if (M.post2) and (M.turret2_time < GetTime()) then
        M.turret2_time = GetTime() + 15.0
        if IsAlive(M.cca2) then
            Defend(M.cca2)
        end
    end
    if (IsAlive(M.cca3)) and (not M.post3) then
        Goto(M.cca3, "post3", 1)
        M.turret3_time = GetTime() + 10.0
        -- PORT FIX: Source set post1 here, so post3 stayed false, Goto repeated
        -- every frame, and the ten-second defense timer never ran. Set post3
        -- to latch the same post3 move once, matching the other three posts.
        -- No spawn, objective, convoy, or outcome gate depends on this flag.
        M.post3 = true
    end
    if (M.post3) and (M.turret3_time < GetTime()) then
        M.turret3_time = GetTime() + 15.0
        if IsAlive(M.cca3) then
            Defend(M.cca3)
        end
    end
    if (IsAlive(M.cca4)) and (not M.post4) then
        Goto(M.cca4, "post4", 1)
        M.turret4_time = GetTime() + 10.0
        M.post4 = true
    end
    if (M.post4) and (M.turret4_time < GetTime()) then
        M.turret4_time = GetTime() + 15.0
        if IsAlive(M.cca4) then
            Defend(M.cca4)
        end
    end
    --[==[ Original C++ comment (inactive):
// this is to insure that the soviets keep trying to get the database relic	
    ]==]
    --[==[ Original C++ comment (inactive):
/*																			
	if ((convoy_started) && (!IsAlive (ccatug)) && (IsAlive(ccarecycle)) && (!build_new_tug))	
	{																		
		build_tug_time = Get_Time () + 60.0f;// was 60 seconds
		tug_done = false;
		build_new_tug = true;												
	}																		
																			
	if ((build_new_tug) && (build_tug_time < Get_Time()) && (!tug_done))	
	{																		
		ccatug = BuildObject("svhaul", 2, ccarecycle);
//		convoy_started = false; // should change this to somthing else
		build_new_tug = false;
		tug_done = true;
	}																								
*/
    ]==]
    --[==[ Original C++ comment (inactive):
// if player destroys all the cca turrets///////////////////////////////////////////////
    ]==]
    if (not IsAlive(M.ccaturret1)) and (not IsAlive(M.ccaturret2)) and (not IsAlive(M.ccaturret3)) and (not IsAlive(M.ccaturret4)) and (not IsAlive(M.ccaturret5)) and (not IsAlive(M.ccaturret6)) and (not M.objective1) then
        AudioMessage("misn0904.wav")
        --[==[ Original C++ comment (inactive):
//congradulations you killed the turrets
        ]==]
        Stop(M.avscav1, 0)
        Stop(M.avscav2, 0)
        Stop(M.avscav3, 0)
        ClearObjectives()
        AddObjective("misn0901.otf", "green")
        AddObjective("misn0902.otf", "white")
        AddObjective("misn0903.otf", "white")
        if not M.third_warning then
            SetAIP("misn09a.aip")
            --[==[ Original C++ comment (inactive):
// causes the soviets to get more aggresive
            ]==]
        end
        M.objective1 = true
    end
    --[==[ Original C++ comment (inactive):
// this is the general warning of the approaching convoy ////////////////////////////////
    ]==]
    if (not M.first_warning) and (M.first_warning_time < GetTime()) then
        AudioMessage("misn0901.wav")
        --[==[ Original C++ comment (inactive):
// the soviets convey will be here in less than 10 minutes
        ]==]
        M.first_warning = true
    end
    if (not M.second_warning) and (M.second_warning_time < GetTime()) then
        AudioMessage("misn0902.wav")
        --[==[ Original C++ comment (inactive):
// the soviets convey will be here in less than 5 minutes
        ]==]
        M.second_warning = true
    end
    if (not M.third_warning) and (M.third_warning_time < GetTime()) then
        M.third_warning_time = GetTime() + 11.0
        if Distance(M.user, M.convoy_geyser) > 500.0 then
            M.relic = BuildObject("obdata", 3, M.convoy_geyser)
            M.ccatug = BuildObject("svhaul", 2, "spawn1")
            M.convoy1 = BuildObject("svfigh", 2, "spawn2")
            M.convoy2 = BuildObject("svfigh", 2, "spawn2")
            M.convoy3 = BuildObject("svfigh", 2, "spawn2")
            M.convoy4 = BuildObject("svfigh", 2, "spawn3")
            M.convoy5 = BuildObject("svtank", 2, "spawn3")
            M.convoy6 = BuildObject("svtank", 2, "spawn3")
            M.convoy7 = BuildObject("svtank", 2, "spawn4")
            M.convoy8 = BuildObject("svtank", 2, "spawn4")
            M.convoy9 = BuildObject("svapc", 2, "spawn4")
            M.convoy0 = BuildObject("svapc", 2, "spawn4")
            Defend(M.convoy1)
            Defend(M.convoy2)
            Defend(M.convoy3)
            Defend(M.convoy4)
            Defend(M.convoy5)
            Defend(M.convoy6)
            Defend(M.convoy7)
            Defend(M.convoy8)
            Defend(M.convoy9)
            Defend(M.convoy0)
            --[==[ Original C++ comment (inactive):
//			Pickup(ccatug, relic); // should do automatically
            ]==]
            if not M.objective1 then
                ClearObjectives()
                AddObjective("misn0901.otf", "red")
                AddObjective("misn0902.otf", "white")
                AddObjective("misn0903.otf", "white")
            end
            M.win_check = GetTime() + 5.0
            SetAIP("misn09b.aip")
            --[==[ Original C++ comment (inactive):
// causes the soviets to get more reserved
            ]==]
            M.relic_free = true
            M.third_warning = true
        end
    end
    --[==[ Original C++ comment (inactive):
// this starts the convoy towards the launch pad ////////////////////////////////////
    ]==]
    if (M.third_warning) and (M.relic_seized) and (not M.convoy_started) then
        SetObjectiveOn(M.relic)
        SetObjectiveName(M.relic, "Alien Relic")
        Goto(M.ccatug, "soviet_path", 1)
        Follow(M.convoy1, M.ccatug)
        Follow(M.convoy2, M.ccatug)
        Follow(M.convoy3, M.ccatug)
        Follow(M.convoy4, M.ccatug)
        Follow(M.convoy5, M.ccatug)
        Follow(M.convoy6, M.ccatug)
        Follow(M.convoy7, M.ccatug)
        Follow(M.convoy8, M.ccatug)
        Follow(M.convoy9, M.ccatug)
        Follow(M.convoy0, M.ccatug)
        M.convoy_cam_time = GetTime() + 7.0
        M.convoy_started = true
    end
    if (M.convoy_started) and (not M.convoy_cam_ready) and (M.convoy_cam_time < GetTime()) then
        AudioMessage("misn0903.wav")
        --[==[ Original C++ comment (inactive):
// the soviets convey is within radar range "I'm picking up the soviet convoy"
        ]==]
        CameraReady()
        M.convoy_cam_time = GetTime() + 18.0
        M.convoy_cam_ready = true
    end
    if (M.convoy_cam_ready) and (not M.convoy_cam_off) then
        CameraPath("convoy_cam_path", M.y, 1150, M.ccatug)
        M.y = M.y - 10
    end
    -- PORT FIX: Source used the CameraCancelled function address without ().
    -- A function address is always true, ending this shot on its first frame.
    -- Call the predicate so the existing 18-second duration/cancel rule works.
    -- Camera completion is not a mission progression or outcome gate.
    if (M.convoy_cam_ready) and (not M.convoy_cam_off) and ((M.convoy_cam_time < GetTime()) or (CameraCancelled())) then
        CameraFinish()
        M.convoy_cam_off = true
    end
    --[==[ Original C++ comment (inactive):
// this is the charon code
    ]==]
    if (IsAlive(M.charon)) and (not M.charon_found) then
        if M.charon_check < GetTime() then
            M.charon_check = GetTime() + 2.0
            if Distance(M.user, M.charon) < 70.0 then
                AudioMessage("misn0915.wav")
                --[==[ Original C++ comment (inactive):
// told to check out the charon
                ]==]
                M.charon_found = true
            end
        end
    end
    if (M.charon_found) and (IsInfo("hbchar") == true) and (not M.charon_build) then
        AudioMessage("misn0916.wav")
        --[==[ Original C++ comment (inactive):
// well done, we'll drop a nav camera here to come back to this, this looks like a good spot to go after artils
        ]==]
        M.charon_nav = BuildObject("apcamr", 1, "charon_spawn")
        if M.charon_nav ~= nil then
            SetObjectiveName(M.charon_nav, "Alien Relic")
        end
        M.charon_build = true
    end
    --[==[ Original C++ comment (inactive):
// this is to check and see if the muf is deployed correctly
    ]==]
    if (M.objective1) or (M.third_warning) then
        if (not M.muf_deployed_good) and (M.deploy_check < GetTime()) then
            M.deploy_check = GetTime() + 2.0
            if IsAlive(M.nsdfmuf) then
                local test1 = IsDeployed(M.nsdfmuf)
                -- PORT FIX: Removed the source's stray semicolon after this if.
                -- It made the following objective update unconditional for a
                -- living factory. Require the already-authored deployed/400m
                -- check. muf_deployed_good only latches this display update;
                -- no convoy timing, relic logic, or outcome uses this flag.
                if (test1) and (Distance(M.nsdfmuf, M.convoy_geyser) < 400.0) then
                    if M.objective1 then
                        ClearObjectives()
                        AddObjective("misn0901.otf", "green")
                        AddObjective("misn0902.otf", "green")
                        AddObjective("misn0903.otf", "white")
                        M.muf_deployed_good = true
                    else
                        ClearObjectives()
                        AddObjective("misn0901.otf", "red")
                        AddObjective("misn0902.otf", "green")
                        AddObjective("misn0903.otf", "white")
                        M.muf_deployed_good = true
                    end
                end
            end
        end
    end
    if (not IsAlive(M.ccarecycle)) and (not IsAlive(M.ccamuf)) and (not M.ccadead) then
        AudioMessage("misn0908.wav")
        --[==[ Original C++ comment (inactive):
// you've cleared the area of the enemy well done
        ]==]
        M.ccadead = true
    end
    --[==[ Original C++ comment (inactive):
// end of general's warings /////////////////////////////////////////////////////////////
    ]==]
    --[==[ Original C++ comment (inactive):
// win/victory conditions  
    ]==]
    if (M.scavs_alive) and (not IsAlive(M.avscav1)) and (not IsAlive(M.avscav2)) and (not IsAlive(M.avscav3)) and (not M.game_over) then
        if (not M.objective1) and (not M.first_warning) then
            M.scrap = GetScrap(1)
            if M.scrap < 10 then
                FailMission(GetTime() + 6.0, "misn09f4.des")
                M.game_over = true
            end
        end
    end
    if (M.convoy_started) and (not IsAlive(M.relic)) and (not M.game_over) then
        AudioMessage("misn0906.wav")
        --[==[ Original C++ comment (inactive):
// the relic has been destroyed commander
        ]==]
        FailMission(GetTime() + 15.0, "misn09f1.des")
        M.game_over = true
    end
    if (M.relic_seized) and (IsAlive(M.ccalaunch)) and (Distance(M.ccatug, M.ccalaunch) < 100.0) and (not M.game_over) then
        AudioMessage("misn0907.wav")
        --[==[ Original C++ comment (inactive):
// the tug has reached the launch pad
        ]==]
        FailMission(GetTime() + 15.0, "misn09f2.des")
        M.game_over = true
    end
    if (M.convoy_started) and (M.unit_check < GetTime()) and (not M.game_over5) then
        M.unit_check = GetTime() + 10.0
        M.stuff = CountUnitsNearObject(M.convoy_geyser, 5000.0, 2, nil)
        if M.stuff == 0 then
            AudioMessage("misn0908.wav")
            --[==[ Original C++ comment (inactive):
// you've cleared the area of the enemy well done
            ]==]
            --[==[ Original C++ comment (inactive):
//			SucceedMission(Get_Time() + 15.0f, "misn09w1.des");
            ]==]
            M.game_over5 = true
        end
    end
    if (IsAlive(M.relic)) and (not M.relic_seized) and (M.win_check < GetTime()) and (not M.game_over) then
        M.win_check = GetTime() + 2.0
        if (IsAlive(M.nsdfmuf)) and (Distance(M.relic, M.nsdfmuf) < 100.0) then
            AudioMessage("misn0909.wav")
            --[==[ Original C++ comment (inactive):
// you've won
            ]==]
            SucceedMission(GetTime() + 15.0, "misn09w1.des")
            M.game_over = true
        end
    end
    if (not IsAlive(M.nsdfmuf)) and (not M.game_over) then
        AudioMessage("misn0911.wav")
        --[==[ Original C++ comment (inactive):
// you've lost your muf
        ]==]
        FailMission(GetTime() + 15.0, "misn09f3.des")
        M.game_over = true
    end
    if (not IsAlive(M.ccalaunch)) and (not M.game_over) then
        AudioMessage("misn0918.wav")
        --[==[ Original C++ comment (inactive):
// you've destroyed the launchpad
        ]==]
        FailMission(GetTime() + 15.0)
        M.game_over = true
    end
    --[==[ Original C++ comment (inactive):
// END OF SCRIPT
    ]==]
end

-- BZR serializes this table's primitive/game types and restores object handles.
-- Load must not run Setup/Start or replay any spawns, commands, or cameras.
function Save()
    return M
end
function Load(state)
    if state ~= nil then M = state end
end
