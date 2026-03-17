-- Misn08 Mission Script (Converted from Misn08Mission.cpp)

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
local start_done = false
local gech_found = false
local gech_found1 = false
local gech_found2 = false
local base_dead = false
local player_dead = false
local unit_spawn = false
local gech_at_nav = false
local gech_at_nav2 = false
local gech_at_nav3 = false
local player_warned_ofgech = false
local colorado_under_attack = false
local colorado_destroyed = false
local followup_message = false
local colorado_message2 = false
local colorado_message3 = false
local colorado_message4 = false
local second_gech_warning = false
local run_into_other_gech = false
local too_close_message = false
local bad_news = false
local base_exposed = false
local bump_into_gech = false
local ccarecycle_spawned = false
local gech_started = false
local gech3_move = false
local first_wave = false
local second_wave = false
local next_wave = false
local gech1_at_base = false
local gech2_at_base = false
local gech3_at_base = false
local gech1_blossom = false
local gech2_blossom = false
local gech3_blossom = false
local fresh_meat = false
local fighter_message = false
local apc_attack = false
local base_set = false
local game_over = false
local cerb_found = false
local relic_message = false
local kill_colorado = false
local gen_message = false

-- Timers
local unit_spawn_time = 999999.0
local followup_message_time = 999999.0
local colorado_message2_time = 999999.0
local colorado_message3_time = 999999.0
local colorado_message4_time = 999999.0
local bad_news_time = 999999.0
local gech_warning_message = 999999.0
local remove_nav5_time = 999999.0
local gech_spawn_time = 999999.0
local gech_check = 999999.0
local gech_check2 = 999999.0
local stumble1_check = 999999.0
local stumble2_check = 999999.0
local trigger_check = 999999.0
local no_stumble_check = 999999.0
local time_waist = 999999.0
local start_gech_time = 999999.0
local gech_check_time = 10.0
local first_wave_time = 999999.0
local second_wave_time = 999999.0
local next_wave_time = 999999.0
local gech1_there_time = 999999.0
local gech2_there_time = 999999.0
local gech3_there_time = 999999.0
local new_aip_time = 999999.0
local fresh_meat_time = 999999.0
local fighter_message_time = 200.0
local player_nosey_time = 45.0
local pull_out_message = 999999.0
local base_check = 999999.0
local cerb_check = 30.0
local next_second = 999999.0
local next_second2 = 999999.0

-- Handles
local user
local nsdfrecycle, ccarecycle, ccamuf, nsdfmuf
local ccagech1, ccagech2, ccagech3
local nav1, nav2, nav3, nav4, nav5
local gech_trigger2, gech_trigger3
local colorado
local attack_geys, ccarecycle_geyser
local stop_geyser1, stop_geyser2, stop_geyser3
local svpatrol1_1, svpatrol1_2, svpatrol1_3
local svpatrol2_1, svpatrol2_2, svpatrol2_3
local cannon_fodder1, cannon_fodder2, cannon_fodder3
local ccaapc, guntower1, guntower2
local relic1, relic2, main_relic

local difficulty = 2

function Start()
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    
    start_done = false
    gech_check_time = 10.0
    fighter_message_time = 200.0
    player_nosey_time = 45.0
    cerb_check = 30.0
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
    
    -- Mission Handles (C++ AddObject replacement)
    local odf = GetOdf(h)
    if odf then odf = string.gsub(odf, "%z", "") end
    if not nsdfmuf and odf == "avfact" then nsdfmuf = h end -- C++ "avmu8" -> likely avfact in Lua or ODF map
    if not ccaapc and odf == "svapc" then ccaapc = h end
    if not guntower1 and odf == "abtowe" then guntower1 = h
    elseif not guntower2 and odf == "abtowe" then guntower2 = h end
end

function DeleteObject(h)
end

