-- Faithful BlackDog02Mission port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/BlackDog02Mission.cpp
-- Source blob: 3d27e9760c7eb6d4a4f0adaf8c263552b66c3b23.
-- Disabled C++ is retained in place; the complete original (including native
-- declarations, serialization and all comments) is in References/BlackDog02Source/.
-- Stock BZR 2.1+ is required for SetCloaked. No campaign helpers are required.

-- Keep the original state numbers and spellings, including the gap at state 12.
local MS_STARTUP = 0
local MS_FIRSTWAVE = 1
local MS_WAITFORSOUND1 = 2
local MS_WAITFORWAVE1 = 3
local MS_PLAYDECLOCK = 4
local MS_WAITINGOBJ2 = 5
local MS_WAVE1DEAD = 6
local MS_WAITFORWAVE2 = 7
local MS_WAVE2DEAD = 8
local MS_PLAYSOUND4 = 9
local MS_WAITFORSOUND4 = 10
local MS_WAITFORSOUND5 = 11
local MS_HARRASDEAD = 13
local MS_WAITFORBOMBERRUN = 14
local MS_BOMBERRUN = 15
local MS_RECYCLERDIE = 16
local MS_ENDWAIT = 17
local MS_END = 18

local function NewState()
    return {
        -- bools: have we lost? / recycler retreat ambush latch
        lost = false, recyclerRetreated = false,
        -- floats: timer to say when the next state starts / so I know when it's been hit..
        stateTimer = 99999.0, recyclerHealth = 99999.0,
        -- PORT FIX: native Load sets deadTimer to 99999; if the player is dead
        -- on the first Update, that postpones the death check for hours. Zero
        -- arms the intended two-second grace period immediately. A normal
        -- living-player first frame already writes zero, so normal flow is unchanged.
        deadTimer = 0,
        -- integers: the state of the mission / sound handle (nil replaces C++ 0)
        missionState = MS_STARTUP,
        -- Handles start nil: user, recycler, wave1_scout1/2, wave1_tank1,
        -- wave2_scout1..4, enemy_scout1..4, enemy_ltnk1/2, enemy_tank1/2,
        -- enemy_turret1..4, nav_alpha, harrass_scout1, harrass_ltnk1,
        -- bomber1_scripted, bomber2_scripted; soundhandle is audio userdata.
    }
end

local M = NewState()

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function Alive(h)
    return Valid(h) and IsAlive(h)
end

local function Distance(h, path)
    -- PORT FIX: an absent object must not satisfy a proximity trigger. Guard
    -- the Lua handle overload; distances for surviving objects are unchanged.
    if not Valid(h) then return math.huge end
    return GetDistance(h, path)
end

local function HealBomber(h)
    -- PORT FIX: native code tests only a nonzero handle, then dereferences
    -- GetObj even after destruction. Skip missing objects instead of crashing;
    -- surviving bombers receive exactly the same per-frame health top-up.
    -- This does not resurrect/rebuild bombers or make them damage-immune.
    if Valid(h) then
        local current, maximum = GetCurHealth(h), GetMaxHealth(h)
        if current ~= maximum then AddHealth(h, maximum - current) end
    end
end

local function RecyclerCamera()
    if Valid(M.recycler) then
        CameraPath("camera_bomber_chasecam", 1000, 0, M.recycler)
    else
        -- PORT FIX: destruction can invalidate the camera's target before the
        -- final narration ends. Continue on the same path facing along it;
        -- no replacement unit, mission gate, narration or delay is introduced.
        CameraPathDir("camera_bomber_chasecam", 1000, 0)
    end
end

local function ResetObjectives()
    ClearObjectives()
    if M.missionState < MS_HARRASDEAD then
        AddObjective("bd02001.otf", M.missionState >= MS_WAVE1DEAD and "green" or "white")
        if M.missionState >= MS_WAITFORSOUND4 then
            AddObjective("bd02002.otf", "green")
        elseif M.missionState >= MS_WAVE1DEAD then
            AddObjective("bd02002.otf", "white")
        end
    end
    if M.missionState >= MS_END then
        AddObjective("bd02003.otf", "red")
    elseif M.missionState >= MS_HARRASDEAD then
        AddObjective("bd02003.otf", "white")
    end
