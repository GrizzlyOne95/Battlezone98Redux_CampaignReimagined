-- Misns4 Mission Script (Converted from Misns4Mission.cpp)

-- Compatibility for 1.5
SetLabel = SetLabel or SettLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
local exu = require("exu")
local aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")

-- Helper for AI
local function SetupAI()
    DiffUtils.SetupTeams(aiCore.Factions.CCA, aiCore.Factions.NSDF, 2)
end

-- Variables
local counter = false
local first = false
local first_bridge = false
local warning = false
local bridge_clear = false
local won = false
local lost = false
local start_done = false
local north_bridge = false

-- Convoy Tracking
local convoy_total = 5
local convoy_count = 0
local convoy_dead = 0
local win_count = 0
local convoy_handles = {} -- Store handles
local convoy_alive = {} -- Store alive state bools (if needed, or just check handles)
local safe = {} -- Store arrival state

-- Timers
local wakeup_time = 99999.0
local convoy_time = 99999.0
local attack_time = 99999.0
local raider_time = 99999.0
local army_time = 99999.0
local counter_time = 99999.0

-- Handles
local player
local cam1
local t1, t2, b1, b2, h1, h2
local counter1, counter2, counter3, counter4

-- Config
local difficulty = 2

function Start()
    if exu then
        if exu.EnableShotConvergence then exu.EnableShotConvergence() end
        if exu.SetSmartCursorRange then exu.SetSmartCursorRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    
    player = GetPlayerHandle()
    start_done = false
    
    -- Init tables
    for i=1, convoy_total do
        convoy_handles[i] = nil
        convoy_alive[i] = true
        safe[i] = false
    end
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then
        aiCore.AddObject(h)
    end
    -- Unit Turbo based on difficulty
    if exu and exu.SetUnitTurbo and IsCraft(h) then
        if team ~= 0 then
             if difficulty >= 3 then exu.SetUnitTurbo(h, true) end
        end
    end
    
    -- In C++ AddObject, it auto-assigns haulers to convoy list if they are Team 1 and "svhaul"
    -- We'll do this in Update where we spawn them to ensure correct indexing, 
    -- or rely on Lua's dynamic nature.
    -- Since we spawn them explicitly in logic, we can assign them there.
end

function DeleteObject(h)
end

