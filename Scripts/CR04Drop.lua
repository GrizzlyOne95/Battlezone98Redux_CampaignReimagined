-- Mission 4 opening, single player: two NSDF dropships land beside the base. One carries Recycler
-- Montana and the factory, the other the player and the wingman. The player's controls stay locked
-- (EXU control mask) until the ramps are down, then the cargo drives out the stern ramps and the
-- ships lift off once everyone is clear. Co-op keeps the stock start (the EXU mask stands down in
-- multiplayer, and guest ships belong to their peers).
--
-- Ship art is the prototype avdrop SDF pair: avdropc (ramps shut) flies, avdropo (ramps swing open
-- once, when the object is created) is swapped in at touchdown. Floor collision is snapshotted when a
-- building is added, so a landed ship must be a new object; units cannot path into its footprint, so
-- the AI cargo is pushed along the centreline lanes with SetVelocity (as the avdtest fixture proved).
local Drop = {}

local FLYING, LANDED, POD = "avdropc", "avdropo", "apcamr"
local OWNER = "mission:misn04-dropship"
local FLY_T = 16.0          -- seconds from 320 m up to touchdown
local DELAY = { 0.0, 2.5 }  -- cargo ship first, then the player's ship
local START_UP, START_BACK = 320.0, 260.0
local OPEN_T = 2.6          -- ANIM index 0 is 30 frames at 15 fps; the lips are down by 2.0 s
local HOLD_UP = 6.0         -- carried units ride 1.5 m over the 4.5 m hold floor
local SPEED = 7.0
local LIFT_AFTER = 6.0      -- a ship may leave this long after release, once nobody is within CLEAR_R
local CLEAR_R = 45.0         -- past the ramp lips (40.3 m); stock spots sit 55-75 m out
local SHIP_GAP = 12.0       -- each ship moves this far out from its anchor, sideways (77 m wide hulls)

local api = {}
local function V(x, y, z) return SetVector(x, y, z) end
local function ground(x, z) return (GetTerrainHeightAndNormal(V(x, 0, z))) end
local function flat(a, b) return V(a.x - b.x, 0, a.z - b.z) end
local function len(d) return math.sqrt(d.x * d.x + d.z * d.z) end
local function unit(d) local n = len(d); if n < 1e-3 then return V(1, 0, 0) end; return V(d.x / n, 0, d.z / n) end
local function log(fmt, ...) if api.log then api.log(string.format("[CR04Drop] " .. fmt, ...)) end end
local function alive(h) return h ~= nil and IsValid(h) end

-- point on a ship's frame: S = stern (exit) direction, L = sideways; metres
local function at(ship, along, lat, up)
    local x = ship.x + ship.sx * along + ship.lx * lat
    local z = ship.z + ship.sz * along + ship.lz * lat
    return V(x, up and (ship.y + up) or ground(x, z), z)
end

-- deck height along the centreline lane, from the avdtest drive: hold floor to the hinge at 24 m,
-- then the 16.3 deg ramp down to its lip at 40.3 m
local function deck(ship, along, lat)
    local p = at(ship, along, lat)
    if along <= 24 then p.y = ship.y + 4.5
    elseif along < 40.3 then p.y = math.max(p.y, ship.y + 4.5 - (along - 24) * 0.2925) end
    return p
end

local function range(cx, cz, sx, sz, lx, lz)
    local lo, hi = 1e9, -1e9
    for a = -40, 40, 10 do
        for l = -18, 18, 9 do
            local h = ground(cx + sx * a + lx * l, cz + sz * a + lz * l)
            lo, hi = math.min(lo, h), math.max(hi, h)
        end
    end
    return hi - lo
end

local function blocked(cx, cz, cargo)
    if not ObjectsInRange then return false end
    for h in ObjectsInRange(45, V(cx, ground(cx, cz), cz)) do
        if not cargo[h] and (IsBuilding(h) or IsCraft(h)) then return true end
    end
    return false
end

