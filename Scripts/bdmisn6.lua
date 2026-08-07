-- bdmisn6.lua (Converted from BlackDog06Mission.cpp)
-- Source-disabled note: the 11-minute destruction deadline also had a visible
-- StartCockpitTimer(11 * 60) display; active source uses only stateTimer2.

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
local won = false
local portal_ours = false
local recycler_dropped = false
local random_attack = true
local soundhandle

-- States
local MS_STARTUP = 0
local MS_STARTCAMERA = 1
local MS_WAITING1 = 2
local MS_WAITFORSOUND2 = 3
local MS_WAITING2 = 4
local MS_FAKEATTACKCAMERA = 5
local MS_WAITFORALL2BDESTDEAD = 6
local MS_WAITFORREDDEVIL = 7
local MS_WAITFORBADGUY = 8
local MS_WAITFORBADGUY1DIE = 9
local MS_WAITFORBADGUY2 = 10
local MS_WAITFORBADGUY2DIE = 11
local MS_WAITFORSOUND3 = 12
local MS_WAITFOROBJECTIVE2 = 13
local MS_WAITFORRECYCLER = 14
local MS_WAITFORBADGUY3 = 15
local MS_WAITFORAPC = 16
local MS_ENDCUTSCENE = 17
local MS_WAITING3 = 18
local MS_WAITAPCFINISHED = 19
local MS_WAITAPCOUT = 20
local MS_WAITFORSOUND8 = 21
local MS_WAITING4 = 22
local MS_RECYCLERDEAD = 23
local MS_ATTACKTOEARLY = 24

local mission_state = MS_STARTUP
local state_timer = 0
local state_timer2 = 0
local state_timer3 = 0
local state_timer4 = 0

-- Handles
local user
local recycler
local portal
local apc_handle
local bdtank = {} -- 1..10
local silo_attack = {} -- 1..10
local h2bdest = {} -- 1..6
local portal_attack = {} -- 1..2
local random_attackers = {} -- 1..5
local badguy = {} -- 1..3

-- Difficulty
local difficulty = 2

-- Preserve native mission state across save/load.
function Save()
    return {
        start_done = start_done,
        lost = lost,
        won = won,
        portal_ours = portal_ours,
        recycler_dropped = recycler_dropped,
        random_attack = random_attack,
        soundhandle = soundhandle,
        mission_state = mission_state,
        state_timer = state_timer,
        state_timer2 = state_timer2,
        state_timer3 = state_timer3,
        state_timer4 = state_timer4,
        user = user,
        recycler = recycler,
        portal = portal,
        apc_handle = apc_handle,
        bdtank = bdtank,
        silo_attack = silo_attack,
        h2bdest = h2bdest,
        portal_attack = portal_attack,
        random_attackers = random_attackers,
        badguy = badguy,
        difficulty = difficulty,
    }
end

function Load(state)
    if not state then return end
    start_done = state.start_done
    lost = state.lost
    won = state.won
    portal_ours = state.portal_ours
    recycler_dropped = state.recycler_dropped
    random_attack = state.random_attack
    soundhandle = state.soundhandle
    mission_state = state.mission_state
    state_timer = state.state_timer
    state_timer2 = state.state_timer2
    state_timer3 = state.state_timer3
    state_timer4 = state.state_timer4
    user = state.user
    recycler = state.recycler
    portal = state.portal
    apc_handle = state.apc_handle
    bdtank = state.bdtank
    silo_attack = state.silo_attack
    h2bdest = state.h2bdest
    portal_attack = state.portal_attack
    random_attackers = state.random_attackers
    badguy = state.badguy
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

    if mission_state >= MS_WAITFORSOUND3 then
        AddObjective("bd06001.otf", "green")
    elseif mission_state >= MS_WAITING1 then
        AddObjective("bd06001.otf", "white")
    end

    if portal_ours then
        AddObjective("bd06002.otf", "green")
    elseif mission_state >= MS_WAITFORRECYCLER then
        AddObjective("bd06002.otf", "white")
    end
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then
        aiCore.AddObject(h)
    end
    -- Track APCs?
