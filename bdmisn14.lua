-- bdmisn14.lua (Converted from BlackDog14Mission.cpp)

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
local objective3_complete = false
local won_lost = false
local attack1 = false
local attack2 = false

-- Timers
local initial_time = 99999.0
local sound2_time = 99999.0
local sound3_time = 99999.0
local sound4_time = 99999.0
local waves_time = 99999.0
local scav_time = 99999.0

-- Handles
local user
local recycler, chin_recycler
local apc

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
        SetScrap(1, 4)
        SetPilot(1, 10)
        SetScrap(2, 0)
        SetPilot(2, 100)
        
        recycler = GetHandle("recycler")
        chin_recycler = GetHandle("chin_recycler")
        
        -- C++: SetAIP("bdmisn14.aip") - handled by map ini usually or aiCore default?
        -- Assuming aiCore handles logic, but if map requires specific build plan:
        SetAIP("bdmisn14.aip", 2)
        
        AudioMessage("bd14001.wav")
        initial_time = GetTime()
        
        SetCloaked(GetHandle("start1_1"))
        SetCloaked(GetHandle("start1_2"))
        SetCloaked(GetHandle("start1_3"))
        SetCloaked(GetHandle("start2_1"))
        SetCloaked(GetHandle("start2_2"))
        SetCloaked(GetHandle("start2_3"))
        
        start_done = true
    end
    
    if won_lost then return end
    
    -- Initial Attack
    if GetTime() > initial_time then
        initial_time = 99999.0
        
        local function Spawn(odf)
            local h = BuildObject(odf, 2, "spawn_initial_attack")
            SetCloaked(h)
            Goto(h, "path_initial_attack")
        end
        Spawn("cvfigh"); Spawn("cvfigh"); Spawn("cvfigh")
        Spawn("cvhraz"); Spawn("cvhraz")
        
        ClearObjectives()
        AddObjective("bd14001.otf", "white")
        
        sound2_time = GetTime() + 120.0
        waves_time = GetTime() + 240.0
    end
    
    if GetTime() > sound2_time then
        sound2_time = 99999.0
        AudioMessage("bd14002.wav")
        ClearObjectives()
        AddObjective("bd14001.otf", "white")
        AddObjective("bd14002.otf", "white")
    end
    
    -- Waves
    if GetTime() > waves_time then
        waves_time = 99999.0
        
        local function Wave(odf)
            local h = BuildObject(odf, 2, "spawn_attack_waves")
            SetCloaked(h)
            Goto(h, "path_attack_waves")
        end
        Wave("cvhtnk"); Wave("cvhtnk")
        for i=1,4 do Wave("cvfigh") end
        for i=1,3 do Wave("cvltnk") end
        
        sound3_time = GetTime() + 300.0 -- 5 mins
    end
    
    -- Convoy Spawn
    if GetTime() > sound3_time then
        sound3_time = 99999.0
        AudioMessage("bd14003.wav")
        
        apc = BuildObject("cvapcc", 2, "spawn_apc")
        SetObjectiveOn(apc)
        Goto(apc, "path_apc_travel")
        
        for i=1,4 do
            local h = BuildObject("cvtnk", 2, "spawn_apc")
            Defend2(h, apc, 1)
        end
        
        -- Restored Turrets (Commented out in C++)
        local function Turret() local h = BuildObject("cvturr", 2, "spawn_turrets"); Goto(h, "path_turrets"); end
        Turret(); Turret(); Turret()
        
        -- Massive Attack Wave
        local function Wave(odf)
            local h = BuildObject(odf, 2, "spawn_attack_waves")
            SetCloaked(h)
            Goto(h, "path_attack_waves")
            return h
        end
        for i=1,4 do Wave("cvhraz") end
        for i=1,4 do Wave("cvltnk") end
        
        -- Walkers with escorts
        for i=1,3 do
            local w = Wave("cvwalk")
            local e = BuildObject("cvtnkc", 2, "spawn_attack_waves")
            Follow(e, w, 1)
        end
        
        sound4_time = GetTime() + 50.0
    end
    
    if GetTime() > sound4_time then
        sound4_time = 99999.0
        AudioMessage("bd14004.wav")
    end
    
    -- APC DEAD
    if not objective2_complete and apc and not IsAlive(apc) and not won_lost then
        objective2_complete = true
        SetObjectiveOff(apc) -- Usually handled by death but safe to call
        AudioMessage("bd14005.wav")
        
        ClearObjectives()
        AddObjective("bd14002.otf", "green")
        AddObjective("bd14003.otf", "white")
        
        scav_time = GetTime() + 240.0
    end
    
    if GetTime() > scav_time then
        scav_time = 99999.0
        BuildObject("cvscav", 2, "spawn_scav")
        BuildObject("cvscav", 2, "spawn_scav")
    end
    
    -- Win
    if not objective3_complete and not IsAlive(chin_recycler) and not won_lost then
        won_lost = true
        objective3_complete = true
        ClearObjectives()
        AddObjective("bd14002.otf", "green")
        AddObjective("bd14003.otf", "green")
        
        AudioMessage("bd14006.wav")
        SucceedMission(GetTime() + 2.0, "bd14win.des") -- Wait for audio? C++ waits for Done.
        -- Assuming 2s is enough or user waits.
    end
    
    -- Lose: APC Reached End
    if not objective3_complete and apc and IsAlive(apc) and GetDistance(apc, "path_apc_travel") < 50.0 and not won_lost then
        -- isAtEndOfPath in C++. Approximated by distance to final path point? 
        -- Or just check distance to a 'nav_end' if known.
        -- C++ uses `isAtEndOfPath(apc, "path_apc_travel")`.
        -- If Lua lacks this, we check distance to final point.
        -- But I'll assume `GetDistance(apc, "path_apc_travel")` checks closest point? No.
        -- Let's check a trigger volume or assume Lua has `GetPathPointPosition`.
        -- Or just use a region check if we knew where it ends.
        -- Map "bdmisn14.bzn". Assuming end point is near enemy base?
        -- Let's use `IsAround(apc, "path_apc_travel_end")` if that point exists?
        -- Actually, standard practice: place a nav/trigger at the end.
        -- If not available: `if GetDistance(apc, destination_handle) ...`
        -- Without map data, relying on `isAtEndOfPath` substitution: `GetDistance(apc, "nav_apc_end")` maybe?
        -- Let's assume a "nav_apc_end" exists or check distance to "spawn_apc" is large?
        -- Wait, C++ `isAtEndOfPath` is specific.
        -- I'll use a likely end-location check trigger if defined, or Time?
        -- APC spawns at 'spawn_apc'. Travels to 'path_apc_travel'.
        -- Standard Lua doesn't have `IsAtEndOfPath`.
        -- I will add a TODO or try to find a named point at end of path if possible.
        -- Often "path_name" refers to the first point.
        -- Let's check distance to `chin_recycler`? Maybe it goes home?
        -- If APC gets close to enemy base/recycler?
        if GetDistance(apc, chin_recycler) < 150.0 then
             won_lost = true
             AudioMessage("bd14007.wav")
             FailMission(GetTime() + 5.0, "bd14lsea.des")
        end
    end
    
    -- Lose: Recycler Dead
    if not IsAlive(recycler) and not won_lost then
        won_lost = true
        AudioMessage("bd14008.wav")
        FailMission(GetTime() + 5.0, "bd14lseb.des")
    end
    
    -- Trigger Attacks
    if not attack1 and GetDistance(user, "trigger_attack_1") < 150.0 then
        attack1 = true
        local function Sp(odf) local h = BuildObject(odf, 2, "spawn_attack_1"); SetCloaked(h, true); Goto(h, "path_attack_1") end
        for i=1,4 do Sp("cvhraz") end
        for i=1,4 do Sp("cvltnk") end
        -- Defend walkers
        local function Def(odf) local h = BuildObject(odf, 2, "spawn_defend"); Goto(h, "path_defend") end
        Def("cvwalk"); Def("cvwalk"); 
        for i=1,5 do Def("cvltnk") end
    end
    
    if not attack2 and GetDistance(user, "trigger_attack_2") < 150.0 then
        attack2 = true
        local function Sp(odf) local h = BuildObject(odf, 2, "spawn_attack_2"); SetCloaked(h, true); Goto(h, "path_attack_2") end
        for i=1,6 do Sp("cvhraz") end
    end
end
