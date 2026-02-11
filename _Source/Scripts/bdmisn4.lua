<<<<<<< HEAD
-- bdmisn4.lua (Converted from BlackDog04Mission.cpp)

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
local camera_ready = {false, false, false}
local camera_complete = {false, false, false}
local goto_scav = false
local objective1_complete = false
local objective2_complete = false
local objective3_complete = false
local in_base_area = false
local do_attack = false
local start_attack = false
local out_of_scav = false
local trigger1_triggered = false
local id_fragment = false
local got_fragment = false
local return_attack = {false, false, false, false}
local lost = false
local won = false

-- Timers
local camera_complete_delay = 99999.9
local get_in_scav_timeout = 99999.0
local portal_cam_time = 99999.9
local portal_off_time = 99999.9
local portal_unit_time = {99999.9, 99999.9}
local portal_sound_time = 99999.9
local in_base_sound_time = 99999.9
local sound4_time = 99999.9
local bomber_time = 99999.9

-- Handles
local user, last_user
local pilot, nav1, nav2
local silo, portal
local scav1, scav2, scav3
local fragment, nav_beacon, hauler
local turrets = {} -- 1..9
local portal_units = {} -- 1..2

-- Sounds (Flags)
local sound_handles = {
    intro = false,
    portal = false,
    scav_msg = false,
    congrats = false,
    base1 = false,
    base2 = false,
    s4 = false,
    s5 = false,
    s6 = false
}

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

local function ActivatePortal(h, flag) 
    -- C++: activatePortal(portal, false);
    -- Lua API usually has ActivatePortal(h, bool)? Or SetPortalState?
    -- Assuming SetPortalState or standard animation.
    -- If unavailable, ignore or replace with effect.
    -- BZRedux usually supports this.
    -- Checking known APIs: `SetPortalState(h, state)` usually exists.
end

