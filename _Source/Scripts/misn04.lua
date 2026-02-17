-- Misn04 Mission Script (Converted from Misn04Mission.cpp)

-- Compatibility for 1.5
SetLabel = SetLabel or SetLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({ "campaignReimagined", "3659600763" })
local exu = require("exu")
local aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")
local subtit = require("ScriptSubtitles")
local PersistentConfig = require("PersistentConfig")

-- Helper for AI
local function SetupAI()
    DiffUtils.SetupTeams(aiCore.Factions.NSDF, aiCore.Factions.CCA, 2)

    -- Configure Player Team (1) for Scavenger Assist
    -- Configure Player Team (1) for Scavenger Assist
    if aiCore.ActiveTeams and aiCore.ActiveTeams[1] then
        aiCore.ActiveTeams[1]:SetConfig("scavengerAssist", PersistentConfig.Settings.ScavengerAssistEnabled)
        aiCore.ActiveTeams[1]:SetConfig("manageFactories", false)
        aiCore.ActiveTeams[1]:SetConfig("autoRepairWingmen", PersistentConfig.Settings.AutoRepairWingmen)
    end

    -- Configure CCA (Team 2)
    if aiCore and aiCore.ActiveTeams and aiCore.ActiveTeams[2] then
        local cca = aiCore.ActiveTeams[2]
        cca:SetMaintainList(
            { scout = 2, scavenger = 4, constructor = 1 },                    -- Recycler
            { tank = 1, lighttank = 1, rockettank = 1, apc = 1, turret = 6 }, -- Factory
            true                                                              -- Locked
        )

        -- Fully Automate Base and Units
        cca.Config.autoManage = true
        cca.Config.autoBuild = true
        cca.Config.manageFactories = true
        cca.Config.manageConstructor = true
        cca.Config.resourceBoost = true
        cca.Config.minScavengers = 4
        cca.Config.requireConstructorFirst = true

        -- High-level Base Planning
        cca:PlanDefensivePerimeter(2, 1) -- 2 powers, 1 tower each (Interleaved)

        -- ExpandBase will automatically handle Barracks, Supply, Comm, Hangar, and HQ over time.
        -- We just need to plan the optimal Silo location since it's terrain-dependent.
        local siloPos = cca:FindOptimalSiloLocation(200, 350)
        if siloPos then
            cca:AddBuilding(aiCore.Units[cca.faction].silo, siloPos, 5)
        end
    end
end

-- Variables
local M = {
    missionstart = false,
    warn = 0,
    safety = 0,
    retreat = false,
    surveysent = false,
    reconsent = false,
    firstwave = false,
    secondwave = false,
    thirdwave = false,
    fourthwave = false,
    fifthwave = false,
    discrelic = false,
    ccatugsent = false,
    attackccabase = false,
    ccabasedestroyed = false,
    fifthwavedestroyed = false,
    missionend = false,
    wavenumber = 1,
    missionwon = false,
    wave1dead = false,
    wave2dead = false,
    wave3dead = false,
    wave4dead = false,
    wave5dead = false,
    possiblewin = false,
    loopbreak = false,
    basesecure = false,
    newobjective = false,
    relicsecure = false,
    discoverrelic = false,
    missionfail2 = false,
    aud10 = nil,
    aud11 = nil,
    aud12 = nil,
    aud13 = nil,
    aud14 = nil,
    ccahasrelic = false,
    relicseen = false,
    obset = false,
    wave1 = 0,
    wave2 = 99999.0,
    wave3 = 99999.0,
    wave4 = 99999.0,
    wave5 = 99999.0,
    endcindone = 999999.0,
    startendcin = 999999.0,
    ccatug = 999999999999.0,
    notfound = 999999999999999.0,
    build2 = false,
    build3 = false,
    build4 = false,
    build5 = false,
    halfway = false,

    -- Handles (init to nil)
    svrec = nil,
    pu1 = nil,
    pu2 = nil,
    pu3 = nil,
    pu4 = nil,
    pu5 = nil,
    pu6 = nil,
    pu7 = nil,
    pu8 = nil,
    navbeacon = nil,
    cheat1 = nil,
    cheat2 = nil,
    cheat3 = nil,
    cheat4 = nil,
    cheat5 = nil,
    cheat6 = nil,
    cheat7 = nil,
    cheat8 = nil,
    cheat9 = nil,
    cheat10 = nil,
    tug = nil,
    svtug = nil,
    tuge1 = nil,
    tuge2 = nil,
    player = nil,
    surv1 = nil,
    surv2 = nil,
    surv3 = nil,
    surv4 = nil,
    cam1 = nil,
    cam2 = nil,
    cam3 = nil,
    basecam = nil,
    reliccam = nil,
    avrec = nil,
    w1u1 = nil,
    w1u2 = nil,
    w2u1 = nil,
    w2u2 = nil,
    w2u3 = nil,
    w3u1 = nil,
    w3u2 = nil,
    w3u3 = nil,
    w3u4 = nil,
    w4u1 = nil,
    w4u2 = nil,
    w4u3 = nil,
    w4u4 = nil,
    w4u5 = nil,
    w5u1 = nil,
    w5u2 = nil,
    w5u3 = nil,
    w5u4 = nil,
    w5u5 = nil,
    w5u6 = nil,
    spawn1 = nil,
    spawn2 = nil,
    spawn3 = nil,
    relic = nil,
    calipso = nil,
    turret1 = nil,
    turret2 = nil,
    turret3 = nil,
    turret4 = nil,

    aud1 = nil,
    aud2 = nil,
    aud3 = nil,
    aud4 = nil,
    aud20 = nil,
    aud21 = nil,
    aud22 = nil,
    aud23 = nil,

    doneaud20 = false,
    doneaud21 = false,
    doneaud22 = false,
    doneaud23 = false,
    done = false,
    secureloopbreak = false,
    found = false,
    endcinfinish = false,
    loopbreak2 = false,
    investigate = 999999999.0,
    investigator = 0,
    tur1 = 999999999.0,
    tur2 = 999999999.0,
    tur3 = 999999999.0,
    tur4 = 999999999.0,
    tur1sent = false,
    tur2sent = false,
    tur3sent = false,
    tur4sent = false,
    cin1done = false,
    missionfail = false,
    chewedout = false,
    relicmoved = false,
    height = 500,
    cintime1 = 9999999999.0,
    fetch = 0,
    reconcca = 0,
    relicstartpos = 0,
    cheater = false,

    cin_started = false,
    difficulty = 2 -- Default Medium
}

