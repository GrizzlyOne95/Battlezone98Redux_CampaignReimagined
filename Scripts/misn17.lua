-- Faithful misn17 port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misn17Mission.cpp.
-- Source blob: 8a3dd976203e79ebae70d30329d4b737fa074764.
-- The enclosing Execute #if 0 in the BZ2 DLL archive is activated for this port;
-- its inner commented alternatives remain disabled at their original locations.
-- Complete unmodified C++ (including comments and native persistence) is kept in
-- References/Misn17Source/. See Docs/MISN17_SOURCE_PORT.md for parity and fixes.
-- Single player, stock BZR API only; no EXU/OpenShim dependency.
local M

local function NewState()
    local state = {}
    state.missionstart = false
    state.raw1there = false
    state.raw2there = false
    state.raw3there = false
    state.raw4there = false
    state.raw5there = false
    state.prothere = false
    state.inprocess = false
    state.minesmade = false
    state.openingcin = false
    state.camera1 = false
    state.camera2 = false
    state.camera3 = false
    state.camera4 = false
    state.camera5 = false
    state.camera6 = false
    state.camera7 = false
    state.dispatch = false
    state.dispatch2 = false
    state.cineractive1 = false
    state.cineractive2 = false
    state.openingcindone = false
    state.crysswitched = false
    state.factorydestroyed = false
    state.attackwavesent = false
    state.firsttimecrysreplaced = false
    state.newobjective = false
    state.checktug = false
    state.crystalhint1 = false
    state.crystalhint2 = false
    state.crystalhint3 = false
    state.said1 = false
    state.procrysgone = false
    state.missionfail = false
    state.missionwon = false
    state.defenders = false
    state.minecin = false
    state.minesdestroyed = false
    state.towersdestroyed = false
    state.tower1spawn = false
    state.tower2spawn = false
    state.tower3spawn = false
    state.tower4spawn = false
    state.tower5spawn = false
    state.tower6spawn = false
    state.tower7spawn = false
    state.tower1dead = false
    state.tower2dead = false
    state.tower3dead = false
    state.tower4dead = false
    state.tower5dead = false
    state.tower6dead = false
    state.tower7dead = false
    state.minecinstart = false
    state.factorypart1dead = false
    state.factorypart2dead = false
    state.factorypart3dead = false
    state.sf2gone = false
    state.sf3gone = false
    state.sf4gone = false
    state.fact1gone = false
    state.fact2gone = false
    state.fact3gone = false
    state.critstatement = false
    state.discheck = 99999.0
    state.minedistancecheck = 99999.0
    state.waveattacks = 99999.0
    state.spawntime1 = 99999.0
    state.spawntime2 = 99999.0
    state.spawntime3 = 99999.0
    state.spawntime4 = 99999.0
    state.tower1check = 99999.0
    state.tower2check = 99999.0
    state.tower3check = 99999.0
    state.tower4check = 99999.0
    state.tower5check = 99999.0
    state.tower6check = 99999.0
    state.tower7check = 99999.0
    state.sf2blow = 99999.0
    state.sf3blow = 99999.0
    state.sf4blow = 99999.0
    state.procrysdes = 99999.0
    state.rawcrys1des = 99999.0
    state.rawcrys2des = 99999.0
    state.rawcrys3des = 99999.0
    state.rawcrys4des = 99999.0
    state.rawcrys5des = 99999.0
    state.procrysreplace = 99999.0
    state.rawcrys1replace = 99999.0
    state.rawcrys2replace = 99999.0
    state.rawcrys3replace = 99999.0
    state.camdone = 99999.0
    state.rawcrys4replace = 99999.0
    state.rawcrys5replace = 99999.0
    state.op1replace = 99999.0
    state.op2replace = 99999.0
    state.op3replace = 99999.0
    state.op4replace = 99999.0
    state.savfactory1 = nil
    state.savfactory2 = nil
    state.savfactory3 = nil
    state.savfactory4 = nil
    state.deftow1a = nil
    state.deftow1b = nil
    state.deftow2a = nil
    state.deftow2b = nil
    state.factorynav = nil
    state.basenav = nil
    state.badman1 = nil
    state.badman2 = nil
    state.badman3 = nil
    state.badman4 = nil
    state.badman5 = nil
    state.badman6 = nil
    state.badman7 = nil
    state.badman8 = nil
    state.badman9 = nil
    state.badman10 = nil
    state.badman11 = nil
    state.badman12 = nil
    state.badman13 = nil
    state.badman14 = nil
    state.deftow3a = nil
    state.deftow3b = nil
    state.deftow4a = nil
    state.deftow4b = nil
    state.deftow5a = nil
    state.deftow5b = nil
    state.deftow6a = nil
    state.deftow6b = nil
    state.aud1 = nil
    state.trig1 = nil
    state.trig2 = nil
    state.trig3 = nil
    state.trig4 = nil
    state.trig5 = nil
    state.trig6 = nil
    state.trig7 = nil
    state.deftow7a = nil
    state.deftow7b = nil
    state.factorypart1 = nil
    state.factorypart2 = nil
    state.factorypart3 = nil
    state.procrys = nil
    state.rawcrys1 = nil
    state.rawcrys2 = nil
    state.rawcrys3 = nil
    state.rawcrys4 = nil
    state.rawcrys5 = nil
    state.miner = nil
    state.avrec = nil
    state.prey1 = nil
    state.ip1 = nil
    state.ip2 = nil
    state.ip3 = nil
    state.ip4 = nil
    state.cam1 = nil
    state.cam2 = nil
    state.cam3 = nil
    state.cam4 = nil
    state.cam5 = nil
    state.cam6 = nil
    state.aw1 = nil
    state.aw2 = nil
    state.aw3 = nil
    state.aw4 = nil
    state.tug = nil
    state.MINE = {}
    state.mineaudio = nil
    state.cinscrap = nil
    state.art1 = nil
    state.art2 = nil
    state.art3 = nil
    state.art4 = nil
    state.art5 = nil
    state.desart1 = nil
    state.desart2 = nil
    state.desart3 = nil
    state.desart4 = nil
    state.desart5 = nil
    state.tower1 = nil
    state.tower2 = nil
    state.tower3 = nil
    state.tower4 = nil
    state.tower5 = nil
    state.tower6 = nil
    state.tower7 = nil
    state.hint = 0
    state.minecount = 0
    state.crit = 0
    --[==[/*
		Initialize variables
	*/]==]
    state.camdone = 9999999999.0
    state.discheck = 9999999999.0
    state.savfactory1 = nil
    state.savfactory2 = nil
    state.savfactory3 = nil
    state.savfactory4 = nil
    state.procrys = nil
    state.rawcrys1 = nil
    state.rawcrys2 = nil
    state.rawcrys3 = nil
    state.rawcrys4 = nil
    state.rawcrys5 = nil
    state.miner = nil
    state.avrec = nil
    state.prey1 = nil
    state.factorypart1 = nil
    state.factorypart2 = nil
    state.factorypart3 = nil
    state.aud1 = nil
    state.missionwon = false
    state.cinscrap = nil
    state.badman1 = nil
    state.badman2 = nil
    state.badman3 = nil
    state.badman4 = nil
    state.badman5 = nil
    state.badman6 = nil
    state.badman7 = nil
    state.badman8 = nil
    state.badman9 = nil
    state.badman10 = nil
    state.badman11 = nil
    state.badman12 = nil
    state.badman13 = nil
    state.badman14 = nil
    state.ip1 = nil
    state.ip2 = nil
    state.ip3 = nil
    state.ip4 = nil
    state.cam1 = nil
    state.cam2 = nil
    state.cam3 = nil
    state.cam4 = nil
    state.cam5 = nil
    state.cam6 = nil
    state.aw1 = nil
    state.aw2 = nil
    state.aw3 = nil
    state.aw4 = nil
    state.tug = nil
    state.factorynav = nil
    state.basenav = nil
    state.sf2gone = false
    state.sf3gone = false
    state.sf4gone = false
    state.sf2blow = 99999999999.0
    state.sf3blow = 99999999999.0
    state.sf4blow = 99999999999.0
    state.deftow1a = nil
    state.deftow1b = nil
    state.deftow2a = nil
    state.deftow2b = nil
    state.deftow3a = nil
    state.deftow3b = nil
    state.deftow4a = nil
    state.deftow4b = nil
    state.deftow5a = nil
    state.deftow5b = nil
    state.deftow6a = nil
    state.deftow6b = nil
    state.deftow7a = nil
    state.deftow7b = nil
    -- SOURCE BUG FIX: native MINE[53] writes past Handle MINE[53] (0..52)
    -- into the next member, mineaudio. The cinematic later overwrites mine 53.
    -- Lua uses the mission's actual mine keys 1..53; the table is already empty.
    -- No handles outside the mine table are overwritten, and spawn order is unchanged.
    state.mineaudio = nil
    state.tower1 = nil
    state.tower2 = nil
    state.tower3 = nil
    state.tower4 = nil
    state.tower5 = nil
    state.tower6 = nil
    state.tower7 = nil
    state.towersdestroyed = false
    state.minecin = false
    state.defenders = false
    state.said1 = false
    state.missionstart = false
    state.dispatch2 = false
    state.inprocess = false
    state.minecinstart = false
    state.checktug = false
    state.newobjective = false
    state.crysswitched = false
    state.factorydestroyed = false
    state.attackwavesent = false
    state.firsttimecrysreplaced = false
    state.dispatch = false
    state.missionfail = false
    state.openingcin = false
    state.factorypart1dead = false
    state.factorypart2dead = false
    state.factorypart3dead = false
    state.openingcin = false
    state.camera1 = true
    state.camera2 = false
    state.camera3 = false
    state.camera4 = false
    state.camera5 = false
    state.camera6 = false
    state.camera7 = false
    state.openingcindone = false
    state.trig1 = nil
    state.trig2 = nil
    state.trig3 = nil
    state.trig4 = nil
    state.trig5 = nil
    state.trig6 = nil
    state.trig7 = nil
    state.hint = 0
    state.spawntime1 = 999999999.0
    state.spawntime2 = 999999999.0
    state.spawntime3 = 999999999.0
    state.spawntime4 = 999999999.0
    state.minedistancecheck = 999999999.0
    state.crit = 0
    state.fact1gone = false
    state.fact2gone = false
    state.fact3gone = false
    state.critstatement = false
    state.minesmade = false
    state.tower1dead = false
    state.tower2dead = false
    state.tower3dead = false
    state.tower4dead = false
    state.tower5dead = false
    state.tower6dead = false
    state.tower7dead = false
    state.tower1check = 9999999999.0
    state.tower2check = 9999999999.0
    state.tower3check = 9999999999.0
    state.tower4check = 9999999999.0
    state.tower5check = 9999999999.0
    state.tower6check = 9999999999.0
    state.tower7check = 9999999999.0
    state.tower1spawn = false
    state.tower2spawn = false
    state.tower3spawn = false
    state.tower4spawn = false
    state.tower5spawn = false
    state.tower6spawn = false
    state.tower7spawn = false
    state.desart1 = nil
    state.desart2 = nil
    state.desart3 = nil
    state.desart4 = nil
    state.desart5 = nil
    state.art1 = nil
    state.art2 = nil
    state.art3 = nil
    state.art4 = nil
    state.art5 = nil
    return state
