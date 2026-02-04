-- bdmisn15.lua (Converted from BlackDog15Mission.cpp)

-- Compatibility
SetLabel = SetLabel or SettLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
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

-- Difficulty
local difficulty = 2

function Start()
    if exu then
        difficulty = (exu.GetDifficulty and exu.GetDifficulty()) or 2
        if exu.EnableShotConvergence then exu.EnableShotConvergence() end
        if exu.SetSmartCursorRange then exu.SetSmartCursorRange(500) end
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
        
        AudioMessage("bd15001.wav")
        sound2_time = GetTime() + 20.0 -- Adjust for audio length approx
        
        start_done = true
    end
    
    if won_lost then return end
    
    -- Wave 1 (West)
    if GetTime() > sound2_time then
        sound2_time = 99999.0
        AudioMessage("bd15002.wav")
        -- Wait for audio done? C++ does. We approximate.
        sound3_time = GetTime() + 40.0
        
        local h = BuildObject("cvfigh", 2, "spawn_west_wave")
        Goto(h, "path_west_wave")
        SetObjectiveOn(h)
        table.insert(units, h)
    end
    
    -- Wave 2 (South)
    if GetTime() > sound3_time then
        sound3_time = 99999.0
        AudioMessage("bd15003.wav")
        sound4_time = GetTime() + 120.0
        
        local function Spawn(odf)
            local h = BuildObject(odf, 2, "spawn_south_wave")
            Goto(h, "path_south_wave")
            SetObjectiveOn(h)
            table.insert(units, h)
        end
        Spawn("cvfigh"); Spawn("cvfigh"); Spawn("cvfigh")
        Spawn("cvltnk"); Spawn("cvtnk"); Spawn("cvapc")
    end
    
    -- Wave 3 (North)
    if GetTime() > sound4_time then
        sound4_time = 99999.0
        AudioMessage("bd15004.wav")
        sound5_time = GetTime() + 180.0
        
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
                AudioMessage("bd15011.wav")
                sound12_time = GetTime() + 5.0
                break
            end
        end
    end
    
    if GetTime() > sound12_time then
        sound12_time = 99999.0
        AudioMessage("bd15012.wav")
        FailMission(GetTime() + 2.0, "bd15lose.des")
    end
    
    -- Win Check
    if all_units_spawned and not objective1_complete then
        objective1_complete = true
        for i, u in pairs(units) do
            if IsAlive(u) then objective1_complete = false; break end
        end
        
        if objective1_complete then
            AudioMessage("bd15007.wav")
            ClearObjectives()
            AddObjective("bd15001.otf", "green")
            AddObjective("bd15002.otf", "white")
            
            doing_countdown = true
            StartCockpitTimer(30, 10, 5)
        end
    end
    
    -- Finale
    if doing_countdown and GetCockpitTimer() <= 2 and not doing_camera then
        doing_camera = true
        CameraReady()
        CameraPath("camera_finale", 2400, 0, "spawn_explosion1")
    end
    
    if doing_countdown and GetCockpitTimer() <= 0 and not doing_explosion then
        doing_explosion = true
        HideCockpitTimer()
        SucceedMission(GetTime() + 5.0, "bd15win.des")
        
        SucceedMission(GetTime() + 5.0, "bd15win.des")
        
        -- Explosion & White Flash (Restored)
        if ColorFade then
            ColorFade(1.0, 0.5, 255, 255, 255)
        end
        BuildObject("xpltrso", 0, "spawn_explosion1") -- C++ uses MakeExplosion
    end
    
    -- Near Sound
    if not sound10_played and GetDistance(user, "chin_launch") < 300.0 then
        sound10_played = true
        AudioMessage("bd15010.wav")
    end
end
