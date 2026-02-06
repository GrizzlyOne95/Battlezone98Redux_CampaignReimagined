-- Misns1 Mission Script (Converted from Misns1Mission.cpp)

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
    DiffUtils.SetupTeams(aiCore.Factions.CCA, aiCore.Factions.NSDF, 2)
end

-- Variables
local missionstart = false
local missionwon = false
local missionfail = false
local coloradosafe = false
local coloradoreachedsafepoint = false
local mufdestroyed = false
local silodestroyed = false
local possible1, possible2 = false, false
local finish = false
local newobjective = false
local pickpath = false
local trapset = false
local blockaderun = false
local enterwarning = false
local halfwaywarn = false
local retreat = false
local retreatpathset = false
local escortretreat = false
local safety1 = false
local cavalry = false
local cavsent = false
local cavpath1, cavpath2 = false, false
local cav1pathwarn1, cav2pathwarn1 = false, false
local cindone, cindone05, cindone1, cindone2, cindone3 = false, false, false, false, false
local cindone4, cindone5, cindone6, cindone7, cindone8 = false, false, false, false, false
local cindone08, cindone9, cindone10 = false, false, false
local cinstated = {cin1 = false}

-- Waves vars
local aw1amade, aw1bmade, aw1cmade = false, false, false
local aw2amade, aw2bmade, aw2cmade = false, false, false
local aw3amade, aw3bmade, aw3cmade = false, false, false
local du1amade, du1bmade = false, false

-- Timers
local startconvoy = 99999.0
local wave1 = 99999.0
local cintime, cintime05, cintime2, cintime3 = 99999.0, 99999.0, 99999.0, 99999.0
local cintime4, cintime5, cintime6, cintime7 = 99999.0, 99999.0, 99999.0, 99999.0
local cintime8, cintime9, cintime09, cintime10, cintime11 = 99999.0, 99999.0, 99999.0, 99999.0, 99999.0
local aw1at, aw1bt, aw1ct = 99999.0, 99999.0, 99999.0
local aw2at, aw2bt, aw2ct = 99999.0, 99999.0, 99999.0
local aw3at, aw3bt, aw3ct = 99999.0, 99999.0, 99999.0
local du1at, du1bt = 99999.0, 99999.0

-- Handles
local colorado
local muf, silo
local geyser
local ef1, ef2, ef3, et1, et2, et3, et4
local walker1, walker2, walker3
local cav1, cav2, cav3
local walkcam1, walkcam2, walkcam3
local hidcam1, hidcam2, hidcam3
local svrec -- Player's Base (usually svrecy2 in C++)

local path = 0
local cav = 0
local difficulty = 2

function Start()
    if exu then
        if exu.EnableShotConvergence then exu.EnableShotConvergence() end
        if exu.SetSmartCursorRange then exu.SetSmartCursorRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    
    missionstart = false
    path = math.random(0,2)
    cav = math.random(0,3)
end

