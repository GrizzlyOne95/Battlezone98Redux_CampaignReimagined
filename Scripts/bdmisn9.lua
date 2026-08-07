-- bdmisn9.lua (Converted from BlackDog09Mission.cpp)
-- Source-disabled note: the convoy briefing once also re-added
-- "bd09001.otf" in green before "bd09002.otf"; active source omits it there.

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
local goto_beacon2 = false
local goto_beacon3 = false
local sound7_played = false
local deviate_spawned = false
local tank_arrived1 = false
local tank_arrived2 = false
local tank_arrived3 = false
local trigger1_triggered = false
local strayed = false
local one_of_the_enemy = false
local sound2_played = false
local portal_active = false
local lost = false
local won = false

-- Handles
local user
local cvtnk1, cvtnk2, cvtnk3, cvtnk4, cvtnk5
local portal
local beacon1, beacon2, beacon3
local sound1, sound2, sound3, win_sound

-- Timers
local sound1_time = 99999.0
local sound2_time = 99999.0
local sound3_time = 99999.0
local sound6_time = 99999.0
local order_goto_time1 = 99999.0
local deviate_time = 99999.0
local tank_timeout = -1.0 -- Using -1 for inactive

-- Difficulty
local difficulty = 2

-- Preserve native mission state across save/load.
function Save()
    return {
        start_done = start_done,
        objective1_complete = objective1_complete,
        objective2_complete = objective2_complete,
        objective3_complete = objective3_complete,
        goto_beacon2 = goto_beacon2,
        goto_beacon3 = goto_beacon3,
        sound7_played = sound7_played,
        deviate_spawned = deviate_spawned,
        tank_arrived1 = tank_arrived1,
        tank_arrived2 = tank_arrived2,
        tank_arrived3 = tank_arrived3,
        trigger1_triggered = trigger1_triggered,
        strayed = strayed,
        one_of_the_enemy = one_of_the_enemy,
        sound2_played = sound2_played,
        portal_active = portal_active,
        lost = lost,
        won = won,
        user = user,
        cvtnk1 = cvtnk1,
        cvtnk2 = cvtnk2,
        cvtnk3 = cvtnk3,
        cvtnk4 = cvtnk4,
        cvtnk5 = cvtnk5,
        portal = portal,
        beacon1 = beacon1,
        beacon2 = beacon2,
        beacon3 = beacon3,
        sound1 = sound1,
        sound2 = sound2,
        sound3 = sound3,
        win_sound = win_sound,
        sound1_time = sound1_time,
        sound2_time = sound2_time,
        sound3_time = sound3_time,
        sound6_time = sound6_time,
        order_goto_time1 = order_goto_time1,
        deviate_time = deviate_time,
        tank_timeout = tank_timeout,
        difficulty = difficulty,
    }
end

