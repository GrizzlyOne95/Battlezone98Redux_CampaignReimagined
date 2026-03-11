-- tran05.lua
-- Converted from Tran05Mission.cpp

-- Compatibility for 1.5 vs Redux naming
SetLabel = SetLabel or SetLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({ "campaignReimagined", "3659600763" })
local exu = require("exu")
aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")
local MissionLifecycle = require("MissionLifecycle")
local subtit = require("ScriptSubtitles")
local PersistentConfig = require("PersistentConfig")
local unpack = table.unpack or unpack

local LABEL_BSCAV = "misn02b_bscav"
local LABEL_BSCOUT = "misn02b_bscout"
local LABEL_SCAV2 = "misn02b_scav2"
local RefreshHandlesAfterLoad
local load_pending = false
local load_grace_until = 0.0
local pending_ai_data = nil

-- Global Variables (State)
local camera1 = false
local camera2 = false
local camera3 = false
local found = false
local found2 = false
local start_done = false
local patrol1 = false
local message1 = false
local message2 = false
local message3 = false
local message4 = false
local message5 = false
local mission_won = false
local mission_lost = false
local bootstrap_done = false
local intro_skipped = false

local wave_timer = 0.0
local last_wave_time = 99999.0
local cam_time = 0.0
local NextSecond = 99999.0
local bio_timer = 0

local bscav = nil
local bscout = nil
local scav2 = nil
local audmsg = nil

-- Handles that are looked up
local dummy = nil
local lander = nil
local bhandle = nil
local bhome = nil
local recycler = nil
local bgoal = nil
local bhandle2 = nil

local lifecycleState = { difficulty = 2 }
local SAVE_VERSION = 1
local lifecycle = MissionLifecycle.New({
    exu = exu,
    aiCore = aiCore,
    subtit = subtit,
    PersistentConfig = PersistentConfig,
    reticleRange = 600,
    ordnanceVelocityInheritance = true,
    updateOrdnance = true,
    monitorDifficultyChanges = true,
    difficultyPollInterval = 1.0,
    clearTurboWhenDisabled = true,
    initializeSubtitlesOnStart = false,
    initializeSubtitlesOnLoad = false,
    refreshDifficultyOnLoad = true,
    hardDifficultyObjective = { "hard_diff", "yellow", 8.0, "High Difficulty: Enemy presence intensified." },
    easyDifficultyObjective = { "easy_diff", "blue", 8.0, "Low Difficulty: Enemy presence reduced." },
    turboValue = function(_, team, state)
        if team == 1 then
            return true
        end
        if team ~= 0 and state.difficulty and state.difficulty > 3 then
            return true
        end
    end
})

local function PackMissionState()
    local data = {}
    local i = 0
    local function push(v)
        i = i + 1
        data[i] = v
    end

    push(SAVE_VERSION)
    push(camera1)
    push(camera2)
    push(camera3)
    push(found)
    push(found2)
    push(start_done)
    push(patrol1)
    push(message1)
    push(message2)
    push(message3)
    push(message4)
    push(message5)
    push(mission_won)
    push(mission_lost)
    push(bootstrap_done)
    push(wave_timer)
    push(last_wave_time)
    push(cam_time)
    push(NextSecond)
    push(nil) -- bscav (restored after load)
    push(nil) -- bscout (restored after load)
    push(nil) -- scav2 (restored after load)
    push(nil) -- audmsg (audio handles are not saved)
    push(nil) -- dummy (restored after load)
    push(nil) -- lander (restored after load)
    push(nil) -- bhandle (restored after load)
    push(nil) -- bhome (restored after load)
    push(nil) -- recycler (restored after load)
    push(nil) -- bgoal (restored after load)
    push(nil) -- bhandle2 (restored after load)
    push(intro_skipped)
    push(bio_timer)

    return data, i
end

-- Save function: Returns values to be saved (no audio handles)
function Save()
    local data, count = PackMissionState()
    return unpack(data, 1, count), aiCore.Save()
end

