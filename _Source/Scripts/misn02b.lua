-- tran05.lua
-- Converted from Tran05Mission.cpp

-- Compatibility for 1.5 vs Redux naming
SetLabel = SetLabel or SetLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({ "campaignReimagined", "3686673790" })
local exu = require("exu")
aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")
local subtit = require("ScriptSubtitles")
local PersistentConfig = require("PersistentConfig")
local PlayerPilotMode = require("PlayerPilotMode")

local LABEL_BSCAV = "misn02b_bscav"
local LABEL_BSCOUT = "misn02b_bscout"
local LABEL_SCAV2 = "misn02b_scav2"
local RefreshHandlesAfterLoad

local difficulty = 2
local hardDifficultyObjective = { "hard_diff", "yellow", 8.0, "High Difficulty: Enemy presence intensified." }
local easyDifficultyObjective = { "easy_diff", "blue", 8.0, "Low Difficulty: Enemy presence reduced." }

local function RefreshDifficulty()
    if exu and exu.GetDifficulty then
        local d = exu.GetDifficulty()
        if d ~= nil then
            difficulty = d
        end
    end
    return difficulty
end

local function ApplyDifficultyObjectives()
    if difficulty >= 3 then
        AddObjective(hardDifficultyObjective[1], hardDifficultyObjective[2], hardDifficultyObjective[3], hardDifficultyObjective[4])
    elseif difficulty <= 1 then
        AddObjective(easyDifficultyObjective[1], easyDifficultyObjective[2], easyDifficultyObjective[3], easyDifficultyObjective[4])
    end
end

local function ApplyQOL()
    if exu then
        if exu.SetReticleRange then
            exu.SetReticleRange(600)
        end
        if exu.SetOrdnanceVelocInheritance then
            exu.SetOrdnanceVelocInheritance(true)
        end
    end

    if PersistentConfig and PersistentConfig.Initialize then
        PersistentConfig.Initialize()
    end
end

local function TurboValue(team)
    if team == 1 then
        return true
    end
    if team ~= 0 and difficulty and difficulty > 3 then
        return true
    end
end

local function ApplyTurbo(h)
    if not (exu and exu.SetUnitTurbo and IsCraft(h)) then
        return
    end
    local value = TurboValue(GetTeamNum(h))
    if value ~= nil and value ~= false then
        exu.SetUnitTurbo(h, value)
    else
        exu.SetUnitTurbo(h, false)
    end
end

local function ApplyTurboToAll()
    if not (exu and exu.SetUnitTurbo) then
        return
    end
    for h in AllCraft() do
        ApplyTurbo(h)
    end
end

local function UpdateModules(dt)
    if exu and exu.UpdateOrdnance then
        exu.UpdateOrdnance()
    end
    if subtit and subtit.Update then
        subtit.Update()
    end
    if PersistentConfig then
        if PersistentConfig.UpdateInputs then PersistentConfig.UpdateInputs() end
        if PersistentConfig.UpdateHeadlights then PersistentConfig.UpdateHeadlights() end
    end
end

local function NewMissionState()
    return {
        camera1 = false,
        camera2 = false,
        camera3 = false,
        found = false,
        found2 = false,
        start_done = false,
        patrol1 = false,
        message1 = false,
        message2 = false,
        message3 = false,
        message4 = false,
        message5 = false,
        mission_won = false,
        mission_lost = false,
        bootstrap_done = false,
        intro_skipped = false,
        wave_timer = 0.0,
        last_wave_time = 99999.0,
        cam_time = 0.0,
        NextSecond = 99999.0,
        bio_timer = 0,
        bscav = nil,
        bscout = nil,
        scav2 = nil,
        audmsg = nil,
        dummy = nil,
        lander = nil,
        bhandle = nil,
        bhome = nil,
        recycler = nil,
        bgoal = nil,
        bhandle2 = nil,
        loading_done = false,
        loadGracePeriod = 0
    }
end
local M = NewMissionState()

function Save()
    return M
end

