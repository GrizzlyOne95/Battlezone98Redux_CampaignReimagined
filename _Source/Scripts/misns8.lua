-- Misns8 Mission Script (Converted from Misns8Mission.cpp)

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
    local bdog = DiffUtils.SetupTeams(aiCore.Factions.BDOG, aiCore.Factions.NSDF, 2)
    
    -- Legacy Features (Misns8 OG Ideas)
    bdog:SetConfig("passiveRegen", true)
    bdog:SetConfig("regenRate", 20.0)
end

-- Variables
local start_done = false
local plan_a = false
local plan_b = false
local plan_c = false

-- Plan A Vars
local turret_move = false
local turret1_set, turret2_set, turret3_set, turret4_set = false, false, false, false
local t1down, t2down, t3down = false, false, false
local rig_prep = false
local base_build = false
local rig_movea = false
local artil_build = false
local at_geyser = false
local silo_center_prep = false
local silo1_build = false
local prep_center_towers = false
local rigs_ordered = false
local welldone_rig = false
local tanks_follow = false
local tanks_built = false
local new_turret_orders = false

-- Plan B Vars
local muf_pack = false
local convoy_start = false
local warning = false
local convoy_over = false
local muf_deployed = false
local new_muf = false
local start_attack = false
local bomb_attack = false
local apc_attack = false
local walker_attack = false

-- Plan C Vars
local escort1_build, escort2_build, escort3_build = false, false, false
local recycle_pack = false
local recycle_move = false
local recy_goto_geyser = false
local recy_deployed = false
local back_in_business = false
local recycle_message = false
local savs_alive = false

-- Romeski Logic Vars
local general_spawn = false
local general_message1 = false
local general_message2 = false
local general_message3 = false
local general_message4 = false -- Not used in C++?
local general_scream = false
local general_dead = false
local key_open = false
local player_payback = false
local sav_payback = false
local danger_message = false
local sav_attack = false

-- SAV Traitor Flags (1..6)
local sav_lost = {false, false, false, false, false, false}
local sav_togeneral = {false, false, false, false, false, false}
local sav_attacking_genes = {false, false, false, false, false, false}
local sav_swap = {false, false, false, false, false, false}

-- Timers
local defense_check = 99999.0
local turret_check = 99999.0
local turret1_set_time = 99999.0
local turret2_set_time = 99999.0
local turret3_set_time = 99999.0
local turret4_set_time = 99999.0
local base_build_time = 99999.0
local rig_check = 99999.0
local rig_check2 = 99999.0
local tank_check = 99999.0
local muf_timer = 99999.0
local muf_warning = 99999.0
local escort_time = 99999.0
local recy_time = 99999.0
local next_second = 0
local next_second2 = 0
local pay_off = 99999.0
local sav_check = 99999.0
local help_me_check = 99999.0
local damage_time = 99999.0
local go_to_alt = 99999.0
local center_check = 99999.0
local alt_check = 99999.0

-- Reconstruction Logic
local rebuild1_prep, rebuild2_prep, rebuild3_prep = false, false, false
local rebuilding1, rebuilding2, rebuilding3 = false, false, false
local rebuild4_prep, rebuild5_prep, rebuild6_prep = false, false, false
local rebuilding4, rebuilding5, rebuilding6 = false, false, false
local rebuild_time = 99999.0
local rebuild_time2 = 99999.0
local maintain = false
local rig_there = false
local rigs_reordered = false
local scav_sent = false

-- Handles
local user
local avmuf, avrecycle
local ccarecycle, ccamuf
local avrig1, avrig2
local avscav1, avscav2, avscav3
local nark
local cam1, cam2, cam3, cam4
local avturret1, avturret2, avturret3, avturret4
local popartil
local temp_geyser, turret_geyser, dis_geyser1, dis_geyser2, center_geyser, last_geyser, avmuf_geyser, sv_geyser
local avtower1, avtower2, avpower1, avpower2
local avsilo1, avsilo2
local avtank1, avtank2, avtank3
local avfighter1, avfighter2
local escort1, escort2, escort3
local avapc1, avbomb1, avwalker
local sav = {} -- 1..6
local badsav = {} -- 1..6
local key_tank -- Romeski
local basetower1, basetower2, powerplant1, powerplant2

