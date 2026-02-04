-- Misn05 Mission Script (Converted from Misn05Mission.cpp)

-- Compatibility for 1.5
SetLabel = SetLabel or SettLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
local exu = require("exu")
local aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")

-- Helper for AI
local function SetupAI()
    DiffUtils.SetupTeams(aiCore.Factions.NSDF, aiCore.Factions.CCA, 2)
end

-- Variables
local game_start = false
local reconfactory = false
local missionwon = false
local missionfail = false
local neworders = false
local basewave = false
local sent1Done = false
local sent2Done = false
local sent3Done = false
local sent4Done = false
local shuffle = false
local notfound = false
local go = false
local check1 = false
local check2 = false
local check3 = false
local check4 = false
local newobjective = false
local possiblewin = false
local takeoutfactory = false
local attacktimeset = false
local attackstatement = false

-- Attack Wave sub-states
local aw1sent = false
local aw2sent = false
local aw3sent = false
local aw4sent = false
local aw1aattack = false
local aw2aattack = false
local aw3aattack = false
local aw4aattack = false
local aw9aattack = false -- Only aw9a uses this in C++ source for attack behavior check

-- Timers
local mine_timers = {} -- Not needed for logic, but maybe for reference?
local randomwave = 99999999.0
local readtime = 99999999999.0
local start = 99999999999999.0
local platoonhere = 99999999999999.0
local bombtime = 0
local aw1t = 99999999999.0
local aw2t = 99999999999.0
local aw3t = 99999999999.0
local aw4t = 99999999999.0

-- Send Times array for shuffling
local sendTime = {99999999.0, 99999999.0, 99999999.0, 99999999.0}

-- Handles
local lemnos, player, svrec, avrec
local wBu1, wBu2, wBu3
local w1u1, w1u2, w1u3, w1u4
local w2u1, w2u2, w2u3, w2u4
local w3u1, w3u2, w3u3, w3u4
local w4u1, w4u2, w4u3, w4u4
local rand1, rand2

-- Final Wave Handles
local aw1, aw2, aw3, aw4, aw5
local aw1a, aw2a, aw3a, aw4a, aw5a, aw6a, aw7a, aw8a, aw9a
local cam1

-- Additional Logic Vars
local needtospawn = true
local needtospawn = true
local reconed = false
-- Cinematic vars
local lemcin1 = false
local lemcin2 = false
local lemcinstart = 99999999.0
local lemcinend = 99999999.0
local difficulty = 2

-- Mines
-- In C++: MINE1..MINE23. We will just spawn them and forget them (Team 3).
-- Logic requested: "get rid of the mine logic... set their team to team 3"

function Start()
	-- EXU/QOL Setup
    if exu then
        local ver = (type(exu.GetVersion) == "function" and exu.GetVersion()) or exu.version or "Unknown"
        print("EXU Version: " .. tostring(ver))
        difficulty = (exu.GetDifficulty and exu.GetDifficulty()) or 2
        print("Difficulty: " .. tostring(difficulty))

        if difficulty >= 3 then
            AddObjective("hard_diff", "red", 8.0, "High Difficulty: Enemy presence intensified.")
        elseif difficulty <= 1 then
            AddObjective("easy_diff", "green", 8.0, "Low Difficulty: Enemy presence reduced.")
        end

        if exu.EnableShotConvergence then exu.EnableShotConvergence() end
        if exu.SetSmartCursorRange then exu.SetSmartCursorRange(500) end
        if exu.EnableOrdnanceTweak then exu.EnableOrdnanceTweak(1.0) end
        if exu.SetSelectNone then exu.SetSelectNone(false) end
    end

    SetupAI()

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
            if difficulty > 3 then
                exu.SetUnitTurbo(h, true)
            end
        end
    end
    
    -- AI Core Hook
    if team == 2 then
        local coreUnits = {GetRecyclerHandle(2), GetFactoryHandle(2), GetConstructorHandle(2), GetArmoryHandle(2)}
        local nearBase = false
        for _, prod in ipairs(coreUnits) do
            if IsValid(prod) and GetDistance(h, prod) < 150 then
                nearBase = true
                break
            end
        end
        for _, prod in ipairs(coreUnits) do
            if h == prod then nearBase = true break end
        end
        
        if nearBase then
            aiCore.AddObject(h)
        end
    end
