-- Run from the repository root with Lua 5.1.
local now, objects, labels, calls, distances, serial, deployed
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function record(name, ...)
    calls[#calls + 1] = {name, ...}
end
local function called(name, arg)
    for _, call in ipairs(calls) do
        if call[1] == name and (arg == nil or call[2] == arg) then return true end
    end
    return false
end
function GetHandle(label)
    if not labels[label] then
        serial = serial + 1
        labels[label] = serial
        objects[serial] = {alive = true, health = 1, odf = "avtank"}
    end
    return labels[label]
end
function GetPlayerHandle() return GetHandle("player") end
function GetTime() return now end
function IsValid(h) return objects[h] ~= nil end
function IsAlive(h) return objects[h] ~= nil and objects[h].alive end
function GetHealth(h) return objects[h].health end
function IsOdf(h, odf) return objects[h].odf == odf end
function GetDistance(h, target)
    assert(IsValid(h), "invalid distance origin")
    assert(type(target) == "string" or IsValid(target), "invalid distance target")
    return distances[tostring(h) .. ":" .. tostring(target)] or 10000
end
function CountUnitsNearObject() return 0 end
function IsDeployed() return deployed end
function BuildObject(odf, team, where)
    serial = serial + 1
    objects[serial] = {alive = true, health = 1, odf = odf}
    record("BuildObject", odf, team, where)
    return serial
end
function RemoveObject(h) objects[h] = nil; record("RemoveObject", h) end
function AudioMessage(name) record("AudioMessage", name); return 1 end
for _, name in ipairs({"SetObjectiveOff", "SetObjectiveOn", "SetObjectiveName",
    "SetScrap", "AddScrap", "SetPilot", "SetAIP", "Patrol", "Stop",
    "SetIndependence", "SetPerceivedTeam", "ClearObjectives", "AddObjective",
    "Attack", "Goto", "Retreat", "Follow", "Defend", "EjectPilot",
    "FailMission", "SucceedMission"}) do
    local operation = name
    _G[operation] = function(...) record(operation, ...) end
end
local function reset()
    now, serial, deployed = 0, 0, false
    objects, labels, calls, distances = {}, {}, {}, {}
    dofile("Scripts/misn07.lua")
    Start()
    Update(0.05)
    return Save()
end
local function near(h, target, distance)
    distances[tostring(h) .. ":" .. tostring(target)] = distance
end
local function kill(h) objects[h].alive = false end

local m = reset()
check(m.start_done and m.mine[0] == "m000" and m.mine[110] == "m110", "startup paths")
check(m.count == 111 and m.mine_check == 11, "native zero-based loop state")
check(not called("AudioMessage"), "briefing remains delayed")
now = 9; Update(0.05)
check(not m.opening_vo, "strict timer boundary")
now = 10; Update(0.05)
check(m.opening_vo and called("AudioMessage", "misn0700.wav"), "opening briefing")
near(m.user, m.wingtank2, 100)
now = 26; Update(0.05)
check(m.rendezvous and IsAlive(m.new_tank1) and IsAlive(m.new_tank2), "rendezvous replacements")
check(not IsValid(m.wingtank2), "old rendezvous tank removed")
local saved = Save()
Load(saved)
check(Save() == saved and Save().rendezvous, "save/load preserves mission state")
near(m.user, m.nav1, 50)
now = 37; Update(0.05)
check(m.tower_warning, "tower warning")
Update(0.05)
check(m.jump_cam_spawned and IsAlive(m.rookie), "rookie lookout sequence")
near(m.user, m.rookie, 30)
now = 48; Update(0.05)
now = 59; Update(0.05)
check(m.rookie_found, "rookie approach")
now = 70; Update(0.05)
check(m.rookie_removed and called("EjectPilot", m.rookie), "rookie jump")
check(not called("BuildObject", "proxmine") and not called("BuildObject", "svtnk7"), "cut content remains disabled")

m = reset()
now = 28; near(m.user, "turret1_spot", 60); Update(0.05)
check(m.alarm_on and m.start_evac and not m.alarm_special, "vehicle entrance alarm")
now = 49; Update(0.05)
check(m.unit_spawn and IsAlive(m.pilot1) and IsAlive(m.spawn_turret1), "standard alarm reinforcements")
objects[m.ccacomtower].health = 0.49; Update(0.05)
check(m.forces_enroute, "damaged radar summons patrols")

m = reset()
near(m.user, m.camera_geyser, 100); Update(0.05)
check(m.out_of_car and not m.alarm_on, "quiet infiltration")
objects[m.powrplnt1].health = 0.94; Update(0.05)
check(m.trigger1 and m.alarm_on and m.alarm_special, "pilot damage alarm")
Update(0.05); now = 21; Update(0.05)
check(m.unit_spawn and objects[m.pilot3].odf == "sssold", "special alarm soldiers")

m = reset()
m.out_of_car = true; objects[m.user].odf = "svtank.odf"
objects[m.barrack1].health = 0.94; Update(0.05)
check(m.vehicle_stolen and m.alarm_on and not m.alarm_special, "stolen vehicle alarm")

m = reset()
m.rendezvous = true; kill(m.svpatrol1_1); near(m.user, m.svpatrol1_2, 40)
Update(0.05)
check(m.p1_retreat and m.patrola2, "runner retreats")
near(m.svpatrol1_2, m.ccarecycle, 50); Update(0.05)
check(m.retreat_success, "runner reaches recycler")
kill(m.svpatrol1_2); Update(0.05)
check(objects[m.svpatrol1_1].odf == "svtank", "escape upgrades replacement patrol")

m = reset()
kill(m.ccacomtower); Update(0.05)
check(m.first_objective and not m.next_mission, "radar destruction starts handoff")
now = 7.5; Update(0.05)
check(not m.next_mission, "handoff strict boundary")
now = 8; Update(0.05)
check(m.next_mission and called("SetAIP", "misn07.aip"), "Utah and strategic AI handoff")
check(called("BuildObject", "avrec7") and called("BuildObject", "avmu7"), "original producer ODFs")
deployed = true; Update(0.05)
check(m.utah_found and not m.test, "deployment uses local predicate without changing source member")
kill(m.ccarecycle); Update(0.05)
check(m.game_over and called("SucceedMission", 23), "enemy recycler victory")
local count = #calls; Update(0.05)
check(#calls == count, "outcome emitted once")

m = reset(); kill(m.ccacomtower); Update(0.05); now = 8; Update(0.05)
kill(m.nsdfrecycle); kill(m.ccarecycle); Update(0.05)
check(called("FailMission", 23) and not called("SucceedMission"), "source failure wins simultaneous destruction")
print("misn07: " .. checks .. " checks passed (" .. _VERSION .. ")")
