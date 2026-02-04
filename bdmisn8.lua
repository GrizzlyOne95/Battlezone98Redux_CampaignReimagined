<<<<<<< HEAD
-- bdmisn8.lua (Converted from BlackDog08Mission.cpp)

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
local camera_ready = {false, false}
local camera_complete = {false, false}
local arrived = false
local pilot_spawned1 = false
local pilot_spawned2 = false
local portal_reprogrammed = false
local apc_heading_back = false
local schedule_lose2 = false
local schedule_lose3 = false
local apc_commandeered = false
local lost = false
local won = false

-- Timers
local second_camera_time = 99999.0
local activate_time = 99999.0
local attack_wave_time = 99999.0
local apc_time = 99999.0
local apc_pilot_time1 = 99999.0
local apc_pilot_time2 = 99999.0
local apc_go_back_time = 99999.0
local sound3_time = 99999.0

-- Handles
local user
local recycler, portal, command, factory
local nav_portal, nav_base
local apc, pilot
local attackers = {
    "cvtnk", "cvtnk", "cvltnk", "cvfigh", "cvfigh",
    "cvfigh", "cvfigh", "cvfigh", "cvrckt", "cvhraz"
}
local wave_count = 0

-- Sounds (Flags)
local intro_sound = false
local intro2_sound = false
local win_sound = false
local lose_sound2 = false
local lose_sound3 = false

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