-- Both ships sit behind their anchors (stock recycler/factory midpoint, stock player spot) with
-- their sterns toward them, so each unit drives straight out of its ramp onto its stock spot.
local function chooseSites(a1, a2, cargo)
    local L = unit(flat(a2, a1))
    local best
    for _, sgn in ipairs({ 1, -1 }) do
        local S = V(L.z * sgn, 0, -L.x * sgn)
        for _, d in ipairs({ 55, 65, 75 }) do
            for _, slide in ipairs({ -20, 0, 20 }) do
                local A = { x = a1.x - S.x * d - L.x * (SHIP_GAP - slide), z = a1.z - S.z * d - L.z * (SHIP_GAP - slide) }
                local B = { x = a2.x - S.x * d + L.x * (SHIP_GAP + slide), z = a2.z - S.z * d + L.z * (SHIP_GAP + slide) }
                local score = range(A.x, A.z, S.x, S.z, L.x, L.z) + range(B.x, B.z, S.x, S.z, L.x, L.z)
                if blocked(A.x, A.z, cargo) or blocked(B.x, B.z, cargo) then score = score + 1000 end
                if not best or score < best.score then
                    best = { score = score, S = S, L = L, d = d, A = A, B = B }
                end
            end
        end
    end
    return best
end

local function shipFrame(c, best)
    return { x = c.x, z = c.z, y = ground(c.x, c.z), sx = best.S.x, sz = best.S.z, lx = best.L.x, lz = best.L.z }
end

local function pose(ship, along, lat, up)
    return BuildDirectionalMatrix(at(ship, along, lat, up), V(ship.sx, 0, ship.sz))
end

local function shipMatrix(ship, height, back)
    local p = V(ship.x + ship.sx * back, ship.y + height, ship.z + ship.sz * back)
    return BuildDirectionalMatrix(p, V(-ship.sx, 0, -ship.sz))   -- the bow (GetFront) faces away from the ramp exit
end

local function pin(ship, c, up)
    if not alive(c.h) then return end
    SetTransform(c.h, pose(ship, c.along, c.lat, up))
    SetVelocity(c.h, V(0, 0, 0))
end

local function lock(on)
    local exu = api.exu
    if not (exu and exu.SetPlayerControlMask) then
        if on then log("control lock unavailable: no EXU control mask") end
        return
    end
    if on then
        if not exu.SetPlayerControlMask(OWNER, exu.CONTROL.ALL) then
            local s = exu.GetPlayerControlState and exu.GetPlayerControlState()
            log("control lock unavailable: %s", tostring(s and s.reason))
        end
    elseif exu.ClearPlayerControlMask then
        exu.ClearPlayerControlMask(OWNER)
    end
end

function Drop.Configure(options)
    api = options or {}
end

-- Start/restart: the mask is not saved and must not outlive the run that set it.
function Drop.Reset()
    lock(false)
end

local function newState()
    local player = GetPlayerHandle()
    local recy, fact = GetHandle("avrecy-1_recycler"), GetHandle("avmuf0_factory")
    local wing = GetHandle("avfigh0_wingman")
    if not (alive(player) and alive(recy) and alive(fact)) then return nil end
    local pr, pf, pp = GetPosition(recy), GetPosition(fact), GetPosition(player)
    local a1 = V((pr.x + pf.x) / 2, 0, (pr.z + pf.z) / 2)
    local cargo = { [player] = true, [recy] = true, [fact] = true }
    if alive(wing) then cargo[wing] = true end
    local best = chooseSites(a1, pp, cargo)
    local s = {
        phase = "fly", t0 = GetTime(), d = best.d,
        ships = {
            { frame = shipFrame(best.A, best), cargo = {
                { h = recy, along = 0, lat = -8 },
                { h = fact, along = 2, lat = 10 } } },
            { frame = shipFrame(best.B, best), cargo = {
                { h = player, along = 6, lat = -7, player = true },
                { h = wing, along = 6, lat = 7 } } },
        },
    }
    log("sites score=%.1f d=%d A=(%.0f,%.0f) B=(%.0f,%.0f) stern=(%.2f,%.2f)", best.score, best.d,
        best.A.x, best.A.z, best.B.x, best.B.z, best.S.x, best.S.z)
    return s
