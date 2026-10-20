-- Mission 03's closing NSDF launch inside the complete misn03 script: Present ops,
-- ordered relay, remote object cameras, skip, deadline, pad loss and save/load.
-- Reuses Test-Misn03Coop.lua's engine/network harness (everything before its first
-- scenario), then drives only the ending.
local source = assert(io.open("Tools/Test-Misn03Coop.lua", "rb")):read("*a")
local head = source:match("^(.-)\n%-%- Four humans, distinct difficulty preferences")
assert(head, "Test-Misn03Coop.lua harness marker moved")

local scenarios = [==[
local function copy(value)
    if type(value) == "function" or type(value) == "userdata" then error("saved state must be plain data") end
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[copy(k)] = copy(v) end
    return out
end
local function addRocket()
    objects.cr03_rocket = { alive = true, team = 0, odf = "cr03rok", health = 0, maxHealth = 0,
        pose = { posit_x = 1000, posit_y = 120, posit_z = 5000 } }
end
local function fxCount(peer, template)
    local n = 0
    for _, s in pairs(peer.fx.systems) do if s.template == template then n = n + 1 end end
    return n
end
local function lightCount(peer) local n = 0; for _ in pairs(peer.fx.lights) do n = n + 1 end; return n end
-- The evacuation, the all-player gate and the older film up to its natural end.
local function driveToOutro(peers_, host)
    host.state.support_time, host.state.apc_spawn_time = now - 1, now - 1
    tick(0.1); settle()
    host.state.movie_time = now - 1
    tick(0.1); settle()
    host.state.pull_out_time, host.state.turret_move_time = now - 1, now - 1
    for _, p in ipairs(peers_) do p.nearLaunch = true end
    tick(0.1); settle()
    check(host.state.final_objective and host.state.startfinishingmovie and host.state.camera_on,
        "all-player gate and the older film did not start")
end

-- Co-op: the older film hands over to the launch at its natural end.
reset(); addRocket()
local host = makePeer(10, 1, true)
local guest = makePeer(20, 2, true)
local guest2 = makePeer(30, 3, true)
registerAll(); settle()
driveToOutro({ host, guest, guest2 }, host)
check(host.state.coopOutroDeadline > now + 95, "the outro deadline must include the launch shot")
check(count(host, "SucceedMission") == 0 and not host.state.launchPhase, "launch started before the older film ended")
host.state.camera_off_time = now - 1
local finishes = count(host, "CameraFinish")
tick(0.1); settle()
check(host.state.launchPhase and host.state.launchFilm and host.state.launchStart > 0, "the launch did not start when the older film ended")
check(count(host, "SucceedMission") == 0 and not host.state.camera_off, "the mission ended before the launch shot")
check(count(host, "CameraFinish") == finishes + 1, "the older shot's camera was not handed back exactly once")
check(count(host, "CameraObject") > 0 and last(host, "CameraObject")[2] == "cr03_rocket" and
    last(host, "CameraObject")[6] == "cr03_rocket", "the leader's camera is not on cr03_rocket")
for _, p in ipairs({ host, guest, guest2 }) do
    check(fxCount(p, "CR/M06/Core") == 1 and fxCount(p, "CR/M06/Plume") == 1 and fxCount(p, "CR/M06/Dust") == 1,
        "every peer must own the shipped Core, Plume and Dust systems")
    check(fxCount(p, "CR/M06/Smoke") == 0, "the Moon has no atmosphere: no smoke layer")
    check(p.fx.created == 3 and lightCount(p) == 1, "three systems and one engine light per peer")
    for _, light in pairs(p.fx.lights) do
        check(type(light.color.r) == "number" and type(light.color.g) == "number" and
            type(light.color.b) == "number" and light.color.r > light.color.b, "the light takes named r/g/b fields")
    end
end
check(count(guest, "RocketFX") == 0, "Present ops are applied, never recorded as engine calls")
-- Rocket anchors: centre bell + 6 on a 9 m ring, every peer.
for _, p in ipairs({ guest, guest2 }) do
    for _, s in pairs(p.fx.systems) do
        if s.template == "CR/M06/Core" or s.template == "CR/M06/Plume" then
            check(s.offsets[0] and s.offsets[0].x == 0 and s.offsets[0].z == 0, "centre bell")
            for index = 1, 6 do
                local at = s.offsets[index]
                check(math.abs(at.x * at.x + at.z * at.z - 81) < 1e-6, "ring bell on a 9 m radius")
            end
            check(s.offsets[7] == nil, "the shared eight-emitter template keeps its eighth emitter dormant")
        end
    end
end
-- Remote cameras follow the shot through the leader's C snapshots.
tick(0.3)
for _, p in ipairs({ guest, guest2 }) do
    check(count(p, "CameraReady") >= 1 and count(p, "CameraObject") >= 1, "guest camera did not follow the launch")
    local call = last(p, "CameraObject")
    check(call[2] == "cr03_rocket" and call[6] == "cr03_rocket", "guest camera subject/target is the rocket")
    check(call[3] > 9000 and call[4] < 0, "guest uses the leader's pullback offsets")
end
-- The pad is not needed to survive: its loss during the launch is not a mission failure.
tick(2)
for _, p in ipairs({ host, guest }) do check(count(p, "SetTransform") > 0, "peer-local rocket flight") end
check(count(host, "SucceedMission") == 0, "mission ended mid-launch")
local fails = count(host, "FailMission")
objects.launch_pad.alive = false
tick(0.1)
check(count(host, "FailMission") == fails and not host.state.lost, "pad loss during the launch must not fail the mission")
settle()
check(count(host, "FailMission") == fails and count(host, "SucceedMission") == 1,
    "pad loss ends the shot early and succeeds")
for _, p in ipairs({ guest, guest2 }) do
    check(count(p, "SucceedMission") == 1 and count(p, "FailMission") == 0 and
        last(p, "SucceedMission")[3] == "misn03w1.des", "guest result missing/duplicated")
    check(next(p.fx.systems) == nil and lightCount(p) == 0, "the result tears the local effects down")
end

-- Co-op: the 90 s deadline is a trigger for the launch, not a cut through it.
reset(); addRocket()
host = makePeer(10, 1, true); guest = makePeer(20, 2, true)
registerAll(); settle()
driveToOutro({ host, guest }, host)
host.state.coopOutroDeadline = now - 1
tick(0.1); settle()
check(host.state.launchPhase and count(host, "SucceedMission") == 0, "the deadline must start the launch, not end the mission")
local started = host.state.launchStart
for i = 1, 50 do tick(0.1, true) end
check(count(host, "SucceedMission") == 0, "the launch must hold until its eleven seconds")
for i = 1, 40 do tick(0.1, true) end
check(count(host, "SucceedMission") == 1 and now - started >= 11, "the launch ended on its eleven seconds")
check(count(guest, "SucceedMission") == 1, "guest result delivered once")

-- A guest skip releases only that guest's camera; the shared shot and result continue.
reset(); addRocket()
host = makePeer(10, 1, true); guest = makePeer(20, 2, true)
registerAll(); settle()
driveToOutro({ host, guest }, host)
host.state.camera_off_time = now - 1
tick(0.1); settle(); tick(0.3)
local guestFinishes = count(guest, "CameraFinish")
guest.skip = true
tick(0.3); settle()
check(count(guest, "CameraFinish") > guestFinishes, "guest skip did not release its camera")
check(host.state.launchPhase and count(host, "SucceedMission") == 0, "guest skip ended the shared launch")

-- No fixture (older save or map): the previous ending is unchanged.
reset()
host = makePeer(10, 1, true); guest = makePeer(20, 2, true)
registerAll(); settle()
driveToOutro({ host, guest }, host)
host.state.camera_off_time = now - 1
tick(0.1); settle()
check(not host.state.launchPhase and count(host, "SucceedMission") == 1 and fxCount(host, "CR/M06/Core") == 0,
    "without cr03_rocket the mission ends as before")

-- Offline: skip ends promptly, both before and during the launch.
reset(); addRocket()
local offline = makePeer(10, 1, false)
tick(0.1)
driveToOutro({ offline }, offline)
offline.skip = true
tick(0.1)
check(count(offline, "SucceedMission") == 1 and not offline.state.launchPhase and fxCount(offline, "CR/M06/Core") == 0,
    "offline skip of the older film still ends the mission at once")
check(count(offline, "Stop") >= 1, "a skipped cinematic stops its subtitles")

reset(); addRocket()
offline = makePeer(10, 1, false)
tick(0.1)
driveToOutro({ offline }, offline)
offline.state.camera_off_time = now - 1
tick(0.1)
check(offline.state.launchPhase and count(offline, "CameraObject") > 0 and fxCount(offline, "CR/M06/Plume") == 1 and
    count(offline, "SucceedMission") == 0, "offline launch did not start")
local readies = count(offline, "CameraReady")
-- Save and reload mid-launch: start time and phase persist, and the shot resumes.
tick(3)
local startTime = offline.state.launchStart
local saved = copy(offline.env.Save())
check(saved.launchPhase and saved.launchStart == startTime and saved.launchFilm and saved.launchFilm.started == startTime,
    "the launch start time and phase are saved")
offline.env.Load(saved, {}, {})
check(next(offline.fx.systems) == nil, "load drops the old local effects")
now = now + 3
tick(0.1)
check(offline.state.launchPhase and offline.state.launchStart == startTime, "load kept the launch phase")
check(count(offline, "CameraReady") > readies, "load re-acquired the local camera")
check(fxCount(offline, "CR/M06/Core") == 1, "load restarted the exhaust")
check(count(offline, "SucceedMission") == 0, "load ended the launch early")
now = startTime + 10.9
tick(0.05)
check(count(offline, "SucceedMission") == 0, "load shortened the shot")
tick(0.2)
check(count(offline, "SucceedMission") == 1 and last(offline, "SucceedMission")[3] == "misn03w1.des", "resumed launch did not finish")
offline.skip = nil

reset(); addRocket()
offline = makePeer(10, 1, false)
tick(0.1)
driveToOutro({ offline }, offline)
offline.state.camera_off_time = now - 1
tick(0.1); tick(2)
offline.skip = true
tick(0.1)
check(count(offline, "SucceedMission") == 1, "offline skip during the launch must end the mission promptly")
print("misn03 rocket launch: " .. checks .. " complete-script Lua 5.1 checks passed")
]==]

local chunk = assert(loadstring(head .. "\n" .. scenarios, "=Test-Misn03Launch"))
setfenv(chunk, getfenv(1))
chunk()
