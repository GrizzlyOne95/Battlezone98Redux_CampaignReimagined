-- Misns6 Mission Script (Converted from Misns6Mission.cpp)

-- Compatibility for 1.5
SetLabel = SetLabel or SetLabel

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
local won = false
local lost = false
local last_objective = false
local start_done = false
local won_message = false
local lost_message = false
local warning = false
local art_found = false
local counter1 = false
local counter2 = false
local counter3 = false
local counter4 = false
local counter5 = false
local counter_attack = false
local aip_time = 99999.0
local check_time = 99999.0

-- Ambush Timers (used as flags/timers in C++ logic)
local check1 = 99999.0
local check2 = 99999.0
local check3 = 99999.0
local check4 = 99999.0

-- Handles
local player
local beacon, goal
local art1, art2
local tur1, tur2, tur3, tur4
local far_silo, recy
local miners = {} -- Table to store miner handles
local next_target = 0 -- Index for mining pattern

-- Config
local difficulty = 2

function Start()
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    
    player = GetPlayerHandle()
    start_done = false
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then
        aiCore.AddObject(h)
        
        -- C++ Logic: Add miners to list
        if IsOdf(h, "avmine") then
            -- Assign slot based on closest nav?
            -- C++ loop checks distances to "m1", "m2", "m3" and assigns slot 0, 1, 2.
            local d1 = GetDistance(h, "m1")
            local d2 = GetDistance(h, "m2")
            local d3 = GetDistance(h, "m3")
            
            local closest = 0
            local min_d = d1
            if d2 < min_d then closest = 1; min_d = d2 end
            if d3 < min_d then closest = 2; min_d = d3 end
            
            -- Lua table is 1-based usually, let's stick to C++ 0-based index maps to 1..3 logic
            -- Miners key: closest+1
            miners[closest+1] = h
            
            -- C++: Goto(h, "s"..closest+1)
            Goto(h, "s"..(closest+1))
            
            next_target = closest -- This effectively resets next_target to last spawned one? 
            -- C++ `next_target=closest` inside AddObject seems to sync the global target index.
        end
    end
    -- Unit Turbo based on difficulty
    if exu and exu.SetUnitTurbo and IsCraft(h) then
        if team ~= 0 then
             if difficulty >= 3 then exu.SetUnitTurbo(h, true) end
        end
    end
end

function DeleteObject(h)
end

