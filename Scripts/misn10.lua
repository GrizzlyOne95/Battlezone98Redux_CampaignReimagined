-- Faithful stock misn10 port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misn10Mission.cpp
-- Source blob: 1e000fdc8e95fa7c58009b249031bb420c789980.
-- Disabled C++ is retained in place; full source and native serialization are
-- archived in References/Misn10Source/. See Docs/MISN10_SOURCE_PORT.md.
-- Single player; no EXU/OpenShim or campaign helper dependency.
local M

local function NewState()
    local state = {}
    state.start_done = false
    state.sav_moved = false
    state.base_dead = false
    state.build_tug = false
    state.making_another_tug = false
    state.made_another_tug = false
    state.position1 = false
    state.position2 = false
    state.position3 = false
    state.position4 = false
    state.position5 = false
    state.position6 = false
    state.position7 = false
    state.sav_seized = false
    state.sav_free = false
    state.sav_secure = false
    state.tug_underway1 = false
    state.tug_underway2 = false
    state.tug_underway3 = false
    state.tug_underway4 = false
    state.tug_underway5 = false
    state.tug_underway6 = false
    state.tug_underway7 = false
    state.tug_wait_center = false
    state.tug_wait2 = false
    state.tug_wait3 = false
    state.tug_wait4 = false
    state.tug_wait5 = false
    state.tug_wait6 = false
    state.tug_wait7 = false
    state.tug_wait_base = false
    state.return_to_base = false
    state.tug_after_sav = false
    state.objective_on = false
    state.tug_at_wait_center = false
    state.relic_free = false
    state.new_aipa = false
    state.new_aipb = false
    state.fighters_underway = false
    state.sav_protected = false
    state.turret1_underway = false
    state.turret2_underway = false
    state.turret3_underway = false
    state.turret1_stop = false
    state.turret2_stop = false
    state.artil1_stop = false
    state.artil2_stop = false
    state.artil3_stop = false
    state.artil1_underway = false
    state.artil2_underway = false
    state.artil3_underway = false
    state.got_position = false
    state.fighter1_underway = false
    state.fighter2_underway = false
    state.tank1_follow = false
    state.tank2_follow = false
    state.tank1_stop = false
    state.tank2_stop = false
    state.plan_a = false
    state.plan_b = false
    state.new_sav_built = false
    state.game_over = false
    state.chase_tug = false
    state.sav_warning = false
    state.player_dead = false
    state.quake = false
    state.gech_warning_message = 99999.0
    state.relic_check = 99999.0
    state.build_sav_time = 99999.0
    state.quake_time = 99999.0
    state.build_another_tug_time = 99999.0
    state.fighter_time = 99999.0
    state.artil1_check = 99999.0
    state.artil2_check = 99999.0
    state.artil3_check = 99999.0
    state.turret1_check = 99999.0
    state.turret2_check = 99999.0
    state.next_second = 99999.0
    state.geys1check = 99999.0
    state.user = nil
    state.ccatug = nil
    state.tugger = nil
    state.sav = nil
    state.nav1 = nil
    state.nav2 = nil
    state.nav3 = nil
    state.ccaartil1 = nil
    state.ccaartil2 = nil
    state.ccaartil3 = nil
    state.ccaturret1 = nil
    state.ccaturret2 = nil
    state.ccaturret3 = nil
    state.ccarecycle = nil
    state.ccamuf = nil
    state.nsdfrecycle = nil
    state.ccafighter1 = nil
    state.ccafighter2 = nil
    state.ccatank1 = nil
    state.ccatank2 = nil
    state.post1_geyser = nil
    state.post3_geyser = nil
    state.geys1 = nil
    state.geys2 = nil
    state.geys3 = nil
    state.geys4 = nil
    state.geys5 = nil
    state.geys6 = nil
    state.geys7 = nil
    state.svartil1 = nil
    state.svartil2 = nil
    state.audmsg = 0
    return state
end
M = NewState()

-- The native AiMission supplies strategic AI. LuaMission must enable it before
-- initialization; later SetAIControl calls can crash stock Redux.
SetAIControl(2, true)

-- Lua handle/position overloads must not receive an absent object. Infinity
-- keeps missing references outside every proximity trigger without changing
-- any comparison between valid objects.
local function Distance(from, to)
    if from == nil or from == 0 or not IsValid(from) then return math.huge end
    if to == nil or to == 0 or not IsValid(to) then return math.huge end
    return GetDistance(from, to)
end

local function IsOdfBase(h, name)
    return IsValid(h) and (IsOdf(h, name) or IsOdf(h, name .. ".odf"))
end

-- BUGFIX: native AddObject tests only NULL and never clears these slots here.
-- Lua retains dead handles, so later AIP-built replacements would be ignored.
-- Reset each dead unit's command flags before assigning its replacement. This
-- preserves living-unit selection/order and the existing AIP production flow;
-- it also handles deletion and replacement between two Update callbacks.
local function ResetUnit(slot)
    if slot == "ccatug" then
        for index = 1, 7 do M["tug_underway" .. index] = false end
        for index = 2, 7 do M["tug_wait" .. index] = false end
        M.tug_after_sav = false
        M.return_to_base = false
        M.tug_wait_center = false
        M.tug_wait_base = false
        M.tug_at_wait_center = false
        M.got_position = false
        M.sav_warning = false
        -- Each new carrier needs fresh escort orders; the source leaves the
        -- surviving tanks' old follow flags set after their carrier is lost.
        M.tank1_follow = false
        M.tank2_follow = false
        if M.sav_seized then
            if IsAlive(M.ccatank1) and IsAlive(M.sav) then Goto(M.ccatank1, M.sav) end
            if IsAlive(M.ccatank2) and IsAlive(M.sav) then Goto(M.ccatank2, M.sav) end
            M.sav_seized = false
            M.sav_free = true
        end
    elseif slot == "ccaturret3" then
        -- The third turret otherwise keeps its old underway flag forever.
        M.turret3_underway = false
    else
        local kind, index = string.match(slot, "^cca(%a+)(%d)$")
        if kind == "turret" or kind == "artil" then
            M[kind .. index .. "_underway"] = false
            M[kind .. index .. "_stop"] = false
        elseif kind == "fighter" then
            M["fighter" .. index .. "_underway"] = false
            M.chase_tug = false
        elseif kind == "tank" then
            M["tank" .. index .. "_follow"] = false
            M["tank" .. index .. "_stop"] = false
            M.chase_tug = false
        end
    end
