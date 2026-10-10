-- Lua 5.1: independent peers and controllable loss/reordering, using the real
-- communication service. Native Redux replication is qualified separately.
local Comms = require("CRCoopComms")
local now, peers, messages, queue, checks = 0, {}, {}, {}, 0
local objects = { [1] = { valid = true, pilot = false }, [2] = { valid = true, pilot = true },
    [3] = { valid = true, pilot = true }, [9] = { valid = true, pilot = false } }
local registry = { [10] = { name = "Host", team = 1, handle = objects[1], ready = true },
    [20] = { name = "Guest", team = 2, handle = objects[2], ready = true },
    [30] = { name = "Friend", team = 3, handle = objects[3], ready = true } }
local function check(value, label) assert(value, label); checks = checks + 1 end
for id in pairs(registry) do
    local mine = id
    local d = {
        time = function() return now end, players = function() return registry end,
        localId = function() return mine end, localHandle = function() return registry[mine].handle end,
        humanTeam = function(t) return t >= 1 and t <= 4 end,
        valid = function(h) return type(h) == "table" and h.valid == true end,
        person = function(h) return h.pilot end, position = function() return { x = 50, y = 0, z = 70 } end,
        network = function() return true end, ready = function() return true end,
        authority = function() return mine == 10 end, leaderTeam = function() return 1 end,
        message = function(text) messages[#messages + 1] = { mine, text } end,
        target = function(h) peers[mine].target = h end,
        send = function(to, channel, ...)
            local args = { ... }
            check(#args == 11, "packet holes")
            local bytes = 0
            for _, v in ipairs(args) do
                check(type(v) ~= "string", "wire strings are unnecessary")
                -- Tables here represent native handles, never on-wire tables.
                bytes = bytes + (type(v) == "number" and 9 or 5)
            end
            check(bytes < 128, "compact wire payload")
            queue[#queue + 1] = { from = mine, to = to, channel = channel, args = args }
        end,
    }
    peers[mine] = { service = Comms.Create(d) }
    peers[mine].service.Reset(true)
end
local unpack = unpack or table.unpack
local function deliver(packet)
    peers[packet.to].service.Receive(packet.from, packet.channel, unpack(packet.args))
end
local function flush()
    while #queue > 0 do local packets = queue; queue = {}; for _, p in ipairs(packets) do deliver(p) end end
end
local function advance(dt)
    now = now + dt
    for _, p in pairs(peers) do p.service.Update() end
end
local H, G, F = peers[10].service, peers[20].service, peers[30].service
check(H.SendPing("terrain", nil, { x = 100, y = 3, z = 120 }), "terrain publish")
local oldPing = queue[1]
queue = {} -- Lose both first transmissions.
advance(0.7); flush()
check(G.GetPings()[10].position.x == 100 and F.GetPings()[10].kind == "terrain", "retry to both guests")
local before = #messages
deliver(oldPing); flush()
check(#messages == before, "duplicate does not notify twice")
check(not H.SendPing("terrain", nil, { x = 1, y = 2, z = 3 }), "ping cooldown")
advance(11); flush()
check(next(H.GetPings()) == nil and next(G.GetPings()) == nil, "ping expiry")
deliver(oldPing); flush()
check(next(G.GetPings()) == nil, "expired old ping cannot resurrect")
check(not H.SendPing("terrain", nil, { x = 0/0, y = 0, z = 0 }), "NaN ground rejected")
check(not H.RequestRescue(), "craft is not a pilot")
check(G.RequestRescue(), "guest pilot requests")
local requestPackets = queue; queue = {}
for _, p in ipairs(requestPackets) do if p.to == 10 then deliver(p) end end
queue = {} -- Friend has not seen this request.
check(H.Respond(20, 1), "host responds")
local responses = queue; queue = {}
for _, p in ipairs(responses) do deliver(p) end
flush()
check(G.GetRequests()[20].status == "Help on the way", "requester sees response")
check(not F.GetRequests()[20], "response cannot invent missing request")
for _, p in ipairs(requestPackets) do if p.to == 30 then deliver(p) end end
flush(); advance(0.7); flush()
check(F.GetRequests()[20].status == "Help on the way", "overtaken request receives retried response")
check(not G.Respond(30, 1), "guest cannot acknowledge as host")
local responsePacket = responses[1]
local spoof = { unpack(responsePacket.args) }; spoof[4] = registry[30].handle
G.Receive(30, "J", unpack(spoof)); flush()
check(G.GetRequests()[20].status == "Help on the way", "host spoof rejected")
check(G.CancelRescue(), "cancel request"); flush()
check(not H.GetRequests()[20] and not F.GetRequests()[20], "cancel replicated")
for _, p in ipairs(requestPackets) do deliver(p) end
flush()
check(not H.GetRequests()[20] and not F.GetRequests()[20], "cancelled request cannot resurrect")
advance(3); flush()
check(G.RequestRescue(), "second request"); flush()
registry[20].handle = { valid = true, pilot = false }
advance(0.1); flush()
check(not H.GetRequests()[20] and not G.GetRequests()[20], "boarding clears requests on all peers")
check(G.SendPing("object", objects[9]), "guest object ping"); flush()
check(H.GetPings()[20].handle == objects[9], "object handles passed unchanged")
check(not peers[10].target, "receiving ping never steals target")
check(H.TargetPing(20) and peers[10].target == objects[9], "explicit target action")
objects[9].valid = false; advance(0.1)
check(not H.GetPings()[20], "destroyed object marker removed")
before = #messages
H.Receive(99, "J", 1, 1, 100, {}, 0, 0, false, 0, 0, 0, 2)
H.Receive(20, "J", 1, 1, 100, false, 0, 0, false, 0, 0, 0, 2)
check(#messages == before, "unknown sender / invalid handle ignored")
check(F.SendPing("terrain", nil, { x = 4, y = 0, z = 5 }), "departing player ping"); flush()
registry[30] = nil; advance(0.1)
check(not H.GetPings()[30], "departure clears marker")
H.Reset(false)
check(not H.IsActive() and not H.SendPing("terrain", nil, { x = 0, y = 0, z = 0 }), "solo inactive")
print("CRCoopComms: " .. checks .. " checks passed")
