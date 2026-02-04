-- bdmisn10.lua (Converted from BlackDog10Mission.cpp)

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
    local caa = aiCore.AddTeam(2, aiCore.Factions.CAA) 
    
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
local camera_ready = {false, false, false}
local camera_complete = {false, false, false}
local arrived = false
local apc_spawned = false
local recycler_spawned = false
local defences_spawned = {false, false, false, false}
local patrols_spawned = {false, false, false, false}

-- Timers
local nav_delay = 99999.0
local apc_delay = 99999.0
local apc_camera_timeout = 99999.0
local camera_time = 99999.0

-- Handles
local user
local destroy = {} -- 1..6
local apc, recycler

-- Logic Data
local defences = {"defend_a", "defend_b", "defend_c", "defend_d"}
local patrols = {"patrol_a", "patrol_b", "patrol_c", "patrol_d"}

local defence_units = {
    {"cvtnk", "cvtnk", "cvltnk", "cvltnk", "cvfigh", "cvfigh"},
    {"cvfigh", "cvfigh", "cvfigh", "cvwalk", "cvhtnk", "cvtnk"},
    {"cvtnk", "cvtnk", "cvtnk", "cvfigh", "cvfigh", "cvwalk"},
    {"cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvtnk", "cvtnk", "cvtnk", "cvwalk"}
}

local patrol_units = {
    {"cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvtnk"},
    {"cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvtnk"},
    {"cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvtnk"},
    {"cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvtnk"}
}

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

-- Ambush spawning helper
local function CheckAmbush(spawn_spot, spawn_idx, spawned_table, unit_list)
    if spawned_table[spawn_idx] then return end
    
    -- C++: GetNearestUnitOnTeam(spawn_spot, 0, 1) < 400.0
    -- Simplified: Player near spot?
    if GetDistance(user, spawn_spot) < 400.0 then
        spawned_table[spawn_idx] = true
        for _, odf in pairs(unit_list) do
            local h = BuildObject(odf, 2, spawn_spot)
            Hunt(h)
        end
    end
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
        SetScrap(1, 100)
        SetScrap(2, 0)
        SetPilot(1, 10)
        
        ClearObjectives()
        AddObjective("bd10001.otf", "white")
        
        for i=1,6 do destroy[i] = GetHandle("destroy_"..i) end
        
        start_done = true
    end
    
    -- Check Ambushes
    for i=1,4 do CheckAmbush(defences[i], i, defences_spawned, defence_units[i]) end
    for i=1,4 do CheckAmbush(patrols[i], i, patrols_spawned, patrol_units[i]) end
    
    -- Intro
    if not camera_complete[1] then
        if not camera_ready[1] then
            camera_ready[1] = true
            CameraReady()
            AudioMessage("bd10001.wav")
        end
        
        if not arrived then
            CameraPath("camera_start", 3000, 2000, destroy[3])
            -- Logic to set arrived?
            -- Timer workaround since we don't have accurate Path completion feedback in base Lua
            if camera_time == 99999.0 then camera_time = GetTime() + 10.0 end
        end
        
        if GetTime() > camera_time then arrived = true end
        
        if (arrived and GetTime() > camera_time + 2.0) or CameraCancelled() then
            CameraFinish()
            camera_complete[1] = true
        end
    end
    
    -- Objectives
    if not objective1_complete then
        local all_dead = true
        for i=1,6 do
            if IsAlive(destroy[i]) then all_dead = false; break end
        end
        
        if all_dead then
            objective1_complete = true
            nav_delay = GetTime() + 10.0
        end
    end
    
    if objective1_complete and GetTime() > nav_delay then
        nav_delay = 99999.0
        BuildObject("apcamr", 1, "navcam_end")
        AudioMessage("bd10002.wav")
        apc_delay = GetTime() + 5.0 -- Wait for audio approx
    end
    
    if objective1_complete and GetTime() > apc_delay then
        apc_delay = 99999.0
        
        apc_spawned = true
        apc = BuildObject("bvapc", 1, "apc")
        Goto(apc, "apc_path", 1)
        
        BuildObject("cbport", 0, "portal")
    end
    
    -- Arrival Cinematic
    if apc_spawned and not camera_complete[2] then
        if not camera_ready[2] then
            camera_ready[2] = true
            CameraReady()
            apc_camera_timeout = GetTime() + 7.0
        end
        
        CameraPath("camera_apc", 30, 200, apc)
        
        if GetTime() > apc_camera_timeout or CameraCancelled() then
            CameraFinish()
            camera_complete[2] = true
        end
    end
    
    if camera_complete[2] and not recycler_spawned then
        recycler_spawned = true
        recycler = BuildObject("bvrecy", 1, "recycler")
        Goto(recycler, "recycler_path", 1)
        
        -- Escorts
        for i=1,6 do
            local h = BuildObject("cvtnka", 1, "capture")
            SetIndependence(h, 0)
            Follow(h, recycler, 1)
        end
    end
    
    -- Win
    if recycler_spawned and not camera_complete[3] then
        if not camera_ready[3] then
            camera_ready[3] = true
            CameraReady()
            AudioMessage("bd10003.wav")
            arrived = false
            camera_time = GetTime() + 10.0
        end
        
        if not arrived then
            CameraPath("camera_end", 30, 200, recycler)
            -- Assuming arrived logic handled by engine or time
        end
        
        if (GetTime() > camera_time) or CameraCancelled() then
            camera_complete[3] = true
            SucceedMission(GetTime() + 1.0, "bd10win.des")
        end
    end
end
