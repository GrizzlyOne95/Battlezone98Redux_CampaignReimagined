-- Tran05Mission.cpp faithful port for stock Battlezone 98 Redux / Lua 5.1.
-- Native map: misn02b.bzn. Kept separate from the reimagined misn02b.lua.
-- Source blob: f318d388fb7976a40652c88b0fb375dcc18fc93a.
-- Full native source: References/EarlyMissionSources/Tran05Mission.cpp.
-- No EXU/OpenShim/project modules; preserve source Execute ordering and timing.
-- INTEGRATION: select this script in a copy of the original mission map.
-- Native PostLoad subtracts 40 from player_path.points[7]. Stock Lua has no
-- path-point setter: apply that x offset once in the map editor (eighth point)
-- before using this script. Do not repeatedly subtract it on saved-game load.
-- Goto retains the engine's path-following behavior rather than approximating
-- it with Lua waypoint proximity checks. The map itself is not changed here.

local function NewState()
    return {
        camera1 = false, camera2 = false, camera3 = false,
        found = false, found2 = false, start_done = false, patrol1 = false,
        message1 = false, message2 = false, message3 = false,
        message4 = false, message5 = false, message6 = false,
        message7 = false, message8 = false, message9 = false,
        message10 = false, message11 = false, message12 = false,
        message13 = false, message14 = false, message15 = false,
        mission_won = false, mission_lost = false, jump_start = false,
        repeat_time = 0, wave_timer = 0, last_wave_time = 99999,
        dramatic_pause = 99999, NextSecond = 99999,
        camera_delay = 0, cam_time = 0, num_reps = 0, on_point = 0,
        -- Native null handles/path pointers and audio ID 0 are nil in Lua.
        -- Unused player/target1/target2/muf/camera/wing and p1..p4 stay nil.
    }
end

local M = NewState()

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function Alive(h)
    return Valid(h) and IsAlive(h)
end

local function Near(a, b, distance)
    -- PORT FIX: native GetObj dereferences and null distance queries can access
    -- missing/dead objects. Only evaluate distances with existing endpoints;
    -- every live-object trigger and its strict threshold remain unchanged.
    return Valid(a) and Valid(b) and GetDistance(a, b) < distance
end

local function AudioDone(msg)
    -- Native ID 0 means no pending playback. Lua uses message userdata/nil.
    return msg == nil or IsAudioMessageDone(msg)
end

function Start()
    M = NewState()
end

-- this is the handle thing brad made for me
function AddObject(h)
    if not Valid(h) then return end
    if GetTeamNum(h) == 1 and IsOdf(h, "avscav") and M.bscav == nil then
        M.found = true
        M.bscav = h
    end
    if GetTeamNum(h) == 2 and IsOdf(h, "svfigh") then
        if not M.found2 then
            M.found2 = true
            M.bscout = h
            Goto(M.bscout, "patrol1", 0)
            SetObjectiveOn(M.bscout)
        elseif Near(M.bscav, M.bgoal, 200) then
            Attack(h, M.bscav)
        else
            Goto(h, "patrol2", 0) -- attack scrap field
        end
    end
end