function Load(...)
    local missionData = ...
    M = missionData or M
    M.loading_done = false
    M.loadGracePeriod = GetTime() + 2.0
end

local function AudioDone(msg)
    return (not msg) or IsAudioMessageDone(msg)
end

RefreshHandlesAfterLoad = function()
    M.dummy = GetHandle("fake_player")
    M.lander = GetHandle("avland0_wingman")
    M.bhandle = GetHandle("sscr_171_scrap")
    M.bhome = GetHandle("abcomm1_i76building")
    M.recycler = GetHandle("avrecy-1_recycler")
    M.bgoal = GetHandle("apscrap-1_camerapod")
    M.bhandle2 = GetHandle("sscr_176_scrap")

    M.bscav = GetHandle(LABEL_BSCAV)
    M.bscout = GetHandle(LABEL_BSCOUT)
    M.scav2 = GetHandle(LABEL_SCAV2)

    local foundScav = IsValid and IsValid(M.bscav)
    local foundScav2 = IsValid and IsValid(M.scav2)
    local foundScout = IsValid and IsValid(M.bscout)

    for h in AllCraft() do
        if not foundScav or not foundScav2 then
            if IsOdf(h, "avscav") and GetTeamNum(h) == 1 then
                if not foundScav then
                    M.bscav = h
                    if SetLabel then SetLabel(M.bscav, LABEL_BSCAV) end
                    foundScav = true
                elseif not foundScav2 then
                    M.scav2 = h
                    if SetLabel then SetLabel(M.scav2, LABEL_SCAV2) end
                    foundScav2 = true
                end
            end
        end

        if not foundScout then
            if IsOdf(h, "svfigh") and GetTeamNum(h) == 2 then
                M.bscout = h
                if SetLabel then SetLabel(M.bscout, LABEL_BSCOUT) end
                foundScout = true
            end
        end

        if foundScav and foundScav2 and foundScout then break end
    end
end

local function SetupAI()
    local playerTeam, enemyTeam = DiffUtils.SetupTeams(aiCore.Factions.NSDF, aiCore.Factions.CCA, 2)
    playerTeam:SetConfig("manageFactories", false)
    playerTeam:SetConfig("autoRepairWingmen", PersistentConfig.Settings.AutoRepairWingmen)
    playerTeam:SetConfig("enableParatroopers", false)
    enemyTeam:SetConfig("enableParatroopers", false)
end

local function PilotModeCanManageHandle(h)
    if not h or not IsValid(h) then
        return false
    end

    if h == M.bscav or h == M.scav2 or h == M.dummy then
        return false
    end

    return h ~= GetPlayerHandle()
end

local function ApplyPostLoadInit()
    Ally(1, 5)
    Ally(5, 1)
    SetAIP("misn02.aip")
    subtit.Initialize("durations.csv")

    if M.bgoal and IsAlive(M.bgoal) then
        SetUserTarget(M.bgoal)
        SetObjectiveName(M.bgoal, "Scrap Field Alpha")
    end

    for h in AllCraft() do
        SetObjectiveOff(h)
    end
end

function Start()
    Ally(1, 5)
    Ally(5, 1)
    RefreshDifficulty()
    ApplyDifficultyObjectives()
    ApplyTurboToAll()
    PlayerPilotMode.Initialize({
        profile = {
            autoManage = false,
            autoRescue = true,
            stickToPlayer = true,
            manageFactories = false,
            autoBuild = false,
        },
        shouldManageHandle = PilotModeCanManageHandle,
    })

    for h in AllCraft() do
        SetObjectiveOff(h)
    end

    M.loading_done = true

    --TestEXU()
end