local function PlaySoundOnce(key, file) 
    if not sound_handles[key] then
        AudioMessage(file)
        sound_handles[key] = true
        return true
    end
    return false
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
    last_user = user
    user = GetPlayerHandle()
    aiCore.Update()
    
    if not start_done then
        SetScrap(1, 8)
        SetPilot(1, 10)
        ClearObjectives()
        
        silo = GetHandle("silo")
        portal = GetHandle("portal")
        scav1 = GetHandle("scav_1")
        scav2 = GetHandle("scav_2")
        scav3 = GetHandle("scav_3")
        fragment = GetHandle("fragment")
        hauler = GetHandle("hauler_1")
        for i=1,9 do turrets[i] = GetHandle("turret_"..i) end
        
        start_done = true
    end
    
    -- SOE #1: Intro
    if not camera_complete[1] then
        if not camera_ready[1] then
            CameraReady()
            pilot = BuildObject("aspilo", 1, "pilot")
            Goto(pilot, "pilot_path", 1)
            -- Hide(user) -- Can't easily hide player in all versions, ignore
            AudioMessage("bd04001.wav")
            camera_ready[1] = true
        end
        
        CameraPath("camera_start_up", 750, 400, pilot)
        
        -- Spawn navs when pilot creates them
        if not nav1 and GetDistance(pilot, "nav_1") < 20.0 then -- Increased dist slightly for reliability
            nav1 = BuildObject("apcamr", 0, "nav_1")
        end
        if not nav2 and GetDistance(pilot, "nav_2") < 20.0 then
            nav2 = BuildObject("apcamr", 0, "nav_2")
            camera_complete_delay = GetTime() + 2.0
        end
        
        if CameraCancelled() then 
            -- StopAudioMessage(introSound)
            camera_complete_delay = -1.0 -- Force complete
        end
        
        if camera_complete_delay < GetTime() or (not nav2 and CameraCancelled()) then -- Force completion logic
            CameraFinish()
            camera_complete[1] = true
            camera_ready[1] = false
            camera_complete_delay = 99999.9
            
            RemoveObject(pilot)
            -- UnHide(user)
            
            if not nav1 then nav1 = BuildObject("apcamr", 0, "nav_1") end
            if not nav2 then nav2 = BuildObject("apcamr", 0, "nav_2") end
            
            SetPerceivedTeam(user, 2) -- Cloak as ally to enemy?
        end
    end
    
    -- SOE #2: Portal
    if camera_complete[1] and not camera_complete[2] then
        if not camera_ready[2] then
            camera_ready[2] = true
            CameraReady()
            -- ActivatePortal(portal, false) 
            portal_cam_time = GetTime() + 6.0
            portal_sound_time = GetTime() + 4.0
            portal_unit_time[1] = GetTime() + 1.5
            portal_unit_time[2] = GetTime() + 4.0
            portal_off_time = GetTime() + 7.0
        end
        
        CameraPath("camera_portal", 3000, 0, portal)
        
        if CameraCancelled() then portal_cam_time = -1.0 end
        
        if portal_cam_time < GetTime() then
            portal_cam_time = 99999.9
            camera_ready[2] = false
            camera_complete[2] = true
            CameraFinish()
        elseif portal_sound_time < GetTime() then
            portal_sound_time = 99999.9
            AudioMessage("bd04002.wav")
        end
    end
    
    -- Portal Units
    for i=1,2 do
        if portal_unit_time[i] < GetTime() then
            portal_unit_time[i] = 99999.9
            -- BuildObjectAtPortal? Lua: BuildObject usually.
            -- Need spawn point near portal if specialized function missing.
            -- Assuming "cvfigh" at "portal" transform.
            portal_units[i] = BuildObject("cvfigh", 2, "unit_path") -- Simplified spawn logic
            Goto(portal_units[i], "unit_path", 1)
        end
    end
    
    if portal_off_time < GetTime() then
        portal_off_time = 99999.9
        -- deactivatePortal(portal)
    end
    
    -- SOE #3: Infiltration
    if camera_complete[2] and not goto_scav then
        AudioMessage("bd04003.wav")
        ClearObjectives()
        AddObjective("bd04001.otf", "white")
        SetObjectiveOn(scav3)
        -- SetObjectiveName("Scavenger")
        goto_scav = true
        SetUserTarget(scav3)
        get_in_scav_timeout = GetTime() + 120.0
    end
    
    -- Timeout Message
    if not objective1_complete and get_in_scav_timeout < GetTime() then
        get_in_scav_timeout = GetTime() + 120.0
        AudioMessage("bd04003.wav")
    end
    
    -- Arrive in Scav
    if user == scav3 then
        if not objective1_complete and not objective2_complete then
            -- StopAudio...
            ClearObjectives()
            AddObjective("bd04001.otf", "green")
            AddObjective("bd04002.otf", "white")
            objective1_complete = true
            SetObjectiveOff(scav3)
            get_in_scav_timeout = 99999.0
            
            Goto(scav1, "scav_path")
            Goto(scav2, "scav_path")
            AudioMessage("bd04010.wav")
            SetObjectiveOn(portal)
        end
    end
    
    -- SOE #4: Base Entry
    if not trigger1_triggered and user == scav3 and GetDistance(scav3, "trigger_1") < 400.0 then
        trigger1_triggered = true
    end
    
    if IsIn(user, "base_limit") and not in_base_area then -- IsIn region check
        in_base_area = true
        if trigger1_triggered then
            -- Safe
        elseif user == scav3 then
            AudioMessage("bd04005.wav") -- "Who go there?"
            in_base_sound_time = GetTime() + 1.0 -- Should be timer for response
            sound_handles.base1 = true
        else
            do_attack = true
        end
    end
    
    if sound_handles.base1 and in_base_sound_time < GetTime() then
       in_base_sound_time = 99999.9
       AudioMessage("bd04006.wav")
       do_attack = true -- "Intruder!"
       sound_handles.base1 = false
    end
    
    if do_attack then
        if not start_attack or last_user ~= user then
            start_attack = true
            for i=1,9 do if IsAlive(turrets[i]) then Attack(turrets[i], user, 1) end end
        end
    end
    
    -- Scan Portal
    if not objective2_complete and IsInfo("cbport") then 
        ClearObjectives()
        AddObjective("bd04004.otf", "white")
        sound4_time = GetTime() + 2.0
        objective2_complete = true
        SetObjectiveOff(portal)
        StartCockpitTimer(60, 15, 5) -- Timer to scan fragment?
    end
    
    if sound4_time < GetTime() then
        AudioMessage("bd04004.wav") -- "Found control"
        sound4_time = 99999.9
    end
    
    -- Timer/Sequence Logic simplified:
    -- C++ has sequence sound4->sound5->sound6 via IsAudioMessageDone.
    -- Lua: Just play sequentially with delays or triggers.
    if objective2_complete and not id_fragment and GetCockpitTimer() <= 0.0 then
        HideCockpitTimer()
        -- Times up logic?
        -- Actually C++: if GetCockpitTimer <= 0 -> Play "Failed/Too Slow"? 
        -- bd04005/6 seem to be "Intruder" sounds.
        -- If timer runs out, you get attacked?
        -- Yes, bd04006 -> DoAttack.
        AudioMessage("bd04005.wav"); AudioMessage("bd04006.wav")
        do_attack = true
    end
    
    -- Scan Fragment
    if objective2_complete and not id_fragment and IsInfo("obdataa") then
        StopCockpitTimer(); HideCockpitTimer()
        id_fragment = true
        AudioMessage("bd04007.wav")
        ClearObjectives()
        AddObjective("bd04003.otf", "white")
        objective3_complete = true
    end
    
    if objective3_complete and not out_of_scav then
        if user ~= scav3 then
            out_of_scav = true
            do_attack = true -- Cover blown if you leave scav
        end
    end
    
    -- SOE #4b: Get Fragment
    if not got_fragment then
        if GetTug(fragment) == user then
            got_fragment = true
            nav_beacon = BuildObject("apcamr", 1, "rv_scout")
            
            -- Spawn Escort for Hauler? Or Player?
            -- C++: Spawns "escort_units" (Team 1).
            BuildObject("bvfigh", 1, "escort_units")
            BuildObject("bvfigh", 1, "escort_units")
            BuildObject("bvfigh", 1, "escort_units")
            BuildObject("bvtank", 1, "escort_units")
            BuildObject("bvtank", 1, "escort_units")
            BuildObject("bvtank", 1, "escort_units")
            bomber_time = GetTime() + 30.0
        end
    end
    
    if bomber_time < GetTime() then
        bomber_time = 99999.9
        
        -- Spawn Bombers (Scripted)
        local function SpawnBomber() 
            local h = BuildObject("bvhraza", 1, "bomber_wing_x5_spawn_point") 
            Goto(h, "trigger_1") 
        end
        for i=1,5 do SpawnBomber() end
        
        -- Override Nav Beacon? C++ overwrites `navBeacon` handle?
        -- Uses `proposed_end_area`.
        if IsAlive(nav_beacon) then RemoveObject(nav_beacon) end
        nav_beacon = BuildObject("apcamr", 1, "proposed_end_area")
        SetLabel(nav_beacon, "Drop Zone")
        SetObjectiveOn(nav_beacon)
        
        -- Attack Hauler!
        local function SpawnAttacker(odf, pt)
            local h = BuildObject(odf, 2, pt)
            Attack(h, hauler, 1)
        end
        for i=1,6 do SpawnAttacker("cvfighg", "chinese_scout_x6_spawn_point") end
        for i=1,2 do SpawnAttacker("cvfighg", "attack_1") end
        for i=1,4 do SpawnAttacker("cvfighg", "attack_2") end
        for i=1,3 do SpawnAttacker("cvtnk", "attack_3") end
    end
    
    -- Return Attacks (Ambush on return path)
    for i=1,4 do
        if not return_attack[i] then
            local spots = {"return_1", "return_2", "return_3", "return_4"}
            if GetDistance(hauler, spots[i]) < 300.0 then
                return_attack[i] = true
                local h = BuildObject("cvfigh", 2, spots[i]); Attack(h, hauler)
                h = BuildObject("cvfigh", 2, spots[i]); Attack(h, hauler)
                h = BuildObject("cvfigh", 2, spots[i]); Attack(h, hauler)
            end
        end
    end
    
    -- Hauler Survival Check
    if IsAlive(hauler) and GetHealth(hauler) <= 0.0 and not lost and not won then
        FailMission(GetTime() + 1.0, "bd04lose.des")
        lost = true
    end
    
    -- Win Check
    if objective3_complete and GetDistance(fragment, nav_beacon) < 50.0 and not won and not lost then
        ClearObjectives()
        AddObjective("bd04003.otf", "green")
        won = true
        AudioMessage("bd04008.wav")
        SucceedMission(GetTime() + 5.0, "bd04win.des") -- Wait for audio simulated
    end
    
    -- Portal Destruction Fail
    if IsAlive(portal) and GetHealth(portal) <= 0.0 and not won and not lost then
        lost = true
        FailMission(GetTime() + 1.0, "bd04lose.des")
    end