function Update(dt)
    M.bplayer = GetPlayerHandle()
    if not M.start_done then
        SetPilot(1, 2)
        SetScrap(1, 5)
        local team = 2 -- hard wired, hope this doesn't change
        SetAIP("misn02.aip", team)
        M.dummy = GetHandle("fake_player")
        M.lander = GetHandle("avland0_wingman")
        M.bhandle = GetHandle("sscr_171_scrap")
        M.bhome = GetHandle("abcomm1_i76building")
        M.recycler = GetHandle("avrecy-1_recycler")
        -- bplayer=GetHandle("player-1_hover");
        M.bgoal = GetHandle("apscrap-1_camerapod")
        M.bhandle2 = GetHandle("sscr_176_scrap")
        if Valid(M.bgoal) then SetUserTarget(M.bgoal) end
        M.start_done = true
        M.camera1 = true
        M.cam_time = GetTime() + 30
        CameraReady()
        M.audmsg = AudioMessage("misn0230.wav")
    end
    if M.camera1 then
        if (Valid(M.lander) and CameraPath("fixcam", 1200, 250, M.lander))
            or CameraCancelled() or AudioDone(M.audmsg) then
            -- (GetTime()>cam_time))) -- cut native timeout, still inactive
            M.camera1 = false
            M.cam_time = GetTime() + 10
            M.camera2 = true
        end
    end
    if M.camera2 then
        M.camera2 = false
        M.camera3 = true
        if Valid(M.dummy) then Goto(M.dummy, "player_path") end
        M.cam_time = GetTime() + 25
        -- Final actor audio has both tracks in one place
        -- StopAudioMessage(audmsg);
        -- audmsg = AudioMessage("misn0232.wav");
    end
    if M.camera3 then
        if (Valid(M.dummy) and CameraPath("zoomcam", 1200, 800, M.dummy))
            or AudioDone(M.audmsg) or CameraCancelled() then
            M.camera3 = false
            M.cam_time = 99999
            CameraFinish()
            if Valid(M.dummy) then RemoveObject(M.dummy) end
            if M.audmsg ~= nil then StopAudioMessage(M.audmsg) end
            M.audmsg = nil
            AudioMessage("misn0224.wav")
            -- Native Get_Time() and GetTime() share simulation time here.
            M.wave_timer = GetTime() + 30
            AddObjective("misn02b1.otf", "white")
        end
    end
    if not M.patrol1 and M.found and Near(M.bhandle, M.bscav, 75) then
        -- Native VECTOR_3D ted = ...GetPosition() was unused; no Lua query.
        BuildObject("svfigh", 2, "spawn1")
        AudioMessage("misn0233.wav")
        M.message1 = true
        M.patrol1 = true
        if not M.message4 and M.found2 then
            -- bscout=GetHandle("svfigh-1_wingman");
            M.message4 = true
        end
    end
    if not M.message4 and M.found2 then
        -- this is in case the AddObject is called in
        -- a different frame then the BuildObject() above
        M.message4 = true
    end
    if M.message4 and not M.message5 and Near(M.bscav, M.bhandle2, 200) then -- was bgoal
        BuildObject("svfigh", 2, "spawn2")
        -- if (bscout!=NULL) Attack(bscout,bscav,1);
        M.message5 = true
        M.wave_timer = GetTime() + 30
    end
    if M.message5 and GetTime() > M.wave_timer then
        BuildObject("svfigh", 2, "spawn2")
        M.wave_timer = GetTime() + 45
    end
    if M.message1 and M.message5 and not M.message2 and Alive(M.bscav)
        and Valid(M.bhome) and GetLastEnemyShot(M.bscav) > 0 then
        -- send the scav home; bscav to bbase
        -- Native CMD_FOLLOW included a temporary two-point AiPath from scav
        -- to home. Stock Follow supplies the same target, with explicit source
        -- priority 0; Lua cannot attach that private AiPath to a command.
        Follow(M.bscav, M.bhome, 0)
        ClearObjectives()
        AddObjective("misn02b2.otf", "white")
        AudioMessage("misn0225.wav")
        local bbase = GetHandle("apbase-1_camerapod")
        if Valid(bbase) then SetUserTarget(bbase) end
        M.message2 = true
    end
    -- PORT FIX: native victory and defeat share audmsg and can both latch in
    -- one frame (e.g. base destroyed as scav2 arrives), overwriting the failure
    -- audio and scheduling both outcomes. Loss retains the source's earlier
    -- evaluation priority; once either result is latched, retain it. Ordinary
    -- play keeps exactly the same objectives, narration and completion time.
    if not M.mission_lost and not M.mission_won and
        ((M.bscav ~= nil and -- was message2, so we know a scav was built
            (not Alive(M.bplayer) or not Alive(M.bscav)
                or (M.message3 and not Alive(M.scav2))))
            or not Alive(M.bhome) or not Alive(M.recycler)) then
        ClearObjectives()
        AddObjective("misn02b4.otf", "red")
        M.audmsg = AudioMessage("misn0227.wav")
        M.mission_lost = true
    end
    if M.mission_lost and AudioDone(M.audmsg) then
        FailMission(GetTime(), "misn02l1.des")
    end
    if not M.mission_lost and not M.mission_won and Alive(M.bplayer)
        and M.message1 and M.message4 and Near(M.bhome, M.bscav, 300)
        and not M.message3 then
        -- Now rescue the second scavenger. Source intentionally does NOT
        -- require message2 here; do not introduce an extra retreat gate.
        Follow(M.bscav, M.bhome)
        M.wave_timer = GetTime() + 45
        M.scav2 = BuildObject("avscav", 1, "spawn3")
        if Valid(M.scav2) then
            Retreat(M.scav2, "retreat")
            SetObjectiveOn(M.scav2)
        end
        AudioMessage("misn0228.wav")
        M.last_wave_time = GetTime() + 10
        M.NextSecond = GetTime() + 1
        M.message3 = true
    end
    if Alive(M.bscav) and M.message3 and GetTime() > M.NextSecond then
        AddHealth(M.bscav, 200)
        M.NextSecond = GetTime() + 1
    end
    if M.last_wave_time < GetTime() then
        local sid = BuildObject("svfigh", 2, "spawn4")
        if Valid(sid) and Valid(M.scav2) then Attack(sid, M.scav2) end
        M.last_wave_time = 99999
    end
    if M.message3 and not M.mission_won and not M.mission_lost
        and Near(M.bhome, M.scav2, 200) then
        ClearObjectives()
        AddObjective("misn02b3.otf", "green")
        if Alive(M.bscav) then AddHealth(M.bscav, 1000) end
        if Alive(M.scav2) then AddHealth(M.scav2, 1000) end
        -- AudioMessage("misn0226.wav");
        M.audmsg = AudioMessage("misn0234.wav")
        M.mission_won = true
    end
    if M.mission_won and AudioDone(M.audmsg) then
        SucceedMission(GetTime(), "misn02w1.des")
    end
