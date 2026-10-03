-- Faithful misns1 DLL-source port for stock Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misns1Mission.cpp
-- Source blob: 2777814cd482d24d7d9aed0ee4b76bb5c937f241.
-- Original disabled C++ is retained at the corresponding locations below.
-- Complete source and native serialization: References/Misns1Source/.
-- Single-player; no EXU/OpenShim or Campaign Reimagined helpers required.
local M

local function NewState()
    local state = {}
    state.coloradoescapes = false
    state.halfwaywarn = false
    state.coloradodestroyed = false
    state.silodestroyed = false
    state.mufdestroyed = false
    state.retreat = false
    state.missionstart = false
    state.missionwon = false
    state.enterwarning = false
    state.trapset = false
    state.coloradosafe = false
    state.missionfail = false
    state.beginassault = false
    state.convoyseen = false
    state.convoyintrap = false
    state.pickpath = false
    state.cav1pathwarn1 = false
    state.cav1pathwarn2 = false
    state.cav2pathwarn1 = false
    state.cav2pathwarn2 = false
    state.cav3pathwarn1 = false
    state.cav3pathwarn2 = false
    state.cav4pathwarn1 = false
    state.cav4pathwarn2 = false
    state.finish = false
    state.cavalry = false
    state.cavsent = false
    state.cavpath1 = false
    state.cavpath2 = false
    state.cavpath3 = false
    state.cavpath4 = false
    state.coloradoreachedsafepoint = false
    state.possible1 = false
    state.possible2 = false
    state.newobjective = false
    state.escortretreat = false
    state.cindone = false
    state.cindone05 = false
    state.cindone1 = false
    state.cindone2 = false
    state.cindone3 = false
    state.cindone4 = false
    state.cindone5 = false
    state.cindone6 = false
    state.cindone7 = false
    state.cindone8 = false
    state.cindone08 = false
    state.cindone9 = false
    state.cindone10 = false
    state.cindone11 = false
    state.retreatpathset = false
    state.blockaderun = false
    state.aw1amade = false
    state.aw1bmade = false
    state.aw1cmade = false
    state.aw2amade = false
    state.aw2bmade = false
    state.aw2cmade = false
    state.aw3amade = false
    state.aw3bmade = false
    state.aw3cmade = false
    state.du1amade = false
    state.du1bmade = false
    state.safety1 = false
    state.startconvoy = 9999999999.0
    state.wave1 = 999999999.0
    state.cintime = 9999999999.0
    state.cintime05 = 99999999.0
    state.cintime2 = 9999999999.0
    state.cintime3 = 9999999999.0
    state.cintime4 = 9999999999.0
    state.cintime5 = 9999999999.0
    state.cintime6 = 9999999999.0
    state.cintime7 = 9999999999.0
    state.cintime8 = 9999999999.0
    state.cintime9 = 9999999999.0
    state.cintime09 = 999999999999.0
    state.cintime10 = 9999999999.0
    state.cintime11 = 9999999999.0
    state.cintime12 = 99999.0
    state.aw1at = 99999999999.0
    state.aw1bt = 99999999999.0
    state.aw1ct = 99999999999.0
    state.aw2at = 99999999999.0
    state.aw2bt = 99999999999.0
    state.aw2ct = 99999999999.0
    state.aw3at = 99999999999.0
    state.aw3bt = 99999999999.0
    state.aw3ct = 99999999999.0
    state.du1at = 99999999999.0
    state.du1bt = 99999999999.0
    state.colorado = nil
    state.ef1 = nil
    state.ef2 = nil
    state.ef3 = nil
    state.et1 = nil
    state.et2 = nil
    state.et3 = nil
    state.et4 = nil
    state.silo = nil
    state.muf = nil
    state.svrec = nil
    state.player = nil
    state.geyser = nil
    state.geyser2 = nil
    state.guntower = nil
    state.walker1 = nil
    state.walker2 = nil
    state.walker3 = nil
    state.walkcam1 = nil
    state.walkcam2 = nil
    state.walkcam3 = nil
    state.hidcam1 = nil
    state.hidcam2 = nil
    state.hidcam3 = nil
    state.basecam = nil
    state.cav1 = nil
    state.cav2 = nil
    state.cav3 = nil
    state.cav4 = nil
    state.cav5 = nil
    state.scav1 = nil
    state.scav2 = nil
    state.aw1a = nil
    state.aw1b = nil
    state.aw1c = nil
    state.aw2a = nil
    state.aw2b = nil
    state.aw2c = nil
    state.aw3a = nil
    state.aw3b = nil
    state.aw3c = nil
    state.du1a = nil
    state.du1b = nil
    state.hostile = nil
    state.ambase = nil
    state.path = 0
    state.cav = 0
    state.aud20 = 0
    state.aud21 = 0
    state.aud22 = 0
    state.aud23 = 0
    state.aud1 = 0
    -- Per-outcome latches suppress repeated engine requests while preserving
    -- the source's order if multiple outcome conditions coincide in one frame.
    state.success_called = false
    state.escape_failure_called = false
    state.recycler_failure_called = false
    return state
