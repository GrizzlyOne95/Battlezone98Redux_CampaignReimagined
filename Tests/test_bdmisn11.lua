-- Run from repository root: lua5.1 Tests/test_bdmisn11.lua
-- Mocked stock API regression tests; engine AI/rendering still need playtesting.
local now, nextHandle, objects, calls, nearest, distance, timer, done
local function Record(name, ...)
    calls[#calls + 1] = {name, ...}
end
local function Count(name, value)
    local count = 0
    for _, c in ipairs(calls) do
        if c[1] == name and (value == nil or c[2] == value) then count = count + 1 end
    end
    return count
end
function GetTime() return now end
function GetHandle(label) return label end
function GetPlayerHandle() return 'user' end
function IsValid(h) return objects[h] ~= nil end
function GetHealth(h) assert(IsValid(h)); return objects[h] end
function BuildObject(odf, team, where, point)
    Record('BuildObject', odf, team, where, point)
    nextHandle = nextHandle + 1; objects[nextHandle] = 1; return nextHandle
end
function GetNearestEnemy() return nearest end
function GetDistance(h, target, point)
    assert(IsValid(h))
    if target == 'recycler' then return distance end
    if target == 'wave_trigger' then return 0 end
    if target == 'recycler_path' then assert(point == 2); return 0 end
    if target == nearest then assert(IsValid(target)); return 300 end
    return 1000
end
function GetPathPointCount() return 3 end
function RemoveObject(h) objects[h] = nil; Record('RemoveObject', h) end
function GiveMaxHealth(h) assert(IsValid(h) and objects[h] > 0); objects[h] = 1 end
function CameraPath(...) Record('CameraPath', ...); return true end
function CameraCancelled() return false end
function AudioMessage(file) Record('AudioMessage', file); return file end
function IsAudioMessageDone(file) return done[file] == true end
function GetCockpitTimer() return timer end
for _, name in ipairs({'SetScrap', 'SetPilot', 'ClearObjectives', 'AddObjective',
    'SetObjectiveName', 'SetPerceivedTeam', 'CameraReady', 'CameraFinish',
    'StopAudioMessage', 'Stop', 'Retreat', 'SetPilotClass', 'SetTeamNum',
    'Goto', 'Attack', 'SetCloaked', 'Defend2', 'SetObjectiveOn',
    'StartCockpitTimer', 'HideCockpitTimer', 'MakeExplosion', 'ColorFade',
    'FailMission', 'SucceedMission'}) do
    _G[name] = function(...) Record(name, ...) end
end
local function Reset()
    now, nextHandle, objects, calls = 0, 100, {}, {}
    for _, h in ipairs({'user', 'recycler', 'apc', 'portal'}) do objects[h] = 1 end
    for i = 1, 6 do objects['enemy_' .. i] = 1 end
    nearest, distance, timer, done = nil, 30, 90, {}
    dofile('Scripts/bdmisn11.lua'); Start()
end
local function Tick(t) now = t; Update(0.1) end
local function ExpectLoss(file)
    assert(Count('FailMission', now + 1) == 1)
    assert(calls[#calls][1] == 'FailMission' or Save().lost)
    for _, c in ipairs(calls) do
        if c[1] == 'FailMission' then assert(c[3] == file) end
    end
end
Reset(); Tick(0)
assert(Save().pilotTransferring and Count('BuildObject', 'aspilo') == 1)
assert(Count('SetScrap') == 1 and Count('SetPilot') == 1)
local saved = Save(); Load(saved); Tick(0.1)
assert(Count('BuildObject', 'aspilo') == 1 and Count('SetScrap') == 1)
distance = 10; Tick(1)
assert(Save().objective1Complete and Count('SetPilotClass') == 1)
assert(Save().recyclerGoTime == 3)
Tick(3); assert(Count('Goto') == 0) -- strict native < timer
Tick(3.1); assert(Count('Goto') == 1 and Save().drive1Time == 23.1)
-- Trigger began at zero; verify six compositions, escorts and disjoint slots.
local waveTimes = {120, 300, 540, 840, 1080, 1260}
local attackers, defenders = {2,2,4,3,3,9}, {4,5,5,7,9,12}
for wave = 1, 6 do
    local before = Count('SetCloaked')
    Tick(waveTimes[wave] + 0.1)
    assert(Count('SetCloaked') - before == attackers[wave] + defenders[wave])
    local built = Count('BuildObject'); local escorts = Count('Defend2')
    local state = Save(); Load(state); Tick(waveTimes[wave] + 0.2)
    assert(Count('BuildObject') == built and Count('Defend2') == escorts)
end
assert(Count('SetCloaked') == 65 and Count('Defend2') == 42)
for i = 0, 70 do assert(Save().enemy[i] ~= nil, 'missing enemy slot '..i) end
-- Both aerial waves; preserve unusual source path/point rather than guessing.
Reset(); distance = 100; Tick(0); Tick(480.1)
assert(Count('BuildObject', 'cssold') == 8)
Tick(780.1); assert(Count('BuildObject', 'cssold') == 16)
for _, c in ipairs(calls) do
    if c[1] == 'BuildObject' and c[2] == 'cssold' then
        assert(c[4] == 'aerial_1' and c[5] == 400)
    end
end
-- Native health warning ordering is deliberately retained.
Reset(); distance = 100; Tick(0); Save().objective1Complete = true
objects.recycler = 0.3; Tick(1)
objects.recycler = 0.2; Tick(2)
objects.recycler = 0.1; Tick(3)
assert(Count('AudioMessage','bd11004.wav') == 1)
assert(Count('AudioMessage','bd11005.wav') == 1)
assert(Count('AudioMessage','bd11006.wav') == 1)
-- All five loss descriptions and transfer-pilot invalid/dead guard.
Reset(); objects.recycler = 0; Tick(0); ExpectLoss('bd11lsed.des')
Reset(); Save().navDistanceOk = true; objects.recycler = 0; Tick(0); ExpectLoss('bd11lseb.des')
Reset(); objects.apc = 0; Tick(0); ExpectLoss('bd11lsea.des')
Reset(); Tick(0); objects[Save().pilot] = 0; Tick(1); ExpectLoss('bd11lsec.des')
Reset(); Tick(0); objects[Save().pilot] = nil; Tick(1); ExpectLoss('bd11lsec.des')
Reset(); distance = 100; objects.portal = 0; Tick(0); ExpectLoss('bd11lsee.des')
-- Entire audio chain/countdown/camera/explosion/win sequence.
Reset(); distance = 100; Tick(0); Tick(1560.1)
assert(Save().objective2Complete)
Tick(1563.2); done['bd11008.wav'] = true; Tick(1563.3)
Tick(1568.4); done['bd11010.wav'] = true; Tick(1568.5)
Tick(1573.6); done['bd11012.wav'] = true; Tick(1573.7)
assert(Count('StartCockpitTimer') == 1)
timer = 0; Tick(1663.7); assert(Save().navDistanceOk)
for _, t in ipairs({1663.8,1665.8,1667.8,1669.8}) do Tick(t) end
assert(Count('MakeExplosion','xpltrsk') == 4)
Tick(1680.8); Tick(1681.8)
assert(Save().explodePortal and Count('MakeExplosion','xpltrso') == 1)
objects.portal = 0; Tick(1684.9)
assert(Count('FailMission') == 0)
done['bd11011.wav'] = true; Tick(1685)
assert(Save().won and Count('SucceedMission') == 1)
Tick(1686); assert(Count('SucceedMission') == 1)
print('BlackDog11: Lua 5.1 regression tests passed')
