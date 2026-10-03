-- misns2: faithful BZ1 DLL port for stock Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misns2Mission.cpp
-- Source blob: 4b5fbd742130d38863281fb790edca869f4cc86d
-- Original commented-out C++ remains disabled at its source locations.
-- Complete native source and serialization are in References/Misns2Source/.
-- Single-player; requires the stock misns2 map labels, paths and mission assets.
-- No EXU/OpenShim, community mission or alternate Lua behavior is required.

local M

local function NewState()
    local state = {
-- All original bool save fields, including dormant state.
        cintimeset = false,
        missionstart = false,
        missionwon = false,
        nicetry = false,
        missionfail = false,
        wave1gone = false,
        wave2gone = false,
        wave3gone = false,
        wave4gone = false,
        wave5gone = false,
        bdplatoonspawned = false,
        navpoint1reached = false,
        navpoint2reached = false,
        navpoint3reached = false,
        navpoint4reached = false,
        navpoint5reached = false,
        sneaktimeset = false,
        camnet1found = false,
        camnet2found = false,
        navpoint6reached = false,
        navpoint7reached = false,
        navpoint8reached = false,
        artwarning = false,
        patrolsent = false,
        playerfound = false,
        platooncamdone = false,
        t1arrive = false,
        t2arrive = false,
        t3arrive = false,
        newobjective = false,
        surrender = false,
        cam1done = false,
        cam2done = false,
        cam3done = false,
        cam4done = false,
        openingcindone = false,
        bdcindone = false,
-- All original float save fields, including dormant state.
        wave1start = 99999.0,
        platooncam = 99999.0,
        sneaktime = 99999.0,
        alerttime = 99999.0,
        cintime = 99999.0,
        cam1t = 99999.0,
        cam2t = 99999.0,
        cam3t = 99999.0,
        cam4t = 99999.0,
-- All original Handle save fields, including dormant state.
        player = nil,
        lu = nil,
        e1a = nil,
        e1b = nil,
        e2a = nil,
        e2b = nil,
        e3a = nil,
        e3b = nil,
        t1 = nil,
        t2 = nil,
        t3 = nil,
        bd1 = nil,
        bd2 = nil,
        bd3 = nil,
        bd4 = nil,
        bd5 = nil,
        bd6 = nil,
        bd7 = nil,
        bd8 = nil,
        bd9 = nil,
        bd10 = nil,
        bd11 = nil,
        bd12 = nil,
        bd13 = nil,
        bd14 = nil,
        bd15 = nil,
        bd16 = nil,
        bd17 = nil,
        bd18 = nil,
        bd19 = nil,
        bd20 = nil,
        bd21 = nil,
        bd22 = nil,
        bd23 = nil,
        bd24 = nil,
        bd25 = nil,
        bd26 = nil,
        bd27 = nil,
        bd100 = nil,
        bd101 = nil,
        bd102 = nil,
        bd103 = nil,
        bd104 = nil,
        bd105 = nil,
        bd106 = nil,
        bd107 = nil,
        bd108 = nil,
        bd109 = nil,
        bd110 = nil,
        dummy = nil,
        bdcam1 = nil,
        bdcam2 = nil,
        bdcam3 = nil,
        bdcam4 = nil,
        bdcam5 = nil,
        bdcam6 = nil,
        bdcam7 = nil,
        bdcam8 = nil,
        bdcam9 = nil,
        bdcam10 = nil,
        bdcam11 = nil,
        bdcam12 = nil,
        bdcam13 = nil,
        bdcam14 = nil,
        launchpad = nil,
        enemy1 = nil,
        enemy2 = nil,
        enemy3 = nil,
        cutoff = nil,
        cam1 = nil,
        nav1 = nil,
        nav2 = nil,
        nav3 = nil,
        nav4 = nil,
        nav5 = nil,
        nav6 = nil,
        nav7 = nil,
        nav8 = nil,
        nav9 = nil,
        nav10 = nil,
        nav11 = nil,
        nav12 = nil,
        nav13 = nil,
        nav14 = nil,
        nav1route = nil,
        navmine = nil,
        cutoff1 = nil,
        cutoff2 = nil,
        cutoff3 = nil,
        cutoff4 = nil,
        cutoff5 = nil,
        cutoff6 = nil,
        pat1 = nil,
        pat2 = nil,
        one = nil,
        two = nil,
        three = nil,
        four = nil,
        five = nil,
        six = nil,
        seven = nil,
        eight = nil,
        nine = nil,
        ten = nil,
-- All original int save fields, including dormant state.
        audmsg = 0,
        aud1 = 0,
        aud2 = 0,
        aud3 = 0,
        aud4 = 0,
        aud10 = 0,
        aud51 = 0,
        aud52 = 0,
        aud50 = 0,
-- Lua-only latch: the engine outcome must only be scheduled once.
        outcomeSent = false,
    }
    return state
end