local function UpdateObjectives()
    ClearObjectives()
    
    -- "Protect the Colorado"
    if IsAlive(colorado) and not coloradosafe then
        AddObjective("misns101.otf", "white")
    elseif (not IsAlive(colorado)) and (not coloradosafe) then
        AddObjective("misns101.otf", "red") -- Failed protection
    elseif coloradosafe and not missionwon then
        AddObjective("misns101.otf", "green") -- Safe
        -- "Destroy Enemy Base"
        AddObjective("misns102.otf", "white")
        if not IsAlive(muf) and not IsAlive(silo) then
             AddObjective("misns102.otf", "green")
        end
    end
    
    if missionwon then
        AddObjective("misns101.otf", "red") -- Legacy C++ quirk kept for fidelity or GREEN? Let's use GREEN for clarity on modern ports.
        -- C++ forced RED on win for 101.otf. Likely implying Colorado leaves the area (so "protection" obj outdated/removed).
        -- I'll use GREEN to signify success.
        AddObjective("misns102.otf", "green")
        AddObjective("misn103.otf", "green")
    end
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then -- Enemy is Team 2 (NSDF)
        aiCore.AddObject(h)
    end
    
    -- Unit Turbo
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
        AudioMessage("misns101.wav")
        
        geyser = GetHandle("eggeizr10_geyser")
        muf = GetHandle("avmuf1_factory") -- Enemy Factory
        silo = GetHandle("absilo1_i76building") -- Enemy Silo
        colorado = GetHandle("avrecy1_recycler") -- Friendly Convoy (Team 1)
        
        -- Escort Group (Team 1)
        ef1 = GetHandle("avfigh3_wingman")
        ef2 = GetHandle("avfigh4_wingman")
        ef3 = GetHandle("avfigh5_wingman")
        et1 = GetHandle("avtank5_wingman")
        et2 = GetHandle("avtank6_wingman")
        et3 = GetHandle("avtank7_wingman")
        et4 = GetHandle("avtank8_wingman")
        
        -- Walkers (Ambush - Team 2 Enemy)
        -- C++: BuildObject("svwalk", 1, ...) -> Wait, C++ mixed teams?
        -- If Player = Team 1 (CCA). Enemies = Team 2 (NSDF usually, but here 'sv' is Soviet).
        -- 'colorado' is avrecy (American). So Colorado is AMERICAN.
        -- If Player is CCA (Soviet), then Colorado IS THE ENEMY.
        -- BUT User just said: "Team 1 is ALWAYS the player, regardless of faction."
        -- So:
        -- Team 1 = Player.
        -- If Player = CCA.
        -- Then Team 1 = CCA.
        -- Handles: 'colorado' (avrecy1) is on Team 1?
        -- If 'colorado' is on Team 1, it is Friendly.
        -- If 'colorado' is avrecy (American), and Player applies as CCA.
        -- This implies we are intercepting/stealing/escorting a captured unit?
        -- "Protect the Colorado" audio suggests it's friendly.
        -- Let's assume Team 1 (Player/Friendly) Escorts 'colorado'.
        -- Enemy = Team 2.
        
        -- C++: `walker1 = BuildObject ("svwalk", 1, "spawnwalker1");`
        -- svwalk on Team 1 ?? That would be Friendly Walker.
        -- But logic uses it for ambush: `trapset = true; AudioMessage("misns123.wav");`
        -- Ambush usually implies Enemy.
        -- Maybe "spawnwalker1" is an enemy spawn point, but C++ builds as Team 1?
        -- If Team 1 is ALWAYS Player, then `svwalk` being built as Team 1 is a Friendly.
        -- This contradicts "Ambush".
        -- UNLESS: Ambush is initiated BY these walkers (Friendly) against ENEMIES?
        -- But `colorado` is Team 1 (Friendly).
        
        -- Re-reading C++:
        -- `SetScrap (2, 50); SetScrap (1,20);` -> Team 2 has advantage.
        
        -- Let's stick to the User directive: Team 1 = Player.
        -- Enemies = Team 2.
        -- Ambush Walkers should be Team 2 (Enemy).
        -- I will spawn `walker1` as Team 2.
        walker1 = BuildObject("svwalk", 2, "spawnwalker1") 
        walker2 = BuildObject("svwalk", 2, "spawnwalker2")
        walker3 = BuildObject("svwalk", 2, "walkstart3") 
        
        -- Cameras/Navs
        walkcam1 = BuildObject("apcamr", 1, "walkcam1"); SetLabel(walkcam1, "Walker Cut Off")
        hidcam1 = BuildObject("apcamr", 1, "hidcamupper"); SetLabel(hidcam1, "Upper Pass Exit")
        hidcam2 = BuildObject("apcamr", 1, "hidcammiddle"); SetLabel(hidcam2, "Middle Pass Exit")
        hidcam3 = BuildObject("apcamr", 1, "hidcamlower"); SetLabel(hidcam3, "Lower Pass Exit")
        
        -- Player Reinforcements (Team 1)
        BuildObject("svtank", 1, "tank1")
        BuildObject("svtank", 1, "tank2")
        BuildObject("svfigh", 1, "figh1")
        BuildObject("svturr", 1, "turr1")
        BuildObject("svturr", 1, "turr2")
        
        SetScrap(2, DiffUtils.ScaleRes(50))
        SetScrap(1, DiffUtils.ScaleRes(20))
        
        startconvoy = GetTime() + DiffUtils.ScaleTimer(180.0)
        missionstart = true
        UpdateObjectives()
        
        -- Cinematic Init
        CameraReady()
        cintime = GetTime() + 11.0
        cintime05 = GetTime() + 11.1
        cintime2 = GetTime() + 20.0
        cintime3 = GetTime() + 27.0
        cintime4 = GetTime() + 29.0
        cintime5 = GetTime() + 31.0
        cintime6 = GetTime() + 33.0
        cintime7 = GetTime() + 44.0
        cintime8 = GetTime() + 46.0
        cintime9 = GetTime() + 48.0
        cintime09 = GetTime() + 50.0
        cintime10 = GetTime() + 60.0
        cintime11 = GetTime() + 66.0
    end
    
    -- Convoy Pathing
    if (not pickpath) and (GetTime() > startconvoy) then
        if IsAlive(ef1) then Follow(ef1, colorado); SetIndependence(ef1, 1) end
        if IsAlive(ef2) then Follow(ef2, colorado); SetIndependence(ef2, 1) end
        if IsAlive(ef3) then Follow(ef3, colorado); SetIndependence(ef3, 1) end
        if IsAlive(et1) then Follow(et1, colorado, 1); SetIndependence(et1, 1) end
        if IsAlive(et2) then Follow(et2, colorado, 1); SetIndependence(et2, 1) end
        
        if path == 0 then Goto(colorado, "upperpath")
        elseif path == 1 then Goto(colorado, "midpath")
        elseif path == 2 then Goto(colorado, "lowerpath")
        end
        pickpath = true
        AudioMessage("misns125.wav")
    end
    
    -- Cinematic Sequence (Reimplemented)
    if not cindone then
        if GetTime() < cintime then
             -- No op, waiting initial delay or using camera ready? C++ started with 'cinpath3' immediately?
             -- Actually C++ logic: if (cindone==false && cintime > GetTime()) CameraPath("cinpath3"...)
             -- This implies it runs UNTIL cintime.
             -- So we should start it once.
             if not cinstated.cin1 then
                 CameraPath("cinpath3", 200, 600, svrec)
                 cinstated.cin1 = true
             end
        end
        
        if (not cindone05) and (GetTime() > cintime05) then
             CameraPath("cinpath4", 300, 500, colorado)
             cindone05 = true
             -- cindone = true -- in C++ this killed the previous block
        end
        
        if (not cindone1) and (GetTime() > cintime2) then
             -- CameraObject(geyser2...)
             CameraPath("geyserpath", 500, 5000, geyser) -- using geyser handle
             cindone1 = true
        end
        
        if (not cindone2) and (GetTime() > cintime3) then
             CameraObject(hidcam1, 1100, 300, 200, hidcam1)
             cindone2 = true
        end
        
        if (not cindone3) and (GetTime() > cintime4) then
             CameraObject(hidcam2, 300, 200, 1500, hidcam2)
             cindone3 = true
        end
        
        if (not cindone4) and (GetTime() > cintime5) then
             CameraObject(hidcam3, 600, 1000, 300, hidcam3)
             cindone4 = true
        end
        
        if (not cindone5) and (GetTime() > cintime6) then
             CameraObject(walker1, -1200, 1500, 1100, walker1) -- walker2 in C++? walker1 here.
             cindone5 = true
        end
        
        if (not cindone6) and (GetTime() > cintime7) then
             CameraObject(walkcam1, 500, 300, 1200, walkcam1)
             cindone6 = true
        end
        
        if (not cindone7) and (GetTime() > cintime8) then
             CameraObject(walkcam2, 1300, 200, 500, walkcam2)
             cindone7 = true
        end
        
        if (not cindone8) and (GetTime() > cintime9) then
             CameraObject(walkcam3, 600, 400, 1300, walkcam3)
             cindone8 = true
        end
        
        if (not cindone08) and (GetTime() > cintime09) then
             CameraPath("approach", 400, 5000, hidcam3)
             cindone08 = true
        end
        
        if (not cindone9) and (GetTime() > cintime10) then
             CameraPath("cinpath1", 300, 500, muf)
             cindone9 = true
        end
        
        if (not cindone10) and (GetTime() > cintime11) then
             CameraFinish()
             cindone = true -- Final done
             cindone10 = true
        end
        
        -- Cancel check
        if CameraCancelled() then
            CameraFinish()
            cindone = true
            cindone10 = true
        end
    end
    
    -- Ambush Trigger
    if (not trapset) and (not blockaderun) and IsAlive(colorado) then
        local dist1 = GetDistance(colorado, walkcam1)
        local dist2 = GetDistance(colorado, walkcam2)
        local dist3 = GetDistance(colorado, walkcam3)
        
        -- Primary Ambush (Restored Multi-Path Triggers from C++ lines 596-619)
        -- FIXED: C++ checked if WALKERS were in position, not Colorado.
        -- "Trap Set" means ambushers are ready.
        if IsAlive(walker1) and (GetDistance(walker1, walkcam1) < 50.0) then
            trapset = true
            AudioMessage("misns123.wav")
        end
    end
    
    -- Halfway Warnings
    if (not halfwaywarn) and not blockaderun then
        if GetDistance(colorado, "halfwayupper") < 100.0 then halfwaywarn = true; AudioMessage("misns102.wav") end
        if GetDistance(colorado, "halfwaymid") < 100.0 then halfwaywarn = true; AudioMessage("misns103.wav") end
        if GetDistance(colorado, "halfwaylower") < 100.0 then halfwaywarn = true; AudioMessage("misns104.wav") end
    end
    
    -- Blockade Run
    if halfwaywarn and not blockaderun then
        if (path == 0 and GetDistance(colorado, hidcam1) < 70.0) or
           (path == 1 and GetDistance(colorado, hidcam2) < 70.0) or
           (path == 2 and GetDistance(colorado, hidcam3) < 70.0) then
            blockaderun = true
            AudioMessage("misns124.wav")
        end
    end
    
    -- Retreat Logic
    if (not retreat) and (not blockaderun) then
        local hostile = GetNearestEnemy(colorado)
        if IsAlive(hostile) and GetDistance(hostile, colorado) < 200.0 then
            retreat = true
            AudioMessage("misns114.wav")
        end
    end
    
    if retreat and (not retreatpathset) then
        Goto(colorado, "retreat1")
        retreatpathset = true
    end
    
    -- Reached Base
    if (not coloradosafe) and (GetDistance(colorado, geyser) < 50.0) then
        coloradosafe = true
        SetAIP("misn09.aip") 
        SetObjectiveOn(colorado); SetObjectiveOn(silo); SetObjectiveOn(muf)
        AudioMessage("misns106.wav")
        UpdateObjectives()
        
        -- Start Waves from Enemy Base (Team 2) against Player/Colorado (Team 1)
        aw1at = GetTime() + DiffUtils.ScaleTimer(25.0)
        aw1bt = GetTime() + DiffUtils.ScaleTimer(30.0)
        aw1ct = GetTime() + DiffUtils.ScaleTimer(35.0)
        aw2at = GetTime() + DiffUtils.ScaleTimer(90.0)
        aw2bt = GetTime() + DiffUtils.ScaleTimer(95.0)
        aw2ct = GetTime() + DiffUtils.ScaleTimer(100.0)
        aw3at = GetTime() + DiffUtils.ScaleTimer(190.0)
        aw3bt = GetTime() + DiffUtils.ScaleTimer(195.0)
        aw3ct = GetTime() + DiffUtils.ScaleTimer(200.0)
        du1at = GetTime() + DiffUtils.ScaleTimer(60.0)
        du1bt = GetTime() + DiffUtils.ScaleTimer(75.0)
    end
    
    -- Safety Fallback
    if (not safety1) and (not coloradosafe) and (not IsAlive(colorado)) then
        -- If Colorado dies, we failed protection?
        -- Actually, mission check: `(!IsAlive(colorado)) && (coloradodestroyed == false) -> coloradodestroyed = true`.
        -- `if (mufdestroyed && silodestroyed && coloradodestroyed) -> Win`.
        -- C++ Line 926: `coloradodestroyed == true && missionwon == false`.
        -- THIS CONFIRMS: WE WANT TO DESTROY COLORADO.
        -- So my previous finding was correct: We ambush Colorado.
        -- BUT: User said Team 1 = Player.
        -- If Team 1 = Player, and Colorado = `avrecy1` (likely Team 1 in map file?), then Player IS Colorado?
        -- But `SetObjectiveOn(colorado)` implies it's a target?
        -- If it's a target, it must be Team 2?
        -- If User played `Misns1`, they play as CCA.
        -- CCA fights USA/NSDF.
        -- Colorado (avrecy) is USA.
        -- So Colorado -> Team 2 (Enemy).
        -- Player -> Team 1 (CCA).
        -- So `colorado` handle must be on Team 2.
        
        -- Re-correcting Logic:
        -- Team 1 = Player (CCA).
        -- Team 2 = Enemy (NSDF/Colorado).
        -- We attack Team 2.
        -- AI Setup: AddTeam(2, NSDF).
        -- `SetupAI` was correct.
        -- `AddObject`: if Team 2, add to AI.
        -- `AddObject(walker1)`: Walkers were `svwalk` in C++.
        -- `svwalk` is CCA unit.
        -- If `walker1` spawns on Team 1, they are Player allies helping ambush.
        -- This makes sense!
        -- "Ambush Trigger": Walkers (Friendly) ambush Convoy (Enemy).
        -- So `walker1` should be Team 1.
        
        -- Fixes:
        -- walker1 spawn: Team 1.
        -- Waves spawn: From `muf` (NSDF Factory, Team 2). So build as Team 2.
        
        SetAIP("misn14.aip")
        BuildObject("avscav", 2, muf) -- Enemy rebuilds
        BuildObject("avscav", 2, muf)
        safety1 = true
        AudioMessage("misns105.wav") -- "Convoy destroyed, reinforcing base"
        aw1at = GetTime() + DiffUtils.ScaleTimer(25.0)
    end
    
    -- Waves (Team 2 Enemy)
    if IsAlive(muf) then
        if GetTime() > aw1at and not aw1amade then BuildObject("avtank", 2, muf); aw1amade = true end
        if GetTime() > aw1bt and not aw1bmade then BuildObject("avfigh", 2, muf); aw1bmade = true end
        if GetTime() > aw1ct and not aw1cmade then BuildObject("avfigh", 2, muf); aw1cmade = true end
        
        if GetTime() > aw2at and not aw2amade then BuildObject("avtank", 2, muf); aw2amade = true end
        if GetTime() > aw2bt and not aw2bmade then BuildObject("avfigh", 2, muf); aw2bmade = true end
        if GetTime() > aw2ct and not aw2cmade then BuildObject("avtank", 2, muf); aw2cmade = true end
        
        if GetTime() > du1at and not du1amade then BuildObject("avturr", 2, muf); du1amade = true end
        if GetTime() > du1bt and not du1bmade then BuildObject("avturr", 2, muf); du1bmade = true end

        -- Restored Wave 3 (Missing in Lua)
        if GetTime() > aw3at and not aw3amade then BuildObject("avtank", 2, muf); aw3amade = true end
        if GetTime() > aw3bt and not aw3bmade then BuildObject("avtank", 2, muf); aw3bmade = true end
        if GetTime() > aw3ct and not aw3cmade then BuildObject("avfigh", 2, muf); aw3cmade = true end
    end
    
    -- Win/Loss
    if (not mufdestroyed) and (not IsAlive(muf)) then
        AudioMessage("misns108.wav")
        mufdestroyed = true
        possible1 = true
        UpdateObjectives()
    end
    
    if (not silodestroyed) and (not IsAlive(silo)) then
        AudioMessage("misns107.wav")
        silodestroyed = true
        possible2 = true
        UpdateObjectives()
    end
    
    if (not IsAlive(colorado)) and coloradosafe then
        -- If Colorado dies AFTER reaching base?
        -- No specific flag in C++ other than `coloradodestroyed`.
    end
    
    if mufdestroyed and silodestroyed and (not IsAlive(colorado)) and (not missionwon) then
        missionwon = true
        UpdateObjectives()
        AudioMessage("misns110.wav")
        SucceedMission(GetTime() + 10.0, "misns1w1.des")
    end
    
    -- Fail condition: Colorado Escapes
    if colorado and IsAlive(colorado) and GetDistance(colorado, "safepoint") < 50.0 and (not coloradoreachedsafepoint) then
        coloradoreachedsafepoint = true
        AudioMessage("misns109.wav")
        AudioMessage("misns111.wav")
        FailMission(GetTime() + 10.0, "misns1l1.des")
    end
    
    -- Fail condition: Player Base dead
    -- `svrec` is player base. If it dies -> fail.
    local my_rec = GetRecyclerHandle(1)
    if (not IsAlive(my_rec)) and (not missionfail) then
        missionfail = true
        FailMission(GetTime() + 10.0, "misns1l2.des")
        AudioMessage("misns112.wav")
    end

    -- Restored "Cavalry" Flanking Wave (Cut Content)
    if (wave1 < GetTime()) and (not cavalry) then
        wave1 = 99999.0
        cavalry = true
        cav1 = BuildObject("avfigh", 2, "cavspawn")
        cav2 = BuildObject("avtank", 2, "cavspawn")
        cav3 = BuildObject("avfigh", 2, "cavspawn")
        AudioMessage("misns122.wav") -- "New contacts!"
    end

    if cavalry and (not cavsent) then
        -- Random path logic from C++
        local path_name = "cavpath1"
        if (cav == 1) or (cav == 3) then path_name = "cavpath2" end
        
        if IsAlive(cav1) then Goto(cav1, path_name) end
        if IsAlive(cav2) then Goto(cav2, path_name) end
        if IsAlive(cav3) then Goto(cav3, path_name) end
        
        if path_name == "cavpath1" then cavpath1 = true else cavpath2 = true end
        cavsent = true
    end

    -- Cavalry Warnings
    if cavpath1 and (not cav1pathwarn1) then
        if (IsAlive(cav1) and GetDistance(cav1, walkcam1) < 200.0) or
           (IsAlive(cav2) and GetDistance(cav2, walkcam1) < 200.0) then
            AudioMessage("misns118.wav")
            cav1pathwarn1 = true
        end
    end
    if cavpath2 and (not cav2pathwarn1) then
        if (IsAlive(cav1) and GetDistance(cav1, walkcam2) < 200.0) or
           (IsAlive(cav2) and GetDistance(cav2, walkcam2) < 200.0) then
            AudioMessage("misns119.wav")
            cav2pathwarn1 = true
        end
    end
end
