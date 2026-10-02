-- Run from the repository root with Lua 5.1. Handles are opaque userdata.
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
function GetHandle(label)
    if not labels[label] then labels[label] = object("svtank", 2) end
    return labels[label]
end
function GetPlayerHandle() return GetHandle("player") end
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
    record("BuildObject", odf, team, where)
    AddObject(h)
    return h
end
function RemoveObject(h) objects[h] = nil; record("RemoveObject", h) end
function SetScrap(team, amount) scrap[team] = amount; record("SetScrap", team, amount) end
function AddScrap(team, amount) scrap[team] = scrap[team] + amount; record("AddScrap", team, amount) end
function GetScrap(team) return scrap[team] end
for _, name in ipairs({"AudioMessage", "ClearObjectives", "AddObjective", "SetPilot",
    "SetObjectiveName", "Defend", "Retreat", "Goto", "Follow", "Attack",
    "SetAIP", "SetIndependence", "FailMission", "SucceedMission"}) do
    local operation = name
    _G[operation] = function(...) record(operation, ...) end
end
local function reset(beforeStart)
    now, nearby = 0, 3
    objects, labels, calls, distances, scrap = {}, {}, {}, {}, {}
    dofile("Scripts/misn13.lua")
    if beforeStart then beforeStart() end
    Start()
    Update(0.05)
    return Save()
end
local function spawn(odf)
    local h = object(odf, 1)
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
check(scrap[1] == 40 and scrap[2] == 200, "starting resources")
check(count("SetPilot", 1, 10) == 1 and count("SetPilot", 2, 40) == 1, "starting pilots")
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
    check(scrap[2] == 200 - dead * 50, "scrap clamp for mask " .. mask)
    check(m.silo1_lost == (dead >= 1) and m.silo2_lost == (dead >= 2)
        and m.silo3_lost == (dead >= 3) and m.silos_gone == (dead == 4), "silo threshold latches " .. mask)
    check(not m.silo4_lost, "unused fourth latch retained " .. mask)
    scrap[2] = 200; tick(2)
    check(scrap[2] == 200, "one-shot silo clamp " .. mask)
end
m = reset(); kill(m.ccasilo2); scrap[2] = 150; tick(1)
check(not m.silo1_lost and scrap[2] == 150, "equal scrap threshold does not latch")
scrap[2] = 151; tick(2); check(m.silo1_lost and scrap[2] == 150, "later excess scrap clamps")

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
check(m.muf_attacked and scrap[2] == 240 and m.safe_time_check == 122, "factory defense and scrap bonus")
check(count("SetAIP", "misn13c.aip") == 1, "factory defense AIP")
near(m.turret1, m.ccamuf, 59); tick(3)
check(m.turret1_muf and count("Defend", m.turret1) == 1, "factory turret deploy")
tick(122); check(count("CountUnitsNearObject") == 0, "factory count strict boundary")
tick(123); check(count("CountUnitsNearObject") == 1 and not m.muf_safe, "factory remains threatened")
nearby = 1; tick(123.05)
check(m.muf_safe and not m.muf_attacked and count("CountUnitsNearObject") == 2, "native discarded comparison preserves every-frame poll")
tick(124); check(count("AddScrap", 2, 40) == 1, "factory safety latch prevents repeated bonus")
m = reset(); objects[m.ccamuf].health = 0.8; tick(1); kill(m.ccamuf); tick(122)
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

m = reset(); scrap[2] = 39; tick(60)
check(not m.scav_swap, "scavenger timer strict boundary")
tick(61); check(m.scav_swap and count("BuildObject", "svscav") == 4, "four scavenger replacements")
check(not IsValid(m.svscav1) and count("Goto", m.svscav5, m.center_geyser) == 1, "replacement routing")
tick(200); check(count("BuildObject", "svscav") == 4, "scavenger swap one shot")
m = reset(); scrap[2] = 40; tick(61); check(not m.scav_swap, "scavenger scrap strict boundary")
scrap[2] = 39; tick(122); check(m.scav_swap, "later low scrap wakes scavengers")
m = reset(); objects[m.svscav1] = nil; kill(m.svscav2); scrap[2] = 39; tick(61)
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
m = reset(); kill(m.ccamuf); tick(1)
check(m.game_over and count("SucceedMission", 16, "misn13w1.des") == 1, "enemy factory victory")
tick(2); check(count("SucceedMission") == 1, "victory one shot")
print("misn13: " .. checks .. " checks passed (" .. _VERSION .. ")")
