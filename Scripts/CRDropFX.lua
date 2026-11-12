-- Dropship engine effects: a jet and a hot glow on every real lift nozzle of each dropship hull, a ground wash under
-- it and one engine light, for every dropship scene (the CRDropIn openings and CRDrop18's extraction ending).
-- Peer-local presentation only: no objects, AI commands, damage or wire events. Each peer finds the hulls by ODF
-- and reads their pose every frame, so the jets follow whatever the leader moves, and the thrust comes from what
-- the hull is doing:
--   <ship>c (flying)  full thrust while airborne or moving; on the ground (a closing fallback) it spools up
--   <ship>o (landed)  spools down after touchdown
--   <ship>x (closing) spools up to idle while the ramps fold, full thrust once it climbs
-- A hull swap (c -> o -> x) builds a new object at the same spot; the new hull takes over the old one's
-- systems and throttle, so the jets never blink.
--
-- Callers: FX.Watch() when a drop starts (every peer), FX.Update() every frame, FX.Reset() on start/load/abort.
-- Without the EXU particle API (or the cr_dropship templates) the module logs once and does nothing.
local FX = {}

-- Nozzle exits in hull space: right, up, front metres; the hull origin is on the ground when landed. From the
-- build scripts in Tools/Dropships: Blender (x, y, z) -> (x, z, -y) here, because every ship's stern ramp (or
-- cvdrop's bow ramp, at Blender -y) puts the bow at Blender -y (CRDropIn.PROFILES: hinge/face). Every layout is
-- mirror-symmetric in x.
--   avdrop  build_dropship.py: three ventral lift bells per nacelle at y -6.5/0/6.5, top z 14.5, 5 m long, the
--           nacelle canted 7 deg about its pivot (+-32, 0, 36): exits at x +-28.8, z 9.7
--   svdrop  build_svdrop.py: hover-jet recesses in the fang bottoms (x +-18.5, y -41.5/-36.5, z 3.0) and the blade
--           pod bottoms (x +-25.5, y +-3.5, z 2.2)
--   cvdrop  build_cvdrop.py: the rocket bells in the feet of the four landing legs (x +-22.5 y -6, x +-30 y 24)
local function mirror(list)
    local out = {}
    for _, n in ipairs(list) do
        out[#out + 1] = { n[1], n[2], n[3] }
        out[#out + 1] = { -n[1], n[2], n[3] }
    end
    return out
end
FX.LAYOUTS = {
    avdrop = { nozzles = mirror({ { 28.8, 9.7, 6.5 }, { 28.8, 9.7, 0 }, { 28.8, 9.7, -6.5 } }), wash = 1.0 },
    svdrop = { nozzles = mirror({ { 18.5, 3.0, 41.5 }, { 18.5, 3.0, 36.5 }, { 25.5, 2.2, 3.5 }, { 25.5, 2.2, -3.5 } }),
        wash = 1.0 },
    cvdrop = { nozzles = mirror({ { 22.5, 0.4, 6 }, { 30, 0.4, -24 } }), wash = 1.2 },
}
FX.LAYOUTS.bvdrop = FX.LAYOUTS.avdrop   -- Black Dog bvdrop is avdrop's model retextured

FX.PAYLOAD = "cr_dropship"
FX.JET, FX.CORE, FX.WASH = "CR/Drop/Jet", "CR/Drop/Core", "CR/Drop/Wash"
FX.JET_RATE, FX.CORE_RATE, FX.WASH_RATE = 70, 36, 150   -- particles/s per nozzle (wash per hull) at full thrust
FX.WASH_HEIGHT = 45      -- the wash fades out as the nozzles climb this high over the ground
FX.AIRBORNE = 1.5        -- metres over the ground that count as flying
FX.MOVING = 0.3          -- m/s of vertical speed that count as flying
FX.IDLE = 0.55           -- throttle while the ramps fold, before the climb
FX.SPOOL_UP_T = 2.0      -- s for a closing hull to reach FX.IDLE
FX.RISE_T, FX.FALL_T = 0.35, 1.8   -- s for the throttle to go 0 -> 1 and 1 -> 0
FX.HANDOVER = 0.75       -- s a lost hull's systems wait for a successor
FX.HANDOVER_R = 25       -- metres (horizontal) a successor may be from the lost hull
FX.FADE_T = 1.5          -- s a finished hull's systems keep for their last particles
FX.SCAN_T = 0.5          -- s between object scans
FX.WATCH_T = 60          -- s a Watch keeps scanning with no hull in sight
FX.LIGHT = { r = 3.0, g = 2.1, b = 1.1, range = 110 }

local env = {}
local tracks, watchUntil, nextScan, serial, failed = {}, nil, 0, 0, nil
local refused = {}   -- hulls whose systems could not be built: not retried every scan

local function now() return env.time and env.time() or GetTime() end
local function exuApi() return env.exu or rawget(_G, "exu") end
local function log(line) if env.log then env.log(line) else print(line) end end
local function call(name, ...)
    local x = exuApi()
    local fn = x and x[name]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end
local function alive(h) return h ~= nil and IsValid(h) end
local function ground(x, y, z)
    local ok, h = pcall(GetTerrainHeightAndNormal, SetVector(x, y, z))
    return ok and type(h) == "number" and h or y
end

-- Overrides for tests: exu, templates() -> ok, reason; time(); log(line).
function FX.Configure(options) env = options or {} end

-- Layout and suffix of a dropship ODF ("avdropc" -> avdrop layout, "c"); nil for anything else.
function FX.Classify(odf)
    if type(odf) ~= "string" then return nil end
    local base, suffix = odf:lower():match("^(%a%adrop)([cox])")
    if not base or not FX.LAYOUTS[base] then return nil end
    return base, suffix
end

-- Pure throttle target from what the hull is doing. age: seconds since this hull (this ODF) appeared.
function FX.Target(suffix, height, vy, age)
    if suffix == "o" then return 0 end
    if height > FX.AIRBORNE or vy > FX.MOVING or (suffix == "c" and vy < -FX.MOVING) then return 1 end
    return FX.IDLE * math.min(1, math.max(0, age / FX.SPOOL_UP_T))
end

-- Pure throttle step toward the target.
function FX.Step(power, target, dt)
    if target > power then return math.min(target, power + dt / FX.RISE_T) end
    return math.max(target, power - dt / FX.FALL_T)
end

local function ready()
    if failed then return false end
    for _, name in ipairs({ "CreateParticleSystem", "DestroyParticleSystem", "SetParticleSystemPosition",
            "SetParticleEmitterEmissionRate" }) do
        if type((exuApi() or {})[name]) ~= "function" then failed = name .. " missing" end
    end
    if not failed then
        local load = env.templates or function() return require("CRParticleTemplates").EnsureExtra(FX.PAYLOAD) end
        local ok, loaded, reason = pcall(load)
        if not ok or not loaded then failed = tostring(reason or loaded or "templates") end
    end
    if failed then log("[CRDropFX] dropship engine effects unavailable: " .. failed); return false end
    return true
end

local function create(name, template, at)
    call("DestroyParticleSystem", name)   -- a system left by an earlier Lua state (a load) under the same name
    if call("CreateParticleSystem", name, template, at) ~= true then return false end
    call("SetParticleSystemKeepLocalSpace", name, false)
    call("SetParticleSystemNonVisibleUpdateTimeout", name, 0)
    call("SetParticleEmitterEmissionRate", name, 0, 0)
    return true
end

local function destroy(track)
    for _, name in ipairs(track.systems) do call("DestroyParticleSystem", name) end
    if track.light then call("DestroyPointLight", track.light) end
    track.systems, track.light = {}, nil
end

local function newTrack(h, base, suffix, p)
    serial = serial + 1
    local prefix = "CRDrop/" .. serial .. "/"
    local layout = FX.LAYOUTS[base]
    local t = { h = h, base = base, suffix = suffix, seen = now(), y = p.y, x = p.x, z = p.z, power = 0,
        systems = {}, jets = {}, cores = {} }
    local at = SetVector(p.x, p.y, p.z)
    for i = 1, #layout.nozzles do
        local jet, core = prefix .. "Jet" .. i, prefix .. "Core" .. i
        if not create(jet, FX.JET, at) or not create(core, FX.CORE, at) then
            t.systems[#t.systems + 1] = jet
            t.systems[#t.systems + 1] = core
            destroy(t)
            return nil
        end
        t.jets[i], t.cores[i] = jet, core
        t.systems[#t.systems + 1] = jet
        t.systems[#t.systems + 1] = core
    end
    t.wash = prefix .. "Wash"
    if create(t.wash, FX.WASH, at) then t.systems[#t.systems + 1] = t.wash else t.wash = nil end
    if type((exuApi() or {}).CreatePointLight) == "function" then
        local name = prefix .. "Light"
        if call("CreatePointLight", name, at, { r = FX.LIGHT.r, g = FX.LIGHT.g, b = FX.LIGHT.b }, FX.LIGHT.range) == true then
            t.light = name
            call("SetPointLightPowerScale", name, 0)
        end
    end
    return t
end

-- A hull that just appeared takes over a lost hull of the same ship (a c -> o -> x swap), else gets new systems.
local function adopt(h, base, suffix)
    if refused[h] then return end
    for _, t in ipairs(tracks) do if t.h == h then return end end
    local p = GetPosition(h)
    local clock = now()
    for _, t in ipairs(tracks) do
        if t.lostAt and not t.fadeAt and t.base == base and clock - t.lostAt <= FX.HANDOVER then
            local dx, dz = p.x - t.x, p.z - t.z
            if dx * dx + dz * dz <= FX.HANDOVER_R * FX.HANDOVER_R then
                t.h, t.suffix, t.seen, t.lostAt, t.y = h, suffix, clock, nil, p.y
                return
            end
        end
    end
    local t = newTrack(h, base, suffix, p)
    if not t then refused[h] = true; return end
    do
        -- First sight of a ship already flying (a guest that joined the scene late) runs at full thrust at once.
        if suffix ~= "o" and p.y - ground(p.x, p.y, p.z) > FX.AIRBORNE then t.power = 1 end
        tracks[#tracks + 1] = t
    end
end

local function scan()
    nextScan = now() + FX.SCAN_T
    if type(AllObjects) ~= "function" then return end
    for h in AllObjects() do
        local base, suffix = FX.Classify(GetOdf(h))
        if base then adopt(h, base, suffix) end
    end
end

local function rates(t, power, wash)
    for i = 1, #t.jets do
        call("SetParticleEmitterEmissionRate", t.jets[i], 0, FX.JET_RATE * power)
        call("SetParticleEmitterEmissionRate", t.cores[i], 0, FX.CORE_RATE * power)
    end
    if t.wash then call("SetParticleEmitterEmissionRate", t.wash, 0, FX.WASH_RATE * wash) end
    if t.light then call("SetPointLightPowerScale", t.light, power) end
end

local function place(t, dt, elapsed)
    local m = GetTransform(t.h)
    local px, py, pz = m.posit_x, m.posit_y, m.posit_z
    local vy = elapsed > 0 and (py - t.y) / elapsed or 0   -- real elapsed time: a long frame must not overstate speed
    local floor = ground(px, py, pz)
    local height = py - floor
    t.power = FX.Step(t.power, FX.Target(t.suffix, height, vy, now() - t.seen), dt)
    t.x, t.y, t.z = px, py, pz
    local layout = FX.LAYOUTS[t.base]
    local low = 1e9
    for i, n in ipairs(layout.nozzles) do
        local x, y, z = n[1], n[2], n[3]
        local wx = px + m.right_x * x + m.up_x * y + m.front_x * z
        local wy = py + m.right_y * x + m.up_y * y + m.front_y * z
        local wz = pz + m.right_z * x + m.up_z * y + m.front_z * z
        local at = SetVector(wx, wy, wz)
        call("SetParticleSystemPosition", t.jets[i], at)
        call("SetParticleSystemPosition", t.cores[i], at)
        if wy < low then low = wy end
    end
    local wash = t.power * layout.wash * math.max(0, 1 - (low - floor) / FX.WASH_HEIGHT)
    if t.wash then call("SetParticleSystemPosition", t.wash, SetVector(px, floor + 0.5, pz)) end
    if t.light then call("SetPointLightPosition", t.light, SetVector(px, math.max(floor + 2, low - 3), pz)) end
    rates(t, t.power, wash)
    t.washPower = wash
end

-- Every frame, every peer. Cheap when nothing is watched or tracked.
function FX.Update()
    if not watchUntil and #tracks == 0 then return end
    local clock = now()
    local elapsed = FX.lastAt and math.max(0, clock - FX.lastAt) or 0
    local dt = math.min(0.25, elapsed)   -- clamps only the throttle step
    FX.lastAt = clock
    local lost = false
    for _, t in ipairs(tracks) do
        if not t.lostAt and not alive(t.h) then t.lostAt, lost = clock, true end
    end
    if watchUntil and (lost or clock >= nextScan) then scan() end
    local keep = {}
    for _, t in ipairs(tracks) do
        if not t.lostAt then
            place(t, dt, elapsed)
            keep[#keep + 1] = t
        elseif not t.fadeAt then
            if clock - t.lostAt > FX.HANDOVER then t.fadeAt = clock; rates(t, 0, 0) end
            keep[#keep + 1] = t
        elseif clock - t.fadeAt < FX.FADE_T then
            keep[#keep + 1] = t
        else
            destroy(t)
        end
    end
    tracks = keep
    for _, t in ipairs(tracks) do if not t.lostAt then watchUntil = math.max(watchUntil or 0, clock + FX.SCAN_T * 4) end end
    if watchUntil and clock > watchUntil and #tracks == 0 then watchUntil = nil end
end

-- A drop is starting: scan for hulls until none has been seen for FX.WATCH_T seconds.
function FX.Watch()
    if not ready() then return false end
    watchUntil = math.max(watchUntil or 0, now() + FX.WATCH_T)
    nextScan = 0
    return true
end

-- True while any hull is tracked or fading (a guest keeps its drop running for the lift-off).
function FX.Busy() return #tracks > 0 end

function FX.Reset()
    for _, t in ipairs(tracks) do destroy(t) end
    tracks, watchUntil, nextScan, FX.lastAt, refused = {}, nil, 0, nil, {}
end

function FX.Describe()
    local rows = {}
    for _, t in ipairs(tracks) do
        rows[#rows + 1] = { base = t.base, suffix = t.suffix, power = t.power, wash = t.washPower or 0,
            jets = #t.jets, lost = t.lostAt ~= nil, fading = t.fadeAt ~= nil, light = t.light ~= nil }
    end
    return { watching = watchUntil ~= nil, failed = failed, tracks = rows }
end

return FX
