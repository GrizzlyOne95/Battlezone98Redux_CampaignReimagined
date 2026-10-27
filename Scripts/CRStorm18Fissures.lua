-- Rare, large ruptures under Mission 18's ordinary crack field. Cosmetic and
-- peer-local, like the existing ground decals: no terrain/collision/damage writes.
-- A charred, white-hot mouth, five rising shafts and embers share one short-range
-- EXU light. Point lights illuminate in all directions; upright billboards carry
-- the visible upward light. Never reserve more than two of EXU's eight lights.
local Water = require("CRStorm18Water")
local Fissures = {}
Fissures.MAX = 2
Fissures.FAR = 180
Fissures.LIGHT_RANGE = 48
Fissures.STEP = 0.10
-- Samples along c18rift's winding hot core. Texture V increases toward -up;
-- the ground billboard's up axis is render -Z (sim +Z).
local NODES = { {-.35, -.02}, {-.175, .12}, {0, -.10}, {.175, -.02}, {.35, .03} }
local PARTS = {
    { key = "mouth", template = "CR18/FissureMouth", material = "CR18/FissureMouth", slots = 1 },
    { key = "rays", template = "CR18/FissureRays", material = "CR18/FissureRay", slots = 5 },
    { key = "embers", template = "CR18/FissureEmbers", material = "CR18/Cinder", slots = 5 },
}
local sin, cos, min, max = math.sin, math.cos, math.min, math.max
local function clamp(v, lo, hi) return max(lo, min(hi, v)) end
local function smooth(v) v = clamp(v, 0, 1); return v * v * (3 - 2 * v) end

