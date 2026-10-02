-- misn08: faithful BZ1 DLL mission port for stock Battlezone 98 Redux / Lua 5.1.
-- Authority: Battlezone_Source/BZ1/from_bz2_dll_src/Misn08Mission.cpp
-- Source blob: d1581e4d62251a9a452e26c30fee162a90cf9571
-- No community/Lua mission used as behavioral evidence.
-- Disabled code is translated in place; the full original is archived below.
-- Intentional source quirks (timers, duplicate spawn assignment, outcome ordering)
-- remain unchanged. Two AddObject copy/paste typos are explicitly repaired.
-- Requires stock misn08 map labels, paths, AIPs, OTF/audio/debrief assets.
-- Native team-2 strategic AI is enabled at startup; no aiCore replacement is used.

local M = {}

local function ResetState()
    M = {
        -- Original bool save fields, including dormant cut-content state.
        start_done = false,
        gech_found = false,
        gech_found1 = false,
        gech_found2 = false,
        base_dead = false,
        player_dead = false,
        unit_spawn = false,
        gech_at_nav = false,
        gech_at_nav2 = false,
        gech_at_nav3 = false,
        player_warned_ofgech = false,
        colorado_under_attack = false,
        colorado_destroyed = false,
        followup_message = false,
        colorado_message2 = false,
        colorado_message3 = false,
        colorado_message4 = false,
        second_gech_warning = false,
        run_into_other_gech = false,
        too_close_message = false,
        bad_news = false,
        base_exposed = false,
        bump_into_gech = false,
        ccarecycle_spawned = false,
        gech_started = false,
        gech3_move = false,
        first_wave = false,
        second_wave = false,
        next_wave = false,
        gech1_at_base = false,
        gech2_at_base = false,
        gech3_at_base = false,
        gech1_blossom = false,
        gech2_blossom = false,
        gech3_blossom = false,
        fresh_meat = false,
        fighter_message = false,
        apc_attack = false,
        base_set = false,
        game_over = false,
        cerb_found = false,
        relic_message = false,
        kill_colorado = false,
        gen_message = false,
        -- Original float save fields, including dormant cut-content state.
        unit_spawn_time = 99999.0,
        followup_message_time = 99999.0,
        colorado_message2_time = 99999.0,
        colorado_message3_time = 99999.0,
        colorado_message4_time = 99999.0,
        bad_news_time = 99999.0,
        gech_warning_message = 99999.0,
        remove_nav5_time = 99999.0,
        gech_spawn_time = 99999.0,
        gech_check = 99999.0,
        gech_check2 = 99999.0,
        stumble1_check = 99999.0,
        stumble2_check = 99999.0,
        trigger_check = 99999.0,
        no_stumble_check = 99999.0,
        time_waist = 99999.0,
        start_gech_time = 99999.0,
        gech_check_time = 99999.0,
        first_wave_time = 99999.0,
        second_wave_time = 99999.0,
        next_wave_time = 99999.0,
        gech1_there_time = 99999.0,
        gech2_there_time = 99999.0,
        gech3_there_time = 99999.0,
        new_aip_time = 99999.0,
        fresh_meat_time = 99999.0,
        fighter_message_time = 99999.0,
        player_nosey_time = 99999.0,
        pull_out_message = 99999.0,
        base_check = 99999.0,
        cerb_check = 99999.0,
        next_second = 99999.0,
        next_second2 = 99999.0,
        -- Original Handle save fields, including dormant cut-content state.
        user = nil,
        death_scrap = nil,
        death_scrap2 = nil,
        death_scrap3 = nil,
        nav1 = nil,
        nav2 = nil,
        nav3 = nil,
        nav4 = nil,
        nav5 = nil,
        ccagech1 = nil,
        ccagech2 = nil,
        ccagech3 = nil,
        colorado = nil,
        drop = nil,
        ccarecycle = nil,
        ccamuf = nil,
        ccaarmor = nil,
        gech_trigger2 = nil,
        gech_trigger3 = nil,
        nsdfrecycle = nil,
        nsdfmuf = nil,
        attack_geys = nil,
        ccarecycle_geyser = nil,
        stop_geyser1 = nil,
        stop_geyser2 = nil,
        stop_geyser3 = nil,
        svpatrol1_1 = nil,
        svpatrol1_2 = nil,
        svpatrol1_3 = nil,
        svpatrol2_1 = nil,
        svpatrol2_2 = nil,
        svpatrol2_3 = nil,
        cannon_fodder1 = nil,
        cannon_fodder2 = nil,
        cannon_fodder3 = nil,
        ccaapc = nil,
        guntower1 = nil,
        guntower2 = nil,
        relic1 = nil,
        relic2 = nil,
        main_relic = nil,
        -- Original int save fields, including dormant cut-content state.
        units1 = 0,
        units2 = 0,
    }
end

ResetState()

local function Setup()


    --[=[

Here's where you set the values at the start.  

]=]

    M.units1 = 0.0
    M.units2 = 0.0

    M.start_done = false
    M.gech_found = false
    M.gech_found1 = false
    M.gech_found2 = false
    M.base_dead = false
    M.player_dead = false
    M.unit_spawn = false
    M.gech_at_nav = false
    M.gech_at_nav2 = false
    M.gech_at_nav3 = false
    M.followup_message = false
    M.player_warned_ofgech = false
    M.colorado_under_attack = false
    M.colorado_destroyed = false
    M.colorado_message2 = false
    M.colorado_message3 = false
    M.colorado_message4 = false
    M.second_gech_warning = false
    M.bad_news = false
    M.run_into_other_gech = false
    M.too_close_message =false
    M.base_exposed = false
    M.bump_into_gech = false
    M.ccarecycle_spawned = false
    M.gech_started = false
    M.gech3_move = false
    M.first_wave = false
    M.second_wave = false
    M.next_wave = false
    M.gech1_at_base = false
    M.gech2_at_base = false
    M.gech3_at_base = false
    M.fresh_meat = false
    M.fighter_message = false
    M.gech1_blossom = false
    M.gech2_blossom = false
    M.gech3_blossom = false
    M.apc_attack = false
    M.game_over = false
    M.base_set = false
    M.cerb_found = false
    M.relic_message = false
    M.kill_colorado = false
    M.gen_message = false


    M.followup_message_time = 99999.0
    M.gech_warning_message = 99999.0
    M.colorado_message2_time = 99999.0
    M.colorado_message3_time = 99999.0
    M.colorado_message4_time = 99999.0
    M.bad_news_time = 99999.0
    M.remove_nav5_time = 99999.0
    M.gech_spawn_time = 99999.0
    M.gech_check = 99999.0
    M.gech_check2 = 99999.0
    M.stumble2_check = 99999.0
    M.stumble1_check = 99999.0
    M.trigger_check = 99999.0
    M.no_stumble_check = 99999.0
    M.time_waist = 99999.0
    M.start_gech_time = 99999.0
    M.gech_check_time = 10.0
    M.first_wave_time = 99999.0
    M.second_wave_time = 99999.0
    M.next_wave_time = 99999.0
    M.gech1_there_time = 99999.0
    M.gech2_there_time = 99999.0
    M.gech3_there_time = 99999.0
    M.new_aip_time = 99999.0
    M.fresh_meat_time = 99999.0
    M.fighter_message_time = 200.0
    M.player_nosey_time = 45.0
    M.pull_out_message = 99999.0
    M.base_check = 99999.0
    M.cerb_check = 30.0
    M.next_second = 99999.0
    M.next_second2 = 99999.0

    M.death_scrap = GetHandle("death_scrap")
    M.death_scrap2 = GetHandle("death_scrap2")
    M.death_scrap3 = GetHandle("death_scrap3")
    M.nsdfrecycle = GetHandle("avrecycle")
    M.ccarecycle = GetHandle("svrecycle")
    M.ccamuf = GetHandle("svmuf")
    M.ccagech1 = GetHandle("sovgech1")
    M.ccagech2 = GetHandle("sovgech2")
    M.nav1 = GetHandle("cam1")
    M.nav4 = GetHandle("cam2")
    M.nav5 = GetHandle("cam5")
    M.gech_trigger2 = GetHandle("giez_spawn2")
    M.gech_trigger3 = GetHandle("giez_spawn3")
    M.colorado = GetHandle("colorado")
    -- M.drop = GetHandle("dropoff57_dropoff")
    M.attack_geys = GetHandle("attack_geyser")
    M.ccarecycle_geyser = GetHandle("ccarecycle_geyser")
    M.stop_geyser1 = GetHandle("stop_geyser1")
    M.stop_geyser2 = GetHandle("stop_geyser2")
    M.stop_geyser3 = GetHandle("stop_geyser3")
    M.svpatrol1_1 = GetHandle("svpatrol1_1")
    M.svpatrol1_2 = GetHandle("svpatrol1_2")
    M.svpatrol1_3 = GetHandle("svpatrol1_3")
    M.svpatrol2_1 = GetHandle("svpatrol2_1")
    M.svpatrol2_2 = GetHandle("svpatrol2_2")
    M.svpatrol2_3 = GetHandle("svpatrol2_3")
    M.relic1 = GetHandle("hbblde1_i76building")
    M.relic2 = GetHandle("hbbldf1_i76building")
    M.main_relic = GetHandle("hbcerb1_i76building")
    M.nsdfmuf = nil
    M.ccaapc = nil
    M.guntower1 = nil
    M.guntower2 = nil
    M.ccagech3 = nil