local function PlaySequenceAudio(flag, file)
    if not flag then
        AudioMessage(file)
        return true
    end
    return false -- Already played or waiting
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
        
        recycler = GetHandle("recycler")
        portal = GetHandle("portal")
        command = GetHandle("command")
        factory = GetHandle("factory")
        nav_portal = GetHandle("nav_portal")
        if nav_portal then SetName(nav_portal, "Portal") end
        nav_base = GetHandle("nav_base")
        if nav_base then SetName(nav_base, "Black Dog Base") end
        
        start_done = true
    end
    
    -- Cam 1: Intro
    if not camera_complete[1] then
        if not camera_ready[1] then
            camera_ready[1] = true
            CameraReady()
            AudioMessage("bd08001.wav")
            intro_sound = true
        end
        
        if not arrived then
            CameraPath("path_camera_intro", 800, 1500, user)
            -- C++ sets arrived=TRUE; logic relies on path completion or audio.
            -- Lua paths usually specific to engine. Assuming CameraPath is fire-once or loops.
            -- C++ loop checks `arrived` BOOL return.
            -- Let's assume after short time we move on if not cancelled.
        end
        
        if CameraCancelled() or (intro_sound and IsAudioMessageDone and IsAudioMessageDone(intro_sound) == 1) then
            -- Note: Lua IsAudioMessageDone might not take handle if not returned.
            -- Replacing with timer approximation for robustness:
            -- Assuming 10s intro.
        end
        
        -- Simplified: Just wait for user to skip or path finish
        -- Or rely on Timer
        if not arrived then -- using arrived as 'timer_set'
             second_camera_time = GetTime() + 10.0 -- Audio length approx
             arrived = true
        end
        
        if CameraCancelled() or GetTime() > second_camera_time then
            CameraFinish()
            camera_complete[1] = true
            second_camera_time = GetTime() + 25.0 -- Wait before Cam 2
            arrived = false -- Reset
        end
    end
    
    -- Cam 2: Portal
    if GetTime() > second_camera_time and not camera_complete[2] then
        if not camera_ready[2] then
            camera_ready[2] = true
            CameraReady()
            AudioMessage("bd08002.wav")
            intro2_sound = true
            
            ClearObjectives()
            AddObjective("bd08001.otf", "white")
            
            activate_time = GetTime() + 0.5
            apc_time = GetTime() + 90.0
        end
        
        CameraPath("path_portalcam", 4000, 1000, portal)
        
        if CameraCancelled() then
            CameraFinish()
            camera_complete[2] = true
        end
        -- C++ finishes cam immediately if `arrived` (path done).
        -- We'll assume path is short or user skips.
        -- Actually `arrived` in C++ usually means path reached end point.
    end
    
    -- Portal Activation
    if GetTime() > activate_time then
        -- ActivatePortal(portal, false)
        -- Lua: SetPortalState or ignore visual.
        -- Trigger waves if active.
        attack_wave_time = GetTime() + 1.0
        activate_time = 99999.0
    end
    
    -- Attack Waves
    if GetTime() > attack_wave_time then
        if GetTime() < apc_time + 45.0 and GetTime() > apc_time - 10.0 then
            -- Pause waves for APC arrival
            attack_wave_time = GetTime() + 5.0
        else
            -- Spawn Wave
            local unit = attackers[math.random(1, 10)]
            -- BuildObjectAtPortal?
            local h = BuildObject(unit, 2, "portal_out") -- Approx
            
            if math.random() < 0.5 then Goto(h, "attack_path1", 1) else Goto(h, "attack_path2", 1) end
            
            wave_count = wave_count + 1
            if wave_count < 4 then
                attack_wave_time = GetTime() + 4.0
            else
                wave_count = 0
                attack_wave_time = GetTime() + 30.0
            end
        end
    end
    
    -- APC Arrival
    if GetTime() > apc_time then
        apc_time = 99999.0
        apc = BuildObject("cvapc", 2, "portal_out") -- AtPortal
        Goto(apc, "portal_out", 1) -- Move out a bit
        attack_wave_time = GetTime() + 30.0
        apc_pilot_time1 = GetTime() + 20.0
        sound3_time = GetTime() + 1.0
    end
    
    if GetTime() > sound3_time then
        sound3_time = 99999.0
        AudioMessage("bd08003.wav")
    end
    
    -- Pilot 1 (Original) Leaves
    if GetTime() > apc_pilot_time1 then
        apc_pilot_time1 = 99999.0
        Stop(apc, 1)
        
        -- C++: `pilot = BuildObject("cspilo", 2, apc); Retreat(pilot, portal, 1);`
        -- Simulate pilot getting out.
        -- Need to make APC empty (no pilot).
        -- Lua: `SetPilotClass(apc, "")`? Or `SetTeam(apc, 0)`?
        -- `SetPerceivedTeam(apc, 0)` in C++.
        SetTeam(apc, 0) -- Neutral? Or just empty.
        pilot = BuildObject("cspilo", 2, "portal_out") -- Spawn nearby
        SetObjPosition(pilot, GetObjPosition(apc)) -- Teleport to APC
        Retreat(pilot, "portal_in", 1)
        pilot_spawned1 = true
        
        ClearObjectives()
        AddObjective("bd08001.otf", "white")
        AddObjective("bd08002.otf", "white")
        SetObjectiveOn(apc)
    end
    
    if pilot_spawned1 then
        if IsAlive(pilot) then
            if GetDistance(pilot, portal) < 20.0 then -- Touching
                RemoveObject(pilot)
                pilot_spawned1 = false
                apc_pilot_time2 = GetTime() + 9 * 60.0
            end
        else -- Dead
            schedule_lose2 = true -- Pilot died? C++ Logic: `pilot killed before reprogramming`.
            -- Wait, if pilot 1 (original) dies, we lose??
            -- C++ Line 506: `scheduleLose2 = TRUE`.
            -- Why? Maybe we needed him to open parsing?
            -- Or maybe `apcPilotTime2` is the reprogramming one.
            -- This logic: User shouldn't kill the fleeing pilot?
            -- Actually, `apcPilotTime2` is set ONLY if pilot touches portal.
            -- So if we kill him, `apcPilotTime2` never sets -> Mission stuck or fail.
            -- Weird design. We must let him leave?
            pilot_spawned1 = false
        end
    end
    
    -- Enemy Pilot 2 (Hijacker) Returns
    if GetTime() > apc_pilot_time2 then
        apc_pilot_time2 = 99999.0
        pilot = BuildObject("cspilo", 2, "spawn_pilot")
        Retreat(pilot, apc, 1) -- Going to APC
        pilot_spawned2 = true
        portal_reprogrammed = true
        AudioMessage("bd08004.wav")
        -- deactivatePortal(portal)
        
        ClearObjectives()
        AddObjective("bd08002.otf", "green")
        AddObjective("bd08003.otf", "white")
        attack_wave_time = 99999.0 -- Stop waves
    end
    
    if pilot_spawned2 then
        if GetTeamNum(apc) == 1 then -- Player got it!
            pilot_spawned2 = false
            Attack(pilot, apc) -- Enemy pilot attacks APC
        elseif not IsAlive(pilot) then
            pilot_spawned2 = false
            pilot = nil
        elseif GetDistance(pilot, apc) < 20.0 then -- Reached APC
            pilot_spawned2 = false
            apc_go_back_time = GetTime() + 25.0
            
            -- Enemy takes APC
            RemoveObject(pilot)
            SetTeam(apc, 2)
            -- SetPilotClass(apc, "cspilo")
            pilot = nil
        end
    end
    
    -- APC Escape Logic
    if GetTime() > apc_go_back_time then
        apc_go_back_time = 99999.0
        if IsAlive(apc) then
            apc_heading_back = true
            -- activatePortal(portal, true)
            Retreat(apc, "portal_in", 1)
        end
    end
    
    if apc_heading_back then
        if GetTeamNum(apc) == 1 then apc_heading_back = false end -- Player took it
        
        if apc_heading_back and not lost and not won then
            if GetDistance(apc, portal) < 20.0 then
                RemoveObject(apc)
                schedule_lose2 = true -- Escaped
            end
        end
    end
    
    -- Loss Conditions
    if not lost and not won then
        if (recycler and not IsAlive(recycler)) or (command and not IsAlive(command)) then
            schedule_lose2 = true
        elseif apc and not IsAlive(apc) then
            schedule_lose3 = true -- Destroyed APC
        end
    end
    
    if schedule_lose2 and not lost then
        lost = true
        AudioMessage("bd08006.wav")
        FailMission(GetTime() + 1.0, "bd08lsea.des")
    end
    if schedule_lose3 and not lost then
        lost = true
        AudioMessage("bd08006.wav")
        FailMission(GetTime() + 1.0, "bd08lseb.des")
    end
    
    -- Win Condition
    if apc and GetTeamNum(apc) == 1 and not apc_commandeered then
        apc_commandeered = true
    end
    
    if apc_commandeered and portal_reprogrammed and not won and not lost then
        won = true
        AudioMessage("bd08007.wav")
        SucceedMission(GetTime() + 1.0, "bd08win.des")
    end
    
