-- Faithful stock misn18 port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misn18Mission.cpp.
-- Disabled C++ is retained verbatim at its original locations below.
-- Full original C++ and header, including native save/load and unused fields,
-- are preserved in References/Misn18Source/. No EXU/OpenShim helpers required.
local M

local function NewState()
    local state = {}
    state.openingcin = false
    state.camera1 = false
    state.camera2 = false
    state.camera3 = false
    state.wave1start = false
    state.wave2start = false
    state.wave3start = false
    state.wave4start = false
    state.wave5start = false
    state.wave6start = false
    state.missionstart = false
    state.missionfail = false
    state.transdestroyed = false
    state.transportfound = false
    state.returnwave = false
    state.missionwon = false
    state.alternateroute = false
    state.rand1brk = false
    state.rand2brk = false
    state.rand3brk = false
    state.newobjective = false
    state.dontgo = false
    state.dg1 = false
    state.dg2 = false
    state.dg3 = false
    state.builddone = false
    state.fail1 = false
    state.fail2 = false
    state.win1 = false
    state.blastoff = false
    state.thrust1 = false
    state.thrust2 = false
    state.thrust3 = false
    state.thrust4 = false
    state.fail3 = false
    state.openingcindone = false
    state.transblownup = false
    state.message1 = false
    state.message2 = false
    state.message3 = false
    state.message4 = false
    state.savwaves = false
    state.explosions = 99999.0
    state.rand1 = 99999.0
    state.rand2 = 99999.0
    state.rand3 = 99999.0
    state.gettosavtrans = 99999.0
    state.hurry1 = 99999.0
    state.hurry2 = 99999.0
    state.hurry3 = 99999.0
    state.hurry4 = 99999.0
    state.savattack = 99999.0
    state.quake_check = 99999.0
    state.next_second = 99999.0
    state.enemycheck = 99999.0
    state.transport = nil
    state.avrec = nil
    state.player = nil
    state.enemy = nil
    state.thrusterone = nil
    state.thrustertwo = nil
    state.thrusterthree = nil
    state.thrusterfour = nil
    state.w1u1 = nil
    state.w1u2 = nil
    state.w1u3 = nil
    state.w1u4 = nil
    state.w2u1 = nil
    state.w2u2 = nil
    state.w2u3 = nil
    state.w2u4 = nil
    state.w3u1 = nil
    state.w3u2 = nil
    state.w3u3 = nil
    state.w3u4 = nil
    state.w4u1 = nil
    state.w4u2 = nil
    state.w4u3 = nil
    state.w4u4 = nil
    state.w5u1 = nil
    state.w5u2 = nil
    state.w5u3 = nil
    state.w5u4 = nil
    state.w6u1 = nil
    state.w6u2 = nil
    state.w6u3 = nil
    state.w6u4 = nil
    state.aud1 = nil
    state.basenav = nil
    state.rand1a = nil
    state.rand1b = nil
    state.rand1c = nil
    state.rand2a = nil
    state.rand2b = nil
    state.rand2c = nil
    state.rand3a = nil
    state.rand3b = nil
    state.rand3c = nil
    state.dg1a = nil
    state.dg1b = nil
    state.dg1c = nil
    state.dg1d = nil
    state.dg2a = nil
    state.dg2b = nil
    state.dg2c = nil
    state.dg2d = nil
    state.dg3a = nil
    state.dg3b = nil
    state.dg3c = nil
    state.dg3d = nil
    state.fury1 = nil
    state.fury2 = nil
    state.fury3 = nil
    state.fury4 = nil
    state.sav1 = nil
    state.sav2 = nil
    state.sav3 = nil
    state.scrapcam = nil
    state.scrapcam2 = nil
    state.x = 0
    state.y = 0
    state.z = 0
    state.quake_level = 0
    state.quake_count = 0
    return state
end
M = NewState()

-- PORT FIX: the C++ enemy handle starts at 0 and GetNearestEnemy can return
-- no object, or a previously cached enemy can disappear before the next poll.
-- Guard absent/invalid object handles instead of passing them into a Lua
-- GetDistance overload. Infinity makes the proximity condition false until
-- a real object is present; all valid distances, thresholds, and routes stay
-- unchanged. This also protects player/recycler distance checks after removal.
local function Distance(from, to)
    if from == nil or from == 0 or not IsValid(from) then return math.huge end
    if to == nil or to == 0 then return math.huge end
    if type(to) ~= "string" and not IsValid(to) then return math.huge end
    return GetDistance(from, to)
