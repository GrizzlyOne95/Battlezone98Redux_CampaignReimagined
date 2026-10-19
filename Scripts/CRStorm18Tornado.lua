-- CRStorm18Tornado: the giant tornado of mission 18 (CRStorm18).
--
-- Three separable parts:
--   motion   pure arithmetic, no engine calls: a roaming track that steers to a
--            waypoint and is held out of the keep-clear circles around the
--            transport, the recycler and the stock spawn points. Every peer
--            steps the same state, and the leader's events correct drift.
--   FX       stacked particle bands (cr18_storm.particle.payload) in local space.
--            The node is moved to the tornado and turned with
--            SetParticleSystemDirection, each band at its own rate, so the
--            funnel shears like a real one. Visual only, built on every peer.
--   effect   an optional mild pull, spin and damage (leader only, tunables
--            below). It is the only part that touches gameplay.
local Tornado = {}

-- Tunables -------------------------------------------------------------------
Tornado.SPEED = 9.5        -- m/s along the track
Tornado.ACCEL = 2.6        -- m/s^2 of steering: wide turns, never a snap
Tornado.PAD = 40           -- m kept beyond every keep-clear circle
Tornado.MARGIN = 140       -- m kept inside the map edge
Tornado.GROW = 10          -- s for the funnel to build to full height
Tornado.FAR = 1100         -- m from the viewer beyond which the funnel stops drawing

-- The gameplay effect. Leader only; set ENABLED false for a purely visual storm.
Tornado.EFFECT = {
    ENABLED = true,
    RADIUS = 45,           -- m: nothing farther than this is touched
    PULL = 7,              -- m/s^2 inward at the core
    SWIRL = 9,             -- m/s^2 around the core
    LIFT = 4,              -- m/s^2 up at the core
    MAX_SPEED = 55,        -- m/s: the effect never accelerates a craft past this
    DAMAGE = 6,            -- hull points per second at the core (0 = none)
}

local sqrt, cos, sin, floor = math.sqrt, math.cos, math.sin, math.floor

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Motion ----------------------------------------------------------------------
function Tornado.InZone(x, z, zones, pad)
    pad = pad or 0
    for i = 1, #(zones or {}) do
        local zn = zones[i]
        local dx, dz = x - zn[1], z - zn[2]
        local lim = zn[3] + pad
        if dx * dx + dz * dz < lim * lim then return zn end
    end
    return nil
end

-- False when the straight segment passes within r + pad of any zone centre.
function Tornado.SegmentClear(x0, z0, x1, z1, zones, pad)
    local sx, sz = x1 - x0, z1 - z0
    local len2 = sx * sx + sz * sz
    for i = 1, #(zones or {}) do
        local zn = zones[i]
        local t = 0
        if len2 > 1e-6 then t = math.max(0, math.min(1, ((zn[1] - x0) * sx + (zn[2] - z0) * sz) / len2)) end
        local dx, dz = x0 + sx * t - zn[1], z0 + sz * t - zn[2]
        local lim = zn[3] + (pad or 0)
        if dx * dx + dz * dz < lim * lim then return false end
    end
    return true
end

local function inBounds(x, z, b, margin)
    return x >= b[1] + margin and x <= b[3] - margin and z >= b[2] + margin and z <= b[4] - margin
end

-- Holds the track out of every zone and inside the map. Overlapping circles can
-- push a point from one into the next, so it repeats; if a pass still ends
-- inside, the track falls back to the last point it knew was clear.
function Tornado.Resolve(s, zones, bounds)
    for _ = 1, 8 do
        local moved = false
        for i = 1, #zones do
            local zn = zones[i]
            local dx, dz = s.x - zn[1], s.z - zn[2]
            local d = sqrt(dx * dx + dz * dz)
            local lim = zn[3] + Tornado.PAD
            if d < lim then
                if d < 1e-3 then dx, dz, d = 1, 0, 1 end
                local nx, nz = dx / d, dz / d
                s.x, s.z = zn[1] + nx * lim, zn[2] + nz * lim
                local vn = s.vx * nx + s.vz * nz
                if vn < 0 then s.vx, s.vz = s.vx - vn * nx, s.vz - vn * nz end
                moved = true
            end
        end
        local m = Tornado.MARGIN
        if s.x < bounds[1] + m then s.x = bounds[1] + m; if s.vx < 0 then s.vx = 0 end; moved = true end
        if s.x > bounds[3] - m then s.x = bounds[3] - m; if s.vx > 0 then s.vx = 0 end; moved = true end
        if s.z < bounds[2] + m then s.z = bounds[2] + m; if s.vz < 0 then s.vz = 0 end; moved = true end
        if s.z > bounds[4] - m then s.z = bounds[4] - m; if s.vz > 0 then s.vz = 0 end; moved = true end
        if not moved then break end
    end
    if Tornado.InZone(s.x, s.z, zones, Tornado.PAD - 0.5) and s.sx then
        s.x, s.z, s.vx, s.vz = s.sx, s.sz, 0, 0
    else
        s.sx, s.sz = s.x, s.z
    end