end
=======
-- bdmisn8.lua (Converted from BlackDog08Mission.cpp)

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
local camera_ready = {false, false}
local camera_complete = {false, false}
local arrived = false
local pilot_spawned1 = false
local pilot_spawned2 = false
local portal_reprogrammed = false
local apc_heading_back = false
local schedule_lose2 = false
local schedule_lose3 = false
local apc_commandeered = false
local lost = false
local won = false

-- Timers
local second_camera_time = 99999.0
local activate_time = 99999.0
local attack_wave_time = 99999.0
local apc_time = 99999.0
local apc_pilot_time1 = 99999.0
local apc_pilot_time2 = 99999.0
local apc_go_back_time = 99999.0
local sound3_time = 99999.0

-- Handles
local user
local recycler, portal, command, factory
local nav_portal, nav_base
local apc, pilot
local attackers = {
    "cvtnk", "cvtnk", "cvltnk", "cvfigh", "cvfigh",
    "cvfigh", "cvfigh", "cvfigh", "cvrckt", "cvhraz"
}
local wave_count = 0

-- Sounds (Flags)
local intro_sound = false
local intro2_sound = false
local win_sound = false
local lose_sound2 = false
local lose_sound3 = false

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

local function PlaySequenceAudio(flag, file)
    if not flag then
        AudioMessage(file)
        return true
    end
    return false -- Already played or waiting
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
        
        recycler = GetHandle("recycler")
        portal = GetHandle("portal")
        command = GetHandle("command")
        factory = GetHandle("factory")
        nav_portal = GetHandle("nav_portal")
        if nav_portal then SetName(nav_portal, "Portal") end
        nav_base = GetHandle("nav_base")
        if nav_base then SetName(nav_base, "Black Dog Base") end
        
        start_done = true
    end
    
    -- Cam 1: Intro
    if not camera_complete[1] then
        if not camera_ready[1] then
            camera_ready[1] = true
            CameraReady()
            AudioMessage("bd08001.wav")
            intro_sound = true
        end
        
        if not arrived then
            CameraPath("path_camera_intro", 800, 1500, user)
            -- C++ sets arrived=TRUE; logic relies on path completion or audio.
            -- Lua paths usually specific to engine. Assuming CameraPath is fire-once or loops.
            -- C++ loop checks `arrived` BOOL return.
            -- Let's assume after short time we move on if not cancelled.
        end
        
        if CameraCancelled() or (intro_sound and IsAudioMessageDone and IsAudioMessageDone(intro_sound) == 1) then
            -- Note: Lua IsAudioMessageDone might not take handle if not returned.
            -- Replacing with timer approximation for robustness:
            -- Assuming 10s intro.
        end
        
        -- Simplified: Just wait for user to skip or path finish
        -- Or rely on Timer
        if not arrived then -- using arrived as 'timer_set'
             second_camera_time = GetTime() + 10.0 -- Audio length approx
             arrived = true
        end
        
        if CameraCancelled() or GetTime() > second_camera_time then
            CameraFinish()
            camera_complete[1] = true
            second_camera_time = GetTime() + 25.0 -- Wait before Cam 2
            arrived = false -- Reset
        end
    end
    
    -- Cam 2: Portal
    if GetTime() > second_camera_time and not camera_complete[2] then
        if not camera_ready[2] then
            camera_ready[2] = true
            CameraReady()
            AudioMessage("bd08002.wav")
            intro2_sound = true
            
            ClearObjectives()
            AddObjective("bd08001.otf", "white")
            
            activate_time = GetTime() + 0.5
            apc_time = GetTime() + 90.0
        end
        
        CameraPath("path_portalcam", 4000, 1000, portal)
        
        if CameraCancelled() then
            CameraFinish()
            camera_complete[2] = true
        end
        -- C++ finishes cam immediately if `arrived` (path done).
        -- We'll assume path is short or user skips.
        -- Actually `arrived` in C++ usually means path reached end point.
    end
    
    -- Portal Activation
    if GetTime() > activate_time then
        -- ActivatePortal(portal, false)
        -- Lua: SetPortalState or ignore visual.
        -- Trigger waves if active.
        attack_wave_time = GetTime() + 1.0
        activate_time = 99999.0
    end
    
    -- Attack Waves
    if GetTime() > attack_wave_time then
        if GetTime() < apc_time + 45.0 and GetTime() > apc_time - 10.0 then
            -- Pause waves for APC arrival
            attack_wave_time = GetTime() + 5.0
        else
            -- Spawn Wave
            local unit = attackers[math.random(1, 10)]
            -- BuildObjectAtPortal?
            local h = BuildObject(unit, 2, "portal_out") -- Approx
            
            if math.random() < 0.5 then Goto(h, "attack_path1", 1) else Goto(h, "attack_path2", 1) end
            
            wave_count = wave_count + 1
            if wave_count < 4 then
                attack_wave_time = GetTime() + 4.0
            else
                wave_count = 0
                attack_wave_time = GetTime() + 30.0
            end
        end
    end
    
    -- APC Arrival
    if GetTime() > apc_time then
        apc_time = 99999.0
        apc = BuildObject("cvapc", 2, "portal_out") -- AtPortal
        Goto(apc, "portal_out", 1) -- Move out a bit
        attack_wave_time = GetTime() + 30.0
        apc_pilot_time1 = GetTime() + 20.0
        sound3_time = GetTime() + 1.0
    end
    
    if GetTime() > sound3_time then
        sound3_time = 99999.0
        AudioMessage("bd08003.wav")
    end
    
    -- Pilot 1 (Original) Leaves
    if GetTime() > apc_pilot_time1 then
        apc_pilot_time1 = 99999.0
        Stop(apc, 1)
        
        -- C++: `pilot = BuildObject("cspilo", 2, apc); Retreat(pilot, portal, 1);`
        -- Simulate pilot getting out.
        -- Need to make APC empty (no pilot).
        -- Lua: `SetPilotClass(apc, "")`? Or `SetTeam(apc, 0)`?
        -- `SetPerceivedTeam(apc, 0)` in C++.
        SetTeam(apc, 0) -- Neutral? Or just empty.
        pilot = BuildObject("cspilo", 2, "portal_out") -- Spawn nearby
        SetObjPosition(pilot, GetObjPosition(apc)) -- Teleport to APC
        Retreat(pilot, "portal_in", 1)
        pilot_spawned1 = true
        
        ClearObjectives()
        AddObjective("bd08001.otf", "white")
        AddObjective("bd08002.otf", "white")
        SetObjectiveOn(apc)
    end
    
    if pilot_spawned1 then
        if IsAlive(pilot) then
            if GetDistance(pilot, portal) < 20.0 then -- Touching
                RemoveObject(pilot)
                pilot_spawned1 = false
                apc_pilot_time2 = GetTime() + 9 * 60.0
            end
        else -- Dead
            schedule_lose2 = true -- Pilot died? C++ Logic: `pilot killed before reprogramming`.
            -- Wait, if pilot 1 (original) dies, we lose??
            -- C++ Line 506: `scheduleLose2 = TRUE`.
            -- Why? Maybe we needed him to open parsing?
            -- Or maybe `apcPilotTime2` is the reprogramming one.
            -- This logic: User shouldn't kill the fleeing pilot?
            -- Actually, `apcPilotTime2` is set ONLY if pilot touches portal.
            -- So if we kill him, `apcPilotTime2` never sets -> Mission stuck or fail.
            -- Weird design. We must let him leave?
            pilot_spawned1 = false
        end
    end
    
    -- Enemy Pilot 2 (Hijacker) Returns
    if GetTime() > apc_pilot_time2 then
        apc_pilot_time2 = 99999.0
        pilot = BuildObject("cspilo", 2, "spawn_pilot")
        Retreat(pilot, apc, 1) -- Going to APC
        pilot_spawned2 = true
        portal_reprogrammed = true
        AudioMessage("bd08004.wav")
        -- deactivatePortal(portal)
        
        ClearObjectives()
        AddObjective("bd08002.otf", "green")
        AddObjective("bd08003.otf", "white")
        attack_wave_time = 99999.0 -- Stop waves
    end
    
    if pilot_spawned2 then
        if GetTeamNum(apc) == 1 then -- Player got it!
            pilot_spawned2 = false
            Attack(pilot, apc) -- Enemy pilot attacks APC
        elseif not IsAlive(pilot) then
            pilot_spawned2 = false
            pilot = nil
        elseif GetDistance(pilot, apc) < 20.0 then -- Reached APC
            pilot_spawned2 = false
            apc_go_back_time = GetTime() + 25.0
            
            -- Enemy takes APC
            RemoveObject(pilot)
            SetTeam(apc, 2)
            -- SetPilotClass(apc, "cspilo")
            pilot = nil
        end
    end
    
    -- APC Escape Logic
    if GetTime() > apc_go_back_time then
        apc_go_back_time = 99999.0
        if IsAlive(apc) then
            apc_heading_back = true
            -- activatePortal(portal, true)
            Retreat(apc, "portal_in", 1)
        end
    end
    
    if apc_heading_back then
        if GetTeamNum(apc) == 1 then apc_heading_back = false end -- Player took it
        
        if apc_heading_back and not lost and not won then
            if GetDistance(apc, portal) < 20.0 then
                RemoveObject(apc)
                schedule_lose2 = true -- Escaped
            end
        end
    end
    
    -- Loss Conditions
    if not lost and not won then
        if (recycler and not IsAlive(recycler)) or (command and not IsAlive(command)) then
            schedule_lose2 = true
        elseif apc and not IsAlive(apc) then
            schedule_lose3 = true -- Destroyed APC
        end
    end
    
    if schedule_lose2 and not lost then
        lost = true
        AudioMessage("bd08006.wav")
        FailMission(GetTime() + 1.0, "bd08lsea.des")
    end
    if schedule_lose3 and not lost then
        lost = true
        AudioMessage("bd08006.wav")
        FailMission(GetTime() + 1.0, "bd08lseb.des")
    end
    
    -- Win Condition
    if apc and GetTeamNum(apc) == 1 and not apc_commandeered then
        apc_commandeered = true
    end
    
    if apc_commandeered and portal_reprogrammed and not won and not lost then
        won = true
        AudioMessage("bd08007.wav")
        SucceedMission(GetTime() + 1.0, "bd08win.des")
    end
    
end
>>>>>>> 30fa079494619a8bd6565c444554253b8b48a7b9