end

local function landShip(s, ship)
    if alive(ship.h) then RemoveObject(ship.h) end
    ship.h = BuildObject(LANDED, 1, shipMatrix(ship.frame, 0, 0))
    ship.landedAt = GetTime()
    for _, c in ipairs(ship.cargo) do
        pin(ship.frame, c, HOLD_UP)
        if alive(c.h) and not c.player then Stop(c.h, 1) end
    end
    log("ship landed odf=%s", tostring(alive(ship.h) and GetOdf(ship.h)))
end

local function release(s)
    if s.camera then
        s.camera = false
        if api.cameraFinish then api.cameraFinish() end
    end
    if alive(s.pod) then RemoveObject(s.pod) end
    s.pod = nil
    lock(false)
    for _, ship in ipairs(s.ships) do
        for _, c in ipairs(ship.cargo) do
            if not c.player and alive(c.h) then
                c.path = { 12, 24, 32, 40.5, 48, s.d }
                c.leg = 1
            end
        end
    end
    s.phase = "drive"
    s.releasedAt = GetTime()
    log("released")
end

local function drive(ship, c)
    if not c.path or not alive(c.h) then c.path = nil; return end
    local f = ship.frame
    local p = GetPosition(c.h)
    local along = (p.x - f.x) * f.sx + (p.z - f.z) * f.sz
    if along >= c.path[c.leg] - 2 then
        c.leg = c.leg + 1
        if c.leg > #c.path then
            c.path = nil
            Stop(c.h, 0)   -- hand the unit back to its AI at its stock spot
            return
        end
    end
    local g = deck(f, c.path[c.leg], c.lat)
    local dir = unit(flat(g, p))
    local v = GetVelocity(c.h)
    SetTransform(c.h, BuildDirectionalMatrix(p, dir))
    SetVelocity(c.h, V(dir.x * SPEED, v.y, dir.z * SPEED))
end

local function clear(ship)
    local f = ship.frame
    for _, c in ipairs(ship.cargo) do
        if c.path then return false end
        if alive(c.h) and len(flat(GetPosition(c.h), V(f.x, 0, f.z))) < CLEAR_R then return false end
    end
    local player = GetPlayerHandle()
    return not (alive(player) and len(flat(GetPosition(player), V(f.x, 0, f.z))) < CLEAR_R)
end

local function cleanup(s)
    for _, ship in ipairs(s.ships or {}) do
        if alive(ship.h) then RemoveObject(ship.h) end
        ship.h = nil
    end
    if alive(s.pod) then RemoveObject(s.pod) end
    s.pod = nil
    if s.camera and api.cameraFinish then api.cameraFinish() end
    s.camera = false
    lock(false)
end

local function begin(M)
    local s = newState()
    if not s then
        log("stock opening: recycler, factory or player missing")
        M.cr04drop = { phase = "done" }
        return
    end
    M.cr04drop = s
    for i, ship in ipairs(s.ships) do
        ship.h = BuildObject(FLYING, 1, shipMatrix(ship.frame, START_UP, START_BACK))
        if not alive(ship.h) then
            log("stock opening: could not build %s", FLYING)
            cleanup(s)
            s.phase = "done"
            return
        end
        ship.delay = DELAY[i]
    end
    local a, b = s.ships[1].frame, s.ships[2].frame
    local mid = { x = (a.x + b.x) / 2, z = (a.z + b.z) / 2 }
    local camX, camZ = mid.x + a.sx * 150, mid.z + a.sz * 150
    s.pod = BuildObject(POD, 0, V(camX, ground(camX, camZ), camZ))
    if alive(s.pod) and api.cameraReady then api.cameraReady(); s.camera = true end
    lock(true)
end

