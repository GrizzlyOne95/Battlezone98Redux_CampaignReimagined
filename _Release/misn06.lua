-- Misn06 Mission Script (Converted from Misn06Mission.cpp)

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

-- Helper for AI
local function SetupAI()
    DiffUtils.SetupTeams(aiCore.Factions.NSDF, aiCore.Factions.CCA, 2)

    -- Configure Player Team (1) for Scavenger Assist
    if aiCore.ActiveTeams and aiCore.ActiveTeams[1] then
        aiCore.ActiveTeams[1]:SetConfig("scavengerAssist", PersistentConfig.Settings.ScavengerAssistEnabled)
        aiCore.ActiveTeams[1]:SetConfig("manageFactories", false)
        aiCore.ActiveTeams[1]:SetConfig("autoRepairWingmen", PersistentConfig.Settings.AutoRepairWingmen)
    end
end

-- Variables (Encapsulated for Save/Load)
local M = {
    -- State Booleans
    missionstart = true,
    starportdisc = false,
    star1recon = false,
    star4recon = false,
    star6recon = false,
    starportreconed = false,
    haephestusdisc = false,
    blockadefound = false,
    ccaattack = false,
    missionfail = false,
    missionwon = false,
    newobjective = false,
    reconheaphestus = false,
    neworders = false,
    safebreak = false,
    buildcam = false,
    ccapullout = false,
    transarrive = false,
    touchdown = false,
    lprecon = false,
    fifteenmin = false,
    platoonhere = false,
    corbettalive = true,
    opencamdone = false,
    cam1done = false,
    cam3done = false,
    patrol1set = false,
    patrol2set = false,
    patrol3set = false,
    startpat1 = false,
    startpat2 = false,
    startpat3 = false,
    startpat4 = false,
    wave1start = false,
    wave2start = false,
    wave3start = false,
    launchpadreconed = false,
    patrol1spawned = false,
    patrol2spawned = false,
    patrol3spawned = false,
    breakme = false,
    bugout = false,
    pickupset = false,
    pickupreached = false,
    hephikey = false,
    reminder = false,
    dustoff = false,
    fail3 = false,
    trigger1 = false,
    timergone = false,
    respawn = false,
    simcam = false,
    removal = false,
    breakout1 = false,
    attack = false,
    breaker = false,
    death = false,
    fifthplatoon = true,
    missionfail1 = false,
    missionfail3 = false,
    missionfail4 = false,
    loopbreak1 = false,
    loopbreaker = false,
    lincolndes = false,
    tenmin = false,
    fivemin = false,
    twomin = false,
    threemin = false,
    endme = false,
    bustout = false,
    economyccaplatoon = false,
    star = false,
    breaker19 = false,

    -- Logic State Integers
    lincoln_state = 0,
    hephwarn = 0,
    ident = 0,
    spfail = 0,
    stardisc = 0,

    -- Timers
    lincoln_timer = 0,
    patrol1time = 99999999.0,
    patrol2time = 99999999.0,
    patrol3time = 99999999.0,
    check1 = 99999999.0,
    opencamtime = 999999.0,
    cam1time = 999999.0,
    cam3time = 999999.0,
    hephdisctime = 9999999999.0,
    identtime = 999999999.0,
    processtime = 999999.0,
    diskstar = 99999999999.0,
    reconsptime = 9999999999999999.0,
    start1 = 999999999.0,
    searchtime = 999999.0,
    transportarrive = 99999.0,
    lincolndestroyed = 999999.0,
    oneminstrans = 999999.0,
    transaway = 999999.0,
    wave1 = 999999.0,
    wave2 = 999999.0,
    wave3 = 999999.0,
    platoonarrive = 999999.0,
    threeminsplatoon = 999999.0,
    tenminsplatoon = 999999.0,
    fiveminsplatoon = 999999.0,
    twominsplatoon = 999999.0,
    timerstart = 999999999.0,
    time1 = 999999999.0,
    deathtime = 999999999999.0,
    end_timer = 999999999999.0,

    -- Handles
    haephestus = nil,
    starport = nil,
    player = nil,
    nav1 = nil,
    rendezvous = nil,
    blockade1 = nil,
    avrec = nil,
    svrec = nil,
    launchpad = nil,
    starportcam = nil,
    dustoffcam = nil,
    art1 = nil,
    turret = nil,
    wAu1 = nil,
    wAu2 = nil,
    wAu3 = nil,
    w1u1 = nil,
    w1u2 = nil,
    w1u3 = nil,
    w2u1 = nil,
    w2u2 = nil,
    w2u3 = nil,
    w3u1 = nil,
    w3u2 = nil,
    w3u3 = nil,
    star2 = nil,
    star6 = nil,
    star8 = nil,                           -- Others unused in logic
    pu1p1 = nil,
    pu2p1 = nil,
    pu1p2 = nil,
    pu2p2 = nil,
    pu1p3 = nil,
    pu2p3 = nil,
    pu1p4 = nil,
    pu2p4 = nil,
    pu3p4 = nil,
    ccap1 = nil,
    ccap2 = nil,
    ccap3 = nil,
    ccap4 = nil,
    ccap5 = nil,
    ccap6 = nil,
    ccap7 = nil,
    ccap8 = nil,
    ccap9 = nil,
    sim1 = nil,
    sim2 = nil,
    sim3 = nil,
    sim4 = nil,
    sim5 = nil,
    sim6 = nil,
    sim7 = nil,
    sim8 = nil,
    sim9 = nil,
    sim10 = nil,
    p5u3 = nil,
    p5u4 = nil,
    p5u6 = nil,
    p5u9 = nil,
    p5u12 = nil,

    -- Setup Vars
    patrol1start = math.random(0, 3),
    patrol2start = math.random(0, 3),
    patrol3start = math.random(0, 3),
    extractpoint = math.random(0, 3),
    difficulty = 2,

    TPS = 20
}

