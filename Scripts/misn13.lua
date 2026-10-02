-- Faithful NSDF misn13 port for stock Battlezone 98 Redux / Lua 5.1.
-- Authority: Battlezone_Source/BZ1/from_bz2_dll_src/Misn13Mission.cpp.
-- Every original source comment is retained verbatim in long comments.
-- Complete native source and serialization: References/Misn13Source/.
-- No EXU, OpenShim, community Lua, or Campaign Reimagined helpers required.
-- Preserve Execute ordering, strict timer comparisons, and command priorities.
-- See Docs/MISN13_LUA_PORT.md for adaptations and validation.

local function NewState()
    local state = {}
    state.start_done = false
    state.silos_gone = false
    state.turret_move = false
    state.first_wave = false
    state.second_wave = false
    state.turret1_set = false
    state.turret2_set = false
    state.artil_move = false
    state.artil_move2 = false
    state.artil_set = false
    state.wave2 = false
    state.wave2_done = false
    state.wave2_move = false
    state.wave3 = false
    state.wave3_done = false
    state.wave3_move = false
    state.wave4 = false
    state.wave4_done = false
    state.wave4_move = false
    state.a = false
    state.b = false
    state.c = false
    state.d = false
    state.silo1_lost = false
    state.silo2_lost = false
    state.silo3_lost = false
    state.silo4_lost = false
    state.make_bomber = false
    state.bomber_attack = false
    state.new_target = false
    state.bomber_retreat = false
    state.sv1_wait = false
    state.sv4_wait = false
    state.sv3_wait = false
    state.sv1_reload = false
    state.sv2_reload = false
    state.sv3_reload = false
    state.sv4_reload = false
    state.set_aip = false
    state.hold_aip = false
    state.bomber_reload = false
    state.assign_tank1 = false
    state.assign_tank2 = false
    state.assign_tank3 = false
    state.assign_tank4 = false
    state.silos_attacked = false
    state.silo_defend = false
    state.muf_attacked = false
    state.muf_safe = false
    state.turret1_muf = false
    state.turret2_muf = false
    state.turret5_muf = false
    state.turret6_muf = false
    state.player_center = false
    state.apc_sent = false
    state.artil_lost = false
    state.game_over = false
    state.scav_swap = false
    state.artil_message = false
    state.first_wave_time = 99999.0
    state.second_wave_time = 99999.0
    state.next_wave_time = 99999.0
    state.artil_move_time = 99999.0
    state.artil_set_time = 99999.0
    state.set_aip_time = 99999.0
    state.bomber_retreat_time = 99999.0
    state.turret_move_time = 99999.0
    state.new_orders_time = 99999.0
    state.safe_time_check = 99999.0
    state.scrap_check = 99999.0
    state.user = nil
    state.nsdfrecycle = nil
    state.nsdfmuf = nil
    state.nav1 = nil
    state.checkpoint1 = nil
    state.checkpoint2 = nil
    state.checkpoint3 = nil
    state.checkpoint4 = nil
    state.ccacom_tower = nil
    state.ccasilo1 = nil
    state.ccasilo2 = nil
    state.ccasilo3 = nil
    state.ccasilo4 = nil
    state.spawn_point1 = nil
    state.spawn_point2 = nil
    state.check1 = nil
    state.check2 = nil
    state.check3 = nil
    state.ccamuf = nil
    state.ccaslf = nil
    state.ccaapc = nil
    state.turret1 = nil
    state.turret2 = nil
    state.turret3 = nil
    state.turret4 = nil
    state.turret5 = nil
    state.turret6 = nil
    state.artil1 = nil
    state.artil2 = nil
    state.artil3 = nil
    state.artil4 = nil
    state.fighter1 = nil
    state.fighter2 = nil
    state.fighter3 = nil
    state.fighter4 = nil
    state.fighter5 = nil
    state.fighter6 = nil
    state.sv1 = nil
    state.sv2 = nil
    state.sv3 = nil
    state.sv4 = nil
    state.sv5 = nil
    state.sv6 = nil
    state.sv7 = nil
    state.sv8 = nil
    state.sv9 = nil
    state.sv0 = nil
    state.tank1 = nil
    state.tank2 = nil
    state.tank3 = nil
    state.tank4 = nil
    state.tank5 = nil
    state.tank6 = nil
    state.tank7 = nil
    state.tank8 = nil
    state.key_geyser1 = nil
    state.key_geyser2 = nil
    state.split_geyser = nil
    state.center_geyser = nil
    state.choke_bridged = false
    state.guntower1 = nil
    state.controltower = nil
    state.center = nil
    state.svscav1 = nil
    state.svscav2 = nil
    state.svscav3 = nil
    state.svscav4 = nil
    state.svscav5 = nil
    state.svscav6 = nil
    state.svscav7 = nil
    state.svscav8 = nil
    state.escort_tank = nil
    state.nsdfrig = nil
    state.avscav1 = nil
    state.avscav2 = nil
    state.avscav3 = nil
    state.check = 0
    state.scrap = 0
    -- shot_by was a native int used as a handle. Retain the returned handle
    -- itself for Redux save/load remapping, rather than coercing it to a number.
    state.shot_by = nil
    return state
end

local M = NewState()
local started = false
local pendingObjects = {}

-- Invalid native handles must not become Lua position/path overloads or meet
-- a range trigger. Live-object distances and thresholds are unchanged.
local function MissionDistance(a, b)
    if not IsValid(a) then return math.huge end
    if type(b) ~= "string" and not IsValid(b) then return math.huge end
    return GetDistance(a, b)
end

-- Native IsOdf accepts ODF basenames; Redux builds may expose the extension.
local function IsOdfBase(h, name)
    return IsValid(h) and (IsOdf(h, name) or IsOdf(h, name .. ".odf"))
end

