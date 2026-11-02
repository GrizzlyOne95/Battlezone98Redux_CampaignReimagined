-- Presentation protocol of the shared CCA runtime, run through the real chmisn07cr.lua guest.
-- Hand-built E/A/C packets are delivered to a guest peer: ordering, duplicates, acknowledgements, identity
-- resolution (labels, gone flags, never-hang guard), cameras, weather ops, wire limits.
--   lua5.1 Tools/Test-Chmisn07Presentation.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Chmisn07Fixture.lua")
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
local before = #guest.calls

-- ordered delivery: seq 1 applies, a gap (3) is withheld and re-acked at 1, 2 then 3 apply
deliver("E", 1, "ClearObjectives", 15)
check(lastAck() == 1 and F.count(guest, "ClearObjectives") >= 1, "seq 1 applies and is acknowledged")
local clears = F.count(guest, "ClearObjectives")
deliver("E", 3, "AddObjective", 15, "ch07003.otf", "white")
check(lastAck() == 1 and F.count(guest, "AddObjective") == 0, "a gap is not applied and re-acknowledges the last in-order event")
deliver("E", 2, "AddObjective", 15, "ch07001.otf", "white")
deliver("E", 3, "AddObjective", 15, "ch07003.otf", "white")
check(lastAck() == 3 and F.count(guest, "AddObjective") == 2, "events apply in order once the gap fills")
deliver("E", 3, "AddObjective", 15, "ch07003.otf", "white")
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
F.spawn("svfigh", 5, 100, 100)
local h = "test1"
F.world().objects[label] = F.world().objects[h]; F.world().objects[label].label = label
deliver("E", 4, "SetObjectiveOn", 15, "@" .. h .. "@" .. label)
check(lastAck() == 4 and F.count(guest, "SetObjectiveOn") == 1, "the marker applies once the label resolves")
deliver("E", 5, "SetObjectiveOn", 15, "!")
check(lastAck() == 5 and F.count(guest, "SetObjectiveOn") == 1, "a gone flag is skipped, never waited on")
-- never-hang guard: gives up after the ttl, counts it
deliver("E", 6, "SetObjectiveName", 15, "@x@missing_label", "Name")
check(lastAck() == 5, "waits first")
F.run(16)
deliver("E", 6, "SetObjectiveName", 15, "@x@missing_label", "Name")
check(lastAck() == 6 and F.count(guest, "SetObjectiveName", "missing_label") == 0, "the guard gives up after the timeout")
check(guest.env.Save().coopUnresolved == 1, "an unresolved identity is counted for the harness")
-- RemoveObject needs no wait: an unresolved removal is dropped
deliver("E", 7, "RemoveObject", 15, "@y@never")
check(lastAck() == 7 and F.count(guest, "RemoveObject") == 0, "an unresolved removal is dropped without waiting")

