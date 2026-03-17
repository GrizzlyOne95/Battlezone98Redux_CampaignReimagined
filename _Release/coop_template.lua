-- coop_template.lua
-- Authoritative Co-op Campaign Template for Battlezone 98 Redux
-- Designed to support up to 4 players with synchronized objectives and AI logic.

-- Compatibility and Library Setup
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
local exu = require("exu")
local aiCore = require("aiCore")

-- Mission State
local start_done = false
local players = {} -- [teamRef] = handle (Manual sync table)
local mission_timer = 0
local objective_step = 0

-- LOGIC GATE: Only the host handles world mutations (spawns, wave timings).
local function HostOnly(fn)
    if IsHost() then fn() end
end

-- SYNC HELPER: Engine bug workaround for GetPlayerHandle(team)
local function SyncPlayerHandles()
    for team = 1, 4 do
        local h = GetPlayerHandle(team) -- This might be null for clients
        if h and h > 0 then
            players[team] = h
        end
    end
    -- Future improvement: Use Send/Receive to broadcast player handles from host to clients
end

-- SYNC HELPER: Objective markers are local, must be called on all clients
local function SyncObjective(handle, state, name)
    SetObjectiveOn(handle)
    SetObjectiveName(handle, name or "Objective")
end

function Start()
    -- Enable modern QOL features
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(400) end
    end

    -- Initial Player Sync
    SyncPlayerHandles()
    start_done = false
end

function AddObject(h)
    -- Host only manages the AI core for consistency
    HostOnly(function()
        local team = GetTeamNum(h)
        if team ~= 1 then -- Assume team 1/2/3/4 are players in co-op?
             aiCore.AddObject(h)
        end
    end)
end

function Update()
    -- Maintain player handle references
    if GetTime() % 5.0 == 0 then SyncPlayerHandles() end
    
    -- Update AI Brain (Host Only)
    HostOnly(function()
        aiCore.Update()
    end)

    if not start_done then
        -- 1. Initialize Teams & Resources
        HostOnly(function()
            SetScrap(1, 20)
            SetPilot(1, 10)
        end)
        
        -- 2. Audio/Intro (All see/hear)
        AudioMessage("misn0101.wav") -- Placeholder intro
        
        start_done = true
    end

    -- MISSION FLOW (Authoritative)
    HostOnly(function()
        if objective_step == 0 then
             -- Example Trigger: Spawn enemy wave
             local h = BuildObject("svfigh", 2, "spawn_wave_1")
             if h then 
                SetLocal(h) -- CRITICAL: Make unit script-ready for network sync
                Attack(h, players[1] or GetPlayerHandle()) 
             end
             objective_step = 1
        end
    end)

    -- SHARED UI (Update on all machines)
    if objective_step == 1 and not objective_flag then
        ClearObjectives()
        AddObjective("Template Objective Activated", "white")
        objective_flag = true
    end
    
    -- CINEMATIC HANDLING Example
    -- if start_cinematic then
    --     CameraPath("my_cam_path", 1000, 2000, some_handle)
    -- end
end

-- DATA SYNC (Network Commands)
function Receive(id, type, val1, val2, str)
    -- Type 7: Custom Script Commands
    if type == 7 then
        if str == "START_CINEMATIC_1" then
            -- Example: Set a local flag to start playing camera path in Update()
            -- start_cinematic = true 
        end
    end
end

-- NETCODE REMINDERS (from ScriptingGuide.txt):
-- 1. SetLocal() is required after every lua BuildObject if you want clients to see it correctly.
-- 2. MakeExplosion() is 100% local (good for VFX, bad for synced damage).
-- 3. Pass variables via 'Send/Receive' if long-range state sync is needed.

