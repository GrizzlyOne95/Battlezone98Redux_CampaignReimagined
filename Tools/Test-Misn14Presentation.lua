-- Run from the repository root: lua5.1 Tools/Test-Misn14Presentation.lua
-- Host/guest presentation parity for misn14 co-op: every peer hears the same radio lines in the same order,
-- shows the same objectives and markers, and films the same shared cutscenes (the intro, the Fury activation
-- and loss-of-control scenes, the rescue APC shots), driven only by the host's ordered E/A stream and the C
-- camera snapshots. Guests never run mission logic.
assert(_VERSION == "Lua 5.1", "run with Lua 5.1")
local F = dofile("Tools/Misn14Fixture.lua")
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

local W = F.reset()
local host = F.makePeer(1, 1, true)
local guests = {F.makePeer(2, 2, true), F.makePeer(3, 3, true), F.makePeer(4, 4, true)}
F.connect()
local function M() return host.env.Save() end
local function toPhase(phase, limit) F.runUntil(function() return M().fury_phase == phase end, limit or 400) end

-- Intro: the path camera reaches every guest.
F.run(3)
for _, g in ipairs(guests) do
    check(F.count(g, "CameraReady") >= 1 and F.count(g, "CameraPath", "cam_path1") > 0, "guest films the intro")
    check(F.heard(g, "misn1401.wav"), "guest hears the briefing")
end
F.runUntil(function() return M().objective_time ~= nil end, 60)
F.run(2)
for _, g in ipairs(guests) do
    check(g.camera == 0, "guest camera released after the intro")
    check(F.count(g, "AddObjective", "misn1401.otf") == 1, "guest shows the stock objective")
    local named = {}
    for _, c in ipairs(F.callsOf(g, "SetObjectiveName")) do named[c[3]] = true end
    check(named["Foothill Geysers"] and named["Canyon Geysers"] and named["CCA Base"] and named["Plateau Geysers"],
        "guest names the four nav pods")
end

-- Beacon 1 marker reaches guests on the spawned pod.
F.run(16)
F.run(2)
for _, g in ipairs(guests) do
    local on = F.last(g, "SetObjectiveOn")
    check(on and on[2] ~= nil and F.alive(on[2]), "guest marks beacon 1 on the real object")
end

-- Activation scene: shared camera on the squad lead, the three lines in order.
toPhase("activating", 60)
F.run(2)
local lead
for _, entry in ipairs(M().fury_squad) do if F.alive(entry.unit) then lead = entry.unit; break end end
for _, g in ipairs(guests) do
    local filmed = false
    for _, c in ipairs(F.callsOf(g, "CameraObject")) do
        if c[2] == lead or (W.objects[c[2]] and W.objects[c[2]] == W.objects[lead]) then filmed = true end
    end
    check(filmed, "guest films the Fury squad during activation")
end
toPhase("control", 20)
F.run(2)
for _, g in ipairs(guests) do
    check(g.camera == 0, "guest camera released after activation")
    check(F.count(g, "AddObjective", "misn14_furies") == 1, "guest shows the Fury squad objective")
end
toPhase("rogue", 100)
F.run(2)
for _, g in ipairs(guests) do
    check(F.count(g, "UpdateObjective", "misn14_furies") == 1 and F.last(g, "UpdateObjective")[3] == "red",
        "guest objective turns red")
    check(g.camera == 0, "guest camera released after the loss scene")
end

-- Rescue 1 with the host's APC: the APC shot reaches guests; beacon 2's Razor Two name resolves.
local apc = F.spawn("avapc", 1, 2400, 99300)
F.nearTo(apc, "rescue1", 30, 0)
F.run(2)
for _, g in ipairs(guests) do
    local filmed = false
    for _, c in ipairs(F.callsOf(g, "CameraObject")) do if W.objects[c[2]] == W.objects[apc] then filmed = true end end
    check(filmed, "guest films the rescue APC")
end
F.run(40)
for _, g in ipairs(guests) do
    local razor = false
    for _, c in ipairs(F.callsOf(g, "SetObjectiveName")) do if c[3] == "Razor Two" and F.alive(c[2]) then razor = true end end
    check(razor, "guest names Razor Two on the real pilot")
end

-- The radio log is identical on every peer (same lines, same order, same Play/Queue choice).
F.run(5)
local function log(p)
    local out = {}
    for _, c in ipairs(p.calls) do if c[1] == "Play" or c[1] == "Queue" then out[#out + 1] = c[1] .. ":" .. c[2] end end
    return table.concat(out, ",")
end
local hostLog = log(host)
for _, needed in ipairs({"misn1401", "misn1416", "misn1402", "misn1423", "misn1424", "misn1425", "misn1426", "misn1409"}) do
    check(hostLog:find(needed, 1, true), "host played " .. needed)
end
for _, g in ipairs(guests) do
    check(log(g) == hostLog, "guest radio log matches the host")
    check(g.env.Save().coopUnresolved == 0, "guest resolved every marker and camera")
    check(F.count(g, "print") == 0, "guest logged nothing unresolved")
end

-- The result: a Texas loss reaches everyone with its debrief.
F.kill("avrecy-1_recycler")
F.run(12)
for _, p in pairs(W.peers) do
    check(F.count(p, "FailMission") == 1 and F.last(p, "FailMission")[3] == "misn14l1.des", "every peer gets the l1 result")
    check(p.camera == 0, "camera stack balanced at the end on peer " .. p.id)
end

print(string.format("misn14 presentation: %d checks passed", checks))