end
=======
-- bdmisn4.lua (Converted from BlackDog04Mission.cpp)

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
local camera_ready = {false, false, false}
local camera_complete = {false, false, false}
local goto_scav = false
local objective1_complete = false
local objective2_complete = false
local objective3_complete = false
local in_base_area = false
local do_attack = false
local start_attack = false
local out_of_scav = false
local trigger1_triggered = false
local id_fragment = false
local got_fragment = false
local return_attack = {false, false, false, false}
local lost = false
local won = false

-- Timers
local camera_complete_delay = 99999.9
local get_in_scav_timeout = 99999.0
local portal_cam_time = 99999.9
local portal_off_time = 99999.9
local portal_unit_time = {99999.9, 99999.9}
local portal_sound_time = 99999.9
local in_base_sound_time = 99999.9
local sound4_time = 99999.9
local bomber_time = 99999.9

-- Handles
local user, last_user
local pilot, nav1, nav2
local silo, portal
local scav1, scav2, scav3
local fragment, nav_beacon, hauler
local turrets = {} -- 1..9
local portal_units = {} -- 1..2

-- Sounds (Flags)
local sound_handles = {
    intro = false,
    portal = false,
    scav_msg = false,
    congrats = false,
    base1 = false,
    base2 = false,
    s4 = false,
    s5 = false,
    s6 = false
}

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