end
M = NewState()

-- BZR overload safety: absent nearest-enemy results must remain outside every
-- proximity trigger. Valid handles and native path point indices are unchanged.
local function Distance(from, to, point)
    if not IsValid(from) then return math.huge end
    if type(to) ~= "string" and not IsValid(to) then return math.huge end
    if point ~= nil then return GetDistance(from, to, point) end
    return GetDistance(from, to)
end

local function NearestEnemy(from)
    if IsValid(from) then return GetNearestEnemy(from) end
    return nil
end

-- A destroyed factory handle cannot be passed as a BZR spawn location. Skip
-- only missing references; each caller still advances its original timer, and
-- existing factory objects (including valid wrecks) retain the source behavior.
local function Spawn(odf, team, where)
    if type(where) == "string" or IsValid(where) then
        return BuildObject(odf, team, where)
    end
    return nil
end

local function DamageValid(h, amount)
    if IsValid(h) then Damage(h, amount) end
end

local function NameValid(h, name)
    if IsValid(h) then SetObjectiveName(h, name) end
end

local function MarkObjective(h)
    if IsValid(h) then SetObjectiveOn(h) end
end

-- A removed shooter/factory or failed spawn supplies no command target. Native
-- null-object commands had no useful effect; valid commands keep their original
-- targets/priorities, and the mission's one-shot flags and timers still advance.
local function AttackValid(h, target, priority)
    if IsValid(h) and IsValid(target) then Attack(h, target, priority) end