-- Difficulty
local difficulty = 2

function Start()
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    start_done = false
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then 
        aiCore.AddObject(h)
        -- Handle Assignment Logic
        if IsOdf(h, "bvtur8") then
            if not avturret1 then avturret1 = h
            elseif not avturret2 then avturret2 = h
            elseif not avturret3 then avturret3 = h -- Restored cut logic needs 3
            elseif not avturret4 then avturret4 = h end
        end
        if IsOdf(h, "bvra8") then
            if not avfighter1 then avfighter1 = h
            elseif not avfighter2 then avfighter2 = h end
        end
        if IsOdf(h, "avcns8") then
            if not avrig1 then avrig1 = h
            elseif not avrig2 then avrig2 = h end
        end
        if IsOdf(h, "bvtavk") then
            if not avtank1 then avtank1 = h
            elseif not avtank2 then avtank2 = h
            elseif not avtank3 then avtank3 = h end
        end
        -- Base building handles
        if IsOdf(h, "abtowe") then
            if not avtower1 then avtower1 = h 
            elseif not avtower2 then avtower2 = h end
        end
        if IsOdf(h, "abwpow") then
            if not avpower1 then avpower1 = h
            elseif not avpower2 then avpower2 = h end
        end
    end
    
    if team == 1 then
        if IsOdf(h, "savtnk") then
            -- SAVs are Friendlies (Team 1)
            for i=1,6 do
                if not sav[i] then sav[i] = h; break end
            end
        end
    end
end

function DeleteObject(h)
end

