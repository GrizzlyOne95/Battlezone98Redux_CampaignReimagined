-- Local material presentation. Event callbacks copy a bounded queue; Update
-- owns renderer work. Shared rain uniforms, owned per-object clones for damage,
-- power, heat and two impact marks. No gameplay/AI/network writes.
local exu = require("exu")
local S = { Enabled = true, Wetness = 0, Clock = 0, MaxEvents = 64,
    MaxRecords = 4096, MaxActive = 64, MaxHeated = 8, PollBudget = 4, MaterialBudget = 16,
    records = {}, order = {}, cursor = 1, materials = {}, materialOrder = {}, materialCursor = 1,
    hits = {}, shots = {}, active = {}, activeSet = {}, activeCursor = 1,
    clones = {}, nextId = 0, timer = 0, bindCursor = 1, started = false, gen = 0,
    -- Cockpit glass damage (CRWetGlass) and electrical brownout.
    CrackStages = { { enter = 0.50, leave = 0.55, level = 0.35 }, { enter = 0.25, leave = 0.30, level = 0.80 } },
    BrownoutDrop = 0.05, BrownoutHold = 0.12, BrownoutCooldown = 0.4, MaxCrackSpots = 32,
    crackSpots = {}, crackSpotCount = 0, crackLevel = 0, glassOn = false,
    SweepWet = 0, MaxWetStep = 0.03, MaxMaterialBudget = 64, CloneWetBudget = 32,
    sweepLeft = 0, cloneLeft = 0, wetCursor = 1, sweepMoving = false,
    flashCache = {}, flashCacheCount = 0, MaxFlashCache = 512,
    -- Muzzle heat: each shot adds HeatPerShot. Heat cools in proportion to
    -- itself (HeatCool per second) plus a small HeatFloor, so steady fire
    -- settles at a warm level instead of draining: ~0.27 at 1 shot/s,
    -- ~0.47 at 1.5, full from about 3 shots/s. A lone shot fades away.
    HeatPerShot = 0.06, HeatMax = 1.0, HeatCool = 0.15, HeatFloor = 0.02, HeatRadius = 0.6,
    -- The glow wraps the barrel within BarrelRadius, from the flash point back
    -- toward the mount for at most BarrelLength, fading out along the way.
    BarrelRadius = 0.35, BarrelLength = 0.8,
    -- Snow on upward faces by world (CRWorldArt name): cover, linear albedo,
    -- blue tint, ice depth in metres (terrain parallax ice under the snow
    -- line, 0 = off) -- the surfaceSnow uniform. The world's terrain
    -- atlas material takes it too. Cockpit materials never do.
    SnowWorlds = { europa = { 0.4, 0.88, 0.35, 1.0 } }, snow = nil,
    -- Dust by world: linear r, g, b and amount -- the surfaceDust uniform.
    -- It settles on tops and, where a material has an ACT map, in occluded
    -- corners and creases; rain washes it off. On terrain it only fills the
    -- hollows of the map's baked shape mask (CRTerrainShape), which also
    -- drifts snow into hollows and off ridges.
    DustWorlds = { mars = { 0.45, 0.17, 0.07, 0.5 } }, dust = nil,
    -- Thruster wash on shaped snow/dust terrain: craft hovering within
    -- WashHeight (full, none) metres of the ground and WashRange of the camera
    -- blow a WashRadius circle clear (surfaceWash0..N: x, z, radius, strength).
    -- The player also leaves trail marks every WashTrailStep metres that fade
    -- over WashTrailFade seconds. WashScan records are checked per update.
    WashSlots = 6, WashRadius = 8, WashHeight = { 4, 12 }, WashRange = 250, WashScan = 32,
    WashTrailStep = 5, WashTrailFade = 4, washers = {}, washCursor = 1, washTrail = {}, washOut = {} }

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end
local function finite(x) return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge end
local function clamp(x, lo, hi) return math.max(lo, math.min(hi, finite(x) and x or lo)) end
local function valid(h) return h ~= nil and call(IsValid, h) == true end
local function vector(x, y, z) return SetVector(x, y, z) end
local function point(t)
    if t == nil then return nil end
    local x, y, z = t.posit_x or t.x, t.posit_y or t.y, t.posit_z or t.z
    if finite(x) and finite(y) and finite(z) then return { x = x, y = y, z = z } end
end
local function axis(m, name)
    if m == nil then return nil end
    local ok, x, y, z = pcall(function() return m[name .. "_x"], m[name .. "_y"], m[name .. "_z"] end)
    if ok and finite(x) and finite(y) and finite(z) then return { x = x, y = y, z = z } end
end
local function dot(a, b) return a.x*b.x + a.y*b.y + a.z*b.z end
local function cross(a, b) return { x = a.y*b.z - a.z*b.y, y = a.z*b.x - a.x*b.z, z = a.x*b.y - a.y*b.x } end
local function unit(a)
    local length = math.sqrt(dot(a, a))
    if finite(length) and length > 0.0001 then return { x = a.x/length, y = a.y/length, z = a.z/length } end
end
local function hullBasis(h)
    local m = call(GetTransform, h)
    local right, up, front = axis(m, "right"), axis(m, "up"), axis(m, "front")
    if right and up and front then return right, up, front end
end

