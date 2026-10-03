-- Run from repository root: lua5.1 Tools/Test-BlackDog08.lua
-- Mock-host tests verify mission gates and API calls, not engine boarding physics.
local now, objects, labels, calls, done, touching, options, serial, player
local checks = 0
local function check(v, message) assert(v, message); checks = checks + 1 end
local function record(name, ...) calls[#calls + 1] = {name, ...} end
local function count(name, first)
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == name and (first == nil or c[2] == first) then n = n + 1 end
    end
    return n
end
local function last(name)
    for i = #calls, 1, -1 do if calls[i][1] == name then return calls[i] end end
end
local function object(team, pilot)
    serial = serial + 1
    objects[serial] = {health = 1, team = team or 1, pilot = pilot}
    return serial
end
function IsValid(h) return h ~= nil and objects[h] ~= nil end
local function valid(h) assert(IsValid(h), 'invalid engine handle'); return objects[h] end
function GetHandle(name)
    if options.missing == name then return nil end
    if not labels[name] then labels[name] = object() end
    record('GetHandle', name)
    return labels[name]
end
function GetPlayerHandle() return player end
function GetTime() return now end
function GetHealth(h) return valid(h).health end
function GetTeamNum(h) return valid(h).team end
function GetPilotClass(h) return valid(h).pilot end
function IsAliveAndPilot(h) return valid(h).health > 0 and objects[h].pilot ~= nil end
function IsTouching(a, b) valid(a); valid(b); return touching[a .. ':' .. b] == true end
function SetObjectiveName(h, name) valid(h); record('SetObjectiveName', h, name) end
function SetScrap(team, amount) record('SetScrap', team, amount) end
function SetPilot(team, amount) record('SetPilot', team, amount) end
function SetPerceivedTeam(h, team) valid(h).perceived = team; record('SetPerceivedTeam', h, team) end
function PortalIn(h) valid(h).inward = true; record('PortalIn', h) end
function PortalOut(h) valid(h).inward = false; record('PortalOut', h) end
function ActivatePortal(h) valid(h).active = not options.activationDelay; record('ActivatePortal', h) end
function DeactivatePortal(h) valid(h).active = false; record('DeactivatePortal', h) end
function isPortalActive(h) return valid(h).active end
function CameraReady() record('CameraReady') end
function CameraFinish() record('CameraFinish') end
function CameraPath(path, height, speed, target)
    valid(target); record('CameraPath', path, height, speed, target)
    return options.arrived == true
end
function CameraCancelled() return options.cancelled == true end
function AudioMessage(name) record('AudioMessage', name); return 'audio:' .. name end
function StopAudioMessage(id) record('StopAudioMessage', id) end
function IsAudioMessageDone(id) assert(id); return done[id] == true end
function ClearObjectives() record('ClearObjectives') end
function AddObjective(name, color) record('AddObjective', name, color) end
function SetObjectiveOn(h) valid(h); record('SetObjectiveOn', h) end
function BuildObjectAtPortal(odf, team, portal)
    valid(portal); record('BuildObjectAtPortal', odf, team, portal)
    if options.failedBuild == odf then return nil end
    local h = object(team, 'cspilo'); AddObject(h); return h
end
function BuildObject(odf, team, position)
    if type(position) == 'number' then valid(position) end
    record('BuildObject', odf, team, position)
    if options.failedBuild == odf then return nil end
    local h = object(team); AddObject(h); return h
end
function Goto(h, path, priority) valid(h); record('Goto', h, path, priority) end
function Stop(h, priority) valid(h); record('Stop', h, priority) end
function Retreat(h, target, priority)
    valid(h); if type(target) == 'number' then valid(target) end
    record('Retreat', h, target, priority)
end
function Attack(h, target, priority) valid(h); valid(target); record('Attack', h, target, priority) end
function RemovePilot(h) valid(h).pilot = nil; record('RemovePilot', h) end
function RemoveObject(h) valid(h); objects[h] = nil; record('RemoveObject', h) end
function GetIn(h, target, priority) valid(h); valid(target); record('GetIn', h, target, priority) end
function FailMission(time, file) record('FailMission', time, file) end
function SucceedMission(time, file) record('SucceedMission', time, file) end
local randomValues = {}
math.random = function(low, high)
    local v = table.remove(randomValues, 1) or low
    assert(v >= low and v <= high)
    return v
end
local function copy(v)
    if type(v) ~= 'table' then return v end
    local c = {}; for k, x in pairs(v) do c[k] = copy(x) end; return c
end
local function reset(config)
    now, serial = 0, 0
    objects, labels, calls, done, touching = {}, {}, {}, {}, {}
    options = config or {}; randomValues = {}
    player = object(1, 'bspilo')
    if options.testPortal then
        local f = assert(io.open('Scripts/bdmisn08.lua', 'r'))
        local source = f:read('*a'); f:close()
        source = source:gsub('local TEST_PORTAL = false', 'local TEST_PORTAL = true', 1)
        assert(loadstring(source))()
    else
        dofile('Scripts/bdmisn08.lua')
    end
    Start(); Update(0.05)
    return Save()
end
local function tick(time) now = time; Update(0.05); return Save() end
local function reload()
    local snapshot = copy(Save()); local before = #calls
    dofile('Scripts/bdmisn08.lua'); Load(snapshot)
    check(#calls == before, 'load performs no engine side effects')
    return Save()
end
local function contact(a, b) touching[a .. ':' .. b] = true end
local function ready(config)
    local m = reset(config)
    options.arrived = true; done[m.introSound] = true; tick(1)
    tick(26.1)
    return Save()
end
local function arrive(config)
    local m = ready(config)
    tick(m.apcTime + 0.1)
    return Save()
end
local function reprogram(config)
    local m = arrive(config)
    tick(m.apcPilotTime1 + 0.1)
    contact(m.pilot, m.portal); tick(now + 0.1)
    tick(m.apcPilotTime2 + 0.1)
    return Save()
end

local m = reset()
check(count('GetHandle') == 6 and count('SetObjectiveName') == 2, 'all map handles and names')
check(last('SetScrap')[3] == 100 and last('SetPilot')[3] == 10, 'resources')
check(not m.won and not m.lost and not m.objective1Complete and not m.scheduleLose1, 'all flags initialized')
check(m.cameraReady[0] and not m.cameraReady[1], 'zero-based camera arrays')
check(m.apcTime == 999999.9 and m.apc == nil, 'unarmed APC timer')
check(last('CameraPath')[2] == 'path_camera_intro' and last('CameraPath')[3] == 800
    and last('CameraPath')[4] == 1500, 'first camera parameters')
options.arrived = true; tick(1)
check(not m.cameraComplete[0], 'first camera waits for both path and audio')
local cameraCalls = count('CameraPath'); tick(2)
check(count('CameraPath') == cameraCalls, 'arrived first camera is latched')
done[m.introSound] = true; tick(3)
check(m.cameraComplete[0] and m.secondCameraTime == 28, '25-second camera gap')
m = reload(); tick(28)
check(not m.cameraReady[1], 'strict second-camera boundary')
tick(28.1)
check(m.cameraComplete[1] and m.apcTime == 118.1 and m.activateTime == 28.6, 'second camera arms arrival and activation')
check(count('StopAudioMessage') == 0, 'second camera does not stop briefing audio')
check(last('CameraPath')[2] == 'path_portalcam' and last('CameraPath')[3] == 4000
    and last('CameraPath')[4] == 1000, 'portal camera parameters')
tick(m.activateTime)
check(count('ActivatePortal') == 0, 'strict activation boundary')
tick(m.activateTime + 0.1)
check(count('PortalOut') == 1 and not objects[m.portal].inward, 'portal activates outward')
local firstWave = m.attackWaveTime
tick(firstWave); check(count('BuildObjectAtPortal') == 0, 'strict wave boundary')
for i = 1, 4 do
    randomValues = {i == 4 and 9 or 0, i % 2 == 0 and 50 or 49}
    tick(m.attackWaveTime + 0.1)
    check(last('Goto')[3] == (i % 2 == 0 and 'attack_path2' or 'attack_path1'), '50 percent path split')
    check(last('Goto')[4] == 1 and last('BuildObjectAtPortal')[3] == 2, 'wave team and priority')
    check(m.attackWaveTime == now + (i < 4 and 4 or 30), 'four-unit cadence')
end
check(m.waveCount == 0 and last('BuildObjectAtPortal')[2] == 'cvhraz', 'wave resets; final weighted entry')
m.attackWaveTime = 80; tick(80.1)
check(m.attackWaveTime == 999999.9, 'waves suspended inside 45 seconds of APC arrival')
tick(m.apcTime); check(m.apc == nil, 'strict APC arrival boundary')
tick(m.apcTime + 0.1)
check(m.apc ~= nil and last('Goto')[3] == 'portal_out', 'APC portal build and exit')
check(m.apcPilotTime1 == now + 20 and m.attackWaveTime == now + 30 and m.sound3Time == now + 1, 'arrival timers')
local soundAt = m.sound3Time; tick(soundAt); check(count('AudioMessage', 'bd08003.wav') == 0, 'strict APC warning boundary')
tick(soundAt + 0.1); check(count('AudioMessage', 'bd08003.wav') == 1, 'warning one-shot')
m = reload(); tick(m.apcPilotTime1)
check(not m.pilotSpawned1, 'strict pilot departure boundary')
tick(m.apcPilotTime1 + 0.1)
check(m.pilotSpawned1 and objects[m.apc].pilot == nil and objects[m.apc].perceived == 0, 'empty APC and first pilot')
check(last('BuildObject')[4] == m.apc and last('Retreat')[3] == m.portal and last('Retreat')[4] == 1, 'pilot spawns at APC and retreats to portal')
check(last('SetObjectiveOn')[2] == m.apc and count('AddObjective') == 3, 'APC marker and two objectives')
local firstPilot = m.pilot; contact(firstPilot, m.portal); tick(now + 0.1)
check(not m.pilotSpawned1 and not IsValid(firstPilot) and m.apcPilotTime2 == now + 540, 'nine-minute reprogramming timer starts at portal contact')
m = reload(); local returnAt = m.apcPilotTime2; tick(returnAt)
check(not m.portalReprogrammed, 'strict reprogramming boundary')
tick(returnAt + 0.1)
check(m.portalReprogrammed and m.pilotSpawned2 and not objects[m.portal].active, 'return pilot and portal shutdown')
check(last('BuildObject')[4] == 'spawn_pilot' and last('Retreat')[3] == m.apc, 'return pilot placement and target')
check(m.attackWaveTime == 999999.9 and last('AddObjective')[2] == 'bd08003.otf', 'waves stop and capture objective')
local returnPilot = m.pilot; contact(returnPilot, m.apc); tick(now + 0.1)
check(m.pilotBoarding and not m.pilotSpawned2 and m.apcGoBackTime == now + 25, 'GetIn handoff keeps original return timer')
check(last('GetIn')[2] == returnPilot and last('GetIn')[3] == m.apc and IsValid(returnPilot), 'pilot retained until engine consumes it')
m = reload(); objects[m.apc].pilot = 'cspilo'; objects[returnPilot] = nil; tick(now + 0.1)
check(not m.pilotBoarding and m.pilot == nil and objects[m.apc].perceived == 2, 'boarding completion restores perceived team')
local escapeAt = m.apcGoBackTime; tick(escapeAt)
check(not m.apcHeadingBack, 'strict APC departure boundary')
tick(escapeAt + 0.1)
check(m.apcHeadingBack and objects[m.portal].inward and objects[m.portal].active, 'return activates inward portal')
check(last('Retreat')[3] == 'portal_in', 'APC returns along source path')
local escaped = m.apc; contact(escaped, m.portal); tick(now + 0.1)
check(m.lost and m.apc == nil and not IsValid(escaped), 'portal escape loses mission')
done[m.loseSound2] = true; tick(now + 0.1)
check(last('FailMission')[3] == 'bd08lsea.des' and last('FailMission')[2] == now + 1, 'escape descriptor waits for loss audio')
tick(now + 0.1); check(count('FailMission') == 1, 'loss outcome one-shot')

m = reset(); options.cancelled = true; tick(1)
check(m.cameraComplete[0] and count('StopAudioMessage') == 1, 'first camera cancellation stops audio')
tick(26.1); check(m.cameraComplete[1] and count('StopAudioMessage') == 1, 'second camera cancellation keeps audio')
m = ready({activationDelay = true}); tick(27); tick(28)
check(count('ActivatePortal') == 2 and m.attackWaveTime == 999999.9, 'retry activation until active')
options.activationDelay = false; tick(29)
check(m.attackWaveTime == 30, 'wave timer armed only after activation succeeds')

-- Early capture remains latched, and victory waits for reprogramming.
m = arrive(); objects[m.apc].team = 1; tick(now + 0.1)
check(m.apcCommandeered and not m.won, 'capture alone cannot win')
m = reload(); objects[m.apc].team = 2; m.apcPilotTime1 = 999999.9; m.apcPilotTime2 = now
tick(now + 0.1)
check(m.won and count('AudioMessage', 'bd08007.wav') == 1, 'historical capture latch preserved')
done[m.winSound] = true; tick(now + 0.1)
check(last('SucceedMission')[3] == 'bd08win.des' and last('SucceedMission')[2] == now + 1, 'win audio and descriptor')
m = reload(); tick(now + 0.1)
check(count('SucceedMission') == 1 and count('SetScrap') == 1, 'save/load never replays success/resources')

m = reprogram(); objects[m.apc].team = 1; tick(now + 0.1)
check(m.won and not m.pilotSpawned2 and last('Attack')[3] == m.apc, 'capture on return makes pilot attack APC')
m = reprogram(); objects[m.pilot].health = 0; tick(now + 0.1)
check(not m.lost and not m.pilotSpawned2 and m.pilot == nil, 'return pilot death is allowed')
objects[m.apc].team = 1; tick(now + 0.1); check(m.won, 'capture still wins after return pilot death')
m = reprogram(); objects[m.apc].pilot = 'cspilo'; contact(m.pilot, m.apc); tick(now + 0.1)
check(not m.pilotBoarding and last('Attack')[3] == player, 'occupied APC makes return pilot attack player')
m = reprogram(); contact(m.pilot, m.apc); tick(now + 0.1)
objects[m.apc].team = 1; tick(now + 0.1)
check(m.won and not m.pilotBoarding and last('Attack')[3] == m.apc, 'capture during pending boarding is respected')
m = reprogram(); contact(m.pilot, m.apc); tick(now + 0.1)
objects[m.pilot].health = 0; tick(now + 0.1); tick(m.apcGoBackTime + 0.1)
check(not m.pilotBoarding and not m.apcHeadingBack, 'failed boarding does not fabricate APC pilot')

for _, label in ipairs({'recycler', 'command'}) do
    m = reset(); objects[labels[label]].health = 0; tick(1)
    check(m.lost and count('FailMission') == 0, 'protected structure loss waits for audio')
    done[m.loseSound2] = true; tick(2)
    check(last('FailMission')[3] == 'bd08lsea.des', 'protected structure failure descriptor')
end
m = reset(); objects[m.factory].health = 0; tick(1)
check(not m.lost, 'commented factory loss remains disabled')
m = reset(); objects[m.portal].health = 0; tick(1)
check(m.lost and last('FailMission')[3] == 'bd08lsec.des', 'portal destruction immediate failure')
m = arrive(); objects[m.apc].health = 0; tick( now + 0.1)
done[m.loseSound3] = true; tick(now + 0.1)
check(m.lost and last('FailMission')[3] == 'bd08lseb.des', 'APC destruction failure descriptor')
tick(m.apcPilotTime1 + 0.1); check(count('BuildObject') == 0, 'destroyed APC cannot spawn pilot through invalid handle')
m = arrive(); tick(m.apcPilotTime1 + 0.1); objects[m.pilot].health = 0
contact(m.pilot, m.portal); tick(now + 0.1)
check(m.lost and m.apcPilotTime2 == 999999.9, 'dead pilot cannot reprogram even while touching portal')
m = arrive({failedBuild = 'cvapc'})
check(m.lost and m.loseSound3 ~= nil, 'failed APC creation uses existing APC failure')
m = arrive({failedBuild = 'cspilo'}); tick(m.apcPilotTime1 + 0.1)
check(m.lost, 'failed first pilot creation safely loses')
m = reset({missing = 'nav_portal'}); check(count('SetObjectiveName') == 1, 'missing beacon naming is safe')
m = reset(); objects[m.recycler] = nil; tick(1)
check(m.lost, 'deleted protected handle safely loses')

-- Every weighted attacker entry is reachable; five slots are fighters.
m = ready(); m.apcTime = 999999.9
local pool = {'cvtnk', 'cvtnk', 'cvltnk', 'cvfigh', 'cvfigh',
    'cvfigh', 'cvfigh', 'cvfigh', 'cvrckt', 'cvhraz'}
for i = 0, 9 do
    m.attackWaveTime = now; randomValues = {i, 0}; tick(now + 0.1)
    check(last('BuildObjectAtPortal')[2] == pool[i + 1], 'weighted attacker slot ' .. i)
end
m = arrive({testPortal = true})
check(objects[player].perceived == 2 and count('BuildObjectAtPortal') == 1, 'TEST_PORTAL disguises player and disables attack waves')
check(m.apcPilotTime1 == now + 20, 'debug mode keeps pilot departure timing')
tick(m.apcPilotTime1 + 0.1); contact(m.pilot, m.portal); tick(now + 0.1)
check(m.apcPilotTime2 == now + 15, 'TEST_PORTAL uses fifteen-second reprogramming delay')
tick(m.apcPilotTime2 + 0.1)
check(m.portalReprogrammed and count('BuildObjectAtPortal') == 1, 'debug path completes without wave spawns')

-- Preserve source result ordering: protected-unit loss precedes capture;
-- portal destruction is checked after the capture/reprogramming victory gate.
m = reprogram(); objects[m.apc].team = 1; objects[m.command].health = 0; tick(now + 0.1)
check(m.lost and not m.won, 'protected loss precedes victory')
m = reprogram(); objects[m.apc].team = 1; objects[m.portal].health = 0; tick(now + 0.1)
check(m.won and not m.lost, 'victory precedes simultaneous portal destruction')
print('BlackDog08: ' .. checks .. ' behavior checks passed (' .. _VERSION .. ').')
