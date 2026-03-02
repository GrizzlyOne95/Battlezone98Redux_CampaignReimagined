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
local Environment = require("Environment")
local PhysicsImpact = require("PhysicsImpact")
--local autosave = require("AutoSave")

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
            { scavenger = 4, constructor = 1 },               -- Recycler
            { tank = 2, lighttank = 1, apc = 1, turret = 6 }, -- Factory
            true                                              -- Locked
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
        local siloPos = cca:FindOptimalSiloLocation(400, 700)
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
    wave1arrive = false,
    wave2arrive = false,
    wave3arrive = false,
    wave4arrive = false,
    wave5arrive = false,
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
    w1u3 = nil, -- Hard+ extra
    w1u4 = nil, -- Very Hard extra
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

    -- Initialize Environment
    Environment.Init()
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
    SetPilot(1, 10)                     -- Pilots not scaled by difficulty

    aiCore.Bootstrap()                  -- Capture pre-placed units/buildings

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

    -- Environment hook for new units
    Environment.OnObjectCreated(h)

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
    Environment.Update(1.0 / M.TPS)
    subtit.Update()
    -- autosave.Update(1.0 / M.TPS)
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
        SetObjectiveName(M.avrec, "Recycler Montana")
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
        Patrol(M.pu8, "outerpatrol")

        AddObjective("misn0401.otf", "white")
        AddObjective("misn0402.otf", "white")

        M.missionstart = true
    end

    -- Dynamic Health Scaling for Relic (Team 0 buildings are weak)
    if M.relic and IsAlive(M.relic) and GetHealth(M.relic) < 1.0 then
        AddHealth(M.relic, 5.0) -- Regenerate relic so player doesn't accidentally kill it
    end

    -- Check if relic is moved by player or CCA
    if M.relic and IsAlive(M.relic) and not M.relicmoved then
        local p = GetPosition(M.relic)
        if GetDistance(p, "relicstart1") > 10.0 then
            M.relicmoved = true
        end
    end

    -- Cheater logic (skip waves if cheater)
    if (not M.cheater) then
        -- =====================================================================
        -- WAVE SYSTEM: Kill-chain (restored from original C++, difficulty scaled)
        -- Each wave only spawns after ALL units from the previous wave are dead.
        -- Approach audio fires when any unit closes within 300 of the recycler.
        -- Death audio fires when the last unit of a wave is destroyed.
        -- =====================================================================

        -- Wave 1: Timer-based start → 2+ svfigh attack from "wave1" path
        if M.wavenumber == 1 and M.wave1 < GetTime() then
            M.w1u1 = BuildObject("svfigh", 2, "wave1")
            M.w1u2 = BuildObject("svfigh", 2, "wave1")
            Attack(M.w1u1, M.avrec, 1); SetIndependence(M.w1u1, 1)
            Attack(M.w1u2, M.avrec, 1); SetIndependence(M.w1u2, 1)
            if M.difficulty >= 3 then -- Hard: 1 extra fighter
                M.w1u3 = BuildObject("svfigh", 2, "wave1")
                Attack(M.w1u3, M.avrec, 1); SetIndependence(M.w1u3, 1)
            end
            if M.difficulty >= 4 then -- Very Hard: 2nd extra fighter
                M.w1u4 = BuildObject("svfigh", 2, "wave1")
                Attack(M.w1u4, M.avrec, 1); SetIndependence(M.w1u4, 1)
            end
            M.wavenumber = 2
            M.wave1arrive = false
            M.firstwave = true
        end

        -- Wave 1: Approach warning
        if M.wavenumber == 2 and not M.wave1arrive and IsAlive(M.avrec) then
            if (M.w1u1 and IsAlive(M.w1u1) and GetDistance(M.avrec, M.w1u1) < 300) or
                (M.w1u2 and IsAlive(M.w1u2) and GetDistance(M.avrec, M.w1u2) < 300) or
                (M.w1u3 and IsAlive(M.w1u3) and GetDistance(M.avrec, M.w1u3) < 300) or
                (M.w1u4 and IsAlive(M.w1u4) and GetDistance(M.avrec, M.w1u4) < 300) then
                subtit.Play("misn0402.wav")
                M.wave1arrive = true
            end
        end

        -- Wave 1: All dead → queue Wave 2 (+60s)
        if M.wavenumber == 2 and not M.build2 then
            if (not (M.w1u1 and IsAlive(M.w1u1))) and
                (not (M.w1u2 and IsAlive(M.w1u2))) and
                (not (M.w1u3 and IsAlive(M.w1u3))) and
                (not (M.w1u4 and IsAlive(M.w1u4))) then
                subtit.Play("misn0403.wav")
                M.wave2 = GetTime() + DiffUtils.ScaleTimer(60.0)
                M.build2 = true
                M.wave1dead = true
            end
        end

        -- Wave 2: svtank + svfigh from "spawn2new"
        if M.wave2 < GetTime() and IsAlive(M.svrec) and not M.secondwave then
            M.w2u1 = BuildObject("svtank", 2, "spawn2new")
            M.w2u2 = BuildObject("svfigh", 2, "spawn2new")
            Goto(M.w2u1, M.avrec, 1); SetIndependence(M.w2u1, 1)
            Goto(M.w2u2, M.avrec, 1); SetIndependence(M.w2u2, 1)
            if M.difficulty >= 3 then -- Hard+: extra fighter
                M.w2u3 = BuildObject("svfigh", 2, "spawn2new")
                Goto(M.w2u3, M.avrec, 1); SetIndependence(M.w2u3, 1)
            end
            M.wavenumber = 3
            M.wave2arrive = false
            M.wave2 = 99999.0
            M.secondwave = true
        end

        -- Wave 2: Approach warning
        if M.wavenumber == 3 and not M.wave2arrive and IsAlive(M.avrec) then
            if (M.w2u1 and IsAlive(M.w2u1) and GetDistance(M.avrec, M.w2u1) < 300) or
                (M.w2u2 and IsAlive(M.w2u2) and GetDistance(M.avrec, M.w2u2) < 300) or
                (M.w2u3 and IsAlive(M.w2u3) and GetDistance(M.avrec, M.w2u3) < 300) then
                subtit.Play("misn0404.wav")
                M.wave2arrive = true
            end
        end

        -- Wave 2: All dead → queue Wave 3 (+74s)
        if M.wavenumber == 3 and not M.build3 then
            if (not (M.w2u1 and IsAlive(M.w2u1))) and
                (not (M.w2u2 and IsAlive(M.w2u2))) and
                (not (M.w2u3 and IsAlive(M.w2u3))) then
                subtit.Play("misn0405.wav")
                M.wave3 = GetTime() + DiffUtils.ScaleTimer(74.0)
                M.build3 = true
                M.wave2dead = true
            end
        end

        -- Wave 3: 3x svfigh from svrec position
        if M.wave3 < GetTime() and IsAlive(M.svrec) and not M.thirdwave then
            M.w3u1 = BuildObject("svfigh", 2, M.svrec)
            M.w3u2 = BuildObject("svfigh", 2, M.svrec)
            M.w3u3 = BuildObject("svfigh", 2, M.svrec)
            Goto(M.w3u1, M.avrec, 1); SetIndependence(M.w3u1, 1)
            Goto(M.w3u2, M.avrec, 1); SetIndependence(M.w3u2, 1)
            Goto(M.w3u3, M.avrec, 1); SetIndependence(M.w3u3, 1)
            if M.difficulty >= 3 then -- Hard+: extra tank
                M.w3u4 = BuildObject("svtank", 2, M.svrec)
                Goto(M.w3u4, M.avrec, 1); SetIndependence(M.w3u4, 1)
            end
            M.wavenumber = 4
            M.wave3arrive = false
            M.wave3 = 99999.0
            M.thirdwave = true
        end

        -- Wave 3: Approach warning
        if M.wavenumber == 4 and not M.wave3arrive and IsAlive(M.avrec) then
            if (M.w3u1 and IsAlive(M.w3u1) and GetDistance(M.avrec, M.w3u1) < 300) or
                (M.w3u2 and IsAlive(M.w3u2) and GetDistance(M.avrec, M.w3u2) < 300) or
                (M.w3u3 and IsAlive(M.w3u3) and GetDistance(M.avrec, M.w3u3) < 300) or
                (M.w3u4 and IsAlive(M.w3u4) and GetDistance(M.avrec, M.w3u4) < 300) then
                subtit.Play("misn0410.wav")
                M.wave3arrive = true
            end
        end

        -- Wave 3: All dead → queue Wave 4 (+60s)
        if M.wavenumber == 4 and not M.build4 then
            if (not (M.w3u1 and IsAlive(M.w3u1))) and
                (not (M.w3u2 and IsAlive(M.w3u2))) and
                (not (M.w3u3 and IsAlive(M.w3u3))) and
                (not (M.w3u4 and IsAlive(M.w3u4))) then
                subtit.Play("misn0411.wav")
                M.wave4 = GetTime() + DiffUtils.ScaleTimer(60.0)
                M.build4 = true
                M.wave3dead = true
            end
        end

        -- Wave 4: svtank + 2x svfigh from "spawnotherside"
        if M.wave4 < GetTime() and IsAlive(M.svrec) and not M.fourthwave then
            M.w4u1 = BuildObject("svtank", 2, "spawnotherside")
            M.w4u2 = BuildObject("svfigh", 2, "spawnotherside")
            M.w4u3 = BuildObject("svfigh", 2, "spawnotherside")
            Goto(M.w4u1, M.avrec, 1); SetIndependence(M.w4u1, 1)
            Goto(M.w4u2, M.avrec, 1); SetIndependence(M.w4u2, 1)
            Goto(M.w4u3, M.avrec, 1); SetIndependence(M.w4u3, 1)
            if M.difficulty >= 3 then -- Hard+: extra tank
                M.w4u4 = BuildObject("svtank", 2, "spawnotherside")
                Goto(M.w4u4, M.avrec, 1); SetIndependence(M.w4u4, 1)
            end
            if M.difficulty >= 4 then -- Very Hard: extra fighter
                M.w4u5 = BuildObject("svfigh", 2, "spawnotherside")
                Goto(M.w4u5, M.avrec, 1); SetIndependence(M.w4u5, 1)
            end
            M.wavenumber = 5
            M.wave4arrive = false
            M.wave4 = 99999.0
            M.fourthwave = true
        end

        -- Wave 4: Approach warning
        if M.wavenumber == 5 and not M.wave4arrive and IsAlive(M.avrec) then
            if (M.w4u1 and IsAlive(M.w4u1) and GetDistance(M.avrec, M.w4u1) < 300) or
                (M.w4u2 and IsAlive(M.w4u2) and GetDistance(M.avrec, M.w4u2) < 300) or
                (M.w4u3 and IsAlive(M.w4u3) and GetDistance(M.avrec, M.w4u3) < 300) or
                (M.w4u4 and IsAlive(M.w4u4) and GetDistance(M.avrec, M.w4u4) < 300) or
                (M.w4u5 and IsAlive(M.w4u5) and GetDistance(M.avrec, M.w4u5) < 300) then
                subtit.Play("misn0412.wav")
                M.wave4arrive = true
            end
        end

        -- Wave 4: All dead → queue Wave 5 (+30s)
        if M.wavenumber == 5 and not M.build5 then
            if (not (M.w4u1 and IsAlive(M.w4u1))) and
                (not (M.w4u2 and IsAlive(M.w4u2))) and
                (not (M.w4u3 and IsAlive(M.w4u3))) and
                (not (M.w4u4 and IsAlive(M.w4u4))) and
                (not (M.w4u5 and IsAlive(M.w4u5))) then
                subtit.Play("misn0413.wav")
                M.wave5 = GetTime() + DiffUtils.ScaleTimer(30.0)
                M.build5 = true
                M.wave4dead = true
            end
        end

        -- Wave 5: svtank + 3x svfigh from svrec position
        if M.wave5 < GetTime() and IsAlive(M.svrec) and not M.fifthwave then
            M.w5u1 = BuildObject("svtank", 2, M.svrec)
            M.w5u2 = BuildObject("svfigh", 2, M.svrec)
            M.w5u3 = BuildObject("svfigh", 2, M.svrec)
            M.w5u4 = BuildObject("svfigh", 2, M.svrec)
            Goto(M.w5u1, M.avrec, 1); SetIndependence(M.w5u1, 1)
            Goto(M.w5u2, M.avrec, 1); SetIndependence(M.w5u2, 1)
            Goto(M.w5u3, M.avrec, 1); SetIndependence(M.w5u3, 1)
            Goto(M.w5u4, M.avrec, 1); SetIndependence(M.w5u4, 1)
            if M.difficulty >= 3 then -- Hard+: extra tank
                M.w5u5 = BuildObject("svtank", 2, M.svrec)
                Goto(M.w5u5, M.avrec, 1); SetIndependence(M.w5u5, 1)
            end
            if M.difficulty >= 4 then -- Very Hard: extra fighter
                M.w5u6 = BuildObject("svfigh", 2, M.svrec)
                Goto(M.w5u6, M.avrec, 1); SetIndependence(M.w5u6, 1)
            end
            M.wavenumber = 6
            M.wave5arrive = false
            M.wave5 = 99999.0
            M.fifthwave = true
        end

        -- Wave 5: Approach warning
        if M.wavenumber == 6 and not M.wave5arrive and IsAlive(M.avrec) then
            if (M.w5u1 and IsAlive(M.w5u1) and GetDistance(M.avrec, M.w5u1) < 300) or
                (M.w5u2 and IsAlive(M.w5u2) and GetDistance(M.avrec, M.w5u2) < 300) or
                (M.w5u3 and IsAlive(M.w5u3) and GetDistance(M.avrec, M.w5u3) < 300) or
                (M.w5u4 and IsAlive(M.w5u4) and GetDistance(M.avrec, M.w5u4) < 300) or
                (M.w5u5 and IsAlive(M.w5u5) and GetDistance(M.avrec, M.w5u5) < 300) or
                (M.w5u6 and IsAlive(M.w5u6) and GetDistance(M.avrec, M.w5u6) < 300) then
                subtit.Play("misn0414.wav")
                M.wave5arrive = true
            end
        end

        -- Wave 5: All dead → mark complete (enables win check)
        if M.wavenumber == 6 and not M.wave5dead then
            if (not (M.w5u1 and IsAlive(M.w5u1))) and
                (not (M.w5u2 and IsAlive(M.w5u2))) and
                (not (M.w5u3 and IsAlive(M.w5u3))) and
                (not (M.w5u4 and IsAlive(M.w5u4))) and
                (not (M.w5u5 and IsAlive(M.w5u5))) and
                (not (M.w5u6 and IsAlive(M.w5u6))) then
                M.wave5dead = true
            end
        end

        -- =====================================================================
        -- RELIC / TUG / WIN / FAIL LOGIC
        -- =====================================================================

        -- Monitor Relic Discovery
        if not M.discoverrelic and IsAlive(M.player) then
            if (GetDistance(M.player, M.relic) < 150.0) or (M.tug and IsAlive(M.tug) and GetDistance(M.tug, M.relic) < 150.0) then
                M.discoverrelic = true
                M.aud1 = subtit.Play("misn0403.wav")
                SetObjectiveName(M.relic, "Alien Relic")
                SetUserTarget(M.relic)
                M.investigate = GetTime() + 90.0
            end
        end

        -- Audio completion for relic discovery
        if M.discoverrelic and not M.basesecure then
            if M.aud1 and IsAudioMessageDone(M.aud1) then
                SetObjectiveName(M.relic, "Alien Relic")
                SetUserTarget(M.relic)
                M.basesecure = true
            end
        end

        -- Tug order logic
        if M.basesecure and not M.relicsecure then
            if M.tug and IsAlive(M.tug) and HasCargo(M.tug) then
                M.relicsecure = true
                M.investigate = 999999999.0
                M.aud2 = subtit.Play("misn0404.wav")
                SetObjectiveOff(M.relic)
                if M.w1u1 and IsAlive(M.w1u1) then Attack(M.w1u1, M.tug, 1) end
                if M.w1u2 and IsAlive(M.w1u2) then Attack(M.w1u2, M.tug, 1) end
            end
        end

        -- Retreat logic if relic is picked up
        if M.relicsecure and not M.retreat then
            if GetDistance(M.tug, "relicstart1") > 40.0 then
                M.retreat = true
                M.aud3 = subtit.Play("misn0405.wav")
            end
        end

        -- Check if CCA captured relic (via wave 3 transport)
        if M.thirdwave and not M.ccahasrelic then
            if M.w3u1 and IsAlive(M.w3u1) then
                if HasCargo(M.w3u1) then
                    M.ccahasrelic = true
                    M.aud4 = subtit.Play("misn0406.wav")
                    Goto(M.w3u1, "spawn3", 1)
                    M.reliccam = M.w3u1
                    SetObjectiveOn(M.w3u1)
                    SetObjectiveName(M.w3u1, "CCA Transport")
                end
            end
        end

        -- Relic failure: CCA transport reaches its base
        if M.ccahasrelic and not M.missionfail then
            if M.w3u1 and GetDistance(M.w3u1, "spawn3") < 100.0 then
                M.missionfail = true
            end
        end

        if M.missionfail and M.w3u1 then
            if not M.cin_started then
                CameraReady()
                M.cin_started = true
            end
            if CameraReady() then
                M.startendcin = GetTime() + 10.0
                CameraPath("failpath", 100, 200, M.w3u1)
            end
            if GetTime() > M.startendcin or CameraCancelled() then
                CameraFinish()
                M.missionfail = false
                CameraCancelled(false)
                FailMission(GetTime() + 5.0)
            end
        end

        -- Relic not secured in time: investigate timeout failure
        if not M.missionfail2 and not M.relicsecure and not M.ccahasrelic then
            if GetTime() > M.investigate then
                M.missionfail2 = true
                M.aud10 = subtit.Play("misn0407.wav")
            end
        end

        if M.missionfail2 then
            if M.aud10 and IsAudioMessageDone(M.aud10) then
                FailMission(GetTime() + 5.0)
            end
        end

        -- Monitor CCA Base attack
        if not M.attackccabase then
            M.z = CountUnitsNearObject(M.svrec, 1000.0, 1, "avtank")
            if M.z > 2 then
                M.attackccabase = true
                M.aud11 = subtit.Play("misn0408.wav")
            end
        end

        if M.attackccabase and not M.ccabasedestroyed then
            local v = GetNearestVehicle(GetPosition("cca_base"))
            if IsAlive(v) then
                if GetTeamNum(v) == 1 and GetDistance(v, "cca_base") < 600.0 then
                    M.ccabasedestroyed = true
                    M.aud11 = subtit.Play("misn0409.wav")
                end
            end
        end

        -- Victory cinematic (CCA base cleared)
        if M.ccabasedestroyed and not M.chewedout then
            if not M.cin_started then
                CameraReady()
                M.cin_started = true
            end
            if CameraReady() then
                M.startendcin = GetTime() + 15.0
                CameraPath("winpath", 100, 200, M.svrec)
            end
            if GetTime() > M.startendcin or CameraCancelled() then
                CameraFinish()
                M.chewedout = true
                CameraCancelled(false)
                M.investigate = GetTime() + 5.0
            end
        end

        -- Win condition: all 5 waves cleared, tug delivered relic, no enemies near base
        if M.fifthwave and not M.missionwon then
            M.z = CountUnitsNearObject(M.svrec, 2000.0, 2, "vehicle")
            if IsAlive(M.tug) and GetDistance(M.tug, M.avrec) < 100.0 and M.z == 0 then
                M.missionwon = true
                M.aud12 = subtit.Play("misn0410.wav")
                M.endcindone = GetTime() + 15.0
            end
        end

        if M.missionwon then
            if not M.cin_started then
                CameraReady()
                M.cin_started = true
            end
            if CameraReady() then
                M.startendcin = GetTime() + 15.0
                CameraPath("winpath", 100, 200, M.avrec)
                SetUserTarget(M.avrec)
            end
            if (M.aud12 and IsAudioMessageDone(M.aud12)) or GetTime() > M.startendcin or CameraCancelled() then
                CameraFinish()
                M.missionwon = false
                CameraCancelled(false)
                SucceedMission(GetTime() + 5.0)
            end
        end

        -- Tug destroyed failure
        if M.tug and not IsAlive(M.tug) and not M.missionfail then
            M.missionfail = true
            M.aud13 = subtit.Play("misn0411.wav")
        end

        if M.missionfail then
            if (M.aud13 and IsAudioMessageDone(M.aud13)) or GetTime() > M.startendcin or CameraCancelled() then
                FailMission(GetTime() + 5.0)
            end
        end

        -- Recycler destroyed failure
        if not IsAlive(M.avrec) and not M.missionfail then
            M.missionfail = true
            M.aud14 = subtit.Play("misn0412.wav")
        end

        if M.missionfail then
            if (M.aud14 and IsAudioMessageDone(M.aud14)) or GetTime() > M.startendcin or CameraCancelled() then
                FailMission(GetTime() + 5.0)
            end
        end
    end
end

function Save()
    return M, aiCore.Save()
end

function Load(data, aiData)
    if data then M = data end
    if aiData then aiCore.Load(aiData) end
    aiCore.Bootstrap()
    ApplyQOL()
end
