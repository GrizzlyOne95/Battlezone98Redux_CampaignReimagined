-- Presentation protocol of the shared CCA runtime, run through the real ch08cr.lua guest.
-- Hand-built E/A/C packets are delivered to a guest peer: ordering, duplicates, acknowledgements, identity
-- resolution (labels, gone flags, never-hang guard), cameras, weather ops, wire limits, and this mission's
-- five presentation ops (each targets a single handle, unlike chmisn07's broadcast-to-every-human style).
--   lua5.1 Tools/Test-Chmisn08Presentation.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Chmisn08Fixture.lua")
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
deliver("E", 3, "AddObjective", 15, "ch08003.otf", "white")
check(lastAck() == 1 and F.count(guest, "AddObjective") == 0, "a gap is not applied and re-acknowledges the last in-order event")
deliver("E", 2, "AddObjective", 15, "ch08001.otf", "white")
deliver("E", 3, "AddObjective", 15, "ch08003.otf", "white")
check(lastAck() == 3 and F.count(guest, "AddObjective") == 2, "events apply in order once the gap fills")
deliver("E", 3, "AddObjective", 15, "ch08003.otf", "white")
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
deliver("E", 8, "Play", 15, "ch08003.wav")
deliver("E", 9, "Queue", 15, "ch08004.wav")
check(F.heardCount(guest, "ch08003.wav") == 1 and F.index(guest, "Queue", "ch08004.wav") ~= nil, "audio ops play and queue on the guest")
-- weather events reach the Europa/Ganymede weather module
deliver("E", 10, "EuropaQuake", 15, 3, 4)
local netEvents = 0
for _, c in ipairs(guest.weatherCalls) do if c[1] == "net" and c[2] == "EuropaQuake" then netEvents = netEvents + 1 end end
check(netEvents == 1 and lastAck() == 10, "weather events reach the Europa weather module")
-- packets from a non-leader never change state
local g2before = #guest.calls
guest.env.Receive(3, "E", Wire.Pack(12, "ClearObjectives", 15))
check(#guest.calls - g2before <= 1, "events from a non-leader are ignored")

-- this mission's five ops: each targets ONE specific handle, unlike chmisn07's broadcast-to-every-human style
-- (only the APC-5 driver's cloak/disguise changes, never every human's).
local target = "test1" -- the real handle spawned above
deliver("E", 11, "CH8Cloak", 15, target)
check(F.cloaked(target) and lastAck() == 11, "CH8Cloak cloaks the named handle on the guest's copy")
deliver("E", 12, "CH8EnableCloak", 15, target, false)
check(F.count(guest, "EnableCloaking", target) == 1 and F.last(guest, "EnableCloaking")[3] == false, "CH8EnableCloak disables cloaking on the named handle")
deliver("E", 13, "CH8Decloak", 15, target)
check(not F.cloaked(target) and lastAck() == 13, "CH8Decloak decloaks the named handle")
deliver("E", 14, "CH8Perceived", 15, target, 5)
check(F.perceived(target) == 5 and lastAck() == 14, "CH8Perceived sets the Soviet perceived team (5) on the named handle")
deliver("E", 15, "CH8Perceived", 15, target, 2)
check(F.perceived(target) == 2, "CH8Perceived restores the handle's own team")
deliver("E", 16, "CH8Boom", 15, "xpltrsr", target)
check(F.count(guest, "MakeExplosion") == 1 and lastAck() == 16, "CH8Boom shows the blast at the named handle")
deliver("E", 17, "CH8Boom", 15, "xpltrsd", "wrecker_1")
check(F.count(guest, "MakeExplosion") == 2 and lastAck() == 17, "CH8Boom also accepts a path location")
-- a gone/invalid handle for a per-handle op is simply skipped, never crashes the guest
deliver("E", 18, "CH8Cloak", 15, "!")
check(lastAck() == 18, "a gone flag for a per-handle op acknowledges without waiting")
deliver("E", 19, "CH8Perceived", 15, "@z@never_resolves", 5)
F.run(16)
deliver("E", 19, "CH8Perceived", 15, "@z@never_resolves", 5)
check(lastAck() == 19, "an unresolved per-handle op also gives up after the never-hang guard")

-- camera stream: serial ordering, kinds, finish
deliver("C", 5, 1, "P", "cut_1", 2000, 0, nil)
deliver("C", 4, 2, "P", "stale", 1, 1, nil)
F.run(1)
check(F.last(guest, "CameraPath") ~= nil, "a streamed shot plays")
for _, c in ipairs(F.callsOf(guest, "CameraPath")) do check(c[2] ~= "stale", "a stale camera serial is ignored") end
deliver("C", 6, 3, "")
F.run(1)
check(guest.camera == 0, "the empty frame releases the guest camera")

-- results: applied after the delay, never the leader's clock
deliver("E", 20, "FailMission", 15, 100000, "ch08lsed.des")
check(F.count(guest, "FailMission") == 1 and F.last(guest, "FailMission")[2] >= w.now + 0.5 and F.last(guest, "FailMission")[3] == "ch08lsed.des" and guest.env.Save().coopResult, "a result is applied once and latches")

-- the leader's own stream, two real peers: events are numbered, strings stay short, cloak/decloak replicate
F.reset()
local lead = F.makePeer(1, 1, true, {})
local other = F.makePeer(2, 2, true, {})
F.connect(); F.run(1)
local lm = lead.env.Save()
F.nearTo("west_1_1", "cut_trigger", 0, 0)
F.run(1); F.run(23) -- the opening cutscene ends; the eight escort tanks are cloaked and then removed
local sent = F.callsOf(lead, "Send")
check(#sent > 3, "the leader streams events and cameras")
local ops = {}
for _, c in ipairs(sent) do if c[2] == "E" then ops[c[4]] = true end end
check(ops["CH8Cloak"], "the leader streams CH8Cloak")
-- the fixture's packet-size assertion (in F.makePeer's Send) already proves every packet string stays < 128 bytes
print("chmisn08 presentation: " .. checks .. " checks passed")