-- Keep the source's first-captured slots, including unused sv2/tank8. Reusing
-- dead slots would change later AIP waves; that needs a separate gameplay decision.
local function RegisterObject(h)
    if not IsValid(h) then return end
    if M.sv1 == nil and IsOdfBase(h, "svapc13") then
        M.sv1 = h
    elseif M.sv2 == nil and IsOdfBase(h, "svapc13") then
        M.sv2 = h
    elseif M.sv3 == nil and IsOdfBase(h, "svhr13") then
        M.sv3 = h
    elseif M.sv4 == nil and IsOdfBase(h, "svhr13") then
        M.sv4 = h
    elseif IsOdfBase(h, "abtowe") then
        M.guntower1 = h
    elseif M.controltower == nil and IsOdfBase(h, "abcomm") then
        M.controltower = h
    elseif M.tank5 == nil and IsOdfBase(h, "svtk13") then
        M.tank5 = h
    elseif M.tank6 == nil and IsOdfBase(h, "svtk13") then
        M.tank6 = h
    elseif M.tank7 == nil and IsOdfBase(h, "svtk13") then
        M.tank7 = h
    elseif M.tank8 == nil and IsOdfBase(h, "svtk13") then
        M.tank8 = h
    elseif M.nsdfmuf == nil and IsOdfBase(h, "avmuf") then
        M.nsdfmuf = h
    elseif M.nsdfrig == nil and IsOdfBase(h, "avcnst") then
        M.nsdfrig = h
    elseif M.avscav1 == nil and IsOdfBase(h, "avscav") then
        M.avscav1 = h
    elseif M.avscav2 == nil and IsOdfBase(h, "avscav") then
        M.avscav2 = h
    elseif M.avscav3 == nil and IsOdfBase(h, "avscav") then
        M.avscav3 = h
    end
end

function Start()
    M = NewState()
    --[=[
/* Here's where you set the values at the start. */
]=]
    M.check = 0
    M.scrap = 100
    M.shot_by = 0
    M.start_done = false
    M.silos_gone = false
    M.turret_move = false
    M.first_wave = false
    M.second_wave = false
    M.artil_move = false
    M.artil_move2 = false
    M.turret1_set = false
    M.turret2_set = false
    M.artil_set = false
    M.wave2 = false
    M.wave2_done = false
    M.wave2_move = false
    M.wave3 = false
    M.wave3_done = false
    M.wave3_move = false
    M.wave4 = false
    M.wave4_done = false
    M.wave4_move = false
    M.a = false
    M.b = false
    M.c = false
    M.d = false
    M.silo1_lost = false
    M.silo2_lost = false
    M.silo3_lost = false
    M.silo4_lost = false
    M.make_bomber = false
    M.bomber_attack = false
    M.new_target = false
    M.bomber_retreat = false
    M.set_aip = false
    M.sv1_wait = false
    M.sv4_wait = false
    M.sv3_wait = false
    M.sv1_reload = false
    M.sv2_reload = false
    M.sv3_reload = false
    M.sv4_reload = false
    M.bomber_reload = false
    M.hold_aip = false
    M.assign_tank1 = false
    M.assign_tank2 = false
    M.assign_tank3 = false
    M.assign_tank4 = false
    M.silos_attacked = false
    M.silo_defend = false
    M.muf_attacked = false
    M.muf_safe = false
    M.turret1_muf = false
    M.turret2_muf = false
    M.turret5_muf = false
    M.turret6_muf = false
    M.choke_bridged = false
    M.artil_lost = true
    M.apc_sent = false
    M.game_over = false
    M.scav_swap = false
    M.artil_message = false
    M.first_wave_time = 99999.0
    M.second_wave_time = 99999.0
    M.next_wave_time = 99999.0
    M.artil_move_time = 99999.0
    M.artil_set_time = 99999.0
    M.set_aip_time = 99999.0
    M.bomber_retreat_time = 99999.0
    M.turret_move_time = 99999.0
    M.new_orders_time = 99999.0
    M.safe_time_check = 99999.0
    M.scrap_check = 60.0
    M.checkpoint1 = GetHandle("svguntower1")
    --[=[
//	checkpoint2 = GetHandle("svcontroltower");
]=]
    M.checkpoint3 = GetHandle("svmuf")
    M.checkpoint4 = GetHandle("svsilo1")
    M.ccasilo1 = GetHandle("svsilo1")
    M.ccasilo2 = GetHandle("svsilo2")
    M.ccasilo3 = GetHandle("svsilo3")
    M.ccasilo4 = GetHandle("svsilo4")
    M.ccamuf = GetHandle("svmuf")
    M.ccaslf = GetHandle("svslf")
    M.ccacom_tower = GetHandle("svcom_tower")
    M.spawn_point1 = GetHandle("spawn_geyser1")
    M.spawn_point2 = GetHandle("spawn_geyser2")
    M.nav1 = GetHandle("apcamr20_camerapod")
    M.turret1 = GetHandle("turret1")
    M.turret2 = GetHandle("turret2")
    M.turret3 = GetHandle("turret3")
    M.turret4 = GetHandle("turret4")
    M.turret5 = GetHandle("turret5")
    M.turret6 = GetHandle("turret6")
    M.artil1 = GetHandle("artil1")
    M.artil2 = GetHandle("artil2")
    M.artil3 = GetHandle("artil3")
    M.artil4 = GetHandle("artil4")
    M.fighter1 = GetHandle("fighter1")
    M.fighter2 = GetHandle("fighter2")
    M.fighter3 = GetHandle("fighter3")
    M.fighter4 = GetHandle("fighter4")
    M.fighter5 = GetHandle("fighter5")
    M.fighter6 = GetHandle("fighter6")
    M.tank1 = GetHandle("tank1")
    M.tank2 = GetHandle("tank2")
    M.tank3 = GetHandle("tank3")
    M.tank4 = GetHandle("tank4")
    M.key_geyser1 = GetHandle("key_geyser1")
    M.key_geyser2 = GetHandle("key_geyser2")
    M.center_geyser = GetHandle("center_geyser")
    M.split_geyser = GetHandle("split_geyser")
    M.nsdfrecycle = GetHandle("avrecycle")
    --[=[
//	ccaapc = GetHandle("svapc");
]=]
    M.svscav1 = GetHandle("svscav1")
    M.svscav2 = GetHandle("svscav2")
    M.svscav3 = GetHandle("svscav3")
    M.svscav4 = GetHandle("svscav4")
    M.svscav5 = nil
    M.svscav6 = nil
    M.svscav7 = nil
    M.svscav8 = nil
    M.sv1 = nil
    M.sv2 = nil
    M.sv3 = nil
    M.sv4 = nil
    M.guntower1 = nil
    M.controltower = nil
    M.tank5 = nil
    M.tank6 = nil
    M.tank7 = nil
    M.tank8 = nil
    M.nsdfmuf = nil
    M.nsdfrig = nil
    M.avscav1 = nil
    M.avscav2 = nil
    M.avscav3 = nil
    M.center = GetHandle("center")
    -- LuaMission can report map objects before Start; native Setup preceded
    -- those callbacks. Replay them after Setup so producer handles are retained.
    started = true
    for _, h in ipairs(pendingObjects) do RegisterObject(h) end
    pendingObjects = {}
