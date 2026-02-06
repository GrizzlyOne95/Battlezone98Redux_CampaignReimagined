-- cmisn04.lua (Converted from Chinese04Mission.cpp)

-- Compatibility
SetLabel = SetLabel or SettLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
local exu = require("exu")
local aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")

-- Helper for AI
local function SetupAI()
    DiffUtils.SetupTeams(aiCore.Factions.CRA, aiCore.Factions.CCA, 2)
end

-- Mission States
local MS_STARTUP = 1
local MS_STARTSCENE = 2
local MS_PLAYSOUND7 = 3
local MS_NEARNAVS = 4
local MS_WAITFORID = 6
local WS_WAITFORSOUND2 = 7
local MS_WAITFORALARM = 8
local MS_CAMERAALARM = 9
local MS_NEARSILO = 10
local MS_INSPECTSILO = 11
local MS_WAIT_TRANS_SOUND2 = 12
local MS_WAITFORSOUND3 = 13
local MS_WAITFORSOUND8 = 14
local MS_WAITFORPORTAL = 15
local MS_CAMERAEND = 16
local MS_END = 100

-- Variables
local mission_state = MS_STARTUP
local lost = false
local won = false
local target_silo_inspected = false
local end_near = false
local inside_cloaked_ship = true
local attacked_already = false
local up_to_navpoint = 0

-- Timers
local state_timer = 99999.0
local portal_timeout = 99999.0

-- Handles
local user, old_user
local target_silo, portal, cca_factory, factory
local nav_points = {} -- 1..6
local attack_user1 = {} -- 25 units
local attack_user2 = {} -- 4 turrets
local attack_user3 = {} -- 4
local attack_user4 = {} -- 4
local attack_user5 = {} -- 4
local attack_user6 = {} -- 6
local empty = {} -- spots 1..25
local turret = {} -- 1..4
local opening_sound, sound_handle, core_fail_sound

-- Difficulty
local difficulty = 2

function Start()
    if exu then
        if exu.EnableShotConvergence then exu.EnableShotConvergence() end
        if exu.SetSmartCursorRange then exu.SetSmartCursorRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then 
        aiCore.AddObject(h)
    end
end

function DeleteObject(h)
end

local function ResetObjectives()
    ClearObjectives()
    if mission_state >= MS_WAITFORID then
        AddObjective("ch04001.otf", "green")
    elseif mission_state >= MS_NEARNAVS then
        AddObjective("ch04001.otf", "white")
    end

    if target_silo_inspected then
        AddObjective("ch04002.otf", "green")
    elseif mission_state >= MS_WAITFORID then
        AddObjective("ch04002.otf", "white")
    end

    if mission_state >= MS_WAIT_TRANS_SOUND2 then
        AddObjective("ch04003.otf", "white")
    end
end

local function UnitsAttackPlayer()
    if user == old_user then return end
    
    for i=1,25 do if attack_user1[i] and IsAlive(attack_user1[i]) then Attack(attack_user1[i], user) end end
    for i=1,4 do if attack_user2[i] and IsAlive(attack_user2[i]) then Attack(attack_user2[i], user) end end
    
    if mission_state >= MS_WAITFORSOUND3 then
        for i=1,4 do
            if attack_user3[i] and IsAlive(attack_user3[i]) then Attack(attack_user3[i], user) end
            if attack_user4[i] and IsAlive(attack_user4[i]) then Attack(attack_user4[i], user) end
            if attack_user5[i] and IsAlive(attack_user5[i]) then Attack(attack_user5[i], user) end
        end
        for i=1,6 do if attack_user6[i] and IsAlive(attack_user6[i]) then Attack(attack_user6[i], user) end end
    end
end

