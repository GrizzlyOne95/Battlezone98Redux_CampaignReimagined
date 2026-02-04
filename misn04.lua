-- misn04.lua
-- Converted from Misn04Mission.cpp

-- Compatibility for 1.5
SetLabel = SetLabel or SettLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
local exu = require("exu")

local M = {
    -- Bools
    missionstart = false,
    basesecure = false,
    relicsecure = false,
    missionfail2 = false,
    done = false,
    firstwave = false,
    found = false,
    ccahasrelic = false,
    build2 = false,
    build3 = false,
    build4 = false,
    build5 = false,
    secondwave = false,
    thirdwave = false,
    fourthwave = false,
    secureloopbreak = false,
    chewedout = false,
    fifthwave = false,
    possiblewin = false,
    attackccabase = false,
    endmission = false,
    fifthwavedestroyed = false,
    ccabasedestroyed = false,
    surveysent = false,
    reconsent = false,
    discrelic = false,
    missionend = false,
    loopbreak = false,
    loopbreak2 = false,
    halfway = false,
    ccatugsent = false,
    cin1done = false,
    wave1arrive = false,
    wave2arrive = false,
    wave3arrive = false,
    wave4arrive = false,
    wave5arrive = false,
    obset = false,
    discoverrelic = false,
    newobjective = false,
    relicmoved = false,
    cheater = false,
    relicseen = false,
    retreat = false,
    missionwon = false,
    missionfail = false,
    wave1dead = false,
    wave2dead = false,
    wave3dead = false,
    wave4dead = false,
    wave5dead = false,
    endcinfinish = false,
    tur1sent = false,
    tur2sent = false,
    tur3sent = false,
    tur4sent = false,
    
    -- Floats
    wave1 = 99999.0,
    wave2 = 99999.0,
    wave3 = 99999.0,
    wave4 = 99999.0,
    wave5 = 99999.0,
    fetch = 99999.0,
    reconcca = 99999.0,
    startendcin = 99999.0,
    endcindone = 99999.0,
    notfound = 99999.0,
    ccatug = 99999.0,
    cintime1 = 99999.0,
    tur1 = 99999.0,
    tur2 = 99999.0,
    tur3 = 99999.0,
    tur4 = 99999.0,
    investigate = 99999.0,

    -- Handles
    svrec = nil,
    pu1 = nil, pu2 = nil, pu3 = nil, pu4 = nil, pu5 = nil, pu6 = nil, pu7 = nil, pu8 = nil,
    navbeacon = nil,
    cheat1 = nil, cheat2 = nil, cheat3 = nil, cheat4 = nil, cheat5 = nil, cheat6 = nil,
    tug = nil, svtug = nil, tuge1 = nil, tuge2 = nil,
    player = nil,
    surv1 = nil, surv2 = nil, surv3 = nil, surv4 = nil,
    cam1 = nil, cam2 = nil, cam3 = nil, basecam = nil, reliccam = nil,
    avrec = nil,
    w1u1 = nil, w1u2 = nil,
    w2u1 = nil, w2u2 = nil, w2u3 = nil,
    w3u1 = nil, w3u2 = nil, w3u3 = nil, w3u4 = nil,
    w4u1 = nil, w4u2 = nil, w4u3 = nil, w4u4 = nil, w4u5 = nil,
    w5u1 = nil, w5u2 = nil, w5u3 = nil, w5u4 = nil, w5u5 = nil, w5u6 = nil,
    relic = nil,
    turret1 = nil, turret2 = nil, turret3 = nil, turret4 = nil,
    new_tank1 = nil, new_tank2 = nil,
    wingtank2 = nil, wingtank3 = nil,
    wingman1 = nil, wingman2 = nil, wingtank1 = nil,

    -- Integers
    relicstartpos = 0,
    wavenumber = 1,
    investigator = 0,
    warn = 0,
    
    -- Audio Handles (simulated as ints/handles in Lua)
    aud1 = nil, aud2 = nil, aud3 = nil, aud4 = nil,
    aud10 = nil, aud11 = nil, aud12 = nil, aud13 = nil, aud14 = nil,
    aud20 = nil, aud21 = nil, aud22 = nil, aud23 = nil,
    audmsg = nil
}

