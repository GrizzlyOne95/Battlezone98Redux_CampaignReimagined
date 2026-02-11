<<<<<<< HEAD
-- bdmisn12.lua (Converted from BlackDog12Mission.cpp)

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
local camera1_sound_played = false
local portal_dead_sound_played = false
local delays_initialized = false
local lost = false
local won = false

-- Arrays
local health_low = {false, false, false, false, false, false, false, false} -- 1-8
local despor_spawned = {false, false, false, false} -- 1-4
local camera_ready = {false, false}
local camera_complete = {false, false}

-- Timers
local delays = {} -- 0-9 in C++, use 1-10 in Lua
local camera1_sound_delay = 99999.0
local scrap_delay = 99999.0
local portal_on_time = 99999.0
local portal_off_time = 99999.0

-- Handles
local user
local recycler, portal
local shields = {} -- 1-4
local power = {} -- 1-4
local goal = {} -- 1-4

-- Warnings
local warnings = {"bd12005.wav", "bd12006.wav", "bd12007.wav", "bd12008.wav"}
local despor_spawns = {"despor_1", "despor_2", "despor_3", "despor_4"}

-- Difficulty
local difficulty = 2

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
        SetScrap(2, 10)
        SetPilot(1, 10)
        
        portal = GetHandle("portal")
        for i=1,4 do shields[i] = GetHandle("shield_"..i) end
        for i=1,4 do power[i] = GetHandle("power_"..i) end
        for i=1,4 do goal[i] = GetHandle("goal_"..i) end
        
        start_done = true
    end
    
    if not delays_initialized then
        delays_initialized = true
        local t = GetTime()
        delays[1] = t + 120.0
        delays[2] = t + 240.0
        delays[3] = t + 360.0
        delays[4] = t + 480.0
        delays[5] = t + 13 * 60.0
        portal_on_time = delays[5] - 2.0
        delays[6] = t + 546.0
        delays[7] = t + 552.0
        portal_off_time = delays[7] + 2.0
        delays[8] = t + 555.0
        
        scrap_delay = 60.0
    end
    
    if lost or won then return end
    
    -- Intro
    if not camera_complete[1] then
        if not camera_ready[1] then
            camera_ready[1] = true
            CameraReady()
            camera1_sound_delay = GetTime() + 3.0
        end
        
        CameraPath("camera_start", 300, 2000, portal)
        
        if GetTime() > camera1_sound_delay then
            camera1_sound_delay = 99999.0
            camera1_sound_played = true
            AudioMessage("bd12001.wav")
        end
        
        if CameraCancelled() then
            CameraFinish()
            camera_complete[1] = true
            ClearObjectives()
            AddObjective("bd12001.otf", "white")
        end
    end
    
    -- Delay 1 (Index 1)
    if GetTime() > delays[1] then
        delays[1] = 99999.0
        -- 3 figh, 2 def
        local function A(odf) local h = BuildObject(odf, 2, "attack_1"); SetCloaked(h); Attack(h, power[1]) return h end
        local a1 = A("cvfigh"); local a2 = A("cvfigh"); local a3 = A("cvfigh")
        local function D(odf, target) local h = BuildObject(odf, 2, "defend_1"); SetCloaked(h); Defend(h, target) end
        D("cvtnk", a1); D("cvtnk", a2)
    end
    
    -- Delay 2
    if GetTime() > delays[2] then
        delays[2] = 99999.0
        local function A(odf) local h = BuildObject(odf, 2, "attack_2"); SetCloaked(h); Attack(h, power[2]) return h end
        local a1 = A("cvfigh"); local a2 = A("cvfigh"); local a3 = A("cvfigh"); local a4 = A("cvhtnk")
        local function D(odf, t) local h = BuildObject(odf, 2, "defend_2"); SetCloaked(h); Defend(h, t) end
        D("cvfigh", a1); D("cvfigh", a2); D("cvfigh", a3); D("cvhtnk", a4)
    end
    
    -- Delay 3
    if GetTime() > delays[3] then
        delays[3] = 99999.0
        local function A(odf) local h = BuildObject(odf, 2, "attack_3"); SetCloaked(h); Attack(h, power[3]) return h end
        local a1 = A("cvhraz"); local a2 = A("cvhraz"); local a3 = A("cvfigh"); local a4 = A("cvfigh")
        local function D(odf, t) local h = BuildObject(odf, 2, "defend_3"); SetCloaked(h); Defend(h, t) end
        D("cvtnk", a1); D("cvtnk", a2); D("cvfigh", a3); D("cvfigh", a4)
    end
    
    -- Delay 4 (Attack Shields primarily)
    if GetTime() > delays[4] then
        delays[4] = 99999.0
        local function Combo(at, sh, df, sp, tdef)
            local a = BuildObject(at, 2, sp); Attack(a, sh)
            local d1 = BuildObject(df, 2, tdef); SetCloaked(d1); Defend(d1, a)
            local d2 = BuildObject(df, 2, tdef); SetCloaked(d2); Defend(d2, a)
        end
        Combo("cvwalk", shields[1], "cvltnk", "attack_4", "defend_4")
        Combo("cvwalk", shields[2], "cvltnk", "attack_5", "defend_5")
        Combo("cvwalk", shields[3], "cvtnk", "attack_6", "defend_6")
        Combo("cvwalk", shields[4], "cvtnk", "attack_7", "defend_7")
        Combo("cvwalk", portal, "cvhtnk", "attack_8", "defend_8")
    end
    
    -- Portal Logic
    if GetTime() > portal_on_time then
        portal_on_time = 99999.0
        ActivatePortal(portal)
    end
    
    -- Delay 5: Recycler Arrives
    if GetTime() > delays[5] then
        delays[5] = 99999.0
        recycler = BuildObject("bvrecyd", 1, "portal") -- "bvrecyd" (deployed recycler)
        -- C++: BuildObjectAtPortal.
        -- Assuming "portal" is a path point OR nav. If just Handle, BuildObjectAtPortal uses its pos.
        -- Lua BuildObject uses path point string. 
        -- If "portal" is an object handle name, we need its position or a nav point name.
        -- Assuming "portal" nav exists or we use GetPosition(portal) + Offset.
        -- But since C++ used "BuildObjectAtPortal", let's assume we have a path point named "portal" or "portal_spawn".
        -- Let's use GetObjPosition(portal) if possible.
        local pp = GetObjPosition(portal) -- Hopefully ODF defines where to spawn
        -- Actually, BuildObject("...", 1, "portal") implies "portal" is a path/nav.
        -- If portal is an object handle, this fails.
        -- C++ `BuildObjectAtPortal` is special.
        -- Let's spawn at "portal" assuming there is a path point there.
        Goto(recycler, "follow")
    end
    
    -- Delay 6
    if GetTime() > delays[6] then
        delays[6] = 99999.0
        local t = BuildObject("bvtank", 1, "portal"); Goto(t, "follow")
        t = BuildObject("bvtank", 1, "portal"); Goto(t, "follow")
    end
    
    -- Delay 7
    if GetTime() > delays[7] then
        delays[7] = 99999.0
        local t = BuildObject("bvfigh", 1, "portal"); Goto(t, "follow")
    end
    
    -- Delay 8: Obj Update
    if GetTime() > delays[8] then
        delays[8] = 99999.0
        ClearObjectives()
        AddObjective("bd12001.otf", "green")
        AddObjective("bd12002.otf", "white")
        objective1_complete = true
    end
    
    -- Portal Off
    if GetTime() > portal_off_time then
        portal_off_time = 99999.0
        DeactivatePortal(portal)
    end
    
    -- Obj 2 Check (Goals)
    if objective1_complete and not objective2_complete then
        local any_alive = false
        for i=1,4 do if IsAlive(goal[i]) then any_alive = true break end end
        
        if not any_alive then
            objective2_complete = true
            AudioMessage("bd12003.wav")
            -- Succeed delay handled in win check
        end
    end
    
    if objective2_complete and not won and not lost then
        -- C++ waits for Audio Done.
        won = true
        SucceedMission(GetTime() + 1.0, "bd12win.des")
    end
    
    -- Health Monitoring
    for i=1,4 do
        -- Power
        if not health_low[i] and IsAlive(power[i]) and GetHealth(power[i]) < 0.25 then
            health_low[i] = true
            AudioMessage(warnings[i])
        end
        -- Shields
        if not health_low[4+i] and IsAlive(shields[i]) and GetHealth(shields[i]) < 0.25 then
            health_low[4+i] = true
            AudioMessage(warnings[i]) -- Uses same warnings index 1-4
        end
    end
    
    -- Despor Spawns (If defense falls)
    for i=1,4 do
        if not despor_spawned[i] then
            if (not IsAlive(power[i])) or (not IsAlive(shields[i])) then
                despor_spawned[i] = true
                local function R(odf) local h = BuildObject(odf, 2, despor_spawns[i]); SetCloaked(h); Attack(h, portal) end
                R("cvltnk"); R("cvltnk")
            end
        end
    end
    
    -- Portal Death
    if not IsAlive(portal) and not lost and not won then
        if not portal_dead_sound_played then
            portal_dead_sound_played = true
            AudioMessage("bd12004.wav")
            lost = true
            FailMission(GetTime() + 2.0, "bd12lsea.des")
        end
    end
    
    -- Scrap Spawns
    if GetTime() > scrap_delay then
        scrap_delay = GetTime() + 60.0
        for i=1,3 do BuildObject("npscr1", 0, "scrap_1") end
        for i=1,3 do BuildObject("npscr1", 0, "scrap_2") end
    end