local function Setup()
--[==[/*
	Here's where you
	set the values
	at the start.  
	*/]==]
    M.player = nil
    M.lu = nil
    M.aud50 = 0
    M.aud51 = 0
    M.aud52 = 0
    M.e1a = nil
    M.e1b = nil
    M.e2a = nil
    M.e2b = nil
    M.e3a = nil
    M.e3b = nil
    M.t1 = nil
    M.t2 = nil
    M.t3 = nil
    M.bd1 = nil
    M.bd2 = nil
    M.bd3 = nil
    M.bd4 = nil
    M.bd5 = nil
    M.bd6 = nil
    M.bd7 = nil
    M.bd8 = nil
    M.bd9 = nil
    M.bd10 = nil
    M.bd11 = nil
    M.bd12 = nil
    M.bd13 = nil
    M.bd14 = nil
    M.bd15 = nil
    M.bd16 = nil
    M.bd17 = nil
    M.bd18 = nil
    M.bd19 = nil
    M.bd20 = nil
    M.bd21 = nil
    M.bd22 = nil
    M.bd23 = nil
    M.bd24 = nil
    M.bd25 = nil
    M.bd26 = nil
    M.bd27 = nil
    M.bd100 = nil
    M.bd101 = nil
    M.bd102 = nil
    M.bd103 = nil
    M.bd104 = nil
    M.bd105 = nil
    M.bd106 = nil
    M.bd107 = nil
    M.bd108 = nil
    M.bd109 = nil
    M.bd110 = nil
    M.aud10 = 0
    M.dummy = nil
    M.bdcam1 = nil
    M.bdcam2 = nil
    M.bdcam3 = nil
    M.bdcam4 = nil
    M.bdcam5 = nil
    M.bdcam6 = nil
    M.bdcam7 = nil
    M.bdcam8 = nil
    M.bdcam9 = nil
    M.bdcam10 = nil
    M.bdcam11 = nil
    M.bdcam12 = nil
    M.bdcam13 = nil
    M.bdcam14 = nil
    M.launchpad = nil
    M.enemy1 = nil
    M.enemy2 = nil
    M.enemy3 = nil
    M.cutoff = nil
    M.nav1 = nil
    M.nav2 = nil
    M.nav3 = nil
    M.nav4 = nil
    M.nav5 = nil
    M.nav6 = nil
    M.nav7 = nil
    M.nav8 = nil
    M.nav9 = nil
    M.navmine = nil
    M.nav10 = nil
    M.nav11 = nil
    M.nav12 = nil
    M.nav13 = nil
    M.nav14 = nil
    M.nav1route = nil
    M.cutoff1 = nil
    M.cutoff2 = nil
    M.cutoff3 = nil
    M.cutoff4 = nil
    M.cutoff5 = nil
    M.cutoff6 = nil
    M.aud1 = 0
    M.pat1 = nil
    M.pat2 = nil
    M.one = nil
    M.two = nil
    M.three = nil
    M.four = nil
    M.five = nil
    M.six = nil
    M.seven = nil
    M.eight = nil
    M.nine = nil
    M.ten = nil
    M.missionstart = false
    M.missionwon = false
    M.missionfail = false
    M.patrolsent = false
    M.playerfound = false
    M.sneaktimeset = false
    M.wave1gone = false
    M.wave2gone = false
    M.wave3gone = false
    M.wave4gone = false
    M.wave5gone = false
    M.surrender = false
    M.openingcindone = false
    M.cam1 = nil
    M.bdcindone = false
    M.aud2 = 0
    M.aud3 = 0
    M.aud4 = 0
    M.camnet1found = false
    M.camnet2found = false
    M.nicetry = false
    M.artwarning = false
    M.bdplatoonspawned = false
    M.navpoint1reached = false
    M.navpoint2reached = false
    M.navpoint3reached = false
    M.navpoint4reached = false
    M.navpoint5reached = false
    M.navpoint6reached = false
    M.navpoint7reached = false
    M.navpoint8reached = false
    M.platooncamdone = false
    M.cam1done = false
    M.cam2done = false
    M.cam3done = false
    M.cam4done = false
    M.t1arrive = false
    M.t2arrive = false
    M.t3arrive = false
    M.newobjective = false
    M.cintimeset = false
    M.cintime = 999999999.0
    M.wave1start = 99999999.0
    M.platooncam = 99999999.0
    M.sneaktime = 9999999999.0
    M.alerttime = 99999999999.0
    M.cam1t = 99999999999.0
    M.cam2t = 99999999999.0
    M.cam3t = 99999999999.0
    M.cam4t = 99999999999.0
end

M = NewState()
Setup()

-- PORT SAFETY: nil/removed native handles are not a location. Return an
-- unreachable distance, so missing craft cannot accidentally trigger ambushes
-- or arrivals. Every valid-object distance and all source thresholds are intact.
local function Distance(from, to)
    if from == nil or from == 0 or not IsValid(from) then return math.huge end
    if to == nil or to == 0 then return math.huge end
    if type(to) ~= "string" and not IsValid(to) then return math.huge end
    return GetDistance(from, to)
end

local function NearestEnemy(h)
    if h == nil or h == 0 or not IsValid(h) then return nil end
    return GetNearestEnemy(h)
end

local function MarkObjective(h)
    if h ~= nil and h ~= 0 and IsValid(h) then SetObjectiveOn(h) end
end

function Start()
    M = NewState()
    Setup()
end

-- The source AddObject(Handle) callback is empty; spawns are tracked in Execute.
function AddObject(h)
end

function Update(dt)
--[==[/*
		Here is where you 
		put what happens 
		every frame.  
	*/]==]
    if (M.missionstart == false) then
        M.aud1 = AudioMessage("misns200.wav")