end

function Start()
    M = NewState()
    --[==[/*
	Here's where you
	set the values
	at the start.  
	*/]==]
    M.wave1start = false
    M.wave2start = false
    M.wave3start = false
    M.wave4start = false
    M.wave5start = false
    M.wave6start = false
    M.rand1brk = false
    M.rand2brk = false
    M.rand3brk = false
    M.dontgo = false
    M.builddone = false
    M.thrust1 = false
    M.thrust2 = false
    M.thrust3 = false
    M.thrust4 = false
    M.enemy = nil
    M.enemycheck = 999999999999.0
    M.dg1 = false
    M.dg2 = false
    M.dg3 = false
    M.next_second = 99999999999.0
    M.message1 = false
    M.message2 = false
    M.message3 = false
    M.message4 = false
    M.missionstart = false
    M.missionwon = false
    M.missionfail = false
    M.transdestroyed = false
    M.transportfound = false
    M.alternateroute = false
    M.transblownup = false
    M.returnwave = false
    M.camera1 = false
    M.camera2 = false
    M.camera3 = false
    M.openingcin = false
    M.fail1 = false
    M.fail2 = false
    M.win1 = false
    M.blastoff = false
    M.newobjective = false
    M.transport = nil
    M.basenav = nil
    M.savattack = 99999999999999.0
    M.avrec = nil
    M.player = nil
    M.thrusterone = nil
    M.thrustertwo = nil
    M.thrusterthree = nil
    M.thrusterfour = nil
    M.w1u1 = nil
    M.w1u2 = nil
    M.w1u3 = nil
    M.w1u4 = nil
    M.w2u1 = nil
    M.w2u2 = nil
    M.w2u3 = nil
    M.w2u4 = nil
    M.w3u1 = nil
    M.w3u2 = nil
    M.w3u3 = nil
    M.w3u4 = nil
    M.w4u1 = nil
    M.w4u2 = nil
    M.w4u3 = nil
    M.w4u4 = nil
    M.w5u1 = nil
    M.w5u2 = nil
    M.w5u3 = nil
    M.w5u4 = nil
    M.w6u1 = nil
    M.w6u2 = nil
    M.w6u3 = nil
    M.w6u4 = nil
    M.scrapcam = nil
    M.scrapcam2 = nil
    M.rand1a = nil
    M.rand1b = nil
    M.rand1c = nil
    M.rand2a = nil
    M.rand2b = nil
    M.rand2c = nil
    M.rand3a = nil
    M.rand3b = nil
    M.rand3c = nil
    M.aud1 = nil
    M.dg1a = nil
    M.dg1b = nil
    M.dg1c = nil
    M.dg1d = nil
    M.dg2a = nil
    M.dg2b = nil
    M.dg2c = nil
    M.dg2d = nil
    M.dg3a = nil
    M.dg3b = nil
    M.dg3c = nil
    M.dg3d = nil
    M.sav1 = nil
    M.sav2 = nil
    M.sav3 = nil
    M.fail3 = false
    M.savwaves = false
    M.openingcindone = false
    M.fury1 = nil
    M.fury2 = nil
    M.fury3 = nil
    M.fury4 = nil
    M.x = 6000
    M.y = 1500
    M.z = 0
    M.rand1 = 9999999.0
    M.rand2 = 9999999.0
    M.rand3 = 9999999.0
    M.hurry1 = 999999.0
    M.hurry2 = 999999.0
    M.hurry3 = 999999.0
    M.hurry4 = 999999.0
    M.gettosavtrans = 9999999.0
    --[==[/*
		Harmless but unnessecary
		initialization of 
		quake variables.
	*/]==]
    M.quake_count = 0
    M.quake_level = 0
end

