-- Lua 5.1: help calls, team status, rescue dispatch, recall, unit hand-off and
-- markers, across three independent peers using the real comms service.
-- Native Redux replication (BuildSyncObject, ownership) is qualified live.
local toolsDir = (arg and arg[0] or ""):match([=[^(.*)[/\][^/\]*$]=]) or "."
package.path = toolsDir .. "/../Scripts/?.lua;" .. package.path
local Comms = require("CRCoopComms")
local unpack = unpack or table.unpack
local now, peers, messages, queue, checks = 0, {}, {}, {}, 0
local function check(value, label) assert(value, label); checks = checks + 1 end
local function object(owner, team, fields)
    local h = { valid = true, owner = owner, team = team, pilot = false, craft = true,
        label = "wingman", odf = "avfigh", pos = { x = 0, y = 0, z = 0 }, hp = 1, ammo = 1 }
    for k, v in pairs(fields or {}) do h[k] = v end
    return h
end
local hostCraft = object(10, 1, { pos = { x = 0, y = 0, z = 0 } })
local guestPilot = object(20, 2, { pilot = true, craft = false, label = "person", pos = { x = 300, y = 0, z = 0 } })
local friendTank = object(30, 3, { pos = { x = 50, y = 0, z = 0 }, hp = 0.9, ammo = 0.8 })
local registry = { [10] = { name = "Host", team = 1, handle = hostCraft, ready = true },
    [20] = { name = "Guest", team = 2, handle = guestPilot, ready = true },
    [30] = { name = "Friend", team = 3, handle = friendTank, ready = true } }
local spawned, removed, recalls, objectives, rescues = {}, {}, {}, {}, {}
local spawnFails, adoptWorks = false, false
local function messagesFor(id, pattern)
    for _, m in ipairs(messages) do if m[1] == id and m[2]:find(pattern, 1, true) then return true end end
    return false