-- ctx uses the storm ground adapter: clock, height, vec, call, ready, hash, seed,
-- sites, sound, and optional quality. All engine operations go through call.
function Fissures.Create(ctx)
    local F = { active = {}, serial = 0, spawned = 0, nextSpawn = nil, nextWrite = 0, stopped = false }
    local collapse = false
    local function hash(n, k) return ctx.hash(ctx.seed, n, k, 1818) end
    local function prefix(slot) return "CR18/Fissure/" .. slot .. "/" end

    local function destroy(slot)
        local r = F.active[slot]
        if not r then return end
        for _, part in ipairs(PARTS) do
            if r.parts[part.key] then
                local name = prefix(slot) .. part.key
                ctx.call("DetachParticleSystem", name)
                ctx.call("DestroyParticleSystem", name)
            end
        end
        if r.light then ctx.call("DestroyPointLight", prefix(slot) .. "light") end
        F.active[slot] = nil
    end

    -- Reject water, cliffs, map edges and rough ground: one large flat decal
    -- must fit the terrain plane, rather than bridge a gully or cut into a hill.
    local function pick(view, n)
        local bounds = ctx.sites.bounds or {0, 97280, 2560, 102400}
        for attempt = 1, 16 do
            local a = hash(n, attempt * 5) * math.pi * 2
            local d = 45 + 50 * hash(n, attempt * 5 + 1)
            local px, pz = view.x + cos(a) * d, view.z + sin(a) * d
            local h, normal = ctx.height(px, pz)
            if h and normal and normal.y >= .92 then
                local bearing = hash(n, attempt * 5 + 2) * math.pi * 2
                local length = 44 + 16 * hash(n, attempt * 5 + 3)
                local width = length / 3
                local cb, sb = cos(bearing), sin(bearing)
                local points, good = {}, true
                -- Include the full decal footprint, beyond the five light shafts.
                for _, uv in ipairs({ {-.5, -.5}, {-.5, .5}, {.5, -.5}, {.5, .5}, unpack(NODES) }) do
                    local dx = cb * uv[1] * length - sb * uv[2] * width
                    local dz = sb * uv[1] * length + cb * uv[2] * width
                    local x, z = px + dx, pz + dz
                    local y, nn = ctx.height(x, z)
                    local plane = h - (normal.x * dx + normal.z * dz) / normal.y
                    if not y or not nn or nn.y < .90 or math.abs(y - plane) > .35
                        or x < bounds[1] + 12 or x > bounds[3] - 12
                        or z < bounds[2] + 12 or z > bounds[4] - 12
                        or Water.InMask(ctx.sites, x, z) then good = false; break end
                    points[#points + 1] = {x = x, y = y, z = z}
                end
                if good and not Water.InMask(ctx.sites, px, pz) then
                    local overlap = false
                    for _, r in pairs(F.active) do
                        local dx, dz = px - r.x, pz - r.z
                        if dx * dx + dz * dz < 65 * 65 then overlap = true end
                    end
                    if not overlap then
                        local nodes = {}
                        for i = 1, #NODES do nodes[i] = points[i + 4] end
                        -- Ogre's vertex rotation axis faces opposite the decal normal.
                        return { x = px, y = h, z = pz, normal = normal, angle = -math.deg(bearing),
                            length = length, width = width, nodes = nodes }
                    end
                end
            end
        end
    end

    local function create(slot, view)
        if ctx.call("MaterialExists", "CR18/FissureMouth", "General") == false then return false end
        F.serial = F.serial + 1
        local r = pick(view, F.serial)
        if not r then return false end
        r.born, r.life = ctx.clock(), 22 + 6 * hash(F.serial, 100)
        r.parts, r.nextLight = {}, 0
        local origin = ctx.vec(r.x, r.y, r.z)
        for _, part in ipairs(PARTS) do
            local name = prefix(slot) .. part.key
            if ctx.call("MaterialExists", part.material, "General") ~= false
                and ctx.call("CreateParticleSystem", name, part.template, origin) == true then
                r.parts[part.key] = true
                ctx.call("SetParticleSystemKeepLocalSpace", name, false)
                ctx.call("SetParticleSystemNonVisibleUpdateTimeout", name, 2)
                for i = 0, part.slots - 1 do ctx.call("SetParticleEmitterEmissionRate", name, i, 0) end
            end
        end
        F.active[slot] = r
        if not r.parts.mouth then destroy(slot); return false end
        local mouth = prefix(slot) .. "mouth"
        ctx.call("SetParticleEmitterPosition", mouth, 0, ctx.vec(0, .16, 0))
        ctx.call("SetParticleEmitterDirection", mouth, 0, ctx.vec(r.normal.x, r.normal.y, -r.normal.z))
        ctx.call("SetParticleAffectorParameter", mouth, 1, "rotation_range_start", tostring(r.angle))
        ctx.call("SetParticleAffectorParameter", mouth, 1, "rotation_range_end", tostring(r.angle))
        if r.parts.embers then
            for i, p in ipairs(r.nodes) do
                ctx.call("SetParticleEmitterPosition", prefix(slot) .. "embers", i - 1,
                    ctx.vec(p.x - r.x, p.y - r.y + .35, -(p.z - r.z)))
            end
        end
        F.spawned = F.spawned + 1
        if ctx.sound then ctx.sound("gquak00.wav") end
        return true
    end

    local function write(slot, r, now, quality)
        local age = now - r.born
        local open = smooth(age / 2.8) * smooth((r.life - age) / 4)
        -- Irregular surges, not an on/off strobe. Both geometry and light breathe.
        local pulse = .82 + .12 * sin(age * 4.1) + .06 * sin(age * 11.3 + slot)
        local heat = open * pulse
        local name = prefix(slot)
        ctx.call("SetParticleSystemDefaultDimensions", name .. "mouth", r.length, r.width * (.14 + .86 * open))
        ctx.call("SetParticleEmitterColor", name .. "mouth", 0, {r = 1, g = 1, b = 1, a = heat})
        ctx.call("SetParticleEmitterEmissionRate", name .. "mouth", 0, 3)
        if r.parts.rays then
            local tall = (24 + 12 * sin(age * .7) ^ 2) * (.2 + .8 * open)
            ctx.call("SetParticleSystemDefaultDimensions", name .. "rays", 5.5 * open + .3, tall)
            for i, p in ipairs(r.nodes) do
                ctx.call("SetParticleEmitterPosition", name .. "rays", i - 1,
                    ctx.vec(p.x - r.x, p.y - r.y + tall * .5, -(p.z - r.z)))
                ctx.call("SetParticleEmitterEmissionRate", name .. "rays", i - 1, 3 * heat * min(1, quality))
            end
        end
        if r.parts.embers then
            for i = 0, #NODES - 1 do
                ctx.call("SetParticleEmitterEmissionRate", name .. "embers", i, 8 * heat * min(1, quality))
            end
        end
        -- One actual red pool of light above the mouth, with a small range to
        -- avoid competing with every headlight/explosion on a terrain patch.
        if not r.light and now >= r.nextLight then
            r.nextLight = now + 2
            r.light = ctx.call("CreatePointLight", name .. "light", ctx.vec(r.x, r.y + 2.5, r.z),
                {r = 4, g = .035, b = .008}, Fissures.LIGHT_RANGE) == true
        end
        if r.light then ctx.call("SetPointLightPowerScale", name .. "light", 1.8 * heat) end
    end

    function F.Update(view, density)
        if F.stopped or not view then return end
        local now = ctx.clock()
        local quality = ctx.quality and tonumber(ctx.quality()) or 1
        quality = max(0, quality or 1)
        density = clamp(tonumber(density) or 0, 0, 1)
        for slot, r in pairs(F.active) do
            local dx, dz = view.x - r.x, view.z - r.z
            if quality == 0 or density == 0 or now - r.born >= r.life or dx * dx + dz * dz > Fissures.FAR ^ 2 then destroy(slot) end
        end
        if quality == 0 or density == 0 then F.nextSpawn = nil; return end
        if not F.nextSpawn then F.nextSpawn = now + 9 end
        if density >= .80 and not collapse then collapse = true; F.nextSpawn = min(F.nextSpawn, now + 1) end
        if now >= F.nextSpawn then
            F.nextSpawn = now + 5 -- back off on unavailable payload or unsuitable ground
            if ctx.ready() then
                for slot = 1, Fissures.MAX do
                    if not F.active[slot] then
                        if create(slot, view) then F.nextSpawn = now + 48 - 30 * density + 6 * hash(F.serial, 101) end
                        break
                    end
                end
            end
        end
        if now >= F.nextWrite then
            F.nextWrite = now + Fissures.STEP
            for slot, r in pairs(F.active) do write(slot, r, now, quality) end
        end
    end

    function F.Stop()
        for slot = 1, Fissures.MAX do destroy(slot) end
        F.stopped = true
    end

    function F.Describe()
        local live, lights = 0, 0
        for _, r in pairs(F.active) do live = live + 1; if r.light then lights = lights + 1 end end
        return { active = live, lights = lights, spawned = F.spawned }
    end
    return F
end
return Fissures
