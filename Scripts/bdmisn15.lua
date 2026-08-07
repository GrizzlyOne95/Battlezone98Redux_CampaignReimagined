-- bdmisn15.lua (Converted from BlackDog15Mission.cpp)
-- Source-disabled handles retained for restoration: intro1 and intro2 could be
-- looked up as "chin_fighter_intro1" and "chin_fighter_intro2". No active
-- source state uses them, so the Lua conversion does not invent a sequence.

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
local won_lost = false
local sound10_played = false
local all_units_spawned = false
local doing_countdown = false
local doing_explosion = false
local doing_camera = false

-- Timers
local sound2_time = 99999.0
local sound3_time = 99999.0
local sound4_time = 99999.0
local sound5_time = 99999.0
local sound6_time = 99999.0
local sound12_time = 99999.0
local east_wave_time = 99999.0

-- Handles
local user
local units = {} -- Tracks all enemy units
local sound1, sound2, sound3, sound4, sound7, sound11, sound12

-- Difficulty
local difficulty = 2

-- Preserve native mission state across save/load.
function Save()
    return {
        start_done = start_done,
        objective1_complete = objective1_complete,
        won_lost = won_lost,
        sound10_played = sound10_played,
        all_units_spawned = all_units_spawned,
        doing_countdown = doing_countdown,
        doing_explosion = doing_explosion,
        doing_camera = doing_camera,
        sound2_time = sound2_time,
        sound3_time = sound3_time,
        sound4_time = sound4_time,
        sound5_time = sound5_time,
        sound6_time = sound6_time,
        sound12_time = sound12_time,
        east_wave_time = east_wave_time,
        user = user,
        units = units,
        sound1 = sound1,
        sound2 = sound2,
        sound3 = sound3,
        sound4 = sound4,
        sound7 = sound7,
        sound11 = sound11,
        sound12 = sound12,
        difficulty = difficulty,
    }
end

