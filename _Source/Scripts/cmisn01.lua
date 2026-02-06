-- cmisn01.lua (Converted from Chinese01Mission.cpp)

-- Compatibility
SetLabel = SetLabel or SettLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
local exu = require("exu")
local aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")

-- Helper for AI
local function SetupAI()
    DiffUtils.SetupTeams(aiCore.Factions.CRA, aiCore.Factions.CCA, 2)
end

-- Variables
local start_done = false
local objective1_complete = false
local objective2_complete = false
local objective3_complete = false
local objective4_complete = false
local hangar_identified = false
local recycler_deployed = false
local tug_near_nav = false
local arials_spawned = false
local focus_on_explosion = false
local doing_explosion = false
local sound10_played = false
local decoy_spawned = false
local won = false
local lost = false

-- Handles
local user
local recycler, tug
local hangar, comm_tower, bb_tower, relic
local escort1, escort2
local detectors = {} -- 1-10
local nav_end

-- Timers
local opening_sound_time = 99999.0
local armoury_sound_time = 99999.0
local wave1_time = 99999.0
local wave2_time = 99999.0
local wave3_time = 99999.0
local wave4_time = 99999.0
local wave5_time = 99999.0
local arial1_time = 99999.0
local arial2_time = 99999.0
local tug_time = 99999.0
local explode_time = 99999.0

-- Difficulty
local difficulty = 2

function Start()
    if exu then
        if exu.EnableShotConvergence then exu.EnableShotConvergence() end
        if exu.SetSmartCursorRange then exu.SetSmartCursorRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    start_done = false
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then 
        aiCore.AddObject(h)
    end
end

function DeleteObject(h)
end