function Update()
    user = GetPlayerHandle()
    aiCore.Update()
    
    if not start_done then
        AudioMessage("misn0800.wav")
        ClearObjectives()
        AddObjective("misn0800.otf", "white")
        AddObjective("misn0801.otf", "white")
        
        SetScrap(1, DiffUtils.ScaleRes(30))
        
        ccagech1 = GetHandle("sovgech1")
        ccagech2 = GetHandle("sovgech2")
        Defend(ccagech1)
        Defend(ccagech2)
        SetWeaponMask(ccagech1, 1) -- Walk mode
        SetWeaponMask(ccagech2, 1) -- Walk mode
        
        nsdfrecycle = GetHandle("avrecycle")
        ccarecycle = GetHandle("svrecycle") -- Might be nil initially? C++ GetHandle("svrecycle")
        ccamuf = GetHandle("svmuf")
        
        nav1 = GetHandle("cam1")
        nav4 = GetHandle("cam2")
        nav5 = GetHandle("cam5")
        SetLabel(nav1, "Drop Zone")
        SetLabel(nav5, "Colorado Base")
        SetLabel(nav4, "CCA Main Base")
        
        gech_trigger2 = GetHandle("giez_spawn2")
        gech_trigger3 = GetHandle("giez_spawn3")
        colorado = GetHandle("colorado")
        
        stop_geyser2 = GetHandle("stop_geyser2")
        stop_geyser3 = GetHandle("stop_geyser3")
        
        svpatrol1_1 = GetHandle("svpatrol1_1")
        svpatrol1_2 = GetHandle("svpatrol1_2")
        svpatrol1_3 = GetHandle("svpatrol1_3")
        svpatrol2_1 = GetHandle("svpatrol2_1")
        svpatrol2_2 = GetHandle("svpatrol2_2")
        svpatrol2_3 = GetHandle("svpatrol2_3")
        
        relic1 = GetHandle("hbblde1_i76building")
        relic2 = GetHandle("hbbldf1_i76building")
        main_relic = GetHandle("hbcerb1_i76building")
        
        start_gech_time = GetTime() + DiffUtils.ScaleTimer(329.0)
        gech_spawn_time = GetTime() + DiffUtils.ScaleTimer(280.0)
        trigger_check = GetTime() + DiffUtils.ScaleTimer(285.0)
        fresh_meat_time = GetTime() + DiffUtils.ScaleTimer(100.0)
        gech_check = GetTime() + DiffUtils.ScaleTimer(61.0)
        first_wave_time = GetTime() + DiffUtils.ScaleTimer(20.0)
        base_check = GetTime() + DiffUtils.ScaleTimer(5.0)
        
        start_done = true
    end
    
    -- Start Gechs
    if start_done and (start_gech_time < GetTime()) and (not gech_started) then
        Goto(ccagech1, "gech_path1")
        Goto(ccagech2, "gech_path2")
        gech_started = true
    end
    
    -- First Wave
    if (first_wave_time < GetTime()) and (not first_wave) then
        if IsAlive(svpatrol2_2) then Goto(svpatrol2_2, nsdfrecycle) end
        if IsAlive(svpatrol2_3) then Goto(svpatrol2_3, nsdfrecycle) end
        first_wave = true
    end
    
    -- Fresh Meat (Reinforcements)
    if (fresh_meat_time < GetTime()) and (not colorado_under_attack) and (not fresh_meat) and IsAlive(ccarecycle) then
        cannon_fodder1 = BuildObject("svfigh", 2, ccarecycle)
        cannon_fodder2 = BuildObject("svfigh", 2, ccarecycle)
        cannon_fodder3 = BuildObject("svfigh", 2, ccarecycle)
        Goto(cannon_fodder1, "gech_path2")
        Goto(cannon_fodder2, "gech_path2")
        Goto(cannon_fodder3, "gech_path2")
        fresh_meat = true;
    end
    
    if (fighter_message_time < GetTime()) and (not colorado_under_attack) and (not fighter_message) then
        AudioMessage("misn0817.wav")
        fighter_message = true
    end
    
    -- Colorado Attack (Gech 3)
    if (gech_spawn_time < GetTime()) and (not colorado_under_attack) then
        gech_spawn_time = GetTime() + DiffUtils.ScaleTimer(10.0)
        
        if GetDistance(user, nav5) > 400.0 then
            -- Initial attack wave
            BuildObject("svfigh", 2, ccarecycle) -- Dummies? C++ rebuilds svpatrol2_2
            BuildObject("svltnk", 2, ccarecycle)
            
            ccagech3 = BuildObject("svwalk", 2, "gech_spawn")
            SetWeaponMask(ccagech3, 1)
            Attack(ccagech3, colorado, 1)
            
            AudioMessage("misn0801.wav")
            colorado_message2_time = GetTime() + 10.0
            
            if IsAlive(svpatrol2_1) then Goto(svpatrol2_1, nav1) end
            if IsAlive(svpatrol2_2) then Goto(svpatrol2_2, nav1) end
            if IsAlive(svpatrol2_3) then Goto(svpatrol2_3, nav1) end
            
            colorado_under_attack = true
        end
    end
    
    -- Player Nosey (Early Colorado approach)
    if (player_nosey_time < GetTime()) and (not colorado_under_attack) then
        player_nosey_time = GetTime() + 32.0
        if GetDistance(user, nav5) < 700.0 then
            gech_spawn_time = GetTime() + 10.0 -- Force trigger soon
            -- Aggro everyone
            local pats = {svpatrol1_1, svpatrol1_2, svpatrol1_3, svpatrol2_1, svpatrol2_2, svpatrol2_3}
            for _, p in ipairs(pats) do
                if IsAlive(p) then Attack(p, user) end -- Or Recycler for group 2 as in C++
            end
        end
    end
    
    -- Colorado Messages
    if colorado_under_attack and (colorado_message2_time < GetTime()) and (not colorado_message2) then
        AudioMessage("misn0803.wav")
        colorado_message3_time = GetTime() + 7.0
        colorado_message2 = true
    end
    
    if colorado_message2 and (colorado_message3_time < GetTime()) and (not colorado_message3) then
        AudioMessage("misn0802.wav")
        AudioMessage("misn0804.wav")
        colorado_message4_time = GetTime() + DiffUtils.ScaleTimer(10.0)
        colorado_message3 = true
    end
    
    if (colorado_message4_time < GetTime()) and (not kill_colorado) then
        kill_colorado = true
    end
    
    -- Keep Colorado alive until scripted death
    if IsAlive(colorado) and (not kill_colorado) then
        if GetTime() > next_second then
            AddHealth(colorado, 500)
            next_second = GetTime() + 1.0
        end
    end
    
    if colorado_message3 and kill_colorado and (not colorado_message4) then
        if IsAlive(colorado) then SetHealth(colorado, 0) end -- Or massive Damage
        remove_nav5_time = GetTime() + 15.0
        colorado_message4 = true
    end
    
    if colorado_message4 and (remove_nav5_time < GetTime()) and (not colorado_destroyed) then
        if IsAlive(nav5) then RemoveObject(nav5) end
        bad_news_time = GetTime() + 5.0
        colorado_destroyed = true
    end
    
    if colorado_destroyed and (not bad_news) and (bad_news_time < GetTime()) then
        AudioMessage("misn0805.wav")
        bad_news_time = GetTime() + 30.0
        bad_news = true
    end
    
    if bad_news and (bad_news_time < GetTime()) and (not gen_message) then
        AudioMessage("misn0810.wav")
        gen_message = true
    end
    
    -- CCA Base Activation
    if bad_news and (not ccarecycle_spawned) then
        SetAIP("misn08.aip")
        SetScrap(2, 40)
        new_aip_time = GetTime() + 420.0
        
        if IsAlive(ccagech3) then Goto(ccagech3, "gech_path2") end
        
        local cam3_spawn_list = {svpatrol1_1, svpatrol1_2, svpatrol1_3}
        for _, p in ipairs(cam3_spawn_list) do
            if IsAlive(p) then Goto(p, "cam3_spawn") end
        end
        
        ccarecycle_spawned = true
    end
    
    -- Gech Stumble Logic
    if (gech_check < GetTime()) and (not gech_found) and (not gech_at_nav) then
        gech_check = GetTime() + 6.0
        
        if (GetDistance(user, ccagech1) < 400.0) and (not gech_found1) then
            AudioMessage("misn0806.wav")
            followup_message_time = GetTime() + 20.0
            stumble2_check = GetTime() + 10.0
            no_stumble_check = GetTime() + 13.0
            gech_found1 = true
            gech_found = true
        end
        
        if (GetDistance(user, ccagech2) < 400.0) and (not gech_found2) then
            AudioMessage("misn0806.wav")
            followup_message_time = GetTime() + 5.0
            stumble2_check = GetTime() + 60.0
            no_stumble_check = GetTime() + 13.0
            gech_found2 = true
            gech_found = true
        end
    end
    
    if gech_found and (followup_message_time < GetTime()) and (not followup_message) then
        AudioMessage("misn0807.wav")
        followup_message = true
    end
    
    -- Base Set (deployed) logic
    if (base_check < GetTime()) and (not base_set) then
        base_check = GetTime() + 2.0
        if IsAlive(nsdfmuf) then -- Assuming Recycler built Factory ("avmu8" -> nsdfmuf)
             -- C++ cast to Factory and IsDeployed check.
             -- Lua: Maybe just check if it exists or use GetODF
             -- C++ actually checks if nsdfmuf (Factory) is deployed.
             base_set = true
             ClearObjectives()
             AddObjective("misn0800.otf", "green")
             AddObjective("misn0801.otf", "white")
        end
    end
    
    -- Approaching Gech Warning
    if colorado_under_attack and (trigger_check < GetTime()) and (not gech_at_nav) and (not gech_found) then
        trigger_check = GetTime() + 19.0
        
        if (GetDistance(gech_trigger2, ccagech2) < 100.0) then
            AudioMessage("misn0809.wav") -- East
            gech_warning_message = GetTime() + 20.0
            gech1_there_time = GetTime() + 100.0
            gech2_there_time = GetTime() + 105.0
            gech_at_nav = true
            gech_at_nav2 = true
        end
        
        if (GetDistance(gech_trigger3, ccagech1) < 100.0) then
            AudioMessage("misn0808.wav") -- West
            gech_warning_message = GetTime() + 20.0
            gech1_there_time = GetTime() + 100.0
            gech2_there_time = GetTime() + 105.0
            gech_at_nav = true
            gech_at_nav3 = true
        end
    end
    
    -- Spawn Navs if warning ignored
    if (gech_at_nav2) and (gech_warning_message < GetTime()) and (not player_warned_ofgech) then
        AudioMessage("misn0814.wav")
        nav2 = BuildObject("apcamr", 1, "cam2_spawn")
        SetLabel(nav2, "Nav Alpha 1")
        time_waist = GetTime() + 14.0
        stumble1_check = GetTime() + 100.0
        player_warned_ofgech = true
    end
    if (gech_at_nav3) and (gech_warning_message < GetTime()) and (not player_warned_ofgech) then
        AudioMessage("misn0815.wav")
        nav3 = BuildObject("apcamr", 1, "cam3_spawn")
        SetLabel(nav3, "Nav Alpha 2")
        time_waist = GetTime() + 14.0
        stumble1_check = GetTime() + 100.0
        player_warned_ofgech = true
    end
    
    -- Gech Attack Base/Blossom
    local function GechAttackLogic(gech, timer_var_name, base_var_name, blossom_var_name)
        if IsAlive(gech) and (GetDistance(gech, stop_geyser3) < 100.0) then
            local target = nsdfrecycle
            if not IsAlive(target) then target = nsdfmuf end
            
            if IsAlive(target) then
                Attack(gech, target)
                _G[base_var_name] = true
                if _G[blossom_var_name] then SetWeaponMask(gech, 5) end
            end
        end
    end
    
    if (gech_found or gech_at_nav) then
        -- (Ideally use table for timers, using hard references for port accuracy)
        if (gech1_there_time < GetTime()) and (not gech1_at_base) then
            gech1_there_time = GetTime() + 30.0
            GechAttackLogic(ccagech1, "gech1_there_time", "gech1_at_base", "gech1_blossom")
        end
        if (gech2_there_time < GetTime()) and (not gech2_at_base) then
            gech2_there_time = GetTime() + 30.0
            GechAttackLogic(ccagech2, "gech2_there_time", "gech2_at_base", "gech2_blossom")
        end
        if (gech3_there_time < GetTime()) and (not gech3_at_base) then
            gech3_there_time = GetTime() + 30.0
            GechAttackLogic(ccagech3, "gech3_there_time", "gech3_at_base", "gech3_blossom")
        end
    end
    
    -- AIP Swapping
    if (new_aip_time < GetTime()) then
        new_aip_time = GetTime() + 420.0
        local units1 = CountUnitsNearObject(stop_geyser2, 5000.0, 1, "avfigh")
        local units2 = CountUnitsNearObject(stop_geyser2, 5000.0, 1, "avtank")
        
        if units1 > units2 then SetAIP("misn08b.aip")
        else SetAIP("misn08a.aip") end
    end
    
    -- APC Attack
    if IsAlive(ccaapc) and (not apc_attack) then
        local tgt = guntower1
        if not IsAlive(tgt) then tgt = guntower2 end
        if not IsAlive(tgt) then tgt = nsdfmuf end
        if not IsAlive(tgt) then tgt = nsdfrecycle end
        
        if IsAlive(tgt) then
            Attack(ccaapc, tgt)
            apc_attack = true
        end
    end
    if apc_attack and (not IsAlive(ccaapc)) then apc_attack = false end
    
    -- Gech Blossom (Low Health)
    local function CheckBlossom(gech, blossom_var)
        if IsAlive(gech) and (not _G[blossom_var]) and (GetHealth(gech) < 0.25) then
            SetWeaponMask(gech, 4) -- Deploy?
            pull_out_message = GetTime() + 6.0
            _G[blossom_var] = true
        end
    end
    CheckBlossom(ccagech1, "gech1_blossom")
    CheckBlossom(ccagech2, "gech2_blossom")
    CheckBlossom(ccagech3, "gech3_blossom")
    
    if (pull_out_message < GetTime()) and (not too_close_message) then
        AudioMessage("misn0816.wav") -- "Pull out!"
        too_close_message = true
    end
    
    -- Relics
    if (not cerb_found) and (not relic_message) and (IsInfo("hbblde") or IsInfo("hbbldf")) then
        if base_dead then AudioMessage("misn0821.wav")
        else AudioMessage("misn0822.wav") end
        relic_message = true
    end
    
    if (not cerb_found) and (cerb_check < GetTime()) then
        cerb_check = GetTime() + 3.0
        if GetDistance(user, main_relic) < 70.0 then
            if base_dead then
                AudioMessage("misn0818.wav")
                AudioMessage("misn0826.wav")
                SucceedMission(GetTime() + 30.0, "misn08w1.des")
                cerb_found = true
            else
                AudioMessage("misn0819.wav")
                cerb_found = true
            end
        end
    end
    
    -- Keep Relic Alive
    if IsAlive(main_relic) then
        if GetTime() > next_second2 then
            AddHealth(main_relic, 500)
            next_second2 = GetTime() + 1.0
        end
    end
    
    -- Win/Loss
    if (not IsAlive(ccarecycle)) and (not IsAlive(ccamuf)) and (not base_dead) then
        if cerb_found then
            AudioMessage("misn0818.wav")
            AudioMessage("misn0826.wav")
            SucceedMission(GetTime() + 30.0, "misn08w1.des")
            base_dead = true
        else
            ClearObjectives()
            AddObjective("misn0801.otf", "green")
            AddObjective("misn0802.otf", "white")
            AudioMessage("misn0820.wav")
            SetObjectiveOn(main_relic)
            SetLabel(main_relic, "Relic Site")
            base_dead = true
        end
    end
    
    if (not IsAlive(nsdfrecycle)) and (not game_over) then
        AudioMessage("misn0421.wav")
        FailMission(GetTime() + 15.0, "misn08f1.des")
        game_over = true
    end
end

