-- Run from repository root: lua5.1 Tools/Test-BlackDog09.lua
local checks = 0
local function check(ok, why)
    checks = checks + 1
    assert(ok, why)
end
local now, player, objects, distances, done, events, touching
local function record(kind, ...)
    events[#events + 1] = {kind, ...}
end
local function count(kind, value)
    local n = 0
    for _, e in ipairs(events) do
        if e[1] == kind and (value == nil or e[2] == value) then n = n + 1 end
    end
    return n
end
local function object(h, odf)
    objects[h] = {odf = odf, health = 1}
    return h
end
function GetTime() return now end
function GetPlayerHandle() return player end
function GetHandle(label) return objects[label] and label end
function IsValid(h) return objects[h] ~= nil end
function IsAlive(h) return IsValid(h) and objects[h].health > 0 end
function IsOdf(h, odf) assert(IsValid(h)); return objects[h].odf == odf end
function GetHealth(h) assert(IsValid(h)); return objects[h].health end
function GetDistance(a, b)
    assert(IsValid(a), 'invalid distance origin')
    return distances[a .. ':' .. b] or distances[b .. ':' .. a] or 1000
end
function SetScrap(...) record('scrap', ...) end
function SetPilot(...) record('pilot', ...) end
function SetPerceivedTeam(...) record('team', ...) end
function ClearObjectives() record('clear') end
function AddObjective(...) record('objective', ...) end
function SetObjectiveOn(h) assert(IsValid(h)); record('on', h) end
function SetObjectiveOff(h) assert(IsValid(h)); record('off', h) end
function AudioMessage(name) record('audio', name); return name end
function IsAudioMessageDone(msg) return done[msg] == true end
function BuildObject(odf, team, path)
    record('build', odf, team, path)
    return object(path .. '#' .. count('build'), odf)
end
function Attack(h, who) assert(IsValid(h) and IsValid(who)); record('attack', h, who) end
function Goto(h, path, priority) record('move', h, path, priority) end
function AllObjects() return next, objects, nil end
function ActivatePortal(h) record('activate', h) end
function IsTouching(a, b) assert(IsValid(a) and IsValid(b)); return touching end
function SucceedMission(...) record('win', ...) end
function FailMission(...) record('lose', ...) end
local function fresh(odf)
    now, player, objects, distances, done, events, touching = 0, 'player', {}, {}, {}, {}, false
    object('player', odf or 'cvapc')
    object('portal', 'portal')
    for i = 1, 5 do object('cvtnk' .. i, 'cvtnkb') end
    object('turret', 'cvturrc')
    object('other', 'avturr')
    dofile('Scripts/bdmisn09.lua')
    Start()
    Update(0.1)
end
local function tick(t) now = t; Update(0.1) end
local function near(a, b, d) distances[a .. ':' .. b] = d end
local function infiltrate()
    tick(1.01)
    done['bd09001.wav'] = true
    tick(2)
    tick(17.01)
    player = 'cvtnk1'
    near(player, 'cvtnk2', 50)
    tick(18)
end

fresh()
check(count('scrap') == 1 and count('pilot') == 1, 'initial resources')
check(count('build') == 0, 'absent beacons cannot advance')
tick(1)
check(count('audio') == 0, 'strict initial deadline')
infiltrate()
check(Save().objective1Complete and not Save().oneOfTheEnemy, 'capture tracked tank')
check(count('audio', 'bd09002.wav') == 1, 'APC briefing')
check(count('build', 'apcamr') == 1, 'first beacon')
tick(23)
check(count('audio', 'bd09003.wav') == 0, 'strict capture briefing deadline')
tick(23.01)
done['bd09003.wav'] = true
tick(24)
tick(25)
check(count('move') == 0, 'strict convoy deadline')
tick(25.01)
check(count('move') == 4, 'four convoy followers')
for _, e in ipairs(events) do
    if e[1] == 'move' then check(e[3] == 'tank_path' and e[4] == 1, 'native convoy orders') end
end
near(player, Save().beacon1, 99)
tick(26)
check(Save().tankArrived1 and Save().gotoBeacon2, 'first rendezvous')
near(player, Save().beacon2, 99)
tick(27)
check(Save().tankArrived2 and Save().gotoBeacon3, 'second rendezvous')
near(player, Save().beacon3, 99)
tick(28)
check(Save().objective2Complete and count('objective', 'bd09003.otf') == 1, 'third rendezvous')
tick(32)
check(count('audio', 'bd09006.wav') == 0, 'strict portal instruction deadline')
local saved = Save()
Load(saved)
tick(32.01)
check(count('audio', 'bd09006.wav') == 1 and count('build', 'apcamr') == 3, 'restore scheduled audio without spawning again')
near(player, 'portal', 250)
tick(33)
check(count('activate') == 0, 'strict portal range')
near(player, 'portal', 249)
tick(34)
check(count('activate') == 1 and count('audio', 'bd09008.wav') == 1, 'activate once')
touching = true
objects.portal.health = 0
tick(35)
check(count('win') == 1 and count('lose') == 0, 'native victory before portal loss')
tick(36)
check(count('win') == 1, 'victory latched')

fresh('avtank')
check(Save().deviateTime == 1, 'exposure arms once')
tick(0.5)
check(Save().deviateTime == 1, 'continuous exposure does not postpone')
tick(1)
check(count('build') == 0, 'strict ambush deadline')
tick(1.01)
check(count('build') == 11 and Save().deviateSpawned, 'eleven attackers')
check(count('attack', 'turret') == 1 and count('attack', 'other') == 0, 'all-object turret sweep')
check(count('build', 'cvfigh') == 4 and count('build', 'cvltnk') == 2 and
      count('build', 'cvhtnk') == 1 and count('build', 'cvrckt') == 2 and
      count('build', 'cvtnk') == 2, 'ambush manifest')
tick(2)
check(count('build') == 11 and count('audio', 'bd09007.wav') == 1, 'ambush one-shot')
near(player, 'trigger_1', 200)
tick(3)
check(not Save().trigger1, 'strict final ambush range')
near(player, 'trigger_1', 199)
tick(4)
tick(5)
check(count('build', 'cvtnk') == 7 and Save().trigger1, 'five final tanks once')

fresh()
infiltrate()
near(player, 'cvtnk2', 76)
tick(20)
check(Save().strayed and Save().deviateTime == 22, 'straying arms two-second ambush')
tick(22)
check(count('build', 'cvfigh') == 0, 'strict straying deadline')
tick(22.01)
check(count('build', 'cvfigh') == 4, 'straying ambush fires')

fresh()
infiltrate()
player = 'player'
near(player, 'cvtnk2', 50)
tick(20)
check(Save().tankTimeout == 620, 'leave tank arms ten minutes')
player = 'cvtnk1'
tick(21)
check(Save().tankTimeout == -1, 'return cancels timer')
player = 'player'
tick(22)
check(Save().tankTimeout == 622, 'second departure gets full timeout')
local state = Save()
Load(state)
tick(622)
check(count('lose') == 0, 'strict timeout deadline')
touching = true
tick(622.01)
check(Save().lost and count('lose') == 1 and count('win') == 0, 'timeout cannot be replaced by victory')
tick(623)
check(count('lose') == 1, 'failure latched')

fresh()
objects.cvtnk1.odf = 'cvtnk'
infiltrate()
check(Save().tankTimeout == 618, 'timeout arms without prior cvtnkb reset')

fresh()
objects.portal = nil
tick(1)
check(Save().lost and count('lose') == 1, 'deleted portal fails safely')
fresh()
touching = true
tick(1)
check(count('win') == 1 and not Save().objective1Complete, 'no invented victory prerequisite')
print('BlackDog09: ' .. checks .. ' behavior checks passed (Lua ' .. _VERSION .. ').')