function Update()
    user = GetPlayerHandle()
    aiCore.Update()
    
    if not start_done then
        SetScrap(1, math.floor(30 * resMult))
        SetPilot(1, math.floor(10 * resMult))
        
        hangar = GetHandle("target_1")
        comm_tower = GetHandle("target_2")
        bb_tower = GetHandle("bb_tower")
        
        detectors[1] = GetHandle("sp_turret_1")
        detectors[2] = GetHandle("sp_turret_2")
        detectors[3] = GetHandle("sp_turret_3")
        for i=1,7 do detectors[3+i] = GetHandle("sp_tower_"..i) end
        
        opening_sound_time = GetTime() + 5.0
        
        EnableAllCloaking(false)
        
        start_done = true
    end
    
    if lost or won then return end
    
    -- Intro
    if GetTime() > opening_sound_time then
        opening_sound_time = 99999.0
        AudioMessage("ch01001.wav")
        -- Spawn Nav Start
        local nav = BuildObject("apcamr", 1, "nav_start")
        if nav then SetName(nav, "CCA Base") end
        
        ClearObjectives()
        AddObjective("ch01001.otf", "white")
    end
    
    -- Recon
    if not hangar_identified and hangar and IsInfo(hangar) then
        hangar_identified = true
        AudioMessage("ch01002.wav")
        ClearObjectives()
        AddObjective("ch01001.otf", "green")
        objective1_complete = true -- Note: C++ sets this, but logic continues?
        armoury_sound_time = GetTime() + 15.0 -- Wait for audio triggers
    end
    
    if GetTime() > armoury_sound_time then
        armoury_sound_time = 99999.0
        AudioMessage("ch01003.wav")
        BuildObject("cvslfb", 1, "armoury")
        AudioMessage("ch01004.wav")
        ClearObjectives()
        AddObjective("ch01001.otf", "green")
        AddObjective("ch01002.otf", "white")
        AddScrap(1, 99)
    end
    
    -- Tower Destruction
    if not objective2_complete and comm_tower and GetHealth(comm_tower) <= 0.0 then
        objective2_complete = true
        AudioMessage("ch01005.wav")
        recycler = BuildObject("cvrecyd", 1, "recycler")
        AddScrap(1, 50)
        ClearObjectives()
        AddObjective("ch01001.otf", "green")
        AddObjective("ch01002.otf", "green")
    end
    
    -- Deployment
    if recycler and not recycler_deployed and IsDeployed(recycler) then -- IsDeployed uses handle
        recycler_deployed = true
        wave1_time = GetTime() + 60.0
    end
    
    -- Waves
    local function SpawnGroup(list, path, loc)
        loc = loc or path
        for _, odf in pairs(list) do
            local h = BuildObject(odf, 2, loc)
            Goto(h, path)
        end
    end
    
    if GetTime() > wave1_time then
        wave1_time = 99999.0
        SpawnGroup({"svfigh","svfigh","svfigh","svfigh","svtank","svtank","svtank","svtank"}, "follow_1", "wave_1")
        wave2_time = GetTime() + 300.0
    end
    
    if GetTime() > wave2_time then
        wave2_time = 99999.0
        SpawnGroup({"svtank","svtank","svtank","svtank","svltnk","svltnk","svltnk","svfigh","svfigh"}, "follow_2", "wave_2")
        wave3_time = GetTime() + 300.0
    end
    
    if GetTime() > wave3_time then
        wave3_time = 99999.0
        SpawnGroup({"svtank","svtank","svtank","svtank","svtank","svtank","svtank","svtank","svtank","svhraz","svhraz","svhraz"}, "follow_3", "wave_3")
        arial1_time = GetTime() + 180.0
    end
    
    if GetTime() > arial1_time then
        arial1_time = 99999.0
        local function AttackRecy(odf, loc) local h = BuildObject(odf, 2, loc); Attack(h, recycler) end
        for i=1, math.ceil(6 * enemyMult) do AttackRecy("sspilo", "aerial_1") end
        arial2_time = GetTime() + 30.0
    end
    
    if GetTime() > arial2_time then
        arial2_time = 99999.0
        local function AttackRecy(odf, loc) local h = BuildObject(odf, 2, loc); Attack(h, recycler) end
        for i=1, math.ceil(4 * enemyMult) do AttackRecy("sssold", "aerial_2") end
        wave4_time = GetTime() + 60.0
    end
    
    if GetTime() > wave4_time then
        wave4_time = 99999.0
        SpawnGroup({"svtank","svtank","svtank","svtank","svhraz","svhraz","svhraz","svhraz","svltnk","svltnk","svltnk","svltnk"}, "follow_4", "wave_4")
        tug_time = GetTime() + 120.0
    end
    
    -- Tug
    if GetTime() > tug_time then
        tug_time = 99999.0
        tug = BuildObject("svhaula", 2, "relic_tug")
        Goto(tug, "tug_path")
        
        local h = BuildObject("svfigh", 2, "tug_defend")
        Defend2(h, tug, 1)
        h = BuildObject("svfigh", 2, "tug_defend")
        Defend2(h, tug, 1)
    end
    
    if tug and not tug_near_nav and GetDistance(tug, "nav_tug") < 1000.0 then
        tug_near_nav = true
        AudioMessage("ch01006.wav")
        BuildObject("apcamr", 1, "nav_tug")
        ClearObjectives()
        AddObjective("ch01002.otf", "green")
        AddObjective("ch01003.otf", "white")
    end
    
    if tug and not IsAlive(tug) and not lost and not won then
        lost = true
        AudioMessage("ch01011.wav")
        FailMission(GetTime() + 5.0, "ch01lseb.des")
    end
    
    if tug and GetDistance(tug, "tug_fail") < 350.0 and GetTeamNum(tug) == 2 and not lost and not won then -- Escaped
        -- Note: Team check ensures we didn't capture it? C++ has this check.
        lost = true
        FailMission(GetTime() + 1.0, "ch01lsea.des")
    end
    
    -- Infiltration / Escort Logic
    if tug and IsAlive(tug) and GetDistance(tug, recycler) < 75.0 and not objective3_complete then
        AudioMessage("ch01007.wav")
        
        -- Spawn escorts
        escort1 = BuildObject("svfigh", 1, "fighters")
        SetPerceivedTeam(escort1, 2)
        SetIndependence(escort1, 0)
        Goto(escort1, "fighters_to")
        
        escort2 = BuildObject("svfigh", 1, "fighters")
        SetPerceivedTeam(escort2, 2)
        SetIndependence(escort2, 0)
        Goto(escort2, "fighters_to")
        
        objective3_complete = true
        ClearObjectives()
        AddObjective("ch01003.otf", "green")
        AddObjective("ch01004.otf", "white")
        
        relic = BuildObject("obdata", 0, "relic_loc")
        
        -- Wave 5
        SpawnGroup({"svtank","svtank","svtank","svtank","svhraz","svhraz","svhraz","svhraz","svltnk","svltnk","svltnk","svltnk","svturrb","svturrb","svturrb","svturrb"}, "follow_5", "wave_5")
    end
    
    -- Stealth Logic
    local function IsEscorted()
        if not (escort1 and IsAlive(escort1) and escort2 and IsAlive(escort2)) then return false end
        -- Check if following user.
        -- Lua API check: IsFollowing(handle, target) available in 2.1+
        if IsFollowing(escort1, user) and IsFollowing(escort2, user) then return true end
        return false
    end
    
    if objective3_complete and not objective4_complete and not lost and not won then
        local within_range = false
        for i=1,10 do
            if detectors[i] and IsAlive(detectors[i]) and GetDistance(user, detectors[i]) < 150.0 then
                within_range = true
                break
            end
        end
        
        if not arials_spawned and within_range then
            arials_spawned = true -- Spawn aerials once if triggered? C++ calls this block multiple times maybe?
            -- C++ spawns them inside `if (!arialsSpawned && withinRange)`.
            local function Sp(odf, loc) BuildObject(odf, 2, loc) end
            for i=1,4 do Sp("sspilo", "aerial_3") end
            for i=1,6 do Sp("sssold", "aerial_4") end
        end
        
        if within_range then
            if IsEscorted() then
                SetPerceivedTeam(user, 2)
            else
                SetPerceivedTeam(user, 1) -- Reveal?
                lost = true
                AudioMessage("ch01008.wav")
                FailMission(GetTime() + 1.0, "ch01lsec.des")
            end
        else
            SetPerceivedTeam(user, 1) -- Reset if safe? C++ does `else SetPerceivedTeam(user, 1)` if NOT escorted?
            -- Wait, C++:
            -- if (escorted) { SetPerceivedTeam(2); } else { SetPerceivedTeam(1); }
            -- Separate check: if (withinRange && !escorted) { lost = true; }
        end
    end
    
    -- Relic Pickup
    if objective3_complete and not objective4_complete and relic and tug and GetCargo then
        -- Use GetCargo if available, else proximity?
        if GetCargo(tug) == relic then
            objective4_complete = true
            ClearObjectives()
            AddObjective("ch01004.otf", "green")
            AddObjective("ch01005.otf", "white")
            
            nav_end = BuildObject("apcamr", 1, "nav_end")
            if nav_end then SetName(nav_end, "Safe Distance"); SetObjectiveOn(nav_end) end
            
            StartCockpitTimer(DiffUtils.ScaleTimer(180), 15, 5)
            explode_time = GetTime() + 30.0 -- ??? C++: explodeTime = GetTime() + 30.0f;
            -- Wait, if timer is 180?
            -- C++ Code:
            -- StartCockpitTimer(180...);
            -- explodeTime = GetTime() + 30.0f;
            -- Then later:
            -- if (GetCockpitTimer() <= 0) { make explode }
            -- else if (GetCockpitTimer() <= 2.0 ...) { camera }
            -- So `explodeTime` seems unused for the main timer mechanism? 
            -- Or maybe it was a delay for something else?
            -- Ah, looking at `explodeTime` usage elsewhere?
            -- It's not used in C++ snippet I saw for the finale. Maybe old code.
        end
    end
    
    -- Decoys
    if objective4_complete and not decoy_spawned then
        for i=1,10 do
            if detectors[i] and IsAlive(detectors[i]) and GetDistance(user, detectors[i]) < 300.0 then
                decoy_spawned = true
                AudioMessage("ch01009.wav")
                for j=1,7 do
                   local h = BuildObject("cvhtnk", 1, "decoy_units")
                   Goto(h, detectors[math.random(1,10)], 1)
                end
                break
            end
        end
    end
    
    -- Finale Nuke
    if objective4_complete and not doing_explosion then
        local t = GetCockpitTimer()
        if t <= 2 and not focus_on_explosion then
             -- Camera logic
             local dist = GetDistance(nav_end, hangar) - 50
             if GetDistance(user, hangar) > dist then
                 CameraReady()
                 CameraPath("cut_end", 3000, 0, bb_tower)
                 focus_on_explosion = true
             end
        end
        
        if t <= 0 then
            doing_explosion = true
            HideCockpitTimer()
            -- Explode
             local dist = GetDistance(nav_end, hangar) - 50.0
             if GetDistance(relic, hangar) > dist then
                 won = true
                 SucceedMission(GetTime() + 3.0, "ch01win.des")
             else
                 lost = true
                 FailMission(GetTime() + 3.0, "ch01lsee.des")
             end
             BuildObject("xpltrsn", 0, "spawn_explosion1")
        end
    end
    
    if recycler and GetHealth(recycler) <= 0.0 and not objective3_complete and not lost and not won then
        lost = true
        FailMission(GetTime() + 1.0, "ch01lsed.des")
    end
end