-- Load function: Restores values from save
function Load(...)
    local count = select("#", ...)
    if count == 0 then return end

    local args = { ... }
    local first = args[1]
    pending_ai_data = nil
    if count > 1 and type(args[count]) == "table" then
        pending_ai_data = args[count]
    end

    if type(first) == "table" then
        local missionData = first
        local idx = 1
        if type(missionData[idx]) == "number" then
            idx = idx + 1 -- SAVE_VERSION
        end

        camera1 = missionData[idx]; idx = idx + 1
        camera2 = missionData[idx]; idx = idx + 1
        camera3 = missionData[idx]; idx = idx + 1
        found = missionData[idx]; idx = idx + 1
        found2 = missionData[idx]; idx = idx + 1
        start_done = missionData[idx]; idx = idx + 1
        patrol1 = missionData[idx]; idx = idx + 1
        message1 = missionData[idx]; idx = idx + 1
        message2 = missionData[idx]; idx = idx + 1
        message3 = missionData[idx]; idx = idx + 1
        message4 = missionData[idx]; idx = idx + 1
        message5 = missionData[idx]; idx = idx + 1
        mission_won = missionData[idx]; idx = idx + 1
        mission_lost = missionData[idx]; idx = idx + 1
        bootstrap_done = missionData[idx]; idx = idx + 1
        wave_timer = missionData[idx]; idx = idx + 1
        last_wave_time = missionData[idx]; idx = idx + 1
        cam_time = missionData[idx]; idx = idx + 1
        NextSecond = missionData[idx]; idx = idx + 1
        bscav = missionData[idx]; idx = idx + 1
        bscout = missionData[idx]; idx = idx + 1
        scav2 = missionData[idx]; idx = idx + 1
        idx = idx + 1 -- audmsg placeholder
        dummy = missionData[idx]; idx = idx + 1
        lander = missionData[idx]; idx = idx + 1
        bhandle = missionData[idx]; idx = idx + 1
        bhome = missionData[idx]; idx = idx + 1
        recycler = missionData[idx]; idx = idx + 1
        bgoal = missionData[idx]; idx = idx + 1
        bhandle2 = missionData[idx]; idx = idx + 1
        intro_skipped = missionData[idx]; idx = idx + 1
        bio_timer = missionData[idx]; idx = idx + 1

        audmsg = nil
        if wave_timer == nil then wave_timer = 0 end
        if last_wave_time == nil then last_wave_time = 99999.0 end
        if cam_time == nil then cam_time = 0.0 end
        if NextSecond == nil then NextSecond = 99999.0 end
        if bio_timer == nil then bio_timer = 0 end
        load_pending = true
        return
    end

    local idx = 1
    if type(args[idx]) == "number" then
        idx = idx + 1 -- SAVE_VERSION
    end

    camera1 = args[idx]; idx = idx + 1
    camera2 = args[idx]; idx = idx + 1
    camera3 = args[idx]; idx = idx + 1
    found = args[idx]; idx = idx + 1
    found2 = args[idx]; idx = idx + 1
    start_done = args[idx]; idx = idx + 1
    patrol1 = args[idx]; idx = idx + 1
    message1 = args[idx]; idx = idx + 1
    message2 = args[idx]; idx = idx + 1
    message3 = args[idx]; idx = idx + 1
    message4 = args[idx]; idx = idx + 1
    message5 = args[idx]; idx = idx + 1
    mission_won = args[idx]; idx = idx + 1
    mission_lost = args[idx]; idx = idx + 1
    bootstrap_done = args[idx]; idx = idx + 1
    wave_timer = args[idx]; idx = idx + 1
    last_wave_time = args[idx]; idx = idx + 1
    cam_time = args[idx]; idx = idx + 1
    NextSecond = args[idx]; idx = idx + 1
    bscav = args[idx]; idx = idx + 1
    bscout = args[idx]; idx = idx + 1
    scav2 = args[idx]; idx = idx + 1
    idx = idx + 1 -- audmsg placeholder
    dummy = args[idx]; idx = idx + 1
    lander = args[idx]; idx = idx + 1
    bhandle = args[idx]; idx = idx + 1
    bhome = args[idx]; idx = idx + 1
    recycler = args[idx]; idx = idx + 1
    bgoal = args[idx]; idx = idx + 1
    bhandle2 = args[idx]; idx = idx + 1
    intro_skipped = args[idx]; idx = idx + 1
    bio_timer = args[idx]; idx = idx + 1

    audmsg = nil
    if wave_timer == nil then wave_timer = 0 end
    if last_wave_time == nil then last_wave_time = 99999.0 end
    if cam_time == nil then cam_time = 0.0 end
    if NextSecond == nil then NextSecond = 99999.0 end
    if bio_timer == nil then bio_timer = 0 end
    load_pending = true
