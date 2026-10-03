-- Faithful stock misn16 port for Battlezone 98 Redux / Lua 5.1.
-- Sole behavior authority: BZ1/from_bz2_dll_src/Misn16Mission.cpp.
-- Source blob: 0b6305ff8ec4f218556c4fe1504e7329177e3e48.
-- All original comments are retained in the archive below; disabled code also
-- remains beside its translated logic. Complete native source and empty header
-- are in References/Misn16Source/. See Docs/MISN16_LUA_PORT.md.
-- Stock LuaMission supplies native AI; no EXU/OpenShim/community Lua required.

local function NewState()
    return {
        counter = false, start_done = false, rcam = false,
        won = false, lost = false, camera1 = false,
        next_reinforcement = 99999.0, rcam_time = 99999.0,
        start_time = 99999.0, alien_wave = 99999.0,
        counter_strike2 = 999999.0, wave_gap = 150.0,
        cam_time1 = 99999.0, alien_wave1 = 99999.0, finish_cam = 99999.0,
        rtype = 0, rcount = 0,
        -- Native Load clears all 21 object/message fields before Setup.
        base1 = nil, base2 = nil, reinfo1 = nil, reinfo2 = nil,
        newbie = nil, recy = nil, muf = nil, audmsg1 = nil, audmsg2 = nil,
        cam1 = nil, cam2 = nil, cam3 = nil, cam4 = nil, cam5 = nil,
        sat1 = nil, sat2 = nil, sat3 = nil,
        tow1 = nil, tow2 = nil, tow3 = nil, tow4 = nil,
        -- Port-only fallback position; included in Save/Load with the handles.
        base2_position = nil,
    }
end

-- State exists before Start because map loading can deliver AddObject early.
local M = NewState()

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function Alive(h)
    return Valid(h) and IsAlive(h)
end

local function AudioDone(message)
    return message == nil or message == 0 or IsAudioMessageDone(message)
end

local function AtHangar(odf)
    if Valid(M.base2) then return BuildObject(odf, 2, M.base2) end
    -- PORT FIX: the counterattack can be triggered by destroying the hangar,
    -- and periodic waves continue during the end delay. A destroyed handle is
    -- not a safe Lua BuildObject location. Use its original position instead;
    -- this preserves the authored spawn site, units, and scheduling.
    if M.base2_position ~= nil then
        return BuildObject(odf, 2, M.base2_position)
    end
    -- A map with no alien_hangar has no authored location to recover.
    return nil
end

local function AttackIfValid(me, target, priority)
    -- PORT FIX: do not pass null/deleted handles into the stock Lua overload.
    -- Keep the chosen target and source priority; never reroute to another base.
    if Valid(me) and Valid(target) then Attack(me, target, priority) end
end

function Start()
    M = NewState()
end

function AddObject(h)
    -- Whenever a new soviet unit is added, that unit storms toward the alien base.
    if not Valid(h) or GetTeamNum(h) ~= 1 then return end
    local combat = IsOdf(h, "svtank") or IsOdf(h, "svturr")
        or IsOdf(h, "svfigh") or IsOdf(h, "svwalk")
    local support = not combat and (IsOdf(h, "svscav") or IsOdf(h, "svhaul"))
    if combat or support then
        local target
        if math.random(0, 1) == 0 then target = M.base1 else target = M.base2 end
        if combat then
            AttackIfValid(h, target, 0)
        elseif Valid(target) then
            -- Same null-handle guard as above, including pre-start map callbacks.
            Goto(h, target, 0)
        end
        M.newbie = h -- so we always have one to key on
    end
end