-- The visible muzzle flash sits at the native mount plus a flash offset: the
-- craft's flashOffset<N> for that slot, else the weapon's own flashOffset. Heat
-- reads the same keys (never writes them) so the glow lands where the flash
-- does, not inside the barrel root. "right up forward" metres, each -20..20;
-- anything else is ignored, exactly like the native parser.
local function parseOffset(value)
    if type(value) ~= "string" then return nil end
    local numbers = {}
    for word in string.gmatch(string.gsub(value, '"', " "), "%S+") do
        local n = tonumber(word)
        if not finite(n) or math.abs(n) > 20 or #numbers >= 3 then return nil end
        numbers[#numbers + 1] = n
    end
    if #numbers == 3 then return { x = numbers[1], y = numbers[2], z = numbers[3] } end
end
local function cachedOffset(key, file, section, label)
    local value = S.flashCache[key]
    if value == nil then
        local odf = call(OpenODF, file)
        value = odf ~= nil and parseOffset((call(GetODFString, odf, section, label, ""))) or false
        if S.flashCacheCount < S.MaxFlashCache then
            S.flashCache[key] = value; S.flashCacheCount = S.flashCacheCount + 1
        end
    end
    return value or nil
end
local function flashOffset(h, slot)
    local craft = call(GetOdf, h)
    if type(craft) == "string" and craft ~= "" then
        local offset = cachedOffset("c:" .. string.lower(craft) .. ":" .. slot, craft, "CraftClass", "flashOffset" .. (slot + 1))
        if offset then return offset end
    end
    local weapon = call(GetWeaponClass, h, slot)
    if type(weapon) == "string" and weapon ~= "" then
        return cachedOffset("w:" .. string.lower(weapon), weapon, "WeaponClass", "flashOffset")
    end
end
-- The offset is in the weapon frame. The shot direction gives that frame for
-- turrets and pitched barrels too; it is stored in hull axes so the anchor
-- stays on the barrel while the craft moves. No shot direction: hull axes.
local function hullOffset(h, offset, shotFront)
    local right, up, front = hullBasis(h)
    if not right then return nil end
    local f = shotFront and unit(shotFront)
    local r = f and unit(cross(up, f))
    if not r then return { x = offset.x, y = offset.y, z = offset.z } end
    local u = cross(f, r)
    local d = { x = r.x*offset.x + u.x*offset.y + f.x*offset.z,
                y = r.y*offset.x + u.y*offset.y + f.y*offset.z,
                z = r.z*offset.x + u.z*offset.y + f.z*offset.z }
    return { x = dot(d, right), y = dot(d, up), z = dot(d, front) }
end

local function target(r) return r.cockpit and {kind = "cockpit", handle = r.handle} or r.handle end
local function own(name) return type(name) == "string" and string.sub(name, 1, 12) == "exu_surface_" end
local function ready()
    for _, name in ipairs({"GetSubEntityCount", "GetSubEntityMaterial", "SetSubEntityMaterial", "CloneSurfaceMaterial",
        "ReleaseSurfaceMaterial", "SetSurfaceMaterial", "SetMaterialShaderVector", "EntityLocalPoint"}) do
        if type(exu[name]) ~= "function" then return false end
    end
    return true
end

-- Reactive surfaces are an Enhanced feature. DX9 and DX11 Stock/Retro keep
-- their stock materials; the profile is re-read each tick so a live switch
-- releases or rebuilds the owned clones.
local function enhanced()
    local profile = call(exu.GetEffectiveRenderProfile)
    return type(profile) == "string" and string.lower(profile) == "enhanced"
end

local function wetMaterial(name, cockpit)
    if type(name) ~= "string" or name == "" or own(name) or S.materials[name] or #S.materialOrder >= 4096 then return end
    S.materials[name] = {cockpit = cockpit}; S.materialOrder[#S.materialOrder + 1] = name
end

-- Detected once per scene from the TRN's terrain atlas; false = no snow.
local function sceneSnow()
    if S.snow ~= nil then return S.snow end
    local file = call(GetMapTRNFilename)
    local trn = type(file) == "string" and file ~= "" and call(OpenODF, file) or nil
    local ok, art = pcall(require, "CRWorldArt")
    local world = trn and ok and type(art) == "table" and call(art.Detect, trn) or nil
    S.snow = S.SnowWorlds[world] or false
    S.dust = S.DustWorlds[world] or false
    if S.snow or S.dust then
        local atlas = call(GetODFString, trn, "Atlases", "MaterialName", "")
        if type(atlas) == "string" and atlas ~= "" then
            atlas = string.upper(atlas)
            wetMaterial(atlas)
            local state = S.materials[atlas]
            if state then
                state.terrain = true
                -- The shape table is keyed by map; its atlas must match.
                local okShape, shapes = pcall(require, "CRTerrainShape")
                local map = string.lower(string.match(file, "([^/\\]+)%.[Tt][Rr][Nn]$") or "")
                local shape = okShape and type(shapes) == "table" and shapes[map]
                if type(shape) == "table" and shape[1] == atlas then state.shape = shape end
            end
        end
    end
    return S.snow
end

local function writeSnow(name, snow)
    return call(exu.SetMaterialShaderVector, name, "surfaceSnow", snow[1], snow[2], snow[3], snow[4], -1, -1, "Autodetect")
end
local NoSnow = {0, 0, 0, 0}
local function sceneDust() sceneSnow(); return S.dust end
local NoShape = {"", 0, 0, 0, 0}
local function writeShape(name, shape)
    return call(exu.SetMaterialShaderVector, name, "surfaceTerrain", shape[2], shape[3], shape[4], shape[5], -1, -1, "Autodetect")
end
local function writeDust(name, dust)
    return call(exu.SetMaterialShaderVector, name, "surfaceDust", dust[1], dust[2], dust[3], dust[4], -1, -1, "Autodetect")
end
-- The terrain shader's world position is camera-relative, so the shaped
-- terrain material also takes the camera's world position every update.
local function cameraPosition()
    local m = call(exu.GetCameraTransformMatrix)
    if type(m) ~= "table" and type(m) ~= "userdata" then return nil end
    local ok, x, y, z = pcall(function()
        if m.posit_x ~= nil then return m.posit_x, m.posit_y, m.posit_z end
        local p = m.posit or m.position
        if p ~= nil then return p.x, p.y, p.z end
    end)
    if ok and finite(x) and finite(y) and finite(z) then return x, y, z end
end
local function followCamera()
    local name = S.shapeMaterial
    if not name then return end
    local x, y, z = cameraPosition()
    if not x then return end
    local at = S.cameraAt
    if at and math.abs(x-at[1]) + math.abs(y-at[2]) + math.abs(z-at[3]) < 0.02 then return end
    local changed = call(exu.SetMaterialShaderVector, name, "surfaceCamera", x, y, z, 0, -1, -1, "Autodetect")
    if finite(changed) and changed > 0 then S.cameraAt = {x, y, z} end
end

-- Wash strength for a craft: 1 hovering low, 0 at WashHeight[2] and above.
local function washOf(h)
    local v = call(GetPosition, h)
    local p = point(v)
    if not p then return nil end
    local ground = call(GetTerrainHeightAndNormal, v)
    if not finite(ground) then return nil end
    local lo, hi = S.WashHeight[1], S.WashHeight[2]
    local t = clamp((hi - (p.y - ground)) / (hi - lo), 0, 1)
    return p, t * t * (3 - 2 * t)
end
local function writeWash(slot, w)
    local last = S.washOut[slot]
    if last and math.abs(last[1]-w[1]) + math.abs(last[2]-w[2]) + math.abs(last[4]-w[4]) < 0.05 and last[3] == w[3] then return end
    local changed = call(exu.SetMaterialShaderVector, S.shapeMaterial, "surfaceWash" .. (slot-1), w[1], w[2], w[3], w[4], -1, -1, "Autodetect")
    if finite(changed) and changed > 0 then S.washOut[slot] = w end
end
local NoWash = {0, 0, 0, 0}
local function clearWash()
    if S.shapeMaterial then
        for slot = 1, S.WashSlots do
            if S.washOut[slot] and S.washOut[slot][4] > 0 then S.washOut[slot] = nil; writeWash(slot, NoWash) end
        end
    end
    S.washers, S.washCursor, S.washTrail, S.washOut = {}, 1, {}, {}
end
local function wash(dt)
    if not S.shapeMaterial or not S.cameraAt then return end
    -- Keep a list of the registered craft that can hover, a few per update.
    for _ = 1, math.min(S.WashScan, #S.order) do
        if S.washCursor > #S.order then S.washCursor = 1 end
        local h = S.order[S.washCursor]; S.washCursor = S.washCursor + 1
        if S.washers[h] == nil and valid(h) then
            local class = call(GetClassLabel, h)
            S.washers[h] = call(IsCraft, h) == true and class ~= "person" and class ~= "walker"
        end
    end
    local cx, cz, range = S.cameraAt[1], S.cameraAt[3], S.WashRange * S.WashRange
    local spots, player = {}, call(GetPlayerHandle)
    for h, craft in pairs(S.washers) do
        if not S.records[h] or not valid(h) then S.washers[h] = nil
        elseif craft then
            local p, s = washOf(h)
            local d = p and (p.x-cx)*(p.x-cx) + (p.z-cz)*(p.z-cz)
            if p and s > 0.02 and d < range then
                spots[#spots+1] = {p.x, p.z, S.WashRadius, s, d}
                local last = S.washTrail[#S.washTrail]
                if h == player and (not last or math.abs(last[1]-p.x) + math.abs(last[2]-p.z) > S.WashTrailStep) then
                    S.washTrail[#S.washTrail+1] = {p.x, p.z, S.WashRadius*0.8, s}
                    if #S.washTrail > S.WashSlots then table.remove(S.washTrail, 1) end
                end
            end
        end
    end
    table.sort(spots, function(a, b) return a[5] < b[5] end)
    -- The trail fills the slots the craft leave free, newest first.
    for i = #S.washTrail, 1, -1 do
        local m = S.washTrail[i]
        m[4] = m[4] - dt / S.WashTrailFade
        if m[4] <= 0 then table.remove(S.washTrail, i) else spots[#spots+1] = m end
    end
    for slot = 1, S.WashSlots do
        local w = spots[slot]
        if w then writeWash(slot, {w[1], w[2], w[3], clamp(w[4], 0, 1)})
        elseif S.washOut[slot] and S.washOut[slot][4] > 0 then writeWash(slot, NoWash) end
    end
end

local function write(slot, name, a, b, c, d)
    local old = slot.values[name]
    if old and math.abs(old[1]-a) < 0.001 and math.abs(old[2]-b) < 0.001 and
        math.abs(old[3]-c) < 0.001 and math.abs(old[4]-d) < 0.001 then return end
    local changed = call(exu.SetMaterialShaderVector, slot.assigned, name, a, b, c, d)
    if finite(changed) and changed > 0 then slot.values[name] = {a,b,c,d} end
end

local function release(r)
    for _, slot in ipairs(r.slots or {}) do
        -- Another owner (team colour, model replacement, etc.) wins. Never
        -- restore a stale source over its assignment.
        if valid(r.handle) and call(exu.GetSubEntityMaterial, target(r), slot.index) == slot.assigned then
            call(exu.SetSubEntityMaterial, target(r), slot.index, slot.source)
        end
        for _, name in ipairs({slot.normal, slot.off}) do
            if name then call(exu.ReleaseSurfaceMaterial, name); S.clones[name] = nil end
        end
    end
    r.slots, r.count, r.bindIndex = {}, nil, 0
end

local function activate(r)
    if S.activeSet[r] then return end
    if #S.active >= S.MaxActive then
        local oldest
        for i, old in ipairs(S.active) do
            if not next(old.heat) and (not oldest or (old.touched or 0) < (S.active[oldest].touched or 0)) then oldest = i end
        end
        if not oldest then return end
        local old = table.remove(S.active, oldest)
        release(old); old.marks = {}; old.needs = false; S.activeSet[old] = nil
    end
    S.activeSet[r] = true; S.active[#S.active + 1] = r
    r.needs = true
    r.touched = S.Clock
end

function S.Register(h)
    if not S.Enabled or not ready() or h == nil or S.records[h] then return end
    if #S.order >= S.MaxRecords then return end
    S.nextId = S.nextId + 1
    local r = {handle = h, id = S.nextId, slots = {}, bindIndex = 0, heat = {}, marks = {}, damage = 0}
    S.records[h] = r; S.order[#S.order + 1] = h
end

function S.Unregister(h)
    local r = S.records[h]
    if r then release(r); r.dead = true; S.activeSet[r] = nil end
    S.records[h] = nil
    if S.cockpit and S.cockpit.handle == h then release(S.cockpit); S.cockpit = nil end
end

local function discover(r)
    if S.Clock < (r.discoverAt or 0) then return end
    local count = call(exu.GetSubEntityCount, target(r))
    if not finite(count) or count < 1 or count > 64 then r.discoverAt = S.Clock + 1; return end
    local index = r.discover or 0
    if index >= count then index = 0 end
    for _ = 1, math.min(2, count-index) do
        wetMaterial(call(exu.GetSubEntityMaterial, target(r), index))
        index = index + 1
    end
    r.discover = index
    if index >= count then r.discoverAt = S.Clock + 2 end
    if r.tower == nil then r.tower = not r.cockpit and call(GetClassLabel, r.handle) == "turret" end
    if r.tower then activate(r) end
end

local function bindOne(r)
    if not r.needs or S.Clock < (r.retry or 0) then return end
    local count = call(exu.GetSubEntityCount, target(r))
    if not finite(count) or count < 1 or count > 64 then r.retry = S.Clock + 1; return end
    if r.count and r.count ~= count then release(r) end
    r.count = count
    local index = r.bindIndex or 0
    if index >= math.min(count, r.cockpit and 16 or 8) then
        if S.Clock < (r.recheckAt or 0) then return end
        r.recheckAt=S.Clock+2;index=0;r.bindIndex=0
    end
    r.unsupported=r.unsupported or {}
    if S.Clock<(r.unsupported[index] or 0) then r.bindIndex=index+1;return end
    local source = call(exu.GetSubEntityMaterial, target(r), index)
    if own(source) then r.bindIndex=index+1;return end
    if type(source) ~= "string" or source == "" then r.retry = S.Clock + 1; return end
    wetMaterial(source, r.cockpit)
    local name = "exu_surface_cr_" .. tostring(r.id) .. "_" .. tostring(index) .. (r.cockpit and "_cockpit" or "")
    if call(exu.CloneSurfaceMaterial, source, name) ~= true then r.retry = S.Clock + 1; return end
    S.clones[name] = true
    -- Only the owned clone's glow pass gets the Enhanced program; the shared
    -- CR_BZBase glow pass keeps CR_Textured_fragment for Stock/Retro.
    call(exu.SetSurfaceFragmentProgram, name, "glow", "CR_TexturedEnhanced_fragment")
    -- Do not replace unsupported stock/particle programs with inert clones.
    local supported = call(exu.SetMaterialShaderVector,name,"surfaceState",0,0,0,0)
    if not finite(supported) or supported < 1 then
        call(exu.ReleaseSurfaceMaterial,name); S.clones[name]=nil; r.bindIndex=index+1;r.unsupported[index]=S.Clock+2; return
    end
    local snow = not r.cockpit and sceneSnow()
    if snow then call(exu.SetMaterialShaderVector, name, "surfaceSnow", snow[1], snow[2], snow[3], snow[4]) end
    local dust = not r.cockpit and sceneDust()
    if dust then call(exu.SetMaterialShaderVector, name, "surfaceDust", dust[1], dust[2], dust[3], dust[4]) end
    if call(exu.SetSurfaceMaterial, target(r), index, name) ~= true then
        call(exu.ReleaseSurfaceMaterial, name); S.clones[name] = nil; r.retry = S.Clock + 1; return
    end
    local slot = {index = index, source = source, normal = name, assigned = name, values = {}}
    r.slots[#r.slots + 1] = slot; r.bindIndex = index + 1
end

local function radiusMark(position, radius)
    return {position.x, position.y, position.z, radius}
end

local function inRange(h)
    local player = call(GetPlayerHandle)
    if not valid(player) then return false end
    local distance = call(GetDistance, h, player)
    return finite(distance) and distance <= 260
end

local function enqueue(queue, h, transform, odf)
    if #queue >= S.MaxEvents then return end
    local p = point(transform)
    if h ~= nil and p then queue[#queue + 1] = {handle = h, position = p, odf = odf, front = axis(transform, "front")} end
end

function S.NotifyHit(odf, _, hit, transform) enqueue(S.hits, hit, transform, odf) end
function S.NotifyShot(odf, shooter, transform) enqueue(S.shots, shooter, transform, odf) end

local function drain(queue, shot)
    for _ = 1, math.min(2, #queue) do
        local event = table.remove(queue, 1)
        if valid(event.handle) and inRange(event.handle) then
            S.Register(event.handle)
            local r = S.records[event.handle]
            if r then
                if shot then
                    -- Match an actual native firing mount, not a guessed mesh
                    -- slot or a whole-hull tint. Deferred until factory commit.
                    local best, bestDistance
                    for slot = 0, 4 do
                        local muzzle = call(exu.GetWeaponMuzzlePosition, event.handle, slot)
                        if muzzle then
                            local dx, dy, dz = muzzle.x-event.position.x, muzzle.y-event.position.y, muzzle.z-event.position.z
                            local d = dx*dx + dy*dy + dz*dz
                            if not bestDistance or d < bestDistance then best, bestDistance = slot, d end
                        end
                    end
                    if best and bestDistance <= 16 then
                        local heated = 0
                        for _, active in ipairs(S.active) do if next(active.heat) then heated=heated+1 end end
                        local heat = r.heat[best] or {energy = 0, display = 0}
                        local mounts=0; for _ in pairs(r.heat) do mounts=mounts+1 end
                        local offset = flashOffset(event.handle, best)
                        offset = offset and hullOffset(event.handle, offset, event.front) or nil
                        if (next(r.heat) or heated<S.MaxHeated) and (r.heat[best] or mounts<2) then
                            heat.energy = math.min(S.HeatMax, heat.energy + S.HeatPerShot)
                            heat.offset = offset
                            r.heat[best] = heat; activate(r); r.touched=S.Clock
                        end
                        -- The player's own barrel heats in F1 too: the cockpit
                        -- record keeps its own heat so each decays once.
                        local c = S.cockpit
                        if c and c.handle == event.handle then
                            local ch = c.heat[best] or {energy = 0, display = 0}
                            local cm=0; for _ in pairs(c.heat) do cm=cm+1 end
                            if c.heat[best] or cm<2 then
                                ch.energy = math.min(S.HeatMax, ch.energy + S.HeatPerShot)
                                ch.offset = offset; c.heat[best] = ch
                            end
                        end
                    end
                else
                    local localPoint = call(exu.EntityLocalPoint, event.handle, vector(event.position.x,event.position.y,event.position.z))
                    if localPoint then
                        if #r.marks >= 2 then table.remove(r.marks, 1) end
                        r.marks[#r.marks + 1] = {anchor = radiusMark(localPoint, 0.65), untilTime = S.Clock + 16}
                        activate(r); r.touched=S.Clock; r.lowHealth=call(GetHealth,r.handle)
                    end
                end
            end
        end
    end
end

-- A real hull loss of at least BrownoutDrop in one tick dips the cockpit's
-- emission (surfaceState.w, the same channel that powers a tower off) for a
-- moment: it eases down in about a tenth of a second and back over about a
-- second. Repair, a new craft and the first sample never trigger it.
local function brownout(r, health, dt)
    local drop = finite(r.lastHull) and r.lastHull-health or 0
    if drop >= S.BrownoutDrop and S.Clock >= (r.brownReady or 0) then
        r.brownDepth = clamp(0.25+drop*2.5, 0.25, 0.6)
        r.brownUntil, r.brownReady = S.Clock+S.BrownoutHold, S.Clock+S.BrownoutCooldown
    end
    r.lastHull = health
    local want = S.Clock < (r.brownUntil or 0) and r.brownDepth or 0
    local now = r.brown or 0
    r.brown = want+(now-want)*math.exp(-dt*(want > now and 18 or 2.5))
    if r.brown < 0.002 then r.brown = 0 end
end

local function updateRecord(r, dt)
    if not valid(r.handle) then S.Unregister(r.handle); return false end
    local health = call(GetHealth, r.handle)
    if finite(health) then
        health = clamp(health,0,1)
        if finite(r.lowHealth) and health > r.lowHealth + 0.04 then r.marks = {}; r.lowHealth=health end
        r.lowHealth = math.min(r.lowHealth or health, health)
        r.health = health
        local desired = r.cockpit and (1-health) or 0
        r.damage = desired + (r.damage-desired)*math.exp(-dt*5)
        if r.cockpit then brownout(r, health, dt) end
    end
    if r.tower then
        local powered = call(exu.IsGunTowerPowered, r.handle)
        if type(powered) == "boolean" then r.powerOff = not powered end
    end
    local anchors, barrels, peak = {}, {}, 0
    r.peak = 0
    local right, up, front
    if next(r.heat) then right, up, front = hullBasis(r.handle) end
    for slot, heat in pairs(r.heat) do
        heat.energy = math.max(0, heat.energy*math.exp(-dt*S.HeatCool)-dt*S.HeatFloor)
        heat.display = heat.energy+(heat.display-heat.energy)*math.exp(-dt*6)
        if heat.display < 0.002 then r.heat[slot] = nil
        else
            local world = call(exu.GetWeaponMuzzlePosition, r.handle, slot)
            local mount = world
            local o = heat.offset
            if world and o and right then
                world = vector(world.x + right.x*o.x + up.x*o.y + front.x*o.z,
                               world.y + right.y*o.x + up.y*o.y + front.y*o.z,
                               world.z + right.z*o.x + up.z*o.y + front.z*o.z)
            end
            -- target(r) is the cockpit model for the F1 record, so the anchor
            -- lands in that model's own space.
            local localPoint = world and call(exu.EntityLocalPoint,target(r),world)
            if localPoint and #anchors < 2 then
                anchors[#anchors+1] = radiusMark(localPoint,S.HeatRadius); peak = math.max(peak,heat.display)
                -- A barrel needs a real mount-to-flash length; else the round tip mask.
                local base = mount ~= world and call(exu.EntityLocalPoint,target(r),mount)
                local dx,dy,dz = base and base.x-localPoint.x, base and base.y-localPoint.y, base and base.z-localPoint.z
                local length = base and math.sqrt(dx*dx+dy*dy+dz*dz) or 0
                if length > 0.05 then
                    local k = math.min(1, S.BarrelLength/length)
                    barrels[#anchors] = {localPoint.x+dx*k, localPoint.y+dy*k, localPoint.z+dz*k, S.BarrelRadius}
                end
            end
        end
    end
    r.peak = peak
    for i=#r.marks,1,-1 do if r.marks[i].untilTime <= S.Clock then table.remove(r.marks,i) end end
    local empty = {0,0,0,0}
    local hit0, hit1 = r.marks[1], r.marks[2]
    for _, slot in ipairs(r.slots) do
        local current = call(exu.GetSubEntityMaterial,target(r),slot.index)
        if current ~= slot.assigned then release(r); r.retry = S.Clock + 0.2; return true end
        local wanted = slot.normal
        if r.powerOff then
            if not slot.off then
                local off = slot.normal .. "_off"
                if call(exu.CloneSurfaceMaterial,slot.source,off) == true then
                    S.clones[off] = true; slot.off = off
                    call(exu.SetSurfaceTexture,off,"EmissiveMap","black.png")
                end
            end
            wanted = slot.off or slot.normal
        end
        if slot.assigned ~= wanted and call(exu.SetSurfaceMaterial,target(r),slot.index,wanted) == true then
            slot.assigned = wanted; slot.values = {}
        end
        write(slot,"surfaceState", r.cockpit and 0 or S.SweepWet, r.damage, peak, r.cockpit and (r.brown or 0) or (r.powerOff and 1 or 0))
        write(slot,"surfaceMode",0,r.cockpit and 1 or 0,r.cockpit and S.Clock or 0,0)
        local a,b = hit0 and hit0.anchor or empty,hit1 and hit1.anchor or empty
        write(slot,"surfaceImpact0",a[1],a[2],a[3],a[4]); write(slot,"surfaceImpact1",b[1],b[2],b[3],b[4])
        write(slot,"surfaceImpactWeights",hit0 and clamp((hit0.untilTime-S.Clock)/4,0,1) or 0,
            hit1 and clamp((hit1.untilTime-S.Clock)/4,0,1) or 0,0,0)
        a,b = anchors[1] or empty,anchors[2] or empty
        write(slot,"surfaceMuzzle0",a[1],a[2],a[3],a[4]); write(slot,"surfaceMuzzle1",b[1],b[2],b[3],b[4])
        a,b = barrels[1] or empty,barrels[2] or empty
        write(slot,"surfaceBarrel0",a[1],a[2],a[3],a[4]); write(slot,"surfaceBarrel1",b[1],b[2],b[3],b[4])
    end
    return true
end

-- Cockpit glass cracks by hull stage, after the ISDF Chronicles cockpit
-- damage preset: a faint star below 50% hull, a strong one below 25%, with
-- hysteresis so damage and repair do not chatter, at a fixed spot per craft.
-- CRWetGlass draws and fades it (on the fitted cockpit glass in F1, else the
-- screen overlay); it only needs Update calls while Busy(). Calls are
-- edge-triggered so a mission's own SetCrack (CRStorm18) is not fought.
local glassModule
local function glass()
    if glassModule == nil then
        local ok, m = pcall(require, "CRWetGlass")
        glassModule = (ok and type(m) == "table" and type(m.SetCrack) == "function" and
            type(m.Update) == "function" and type(m.Busy) == "function") and m or false
    end
    return glassModule or nil
end

local function crackSpot(h)
    local spot = S.crackSpots[h]
    if spot then return spot end
    if S.crackSpotCount >= S.MaxCrackSpots then S.crackSpots, S.crackSpotCount = {}, 0 end
    local text, hash = tostring(h), 0
    for i = 1, #text do hash = (hash*31+text:byte(i)) % 1000003 end
    local x = 0.30+0.40*((hash*0.6180339887) % 1)
    if math.abs(x-0.5) < 0.08 then x = x < 0.5 and 0.42 or 0.58 end -- keep the reticle clear
    spot = { x = x, y = 0.26+0.18*((hash*0.7548776662) % 1) }
    S.crackSpots[h], S.crackSpotCount = spot, S.crackSpotCount+1
    return spot
end

local function setCrack(level, spot)
    if level <= 0 and S.crackLevel <= 0 then return end
    if level == S.crackLevel and (level <= 0 or spot == S.crackAt) then return end
    local g = glass(); if not g then return end
    call(g.SetCrack, level, spot and spot.x, spot and spot.y)
    S.crackLevel, S.crackAt, S.glassOn = level, spot, true
end

-- Every frame, even while disabled or outside Enhanced, until a cleared crack
-- has faded: CRWetGlass only animates while someone calls Update.
local function driveGlass()
    if not S.glassOn then return end
    local g = glass()
    if not g then S.glassOn = false; return end
    call(g.Update, 0)
    if S.crackLevel <= 0 and call(g.Busy) ~= true then S.glassOn = false end
end

local function cockpitGlass(r)
    if not r or not finite(r.health) then setCrack(0); return end
    local hp, st, stage = r.health, S.CrackStages, r.stage
    if stage == nil then stage = hp < st[2].enter and 2 or hp < st[1].enter and 1 or 0
    elseif stage < 2 and hp < st[2].enter then stage = 2
    elseif stage < 1 and hp < st[1].enter then stage = 1
    elseif stage == 2 and hp > st[2].leave then stage = hp > st[1].leave and 0 or 1
    elseif stage == 1 and hp > st[1].leave then stage = 0 end
    r.stage = stage
    setCrack(stage > 0 and st[stage].level or 0, crackSpot(r.handle))
end

local function cockpit()
    local h = call(GetPlayerHandle)
    local visible = valid(h) and call(IsCraft,h) == true and call(exu.GetCameraView) == 1 and call(exu.GetSatState) ~= 1
    if S.cockpit and (not visible or S.cockpit.handle ~= h) then release(S.cockpit); S.cockpit = nil end
    if visible and not S.cockpit then
        S.nextId = S.nextId+1
        S.cockpit = {handle=h,id=S.nextId,cockpit=true,needs=true,slots={},bindIndex=0,marks={},heat={},damage=0}
    end
end

-- exu.BulletHit/BulletInit are single globals and other modules replace or
-- chain them. We wrap whatever is installed now, and Update re-wraps (chaining
-- the current function) if the global stops being our latest wrapper. `busy`
-- makes a wrapper nested inside another of ours pass through, so a callback
-- that replaced the global but still chains an older wrapper notifies once.
local function wrapCallback(field, notify, busy)
    local prev, gen = exu[field], S.gen
    local function wrapper(...)
        if S.gen ~= gen or S[busy] then return call(prev, ...) end
        S[busy] = true
        local a, b = call(prev, ...)
        S[busy] = false
        if S.started and S.Enabled then notify(...) end
        return a, b
    end
    S[field .. "Prev"], S[field .. "Wrapper"] = prev, wrapper
    exu[field] = wrapper
end

local function wrapCallbacks()
    if S.BulletHitWrapper == nil or exu.BulletHit ~= S.BulletHitWrapper then wrapCallback("BulletHit", S.NotifyHit, "hitBusy") end
    if S.BulletInitWrapper == nil or exu.BulletInit ~= S.BulletInitWrapper then wrapCallback("BulletInit", S.NotifyShot, "shotBusy") end
end

function S.Start()
    if S.started or not ready() then return end
    S.started = true
    wrapCallbacks()
    call(exu.SetReactiveChunksEnabled,true)
end

function S.Update(dt)
    driveGlass()
    if not S.Enabled or not ready() then return end
    if not enhanced() then
        if S.started then S.Suspend() end
        return
    end
    S.Start()
    wrapCallbacks()
    dt = clamp(dt,0,0.25); if dt <= 0 then return end
    S.Clock = S.Clock+dt
    followCamera(); wash(dt)
    local weather = package.loaded.CRWeather
    local rain = weather and call(weather.GetSurfaceWetness) or 0
    rain = clamp(rain,0,1)
    local tau = rain > S.Wetness and 2.5 or 10
    S.Wetness = rain+(S.Wetness-rain)*math.exp(-dt/tau)
    S.timer = S.timer+dt
    if S.timer < 0.05 then return end
    local step = S.timer; S.timer = 0
    drain(S.hits,false); drain(S.shots,true)
    cockpit()
    for _=1,math.min(S.PollBudget,#S.order) do
        if S.cursor > #S.order then S.cursor=1 end
        local h=S.order[S.cursor];local r=S.records[h]
        if r and valid(h) then discover(r);S.cursor=S.cursor+1
        else S.Unregister(h);table.remove(S.order,S.cursor) end
    end
    -- Rain sweep. Every shared material and owned clone gets the same swept
    -- value, which advances by at most MaxWetStep per completed sweep, so no
    -- material lags its neighbours or pops; the per-tick budget grows only
    -- while the value is moving.
    if S.sweepLeft <= 0 and S.cloneLeft <= 0 then
        local before = S.SweepWet
        S.SweepWet = S.SweepWet + clamp(S.Wetness-S.SweepWet, -S.MaxWetStep, S.MaxWetStep)
        S.sweepMoving = math.abs(S.SweepWet-before) > 0.0005
        S.sweepLeft, S.cloneLeft = #S.materialOrder, #S.active
    end
    local moving = S.sweepMoving or math.abs(S.Wetness-S.SweepWet) > 0.001
    local snow, dust = sceneSnow(), sceneDust()
    for _=1,math.min(moving and S.MaxMaterialBudget or S.MaterialBudget,#S.materialOrder) do
        if S.materialCursor > #S.materialOrder then S.materialCursor=1 end
        local name=S.materialOrder[S.materialCursor];local state=S.materials[name]
        if S.Clock >= (state.retry or 0) and (not state.wet or math.abs(state.wet-S.SweepWet)>0.001) then
            local changed=call(exu.SetMaterialShaderVector,name,"surfaceState",S.SweepWet,0,0,0,-1,-1,"Autodetect")
            if finite(changed) and changed > 0 then state.wet=S.SweepWet
            else state.retry=S.Clock+2 end
        end
        -- Snow is fixed for the scene: one write per material, own retry,
        -- since terrain takes surfaceSnow but has no surfaceState.
        if snow and not state.cockpit and not state.snow and S.Clock >= (state.snowRetry or 0) then
            local changed=writeSnow(name,snow)
            if finite(changed) and changed > 0 then state.snow=true else state.snowRetry=S.Clock+2 end
        end
        if dust and not state.cockpit and (state.shape or not state.terrain) and not state.dust and S.Clock >= (state.dustRetry or 0) then
            local changed=writeDust(name,dust)
            if finite(changed) and changed > 0 then state.dust=true else state.dustRetry=S.Clock+2 end
        end
        if state.shape and not state.shaped and S.Clock >= (state.shapeRetry or 0) then
            local changed=writeShape(name,state.shape)
            if finite(changed) and changed > 0 then
                state.shaped=true;S.shapeMaterial=name;S.cameraAt=nil;followCamera()
            else state.shapeRetry=S.Clock+2 end
        end
        S.materialCursor=S.materialCursor+1;S.sweepLeft=S.sweepLeft-1
    end
    -- Owned clones (towers, hit units) take the swept value here too, not
    -- only when their record's slower round-robin update comes around.
    local cloneWrites = 0
    for _=1,#S.active do
        if S.cloneLeft <= 0 or cloneWrites >= (moving and S.CloneWetBudget or 4) then break end
        if S.wetCursor > #S.active then S.wetCursor=1 end
        local r=S.active[S.wetCursor]
        if not r.dead and S.activeSet[r] then
            for _,slot in ipairs(r.slots) do
                write(slot,"surfaceState",S.SweepWet,r.damage or 0,r.peak or 0,r.powerOff and 1 or 0)
                cloneWrites=cloneWrites+1
            end
        end
        S.wetCursor=S.wetCursor+1;S.cloneLeft=S.cloneLeft-1
    end
    if #S.active == 0 then S.cloneLeft = 0 end
    -- Hot mounts update at 20 Hz (at most eight craft); cold records get
    -- four bounded slices per tick. Only ONE world clone is created per tick.
    if #S.active>0 then
        if S.bindCursor>#S.active then S.bindCursor=1 end
        local r=S.active[S.bindCursor]
        if not r.dead and S.activeSet[r] then bindOne(r) end
        S.bindCursor=S.bindCursor+1
    end
    for _,r in ipairs(S.active) do
        if not r.dead and S.activeSet[r] and next(r.heat) then
            updateRecord(r,S.Clock-(r.lastUpdate or S.Clock-step));r.lastUpdate=S.Clock
        end
    end
    for _=1,math.min(4,#S.active) do
        if S.activeCursor>#S.active then S.activeCursor=1 end
        local r=S.active[S.activeCursor]
        if r.dead or not S.activeSet[r] then table.remove(S.active,S.activeCursor)
        else
            if r.lastUpdate~=S.Clock then updateRecord(r,S.Clock-(r.lastUpdate or S.Clock-step));r.lastUpdate=S.Clock end
            if not r.tower and not next(r.heat) and #r.marks==0 then
                release(r);r.needs=false;S.activeSet[r]=nil
            end
            S.activeCursor=S.activeCursor+1
        end
    end
    if S.cockpit then bindOne(S.cockpit);updateRecord(S.cockpit,step) end
    cockpitGlass(S.cockpit)
end

function S.ResetScene()
    for _,r in pairs(S.records) do release(r) end
    if S.cockpit then release(S.cockpit) end
    for name,state in pairs(S.materials) do
        call(exu.SetMaterialShaderVector,name,"surfaceState",0,0,0,0,-1,-1,"Autodetect")
        if state.snow then writeSnow(name,NoSnow) end
        if state.dust then writeDust(name,NoSnow) end
        if state.shaped then writeShape(name,NoShape) end
    end
    S.records,S.order,S.materials,S.materialOrder,S.active,S.activeSet = {},{},{},{},{},{}
    S.hits,S.shots,S.clones = {},{},{}
    S.cockpit=nil;S.cursor=1;S.materialCursor=1;S.activeCursor=1;S.bindCursor=1;S.Wetness=0;S.timer=0
    setCrack(0);S.crackSpots,S.crackSpotCount={},0
    S.SweepWet=0;S.sweepLeft=0;S.cloneLeft=0;S.wetCursor=1;S.sweepMoving=false
    clearWash();S.snow=nil;S.dust=nil;S.shapeMaterial=nil;S.cameraAt=nil
end

-- Player setting. Off restores every owned material, releases clones, unhooks
-- the callbacks and stops all work (Register/Update are no-ops while off).
-- Returns true when the state changed.
function S.SetEnabled(enabled)
    enabled = enabled ~= false
    if S.Enabled == enabled then return false end
    S.Enabled = enabled
    if not enabled then S.Shutdown() end
    return true
end

-- Leaving Enhanced: restore every owned material and unhook, but keep the
-- registered craft so returning to Enhanced resumes without a rebuild.
function S.Suspend()
    for _,r in pairs(S.records) do release(r); r.needs=false; r.marks={}; r.heat={}; r.discover=nil; r.discoverAt=nil end
    if S.cockpit then release(S.cockpit) end
    for name,state in pairs(S.materials) do
        call(exu.SetMaterialShaderVector,name,"surfaceState",0,0,0,0,-1,-1,"Autodetect")
        if state.snow then writeSnow(name,NoSnow) end
        if state.dust then writeDust(name,NoSnow) end
        if state.shaped then writeShape(name,NoShape) end
    end
    S.materials,S.materialOrder,S.active,S.activeSet = {},{},{},{}
    S.hits,S.shots,S.clones = {},{},{}
    S.cockpit=nil;S.materialCursor=1;S.activeCursor=1;S.bindCursor=1;S.Wetness=0;S.timer=0
    clearWash();S.shapeMaterial=nil;S.cameraAt=nil
    setCrack(0)
    S.SweepWet=0;S.sweepLeft=0;S.cloneLeft=0;S.wetCursor=1;S.sweepMoving=false
    S.Unhook()
end

function S.Unhook()
    -- Restore only if nothing was layered over us; otherwise our stale wrapper
    -- stays in someone's chain and passes through (generation check).
    if exu.BulletHit==S.BulletHitWrapper then exu.BulletHit=S.BulletHitPrev end
    if exu.BulletInit==S.BulletInitWrapper then exu.BulletInit=S.BulletInitPrev end
    S.BulletHitWrapper,S.BulletInitWrapper,S.BulletHitPrev,S.BulletInitPrev=nil,nil,nil,nil
    S.gen=S.gen+1;S.hitBusy,S.shotBusy=false,false
    S.started=false
    call(exu.SetReactiveChunksEnabled,false)
end

function S.Shutdown()
    S.ResetScene()
    S.Unhook()
end

return S
