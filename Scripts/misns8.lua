-- Faithful stock misns8 port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misns8Mission.cpp
-- Source blob: 9d5dfd561387e867bcbfc973573087616bca2cbe.
-- Every disabled C++ fragment is retained in place as a Lua comment; the entire
-- native source and header are archived in References/Misns8Source/.
-- No campaign helper, EXU, or OpenShim dependency is required.

local function NewState()
    local M = {}
    -- Native Load defaults plus Setup overrides, including unused bool state.
    M.start_done = false
    M.convoy_start = false
    M.convoy_over = false
    M.nsdf_adjust = false
    M.base_build = false
    M.new_muf_built = false
    M.muf_deployed = false
    M.plan_a = false
    M.plan_b = false
    M.plan_c = false
    M.gech1_set = false
    M.gechs_built = false
    M.turret_move = false
    M.turret1_set = false
    M.turret2_set = false
    M.turret3_set = false
    M.turret4_set = false
    M.rig_movea = false
    M.rig_prep = false
    M.rig_prepa = false
    M.rigs_ordered = false
    M.rig_wait = false
    M.rigsabuildn = false
    M.rigs_at_last = false
    M.build_last = false
    M.prep_silo = false
    M.build_silo = false
    M.t1down = false
    M.t2down = false
    M.t3down = false
    M.new_turret_orders = false
    M.silo_center_prep = false
    M.silo1_build = false
    M.prep_center_towers = false
    M.welldone_rig = false
    M.recycle_move = false
    M.recy_goto_geyser = false
    M.recy_deployed = false
    M.at_geyser = false
    M.artil_build = false
    M.muf_pack = false
    M.start_attack = false
    M.recycle_pack = false
    M.scav_sent = false
    M.rebuild1_prep = false
    M.rebuild2_prep = false
    M.rebuild3_prep = false
    M.rebuilding1 = false
    M.rebuilding2 = false
    M.rebuilding3 = false
    M.rebuild4_prep = false
    M.rebuild5_prep = false
    M.rebuild6_prep = false
    M.rebuilding4 = false
    M.rebuilding5 = false
    M.rebuilding6 = false
    M.warning = false
    M.tanks_built = false
    M.tanks_follow = false
    M.bomb_attack = false
    M.apc_attack = false
    M.walker_attack = false
    M.build_muf = false
    M.back_in_business = false
    M.game_over = false
    M.recycle_message = false
    M.new_muf = false
    M.escort1_build = false
    M.escort2_build = false
    M.escort3_build = false
    M.silo_lost = false
    M.maintain = false
    M.rig_there = false
    M.rigs_reordered = false
    M.general_spawn = false
    M.key_open = false
    M.sav1_lost = false
    M.sav2_lost = false
    M.sav3_lost = false
    M.sav4_lost = false
    M.sav5_lost = false
    M.sav6_lost = false
    M.sav1_togeneral = false
    M.sav2_togeneral = false
    M.sav3_togeneral = false
    M.sav4_togeneral = false
    M.sav5_togeneral = false
    M.sav6_togeneral = false
    M.savs_alive = false
    M.general_dead = false
    M.general_message1 = false
    M.general_message2 = false
    M.general_message3 = false
    M.general_message4 = false
    M.general_message5 = false
    M.general_message6 = false
    M.sav1_attack = false
    M.sav2_attack = false
    M.sav3_attack = false
    M.sav4_attack = false
    M.sav5_attack = false
    M.sav6_attack = false
    M.player_payback = false
    M.sav_payback = false
    M.general_scream = false
    M.danger_message = false
    M.sav1_swap = false
    M.sav2_swap = false
    M.sav3_swap = false
    M.sav4_swap = false
    M.sav5_swap = false
    M.sav6_swap = false
    M.sav_attack = false
    -- Native Load defaults plus Setup overrides, including unused float state.
    M.unit_spawn_time = 99999.0
    M.new_muf_time = 99999.0
    M.convoy_check = 99999.0
    M.turret_check = 99999.0
    M.rig_check = 99999.0
    M.rig_check2 = 99999.0
    M.rig_move = 99999.0
    M.base_build_time = 99999.0
    M.silo_prep = 99999.0
    M.turret1_set_time = 99999.0
    M.turret2_set_time = 99999.0
    M.turret3_set_time = 99999.0
    M.turret4_set_time = 99999.0
    M.recy_time = 99999.0
    M.muf_timer = 99999.0
    M.rebuild_time = 99999.0
    M.rebuild_time2 = 99999.0
    M.muf_warning = 99999.0
    M.tank_check = 99999.0
    M.escort_time = 99999.0
    M.defense_check = 99999.0
    M.center_check = 99999.0
    M.alt_check = 99999.0
    M.next_second = 0
    M.next_second2 = 0
    M.go_to_alt = 99999.0
    M.pay_off = 99999.0
    M.sav_check = 99999.0
    M.damage_time = 99999.0
    M.help_me_check = 99999.0
    -- Native Load defaults plus Setup overrides, including unused int state.
    M.units = 1
    M.scrap = 0
    M.check = 1
    M.check2 = 1
    M.tanks = 0
    M.defense1 = 3
    M.defense2 = 3
    M.silo1 = 1
    M.tower1 = 1
    M.power1 = 1
    M.silo2 = 1
    M.tower2 = 1
    M.power2 = 1
    -- All native handle members default to nil (native handle 0).
    -- user, cam1, cam2, cam3, cam4, avrig1, avrig2, avmuf, avrecycle, avmuftemp, avrecycletemp, ccarecycle, ccamuf, avturret1, avturret2, avturret3, avturret4, center_geyser, first_geyser, last_geyser, sv_geyser, av_geyser, temp_geyser, turret_geyser, dis_geyser1, dis_geyser2, avmuf_geyser, avscav1, avscav2, avscav3, avbomb1, avbomb2, avapc1, avapc2, avgech1, avtank1, avtank2, avtank3, avgech2, avtower1, avtower2, avpower1, avpower2, avtower3, avtower4, avpower3, avpower4, avsilo1, avsilo2, screwtower, screwpower, svpower1, svpower2, sav1, sav2, sav3, sav4, sav5, sav6, avfighter1, avfighter2, avwalker, escort1, escort2, escort3, powerplant1, powerplant2, basetower1, basetower2, screwu1, screwu2, key_tank, badsav1, badsav2, badsav3, badsav4, badsav5, badsav6, popartil, nark
    return M
end

local M = NewState()

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function Distance(a, b)
    -- PORT FIX: missing/deleted handles cannot satisfy a proximity test.
    -- Guard Lua overloads to avoid an invalid call or false arrival; distances
    -- and thresholds on a valid map remain identical to the source.
    if not Valid(a) or not Valid(b) then return math.huge end
    return GetDistance(a, b)
end

function Start()
    -- Numeric defaults exist before map AddObject callbacks. Bind map labels
    -- here without erasing any production slots collected while the map loads.
    M.avmuf = GetHandle ("avmuf")
    M.avrecycle = GetHandle ("avrecycle")
    M.ccarecycle = GetHandle ("svrecycle")
    M.ccamuf = GetHandle ("svmuf")
    M.center_geyser = GetHandle ("center_geyser")
    M.first_geyser = GetHandle ("first_geyser")
    M.last_geyser = GetHandle ("last_geyser")
    M.sv_geyser = GetHandle ("sv_geyser")
    M.av_geyser = GetHandle ("av_geyser")
    M.temp_geyser = GetHandle("temp_geyser")
    M.turret_geyser = GetHandle("turret_geyser")
    M.dis_geyser1 = GetHandle("dis_geyser1")
    M.dis_geyser2 = GetHandle("dis_geyser2")
    M.cam1 = GetHandle("cam")
    M.cam2 = GetHandle("basecam")
    M.powerplant1 = GetHandle("powerplant1")
    M.powerplant2 = GetHandle("powerplant2")
    M.basetower1 = GetHandle("basetower1")
    M.basetower2 = GetHandle("basetower2")
    M.avmuf_geyser = GetHandle("avmuf_geyser")