end

function DeleteObject(h)
end

function Update()
	player = GetPlayerHandle()
    if exu and exu.UpdateOrdnance then exu.UpdateOrdnance() end
    aiCore.Update()

    -- Game Start / Initial Setup
    if not game_start then
        SetScrap(1, DiffUtils.ScaleRes(20))
        SetScrap(2, DiffUtils.ScaleRes(20))
        
        lemnos = GetHandle("oblema110_i76building")
        svrec = GetHandle("svrecy-1_recycler")
        avrec = GetHandle("avrecy-1_recycler")
        
        SetAIP("misn05.aip")
        AudioMessage("misn0501.wav")
        game_start = true
        
        randomwave = GetTime() + 1.0
        
        cam1 = GetHandle("cam1")
        SetLabel(cam1, "Volcano")
        newobjective = true
    end

    -- Objectives
    if newobjective then
        ClearObjectives()
        if missionwon then
            AddObjective("misn0502.otf", "green")
        end
        if neworders and not missionwon then
            AddObjective("misn0502.otf", "white")
        end
        if neworders then
            AddObjective("misn0503.otf", "green")
        end
        if reconfactory and not neworders then
            AddObjective("misn0503.otf", "white")
        end
        if reconfactory then
            AddObjective("misn0501.otf", "green")
        else
            AddObjective("misn0501.otf", "white")
        end
        newobjective = false
    end

    -- Random Spawns (Start of mission)
    if not reconed then
        if needtospawn then
            if (randomwave < GetTime()) and IsAlive(svrec) then
                rand1 = BuildObject("svfigh", 2, svrec)
                rand2 = BuildObject("svfigh", 2, svrec)
                Attack(rand1, avrec)
                Attack(rand2, avrec)
                
                for i=1, DiffUtils.ScaleEnemy(1)-1 do
                    local h = BuildObject("svfigh", 2, svrec); Attack(h, avrec); SetIndependence(h, 1)
                end
                SetIndependence(rand1, 1)
                SetIndependence(rand2, 1)
                needtospawn = false
            end
        else
            if (not IsAlive(rand1)) and (not IsAlive(rand2)) then
                needtospawn = true
                -- Reset timer? C++ didn't reset 'randomwave', so it spawns immediately next loop?
                -- C++: checks (randomwave < GetTime()). If we set needtospawn=true, next frame it enters.
                -- To prevent spam, we probably should set a modest delay, but porting strictly:
                -- C++ checks (!IsAlive && !IsAlive) -> needtospawn = true.
                -- Next frame: needtospawn==true -> check (randomwave < GetTime()). randomwave was set at start once.
                -- So yes, it immediately spawns again.
                -- We'll keep it as is.
            end
        end
    end

    -- Not Found Warning (Player near factory but hasn't triggered recon yet)
    if (not reconfactory) and (GetDistance(player, lemnos) < 600.0) and (not notfound) then
        AudioMessage("misn0502.wav")
        notfound = true
    end

    -- Recon Factory Logic
    if (not reconfactory) and (GetDistance(player, lemnos) < 230.0) then
        AudioMessage("misn0503.wav")
        AudioMessage("misn0504.wav")
        reconfactory = true
        newobjective = true
        start = GetTime() + 90.0
        
        -- Cut Cinematic: Recon Factory
        lemcinstart = GetTime() - 1.0 -- Immediate start? C++ had GetTime() - 1.0 logic? Effectively immediate.
        lemcinend = GetTime() + 3.0
    end
    
    -- Cinematic Logic
    if (not lemcin1) and (lemcinstart < GetTime()) and reconfactory then
        CameraReady()
        lemcin1 = true
    end
    
    if lemcin1 and (not lemcin2) then
        if lemcinend > GetTime() then
             CameraObject(player, 0, 5000, -5000, lemnos)
        else
             CameraFinish()
             lemcin2 = true
        end
        
        if CameraCancelled() then
            CameraFinish()
            lemcin2 = true
        end
    end

    -- Shuffle Logic (Triggered by 'notfound' aka getting close to 600m)
    if notfound and (not shuffle) then
        sendTime[1] = GetTime() + DiffUtils.ScaleTimer(10.0)
        sendTime[2] = GetTime() + DiffUtils.ScaleTimer(90.0)
        sendTime[3] = GetTime() + DiffUtils.ScaleTimer(130.0)
        sendTime[4] = GetTime() + DiffUtils.ScaleTimer(190.0)
        
        -- Shuffle logic ported from C++:
        -- for (i=0; i < 10; i++) swap random elements
        for i = 1, 10 do
            local j = math.random(1, 4)
            local k = math.random(1, 4)
            local temp = sendTime[j]
            sendTime[j] = sendTime[k]
            sendTime[k] = temp
        end
        
        shuffle = true
    end

    -- Wave 1
    if (sendTime[1] < GetTime()) and (not sent1Done) then
        w1u1 = BuildObject("svfigh", 2, svrec)
        w1u2 = BuildObject("svfigh", 2, svrec)
        w1u3 = BuildObject("svturr", 2, svrec)
        w1u4 = BuildObject("svturr", 2, svrec)
        
        for i=1, DiffUtils.ScaleEnemy(1)-1 do
            local h = BuildObject("svfigh", 2, svrec); Attack(h, avrec); SetIndependence(h, 1)
        end
        sent1Done = true
        
        Follow(w1u1, w1u3)
        Follow(w1u2, w1u4)
        SetIndependence(w1u1, 1)
        SetIndependence(w1u2, 1)
        Goto(w1u3, "defendrim2")
        Goto(w1u4, "defendrim1")
        
        check1 = true
        check2 = true
        check3 = true
        check4 = true
    end

    -- Check Logic (Turrets -> Patrol if dead/arrived)
    if IsAlive(w1u3) and (not check1) and (GetCurrentCommand(w1u3) == 0) then -- CMD_NONE
        Defend(w1u3, 1000)
    end
    if check1 and (not IsAlive(w1u3) or GetDistance(w1u3, "defendrim2") < 20.0) then
        if IsAlive(w1u3) then Stop(w1u3, 1000) end
        Patrol(w1u1, "attackpatrol1", 2)
        check1 = false
    end

    if IsAlive(w1u4) and (not check2) and (GetCurrentCommand(w1u4) == 0) then
        Defend(w1u4, 1000)
    end
    if check2 and (not IsAlive(w1u4) or GetDistance(w1u4, "defendrim1") < 20.0) then
        if IsAlive(w1u4) then Stop(w1u4, 1000) end
        Patrol(w1u2, "attackpatrol1", 2)
        check2 = false
    end
    
    -- Wave 2 (Tanks + Turrets)
    if (sendTime[2] < GetTime()) and (not sent2Done) then
        w2u1 = BuildObject("svtank", 2, svrec)
        w2u2 = BuildObject("svtank", 2, svrec)
        w2u3 = BuildObject("svturr", 2, svrec)
        w2u4 = BuildObject("svturr", 2, svrec)
        
        for i=1, DiffUtils.ScaleEnemy(1)-1 do
            local h = BuildObject("svtank", 2, svrec); Attack(h, avrec); SetIndependence(h, 1)
        end
        sent2Done = true
        Follow(w2u1, w2u3)
        Follow(w2u2, w2u4)
        SetIndependence(w2u1, 1)
        SetIndependence(w2u2, 1)
        Goto(w2u3, "defendrim3")
        Goto(w2u4, "defendrim4")
    end

    if IsAlive(w2u3) and (not check3) and (GetCurrentCommand(w2u3) == 0) then
        Defend(w2u3, 1000)
    end
    if check3 and (not IsAlive(w2u3) or GetDistance(w2u3, "defendrim3") < 20.0) then
        if IsAlive(w2u3) then Stop(w2u3, 1000) end
        Patrol(w2u1, "attackpatrol1", 2)
        check3 = false
    end

    if IsAlive(w2u4) and (not check4) and (GetCurrentCommand(w2u4) == 0) then
        Defend(w2u4, 1000)
    end
    if check4 and (not IsAlive(w2u4) or GetDistance(w2u4, "defendrim4") < 20.0) then
        if IsAlive(w2u4) then Stop(w2u4, 1000) end
        Patrol(w2u2, "attackpatrol1", 2)
        check4 = false
    end

    -- Wave 3
        w3u3 = BuildObject("svfigh", 2, svrec)
        w3u4 = BuildObject("svfigh", 2, svrec)
        sent3Done = true
        Patrol(w3u3, "attackpatrol1", 2)
        Patrol(w3u4, "attackpatrol1", 2)
        
        for i=1, DiffUtils.ScaleEnemy(2)-2 do
            local h = BuildObject("svfigh", 2, svrec); Patrol(h, "attackpatrol1", 2); SetIndependence(h, 1)
        end

    -- Wave 4
    if (sendTime[4] < GetTime()) and (not sent4Done) then
        w4u3 = BuildObject("svfigh", 2, svrec)
        w4u4 = BuildObject("svfigh", 2, svrec)
        sent4Done = true
        Patrol(w4u3, "attackpatrol1", 2)
        Patrol(w4u4, "attackpatrol1", 2)
        
        for i=1, DiffUtils.ScaleEnemy(2)-2 do
            local h = BuildObject("svfigh", 2, svrec); Patrol(h, "attackpatrol1", 2); SetIndependence(h, 1)
        end
    end

    -- Post-Recon Logic
    if reconfactory and (not reconed) then
        if IsInfo("oblema") or (start < GetTime()) then
            AudioMessage("misn0515.wav") -- Restored cut audio
            readtime = GetTime() + 5.0
            reconed = true
        end
    end

    if (not neworders) and (readtime < GetTime()) then
        neworders = true
        AudioMessage("misn0506.wav")
        newobjective = true
    end

    -- Base Wave (Spawns after recon)
    if IsAlive(svrec) and (not basewave) and reconfactory then
        wBu1 = BuildObject("svtank", 2, svrec)
        wBu2 = BuildObject("svfigh", 2, svrec)
        wBu3 = BuildObject("svfigh", 2, svrec)
        Attack(wBu1, avrec)
        Attack(wBu2, avrec)
        Attack(wBu3, avrec)
        SetIndependence(wBu1, 1)
        SetIndependence(wBu2, 1)
        SetIndependence(wBu3, 1)
        basewave = true
    end

    -- Check if all waves are dead to trigger Final Attack
    if sent1Done and sent2Done and sent3Done and sent4Done and 
       (not IsAlive(w1u1)) and (not IsAlive(w1u2)) and (not IsAlive(w1u3)) and (not IsAlive(w1u4)) and
       (not IsAlive(w2u1)) and (not IsAlive(w2u2)) and (not IsAlive(w2u3)) and (not IsAlive(w2u4)) and
       (not IsAlive(w3u1)) and (not IsAlive(w3u2)) and (not IsAlive(w3u3)) and (not IsAlive(w3u4)) and
       (not IsAlive(w4u1)) and (not IsAlive(w4u2)) and (not IsAlive(w4u3)) and (not IsAlive(w4u4)) and
       (not attacktimeset) then
       
        AudioMessage("misn0507.wav")
        platoonhere = GetTime() + DiffUtils.ScaleTimer(45.0)
        attacktimeset = true
        go = true
    end

    -- Spawn Final Attackers
    if (not IsAlive(aw1)) and (not IsAlive(aw2)) and (not IsAlive(aw3)) and (not IsAlive(aw4)) and (not IsAlive(aw5)) and
       (platoonhere < GetTime()) and go and IsAlive(svrec) then
       
        AudioMessage("misn0508.wav")
        AudioMessage("misn0509.wav")
        
        local attacksent = math.random(0, 3)
        attackstatement = false
        
        -- Spawn Razor/Hraz
        -- Note: Source uses 'aw1', 'aw2', 'aw3'. aw4/aw5 commented out.
        aw1 = BuildObject("svhraz", 2, svrec)
        aw2 = BuildObject("svhraz", 2, svrec)
        aw3 = BuildObject("svhraz", 2, svrec)
        
        for i=1, DiffUtils.ScaleEnemy(3)-3 do
            BuildObject("svhraz", 2, svrec) -- simplified for now
        end
        
        local dest = "destroy1"
        if attacksent == 1 then dest = "destroy2"
        elseif attacksent == 2 then dest = "destroy3"
        elseif attacksent == 3 then dest = "destroy4"
        end
        
        Goto(aw1, dest)
        Goto(aw2, dest)
        Goto(aw3, dest)
        
        if difficulty >= 3 then
            aw4 = BuildObject("svhraz", 2, svrec)
            aw5 = BuildObject("svhraz", 2, svrec)
            Goto(aw4, dest)
            Goto(aw5, dest)
        end
        
        bombtime = GetTime() + DiffUtils.ScaleTimer(10.0)
        -- Note: attackcmd variable used in C++ logic for aw* attack switching, but it's local there inside Execute? 
        -- No, it's a member variable. We need 'attackcmd' state.
        attackcmd = false 
        
        aw1t = GetTime() + DiffUtils.ScaleTimer(10.0)
        aw2t = GetTime() + DiffUtils.ScaleTimer(50.0)
        aw3t = GetTime() + DiffUtils.ScaleTimer(100.0)
        aw4t = GetTime() + DiffUtils.ScaleTimer(140.0)
    end

    -- Attack Command Switch (Razors switch to attack Factory)
    if (attackcmd == false) and (bombtime < GetTime()) and IsAlive(aw1) then -- checking bombtime valid
        local check_dist = false
        local dests = {"dest1", "dest2"} -- Implicitly checked in C++
        
        local function CheckAndAttack(u)
             if IsAlive(u) then
                if (GetDistance(u, "dest1") < 30.0) or (GetDistance(u, "dest2") < 30.0) then
                    Attack(u, lemnos)
                    SetIndependence(u, 1)
                    return true
                end
             end
             return false
        end

        if CheckAndAttack(aw1) or CheckAndAttack(aw2) or CheckAndAttack(aw3) or CheckAndAttack(aw4) or CheckAndAttack(aw5) then
             attackcmd = true
        end
        bombtime = GetTime() + 3.0
    end

    -- Additional Waves (aw1a...aw9a) triggered by timers
    if (aw1t < GetTime()) and (not aw1sent) and IsAlive(svrec) then
        aw2a = BuildObject("svfigh", 2, svrec)
        Attack(aw2a, lemnos)
        SetIndependence(aw2a, 1)
        aw1sent = true
    end

    if (aw2t < GetTime()) and (not aw2sent) and IsAlive(svrec) then
        aw4a = BuildObject("svtank", 2, svrec)
        Attack(aw4a, lemnos)
        SetIndependence(aw4a, 1)
        aw2sent = true
    end

    if (aw3t < GetTime()) and (not aw3sent) and IsAlive(svrec) then
        aw5a = BuildObject("svfigh", 2, svrec)
        aw6a = BuildObject("svfigh", 2, svrec)
        Attack(aw5a, lemnos)
        Attack(aw6a, lemnos)
        SetIndependence(aw5a, 1)
        SetIndependence(aw6a, 1)
        aw3sent = true
    end

    if (aw4t < GetTime()) and (not aw4sent) and IsAlive(svrec) then
        aw8a = BuildObject("svfigh", 2, svrec)
        aw9a = BuildObject("svtank", 2, svrec)
        Attack(aw8a, lemnos)
        Attack(aw9a, lemnos)
        SetIndependence(aw8a, 1)
        SetIndependence(aw9a, 1)
        aw4sent = true
    end

    -- Force attack factory if near
    local function ForceAttack(u, flag)
        if (not flag) and IsAlive(u) and (GetDistance(u, lemnos) < 300.0) then
            Attack(u, lemnos)
            SetIndependence(u, 1)
            return true
        end
        return flag
    end
    -- Note: 'aw1sent' check in C++ wrapper seems redundant if we just check aliveness/timer
    aw1aattack = ForceAttack(aw1a, aw1aattack)
    aw2aattack = ForceAttack(aw2a, aw2aattack)
    aw3aattack = ForceAttack(aw3a, aw3aattack)
    aw4aattack = ForceAttack(aw4a, aw4aattack)
    aw9aattack = ForceAttack(aw9a, aw9aattack)

    -- Possible Win (Recycler Dead) -> Send everything to factory
    if (not IsAlive(svrec)) and (not possiblewin) then
        possiblewin = true
        AudioMessage("misn0516.wav")
        
        -- Force all attack flags to true (stops distance checks)
        aw1aattack = true
        aw2aattack = true
        aw3aattack = true
        aw4aattack = true
        aw9aattack = true
        
        -- Force all wave flags to true so Win Condition can trigger
        sent1Done = true
        sent2Done = true
        sent3Done = true
        sent4Done = true
        aw1sent = true
        aw2sent = true
        aw3sent = true
        aw4sent = true
        
        -- Send everything remaining to attack Factory
        local all_units = {
            w1u1, w1u2, w1u3, w1u4,
            w2u1, w2u2, w2u3, w2u4,
            w3u1, w3u2, w3u3, w3u4,
            w4u1, w4u2, w4u3, w4u4,
            aw1, aw2, aw3, aw4, aw5,
            aw1a, aw2a, aw3a, aw4a, aw5a, aw6a, aw7a, aw8a, aw9a
        }
        
        local remaining = false
        for _, u in ipairs(all_units) do
            if IsAlive(u) then
                Attack(u, lemnos) -- Attack Factory
                SetIndependence(u, 1)
                remaining = true
            end
        end
        
        if remaining then
             AudioMessage("misn0517.wav")
        end
        
        takeoutfactory = true
    end
    
    -- Win Condition
    if aw1sent and aw2sent and aw3sent and aw4sent and sent1Done and sent2Done and sent3Done and sent4Done and (not missionwon) then
        -- Check if EVERYTHING is dead
         local all_units = {
            w1u1, w1u2, w1u3, w1u4,
            w2u1, w2u2, w2u3, w2u4,
            w3u1, w3u2, w3u3, w3u4,
            w4u1, w4u2, w4u3, w4u4,
            aw1, aw2, aw3, aw4, aw5,
            aw1a, aw2a, aw3a, aw4a, aw5a, aw6a, aw7a, aw8a, aw9a
        }
        local any_alive = false
        for _, u in ipairs(all_units) do
            if IsAlive(u) then any_alive = true break end
        end
        
        if not any_alive then
            missionwon = true
            newobjective = true
            AudioMessage("misn0511.wav")
            AudioMessage("misn0512.wav")
            SucceedMission(GetTime() + 15.0, "misn05w1.des")
        end
    end

    -- Fail Conditions
    if (not IsAlive(avrec)) and (not missionfail) then
        FailMission(GetTime() + 15.0, "misn05l1.des")
        AudioMessage("misn0513.wav")
        missionfail = true
    end

    if (not IsAlive(lemnos)) and (not missionfail) then
        FailMission(GetTime() + 15.0, "misn05l2.des")
        AudioMessage("misn0514.wav")
        missionfail = true
    end
end
