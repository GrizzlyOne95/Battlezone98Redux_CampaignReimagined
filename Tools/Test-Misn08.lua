-- Run from the repository root with Lua 5.1.
-- Offline (single-player) behavior of the co-op-capable misn08: the real CRCoop
-- runs with single-player semantics, so every check below is the DLL's own flow
-- (plus the documented restored behavior). Multi-player behavior is covered by
-- Tools/Test-Misn08Coop.lua. Mock-engine checks only; no engine/asset validation.
local now, objects, labels, calls, distances, serial, deployed, counts, info
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function record(name, ...)
    calls[#calls + 1] = {name, ...}
end
local function called(name, first, second)
    for _, call in ipairs(calls) do
        if call[1] == name and (first == nil or call[2] == first) and (second == nil or call[3] == second) then
            return true
        end
    end
    return false
end
local function count(name, first)
    local n = 0
    for _, call in ipairs(calls) do
        if call[1] == name and (first == nil or call[2] == first) then n = n + 1 end
    end
    return n
end
function GetHandle(label)
    if not labels[label] then
        serial = serial + 1
        labels[label] = serial
        objects[serial] = {alive = true, health = 1, odf = "avtank", team = 1}
    end
    return labels[label]
end
function SetVector(x, y, z) return {x = x or 0, y = y or 0, z = z or 0} end
function GetLabel(h) return nil end
function DisplayMessage() end
function Ally() end
function UnAlly() end
function GetPilot() return 10 end
local function noop() end
local modules = {
    RequireFix = {Initialize = noop}, exu = {},
    ScriptSubtitles = {Play = function(file) record("Play", file); return 1 end,
        Queue = function(file) record("Queue", file) end, Stop = noop, Update = noop, Initialize = noop},
}
function require(name) return assert(modules[name], name) end
function GetPlayerHandle() return GetHandle("player") end
function GetTime() return now end
function IsValid(h) return objects[h] ~= nil end
function IsAlive(h) return objects[h] ~= nil and objects[h].alive end
function GetHealth(h) return objects[h].health end
function GetTeamNum(h) return objects[h] and objects[h].team or 0 end
function IsOdf(h, odf) return objects[h].odf == odf end
function IsInfo(prefix) return info[prefix] == true end
function GetDistance(h, target)
    assert(IsValid(h), "invalid distance origin")
    assert(type(target) == "string" or IsValid(target), "invalid distance target")
    return distances[tostring(h) .. ":" .. tostring(target)] or 10000
end
function CountUnitsNearObject(h, range, team, odf)
    record("CountUnitsNearObject", h, range, team, odf)
    return counts[odf] or 0
end
function IsDeployed() return deployed end
function AllObjects()
    local i = 0
    return function()
        while i < serial do
            i = i + 1
            if objects[i] then return i end
        end
    end
end
function BuildObject(odf, team, where)
    serial = serial + 1
    objects[serial] = {alive = true, health = 1, odf = odf, team = team}
    record("BuildObject", odf, team, where)
    AddObject(serial) -- the real BuildObject invokes AddObject synchronously
    return serial
end
function RemoveObject(h) objects[h] = nil; record("RemoveObject", h) end
function Damage(h, amount) record("Damage", h, amount); objects[h].alive = false end
for _, name in ipairs({"SetAIControl", "SetObjectiveOff", "SetObjectiveOn", "SetObjectiveName", "SetScrap",
    "SetPilot", "SetAIP", "ClearObjectives", "AddObjective", "Attack", "Goto", "Defend", "SetWeaponMask",
    "AddHealth", "FailMission", "SucceedMission"}) do
    local operation = name
    _G[operation] = function(...) record(operation, ...) end
end
local function step(t) now = t; Update(0.05) end
local function reset(specs)
    now, serial, deployed = 0, 0, false
    objects, labels, calls, distances, counts, info = {}, {}, {}, {}, {}, {}
    local handles = {}
    for i, spec in ipairs(specs or {}) do
        serial = serial + 1
        objects[serial] = {alive = true, health = 1, odf = spec[1], team = spec[2]}
        handles[i] = serial
    end
    modules.CRCoopComms = assert(loadfile("Scripts/CRCoopComms.lua"))()
    modules.CRCoopRespawn = assert(loadfile("Scripts/CRCoopRespawn.lua"))()
    modules.CRCoop = assert(loadfile("Scripts/CRCoop.lua"))()
    dofile("Scripts/misn08.lua")
    Start()
    return Save(), handles
end
local function near(h, target, distance)
    distances[tostring(h) .. ":" .. tostring(target)] = distance
end
local function kill(h) objects[h].alive = false end

-- ------------------------------------------------------------- full host flow
local m, h = reset({{"avmu8", 1}, {"abtowe", 1}, {"abtowe", 1}, {"svapc", 5}})
check(called("SetAIControl", 5, true), "native AI startup on the CCA team")
check(m.nsdfmuf == h[1] and m.guntower1 == h[2] and m.guntower2 == h[3] and m.ccaapc == h[4], "map object bootstrap")
step(0)
check(count("Play", "misn0800.wav") == 1, "opening radio")
check(count("AddObjective") == 2 and called("SetScrap", 1, 30), "opening objectives/resources")
check(called("SetWeaponMask", m.ccagech1, 1), "initial walker weapons")
step(20)
check(not m.first_wave, "strict timer boundary")
step(20.1)
check(called("Goto", m.svpatrol2_2, m.nsdfrecycle) and m.first_wave, "first fighters")
deployed = true
step(22.2)
check(m.base_set and called("AddObjective", "misn0800.otf", "green"), "factory deployment")
step(100.1)
check(count("BuildObject", "svfigh") == 3 and m.fresh_meat, "reinforcement trio")
for _, call in ipairs(calls) do
    if call[1] == "BuildObject" then check(call[3] == 5, "CCA spawns use the enemy team: " .. call[2]) end
end
step(200.1)
check(called("Play", "misn0817.wav"), "fighter radio")
near(m.user, m.nav5, 300)
step(280.1)
check(not m.colorado_under_attack, "Colorado attack deferred while a player is within 400 m")
check(m.colorado_warned and count("Play", "misn0824.wav") == 1, "0824 warns a player approaching the Colorado, once")
near(m.user, m.nav5, 10000)
step(290.2)
check(m.colorado_under_attack and count("BuildObject", "svwalk") == 1, "Colorado walker spawn")
check(count("BuildObject", "svfigh") == 4 and count("BuildObject", "svltnk") == 1, "source duplicate slot still spawns both units")
local walker3 = m.ccagech3
check(called("Attack", walker3, m.colorado), "Colorado targeted by walker 3")
check(m.strike and m.strike.figh and m.strike.ltnk and m.strike.figh ~= m.strike.ltnk, "strike fighter and light tank tracked")
check(called("Attack", m.strike.figh, m.colorado) and called("Attack", m.strike.ltnk, m.colorado), "CCA strike ordered onto the Colorado")
step(300.3)
check(called("Play", "misn0803.wav"), "Colorado second radio")
step(307.4)
check(called("Play", "misn0802.wav") and called("Queue", "misn0804.wav") and count("Play", "misn0804.wav") == 0,
    "back-to-back Colorado radios play then queue")
check(called("AddHealth", m.colorado, 500.0), "the Colorado is healed while it is protected")
check(not m.kill_colorado, "the heal is still running")
step(317.5)
check(m.kill_colorado and not called("Damage") and not m.colorado_message4, "heal stops; nothing is scripted dead")
local heals = count("AddHealth", m.colorado)
step(318.6)
check(count("AddHealth", m.colorado) == heals, "no further Colorado heal after the fall begins")
near(m.gech_trigger2, m.ccagech2, 50)
kill(m.colorado) -- destroyed by the walker and the strike
step(319)
check(not called("Damage") and m.colorado_message4, "a Colorado killed by the attackers needs no scripted damage")
check(called("Goto", m.strike.figh, m.nav1) and called("Goto", m.strike.ltnk, m.nav1), "strike units resume the DLL's Drop Zone order")
step(329.1)
check(called("Goto", m.ccagech1, "gech_path1") and called("Goto", m.ccagech2, "gech_path2"), "walker route start")
step(334.1)
check(called("RemoveObject", m.nav5) and m.colorado_destroyed, "Colorado nav removed")
near(walker3, m.stop_geyser2, 20)
step(339.2)
check(called("SetAIP", "misn08.aip", 5) and called("SetScrap", 5, 40) and called("SetPilot", 5, 40), "strategic AI on the CCA team")
check(called("Goto", walker3, "gech_path2") and m.gech3_move, "walker 3 continues toward the base (restored)")
check(m.gech3_there_time > 339.2 + 96 and m.gech3_there_time < 339.2 + 98, "walker 3 base arrival armed")
step(369.3)
check(called("Play", "misn0810.wav"), "general radio")
near(walker3, m.stop_geyser3, 50)
step(437)
check(m.gech3_at_base and called("Attack", walker3, m.nsdfrecycle), "walker 3 attacks the player base")
counts.avfigh, counts.avtank = 5, 2
step(760)
check(called("SetAIP", "misn08b.aip", 5) and called("CountUnitsNearObject", m.stop_geyser2, 5000.0, 1, "avfigh"), "fighter-heavy AIP")
counts.avfigh, counts.avtank = 1, 4
step(1181)
check(called("SetAIP", "misn08a.aip", 5), "tank-heavy AIP")

-- ----------------------------------------------- fallback when nothing kills it
m = reset()
step(0); step(290.2); step(300.3); step(307.4); step(317.5)
check(m.kill_colorado and IsAlive(m.colorado), "the Colorado survives the radio timeline")
step(437.4)
check(not called("Damage") and IsAlive(m.colorado), "no scripted damage before the generous timeout")
step(437.6)
check(called("Damage", m.colorado, 20000) and m.colorado_message4, "fallback damage after the timeout")
step(453)
check(called("RemoveObject", m.nav5), "the DLL timeline continues after the fallback")

-- ----------------------------------------------------- early walker discovery
for _, variant in ipairs({1, 2}) do
    m = reset(); step(0)
    local found, other = "ccagech" .. variant, "ccagech" .. (3 - variant)
    near(m.user, m[found], 300)
    step(61.1)
    check(m["gech_found" .. variant] and count("Play", "misn0806.wav") == 1, "early walker discovery " .. variant)
    step(variant == 1 and 81.2 or 66.2)
    check(called("Play", "misn0807.wav"), "asymmetric followup " .. variant)
    near(m.user, m[other], 80)
    step(variant == 1 and 103 or 122)
    check(m.run_into_other_gech and called("Play", "misn0813.wav"), "stumble into other walker " .. variant)
    check(not m.too_close_message, "80 m is outside the 75 m close-range warning")
    near(m.user, m[other], 70)
    step(variant == 1 and 104 or 123)
    check(m.too_close_message and count("Play", "misn0816.wav") == 1, "0816 close-range warning within 75 m (restored) " .. variant)
end

for _, variant in ipairs({1, 2}) do
    m = reset(); step(0)
    near(m.user, m["ccagech" .. variant], 300); step(61.1)
    near(variant == 1 and m.gech_trigger2 or m.gech_trigger3, m["ccagech" .. (3 - variant)], 50)
    step(74.2)
    check(m.second_gech_warning and called("BuildObject", "apcamr"), "second walker remote warning " .. variant)
end

for _, variant in ipairs({2, 3}) do
    m = reset(); step(0)
    near(m["gech_trigger" .. variant], m["ccagech" .. (variant == 2 and 2 or 1)], 50)
    step(280.1); step(285.1)
    check(m["gech_at_nav" .. variant], "undiscovered walker reaches trigger " .. variant)
    step(305.2)
    check(m.player_warned_ofgech and called("SetObjectiveName", m[variant == 2 and "nav2" or "nav3"],
        variant == 2 and "Nav Alpha 1" or "Nav Alpha 2"), "first nav warning " .. variant)
    near(variant == 2 and m.gech_trigger3 or m.gech_trigger2, m["ccagech" .. (variant == 2 and 1 or 2)], 50)
    step(319.3)
    check(m.second_gech_warning, "second nav warning " .. variant)
end

-- ------------------------------------------------------ nosey player, popper
m = reset(); step(0)
near(m.user, m.nav5, 600); step(45.1)
check(m.gech_spawn_time == 55.1 and called("Attack", m.svpatrol1_1, m.user), "nosey player acceleration")
check(count("Play", "misn0824.wav") == 1, "0824 on the nosey branch")
step(55.2)
check(m.colorado_under_attack, "accelerated Colorado attack")

m = reset(); step(0)
near(m.user, m.ccagech1, 300); step(61.1)
near(m.ccagech1, m.stop_geyser3, 50)
objects[m.ccagech1].health = 0.2
step(70)
check(m.gech1_blossom and called("SetWeaponMask", m.ccagech1, 4), "popper threshold")
step(76.1)
check(called("Play", "misn0816.wav"), "popper warning")
step(100.1)
check(m.gech1_at_base and called("Attack", m.ccagech1, m.nsdfrecycle) and called("SetWeaponMask", m.ccagech1, 5),
    "walker arrival weapons and target")
local apc = BuildObject("svapc", 5, "x")
local tower = BuildObject("abtowe", 1, "x")
step(101)
check(m.ccaapc == apc and called("Attack", apc, tower), "repaired APC tracking")
local enemyTower = BuildObject("abtowe", 5, "x")
local playerApc = BuildObject("svapc", 1, "x")
check(m.guntower2 ~= enemyTower and m.ccaapc ~= playerApc, "AddObject ignores wrong-team objects")

-- ----------------------------------------------------------- relic and results
m = reset(); step(0)
info.hbblde = true; step(1)
check(called("Play", "misn0822.wav") and m.relic_message, "relic reconnaissance")
check(called("AddHealth", m.main_relic, 500.0), "the relic heal runs (sentinel fixed)")
m = reset(); step(0)
kill(m.ccarecycle); kill(m.ccamuf); step(1)
info.hbbldf = true; step(2)
check(called("Play", "misn0821.wav"), "wrong ruins after the base fell")

for _, relicFirst in ipairs({true, false}) do
    m = reset(); step(0)
    if relicFirst then
        near(m.user, m.main_relic, 60); step(30.1)
        check(called("Play", "misn0819.wav") and count("SucceedMission") == 0, "relic-first waits for base")
    end
    kill(m.ccarecycle); kill(m.ccamuf)
    step(31)
    if not relicFirst then
        check(called("SetObjectiveOn", m.main_relic) and called("AddObjective", "misn0802.otf"), "base-first relic objective")
        near(m.user, m.main_relic, 60); step(34.2)
    end
    check(count("SucceedMission") == 1 and called("Play", "misn0818.wav") and called("Queue", "misn0826.wav")
        and count("Play", "misn0826.wav") == 0, "victory order " .. tostring(relicFirst))
end

m = reset(); step(0)
kill(m.nsdfrecycle); step(1); step(2)
check(count("FailMission") == 1 and called("FailMission", 16, "misn08f1.des"), "recycler loss scheduled once")
check(called("Play", "misn0823.wav") and count("Play", "misn0421.wav") == 0,
    "the Utah loss line is 0823 (the DLL's 0421 is substituted by the adapter)")

-- ----------------------------------------------------------------- save / load
m = reset(); step(0); step(280.1); step(290.2)
local snapshot = {}
for k, v in pairs(Save()) do snapshot[k] = v end
calls = {}
Load(snapshot)
step(297.3)
check(count("Play", "misn0800.wav") == 0 and count("BuildObject") == 0, "load does not replay initialization/spawn")
check(called("Play", "misn0802.wav") and Save().ccagech3 == snapshot.ccagech3, "load continues Colorado radio and walker handle")
check(Save().gech_spawn_time == snapshot.gech_spawn_time and Save().start_gech_time == snapshot.start_gech_time, "saved timers retained")

print("misn08: " .. checks .. " Lua 5.1 mock-engine checks passed")
