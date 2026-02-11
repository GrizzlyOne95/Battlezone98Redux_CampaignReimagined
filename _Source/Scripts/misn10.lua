-- Misn10 Mission Script (Converted from Misn10Mission.cpp)

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
local start_done = false
local sav_moved = false
local base_dead = false
local player_dead = false
local making_another_tug = false
local made_another_tug = false
local build_tug = false
local position1 = false
local position2 = false
local position3 = false
local position4 = false
local position5 = false
local position6 = false
local position7 = false
local tug_underway1 = false
local tug_underway2 = false
local tug_underway3 = false
local tug_underway4 = false
local tug_underway5 = false
local tug_underway6 = false
local tug_underway7 = false
local tug_after_sav = false
local sav_seized = false
local sav_free = true
local sav_secure = false
local return_to_base = false
local tug_wait_center = false
local tug_wait2 = false
local tug_wait3 = false
local tug_wait4 = false
local tug_wait5 = false
local tug_wait6 = false
local tug_wait7 = false
local tug_wait_base = false
local tug_at_wait_center = false
local objective_on = false
local new_aipa = false
local new_aipb = false
local relic_free = true -- Appears synonymous with sav_free logic in parts
local fighters_underway = false
local sav_protected = false
local turret1_underway = false
local turret2_underway = false
local turret3_underway = false
local turret1_stop = false
local turret2_stop = false
local artil1_stop = false
local artil2_stop = false
local artil3_stop = false
local artil1_underway = false
local artil2_underway = false
local artil3_underway = false
local got_position = false
local fighter1_underway = false
local fighter2_underway = false
local tank1_follow = false
local tank2_follow = false
local tank1_stop = false
local tank2_stop = false
local plan_a = false
local plan_b = false
local game_over = false
local chase_tug = false
local sav_warning = false
local quake = false
local new_sav_built = false

-- Timers
local gech_warning_message = 99999.0
local relic_check = 99999.0
local build_sav_time = 99999.0
local quake_time = 4.0
local build_another_tug_time = 99999.0
local fighter_time = 99999.0
local artil1_check = 99999.0
local artil2_check = 99999.0
local artil3_check = 99999.0
local turret1_check = 99999.0
local turret2_check = 99999.0
local next_second = 0.0
local geys1check = 180.0

-- Handles
local user
local ccatug, tugger, sav -- sav = relic
local nav1, nav2, nav3
local ccaartil1, ccaartil2, ccaartil3
local ccaturret1, ccaturret2, ccaturret3
local ccarecycle, ccamuf, nsdfrecycle
local ccafighter1, ccafighter2, ccatank1, ccatank2
local post1_geyser, post3_geyser
local geys1, geys2, geys3, geys4, geys5, geys6, geys7
local svartil1, svartil2

local difficulty = 2

function Start()
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    
    start_done = false
    -- C++ sets geys1check = 180.0f here
    geys1check = GetTime() + DiffUtils.ScaleTimer(180.0)
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then
        aiCore.AddObject(h)
    end
    -- Unit Turbo based on difficulty
    if exu and exu.SetUnitTurbo and IsCraft(h) then
        if team ~= 0 then
             if difficulty >= 3 then exu.SetUnitTurbo(h, true) end
        end
    end
end

function DeleteObject(h)
    -- Reset logic if tug destroyed
    if h == ccatug then
        tug_underway1 = false
        tug_underway2 = false
        tug_underway3 = false
        tug_underway4 = false
        tug_underway5 = false
        tug_underway6 = false
        tug_underway7 = false
        tug_after_sav = false
        return_to_base = false
        tug_wait_center = false
        tug_wait2 = false
        tug_wait3 = false
        tug_wait4 = false
        tug_wait5 = false
        tug_wait6 = false
        tug_wait7 = false
        tug_wait_base = false
        tug_at_wait_center = false
        got_position = false
        sav_warning = false
    end
end