-- Helper for Difficulty-Scaled Tug Arrival
local function GetTugDelay()
    local baseDelay = 180.0 -- Medium (Default)
    if M.difficulty >= 4 then
        return 0.0          -- Very Hard: Immediate
    elseif M.difficulty == 3 then
        baseDelay = 60.0    -- Hard
    elseif M.difficulty == 1 then
        baseDelay = 300.0   -- Easy
    elseif M.difficulty == 0 then
        baseDelay = 450.0   -- Very Easy
    end
    return DiffUtils.ScaleTimer(baseDelay)
end

-- EXU/QOL Persistence Helper
function ApplyQOL()
    if not exu then return end

    if exu.SetShotConvergence then exu.SetShotConvergence(true) end
    if exu.SetReticleRange then exu.SetReticleRange(600) end
    if exu.SetOrdnanceVelocInheritance then exu.SetOrdnanceVelocInheritance(true) end

    -- Initialize Persistent Config
    PersistentConfig.Initialize()
end

function Start()
    M.TPS = 20 -- Default TPS value

    -- One-time initialization logic
    M.relicstartpos = math.random(0, 3)

    -- EXU/QOL Setup
    if exu then
        local ver = (type(exu["GetVersion"]) == "function" and exu["GetVersion"]()) or exu["version"] or "Unknown"
        print("EXU Version: " .. tostring(ver))
        M.difficulty = (exu.GetDifficulty and exu.GetDifficulty()) or 2
        print("Difficulty: " .. tostring(M.difficulty))

        if M.difficulty >= 3 then
            AddObjective("hard_diff", "yellow", 8.0, "High Difficulty: Enemy presence intensified.")
        elseif M.difficulty <= 1 then
            AddObjective("easy_diff", "blue", 8.0, "Low Difficulty: Enemy presence reduced.")
        end

        ApplyQOL()
    end

    -- Initialize AI for enemy team
    SetupAI()

    -- Dynamic Starting Resources
    SetScrap(1, DiffUtils.ScaleRes(40)) -- Increased base scrap
    SetPilot(1, DiffUtils.ScaleRes(10))

    aiCore.Bootstrap() -- Capture pre-placed units/buildings

    subtit.Initialize()
end

-- Save/Load removed from here, moving logic to bottom functions

function AddObject(h)
    local team = GetTeamNum(h)
    local prod = IsOdf(h, "factory")
    local nearBase = false

    -- Filter logic for AI
    if team == 2 then
        -- Only add if near base
        if M.svrec and IsAlive(M.svrec) and GetDistance(h, M.svrec) < 400.0 then
            nearBase = true
        elseif GetDistance(h, "cca_base") < 400.0 then
            nearBase = true
        end

        if nearBase then
            aiCore.AddObject(h)
        end
    elseif team == 1 then
        aiCore.AddObject(h)
    end

    -- TURBO Logic (Hard+)
    if exu and M.difficulty >= 2 and team == 2 and IsOdf(h, "vehicle") then
        exu.SetUnitTurbo(h, true) -- speed boost for enemy units
    end

    -- Capture Player Tug for Audio (Corrected to avhaul per C++)
    if team == 1 and IsOdf(h, "avhaul") then
        M.tug = h
    end
end

function DeleteObject(h)
    -- No specific logic in C++, just standard.
end

