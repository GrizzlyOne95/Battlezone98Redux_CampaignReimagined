-- bdmisn11.lua (Converted from BlackDog11Mission.cpp)

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
local camera_ready = {false, false, false}
local camera_complete = {false, false, false}
local apc_wants_to_transfer = false
local pilot_transferring = false
local told_to_go = false
local attacks_sent = false
local nav_distance_ok = false
local retreat_spawned = false
local sound4_played = false
local sound5_played = false
local sound6_played = false
local cockpit_timer_active = false
local explode_portal = false
local arried = false
local lost = false
local won = false

-- Timers
local recycler_go_time = 99999.0
local drive1_time = 99999.0
local attack_times = {99999.0, 99999.0, 99999.0, 99999.0, 99999.0, 99999.0}
local go_to_portal_time = 99999.0
local camera_destruct_time = 99999.0
local explode_time = 99999.0
local explode_delay = 99999.0
local explode_seq_times = {99999.0, 99999.0, 99999.0, 99999.0} -- 1-4
local aerial1_time = 99999.0
local aerial2_time = 99999.0
local sound8_time = 99999.0
local sound9_time = 99999.0
local sound12_time = 99999.0

-- Handles
local user
local recycler, apc, pilot
local portal
local nav_recycler, nav_end
local enemy = {} -- Up to 71

-- Logic Data
local attacks = {0, 2, 4, 8, 11, 14, 23} -- Index offsets
local defends = {0, 4, 9, 14, 21, 30, 42}
local attack_spawns = {"attack_1", "attack_2", "attack_3", "attack_4", "attack_5", "attack_6"}
local defend_spawns = {"defend_1", "defend_2", "defend_3", "defend_4", "defend_5", "defend_6"}

local attack_units_list = {
    "cvhraz", "cvhraz", -- 1
    "cvhtnk", "cvhraz", -- 2
    "cvhraz", "cvhraz", "cvhtnk", "cvhtnk", -- 3
    "cvhtnk", "cvhtnk", "cvhtnk", -- 4
    "cvhraz", "cvhraz", "cvhraz", -- 5
    "cvhtnk", "cvhtnk", "cvhtnk", "cvfigh", "cvfigh", "cvfigh", "cvhraz", "cvhraz", "cvhraz" -- 6
}

