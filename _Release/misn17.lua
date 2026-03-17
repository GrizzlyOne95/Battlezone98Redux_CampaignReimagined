-- Misn17 Mission Script (Converted from Misn17Mission.cpp)

-- Compatibility for 1.5
SetLabel = SetLabel or SetLabel

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
local missionstart = false
local missionwon = false
local missionfail = false
local openingcin = false
local camera1, camera2, camera3, camera4, camera5, camera6, camera7 = true, false, false, false, false, false, false
local towersdestroyed = false
local towersdestroyed = false
local minesmade = false
local minesdestroyed = false
local minecin = false
local minecinstart = false
local defenders = false
local newobjective = false
local factorypart1dead = false
local factorypart2dead = false
local factorypart3dead = false
local sf2gone = false
local sf3gone = false
local sf4gone = false

local tower_status = {
    {dead = false, spawned = false}, -- 1
    {dead = false, spawned = false}, -- 2
    {dead = false, spawned = false}, -- 3
    {dead = false, spawned = false}, -- 4
    {dead = false, spawned = false}, -- 5
    {dead = false, spawned = false}, -- 6
    {dead = false, spawned = false}  -- 7
}

-- Timers
local minedistancecheck = 99999.0
local discheck = 99999.0
local waveattacks = 99999.0
local camdone = 99999.0
local spawntime1 = 99999.0
local spawntime2 = 99999.0
local spawntime3 = 99999.0
local spawntime4 = 99999.0
local sf2blow = 99999.0
local sf3blow = 99999.0
local sf4blow = 99999.0

-- Handles
local avrec
local savfactory1, savfactory2, savfactory3, savfactory4
local factorypart1, factorypart2, factorypart3
local factorynav, basenav
local tower_handles = {} -- Array for tower1..7
local mine_handles = {} -- Array for MINE[1..53]
local deftows = {} -- To track defenders if needed
local art1, art2, art3, art4, art5
local desart1, desart2, desart3, desart4, desart5
local cinscrap

local minecount = 0
local difficulty = 2

function Start()
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    
    missionstart = false
end

local function UpdateObjectives()
    ClearObjectives()
    if not towersdestroyed then
        AddObjective("misn1701.otf", "white")
    elseif towersdestroyed and not missionwon then
        AddObjective("misn1701.otf", "green")
        AddObjective("misn1702.otf", "white")
    elseif missionwon then
        AddObjective("misn1701.otf", "green")
        AddObjective("misn1702.otf", "green")
    end
end

function AddObject(h)
    local team = GetTeamNum(h)
    
    if team == 2 then
        aiCore.AddObject(h)
    end
    
    local odf = GetOdf(h); if odf then odf = string.gsub(odf, "%z", "") end
    if odf == "avartl" then
        if not art1 then art1 = h
        elseif not art2 then art2 = h
        elseif not art3 then art3 = h
        elseif not art4 then art4 = h
        elseif not art5 then art5 = h end
    end
    
    -- Unit Turbo based on difficulty
    if exu and exu.SetUnitTurbo and IsCraft(h) then
        if team ~= 0 then
             if difficulty >= 3 then exu.SetUnitTurbo(h, true) end
        end
    end
end

function DeleteObject(h)
end

