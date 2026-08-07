-- BlackDog01 Mission Script
-- Source-disabled note: the intro camera branch contains an immediate
-- SucceedMission(GetTime(), "bd01win.des") test hook; it remains disabled.
-- Restores "Dual Scavenger" Defense Logic
-- Source audio-role comments are retained: bd01004.wav is the "congrats"
-- message and bd01005.wav is the recycler-loss "failure" message.

local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})
local exu = require("exu")
local aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")

-- Helper for AI
local function SetupAI()
    DiffUtils.SetupTeams(aiCore.Factions.BDOG, aiCore.Factions.CCA, 2)
end

-- Variables
local start_done = false
local objective1_complete = false
local objective2_complete = false
local objective3_complete = false
local camera_ready = false
local camera_complete = {false, false}
local scavengers_created = false
local sound_started = {}
local sound_played = {}
local sound_handles = {}
local opening_sound, sound6, sound7, sound8, sound9
local beacon_spawned1 = false
local beacon_spawned2 = false
local ambush_retreat = false
local wave1_ready = false
local wave2_ready = false
local game_over = false

-- Timers
local wave2_delay = 999999.0
local delay_time1 = 999999.0
local delay_time2 = 999999.0
local delay_time3 = 999999.0
local sound6_time = 999999.9
local sound7_time = 999999.9
local sound8_time = 999999.9
local sound9_time = 999999.9

-- Handles
local user, recycler, wingman1, wingman2
local scavengers = {nil, nil} -- Array for dual scavengers
local badguy1_ambush, badguy2_ambush
local badguy1_wave1, badguy2_wave1, badguy3_wave1, badguy4_wave1
local badguy1_wave2, badguy2_wave2, badguy3_wave2, badguy4_wave2, badguy5_wave2
local beacon

local difficulty = 2

local function resetObjectives()
    ClearObjectives()
    AddObjective("bd01001.otf", objective1_complete and "GREEN" or "WHITE")
    if not beacon_spawned2 then return end
    AddObjective("bd01002.otf", objective2_complete and "GREEN" or "WHITE")
    if not wave1_ready then return end
    AddObjective("bd01003.otf", objective3_complete and "GREEN" or "WHITE")
end

