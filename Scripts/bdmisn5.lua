-- bdmisn5.lua (Converted from BlackDog05Mission.cpp)
-- Source-disabled note: Setup once used BuildObject("cbport", 0, "portal");
-- the authored map portal handle is used by the active mission and conversion.

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
local camera_ready = false
local camera_complete = {false, false}
local waits_initialized = false
local wait_over = {false, false, false, false, false}
local quitters_spawned = false
local quitter_movie_done = false
local num_bombers = 0
local won = false
local lost = false

-- Timers
local wait_time = {99999.0, 99999.0, 99999.0, 99999.0, 99999.0}
local rear_attack_time1 = 99999.0
local rear_attack_time2 = 99999.0
local howitzer_time = 99999.0
local quitter_delay = 99999.0
local quitter_cam_time = 99999.0
local intro_sound, quitter_sound, sound6

-- Handles
local user, recycler, portal
local units = {} -- Main enemy tracking (approx 46 slots)
local quitters = {} -- 1..6

-- Difficulty
local difficulty = 2

-- Preserve native mission state across save/load.
function Save()
    return {
        start_done = start_done,
        objective1_complete = objective1_complete,
        objective2_complete = objective2_complete,
        camera_ready = camera_ready,
        camera_complete = camera_complete,
        waits_initialized = waits_initialized,
        wait_over = wait_over,
        quitters_spawned = quitters_spawned,
        quitter_movie_done = quitter_movie_done,
        num_bombers = num_bombers,
        won = won,
        lost = lost,
        wait_time = wait_time,
        rear_attack_time1 = rear_attack_time1,
        rear_attack_time2 = rear_attack_time2,
        howitzer_time = howitzer_time,
        quitter_delay = quitter_delay,
        quitter_cam_time = quitter_cam_time,
        intro_sound = intro_sound,
        quitter_sound = quitter_sound,
        sound6 = sound6,
        user = user,
        recycler = recycler,
        portal = portal,
        units = units,
        quitters = quitters,
        difficulty = difficulty,
    }
end

function Load(state)
    if not state then return end
    start_done = state.start_done
    objective1_complete = state.objective1_complete
    objective2_complete = state.objective2_complete
    camera_ready = state.camera_ready
    camera_complete = state.camera_complete
    waits_initialized = state.waits_initialized
    wait_over = state.wait_over
    quitters_spawned = state.quitters_spawned
    quitter_movie_done = state.quitter_movie_done
    num_bombers = state.num_bombers
    won = state.won
    lost = state.lost
    wait_time = state.wait_time
    rear_attack_time1 = state.rear_attack_time1
    rear_attack_time2 = state.rear_attack_time2
    howitzer_time = state.howitzer_time
    quitter_delay = state.quitter_delay
    quitter_cam_time = state.quitter_cam_time
    intro_sound = state.intro_sound
    quitter_sound = state.quitter_sound
    sound6 = state.sound6
    user = state.user
    recycler = state.recycler
    portal = state.portal
    units = state.units
    quitters = state.quitters
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

-- Restored cut content: BlackDog05Mission.cpp encloses this entire production
-- objective in #if 0. Without it objective1Complete can never become true and
-- the mission cannot reach its victory branch, so the intended seven-offensive-
-- units objective and its 40-minute follow-up timer are enabled here.
function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then
        aiCore.AddObject(h)
    elseif team == 1 then
        -- Lua does not expose the C++ team-slot range; mirror its offensive-unit
        -- intent with the Black Dog combat ODFs used by this mission.
        if IsOdf(h, "bvbomb") or IsOdf(h, "bvhraz") or IsOdf(h, "bvtank") or IsOdf(h, "bvmisl") or IsOdf(h, "bvwalk") then
            if num_bombers < 7 then
                num_bombers = num_bombers + 1
                if num_bombers >= 7 and not objective1_complete then
                    objective1_complete = true
                    ClearObjectives()
                    AddObjective("bd05001.otf", "green")
                    StopCockpitTimer()
                    StartCockpitTimer(40 * 60, 60, 10)
                end
            end
        end
    end
end

function DeleteObject(h)
end

local function ResetObjectives()
    ClearObjectives()
    if objective1_complete then
        AddObjective("bd05001.otf", "green")
    else
        AddObjective("bd05001.otf", "white") -- "Build 7 Bombers" text
    end
end