end

local trackedSlots = {
    {"ccatug", "svhaul"},
    {"ccaartil1", "svartl"}, {"ccaartil2", "svartl"}, {"ccaartil3", "svartl"},
    {"ccaturret1", "svturr"}, {"ccaturret2", "svturr"}, {"ccaturret3", "svturr"},
    {"ccafighter1", "svfigh"}, {"ccafighter2", "svfigh"},
    {"ccatank1", "svltnk"}, {"ccatank2", "svltnk"}, {"ccamuf", "svmuf"},
}

function Start()
    M = NewState()
    --[==[/*
Here's where you set the values at the start.  
*/]==]
    M.start_done = false
    M.sav_moved = false
    M.base_dead = false
    M.player_dead = false
    M.making_another_tug = false
    M.made_another_tug = false
    M.build_tug = false
    M.position1 = false
    M.position2 = false
    M.position3 = false
    M.position4 = false
    M.position5 = false
    M.position6 = false
    M.position7 = false
    M.tug_underway1 = false
    M.tug_underway2 = false
    M.tug_underway3 = false
    M.tug_underway4 = false
    M.tug_underway5 = false
    M.tug_underway6 = false
    M.tug_underway7 = false
    M.tug_after_sav = false
    M.sav_seized = false
    M.sav_free = true
    M.sav_secure = false
    M.return_to_base = false
    M.tug_wait_center = false
    M.tug_wait2 = false
    M.tug_wait3 = false
    M.tug_wait4 = false
    M.tug_wait5 = false
    M.tug_wait6 = false
    M.tug_wait7 = false
    M.tug_wait_base = false
    M.tug_at_wait_center = false
    M.objective_on = false
    M.new_aipa = false
    M.new_aipb = false
    M.relic_free = true
    M.fighters_underway = false
    M.sav_protected = false
    M.turret1_underway = false
    M.turret2_underway = false
    M.turret3_underway = false
    M.turret1_stop = false
    M.turret2_stop = false
    M.artil1_stop = false
    M.artil2_stop = false
    M.artil3_stop = false
    M.got_position = false
    M.fighter1_underway = false
    M.fighter2_underway = false
    M.tank1_follow = false
    M.tank2_follow = false
    M.tank1_stop = false
    M.tank2_stop = false
    M.plan_a = false
    M.plan_b = false
    M.artil1_underway = false
    M.artil2_underway = false
    M.artil3_underway = false
    M.game_over = false
    M.chase_tug = false
    M.sav_warning = false
    M.quake = false
    M.new_sav_built = false
    --temp
    M.gech_warning_message = 99999.0
    M.build_sav_time = 99999.0
    --temp
    M.build_another_tug_time = 99999.0
    M.relic_check = 99999.0
    M.fighter_time = 99999.0
    M.turret1_check = 99999.0
    M.turret2_check = 99999.0
    M.artil1_check = 99999.0
    M.artil2_check = 99999.0
    M.artil3_check = 99999.0
    M.geys1check = 180.0
    M.quake_time = 4.0
    M.next_second = 0
    M.sav = GetHandle("relic")
    M.nav1 = GetHandle("cam1")
    M.nav2 = GetHandle("cam2")
    M.nav3 = GetHandle("cam3")
    M.ccarecycle = GetHandle("svrecycler")
    M.nsdfrecycle = GetHandle("avrecycler")
    M.post1_geyser = GetHandle("post1_geyser")
    M.post3_geyser = GetHandle("post3_geyser")
    M.geys1 = GetHandle("geyser1")
    M.geys2 = GetHandle("geyser2")
    M.geys3 = GetHandle("geyser3")
    M.geys4 = GetHandle("geyser4")
    M.geys5 = GetHandle("geyser5")
    M.geys6 = GetHandle("geyser6")
    M.geys7 = GetHandle("geyser7")
    M.svartil1 = GetHandle("svartil1")
    M.svartil2 = GetHandle("svartil2")
    M.ccatug = nil
    M.ccaartil1 = nil
    M.ccaartil2 = nil
    M.ccaartil3 = nil
    M.ccaturret1 = nil
    M.ccaturret2 = nil
    M.ccaturret3 = nil
    M.ccafighter1 = nil
    M.ccafighter2 = nil
    M.ccatank1 = nil
    M.ccatank2 = nil
    M.ccamuf = GetHandle("svmuf")
    M.tugger = nil
end

function AddObject(h)
    if not IsValid(h) then return end
    -- Preserve the native ODF-only admission rule and first vacant slot order.
    -- Duplicate notifications must not occupy two slots with the same unit.
    for _, entry in ipairs(trackedSlots) do
        if M[entry[1]] == h then return end
    end
    for _, entry in ipairs(trackedSlots) do
        local slot, odf = entry[1], entry[2]
        if not IsAlive(M[slot]) and IsOdfBase(h, odf) then
            ResetUnit(slot)
            M[slot] = h
            return
        end
    end
end

function DeleteObject(h)
    -- Compare cached handles only; destroyed-object properties are unsafe here.
    for _, entry in ipairs(trackedSlots) do
        local slot = entry[1]
        if M[slot] == h then
            ResetUnit(slot)
            M[slot] = nil
        end
    end
end