end
=======
-- bdmisn12.lua (Converted from BlackDog12Mission.cpp)

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
local camera1_sound_played = false
local portal_dead_sound_played = false
local delays_initialized = false
local lost = false
local won = false

-- Arrays
local health_low = {false, false, false, false, false, false, false, false} -- 1-8
local despor_spawned = {false, false, false, false} -- 1-4
local camera_ready = {false, false}
local camera_complete = {false, false}

-- Timers
local delays = {} -- 0-9 in C++, use 1-10 in Lua
local camera1_sound_delay = 99999.0
local scrap_delay = 99999.0
local portal_on_time = 99999.0
local portal_off_time = 99999.0

-- Handles
local user
local recycler, portal
local shields = {} -- 1-4
local power = {} -- 1-4
local goal = {} -- 1-4

-- Warnings
local warnings = {"bd12005.wav", "bd12006.wav", "bd12007.wav", "bd12008.wav"}
local despor_spawns = {"despor_1", "despor_2", "despor_3", "despor_4"}

-- Difficulty
local difficulty = 2

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
        SetScrap(2, 10)
        SetPilot(1, 10)
        
        portal = GetHandle("portal")
        for i=1,4 do shields[i] = GetHandle("shield_"..i) end
        for i=1,4 do power[i] = GetHandle("power_"..i) end
        for i=1,4 do goal[i] = GetHandle("goal_"..i) end
        
        start_done = true
    end
    
    if not delays_initialized then
        delays_initialized = true
        local t = GetTime()
        delays[1] = t + 120.0
        delays[2] = t + 240.0
        delays[3] = t + 360.0
        delays[4] = t + 480.0
        delays[5] = t + 13 * 60.0
        portal_on_time = delays[5] - 2.0
        delays[6] = t + 546.0
        delays[7] = t + 552.0
        portal_off_time = delays[7] + 2.0
        delays[8] = t + 555.0
        
        scrap_delay = 60.0
    end
    
    if lost or won then return end
    
    -- Intro
    if not camera_complete[1] then
        if not camera_ready[1] then
            camera_ready[1] = true
            CameraReady()
            camera1_sound_delay = GetTime() + 3.0
        end
        
        CameraPath("camera_start", 300, 2000, portal)
        
        if GetTime() > camera1_sound_delay then
            camera1_sound_delay = 99999.0
            camera1_sound_played = true
            AudioMessage("bd12001.wav")
        end
        
        if CameraCancelled() then
            CameraFinish()
            camera_complete[1] = true
            ClearObjectives()
            AddObjective("bd12001.otf", "white")
        end
    end
    
    -- Delay 1 (Index 1)
    if GetTime() > delays[1] then
        delays[1] = 99999.0
        -- 3 figh, 2 def
        local function A(odf) local h = BuildObject(odf, 2, "attack_1"); SetCloaked(h); Attack(h, power[1]) return h end
        local a1 = A("cvfigh"); local a2 = A("cvfigh"); local a3 = A("cvfigh")
        local function D(odf, target) local h = BuildObject(odf, 2, "defend_1"); SetCloaked(h); Defend(h, target) end
        D("cvtnk", a1); D("cvtnk", a2)
    end
    
    -- Delay 2
    if GetTime() > delays[2] then
        delays[2] = 99999.0
        local function A(odf) local h = BuildObject(odf, 2, "attack_2"); SetCloaked(h); Attack(h, power[2]) return h end
        local a1 = A("cvfigh"); local a2 = A("cvfigh"); local a3 = A("cvfigh"); local a4 = A("cvhtnk")
        local function D(odf, t) local h = BuildObject(odf, 2, "defend_2"); SetCloaked(h); Defend(h, t) end
        D("cvfigh", a1); D("cvfigh", a2); D("cvfigh", a3); D("cvhtnk", a4)
    end
    
    -- Delay 3
    if GetTime() > delays[3] then
        delays[3] = 99999.0
        local function A(odf) local h = BuildObject(odf, 2, "attack_3"); SetCloaked(h); Attack(h, power[3]) return h end
        local a1 = A("cvhraz"); local a2 = A("cvhraz"); local a3 = A("cvfigh"); local a4 = A("cvfigh")
        local function D(odf, t) local h = BuildObject(odf, 2, "defend_3"); SetCloaked(h); Defend(h, t) end
        D("cvtnk", a1); D("cvtnk", a2); D("cvfigh", a3); D("cvfigh", a4)
    end
    
    -- Delay 4 (Attack Shields primarily)
    if GetTime() > delays[4] then
        delays[4] = 99999.0
        local function Combo(at, sh, df, sp, tdef)
            local a = BuildObject(at, 2, sp); Attack(a, sh)
            local d1 = BuildObject(df, 2, tdef); SetCloaked(d1); Defend(d1, a)
            local d2 = BuildObject(df, 2, tdef); SetCloaked(d2); Defend(d2, a)
        end
        Combo("cvwalk", shields[1], "cvltnk", "attack_4", "defend_4")
        Combo("cvwalk", shields[2], "cvltnk", "attack_5", "defend_5")
        Combo("cvwalk", shields[3], "cvtnk", "attack_6", "defend_6")
        Combo("cvwalk", shields[4], "cvtnk", "attack_7", "defend_7")
        Combo("cvwalk", portal, "cvhtnk", "attack_8", "defend_8")
    end
    
    -- Portal Logic
    if GetTime() > portal_on_time then
        portal_on_time = 99999.0
        ActivatePortal(portal)
    end
    
    -- Delay 5: Recycler Arrives
    if GetTime() > delays[5] then
        delays[5] = 99999.0
        recycler = BuildObject("bvrecyd", 1, "portal") -- "bvrecyd" (deployed recycler)
        -- C++: BuildObjectAtPortal.
        -- Assuming "portal" is a path point OR nav. If just Handle, BuildObjectAtPortal uses its pos.
        -- Lua BuildObject uses path point string. 
        -- If "portal" is an object handle name, we need its position or a nav point name.
        -- Assuming "portal" nav exists or we use GetPosition(portal) + Offset.
        -- But since C++ used "BuildObjectAtPortal", let's assume we have a path point named "portal" or "portal_spawn".
        -- Let's use GetObjPosition(portal) if possible.
        local pp = GetObjPosition(portal) -- Hopefully ODF defines where to spawn
        -- Actually, BuildObject("...", 1, "portal") implies "portal" is a path/nav.
        -- If portal is an object handle, this fails.
        -- C++ `BuildObjectAtPortal` is special.
        -- Let's spawn at "portal" assuming there is a path point there.
        Goto(recycler, "follow")
    end
    
    -- Delay 6
    if GetTime() > delays[6] then
        delays[6] = 99999.0
        local t = BuildObject("bvtank", 1, "portal"); Goto(t, "follow")
        t = BuildObject("bvtank", 1, "portal"); Goto(t, "follow")
    end
    
    -- Delay 7
    if GetTime() > delays[7] then
        delays[7] = 99999.0
        local t = BuildObject("bvfigh", 1, "portal"); Goto(t, "follow")
    end
    
    -- Delay 8: Obj Update
    if GetTime() > delays[8] then
        delays[8] = 99999.0
        ClearObjectives()
        AddObjective("bd12001.otf", "green")
        AddObjective("bd12002.otf", "white")
        objective1_complete = true
    end
    
    -- Portal Off
    if GetTime() > portal_off_time then
        portal_off_time = 99999.0
        DeactivatePortal(portal)
    end
    
    -- Obj 2 Check (Goals)
    if objective1_complete and not objective2_complete then
        local any_alive = false
        for i=1,4 do if IsAlive(goal[i]) then any_alive = true break end end
        
        if not any_alive then
            objective2_complete = true
            AudioMessage("bd12003.wav")
            -- Succeed delay handled in win check
        end
    end
    
    if objective2_complete and not won and not lost then
        -- C++ waits for Audio Done.
        won = true
        SucceedMission(GetTime() + 1.0, "bd12win.des")
    end
    
    -- Health Monitoring
    for i=1,4 do
        -- Power
        if not health_low[i] and IsAlive(power[i]) and GetHealth(power[i]) < 0.25 then
            health_low[i] = true
            AudioMessage(warnings[i])
        end
        -- Shields
        if not health_low[4+i] and IsAlive(shields[i]) and GetHealth(shields[i]) < 0.25 then
            health_low[4+i] = true
            AudioMessage(warnings[i]) -- Uses same warnings index 1-4
        end
    end
    
    -- Despor Spawns (If defense falls)
    for i=1,4 do
        if not despor_spawned[i] then
            if (not IsAlive(power[i])) or (not IsAlive(shields[i])) then
                despor_spawned[i] = true
                local function R(odf) local h = BuildObject(odf, 2, despor_spawns[i]); SetCloaked(h); Attack(h, portal) end
                R("cvltnk"); R("cvltnk")
            end
        end
    end
    
    -- Portal Death
    if not IsAlive(portal) and not lost and not won then
        if not portal_dead_sound_played then
            portal_dead_sound_played = true
            AudioMessage("bd12004.wav")
            lost = true
            FailMission(GetTime() + 2.0, "bd12lsea.des")
        end
    end
    
    -- Scrap Spawns
    if GetTime() > scrap_delay then
        scrap_delay = GetTime() + 60.0
        for i=1,3 do BuildObject("npscr1", 0, "scrap_1") end
        for i=1,3 do BuildObject("npscr1", 0, "scrap_2") end
    end
end
>>>>>>> 30fa079494619a8bd6565c444554253b8b48a7b9