function Update()
    user = GetPlayerHandle()
    aiCore.Update()

    if not start_done then
        SetScrap(1, 8)
        SetPilot(1, 10)

        recycler = GetHandle("recycler")
        portal = GetHandle("portal")
        -- units 1..15 from map? C++ has handles unit_1..15.
        -- Assuming map units exist.
        for i=1,15 do units[i] = GetHandle("unit_"..i) end

        ResetObjectives()
        start_done = true
    end

    -- Intro
    if not camera_complete[1] then
        if not camera_ready then
            CameraReady()
            intro_sound = AudioMessage("bd05001.wav")
            ResetObjectives()
            camera_ready = true
        end

        local arrived = CameraPath("camera_start_arc", 3000, 2000, recycler)

        if CameraCancelled() then
            arrived = true
            if intro_sound then StopAudioMessage(intro_sound) end
        end
        if arrived then
            CameraFinish()
            camera_complete[1] = true
            camera_ready = false
            ResetObjectives()
        end
    end

    -- Initialize Waves
    if not waits_initialized then
        local t = GetTime()
        wait_time[1] = t + 240.0
        wait_time[2] = t + 300.0
        wait_time[3] = t + 540.0
        wait_time[4] = t + 840.0
        wait_time[5] = t + 1140.0

        howitzer_time = t + 420.0
        rear_attack_time1 = t + 450.0
        rear_attack_time2 = t + 660.0
        waits_initialized = true
    end

    -- Processing Waves
    if not wait_over[1] and GetTime() > wait_time[1] then
        AudioMessage("bd05002.wav")
        wait_over[1] = true
    end

    if not wait_over[2] and GetTime() > wait_time[2] then
        -- First Wave
        local function Spawn(odf)
            local h = BuildObject(odf, 2, "first_wave"); SetCloaked(h, true); Goto(h, recycler, 1)
            table.insert(units, h)
        end
        Spawn("cvfigh"); Spawn("cvfigh"); Spawn("cvltnk"); Spawn("cvltnk")
        wait_over[2] = true
    end

    if not wait_over[3] and GetTime() > wait_time[3] then
        -- Second Wave
        local function Spawn(odf)
            local h = BuildObject(odf, 2, "second_wave"); SetCloaked(h, true); Attack(h, recycler, 1)
            table.insert(units, h)
        end
        Spawn("cvltnk"); Spawn("cvltnk"); Spawn("cvtnk"); Spawn("cvtnk")
        wait_over[3] = true
    end

    if not wait_over[4] and GetTime() > wait_time[4] then
        -- Third Wave
        local function Spawn(odf)
            local h = BuildObject(odf, 2, "third_wave"); SetCloaked(h, true); Goto(h, recycler, 1)
            table.insert(units, h)
        end
        Spawn("cvtnk"); Spawn("cvtnk"); Spawn("cvhraz"); Spawn("cvhraz"); Spawn("cvwalk")
        wait_over[4] = true
    end

    if not wait_over[5] and GetTime() > wait_time[5] then
        -- Fourth Wave
        local function Spawn(odf)
            local h = BuildObject(odf, 2, "fourth_wave"); SetCloaked(h, true); Goto(h, recycler, 1)
            table.insert(units, h)
        end
        Spawn("cvtnk"); Spawn("cvtnk"); Spawn("cvhraz"); Spawn("cvhraz"); Spawn("cvwalk"); Spawn("cvwalk")
        wait_over[5] = true
    end

    -- Rear Attacks
    if GetTime() > rear_attack_time1 then
        rear_attack_time1 = 99999.0
        for i=1,5 do
            local h = BuildObject("cvtnk", 2, "rear_attack"); SetCloaked(h, true); Attack(h, recycler, 1)
            table.insert(units, h)
        end
    end

    if GetTime() > rear_attack_time2 then
        rear_attack_time2 = 99999.0
        for i=1,5 do
            local h = BuildObject("cvtnk", 2, "rear_attack"); SetCloaked(h, true); Attack(h, recycler, 1)
            table.insert(units, h)
        end
    end

    if GetTime() > howitzer_time then
        howitzer_time = 99999.0
        local h = BuildObject("cvartl", 2, "howit"); SetCloaked(h, true); Goto(h, recycler, 1); table.insert(units, h)
        h = BuildObject("cvartl", 2, "howit"); SetCloaked(h, true); Goto(h, recycler, 1); table.insert(units, h)
    end

    -- Win Condition Check: All Enemies Dead?
    if not objective2_complete and wait_over[5] then
        local all_dead = true
        for _, u in pairs(units) do
            if IsAlive(u) then all_dead = false; break end
        end

        if all_dead then
            objective2_complete = true
            AudioMessage("bd05004.wav")
            ResetObjectives()
        end
    end

    -- The source starts the retreat as soon as the fixed enemy roster is dead;
    -- production completion is checked separately by the victory branch.
    if objective2_complete and not quitters_spawned then
        quitters[1] = BuildObject("cvtnk", 2, "quitters")
        quitters[2] = BuildObject("cvtnk", 2, "quitters")
        quitters[3] = BuildObject("cvwalk", 2, "quitters")
        quitters[4] = BuildObject("cvwalk", 2, "quitters")
        quitters[5] = BuildObject("cspilo", 2, "quitters")
        quitters[6] = BuildObject("cvltnk", 2, "quitters")

        for i=1,6 do Retreat(quitters[i], "portal_in", 1) end
        -- Source calls activatePortal(portal, true). The Redux Lua API exposes
        -- no matching portal activation binding; proximity removal below keeps
        -- the authored retreat flow without inventing a replacement API.
        quitters_spawned = true
    end

    if quitters_spawned then
        for i=1,6 do
            if IsAlive(quitters[i]) then
                if GetDistance(quitters[i], portal) < 20.0 then -- Touching portal?
                    RemoveObject(quitters[i])
                end
            end
        end
    end

    -- Retreat Cinematic
    if quitters_spawned and camera_complete[1] and not camera_complete[2] then
        if not camera_ready then
            CameraReady()
            quitter_sound = AudioMessage("bd05005.wav")
            quitter_cam_time = GetTime() + 15.0
            camera_ready = true
        end

        CameraPath("camera_retreat", 3000, 0, portal)

        if quitter_sound and IsAudioMessageDone(quitter_sound) then
            quitter_sound = nil
            quitter_delay = GetTime() + 3.0
        end

        if CameraCancelled() or (GetTime() > quitter_delay and GetTime() > quitter_cam_time) then
            CameraFinish()
            camera_complete[2] = true
            camera_ready = false
            quitter_movie_done = true
        end
    end

    -- Victory
    if objective1_complete and objective2_complete and quitter_movie_done and not won and not lost then
        won = true
        sound6 = AudioMessage("bd05006.wav")
    end
    if sound6 and IsAudioMessageDone(sound6) then
        sound6 = nil
        SucceedMission(0.1, "bd05win.des")
    end
end

