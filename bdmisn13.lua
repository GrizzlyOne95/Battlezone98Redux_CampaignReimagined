<<<<<<< HEAD
-- bdmisn13.lua (Converted from BlackDog13Mission.cpp)

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
local objective2_complete = false
local camera_complete = false
local camera_ready = false
local arrived = false
local defenders_spawned = {false, false, false, false, false, false}
local recycled = {false, false, false, false, false, false}
local silos_recycled = false
local recycle_checked = false
local sound2_played = false
local lost = false
local won = false

-- Timers
local time_waves = {99999.0, 99999.0, 99999.0, 99999.0}

-- Handles
local user
local recycler, chin_recycler
local silos = {} -- 1-6

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
        SetScrap(1, 30)
        SetPilot(1, 10)
        
        recycler = GetHandle("recycler")
        chin_recycler = GetHandle("chin_recycler")
        for i=1,6 do silos[i] = GetHandle("chin_silo"..i) end
        
        time_waves[1] = GetTime() + 180.0
        time_waves[2] = GetTime() + 600.0
        time_waves[3] = GetTime() + 900.0
        time_waves[4] = GetTime() + 1800.0
        
        StartCockpitTimer(45*60, 30, 10)
        
        for i=1,6 do
            local h = GetHandle("nav_chin_silo"..i)
            if h then SetName(h, "Scrap Field") end
        end
        
        start_done = true
    end
    
    if lost or won then return end
    
    -- Intro
    if not camera_complete then
        if not camera_ready then
            camera_ready = true
            CameraReady()
            AudioMessage("bd13001.wav")
        end
        
        if not arrived then
            CameraPath("camera_intro", 500, 1500, silos[6])
            -- Assuming camera engine handles stopping
        end
        
        if CameraCancelled() then -- or audio done approx
            CameraFinish()
            camera_complete = true
            ClearObjectives()
            AddObjective("bd13001.otf", "white")
        end
    end
    
    -- Waves
    local function SpawnWave(list)
        for _, u in pairs(list) do
            local h = BuildObject(u, 2, "spawn_attack_waves")
            Goto(h, recycler, 1)
        end
    end
    
    if GetTime() > time_waves[1] then
        time_waves[1] = 99999.0
        SpawnWave({"cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvltnk", "cvltnk", "cvtnk"})
    end
    
    if GetTime() > time_waves[2] then
        time_waves[2] = 99999.0
        SpawnWave({"cvrckt", "cvrckt", "cvltnk", "cvltnk", "cvtnk", "cvtnk"})
    end
    
    if GetTime() > time_waves[3] then
        time_waves[3] = 99999.0
        SpawnWave({"cvhraz", "cvhraz", "cvhraz", "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvfigh"})
    end
    
    if GetTime() > time_waves[4] then
        time_waves[4] = 99999.0
        SpawnWave({"cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvhtnk", "cvhtnk"})
    end
    
    -- Silo Defenders
    local def_units_1 = {"cvfigh", "cvfigh", "cvltnk", "cvltnk"}
    local def_units_2 = {"cvltnk", "cvltnk", "cvltnk", "cvltnk"}
    local def_units_3 = {"cvfigh", "cvfigh", "cvrckt", "cvrckt"}
    local def_units_4 = {"cvtnk", "cvtnk", "cvltnk", "cvltnk"}
    local def_units_5 = {"cvfigh", "cvfigh", "cvfigh", "cvfigh"}
    local def_units_6 = {"cvhtnk", "cvhtnk", "cvfigh", "cvfigh"}
    local all_defs = {def_units_1, def_units_2, def_units_3, def_units_4, def_units_5, def_units_6}
    local spawns = {"spawn_defend1", "spawn_defend1", "spawn_defend6", "spawn_defend6"} -- C++ reuses spawns by index per unit group
    
    for i=1,6 do
        if not defenders_spawned[i] and GetDistance(user, silos[i]) < 400.0 then -- Distance check missing in C++, likely implicit or <400
            defenders_spawned[i] = true
            local units = all_defs[i]
            for j=1,4 do
                local h = BuildObject(units[j], 2, spawns[j]) -- Simulating the C++ unrolled loop
                Defend2(h, silos[i], 1)
            end
        end
    end
    
    -- Recycle Check
    if not silos_recycled then
        for i=1,6 do
            if not recycled[i] then
                if not IsAlive(silos[i]) then -- Died
                    -- Use native API to check if recycled
                    if IsRecycledByTeam(silos[i], 1) then
                         recycled[i] = true
                    else
                         lost = true
                         FailMission(GetTime() + 1.0, "bd13lsec.des") -- Destroyed!
                    end
                end
            end
        end
        
        local all = true
        for i=1,6 do if not recycled[i] then all = false break end end
        if all then 
            silos_recycled = true 
            HideCockpitTimer()
            sound2_played = true
            AudioMessage("bd13002.wav")
            ClearObjectives()
            AddObjective("bd13001.otf", "green")
            AddObjective("bd13002.otf", "white")
        end
    end
    
    -- Timer Fail
    if not recycle_checked and GetCockpitTimer() <= 0.0 then
        recycle_checked = true
        if not silos_recycled then
            lost = true
            AudioMessage("bd13005.wav")
            FailMission(GetTime() + 1.0, "bd13lsea.des") -- Time out
        end
    end
    
    -- Lose Logic
    if not IsAlive(recycler) and not won and not lost then
        lost = true
        AudioMessage("bd13004.wav")
        FailMission(GetTime() + 1.0, "bd13lseb.des")
    end
    
    -- Enemy Recycler Logic
    if IsAlive(chin_recycler) then
        if GetHealth(chin_recycler) < 1.0 and not silos_recycled and not won and not lost then
            lost = true
            FailMission(GetTime() + 1.0, "bd13lsed.des") -- Attacked too early
        end
    elseif silos_recycled and not won and not lost then -- Dead and allowed
        won = true
        AudioMessage("bd13003.wav")
        SucceedMission(GetTime() + 1.0, "bd13win.des")
    end
