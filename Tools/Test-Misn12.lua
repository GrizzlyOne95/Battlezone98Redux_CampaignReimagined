-- Run from the repository root with Lua 5.1: lua5.1 Tools/Test-Misn12.lua
-- Engine-facing scenario tests; the stock game/map still need an in-game run.
local now, objects, labels, calls, distances, serial, player, timer, timerRunning
local cancelled, infos, objectives
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function record(name, ...)
    calls[#calls + 1] = {name, ...}
end
local function count(name, arg, arg2)
    local n = 0
    for _, call in ipairs(calls) do
        if call[1] == name and (arg == nil or call[2] == arg)
            and (arg2 == nil or call[3] == arg2) then n = n + 1 end
    end
    return n
end
local function called(name, arg, arg2) return count(name, arg, arg2) > 0 end
local function object(odf, team)
    serial = serial + 1
    objects[serial] = {alive = true, health = 1, odf = odf, team = team}
    return serial
end
function GetHandle(label)
    if not labels[label] then labels[label] = object("svtank", 5) end
    return labels[label]
end
function GetTeamNum(h) assert(IsValid(h)); return objects[h].team end
function AllObjects()
    local list = {}
    for h in pairs(objects) do list[#list + 1] = h end
    table.sort(list)
    local i = 0
    return function() i = i + 1; return list[i] end
end
function DisplayMessage() end
function Ally() end
function UnAlly() end
function GetPlayerHandle() return player end
function GetTime() return now end
function IsValid(h) return h ~= nil and objects[h] ~= nil end
function IsAlive(h) return IsValid(h) and objects[h].alive end
function GetHealth(h) assert(IsValid(h)); return objects[h].health end
function IsOdf(h, odf) return IsValid(h) and objects[h].odf == odf end
function GetDistance(h, target)
    assert(IsValid(h), "invalid distance origin")
    assert(type(target) == "string" or IsValid(target), "invalid distance target")
    return distances[tostring(h) .. ":" .. tostring(target)] or 10000
end
function BuildObject(odf, team, where)
    assert(type(where) == "string" or IsValid(where), "invalid build location")
    local h = object(odf, team)
    record("BuildObject", odf, team, where, h)
    return h
end
function RemoveObject(h) objects[h] = nil; record("RemoveObject", h) end
function AudioMessage(name) record("AudioMessage", name); return #calls end
function CameraReady() record("CameraReady"); return true end
function CameraFinish() record("CameraFinish"); return true end
function CameraCancelled() return cancelled end
function CameraPath(...) record("CameraPath", ...); return false end
function CameraObject(...) record("CameraObject", ...); return false end
function IsInfo(odf) return infos[odf] or false end
function SetTeamNum(h, team)
    assert(IsValid(h), "invalid team handle")
    objects[h].team = team; record("SetTeamNum", h, team)
end
function SetObjectiveName(h, name)
    assert(IsValid(h), "invalid name handle")
    objects[h].name = name; record("SetObjectiveName", h, name)
end
function ClearObjectives() objectives = {}; record("ClearObjectives") end
function AddObjective(name, color)
    objectives[#objectives + 1] = {name, color}
    assert(#objectives <= 10, "objective panel overflow")
    assert(color == "white" or color == "green" or color == "red" or color == "yellow")
    record("AddObjective", name, color)
end
function StartCockpitTimer(seconds, warn, alert)
    timer, timerRunning = seconds, true
    record("StartCockpitTimer", seconds, warn, alert)
end
function GetCockpitTimer() return timer end
function StopCockpitTimer() timerRunning = false; record("StopCockpitTimer") end
for _, name in ipairs({"StopAudioMessage", "HideCockpitTimer", "SetWeaponMask",
    "SetObjectiveOn", "SetObjectiveOff", "Defend", "Goto", "Patrol", "Stop",
    "Attack", "Follow", "AddAmmo", "AddHealth", "SetPerceivedTeam",
    "FailMission", "SucceedMission"}) do
    local operation = name
    _G[operation] = function(...) record(operation, ...) end
end
-- Razor One mocks: positions default to the origin, no object is ever shot at unless a test says so.
local positions = {}
function SetVector(x, y, z) return {x = x, y = y, z = z} end
function GetPosition(h) return positions[h] or {x = 0, y = 0, z = 0} end
function GetTerrainHeightAndNormal() return 0, {x = 0, y = 1, z = 0} end
function GetWhoShotMe(h) return objects[h] and objects[h].shooter or nil end
local function near(h, target, distance)
    distances[tostring(h) .. ":" .. tostring(target)] = distance
end
local function step(time)
    if time then now = time end
    Update(0.05)
end
local function noop() end
local modules = {
    RequireFix = {Initialize = noop}, exu = {},
    Environment = {Init = noop, Update = noop, OnObjectCreated = noop},
    -- The real module plays through AudioMessage and returns its handle.
    ScriptSubtitles = {Play = function(file) return AudioMessage(file) end,
        Queue = function(file) return AudioMessage(file) end, Stop = noop, Update = noop, Initialize = noop},
    CREuropaSites12 = {mission = "misn12"},
    CREuropaWeather = {Seed = 1, Init = noop, Update = noop, Shutdown = noop, OnObjectCreated = noop,
        Save = function() return {tag = "weather"} end, Load = noop, AnnounceState = noop,
        ApplyNetEvent = noop, GetVentSites = function() return {{label = "center_geyser"}} end,
        SetTargetLevel = function(level) record("EuropaTarget", level) end,
        ReleaseForcedLevel = function() record("EuropaRelease") end,
        TriggerPlume = function(index) record("EuropaPlume", index) end,
        Quake = function(strength, seconds) record("EuropaQuake", strength, seconds) end,
        Surge = function(seconds, strength) record("EuropaSurge", seconds, strength) end},
}
function require(name) return assert(modules[name], name) end
local function reset()
    now, serial, cancelled = 0, 0, false
    objects, labels, calls, distances, infos, objectives = {}, {}, {}, {}, {}, {}
    player = object("avtank", 1)
    modules.CRCoopComms = assert(loadfile("Scripts/CRCoopComms.lua"))()
    modules.CRCoopRespawn = assert(loadfile("Scripts/CRCoopRespawn.lua"))()
    modules.CRCoop = assert(loadfile("Scripts/CRCoop.lua"))()
    timer, timerRunning = 0, false
    dofile("Scripts/misn12.lua")
    Start()
    check(not Save().start_done and #calls == count("RemoveObject"), "Start only performs source Setup (and drops the co-op buoys)")
    step()
    return Save()
end
local function capture(m)
    player = m.key_ship
    objects[player].alive = true
    step()
    return m
end
local function disableMovies(m)
    m.camera_off, m.camera4 = true, true
end
local function approach(m, target, distance)
    near(player, target, distance)
    step()
end
local function remote(m, target) near(player, target, 10000) end
local function copy(t)
    if type(t) ~= "table" then return t end
    local result = {}
    for k, v in pairs(t) do result[k] = copy(v) end
    return result
end

local m = reset()
check(m.start_done and objects[m.key_ship].odf == "svfi12", "original key-ship ODF")
check(count("BuildObject", "apcamr") == 6 and count("BuildObject", "svfi12") == 1, "startup spawns")
check(not m.multi and not m.strict and m.slots == 1 and #m.arty == 4, "offline: one human, one key ship, four howitzers found")
for _, h in ipairs({m.center_cam, m.start_cam, m.check2_cam, m.check3_cam, m.check4_cam, m.goal_cam}) do
    check(objects[h].team == 7, "the pods hide on the support team, never guest team 3")
end
check(objects[m.key_ship].team == 5, "the key ship is a CCA (team 5) craft")
check(timer == 1200 and called("StartCockpitTimer", 1200, 300), "20-minute deadline")
check(called("SetWeaponMask", m.key_ship, 3), "original key-ship weapon mask")
check(objects[m.nav1].name == "Drop Zone", "nav name")
step(12); check(not m.camera4, "briefing strict time boundary")
step(12.01); check(m.camera4 and called("CameraFinish"), "briefing completion")
step(13); check(called("AddHealth", m.ccacom_tower, 200), "tower repairs every simulated second")
local repairs = count("AddHealth"); local repairAt = m.next_second; step(repairAt)
check(count("AddHealth") == repairs, "repair timer strict boundary")
step(repairAt + 0.01); check(count("AddHealth") == repairs + 1, "repair next interval")

-- An unpiloted key vehicle still stops at the checkpoint and can be captured.
m = reset(); objects[m.key_ship].alive = false
near(m.key_ship, m.checkpoint1, 79); step()
check(m.checked_in and called("Stop", m.key_ship, 1), "sniped vehicle uses existence test")
step(20); check(not m.going_again, "checkpoint wait strict boundary")
step(20.01); check(m.going_again, "key-ship route restarts after wait")
near(m.key_ship, m.spawn_geyser, 99); step(30.02)
check(count("BuildObject", "svfi12") == 2 and not m.checked_in and not m.going_again, "key-ship recycling")
capture(m)
check(m.key_captured and called("AddAmmo", player, 2000), "capture ammo and state")
check(#objectives == 5 and objectives[1][2] == "green", "capture objective panel")
check(called("SetObjectiveOff", m.checkpoint1), "capture removes checkpoint marker")
local spawnCount = count("BuildObject", "svfi12"); step(50)
check(count("BuildObject", "svfi12") == spawnCount, "captured vehicle never respawns")

-- Capture movie has three timed shots; cancelling advances the original sequence.
m = capture(reset()); step(10)
check(not m.camera_on, "capture movie strict boundary")
step(10.01); check(m.camera_on and m.camera1 and not m.camera2, "capture movie starts")
check(called("AudioMessage", "misn1218.wav"), "first capture narration")
local shotAt = m.camera_time; step(shotAt); check(not m.camera2, "second shot strict boundary")
step(shotAt + 0.01); check(m.camera2 and called("AudioMessage", "misn1219.wav"), "second capture shot")
step(22.03); check(m.camera3 and called("AudioMessage", "misn1220.wav"), "third capture shot")
step(28.04); check(m.camera_off and called("AudioMessage", "misn1222.wav"), "capture movie ends")
m = capture(reset()); cancelled = true; step(10.01)
check(m.camera1 and m.camera2 and m.camera3 and m.camera_off, "source same-frame cancel cascade")

-- Correct route, uplink hysteresis, interruption/reconnect, delayed return check.
m = capture(reset()); disableMovies(m)
approach(m, m.checkpoint2, 69); check(m.check2 and m.good1, "checkpoint 2 accepted")
remote(m, m.checkpoint2); approach(m, m.checkpoint3, 69)
check(m.check3 and m.good2, "checkpoint 3 accepted")
remote(m, m.checkpoint3); approach(m, m.checkpoint4, 69)
check(m.check4 and m.good3, "checkpoint 4 accepted")
remote(m, m.checkpoint4); approach(m, m.ccacom_tower, 100)
check(m.did_it_right and not m.interface_connect, "proper final checkpoint greeting")
approach(m, m.ccacom_tower, 60); check(not m.interface_connect, "uplink strict 60-metre boundary")
approach(m, m.ccacom_tower, 59); check(m.interface_connect and m.interface_time == 45, "45-second uplink")
approach(m, m.ccacom_tower, 76); check(m.warning_message and m.interface_connect, "75-metre warning")
step(5); check(m.warning_message, "warning-repeat strict boundary")
step(5.01); check(not m.warning_message, "warning repeat expires")
step(); check(m.warning_message and count("AudioMessage", "misn1202.wav") == 2, "warning repeats")
approach(m, m.ccacom_tower, 85); check(m.interface_connect, "85-metre connection boundary")
approach(m, m.ccacom_tower, 86); check(not m.interface_connect, "uplink breaks beyond 85 metres")
approach(m, m.ccacom_tower, 59); check(m.interface_time == now + 45, "reconnect starts full interval")
local uploadEnd = m.interface_time; step(uploadEnd)
check(not m.interface_complete, "upload strict timer boundary")
step(uploadEnd + 0.01)
check(m.interface_complete and not timerRunning and called("HideCockpitTimer"), "upload stops/hides deadline")
check(m.discovered and called("Attack", m.guard_tank1, player), "upload triggers escape opposition")
check(#objectives == 1 and objectives[1][1] == "misn1205.otf", "return objective")
check(count("BuildObject", "avfigh") == 0 and m.razor_state == "none" and count("AudioMessage", "misn1224.wav") == 0,
    "no Razor One before the hunters catch up: the uplink alone does not call him")
step(now + 30)
check(count("BuildObject", "avfigh") == 0, "hunters far away and nobody hurt: still no Razor One")
-- Hunters were seen outside the catch radius; one closes to 200 m: the call goes out once.
near(player, m.patrol1_1, 199); step()
check(count("BuildObject", "avfigh") == 1 and objects[m.razor].team == 1 and m.razor_state == "held",
    "Razor One's scout appears at the compound when a hunter closes to 200 m (restored arc)")
check(called("SetPerceivedTeam", m.razor, 5) and called("SetObjectiveName", m.razor, "Razor One"), "disguised and marked")
check(count("AudioMessage", "misn1224.wav") == 1 and called("Goto", m.razor), "he calls at once and heads for the channel")
step(now + 30)
check(count("BuildObject", "avfigh") == 1 and count("AudioMessage", "misn1224.wav") == 1, "the call happens only once")
check(#(m.hunters or {}) == 0 and #(m.extra_patrols or {}) == 0, "one human: no scaling units")
near(player, m.nav1, 74); step(m.win_check_time)
check(not m.win, "source 120-second return delay strict boundary")
step(m.win_check_time + 0.01)
check(m.win and called("SucceedMission", now + 7, "misn12w1.des"), "drop-zone victory")
local victories = count("SucceedMission"); step(now + 6)
check(count("SucceedMission") == victories, "victory emitted once")

-- A hit from a CCA unit also calls him; a hit from anything else does not.
local function uplinkDone()
    local u = capture(reset()); disableMovies(u); approach(u, u.ccacom_tower, 59)
    step(u.interface_time + 0.01)
    return u
end
m = uplinkDone()
check(m.interface_complete and m.razor_state == "none", "uplink done, nobody caught")
objects[player].health = 0.8; objects[player].shooter = object("avtank", 1); step()
check(m.razor_state == "none", "damage from a friendly does not call Razor One")
objects[player].health = 0.7; objects[player].shooter = m.patrol1_2; step()
check(m.razor_state == "held" and count("AudioMessage", "misn1224.wav") == 1, "damage from a CCA unit calls Razor One")
m = capture(reset()); disableMovies(m)
objects[player].health = 0.95; objects[player].shooter = m.patrol1_2; step()
check(m.razor_state == "none", "damage before the uplink never counts")

-- Out-of-order routes and original recovery/escalation branches.
m = capture(reset()); disableMovies(m)
approach(m, m.checkpoint3, 100)
check(m.cca_warning_message and m.follow_spawn and m.last_warned, "3 before 2 warning and escort")
remote(m, m.checkpoint3); approach(m, m.checkpoint2, 69)
check(m.better_message and not m.check2, "source recovery retains check2 flag")
remote(m, m.checkpoint2); approach(m, m.checkpoint4, 69)
check(m.check4 and not m.real_bad, "recovered route accepts checkpoint 4")
remote(m, m.checkpoint4); approach(m, m.ccacom_tower, 100)
check(m.final_warned and m.final_warning == now + 20, "recovered final warning interval")
step(m.final_warning + 0.01)
check(m.identify_message and m.next_message_time == now + 10, "final warning becomes identification demand")
step(m.next_message_time + 0.01)
check(m.real_bad and m.discovered and called("SetPerceivedTeam", player, 1), "identification timeout exposes player")
check(count("BuildObject", "svtank") == 4, "discovery guard wave")
for _, h in ipairs({m.guard1, m.guard2, m.guard3}) do objects[h].alive = false end
local survivor = m.guard4; step()
check(count("BuildObject", "svtank") == 8 and IsAlive(survivor), "source replenishment ignores guard4 survivor")

m = capture(reset()); disableMovies(m)
approach(m, m.checkpoint2, 69); remote(m, m.checkpoint2)
approach(m, m.checkpoint4, 100)
check(m.cca_warning_message and not m.check3, "2 to 4 warning")
remote(m, m.checkpoint4); approach(m, m.checkpoint3, 69)
check(m.better_message and m.check4 and not m.check3, "2/4/3 recovery preserves source shortcut")

m = capture(reset()); disableMovies(m); approach(m, m.ccacom_tower, 100)
check(m.straight_to_5 and m.identify_message and m.next_message_time == 15, "straight to 5 uses 15-second warning")
m = capture(reset()); disableMovies(m); approach(m, m.checkpoint4, 100)
check(m.identify_message and m.next_message_time == 20, "straight to 4 uses 20-second warning")
m = capture(reset()); disableMovies(m); approach(m, m.checkpoint3, 100)
remote(m, m.checkpoint3); approach(m, m.checkpoint4, 100)
check(m.real_bad and m.discovered, "3 to 4 without recovery immediately exposes player")
check(not m.game_blown and count("FailMission") == 0, "one human: exposure hunts the player but never fails the mission (stock rules)")

-- Pre-capture failures retain the 5-second wave and 10-second failure schedule.
m = reset(); objects[m.user_tank].health = 0.90; step()
check(not m.game_blown, "player health strict threshold")
objects[m.user_tank].health = 0.89; step()
check(m.game_blown and called("FailMission", 10), "damaged starting tank failure")
step(5); check(not m.death_squad1, "death squad strict boundary")
step(5.01); check(IsAlive(m.death_squad1) and IsAlive(m.death_squad4), "death squad appears after five seconds")
check(count("BuildObject", "svltnk") == 2, "original death-squad unit mix")
local failures = count("FailMission"); step(6)
check(count("FailMission") == failures, "failure emitted once")
m = reset(); objects[m.key_ship].alive = false; objects[m.key_ship].health = 0.49; step()
check(m.game_blown and called("AudioMessage", "misn1228.wav"), "empty key ship damage failure")
m = reset(); near(m.user_tank, m.checkpoint1, 74); step()
check(m.game_blown and objectives[1][2] == "red", "tank checkpoint intrusion fails")
m = reset(); timer = 0; step()
check(m.game_over and called("FailMission", 15, "misn12f1.des"), "deadline failure descriptor")

-- Entering another Soviet vehicle provokes the original recurring attacks.
m = capture(reset()); disableMovies(m); player = object("svtank", 1); step()
check(m.out_of_ship and m.grump and m.blown_otf, "vehicle switch detected")
check(called("Attack", m.guard_tank1, player) and m.grump_time == 180, "vehicle-switch response")
step(180.01); check(not m.grump, "recurring hostility interval")
step(); check(m.grump and m.grump_time == now + 180, "recurring hostility reissues attacks")

-- Patrol typo correction, and original OR predicate (both flags stop routing).
m = reset(); m.patrol2_1_time = 0; near(m.patrol2_1, m.center_geyser, 49); step(1)
check(called("Goto", m.patrol2_1, "path3") and not called("Goto", m.patrol1_1, "path3"), "patrol2_1 gets its own path3 command")
check(m.p2_1center and m.patrol2_1_time == 11, "corrected route retains interval/state")
m.real_bad, m.game_blown, m.p2_1center = true, true, false; m.patrol2_1_time = 0
calls = {}; step(2)
check(not called("Goto", m.patrol2_1, "path3"), "source OR routing stops only when both conditions hold")

-- Nav cameras use actual team changes; removed pods cannot crash name updates.
m = capture(reset()); disableMovies(m); infos.sbhqt1 = true
approach(m, m.center, 99)
check(m.camera_swap1 and objects[m.start_cam].team == 1 and objects[m.goal_cam].team == 1, "center console reveals route pods")
check(objects[m.center_cam].team == 7 and objects[m.start_cam].name == "Check Point", "source center pod exclusion and names")
remote(m, m.center); step(1.01)
check(m.camera_swap_back and not m.camera_swap1 and objects[m.start_cam].team == 7, "console range restores the hidden team")
near(player, m.checkpoint1, 99); step()
check(m.camera_swap2 and objects[m.center_cam].team == 1, "checkpoint console reveals center pod")
remote(m, m.checkpoint1); step(now + 1.01)
check(not m.camera_swap2 and objects[m.center_cam].team == 7, "checkpoint console range restores center pod")
m = capture(reset()); disableMovies(m); infos.sbhqt2 = true
RemoveObject(m.check2_cam); approach(m, m.center, 99)
check(m.camera_swap1 and not IsValid(m.check2_cam), "removed camera pod safely skipped")

-- Save/load into a freshly loaded script must retain timers/handles/camera flags.
m = capture(reset()); disableMovies(m); approach(m, m.ccacom_tower, 59)
step(20); local saved = copy(Save()); local builds = count("BuildObject")
dofile("Scripts/misn12.lua"); Load(saved)
check(Save().interface_time == 45 and Save().key_ship == m.key_ship, "load restores timer and vehicle handle")
step(45); check(not Save().interface_complete and count("BuildObject") == builds, "load neither restarts Setup nor duplicates spawns")
step(45.01); check(Save().interface_complete, "restored upload completes on original schedule")
saved = copy(Save()); dofile("Scripts/misn12.lua"); Load(saved)
near(player, saved.nav1, 74); step(saved.win_check_time + 0.01)
check(Save().win, "save during escape preserves victory gate")
check(saved.countdown_time == 99999 and saved.check1 == false, "unused original fields survive serialization")
print("misn12: " .. checks .. " checks passed (" .. _VERSION .. ")")
