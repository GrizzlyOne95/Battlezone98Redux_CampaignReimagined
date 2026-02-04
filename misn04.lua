-- Misn04 Mission Script (Converted from Misn04Mission.cpp)

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
    DiffUtils.SetupTeams(aiCore.Factions.NSDF, aiCore.Factions.CCA, 2)
end

-- Variables
local missionstart = false
local warn = 0
local safety = 0
local retreat = false
local surveysent = false
local reconsent = false
local firstwave = false
local secondwave = false
local thirdwave = false
local fourthwave = false
local fifthwave = false
local discrelic = false
local ccatugsent = false
local attackccabase = false
local ccabasedestroyed = false
local fifthwavedestroyed = false
local missionend = false
local wavenumber = 1
local missionwon = false
local wave1dead = false
local wave2dead = false
local wave3dead = false
local wave4dead = false
local wave5dead = false
local possiblewin = false
local loopbreak = false
local basesecure = false
local newobjective = false
local relicsecure = false
local discoverrelic = false
local missionfail2 = false
local aud10 = 0
local aud11 = 0
local aud12 = 0
local aud13 = 0
local aud14 = 0
local ccahasrelic = false
local relicseen = false
local obset = false
local wave1 = 0
local wave2 = 99999.0
local wave3 = 99999.0
local wave4 = 99999.0
local wave5 = 99999.0
local endcindone = 999999.0
local startendcin = 999999.0
local ccatug = 999999999999.0
local notfound = 999999999999999.0
local build2 = false
local build3 = false
local build4 = false
local build5 = false
local halfway = false

-- Handles
local svrec, pu1, pu2, pu3, pu4, pu5, pu6, pu7, pu8, navbeacon
local cheat1, cheat2, cheat3, cheat4, cheat5, cheat6, cheat7, cheat8, cheat9, cheat10
local tug, svtug, tuge1, tuge2
local player, surv1, surv2, surv3, surv4
local cam1, cam2, cam3, basecam, reliccam
local avrec, w1u1, w1u2
local w2u1, w2u2, w2u3
local w3u1, w3u2, w3u3, w3u4
local w4u1, w4u2, w4u3, w4u4, w4u5
local w5u1, w5u2, w5u3, w5u4, w5u5, w5u6
local spawn1, spawn2, spawn3, relic
local calipso, turret1, turret2, turret3, turret4

local aud1, aud2, aud3, aud4, aud20, aud21, aud22, aud23

local doneaud20 = false
local doneaud21 = false
local doneaud22 = false
local doneaud23 = false
local done = false
local secureloopbreak = false
local found = false
local endcinfinish = false
local loopbreak2 = false
-- ob1..ob8 in C++ were true but seemingly unused or just flags. Include if needed.
local investigate = 999999999.0
local investigator = 0
local tur1 = 999999999.0
local tur2 = 999999999.0
local tur3 = 999999999.0
local tur4 = 999999999.0
local tur1sent = false
local tur2sent = false
local tur3sent = false
local tur4sent = false
local cin1done = false
local missionfail = false
local chewedout = false
local relicmoved = false
local height = 500
local cintime1 = 9999999999.0
local fetch = 0
local reconcca = 0
local relicstartpos = 0
local cheater = false
local difficulty = 2 -- Default Medium

function Start()
	-- One-time initialization logic
	relicstartpos = math.random(0, 3)
	
    -- EXU/QOL Setup
    if exu then
        local ver = (type(exu.GetVersion) == "function" and exu.GetVersion()) or exu.version or "Unknown"
        print("EXU Version: " .. tostring(ver))
        difficulty = (exu.GetDifficulty and exu.GetDifficulty()) or 2
        print("Difficulty: " .. tostring(difficulty))

        if difficulty >= 3 then
            AddObjective("hard_diff", "red", 8.0, "High Difficulty: Enemy presence intensified.")
        elseif difficulty <= 1 then
            AddObjective("easy_diff", "green", 8.0, "Low Difficulty: Enemy presence reduced.")
        end

        if exu.EnableShotConvergence then exu.EnableShotConvergence() end
        if exu.SetSmartCursorRange then exu.SetSmartCursorRange(500) end
        if exu.EnableOrdnanceTweak then exu.EnableOrdnanceTweak(1.0) end
        if exu.SetSelectNone then exu.SetSelectNone(false) end
    end

    -- Dynamic Starting Resources
    SetScrap(1, DiffUtils.ScaleRes(20))
    SetPilot(1, DiffUtils.ScaleRes(10))
    
    SetupAI() -- Initialize AI