-- Preserve native mission state across save/load.
function Save()
    return {
        start_done = start_done,
        objective1_complete = objective1_complete,
        objective2_complete = objective2_complete,
        objective3_complete = objective3_complete,
        camera_ready = camera_ready,
        camera_complete = camera_complete,
        scavengers_created = scavengers_created,
        sound_started = sound_started,
        sound_played = sound_played,
        sound_handles = sound_handles,
        opening_sound = opening_sound,
        sound6 = sound6,
        sound7 = sound7,
        sound8 = sound8,
        sound9 = sound9,
        beacon_spawned1 = beacon_spawned1,
        beacon_spawned2 = beacon_spawned2,
        ambush_retreat = ambush_retreat,
        wave1_ready = wave1_ready,
        wave2_ready = wave2_ready,
        game_over = game_over,
        wave2_delay = wave2_delay,
        delay_time1 = delay_time1,
        delay_time2 = delay_time2,
        delay_time3 = delay_time3,
        sound6_time = sound6_time,
        sound7_time = sound7_time,
        sound8_time = sound8_time,
        sound9_time = sound9_time,
        user = user,
        recycler = recycler,
        wingman1 = wingman1,
        wingman2 = wingman2,
        scavengers = scavengers,
        badguy1_ambush = badguy1_ambush,
        badguy2_ambush = badguy2_ambush,
        badguy1_wave1 = badguy1_wave1,
        badguy2_wave1 = badguy2_wave1,
        badguy3_wave1 = badguy3_wave1,
        badguy4_wave1 = badguy4_wave1,
        badguy1_wave2 = badguy1_wave2,
        badguy2_wave2 = badguy2_wave2,
        badguy3_wave2 = badguy3_wave2,
        badguy4_wave2 = badguy4_wave2,
        badguy5_wave2 = badguy5_wave2,
        beacon = beacon,
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
    scavengers_created = state.scavengers_created
    sound_started = state.sound_started
    sound_played = state.sound_played
    sound_handles = state.sound_handles
    opening_sound = state.opening_sound
    sound6 = state.sound6
    sound7 = state.sound7
    sound8 = state.sound8
    sound9 = state.sound9
    beacon_spawned1 = state.beacon_spawned1
    beacon_spawned2 = state.beacon_spawned2
    ambush_retreat = state.ambush_retreat
    wave1_ready = state.wave1_ready
    wave2_ready = state.wave2_ready
    game_over = state.game_over
    wave2_delay = state.wave2_delay
    delay_time1 = state.delay_time1
    delay_time2 = state.delay_time2
    delay_time3 = state.delay_time3
    sound6_time = state.sound6_time
    sound7_time = state.sound7_time
    sound8_time = state.sound8_time
    sound9_time = state.sound9_time
    user = state.user
    recycler = state.recycler
    wingman1 = state.wingman1
    wingman2 = state.wingman2
    scavengers = state.scavengers
    badguy1_ambush = state.badguy1_ambush
    badguy2_ambush = state.badguy2_ambush
    badguy1_wave1 = state.badguy1_wave1
    badguy2_wave1 = state.badguy2_wave1
    badguy3_wave1 = state.badguy3_wave1
    badguy4_wave1 = state.badguy4_wave1
    badguy1_wave2 = state.badguy1_wave2
    badguy2_wave2 = state.badguy2_wave2
    badguy3_wave2 = state.badguy3_wave2
    badguy4_wave2 = state.badguy4_wave2
    badguy5_wave2 = state.badguy5_wave2
    beacon = state.beacon
    difficulty = state.difficulty
end
function Start()
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    start_done = false
    -- Initialize Sound Arrays
    for i=0, 4 do sound_started[i] = false; sound_played[i] = false end
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then aiCore.AddObject(h) end

    -- Capture Scavengers
    if (not scavengers_created) and IsOdf(h, "bvscav") and (team == 1) then
        if not scavengers[1] then scavengers[1] = h
        elseif not scavengers[2] then scavengers[2] = h end
    end
end

function DeleteObject(h)
end

function Update()
    user = GetPlayerHandle()
    aiCore.Update()

    if not start_done then
        SetScrap(1, 12)
        SetPilot(1, 10)

        recycler = GetHandle("recycler")
        wingman1 = GetHandle("wingman1_bobcat")
        wingman2 = GetHandle("wingman2_bobcat")
        Goto(recycler, "start_path_recycler")
        Goto(wingman1, "start_path_wingman1")
        Goto(wingman2, "start_path_wingman2")

        opening_sound = AudioMessage("bd01001.wav")
        resetObjectives()

        start_done = true
    end

    -- Recycler death: the C++ waits for the loss VO to finish before it
    -- schedules the failure. Do not gate this on IsAlive(), since a vehicle
    -- at zero health is already reported dead by that helper.
    if (GetHealth(recycler) <= 0) and (not sound_started[3]) then
        sound_started[3] = true
        sound_handles[3] = AudioMessage("bd01005.wav")
    end
    if sound_started[3] and not sound_played[3] and IsAudioMessageDone(sound_handles[3]) then
        FailMission(GetTime() + 4.0, "bd01lsea.des")
        sound_played[3] = true
    end

    -- Camera Intro
    if not camera_complete[1] then
        if not camera_ready then
            CameraReady()
            camera_ready = true
        end
        local arrived = CameraPath("camera_start_arc", 3000, 3500, recycler)
        if CameraCancelled() or arrived then
            if CameraCancelled() and opening_sound then StopAudioMessage(opening_sound) end
            CameraFinish()
            camera_complete[1] = true
            camera_ready = false
            sound8_time = GetTime() + 90.0
        end
    end

    -- Deploy Reminders
    if (sound8_time < GetTime()) then
        sound8_time = 999999.9
        if not IsDeployed(recycler) then sound8 = AudioMessage("bd01008.wav") end
    end
    if sound8 and IsAudioMessageDone(sound8) then
        sound8 = nil
        sound9_time = GetTime() + 30.0
    end
    if sound9_time < GetTime() then
        sound9_time = 999999.9
        if not IsDeployed(recycler) then sound9 = AudioMessage("bd01009.wav") end
    end
    if sound9 and IsAudioMessageDone(sound9) then
        sound9 = nil
        FailMission(GetTime() + 1.0, "bd01lseb.des")
    end

    -- Despite its old variable name, the source advances as soon as the
    -- recycler deploys; it does not require one or two scavengers to exist.
    if not scavengers_created then
        if IsDeployed(recycler) then
            scavengers_created = true
            delay_time1 = GetTime() + 20.0
            sound8_time = 999999.9
            sound9_time = 999999.9
            objective1_complete = true

            resetObjectives()
        end
    end

    if not scavengers_created then return end
    if GetTime() < delay_time1 then return end

    -- Ambush Phase
    if not beacon_spawned1 then
        beacon_spawned1 = true
        beacon = BuildObject("apcamr", 1, "spawn_nav_beacon")
        SetLabel(beacon, "Nav Alpha")

        badguy1_ambush = BuildObject("cvfigh", 2, "spawn_attack_ambush")
        Patrol(badguy1_ambush, "ambush_patrol_path", 1)
        Cloak(badguy1_ambush)

        badguy2_ambush = BuildObject("cvfigh", 2, "spawn_attack_ambush")
        Patrol(badguy2_ambush, "ambush_patrol_path", 1)
        Cloak(badguy2_ambush)
    end

    -- Play Audio 2
    if not sound_started[0] then
        sound_handles[0] = AudioMessage("bd01002.wav")
        sound_started[0] = true
    end
    if not sound_played[0] then
        if IsAudioMessageDone(sound_handles[0]) then sound_played[0] = true else return end
    end

    if not beacon_spawned2 then
        beacon_spawned2 = true
        SetUserTarget(beacon)
        resetObjectives()
        sound6_time = GetTime() + 60.0
    end

    -- The nav is considered found by any allied unit, by either ambusher
    -- being decloaked, or by the player reaching it directly.
    if (sound6_time < GetTime() + 60.0) or (sound7_time < GetTime() + 30.0) then
        local ally = GetNearestUnitOnTeam("spawn_nav_beacon", 0, 1)
        local ally_near = IsAlive(ally) and GetDistance(ally, "spawn_nav_beacon") < 100.0
        if ally_near or not IsCloaked(badguy1_ambush) or not IsCloaked(badguy2_ambush)
            or GetDistance(user, beacon) < 100.0 then
            objective2_complete = true
            sound6_time = 999999.0
            sound7_time = 999999.0
            resetObjectives()
        end
    end

    if sound6_time < GetTime() then
        sound6_time = 999999.9
        sound6 = AudioMessage("bd01006.wav")
    end
    if sound6 and IsAudioMessageDone(sound6) then
        sound6 = nil
        sound7_time = GetTime() + 30.0
    end
    if sound7_time < GetTime() then
        sound7_time = 999999.9
        sound7 = AudioMessage("bd01007.wav")
    end
    if sound7 and IsAudioMessageDone(sound7) then
        sound7 = nil
        FailMission(GetTime() + 1.0, "bd01lsec.des")
    end

    -- Ambush Retreat
    if not ambush_retreat then
        if (not IsAlive(badguy1_ambush)) or (not IsAlive(badguy2_ambush)) then
            -- One dead, retreat the other
            if IsAlive(badguy1_ambush) then Retreat(badguy1_ambush, "ambush_retreat_path", 1); Cloak(badguy1_ambush) end
            if IsAlive(badguy2_ambush) then Retreat(badguy2_ambush, "ambush_retreat_path", 1); Cloak(badguy2_ambush) end
            delay_time2 = GetTime() + 5.0
            ambush_retreat = true
        end
    end

    if not ambush_retreat then return end
    if GetTime() < delay_time2 then return end

    -- Wave 1
    if not wave1_ready then
        wave1_ready = true
        badguy1_wave1 = BuildObject("cvfigh", 2, "spawn_attack_wave1")
        Attack(badguy1_wave1, recycler)
        badguy2_wave1 = BuildObject("cvfigh", 2, "spawn_attack_wave1")
        Attack(badguy2_wave1, recycler)

        wave2_delay = GetTime() + 60.0
        resetObjectives()
    end

    -- Wave 1 Reinforcements
    if not camera_complete[2] then
        if not camera_ready then
            CameraReady()
            camera_ready = true
            AudioMessage("bd01003.wav")
        end
        local arrived = CameraPath("camera_attack_view", 2000, 1000, badguy1_wave1)
        if CameraCancelled() or arrived then
            CameraFinish()
            camera_complete[2] = true
            camera_ready = false

            badguy3_wave1 = BuildObject("cvfigh", 2, "spawn_attack_wave1a")
            Attack(badguy3_wave1, recycler)
            badguy4_wave1 = BuildObject("cvfigh", 2, "spawn_attack_wave1a")
            Attack(badguy4_wave1, recycler)
        end
    end

    if GetTime() < wave2_delay then return end

    -- Wave 2
    if not wave2_ready then
        wave2_ready = true
        badguy1_wave2 = BuildObject("cvfigh", 2, "spawn_attack_wave2"); Attack(badguy1_wave2, recycler)
        badguy2_wave2 = BuildObject("cvfigh", 2, "spawn_attack_wave2"); Attack(badguy2_wave2, recycler)
        badguy3_wave2 = BuildObject("cvltnk", 2, "spawn_attack_wave2"); Attack(badguy3_wave2, recycler)
        badguy4_wave2 = BuildObject("cvfigh", 2, "spawn_attack_wave2a"); Attack(badguy4_wave2, recycler)
        badguy5_wave2 = BuildObject("cvfigh", 2, "spawn_attack_wave2a"); Attack(badguy5_wave2, recycler)

    end

    -- Win Condition
    local all_bad = {badguy1_wave1, badguy2_wave1, badguy3_wave1, badguy4_wave1,
                     badguy1_wave2, badguy2_wave2, badguy3_wave2, badguy4_wave2, badguy5_wave2,
                     badguy1_ambush, badguy2_ambush}
    local all_dead = true
    for _, h in ipairs(all_bad) do if IsAlive(h) then all_dead = false; break end end

    if all_dead and (not sound_started[2]) then
        sound_started[2] = true
        sound_handles[2] = AudioMessage("bd01004.wav")
        objective3_complete = true
        resetObjectives()
    end
    if sound_started[2] and not sound_played[2] and IsAudioMessageDone(sound_handles[2]) then
        sound_played[2] = true
        SucceedMission(GetTime() + 4.0, "bd01win.des")
    end
end