end

function AddObject(h)
    if not Valid(h) then return end
    -- Keep the exact source slot priority and ODF matching (no team filter).
    if M.avturret1 == nil and IsOdf(h, "bvtur8") then
        M.avturret1 = h
    elseif M.avturret2 == nil and IsOdf(h, "bvtur8") then
        M.avturret2 = h
    elseif M.avfighter1 == nil and IsOdf(h, "bvra8") then
        M.avfighter1 = h
    elseif M.avfighter2 == nil and IsOdf(h, "bvra8") then
        M.avfighter2 = h
    elseif M.avrig1 == nil and IsOdf(h, "avcns8") then
        M.avrig1 = h
    elseif M.avrig2 == nil and IsOdf(h, "avcns8") then
        M.avrig2 = h
    elseif M.avtank1 == nil and IsOdf(h, "bvtavk") then
        M.avtank1 = h
    elseif M.avtank2 == nil and IsOdf(h, "bvtavk") then
        M.avtank2 = h
    elseif M.avtank3 == nil and IsOdf(h, "bvtavk") then
        M.avtank3 = h
    elseif M.avtower1 == nil and IsOdf(h, "abtowe") then
        M.avtower1 = h
    elseif M.avtower2 == nil and IsOdf(h, "abtowe") then
        M.avtower2 = h
    elseif M.avpower1 == nil and IsOdf(h, "abwpow") then
        M.avpower1 = h
    elseif M.avpower2 == nil and IsOdf(h, "abwpow") then
        M.avpower2 = h
    elseif M.avtower3 == nil and IsOdf(h, "abtowe") then
        M.avtower3 = h
    elseif M.avtower4 == nil and IsOdf(h, "abtowe") then
        M.avtower4 = h
    elseif M.avpower3 == nil and IsOdf(h, "abwpow") then
        M.avpower3 = h
    elseif M.avpower4 == nil and IsOdf(h, "abwpow") then
        M.avpower4 = h
    elseif M.avsilo1 == nil and IsOdf(h, "absilo") then
        M.avsilo1 = h
    elseif M.avsilo2 == nil and IsOdf(h, "absilo") then
        M.avsilo2 = h
    elseif M.screwtower == nil and IsOdf(h, "abtowe") then
        M.screwtower = h
    elseif M.screwpower == nil and IsOdf(h, "abwpow") then
        M.screwpower = h
    elseif M.svpower1 == nil and IsOdf(h, "sbwpow") then
        M.svpower1 = h
    elseif M.svpower2 == nil and IsOdf(h, "sbwpow") then
        M.svpower2 = h
    elseif M.avturret3 == nil and IsOdf(h, "bvtur8") then
        M.avturret3 = h
    elseif M.avturret4 == nil and IsOdf(h, "bvtur8") then
        M.avturret4 = h
    elseif M.avbomb1 == nil and IsOdf(h, "bvhraz") then
        M.avbomb1 = h
    elseif M.avapc1 == nil and IsOdf(h, "bvapc") then
        M.avapc1 = h
    elseif M.sav1 == nil and IsOdf(h, "savtnk") then
        M.sav1 = h
    elseif M.sav2 == nil and IsOdf(h, "savtnk") then
        M.sav2 = h
    elseif M.sav3 == nil and IsOdf(h, "savtnk") then
        M.sav3 = h
    elseif M.sav4 == nil and IsOdf(h, "savtnk") then
        M.sav4 = h
    elseif M.sav5 == nil and IsOdf(h, "savtnk") then
        M.sav5 = h
    elseif M.sav6 == nil and IsOdf(h, "savtnk") then
        M.sav6 = h
    elseif M.avwalker == nil and IsOdf(h, "bvwalk") then
        M.avwalker = h
    end
end