end
M = NewState()

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

-- BUG FIX: removed escorts and never-created camera pods have no position.
-- Return infinity for missing handles so they cannot trip proximity warnings;
-- every valid-handle distance and all source thresholds remain unchanged.
local function MissionDistance(from, to)
    if not Valid(from) or to == nil or to == 0 then return math.huge end
    if type(to) ~= "string" and not Valid(to) then return math.huge end
    return GetDistance(from, to)
end

local function NearestEnemy(h)
    if Valid(h) then return GetNearestEnemy(h) end
    return nil
end

-- BUG FIX: the source removes et3 at startup but later commands it to follow.
-- Skip calls on absent craft/targets; do not replace that cut escort or change
-- any surviving escort's command. The same guard covers destruction mid-flight.
local function MissionGoto(h, where, priority)
    if Valid(h) and (type(where) == "string" or Valid(where)) then
        Goto(h, where, priority)
    end
end

local function MissionFollow(h, target, priority)
    if Valid(h) and Valid(target) then Follow(h, target, priority) end
end

local function MissionAttack(h, target)
    if Valid(h) and Valid(target) then Attack(h, target) end
end

local function Independence(h, level)
    if Valid(h) then SetIndependence(h, level) end
end

local function ObjectiveOn(h)
    if Valid(h) then SetObjectiveOn(h) end
end

local function ObjectiveName(h, name)
    if Valid(h) then SetObjectiveName(h, name) end
end

local function MissionRemove(h)
    if Valid(h) then RemoveObject(h) end
end

-- BUG FIX: scavenger/turret creation could use a removed factory as its
-- position. Never invent a replacement spawn point. Valid factories still
-- produce the exact source units at the exact source times. A still-valid wreck
-- remains a usable position as in the source; only missing objects are skipped.
-- Caller latches still advance, so these are one-shot attempts.
local function BuildAtFactory(odf, team, factory)
    if Valid(factory) then
        return BuildObject(odf, team, factory)
    end
    return nil
end

local function AudioDone(message)
    if message == nil or message == 0 then return true end
    return IsAudioMessageDone(message)
end

function Start()
    --[=[/*
	Here's where you
	set the values
	at the start.  
	*/]=]
    M = NewState()
end

function AddObject(h)
    -- Misns1Mission::AddObject(Handle) is empty in the DLL source.
end

function Save()
    return M
end

function Load(state)
    M = state
end

