-- bdmisn2.lua (Converted from BlackDog02Mission.cpp)
-- Source-disabled alternatives retained as design notes: recycler Retreat
-- instead of Goto; harassers Attack instead of Goto; bomber pathing before its
-- recycler Attack; removing/stopping the bomber after impact; and a second
-- recycler Explode fallback. The first-hit Explode branch is restored below.
-- The source also disabled an AddObject-driven factory trigger:
--   if missionState == MS_WAITFORFACTORY and IsOdf(h, "bvmuf") then
--       missionState = MS_WAITFORWAVE1; stateTimer = GetTime() + 65
--   end
-- and disabled Goto(bomber_scripted, "path_bomber_attackpath") immediately
-- before the scripted bomber's recycler Attack.

-- Compatibility
SetLabel = SetLabel or SetLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})
local exu = require("exu")
local aiCore = require("aiCore")

-- Helper for AI
local function SetupAI()
    -- Team 1: Black Dogs (Player)
    -- Team 2: CAA (Enemy)
    local caa = aiCore.AddTeam(2, aiCore.Factions.CCA)

    local diff = (exu and exu.GetDifficulty and exu.GetDifficulty()) or 2
    if diff <= 1 then
        caa:SetConfig("pilotZeal", 0.1)
    elseif diff >= 3 then
        caa:SetConfig("pilotZeal", 0.9)
    else
        caa:SetConfig("pilotZeal", 0.4)
    end
end

-- Variables
local start_done = false
local lost = false
local recycler_retreated = false
local recycler_health_prev = 0
local dead_timer = 99999.0
local state_timer = 0
local mission_state = 0

-- State Constants
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

-- Handles
local user, recycler
local wave1_scout1, wave1_scout2, wave1_tank1
local wave2_scout1, wave2_scout2, wave2_scout3, wave2_scout4
local enemy_scout1, enemy_scout2, enemy_scout3, enemy_scout4
local enemy_ltnk1, enemy_ltnk2, enemy_tank1, enemy_tank2
local enemy_turret1, enemy_turret2, enemy_turret3, enemy_turret4
local nav_alpha
local harrass_scout1, harrass_ltnk1
local bomber1_scripted, bomber2_scripted

local soundhandle

-- Difficulty
local difficulty = 2

-- Preserve native mission state across save/load.
function Save()
    return {
        start_done = start_done,
        lost = lost,
        recycler_retreated = recycler_retreated,
        recycler_health_prev = recycler_health_prev,
        dead_timer = dead_timer,
        state_timer = state_timer,
        mission_state = mission_state,
        user = user,
        recycler = recycler,
        wave1_scout1 = wave1_scout1,
        wave1_scout2 = wave1_scout2,
        wave1_tank1 = wave1_tank1,
        wave2_scout1 = wave2_scout1,
        wave2_scout2 = wave2_scout2,
        wave2_scout3 = wave2_scout3,
        wave2_scout4 = wave2_scout4,
        enemy_scout1 = enemy_scout1,
        enemy_scout2 = enemy_scout2,
        enemy_scout3 = enemy_scout3,
        enemy_scout4 = enemy_scout4,
        enemy_ltnk1 = enemy_ltnk1,
        enemy_ltnk2 = enemy_ltnk2,
        enemy_tank1 = enemy_tank1,
        enemy_tank2 = enemy_tank2,
        enemy_turret1 = enemy_turret1,
        enemy_turret2 = enemy_turret2,
        enemy_turret3 = enemy_turret3,
        enemy_turret4 = enemy_turret4,
        nav_alpha = nav_alpha,
        harrass_scout1 = harrass_scout1,
        harrass_ltnk1 = harrass_ltnk1,
        bomber1_scripted = bomber1_scripted,
        bomber2_scripted = bomber2_scripted,
        soundhandle = soundhandle,
        difficulty = difficulty,
    }
end

