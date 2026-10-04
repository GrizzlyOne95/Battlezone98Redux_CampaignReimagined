-- Run from repository root: lua5.1 Tools/Test-DemoMission.lua
-- Tests decisions through stock-API stubs; not native AI/rendering/remapping.
local now, objects, labels, events, nextHandle, distance, failSpawn
local function event(kind, ...) events[#events + 1] = {kind, ...} end
local function add(team, label)
    nextHandle = nextHandle + 1
    objects[nextHandle] = {team = team, valid = true, alive = true}
    if label then labels[label] = nextHandle end
    return nextHandle
end
function IsValid(h) return objects[h] ~= nil and objects[h].valid end
function IsAlive(h) assert(IsValid(h)); return objects[h].alive end
function GetTime() return now end
function GetHandle(label) return labels[label] end
function GetPlayerHandle() return labels.user end
function GetTeamNum(h) assert(IsValid(h)); return objects[h].team end
function SetTeamNum(h, team) assert(IsValid(h)); objects[h].team = team end
function BuildObject(odf, team, path)
    event("spawn", odf, team, path)
    if failSpawn then return nil end
    local h = add(team)
    objects[h].odf, objects[h].path = odf, path
    return h
end
function AllObjects()
    local snapshot = {}
    for h, o in pairs(objects) do if o.valid then snapshot[#snapshot + 1] = h end end
    local i = 0
    return function() i = i + 1; return snapshot[i] end
end
function RemoveObject(h) assert(IsValid(h)); objects[h].valid = false; event("remove", h) end
local function order(kind, h, target)
    assert(IsValid(h) and (type(target) == "string" or IsValid(target)))
    event(kind, h, target)
end
function Goto(h, target) order("go", h, target) end
function Follow(h, target) order("follow", h, target) end
function Attack(h, target) order("attack", h, target) end
function GetDistance(a, b) assert(IsValid(a) and IsValid(b)); return distance end
function CameraReady() event("ready"); return true end
function CameraFinish() event("finish"); return true end
function CameraObject(a, x, y, z, b)
    assert(IsValid(a) and IsValid(b)); event("camera", a, x, y, z, b)
end
function CameraPath(path, height, speed, h)
    assert(IsValid(h)); event("path", path, height, speed, h)
end
function Damage(h, amount) assert(IsValid(h)); event("damage", h, amount) end
function DisplayMessage(text) event("message", text) end
function SucceedMission(at, file) event("success", at, file) end
local function count(kind)
    local n = 0
    for _, e in ipairs(events) do if e[1] == kind then n = n + 1 end end
    return n
end
local function reset()
    now, objects, labels, events, nextHandle, distance, failSpawn = 0, {}, {}, {}, 0, 500, false
    add(1, "user")
    for seq = 5, 8 do add(0, "demo_keep_" .. seq) end
    dofile("Scripts/demo01.lua")
    Start()
end
reset()
Update(0.1)
local m = Save()
assert(count("spawn") == 15 and count("go") == 5 and count("follow") == 1)
assert(m.angle == 0 and count("camera") == 0 and count("ready") == 1)
assert(objects[m.foe3].path == "foe2" and objects[m.foe4].path == "foe2")
now = 7; Update(0.1); assert(m.angle == 0, "strict camera > threshold")
now = 7.1; Update(0.1); assert(m.angle == 1)
-- Immediate transition runs camera2 on the same frame.
distance = 199
Update(0.1)
assert(m.camera2 and not m.camera1 and count("attack") == 1 and count("damage") == 1)
assert(count("camera") >= 2)
-- Death of foe1 switches the camera subject to foe2.
objects[m.foe1].alive = false
Update(0.1)
local last = events[#events]
assert(last[1] == "camera" and last[6] == m.foe2)
-- Save/load must retain handles, angle, timer, counters and exemptions.
local saved = {}
for k, v in pairs(m) do saved[k] = v end
Start(); Load(saved); assert(Save() == saved)
assert(Save().target == m.target and Save().camera_time == m.camera_time)
local neutral = add(0)
local team3 = add(3)
local scrap = add(0); objects[scrap].alive = false
now = 55; Update(0.1); assert(Save().cycle_count == 0, "strict cycle > threshold")
now = 55.01; Update(0.1)
assert(Save().cycle_count == 1 and not Save().start_done)
assert(not IsValid(neutral) and not IsValid(scrap), "cleanup includes noncraft")
assert(IsValid(team3) and IsValid(labels.user))
for seq = 5, 8 do assert(IsValid(labels["demo_keep_" .. seq])) end
assert(not IsValid(m.target) and not IsValid(m.friend1))
-- Five cycles, four cleanups, one terminal report; camera setup occurs once.
reset()
for cycle = 1, 5 do
    Update(0.1)
    local s = Save()
    now = s.cycle_time + 55.01
    Update(0.1)
    assert(Save().cycle_count == cycle)
end
assert(count("spawn") == 75 and count("ready") == 1)
assert(count("success") == 1 and count("finish") == 1)
assert(Save().lost and Save().total_time > 275 and Save().average_update_rate > 0)
local frames = Save().frame_count
Update(0.1); assert(Save().frame_count == frames and count("success") == 1)
-- Destroyed subject skips invalid camera calls and restarts immediately.
reset(); Update(0.1)
objects[Save().target].valid = false
Update(0.1); assert(Save().cycle_count == 1 and not Save().start_done)
-- Failed spawns complete five empty cycles without invalid commands or 0/0.
reset(); failSpawn = true
for i = 1, 5 do Update(0.1) end
assert(Save().lost and Save().average_update_rate == 0 and count("success") == 1)
assert(count("go") == 0 and count("camera") == 0)
-- Missing keep labels are reported rather than guessed from iterator order.
reset(); labels.demo_keep_5 = nil
Start(); assert(count("message") == 1)
print("DemoMission: Lua 5.1 flow checks passed")