end

local function AudioDone(msg)
    return (not msg) or IsAudioMessageDone(msg)
end

RefreshHandlesAfterLoad = function()
    dummy = GetHandle("fake_player")
    lander = GetHandle("avland0_wingman")
    bhandle = GetHandle("sscr_171_scrap")
    bhome = GetHandle("abcomm1_i76building")
    recycler = GetHandle("avrecy-1_recycler")
    bgoal = GetHandle("apscrap-1_camerapod")
    bhandle2 = GetHandle("sscr_176_scrap")

    bscav = GetHandle(LABEL_BSCAV)
    bscout = GetHandle(LABEL_BSCOUT)
    scav2 = GetHandle(LABEL_SCAV2)

    local foundScav = IsValid and IsValid(bscav)
    local foundScav2 = IsValid and IsValid(scav2)
    local foundScout = IsValid and IsValid(bscout)

    for h in AllCraft() do
        if not foundScav or not foundScav2 then
            if IsOdf(h, "avscav") and GetTeamNum(h) == 1 then
                if not foundScav then
                    bscav = h
                    if SetLabel then SetLabel(bscav, LABEL_BSCAV) end
                    foundScav = true
                elseif not foundScav2 then
                    scav2 = h
                    if SetLabel then SetLabel(scav2, LABEL_SCAV2) end
                    foundScav2 = true
                end
            end
        end

        if not foundScout then
            if IsOdf(h, "svfigh") and GetTeamNum(h) == 2 then
                bscout = h
                if SetLabel then SetLabel(bscout, LABEL_BSCOUT) end
                foundScout = true
            end
        end

        if foundScav and foundScav2 and foundScout then break end
    end
end

function Start()
    Ally(1, 5)
    Ally(5, 1)
    lifecycle:RefreshDifficulty(lifecycleState)
    lifecycle:ApplyDifficultyObjectives(lifecycleState)
    lifecycle:ApplyTurboToAll(lifecycleState)

    for h in AllCraft() do
        SetObjectiveOff(h)
    end

    --TestEXU()
end

function PostLoad()
    RefreshHandlesAfterLoad()
    lifecycle:Load(lifecycleState, pending_ai_data)
    pending_ai_data = nil
    load_pending = false
    load_grace_until = GetTime() + 2.0
end

-- AddObject function: Called when a game object is added
function AddObject(h)
    local team = GetTeamNum(h)
    local odf = GetOdf(h)
    if odf then odf = string.gsub(odf, "%z", "") end

    lifecycle:OnObjectCreated(lifecycleState, h)

    if team == 1 and odf == "avscav" and bscav == nil then
        found = true
        bscav = h
        if SetLabel then SetLabel(bscav, LABEL_BSCAV) end
        SetCritical(bscav, true)
        SetObjectiveOn(bscav)

        -- Difficulty-based behavior for dummy tank
        local d = DiffUtils.Get().index
        if d < 2 and IsAlive(dummy) and not camera1 and not camera2 and not camera3 then
            Follow(dummy, bscav)
        end
    end

    if team == 2 and odf == "svfigh" then
        if not found2 then
            found2 = true
            bscout = h
            if SetLabel then SetLabel(bscout, LABEL_BSCOUT) end
            Goto(bscout, "patrol1")
            SetObjectiveOn(bscout)
        else
            if IsAlive(bscav) and IsAlive(bgoal) and GetDistance(bscav, bgoal) < 200.0 then
                Attack(h, bscav)
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
        if register then aiCore.AddObject(h) end
    end
end

