-- Run from the repository root with Lua 5.1. Handles are opaque userdata.
-- Offline (single-player) behavior of the co-op-capable misn13: the real CRCoop runs with
-- single-player semantics, so every check below is the DLL's own flow plus the documented CR
-- changes (CCA on team 5, the whole-base win, restored waves 2-4, the unused misn1301 line, the
-- escort/reserve roles, the team filters). Multi-player behavior is in Test-Misn13Coop.lua.
local now, objects, labels, calls, distances, scrap, nearby
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function record(name, ...)
    calls[#calls + 1] = {name, ...}
end
local function count(name, arg, target)
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == name and (arg == nil or c[2] == arg)
            and (target == nil or c[3] == target) then n = n + 1 end
    end
    return n
end
local function object(odf, team)
    local h = newproxy(true)
    objects[h] = {alive = true, health = 1, odf = odf, team = team}
    return h
end
-- Authored teams in Missions/misn13.bzn: the Texas, its nav pod and the player are team 1, every other
-- named object is the CCA (team 5 after Build-CoopMap.py).
local NSDF_LABELS = {avrecycle = true, apcamr20_camerapod = true, player = true, player0_hover = true}
function GetHandle(label)
    if not labels[label] then
        labels[label] = object(NSDF_LABELS[label] and "avrecy" or "svtank", NSDF_LABELS[label] and 1 or 5)
    end
    return labels[label]
end
function GetPlayerHandle() return GetHandle("player") end
function GetTeamNum(h) assert(IsValid(h), "invalid team read"); return objects[h].team end
function GetLabel() return nil end
function SetVector(x, y, z) return {x = x or 0, y = y or 0, z = z or 0} end
function GetPosition() return SetVector(0, 0, 0) end
function DisplayMessage() end
function Ally() end
function UnAlly() end
function GetTime() return now end
function IsValid(h) return objects[h] ~= nil end
function IsAlive(h) return IsValid(h) and objects[h].alive end
function GetHealth(h) assert(IsAlive(h)); return objects[h].health end
function GetWhoShotMe(h) assert(IsAlive(h)); return objects[h].shooter end
function IsOdf(h, name) return IsValid(h) and objects[h].odf == name end
function GetDistance(h, target)
    assert(IsValid(h), "invalid distance origin")
    assert(type(target) == "string" or IsValid(target), "invalid distance target")
    return distances[h] and distances[h][target] or 10000
end
function CountUnitsNearObject(h, range, team, odf)
    assert(IsAlive(h), "invalid factory count")
    assert(range == 400 and team == 1 and odf == nil, "native unfiltered count")
    record("CountUnitsNearObject", h)
    return nearby
end
function BuildObject(odf, team, where)
    assert(type(where) == "string" or IsAlive(where), "invalid spawn location")
    local h = object(odf, team)
    record("BuildObject", odf, team, where, h)
    AddObject(h)
    return h
end
function RemoveObject(h) objects[h] = nil; record("RemoveObject", h) end
function SetScrap(team, amount) scrap[team] = amount; record("SetScrap", team, amount) end
function AddScrap(team, amount) scrap[team] = scrap[team] + amount; record("AddScrap", team, amount) end
function GetScrap(team) return scrap[team] end
-- The real ScriptSubtitles plays through AudioMessage; the stub returns an opaque audio handle.
for _, name in ipairs({"AudioMessage", "ClearObjectives", "AddObjective", "UpdateObjective", "SetPilot",
    "SetObjectiveName", "SetObjectiveOn", "SetObjectiveOff", "SetUserTarget", "Defend", "Retreat", "Goto",
    "Follow", "Attack", "SetAIP", "SetAIControl", "SetIndependence", "FailMission", "SucceedMission"}) do
    local operation = name
    _G[operation] = function(...) record(operation, ...) end
end
local function noop() end
local modules = {
    RequireFix = {Initialize = noop}, exu = {},
    ScriptSubtitles = {Play = function(file) AudioMessage(file); return 1 end,
        Queue = function(file) AudioMessage(file); return 1 end, Stop = noop, Update = noop, Initialize = noop},
}
function require(name) return assert(modules[name], name) end
local function reset(beforeStart)
    now, nearby = 0, 3
    objects, labels, calls, distances, scrap = {}, {}, {}, {}, {}
    modules.CRCoopComms = assert(loadfile("Scripts/CRCoopComms.lua"))()
    modules.CRCoopRespawn = assert(loadfile("Scripts/CRCoopRespawn.lua"))()
    modules.CRCoop = assert(loadfile("Scripts/CRCoop.lua"))()
    dofile("Scripts/misn13.lua")
    if beforeStart then beforeStart() end
    Start()
    Update(0.05)
    return Save()
end
-- The CCA's AIP units are team 5; everything else a test spawns is a human (team 1) object.
local function spawn(odf, team)
    local h = object(odf, team or (odf:sub(1, 2) == "sv" and 5 or 1))
    AddObject(h)
    return h
end
local function kill(h) objects[h].alive = false end
local function near(h, target, distance)
    distances[h] = distances[h] or {}
    distances[h][target] = distance
end
local function tick(t) now = t; Update(0.05) end

local m = reset()
check(m.start_done and count("AudioMessage", "misn1300.wav") == 1, "opening briefing")
check(scrap[1] == 40 and scrap[5] == 200, "starting resources")
check(count("SetPilot", 1, 10) == 1 and count("SetPilot", 5, 40) == 1, "starting pilots")
check(count("AddObjective", "misn1300.otf", "white") == 1, "source objective")
check(count("SetObjectiveName", m.nav1, "Drop Zone") == 1, "native camera name")
check(count("BuildObject", "svtank") == 1 and count("Defend", m.escort_tank) == 1, "artillery escort")
check(count("Follow", m.tank1, m.ccamuf) == 1 and count("Follow", m.tank3, m.center) == 1, "initial tank assignments")
check(m.artil_move_time == 900 and m.next_wave_time == 300 and m.artil_lost, "native timers and unused latch")
check(count("Retreat", m.turret1, "turret_path1") == 1 and count("Defend", m.turret3) == 1, "turret startup")
tick(5); check(not m.first_wave, "first wave strict boundary")
tick(6); check(m.first_wave and count("Attack", m.tank3, m.nsdfrecycle) == 1, "first wave targets recycler")
check(count("Attack", m.fighter6, m.nsdfrecycle) == 1, "fighters join first wave")
tick(11); check(not m.second_wave, "second wave strict boundary")
tick(12); check(m.second_wave and count("Goto", m.fighter1, "choke_point1") == 1, "second wave staging")
tick(72); check(count("SetAIP", "misn13.aip") == 0, "AIP strict boundary")
tick(73); check(count("SetAIP", "misn13.aip") == 1 and m.set_aip_time == 313, "normal AIP start")
tick(313); check(count("SetAIP", "misn13.aip") == 1, "AIP repeat strict boundary")
tick(314); check(count("SetAIP", "misn13.aip") == 2 and not m.set_aip, "source AIP repeats")
check(count("AudioMessage", "misn1300.wav") == 1, "briefing is one shot")

-- Every silo combination, including skipped thresholds and one-shot clamps.
for mask = 0, 15 do
    m = reset()
    local dead = 0
    for i = 1, 4 do
        if math.floor(mask / 2^(i-1)) % 2 == 1 then kill(m["ccasilo" .. i]); dead = dead + 1 end
    end
    tick(1)
    check(scrap[5] == 200 - dead * 50, "scrap clamp for mask " .. mask)
    check(m.silo1_lost == (dead >= 1) and m.silo2_lost == (dead >= 2)
        and m.silo3_lost == (dead >= 3) and m.silos_gone == (dead == 4), "silo threshold latches " .. mask)
    check(not m.silo4_lost, "unused fourth latch retained " .. mask)
    scrap[5] = 200; tick(2)
    check(scrap[5] == 200, "one-shot silo clamp " .. mask)
end
m = reset(); kill(m.ccasilo2); scrap[5] = 150; tick(1)
check(not m.silo1_lost and scrap[5] == 150, "equal scrap threshold does not latch")
scrap[5] = 151; tick(2); check(m.silo1_lost and scrap[5] == 150, "later excess scrap clamps")

m = reset()
near(m.turret5, m.ccasilo1, 59); near(m.turret6, m.ccasilo1, 59)
near(m.turret1, m.key_geyser1, 99); near(m.turret2, m.key_geyser1, 99)
tick(120); check(not m.silo_defend, "turret poll strict boundary")
tick(121); check(m.silo_defend and not m.turret1_set, "shared source timer defers geyser staging")
tick(125); check(m.turret1_set and m.turret2_set, "geyser staging after silo defense")
check(count("Goto", m.turret2, m.key_geyser2) == 1, "turret2 source test and destination differ")
objects[m.ccasilo3].health = 0.95; tick(125); check(not m.silos_attacked, "silo damage strict boundary")
objects[m.ccasilo3].health = 0.94; tick(126); check(m.silos_attacked, "silo alarm")
tick(128); check(count("Goto", m.tank1, "silo_spot") == 0, "defense delay strict boundary")
tick(129); check(count("Goto", m.tank1, "silo_spot") == 1, "silo reinforcements")
check(count("Goto", m.tank4, "silo_spot") == 2, "source duplicate tank4 command retained")
tick(250); check(count("Goto", m.tank1, "silo_spot") == 2, "silo orders repeat at 120 seconds")
kill(m.turret3); kill(m.turret4); tick(251); check(m.choke_bridged, "chokepoint state")

-- Capture order, ODF extension handling, and callbacks before Start.
local earlyFactory
m = reset(function() earlyFactory = spawn("avmuf.odf") end)
check(m.nsdfmuf == earlyFactory, "pre-Start callback retained")
local apc1, apc2 = spawn("svapc13"), spawn("svapc13.odf")
local hr1, hr2 = spawn("svhr13"), spawn("svhr13.odf")
local escorts = {}
for i = 1, 4 do escorts[i] = spawn("svtk13") end
check(m.sv1 == apc1 and m.sv2 == apc2 and m.sv3 == hr1 and m.sv4 == hr2, "bomber capture slots")
check(m.tank5 == escorts[1] and m.tank8 == escorts[4], "escort capture slots")
local tower, comm = spawn("abtowe"), spawn("abcomm")
tick(1)
check(m.make_bomber and m.bomber_attack and not m.hold_aip, "three-unit bomber handoff")
check(count("SetAIP", "misn13a.aip") == 1, "bomber AIP")
check(count("Attack", hr1, tower) == 1 and count("Attack", hr2, tower) == 1, "howitzers prefer gun tower")
check(count("Attack", apc1, comm) == 1 and count("Attack", apc2) == 0, "only first APC attacks")
check(count("Follow", escorts[2], apc1) == 1 and count("Follow", escorts[1]) == 0, "source escort branch nesting")
kill(tower); tick(2)
check(m.new_target and count("Attack", hr1, comm) == 1, "bombers retarget communications")
kill(comm); tick(3)
check(count("Attack", hr1, earlyFactory) == 0, "source retarget latch remains one shot")
kill(hr1); kill(hr2); tick(4)
check(not m.bomber_attack and not m.make_bomber and not m.new_target, "both-howitzers-dead reset")
local replacement = spawn("svhr13")
check(m.sv3 == hr1 and m.sv4 == hr2 and replacement ~= m.sv3, "source first-captured dead slots retained")
check(count("Retreat", apc1) == 0 and not m.bomber_reload, "cut retreat and reload remain disabled")

m = reset(); m.nsdfmuf = spawn("avmuf"); spawn("abcomm")
local onlyHr1, onlyHr2 = spawn("svhr13"), spawn("svhr13")
tick(1)
check(count("Attack", onlyHr1, m.nsdfmuf) == 1 and count("Attack", onlyHr2, m.nsdfmuf) == 1, "initial fallback prefers factory")
check(m.hold_aip and not m.bomber_attack, "missing APC holds normal AIP")
m.set_aip_time = 0; tick(2)
check(count("SetAIP", "misn13.aip") == 0, "hold suppresses normal AIP")

m = reset(); objects[m.ccamuf].health = 0.90; tick(1)
check(not m.muf_attacked, "factory damage strict boundary")
objects[m.ccamuf].health = 0.89; tick(2)
check(m.muf_attacked and scrap[5] == 240 and m.safe_time_check == 122, "factory defense and scrap bonus")
check(count("SetAIP", "misn13c.aip") == 1, "factory defense AIP")
near(m.turret1, m.ccamuf, 59); tick(3)
check(m.turret1_muf and count("Defend", m.turret1) == 1, "factory turret deploy")
tick(122); check(count("CountUnitsNearObject") == 0, "factory count strict boundary")
tick(123); check(count("CountUnitsNearObject") == 1 and not m.muf_safe, "factory remains threatened")
nearby = 1; tick(123.05)
check(m.muf_safe and not m.muf_attacked and count("CountUnitsNearObject") == 2, "native discarded comparison preserves every-frame poll")
tick(124); check(count("AddScrap", 5, 40) == 1, "factory safety latch prevents repeated bonus")
local function killBase(m, except)
    for _, h in ipairs({m.ccamuf, m.hangar, m.ccasilo1, m.ccasilo2, m.ccasilo3, m.ccasilo4}) do
        if h ~= except then kill(h) end
    end
end
m = reset(); objects[m.ccamuf].health = 0.8; tick(1); killBase(m); tick(122)
check(count("CountUnitsNearObject") == 0 and count("SucceedMission", 137) == 1, "destroyed factory guard preserves victory")

m = reset(); local scav1, scav2, scav3 = spawn("avscav"), spawn("avscav"), spawn("avscav")
tick(900); check(not m.artil_move, "artillery strict boundary")
tick(901); check(m.artil_move and count("Retreat", m.artil4, "artil_path1") == 1, "artillery march at 15 minutes")
near(m.artil4, m.split_geyser, 20); tick(912); check(not m.artil_move2, "artillery range strict boundary")
near(m.artil4, m.split_geyser, 19); tick(918)
check(m.artil_move2 and m.artil_set_time == 1038, "artillery splits at geyser")
check(count("Goto", m.artil3, "artil_point3") == 1 and count("SetIndependence", m.artil3, 1) == 1, "artillery positions and initiative")
check(count("Follow", m.escort_tank, m.artil1) == 1, "escort follows artillery1")
tick(1038); check(not m.artil_set, "artillery attack strict boundary")
tick(1039)
check(m.artil_set and count("Attack", m.artil1, scav1) == 1 and count("Attack", m.artil2, scav3) == 1, "artillery target priorities")
objects[scav2].shooter = m.artil3; tick(1040)
check(m.artil_message and count("AudioMessage", "misn1302.wav") == 1, "artillery warning recognizes opaque shooter")
tick(1041); check(count("AudioMessage", "misn1302.wav") == 1, "artillery warning one shot")
for _, victim in ipairs({"nsdfrecycle", "nsdfmuf", "avscav1", "avscav2", "avscav3"}) do
    m = reset(); spawn("avmuf"); spawn("avscav"); spawn("avscav"); spawn("avscav")
    m.artil_move2 = true; objects[m[victim]].shooter = m.artil4; tick(1)
    check(m.artil_message, "warning victim " .. victim)
end
m = reset(); m.artil_move2 = true; m.artil1 = nil; tick(1)
check(not m.artil_message, "nil shooter never matches nil artillery")
m = reset(); objects[m.artil4] = nil; tick(901); tick(912)
check(not m.artil_move2, "missing lead artillery cannot trip range gate")

m = reset(); scrap[5] = 39; tick(60)
check(not m.scav_swap, "scavenger timer strict boundary")
tick(61); check(m.scav_swap and count("BuildObject", "svscav") == 4, "four scavenger replacements")
check(not IsValid(m.svscav1) and count("Goto", m.svscav5, m.center_geyser) == 1, "replacement routing")
tick(200); check(count("BuildObject", "svscav") == 4, "scavenger swap one shot")
m = reset(); scrap[5] = 40; tick(61); check(not m.scav_swap, "scavenger scrap strict boundary")
scrap[5] = 39; tick(122); check(m.scav_swap, "later low scrap wakes scavengers")
m = reset(); objects[m.svscav1] = nil; kill(m.svscav2); scrap[5] = 39; tick(61)
check(m.scav_swap and count("BuildObject", "svscav") == 2, "dead scavengers stay lost")

-- Simulate engine serialization with a fresh Lua module and a copied state.
m = reset(); spawn("avmuf"); spawn("svapc13"); spawn("svhr13"); tick(6)
local saved = {}; for k, v in pairs(Save()) do saved[k] = v end
local opening = count("AudioMessage", "misn1300.wav")
dofile("Scripts/misn13.lua"); Load(saved); tick(7)
check(Save() == saved and saved.first_wave and saved.nsdfmuf == m.nsdfmuf, "save/load preserves handles and latches")
check(count("AudioMessage", "misn1300.wav") == opening, "save/load does not replay startup")
local postLoad = spawn("svhr13"); check(saved.sv4 == postLoad, "post-load callbacks use restored state")
check(type(saved.sv3) == "userdata", "handles remain opaque")

m = reset(); kill(m.nsdfrecycle); kill(m.ccamuf); tick(1)
check(m.game_over and count("FailMission", 16, "misn13f1.des") == 1 and count("SucceedMission") == 0, "failure wins simultaneous destruction")
tick(2); check(count("FailMission") == 1, "failure one shot")
-- CR win: the Unit Factory, the hangar (svguntower2) and all four silos.
m = reset(); kill(m.ccamuf); tick(1)
check(not m.game_over and count("SucceedMission") == 0 and count("AudioMessage", "misn1303.wav") == 0,
    "the factory alone no longer wins")
for i = 1, 3 do kill(m["ccasilo" .. i]) end
kill(m.hangar); tick(2)
check(not m.game_over and count("SucceedMission") == 0, "three silos are not four")
kill(m.ccasilo4); tick(3)
check(m.game_over and count("SucceedMission", 18, "misn13w1.des") == 1 and count("AudioMessage", "misn1303.wav") == 1,
    "factory + hangar + four silos win and play misn1303")
tick(4); check(count("SucceedMission") == 1 and count("AudioMessage", "misn1303.wav") == 1, "victory one shot")
m = reset(); killBase(m, m.hangar); tick(1)
check(not m.game_over, "a living hangar blocks the win")
kill(m.hangar); tick(2); check(m.game_over and count("SucceedMission") == 1, "the hangar completes the win")
m = reset(); killBase(m, m.ccasilo2); tick(1)
check(not m.game_over, "one living silo blocks the win")
kill(m.ccasilo2); tick(2); check(m.game_over, "the last silo completes the win")
m = reset(); killBase(m); kill(m.nsdfrecycle); tick(1)
check(m.game_over and count("FailMission") == 1 and count("SucceedMission") == 0, "loss still beats a simultaneous win")
m = reset(); m.hangar = nil; kill(m.ccamuf); for i = 1, 4 do kill(m["ccasilo" .. i]) end; tick(1)
check(m.game_over and count("SucceedMission") == 1, "a hangar the map never provided cannot block the win")

-- ---------------------------------------------------------------- CR co-op layer, offline semantics
local function built(odf, team, where)
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == "BuildObject" and c[2] == odf and (team == nil or c[3] == team) and (where == nil or c[4] == where) then n = n + 1 end
    end
    return n
end
local function builtHandles(odf, where)
    local list = {}
    for _, c in ipairs(calls) do
        if c[1] == "BuildObject" and c[2] == odf and c[4] == where then list[#list + 1] = c[5] end
    end
    return list
end
local function lastText(key)
    for i = #calls, 1, -1 do
        local c = calls[i]
        if (c[1] == "UpdateObjective" or c[1] == "AddObjective") and c[2] == key then return c[5], c[3] end
    end
end

m = reset()
check(count("SetAIControl", 5, true) == 1, "the CCA team is AI-controlled once, at chunk load")
check(count("SetAIP", "misn13.aip") == 0, "SetAIP stays in Update")
tick(6); tick(12); tick(73); check(count("SetAIP", "misn13.aip", 5) == 1, "the DLL AIP is set on the CCA team")
check(m.hangar == GetHandle("svguntower2") and m.escorts[3] == GetHandle("artil_escort3")
    and m.reserves[2] == GetHandle("cca_reserve2"), "co-op handles resolve by their map labels")

-- Objectives: the stock line first (kept for the DLL), then the CR progress list.
m = reset()
check(count("ClearObjectives") == 2 and count("AddObjective", "misn13_recycler") == 1
    and count("AddObjective", "misn13_factory") == 1 and count("AddObjective", "misn13_hangar") == 1
    and count("AddObjective", "misn13_silos") == 1, "the four objectives replace the stock one")
check(lastText("misn13_silos") == "Destroy the CCA silos (0/4)", "silo progress text")
kill(m.ccasilo1); tick(1)
check(lastText("misn13_silos") == "Destroy the CCA silos (1/4)", "silo progress counts")
kill(m.hangar); kill(m.ccamuf); tick(2)
local _, color = lastText("misn13_hangar"); check(color == "green", "hangar objective completes")
_, color = lastText("misn13_factory"); check(color == "green", "factory objective completes")
local updates = count("UpdateObjective"); tick(2.5)
check(count("UpdateObjective") == updates, "objectives update only on change")
m = reset(); kill(m.nsdfrecycle); tick(1)
_, color = lastText("misn13_recycler"); check(color == "red", "recycler loss is red")

-- misn1301: 25 s after the first attack, once.
m = reset(); tick(6)
check(m.first_wave and m.collins_time == 31, "misn1301 is timed from the first attack")
tick(31); check(count("AudioMessage", "misn1301.wav") == 0, "misn1301 strict boundary")
tick(31.5); check(count("AudioMessage", "misn1301.wav") == 1 and m.collins_done, "misn1301 plays")
tick(60); check(count("AudioMessage", "misn1301.wav") == 1, "misn1301 one shot")
check(31 - 6 > 0 and 31 > 21.8, "misn1301 follows the 22 s opening briefing")
m = reset(); tick(6); kill(m.nsdfrecycle); tick(7); tick(40)
check(count("AudioMessage", "misn1301.wav") == 0, "no misn1301 after the mission is over")

-- Restored waves 2-4.
m = reset()
check(m.next_wave_time == 300, "the DLL next_wave_time schedules wave 2")
tick(300); check(not m.wave2 and built("svtank", 5, m.spawn_point1) == 0, "wave 2 strict boundary")
tick(301)
check(m.wave2 and not m.wave3 and m.next_wave_time == 601, "wave 2 is built and wave 3 scheduled 300 s later")
local w2 = builtHandles("svtank", m.spawn_point1)
check(#w2 == 2 and #builtHandles("svfigh", m.spawn_point1) == 1, "wave 2 is two svtank and one svfigh at spawn_geyser1")
for _, h in ipairs(w2) do
    check(objects[h].team == 5 and count("Goto", h, "choke_point3") == 1, "wave 2 heads for choke_point3")
end
local lead = w2[1]
tick(304); check(not m.wave2_move, "wave 2 holds at the choke point until its lead arrives")
near(lead, "choke_point3", 149); tick(306)
check(m.wave2_move and count("Goto", w2[2], "turret_path3") == 1, "wave 2 takes turret_path3")
tick(308); check(not m.wave2_done, "wave 2 follows the path")
near(lead, m.checkpoint1, 200); tick(310)
check(m.wave2_done and count("Attack", w2[1], m.nsdfrecycle) == 1 and count("Attack", w2[2], m.nsdfrecycle) == 1,
    "wave 2 finally attacks the Recycler")
check(built("svtank", 5, m.spawn_point2) == 0, "wave 3 is not early")
tick(601); check(not m.wave3, "wave 3 strict boundary")
tick(602)
check(m.wave3 and #builtHandles("svtank", m.spawn_point2) == 2 and #builtHandles("svfigh", m.spawn_point2) == 2,
    "wave 3 is two svtank and two svfigh at spawn_geyser2")
check(count("Goto", builtHandles("svfigh", m.spawn_point2)[1], "choke_point2") == 1, "wave 3 uses choke_point2")
tick(903); check(m.wave4, "wave 4 follows 300 s later")
tick(906); check(m.next_wave_time == 99999, "wave 4 is the last")
tick(1500); check(built("svtank", 5, m.spawn_point2) == 5, "no fifth wave")
-- A wave that never reaches its choke point moves on by timeout.
m = reset(); tick(301); tick(421); check(not m.wave2_move, "choke timeout strict boundary")
tick(423); check(m.wave2_move, "choke timeout")
-- Gates: the factory death stops the reinforcements; the live cap postpones a wave.
m = reset(); kill(m.ccamuf); tick(301)
check(not m.wave2, "no reinforcements once the Unit Factory is gone")
m = reset()
local cap = {}
for i = 1, 16 do cap[i] = object("svtank", 5) end
m.wave_units[1] = cap
tick(301); check(not m.wave2 and m.next_wave_time == 331, "the live cap postpones the wave")
for i = 1, 5 do kill(cap[i]) end
tick(332); check(m.wave2, "the wave follows once units fall below the cap")
-- Wave units are never tracked as the AIP units.
m = reset(); tick(301)
check(m.tank5 == nil and m.sv1 == nil, "wave units do not take the AIP capture slots")
-- Opening rush extras: none for one human.
m = reset(); tick(6)
check(m.rush_extras and built("svtank", 5, "choke_point1") == 0, "a single human gets the DLL rush unchanged")

-- Escorts: three DEFEND tanks join the artillery march.
m = reset()
for i = 1, 3 do check(count("Defend", m.escorts[i]) == 1, "escort " .. i .. " guards at the start") end
tick(1); check(count("Defend", m.escorts[1]) == 1, "escorts are ordered once")
tick(901)
for i = 1, 3 do check(count("Retreat", m.escorts[i], "artil_path1") == 1, "escort " .. i .. " marches with the artillery") end
check(count("Follow", m.escorts[1]) == 0, "escorts wait for the split before following")
near(m.artil4, m.split_geyser, 19); tick(912)
check(m.artil_move2 and count("Follow", m.escorts[1], m.artil1) == 1 and count("Follow", m.escorts[2], m.artil2) == 1
    and count("Follow", m.escorts[3], m.artil3) == 1, "each escort follows a howitzer")
kill(m.artil2); tick(920)
check(count("Follow", m.escorts[2], m.artil1) == 1, "an escort whose howitzer died follows another")
tick(930); check(count("Follow", m.escorts[2], m.artil1) == 1, "the follow order is not repeated")
local followed = count("Follow", m.escorts[1])
kill(m.escorts[1]); tick(940); check(count("Follow", m.escorts[1]) == followed, "dead escorts are not ordered")

-- Reserve: the two idle (get-bomb) tanks guard the factory and the silos.
m = reset()
for i = 1, 2 do check(count("Defend", m.reserves[i]) == 1, "reserve " .. i .. " guards") end
objects[m.ccamuf].health = 0.89; tick(2)
check(m.muf_attacked and count("Goto", m.reserves[1], m.ccamuf) == 1 and count("Goto", m.reserves[2], m.ccamuf) == 1,
    "the reserve answers a factory attack")
near(m.reserves[1], m.ccamuf, 59); tick(3)
check(count("Defend", m.reserves[1]) == 2 and count("Defend", m.reserves[2]) == 1, "an arrived reserve holds the factory")
tick(92); check(count("Goto", m.reserves[1], m.ccamuf) == 1, "the held reserve is not re-sent")
tick(94); tick(95)
check(count("Goto", m.reserves[1], m.ccamuf) == 2, "the reserve returns to guard and answers again")
m = reset(); objects[m.ccasilo3].health = 0.94; tick(1)
check(m.silos_attacked and count("Goto", m.reserves[1], "silo_spot") == 1 and count("Goto", m.reserves[2], "silo_spot") == 1,
    "the reserve answers a silo attack")
kill(m.reserves[2]); near(m.reserves[1], "silo_spot", 59); tick(4)
check(count("Defend", m.reserves[1]) == 2, "an arrived reserve holds silo_spot")

-- Team filters on the DLL first-come capture slots.
m = reset()
local humanApc, ccaApc = spawn("svapc13", 1), spawn("svapc13", 5)
check(m.sv1 == ccaApc and m.sv2 == nil, "a human-team look-alike never takes a CCA bomber slot")
local alliedTank, ccaTank = spawn("svtk13", 1), spawn("svtk13", 5)
check(m.tank5 == ccaTank and m.tank6 == nil, "AIP tanks must be CCA")
local ccaTower, humanTower = spawn("abtowe", 5), spawn("abtowe", 3)
check(m.guntower1 == humanTower, "only a human tower is the bombers target (guest teams count)")
local ccaMuf, firstMuf, secondMuf = spawn("avmuf", 5), spawn("avmuf", 2), spawn("avmuf", 1)
check(m.nsdfmuf == firstMuf, "avmuf is first-come among human teams")
local s5, s4 = spawn("avscav", 5), spawn("avscav", 4)
check(m.avscav1 == s4 and m.avscav2 == nil, "CCA scavengers never take the human scavenger slots")
local comm5, comm2 = spawn("abcomm", 5), spawn("abcomm", 2)
check(m.controltower == comm2, "only a human comm tower is tracked")
local rig5, rig3 = spawn("avcnst", 5), spawn("avcnst", 3)
check(m.nsdfrig == rig3, "constructor slot is human-only")
local ok = pcall(AddObject, nil); check(ok, "AddObject tolerates nil")

-- misn1302 now works for any human craft.
m = reset(); m.artil_move2 = true
objects[labels.player].shooter = m.artil3; tick(1)
check(m.artil_message and count("AudioMessage", "misn1302.wav") == 1, "artillery warning fires for a player craft")
tick(2); check(count("AudioMessage", "misn1302.wav") == 1, "artillery warning is one shot")
m = reset(); m.artil_move2 = true; objects[labels.player].shooter = GetHandle("svfigh_other"); tick(1)
check(not m.artil_message, "a non-artillery shooter never warns")

-- Factory-safety count: every human team, threshold grows with the players (one here).
m = reset(); objects[m.ccamuf].health = 0.8; tick(1); nearby = 2; tick(122); tick(123)
check(not m.muf_safe, "two human units near the factory keep it threatened")
nearby = 1; tick(124); check(m.muf_safe, "one human unit near the factory is safe")
print("misn13: " .. checks .. " checks passed (" .. _VERSION .. ")")
