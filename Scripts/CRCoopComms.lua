-- Co-op comms: pings, help calls, team status, rescue dispatch, recall and
-- unit hand-off. Every world change runs on the machine that owns the object:
-- a guest moves only its own craft; a rescue is the host's native CMD_RESCUE
-- order (RescueTask drives to the pilot and its AI pilot bails out within
-- 30 m, so the guest boards through the stock hop-in handoff); a hand-off
-- rebuilds the unit on the receiver before the giver removes its original.
-- SetLocal is never used.
local M = {}
local unpackArgs = unpack or table.unpack
local VERSION, CHANNEL = 2, "J"
local PING, REQUEST, CANCEL, RESPONSE, RECEIPT = 1, 2, 3, 4, 5
local STATUS, DISPATCH, RECALL, GIVE, TAKEN = 6, 7, 8, 9, 10
M.RESCUE, M.SUPPLY = 1, 2
M.HELP_COOLDOWN, M.NO_ANSWER_AFTER, M.SUPPLY_TIMEOUT = 20, 15, 45
local STATUS_PERIOD, MARKER_PERIOD = 2, 1
local ARRIVE_RANGE, GIVE_TIMEOUT = 35, 8
-- Production units never change hands.
local PRODUCTION = { recycler = true, factory = true, armory = true, constructionrig = true }
local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < 10000000
end
local function integer(n)
    return finite(n) and n >= 1 and n <= 2147483647 and n == math.floor(n)
end
local function clean(s)
    return tostring(s or "Player"):gsub("[%c]", " "):sub(1, 32)
end
local function percent(f)
    if not finite(f) then return 0 end
    return math.max(0, math.min(100, math.floor(f * 100 + 0.5)))
end
-- hp and ammo (0-100 each) share one wire number: hp * 1000 + ammo.
local function encode(hp, ammo) return hp * 1000 + ammo end
local function decode(v) return math.floor(v / 1000), v % 1000 end
M.Encode, M.Decode = encode, decode

