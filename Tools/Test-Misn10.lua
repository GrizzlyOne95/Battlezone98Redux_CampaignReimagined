-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Run from the repository root: lua5.1 Tools/Test-Misn10.lua
-- Offline (single-player) behavior of the co-op-capable misn10: the real CRCoop runs with
-- single-player semantics, so every check below is the DLL's own flow plus the documented
-- restored behavior (tug rebuild, plan B, pickup quake, Io weather beats, CCA scaling).
-- Multi-player behavior is out of scope here. Mock-host tests verify authored branching and
-- commands, not native AI or rendering.
assert(_VERSION == "Lua 5.1", "validate against the shipping Lua version")
local now, serial, objects, labels, distances, calls, cargo, scrap, wxState
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
local function count(name, ...)
    local total = 0
    for _, call in ipairs(calls) do
        if matches(call, name, ...) then total = total + 1 end
    end
    return total
end
local function last(name)
    for i = #calls, 1, -1 do
        if calls[i][1] == name then return calls[i] end
    end
end
local function firstIndex(name, ...)
    for i, call in ipairs(calls) do
        if matches(call, name, ...) then return i end
    end
end
local function object(odf, team)
    serial = serial + 1
    objects[serial] = {alive = true, odf = odf, team = team or 5}
    return serial
end
function GetHandle(label) return labels[label] end
function GetPlayerHandle() return labels.player end
function SetVector(x, y, z) return {x = x or 0, y = y or 0, z = z or 0} end
function GetLabel(h) return nil end
function GetPosition(h) return SetVector(0, 0, 0) end
function GetTerrainHeightAndNormal() return 20, SetVector(0, 1, 0) end
function DisplayMessage() end
function Ally() end
function UnAlly() end
function AllObjects()
    local i = 0
    return function()
        while i < serial do
            i = i + 1
            if objects[i] then return i end
        end
    end
end
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
function AudioMessage(name)
    record("AudioMessage", name)
    return {name = name}
end
function BuildObject(odf, team, where)
    local h = object(odf, team)
    record("BuildObject", odf, team, where, h)
    AddObject(h) -- Native creation may synchronously notify the mission.
    return h
end
for _, name in ipairs({"SetAIControl", "SetPilot", "SetAIP", "ClearObjectives",
    "AddObjective", "SetObjectiveOn", "SetObjectiveName", "SetIndependence",
    "Goto", "Follow", "Pickup", "Defend", "Attack", "AddHealth", "Stop", "RemoveObject",
    "SucceedMission", "FailMission", "StartEarthquake", "StopEarthquake"}) do
    local operation = name
    _G[operation] = function(...) record(operation, ...) end
end

local function noop() end
local ioSites = {mission = "misn10"}
local pda = {Initialize = 0, UpdateInputs = 0, UpdateHeadlights = 0, OnObjectCreated = 0}
local modules = {
    PersistentConfig = {
        Initialize = function() pda.Initialize = pda.Initialize + 1 end,
        UpdateInputs = function() pda.UpdateInputs = pda.UpdateInputs + 1 end,
        UpdateHeadlights = function() pda.UpdateHeadlights = pda.UpdateHeadlights + 1 end,
        OnObjectCreated = function() pda.OnObjectCreated = pda.OnObjectCreated + 1 end},
    RequireFix = {Initialize = noop}, exu = {},
    Environment = {Init = noop, BindWeatherSensors = noop, Update = noop, OnObjectCreated = noop},
    -- The real module plays through AudioMessage and returns its handle.
    ScriptSubtitles = {Play = function(file) return AudioMessage(file) end,
        Queue = function(file) return AudioMessage(file) end, Stop = noop, Update = noop, Initialize = noop},
    CRIoSites10 = ioSites,
    CRIoWeather = {Seed = 1,
        Init = function(config) record("IoInit", config) end,
        Update = function(dt) record("IoUpdate", dt) end,
        Shutdown = function() record("IoShutdown") end,
        OnObjectCreated = noop,
        Save = function() record("IoSave"); return wxState end,
        Load = function(state) record("IoLoad", state) end,
        AnnounceState = function() record("IoAnnounce") end,
        ApplyNetEvent = function(...) record("IoNetEvent", ...) end,
        SetTargetLevel = function(level) record("IoTarget", level) end,
        ForceLevel = function(level, seconds, transition) record("IoForce", level, seconds, transition) end,
        ReleaseForcedLevel = function() record("IoRelease") end,
        Quake = function(strength, duration) record("IoQuake", strength, duration) end},
}
function require(name) return assert(modules[name], name) end