function Save()
    return M
end

function Load(data)
    if data then
        M = data
    end
end

function Start()
    M.relicstartpos = math.random(0, 3)
    SetScrap(1, 20)
    
    M.wave2 = 99999.0
    M.wave3 = 99999.0
    M.wave4 = 99999.0
    M.wave5 = 99999.0
    M.endcindone = 99999.0
    M.startendcin = 99999.0
    M.ccatug = 999999999999.0
    M.notfound = 999999999999999.0
    M.investigate = 999999999.0
    M.tur1 = 999999999.0
    M.tur2 = 999999999.0
    M.tur3 = 999999999.0
    M.tur4 = 999999999.0
    M.cintime1 = 9999999999.0
end

function AddObject(h)
    local team = GetTeamNum(h)

    -- Apply turbo to new enemy units on Very Hard difficulty
    if exu and exu.SetUnitTurbo and IsCraft(h) then
        if team == 1 then
            exu.SetUnitTurbo(h, true)
        elseif team ~= 0 then
            local diff = (exu.GetDifficulty and exu.GetDifficulty()) or 2
            if diff > 3 then
                exu.SetUnitTurbo(h, true)
            end
        end
    end

    if GetTeamNum(h) == 1 and IsOdf(h, "avhaul") then
        M.found = true
        M.tug = h
    end
end