end

function AddObject(h)
    local team = GetTeamNum(h)

	-- void Misn04Mission::AddObject(Handle h) logic
	if (team == 1) and (IsOdf(h, "avhaul")) then
		found = true
		tug = h
	end

    -- aiCore and DiffUtils handle Team 1 enhancements and Turbo automatically
    
    -- AI Core Hook (Safeguarded)
    if team == 2 then
        -- Only register if near production buildings (prevent hijacking scripted waves)
        local coreUnits = {GetRecyclerHandle(2), GetFactoryHandle(2), GetConstructorHandle(2), GetArmoryHandle(2)}
        local nearBase = false
        
        -- Check distance to key buildings
        for _, prod in ipairs(coreUnits) do
            if IsValid(prod) and GetDistance(h, prod) < 150 then
                nearBase = true
                break
            end
        end
        
        -- Also include the buildings themselves
        for _, prod in ipairs(coreUnits) do
            if h == prod then nearBase = true break end
        end
        
        if nearBase then
            aiCore.AddObject(h)
        end
    end
end

function DeleteObject(h)
	-- No specific logic in C++, just standard.
end

function Update()
	-- void Misn04Mission::Execute(void) logic
	
	player = GetPlayerHandle()
	player = GetPlayerHandle()
    if exu and exu.UpdateOrdnance then exu.UpdateOrdnance() end
    
    aiCore.Update()
	
	if (not missionstart) then
		wave1 = GetTime() + DiffUtils.ScaleTimer(30.0) + math.random(-5, 10)
		fetch = GetTime() + DiffUtils.ScaleTimer(240.0)
		AudioMessage("misn0401.wav")
		cam1 = GetHandle("apcamr352_camerapod")
		cam2 = GetHandle("apcamr350_camerapod")
		cam3 = GetHandle("apcamr351_camerapod")
		basecam = GetHandle("apcamr-1_camerapod")
		svrec = GetHandle("svrecy-1_recycler")
		avrec = GetHandle("avrecy-1_recycler")
		relic = BuildObject("obdata", 0, "relicstart1")
		pu1 = GetHandle("svfigh-1_wingman")
		-- pu2 commented out in C++
		pu3 = GetHandle("svfigh282_wingman")
		-- pu4, pu5 commented out
		pu6 = GetHandle("svfigh279_wingman")
		-- pu7 commented out
		pu8 = GetHandle("svfigh278_wingman")
		
		SetObjectiveName(cam1, "SW Geyser")
		SetObjectiveName(cam2, "NW Geyser")
		SetObjectiveName(cam3, "NE Geyser")
		SetObjectiveName(basecam, "CCA Base")
		
		Patrol(pu1, "innerpatrol")
		Patrol(pu3, "innerpatrol")
		Patrol(pu6, "outerpatrol")
		Patrol(pu8, "scouting")
		
		AddObjective("misn0401.otf", "white")
		AddObjective("misn0400.otf", "white")
		
		missionstart = true
		cheater = false
		-- relicstartpos already set in Start() to random
		
		tur1 = GetTime() + DiffUtils.ScaleTimer(30.0)
		tur2 = GetTime() + DiffUtils.ScaleTimer(45.0) + math.random(0, 5)
		tur3 = GetTime() + DiffUtils.ScaleTimer(60.0) + math.random(5, 10)
		tur4 = GetTime() + DiffUtils.ScaleTimer(75.0) + math.random(10, 15)
		investigate = GetTime() + 3.0
	end
	
	-- Keep updating player just in case
	player = GetPlayerHandle()
	
	AddHealth(cam1, 1000)
	AddHealth(cam2, 1000)
	AddHealth(cam3, 1000)
	
	-- Relic placement
	if (not relicmoved) then
		if relicstartpos == 0 then
			SetPosition(relic, "relicstart1")
		elseif relicstartpos == 1 then
			SetPosition(relic, "relicstart2")
		elseif relicstartpos == 2 then
			SetPosition(relic, "relicstart3")
		elseif relicstartpos == 3 then
			SetPosition(relic, "relicstart4")
		end
		relicmoved = true
	end
	
	-- Cheater spawns (player finds relic early)
	if (not reconsent) and (not cheater) and (GetDistance(player, relic) < 600.0) then
		cheat1 = BuildObject("svfigh", 2, relic)
		cheat2 = BuildObject("svfigh", 2, relic)
		cheat3 = BuildObject("svfigh", 2, relic)
		cheat4 = BuildObject("svfigh", 2, relic)
		cheat5 = BuildObject("svfigh", 2, relic)
		cheat6 = BuildObject("svfigh", 2, relic)
		
		local pathA, pathB = "", ""
		if relicstartpos == 0 then
			pathA = "relicpatrolpath1a"
			pathB = "relicpatrolpath1b"
		elseif relicstartpos == 1 then
			pathA = "relicpatrolpath2a"
			pathB = "relicpatrolpath2b"
		elseif relicstartpos == 2 then
			pathA = "relicpatrolpath3a"
			pathB = "relicpatrolpath3b"
		elseif relicstartpos == 3 then
			pathA = "relicpatrolpath4a"
			pathB = "relicpatrolpath4b"
		end
		
		Patrol(cheat1, pathA)
		Patrol(cheat2, pathA)
		Patrol(cheat3, pathA)
		Patrol(cheat4, pathB)
		Patrol(cheat5, pathB)
		Patrol(cheat6, pathB)
		
		SetIndependence(cheat1, 1)
		SetIndependence(cheat2, 1)
		SetIndependence(cheat3, 1)
		SetIndependence(cheat4, 1)
		SetIndependence(cheat5, 1)
		SetIndependence(cheat6, 1)
		
		surveysent = true
		cheater = true
		reconcca = GetTime() -- Immediate recon
	end
	
	-- Survey sent logic (timed)
	if (fetch < GetTime()) and (not surveysent) then
		surv1 = BuildObject("svfigh", 2, relic)
		surv2 = BuildObject("svfigh", 2, relic)
		
		local pathA, pathB = "", ""
		if relicstartpos == 0 then
			pathA = "relicpatrolpath1a"
			pathB = "relicpatrolpath1b"
		elseif relicstartpos == 1 then
			pathA = "relicpatrolpath2a"
			pathB = "relicpatrolpath2b"
		elseif relicstartpos == 2 then
			pathA = "relicpatrolpath3a"
			pathB = "relicpatrolpath3b"
		elseif relicstartpos == 3 then
			pathA = "relicpatrolpath4a"
			pathB = "relicpatrolpath4b"
		end
		
		Patrol(surv1, pathA)
		Patrol(surv2, pathB)
		SetIndependence(surv1, 1)
		SetIndependence(surv2, 1)
		
		surveysent = true
		reconcca = GetTime() + DiffUtils.ScaleTimer(60.0)
	end
	
	-- Turret spawning logic
	if (not tur1sent) and (tur1 < GetTime()) and IsAlive(svrec) then
		turret1 = BuildObject("svturr", 2, svrec)
		Goto(turret1, "turret1")
		tur1sent = true
	end
	if (not tur2sent) and (tur2 < GetTime()) and IsAlive(svrec) then
		turret2 = BuildObject("svturr", 2, svrec)
		Goto(turret2, "turret2")
		tur2sent = true
	end
	if (not tur3sent) and (tur3 < GetTime()) and IsAlive(svrec) then
		turret3 = BuildObject("svturr", 2, svrec)
		Goto(turret3, "turret3")
		tur3sent = true
	end
	if (not tur4sent) and (tur4 < GetTime()) and IsAlive(svrec) then
		turret4 = BuildObject("svturr", 2, svrec)
		Goto(turret4, "turret4")
		tur4sent = true
	end
	
	-- Recon CCA Logic
	if (reconcca < GetTime()) and (not reconsent) and (surveysent) then
		aud4 = AudioMessage("misn0406.wav")
		if relicstartpos == 0 then
			reliccam = BuildObject("apcamr", 1, "reliccam1")
		elseif relicstartpos == 1 then
			reliccam = BuildObject("apcamr", 1, "reliccam2")
		elseif relicstartpos == 2 then
			reliccam = BuildObject("apcamr", 1, "reliccam3")
		elseif relicstartpos == 3 then
			reliccam = BuildObject("apcamr", 1, "reliccam4")
		end
		
		reconsent = true
		obset = true
		notfound = GetTime() + 90.0
	end
	
	if (obset) and IsAudioMessageDone(aud4) then
		SetObjectiveName(reliccam, "Investigate CCA")
		newobjective = true
		obset = false
	end
	
	-- Found relic logic
	if (found) and (not halfway) then
		if HasCargo(tug) then
			AudioMessage("misn0419.wav")
			halfway = true
			SetObjectiveOff(relic)
			if IsAlive(tuge1) then Attack(tuge1, tug) end
			if IsAlive(tuge2) then Attack(tuge2, tug) end
		end
	end
	
	-- Relic secure check (delivered to recycler)
	if (reconsent) then
		if (GetDistance(relic, avrec) < 100.0) and (not relicsecure) then
			aud23 = AudioMessage("misn0420.wav")
			relicsecure = true
			newobjective = true
		end
	end
	
	-- CCA Tug Logic
	if (ccatug < GetTime()) and (not ccatugsent) and IsAlive(svrec) then
		svtug = BuildObject("svhaul", 2, svrec)
		tuge1 = BuildObject("svfigh", 2, svrec)
		tuge2 = BuildObject("svfigh", 2, svrec)
		Pickup(svtug, relic)
		Follow(tuge1, svtug)
		Follow(tuge2, svtug)
		ccatugsent = true
	end
	
	if (ccatugsent) and (not ccahasrelic) then
		if IsAlive(svtug) then
			if HasCargo(svtug) and (not HasCargo(tug)) then
				ccahasrelic = true
				Goto(svtug, "dropoff")
				AudioMessage("misn0427.wav")
				SetObjectiveOn(svtug)
				SetObjectiveName(svtug, "CCA Tug")
			end
		end
	end
	
	if (ccahasrelic) and (GetDistance(svtug, svrec) < 60.0) and (not missionfail2) then
		aud10 = AudioMessage("misn0431.wav")
		aud11 = AudioMessage("misn0432.wav")
		aud12 = AudioMessage("misn0433.wav")
		aud13 = AudioMessage("misn0434.wav")
		missionfail2 = true
		CameraReady()
	end
	
	if (missionfail2) and (not done) then
		CameraPath("ccareliccam", 3000, 1000, svtug)
		if (IsAudioMessageDone(aud10) and IsAudioMessageDone(aud11) and IsAudioMessageDone(aud12) and IsAudioMessageDone(aud13)) or CameraCancelled() then
			CameraFinish()
			StopAudioMessage(aud10)
			StopAudioMessage(aud11)
			StopAudioMessage(aud12)
			StopAudioMessage(aud13)
			FailMission(GetTime(), "misn04l1.des")
			done = true
		end
	end
	
	-- Warning logic if not found
	if (not discoverrelic) and (reconsent) and (notfound < GetTime()) and (not ccahasrelic) and (warn < 4) then
		AudioMessage("misn0429.wav")
		notfound = GetTime() + DiffUtils.ScaleTimer(85.0)
		warn = warn + 1
	end
	
	if (warn == 4) and (notfound < GetTime()) and (not missionfail) then
		aud14 = AudioMessage("misn0694.wav")
		missionfail = true
	end
	if (missionfail) then
		if (warn == 4) and IsAudioMessageDone(aud14) then
			FailMission(GetTime(), "misn04l4.des")
			warn = 0
		end
	end
	
	-- Discover Relic logic (Investigator count)
	if (not discoverrelic) then
		if (investigate < GetTime()) then
			investigator = CountUnitsNearObject(relic, 400.0, 1, nil)
			if IsAlive(reliccam) then
				investigator = investigator - 1
			end
		end
		
		if (investigator >= 1) then
			aud2 = AudioMessage("misn0408.wav")
			aud3 = AudioMessage("misn0409.wav")
			relicseen = true
			newobjective = true
			ccatug = GetTime() + DiffUtils.ScaleTimer(200.0) + math.random(-5, 10)
			discoverrelic = true
			CameraReady()
			cintime1 = GetTime() + 23.0
		end
	end
	
	-- Cinematic Logic for Discovery
	if (discoverrelic) and (not cin1done) then
		if (discoverrelic and IsAudioMessageDone(aud2) and IsAudioMessageDone(aud3)) or CameraCancelled() then
			CameraFinish()
			StopAudioMessage(aud2)
			StopAudioMessage(aud3)
			cin1done = true
		end
	end
	
	if (discoverrelic) and (cintime1 > GetTime()) and (not cin1done) then
		if relicstartpos == 0 then CameraPath("reliccin1", 500, 400, relic)
		elseif relicstartpos == 1 then CameraPath("reliccin2", 500, 400, relic)
		elseif relicstartpos == 2 then CameraPath("reliccin3", 500, 400, relic)
		elseif relicstartpos == 3 then CameraPath("reliccin4", 500, 400, relic)
		end
	end
	
	-- Objective Updates
	if (newobjective) then
		ClearObjectives()
		if (not basesecure) then AddObjective("misn0401.otf", "white") end
		if (basesecure) then AddObjective("misn0401.otf", "green") end
		
		if (not relicsecure) and (relicseen) then AddObjective("misn0403.otf", "white") end
		if (relicsecure) then AddObjective("misn0403.otf", "green") end
		
		if (reconsent) and (not discoverrelic) then AddObjective("misn0405.otf", "white") end
		if (discoverrelic) then AddObjective("misn0405.otf", "green") end
		
		newobjective = false
	end
	
	-- Wave Logic
	if (wavenumber == 1) then
		-- Just checking liveness (noop in C++)
	end
	
	if (wavenumber == 1) and (GetTime() > wave1) then
		w1u1 = BuildObject("svfigh", 2, "wave1")
		w1u2 = BuildObject("svfigh", 2, "wave1")
		Attack(w1u1, avrec, 1)
		Attack(w1u2, avrec, 1)
		
		for i=1, DiffUtils.ScaleEnemy(1)-1 do
			local h = BuildObject("svfigh", 2, "wave1"); Attack(h, avrec, 1); SetIndependence(h, 1)
		end

		SetIndependence(w1u1, 1)
		SetIndependence(w1u2, 1)
		wavenumber = 2
		wave1arrive = false
	end
	
	if (wavenumber == 2) and (not IsAlive(w1u1)) and (not IsAlive(w1u2)) and (not build2) then
		wave2 = GetTime() + DiffUtils.ScaleTimer(60.0) + math.random(-5, 5)
		build2 = true
		wave1dead = true
	end
	
	if (wave2 < GetTime()) and IsAlive(svrec) then
        local type2 = "svltnk"
        if difficulty <= 1 then type2 = "svfigh" end

		w2u1 = BuildObject(type2, 2, "spawn2new")
		w2u2 = BuildObject("svfigh", 2, "spawn2new")
		Goto(w2u1, avrec, 1)
		Goto(w2u2, avrec, 1)
		SetIndependence(w2u1, 1)
		SetIndependence(w2u2, 1)
		wavenumber = 3
		wave2arrive = false
		wave2 = 99999.0
	end
	
	if (wavenumber == 3) and (not IsAlive(w2u1)) and (not IsAlive(w2u2)) and (not build3) then
		wave3 = GetTime() + DiffUtils.ScaleTimer(74.0) + math.random(-10, 10)
		build3 = true
		wave2dead = true
	end
	
	if (wave3 < GetTime()) and IsAlive(svrec) then
        local type3 = "svfigh"
        if difficulty >= 2 then type3 = "svltnk" end

		w3u1 = BuildObject(type3, 2, svrec)
		w3u2 = BuildObject("svfigh", 2, svrec)
		w3u3 = BuildObject("svfigh", 2, svrec)
		Goto(w3u1, avrec, 1)
		Goto(w3u2, avrec, 1)
		Goto(w3u3, avrec, 1)
		SetIndependence(w3u1, 1)
		SetIndependence(w3u2, 1)
		SetIndependence(w3u3, 1)
		wavenumber = 4
		wave3arrive = false
		wave3 = 99999.0
	end
	
	if (wavenumber == 4) and (not IsAlive(w3u1)) and (not IsAlive(w3u2)) and (not IsAlive(w3u3)) and (not build4) then
		wave4 = GetTime() + DiffUtils.ScaleTimer(60.0) + math.random(-5, 5)
		build4 = true
		wave3dead = true
	end
	
	if (wave4 < GetTime()) and IsAlive(svrec) then
        local type4 = "svtank"
        if difficulty <= 1 then type4 = "svltnk" end

		w4u1 = BuildObject(type4, 2, "spawnotherside")
		w4u2 = BuildObject("svfigh", 2, "spawnotherside")
		w4u3 = BuildObject("svfigh", 2, "spawnotherside")
		Goto(w4u1, avrec, 1)
		Goto(w4u2, avrec, 1)
		Goto(w4u3, avrec, 1)
		SetIndependence(w4u1, 1)
		SetIndependence(w4u2, 1)
		SetIndependence(w4u3, 1)
		wavenumber = 5
		wave4arrive = false
		wave4 = 99999.0
	end
	
	if (wavenumber == 5) and (not IsAlive(w4u1)) and (not IsAlive(w4u2)) and (not IsAlive(w4u3)) and (not build5) then
		wave5 = GetTime() + DiffUtils.ScaleTimer(30.0) + math.random(-2, 8)
		build5 = true
		wave4dead = true
	end
	
	if (wave5 < GetTime()) and IsAlive(svrec) then
		w5u1 = BuildObject("svtank", 2, svrec)
		w5u2 = BuildObject("svfigh", 2, svrec)
		w5u3 = BuildObject("svfigh", 2, svrec)
		w5u4 = BuildObject("svfigh", 2, svrec)
		Goto(w5u1, avrec, 1)
		Goto(w5u2, avrec, 1)
		Goto(w5u3, avrec, 1)
		Goto(w5u4, avrec, 1)
		SetIndependence(w5u1, 1)
		SetIndependence(w5u2, 1)
		SetIndependence(w5u3, 1)
		SetIndependence(w5u4, 1)
		wavenumber = 6
		wave5arrive = false
		wave5 = 99999.0
	end
	
	-- Wave Arrival Audio
	if (not wave1arrive) and IsAlive(avrec) then
		if (GetDistance(avrec, w1u1) < 300.0) or (GetDistance(avrec, w1u2) < 300.0) then
			AudioMessage("misn0402.wav")
			wave1arrive = true
			wave1dead = true 
		end
	end
	
	if (not wave2arrive) and IsAlive(avrec) then
		if (GetDistance(avrec, w2u1) < 300.0) or (GetDistance(avrec, w2u2) < 300.0) then
			AudioMessage("misn0404.wav")
			wave2arrive = true
		end
	end
	if (not wave3arrive) and IsAlive(avrec) then
		if (GetDistance(avrec, w3u1) < 300.0) or (GetDistance(avrec, w3u2) < 300.0) or (GetDistance(avrec, w3u3) < 300.0) then
			AudioMessage("misn0410.wav")
			wave3arrive = true
		end
	end
	if (not wave4arrive) and IsAlive(avrec) then
		if (GetDistance(avrec, w4u1) < 300.0) or (GetDistance(avrec, w4u2) < 300.0) or (GetDistance(avrec, w4u3) < 300.0) then
			AudioMessage("misn0412.wav")
			wave4arrive = true
		end
	end
	if (not wave5arrive) and IsAlive(avrec) then
		if (GetDistance(avrec, w5u1) < 300.0) or (GetDistance(avrec, w5u2) < 300.0) or (GetDistance(avrec, w5u3) < 300.0) or (GetDistance(avrec, w5u4) < 300.0) then
			AudioMessage("misn0414.wav")
			wave5arrive = true
		end
	end
	
	if (not attackccabase) and (GetDistance(player, svrec) < 300.0) then
		AudioMessage("misn0423.wav")
		attackccabase = true
	end
	
	-- Wave Dead Audio
	if (wave1dead) and (not IsAlive(w1u1)) and (not IsAlive(w1u2)) then
		AudioMessage("misn0403.wav")
		wave1dead = false
	end
	if (wave2dead) then
		AudioMessage("misn0405.wav")
		wave2dead = false
	end
	if (wave3dead) then
		AudioMessage("misn0411.wav")
		wave3dead = false
	end
	if (wave4dead) then
		AudioMessage("misn0413.wav")
		wave4dead = false
	end
	
	-- Chewed out logic (all fail)
	if (not loopbreak) and (not possiblewin) and (not missionwon) and (not IsAlive(svrec)) then
		AudioMessage("misn0417.wav")
		possiblewin = true
		chewedout = true
		
		-- Check if any enemies remain
		if (not IsAlive(svrec)) and 
			(IsAlive(w1u1) or IsAlive(w1u2) or IsAlive(w2u1) or IsAlive(w2u2) or
			 IsAlive(w3u1) or IsAlive(w3u2) or IsAlive(w3u3) or
			 IsAlive(w4u1) or IsAlive(w4u2) or IsAlive(w4u3) or
			 IsAlive(w5u1) or IsAlive(w5u2) or IsAlive(w5u3) or IsAlive(w5u4)) then
			 AudioMessage("misn0418.wav")
			 loopbreak = true
		end
	end
	
	-- Base Secure Logic
	if (not basesecure) and (not IsAlive(svrec)) and
		(not IsAlive(w1u1)) and (not IsAlive(w1u2)) and
		(not IsAlive(w2u1)) and (not IsAlive(w2u2)) and
		(not IsAlive(w3u1)) and (not IsAlive(w3u2)) and (not IsAlive(w3u3)) and
		(not IsAlive(w4u1)) and (not IsAlive(w4u2)) and (not IsAlive(w4u3)) and
		(not IsAlive(w5u1)) and (not IsAlive(w5u2)) and (not IsAlive(w5u3)) and (not IsAlive(w5u4)) then
		basesecure = true
		newobjective = true
	end
	
	if (relicsecure) and (basesecure) then
		missionwon = true
	end
	
	if (missionwon) and (not endmission) then
		if (IsAudioMessageDone(aud20) and IsAudioMessageDone(aud21) and IsAudioMessageDone(aud22) and IsAudioMessageDone(aud23)) then
			SucceedMission(GetTime(), "misn04w1.des")
		end
	end
	
	if (not missionwon) and (not IsAlive(avrec)) and (not missionfail) then
		AudioMessage("misn0421.wav")
		AudioMessage("misn0422.wav")
		missionfail = true
		FailMission(GetTime() + 20.0, "misn04l3.des")
	end
	
	-- Retreat Logic
	if (not basesecure) and (not secureloopbreak) and (wavenumber == 6) and
		(not IsAlive(w5u1)) and (not IsAlive(w5u2)) and (not IsAlive(w5u3)) and (not IsAlive(w5u4)) and
		IsAlive(svrec) then
		
		if (not retreat) then
			if IsAlive(tuge1) then Retreat(tuge1, "retreatpoint") end
			if IsAlive(tuge2) then Retreat(tuge2, "retreatpoint28") end
			if IsAlive(pu1) then Retreat(pu1, "retreatpoint27") end
			if IsAlive(pu2) then Retreat(pu2, "retreatpoint26") end
			if IsAlive(pu3) then Retreat(pu3, "retreatpoint25") end
			if IsAlive(pu4) then Retreat(pu4, "retreatpoint24") end
			if IsAlive(pu5) then Retreat(pu5, "retreatpoint23") end
			if IsAlive(pu6) then Retreat(pu6, "retreatpoint22") end
			if IsAlive(pu7) then Retreat(pu7, "retreatpoint21") end
			if IsAlive(pu8) then Retreat(pu8, "retreatpoint20") end
			if IsAlive(cheat1) then Retreat(cheat1, "retreatpoint19") end
			if IsAlive(cheat2) then Retreat(cheat2, "retreatpoint18") end
			if IsAlive(cheat3) then Retreat(cheat3, "retreatpoint17") end
			if IsAlive(cheat4) then Retreat(cheat4, "retreatpoint16") end
			if IsAlive(cheat5) then Retreat(cheat5, "retreatpoint15") end
			if IsAlive(cheat6) then Retreat(cheat6, "retreatpoint14") end
			if IsAlive(cheat7) then Retreat(cheat7, "retreatpoint13") end
			if IsAlive(cheat8) then Retreat(cheat8, "retreatpoint12") end
			if IsAlive(cheat9) then Retreat(cheat9, "retreatpoint11") end
			if IsAlive(cheat10) then Retreat(cheat10, "retreatpoint10") end
			if IsAlive(surv1) then Retreat(surv1, "retreatpoint9") end
			if IsAlive(surv2) then Retreat(surv2, "retreatpoint8") end
			if IsAlive(surv3) then Retreat(surv3, "retreatpoint7") end
			if IsAlive(surv4) then Retreat(surv4, "retreatpoint6") end
			if IsAlive(turret1) then Retreat(turret1, "retreatpoint2") end
			if IsAlive(turret2) then Retreat(turret2, "retreatpoint3") end
			if IsAlive(turret3) then Retreat(turret3, "retreatpoint4") end
			if IsAlive(turret4) then Retreat(turret4, "retreatpoint5") end
			retreat = true
		end
		
		aud21 = AudioMessage("misn0415.wav")
		aud22 = AudioMessage("misn0416.wav")
		basesecure = true
		newobjective = true
		secureloopbreak = true
	end
	
	if (not IsAlive(relic)) and (not missionfail) then
		FailMission(GetTime() + 20.0, "misn04l2.des")
		AudioMessage("misn0431.wav")
		AudioMessage("misn0432.wav")
		AudioMessage("misn0433.wav")
		AudioMessage("misn0434.wav")
		missionfail = true
	end
	
	-- Additional conditions from end of C++ file
	if (not basesecure) and (not secureloopbreak) and (wavenumber == 6) and
		(not IsAlive(w5u1)) and (not IsAlive(w5u2)) and (not IsAlive(w5u3)) and (not IsAlive(w5u4)) and
		(not IsAlive(svrec)) and (chewedout) then
		
		aud20 = AudioMessage("misn0425.wav")
		basesecure = true
		newobjective = true
		secureloopbreak = true
	end