end

function DeleteObject(h)
end

function Update()
    user = GetPlayerHandle()
    aiCore.Update()

    if not start_done then
        SetScrap(1, 75)
        SetPilot(1, 10)

        recycler = nil -- Not built yet
        portal = GetHandle("portal")
        apc_handle = nil

        for i=1,10 do
            silo_attack[i] = GetHandle("silo_attack"..i)
            bdtank[i] = GetHandle("bdtank_"..i)
        end

        h2bdest[1] = GetHandle("2bdest_1")
        h2bdest[2] = GetHandle("2bdest_2")
        h2bdest[3] = GetHandle("2bdest_3")
        h2bdest[4] = GetHandle("2bdest_7")
        h2bdest[5] = GetHandle("2bdest_9")
        h2bdest[6] = GetHandle("2bdest_10")

        start_done = true
        mission_state = MS_STARTCAMERA
        state_timer = GetTime() + 2.0
        CameraReady()
        ResetObjectives()
    end

    -- Lose Conditions
    if not lost then
        if not IsAlive(portal) then
            FailMission(GetTime() + 2.0, "bd06lseb.des")
            lost = true
        end

        -- APC capture logic check. The source enumerates every bvapc, captures
        -- the first within 100 metres of apc_in, and only fails after both the
        -- recycler and the entire APC roster are gone.
        if not portal_ours and recycler then
            local apc_count = 0
            for candidate in AllCraft() do
                if IsOdf(candidate, "bvapc") then
                    if GetDistance(candidate, "apc_in") < 100.0 then
                        Goto(candidate, "apc_in")
                        apc_handle = candidate
                        portal_ours = true
                        soundhandle = nil
                        ResetObjectives()
                        for k=1,3 do
                            local t = BuildObject("cvartl", 2, "portal_attack_1")
                            Attack(t, portal)
                        end
                        mission_state = MS_ENDCUTSCENE
                        state_timer = 0
                        CameraReady()
                        break
                    end
                    apc_count = apc_count + 1
                end
            end

            if not portal_ours and apc_count == 0 and not IsAlive(recycler) and mission_state ~= MS_RECYCLERDEAD then
                mission_state = MS_RECYCLERDEAD
                soundhandle = AudioMessage("bd06006.wav")
            end
        end
    elseif lost then
        return
    end

    -- Recurring pressure restored from the C++ timers. Portal animation helpers
    -- are not exposed to Lua, so portal attackers spawn at its live transform.
    if state_timer4 > 0 and state_timer4 < GetTime() then
        for i=1,2 do
            local roll = math.random()
            local odf = roll < 0.33 and "cvfigh" or (roll < 0.66 and "cvtnk" or "cvrckt")
            portal_attack[i] = BuildObject(odf, 2, GetTransform(portal))
            Goto(portal_attack[i], "camera_go")
        end
        state_timer4 = GetTime() + 80.0
    end

    if state_timer3 > 0 and state_timer3 < GetTime() then
        for i=1,5 do
            local odf = math.random() < 0.5 and "cvfigh" or "cvtnk"
            random_attackers[i] = BuildObject(odf, 2, "attack_always")
            Hunt(random_attackers[i])
        end
        state_timer3 = GetTime() + 110.0
    end

    -- State Machine
    if mission_state == MS_STARTCAMERA then
        local arrived = CameraPath("camera_start", 1000, 2500, portal)

        if GetTime() > state_timer and not soundhandle then -- soundhandle used as flag
            soundhandle = AudioMessage("bd06001.wav")
        end

        if arrived or CameraCancelled() then
            CameraFinish()
            mission_state = MS_WAITING1
            state_timer = GetTime() + 20.0
            state_timer2 = GetTime() + (11 * 60.0) -- Timer?
            ResetObjectives()
            soundhandle = nil
        end

    elseif mission_state == MS_WAITING1 then
        if GetTime() > state_timer then
            soundhandle = AudioMessage("bd06002.wav")
            for i=1,10 do
                if IsAlive(silo_attack[i]) then Goto(silo_attack[i], "fake_attack") end
            end
            mission_state = MS_WAITFORSOUND2
        else
            -- Check integrity (Early Attack fail)
            for i=1,10 do
                local o = silo_attack[i]
                if IsAlive(o) and GetHealth(o) < GetMaxHealth(o) then -- Taken damage
                    mission_state = MS_ATTACKTOEARLY
                    soundhandle = AudioMessage("bd06007.wav")
                    return
                end
            end
        end

    elseif mission_state == MS_WAITFORSOUND2 then
        if soundhandle and IsAudioMessageDone(soundhandle) then
            soundhandle = nil
            mission_state = MS_WAITING2
            state_timer = GetTime() + 3.0
        end

    elseif mission_state == MS_WAITING2 then
        if GetTime() > state_timer then
            mission_state = MS_FAKEATTACKCAMERA
            state_timer = GetTime() + 5.0
            CameraReady()
        end

    elseif mission_state == MS_FAKEATTACKCAMERA then
        local cam_target = silo_attack[3] or portal
        local arrived = CameraPath("camera_go", 2000, 2000, cam_target)

        if arrived or CameraCancelled() or GetTime() > state_timer then
            for i=1,10 do
                if IsAlive(silo_attack[i]) then RemoveObject(silo_attack[i]) end
            end
            CameraFinish()
            mission_state = MS_WAITFORALL2BDESTDEAD
        end

    elseif mission_state == MS_WAITFORALL2BDESTDEAD then
        if GetTime() > state_timer2 then -- Time limit
            FailMission(GetTime()+2.0, "bd06lsed.des")
            lost = true
        end

        local all_dead = true
        for i=1,6 do if IsAlive(h2bdest[i]) then all_dead = false break end end

        if all_dead then
            mission_state = MS_WAITFORREDDEVIL
            ResetObjectives()
            state_timer = GetTime() + 90.0
            state_timer3 = GetTime() + 110.0 -- Random Attack Timer
            state_timer4 = GetTime() + 80.0 -- Portal Attack Timer
        end

    elseif mission_state == MS_WAITFORREDDEVIL then
        if GetTime() > state_timer then
            -- Spawn Backup
            local dead_count = 0
            for i=1,10 do if not IsAlive(bdtank[i]) then dead_count = dead_count + 1 end end
            dead_count = math.min(dead_count, 5) -- Limit

            for i=1,dead_count do
                local t = BuildObject("bvrdeva", 1, "backup_1")
                Goto(t, "backup_path")
            end

            state_timer = GetTime() + 90.0
            mission_state = MS_WAITFORBADGUY
        end

    elseif mission_state == MS_WAITFORBADGUY then
        if GetTime() > state_timer then
            badguy[1] = BuildObject("cvtnk", 2, "attack_1"); Attack(badguy[1], user)
            badguy[2] = BuildObject("cvtnk", 2, "attack_1"); Attack(badguy[2], user)
            mission_state = MS_WAITFORBADGUY1DIE
        end

    elseif mission_state == MS_WAITFORBADGUY1DIE then
        if not IsAlive(badguy[1]) then
            state_timer = GetTime() + 180.0 -- 3 mins
            mission_state = MS_WAITFORBADGUY2
        end

    elseif mission_state == MS_WAITFORBADGUY2 then
        if GetTime() > state_timer then
            badguy[1] = BuildObject("cvtnk", 2, "attack_2"); Attack(badguy[1], user)
            badguy[2] = BuildObject("cvtnk", 2, "attack_2"); Attack(badguy[2], user)
            badguy[3] = BuildObject("cvtnk", 2, "attack_2"); Attack(badguy[3], user)
            mission_state = MS_WAITFORBADGUY2DIE
        end

    elseif mission_state == MS_WAITFORBADGUY2DIE then
        if not IsAlive(badguy[1]) and not IsAlive(badguy[2]) and not IsAlive(badguy[3]) then
            mission_state = MS_WAITFORSOUND3
            ResetObjectives()
            soundhandle = AudioMessage("bd06003.wav")
        end

    elseif mission_state == MS_WAITFORSOUND3 then
        if soundhandle and IsAudioMessageDone(soundhandle) then
            soundhandle = nil
            recycler = BuildObject("bvrecy", 1, "recycler_spawn")
            Goto(recycler, "recycler_path")

            local t = BuildObject("bvrdeva", 1, "recycler_spawn"); Follow(t, recycler)
            t = BuildObject("bvrdeva", 1, "recycler_spawn"); Follow(t, recycler)

            state_timer = GetTime() + 30.0
            mission_state = MS_WAITFOROBJECTIVE2
        end

    elseif mission_state == MS_WAITFOROBJECTIVE2 then
        if GetTime() > state_timer then
            mission_state = MS_WAITFORRECYCLER
            ResetObjectives()
        end

    elseif mission_state == MS_WAITFORRECYCLER then
        if IsAlive(recycler) and GetCurrentCommand(recycler) == AiCommand.NONE then
            Deploy(recycler)
            AudioMessage("bd06004.wav")
            mission_state = MS_WAITFORBADGUY3
            state_timer = GetTime() + 60.0
        end

    elseif mission_state == MS_WAITFORBADGUY3 then
        -- The C++ stores a 60-second timer but does not test it in this state;
        -- the five hunters spawn on the next update exactly as authored.
        for i=1,5 do
            local t = BuildObject("cvtnk", 2, "attack_3")
            Hunt(t)
        end
        mission_state = MS_WAITFORAPC

    elseif mission_state == MS_WAITFORAPC then
        -- Handled in main loop (Lose/Win check)

    elseif mission_state == MS_ENDCUTSCENE then
        -- APC In Portal
        if apc_handle and GetCurrentCommand(apc_handle) == AiCommand.NONE then
            RemoveObject(apc_handle)
            apc_handle = nil
            soundhandle = AudioMessage("bd06009.wav")
            state_timer2 = GetTime() + 60.0
        end

        if soundhandle and IsAudioMessageDone(soundhandle) then
            soundhandle = nil
            for i=1,7 do
                local t = BuildObject("cvtnk", 2, "dummy_1")
                Goto(t, "dummy_1_path")
            end
            state_timer = GetTime() + 3.0
        end

        local arrived = CameraPath("camera_end_scene", 2000, 0, apc_handle or portal)
        if arrived or (state_timer > 0 and (CameraCancelled() or GetTime() > state_timer)) then
            CameraFinish()
            mission_state = MS_WAITING3
            state_timer = GetTime() + 5.0
        end

    elseif mission_state == MS_WAITING3 then
        if GetTime() > state_timer then
            for i=1,7 do
                local t = BuildObject("cvfigh", 2, "portal_attack_2")
                Attack(t, portal)
            end
            mission_state = MS_WAITAPCFINISHED
        end

    elseif mission_state == MS_WAITAPCFINISHED then
        if GetTime() > state_timer2 then
            apc_handle = BuildObject("bvapc", 1, GetTransform(portal))
            Goto(apc_handle, "apc_out")
            mission_state = MS_WAITAPCOUT
        end

    elseif mission_state == MS_WAITAPCOUT then
        if apc_handle and GetCurrentCommand(apc_handle) == AiCommand.NONE then
            SucceedMission(GetTime() + 10.0, "bd06wina.des")
            won = true
            -- The native script reuses its terminal "lost" guard here so no
            -- later failure or pressure event can fire during the win delay.
            lost = true
        end
        -- Cut source branch retained for restoration reference: the disabled
        -- C++ alternative played "bd06008.wav", waited five seconds, played
        -- "bd06005.wav", then scheduled the same success. It is intentionally not
        -- substituted for the active original ending above.

    elseif mission_state == MS_RECYCLERDEAD then
        if soundhandle and IsAudioMessageDone(soundhandle) then
            soundhandle = nil
            FailMission(GetTime() + 2.0, "bd06lsec.des")
            lost = true
        end

    elseif mission_state == MS_ATTACKTOEARLY then
        if soundhandle and IsAudioMessageDone(soundhandle) then
            soundhandle = nil
            FailMission(GetTime() + 2.0, "bd06lsea.des")
            lost = true
        end
    end
end