function Update()
    player = GetPlayerHandle()
    aiCore.Update()
    
    if not start_done then
        start_done = true
        convoy_time = GetTime() + DiffUtils.ScaleTimer(420.0)
        wakeup_time = GetTime() + DiffUtils.ScaleTimer(30.0)
        
        BuildObject("avartl", 2, "spawn2")
        cam1 = BuildObject("spcamr", 1, "camerapt")
        if IsAlive(cam1) then SetLabel(cam1, "Bridge") end
        
        raider_time = GetTime() + DiffUtils.ScaleTimer(30.0)
        army_time = GetTime() + DiffUtils.ScaleTimer(100.0)
        
        AddScrap(1, DiffUtils.ScaleRes(50))
        SetPilot(1, DiffUtils.ScaleRes(30))
        SetPilot(2, DiffUtils.ScaleRes(30))
        
        ClearObjectives()
        AddObjective("misns4.otf", "white")
        AudioMessage("misns401.wav")
        AudioMessage("misns410.wav")
        StartCockpitTimer(DiffUtils.ScaleTimer(420), DiffUtils.ScaleTimer(300), 0)
        
        -- Static Objects (Team 2 Turrets/Power/Con)
        BuildObject("abtowe", 2, "tower1")
        BuildObject("abtowe", 2, "tower2")
        BuildObject("ablpow", 2, "power1")
        BuildObject("ablpow", 2, "power2")
        BuildObject("svcnst", 1, "svcnst")
    end
    
    -- Timer Events
    
    -- Wakeup Raider (Repeating?) No, loop below sets wakeup_time=99999
    if (GetTime() > wakeup_time) then
        local h = BuildObject("avfigh", 2, "spawn4")
        Goto(h, "wakeup")
        wakeup_time = 99999.0
    end
    
    -- Convoy Spawn Logic
    if (GetTime() > convoy_time) then
        if not first then
            AudioMessage("misns402.wav")
            StopCockpitTimer()
            HideCockpitTimer()
            first = true
        end
        
        local hauler = BuildObject("svhaul", 1, "spawn1")
        SetObjectiveOn(hauler)
        Goto(hauler, "escort") -- Ensure they follow path
        
        -- Add to tracking list
        convoy_count = convoy_count + 1
        convoy_handles[convoy_count] = hauler
        convoy_alive[convoy_count] = true
        
        if convoy_count < convoy_total then
            convoy_time = GetTime() + DiffUtils.ScaleTimer(45.0)
        else
            convoy_time = 99999.0
        end
    end
    
    -- Raider Wave
    if (GetTime() > raider_time) then
        BuildObject("avfigh", 2, "spawn4")
        BuildObject("avfigh", 2, "spawn4")
        -- Restoration: BuildObject("avltnk",2,"spawn4"); (Commented out in C++)
        BuildObject("avltnk", 2, "spawn4") 
        raider_time = 99999.0
    end
    
    -- Army Wave (Bridge Defense)
    if (GetTime() > army_time) then
        t1 = BuildObject("avtank", 2, "sbridge")
        t2 = BuildObject("avtank", 2, "sbridge")
        b1 = BuildObject("avhraz", 2, "sbridge")
        -- Restoration: b2 = BuildObject("avhraz",2,"sbridge"); (Commented out)
        b2 = BuildObject("avhraz", 2, "sbridge")
        
        army_time = 99999.0
    end
    
    -- North Bridge Trigger (Base Spawn)
    if (not north_bridge) and (GetDistance(player, "sbridge") < 200.0) then
        north_bridge = true
        -- Restoration: BuildObject("avtank",2,"spawn3") (Commented out in C++)
        BuildObject("avtank", 2, "spawn3")
        
        -- Active code:
        BuildObject("avltnk", 2, "spawn3")
        BuildObject("avturr", 2, "spawn3")
        BuildObject("avscav", 2, "spawn3")
        BuildObject("avrecy", 2, "spawn3")
        -- C++ Comment: "Now load an AIP." (Not implemented in C++?)
        -- We can enable a defensive AIP here.
        -- SetAIP("defensive.aip") -- Assuming generic
    end
    
    -- Bridge Cleared -> Counter Attack
    if (not bridge_clear) and north_bridge and 
       (not IsAlive(t1)) and (not IsAlive(t2)) and (not IsAlive(b1)) and (not IsAlive(b2)) then -- Added b2 check
       
       AudioMessage("misns405.wav")
       bridge_clear = true
       SetAIP("misns4.aip")
       counter_time = GetTime() + DiffUtils.ScaleTimer(150.0) -- 2.5 mins
    end
    
    -- Warning Zone
    if (not warning) and (GetDistance(player, "warn1") < 200.0) then
        AudioMessage("misns409.wav")
        warning = true
    end
    
    -- Counter Attack Trigger
    -- Triggers if timer expires OR Convoy #2 gets near "warn1" (forward scout?)
    -- C++ lines 230+: if (IsAlive(convoy_handle[2])...
    -- Indexing note: convoy_handle[2] is the 3rd one in C++ (0-based) or 2nd? C++ array is [10].
    -- Loop 98: for (count=0;count<convoy_total;count++).
    -- So convoy_handle[2] is the *3rd* hauler spawned (0,1,2).
    -- In Lua, we use 1-based usually.
    -- Let's assume we check the 3rd spawned hauler.
    local scout_hauler = convoy_handles[3] 
    
    if IsAlive(scout_hauler) and (not counter) and 
       ((GetTime() > counter_time) or (GetDistance(scout_hauler, "warn1") < 200.0)) then
       
       counter1 = BuildObject("avrckt", 2, "counter"); Goto(counter1, "sbridge")
       counter2 = BuildObject("avrckt", 2, "counter"); Goto(counter2, "sbridge")
       counter3 = BuildObject("avrckt", 2, "counter"); Goto(counter3, "sbridge")
       counter4 = BuildObject("avrckt", 2, "counter"); Goto(counter4, "sbridge")
       
       counter = true
       counter_time = 99999.0
    end
    
    -- Convoy Monitoring Loop
    for i=1, convoy_count do -- Iterate over currently spawned ones
        local h = convoy_handles[i]
        if h then
            -- Death Check
            if (not IsAlive(h)) and (convoy_alive[i]) then
                AudioMessage("misns403.wav")
                convoy_alive[i] = false
                convoy_dead = convoy_dead + 1
                
                -- Fail Condition: > 1/3 dead. 5 total -> 1.66 -> 2 dead = Fail?
                -- C++: if (convoy_dead > convoy_total/3) -> 5/3 = 1 (integer div). 
                -- So if dead > 1 -> 2 dead.
                -- So 2 dead = Fail. 4 must live.
                if convoy_dead > math.floor(convoy_total/3) then
                    FailMission(GetTime() + 15.0, "misns4l1.des")
                end
            end
            
            -- Goal Check
            if IsAlive(h) and (GetDistance(h, "goal") < 100.0) and (not safe[i]) then
                safe[i] = true
                win_count = win_count + 1
            end
        end
    end
    
    -- Win Condition
    -- C++: (win_count == convoy_total-1) -> 4.
    if (win_count == (convoy_total - 1)) and (not won) then
        SucceedMission(GetTime() + 10.0, "misns4w1.des")
        won = true
    end
end
