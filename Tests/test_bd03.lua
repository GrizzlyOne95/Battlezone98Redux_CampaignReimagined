-- Run from the repository root with Lua 5.1: lua Tests/test_bd03.lua
-- Engine mocks exercise mission decisions; real map pathing/cameras/assets
-- still require Battlezone 98 Redux validation.
local script = "Scripts/bd03.lua"
local clock, calls, objects, messages, distances, deployed, pathCounts
local nextHandle, cancelled, nextRandom, lastPathPoint
local assertions = 0
local function check(condition, message)
    assertions = assertions + 1
    assert(condition, message)
end
local function log(name, ...)
    calls[#calls + 1] = {name, ...}
end
local function count(name, first, second)
    local n = 0
    for _, call in ipairs(calls) do
        if call[1] == name and (first == nil or call[2] == first)
            and (second == nil or call[3] == second) then n = n + 1 end
    end
    return n
end
local function reset()
    clock, calls, objects, messages, distances = 0, {}, {}, {}, {}
    deployed, pathCounts = {}, {path_recycler_travel = 4}
    nextHandle, cancelled, nextRandom, lastPathPoint = 0, false, 0, nil
    GetTime = function() return clock end
    GetHandle = function(label)
        if not objects[label] then objects[label] = {health = 1, valid = true} end
        return label
    end
    GetPlayerHandle = function() return GetHandle("player") end
    IsValid = function(h) return objects[h] ~= nil and objects[h].valid end
    GetHealth = function(h) assert(IsValid(h)); return objects[h].health end
    GetPathPointCount = function(path) return pathCounts[path] or 0 end
    GetDistance = function(h, to, point)
        assert(IsValid(h))
        if type(to) ~= "string" then assert(IsValid(to)) end
        if point ~= nil then lastPathPoint = point end
        return distances[h .. "|" .. tostring(to) .. "|" .. tostring(point)] or 10000
    end
    IsDeployed = function(h) assert(IsValid(h)); return deployed[h] or false end
    BuildObject = function(odf, team, where)
        nextHandle = nextHandle + 1
        local h = "unit" .. nextHandle
        objects[h] = {health = 1, valid = true}
        log("BuildObject", odf, team, where, h)
        return h
    end
    RemoveObject = function(h) log("RemoveObject", h); objects[h].valid = false end
    AudioMessage = function(file)
        local h = {file = file, done = false}
        messages[#messages + 1] = h
        log("AudioMessage", file)
        return h
    end
    IsAudioMessageDone = function(h) assert(h); return h.done end
    StopAudioMessage = function(h) h.done = true; log("StopAudioMessage", h.file) end
    CameraCancelled = function() return cancelled end
    local names = {"SetScrap", "SetPilot", "SetObjectiveName", "SetCloaked",
        "ClearObjectives", "AddObjective", "CameraReady", "CameraFinish",
        "CameraPath", "Goto", "Follow", "Defend2", "Attack", "Hunt",
        "SetObjectiveOn", "SucceedMission", "FailMission"}
    for _, name in ipairs(names) do
        local fn = name
        _G[fn] = function(...) log(fn, ...) end
    end
    math.random = function(lo, hi)
        local value = lo + (nextRandom % (hi - lo + 1))
        nextRandom = nextRandom + 1
        return value
    end
    dofile(script)
    Start()
end
local function step(t) clock = t; Update(0.1) end
local function distance(a, b, value, point)
    distances[a .. "|" .. tostring(b) .. "|" .. tostring(point)] = value
end
local function finish(slot)
    local h = Save().soundHandle[slot]
    assert(h, "missing sound slot " .. slot)
    h.done = true
end
local function apc()
    local m = Save()
    m.apc = BuildObject("bvapcb", 1, "spawn_apc")
    m.apcSpawned = true
    return m.apc
end

reset()
step(0)
check(count("SetScrap", 1, 8) == 1 and count("SetPilot", 1, 10) == 1, "initial resources")
check(count("SetCloaked") == 6, "all six initial enemies cloak")
check(count("AudioMessage", "bd03001.wav") == 1, "intro message")
step(1)
check(count("SetScrap") == 1 and count("AudioMessage", "bd03001.wav") == 1, "startup is one-shot")
finish(0); step(2)
check(count("Goto", "recycler", "path_recycler_travel") == 1, "recycler travels after intro")
check(count("Follow") == 2 and Save().recyclerOnPath, "cinematic escort")
finish(1); step(3)
check(count("RemoveObject") == 2 and Save().sound1Delay == 63, "escorts removed and briefing delay")
step(63)
check(count("AudioMessage", "bd03003.wav") == 0, "strict sound timer boundary")
step(63.1); finish(2); step(64)
check(Save().sound2Delay == 94, "second briefing delay")
step(94.1); finish(3); step(95)
check(Save().sound3Delay == 105 and count("AddObjective", "bd03002.otf", "white") == 1, "objective briefing")
step(105.1); finish(4); step(106)
check(Save().soundComplete[4], "final early briefing completes")
distance("player", "recycler", 75); step(107)
check(not Save().objective1Complete, "rendezvous strict radius")
distance("player", "recycler", 74.9); step(108); step(109)
check(count("AudioMessage", "bd03006.wav") == 1 and Save().objective2Complete, "rendezvous one-shot")

reset(); step(0); finish(0); step(1)
distance("recycler", "path_recycler_travel", 24.9, 3); step(2)
check(lastPathPoint == 3, "path endpoint uses count minus one")
check(count("BuildObject", "cvturr") == 2 and count("BuildObject", "cvfigh") == 4, "turrets and guards")
check(count("Defend2") == 4 and not Save().recyclerOnPath, "guards defend correct turret")
check(count("Goto", "recycler", "geyser1") == 1, "move to geyser")
step(3); check(count("BuildObject") == 6, "endpoint transition is one-shot")
deployed.recycler = true; step(10); step(40)
check(count("Attack") == 0, "deployment wave strict timer")
step(40.1); step(41)
check(count("Attack") == 2 and count("BuildObject", "cvfigh") == 6, "deployment wave is two fighters once")

reset(); step(0); finish(0); step(1)
pathCounts.path_recycler_travel = 0
step(2); check(Save().recyclerOnPath and count("BuildObject") == 0, "missing path cannot arrive")
pathCounts.path_recycler_travel = 4
distance("recycler", "path_recycler_travel", 25, 3)
step(3); check(Save().recyclerOnPath, "path tolerance strict boundary")

reset(); step(0); step(420)
check(count("BuildObject") == 0, "seven minute wave strict boundary")
step(420.1)
check(count("BuildObject", "cvfigh") == 3 and count("BuildObject", "cvtnk") == 2, "seven minute cloaked wave")
check(count("Goto") == 5 and count("SetCloaked") == 11, "wave follows path at priority zero")
check(count("AudioMessage", "bd03007.wav") == 1, "APC briefing at seven minutes")
finish(5); step(421)
check(count("BuildObject", "bvapcb") == 1 and count("BuildObject", "bvraz") == 2, "APC and two escorts")
check(count("SetObjectiveOn") == 1 and count("Defend2") == 2, "APC escort orders")
step(540); check(count("BuildObject", "cvfighf") == 0, "nine minute boundary")
step(540.1); check(count("BuildObject", "cvfighf") == 1, "dedicated APC attacker")
step(600); check(count("Hunt") == 0, "random attack strict boundary")
step(600.1)
check(count("Hunt") == 2 and Save().randomDelay == 690.1, "random wave every ninety seconds")
step(660.1)
check(count("BuildObject", "cvfigh") == 9, "eleven minute two fighter wave")
local before = count("BuildObject")
step(690.1); check(count("BuildObject") == before, "repeat wave strict boundary")
step(690.2); check(count("BuildObject") == before + 4, "repeat wave four units")
local h = Save().apc
objects[h].health = 0.97; step(691); step(692)
check(count("AudioMessage", "bd03008.wav") == 1, "APC damage message once")
distance(h, "trigger_ambush", 50); step(693)
check(not Save().triggerAmbush, "ambush strict radius")
distance(h, "trigger_ambush", 49.9); step(694); step(695)
check(Save().triggerAmbush and count("Follow") == 2, "two cloaked ambushers once")

reset(); step(0)
h = apc()
distance(h, "nav_delta", 75); step(1)
check(not Save().won, "victory strict radius")
distance(h, "nav_delta", 74.9); step(2)
check(Save().won and count("SucceedMission") == 0, "victory waits for audio")
finish(7); step(3); step(4)
check(count("SucceedMission", 5, "bd03win.des") == 1, "victory debrief and two-second delay")

reset(); step(0)
h = apc(); objects[h].health = 0
distance(h, "nav_delta", 1); step(1)
check(Save().lost and not Save().won and count("AudioMessage", "bd03009.wav") == 0, "wreck cannot win")
finish(8); step(2)
check(count("AudioMessage", "bd03011.wav") == 1 and count("FailMission") == 0, "APC loss second audio")
finish(9); step(3); step(4)
check(count("FailMission", 5, "bd03lseb.des") == 1, "APC loss debrief")

reset(); step(0); objects.recycler.valid = false; step(1)
check(Save().lost and count("AudioMessage", "bd03012.wav") == 1, "deleted recycler loss")
finish(6); step(2); step(3)
check(count("FailMission", 4, "bd03lsea.des") == 1, "recycler loss debrief")
reset(); step(0); h = apc()
objects.recycler.health = 0; objects[h].health = 0; step(1)
check(count("AudioMessage", "bd03012.wav") == 1 and count("AudioMessage", "bd03010.wav") == 0, "recycler loss retains precedence")

reset(); step(0); cancelled = true; step(1)
check(Save().soundComplete[0] and Save().soundComplete[1], "both intro shots cancel and finish")
check(count("CameraFinish") == 2 and count("RemoveObject") == 2, "cancel releases cameras and removes escort")

reset(); step(0); step(420.1); finish(5); step(421)
local saved = Save()
-- BZR serializes handles/audio userdata; deep-copy tables to simulate reload
-- while retaining the mocked audio handle identities.
local function copy(t)
    local out = {}
    for key, value in pairs(t) do
        if type(value) == "table" and not value.file then out[key] = copy(value)
        else out[key] = value end
    end
    return out
end
local restored = copy(saved)
dofile(script); Load(restored)
check(Save().apc == saved.apc and Save().soundHandle[0] == saved.soundHandle[0], "saved engine/audio handles retained")
check(Save().randomDelay == 600 and Save().apcAttackTime == 540, "saved timer deadlines retained")
before = count("BuildObject"); step(422)
check(count("BuildObject") == before and count("SetScrap") == 1, "load does not replay setup or spawns")

print("bd03: " .. assertions .. " assertions passed (Lua " .. _VERSION .. ")")