end

function Save()
	return missionstart, warn, retreat, surveysent, reconsent, firstwave, secondwave, thirdwave, fourthwave, fifthwave,
	discrelic, ccatugsent, attackccabase, ccabasedestroyed, fifthwavedestroyed, missionend, wavenumber, missionwon,
	wave1dead, wave2dead, wave3dead, wave4dead, wave5dead, possiblewin, loopbreak, basesecure, newobjective,
	relicsecure, discoverrelic, missionfail2, aud10, aud11, aud12, aud13, aud14, ccahasrelic, relicseen, obset,
	wave1, wave2, wave3, wave4, wave5, endcindone, startendcin, ccatug, notfound, build2, build3, build4, build5, halfway,
	svrec, pu1, pu2, pu3, pu4, pu5, pu6, pu7, pu8, navbeacon,
	cheat1, cheat2, cheat3, cheat4, cheat5, cheat6, cheat7, cheat8, cheat9, cheat10,
	tug, svtug, tuge1, tuge2,
	player, surv1, surv2, surv3, surv4,
	cam1, cam2, cam3, basecam, reliccam,
	avrec, w1u1, w1u2,
	w2u1, w2u2, w2u3,
	w3u1, w3u2, w3u3, w3u4,
	w4u1, w4u2, w4u3, w4u4, w4u5,
	w5u1, w5u2, w5u3, w5u4, w5u5, w5u6,
	spawn1, spawn2, spawn3, relic,
	calipso, turret1, turret2, turret3, turret4,
	aud1, aud2, aud3, aud4, aud20, aud21, aud22, aud23,
	doneaud20, doneaud21, doneaud22, doneaud23, done, secureloopbreak, found, endcinfinish, loopbreak2,
	investigate, investigator, tur1, tur2, tur3, tur4, tur1sent, tur2sent, tur3sent, tur4sent,
	cin1done, missionfail, chewedout, relicmoved, height, cintime1, fetch, reconcca, relicstartpos, cheater
