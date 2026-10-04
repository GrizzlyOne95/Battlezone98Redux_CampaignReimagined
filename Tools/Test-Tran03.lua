-- Run from repository root with Lua 5.1: lua Tools/Test-Tran03.lua
local objects, calls, now, scrap, selected, deployed, distance
local function Record(name, ...)
    calls[#calls + 1] = {name, ...}
end
local function Count(name, value)
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == name and (value == nil or c[2] == value) then n = n + 1 end
    end
    return n
end
local function Existing(h)
    assert(objects[h] and objects[h].alive, "invalid object query/command")
end
function IsValid(h) return objects[h] ~= nil and objects[h].alive end
IsAlive = IsValid
function GetTeamNum(h) Existing(h); return objects[h].team end
function IsOdf(h, odf) Existing(h); return objects[h].odf == odf end
function IsSelected(h) Existing(h); return selected end
function IsDeployed(h) Existing(h); return deployed end
function GetPosition(h) Existing(h); return h end
function Distance3DSquared(a, b) Existing(a); Existing(b); return distance * distance end
function GetHandle(label)
    return ({eggeizr111_geyser = "geyser", ["avrecy-1_recycler"] = "recycler",
        ["svfigh-1_wingman"] = "attacker"})[label]
end
function GetTime() return now end
function GetScrap(team) assert(team == 1); return scrap end
function SetScrap(team, amount) assert(team == 1); scrap = amount end
function SetObjectiveOn(h) Existing(h); Record("on", h) end
function SetObjectiveOff(h) Existing(h); Record("off", h) end
function SetObjectiveName(h, name) Existing(h); Record("name", h, name) end
function AddHealth(h, amount) Existing(h); Record("health", h, amount) end
function Attack(h, target, priority)
    Existing(h); Existing(target); Record("attack", h, target, priority)
end
function ClearObjectives() Record("clear") end
function AddObjective(...) Record("objective", ...) end
function AudioMessage(...) Record("audio", ...) end
function FailMission(...) Record("fail", ...) end
function SucceedMission(...) Record("win", ...) end

local function Reset()
    objects = {recycler = {alive = true}, geyser = {alive = true},
        attacker = {alive = true}, scav = {alive = true, team = 1, odf = "avscav"}}
    calls, now, scrap, selected, deployed, distance = {}, 0, 0, false, true, 250
    dofile("Scripts/tran03.lua")
    Start()
end
local function DeployRecycler()
    Update(0.1)
    assert(scrap == 7 and Count("audio", "tran0301.wav") == 1)
    selected = true
    Update(0.1)
    assert(Save().first_message and not Save().second_message)
    deployed = false
    Update(0.1)
    assert(Save().second_message and not Save().third_message)
    distance = 200
    Update(0.1)
    assert(not Save().third_message)
    distance = 199.9
    Update(0.1)
    assert(Save().third_message and Save().fourth_message)
    deployed = true
    Update(0.1)
    assert(Save().fifth_message and Save().fifthb_message)
end

Reset()
-- Initial-map callbacks must survive Start, as well as ordinary construction.
AddObject("scav")
Start()
assert(Save().found and Save().scav == "scav")
DeployRecycler()
scrap = 5
Update(0.1)
assert(not Save().sixth_message)
scrap, now = 4, 10
Update(0.1)
assert(Save().sixth_message and Save().delay_message == 15)
assert(Count("attack") == 1)
local attack
for _, c in ipairs(calls) do if c[1] == "attack" then attack = c end end
assert(attack[2] == "attacker" and attack[3] == "scav" and attack[4] == 1)
local saved, before = Save(), #calls
Load(saved)
Update(0.1)
assert(#calls == before, "load repeated narration/orders or attacker healing")
now = 16
Update(0.1)
assert(Save().delay_message == 99999 and Count("audio", "tran0311.wav") == 0)
objects.attacker.alive, scrap = false, 1
Update(0.1)
assert(Save().seventh_message and Count("win") == 0)
scrap, now = 2, 20
Update(0.1)
assert(Count("win", 40) == 1 and Count("fail") == 0)
Update(0.1)
assert(Count("win") == 1)

Reset()
DeployRecycler()
AddObject("scav")
scrap = 4
objects.attacker.alive = false -- killed before tutorial orders the attack
Update(0.1)
assert(Count("attack") == 0 and Count("win") == 1)

Reset()
DeployRecycler()
AddObject("scav")
scrap = 4
Update(0.1)
objects.scav.alive, objects.attacker.alive = false, false
Update(0.1)
assert(Count("fail", 10) == 1 and Count("win") == 0)
Update(0.1)
assert(Count("fail") == 1)

Reset()
DeployRecycler()
objects.recycler.alive = false
Update(0.1)
assert(Count("fail") == 1 and Count("win") == 0)

Reset()
objects.geyser = nil
selected, deployed = true, false
Update(0.1)
assert(Save().second_message and not Save().third_message)
print("Tran03: tutorial, thresholds, save/load, early kill and destruction checks passed")
