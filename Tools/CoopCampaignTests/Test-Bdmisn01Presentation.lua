-- Presentation protocol of the shared CCA runtime, run through the real bd01cr.lua guest.
-- Hand-built E/A/C packets are delivered to a guest peer: ordering, duplicates, acknowledgements, identity
-- resolution (labels, gone flags, never-hang guard), cameras, weather ops, wire limits.
--   lua5.1 Tools/CoopCampaignTests/Test-Bdmisn01Presentation.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/CoopCampaignTests/Bdmisn01Fixture.lua")
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
local before = #guest.calls

-- ordered delivery: seq 1 applies, a gap (3) is withheld and re-acked at 1, 2 then 3 apply
deliver("E", 1, "ClearObjectives", 15)
check(lastAck() == 1 and F.count(guest, "ClearObjectives") >= 1, "seq 1 applies and is acknowledged")
local clears = F.count(guest, "ClearObjectives")
deliver("E", 3, "AddObjective", 15, "bd01003.otf", "white")
check(lastAck() == 1 and F.count(guest, "AddObjective") == 0, "a gap is not applied and re-acknowledges the last in-order event")
deliver("E", 2, "AddObjective", 15, "bd01001.otf", "white")
deliver("E", 3, "AddObjective", 15, "bd01003.otf", "white")
check(lastAck() == 3 and F.count(guest, "AddObjective") == 2, "events apply in order once the gap fills")
deliver("E", 3, "AddObjective", 15, "bd01003.otf", "white")
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
F.spawn("avtank", 5, 100, 100)
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
deliver("E", 8, "Play", 15, "bd01003.wav")
deliver("E", 9, "Queue", 15, "bd01004.wav")
check(F.heardCount(guest, "bd01003.wav") == 1 and F.index(guest, "Queue", "bd01004.wav") ~= nil, "audio ops play and queue on the guest")
-- weather ops carry no handle and go to the weather module
deliver("E", 10, "EuropaQuake", 15, 3, 4)
check(#weatherEvents >= 1 and weatherEvents[#weatherEvents][1] == "EuropaQuake" and lastAck() == 10, "weather events reach the Ganymede weather module")
-- packets from a non-leader or aimed at the leader never change state
local g2before = #guest.calls
guest.env.Receive(3, "E", Wire.Pack(12, "ClearObjectives", 15))
check(#guest.calls - g2before <= 1, "events from a non-leader are ignored")

-- camera stream: serial ordering, kinds, finish
local gcam = F.count(guest, "CameraPath")
deliver("C", 5, 1, "P", "opencam", 1500, 8000, nil)
deliver("C", 4, 2, "P", "stale", 1, 1, nil)
F.run(1)
check(F.last(guest, "CameraPath") ~= nil, "a streamed shot plays")
for _, c in ipairs(F.callsOf(guest, "CameraPath")) do check(c[2] ~= "stale", "a stale camera serial is ignored") end
deliver("C", 6, 3, "")
F.run(1)
check(guest.camera == 0, "the empty frame releases the guest camera")

-- results: applied after the delay, never the leader's clock
deliver("E", 11, "FailMission", 15, 100000, "bd01lsea.des")
check(F.count(guest, "FailMission") == 1 and F.last(guest, "FailMission")[2] >= w.now + 0.5 and F.last(guest, "FailMission")[3] == "bd01lsea.des" and guest.env.Save().coopResult, "a result is applied once and latches")


-- the leader's own stream, two real peers: events are numbered, labels precede markers, strings stay short
F.reset()
local lead = F.makePeer(1, 1, true, {})
local other = F.makePeer(2, 2, true, {})
F.connect(); F.run(1)
local lm = lead.env.Save()
F.world().cameraDone["camera_start_arc"] = true; F.run(1)
F.world().objects["recycler"].deployed = true; F.run(23)
local sent = F.callsOf(lead, "Send")
check(#sent > 3, "the leader streams events and cameras")
check(lm.beaconSpawned2 and F.count(other, "SetObjectiveName", lm.beacon) == 1, "the named beacon replicates; the fixture asserts every packet string < 128 bytes")
check(F.count(other, "SetObjectiveOn", lm.beacon) == 1, "the beacon marker follows its label to the guest")
local objectiveCount = F.count(other, "AddObjective")
F.run(10)
check(F.count(other, "AddObjective") == objectiveCount, "an unchanged objective rebuild is not streamed again (the guest list is stable)")
print("bdmisn01 presentation: " .. checks .. " checks passed")