end
=======
-- bdmisn13.lua (Converted from BlackDog13Mission.cpp)

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
local objective2_complete = false
local camera_complete = false
local camera_ready = false
local arrived = false
local defenders_spawned = {false, false, false, false, false, false}
local recycled = {false, false, false, false, false, false}
local silos_recycled = false
local recycle_checked = false
local sound2_played = false
local lost = false
local won = false

-- Timers
local time_waves = {99999.0, 99999.0, 99999.0, 99999.0}

-- Handles
local user
local recycler, chin_recycler
local silos = {} -- 1-6

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
        SetScrap(1, 30)
        SetPilot(1, 10)
        
        recycler = GetHandle("recycler")
        chin_recycler = GetHandle("chin_recycler")
        for i=1,6 do silos[i] = GetHandle("chin_silo"..i) end
        
        time_waves[1] = GetTime() + 180.0
        time_waves[2] = GetTime() + 600.0
        time_waves[3] = GetTime() + 900.0
        time_waves[4] = GetTime() + 1800.0
        
        StartCockpitTimer(45*60, 30, 10)
        
        for i=1,6 do
            local h = GetHandle("nav_chin_silo"..i)
            if h then SetName(h, "Scrap Field") end
        end
        
        start_done = true
    end
    
    if lost or won then return end
    
    -- Intro
    if not camera_complete then
        if not camera_ready then
            camera_ready = true
            CameraReady()
            AudioMessage("bd13001.wav")
        end
        
        if not arrived then
            CameraPath("camera_intro", 500, 1500, silos[6])
            -- Assuming camera engine handles stopping
        end
        
        if CameraCancelled() then -- or audio done approx
            CameraFinish()
            camera_complete = true
            ClearObjectives()
            AddObjective("bd13001.otf", "white")
        end
    end
    
    -- Waves
    local function SpawnWave(list)
        for _, u in pairs(list) do
            local h = BuildObject(u, 2, "spawn_attack_waves")
            Goto(h, recycler, 1)
        end
    end
    
    if GetTime() > time_waves[1] then
        time_waves[1] = 99999.0
        SpawnWave({"cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvltnk", "cvltnk", "cvtnk"})
    end
    
    if GetTime() > time_waves[2] then
        time_waves[2] = 99999.0
        SpawnWave({"cvrckt", "cvrckt", "cvltnk", "cvltnk", "cvtnk", "cvtnk"})
    end
    
    if GetTime() > time_waves[3] then
        time_waves[3] = 99999.0
        SpawnWave({"cvhraz", "cvhraz", "cvhraz", "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvfigh"})
    end
    
    if GetTime() > time_waves[4] then
        time_waves[4] = 99999.0
        SpawnWave({"cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvhtnk", "cvhtnk"})
    end
    
    -- Silo Defenders
    local def_units_1 = {"cvfigh", "cvfigh", "cvltnk", "cvltnk"}
    local def_units_2 = {"cvltnk", "cvltnk", "cvltnk", "cvltnk"}
    local def_units_3 = {"cvfigh", "cvfigh", "cvrckt", "cvrckt"}
    local def_units_4 = {"cvtnk", "cvtnk", "cvltnk", "cvltnk"}
    local def_units_5 = {"cvfigh", "cvfigh", "cvfigh", "cvfigh"}
    local def_units_6 = {"cvhtnk", "cvhtnk", "cvfigh", "cvfigh"}
    local all_defs = {def_units_1, def_units_2, def_units_3, def_units_4, def_units_5, def_units_6}
    local spawns = {"spawn_defend1", "spawn_defend1", "spawn_defend6", "spawn_defend6"} -- C++ reuses spawns by index per unit group
    
    for i=1,6 do
        if not defenders_spawned[i] and GetDistance(user, silos[i]) < 400.0 then -- Distance check missing in C++, likely implicit or <400
            defenders_spawned[i] = true
            local units = all_defs[i]
            for j=1,4 do
                local h = BuildObject(units[j], 2, spawns[j]) -- Simulating the C++ unrolled loop
                Defend2(h, silos[i], 1)
            end
        end
    end
    
    -- Recycle Check
    if not silos_recycled then
        for i=1,6 do
            if not recycled[i] then
                if not IsAlive(silos[i]) then -- Died
                    -- Use native API to check if recycled
                    if IsRecycledByTeam(silos[i], 1) then
                         recycled[i] = true
                    else
                         lost = true
                         FailMission(GetTime() + 1.0, "bd13lsec.des") -- Destroyed!
                    end
                end
            end
        end
        
        local all = true
        for i=1,6 do if not recycled[i] then all = false break end end
        if all then 
            silos_recycled = true 
            HideCockpitTimer()
            sound2_played = true
            AudioMessage("bd13002.wav")
            ClearObjectives()
            AddObjective("bd13001.otf", "green")
            AddObjective("bd13002.otf", "white")
        end
    end
    
    -- Timer Fail
    if not recycle_checked and GetCockpitTimer() <= 0.0 then
        recycle_checked = true
        if not silos_recycled then
            lost = true
            AudioMessage("bd13005.wav")
            FailMission(GetTime() + 1.0, "bd13lsea.des") -- Time out
        end
    end
    
    -- Lose Logic
    if not IsAlive(recycler) and not won and not lost then
        lost = true
        AudioMessage("bd13004.wav")
        FailMission(GetTime() + 1.0, "bd13lseb.des")
    end
    
    -- Enemy Recycler Logic
    if IsAlive(chin_recycler) then
        if GetHealth(chin_recycler) < 1.0 and not silos_recycled and not won and not lost then
            lost = true
            FailMission(GetTime() + 1.0, "bd13lsed.des") -- Attacked too early
        end
    elseif silos_recycled and not won and not lost then -- Dead and allowed
        won = true
        AudioMessage("bd13003.wav")
        SucceedMission(GetTime() + 1.0, "bd13win.des")
    end
end
>>>>>>> 30fa079494619a8bd6565c444554253b8b48a7b9