end

function Start()
    -- Setup: resource/cloak/objective startup still happens on the first Update.
    M = NewState()
    M.recycler = GetHandle("recycler")
    M.enemy_turret1 = GetHandle("enemy_turret1")
    M.enemy_turret2 = GetHandle("enemy_turret2")
    M.enemy_turret3 = GetHandle("enemy_turret3")
    M.enemy_turret4 = GetHandle("enemy_turret4")
end

function AddObject(h)
    --[[ Original cut factory gate. MS_WAITFORFACTORY is not defined in this mission.
	if (missionState == MS_WAITFORFACTORY && IsOdf(h, "bvmuf"))
	{
		// set to first wave and setup the timer till it kicks off
		missionState = MS_WAITFORWAVE1;
		stateTimer = GetTime() + (60 + 5); // 30 seconds to build factory??
//		stateTimer = GetTime() + (5); // 30 seconds to build factory??
		resetObjectives();
	}
    ]]
end

local function Lose(filename)
    FailMission(GetTime() + 2.0, filename)
    M.lost = true
    -- PORT FIX: release an active pre-ending cinematic on defeat; native code
    -- can leave camera control held. This only releases the view and retains
    -- the original failure filename and two-second delay.
    if M.missionState == MS_PLAYDECLOCK or M.missionState == MS_WAITFORSOUND4
        or M.missionState == MS_WAITFORSOUND5 then
        CameraFinish()
    end
end

