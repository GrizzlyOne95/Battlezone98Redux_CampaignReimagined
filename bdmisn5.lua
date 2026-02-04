-- bdmisn5.lua (Converted from BlackDog05Mission.cpp)

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

-- Handles
local user, recycler, portal
local units = {} -- Main enemy tracking (approx 46 slots)
local quitters = {} -- 1..6

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

-- Restored Cut Content: Track built offensive units
function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then 
        aiCore.AddObject(h)
    elseif team == 1 then
        -- C++: if slot >= TEAM_SLOT_MIN_OFFENSE (bombers/tanks)
        -- Simplified Lua check:
        local odf = GetOdf(h)
        if IsOdf(h, "bvbomb") or IsOdf(h, "bvhraz") or IsOdf(h, "bvtank") or IsOdf(h, "bvmisl") or IsOdf(h, "bvwalk") then
            if num_bombers < 7 then
                num_bombers = num_bombers + 1
                if num_bombers >= 7 and not objective1_complete then
                    objective1_complete = true
                    ClearObjectives()
                    AddObjective("bd05001.otf", "green") -- "Production Complete"
                    -- StartCockpitTimer equivalent if needed (C++ sets timer to 2400s?)
                    -- "StartCockpitTimer(40 * 60, 60, 10)" -> 40 mins? That's huge. 
                    -- Maybe purely decorative or time limit? 
                    -- Let's ignore timer unless critical (commented out in C++ logic implies debugging context usually).
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
            AudioMessage("bd05001.wav")
            ResetObjectives()
            camera_ready = true
        end
        
        CameraPath("camera_start_arc", 3000, 2000, recycler)
        
        if CameraCancelled() then
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
    
    -- Retreat / Quitters
    -- Original logic: objective2Complete triggers retreat.
    -- Wait, C++ line 586: `if (objective2Complete && !quittersSpawned)`.
    -- So even if objective1 (production) isn't done, enemies might retreat if player killed everyone?
    -- BUT, Win condition (Line 666) requires both: `if (objective1Complete && objective2Complete ...)`
    -- So if we kill everyone but haven't built 7 bombers, we sit there?
    -- Yes. So we MUST build the bombers. My restoration is correct.
    
    if objective2_complete and not quitters_spawned then
        quitters[1] = BuildObject("cvtnk", 2, "quitters")
        quitters[2] = BuildObject("cvtnk", 2, "quitters")
        quitters[3] = BuildObject("cvwalk", 2, "quitters")
        quitters[4] = BuildObject("cvwalk", 2, "quitters")
        quitters[5] = BuildObject("cspilo", 2, "quitters")
        quitters[6] = BuildObject("cvltnk", 2, "quitters")
        
        for i=1,6 do Retreat(quitters[i], "portal_in", 1) end
        -- ActivatePortal(portal, true) 
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
            AudioMessage("bd05005.wav")
            quitter_cam_time = GetTime() + 15.0
            camera_ready = true
        end
        
        CameraPath("camera_retreat", 3000, 0, portal)
        
        if CameraCancelled() or GetTime() > quitter_cam_time then
            CameraFinish()
            camera_complete[2] = true
            camera_ready = false
            quitter_movie_done = true
        end
    end
    
    -- Victory
    if objective1_complete and objective2_complete and quitter_movie_done and not won and not lost then
        won = true
        AudioMessage("bd05006.wav")
        SucceedMission(GetTime() + 5.0, "bd05win.des")
    end
end
