local Sim = dofile("Tools/BZRPeerTransportSim.lua")
local delivered = {}
local sim = Sim.New(function(p) delivered[#delivered + 1] = p.kind end)
sim:Send(10, 20, "first", { "value" }, true)
sim:Send(10, 20, "second", { 3 }, true)
local header = sim:Header(sim.queue[1])
assert(#header == 18 and header:byte(1) == 0xC0 and header:byte(2) == 0)
assert(header:sub(11, 14) == "\0\0\0\1" and header:sub(15, 18) == "\0\0\0\1")
-- The later reliable packet is rejected, not delivered before the missing one.
sim:Step(0.1, true, function(p) return p.kind == "first" end)
assert(#delivered == 0 and sim.rejected == 1)
-- Ordered retries close the gap; acknowledgements remove both pending sends.
sim:Step(0.3)
sim:Step(0.4)
assert(table.concat(delivered, ",") == "first,second")
assert(next(sim.links["10:20"].pending) == nil and sim.retries == 2)
-- A duplicate reliable datagram cannot dispatch twice.
sim.queue[#sim.queue + 1] = { from = 10, to = 20, reliable = true,
    seq = 1, ack = 1, kind = "duplicate", args = {}, due = 0 }
sim:Step(0.5)
assert(#delivered == 2 and sim.rejected == 2)
-- Unreliable sends carry the current sequence without incrementing it.
sim:Send(10, 20, "snapshot", { false }, false)
sim:Send(10, 20, "newest", { true }, false)
assert(sim:Header(sim.queue[#sim.queue]):byte(1) == 0x40)
sim:Step(0.6, false, function(p) return p.kind == "snapshot" end)
sim:Step(1)
assert(table.concat(delivered, ",") == "first,second,newest")
-- Native reliable backlog is distinct from mission event retries. A sustained
-- gap prevents later gameplay dispatch, then recovers when loss ends.
local seen = 0
local stalled = Sim.New(function() seen = seen + 1 end, { latency = 0.1, retry = 0.3 })
for i = 1, 20 do stalled:Send(10, 20, tostring(i), {}, true) end
for i = 1, 20 do stalled:Step(i * 0.1, false, function(p) return p.seq == 1 and not p.ackOnly end) end
assert(seen == 0 and stalled.retries > 0)
for i = 21, 30 do stalled:Step(i * 0.1) end
assert(seen == 20)
print("BZRNet peer envelope ordering, ACK, loss, duplicate and backlog checks passed")