--[==[//AudioMessage ("misns202.wav");]==]
        M.launchpad = GetHandle("sblpad59_i76building")
        M.player = GetHandle("svtank0_wingman")
        M.lu = GetHandle("svfigh2_wingman")
        M.nav1route = GetHandle("apcamr5_camerapod")
--[==[//navmine = GetHandle("navmine");]==]
        M.e1a = GetHandle("svfigh3_wingman")
        M.e2b = GetHandle("svfigh5_wingman")
        M.e3a = GetHandle("svfigh6_wingman")
        M.e2a = GetHandle("svtank5_wingman")
        M.e1b = GetHandle("svtank4_wingman")
        M.e3b = GetHandle("svtank12_wingman")
        M.t1 = GetHandle("svapc0_apc")
        M.t2 = GetHandle("svapc1_apc")
        M.t3 = GetHandle("svapc2_apc")
        M.wave1start = GetTime() + 10.0
        M.missionstart = true
        AddObjective("misns201.otf", "white")
        AddObjective("misns202.otf", "white")
        AddObjective("misns203.otf", "white")
        CameraReady()
        M.cam1 = GetHandle("cam1")
        M.cam1t = GetTime() + 9.0
        M.cam2t = GetTime() + 9.01
        M.cam3t = GetTime() + 24.0
        M.cam4t = GetTime() + 34.0
-- PORT SAFETY: native GetObj(cam1)->SetName dereferenced a missing label.
-- Skip only that invalid-object call; a valid Launch Pad retains its name.
        if IsValid(M.cam1) then SetObjectiveName(M.cam1, "Launch Pad") end
    end
    if (M.openingcindone == false) then
        CameraPath("cinpath1", 500, 200, M.t1)
        if ((IsAudioMessageDone(M.aud1)) or (CameraCancelled())) then
            M.openingcindone = true
            CameraFinish()
            StopAudioMessage(M.aud1)
            AudioMessage("misns202.wav")
        end
    end
--[==[/*if
		(
		(cam1t > GetTime()) && (cam1done == false)
		)
	{
		CameraPath("cinpath1", 500, 800, t1);
	}
	if
		(
		(cam2t < GetTime()) && (cam2done == false)
		)
	{
		CameraPath("cinpath2", 600, 7000, nav1route);
		cam1done = true;
	}
	if
		(
		(cam3t < GetTime()) && (cam3done == false)
		)
	{
		CameraPath("cinpath4", 400, 4000, launchpad);
		cam2done = true;
	}
	if
		(
		(cam4t < GetTime()) && (cam4done == false)
		)
	{
		CameraFinish();
		cam3done = true;
		cam4done = true;
	}*/]==]
    if (M.newobjective == true) then
        ClearObjectives()
        if (not IsAlive(M.t1)) then
            AddObjective("misns201.otf", "red")
        end
        if (not IsAlive(M.t2)) then
            AddObjective("misns202.otf", "red")
        end
        if (not IsAlive(M.t3)) then
            AddObjective("misns203.otf", "red")
        end
        if ((IsAlive(M.t1)) and (M.t1arrive == false)) then
            AddObjective("misns201.otf", "white")
        end
        if ((IsAlive(M.t1)) and (M.t1arrive == true)) then
            AddObjective("misns201.otf", "green")
        end
        if ((IsAlive(M.t2)) and (M.t2arrive == true)) then
            AddObjective("misns202.otf", "green")
        end
        if ((IsAlive(M.t2)) and (M.t2arrive == false)) then
            AddObjective("misns202.otf", "white")
        end
        if ((IsAlive(M.t3)) and (M.t3arrive == true)) then
            AddObjective("misns203.otf", "green")
        end
        if ((IsAlive(M.t3)) and (M.t3arrive == false)) then
            AddObjective("misns203.otf", "white")
        end
        M.newobjective = false
    end
    if ((M.wave1start < GetTime()) and (M.wave1gone == false)) then
        M.bd1 = BuildObject("bvtank", 2, "bdsp1")
        M.bd2 = BuildObject("bvraz", 2, "bdsp1")
--[==[//bd3 = BuildObject ("bvraz", 2, "bdsp1");]==]
--[==[//bd4 = BuildObject ("bvraz", 2, "bdsp1");]==]
        Attack(M.bd1, M.t1, 1)
        Attack(M.bd2, M.t3, 1)
--[==[//Attack (bd3, t3, 1);]==]
--[==[//Attack (bd4, t3, 1);]==]
        SetIndependence(M.bd1, 1)
        SetIndependence(M.bd2, 1)
--[==[//SetIndependence (bd3, 1);]==]
--[==[//SetIndependence (bd4, 1);]==]
        M.wave1gone = true
        M.wave1start = 999999999999.0
    end
    if ((M.wave1gone == true) and (not IsAlive(M.bd1)) and (not IsAlive(M.bd2)) and (M.cintimeset == false)) then
        AudioMessage("misns203.wav")
        M.cintime = GetTime() +3.0
        M.cintimeset = true
    end
    if ((not IsAlive(M.bd1))
        and (not IsAlive(M.bd2))
        and (M.surrender == false)
        and (M.wave1gone == true)
        and (M.cintime < GetTime())) then
        M.aud2 = AudioMessage("misns204.wav")
        M.aud3 = AudioMessage("misns205.wav")
        M.surrender = true
        CameraReady()
        M.platooncam = GetTime() + 20.0
        M.bd100 = BuildObject("bvtank", 2, "100")
        M.bd101 = BuildObject("bvtank", 2, "101")
        M.bd102 = BuildObject("bvtank", 2, "102")
        M.bd103 = BuildObject("bvtank", 2, "103")
        M.bd104 = BuildObject("bvtank", 2, "104")
        M.bd105 = BuildObject("bvtank", 2, "105")
        M.bd106 = BuildObject("bvtank", 2, "106")
        M.bd107 = BuildObject("bvtank", 2, "107")
        M.bd108 = BuildObject("bvtank", 2, "108")
        M.bd109 = BuildObject("bvtank", 2, "109")
        M.bd110 = BuildObject("bvtank", 2, "110")
    end
    if (M.bdcindone == false) then
        if (M.surrender == true) then
            CameraPath("platooncam", 1000, 600, M.bd100)
            if (((IsAudioMessageDone(M.aud2)) and (IsAudioMessageDone(M.aud3))) or (CameraCancelled())) then
                CameraFinish()
                StopAudioMessage(M.aud2)
                StopAudioMessage(M.aud3)
                M.aud4 = AudioMessage("misns206.wav")
                M.platooncamdone = true
                Attack(M.bd103, M.t3)
                Attack(M.bd104, M.t2)
                RemoveObject(M.bd100)
                RemoveObject(M.bd101)
                RemoveObject(M.bd102)
                RemoveObject(M.bd105)
                RemoveObject(M.bd106)
                RemoveObject(M.bd107)
                RemoveObject(M.bd108)
                RemoveObject(M.bd109)
                RemoveObject(M.bd110)
                M.bdcindone = true
            end
        end
    end
--[==[/*	if 
		(
		(surrender == true) && (platooncam > GetTime())
		)

	{
		CameraPath("platooncam", 1000, 600, bd100);
	}

	if 
		(
		(platooncam < GetTime()) && (platooncamdone == false)
		)
	{
		CameraFinish();
		platooncamdone = true;
		Attack (bd103, t3);
		Attack (bd104, t2);
		RemoveObject(bd100);
		RemoveObject(bd101);
		RemoveObject(bd102);
		RemoveObject(bd105);
		RemoveObject(bd106);
		RemoveObject(bd107);
		RemoveObject(bd108);
		RemoveObject(bd109);
		RemoveObject(bd110);
	}*/]==]
-- GetNearestVehicle(path, 1) samples path point 1, as in native ScriptUtils.
-- It is not a team filter; the explicit team tests below remain unchanged.
    if (M.wave2gone == false) then
        M.enemy3 = GetNearestVehicle("bdsp2", 1)
    end
    if ((M.wave2gone == false) and (Distance(M.enemy3, "bdsp2") < 420.0)) then
        M.bd5 = BuildObject("bvraz", 2, "bdsp2")
        M.bd6 = BuildObject("bvraz", 2, "bdsp2")
        M.bd7 = BuildObject("bvraz", 2, "bdsp2")
        M.bd8 = BuildObject("bvtank", 2, "bdsp2")
        Attack(M.bd5, M.t3, 1)
        Attack(M.bd6, M.t1, 1)
        Attack(M.bd7, M.t3, 1)
        Attack(M.bd8, M.t2, 1)
        SetIndependence(M.bd5, 1)
        SetIndependence(M.bd6, 1)
        SetIndependence(M.bd7, 1)
        SetIndependence(M.bd8, 1)
        M.wave2gone = true
    end
    if (((Distance(M.t1, "nav1") < 200.0)
        or (Distance(M.t2, "nav1") < 200.0)
        or (Distance(M.t3, "nav1") < 200.0))
        and (M.wave2gone == false)) then
        M.bd5 = BuildObject("bvraz", 2, "bdsp2")
        M.bd6 = BuildObject("bvraz", 2, "bdsp2")
        M.bd7 = BuildObject("bvraz", 2, "bdsp2")
        M.bd8 = BuildObject("bvtank", 2, "bdsp2")
        Attack(M.bd5, M.t1, 1)
        Attack(M.bd6, M.t2, 1)
        Attack(M.bd7, M.t2, 1)
        Attack(M.bd8, M.t3, 1)
        SetIndependence(M.bd5, 1)
        SetIndependence(M.bd6, 1)
        SetIndependence(M.bd7, 1)
        SetIndependence(M.bd8, 1)
        M.wave2gone = true
    end
    if (M.wave3gone == false) then
        M.enemy1 = GetNearestVehicle("bdsp3", 1)
    end
    if ((M.wave3gone == false) and (Distance(M.enemy1, "bdsp3") < 450.0) and (GetTeamNum(M.enemy1) == 1)) then
        M.bd9 = BuildObject("bvartl", 2, "bdsp3")
        M.bd10 = BuildObject("bvartl", 2, "bdsp3")
        M.bd11 = BuildObject("bvtank", 2, "bdsp3")
        SetIndependence(M.bd11, 1)
        M.wave3gone = true
    end
    if ((M.wave3gone == false)
        and ((Distance(M.t1, "nav3") < 400.0)
        or (Distance(M.t2, "nav3") < 400.0)
        or (Distance(M.t3, "nav3") < 400.0))) then
        M.bd9 = BuildObject("bvartl", 2, "bdsp3")
        M.bd10 = BuildObject("bvartl", 2, "bdsp3")
        M.bd11 = BuildObject("bvtank", 2, "bdsp3")
--[==[//bdcutoff1 = BuildObject("bvraz", 2, "nav5");]==]
--[==[//bdcutoff2 = BuildObject("bvraz", 2, "nav5");]==]
--[==[//bdcutoff3 = BuildObject("bvraz", 2, "nav5");]==]
--[==[//Attack(bdcutoff1, t1);]==]
--[==[//Attack(bdcutoff2, t2);]==]
--[==[//Attack(bdcut0ff2, t3);]==]
        BuildObject("proxmine", 2, "mine1")
        BuildObject("proxmine", 2, "mine2")
        BuildObject("proxmine", 2, "mine3")
        BuildObject("proxmine", 2, "mine4")
        BuildObject("proxmine", 2, "mine5")
        BuildObject("proxmine", 2, "mine6")
        BuildObject("proxmine", 2, "mine7")
        BuildObject("proxmine", 2, "mine8")
        BuildObject("proxmine", 2, "mine9")
        BuildObject("proxmine", 2, "mine10")
        BuildObject("proxmine", 2, "mine11")
        BuildObject("proxmine", 2, "mine12")
        BuildObject("proxmine", 2, "mine13")
        BuildObject("proxmine", 2, "mine14")
        BuildObject("proxmine", 2, "mine15")
        BuildObject("proxmine", 2, "mine16")
        BuildObject("proxmine", 2, "mine17")
        BuildObject("proxmine", 2, "mine18")
        BuildObject("proxmine", 2, "mine19")
        Attack(M.bd9, M.t3)
        Attack(M.bd10, M.t2)
        Follow(M.bd11, M.bd9)
        SetIndependence(M.bd11, 1)
        M.wave3gone = true
        M.alerttime = GetTime() + 15.0
    end
    if ((M.alerttime < GetTime()) and (M.artwarning == false)) then
        MarkObjective(M.bd9)
        MarkObjective(M.bd10)
        AudioMessage("misns210.wav")
        MarkObjective(M.bd12)
        MarkObjective(M.bd13)
        M.artwarning = true
    end
    if (M.wave4gone == false) then
        M.enemy2 = GetNearestVehicle("bdsp4", 1)
    end
    if ((M.wave4gone == false) and (Distance(M.enemy2, "bdsp4") < 450.0) and (GetTeamNum(M.enemy2) == 1)) then
        M.bd12 = BuildObject("bvartl", 2, "bdsp4")
        M.bd13 = BuildObject("bvtank", 2, "bdsp4")
        M.bd14 = BuildObject("bvtank", 2, "bdsp4")
        SetIndependence(M.bd14, 1)
        M.wave4gone = true
    end
    if ((M.wave4gone == false)
        and ((Distance(M.t1, "nav3") < 200.0)
        or (Distance(M.t2, "nav3") < 200.0)
        or (Distance(M.t3, "nav3") < 200.0))) then
        M.bd12 = BuildObject("bvartl", 2, "bdsp4")
        M.bd13 = BuildObject("bvartl", 2, "bdsp4")
        M.bd14 = BuildObject("bvtank", 2, "bdsp4")
        Attack(M.bd12, M.t1)
        Attack(M.bd13, M.t2)
        Follow(M.bd14, M.bd12)
        SetIndependence(M.bd14, 1)
        M.wave4gone = true
    end
    if ((M.wave4gone == true)
        and (M.wave3gone == true)
        and (M.bdplatoonspawned == false)
        and (not IsAlive(M.bd9))
        and (not IsAlive(M.bd10))
        and (not IsAlive(M.bd12))
        and (not IsAlive(M.bd13))) then
        M.bd15 = BuildObject("bvtank", 2, "bdspmain")
        M.bd16 = BuildObject("bvtank", 2, "bdspmain")
        M.bd17 = BuildObject("bvtank", 2, "bdspmain")
        M.bd18 = BuildObject("bvtank", 2, "bdspmain")
        M.bdplatoonspawned = true
        Attack(M.bd15, M.t1)
        Attack(M.bd16, M.t1)
        Attack(M.bd17, M.t2)
        Attack(M.bd18, M.t2)
    end
    if ((M.wave5gone == false)
        and ((Distance(M.player, M.launchpad) < 550.0)
        or (Distance(M.t1, M.launchpad) < 550.0)
        or (Distance(M.t2, M.launchpad) < 550.0)
        or (Distance(M.t3, M.launchpad) < 550.0))) then
        M.bd22 = BuildObject("bvraz", 2, "bdsp5")
        M.bd23 = BuildObject("bvraz", 2, "bdsp5")
        M.bd24 = BuildObject("bvraz", 2, "bdsp5")
--[==[//bd25 = BuildObject ("bvtank", 2, "bdsp5");]==]
--[==[//bd26 = BuildObject ("bvtank", 2, "bdsp5");]==]
        Attack(M.bd22, M.t1)
        Attack(M.bd23, M.t2)
        Attack(M.bd24, M.t3)
        M.wave5gone = true
    end
    if (M.bdplatoonspawned == false) then
        M.dummy = GetNearestVehicle("bdspmain", 1)
    end
    if ((Distance(M.dummy, "bdspmain") < 420.0) and (M.bdplatoonspawned == false) and (GetTeamNum(M.dummy) == 1)) then
        M.bd15 = BuildObject("bvtank", 2, "bdspmain")
        M.bd16 = BuildObject("bvtank", 2, "bdspmain")
        M.bd17 = BuildObject("bvtank", 2, "bdspmain")
        M.bd18 = BuildObject("bvtank", 2, "bdspmain")
        M.bd19 = BuildObject("bvraz", 2, "bdspmain")
        M.bd20 = BuildObject("bvraz", 2, "bdspmain")
        M.bd21 = BuildObject("bvraz", 2, "bdspmain")
        M.bdplatoonspawned = true
    end
    if ((Distance(M.player, "bdnet4") < 550.0) and (M.camnet1found == false)) then
--[==[/*nav1 = BuildObject ("apcamr", 2, "bdnet1");
		nav2 = BuildObject ("apcamr", 2, "bdnet2");
		nav3 = BuildObject ("apcamr", 2, "bdnet3");
		nav4 = BuildObject ("apcamr", 2, "bdnet4");
		nav5 = BuildObject ("apcamr", 2, "bdnet5");
		nav6 = BuildObject ("apcamr", 2, "bdnet6");*/]==]
        M.cutoff1 = BuildObject("bvtank", 2, "bdnet4")
        M.cutoff2 = BuildObject("bvtank", 2, "bdnet4")
        M.cutoff3 = BuildObject("bvraz", 2, "bdnet4")
        M.cutoff4 = BuildObject("bvraz", 2, "bdnet4")
        M.cutoff5 = BuildObject("bvraz", 2, "bdnet4")
        M.cutoff6 = BuildObject("bvraz", 2, "bdnet4")
        Attack(M.cutoff1, M.t1)
        SetIndependence(M.cutoff1, 1)
        Attack(M.cutoff2, M.t1)
        SetIndependence(M.cutoff2, 1)
        Attack(M.cutoff3, M.t2)
        SetIndependence(M.cutoff3, 1)
        Attack(M.cutoff4, M.t2)
        SetIndependence(M.cutoff4, 1)
        Attack(M.cutoff5, M.t3)
        SetIndependence(M.cutoff5, 1)
        Attack(M.cutoff6, M.t3)
        SetIndependence(M.cutoff6, 1)
        M.camnet1found = true
        M.bd12 = BuildObject("bvartl", 2, "bdsp4")
        M.bd13 = BuildObject("bvartl", 2, "bdsp4")
        M.bd14 = BuildObject("bvtank", 2, "bdsp4")
-- BUG FIX: source sets wave3gone here, but these are wave 4 handles
-- (bd12-bd14 at bdsp4). That suppresses wave 3 and lets wave 4 overwrite
-- this group later. Track wave4gone instead, preserving this ambush's
-- units, orders and timing and the intended independent wave sequence.
-- Original: wave3gone = true;
        M.wave4gone = true
        Attack(M.bd12, M.t3)
        Follow(M.bd13, M.bd12)
        Follow(M.bd14, M.bd12)
    end
    if ((M.camnet1found == true) and (M.nicetry == false)) then
        M.cutoff = NearestEnemy(M.cutoff1)
    end
    if ((Distance(M.cutoff, M.cutoff1) < 400.0) and (M.nicetry == false)) then
        AudioMessage("misns209.wav")
        M.nicetry = true
    end
    if (((Distance(M.player, "bdnet9") < 410.0)
        or (Distance(M.player, "bdnet12") < 410.0))
        and (M.camnet2found == false)) then
        M.nav7 = BuildObject("apcamr", 2, "bdnet7")
        M.nav8 = BuildObject("apcamr", 2, "bdnet8")
        M.nav9 = BuildObject("apcamr", 2, "bdnet9")
        M.nav10 = BuildObject("apcamr", 2, "bdnet10")
        M.nav11 = BuildObject("apcamr", 2, "bdnet11")
        M.nav12 = BuildObject("apcamr", 2, "bdnet12")
        M.nav13 = BuildObject("apcamr", 2, "bdnet13")
        M.nav14 = BuildObject("apcamr", 2, "bdnet14")
        M.camnet2found = true
        AudioMessage("misns207.wav")
    end
    if (M.camnet2found == true) then
        M.one = GetNearestVehicle("bdnet7", 1)
        M.two = GetNearestVehicle("bdnet8", 1)
        M.three = GetNearestVehicle("bdnet9", 1)
        M.four = GetNearestVehicle("bdnet10", 1)
        M.five = GetNearestVehicle("bdnet11", 1)
        M.six = GetNearestVehicle("bdnet12", 1)
        M.seven = GetNearestVehicle("bdnet13", 1)
        M.eight = GetNearestVehicle("bdnet14", 1)
        if (((Distance(M.one, "bdnet7") < 20.0)
            or (Distance(M.two, "bdnet8") < 20.0)
            or (Distance(M.three, "bdnet9") < 20.0)
            or (Distance(M.four, "bdnet10") < 20.0)
            or (Distance(M.five, "bdnet11") < 20.0)
            or (Distance(M.six, "bdnet12") < 20.0)
            or (Distance(M.seven, "bdnet13") < 20.0)
            or (Distance(M.eight, "bdnet14") < 20.0))
            and (M.wave3gone == false)) then
            M.bd9 = BuildObject("bvartl", 2, "bdsp3")
            M.bd10 = BuildObject("bvartl", 2, "bdsp3")
            M.bd11 = BuildObject("bvtank", 2, "bdsp3")
            Attack(M.bd9, M.t3)
            Attack(M.bd10, M.t2)
            Follow(M.bd11, M.bd9)
            M.wave3gone = true
        end
    end
    if ((M.camnet2found == true)
        and ((not IsAlive(M.nav7))
        or (not IsAlive(M.nav8))
        or (not IsAlive(M.nav9))
        or (not IsAlive(M.nav10))
        or (not IsAlive(M.nav11))
        or (not IsAlive(M.nav12))
        or (not IsAlive(M.nav13))
        or (not IsAlive(M.nav14)))
        and (M.sneaktimeset == false)) then
        M.sneaktime = GetTime() + 45.0
        M.sneaktimeset = true
        AudioMessage("misns208.wav")
    end
    if ((M.sneaktime < GetTime()) and (M.patrolsent == false)) then
        M.pat1 = BuildObject("svfigh", 2, "bdspmain")
        M.pat2 = BuildObject("svfigh", 2, "bdspmain")
        M.patrolsent = true
        Goto(M.pat1, "bdnet9")
        Goto(M.pat2, "bdnet12")
    end
    if ((M.patrolsent == true) and (M.playerfound == false)) then
        M.ten = NearestEnemy(M.pat1)
        M.nine = NearestEnemy(M.pat2)
-- BUG FIX: nine comes from pat2, ten from pat1. The source tested
-- nine/pat1 twice, making the second scout branch unreachable. Pair
-- each enemy with its querying scout; keep the 50 m trigger, original
-- spawn/retarget orders and wave3gone latch. No new mission phase.
-- Original (both branches): GetDistance(nine, pat1) < 50.0f
        if ((Distance(M.nine, M.pat2) < 50.0) and (M.wave3gone == false)) then
            if (M.wave3gone == false) then
                M.bd9 = BuildObject("bvartl", 2, "bdsp3")
                M.bd10 = BuildObject("bvartl", 2, "bdsp3")
                M.bd11 = BuildObject("bvtank", 2, "bdsp3")
                Attack(M.bd9, M.t3)
                Attack(M.bd10, M.t2)
                Follow(M.bd11, M.bd9)
                M.wave3gone = true
            end
            if (M.wave3gone == true) then
                if (IsAlive(M.bd9)) then
                    Attack(M.bd9, M.nine)
                end
                if (IsAlive(M.bd10)) then
                    Attack(M.bd10, M.nine)
                end
                if (IsAlive(M.bd11)) then
                    Follow(M.bd11, M.bd9)
                end
                M.wave3gone = true
            end
        end
        if ((Distance(M.ten, M.pat1) < 50.0) and (M.wave3gone == false)) then
            if (M.wave3gone == false) then
                M.bd9 = BuildObject("bvartl", 2, "bdsp3")
                M.bd10 = BuildObject("bvartl", 2, "bdsp3")
                M.bd11 = BuildObject("bvtank", 2, "bdsp3")
                Attack(M.bd9, M.ten)
                Attack(M.bd10, M.ten)
                Follow(M.bd11, M.bd9)
                M.wave3gone = true
            end
            if (M.wave3gone == true) then
                if (IsAlive(M.bd9)) then
                    Attack(M.bd9, M.ten)
                end
                if (IsAlive(M.bd10)) then
                    Attack(M.bd10, M.ten)
                end
                if (IsAlive(M.bd11)) then
                    Follow(M.bd11, M.ten)
                end
            end
            M.wave3gone = true
        end
    end
    if ((M.patrolsent == true)
        and (M.playerfound == false)
        and ((Distance(M.pat1, "bdnet9") < 20.0)
        or (Distance(M.pat2, "bdnet12") < 20.0))
        and (M.bdplatoonspawned == false)) then
        M.bd15 = BuildObject("bvtank", 2, "bdspmain")
        M.bd16 = BuildObject("bvtank", 2, "bdspmain")
        M.bd17 = BuildObject("bvtank", 2, "bdspmain")
        M.bd18 = BuildObject("bvtank", 2, "bdspmain")
        M.bd19 = BuildObject("bvraz", 2, "bdspmain")
        M.bd20 = BuildObject("bvraz", 2, "bdspmain")
        M.bd21 = BuildObject("bvraz", 2, "bdspmain")
        M.bdplatoonspawned = true
        Attack(M.bd15, M.t1)
        SetIndependence(M.bd15, 1)
        Attack(M.bd16, M.t1)
        SetIndependence(M.bd16, 1)
        Attack(M.bd17, M.t2)
        SetIndependence(M.bd17, 1)
        Attack(M.bd18, M.t2)
        SetIndependence(M.bd18, 1)
        Attack(M.bd19, M.t3)
        SetIndependence(M.bd19, 1)
        Attack(M.bd20, M.t3)
        SetIndependence(M.bd20, 1)
        Attack(M.bd21, M.t1)
        SetIndependence(M.bd21, 1)
    end
    if ((M.patrolsent == true)
        and (M.playerfound == false)
        and ((Distance(M.pat1, "bdnet9") < 20.0)
        or (Distance(M.pat2, "bdnet12") < 20.0))) then
        if (M.wave3gone == false) then
            M.bd9 = BuildObject("bvartl", 2, "bdsp3")
            M.bd10 = BuildObject("bvartl", 2, "bdsp3")
            M.bd11 = BuildObject("bvtank", 2, "bdsp3")
            Attack(M.bd9, M.t3)
            Attack(M.bd10, M.t2)
            Follow(M.bd11, M.bd9)
            M.wave3gone = true
        end
        if (M.wave3gone == true) then
            if (IsAlive(M.bd9)) then
                Attack(M.bd9, M.t3)
            end
            if (IsAlive(M.bd10)) then
                Attack(M.bd10, M.t2)
            end
            if (IsAlive(M.bd11)) then
                Follow(M.bd11, M.bd9)
            end
        end
        M.wave3gone = true
    end
--[==[//victory points]==]
    if ((not IsAlive(M.t1)) and (M.missionfail == false)) then
        M.aud10 = AudioMessage("misns212.wav")
        M.missionfail = true
        M.newobjective = true
    end
    if ((not IsAlive(M.t2)) and (M.missionfail == false)) then
        M.aud10 = AudioMessage("misns212.wav")
        M.missionfail = true
        M.newobjective = true
    end
    if ((not IsAlive(M.t3)) and (M.missionfail == false)) then
        M.aud10 = AudioMessage("misns212.wav")
        M.missionfail = true
        M.newobjective = true
    end
-- BUG FIX: source reissues FailMission/SucceedMission every frame once
-- audio finishes. Schedule once at the same source time and debrief; all
-- preceding radio, arrival and retreat logic still runs in source order.
    if not M.outcomeSent and ((M.missionfail == true) and (IsAudioMessageDone(M.aud10))) then
        FailMission(GetTime(), "misns2l1.des")
        M.outcomeSent = true
    end
-- BUG FIX: a destroyed APC may still have a valid wreck handle. Only a
-- living APC can arrive; otherwise failure and arrival/success could fire
-- together. Living APCs retain the exact 100 m trigger and radio sequence.
    if IsAlive(M.t1) and ((Distance(M.t1, M.launchpad) < 100.0) and (M.t1arrive == false)) then
        AudioMessage("misns216.wav")
        M.t1arrive = true
        M.newobjective = true
    end
    if IsAlive(M.t2) and ((Distance(M.t2, M.launchpad) < 100.0) and (M.t2arrive == false)) then
        AudioMessage("misns217.wav")
        M.t2arrive = true
        M.newobjective = true
    end
    if IsAlive(M.t3) and ((Distance(M.t3, M.launchpad) < 100.0) and (M.t3arrive == false)) then
        AudioMessage("misns218.wav")
        M.t3arrive = true
        M.newobjective = true
    end
-- BUG FIX: source arrival flags remain true after an APC dies. Failure
-- takes precedence over victory, including during the victory radio queue.
-- This preserves "escort all three APCs" and the source's audio-gated ending;
-- it prevents contradictory debriefs without changing a successful convoy.
    if not M.missionfail
        and ((M.missionwon == false)
        and (M.t1arrive == true)
        and (M.t2arrive == true)
        and (M.t3arrive == true)) then
        M.missionwon = true
        M.aud50 = AudioMessage("misns213.wav")
        M.aud51 = AudioMessage("misns214.wav")
        M.aud52 = AudioMessage("misns215.wav")
        if (IsAlive(M.bd3)) then
            Retreat(M.bd3, "bdspmain", 1000)
        end
        if (IsAlive(M.bd4)) then
            Retreat(M.bd4, "bdspmain", 1000)
        end
        if (IsAlive(M.bd5)) then
            Retreat(M.bd5, "bdspmain", 1000)
        end
        if (IsAlive(M.bd6)) then
            Retreat(M.bd6, "bdspmain", 1000)
        end
        if (IsAlive(M.bd7)) then
            Retreat(M.bd7, "bdspmain", 1000)
        end
        if (IsAlive(M.bd8)) then
            Retreat(M.bd8, "bdspmain", 1000)
        end
        if (IsAlive(M.bd9)) then
            Retreat(M.bd9, "bdspmain", 1000)
        end
        if (IsAlive(M.bd10)) then
            Retreat(M.bd10, "bdspmain", 1000)
        end
        if (IsAlive(M.bd11)) then
            Retreat(M.bd11, "bdspmain", 1000)
        end
        if (IsAlive(M.bd12)) then
            Retreat(M.bd12, "bdspmain", 1000)
        end
        if (IsAlive(M.bd13)) then
            Retreat(M.bd13, "bdspmain", 1000)
        end
        if (IsAlive(M.bd14)) then
            Retreat(M.bd14, "bdspmain", 1000)
        end
        if (IsAlive(M.bd15)) then
            Retreat(M.bd15, "bdspmain", 1000)
        end
        if (IsAlive(M.bd16)) then
            Retreat(M.bd16, "bdspmain", 1000)
        end
        if (IsAlive(M.bd17)) then
            Retreat(M.bd17, "bdspmain", 1000)
        end
        if (IsAlive(M.bd18)) then
            Retreat(M.bd18, "bdspmain", 1000)
        end
        if (IsAlive(M.bd19)) then
            Retreat(M.bd19, "bdspmain", 1000)
        end
        if (IsAlive(M.bd20)) then
            Retreat(M.bd20, "bdspmain", 1000)
        end
        if (IsAlive(M.bd21)) then
            Retreat(M.bd21, "bdspmain", 1000)
        end
        if (IsAlive(M.bd22)) then
            Retreat(M.bd22, "bdspmain", 1000)
        end
        if (IsAlive(M.bd23)) then
            Retreat(M.bd23, "bdspmain", 1000)
        end
        if (IsAlive(M.bd24)) then
            Retreat(M.bd24, "bdspmain", 1000)
        end
        if (IsAlive(M.bd25)) then
            Retreat(M.bd25, "bdspmain", 1000)
        end
        if (IsAlive(M.bd26)) then
            Retreat(M.bd26, "bdspmain", 1000)
        end
        if (IsAlive(M.bd27)) then
            Retreat(M.bd27, "bdspmain", 1000)
        end
        if (IsAlive(M.bd100)) then
            Retreat(M.bd100, "bdspmain", 1000)
        end
        if (IsAlive(M.bd101)) then
            Retreat(M.bd101, "bdspmain", 1000)
        end
        if (IsAlive(M.bd102)) then
            Retreat(M.bd102, "bdspmain", 1000)
        end
        if (IsAlive(M.bd103)) then
            Retreat(M.bd103, "bdspmain", 1000)
        end
        if (IsAlive(M.bd104)) then
            Retreat(M.bd104, "bdspmain", 1000)
        end
        if (IsAlive(M.bd105)) then
            Retreat(M.bd105, "bdspmain", 1000)
        end
        if (IsAlive(M.bd106)) then
            Retreat(M.bd106, "bdspmain", 1000)
        end
        if (IsAlive(M.bd107)) then
            Retreat(M.bd107, "bdspmain", 1000)
        end
        if (IsAlive(M.bd108)) then
            Retreat(M.bd108, "bdspmain", 1000)
        end
        if (IsAlive(M.bd109)) then
            Retreat(M.bd109, "bdspmain", 1000)
        end
        if (IsAlive(M.bd110)) then
            Retreat(M.bd110, "bdspmain", 1000)
        end
        if (IsAlive(M.cutoff1)) then
            Retreat(M.cutoff1, "bdspmain", 1000)
        end
        if (IsAlive(M.cutoff2)) then
            Retreat(M.cutoff2, "bdspmain", 1000)
        end
        if (IsAlive(M.cutoff3)) then
            Retreat(M.cutoff3, "bdspmain", 1000)
        end
        if (IsAlive(M.cutoff4)) then
            Retreat(M.cutoff4, "bdspmain", 1000)
        end
        if (IsAlive(M.cutoff5)) then
            Retreat(M.cutoff5, "bdspmain", 1000)
        end
        if (IsAlive(M.cutoff6)) then
            Retreat(M.cutoff6, "bdspmain", 1000)
        end
        if (IsAlive(M.pat1)) then
            Retreat(M.pat1, "bdspmain", 1000)
        end
        if (IsAlive(M.pat2)) then
            Retreat(M.pat2, "bdspmain", 1000)
        end
    end
    if not M.outcomeSent
        and not M.missionfail
        and ((M.missionwon == true)
        and (IsAudioMessageDone(M.aud50))
        and (IsAudioMessageDone(M.aud51))
        and (IsAudioMessageDone(M.aud52))) then
        SucceedMission(GetTime() + 0.0, "misns2w1.des")
        M.outcomeSent = true
    end
end

-- BZR serializes table values and remaps saved game handles. Do not rerun
-- Setup, recreate objects or restart audio/cinematics when restoring a save.
function Save()
    return M
end

function Load(state)
    M = state
end