local function reset(started)
    now, serial = 0, 0
    objects, labels, distances, calls, cargo, scrap = {}, {}, {}, {}, {}, {}
    wxState = {tag = "weather"}
    for _, label in ipairs({"player", "relic", "cam1", "cam2", "cam3", "svrecycler",
        "avrecycler", "post1_geyser", "post3_geyser", "geyser1", "geyser2",
        "geyser3", "geyser4", "geyser5", "geyser6", "geyser7", "svartil1",
        "svartil2", "svmuf"}) do
        local team = 0
        if label == "player" or label == "avrecycler" then team = 1
        elseif label == "svrecycler" or label == "svartil1" or label == "svartil2" or label == "svmuf" then team = 5 end
        labels[label] = object("label", team)
    end
    modules.CRCoopDiagnostics = assert(loadfile("Scripts/CRCoopDiagnostics.lua"))()
    modules.CRCoopComms = assert(loadfile("Scripts/CRCoopComms.lua"))()
    modules.CRWire = assert(loadfile("Scripts/CRWire.lua"))()
    modules.CRCoopRespawn = assert(loadfile("Scripts/CRCoopRespawn.lua"))()
    modules.CRCoop = assert(loadfile("Scripts/CRCoop.lua"))()
    for k in pairs(pda) do pda[k] = 0 end
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
local function step(time) now = time; Update(0.05) end
local function armies()
    spawn("svhaul")
    for _ = 1, 3 do spawn("svartl"); spawn("svturr") end
    for _ = 1, 2 do spawn("svfigh"); spawn("svltnk") end
end
local function route(m, index)
    for i = 1, 7 do near(m.sav, m["geys" .. i], i == index and 10 or 1000 + i) end
end

-- ---------------------------------------------------------------- startup / setup
local m = reset(false)
check(pda.Initialize == 1, "PersistentConfig.Initialize ran exactly once after Start")
check(count("SetAIControl", 5, true) == 1 and count("SetAIControl") == 1,
    "strategic AI enabled once, on the CCA team (team 5), at the chunk root")
check(m.sav_free and not m.start_done and m.quake_time == 4 and m.geys1check == 180, "native Setup defaults")
check(not called("IoInit") and Save().weatherState == nil, "no weather before the first update")
Update(0.05)
check(pda.UpdateInputs >= 1 and pda.UpdateHeadlights >= 1, "the first Update drives PersistentConfig inputs and headlights")
check(pda.Initialize == 1, "the first Update does not re-initialize PersistentConfig")
check(m.start_done and called("AudioMessage", "misn1000.wav"), "briefing")
check(called("AddObjective", "misn1000.otf", "white"), "original objective")
check(called("SetScrap", 1, 30) and called("SetScrap", 5, 40)
    and called("SetPilot", 1, 10) and called("SetPilot", 5, 40), "starting resources (CCA is team 5)")
check(not called("SetScrap", 2) and not called("SetPilot", 2), "nothing is configured on team 2")
check(called("SetAIP", "misn10.aip", 5), "starting CCA production")
check(called("SetObjectiveName", m.nav1, "Relic Site")
    and called("SetObjectiveName", m.nav2, "CCA Base")
    and called("SetObjectiveName", m.nav3, "Drop Zone"), "native beacon names")
