-- bdmisn8.lua (Converted from BlackDog08Mission.cpp)

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
local objective1_complete = false
local objective2_complete = false
local objective3_complete = false
local camera_ready = {false, false}
local camera_complete = {false, false}
local arrived = false
local pilot_spawned1 = false
local pilot_spawned2 = false
local portal_reprogrammed = false
local apc_heading_back = false
local schedule_lose2 = false
local schedule_lose3 = false
local apc_commandeered = false
local lost = false
local won = false

-- Timers
local second_camera_time = 99999.0
local activate_time = 99999.0
local attack_wave_time = 99999.0
local apc_time = 99999.0
local apc_pilot_time1 = 99999.0
local apc_pilot_time2 = 99999.0
local apc_go_back_time = 99999.0
local sound3_time = 99999.0

-- Handles
local user
local recycler, portal, command, factory
local nav_portal, nav_base
local apc, pilot
local attackers = {
    "cvtnk", "cvtnk", "cvltnk", "cvfigh", "cvfigh",
    "cvfigh", "cvfigh", "cvfigh", "cvrckt", "cvhraz"
}
local wave_count = 0

-- Sounds (Flags)
local intro_sound, intro2_sound, win_sound, lose_sound2, lose_sound3

-- Difficulty
local difficulty = 2

-- Preserve native mission state across save/load.
function Save()
    return {
        start_done = start_done,
        objective1_complete = objective1_complete,
        objective2_complete = objective2_complete,
        objective3_complete = objective3_complete,
        camera_ready = camera_ready,
        camera_complete = camera_complete,
        arrived = arrived,
        pilot_spawned1 = pilot_spawned1,
        pilot_spawned2 = pilot_spawned2,
        portal_reprogrammed = portal_reprogrammed,
        apc_heading_back = apc_heading_back,
        schedule_lose2 = schedule_lose2,
        schedule_lose3 = schedule_lose3,
        apc_commandeered = apc_commandeered,
        lost = lost,
        won = won,
        second_camera_time = second_camera_time,
        activate_time = activate_time,
        attack_wave_time = attack_wave_time,
        apc_time = apc_time,
        apc_pilot_time1 = apc_pilot_time1,
        apc_pilot_time2 = apc_pilot_time2,
        apc_go_back_time = apc_go_back_time,
        sound3_time = sound3_time,
        user = user,
        recycler = recycler,
        portal = portal,
        command = command,
        factory = factory,
        nav_portal = nav_portal,
        nav_base = nav_base,
        apc = apc,
        pilot = pilot,
        attackers = attackers,
        wave_count = wave_count,
        intro_sound = intro_sound,
        intro2_sound = intro2_sound,
        win_sound = win_sound,
        lose_sound2 = lose_sound2,
        lose_sound3 = lose_sound3,
        difficulty = difficulty,
    }
end

