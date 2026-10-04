-- Run with Lua 5.1 from the repository root: lua5.1 Tests/test_bdmisn14.lua
-- Stock API mocks validate event flow; they cannot establish engine AI/path behavior.
local script = 'Scripts/bdmisn14.lua'
local now, objects, events, nextHandle, done, distance, pathCount, player

local function Record(kind, ...)
    events[#events + 1] = { kind, ... }
end

local function ValidObject(h)
    assert(h ~= nil and objects[h] and objects[h].valid, 'invalid handle query')
    return objects[h]
end

function GetHandle(label) return label end
function GetPlayerHandle() return player end
function GetTime() return now end
function IsValid(h) return objects[h] ~= nil and objects[h].valid end
function GetHealth(h) return ValidObject(h).health end
function GetPathPointCount(path)
    assert(path == 'path_apc_travel')
    return pathCount
end
function GetDistance(h, path, point)
    ValidObject(h)
    if path == 'path_apc_travel' then
        assert(point == pathCount - 1, 'must query the last zero-based waypoint')
    end
    return distance[path] or 1000
end
function BuildObject(odf, team, path)
    nextHandle = nextHandle + 1
    local h = nextHandle
    objects[h] = { valid = true, health = 1, odf = odf, team = team, path = path }
    Record('build', odf, team, path, h)
    return h
end
function SetCloaked(h) ValidObject(h).cloaked = true; Record('cloak', h) end
function Goto(h, path) ValidObject(h).route = path; Record('route', h, path) end
function Defend2(h, target) ValidObject(h).defend = target; Record('defend', h, target) end
function Follow(h, target) ValidObject(h).follow = target; Record('follow', h, target) end
function SetObjectiveOn(h) ValidObject(h).marked = true; Record('mark', h) end
function SetObjectiveOff(h) ValidObject(h).marked = false; Record('unmark', h) end
function AudioMessage(name) Record('audio', name); return name end
function IsAudioMessageDone(msg) return done[msg] == true end
function ClearObjectives() Record('clear') end
function AddObjective(name, color) Record('objective', name, color) end
function SetAIP(name) Record('aip', name) end
function SetScrap(team, amount) Record('scrap', team, amount) end
function SetPilot(team, amount) Record('pilot', team, amount) end
function SucceedMission(t, name) Record('win', t, name) end
function FailMission(t, name) Record('lose', t, name) end

local function Count(kind, value)
    local n = 0
    for _, e in ipairs(events) do
        if e[1] == kind and (value == nil or e[2] == value) then n = n + 1 end
    end
    return n
end

local function Reset()
    now, nextHandle, pathCount = 0, 0, 4
    objects, events, done, distance = {}, {}, {}, {}
    player = 'player'
    for _, label in ipairs({ 'player', 'recycler', 'chin_recycler',
        'start1_1', 'start1_2', 'start1_3', 'start2_1', 'start2_2', 'start2_3' }) do
        objects[label] = { valid = true, health = 1 }
    end
    dofile(script)
    Start()
end

local function Tick(t) now = t; Update(0.1) end
local function Copy(v)
    if type(v) ~= 'table' then return v end
    local copy = {}
    for k, item in pairs(v) do copy[k] = Copy(item) end
    return copy
end

local function Restore()
    local state = Copy(Save())
    dofile(script)
    Load(state)
end

local function SpawnAPC()
    Tick(0); Tick(0.1); Tick(240.2); Tick(540.3)
    return Save().apc
end

-- Startup, strict timer boundaries, exact wave counts, cut content, and escort targets.
Reset()
Tick(0)
assert(Count('build') == 0 and Count('cloak') == 6)
assert(Count('aip', 'bdmisn14.aip') == 1)
Tick(0)
assert(Count('build') == 0 and Count('audio', 'bd14001.wav') == 1)
Tick(0.1)
assert(Count('build') == 5 and Count('build', 'cvfigh') == 3 and Count('build', 'cvhraz') == 2)
assert(Save().sound2Time == 120.1 and Save().wavesTime == 240.1)
Tick(120.1)
assert(Count('audio', 'bd14002.wav') == 0)
Tick(120.2)
assert(Count('audio', 'bd14002.wav') == 1)
Tick(240.1)
assert(Count('build') == 5)
Tick(240.2)
assert(Count('build') == 14 and Count('build', 'cvhtnk') == 2)
assert(Count('build', 'cvltnk') == 3 and Save().sound3Time == 540.2)
Tick(540.2)
assert(Count('build') == 14)
Tick(540.3)
assert(Count('build') == 33 and Count('build', 'cvtnk') == 4)
assert(Count('build', 'cvwalk') == 3 and Count('build', 'cvtnkc') == 3)
assert(Count('build', 'cvturr') == 0)
local apc = Save().apc
for _, o in pairs(objects) do
    if o.odf == 'cvtnk' then assert(o.defend == apc) end
    if o.odf == 'cvwalk' then assert(o.cloaked and o.route == 'path_attack_waves') end
    if o.odf == 'cvtnkc' then assert(objects[o.follow].odf == 'cvwalk') end
end
Tick(590.3)
assert(Count('audio', 'bd14004.wav') == 0)
Restore()
Tick(590.4)
assert(Count('audio', 'bd14004.wav') == 1 and Count('build') == 33)
assert(Count('aip') == 1 and Count('scrap') == 2 and Count('pilot') == 2)

-- Intercept a deleted APC at the destination; no stale-wreck loss, delayed scavengers.
objects[apc].valid = false
distance.path_apc_travel = 0
Tick(600)
assert(Save().objective2Complete and not Save().wonLost)
assert(Count('audio', 'bd14005.wav') == 1 and Count('audio', 'bd14007.wav') == 0)
Tick(840)
assert(Count('build', 'cvscav') == 0)
Restore()
Tick(840.1); Tick(841)
assert(Count('build', 'cvscav') == 2 and Count('audio', 'bd14005.wav') == 1)

-- Living APC arrival and deferred loss survive save/load, with an explicit 25 m boundary.
Reset(); apc = SpawnAPC()
distance.path_apc_travel = 25
Tick(550)
assert(not Save().wonLost)
pathCount = 0
Tick(551)
assert(not Save().wonLost)
pathCount = 4
distance.path_apc_travel = 24.9
Tick(552)
assert(Save().wonLost and Count('lose') == 0)
Restore()
done['bd14007.wav'] = true
Tick(553); Tick(554)
assert(Count('lose') == 1 and events[#events][3] == 'bd14lsea.des')

-- Source win precedence when enemy recycler death coincides with APC arrival/player loss.
Reset(); apc = SpawnAPC()
objects.chin_recycler.health = 0
objects.recycler.health = 0
distance.path_apc_travel = 0
Tick(550)
assert(Save().objective3Complete and Count('audio', 'bd14006.wav') == 1)
assert(Count('audio', 'bd14007.wav') == 0 and Count('audio', 'bd14008.wav') == 0)
Restore()
done['bd14006.wav'] = true
Tick(551); Tick(552)
assert(Count('win') == 1 and Count('lose') == 0 and events[#events][3] == 'bd14win.des')

-- Player recycler loss uses its own debrief and waits for narration completion.
Reset(); Tick(0)
objects.recycler.valid = false
Tick(0.1)
assert(Save().wonLost and Count('lose') == 0)
Restore()
done['bd14008.wav'] = true
Tick(1); Tick(2)
assert(Count('lose') == 1 and events[#events][3] == 'bd14lseb.des')

-- Proximity ambushes are strict, one-shot, and safe without a controlled player object.
Reset(); Tick(0)
player = nil
distance.trigger_attack_1 = 0
distance.trigger_attack_2 = 0
Tick(0.1)
assert(not Save().attack1 and not Save().attack2)
player = 'player'
distance.trigger_attack_1 = 150
distance.trigger_attack_2 = 150
Tick(1)
assert(not Save().attack1 and not Save().attack2)
distance.trigger_attack_1 = 149.9
distance.trigger_attack_2 = 149.9
Tick(2)
assert(Save().attack1 and Save().attack2 and Count('build') == 26)
assert(Count('build', 'cvwalk') == 2 and Count('build', 'cvltnk') == 9)
Restore(); Tick(3)
assert(Count('build') == 26)
print('BlackDog14: Lua 5.1 event-flow tests passed')