end

local function DefendValid(h, target, priority)
    if IsValid(h) and IsValid(target) then Defend2(h, target, priority) end
end

-- A cinematic whose target has been removed can skip that shot. The original
-- camera order, offsets, audio end/cancel gates and gameplay timers stay intact.
local function TargetCameraPath(path, height, speed, target)
    if IsValid(target) then return CameraPath(path, height, speed, target) end
    return true
end

local function TargetCameraObject(base, right, up, forward, target)
    if IsValid(base) and IsValid(target) then
        return CameraObject(base, right, up, forward, target)
    end
    return false
end

function Start()
    -- State is initialized when the chunk loads, before any AddObject calls.
    -- Do not reset artillery registered before Start; first Update does setup.
end

function AddObject(h)
    if not IsValid(h) then return end
    if (M.art1 == nil) and(IsOdf(h, "avartl")) then
        M.art1 = h
    else
        if (M.art2 == nil) and(IsOdf(h, "avartl")) then
            M.art2 = h
        else
            if (M.art3 == nil) and(IsOdf(h, "avartl")) then
                M.art3 = h
            else
                if (M.art4 == nil) and(IsOdf(h, "avartl")) then
                    M.art4 = h
                else
                    if (M.art5 == nil) and(IsOdf(h, "avartl")) then
                        M.art5 = h
                    end
                end
            end
        end
    end
end

