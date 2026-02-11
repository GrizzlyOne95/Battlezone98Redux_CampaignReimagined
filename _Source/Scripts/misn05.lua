-- Misn05 Mission Script (Converted from Misn05Mission.cpp)

-- Compatibility for 1.5
SetLabel = SetLabel or SettLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
local exu = require("exu")
local aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")
local subtit = require("ScriptSubtitles")

-- Helper for AI
local function SetupAI()
    DiffUtils.SetupTeams(aiCore.Factions.NSDF, aiCore.Factions.CCA, 2)
    
    -- Configure Player Team (1) for Scavenger Assist
    if aiCore.ActiveTeams and aiCore.ActiveTeams[1] then
        aiCore.ActiveTeams[1]:SetConfig("scavengerAssist", true)
    end
    
    -- Configure CCA (Team 2)
    if aiCore and aiCore.ActiveTeams and aiCore.ActiveTeams[2] then
        aiCore.ActiveTeams[2]:SetStrategy("Balanced")
        aiCore.ActiveTeams[2].Config.resourceBoost = true
        
        -- Basic base planning
        local cca = aiCore.ActiveTeams[2]
        cca:PlanDefensivePerimeter(2, 2) -- 2 powers, 2 towers each
    end
end

-- Variables (Encapsulated for Save/Load)
local M = {
    game_start = false,
    reconfactory = false,
    missionwon = false,
    missionfail = false,
    neworders = false,
    basewave = false,
    sent1Done = false,
    sent2Done = false,
    sent3Done = false,
    sent4Done = false,
    shuffle = false,
    notfound = false,
    go = false,
    check1 = false,
    check2 = false,
    check3 = false,
    check4 = false,
    newobjective = false,
    possiblewin = false,
    takeoutfactory = false,
    attacktimeset = false,
    attackstatement = false,
    
    -- Attack Wave sub-states
    aw1sent = false,
    aw2sent = false,
    aw3sent = false,
    aw4sent = false,
    aw1aattack = false,
    aw2aattack = false,
    aw3aattack = false,
    aw4aattack = false,
    aw9aattack = false,
    attackcmd = false,

    -- Timers
    randomwave = 99999999.0,
    readtime = 99999999999.0,
    start = 99999999999999.0,
    platoonhere = 99999999999999.0,
    bombtime = 0,
    aw1t = 99999999999.0,
    aw2t = 99999999999.0,
    aw3t = 99999999999.0,
    aw4t = 99999999999.0,
    
    -- Send Times array for shuffling
    sendTime = {99999999.0, 99999999.0, 99999999.0, 99999999.0},

    -- Handles
    lemnos = nil, player = nil, svrec = nil, avrec = nil,
    wBu1 = nil, wBu2 = nil, wBu3 = nil,
    w1u1 = nil, w1u2 = nil, w1u3 = nil, w1u4 = nil,
    w2u1 = nil, w2u2 = nil, w2u3 = nil, w2u4 = nil,
    w3u1 = nil, w3u2 = nil, w3u3 = nil, w3u4 = nil,
    w4u1 = nil, w4u2 = nil, w4u3 = nil, w4u4 = nil,
    rand1 = nil, rand2 = nil,
    aw1 = nil, aw2 = nil, aw3 = nil, aw4 = nil, aw5 = nil,
    aw1a = nil, aw2a = nil, aw3a = nil, aw4a = nil, aw5a = nil, aw6a = nil, aw7a = nil, aw8a = nil, aw9a = nil,
    cam1 = nil,

    -- Additional Logic Vars
    needtospawn = true,
    reconed = false,
    lemcin1 = false,
    lemcin2 = false,
    lemcinstart = 99999999.0,
    lemcinend = 99999999.0,
    difficulty = 2
}

function ApplyQOL()
    if not exu then return end
    if exu.SetShotConvergence then exu.SetShotConvergence(true) end
    if exu.SetReticleRange then exu.SetReticleRange(600) end
    if exu.SetOrdnanceVelocInheritance then exu.SetOrdnanceVelocInheritance(true) end
    PersistentConfig.Initialize()
end

function Start()
	-- EXU/QOL Setup
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

    -- Spawn Mines
    for i = 1, 23 do
        local pathName = "path_" .. i
        local mine = BuildObject("boltmine", 3, pathName) -- Team 3 = Alien/Hostile
    end
end