function Load(state)
    if not state then return end
    start_done = state.start_done
    objective1_complete = state.objective1_complete
    objective2_complete = state.objective2_complete
    objective3_complete = state.objective3_complete
    goto_beacon2 = state.goto_beacon2
    goto_beacon3 = state.goto_beacon3
    sound7_played = state.sound7_played
    deviate_spawned = state.deviate_spawned
    tank_arrived1 = state.tank_arrived1
    tank_arrived2 = state.tank_arrived2
    tank_arrived3 = state.tank_arrived3
    trigger1_triggered = state.trigger1_triggered
    strayed = state.strayed
    one_of_the_enemy = state.one_of_the_enemy
    sound2_played = state.sound2_played
    portal_active = state.portal_active
    lost = state.lost
    won = state.won
    user = state.user
    cvtnk1 = state.cvtnk1
    cvtnk2 = state.cvtnk2
    cvtnk3 = state.cvtnk3
    cvtnk4 = state.cvtnk4
    cvtnk5 = state.cvtnk5
    portal = state.portal
    beacon1 = state.beacon1
    beacon2 = state.beacon2
    beacon3 = state.beacon3
    sound1 = state.sound1
    sound2 = state.sound2
    sound3 = state.sound3
    win_sound = state.win_sound
    sound1_time = state.sound1_time
    sound2_time = state.sound2_time
    sound3_time = state.sound3_time
    sound6_time = state.sound6_time
    order_goto_time1 = state.order_goto_time1
    deviate_time = state.deviate_time
    tank_timeout = state.tank_timeout
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
        SetScrap(1, 0)
        SetPilot(1, 0)

        cvtnk1 = GetHandle("cvtnk1")
        cvtnk2 = GetHandle("cvtnk2")
        cvtnk3 = GetHandle("cvtnk3")
        cvtnk4 = GetHandle("cvtnk4")
        cvtnk5 = GetHandle("cvtnk5")
        portal = GetHandle("portal")

        sound1_time = GetTime() + 1.0

        ClearObjectives()
        AddObjective("bd09001.otf", "white")
        if cvtnk1 then SetObjectiveOn(cvtnk1) end

        start_done = true
    end

    if lost or won then return end

    -- Sound 1
    if GetTime() > sound1_time then
        sound1_time = 99999.0
        sound1 = AudioMessage("bd09001.wav")
    end
    if sound1 and IsAudioMessageDone(sound1) then
        sound1 = nil
        sound2_time = GetTime() + 15.0
    end

    -- The source specifically requires the player's initial cvapc disguise at
    -- this checkpoint; capturing cvtnk1 is the following objective.
    if GetTime() > sound2_time and not sound2_played then
        sound2_time = 99999.0
        if IsOdf(user, "cvapc") then
            sound2_played = true
            one_of_the_enemy = true
            sound2 = AudioMessage("bd09002.wav")
        end
    end

    if not sound2_played and not IsOdf(user, "cvapc") then
        one_of_the_enemy = false
        SetPerceivedTeam(user, 1)
        Attack(cvtnk2, user)
        Attack(cvtnk3, user)
        Attack(cvtnk4, user)
        Attack(cvtnk5, user)
        deviate_time = GetTime() + 1.0
    end
    if sound2 and IsAudioMessageDone(sound2) then
        sound2 = nil
    end

    if one_of_the_enemy then
        SetPerceivedTeam(user, 2)
    end

    -- Obj 1 Complete (Got Tank)
    if not objective1_complete and user == cvtnk1 and sound2_played then
        one_of_the_enemy = false
        objective1_complete = true
        SetObjectiveOff(cvtnk1)
        sound3_time = GetTime() + 5.0
        beacon1 = BuildObject("apcamr", 1, "spawn_beacon1"); SetLabel(beacon1, "Beacon 1")
    end

    -- Strayed Check (Distance from convoy)
    if objective1_complete and not strayed then
        local too_far = true
        local friends = {cvtnk2, cvtnk3, cvtnk4, cvtnk5}
        for _, t in pairs(friends) do
            if IsAlive(t) and GetDistance(user, t) <= 75.0 then
                too_far = false
            end
        end

        if too_far then
            SetPerceivedTeam(user, 1)
            strayed = true
            deviate_time = GetTime() + 2.0
        end
    end

    -- Convoy Orders
    if GetTime() > sound3_time and not deviate_spawned then
        sound3_time = 99999.0
        sound3 = AudioMessage("bd09003.wav")
    end
    if sound3 and IsAudioMessageDone(sound3) then
        sound3 = nil
        ClearObjectives()
        AddObjective("bd09002.otf", "white")
        order_goto_time1 = GetTime() + 1.0
    end

    if GetTime() > order_goto_time1 then
        order_goto_time1 = 99999.0
        for i=2,5 do
            local t = GetHandle("cvtnk"..i)
            if IsAlive(t) then Goto(t, "tank_path", 1) end
        end
    end

    -- Beacons Reached
    -- Beacon 1
    if not tank_arrived1 then
        local arrived = false
        for i=1,5 do
            local t = GetHandle("cvtnk"..i)
            if IsAlive(t) and GetDistance(t, beacon1) < 100.0 then arrived = true end
        end
        if arrived then
            tank_arrived1 = true
            beacon2 = BuildObject("apcamr", 1, "spawn_beacon2"); SetLabel(beacon2, "Beacon 2")
        end
    end

    if objective1_complete and not goto_beacon2 and not deviate_spawned and GetDistance(user, beacon1) < 100.0 then
        goto_beacon2 = true
        AudioMessage("bd09004.wav")
    end

    -- Beacon 2
    if not tank_arrived2 then
        local arrived = false
        for i=1,5 do
            local t = GetHandle("cvtnk"..i)
            if IsAlive(t) and GetDistance(t, beacon2) < 100.0 then arrived = true end
        end
        if arrived then
            tank_arrived2 = true
            beacon3 = BuildObject("apcamr", 1, "spawn_beacon3"); SetLabel(beacon3, "Beacon 3")
        end
    end

    if objective1_complete and not goto_beacon3 and not deviate_spawned and GetDistance(user, beacon2) < 100.0 then
        goto_beacon3 = true
        AudioMessage("bd09005.wav")
        sound6_time = GetTime() + 5.0
    end

    if GetTime() > sound6_time then
        sound6_time = 99999.0
        AudioMessage("bd09006.wav")
        SetObjectiveOn(portal)
    end

    -- Obj 2 Check
    if not objective2_complete and goto_beacon2 and goto_beacon3 and GetDistance(user, beacon3) < 100.0 then
        objective2_complete = true
        ClearObjectives()
        AddObjective("bd09001.otf", "green")
        AddObjective("bd09002.otf", "green")
        AddObjective("bd09003.otf", "white")
    end

    -- Deviate / Betrayal
    if GetTime() > deviate_time and not deviate_spawned then
        SetPerceivedTeam(user, 1) -- Cover blown
        deviate_time = 99999.0
        deviate_spawned = true

        -- Spawn Attackers
        local function Spawn(odf, pt)
            local h = BuildObject(odf, 2, pt)
            Attack(h, user)
        end
        Spawn("cvfigh", "spawn_deviate1"); Spawn("cvfigh", "spawn_deviate1")
        Spawn("cvltnk", "spawn_deviate2"); Spawn("cvltnk", "spawn_deviate2")
        Spawn("cvhtnk", "spawn_deviate3")
        Spawn("cvrckt", "spawn_deviate4"); Spawn("cvrckt", "spawn_deviate4")
        Spawn("cvfigh", "spawn_deviate5"); Spawn("cvfigh", "spawn_deviate5")
        Spawn("cvtnk", "spawn_deviate6"); Spawn("cvtnk", "spawn_deviate6")

        AudioMessage("bd09007.wav")
        for h in AllCraft() do
            if IsOdf(h, "cvturrc") then Attack(h, user) end
        end
    end

    -- Time Out of Tank (Cover maintenance)
    if objective1_complete and not IsOdf(user, "cvtnkb") and tank_timeout < 0 then
        tank_timeout = GetTime() + 600.0
    elseif IsOdf(user, "cvtnkb") then
        tank_timeout = -1.0
    end

    if tank_timeout > 0 and GetTime() > tank_timeout then
        FailMission(GetTime()+1.0, "bd09lose.des")
        lost = true
    end

    -- Final Trigger
    if not trigger1_triggered and GetDistance(user, "trigger_1") < 200.0 then
        trigger1_triggered = true
        for i=1,5 do
            local h = BuildObject("cvtnk", 2, "last_one")
            Attack(h, user)
        end
    end

    -- Portal Escape
    if GetDistance(user, portal) < 250.0 and not portal_active then
        portal_active = true
        -- Source calls activatePortal(portal, true); Redux Lua exposes no
        -- portal-state binding, but retains the portal approach cue and exit.
        win_sound = AudioMessage("bd09008.wav")
    end

    if GetDistance(user, portal) < 20.0 and not won and not lost then -- isTouching
        won = true
        SucceedMission(GetTime(), "bd09win.des")
    end

    if not IsAlive(portal) and not lost and not won then
        lost = true
        FailMission(GetTime()+1.0, "bd09lseb.des") -- Portal dead
    end
end

