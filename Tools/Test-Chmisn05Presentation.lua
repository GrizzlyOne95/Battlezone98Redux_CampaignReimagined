-- Presentation protocol of the shared CCA runtime, run through the real ch05cr.lua guest.
-- Hand-built E/A/C packets are delivered to a guest peer: ordering, duplicates, acknowledgements, identity
-- resolution (labels, gone flags, never-hang guard), the tug film, results, wire limits; then the leader's own stream.
--   lua5.1 Tools/Test-Chmisn05Presentation.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Chmisn05Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end
local Wire = assert(loadfile("Scripts/CRWire.lua"))()

local w = F.reset()
-- Only the guest runs; the test speaks for the leader (team 1), so the stream is fully controlled.
local guest = F.makePeer(2, 2, true, {})
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
deliver("E", 3, "AddObjective", 15, "ch05003.otf", "white")
check(lastAck() == 1 and F.count(guest, "AddObjective") == 0, "a gap is not applied and re-acknowledges the last in-order event")
deliver("E", 2, "AddObjective", 15, "ch05001.otf", "green")
deliver("E", 3, "AddObjective", 15, "ch05003.otf", "white")
check(lastAck() == 3 and F.count(guest, "AddObjective") == 2, "events apply in order once the gap fills")
deliver("E", 3, "AddObjective", 15, "ch05003.otf", "white")
check(F.count(guest, "AddObjective") == 2 and lastAck() == 3, "a retransmission is acknowledged but not applied twice")

-- unknown or malformed ops advance nothing harmful
deliver("E", 4, "NotAnOp", 15, 1, 2)
check(lastAck() == 3, "an unknown op is never applied or acknowledged as progress")
deliver("E", "x", "AddObjective", 15)
deliver("E", 4, 5, 15)
check(lastAck() == 3, "malformed packets are tolerated")

-- identity: an unresolved label withholds the acknowledgement; resolving it applies the marker once
local label = "fresh_label"
deliver("E", 4, "SetObjectiveOn", 15, "@fresh1@" .. label)
check(lastAck() == 3 and F.count(guest, "SetObjectiveOn") == 0, "a marker whose object has not replicated yet waits")
w.now = w.now + 1
F.spawn("svhaul", 5, 100, 100)
local h = "test1"
F.world().objects[label] = F.world().objects[h]; F.world().objects[label].label = label
deliver("E", 4, "SetObjectiveOn", 15, "@" .. h .. "@" .. label)
check(lastAck() == 4 and F.count(guest, "SetObjectiveOn") == 1, "the marker applies once the label resolves")
deliver("E", 5, "SetObjectiveOff", 15, "!")
check(lastAck() == 5 and F.count(guest, "SetObjectiveOff") == 0, "a gone flag is skipped, never waited on")
-- never-hang guard: gives up after the ttl, counts it
deliver("E", 6, "SetObjectiveName", 15, "@x@missing_label", "Last GPS Fix")
check(lastAck() == 5, "waits first")
F.run(16)
deliver("E", 6, "SetObjectiveName", 15, "@x@missing_label", "Last GPS Fix")
check(lastAck() == 6 and F.count(guest, "SetObjectiveName", "missing_label") == 0, "the guard gives up after the timeout")
check(guest.env.Save().coopUnresolved == 1, "an unresolved identity is counted for the harness")
deliver("E", 7, "RemoveObject", 15, "@y@never")
check(lastAck() == 7 and F.count(guest, "RemoveObject") == 0, "an unresolved removal is dropped without waiting")

-- audio
deliver("E", 8, "Play", 15, "ch05001.wav")
deliver("E", 9, "Queue", 15, "ch05008.wav")
check(F.heardCount(guest, "ch05001.wav") == 1 and F.index(guest, "Queue", "ch05008.wav") ~= nil, "audio ops play and queue on the guest")

-- packets from a non-leader or aimed at the leader never change state
local before = #guest.calls
guest.env.Receive(3, "E", Wire.Pack(20, "ClearObjectives", 15))
check(#guest.calls - before <= 1, "events from a non-leader are ignored")

-- camera stream: serial ordering, kinds, finish. The tug film is a path shot with a target.
deliver("C", 5, 1, "P", "haul_cam", 800, 0, label)
deliver("C", 4, 2, "P", "stale", 1, 1, nil)
F.run(1)
check(F.last(guest, "CameraPath") ~= nil and F.last(guest, "CameraPath")[2] == "haul_cam" and F.last(guest, "CameraPath")[5] == label,
    "the streamed tug film plays on the target")
for _, c in ipairs(F.callsOf(guest, "CameraPath")) do check(c[2] ~= "stale", "a stale camera serial is ignored") end
check(guest.camera == 1, "the guest camera is up")
w.cancel = true -- the guest presses skip: it releases its own camera only
F.run(1)
check(guest.camera == 0, "a skip releases the guest's own camera")
w.cancel = false
deliver("C", 6, 3, "")
F.run(1)
check(guest.camera == 0, "the empty frame releases the guest camera")

-- results: applied after the delay, never the leader's clock
deliver("E", 10, "SucceedMission", 15, 100000, "ch05win.des")
check(F.count(guest, "SucceedMission") == 1 and F.last(guest, "SucceedMission")[2] >= w.now + 0.5 and F.last(guest, "SucceedMission")[3] == "ch05win.des"
    and guest.env.Save().coopResult, "a result is applied once and latches")

-- the leader's own stream, two real peers: events are numbered, labels precede markers, strings stay short
F.reset()
local lead = F.makePeer(1, 1, true, {})
local other = F.makePeer(2, 2, true, {})
F.connect(); F.run(2)
w = F.world()
F.setScrap(1, 3); F.run(1)
local m = lead.env.Save()
F.nearTo(m.leadScout, "trigger_1", 10, 0)
F.runUntil(function() return m.objective1Complete end, 40)
F.run(2)
local named = 0
for _, c in ipairs(F.callsOf(other, "SetObjectiveName")) do if c[3] == "Last GPS Fix" then named = named + 1 end end
check(named == 1, "the Last GPS Fix nav replicates by name; the fixture asserts every packet string < 128 bytes")
check(F.count(other, "SetObjectiveOn") == 1, "and its marker (a network game marks the target for everyone)")
F.nearTo(lead.player, "trigger_1", 330, 0); F.nearTo(other.player, "trigger_1", 336, 0)
F.runUntil(function() return m.doHaulCam end, 20)
F.run(3)
check(F.count(other, "CameraReady") == 1 and F.count(other, "CameraPath", "haul_cam") >= 1, "the film reaches the second peer")
F.run(14)
check(other.camera == 0 and lead.camera == 0, "and ends on both")
local objectiveCount = F.count(other, "AddObjective")
F.run(10)
check(F.count(other, "AddObjective") == objectiveCount, "an unchanged objective list is not streamed again (the guest list is stable)")
local sent = F.callsOf(lead, "Send")
check(#sent > 3, "the leader streams events and cameras")
local ops = {}
for _, c in ipairs(sent) do if c[2] == "E" then ops[#ops + 1] = c end end
check(#ops > 3, "numbered events are on the wire")
print("chmisn05 presentation: " .. checks .. " checks passed")
