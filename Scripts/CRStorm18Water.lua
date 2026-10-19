-- CRStorm18Water: mission 18's water and how the storm works on it.
-- Peer-local and visual only (no events): every peer builds the baked pools,
-- streams and cascade itself and drives the look from its own copy of the
-- storm level, which the replicated phase already keeps in step.
--
--   geometry  three StaticGeometry sheets from the generated meshes
--             (Tools/Build-Misn18Water.py): CR18/Pools, CR18/Streams, CR18/Cascade
--   storm     the CR18_Water_v1 program reads two pass colours per material:
--             diffuse = (mud rgb, mud amount), specular.r = extra scroll phase.
--             Mud rises with the level (the streams run brown); the extra phase is
--             integrated here so a speed change never makes the water jump. It wraps
--             at PHASE_WRAP, which every material's scroll rate divides evenly.
--   mist      CR18/CascadeMist at the foot of the fall; its rate follows the level
--   Stop      writes the calm pass colours back (materials outlive the Lua state)
--   wakes     W.WakeSurface(x, z) is CRWake's resolver: water over the mask, else mud
--
-- Every engine call is guarded; no EXU, a missing material or a failed create
-- degrades to less water, never to an error.
local Water = {}

Water.PHASE_WRAP = 1000
Water.INTERVAL = 0.08      -- s between material writes while the water is changing
Water.IDLE = 1.0           -- s between writes while it is not
Water.RETRY = 30           -- s before a failed sheet is tried again
Water.MASK_LIFT = 0.5      -- m a wake rises over the mask (streams sit 0.15 m up, pools up to 2 m)
Water.SHEETS = {           -- name, sites key, render distance, mud colour
    { name = "CR18/Pools", key = "pools", distance = 360, mud = { 0.20, 0.14, 0.08 } },
    { name = "CR18/Streams", key = "streams", distance = 300, mud = { 0.34, 0.23, 0.13 } },
    { name = "CR18/Cascade", key = "cascade", distance = 300, mud = { 0.40, 0.29, 0.18 } },
}
Water.MIST = "CR18/CascadeMist"

local floor, max, min = math.floor, math.max, math.min
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function smooth(t) t = clamp(t, 0, 1); return t * t * (3 - 2 * t) end
local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

-- What the storm does to the water at `level` (0..1) with the ascent's gale `wind`
-- (1 normally, 1.7 in the ascent). Pure. `violent` is 0 below 0.9 and 1 from the
-- collapse's level up: collapse, final, extract and ascent are the most violent look.
function Water.Params(level, wind)
    level = clamp(tonumber(level) or 0, 0, 1)
    wind = clamp(tonumber(wind) or 1, 1, 2)
    local violent = smooth((level - 0.9) / 0.1)
    local gale = 1 + 0.45 * (wind - 1)
    return {
        mud = clamp((level - 0.10) / 0.90, 0, 1) ^ 0.9,
        streams = (1 + 2.2 * level + violent) * gale,
        pools = (1 + 9 * level + 4 * violent) * gale,
        cascade = (1 + 1.2 * level + 0.8 * violent) * gale,
        mist = (16 + 54 * level + 30 * violent) * (1 + 0.5 * (wind - 1)),
        violent = violent,
    }
end

-- Is (x, z) a cell of the generated water mask? (Same run-length format as CRJungle17Sites.)
function Water.InMask(sites, px, pz)
    local m = sites and sites.watermask
    if not m then return false end
    local row = m.rows[floor((pz - m.originZ) / m.cell + 0.5) - m.firstRow + 1]
    if not row then return false end
    local col = floor((px - m.originX) / m.cell + 0.5)
    for i = 1, #row - 1, 2 do
        local start = row[i]
        if col < start then return false end
        if col < start + row[i + 1] then return true end
    end
    return false
end