function Load(state)
    if not state then return end
    start_done = state.start_done
    objective1_complete = state.objective1_complete
    won_lost = state.won_lost
    sound10_played = state.sound10_played
    all_units_spawned = state.all_units_spawned
    doing_countdown = state.doing_countdown
    doing_explosion = state.doing_explosion
    doing_camera = state.doing_camera
    sound2_time = state.sound2_time
    sound3_time = state.sound3_time
    sound4_time = state.sound4_time
    sound5_time = state.sound5_time
    sound6_time = state.sound6_time
    sound12_time = state.sound12_time
    east_wave_time = state.east_wave_time
    user = state.user
    units = state.units
    sound1 = state.sound1
    sound2 = state.sound2
    sound3 = state.sound3
    sound4 = state.sound4
    sound7 = state.sound7
    sound11 = state.sound11
    sound12 = state.sound12
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
        SetScrap(1, 50)
        SetPilot(1, 10)

        ClearObjectives()
        AddObjective("bd15001.otf", "white")

        sound1 = AudioMessage("bd15001.wav")

        start_done = true
    end

    if sound1 and IsAudioMessageDone(sound1) then
        sound1 = nil
        sound2_time = GetTime() + 20.0
    end

    -- Wave 1 (West)
    if GetTime() > sound2_time then
        sound2_time = 99999.0
        sound2 = AudioMessage("bd15002.wav")

        local h = BuildObject("cvfigh", 2, "spawn_west_wave")
        Goto(h, "path_west_wave")
        SetObjectiveOn(h)
        table.insert(units, h)
    end
    if sound2 and IsAudioMessageDone(sound2) then
        sound2 = nil
        sound3_time = GetTime() + 40.0
    end

    -- Wave 2 (South)
    if GetTime() > sound3_time then
        sound3_time = 99999.0
        sound3 = AudioMessage("bd15003.wav")

        local function Spawn(odf)
            local h = BuildObject(odf, 2, "spawn_south_wave")
            Goto(h, "path_south_wave")
            SetObjectiveOn(h)
            table.insert(units, h)
        end
        Spawn("cvfigh"); Spawn("cvfigh"); Spawn("cvfigh")
        Spawn("cvltnk"); Spawn("cvtnk"); Spawn("cvapc")
    end
    if sound3 and IsAudioMessageDone(sound3) then
        sound3 = nil
        sound4_time = GetTime() + 120.0
    end

    -- Wave 3 (North)
    if GetTime() > sound4_time then
        sound4_time = 99999.0
        sound4 = AudioMessage("bd15004.wav")

        local function Spawn(odf)
            local h = BuildObject(odf, 2, "spawn_north_wave")
            Goto(h, "path_north_wave")
            SetObjectiveOn(h)
            table.insert(units, h)
        end
        Spawn("cvapc"); Spawn("cvapc"); Spawn("cvapc")
        Spawn("cvhtnk"); Spawn("cvtnk"); Spawn("cvtnk")
        Spawn("cvtnk")
    end
    if sound4 and IsAudioMessageDone(sound4) then
        sound4 = nil
        sound5_time = GetTime() + 180.0
    end

    -- Wave 4 (East)
    if GetTime() > sound5_time then
        sound5_time = 99999.0
        AudioMessage("bd15005.wav")
        east_wave_time = GetTime() + 60.0

        local function Spawn(odf)
            local h = BuildObject(odf, 2, "spawn_east_wave")
            Goto(h, "path_east_wave")
            SetObjectiveOn(h)
            table.insert(units, h)
        end
        Spawn("cvfigh"); Spawn("cvfigh"); Spawn("cvfigh")
        Spawn("cvltnk"); Spawn("cvltnk"); Spawn("cvltnk")
    end

    if GetTime() > east_wave_time then
        east_wave_time = 99999.0
        sound6_time = GetTime() + 180.0

        local function Spawn(odf)
            local h = BuildObject(odf, 2, "spawn_east_wave")
            Goto(h, "path_east_wave")
            SetObjectiveOn(h)
            table.insert(units, h)
        end
        Spawn("cvltnk"); Spawn("cvltnk")
        Spawn("cvhraz"); Spawn("cvhraz")
        Spawn("cvfigh"); Spawn("cvfigh")
    end

    -- Wave 5 (Massive)
    if GetTime() > sound6_time then
        sound6_time = 99999.0
        AudioMessage("bd15006.wav")

        local function Spawn(odf, loc, path)
            local h = BuildObject(odf, 2, loc)
            Goto(h, path)
            SetObjectiveOn(h)
            table.insert(units, h)
        end
        Spawn("cvhtnk", "spawn_south_wave", "path_south_wave")
        Spawn("cvfigh", "spawn_north_wave", "path_north_wave")
        Spawn("cvfigh", "spawn_north_wave", "path_north_wave")
        Spawn("cvapc", "spawn_west_wave", "path_west_wave")
        Spawn("cvapc", "spawn_west_wave", "path_west_wave")
        Spawn("cvhaul", "spawn_west_wave", "path_west_wave")

        all_units_spawned = true
    end

    -- Defense Check (Lose Condition)
    for i, u in pairs(units) do
        if IsAlive(u) then
            if GetDistance(u, "chin_launch") < 100.0 then
                won_lost = true
                sound11 = AudioMessage("bd15011.wav")
                break
            end
        end
    end

    if sound11 and IsAudioMessageDone(sound11) then
        sound11 = nil
        sound12_time = GetTime() + 5.0
    end
    if GetTime() > sound12_time then
        sound12_time = 99999.0
        sound12 = AudioMessage("bd15012.wav")
    end
    if sound12 and IsAudioMessageDone(sound12) then
        sound12 = nil
        FailMission(GetTime(), "bd15lose.des")
    end

    -- Win Check
    if all_units_spawned and not objective1_complete then
        objective1_complete = true
        for i, u in pairs(units) do
            if IsAlive(u) then objective1_complete = false; break end
        end

        if objective1_complete then
            sound7 = AudioMessage("bd15007.wav")
            ClearObjectives()
            AddObjective("bd15001.otf", "green")
            AddObjective("bd15002.otf", "white")

        end
    end
    if sound7 and IsAudioMessageDone(sound7) then
        sound7 = nil
        doing_countdown = true
        StartCockpitTimer(30, 10, 5)
    end

    -- Finale
    if doing_countdown and GetCockpitTimer() <= 2 and not doing_camera then
        -- BlackDog15Mission.cpp contains a disabled
        -- `sound9 = AudioMessage("bd15013.wav")` immediately before this
        -- finale camera. Keep it documented but disabled to preserve the active
        -- source timing; the camera/explosion branch itself remains intact.
        doing_camera = true
        CameraReady()
        CameraPath("camera_finale", 2400, 0, "spawn_explosion1")
    end

    if doing_countdown and GetCockpitTimer() <= 0 and not doing_explosion then
        doing_explosion = true
        HideCockpitTimer()
        SucceedMission(GetTime() + 5.0, "bd15win.des")

        -- Explosion & White Flash (Restored)
        if ColorFade then
            ColorFade(1.0, 0.5, 255, 255, 255)
        end
        MakeExplosion("xpltrso", "spawn_explosion1")
    end

    -- Near Sound
    if not sound10_played and GetDistance(user, "chin_launch") < 300.0 then
        sound10_played = true
        AudioMessage("bd15010.wav")
    end
end