end

function Load(...)
    local args = {...}
    missionstart, warn, retreat, surveysent, reconsent, firstwave, secondwave, thirdwave, fourthwave, fifthwave,
    discrelic, ccatugsent, attackccabase, ccabasedestroyed, fifthwavedestroyed, missionend, wavenumber, missionwon,
    wave1dead, wave2dead, wave3dead, wave4dead, wave5dead, possiblewin, loopbreak, basesecure, newobjective,
    relicsecure, discoverrelic, missionfail2, aud10, aud11, aud12, aud13, aud14, ccahasrelic, relicseen, obset,
    wave1, wave2, wave3, wave4, wave5, endcindone, startendcin, ccatug, notfound, build2, build3, build4, build5, halfway,
    svrec, pu1, pu2, pu3, pu4, pu5, pu6, pu7, pu8, navbeacon,
    cheat1, cheat2, cheat3, cheat4, cheat5, cheat6, cheat7, cheat8, cheat9, cheat10,
    tug, svtug, tuge1, tuge2,
    player, surv1, surv2, surv3, surv4,
    cam1, cam2, cam3, basecam, reliccam,
    avrec, w1u1, w1u2,
    w2u1, w2u2, w2u3,
    w3u1, w3u2, w3u3, w3u4,
    w4u1, w4u2, w4u3, w4u4, w4u5,
    w5u1, w5u2, w5u3, w5u4, w5u5, w5u6,
    spawn1, spawn2, spawn3, relic,
    calipso, turret1, turret2, turret3, turret4,
    aud1, aud2, aud3, aud4, aud20, aud21, aud22, aud23,
    doneaud20, doneaud21, doneaud22, doneaud23, done, secureloopbreak, found, endcinfinish, loopbreak2,
    investigate, investigator, tur1, tur2, tur3, tur4, tur1sent, tur2sent, tur3sent, tur4sent,
    cin1done, missionfail, chewedout, relicmoved, height, cintime1, fetch, reconcca, relicstartpos, cheater = unpack(args)
end