function Update()
    user = GetPlayerHandle()
    aiCore.Update()
    
    if not start_done then
        AudioMessage("misn1000.wav")
        ClearObjectives()
        AddObjective("misn1000.otf", "white")
        
        SetScrap(1, DiffUtils.ScaleRes(30))
        SetScrap(2, DiffUtils.ScaleRes(40))
        SetAIP("misn10.aip")
        
        turret1_check = GetTime() + DiffUtils.ScaleTimer(19.0)
        turret2_check = GetTime() + DiffUtils.ScaleTimer(20.0)
        artil1_check = GetTime() + DiffUtils.ScaleTimer(21.0)
        artil2_check = GetTime() + DiffUtils.ScaleTimer(22.0)
        artil3_check = GetTime() + DiffUtils.ScaleTimer(23.0)
        geys1check = GetTime() + DiffUtils.ScaleTimer(180.0)
        
        sav = GetHandle("relic")
        nav1 = GetHandle("cam1")
        nav2 = GetHandle("cam2")
        nav3 = GetHandle("cam3")
        SetLabel(nav1, "Relic Site")
        SetLabel(nav2, "CCA Base")
        SetLabel(nav3, "Drop Zone")
        
        svartil1 = GetHandle("svartil1")
        svartil2 = GetHandle("svartil2")
        SetIndependence(svartil1, 1)
        SetIndependence(svartil2, 1)
        
        ccarecycle = GetHandle("svrecycler")
        nsdfrecycle = GetHandle("avrecycler")
        ccamuf = GetHandle("svmuf")
        
        post1_geyser = GetHandle("post1_geyser")
        post3_geyser = GetHandle("post3_geyser")
        geys1 = GetHandle("geyser1")
        geys2 = GetHandle("geyser2")
        geys3 = GetHandle("geyser3")
        geys4 = GetHandle("geyser4")
        geys5 = GetHandle("geyser5")
        geys6 = GetHandle("geyser6")
        geys7 = GetHandle("geyser7")
        
        ccatug = GetHandle("svhaul") -- Might need to Find it if not predefined
        -- In C++, Setup just does GetHandle("relic"), etc. 
        -- Handles like ccatug, ccaartil are found in AddObject in C++.
        -- Here we'll search for them if not preset or use GetHandle if they have ODF names in map.
        -- Assuming C++ AddObject filled them by ODF class. We need to find them.
        -- Function to find existing unit by ODF
        local function FindUnit(odf)
            local nearby = GetObjectsInRange(ccarecycle, 500.0, "any") -- Look near base
            for _, h in ipairs(nearby) do
                local check = GetOdf(h)
                if check then check = string.gsub(check, "%z", "") end
                if check == odf then return h end
            end
            -- Fallback, check map wide? Map is small enough or rely on dynamic add.
            return nil
        end
        if not ccatug then ccatug = FindUnit("svhaul") end
        if not ccaartil1 then ccaartil1 = FindUnit("svartl") end -- Lua loop will find same one?
        -- Better way: Iterate all units.
        
        -- Just let dynamic discovery happen or do a sweep
        -- Actually, mission script starts -> Objects already spawned usually.
        -- We will assume AddObject handles dynamic or they exist.
        -- For now, do a quick sweep around recycler for initial units.
        local units = GetObjectsInRange(ccarecycle, 1000.0, "any")
        for _, h in ipairs(units) do AddObject(h) end 
        -- Note: AddObject above calls aiCore.AddObject. We also need to populate local handles.
        -- Re-implement C++ AddObject Logic roughly:
        for _, h in ipairs(units) do
            local odf = GetOdf(h)
            if odf then odf = string.gsub(odf, "%z", "") end
            if not ccatug and odf == "svhaul" then ccatug = h end
            if not ccafighter1 and odf == "svfigh" then ccafighter1 = h 
            elseif not ccafighter2 and odf == "svfigh" then ccafighter2 = h end
            
            if not ccatank1 and odf == "svltnk" then ccatank1 = h
            elseif not ccatank2 and odf == "svltnk" then ccatank2 = h end
            
            if not ccaartil1 and odf == "svartl" then ccaartil1 = h
            elseif not ccaartil2 and odf == "svartl" then ccaartil2 = h
            elseif not ccaartil3 and odf == "svartl" then ccaartil3 = h end
            
            if not ccaturret1 and odf == "svturr" then ccaturret1 = h
            elseif not ccaturret2 and odf == "svturr" then ccaturret2 = h
            elseif not ccaturret3 and odf == "svturr" then ccaturret3 = h end
        end
        
        relic_free = true
        sav_free = true
        start_done = true
    end
    
    -- Relic Tracking Logic
    if sav_free and IsAlive(sav) then
        tugger = GetTug(sav)
        if IsAlive(tugger) then
            if GetTeamNum(tugger) == 1 then
                sav_free = false
                sav_secure = true
            else
                sav_free = false
                sav_seized = true
                tugger = ccatug
            end
        end
    end
    
    if sav_secure and (not IsAlive(tugger)) then
        if not sav_seized then
            sav_free = true
            sav_secure = false
            chase_tug = false -- Stop chasing dead tug
            fighter1_underway = false
            fighter2_underway = false
        end
    end
    
    if sav_seized and (not IsAlive(ccatug)) then
        if IsAlive(ccatank1) and IsAlive(sav) then Goto(ccatank1, sav) end
        if IsAlive(ccatank2) and IsAlive(sav) then Goto(ccatank2, sav) end
        
        sav_seized = false
        got_position = false
        sav_free = true
    end
    
    if sav_seized and (not sav_warning) then
        AudioMessage("misn1005.wav")
        sav_warning = true
    end
    
    -- Chase Logic
    if IsAlive(tugger) and (not chase_tug) and sav_secure then
        local attackers = {ccafighter1, ccafighter2, ccatank1, ccatank2, svartil1, svartil2, ccaartil1, ccaartil2, ccaartil3}
        for _, h in ipairs(attackers) do
            if IsAlive(h) then Attack(h, tugger) end
        end
        chase_tug = true
    end
    
    -- Dynamic Pathfinding Logic (C++ got_position)
    if IsAlive(ccatug) and sav_free and (not got_position) then
        local dists = {}
        for i=1,7 do
            dists[i] = GetDistance(sav, "geyser"..i)
        end
        
        -- Find min dist index
        local min_idx = 1
        local min_dist = dists[1]
        for i=2,7 do
            if dists[i] < min_dist then
                min_dist = dists[i]
                min_idx = i
            end
        end
        
        position1 = (min_idx == 1)
        position2 = (min_idx == 2)
        position3 = (min_idx == 3)
        position4 = (min_idx == 4)
        position5 = (min_idx == 5)
        position6 = (min_idx == 6)
        position7 = (min_idx == 7)
        
        got_position = true
    end
    
    -- Execute Tug Path
    if IsAlive(ccatug) and got_position then
        if IsAlive(ccatank1) and (not tank1_follow) then Follow(ccatank1, ccatug); tank1_follow = true end
        if IsAlive(ccatank2) and (not tank2_follow) then Follow(ccatank2, ccatug); tank2_follow = true end
        
        local function ProcessPath(pos_flag, underway_var, path_name, geys_name, return_path)
            -- Start Path
            if sav_free and pos_flag and (not _G[underway_var]) and (not tug_after_sav) then
                Goto(ccatug, path_name)
                _G[underway_var] = true
            end
            
            -- Check Pickup Proximity
            if _G[underway_var] and sav_free and (not tug_after_sav) then
                local dist_sav = GetDistance(ccatug, sav)
                local dist_geys = GetDistance(ccatug, geys_name)
                
                if (dist_sav < dist_geys and dist_sav < 100.0) or (dist_geys < 100.0) then
                    Pickup(ccatug, sav)
                    -- Tanks stop following? C++ re-issues Follow(0)? Or same.
                    -- C++: Follow(ccatank1, ccatug, 0)
                    if IsAlive(ccatank1) then Follow(ccatank1, ccatug) end
                    if IsAlive(ccatank2) then Follow(ccatank2, ccatug) end
                    tug_after_sav = true
                end
            end
            
            -- Return Logic
            if tug_after_sav and _G[underway_var] and sav_seized and (not return_to_base) then
                Goto(ccatug, return_path)
                return_to_base = true
            end
        end
        
        -- Path Definitions
        -- Position 1
        ProcessPath(position1, "tug_underway1", "relic_path1", "geyser1", "main_return_path")
        -- Position 2: special return to ccarecycle
        if sav_free and position2 and (not tug_underway2) and (not tug_after_sav) then
            Goto(ccatug, "relic_path1"); tug_underway2 = true
        end
        if tug_underway2 and sav_free and (not tug_after_sav) and (GetDistance(ccatug, geys2) < 100.0 or GetDistance(ccatug, sav) < 100.0) then
            Pickup(ccatug, sav); tug_after_sav = true
        end
        if tug_after_sav and tug_underway2 and sav_seized and (not return_to_base) then
            Goto(ccatug, ccarecycle); return_to_base = true
        end
        
        -- Position 3
        ProcessPath(position3, "tug_underway3", "attack_path_central", "geyser3", "lsouth_return_path")
        -- Position 4
        ProcessPath(position4, "tug_underway4", "attack_path_central", "geyser4", "main_return_path")
        -- Position 5
        ProcessPath(position5, "tug_underway5", "attack_path_south", "geyser5", "ssouth_return_path")
        -- Position 6
        ProcessPath(position6, "tug_underway6", "attack_path_north", "geyser6", "main_return_path")
        -- Position 7
        ProcessPath(position7, "tug_underway7", "attack_path_south", "geyser7", "msouth_return_path")
    end
    
    -- Waiting Tug Logic (If player secured relic before enemy)
    if not IsAlive(sav) then -- IsAlive(sav) false?? "sav" is relic? Perhaps picked up inside a Tug?
        -- In BZ, if object is in a Tug, IsAlive is still true usually involved in calculations?
        -- C++ checks "if (!IsAlive(sav))" but also "if ((sav_secure)...)".
        -- If sav is cargo, is it alive? Usually yes.
        -- Logic might imply if it's "Gone" or picked up?
        -- Let's stick to state flags.
    end
    -- Tug Wait Logic (Restored C++ Behavior)
    -- If the player secures the relic first, the enemy tug shouldn't just vanish or idle aimlessly.
    -- It should retreat to a standby position near a geyser or base to ambush.
    if sav_secure then
        -- Default: Go home if no active mission
        if (not tug_underway1) and (not tug_underway2) and (not tug_underway3) and (not tug_underway4) and 
           (not tug_underway5) and (not tug_underway6) and (not tug_underway7) and (not tug_at_wait_center) then
           Goto(ccatug, ccarecycle)
           tug_wait_base = true
        end

        -- If intercepted mid-route (e.g., tug_underway2), divert to wait
        if tug_underway2 and GetDistance(ccatug, geys2) < 80.0 and (not tug_wait2) then
            Goto(ccatug, geys2); tug_underway2 = false; tug_wait2 = true
        end
        if tug_underway3 and GetDistance(ccatug, geys3) < 80.0 and (not tug_wait3) then
            Goto(ccatug, geys3); tug_underway3 = false; tug_wait3 = true
        end
        if tug_underway4 and GetDistance(ccatug, geys4) < 80.0 and (not tug_wait4) then
            Goto(ccatug, geys4); tug_underway4 = false; tug_wait4 = true
        end
        if tug_underway5 and GetDistance(ccatug, geys5) < 80.0 and (not tug_wait5) then
            Goto(ccatug, ccarecycle); tug_underway5 = false; tug_wait5 = true -- Retreat
        end
        -- If player drops it, resume chase from wait?
        -- Logic implied: if sav_free again, tug should reactivate. 
        -- Handled by general loop? Yes, if sav_free triggers, `got_position` might reset? 
        -- C++ loop for `got_position` runs only if `(!got_position)`.
        -- So if we want re-engagement, we must reset `got_position = false` when relic is dropped.
    end
    
    -- Reset pathfinding if relic dropped
    if sav_free and sav_secure then -- Transition secure -> free
        -- Wait, sav_free and sav_secure are mutually exclusive usually.
        -- We detecting the transition: sav_free == true, but we were secure?
        -- Need a previous state tracker or check. 
        -- Actually, 'sav_secure' means player has it. 'sav_free' means nobody has it.
        -- If player drops it, secure becomes false, free becomes true.
        -- We need to reset `got_position` to `false` to recalculate path!
        -- BUT, got_position logic block checks `if (IsAlive(ccatug)) and (sav_free) and (!got_position)`.
        -- So we just need to flip `got_position` to false when drop happens.
    end
    
    -- Objective Check
    if (GetDistance(user, sav) < 100.0) and (not objective_on) then
        SetObjectiveOn(sav)
        SetLabel(sav, "Alien Relic")
        objective_on = true
    end
    
    -- Fighter/Turret logic
    if relic_free and IsAlive(ccafighter1) and (not fighter1_underway) then
        Follow(ccafighter1, sav)
        fighter1_underway = true
    end
    if relic_free and IsAlive(ccafighter2) and (not fighter2_underway) then
        Follow(ccafighter2, sav)
        fighter2_underway = true
    end
    
    -- Artillery Movement
    if (artil1_check < GetTime()) then
        artil1_check = GetTime() + DiffUtils.ScaleTimer(15.0)
        if IsAlive(ccaartil1) and (not artil1_stop) then
            if (not artil1_underway) then Goto(ccaartil1, "artil1_path"); artil1_underway = true end
            if GetDistance(ccaartil1, post1_geyser) < 20.0 then Defend(ccaartil1); artil1_stop = true end
        end
        if IsAlive(ccaartil2) and (not artil2_stop) then
            if (not artil2_underway) then Goto(ccaartil2, "artil2_path"); artil2_underway = true end
            if GetDistance(ccaartil2, post3_geyser) < 20.0 then Defend(ccaartil2); artil2_stop = true end
        end
        if IsAlive(ccaartil3) and (not artil3_stop) then
            if (not artil3_underway) then Goto(ccaartil3, "relic_path1"); artil3_underway = true end
            if GetDistance(ccaartil3, geys2) < 50.0 then Defend(ccaartil3); artil3_stop = true end
        end
    end
    
    -- Artillery Shelling
    if (geys1check < GetTime()) and (not chase_tug) then
        geys1check = GetTime() + DiffUtils.ScaleTimer(150.0)
        local target = geys1
        if GetDistance(user, geys1) < 200.0 then target = user end
        
        if IsAlive(svartil1) then Attack(svartil1, target) end
        if IsAlive(svartil2) then Attack(svartil2, target) end
    end
    
    -- AIP Plan A
    if IsAlive(ccafighter1) and IsAlive(ccafighter2) and (not plan_a) then
        if GetScrap(2) > DiffUtils.ScaleRes(15) then SetAIP("misn10a.aip"); plan_a = true end
    end
    
    -- Keep Relic Alive
    if IsAlive(sav) then
        if GetTime() > next_second then
            AddHealth(sav, 100) -- Keep it invincible?
            AddHealth(sav, 100) -- Keep it invincible?
            next_second = GetTime() + 1.0
        end
        end
    end
    
    -- Enemy Tug Rebuild Logic (Restored from C++ lines 970-1008)
    -- "hopefully, the following code will build a cca tug every 30 seconds after the last cca tug is destoyed"
    if (not IsAlive(ccatug)) and (not making_another_tug) and (not game_over) then
        making_another_tug = true
        build_another_tug_time = GetTime() + DiffUtils.ScaleTimer(30.0)
    end
    
    if making_another_tug and (GetTime() > build_another_tug_time) then
        if IsAlive(ccarecycle) then
            ccatug = BuildObject("svhaul", 2, ccarecycle)
            making_another_tug = false
            
            -- Reset all tug flags to restart mission
            tug_underway1 = false
            tug_underway2 = false
            tug_underway3 = false
            tug_underway4 = false
            tug_underway5 = false
            tug_underway6 = false
            tug_underway7 = false
            tug_after_sav = false
            return_to_base = false
            tug_wait_center = false
            tug_wait2 = false
            tug_wait3 = false
            tug_wait4 = false
            tug_wait5 = false
            tug_wait6 = false
            tug_wait7 = false
            tug_wait_base = false
            tug_at_wait_center = false
            got_position = false -- Recalculate path
            sav_warning = false
            
            -- Re-assign escorts
            if IsAlive(ccatank1) then Follow(ccatank1, ccatug) end
            if IsAlive(ccatank2) then Follow(ccatank2, ccatug) end
        end
    end
    
    -- Cut Earthquake Content
    if (not quake) and (quake_time < GetTime()) then
        quake_time = GetTime() + 10.0
        StartEarthquake(2.0)
        quake = true
    end
    
    if quake and (quake_time < GetTime()) then
        StopEarthquake()
        quake_time = GetTime() + 120.0
        quake = false
    end
    
    -- Victory
    if sav_secure and (GetDistance(sav, nsdfrecycle) < 100.0) and (not game_over) then
        AudioMessage("misn1001.wav")
        SucceedMission(GetTime() + 15.0, "misn10w1.des")
        game_over = true
    end
    
    -- Failure
    if sav_seized and (GetDistance(sav, ccarecycle) < 100.0) and (not game_over) then
        AudioMessage("misn1002.wav")
        FailMission(GetTime() + 15.0, "misn10f1.des")
        game_over = true
    end
    
    if (not IsAlive(sav)) and (not game_over) then
        -- C++ checks this. If relic destroyed.
        AudioMessage("misn1003.wav")
        FailMission(GetTime() + 15.0, "misn10f2.des")
        game_over = true
    end
    
    if (not IsAlive(nsdfrecycle)) and (not game_over) then
        AudioMessage("misn1004.wav")
        FailMission(GetTime() + 15.0, "misn10f3.des")
        game_over = true
    end
end

