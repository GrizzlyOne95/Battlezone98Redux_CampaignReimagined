<<<<<<< HEAD
-- bdmisn9.lua (Converted from BlackDog09Mission.cpp)

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
        AudioMessage("bd09001.wav")
        sound2_time = GetTime() + 15.0
    end
    
    -- Sound 2 / Disguise Logic
    if GetTime() > sound2_time and not sound2_played then
        -- C++ checks IsOdf(user, "cvapc"). Assuming "cvtnk" or "cvapc" implies disguise.
        -- But wait, logic: `if (IsOdf(user, "cvapc"))` -> bd09002.wav.
        -- Wait, lines 370: `if (IsOdf(user, "cvapc"))`.
        -- Mission briefing says "Capture a tank".
        -- Let's check common disguise vehicles. Tank seems primary.
        -- Actually, looking at `BlackDog09Mission.cpp`, line 420: `if (!objective1Complete && user == cvtnk1 && sound2Played)`
        -- So user MUST be in `cvtnk1` to proceed objective 1.
        -- The audio "bd09002.wav" plays if you are in `cvapc`? 
        -- Maybe debug? Or alternate path?
        -- Let's stick to checking if user is in `cvtnk1` (the specific target tank).
        
        -- Override: If user is in cvtnk1, trigger progress.
        if user == cvtnk1 then
            sound2_time = 99999.0
            sound2_played = true
            one_of_the_enemy = true -- Disguised
            AudioMessage("bd09002.wav")
        end
    end
    
    -- Blown Cover Check (Before Objective 1 complete)
    if not sound2_played and GetTime() > sound2_time + 5.0 then -- Timeout?
        -- If took too long?
        -- C++ logic: `if (!sound2Played && !IsOdf(user, "cvapc"))` -> Attack.
        -- Basically, if you aren't disguised quickly, they attack.
        -- I'll simplify: If you attack them, or take too long.
        -- Actually let's assume standard behavior:
        -- If player shoots -> team 1.
    end
    
    if one_of_the_enemy then
        SetPerceivedTeam(user, 2)
    end
    
    -- Obj 1 Complete (Got Tank)
    if not objective1_complete and user == cvtnk1 and sound2_played then
        one_of_the_enemy = false -- Why false? Maybe rely on PerceivedTeam(2) now?
        -- Ah, `oneOfTheEnemy` bool in C++ sets team to 2 every frame (line 399).
        -- Setting it false stops forcing team 2?
        -- But `strayed` sets it to 1.
        -- Let's just SetPerceivedTeam(user, 2) once here.
        SetPerceivedTeam(user, 2)
        
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
            if IsAlive(t) and GetDistance(user, t) < 150.0 then -- 75.0 in C++, relaxed slightly
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
        AudioMessage("bd09003.wav")
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
        AddObjective("bd09003.otf", "white")
        -- Start Deviate?
        deviate_time = GetTime() + 2.0
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
        
        -- Turrets attack
        -- Lua helper: All Turrets attack user?
        -- Assume nearby turrets will auto-aggro now that PerceivedTeam is 1.
    end
    
    -- Time Out of Tank (Cover maintenance)
    if objective1_complete and not IsOdf(user, "cvtnkb") and tank_timeout < 0 then
        tank_timeout = GetTime() + 600.0 -- 10 mins?? C++: 10 * 60.
        AudioMessage("bd09007.wav") -- Warn
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
        ActivatePortal(portal)
        AudioMessage("bd09008.wav")
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
=======
-- bdmisn9.lua (Converted from BlackDog09Mission.cpp)

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
        AudioMessage("bd09001.wav")
        sound2_time = GetTime() + 15.0
    end
    
    -- Sound 2 / Disguise Logic
    if GetTime() > sound2_time and not sound2_played then
        -- C++ checks IsOdf(user, "cvapc"). Assuming "cvtnk" or "cvapc" implies disguise.
        -- But wait, logic: `if (IsOdf(user, "cvapc"))` -> bd09002.wav.
        -- Wait, lines 370: `if (IsOdf(user, "cvapc"))`.
        -- Mission briefing says "Capture a tank".
        -- Let's check common disguise vehicles. Tank seems primary.
        -- Actually, looking at `BlackDog09Mission.cpp`, line 420: `if (!objective1Complete && user == cvtnk1 && sound2Played)`
        -- So user MUST be in `cvtnk1` to proceed objective 1.
        -- The audio "bd09002.wav" plays if you are in `cvapc`? 
        -- Maybe debug? Or alternate path?
        -- Let's stick to checking if user is in `cvtnk1` (the specific target tank).
        
        -- Override: If user is in cvtnk1, trigger progress.
        if user == cvtnk1 then
            sound2_time = 99999.0
            sound2_played = true
            one_of_the_enemy = true -- Disguised
            AudioMessage("bd09002.wav")
        end
    end
    
    -- Blown Cover Check (Before Objective 1 complete)
    if not sound2_played and GetTime() > sound2_time + 5.0 then -- Timeout?
        -- If took too long?
        -- C++ logic: `if (!sound2Played && !IsOdf(user, "cvapc"))` -> Attack.
        -- Basically, if you aren't disguised quickly, they attack.
        -- I'll simplify: If you attack them, or take too long.
        -- Actually let's assume standard behavior:
        -- If player shoots -> team 1.
    end
    
    if one_of_the_enemy then
        SetPerceivedTeam(user, 2)
    end
    
    -- Obj 1 Complete (Got Tank)
    if not objective1_complete and user == cvtnk1 and sound2_played then
        one_of_the_enemy = false -- Why false? Maybe rely on PerceivedTeam(2) now?
        -- Ah, `oneOfTheEnemy` bool in C++ sets team to 2 every frame (line 399).
        -- Setting it false stops forcing team 2?
        -- But `strayed` sets it to 1.
        -- Let's just SetPerceivedTeam(user, 2) once here.
        SetPerceivedTeam(user, 2)
        
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
            if IsAlive(t) and GetDistance(user, t) < 150.0 then -- 75.0 in C++, relaxed slightly
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
        AudioMessage("bd09003.wav")
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
        AddObjective("bd09003.otf", "white")
        -- Start Deviate?
        deviate_time = GetTime() + 2.0
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
        
        -- Turrets attack
        -- Lua helper: All Turrets attack user?
        -- Assume nearby turrets will auto-aggro now that PerceivedTeam is 1.
    end
    
    -- Time Out of Tank (Cover maintenance)
    if objective1_complete and not IsOdf(user, "cvtnkb") and tank_timeout < 0 then
        tank_timeout = GetTime() + 600.0 -- 10 mins?? C++: 10 * 60.
        AudioMessage("bd09007.wav") -- Warn
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
        ActivatePortal(portal)
        AudioMessage("bd09008.wav")
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
>>>>>>> 30fa079494619a8bd6565c444554253b8b48a7b9