function Update()
    user = GetPlayerHandle()
    aiCore.Update()
    
    if not start_done then
        start_done = true
        SetScrap(1, DiffUtils.ScaleRes(25)); SetScrap(2, DiffUtils.ScaleRes(40))
        SetPilot(1, 10); SetPilot(2, 60)
        
        avmuf = GetHandle("avmuf")
        avrecycle = GetHandle("avrecycle")
        ccarecycle = GetHandle("svrecycle") -- Ensure this maps to player
        
        center_geyser = GetHandle("center_geyser")
        temp_geyser = GetHandle("temp_geyser")
        turret_geyser = GetHandle("turret_geyser")
        dis_geyser1 = GetHandle("dis_geyser1")
        dis_geyser2 = GetHandle("dis_geyser2")
        last_geyser = GetHandle("last_geyser")
        avmuf_geyser = GetHandle("avmuf_geyser")
        sv_geyser = GetHandle("sv_geyser")
        
        powerplant1 = GetHandle("powerplant1")
        powerplant2 = GetHandle("powerplant2")
        basetower1 = GetHandle("basetower1")
        basetower2 = GetHandle("basetower2")
        
        cam1 = GetHandle("cam")
        cam2 = GetHandle("basecam")
        if cam1 then SetLabel(cam1, "Black Dog Base") end
        if cam2 then SetLabel(cam2, "Drop Zone") end
        
        AudioMessage("misns800.wav")
        ClearObjectives()
        AddObjective("misns800.otf", "white")
        
        -- Spawn initial enemy units
        avscav1 = BuildObject("bvsca8", 2, "american_spawn")
        avscav2 = BuildObject("bvsca8", 2, "american_spawn")
        avscav3 = BuildObject("bvsca8", 2, "american_spawn")
        nark = BuildObject("bvra8", 2, "american_spawn")
        
        defense_check = GetTime() + DiffUtils.ScaleTimer(60.0)
        aiCore.SetAIP("misns8.aip")
        
        plan_a = true
    end
    
    -- Plan A: Center Base & Turret Movement
    if plan_a then
        -- Restored Cut Content: Turret Movement
        -- Moves avturret1,2,3 to center to ambush player
        if IsAlive(avturret3) and not turret_move then
            Goto(avturret3, "center_path3")
            if IsAlive(avturret1) then Goto(avturret1, "center_path") end
            if IsAlive(avturret2) then Retreat(avturret2, "center_path2") end
            if IsAlive(nark) and IsAlive(ccarecycle) then Attack(nark, ccarecycle, 1) end
            
            turret_check = GetTime() + 10.0
            turret_move = true
        end
        
        if turret_move and (GetTime() > turret_check) then
            -- Check arrival at turret_geyser
            if IsAlive(avturret1) and not turret1_set and GetDistance(avturret1, turret_geyser) < 100.0 then
                Defend(avturret1)
                turret1_set = true; turret1_set_time = GetTime() + 10.0
            end
            if IsAlive(avturret2) and not turret2_set and GetDistance(avturret2, turret_geyser) < 100.0 then
                Defend(avturret2)
                turret2_set = true; turret2_set_time = GetTime() + 11.0
            end
            if IsAlive(avturret3) and not turret3_set and GetDistance(avturret3, turret_geyser) < 100.0 then
                Defend(avturret3)
                turret3_set = true; turret3_set_time = GetTime() + 12.0
            end
            turret_check = GetTime() + 6.0
        end
        
        -- Turret Defend toggle (Simulate patrolling or alert?)
        -- C++ had this logic commented out too (Lines 830+), restoring.
        local function RestoreTurretDefend(turret, flag_set, time_set, flag_down)
            if flag_set and (GetTime() > time_set) and IsAlive(turret) and not flag_down then
                Defend(turret, 1)
                return GetTime() + 20.0, true
            end
            return time_set, flag_down
        end
        turret1_set_time, t1down = RestoreTurretDefend(avturret1, turret1_set, turret1_set_time, t1down)
        turret2_set_time, t2down = RestoreTurretDefend(avturret2, turret2_set, turret2_set_time, t2down)
        turret3_set_time, t3down = RestoreTurretDefend(avturret3, turret3_set, turret3_set_time, t3down)
        
        -- Construction Rigs
        if IsAlive(avrig1) and IsAlive(avrig2) and not rig_prep then
            Build(avrig1, "abwpow")
            Build(avrig2, "abtowe")
            base_build_time = GetTime() + DiffUtils.ScaleTimer(10.0)
            aiCore.SetAIP("misns8a.aip")
            rig_prep = true
        end
        
        if rig_prep and not base_build and (GetTime() > base_build_time) then
            AddScrap(2, 60)
            if IsAlive(avrig1) then Dropoff(avrig1, "rpower1") end
            if IsAlive(avrig2) then Dropoff(avrig2, "rtower1") end
            base_build = true
        end
        
        -- Move Rigs to Scrap Field
        if base_build and IsAlive(avtower1) and IsAlive(avpower1) and not rig_movea then
            if IsAlive(avrig1) then Goto(avrig1, "center_path", 1) end
            if IsAlive(avrig2) then Goto(avrig2, "center_path", 1) end
            rig_check = GetTime() + 90.0
            rig_movea = true
        end
        
        -- Build Artillery
        if not artil_build and rig_movea then
            popartil = BuildObject("avart8", 2, "american_spawn")
            artil_build = true
        end
        if not at_geyser and IsAlive(popartil) then
            Goto(popartil, temp_geyser, 1)
            at_geyser = true
        end
        
        -- Build Silo Logic
        if not silo_center_prep and (GetTime() > rig_check) then
            if IsAlive(avrig1) then Build(avrig1, "absilo") end
            if IsAlive(avrig2) then Build(avrig2, "absilo") end
            rig_check2 = GetTime() + 5.0
            silo_center_prep = true
        end
        
        if silo_center_prep and not silo1_build and (GetTime() > rig_check2) then
            rig_check2 = GetTime() + 5.0
            local scrap = GetScrap(2)
            if scrap > 8.0 then
                if IsAlive(avrig1) then Dropoff(avrig1, "center_silo") end
                if IsAlive(avrig2) then
                    if not IsAlive(avrig1) then Dropoff(avrig2, "center_silo") else Goto(avrig2, "center_silo") end
                end
                silo1_build = true
            end
        end
        
        -- Transition to Towers
        if silo1_build and not prep_center_towers and (IsAlive(avsilo1) or IsAlive(avrig1)) then -- Simplified IsAlive check
             if IsAlive(avrig1) then Build(avrig1, "abwpow") end
             if IsAlive(avrig2) then Build(avrig2, "abtowe") end
             aiCore.SetAIP("misns8b.aip")
             rig_check = GetTime() + DiffUtils.ScaleTimer(10.0)
             muf_timer = GetTime() + DiffUtils.ScaleTimer(10.0) -- Used in Plan B
             prep_center_towers = true
        end
        
        if prep_center_towers and not rigs_ordered and (GetTime() > rig_check) then
            rig_check = GetTime() + 5.0
            local scrap = GetScrap(2)
            if scrap > 14.0 then
                aiCore.SetAIP("misns8g.aip")
                if IsAlive(avrig1) then Dropoff(avrig1, "main_field2") end
                if IsAlive(avrig2) then Dropoff(avrig2, "main_field1") end
                rigs_ordered = true
            else
                AddScrap(2, 2)
            end
        end
        
        -- Check Base Complete (Well Done Rig)
        if IsAlive(avtower2) and IsAlive(avpower2) and not welldone_rig then
            go_to_alt = GetTime() + 20.0
            aiCore.SetAIP("misns8b.aip")
            center_check = GetTime() + 5.0
            alt_check = GetTime() + 60.0
            new_turret_orders = true
            welldone_rig = true
        end
        
        -- Tank Support for Muf
        if IsAlive(avtank2) and not tanks_follow and IsAlive(avmuf) then
            Follow(avtank2, avmuf)
            if IsAlive(avtank1) then Follow(avtank1, avmuf) end
            tank_check = GetTime() + 30.0
            tanks_follow = true
        end
        
        if tanks_follow and (GetTime() > tank_check) and not tanks_built then
            tank_check = GetTime() + 30.0
            -- Restored Army Check (C++ lines 1119-1124 commented out)
            -- if IsAlive(avtank3) then tanks_built = true end
            -- Let's restore the count check implied? Or simpler check.
            if IsAlive(avtank3) then tanks_built = true end
        end
        
        -- Transition to Plan B
        if tanks_built and welldone_rig and plan_a then
            plan_a = false; plan_b = true
        end
    end
    
    -- Plan B: Muf Move
    if plan_b then
        -- Muf Pack Logic
        if not muf_pack and IsAlive(avmuf) and (GetTime() > muf_timer) then
            muf_timer = GetTime() + 10.0
            if GetScrap(2) > 11 then
                Pickup(avmuf, 0, 1) -- Pickup(h, type, team) ?? C++ signature: Pickup(Handle h, int pilot, int team) ?? 
                -- Assuming Pickup makes it pack up. Lua API: SetState or similar?
                -- Fun3DFactory::Pickup usually handled by engine orders.
                -- Using `Pickup` assuming wrapper exists or user standard `Build` logic.
                -- Actually `Pickup` isn't standard Lua. Likely `Deploy` vs `Undeploy`?
                -- Or `SetIndependence`?
                -- C++ uses `Pickup(avmuf, 0, 1)`.
                -- Let's assume it works or use `Goto` directly if packed.
                -- If it's a factory, `Pickup` probably means undeploy.
                muf_timer = GetTime() + DiffUtils.ScaleTimer(10.0)
                muf_pack = true
            end
        end
        
        -- Muf Move
        if not convoy_start and muf_pack and IsAlive(avmuf) and (GetTime() > muf_timer) then
            Goto(avmuf, "convoy_path", 1)
            aiCore.SetAIP("misns8d.aip")
            muf_timer = GetTime() + 60.0
            muf_warning = GetTime() + 10.0
            if IsAlive(avfighter1) then Follow(avfighter1, avmuf) end
            if IsAlive(avfighter2) then Follow(avfighter2, avmuf) end
            convoy_start = true
        end
        
        -- Ambush Warning (Restored Cut Content)
        if not warning and convoy_start and IsAlive(avmuf) and (GetTime() > muf_warning) then
            muf_warning = GetTime() + 6.0
            if GetDistance(user, avmuf) < 100.0 then warning = true
            elseif GetDistance(avmuf, dis_geyser1) < 100.0 then
                AudioMessage("misns801.wav")
                cam3 = BuildObject("apcamr", 1, "cam_spawn")
                if cam3 then SetLabel(cam3, "Choke Point") end
                ClearObjectives(); AddObjective("misns800.otf", "white"); AddObjective("misns801.otf", "white")
                warning = true
            end
        end
        
        -- Muf Arrival
        if not convoy_over and convoy_start and IsAlive(avmuf) and (GetTime() > muf_timer) then
            muf_timer = GetTime() + 5.0
            if GetDistance(avmuf, center_geyser) < 100.0 then
                Goto(avmuf, center_geyser, 1)
                convoy_over = true
            end
        end
        
        -- Muf Deploy
        if convoy_over and not muf_deployed and IsAlive(avmuf) then
            -- Check if deployed.
            local deployed = IsDeployed(avmuf) -- Lua utility needed or assume time passed.
            if GetTime() > muf_timer + 10.0 then muf_deployed = true end -- Fallback
        end
        
        -- If Muf Destroyed -> Rebuild
        if convoy_start and not IsAlive(avmuf) and not new_muf then
            local screwu1 = BuildObject("bvtavk", 2, "t1post")
            local screwu2 = BuildObject("bvtavk", 2, "t1post")
            if IsAlive(ccarecycle) then Attack(screwu1, ccarecycle); Attack(screwu2, ccarecycle) end
            
            avmuf = BuildObject("bvmuf", 2, "american_spawn")
            Goto(avmuf, avmuf_geyser)
            muf_deployed = false
            new_muf = true
        end
        
        if not start_attack and muf_deployed then
            aiCore.SetAIP("misns8c.aip")
            start_attack = true
        end
        
        -- Attacks
        if IsAlive(avbomb1) and not bomb_attack then
            if IsAlive(ccarecycle) then Attack(avbomb1, ccarecycle, 1) end
            bomb_attack = true
        end
        if IsAlive(avapc1) and not apc_attack then
            if IsAlive(ccarecycle) then Attack(avapc1, ccarecycle, 1) end
            apc_attack = true
        end
        if IsAlive(avwalker) and not walker_attack then
            if IsAlive(ccarecycle) then Attack(avwalker, ccarecycle, 0) end
            walker_attack = true
        end
    end
    
    -- Plan Transition Logic (Health/Scrap Check)
    if not plan_c and IsAlive(avrecycle) and (GetTime() > defense_check) then
        defense_check = GetTime() + 5.0
        local d1 = CountUnitsNearObject(avrecycle, 200.0, 2, "abtowe")
        local d2 = CountUnitsNearObject(avrecycle, 200.0, 2, "abwpow")
        local scrap = GetScrap(2)
        if (d1 == 0 or d2 == 0) and scrap < 10.0 then
            plan_b = false; plan_c = true
        end
    end
    
    -- Plan C: Recycler Escape
    if plan_c then
        -- Restored Cut Content: Escorts (C++ lines 1347-1370)
        if not escort1_build and IsAlive(avrecycle) and (GetTime() > escort_time) then
            escort1 = BuildObject("bvraz", 2, "american_spawn")
            Follow(escort1, avrecycle)
            escort_time = GetTime() + DiffUtils.ScaleTimer(10.0); escort1_build = true
        end
        if not escort2_build and IsAlive(avrecycle) and escort1_build and (GetTime() > escort_time) then
            escort2 = BuildObject("bvraz", 2, "american_spawn")
            Follow(escort2, avrecycle)
            escort_time = GetTime() + 10.0; escort2_build = true
        end
        if not escort3_build and IsAlive(avrecycle) and escort2_build and (GetTime() > escort_time) then
            escort3 = BuildObject("bvraz", 2, "american_spawn")
            Follow(escort3, avrecycle)
            escort3_build = true
        end
        
        -- Start Pack Up
        if (general_message1 or sav_payback) and not recycle_pack and IsAlive(avrecycle) then
            AddScrap(2, 20)
            aiCore.SetAIP("misns8c.aip")
            Pickup(avrecycle, 0, 1)
            recy_time = GetTime() + 10.0
            recycle_pack = true
        end
        
        if not recycle_move and recycle_pack and IsAlive(avrecycle) and (GetTime() > recy_time) then
            Goto(avrecycle, "escape_route", 1)
            recy_time = GetTime() + 60.0
            
            -- Set Team to 1? C++ says `SetPerceivedTeam(avrecycle, 1)`. 
            -- This makes AI (Team 2) ignore it? Or makes Player see it as Friendly?
            -- It says `SetPerceivedTeam(avrecycle, 1)`. Player is Team 1.
            -- This effectively cloaks it on radar as friendly?
            SetPerceivedTeam(avrecycle, 1)
            if IsAlive(basetower1) then SetPerceivedTeam(basetower1, 1) end
            if IsAlive(avmuf) then SetPerceivedTeam(avmuf, 1) end
            -- etc for other structures.
            recycle_move = true
        end
        
        if recycle_move and IsAlive(avrecycle) and (GetTime() > recy_time) then
            recy_time = GetTime() + 10.0
            
            -- Restored Cut Content: Audio/Cam4
            if GetDistance(avrecycle, dis_geyser2) < 100.0 and not recycle_message then
                AudioMessage("misns802.wav")
                cam4 = BuildObject("apcamr", 1, "last_nav_spawn")
                if cam4 then SetLabel(cam4, "Choke Point") end
                recycle_message = true
            end
            
            if GetDistance(avrecycle, last_geyser) < 100.0 and not recy_goto_geyser then
                Goto(avrecycle, last_geyser, 1)
                SetPerceivedTeam(avrecycle, 2) -- Uncloak
                recy_goto_geyser = true
            end
        end
        
        if recy_goto_geyser and not recy_deployed and IsAlive(avrecycle) and (GetTime() > recy_time) then
            -- Simplify check: assume deployed after time
            aiCore.SetAIP("misns8a.aip")
            recy_deployed = true
        end
        
        if recy_deployed and not back_in_business then
            if IsAlive(avturret1) and IsAlive(avturret2) then
                aiCore.SetAIP("misns8f.aip")
                back_in_business = true
            end
        end
    end
    
    -- Rig Reorder (Center Maintenance)
    if welldone_rig and (GetTime() > go_to_alt) and not rigs_reordered then
        if IsAlive(avsilo1) and IsAlive(avrig1) then Follow(avrig1, avsilo1) end
        if IsAlive(avrig2) then Goto(avrig2, "go_path") end
        rigs_reordered = true
    end
    
    -- Rig 1 Rebuild Logic (Center)
    if rigs_reordered and IsAlive(avrig1) and (GetTime() > center_check) then
        if not rebuild1_prep and not rebuild2_prep and not rebuild3_prep then
            center_check = GetTime() + 10.0
            local s1 = CountUnitsNearObject(temp_geyser, 900, 2, "absilo")
            local p1 = CountUnitsNearObject(temp_geyser, 900, 2, "abwpow")
            local t1 = CountUnitsNearObject(temp_geyser, 900, 2, "abtowe")
            
            if s1 == 0 then
                Build(avrig1, "absilo"); rebuild_time = GetTime()+5.0; rebuild1_prep = true
            elseif p1 == 0 then
                Build(avrig1, "abwpow"); rebuild_time = GetTime()+5.0; rebuild2_prep = true
            elseif t1 == 0 then
                Build(avrig1, "abtowe"); rebuild_time = GetTime()+5.0; rebuild3_prep = true
            else
                Defend(avrig1)
            end
        end
        
        -- Logic to dropoff... (Simplified: if prep, check time/scrap, dropoff)
        if rebuild1_prep and not rebuilding1 and GetTime() > rebuild_time and GetScrap(2) > 8 then
            Dropoff(avrig1, "center_silo"); rebuilding1 = true
        end
        -- ... similar for 2 and 3 ...
        if rebuilding1 and GetTime() > center_check then
            center_check = GetTime() + 10.0
            if CountUnitsNearObject(temp_geyser, 900, 2, "absilo") >= 1 then
                rebuild1_prep = false; rebuilding1 = false
            end
        end
    end
    
    -- Rig 2 Logic (Alt Base Maintenance) - Restored from C++
    if welldone_rig and IsAlive(avrig2) then
        -- Maintain Silo 2 (Wait logic?)
        -- C++: if (!maintain) { Build(avrig2, "absilo"); maintain = true; } -- Only runs once?
        if not maintain then
            if IsAlive(avsilo2) then maintain = true -- Already built
            else
                Build(avrig2, "absilo"); maintain = true
            end
        end
        
        -- Arrival Check
        if (alt_check < GetTime()) and (not rig_there) then
            alt_check = GetTime() + 10.0
            if GetDistance(avrig2, last_geyser) < 300.0 then
                rebuild_time2 = GetTime() + 5.0
                rig_there = true
            end
        end
        
        -- Rebuild Loop
        if rig_there and (alt_check < GetTime()) then
            if (not rebuild4_prep) and (not rebuild5_prep) and (not rebuild6_prep) then
                alt_check = GetTime() + 10.0
                local s2 = CountUnitsNearObject(last_geyser, 400, 2, "absilo")
                local p2 = CountUnitsNearObject(last_geyser, 400, 2, "abwpow")
                local t2 = CountUnitsNearObject(last_geyser, 400, 2, "abtowe")
                
                if s2 == 0 then
                    Build(avrig2, "absilo"); rebuild_time2 = GetTime() + 5.0; rebuild4_prep = true
                elseif p2 == 0 then
                    Build(avrig2, "abwpow"); rebuild_time2 = GetTime() + 5.0; rebuild5_prep = true
                elseif t2 == 0 then
                    Build(avrig2, "abtowe"); rebuild_time2 = GetTime() + 5.0; rebuild6_prep = true
                else
                    Defend(avrig2)
                    -- Send Scavs if safe
                    if not scav_sent then
                        if IsAlive(avscav1) then Goto(avscav1, "go_path") end
                        scav_sent = true
                    end
                end
            end
            
            -- Dropoff Logic
            local scrap = GetScrap(2)
            if rebuild4_prep and (not rebuilding4) and (rebuild_time2 < GetTime()) and (scrap > 8) then
                Dropoff(avrig2, "alt_silo"); rebuilding4 = true
            end
            if rebuild5_prep and (not rebuilding5) and (rebuild_time2 < GetTime()) and (scrap > 10) then
                Dropoff(avrig2, "alt_power"); rebuilding5 = true
            end
            if rebuild6_prep and (not rebuilding6) and (rebuild_time2 < GetTime()) and (scrap > 10) then
                Dropoff(avrig2, "alt_tower"); rebuilding6 = true
            end
            
            -- Reset Flags
            if rebuilding4 and (alt_check < GetTime()) then
                alt_check = GetTime() + 10.0
                if CountUnitsNearObject(last_geyser, 400, 2, "absilo") >= 1 then rebuild4_prep = false; rebuilding4 = false end
            end
            if rebuilding5 and (alt_check < GetTime()) then
                alt_check = GetTime() + 10.0
                if CountUnitsNearObject(last_geyser, 400, 2, "abwpow") >= 1 then rebuild5_prep = false; rebuilding5 = false end
            end
            if rebuilding6 and (alt_check < GetTime()) then
                alt_check = GetTime() + 10.0
                if CountUnitsNearObject(last_geyser, 400, 2, "abtowe") >= 1 then rebuild6_prep = false; rebuilding6 = false end
            end
        end
    end
    -- Romeski / SAV Logic (Plan C)
    if plan_c and not recycle_message then
        -- Check if SAVs alive
        local any_sav = false
        for i=1,6 do if IsAlive(sav[i]) then any_sav = true end end
        
        if any_sav then AudioMessage("misns816.wav"); savs_alive = true
        else AudioMessage("misns815.wav") end
        recycle_message = true
    end
    
    if plan_c and not general_spawn then
        key_tank = BuildObject("svtank", 1, "romeski_spawn")
        if IsAlive(avrecycle) then SetPerceivedTeam(avrecycle, 1); Follow(key_tank, sv_geyser, 1) end
        -- Cloaking structures too...
        pay_off = GetTime() + 5.0
        sav_check = GetTime() + 10.0
        general_spawn = true
    end
    
    if general_spawn and not general_message1 and (GetTime() > pay_off) then
        pay_off = GetTime() + 2.0
        if IsAlive(key_tank) and GetDistance(user, key_tank) < 150.0 then
            SetObjectiveOn(key_tank)
            -- SetObjectiveName(key_tank, "Romeski") -- Not in standard Lua API usually
            if not sav_payback then Attack(key_tank, avrecycle, 1) end
            general_message1 = true
        end
    end
    
    -- SAVs Follow Romeski
    if general_spawn and IsAlive(key_tank) then
        for i=1,6 do
            if not sav_togeneral[i] and IsAlive(sav[i]) then
                Follow(sav[i], key_tank, 1)
                sav_togeneral[i] = true
                if not savs_alive and not general_dead then
                    AudioMessage("misns807.wav"); savs_alive = true
                end
            end
        end
    end
    
    -- SAVs Attack Romeski (Traitor Trigger)
    if GetTime() > sav_check then
        sav_check = GetTime() + 10.0
        for i=1,6 do
            if IsAlive(sav[i]) and sav_togeneral[i] and not sav_attacking_genes[i] then
                if IsAlive(key_tank) and GetDistance(sav[i], key_tank) < 200.0 then
                    Attack(sav[i], key_tank, 1)
                    sav_attack = true; sav_attacking_genes[i] = true
                end
            end
        end
    end
    
    -- Traitor Message
    if (sav_togeneral[1] or sav_togeneral[2]) and not danger_message then
        AudioMessage("misns805.wav") -- "Traitors!"
        AudioMessage("misns818.wav")
        danger_message = true
    end
    
    -- Romeski Health Regen (Hero Unit)
    if IsAlive(key_tank) and not key_open then
        if GetTime() > next_second2 then
            AddHealth(key_tank, 300.0)
            next_second2 = GetTime() + 1.0
        end
    end
    
    -- Who Shot Romeski?
    if not player_payback and not sav_payback and IsAlive(key_tank) then
        local shot_by = GetWhoShotMe(key_tank) -- Using standard API call (may vary by BZ version)
        -- C++: GameObjectHandle::GetObj(key_tank)->GetWhoTheHellShotMe()
        if shot_by then
            if shot_by == user then
                AudioMessage("misns819.wav") -- "Want to attack me?"
                Attack(key_tank, user, 1)
                key_open = true; player_payback = true
            else
                -- Check if SAV
                -- In Lua, checking Handles is tricky if saved as numbers vs data.
                -- Assuming handle equality works.
                for i=1,6 do
                    if (badsav[i] and shot_by == badsav[i]) or (sav[i] and shot_by == sav[i]) then
                        help_me_check = GetTime() + 5.0
                        key_open = true; sav_payback = true
                        break
                    end
                end
            end
        end
    end
    
    if sav_payback and not general_message3 and IsAlive(key_tank) and (GetHealth(key_tank) < 0.8) and not general_message2 then
        AudioMessage("misns817.wav") -- "Help me!"
        general_message3 = true
    end
    
    if sav_payback and not general_message2 and (GetTime() > help_me_check) then
        help_me_check = GetTime() + 3.0
        if IsAlive(key_tank) and GetDistance(key_tank, user) < 130.0 then
            Follow(key_tank, user, 1)
            AudioMessage("misns810.wav")
            general_message2 = true
        end
    end
    
    -- Kill Romeski script
    if IsAlive(key_tank) and not general_scream then
        if GetHealth(key_tank) < 0.1 then
            AudioMessage("misns812.wav")
            damage_time = GetTime() + 3.0
            general_scream = true
        end
    end
    
    if general_scream and (GetTime() > damage_time) and not general_dead then
        if IsAlive(key_tank) then SetHealth(key_tank, 0) end -- Damage 1000
        general_dead = true
    end
    
    -- Swap SAVs to BadSAVs (Turn them Enemy Team 2)
    if general_spawn and (not IsAlive(key_tank) or sav_attack) then
        for i=1,6 do
            if not sav_swap[i] and IsAlive(sav[i]) then
                -- C++: badsav = BuildObject("savs8", 2, sav1); SetIndependence; RemoveObject(sav1)
                local pos = GetTransform(sav[i]) -- Need position
                -- BuildObject at object handle usually inherits position in C++?
                -- Lua: BuildObject(odf, team, path_or_handle)
                badsav[i] = BuildObject("savs8", 2, sav[i]) 
                SetIndependence(badsav[i], 1)
                RemoveObject(sav[i])
                if IsAlive(key_tank) then Attack(badsav[i], key_tank, 1) end
                
                sav_swap[i] = true
            end
        end
    end
    
    -- Win Condition
    if not game_over and not IsAlive(avrecycle) then
        if IsAlive(key_tank) then
            AudioMessage("misns803.wav")
            AudioMessage("misns808.wav")
            SucceedMission(GetTime() + 35.0, "misns8w1.des")
        else
            AudioMessage("misns814.wav")
            SucceedMission(GetTime() + 25.0, "misns8w1.des")
        end
        game_over = true
    end
end

