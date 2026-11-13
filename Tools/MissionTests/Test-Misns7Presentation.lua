-- Presentation protocol of the shared CCA runtime, run through the real misns7cr.lua guest.
-- Hand-built E/A/C packets are delivered to a guest peer: ordering, duplicates, acknowledgements, identity
-- resolution (labels, gone flags, never-hang guard), the object cameras misns7 uses, Titan weather ops, wire limits.
--   lua5.1 Tools/MissionTests/Test-Misns7Presentation.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/MissionTests/Misns7Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end
local Wire = assert(loadfile("Scripts/CRWire.lua"))()

local weatherEvents = {}
local weather = { module = function(peer, record)
    return { Seed = 7, Init = function() end, Update = function() end,
        ApplyNetEvent = function(op, ...) weatherEvents[#weatherEvents + 1] = { op, ... } end,
        Shutdown = function() end, Save = function() return {} end }
end, sites = { bounds = {} } }

local w = F.reset()
-- Only the guest runs; the test speaks for the leader (team 1), so the stream is fully controlled.
local guest = F.makePeer(2, 2, true, { weather = weather })
guest.env.CreatePlayer(2, "P2", 2)
guest.env.AddPlayer(1, "P1", 1)
F.run(1)
local function deliver(kind, ...)
    guest.env.Receive(1, kind, Wire.Pack(...))
end
local acked = {}
local realSend = guest.env.Send
guest.env.Send = function(to, kind, ...)
    if kind == "A" then acked[#acked + 1] = (Wire.Unpack(...)) end
    return realSend(to, kind, ...)
end
local function lastAck() return acked[#acked] end

-- ordered delivery: seq 1 applies, a gap (3) is withheld and re-acked at 1, 2 then 3 apply
deliver("E", 1, "ClearObjectives", 15)
check(lastAck() == 1 and F.count(guest, "ClearObjectives") >= 1, "seq 1 applies and is acknowledged")
deliver("E", 3, "AddObjective", 15, "misns703.otf", "green")
check(lastAck() == 1 and F.count(guest, "AddObjective") == 0, "a gap is not applied and re-acknowledges the last in-order event")
deliver("E", 2, "AddObjective", 15, "misns700.otf", "white")
deliver("E", 3, "AddObjective", 15, "misns703.otf", "green")
check(lastAck() == 3 and F.count(guest, "AddObjective") == 2, "events apply in order once the gap fills")
deliver("E", 3, "AddObjective", 15, "misns703.otf", "green")
check(F.count(guest, "AddObjective") == 2 and lastAck() == 3, "a retransmission is acknowledged but not applied twice")

-- unknown or malformed ops advance nothing harmful (a Venus op is not a Titan op)
deliver("E", 4, "NotAnOp", 15, 1, 2)
deliver("E", 4, "VenusStrike", 15, 1, 2)
check(lastAck() == 3, "an unknown op is never applied or acknowledged as progress")
deliver("E", "x", "AddObjective", 15)
deliver("E", 4, 5, 15)
check(lastAck() == 3, "malformed packets are tolerated")

-- identity: the prison marker (SetObjectiveName on the jail) waits for the label, a removed engineer is skipped
local label = "fresh_label"
deliver("E", 4, "SetObjectiveOn", 15, "@fresh1@" .. label)
check(lastAck() == 3 and F.count(guest, "SetObjectiveOn") == 0, "a marker whose object has not replicated yet waits")
w.now = w.now + 1
F.spawn("sssold", 1, 100, 100)
local h = "test1"
F.world().objects[label] = F.world().objects[h]; F.world().objects[label].label = label
deliver("E", 4, "SetObjectiveOn", 15, "@" .. h .. "@" .. label)
check(lastAck() == 4 and F.count(guest, "SetObjectiveOn") == 1, "the marker applies once the label resolves")
deliver("E", 5, "SetObjectiveOn", 15, "!")
check(lastAck() == 5 and F.count(guest, "SetObjectiveOn") == 1, "a gone flag is skipped, never waited on")
deliver("E", 6, "SetObjectiveName", 15, "@x@missing_label", "Military Prison")
check(lastAck() == 5, "waits first")
F.run(16)
deliver("E", 6, "SetObjectiveName", 15, "@x@missing_label", "Military Prison")
check(lastAck() == 6 and F.count(guest, "SetObjectiveName", "missing_label") == 0, "the guard gives up after the timeout")
check(guest.env.Save().coopUnresolved == 1, "an unresolved identity is counted for the harness")
deliver("E", 7, "RemoveObject", 15, "@y@never")
check(lastAck() == 7 and F.count(guest, "RemoveObject") == 0, "an unresolved removal (the engineer) is dropped without waiting")

-- audio and result ops
deliver("E", 8, "Play", 15, "misns702.wav")
deliver("E", 9, "Queue", 15, "misns704.wav")
check(F.heardCount(guest, "misns702.wav") == 1 and F.index(guest, "Queue", "misns704.wav") ~= nil, "audio ops play and queue on the guest")
-- Titan weather ops carry no handle and go to the weather module
deliver("E", 10, "TitanState", 15, 7, 1, 2)
deliver("E", 11, "TitanRoll", 15, 1, 0.8, 60)
check(#weatherEvents == 2 and weatherEvents[1][1] == "TitanState" and weatherEvents[2][1] == "TitanRoll" and lastAck() == 11,
    "Titan weather events reach the weather module")
-- packets from a non-leader never change state
local g2before = #guest.calls
guest.env.Receive(3, "E", Wire.Pack(13, "ClearObjectives", 15))
check(#guest.calls - g2before <= 1, "events from a non-leader are ignored")

-- camera stream: the prison and delivery shots are object cameras ("O"): subject, x, y, z, target
F.spawn("abstor", 5, 100, 100)
local geyser, boxes = "geyser1", "boxes"
deliver("C", 5, 1, "O", "@geyser1@geyser1", -1500, 1000, -5000, "@boxes@boxes")
F.run(1)
check(F.last(guest, "CameraObject") ~= nil and F.last(guest, "CameraObject")[2] == geyser and F.last(guest, "CameraObject")[6] == boxes
    and guest.camera == 1, "a streamed object shot plays on the guest")
deliver("C", 4, 2, "O", "@geyser1@geyser1", 1, 1, 1, "@boxes@boxes")
for _, c in ipairs(F.callsOf(guest, "CameraObject")) do check(c[3] ~= 1, "a stale camera serial is ignored") end
deliver("C", 6, 3, "")
F.run(1)
check(guest.camera == 0, "the empty frame releases the guest camera")

-- results: applied after the delay, never the leader's clock
deliver("E", 12, "SucceedMission", 15, 100000, "misns7w1.des")
check(F.count(guest, "SucceedMission") == 1 and F.last(guest, "SucceedMission")[2] >= w.now + 0.5
    and F.last(guest, "SucceedMission")[3] == "misns7w1.des" and guest.env.Save().coopResult, "a result is applied once and latches")

-- the leader's own stream, two real peers: events are numbered, labels precede markers, strings stay short
F.reset()
local lead = F.makePeer(1, 1, true, {})
local other = F.makePeer(2, 2, true, {})
F.connect(); F.run(3)
local lm = lead.env.Save()
check(#F.callsOf(lead, "Send") > 3, "the leader streams events and cameras")
check(F.count(other, "SetObjectiveName", "jail") >= 1 and F.count(other, "SetObjectiveOn", "jail") >= 1,
    "the prison marker replicates; the fixture asserts every packet string < 128 bytes")
local objectiveCount = F.count(other, "AddObjective")
for _ = 1, 20 do F.run(0.25) end
check(F.count(other, "AddObjective") == objectiveCount, "an unchanged objective list is not streamed again")
print("misns7 presentation: " .. checks .. " checks passed")