function Update()
    local player = GetPlayerHandle()
    aiCore.Update()
    
    if not missionstart then
        minedistancecheck = GetTime() + 10.0
        AudioMessage("misn1701.wav")
        
        avrec = GetHandle("avrecy18_recycler")
        savfactory1 = GetHandle("savfactory1")
        savfactory2 = GetHandle("savfactory2")
        savfactory3 = GetHandle("savfactory3")
        savfactory4 = GetHandle("savfactory4")
        
        factorypart1 = GetHandle("factorypart1")
        factorypart2 = GetHandle("factorypart2")
        factorypart3 = GetHandle("factorypart3")
        
        factorynav = GetHandle("factorynav")
        basenav = GetHandle("basenav")
        if factorynav then SetLabel(factorynav, "Furies Factory") end
        if basenav then SetLabel(basenav, "Home Base") end
        
        -- Build Towers
        for i = 1, 7 do
            tower_handles[i] = BuildObject("hbptow", 2, "geizer"..i)
            SetObjectiveOn(tower_handles[i])
            SetLabel(tower_handles[i], "Tower "..i)
        end
        
        UpdateObjectives()
        
        SetScrap(1, DiffUtils.ScaleRes(40))
        SetAIP("misn17.aip")
        
        spawntime1 = GetTime() + DiffUtils.ScaleTimer(10.0)
        spawntime2 = GetTime() + DiffUtils.ScaleTimer(100.0)
        spawntime3 = GetTime() + DiffUtils.ScaleTimer(220.0)
        spawntime4 = GetTime() + DiffUtils.ScaleTimer(340.0)
        
        discheck = GetTime() + DiffUtils.ScaleTimer(30.0)
        
        
        CameraReady()
        CameraPath("cineractive1", 1000, 2000, savfactory1)
        
        missionstart = true
        openingcin = true
    end
    
    -- Intro Cinematic (Restored Multi-Stage Sequence from C++)
    if openingcin then
        if CameraCancelled() then
            CameraFinish()
            openingcin = false
            camera1, camera2, camera3, camera4, camera5, camera6, camera7 = false, false, false, false, false, false, false
        else
            -- Sequence: Factory -> Tow1 -> Tow6 -> Tow3 -> Tow4 -> Tow5 -> Tow7
            if camera1 and CameraPath("cineractive1", 1000, 2000, savfactory1) then
                camera1 = false; camera2 = true
            elseif camera2 and (CameraPath("cineractive2", 500, 2000, tower_handles[1])) then
                camera2 = false; camera3 = true
            elseif camera3 and (CameraPath("cineractive3", 1000, 2000, tower_handles[6])) then
                camera3 = false; camera4 = true
            elseif camera4 and (CameraPath("cineractive5", 1000, 2000, tower_handles[3])) then
                camera4 = false; camera5 = true
            elseif camera5 and (CameraPath("cineractive6", 1000, 2000, tower_handles[4])) then
                camera5 = false; camera6 = true
            elseif camera6 and (CameraPath("cineractive4", 1000, 2000, tower_handles[5])) then
                camera6 = false; camera7 = true
            elseif camera7 and (CameraPath("cineractive7", 1000, 1700, tower_handles[7])) then
                camera7 = false; 
                CameraFinish()
                openingcin = false
            end
        end
    end
    
    -- Artillery Counters
    local arts = { {art1, desart1}, {art2, desart2}, {art3, desart3}, {art4, desart4}, {art5, desart5} }
    -- Lua doesn't support updating local variables via table refs easily without wrapper, 
    -- but we can check handles directly.
    
    if IsAlive(art1) and not IsAlive(desart1) then desart1 = BuildObject("hvsav", 2, "counter"); Attack(desart1, art1) end
    if IsAlive(art2) and not IsAlive(desart2) then desart2 = BuildObject("hvsav", 2, "counter"); Attack(desart2, art2) end
    if IsAlive(art3) and not IsAlive(desart3) then desart3 = BuildObject("hvsav", 2, "counter"); Attack(desart3, art3) end
    if IsAlive(art4) and not IsAlive(desart4) then desart4 = BuildObject("hvsav", 2, "counter"); Attack(desart4, art4) end
    if IsAlive(art5) and not IsAlive(desart5) then desart5 = BuildObject("hvsav", 2, "counter"); Attack(desart5, art5) end
    
    -- Tower Logic
    for i = 1, 7 do
        local tow = tower_handles[i]
        
        -- Defense Spawn
        if IsAlive(tow) and (not tower_status[i].spawned) then
            local enemy = GetNearestEnemy(tow)
            if IsAlive(enemy) and (GetDistance(tow, enemy) < 450.0) then -- 400-450 range
                local d1 = BuildObject("hvsat", 2, tow)
                local d2 = BuildObject("hvsat", 2, tow)
                Defend(d1, tow)
                Defend(d2, tow)
                tower_status[i].spawned = true
            end
        end
        
        -- Death Handler
        if (not IsAlive(tow)) and (not tower_status[i].dead) then
            BuildObject("eggeizr1", 0, "geizer"..i)
            tower_status[i].dead = true
        end
    end
    
    -- Minefield Trigger
    if (not towersdestroyed) and (not openingcin) then
        local all_dead = true
        for i = 1, 7 do if not tower_status[i].dead then all_dead = false; break end end
        
        if all_dead then
            if not minesmade then
                -- Build Mines
                for m = 1, 53 do
                    mine_handles[m] = BuildObject("boltmine2", 2, "mine"..m)
                end
                camera1 = false -- Reset cinematic vars just in case
                minesmade = true
            end
            
            CameraReady()
            towersdestroyed = true
            UpdateObjectives()
            
            minesdestroyed = true -- Start destruction sequence
            minecinstart = true
            minecount = 1
            AudioMessage("misn1730.wav")
        end
    end
    
    -- Minefield Cinematic
    if minecinstart then
        CameraPath("minecin", 1000, 500, savfactory2)
        minecinstart = false -- One shot trigger for camera
    end
    
    if minesdestroyed and minesmade then
        -- Detonate mines sequentially
        if minecount <= 53 then
            if IsAlive(mine_handles[minecount]) then
                Damage(mine_handles[minecount], 10000)
            end
            minecount = minecount + 1
        else
            minesdestroyed = false -- Done
            CameraFinish() -- End Sequence
        end
    end
    
    -- Factory Spawns
    if GetTime() > spawntime1 then BuildObject("hvsat", 2, savfactory1); spawntime1 = GetTime() + DiffUtils.ScaleTimer(400.0) end
    if GetTime() > spawntime2 then BuildObject("hvsav", 2, savfactory2); spawntime2 = GetTime() + DiffUtils.ScaleTimer(400.0) end
    if GetTime() > spawntime3 then BuildObject("hvsat", 2, savfactory3); spawntime3 = GetTime() + DiffUtils.ScaleTimer(400.0) end
    if GetTime() > spawntime4 then BuildObject("hvsat", 2, savfactory4); spawntime4 = GetTime() + DiffUtils.ScaleTimer(400.0) end
    
    -- Defensive Wave
    if (GetTime() > discheck) and (not defenders) then
        local prey = GetNearestEnemy(savfactory1)
        if IsAlive(prey) and (GetDistance(prey, "savspawn") < 450.0) then
            local ip1 = BuildObject("hvsat", 2, savfactory2)
            local ip2 = BuildObject("hvsat", 2, savfactory3)
            local ip3 = BuildObject("hvsav", 2, savfactory4)
            local ip4 = BuildObject("hvsav", 2, savfactory1)
            Defend(ip1, savfactory2)
            Defend(ip2, savfactory3)
            Defend(ip3, savfactory4)
            Defend(ip4, savfactory1)
            defenders = true -- Only once? C++ sets it true and doesn't reset.
        end
        discheck = GetTime() + 5.0
    end
    
    -- Factory Parts Logic
    if (not factorypart1dead) and (not IsAlive(factorypart1)) then BuildObject("eggiezr1", 3, "part1geizer"); factorypart1dead = true end
    if (not factorypart2dead) and (not IsAlive(factorypart2)) then BuildObject("eggiezr1", 3, "part2geizer"); factorypart2dead = true end
    if (not factorypart3dead) and (not IsAlive(factorypart3)) then BuildObject("eggiezr1", 3, "part3geizer"); factorypart3dead = true end
    
    -- Win Condition
    if (not missionwon) and factorypart1dead and factorypart2dead and factorypart3dead then
        AudioMessage("misn1703.wav")
        missionwon = true
        UpdateObjectives()
        SucceedMission(GetTime() + 4.0, "misn17w1.des")
        
        CameraReady()
        cinscrap = BuildObject("eggeizr1", 3, "cinscrap")
        CameraObject(cinscrap, 1000, 8000, 1000, savfactory1)
        
        sf2blow = GetTime() + 1.0
        sf4blow = GetTime() + 2.5
        sf3blow = GetTime() + 3.2
    end
    
    -- Post-Win Cinematic Destruction
    if missionwon then
        if (not sf2gone) and (GetTime() > sf2blow) then Damage(savfactory2, 200000); sf2gone = true end
        if (not sf3gone) and (GetTime() > sf3blow) then Damage(savfactory3, 200000); sf3gone = true end
        if (not sf4gone) and (GetTime() > sf4blow) then Damage(savfactory4, 200000); sf4gone = true end
    end
    
    -- Loss Condition
    if (not missionfail) and (not IsAlive(avrec)) then
        FailMission(GetTime() + 20.0, "misn17l1.des")
        AudioMessage("misn1704.wav")
        missionfail = true
    end
end