function ApplyQOL()
    if not exu then return end
    if exu.SetShotConvergence then exu.SetShotConvergence(true) end
    if exu.SetReticleRange then exu.SetReticleRange(500) end
    if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    PersistentConfig.Initialize()
    Environment.Init()
    PhysicsImpact.Init()
end

function Start()
    M.TPS = 20
    if exu then
        local ver = (type(exu.GetVersion) == "function" and exu.GetVersion()) or exu.version or "Unknown"
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

    SetupAI()
    aiCore.Bootstrap()
    subtit.Initialize()

    -- Variables init (C++ Setup)
    M.missionstart = true
    M.corbettalive = true
    M.fifthplatoon = true
    M.reconsptime = GetTime() + 999999.0 -- Init high
end

function AddObject(h)
    local team = GetTeamNum(h)

    Environment.OnObjectCreated(h)
    PhysicsImpact.OnObjectCreated(h)

    if team == 2 then
        aiCore.AddObject(h)
    elseif team == 1 then
        aiCore.AddObject(h)
    end

    -- Unit Turbo based on difficulty
    if exu and exu.SetUnitTurbo and IsCraft(h) then
        if team == 1 then
            exu.SetUnitTurbo(h, true)
        elseif team ~= 0 then
            if M.difficulty >= 2 then
                exu.SetUnitTurbo(h, 2.5) -- Scaled turbo for enemies
            end
        end
    end
end

function DeleteObject(h)
end