end

--[=[
// this is the handle thing brad made for me
]=]
function AddObject(h)
    if started then
        RegisterObject(h)
    else
        pendingObjects[#pendingObjects + 1] = h
    end
end

function Update(dt)
    --[=[
// START OF SCRIPT
]=]
    M.user = GetPlayerHandle()
    --[=[
//assigns the player a handle every frame
]=]
    --[=[
// these are constants
]=]
    if M.bomber_attack then
        if not IsAlive(M.sv1) then
            M.sv1_wait = false
        end
        if not IsAlive(M.sv4) then
            M.sv4_wait = false
        end
        if not IsAlive(M.sv3) then
            M.sv3_wait = false
        end
        if (not IsAlive(M.sv3)) and (not IsAlive(M.sv4)) then
            M.make_bomber = false
            M.bomber_attack = false
            M.new_target = false
            M.bomber_retreat = false
            M.bomber_retreat_time = 99999.0
            M.bomber_reload = false
            --[=[
//			sv1_reload = false;
]=]
            --[=[
//			sv2_reload = false;
]=]
            --[=[
//			sv3_reload = false;
]=]
            --[=[
//			sv4_reload = false;
]=]
        end
    end
    if not IsAlive(M.tank1) then
        M.assign_tank1 = false
    end
    if not IsAlive(M.tank2) then
        M.assign_tank2 = false
    end
    if not IsAlive(M.tank3) then
        M.assign_tank3 = false
    end
    if not IsAlive(M.tank4) then
        M.assign_tank4 = false
    --[=[
// end of constants ///////////////////////////////////////////////////////////////////
]=]
    end
    if not M.start_done then
        AudioMessage("misn1300.wav")
        ClearObjectives()
        AddObjective("misn1300.otf", "white")
        SetPilot(1, 10)
        SetPilot(2, 40)
        SetScrap(1, 40)
        SetScrap(2, 200)
        Defend(M.tank1)
        Defend(M.tank2)
        Defend(M.artil1)
        Defend(M.artil2)
        Defend(M.artil3)
        Defend(M.artil4)
        --[=[
//		Defend(ccaapc);
]=]
        M.escort_tank = BuildObject("svtank", 2, M.artil1)
        if M.nav1~=nil then
            SetObjectiveName(M.nav1, "Drop Zone")
        end
        Defend(M.escort_tank)
        M.first_wave_time = GetTime() +5.0
        M.next_wave_time = GetTime() +300.0
        M.artil_move_time = GetTime() + 900.0
        --[=[
// this may move
]=]
        M.start_done = true
    --[=[
// this is going to subtract scrap from the soviets if the silos are destroyed
]=]
    end
    if (not IsAlive(M.ccasilo1)) and (GetScrap(2)> 150) and (not M.silo1_lost) then
        SetScrap(2, 150)
        M.silo1_lost = true
    end
    if (not IsAlive(M.ccasilo2)) and (GetScrap(2)> 150) and (not M.silo1_lost) then
        SetScrap(2, 150)
        M.silo1_lost = true
    end
    if (not IsAlive(M.ccasilo3)) and (GetScrap(2)> 150) and (not M.silo1_lost) then
        SetScrap(2, 150)
        M.silo1_lost = true
    end
    if (not IsAlive(M.ccasilo4)) and (GetScrap(2)> 150) and (not M.silo1_lost) then
        SetScrap(2, 150)
        M.silo1_lost = true
    end
    if (not IsAlive(M.ccasilo1)) and (not IsAlive(M.ccasilo2)) and (GetScrap(2)> 100) and (not M.silo2_lost) then
        SetScrap(2, 100)
        M.silo2_lost = true
    end
    if (not IsAlive(M.ccasilo1)) and (not IsAlive(M.ccasilo3)) and (GetScrap(2)> 100) and (not M.silo2_lost) then
        SetScrap(2, 100)
        M.silo2_lost = true
    end
    if (not IsAlive(M.ccasilo1)) and (not IsAlive(M.ccasilo4)) and (GetScrap(2)> 100) and (not M.silo2_lost) then
        SetScrap(2, 100)
        M.silo2_lost = true
    end
    if (not IsAlive(M.ccasilo2)) and (not IsAlive(M.ccasilo3)) and (GetScrap(2)> 100) and (not M.silo2_lost) then
        SetScrap(2, 100)
        M.silo2_lost = true
    end
    if (not IsAlive(M.ccasilo2)) and (not IsAlive(M.ccasilo4)) and (GetScrap(2)> 100) and (not M.silo2_lost) then
        SetScrap(2, 100)
        M.silo2_lost = true
    end
    if (not IsAlive(M.ccasilo3)) and (not IsAlive(M.ccasilo4)) and (GetScrap(2)> 100) and (not M.silo2_lost) then
        SetScrap(2, 100)
        M.silo2_lost = true
    end
    if (not IsAlive(M.ccasilo1)) and (not IsAlive(M.ccasilo2)) and (not IsAlive(M.ccasilo3)) and (GetScrap(2)> 50) and (not M.silo3_lost) then
        SetScrap(2, 50)
        M.silo3_lost = true
    end
    if (not IsAlive(M.ccasilo1)) and (not IsAlive(M.ccasilo2)) and (not IsAlive(M.ccasilo4)) and (GetScrap(2)> 50) and (not M.silo3_lost) then
        SetScrap(2, 50)
        M.silo3_lost = true
    end
    if (not IsAlive(M.ccasilo1)) and (not IsAlive(M.ccasilo3)) and (not IsAlive(M.ccasilo4)) and (GetScrap(2)> 50) and (not M.silo3_lost) then
        SetScrap(2, 50)
        M.silo3_lost = true
    end
    if (not IsAlive(M.ccasilo2)) and (not IsAlive(M.ccasilo3)) and (not IsAlive(M.ccasilo4)) and (GetScrap(2)> 50) and (not M.silo3_lost) then
        SetScrap(2, 50)
        M.silo3_lost = true
    end
    if (not IsAlive(M.ccasilo1)) and (not IsAlive(M.ccasilo2)) and (not IsAlive(M.ccasilo3)) and (not IsAlive(M.ccasilo4)) and (GetScrap(2)> 0) and (not M.silos_gone) then
        M.silos_gone = true
        SetScrap(2, 0)
    --[=[
// now I'm going to start the battle by sending the turrets to smart locations
]=]
    --[=[
// this immediately sends turrets to key locations
]=]
    end
    if (M.start_done) and (not M.turret_move) then
        Retreat(M.turret1, "turret_path1")
        --[=[
// a scrap field vital to americans
]=]
        Retreat(M.turret2, "turret_path1")
        --[=[
// a scrap field vital to americans
]=]
        Defend(M.turret3)
        --[=[
// the main choke point where americans must come through
]=]
        Defend(M.turret4)
        --[=[
// the main choke point where americans must come through
]=]
        Retreat(M.turret5, "turret_path2")
        --[=[
// the scrap silos
]=]
        Retreat(M.turret6, "turret_path2")
        --[=[
// the scrap silos
]=]
        Goto(M.ccaslf, "slf_path")
        M.turret_move_time = GetTime() + 120.0
        M.turret_move = true
    end
    if (M.turret_move) and (M.turret_move_time < GetTime()) and (not M.silo_defend) then
        M.turret_move_time = GetTime() + 3.0
        if (MissionDistance(M.turret5, M.ccasilo1) < 60.0) and (MissionDistance(M.turret6, M.ccasilo1) < 60.0) then
            Defend(M.turret5)
            Defend(M.turret6)
            M.silo_defend = true
        end
    end
    if (M.turret_move) and (M.turret_move_time < GetTime()) and (not M.turret1_set) then
        if MissionDistance(M.turret1, M.key_geyser1) < 100.0 then
            Goto(M.turret1, M.key_geyser1)
            M.turret1_set = true
        end
    end
    if (M.turret_move) and (M.turret_move_time < GetTime()) and (not M.turret2_set) then
        if MissionDistance(M.turret2, M.key_geyser1) < 100.0 then
            Goto(M.turret2, M.key_geyser2)
            M.turret2_set = true
        end
    --[=[
// sending the tanks that would have been following the player in for the first attack
]=]
    end
    if (M.start_done) and (M.first_wave_time < GetTime()) and (not M.first_wave) then
        Attack(M.tank3, M.nsdfrecycle, 1)
        Attack(M.tank4, M.nsdfrecycle, 1)
        Attack(M.fighter5, M.nsdfrecycle, 1)
        Attack(M.fighter6, M.nsdfrecycle, 1)
        M.second_wave_time = GetTime() + 5.0
        M.first_wave = true
    end
    if (M.first_wave) and (M.second_wave_time < GetTime()) and (not M.second_wave) then
        Goto(M.fighter1, "choke_point1")
        Goto(M.fighter2, "choke_point1")
        Goto(M.fighter3, M.key_geyser1)
        Goto(M.fighter4, M.key_geyser2)
        M.set_aip_time = GetTime() + 60.0
        M.second_wave = true
    end
    if (not M.set_aip) and (M.set_aip_time < GetTime()) and (not M.hold_aip) and (not M.muf_attacked) then
        M.set_aip_time = GetTime() + 240.0
        SetAIP("misn13.aip")
        --[=[
//		set_aip = true;
]=]
    --[=[
//	if (set_aip)
]=]
    --[=[
//	{
]=]
    --[=[
//		set_aip = false;
]=]
    --[=[
//	}
]=]
    --[=[
// tank code
]=]
    end
    if (IsAlive(M.tank1)) and (not M.assign_tank1) then
        Follow(M.tank1, M.ccamuf)
        M.assign_tank1 = true
    end
    if (IsAlive(M.tank2)) and (not M.assign_tank2) then
        Follow(M.tank2, M.ccamuf)
        M.assign_tank2 = true
    end
    if (IsAlive(M.tank3)) and (not M.assign_tank3) then
        Follow(M.tank3, M.center)
        M.assign_tank3 = true
    end
    if (IsAlive(M.tank4)) and (not M.assign_tank4) then
        Follow(M.tank4, M.center)
        M.assign_tank4 = true
    --[=[
// this sends the first apc after the player's comtower
]=]
    --[=[
//	if ((IsAlive(controltower)) && (!apc_sent))
]=]
    --[=[
//	{
]=]
    --[=[
//		Attack(ccaapc, controltower, 1);
]=]
    --[=[
//		apc_sent = true;
]=]
    --[=[
//	}
]=]
    --[=[
// this is bomber code ////////////////////////////////////////////////////////////////////////////
]=]
    end
    if ((IsAlive(M.guntower1)) or (IsAlive(M.controltower))) and (not M.make_bomber) and (not M.muf_attacked) then
        SetAIP("misn13a.aip")
        M.hold_aip = true
        M.make_bomber = true
    end
    if (M.make_bomber) and (not M.bomber_attack) then
        if (IsAlive(M.sv4)) and (not M.sv4_wait) then
            if IsAlive(M.guntower1) then
                Attack(M.sv4, M.guntower1)
            else
                if IsAlive(M.nsdfmuf) then
                    Attack(M.sv4, M.nsdfmuf)
                else
                    if IsAlive(M.controltower) then
                        Attack(M.sv4, M.controltower)
                    end
                end
                if IsAlive(M.tank5) then
                    Follow(M.tank5, M.sv4)
                end
            end
            M.sv4_wait = true
        end
        if (IsAlive(M.sv1)) and (not M.sv1_wait) then
            if IsAlive(M.controltower) then
                Attack(M.sv1, M.controltower)
            else
                if IsAlive(M.guntower1) then
                    Attack(M.sv1, M.guntower1)
                else
                    if IsAlive(M.nsdfmuf) then
                        Attack(M.sv1, M.nsdfmuf)
                    end
                end
            end
            if IsAlive(M.tank6) then
                Follow(M.tank6, M.sv1)
            end
            M.sv1_wait = true
        end
        if (IsAlive(M.sv3)) and (not M.sv3_wait) then
            if IsAlive(M.guntower1) then
                Attack(M.sv3, M.guntower1)
            else
                if IsAlive(M.nsdfmuf) then
                    Attack(M.sv3, M.nsdfmuf)
                else
                    if IsAlive(M.controltower) then
                        Attack(M.sv3, M.controltower)
                    end
                end
                if IsAlive(M.tank7) then
                    Follow(M.tank7, M.sv3)
                end
            end
            M.sv3_wait = true
        end
    end
    if (M.sv1_wait) and (M.sv3_wait) and (M.sv4_wait) and (not M.bomber_attack) then
        M.hold_aip = false
        --[=[
//		bomber_reload = false;
]=]
        M.bomber_attack = true
    end
    if (M.bomber_attack) and (not IsAlive(M.guntower1)) and (not M.new_target) then
        if IsAlive(M.controltower) then
            if IsAlive(M.sv1) then
                Attack(M.sv1, M.controltower)
            end
            if IsAlive(M.sv3) then
                Attack(M.sv3, M.controltower)
            end
            if IsAlive(M.sv4) then
                Attack(M.sv4, M.controltower)
            end
            M.new_target = true
        else
            if IsAlive(M.nsdfmuf) then
                if IsAlive(M.sv1) then
                    Attack(M.sv1, M.nsdfmuf)
                end
                if IsAlive(M.sv3) then
                    Attack(M.sv3, M.nsdfmuf)
                end
                if IsAlive(M.sv4) then
                    Attack(M.sv4, M.nsdfmuf)
                end
                M.new_target = true
            end
        end
        --[=[
/*			else
			{
				if (IsAlive(sv1))
				{
					Retreat(sv1, ccamuf);
				}
				if (IsAlive(sv3))
				{
					Retreat(sv3, ccamuf);
				}
				if (IsAlive(sv4))
				{
					Retreat(sv4, ccamuf);
				}
			}
*/
]=]
        --[=[
//		bomber_retreat_time = Get_Time() + 15.0f;
]=]
        --[=[
//		bomber_retreat = true;
]=]
    --[=[
/*
	if ((new_target) && ((!IsAlive(controltower)) || (!IsAlive(nsdfmuf))) && (!bomber_retreat))
	{
		if(IsAlive(sv1))
		{
			Retreat(sv1, ccamuf);
		}
//		if(IsAlive(sv2))
//		{
//			Retreat(sv2, ccamuf);
//		}
		if(IsAlive(sv3))
		{
			Retreat(sv3, ccamuf);
		}
		if(IsAlive(sv4))
		{
			Retreat(sv4, ccamuf);
		}
		
		bomber_retreat_time = Get_Time() + 15.0f;
		bomber_retreat = true;
	}

*/
]=]
    --[=[
/*
	if ((bomber_retreat) && (bomber_retreat_time < Get_Time()) && (!bomber_reload))
	{
		bomber_retreat_time = Get_Time() + 15.0f;

		if (GetDistance(user, ccamuf) > 500.0f)
		{
			if ((IsAlive(sv1)) && (GetDistance(sv1, ccamuf) < 100.0f) && (!sv1_reload))
			{
				RemoveObject(sv1);
				sv1 = BuildObject("avhraz", 2, ccamuf);
				AddScrap(2, -2);
				sv1_reload = true;
			}
//			if ((IsAlive(sv2)) && (GetDistance(sv2, ccamuf) < 50.0f) && (!sv2_reload))
//			{
//				RemoveObject(sv2);
//				sv2 = BuildObject("avhraz", 2, ccamuf);
//				AddScrap(2, -2);
//				sv2_reload = true;
//			}
			if ((IsAlive(sv3)) && (GetDistance(sv3, ccamuf) < 100.0f) && (!sv3_reload))
			{
				RemoveObject(sv3);
				sv3 = BuildObject("avhraz", 2, ccamuf);
				AddScrap(2, -2);
				sv3_reload = true;
			}
			if ((IsAlive(sv4)) && (GetDistance(sv4, ccamuf) < 100.0f) && (!sv4_reload))
			{
				RemoveObject(sv4);
				sv4 = BuildObject("avhraz", 2, ccamuf);
				AddScrap(2, -2);
				sv4_reload = true;
			}
		}
*/
]=]
    --[=[
//		if (((sv1_reload) && /*(sv2_reload) && */(sv3_reload) && (sv4_reload)) ||
]=]
    --[=[
//			((!IsAlive(sv1)) && /*(sv2_reload) && */(sv3_reload) && (sv4_reload)) ||
]=]
    --[=[
//			(/*(!IsAlive(sv2)) && */(sv1_reload) && (sv3_reload) && (sv4_reload)) ||
]=]
    --[=[
//			((!IsAlive(sv3)) && (sv1_reload) && /*(sv2_reload) && */(sv4_reload)) ||
]=]
    --[=[
//			((!IsAlive(sv4)) && (sv1_reload) && /*(sv2_reload) && */(sv3_reload)) ||
]=]
    --[=[
//			((!IsAlive(sv1)) && /*(!IsAlive(sv2)) && */(sv3_reload) && (sv4_reload)) ||
]=]
    --[=[
//			((!IsAlive(sv1)) && (!IsAlive(sv3)) && /*(sv2_reload) && */(sv4_reload)) ||
]=]
    --[=[
//			((!IsAlive(sv1)) && (!IsAlive(sv4)) && /*(sv2_reload) && */(sv3_reload)) ||
]=]
    --[=[
//			(/*(!IsAlive(sv2)) && */(!IsAlive(sv3)) && (sv1_reload) && (sv4_reload)) ||
]=]
    --[=[
//			(/*(!IsAlive(sv2)) && */(!IsAlive(sv4)) && (sv1_reload) && (sv3_reload)) ||
]=]
    --[=[
//			((!IsAlive(sv3)) && (!IsAlive(sv4)) && (sv1_reload)/* && (sv2_reload) */) ||
]=]
    --[=[
//			((!IsAlive(sv1)) && /*(!IsAlive(sv2)) && */(!IsAlive(sv3)) && (sv4_reload)) ||
]=]
    --[=[
//			((!IsAlive(sv1)) && /*(!IsAlive(sv2)) && */(!IsAlive(sv4)) && (sv3_reload)) ||
]=]
    --[=[
//			((!IsAlive(sv1)) && (!IsAlive(sv3)) && (!IsAlive(sv4))/* && (sv2_reload) */) ||
]=]
    --[=[
//			(/*(!IsAlive(sv2)) && */(!IsAlive(sv3)) && (!IsAlive(sv4)) && (sv1_reload)))
]=]
    --[=[
//		{
]=]
    --[=[
/*(			if (!IsAlive(sv1))
			{
				Defend(sv1);
			}
			if (!IsAlive(sv2))
			{
				Defend(sv2);
			}
			if (!IsAlive(sv3))
			{
				Defend(sv3);
			}
			if (!IsAlive(sv4))
			{
				Defend(sv4);
			}
*/
]=]
    --[=[
//			make_bomber = false;
]=]
    --[=[
//			bomber_attack = false;
]=]
    --[=[
//			sv1_wait = false;
]=]
    --[=[
//			sv3_wait = false;
]=]
    --[=[
//			sv4_wait = false;
]=]
    --[=[
//			new_target = false;
]=]
    --[=[
//			bomber_retreat = false;
]=]
    --[=[
//			bomber_retreat_time = 99999.0f;
]=]
    --[=[
//			sv1_reload = false;
]=]
    --[=[
//			sv2_reload = false;
]=]
    --[=[
//			sv3_reload = false;
]=]
    --[=[
//			sv4_reload = false;
]=]
    --[=[
//			bomber_reload = true;
]=]
    --[=[
//		}
]=]
    --[=[
//	}
]=]
    --[=[
// end bomber code ////////////////////////////////////////////////////////////////////////////
]=]
    --[=[
// this is what happens if the silos get attacked
]=]
    end
    if (IsAlive(M.ccasilo1)) and (not M.silos_attacked) and (GetHealth(M.ccasilo1) < 0.95) then
        M.new_orders_time = GetTime() + 2.0
        M.silos_attacked = true
    end
    if (IsAlive(M.ccasilo2)) and (not M.silos_attacked) and (GetHealth(M.ccasilo2) < 0.95) then
        M.new_orders_time = GetTime() + 2.0
        M.silos_attacked = true
    end
    if (IsAlive(M.ccasilo3)) and (not M.silos_attacked) and (GetHealth(M.ccasilo3) < 0.95) then
        M.new_orders_time = GetTime() + 2.0
        M.silos_attacked = true
    end
    if (IsAlive(M.ccasilo4)) and (not M.silos_attacked) and (GetHealth(M.ccasilo4) < 0.95) then
        M.new_orders_time = GetTime() + 2.0
        M.silos_attacked = true
    end
    if (M.silos_attacked) and (M.new_orders_time < GetTime()) then
        M.new_orders_time = GetTime() + 120.0
        if IsAlive(M.tank1) then
            Goto(M.tank1, "silo_spot")
        end
        if IsAlive(M.tank2) then
            Goto(M.tank2, "silo_spot")
        end
        if IsAlive(M.tank3) then
            Goto(M.tank3, "silo_spot")
        end
        if IsAlive(M.tank4) then
            Goto(M.tank4, "silo_spot")
        end
        if IsAlive(M.turret1) then
            Goto(M.turret1, "silo_spot")
        end
        if IsAlive(M.turret2) then
            Goto(M.turret2, "silo_spot")
        end
        if IsAlive(M.turret5) then
            Goto(M.turret5, "silo_spot")
        end
        if IsAlive(M.turret6) then
            Goto(M.turret6, "silo_spot")
        end
        if IsAlive(M.tank4) then
            Goto(M.tank4, "silo_spot")
        end
        if (M.bomber_reload) or (M.bomber_attack) then
            if IsAlive(M.sv1) then
                Goto(M.sv1, "silo_spot")
            --[=[
//			if (IsAlive(sv2))
]=]
            --[=[
//			{
]=]
            --[=[
//				Goto(sv2, "silo_spot");
]=]
            --[=[
//			}
]=]
            end
            if IsAlive(M.sv3) then
                Goto(M.sv3, "silo_spot")
            end
            if IsAlive(M.sv4) then
                Goto(M.sv4, "silo_spot")
            end
        end
    --[=[
// this is what happens if the muf is under attack
]=]
    end
    if (IsAlive(M.ccamuf)) and (not M.muf_attacked) and (GetHealth(M.ccamuf) < 0.90) and (not M.muf_safe) then
        if IsAlive(M.turret1) then
            Goto(M.turret1, M.ccamuf)
        end
        if IsAlive(M.turret2) then
            Goto(M.turret2, M.ccamuf)
        end
        if IsAlive(M.turret5) then
            Goto(M.turret5, M.ccamuf)
        end
        if IsAlive(M.turret6) then
            Goto(M.turret6, M.ccamuf)
        end
        AddScrap(2, 40)
        M.safe_time_check = GetTime() + 120.0
        SetAIP("misn13c.aip")
        M.muf_attacked = true
    end
    if (M.muf_attacked) and (IsAlive(M.turret1)) and (not M.turret1_muf) and MissionDistance(M.turret1, M.ccamuf) < 60.0 then
        Defend(M.turret1)
        M.turret1_muf = true
    end
    if (M.muf_attacked) and (IsAlive(M.turret2)) and (not M.turret2_muf) and MissionDistance(M.turret2, M.ccamuf) < 60.0 then
        Defend(M.turret2)
        M.turret2_muf = true
    end
    if (M.muf_attacked) and (IsAlive(M.turret5)) and (not M.turret5_muf) and MissionDistance(M.turret5, M.ccamuf) < 60.0 then
        Defend(M.turret5)
        M.turret5_muf = true
    end
    if (M.muf_attacked) and (IsAlive(M.turret6)) and (not M.turret6_muf) and MissionDistance(M.turret6, M.ccamuf) < 60.0 then
        Defend(M.turret6)
        M.turret6_muf = true
    --[=[
// this checks to see of the coast is clear after the muf is attacked
]=]
    end
    if (not M.game_over) and (M.muf_attacked) and (M.safe_time_check < GetTime()) and (not M.muf_safe) and IsAlive(M.ccamuf) then
        -- BUGFIX: do not count units around a destroyed factory. Its destruction
        -- still wins at the source's end-of-update check; live defense is unchanged.
        -- BUGFIX / fidelity: the native line below discards a comparison result.
        -- Lua cannot use a bare comparison as a statement, so omit the no-op.
        -- Do NOT turn it into an assignment: that would delay the original
        -- every-update coast-clear check by up to 60 seconds and alter AIP flow.
        --[=[
        safe_time_check < Get_Time() + 60.0f;
        ]=]
        M.check = CountUnitsNearObject(M.ccamuf, 400.0, 1, nil)
        if M.check < 2.0 then
            M.muf_safe = true
            M.muf_attacked = false
        end
    --[=[
// this checks to see if the player has broken through the main chokepoint
]=]
    end
    if (not M.choke_bridged) and (not IsAlive(M.turret3)) and (not IsAlive(M.turret4)) then
        M.choke_bridged = true
    --[=[
// this is the section that moves the first wave of soviet artillery units
]=]
    end
    if (M.artil_move_time < GetTime()) and (not M.artil_move) then
        M.artil_move_time = GetTime() + 10.0
        if IsAlive(M.artil1) then
            Retreat(M.artil1, "artil_path1")
        end
        if IsAlive(M.artil2) then
            Retreat(M.artil2, "artil_path1")
        end
        if IsAlive(M.artil3) then
            Retreat(M.artil3, "artil_path1")
        end
        if IsAlive(M.artil4) then
            Retreat(M.artil4, "artil_path1")
        end
        if IsAlive(M.escort_tank) then
            Retreat(M.escort_tank, "artil_path1")
        end
        M.artil_move = true
    end
    if (M.artil_move) and (M.artil_move_time < GetTime()) and (not M.artil_move2) then
        M.artil_move_time = GetTime() + 5.0
        if MissionDistance(M.artil4, M.split_geyser) < 20.0 then
            if IsAlive(M.artil1) then
                Goto(M.artil1, "artil_point1")
                SetIndependence(M.artil1, 1)
            end
            if IsAlive(M.artil2) then
                Goto(M.artil2, "artil_point2")
                SetIndependence(M.artil2, 1)
            end
            if IsAlive(M.artil3) then
                Goto(M.artil3, "artil_point3")
                SetIndependence(M.artil3, 1)
            end
            if IsAlive(M.artil4) then
                Goto(M.artil4, "artil_point4")
                SetIndependence(M.artil4, 1)
            end
            if IsAlive(M.escort_tank) then
                Follow(M.escort_tank, M.artil1)
            end
            M.artil_set_time = GetTime() + 120.0
            M.artil_move2 = true
        end
    end
    if (M.artil_set_time < GetTime()) and (not M.artil_set) then
        if IsAlive(M.artil1) then
            if IsAlive(M.avscav1) then
                Attack(M.artil1, M.avscav1)
            else
                if IsAlive(M.avscav2) then
                    Attack(M.artil1, M.avscav2)
                else
                    if IsAlive(M.avscav3) then
                        Attack(M.artil1, M.avscav3)
                    end
                end
            end
        end
        if IsAlive(M.artil2) then
            if IsAlive(M.avscav3) then
                Attack(M.artil2, M.avscav3)
            else
                if IsAlive(M.avscav2) then
                    Attack(M.artil2, M.avscav2)
                else
                    if IsAlive(M.avscav1) then
                        Attack(M.artil2, M.avscav1)
                    end
                end
            end
        end
        M.artil_set = true
    end
    if (not IsAlive(M.artil1)) and (not IsAlive(M.artil2)) and (not IsAlive(M.artil3)) and (not IsAlive(M.artil4)) then
        M.artil_lost = true
    end
    if (M.artil_move2) and (not M.artil_message) then
        -- Redux uses nil for no shooter; native code used 0. Check both so
        -- absent artillery handles cannot spuriously match an absent shooter.
        if IsAlive(M.nsdfrecycle) then
            M.shot_by = GetWhoShotMe(M.nsdfrecycle)
            if M.shot_by ~= nil and M.shot_by ~= 0 then
                if (M.artil1 == M.shot_by) or (M.artil2 == M.shot_by) or (M.artil3 == M.shot_by) or (M.artil4 == M.shot_by) then
                    AudioMessage("misn1302.wav")
                    M.artil_message = true
                end
            end
        end
        if (IsAlive(M.nsdfmuf)) and (not M.artil_message) then
            M.shot_by = GetWhoShotMe(M.nsdfmuf)
            if M.shot_by ~= nil and M.shot_by ~= 0 then
                if (M.artil1 == M.shot_by) or (M.artil2 == M.shot_by) or (M.artil3 == M.shot_by) or (M.artil4 == M.shot_by) then
                    AudioMessage("misn1302.wav")
                    M.artil_message = true
                end
            end
        end
        if (IsAlive(M.avscav1)) and (not M.artil_message) then
            M.shot_by = GetWhoShotMe(M.avscav1)
            if M.shot_by ~= nil and M.shot_by ~= 0 then
                if (M.artil1 == M.shot_by) or (M.artil2 == M.shot_by) or (M.artil3 == M.shot_by) or (M.artil4 == M.shot_by) then
                    AudioMessage("misn1302.wav")
                    M.artil_message = true
                end
            end
        end
        if (IsAlive(M.avscav2)) and (not M.artil_message) then
            M.shot_by = GetWhoShotMe(M.avscav2)
            if M.shot_by ~= nil and M.shot_by ~= 0 then
                if (M.artil1 == M.shot_by) or (M.artil2 == M.shot_by) or (M.artil3 == M.shot_by) or (M.artil4 == M.shot_by) then
                    AudioMessage("misn1302.wav")
                    M.artil_message = true
                end
            end
        end
        if (IsAlive(M.avscav3)) and (not M.artil_message) then
            M.shot_by = GetWhoShotMe(M.avscav3)
            if M.shot_by ~= nil and M.shot_by ~= 0 then
                if (M.artil1 == M.shot_by) or (M.artil2 == M.shot_by) or (M.artil3 == M.shot_by) or (M.artil4 == M.shot_by) then
                    AudioMessage("misn1302.wav")
                    M.artil_message = true
                end
            end
        end
    --[=[
// this wakes up the scavengers
]=]
    end
    if (M.scrap_check < GetTime()) and (not M.scav_swap) then
        M.scrap_check = GetTime() + 60.0
        M.scrap = GetScrap(2)
        if M.scrap < 40 then
            -- BUGFIX: a non-null native handle can outlive its scavenger. Build
            -- only from surviving scavengers, avoiding an invalid spawn location
            -- and resurrecting killed units. The timer, scrap threshold, swap
            -- order, and commands for surviving units are exactly as in source.
            if IsAlive(M.svscav1) then
                M.svscav5 = BuildObject("svscav", 2, M.svscav1)
                RemoveObject(M.svscav1)
                Goto(M.svscav5, M.center_geyser)
            end
            if IsAlive(M.svscav2) then
                M.svscav6 = BuildObject("svscav", 2, M.svscav2)
                RemoveObject(M.svscav2)
                Goto(M.svscav6, M.center_geyser)
            end
            if IsAlive(M.svscav3) then
                M.svscav7 = BuildObject("svscav", 2, M.svscav3)
                RemoveObject(M.svscav3)
                Goto(M.svscav7, M.center_geyser)
            end
            if IsAlive(M.svscav4) then
                M.svscav8 = BuildObject("svscav", 2, M.svscav4)
                RemoveObject(M.svscav4)
                Goto(M.svscav8, M.center_geyser)
            end
            M.scav_swap = true
        end
    --[=[
// win/loose conditions
]=]
    end
    if (not IsAlive(M.nsdfrecycle)) and (not M.game_over) then
        AudioMessage("misn1304.wav")
        FailMission(GetTime() + 15.0, "misn13f1.des")
        M.game_over = true
    end
    if (not IsAlive(M.ccamuf)) and (not M.game_over) then
        AudioMessage("misn1303.wav")
        SucceedMission(GetTime() + 15.0, "misn13w1.des")
        M.game_over = true
    --[=[
// end of scrap reduction
]=]
    --[=[
// END OF SCRIPT
]=]
    end
end

function Save()
    return M
end

function Load(state)
    M = state
    started = true
    pendingObjects = {}
end

-- Native declaration/serialization comments (full methods in snapshot).
--[=[
/*
	Misn13Mission
*/
]=]
--[=[
// bools
]=]
--[=[
// floats
]=]
--[=[
// handles
]=]
--[=[
// integers
]=]
--[=[
// init bools
]=]
--[=[
// init floats
]=]
--[=[
// init handles
]=]
--[=[
// init ints
]=]
--[=[
// bools
]=]
--[=[
// floats
]=]
--[=[
// Handles
]=]
--[=[
// ints
]=]
--[=[
// bools
]=]
--[=[
// floats
]=]
--[=[
// Handles
]=]
--[=[
// ints
]=]
