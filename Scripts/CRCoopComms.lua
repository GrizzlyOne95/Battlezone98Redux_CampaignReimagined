-- Presentation-only co-op pings and pilot requests. No ownership, spawning,
-- objective flags, mission names, or AI commands are changed by this service.
local M = {}
local unpackArgs = unpack or table.unpack
local VERSION, CHANNEL = 1, "J"
local PING, REQUEST, CANCEL, RESPONSE, RECEIPT = 1, 2, 3, 4, 5
local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < 10000000
end
local function integer(n)
    return finite(n) and n >= 1 and n <= 2147483647 and n == math.floor(n)
end
local function clean(s)
    return tostring(s or "Player"):gsub("[%c]", " "):sub(1, 32)
end

function M.Create(d)
    local service = {}
    local pings, requests, seen, outbox = {}, {}, {}, {}
    local seq, nextPing, nextRequest, revision = 0, 0, 0, 0
    local enabled = false
    local function now() return d.time() end
    local function changed() revision = revision + 1 end
    local function valid(h)
        if h == nil or h == false then return false end
        local ok, result = pcall(d.valid, h)
        return ok and result == true
    end
    local function player(id)
        local p = d.players()[id]
        return p and d.humanTeam(p.team) and not p.lateJoin and p or nil
    end
    local function notify(text)
        if d.message then d.message("[CO-OP] " .. text) end
        changed()
    end
    local function position(h)
        if valid(h) then return d.position(h) end
    end
    local function coordinates(v)
        return v and finite(v.x) and finite(v.y) and finite(v.z)
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
    local function apply(from, p)
        local op, number, origin, subject, subjectRevision = p[2], p[3], p[4], p[5], p[6]
        local h, value = p[7], p[11]
        local who = player(from)
        if op == PING then
            local old = pings[from]
            if old and number <= old.seq then return end
            pings[from] = { sender = from, seq = number, handle = value == 1 and h or nil,
                position = { x = p[8], y = p[9], z = p[10] }, expires = now() + 10,
                name = clean(who.name), kind = value == 1 and "object" or "terrain" }
            notify(clean(who.name) .. " pinged " .. (value == 1 and "an object." or "a location."))
        elseif op == REQUEST then
            local old = requests[from]
            if old and number <= old.seq then return end
            requests[from] = { sender = from, seq = number, pilot = origin,
                name = clean(who.name), status = "Requested" }
            notify(clean(who.name) .. " needs a rescue craft.")
        elseif op == CANCEL then
            local old = requests[from]
            if old and old.seq == subjectRevision then
                requests[from] = nil
                notify(clean(who.name) .. " cancelled their rescue request.")
            end
        elseif op == RESPONSE then
            local request = requests[subject]
            if request and request.seq == subjectRevision and request.pilot == h and
                (not request.responseSeq or number > request.responseSeq) then
                request.responseSeq = number
                request.status = value == 1 and "Help on the way" or "No craft available"
                notify("Host to " .. request.name .. ": " .. request.status .. ".")
            end
        end
    end
    local function publish(p)
        local id = d.localId()
        if not player(id) then return false, "Player registry is not ready." end
        apply(id, p)
        for to in pairs(d.players()) do
            if to ~= id and player(to) then
                send(to, p)
                outbox[tostring(p[3]) .. ":" .. tostring(to)] = {
                    to = to, packet = p, next = now() + 0.6, deadline = now() + 5 }
            end
        end
        return true
    end
    function service.Reset(active)
        pings, requests, seen, outbox = {}, {}, {}, {}
        seq, nextPing, nextRequest = 0, 0, 0
        enabled = active == true
        changed()
    end
    function service.IsActive() return enabled and d.network() end
    function service.GetRevision() return revision end
    function service.GetPings() return pings end
    function service.GetRequests() return requests end
    function service.SendPing(kind, h, pos)
        if not service.IsActive() or not d.ready() then return false, "Co-op is still synchronizing." end
        if now() < nextPing then return false, "Wait a moment before pinging again." end
        if kind == "object" then
            if not valid(h) then return false, "That object is no longer available." end
            pos = position(h)
        elseif kind ~= "terrain" then return false, "Aim at an object or nearby terrain." end
        if not coordinates(pos) then return false, "There is no valid ground hit here." end
        nextPing = now() + 1.5
        return publish(packet(PING, nil, nil, kind == "object" and h or nil, pos, kind == "object" and 1 or 2))
    end
    function service.RequestRescue()
        if not service.IsActive() or not d.ready() then return false, "Co-op is still synchronizing." end
        local id, h = d.localId(), d.localHandle()
        if not valid(h) or not d.person(h) then return false, "Rescue requests are for living pilots." end
        if requests[id] then return false, "Your rescue request is already active." end
        if now() < nextRequest then return false, "Wait a moment before requesting again." end
        nextRequest = now() + 2
        return publish(packet(REQUEST))
    end
    function service.CancelRescue()
        local request = requests[d.localId()]
        if not service.IsActive() or not request then return false, "No active rescue request." end
        return publish(packet(CANCEL, nil, request.seq))
    end
    function service.Respond(subject, response)
        local request = requests[subject]
        if not service.IsActive() or not d.authority() then return false, "Only the campaign host can respond." end
        if not request then return false, "That request is no longer active." end
        if response ~= 1 and response ~= 2 then return false, "Unknown response." end
        return publish(packet(RESPONSE, subject, request.seq, request.pilot, nil, response))
    end
    function service.TargetPing(subject)
        local ping = pings[subject]
        if not service.IsActive() or not ping or ping.kind ~= "object" or not valid(ping.handle) then
            return false, "Choose an active object ping."
        end
        d.target(ping.handle)
        return true
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
        if op ~= PING and op ~= REQUEST and op ~= CANCEL and op ~= RESPONSE then return true end
        if op == PING then
            if (p[11] ~= 1 and p[11] ~= 2) or not finite(p[8]) or not finite(p[9]) or not finite(p[10]) then return true end
            if p[11] == 1 and not valid(p[7]) then return true end
        elseif op == REQUEST then
            if not d.person(p[4]) then return true end
        elseif op == CANCEL then
            if not integer(p[6]) then return true end
        elseif op == RESPONSE then
            if who.team ~= d.leaderTeam() or not integer(p[5]) or not integer(p[6]) or
                not player(p[5]) or not valid(p[7]) or (p[11] ~= 1 and p[11] ~= 2) then return true end
            local request = requests[p[5]]
            local cancelled = seen[p[5]] and seen[p[5]].cancelledThrough or 0
            -- A response can overtake its request. Withhold the receipt so the
            -- sender retries after the missing request arrives.
            if not request and cancelled < p[6] then return true end
            if request and request.seq < p[6] then return true end
        end
        local receipt = { VERSION, RECEIPT, p[3], d.localHandle(), 0, 0, false, 0, 0, 0, op }
        send(from, receipt)
        if not seen[from] or seen[from].actor ~= p[4] then
            seen[from] = { actor = p[4], highWater = {} }
        end
        local key = op == RESPONSE and "response:" .. tostring(p[5]) or tostring(op)
        if p[3] <= (seen[from].highWater[key] or 0) then return true end
        seen[from].highWater[key] = p[3]
        -- Each op has its own high-water mark. A newer cancellation must not
        -- let a delayed request resurrect the same request revision.
        if op == CANCEL then
            seen[from].cancelledThrough = math.max(seen[from].cancelledThrough or 0, p[6])
        elseif op == REQUEST and p[3] <= (seen[from].cancelledThrough or 0) then return true end
        apply(from, p)
        return true
    end
    function service.Update()
        if not service.IsActive() then return end
        local time = now()
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
            if not who or who.handle ~= request.pilot or not valid(request.pilot) or not d.person(request.pilot) then
                requests[id] = nil; changed()
            end
        end
        for id in pairs(seen) do
            if not player(id) then seen[id] = nil end
        end
        for key, job in pairs(outbox) do
            if time >= job.deadline or not player(job.to) then outbox[key] = nil
            elseif time >= job.next then send(job.to, job.packet); job.next = time + 0.6 end
        end
    end
    return service
end
return M