function Update(dt)
    --[==[/*
Here is where you put what happens every frame.  
*/]==]
    if (M.sav_free) and (IsAlive(M.sav)) then
        M.tugger = GetTug(M.sav)
        if IsAlive(M.tugger) then
            if GetTeamNum(M.tugger) == 1 then
                M.sav_free = false
                M.sav_secure = true
            else
                M.sav_free = false
                M.sav_seized = true
                M.tugger = M.ccatug
            end
        end
    end
    if (M.sav_secure) and (not IsAlive(M.tugger)) then
        if not M.sav_seized then
            M.sav_free = true
            M.chase_tug = false
            M.got_position = false
            M.sav_secure = false
            M.fighter1_underway = false
            M.fighter2_underway = false
        end
    end
    --[==[/*	if (IsAlive(sav))
	{
		if (IsAlive(ccatug))
		{
			if (HasCargo(ccatug))
			{
				sav_free = false;
				sav_seized = true;
			}
			else
			{
				if (!sav_secure)
				{
					sav_free = true;
					sav_seized = false;
				}
			}
		}

		if (!sav_seized)
		{
			tugger = GetTug(sav);

			if (tugger !=0)
			{
				if (GetTeamNum(tugger) == 1)
				{
					sav_free = false;
					sav_secure = true;
				}
				else
				{
					sav_free = false;
					sav_seized = true;
					tugger = ccatug;
				}
			}
		}

		if ((sav_secure) && (!IsAlive(tugger)))
		{
			if (!sav_seized)
			{
				sav_free = true;
				chase_tug = false;
				got_position = false;
				sav_secure = false;
				fighter1_underway = false;
				fighter2_underway = false;
			}
		}
	}
*/]==]
    if (M.sav_seized) and (not IsAlive(M.ccatug)) then
        if (IsAlive(M.ccatank1)) and (IsAlive(M.sav)) then
            Goto(M.ccatank1, M.sav)
        end
        if (IsAlive(M.ccatank2)) and (IsAlive(M.sav)) then
            Goto(M.ccatank2, M.sav)
        end
        M.sav_seized = false
        M.got_position = false
        M.sav_free = true
    end
    if not IsAlive(M.ccatug) then
        --////////////////////////
        M.tug_underway1 = false
        M.tug_underway2 = false
        M.tug_underway3 = false
        M.tug_underway4 = false
        M.tug_underway5 = false
        M.tug_underway6 = false
        M.tug_underway7 = false
        M.tug_after_sav = false
        --all tug settings reset because the last tug was destroyed
        M.return_to_base = false
        M.tug_wait_center = false
        M.tug_wait2 = false
        M.tug_wait3 = false
        M.tug_wait4 = false
        M.tug_wait5 = false
        M.tug_wait6 = false
        M.tug_wait7 = false
        M.tug_wait_base = false
        M.tug_at_wait_center = false
        M.got_position = false
        M.sav_warning = false
        -- BUGFIX: allow the surviving tanks to follow the next AIP-built tug.
        -- This only resets stale orders after carrier death, preserving the
        -- original escort behavior for every living carrier.
        M.tank1_follow = false
        M.tank2_follow = false
        --////////////////////////
    end
    if (M.sav_seized) and (not M.sav_warning) then
        AudioMessage("misn1005.wav")
        -- the sav is being taken sir
        M.sav_warning = true
    end
    M.user = GetPlayerHandle()
    --assigns the player a handle every frame
    -- constant variables
    if not IsAlive(M.ccaturret1) then
        M.turret1_underway = false
        M.turret1_stop = false
    end
    if not IsAlive(M.ccaturret2) then
        M.turret2_underway = false
        M.turret2_stop = false
    end
    if not IsAlive(M.ccaartil1) then
        M.artil1_stop = false
        M.artil1_underway = false
    end
    if not IsAlive(M.ccaartil2) then
        M.artil2_stop = false
        M.artil2_underway = false
    end
    if not IsAlive(M.ccaartil3) then
        M.artil3_stop = false
        M.artil3_underway = false
    end
    if not IsAlive(M.ccafighter1) then
        M.fighter1_underway = false
        M.chase_tug = false
    end
    if not IsAlive(M.ccafighter2) then
        M.fighter2_underway = false
        M.chase_tug = false
    end
    if not IsAlive(M.ccatank1) then
        M.tank1_follow = false
        M.tank1_stop = false
        M.chase_tug = false
    end
    if not IsAlive(M.ccatank2) then
        M.tank2_follow = false
        M.tank2_stop = false
        M.chase_tug = false
    end
    -- the first thing I want to do is get the position of the sav
    if (IsAlive(M.ccatug)) and (M.sav_free) and (not M.got_position) then
        local route_found = false
        if ((Distance(M.sav, M.geys1)) < (Distance(M.sav, M.geys2))) and ((Distance(M.sav, M.geys1)) < (Distance(M.sav, M.geys3))) and ((Distance(M.sav, M.geys1)) < (Distance(M.sav, M.geys4))) and ((Distance(M.sav, M.geys1)) < (Distance(M.sav, M.geys5))) and ((Distance(M.sav, M.geys1)) < (Distance(M.sav, M.geys6))) and ((Distance(M.sav, M.geys1)) < (Distance(M.sav, M.geys7))) then
            M.position1 = true
            route_found = true
            --
            M.position2 = false
            --
            M.position3 = false
            -- this code gets the position of the relic so I can determine 
            M.position4 = false
            -- which path to send the cca tug down and back
            M.position5 = false
            --
            M.position6 = false
            --
            M.position7 = false
            --
        else
            if ((Distance(M.sav, M.geys2)) < (Distance(M.sav, M.geys1))) and ((Distance(M.sav, M.geys2)) < (Distance(M.sav, M.geys3))) and ((Distance(M.sav, M.geys2)) < (Distance(M.sav, M.geys4))) and ((Distance(M.sav, M.geys2)) < (Distance(M.sav, M.geys5))) and ((Distance(M.sav, M.geys2)) < (Distance(M.sav, M.geys6))) and ((Distance(M.sav, M.geys2)) < (Distance(M.sav, M.geys7))) then
                M.position1 = false
                --
                M.position2 = true
                route_found = true
                --
                M.position3 = false
                -- this code gets the position of the relic so I can determine 
                M.position4 = false
                -- which path to send the cca tug down and back
                M.position5 = false
                --
                M.position6 = false
                --
                M.position7 = false
                --
            else
                if ((Distance(M.sav, M.geys3)) < (Distance(M.sav, M.geys1))) and ((Distance(M.sav, M.geys3)) < (Distance(M.sav, M.geys2))) and ((Distance(M.sav, M.geys3)) < (Distance(M.sav, M.geys4))) and ((Distance(M.sav, M.geys3)) < (Distance(M.sav, M.geys5))) and ((Distance(M.sav, M.geys3)) < (Distance(M.sav, M.geys6))) and ((Distance(M.sav, M.geys3)) < (Distance(M.sav, M.geys7))) then
                    M.position1 = false
                    --
                    M.position2 = false
                    --
                    M.position3 = true
                    route_found = true
                    -- this code gets the position of the relic so I can determine 
                    M.position4 = false
                    -- which path to send the cca tug down and back
                    M.position5 = false
                    --
                    M.position6 = false
                    --
                    M.position7 = false
                    --
                else
                    if (not M.sav_seized) and ((Distance(M.sav, M.geys4)) < (Distance(M.sav, M.geys1))) and ((Distance(M.sav, M.geys4)) < (Distance(M.sav, M.geys2))) and ((Distance(M.sav, M.geys4)) < (Distance(M.sav, M.geys3))) and ((Distance(M.sav, M.geys4)) < (Distance(M.sav, M.geys5))) and ((Distance(M.sav, M.geys4)) < (Distance(M.sav, M.geys6))) and ((Distance(M.sav, M.geys4)) < (Distance(M.sav, M.geys7))) then
                        M.position1 = false
                        --
                        M.position2 = false
                        --
                        M.position3 = false
                        -- this code gets the position of the relic so I can determine 
                        M.position4 = true
                        route_found = true
                        -- which path to send the cca tug down and back
                        M.position5 = false
                        --
                        M.position6 = false
                        --
                        M.position7 = false
                        --
                    else
                        if ((Distance(M.sav, M.geys5)) < (Distance(M.sav, M.geys1))) and ((Distance(M.sav, M.geys5)) < (Distance(M.sav, M.geys2))) and ((Distance(M.sav, M.geys5)) < (Distance(M.sav, M.geys3))) and ((Distance(M.sav, M.geys5)) < (Distance(M.sav, M.geys4))) and ((Distance(M.sav, M.geys5)) < (Distance(M.sav, M.geys6))) and ((Distance(M.sav, M.geys5)) < (Distance(M.sav, M.geys7))) then
                            M.position1 = false
                            --
                            M.position2 = false
                            --
                            M.position3 = false
                            --
                            M.position4 = false
                            -- this code gets the position of the relic so I can determine 
                            M.position5 = true
                            route_found = true
                            -- which path to send the cca tug down and back
                            M.position6 = false
                            --
                            M.position7 = false
                            --
                        else
                            if ((Distance(M.sav, M.geys6)) < (Distance(M.sav, M.geys1))) and ((Distance(M.sav, M.geys6)) < (Distance(M.sav, M.geys2))) and ((Distance(M.sav, M.geys6)) < (Distance(M.sav, M.geys3))) and ((Distance(M.sav, M.geys6)) < (Distance(M.sav, M.geys4))) and ((Distance(M.sav, M.geys6)) < (Distance(M.sav, M.geys5))) and ((Distance(M.sav, M.geys6)) < (Distance(M.sav, M.geys7))) then
                                M.position1 = false
                                --
                                M.position2 = false
                                --
                                M.position3 = false
                                -- this code gets the position of the relic so I can determine 
                                M.position4 = false
                                -- which path to send the cca tug down and back
                                M.position5 = false
                                --
                                M.position6 = true
                                route_found = true
                                --
                                M.position7 = false
                                --
                            else
                                if ((Distance(M.sav, M.geys7)) < (Distance(M.sav, M.geys1))) and ((Distance(M.sav, M.geys7)) < (Distance(M.sav, M.geys2))) and ((Distance(M.sav, M.geys7)) < (Distance(M.sav, M.geys3))) and ((Distance(M.sav, M.geys7)) < (Distance(M.sav, M.geys4))) and ((Distance(M.sav, M.geys7)) < (Distance(M.sav, M.geys5))) and ((Distance(M.sav, M.geys7)) < (Distance(M.sav, M.geys6))) then
                                    M.position1 = false
                                    --
                                    M.position2 = false
                                    --
                                    M.position3 = false
                                    -- this code gets the position of the relic so I can determine 
                                    M.position4 = false
                                    -- which path to send the cca tug down and back
                                    M.position5 = false
                                    --
                                    M.position6 = false
                                    --
                                    M.position7 = true
                                    route_found = true
                                    --
                                end
                            end
                        end
                    end
                end
            end
        end
        -- BUGFIX: every original comparison is strict, so an exact nearest
        -- geyser tie selects no route yet sets got_position permanently. Keep
        -- all unique-nearest decisions above. Only when tied, use the lowest
        -- numbered finite minimum; the same seven lava-avoiding paths apply.
        if not route_found and not M.sav_seized then
            local nearest, shortest = nil, math.huge
            for index = 1, 7 do
                local distance = Distance(M.sav, M["geys" .. index])
                if distance < shortest then nearest, shortest = index, distance end
            end
            if nearest then
                for index = 1, 7 do M["position" .. index] = index == nearest end
                route_found = true
            end
        end
        -- Retry rather than commit an empty route if required map labels are absent.
        M.got_position = route_found
    end
    -- now I'll start the mission
    if not M.start_done then
        AudioMessage("misn1000.wav")
        -- player briefing
        ClearObjectives()
        AddObjective("misn1000.otf", "white")
        SetIndependence(M.svartil1, 1)
        SetIndependence(M.svartil2, 1)
        SetScrap(1, 30)
        SetPilot(1, 10)
        SetScrap(2, 40)
        SetPilot(2, 40)
        SetAIP("misn10.aip")
        -- this sets the soviets into action
        --[==[//		build_sav_time = Get_Time() + 120.0f;//temp]==]
        --[==[//		relic_check = Get_Time() + 5.0f;]==]
        M.turret1_check = GetTime() + 19.0
        M.turret2_check = GetTime() + 20.0
        M.artil1_check = GetTime() + 21.0
        M.artil2_check = GetTime() + 22.0
        M.artil3_check = GetTime() + 23.0
        if M.nav1 ~= nil then
            SetObjectiveName(M.nav1, "Relic Site")
        end
        if M.nav2 ~= nil then
            SetObjectiveName(M.nav2, "CCA Base")
        end
        if M.nav3 ~= nil then
            SetObjectiveName(M.nav3, "Drop Zone")
        end
        M.relic_free = true
        M.start_done = true
    end
    if (Distance(M.user, M.sav) < 100.0) and (not M.objective_on) then
        SetObjectiveOn(M.sav)
        SetObjectiveName(M.sav, "Alien Relic")
        M.objective_on = true
    end
    --[==[/*	if ((!quake) && (quake_time < Get_Time()))
	{
		quake_time = Get_Time() + 10.0f;
		StartEarthquake(2.0f);
		quake = true;
	}

	if ((quake) && (quake_time < Get_Time()))
	{
		StopEarthquake();
		quake_time = Get_Time() + 120.0f;
		quake = false;
	}
*/]==]
    -- The first thing the soviets do is secure the sav with fighters
    if (M.relic_free) and (IsAlive(M.ccafighter1)) and (not M.fighter1_underway) then
        Follow(M.ccafighter1, M.sav)
        M.fighter1_underway = true
    end
    if (M.relic_free) and (IsAlive(M.ccafighter2)) and (not M.fighter2_underway) then
        Follow(M.ccafighter2, M.sav)
        M.fighter2_underway = true
    end
    -- now that fighters are protecting the sav the soviets position turrets to assist
    if (IsAlive(M.ccaturret1)) and (not M.turret1_underway) then
        Goto(M.ccaturret1, "relic_path1")
        M.turret1_underway = true
    end
    if (IsAlive(M.ccaturret2)) and (not M.turret2_underway) then
        Goto(M.ccaturret2, "relic_path1")
        M.turret2_underway = true
    end
    if (IsAlive(M.ccaturret3)) and (not M.turret3_underway) then
        if (IsAlive(M.ccarecycle)) and (Distance(M.ccaturret3, M.ccarecycle) > 30.0) then
            Defend(M.ccaturret3)
            M.turret3_underway = true
        end
    end
    -- gets the turrets to stop
    if (M.turret1_underway) and (M.turret1_check < GetTime()) then
        M.turret1_check = GetTime() + 3.0
        if (IsAlive(M.ccaturret1)) and (not M.turret1_stop) and (Distance(M.ccaturret1, M.geys1) < 50.0) then
            Defend(M.ccaturret1)
            M.turret1_stop = true
        end
    end
    if (M.turret2_underway) and (M.turret2_check < GetTime()) then
        M.turret2_check = GetTime() + 3.0
        if (IsAlive(M.ccaturret2)) and (not M.turret2_stop) and (Distance(M.ccaturret2, M.geys2) < 50.0) then
            Defend(M.ccaturret2)
            M.turret2_stop = true
        end
    end
    -- now the soviets will check to see if they can change their first aip
    if (IsAlive(M.ccafighter1)) and (IsAlive(M.ccafighter2)) and (IsAlive(M.ccaturret1)) and (IsAlive(M.ccaturret2)) and (not M.plan_a) then
        if GetScrap(2) > 15.0 then
            SetAIP("misn10a.aip")
            M.plan_a = true
        end
    end
    --[==[/*	if ((IsAlive(ccatank1)) && (!IsAlive(ccatug)) && (!tank1_stop))
	{
		Stop(ccatank1);
		tank1_stop = true;
	}

	if ((IsAlive(ccatank2)) && (!IsAlive(ccatug)) && (!tank2_stop))
	{
		Stop(ccatank2);
		tank2_stop = true;
	}
*/]==]
    -- now they check to see if they can load their next aip
    --[==[//	if ((IsAlive(ccatug)) && (IsAlive(ccatank1)) ]==]
    --		&& (IsAlive(ccatank2)) && (!plan_b))
    --[==[//	{]==]
    --[==[//		SetScrap(2, 40);]==]
    --[==[//		SetAIP("misn10b.aip");]==]
    --[==[//		plan_b = true;]==]
    --[==[//	}]==]
    -- this sets the artillery into motion
    if (IsAlive(M.ccaartil1)) and (not M.artil1_underway) then
        Goto(M.ccaartil1, "artil1_path", 1)
        M.artil1_underway = true
    end
    if (IsAlive(M.ccaartil2)) and (not M.artil2_underway) then
        Goto(M.ccaartil2, "artil2_path", 1)
        M.artil2_underway = true
    end
    if (IsAlive(M.ccaartil3)) and (not M.artil3_underway) then
        Goto(M.ccaartil3, "relic_path1")
        M.artil3_underway = true
    end
    -- this is checking to see if the soviet artil has reached it's spot
    if M.artil1_check < GetTime() then
        M.artil1_check = GetTime() + 3.0
        if (IsAlive(M.ccaartil1)) and (not M.artil1_stop) and (Distance(M.ccaartil1, M.post1_geyser) < 20.0) then
            Defend(M.ccaartil1)
            M.artil1_stop = true
        end
    end
    if M.artil2_check < GetTime() then
        M.artil2_check = GetTime() + 3.0
        if (IsAlive(M.ccaartil2)) and (not M.artil2_stop) and (Distance(M.ccaartil2, M.post3_geyser) < 20.0) then
            Defend(M.ccaartil2)
            M.artil2_stop = true
        end
    end
    if M.artil3_check < GetTime() then
        M.artil3_check = GetTime() + 3.0
        if (IsAlive(M.ccaartil3)) and (not M.artil3_stop) and (Distance(M.ccaartil3, M.geys2) < 50.0) then
            Defend(M.ccaartil3)
            M.artil3_stop = true
        end
    end
    --[==[/*
	if ((build_sav_time < Get_Time()) && (!new_sav_built)) //this will be replaced by "sav_free"
	{
		sav = BuildObject ("abstor", 1, geys7);

		tug_underway1 = false;
		tug_underway2 = false;
		tug_underway3 = false;
		tug_underway4 = false;
		tug_underway5 = false;
		tug_underway6 = false;
		tug_underway7 = false;
		tug_after_sav = false;
		tug_wait_center = false;
		tug_wait2 = false;
		tug_wait3 = false;
		tug_wait4 = false;
		tug_wait5 = false;
		tug_wait6 = false;
		tug_wait7 = false;
		tug_wait_base = false;		
		sav_seized = false;
		new_sav_built = true;
	}
*/]==]
    -- hopefully, the following code will build a cca tug every 30 seconds after the last cca tug is destoyed
    --[==[/*
		if ((!build_tug) && (IsAlive(ccarecycle)))
		{
			ccatug = BuildObject("svhaul", 2, ccarecycle);
			build_tug = true;
		}
		
		if ((build_tug) && (!IsAlive(ccatug)) && (!making_another_tug))
		{
			build_another_tug_time = Get_Time() + 30.0f;
			//////////////////////////
			tug_underway1 = false;	//
			tug_underway2 = false;	//
			tug_underway3 = false;	//
			tug_underway4 = false;	//
			tug_underway5 = false;	// 
			tug_underway6 = false;	//
			tug_underway7 = false;	//
			tug_after_sav = false;	//all tug settings reset because the last tug was destroyed
			return_to_base = false;	//
			tug_wait_center = false;//
			tug_wait2 = false;		//
			tug_wait3 = false;		//
			tug_wait4 = false;		//
			tug_wait5 = false;		//
			tug_wait6 = false;		//
			tug_wait7 = false;		//
			tug_wait_base = false;	//
			tug_at_wait_center = false;
			//////////////////////////
			making_another_tug = true;
		}

		if ((making_another_tug) && (build_another_tug_time < Get_Time()) && (build_tug))
		{
			making_another_tug = false;
			build_tug = false;
		}
*/]==]
    -- now I'm attempting to send the cca tug to the relic in the smartest path /////////////////////////////////////////////////////////////////////////////////////////////////////////
    -- first I determine where the relic on the map by dertermining which geyser its closest to /////////////////////////////////////////////////////////////////////////////////////////
    -- now that I know which geyser the relic closest to I'll send the cca tug down the appropriate path (to keep it out of the lava fields as much as possible //////////////////////////////
    if (IsAlive(M.ccatug)) and (M.got_position) then
        if (IsAlive(M.ccatank1)) and (not M.tank1_follow) then
            Follow(M.ccatank1, M.ccatug, 1)
            M.tank1_follow = true
        end
        if (IsAlive(M.ccatank2)) and (not M.tank2_follow) then
            Follow(M.ccatank2, M.ccatug, 1)
            M.tank2_follow = true
        end
        if (not M.tug_underway1) and (M.sav_free) and (M.position1) and (not M.tug_after_sav) then
            Goto(M.ccatug, "relic_path1", 1)
            M.tug_underway1 = true
        end
        if (M.tug_underway1) and (M.sav_free) and (Distance(M.ccatug, M.sav) < Distance(M.ccatug, M.geys1)) and (Distance(M.ccatug, M.sav) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            if IsAlive(M.ccatank1) then
                Follow(M.ccatank1, M.ccatug, 0)
            end
            if IsAlive(M.ccatank2) then
                Follow(M.ccatank2, M.ccatug, 0)
            end
            M.tug_after_sav = true
        end
        if (M.tug_underway1) and (M.sav_free) and (Distance(M.ccatug, M.geys1) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.sav_free) and (M.position2) and (not M.tug_underway2) and (not M.tug_after_sav) then
            Goto(M.ccatug, "relic_path1", 1)
            M.tug_underway2 = true
        end
        if (M.tug_underway2) and (M.sav_free) and (Distance(M.ccatug, M.sav) < Distance(M.ccatug, M.geys2)) and (Distance(M.ccatug, M.sav) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.tug_underway2) and (M.sav_free) and (Distance(M.ccatug, M.geys2) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.sav_free) and (M.position3) and (not M.tug_underway3) and (not M.tug_after_sav) then
            Goto(M.ccatug, "attack_path_central", 1)
            M.tug_underway3 = true
        end
        if (M.tug_underway3) and (M.sav_free) and (Distance(M.ccatug, M.sav) < Distance(M.ccatug, M.geys3)) and (Distance(M.ccatug, M.sav) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.tug_underway3) and (M.sav_free) and (Distance(M.ccatug, M.geys3) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.sav_free) and (M.position4) and (not M.tug_underway4) and (not M.tug_after_sav) then
            Goto(M.ccatug, "attack_path_central", 1)
            M.tug_underway4 = true
        end
        if (M.tug_underway4) and (M.sav_free) and (Distance(M.ccatug, M.sav) < Distance(M.ccatug, M.geys4)) and (Distance(M.ccatug, M.sav) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.tug_underway4) and (M.sav_free) and (Distance(M.ccatug, M.geys4) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.sav_free) and (M.position5) and (not M.tug_underway5) and (not M.tug_after_sav) then
            Goto(M.ccatug, "attack_path_south", 1)
            M.tug_underway5 = true
        end
        if (M.tug_underway5) and (M.sav_free) and (Distance(M.ccatug, M.sav) < Distance(M.ccatug, M.geys5)) and (Distance(M.ccatug, M.sav) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.tug_underway5) and (M.sav_free) and (Distance(M.ccatug, M.geys5) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.sav_free) and (M.position6) and (not M.tug_underway6) and (not M.tug_after_sav) then
            Goto(M.ccatug, "attack_path_north", 1)
            M.tug_underway6 = true
        end
        if (M.tug_underway6) and (M.sav_free) and (Distance(M.ccatug, M.sav) < Distance(M.ccatug, M.geys6)) and (Distance(M.ccatug, M.sav) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.tug_underway6) and (M.sav_free) and (Distance(M.ccatug, M.geys6) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.sav_free) and (M.position7) and (not M.tug_underway7) and (not M.tug_after_sav) then
            Goto(M.ccatug, "attack_path_south", 1)
            M.tug_underway7 = true
        end
        if (M.tug_underway7) and (M.sav_free) and (Distance(M.ccatug, M.sav) < Distance(M.ccatug, M.geys7)) and (Distance(M.ccatug, M.sav) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        if (M.tug_underway7) and (M.sav_free) and (Distance(M.ccatug, M.geys7) < 100.0) and (not M.tug_after_sav) then
            Pickup(M.ccatug, M.sav, 1)
            M.tug_after_sav = true
        end
        -- now that the tug has picked the correct path I'll have the tug pick up the sav and pick a path home //////////////////////////////////
        if (M.tug_after_sav) and (M.tug_underway1) and (M.sav_seized) and (not M.return_to_base) then
            Goto(M.ccatug, "main_return_path", 1)
            M.return_to_base = true
        end
        if (M.tug_after_sav) and (M.tug_underway2) and (M.sav_seized) and (not M.return_to_base) then
            Goto(M.ccatug, M.ccarecycle, 1)
            M.return_to_base = true
        end
        if (M.tug_after_sav) and (M.tug_underway3) and (M.sav_seized) and (not M.return_to_base) then
            Goto(M.ccatug, "lsouth_return_path", 1)
            M.return_to_base = true
        end
        if (M.tug_after_sav) and (M.tug_underway4) and (M.sav_seized) and (not M.return_to_base) then
            Goto(M.ccatug, "main_return_path", 1)
            M.return_to_base = true
        end
        if (M.tug_after_sav) and (M.tug_underway5) and (M.sav_seized) and (not M.return_to_base) then
            Goto(M.ccatug, "ssouth_return_path", 1)
            M.return_to_base = true
        end
        if (M.tug_after_sav) and (M.tug_underway6) and (M.sav_seized) and (not M.return_to_base) then
            Goto(M.ccatug, "main_return_path", 1)
            M.return_to_base = true
        end
        if (M.tug_after_sav) and (M.tug_underway7) and (M.sav_seized) and (not M.return_to_base) then
            Goto(M.ccatug, "msouth_return_path", 1)
            M.return_to_base = true
        end
    end
    -- this is what happens if the player aquires the relic before the cca and a cca tug exits //////////////////
    if not IsAlive(M.sav) then
        if (M.sav_secure) and (not M.tug_underway1) then
            M.tug_wait_base = true
        end
        if (M.sav_secure) and (M.tug_underway1) then
            M.tug_underway1 = false
            M.tug_wait_center = true
        end
        if (M.sav_secure) and (not M.tug_underway2) then
            M.tug_wait_base = true
        end
    end
    if (M.sav_secure) and (M.tug_underway2) and (Distance(M.ccatug, M.geys2) < 50.0) and (not M.tug_wait2) then
        Goto(M.ccatug, M.geys2, 1)
        M.tug_underway2 = false
        M.tug_wait2 = true
    end
    if (M.sav_secure) and (M.tug_underway2) and (M.tug_after_sav) and (not M.tug_wait2) then
        Goto(M.ccatug, M.geys2, 1)
        M.tug_underway2 = false
        M.tug_after_sav = false
        M.tug_wait2 = true
    end
    if (not IsAlive(M.sav)) and (M.sav_secure) and (not M.tug_underway3) then
        M.tug_wait_base = true
    end
    if (M.sav_secure) and (M.tug_underway3) and (Distance(M.ccatug, M.geys3) < 50.0) and (not M.tug_wait3) then
        Goto(M.ccatug, M.geys3, 1)
        M.tug_underway3 = false
        M.tug_wait3 = true
    end
    if (M.sav_secure) and (M.tug_underway3) and (M.tug_after_sav) and (not M.tug_wait3) then
        Goto(M.ccatug, M.geys3, 1)
        M.tug_underway3 = false
        M.tug_after_sav = false
        M.tug_wait3 = true
    end
    if (not IsAlive(M.sav)) and (M.sav_secure) and (not M.tug_underway4) then
        M.tug_wait_base = true
    end
    if (M.sav_secure) and (M.tug_underway4) and (Distance(M.ccatug, M.geys4) < 50.0) and (not M.tug_wait4) then
        Goto(M.ccatug, M.geys4, 1)
        M.tug_underway4 = false
        M.tug_wait4 = true
    end
    if (M.sav_secure) and (M.tug_underway4) and (M.tug_after_sav) and (not M.tug_wait4) then
        Goto(M.ccatug, M.geys4, 1)
        M.tug_underway4 = false
        M.tug_after_sav = false
        M.tug_wait4 = true
    end
    if (not IsAlive(M.sav)) and (M.sav_secure) and (not M.tug_underway5) then
        M.tug_wait_base = true
    end
    if (M.sav_secure) and (M.tug_underway5) and (Distance(M.ccatug, M.geys5) < 50.0) and (not M.tug_wait5) then
        Goto(M.ccatug, M.geys5, 1)
        M.tug_underway5 = false
        M.tug_wait5 = true
    end
    if (M.sav_secure) and (M.tug_underway5) and (M.tug_after_sav) and (not M.tug_wait5) then
        Goto(M.ccatug, M.geys5, 1)
        M.tug_underway5 = false
        M.tug_after_sav = false
        M.tug_wait5 = true
    end
    if (not IsAlive(M.sav)) and (M.sav_secure) and (not M.tug_underway6) then
        M.tug_wait_base = true
    end
    if (M.sav_secure) and (M.tug_underway6) and (Distance(M.ccatug, M.geys6) < 50.0) and (not M.tug_wait6) then
        Goto(M.ccatug, M.geys6, 1)
        M.tug_underway6 = false
        M.tug_wait6 = true
    end
    if (M.sav_secure) and (M.tug_underway6) and (M.tug_after_sav) and (not M.tug_wait6) then
        Goto(M.ccatug, M.geys6, 1)
        M.tug_underway6 = false
        M.tug_after_sav = false
        M.tug_wait6 = true
    end
    if (not IsAlive(M.sav)) and (M.sav_secure) and (not M.tug_underway7) then
        M.sav_seized = true
        M.tug_wait_base = true
    end
    if (M.sav_secure) and (M.tug_underway7) and (Distance(M.ccatug, M.geys7) < 50.0) and (not M.tug_wait7) then
        Goto(M.ccatug, M.geys7, 1)
        M.tug_underway7 = false
        M.tug_wait7 = true
    end
    if (M.sav_secure) and (M.tug_underway7) and (M.tug_after_sav) and (not M.tug_wait7) then
        Goto(M.ccatug, M.geys7, 1)
        M.tug_underway7 = false
        M.tug_after_sav = false
        M.tug_wait7 = true
    end
    -- this is going to make the cca go after the american tug
    -- BUGFIX: C++ only checks tugger != 0, but assigns the Soviet tug to
    -- tugger on CCA pickup. Priority-1 Attack can then make the CCA shoot its
    -- own carrier. Require a living team-1 carrier for the intended American
    -- tug pursuit. The original pursuit orders, priorities, and timing remain
    -- unchanged for player pickup; nil is also excluded (nil ~= 0 in Lua).
    if M.sav_secure and IsAlive(M.tugger) and GetTeamNum(M.tugger) == 1
        and not M.chase_tug then
        if IsAlive(M.ccafighter1) then
            Attack(M.ccafighter1, M.tugger, 1)
        end
        if IsAlive(M.ccafighter2) then
            Attack(M.ccafighter2, M.tugger, 1)
        end
        if IsAlive(M.ccatank1) then
            Attack(M.ccatank1, M.tugger, 1)
        end
        if IsAlive(M.ccatank2) then
            Attack(M.ccatank2, M.tugger, 1)
        end
        if IsAlive(M.svartil1) then
            Attack(M.svartil1, M.tugger, 1)
        end
        if IsAlive(M.svartil2) then
            Attack(M.svartil2, M.tugger, 1)
        end
        if IsAlive(M.ccaartil1) then
            Attack(M.ccaartil1, M.tugger, 1)
        end
        if IsAlive(M.ccaartil2) then
            Attack(M.ccaartil2, M.tugger, 1)
        end
        if IsAlive(M.ccaartil3) then
            Attack(M.ccaartil3, M.tugger, 1)
        end
        M.chase_tug = true
    end
    -- this make the artil sheel the relic
    if (M.geys1check < GetTime()) and (not M.chase_tug) then
        M.geys1check = GetTime() + 150.0
        if Distance(M.user, M.geys1) < 200.0 then
            if IsAlive(M.svartil1) then
                Attack(M.svartil1, M.user)
            end
            if IsAlive(M.svartil2) then
                Attack(M.svartil2, M.user)
            end
        else
            if IsAlive(M.svartil1) then
                Attack(M.svartil1, M.geys1)
            end
            if IsAlive(M.svartil2) then
                Attack(M.svartil2, M.geys1)
            end
        end
    end
    -- this is making sure the sav doesn't die
    if IsAlive(M.sav) then
        if GetTime() > M.next_second then
            AddHealth(M.sav, 100.0)
            M.next_second = GetTime() + 1.0
        end
    end
    -- win/victory conditions ////////////////////////////////////////////
    if (M.sav_secure) and (Distance(M.sav, M.nsdfrecycle) < 100.0) and (not M.game_over) then
        AudioMessage("misn1001.wav")
        --well done
        SucceedMission(GetTime() + 15.0, "misn10w1.des")
        M.game_over = true
    end
    if (M.sav_seized) and (not M.game_over) and (Distance(M.sav, M.ccarecycle) < 100.0) then
        AudioMessage("misn1002.wav")
        -- you lost
        FailMission(GetTime() + 15.0, "misn10f1.des")
        M.game_over = true
    end
    if (not IsAlive(M.sav)) and (not M.game_over) then
        AudioMessage("misn1003.wav")
        -- we lost the sav
        FailMission(GetTime() + 15.0, "misn10f2.des")
        M.game_over = true
    end
    if (not IsAlive(M.nsdfrecycle)) and (not M.game_over) then
        AudioMessage("misn1004.wav")
        -- we lost the Utah
        FailMission(GetTime() + 15.0, "misn10f3.des")
        M.game_over = true
    end
    -- END OF SCRIPT
end

function Save()
    return M
end

function Load(state)
    M = state
end
