-- Dropship insertion: NSDF dropships fly in, land, open their stern ramps, let their cargo out and lift off.
-- Mission-agnostic and co-op safe; misn04's opening is the first user (the misn14 Titan drop is meant to be next).
--
-- The mission (the leader) passes the anchors and the cargo: Drop.Begin(state, spec). The plan goes out as numbers
-- on the mission's ordered event stream (DropShip per ship, DropCrew per human, then DropGo) through api.present,
-- which must also apply the event locally. Every pose before the release is a pure function of the plan and the
-- seconds since DropGo (each peer starts its clock when it applies DropGo), so no pose is ever sent:
--   * the LEADER builds and moves the ship objects and the AI cargo it owns, drives that cargo out, lifts the ships;
--   * EVERY peer pins its OWN craft (GetPlayerHandle on that machine) in its hold slot until the release time.
-- Offline the leader is the only peer, so the same code path plays; the EXU control mask locks the player until the
-- release. In network games the mask stands down, so pinning every frame (plus a health top-up) is the hold.
--
-- Technique and measured numbers come from CR04Drop (misn04's single-player prototype) and its avdtest fixture:
--   * Ship art is the prototype avdrop SDF set: avdropc (ramps shut) flies in; avdropo (its ANIM index 0 swings the
--     ramps open once, when the object is created) is swapped in at touchdown; avdropx (same model, ANIM 0 runs
--     open -> shut) is swapped in before lift-off, so the ramps fold up and the ship flies out.
--   * Floor collision is snapshotted when a building is added, so a landed ship must be a NEW object.
--   * Units cannot path into the ship's footprint, so cargo is pinned with SetTransform while carried and pushed
--     down the ramp lanes with SetVelocity once released.
-- Numbers marked "CR guess" are inferences that need a live tune; the rest are CR04Drop's measured ones.
local Drop = {}

Drop.FLYING, Drop.LANDED, Drop.CLOSING, Drop.POD = "avdropc", "avdropo", "avdropx", "apcamr"
-- The mission's event stream must accept exactly these ops (and route them to Drop.Apply).
Drop.OPS = { DropShip = true, DropCrew = true, DropGo = true }

Drop.FLY_T = 16.0          -- s from START_UP to touchdown
Drop.START_UP, Drop.START_BACK = 320.0, 260.0
Drop.OPEN_T = 2.6          -- ANIM index 0 is 30 frames at 15 fps; the lips are down by 2.0 s
Drop.CLOSE_T = 2.4         -- avdropx folds the ramps in the same 2.0 s, then the ship lifts
Drop.HOLD_UP = 6.0         -- carried units ride 1.5 m over the 4.5 m hold floor
Drop.FLOOR = 4.5           -- hold floor over the ground under the hull
Drop.HINGE = 24.0          -- ramp hinge, metres behind the hull centre
Drop.LIP = 40.3            -- ramp lip, metres behind the hull centre (avdtest drive)
Drop.RAMP_SLOPE = 0.2925   -- the 16.3 deg ramp: metres down per metre out
Drop.SPEED = 7.0           -- m/s the AI cargo is pushed down its lane
Drop.LIFT_AFTER = 6.0      -- a ship may leave this long after release, once nobody is within CLEAR_R
Drop.CLEAR_R = 45.0        -- past the ramp lips (40.3 m); stock spots sit 55-75 m out
Drop.SHIP_GAP = 12.0       -- with two anchors each ship moves this far out sideways (77 m wide hulls)
Drop.LIFT_ACCEL = 1.5      -- up = LIFT_ACCEL * a^2 metres, a seconds after lift-off
Drop.LIFT_BACK = -0.6      -- back = LIFT_BACK * a^2 metres (the ship noses forward as it climbs)
Drop.LIFT_GONE = 500.0     -- the climbing ship is removed this high
Drop.CAMERA_OUT = 150.0    -- the camera pod stands this far out from the ships, past the ramps
Drop.CAMERA_UP = 1800      -- CameraObject offset over the pod (cm)
Drop.DRIVE_MAX = 40.0      -- s after release an AI unit still pushing down its lane is handed back      CR guess
Drop.GOAL_T = 15.0         -- s an AI unit off the ramp gets to reach its spot before it is handed back
Drop.MAX_SHIPS = 2
-- Hold lanes. The hold is 35 m wide; each side lane takes 6 tanks nose to tail. Row 1 is CR04Drop's measured
-- player/wingman spot (6 m back, 7 m out); the further rows are 8 m apart.                         CR guess (rows 2-6)
Drop.LANES = { -7, 7 }
Drop.ROWS = { 6, -2, -10, -18, -26, -34 }
Drop.EXIT = 52.0           -- along the lane, where a load puts a still-carried unit down (past the lip)  CR guess
Drop.PATH = { 12, 24, 32, 40.5, 48 }   -- AI lane legs (metres along), then the unit's own spot

local sqrt, max, min, floor = math.sqrt, math.max, math.min, math.floor

-- Pure choreography ----------------------------------------------------------------------------------------------
-- A ship frame: x, z, y (ground) of the landing spot; sx, sz the stern (ramp exit) direction; lx, lz sideways;
-- delay the seconds after DropGo it starts its descent.

-- The j-th automatic hold slot: front row first, alternating lanes. Returns along, lat (nil when the hold is full).
function Drop.Slot(j)
    local row = floor((j - 1) / #Drop.LANES) + 1
    if j < 1 or row > #Drop.ROWS then return nil end
    return Drop.ROWS[row], Drop.LANES[(j - 1) % #Drop.LANES + 1]
end

-- Seconds after DropGo that the ship touches down.
function Drop.Touchdown(ship) return (ship.delay or 0) + Drop.FLY_T end

-- Seconds after DropGo that every ramp is down: the carried craft are released.
function Drop.ReleaseTime(ships, n)
    local last = 0
    for i = 1, n do last = max(last, Drop.Touchdown(ships[i])) end
    return last + Drop.OPEN_T
end

-- "fly" until the touchdown, then "landed".
function Drop.Stage(ship, t)
    if t < Drop.Touchdown(ship) then return "fly" end
    return "landed"
end

-- Height and back-offset (along the stern direction) of the hull centre over its landing spot at time t.
function Drop.Offsets(ship, t)
    local u = min(1, max(0, (t - (ship.delay or 0)) / Drop.FLY_T))
    local k = 1 - u
    return Drop.START_UP * k * k * k, Drop.START_BACK * k * k
end

-- Height and back-offset a seconds after lift-off.
function Drop.LiftOffsets(a)
    return Drop.LIFT_ACCEL * a * a, Drop.LIFT_BACK * a * a
end

-- World position of the hull centre at time t.
function Drop.HullPos(ship, t)
    local up, back = Drop.Offsets(ship, t)
    return ship.x + ship.sx * back, ship.y + up, ship.z + ship.sz * back
end

-- Point on the ship frame: along the stern direction and sideways, `up` over the landing spot or on the ground.
function Drop.At(ship, along, lat, up, ground)
    local x = ship.x + ship.sx * along + ship.lx * lat
    local z = ship.z + ship.sz * along + ship.lz * lat
    return x, up and (ship.y + up) or (ground and ground(x, z) or ship.y), z
end

-- Deck height along a lane: the hold floor to the hinge, then the ramp down to its lip.
function Drop.Deck(ship, along, lat, ground)
    local x, y, z = Drop.At(ship, along, lat, nil, ground)
    if along <= Drop.HINGE then y = ship.y + Drop.FLOOR
    elseif along < Drop.LIP then y = max(y, ship.y + Drop.FLOOR - (along - Drop.HINGE) * Drop.RAMP_SLOPE) end
    return x, y, z
end

-- Where a carried craft rides at time t: its hold slot, travelling with the hull. Returns x, y, z and the heading
-- (a unit vector, x and z): it faces the ramp, so it drives straight out.
function Drop.HoldPos(ship, along, lat, t)
    local up, back = Drop.Offsets(ship, t)
    local x = ship.x + ship.sx * (back + along) + ship.lx * lat
    local z = ship.z + ship.sz * (back + along) + ship.lz * lat
    return x, ship.y + up + Drop.HOLD_UP, z, ship.sx, ship.sz
end

-- Where a carried craft is set down when the drop cannot finish (a load mid-drop): out past the lip on its lane,
-- each row as far behind the first as it rode, so nothing lands on anything else.
function Drop.ExitPos(ship, along, lat, ground)
    return Drop.At(ship, Drop.EXIT + (Drop.ROWS[1] - along), lat, nil, ground)
end

local function flatness(x, z, sx, sz, lx, lz, ground)
    local lo, hi = 1e9, -1e9
    for along = -40, 40, 10 do
        for lat = -18, 18, 9 do
            local h = ground(x + sx * along + lx * lat, z + sz * along + lz * lat)
            lo, hi = min(lo, h), max(hi, h)
        end
    end
    return hi - lo
end

-- Landing sites behind 1 or 2 anchors ({x, z}: where each ship's cargo should end up), sterns toward them, so the
-- cargo drives straight out of the ramp onto its spot. With two anchors the ships stand side by side along the line
-- between them (CR04Drop's layout); with one, `lateral` ({x, z}, default +x) sets that line. The flattest
-- unblocked candidate wins; `blocked(x, z)` (optional) vetoes a site. Deterministic: the same inputs give the
-- same plan. Returns the frames (without delay) and the anchor distance d.
function Drop.Sites(anchors, ground, blocked, lateral)
    local n = #anchors
    local lx, lz
    if n >= 2 then lx, lz = anchors[2].x - anchors[1].x, anchors[2].z - anchors[1].z
    else lx, lz = lateral and lateral.x or 1, lateral and lateral.z or 0 end
    local len = sqrt(lx * lx + lz * lz)
    if len < 1e-3 then lx, lz = 1, 0 else lx, lz = lx / len, lz / len end
    local best
    for _, sgn in ipairs({ 1, -1 }) do
        local sx, sz = lz * sgn, -lx * sgn
        for _, d in ipairs({ 55, 65, 75 }) do
            for _, slide in ipairs({ -20, 0, 20 }) do
                local spots = {}
                for i = 1, n do
                    local a = anchors[i]
                    local side = slide
                    if n >= 2 then side = (i == 1) and -(Drop.SHIP_GAP - slide) or (Drop.SHIP_GAP + slide) end
                    spots[i] = { x = a.x - sx * d + lx * side, z = a.z - sz * d + lz * side }
                end
                local score = 0
                for i = 1, n do
                    local p = spots[i]
                    score = score + flatness(p.x, p.z, sx, sz, lx, lz, ground)
                    if blocked and blocked(p.x, p.z) then score = score + 1000 end
                end
                if not best or score < best.score then
                    best = { score = score, spots = spots, sx = sx, sz = sz, d = d }
                end
            end
        end
    end
    local frames = {}
    for i, p in ipairs(best.spots) do
        frames[i] = { x = p.x, z = p.z, y = ground(p.x, p.z), sx = best.sx, sz = best.sz, lx = lx, lz = lz }
    end
    return frames, best.d, best.score
end

-- Runtime ---------------------------------------------------------------------------------------------------------
-- api (Drop.Configure): present(op, ...) the mission's replicated event (applied locally too), isLeader(),
-- isNetwork(), myTeam(), player() this peer's craft, forEachHuman(fn(h)) every human craft the leader knows,
-- cameraReady/cameraObject/cameraFinish/cameraCancelled (the mission's shared-camera wrappers), exu, owner (the
-- control-mask owner id), log(line).
local api = {}

local function V(x, y, z) return SetVector(x, y, z) end
local function ground(x, z)
    local ok, h = pcall(GetTerrainHeightAndNormal, V(x, 0, z))
    return ok and type(h) == "number" and h or 0
end
local function alive(h) return h ~= nil and IsValid(h) end
local function call(name, ...) local f = api[name]; if type(f) == "function" then return f(...) end end
local function log(fmt, ...) if api.log then api.log(string.format("[CRDropIn] " .. fmt, ...)) end end
local function isNum(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end
local function network() return call("isNetwork") == true end
local function leading() return not network() or call("isLeader") == true end

function Drop.Configure(options)
    api = options or {}
end

local function lock(on)
    if network() then return end -- the EXU mask stands down in multiplayer; pinning is the hold there
    local exu = api.exu
    if not (exu and exu.SetPlayerControlMask) then
        if on then log("control lock unavailable: no EXU control mask") end
        return
    end
    local owner = api.owner or "mission:dropship"
    if on then
        if not exu.SetPlayerControlMask(owner, exu.CONTROL.ALL) then
            local s = exu.GetPlayerControlState and exu.GetPlayerControlState()
            log("control lock unavailable: %s", tostring(s and s.reason))
        end
    elseif exu.ClearPlayerControlMask then
        exu.ClearPlayerControlMask(owner)
    end
end

-- Start/restart: the mask is not saved and must not outlive the run that set it.
function Drop.Reset()
    lock(false)
end

local function matrix(x, y, z, dx, dz) return BuildDirectionalMatrix(V(x, y, z), V(dx, 0, dz)) end
-- The bow (GetFront) faces away from the ramp exit.
local function hullMatrix(ship, up, back)
    return matrix(ship.x + ship.sx * back, ship.y + up, ship.z + ship.sz * back, -ship.sx, -ship.sz)
end

-- Hold a carried craft in its slot and keep it whole.
local function pin(h, ship, along, lat, t)
    if not alive(h) then return end
    local x, y, z, dx, dz = Drop.HoldPos(ship, along, lat, t)
    SetTransform(h, matrix(x, y, z, dx, dz))
    SetVelocity(h, V(0, 0, 0))
    if type(SetCurHealth) == "function" and type(GetMaxHealth) == "function" then
        pcall(SetCurHealth, h, GetMaxHealth(h))
    end
end

local function setDown(h, x, z, ship)
    if not alive(h) then return end
    SetTransform(h, matrix(x, ground(x, z) + 1.0, z, ship.sx, ship.sz)) -- 1 m over the ground: CR guess
    SetVelocity(h, V(0, 0, 0))
end

-- Events (every peer, the leader included) -------------------------------------------------------------------------
function Drop.Apply(s, op, ...)
    if type(s) ~= "table" or s.go or s.phase == "done" then return end
    if op == "DropShip" then
        local i, n, x, z, y, sx, sz, lx, lz, delay = ...
        for _, v in ipairs({ i, n, x, z, y, sx, sz, lx, lz, delay }) do if not isNum(v) then return end end
        if i < 1 or i > Drop.MAX_SHIPS or n < 1 or n > Drop.MAX_SHIPS or i ~= floor(i) or n ~= floor(n) then return end
        s.n = n
        s.ships = s.ships or {}
        s.ships[i] = { x = x, z = z, y = y, sx = sx, sz = sz, lx = lx, lz = lz, delay = delay }
    elseif op == "DropCrew" then
        local team, i, along, lat = ...
        if not (isNum(team) and isNum(i) and isNum(along) and isNum(lat)) then return end
        s.crew = s.crew or {}
        s.crew[team] = { ship = i, along = along, lat = lat }
    elseif op == "DropGo" then
        local complete = isNum(s.n)
        for i = 1, complete and s.n or 0 do if not (s.ships and s.ships[i]) then complete = false end end
        for _, c in pairs(s.crew or {}) do if not (complete and s.ships[c.ship]) then complete = false end end
        if not complete then
            log("incomplete plan: no drop on this peer")
            s.phase = "done"
            return
        end
        s.go, s.t0, s.phase = true, GetTime(), "drop"
        lock(true)
    end
end

-- Leader ---------------------------------------------------------------------------------------------------------
local function cleanupLead(L)
    for _, hull in ipairs(L.hulls) do
        if alive(hull.h) then RemoveObject(hull.h) end
        hull.h, hull.gone = nil, true
    end
    if alive(L.pod) then RemoveObject(L.pod) end
    L.pod = nil
end

-- Leader: plan the drop and start it on every peer. spec:
--   ships   = { { anchor = {x, z}, delay = s, crew = {team, ...} (humans riding here), cargo = { {h, goal = pos,
--               along = m, lat = m (optional: else the next free lane slot after the crew)} } }, ... } (1-2 ships)
--   focus   = ship index the camera looks at (default the last); team = ship team (default 1)
--   exclude = { [handle] = true } objects that do not block a site (the cargo itself)
--   lateral = {x, z} the side-by-side line for a single anchor
-- Returns false (state done, nothing built, nothing sent) when the ships cannot be built.
function Drop.Begin(s, spec)
    local n = #spec.ships
    if n < 1 or n > Drop.MAX_SHIPS then s.phase = "done"; return false end
    local anchors = {}
    for i = 1, n do anchors[i] = spec.ships[i].anchor end
    local exclude = spec.exclude or {}
    local blocked = nil
    if type(ObjectsInRange) == "function" then
        blocked = function(x, z)
            for h in ObjectsInRange(45, V(x, ground(x, z), z)) do
                if not exclude[h] and (IsBuilding(h) or IsCraft(h)) then return true end
            end
            return false
        end
    end
    local frames, d, score = Drop.Sites(anchors, ground, blocked, spec.lateral)
    local L = { hulls = {}, cargo = {}, d = d, focus = spec.focus or n, team = spec.team or 1 }
    local crew = {}
    for i = 1, n do
        local ship, frame = spec.ships[i], frames[i]
        frame.delay = ship.delay or 0
        local j = 0
        for _, team in ipairs(ship.crew or {}) do
            j = j + 1
            local along, lat = Drop.Slot(j)
            if along then crew[#crew + 1] = { team = team, ship = i, along = along, lat = lat }
            else log("hold full: team %d rides nowhere", team) end
        end
        for _, c in ipairs(ship.cargo or {}) do
            local along, lat = c.along, c.lat
            if not along then j = j + 1; along, lat = Drop.Slot(j) end
            if along and alive(c.h) then
                L.cargo[#L.cargo + 1] = { h = c.h, ship = i, along = along, lat = lat, goal = c.goal }
            end
        end
        local up, back = Drop.Offsets(frame, 0)
        local h = BuildObject(Drop.FLYING, L.team, hullMatrix(frame, up, back))
        if not alive(h) then
            log("stock opening: could not build %s", Drop.FLYING)
            cleanupLead(L)
            s.phase = "done"
            return false
        end
        L.hulls[i] = { h = h, odf = Drop.FLYING }
    end
    s.lead = L
    log("sites score=%.1f d=%d ships=%d crew=%d cargo=%d stern=(%.2f,%.2f)", score, d, n, #crew, #L.cargo,
        frames[1].sx, frames[1].sz)
    -- The camera pod stands out past the ramps, between the ships.
    local mx, mz = 0, 0
    for i = 1, n do mx, mz = mx + frames[i].x / n, mz + frames[i].z / n end
    local cx, cz = mx + frames[1].sx * Drop.CAMERA_OUT, mz + frames[1].sz * Drop.CAMERA_OUT
    L.pod = BuildObject(Drop.POD, 0, V(cx, ground(cx, cz), cz))
    for i = 1, n do
        local f = frames[i]
        call("present", "DropShip", i, n, f.x, f.z, f.y, f.sx, f.sz, f.lx, f.lz, f.delay)
    end
    for _, c in ipairs(crew) do call("present", "DropCrew", c.team, c.ship, c.along, c.lat) end
    call("present", "DropGo")
    if not s.go then
        -- The mission did not apply the plan locally: nothing can play.
        log("stock opening: plan not applied")
        cleanupLead(L)
        s.phase = "done"
        return false
    end
    if alive(L.pod) and api.cameraReady then api.cameraReady(); L.camera = true end
    return true
end

local function release(s)
    s.released, s.releasedAt = true, GetTime()
    lock(false)
    local L = s.lead
    if L then
        if L.camera then
            L.camera = false
            call("cameraFinish")
        end
        if alive(L.pod) then RemoveObject(L.pod) end
        L.pod = nil
        for _, c in ipairs(L.cargo) do
            if alive(c.h) then c.path, c.leg = true, 1 end
        end
    end
    log("released")
end

-- Push an AI unit down its lane, then onto its own spot, then hand it back to its AI.
local function drive(s, c)
    if not alive(c.h) then c.path = nil; return end
    local f = s.ships[c.ship]
    local now = GetTime()
    if now - s.releasedAt > Drop.DRIVE_MAX then c.path = nil; Stop(c.h, 0); return end
    local p = GetPosition(c.h)
    local along = (p.x - f.x) * f.sx + (p.z - f.z) * f.sz
    local legs = #Drop.PATH + 1
    local function leg(k) return Drop.PATH[k] or s.lead.d end
    if c.leg <= legs and along >= leg(c.leg) - 2 then c.leg = c.leg + 1 end
    local gx, gz
    if c.leg > legs then
        c.goalBy = c.goalBy or now + Drop.GOAL_T   -- give up if the spot is blocked
        local dx, dz = c.goal and (c.goal.x - p.x) or 0, c.goal and (c.goal.z - p.z) or 0
        if not c.goal or sqrt(dx * dx + dz * dz) < 4 or now > c.goalBy then
            c.path = nil
            Stop(c.h, 0)
            return
        end
        gx, gz = c.goal.x, c.goal.z
    else
        local x, _, z = Drop.Deck(f, leg(c.leg), c.lat, ground)
        gx, gz = x, z
    end
    local dx, dz = gx - p.x, gz - p.z
    local len = sqrt(dx * dx + dz * dz)
    if len < 1e-3 then dx, dz = f.sx, f.sz else dx, dz = dx / len, dz / len end
    local v = GetVelocity(c.h)
    SetTransform(c.h, BuildDirectionalMatrix(p, V(dx, 0, dz)))
    SetVelocity(c.h, V(dx * Drop.SPEED, v.y, dz * Drop.SPEED))
end

local function near(h, f)
    if not alive(h) then return false end
    local p = GetPosition(h)
    local dx, dz = p.x - f.x, p.z - f.z
    return dx * dx + dz * dz < Drop.CLEAR_R * Drop.CLEAR_R
end

local function clear(s, i)
    local f = s.ships[i]
    for _, c in ipairs(s.lead.cargo) do
        if c.ship == i and c.path then return false end
        if near(c.h, f) then return false end
    end
    local free = true
    if api.forEachHuman then
        api.forEachHuman(function(h) if near(h, f) then free = false end end)
    elseif near(call("player"), f) then
        free = false
    end
    return free
end

local function swap(hull, odf, m, team)
    if alive(hull.h) then RemoveObject(hull.h) end
    hull.h, hull.odf = BuildObject(odf, team, m), odf
end

local function lead(s, t, rel)
    local L, now = s.lead, GetTime()
    for i = 1, s.n do
        local ship, hull = s.ships[i], L.hulls[i]
        if hull.gone then
            -- nothing left of this ship
        elseif hull.liftAt then
            local up, back = Drop.LiftOffsets(now - hull.liftAt)
            if alive(hull.h) and up <= Drop.LIFT_GONE then
                SetTransform(hull.h, hullMatrix(ship, up, back))
            else
                if alive(hull.h) then RemoveObject(hull.h) end
                hull.h, hull.gone = nil, true
            end
        elseif hull.closeAt then
            if now - hull.closeAt >= Drop.CLOSE_T then hull.liftAt = now; log("ship %d lifting", i) end
        elseif Drop.Stage(ship, t) == "fly" then
            if alive(hull.h) then
                local up, back = Drop.Offsets(ship, t)
                SetTransform(hull.h, hullMatrix(ship, up, back))
            end
        else
            if hull.odf ~= Drop.LANDED then
                swap(hull, Drop.LANDED, hullMatrix(ship, 0, 0), L.team)
                for _, c in ipairs(L.cargo) do
                    if c.ship == i and alive(c.h) then pin(c.h, ship, c.along, c.lat, t); Stop(c.h, 1) end
                end
                log("ship %d landed odf=%s", i, tostring(alive(hull.h) and GetOdf(hull.h)))
            end
            if s.released and not alive(hull.h) then
                hull.gone = true
            elseif s.released and now - s.releasedAt > Drop.LIFT_AFTER and clear(s, i) then
                local m = hullMatrix(ship, 0, 0)
                swap(hull, Drop.CLOSING, m, L.team)
                if not alive(hull.h) then swap(hull, Drop.FLYING, m, L.team) end
                hull.closeAt = now
                log("ship %d closing odf=%s", i, tostring(alive(hull.h) and GetOdf(hull.h)))
            end
        end
    end
    for _, c in ipairs(L.cargo) do
        if t < rel then pin(c.h, s.ships[c.ship], c.along, c.lat, t)
        elseif c.path then drive(s, c) end
    end
    local focus = L.hulls[L.focus]
    if L.camera and t < rel and alive(L.pod) and focus and alive(focus.h) then
        call("cameraObject", L.pod, 0, Drop.CAMERA_UP, 0, focus.h)
    end
    if s.released then
        for _, hull in ipairs(L.hulls) do if not hull.gone then return end end
        for _, c in ipairs(L.cargo) do if c.path then return end end
        s.phase = "done"
        log("done")
    end
end

-- A save taken mid-drop: the cameras and the control mask did not survive it and the ship handles cannot be
-- trusted. Go straight to the end state: ships and pod gone, AI cargo on its spot, this peer's craft (if it was
-- still carried) set down past the ramp on its lane.
local function recover(s)
    s.recover = nil
    local L = s.lead
    if L and leading() then
        if type(AllObjects) == "function" then
            for h in AllObjects() do
                if IsOdf(h, Drop.FLYING) or IsOdf(h, Drop.LANDED) or IsOdf(h, Drop.CLOSING) then RemoveObject(h) end
            end
        end
        cleanupLead(L)
        L.camera = false
        for _, c in ipairs(L.cargo) do
            if alive(c.h) and (not s.released or c.path) then
                local ship = s.ships[c.ship]
                if c.goal then setDown(c.h, c.goal.x, c.goal.z, ship)
                else local x, _, z = Drop.ExitPos(ship, c.along, c.lat, ground); setDown(c.h, x, z, ship) end
                Stop(c.h, 0)
            end
            c.path = nil
        end
    end
    local mine = s.crew and s.crew[call("myTeam")]
    if s.go and not s.released and mine and s.ships[mine.ship] then
        local ship = s.ships[mine.ship]
        local x, _, z = Drop.ExitPos(ship, mine.along, mine.lat, ground)
        setDown(call("player"), x, z, ship)
    end
    lock(false)
    s.released, s.phase = true, "done"
    log("recovered after load")
end

-- Every peer, every frame. Returns true while the carried craft are still held (the mission's stock opening waits).
function Drop.Update(s)
    if type(s) ~= "table" or s.phase == "done" then return false end
    if s.recover then recover(s); return false end
    if not s.go then return false end
    local isLead = s.lead ~= nil and leading()
    local t = GetTime() - s.t0
    local rel = Drop.ReleaseTime(s.ships, s.n)
    if isLead and s.lead.camera and t < rel and call("cameraCancelled") then
        -- Offline skip (cameraCancelled is false in network games): touch every ship down now; the ramps still
        -- take OPEN_T.
        local last = rel - Drop.OPEN_T
        if t < last then s.t0 = GetTime() - last; t = last end
    end
    if t < rel then
        local mine = s.crew and s.crew[call("myTeam")]
        if mine then pin(call("player"), s.ships[mine.ship], mine.along, mine.lat, t) end
    elseif not s.released then
        release(s)
    end
    if isLead then lead(s, t, rel)
    elseif s.released then s.phase = "done" end
    return t < rel
end

-- Load: the mask is not saved and ship handles cannot be trusted across a save.
function Drop.OnLoad(s)
    if type(s) == "table" and s.phase ~= "done" then s.recover = true end
end

return Drop