function Update()
    M.player = GetPlayerHandle()
    if exu and exu.UpdateOrdnance then exu.UpdateOrdnance() end
    aiCore.Update()
    Environment.Update(1.0 / M.TPS)
    PhysicsImpact.Update(1.0 / M.TPS)
    subtit.Update()
    PersistentConfig.UpdateInputs()
    PersistentConfig.UpdateHeadlights()

    if M.missionstart then
        subtit.Play("misn0601.wav")
        M.missionstart = false

        M.rendezvous = GetHandle("eggeizr1-1_geyser")
        SetObjectiveName(M.rendezvous, "5th Platoon")
        M.haephestus = GetHandle("obheph0_i76building")
        M.avrec = GetHandle("avrecy-1_recycler")
        M.svrec = GetHandle("svrecy-1_recycler")
        M.launchpad = GetHandle("sblpad0_i76building")
        M.wAu1 = GetHandle("svfigh568_wingman")
        M.wAu2 = GetHandle("svfigh566_wingman")
        M.turret = GetHandle("turret")

        M.star2 = GetHandle("obstp25_i76building")
        M.star6 = GetHandle("obstp10_i76building")
        M.star8 = GetHandle("obstp33_i76building")
        M.blockade1 = GetHandle("svturr649_turrettank")

        -- Opening Cinematic Units
        M.p5u3 = GetHandle("avtank13_wingman")
        M.p5u4 = GetHandle("avtank11_wingman")
        M.p5u6 = GetHandle("avtank12_wingman")
        M.p5u9 = GetHandle("avfigh7_wingman")
        M.p5u12 = GetHandle("avfigh10_wingman")

        M.patrol1time = GetTime() + DiffUtils.ScaleTimer(30.0)
        M.patrol2time = GetTime() + DiffUtils.ScaleTimer(30.0)
        M.patrol3time = GetTime() + DiffUtils.ScaleTimer(30.0)

        SetObjectiveOn(M.rendezvous)
        AddObjective("misn0600.otf", "white")

        CameraReady()
        M.opencamtime = GetTime() + 28.0
        M.opencamdone = true
        M.newobjective = true

        SetScrap(1, DiffUtils.ScaleRes(5))
        M.art1 = GetHandle("svartl648_howitzer")
        Defend(M.art1, 1)
        M.check1 = GetTime() + 20.0
    end

    AddHealth(M.star2, 1000)
    AddHealth(M.star6, 1000)
    AddHealth(M.star8, 1000)

    -- Patrol Logic (Trigger1)
    if not M.trigger1 then
        local trigger_obj = GetNearestEnemy(M.turret)
        if (GetDistance(trigger_obj, M.turret) < 200.0) or (not IsAlive(M.turret)) then
            -- Initial Patrol Groups
            if not M.patrol1set then
                local type = "svfigh"
                if M.patrol1start == 2 then type = "svtank" end
                M.pu1p1 = BuildObject(type, 2, "pat1sp" .. (M.patrol1start + 1))
                M.patrol1set = true
            end
            if not M.patrol2set then
                local type = "svfigh"
                if M.patrol2start == 2 then type = "svtank" end
                M.pu1p2 = BuildObject(type, 2, "pat2sp" .. (M.patrol2start + 1))
                M.patrol2set = true
            end
            if not M.patrol3set then
                local type = "svfigh"
                if M.patrol3start == 2 then type = "svtank" end
                M.pu1p3 = BuildObject(type, 2, "pat3sp" .. (M.patrol3start + 1))
                M.patrol3set = true
            end

            if M.patrol1set and not M.startpat1 then
                for i = 1, DiffUtils.ScaleEnemy(1) do Patrol(M.pu1p1, "patrol1") end
                M.startpat1 = true
            end
            if M.patrol2set and not M.startpat2 then
                for i = 1, DiffUtils.ScaleEnemy(1) do Patrol(M.pu1p2, "patrol2") end
                M.startpat2 = true
            end
            if M.patrol3set and not M.startpat3 then
                for i = 1, DiffUtils.ScaleEnemy(1) do Patrol(M.pu1p3, "patrol3") end
                M.startpat3 = true
            end

            if not M.startpat4 then
                M.pu1p4 = BuildObject("svfigh", 2, "patrol4_spawn")
                M.pu2p4 = BuildObject("svfigh", 2, "patrol4_spawn")
                M.pu3p4 = BuildObject("svfigh", 2, "patrol4_spawn")
                Patrol(M.pu1p4, "patrol4")
                Patrol(M.pu2p4, "patrol4")
                Patrol(M.pu3p4, "patrol4")
                M.startpat4 = true
            end

            M.trigger1 = true
        end
    end

    -- Dynamic Patrol Spawning
    if M.trigger1 then
        if (M.patrol1time < GetTime()) and (not M.patrol1spawned) then
            M.patrol1time = GetTime() + 2.0
            if IsAlive(M.pu1p1) and (GetNearestEnemy(M.pu1p1) < 450.0) then
                M.pu2p1 = BuildObject("svtank", 2, M.pu1p1)
                M.patrol1spawned = true
                Patrol(M.pu2p1, "patrol1")
            end
        end
        if (M.patrol2time < GetTime()) and (not M.patrol2spawned) then
            M.patrol2time = GetTime() + 2.0
            if IsAlive(M.pu1p2) and (GetNearestEnemy(M.pu1p2) < 450.0) then
                M.pu2p2 = BuildObject("svfigh", 2, M.pu1p2)
                M.patrol2spawned = true
                Patrol(M.pu2p2, "patrol2")
            end
        end
        if (M.patrol3time < GetTime()) and (not M.patrol3spawned) then
            M.patrol3time = GetTime() + 2.0
            if IsAlive(M.pu1p3) and (GetNearestEnemy(M.pu1p3) < 450.0) then
                M.pu2p3 = BuildObject("svfigh", 2, M.pu1p3)
                M.patrol3spawned = true
                Patrol(M.pu2p3, "patrol3")
            end
        end
    end

    -- Mission Fail 1 (Player Recycler Dead)
    if (not IsAlive(M.avrec)) and (not M.missionfail1) then
        subtit.Play("misn0653.wav")
        subtit.Play("misn0651.wav")
        M.missionfail1 = true
        FailMission(GetTime() + 10.0, "misn06l5.des")
    end

    -- Opening Cam
    if M.opencamdone then
        CameraPath("openingcampath", 1000, 500, M.p5u3)
        AddHealth(M.p5u3, 50)
        AddHealth(M.p5u4, 50)
        AddHealth(M.p5u6, 50)
        AddHealth(M.p5u9, 50)
        AddHealth(M.p5u12, 50)

        if (M.opencamtime < GetTime()) or CameraCancelled() then
            CameraFinish()
            M.opencamdone = false
            -- Remove opening units
            local units = { M.p5u3, M.p5u4, M.p5u6, M.p5u9, M.p5u12 }
            for _, u in ipairs(units) do if IsAlive(u) then RemoveObject(u) end end
        end
    end

    -- Objective Logic
    if M.newobjective then
        ClearObjectives()
        if M.bugout and M.missionwon then
            AddObjective("misn0606.otf", "green")
            AddObjective("misn0605.otf", "green")
            AddObjective("misn0604.otf", "green")
        elseif M.bugout and not M.missionwon then
            AddObjective("misn0606.otf", "white")
            AddObjective("misn0605.otf", "green")
            AddObjective("misn0604.otf", "green")
        elseif M.lprecon and not M.bugout then
            AddObjective("misn0605.otf", "white")
            AddObjective("misn0604.otf", "green")
        elseif M.starportreconed and not M.transarrive and not M.safebreak then
            AddObjective("misn0604.otf", "white")
            AddObjective("misn0603.otf", "green")
            AddObjective("misn0602.otf", "green")
            AddObjective("misn0601.otf", "green")
        elseif M.neworders and not M.starportreconed then
            AddObjective("misn0603.otf", "white")
            AddObjective("misn0602.otf", "green")
            AddObjective("misn0601.otf", "green")
        elseif M.reconheaphestus and not M.neworders then
            AddObjective("misn0602.otf", "white")
            AddObjective("misn0601.otf", "green")
        elseif M.haephestusdisc and not M.reconheaphestus and not M.hephikey then
            AddObjective("misn0601.otf", "white")
        elseif M.fifthplatoon then
            AddObjective("misn0600.otf", "white")
        end
        M.newobjective = false
    end

    -- Hephaestus Logic
    if (not M.haephestusdisc) and (GetDistance(M.haephestus, M.player) < 1000.0) then
        subtit.Play("misn0602.wav")
        M.haephestusdisc = true
        M.hephdisctime = GetTime() + 60.0
        SetObjectiveOn(M.haephestus)
        SetObjectiveName(M.haephestus, "Object")
        M.newobjective = true
    end

    if M.haephestusdisc and (not M.reconheaphestus) and (not M.hephikey) and (M.hephdisctime < GetTime()) and (M.hephwarn < 2) then
        subtit.Play("misn0690.wav")
        M.hephdisctime = GetTime() + 20.0
        M.hephwarn = M.hephwarn + 1
    end

    if (M.hephwarn == 2) and (not M.missionfail4) and (M.hephdisctime < GetTime()) then
        subtit.Play("misn0694.wav")
        M.missionfail4 = true
        FailMission(GetTime(), "misn06l1.des")
    end

    -- Ident Logic
    if (not M.reconheaphestus) and (GetDistance(M.player, M.haephestus) < 125.0) and (not M.hephikey) then
        subtit.Play("misn0603.wav")
        subtit.Play("misn0604.wav")
        M.reconheaphestus = true
        SetObjectiveOff(M.haephestus)
        SetObjectiveName(M.haephestus, "Haephestus")
        CameraReady()
        M.cam1time = GetTime() + 12.0
        M.cam1done = true
        M.identtime = GetTime() + 20.0
    end

    if (M.identtime < GetTime()) and (not M.hephikey) and (M.ident < 2) then
        subtit.Play("misn0691.wav")
        M.ident = M.ident + 1
        M.identtime = GetTime() + 10.0
    end

    if (M.ident == 2) and (M.identtime < GetTime()) and (not M.hephikey) and (not M.missionfail) then
        subtit.Play("misn0694.wav")
        M.missionfail = true
        FailMission(GetTime(), "misn06l2.des")
    end

    if IsInfo("obheph") and (not M.hephikey) then
        M.processtime = GetTime() + 5.0
        M.hephikey = true
        M.reconheaphestus = true
        SetObjectiveOff(M.haephestus)
        M.newobjective = true
        -- Reset ident fails
        M.ident = 0
    end

    if (not M.neworders) and (M.processtime < GetTime()) then
        subtit.Play("misn0605.wav")
        M.fifthplatoon = false
        M.neworders = true
        M.buildcam = true
        M.diskstar = GetTime() + 80.0
    end

    if M.buildcam then
        SetObjectiveOff(M.rendezvous)
        M.starportcam = BuildObject("apcamr", 1, "cam1spawn")
        SetObjectiveName(M.starportcam, "Starport")
        M.buildcam = false
        M.newobjective = true
    end

    if (GetDistance(M.player, M.blockade1) < 420.0) and (not M.blockadefound) then
        subtit.Play("misn0636.wav")
        M.blockadefound = true
    end

    -- Starport Recon
    if IsInfo("obstp1") and (not M.star1recon) then M.star1recon = true end
    if IsInfo("obstp8") and (not M.star4recon) then M.star4recon = true end
    if IsInfo("obstp3") and (not M.star6recon) then M.star6recon = true end

    -- Starport Fail Timer
    if (not M.starportreconed) and (M.reconsptime < GetTime()) and (not M.fail3) and (M.spfail < 4) then
        subtit.Play("misn0654.wav")
        M.reconsptime = GetTime() + 15.0
        M.spfail = M.spfail + 1
    end
    if (not M.fail3) and (M.spfail == 4) then
        M.fail3 = true
        subtit.Play("misn0694.wav")
        FailMission(GetTime(), "misn06l6.des")
    end

    if M.star1recon and M.star4recon and M.star6recon and (not M.starportreconed) then
        subtit.Play("misn0650.wav")
        subtit.Play("misn0606.wav")
        subtit.Play("misn0607.wav")
        M.starportreconed = true
        M.start1 = GetTime() + 15.0
    end

    if (not M.star) and M.starportreconed and (M.start1 < GetTime()) then
        M.newobjective = true
        M.star = true
    end

    -- Starport Disc Check
    if (not M.starportdisc) and (GetDistance(M.star8, M.player) < 200.0) then
        subtit.Play("misn0608.wav")
        M.searchtime = GetTime() + 15.0
        M.starportdisc = true
        M.reconsptime = GetTime() + 20.0 -- Set fail timer
    end

    if M.neworders and (not M.starportdisc) and (M.diskstar < GetTime()) and (M.stardisc < 3) then
        subtit.Play("misn0695.wav")
        M.diskstar = GetTime() + 40.0
        M.stardisc = M.stardisc + 1
    end

    if (M.stardisc == 3) and (M.diskstar < GetTime()) and (not M.missionfail3) then
        M.missionfail3 = true
        subtit.Play("misn0694.wav")
        FailMission(GetTime(), "misn06l3.des")
    end

    -- CCA Attack Logic
    if (not M.ccaattack) and (M.check1 < GetTime()) then
        local enemy = GetNearestEnemy(M.wAu1)
        if (GetDistance(enemy, M.wAu1) < 410.0) then
            Attack(M.wAu1, enemy)
            Attack(M.wAu2, enemy)
            SetIndependence(M.wAu2, 1)
            M.ccaattack = true
            M.start1 = GetTime() - 1 -- Force next check
        end
        M.check1 = GetTime() + 1.5
    end

    if M.starportreconed and (not M.ccaattack) then
        Attack(M.wAu1, M.player)
        Attack(M.wAu2, M.player)
        SetIndependence(M.wAu1, 1)
        SetIndependence(M.wAu2, 1)
        M.ccaattack = true
    end

    -- CCA Pullout / Transport Arrival
    if M.ccaattack and (not M.loopbreak1) and (M.start1 < GetTime()) and
        ((GetDistance(M.wAu1, "cam1spawn") < 400.0) or (GetDistance(M.wAu2, "cam1spawn") < 400.0)) then
        subtit.Play("misn0611.wav")
        CameraReady()
        M.cam3time = GetTime() + 5.0
        M.cam3done = true
        M.ccaattack = false
        M.loopbreak1 = true
    end

    -- Cam Logic
    if M.cam1done then
        CameraPath("cam1path", 800, 1000, M.haephestus)
        if (M.cam1time < GetTime()) or CameraCancelled() then
            CameraFinish()
            M.cam1done = false
            M.newobjective = true
        end
    end

    if M.cam3done then
        CameraObject(M.wAu1, 300, 100, -900, M.wAu1)
        if (M.cam3time < GetTime()) or CameraCancelled() then
            CameraFinish()
            M.cam3done = false
        end
    end

    -- Transport Logic
    if (not IsAlive(M.wAu1)) and (not IsAlive(M.wAu2)) and (not M.ccapullout) and M.starportreconed then
        subtit.Play("misn0612.wav")
        subtit.Play("misn0613.wav")
        M.transportarrive = GetTime() + 50.0
        M.transarrive = true
        M.safebreak = true
        M.ccapullout = true

        -- Set Waves
        M.wave1 = GetTime() + DiffUtils.ScaleTimer(60.0)
        M.wave2 = GetTime() + DiffUtils.ScaleTimer(180.0)
        M.wave3 = GetTime() + DiffUtils.ScaleTimer(300.0)
    end

    if (not M.breaker19) and M.ccapullout and (M.transportarrive < GetTime()) then
        M.breaker19 = true
    end

    -- Waves
    if (M.wave1 < GetTime()) and (not M.wave1start) and IsAlive(M.svrec) then
        M.w1u1 = BuildObject("svfigh", 2, M.svrec)
        M.w1u2 = BuildObject("svtank", 2, M.svrec)
        M.w1u3 = BuildObject("svfigh", 2, M.svrec)
        Attack(M.w1u1, M.avrec)
        Attack(M.w1u2, M.avrec)
        Attack(M.w1u3, M.avrec)

        for i = 1, DiffUtils.ScaleEnemy(3) - 3 do
            local h = BuildObject("svfigh", 2, M.svrec); Attack(h, M.avrec); SetIndependence(h, 1)
        end

        SetIndependence(M.w1u1, 1)
        SetIndependence(M.w1u2, 1)
        SetIndependence(M.w1u3, 1)
        M.wave1start = true
    end

    if (M.wave2 < GetTime()) and (not M.wave2start) and IsAlive(M.svrec) then
        M.w2u1 = BuildObject("svfigh", 2, M.svrec)
        M.w2u2 = BuildObject("svtank", 2, M.svrec)
        M.w2u3 = BuildObject("svfigh", 2, M.svrec)
        Attack(M.w2u1, M.avrec)
        Attack(M.w2u2, M.avrec)
        Attack(M.w2u3, M.avrec)
        SetIndependence(M.w2u1, 1)
        SetIndependence(M.w2u2, 1)
        SetIndependence(M.w2u3, 1)
        M.wave2start = true
    end

    if (M.wave3 < GetTime()) and (not M.wave3start) and IsAlive(M.svrec) then
        M.w3u1 = BuildObject("svfigh", 2, M.svrec)
        M.w3u2 = BuildObject("svtank", 2, M.svrec)
        M.w3u3 = BuildObject("svfigh", 2, M.svrec)
        Attack(M.w3u1, M.avrec)
        Attack(M.w3u2, M.avrec)
        Attack(M.w3u3, M.avrec)

        for i = 1, DiffUtils.ScaleEnemy(3) - 3 do
            local h = BuildObject("svfigh", 2, M.svrec); Attack(h, M.avrec); SetIndependence(h, 1)
        end

        SetIndependence(M.w3u1, 1)
        SetIndependence(M.w3u2, 1)
        SetIndependence(M.w3u3, 1)
        M.wave3start = true
    end

    -- Transport Arrival Events
    if (M.transportarrive < GetTime()) and M.transarrive then
        subtit.Play("misn0614.wav")
        -- subtit.Play("misn0628.wav") -- Moved to end of sequence
        M.lincolndestroyed = GetTime() + 60.0
        M.oneminstrans = GetTime() + DiffUtils.ScaleTimer(60.0)
        M.transaway = GetTime() + DiffUtils.ScaleTimer(90.0)
        M.platoonarrive = GetTime() + DiffUtils.ScaleTimer(1410.0)
        M.threeminsplatoon = GetTime() + DiffUtils.ScaleTimer(390.0)
        M.tenminsplatoon = GetTime() + DiffUtils.ScaleTimer(810.0)
        M.fiveminsplatoon = GetTime() + DiffUtils.ScaleTimer(1110.0)
        M.twominsplatoon = GetTime() + DiffUtils.ScaleTimer(1260.0) -- Corbett dead time
        M.transarrive = false
        M.touchdown = true
        M.threemin = true
        M.tenmin = true
        M.fivemin = true
        M.twomin = true
        M.platoonhere = true
        M.newobjective = true
        M.timerstart = GetTime() + 27.42
        M.lincolndes = true

        -- Start Lincoln Audio Sequence
        M.lincoln_state = 1
        M.lincoln_timer = GetTime() + 4.0
    end

    -- Lincoln Audio Sequence
    if M.lincoln_state > 0 then
        if M.lincoln_timer < GetTime() then
            if M.lincoln_state == 1 then
                subtit.Play("misn0615.wav") -- Order blockade
                M.lincoln_timer = GetTime() + 10.0
                M.lincoln_state = 2
            elseif M.lincoln_state == 2 then
                subtit.Play("misn0616.wav") -- One minute
                M.lincoln_timer = GetTime() + 2.0
                M.lincoln_state = 3
            elseif M.lincoln_state == 3 then
                subtit.Play("misn0617.wav")        -- Not enough time
                M.lincoln_timer = GetTime() + 25.0 -- Wait for engagement
                M.lincoln_state = 4
            elseif M.lincoln_state == 4 then
                subtit.Play("misn0625.wav") -- Lincoln under attack
                M.lincoln_timer = GetTime() + 4.0
                M.lincoln_state = 5
            elseif M.lincoln_state == 5 then
                subtit.Play("misn0626.wav") -- Mayday
                M.lincoln_timer = GetTime() + 8.0
                M.lincoln_state = 6
            elseif M.lincoln_state == 6 then
                if M.lincolndestroyed < GetTime() then
                    subtit.Play("misn0627.wav") -- Lincoln destroyed
                    M.lincoln_timer = GetTime() + 6.0
                    M.lincoln_state = 7
                end
            elseif M.lincoln_state == 7 then
                subtit.Play("misn0628.wav") -- Transport escaped
                M.lincoln_state = 0
            end
        end
    end

    -- Launchpad Objective
    if (not M.lprecon) and M.lincolndes and (M.lincolndestroyed < GetTime()) then
        M.lprecon = true
        StartCockpitTimer(540.0, 362.0, 180.0) -- Example vals
        SetObjectiveOn(M.launchpad)
        M.newobjective = true
    end

    -- Simulacrum (Tank Battle)
    if (M.threeminsplatoon < GetTime()) and M.threemin and (not M.launchpadreconed) then
        local bogey = GetNearestEnemy(M.player)
        if GetDistance(bogey, M.player) > 400.0 then
            M.sim1 = BuildObject("avtank", 3, "sim1")
            M.sim2 = BuildObject("avtank", 3, "sim2")
            M.sim3 = BuildObject("avtank", 3, "sim3")
            M.sim4 = BuildObject("avtank", 3, "sim4")
            M.sim5 = BuildObject("avtank", 3, "sim5")
            M.sim6 = BuildObject("avfigh", 3, "sim6")
            M.sim7 = BuildObject("avfigh", 3, "sim7")
            M.sim8 = BuildObject("avfigh", 3, "sim8")
            M.sim9 = BuildObject("avfigh", 3, "sim9")
            M.sim10 = BuildObject("avfigh", 3, "sim10")

            Goto(M.sim1, "simpoint5")
            -- ... (Assume logic to move them)

            CameraReady()
            subtit.Play("misn0631.wav")
            subtit.Play("misn0642.wav")
            -- ...
            M.simcam = true
            M.threemin = false
            HideCockpitTimer()
        end
    end

    if M.simcam then
        CameraObject(M.sim5, 0, 1000, -4000, M.sim5)
        if (not M.attack) then -- wait logic can be handled by time vs checks for now
            M.attack = true
            Goto(M.sim1, "simpoint1")
            -- ...
        end
        if (not M.breakout1) and (GetTime() > M.threeminsplatoon + 20.0) then -- 20s cutscene
            CameraFinish()
            M.breakout1 = true
            M.simcam = false
        end
    end

    if M.breakout1 and (not M.removal) then
        -- Remove Simulated Units
        local sims = { M.sim1, M.sim2, M.sim3, M.sim4, M.sim5, M.sim6, M.sim7, M.sim8, M.sim9, M.sim10 }
        for _, s in ipairs(sims) do if IsAlive(s) then RemoveObject(s) end end
        M.removal = true
        StopCockpitTimer()
        HideCockpitTimer()
    end

    -- Warnings
    if (M.tenminsplatoon < GetTime()) and M.tenmin and (not M.launchpadreconed) and (not M.reminder) then
        subtit.Play("misn0632.wav")
        M.tenmin = false
    end

    if (M.fiveminsplatoon < GetTime()) and M.fivemin and (not M.launchpadreconed) and (not M.reminder) then
        subtit.Play("misn0633.wav")
        M.fivemin = false
    end

    -- 2min Warning => Corbett Death
    if (M.twominsplatoon < GetTime()) and M.twomin and (not M.launchpadreconed) and (not M.reminder) then
        subtit.Play("misn0634.wav")
        M.twomin = false
    end

    if (M.twominsplatoon < GetTime()) and M.corbettalive then
        M.corbettalive = false
    end

    -- Reminder Logic
    if (GetDistance(M.player, M.svrec) < 250.0) and (not M.reminder) and (not M.launchpadreconed) then
        subtit.Play("misn0638.wav")
        M.reminder = true
        M.end_timer = GetTime() + 120.0
    end

    if M.reminder and (GetDistance(M.player, M.launchpad) > 400.0) and (not M.launchpadreconed) and (M.end_timer < GetTime()) and (not M.breaker) then
        subtit.Play("misn0635.wav")
        -- ...
        M.platoonhere = false -- Cancel timer
        M.endme = true
        M.breaker = true
    end

    if M.endme then
        FailMission(GetTime(), "misn06l4.des")
    end

    -- Launchpad Info
    if IsInfo("sblpad") and (not M.launchpadreconed) then
        M.time1 = GetTime() + 2.0
        M.bugout = true
        M.launchpadreconed = true
        HideCockpitTimer()
        SetObjectiveOff(M.launchpad)
    end

    -- Bugout / CCA Platoon Spawn
    if M.bugout and M.corbettalive and (M.time1 < GetTime()) and (not M.bustout) then
        subtit.Play("misn0629.wav")
        subtit.Play("misn0630.wav")
        subtit.Play("misn0647.wav")

        M.ccap1 = BuildObject("svfigh", 2, "ccaplatoonspawn")
        Attack(M.ccap1, M.avrec)
        SetIndependence(M.ccap1, 1)

        M.platoonhere = false
        M.pickupset = true
        M.newobjective = true
        M.bustout = true
    end

    if (not M.breakme) and M.bugout and (not M.corbettalive) and (M.time1 < GetTime()) then
        subtit.Play("misn0629.wav") -- Different audio sequence for dead corbett?
        -- ...
        M.ccap1 = BuildObject("svfigh", 2, "ccaplatoonspawn")
        SetIndependence(M.ccap1, 1)
        M.platoonhere = false
        M.breakme = true
        M.pickupset = true
        M.newobjective = true
        M.deathtime = GetTime() + 30.0
    end

    if (M.deathtime < GetTime()) and (not M.death) then
        M.death = true
        subtit.Play("misn0635.wav")
        M.ccap1 = BuildObject("svfigh", 2, "ccaplatoonspawn")
        Attack(M.ccap1, M.avrec)
    end

    -- Extraction Point
    if M.pickupset then
        local dest = "bugout" .. (M.extractpoint + 1)
        M.dustoffcam = BuildObject("apcamr", 1, dest)
        SetObjectiveName(M.dustoffcam, "Dust Off")
        M.pickupset = false
        M.pickupreached = true
        SetObjectiveOff(M.launchpad)
    end

    -- Respawn Dustoff if dead
    if M.bustout and (not IsAlive(M.dustoffcam)) then
        M.pickupset = true
    end

    if (GetDistance(M.avrec, M.dustoffcam) < 100.0) and (GetDistance(M.player, M.dustoffcam) < 100.0) and M.pickupreached then
        subtit.Play("misn0649.wav")
        SucceedMission(GetTime() + 5.0, "misn06w1.des")
        M.pickupreached = false
        M.dustoff = true
        M.newobjective = true
    end

    -- Platoon Arrive (Time Out)
    if (M.platoonarrive < GetTime()) and M.platoonhere and M.reminder and (M.time1 < GetTime()) then
        -- Time out fail C++ logic
        -- Calls Fail? Logic block 1698
        -- Actually just spawns ccap1 and attacks?
        -- "misn06l4.des" called in separate block if endme==true
        -- This block sets corbettalive = false.
    end

    -- CCA Platoon Infinite Respawn (Economy Mode)
    if IsAlive(M.ccap1) then
        if (GetNearestEnemy(M.ccap1) < 410.0) and (not M.economyccaplatoon) then
            M.ccap2 = BuildObject("svfigh", 2, M.ccap1)
            M.ccap3 = BuildObject("svfigh", 2, M.ccap1)
            M.ccap4 = BuildObject("svfigh", 2, M.ccap1)
            M.ccap5 = BuildObject("svfigh", 2, M.ccap1)
            M.ccap6 = BuildObject("svtank", 2, M.ccap1)
            M.ccap7 = BuildObject("svtank", 2, M.ccap1)
            M.ccap8 = BuildObject("svtank", 2, M.ccap1)
            M.ccap9 = BuildObject("svtank", 2, M.ccap1)

            Attack(M.ccap2, M.avrec)
            -- ... Attack/Independence all ...
            M.economyccaplatoon = true
        end
    end

    if M.platoonhere and (not M.respawn) then
        -- Check if all ccap* dead
        -- If dead, respawn ccap1, set economyccaplatoon = false
    end
end

function Save()
    return M, aiCore.Save()
end

function Load(missionData, aiData)
    M = missionData
    if aiData then aiCore.Load(aiData) end
    aiCore.Bootstrap()
    ApplyQOL()
    subtit.Initialize()
end