-- ctx: call(name, ...), call2(name, ...), vec(x, y, z), sites, ready() (templates),
-- clock(), quality() (optional)
function Water.Create(ctx)
    local W = { built = {}, retry = {}, phase = {}, writes = 0, errors = 0, lastError = nil, mist = false,
                mistRate = nil, nextWrite = 0, nextMist = 0, stopped = false, params = Water.Params(0, 1), sheetsBuilt = 0 }
    local sites = ctx.sites or {}
    local water = sites.water
    for _, s in ipairs(Water.SHEETS) do W.phase[s.key] = 0 end

    local function colours(sheet, mudAmount, phaseValue)
        local mud = sheet.mud
        return {
            ambient = { r = 1, g = 1, b = 1, a = 1 },
            diffuse = { r = mud[1], g = mud[2], b = mud[3], a = mudAmount },
            specular = { r = phaseValue, g = 0, b = 0, a = 0 },
            emissive = { r = 0, g = 0, b = 0, a = 1 },
        }
    end

    local function write(p, calm)
        for _, s in ipairs(Water.SHEETS) do
            ctx.call("SetMaterialPassColors", s.name, colours(s, calm and 0 or p.mud, calm and 0 or W.phase[s.key]), -1, -1, nil, false)
        end
        W.writes = W.writes + 1
    end

    local function buildSheet(s)
        local site = water and water[s.key]
        if not site or W.built[s.key] or (W.retry[s.key] or 0) > ctx.clock() then return end
        if ctx.call("MaterialExists", s.name, "General") == false then
            W.retry[s.key] = ctx.clock() + Water.RETRY
            W.lastError = s.name .. " is not loaded"
            return
        end
        local p = site.position
        local info, reason = ctx.call2("CreateStaticGeometry", s.name, site.mesh, nil,
            { { position = { x = p[1], y = p[2], z = p[3] }, scale = 1 } },
            { origin = { x = 0, y = 0, z = 97280 }, regionDimensions = { x = 128, y = 256, z = 128 },
              renderingDistance = s.distance, castShadows = false, visible = true })
        if info then
            W.built[s.key] = true
            W.sheetsBuilt = W.sheetsBuilt + 1
            W.nextWrite = 0
        else
            W.errors = W.errors + 1
            W.lastError = tostring(reason or "CreateStaticGeometry unavailable")
            W.retry[s.key] = ctx.clock() + Water.RETRY
        end
    end

    local function ensureMist()
        local c = sites.cascade
        if W.mist or type(c) ~= "table" or not finite(c.x) or ctx.clock() < W.nextMist then return end
        if not ctx.ready() then W.nextMist = ctx.clock() + 5; return end
        W.nextMist = ctx.clock() + Water.RETRY
        local ok = ctx.call("CreateParticleSystem", Water.MIST, Water.MIST, ctx.vec(c.x, c.y + 1, c.z))
        if ok == true then
            ctx.call("SetParticleSystemKeepLocalSpace", Water.MIST, false)
            W.mist, W.mistRate = true, nil
        end
    end

    -- level: the storm's smoothed level; wind: the phase's gale factor (1 normally)
    function W.Update(dt, level, wind)
        if W.stopped then return end
        dt = clamp(tonumber(dt) or 0, 0, 1)
        local p = Water.Params(level, wind)
        W.params = p
        for _, s in ipairs(Water.SHEETS) do
            if not W.built[s.key] then buildSheet(s); break end -- one create a frame
        end
        ensureMist()
        for _, s in ipairs(Water.SHEETS) do
            local k = s.key
            W.phase[k] = (W.phase[k] + (p[k] - 1) * dt) % Water.PHASE_WRAP
        end
        local now = ctx.clock()
        if W.sheetsBuilt > 0 and now >= W.nextWrite then
            local moving = p.pools > 1.001 or p.mud > 0.001
            W.nextWrite = now + (moving and Water.INTERVAL or Water.IDLE)
            write(p, false)
        end
        if W.mist then
            local q = ctx.quality and ctx.quality() or 1
            local rate = floor(p.mist * min(1, max(0.2, tonumber(q) or 1)) + 0.5)
            if rate ~= W.mistRate then
                W.mistRate = rate
                ctx.call("SetParticleEmitterEmissionRate", Water.MIST, 0, rate)
            end
        end
    end

    -- Wake resolver for CRWake: water over the mask, else the scorched mud.
    function W.WakeSurface(px, pz)
        if Water.InMask(sites, px, pz) then return "water", 1, Water.MASK_LIFT end
        return "mud", 0.6 + 0.4 * W.params.mud, 0
    end

    function W.Stop()
        W.stopped = true
        for _, s in ipairs(Water.SHEETS) do
            if W.built[s.key] then ctx.call("DestroyStaticGeometry", s.name) end
        end
        if W.mist then
            ctx.call("SetParticleEmitterEmissionRate", Water.MIST, 0, 0)
            ctx.call("DestroyParticleSystem", Water.MIST)
        end
        write(Water.Params(0, 1), true)
        W.built, W.mist = {}, false
    end

    function W.Describe()
        return { sheets = W.sheetsBuilt, mist = W.mist, mistRate = W.mistRate or 0, mud = W.params.mud,
                 streams = W.params.streams, pools = W.params.pools, cascade = W.params.cascade,
                 phase = { pools = W.phase.pools, streams = W.phase.streams, cascade = W.phase.cascade },
                 writes = W.writes, errors = W.errors, lastError = W.lastError }
    end
    return W
end

return Water
