-- Fixture contract only; native movement, boarding and abandon need game tests.
local net, player, built = false, 1, 2
local onFoot, commandable, targetTeam = true, true, 1
local odf, classLabel = 'avrsav.odf', 'sav'
local calls, expectedOdf, expectedX, expectedName = {}, 'avpsav', 120, 'Boardable Fury Test'
AiCommand = {RESCUE = 'native-rescue'} -- Mock sentinel, not an engine enum value.
function IsNetGame() return net end
function GetPlayerHandle() return player end
function IsValid(h) return h == 1 or h == 2 end
function IsPerson(h) assert(h == 1); return onFoot end
function GetPosition(h) assert(h == 1); return {x=100,y=5,z=200} end
function GetTeamNum(h) assert(h == 1 or h == 2); return h == 1 and 1 or targetTeam end
function GetOdf(h) assert(h == 2); return odf end
function GetClassLabel(h) assert(h == 2); return classLabel end
function CanCommand(h) assert(h == 2); return commandable end
function SetVector(x,y,z) return {x=x,y=y,z=z} end
function BuildObject(odf,team,where)
    assert(odf == expectedOdf and team == 1 and where.x == expectedX and where.y == 5 and where.z == 200)
    calls[#calls+1] = 'build'
    return built
end
function RemovePilot(h) assert(h == 2); calls[#calls+1] = 'empty' end
function SetObjectiveName(h,name) assert(h == 2 and name == expectedName); calls[#calls+1] = 'name' end
function SetObjectiveOn(h) assert(h == 2); calls[#calls+1] = 'mark' end
function SetCommand(h,cmd,priority,who)
    assert(h == 2 and cmd == AiCommand.RESCUE and priority == 0 and who == 1)
    calls[#calls+1] = 'rescue'
end
local fixture = dofile('Scripts/CRSAVTest.lua')
net = true
assert(fixture.Spawn() == nil and fixture.SpawnPickup() == nil and fixture.RequestPickup(2) == nil and #calls == 0)
net, player = false, nil
assert(fixture.Spawn() == nil and fixture.SpawnPickup() == nil and fixture.RequestPickup(2) == nil and #calls == 0)
player = 1
assert(fixture.Spawn() == 2 and table.concat(calls, ',') == 'build,empty,name,mark')
built, calls = nil, {}
assert(fixture.Spawn() == nil and table.concat(calls, ',') == 'build')
expectedOdf, expectedX, expectedName = 'avrsav', 180, 'Fury Pickup Test'
calls = {}
assert(fixture.SpawnPickup() == nil and table.concat(calls, ',') == 'build')
built, calls = 2, {}
assert(fixture.SpawnPickup() == 2 and table.concat(calls, ',') == 'build,name,mark')
calls = {}
assert(fixture.RequestPickup(nil) == nil and fixture.RequestPickup(99) == nil)
onFoot = false
assert(fixture.RequestPickup(2) == nil)
onFoot, targetTeam = true, 2
assert(fixture.RequestPickup(2) == nil)
targetTeam, odf = 1, 'avpsav'
assert(fixture.RequestPickup(2) == nil)
odf, classLabel = 'avrsav', 'wingman'
assert(fixture.RequestPickup(2) == nil)
classLabel, commandable = 'sav', false
assert(fixture.RequestPickup(2) == nil)
commandable, AiCommand = true, nil
assert(fixture.RequestPickup(2) == nil and #calls == 0)
AiCommand, odf = {RESCUE = 'native-rescue'}, 'AVRSAV.ODF'
assert(fixture.RequestPickup(2) == true and table.concat(calls, ',') == 'rescue')
print('SAV prototype guards, empty/occupied lifecycle and player-priority native rescue contract passed; no forced player transfer.')
