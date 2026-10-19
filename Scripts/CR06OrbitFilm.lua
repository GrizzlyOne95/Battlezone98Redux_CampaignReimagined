-- Escape from Mars: orbital insert under the restored Lincoln Mayday VO
-- (misn0625 "under attack", misn0626 "Mayday... Our engines are--").
-- Prototype: runs on the authority only (guests keep the ground view). The fleet is staged far above the launch pad
-- so the 5 km drop sits beyond the shortened far clip: the view shows only the
-- starfield dome, the ships and their effects. Every actor, particle system,
-- light and scene override is local and is removed when the shot ends.
local Film = {}

local ALTITUDE = 5000      -- metres above the pad
local FAR, NEAR = 3000, 2  -- terrain at -5 km is clipped; the dome sits at 0.45x far
local CLIMAX = 15.6        -- "Our engines are--": 0625 (2.4 s) + most of 0626 (15 s)
local HARD_END = 24        -- audio missing or stalled
local LINCOLN_SPEED, DESTROYER_SPEED = 12, 34
local BOLT_SPEED = 650

local function lerp(a, b, t) return a + (b - a) * t end
local function smooth(t) t = math.max(0, math.min(1, t)); return t * t * (3 - 2 * t) end

-- Ship frame helpers. A frame is {x,y,z, r={..}, u={..}, f={..}} in world space.
local function heading(fx, fz, bank)
    local l = math.sqrt(fx * fx + fz * fz)
    fx, fz = fx / l, fz / l
    -- Left-handed BZ basis: front = +Z and right = +X at identity.
    local rx, rz = fz, -fx
    local c, s = math.cos(bank or 0), math.sin(bank or 0)
    return { r = { rx * c, s, rz * c }, u = { -rx * s, c, -rz * s }, f = { fx, 0, fz } }
end

local function local_to_world(frame, lx, ly, lz)
    local r, u, f = frame.r, frame.u, frame.f
    return frame.x + r[1] * lx + u[1] * ly + f[1] * lz,
           frame.y + r[2] * lx + u[2] * ly + f[2] * lz,
           frame.z + r[3] * lx + u[3] * ly + f[3] * lz
end

local function place(api, h, frame)
    if not api.valid(h) then return end
    local m = api.transform(h)
    m.right_x, m.right_y, m.right_z = frame.r[1], frame.r[2], frame.r[3]
    m.up_x, m.up_y, m.up_z = frame.u[1], frame.u[2], frame.u[3]
    m.front_x, m.front_y, m.front_z = frame.f[1], frame.f[2], frame.f[3]
    m.posit_x, m.posit_y, m.posit_z = frame.x, frame.y, frame.z
    api.place(h, m)
end

local function call(api, name, ...)
    local fn = api.exu and api.exu[name]
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

-- Staging, relative to the shot origin O (pad x/z, ALTITUDE above it).
-- The Lincoln steams along +X. Its starboard side faces -Z, toward the CCA
-- destroyers; the camera sits on the port (+Z) side looking through it.
local function frames(shot, t)
    local o = shot.origin
    local L = heading(1, 0, 0)
    L.x, L.y, L.z = o.x + LINCOLN_SPEED * t, o.y, o.z
    local D1 = heading(-1, 0.12, math.rad(-8))
    D1.x, D1.y, D1.z = o.x + 520 - DESTROYER_SPEED * t, o.y + 70, o.z - 620
    local D2 = heading(0.96, 0.18, math.rad(6))
    D2.x, D2.y, D2.z = o.x - 380 + (DESTROYER_SPEED - 6) * t, o.y - 110, o.z - 860
    local T = heading(0, 1, 0)
    T.x, T.y, T.z = o.x + 260, o.y - 520 + 0.5 * 9 * t * t + 30 * t, o.z - 1350
    -- The CCA transport stands on its tail; its own frame keeps the mesh upright.
    T.r, T.u, T.f = { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }
    return L, D1, D2, T
end

-- Lincoln starboard hull sample in its local frame (x right, y up, z forward).
-- Deterministic LCG kept in the shot table (no closures in saved state).
function Film.rng(shot)
    shot.seed = (shot.seed * 1103515245 + 12345) % 2147483648
    return shot.seed / 2147483648
end

local function hull_point(shot, aft)
    local z = aft and lerp(-185, -140, Film.rng(shot)) or lerp(-170, 170, Film.rng(shot))
    return 56, lerp(-26, 36, Film.rng(shot)), z
end

