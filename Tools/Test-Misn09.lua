-- Run from the repository root: lua5.1 Tools/Test-Misn09.lua
-- Mock-host tests verify authored branching/commands, not native AI or rendering.
assert(_VERSION == "Lua 5.1", "Run this suite with Lua 5.1")
local now, serial, objects, labels, calls, distances, cargo, audio, cancelled, info
local scraps, unitCount, objectives
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function record(name, ...)
    calls[#calls + 1] = {name, ...}
end
local function count(name, arg, arg2)
    local total = 0
    for _, call in ipairs(calls) do
        if call[1] == name and (arg == nil or call[2] == arg)
            and (arg2 == nil or call[3] == arg2) then total = total + 1 end
    end
    return total
end
local function last(name)
    for i = #calls, 1, -1 do
        if calls[i][1] == name then return calls[i] end
    end
end
local function make(odf, team)
    serial = serial + 1
    objects[serial] = {odf = odf, team = team or 2, alive = true, deployed = false}
    return serial
end
function GetHandle(label)
    if not labels[label] then labels[label] = make("map", 0) end
    return labels[label]
end
function GetPlayerHandle() return GetHandle("player") end
function GetTime() return now end
function IsValid(h) return objects[h] ~= nil end
function IsAlive(h) return IsValid(h) and objects[h].alive end
function IsOdf(h, odf) return objects[h].odf == odf end
function IsDeployed(h) return objects[h].deployed end
function GetTeamNum(h) return objects[h].team end
function GetTug(h) return cargo[h] end
function GetDistance(h, target)
    assert(IsValid(h), "invalid distance origin")
    assert(type(target) == "string" or IsValid(target), "invalid distance target")
    return distances[tostring(h) .. ":" .. tostring(target)] or 10000
end
function BuildObject(odf, team, where)
    local h = make(odf, team)
    record("BuildObject", odf, team, where, h)
    AddObject(h) -- Native creation may synchronously notify the mission.
    return h
end
function AudioMessage(name)
    local message = {done = false, name = name}
    audio[#audio + 1] = message
    record("AudioMessage", name)
    return message
end
function IsAudioMessageDone(message)
    assert(message ~= nil, "nil audio message passed to stock API")
    return message.done
end
function StopAudioMessage(message)
    assert(message ~= nil, "nil audio message passed to stock API")
    message.done = true
    record("StopAudioMessage", message)
end
function CameraCancelled() return cancelled end
function CameraReady() record("CameraReady"); return true end
function CameraPath(...) record("CameraPath", ...); return false end
function CameraFinish() record("CameraFinish"); return true end
function IsInfo(odf) return info[odf] == true end
function CountUnitsNearObject(h, distance, team, odf)
    record("CountUnitsNearObject", h, distance, team, odf)
    return unitCount
end
function SetScrap(team, amount) scraps[team] = amount; record("SetScrap", team, amount) end
function GetScrap(team) return scraps[team] or 0 end
function ClearObjectives() objectives = {}; record("ClearObjectives") end
function AddObjective(name, color)
    objectives[name] = color
    local total = 0
    for _ in pairs(objectives) do total = total + 1 end
    assert(total <= 10, "stock objective capacity exceeded")
    record("AddObjective", name, color)
end
for _, name in ipairs({"Defend", "Follow", "Goto", "Stop", "Pickup", "Dropoff",
    "SetPilot", "SetAIP", "SetObjectiveName", "SetObjectiveOn", "FailMission", "SucceedMission"}) do
    local operation = name
    _G[operation] = function(...) record(operation, ...) end
end
local function reset()
    now, serial, cancelled, unitCount = 0, 0, false, 1
    objects, labels, calls, distances, cargo, audio, info, scraps, objectives = {}, {}, {}, {}, {}, {}, {}, {}, {}
    dofile("Scripts/misn09.lua")
    Start()
    Update(0.05)
    return Save()
end
local function step(time) now = time; Update(0.05) end
local function near(h, target, distance) distances[tostring(h) .. ":" .. tostring(target)] = distance end
local function kill(h) objects[h].alive = false end
local function destroyArtillery(m)
    for i = 1, 6 do kill(m["ccaturret" .. i]) end
end
local function convoy(m)
    step(1301)
    check(m.third_warning and IsAlive(m.relic) and IsAlive(m.ccatug), "convoy spawns")
end
local function seize(m)
    convoy(m)
    Update(0.05)
    cargo[m.relic] = m.ccatug
    Update(0.05)
end

local m = reset()
check(m.start_done and m.start_camera1 and m.x == 950 and m.y == 3000, "native setup/start state")
check(m.camera_ready_time == 6 and m.next_shot_time == 22 and m.third_warning_time == 1300, "startup timer values")
check(count("Follow", m.nsdfrig, m.nsdfmuf) == 1 and count("Follow", m.nsdfslf, m.nsdfrig) == 1, "rendezvous followers")
check(last("Follow")[4] == 0 and scraps[2] == 40, "command priorities and CCA resource setup")
check(count("AudioMessage") == 0 and count("CameraPath", "camera_circle") == 1, "opening camera before briefing")
check(count("SetObjectiveName", m.nav1, "Choke Point") == 1, "initial navigation name")
step(6)
check(not m.opening_vo, "strict six-second briefing boundary")
step(6.1)
check(m.opening_vo and not m.muf_gobaby and objectives["misn0900.otf"] == "white", "briefing waits for audio")
m.audmsg.done = true; Update(0.05)
check(m.muf_gobaby and count("Goto", m.nsdfmuf, "return_path") == 1, "audio completion moves factory")
near(m.user, m.nsdfmuf, 70); step(7.2)
check(not m.muf_contact, "strict rendezvous distance")
near(m.user, m.nsdfmuf, 69); step(8.3)
check(m.muf_contact and m.movie_time == 15.3 and scraps[1] == 20, "rendezvous releases units/resources")
check(count("Defend", m.nsdfrig) == 1 and count("Stop", m.nsdfslf) == 1, "rendezvous command handoff")
step(15.4)
check(m.camera_ready and m.x == 1040 and not m.cam_off, "artillery shot and original per-update camera height")
step(22.4)
check(not m.cam_off, "strict artillery camera end time")
step(22.5)
check(m.cam_off and m.player_camera_off and count("SetAIP", "misn09.aip") == 1, "camera completion activates initial AIP")
check(objectives["misn0900.otf"] == "green" and objectives["misn0901.otf"] == "white", "artillery objectives")
step(82.5)
check(not m.recon_artil, "strict recon timer")
step(82.6)
check(m.recon_artil and count("AudioMessage", "misn0913.wav") == 1, "recon warning")
near(m.user, m.nav1, 99); step(83.7)
check(m.base_warning and count("AudioMessage", "misn0914.wav") == 1, "base proximity warning")

m = reset(); cancelled = true; Update(0.05)
check(m.player_camera_off and not m.start_camera1 and count("StopAudioMessage") == 0, "early cancel safely handles absent audio")
m = reset(); step(7); cancelled = true; Update(0.05)
check(m.audmsg.done and m.muf_gobaby and count("StopAudioMessage") == 1, "briefing cancellation releases factory")

m = reset()
local slots = {"cca1", "cca2", "cca3", "cca4"}
for i, slot in ipairs(slots) do
    local h = make(i == 1 and "svturr.odf" or "svturr", 1)
    AddObject(h)
    check(m[slot] == h, "native ODF-only turret callback slot " .. i)
end
local fifth = make("svturr", 2); AddObject(fifth)
check(m.cca4 ~= fifth, "full native turret slots are not replaced")
kill(m.cca1); AddObject(fifth)
check(not IsAlive(m.cca1), "dead native tracking slot is retained")
Update(0.05)
check(m.post3 and not m.post1 and count("Goto", m.cca3, "post3") == 1, "post3 fix does not set post1")
Update(0.05)
check(count("Goto", m.cca3, "post3") == 1, "post3 move is not reset each frame")
step(10)
check(count("Defend", m.cca3) == 0, "strict turret timer boundary")
step(10.1)
check(count("Defend", m.cca3) == 1 and m.turret3_time == 25.1, "post3 periodic defense restored")
step(25.1); check(count("Defend", m.cca3) == 1, "strict periodic defense boundary")
step(25.2); check(count("Defend", m.cca3) == 2, "fifteen-second turret defense cadence")
for _, item in ipairs({{"svfigh", "cca5"}, {"svfigh", "cca6"}, {"svfigh", "cca7"}, {"svfigh", "cca8"},
    {"svtank", "cca9"}, {"svtank", "cca0"}, {"svscav", "scav1"}, {"svscav", "scav2"}, {"svscav", "scav3"},
    {"avwalk", "nsdfgech1"}, {"svhaul", "ccatug"}, {"absilo", "avsilo"}}) do
    local h = make(item[1], 1); AddObject(h)
    check(m[item[2]] == h, "native callback slot " .. item[2])
end
AddObject(nil)
check(m.avsilo ~= nil, "nil callback is ignored")

m = reset(); step(7)
check(not m.scavs_alive, "scavengers remain followers before deployment")
objects[m.nsdfmuf].deployed = true; step(9.1)
check(m.muf_deployed and m.scavs_alive and count("Stop", m.avscav1) == 1, "deployment releases scavengers")
Update(0.05); check(count("Stop", m.avscav1) == 1, "scavenger release is one-shot")
m = reset(); local silo = make("absilo", 1); AddObject(silo); Update(0.05)
check(m.scavs_alive and not m.muf_deployed, "silo also releases scavengers")

m = reset(); destroyArtillery(m); Update(0.05)
check(m.objective1 and count("SetAIP", "misn09a.aip") == 1, "artillery destruction activates aggressive AIP")
check(objectives["misn0901.otf"] == "green" and objectives["misn0902.otf"] == "white", "artillery destruction objectives")
m.muf_deployed = true; m.deploy_check = 0
near(m.nsdfmuf, m.convoy_geyser, 399); step(1)
check(not m.muf_deployed_good, "semicolon fix requires actual deployment")
objects[m.nsdfmuf].deployed = true; near(m.nsdfmuf, m.convoy_geyser, 400); step(3.1)
check(not m.muf_deployed_good, "strict 400m deployment distance")
near(m.nsdfmuf, m.convoy_geyser, 399); step(5.2)
check(m.muf_deployed_good and objectives["misn0902.otf"] == "green", "correct deployment updates display")

m = reset(); step(700); check(not m.first_warning, "strict first warning boundary")
step(700.1); check(m.first_warning and count("AudioMessage", "misn0901.wav") == 1, "first warning")
step(1000); check(not m.second_warning, "strict second warning boundary")
step(1000.1); check(m.second_warning and count("AudioMessage", "misn0902.wav") == 1, "second warning")
step(1300); check(not m.third_warning, "strict convoy boundary")
near(m.user, m.convoy_geyser, 500); step(1300.1)
check(not m.third_warning and m.third_warning_time == 1311.1 and count("BuildObject") == 0, "visible convoy spawn deferred eleven seconds")
near(m.user, m.convoy_geyser, 501); step(1311.1)
check(not m.third_warning, "strict deferred spawn boundary")
step(1311.2)
check(m.third_warning and count("BuildObject") == 12 and objects[m.relic].team == 3, "original relic/tug/ten-escort convoy")
check(m.relic_free and not m.convoy_started and count("Pickup") == 0, "spawn preserves next-update pickup")
check(count("SetAIP", "misn09b.aip") == 1 and objectives["misn0901.otf"] == "red", "convoy switches AIP and incomplete objective display")
Update(0.05)
check(m.tug_underway and count("Pickup", m.ccatug, m.relic) == 1, "CCA tug tries to take relic once")
cargo[m.relic] = m.ccatug; Update(0.05)
check(m.relic_seized and m.head_4_pad and m.convoy_started, "enemy pickup starts convoy")
check(count("Dropoff", m.ccatug, "soviet_path") == 1 and count("Follow", m.convoy0, m.ccatug) == 1, "convoy escort/dropoff commands")
check(count("SetObjectiveOn", m.relic) == 1 and count("SetObjectiveName", m.relic, "Alien Relic") == 1, "relic objective marker")
step(1318.2); check(not m.convoy_cam_ready, "strict convoy camera start boundary")
step(1318.3)
check(m.convoy_cam_ready and not m.convoy_cam_off and m.y == 2990, "camera predicate fix keeps shot open")
step(1336.3); check(not m.convoy_cam_off, "strict eighteen-second camera boundary")
step(1336.4); check(m.convoy_cam_off, "convoy shot finishes on original authored timer")
local spawns = count("BuildObject")
kill(m.ccatug); cargo[m.relic] = nil; Update(0.05)
check(m.relic_free and not m.relic_seized and not m.tug_underway and not m.head_4_pad, "destroyed enemy tug frees relic and flags")
step(1400)
check(count("BuildObject") == spawns, "cut replacement-tug code stays inactive")
local friendly = make("avhaul", 1); cargo[m.relic] = friendly; Update(0.05)
check(m.relic_secure and not m.relic_free and m.tugger == friendly, "friendly relic capture")
kill(friendly); cargo[m.relic] = nil; Update(0.05)
check(m.relic_free and not m.relic_secure, "destroyed friendly tug frees relic")

m = reset(); seize(m); step(1309); cancelled = true; Update(0.05)
check(m.convoy_cam_off, "convoy camera honors cancellation")
m = reset(); m.third_warning = true; destroyArtillery(m); Update(0.05)
check(m.objective1 and count("SetAIP", "misn09a.aip") == 0, "late artillery destruction does not override convoy AIP")
m = reset(); m.third_warning = true
m.muf_deployed = true; objects[m.nsdfmuf].deployed = true
m.objective1 = false; m.deploy_check = 0; near(m.nsdfmuf, m.convoy_geyser, 399); step(1)
check(m.muf_deployed_good and objectives["misn0901.otf"] == "red", "deployment display preserves failed artillery color")

m = reset(); near(m.user, m.charon, 69); step(30)
check(not m.charon_found, "strict Charon poll boundary")
step(30.1); check(m.charon_found and not m.charon_build, "Charon proximity message")
info.hbchar = true; Update(0.05)
check(m.charon_build and objects[m.charon_nav].odf == "apcamr", "Charon info scan builds beacon")
check(count("SetObjectiveName", m.charon_nav, "Alien Relic") == 1, "Charon beacon name")
Update(0.05); check(count("BuildObject", "apcamr") == 1, "Charon beacon built once")

m = reset(); m.scavs_alive = true
for i = 1, 3 do kill(m["avscav" .. i]) end
scraps[1] = 9; Update(0.05)
check(m.game_over and last("FailMission")[3] == "misn09f4.des" and last("FailMission")[2] == 6, "early scavenger/scrap failure")
m = reset(); m.scavs_alive = true; for i = 1, 3 do kill(m["avscav" .. i]) end
scraps[1] = 10; Update(0.05)
check(not m.game_over, "ten scrap avoids scavenger failure")
m.first_warning = true; scraps[1] = 0; Update(0.05)
check(not m.game_over, "first warning closes early scavenger failure window")

m = reset(); seize(m); kill(m.relic); kill(m.nsdfmuf); kill(m.ccalaunch); Update(0.05)
check(last("FailMission")[3] == "misn09f1.des" and count("FailMission") == 1, "relic loss precedes simultaneous factory/pad loss")
m = reset(); seize(m); near(m.ccatug, m.ccalaunch, 99); Update(0.05)
check(last("FailMission")[3] == "misn09f2.des", "enemy launchpad arrival failure")
m = reset(); kill(m.nsdfmuf); kill(m.ccalaunch); Update(0.05)
check(last("FailMission")[3] == "misn09f3.des" and count("FailMission") == 1, "factory failure precedes launchpad failure")
m = reset(); kill(m.ccalaunch); Update(0.05)
check(m.game_over and last("FailMission")[3] == nil and count("AudioMessage", "misn0918.wav") == 1, "launchpad destruction keeps default debrief")

m = reset(); seize(m); kill(m.ccatug); cargo[m.relic] = nil
near(m.relic, m.nsdfmuf, 100); step(1306.1)
check(not m.game_over, "strict relic delivery distance")
near(m.relic, m.nsdfmuf, 99); step(1308.2)
check(m.game_over and count("SucceedMission") == 1 and last("SucceedMission")[3] == "misn09w1.des", "free relic near living factory wins without extra capture/deployment condition")
m = reset(); seize(m); near(m.relic, m.nsdfmuf, 1); step(1306.1)
check(not m.game_over, "enemy-held relic cannot win")
unitCount = 0; step(1361)
check(m.game_over5 and not m.game_over and count("SucceedMission") == 0, "cut all-enemies-cleared victory remains only a message")
check(last("CountUnitsNearObject")[3] == 5000 and last("CountUnitsNearObject")[4] == 2, "original enemy-cleared query")

m = reset(); seize(m); kill(m.ccarecycle); kill(m.ccamuf); Update(0.05)
check(m.ccadead and not m.game_over, "enemy base destruction is informational")
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = clone(item) end
    return result
end
local saved = clone(Save()); local callCount = #calls
Load(saved)
check(Save() == saved and saved.convoy_started and saved.relic_seized, "load restores active convoy/relic state")
check(#calls == callCount, "load itself replays no setup/spawns/cameras")
Update(0.05)
check(count("BuildObject") == 12 and count("Goto", m.ccatug, "soviet_path") == 1, "resumed update does not respawn/restart convoy")
Load(nil); check(Save() == saved, "nil load leaves current state intact")

m = reset(); m.nav1 = nil; m.charon = nil; m.user = nil; Update(0.05)
check(not m.game_over and not m.base_warning, "missing optional handles do not create proximity alarms")
check(count("CameraPath", "launch_camera_path") == 0 and count("CameraPath", "choke_cam_path") == 0,
    "cut opening camera alternatives remain inactive")
print("misn09: " .. checks .. " Lua 5.1 behavior checks passed")
