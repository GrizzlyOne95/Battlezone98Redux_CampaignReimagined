-- Local, mission-scoped observations of CR control messages. These are not
-- engine packet/byte counts or proof that every simulated object is synchronized.
local M = {}
M.QUIET_AFTER, M.STALLED_AFTER = 3, 10
function M.Create(d)
    local service, peers = {}, {}
    local function now() return d.time() end
    local function record(id)
        if not peers[id] then peers[id] = { sent = 0, received = 0 } end
        return peers[id]
    end
    local function age(at) return at and math.max(0, now() - at) or nil end
    function service.Reset() peers = {} end
    function service.Forget(id) peers[id] = nil end
    function service.Sent(to)
        for id, p in pairs(d.players()) do
            if id ~= d.localId() and d.humanTeam(p.team) and (to == 0 or to == id) then
                record(id).sent = record(id).sent + 1
            end
        end
    end
    function service.Received(id, heartbeat, protocol, admitted, phase)
        if id == d.localId() then return end
        local p = d.players()[id]
        if not p or not d.humanTeam(p.team) then return end
        local r = record(id)
        r.received, r.lastReceived = r.received + 1, now()
        if heartbeat then
            r.lastHeartbeat = now()
            -- Clear optional metadata on a legacy/partial heartbeat; never
            -- retain a prior assertion as current evidence.
            r.protocol = type(protocol) == "number" and protocol or nil
            if type(admitted) == "boolean" then r.admitted = admitted else r.admitted = nil end
            r.phase = type(phase) == "number" and phase >= 0 and phase == math.floor(phase) and phase or nil
        end
    end
    function service.Snapshot()
        local result = { players = {}, phase = d.phase(), ready = d.ready(),
            leaderDeparted = d.leaderDeparted(), protocol = d.protocol,
            quietAfter = M.QUIET_AFTER, stalledAfter = M.STALLED_AFTER }
        local delivery = d.delivery and d.delivery() or { peers = {} }
        for id, p in pairs(d.players()) do
            if d.humanTeam(p.team) then
                local r = peers[id] or {}
                local own = id == d.localId()
                local a = age(r.lastHeartbeat)
                local receiveAge = age(r.lastReceived)
                local appAge = delivery.peers[id] and delivery.peers[id].receiveAge
                if appAge and (not receiveAge or appAge < receiveAge) then receiveAge = appAge end
                local status
                if p.lateJoin then status = "Restart required"
                elseif result.leaderDeparted then status = "Host left"
                elseif not own and r.protocol and r.protocol ~= d.protocol then status = "Protocol mismatch"
                elseif own then status = result.ready and "Synced (local)" or "Syncing (local)"
                elseif receiveAge and receiveAge >= M.STALLED_AFTER then status = "Traffic stalled"
                elseif receiveAge and receiveAge >= M.QUIET_AFTER then status = "No recent traffic"
                elseif a and a >= M.QUIET_AFTER then status = "Heartbeat delayed"
                elseif not d.valid(p.handle) then status = "Player unavailable"
                elseif not a then status = "Syncing"
                elseif r.admitted == false then status = "Syncing"
                elseif r.admitted == nil or r.phase == nil then status = "Readiness unknown"
                elseif r.phase ~= result.phase then status = "Phase differs"
                else status = "Synced" end
                result.players[id] = { id = id, name = p.name, team = p.team,
                    localPlayer = own, host = p.team == d.leaderTeam(), status = status,
                    handleValid = d.valid(p.handle), heartbeatAge = a,
                    receiveAge = receiveAge, sent = r.sent or 0, received = r.received or 0,
                    protocol = own and d.protocol or r.protocol,
                    phase = own and result.phase or r.phase, admitted = r.admitted }
            end
        end
        return result
    end
    return service
end
return M