-- AddObject function: Called when a game object is added
function AddObject(h)
    local team = GetTeamNum(h)
    local odf = GetOdf(h)
    if odf then odf = string.gsub(odf, "%z", "") end

    if PersistentConfig and PersistentConfig.OnObjectCreated then
        PersistentConfig.OnObjectCreated(h)
    end
    ApplyTurbo(h)

    if team == 1 and odf == "avscav" and M.bscav == nil then
        M.found = true
        M.bscav = h
        if SetLabel then SetLabel(M.bscav, LABEL_BSCAV) end
        SetCritical(M.bscav, true)
        SetObjectiveOn(M.bscav)

        -- Difficulty-based behavior for M.dummy tank
        local d = DiffUtils.Get().index
        if d < 2 and IsAlive(M.dummy) and not M.camera1 and not M.camera2 and not M.camera3 then
            Follow(M.dummy, M.bscav)
        end
    end

    if team == 2 and odf == "svfigh" then
        if not M.found2 then
            M.found2 = true
            M.bscout = h
            if SetLabel then SetLabel(M.bscout, LABEL_BSCOUT) end
            Goto(M.bscout, "M.patrol1")
            SetObjectiveOn(M.bscout)
        else
            if IsAlive(M.bscav) and IsAlive(M.bgoal) and GetDistance(M.bscav, M.bgoal) < 200.0 then
                Attack(h, M.bscav)
            else
                Goto(h, "patrol2")
            end
        end
    end

    -- Register with aiCore
    if team == 1 or team == 2 then
        local register = false
        if team == 1 then
            if IsOdf(h, "avscav") then register = true end
        else
            -- CCA Team 2 in this mission is strictly scripted waves,
            -- but we still register them to aiCore so they can be tracked
            -- even if not "produced" by a factory here.
            register = true
        end
        if register then
            if team == 1 then
                PlayerPilotMode.AddObject(h)
            else
                aiCore.AddObject(h)
            end
        end
    end
end