function Update(dt)
    -- Native AiMission updates strategic AI before Execute. LuaMission owns
    -- that engine update; retain every Execute branch in original order.
    -- START OF SCRIPT
    M.user = GetPlayerHandle()
    --assigns the player a handle every frame
    if not IsAlive(M.sav1) then
        M.sav1_swap = false
    end
    if not IsAlive(M.sav2) then
        M.sav2_swap = false
    end
    if not IsAlive(M.sav3) then
        M.sav3_swap = false
    end
    if not IsAlive(M.sav4) then
        M.sav4_swap = false
    end
    if not IsAlive(M.sav5) then
        M.sav5_swap = false
    end
    if not IsAlive(M.sav6) then
        M.sav6_swap = false
    end
    if not IsAlive(M.avbomb1) then
        M.bomb_attack = false
    end
    if not IsAlive(M.avapc1) then
        M.apc_attack = false
    end
    if not IsAlive(M.avwalker) then
        M.walker_attack = false
    end
    if (IsAlive(M.avrecycle))  and  (not M.recycle_move) then
        if GetTime() > M.next_second then
            AddHealth(M.avrecycle, 200.0)
            M.next_second = GetTime() + 1.0
        end
    end
    if not M.start_done then
        SetScrap(1, 25)
        SetScrap(2, 40)
        SetPilot(1, 10)
        SetPilot(2, 60)
        AudioMessage("misns800.wav")
        -- General "mission breifing"
        ClearObjectives()
        AddObjective("misns800.otf", "white")
        --		AddObjective("misns800.otf", WHITE);
        M.avscav1 = BuildObject("bvsca8", 2, "american_spawn")
        M.avscav2 = BuildObject("bvsca8", 2, "american_spawn")
        M.avscav3 = BuildObject("bvsca8", 2, "american_spawn")
        M.nark = BuildObject("bvra8", 2, "american_spawn")
        if M.cam1~=nil then
            SetObjectiveName(M.cam1, "Black Dog Base")
        end
        if M.cam2~=nil then
            SetObjectiveName(M.cam2, "Drop Zone")
        end
        M.defense_check = GetTime() + 60.0
        SetAIP("misns8.aip")
        M.start_done = true
        M.plan_a = true
    end
    -- this is the start of PLAN A - take the center
    if M.plan_a then
        -- first I build the turrets and then the rigs
        --[=[/*	if ((IsAlive(avturret3)) && (!turret_move))
	{
		Goto(avturret3, "center_path3");

		if (IsAlive(avturret1))
		{
			Goto(avturret1, "center_path");
		}

		if (IsAlive(avturret2))
		{
			Retreat(avturret2, "center_path2", 1);
		}

		if ((IsAlive(nark)) && (IsAlive(ccarecycle)))
		{
			Attack(nark, ccarecycle, 1);
		}
		
		turret_check = Get_Time() + 10.0f;
		turret_move = true;
	}

	if ((turret_move) && (turret_check < Get_Time()))
	{
		if ((IsAlive(avturret1)) && (!turret1_set) && (GetDistance(avturret1, turret_geyser) < 100.0f))
		{
			Defend(avturret1);
			turret1_set_time = Get_Time() + 10.0f;
			turret1_set = true;
		}

		if ((IsAlive(avturret2)) && (!turret2_set) && (GetDistance(avturret2, turret_geyser) < 100.0f))
		{
			Defend(avturret2);
//			RemoveObject(temp_geyser);
			turret2_set_time = Get_Time() + 11.0f;
			turret2_set = true;
		}

		if ((IsAlive(avturret3)) && (!turret3_set) && (GetDistance(avturret3, turret_geyser) < 100.0f))
		{
			Defend(avturret3);
			turret3_set_time = Get_Time() + 12.0f;
			turret3_set = true;
		}

		if ((IsAlive(popartil)) && (!turret4_set) && (GetDistance(popartil, temp_geyser) < 20.0f))
		{
			Defend(popartil);
			turret4_set_time = Get_Time() + 12.0f;
			turret4_set = true;
		}

		turret_check = Get_Time() + 6.0f;
	}

	if (!new_turret_orders)
	{
		if ((turret1_set) && (turret1_set_time < Get_Time()))
		{
			if (IsAlive(avturret1))
			{
				turret1_set_time = Get_Time() + 20.0f;
				Defend(avturret1);
			}
		}

		if ((turret2_set) && (turret2_set_time < Get_Time()))
		{
			if (IsAlive(avturret2))
			{
				turret2_set_time = Get_Time() + 20.0f;
				Defend(avturret2);
			}
		}

		if ((turret3_set) && (turret3_set_time < Get_Time()))
		{
			if (IsAlive(avturret3))
			{
				turret3_set_time = Get_Time() + 20.0f;
				Defend(avturret3);
			}
		}

		if ((turret4_set) && (turret4_set_time < Get_Time()))
		{
			if (IsAlive(popartil))
			{
				turret4_set_time = Get_Time() + 180.0f;
				Defend(popartil);
			}
		}
	}

/*	if ((turret1_set) && (turret1_set_time < Get_Time()))
	{
		if ((IsAlive(avturret1)) && (!t1down))
		{
			Defend(avturret1, 1);
			t1down = true;
		}
	}

	if ((turret2_set) && (turret2_set_time < Get_Time()))
	{
		if ((IsAlive(avturret2)) && (!t2down))
		{
			Defend(avturret2, 1);
			t2down = true;
		}
	}

	if ((turret3_set) && (turret3_set_time < Get_Time()))
	{
		if ((IsAlive(avturret3)) && (!t3down))
			{
				Defend(avturret3, 1);
				t3down = true;
			}
	}
*/]=]
    end
    -- this is telling the construction rigs to build gun towers at their base
    if (IsAlive(M.avrig1))  and  (IsAlive(M.avrig2))  and  (not M.rig_prep) then
        Build(M.avrig1, "abwpow")
        Build(M.avrig2, "abtowe")
        M.base_build_time = GetTime() + 10.0
        SetAIP("misns8a.aip")
        -- this buld another turret and HAVE 3 fighters (have 4 scavs)
        M.rig_prep = true
    end
    if (M.rig_prep)  and  (not M.base_build)  and  (M.base_build_time < GetTime()) then
        AddScrap(2, 60)
        if IsAlive(M.avrig1) then
            Dropoff(M.avrig1, "rpower1")
        end
        if IsAlive(M.avrig2) then
            Dropoff(M.avrig2, "rtower1")
        end
        M.base_build = true
    end
    -- this is sending the construction rigs to the scrap field
    if (M.base_build)  and  (IsAlive(M.avtower1))  and  (IsAlive(M.avpower1))  and  (not M.rig_movea) then
        if IsAlive(M.avrig1) then
            Goto(M.avrig1, "center_path", 1)
        end
        if IsAlive(M.avrig2) then
            Goto(M.avrig2, "center_path", 1)
        end
        M.rig_check = GetTime() + 90.0
        M.rig_movea = true
    end
    -- building artil w/poppers
    if (not M.artil_build)  and  (M.rig_movea) then
        M.popartil = BuildObject("avart8", 2, "american_spawn")
        M.artil_build = true
    end
    if (not M.at_geyser)  and  (IsAlive(M.popartil)) then
        Goto(M.popartil, M.temp_geyser, 1)
        M.at_geyser = true
    end
    -- first I build a silo
    if (not M.silo_center_prep)  and  (M.rig_check < GetTime()) then
        M.rig_check2 = GetTime() + 5.0
        if IsAlive(M.avrig1) then
            Build(M.avrig1, "absilo")
        end
        if IsAlive(M.avrig2) then
            Build(M.avrig2, "absilo")
        end
        M.silo_center_prep = true
    end
    if (M.silo_center_prep)  and  (not M.silo1_build)  and  (M.rig_check2 < GetTime()) then
        M.rig_check2 = GetTime() + 5.0
        M.scrap = GetScrap(2)
        if IsAlive(M.avrig1) then
            M.check2 = math.floor(Distance(M.avrig1, M.temp_geyser))
        else
            if IsAlive(M.avrig2) then
                M.check2 = math.floor(Distance(M.avrig2, M.temp_geyser))
            end
        end
        if M.scrap > 8.0 then
            if IsAlive(M.avrig1) then
                Dropoff(M.avrig1, "center_silo")
                if IsAlive(M.avrig2) then
                    Goto(M.avrig2, "center_silo")
                end
                M.silo1_build = true
            else
                if IsAlive(M.avrig2) then
                    Dropoff(M.avrig2, "center_silo")
                    M.silo1_build = true
                end
            end
        else
            if M.check2 < 100.0 then
                if IsAlive(M.avrig1) then
                    Defend(M.avrig1)
                end
                if IsAlive(M.avrig2) then
                    Defend(M.avrig2)
                end
            else
                if IsAlive(M.avrig1) then
                    Goto(M.avrig1, M.temp_geyser, 1)
                end
                if IsAlive(M.avrig2) then
                    Goto(M.avrig2, M.temp_geyser, 1)
                end
            end
        end
    end
    if (M.silo1_build)  and  (not M.prep_center_towers)  and  (IsAlive(M.avsilo1)) then
        if IsAlive(M.avrig1) then
            Build(M.avrig1, "abwpow")
        end
        if IsAlive(M.avrig2) then
            Build(M.avrig2, "abtowe")
        end
        SetAIP("misns8b.aip")
        -- this builds another fighter (have 3) (have 4 scavs)
        M.rig_check = GetTime() + 10.0
        M.muf_timer = GetTime() + 10.0
        -- BE CAREFUL - carries over into plan_b 
        M.prep_center_towers = true
    end
    -- this is making the rigs build a gun tower and powerplant in the center
    if (M.prep_center_towers)  and  (not M.rigs_ordered)  and  (M.rig_check < GetTime()) then
        M.rig_check = GetTime() + 5.0
        M.scrap = GetScrap(2)
        if M.scrap > 14.0 then
            SetAIP("misns8g.aip")
            -- this stops building vehicles while the rigs build towers
            if IsAlive(M.avrig1) then
                Dropoff(M.avrig1, "main_field2")
            end
            if IsAlive(M.avrig2) then
                Dropoff(M.avrig2, "main_field1")
            end
            M.rigs_ordered = true
        else
            if (IsAlive(M.avrig1))  and  (Distance(M.avrig1, M.temp_geyser) < 200.0) then
                Defend(M.avrig1)
                if IsAlive(M.avrig2) then
                    Defend(M.avrig2)
                end
            else
                if (IsAlive(M.avrig2))  and  (Distance(M.avrig2, M.temp_geyser) < 200.0) then
                    Defend(M.avrig2)
                end
            end
            AddScrap(2, 2)
        end
    end
    --[=[/*	if ((rigs_ordered) && (!rigsabuildn) && (rig_check < Get_Time()))
	{
		rig_check = Get_Time() + 10.0f;
		scrap = GetScrap(2);

		if (scrap > 18.0f) 
		{
			if (IsAlive(avrig1))
			{
				Dropoff(avrig1, "main_field2");
			}

			if (IsAlive(avrig2))
			{
				Dropoff(avrig2, "main_field1");
			}

			rigsabuildn = true;
		}
	}
*/]=]
    if (IsAlive(M.avtower2))  and  (IsAlive(M.avpower2))  and  (not M.welldone_rig) then
        M.go_to_alt = GetTime() + 20.0
        SetAIP("misns8b.aip")
        -- this builds another fighter (have 3) (have 4 scavs)		
        M.center_check = GetTime() + 5.0
        M.alt_check = GetTime() + 60.0
        M.new_turret_orders = true
        -- releases the original 3 turrets if they are still alive
        M.welldone_rig = true
    end
    -- this is checking to see if the muf has tank support
    if (IsAlive(M.avtank2))  and  (not M.tanks_follow) then
        if IsAlive (M.avmuf) then
            Follow(M.avtank2, M.avmuf)
            if IsAlive(M.avtank1) then
                Follow(M.avtank1, M.avmuf)
            end
            M.tank_check = GetTime() + 30.0
            M.tanks_follow = true
        end
    end
    if (M.tanks_follow)  and  (M.tank_check < GetTime())  and  (not M.tanks_built) then
        M.tank_check = GetTime() + 30.0
        if IsAlive(M.avtank3) then
            --			tanks = CountUnitsNearObject(avmuf, 4000, 2, "bvtavk");
            --
            --			if (tanks > 3)
            --			{
            M.tanks_built = true
            --			}
        end
    end
    if (M.tanks_built)  and  (M.welldone_rig)  and  (M.plan_a) then
        M.plan_a = false
        M.plan_b = true
    end
    -- this is the start of PLAN B "move muf"
    if M.plan_b then
        -- carry-over form plan_a
        --[=[/*	if ((turret1_set) && (turret1_set_time < Get_Time()))
	{
		if (IsAlive(avturret1))
		{
			turret1_set_time = Get_Time() + 20.0f;
			Defend(avturret1);
		}
	}

	if ((turret2_set) && (turret2_set_time < Get_Time()))
	{
		if (IsAlive(avturret2))
		{
			turret2_set_time = Get_Time() + 20.0f;
			Defend(avturret2);
		}
	}

	if ((turret3_set) && (turret3_set_time < Get_Time()))
	{
		if (IsAlive(avturret3))
		{
			turret3_set_time = Get_Time() + 20.0f;
			Defend(avturret3);
		}
	}
*/]=]
        if (M.turret4_set)  and  (M.turret4_set_time < GetTime()) then
            if IsAlive(M.popartil) then
                M.turret4_set_time = GetTime() + 180.0
                Defend(M.popartil)
            end
        end
        -- this makes the muf move
        if (not M.muf_pack)  and  (IsAlive(M.avmuf))  and  (M.muf_timer < GetTime()) then
            M.muf_timer = GetTime() + 10.0
            M.scrap = GetScrap(2)
            if M.scrap > 11 then
            -- Native target 0 becomes Lua nil: pack the producer itself.
            Pickup(M.avmuf, nil, 1)
                M.muf_timer = GetTime() + 10.0
                M.muf_pack = true
            end
        end
        if (not M.convoy_start)  and  (M.muf_pack)  and  (IsAlive(M.avmuf))  and  (M.muf_timer < GetTime()) then
            Goto(M.avmuf, "convoy_path", 1)
            SetAIP("misns8d.aip")
            -- povides fighter support
            M.muf_timer = GetTime() + 60.0
            M.muf_warning = GetTime() + 10.0
            if IsAlive(M.avfighter1) then
                Follow(M.avfighter1, M.avmuf)
            end
            if IsAlive(M.avfighter2) then
                Follow(M.avfighter2, M.avmuf)
            end
            M.convoy_start = true
        end
        if (not M.warning)  and  (M.convoy_start)  and  (IsAlive(M.avmuf))  and  (M.muf_warning < GetTime()) then
            M.muf_warning = GetTime() + 6.0
            if Distance(M.user, M.avmuf) < 100.0 then
                M.warning = true
            else
                if Distance(M.avmuf, M.dis_geyser1) < 100.0 then
                    AudioMessage("misns801.wav")
                    M.cam3 = BuildObject ("apcamr", 1, "cam_spawn")
                    if M.cam3~=nil then
                        SetObjectiveName(M.cam3, "Choke Point")
                    end
                    ClearObjectives()
                    AddObjective("misns800.otf", "white")
                    AddObjective("misns801.otf", "white")
                    M.warning = true
                end
            end
        end
        if (not M.convoy_over)  and  (M.convoy_start)  and  (IsAlive(M.avmuf))  and  (M.muf_timer < GetTime()) then
            M.muf_timer = GetTime() + 5.0
            if Distance(M.avmuf, M.center_geyser) < 100.0 then
                Goto(M.avmuf, M.center_geyser, 1)
                M.convoy_over = true
            end
        end
        if (M.convoy_over)  and  (not M.muf_deployed) then
            if IsAlive(M.avmuf) then
                local test=IsDeployed(M.avmuf)
                if test then
                    M.muf_deployed = true
                end
            end
        end
        -- this is what happens when the muf is destroyed
        if (M.convoy_start)  and  (not IsAlive(M.avmuf))  and  (not M.new_muf) then
            M.screwu1 = BuildObject("bvtavk", 2, "t1post")
            M.screwu2 = BuildObject("bvtavk", 2, "t1post")
            if IsAlive(M.ccarecycle) then
                Attack(M.screwu1, M.ccarecycle)
                Attack(M.screwu2, M.ccarecycle)
            end
            M.avmuf = BuildObject("bvmuf", 2, "american_spawn")
            Goto(M.avmuf, M.avmuf_geyser)
            M.muf_deployed = false
            M.new_muf = true
        end
        if (not M.start_attack)  and  (M.muf_deployed) then
            SetAIP("misns8c.aip")
            -- starts to produce tanks + bombers and gechs (have 4 scavs)
            --		plan_b = false;
            --		plan_c = true;
            M.start_attack = true
        end
        if (IsAlive(M.avbomb1))  and  (not M.bomb_attack) then
            if IsAlive(M.ccarecycle) then
                Attack(M.avbomb1, M.ccarecycle, 1)
            end
            M.bomb_attack = true
        end
        if (IsAlive(M.avapc1))  and  (not M.apc_attack) then
            if IsAlive(M.ccarecycle) then
                Attack(M.avapc1, M.ccarecycle, 1)
            end
            M.apc_attack = true
        end
        if (IsAlive(M.avwalker))  and  (not M.walker_attack) then
            if IsAlive(M.ccarecycle) then
                Attack(M.avwalker, M.ccarecycle, 0)
            end
            M.walker_attack = true
        end
    end
    -- this constitutes the situation where plan_c happens
    if (not M.plan_c)  and  (IsAlive(M.avrecycle))  and  (M.defense_check < GetTime()) then
        M.defense_check = GetTime() + 5.0
        M.defense1 = CountUnitsNearObject(M.avrecycle, 200.0, 2, "abtowe")
        M.defense2 = CountUnitsNearObject(M.avrecycle, 200.0, 2, "abwpow")
        M.scrap = GetScrap(2)
        --[=[/*((defense1 == 1) && (defense2 == 1)) || */]=]
        if ((M.defense1 == 0)  or  (M.defense2 == 0))  and  (M.scrap < 10.0) then
            M.plan_a = false
            M.plan_b = false
            M.plan_c = true
        end
    end
    -- this is the start of PLAN C "move Recycler"
    if M.plan_c then
        --[=[/*	if ((!escort1_build) && (IsAlive(avrecycle)) && (escort_time < Get_Time()))
	{ 
		escort1 = BuildObject("bvraz", 2, "american_spawn");
		Follow(escort1, avrecycle);
		escort_time = Get_Time() + 10.0f;
		escort1_build = true;
	}

	if ((!escort2_build) && (IsAlive(avrecycle)) && (escort1_build) &&  (escort_time < Get_Time()))
	{ 
		escort2 = BuildObject("bvraz", 2, "american_spawn");
		Follow(escort2, avrecycle);
		escort_time = Get_Time() + 10.0f;
		escort2_build = true;
	}

	if ((!escort3_build) && (IsAlive(avrecycle)) && (escort2_build) && (escort_time < Get_Time()))
	{ 
		escort3 = BuildObject("bvraz", 2, "american_spawn");
		Follow(escort3, avrecycle);
		escort3_build = true;
	}

*/]=]
        --[=[/*escort3_build) && */]=]
        if ((M.general_message1)  or  (M.sav_payback))  and  (not M.recycle_pack)  and  (IsAlive(M.avrecycle)) then
            AddScrap(2, 20)
            SetAIP("misns8c.aip")
        -- Native target 0 becomes Lua nil: pack the recycler itself.
        Pickup(M.avrecycle, nil, 1)
            M.recy_time = GetTime() + 10.0
            M.recycle_pack = true
        end
        if (not M.recycle_move)  and  (M.recycle_pack)  and  (IsAlive(M.avrecycle))  and  (M.recy_time < GetTime()) then
            Goto(M.avrecycle, "escape_route", 1)
            M.recy_time = GetTime() + 60.0
            --[=[/*			if (IsAlive(escort1))
		{
			Follow(escort1, avrecycle);
		}

		if (IsAlive(escort2))
		{
			Follow(escort2, avrecycle);
		}

		if (IsAlive(escort3))
		{
			Follow(escort3, avrecycle);
		}
*/]=]
            SetPerceivedTeam(M.avrecycle, 1)
            if IsAlive(M.basetower1) then
                SetPerceivedTeam(M.basetower1, 1)
            end
            if IsAlive(M.basetower2) then
                SetPerceivedTeam(M.basetower2, 1)
            end
            if IsAlive(M.avtower1) then
                SetPerceivedTeam(M.avtower1, 1)
            end
            if IsAlive(M.powerplant1) then
                SetPerceivedTeam(M.powerplant1, 1)
            end
            if IsAlive(M.powerplant2) then
                SetPerceivedTeam(M.powerplant2, 1)
            end
            if IsAlive(M.avpower1) then
                SetPerceivedTeam(M.avpower1, 1)
            end
            if IsAlive(M.avmuf) then
                SetPerceivedTeam(M.avmuf, 1)
            end
            M.recycle_move = true
        end
        -- PORT FIX: native arrival polling resets recy_time before the following
        -- deployment test on every due frame, so that test can never run. Stop
        -- arrival polling once recy_goto_geyser is set; the next original ten-
        -- second deadline can then reach IsDeployed. Travel, arrival distance,
        -- deployment polling and AIP order retain the intended source flow.
        if (M.recycle_move)  and  (not M.recy_goto_geyser)  and  (IsAlive(M.avrecycle))  and  (M.recy_time < GetTime()) then
            M.recy_time = GetTime() + 10.0
            --[=[/*
		if ((GetDistance(avrecycle, dis_geyser2) < 100.0f) && (!recycle_message))
		{
			AudioMessage("misns802.wav");
			cam4 = BuildObject ("apcamr", 1, "last_nav_spawn");
			if (cam4!=NULL) GameObjectHandle::GetObj(cam4)->SetName("Choke Point");
			recycle_message = true;
		}
*/]=]
            if (Distance(M.avrecycle, M.last_geyser) < 100.0)  and  (not M.recy_goto_geyser) then
                Goto(M.avrecycle, M.last_geyser, 1)
                SetPerceivedTeam(M.avrecycle, 2)
                M.recy_goto_geyser = true
            end
        end
        if (M.recy_goto_geyser)  and  (not M.recy_deployed)  and  (IsAlive(M.avrecycle))  and  (M.recy_time < GetTime()) then
            M.recy_time = GetTime() + 5.0
            local test=IsDeployed(M.avrecycle)
            if test then
                SetAIP("misns8a.aip")
                M.recy_deployed = true
            end
        end
        if (M.recy_deployed)  and  (not M.back_in_business) then
            if (IsAlive(M.avturret1))  and  (IsAlive(M.avturret2)) then
                SetAIP("misns8f.aip")
                M.back_in_business = true
            end
        end
    end
    -- this makes sure rig1 keep up the center
    if (M.welldone_rig)  and  (M.go_to_alt < GetTime())  and  (not M.rigs_reordered) then
        if IsAlive(M.avsilo1) then
            if IsAlive(M.avrig1) then
                --			SetIndependence(avrig1, 1);
                Follow(M.avrig1, M.avsilo1)
            end
            if IsAlive(M.avrig2) then
                --			SetIndependence(avrig2, 1);
                Goto(M.avrig2, "go_path")
            end
        else
            if IsAlive(M.avrig1) then
                --			SetIndependence(avrig2, 1);
                Build(M.avrig1, "absilo")
            end
            if IsAlive(M.avrig2) then
                --			SetIndependence(avrig2, 1);
                Goto(M.avrig2, "go_path")
            end
        end
        M.rigs_reordered = true
    end
    if (M.rigs_reordered)  and  (IsAlive(M.avrig1))  and  (M.center_check < GetTime()) then
        if (not M.rebuild1_prep)  and  (not M.rebuild2_prep)  and  (not M.rebuild3_prep) then
            M.center_check = GetTime() + 10.0
            M.silo1 = CountUnitsNearObject(M.temp_geyser, 900, 2, "absilo")
            M.power1 = CountUnitsNearObject(M.temp_geyser, 900, 2, "abwpow")
            M.tower1 = CountUnitsNearObject(M.temp_geyser, 900, 2, "abtowe")
            if M.silo1 == 0 then
                Build(M.avrig1, "absilo")
                M.rebuild_time = GetTime() + 5.0
                M.rebuild1_prep = true
            else
                if M.power1 == 0 then
                    Build(M.avrig1, "abwpow")
                    M.rebuild_time = GetTime() + 5.0
                    M.rebuild2_prep = true
                else
                    if M.tower1 == 0 then
                        Build(M.avrig1, "abtowe")
                        M.rebuild_time = GetTime() + 5.0
                        M.rebuild3_prep = true
                    else
                        Defend(M.avrig1)
                    end
                end
            end
        end
        if (M.rebuild1_prep)  and  (not M.rebuilding1)  and  (M.rebuild_time < GetTime()) then
            M.rebuild_time = GetTime() + 5.0
            M.scrap = GetScrap(2)
            if M.scrap > 8 then
                Dropoff(M.avrig1, "center_silo")
                M.rebuilding1 = true
            end
        end
        if (M.rebuild2_prep)  and  (not M.rebuilding2)  and  (M.rebuild_time < GetTime()) then
            M.rebuild_time = GetTime() + 5.0
            M.scrap = GetScrap(2)
            if M.scrap > 10 then
                Dropoff(M.avrig1, "main_field2")
                M.rebuilding2 = true
            end
        end
        if (M.rebuild3_prep)  and  (not M.rebuilding3)  and  (M.rebuild_time < GetTime()) then
            M.rebuild_time = GetTime() + 5.0
            M.scrap = GetScrap(2)
            if M.scrap > 10 then
                Dropoff(M.avrig1, "main_field1")
                M.rebuilding3 = true
            end
        end
        if (M.rebuilding1)  and  (M.center_check < GetTime()) then
            M.center_check = GetTime() + 10.0
            M.silo1 = CountUnitsNearObject(M.temp_geyser, 900, 2, "absilo")
            -- PORT FIX: native == 1 stalls maintenance if an additional matching
            -- structure is present. >= 1 recognizes the completed build; the
            -- ordinary one-structure case, priorities and timers are unchanged.
            if M.silo1 >= 1 then
                M.rebuild1_prep = false
                M.rebuilding1 = false
            end
        end
        if (M.rebuilding2)  and  (M.center_check < GetTime()) then
            M.center_check = GetTime() + 10.0
            M.power1 = CountUnitsNearObject(M.temp_geyser, 900, 2, "abwpow")
            -- PORT FIX: same exact-count maintenance stall as the silo above.
            -- Accept additional power plants; normal completion timing is unchanged.
            if M.power1 >= 1 then
                M.rebuild2_prep = false
                M.rebuilding2 = false
            end
        end
        if (M.rebuilding3)  and  (M.center_check < GetTime()) then
            M.center_check = GetTime() + 10.0
            M.tower1 = CountUnitsNearObject(M.temp_geyser, 900, 2, "abtowe")
            -- PORT FIX: accept an existing tower even if another was built nearby.
            -- The original one-tower flow and polling interval are unchanged.
            if M.tower1 >= 1 then
                M.rebuild3_prep = false
                M.rebuilding3 = false
            end
        end
    end
    -- this is rig2 code
    if (M.welldone_rig)  and  (IsAlive(M.avrig2)) then
        if not M.maintain then
            Build(M.avrig2, "absilo")
            M.maintain = true
        end
        if (M.alt_check < GetTime())  and  (not M.rig_there) then
            M.alt_check = GetTime() + 10.0
            if Distance(M.avrig2, M.last_geyser) < 300.0 then
                M.rebuild_time2 = GetTime() + 5.0
                M.rig_there = true
            end
        end
        if (M.rig_there)  and  (M.alt_check < GetTime()) then
            if (not M.rebuild4_prep)  and  (not M.rebuild5_prep)  and  (not M.rebuild6_prep) then
                M.alt_check = GetTime() + 10.0
                M.silo2 = CountUnitsNearObject(M.last_geyser, 400, 2, "absilo")
                M.power2 = CountUnitsNearObject(M.last_geyser, 400, 2, "abwpow")
                M.tower2 = CountUnitsNearObject(M.last_geyser, 400, 2, "abtowe")
                if M.silo2 == 0 then
                    Build(M.avrig2, "absilo")
                    M.rebuild_time2 = GetTime() + 5.0
                    M.rebuild4_prep = true
                else
                    if M.power2 == 0 then
                        Build(M.avrig2, "abwpow")
                        M.rebuild_time2 = GetTime() + 5.0
                        M.rebuild5_prep = true
                    else
                        if M.tower2 == 0 then
                            Build(M.avrig2, "abtowe")
                            M.rebuild_time2 = GetTime() + 5.0
                            M.rebuild6_prep = true
                        else
                            Defend(M.avrig2)
                            if not M.scav_sent then
                                if IsAlive(M.avscav1) then
                                    Goto(M.avscav1, "go_path")
                                end
                                M.scav_sent = true
                            end
                        end
                    end
                end
            end
            if (M.rebuild4_prep)  and  (not M.rebuilding4)  and  (M.rebuild_time2 < GetTime()) then
                M.rebuild_time2 = GetTime() + 5.0
                M.scrap = GetScrap(2)
                if M.scrap > 8 then
                    Dropoff(M.avrig2, "alt_silo")
                    M.rebuilding4 = true
                end
            end
            if (M.rebuild5_prep)  and  (not M.rebuilding5)  and  (M.rebuild_time2 < GetTime()) then
                M.rebuild_time2 = GetTime() + 5.0
                M.scrap = GetScrap(2)
                if M.scrap > 10 then
                    Dropoff(M.avrig2, "alt_power")
                    M.rebuilding5 = true
                end
            end
            if (M.rebuild6_prep)  and  (not M.rebuilding6)  and  (M.rebuild_time2 < GetTime()) then
                M.rebuild_time2 = GetTime() + 5.0
                M.scrap = GetScrap(2)
                if M.scrap > 10 then
                    Dropoff(M.avrig2, "alt_tower")
                    M.rebuilding6 = true
                end
            end
            if (M.rebuilding4)  and  (M.alt_check < GetTime()) then
                M.alt_check = GetTime() + 10.0
                M.silo2 = CountUnitsNearObject(M.last_geyser, 400, 2, "absilo")
                -- PORT FIX: >= 1 avoids the same extra-structure maintenance
                -- stall at the alternate site, without changing normal timing.
                if M.silo2 >= 1 then
                    M.rebuild4_prep = false
                    M.rebuilding4 = false
                end
            end
            if (M.rebuilding5)  and  (M.alt_check < GetTime()) then
                M.alt_check = GetTime() + 10.0
                M.power2 = CountUnitsNearObject(M.last_geyser, 400, 2, "abwpow")
                -- PORT FIX: accept extra power plants; one-plant flow is unchanged.
                if M.power2 >= 1 then
                    M.rebuild5_prep = false
                    M.rebuilding5 = false
                end
            end
            if (M.rebuilding6)  and  (M.alt_check < GetTime()) then
                M.alt_check = GetTime() + 10.0
                M.tower2 = CountUnitsNearObject(M.last_geyser, 400, 2, "abtowe")
                -- PORT FIX: accept extra towers; one-tower flow is unchanged.
                if M.tower2 >= 1 then
                    M.rebuild6_prep = false
                    M.rebuilding6 = false
                end
            end
        end
    end
    -- this is the attemp at the tank encounter
    if (M.plan_c)  and  (not M.recycle_message) then
        if (IsAlive(M.sav1))  or  (IsAlive(M.sav2))  or  (IsAlive(M.sav3))  or  (IsAlive(M.sav4))  or  (IsAlive(M.sav5))  or  (IsAlive(M.sav6)) then
            AudioMessage("misns816.wav")
            M.savs_alive = true
            M.recycle_message = true
        else
            AudioMessage("misns815.wav")
            M.recycle_message = true
        end
    end
    if (M.plan_c)  and  (not M.general_spawn) then
        M.key_tank = BuildObject ("svtank", 1, "romeski_spawn")
        if IsAlive(M.avrecycle) then
            SetPerceivedTeam(M.avrecycle, 1)
            Follow(M.key_tank, M.sv_geyser, 1)
        end
        if IsAlive(M.basetower1) then
            SetPerceivedTeam(M.basetower1, 1)
        end
        if IsAlive(M.basetower2) then
            SetPerceivedTeam(M.basetower2, 1)
        end
        if IsAlive(M.avtower1) then
            SetPerceivedTeam(M.avtower1, 1)
        end
        if IsAlive(M.powerplant1) then
            SetPerceivedTeam(M.powerplant1, 1)
        end
        if IsAlive(M.powerplant2) then
            SetPerceivedTeam(M.powerplant2, 1)
        end
        if IsAlive(M.avpower1) then
            SetPerceivedTeam(M.avpower1, 1)
        end
        if IsAlive(M.avmuf) then
            SetPerceivedTeam(M.avmuf, 1)
        end
        M.pay_off = GetTime() + 5.0
        -- for big finish
        M.sav_check = GetTime() + 10.0
        M.general_spawn = true
    end
    if (M.general_spawn)  and  (not M.general_message1)  and  (M.pay_off < GetTime()) then
        M.pay_off = GetTime() + 2.0
        if (IsAlive(M.key_tank))  and  (Distance(M.user, M.key_tank) < 150.0) then
            SetObjectiveOn(M.key_tank)
            SetObjectiveName(M.key_tank, "Romeski")
            if not M.sav_payback then
                --				AudioMessage("win.wav"); //glad you could make it commander now watch as I destroy the recycler
                Attack(M.key_tank, M.avrecycle, 1)
            end
            M.general_message1 = true
        end
    end
    --[=[/*
	// this sends savs to recycler when there is no romeski
	if ((recycle_message) && (IsAlive(avrecycle)) && (!general_spawn))
	{
		if ((!sav1_lost) && (IsAlive(sav1)))
		{
			Follow(sav1, avrecycle, 1);
			sav1_lost = true;
			if ((!savs_alive) && (!general_dead))
			{
				AudioMessage("misns807.wav");
				savs_alive = true;
			}
		}
		if ((!sav2_lost) && (IsAlive(sav2)))
		{
			Follow(sav2, avrecycle, 1);
			sav2_lost = true;
			if ((!savs_alive) && (!general_dead))
			{
				AudioMessage("misns807.wav");
				savs_alive = true;
			}
		}
		if ((!sav3_lost) && (IsAlive(sav3)))
		{
			Follow(sav3, avrecycle, 1);
			sav3_lost = true;
			if ((!savs_alive) && (!general_dead))
			{
				AudioMessage("misns807.wav");
				savs_alive = true;
			}
		}
		if ((!sav4_lost) && (IsAlive(sav4)))
		{
			Follow(sav4, avrecycle, 1);
			sav4_lost = true;
			if ((!savs_alive) && (!general_dead))
			{
				AudioMessage("misns807.wav");
				savs_alive = true;
			}
		}
		if ((!sav5_lost) && (IsAlive(sav5)))
		{
			Follow(sav5, avrecycle, 1);
			sav5_lost = true;
			if ((!savs_alive) && (!general_dead))
			{
				AudioMessage("misns807.wav");
				savs_alive = true;
			}
		}
		if ((!sav6_lost) && (IsAlive(sav6)))
		{
			Follow(sav6, avrecycle, 1);
			sav6_lost = true;
			if ((!savs_alive) && (!general_dead))
			{
				AudioMessage("misns807.wav");
				savs_alive = true;
			}
		}
	}
*/]=]
    if (M.general_spawn)  and  (IsAlive(M.key_tank)) then
        if (not M.sav1_togeneral)  and  (IsAlive(M.sav1)) then
            Follow(M.sav1, M.key_tank, 1)
            M.sav1_togeneral = true
            if (not M.savs_alive)  and  (not M.general_dead) then
                AudioMessage("misns807.wav")
                M.savs_alive = true
            end
        end
        if (not M.sav2_togeneral)  and  (IsAlive(M.sav2)) then
            Follow(M.sav2, M.key_tank, 1)
            M.sav2_togeneral = true
            if (not M.savs_alive)  and  (not M.general_dead) then
                AudioMessage("misns807.wav")
                M.savs_alive = true
            end
        end
        if (not M.sav3_togeneral)  and  (IsAlive(M.sav3)) then
            Follow(M.sav3, M.key_tank, 1)
            M.sav3_togeneral = true
            if (not M.savs_alive)  and  (not M.general_dead) then
                AudioMessage("misns807.wav")
                M.savs_alive = true
            end
        end
        if (not M.sav4_togeneral)  and  (IsAlive(M.sav4)) then
            Follow(M.sav4, M.key_tank, 1)
            M.sav4_togeneral = true
            if (not M.savs_alive)  and  (not M.general_dead) then
                AudioMessage("misns807.wav")
                M.savs_alive = true
            end
        end
        if (not M.sav5_togeneral)  and  (IsAlive(M.sav5)) then
            Follow(M.sav5, M.key_tank, 1)
            M.sav5_togeneral = true
            if (not M.savs_alive)  and  (not M.general_dead) then
                AudioMessage("misns807.wav")
                M.savs_alive = true
            end
        end
        if (not M.sav6_togeneral)  and  (IsAlive(M.sav6)) then
            Follow(M.sav6, M.key_tank, 1)
            M.sav6_togeneral = true
            if (not M.savs_alive)  and  (not M.general_dead) then
                AudioMessage("misns807.wav")
                M.savs_alive = true
            end
        end
    end
    if M.sav_check < GetTime() then
        M.sav_check = GetTime() + 10.0
        if (IsAlive(M.sav1))  and  (M.sav1_togeneral)  and  (not M.sav1_attack) then
            if (IsAlive(M.key_tank))  and  (Distance(M.sav1, M.key_tank) < 200.0) then
                --				Defend(key_tank);
                Attack(M.sav1, M.key_tank, 1)
                M.sav_attack = true
                M.sav1_attack = true
            end
        end
        if (IsAlive(M.sav2))  and  (M.sav2_togeneral)  and  (not M.sav2_attack) then
            if (IsAlive(M.key_tank))  and  (Distance(M.sav2, M.key_tank) < 200.0) then
                --				Defend(key_tank);
                Attack(M.sav2, M.key_tank, 1)
                M.sav_attack = true
                M.sav2_attack = true
            end
        end
        if (IsAlive(M.sav3))  and  (M.sav3_togeneral)  and  (not M.sav3_attack) then
            if (IsAlive(M.key_tank))  and  (Distance(M.sav3, M.key_tank) < 200.0) then
                --				Defend(key_tank);
                Attack(M.sav3, M.key_tank, 1)
                M.sav_attack = true
                M.sav3_attack = true
            end
        end
        if (IsAlive(M.sav4))  and  (M.sav4_togeneral)  and  (not M.sav4_attack) then
            if (IsAlive(M.key_tank))  and  (Distance(M.sav4, M.key_tank) < 200.0) then
                --				Defend(key_tank);
                Attack(M.sav4, M.key_tank, 1)
                M.sav_attack = true
                M.sav4_attack = true
            end
        end
        if (IsAlive(M.sav5))  and  (M.sav5_togeneral)  and  (not M.sav5_attack) then
            if (IsAlive(M.key_tank))  and  (Distance(M.sav5, M.key_tank) < 200.0) then
                --				Defend(key_tank);
                Attack(M.sav5, M.key_tank, 1)
                M.sav_attack = true
                M.sav5_attack = true
            end
        end
        if (IsAlive(M.sav6))  and  (M.sav6_togeneral)  and  (not M.sav6_attack) then
            if (IsAlive(M.key_tank))  and  (Distance(M.sav6, M.key_tank) < 200.0) then
                --				Defend(key_tank);
                Attack(M.sav6, M.key_tank, 1)
                M.sav_attack = true
                M.sav6_attack = true
            end
        end
    end
    if ((M.sav1_togeneral)  or  (M.sav2_togeneral)  or  (M.sav3_togeneral)  or 
		(M.sav4_togeneral)  or  (M.sav5_togeneral)  or  (M.sav6_togeneral))  and  (not M.danger_message) then
        AudioMessage("misns805.wav")
        AudioMessage("misns818.wav")
        M.danger_message = true
    end
    -- this gives romeski health
    if (IsAlive(M.key_tank))  and  (not M.key_open) then
        if GetTime() > M.next_second2 then
            AddHealth(M.key_tank, 300.0)
            M.next_second2 = GetTime() + 1.0
        end
    end
    -- this determines who shot him
    -- if the decision hasn't been made...
    if (not M.player_payback)  and  (not M.sav_payback) then
        -- the player
        if IsAlive(M.key_tank) then
            -- who shot this vehicle?
            -- Stock Lua equivalent of GetWhoTheHellShotMe. Normalize no attacker
            -- to native 0 so empty SAV slots never count as the first shooter.
            local shot_by = (GetWhoShotMe(M.key_tank) or 0)
            if shot_by ~= 0 then
                -- if the player shot him...
                if M.user == shot_by then
                    -- "want to attack me huh?! We'll see."
                    AudioMessage("misns819.wav")
                    Attack(M.key_tank, M.user, 1)
                    M.key_open = true
                    M.player_payback = true
                else
                    -- did an SAV shoot it?
                    if (M.badsav1 == shot_by)  or 
					(M.badsav2 == shot_by)  or 
					(M.badsav3 == shot_by)  or 
					(M.badsav4 == shot_by)  or 
					(M.badsav5 == shot_by)  or 
					(M.badsav6 == shot_by) then
                        -- "help me!"
                        --				AudioMessage("misns817.wav");
                        M.help_me_check = GetTime() + 5.0
                        M.key_open = true
                        M.sav_payback = true
                    end
                end
            end
        end
    end
    if (M.sav_payback)  and  (not M.general_message3)  and  (IsAlive(M.key_tank))  and  
		(GetHealth(M.key_tank) < 0.80)  and  (not M.general_message2) then
        AudioMessage("misns817.wav")
        M.general_message3 = true
    end
    -- romeski is attacked by savs and them gets close to player he asks for help
    if (M.sav_payback)  and  (not M.general_message2)  and  (M.help_me_check < GetTime()) then
        M.help_me_check = GetTime() + 3.0
        if (IsAlive(M.key_tank))  and  (Distance(M.key_tank, M.user) < 130.0) then
            Follow(M.key_tank, M.user, 1)
            AudioMessage("misns810.wav")
            M.general_message2 = true
        end
    end
    -- this is killing Romeski
    if (IsAlive(M.key_tank))  and  (not M.general_scream) then
        if (GetHealth(M.key_tank) < 0.10) then
            AudioMessage("misns812.wav")
            M.damage_time = GetTime() + 3.0
            M.general_scream = true
        end
    end
    if (M.general_scream)  and  (M.damage_time < GetTime())  and  (not M.general_dead) then
        if IsAlive(M.key_tank) then
            Damage(M.key_tank, 1000)
            M.general_dead = true
        else
            M.general_dead = true
        end
    end
    if (M.general_spawn)  and  ((not IsAlive(M.key_tank))  or  (M.sav_attack)) then
        if (not M.sav1_swap)  and  (IsAlive(M.sav1)) then
            M.badsav1 = BuildObject("savs8", 2, M.sav1)
            SetIndependence(M.badsav1, 1)
            RemoveObject(M.sav1)
            if IsAlive(M.key_tank) then
                Attack(M.badsav1, M.key_tank, 1)
            end
            if not M.danger_message then
                AudioMessage("misns805.wav")
                M.danger_message = true
            end
            M.sav1_swap = true
        end
        if (not M.sav2_swap)  and  (IsAlive(M.sav2)) then
            M.badsav2 = BuildObject("savs8", 2, M.sav2)
            SetIndependence(M.badsav2, 1)
            RemoveObject(M.sav2)
            if IsAlive(M.key_tank) then
                Attack(M.badsav2, M.key_tank, 1)
            end
            if not M.danger_message then
                AudioMessage("misns805.wav")
                M.danger_message = true
            end
            M.sav2_swap = true
        end
        if (not M.sav3_swap)  and  (IsAlive(M.sav3)) then
            M.badsav3 = BuildObject("savs8", 2, M.sav3)
            SetIndependence(M.badsav3, 1)
            RemoveObject(M.sav3)
            if IsAlive(M.key_tank) then
                Attack(M.badsav3, M.key_tank, 1)
            end
            if not M.danger_message then
                AudioMessage("misns805.wav")
                M.danger_message = true
            end
            M.sav3_swap = true
        end
        if (not M.sav4_swap)  and  (IsAlive(M.sav4)) then
            M.badsav4 = BuildObject("savs8", 2, M.sav4)
            SetIndependence(M.badsav4, 1)
            RemoveObject(M.sav4)
            if IsAlive(M.key_tank) then
                Attack(M.badsav4, M.key_tank, 1)
            end
            if not M.danger_message then
                AudioMessage("misns805.wav")
                M.danger_message = true
            end
            M.sav4_swap = true
        end
        if (not M.sav5_swap)  and  (IsAlive(M.sav5)) then
            M.badsav5 = BuildObject("savs8", 2, M.sav5)
            SetIndependence(M.badsav5, 1)
            RemoveObject(M.sav5)
            if IsAlive(M.key_tank) then
                Attack(M.badsav5, M.key_tank, 1)
            end
            if not M.danger_message then
                AudioMessage("misns805.wav")
                M.danger_message = true
            end
            M.sav5_swap = true
        end
        if (not M.sav6_swap)  and  (IsAlive(M.sav6)) then
            M.badsav6 = BuildObject("savs8", 2, M.sav6)
            SetIndependence(M.badsav6, 1)
            RemoveObject(M.sav6)
            if IsAlive(M.key_tank) then
                Attack(M.badsav6, M.key_tank, 1)
            end
            if not M.danger_message then
                AudioMessage("misns805.wav")
                M.danger_message = true
            end
            M.sav6_swap = true
        end
    end
    -- win/ loose conditions
    if (not IsAlive(M.avrecycle))  and  (not M.game_over) then
        if IsAlive(M.badsav1) then
            Goto(M.badsav1, M.first_geyser, 1)
        end
        if IsAlive(M.badsav2) then
            Goto(M.badsav2, M.first_geyser, 1)
        end
        if IsAlive(M.badsav3) then
            Goto(M.badsav3, M.first_geyser, 1)
        end
        if IsAlive(M.badsav4) then
            Goto(M.badsav4, M.first_geyser, 1)
        end
        if IsAlive(M.badsav5) then
            Goto(M.badsav5, M.first_geyser, 1)
        end
        if IsAlive(M.badsav6) then
            Goto(M.badsav6, M.first_geyser, 1)
        end
        if IsAlive(M.key_tank) then
            AudioMessage("misns803.wav")
            -- congradulations
            AudioMessage("misns808.wav")
            SucceedMission(GetTime() + 35.0, "misns8w1.des")
            M.game_over = true
        else
            AudioMessage("misns814.wav")
            SucceedMission(GetTime() + 25.0, "misns8w1.des")
            M.game_over = true
        end
    end
end

function Save()
    return M
end

function Load(state)
    -- LuaMission restores serialized handles. Do not replay Setup/startup or
    -- reset construction, convoy, betrayal, audio, or victory timers on load.
    M = state
end