local function stage_scene(shot, api)
    local exu = api.exu
    shot.saved = {
        fog = call(api, "GetFog"), ambient = call(api, "GetAmbientLight"),
        sun = call(api, "GetSunDirection"),
        dome = call(api, "GetSkyDomeEnabled"), plane = call(api, "GetSkyPlaneEnabled"),
        box = call(api, "GetSkyBoxEnabled"),
    }
    local near, far
    if type(exu.GetCameraClipDistances) == "function" then
        local ok, n, f = pcall(exu.GetCameraClipDistances)
        if ok then near, far = n, f end
    end
    shot.saved.near, shot.saved.far = near, far
    shot.hidden = {}
    for _, name in ipairs(api.weatherSystems and api.weatherSystems() or {}) do
        if call(api, "SetParticleSystemVisible", name, false) ~= nil then shot.hidden[#shot.hidden + 1] = name end
    end
    call(api, "SetSkyPlaneEnabled", false)
    call(api, "SetSkyBoxEnabled", false)
    if call(api, "SetSkyDome", "CR06/Starfield", 2, 3, FAR * 0.45, true) ~= true then
        api.log("[misn06] orbital starfield dome unavailable")
    end
    shot.domeOwned = true
    -- The stock sky ceiling, cloud layers and sun are drawn by the engine with
    -- materials named after their textures; retexture them for the shot.
    shot.retextured = {}
    for _, swap in ipairs(api.skyTextures or {}) do
        if call(api, "MaterialExists", swap[1]) == true
            and pcall(exu.SetMaterialTexture, swap[1], swap[2]) then
            shot.retextured[#shot.retextured + 1] = swap[1]
        end
    end
    api.log("[misn06] orbit sky retextured " .. #shot.retextured .. " material(s)")
end

local function apply_scene(shot, api)
    -- Re-asserted every frame: a paused atmosphere must not win a stale write.
    call(api, "SetCameraClipDistances", NEAR, FAR)
    call(api, "SetFog", 0, 0, 0, 20000, 30000)
    call(api, "SetAmbientLight", 0.10, 0.11, 0.14)
    call(api, "SetSunDirection", -0.35, -0.45, -0.82)
end

local function restore_scene(shot, api)
    local s = shot.saved
    if not s then return end
    if s.near and s.far then call(api, "SetCameraClipDistances", s.near, s.far) end
    if s.fog then call(api, "SetFog", s.fog) end
    if s.ambient then call(api, "SetAmbientLight", s.ambient) end
    if s.sun then call(api, "SetSunDirection", s.sun) end
    if shot.domeOwned then call(api, "SetSkyDomeEnabled", s.dome == true) end
    if s.plane then call(api, "SetSkyPlaneEnabled", true) end
    if s.box then call(api, "SetSkyBoxEnabled", true) end
    for _, name in ipairs(shot.hidden or {}) do call(api, "SetParticleSystemVisible", name, true) end
    for _, material in ipairs(shot.retextured or {}) do call(api, "SetMaterialTexture", material, material) end
    shot.retextured = nil
    shot.saved = nil
end

local function fx_name(shot, tag)
    shot.serial = shot.serial + 1
    return "CR06/Orbit/" .. tag .. "/" .. shot.serial
end

local function new_system(shot, api, tag, template, x, y, z, ttl)
    local name = fx_name(shot, tag)
    if call(api, "CreateParticleSystem", name, template, api.vector(x, y, z)) ~= true then return nil end
    call(api, "SetParticleSystemKeepLocalSpace", name, false)
    call(api, "SetParticleSystemNonVisibleUpdateTimeout", name, 0)
    shot.systems[name] = ttl and (api.time() + ttl) or true
    return name
end

local function blast(shot, api, x, y, z, big)
    new_system(shot, api, "Blast", big and "CR/M06O/BigBlast" or "CR/M06O/Blast", x, y, z, 4)
    -- Stock explosions draw large flat flash sprites; only the big hits get one.
    if big and api.explode then pcall(api.explode, "xbldxpl", api.vector(x, y, z)) end
end

local function add_burn(shot, api, lx, ly, lz)
    local L = shot.frames.L
    local x, y, z = local_to_world(L, lx, ly, lz)
    local burn = new_system(shot, api, "Burn", "CR/M06O/Burn", x, y, z)
    local vent = new_system(shot, api, "Vent", "CR/M06O/Vent", x, y, z)
    shot.burns[#shot.burns + 1] = { lx, ly, lz, burn, vent }
end

local function build(api, odf, x, y, z)
    local h = api.build(odf, 0, api.vector(x, y, z))
    if api.valid(h) then call(api, "SetEntityRenderingDistance", h, FAR * 2) end
    return h
end

function Film.Begin(state, api, pad)
    if state.orbitFilmStarted then return end
    state.orbitFilmStarted = true
    -- Co-op: only the authority reaches this call; guests keep their normal view.
    if not api.exu or not api.valid(pad) then return end
    local loaded = api.templates and api.templates()
    if not loaded then api.log("[misn06] orbital insert skipped: particle templates unavailable"); return end
    local p = api.transform(pad)
    local shot = {
        started = api.time(), origin = { x = p.posit_x, y = p.posit_y + ALTITUDE, z = p.posit_z },
        systems = {}, burns = {}, guns = {}, impacts = {}, serial = 0, camera = false,
        seed = 626,   -- plain data only: the mission table is saved
    }
    local o = shot.origin
    shot.lincoln = build(api, "cr06lin", o.x, o.y, o.z)
    shot.d1 = build(api, "cr06dst", o.x + 520, o.y + 70, o.z - 620)
    shot.d2 = build(api, "cr06dst", o.x - 380, o.y - 110, o.z - 860)
    shot.transport = build(api, "cr06rok", o.x + 260, o.y - 520, o.z - 1350)
    if not api.valid(shot.lincoln) then
        api.log("[misn06] orbital insert skipped: cr06lin could not be built")
        Film.Stop(state, api)
        return
    end
    state.orbitFilm = shot
    stage_scene(shot, api)
    -- Each destroyer carries one bolt system with three starboard-facing guns.
    for _, which in ipairs({ "d1", "d2" }) do
        local name = new_system(shot, api, "Guns", "CR/M06O/Bolt", o.x, o.y, o.z)
        if name then shot.guns[#shot.guns + 1] = { ship = which, system = name, next = 0 } end
    end
    -- Transport exhaust reuses the launch film's eight-bell templates.
    if api.layout then
        for _, kind in ipairs({ "Core", "Plume" }) do
            local name = new_system(shot, api, "Rocket" .. kind, "CR/M06/" .. kind, o.x, o.y, o.z)
            if name then
                for i, nozzle in ipairs(api.layout.nozzles) do
                    call(api, "SetParticleEmitterPosition", name, i - 1, api.vector(nozzle[1], 0, nozzle[2]))
                    call(api, "SetParticleEmitterEmissionRate", name, i - 1, kind == "Core" and 40 or 30)
                end
                shot["rocket" .. kind] = name
            end
        end
    end
    if type(api.exu.CreatePointLight) == "function" then
        shot.light = "CR06/Orbit/Flash"
        if call(api, "CreatePointLight", shot.light, api.vector(o.x, o.y, o.z), { r = 3, g = 1.8, b = 0.9 }, 450) ~= true then
            shot.light = nil
        end
    end
end

local GUN_OFFSETS = { { -70, 18, 0 }, { 10, 24, 0 }, { 90, 14, 0 } }  -- destroyer-local forward offsets

local function update_guns(shot, api, t, now)
    if t < 1.2 or t > CLIMAX + 1.5 then
        for _, gun in ipairs(shot.guns) do
            for i = 0, 2 do call(api, "SetParticleEmitterEmissionRate", gun.system, i, 0) end
        end
        return
    end
    local L = shot.frames.L
    for _, gun in ipairs(shot.guns) do
        local D = shot.frames[gun.ship == "d1" and "D1" or "D2"]
        call(api, "SetParticleSystemPosition", gun.system, api.vector(D.x, D.y, D.z))
        if now >= gun.next then
            gun.next = now + 0.35
            for i, g in ipairs(GUN_OFFSETS) do
                -- Guns sit on the Lincoln-facing beam; aim at a fresh hull point.
                local side = (L.z > D.z) and 1 or -1
                local gx, gy, gz = local_to_world(D, 0, g[2], g[1])
                gz = gz + side * 22
                local hx, hy, hz = hull_point(shot, t > CLIMAX - 3 and Film.rng(shot) < 0.6)
                local tx, ty, tz = local_to_world(L, hx, hy, hz)
                local dx, dy, dz = tx - gx, ty - gy, tz - gz
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                local ttl = dist / BOLT_SPEED
                call(api, "SetParticleEmitterPosition", gun.system, i - 1, api.vector(gx - D.x, gy - D.y, gz - D.z))
                call(api, "SetParticleEmitterDirection", gun.system, i - 1, api.vector(dx / dist, dy / dist, dz / dist))
                call(api, "SetParticleEmitterTimeToLive", gun.system, i - 1, ttl * 0.97, ttl)
                call(api, "SetParticleEmitterEmissionRate", gun.system, i - 1, 7)
                if Film.rng(shot) < 0.45 then
                    shot.impacts[#shot.impacts + 1] = { at = now + ttl, hx, hy, hz }
                end
            end
        end
    end
end

function Film.Update(state, api)
    local shot = state.orbitFilm
    if not shot then return end
    local now = api.time()
    local t = now - shot.started
    if not api.valid(shot.lincoln) then Film.Stop(state, api); return end
    if not shot.climaxAt and t >= CLIMAX then shot.climaxAt = now end
    if not shot.endAt then
        if (api.audioDone and api.audioDone() and t > CLIMAX) or t >= HARD_END then
            shot.endAt = now + 1.6
        end
    elseif now >= shot.endAt then
        Film.Stop(state, api)
        return
    end

    local L, D1, D2, T = frames(shot, t)
    shot.frames = { L = L, D1 = D1, D2 = D2, T = T }
    place(api, shot.lincoln, L)
    place(api, shot.d1, D1)
    place(api, shot.d2, D2)
    place(api, shot.transport, T)
    apply_scene(shot, api)
    for _, kind in ipairs({ "Core", "Plume" }) do
        local name = shot["rocket" .. kind]
        if name then call(api, "SetParticleSystemPosition", name, api.vector(T.x, T.y + (api.layout.nozzleY or 0), T.z)) end
    end

    update_guns(shot, api, t, now)
    for i = #shot.impacts, 1, -1 do
        local hit = shot.impacts[i]
        if now >= hit.at then
            table.remove(shot.impacts, i)
            blast(shot, api, local_to_world(L, hit[1], hit[2], hit[3]))
        end
    end
    -- Fires break out along the starboard side, then the engine section goes.
    local burnTimes = { 4.5, 8.0, 11.0, 13.5 }
    local burnSpots = { { 56, 12, 60 }, { 56, -8, -40 }, { 52, 30, 120 }, { 50, 4, -150 } }
    for i, when in ipairs(burnTimes) do
        if t >= when and #shot.burns < i then add_burn(shot, api, burnSpots[i][1], burnSpots[i][2], burnSpots[i][3]) end
    end
    for _, b in ipairs(shot.burns) do
        local x, y, z = local_to_world(L, b[1], b[2], b[3])
        if b[4] then call(api, "SetParticleSystemPosition", b[4], api.vector(x, y, z)) end
        if b[5] then call(api, "SetParticleSystemPosition", b[5], api.vector(x, y, z)) end
    end
    if shot.climaxAt and now >= (shot.nextClimax or 0) then
        shot.nextClimax = now + 0.22
        local hx, hy, hz = hull_point(shot, true)
        hx = lerp(-50, 56, Film.rng(shot))
        blast(shot, api, local_to_world(L, hx, hy, hz))
        if not shot.bigBlast then
            shot.bigBlast = true
            local bx, by, bz = local_to_world(L, 0, 10, -175)
            blast(shot, api, bx, by, bz, true)
        end
    end
    if shot.light then
        local flash = shot.climaxAt and (2.5 + 1.5 * math.sin(t * 37)) or (0.35 + 0.3 * math.max(0, math.sin(t * 9)))
        call(api, "SetPointLightPosition", shot.light, api.vector(local_to_world(L, 90, 20, shot.climaxAt and -160 or 0)))
        call(api, "SetPointLightPowerScale", shot.light, flash)
    end
    for name, expires in pairs(shot.systems) do
        if expires ~= true and now >= expires then
            call(api, "DestroyParticleSystem", name)
            shot.systems[name] = nil
        end
    end

    if shot.skipped then return end
    if not shot.camera then api.ready(); shot.camera = true end
    -- One continuous move along the Lincoln's port side: from forward of the
    -- bridge, past the arch tower, to the stern where the engines fail.
    local k = smooth(t / CLIMAX)
    api.camera(shot.lincoln, math.floor(lerp(-62000, -34000, k)), math.floor(lerp(9000, 2500, k)),
               math.floor(lerp(30000, -26000, k)), shot.lincoln)
    if api.cancelled() then
        api.finish()
        shot.camera, shot.skipped = false, true
        Film.Stop(state, api)
    end
end

function Film.Stop(state, api)
    local shot = state.orbitFilm
    state.orbitFilm = nil
    if not shot then return end
    if shot.camera then api.finish(); shot.camera = false end
    for name in pairs(shot.systems or {}) do call(api, "DestroyParticleSystem", name) end
    if shot.light then call(api, "DestroyPointLight", shot.light) end
    restore_scene(shot, api)
    for _, key in ipairs({ "lincoln", "d1", "d2", "transport" }) do
        if api.valid(shot[key]) then api.remove(shot[key]) end
    end
    state.orbitFilmDone = true
end

function Film.Active(state) return state.orbitFilm ~= nil end

function Film.Load(state, api)
    -- The staged fleet is presentation only; a mid-shot save resumes without it.
    local shot = state.orbitFilm
    if shot then
        shot.camera = false
        shot.systems, shot.light, shot.saved = {}, nil, nil
        Film.Stop(state, api)
    end
end

return Film