function Update(dt)
    --[==[/*
	   Event loop.
	*/]==]
    if M.missionstart == false then
        M.minedistancecheck = GetTime() + 10.0
        M.aud1 = AudioMessage("misn1701.wav")
        M.avrec = GetHandle("avrecy18_recycler")
        M.savfactory1 = GetHandle("savfactory1")
        M.savfactory2 = GetHandle("savfactory2")
        M.savfactory3 = GetHandle("savfactory3")
        M.savfactory4 = GetHandle("savfactory4")
        M.factorypart1 = GetHandle("factorypart1")
        M.factorypart2 = GetHandle("factorypart2")
        M.factorypart3 = GetHandle("factorypart3")
        M.factorynav = GetHandle("factorynav")
        M.basenav = GetHandle("basenav")
        M.tower1 = Spawn("hbptow", 2, "geizer1")
        M.tower2 = Spawn("hbptow", 2, "geizer2")
        M.tower3 = Spawn("hbptow", 2, "geizer3")
        M.tower4 = Spawn("hbptow", 2, "geizer4")
        M.tower5 = Spawn("hbptow", 2, "geizer5")
        M.tower6 = Spawn("hbptow", 2, "geizer6")
        M.tower7 = Spawn("hbptow", 2, "geizer7")
        MarkObjective(M.tower1)
        MarkObjective(M.tower2)
        MarkObjective(M.tower3)
        MarkObjective(M.tower4)
        MarkObjective(M.tower5)
        MarkObjective(M.tower6)
        MarkObjective(M.tower7)
        NameValid(M.tower1, "Tower 1")
        NameValid(M.tower2, "Tower 2")
        NameValid(M.tower3, "Tower 3")
        NameValid(M.tower4, "Tower 4")
        NameValid(M.tower5, "Tower 5")
        NameValid(M.tower6, "Tower 6")
        NameValid(M.tower7, "Tower 7")
        NameValid(M.factorynav, "Furies Factory")
        NameValid(M.basenav, "Home Base")
        M.missionstart = true
        M.waveattacks = GetTime() + 1800.0
        M.newobjective = true
        M.camdone = GetTime() + 35.0
        SetScrap(1, 40)
        M.spawntime1 = GetTime() + 10.0
        M.spawntime2 = GetTime() + 100.0
        M.spawntime3 = GetTime() + 220.0
        M.spawntime4 = GetTime() + 340.0
        SetAIP("misn17.aip")
        M.discheck = GetTime() + 30.0
        M.tower1check = GetTime() + 3.0
        M.tower2check = GetTime() + 3.0
        M.tower3check = GetTime() + 3.0
        M.tower4check = GetTime() + 3.0
        M.tower5check = GetTime() + 3.0
        M.tower6check = GetTime() + 3.0
        M.tower7check = GetTime() + 3.0
        CameraReady()
    end
    if (IsAlive(M.art1)) and(not IsAlive(M.desart1)) then
        M.desart1 = Spawn("hvsav", 2, "counter")
        AttackValid(M.desart1, M.art1)
    end
    if (IsAlive(M.art2)) and(not IsAlive(M.desart2)) then
        M.desart2 = Spawn("hvsav", 2, "counter")
        AttackValid(M.desart2, M.art2)
    end
    if (IsAlive(M.art3)) and(not IsAlive(M.desart3)) then
        M.desart3 = Spawn("hvsav", 2, "counter")
        AttackValid(M.desart3, M.art3)
    end
    if (IsAlive(M.art4)) and(not IsAlive(M.desart4)) then
        M.desart4 = Spawn("hvsav", 2, "counter")
        AttackValid(M.desart4, M.art4)
    end
    if (IsAlive(M.art5)) and(not IsAlive(M.desart5)) then
        M.desart5 = Spawn("hvsav", 2, "counter")
        AttackValid(M.desart5, M.art5)
    end
    if M.openingcin == false then
        CameraReady()
        M.camera1 = true
        M.openingcin = true
    end
    if M.camera2 == true then
        if TargetCameraPath("cineractive2", 500, 2000, M.tower1) then
            --[==[//	(PanDone())]==]
            M.camera2 = false
            M.camera3 = true
        end
    end
    if M.camera3 == true then
        if TargetCameraPath("cineractive3", 1000, 2000, M.tower6) then
            --[==[//				(PanDone())]==]
            M.camera3 = false
            M.camera4 = true
        end
    end
    if M.camera4 == true then
        if TargetCameraPath("cineractive5", 1000, 2000, M.tower3) then
            --[==[//				(PanDone())]==]
            M.camera4 = false
            M.camera5 = true
        end
    end
    if M.camera5 == true then
        if TargetCameraPath("cineractive6", 1000, 2000, M.tower4) then
            --[==[//				(PanDone())]==]
            M.camera5 = false
            M.camera6 = true
        end
    end
    if M.camera6 == true then
        if TargetCameraPath("cineractive4", 1000, 2000, M.tower5) then
            --[==[//				(PanDone())]==]
            M.camera6 = false
            M.camera7 = true
        end
    end
    if M.camera7 == true then
        if TargetCameraPath("cineractive7", 1000, 1700, M.tower7) then
            --[==[//				(PanDone())]==]
            M.camera7 = false
            CameraFinish()
        end
    end
    if M.camera1 == true then
        if TargetCameraPath("cineractive1", 1000, 2000, M.savfactory1) then
            --[==[//				(PanDone())]==]
            M.camera1 = false
            M.camera2 = true
        end
    end
    if M.openingcindone == false then
        if (IsAudioMessageDone(M.aud1)) or(CameraCancelled()) then
            CameraFinish()
            StopAudioMessage(M.aud1)
            M.openingcindone = true
            M.camera1 = false
            M.camera2 = false
            M.camera3 = false
            M.camera4 = false
            M.camera5 = false
            M.camera6 = false
            M.camera7 = false
            CameraFinish()
        end
    end
    --[==[/*if
		(cineractive1 == false)
	{
		CameraPath("cineractive1", 1000, 2000, savfactory1);
		cineractive2 = true;
	}

	if
		(
		(cineractive2 == true) && (PanDone())
		)
	{
		CameraPath("cineractive2", 200, 2000, tower1);
		cineractive1 = true;
	}

	if
		(
		(cineractive1 == true) && (PanDone())
		)
	{
		CameraFinish();
	}*/]==]
    if (M.factorypart1dead == false) and(not IsAlive(M.factorypart1)) then
        Spawn("eggeizr1", 3, "part1geizer")
        -- SOURCE BUG FIX: native "eggiezr1" transposes the geyser ODF name.
        -- Use "eggeizr1", as in tower replacements and the finale; this restores
        -- the intended debris object without changing completion gates/timers.
        M.factorypart1dead = true
    end
    if (M.factorypart2dead == false) and(not IsAlive(M.factorypart2)) then
        -- Same geyser ODF transposition correction as factorypart1.
        Spawn("eggeizr1", 3, "part2geizer")
        M.factorypart2dead = true
    end
    if (M.factorypart3dead == false) and(not IsAlive(M.factorypart3)) then
        -- Same geyser ODF transposition correction as factorypart1.
        Spawn("eggeizr1", 3, "part3geizer")
        M.factorypart3dead = true
    end
    if (M.minesmade == false) and(M.minedistancecheck < GetTime()) then
        M.miner = NearestEnemy(M.savfactory2)
        if (Distance(M.miner, "pt1") < 610.0) or(Distance(M.miner, "pt2") < 610.0) or(Distance(M.miner, "pt3") < 610.0) then
            M.MINE[1] = Spawn("boltmine2", 2, "mine1")
            M.MINE[2] = Spawn("boltmine2", 2, "mine2")
            M.MINE[3] = Spawn("boltmine2", 2, "mine3")
            M.MINE[4] = Spawn("boltmine2", 2, "mine4")
            M.MINE[5] = Spawn("boltmine2", 2, "mine5")
            M.MINE[6] = Spawn("boltmine2", 2, "mine6")
            M.MINE[7] = Spawn("boltmine2", 2, "mine7")
            M.MINE[8] = Spawn("boltmine2", 2, "mine8")
            M.MINE[9] = Spawn("boltmine2", 2, "mine9")
            -- SOURCE BUG FIX: " mine10" has a stray leading space. Use "mine10"
            -- so the tenth mine spawns at its authored path in the same sequence.
            M.MINE[10] = Spawn("boltmine2", 2, "mine10")
            M.MINE[11] = Spawn("boltmine2", 2, "mine11")
            M.MINE[12] = Spawn("boltmine2", 2, "mine12")
            M.MINE[13] = Spawn("boltmine2", 2, "mine13")
            M.MINE[14] = Spawn("boltmine2", 2, "mine14")
            M.MINE[15] = Spawn("boltmine2", 2, "mine15")
            M.MINE[16] = Spawn("boltmine2", 2, "mine16")
            M.MINE[17] = Spawn("boltmine2", 2, "mine17")
            M.MINE[18] = Spawn("boltmine2", 2, "mine18")
            M.MINE[19] = Spawn("boltmine2", 2, "mine19")
            M.MINE[20] = Spawn("boltmine2", 2, "mine20")
            M.MINE[21] = Spawn("boltmine2", 2, "mine21")
            M.MINE[22] = Spawn("boltmine2", 2, "mine22")
            M.MINE[23] = Spawn("boltmine2", 2, "mine23")
            M.MINE[24] = Spawn("boltmine2", 2, "mine24")
            M.MINE[25] = Spawn("boltmine2", 2, "mine25")
            M.MINE[26] = Spawn("boltmine2", 2, "mine26")
            M.MINE[27] = Spawn("boltmine2", 2, "mine27")
            M.MINE[28] = Spawn("boltmine2", 2, "mine28")
            M.MINE[29] = Spawn("boltmine2", 2, "mine29")
            M.MINE[30] = Spawn("boltmine2", 2, "mine30")
            M.MINE[31] = Spawn("boltmine2", 2, "mine31")
            M.MINE[32] = Spawn("boltmine2", 2, "mine32")
            M.MINE[33] = Spawn("boltmine2", 2, "mine33")
            M.MINE[34] = Spawn("boltmine2", 2, "mine34")
            M.MINE[35] = Spawn("boltmine2", 2, "mine35")
            M.MINE[36] = Spawn("boltmine2", 2, "mine36")
            M.MINE[37] = Spawn("boltmine2", 2, "mine37")
            M.MINE[38] = Spawn("boltmine2", 2, "mine38")
            M.MINE[39] = Spawn("boltmine2", 2, "mine39")
            M.MINE[40] = Spawn("boltmine2", 2, "mine40")
            M.MINE[41] = Spawn("boltmine2", 2, "mine41")
            M.MINE[42] = Spawn("boltmine2", 2, "mine42")
            M.MINE[43] = Spawn("boltmine2", 2, "mine43")
            M.MINE[44] = Spawn("boltmine2", 2, "mine44")
            M.MINE[45] = Spawn("boltmine2", 2, "mine45")
            M.MINE[46] = Spawn("boltmine2", 2, "mine46")
            M.MINE[47] = Spawn("boltmine2", 2, "mine47")
            M.MINE[48] = Spawn("boltmine2", 2, "mine48")
            M.MINE[49] = Spawn("boltmine2", 2, "mine49")
            M.MINE[50] = Spawn("boltmine2", 2, "mine50")
            M.MINE[51] = Spawn("boltmine2", 2, "mine51")
            M.MINE[52] = Spawn("boltmine2", 2, "mine52")
            M.MINE[53] = Spawn("boltmine2", 2, "mine53")
            M.minesmade = true
        end
        M.minedistancecheck = GetTime() + 3.0
    end
    if (IsAlive(M.tower1)) and(M.tower1spawn == false) and(M.tower1check < GetTime()) then
        M.trig1 = NearestEnemy(M.tower1)
        if Distance(M.tower1, M.trig1) < 400.0 then
            M.deftow1a = Spawn("hvsat", 2, M.tower1)
            M.deftow1b = Spawn("hvsat", 2, M.tower1)
            -- BZR API ADAPTATION: native Defend2 priority 1000 is nonzero
            -- (uncommandable); Redux's documented equivalent is priority 1.
            -- All fourteen escorts keep their original defend target/control.
            DefendValid(M.deftow1a, M.tower1, 1)
            DefendValid(M.deftow1b, M.tower1, 1)
            M.tower1spawn = true
        end
        M.tower1check = GetTime() + 2.0
        M.trig1 = nil
    end
    if (IsAlive(M.deftow1a)) and(GetCurrentCommand(M.deftow1a) == AiCommand.DEFEND) then
        if GetLastEnemyShot(M.deftow1a) > 0 then
            M.badman1 = GetWhoShotMe(M.deftow1a)
            AttackValid(M.deftow1a, M.badman1, 1)
        end
    end
    if (IsAlive(M.deftow1b)) and(GetCurrentCommand(M.deftow1b) == AiCommand.DEFEND) then
        if GetLastEnemyShot(M.deftow1b) > 0 then
            M.badman2 = GetWhoShotMe(M.deftow1b)
            AttackValid(M.deftow1b, M.badman2, 1)
        end
    end
    if (IsAlive(M.deftow2a)) and(GetCurrentCommand(M.deftow2a) == AiCommand.DEFEND) then
        if GetLastEnemyShot(M.deftow2a) > 0 then
            M.badman3 = GetWhoShotMe(M.deftow2a)
            AttackValid(M.deftow2a, M.badman3, 1)
        end
    end
    if (IsAlive(M.deftow2b)) and(GetCurrentCommand(M.deftow2b) == AiCommand.DEFEND) then
        if GetLastEnemyShot(M.deftow2b) > 0 then
            M.badman4 = GetWhoShotMe(M.deftow2b)
            AttackValid(M.deftow2b, M.badman4, 1)
        end
    end
    if (IsAlive(M.deftow3a)) and(GetCurrentCommand(M.deftow3a) == AiCommand.DEFEND) then
        if GetLastEnemyShot(M.deftow3a) > 0 then
            M.badman5 = GetWhoShotMe(M.deftow3a)
            AttackValid(M.deftow3a, M.badman5, 1)
        end
    end
    if (IsAlive(M.deftow3b)) and(GetCurrentCommand(M.deftow3b) == AiCommand.DEFEND) then
        if GetLastEnemyShot(M.deftow3b) > 0 then
            M.badman6 = GetWhoShotMe(M.deftow3b)
            AttackValid(M.deftow3b, M.badman6, 1)
        end
    end
    if (IsAlive(M.deftow4a)) and(GetCurrentCommand(M.deftow4a) == AiCommand.DEFEND) then
        if GetLastEnemyShot(M.deftow4a) > 0 then
            M.badman7 = GetWhoShotMe(M.deftow4a)
            AttackValid(M.deftow4a, M.badman7, 1)
        end
    end
    if (IsAlive(M.deftow4b)) and(GetCurrentCommand(M.deftow4b) == AiCommand.DEFEND) then
        if GetLastEnemyShot(M.deftow4b) > 0 then
            M.badman8 = GetWhoShotMe(M.deftow4b)
            AttackValid(M.deftow4b, M.badman8, 1)
        end
    end
    if (IsAlive(M.deftow5a)) and(GetCurrentCommand(M.deftow5a) == AiCommand.DEFEND) then
        if GetLastEnemyShot(M.deftow5a) > 0 then
            M.badman9 = GetWhoShotMe(M.deftow5a)
            AttackValid(M.deftow5a, M.badman9, 1)
        end
    end
    if (IsAlive(M.deftow5b)) and(GetCurrentCommand(M.deftow5b) == AiCommand.DEFEND) then
        if GetLastEnemyShot(M.deftow5b) > 0 then
            M.badman10 = GetWhoShotMe(M.deftow5b)
            AttackValid(M.deftow5b, M.badman10, 1)
        end
    end
    if (IsAlive(M.deftow6a)) and(GetCurrentCommand(M.deftow6a) == AiCommand.DEFEND) then
        if GetLastEnemyShot(M.deftow6a) > 0 then
            M.badman11 = GetWhoShotMe(M.deftow6a)
            AttackValid(M.deftow6a, M.badman11, 1)
        end
    end
    if (IsAlive(M.deftow6b)) and(GetCurrentCommand(M.deftow6b) == AiCommand.DEFEND) then
        if GetLastEnemyShot(M.deftow6b) > 0 then
            M.badman12 = GetWhoShotMe(M.deftow6b)
            AttackValid(M.deftow6b, M.badman12, 1)
        end
    end
    if (IsAlive(M.deftow7a)) and(GetCurrentCommand(M.deftow7a) == AiCommand.DEFEND) then
        if GetLastEnemyShot(M.deftow7a) > 0 then
            M.badman13 = GetWhoShotMe(M.deftow7a)
            -- SOURCE BUG FIX: this defender stores its shooter in badman13,
            -- but C++ attacks badman14 (the other escort's shooter). Retaliate
            -- against its own attacker; no proximity, wave or objective gate changes.
            AttackValid(M.deftow7a, M.badman13, 1)
        end
    end
    if (IsAlive(M.deftow7b)) and(GetCurrentCommand(M.deftow7b) == AiCommand.DEFEND) then
        if GetLastEnemyShot(M.deftow7b) > 0 then
            M.badman14 = GetWhoShotMe(M.deftow7b)
            AttackValid(M.deftow7b, M.badman14, 1)
        end
    end
    if (IsAlive(M.tower2)) and(M.tower2spawn == false) and(M.tower2check < GetTime()) then
        M.trig2 = NearestEnemy(M.tower2)
        if Distance(M.tower2, M.trig2) < 400.0 then
            M.deftow2a = Spawn("hvsat", 2, M.tower2)
            M.deftow2b = Spawn("hvsat", 2, M.tower2)
            DefendValid(M.deftow2a, M.tower2, 1)
            DefendValid(M.deftow2b, M.tower2, 1)
            M.tower2spawn = true
        end
        M.trig2 = nil
        M.tower2check = GetTime() + 2.0
    end
    if (IsAlive(M.tower3)) and(M.tower3spawn == false) and(M.tower3check < GetTime()) then
        M.trig3 = NearestEnemy(M.tower3)
        if Distance(M.tower3, M.trig3) < 400.0 then
            M.deftow3a = Spawn("hvsat", 2, M.tower3)
            M.deftow3b = Spawn("hvsat", 2, M.tower3)
            DefendValid(M.deftow3a, M.tower3, 1)
            DefendValid(M.deftow3b, M.tower3, 1)
            M.tower3spawn = true
        end
        M.trig3 = nil
        M.tower3check = GetTime() + 2.0
    end
    if (IsAlive(M.tower4)) and(M.tower4spawn == false) and(M.tower4check < GetTime()) then
        M.trig4 = NearestEnemy(M.tower4)
        if Distance(M.tower4, M.trig4) < 400.0 then
            M.deftow4a = Spawn("hvsat", 2, M.tower4)
            M.deftow4b = Spawn("hvsat", 2, M.tower4)
            DefendValid(M.deftow4a, M.tower4, 1)
            DefendValid(M.deftow4b, M.tower4, 1)
            M.tower4spawn = true
        end
        M.trig4 = nil
        M.tower4check = GetTime() + 2.0
    end
    if (IsAlive(M.tower5)) and(M.tower5spawn == false) and(M.tower5check < GetTime()) then
        M.trig5 = NearestEnemy(M.tower5)
        if Distance(M.tower5, M.trig5) < 400.0 then
            M.deftow5a = Spawn("hvsat", 2, M.tower5)
            M.deftow5b = Spawn("hvsat", 2, M.tower5)
            DefendValid(M.deftow5a, M.tower5, 1)
            DefendValid(M.deftow5b, M.tower5, 1)
            M.tower5spawn = true
        end
        M.trig5 = nil
        M.tower5check = GetTime() + 2.0
    end
    if (IsAlive(M.tower6)) and(M.tower6spawn == false) and(M.tower6check < GetTime()) then
        M.trig6 = NearestEnemy(M.tower6)
        if Distance(M.tower6, M.trig6) < 400.0 then
            M.deftow6a = Spawn("hvsat", 2, M.tower6)
            M.deftow6b = Spawn("hvsat", 2, M.tower6)
            DefendValid(M.deftow6a, M.tower6, 1)
            DefendValid(M.deftow6b, M.tower6, 1)
            M.tower6spawn = true
        end
        M.trig6 = nil
        M.tower6check = GetTime() + 2.0
    end
    if (IsAlive(M.tower7)) and(M.tower7spawn == false) and(M.tower7check < GetTime()) then
        M.trig7 = NearestEnemy(M.tower7)
        if Distance(M.tower7, M.trig7) < 400.0 then
            M.deftow7a = Spawn("hvsat", 2, M.tower7)
            M.deftow7b = Spawn("hvsat", 2, M.tower7)
            DefendValid(M.deftow7a, M.tower7, 1)
            DefendValid(M.deftow7b, M.tower7, 1)
            M.tower7spawn = true
        end
        M.trig7 = nil
        M.tower7check = GetTime() + 2.0
    end
    if (not IsAlive(M.tower1)) and(M.tower1dead == false) then
        Spawn("eggeizr1", 0, "geizer1")
        M.tower1dead = true
    end
    if (not IsAlive(M.tower2)) and(M.tower2dead == false) then
        Spawn("eggeizr1", 0, "geizer2")
        M.tower2dead = true
    end
    if (not IsAlive(M.tower3)) and(M.tower3dead == false) then
        Spawn("eggeizr1", 0, "geizer3")
        M.tower3dead = true
    end
    if (not IsAlive(M.tower4)) and(M.tower4dead == false) then
        Spawn("eggeizr1", 0, "geizer4")
        M.tower4dead = true
    end
    if (not IsAlive(M.tower5)) and(M.tower5dead == false) then
        Spawn("eggeizr1", 0, "geizer5")
        M.tower5dead = true
    end
    if (not IsAlive(M.tower6)) and(M.tower6dead == false) then
        Spawn("eggeizr1", 0, "geizer6")
        M.tower6dead = true
    end
    if (not IsAlive(M.tower7)) and(M.tower7dead == false) then
        Spawn("eggeizr1", 0, "geizer7")
        M.tower7dead = true
    end
    if M.newobjective == true then
        ClearObjectives()
        if M.towersdestroyed == false then
            AddObjective("misn1701.otf", "white")
        end
        if (M.towersdestroyed == true) and(M.missionwon == false) then
            AddObjective("misn1701.otf", "green")
            AddObjective("misn1702.otf", "white")
        end
        if M.missionwon == true then
            AddObjective("misn1701.otf", "green")
            AddObjective("misn1702.otf", "green")
        end
        M.newobjective = false
    end
    if M.spawntime1 < GetTime() then
        Spawn("hvsat", 2, M.savfactory1)
        M.spawntime1 = GetTime() + 400.0
    end
    if M.spawntime2 < GetTime() then
        Spawn("hvsav", 2, M.savfactory2)
        M.spawntime2 = GetTime() + 400.0
    end
    if M.spawntime3 < GetTime() then
        Spawn("hvsat", 2, M.savfactory3)
        M.spawntime3 = GetTime() + 400.0
    end
    if M.spawntime4 < GetTime() then
        Spawn("hvsat", 2, M.savfactory4)
        M.spawntime4 = GetTime() + 400.0
    end
    if (M.discheck < GetTime()) and(M.defenders == false) then
        M.prey1 = NearestEnemy(M.savfactory1)
        if Distance(M.prey1, "savspawn", 1) < 450.0 then
            M.ip1 = Spawn("hvsat", 2, M.savfactory2)
            M.ip2 = Spawn("hvsat", 2, M.savfactory3)
            M.ip3 = Spawn("hvsav", 2, M.savfactory4)
            M.ip4 = Spawn("hvsav", 2, M.savfactory1)
            M.defenders = true
            DefendValid(M.ip1, M.savfactory2)
            DefendValid(M.ip2, M.savfactory3)
            DefendValid(M.ip3, M.savfactory4)
            DefendValid(M.ip4, M.savfactory1)
        end
        M.discheck = GetTime() + 5.0
    end
    if (not IsAlive(M.avrec)) and(M.missionfail == false) then
        FailMission(GetTime() + 20.0, "misn17l1.des")
        AudioMessage("misn1704.wav")
        M.missionfail = true
    end
    if (M.tower1dead == true) and(M.tower2dead == true) and(M.tower3dead == true) and(M.tower4dead == true) and(M.tower5dead == true) and(M.tower6dead == true) and(M.tower7dead == true) and(M.towersdestroyed == false) then
        if M.minesmade == false then
            GetRidOfSomeScrap()
            M.MINE[1] = Spawn("boltmine2", 2, "mine1")
            M.MINE[2] = Spawn("boltmine2", 2, "mine2")
            M.MINE[3] = Spawn("boltmine2", 2, "mine3")
            M.MINE[4] = Spawn("boltmine2", 2, "mine4")
            M.MINE[5] = Spawn("boltmine2", 2, "mine5")
            M.MINE[6] = Spawn("boltmine2", 2, "mine6")
            M.MINE[7] = Spawn("boltmine2", 2, "mine7")
            M.MINE[8] = Spawn("boltmine2", 2, "mine8")
            M.MINE[9] = Spawn("boltmine2", 2, "mine9")
            -- SOURCE BUG FIX: " mine10" has a stray leading space. Use "mine10"
            -- so the tenth mine spawns at its authored path in the same sequence.
            M.MINE[10] = Spawn("boltmine2", 2, "mine10")
            M.MINE[11] = Spawn("boltmine2", 2, "mine11")
            M.MINE[12] = Spawn("boltmine2", 2, "mine12")
            M.MINE[13] = Spawn("boltmine2", 2, "mine13")
            M.MINE[14] = Spawn("boltmine2", 2, "mine14")
            M.MINE[15] = Spawn("boltmine2", 2, "mine15")
            M.MINE[16] = Spawn("boltmine2", 2, "mine16")
            M.MINE[17] = Spawn("boltmine2", 2, "mine17")
            M.MINE[18] = Spawn("boltmine2", 2, "mine18")
            M.MINE[19] = Spawn("boltmine2", 2, "mine19")
            M.MINE[20] = Spawn("boltmine2", 2, "mine20")
            M.MINE[21] = Spawn("boltmine2", 2, "mine21")
            M.MINE[22] = Spawn("boltmine2", 2, "mine22")
            M.MINE[23] = Spawn("boltmine2", 2, "mine23")
            M.MINE[24] = Spawn("boltmine2", 2, "mine24")
            M.MINE[25] = Spawn("boltmine2", 2, "mine25")
            M.MINE[26] = Spawn("boltmine2", 2, "mine26")
            M.MINE[27] = Spawn("boltmine2", 2, "mine27")
            M.MINE[28] = Spawn("boltmine2", 2, "mine28")
            M.MINE[29] = Spawn("boltmine2", 2, "mine29")
            M.MINE[30] = Spawn("boltmine2", 2, "mine30")
            M.MINE[31] = Spawn("boltmine2", 2, "mine31")
            M.MINE[32] = Spawn("boltmine2", 2, "mine32")
            M.MINE[33] = Spawn("boltmine2", 2, "mine33")
            M.MINE[34] = Spawn("boltmine2", 2, "mine34")
            M.MINE[35] = Spawn("boltmine2", 2, "mine35")
            M.MINE[36] = Spawn("boltmine2", 2, "mine36")
            M.MINE[37] = Spawn("boltmine2", 2, "mine37")
            M.MINE[38] = Spawn("boltmine2", 2, "mine38")
            M.MINE[39] = Spawn("boltmine2", 2, "mine39")
            M.MINE[40] = Spawn("boltmine2", 2, "mine40")
            M.MINE[41] = Spawn("boltmine2", 2, "mine41")
            M.MINE[42] = Spawn("boltmine2", 2, "mine42")
            M.MINE[43] = Spawn("boltmine2", 2, "mine43")
            M.MINE[44] = Spawn("boltmine2", 2, "mine44")
            M.MINE[45] = Spawn("boltmine2", 2, "mine45")
            M.MINE[46] = Spawn("boltmine2", 2, "mine46")
            M.MINE[47] = Spawn("boltmine2", 2, "mine47")
            M.MINE[48] = Spawn("boltmine2", 2, "mine48")
            M.MINE[49] = Spawn("boltmine2", 2, "mine49")
            M.MINE[50] = Spawn("boltmine2", 2, "mine50")
            M.MINE[51] = Spawn("boltmine2", 2, "mine51")
            M.MINE[52] = Spawn("boltmine2", 2, "mine52")
            M.MINE[53] = Spawn("boltmine2", 2, "mine53")
            M.minesmade = true
        end
        CameraReady()
        M.newobjective = true
        M.towersdestroyed = true
        M.minesdestroyed = true
        M.minecinstart = true
        M.minecount = 0
        M.mineaudio = AudioMessage("misn1730.wav")
    end
    if (M.minesdestroyed == true) and(M.minesmade == true) then
        -- SOURCE BUG FIX: C++ damages unbuilt MINE[0], then indices 1..53
        -- despite declaring only 53 slots. Preserve its initial no-op frame and
        -- 54-update cadence, but damage only the 53 built mines in a Lua table.
        -- Already-detonated mines are skipped by DamageValid, without pausing.
        if M.minecount >= 1 and M.minecount <= 53 then
            DamageValid(M.MINE[M.minecount], 10000)
        end
        M.minecount = M.minecount + 1
        if M.minecount > 53 then
            M.minesdestroyed = false
        end
    end
    if (M.minesdestroyed == true) and(M.minecin == false) then
        TargetCameraPath("minecin", 1000, 500, M.savfactory2)
    end
    if M.minecinstart == true then
        if (IsAudioMessageDone(M.mineaudio)) or(CameraCancelled()) then
            CameraFinish()
            M.minecin = true
            StopAudioMessage(M.mineaudio)
            M.minecinstart = false
        end
    end
    if (M.missionwon == false) and(not IsAlive(M.factorypart1)) and(not IsAlive(M.factorypart2)) and(not IsAlive(M.factorypart3)) then
        AudioMessage("misn1703.wav")
        M.missionwon = true
        SucceedMission(GetTime() + 4.0, "misn17w1.des")
        CameraReady()
        M.cinscrap = Spawn("eggeizr1", 3, "cinscrap")
        TargetCameraObject(M.cinscrap, 1000, 8000, 1000, M.savfactory1)
        M.sf2blow = GetTime() + 1.0
        M.sf4blow = GetTime() + 2.5
        M.sf3blow = GetTime() + 3.2
    end
    if M.missionwon == true then
        if (M.sf2gone == false) and(M.sf2blow < GetTime()) then
            DamageValid(M.savfactory2, 200000)
            M.sf2gone = true
        end
        if (M.sf3gone == false) and(M.sf3blow < GetTime()) then
            DamageValid(M.savfactory3, 200000)
            M.sf3gone = true
        end
        if (M.sf4gone == false) and(M.sf4blow < GetTime()) then
            DamageValid(M.savfactory4, 200000)
            M.sf4gone = true
        end
    end
end

function Save()
    return M
end

function Load(state)
    -- BZR serializes/remaps handles and audio messages, including nested tables.
    -- Restore without replaying startup, spawning units, or restarting timers.
    M = state
end