function AddObject(h)
    local team = GetTeamNum(h)

    -- EXU Turbo
    if exu and exu.SetUnitTurbo and IsCraft(h) then
        if team == 1 then
            exu.SetUnitTurbo(h, true)
        elseif team ~= 0 then
            if M.difficulty >= 2 then
                exu.SetUnitTurbo(h, 2.5) -- Scaled turbo for enemies
            end
        end
    end
    
    -- AI Core Hook
    if team == 2 then
        local nearBase = false
        if M.svrec and IsAlive(M.svrec) and GetDistance(h, M.svrec) < 400 then
            nearBase = true
        elseif TryGetHandle("cca_base") and GetDistance(h, "cca_base") < 400 then
            nearBase = true
        end
        
        if nearBase then
            aiCore.AddObject(h)
        end
    elseif team == 1 then
        aiCore.AddObject(h)
    end
end

function DeleteObject(h)
end

function Update()
	M.player = GetPlayerHandle()
    if exu and exu.UpdateOrdnance then exu.UpdateOrdnance() end
    aiCore.Update()
    subtit.Update()

    -- Game Start / Initial Setup
    if not M.game_start then
        SetScrap(1, DiffUtils.ScaleRes(40))
        SetScrap(2, DiffUtils.ScaleRes(40))
        SetPilot(1, DiffUtils.ScaleRes(10))
        
        M.lemnos = GetHandle("oblema110_i76building")
        M.svrec = GetHandle("svrecy-1_recycler")
        M.avrec = GetHandle("avrecy-1_recycler")
        
        SetAIP("misn05.aip")
        subtit.Play("misn0501.wav")
        M.game_start = true
        
        M.randomwave = GetTime() + DiffUtils.ScaleTimer(5.0)
        
        M.cam1 = GetHandle("cam1")
        SetLabel(M.cam1, "Volcano")
        M.newobjective = true
    end

    -- Objectives
    if M.newobjective then
        ClearObjectives()
        if M.missionwon then
            AddObjective("misn0502.otf", "green")
        end
        if M.neworders and not M.missionwon then
            AddObjective("misn0502.otf", "white")
        end
        if M.neworders then
            AddObjective("misn0503.otf", "green")
        end
        if M.reconfactory and not M.neworders then
            AddObjective("misn0503.otf", "white")
        end
        if M.reconfactory then
            AddObjective("misn0501.otf", "green")
        else
            AddObjective("misn0501.otf", "white")
        end
        M.newobjective = false
    end

    -- Random Spawns (Start of mission)
    if not M.reconed then
        if M.needtospawn then
            if (M.randomwave < GetTime()) and IsAlive(M.svrec) then
                local type1 = "svfigh"
                if M.difficulty >= 3 then type1 = "svltnk" end

                M.rand1 = BuildObject(type1, 2, M.svrec)
                M.rand2 = BuildObject("svfigh", 2, M.svrec)
                Attack(M.rand1, M.avrec)
                Attack(M.rand2, M.avrec)
                
                for i=1, DiffUtils.ScaleEnemy(1)-1 do
                    local h = BuildObject("svfigh", 2, M.svrec); Attack(h, M.avrec); SetIndependence(h, 1)
                end
                SetIndependence(M.rand1, 1)
                SetIndependence(M.rand2, 1)
                M.needtospawn = false
            end
        else
            if (not IsAlive(M.rand1)) and (not IsAlive(M.rand2)) then
                M.needtospawn = true
                M.randomwave = GetTime() + DiffUtils.ScaleTimer(20.0)
            end
        end
    end

    -- Not Found Warning (Player near factory but hasn't triggered recon yet)
    if (not M.reconfactory) and (GetDistance(M.player, M.lemnos) < 600.0) and (not M.notfound) then
        subtit.Play("misn0502.wav")
        M.notfound = true
    end

    -- Recon Factory Logic
    if (not M.reconfactory) and (GetDistance(M.player, M.lemnos) < 230.0) then
        subtit.Play("misn0503.wav")
        subtit.Play("misn0504.wav")
        M.reconfactory = true
        M.newobjective = true
        M.start = GetTime() + DiffUtils.ScaleTimer(90.0)
        
        -- Cut Cinematic: Recon Factory
        M.lemcinstart = GetTime() - 0.1
        M.lemcinend = GetTime() + 4.0
    end
    
    -- Cinematic Logic
    if (not M.lemcin1) and (M.lemcinstart < GetTime()) and M.reconfactory then
        CameraReady()
        M.lemcin1 = true
    end
    
    if M.lemcin1 and (not M.lemcin2) then
        if M.lemcinend > GetTime() then
             CameraObject(M.player, 0, 5000, -5000, M.lemnos)
        else
             CameraFinish()
             M.lemcin2 = true
        end
        
        if CameraCancelled() then
            CameraFinish()
            M.lemcin2 = true
        end
    end

    -- Shuffle Logic (Triggered by 'notfound' aka getting close to 600m)
    if M.notfound and (not M.shuffle) then
        M.sendTime = {
            GetTime() + DiffUtils.ScaleTimer(10.0),
            GetTime() + DiffUtils.ScaleTimer(90.0),
            GetTime() + DiffUtils.ScaleTimer(130.0),
            GetTime() + DiffUtils.ScaleTimer(190.0)
        }
        
        for i = 1, 10 do
            local j, k = math.random(1, 4), math.random(1, 4)
            M.sendTime[j], M.sendTime[k] = M.sendTime[k], M.sendTime[j]
        end
        M.shuffle = true
    end

    -- Wave 1
    if (M.sendTime[1] < GetTime()) and (not M.sent1Done) then
        local type1 = "svfigh"
        if M.difficulty >= 3 then type1 = "svltnk" end

        M.w1u1 = BuildObject(type1, 2, M.svrec)
        M.w1u2 = BuildObject("svfigh", 2, M.svrec)
        M.w1u3 = BuildObject("svturr", 2, M.svrec)
        M.w1u4 = BuildObject("svturr", 2, M.svrec)
        
        for i=1, DiffUtils.ScaleEnemy(1)-1 do
            local h = BuildObject("svfigh", 2, M.svrec); Attack(h, M.avrec); SetIndependence(h, 1)
        end
        M.sent1Done = true
        
        Follow(M.w1u1, M.w1u3)
        Follow(M.w1u2, M.w1u4)
        SetIndependence(M.w1u1, 1)
        SetIndependence(M.w1u2, 1)
        Goto(M.w1u3, "defendrim2")
        Goto(M.w1u4, "defendrim1")
        
        M.check1 = true
        M.check2 = true
        M.check3 = true
        M.check4 = true
    end

    -- Check Logic (Turrets -> Patrol if dead/arrived)
    if IsAlive(M.w1u3) and (not M.check1) and (GetCurrentCommand(M.w1u3) == 0) then
        Defend(M.w1u3, 1)
    end
    if M.check1 and (not IsAlive(M.w1u3) or GetDistance(M.w1u3, "defendrim2") < 40.0) then
        if IsAlive(M.w1u3) then Stop(M.w1u3, 1) end
        Patrol(M.w1u1, "attackpatrol1", 1)
        M.check1 = false
    end

    if IsAlive(M.w1u4) and (not M.check2) and (GetCurrentCommand(M.w1u4) == 0) then
        Defend(M.w1u4, 1)
    end
    if M.check2 and (not IsAlive(M.w1u4) or GetDistance(M.w1u4, "defendrim1") < 40.0) then
        if IsAlive(M.w1u4) then Stop(M.w1u4, 1) end
        Patrol(M.w1u2, "attackpatrol1", 1)
        M.check2 = false
    end
    
    -- Wave 2 (Tanks + Turrets)
    if (M.sendTime[2] < GetTime()) and (not M.sent2Done) then
        local type2 = "svtank"
        if M.difficulty <= 1 then type2 = "svltnk" end

        M.w2u1 = BuildObject(type2, 2, M.svrec)
        M.w2u2 = BuildObject(type2, 2, M.svrec)
        M.w2u3 = BuildObject("svturr", 2, M.svrec)
        M.w2u4 = BuildObject("svturr", 2, M.svrec)
        
        for i=1, DiffUtils.ScaleEnemy(1)-1 do
            local h = BuildObject(type2, 2, M.svrec); Attack(h, M.avrec); SetIndependence(h, 1)
        end
        M.sent2Done = true
        Follow(M.w2u1, M.w2u3)
        Follow(M.w2u2, M.w2u4)
        SetIndependence(M.w2u1, 1)
        SetIndependence(M.w2u2, 1)
        Goto(M.w2u3, "defendrim3")
        Goto(M.w2u4, "defendrim4")
    end

    if IsAlive(M.w2u3) and (not M.check3) and (GetCurrentCommand(M.w2u3) == 0) then
        Defend(M.w2u3, 1)
    end
    if M.check3 and (not IsAlive(M.w2u3) or GetDistance(M.w2u3, "defendrim3") < 40.0) then
        if IsAlive(M.w2u3) then Stop(M.w2u3, 1) end
        Patrol(M.w2u1, "attackpatrol1", 1)
        M.check3 = false
    end

    if IsAlive(M.w2u4) and (not M.check4) and (GetCurrentCommand(M.w2u4) == 0) then
        Defend(M.w2u4, 1)
    end
    if M.check4 and (not IsAlive(M.w2u4) or GetDistance(M.w2u4, "defendrim4") < 40.0) then
        if IsAlive(M.w2u4) then Stop(M.w2u4, 1) end
        Patrol(M.w2u2, "attackpatrol1", 1)
        M.check4 = false
    end

    -- Wave 3
    if (M.sendTime[3] < GetTime()) and (not M.sent3Done) then
        M.w3u3 = BuildObject("svfigh", 2, M.svrec)
        M.w3u4 = BuildObject("svfigh", 2, M.svrec)
        M.sent3Done = true
        Patrol(M.w3u3, "attackpatrol1", 1)
        Patrol(M.w3u4, "attackpatrol1", 1)
        
        for i=1, DiffUtils.ScaleEnemy(2)-2 do
            local h = BuildObject("svfigh", 2, M.svrec); Patrol(h, "attackpatrol1", 1); SetIndependence(h, 1)
        end
    end

    -- Wave 4
    if (M.sendTime[4] < GetTime()) and (not M.sent4Done) then
        local type4 = "svltnk"
        if M.difficulty >= 3 then type4 = "svtank" end

        M.w4u3 = BuildObject(type4, 2, M.svrec)
        M.w4u4 = BuildObject(type4, 2, M.svrec)
        M.sent4Done = true
        Patrol(M.w4u3, "attackpatrol1", 1)
        Patrol(M.w4u4, "attackpatrol1", 1)
        
        for i=1, DiffUtils.ScaleEnemy(2)-2 do
            local h = BuildObject(type4, 2, M.svrec); Patrol(h, "attackpatrol1", 1); SetIndependence(h, 1)
        end
    end

    -- Post-Recon Logic
    if M.reconfactory and (not M.reconed) then
        if IsInfo("oblema") or (M.start < GetTime()) then
            subtit.Play("misn0515.wav")
            M.readtime = GetTime() + 10.0
            M.reconed = true
        end
    end

    if (not M.neworders) and (M.readtime < GetTime()) then
        M.neworders = true
        subtit.Play("misn0506.wav")
        M.newobjective = true
    end

    -- Base Wave (Spawns after recon)
    if IsAlive(M.svrec) and (not M.basewave) and M.reconfactory then
        M.wBu1 = BuildObject("svtank", 2, M.svrec)
        M.wBu2 = BuildObject("svfigh", 2, M.svrec)
        M.wBu3 = BuildObject("svfigh", 2, M.svrec)
        Attack(M.wBu1, M.avrec)
        Attack(M.wBu2, M.avrec)
        Attack(M.wBu3, M.avrec)
        SetIndependence(M.wBu1, 1)
        SetIndependence(M.wBu2, 1)
        SetIndependence(M.wBu3, 1)
        M.basewave = true
    end

    -- Check if all waves are dead to trigger Final Attack
    if M.sent1Done and M.sent2Done and M.sent3Done and M.sent4Done and 
       (not IsAlive(M.w1u1)) and (not IsAlive(M.w1u2)) and (not IsAlive(M.w1u3)) and (not IsAlive(M.w1u4)) and
       (not IsAlive(M.w2u1)) and (not IsAlive(M.w2u2)) and (not IsAlive(M.w2u3)) and (not IsAlive(M.w2u4)) and
       (not IsAlive(M.w3u1)) and (not IsAlive(M.w3u2)) and (not IsAlive(M.w3u3)) and (not IsAlive(M.w3u4)) and
       (not IsAlive(M.w4u1)) and (not IsAlive(M.w4u2)) and (not IsAlive(M.w4u3)) and (not IsAlive(M.w4u4)) and
       (not M.attacktimeset) then
       
        subtit.Play("misn0507.wav")
        M.platoonhere = GetTime() + DiffUtils.ScaleTimer(45.0)
        M.attacktimeset = true
        M.go = true
    end

    -- Spawn Final Attackers
    if (not IsAlive(M.aw1)) and (not IsAlive(M.aw2)) and (not IsAlive(M.aw3)) and (not IsAlive(M.aw4)) and (not IsAlive(M.aw5)) and
       (M.platoonhere < GetTime()) and M.go and IsAlive(M.svrec) then
       
        subtit.Play("misn0508.wav")
        subtit.Play("misn0509.wav")
        
        local attacksent = math.random(0, 3)
        M.attackstatement = false
        
        M.aw1 = BuildObject("svhraz", 2, M.svrec)
        M.aw2 = BuildObject("svhraz", 2, M.svrec)
        M.aw3 = BuildObject("svhraz", 2, M.svrec)
        
        for i=1, DiffUtils.ScaleEnemy(3)-3 do
            local h = BuildObject("svhraz", 2, M.svrec); SetIndependence(h, 1)
        end
        
        local dest = "destroy1"
        if attacksent == 1 then dest = "destroy2"
        elseif attacksent == 2 then dest = "destroy3"
        elseif attacksent == 3 then dest = "destroy4"
        end
        
        Goto(M.aw1, dest)
        Goto(M.aw2, dest)
        Goto(M.aw3, dest)
        
        if M.difficulty >= 3 then
            M.aw4 = BuildObject("svhraz", 2, M.svrec)
            M.aw5 = BuildObject("svhraz", 2, M.svrec)
            Goto(M.aw4, dest)
            Goto(M.aw5, dest)
        end
        
        M.bombtime = GetTime() + DiffUtils.ScaleTimer(10.0)
        M.attackcmd = false 
        
        M.aw1t = GetTime() + DiffUtils.ScaleTimer(15.0)
        M.aw2t = GetTime() + DiffUtils.ScaleTimer(55.0)
        M.aw3t = GetTime() + DiffUtils.ScaleTimer(110.0)
        M.aw4t = GetTime() + DiffUtils.ScaleTimer(160.0)
    end

    -- Attack Command Switch (Razors switch to attack Factory)
    if (not M.attackcmd) and (M.bombtime < GetTime()) then
        local function CheckAndAttack(u)
             if IsAlive(u) then
                if (GetDistance(u, "dest1") < 60.0) or (GetDistance(u, "dest2") < 60.0) then
                    Attack(u, M.lemnos)
                    SetIndependence(u, 1)
                    return true
                end
             end
             return false
        end

        if CheckAndAttack(M.aw1) or CheckAndAttack(M.aw2) or CheckAndAttack(M.aw3) or CheckAndAttack(M.aw4) or CheckAndAttack(M.aw5) then
            M.attackcmd = true
        end
        M.bombtime = GetTime() + 3.0
    end
    
    -- Platoon Closing In Warning
    if (not M.attackstatement) then
        local function IsThreat(u)
            return IsAlive(u) and (GetDistance(u, M.lemnos) < 500.0)
        end
        
        if IsThreat(M.aw1) or IsThreat(M.aw2) or IsThreat(M.aw3) or IsThreat(M.aw4) or IsThreat(M.aw5) then
            subtit.Play("misn0510.wav")
            M.attackstatement = true
        end
    end

    -- Additional Waves (aw1a...aw9a) triggered by timers
    if (M.aw1t < GetTime()) and (not M.aw1sent) and IsAlive(M.svrec) then
        M.aw2a = BuildObject("svfigh", 2, M.svrec)
        Attack(M.aw2a, M.lemnos)
        SetIndependence(M.aw2a, 1)
        M.aw1sent = true
    end

    if (M.aw2t < GetTime()) and (not M.aw2sent) and IsAlive(M.svrec) then
        M.aw4a = BuildObject("svtank", 2, M.svrec)
        Attack(M.aw4a, M.lemnos)
        SetIndependence(M.aw4a, 1)
        M.aw2sent = true
    end

    if (M.aw3t < GetTime()) and (not M.aw3sent) and IsAlive(M.svrec) then
        M.aw5a = BuildObject("svfigh", 2, M.svrec)
        M.aw6a = BuildObject("svfigh", 2, M.svrec)
        Attack(M.aw5a, M.lemnos)
        Attack(M.aw6a, M.lemnos)
        SetIndependence(M.aw5a, 1)
        SetIndependence(M.aw6a, 1)
        M.aw3sent = true
    end

    if (M.aw4t < GetTime()) and (not M.aw4sent) and IsAlive(M.svrec) then
        M.aw8a = BuildObject("svfigh", 2, M.svrec)
        local type9 = "svtank"
        if M.difficulty >= 3 then type9 = "svhraz" end
        M.aw9a = BuildObject(type9, 2, M.svrec)
        Attack(M.aw8a, M.lemnos)
        Attack(M.aw9a, M.lemnos)
        SetIndependence(M.aw8a, 1)
        SetIndependence(M.aw9a, 1)
        M.aw4sent = true
    end

    -- Force attack factory if near
    local function ForceAttack(u, flag)
        if (not flag) and IsAlive(u) and (GetDistance(u, M.lemnos) < 300.0) then
            Attack(u, M.lemnos)
            SetIndependence(u, 1)
            return true
        end
        return flag
    end
    M.aw1aattack = ForceAttack(M.aw1a, M.aw1aattack)
    M.aw2aattack = ForceAttack(M.aw2a, M.aw2aattack)
    M.aw3aattack = ForceAttack(M.aw3a, M.aw3aattack)
    M.aw4aattack = ForceAttack(M.aw4a, M.aw4aattack)
    M.aw9aattack = ForceAttack(M.aw9a, M.aw9aattack)

    -- Possible Win (Recycler Dead) -> Send everything to factory
    if (not IsAlive(M.svrec)) and (not M.possiblewin) then
        M.possiblewin = true
        subtit.Play("misn0516.wav")
        
        M.aw1aattack = true
        M.aw2aattack = true
        M.aw3aattack = true
        M.aw4aattack = true
        M.aw9aattack = true
        
        M.sent1Done = true
        M.sent2Done = true
        M.sent3Done = true
        M.sent4Done = true
        M.aw1sent = true
        M.aw2sent = true
        M.aw3sent = true
        M.aw4sent = true
        
        local all_units = {
            M.w1u1, M.w1u2, M.w1u3, M.w1u4,
            M.w2u1, M.w2u2, M.w2u3, M.w2u4,
            M.w3u1, M.w3u2, M.w3u3, M.w3u4,
            M.w4u1, M.w4u2, M.w4u3, M.w4u4,
            M.aw1, M.aw2, M.aw3, M.aw4, M.aw5,
            M.aw1a, M.aw2a, M.aw3a, M.aw4a, M.aw5a, M.aw6a, M.aw7a, M.aw8a, M.aw9a
        }
        
        local remaining = false
        for _, u in ipairs(all_units) do
            if IsAlive(u) then
                Attack(u, M.lemnos)
                SetIndependence(u, 1)
                remaining = true
            end
        end
        
        if remaining then
             subtit.Play("misn0517.wav")
        end
        
        M.takeoutfactory = true
    end
    
    -- Win Condition
    if M.sent1Done and M.sent2Done and M.sent3Done and M.sent4Done and M.aw1sent and M.aw2sent and M.aw3sent and M.aw4sent and (not M.missionwon) then
         local all_units = {
            M.w1u1, M.w1u2, M.w1u3, M.w1u4,
            M.w2u1, M.w2u2, M.w2u3, M.w2u4,
            M.w3u1, M.w3u2, M.w3u3, M.w3u4,
            M.w4u1, M.w4u2, M.w4u3, M.w4u4,
            M.aw1, M.aw2, M.aw3, M.aw4, M.aw5,
            M.aw1a, M.aw2a, M.aw3a, M.aw4a, M.aw5a, M.aw6a, M.aw7a, M.aw8a, M.aw9a
        }
        local any_alive = false
        for _, u in ipairs(all_units) do
            if IsAlive(u) then any_alive = true break end
        end
        
        if not any_alive then
            M.missionwon = true
            M.newobjective = true
            subtit.Play("misn0511.wav")
            subtit.Play("misn0512.wav")
            SucceedMission(GetTime() + 15.0, "misn05w1.des")
        end
    end

    -- Fail Conditions
    if (not IsAlive(M.avrec)) and (not M.missionfail) then
        FailMission(GetTime() + 15.0, "misn05l1.des")
        subtit.Play("misn0513.wav")
        M.missionfail = true
    end

    if (not IsAlive(M.lemnos)) and (not M.missionfail) then
        FailMission(GetTime() + 15.0, "misn05l2.des")
        subtit.Play("misn0514.wav")
        M.missionfail = true
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