function M.Create(d)
    local service = {}
    local pings, requests, seen, outbox = {}, {}, {}, {}
    local statuses, dispatches, gives, taken, marked = {}, {}, {}, {}, {}
    local seq, nextPing, nextRequest, revision = 0, 0, 0, 0
    local nextStatus, nextMarkers, lastStatus = 0, 0, nil
    local enabled, markers = false, true
    local function now() return d.time() end
    local function changed() revision = revision + 1 end
    local function valid(h)
        if h == nil or h == false then return false end
        local ok, result = pcall(d.valid, h)
        return ok and result == true
    end
    local function call(name, ...)
        if type(d[name]) ~= "function" then return nil end
        local ok, a = pcall(d[name], ...)
        if ok then return a end
    end
    local function player(id)
        local p = d.players()[id]
        return p and d.humanTeam(p.team) and not p.lateJoin and p or nil
    end
    local function say(text) if d.message then d.message("[CO-OP] " .. text) end end
    local function notify(text) say(text); changed() end
    local function position(h)
        if valid(h) then return d.position(h) end
    end
    local function coordinates(v)
        return v and finite(v.x) and finite(v.y) and finite(v.z)
    end
    local function onFoot(id)
        local p = player(id)
        return p ~= nil and valid(p.handle) and d.person(p.handle) == true
    end
    local function critical(id)
        local st = statuses[id]
        return st ~= nil and not onFoot(id) and (st.hp <= 25 or st.ammo <= 10)
    end
    local function packet(op, subject, subjectRevision, h, pos, value)
        seq = seq + 1
        return { VERSION, op, seq, d.localHandle(), subject or 0, subjectRevision or 0,
            h or false, pos and pos.x or 0, pos and pos.y or 0, pos and pos.z or 0, value or 0 }
    end
    local function send(to, p)
        -- false is an on-wire placeholder for an absent handle, never a table.
        d.send(to, CHANNEL, unpackArgs(p, 1, 11))
    end
    -- Guests ordered by id, host excluded: a recall spreads them on a ring.
    local function guestOrdinal(id)
        local ids, players = {}, d.players()
        for other, p in pairs(players) do
            if player(other) and p.team ~= d.leaderTeam() then ids[#ids + 1] = other end
        end
        table.sort(ids)
        for i, other in ipairs(ids) do if other == id then return i end end
        return 1
    end
    -- A unit can change hands only from the machine that owns it.
    function service.CanGive(h)
        local me = player(d.localId())
        if not me or not valid(h) or h == d.localHandle() then return false end
        if call("isLocal", h) ~= true or call("team", h) ~= me.team then return false end
        if call("isCraft", h) ~= true or d.person(h) then return false end
        return not PRODUCTION[tostring(call("classLabel", h) or "")]
    end
    local function takeUnit(from, h, value)
        if taken[h] then return end
        local me = player(d.localId())
        local odf, xf, label = call("odf", h), call("transform", h), call("classLabel", h)
        if not me or not valid(h) or not odf or not xf or PRODUCTION[tostring(label or "")] then
            say("Could not take that unit.")
            return
        end
        local copy = call("spawn", odf, me.team, xf)
        if not valid(copy) then say("Could not take that unit."); return end
        taken[h] = true
        local hp, ammo = decode(value)
        call("setHealth", copy, hp / 100)
        call("setAmmo", copy, ammo / 100)
        service.Publish(packet(TAKEN, from, nil, h))
    end
    local function apply(from, p)
        local op, number, origin, subject, subjectRevision = p[2], p[3], p[4], p[5], p[6]
        local h, value = p[7], p[11]
        local who = player(from)
        local me = d.localId()
        if op == PING then
            local old = pings[from]
            if old and number <= old.seq then return end
            pings[from] = { sender = from, seq = number, handle = value == 1 and h or nil,
                position = { x = p[8], y = p[9], z = p[10] }, expires = now() + 10,
                name = clean(who.name), kind = value == 1 and "object" or "terrain" }
            notify(clean(who.name) .. (value == 1 and " marked a target." or " marked a spot."))
        elseif op == REQUEST then
            local old = requests[from]
            if old and number <= old.seq then return end
            local kind = value == M.SUPPLY and M.SUPPLY or M.RESCUE
            requests[from] = { sender = from, seq = number, pilot = origin, kind = kind,
                created = now(), name = clean(who.name), status = "Requested" }
            notify(clean(who.name) .. (kind == M.RESCUE and " is on foot and needs a ride!" or " needs supplies!") ..
                (d.authority and d.authority() and " (CO-OP page)" or ""))
        elseif op == CANCEL then
            local old = requests[from]
            if old and old.seq == subjectRevision then
                requests[from] = nil
                notify(clean(who.name) .. " no longer needs help.")
            end
        elseif op == RESPONSE then
            local request = requests[subject]
            if request and request.seq == subjectRevision and request.pilot == h and
                (not request.responseSeq or number > request.responseSeq) then
                request.responseSeq = number
                request.status = value == 1 and "Help on the way" or "No craft available"
                local what = request.kind == M.SUPPLY and "supplies" or "a ride"
                notify(value == 1 and "Host: " .. what .. " coming for " .. request.name .. "."
                    or "Host: no " .. (request.kind == M.SUPPLY and "supplies" or "ride") ..
                        " for " .. request.name .. " right now.")
            end
        elseif op == STATUS then
            local hp, ammo = decode(value)
            local old = statuses[from]
            if old and number <= old.seq then return end
            if not old or old.hp ~= hp or old.ammo ~= ammo then changed() end
            statuses[from] = { seq = number, hp = hp, ammo = ammo }
        elseif op == DISPATCH then
            local target = player(subject)
            if not target then return end
            local request = requests[subject]
            if request and value == 1 then request.status = "Help on the way" end
            if subject == me then
                notify(value == 1 and "The host is sending you a ride. Stay put."
                    or "Your ride is here. Get in!")
            elseif value == 1 then
                notify("Host sent a ride to " .. clean(target.name) .. ".")
            end
        elseif op == RECALL then
            if from ~= me and coordinates({ x = p[8], y = p[9], z = p[10] }) then
                call("recall", { x = p[8], y = p[9], z = p[10] }, guestOrdinal(me))
            end
            notify(from == me and "Pulled everyone to you." or "The host pulled everyone to their position.")
        elseif op == GIVE then
            local target = player(subject)
            if not target then return end
            if subject == me then
                notify(clean(who.name) .. " gave you a unit.")
                takeUnit(from, h, value)
            elseif from ~= me then
                notify(clean(who.name) .. " gave a unit to " .. clean(target.name) .. ".")
            end
        elseif op == TAKEN then
            if subject == me and gives[h] then
                gives[h] = nil
                call("remove", h)
                changed()
            end
        end
    end
    function service.Publish(p)
        local id = d.localId()
        if not player(id) then return false, "Still connecting. Try again in a moment." end
        apply(id, p)
        for to in pairs(d.players()) do
            if to ~= id and player(to) then
                send(to, p)
                if p[2] ~= STATUS then
                    outbox[tostring(p[3]) .. ":" .. tostring(to)] = {
                        to = to, packet = p, next = now() + 0.6, deadline = now() + 5 }
                end
            end
        end
        return true
    end
    local publish = service.Publish
    function service.Reset(active)
        pings, requests, seen, outbox = {}, {}, {}, {}
        statuses, dispatches, gives, taken, marked = {}, {}, {}, {}, {}
        seq, nextPing, nextRequest = 0, 0, 0
        nextStatus, nextMarkers, lastStatus = 0, 0, nil
        enabled = active == true
        changed()
    end
    function service.IsActive() return enabled and d.network() end
    function service.GetRevision() return revision end
    function service.GetPings() return pings end
    function service.GetRequests() return requests end
    function service.GetStatus(id) return statuses[id] end
    function service.IsOnFoot(id) return onFoot(id) end
    function service.IsCritical(id) return critical(id) end
    function service.GetDispatches() return dispatches end
    function service.MarkersOn() return markers end
    function service.SetMarkers(on) markers = on == true; nextMarkers = 0; changed() end
    -- Short status word for the PDA team list and the HUD markers.
    function service.Describe(id)
        local request = requests[id]
        if request then
            if request.status == "Help on the way" then
                return request.kind == M.SUPPLY and "supplies coming" or "ride coming"
            end
            return request.kind == M.SUPPLY and "NEEDS SUPPLIES" or "NEEDS A RIDE"
        end
        if onFoot(id) then return "on foot" end
        local st = statuses[id]
        if not st then return "" end
        return string.format("H%d A%d%s", st.hp, st.ammo, critical(id) and " !" or "")
    end
    function service.SendPing(kind, h, pos)
        if not service.IsActive() or not d.ready() then return false, "Still connecting. Try again in a moment." end
        if now() < nextPing then return false, "Wait a moment before marking again." end
        if kind == "object" then
            if not valid(h) then return false, "That target is gone." end
            pos = position(h)
        elseif kind ~= "terrain" then return false, "Aim at something first." end
        if not coordinates(pos) then return false, "Aim at the ground or a target." end
        nextPing = now() + 1.5
        return publish(packet(PING, nil, nil, kind == "object" and h or nil, pos, kind == "object" and 1 or 2))
    end
    -- On foot: ask for a ride. In a vehicle: ask for supplies.
    function service.CallForHelp()
        if not service.IsActive() or not d.ready() then return false, "Still connecting. Try again in a moment." end
        if d.authority() then return false, "You are the host." end
        local id, h = d.localId(), d.localHandle()
        if not valid(h) then return false, "You have no craft right now." end
        if requests[id] then return false, "Your call for help is still open." end
        local wait = math.ceil(nextRequest - now())
        if wait > 0 then return false, "Wait " .. wait .. "s before calling again." end
        nextRequest = now() + M.HELP_COOLDOWN
        return publish(packet(REQUEST, nil, nil, nil, nil, d.person(h) and M.RESCUE or M.SUPPLY))
    end
    function service.RequestRescue()
        if not service.IsActive() or not d.ready() then return false, "Still connecting. Try again in a moment." end
        local id, h = d.localId(), d.localHandle()
        if not valid(h) or not d.person(h) then return false, "You can only call for a ride while on foot." end
        if requests[id] then return false, "Your call for help is still open." end
        if now() < nextRequest then return false, "Wait a moment before calling again." end
        nextRequest = now() + 2
        return publish(packet(REQUEST, nil, nil, nil, nil, M.RESCUE))
    end
    function service.CancelRescue()
        local request = requests[d.localId()]
        if not service.IsActive() or not request then return false, "You have no open call for help." end
        return publish(packet(CANCEL, nil, request.seq))
    end
    function service.Respond(subject, response)
        local request = requests[subject]
        if not service.IsActive() or not d.authority() then return false, "Only the host can answer." end
        if not request then return false, "They no longer need help." end
        if response ~= 1 and response ~= 2 then return false, "Unknown response." end
        return publish(packet(RESPONSE, subject, request.seq, request.pilot, nil, response))
    end
    function service.TargetPing(subject)
        local ping = pings[subject]
        if not service.IsActive() or not ping or ping.kind ~= "object" or not valid(ping.handle) then
            return false, "That mark is gone."
        end
        d.target(ping.handle)
        return true
    end
    -- Host: order one of its own craft to pick up a guest on foot with the
    -- stock rescue command. The engine does the rest: drive, bail out, board.
    function service.Dispatch(craft, subject)
        if not service.IsActive() or not d.authority() then return false, "Only the host can send a ride." end
        if not service.CanGive(craft) then return false, "Select one of your own vehicles first." end
        if not onFoot(subject) then return false, "That player is not on foot." end
        for other, job in pairs(dispatches) do
            if job.craft == craft then dispatches[other] = nil end
        end
        local ok = pcall(d.rescue, craft, player(subject).handle)
        if not ok then return false, "That vehicle cannot do a pickup." end
        dispatches[subject] = { craft = craft }
        return publish(packet(DISPATCH, subject, nil, craft, nil, 1))
    end
    function service.Recall()
        if not service.IsActive() or not d.authority() then return false, "Only the host can do that." end
        local pos = position(d.localHandle())
        if not coordinates(pos) then return false, "You have no craft right now." end
        return publish(packet(RECALL, nil, nil, nil, pos))
    end
    function service.Give(h, subject)
        if not service.IsActive() or not d.ready() then return false, "Still connecting. Try again in a moment." end
        if subject == d.localId() or not player(subject) then return false, "Pick a teammate." end
        if not service.CanGive(h) then return false, "You can only give your own units (not production units)." end
        if gives[h] then return false, "That unit is already being handed over." end
        gives[h] = { to = subject, deadline = now() + GIVE_TIMEOUT }
        local value = encode(percent(call("health", h)), percent(call("ammo", h)))
        return publish(packet(GIVE, subject, nil, h, nil, value))
    end
    function service.Receive(from, channel, ...)
        if channel ~= CHANNEL then return false end
        if not service.IsActive() then return true end
        local p = { ... }
        local who, op = player(from), p[2]
        if not who or from == d.localId() or p[1] ~= VERSION or not integer(p[3]) or
            not valid(p[4]) or who.handle ~= p[4] then return true end
        if op == RECEIPT then
            local key = tostring(p[3]) .. ":" .. tostring(from)
            local job = outbox[key]
            if job and p[11] == job.packet[2] then outbox[key] = nil end
            return true
        end
        if op == STATUS then
            -- Periodic and unacknowledged: a lost one is replaced by the next.
            if finite(p[11]) and p[11] >= 0 and p[11] < 1000000 then apply(from, p) end
            return true
        end
        if not integer(op) or op > TAKEN then return true end
        local leader = who.team == d.leaderTeam()
        if op == PING then
            if (p[11] ~= 1 and p[11] ~= 2) or not finite(p[8]) or not finite(p[9]) or not finite(p[10]) then return true end
            if p[11] == 1 and not valid(p[7]) then return true end
        elseif op == REQUEST then
            local person = d.person(p[4])
            if p[11] == M.SUPPLY then
                if person then return true end
            elseif not person then return true end
        elseif op == CANCEL then
            if not integer(p[6]) then return true end
        elseif op == RESPONSE then
            if not leader or not integer(p[5]) or not integer(p[6]) or
                not player(p[5]) or not valid(p[7]) or (p[11] ~= 1 and p[11] ~= 2) then return true end
            local request = requests[p[5]]
            local cancelled = seen[p[5]] and seen[p[5]].cancelledThrough or 0
            -- A response can overtake its request. Withhold the receipt so the
            -- sender retries after the missing request arrives.
            if not request and cancelled < p[6] then return true end
            if request and request.seq < p[6] then return true end
        elseif op == DISPATCH then
            if not leader or not integer(p[5]) or (p[11] ~= 1 and p[11] ~= 2) then return true end
        elseif op == RECALL then
            if not leader or not finite(p[8]) or not finite(p[9]) or not finite(p[10]) then return true end
        elseif op == GIVE then
            if not integer(p[5]) or not valid(p[7]) or not finite(p[11]) or p[11] < 0 then return true end
        elseif op == TAKEN then
            if not integer(p[5]) or p[7] == false then return true end
        end
        local receipt = { VERSION, RECEIPT, p[3], d.localHandle(), 0, 0, false, 0, 0, 0, op }
        send(from, receipt)
        if not seen[from] or seen[from].actor ~= p[4] then
            seen[from] = { actor = p[4], highWater = {} }
        end
        -- Each op has its own high-water mark; hand-offs and dispatches are
        -- tracked per unit or per player so one cannot shadow another.
        local key = tostring(op)
        if op == RESPONSE or op == DISPATCH then key = key .. ":" .. tostring(p[5])
        elseif op == GIVE or op == TAKEN then key = key .. ":" .. tostring(p[7]) end
        if p[3] <= (seen[from].highWater[key] or 0) then return true end
        seen[from].highWater[key] = p[3]
        -- A newer cancellation must not let a delayed request resurrect the
        -- same request revision.
        if op == CANCEL then
            seen[from].cancelledThrough = math.max(seen[from].cancelledThrough or 0, p[6])
        elseif op == REQUEST and p[3] <= (seen[from].cancelledThrough or 0) then return true end
        apply(from, p)
        return true
    end
    local function distance(a, b)
        if not coordinates(a) or not coordinates(b) then return math.huge end
        local dx, dz = a.x - b.x, a.z - b.z
        return math.sqrt(dx * dx + dz * dz)
    end
    local function updateMarkers(time)
        if time < nextMarkers then return end
        nextMarkers = time + MARKER_PERIOD
        local me = d.localId()
        for id, p in pairs(d.players()) do
            local h = player(id) and id ~= me and valid(p.handle) and p.handle or nil
            if marked[id] and marked[id] ~= h then
                if valid(marked[id]) then call("objective", marked[id], nil, clean(p.name)) end
                marked[id] = nil
            end
            if h and markers then
                local word = service.Describe(id)
                call("objective", h, clean(p.name) .. (word ~= "" and "  " .. word or ""), clean(p.name))
                marked[id] = h
            elseif h and marked[id] then
                call("objective", h, nil, clean(p.name))
                marked[id] = nil
            end
        end
    end
    function service.Update()
        if not service.IsActive() then return end
        local time = now()
        local me = d.localId()
        for id, ping in pairs(pings) do
            if not player(id) or time >= ping.expires or (ping.handle and not valid(ping.handle)) then
                pings[id] = nil; changed()
            elseif ping.handle then
                local pos = position(ping.handle)
                if coordinates(pos) then ping.position = { x = pos.x, y = pos.y, z = pos.z } end
            end
        end
        for id, request in pairs(requests) do
            local who = player(id)
            local gone = not who or who.handle ~= request.pilot or not valid(request.pilot)
            if not gone and request.kind == M.SUPPLY then
                gone = d.person(request.pilot) or
                    (time - request.created >= M.SUPPLY_TIMEOUT and not critical(id))
                if gone and id == me then say("Your supply call timed out.") end
            elseif not gone then
                gone = not d.person(request.pilot)
            end
            if gone then
                requests[id] = nil; changed()
            elseif id == me and request.status == "Requested" and not request.warned and
                time - request.created >= M.NO_ANSWER_AFTER then
                request.warned = true
                notify("No answer from the host yet. Your call is still open.")
            end
        end
        -- Own status, broadcast every couple of seconds (and kept locally).
        local own = player(me) and d.localHandle()
        if time >= nextStatus and valid(own) then
            nextStatus = time + STATUS_PERIOD
            local value = encode(percent(call("health", own)), percent(call("ammo", own)))
            if value ~= lastStatus or not statuses[me] then
                lastStatus = value
                publish(packet(STATUS, nil, nil, nil, nil, value))
            else
                -- Unchanged: still resend so late peers learn it, without
                -- touching our own record.
                local p = packet(STATUS, nil, nil, nil, nil, value)
                for to in pairs(d.players()) do
                    if to ~= me and player(to) then send(to, p) end
                end
            end
        end
        for subject, job in pairs(dispatches) do
            local target = player(subject)
            -- The guest boarding (no longer on foot) or the craft dying ends it.
            if not target or not valid(job.craft) or not onFoot(subject) then
                dispatches[subject] = nil; changed()
            elseif not job.arrived and
                distance(position(job.craft), position(target.handle)) <= ARRIVE_RANGE then
                job.arrived = true
                publish(packet(DISPATCH, subject, nil, job.craft, nil, 2))
            end
        end
        for h, job in pairs(gives) do
            if time >= job.deadline then
                gives[h] = nil
                notify("Hand-off failed. You keep the unit.")
            end
        end
        for id in pairs(seen) do
            if not player(id) then seen[id] = nil end
        end
        for id in pairs(statuses) do
            if not player(id) then statuses[id] = nil end
        end
        for key, job in pairs(outbox) do
            if time >= job.deadline or not player(job.to) then outbox[key] = nil
            elseif time >= job.next then send(job.to, job.packet); job.next = time + 0.6 end
        end
        updateMarkers(time)
    end
    return service
end
return M