-- Update function: Called every frame
function Update()
    if load_pending then
        return
    end
    if GetTime() < load_grace_until then
        return
    end
    local player = GetPlayerHandle()
    aiCore.Update()
    lifecycle:Update(lifecycleState, 1.0 / 20.0)

    -- Holographic Bio Logic
    if (camera1 or camera2 or camera3) and GetTime() >= bio_timer then
        --if IsAlive(player) then
        -- Spawns the holographic bio above the player
        local pos = GetPosition(player)
        pos.y = pos.y + 10.0
        MakeExplosion("xbio", pos)
        -- end
        bio_timer = GetTime() + 10.0
    end

    if not start_done then
        local playerTeam, enemyTeam = DiffUtils.SetupTeams(aiCore.Factions.NSDF, aiCore.Factions.CCA, 2)
        playerTeam:SetConfig("manageFactories", false)
        playerTeam:SetConfig("autoRepairWingmen", PersistentConfig.Settings.AutoRepairWingmen)
        playerTeam:SetConfig("enableParatroopers", false)
        enemyTeam:SetConfig("enableParatroopers", false)

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
        lifecycle:ApplyQOL()

        SetPilot(1, math.max(1, DiffUtils.ScaleRes(2)))
        SetScrap(1, math.max(4, DiffUtils.ScaleRes(5)))
        SetAIP("misn02.aip")

        dummy = GetHandle("fake_player")
        lander = GetHandle("avland0_wingman")
        bhandle = GetHandle("sscr_171_scrap")
        bhome = GetHandle("abcomm1_i76building")
        recycler = GetHandle("avrecy-1_recycler")
        bgoal = GetHandle("apscrap-1_camerapod")
        bhandle2 = GetHandle("sscr_176_scrap")

        SetUserTarget(bgoal)
        SetObjectiveName(bgoal, "Scrap Field Alpha")
        --SetObjectiveName(recycler, "Recycler Montana")
        start_done = true
        subtit.Initialize("durations.csv")

        -- Establish alliance between player (team 1) and dummy tank (team 5)
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

        camera1 = true
        cam_time = GetTime() + 30.0
        CameraReady()
        audmsg = subtit.Play("misn0230.wav")
        --audmsg = subtit.Play("misn0201.wav")
    end

    -- Camera Logic
    if camera1 then
        if CameraPath("fixcam", 1200, 250, lander) or CameraCancelled() or AudioDone(audmsg) then
            -- Stop audio and subtitles if skipped
            if CameraCancelled() then
                subtit.Stop()
                intro_skipped = true
                audmsg = nil
            end
            camera1 = false
            cam_time = GetTime() + 10.0
            camera2 = true
        end
    end

    if camera2 then
        camera2 = false
        camera3 = true
        if IsAlive(dummy) then
            Goto(dummy, "player_path")
        end
        cam_time = GetTime() + 25.0
    end

    if camera3 then
        if CameraPath("zoomcam", 1200, 800, dummy) or AudioDone(audmsg) or CameraCancelled() then
            camera3 = false
            cam_time = 99999.0
            CameraFinish()

            -- Reassign dummy tank instead of removing it
            if IsAlive(dummy) then
                SetTeamNum(dummy, 5) -- Set to team 5
                Ally(1, 5)           -- Make teams 1 and 5 allies

                local d = DiffUtils.Get().index
                if d < 2 and IsAlive(bscav) then
                    Follow(dummy, bscav)
                elseif IsAlive(recycler) then
                    Defend2(dummy, recycler, 0) -- Set to defend the recycler
                end
            end

            --SetPosition(player, "playermove")
            -- Stop previous audio if the user skipped the cinematic, then start the next one
            if CameraCancelled() or intro_skipped then
                subtit.Stop()
                intro_skipped = true
            end

            if not intro_skipped then
                audmsg = subtit.Play("misn0201.wav")
            end
            --subtit.Play("misn0224.wav")
            wave_timer = GetTime() + DiffUtils.ScaleTimer(30.0)
            AddObjective("misn02b1.otf", "white")
        end
    end

    -- Patrol 1 Logic
    if not patrol1 and found and IsAlive(bhandle) and IsAlive(bscav) and GetDistance(bhandle, bscav) < 75.0 then
        for i = 1, DiffUtils.ScaleEnemy(1) do BuildObject("svfigh", 2, "spawn1") end

        subtit.Play("misn0233.wav")
        message1 = true
        patrol1 = true

        if not message4 and found2 then
            message4 = true
        end
    end

    if not message4 and found2 then
        message4 = true
    end

    -- Capture pre-placed units if start_done just flipped
    if start_done and not bootstrap_done then
        aiCore.Bootstrap()
        bootstrap_done = true
    end

    -- Wave Logic
    if message4 and not message5 and IsAlive(bscav) and IsAlive(bhandle2) and GetDistance(bscav, bhandle2) < 200.0 then
        BuildObject("svfigh", 2, "spawn2")
        message5 = true
        wave_timer = GetTime() + 30.0
    end

    if message5 and not message3 and GetTime() > wave_timer then
        for i = 1, DiffUtils.ScaleEnemy(1) do BuildObject("svfigh", 2, "spawn2") end
        wave_timer = GetTime() + DiffUtils.ScaleTimer(45.0)
    end

    -- Retreat Logic
    if message1 and message5 and not message2 and IsAlive(bscav) and GetLastEnemyShot(bscav) > 0 then
        Follow(bscav, bhome)
        ClearObjectives()
        AddObjective("misn02b2.otf", "white")
        subtit.Play("misn0225.wav")
        local bbase = GetHandle("apbase-1_camerapod")
        SetUserTarget(bbase)
        message2 = true
    end

    -- Loss Condition
    if bscav ~= nil and not mission_lost then
        if not IsAlive(player) or not IsAlive(bscav) or (message3 and not IsAlive(scav2)) or not IsAlive(bhome) or not IsAlive(recycler) then
            ClearObjectives()
            AddObjective("misn02b4.otf", "red")
            audmsg = subtit.Play("misn0227.wav")
            mission_lost = true
        end
    end

    if mission_lost and AudioDone(audmsg) then
        FailMission(GetTime(), "misn02l1.des")
    end

    -- Rescue Logic
    if IsAlive(player) and message1 and message4 and IsAlive(bhome) and IsAlive(bscav) and GetDistance(bhome, bscav) < 300.0 and not message3 then
        Follow(bscav, bhome)
        wave_timer = GetTime() + 45.0
        scav2 = BuildObject("avscav", 1, "spawn3")
        if SetLabel then SetLabel(scav2, LABEL_SCAV2) end
        SetCritical(scav2, true)
        Retreat(scav2, "retreat")
        SetObjectiveOn(scav2)
        SetObjectiveOff(bscav)
        subtit.Play("misn0228.wav")
        last_wave_time = GetTime() + 10.0
        NextSecond = GetTime() + 1.0
        message3 = true

        -- Dummy tank follow scav2 logic for lower difficulties
        local d = DiffUtils.Get().index
        if d < 2 and IsAlive(dummy) then
            Follow(dummy, scav2)
        end

        -- Flanking Ambush: Spawn enemies behind the player at spawn1
        for i = 1, DiffUtils.ScaleEnemy(1) do
            local h = BuildObject("svfigh", 2, "spawn1")
            Attack(h, scav2)
        end
    end

    -- Health Regen
    if IsAlive(bscav) and message3 and GetTime() > NextSecond then
        AddHealth(bscav, 200.0)
        NextSecond = GetTime() + 1.0
    end

    -- Final Wave
    if last_wave_time < GetTime() then
        for i = 1, DiffUtils.ScaleEnemy(1) do
            local sid = BuildObject("svfigh", 2, "spawn4")
            if IsAlive(scav2) then Attack(sid, scav2) end
        end
        last_wave_time = 99999.0
    end

    -- Win Condition
    if message3 and not mission_won and IsAlive(bhome) and IsAlive(scav2) and GetDistance(bhome, scav2) < 200.0 then
        ClearObjectives()
        SetObjectiveOff(scav2)
        if IsAlive(bscav) then SetObjectiveOff(bscav) end
        AddObjective("misn02b3.otf", "green")
        if IsAlive(bscav) then AddHealth(bscav, 1000.0) end
        if IsAlive(scav2) then AddHealth(scav2, 1000.0) end
        audmsg = subtit.Play("misn0234.wav")
        mission_won = true
    end

    if mission_won and AudioDone(audmsg) then
        SucceedMission(GetTime(), "misn02w1.des")
    end
end
