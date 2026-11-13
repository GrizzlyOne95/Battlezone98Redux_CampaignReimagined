-- Execute the cosmetic rupture service against strict EXU-shaped calls. Rendering
-- still needs the native smoke; this covers light/resource ownership and budget.
assert(_VERSION == "Lua 5.1")
package.path = "Scripts/?.lua;" .. package.path
local Fissures = require("CRStorm18Fissures")
local Rng = require("CRStorm18Rng")
local checks = 0
local function check(v, msg) checks = checks + 1; assert(v, msg) end
local function size(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < 1e9 end
local function vector(v) return v and finite(v.x) and finite(v.y) and finite(v.z) end
local function colour(v) return v and finite(v.r) and finite(v.g) and finite(v.b) end
local function fixture(opts)
    opts = opts or {}
    local w = { now = 0, systems = {}, lights = {}, created = {}, requests = 0, dims = {}, powers = {}, quality = 1 }
    local ctx = {
        seed = opts.seed or 18018, hash = Rng.Hash, vec = function(x, y, z) return {x = x, y = y, z = z} end,
        sites = {bounds = {0, 97280, 2560, 102400}},
        ready = function() return not opts.noPayload end,
        quality = function() return w.quality end,
        clock = function() return w.now end,
        height = function(x, z)
            if opts.noTerrain then return nil end
            if opts.cliffs then return 100, {x = .8, y = .6, z = 0} end
            if opts.rough then return 100 + math.sin(x * 3) * 20, {x = 0, y = 1, z = 0} end
            return 100 + (opts.slope and x * .1 or 0), {x = opts.slope and -.0995 or 0, y = opts.slope and .995 or 1, z = 0}
        end,
    }
    if opts.water then
        local rows = {}
        for i = 1, 1025 do rows[i] = {0, 513} end
        ctx.sites.watermask = {originX = 0, originZ = 97280, cell = 5, firstRow = 0, rows = rows}
    end
    local limits = { ["CR18/FissureMouth"] = 1, ["CR18/FissureRays"] = 5, ["CR18/FissureEmbers"] = 5 }
    ctx.call = function(fn, name, ...)
        local a = {...}
        if fn == "MaterialExists" then
            return not opts.noMaterials
        elseif fn == "CreateParticleSystem" then
            check(limits[a[1]] and vector(a[2]), "particle template and sim-space origin")
            if opts.noMouth and a[1] == "CR18/FissureMouth" then return false end
            check(not w.systems[name], "no duplicate system creation")
            w.systems[name] = {slots = limits[a[1]], origin = a[2], rates = {}}
            if a[1] == "CR18/FissureMouth" then w.created[#w.created + 1] = a[2] end
            return true
        elseif fn == "DetachParticleSystem" then
            check(w.systems[name] ~= nil, "detach only own live system"); return true
        elseif fn == "DestroyParticleSystem" then
            check(w.systems[name] ~= nil, "destroy only own live system"); w.systems[name] = nil; return true
        elseif fn == "CreatePointLight" then
            w.requests = w.requests + 1
            check(vector(a[1]) and colour(a[2]), "native point light uses named RGB and sim-space vector")
            check(a[2].r >= 3 and a[2].r > a[2].g * 20, "light is bright saturated red")
            check(a[3] == Fissures.LIGHT_RANGE and a[3] <= 50, "bounded light influence")
            if opts.noLights then return false end
            check(not w.lights[name], "no duplicate light")
            w.lights[name] = {pos = a[1]}; return true
        elseif fn == "DestroyPointLight" then
            check(w.lights[name] ~= nil, "only destroys a successfully created light")
            w.lights[name] = nil; return true
        elseif fn == "SetPointLightPowerScale" then
            check(w.lights[name] and finite(a[1]) and a[1] >= 0 and a[1] <= 1.81, "bounded pulse on an owned light")
            w.powers[#w.powers + 1] = a[1]; return true
        end
        local s = w.systems[name]
        check(s ~= nil, fn .. " addresses a live owned system")
        if fn == "SetParticleSystemDefaultDimensions" then
            check(finite(a[1]) and finite(a[2]) and a[1] > 0 and a[2] > 0, "positive dimensions")
            w.dims[name] = {a[1], a[2]}
        elseif fn == "SetParticleEmitterEmissionRate" then
            check(a[1] >= 0 and a[1] < s.slots and finite(a[2]) and a[2] >= 0, "valid emitter/rate")
            s.rates[a[1]] = a[2]
        elseif fn == "SetParticleEmitterPosition" or fn == "SetParticleEmitterDirection" then
            check(a[1] >= 0 and a[1] < s.slots and vector(a[2]), "valid emitter/local vector")
        elseif fn == "SetParticleEmitterColor" then
            check(a[1] == 0 and colour(a[2]) and finite(a[2].a), "native RGBA emitter colour")
        elseif fn == "SetParticleAffectorParameter" then
            check(a[1] == 1 and (a[2] == "rotation_range_start" or a[2] == "rotation_range_end")
                and finite(tonumber(a[3])), "mouth Rotator is affector 1")
        else
            check(fn == "SetParticleSystemKeepLocalSpace" or fn == "SetParticleSystemNonVisibleUpdateTimeout", "known EXU call " .. fn)
        end
        return true
    end
    w.ctx, w.fx = ctx, Fissures.Create(ctx)
    w.view = {x = 1300, y = 110, z = 99000}
    function w.run(seconds, density)
        for _ = 1, math.floor(seconds * 10 + .5) do
            w.now = w.now + .1
            w.fx.Update(w.view, density)
            check(w.fx.Describe().active <= 2 and size(w.lights) <= 2 and size(w.systems) <= 6, "two-light/six-system cap")
        end
    end
    return w
end

local w = fixture()
w.run(90, 0)
check(w.fx.Describe().spawned == 0 and size(w.lights) == 0, "no major ruptures before core destruction")
w.run(8, .12)
check(w.fx.Describe().spawned == 0, "core1 has a quiet lead-in")
w.run(5, .12)
check(w.fx.Describe().spawned == 1 and size(w.lights) == 1, "core1 opens a large illuminated rupture")
local origin = w.created[1]
local d = math.sqrt((origin.x - w.view.x)^2 + (origin.z - w.view.z)^2)
check(d >= 45 and d <= 95, "opening is visible nearby but away from the viewer")
local mouth = w.dims["CR18/Fissure/1/mouth"]
check(mouth and mouth[1] >= 44 and mouth[1] <= 60 and mouth[2] > 8, "mouth is tens of metres long and grows wide")
do
    -- Ogre 1.10 rotates these vertices around -normal. Compare the authored UV
    -- hot-core points against actual shaft world positions, including sim Z.
    local r = w.fx.active[1]
    local angle = math.rad(r.angle)
    local uv = {{.15, .52}, {.325, .38}, {.5, .60}, {.675, .52}, {.85, .47}}
    for i, p in ipairs(uv) do
        local x, y = (p[1] - .5) * r.length, (.5 - p[2]) * r.width
        local rx = x * math.cos(angle) + y * math.sin(angle)
        local rz = x * math.sin(angle) - y * math.cos(angle)
        check(math.abs(r.nodes[i].x - r.x - rx) < 1e-6 and math.abs(r.nodes[i].z - r.z + rz) < 1e-6,
            "shaft follows the rotated hot-core UV rather than mirrored ground coordinates")
    end
end
w.run(160, .12)
local early = w.fx.Describe().spawned
check(early >= 3 and early <= 5, "early large ruptures remain occasional")
w.run(160, 1)
check(w.fx.Describe().spawned - early >= 6, "collapse increases rupture frequency")
local lo, hi = math.huge, 0
for _, p in ipairs(w.powers) do lo, hi = math.min(lo, p), math.max(hi, p) end
check(lo < .2 and hi > 1.4, "light swells from dark to hot rather than staying at full power")
w.run(1, 0)
check(size(w.systems) == 0 and size(w.lights) == 0, "zero density clears resources")
w.run(13, 1)
check(w.fx.Describe().active > 0, "resources recover when activity returns")
w.quality = 0; w.run(1, 1)
check(size(w.systems) == 0 and size(w.lights) == 0, "quality zero removes beams and point lights")
w.quality = 1; w.run(14, 1)
check(size(w.lights) > 0, "quality restores later ruptures")
w.fx.Stop(); w.fx.Stop(); w.run(50, 1)
check(size(w.systems) == 0 and size(w.lights) == 0, "idempotent Stop releases all owned resources and prevents recreation")

local a, b = fixture(), fixture()
a.run(120, 1); b.run(120, 1)
check(#a.created == #b.created and #a.created >= 4, "shared seed/clock schedule repeats")
for i, p in ipairs(a.created) do check(p.x == b.created[i].x and p.z == b.created[i].z, "same camera yields same cosmetic positions") end
a.fx.Stop(); b.fx.Stop()

for _, opts in ipairs({{noPayload = true}, {noTerrain = true}, {cliffs = true}, {rough = true}, {water = true}, {noMouth = true}, {noMaterials = true}}) do
    local f = fixture(opts); f.run(65, 1)
    check(f.fx.Describe().active == 0 and size(f.systems) == 0 and size(f.lights) == 0, "unavailable assets or unsuitable terrain leave no partial resources")
    f.fx.Stop()
end
local refused = fixture({noLights = true}); refused.run(35, 1)
check(#refused.created > 0 and refused.requests > 0 and refused.requests < 25, "light cap/refusal leaves the mouth and retries with backoff")
refused.fx.Stop()
local slope = fixture({slope = true}); slope.run(16, 1)
check(slope.fx.Describe().active == 1, "a suitable sloped terrain plane accepts a mouth")
slope.view.x = slope.view.x + 1000; slope.run(.1, 1)
check(slope.fx.Describe().active == 0 and size(slope.lights) == 0, "leaving the area releases the light immediately")
slope.fx.Stop()
print("CRSTORM18 FISSURES OK (" .. checks .. " checks)")
