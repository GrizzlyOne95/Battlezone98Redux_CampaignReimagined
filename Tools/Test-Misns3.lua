-- Run from the repository root with Lua 5.1: lua5.1 Tools/Test-Misns3.lua
-- Observable host behavior; does not substitute for BZR playtesting.
local now, objects, labels, calls, distances, enemies, done, options, serial, objectives
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local function record(name, ...) calls[#calls + 1] = {name, ...} end
local function count(name, arg)
    local n = 0
    for _, call in ipairs(calls) do
        if call[1] == name and (arg == nil or arg == call[2]) then n = n + 1 end
    end
    return n
end
local function last(name)
    for i = #calls, 1, -1 do if calls[i][1] == name then return calls[i] end end
end
local function object(odf)
    serial = serial + 1; objects[serial] = {odf = odf, alive = true}; return serial
end
function GetTime() return now end
function GetHandle(label)
    if options.missing and options.missing[label] then return nil end
    if not labels[label] then labels[label] = object("mapobject") end
    return labels[label]
end
function GetPlayerHandle() return GetHandle("player") end
function IsValid(h) return objects[h] ~= nil end
function IsAlive(h) return IsValid(h) and objects[h].alive end
function GetDistance(from, to)
    assert(IsValid(from) and (type(to) == "string" or IsValid(to)), "invalid distance operands")
    return distances[tostring(from) .. ":" .. tostring(to)] or 10000
end
function BuildObject(odf, team, where)
    assert(team == 2 and (type(where) == "string" or IsValid(where)), "bad spawn")
    record("BuildObject", odf, team, where)
    if options.failedSpawn == odf then return nil end
    local h = object(odf); AddObject(h); return h
end
function Attack(h, target)
    assert(IsValid(h) and IsValid(target), "invalid attack"); record("Attack", h, target)
end
function Follow(h, leader)
    assert(IsValid(h) and IsValid(leader), "invalid follow"); record("Follow", h, leader)
end
function Goto(h, path) assert(IsValid(h)); record("Goto", h, path) end
function SetIndependence(h, value) assert(IsValid(h)); record("SetIndependence", h, value) end
function GetNearestEnemy(h) assert(IsValid(h), "invalid nearest query"); return enemies[h] end
function SetObjectiveName(h, name) assert(IsValid(h)); record("SetObjectiveName", h, name) end
function ClearObjectives() objectives = {}; record("ClearObjectives") end
function AddObjective(name, color)
    objectives[#objectives + 1] = {name, color}; assert(#objectives <= 10); record("AddObjective", name, color)
end
function UpdateObjective(name, color)
    local found = false
    for _, entry in ipairs(objectives) do if entry[1] == name then entry[2] = color; found = true end end
    assert(found, "updating absent objective"); record("UpdateObjective", name, color)
end
function AudioMessage(name) record("AudioMessage", name); return "audio:" .. name end
function IsAudioMessageDone(msg) assert(type(msg) == "string", "invalid audio ID"); return done[msg] or false end
function SucceedMission(time, file) record("SucceedMission", time, file) end
function FailMission(time, file) record("FailMission", time, file) end
local function reset(config)
    options = config or {}; now = options.time or 0; serial = 0
    objects, labels, calls, distances, enemies, done, objectives = {}, {}, {}, {}, {}, {}, {}
    dofile("Scripts/misns3.lua"); Start(); Update(0.05); return Save()
end
local function near(from, to, distance) distances[tostring(from) .. ":" .. tostring(to)] = distance end
local function step(time) now = time; Update(0.05) end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = copy(item) end; return result
end
local function resume()
    local saved = copy(Save()); dofile("Scripts/misns3.lua"); Load(saved); return Save()
end

local m = reset({time = 0.75})
check(m.missionstart and count("AudioMessage", "misns301.wav") == 1, "briefing once")
check(m.withdraw == 600.75 and m.help1 == 120.75 and m.help2 == 280.75 and m.help3 == 380.75, "float deadlines")
check(m.Checkdist == 5 and m.Checkdist2 == 5 and m.Checkalive == 15, "C++ integer timer truncation")
check(count("SetObjectiveName") == 2 and last("SetObjectiveName")[3] == "Black Dog Outpost", "marker names")
check(#objectives == 1 and objectives[1][1] == "misns301.otf" and objectives[1][2] == "white", "initial objective")
m = resume(); step(120.75)
check(not m.plea1 and count("AudioMessage", "misns301.wav") == 1, "load preserves strict first plea deadline without replay")
step(120.76); step(281); step(381); step(382)
check(m.plea1 and m.plea2 and m.plea3, "all three help pleas")
for i = 7, 9 do check(count("AudioMessage", "misns30" .. i .. ".wav") == 1, "plea once") end

m = reset(); near(m.player, "bdspawntrig", 200); Update(0.05)
check(not m.bdspawned, "defender strict 200m boundary")
near(m.player, "bdspawntrig", 199); Update(0.05)
check(m.bdspawned and count("BuildObject", "avtank") == 3 and count("BuildObject", "avfigh") == 2, "initial wave composition")
check(count("Attack") == 5 and count("AudioMessage", "misns310.wav") == 1, "initial wave attacks and radio")
step(15); check(count("Attack") == 5, "retarget strict 15s boundary")
step(15.5); check(count("Attack") == 10 and m.Checkalive == 23, "retarget truncates next eight-second poll")
for i = 1, 5 do objects[m["bd" .. i]].alive = false end
step(23); check(count("BuildObject") == 5, "replacement strict poll boundary")
step(23.1); check(count("BuildObject") == 10 and count("Attack") == 10, "replacement waits to receive orders")
m = resume(); step(31.1)
check(count("Attack") == 15 and count("BuildObject") == 10, "replacement retarget resumes after load")
objects[m.avrec].alive = false; Update(0.05)
check(m.recyclerdestroyed and m.bdspawned2 and not m.bdspawned, "destruction switches phases")
check(count("Goto") == 4 and count("AudioMessage", "misns302.wav") == 1, "four retreat routes")
for i, key in ipairs({"bd50", "bd60", "bd70", "bd80"}) do
    check(calls[#calls - 4 + i][1] == "Goto" and calls[#calls - 4 + i][3] == "bdpath" .. i, "source route order")
    near(m.player, m[key], 410)
end
Update(0.05); check(count("Follow") == 0 and #objectives == 2, "410m boundary and delayed objective refresh")
check(objectives[1][2] == "white" and objectives[2][2] == "green", "recycler objective complete")
for _, key in ipairs({"bd50", "bd60", "bd70", "bd80"}) do near(m.player, m[key], 409) end
Update(0.05); Update(0.05)
check(count("Follow") == 8 and m.unit1spawned and m.unit2spawned and m.unit3spawned and m.unit4spawned, "eight escorts once")
for _, key in ipairs({"bd51", "bd52", "bd62", "bd61", "bd71", "bd72", "bd81", "bd82"}) do
    local expected = (key == "bd61" or key == "bd62" or key == "bd71") and "avfigh" or "avtank"
    check(objects[m[key]].odf == expected, "escort composition " .. key)
end
near(m.player, "homesweethome", 200); step(601)
check(not m.missionwon and not m.missionfail and not m.warn1, "return boundary; destroyed recycler suppresses timeout")
near(m.player, "homesweethome", 199); Update(0.05)
check(m.missionwon and count("SucceedMission") == 0, "return waits for victory audio")
m = resume(); Update(0.05)
check(#objectives == 2 and objectives[1][2] == "green" and objectives[2][2] == "green", "victory refresh has two green slots")
done[m.aud50] = true; Update(0.05)
check(last("SucceedMission")[2] == now and last("SucceedMission")[3] == "misns3w1.des", "audio-gated success")
step(602); check(count("BuildObject") == 22, "no replacement waves after destruction")

m = reset(); step(600); check(not m.missionfail, "withdraw strict 600s boundary")
step(600.1); check(m.missionfail and count("FailMission") == 0, "withdraw waits for radio")
m = resume(); done[m.aud2] = true; Update(0.05)
check(last("FailMission")[3] == "misns3l1.des", "withdrawal loss resumes after load")
m = reset(); near(m.player, "don'tgohere", 50); near(m.player, "iwarnedyou", 50); Update(0.05)
check(not m.warn1 and not m.warn2, "warning strict 50m boundary")
near(m.player, "don'tgohere", 49); near(m.player, "iwarnedyou", 49); Update(0.05); Update(0.05)
check(count("AudioMessage", "misns305.wav") == 1 and count("AudioMessage", "misns306.wav") == 1, "warnings once")
check(count("FailMission") == 0, "disobedience waits for audio")
m = resume(); objects[m.avrec].alive = false; done[m.aud1] = true; Update(0.05)
check(last("FailMission")[3] == "misns3l2.des", "source retains previously latched disobedience after destruction")

for trigger = 1, 2 do
    for _, bomber in ipairs({"bomb1", "bomb2", "bomb3", "bomb4", "player"}) do
        m = reset(); near(m[bomber], "patroltrig" .. trigger, 100); step(5.1)
        check(not m.patrolspawned, "patrol strict 100m boundary")
        near(m[bomber], "patroltrig" .. trigger, 99); step(8.1)
        check(m.patrolspawned and count("BuildObject", "bvraz") == 2, "each bomber/player triggers each patrol route")
        check(last("Goto")[3] == "patrolpath" .. trigger and count("SetIndependence") == 2, "patrol route and independence")
        step(12); check(count("BuildObject", "bvraz") == 2, "patrol one-shot")
    end
end
m = reset(); near(m.bomb1, "patroltrig1", 99); near(m.bomb2, "patroltrig2", 99); step(5)
check(not m.patrolspawned, "patrol strict five-second poll")
step(5.1); check(count("BuildObject", "bvraz") == 4 and count("AudioMessage", "misns219.wav") == 2, "simultaneous source patrols retained")
local e1, e2 = object("enemy1"), object("enemy2")
enemies[m.pat1], enemies[m.pat2] = e1, e2
near(m.pat1, e1, 180); near(m.pat2, e2, 180); step(8.1)
check(not m.mark1, "patrol strict 180m detection")
near(m.pat1, e1, 179); near(m.pat2, e2, 179); step(11.1)
check(m.mark1 and m.play and m.bdspawned and count("Attack") == 4, "both patrol targets checked independently")
check(last("Attack")[3] == e2 and count("AudioMessage", "misns220.wav") == 1, "second target overrides first and radio once")
step(15.1); check(count("BuildObject", "avtank") == 3 and count("BuildObject", "avfigh") == 2, "patrol detection activates source shared defender flag")

for field = 1, 3 do
    for _, suffix in ipairs({"", "b"}) do
        m = reset(); near(m.player, "minetrig" .. field .. suffix, 200); Update(0.05)
        check(not m["minefield" .. field], "mine trigger strict boundary")
        near(m.player, "minetrig" .. field .. suffix, 199); Update(0.05)
        local first = ({1, 12, 23})[field]; local finish = ({11, 22, 34})[field]
        check(count("BuildObject", "proxmine") == finish - first + 1, "minefield count for either trigger")
        local index = first
        for _, call in ipairs(calls) do
            if call[1] == "BuildObject" then check(call[4] == "path_" .. index, "mine placement order"); index = index + 1 end
        end
        m = resume(); Update(0.05)
        check(count("BuildObject", "proxmine") == finish - first + 1, "minefields do not duplicate after load")
    end
end
m = reset({missing = {basenav = true, avrecy = true, bomb1 = true, bomb2 = true, bomb3 = true, bomb4 = true}})
step(10); check(count("SetObjectiveName") == 0 and not m.patrolspawned, "missing markers/bombers safe")
near(m.player, "patroltrig1", 1); step(14); objects[m.pat1] = nil; objects[m.pat2] = nil; step(20)
check(not m.mark1, "deleted patrols and nil nearest enemies safe")
m = reset({failedSpawn = "avtank"}); near(m.player, "bdspawntrig", 1); Update(0.05)
check(count("Attack") == 2, "failed spawns skip invalid orders")
objects[m.avrec].alive = false; Update(0.05); step(20)
check(m.recyclerdestroyed and not m.unit1spawned and not m.unit4spawned, "missing retreat leaders never spawn escorts at an invalid handle")
print("misns3 host checks passed: " .. checks)
