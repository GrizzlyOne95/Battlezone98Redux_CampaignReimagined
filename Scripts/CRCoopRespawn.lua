-- Co-op respawn placement. Native MultST respawns a player as a pilot at the
-- team's start location (50 m up, +-10 m), which can be far from the story
-- after a long mission. Each client watches its own player handle and, after
-- a respawn, moves the new handle (which it owns, so the move replicates) to
-- the first of:
--   1. a living teammate whose handle has been settled for a while
--      (so two players who die together do not follow each other to spawn);
--   2. the mission's rally point for the current phase, if it declared one;
--   3. this player's last safe position (alive, settled, no enemy near,
--      recorded well before the death);
--   4. otherwise the native spawn is kept.
-- A respawn is the first new player handle after a native life was lost
-- (d.nativeLives() dropped); ejects and hop-outs cost no life. Without a lives
-- readout, a new handle far from a dead old one counts instead.
--
-- Lives are counted here, not natively (native lives stay high: at zero MultST
-- drops the player out of the match and they cannot rejoin). A player starts
-- with d.lives() lives including the current one; each respawn uses one. A
-- respawn with none left calls d.outOfLives() instead of placing the player,
-- and the mission fails for everyone.
local M = {}

M.RESPAWN_DISTANCE = 150     -- fallback: a new handle this far from a dead one is a respawn
M.TEAMMATE_SETTLED = 8       -- seconds a teammate's handle must be unchanged
M.SAFE_INTERVAL = 2          -- seconds between safe-position samples
M.SAFE_ENEMY_RADIUS = 200
M.SAFE_MIN_AGE = 15          -- a safe sample must predate the death by this much
M.SAFE_KEEP = 16
M.PLACE_MIN, M.PLACE_MAX = 30, 50

local function distance2d(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

function M.Create(d)
    local service = {}
    local me = { handle = nil, pos = nil, since = 0 }
    local peers = {}           -- player id -> { handle, since }
    local safe = {}            -- { t, pos } oldest first
    local nextSafe = 0
    local rally = {}           -- phase -> label/path name or position
    local respawns = 0

    local function valid(h) return h ~= nil and d.valid(h) end
    local function alive(h) return valid(h) and d.alive(h) end

    function service.Reset()
        me = { handle = nil, pos = nil, since = 0 }
        peers, safe, nextSafe, respawns = {}, {}, 0, 0
        service.lastRespawn = nil
    end

    -- points: { [phase] = "path_or_label" | vector }. The highest phase not
    -- above the current mission phase wins.
    function service.SetRallyPoints(points)
        rally = type(points) == "table" and points or {}
    end

    local function rallyPosition()
        local best, bestPhase = nil, -math.huge
        local phase = d.phase()
        for p, where in pairs(rally) do
            if type(p) == "number" and p <= phase and p > bestPhase then best, bestPhase = where, p end
        end
        if best == nil then return nil end
        if type(best) == "table" then return best end
        local ok, pos = pcall(d.position, best)
        return ok and pos or nil
    end

    local function enemyNear(pos, radius)
        for h in d.allCraft() do
            local team = d.team(h)
            if team ~= 0 and not d.humanTeam(team) and alive(h) then
                local p = d.position(h)
                if p and distance2d(p, pos) < radius then return true end
            end
        end
        return false
    end

    local function teammateTarget(now, deathPos)
        local best, bestDist, bestName
        for id, p in pairs(d.players()) do
            local peer = peers[id]
            if id ~= d.localId() and d.humanTeam(p.team) and peer and alive(peer.handle) and
                now - peer.since >= M.TEAMMATE_SETTLED then
                local pos = d.position(peer.handle)
                local dist = deathPos and distance2d(pos, deathPos) or 0
                if pos and (not best or dist < bestDist) then best, bestDist, bestName = pos, dist, p.name end
            end
        end
        return best, bestName
    end

    local function safeTarget(deathTime)
        for i = #safe, 1, -1 do
            if deathTime - safe[i].t >= M.SAFE_MIN_AGE then return safe[i].pos end
        end
    end

    local function place(h, around)
        local pos = d.near(around, M.PLACE_MIN, M.PLACE_MAX)
        pos.y = d.ground(pos) + 2
        d.move(h, pos)
        return pos
    end

    -- Returns a record of what happened on a respawn (for logs/tests), else nil.
    local function onRespawn(h, now)
        respawns = respawns + 1
        local left = d.lives() - respawns
        if left <= 0 then
            d.outOfLives()
            return { how = "out", lives = 0 }
        end
        local deathPos, deathTime = me.pos, me.lastAliveAt or now
        local target, who = teammateTarget(now, deathPos)
        local how = target and "teammate" or nil
        if not target then target = rallyPosition(); how = target and "rally" or nil end
        if not target then target = safeTarget(deathTime); how = target and "safe" or nil end
        local record = { how = how or "spawn", who = who, lives = left }
        if target then record.pos = place(h, target) end
        local where = how == "teammate" and ("near " .. tostring(who or "your teammate"))
            or how == "rally" and "at the rally point" or how == "safe" and "at your last safe position"
            or "at the drop zone"
        d.message(string.format("[CO-OP] Respawned %s. Lives left: %d.", where, left))
        return record
    end

    function service.Update()
        if not d.network() then return end
        local now = d.time()

        -- Teammates: note when each handle last changed.
        for id, p in pairs(d.players()) do
            if id ~= d.localId() then
                local peer = peers[id]
                if not peer or peer.handle ~= p.handle then peers[id] = { handle = p.handle, since = now } end
            end
        end

        -- A death costs a native life (Net::KillPlayer); the next new handle is
        -- the respawn, wherever it appears (dying near the start is common).
        local nativeLives = d.nativeLives and d.nativeLives() or nil
        if nativeLives and me.nativeLives and nativeLives < me.nativeLives then me.diedPending = true end
        if nativeLives then me.nativeLives = nativeLives end

        local h = d.localHandle()
        if not valid(h) then return end
        local pos = d.position(h)
        local record
        if h ~= me.handle then
            local old, oldPos = me.handle, me.pos
            local respawned
            if nativeLives then
                respawned = me.diedPending and old ~= nil
            else
                -- No lives readout: only a far-away new handle after a death counts.
                respawned = old ~= nil and oldPos and not alive(old) and distance2d(pos, oldPos) > M.RESPAWN_DISTANCE
            end
            me.diedPending = false
            if respawned then
                record = onRespawn(h, now)
                pos = record.pos or pos
            end
            me.handle, me.since = h, now
        end
        if alive(h) then me.pos, me.lastAliveAt = pos, now end

        if now >= nextSafe then
            nextSafe = now + M.SAFE_INTERVAL
            if alive(h) and now - me.since >= M.TEAMMATE_SETTLED and not enemyNear(pos, M.SAFE_ENEMY_RADIUS) then
                safe[#safe + 1] = { t = now, pos = pos }
                if #safe > M.SAFE_KEEP then table.remove(safe, 1) end
            end
        end
        if record then service.lastRespawn = record end
    end

    function service.GetState()
        return { handleSince = me.since, safeCount = #safe, respawns = respawns,
            livesLeft = d.lives() - respawns, lastRespawn = service.lastRespawn }
    end

    return service
end
return M