function Update()
    user = GetPlayerHandle()
    aiCore.Update()
    
    -- In-state object maintenance (health etc)
    if IsAlive(factory) then GiveMaxHealth(factory) end
    if IsAlive(portal) then GiveMaxHealth(portal) end
    if mission_state == MS_CAMERAEND and IsAlive(user) then GiveMaxHealth(user) end
    
    -- Detection logic
    if attacked_already and mission_state <= MS_WAITFORPORTAL then
        UnitsAttackPlayer()
    end
    
    -- Seat change logic
    if mission_state ~= MS_STARTUP and user ~= old_user then
        if inside_cloaked_ship then
            SetDecloaked(old_user)
            EnableCloaking(old_user, false)
        end
        inside_cloaked_ship = false
    end
    
    -- FSM
    if mission_state == MS_STARTUP then
        SetScrap(1, DiffUtils.ScaleRes(0))
        SetPilot(1, DiffUtils.ScaleRes(10))
        old_user = user
        
        target_silo = GetHandle("target_silo")
        nav_points[1] = GetHandle("nav_1")
        cca_factory = GetHandle("cca_factory")
        factory = GetHandle("factory")
        portal = GetHandle("portal")
        
        for i=1,25 do empty[i] = GetHandle("empty_"..i) end
        for i=1,4 do turret[i] = GetHandle("turret_"..i) end
        
        opening_sound = AudioMessage("ch04001.wav")
        CameraReady()
        mission_state = MS_STARTSCENE
    
    elseif mission_state == MS_STARTSCENE then
        local arrived = CameraPath("camera_start", 1000, 1200, target_silo)
        if arrived or CameraCancelled() then
            if opening_sound then StopAudioMessage(opening_sound) end
            CameraFinish()
            mission_state = MS_PLAYSOUND7
            state_timer = GetTime() + 5.0
        end

    elseif mission_state == MS_PLAYSOUND7 then
        if GetTime() > state_timer then
            AudioMessage("ch04007.wav")
            StartCockpitTimer(DiffUtils.ScaleTimer(130)) -- 2:10 scaled
            mission_state = MS_NEARNAVS
            up_to_navpoint = 1
            ResetObjectives()
            SetUserTarget(nav_points[1])
        end

    elseif mission_state == MS_NEARNAVS then
        if GetCockpitTimer() < 1 then
            AudioMessage("ch04006.wav")
            FailMission(GetTime() + 2.0, "ch04lsea.des")
            mission_state = MS_END
        elseif GetDistance(user, nav_points[up_to_navpoint]) < 50.0 then
            if up_to_navpoint >= 6 then
                for i=1,6 do if nav_points[i] then RemoveObject(nav_points[i]) end end
                HideCockpitTimer()
                mission_state = MS_WAITFORID
                ResetObjectives()
                SetPerceivedTeam(user, 2)
                SetObjectiveOn(target_silo)
            else
                up_to_navpoint = up_to_navpoint + 1
                local name = (up_to_navpoint == 6) and "Pit Entrance" or "nav_"..up_to_navpoint
                nav_points[up_to_navpoint] = BuildObject("apcamr", 1, "nav_"..up_to_navpoint)
                if up_to_navpoint == 6 then SetName(nav_points[up_to_navpoint], "Pit Entrance") end
                SetUserTarget(nav_points[up_to_navpoint])
            end
        end

    elseif mission_state == MS_WAITFORID then
        target_silo_inspected = IsInfo(target_silo)
        local dist = GetDistance(user, "trigger_1")
        if dist <= 70.0 or target_silo_inspected then
            sound_handle = nil
            mission_state = WS_WAITFORSOUND2
        end

    elseif mission_state == WS_WAITFORSOUND2 then
        if not sound_handle or IsAudioMessageDone(sound_handle) then
            state_timer = GetTime() + 1.0
            mission_state = MS_WAITFORALARM
        end

    elseif mission_state == MS_WAITFORALARM then
        if GetTime() > state_timer then
            -- Pilots fleeing (Scaled)
            for i=1, DiffUtils.ScaleEnemy(6) do Retreat(BuildObject("sspilo", 2, "pilot_"..((i-1)%6+1)), empty[(i-1)%25+1]) end
            for i=7, DiffUtils.ScaleEnemy(10) do Retreat(BuildObject("sspilo", 2, "pilot_"..((i-1)%10+1)), empty[(i-1)%25+1]) end
            -- Additional individual ones as per C++ lore
            Retreat(BuildObject("sspilo", 2, "pilot_11"), empty[11])
            Retreat(BuildObject("sspilo", 2, "pilot_25"), empty[25])

            mission_state = MS_CAMERAALARM
            state_timer = GetTime() + 5.0
            CameraReady()
        end

    elseif mission_state == MS_CAMERAALARM then
        CameraPath("camera_alarm", 2000, 0, cca_factory)
        if CameraCancelled() or GetTime() > state_timer then
            CameraFinish()
            if not IsCloaked(user) then
                attacked_already = true
                SetPerceivedTeam(user, 1)
                for i=1,25 do attack_user1[i] = empty[i]; Attack(attack_user1[i], user) end
                for i=1,4 do attack_user2[i] = turret[i]; Attack(attack_user2[i], user) end
            else
                attacked_already = false
            end
            mission_state = MS_NEARSILO
        end

    elseif mission_state == MS_NEARSILO then
        if attacked_already then
            if core_fail_sound then
                if IsAudioMessageDone(core_fail_sound) then core_fail_sound = nil end
            elseif IsCloaked(user) then
                core_fail_sound = AudioMessage("ch04002.wav")
                SetDecloaked(user); EnableCloaking(user, false)
            end
        end

        if GetDistance(user, target_silo) <= 200.0 then
            Goto(BuildObject("svfigh", 2, "fighter_1"), "figh1_path")
            Goto(BuildObject("svfigh", 2, "fighter_2"), "figh2_path")
            mission_state = MS_INSPECTSILO
        end

    elseif mission_state == MS_INSPECTSILO then
        if attacked_already then
            if core_fail_sound then
                if IsAudioMessageDone(core_fail_sound) then core_fail_sound = nil end
            elseif IsCloaked(user) then
                core_fail_sound = AudioMessage("ch04002.wav")
                SetDecloaked(user); EnableCloaking(user, false)
            end
        end

        if not target_silo_inspected then target_silo_inspected = IsInfo(target_silo) end
        if target_silo_inspected then
            sound_handle = nil
            SetObjectiveOff(target_silo)
            mission_state = MS_WAIT_TRANS_SOUND2
            state_timer = GetTime() + 45.0
            ResetObjectives()

            if not attacked_already then
                if IsCloaked(user) then
                    sound_handle = AudioMessage("ch04002.wav")
                    SetDecloaked(user)
                end
                EnableCloaking(user, false)
                attacked_already = true
                SetPerceivedTeam(user, 1)
                for i=1,25 do attack_user1[i] = empty[i]; Attack(attack_user1[i], user) end
                for i=1,4 do attack_user2[i] = turret[i]; Attack(attack_user2[i], user) end
            end
        end

    elseif mission_state == MS_WAIT_TRANS_SOUND2 then
        if not sound_handle or IsAudioMessageDone(sound_handle) then
            sound_handle = AudioMessage("ch04003.wav")
            for i=1, DiffUtils.ScaleEnemy(4) do
                attack_user3[i] = BuildObject("svfigha", 2, "chase_1"); Attack(attack_user3[i], user)
                attack_user4[i] = BuildObject("svtanka", 2, "chase_2"); Attack(attack_user4[i], user)
                attack_user5[i] = BuildObject("svfigha", 2, "chase_3"); Attack(attack_user5[i], user)
            end
            for i=1, DiffUtils.ScaleEnemy(6) do attack_user6[i] = BuildObject("svfigh", 2, "portal_units") end
            ActivatePortal(portal)
            mission_state = MS_WAITFORSOUND3
        end

    elseif mission_state == MS_WAITFORSOUND3 then
        if IsAudioMessageDone(sound_handle) then
            sound_handle = AudioMessage("ch04008.wav")
            mission_state = MS_WAITFORSOUND8
        end

    elseif mission_state == MS_WAITFORSOUND8 then
        if IsAudioMessageDone(sound_handle) then
            portal_timeout = GetTime() + DiffUtils.ScaleTimer(135) -- 2:15 scaled
            nav_points[1] = BuildObject("apcamr", 1, "nav_base")
            SetUserTarget(nav_points[1])
            mission_state = MS_WAITFORPORTAL
        end

    elseif mission_state == MS_WAITFORPORTAL then
        if GetTime() > portal_timeout then
            FailMission(GetTime() + 2.0, "ch04lseb.des")
            mission_state = MS_END
        elseif GetDistance(user, portal) < 100.0 then
            if nav_points[1] then RemoveObject(nav_points[1]) end
            HideCockpitTimer()
            SetPerceivedTeam(user, 2)
            GiveMaxHealth(user)
            Hide(user)
            mission_state = MS_CAMERAEND
            CameraReady()
            end_near = false
            state_timer = 0
        end

    elseif mission_state == MS_CAMERAEND then
        local arrived = false
        if not end_near then
            arrived = CameraPathDir("auto_end", 500, 3000)
        else
            CameraPathDir("auto_end", 500, 0)
        end

        if not end_near and arrived then
            end_near = true
            state_timer = GetTime() + 2.0
        end

        if end_near and GetTime() > state_timer then
            DeactivatePortal(portal)
            mission_state = MS_END
            SucceedMission(GetTime() + 4.0, "ch04win.des")
        end
    end
    
    if user ~= old_user then old_user = user end
end