function Update()
    M.player = GetPlayerHandle()
    if exu and exu.UpdateOrdnance then exu.UpdateOrdnance() end

    -- Get difficulty for dynamic adjustments (0=Very Easy, 1=Easy, 2=Medium, 3=Hard, 4=Very Hard)
    local diff = 2
    if exu and exu.GetDifficulty then diff = exu.GetDifficulty() end

    if not M.missionstart then
        if exu then
            local ver = (type(exu.GetVersion) == "function" and exu.GetVersion()) or exu.version or "Unknown"
            print("EXU Version: " .. tostring(ver))
            print("Difficulty: " .. tostring(diff))

            if diff >= 3 then
                AddObjective("hard_diff", "red", 8.0, "High Difficulty: Enemy presence intensified.")
            elseif diff <= 1 then
                AddObjective("easy_diff", "green", 8.0, "Low Difficulty: Enemy presence reduced.")
            end

            -- Apply turbo to existing units
            if exu.SetUnitTurbo then
                for h in AllCraft() do
                    if GetTeamNum(h) == 1 then
                        exu.SetUnitTurbo(h, true)
                    elseif GetTeamNum(h) ~= 0 and diff > 3 then
                        exu.SetUnitTurbo(h, true)
                    end
                end
            end

            if exu.EnableShotConvergence then exu.EnableShotConvergence() end
            if exu.SetSmartCursorRange then exu.SetSmartCursorRange(500) end
            if exu.EnableOrdnanceTweak then exu.EnableOrdnanceTweak(1.0) end
            if exu.SetSelectNone then exu.SetSelectNone(false) end
        end

        -- Dynamic Starting Scrap
        local start_scrap = 20
        if diff <= 1 then start_scrap = 30
        elseif diff >= 3 then start_scrap = 15 end
        SetScrap(1, start_scrap)

        local diff_mod = 0
        if diff <= 1 then diff_mod = 15.0
        elseif diff >= 3 then diff_mod = -10.0 end

        M.wave1 = GetTime() + 30.0 + diff_mod
        M.fetch = GetTime() + 240.0 -- change to 350.0f
        AudioMessage("misn0401.wav")
        
        M.cam1 = GetHandle("apcamr352_camerapod")
        M.cam2 = GetHandle("apcamr350_camerapod")
        M.cam3 = GetHandle("apcamr351_camerapod")
        M.basecam = GetHandle("apcamr-1_camerapod")
        M.svrec = GetHandle("svrecy-1_recycler")
        M.avrec = GetHandle("avrecy-1_recycler")
        M.relic = BuildObject("obdata", 0, "relicstart1")
        
        M.pu1 = GetHandle("svfigh-1_wingman")
        M.pu3 = GetHandle("svfigh282_wingman")
        M.pu6 = GetHandle("svfigh279_wingman")
        M.pu8 = GetHandle("svfigh278_wingman")
        
        -- Additional handles needed for logic later
        M.wingman1 = GetHandle("avfigh1")
        M.wingman2 = GetHandle("avfigh2") -- Assuming name based on context
        M.wingtank1 = GetHandle("avtank1")
        M.wingtank2 = GetHandle("avtank2")
        M.wingtank3 = GetHandle("avtank3")

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
        
        M.tur1 = GetTime() + 30.0
        M.tur2 = GetTime() + 45.0
        M.tur3 = GetTime() + 60.0
        M.tur4 = GetTime() + 75.0
        M.investigate = GetTime() + 3.0
    end

    if IsAlive(M.cam1) then AddHealth(M.cam1, 1000) end
    if IsAlive(M.cam2) then AddHealth(M.cam2, 1000) end
    if IsAlive(M.cam3) then AddHealth(M.cam3, 1000) end

    if not M.relicmoved and IsAlive(M.relic) then
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

    if not M.reconsent and not M.cheater and IsAlive(M.relic) and GetDistance(M.player, M.relic) < 600.0 then
        M.cheat1 = BuildObject("svfigh", 2, M.relic)
        M.cheat2 = BuildObject("svfigh", 2, M.relic)
        M.cheat3 = BuildObject("svfigh", 2, M.relic)
        M.cheat4 = BuildObject("svfigh", 2, M.relic)
        M.cheat5 = BuildObject("svfigh", 2, M.relic)
        M.cheat6 = BuildObject("svfigh", 2, M.relic)
        
        local path_a = "relicpatrolpath1a"
        local path_b = "relicpatrolpath1b"
        
        if M.relicstartpos == 1 then
            path_a = "relicpatrolpath2a"
            path_b = "relicpatrolpath2b"
        elseif M.relicstartpos == 2 then
            path_a = "relicpatrolpath3a"
            path_b = "relicpatrolpath3b"
        elseif M.relicstartpos == 3 then
            path_a = "relicpatrolpath4a"
            path_b = "relicpatrolpath4b"
        end
        
        Patrol(M.cheat1, path_a)
        Patrol(M.cheat2, path_a)
        Patrol(M.cheat3, path_a)
        Patrol(M.cheat4, path_b)
        Patrol(M.cheat5, path_b)
        Patrol(M.cheat6, path_b)
        
        SetIndependence(M.cheat1, 1)
        SetIndependence(M.cheat2, 1)
        SetIndependence(M.cheat3, 1)
        SetIndependence(M.cheat4, 1)
        SetIndependence(M.cheat5, 1)
        SetIndependence(M.cheat6, 1)
        
        M.surveysent = true
        M.cheater = true
        M.reconcca = GetTime()
    end

    if M.fetch < GetTime() and not M.surveysent and IsAlive(M.relic) then
        M.surv1 = BuildObject("svfigh", 2, M.relic)
        M.surv2 = BuildObject("svfigh", 2, M.relic)
        
        local path_a = "relicpatrolpath1a"
        local path_b = "relicpatrolpath1b"
        
        if M.relicstartpos == 1 then
            path_a = "relicpatrolpath2a"
            path_b = "relicpatrolpath2b"
        elseif M.relicstartpos == 2 then
            path_a = "relicpatrolpath3a"
            path_b = "relicpatrolpath3b"
        elseif M.relicstartpos == 3 then
            path_a = "relicpatrolpath4a"
            path_b = "relicpatrolpath4b"
        end
        
        Patrol(M.surv1, path_a)
        Patrol(M.surv2, path_b)
        SetIndependence(M.surv1, 1)
        SetIndependence(M.surv2, 1)
        
        M.surveysent = true
        M.reconcca = GetTime() + 60
    end

    if not M.tur1sent and M.tur1 < GetTime() and IsAlive(M.svrec) then
        M.turret1 = BuildObject("svturr", 2, M.svrec)
        Goto(M.turret1, "turret1")
        M.tur1sent = true
    end
    if not M.tur2sent and M.tur2 < GetTime() and IsAlive(M.svrec) then
        M.turret2 = BuildObject("svturr", 2, M.svrec)
        Goto(M.turret2, "turret2")
        M.tur2sent = true
    end
    if not M.tur3sent and M.tur3 < GetTime() and IsAlive(M.svrec) then
        M.turret3 = BuildObject("svturr", 2, M.svrec)
        Goto(M.turret3, "turret3")
        M.tur3sent = true
    end
    if not M.tur4sent and M.tur4 < GetTime() and IsAlive(M.svrec) then
        M.turret4 = BuildObject("svturr", 2, M.svrec)
        Goto(M.turret4, "turret4")
        M.tur4sent = true
    end

    if M.reconcca < GetTime() and not M.reconsent and M.surveysent then
        M.aud4 = AudioMessage("misn0406.wav")
        local cam_spawn = "reliccam1"
        if M.relicstartpos == 1 then cam_spawn = "reliccam2"
        elseif M.relicstartpos == 2 then cam_spawn = "reliccam3"
        elseif M.relicstartpos == 3 then cam_spawn = "reliccam4" end
        
        M.reliccam = BuildObject("apcamr", 1, cam_spawn)
        
        M.reconsent = true
        M.obset = true
        M.notfound = GetTime() + 90.0
    end

    if M.obset and IsAudioMessageDone(M.aud4) then
        SetObjectiveName(M.reliccam, "Investigate CCA")
        M.newobjective = true
        M.obset = false
    end

    if M.found and not M.halfway and IsAlive(M.tug) then
        if HasCargo(M.tug) then
            AudioMessage("misn0419.wav")
            M.halfway = true
            SetObjectiveOff(M.relic)
            if IsAlive(M.tuge1) then Attack(M.tuge1, M.tug) end
            if IsAlive(M.tuge2) then Attack(M.tuge2, M.tug) end
        end
    end

    if M.reconsent then
        if IsAlive(M.relic) and IsAlive(M.avrec) and GetDistance(M.relic, M.avrec) < 100.0 and not M.relicsecure then
            M.aud23 = AudioMessage("misn0420.wav")
            M.relicsecure = true
            M.newobjective = true
        end
    end

    if M.ccatug < GetTime() and not M.ccatugsent and IsAlive(M.svrec) then
        M.svtug = BuildObject("svhaul", 2, M.svrec)
        M.tuge1 = BuildObject("svfigh", 2, M.svrec)
        M.tuge2 = BuildObject("svfigh", 2, M.svrec)
        Pickup(M.svtug, M.relic)
        Follow(M.tuge1, M.svtug)
        Follow(M.tuge2, M.svtug)
        M.ccatugsent = true
    end

    if M.ccatugsent and not M.ccahasrelic and IsAlive(M.svtug) then
        if HasCargo(M.svtug) and (not IsAlive(M.tug) or not HasCargo(M.tug)) then
            M.ccahasrelic = true
            Goto(M.svtug, "dropoff")
            AudioMessage("misn0427.wav")
            SetObjectiveOn(M.svtug)
            SetObjectiveName(M.svtug, "CCA Tug")
        end
    end

    if M.ccahasrelic and IsAlive(M.svtug) and IsAlive(M.svrec) and GetDistance(M.svtug, M.svrec) < 60.0 and not M.missionfail2 then
        M.aud10 = AudioMessage("misn0431.wav")
        M.aud11 = AudioMessage("misn0432.wav")
        M.aud12 = AudioMessage("misn0433.wav")
        M.aud13 = AudioMessage("misn0434.wav")
        M.missionfail2 = true
        CameraReady()
    end

    if M.missionfail2 and not M.done then
        CameraPath("ccareliccam", 3000, 1000, M.svtug)
        if (IsAudioMessageDone(M.aud10) and IsAudioMessageDone(M.aud11) and IsAudioMessageDone(M.aud12) and IsAudioMessageDone(M.aud13)) or CameraCancelled() then
            CameraFinish()
            StopAudioMessage(M.aud10)
            StopAudioMessage(M.aud11)
            StopAudioMessage(M.aud12)
            StopAudioMessage(M.aud13)
            FailMission(GetTime(), "misn04l1.des")
            M.done = true
        end
    end

    if not M.discoverrelic and M.reconsent and M.notfound < GetTime() and not M.ccahasrelic and M.warn < 4 then
        AudioMessage("misn0429.wav")
        M.notfound = GetTime() + 85.0
        M.warn = M.warn + 1
    end

    if M.warn == 4 and M.notfound < GetTime() and not M.missionfail then
        M.aud14 = AudioMessage("misn0694.wav")
        M.missionfail = true
    end
    
    if M.missionfail then
        if M.warn == 4 and IsAudioMessageDone(M.aud14) then
            FailMission(GetTime(), "misn04l4.des")
            M.warn = 0
        end
    end

    if not M.discoverrelic then
        if M.investigate < GetTime() then
            M.investigator = CountUnitsNearObject(M.relic, 400.0, 1, nil)
            if IsAlive(M.reliccam) then
                M.investigator = M.investigator - 1
            end
        end

        if M.investigator >= 1 then
            M.aud2 = AudioMessage("misn0408.wav")
            M.aud3 = AudioMessage("misn0409.wav")
            M.relicseen = true
            M.newobjective = true
            M.ccatug = GetTime() + 200.0 -- change to 240.0f
            M.discoverrelic = true
            CameraReady()
            M.cintime1 = GetTime() + 23.0
        end
    end

    if M.discoverrelic and not M.cin1done then
        if (IsAudioMessageDone(M.aud2) and IsAudioMessageDone(M.aud3)) or CameraCancelled() then
            CameraFinish()
            StopAudioMessage(M.aud2)
            StopAudioMessage(M.aud3)
            M.cin1done = true
        end
    end

    if M.discoverrelic and M.cintime1 > GetTime() and not M.cin1done then
        local cam_path = "reliccin1"
        if M.relicstartpos == 1 then cam_path = "reliccin2"
        elseif M.relicstartpos == 2 then cam_path = "reliccin3"
        elseif M.relicstartpos == 3 then cam_path = "reliccin4" end
        CameraPath(cam_path, 500, 400, M.relic)
    end

    if M.newobjective then
        ClearObjectives()
        if not M.basesecure then
            AddObjective("misn0401.otf", "white")
        else
            AddObjective("misn0401.otf", "green")
        end

        if not M.relicsecure and M.relicseen then
            AddObjective("misn0403.otf", "white")
        end
        if M.relicsecure then
            AddObjective("misn0403.otf", "green")
        end
        
        if M.reconsent and not M.discoverrelic then
            AddObjective("misn0405.otf", "white")
        end
        if M.discoverrelic then
            AddObjective("misn0405.otf", "green")
        end
        
        M.newobjective = false
    end

    if M.wavenumber == 1 and GetTime() > M.wave1 then
        M.w1u1 = BuildObject("svfigh", 2, "wave1")
        Attack(M.w1u1, M.avrec, 1)
        SetIndependence(M.w1u1, 1)

        if diff > 0 then
            M.w1u2 = BuildObject("svfigh", 2, "wave1")
            Attack(M.w1u2, M.avrec, 1)
            SetIndependence(M.w1u2, 1)
        end

        if diff >= 3 then
            local extra = BuildObject("svfigh", 2, "wave1")
            Attack(extra, M.avrec, 1)
            SetIndependence(extra, 1)
        end

        M.wavenumber = 2
        M.wave1arrive = false
    end

    if M.wavenumber == 2 and not IsAlive(M.w1u1) and not IsAlive(M.w1u2) and not M.build2 then
        M.wave2 = GetTime() + 60.0
        M.build2 = true
        M.wave1dead = true
    end

    if M.wave2 < GetTime() and IsAlive(M.svrec) then
        M.w2u1 = BuildObject("svtank", 2, "spawn2new")
        Goto(M.w2u1, M.avrec, 1)
        SetIndependence(M.w2u1, 1)

        if diff > 0 then
            M.w2u2 = BuildObject("svfigh", 2, "spawn2new")
            Goto(M.w2u2, M.avrec, 1)
            SetIndependence(M.w2u2, 1)
        end

        if diff >= 3 then
            local extra = BuildObject("svtank", 2, "spawn2new")
            Goto(extra, M.avrec, 1)
            SetIndependence(extra, 1)
        end

        M.wavenumber = 3
        M.wave2arrive = false
        M.wave2 = 99999.0
    end

    if M.wavenumber == 3 and not IsAlive(M.w2u1) and not IsAlive(M.w2u2) and not M.build3 then
        M.wave3 = GetTime() + 74.0
        M.build3 = true
        M.wave2dead = true
    end

    if M.wave3 < GetTime() and IsAlive(M.svrec) then
        M.w3u1 = BuildObject("svfigh", 2, M.svrec)
        Goto(M.w3u1, M.avrec, 1)
        SetIndependence(M.w3u1, 1)

        if diff > 0 then
            M.w3u2 = BuildObject("svfigh", 2, M.svrec)
            Goto(M.w3u2, M.avrec, 1)
            SetIndependence(M.w3u2, 1)
        end

        if diff > 1 then
            M.w3u3 = BuildObject("svfigh", 2, M.svrec)
            Goto(M.w3u3, M.avrec, 1)
            SetIndependence(M.w3u3, 1)
        end

        if diff >= 3 then
            local extra = BuildObject("svfigh", 2, M.svrec)
            Goto(extra, M.avrec, 1)
            SetIndependence(extra, 1)
        end

        M.wavenumber = 4
        M.wave3arrive = false
        M.wave3 = 99999.0
    end

    if M.wavenumber == 4 and not IsAlive(M.w3u1) and not IsAlive(M.w3u2) and not IsAlive(M.w3u3) and not M.build4 then
        M.wave4 = GetTime() + 60.0
        M.build4 = true
        M.wave3dead = true
    end

    if M.wave4 < GetTime() and IsAlive(M.svrec) then
        M.w4u1 = BuildObject("svtank", 2, "spawnotherside")
        Goto(M.w4u1, M.avrec, 1)
        SetIndependence(M.w4u1, 1)

        if diff > 0 then
            M.w4u2 = BuildObject("svfigh", 2, "spawnotherside")
            Goto(M.w4u2, M.avrec, 1)
            SetIndependence(M.w4u2, 1)
        end

        if diff > 1 then
            M.w4u3 = BuildObject("svfigh", 2, "spawnotherside")
            Goto(M.w4u3, M.avrec, 1)
            SetIndependence(M.w4u3, 1)
        end

        if diff >= 3 then
            local extra = BuildObject("svtank", 2, "spawnotherside")
            Goto(extra, M.avrec, 1)
            SetIndependence(extra, 1)
        end

        M.wavenumber = 5
        M.wave4arrive = false
        M.wave4 = 99999.0
    end

    if M.wavenumber == 5 and not IsAlive(M.w4u1) and not IsAlive(M.w4u2) and not IsAlive(M.w4u3) and not M.build5 then
        M.wave5 = GetTime() + 30.0
        M.build5 = true
        M.wave4dead = true
    end

    if M.wave5 < GetTime() and IsAlive(M.svrec) then
        M.w5u1 = BuildObject("svtank", 2, M.svrec)
        Goto(M.w5u1, M.avrec, 1)
        SetIndependence(M.w5u1, 1)

        if diff > 0 then
            M.w5u2 = BuildObject("svfigh", 2, M.svrec)
            Goto(M.w5u2, M.avrec, 1)
            SetIndependence(M.w5u2, 1)
        end

        if diff > 1 then
            M.w5u3 = BuildObject("svfigh", 2, M.svrec)
            Goto(M.w5u3, M.avrec, 1)
            SetIndependence(M.w5u3, 1)
            
            M.w5u4 = BuildObject("svfigh", 2, M.svrec)
            Goto(M.w5u4, M.avrec, 1)
            SetIndependence(M.w5u4, 1)
        end

        if diff >= 3 then
            local extra = BuildObject("svtank", 2, M.svrec)
            Goto(extra, M.avrec, 1)
            SetIndependence(extra, 1)
        end

        M.wavenumber = 6
        M.wave5arrive = false
        M.wave5 = 99999.0
    end

    if not M.wave1arrive and IsAlive(M.avrec) then
        if (IsAlive(M.w1u1) and GetDistance(M.avrec, M.w1u1) < 300.0) or (IsAlive(M.w1u2) and GetDistance(M.avrec, M.w1u2) < 300.0) then
            AudioMessage("misn0402.wav")
            M.wave1arrive = true
            M.wave1dead = true
        end
    end

    if not M.wave2arrive and IsAlive(M.avrec) then
        if (IsAlive(M.w2u1) and GetDistance(M.avrec, M.w2u1) < 300.0) or (IsAlive(M.w2u2) and GetDistance(M.avrec, M.w2u2) < 300.0) then
            AudioMessage("misn0404.wav")
            M.wave2arrive = true
        end
    end

    if not M.wave3arrive and IsAlive(M.avrec) then
        if (IsAlive(M.w3u1) and GetDistance(M.avrec, M.w3u1) < 300.0) or (IsAlive(M.w3u2) and GetDistance(M.avrec, M.w3u2) < 300.0) or (IsAlive(M.w3u3) and GetDistance(M.avrec, M.w3u3) < 300.0) then
            AudioMessage("misn0410.wav")
            M.wave3arrive = true
        end
    end

    if not M.wave4arrive and IsAlive(M.avrec) then
        if (IsAlive(M.w4u1) and GetDistance(M.avrec, M.w4u1) < 300.0) or (IsAlive(M.w4u2) and GetDistance(M.avrec, M.w4u2) < 300.0) or (IsAlive(M.w4u3) and GetDistance(M.avrec, M.w4u3) < 300.0) then
            AudioMessage("misn0412.wav")
            M.wave4arrive = true
        end
    end

    if not M.wave5arrive and IsAlive(M.avrec) then
        if (IsAlive(M.w5u1) and GetDistance(M.avrec, M.w5u1) < 300.0) or (IsAlive(M.w5u2) and GetDistance(M.avrec, M.w5u2) < 300.0) or (IsAlive(M.w5u3) and GetDistance(M.avrec, M.w5u3) < 300.0) or (IsAlive(M.w5u4) and GetDistance(M.avrec, M.w5u4) < 300.0) then
            AudioMessage("misn0414.wav")
            M.wave5arrive = true
        end
    end

    if not M.attackccabase and IsAlive(M.svrec) and GetDistance(M.player, M.svrec) < 300.0 then
        AudioMessage("misn0423.wav")
        M.attackccabase = true
    end

    if M.wave1dead and not IsAlive(M.w1u1) and not IsAlive(M.w1u2) then
        AudioMessage("misn0403.wav")
        M.wave1dead = false
    end

    if M.wave2dead then
        AudioMessage("misn0405.wav")
        M.wave2dead = false
    end
    if M.wave3dead then
        AudioMessage("misn0411.wav")
        M.wave3dead = false
    end
    if M.wave4dead then
        AudioMessage("misn0413.wav")
        M.wave4dead = false
    end

    if not M.loopbreak and not M.possiblewin and not M.missionwon and not IsAlive(M.svrec) then
        AudioMessage("misn0417.wav")
        M.possiblewin = true
        M.chewedout = true
        
        local enemies_alive = false
        if IsAlive(M.w1u1) or IsAlive(M.w1u2) or IsAlive(M.w2u1) or IsAlive(M.w2u2) or IsAlive(M.w3u1) or IsAlive(M.w3u2) or IsAlive(M.w3u3) or IsAlive(M.w4u1) or IsAlive(M.w4u2) or IsAlive(M.w4u3) or IsAlive(M.w5u1) or IsAlive(M.w5u2) or IsAlive(M.w5u3) or IsAlive(M.w5u4) then
            enemies_alive = true
        end

        if not IsAlive(M.svrec) and enemies_alive then
            AudioMessage("misn0418.wav")
            M.loopbreak = true
        end
    end

    if not M.basesecure and not IsAlive(M.svrec) and
       not IsAlive(M.w1u1) and not IsAlive(M.w1u2) and
       not IsAlive(M.w2u1) and not IsAlive(M.w2u2) and
       not IsAlive(M.w3u1) and not IsAlive(M.w3u2) and not IsAlive(M.w3u3) and
       not IsAlive(M.w4u1) and not IsAlive(M.w4u2) and not IsAlive(M.w4u3) and
       not IsAlive(M.w5u1) and not IsAlive(M.w5u2) and not IsAlive(M.w5u3) and not IsAlive(M.w5u4) then
        M.basesecure = true
        M.newobjective = true
    end

    if M.relicsecure and M.basesecure then
        M.missionwon = true
    end

    if M.missionwon and not M.endmission then
        if IsAudioMessageDone(M.aud20) and IsAudioMessageDone(M.aud21) and IsAudioMessageDone(M.aud22) and IsAudioMessageDone(M.aud23) then
            SucceedMission(GetTime(), "misn04w1.des")
        end
    end

    if not M.missionwon and not IsAlive(M.avrec) and not M.missionfail then
        AudioMessage("misn0421.wav")
        AudioMessage("misn0422.wav")
        M.missionfail = true
        FailMission(GetTime() + 20.0, "misn04l3.des")
    end

    if not M.basesecure and not M.secureloopbreak and M.wavenumber == 6 and
       not IsAlive(M.w5u1) and not IsAlive(M.w5u2) and not IsAlive(M.w5u3) and not IsAlive(M.w5u4) and
       IsAlive(M.svrec) then
       
        if not M.retreat then
            if IsAlive(M.tuge1) then Retreat(M.tuge1, "retreatpoint") end
            if IsAlive(M.tuge2) then Retreat(M.tuge2, "retreatpoint28") end
            if IsAlive(M.pu1) then Retreat(M.pu1, "retreatpoint27") end
            if IsAlive(M.pu3) then Retreat(M.pu3, "retreatpoint25") end
            if IsAlive(M.pu6) then Retreat(M.pu6, "retreatpoint22") end
            if IsAlive(M.pu8) then Retreat(M.pu8, "retreatpoint20") end
            if IsAlive(M.cheat1) then Retreat(M.cheat1, "retreatpoint19") end
            if IsAlive(M.cheat2) then Retreat(M.cheat2, "retreatpoint18") end
            if IsAlive(M.cheat3) then Retreat(M.cheat3, "retreatpoint17") end
            if IsAlive(M.cheat4) then Retreat(M.cheat4, "retreatpoint16") end
            if IsAlive(M.cheat5) then Retreat(M.cheat5, "retreatpoint15") end
            if IsAlive(M.cheat6) then Retreat(M.cheat6, "retreatpoint14") end
            if IsAlive(M.surv1) then Retreat(M.surv1, "retreatpoint9") end
            if IsAlive(M.surv2) then Retreat(M.surv2, "retreatpoint8") end
            if IsAlive(M.turret1) then Retreat(M.turret1, "retreatpoint2") end
            if IsAlive(M.turret2) then Retreat(M.turret2, "retreatpoint3") end
            if IsAlive(M.turret3) then Retreat(M.turret3, "retreatpoint4") end
            if IsAlive(M.turret4) then Retreat(M.turret4, "retreatpoint5") end
            M.retreat = true
        end

        M.aud21 = AudioMessage("misn0415.wav")
        M.aud22 = AudioMessage("misn0416.wav")
        M.basesecure = true
        M.newobjective = true
        M.secureloopbreak = true
    end

    if not IsAlive(M.relic) and not M.missionfail then
        FailMission(GetTime() + 20.0, "misn04l2.des")
        AudioMessage("misn0431.wav")
        AudioMessage("misn0432.wav")
        AudioMessage("misn0433.wav")
        AudioMessage("misn0434.wav")
        M.missionfail = true
    end

    if not M.basesecure and not M.secureloopbreak and M.wavenumber == 6 and
       not IsAlive(M.w5u1) and not IsAlive(M.w5u2) and not IsAlive(M.w5u3) and not IsAlive(M.w5u4) and
       not IsAlive(M.svrec) and M.chewedout then
        M.aud20 = AudioMessage("misn0425.wav")
        M.basesecure = true
        M.newobjective = true
        M.secureloopbreak = true
    end
end