local function fly(s, now)
    local landed = 0
    for _, ship in ipairs(s.ships) do
        local u = math.min(1, math.max(0, (now - s.t0 - ship.delay) / FLY_T))
        local k = 1 - u
        if ship.landedAt then
            landed = landed + 1
        elseif u >= 1 then
            landShip(s, ship)
            landed = landed + 1
        else
            if alive(ship.h) then
                SetTransform(ship.h, shipMatrix(ship.frame, START_UP * k * k * k, START_BACK * k * k))
            end
            local f = ship.frame
            local carried = { x = f.x + f.sx * START_BACK * k * k, y = f.y + START_UP * k * k * k + HOLD_UP,
                              z = f.z + f.sz * START_BACK * k * k }
            for _, c in ipairs(ship.cargo) do
                if alive(c.h) then
                    local p = V(carried.x + f.sx * c.along + f.lx * c.lat, carried.y, carried.z + f.sz * c.along + f.lz * c.lat)
                    SetTransform(c.h, BuildDirectionalMatrix(p, V(f.sx, 0, f.sz)))
                    SetVelocity(c.h, V(0, 0, 0))
                end
            end
        end
    end
    return landed == #s.ships
end

-- Returns true while the stock opening must wait (ships descending, ramps opening).
function Drop.Update(M)
    local s = M.cr04drop
    if s and s.phase == "done" then return false end
    if not s then begin(M); s = M.cr04drop end
    if s.recover then
        -- A save taken mid-intro: Ogre-side ships and the EXU mask did not survive it. Stand
        -- everything down and let the stock opening run with the units wherever they are.
        if AllObjects then
            for h in AllObjects() do
                if IsOdf(h, FLYING) or IsOdf(h, LANDED) then RemoveObject(h) end
            end
        end
        s.ships, s.pod, s.camera = {}, nil, false
        lock(false)
        s.phase, s.recover = "done", nil
        log("recovered after load")
        return false
    end
    if s.phase == "done" then return false end
    local now = GetTime()
    if s.phase == "fly" or s.phase == "open" then
        if s.camera and api.cameraCancelled and api.cameraCancelled() then
            s.t0 = now - FLY_T - 10   -- skip: touch both ships down now
        end
        if s.camera and alive(s.pod) and alive(s.ships[2].h) then
            CameraObject(s.pod, 0, 1800, 0, s.ships[2].h)
        end
        if fly(s, now) then
            s.phase = "open"
            local last = math.max(s.ships[1].landedAt, s.ships[2].landedAt)
            for _, ship in ipairs(s.ships) do
                for _, c in ipairs(ship.cargo) do
                    if alive(c.h) then
                        pin(ship.frame, c, HOLD_UP)
                        if not c.player then Stop(c.h, 1) end
                    end
                end
            end
            if now - last >= OPEN_T then release(s) end
        end
        return s.phase ~= "drive"
    end
    for _, ship in ipairs(s.ships) do
        for _, c in ipairs(ship.cargo) do drive(ship, c) end
        if not ship.liftAt and alive(ship.h) and now - s.releasedAt > LIFT_AFTER and clear(ship) then
            local m = shipMatrix(ship.frame, 0, 0)
            RemoveObject(ship.h)
            ship.h = BuildObject(FLYING, 1, m)
            ship.liftAt = now
            log("ship lifting")
        end
        if ship.liftAt and alive(ship.h) then
            local a = now - ship.liftAt
            local up = 1.5 * a * a
            SetTransform(ship.h, shipMatrix(ship.frame, up, -0.6 * a * a))
            if up > 500 then RemoveObject(ship.h); ship.h = nil end
        end
    end
    local busy = false
    for _, ship in ipairs(s.ships) do
        if alive(ship.h) then busy = true end
        for _, c in ipairs(ship.cargo) do if c.path then busy = true end end
    end
    if not busy then s.phase = "done"; log("done") end
    return false
end

-- Load: the mask is not saved and ship handles cannot be trusted across a save.
function Drop.OnLoad(M)
    local s = M and M.cr04drop
    if s and s.phase ~= "done" then s.recover = true end
end

return Drop
