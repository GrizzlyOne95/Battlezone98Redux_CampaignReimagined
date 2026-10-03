-- Run from the repository root: lua5.1 Tools/Test-Misn17.lua
-- Simulates BZR callbacks; verifies source-defined events and strict boundaries.
local now, objects, labels, calls, distances, nearest, audio, pathdone, cancelled
local serial, messages, checks = 0, 0, 0
AiCommand = {NONE = 0, ATTACK = 3, DEFEND = 16}
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function record(name, ...)
    calls[#calls + 1] = {name, ...}
end
local function count(name, first)
    local n = 0
    for _, call in ipairs(calls) do
        if call[1] == name and (first == nil or call[2] == first) then n = n + 1 end
    end
    return n
end
local function find(name, first)
    for _, call in ipairs(calls) do
        if call[1] == name and (first == nil or call[2] == first) then return call end
    end
end
local function valid(h)
    assert(IsValid(h), "invalid handle passed to host API: " .. tostring(h))
end
function IsValid(h) return h ~= nil and objects[h] ~= nil end
function IsAlive(h) return IsValid(h) and objects[h].alive end
function GetTime() return now end
function GetHandle(name) return labels[name] end
function IsOdf(h, odf) valid(h); return objects[h].odf == odf end
function GetNearestEnemy(h) valid(h); return nearest[h] end
local function distancekey(h, where, point)
    return tostring(h) .. ":" .. tostring(where) .. ":" .. tostring(point)
end
function GetDistance(h, where, point)
    valid(h)
    assert(type(where) == "string" or IsValid(where), "invalid distance target")
    return distances[distancekey(h, where, point)] or 10000
end
local function near(h, where, distance, point)
    distances[distancekey(h, where, point)] = distance
end
function BuildObject(odf, team, where)
    assert(type(where) == "string" or IsValid(where), "invalid spawn location")
    assert(type(where) ~= "string" or not where:match("^%s"), "bad path whitespace")
    assert(odf ~= "eggiezr1", "misspelled geyser ODF")
    serial = serial + 1
    local h = serial
    objects[h] = {alive = true, odf = odf, team = team, command = AiCommand.NONE}
    record("BuildObject", odf, team, where, h)
    if AddObject then AddObject(h) end
    return h
end
function Attack(h, who, priority)
    valid(h); valid(who)
    objects[h].command = AiCommand.ATTACK
    record("Attack", h, who, priority)
end
function Defend2(h, who, priority)
    valid(h); valid(who)
    assert(priority == nil or priority == 1, "invalid BZR command priority")
    objects[h].command = AiCommand.DEFEND
    record("Defend2", h, who, priority)
end
function GetCurrentCommand(h) valid(h); return objects[h].command end
function GetLastEnemyShot(h) valid(h); return objects[h].lastshot or 0 end
function GetWhoShotMe(h) valid(h); return objects[h].shooter end
function Damage(h, amount)
    valid(h)
    objects[h].alive = false
    record("Damage", h, amount)
end
function SetObjectiveOn(h) valid(h); record("SetObjectiveOn", h) end
function SetObjectiveName(h, name) valid(h); record("SetObjectiveName", h, name) end
function AudioMessage(name)
    messages = messages + 1
    audio[messages] = {name = name, done = false}
    record("AudioMessage", name)
    return messages
end
function IsAudioMessageDone(msg)
    assert(audio[msg], "invalid audio message")
    return audio[msg].done
end
function StopAudioMessage(msg)
    assert(audio[msg], "invalid audio message")
    record("StopAudioMessage", msg)
end
function CameraPath(path, height, speed, target)
    valid(target); record("CameraPath", path, height, speed, target)
    return pathdone[path] or false
end
function CameraObject(base, right, up, forward, target)
    valid(base); valid(target); record("CameraObject", base, right, up, forward, target)
    return false
end
function CameraCancelled() return cancelled end
for _, name in ipairs({"SetScrap", "SetAIP", "ClearObjectives", "AddObjective",
    "FailMission", "SucceedMission", "CameraReady", "CameraFinish", "GetRidOfSomeScrap"}) do
    local operation = name
    _G[operation] = function(...) record(operation, ...) end
end
local function reset(beforestart)
    now, serial, messages, cancelled = 0, 0, 0, false
    objects, labels, calls, distances, nearest, audio, pathdone = {}, {}, {}, {}, {}, {}, {}
    AddObject = nil
    for _, label in ipairs({"avrecy18_recycler", "savfactory1", "savfactory2", "savfactory3",
        "savfactory4", "factorypart1", "factorypart2", "factorypart3", "factorynav", "basenav"}) do
        labels[label] = BuildObject("map_object", 2, label)
    end
    dofile("Scripts/misn17.lua")
    if beforestart then beforestart() end
    Start()
    calls = {}
    Update(0.05)
    return Save()
end
local function tick(time)
    now = time
    Update(0.05)
end
local function kill(h) objects[h].alive = false end
local function erase(h) objects[h] = nil end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
local function towersdown(m)
    for i = 1, 7 do kill(m["tower" .. i]) end
end
local function partdown(m)
    for i = 1, 3 do kill(m["factorypart" .. i]) end
end

local m = reset()
check(m.missionstart and m.openingcin and not m.openingcindone, "mission startup")
check(count("BuildObject", "hbptow") == 7 and count("SetObjectiveOn") == 7, "seven towers marked")
check(find("SetObjectiveName", m.factorynav)[3] == "Furies Factory", "factory nav name")
check(find("SetObjectiveName", m.basenav)[3] == "Home Base", "base nav name")
check(find("SetScrap", 1)[3] == 40 and count("SetAIP", "misn17.aip") == 1, "scrap and strategic AI")
check(count("AudioMessage", "misn1701.wav") == 1 and count("AddObjective", "misn1701.otf") == 1, "briefing and first objective")
check(m.waveattacks == 1800 and m.camdone == 35, "unused source timers retained")
check(m.raw1there == false and m.procrysreplace == 99999 and m.crit == 0, "unused crystal state retained")
check(find("CameraPath", "cineractive1")[3] == 1000 and m.camera1, "opening shot retains source height")
pathdone.cineractive1 = true
Update(0.05)
check(not m.camera1 and m.camera2 and count("CameraPath", "cineractive2") == 0, "camera2 starts next update")
Update(0.05)
check(m.camera2 and not m.camera3, "camera waits for path completion")
local sequence = {"cineractive2", "cineractive3", "cineractive5", "cineractive6", "cineractive4", "cineractive7"}
calls = {}
for _, path in ipairs(sequence) do pathdone[path] = true end
Update(0.05)
local seen = {}
for _, call in ipairs(calls) do if call[1] == "CameraPath" then seen[#seen + 1] = call[2] end end
check(table.concat(seen, ",") == table.concat(sequence, ","), "native camera order and same-frame progression")
check(not m.camera7 and not m.openingcindone, "path end remains separate from audio completion")
audio[m.aud1].done = true
Update(0.05)
check(m.openingcindone and count("StopAudioMessage", m.aud1) == 1, "audio ends opening cinematic")
m = reset(); cancelled = true; Update(0.05)
check(m.openingcindone and not m.camera1, "opening skip")
m = reset(); erase(m.savfactory1); Update(0.05)
check(not m.camera1 and m.camera2, "missing camera target safely advances shot")

-- Tower proximity, single spawn and every escort's own retaliation target.
m = reset()
local intruder = BuildObject("avtank", 1, "intruder")
for i = 1, 7 do nearest[m["tower" .. i]] = intruder; near(m["tower" .. i], intruder, 400) end
tick(3)
check(count("BuildObject", "hvsat") == 0, "tower check uses strict timer boundary")
tick(3.1)
check(count("BuildObject", "hvsat") == 0 and m.tower1check == 5.1, "tower 400m excluded and check rescheduled")
for i = 1, 7 do near(m["tower" .. i], intruder, 399) end
tick(5.2)
check(count("BuildObject", "hvsat") == 14 and count("Defend2") == 14, "all fourteen tower defenders")
for i = 1, 7 do
    check(m["tower" .. i .. "spawn"] and m["trig" .. i] == nil, "tower " .. i .. " one-shot state")
    for _, suffix in ipairs({"a", "b"}) do
        local escort = m["deftow" .. i .. suffix]
        check(find("Defend2", escort)[3] == m["tower" .. i], "escort follows its tower")
        local shooter = BuildObject("avtank", 1, "shooter")
        objects[escort].lastshot, objects[escort].shooter = 1, shooter
    end
end
Update(0.05)
for i = 1, 7 do
    for _, suffix in ipairs({"a", "b"}) do
        local escort = m["deftow" .. i .. suffix]
        check(find("Attack", escort)[3] == objects[escort].shooter, "escort retaliates against its own attacker")
    end
end
tick(8)
check(count("BuildObject", "hvsat") == 14, "tower defenders never respawn")
m = reset(); tick(4)
check(not m.tower1spawn and m.tower7check == 6, "no nearest enemy safely retries")

-- Each of the five historical artillery slots gets its own replacing counter.
local artillery = {}
m = reset(function()
    for i = 1, 6 do artillery[i] = BuildObject("avartl", 1, "artillery") end
end)
check(m.art1 == artillery[1] and m.art5 == artillery[5], "pre-Start artillery callbacks survive")
check(count("BuildObject", "hvsav") == 5, "five artillery counters, sixth artillery ignored")
for i = 1, 5 do check(find("Attack", m["desart" .. i])[3] == artillery[i], "counter targets registered artillery") end
kill(m.desart3); Update(0.05)
check(count("BuildObject", "hvsav") == 6, "dead artillery counter replaced")
kill(artillery[1]); kill(m.desart1); Update(0.05)
check(count("BuildObject", "hvsav") == 6, "dead artillery no longer gets counter")
local sixth = BuildObject("avartl", 1, "artillery")
check(m.art1 == artillery[1] and m.art5 == artillery[5], "source artillery slots are never reclaimed")

-- Periodic factory waves: original offsets, ODFs and 400-second intervals.
m = reset()
for i, initial in ipairs({10, 100, 220, 340}) do
    tick(initial)
    check(m["spawntime" .. i] == initial, "factory " .. i .. " strict initial boundary")
    tick(initial + 0.1)
    check(m["spawntime" .. i] == initial + 400.1, "factory " .. i .. " recurring interval")
    local found
    for _, call in ipairs(calls) do
        if call[1] == "BuildObject" and call[4] == m["savfactory" .. i] then found = call end
    end
    check(found and found[2] == (i == 2 and "hvsav" or "hvsat"), "factory " .. i .. " wave ODF")
end
tick(410.1); check(m.spawntime1 == 410.1, "periodic wave strict boundary")
tick(410.2); check(m.spawntime1 == 810.2, "periodic wave advances from current time")
erase(m.savfactory2); tick(500.2)
check(m.spawntime2 == 900.2, "removed factory safely keeps original timer cadence")

-- Factory approach uses savspawn point 1; its four defenders are one-shot.
m = reset(); intruder = BuildObject("avtank", 1, "intruder")
nearest[m.savfactory1] = intruder; near(intruder, "savspawn", 450, 1)
tick(30); check(m.discheck == 30 and not m.defenders, "factory approach timer boundary")
tick(30.1); check(not m.defenders and m.discheck == 35.1, "factory 450m excluded")
near(intruder, "savspawn", 449, 1); tick(35.2)
check(m.defenders and count("Defend2") == 4, "factory four defenders")
for i, factory in ipairs({2, 3, 4, 1}) do check(find("Defend2", m["ip" .. i])[3] == m["savfactory" .. factory], "factory defender target") end
tick(41); check(count("Defend2") == 4, "factory defenders do not repeat")
m = reset(); intruder = BuildObject("avtank", 1, "intruder")
nearest[m.savfactory1] = intruder; near(intruder, "savspawn", 1, 1)
erase(m.savfactory2); tick(31)
check(m.defenders and count("Defend2") == 3 and m.ip1 == nil, "removed factory omits only invalid defender command")
m = reset(); intruder = BuildObject("avtank", 1, "intruder")
nearest[m.tower7] = intruder; near(m.tower7, intruder, 1); tick(4)
local escort = m.deftow7a
objects[escort].lastshot = 1
objects[escort].shooter = nil
Update(0.05)
check(count("Attack", escort) == 0, "missing shooter never becomes an invalid command target")

-- Proximity minefield checks all three paths and builds exactly 53 mines once.
for _, path in ipairs({"pt1", "pt2", "pt3"}) do
    m = reset(); intruder = BuildObject("avtank", 1, "intruder")
    nearest[m.savfactory2] = intruder; near(intruder, path, 610)
    tick(10); check(not m.minesmade and m.minedistancecheck == 10, "mine timer strict boundary")
    tick(10.1); check(not m.minesmade and m.minedistancecheck == 13.1, "mine 610m excluded")
    near(intruder, path, 609); tick(13.2)
    check(m.minesmade and count("BuildObject", "boltmine2") == 53, path .. " builds minefield")
    check(objects[m.MINE[53]].odf == "boltmine2" and m.MINE[0] == nil, "mine table exact endpoints")
    local tenth
    for _, call in ipairs(calls) do if call[1] == "BuildObject" and call[5] == m.MINE[10] then tenth = call end end
    check(tenth[4] == "mine10", "tenth mine corrected path")
    tick(17); check(count("BuildObject", "boltmine2") == 53, "proximity minefield one-shot")
end
m = reset(); tick(11)
check(not m.minesmade and m.minedistancecheck == 14, "absent mining target safely retries")

-- Last tower triggers fallback field, destruction cadence and deferred objectives.
m = reset(); towersdown(m); calls = {}; tick(5)
check(m.towersdestroyed and m.minesmade and m.minecinstart, "all towers trigger mine cinematic")
check(count("BuildObject", "eggeizr1") == 7 and count("BuildObject", "boltmine2") == 53, "tower debris and fallback minefield")
check(count("GetRidOfSomeScrap") == 1, "source scrap cleanup before fallback mine burst")
check(m.minecount == 1 and count("Damage") == 0, "original mine index-zero no-op frame preserved")
check(m.newobjective and count("AddObjective", "misn1702.otf") == 0, "source defers factory objective one update")
Update(0.05)
check(find("AddObjective", "misn1701.otf")[3] == "green" and find("AddObjective", "misn1702.otf")[3] == "white", "factory objective activated")
for i = 1, 8 do Update(0.05) end
local saved = copy(Save())
local previouscalls = #calls
Load(saved); m = Save()
check(m == saved and m.minecount == 10 and m.MINE[53] ~= nil, "save/load restores mine table and counter")
check(#calls == previouscalls and m.mineaudio == saved.mineaudio and m.spawntime2 == 100, "load has no startup effects")
erase(m.MINE[32]) -- This mine already detonated in the simulated world.
cancelled = true; Update(0.05); cancelled = false
check(m.minecin and not m.minecinstart and m.minesdestroyed, "camera skip leaves mine destruction running")
for i = 1, 43 do Update(0.05) end
check(m.minecount == 54 and not m.minesdestroyed, "54 source updates including index-zero frame")
check(count("Damage") == 52 and find("Damage", m.MINE[53]), "all remaining mines including 53 destroyed")
local damaged = count("Damage"); Update(0.05)
check(count("Damage") == damaged and count("GetRidOfSomeScrap") == 1, "mine cleanup and destruction never repeat")
m = reset(); intruder = BuildObject("avtank", 1, "intruder")
nearest[m.savfactory2] = intruder; near(intruder, "pt1", 1); tick(11)
towersdown(m); Update(0.05)
check(count("BuildObject", "boltmine2") == 53 and count("GetRidOfSomeScrap") == 0, "existing proximity field reused")
audio[m.mineaudio].done = true; Update(0.05)
check(m.minecin and not m.minecinstart, "mine audio completion ends cinematic")

-- Factory parts, victory camera, timed root explosions and one-shot failure.
m = reset(); kill(m.factorypart1); tick(50)
check(m.factorypart1dead and not m.missionwon, "one dead factory part does not win")
local debris = find("BuildObject", "eggeizr1")
check(debris and debris[3] == 3 and debris[4] == "part1geizer", "factory part geyser corrected")
kill(m.factorypart2); Update(0.05)
check(m.factorypart2dead and not m.missionwon, "two dead factory parts do not win")
kill(m.factorypart3); tick(100)
check(m.missionwon and not m.towersdestroyed, "source victory depends on parts, without added tower gate")
check(find("SucceedMission", 104)[3] == "misn17w1.des" and count("AudioMessage", "misn1703.wav") == 1, "four-second victory handoff")
local shot = find("CameraObject", m.cinscrap)
check(shot and shot[3] == 1000 and shot[4] == 8000 and shot[5] == 1000 and shot[6] == m.savfactory1, "finale camera coordinates")
tick(101); check(not m.sf2gone, "first explosion strict boundary")
tick(101.1); check(m.sf2gone and not m.sf4gone and not m.sf3gone, "first factory explosion")
local finale = copy(Save()); Load(finale); m = Save()
check(m.sf2gone and m.sf4blow == 102.5 and m.sf3blow == 103.2, "save/load between finale explosions")
tick(102.5); check(not m.sf4gone, "second explosion strict boundary")
tick(102.6); check(m.sf4gone and not m.sf3gone, "factory4 explodes second")
tick(103.2); check(not m.sf3gone, "third explosion strict boundary")
tick(103.3); check(m.sf3gone and IsAlive(m.savfactory1), "factory3 explodes last, root1 unchanged")
check(count("Damage") == 3 and count("SucceedMission") == 1, "finale events emitted once")
m = reset(); kill(m.avrec); tick(12)
check(m.missionfail and find("FailMission", 32)[3] == "misn17l1.des", "recycler loss failure delay")
Update(0.05); check(count("FailMission") == 1 and count("AudioMessage", "misn1704.wav") == 1, "failure one-shot")
m = reset(); kill(m.avrec); partdown(m); tick(12)
check(m.missionfail and m.missionwon and count("FailMission") == 1 and count("SucceedMission") == 1, "source independent simultaneous outcome requests preserved")

print("misn17: " .. checks .. " checks passed (" .. _VERSION .. ")")