end

function AddObject(h)

    if ((M.nsdfmuf == nil) and (IsOdf(h,"avmu8"))) then
        M.nsdfmuf = h
    else
        if ((M.ccaapc == nil) and (IsOdf(h,"svapc"))) then
            -- Source typo: nsdfmuf = h; the svapc belongs in ccaapc.
            M.ccaapc = h
        else
            if ((M.guntower1 == nil) and (IsOdf(h,"abtowe"))) then
                M.guntower1 = h
            else
                if ((M.guntower2 == nil) and (IsOdf(h,"abtowe"))) then
                    -- Source typo: guntower1 = h; this is the second tower slot.
                    M.guntower2 = h
                end
            end
        end
    end
end

function Start()
    SetAIControl(2, true)
    Setup()
    -- C++ Setup precedes AiMission::Load and its AddObject notifications.
    -- Redux may create map objects before Start; recover the four tracked slots
    -- after Setup so those earlier notifications cannot be discarded.
    for h in AllObjects() do
        AddObject(h)
    end
end

function Update(dt)


    --[=[

Here is where you put what happens every frame.  

]=]

    M.user = GetPlayerHandle() --assigns the player a handle every frame

    if (not M.start_done) then
        AudioMessage("misn0800.wav") --starts opeing V.O.
        ClearObjectives()
        AddObjective("misn0800.otf", "white")
        AddObjective("misn0801.otf", "white")
        -- SetPilot(1, 30)
        SetScrap(1,30)
        Defend(M.ccagech1)
        Defend(M.ccagech2)
        M.start_gech_time = GetTime() + 329.0 -- starts the gechs towards the base
        M.gech_spawn_time = GetTime() + 280.0 -- starts attack on colorado
        M.trigger_check = GetTime() + 285.0
        M.fresh_meat_time = 100.0 -- build more units to send after player
        M.gech_check = GetTime() + 61.0 -- searches to see if the player encounters a gech
        M.first_wave_time = GetTime() + 20.0 -- starts the first wave of fighters
        SetWeaponMask(M.ccagech1, 1)
        SetWeaponMask(M.ccagech2, 1)
        if (M.nav1~=nil) then SetObjectiveName(M.nav1, "Drop Zone") end
        if (M.nav5~=nil) then SetObjectiveName(M.nav5, "Colorado Base") end
        if (M.nav4~=nil) then SetObjectiveName(M.nav4, "CCA Main Base") end
        M.base_check = GetTime() + 5.0
        M.start_done = true
    end

    if ((M.start_done) and (M.start_gech_time < GetTime()) and (not M.gech_started)) then --sets gechs into motion
        Goto(M.ccagech1, "gech_path1")
        Goto(M.ccagech2, "gech_path2")
        M.gech_started = true
    end
    -- this sends the first soviets into the user's base
    if ((M.first_wave_time < GetTime()) and (not M.first_wave)) then
        Goto(M.svpatrol2_2, M.nsdfrecycle)
        Goto(M.svpatrol2_3, M.nsdfrecycle)
        M.first_wave = true
    end

    if ((M.fresh_meat_time < GetTime()) and (not M.colorado_under_attack) and (not M.fresh_meat)) then
        M.cannon_fodder1 = BuildObject("svfigh", 2, M.ccarecycle)
        M.cannon_fodder2 = BuildObject("svfigh", 2, M.ccarecycle)
        M.cannon_fodder3 = BuildObject("svfigh", 2, M.ccarecycle)
        Goto(M.cannon_fodder1, "gech_path2")
        Goto(M.cannon_fodder2, "gech_path2")
        Goto(M.cannon_fodder3, "gech_path2")
        M.fresh_meat = true
    end

    if ((M.fighter_message_time < GetTime()) and (not M.colorado_under_attack) and (not M.fighter_message)) then
        AudioMessage("misn0817.wav") -- colorado: we're experiencing a lot of fighters - they know we're here - wonder what the main forces is waiting for
        M.fighter_message = true
    end


    -- colorado gets attacked by gech //////////////////////////////////////////////////////////////////////////

    if ((M.gech_spawn_time < GetTime()) and (not M.colorado_under_attack)) then --gech attacks colorado
        M.gech_spawn_time = GetTime() + 10.0

        if (GetDistance(M.user, M.nav5) > 400.0) then
            M.svpatrol2_2 = BuildObject("svfigh", 2, M.ccarecycle)
            M.svpatrol2_2 = BuildObject("svltnk", 2, M.ccarecycle)
            M.ccagech3 = BuildObject("svwalk", 2, "gech_spawn")
            SetWeaponMask(M.ccagech3, 1)
            Attack(M.ccagech3, M.colorado, 1)
            AudioMessage("misn0801.wav") -- player gets message that colorado is encountering hostiles "standby"
            M.colorado_message2_time = GetTime() + 10.0

            if (IsAlive(M.svpatrol2_1)) then
                Goto(M.svpatrol2_1, M.nav1)
            end
            if (IsAlive(M.svpatrol2_2)) then
                Goto(M.svpatrol2_2, M.nav1)
            end
            if (IsAlive(M.svpatrol2_3)) then
                Goto(M.svpatrol2_3, M.nav1)
            end

            M.colorado_under_attack = true
        end
    end

    -- this is what happens if the player tries to get to the colorado before the attack - it speeds things up
    if ((M.player_nosey_time < GetTime()) and (not M.colorado_under_attack)) then
        M.player_nosey_time = GetTime() + 32.0

        if (GetDistance(M.user, M.nav5) < 700.0) then
            M.gech_spawn_time = GetTime() + 10.0

            if (IsAlive(M.svpatrol1_1)) then
                Attack(M.svpatrol1_1, M.user)
            end
            if (IsAlive(M.svpatrol1_2)) then
                Attack(M.svpatrol1_2, M.user)
            end
            if (IsAlive(M.svpatrol1_3)) then
                Attack(M.svpatrol1_3, M.user)
            end
            if (IsAlive(M.svpatrol2_1)) then
                Attack(M.svpatrol2_1, M.nsdfrecycle)
            end
            if (IsAlive(M.svpatrol2_2)) then
                Attack(M.svpatrol2_2, M.nsdfrecycle)
            end
            if (IsAlive(M.svpatrol2_3)) then
                Attack(M.svpatrol2_3, M.nsdfrecycle)
            end
        end
    end

    if ((M.colorado_under_attack) and (M.colorado_message2_time < GetTime()) and (not M.colorado_message2)) then

        AudioMessage("misn0803.wav") --second message from colorado
        M.colorado_message3_time = GetTime() + 7.0
        M.colorado_message2 = true
    end

    if ((M.colorado_message2) and (M.colorado_message3_time < GetTime()) and (not M.colorado_message3)) then

        AudioMessage("misn0802.wav") --third message from colorado
        AudioMessage("misn0804.wav") --final message from colorado
        M.colorado_message4_time = GetTime() + 10.0
        M.colorado_message3 = true
    end

    if ((M.colorado_message4_time < GetTime()) and (not M.kill_colorado)) then
        M.kill_colorado = true
    end

    if ((IsAlive(M.colorado)) and (not M.kill_colorado)) then
        if (GetTime()>M.next_second) then
            AddHealth(M.colorado, 500.0)
            M.next_second = GetTime() + 1.0
        end
    end

    if ((M.colorado_message3) and (M.kill_colorado) and (not M.colorado_message4)) then
        if (IsAlive(M.colorado)) then
            Damage(M.colorado, 20000)
        end
        M.remove_nav5_time = GetTime() + 15.0
        M.colorado_message4 = true
    end

    if ((M.colorado_message4) and (M.remove_nav5_time < GetTime()) and (not M.colorado_destroyed)) then
        -- RemoveObject (M.colorado)
        RemoveObject (M.nav5)
        -- RemoveObject (M.drop)
        M.bad_news_time = GetTime() + 5.0
        M.colorado_destroyed = true
    end

    if ((M.colorado_destroyed) and (not M.bad_news) and (M.bad_news_time < GetTime())) then
        AudioMessage("misn0805.wav") --Corbett give player news of colorado fate
        M.bad_news_time = GetTime() + 30.0
        M.bad_news = true
    end

    if ((M.bad_news) and (M.bad_news_time < GetTime()) and (not M.gen_message)) then
        AudioMessage("misn0810.wav") --Gen Collins give player news of colorado fate
        M.gen_message = true
    end

    -- end soviet attack on colorado ///////////////////////////////////////////////////////////////////////////////


    -- this is going to give the soviets a recycler and start them attacking

    if ((M.bad_news) and (not M.ccarecycle_spawned)) then
        SetAIP("misn08.aip")
        SetScrap(2, 40)
        SetPilot(2, 40)
        M.new_aip_time = GetTime() + 420.0
        if (IsAlive(M.ccagech3)) then
            Goto(M.ccagech3, "gech_path2")
        end

        if (IsAlive(M.svpatrol1_1)) then
            Goto(M.svpatrol1_1, "cam3_spawn")
        end
        if (IsAlive(M.svpatrol1_2)) then
            Goto(M.svpatrol1_2, "cam3_spawn")
        end
        if (IsAlive(M.svpatrol1_3)) then
            Goto(M.svpatrol1_3, "cam3_spawn")
        end

        M.ccarecycle_spawned = true
    end

    -- this is sending the third gech down the gech path when it gets to a certain point

    --[=[
    if ((M.ccarecycle_spawned) and (not M.gech3_move) and (M.gech_check_time < GetTime())) then
        if (GetDistance(M.ccagech3, M.stop_geyser2) < 30.0) then
            Goto(M.ccagech3, "gech_path2")
            M.gech3_there_time = GetTime() + 97.0
            M.gech3_move = true
        end
    end

]=]


    -- this is what happens when the player encounters the gech before it reaches the nav point ////////////////////

    if ((M.gech_check < GetTime()) and (not M.gech_found) and (not M.gech_at_nav)) then
        M.gech_check = GetTime() + 6.0

        if ((GetDistance(M.user,M.ccagech1) < 400.0) and (not M.gech_found1) and (not M.gech_found) and (not M.gech_at_nav)) then --if player reaches gech before gech reaches nav
            AudioMessage("misn0806.wav") -- "we're picking up something big on your radar, you may want to check it out"
            M.followup_message_time = GetTime() + 20.0 -- setting up follow up message about cca gech
            M.stumble2_check = GetTime() + 10.0
            M.no_stumble_check = GetTime() + 13.0
            M.gech1_there_time = 100.0
            M.gech2_there_time = 105.0
            M.gech_found1 = true
            M.gech_found = true
        end

        if ((GetDistance(M.user,M.ccagech2) < 400.0) and (not M.gech_found) and (not M.gech_found2) and (not M.gech_at_nav)) then --if player reaches gech before gech reaches nav
            AudioMessage("misn0806.wav") -- "we're picking up something big on your radar, you may want to check it out"
            M.followup_message_time = GetTime() + 5.0 -- setting up follow up message about cca gech
            M.stumble2_check = GetTime() + 60.0
            M.no_stumble_check = GetTime() + 13.0
            M.gech1_there_time = 100.0
            M.gech2_there_time = 105.0
            M.gech_found2 = true
            M.gech_found = true
        end
    end

    if ((M.gech_found) and (M.followup_message_time < GetTime()) and (not M.followup_message)) then
        AudioMessage("misn0807.wav") -- "what the hell is that thing - approach with caution!"
        M.followup_message = true
    end


    if ((M.base_check < GetTime()) and (not M.base_set)) then
        M.base_check = GetTime() + 2.0

        if (IsAlive(M.nsdfmuf)) then
            local test = IsDeployed(M.nsdfmuf)

            if (test) then
                ClearObjectives()
                AddObjective("misn0800.otf", "green")
                AddObjective("misn0801.otf", "white")
                M.base_set = true
            end
        end
    end



    -- this is what happens when the player goes and sees the gech after the first nav is dropped

    if ((M.gech_found) and (M.stumble2_check < GetTime()) and (not M.second_gech_warning) and (not M.run_into_other_gech)) then
        M.stumble2_check = GetTime() + 21.0

        if ((M.gech_found1) and (GetDistance(M.user,M.ccagech2) < 100.0) and (not M.run_into_other_gech)) then
            AudioMessage("misn0813.wav") --Oh no! Looks like you've found another one!
            M.run_into_other_gech = true
        end

        if ((M.gech_found2) and (GetDistance(M.user,M.ccagech1) < 100.0) and (not M.run_into_other_gech)) then
            AudioMessage("misn0813.wav") --Oh no! Looks like you've found another one!
            M.run_into_other_gech = true
        end
    end

    -- this is when the player runs into one gech but the other gech gets half-way to base before being discovered

    if ((M.gech_found) and (M.no_stumble_check < GetTime()) and (not M.run_into_other_gech) and (not M.second_gech_warning)) then
        M.no_stumble_check = GetTime() + 9.0

        if ((M.gech_found1) and (GetDistance(M.gech_trigger2, M.ccagech2) < 100.0) and (not M.second_gech_warning)) then
            AudioMessage("misn0815.wav") --V.O. looks like we've got another one coming out of the west
            M.nav2 = BuildObject ("apcamr", 1, "cam2_spawn") -- builds camera near gech
            if (M.nav2~=nil) then SetObjectiveName(M.nav2, "Nav Alpha 1") end
            M.second_gech_warning = true
        end

        if ((M.gech_found2) and (GetDistance(M.gech_trigger3,M.ccagech1) < 100.0) and (not M.second_gech_warning)) then
            AudioMessage("misn0814.wav") --V.O. warns player of second gech
            M.nav3 = BuildObject ("apcamr", 1, "cam3_spawn") -- builds camera near gech
            if (M.nav3~=nil) then SetObjectiveName(M.nav3, "Nav Alpha 2") end
            M.second_gech_warning = true
        end
    end


    -- the following occurs when the approaching gechs get half-way to the player's base

    if ((M.colorado_under_attack) and (M.trigger_check < GetTime()) and (not M.gech_at_nav) and (not M.gech_found)) then
        M.trigger_check = GetTime() + 19.0

        if ((not M.gech_found) and (GetDistance(M.gech_trigger2, M.ccagech2) < 100.0) and (not M.gech_at_nav)) then --if gech reaches nav before player reaches gech
            AudioMessage("misn0809.wav") -- "We've detected something strange on approach from the east - standby"
            M.gech_warning_message = GetTime() + 20.0
            M.gech1_there_time = 100.0
            M.gech2_there_time = 105.0
            M.gech_at_nav = true
            M.gech_at_nav2 = true
        end

        if ((not M.gech_found) and (GetDistance(M.gech_trigger3,M.ccagech1) < 100.0) and (not M.gech_at_nav)) then --if gech reaches nav before player reaches gech
            AudioMessage("misn0808.wav") -- "We've detected something strange on approach from the west - standby"
            M.gech_warning_message = GetTime() + 20.0
            M.gech1_there_time = 100.0
            M.gech2_there_time = 105.0
            M.gech_at_nav = true
            M.gech_at_nav3 = true
        end
    end

    if ((M.gech_at_nav2) and (M.gech_warning_message < GetTime()) and (not M.player_warned_ofgech)) then --if player ignores gech_at_nav message
        AudioMessage("misn0814.wav") -- Check it out - we're dropping a nav camera there now
        M.nav2 = BuildObject ("apcamr", 1, "cam2_spawn") -- builds camera near gech
        if (M.nav2~=nil) then SetObjectiveName(M.nav2, "Nav Alpha 1") end
        M.time_waist = GetTime() + 14.0
        M.stumble1_check = GetTime() + 100.0
        M.player_warned_ofgech = true
    end

    if ((M.gech_at_nav3) and (M.gech_warning_message < GetTime()) and (not M.player_warned_ofgech)) then --if player ignores gech_at_nav message
        AudioMessage("misn0815.wav") -- Check it out - we're dropping a nav camera there now
        M.nav3 = BuildObject ("apcamr", 1, "cam3_spawn") -- builds camera near gech
        if (M.nav3~=nil) then SetObjectiveName(M.nav3, "Nav Alpha 2") end
        M.time_waist = GetTime() + 14.0
        M.stumble1_check = GetTime() + 100.0
        M.player_warned_ofgech = true
    end

    -- this is the player getting warned of the second gech if he hasn't gone to see the first one yet //////////////////

    if ((M.player_warned_ofgech) and (M.time_waist < GetTime()) and (not M.second_gech_warning) and (not M.bump_into_gech)) then
        M.time_waist = GetTime() + 14.0

        if ((M.gech_at_nav2) and (GetDistance(M.gech_trigger3,M.ccagech1) < 75.0) and (not M.second_gech_warning)) then --second gech found
            AudioMessage("misn0812.wav") --looks like we've got another one coming out of the east
            M.nav3 = BuildObject ("apcamr", 1, "cam3_spawn") -- builds camera near gech
            if (M.nav3~=nil) then SetObjectiveName(M.nav3, "Nav Alpha 2") end
            M.second_gech_warning = true
        end

        if ((M.gech_at_nav3) and (GetDistance(M.gech_trigger2, M.ccagech2) < 75.0) and (not M.second_gech_warning)) then --second gech found
            AudioMessage("misn0811.wav") --looks like we've got another one coming out of the west
            M.nav2 = BuildObject ("apcamr", 1, "cam2_spawn") -- builds camera near gech
            if (M.nav2~=nil) then SetObjectiveName(M.nav2, "Nav Alpha 1") end
            M.second_gech_warning = true
        end
    end

    -- this is what happens when the player goes and sees the gech after the first nav is dropped

    if ((M.player_warned_ofgech) and (M.stumble1_check < GetTime()) and (not M.second_gech_warning) and (not M.bump_into_gech)) then
        M.stumble1_check = GetTime() + 23.0

        if ((M.gech_at_nav2) and (GetDistance(M.user,M.ccagech1) < 100.0) and (not M.bump_into_gech)) then
            AudioMessage("misn0813.wav") --Oh no! Looks like you've found another one!
            M.bump_into_gech = true
        end

        if ((M.gech_at_nav3) and (GetDistance(M.user,M.ccagech2) < 100.0) and (not M.bump_into_gech)) then
            AudioMessage("misn0813.wav") --Oh no! Looks like you've found another one!
            M.bump_into_gech = true
        end
    end


    -- this makes the gechs attack the player's base when they get close enough

    if ((M.gech_found) or (M.gech_at_nav)) then
        if ((M.gech1_there_time < GetTime()) and (not M.gech1_at_base)) then
            M.gech1_there_time = GetTime() + 30.0

            if ((IsAlive(M.ccagech1)) and (GetDistance(M.ccagech1, M.stop_geyser3) < 100.0)) then
                if (IsAlive(M.nsdfrecycle)) then
                    Attack(M.ccagech1, M.nsdfrecycle)
                    if (M.gech1_blossom) then
                        SetWeaponMask(M.ccagech1, 5)
                    end
                    M.gech1_at_base = true
                else
                    if (IsAlive(M.nsdfmuf)) then
                        Attack(M.ccagech1, M.nsdfmuf)
                        if (M.gech1_blossom) then
                            SetWeaponMask(M.ccagech1, 5)
                        end
                        M.gech1_at_base = true
                    end
                end
            end
        end

        if ((M.gech2_there_time < GetTime()) and (not M.gech2_at_base)) then
            M.gech2_there_time = GetTime() + 30.0

            if ((IsAlive(M.ccagech2)) and (GetDistance(M.ccagech2, M.stop_geyser3) < 100.0)) then
                if (IsAlive(M.nsdfrecycle)) then
                    Attack(M.ccagech2, M.nsdfrecycle)
                    if (M.gech2_blossom) then
                        SetWeaponMask(M.ccagech2, 5)
                    end
                    M.gech2_at_base = true
                else
                    if (IsAlive(M.nsdfmuf)) then
                        Attack(M.ccagech2, M.nsdfmuf)
                        if (M.gech2_blossom) then
                            SetWeaponMask(M.ccagech2, 5)
                        end
                        M.gech2_at_base = true
                    end
                end
            end
        end

        if ((M.gech3_there_time < GetTime()) and (not M.gech3_at_base)) then
            M.gech3_there_time = GetTime() + 30.0

            if ((IsAlive(M.ccagech3)) and (GetDistance(M.ccagech3, M.stop_geyser3) < 100.0)) then
                if (IsAlive(M.nsdfrecycle)) then
                    Attack(M.ccagech3, M.nsdfrecycle)
                    if (M.gech3_blossom) then
                        SetWeaponMask(M.ccagech3, 5)
                    end
                    M.gech3_at_base = true
                else
                    if (IsAlive(M.nsdfmuf)) then
                        Attack(M.ccagech3, M.nsdfmuf)
                        if (M.gech3_blossom) then
                            SetWeaponMask(M.ccagech3, 5)
                        end
                        M.gech3_at_base = true
                    end
                end
            end
        end

    end

    -- now I'm loading the new attack aips if the correct amount of time has passed

    if (M.new_aip_time < GetTime()) then
        M.new_aip_time = GetTime() + 420.0

        M.units1 = CountUnitsNearObject(M.stop_geyser2, 5000.0, 1, "avfigh")
        M.units2 = CountUnitsNearObject(M.stop_geyser2, 5000.0, 1, "avtank")

        if (M.units1 > M.units2) then
            SetAIP("misn08b.aip")
        else
            SetAIP("misn08a.aip")
        end
    end

    -- this is apc code

    if ((IsAlive(M.ccaapc)) and (not M.apc_attack)) then
        if (IsAlive(M.guntower1)) then
            Attack(M.ccaapc, M.guntower1)
        else
            if (IsAlive(M.guntower2)) then
                Attack(M.ccaapc, M.guntower2)
            else
                if (IsAlive(M.nsdfmuf)) then
                    Attack(M.ccaapc, M.nsdfmuf)
                else
                    if (IsAlive(M.nsdfrecycle)) then
                        Attack(M.ccaapc, M.nsdfrecycle)
                    end
                end
            end
        end

        M.apc_attack = true
    end

    if ((M.apc_attack) and (not IsAlive(M.ccaapc))) then
        M.apc_attack = false
    end


    -- This is another radar comment when the player gets extrememly close to the gech

    --[=[
    if ((M.gech_found) and (not M.too_close_message) or (M.gech_at_nav) and (not M.too_close_message)) then
        if ((GetDistance(M.user, M.ccagech1) < 75.0) and (not M.too_close_message)) then
            AudioMessage("misn0816.wav") -- pull out!! what the hell is that!
            M.too_close_message = true
        end

        if ((GetDistance(M.user, M.ccagech2) < 75.0) and (not M.too_close_message)) then
            AudioMessage("misn0816.wav") -- pull out!! what the hell is that!
            M.too_close_message = true
        end
    end
]=]


    if ((M.pull_out_message < GetTime()) and (not M.too_close_message)) then
        AudioMessage("misn0816.wav") -- pull out!! what the hell is that!
        M.too_close_message = true
    end


    -- this will make the gechs use the popper

    if ((IsAlive(M.ccagech1)) and (not M.gech1_blossom) and (GetHealth(M.ccagech1) < 0.25)) then
        SetWeaponMask(M.ccagech1, 4)
        M.pull_out_message = GetTime() + 6.0
        M.gech1_blossom = true
    end

    if ((IsAlive(M.ccagech2)) and (not M.gech2_blossom) and (GetHealth(M.ccagech2) < 0.25)) then
        SetWeaponMask(M.ccagech2, 4)
        M.pull_out_message = GetTime() + 6.0
        M.gech2_blossom = true
    end

    if ((IsAlive(M.ccagech3)) and (not M.gech3_blossom) and (GetHealth(M.ccagech3) < 0.25)) then
        SetWeaponMask(M.ccagech3, 4)
        M.pull_out_message = GetTime() + 6.0
        M.gech3_blossom = true
    end

    -- this is the relic code

    if ((not M.cerb_found) and (not M.relic_message) and ((IsInfo("hbblde") == true) or (IsInfo("hbbldf") == true))) then
        if (M.base_dead) then
            AudioMessage("misn0821.wav") -- that's not it, the ruins will be much larger
            M.relic_message = true
        else
            AudioMessage("misn0822.wav") -- this area is crawling with relics recon as many as possible
            M.relic_message = true
        end
    end

    if ((not M.cerb_found) and (M.cerb_check < GetTime())) then
        M.cerb_check = GetTime() + 3.0

        if (GetDistance(M.user, M.main_relic) < 70.0) then
            if (M.base_dead) then
                AudioMessage("misn0818.wav") -- well done
                AudioMessage("misn0826.wav")
                SucceedMission(GetTime() + 30.0, "misn08w1.des") --well done
                M.cerb_found = true
            else
                AudioMessage("misn0819.wav") -- this must be how they built gechs - find base
                M.cerb_found = true
            end
        end
    end

    if (IsAlive(M.main_relic)) then
        if (GetTime()>M.next_second2) then
            AddHealth(M.main_relic, 500.0)
            M.next_second2 = GetTime() + 1.0
        end
    end


    -- win/loose conditions /////////////////////////////

    if ((not IsAlive(M.ccarecycle)) and (not IsAlive(M.ccamuf)) and (not M.base_dead)) then
        if (M.cerb_found) then
            AudioMessage("misn0818.wav")
            AudioMessage("misn0826.wav")
            SucceedMission(GetTime() + 30.0, "misn08w1.des") --well done
            M.base_dead = true
        else
            ClearObjectives()
            AddObjective("misn0801.otf", "green")
            AddObjective("misn0802.otf", "white")
            AudioMessage("misn0820.wav") -- find cerbeus
            SetObjectiveOn(M.main_relic)
            SetObjectiveName(M.main_relic, "Relic Site")
            M.base_dead = true
        end
    end

    if ((not IsAlive(M.nsdfrecycle)) and (not M.game_over)) then
        AudioMessage("misn0421.wav")
        FailMission(GetTime() + 15.0, "misn08f1.des") --lost recycler
        M.game_over = true
    end