local function ActivatePortal(h, flag) 
    -- C++: activatePortal(portal, false);
    -- Lua API usually has ActivatePortal(h, bool)? Or SetPortalState?
    -- Assuming SetPortalState or standard animation.
    -- If unavailable, ignore or replace with effect.
    -- BZRedux usually supports this.
    -- Checking known APIs: `SetPortalState(h, state)` usually exists.
end

local function PlaySoundOnce(key, file) 
    if not sound_handles[key] then
        AudioMessage(file)
        sound_handles[key] = true
        return true
    end
    return false
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
    last_user = user
    user = GetPlayerHandle()
    aiCore.Update()
    
    if not start_done then
        SetScrap(1, 8)
        SetPilot(1, 10)
        ClearObjectives()
        
        silo = GetHandle("silo")
        portal = GetHandle("portal")
        scav1 = GetHandle("scav_1")
        scav2 = GetHandle("scav_2")
        scav3 = GetHandle("scav_3")
        fragment = GetHandle("fragment")
        hauler = GetHandle("hauler_1")
        for i=1,9 do turrets[i] = GetHandle("turret_"..i) end
        
        start_done = true
    end
    
    -- SOE #1: Intro
    if not camera_complete[1] then
        if not camera_ready[1] then
            CameraReady()
            pilot = BuildObject("aspilo", 1, "pilot")
            Goto(pilot, "pilot_path", 1)
            -- Hide(user) -- Can't easily hide player in all versions, ignore
            AudioMessage("bd04001.wav")
            camera_ready[1] = true
        end
        
        CameraPath("camera_start_up", 750, 400, pilot)
        
        -- Spawn navs when pilot creates them
        if not nav1 and GetDistance(pilot, "nav_1") < 20.0 then -- Increased dist slightly for reliability
            nav1 = BuildObject("apcamr", 0, "nav_1")
        end
        if not nav2 and GetDistance(pilot, "nav_2") < 20.0 then
            nav2 = BuildObject("apcamr", 0, "nav_2")
            camera_complete_delay = GetTime() + 2.0
        end
        
        if CameraCancelled() then 
            -- StopAudioMessage(introSound)
            camera_complete_delay = -1.0 -- Force complete
        end
        
        if camera_complete_delay < GetTime() or (not nav2 and CameraCancelled()) then -- Force completion logic
            CameraFinish()
            camera_complete[1] = true
            camera_ready[1] = false
            camera_complete_delay = 99999.9
            
            RemoveObject(pilot)
            -- UnHide(user)
            
            if not nav1 then nav1 = BuildObject("apcamr", 0, "nav_1") end
            if not nav2 then nav2 = BuildObject("apcamr", 0, "nav_2") end
            
            SetPerceivedTeam(user, 2) -- Cloak as ally to enemy?
        end
    end
    
    -- SOE #2: Portal
    if camera_complete[1] and not camera_complete[2] then
        if not camera_ready[2] then
            camera_ready[2] = true
            CameraReady()
            -- ActivatePortal(portal, false) 
            portal_cam_time = GetTime() + 6.0
            portal_sound_time = GetTime() + 4.0
            portal_unit_time[1] = GetTime() + 1.5
            portal_unit_time[2] = GetTime() + 4.0
            portal_off_time = GetTime() + 7.0
        end
        
        CameraPath("camera_portal", 3000, 0, portal)
        
        if CameraCancelled() then portal_cam_time = -1.0 end
        
        if portal_cam_time < GetTime() then
            portal_cam_time = 99999.9
            camera_ready[2] = false
            camera_complete[2] = true
            CameraFinish()
        elseif portal_sound_time < GetTime() then
            portal_sound_time = 99999.9
            AudioMessage("bd04002.wav")
        end
    end
    
    -- Portal Units
    for i=1,2 do
        if portal_unit_time[i] < GetTime() then
            portal_unit_time[i] = 99999.9
            -- BuildObjectAtPortal? Lua: BuildObject usually.
            -- Need spawn point near portal if specialized function missing.
            -- Assuming "cvfigh" at "portal" transform.
            portal_units[i] = BuildObject("cvfigh", 2, "unit_path") -- Simplified spawn logic
            Goto(portal_units[i], "unit_path", 1)
        end
    end
    
    if portal_off_time < GetTime() then
        portal_off_time = 99999.9
        -- deactivatePortal(portal)
    end
    
    -- SOE #3: Infiltration
    if camera_complete[2] and not goto_scav then
        AudioMessage("bd04003.wav")
        ClearObjectives()
        AddObjective("bd04001.otf", "white")
        SetObjectiveOn(scav3)
        -- SetObjectiveName("Scavenger")
        goto_scav = true
        SetUserTarget(scav3)
        get_in_scav_timeout = GetTime() + 120.0
    end
    
    -- Timeout Message
    if not objective1_complete and get_in_scav_timeout < GetTime() then
        get_in_scav_timeout = GetTime() + 120.0
        AudioMessage("bd04003.wav")
    end
    
    -- Arrive in Scav
    if user == scav3 then
        if not objective1_complete and not objective2_complete then
            -- StopAudio...
            ClearObjectives()
            AddObjective("bd04001.otf", "green")
            AddObjective("bd04002.otf", "white")
            objective1_complete = true
            SetObjectiveOff(scav3)
            get_in_scav_timeout = 99999.0
            
            Goto(scav1, "scav_path")
            Goto(scav2, "scav_path")
            AudioMessage("bd04010.wav")
            SetObjectiveOn(portal)
        end
    end
    
    -- SOE #4: Base Entry
    if not trigger1_triggered and user == scav3 and GetDistance(scav3, "trigger_1") < 400.0 then
        trigger1_triggered = true
    end
    
    if IsIn(user, "base_limit") and not in_base_area then -- IsIn region check
        in_base_area = true
        if trigger1_triggered then
            -- Safe
        elseif user == scav3 then
            AudioMessage("bd04005.wav") -- "Who go there?"
            in_base_sound_time = GetTime() + 1.0 -- Should be timer for response
            sound_handles.base1 = true
        else
            do_attack = true
        end
    end
    
    if sound_handles.base1 and in_base_sound_time < GetTime() then
       in_base_sound_time = 99999.9
       AudioMessage("bd04006.wav")
       do_attack = true -- "Intruder!"
       sound_handles.base1 = false
    end
    
    if do_attack then
        if not start_attack or last_user ~= user then
            start_attack = true
            for i=1,9 do if IsAlive(turrets[i]) then Attack(turrets[i], user, 1) end end
        end
    end
    
    -- Scan Portal
    if not objective2_complete and IsInfo("cbport") then 
        ClearObjectives()
        AddObjective("bd04004.otf", "white")
        sound4_time = GetTime() + 2.0
        objective2_complete = true
        SetObjectiveOff(portal)
        StartCockpitTimer(60, 15, 5) -- Timer to scan fragment?
    end
    
    if sound4_time < GetTime() then
        AudioMessage("bd04004.wav") -- "Found control"
        sound4_time = 99999.9
    end
    
    -- Timer/Sequence Logic simplified:
    -- C++ has sequence sound4->sound5->sound6 via IsAudioMessageDone.
    -- Lua: Just play sequentially with delays or triggers.
    if objective2_complete and not id_fragment and GetCockpitTimer() <= 0.0 then
        HideCockpitTimer()
        -- Times up logic?
        -- Actually C++: if GetCockpitTimer <= 0 -> Play "Failed/Too Slow"? 
        -- bd04005/6 seem to be "Intruder" sounds.
        -- If timer runs out, you get attacked?
        -- Yes, bd04006 -> DoAttack.
        AudioMessage("bd04005.wav"); AudioMessage("bd04006.wav")
        do_attack = true
    end
    
    -- Scan Fragment
    if objective2_complete and not id_fragment and IsInfo("obdataa") then
        StopCockpitTimer(); HideCockpitTimer()
        id_fragment = true
        AudioMessage("bd04007.wav")
        ClearObjectives()
        AddObjective("bd04003.otf", "white")
        objective3_complete = true
    end
    
    if objective3_complete and not out_of_scav then
        if user ~= scav3 then
            out_of_scav = true
            do_attack = true -- Cover blown if you leave scav
        end
    end
    
    -- SOE #4b: Get Fragment
    if not got_fragment then
        if GetTug(fragment) == user then
            got_fragment = true
            nav_beacon = BuildObject("apcamr", 1, "rv_scout")
            
            -- Spawn Escort for Hauler? Or Player?
            -- C++: Spawns "escort_units" (Team 1).
            BuildObject("bvfigh", 1, "escort_units")
            BuildObject("bvfigh", 1, "escort_units")
            BuildObject("bvfigh", 1, "escort_units")
            BuildObject("bvtank", 1, "escort_units")
            BuildObject("bvtank", 1, "escort_units")
            BuildObject("bvtank", 1, "escort_units")
            bomber_time = GetTime() + 30.0
        end
    end
    
    if bomber_time < GetTime() then
        bomber_time = 99999.9
        
        -- Spawn Bombers (Scripted)
        local function SpawnBomber() 
            local h = BuildObject("bvhraza", 1, "bomber_wing_x5_spawn_point") 
            Goto(h, "trigger_1") 
        end
        for i=1,5 do SpawnBomber() end
        
        -- Override Nav Beacon? C++ overwrites `navBeacon` handle?
        -- Uses `proposed_end_area`.
        if IsAlive(nav_beacon) then RemoveObject(nav_beacon) end
        nav_beacon = BuildObject("apcamr", 1, "proposed_end_area")
        SetLabel(nav_beacon, "Drop Zone")
        SetObjectiveOn(nav_beacon)
        
        -- Attack Hauler!
        local function SpawnAttacker(odf, pt)
            local h = BuildObject(odf, 2, pt)
            Attack(h, hauler, 1)
        end
        for i=1,6 do SpawnAttacker("cvfighg", "chinese_scout_x6_spawn_point") end
        for i=1,2 do SpawnAttacker("cvfighg", "attack_1") end
        for i=1,4 do SpawnAttacker("cvfighg", "attack_2") end
        for i=1,3 do SpawnAttacker("cvtnk", "attack_3") end
    end
    
    -- Return Attacks (Ambush on return path)
    for i=1,4 do
        if not return_attack[i] then
            local spots = {"return_1", "return_2", "return_3", "return_4"}
            if GetDistance(hauler, spots[i]) < 300.0 then
                return_attack[i] = true
                local h = BuildObject("cvfigh", 2, spots[i]); Attack(h, hauler)
                h = BuildObject("cvfigh", 2, spots[i]); Attack(h, hauler)
                h = BuildObject("cvfigh", 2, spots[i]); Attack(h, hauler)
            end
        end
    end
    
    -- Hauler Survival Check
    if IsAlive(hauler) and GetHealth(hauler) <= 0.0 and not lost and not won then
        FailMission(GetTime() + 1.0, "bd04lose.des")
        lost = true
    end
    
    -- Win Check
    if objective3_complete and GetDistance(fragment, nav_beacon) < 50.0 and not won and not lost then
        ClearObjectives()
        AddObjective("bd04003.otf", "green")
        won = true
        AudioMessage("bd04008.wav")
        SucceedMission(GetTime() + 5.0, "bd04win.des") -- Wait for audio simulated
    end
    
    -- Portal Destruction Fail
    if IsAlive(portal) and GetHealth(portal) <= 0.0 and not won and not lost then
        lost = true
        FailMission(GetTime() + 1.0, "bd04lose.des")
    end
end
>>>>>>> 30fa079494619a8bd6565c444554253b8b48a7b9

