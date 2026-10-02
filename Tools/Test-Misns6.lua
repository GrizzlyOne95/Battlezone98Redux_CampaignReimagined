-- Run from repository root: lua5.1 Tools/Test-Misns6.lua
-- Mock host tests mission decisions, not engine AI or native save rebasing.
assert(_VERSION == "Lua 5.1", "run with Lua 5.1")
local now, objects, labels, calls, distances, serial, callback_mode, audio_done
local checks = 0
local function check(ok, msg) assert(ok, msg); checks = checks + 1 end
local function record(name, ...) calls[#calls + 1] = {name, ...} end
local function count(name, arg)
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == name and (arg == nil or c[2] == arg) then n = n + 1 end
    end
    return n
end
local function called(name, ...)
    local args = {...}
    for _, c in ipairs(calls) do
        if c[1] == name then
            local matches = true
            for i = 1, select("#", ...) do
                if c[i + 1] ~= args[i] then matches = false end
            end
            if matches then return true end
        end
    end
    return false
end
AiCommand = {NONE = 0, GO = 3, LAY_MINES = 29}
local function spawn(odf, team)
    serial = serial + 1
    objects[serial] = {odf = odf, team = team, alive = true,
        command = AiCommand.NONE, shot = -1e30}
    return serial
end
function GetHandle(label)
    if labels[label] == false then return nil end
    if not labels[label] then labels[label] = spawn("mapobject", 2) end
    return labels[label]
end
function GetPlayerHandle() return GetHandle("player") end
function GetTime() return now end
function IsValid(h) return h ~= nil and objects[h] ~= nil end
function IsAlive(h) return IsValid(h) and objects[h].alive end
function GetTeamNum(h) assert(IsValid(h)); return objects[h].team end
function IsOdf(h, odf) assert(IsValid(h)); return objects[h].odf == odf end
function GetLastEnemyShot(h) assert(IsAlive(h)); return objects[h].shot end
function GetCurrentCommand(h) assert(IsAlive(h)); return objects[h].command end
local function key(h, target, point)
    return tostring(h) .. ":" .. tostring(target) .. ":" .. tostring(point)
end
function GetDistance(h, target, point)
    assert(IsValid(h), "invalid distance origin")
    assert(type(target) == "string" or IsValid(target), "invalid distance target")
    record("GetDistance", h, target, point)
    return distances[key(h, target, point)] or 10000
end
local function near(h, target, d, point) distances[key(h, target, point)] = d end
function BuildObject(odf, team, where)
    local h = spawn(odf, team)
    if odf == "avmine" then
        local i = tonumber(where:match("^m([123])$"))
        if i then near(h, "m" .. i, 0, 1) end
    end
    record("BuildObject", odf, team, where, h)
    if callback_mode == "sync" then AddObject(h) end
    return h
end
function Goto(h, path, priority)
    assert(IsValid(h)); objects[h].command = AiCommand.GO
    record("Goto", h, path, priority)
end
function Mine(h, path, priority)
    assert(IsAlive(h)); objects[h].command = AiCommand.LAY_MINES
    record("Mine", h, path, priority)
end
function AudioMessage(name)
    record("AudioMessage", name)
    -- A nonnumeric token catches ports accidentally treating messages as ints.
    return "message:" .. name
end
function IsAudioMessageDone(message)
    assert(message == "message:misns609.wav"); return audio_done
end
function Defend(h, priority) assert(IsValid(h)); record("Defend", h, priority) end
function SetObjectiveOn(h) assert(IsValid(h)); record("SetObjectiveOn", h) end
for _, name in ipairs({"Attack", "SetScrap", "ClearObjectives", "AddObjective",
    "SetAIP", "FailMission", "SucceedMission"}) do
    local op = name
    _G[op] = function(...) record(op, ...) end
end
local function clear() calls = {} end
local function kill(h) objects[h].alive = false end
local function reset(mode, missing)
    now, serial, audio_done, callback_mode = 0, 0, false, mode or "sync"
    objects, labels, calls, distances = {}, {}, {}, {}
    for _, label in ipairs(missing or {}) do labels[label] = false end
    dofile("Scripts/misns6.lua"); Start()
    check(not Save().start_done and #calls == 0, "Start only resets state")
    Update(0.05)
    return Save()
end
local function copy(t)
    local result = {}
    for k, v in pairs(t) do result[k] = type(v) == "table" and copy(v) or v end
    return result
end

local m = reset()
check(count("BuildObject", "avmine") == 3 and count("BuildObject") == 3,
    "three miners only; cut recycler remains disabled")
check(m.next_target == 2 and m.miners[1] and m.miners[2] and m.miners[3],
    "three source-indexed slots and shared target initialized by callbacks")
check(called("Goto", m.miners[1], "s1", 1)
    and called("Goto", m.miners[2], "s2", 1)
    and called("Goto", m.miners[3], "s3", 1), "miners routed to nearest seed paths")
check(count("Defend") == 6 and called("Defend", m.art1, 1)
    and called("Defend", m.tur4, 1), "both artillery and four turrets defended")
check(called("SetScrap", 1, 20) and called("AudioMessage", "misns601.wav")
    and called("AddObjective", "misns601.otf", "white")
    and called("AddObjective", "misns602.otf", "white"), "briefing/resources/objectives")
check(m.check_time == 10 and m.aip_time == 120 and m.check1 == 99999
    and m.check2 == 99999 and m.check3 == 99999 and m.check4 == 99999,
    "all native timer defaults retained including dormant proximity waves")
clear(); Update(0.05)
check(count("BuildObject") == 0 and count("Defend") == 0, "startup happens once")
local player = GetPlayerHandle()
near(player, "m2", 250, 1); Update(0.05)
check(not m.warning, "warning strict distance boundary")
near(player, "m2", 249, 1); Update(0.05)
check(m.warning and called("AudioMessage", "misns602.wav"), "mine warning at explicit path point 1")
clear(); Update(0.05)
check(count("AudioMessage", "misns602.wav") == 0, "warning one-shot")
for i = 1, 3 do objects[m.miners[i]].command = AiCommand.NONE end
clear(); now = 10; Update(0.05)
check(count("Mine") == 0, "miner poll strict ten-second boundary")
now = 10.01; Update(0.05)
check(count("Mine") == 3 and called("Mine", m.miners[1], "s3", 1)
    and called("Mine", m.miners[2], "m1", 1)
    and called("Mine", m.miners[3], "m2", 1), "shared six-path rotation checks all three miners")
check(m.next_target == 5 and m.check_time == 13.01, "rotation and three-second poll cadence")
clear(); now = 13.01; Update(0.05)
check(count("Mine") == 0, "poll equality does not run")
now = 13.02; Update(0.05)
check(count("Mine") == 0, "active LAY_MINES commands are not restarted")
objects[m.miners[2]].command = AiCommand.NONE
clear(); now = 16.03; Update(0.05)
check(count("Mine") == 1 and called("Mine", m.miners[2], "m3", 1)
    and m.next_target == 0, "last path wraps; only idle miner receives command")
kill(m.miners[1]); objects[m.miners[3]].shot = 1
clear(); now = 19.04; Update(0.05)
check(m.counter1 and count("BuildObject", "bvraz") == 2 and count("Attack") == 2,
    "enemy-shot timestamp on surviving miner creates razors despite dead first miner")
check(called("BuildObject", "bvraz", 2, "counter1")
    and called("BuildObject", "bvraz", 2, "counter2"), "razor spawn sites unchanged")
for _, c in ipairs(calls) do
    if c[1] == "Attack" then check(c[3] == player and c[4] == nil,
        "razors attack current player with default priority") end
end
clear(); now = 23; Update(0.05)
check(count("BuildObject", "bvraz") == 0, "miner retaliation one-shot")
clear(); now = 120; Update(0.05)
check(count("SetAIP") == 0, "AIP strict 120-second boundary")
now = 120.01; Update(0.05)
check(called("SetAIP", "misns6.aip") and m.aip_time == 99999, "AIP switches and disarms")
clear(); Update(0.05)
check(count("SetAIP") == 0, "AIP one-shot during ordinary mission")
near(player, "counter2", 1); near(player, "counter3", 1)
near(player, "counter4", 1); near(player, "counter5", 1)
clear(); now = 300; Update(0.05)
check(count("BuildObject") == 0, "proximity waves remain dormant despite player proximity")
near(player, m.art1, 200); near(player, m.art2, 200); Update(0.05)
check(not m.art_found, "artillery strict boundary")
near(player, m.art2, 199); Update(0.05)
check(m.art_found and called("AudioMessage", "misns605.wav"), "either artillery triggers discovery")
near(m.far_silo, player, 400); Update(0.05)
check(not m.counter_attack, "silo strict boundary")
clear(); near(m.far_silo, player, 399); Update(0.05)
check(m.counter_attack and count("BuildObject", "bvltnk") == 2
    and count("BuildObject", "bvtank") == 2 and count("BuildObject", "bvrckt") == 1
    and count("Goto") == 5 and called("AudioMessage", "misns603.wav"), "five-unit silo wave")
for _, c in ipairs(calls) do
    if c[1] == "Goto" then check(c[3] == "counter_attack_path" and c[4] == 1,
        "silo-wave route and priority") end
end
clear(); Update(0.05)
check(count("BuildObject") == 0 and count("AudioMessage", "misns605.wav") == 0,
    "silo wave and artillery discovery one-shot")
near(player, m.goal, 300); Update(0.05)
check(not m.last_objective, "final objective strict boundary")
near(player, m.goal, 299); clear(); Update(0.05)
check(m.last_objective and called("AddObjective", "misns601.otf", "green")
    and called("AddObjective", "misns602.otf", "white")
    and called("SetObjectiveOn", m.goal), "goal approach objective progression")
clear(); kill(m.goal); now = 400; Update(0.05)
check(m.won and m.won_message and count("AudioMessage", "misns609.wav") == 1
    and count("SucceedMission") == 0, "goal destruction waits for victory audio")
kill(m.recy); clear(); Update(0.05)
check(count("FailMission") == 0 and count("AudioMessage", "misns609.wav") == 0,
    "victory precedence and no repeated audio while waiting")
audio_done = true; clear(); now = 405; Update(0.05)
check(m.won and m.success_scheduled and called("SucceedMission", 405, "misns6w1.des")
    and count("FailMission") == 0, "success latches without conflicting recycler failure")
clear(); Update(0.05)
check(count("SucceedMission") == 0 and count("AudioMessage") == 0 and count("FailMission") == 0,
    "terminal success does not retrigger")

m = reset("deferred")
check(m.miners[1] and m.miners[2] and m.miners[3], "explicit registration covers delayed callbacks")
local before = m.next_target; clear()
for i = 1, 3 do AddObject(m.miners[i]) end
check(m.next_target == before and count("Goto") == 0, "late callbacks are idempotent")
local friendly = spawn("avmine", 1); local other = spawn("bvtank", 2)
AddObject(friendly); AddObject(other); AddObject(nil)
check(count("Goto") == 0, "team/ODF/invalid filters")
local replacement = spawn("avmine.odf", 2)
near(replacement, "m2", 1, 1); AddObject(replacement)
check(m.miners[2] == replacement and m.next_target == 1
    and called("Goto", replacement, "s2", 1), "new enemy miner replaces nearest slot and resets shared target")
local far = spawn("avmine", 2)
for i = 1, 3 do near(far, "m" .. i, 100000, 1) end
clear(); AddObject(far)
check(m.miners[1] == far and m.next_target == 0 and count("Goto") == 0,
    "uninitialized closest fixed without inventing an out-of-range route")

m = reset(); clear(); objects[m.miners[1]].shot = 0; now = 11; Update(0.05)
check(not m.counter1, "zero enemy-shot timestamp remains false exactly as source")
-- Exercise dormant source branches by explicitly arming their preserved timers.
m.check1, m.check2, m.check3, m.check4 = 10, 9, 8, 7
local p = GetPlayerHandle()
near(p, "counter2", 399); near(p, "counter3", 399)
near(p, "counter4", 199); near(p, "counter5", 199)
clear(); now = 20; Update(0.05)
check(count("BuildObject", "bvtank") == 8 and count("BuildObject", "bvturr") == 4,
    "all four dormant wave bodies retained")
check(m.check1 == 310 and m.check2 == 309 and m.check3 == 320 and m.check4 == 320,
    "first two add 300 to old deadline; other two use current time")
check(not m.counter2 and not m.counter3 and not m.counter4 and not m.counter5,
    "source repeatable-wave flags not silently made one-shot")
for _, path in ipairs({"counter2", "counter3", "counter4", "counter5"}) do
    check(called("BuildObject", "bvtank", 2, path)
        and called("BuildObject", "bvturr", 2, path), "wave spawn path " .. path)
end
clear(); now = 321; Update(0.05)
check(count("BuildObject") == 12, "armed proximity waves repeat after cooldown")
near(p, "counter2", 400); near(p, "counter3", 400)
near(p, "counter4", 200); near(p, "counter5", 200)
clear(); now = 622; Update(0.05)
check(count("BuildObject") == 0 and m.check1 == 625 and m.check2 == 625
    and m.check3 == 625 and m.check4 == 625, "strict radii; failed checks retry in three seconds")

m = reset(); kill(m.recy); now = 2; clear(); Update(0.05)
check(m.lost and called("FailMission", 4, "misns6l1.des"), "recycler loss schedules two-second failure")
kill(m.goal); audio_done = true; clear(); Update(0.05)
check(count("FailMission") == 0 and count("SucceedMission") == 0
    and count("AudioMessage", "misns609.wav") == 0, "loss final; later goal death cannot overwrite it")
m = reset(); kill(m.goal); kill(m.recy); audio_done = true; clear(); Update(0.05)
check(m.won and count("SucceedMission") == 1 and count("FailMission") == 0,
    "simultaneous destruction retains source victory precedence")
m = reset("sync", {"avartl3_howitzer", "absilo0_scrapsilo"})
check(not m.art_found and not m.counter_attack and count("Defend") == 5,
    "missing optional objects do not create false proximity or invalid commands")
objects[m.art2] = nil; objects[GetPlayerHandle()] = nil; Update(0.05)
check(not m.art_found and not m.warning, "removed/player handles cannot satisfy proximity")

m = reset(); now = 11; objects[m.miners[2]].command = AiCommand.NONE; Update(0.05)
kill(m.goal); now = 12; Update(0.05)
local snapshot = copy(Save())
dofile("Scripts/misns6.lua"); clear(); Load(snapshot); now = 13; Update(0.05)
check(Save() == snapshot and snapshot.won and not snapshot.success_scheduled
    and snapshot.next_target == m.next_target and snapshot.aip_time == 120,
    "reload preserves rotation, delayed AIP and pending victory")
check(count("BuildObject") == 0 and count("SetScrap") == 0
    and count("AudioMessage") == 0, "reload does not replay startup or victory audio")
audio_done = true; now = 14; Update(0.05)
check(called("SucceedMission", 14, "misns6w1.des"), "restored audio message finishes victory once")
snapshot = copy(Save()); dofile("Scripts/misns6.lua"); Load(snapshot); clear(); Update(0.05)
check(count("SucceedMission") == 0, "success latch persists after reload")
print("misns6: " .. checks .. " checks passed (" .. _VERSION .. ")")
