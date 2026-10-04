-- Run from the repository root with Lua 5.1: lua Tools/Test-Tran02Mission.lua
-- Deterministic engine mocks; actual menu/input and AI behavior need BZR QA.
local time, objects, audio, results, moves
AiCommand = { NONE = 0, GO = 3 }
local function reset()
    time, objects, audio, results, moves = 0, {}, {}, {}, {}
    for _, label in ipairs({"avturr-1_turrettank", "nparr-1_i76building", "avhaul-1_tug", "avhaul19_tug"}) do
        objects[label] = { alive = true, valid = true, selected = false,
            command = AiCommand.NONE, pos = {x = 0, y = 0, z = 0} }
    end
    objects["nparr-1_i76building"].pos.x = 200
end
GetHandle = function(label) return objects[label] end
IsAlive = function(h) return h ~= nil and h.valid and h.alive end
IsValid = function(h) return h ~= nil and h.valid end
IsSelected = function(h) return h.selected end
GetTime = function() return time end
GetPosition = function(h) assert(IsValid(h)); return h.pos end
GetCurrentCommand = function(h) return h.command end
Distance3DSquared = function(a,b)
    return (a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2
end
AudioMessage = function(name) audio[#audio+1] = name end
SetObjectiveOn = function(h) assert(IsValid(h)); h.objective = true end
SetObjectiveOff = function(h) assert(IsValid(h)); h.objective = false end
SetObjectiveName = function(h, name) assert(IsValid(h)); h.name = name end
ClearObjectives = function() end
AddObjective = function(name, color) assert(name == "tran0201.otf" and color == "green") end
Goto = function(h, pos, priority)
    assert(IsAlive(h) and priority == 1)
    moves[#moves+1] = { h=h, pos={x=pos.x,y=pos.y,z=pos.z} }
    h.command = AiCommand.GO
end
FailMission = function(t, name) results[#results+1] = {kind="fail",t=t,name=name} end
SucceedMission = function(t, name) results[#results+1] = {kind="win",t=t,name=name} end
local function pack(...) return {n=select("#", ...), ...} end
local function reload() local saved=pack(Save()); Load(unpack(saved,1,saved.n)) end
local function tick(t) time=t; Update(0.1) end
local function last() return audio[#audio] end
local function begin()
    reset(); dofile("Scripts/Tran02Mission.lua"); Start(); tick(0)
    assert(last()=="tran0201.wav")
    tick(1); assert(last()=="tran0201.wav") -- strict >, not >=
    tick(1.1); assert(last()=="tran0204.wav")
end
local function selectAndTravel()
    local turret=objects["avturr-1_turrettank"]
    GameKey("2"); tick(2); assert(last()=="tran0205.wav")
    turret.selected=true; tick(3); assert(last()=="tran0206.wav")
    turret.selected=false; tick(4); assert(last()=="misn0109.wav")
    turret.pos.x=100; tick(5); assert(last()=="misn0109.wav") -- exactly 100m
    turret.pos.x=101; tick(6); assert(last()=="tran0212.wav")
    tick(7); assert(last()=="tran0212.wav") -- earlier "2" is not latched
    GameKey("2"); tick(8); assert(last()=="tran0211.wav")
    turret.selected=true; tick(9); assert(last()=="tran0208.wav")
    return turret
end
begin()
local turret=selectAndTravel()
reload(); turret.command=AiCommand.GO; tick(10)
assert(last()=="tran0209.wav" and #moves==1 and #results==0)
assert(moves[1].pos.x==101)
turret.pos.x=500; objects["avhaul-1_tug"].command=AiCommand.NONE; tick(11)
assert(#moves==1) -- unfinished C++ idle block intentionally stays a no-op
objects["avhaul-1_tug"].alive=false; tick(12); assert(#results==0)
reload(); objects["avhaul-1_tug"].valid=false; tick(13)
assert(last()=="tran0210.wav" and #results==1 and results[1].kind=="win" and results[1].t==23)
tick(14); assert(#results==1)

begin(); turret=selectAndTravel()
objects["avhaul-1_tug"].valid=false; turret.command=AiCommand.GO; tick(10)
assert(#results==1 and results[1].kind=="fail" and results[1].t==12)
reload(); tick(11); assert(#results==1) -- no competing success or repeated failure

begin(); objects["avturr-1_turrettank"].alive=false; tick(2)
assert(#results==1 and results[1].t==7); reload(); tick(3); assert(#results==1)

reset(); objects["nparr-1_i76building"]=nil; objects["avhaul19_tug"]=nil
dofile("Scripts/Tran02Mission.lua"); Start(); tick(0); tick(2)
objects["avturr-1_turrettank"].selected=true; tick(3); reload(); tick(4)
assert(#results==0) -- nil handles survive flat Save/Load; no marker crash

begin(); tick(31.1); assert(last()=="tran0204.wav") -- no reminder at equality
local count=#audio; tick(31.2); assert(#audio==count+1 and last()=="tran0204.wav")
tick(46.2); assert(#audio==count+1); tick(46.3); assert(#audio==count+2)
print("Tran02Mission: Lua 5.1 mocked progression, timing, save/load and failure tests passed")
