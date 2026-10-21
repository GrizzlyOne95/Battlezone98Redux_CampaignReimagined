-- CRStorm18Ground: everything mission 18's storm does to the ground.
-- Peer-local and visual only: each peer builds it around its own camera from
-- the shared seed, so no ground state ever crosses the wire.
--
--   scrub     dead ground cover (the baked misn17 meshes on the scorched atlas),
--             streamed in StaticGeometry tiles around the camera: a tile builds
--             inside BUILD m and is destroyed beyond DROP m, one build a frame,
--             so only a few hundred plants exist at once (misn17 builds all
--             31,000 up front and holds 45 ms frames near its trees; here the
--             resident set is about a tenth of that)
--   cracks    glowing fissures with a soot stain and a dust burst, laid on a
--             world-aligned grid. A cell holds a crack when hash(seed, cell) is
--             under the phase's density, so raising the density only ever ADDS
--             cracks: they appear progressively and every peer agrees
--   slides    a dust cloud and a spray of rock sliding down a steep slope near
--             the camera, leader-timed (event), shaped locally
local okDamage,Damage=pcall(require,"CRFloraDamage")
if not okDamage then Damage=nil end
local Fissures = require("CRStorm18Fissures")
local Ground = {}

-- Tunables -------------------------------------------------------------------
Ground.BUILD = 520          -- m: build a scrub tile when its centre is this close
Ground.DROP = 700           -- m: destroy it beyond this
Ground.RENDER = 260         -- m: StaticGeometry cull distance (the misn17 value)
Ground.TILE_RETRY = 30      -- s before a failed tile is tried again
Ground.CELL = 20            -- m: crack grid
Ground.CRACK_RADIUS = 95    -- m around the camera that holds cracks
Ground.CRACK_MAX = 0.55     -- fraction of cells holding a crack at density 1
Ground.CRACK_LIFE = 15.5    -- s before a crack still in view is laid again (ttl is 18)
Ground.SOOT_LIFE = 21       -- s, likewise (ttl is 26)
Ground.CRACKS_PER_TICK = 3
Ground.SLIDES = 3           -- simultaneous landslides
Ground.MIN_NORMAL_Y = 0.78  -- no crack decal on slopes steeper than this

local floor, sqrt, cos, sin = math.floor, math.sqrt, math.cos, math.sin