-- Update function: Called every frame
function Update()
    if GetTime() < (M.loadGracePeriod or 0) then
        return
    end
    if not M.loading_done then
        RefreshHandlesAfterLoad()
        RefreshDifficulty()
        ApplyDifficultyObjectives()
        ApplyQOL()
        PlayerPilotMode.Initialize({
            profile = {
                autoManage = false,
                autoRescue = true,
                stickToPlayer = true,
                manageFactories = false,
                autoBuild = false,
            },
            shouldManageHandle = PilotModeCanManageHandle,
        })
        SetupAI()
        aiCore.Bootstrap()
        ApplyTurboToAll()
        ApplyPostLoadInit()
        M.loading_done = true
    end
    local player = GetPlayerHandle()
    PlayerPilotMode.Update()
    aiCore.Update()
    UpdateModules(1.0 / 20.0)

    -- Holographic Bio Logic
    if (M.camera1 or M.camera2 or M.camera3) and GetTime() >= M.bio_timer then
        --if IsAlive(player) then
        -- Spawns the holographic bio above the player
        local pos = GetPosition(player)
        pos.y = pos.y + 10.0
        MakeExplosion("xbio", pos)
        -- end
        M.bio_timer = GetTime() + 10.0
    end

    if not M.start_done then
        SetupAI()

        --[[
        -- Available AI Configuration Flags (Reference from aiCore.lua):
        -- flags marked [Diff] are managed by DiffUtils:SetupTeams() based on difficulty.
        -- playerTeam:SetConfig("difficulty", 1)         -- [Stub]
        -- playerTeam:SetConfig("race", "nsdf")          -- Default "nsdf"
        -- playerTeam:SetConfig("kc", 0)                  -- [Stub]
        -- playerTeam:SetConfig("stratMultiplier", 1.0)   -- [Stub]
        -- playerTeam:SetConfig("autoBuild", true)

        -- Advanced Settings
        -- playerTeam:SetConfig("thumperChance", 10)       -- [Diff]
        -- playerTeam:SetConfig("mortarChance", 20)        -- [Diff]
        -- playerTeam:SetConfig("fieldChance", 10)         -- [Diff]
        -- playerTeam:SetConfig("doubleWeaponChance", 20)  -- [Diff]
        -- playerTeam:SetConfig("howitzerChance", 50)       -- [Diff]

        -- AI Behavior Settings
        -- playerTeam:SetConfig("soldierRange", 50)
        -- playerTeam:SetConfig("sniperSteal", true)
        -- playerTeam:SetConfig("pilotZeal", 0.4)          -- [Diff]
        -- playerTeam:SetConfig("sniperTraining", 75)      -- [Diff]
        -- playerTeam:SetConfig("sniperStealth", 0.5)      -- [Diff]
        -- playerTeam:SetConfig("resourceBoost", false)    -- [Diff]

        -- Timers
        -- playerTeam:SetConfig("upgradeInterval", 240)    -- [Diff]
        -- playerTeam:SetConfig("wreckerInterval", 600)    -- [Diff]
        -- playerTeam:SetConfig("techInterval", 60)
        -- playerTeam:SetConfig("techMax", 4)

        -- Toggles
        -- playerTeam:SetConfig("passiveRegen", false)     -- [Diff] (Player Only)
        -- playerTeam:SetConfig("autoManage", false)
        -- playerTeam:SetConfig("autoRepairWingmen", false) -- [Diff]
        -- playerTeam:SetConfig("autoRescue", false)       -- [Diff] (Player Only)
        -- playerTeam:SetConfig("autoTugs", false)
        -- playerTeam:SetConfig("stickToPlayer", false)    -- [Diff] (Player Only)
        -- playerTeam:SetConfig("dynamicMinefields", false)
        -- playerTeam:SetConfig("scavengerAssist", false) -- [Diff] (Player Only)

        -- Minefield positions
        -- playerTeam:SetConfig("minefields", {}) -- List of positions for minelayers

        -- Automation Sub-config
        -- playerTeam:SetConfig("followPercentage", 30)
        -- playerTeam:SetConfig("patrolPercentage", 30)
        -- playerTeam:SetConfig("guardPercentage", 40)
        -- playerTeam:SetConfig("scavengerCount", 4)
        -- playerTeam:SetConfig("tugCount", 2)
        -- playerTeam:SetConfig("buildingSpacing", 80)
        -- playerTeam:SetConfig("rescueDelay", 2.0)
        -- playerTeam:SetConfig("pilotTopoff", 4)          -- [Diff]

        -- Reinforcements
        -- playerTeam:SetConfig("orbitalReinforce", false) -- Default false

        -- Legacy Features
        -- playerTeam:SetConfig("regenRate", 0.0)          -- [Diff] (Building Regen)
        -- playerTeam:SetConfig("reclaimEngineers", false)

        -- Factory Management
        -- playerTeam:SetConfig("manageFactories", true)

        -- Wreckers & Paratroopers
        -- playerTeam:SetConfig("enableWreckers", false)     -- [Diff]
        -- playerTeam:SetConfig("enableParatroopers", false)  -- [Diff]
        -- playerTeam:SetConfig("paratrooperChance", 0)       -- [Diff]
        -- playerTeam:SetConfig("paratrooperInterval", 600)   -- [Diff]

        -- Construction Defaults
        -- playerTeam:SetConfig("siloMinDistance", 250.0)
        -- playerTeam:SetConfig("siloMaxDistance", 450.0)
        --]]
        ApplyQOL()

        SetPilot(1, math.max(1, DiffUtils.ScaleRes(2)))
        SetScrap(1, math.max(4, DiffUtils.ScaleRes(5)))
        SetAIP("misn02.aip")

        M.dummy = GetHandle("fake_player")
        M.lander = GetHandle("avland0_wingman")
        M.bhandle = GetHandle("sscr_171_scrap")
        M.bhome = GetHandle("abcomm1_i76building")
        M.recycler = GetHandle("avrecy-1_recycler")
        M.bgoal = GetHandle("apscrap-1_camerapod")
        M.bhandle2 = GetHandle("sscr_176_scrap")

        SetUserTarget(M.bgoal)
        SetObjectiveName(M.bgoal, "Scrap Field Alpha")
        --SetObjectiveName(M.recycler, "Recycler Montana")
        M.start_done = true
        subtit.Initialize("durations.csv")

        -- Establish alliance between player (team 1) and M.dummy tank (team 5)
        Ally(1, 5)

        -- Spawn pilots at Recycler based on difficulty
        local d = DiffUtils.Get().index
        local pilotCount = 0
        if d == 0 then
            pilotCount = 3 -- Very Easy
        elseif d == 1 then
            pilotCount = 2 -- Easy
        elseif d == 2 or d == 3 then
            pilotCount = 1 -- Medium/Hard
        end                -- Very Hard (4) gets 0

        for i = 1, pilotCount do
            BuildObject("aspilo", 1, "avrecy-1_recycler")
        end

        M.camera1 = true
        M.cam_time = GetTime() + 30.0
        CameraReady()
        M.audmsg = subtit.Play("misn0230.wav")
        --M.audmsg = subtit.Play("misn0201.wav")
    end

    -- Camera Logic
    if M.camera1 then
        if CameraPath("fixcam", 1200, 250, M.lander) or CameraCancelled() or AudioDone(M.audmsg) then
            -- Stop audio and subtitles if skipped
            if CameraCancelled() then
                subtit.Stop()
                M.intro_skipped = true
                M.audmsg = nil
            end
            M.camera1 = false
            M.cam_time = GetTime() + 10.0
            M.camera2 = true
        end
    end

    if M.camera2 then
        M.camera2 = false
        M.camera3 = true
        if IsAlive(M.dummy) then
            Goto(M.dummy, "player_path")
        end
        M.cam_time = GetTime() + 25.0
    end

    if M.camera3 then
        if CameraPath("zoomcam", 1200, 800, M.dummy) or AudioDone(M.audmsg) or CameraCancelled() then
            M.camera3 = false
            M.cam_time = 99999.0
            CameraFinish()

            -- Reassign M.dummy tank instead of removing it
            if IsAlive(M.dummy) then
                SetTeamNum(M.dummy, 5) -- Set to team 5
                Ally(1, 5)           -- Make teams 1 and 5 allies

                local d = DiffUtils.Get().index
                if d < 2 and IsAlive(M.bscav) then
                    Follow(M.dummy, M.bscav)
                elseif IsAlive(M.recycler) then
                    Defend2(M.dummy, M.recycler, 0) -- Set to defend the M.recycler
                end
            end

            --SetPosition(player, "playermove")
            -- Stop previous audio if the user skipped the cinematic, then start the next one
            if CameraCancelled() or M.intro_skipped then
                subtit.Stop()
                M.intro_skipped = true
            end

            if not M.intro_skipped then
                M.audmsg = subtit.Play("misn0201.wav")
            end
            --subtit.Play("misn0224.wav")
            M.wave_timer = GetTime() + DiffUtils.ScaleTimer(30.0)
            AddObjective("misn02b1.otf", "white")
        end
    end

    -- Patrol 1 Logic
    if not M.patrol1 and M.found and IsAlive(M.bhandle) and IsAlive(M.bscav) and GetDistance(M.bhandle, M.bscav) < 75.0 then
        for i = 1, DiffUtils.ScaleEnemy(1) do BuildObject("svfigh", 2, "spawn1") end

        subtit.Play("misn0233.wav")
        M.message1 = true
        M.patrol1 = true

        if not M.message4 and M.found2 then
            M.message4 = true
        end
    end

    if not M.message4 and M.found2 then
        M.message4 = true
    end

    -- Capture pre-placed units if M.start_done just flipped
    if M.start_done and not M.bootstrap_done then
        aiCore.Bootstrap()
        M.bootstrap_done = true
    end

    -- Wave Logic
    if M.message4 and not M.message5 and IsAlive(M.bscav) and IsAlive(M.bhandle2) and GetDistance(M.bscav, M.bhandle2) < 200.0 then
        BuildObject("svfigh", 2, "spawn2")
        M.message5 = true
        M.wave_timer = GetTime() + 30.0
    end

    if M.message5 and not M.message3 and GetTime() > M.wave_timer then
        for i = 1, DiffUtils.ScaleEnemy(1) do BuildObject("svfigh", 2, "spawn2") end
        M.wave_timer = GetTime() + DiffUtils.ScaleTimer(45.0)
    end

    -- Retreat Logic
    if M.message1 and M.message5 and not M.message2 and IsAlive(M.bscav) and GetLastEnemyShot(M.bscav) > 0 then
        Follow(M.bscav, M.bhome)
        ClearObjectives()
        AddObjective("misn02b2.otf", "white")
        subtit.Play("misn0225.wav")
        local bbase = GetHandle("apbase-1_camerapod")
        SetUserTarget(bbase)
        M.message2 = true
    end

    -- Loss Condition
    if M.bscav ~= nil and not M.mission_lost then
        if not IsAlive(player) or not IsAlive(M.bscav) or (M.message3 and not IsAlive(M.scav2)) or not IsAlive(M.bhome) or not IsAlive(M.recycler) then
            ClearObjectives()
            AddObjective("misn02b4.otf", "red")
            M.audmsg = subtit.Play("misn0227.wav")
            M.mission_lost = true
        end
    end

    if M.mission_lost and AudioDone(M.audmsg) then
        FailMission(GetTime(), "misn02l1.des")
    end

    -- Rescue Logic
    if IsAlive(player) and M.message1 and M.message4 and IsAlive(M.bhome) and IsAlive(M.bscav) and GetDistance(M.bhome, M.bscav) < 300.0 and not M.message3 then
        Follow(M.bscav, M.bhome)
        M.wave_timer = GetTime() + 45.0
        M.scav2 = BuildObject("avscav", 1, "spawn3")
        if SetLabel then SetLabel(M.scav2, LABEL_SCAV2) end
        SetCritical(M.scav2, true)
        Retreat(M.scav2, "retreat")
        SetObjectiveOn(M.scav2)
        SetObjectiveOff(M.bscav)
        subtit.Play("misn0228.wav")
        M.last_wave_time = GetTime() + 10.0
        M.NextSecond = GetTime() + 1.0
        M.message3 = true

        -- Dummy tank follow M.scav2 logic for lower difficulties
        local d = DiffUtils.Get().index
        if d < 2 and IsAlive(M.dummy) then
            Follow(M.dummy, M.scav2)
        end

        -- Flanking Ambush: Spawn enemies behind the player at spawn1
        for i = 1, DiffUtils.ScaleEnemy(1) do
            local h = BuildObject("svfigh", 2, "spawn1")
            Attack(h, M.scav2)
        end
    end

    -- Health Regen
    if IsAlive(M.bscav) and M.message3 and GetTime() > M.NextSecond then
        AddHealth(M.bscav, 200.0)
        M.NextSecond = GetTime() + 1.0
    end

    -- Final Wave
    if M.last_wave_time < GetTime() then
        for i = 1, DiffUtils.ScaleEnemy(1) do
            local sid = BuildObject("svfigh", 2, "spawn4")
            if IsAlive(M.scav2) then Attack(sid, M.scav2) end
        end
        M.last_wave_time = 99999.0
    end

    -- Win Condition
    if M.message3 and not M.mission_won and IsAlive(M.bhome) and IsAlive(M.scav2) and GetDistance(M.bhome, M.scav2) < 200.0 then
        ClearObjectives()
        SetObjectiveOff(M.scav2)
        if IsAlive(M.bscav) then SetObjectiveOff(M.bscav) end
        AddObjective("misn02b3.otf", "green")
        if IsAlive(M.bscav) then AddHealth(M.bscav, 1000.0) end
        if IsAlive(M.scav2) then AddHealth(M.scav2, 1000.0) end
        M.audmsg = subtit.Play("misn0234.wav")
        M.mission_won = true
    end

    if M.mission_won and AudioDone(M.audmsg) then
        SucceedMission(GetTime(), "misn02w1.des")
    end
end