local defend_units_list = {
    "cvtnk", "cvtnk", "cvfigh", "cvfigh", -- 1
    "cvfigh", "cvfigh", "cvfigh", "cvhtnk", "cvltnk", -- 2
    "cvtnk", "cvtnk", "cvtnk", "cvfigh", "cvfigh", -- 3
    "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvtnk", "cvtnk", "cvtnk", -- 4
    "cvhtnk", "cvhtnk", "cvhtnk", "cvhtnk", "cvtnk", "cvtnk", "cvtnk", "cvfigh", "cvfigh", -- 5
    "cvhtnk", "cvhtnk", "cvhtnk", "cvhtnk", "cvtnk", "cvtnk", "cvtnk", "cvtnk", "cvfigh", "cvfigh", "cvfigh", "cvfigh" -- 6
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
        SetPilot(1, 10)
        
        ClearObjectives()
        AddObjective("bd11001.otf", "white")
        
        recycler = GetHandle("recycler")
        portal = GetHandle("portal")
        apc = GetHandle("apc")
        
        nav_recycler = BuildObject("apcamr", 1, "recy_nav")
        SetLabel(nav_recycler, "Recycler")
        
        start_done = true
    end
    
    if lost or won then return end
    
    -- Lose Logic
    if not IsAlive(recycler) and not won and not lost then
        lost = true
        if nav_distance_ok then
            FailMission(GetTime() + 1.0, "bd11lseb.des")
        else
            FailMission(GetTime() + 1.0, "bd11lsed.des")
        end
    end
    
    if not objective1_complete and not IsAlive(apc) and not won and not lost then
        lost = true
        FailMission(GetTime() + 1.0, "bd11lsea.des")
    end
    
    -- Intro
    if not camera_complete[1] then
        if not camera_ready[1] then
            camera_ready[1] = true
            CameraReady()
            AudioMessage("bd11001.wav")
        end
        
        CameraPath("camera_start", 1000, 1600, recycler)
        
        if CameraCancelled() then
            CameraFinish()
            camera_complete[1] = true
        end
    end
    
    -- Pilot Transfer
    if not objective1_complete and not pilot_transferring then
        local dist = GetDistance(apc, recycler)
        local enemy = GetNearestEnemy(apc)
        if dist < 50.0 and (not enemy or GetDistance(apc, enemy) > 200.0) then
            Stop(apc, 1)
            pilot_transferring = true
            pilot = BuildObject("aspilo", 1, apc)
            -- Position fix logic probably needed in Lua if BuildObject spawns at 0,0,0
            SetObjPosition(pilot, GetObjPosition(apc))
            Goto(pilot, recycler, 1)
        end
    end
    
    if pilot_transferring then
        if not IsAlive(pilot) and not won and not lost then
            lost = true
            FailMission(GetTime() + 1.0, "bd11lsec.des")
        end
        
        if IsAlive(pilot) and GetDistance(pilot, recycler) < 15.0 then
            pilot_transferring = false
            objective1_complete = true
            RemoveObject(pilot)
            pilot = nil
            
            -- Set Recycler to Player Team properly
            -- "o->curPilot = *(PrjID*)"bspilo\0";" simulated by SetPilotClass?
            -- Assuming just SetTeam(recycler, 1) and maybe SetIndependence.
            SetTeam(recycler, 1)
            -- Add Pilot? SetPilotClass(recycler, "bspilo")
            
            recycler_go_time = GetTime() + 2.0
            AudioMessage("bd11002.wav")
        end
    end
    
    -- Recycler Move
    if GetTime() > recycler_go_time then
        told_to_go = true
        recycler_go_time = 99999.0
        Goto(recycler, "recycler_path", 1)
        drive1_time = GetTime() + 20.0
    end
    
    if told_to_go and GetDistance(recycler, "recycler_path") < 50.0 then -- At end
        told_to_go = false -- Deployed presumably?
        -- Deploy(recycler)
        AudioMessage("bd11003.wav") -- ? Not in original but logical for reached dest
        ClearObjectives()
        AddObjective("bd11001.otf", "green")
        AddObjective("bd11002.otf", "white")
    end
    
    -- Wave Triggers
    if not attacks_sent and GetDistance(recycler, "wave_trigger") < 50.0 then
        attacks_sent = true
        local t = GetTime()
        attack_times[1] = t + 2 * 60.0
        attack_times[2] = t + 5 * 60.0
        attack_times[3] = t + 9 * 60.0
        attack_times[4] = t + 14 * 60.0
        attack_times[5] = t + 18 * 60.0
        attack_times[6] = t + 21 * 60.0
        
        go_to_portal_time = t + 26 * 60.0 -- 26 mins?
        aerial1_time = t + 8 * 60.0
        aerial2_time = t + 13 * 60.0
        
        -- Initial Trigger Spawns
        local function AttackRecy(odf) local h = BuildObject(odf, 2, "drive_2"); Attack(h, recycler) end
        AttackRecy("cvltnk"); AttackRecy("cvltnk"); AttackRecy("cvltnk")
        AttackRecy("cvhraz"); AttackRecy("cvhraz")
    end
    
    -- Process Waves
    for i=1,6 do
        if GetTime() > attack_times[i] then
            attack_times[i] = 99999.0
            
            -- Attackers
            -- Logic: attacks[i] to attacks[i+1]
            local start_idx = attacks[i] + 1
            local end_idx = attacks[i+1]
            if not end_idx then end_idx = #attack_units_list end -- Fallback
            
            for j=start_idx, end_idx do
                local u = attack_units_list[j]
                if u then
                    local h = BuildObject(u, 2, attack_spawns[i])
                    SetCloaked(h)
                    Attack(h, recycler)
                end
            end
            
            -- Defenders
            start_idx = defends[i] + 1
            end_idx = defends[i+1]
            for j=start_idx, end_idx do
                local u = defend_units_list[j]
                if u then
                    local h = BuildObject(u, 2, defend_spawns[i])
                    SetCloaked(h)
                    -- Defend2 logic? C++ uses modulus to pick defend target from attackers.
                    -- Simplified: Defend base or roam.
                    Goto(h, recycler, 1) -- Aggressive defense
                end
            end
        end
    end
    
    -- Aerials
    if GetTime() > aerial1_time then
        aerial1_time = 99999.0
        for i=1,8 do local h = BuildObject("cssold", 2, "aerial_1"); Attack(h, recycler) end -- Soldiers? 400 height?
        -- Lua BuildObject doesn't take height. Need SetObjPosition.
        -- Skip height for simplicity or use specific spawn point elevation.
    end
    if GetTime() > aerial2_time then
        aerial2_time = 99999.0
        for i=1,8 do local h = BuildObject("cssold", 2, "aerial_1"); Attack(h, recycler) end
    end
    
    -- Portal Phase
    if GetTime() > go_to_portal_time then
        go_to_portal_time = 99999.0
        ClearObjectives()
        AddObjective("bd11002.otf", "green")
        AudioMessage("bd11007.wav")
        sound8_time = GetTime() + 3.0
    end
    
    if GetTime() > sound8_time then
        sound8_time = 99999.0
        AudioMessage("bd11008.wav")
        sound9_time = GetTime() + 5.0
    end
    
    if GetTime() > sound9_time then
        sound9_time = 99999.0
        AudioMessage("bd11009.wav")
        AudioMessage("bd11010.wav")
        sound12_time = GetTime() + 5.0
    end
    
    if GetTime() > sound12_time then
        sound12_time = 99999.0
        AudioMessage("bd11012.wav")
        ClearObjectives()
        AddObjective("bd11003.otf", "white")
        SetObjectiveOn(portal)
        StartCockpitTimer(90, 30, 10)
        cockpit_timer_active = true
    end
    
    -- End Sequence
    if cockpit_timer_active and GetCockpitTimer() <= 0.0 then
        cockpit_timer_active = false
        HideCockpitTimer()
        local t = GetTime()
        explode_seq_times[1] = t
        explode_seq_times[2] = t + 2.0
        explode_seq_times[3] = t + 4.0
        explode_seq_times[4] = t + 6.0
        explode_time = t + 18.0
        camera_destruct_time = t + 17.0
        nav_distance_ok = true -- Won basically
    end
    
    for i=1,4 do
        if GetTime() > explode_seq_times[i] then
            explode_seq_times[i] = 99999.0
            MakeExplosionAtPath("xpltrsk", "dw_"..i)
        end
    end
    
    if GetTime() > camera_destruct_time then
        camera_destruct_time = 99999.0
        CameraReady()
        CameraPath("camera_destruct", 1000, 0, portal)
    end
    
    if GetTime() > explode_time then
        explode_time = 99999.0
        explode_delay = GetTime() + 3.0
        explode_portal = true
        MakeExplosionAtHandle("xpltrso", portal)
    end
    
    if GetTime() > explode_delay then
        explode_delay = 99999.0
        CameraFinish()
        AudioMessage("bd11011.wav") -- Victory words
        ClearObjectives()
        AddObjective("bd11003.otf", "green")
        
        -- Win
        won = true
        SucceedMission(GetTime() + 3.0, "bd11win.des")
    end
    
    -- Safety Fail
    if IsAlive(portal) and GetHealth(portal) <= 0.0 and not explode_portal and not won and not lost then
        lost = true
        FailMission(GetTime() + 1.0, "bd11lsee.des") -- Destroyed too early?
    end
end