end

-- Picks the next waypoint: near one of the anchors (players) when there are any,
-- otherwise anywhere free. The track to it must clear every zone. Returns false
-- and leaves the old waypoint when nothing qualified.
function Tornado.Pick(s, rng, zones, bounds, anchors)
    for attempt = 1, 30 do
        local x, z
        if anchors and #anchors > 0 and attempt <= 22 then
            local a = anchors[1 + floor(rng:Float() * #anchors)]
            local ang, d = rng:Float() * 6.2831853, 150 + rng:Float() * 100
            x, z = a.x + cos(ang) * d, a.z + sin(ang) * d
        else
            x = bounds[1] + Tornado.MARGIN + rng:Float() * (bounds[3] - bounds[1] - 2 * Tornado.MARGIN)
            z = bounds[2] + Tornado.MARGIN + rng:Float() * (bounds[4] - bounds[2] - 2 * Tornado.MARGIN)
        end
        if inBounds(x, z, bounds, Tornado.MARGIN) and not Tornado.InZone(x, z, zones, Tornado.PAD + 20)
            and Tornado.SegmentClear(s.x, s.z, x, z, zones, Tornado.PAD + 10) then
            s.wx, s.wz, s.n = x, z, s.n + 1
            return true
        end
    end
    return false
end

-- A new funnel on the ground, clear of every zone, 300 to 450 m from an anchor
-- when it has one (close enough to roll into view within the minute).
function Tornado.Spawn(rng, zones, bounds, anchors)
    local s = { x = 0, z = 0, vx = 0, vz = 0, wx = 0, wz = 0, t = 0, n = 0, speed = Tornado.SPEED }
    local placed = false
    for attempt = 1, 60 do
        local x, z
        if anchors and #anchors > 0 and attempt <= 40 then
            local a = anchors[1 + floor(rng:Float() * #anchors)]
            local ang, d = rng:Float() * 6.2831853, 300 + rng:Float() * 150
            x, z = a.x + cos(ang) * d, a.z + sin(ang) * d
        else
            x = bounds[1] + Tornado.MARGIN + rng:Float() * (bounds[3] - bounds[1] - 2 * Tornado.MARGIN)
            z = bounds[2] + Tornado.MARGIN + rng:Float() * (bounds[4] - bounds[2] - 2 * Tornado.MARGIN)
        end
        if inBounds(x, z, bounds, Tornado.MARGIN) and not Tornado.InZone(x, z, zones, Tornado.PAD + 20) then
            s.x, s.z, placed = x, z, true
            break
        end
    end
    if not placed then
        s.x, s.z = (bounds[1] + bounds[3]) / 2, (bounds[2] + bounds[4]) / 2
        local zn = Tornado.InZone(s.x, s.z, zones, Tornado.PAD)
        if zn then s.x, s.z = bounds[1] + Tornado.MARGIN, bounds[2] + Tornado.MARGIN end
    end
    s.sx, s.sz, s.wx, s.wz = s.x, s.z, s.x, s.z
    Tornado.Pick(s, rng, zones, bounds, anchors)
    return s
end

function Tornado.Step(s, dt, zones, bounds)
    dt = math.max(0, math.min(tonumber(dt) or 0, 0.5))
    s.t = s.t + dt
    local dx, dz = s.wx - s.x, s.wz - s.z
    local d = sqrt(dx * dx + dz * dz)
    local sp = s.speed or Tornado.SPEED
    local tvx, tvz = 0, 0
    if d > 8 then tvx, tvz = dx / d * sp, dz / d * sp end
    local ax, az = tvx - s.vx, tvz - s.vz
    local al = sqrt(ax * ax + az * az)
    local cap = Tornado.ACCEL * dt
    if al > cap then ax, az = ax / al * cap, az / al * cap end
    s.vx, s.vz = s.vx + ax, s.vz + az
    s.x, s.z = s.x + s.vx * dt, s.z + s.vz * dt
    Tornado.Resolve(s, zones, bounds)
end

-- Wire form: n, x, z, vx, vz, wx, wz, t. Numbers only.
function Tornado.Encode(s)
    local function r(v) return floor(v * 10 + 0.5) / 10 end
    return s.n, r(s.x), r(s.z), r(s.vx), r(s.vz), r(s.wx), r(s.wz), r(s.t)
end

-- Applies a received state; nil on a malformed packet.
function Tornado.Decode(s, n, x, z, vx, vz, wx, wz, t)
    for _, v in ipairs({ n, x, z, vx, vz, wx, wz, t }) do
        if not finite(v) then return nil end
    end
    s = s or { speed = Tornado.SPEED }
    s.n, s.x, s.z, s.vx, s.vz, s.wx, s.wz, s.t = n, x, z, vx, vz, wx, wz, t
    s.sx, s.sz = x, z
    return s
end

-- Gameplay effect -------------------------------------------------------------
-- Leader only (the director enforces that). Pulls and spins every craft this
-- peer owns inside the radius and wears it down a little; never touches a
-- building. Returns how many craft it moved.
function Tornado.Affect(s, dt)
    local e = Tornado.EFFECT
    if not e.ENABLED or type(SetVelocity) ~= "function" or type(GetVelocity) ~= "function" then return 0 end
    local each = type(AllCraft) == "function" and AllCraft or AllObjects
    if type(each) ~= "function" then return 0 end
    local grow = math.max(0, math.min(1, s.t / Tornado.GROW))
    if grow < 0.5 then return 0 end
    local netgame = type(IsNetGame) == "function" and IsNetGame()
    local moved, hurt = 0, {}
    local owed = Tornado.owed or {}
    for h in each() do
        local ok = pcall(function()
            if type(IsValid) == "function" and not IsValid(h) then return end
            if type(IsBuilding) == "function" and IsBuilding(h) then return end
            if netgame and type(IsLocal) == "function" and not IsLocal(h) then return end
            local p = GetPosition(h)
            if not p then return end
            local dx, dz = s.x - p.x, s.z - p.z
            local d = sqrt(dx * dx + dz * dz)
            if d >= e.RADIUS then return end
            local f = (1 - d / e.RADIUS)
            f = f * f * grow
            local inx, inz = 0, 0
            if d > 1e-3 then inx, inz = dx / d, dz / d end
            local v = GetVelocity(h)
            local nvx = v.x + (inx * e.PULL - inz * e.SWIRL) * f * dt
            local nvz = v.z + (inz * e.PULL + inx * e.SWIRL) * f * dt
            local nvy = v.y + e.LIFT * f * dt
            local sp = sqrt(nvx * nvx + nvz * nvz)
            if sp > e.MAX_SPEED then nvx, nvz = nvx / sp * e.MAX_SPEED, nvz / sp * e.MAX_SPEED end
            SetVelocity(h, SetVector(nvx, nvy, nvz))
            moved = moved + 1
            if e.DAMAGE > 0 and type(Damage) == "function" then
                local sum = (owed[h] or 0) + e.DAMAGE * f * dt
                if sum >= 1 then
                    Damage(h, floor(sum))
                    sum = sum - floor(sum)
                end
                hurt[h] = sum
            end
        end)
        if not ok then break end
    end
    Tornado.owed = hurt -- forget craft that left the radius
    return moved
end

-- FX --------------------------------------------------------------------------
local BANDS = {
    { key = "base",   template = "CR18/TornadoBase",   spin = 0.9,  rate = 70 },
    { key = "mid",    template = "CR18/TornadoMid",    spin = 1.35, rate = 60 },
    { key = "top",    template = "CR18/TornadoTop",    spin = 1.9,  rate = 48 },
    { key = "core",   template = "CR18/TornadoCore",   spin = -1.1, rate = 44 },
    { key = "skirt",  template = "CR18/TornadoSkirt",  spin = 0.5,  rate = 70 },
    { key = "debris", template = "CR18/TornadoDebris", spin = 2.2,  rate = 32 },
    { key = "glow",   template = "CR18/TornadoGlow",   spin = 0.0,  rate = 12 },
    { key = "ember",  template = "CR18/TornadoEmber",  spin = 1.2,  rate = 34 },
}
Tornado.BANDS = BANDS

local PREFIX = "CR18/Tornado/"
local LIGHT = "CR18/TornadoLight"

-- ctx: call(fn, ...) -> result or nil (guarded EXU call), vec = SetVector,
-- ready() -> true when the templates parsed, ground(x, z) -> height, quality.
function Tornado.NewFx(ctx)
    local F = { live = false, failed = false, hidden = false, angle = {}, nextTurn = 0, nextLight = 0,
                lit = false, failures = 0 }
    for _, b in ipairs(BANDS) do F.angle[b.key] = 0 end

    local function create()
        if not ctx.ready() then F.failed = true; return end
        for _, b in ipairs(BANDS) do
            if ctx.call("CreateParticleSystem", PREFIX .. b.key, b.template, ctx.vec(0, -500, 0)) ~= true then
                F.failures = F.failures + 1
            else
                ctx.call("SetParticleSystemKeepLocalSpace", PREFIX .. b.key, true)
                ctx.call("SetParticleSystemNonVisibleUpdateTimeout", PREFIX .. b.key, 2.0)
                ctx.call("SetParticleEmitterEmissionRate", PREFIX .. b.key, 0, 0)
            end
        end
        if F.failures == #BANDS then F.failed = true; return end
        F.live = true
    end

    local function show(on)
        if F.hidden == not on then return end
        F.hidden = not on
        for _, b in ipairs(BANDS) do
            ctx.call("SetParticleSystemEmitting", PREFIX .. b.key, on)
            ctx.call("SetParticleSystemVisible", PREFIX .. b.key, on)
        end
    end

    -- s: the track (nil = no tornado), view: {x,z} of the local camera, now: s clock.
    function F.Update(dt, s, view, now)
        if s == nil then
            if F.live then F.Destroy() end
            return
        end
        if F.failed then return end
        if not F.live then create(); if not F.live then return end end
        local near = true
        if view then
            local dx, dz = s.x - view.x, s.z - view.z
            near = sqrt(dx * dx + dz * dz) < Tornado.FAR
        end
        show(near)
        if not near then return end
        local grow = math.max(0, math.min(1, s.t / Tornado.GROW))
        local q = math.max(0, tonumber(ctx.quality and ctx.quality()) or 1)
        local y = ctx.ground(s.x, s.z)
        for _, b in ipairs(BANDS) do
            F.angle[b.key] = (F.angle[b.key] + b.spin * dt) % 6.2831853
            ctx.call("SetParticleSystemPosition", PREFIX .. b.key, ctx.vec(s.x, y, s.z))
        end
        if now >= F.nextTurn then
            F.nextTurn = now + 0.05
            for _, b in ipairs(BANDS) do
                if b.spin ~= 0 then
                    local a = F.angle[b.key]
                    ctx.call("SetParticleSystemDirection", PREFIX .. b.key, ctx.vec(cos(a), 0, sin(a)))
                end
                ctx.call("SetParticleEmitterEmissionRate", PREFIX .. b.key, 0, b.rate * grow * q)
            end
        end
        if now >= F.nextLight then
            F.nextLight = now + 0.1
            local flick = 0.8 + 0.2 * sin(now * 9.1) + 0.1 * sin(now * 23.7)
            if not F.lit and ctx.call("CreatePointLight", LIGHT, ctx.vec(s.x, y + 14, s.z), { r = 1, g = 0.33, b = 0.07 }, 150) == true then
                F.lit = true
            end
            if F.lit then
                ctx.call("SetPointLightPosition", LIGHT, ctx.vec(s.x, y + 14, s.z))
                ctx.call("SetPointLightPowerScale", LIGHT, 1.6 * grow * flick)
            end
        end
    end

    function F.Destroy()
        for _, b in ipairs(BANDS) do
            ctx.call("DetachParticleSystem", PREFIX .. b.key)
            ctx.call("DestroyParticleSystem", PREFIX .. b.key)
        end
        if F.lit then ctx.call("DestroyPointLight", LIGHT) end
        F.live, F.lit, F.hidden = false, false, false
    end

    function F.Describe()
        return { live = F.live, failed = F.failed, failures = F.failures, hidden = F.hidden, light = F.lit }
    end
    return F
end

return Tornado