-- audio and result ops
deliver("E", 8, "Play", 15, "ch07003.wav")
deliver("E", 9, "Queue", 15, "ch07004.wav")
check(F.heardCount(guest, "ch07003.wav") == 1 and F.index(guest, "Queue", "ch07004.wav") ~= nil, "audio ops play and queue on the guest")
-- weather ops carry no handle and go to the weather module
deliver("E", 10, "EuropaQuake", 15, 3, 4)
local netEvents = 0
for _, c in ipairs(guest.weatherCalls) do if c[1] == "net" and c[2] == "EuropaQuake" then netEvents = netEvents + 1 end end
check(netEvents == 1 and lastAck() == 10, "weather events reach the Europa weather module")
-- packets from a non-leader or aimed at the leader never change state
local g2before = #guest.calls
guest.env.Receive(3, "E", Wire.Pack(12, "ClearObjectives", 15))
check(#guest.calls - g2before <= 1, "events from a non-leader are ignored")

-- this mission's five ops on a guest: the disguise is every human's, the pickup flash only the picker's
local gp = "player2"
deliver("E", 11, "CH7Hide", 15, 1)
check(F.hidden(gp) and lastAck() == 11, "CH7Hide hides the humans on the guest's copy")
deliver("E", 12, "CH7Disguise", 15, 5)
check(F.perceived(gp) == 5 and lastAck() == 12, "CH7Disguise 5 sets the Soviet perceived team (5) on the guest's copy")
deliver("E", 13, "CH7Disguise", 15, 1)
check(F.perceived(gp) == 2, "CH7Disguise 1 restores the human's own team")
deliver("E", 14, "CH7Hide", 15, 0)
check(not F.hidden(gp), "CH7Hide 0 shows them again")
deliver("E", 15, "CH7Exit", 15)
local pos = F.posOf(gp)
check(lastAck() == 15 and math.abs(pos.x - 1004) < 1.5 and math.abs(pos.z - 99638) < 1.5, "CH7Exit lifts the guest's own pilot out of the tower")
deliver("E", 16, "CH7Boom", 15, "xtorxplb", "expl_north_spn")
check(F.count(guest, "MakeExplosion") == 1 and lastAck() == 16, "CH7Boom shows the blast")
deliver("E", 17, "CH7Pickup", 15, 3)
check(F.count(guest, "ColorFade") == 0 and lastAck() == 17, "a pickup of another team flashes nothing")
deliver("E", 18, "CH7Pickup", 15, 2)
check(F.count(guest, "ColorFade") == 1 and F.count(guest, "StartSound", "repair.wav") == 1, "the picker's own peer flashes")

-- camera stream: serial ordering, kinds, finish
local gcam = F.count(guest, "CameraPath")
deliver("C", 5, 1, "P", "cin_start", 1500, 8000, nil)
deliver("C", 4, 2, "P", "stale", 1, 1, nil)
F.run(1)
check(F.last(guest, "CameraPath") ~= nil, "a streamed shot plays")
for _, c in ipairs(F.callsOf(guest, "CameraPath")) do check(c[2] ~= "stale", "a stale camera serial is ignored") end
deliver("C", 6, 3, "")
F.run(1)
check(guest.camera == 0, "the empty frame releases the guest camera")

-- results: applied after the delay, never the leader's clock
deliver("E", 19, "FailMission", 15, 100000, "ch07lose.des")
check(F.count(guest, "FailMission") == 1 and F.last(guest, "FailMission")[2] >= w.now + 0.5 and F.last(guest, "FailMission")[3] == "ch07lose.des" and guest.env.Save().coopResult, "a result is applied once and latches")


-- the leader's own stream, two real peers: events are numbered, labels precede markers, strings stay short
F.reset()
local lead = F.makePeer(1, 1, true, {})
local other = F.makePeer(2, 2, true, {})
F.connect(); F.run(1)
local lm = lead.env.Save()
lm.direction = 0
F.world().cameraDone["cin_start"] = true; F.run(1); F.world().cameraDone["cin_start"] = false
F.nearTo(lead.player, "commtower", 5, 0); F.run(1)
F.nearTo(lm.fakePlayer, "fake_vanish", 0, 0); F.run(6)
F.world().cameraDone["cin_north"] = true; F.run(3)
local sent = F.callsOf(lead, "Send")
check(#sent > 3, "the leader streams events and cameras")
check(F.count(other, "SetObjectiveName", lm.navBridge) == 1, "the named bridge beacon replicates; the fixture asserts every packet string < 128 bytes")
local objectiveCount = F.count(other, "AddObjective")
F.run(10)
check(F.count(other, "AddObjective") == objectiveCount, "an unchanged objective rebuild is not streamed again (the guest list is stable)")
local ops = {}
for _, c in ipairs(sent) do if c[2] == "E" then ops[c[4]] = true end end
for _, op in ipairs({"CH7Hide", "CH7Disguise", "CH7Exit"}) do check(ops[op], "the leader streams " .. op) end
check(F.perceived("player2") == 2 and not F.hidden("player2"), "and the second peer applied them (its own team back, visible)")
print("chmisn07 presentation: " .. checks .. " checks passed")