function Update()
    -- void Misn04Mission::Execute(void) logic

    M.player = GetPlayerHandle()
    if exu and exu["UpdateOrdnance"] then exu["UpdateOrdnance"]() end

    aiCore.Update()
    subtit.Update()
    PersistentConfig.UpdateInputs()
    PersistentConfig.UpdateHeadlights()

    if (not M.missionstart) then
        M.wave1 = GetTime() + DiffUtils.ScaleTimer(30.0) + math.random(-5, 10)
        M.fetch = GetTime() + DiffUtils.ScaleTimer(240.0)
        subtit.Play("misn0401.wav")
        M.cam1 = GetHandle("apcamr352_camerapod")
        M.cam2 = GetHandle("apcamr350_camerapod")
        M.cam3 = GetHandle("apcamr351_camerapod")
        M.basecam = GetHandle("apcamr-1_camerapod")
        M.svrec = GetHandle("svrecy-1_recycler")
        M.avrec = GetHandle("avrecy-1_recycler")
        M.relic = BuildObject("obdata", 0, "relicstart1")
        M.pu1 = GetHandle("svfigh-1_wingman")
        -- pu2 commented out in C++
        M.pu3 = GetHandle("svfigh282_wingman")
        -- pu4, pu5 commented out
        M.pu6 = GetHandle("svfigh279_wingman")
        -- pu7 commented out
        M.pu8 = GetHandle("svfigh278_wingman")

        SetObjectiveName(M.cam1, "SW Geyser")
        SetObjectiveName(M.cam2, "NW Geyser")
        SetObjectiveName(M.cam3, "NE Geyser")
        SetObjectiveName(M.basecam, "CCA Base")

        Patrol(M.pu1, "innerpatrol")
        Patrol(M.pu3, "innerpatrol")
        Patrol(M.pu6, "outerpatrol")
        Patrol(M.pu8, "scouting")

        AddObjective("misn0401.otf", "white")
        AddObjective("misn0400.otf", "white")

        M.missionstart = true
        M.cheater = false
        -- relicstartpos already set in Start() to random

        M.tur1 = GetTime() + DiffUtils.ScaleTimer(30.0)
        M.tur2 = GetTime() + DiffUtils.ScaleTimer(45.0) + math.random(0, 5)
        M.tur3 = GetTime() + DiffUtils.ScaleTimer(60.0) + math.random(5, 10)
        M.tur4 = GetTime() + DiffUtils.ScaleTimer(75.0) + math.random(10, 15)
        M.investigate = GetTime() + 3.0
    end



    AddHealth(M.cam1, 1000)
    AddHealth(M.cam2, 1000)
    AddHealth(M.cam3, 1000)

    -- Relic placement
    if (not M.relicmoved) then
        if M.relicstartpos == 0 then
            SetPosition(M.relic, "relicstart1")
        elseif M.relicstartpos == 1 then
            SetPosition(M.relic, "relicstart2")
        elseif M.relicstartpos == 2 then
            SetPosition(M.relic, "relicstart3")
        elseif M.relicstartpos == 3 then
            SetPosition(M.relic, "relicstart4")
        end
        M.relicmoved = true
    end

    -- Cheater spawns (player finds relic early)
    if (not M.reconsent) and (not M.cheater) and (GetDistance(M.player, M.relic) < 600.0) then
        M.cheat1 = BuildObject("svfigh", 2, M.relic)
        M.cheat2 = BuildObject("svfigh", 2, M.relic)
        M.cheat3 = BuildObject("svfigh", 2, M.relic)
        M.cheat4 = BuildObject("svfigh", 2, M.relic)
        M.cheat5 = BuildObject("svfigh", 2, M.relic)
        M.cheat6 = BuildObject("svfigh", 2, M.relic)

        local pathA, pathB = "", ""
        if M.relicstartpos == 0 then
            pathA = "relicpatrolpath1a"
            pathB = "relicpatrolpath1b"
        elseif M.relicstartpos == 1 then
            pathA = "relicpatrolpath2a"
            pathB = "relicpatrolpath2b"
        elseif M.relicstartpos == 2 then
            pathA = "relicpatrolpath3a"
            pathB = "relicpatrolpath3b"
        elseif M.relicstartpos == 3 then
            pathA = "relicpatrolpath4a"
            pathB = "relicpatrolpath4b"
        end

        Patrol(M.cheat1, pathA)
        Patrol(M.cheat2, pathA)
        Patrol(M.cheat3, pathA)
        Patrol(M.cheat4, pathB)
        Patrol(M.cheat5, pathB)
        Patrol(M.cheat6, pathB)

        for i = 1, DiffUtils.ScaleEnemy(6) - 6 do
            local path = (i % 2 == 0) and pathA or pathB
            local h = BuildObject("svfigh", 2, M.relic)
            Patrol(h, path)
            SetIndependence(h, 1)
        end

        SetIndependence(M.cheat1, 1)
        SetIndependence(M.cheat2, 1)
        SetIndependence(M.cheat3, 1)
        SetIndependence(M.cheat4, 1)
        SetIndependence(M.cheat5, 1)
        SetIndependence(M.cheat6, 1)

        M.surveysent = true
        M.cheater = true
        M.reconcca = GetTime() -- Immediate recon
    end

    -- Survey sent logic (timed)
    if (M.fetch < GetTime()) and (not M.surveysent) then
        M.surv1 = BuildObject("svfigh", 2, M.relic)
        M.surv2 = BuildObject("svfigh", 2, M.relic)

        local pathA, pathB = "", ""
        if M.relicstartpos == 0 then
            pathA = "relicpatrolpath1a"
            pathB = "relicpatrolpath1b"
        elseif M.relicstartpos == 1 then
            pathA = "relicpatrolpath2a"
            pathB = "relicpatrolpath2b"
        elseif M.relicstartpos == 2 then
            pathA = "relicpatrolpath3a"
            pathB = "relicpatrolpath3b"
        elseif M.relicstartpos == 3 then
            pathA = "relicpatrolpath4a"
            pathB = "relicpatrolpath4b"
        end

        Patrol(M.surv1, pathA)
        Patrol(M.surv2, pathB)
        SetIndependence(M.surv1, 1)
        SetIndependence(M.surv2, 1)

        for i = 1, DiffUtils.ScaleEnemy(2) - 2 do
            local path = (i % 2 == 0) and pathA or pathB
            local h = BuildObject("svfigh", 2, M.relic)
            Patrol(h, path)
            SetIndependence(h, 1)
        end

        M.surveysent = true
        M.reconcca = GetTime() + DiffUtils.ScaleTimer(60.0)
    end

    -- Turret spawning logic
    if (not M.tur1sent) and (M.tur1 < GetTime()) and IsAlive(M.svrec) then
        M.turret1 = BuildObject("svturr", 2, M.svrec)
        Goto(M.turret1, "turret1")
        M.tur1sent = true
    end
    if (not M.tur2sent) and (M.tur2 < GetTime()) and IsAlive(M.svrec) then
        M.turret2 = BuildObject("svturr", 2, M.svrec)
        Goto(M.turret2, "turret2")
        M.tur2sent = true
    end
    if (not M.tur3sent) and (M.tur3 < GetTime()) and IsAlive(M.svrec) then
        M.turret3 = BuildObject("svturr", 2, M.svrec)
        Goto(M.turret3, "turret3")
        M.tur3sent = true
    end
    if (not M.tur4sent) and (M.tur4 < GetTime()) and IsAlive(M.svrec) then
        M.turret4 = BuildObject("svturr", 2, M.svrec)
        Goto(M.turret4, "turret4")
        M.tur4sent = true
    end

    -- Recon CCA Logic
    if (M.reconcca < GetTime()) and (not M.reconsent) and (M.surveysent) then
        M.aud4 = subtit.Play("misn0406.wav")
        if M.relicstartpos == 0 then
            M.reliccam = BuildObject("apcamr", 1, "reliccam1")
        elseif M.relicstartpos == 1 then
            M.reliccam = BuildObject("apcamr", 1, "reliccam2")
        elseif M.relicstartpos == 2 then
            M.reliccam = BuildObject("apcamr", 1, "reliccam3")
        elseif M.relicstartpos == 3 then
            M.reliccam = BuildObject("apcamr", 1, "reliccam4")
        end

        M.reconsent = true
        M.obset = true
        M.notfound = GetTime() + 90.0
    end

    if (M.obset) and IsAudioMessageDone(M.aud4) then
        SetObjectiveName(M.reliccam, "Investigate CCA")
        M.newobjective = true
        M.obset = false
    end

    -- Found relic logic
    if (M.found) and (not M.halfway) then
        if HasCargo(M.tug) then
            subtit.Play("misn0419.wav")
            M.halfway = true
            SetObjectiveOff(M.relic)
            if IsAlive(M.tuge1) then Attack(M.tuge1, M.tug) end
            if IsAlive(M.tuge2) then Attack(M.tuge2, M.tug) end
        end
    end

    -- Relic secure check (delivered to recycler)
    if (M.reconsent) then
        if (GetDistance(M.relic, M.avrec) < 100.0) and (not M.relicsecure) then
            M.aud23 = subtit.Play("misn0420.wav")
            M.relicsecure = true
            M.newobjective = true
        end
    end

    -- CCA Tug Logic
    if (M.ccatug < GetTime()) and (not M.ccatugsent) and IsAlive(M.svrec) then
        M.svtug = BuildObject("svhaul", 2, M.svrec)
        M.tuge1 = BuildObject("svfigh", 2, M.svrec)
        M.tuge2 = BuildObject("svfigh", 2, M.svrec)

        for i = 1, DiffUtils.ScaleEnemy(2) - 2 do
            local h = BuildObject("svfigh", 2, M.svrec)
            Attack(h, M.player, 1) -- Focus on player to protect tug
            SetIndependence(h, 1)
        end
        Pickup(M.svtug, M.relic)
        Follow(M.tuge1, M.svtug)
        Follow(M.tuge2, M.svtug)
        M.ccatugsent = true
    end

    if (M.ccatugsent) and (not M.ccahasrelic) then
        if IsAlive(M.svtug) then
            if HasCargo(M.svtug) and (not HasCargo(M.tug)) then
                M.ccahasrelic = true
                Goto(M.svtug, "dropoff")
                subtit.Play("misn0427.wav")
                SetObjectiveOn(M.svtug)
                SetObjectiveName(M.svtug, "CCA Tug")
            end
        end
    end

    if (M.ccahasrelic) and (GetDistance(M.svtug, M.svrec) < 60.0) and (not M.missionfail2) then
        M.aud10 = subtit.Play("misn0431.wav")
        M.aud11 = subtit.Play("misn0432.wav")
        M.aud12 = subtit.Play("misn0433.wav")
        M.aud13 = subtit.Play("misn0434.wav")
        M.missionfail2 = true
        CameraReady()
    end

    if (M.missionfail2) and (not M.done) then
        CameraPath("ccareliccam", 3000, 1000, M.svtug)
        if (IsAudioMessageDone(M.aud10) and IsAudioMessageDone(M.aud11) and IsAudioMessageDone(M.aud12) and IsAudioMessageDone(M.aud13)) or CameraCancelled() then
            CameraFinish()
            -- Only stop subtitles if the user skipped the cinematic
            if CameraCancelled() then
                subtit.Stop()
            end
            FailMission(GetTime(), "misn04l1.des")
            M.done = true
        end
    end

    -- Warning logic if not found
    if (not M.discoverrelic) and (M.reconsent) and (M.notfound < GetTime()) and (not M.ccahasrelic) and (M.warn < 4) then
        subtit.Play("misn0429.wav")
        M.notfound = GetTime() + DiffUtils.ScaleTimer(85.0)
        M.warn = M.warn + 1
    end

    if (M.warn == 4) and (M.notfound < GetTime()) and (not M.missionfail) then
        M.aud14 = subtit.Play("misn0694.wav")
        M.missionfail = true
    end
    if (M.missionfail) then
        if (M.warn == 4) and IsAudioMessageDone(M.aud14) then
            FailMission(GetTime(), "misn04l4.des")
            M.warn = 0
        end
    end

    -- Discover Relic logic (Investigator count)
    if (not M.discoverrelic) then
        -- Calipso Logic (Restored from C++ lines 448-468)
        -- Checks if an AI teammate finds the relic first
        local calipso = GetNearestVehicle(M.relic)
        if IsAlive(calipso) then
            if (GetTeamNum(calipso) == 1) and (GetDistance(M.relic, calipso) <= 500.0) and (calipso ~= M.player) then
                subtit.Play("misn0407.wav") -- "I've found something..."

                -- Shared discovery logic
                M.relicseen = true
                M.newobjective = true
                M.ccatug = GetTime() + GetTugDelay() + math.random(-5, 10)
                M.discoverrelic = true
                CameraReady()
                M.cintime1 = GetTime() + 23.0
            end
        end
    end

    if (not M.discoverrelic) then
        if (M.investigate < GetTime()) then
            M.investigator = CountUnitsNearObject(M.relic, 400.0, 1, "")
            if IsAlive(M.reliccam) then
                M.investigator = M.investigator - 1
            end
        end

        if (M.investigator >= 1) then
            M.aud2 = subtit.Play("misn0408.wav")
            M.aud3 = subtit.Play("misn0409.wav")
            M.relicseen = true
            M.newobjective = true
            M.ccatug = GetTime() + GetTugDelay() + math.random(-5, 10)
            M.discoverrelic = true
            CameraReady()
            M.cintime1 = GetTime() + 23.0

            -- Set user target to relic for visibility
            SetUserTarget(M.relic)
        end
    end

    if (M.discoverrelic) and (not M.cin1done) then
        if (M.discoverrelic and IsAudioMessageDone(M.aud2) and IsAudioMessageDone(M.aud3)) or CameraCancelled() then
            CameraFinish()
            -- Only stop subtitles if the user skipped the cinematic
            if CameraCancelled() then
                subtit.Stop()
            end
            M.cin1done = true
        end
    end

    if (M.discoverrelic) and (M.cintime1 > GetTime()) and (not M.cin1done) then
        if M.relicstartpos == 0 then
            CameraPath("reliccin1", 500, 400, M.relic)
        elseif M.relicstartpos == 1 then
            CameraPath("reliccin2", 500, 400, M.relic)
        elseif M.relicstartpos == 2 then
            CameraPath("reliccin3", 500, 400, M.relic)
        elseif M.relicstartpos == 3 then
            CameraPath("reliccin4", 500, 400, M.relic)
        end
    end

    -- Objective Updates
    if (M.newobjective) then
        ClearObjectives()
        if (not M.basesecure) then AddObjective("misn0401.otf", "white") end
        if (M.basesecure) then AddObjective("misn0401.otf", "green") end

        if (not M.relicsecure) and (M.relicseen) then AddObjective("misn0403.otf", "white") end
        if (M.relicsecure) then AddObjective("misn0403.otf", "green") end

        if (M.reconsent) and (not M.discoverrelic) then AddObjective("misn0405.otf", "white") end
        if (M.discoverrelic) then AddObjective("misn0405.otf", "green") end

        M.newobjective = false
    end

    -- Wave Logic
    if (M.wavenumber == 1) then
        -- Just checking liveness (noop in C++)
    end

    if (M.wavenumber == 1) and (GetTime() > M.wave1) then
        M.w1u1 = BuildObject("svfigh", 2, "wave1")
        M.w1u2 = BuildObject("svfigh", 2, "wave1")
        Attack(M.w1u1, M.avrec, 1)
        Attack(M.w1u2, M.avrec, 1)

        for i = 1, DiffUtils.ScaleEnemy(2) - 2 do
            local h = BuildObject("svfigh", 2, "wave1"); Attack(h, M.avrec, 1); SetIndependence(h, 1)
        end

        SetIndependence(M.w1u1, 1)
        SetIndependence(M.w1u2, 1)
        M.wavenumber = 2
        M.wave1arrive = false
    end

    if (M.wavenumber == 2) and (not IsAlive(M.w1u1)) and (not IsAlive(M.w1u2)) and (not M.build2) then
        M.wave2 = GetTime() + DiffUtils.ScaleTimer(60.0) + math.random(-5, 5)
        M.build2 = true
        M.wave1dead = true
    end

    if (M.wave2 < GetTime()) and IsAlive(M.svrec) then
        local type2 = "svltnk"
        if M.difficulty <= 1 then type2 = "svfigh" end

        M.w2u1 = BuildObject(type2, 2, "spawn2new")
        M.w2u2 = BuildObject("svfigh", 2, "spawn2new")
        Goto(M.w2u1, M.avrec, 1)
        Goto(M.w2u2, M.avrec, 1)
        SetIndependence(M.w2u1, 1)
        SetIndependence(M.w2u2, 1)

        for i = 1, DiffUtils.ScaleEnemy(2) - 2 do
            local h = BuildObject("svfigh", 2, "spawn2new")
            Goto(h, M.avrec, 1)
            SetIndependence(h, 1)
        end
        M.wavenumber = 3
        M.wave2arrive = false
        M.wave2 = 99999.0
    end

    if (M.wavenumber == 3) and (not IsAlive(M.w2u1)) and (not IsAlive(M.w2u2)) and (not M.build3) then
        M.wave3 = GetTime() + DiffUtils.ScaleTimer(74.0) + math.random(-10, 10)
        M.build3 = true
        M.wave2dead = true
    end

    if (M.wave3 < GetTime()) and IsAlive(M.svrec) then
        local type3 = "svfigh"
        if M.difficulty >= 2 then type3 = "svltnk" end

        M.w3u1 = BuildObject(type3, 2, M.svrec)
        M.w3u2 = BuildObject("svfigh", 2, M.svrec)
        M.w3u3 = BuildObject("svfigh", 2, M.svrec)
        Goto(M.w3u1, M.avrec, 1)
        Goto(M.w3u2, M.avrec, 1)
        Goto(M.w3u3, M.avrec, 1)
        SetIndependence(M.w3u1, 1)
        SetIndependence(M.w3u2, 1)
        SetIndependence(M.w3u3, 1)

        for i = 1, DiffUtils.ScaleEnemy(3) - 3 do
            local h = BuildObject("svfigh", 2, M.svrec)
            Goto(h, M.avrec, 1)
            SetIndependence(h, 1)
        end
        M.wavenumber = 4
        M.wave3arrive = false
        M.wave3 = 99999.0
    end

    if (M.wavenumber == 4) and (not IsAlive(M.w3u1)) and (not IsAlive(M.w3u2)) and (not IsAlive(M.w3u3)) and (not M.build4) then
        M.wave4 = GetTime() + DiffUtils.ScaleTimer(60.0) + math.random(-5, 5)
        M.build4 = true
        M.wave3dead = true
    end

    if (M.wave4 < GetTime()) and IsAlive(M.svrec) then
        local type4 = "svtank"
        if M.difficulty <= 1 then type4 = "svltnk" end

        M.w4u1 = BuildObject(type4, 2, "spawnotherside")
        M.w4u2 = BuildObject("svfigh", 2, "spawnotherside")
        M.w4u3 = BuildObject("svfigh", 2, "spawnotherside")
        Goto(M.w4u1, M.avrec, 1)
        Goto(M.w4u2, M.avrec, 1)
        Goto(M.w4u3, M.avrec, 1)
        SetIndependence(M.w4u1, 1)
        SetIndependence(M.w4u2, 1)
        SetIndependence(M.w4u3, 1)

        for i = 1, DiffUtils.ScaleEnemy(3) - 3 do
            local h = BuildObject("svfigh", 2, "spawnotherside")
            Goto(h, M.avrec, 1)
            SetIndependence(h, 1)
        end
        M.wavenumber = 5
        M.wave4arrive = false
        M.wave4 = 99999.0
    end

    if (M.wavenumber == 5) and (not IsAlive(M.w4u1)) and (not IsAlive(M.w4u2)) and (not IsAlive(M.w4u3)) and (not M.build5) then
        M.wave5 = GetTime() + DiffUtils.ScaleTimer(30.0) + math.random(-2, 8)
        M.build5 = true
        M.wave4dead = true
    end

    if (M.wave5 < GetTime()) and IsAlive(M.svrec) then
        M.w5u1 = BuildObject("svtank", 2, M.svrec)
        M.w5u2 = BuildObject("svfigh", 2, M.svrec)
        M.w5u3 = BuildObject("svfigh", 2, M.svrec)
        M.w5u4 = BuildObject("svfigh", 2, M.svrec)
        Goto(M.w5u1, M.avrec, 1)
        Goto(M.w5u2, M.avrec, 1)
        Goto(M.w5u3, M.avrec, 1)
        Goto(M.w5u4, M.avrec, 1)
        SetIndependence(M.w5u1, 1)
        SetIndependence(M.w5u2, 1)
        SetIndependence(M.w5u3, 1)
        SetIndependence(M.w5u4, 1)

        for i = 1, DiffUtils.ScaleEnemy(4) - 4 do
            local h = BuildObject("svfigh", 2, M.svrec)
            Goto(h, M.avrec, 1)
            SetIndependence(h, 1)
        end
        M.wavenumber = 6
        M.wave5arrive = false
        M.wave5 = 99999.0
    end

    -- Wave Arrival Audio
    if (not M.wave1arrive) and IsAlive(M.avrec) then
        if (GetDistance(M.avrec, M.w1u1) < 300.0) or (GetDistance(M.avrec, M.w1u2) < 300.0) then
            subtit.Play("misn0402.wav")
            M.wave1arrive = true
            M.wave1dead = true
        end
    end

    if (not M.wave2arrive) and IsAlive(M.avrec) then
        if (GetDistance(M.avrec, M.w2u1) < 300.0) or (GetDistance(M.avrec, M.w2u2) < 300.0) then
            subtit.Play("misn0404.wav")
            M.wave2arrive = true
        end
    end
    if (not M.wave3arrive) and IsAlive(M.avrec) then
        if (GetDistance(M.avrec, M.w3u1) < 300.0) or (GetDistance(M.avrec, M.w3u2) < 300.0) or (GetDistance(M.avrec, M.w3u3) < 300.0) then
            subtit.Play("misn0410.wav")
            M.wave3arrive = true
        end
    end
    if (not M.wave4arrive) and IsAlive(M.avrec) then
        if (GetDistance(M.avrec, M.w4u1) < 300.0) or (GetDistance(M.avrec, M.w4u2) < 300.0) or (GetDistance(M.avrec, M.w4u3) < 300.0) then
            subtit.Play("misn0412.wav")
            M.wave4arrive = true
        end
    end
    if (not M.wave5arrive) and IsAlive(M.avrec) then
        if (GetDistance(M.avrec, M.w5u1) < 300.0) or (GetDistance(M.avrec, M.w5u2) < 300.0) or (GetDistance(M.avrec, M.w5u3) < 300.0) or (GetDistance(M.avrec, M.w5u4) < 300.0) then
            subtit.Play("misn0414.wav")
            M.wave5arrive = true
        end
    end

    if (not M.attackccabase) and (GetDistance(M.player, M.svrec) < 300.0) then
        subtit.Play("misn0423.wav")
        M.attackccabase = true
    end

    -- Wave Dead Audio
    if (M.wave1dead) and (not IsAlive(M.w1u1)) and (not IsAlive(M.w1u2)) then
        subtit.Play("misn0403.wav")
        M.wave1dead = false
    end
    if (M.wave2dead) then
        subtit.Play("misn0405.wav")
        M.wave2dead = false
    end
    if (M.wave3dead) then
        subtit.Play("misn0411.wav")
        M.wave3dead = false
    end
    if (M.wave4dead) then
        subtit.Play("misn0413.wav")
        M.wave4dead = false
    end

    -- Chewed out logic (all fail)
    if (not M.loopbreak) and (not M.possiblewin) and (not M.missionwon) and (not IsAlive(M.svrec)) then
        subtit.Play("misn0417.wav")
        M.possiblewin = true
        M.chewedout = true

        -- Check if any enemies remain
        if (not IsAlive(M.svrec)) and
            (IsAlive(M.w1u1) or IsAlive(M.w1u2) or IsAlive(M.w2u1) or IsAlive(M.w2u2) or
                IsAlive(M.w3u1) or IsAlive(M.w3u2) or IsAlive(M.w3u3) or
                IsAlive(M.w4u1) or IsAlive(M.w4u2) or IsAlive(M.w4u3) or
                IsAlive(M.w5u1) or IsAlive(M.w5u2) or IsAlive(M.w5u3) or IsAlive(M.w5u4)) then
            subtit.Play("misn0418.wav")
            M.loopbreak = true
        end
    end

    -- Base Secure Logic
    if (not M.basesecure) and (not IsAlive(M.svrec)) and
        (not IsAlive(M.w1u1)) and (not IsAlive(M.w1u2)) and
        (not IsAlive(M.w2u1)) and (not IsAlive(M.w2u2)) and
        (not IsAlive(M.w3u1)) and (not IsAlive(M.w3u2)) and (not IsAlive(M.w3u3)) and
        (not IsAlive(M.w4u1)) and (not IsAlive(M.w4u2)) and (not IsAlive(M.w4u3)) and
        (not IsAlive(M.w5u1)) and (not IsAlive(M.w5u2)) and (not IsAlive(M.w5u3)) and (not IsAlive(M.w5u4)) then
        M.basesecure = true
        M.newobjective = true
    end

    if (M.relicsecure) and (M.basesecure) then
        M.missionwon = true
    end

    if (M.missionwon) and (not M.missionend) then
        if (not M.aud20 or IsAudioMessageDone(M.aud20)) and
            (not M.aud21 or IsAudioMessageDone(M.aud21)) and
            (not M.aud22 or IsAudioMessageDone(M.aud22)) and
            (not M.aud23 or IsAudioMessageDone(M.aud23)) then
            if not M.cin_started then
                CameraReady()
                M.cin_started = true
                -- Play final VO
                M.audmsg = subtit.Play("misn0426.wav")
                -- 15 seconds safety timer for cinematic
                M.startendcin = GetTime() + 15.0
            end

            -- Cinematic Path: endcin, higher speed (1500)
            CameraPath("endcin", 1500, 3000, M.player)

            if CameraCancelled() or (GetTime() > M.startendcin and IsAudioMessageDone(M.audmsg)) then
                CameraFinish()
                if CameraCancelled() then
                    subtit.Stop()
                end
                SucceedMission(GetTime(), "misn04w1.des")
                M.missionend = true
            end
        end
    end

    if (not M.missionwon) and (not IsAlive(M.avrec)) and (not M.missionfail) then
        subtit.Play("misn0421.wav")
        subtit.Play("misn0422.wav")
        M.missionfail = true
        FailMission(GetTime() + 20.0, "misn04l3.des")
    end

    -- Retreat Logic
    if (not M.basesecure) and (not M.secureloopbreak) and (M.wavenumber == 6) and
        (not IsAlive(M.w5u1)) and (not IsAlive(M.w5u2)) and (not IsAlive(M.w5u3)) and (not IsAlive(M.w5u4)) and
        IsAlive(M.svrec) then
        if (not M.retreat) then
            if IsAlive(M.tuge1) then Retreat(M.tuge1, "retreatpoint") end
            if IsAlive(M.tuge2) then Retreat(M.tuge2, "retreatpoint28") end
            if IsAlive(M.pu1) then Retreat(M.pu1, "retreatpoint27") end
            if IsAlive(M.pu2) then Retreat(M.pu2, "retreatpoint26") end
            if IsAlive(M.pu3) then Retreat(M.pu3, "retreatpoint25") end
            if IsAlive(M.pu4) then Retreat(M.pu4, "retreatpoint24") end
            if IsAlive(M.pu5) then Retreat(M.pu5, "retreatpoint23") end
            if IsAlive(M.pu6) then Retreat(M.pu6, "retreatpoint22") end
            if IsAlive(M.pu7) then Retreat(M.pu7, "retreatpoint21") end
            if IsAlive(M.pu8) then Retreat(M.pu8, "retreatpoint20") end
            if IsAlive(M.cheat1) then Retreat(M.cheat1, "retreatpoint19") end
            if IsAlive(M.cheat2) then Retreat(M.cheat2, "retreatpoint18") end
            if IsAlive(M.cheat3) then Retreat(M.cheat3, "retreatpoint17") end
            if IsAlive(M.cheat4) then Retreat(M.cheat4, "retreatpoint16") end
            if IsAlive(M.cheat5) then Retreat(M.cheat5, "retreatpoint15") end
            if IsAlive(M.cheat6) then Retreat(M.cheat6, "retreatpoint14") end
            if IsAlive(M.cheat7) then Retreat(M.cheat7, "retreatpoint13") end
            if IsAlive(M.cheat8) then Retreat(M.cheat8, "retreatpoint12") end
            if IsAlive(M.cheat9) then Retreat(M.cheat9, "retreatpoint11") end
            if IsAlive(M.cheat10) then Retreat(M.cheat10, "retreatpoint10") end
            if IsAlive(M.surv1) then Retreat(M.surv1, "retreatpoint9") end
            if IsAlive(M.surv2) then Retreat(M.surv2, "retreatpoint8") end
            if IsAlive(M.surv3) then Retreat(M.surv3, "retreatpoint7") end
            if IsAlive(M.surv4) then Retreat(M.surv4, "retreatpoint6") end
            if IsAlive(M.turret1) then Retreat(M.turret1, "retreatpoint2") end
            if IsAlive(M.turret2) then Retreat(M.turret2, "retreatpoint3") end
            if IsAlive(M.turret3) then Retreat(M.turret3, "retreatpoint4") end
            if IsAlive(M.turret4) then Retreat(M.turret4, "retreatpoint5") end
            M.retreat = true
        end

        M.aud21 = subtit.Play("misn0415.wav")
        M.aud22 = subtit.Play("misn0416.wav")
        M.basesecure = true
        M.newobjective = true
        M.secureloopbreak = true
    end

    if (not IsAlive(M.relic)) and (not M.missionfail) then
        FailMission(GetTime() + 20.0, "misn04l2.des")
        subtit.Play("misn0431.wav")
        subtit.Play("misn0432.wav")
        subtit.Play("misn0433.wav")
        subtit.Play("misn0434.wav")
        M.missionfail = true
    end

    -- Additional conditions from end of C++ file
    if (not M.basesecure) and (not M.secureloopbreak) and (M.wavenumber == 6) and
        (not IsAlive(M.w5u1)) and (not IsAlive(M.w5u2)) and (not IsAlive(M.w5u3)) and (not IsAlive(M.w5u4)) and
        (not IsAlive(M.svrec)) and (M.chewedout) then
        M.aud20 = subtit.Play("misn0425.wav")
        M.basesecure = true
        M.newobjective = true
        M.secureloopbreak = true
    end
end

function Save()
    return M, aiCore.Save()
end

function Load(missionData, aiData)
    M = missionData
    if aiData then aiCore.Load(aiData) end
    aiCore.Bootstrap() -- Refresh/Capture pre-placed or existing units
    ApplyQOL()         -- Reapply engine settings
    subtit.Initialize()
end
