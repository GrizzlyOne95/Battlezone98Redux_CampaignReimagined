-- Mission 18 extraction ending: NSDF dropships land beside the Texas, load the surviving craft (each human's
-- own ship, plus one ship for the Recycler and Factory), close their ramps and lift into the storm.
--
-- This module is the dropship choreography only: pure, deterministic functions of the plan and the clock, so
-- every peer computes the same pose and the leader can drive the ship objects while each peer pins its OWN
-- craft aboard. CRMisn18 owns the state machine, the cameras and the replication. It reuses the technique and
-- the measured numbers of CR04Drop (misn04's opening; that file is being reworked on another branch and is not
-- touched here): avdropc flies in, avdropo is swapped in at touchdown (ramps swing open once on creation),
-- avdropx is swapped in before lift-off (ramps fold shut once), carried craft are pinned with SetTransform.
--
-- Numbers marked "CR18 guess" are inferences that need a live tune; the rest are CR04Drop's.
local Drop = {}

Drop.FLYING, Drop.LANDED, Drop.CLOSING = "avdropc", "avdropo", "avdropx"
Drop.POD = "apcamr"

Drop.FLY_T = 9.0          -- s from START_UP to touchdown (CR04Drop uses 16)                          CR18 guess
Drop.OPEN_T = 2.6         -- ANIM index 0 is 30 frames at 15 fps; the lips are down by 2.0 s
Drop.LOAD_T = 6.0         -- s the craft take to glide up the ramp into the hold                      CR18 guess
Drop.CLOSE_T = 2.4        -- avdropx folds the ramps in 2.0 s, then the ship lifts
Drop.STAGGER = 1.2        -- s between one ship's start and the next                                 CR18 guess
Drop.START_UP, Drop.START_BACK = 320.0, 260.0
Drop.HOLD_UP = 6.0        -- carried craft ride this far over the ground under the hull
Drop.LIP = 40.3           -- ramp lip, metres behind the hull centre (measured by CR04Drop's avdtest)
Drop.HINGE = 24.0
Drop.LIFT_ACCEL = 1.5     -- up = LIFT_ACCEL * a^2 metres, a seconds after lift-off
Drop.LIFT_BACK = -0.6
Drop.RING = { 150, 180, 210 }   -- candidate site radii around the Texas; inside the storm's 300 m keep-clear zone
Drop.MAX_SHIPS = 5
Drop.SHOT1 = 27.0         -- s from the start to the end of the extraction shot (the last ramps are closed)
Drop.SHOT2 = 12.0         -- s of the ascent shot after it                                            CR18 guess

local sqrt, cos, sin, floor, max, min = math.sqrt, math.cos, math.sin, math.floor, math.max, math.min

local function lerp(a, b, t) return a + (b - a) * t end
local function ease(t) t = max(0, min(1, t)); return t * t * (3 - 2 * t) end

-- Total length of the whole ending (both shots).
function Drop.Total() return Drop.SHOT1 + Drop.SHOT2 end

-- The ship at index i starts this many seconds late.
function Drop.Delay(i) return (i - 1) * Drop.STAGGER end

-- Stage of ship i at time t (seconds since the start): name and seconds into it.
--   wait -> fly -> open (landed, ramps swinging) -> load -> close (avdropx) -> lift
function Drop.Stage(i, t)
    local a = t - Drop.Delay(i)
    if a < 0 then return "wait", 0 end
    if a < Drop.FLY_T then return "fly", a end
    a = a - Drop.FLY_T
    if a < Drop.OPEN_T then return "open", a end
    a = a - Drop.OPEN_T
    if a < Drop.LOAD_T then return "load", a end
    a = a - Drop.LOAD_T
    if a < Drop.CLOSE_T then return "close", a end
    return "lift", a - Drop.CLOSE_T
end

-- Which object the leader keeps for a stage.
function Drop.Odf(stage)
    if stage == "fly" or stage == "wait" then return Drop.FLYING end
    if stage == "open" or stage == "load" then return Drop.LANDED end
    return Drop.CLOSING
end

-- Height and back-offset of the hull centre above its landing spot (metres, along the stern direction).
function Drop.Offsets(i, t)
    local stage, a = Drop.Stage(i, t)
    if stage == "wait" then return Drop.START_UP, Drop.START_BACK end
    if stage == "fly" then
        local k = 1 - min(1, a / Drop.FLY_T)
        return Drop.START_UP * k * k * k, Drop.START_BACK * k * k
    end
    if stage == "lift" then return Drop.LIFT_ACCEL * a * a, Drop.LIFT_BACK * a * a end
    return 0, 0
end

-- Ship frame: x, z, y (ground) of the landing spot; sx, sz the stern (ramp exit) direction; lx, lz sideways.
-- World position of the hull centre at time t.
function Drop.HullPos(ship, i, t)
    local up, back = Drop.Offsets(i, t)
    return ship.x + ship.sx * back, ship.y + up, ship.z + ship.sz * back
end

-- Point on the ship's frame: along the stern direction and sideways, on the ground or `up` over the hull.
function Drop.At(ship, along, lat, up, ground)
    local x = ship.x + ship.sx * along + ship.lx * lat
    local z = ship.z + ship.sz * along + ship.lz * lat
    return x, up and (ship.y + up) or (ground and ground(x, z) or ship.y), z
end

-- Deck height along the centreline lane: the hold floor to the hinge, then the ramp down to its lip.
function Drop.Deck(ship, along, lat, ground)
    local x, y, z = Drop.At(ship, along, lat, nil, ground)
    if along <= Drop.HINGE then y = ship.y + 4.5
    elseif along < Drop.LIP then y = max(y, ship.y + 4.5 - (along - Drop.HINGE) * 0.2925) end
    return x, y, z
end

-- Where a carried craft sits at time t, given its lane slot and where it stood when the ending began.
-- Before loading it holds its spot; while loading it glides to the lip and up into the hold; afterwards it
-- rides the hull. Returns x, y, z and the heading (a unit vector, x and z) it should face.
function Drop.CargoPos(ship, i, slot, start, t, ground)
    local stage, a = Drop.Stage(i, t)
    local hx, hy, hz = Drop.At(ship, slot.along, slot.lat, Drop.HOLD_UP, ground)
    local fx, fz = ship.sx, ship.sz
    if stage == "wait" or stage == "fly" or stage == "open" then
        return start.x, start.y, start.z, start.dx, start.dz
    end
    if stage == "load" then
        local r = a / Drop.LOAD_T
        local lx, ly, lz = Drop.Deck(ship, Drop.LIP, slot.lat, ground)
        if r < 0.6 then
            local k = ease(r / 0.6)
            local dx, dz = lx - start.x, lz - start.z
            local d = sqrt(dx * dx + dz * dz)
            return lerp(start.x, lx, k), lerp(start.y, ly + 1.0, k), lerp(start.z, lz, k),
                d > 1e-3 and dx / d or fx, d > 1e-3 and dz / d or fz
        end
        local k = ease((r - 0.6) / 0.4)
        return lerp(lx, hx, k), lerp(ly + 1.0, hy, k), lerp(lz, hz, k), -fx, -fz
    end
    -- close / lift: the hold travels with the hull
    local up, back = Drop.Offsets(i, t)
    return hx + ship.sx * back, hy + up, hz + ship.sz * back, fx, fz
end

-- Lane slots in the hold. Humans take the middle; the base ship carries the Recycler and the Factory.
Drop.SLOTS = {
    human = { along = 6, lat = 0 },
    recycler = { along = 0, lat = -8 },
    factory = { along = 2, lat = 10 },
}

-- Sites ------------------------------------------------------------------------------------------------
-- `count` landing spots on a ring around (cx, cz), sterns toward the centre. `ground(x, z)` gives the height.
-- The flattest of the candidate radii and start angles wins. The result depends only on its inputs, so the
-- same call gives the same plan on any machine. Returns a list of {x, y, z, sx, sz, lx, lz} and the score.
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

function Drop.Sites(cx, cz, count, ground)
    count = max(1, min(Drop.MAX_SHIPS, floor(count)))
    local best
    for _, radius in ipairs(Drop.RING) do
        for turn = 0, 2 do
            local theta0 = turn * (math.pi * 2 / count) / 3
            local list, score = {}, 0
            for j = 1, count do
                local th = theta0 + (j - 1) * math.pi * 2 / count
                local x, z = cx + cos(th) * radius, cz + sin(th) * radius
                local sx, sz = (cx - x) / radius, (cz - z) / radius
                local lx, lz = -sz, sx
                list[j] = { x = x, z = z, y = ground(x, z), sx = sx, sz = sz, lx = lx, lz = lz }
                score = score + flatness(x, z, sx, sz, lx, lz, ground)
            end
            if not best or score < best.score then best = { score = score, list = list } end
        end
    end
    return best.list, best.score
end

return Drop