end

function Save()
    return M
end

function Load(state)
    -- LuaMission remaps serialized handles/messages. Do not run Setup again,
    -- replay the intro, restart timers or reissue orders on saved-game load.
    M = state
end

-- Complete original comment/cut-content ledger; all fragments stay inactive.
--[==[

Tran05Mission.cpp:17
/*
	Tran05Mission
*/

Tran05Mission.cpp:21
// used by (misn02b.bzn) as first american mission

Tran05Mission.cpp:42
// bools

Tran05Mission.cpp:76
// floats

Tran05Mission.cpp:92
// handles

Tran05Mission.cpp:111
// the base

Tran05Mission.cpp:118
// path pointers

Tran05Mission.cpp:131
// integers

Tran05Mission.cpp:181
// this is the handle thing brad made for me

Tran05Mission.cpp:212
// attack scrap field

Tran05Mission.cpp:225
// hard wired, hope this doesn't change

Tran05Mission.cpp:227
/*
			misn0224
			Commander, we've discovered a deposit of bio metal..
			stay close to the scavenger.  
		*/

Tran05Mission.cpp:237
//	bplayer=GetHandle("player-1_hover");

Tran05Mission.cpp:252
//(GetTime()>cam_time)))

Tran05Mission.cpp:265
// Final actor audio has both tracks in one place

Tran05Mission.cpp:266
//	StopAudioMessage(audmsg);

Tran05Mission.cpp:267
//		audmsg = AudioMessage("misn0232.wav");

Tran05Mission.cpp:301
//bscout=GetHandle("svfigh-1_wingman");

Tran05Mission.cpp:307
// this is in case the AddObject is called in 

Tran05Mission.cpp:308
// a different frame then the BuildObject() above

Tran05Mission.cpp:311
// was bgoal

Tran05Mission.cpp:314
//		if (bscout!=NULL) Attack(bscout,bscav,1);

Tran05Mission.cpp:329
// send the scav home

Tran05Mission.cpp:330
// bscav to bbase

Tran05Mission.cpp:339
/*
			misn0225
			Commander our insturments show that you are heavily
			ounumbered..
		*/

Tran05Mission.cpp:349
// was message2, so we know a scav was built

Tran05Mission.cpp:359
/*
			You or the scav is dead
			*/

Tran05Mission.cpp:364
/*
			misn0227
			Eagle's Nest 1 is being overrun.  
			Our forces are surrendering..
		*/

Tran05Mission.cpp:381
/*
			Now rescue the second
			scavenger
		*/

Tran05Mission.cpp:414
/*
			misn0226
			Good work.  I know you wanted to engage..
		*/

Tran05Mission.cpp:418
//	AudioMessage("misn0226.wav");

Tran05Mission.cpp:457
// bools

Tran05Mission.cpp:462
// floats

Tran05Mission.cpp:467
// Handles

Tran05Mission.cpp:472
// path pointers

Tran05Mission.cpp:478
// ints

Tran05Mission.cpp:489
// hack path to go around buildings

Tran05Mission.cpp:517
// bools

Tran05Mission.cpp:522
// floats

Tran05Mission.cpp:527
// Handles

Tran05Mission.cpp:532
// path pointers

Tran05Mission.cpp:538
// ints
]==]