function Update(dt)
    M.user = GetPlayerHandle() -- assigns the player a handle every frame
    -- PORT FIX: once defeat is scheduled, stop mission work even if the player
    -- is still dead. Native !lost && !IsAlive can otherwise leave one more
    -- state transition in the recycler-loss frame, entering the ending and
    -- bypassing its later lost check. Living mission flow is unchanged.
    if M.lost then return end
    if M.missionState < MS_RECYCLERDIE then
        if not Alive(M.user) then
            -- Lua considers 0 true; explicitly reproduce C++'s timer test.
            if M.deadTimer ~= 0 then
                if M.deadTimer < GetTime() then
                    Lose("bd02lose.des")
                    return
                end
            else
                M.deadTimer = GetTime() + 2
            end
        else
            M.deadTimer = 0
        end
        if not Alive(M.recycler) then
            Lose("bd02lsea.des")
            return
        end
    end

    local state = M.missionState
    if state == MS_STARTUP then
        SetScrap(1, 20)
        SetPilot(1, 10)
        -- setup the cloaked turrets
        if Valid(M.enemy_turret1) then SetCloaked(M.enemy_turret1) end
        if Valid(M.enemy_turret2) then SetCloaked(M.enemy_turret2) end
        if Valid(M.enemy_turret3) then SetCloaked(M.enemy_turret3) end
        if Valid(M.enemy_turret4) then SetCloaked(M.enemy_turret4) end
        -- setup the initial objectives
        ResetObjectives()
        M.missionState = MS_FIRSTWAVE
        M.stateTimer = GetTime() + 2
    elseif state == MS_FIRSTWAVE then
        if M.stateTimer < GetTime() then
            M.soundhandle = AudioMessage("bd02001.wav")
            M.missionState = MS_WAITFORSOUND1
            M.stateTimer = 0
        end
    elseif state == MS_WAITFORSOUND1 then
        if IsAudioMessageDone(M.soundhandle) then
            M.missionState = MS_WAITFORWAVE1
            M.stateTimer = GetTime() + 20
        end
    elseif state == MS_WAITFORWAVE1 then
        if M.stateTimer < GetTime() then
            M.wave1_scout1 = BuildObject("cvfigh", 2, "spawn_wave1_scout1")
            M.wave1_scout2 = BuildObject("cvfigh", 2, "spawn_wave1_scout2")
            M.wave1_tank1 = BuildObject("cvtnk", 2, "spawn_wave1_tank1")
            AudioMessage("bd02002.wav")
            CameraReady()
            M.missionState = MS_PLAYDECLOCK
            if Valid(M.wave1_scout1) then Goto(M.wave1_scout1, "wave1_scout1_attackpath") end
            if Valid(M.wave1_scout2) then Goto(M.wave1_scout2, "wave1_scout2_attackpath") end
            if Valid(M.wave1_tank1) then Goto(M.wave1_tank1, "wave1_tank1_attackpath") end
            -- Native switch deliberately falls through into MS_PLAYDECLOCK.
            state = MS_PLAYDECLOCK
        end
    elseif state == MS_WAITINGOBJ2 then
        if M.stateTimer < GetTime() then
            M.missionState = MS_WAVE1DEAD
            AudioMessage("bd02003.wav")
            ResetObjectives()
        end
    elseif state == MS_WAVE1DEAD then
        if not Alive(M.wave1_scout1) and not Alive(M.wave1_scout2) and not Alive(M.wave1_tank1) then
            M.missionState = MS_WAITFORWAVE2
            M.stateTimer = GetTime() + 20
        end
    elseif state == MS_WAITFORWAVE2 then
        if M.stateTimer < GetTime() then
            M.missionState = MS_WAVE2DEAD
            M.wave2_scout1 = BuildObject("cvfigh", 2, "spawn_wave2_scout1")
            M.wave2_scout2 = BuildObject("cvfigh", 2, "spawn_wave2_scout2")
            M.wave2_scout3 = BuildObject("cvfigh", 2, "spawn_wave2_scout3")
            M.wave2_scout4 = BuildObject("cvfigh", 2, "spawn_wave2_scout4")
            if Valid(M.wave2_scout1) then Goto(M.wave2_scout1, "wave2_scout1_attackpath") end
            if Valid(M.wave2_scout2) then Goto(M.wave2_scout2, "wave2_scout2_attackpath") end
            if Valid(M.wave2_scout3) then Goto(M.wave2_scout3, "wave2_scout3_attackpath") end
            if Valid(M.wave2_scout4) then Goto(M.wave2_scout4, "wave2_scout4_attackpath") end
        end
    elseif state == MS_WAVE2DEAD then
        if not Alive(M.wave2_scout1) and not Alive(M.wave2_scout2)
            and not Alive(M.wave2_scout3) and not Alive(M.wave2_scout4) then
            M.missionState = MS_PLAYSOUND4
            M.stateTimer = GetTime() + 10
        end
    elseif state == MS_PLAYSOUND4 then
        if M.stateTimer < GetTime() then
            M.soundhandle = AudioMessage("bd02004.wav")
            M.missionState = MS_WAITFORSOUND4
            ResetObjectives()
            M.enemy_scout1 = BuildObject("cvfigh", 2, "spawn_enemy_scout1")
            M.enemy_scout2 = BuildObject("cvfigh", 2, "spawn_enemy_scout2")
            M.enemy_scout3 = BuildObject("cvfigh", 2, "spawn_enemy_scout3")
            M.enemy_scout4 = BuildObject("cvfigh", 2, "spawn_enemy_scout4")
            M.enemy_ltnk1 = BuildObject("cvltnk", 2, "spawn_enemy_ltnk")
            M.enemy_ltnk2 = BuildObject("cvltnk", 2, "spawn_enemy_ltnk2")
            M.enemy_tank1 = BuildObject("cvtnk", 2, "spawn_enemy_tank")
            M.enemy_tank2 = BuildObject("cvtnk", 2, "spawn_enemy_tank2")
            if Valid(M.enemy_scout1) then Goto(M.enemy_scout1, "spawn_nav_alpha") end
            if Valid(M.enemy_scout2) then Goto(M.enemy_scout2, "spawn_nav_alpha") end
            if Valid(M.enemy_scout3) then Goto(M.enemy_scout3, "spawn_nav_alpha") end
            if Valid(M.enemy_scout4) then Goto(M.enemy_scout4, "spawn_nav_alpha") end
            if Valid(M.enemy_ltnk1) then Goto(M.enemy_ltnk1, "spawn_nav_alpha") end
            if Valid(M.enemy_ltnk2) then Goto(M.enemy_ltnk2, "spawn_nav_alpha") end
            if Valid(M.enemy_tank1) then Goto(M.enemy_tank1, "spawn_nav_alpha") end
            if Valid(M.enemy_tank2) then Goto(M.enemy_tank2, "spawn_nav_alpha") end
            if Alive(M.enemy_turret1) then Goto(M.enemy_turret1, "path_turret1") end
            if Alive(M.enemy_turret2) then Goto(M.enemy_turret2, "path_turret2") end
            if Alive(M.enemy_turret3) then Goto(M.enemy_turret3, "path_turret3") end
            if Alive(M.enemy_turret4) then Goto(M.enemy_turret4, "path_turret4") end
            CameraReady()
            -- The second intentional native switch fall-through.
            state = MS_WAITFORSOUND4
        end
    elseif state == MS_WAITFORSOUND5 then
        if Valid(M.enemy_tank1) then CameraPath("camera_massive_attack", 2000, 10, M.enemy_tank1) end
        if IsAudioMessageDone(M.soundhandle) then
            CameraFinish()
            if Valid(M.enemy_scout1) then RemoveObject(M.enemy_scout1) end
            if Valid(M.enemy_scout2) then RemoveObject(M.enemy_scout2) end
            if Valid(M.enemy_scout3) then RemoveObject(M.enemy_scout3) end
            if Valid(M.enemy_scout4) then RemoveObject(M.enemy_scout4) end
            if Valid(M.enemy_ltnk1) then RemoveObject(M.enemy_ltnk1) end
            if Valid(M.enemy_ltnk2) then RemoveObject(M.enemy_ltnk2) end
            if Valid(M.enemy_tank1) then RemoveObject(M.enemy_tank1) end
            if Valid(M.enemy_tank2) then RemoveObject(M.enemy_tank2) end
            -- nav alpha (what else could it be???)
            M.nav_alpha = BuildObject("apcamr", 1, "spawn_nav_alpha")
            if Valid(M.nav_alpha) then SetObjectiveName(M.nav_alpha, "Nav Alpha") end -- native SetName alias
            M.missionState = MS_HARRASDEAD
            M.stateTimer = GetTime() + 4 -- retained even though the source never tests it
            ResetObjectives()
            -- Retreat(recycler, "path_recycler_retreat");
            Goto(M.recycler, "path_recycler_retreat")
            M.recyclerRetreated = false
            M.harrass_scout1 = BuildObject("cvfigh", 2, "spawn_scout1_harrass")
            M.harrass_ltnk1 = BuildObject("cvltnk", 2, "spawn_ltnk1_harrass")
            -- Attack(harrass_scout1, user);
            -- Attack(harrass_ltnk1, user);
            if Valid(M.harrass_scout1) and Valid(M.user) then Goto(M.harrass_scout1, M.user) end
            if Valid(M.harrass_ltnk1) and Valid(M.user) then Goto(M.harrass_ltnk1, M.user) end
        end
    elseif state == MS_HARRASDEAD then
        if not M.recyclerRetreated and Distance(M.recycler, "trigger_1") < 100 then
            for i = 0, 5 do
                local temp = BuildObject("cvfigh", 2, "fighter_1")
                if Valid(temp) and Valid(M.user) then Attack(temp, M.user) end
            end
            M.recyclerRetreated = true
        end
        -- Source does not require harassment deaths or the unused +4 timer.
        if GetCurrentCommand(M.recycler) == AiCommand.NONE then
            Stop(M.recycler)
            M.soundhandle = AudioMessage("bd02006.wav")
            M.missionState = MS_WAITFORBOMBERRUN
        end
    elseif state == MS_WAITFORBOMBERRUN then
        if IsAudioMessageDone(M.soundhandle) then
            if Valid(M.harrass_scout1) then RemoveObject(M.harrass_scout1) end
            if Valid(M.harrass_ltnk1) then RemoveObject(M.harrass_ltnk1) end
            if Valid(M.enemy_turret1) then RemoveObject(M.enemy_turret1) end
            if Valid(M.enemy_turret2) then RemoveObject(M.enemy_turret2) end
            if Valid(M.enemy_turret3) then RemoveObject(M.enemy_turret3) end
            if Valid(M.enemy_turret4) then RemoveObject(M.enemy_turret4) end
            AudioMessage("bd02007.wav")
            M.bomber1_scripted = BuildObject("cvhraz", 2, "spawn_bomber_1")
            -- Goto(bomber_scripted, "path_bomber_attackpath");
            if Valid(M.bomber1_scripted) then Attack(M.bomber1_scripted, M.recycler) end
            M.bomber2_scripted = BuildObject("cvhraz", 2, "spawn_bomber_2")
            if Valid(M.bomber2_scripted) then Attack(M.bomber2_scripted, M.recycler) end
            M.recyclerHealth = GetHealth(M.recycler)
            M.soundhandle = nil -- C++ 0; do not pass Lua number 0 as audio userdata
            M.missionState = MS_BOMBERRUN
        end
    elseif state == MS_BOMBERRUN then
        HealBomber(M.bomber1_scripted)
        HealBomber(M.bomber2_scripted)
        if Distance(M.bomber1_scripted, "camera_bomber_chasecam") <= 50
            or Distance(M.bomber2_scripted, "camera_bomber_chasecam") <= 50 then
            CameraReady()
            M.missionState = MS_RECYCLERDIE
        end
    elseif state == MS_RECYCLERDIE then
        HealBomber(M.bomber1_scripted)
        HealBomber(M.bomber2_scripted)
        -- CameraPath("camera_bomber_chasecam", 1000, 0, bomber_scripted);
        RecyclerCamera()
        if M.recyclerHealth ~= 0 and (not Alive(M.recycler) or M.recyclerHealth ~= GetHealth(M.recycler)) then -- it's been hit...
            -- Recycler *myRecycler = (Recycler *) GameObjectHandle::GetObj(recycler);
            -- myRecycler->Explode();
            M.recyclerHealth = 0
            AudioMessage("bd02008.wav")
            -- myRecycler->AddHealth(-((myRecycler->GetCurHealth() / 4) * 3));
            -- Stop(bomber_scripted);
            -- RemoveObject(bomber_scripted);
            -- bomber_scripted = 0;
            -- stateTimer = GetTime() + 3;
        end
        if M.soundhandle == nil and not Alive(M.recycler) then
            M.soundhandle = AudioMessage("bd02009.wav")
        end
        -- PORT FIX: source has `if (!soundhandle && IsAudioMessageDone(soundhandle))`.
        -- It polls a zero handle before destruction, and becomes false once
        -- bd02009 supplies a real handle, potentially skipping/stalling the end.
        -- Wait for that real final message. This restores the existing intended
        -- recycler-death -> narration -> three-second camera hold -> success
        -- sequence; all waves, prerequisites and original delays stay intact.
        if M.soundhandle ~= nil and IsAudioMessageDone(M.soundhandle) then
            --[[
//				Recycler *myRecycler = (Recycler *) GameObjectHandle::GetObj(recycler);
//				if(myRecycler)
//				{
//					myRecycler->Explode();
//				}
            ]]
            M.missionState = MS_ENDWAIT
            M.stateTimer = GetTime() + 3
            ResetObjectives()
        end
    elseif state == MS_ENDWAIT then
        RecyclerCamera()
        if M.stateTimer < GetTime() then
            M.missionState = MS_END
            CameraFinish()
            SucceedMission(GetTime() + 5.0, "bd02win.des")
        end
    end

    -- Separate blocks reproduce only the two deliberate C++ fall-throughs;
    -- all other state changes wait until the next Update, as in the switch.
    if state == MS_PLAYDECLOCK then
        local arrived = false
        if Valid(M.wave1_scout1) then
            arrived = CameraPath("camera_decloak", 2000, 1000, M.wave1_scout1)
        end
        -- PORT FIX: release the decloak shot if its subject vanishes. This
        -- substitutes for an unusable camera's completion, retaining the +5 wait.
        if arrived or CameraCancelled() or not Valid(M.wave1_scout1) then
            CameraFinish()
            M.missionState = MS_WAITINGOBJ2
            M.stateTimer = GetTime() + 5
        end
    elseif state == MS_WAITFORSOUND4 then
        if Valid(M.enemy_tank1) then CameraPath("camera_massive_attack", 2000, 10, M.enemy_tank1) end
        if IsAudioMessageDone(M.soundhandle) then
            M.soundhandle = AudioMessage("bd02005.wav")
            M.missionState = MS_WAITFORSOUND5
        end
    end
end

function Save()
    return M
end

function Load(state)
    -- LuaMission restores the state table, including engine handles/audio.
    -- Do not replay Setup, rebuild units, reset objectives, or restart timers.
    M = state
end