function Update(dt)
    --[=[/*
		Here is where you 
		put what happens 
		every frame.  
	*/]=]
    if (M.missionstart == false) then
        AudioMessage("misns101.wav")
        M.geyser = GetHandle("eggeizr10_geyser")
        M.muf = GetHandle("avmuf1_factory")
        M.silo = GetHandle("absilo1_i76building")
        M.colorado = GetHandle("avrecy1_recycler")
        M.svrec = GetHandle("svrecy2_recycler")
        SetScrap(2, 50)
        SetScrap(1, 20)
        --[=[//geyser2 = GetHandle ("geyser2");]=]
        M.ef1 = GetHandle("avfigh3_wingman")
        M.ef2 = GetHandle("avfigh4_wingman")
        M.ef3 = GetHandle("avfigh5_wingman")
        M.et1 = GetHandle("avtank5_wingman")
        M.et2 = GetHandle("avtank6_wingman")
        M.et3 = GetHandle("avtank7_wingman")
        M.et4 = GetHandle("avtank8_wingman")
        M.ambase = GetHandle("ambase")
        --[=[// temporary ]=]
        M.walker1 = BuildObject("svwalk", 1, "spawnwalker1")
        --[=[//walker2 = BuildObject ("svwalk", 1, "spawnwalker2"); ]=]
        --[=[//walker3 = BuildObject ("svwalk", 1, "walkstart3"); ]=]
        M.walkcam1 = BuildObject("apcamr", 1, "walkcam1")
        --[=[//walkcam2 = BuildObject ("apcamr", 1, "walkcam2");]=]
        --[=[//walkcam3 = BuildObject ("apcamr", 1, "walkcam3");]=]
        M.hidcam1 = BuildObject("apcamr", 1, "hidcamupper")
        M.hidcam2 = BuildObject("apcamr", 1, "hidcammiddle")
        M.hidcam3 = BuildObject("apcamr", 1, "hidcamlower")
        M.basecam = GetHandle("apcamr0_camerapod")
        ObjectiveName(M.walkcam1, "Walker Cut Off")
        --[=[//GameObjectHandle :: GetObj(walkcam2) ->SetName ("Middle Pass Exit");]=]
        ObjectiveName(M.ambase, "American Outpost")
        ObjectiveName(M.hidcam1, "Upper Pass Exit")
        ObjectiveName(M.hidcam2, "Middle Pass Exit")
        ObjectiveName(M.hidcam3, "Lower Pass Exit")
        ObjectiveName(M.basecam, "Home Base")
        --[=[//Goto (walker1, "spawnwalker1");]=]
        --[=[//Goto (walker2, "spawnwalker2");]=]
        --[=[//Goto (walker3, "spawnwalker3");]=]
        --[=[//RemoveObject (ef2);]=]
        --[=[//RemoveObject (ef3);]=]
        --[=[//RemoveObject (et1);]=]
        --[=[//RemoveObject (et2);]=]
        MissionRemove(M.et3)
        MissionRemove(M.et4)
        BuildObject("svtank", 1, "tank1")
        BuildObject("svtank", 1, "tank2")
        BuildObject("svfigh", 1, "figh1")
        BuildObject("svturr", 1, "turr1")
        BuildObject("svturr", 1, "turr2")
        M.startconvoy = GetTime() + 180.0
        M.missionstart = true
        SetScrap(1, 20)
        SetScrap(2, 50)
        M.path = math.random(0, 2)
        M.cav = math.random(0, 3)
        M.newobjective = true
        --[=[//CameraReady();]=]
        M.cintime = GetTime() + 11.0
        --[=[//11]=]
        M.cintime05 = GetTime() + 11.1
        --[=[//11]=]
        M.cintime2 = GetTime() + 20.0
        M.cintime3 = GetTime() + 27.0
        M.cintime4 = GetTime() + 29.0
        M.cintime5 = GetTime() + 31.0
        M.cintime6 = GetTime() + 33.0
        M.cintime7 = GetTime() + 44.0
        M.cintime8 = GetTime() + 46.0
        M.cintime9 = GetTime() + 48.0
        M.cintime09 = GetTime() + 50.0
        M.cintime10 = GetTime() + 60.0
        M.cintime11 = GetTime() + 66.0
    end
    IsAlive(M.colorado)
    --[=[/*if
		(
		(cindone == false) && (cintime > GetTime())
		)
	{
		CameraPath("cinpath3", 200, 600, svrec);
	}
	if
		(
		(cindone05 == false) && (cintime05 < GetTime())
		)
	{
		CameraPath("cinpath4", 300, 500, colorado);
		cindone = true;
	}
	if
		(
		(cindone1 == false) && (cintime2 < GetTime())
		)
	{
		//CameraObject(geyser2, 3000, 600, 3000, geyser2);
		CameraPath("geyserpath", 500, 5000, geyser2);
		cindone05 = true;
	}
	//CameraObject(walker1, -1200, 1500, -1100, walker2);
	if
		(
		(cintime3 < GetTime()) && (cindone2 == false)
		)
	{
		CameraObject(hidcam1, 1100, 300, 200, hidcam1);
		cindone1 = true;
	}
	if
		(
		(cintime4 < GetTime()) && (cindone3 == false)
		)
	{
		CameraObject(hidcam2, 300, 200, 1500, hidcam2);
		cindone2 = true;
	}
	if
		(
		(cintime5 < GetTime()) && (cindone4 == false)
		)
	{
		CameraObject(hidcam3, 600, 1000, 300, hidcam3);
		cindone3 = true;
	}
	if
		(
		(cintime6 < GetTime()) && (cindone5 == false)
		)
	{
		CameraObject(walker1, -1200, 1500, 1100, walker2);
		cindone4 = true;
	}
	if
		(
		(cintime7 < GetTime()) && (cindone6 == false)
		)
	{
		CameraObject(walkcam1, 500, 300, 1200, walkcam1);
		cindone5 = true;
	}
	if
		(
		(cintime8 < GetTime()) && (cindone7 == false)
		)
	{
		CameraObject(walkcam2, 1300, 200, 500, walkcam2);
		cindone6 = true;
	}
	if
		(
		(cintime9 < GetTime()) && (cindone8 == false)
		)
	{
		CameraObject(walkcam3, 600, 400, 1300, walkcam3);
		cindone7 = true;
	}
	if
		(
		(cindone08 == false) && (cintime09 < GetTime())
		)
	{
		CameraPath("approach", 400, 5000, hidcam3);
		cindone8 = true;
	}
	if
		(
		(cindone9 == false) && (cintime10 < GetTime())
		)
	{
		CameraPath("cinpath1", 300, 500, muf);
		cindone08 = true;
	}
	if
		(
		(cintime11 < GetTime()) && (cindone10 == false)
		)
	{
		CameraFinish();
		cindone9 = true;
		cindone10 = true;
	}*/]=]
    if (M.newobjective == true) then
        ClearObjectives()
        if ((IsAlive(M.colorado)) and (M.coloradosafe == false)) then
            AddObjective("misns101.otf", "white")
        end
        if ((not IsAlive(M.colorado)) and (M.coloradosafe == false)) then
            AddObjective("misns101.otf", "green")
        end
        if (M.coloradoreachedsafepoint == true) then
            AddObjective("misns101.otf", "red")
        end
        if (M.coloradosafe == false) then
            if ((IsAlive(M.muf)) or (IsAlive(M.silo))) then
                AddObjective("misns102.otf", "white")
            end
        end
        if (M.coloradosafe == true) then
            if ((IsAlive(M.muf)) or (IsAlive(M.silo)) or (IsAlive(M.colorado))) then
                AddObjective("misns102.otf", "white")
            end
        end
        if (M.coloradosafe == false) then
            if ((not IsAlive(M.muf)) and (not IsAlive(M.silo))) then
                AddObjective("misns102.otf", "green")
            end
        end
        if (M.coloradosafe == true) then
            if ((not IsAlive(M.muf)) and (not IsAlive(M.silo)) and (not IsAlive(M.colorado))) then
                AddObjective("misns102.otf", "green")
            end
        end
        if ((IsAlive(M.svrec)) and (M.missionwon == false)) then
            AddObjective("misns103.otf", "white")
        end
        if (not IsAlive(M.svrec)) then
            AddObjective("misns103.otf", "red")
        end
        if (M.missionwon == true) then
            -- BUG FIX: source "misn103.otf" omits this mission's "s" prefix.
            -- Complete this mission's existing recycler objective; UI-only change,
            -- with no change to victory conditions, radio, or debrief timing.
            AddObjective("misns103.otf", "green")
        end
        if ((M.coloradosafe == true) and (M.missionwon == false)) then
            AddObjective("misns101.otf", "red")
        end
        M.newobjective = false
    end
    if ((M.pickpath == false) and (M.startconvoy < GetTime())) then
        if M.path == 0 then
            MissionFollow(M.ef1, M.colorado)
            MissionFollow(M.ef2, M.colorado)
            MissionFollow(M.ef3, M.colorado)
            MissionGoto(M.colorado, "upperpath")
            MissionFollow(M.et1, M.colorado, 1)
            MissionFollow(M.et2, M.colorado, 1)
            --[=[//Follow (et3, colorado, 1);]=]
            --[=[//Follow (et4, colorado, 1);]=]
        elseif M.path == 1 then
            MissionFollow(M.ef1, M.colorado)
            MissionFollow(M.ef2, M.colorado)
            MissionFollow(M.ef3, M.colorado)
            MissionGoto(M.colorado, "midpath")
            MissionFollow(M.et1, M.colorado, 1)
            MissionFollow(M.et2, M.colorado, 1)
            --[=[//Follow (et3, colorado, 1);]=]
            --[=[//Follow (et4, colorado, 1);]=]
        elseif M.path == 2 then
            MissionFollow(M.ef1, M.colorado)
            MissionFollow(M.ef2, M.colorado)
            MissionFollow(M.ef3, M.colorado)
            MissionGoto(M.colorado, "lowerpath")
            MissionFollow(M.et1, M.colorado, 1)
            MissionFollow(M.et2, M.colorado, 1)
            --[=[//Follow (et3, colorado, 1);]=]
            --[=[//Follow (et4, colorado, 1);]=]
        end
        Independence(M.ef1, 1)
        Independence(M.ef2, 1)
        Independence(M.ef3, 1)
        Independence(M.et1, 1)
        Independence(M.et2, 1)
        --[=[//SetIndependence(et3, 1);]=]
        --[=[//SetIndependence(et4, 1);]=]
        M.pickpath = true
        AudioMessage("misns125.wav")
    end
    --[=[//||]=]
    --[=[//(GetDistance(walker2, walkcam1) < 50.0f) ||]=]
    --[=[//(GetDistance(walker3, walkcam1) < 50.0f)]=]
    if (((MissionDistance(M.walker1, M.walkcam1) < 50.0)) and (M.trapset == false) and (M.blockaderun == false) and (IsAlive(M.colorado))) then
        M.trapset = true
        AudioMessage("misns123.wav")
    end
    --[=[/*if 
		(
		(
		(GetDistance(walker1, walkcam2) < 50.0f) ||
		(GetDistance(walker2, walkcam2) < 50.0f) //||
		//(GetDistance(walker3, walkcam2) < 50.0f)
		) && (trapset == false) && (blockaderun == false)
		)
	{
		trapset = true;
		AudioMessage("misns123.wav");
	}

	if 
		(
		(
		(GetDistance(walker1, walkcam3) < 50.0f) ||
		(GetDistance(walker2, walkcam3) < 50.0f) //||
		//(GetDistance(walker3, walkcam3) < 50.0f)
		) && (trapset == false) && (blockaderun == false)
		)
	{
		trapset = true;
		AudioMessage("misns123.wav");
	}*/]=]
    if ((M.halfwaywarn == true) and (M.blockaderun == false)) then
        if ((M.path == 0) and (MissionDistance(M.colorado, M.hidcam1) < 70.0)) then
            M.blockaderun = true
            AudioMessage("misns124.wav")
        end
        if ((M.path == 1) and (MissionDistance(M.colorado, M.hidcam2) < 70.0)) then
            M.blockaderun = true
            AudioMessage("misns124.wav")
        end
        if ((M.path == 2) and (MissionDistance(M.colorado, M.hidcam3) < 70.0)) then
            M.blockaderun = true
            AudioMessage("misns124.wav")
        end
    end
    if ((M.retreat == false) and (M.blockaderun == false)) then
        M.hostile = NearestEnemy(M.colorado)
        if (MissionDistance(M.hostile, M.colorado) < 200.0) then
            --[=[//Attack (walker1, colorado);]=]
            --[=[//Attack (walker2, ef2);]=]
            --[=[//Attack (walker3, ef1);]=]
            --[=[//SetIndependence (walker1, 1);]=]
            --[=[//SetIndependence (walker2, 1);]=]
            --[=[//SetIndependence (walker3, 1);]=]
            M.retreat = true
            AudioMessage("misns114.wav")
        end
    end
    if ((M.retreatpathset == false) and (M.retreat == true)) then
        MissionGoto(M.colorado, "retreat1")
        MissionAttack(M.ef1, M.hostile)
        MissionFollow(M.ef2, M.ef1)
        MissionFollow(M.et3, M.ef1)
        Independence(M.ef1, 1)
        Independence(M.ef2, 1)
        Independence(M.et3, 1)
        M.retreatpathset = true
    end
    if ((M.retreat == true) and (MissionDistance(M.colorado, M.geyser) < 50.0) and (M.coloradosafe == false)) then
        M.coloradosafe = true
        SetAIP("misn09.aip")
        ObjectiveOn(M.colorado)
        ObjectiveOn(M.silo)
        ObjectiveOn(M.muf)
        AudioMessage("misns106.wav")
        M.aw1at = GetTime() + 25.0
        M.aw1bt = GetTime() + 30.0
        M.aw1ct = GetTime() + 35.0
        M.aw2at = GetTime() + 90.0
        M.aw2bt = GetTime() + 95.0
        M.aw2ct = GetTime() + 100.0
        M.aw3at = GetTime() + 190.0
        M.aw3bt = GetTime() + 195.0
        M.aw3ct = GetTime() + 200.0
        M.du1at = GetTime() + 60.0
        M.du1bt = GetTime() + 75.0
        M.newobjective = true
    end
    if ((not IsAlive(M.colorado)) and (M.escortretreat == false)) then
        MissionGoto(M.ef1, M.muf, 1000)
        MissionGoto(M.ef2, M.muf, 1000)
        MissionGoto(M.ef3, M.muf, 1000)
        --[=[//Goto(et1, muf, 1000);]=]
        M.escortretreat = true
    end
    if ((M.safety1 == false) and (M.coloradosafe == false) and (not IsAlive(M.colorado))) then
        SetAIP("misn14.aip")
        M.scav1 = BuildAtFactory("avscav", 2, M.muf)
        M.scav2 = BuildAtFactory("avscav", 2, M.muf)
        ObjectiveOn(M.silo)
        ObjectiveOn(M.muf)
        --[=[//coloradosafe = true;]=]
        M.safety1 = true
        AudioMessage("misns105.wav")
        M.aw1at = GetTime() + 25.0
        M.aw1bt = GetTime() + 35.0
        M.aw1ct = GetTime() + 40.0
        M.aw2at = GetTime() + 90.0
        M.aw2bt = GetTime() + 95.0
        M.aw2ct = GetTime() + 100.0
        M.aw3at = GetTime() + 190.0
        M.aw3bt = GetTime() + 195.0
        M.aw3ct = GetTime() + 200.0
        M.du1at = GetTime() + 60.0
        M.du1bt = GetTime() + 75.0
        M.newobjective = true
    end
    if ((M.aw1at < GetTime()) and (M.aw1amade == false) and (IsAlive(M.muf))) then
        BuildAtFactory("avtank", 2, M.muf)
        M.aw1amade = true
    end
    if ((M.aw1bt < GetTime()) and (M.aw1bmade == false) and (IsAlive(M.muf))) then
        BuildAtFactory("avfigh", 2, M.muf)
        M.aw1bmade = true
    end
    if ((M.aw1ct < GetTime()) and (M.aw1cmade == false) and (IsAlive(M.muf))) then
        BuildAtFactory("avfigh", 2, M.muf)
        M.aw1cmade = true
    end
    if ((M.aw2at < GetTime()) and (M.aw2amade == false) and (IsAlive(M.muf))) then
        BuildAtFactory("avtank", 2, M.muf)
        M.aw2amade = true
    end
    if ((M.aw2bt < GetTime()) and (M.aw2bmade == false) and (IsAlive(M.muf))) then
        BuildAtFactory("avfigh", 2, M.muf)
        M.aw2bmade = true
    end
    if ((M.aw2ct < GetTime()) and (M.aw2cmade == false) and (IsAlive(M.muf))) then
        BuildAtFactory("avtank", 2, M.muf)
        M.aw2cmade = true
    end
    if ((M.aw3at < GetTime()) and (M.aw3amade == false) and (IsAlive(M.muf)) and (IsAlive(M.silo))) then
        BuildAtFactory("avtank", 2, M.muf)
        M.aw3amade = true
    end
    if ((M.aw3bt < GetTime()) and (M.aw3bmade == false) and (IsAlive(M.muf)) and (IsAlive(M.silo))) then
        BuildAtFactory("avtank", 2, M.muf)
        M.aw3bmade = true
    end
    if ((M.aw3ct < GetTime()) and (M.aw3cmade == false) and (IsAlive(M.muf)) and (IsAlive(M.silo))) then
        BuildAtFactory("avfigh", 2, M.muf)
        M.aw3cmade = true
    end
    if ((M.du1at < GetTime()) and (M.du1amade == false)) then
        BuildAtFactory("avturr", 2, M.muf)
        M.du1amade = true
    end
    if ((M.du1bt < GetTime()) and (M.du1bmade == false)) then
        BuildAtFactory("avturr", 2, M.muf)
        M.du1bmade = true
    end
    --[=[/*if
		(
		(aw1sent == false) && (aw1amade == true) &&
		(aw1bmade == true) && (aw1cmade == true)
		)
	{
		Attack(aw1a, svrec);
		Attack(aw1b, svrec);
		Attack(aw1c, svrec);
		SetIndependence(aw1a, 1);
		SetIndependence(aw1b, 1);
		SetIndependence(aw1c, 1);
		aw1sent = true;
	}
	if
		(
		(aw2sent == false) && (aw2amade == true) &&
		(aw2bmade == true) && (aw2cmade == true)
		)
	{
		Attack(aw2a, svrec);
		Attack(aw2b, svrec);
		Attack(aw2c, svrec);
		SetIndependence(aw2a, 1);
		SetIndependence(aw2b, 1);
		SetIndependence(aw2c, 1);
		aw2sent = true;
	}
	if
		(
		(aw3sent == false) && (aw3amade == true) &&
		(aw3bmade == true) && (aw3cmade == true)
		)
	{
		Attack(aw3a, svrec);
		Attack(aw3b, svrec);
		Attack(aw3c, svrec);
		SetIndependence(aw3a, 1);
		SetIndependence(aw3b, 1);
		SetIndependence(aw3c, 1);
		aw3sent = true;
	}*/]=]
    if ((not IsAlive(M.colorado)) and (M.coloradodestroyed == false)) then
        M.coloradodestroyed = true
        M.wave1 = GetTime() + 180.0
    end
    if ((not IsAlive(M.muf)) and (M.mufdestroyed == false)) then
        AudioMessage("misns108.wav")
        M.mufdestroyed = true
        M.possible1 = true
    end
    if ((not IsAlive(M.silo)) and (M.silodestroyed == false)) then
        M.possible2 = true
        AudioMessage("misns107.wav")
        M.silodestroyed = true
    end
    if ((M.possible1 == true) and (M.possible2 == true)) then
        M.newobjective = true
    end
    if ((M.mufdestroyed == true) and (M.silodestroyed == true) and (M.coloradodestroyed == true) and (M.missionwon == false)) then
        M.newobjective = true
        M.missionwon = true
    end
    if ((M.missionwon == true) and (M.finish == false)) then
        M.aud1 = AudioMessage("misns110.wav")
        M.finish = true
    end
    if ((M.finish == true) and (AudioDone(M.aud1))) then
        -- BUG FIX: issue this outcome once, at the first source-eligible frame.
        -- No delay, precedence, or other branch is changed. The latch is saved.
        if not M.success_called then
            M.success_called = true
            SucceedMission(GetTime(), "misns1w1.des")
        end
    end
    if ((M.enterwarning == false) and (MissionDistance(M.colorado, M.walkcam1) < 70.0)) then
        if (M.path == 0) then
            AudioMessage("misns117.wav")
            M.enterwarning = true
        end
        if (M.path == 1) then
            AudioMessage("misns116.wav")
            M.enterwarning = true
        end
        if (M.path == 2) then
            AudioMessage("misns115.wav")
            M.enterwarning = true
        end
    end
    if ((MissionDistance(M.colorado, "halfwayupper") < 100.0) and (M.halfwaywarn == false)) then
        M.halfwaywarn = true
        AudioMessage("misns102.wav")
    end
    if ((MissionDistance(M.colorado, "halfwaymid") < 100.0) and (M.halfwaywarn == false)) then
        M.halfwaywarn = true
        AudioMessage("misns103.wav")
    end
    if ((MissionDistance(M.colorado, "halfwaylower") < 100.0) and (M.halfwaywarn == false)) then
        M.halfwaywarn = true
        AudioMessage("misns104.wav")
    end
    --[=[// I know succeds is not the correct spelling but it was easier to leave it then to change it.  I'm not dumb.  I'm just lazy. hehe]=]
    if ((M.blockaderun == true) and (MissionDistance(M.colorado, "safepoint") < 60.0) and (M.coloradoreachedsafepoint == false)) then
        M.aud20 = AudioMessage("misns109.wav")
        M.aud21 = AudioMessage("misns111.wav")
        M.coloradoreachedsafepoint = true
        M.newobjective = true
        CameraReady()
        -- BUG FIX: geyser2's lookup is commented out, so the source's
        -- CameraObject(geyser2, 1200, 500, 1200, colorado) has no anchor.
        -- Prefer that anchor if restored later; otherwise use the escaping
        -- recycler for this loss shot. Only framing changes; failure still
        -- waits for both original radio messages, with unchanged triggers.
        local anchor = Valid(M.geyser2) and M.geyser2 or M.colorado
        if Valid(anchor) and Valid(M.colorado) then
            CameraObject(anchor, 1200, 500, 1200, M.colorado)
        end
    end
    if ((M.coloradoreachedsafepoint == true) and (AudioDone(M.aud20)) and (AudioDone(M.aud21))) then
        -- BUG FIX: issue this outcome once, at the first source-eligible frame.
        -- No delay, precedence, or other branch is changed. The latch is saved.
        if not M.escape_failure_called then
            M.escape_failure_called = true
            FailMission(GetTime(), "misns1l1.des")
        end
    end
    if ((not IsAlive(M.svrec)) and (M.missionfail == false)) then
        M.aud22 = AudioMessage("misns112.wav")
        M.aud23 = AudioMessage("misns113.wav")
        M.missionfail = true
        M.newobjective = true
    end
    if ((M.missionfail == true) and (AudioDone(M.aud22)) and (AudioDone(M.aud23))) then
        -- BUG FIX: issue this outcome once, at the first source-eligible frame.
        -- No delay, precedence, or other branch is changed. The latch is saved.
        if not M.recycler_failure_called then
            M.recycler_failure_called = true
            FailMission(GetTime(), "misns1l2.des")
        end
    end
    if ((M.wave1 < GetTime()) and (M.cavalry == false)) then
        M.wave1 = 99999999999.0
        M.cavalry = true
        M.cav1 = BuildObject("avfigh", 2, "cavspawn")
        M.cav2 = BuildObject("avtank", 2, "cavspawn")
        M.cav3 = BuildObject("avfigh", 2, "cavspawn")
        --[=[//cav4 = BuildObject ("avtank", 2, "cavspawn");]=]
        --[=[//cav5 = BuildObject ("avtank", 2, "cavspawn");]=]
        AudioMessage("misns122.wav")
    end
    if ((M.cavalry == true) and (M.cavsent == false)) then
        if M.cav == 0 then
            MissionGoto(M.cav1, "cavpath1")
            MissionGoto(M.cav2, "cavpath1")
            MissionGoto(M.cav3, "cavpath1")
            --[=[//Goto (cav4, "cavpath1");]=]
            --[=[//Goto (cav5, "cavpath1");]=]
            M.cavpath1 = true
        elseif M.cav == 1 then
            MissionGoto(M.cav1, "cavpath2")
            MissionGoto(M.cav2, "cavpath2")
            MissionGoto(M.cav3, "cavpath2")
            --[=[//Goto (cav4, "cavpath2");]=]
            --[=[//Goto (cav5, "cavpath2");]=]
            M.cavpath2 = true
        elseif M.cav == 2 then
            MissionGoto(M.cav1, "cavpath1")
            MissionGoto(M.cav2, "cavpath1")
            MissionGoto(M.cav3, "cavpath1")
            --[=[//Goto (cav4, "cavpath1");]=]
            --[=[//Goto (cav5, "cavpath1");]=]
            M.cavpath1 = true
        elseif M.cav == 3 then
            MissionGoto(M.cav1, "cavpath2")
            MissionGoto(M.cav2, "cavpath2")
            MissionGoto(M.cav3, "cavpath2")
            --[=[//Goto (cav4, "cavpath2");]=]
            --[=[//Goto (cav5, "cavpath2");]=]
            M.cavpath2 = true
        end
        M.cavsent = true
    end
    --[=[//||]=]
    --[=[//(GetDistance (cav4, walkcam1) < 200.0f) ||]=]
    --[=[//(GetDistance (cav5, walkcam1) < 200.0f)]=]
    if ((M.cavpath1 == true) and ((MissionDistance(M.cav1, M.walkcam1) < 200.0) or (MissionDistance(M.cav2, M.walkcam1) < 200.0) or (MissionDistance(M.cav3, M.walkcam1) < 200.0)) and (M.cav1pathwarn1 == false)) then
        AudioMessage("misns118.wav")
        M.cav1pathwarn1 = true
    end
    --[=[//||]=]
    --[=[//(GetDistance (cav4, walkcam2) < 50.0f) ||]=]
    --[=[//(GetDistance (cav5, walkcam2) < 50.0f)]=]
    if ((M.cavpath2 == true) and ((MissionDistance(M.cav1, M.walkcam2) < 50.0) or (MissionDistance(M.cav2, M.walkcam2) < 50.0) or (MissionDistance(M.cav3, M.walkcam2) < 50.0)) and (M.cav2pathwarn1 == false)) then
        AudioMessage("misns119.wav")
        M.cav2pathwarn1 = true
    end
    --[=[/*if 
		(
		(cavpath3 == true) && 
		(
		(GetDistance (cav1, walkcam1) < 200.0f) ||
		(GetDistance (cav2, walkcam1) < 200.0f) ||
		(GetDistance (cav3, walkcam1) < 200.0f) ||
		(GetDistance (cav4, walkcam1) < 200.0f) ||
		(GetDistance (cav5, walkcam1) < 200.0f)
		) && (cav3pathwarn1 == false)
		)
	{
		AudioMessage("misns118.wav");
		cav3pathwarn1 = true;
	}

	if 
		(
		(cavpath3 == true) && 
		(
		(GetDistance (cav1, hidcam2) < 60.0f) ||
		(GetDistance (cav2, hidcam2) < 60.0f) ||
		(GetDistance (cav3, hidcam2) < 60.0f) ||
		(GetDistance (cav4, hidcam2) < 60.0f) ||
		(GetDistance (cav5, hidcam2) < 60.0f)
		) && (cav3pathwarn2 == false)
		)
	{
		AudioMessage("misns120.wav");
		cav3pathwarn2 = true;
	}
	
	if 
		(
		(cavpath4 == true) && 
		(
		(GetDistance (cav1, walkcam2) < 50.0f) ||
		(GetDistance (cav2, walkcam2) < 50.0f) ||
		(GetDistance (cav3, walkcam2) < 50.0f) ||
		(GetDistance (cav4, walkcam2) < 50.0f) ||
		(GetDistance (cav5, walkcam2) < 50.0f)
		) && (cav4pathwarn1 == false)
		)
	{
		AudioMessage("misns119.wav");
		cav4pathwarn1 = true;
	}

	if 
		(
		(cavpath4 == true) && 
		(
		(GetDistance (cav1, hidcam1) < 100.0f) ||
		(GetDistance (cav2, hidcam1) < 100.0f) ||
		(GetDistance (cav3, hidcam1) < 100.0f) ||
		(GetDistance (cav4, hidcam1) < 100.0f) ||
		(GetDistance (cav5, hidcam1) < 100.0f)
		) && (cav4pathwarn2 == false)
		)
	{
		AudioMessage("misns121.wav");
		cav4pathwarn2 = true;
	}*/]=]
end
