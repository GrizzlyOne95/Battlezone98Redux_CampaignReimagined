-- Lifecycle/guard contract only: native boarding still requires an in-game test.
local net, player, built = false, 1, 2
local calls = {}
function IsNetGame() return net end
function GetPlayerHandle() return player end
function IsValid(h) return h == 1 or h == 2 end
function GetPosition(h) assert(h == 1); return {x=100,y=5,z=200} end
function GetTeamNum(h) assert(h == 1); return 1 end
function SetVector(x,y,z) return {x=x,y=y,z=z} end
function BuildObject(odf,team,where)
    assert(odf == 'avpsav' and team == 1 and where.x == 120 and where.y == 5 and where.z == 200)
    calls[#calls+1] = 'build'
    return built
end
function RemovePilot(h) assert(h == 2); calls[#calls+1] = 'empty' end
function SetObjectiveName(h,name) assert(h == 2 and name == 'Boardable Fury Test'); calls[#calls+1] = 'name' end
function SetObjectiveOn(h) assert(h == 2); calls[#calls+1] = 'mark' end
local fixture = dofile('Scripts/CRSAVTest.lua')
net = true
assert(fixture.Spawn() == nil and #calls == 0)
net, player = false, nil
assert(fixture.Spawn() == nil and #calls == 0)
player = 1
assert(fixture.Spawn() == 2 and table.concat(calls, ',') == 'build,empty,name,mark')
built, calls = nil, {}
assert(fixture.Spawn() == nil and table.concat(calls, ',') == 'build')
print('SAV prototype guards and empty-spawn lifecycle passed; no forced player transfer.')