function Load(state)
    if not state then return end
    start_done = state.start_done
    lost = state.lost
    recycler_retreated = state.recycler_retreated
    recycler_health_prev = state.recycler_health_prev
    dead_timer = state.dead_timer
    state_timer = state.state_timer
    mission_state = state.mission_state
    user = state.user
    recycler = state.recycler
    wave1_scout1 = state.wave1_scout1
    wave1_scout2 = state.wave1_scout2
    wave1_tank1 = state.wave1_tank1
    wave2_scout1 = state.wave2_scout1
    wave2_scout2 = state.wave2_scout2
    wave2_scout3 = state.wave2_scout3
    wave2_scout4 = state.wave2_scout4
    enemy_scout1 = state.enemy_scout1
    enemy_scout2 = state.enemy_scout2
    enemy_scout3 = state.enemy_scout3
    enemy_scout4 = state.enemy_scout4
    enemy_ltnk1 = state.enemy_ltnk1
    enemy_ltnk2 = state.enemy_ltnk2
    enemy_tank1 = state.enemy_tank1
    enemy_tank2 = state.enemy_tank2
    enemy_turret1 = state.enemy_turret1
    enemy_turret2 = state.enemy_turret2
    enemy_turret3 = state.enemy_turret3
    enemy_turret4 = state.enemy_turret4
    nav_alpha = state.nav_alpha
    harrass_scout1 = state.harrass_scout1
    harrass_ltnk1 = state.harrass_ltnk1
    bomber1_scripted = state.bomber1_scripted
    bomber2_scripted = state.bomber2_scripted
    soundhandle = state.soundhandle
    difficulty = state.difficulty
end
function Start()
    if exu then
        difficulty = (exu.GetDifficulty and exu.GetDifficulty()) or 2
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
    end
    SetupAI()
    start_done = false
end

local function ResetObjectives()
    ClearObjectives()

    if mission_state < MS_HARRASDEAD then
        if mission_state >= MS_WAVE1DEAD then
            AddObjective("bd02001.otf", "green")
        else
            AddObjective("bd02001.otf", "white")
        end

        if mission_state >= MS_WAITFORSOUND4 then
            AddObjective("bd02002.otf", "green")
        elseif mission_state >= MS_WAVE1DEAD then
            AddObjective("bd02002.otf", "white")
        end
    end

    if mission_state >= MS_END then
        AddObjective("bd02003.otf", "red")
    elseif mission_state >= MS_HARRASDEAD then
        AddObjective("bd02003.otf", "white")
    end
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then
        aiCore.AddObject(h)
    end
end

function DeleteObject(h)
end

