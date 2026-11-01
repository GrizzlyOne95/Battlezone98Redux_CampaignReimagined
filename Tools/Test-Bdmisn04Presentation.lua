-- Presentation protocol of the shared CCA runtime, run through the real bdmisn04cr.lua guest.
-- Hand-built E/A/C packets are delivered to a guest peer: ordering, duplicates, acknowledgements, identity
-- resolution (labels, gone flags, never-hang guard), cameras, weather ops, this mission's four ops, wire limits.
--   lua5.1 Tools/Test-Bdmisn04Presentation.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Bdmisn04Fixture.lua")
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
deliver("E", 3, "AddObjective", 15, "bd04003.otf", "white")
check(lastAck() == 1 and F.count(guest, "AddObjective") == 0, "a gap is not applied and re-acknowledges the last in-order event")
deliver("E", 2, "AddObjective", 15, "bd04001.otf", "white")
deliver("E", 3, "AddObjective", 15, "bd04003.otf", "white")
check(lastAck() == 3 and F.count(guest, "AddObjective") == 2, "events apply in order once the gap fills")
deliver("E", 3, "AddObjective", 15, "bd04003.otf", "white")
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
F.spawn("cvfigh", 5, 100, 100)
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
deliver("E", 7, "RemoveObject", 15, "@y@never")
check(lastAck() == 7 and F.count(guest, "RemoveObject") == 0, "an unresolved removal is dropped without waiting")

-- audio, the cockpit minute and the weather
deliver("E", 8, "Play", 15, "bd04001.wav")
deliver("E", 9, "Queue", 15, "bd04009.wav")
check(F.heardCount(guest, "bd04001.wav") == 1 and F.index(guest, "Queue", "bd04009.wav") ~= nil, "audio ops play and queue on the guest")
deliver("E", 10, "StartCockpitTimer", 15, 60, 15, 5)
deliver("E", 11, "StopCockpitTimer", 15)
check(F.count(guest, "StartCockpitTimer") == 1 and F.count(guest, "StopCockpitTimer") == 1 and lastAck() == 11, "the minute starts and stops on the guest")
deliver("E", 12, "EuropaQuake", 15, 1, 0.3, 3, 1)
local net = guest.weatherCalls[#guest.weatherCalls]
check(net[1] == "net" and net[2] == "EuropaQuake" and lastAck() == 12, "weather events reach the Ganymede director")

-- this mission's four ops run on the guest's own copy of the world
deliver("E", 13, "BD4Hide", 15, 1)
check(F.count(guest, "Hide") >= 1 and F.hidden("player2"), "the guest's pilot is hidden for the film")
deliver("E", 14, "BD4Hide", 15, 0)
check(F.count(guest, "UnHide") >= 1 and not F.hidden("player2"), "and shown again")
deliver("E", 15, "BD4Disguise", 15, 5)
check(F.perceived("player2") == 5 and lastAck() == 15, "the disguise applies to the guest's pilot")
deliver("E", 16, "BD4Portal", 15, 1)
deliver("E", 17, "BD4Portal", 15, 0)
check(F.count(guest, "PortalOut", "portal") == 1 and F.count(guest, "DeactivatePortal", "portal") == 1, "the portal opens and closes by its map label")
deliver("E", 18, "BD4Target", 15, "scav_3")
deliver("E", 19, "BD4Target", 15, "no_such_label")
check(F.count(guest, "SetUserTarget", "scav_3") == 1 and F.count(guest, "SetUserTarget") == 1 and lastAck() == 19, "the user target resolves by label and an unknown label is skipped")
-- packets from a non-leader or aimed at the leader never change state
local before = #guest.calls
guest.env.Receive(3, "E", Wire.Pack(20, "ClearObjectives", 15))
check(#guest.calls - before <= 1, "events from a non-leader are ignored")
-- a guest's own report packet is only honoured by the leader
guest.env.Receive(1, "I", "cbport")
check(F.count(guest, "Send", "I") == 0, "a guest never forwards a report")

-- camera stream: serial ordering, kinds, finish
deliver("C", 5, 1, "P", "camera_start_up", 750, 400, nil)
deliver("C", 4, 2, "P", "stale", 1, 1, nil)
F.run(1)
check(F.last(guest, "CameraPath") ~= nil, "a streamed shot plays")
for _, c in ipairs(F.callsOf(guest, "CameraPath")) do check(c[2] ~= "stale", "a stale camera serial is ignored") end
deliver("C", 6, 3, "")
F.run(1)
check(guest.camera == 0, "the empty frame releases the guest camera")

-- results: applied after the delay, never the leader's clock
deliver("E", 20, "FailMission", 15, 100000, "bd04lose.des")
check(F.count(guest, "FailMission") == 1 and F.last(guest, "FailMission")[2] >= w.now + 0.5 and F.last(guest, "FailMission")[3] == "bd04lose.des"
    and guest.env.Save().coopResult, "a result is applied once and latches")

-- the leader's own stream, two real peers: events are numbered, labels precede markers, strings stay short
F.reset()
local lead = F.makePeer(1, 1, true, {})
local other = F.makePeer(2, 2, true, {})
F.connect(); F.run(2)
w = F.world()
w.cameraDone["camera_start_up"] = true; F.run(1); w.cameraDone["camera_start_up"] = false
F.run(14)
local sent = F.callsOf(lead, "Send")
check(#sent > 3, "the leader streams events and cameras")
check(F.count(other, "SetObjectiveName", "scav_3") >= 1, "the named scav replicates; the fixture asserts every packet string < 128 bytes")
local objectiveCount = F.count(other, "AddObjective")
F.run(10)
check(F.count(other, "AddObjective") == objectiveCount, "an unchanged objective list is not streamed again (the guest list is stable)")
local ops = {}
for _, c in ipairs(sent) do if c[2] == "E" then ops[c[4]] = true end end
for _, op in ipairs({"BD4Hide", "BD4Disguise", "BD4Portal", "BD4Target"}) do check(ops[op], "the leader streams " .. op) end
check(F.count(other, "PortalOut") == 1 and F.perceived("player2") == 5 and F.count(other, "SetUserTarget", "scav_3") == 1,
    "and the second peer applied them")
print("bdmisn04 presentation: " .. checks .. " checks passed")