function Load(state)
    if not state then return end
    start_done = state.start_done
    objective1_complete = state.objective1_complete
    objective2_complete = state.objective2_complete
    objective3_complete = state.objective3_complete
    camera_ready = state.camera_ready
    camera_complete = state.camera_complete
    arrived = state.arrived
    pilot_spawned1 = state.pilot_spawned1
    pilot_spawned2 = state.pilot_spawned2
    portal_reprogrammed = state.portal_reprogrammed
    apc_heading_back = state.apc_heading_back
    schedule_lose2 = state.schedule_lose2
    schedule_lose3 = state.schedule_lose3
    apc_commandeered = state.apc_commandeered
    lost = state.lost
    won = state.won
    second_camera_time = state.second_camera_time
    activate_time = state.activate_time
    attack_wave_time = state.attack_wave_time
    apc_time = state.apc_time
    apc_pilot_time1 = state.apc_pilot_time1
    apc_pilot_time2 = state.apc_pilot_time2
    apc_go_back_time = state.apc_go_back_time
    sound3_time = state.sound3_time
    user = state.user
    recycler = state.recycler
    portal = state.portal
    command = state.command
    factory = state.factory
    nav_portal = state.nav_portal
    nav_base = state.nav_base
    apc = state.apc
    pilot = state.pilot
    attackers = state.attackers
    wave_count = state.wave_count
    intro_sound = state.intro_sound
    intro2_sound = state.intro2_sound
    win_sound = state.win_sound
    lose_sound2 = state.lose_sound2
    lose_sound3 = state.lose_sound3
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
        SetScrap(1, 100)
        SetPilot(1, 10)

        recycler = GetHandle("recycler")
        portal = GetHandle("portal")
        command = GetHandle("command")
        factory = GetHandle("factory")
        nav_portal = GetHandle("nav_portal")
        if nav_portal then SetName(nav_portal, "Portal") end
        nav_base = GetHandle("nav_base")
        if nav_base then SetName(nav_base, "Black Dog Base") end

        start_done = true
    end

    -- Cam 1: Intro
    if not camera_complete[1] then
        if not camera_ready[1] then
            camera_ready[1] = true
            CameraReady()
            intro_sound = AudioMessage("bd08001.wav")
        end

        if not arrived then
            arrived = CameraPath("path_camera_intro", 800, 1500, user)
        end

        local sequence_done = arrived and intro_sound and IsAudioMessageDone(intro_sound)
        if CameraCancelled() then
            sequence_done = true
            if intro_sound then StopAudioMessage(intro_sound) end
        end

        if sequence_done then
            CameraFinish()
            camera_complete[1] = true
            second_camera_time = GetTime() + 25.0 -- Wait before Cam 2
            arrived = false -- Reset
        end
    end

    -- Cam 2: Portal
    if GetTime() > second_camera_time and not camera_complete[2] then
        if not camera_ready[2] then
            camera_ready[2] = true
            CameraReady()
            intro2_sound = AudioMessage("bd08002.wav")

            ClearObjectives()
            AddObjective("bd08001.otf", "white")

            activate_time = GetTime() + 0.5
            apc_time = GetTime() + 90.0
        end

        arrived = CameraPath("path_portalcam", 4000, 1000, portal)

        if arrived or CameraCancelled() then
            CameraFinish()
            camera_complete[2] = true
        end
    end

    -- Portal Activation
    if GetTime() > activate_time then
        -- Source activates the portal and waits for isPortalActive(). Redux Lua
        -- exposes neither binding; retain its half-second activation lead-in and
        -- start the same wave schedule against the authored portal object.
        attack_wave_time = GetTime() + 1.0
        activate_time = 99999.0
    end

    -- Attack Waves
    if GetTime() > attack_wave_time then
        if apc_time < GetTime() + 45.0 then
            -- Source suspends waves for the final 45 seconds before APC arrival.
            attack_wave_time = 99999.0
        else
            -- Spawn Wave
            local unit = attackers[math.random(1, 10)]
            local h = BuildObject(unit, 2, GetTransform(portal))

            if math.random() < 0.5 then Goto(h, "attack_path1", 1) else Goto(h, "attack_path2", 1) end

            wave_count = wave_count + 1
            if wave_count < 4 then
                attack_wave_time = GetTime() + 4.0
            else
                wave_count = 0
                attack_wave_time = GetTime() + 30.0
            end
        end
    end

    -- APC Arrival
    if GetTime() > apc_time then
        apc_time = 99999.0
        apc = BuildObject("cvapc", 2, GetTransform(portal))
        Goto(apc, "portal_out", 1) -- Move out a bit
        attack_wave_time = GetTime() + 30.0
        apc_pilot_time1 = GetTime() + 20.0
        sound3_time = GetTime() + 1.0
    end

    if GetTime() > sound3_time then
        sound3_time = 99999.0
        AudioMessage("bd08003.wav")
    end

    -- Pilot 1 (Original) Leaves
    if GetTime() > apc_pilot_time1 then
        apc_pilot_time1 = 99999.0
        Stop(apc, 1)

        RemovePilot(apc)
        pilot = BuildObject("cspilo", 2, apc)
        SetPerceivedTeam(apc, 0)
        Retreat(pilot, "portal_in", 1)
        pilot_spawned1 = true

        ClearObjectives()
        AddObjective("bd08001.otf", "white")
        AddObjective("bd08002.otf", "white")
        SetObjectiveOn(apc)
    end

    if pilot_spawned1 then
        if IsAlive(pilot) then
            if GetDistance(pilot, portal) < 20.0 then -- Touching
                RemoveObject(pilot)
                pilot_spawned1 = false
                apc_pilot_time2 = GetTime() + 9 * 60.0
            end
        else -- The source treats killing this pilot before reprogramming as failure.
            schedule_lose2 = true
            pilot_spawned1 = false
        end
    end

    -- Enemy Pilot 2 (Hijacker) Returns
    if GetTime() > apc_pilot_time2 then
        apc_pilot_time2 = 99999.0
        pilot = BuildObject("cspilo", 2, "spawn_pilot")
        RemovePilot(apc)
        Retreat(pilot, apc, 1) -- Going to APC
        pilot_spawned2 = true
        portal_reprogrammed = true
        AudioMessage("bd08004.wav")
        -- Source deactivates the portal here; no Redux Lua binding is exposed.

        ClearObjectives()
        AddObjective("bd08002.otf", "green")
        AddObjective("bd08003.otf", "white")
        attack_wave_time = 99999.0 -- Stop waves
    end

    if pilot_spawned2 then
        if GetTeamNum(apc) == 1 then -- Player got it!
            pilot_spawned2 = false
            Attack(pilot, apc) -- Enemy pilot attacks APC
        elseif not IsAlive(pilot) then
            pilot_spawned2 = false
            pilot = nil
        elseif GetDistance(pilot, apc) < 20.0 then -- Reached APC
            pilot_spawned2 = false
            apc_go_back_time = GetTime() + 25.0

            -- Enemy takes the empty APC, matching curPilot/SetPerceivedTeam in C++.
            SetPilotClass(apc, "cspilo")
            RemoveObject(pilot)
            SetPerceivedTeam(apc, 2)
            pilot = nil
        end
    end

    -- APC Escape Logic
    if GetTime() > apc_go_back_time then
        apc_go_back_time = 99999.0
        if IsAlive(apc) then
            apc_heading_back = true
            -- Source reactivates the portal here; no Redux Lua binding is exposed.
            Retreat(apc, "portal_in", 1)
        end
    end

    if apc_heading_back then
        if GetTeamNum(apc) == 1 then apc_heading_back = false end -- Player took it

        if apc_heading_back and not lost and not won then
            if GetDistance(apc, portal) < 20.0 then
                RemoveObject(apc)
                schedule_lose2 = true -- Escaped
            end
        end
    end

    -- Loss Conditions
    if not lost and not won then
        if (recycler and not IsAlive(recycler)) or (command and not IsAlive(command)) then
            schedule_lose2 = true
        elseif apc and not IsAlive(apc) then
            schedule_lose3 = true -- Destroyed APC
        end
    end

    if schedule_lose2 and not lost then
        schedule_lose2 = false
        lost = true
        lose_sound2 = AudioMessage("bd08006.wav")
    end
    if schedule_lose3 and not lost then
        schedule_lose3 = false
        lost = true
        lose_sound3 = AudioMessage("bd08006.wav")
    end
    if lose_sound2 and IsAudioMessageDone(lose_sound2) then
        lose_sound2 = nil
        FailMission(GetTime() + 1.0, "bd08lsea.des")
    end
    if lose_sound3 and IsAudioMessageDone(lose_sound3) then
        lose_sound3 = nil
        FailMission(GetTime() + 1.0, "bd08lseb.des")
    end

    -- Win Condition
    if apc and GetTeamNum(apc) == 1 and not apc_commandeered then
        apc_commandeered = true
    end

    if apc_commandeered and portal_reprogrammed and not won and not lost then
        won = true
        win_sound = AudioMessage("bd08007.wav")
    end
    if win_sound and IsAudioMessageDone(win_sound) then
        win_sound = nil
        SucceedMission(GetTime() + 1.0, "bd08win.des")
    end

    -- The portal is a primary mission asset in the source. Destroying it is
    -- a distinct loss from losing the recycler/command tower or the APC.
    if not won and not lost and GetHealth(portal) <= 0.0 then
        lost = true
        FailMission(GetTime() + 1.0, "bd08lsec.des")
    end

end