-- ctx: call(fn, ...), vec, ready(), seed, hash(seed,a,b,c), sites, anchorFor(view),
-- height(x, z) -> h, normal|nil, material() -> name, sound(file, pos)
function Ground.Create(ctx)
    local G = { tiles = {}, retry = {}, built = 0, destroyed = 0, errors = 0, lastError = nil,
                laid = {}, cracksLaid = 0, slides = {}, slidesStarted = 0, nextTile = 0, nextCrack = 0,
                sets = nil, anchor = nil, slideSets = nil, material = nil, ringDistance = 0 }
    local sites = ctx.sites or { layers = {} }
    local layers = sites.layers or {}
    local fissures = Fissures.Create(ctx)

    -- Scrub -------------------------------------------------------------------
    local function tileName(i) return "CR18/Scrub/" .. i end
    local removed=ctx.flora or {}
    if Damage then
        for i,l in ipairs(layers) do
            local name=tileName(i)
            local o=sites.origin or {0,0,0}
            removed[name]=Damage.Register(name,{mesh=l.mesh,points=l.instances,material=ctx.material(),
                options={origin={x=o[1],y=o[2],z=o[3]},regionDimensions={x=192,y=256,z=192},
                    renderingDistance=Ground.RENDER,castShadows=false,visible=true},
                onRemove=ctx.removeLitter},removed[name])
            if ctx.removeLitter then for pi,p in ipairs(l.instances) do
                if Damage.IsRemoved(name,pi) then ctx.removeLitter(p) end
            end end
        end
    end

    local function nearest(view)
        local best, bestD
        for i = 1, #layers do
            if not G.tiles[i] and (G.retry[i] or 0) <= ctx.clock() then
                local l = layers[i]
                local dx, dz = l.cx - view.x, l.cz - view.z
                local d = dx * dx + dz * dz
                if d < Ground.BUILD * Ground.BUILD and (not bestD or d < bestD) then best, bestD = i, d end
            end
        end
        return best
    end

    local function buildTile(i)
        local l = layers[i]
        local instances=Damage and Damage.Instances(tileName(i)) or nil
        if not instances then
            instances={}
            for k,p in ipairs(l.instances) do
                instances[k]={position={x=p[1],y=p[2],z=p[3]},yaw=p[4],scale=p[5]}
            end
        end
        if #instances==0 then G.tiles[i]=true;return end
        local o = sites.origin or { 0, 0, 0 }
        local material = G.material or ctx.material()
        G.material = material
        local info, reason = ctx.call2("CreateStaticGeometry", tileName(i), l.mesh, material, instances,
            { origin = { x = o[1], y = o[2], z = o[3] }, regionDimensions = { x = 192, y = 256, z = 192 },
              renderingDistance = Ground.RENDER, castShadows = false, visible = true })
        if info then
            if Damage then Damage.Resident(tileName(i),true) end
            G.tiles[i] = true
            G.built = G.built + 1
        else
            G.errors = G.errors + 1
            G.lastError = tostring(reason or "CreateStaticGeometry unavailable")
            G.retry[i] = ctx.clock() + Ground.TILE_RETRY
        end
    end

    local function updateScrub(view)
        if ctx.clock() < G.nextTile then return end
        G.nextTile = ctx.clock() + 0.25
        local drops = 0
        for i in pairs(G.tiles) do
            local l = layers[i]
            local dx, dz = l.cx - view.x, l.cz - view.z
            if dx * dx + dz * dz > Ground.DROP * Ground.DROP and drops < 2 then
                ctx.call("DestroyStaticGeometry", tileName(i))
                if Damage then Damage.Resident(tileName(i),false) end
                G.tiles[i] = nil
                G.destroyed = G.destroyed + 1
                drops = drops + 1
            end
        end
        local i = nearest(view)
        if i then buildTile(i) end
    end

    -- Emitter-slot sets (the CRGroundFX.Print pattern) ----------------------------
    local function newSet(name, template, slots)
        ctx.call("DetachParticleSystem", name)
        ctx.call("DestroyParticleSystem", name)
        if ctx.call("CreateParticleSystem", name, template, G.anchor) ~= true then return nil end
        ctx.call("SetParticleSystemKeepLocalSpace", name, false)
        ctx.call("SetParticleSystemNonVisibleUpdateTimeout", name, 2.0)
        for e = 0, slots - 1 do ctx.call("SetParticleEmitterEmissionRate", name, e, 0) end
        return { name = name, slots = slots, nextSlot = 0, off = {} }
    end

    local function fire(set, pos, normal, rate, on)
        local e = set.nextSlot
        set.nextSlot = (e + 1) % set.slots
        local a = G.anchor
        ctx.call("SetParticleEmitterPosition", set.name, e, ctx.vec(pos.x - a.x, pos.y - a.y, -(pos.z - a.z)))
        if normal then ctx.call("SetParticleEmitterDirection", set.name, e, ctx.vec(normal.x, normal.y, -normal.z)) end
        ctx.call("SetParticleEmitterEmissionRate", set.name, e, rate)
        set.off[e] = ctx.clock() + on
    end

    local function settle(set)
        local now = ctx.clock()
        for e, t in pairs(set.off) do
            if now >= t then
                ctx.call("SetParticleEmitterEmissionRate", set.name, e, 0)
                set.off[e] = nil
            end
        end
    end

    local function ensureSets(view)
        if G.sets ~= nil then return G.sets end
        if not ctx.ready() then G.sets = false; return false end
        G.anchor = ctx.vec(view.x, view.y or 0, view.z)
        local sets = {
            a = newSet("CR18/Ground/CrackA", "CR18/CrackA", 6),
            b = newSet("CR18/Ground/CrackB", "CR18/CrackB", 6),
            soot = newSet("CR18/Ground/Soot", "CR18/Soot", 6),
            puff = newSet("CR18/Ground/Puff", "CR18/CrackPuff", 6),
        }
        G.sets = (sets.a or sets.b) and sets or false
        return G.sets
    end

    -- A moved camera gets a node of its own: emitter offsets stay small. Slots
    -- are blinks of a tenth of a second, so none is re-placed.
    local function reanchor(view)
        local a = G.anchor
        local dx, dz = view.x - a.x, view.z - a.z
        if dx * dx + dz * dz < 300 * 300 then return end
        G.anchor = ctx.vec(view.x, view.y or 0, view.z)
        for _, set in pairs(G.sets) do ctx.call("SetParticleSystemPosition", set.name, G.anchor) end
    end

    -- Cracks ------------------------------------------------------------------
    -- rec: nil (first time), or the record of the last lay ({ t = crack time,
    -- s = soot time }). A crack that is still in view is re-laid before its 18 s
    -- life ends; its soot (26 s) a little later. Returns the new record.
    local function layCrack(i, j, rec)
        local px = (i + 0.15 + 0.7 * ctx.hash(ctx.seed, i, j, 2)) * Ground.CELL
        local pz = (j + 0.15 + 0.7 * ctx.hash(ctx.seed, i, j, 3)) * Ground.CELL
        local h, n = ctx.height(px, pz)
        if not h then return nil end
        if n and n.y < Ground.MIN_NORMAL_Y then return false end
        local now = ctx.clock()
        local normal = n or { x = 0, y = 1, z = 0 }
        local set = ctx.hash(ctx.seed, i, j, 4) < 0.5 and G.sets.a or G.sets.b
        if set then fire(set, { x = px, y = h + 0.06, z = pz }, normal, 40, 0.06) end
        local out = { t = now, s = rec and rec.s or now }
        if G.sets.soot and (rec == nil or now - rec.s >= Ground.SOOT_LIFE) then
            fire(G.sets.soot, { x = px, y = h + 0.03, z = pz }, normal, 40, 0.06)
            out.s = now
        end
        if rec == nil and G.sets.puff then fire(G.sets.puff, { x = px, y = h + 0.3, z = pz }, nil, 260, 0.05) end
        return out
    end

    local function updateCracks(view, density)
        if density <= 0 or not ensureSets(view) then return end
        if ctx.clock() < G.nextCrack then return end
        G.nextCrack = ctx.clock() + 0.35
        reanchor(view)
        local c = Ground.CELL
        local r = Ground.CRACK_RADIUS
        local i0, i1 = floor((view.x - r) / c), floor((view.x + r) / c)
        local j0, j1 = floor((view.z - r) / c), floor((view.z + r) / c)
        local now, laid = ctx.clock(), 0
        local share = density * Ground.CRACK_MAX
        for i = i0, i1 do
            for j = j0, j1 do
                if ctx.hash(ctx.seed, i, j, 1) < share then
                    local key = i * 100003 + j
                    local rec = G.laid[key]
                    if rec == nil or (rec ~= false and now - rec.t >= Ground.CRACK_LIFE) then
                        local cx, cz = (i + 0.5) * c - view.x, (j + 0.5) * c - view.z
                        if cx * cx + cz * cz <= r * r and laid < Ground.CRACKS_PER_TICK then
                            local made = layCrack(i, j, rec)
                            if made then
                                G.laid[key] = made
                                G.cracksLaid = G.cracksLaid + 1
                                laid = laid + 1
                            elseif made == false then
                                G.laid[key] = false -- too steep: never retry
                            end
                        end
                    end
                end
            end
        end
    end

    -- Landslides ---------------------------------------------------------------
    local function ensureSlideSets()
        if G.slideSets ~= nil then return G.slideSets end
        if not ctx.ready() then G.slideSets = false; return false end
        local sets = {}
        for k = 1, Ground.SLIDES do
            local d = newSet("CR18/Ground/SlideDust" .. k, "CR18/SlideDust", 1)
            local r = newSet("CR18/Ground/SlideRock" .. k, "CR18/SlideRock", 1)
            if d and r then
                ctx.call("SetParticleSystemPosition", d.name, ctx.vec(0, -500, 0))
                ctx.call("SetParticleSystemPosition", r.name, ctx.vec(0, -500, 0))
                sets[k] = { dust = d, rock = r }
            end
        end
        G.slideSets = next(sets) and sets or false
        return G.slideSets
    end

    -- The steepest of a few random candidates 50-160 m from the camera. A flat
    -- map still slides: the direction is then a hashed bearing.
    function G.Slide(power, serial, view)
        if not view or not G.anchor and not ensureSets(view) then return false end
        local sets = ensureSlideSets()
        if not sets then return false end
        local slot
        for k = 1, Ground.SLIDES do
            if sets[k] and not G.slides[k] then slot = k; break end
        end
        if not slot then return false end
        local best
        for k = 1, 10 do
            local a = ctx.hash(ctx.seed, serial, k, 11) * 6.2831853
            local d = 50 + 110 * ctx.hash(ctx.seed, serial, k, 12)
            local x, z = view.x + cos(a) * d, view.z + sin(a) * d
            local h, n = ctx.height(x, z)
            if h then
                local steep = n and (1 - n.y) or 0
                if not best or steep > best.steep then best = { x = x, z = z, h = h, n = n, steep = steep } end
            end
        end
        if not best then return false end
        local tx, ty, tz
        local n = best.n
        if n and n.y > 0.05 and (n.x * n.x + n.z * n.z) > 1e-4 then
            tx, tz = n.x, n.z
            ty = -(n.x * n.x + n.z * n.z) / n.y
        else
            local a = ctx.hash(ctx.seed, serial, 0, 13) * 6.2831853
            tx, tz, ty = cos(a), sin(a), -0.15
        end
        local len = sqrt(tx * tx + ty * ty + tz * tz)
        tx, ty, tz = tx / len, ty / len, tz / len
        power = math.max(0.2, math.min(1, tonumber(power) or 0.5))
        local rec = { x = best.x, z = best.z, tx = tx, ty = ty, tz = tz, born = ctx.clock(),
                      dur = 3.5 + 4 * power, power = power, speed = 7 + 5 * power, nextY = 0, y = best.h }
        G.slides[slot] = rec
        G.slidesStarted = G.slidesStarted + 1
        local set = sets[slot]
        for _, s in ipairs({ set.dust, set.rock }) do
            ctx.call("SetParticleEmitterDirection", s.name, 0, ctx.vec(tx, ty, -tz))
        end
        ctx.sound("gquak00.wav", ctx.vec(best.x, best.h, best.z))
        ctx.sound("r_exp3.wav", ctx.vec(best.x, best.h, best.z))
        return true
    end

    local function updateSlides(dt)
        local sets = G.slideSets
        if not sets then return end
        local now = ctx.clock()
        for k, rec in pairs(G.slides) do
            local set = sets[k]
            local age = now - rec.born
            if age >= rec.dur or not set then
                if set then
                    ctx.call("SetParticleEmitterEmissionRate", set.dust.name, 0, 0)
                    ctx.call("SetParticleEmitterEmissionRate", set.rock.name, 0, 0)
                    ctx.call("SetParticleSystemPosition", set.dust.name, ctx.vec(0, -500, 0))
                    ctx.call("SetParticleSystemPosition", set.rock.name, ctx.vec(0, -500, 0))
                end
                G.slides[k] = nil
            else
                local x, z = rec.x + rec.tx * rec.speed * age, rec.z + rec.tz * rec.speed * age
                if now >= rec.nextY then
                    rec.nextY = now + 0.15
                    rec.y = ctx.height(x, z) or rec.y
                end
                local fade = math.min(1, (rec.dur - age) / 1.2, age / 0.4 + 0.2)
                local pos = ctx.vec(x, rec.y + 1.5, z)
                ctx.call("SetParticleSystemPosition", set.dust.name, pos)
                ctx.call("SetParticleSystemPosition", set.rock.name, pos)
                ctx.call("SetParticleEmitterEmissionRate", set.dust.name, 0, 90 * rec.power * fade)
                ctx.call("SetParticleEmitterEmissionRate", set.rock.name, 0, 26 * rec.power * fade)
            end
        end
    end

    -- view {x,z,y?}: the local camera; level 0..1; crack 0..1 (phase density).
    function G.Update(dt, view, crack)
        if not view then return end
        updateScrub(view)
        if Damage then Damage.Update() end
        updateCracks(view, tonumber(crack) or 0)
        fissures.Update(view, crack)
        if G.sets then
            for _, set in pairs(G.sets) do settle(set) end
        end
        updateSlides(dt)
    end

    function G.Stop()
        fissures.Stop()
        if Damage then for i in ipairs(layers) do Damage.Unregister(tileName(i)) end end
        for i in pairs(G.tiles) do ctx.call("DestroyStaticGeometry", tileName(i)) end
        G.tiles = {}
        if G.sets then
            for _, set in pairs(G.sets) do
                ctx.call("DetachParticleSystem", set.name)
                ctx.call("DestroyParticleSystem", set.name)
            end
        end
        if G.slideSets then
            for _, set in pairs(G.slideSets) do
                for _, s in ipairs({ set.dust, set.rock }) do
                    ctx.call("DetachParticleSystem", s.name)
                    ctx.call("DestroyParticleSystem", s.name)
                end
            end
        end
        G.sets, G.slideSets, G.slides, G.laid, G.anchor = nil, nil, {}, {}, nil
    end

    function G.Describe()
        local n = 0
        for _ in pairs(G.tiles) do n = n + 1 end
        local active = 0
        for _ in pairs(G.slides) do active = active + 1 end
        return { flora=Damage and Damage.Describe() or nil, tiles = n, totalTiles = #layers, built = G.built, destroyed = G.destroyed, errors = G.errors,
                 lastError = G.lastError, cracks = G.cracksLaid, slides = G.slidesStarted, slidesActive = active,
                 material = G.material, particles = G.sets and true or false, fissures = fissures.Describe() }
    end
    return G
end

return Ground