function Update(dt)
    --[==[/*
		Here is where you 
		put what happens 
		every frame.  
	*/]==]
    if M.missionstart == false then
        M.aud1 = AudioMessage("misn1801.wav")
        M.avrec = GetHandle("avrecy2_recycler")
        SetScrap(1, 80)
        M.scrapcam = GetHandle("scrapcam")
        M.scrapcam2 = GetHandle("scrapcam2")
        M.rand1 = GetTime() + 150.0
        M.rand2 = GetTime() + 230.0
        M.rand3 = GetTime() + 310.0
        M.gettosavtrans = GetTime() + 600.0
        M.basenav = GetHandle("basenav")
        SetObjectiveName(M.basenav, "Home Base")
        M.missionstart = true
        M.thrusterone = GetHandle("hbtrn20049_i76building")
        M.thrustertwo = GetHandle("hbtrn20050_i76building")
        M.thrusterthree = GetHandle("hbtrn20051_i76building")
        M.thrusterfour = GetHandle("hbtrn20052_i76building")
        M.transport = GetHandle("hbtran0038_i76building")
        StartEarthquake(2.0)
        M.quake_level = 2
        M.quake_check = GetTime() + 2.0
        M.newobjective = true
        SetObjectiveOn(M.transport)
        M.next_second = GetTime() + 5.0
        M.enemycheck = GetTime() + 3.0
    end
    M.player = GetPlayerHandle()
    if (M.transportfound == false) and (M.enemycheck < GetTime()) then
        if IsAlive(M.transport) then
            M.enemy = GetNearestEnemy(M.transport)
            M.enemycheck = GetTime() + 3.0
        end
    end
    if M.newobjective == true then
        ClearObjectives()
        if M.missionwon == true then
            AddObjective("misn1803.otf", "green")
            AddObjective("misn1802.otf", "green")
        end
        if (M.transdestroyed == true) and (M.missionwon == false) then
            AddObjective("misn1803.otf", "white")
            AddObjective("misn1802.otf", "green")
        end
        if (M.transdestroyed == false) and (M.transportfound == true) then
            AddObjective("misn1802.otf", "white")
        end
        if M.transportfound == false then
            AddObjective("misn1801.otf", "white")
        end
        M.newobjective = false
    end
    --[==[/*
		After four seconds the
		quake gets bigger for 
		two seconds.
	*/]==]
    --[==[/*if (GetTime()>quake_check)
	{
		quake_count++;
		quake_check=GetTime()+3.0f;
		if (quake_count%4==1)
		{
			UpdateEarthQuake(quake_level*3.0f);
		}
		else UpdateEarthQuake(quake_level*0.9f);

	}*/]==]
    if M.openingcin == false then
        CameraReady()
        M.camera1 = true
        M.openingcin = true
    end
    if M.camera2 == true then
        if CameraPath("opencam1", 1500, 8000, M.scrapcam) then
            --[==[//	(PanDone())]==]
            M.camera2 = false
            M.camera3 = true
        end
    end
    if M.camera3 == true then
        if CameraPath("opencam2", 1500, 9000, M.scrapcam2) then
            --[==[//				(PanDone())]==]
            M.camera3 = false
            RemoveObject(M.scrapcam)
            RemoveObject(M.scrapcam2)
        end
    end
    if M.camera1 == true then
        -- SOURCE BEHAVIOR: x changes by 20 per Update, not by elapsed seconds.
        -- Keep the native camera increment; dt-scaling would alter this shot.
        M.x = M.x - 20
        if CameraPath("opencam3", M.x, 2000, M.transport) then
            --[==[//				(PanDone())]==]
            M.camera1 = false
            M.camera2 = true
        end
    end
    if M.openingcindone == false then
        if (IsAudioMessageDone(M.aud1)) or (CameraCancelled()) then
            StopAudioMessage(M.aud1)
            M.openingcindone = true
            M.camera1 = false
            M.camera2 = false
            M.camera3 = false
            CameraFinish()
        end
    end
    -- SOURCE BEHAVIOR: next_second is advanced only by the undiscovered
    -- thruster-healing block below. Once found, the transport gains 100 health
    -- every Update after that deadline; thrusters stop healing. Giving the
    -- transport a separate one-second timer would change combat difficulty.
    if M.transdestroyed == false then
        if (IsAlive(M.transport)) and (GetTime() > M.next_second) then
            AddHealth(M.transport, 100.0)
        end
    end
    if (M.transdestroyed == true) and (M.transblownup == false) then
        Damage(M.transport, 999999999.0)
        M.transblownup = true
    end
    if M.transportfound == false then
        if GetTime() > M.next_second then
            if IsAlive(M.thrusterone) then
                AddHealth(M.thrusterone, 50.0)
            end
            if IsAlive(M.thrustertwo) then
                AddHealth(M.thrustertwo, 50.0)
            end
            if IsAlive(M.thrusterthree) then
                AddHealth(M.thrusterthree, 50.0)
            end
            if IsAlive(M.thrusterfour) then
                AddHealth(M.thrusterfour, 50.0)
            end
            M.next_second = GetTime() + 1.0
        end
    end
    if (M.wave1start == false) and (
        (Distance(M.player, "spawn1a") < 100.0) or
        (Distance(M.player, "spawnalt1a") < 100.0) or
        (Distance(M.player, "cheat1a") < 200.0) or
        (Distance(M.player, "cheatalt1a") < 200.0)) then
        M.w1u1 = BuildObject("hvsat", 2, "spawn1b")
        M.w1u3 = BuildObject("hvsat", 2, "spawnalt1b")
        Goto(M.w1u1, "transport1")
        Goto(M.w1u3, "transport2")
        SetIndependence(M.w1u1, 1)
        SetIndependence(M.w1u3, 1)
        M.wave1start = true
    end
    if (M.wave2start == false) and (
        (Distance(M.player, "spawn2a") < 100.0) or
        (Distance(M.player, "spawnalt2a") < 100.0) or
        (Distance(M.player, "cheat2a") < 200.0) or
        (Distance(M.player, "cheatalt2a") < 200.0)) then
        M.w2u2 = BuildObject("hvsat", 2, "spawn2b")
        M.w2u4 = BuildObject("hvsat", 2, "spawnalt2b")
        Goto(M.w2u2, "transport3")
        Goto(M.w2u4, "transport4")
        SetIndependence(M.w2u2, 1)
        SetIndependence(M.w2u4, 1)
        M.wave2start = true
    end
    if (M.wave3start == false) and (
        (Distance(M.player, "spawn3a") < 100.0) or
        (Distance(M.player, "spawnalt3a") < 100.0) or
        (Distance(M.player, "cheat3a") < 200.0) or
        (Distance(M.player, "cheatalt3a") < 200.0)) then
        M.w3u1 = BuildObject("hvsat", 2, "spawn3b")
        M.w3u3 = BuildObject("hvsat", 2, "spawnalt3b")
        Goto(M.w3u1, "transport5")
        Goto(M.w3u3, "transport6")
        SetIndependence(M.w3u1, 1)
        SetIndependence(M.w3u3, 1)
        M.wave3start = true
    end
    if (M.rand1 < GetTime()) and (M.rand1brk == false) then
        M.rand1a = BuildObject("hvsav", 2, "spawnrand")
        Goto(M.rand1a, "transport7")
        SetIndependence(M.rand1a, 1)
        M.rand1brk = true
    end
    if (M.rand2 < GetTime()) and (M.rand2brk == false) then
        M.rand2a = BuildObject("hvsav", 2, "spawnrand")
        Goto(M.rand2a, "transport8")
        SetIndependence(M.rand2a, 1)
        M.rand2brk = true
    end
    if (M.rand3 < GetTime()) and (M.rand3brk == false) then
        M.rand3a = BuildObject("hvsav", 2, "spawnrand")
        Goto(M.rand3a, "transport9")
        SetIndependence(M.rand3a, 1)
        M.rand3brk = true
    end
    if (M.transdestroyed == true) and (M.dontgo == false) and (Distance(M.player, "dontgo") < 50.0) then
        AudioMessage("misn1805.wav")
        M.dontgo = true
    end
    if (M.dontgo == true) and (Distance(M.player, "dontgo1") < 100.0) and (M.dg1 == false) then
        M.dg1a = BuildObject("hvsat", 2, "dgs1")
        M.dg1b = BuildObject("hvsav", 2, "spawn1")
        M.dg1 = true
    end
    if (M.dontgo == true) and (Distance(M.player, "dontgo2") < 100.0) and (M.dg2 == false) then
        M.dg2a = BuildObject("hvsat", 2, "dgs2")
        M.dg2b = BuildObject("hvsav", 2, "spawn1")
        M.dg2 = true
    end
    if (M.dontgo == true) and (Distance(M.player, "dontgo3") < 100.0) and (M.dg3 == false) then
        M.dg3a = BuildObject("hvsat", 2, "dgs3")
        M.dg3b = BuildObject("hvsav", 2, "spawn1")
        M.dg3 = true
    end
    if (not IsAlive(M.thrusterone)) and (not IsAlive(M.thrustertwo)) and (not IsAlive(M.thrusterthree)) and (not IsAlive(M.thrusterfour)) and (M.transdestroyed == false) then
        AudioMessage("misn1804.wav")
        M.transdestroyed = true
        M.newobjective = true
        M.hurry1 = GetTime() + 60.0
        M.hurry2 = GetTime() + 85.0
        M.hurry3 = GetTime() + 115.0
        M.hurry4 = GetTime() + 140.0
        M.quake_level = 6
        StartCockpitTimer(180.0, 120.0, 30.0)
    end
    if (M.hurry1 < GetTime()) and (M.missionwon == false) then
        AudioMessage("misn1809.wav")
        M.hurry1 = GetTime() + 99999999.0
    end
    if (M.hurry2 < GetTime()) and (M.missionwon == false) then
        AudioMessage("misn1810.wav")
        M.hurry2 = GetTime() + 99999999.0
    end
    if (M.hurry3 < GetTime()) and (M.missionwon == false) then
        AudioMessage("misn1811.wav")
        M.hurry3 = GetTime() + 99999999.0
    end
    if (M.hurry4 < GetTime()) and (M.missionwon == false) then
        AudioMessage("misn1812.wav")
        M.hurry4 = GetTime() + 99999999.0
    end
    if (M.transportfound == false) and (
        (Distance(M.player, "transfound") < 100.0) or
        (Distance(M.enemy, M.transport) < 200.0)) then
        AudioMessage("misn1816.wav")
        M.transportfound = true
        if IsAlive(M.transport) then
            SetObjectiveOff(M.transport)
        end
        if IsAlive(M.thrusterone) then
            SetObjectiveOn(M.thrusterone)
        end
        if IsAlive(M.thrustertwo) then
            SetObjectiveOn(M.thrustertwo)
        end
        if IsAlive(M.thrusterthree) then
            SetObjectiveOn(M.thrusterthree)
        end
        if IsAlive(M.thrusterfour) then
            SetObjectiveOn(M.thrusterfour)
        end
        M.savattack = GetTime() + 180.0
        M.newobjective = true
        if M.wave1start == false then
            M.w1u1 = BuildObject("hvsat", 2, "spawn1b")
            M.w1u3 = BuildObject("hvsat", 2, "spawnalt1b")
            Goto(M.w1u1, "transport1")
            Goto(M.w1u3, "transport2")
            SetIndependence(M.w1u1, 1)
            SetIndependence(M.w1u3, 1)
            M.wave1start = true
        end
        if M.wave2start == false then
            M.w2u2 = BuildObject("hvsat", 2, "spawn2b")
            M.w2u4 = BuildObject("hvsat", 2, "spawnalt2b")
            Goto(M.w2u2, "transport3")
            Goto(M.w2u4, "transport4")
            SetIndependence(M.w2u2, 1)
            SetIndependence(M.w2u4, 1)
            M.wave2start = true
        end
        if M.wave3start == false then
            M.w3u1 = BuildObject("hvsat", 2, "spawn3b")
            M.w3u3 = BuildObject("hvsat", 2, "spawnalt3b")
            Goto(M.w3u1, "transport5")
            Goto(M.w3u3, "transport6")
            SetIndependence(M.w3u1, 1)
            SetIndependence(M.w3u3, 1)
            M.wave3start = true
        end
    end
    if (M.transdestroyed == false) and (M.savwaves == false) and (M.savattack < GetTime()) then
        M.savwaves = true
        M.fury1 = BuildObject("hvsav", 2, "spawnrand")
        M.fury2 = BuildObject("hvsav", 2, "spawnrand")
        M.fury3 = BuildObject("hvsav", 2, "spawnrand2")
        M.fury4 = BuildObject("hvsav", 2, "spawnrand2")
        Attack(M.fury1, M.avrec)
        Attack(M.fury2, M.avrec)
        Attack(M.fury3, M.avrec)
        Attack(M.fury4, M.avrec)
    end
    -- SOURCE BEHAVIOR: once enabled, this wave replaces itself only when all
    -- four units die, and continues even after transport destruction. Adding a
    -- transdestroyed gate here would reduce pressure during the escape.
    if M.savwaves == true then
        if (not IsAlive(M.fury1)) and (not IsAlive(M.fury2)) and (not IsAlive(M.fury3)) and (not IsAlive(M.fury4)) then
            M.fury1 = BuildObject("hvsav", 2, "spawnrand")
            M.fury2 = BuildObject("hvsav", 2, "spawnrand")
            M.fury3 = BuildObject("hvsav", 2, "spawnrand2")
            M.fury4 = BuildObject("hvsav", 2, "spawnrand2")
            Attack(M.fury1, M.avrec)
            Attack(M.fury2, M.avrec)
            Attack(M.fury3, M.avrec)
            Attack(M.fury4, M.avrec)
        end
    end
    if (M.transportfound == false) and (M.gettosavtrans < GetTime()) and (M.fail1 == false) then
        FailMission(GetTime() + 5.0, "misn18l1.des")
        AudioMessage("misn1806.wav")
        M.fail1 = true
    end
    -- SOURCE BEHAVIOR: victory uses <200 m, while timer failure requires >400 m.
    -- The 200..400 m band and the independent failure latches are intentional
    -- fidelity choices here; tightening them would change escape outcomes.
    if (M.transdestroyed == true) and (Distance(M.player, M.avrec) > 400.0) and (GetCockpitTimer() <= 0) and (M.fail2 == false) then
        CameraReady()
        FailMission(GetTime() + 7.0, "misn18l2.des")
        AudioMessage("misn1807.wav")
        M.fail2 = true
        M.blastoff = true
    end
    if (not IsAlive(M.avrec)) and (M.fail3 == false) then
        M.fail3 = true
        FailMission(GetTime() + 7.0, "misn18l3.des")
        -- The DLL really references misn1704.wav for recycler loss; retain it.
        AudioMessage("misn1704.wav")
    end
    if M.blastoff == true then
        M.y = M.y + 500
        CameraObject(M.player, 1, M.y, 1000, M.player)
    end
    if ((Distance(M.player, "return1") < 100.0) or
        (Distance(M.player, "return2") < 100.0)) and
        (M.returnwave == false) and (M.transdestroyed == true) then
        M.sav1 = BuildObject("hvsat", 2, "spawnreturn")
        --[==[//sav2 = BuildObject ("hvsat",2, "spawnreturn");]==]
        --[==[//sav3 = BuildObject ("hvsav",2, "spawnreturn");]==]
        M.returnwave = true
    end
    if (Distance(M.player, M.avrec) < 200.0) and (M.transdestroyed == true) and (M.missionwon == false) then
        AudioMessage("misn1808.wav")
        SucceedMission(GetTime() + 12.0)
        M.fail2 = true
        M.missionwon = true
        M.newobjective = true
    end
    if (not IsAlive(M.thrusterone)) and (M.thrust1 == false) then
        M.z = M.z + 1
        M.thrust1 = true
    end
    if (not IsAlive(M.thrustertwo)) and (M.thrust2 == false) then
        M.z = M.z + 1
        M.thrust2 = true
    end
    if (not IsAlive(M.thrusterthree)) and (M.thrust3 == false) then
        M.z = M.z + 1
        M.thrust3 = true
    end
    if (not IsAlive(M.thrusterfour)) and (M.thrust4 == false) then
        M.z = M.z + 1
        M.thrust4 = true
    end
    if (M.z == 1) and (M.message1 == false) then
        AudioMessage("misn1813.wav")
        M.message1 = true
    end
    if (M.z == 2) and (M.message2 == false) then
        AudioMessage("misn1814.wav")
        M.message2 = true
    end
    if (M.z == 3) and (M.message3 == false) then
        AudioMessage("misn1815.wav")
        M.message3 = true
    end
end

-- Stock LuaMission serializes this table's primitive values and engine types,
-- including object handles and the AudioMessage token; it remaps handles on load.
-- Load restores the saved flags, timers, and camera counters without Setup or
-- replaying the first-frame mission initialization.
function Save()
    return M
end

function Load(state)
    M = state
end