function Update()
    user = GetPlayerHandle()
    aiCore.Update()

    if not start_done then
        recycler = GetHandle("recycler")
        enemy_turret1 = GetHandle("enemy_turret1")
        enemy_turret2 = GetHandle("enemy_turret2")
        enemy_turret3 = GetHandle("enemy_turret3")
        enemy_turret4 = GetHandle("enemy_turret4")

        SetScrap(1, 20)
        SetPilot(1, 10)

        SetCloaked(enemy_turret1, true)
        SetCloaked(enemy_turret2, true)
        SetCloaked(enemy_turret3, true)
        SetCloaked(enemy_turret4, true)

        mission_state = MS_FIRSTWAVE
        state_timer = GetTime() + 2.0
        ResetObjectives()

        start_done = true
    end

    -- Recycler Dead Logic (Before Planned Death)
    if mission_state < MS_RECYCLERDIE then
        if not IsAlive(recycler) and not lost then
            FailMission(GetTime() + 2.0, "bd02lsea.des")
            lost = true
        end
    end

    -- Player Dead Logic
    if mission_state < MS_RECYCLERDIE then
        if not IsAlive(user) and not lost then
            if dead_timer == 99999.0 then
                dead_timer = GetTime() + 2.0
            elseif GetTime() > dead_timer then
                FailMission(GetTime() + 2.0, "bd02lose.des")
                lost = true
            end
        else
            dead_timer = 99999.0
        end
    end

    if lost then return end

    -- Mission State Machine
    if mission_state == MS_FIRSTWAVE then
        if GetTime() > state_timer then
            soundhandle = AudioMessage("bd02001.wav")
            mission_state = MS_WAITFORSOUND1
        end

    elseif mission_state == MS_WAITFORSOUND1 then
        if soundhandle and IsAudioMessageDone(soundhandle) then
            soundhandle = nil
            mission_state = MS_WAITFORWAVE1
            state_timer = GetTime() + 20.0
        end

    elseif mission_state == MS_WAITFORWAVE1 then
        if GetTime() > state_timer then
            wave1_scout1 = BuildObject("cvfigh", 2, "spawn_wave1_scout1")
            wave1_scout2 = BuildObject("cvfigh", 2, "spawn_wave1_scout2")
            wave1_tank1 = BuildObject("cvtnk", 2, "spawn_wave1_tank1")

            AudioMessage("bd02002.wav")
            CameraReady()

            mission_state = MS_PLAYDECLOCK

            Goto(wave1_scout1, "wave1_scout1_attackpath")
            Goto(wave1_scout2, "wave1_scout2_attackpath")
            Goto(wave1_tank1, "wave1_tank1_attackpath")
        end

    elseif mission_state == MS_PLAYDECLOCK then
        local arrived = CameraPath("camera_decloak", 2000, 1000, wave1_scout1)
        if arrived or CameraCancelled() then
            CameraFinish()
            mission_state = MS_WAITINGOBJ2
            state_timer = GetTime() + 5.0
        end

    elseif mission_state == MS_WAITINGOBJ2 then
        if GetTime() > state_timer then
            mission_state = MS_WAVE1DEAD
            AudioMessage("bd02003.wav")
            ResetObjectives()
        end

    elseif mission_state == MS_WAVE1DEAD then
        if not IsAlive(wave1_scout1) and not IsAlive(wave1_scout2) and not IsAlive(wave1_tank1) then
            mission_state = MS_WAITFORWAVE2
            state_timer = GetTime() + 20.0
        end

    elseif mission_state == MS_WAITFORWAVE2 then
        if GetTime() > state_timer then
            mission_state = MS_WAVE2DEAD
            wave2_scout1 = BuildObject("cvfigh", 2, "spawn_wave2_scout1")
            wave2_scout2 = BuildObject("cvfigh", 2, "spawn_wave2_scout2")
            wave2_scout3 = BuildObject("cvfigh", 2, "spawn_wave2_scout3")
            wave2_scout4 = BuildObject("cvfigh", 2, "spawn_wave2_scout4")

            Goto(wave2_scout1, "wave2_scout1_attackpath")
            Goto(wave2_scout2, "wave2_scout2_attackpath")
            Goto(wave2_scout3, "wave2_scout3_attackpath")
            Goto(wave2_scout4, "wave2_scout4_attackpath")
        end

    elseif mission_state == MS_WAVE2DEAD then
        if not IsAlive(wave2_scout1) and not IsAlive(wave2_scout2) and not IsAlive(wave2_scout3) and not IsAlive(wave2_scout4) then
            mission_state = MS_PLAYSOUND4
            state_timer = GetTime() + 10.0
        end

    elseif mission_state == MS_PLAYSOUND4 then
        if GetTime() > state_timer then
            soundhandle = AudioMessage("bd02004.wav")
            mission_state = MS_WAITFORSOUND4
            ResetObjectives()

            -- Massive Spawn
            enemy_scout1 = BuildObject("cvfigh", 2, "spawn_enemy_scout1")
            enemy_scout2 = BuildObject("cvfigh", 2, "spawn_enemy_scout2")
            enemy_scout3 = BuildObject("cvfigh", 2, "spawn_enemy_scout3")
            enemy_scout4 = BuildObject("cvfigh", 2, "spawn_enemy_scout4")
            enemy_ltnk1 = BuildObject("cvltnk", 2, "spawn_enemy_ltnk")
            enemy_ltnk2 = BuildObject("cvltnk", 2, "spawn_enemy_ltnk2")
            enemy_tank1 = BuildObject("cvtnk", 2, "spawn_enemy_tank")
            enemy_tank2 = BuildObject("cvtnk", 2, "spawn_enemy_tank2")

            local nav_pt = "spawn_nav_alpha"
            Goto(enemy_scout1, nav_pt); Goto(enemy_scout2, nav_pt)
            Goto(enemy_scout3, nav_pt); Goto(enemy_scout4, nav_pt)
            Goto(enemy_ltnk1, nav_pt); Goto(enemy_ltnk2, nav_pt)
            Goto(enemy_tank1, nav_pt); Goto(enemy_tank2, nav_pt)

            if IsAlive(enemy_turret1) then Goto(enemy_turret1, "path_turret1") end
            if IsAlive(enemy_turret2) then Goto(enemy_turret2, "path_turret2") end
            if IsAlive(enemy_turret3) then Goto(enemy_turret3, "path_turret3") end
            if IsAlive(enemy_turret4) then Goto(enemy_turret4, "path_turret4") end

            CameraReady()
        end

    elseif mission_state == MS_WAITFORSOUND4 then
        CameraPath("camera_massive_attack", 2000, 10, enemy_tank1)

        if soundhandle and IsAudioMessageDone(soundhandle) then
            soundhandle = AudioMessage("bd02005.wav")
            mission_state = MS_WAITFORSOUND5
        end

    elseif mission_state == MS_WAITFORSOUND5 then
        CameraPath("camera_massive_attack", 2000, 10, enemy_tank1)

        if soundhandle and IsAudioMessageDone(soundhandle) then
            soundhandle = nil
            CameraFinish()

            -- Cleanup
            RemoveObject(enemy_scout1); RemoveObject(enemy_scout2)
            RemoveObject(enemy_scout3); RemoveObject(enemy_scout4)
            RemoveObject(enemy_ltnk1); RemoveObject(enemy_ltnk2)
            RemoveObject(enemy_tank1); RemoveObject(enemy_tank2)

            nav_alpha = BuildObject("apcamr", 1, "spawn_nav_alpha")
            SetLabel(nav_alpha, "Nav Alpha")

            mission_state = MS_HARRASDEAD
            state_timer = GetTime() + 4.0
            ResetObjectives()

            Goto(recycler, "path_recycler_retreat")
            recycler_retreated = false

            harrass_scout1 = BuildObject("cvfigh", 2, "spawn_scout1_harrass")
            harrass_ltnk1 = BuildObject("cvltnk", 2, "spawn_ltnk1_harrass")

            Goto(harrass_scout1, user)
            Goto(harrass_ltnk1, user)
        end

    elseif mission_state == MS_HARRASDEAD then
        if not recycler_retreated and GetDistance(recycler, "trigger_1") < 100.0 then
            -- Spawn harassers
            for i=1,6 do
                local temp = BuildObject("cvfigh", 2, "fighter_1")
                Attack(temp, user)
            end
            recycler_retreated = true
        end

        if GetCurrentCommand(recycler) == AiCommand.NONE then
             Stop(recycler)
             soundhandle = AudioMessage("bd02006.wav")
             mission_state = MS_WAITFORBOMBERRUN
        end

    elseif mission_state == MS_WAITFORBOMBERRUN then
        if soundhandle and IsAudioMessageDone(soundhandle) then
            soundhandle = nil
            RemoveObject(harrass_scout1); RemoveObject(harrass_ltnk1)
            RemoveObject(enemy_turret1); RemoveObject(enemy_turret2)
            RemoveObject(enemy_turret3); RemoveObject(enemy_turret4)

            AudioMessage("bd02007.wav")

            bomber1_scripted = BuildObject("cvhraz", 2, "spawn_bomber_1")
            Attack(bomber1_scripted, recycler)

            bomber2_scripted = BuildObject("cvhraz", 2, "spawn_bomber_2")
            Attack(bomber2_scripted, recycler)

            recycler_health_prev = GetHealth(recycler)
            mission_state = MS_BOMBERRUN
        end

    elseif mission_state == MS_BOMBERRUN then
        -- Invincible Bombers
        if IsAlive(bomber1_scripted) then AddHealth(bomber1_scripted, 1000) end
        if IsAlive(bomber2_scripted) then AddHealth(bomber2_scripted, 1000) end

        if (IsAlive(bomber1_scripted) and GetDistance(bomber1_scripted, "camera_bomber_chasecam") <= 50.0) or
           (IsAlive(bomber2_scripted) and GetDistance(bomber2_scripted, "camera_bomber_chasecam") <= 50.0) then
            CameraReady()
            mission_state = MS_RECYCLERDIE
        end

    elseif mission_state == MS_RECYCLERDIE then
        if IsAlive(bomber1_scripted) then AddHealth(bomber1_scripted, 1000) end
        if IsAlive(bomber2_scripted) then AddHealth(bomber2_scripted, 1000) end

        CameraPath("camera_bomber_chasecam", 1000, 0, recycler)

        if IsAlive(recycler) and GetHealth(recycler) < recycler_health_prev then
            -- Hit!
            recycler_health_prev = 0
            AudioMessage("bd02008.wav")

            -- Restored cut branch: BlackDog02Mission.cpp comments out
            -- myRecycler->Explode() on this first hit. Redux Lua has no Explode
            -- binding, so lethal damage is the direct equivalent.
            Damage(recycler, 10000)
        end

        if not soundhandle and not IsAlive(recycler) then
            soundhandle = AudioMessage("bd02009.wav")
        end

        if soundhandle and IsAudioMessageDone(soundhandle) then
            soundhandle = nil
            mission_state = MS_ENDWAIT
            state_timer = GetTime() + 3.0
            ResetObjectives()
        end

    elseif mission_state == MS_ENDWAIT then
        CameraPath("camera_bomber_chasecam", 1000, 0, recycler) -- Or wrecks

        if GetTime() > state_timer then
            mission_state = MS_END
            CameraFinish()
            SucceedMission(GetTime() + 5.0, "bd02win.des")
        end
    end
end