local function Reinforcement()
    if M.rtype == 1 then
        -- The thriteenth workers hauling battilion
        AudioMessage("misn1603.wav")
        BuildObject("svfigh", 1, "starta")
        BuildObject("svhaul", 1, "starta2")
        BuildObject("svhaul", 1, "starta3")
    elseif M.rtype == 2 then
        -- Eighth scrap auxilliries
        AudioMessage("misn1604.wav")
        BuildObject("svscav", 1, "startb")
        BuildObject("svscav", 1, "startb2")
        BuildObject("svfigh", 1, "startb3")
    elseif M.rtype == 3 then
        -- Remenants of various units
        AudioMessage("misn1605.wav")
        BuildObject("svscav", 1, "starta")
        BuildObject("svturr", 1, "starta2")
        BuildObject("svfigh", 1, "starta3")
    elseif M.rtype == 4 then
        -- A scout unit
        AudioMessage("misn1606.wav")
        BuildObject("svfigh", 1, "startb")
        BuildObject("svfigh", 1, "startb2")
    elseif M.rtype == 5 or M.rtype == 6 then
        if M.rtype == 5 then
            -- A light armor unit
            AudioMessage("misn1607.wav")
            BuildObject("svfigh", 1, "starta")
            BuildObject("svfigh", 1, "starta2")
            BuildObject("svtank", 1, "starta3")
        end
        -- SOURCE QUIRK PRESERVED: case 5 has no break, so it also executes case 6.
        -- Adding a break would remove three tanks and one radio call from type 5.
        -- A strike wing
        AudioMessage("misn1607.wav")
        BuildObject("svtank", 1, "startb")
        BuildObject("svtank", 1, "startb2")
        BuildObject("svtank", 1, "startb3")
        --[==[//	BuildObject("svfigh",1,"reinforce24");]==]
        -- Disabled Lua equivalent: BuildObject("svfigh", 1, "reinforce24")
    elseif M.rtype == 7 then
        -- Heavy armor
        AudioMessage("misn1608.wav")
        BuildObject("svwalk", 1, "starta")
        BuildObject("svwalk", 1, "starta2")
        BuildObject("svwalk", 1, "starta3")
        --[==[//	BuildObject("svtank",1,"reinforce14");]==]
        -- Disabled Lua equivalent: BuildObject("svtank", 1, "reinforce14")
    end
end

function Update(dt)
    -- Preserve native Execute order; independent blocks can fire in one update.
    local player = GetPlayerHandle()
    if not M.start_done then
        M.audmsg1 = AudioMessage("misn1601.wav")
        M.audmsg2 = AudioMessage("misn1602.wav")
        M.recy = GetHandle("avrecy0_recycler")
        M.next_reinforcement = GetTime() + 120.0 -- should be 120
        M.rtype = math.random(1, 2) -- same choices as rand()%2+1
        M.start_done = true
        M.base1 = GetHandle("alien_hq")
        M.base2 = GetHandle("alien_hangar")
        if Valid(M.base2) then M.base2_position = GetPosition(M.base2) end
        SetScrap(1, 50)
        SetAIP("misn16.aip")
        ClearObjectives()
        AddObjective("misn1601.otf", "white")
        M.alien_wave = GetTime() + 60.0
        M.alien_wave1 = GetTime() + 90.0
        M.cam1 = GetHandle("apcamr12_camerapod")
        M.cam2 = GetHandle("apcamr15_camerapod")
        M.cam3 = GetHandle("apcamr13_camerapod")
        M.cam4 = GetHandle("apcamr11_camerapod")
        if Valid(M.cam1) then SetObjectiveName(M.cam1, "NW Geyser") end
        if Valid(M.cam2) then SetObjectiveName(M.cam2, "Foothill Geysers") end
        if Valid(M.cam3) then SetObjectiveName(M.cam3, "Geyser Site") end
        if Valid(M.cam4) then SetObjectiveName(M.cam4, "Alien HQ") end
        M.tow1 = GetHandle("sbtowe0_turret")
        M.tow2 = GetHandle("sbtowe1_turret")
        M.tow3 = GetHandle("sbtowe2_turret")
        M.tow4 = GetHandle("sbtowe3_turret")
        M.sat1 = GetHandle("hvsat0_wingman")
        M.sat2 = GetHandle("hvsat1_wingman")
        M.sat3 = GetHandle("hvsat2_wingman")
        if Valid(M.sat1) then Defend(M.sat1, 1) end
        if Valid(M.sat2) then Defend(M.sat2, 1) end
        if Valid(M.sat3) then Defend(M.sat3, 1) end
        M.muf = GetHandle("avmuf26_factory")
        M.camera1 = true
        M.cam_time1 = GetTime() + 20.0
        CameraReady()
    end
    if M.camera1 and Valid(M.base2) then
        CameraPath("camera_path1", 4000, 500, M.base2)
    end
    if M.camera1 and (CameraCancelled() or GetTime() > M.cam_time1
            or AudioDone(M.audmsg2)) then
        M.camera1 = false
        CameraFinish()
    end
    -- PORT FIX: after count 10 the native expired timer increments rcount every
    -- frame forever. Saturate at 10, preventing integer overflow without adding
    -- a reinforcement, radio message, cinematic, or changing the nine waves.
    if M.rcount < 10 and GetTime() > M.next_reinforcement then
        M.rcount = M.rcount + 1
        if M.rcount < 10 then
            Reinforcement()
            -- all times after the first its random
            M.rtype = math.random(1, 7)
            M.next_reinforcement = GetTime() + 180.0
            M.start_time = GetTime() + 2.0 -- give time for units to exist
        else
            --[==[//AudioMessage("misn1614.wav");]==]
            -- Disabled Lua equivalent: AudioMessage("misn1614.wav")
        end
    end
    if GetTime() > M.start_time then
        -- PORT FIX: C++ leaves enemy uninitialized when the player is dead and
        -- also passes an absent nearest enemy to GetDistance. Only a live player
        -- and a valid camera subject can start the optional four-second shot.
        -- No enemy means safe; valid-enemy cases retain the strict >150 test.
        -- Reinforcement timing and the player's combat orders are unchanged.
        if Alive(player) and Valid(M.newbie) then
            local enemy = GetNearestEnemy(player)
            if not Valid(enemy) or GetDistance(player, enemy) > 150.0 then
                M.rcam = true
                M.rcam_time = GetTime() + 4.0
                CameraReady()
            end
        end
        M.start_time = 99999.0
    end
    if M.rcam and Valid(M.newbie) then
        CameraObject(M.newbie, 0, 2000, 3000, M.newbie)
    end
    -- PORT FIX: if the tracked unit disappears during its shot, finish the
    -- camera instead of passing a deleted handle. Normal shots still last 4 s.
    if M.rcam and (M.rcam_time < GetTime() or CameraCancelled()
            or not Valid(M.newbie)) then
        M.rcam = false
        CameraFinish()
        M.rcam_time = 99999.0
    end
    if GetTime() > M.alien_wave then
        AtHangar("hvsav")
        M.alien_wave = GetTime() + M.wave_gap
        if M.wave_gap > 60.0 then M.wave_gap = M.wave_gap - 5.0 end
    end
    if GetTime() > M.alien_wave1 then
        local sat = BuildObject("hvsat", 2, "sat1")
        if Valid(sat) then Goto(sat, "strike1") end
        sat = BuildObject("hvsat", 2, "sat2")
        if Valid(sat) then Goto(sat, "strike2") end
        -- Source coupling is intentional: do not replace with GetTime()+90.
        M.alien_wave1 = M.alien_wave + 90.0
    end
    -- If the user is winning turn up the heat.
    if not M.won and not M.lost and not M.counter and
            ((not Alive(M.tow1) and not Alive(M.tow2))
            or (not Alive(M.tow3) and not Alive(M.tow4))
            or not Alive(M.base1) or not Alive(M.base2)) then
        -- That means one of the entrances is open. Counter attack!!
        local sav1 = AtHangar("hvsav")
        local sav2 = AtHangar("hvsav")
        --[==[//		Handle sav3=BuildObject("hvsav",2,base2);]==]
        -- Disabled Lua equivalent: local sav3 = AtHangar("hvsav")
        AttackIfValid(sav1, M.muf, 1)
        AttackIfValid(sav2, M.muf, 1)
        --[==[//		Attack(sav3,muf,1);]==]
        -- Disabled Lua equivalent: AttackIfValid(sav3, M.muf, 1)
        M.counter = true
        M.counter_strike2 = GetTime() + 120.0 -- another killer attack
    end
    if GetTime() > M.counter_strike2 then
        local sav1 = AtHangar("hvsav")
        local sav2 = AtHangar("hvsav")
        --[==[//		Handle sav3=BuildObject("hvsav",2,base2);]==]
        -- Disabled Lua equivalent: local sav3 = AtHangar("hvsav")
        AttackIfValid(sav1, M.recy, 1)
        AttackIfValid(sav2, M.recy, 1)
        --[==[//		Attack(sav1,recy,1);]==]
        -- Disabled Lua equivalent: AttackIfValid(sav1, M.recy, 1)
        -- The source repeats sav1 here, not sav3; preserve it for reconstruction.
        M.counter_strike2 = 99999.0
    end
    if not M.won and not Alive(M.base1) and not Alive(M.base2) then
        -- We've destroyed the alien building facillity
        AudioMessage("misn1613.wav")
        M.won = true
        SucceedMission(GetTime() + 15.0, "misn16w1.des")
    end
    if not M.lost and not Alive(M.recy) then
        -- We've lost the utah. The soviets are withdrawing
        AudioMessage("misn1612.wav")
        M.lost = true
        FailMission(GetTime() + 15.0, "misn16l1.des")
    end
end

function Save()
    return M
end

function Load(state)
    -- Stock LuaMission serializes tables, object handles, vectors, and messages.
    -- Do not rerun Start/Setup, briefings, AI selection, or random choices here.
    M = state
end

-- Every original C++ comment, in source order (including native lifecycle).
--[====[
/*
	Misn16Mission
*/

// bools

// floats

// handles

// integers

// type of reinforcement, count 

// if we haven't found one there isn't

// one

// two & a half minutes

/*
		Whenever a new soviet unit
		is added, that unit storms
		toward the alien base.  
	*/

// so we always have one to key on

// so we always have one to key on

//should be 120

// wimpy reinforcements, type 1 or 0

/*
					The thriteenth workers 
					hauling battilion
				*/

/*
					Eighth scrap auxilliries
				*/

/*
					Remenants of various units
				*/

/*
					A scout unit
				*/

/*
					A light armor unit
				*/

/* 
					A strike wing
				*/

//	BuildObject("svfigh",1,"reinforce24");

/*
					Heavy armor
				*/

//	BuildObject("svtank",1,"reinforce14");

// all times after the first its random

// give time for units to exist

//AudioMessage("misn1614.wav");

// better safe then sorry

// if safe do cineractive

/*	
		If the user
		is winning turn up
		the heat.
	*/

/*
			That means one of the
			entrances is open.
			Counter attack!!
		*/

//		Handle sav3=BuildObject("hvsav",2,base2);

//		Attack(sav3,muf,1);

// another killer attack

//		Handle sav3=BuildObject("hvsav",2,base2);

//		Attack(sav1,recy,1);

/*
			We've destroyed the 
			alien building facillity
		*/

/*
			We've lost the
			utah.  The soviets
			are withdrawing
		*/

// init bools

// init floats

// init handles

// init ints

// bools

// floats

// Handles

// ints

// bools

// floats

// Handles

// ints
]====]
