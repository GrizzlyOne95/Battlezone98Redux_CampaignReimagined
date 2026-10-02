-- Run from the repository root: lua5.1 Tools/Test-Misn10.lua
assert(_VERSION == "Lua 5.1", "validate against the shipping Lua version")
local now, serial, objects, labels, distances, calls, cargo, scrap
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function record(name, ...)
    calls[#calls + 1] = {name, ...}
end
local function matches(call, name, ...)
    if call[1] ~= name then return false end
    local args = {...}
    for index, value in ipairs(args) do
        if call[index + 1] ~= value then return false end
    end
    return true
end
local function called(name, ...)
    for _, call in ipairs(calls) do
        if matches(call, name, ...) then return true end
    end
    return false
end
local function count(name)
    local total = 0
    for _, call in ipairs(calls) do if call[1] == name then total = total + 1 end end
    return total
end
local function object(odf, team)
    serial = serial + 1
    objects[serial] = {alive = true, odf = odf, team = team or 2}
    return serial
end
function GetHandle(label) return labels[label] end
function GetPlayerHandle() return labels.player end
function GetTime() return now end
function IsValid(h) return h ~= nil and objects[h] ~= nil end
function IsAlive(h) return IsValid(h) and objects[h].alive end
function IsOdf(h, odf) assert(IsValid(h)); return objects[h].odf == odf end
function GetTeamNum(h) assert(IsValid(h)); return objects[h].team end
function GetTug(h) assert(IsValid(h)); return cargo[h] end
function GetScrap(team) return scrap[team] or 0 end
function GetDistance(h, target)
    assert(IsValid(h) and IsValid(target), "invalid distance overload")
    return distances[tostring(h) .. ":" .. tostring(target)] or 10000
end
function SetScrap(team, amount) scrap[team] = amount; record("SetScrap", team, amount) end
function AudioMessage(name) record("AudioMessage", name); return 1 end
for _, name in ipairs({"SetAIControl", "SetPilot", "SetAIP", "ClearObjectives",
    "AddObjective", "SetObjectiveOn", "SetObjectiveName", "SetIndependence",
    "Goto", "Follow", "Pickup", "Defend", "Attack", "AddHealth",
    "SucceedMission", "FailMission", "StartEarthquake", "StopEarthquake", "BuildObject"}) do
    local operation = name
    _G[operation] = function(...) record(operation, ...) end
end
local function reset(started)
    now, serial = 0, 0
    objects, labels, distances, calls, cargo, scrap = {}, {}, {}, {}, {}, {}
    for _, label in ipairs({"player", "relic", "cam1", "cam2", "cam3", "svrecycler",
        "avrecycler", "post1_geyser", "post3_geyser", "geyser1", "geyser2",
        "geyser3", "geyser4", "geyser5", "geyser6", "geyser7", "svartil1",
        "svartil2", "svmuf"}) do
        labels[label] = object("label", label == "player" and 1 or 2)
    end
    dofile("Scripts/misn10.lua")
    Start()
    if started ~= false then Update(0.05) end
    return Save()
end
local function near(h, target, distance)
    distances[tostring(h) .. ":" .. tostring(target)] = distance
end
local function spawn(odf, team)
    local h = object(odf, team)
    AddObject(h)
    return h
end
local function kill(h, notify)
    objects[h].alive = false
    if notify then DeleteObject(h); objects[h] = nil end
end
local function clear() calls = {} end
local function armies()
    spawn("svhaul")
    for _ = 1, 3 do spawn("svartl"); spawn("svturr") end
    for _ = 1, 2 do spawn("svfigh"); spawn("svltnk") end
end
local function route(m, index)
    for i = 1, 7 do near(m.sav, m["geys" .. i], i == index and 10 or 1000 + i) end
end

local m = reset(false)
check(called("SetAIControl", 2, true) and count("SetAIControl") == 1, "AI enabled only at initialization")
check(m.sav_free and not m.start_done and m.quake_time == 4 and m.geys1check == 180, "native Setup defaults")
Update(0.05)
check(m.start_done and called("AudioMessage", "misn1000.wav"), "briefing")
check(called("AddObjective", "misn1000.otf", "white"), "original objective")
check(called("SetScrap", 1, 30) and called("SetScrap", 2, 40)
    and called("SetPilot", 1, 10) and called("SetPilot", 2, 40), "starting resources")
check(called("SetAIP", "misn10.aip"), "starting Soviet production")
check(called("SetObjectiveName", m.nav1, "Relic Site")
    and called("SetObjectiveName", m.nav2, "CCA Base")
    and called("SetObjectiveName", m.nav3, "Drop Zone"), "native beacon names")
check(m.turret1_check == 19 and m.turret2_check == 20
    and m.artil1_check == 21 and m.artil2_check == 22 and m.artil3_check == 23, "staggered defense timers")
check(not m.chase_tug and not called("Attack"), "nil carrier never chased")
near(m.user, m.sav, 100); clear(); Update(0.05)
check(not m.objective_on, "objective distance is strict")
near(m.user, m.sav, 99); Update(0.05)
check(m.objective_on and called("SetObjectiveOn", m.sav)
    and called("SetObjectiveName", m.sav, "Alien Relic"), "nearby relic marker")
clear(); Update(0.05)
check(not called("AudioMessage") and not called("SetObjectiveOn"), "one-shot startup/marker")

m = reset(); armies(); route(m, 1); scrap[2] = 15
near(m.ccaturret1, m.geys1, 49); near(m.ccaturret2, m.geys2, 49)
near(m.ccaartil1, m.post1_geyser, 19); near(m.ccaartil2, m.post3_geyser, 19)
near(m.ccaartil3, m.geys2, 49); near(m.ccaturret3, m.ccarecycle, 30)
clear(); Update(0.05)
check(called("Follow", m.ccafighter1, m.sav) and called("Follow", m.ccafighter2, m.sav), "fighters secure relic")
check(called("Goto", m.ccaturret1, "relic_path1")
    and called("Goto", m.ccaturret2, "relic_path1"), "turret routes")
check(called("Goto", m.ccaartil1, "artil1_path", 1)
    and called("Goto", m.ccaartil2, "artil2_path", 1)
    and called("Goto", m.ccaartil3, "relic_path1"), "artillery routes and priorities")
check(not m.plan_a and not m.turret3_underway, "AIP scrap and base turret strict thresholds")
scrap[2] = 16; near(m.ccaturret3, m.ccarecycle, 31); Update(0.05)
check(m.plan_a and called("SetAIP", "misn10a.aip"), "AIP A activates after four defenders")
check(m.turret3_underway and called("Defend", m.ccaturret3), "third turret defends base")
now = 19; clear(); Update(0.05)
check(not m.turret1_stop, "timer exact boundary")
now = 19.1; Update(0.05)
check(m.turret1_stop and called("Defend", m.ccaturret1) and m.turret1_check == 22.1, "first turret three-second poll")
now = 24; Update(0.05)
check(m.turret2_stop and m.artil1_stop and m.artil2_stop and m.artil3_stop, "remaining defense placements")
check(not called("SetAIP", "misn10b.aip"), "cut AIP B stays disabled")

local outgoing = {"relic_path1", "relic_path1", "attack_path_central", "attack_path_central",
    "attack_path_south", "attack_path_north", "attack_path_south"}
local returning = {"main_return_path", false, "lsouth_return_path", "main_return_path",
    "ssouth_return_path", "main_return_path", "msouth_return_path"}
for index = 1, 7 do
    m = reset(); armies(); route(m, index); clear(); Update(0.05)
    check(m.got_position and m["position" .. index] and m["tug_underway" .. index]
        and called("Goto", m.ccatug, outgoing[index], 1), "outgoing route " .. index)
    check(called("Follow", m.ccatank1, m.ccatug, 1)
        and called("Follow", m.ccatank2, m.ccatug, 1), "tank escort " .. index)
    near(m.ccatug, m.sav, 90); near(m.ccatug, m["geys" .. index], 120)
    clear(); Update(0.05)
    check(m.tug_after_sav and called("Pickup", m.ccatug, m.sav, 1), "early pickup " .. index)
    check((index == 1) == called("Follow", m.ccatank1, m.ccatug, 0), "route-one-only escort priority change " .. index)
    cargo[m.sav] = m.ccatug; clear(); Update(0.05)
    check(m.sav_seized and m.return_to_base and called("Goto", m.ccatug, returning[index] or m.ccarecycle, 1), "return route " .. index)
    check(called("AudioMessage", "misn1005.wav") and not called("Attack"), "CCA warning without friendly fire " .. index)
    check(not m.chase_tug, "CCA carrier does not suppress bombardment " .. index)
    clear(); Update(0.05)
    check(not called("AudioMessage", "misn1005.wav"), "seizure warning once " .. index)

    m = reset(); spawn("svhaul"); route(m, index); Update(0.05)
    near(m.ccatug, m["geys" .. index], 100); clear(); Update(0.05)
    check(not m.tug_after_sav, "pickup threshold is strict " .. index)
    near(m.ccatug, m["geys" .. index], 99); Update(0.05)
    check(m.tug_after_sav and called("Pickup", m.ccatug, m.sav, 1), "geyser fallback pickup " .. index)
end

m = reset(); spawn("svhaul")
near(m.sav, m.geys3, 10); near(m.sav, m.geys5, 10)
Update(0.05)
check(m.position3 and m.got_position and m.tug_underway3, "exact tie uses lowest nearest geyser")
m.got_position = false; near(m.sav, m.geys3, 20); near(m.sav, m.geys5, 5); near(m.sav, m.geys6, 5)
Update(0.05)
check(m.position5 and not m.position3, "tie replaces a stale previous position")
m = reset(false); for i = 1, 7 do objects[m["geys" .. i]] = nil end
spawn("svhaul"); Update(0.05)
check(not m.got_position and not m.tug_underway1 and not m.game_over, "missing geysers do not create an empty committed route")

m = reset(); armies(); route(m, 3); Update(0.05)
local playerTug = object("avhaul", 1); cargo[m.sav] = playerTug
near(m.ccatug, m.geys3, 49); clear(); Update(0.05)
check(m.sav_secure and not m.sav_free and m.tugger == playerTug, "player relic acquisition")
check(m.tug_wait3 and not m.tug_underway3 and called("Goto", m.ccatug, m.geys3, 1), "CCA tug waits on player acquisition")
for _, field in ipairs({"ccafighter1", "ccafighter2", "ccatank1", "ccatank2",
    "svartil1", "svartil2", "ccaartil1", "ccaartil2", "ccaartil3"}) do
    check(called("Attack", m[field], playerTug, 1), "player tug pursuer " .. field)
end
clear(); Update(0.05)
check(not called("Attack") and m.chase_tug, "pursuit one-shot with all pursuers alive")
cargo[m.sav] = nil; kill(playerTug); clear(); Update(0.05)
check(m.sav_free and not m.sav_secure and not m.chase_tug and not called("Attack"), "dead player tug frees relic and stops invalid pursuit")

for index = 2, 7 do
    m = reset(); armies(); route(m, index); Update(0.05)
    near(m.ccatug, m.sav, 90); near(m.ccatug, m["geys" .. index], 120); Update(0.05)
    cargo[m.sav] = object("avhaul", 1); clear(); Update(0.05)
    check(m["tug_wait" .. index] and not m.tug_after_sav
        and called("Goto", m.ccatug, m["geys" .. index], 1), "pickup interruption wait route " .. index)
end

m = reset(); armies(); route(m, 1); Update(0.05)
cargo[m.sav] = m.ccatug; Update(0.05); cargo[m.sav] = nil
local oldTug = m.ccatug; kill(oldTug); clear(); Update(0.05)
check(m.sav_free and not m.sav_seized and not m.got_position
    and not m.return_to_base and not m.sav_warning, "destroyed CCA tug resets haul")
check(called("Goto", m.ccatank1, m.sav) and called("Goto", m.ccatank2, m.sav), "tanks guard dropped relic")
local replacement = spawn("svhaul.odf"); route(m, 7); clear(); Update(0.05)
check(m.ccatug == replacement and m.tug_underway7 and called("Goto", replacement, "attack_path_south", 1), "AIP tug replacement is routed")
check(called("Follow", m.ccatank1, replacement, 1) and called("Follow", m.ccatank2, replacement, 1), "surviving tanks escort the replacement carrier")

-- Replacement arriving before Update must not inherit old command flags.
m = reset(); armies(); route(m, 1); Update(0.05)
cargo[m.sav] = m.ccatug; Update(0.05); cargo[m.sav] = nil
oldTug = m.ccatug; kill(oldTug, true); replacement = spawn("svhaul")
check(m.ccatug == replacement and m.sav_free and not m.sav_seized
    and not m.return_to_base and not m.tug_after_sav, "between-update tug deletion/replacement")

local slots = {{"ccaartil1", "svartl", "artil1_underway"},
    {"ccaartil2", "svartl", "artil2_underway"}, {"ccaartil3", "svartl", "artil3_underway"},
    {"ccaturret1", "svturr", "turret1_underway"}, {"ccaturret2", "svturr", "turret2_underway"},
    {"ccaturret3", "svturr", "turret3_underway"}, {"ccafighter1", "svfigh", "fighter1_underway"},
    {"ccafighter2", "svfigh", "fighter2_underway"}, {"ccatank1", "svltnk", "tank1_follow"},
    {"ccatank2", "svltnk", "tank2_follow"}, {"ccamuf", "svmuf"}}
for _, entry in ipairs(slots) do
    m = reset(); armies(); route(m, 1); Update(0.05)
    local old = m[entry[1]]; kill(old, true)
    local new = spawn(entry[2])
    check(m[entry[1]] == new and (not entry[3] or not m[entry[3]]), "replacement state " .. entry[1])
    if entry[3] then clear(); Update(0.05); check(m[entry[3]], "replacement commanded " .. entry[1]) end
end
m = reset(); local first = spawn("svfigh"); AddObject(first)
check(m.ccafighter1 == first and m.ccafighter2 == nil, "duplicate callback occupies one slot")
local second = spawn("svfigh", 1)
check(m.ccafighter2 == second, "native ODF-only admission preserved")
local third = spawn("svfigh"); check(m.ccafighter2 ~= third, "living slots remain unchanged")
kill(first); local newFirst = spawn("svfigh")
check(m.ccafighter1 == newFirst, "dead handle replacement without DeleteObject callback")

m = reset(); now = 180; clear(); Update(0.05)
check(not called("Attack"), "bombardment strict initial timer")
now = 181; Update(0.05)
check(called("Attack", m.svartil1, m.geys1) and m.geys1check == 331, "periodic relic-site bombardment")
now = 332; near(m.user, m.geys1, 199); clear(); Update(0.05)
check(called("Attack", m.svartil1, m.user) and called("Attack", m.svartil2, m.user), "nearby player bombardment")
now = 483; near(m.user, m.geys1, 200); clear(); Update(0.05)
check(called("Attack", m.svartil1, m.geys1), "bombardment distance is strict")
m = reset(); now = 0; clear(); Update(0.05)
check(not called("AddHealth"), "heal strict zero boundary")
now = 0.1; Update(0.05)
check(called("AddHealth", m.sav, 100) and m.next_second == 1.1, "relic gains 100 raw health")
now = 1.1; clear(); Update(0.05); check(not called("AddHealth"), "heal strict next boundary")
now = 1.2; Update(0.05); check(count("AddHealth") == 1, "heal once per scheduled second")
now = 1000; Update(0.05)
check(not called("BuildObject") and not called("StartEarthquake") and not called("StopEarthquake"), "temporary spawns and quakes stay cut")

m = reset(); armies(); route(m, 6); Update(0.05)
local copy = {}; for key, value in pairs(Save()) do copy[key] = value end
clear(); Load(copy)
check(Save() == copy and copy.tug_underway6 and copy.ccatug == m.ccatug, "Save/Load state and handles")
Update(0.05)
check(not called("SetAIControl") and not called("SetAIP") and not called("AudioMessage")
    and not called("Goto"), "load does not replay setup, briefing, production, or routes")

m = reset(); cargo[m.sav] = object("avhaul", 1)
near(m.sav, m.nsdfrecycle, 100); clear(); Update(0.05)
check(not m.game_over, "delivery threshold is strict")
near(m.sav, m.nsdfrecycle, 99); kill(m.nsdfrecycle); now = 10; Update(0.05)
check(m.game_over and called("SucceedMission", 25, "misn10w1.des")
    and not called("FailMission"), "delivery retains precedence over simultaneous recycler death")
clear(); Update(0.05); check(not called("SucceedMission") and not called("FailMission"), "mission outcome once")
m = reset(); spawn("svhaul"); cargo[m.sav] = m.ccatug; near(m.sav, m.ccarecycle, 99)
clear(); Update(0.05)
check(called("FailMission", 15, "misn10f1.des") and called("AudioMessage", "misn1002.wav"), "CCA delivery failure")
m = reset(); kill(m.sav); kill(m.nsdfrecycle); clear(); Update(0.05)
check(called("FailMission", 15, "misn10f2.des") and not called("AudioMessage", "misn1004.wav"), "relic loss precedes Utah loss")
m = reset(); kill(m.nsdfrecycle); clear(); Update(0.05)
check(called("FailMission", 15, "misn10f3.des") and called("AudioMessage", "misn1004.wav"), "Utah loss failure")
m = reset(false); objects[m.sav] = nil; objects[m.nav1] = nil; clear(); Update(0.05)
check(called("FailMission", 15, "misn10f2.des") and not called("SetObjectiveOn"), "missing handles avoid false proximity victory/marker")

print("misn10: " .. checks .. " checks passed (" .. _VERSION .. ")")