end
for id in pairs(registry) do
    local mine = id
    local d = {
        time = function() return now end, players = function() return registry end,
        localId = function() return mine end,
        localHandle = function() return registry[mine] and registry[mine].handle end,
        humanTeam = function(t) return t >= 1 and t <= 4 end,
        valid = function(h) return type(h) == "table" and h.valid == true end,
        person = function(h) return h.pilot end, position = function(h) return h.pos end,
        network = function() return true end, ready = function() return true end,
        authority = function() return mine == 10 end, leaderTeam = function() return 1 end,
        message = function(text) messages[#messages + 1] = { mine, text } end,
        target = function() end,
        send = function(to, channel, ...)
            queue[#queue + 1] = { from = mine, to = to, channel = channel, args = { ... } }
        end,
        health = function(h) return h.hp end, ammo = function(h) return h.ammo end,
        isLocal = function(h) return h.owner == mine end, team = function(h) return h.team end,
        isCraft = function(h) return h.craft end, classLabel = function(h) return h.label end,
        odf = function(h) return h.odf end, transform = function(h) return h.pos end,
        spawn = function(odf, team, xf)
            if spawnFails then return nil end
            local copy = object(mine, team, { odf = odf, pos = xf })
            spawned[#spawned + 1] = copy
            return copy
        end,
        adopt = function(h, team)
            if not adoptWorks then return false end
            h.owner, h.team = mine, team
            return true
        end,
        setHealth = function(h, f) h.hp = f end, setAmmo = function(h, f) h.ammo = f end,
        remove = function(h) h.valid = false; removed[#removed + 1] = h end,
        rescue = function(craft, pilot) rescues[#rescues + 1] = { craft = craft, pilot = pilot } end,
        recall = function(pos, ordinal) recalls[#recalls + 1] = { who = mine, pos = pos, ordinal = ordinal } end,
        objective = function(h, label) objectives[mine .. ":" .. tostring(h)] = label end,
    }
    peers[mine] = { service = Comms.Create(d) }
    peers[mine].service.Reset(true)
end
local function flush()
    while #queue > 0 do
        local packets = queue; queue = {}
        for _, p in ipairs(packets) do
            if peers[p.to] then peers[p.to].service.Receive(p.from, p.channel, unpack(p.args)) end
        end
    end
end
local function advance(dt)
    now = now + dt
    for _, p in pairs(peers) do p.service.Update() end
    flush()
end
local H, G, F = peers[10].service, peers[20].service, peers[30].service

-- Status: everyone learns everyone's hull and ammo.
advance(0.1)
check(H.GetStatus(30).hp == 90 and H.GetStatus(30).ammo == 80, "status reaches the host")
check(G.Describe(30) == "H90 A80" and H.Describe(20) == "on foot", "short status words")

-- Help calls: on foot asks for a ride, in a vehicle for supplies; cooldown; host cannot call.
check(G.CallForHelp(), "guest on foot calls"); flush()
check(H.GetRequests()[20].kind == Comms.RESCUE and H.Describe(20) == "NEEDS A RIDE", "rescue call reaches host")
check(messagesFor(10, "Guest is on foot and needs a ride! (CO-OP page)"), "host told where to answer")
local ok, why = G.CallForHelp()
check(not ok and why == "Your call for help is still open.", "one open call at a time")
ok, why = H.CallForHelp()
check(not ok and why == "You are the host.", "host does not call")
check(F.CallForHelp(), "guest in a vehicle calls"); flush()
check(H.GetRequests()[30].kind == Comms.SUPPLY and G.Describe(30) == "NEEDS SUPPLIES", "supply call")

-- No answer within 15 s: only the caller is told, once.
advance(14); check(not messagesFor(20, "No answer from the host yet"), "no early warning")
advance(1.5)
check(messagesFor(20, "No answer from the host yet") and not messagesFor(10, "No answer"), "caller warned at 15 s")

-- Supply calls time out at 45 s unless the caller is critical.
advance(30)
check(not H.GetRequests()[30] and messagesFor(30, "Your supply call timed out."), "supply call timed out")
local wait
ok, wait = F.CallForHelp()
check(ok, "cooldown long over"); flush()
ok, why = F.CancelRescue(); flush()
check(ok and not H.GetRequests()[30], "cancel")
ok, why = F.CallForHelp()
check(not ok and why:find("before calling again", 1, true), "cooldown after a call")
advance(Comms.HELP_COOLDOWN)
friendTank.hp = 0.1
advance(2.1)
check(H.IsCritical(30) and H.Describe(30):find("!", 1, true), "critical hull flagged")
check(F.CallForHelp(), "critical tank calls"); flush()
advance(60)
check(H.GetRequests()[30], "critical supply call never times out")
friendTank.hp = 0.9
advance(2.1); advance(0.1)
check(not H.GetRequests()[30], "times out once repaired")

-- Rescue dispatch: the host's own craft gets the stock rescue order; the
-- engine drives it, bails its AI pilot out and lets the guest board.
check(not G.Dispatch(hostCraft, 20), "guests cannot dispatch")
local foreign = object(30, 3)
check(not H.Dispatch(foreign, 20), "host cannot send a unit it does not own")
check(not H.Dispatch(friendTank, 30), "only to players on foot")
local ride = object(10, 1, { pos = { x = 0, y = 0, z = 0 } })
local before = #spawned
check(H.Dispatch(ride, 20), "host dispatches"); flush()
check(rescues[1].craft == ride and rescues[1].pilot == guestPilot and #rescues == 1, "one native rescue order")
check(messagesFor(20, "The host is sending you a ride."), "guest told a ride is coming")
check(G.GetRequests()[20].status == "Help on the way" and H.Describe(20) == "ride coming", "request answered by dispatch")
advance(0.1)
check(not messagesFor(20, "Your ride is here"), "not there yet")
ride.pos = { x = 280, y = 0, z = 0 }
advance(0.1); advance(0.1)
check(messagesFor(20, "Your ride is here. Get in!"), "guest told to get in")
check(#spawned == before and ride.valid and #rescues == 1, "no copy, no removal, no re-order")
-- Boarding (the guest's handle becomes the craft) ends the dispatch.
registry[20].handle = ride
advance(0.1)
check(not next(H.GetDispatches()), "boarding ends the dispatch")
registry[20].handle = guestPilot

-- Hand-off between guests: rebuilt by the receiver, original removed by the giver.
local tank = object(30, 3, { hp = 0.5, ammo = 0.25, odf = "avtank", pos = { x = 9, y = 1, z = 9 } })
before = #spawned
check(F.Give(tank, 20), "guest gives a tank"); flush(); advance(0.1)
copy = spawned[#spawned]
check(#spawned == before + 1 and copy.owner == 20 and copy.team == 2 and copy.odf == "avtank", "receiver rebuilt it")
check(copy.hp == 0.5 and copy.ammo == 0.25, "hull and ammo carried over")
check(not tank.valid, "giver removed the original")
check(messagesFor(10, "Friend gave a unit to Guest."), "others told")
local recycler = object(30, 3, { label = "recycler" })
ok, why = F.Give(recycler, 20)
check(not ok and why:find("production", 1, true), "production units stay")
check(not F.Give(object(10, 1), 20), "cannot give someone else's unit")
check(not F.Give(friendTank, 20), "cannot give your own craft")
-- With exu.AdoptObject the receiver takes the real unit; nothing is rebuilt
-- or removed.
adoptWorks = true
local scout = object(30, 3, { odf = "avscout" })
before = #spawned
local removedBefore = #removed
check(F.Give(scout, 20), "guest gives a scout"); flush(); advance(0.1)
check(#spawned == before and #removed == removedBefore and scout.valid, "adopted in place")
check(scout.owner == 20 and scout.team == 2, "receiver owns it on its team")
check(not messagesFor(30, "Hand-off failed"), "giver saw it taken")
adoptWorks = false
-- A receiver that cannot rebuild leaves the unit with the giver.
spawnFails = true
local kept = object(10, 1)
check(H.Give(kept, 30), "host offers a unit"); flush()
advance(9)
check(kept.valid and messagesFor(10, "Hand-off failed. You keep the unit."), "failed hand-off keeps the unit")
spawnFails = false

-- Recall: guests move themselves around the host; the host stays put.
recalls = {}
check(not G.Recall(), "guests cannot recall")
check(H.Recall()); flush()
check(#recalls == 2, "both guests moved")
check(recalls[1].who ~= 10 and recalls[2].who ~= 10 and recalls[1].ordinal ~= recalls[2].ordinal, "spread around the host")

-- Markers: on by default, local to each peer, cleared when switched off.
advance(1.1)
check(objectives["10:" .. tostring(friendTank)] == "Friend  H90 A80", "host sees a guest marker")
check(objectives["30:" .. tostring(friendTank)] == nil, "no marker on yourself")
H.SetMarkers(false); advance(1.1)
check(objectives["10:" .. tostring(friendTank)] == nil and G.MarkersOn(), "host cleared its markers only")

print("CRCoopAssist: " .. checks .. " checks passed")