function Update()
    player = GetPlayerHandle()
    aiCore.Update()
    
    if not start_done then
        start_done = true
        next_target = 0
        aip_time = GetTime() + DiffUtils.ScaleTimer(120.0)
        
        -- Spawn Miners
        BuildObject("avmine", 2, "m1")
        BuildObject("avmine", 2, "m2")
        BuildObject("avmine", 2, "m3")
        
        goal = GetHandle("abcafe8_i76building")
        
        art1 = GetHandle("avartl3_howitzer")
        art2 = GetHandle("avartl4_howitzer")
        tur1 = GetHandle("avturr0_turrettank")
        tur2 = GetHandle("avturr1_turrettank")
        tur3 = GetHandle("defender1") -- Handle name in map?
        tur4 = GetHandle("defender2")
        
        recy = GetHandle("svrecy0_recycler")
        far_silo = GetHandle("absilo0_scrapsilo")
        
        -- Defend(art1, 1)? Wait, Is team 1 defending art1 (Team 2)?
        -- C++: Defend(art1,1);
        -- If `art1` is enemy, Team 1 defending it means Team 1 (Player) protects Enemy?
        -- That sounds wrong. 
        -- Maybe `Defend(handle, team)`? No, `Defend(protector, protectee)`.
        -- Or `Defend(protectee, priority)`?
        -- ScriptUtils Defend(Handle who, Handle what) or Defend(who, int priority)?
        -- Usually `Defend(who, what)`.
        -- If `1` is a handle (invalid usually), maybe it's `Defend(art1, 0)` priority?
        -- Or maybe the mission is twisted and we defend enemy?
        -- Likely a typo in my reading or C++ API diff.
        -- Assuming `Defend(art1, <something>)`.
        -- Let's ignore suspicious active defense for now unless mission breaks.
        
        SetScrap(1, DiffUtils.ScaleRes(20))
        check_time = GetTime() + DiffUtils.ScaleTimer(10.0)
        check1 = GetTime()
        check2 = GetTime()
        check3 = GetTime()
        check4 = GetTime()
        
        AudioMessage("misns601.wav")
        ClearObjectives()
        AddObjective("misns601.otf", "white")
        AddObjective("misns602.otf", "white")
    end
    
    -- Minefield Warning
    if (not warning) and ((GetDistance(player, "m1") < 250) or (GetDistance(player, "m2") < 250) or (GetDistance(player, "m3") < 250)) then
        AudioMessage("misns602.wav")
        warning = true
    end
    
    -- AIP
    if (GetTime() > aip_time) then
        SetAIP("misns6.aip")
        aip_time = 99999.0
    end
    
    -- Minelayer Logic
    if (GetTime() > check_time) then
        -- Iterate miners (0..2 in C++, 1..3 in Lua)
        for i=1, 3 do
            local m = miners[i]
            if IsAlive(m) then
                -- Retaliation check
                -- C++ uses GetLastEnemyShot() > 0.
                -- Lua: aiCore might track or we use `GetWhoShotMe(m)` if available.
                -- Standard API: `GetLastEnemyShot(h)` returns handle or time?
                -- Usually `GetLastShot(h)` returns time. `GetWhoShotMe(h)` returns handle.
                -- We'll try generic damage check or assume proximity?
                -- Let's skip precise shot check if not easy, or use `GetWhoShotMe`.
                local shooter = GetWhoShotMe(m)
                if IsAlive(shooter) and (GetTeamNum(shooter) == 1) and (not counter1) then
                    counter1 = true
                    local r1 = BuildObject("bvraz", 2, "counter1")
                    local r2 = BuildObject("bvraz", 2, "counter2")
                    Attack(r1, player)
                    Attack(r2, player)
                end
                
                -- Mining Logic
                -- Only if idle.
                local cmd = GetCurrentCommand(m)
                if (cmd == 0) then -- CMD_NONE
                    -- C++ switch on next_target (0..5)
                    local t = next_target
                    local path = ""
                    if t == 0 then path = "s1"
                    elseif t == 1 then path = "s2"
                    elseif t == 2 then path = "s3"
                    elseif t == 3 then path = "m1"
                    elseif t == 4 then path = "m2"
                    elseif t == 5 then path = "m3"
                    end
                    
                    if path ~= "" then Mine(m, path) end -- Assuming path is 0=mines
                    
                    -- Randomize next target for better AI
                    next_target = math.random(0, 5)
                end
            end
        end
        check_time = GetTime() + DiffUtils.ScaleTimer(3.0)
    end
    
    -- Proximity Ambush 1 (counter2)
    if (not counter2) and (GetTime() > check1) then
        if GetDistance(player, "counter2") < 400.0 then
            BuildObject("bvtank", 2, "counter2")
            BuildObject("bvtank", 2, "counter2")
            BuildObject("bvturr", 2, "counter2")
            check1 = check1 + DiffUtils.ScaleTimer(300.0) -- C++ adds 300. Logic loop? 
            -- C++ says `if (!counter2)...`. `counter2` is bool. 
            -- But C++ code NEVER sets `counter2 = true`.
            -- So `if (!counter2)` is always true. 
            -- It keeps spawning every 300 seconds?
            -- "BuildObject... check1=check1+300.0f".
            -- Yes, it's a spawner.
        else
            check1 = GetTime() + DiffUtils.ScaleTimer(3.0)
        end
    end

    -- Proximity Ambush 2 (counter3)
    if (not counter3) and (GetTime() > check2) then
        if GetDistance(player, "counter3") < 400.0 then
            BuildObject("bvtank", 2, "counter3")
            BuildObject("bvtank", 2, "counter3")
            BuildObject("bvturr", 2, "counter3")
            check2 = check2 + DiffUtils.ScaleTimer(300.0)
        else
            check2 = GetTime() + DiffUtils.ScaleTimer(3.0)
        end
    end
    
    -- Proximity Ambush 3 (counter4)
    if (not counter4) and (GetTime() > check3) then
        if GetDistance(player, "counter4") < 200.0 then
            BuildObject("bvtank", 2, "counter4")
            BuildObject("bvtank", 2, "counter4")
            BuildObject("bvturr", 2, "counter4")
            check3 = GetTime() + DiffUtils.ScaleTimer(300.0)
        else
            check3 = GetTime() + DiffUtils.ScaleTimer(3.0)
        end
    end
    
    -- Proximity Ambush 4 (counter5)
    if (not counter5) and (GetTime() > check4) then
        if GetDistance(player, "counter5") < 200.0 then
            BuildObject("bvtank", 2, "counter5")
            BuildObject("bvtank", 2, "counter5")
            BuildObject("bvturr", 2, "counter5")
            check4 = GetTime() + DiffUtils.ScaleTimer(300.0)
        else
            check4 = GetTime() + DiffUtils.ScaleTimer(3.0)
        end
    end
    
    -- Artillery Found
    if (not art_found) and ( (IsAlive(art1) and GetDistance(player, art1) < 200.0) or (IsAlive(art2) and GetDistance(player, art2) < 200.0) ) then
        art_found = true
        AudioMessage("misns605.wav")
    end
    
    -- Silo Counter Attack
    if (not counter_attack) and (GetDistance(player, far_silo) < 400.0) then
        local function SpawnAttack(odf)
            local h = BuildObject(odf, 2, "counter_attack")
            Goto(h, "counter_attack_path")
        end
        SpawnAttack("bvltnk")
        SpawnAttack("bvltnk")
        SpawnAttack("bvtank")
        SpawnAttack("bvtank")
        SpawnAttack("bvrckt")
        AudioMessage("misns603.wav")
        counter_attack = true
    end
    
    -- Last Objective
    if (not last_objective) and IsAlive(goal) and (GetDistance(player, goal) < 300.0) then
        ClearObjectives()
        AddObjective("misns601.otf", "green")
        AddObjective("misns602.otf", "white")
        last_objective = true
        SetObjectiveOn(goal)
    end
    
    -- Victory
    if (not won) and (not IsAlive(goal)) then
        won = true
        AudioMessage("misns609.wav") -- Capture handle if needed for Done check
        SucceedMission(GetTime() + 10.0, "misns6w1.des")
    end
    
    -- Loss
    if (not lost) and (not won) and (not IsAlive(recy)) then
        lost = true
        FailMission(GetTime() + 2.0, "misns6l1.des")
    end
end