check(m.turret1_check == 19 and m.turret2_check == 20
    and m.artil1_check == 21 and m.artil2_check == 22 and m.artil3_check == 23, "staggered defense timers")
check(not m.chase_tug and not called("Attack"), "nil carrier never chased")
-- Relic marker: strict 100 m through CRCoop (one offline player = labels.player).
check(m.user == labels.player, "offline player handle is the local player")
near(m.user, m.sav, 100); clear(); Update(0.05)
check(not m.objective_on, "objective distance is strict")
near(m.user, m.sav, 99); Update(0.05)
check(m.objective_on and called("SetObjectiveOn", m.sav)
    and called("SetObjectiveName", m.sav, "Alien Relic"), "nearby relic marker")
clear(); Update(0.05)
check(not called("AudioMessage") and not called("SetObjectiveOn"), "one-shot startup/marker")

-- ---------------------------------------------------------------- offline scaling
m = reset()
check(count("BuildObject") == 0 and not called("BuildObject", "svfigh") and scrap[5] == 40,
    "one player: no relic-carrier hunter and CCA scrap stays 40")
check(m.hunters ~= nil and #m.hunters == 0 and m.ccafighter1 == nil, "one player: no hunter tracked")

-- ---------------------------------------------------------------- AIP / defense placement
m = reset(); armies(); route(m, 1); m.plan_b = true; scrap[5] = 15
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
check(not m.plan_a and not m.turret3_underway, "AIP scrap (team 5, > 15) and base turret strict thresholds")
scrap[5] = 16; near(m.ccaturret3, m.ccarecycle, 31); Update(0.05)
check(m.plan_a and called("SetAIP", "misn10a.aip", 5), "AIP A activates after four defenders")
check(m.turret3_underway and called("Defend", m.ccaturret3), "third turret defends base")
now = 19; clear(); Update(0.05)
check(not m.turret1_stop, "timer exact boundary")
now = 19.1; Update(0.05)
check(m.turret1_stop and called("Defend", m.ccaturret1) and m.turret1_check == 22.1, "first turret three-second poll")
now = 24; Update(0.05)
check(m.turret2_stop and m.artil1_stop and m.artil2_stop and m.artil3_stop, "remaining defense placements")
check(not called("SetAIP", "misn10b.aip"), "plan B stays off while it is marked done")

-- ---------------------------------------------------------------- plan B
m = reset(); scrap[5] = 7; clear()
local planTug = spawn("svhaul"); local planTank1 = spawn("svltnk")
Update(0.05)
check(not m.plan_b and not called("SetAIP", "misn10b.aip"), "plan B waits for both tanks")
local planTank2 = spawn("svltnk")
kill(planTug); Update(0.05)
check(not m.plan_b and not called("SetAIP", "misn10b.aip"), "plan B needs the tug alive")
objects[planTug].alive = true; kill(planTank1); Update(0.05)
check(not m.plan_b and not called("SetAIP", "misn10b.aip"), "plan B needs tank 1 alive")
objects[planTank1].alive = true; kill(planTank2); Update(0.05)
check(not m.plan_b and not called("SetAIP", "misn10b.aip"), "plan B needs tank 2 alive")
objects[planTank2].alive = true; clear(); Update(0.05)
check(m.plan_b and scrap[5] == 40 and count("SetScrap", 5, 40) == 1
    and count("SetAIP", "misn10b.aip", 5) == 1, "plan B restocks the CCA and loads misn10b.aip once")
check(firstIndex("SetScrap", 5, 40) < firstIndex("SetAIP", "misn10b.aip", 5), "plan B restocks before the AIP swap")
scrap[5] = 3; clear(); Update(0.05); step(5)
check(count("SetAIP", "misn10b.aip") == 0 and scrap[5] == 3, "plan B is one-shot")

-- ---------------------------------------------------------------- routes 1-7
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

-- ---------------------------------------------------------------- human carrier and pursuit
m = reset(); armies(); route(m, 3); Update(0.05)
local playerTug = object("avhaul", 1); cargo[m.sav] = playerTug
near(m.ccatug, m.geys3, 49); clear(); Update(0.05)
check(m.sav_secure and not m.sav_free and m.tugger == playerTug, "player relic acquisition (tug team is not 5)")
check(m.tug_wait3 and not m.tug_underway3 and called("Goto", m.ccatug, m.geys3, 1), "CCA tug waits on player acquisition")
for _, field in ipairs({"ccafighter1", "ccafighter2", "ccatank1", "ccatank2",
    "svartil1", "svartil2", "ccaartil1", "ccaartil2", "ccaartil3"}) do
    check(called("Attack", m[field], playerTug, 1), "player tug pursuer " .. field)
end
clear(); Update(0.05)
check(not called("Attack") and m.chase_tug, "pursuit one-shot with all pursuers alive")
cargo[m.sav] = nil; kill(playerTug); clear(); Update(0.05)
check(m.sav_free and not m.sav_secure and not m.chase_tug and not called("Attack"), "dead player tug frees relic and stops invalid pursuit")

-- A carrier on a non-human team (support team 7) secures the relic but is not chased.
m = reset(); armies(); route(m, 3); Update(0.05)
cargo[m.sav] = object("avhaul", 7); clear(); Update(0.05)
check(m.sav_secure and not m.sav_seized and not m.chase_tug and not called("Attack"),
    "a non-human (team 7) carrier is not a pursuit target")

for index = 2, 7 do
    m = reset(); armies(); route(m, index); Update(0.05)
    near(m.ccatug, m.sav, 90); near(m.ccatug, m["geys" .. index], 120); Update(0.05)
    cargo[m.sav] = object("avhaul", 1); clear(); Update(0.05)
    check(m["tug_wait" .. index] and not m.tug_after_sav
        and called("Goto", m.ccatug, m["geys" .. index], 1), "pickup interruption wait route " .. index)
end

-- ---------------------------------------------------------------- tug death / replacement
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

-- ---------------------------------------------------------------- tug rebuild
m = reset(); local tug = spawn("svhaul")
step(1)
check(m.build_tug and count("BuildObject") == 0, "a living CCA tug arms the rebuild")
step(100); kill(tug)
step(101)
check(m.making_another_tug and m.build_another_tug_time == 131, "tug death schedules the rebuild 30 s out")
step(130)
check(count("BuildObject") == 0, "rebuild is strict at +30.0 s")
step(131.01)
check(count("BuildObject", "svhaul", 5, m.ccarecycle) == 1 and count("BuildObject") == 1, "rebuild fires just after +30 s")
local rebuilt = last("BuildObject")[5]
check(m.ccatug == rebuilt and IsAlive(rebuilt) and m.tug_rebuilds == 1, "the rebuilt tug is tracked in M.ccatug via AddObject")
clear(); Update(0.05)
check(called("Goto", rebuilt, "relic_path1", 1) and m.got_position, "the rebuilt tug is routed like any replacement")
-- Second death rebuilds once more; the third never does.
clear(); kill(rebuilt); step(200); step(230); check(count("BuildObject") == 0, "second rebuild also waits 30 s")
step(230.1)
check(count("BuildObject", "svhaul", 5) == 1 and m.tug_rebuilds == 2, "second rebuild")
local second = m.ccatug; step(231); kill(second); step(300); step(400); step(1000)
check(count("BuildObject") == 1 and m.tug_rebuilds == 2 and IsAlive(m.sav), "a third tug death never rebuilds")

-- An AIP-built tug inside the window replaces the dead one: no rebuild.
m = reset(); tug = spawn("svhaul"); step(1); step(100); kill(tug); step(101)
step(110); local aipTug = spawn("svhaul", 5)
step(131.5); step(140)
check(count("BuildObject") == 0 and m.ccatug == aipTug and not m.making_another_tug, "an AIP-built tug in the window cancels the rebuild")

-- A dead relic never rebuilds a tug (dead before the tug, and dying inside the window).
m = reset(); tug = spawn("svhaul"); step(1); kill(m.sav); kill(tug); step(100); step(200)
check(count("BuildObject") == 0 and not m.making_another_tug, "no rebuild scheduled when the relic is dead")
m = reset(); tug = spawn("svhaul"); step(1); kill(tug); step(100); kill(m.sav); step(100.1); step(131); step(140)
check(count("BuildObject") == 0, "no rebuild when the relic dies inside the window")

-- The factory is the recycler, else the muf; with neither there is no rebuild.
m = reset(); tug = spawn("svhaul"); step(1); kill(tug); kill(m.ccarecycle); step(100); step(131)
check(count("BuildObject", "svhaul", 5, m.ccamuf) == 1, "rebuild falls back to the CCA muf")
m = reset(); tug = spawn("svhaul"); step(1); kill(tug); kill(m.ccarecycle); kill(m.ccamuf); step(100); step(131)
check(count("BuildObject") == 0, "no rebuild without a CCA factory")

-- ---------------------------------------------------------------- slot replacement and team filter
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
local second2 = spawn("svfigh", 1)
check(m.ccafighter2 == nil, "a team-1 look-alike never takes the second fighter slot")
second2 = spawn("svfigh")
check(m.ccafighter2 == second2, "team 5 takes the next vacant slot")
local third = spawn("svfigh"); check(m.ccafighter2 ~= third, "living slots remain unchanged")
kill(first); local newFirst = spawn("svfigh")
check(m.ccafighter1 == newFirst, "dead handle replacement without DeleteObject callback")

local filterSlots = {svturr = "ccaturret1", svartl = "ccaartil1", svfigh = "ccafighter1",
    svltnk = "ccatank1", svhaul = "ccatug", svmuf = "ccamuf"}
for odf, slot in pairs(filterSlots) do
    m = reset(); kill(m.ccamuf)
    for _, team in ipairs({1, 2, 3, 4, 7}) do
        local h = spawn(odf, team)
        local taken = false
        for _, name in ipairs({"ccaturret1", "ccaturret2", "ccaturret3", "ccaartil1", "ccaartil2", "ccaartil3",
            "ccafighter1", "ccafighter2", "ccatank1", "ccatank2", "ccatug", "ccamuf"}) do
            if m[name] == h then taken = true end
        end
        check(not taken, odf .. " of team " .. team .. " never takes a tracked slot")
    end
    local h = spawn(odf, 5)
    check(m[slot] == h, odf .. " of team 5 takes " .. slot)
end

-- ---------------------------------------------------------------- bombardment and heal
m = reset(); now = 180; clear(); Update(0.05)
check(not called("Attack"), "bombardment strict initial timer")
now = 181; Update(0.05)
check(called("Attack", m.svartil1, m.geys1) and m.geys1check == 331, "periodic relic-site bombardment")
now = 332; near(m.user, m.geys1, 199); clear(); Update(0.05)
check(called("Attack", m.svartil1, m.user) and called("Attack", m.svartil2, m.user), "nearby player bombardment (nearest player handle)")
now = 483; near(m.user, m.geys1, 200); clear(); Update(0.05)
check(called("Attack", m.svartil1, m.geys1), "bombardment distance is strict")
m = reset(); now = 0; clear(); Update(0.05)
check(not called("AddHealth"), "heal strict zero boundary")
now = 0.1; Update(0.05)
check(called("AddHealth", m.sav, 100) and m.next_second == 1.1, "relic gains 100 raw health")
now = 1.1; clear(); Update(0.05); check(not called("AddHealth"), "heal strict next boundary")
now = 1.2; Update(0.05); check(count("AddHealth") == 1, "heal once per scheduled second")
now = 1000; Update(0.05)
check(not called("StartEarthquake") and not called("StopEarthquake") and count("IoQuake") == 0,
    "no quake without a relic pickup")

-- ---------------------------------------------------------------- pickup quake
m = reset(); clear()
playerTug = object("avhaul", 1); cargo[m.sav] = playerTug
step(10)
check(m.sav_secure and m.quake and count("IoQuake") == 1 and called("IoQuake", 0.85, 6), "first human pickup quakes once (0.85, 6)")
cargo[m.sav] = nil; kill(playerTug); step(11)
local ccaCarrier = spawn("svhaul"); cargo[m.sav] = ccaCarrier; step(12); step(13)
check(m.sav_seized and count("IoQuake") == 1 and m.quake, "later pickups never quake again")
check(not called("StartEarthquake") and not called("StopEarthquake"), "the mission never calls StartEarthquake/StopEarthquake itself")
m = reset(); clear(); ccaCarrier = spawn("svhaul"); cargo[m.sav] = ccaCarrier; step(10)
check(m.sav_seized and m.quake and count("IoQuake") == 1 and called("IoQuake", 0.85, 6), "a CCA seizure quakes once too")
step(11); step(12)
check(count("IoQuake") == 1 and not called("StartEarthquake") and not called("StopEarthquake"), "seizure quake is one-shot")

-- ---------------------------------------------------------------- Io weather
m = reset(); clear(); Update(0.05); Update(0.05); step(3)
check(count("IoUpdate") == 3 and last("IoUpdate")[2] == 0.05, "weather Update(dt) every frame")
m = reset()
check(count("IoInit") == 1, "weather initialised once")
local cfg = last("IoInit")[2]
check(cfg.startLevel == 1 and cfg.targetLevel == 1 and cfg.sites == ioSites and cfg.authority == true and cfg.seed == nil,
    "calm start, the CRIoSites10 sites, host authority")
check(m.ioSeed == 1, "the authority keeps the weather seed in the mission state")
check(count("IoTarget") == 0 and count("IoForce") == 0, "no weather beat before the race")

m = reset(); spawn("svhaul"); clear(); Update(0.05); Update(0.05)
check(count("IoTarget", 2) == 1 and count("IoTarget") == 1, "level 2 once when the CCA tug first exists")

m = reset(); spawn("svhaul"); near(m.ccatug, m.sav, 400); clear(); Update(0.05)
check(count("IoTarget", 3) == 0, "tug close beat is strict at 400 m")
near(m.ccatug, m.sav, 399); Update(0.05); Update(0.05)
check(count("IoTarget", 3) == 1, "level 3 once when the CCA tug closes within 399 m")
check(firstIndex("IoTarget", 2) < firstIndex("IoTarget", 3), "level 2 precedes level 3")
m = reset(); playerTug = object("avhaul", 1); cargo[m.sav] = playerTug; clear(); step(1); step(2)
check(count("IoTarget", 3) == 1, "level 3 on the first human secure")
m = reset(); ccaCarrier = spawn("svhaul"); cargo[m.sav] = ccaCarrier; clear(); step(1); step(2)
check(count("IoTarget", 3) == 1, "level 3 on the first CCA seizure")

-- Climax: secured carrier near Utah (avrecycler), seized carrier near the CCA recycler (svrecycler).
m = reset(); playerTug = object("avhaul", 1); cargo[m.sav] = playerTug
near(playerTug, m.nsdfrecycle, 500); clear(); step(1)
check(count("IoForce") == 0, "climax is strict at 500 m")
near(playerTug, m.ccarecycle, 100); step(2)
check(count("IoForce") == 0, "the secured carrier's destination is Utah, not the CCA base")
near(playerTug, m.nsdfrecycle, 499); step(3); step(4)
check(count("IoForce") == 1 and called("IoForce", 5, 60, 10), "ForceLevel(5, 60, 10) once near Utah")
m = reset(); ccaCarrier = spawn("svhaul"); cargo[m.sav] = ccaCarrier
near(ccaCarrier, m.ccarecycle, 500); clear(); step(1)
check(count("IoForce") == 0, "seized climax is strict at 500 m")
near(ccaCarrier, m.nsdfrecycle, 100); step(2)
check(count("IoForce") == 0, "the seized carrier's destination is the CCA recycler")
near(ccaCarrier, m.ccarecycle, 499); step(3); step(4)
check(count("IoForce") == 1 and called("IoForce", 5, 60, 10), "ForceLevel(5, 60, 10) once near the CCA recycler")

-- Victory eases the sky back to calm exactly once, release first.
m = reset(); cargo[m.sav] = object("avhaul", 1)
near(m.sav, m.nsdfrecycle, 100); clear(); Update(0.05)
check(not m.game_over and count("IoRelease") == 0, "delivery threshold is strict")
near(m.sav, m.nsdfrecycle, 99); kill(m.nsdfrecycle); now = 10; Update(0.05)
check(m.game_over and called("SucceedMission", 25, "misn10w1.des")
    and not called("FailMission"), "delivery retains precedence over simultaneous recycler death")
check(count("IoRelease") == 1 and count("IoTarget", 1) == 1
    and firstIndex("IoRelease") < firstIndex("IoTarget", 1), "victory releases the forced level, then calms the sky")
clear(); Update(0.05)
check(not called("SucceedMission") and not called("FailMission") and count("IoRelease") == 0
    and count("IoTarget", 1) == 0, "mission outcome once")
check(count("IoUpdate") == 1, "weather keeps updating after the outcome")
m = reset(); spawn("svhaul"); cargo[m.sav] = m.ccatug; near(m.sav, m.ccarecycle, 99)
clear(); Update(0.05)
check(called("FailMission", 15, "misn10f1.des") and called("AudioMessage", "misn1002.wav"), "CCA delivery failure")
check(count("IoRelease") == 0 and count("IoTarget", 1) == 0, "a defeat does not calm the sky")
m = reset(); kill(m.sav); kill(m.nsdfrecycle); clear(); Update(0.05)
check(called("FailMission", 15, "misn10f2.des") and not called("AudioMessage", "misn1004.wav"), "relic loss precedes Utah loss")
m = reset(); kill(m.nsdfrecycle); clear(); Update(0.05)
check(called("FailMission", 15, "misn10f3.des") and called("AudioMessage", "misn1004.wav"), "Utah loss failure")
m = reset(false); objects[m.sav] = nil; objects[m.nav1] = nil; clear(); Update(0.05)
check(called("FailMission", 15, "misn10f2.des") and not called("SetObjectiveOn"), "missing handles avoid false proximity victory/marker")

-- ---------------------------------------------------------------- Save / Load
m = reset(); armies(); route(m, 6); Update(0.05)
local copy = {}; for key, value in pairs(Save()) do copy[key] = value end
check(copy.weatherState == wxState and called("IoSave"), "Save returns M with the weather director's state")
local saved = {}; for key, value in pairs(copy) do saved[key] = value end
clear(); Load(copy)
check(Save() == copy and copy.tug_underway6 and copy.ccatug == m.ccatug, "Save/Load state and handles")
clear(); Update(0.05)
check(not called("SetAIControl") and not called("SetAIP") and not called("AudioMessage")
    and not called("Goto") and not called("BuildObject")
    and not called("IoQuake"), "load does not replay setup, briefing, production, routes or quakes")
check(count("IoInit")==1 and count("IoLoad",wxState)==1,
    "same-Lua load rebuilds weather from saved scalars exactly once")
-- A reloaded chunk restores the weather from the saved state on its first update.
local savedState = saved.weatherState
m = reset(false); Load(saved); clear(); Update(0.05)
check(count("IoInit") == 1 and count("IoLoad", saved.weatherState) == 1, "a fresh chunk restores the saved weather once")
check(not called("AudioMessage", "misn1000.wav") and not called("SetAIP"), "restored state keeps the briefing and AIP done")

print("misn10: " .. checks .. " checks passed (" .. _VERSION .. ")")