end

-- Redux serializes this table's primitive/game values, including handles.
-- Load must not rerun Setup or replay opening events. LuaMission handles remapping.
function Save()
    return M
end

function Load(saved)
    assert(type(saved) == "table", "misn08: missing mission save state")
    M = saved
end

-- Original source archive, LF-normalized, otherwise verbatim. Keep ALL comments,
-- including disabled C++ and engine serialization boilerplate, for reconstruction.
--[==[
#include "GameCommon.h"
#include "..\fun3d\Factory.h"
#include "..\fun3d\AiMission.h"
#include "..\fun3d\PowerUp.h"
#include "..\fun3d\ScriptUtils.h"


/*
Misn08Mission Event
*/

class Misn08Mission : public AiMission {
	DECLARE_RTIME(Misn08Mission)
public:
	Misn08Mission(void);
	~Misn08Mission();

	virtual bool Load(file fp);
	virtual bool PostLoad(void);
	virtual bool Save(file fp);

	virtual void Update(void);

	virtual void AddObject(GameObject *gameObj);

private:
	void Setup(void);
	void AddObject(Handle h);
	void Execute(void);

	// bools
	union {
		struct {
			bool
				start_done, 
				gech_found, gech_found1, gech_found2, 
				base_dead, 
				player_dead,
				unit_spawn,
				gech_at_nav, gech_at_nav2, gech_at_nav3,
				player_warned_ofgech,
				colorado_under_attack,
				colorado_destroyed,
				followup_message,
				colorado_message2,
				colorado_message3,
				colorado_message4,
				second_gech_warning,
				run_into_other_gech,
				too_close_message,
				bad_news,
				base_exposed,
				bump_into_gech,
				ccarecycle_spawned,
				gech_started,
				gech3_move,
				first_wave, second_wave, next_wave,
				gech1_at_base, gech2_at_base, gech3_at_base,
				gech1_blossom, gech2_blossom, gech3_blossom,
				fresh_meat, fighter_message,
				apc_attack, base_set, game_over, cerb_found, relic_message,
				kill_colorado, gen_message,
				b_last;
		};
		bool b_array[44];
	};

	// floats
	union {
		struct {
			float
				unit_spawn_time,
				followup_message_time,
				colorado_message2_time, colorado_message3_time, colorado_message4_time,
				bad_news_time,
				gech_warning_message,
				remove_nav5_time,
				gech_spawn_time,
				gech_check, gech_check2,
				stumble1_check, stumble2_check, trigger_check, no_stumble_check,
				time_waist,
				start_gech_time,
				gech_check_time,
				first_wave_time,
				second_wave_time,
				next_wave_time,
				gech1_there_time, gech2_there_time, gech3_there_time,
				new_aip_time,
				fresh_meat_time,
				fighter_message_time, player_nosey_time,
				pull_out_message, base_check, cerb_check,
				next_second, next_second2,
				f_last;
		};
		float f_array[33];
	};

	// handles
	union {
		struct {
			Handle
				user, death_scrap, death_scrap2, death_scrap3,
				nav1, nav2, nav3, nav4, nav5,
				ccagech1, ccagech2, ccagech3,
				colorado, drop,
				ccarecycle, ccamuf, ccaarmor,
				gech_trigger2, gech_trigger3,
				nsdfrecycle, nsdfmuf,
				attack_geys,
				ccarecycle_geyser,
				stop_geyser1, stop_geyser2, stop_geyser3,
				svpatrol1_1, svpatrol1_2, svpatrol1_3,
				svpatrol2_1, svpatrol2_2, svpatrol2_3,
				cannon_fodder1, cannon_fodder2, cannon_fodder3,
				ccaapc, guntower1, guntower2, relic1, relic2, main_relic,
				h_last;
		};
		Handle h_array[41];
	};

	// integers
	union {
		struct {
			int
				units1, units2,
				i_last;
		};
		int i_array[2];
	};
};

void Misn08Mission::Setup(void)
{
/*
Here's where you set the values at the start.  
*/
	units1 = 0.0f;
	units2 = 0.0f;
	
	start_done = false;
	gech_found = false;
	gech_found1 = false;
	gech_found2 = false;
	base_dead = false;
	player_dead = false;
	unit_spawn = false;
	gech_at_nav = false;
	gech_at_nav2 = false;
	gech_at_nav3 = false;
	followup_message = false;
	player_warned_ofgech = false;
	colorado_under_attack = false;
	colorado_destroyed = false;
	colorado_message2 = false;
	colorado_message3 = false;
	colorado_message4 = false;
	second_gech_warning = false;
	bad_news = false;
	run_into_other_gech = false;
	too_close_message =false;
	base_exposed = false;
	bump_into_gech = false;
	ccarecycle_spawned = false;
	gech_started = false;
	gech3_move = false;
	first_wave = false;
	second_wave = false;
	next_wave = false;
	gech1_at_base = false;
	gech2_at_base = false;
	gech3_at_base = false;
	fresh_meat = false;
	fighter_message = false;
	gech1_blossom = false;
	gech2_blossom = false;
	gech3_blossom = false;
	apc_attack = false;
	game_over = false;
	base_set = false;
	cerb_found = false;
	relic_message = false;
	kill_colorado = false;
	gen_message = false;


	followup_message_time = 99999.0f;
	gech_warning_message = 99999.0f;
	colorado_message2_time = 99999.0f;
	colorado_message3_time = 99999.0f;
	colorado_message4_time = 99999.0f;
	bad_news_time = 99999.0f;
	remove_nav5_time = 99999.0f;
	gech_spawn_time = 99999.0f;
	gech_check = 99999.0f;
	gech_check2 = 99999.0f;
	stumble2_check = 99999.0f;
	stumble1_check = 99999.0f;
	trigger_check = 99999.0f;
	no_stumble_check = 99999.0f;
	time_waist = 99999.0f;
	start_gech_time = 99999.0f;
	gech_check_time = 10.0f;
	first_wave_time = 99999.0f;
	second_wave_time = 99999.0f;
	next_wave_time = 99999.0f;
	gech1_there_time = 99999.0f;
	gech2_there_time = 99999.0f;
	gech3_there_time = 99999.0f;
	new_aip_time = 99999.0f;
	fresh_meat_time = 99999.0f;
	fighter_message_time = 200.0f;
	player_nosey_time = 45.0f;
	pull_out_message = 99999.0f;
	base_check = 99999.0f;
	cerb_check = 30.0f;
	next_second = 99999.0f;
	next_second2 = 99999.0f;
	
	death_scrap = GetHandle("death_scrap");
	death_scrap2 = GetHandle("death_scrap2");
	death_scrap3 = GetHandle("death_scrap3");
	nsdfrecycle = GetHandle("avrecycle");
	ccarecycle = GetHandle("svrecycle");
	ccamuf = GetHandle("svmuf");
	ccagech1 = GetHandle("sovgech1");
	ccagech2 = GetHandle("sovgech2");
	nav1 = GetHandle("cam1");
	nav4 = GetHandle("cam2");
	nav5 = GetHandle("cam5");
	gech_trigger2 = GetHandle("giez_spawn2");
	gech_trigger3 = GetHandle("giez_spawn3");
	colorado = GetHandle("colorado");
//	drop = GetHandle("dropoff57_dropoff");
	attack_geys = GetHandle("attack_geyser");
	ccarecycle_geyser = GetHandle("ccarecycle_geyser");
	stop_geyser1 = GetHandle("stop_geyser1");
	stop_geyser2 = GetHandle("stop_geyser2");
	stop_geyser3 = GetHandle("stop_geyser3");
	svpatrol1_1 = GetHandle("svpatrol1_1");
	svpatrol1_2 = GetHandle("svpatrol1_2");
	svpatrol1_3 = GetHandle("svpatrol1_3");
	svpatrol2_1 = GetHandle("svpatrol2_1");
	svpatrol2_2 = GetHandle("svpatrol2_2");
	svpatrol2_3 = GetHandle("svpatrol2_3");
	relic1 = GetHandle("hbblde1_i76building");
	relic2 = GetHandle("hbbldf1_i76building");
	main_relic = GetHandle("hbcerb1_i76building");
	nsdfmuf = NULL;
	ccaapc = NULL;
	guntower1 = NULL;
	guntower2 = NULL;
	ccagech3 = 0;
}

void Misn08Mission::AddObject(Handle h)
{
	if ((nsdfmuf == NULL) && (IsOdf(h,"avmu8")))
	{
		nsdfmuf = h;
	}
	else
	{
		if ((ccaapc == NULL) && (IsOdf(h,"svapc")))
		{
			nsdfmuf = h;
		}
		else
		{
			if ((guntower1 == NULL) && (IsOdf(h,"abtowe")))
			{
				guntower1 = h;
			}
			else
			{
				if ((guntower2 == NULL) && (IsOdf(h,"abtowe")))
				{
					guntower1 = h;
				}
			}
		}
	}
}

void Misn08Mission::Execute(void)
{
/*
Here is where you put what happens every frame.  
*/
	user = GetPlayerHandle(); //assigns the player a handle every frame

	if (!start_done)
	{
		AudioMessage("misn0800.wav"); //starts opeing V.O.
		ClearObjectives();
		AddObjective("misn0800.otf", WHITE);
		AddObjective("misn0801.otf", WHITE);
//		SetPilot(1, 30);
		SetScrap(1,30);
		Defend(ccagech1);
		Defend(ccagech2);
		start_gech_time = Get_Time() + 329.0f; // starts the gechs towards the base
		gech_spawn_time = Get_Time() + 280.0f; // starts attack on colorado
		trigger_check = Get_Time() + 285.0f;
		fresh_meat_time = 100.0f; // build more units to send after player
		gech_check = Get_Time() + 61.0f; // searches to see if the player encounters a gech
		first_wave_time = Get_Time() + 20.0f; // starts the first wave of fighters
		SetWeaponMask(ccagech1, 1);
		SetWeaponMask(ccagech2, 1);
		if (nav1!=NULL) GameObjectHandle::GetObj(nav1)->SetName("Drop Zone");
		if (nav5!=NULL) GameObjectHandle::GetObj(nav5)->SetName("Colorado Base");
		if (nav4!=NULL) GameObjectHandle::GetObj(nav4)->SetName("CCA Main Base");
		base_check = Get_Time() + 5.0f;
		start_done = true;
	}

	if ((start_done) && (start_gech_time < Get_Time()) && (!gech_started)) //sets gechs into motion
	{
		Goto(ccagech1, "gech_path1"); 
		Goto(ccagech2, "gech_path2");
		gech_started = true;
	}
	// this sends the first soviets into the user's base
	if ((first_wave_time < Get_Time()) && (!first_wave))
	{
		Goto(svpatrol2_2, nsdfrecycle);
		Goto(svpatrol2_3, nsdfrecycle);
		first_wave = true;
	}

	if ((fresh_meat_time < Get_Time()) && (!colorado_under_attack) && (!fresh_meat))
	{
		cannon_fodder1 = BuildObject("svfigh", 2, ccarecycle);
		cannon_fodder2 = BuildObject("svfigh", 2, ccarecycle);
		cannon_fodder3 = BuildObject("svfigh", 2, ccarecycle);
		Goto(cannon_fodder1, "gech_path2");
		Goto(cannon_fodder2, "gech_path2");
		Goto(cannon_fodder3, "gech_path2");
		fresh_meat = true;
	}

	if ((fighter_message_time < Get_Time()) && (!colorado_under_attack) && (!fighter_message))
	{
		AudioMessage("misn0817.wav"); // colorado: we're experiencing a lot of fighters - they know we're here - wonder what the main forces is waiting for
		fighter_message = true;
	}


// colorado gets attacked by gech //////////////////////////////////////////////////////////////////////////

	if ((gech_spawn_time < Get_Time()) && (!colorado_under_attack))//gech attacks colorado
	{
		gech_spawn_time = Get_Time() + 10.0f;

		if (GetDistance(user, nav5) > 400.0f)
		{
			svpatrol2_2 = BuildObject("svfigh", 2, ccarecycle);
			svpatrol2_2 = BuildObject("svltnk", 2, ccarecycle);
			ccagech3 = BuildObject("svwalk", 2, "gech_spawn");
			SetWeaponMask(ccagech3, 1);
			Attack(ccagech3, colorado, 1);
			AudioMessage("misn0801.wav");// player gets message that colorado is encountering hostiles "standby"
			colorado_message2_time = Get_Time() + 10.0f;

			if (IsAlive(svpatrol2_1))
			{
				Goto(svpatrol2_1, nav1);
			}
			if (IsAlive(svpatrol2_2))
			{
				Goto(svpatrol2_2, nav1);
			}
			if (IsAlive(svpatrol2_3))
			{
				Goto(svpatrol2_3, nav1);
			}

			colorado_under_attack = true;
		}
	}
	
	// this is what happens if the player tries to get to the colorado before the attack - it speeds things up
	if ((player_nosey_time < GetTime()) && (!colorado_under_attack))
	{
		player_nosey_time = GetTime() + 32.0f;

		if (GetDistance(user, nav5) < 700.0f)
		{
			gech_spawn_time = Get_Time() + 10.0f;

			if (IsAlive(svpatrol1_1))
			{
				Attack(svpatrol1_1, user);
			}
			if (IsAlive(svpatrol1_2))
			{
				Attack(svpatrol1_2, user);
			}
			if (IsAlive(svpatrol1_3))
			{
				Attack(svpatrol1_3, user);
			}
			if (IsAlive(svpatrol2_1))
			{
				Attack(svpatrol2_1, nsdfrecycle);
			}
			if (IsAlive(svpatrol2_2))
			{
				Attack(svpatrol2_2, nsdfrecycle);
			}
			if (IsAlive(svpatrol2_3))
			{
				Attack(svpatrol2_3, nsdfrecycle);
			}
		}
	}

	if ((colorado_under_attack) && (colorado_message2_time < Get_Time()) && (!colorado_message2))
	{

		AudioMessage("misn0803.wav");//second message from colorado
		colorado_message3_time = Get_Time() + 7.0f;
		colorado_message2 = true;
	}	

	if ((colorado_message2) && (colorado_message3_time < Get_Time()) && (!colorado_message3))
	{

		AudioMessage("misn0802.wav");//third message from colorado
		AudioMessage("misn0804.wav");//final message from colorado
		colorado_message4_time = Get_Time() + 10.0f;
		colorado_message3 = true;
	}

	if ((colorado_message4_time < Get_Time()) && (!kill_colorado))
	{
		kill_colorado = true;
	}

	if ((IsAlive(colorado)) && (!kill_colorado))
	{
		if (GetTime()>next_second)
		{
			GameObjectHandle::GetObj(colorado)->AddHealth(500.0f);
			next_second = GetTime() + 1.0f;
		}
	}

	if ((colorado_message3) && (kill_colorado) && (!colorado_message4))
	{
		if (IsAlive(colorado))
		{
			Damage(colorado, 20000);
		}
		remove_nav5_time = Get_Time() + 15.0f;
		colorado_message4 = true;
	}

	if ((colorado_message4) && (remove_nav5_time < Get_Time()) && (!colorado_destroyed))
	{
//		RemoveObject (colorado);
		RemoveObject (nav5);
//		RemoveObject (drop);
		bad_news_time = Get_Time() + 5.0f;
		colorado_destroyed = true;
	}

	if ((colorado_destroyed) && (!bad_news) && (bad_news_time < Get_Time()))
	{
		AudioMessage("misn0805.wav");//Corbett give player news of colorado fate
		bad_news_time = Get_Time() + 30.0f;
		bad_news = true;
	}

	if ((bad_news) && (bad_news_time < Get_Time()) && (!gen_message))
	{
		AudioMessage("misn0810.wav");//Gen Collins give player news of colorado fate
		gen_message = true;
	}

// end soviet attack on colorado ///////////////////////////////////////////////////////////////////////////////


// this is going to give the soviets a recycler and start them attacking

	if ((bad_news) && (!ccarecycle_spawned))
	{
		SetAIP("misn08.aip");		
		SetScrap(2, 40);
		SetPilot(2, 40);
		new_aip_time = Get_Time() + 420.0f;
		if (IsAlive(ccagech3))
		{
			Goto(ccagech3, "gech_path2");
		}

		if (IsAlive(svpatrol1_1))
		{
			Goto(svpatrol1_1, "cam3_spawn");
		}
		if (IsAlive(svpatrol1_2))
		{
			Goto(svpatrol1_2, "cam3_spawn");
		}
		if (IsAlive(svpatrol1_3))
		{
			Goto(svpatrol1_3, "cam3_spawn");
		}

		ccarecycle_spawned = true;
	}

	// this is sending the third gech down the gech path when it gets to a certain point
/*	if ((ccarecycle_spawned) && (!gech3_move) && (gech_check_time < Get_Time()))
	{
		if (GetDistance(ccagech3, stop_geyser2) < 30.0f)
		{
			Goto(ccagech3, "gech_path2");
			gech3_there_time = Get_Time() + 97.0f;
			gech3_move = true;
		}
	}

*/	

// this is what happens when the player encounters the gech before it reaches the nav point ////////////////////

	if ((gech_check < Get_Time()) && (!gech_found) && (!gech_at_nav))
	{
		gech_check = Get_Time() + 6.0f;

		if ((GetDistance(user,ccagech1) < 400.0f) && (!gech_found1) && (!gech_found) && (!gech_at_nav)) //if player reaches gech before gech reaches nav
		{
			AudioMessage("misn0806.wav"); // "we're picking up something big on your radar, you may want to check it out"
			followup_message_time = Get_Time() + 20.0f; // setting up follow up message about cca gech
			stumble2_check = Get_Time() + 10.0f;
			no_stumble_check = Get_Time() + 13.0f;
			gech1_there_time = 100.0f;
			gech2_there_time = 105.0f;
			gech_found1 = true;
			gech_found = true;
		}

		if ((GetDistance(user,ccagech2) < 400.0f) && (!gech_found) && (!gech_found2) && (!gech_at_nav)) //if player reaches gech before gech reaches nav
		{
			AudioMessage("misn0806.wav"); // "we're picking up something big on your radar, you may want to check it out"
			followup_message_time = Get_Time() + 5.0f; // setting up follow up message about cca gech
			stumble2_check = Get_Time() + 60.0f;
			no_stumble_check = Get_Time() + 13.0f;
			gech1_there_time = 100.0f;
			gech2_there_time = 105.0f;
			gech_found2 = true;
			gech_found = true;
		}
	}

	if ((gech_found) && (followup_message_time < Get_Time()) && (!followup_message))
	{
		AudioMessage("misn0807.wav"); // "what the hell is that thing - approach with caution!"
		followup_message = true;
	}


	if ((base_check < Get_Time()) && (!base_set))
	{
		base_check = Get_Time() + 2.0f;

		if (IsAlive(nsdfmuf))
		{
			bool test=((Factory *) GameObjectHandle::GetObj(nsdfmuf))->IsDeployed();

			if (test)
			{
				ClearObjectives();
				AddObjective("misn0800.otf", GREEN);
				AddObjective("misn0801.otf", WHITE);
				base_set = true;
			}
		}
	}


	
	// this is what happens when the player goes and sees the gech after the first nav is dropped 

	if ((gech_found) && (stumble2_check < Get_Time()) && (!second_gech_warning) && (!run_into_other_gech))
	{
		stumble2_check = Get_Time() + 21.0f;
		
		if ((gech_found1) && (GetDistance(user,ccagech2) < 100.0f) && (!run_into_other_gech))
		{
			AudioMessage("misn0813.wav"); //Oh no! Looks like you've found another one!
			run_into_other_gech = true;
		}

		if ((gech_found2) && (GetDistance(user,ccagech1) < 100.0f) && (!run_into_other_gech))
		{
			AudioMessage("misn0813.wav"); //Oh no! Looks like you've found another one!
			run_into_other_gech = true;
		}
	}

	// this is when the player runs into one gech but the other gech gets half-way to base before being discovered

	if ((gech_found) && (no_stumble_check < Get_Time()) && (!run_into_other_gech) && (!second_gech_warning))
	{
		no_stumble_check = Get_Time() + 9.0f;

		if ((gech_found1) && (GetDistance(gech_trigger2, ccagech2) < 100.0f) && (!second_gech_warning))
		{
			AudioMessage("misn0815.wav"); //V.O. looks like we've got another one coming out of the west
			nav2 = BuildObject ("apcamr", 1, "cam2_spawn"); // builds camera near gech
			if (nav2!=NULL) GameObjectHandle::GetObj(nav2)->SetName("Nav Alpha 1");
			second_gech_warning = true;
		}

		if ((gech_found2) && (GetDistance(gech_trigger3,ccagech1) < 100.0f) && (!second_gech_warning))
		{
			AudioMessage("misn0814.wav"); //V.O. warns player of second gech
			nav3 = BuildObject ("apcamr", 1, "cam3_spawn"); // builds camera near gech
			if (nav3!=NULL) GameObjectHandle::GetObj(nav3)->SetName("Nav Alpha 2");
			second_gech_warning = true;
		}
	}


// the following occurs when the approaching gechs get half-way to the player's base

	if ((colorado_under_attack) && (trigger_check < Get_Time()) && (!gech_at_nav) && (!gech_found))
	{
		trigger_check = Get_Time() + 19.0f;
		
		if ((!gech_found) && (GetDistance(gech_trigger2, ccagech2) < 100.0f) && (!gech_at_nav)) //if gech reaches nav before player reaches gech
		{
			AudioMessage("misn0809.wav"); // "We've detected something strange on approach from the east - standby"
			gech_warning_message = Get_Time() + 20.0f;
			gech1_there_time = 100.0f;
			gech2_there_time = 105.0f;
			gech_at_nav = true;
			gech_at_nav2 = true;
		}	

		if ((!gech_found) && (GetDistance(gech_trigger3,ccagech1) < 100.0f) && (!gech_at_nav)) //if gech reaches nav before player reaches gech	
		{
			AudioMessage("misn0808.wav"); // "We've detected something strange on approach from the west - standby"
			gech_warning_message = Get_Time() + 20.0f;
			gech1_there_time = 100.0f;
			gech2_there_time = 105.0f;
			gech_at_nav = true;
			gech_at_nav3 = true;
		}
	}

	if ((gech_at_nav2) && (gech_warning_message < Get_Time()) && (!player_warned_ofgech)) //if player ignores gech_at_nav message
	{
		AudioMessage("misn0814.wav"); // Check it out - we're dropping a nav camera there now
		nav2 = BuildObject ("apcamr", 1, "cam2_spawn"); // builds camera near gech
		if (nav2!=NULL) GameObjectHandle::GetObj(nav2)->SetName("Nav Alpha 1");
		time_waist = Get_Time() + 14.0f;
		stumble1_check = Get_Time() + 100.0f;
		player_warned_ofgech = true;
	}

	if ((gech_at_nav3) && (gech_warning_message < Get_Time()) && (!player_warned_ofgech)) //if player ignores gech_at_nav message
	{
		AudioMessage("misn0815.wav"); // Check it out - we're dropping a nav camera there now
		nav3 = BuildObject ("apcamr", 1, "cam3_spawn"); // builds camera near gech
		if (nav3!=NULL) GameObjectHandle::GetObj(nav3)->SetName("Nav Alpha 2");
		time_waist = Get_Time() + 14.0f;
		stumble1_check = Get_Time() + 100.0f;
		player_warned_ofgech = true;
	}

	// this is the player getting warned of the second gech if he hasn't gone to see the first one yet //////////////////

	if ((player_warned_ofgech) && (time_waist < Get_Time()) && (!second_gech_warning) && (!bump_into_gech))
	{
		time_waist = Get_Time() + 14.0f;

		if ((gech_at_nav2) && (GetDistance(gech_trigger3,ccagech1) < 75.0f) && (!second_gech_warning)) //second gech found
		{
			AudioMessage("misn0812.wav");  //looks like we've got another one coming out of the east
			nav3 = BuildObject ("apcamr", 1, "cam3_spawn"); // builds camera near gech
			if (nav3!=NULL) GameObjectHandle::GetObj(nav3)->SetName("Nav Alpha 2");
			second_gech_warning = true;
		}

		if ((gech_at_nav3) && (GetDistance(gech_trigger2, ccagech2) < 75.0f) && (!second_gech_warning)) //second gech found
		{
			AudioMessage("misn0811.wav"); //looks like we've got another one coming out of the west
			nav2 = BuildObject ("apcamr", 1, "cam2_spawn"); // builds camera near gech
			if (nav2!=NULL) GameObjectHandle::GetObj(nav2)->SetName("Nav Alpha 1");
			second_gech_warning = true;
		}
	}

	// this is what happens when the player goes and sees the gech after the first nav is dropped 

	if ((player_warned_ofgech) && (stumble1_check < Get_Time()) && (!second_gech_warning) && (!bump_into_gech))
	{
		stumble1_check = Get_Time() + 23.0f;
		
		if ((gech_at_nav2) && (GetDistance(user,ccagech1) < 100.0f) && (!bump_into_gech))
		{
			AudioMessage("misn0813.wav"); //Oh no! Looks like you've found another one!
			bump_into_gech = true;
		}

		if ((gech_at_nav3) && (GetDistance(user,ccagech2) < 100.0f) && (!bump_into_gech))
		{
			AudioMessage("misn0813.wav"); //Oh no! Looks like you've found another one!
			bump_into_gech = true;
		}
	}


// this makes the gechs attack the player's base when they get close enough

	if ((gech_found) || (gech_at_nav))
	{
		if ((gech1_there_time < Get_Time()) && (!gech1_at_base))
		{
			gech1_there_time = Get_Time() + 30.0f;
			
			if ((IsAlive(ccagech1)) && (GetDistance(ccagech1, stop_geyser3) < 100.0f))
			{
				if (IsAlive(nsdfrecycle))
				{
					Attack(ccagech1, nsdfrecycle);
					if (gech1_blossom)
					{
						SetWeaponMask(ccagech1, 5);
					}
					gech1_at_base = true;
				}
				else
				{
					if (IsAlive(nsdfmuf))
					{
						Attack(ccagech1, nsdfmuf);
						if (gech1_blossom)
						{
							SetWeaponMask(ccagech1, 5);
						}
						gech1_at_base = true;
					}
				}
			}
		}

		if ((gech2_there_time < Get_Time()) && (!gech2_at_base))
		{
			gech2_there_time = Get_Time() + 30.0f;
			
			if ((IsAlive(ccagech2)) && (GetDistance(ccagech2, stop_geyser3) < 100.0f))
			{
				if (IsAlive(nsdfrecycle))
				{
					Attack(ccagech2, nsdfrecycle);
					if (gech2_blossom)
					{
						SetWeaponMask(ccagech2, 5);
					}
					gech2_at_base = true;
				}
				else
				{
					if (IsAlive(nsdfmuf))
					{
						Attack(ccagech2, nsdfmuf);
						if (gech2_blossom)
						{
							SetWeaponMask(ccagech2, 5);
						}
						gech2_at_base = true;
					}
				}
			}
		}

		if ((gech3_there_time < Get_Time()) && (!gech3_at_base))
		{
			gech3_there_time = Get_Time() + 30.0f;
			
			if ((IsAlive(ccagech3)) && (GetDistance(ccagech3, stop_geyser3) < 100.0f))
			{
				if (IsAlive(nsdfrecycle))
				{
					Attack(ccagech3, nsdfrecycle);
					if (gech3_blossom)
					{
						SetWeaponMask(ccagech3, 5);
					}
					gech3_at_base = true;
				}
				else
				{
					if (IsAlive(nsdfmuf))
					{
						Attack(ccagech3, nsdfmuf);
						if (gech3_blossom)
						{
							SetWeaponMask(ccagech3, 5);
						}
						gech3_at_base = true;
					}
				}
			}
		}

	}

// now I'm loading the new attack aips if the correct amount of time has passed

	if (new_aip_time < Get_Time())
	{
		new_aip_time = Get_Time() + 420.0f;
		
		units1 = CountUnitsNearObject(stop_geyser2, 5000.0f, 1, "avfigh");
		units2 = CountUnitsNearObject(stop_geyser2, 5000.0f, 1, "avtank");

		if(units1 > units2)
		{
			SetAIP("misn08b.aip");
		}
		else
		{
			SetAIP("misn08a.aip");
		}
	}

// this is apc code

	if ((IsAlive(ccaapc)) && (!apc_attack))
	{
		if (IsAlive(guntower1))
		{
			Attack(ccaapc, guntower1);
		}
		else
		{
			if (IsAlive(guntower2))
			{
				Attack(ccaapc, guntower2);
			}
			else
			{
				if (IsAlive(nsdfmuf))
				{
					Attack(ccaapc, nsdfmuf);
				}
				else
				{
					if (IsAlive(nsdfrecycle))
					{
						Attack(ccaapc, nsdfrecycle);
					}
				}
			}
		}

		apc_attack = true;
	}

	if ((apc_attack) && (!IsAlive(ccaapc)))
	{
		apc_attack = false;
	}


//This is another radar comment when the player gets extrememly close to the gech
/*	if ((gech_found) && (!too_close_message) || (gech_at_nav) && (!too_close_message))
	{
		if ((GetDistance(user, ccagech1) < 75.0f) && (!too_close_message))
		{
			AudioMessage("misn0816.wav"); // pull out!! what the hell is that!
			too_close_message = true;
		}

		if ((GetDistance(user, ccagech2) < 75.0f) && (!too_close_message))
		{
			AudioMessage("misn0816.wav"); // pull out!! what the hell is that!
			too_close_message = true;
		}
	}
*/

	if ((pull_out_message < Get_Time()) && (!too_close_message))
	{
		AudioMessage("misn0816.wav"); // pull out!! what the hell is that!
		too_close_message = true;
	}


// this will make the gechs use the popper

	if ((IsAlive(ccagech1)) && (!gech1_blossom) && (GameObjectHandle::GetObj(ccagech1)->GetHealth() < 0.25f))
	{
		SetWeaponMask(ccagech1, 4);
		pull_out_message = Get_Time() + 6.0f;
		gech1_blossom = true;
	}
	
	if ((IsAlive(ccagech2)) && (!gech2_blossom) && (GameObjectHandle::GetObj(ccagech2)->GetHealth() < 0.25f))
	{
		SetWeaponMask(ccagech2, 4);
		pull_out_message = Get_Time() + 6.0f;
		gech2_blossom = true;
	}
	
	if ((IsAlive(ccagech3)) && (!gech3_blossom) && (GameObjectHandle::GetObj(ccagech3)->GetHealth() < 0.25f))
	{
		SetWeaponMask(ccagech3, 4);
		pull_out_message = Get_Time() + 6.0f;
		gech3_blossom = true;
	}

// this is the relic code

	if ((!cerb_found) && (!relic_message) && ((IsInfo("hbblde") == true) || (IsInfo("hbbldf") == true)))
	{
		if (base_dead)
		{
			AudioMessage("misn0821.wav"); // that's not it, the ruins will be much larger
			relic_message = true;
		}
		else
		{
			AudioMessage("misn0822.wav"); // this area is crawling with relics recon as many as possible
			relic_message = true;
		}
	}

	if ((!cerb_found) && (cerb_check < Get_Time()))
	{
		cerb_check = Get_Time() + 3.0f;

		if (GetDistance(user, main_relic) < 70.0f)
		{
			if (base_dead)
			{
				AudioMessage("misn0818.wav"); // well done
				AudioMessage("misn0826.wav");
				SucceedMission(Get_Time() + 30.0f, "misn08w1.des"); //well done
				cerb_found = true;
			}
			else
			{
				AudioMessage("misn0819.wav"); // this must be how they built gechs - find base
				cerb_found = true;
			}
		}
	}

	if (IsAlive(main_relic))
	{
		if (GetTime()>next_second2)
		{
			GameObjectHandle::GetObj(main_relic)->AddHealth(500.0f);
			next_second2 = GetTime() + 1.0f;
		}
	}


// win/loose conditions /////////////////////////////
	
	if ((!IsAlive(ccarecycle)) && (!IsAlive(ccamuf)) && (!base_dead))
	{
		if (cerb_found)
		{
			AudioMessage("misn0818.wav");
			AudioMessage("misn0826.wav");
			SucceedMission(Get_Time() + 30.0f, "misn08w1.des"); //well done
			base_dead = true;
		}
		else
		{
			ClearObjectives();
			AddObjective("misn0801.otf", GREEN);
			AddObjective("misn0802.otf", WHITE);
			AudioMessage("misn0820.wav"); // find cerbeus
			SetObjectiveOn(main_relic);
			SetObjectiveName(main_relic, "Relic Site");
			base_dead = true;
		}
	}

	if ((!IsAlive(nsdfrecycle)) && (!game_over))
	{
		AudioMessage("misn0421.wav");
		FailMission(Get_Time() + 15.0f, "misn08f1.des"); //lost recycler
		game_over = true;
	}

}	

IMPLEMENT_RTIME(Misn08Mission)

Misn08Mission::Misn08Mission(void)
{
}

Misn08Mission::~Misn08Mission()
{
}

void Misn08Mission::AddObject(GameObject *gameObj)
{
	AddObject(gameObj->GetHandle());
	AiMission::AddObject(gameObj);
}

bool Misn08Mission::Load(file fp)
{
	if (missionSave) {
		int i;

		// init bools
		int b_count = &b_last - b_array;
		_ASSERTE(b_count == SIZEOF(b_array));
		for (i = 0; i < b_count; i++)
			b_array[i] = false;

		// init floats
		int f_count = &f_last - f_array;
		_ASSERTE(f_count == SIZEOF(f_array));
		for (i = 0; i < f_count; i++)
			f_array[i] = 99999.0f;

		// init handles
		int h_count = &h_last - h_array;
		_ASSERTE(h_count == SIZEOF(h_array));
		for (i = 0; i < h_count; i++)
			h_array[i] = 0;

		// init ints
		int i_count = &i_last - i_array;
		_ASSERTE(i_count == SIZEOF(i_array));
		for (i = 0; i < i_count; i++)
			i_array[i] = 0;

		Setup();
		return AiMission::Load(fp);
	}

	bool ret = true;

	// bools
	int b_count = &b_last - b_array;
	_ASSERTE(b_count == SIZEOF(b_array));
	ret = ret && in(fp, b_array, sizeof(b_array));

	// floats
	int f_count = &f_last - f_array;
	_ASSERTE(f_count == SIZEOF(f_array));
	ret = ret && in(fp, f_array, sizeof(f_array));

	// Handles
	int h_count = &h_last - h_array;
	_ASSERTE(h_count == SIZEOF(h_array));
	ret = ret && in(fp, h_array, sizeof(h_array));

	// ints
	int i_count = &i_last - i_array;
	_ASSERTE(i_count == SIZEOF(i_array));
	ret = ret && in(fp, i_array, sizeof(i_array));

	ret = ret && AiMission::Load(fp);
	return ret;
}

bool Misn08Mission::PostLoad(void)
{
	if (missionSave)
		return AiMission::PostLoad();

	bool ret = true;

	int h_count = &h_last - h_array;
	for (int i = 0; i < h_count; i++)
		h_array[i] = ConvertHandle(h_array[i]);

	ret = ret && AiMission::PostLoad();

	return ret;
}

bool Misn08Mission::Save(file fp)
{
	if (missionSave)
		return AiMission::Save(fp);

	bool ret = true;

	// bools
	int b_count = &b_last - b_array;
	_ASSERTE(b_count == SIZEOF(b_array));
	ret = ret && out(fp, b_array, sizeof(b_array), "b_array");

	// floats
	int f_count = &f_last - f_array;
	_ASSERTE(f_count == SIZEOF(f_array));
	ret = ret && out(fp, f_array, sizeof(f_array), "f_array");

	// Handles
	int h_count = &h_last - h_array;
	_ASSERTE(h_count == SIZEOF(h_array));
	ret = ret && out(fp, h_array, sizeof(h_array), "h_array");

	// ints
	int i_count = &i_last - i_array;
	_ASSERTE(i_count == SIZEOF(i_array));
	ret = ret && out(fp, i_array, sizeof(i_array), "i_array");

	ret = ret && AiMission::Save(fp);
	return ret;
}

void Misn08Mission::Update(void)
{
	AiMission::Update();
	Execute();
}


]==]
