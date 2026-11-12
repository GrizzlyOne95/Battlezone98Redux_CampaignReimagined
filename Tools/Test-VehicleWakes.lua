-- Test-VehicleWakes.lua
--
-- Drives the real CRWake module against a stubbed exu and a stubbed BZ Lua
-- runtime. No game, no Ogre.
--
-- Usage, from the repository root:
--
--     lua5.1 Tools/Test-VehicleWakes.lua Scripts
--
-- Covers the load budget (range cutoff, global system cap, nearest-first,
-- scan rate, camera-facing cull), pooling and linger, the Achilles-style
-- water/grass resolver, Stop, the disabled / no-EXU no-ops, disable-after-error,
-- and that every template the profiles name exists in cr_wake.particle.payload
-- on a material that already exists.
--
-- Also covers the kickup physics: per-craft emitter aim / velocity / TTL setter
-- calls (stubbed exu, throttled, no-ops without the API), the ballistic TTL
-- clamp, pilots on foot (no idle emission, apex cap on every world, small
-- sprite), pool reuse by template + mode, the player's pilot ranking first,
-- Ganymede's surface, and the vacuum / air template contracts.
--
-- Prints VEHICLE WAKES OK on success; prints each failed expectation and exits
-- 1 otherwise.

-- The engine returns VECTOR_3D userdata (not tables); mocks must do the same.
local function UD(t)
    local u = newproxy(true)
    getmetatable(u).__index = function(_, k) return t[k] end
    return u
end

local scriptDir = ... or "Scripts"

local failures, assertions = {}, 0
local function check(condition, message)
    assertions = assertions + 1
    if not condition then failures[#failures + 1] = message end
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local GROUND = 100.0

-- One isolated world + module instance.
--   options.noExu        exu lacks the particle API
--   options.noPayload    CRParticleTemplates.EnsureExtra fails
--   options.camera       { x, z, fx, fz } -> exu.GetCameraTransformMatrix
local function NewWorld(options)
    options = options or {}
    local w = { now = 0.0, objects = {}, order = {}, systems = {}, created = 0, destroyed = 0,
                allCraftCalls = 0, extra = {}, aimCalls = 0, persons = {} }
    local env = setmetatable({}, { __index = _G })
    env._G = env

    local exu = {}
    if not options.noExu then
        exu.CreateParticleSystem = function(name, template, position)
            if w.systems[name] ~= nil then return false end
            w.systems[name] = { template = template, position = position, rates = {}, local_ = nil,
                                dirs = {}, vel = {}, ttl = {}, params = {} }
            w.created = w.created + 1
            return true
        end
        exu.DestroyParticleSystem = function(name)
            if w.systems[name] == nil then return false end
            w.systems[name] = nil
            w.destroyed = w.destroyed + 1
            return true
        end
        exu.SetParticleSystemKeepLocalSpace = function(name, v)
            if w.systems[name] then w.systems[name].local_ = v end
            return true
        end
        exu.SetParticleSystemNonVisibleUpdateTimeout = function() return true end
        exu.SetParticleSystemPosition = function(name, v)
            if w.systems[name] then w.systems[name].position = v end
            return true
        end
        exu.SetParticleEmitterEmissionRate = function(name, i, r)
            if w.systems[name] then w.systems[name].rates[i] = r end
            return true
        end
        if not options.noAim then
            exu.SetParticleSystemDefaultDimensions = function(name, ww, hh)
                if w.systems[name] then w.systems[name].dims = { ww, hh } end
                return true
            end
            exu.SetParticleEmitterDirection = function(name, i, d)
                w.aimCalls = w.aimCalls + 1
                if w.systems[name] then w.systems[name].dirs[i] = { x = d.x, y = d.y, z = d.z } end
                return true
            end
            exu.SetParticleEmitterVelocity = function(name, i, lo, hi)
                if w.systems[name] then w.systems[name].vel[i] = { lo, hi } end
                return true
            end
            exu.SetParticleEmitterTimeToLive = function(name, i, lo, hi)
                if w.systems[name] then w.systems[name].ttl[i] = { lo, hi } end
                return true
            end
            exu.SetParticleEmitterParameter = function(name, i, key, value)
                if w.systems[name] then w.systems[name].params[key] = value end
                return true
            end
            exu.SetParticleEmitterAngle = function(name, i, a)
                if w.systems[name] then w.systems[name].angle = a end
                return true
            end
        end
    end
    if options.camera then
        exu.GetCameraTransformMatrix = function()
            local c = options.camera
            return UD({ posit_x = c.x, posit_y = GROUND + 3.0, posit_z = c.z, front_x = c.fx, front_z = c.fz })
        end
    end

    env.GetTime = function() return w.now end
    env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
    env.print = function() end
    env.GetPlayerHandle = function() return "player" end
    env.IsValid = function(h) return h == "player" or w.objects[h] ~= nil end
    env.IsPerson = function(h) return w.persons[h] == true end
    env.GetPosition = function(h)
        local o = w.objects[h]
        if o then return UD({ x = o.x, y = o.y, z = o.z }) end
        return nil
    end
    env.GetVelocity = function(h)
        local o = w.objects[h]
        if o then return UD({ x = o.vx, y = 0.0, z = o.vz }) end
        return nil
    end
    env.GetTerrainHeightAndNormal = function() return GROUND, UD({ x = 0.0, y = 1.0, z = 0.0 }) end
    env.AllCraft = function()
        w.allCraftCalls = w.allCraftCalls + 1
        local i = 0
        return function()
            i = i + 1
            return w.order[i]
        end
    end

    local preload = {
        exu = exu,
        CRParticleTemplates = {
            EnsureExtra = function(name)
                w.extra[#w.extra + 1] = name
                if options.noPayload then return false, "stub" end
                return true
            end,
        },
    }
    env.require = function(name)
        if preload[name] ~= nil then return preload[name] end
        error("unexpected module " .. tostring(name))
    end
    local chunk = assert(loadfile(scriptDir .. "/CRWake.lua"))
    setfenv(chunk, env)
    w.Wake = chunk("CRWake")
    w.env = env

    w.objects.player = { x = 0.0, y = GROUND + 2.0, z = 0.0, vx = 0.0, vz = 0.0 }
    w.order[1] = "player"

    function w.Add(name, x, z, vx, vz, height)
        w.objects[name] = { x = x, y = GROUND + (height or 2.0), z = z, vx = vx or 0.0, vz = vz or 0.0 }
        w.order[#w.order + 1] = name
        return name
    end
    -- A pilot on foot. `height` is above the terrain (feet).
    function w.AddPerson(name, x, z, vx, vz, height)
        w.persons[name] = true
        return w.Add(name, x, z, vx, vz, height or 0.0)
    end
    function w.Remove(name)
        w.objects[name] = nil
        for i = #w.order, 1, -1 do if w.order[i] == name then table.remove(w.order, i) end end
    end
    function w.Run(seconds, step)
        step = step or 0.05
        local t = 0.0
        while t < seconds - 1e-9 do
            w.now = w.now + step
            w.Wake.Update(step)
            t = t + step
        end
    end
    function w.Live(template)
        local n = 0
        for _, s in pairs(w.systems) do
            if template == nil or s.template == template then n = n + 1 end
        end
        return n
    end
    -- Systems that currently emit, sorted by distance of their position from the player.
    function w.Emitting()
        local list = {}
        for _, s in pairs(w.systems) do
            local emits = false
            for _, r in pairs(s.rates) do if r > 0 then emits = true end end
            if emits then list[#list + 1] = s end
        end
        return list
    end
    return w
end

local function Surface(name) return function() return name, 1.0, 0.0 end end

-- =============================================================================
-- 1. Range cutoff
-- =============================================================================

do
    local w = NewWorld()
    w.Wake.Init({ surface = "mars" })
    w.Add("near", 60.0, 0.0, 20.0, 0.0)
    w.Add("far", 500.0, 0.0, 20.0, 0.0)
    w.Add("edge_out", 141.0, 0.0, 20.0, 0.0)
    w.Run(2.0)
    local near, far, edge = false, false, false
    for _, s in pairs(w.systems) do
        local x = s.position.x
        if math.abs(x - 60.0) < 1.0 then near = true end
        if math.abs(x - 500.0) < 1.0 then far = true end
        if math.abs(x - 141.0) < 1.0 then edge = true end
    end
    check(near, "a moving craft inside the range gets a wake")
    check(not far, "a craft at 500 m never gets a system")
    check(not edge, "a craft just outside the default 140 m range gets none")
    check(w.Live() == 1, "only the near craft holds a system (" .. w.Live() .. ")")
    check(near and next(w.systems) and w.systems[next(w.systems)].local_ == false, "its particles stay where thrown")

    -- Configurable range.
    local w2 = NewWorld()
    w2.Wake.Init({ surface = "mars", trackRange = 200.0 })
    w2.Add("c", 180.0, 0.0, 20.0, 0.0)
    w2.Run(2.0)
    check(w2.Live() == 1, "trackRange is configurable")

    -- Every craft far away: nothing is ever created, and no terrain work happens.
    local w3 = NewWorld()
    w3.Wake.Init({ surface = "mars" })
    for i = 1, 10 do w3.Add("f" .. i, 300.0 + i * 20.0, 0.0, 20.0, 0.0) end
    w3.Run(5.0)
    check(w3.created == 0, "ten distant craft create nothing")
end

-- =============================================================================
-- 2. Global cap and nearest-first
-- =============================================================================

do
    local w = NewWorld()
    w.Wake.Init({ surface = "mars" })
    for i = 1, 10 do w.Add("t" .. i, 10.0 + i * 8.0, 0.0, 22.0, 0.0) end
    w.Run(3.0)
    check(w.Live() == 4, "ten nearby craft hold exactly the default cap of 4 systems (" .. w.Live() .. ")")
    local xs = {}
    for _, s in pairs(w.systems) do xs[#xs + 1] = s.position.x end
    table.sort(xs)
    -- t1..t4 are the nearest (18, 26, 34, 42 m from the player at the origin).
    local nearest = true
    for i, x in ipairs(xs) do if math.abs(x - (10.0 + i * 8.0)) > 6.0 then nearest = false end end
    check(nearest, "the four nearest craft are the ones that get systems")
    check(w.created == 4, "systems are created once, not per scan (" .. w.created .. ")")

    -- A nearer craft arrives: it takes a slot from the farthest, nothing is added.
    w.Add("closer", 8.0, 0.0, 22.0, 0.0)
    w.Run(1.5)
    local hasCloser = false
    local maxX = 0.0
    for _, s in pairs(w.systems) do
        if math.abs(s.position.x - 8.0) < 6.0 then hasCloser = true end
    end
    check(hasCloser, "a nearer craft displaces the farthest")
    check(w.Live() <= 4, "and the cap still holds (" .. w.Live() .. ")")
    check(w.created <= 5, "displacement recycles a pooled system rather than churning (" .. w.created .. ")")

    -- Craft that move about for a long time never push creation past the cap by much.
    local before = w.created
    for step = 1, 40 do
        for i = 1, 10 do
            local o = w.objects["t" .. i]
            o.x = 10.0 + i * 8.0 + (step % 3) * 3.0
        end
        w.Run(0.25)
    end
    check(w.Live() <= 4, "cap holds through a long run")
    check(w.created - before <= 4, "no creation churn over a long run (" .. (w.created - before) .. ")")
end

do
    -- The cap is clamped to the hard maximum of 6.
    local w = NewWorld()
    w.Wake.Init({ surface = "mars", maxSystems = 50 })
    for i = 1, 12 do w.Add("t" .. i, 10.0 + i * 5.0, 0.0, 22.0, 0.0) end
    w.Run(3.0)
    check(w.Live() == 6, "maxSystems is clamped to 6 (" .. w.Live() .. ")")
    local w0 = NewWorld()
    w0.Wake.Init({ surface = "mars", maxSystems = 0 })
    w0.Add("a", 20.0, 0.0, 22.0, 0.0)
    w0.Run(2.0)
    check(w0.Live() == 1, "maxSystems is clamped to at least 1")
end

-- =============================================================================
-- 3. Scan rate
-- =============================================================================

do
    local w = NewWorld()
    w.Wake.Init({ surface = "mars", tuning = { interval = 0.01 } })
    w.Add("a", 20.0, 0.0, 22.0, 0.0)
    w.Run(10.0)
    check(w.allCraftCalls <= 41, "the craft list is walked at most 4 times a second (" .. w.allCraftCalls .. " in 10 s)")
    check(w.allCraftCalls >= 30, "... and still about 4 times a second")
end

-- =============================================================================
-- 4. Idle, linger, destroy; pooled reuse; gating
-- =============================================================================

do
    local w = NewWorld()
    w.Wake.Init({ surface = "mars" })
    w.Add("m", 30.0, 0.0, 20.0, 0.0)
    w.Add("hi", 40.0, 0.0, 30.0, 0.0, 60.0)        -- a flyer 60 above the ground
    w.Add("turret", 50.0, 0.0, 0.0, 0.0)           -- never moved
    w.Run(2.0)
    check(w.Live() == 1, "a low mover gets one; a high flyer and a parked turret get none (" .. w.Live() .. ")")
    local sys = w.systems[next(w.systems)]
    check(sys.rates[0] and sys.rates[0] > 5.0, "the mover's system emits")
    check(sys.rates[1] and sys.rates[1] > 0.0 and sys.rates[1] < sys.rates[0], "the secondary emitter takes a share")

    w.objects.m.vx = 0.0
    w.Run(1.0)
    check(w.Live() == 1, "a craft that has just stopped keeps its system while it lingers")
    w.Run(2.5)
    local quiet = true
    for _, r in pairs(sys.rates) do if r > 0 then quiet = false end end
    -- (the stopped craft is within the idle grace, so it still wakes a little)
    check(w.Live() == 1, "still inside the linger window")
    w.Run(12.0)
    check(w.Live() == 0, "after the linger the system is destroyed (" .. w.Live() .. ")")
    check(w.created == w.destroyed, "nothing leaked")

    -- A new craft reuses a lingering system instead of creating another.
    w.Add("m2", 30.0, 10.0, 20.0, 0.0)
    w.Run(2.0)
    local created = w.created
    w.Remove("m2")
    w.Add("m3", 35.0, 10.0, 20.0, 0.0)
    w.Run(1.0)
    check(w.created == created, "a lingering system is reused by the next craft (" .. (w.created - created) .. " new)")
end

-- =============================================================================
-- 5. Surface selection: water vs grass, accent ring only with a spare slot
-- =============================================================================

do
    local w = NewWorld()
    local calls = 0
    local function resolver(x, z)
        calls = calls + 1
        if x > 100.0 then return "water", 1.0, 1.1 end
        return "grass", 0.6, 0.0
    end
    w.Wake.Init({ surface = resolver, surfaces = { "water", "grass" } })
    check(w.extra[1] == "cr_wake" and #w.extra == 1, "the shared payload is requested once for both surfaces")
    w.Add("wet", 120.0, 0.0, 20.0, 0.0)
    w.Run(2.0)
    check(w.Live("CRWake/WaterSpray") == 1, "a craft the resolver calls water gets the spray")
    check(w.Live("CRWake/WaterRing") == 1, "and a flat wake ring while a slot is spare")
    check(w.Live("CRWake/GrassBits") == 0, "but no grass debris")
    for _, s in pairs(w.systems) do
        if s.template == "CRWake/WaterSpray" then
            check(math.abs(s.position.y - (GROUND + 1.1 + 0.2)) < 1e-6, "the water wake sits on the lifted surface")
        end
    end

    w.objects.wet.x = 101.0
    w.Add("dry", 99.0, 0.0, 20.0, 0.0)
    w.Run(2.0)
    check(w.Live("CRWake/GrassBits") == 1, "a craft on the other side of the resolver gets grass debris")
    local grass
    for _, s in pairs(w.systems) do if s.template == "CRWake/GrassBits" then grass = s end end
    local wetSpray
    for _, s in pairs(w.systems) do if s.template == "CRWake/WaterSpray" then wetSpray = s end end
    check(grass.rates[0] < wetSpray.rates[0], "the resolver's rate scale applies (grass 0.6x)")

    -- With the cap full of mains the ring is never created.
    local w2 = NewWorld()
    w2.Wake.Init({ surface = Surface("water"), surfaces = { "water" } })
    for i = 1, 6 do w2.Add("w" .. i, 20.0 + i * 5.0, 0.0, 20.0, 0.0) end
    w2.Run(3.0)
    check(w2.Live() == 4, "water craft still obey the cap (" .. w2.Live() .. ")")
    check(w2.Live("CRWake/WaterSpray") == 4 and w2.Live("CRWake/WaterRing") == 0, "spray first; rings only if slots are spare")

    -- A craft driving from water onto grass swaps its template and recycles.
    local w3 = NewWorld()
    w3.Wake.Init({ surface = resolver, surfaces = { "water", "grass" } })
    w3.Add("amph", 110.0, 0.0, 10.0, 0.0)
    w3.Run(0.5)
    w3.objects.amph.x = 90.0
    w3.Run(1.5)
    check(w3.Live("CRWake/GrassBits") == 1, "leaving the water swaps to the grass wake")
    check(w3.Live("CRWake/WaterSpray") <= 1 and w3.Live() <= 4, "the old surface's system is only lingering")
    w3.Run(8.0)
    check(w3.Live("CRWake/WaterSpray") == 0 and w3.Live("CRWake/WaterRing") == 0, "and is destroyed after the linger")

    -- A resolver that errors or returns nothing yields no wake and no crash.
    local w4 = NewWorld()
    w4.Wake.Init({ surface = function() error("boom") end, surfaces = { "grass" } })
    w4.Add("a", 30.0, 0.0, 20.0, 0.0)
    w4.Run(2.0)
    check(w4.Live() == 0 and w4.Wake.IsActive(), "a failing resolver draws nothing but does not disable the module")
end

-- =============================================================================
-- 6. Stop destroys everything; Reset; SetEnabled
-- =============================================================================

do
    local w = NewWorld()
    w.Wake.Init({ surface = Surface("water"), surfaces = { "water" } })
    for i = 1, 3 do w.Add("w" .. i, 20.0 + i * 5.0, 0.0, 20.0, 0.0) end
    w.Run(2.0)
    check(w.Live() >= 3, "systems are live before Stop")
    w.Wake.Stop()
    check(w.Live() == 0 and count(w.systems) == 0, "Stop destroys every system")
    check(w.created == w.destroyed, "every created system was destroyed")
    check(w.Wake.GetSystemCount() == 0, "and the module's count is zero")
    local created = w.created
    w.Run(2.0)
    check(w.created == created, "after Stop, Update is a no-op")
    w.Wake.Stop()

    -- Re-Init after Stop works (a new mission in the same state).
    w.Wake.Init({ surface = "mars" })
    w.Run(2.0)
    check(w.Live() >= 1, "Init after Stop starts again")
    w.Wake.SetEnabled(false)
    check(w.Live() == 0, "SetEnabled(false) destroys the systems")
    w.Run(2.0)
    check(w.Live() == 0, "and none are created while disabled")
    w.Wake.SetEnabled(true)
    w.Run(2.0)
    check(w.Live() >= 1, "SetEnabled(true) resumes")

    w.Wake.Reset()
    check(w.Live() == 0, "Reset (after a load) drops every system")
end

-- =============================================================================
-- 7. Disabled / unavailable is a no-op
-- =============================================================================

do
    local w = NewWorld({ noExu = true })
    local usable = w.Wake.Init({ surface = "mars" })
    w.Add("a", 30.0, 0.0, 20.0, 0.0)
    w.Run(3.0)
    check(usable == false and w.created == 0 and w.allCraftCalls == 0, "without the EXU particle API it does nothing at all")
    w.Wake.Stop()

    local off = NewWorld()
    off.Wake.Init({ surface = "mars", enabled = false })
    off.Add("a", 30.0, 0.0, 20.0, 0.0)
    off.Run(3.0)
    check(off.created == 0 and off.allCraftCalls == 0, "enabled=false never scans or creates")

    local q0 = NewWorld()
    q0.Wake.Init({ surface = "mars", quality = 0 })
    q0.Add("a", 30.0, 0.0, 20.0, 0.0)
    q0.Run(3.0)
    check(q0.created == 0, "quality 0 creates nothing")
    q0.Wake.SetQuality(1.0)
    q0.Run(2.0)
    check(q0.created == 1, "SetQuality restores it")

    local np = NewWorld({ noPayload = true })
    local ready = np.Wake.Init({ surface = "mars" })
    np.Add("a", 30.0, 0.0, 20.0, 0.0)
    np.Run(3.0)
    check(ready == false and np.created == 0, "a missing payload fails closed")

    -- Regolith needs no payload of its own (the Moon director loads cr_moon).
    local rg = NewWorld()
    rg.Wake.Init({ surface = "regolith" })
    check(#rg.extra == 0, "regolith requests no extra payload")
    rg.Add("a", 30.0, 0.0, 20.0, 0.0)
    rg.Run(2.0)
    check(rg.Live("CR/Moon/HoverDust") == 1, "regolith uses the Moon's existing template")
    local rs = rg.systems[next(rg.systems)]
    check(rs.rates[0] and rs.rates[1] and rs.rates[1] > 0 and rs.rates[1] < rs.rates[0], "regolith drives the chip emitter (1) below the dust emitter (0)")

    -- No player: nothing to measure from.
    local nop = NewWorld()
    nop.Wake.Init({ surface = "mars" })
    nop.env.GetPlayerHandle = function() return nil end
    nop.Add("a", 30.0, 0.0, 20.0, 0.0)
    nop.Run(2.0)
    check(nop.created == 0, "with no viewpoint nothing is tracked")
end

-- =============================================================================
-- 8. Disable after error
-- =============================================================================

do
    local w = NewWorld()
    w.Wake.Init({ surface = "mars" })
    w.Add("a", 30.0, 0.0, 20.0, 0.0)
    w.Run(1.0)
    check(w.Live() == 1, "a wake is live before the fault")
    w.Wake.Profiles.mars.shares = nil     -- the next new system's rate write raises
    w.Add("b", 40.0, 5.0, 20.0, 0.0)
    w.Run(1.0)
    check(not w.Wake.IsActive(), "an error disables the module")
    check(w.Live() == 0, "and destroys its systems")
    local created = w.created
    w.Run(2.0)
    check(w.created == created, "and it stays quiet")
end

-- =============================================================================
-- 9. Camera-facing cull
-- =============================================================================

do
    -- Camera at the origin looking down +z: a craft at z=+80 is in front, z=-80 behind.
    local w = NewWorld({ camera = { x = 0.0, z = 0.0, fx = 0.0, fz = 1.0 } })
    w.Wake.Init({ surface = "mars" })
    w.Add("front", 0.0, 80.0, 0.0, 20.0)
    w.Add("behind", 0.0, -80.0, 0.0, 20.0)
    w.Add("closeBehind", 0.0, -10.0, 0.0, 20.0)
    w.Run(2.0)
    local front, behind, close = false, false, false
    for _, s in pairs(w.systems) do
        if math.abs(s.position.z - 80.0) < 8.0 then front = true end
        if math.abs(s.position.z + 80.0) < 8.0 then behind = true end
        if math.abs(s.position.z + 10.0) < 8.0 then close = true end
    end
    check(front, "a craft in front of the camera is kept")
    check(not behind, "a craft behind the camera is skipped")
    check(close, "but a craft right beside the camera is kept")

    -- Same scene without a camera facing: distance only.
    local w2 = NewWorld()
    w2.Wake.Init({ surface = "mars" })
    w2.Add("front", 0.0, 80.0, 0.0, 20.0)
    w2.Add("behind", 0.0, -80.0, 0.0, 20.0)
    w2.Run(2.0)
    check(w2.Live() == 2, "without a camera the cull falls back to distance only")

    -- cullBehind = false keeps everyone in range.
    local w3 = NewWorld({ camera = { x = 0.0, z = 0.0, fx = 0.0, fz = 1.0 } })
    w3.Wake.Init({ surface = "mars", tuning = { cullBehind = false } })
    w3.Add("front", 0.0, 80.0, 0.0, 20.0)
    w3.Add("behind", 0.0, -80.0, 0.0, 20.0)
    w3.Run(2.0)
    check(w3.Live() == 2, "cullBehind=false disables the facing cull")

    -- The range is measured from the camera, not the player, when it reports one.
    local w4 = NewWorld({ camera = { x = 300.0, z = 0.0, fx = 1.0, fz = 0.0 } })
    w4.Wake.Init({ surface = "mars", tuning = { maxCameraOffset = 600 } })
    w4.Add("nearCam", 380.0, 0.0, 20.0, 0.0)
    w4.Add("nearPlayer", 40.0, 0.0, 20.0, 0.0)
    w4.Run(2.0)
    local camSide, playerSide = false, false
    for _, s in pairs(w4.systems) do
        if math.abs(s.position.x - 380.0) < 8.0 then camSide = true end
        if math.abs(s.position.x - 40.0) < 8.0 then playerSide = true end
    end
    check(camSide and not playerSide, "the viewpoint is the camera when EXU reports one")
end

-- =============================================================================
-- 10. Distance fade
-- =============================================================================

do
    local w = NewWorld()
    w.Wake.Init({ surface = "mars" })
    w.Add("nearc", 20.0, 0.0, 25.0, 0.0)
    w.Add("farc", 135.0, 0.0, 25.0, 0.0)
    w.Run(2.0)
    local nearRate, farRate
    for _, s in pairs(w.systems) do
        if math.abs(s.position.x - 20.0) < 8.0 then nearRate = s.rates[0] end
        if math.abs(s.position.x - 135.0) < 8.0 then farRate = s.rates[0] end
    end
    check(nearRate and farRate and farRate < nearRate * 0.5, "emission fades with distance")
end

-- =============================================================================
-- 10b. Achilles: the real generated stream/pool mask through the real resolver
-- =============================================================================

do
    local sites = dofile(scriptDir .. "/CRJungle17Sites.lua")
    local mask = sites.watermask
    check(type(mask) == "table" and mask.cell == 5 and #mask.rows > 100, "the generated sites carry a water mask")
    local w = NewWorld()
    local modules = {
        CRWeather = { Init = function() end, Update = function() end, Shutdown = function() end,
            SetPreset = function() end, SetWindOverride = function() end, ClearWindOverride = function() end,
            SetIntensity = function() end },
        CRWeatherPresets = { Presets = { AcidRainVisual = { precipitation = { { emitters = { [0] = {} } } } } } },
        CRJungle17Sites = sites,
        CRSplash = { Set = function() end, Update = function() end, Stop = function() end, SetWind = function() end },
        CRWetGlass = { Update = function() end, Stop = function() end },
        CRParticleTemplates = { EnsureExtra = function() return true end },
        Environment = { RegisterEnvironmentModifier = function() end },
        CRFoliageWind = { Register = function() end, EnableLitter = function() end, Describe = function() return {} end },
        CRWake = w.Wake,
    }
    local base = w.env.require
    w.env.require = function(name) return modules[name] or base(name) end
    local chunk = assert(loadfile(scriptDir .. "/CRJungle17.lua"))
    setfenv(chunk, w.env)
    local J = chunk().Create({ exu = {} })

    local function cellXZ(rowIndex, col)
        return col * mask.cell, (mask.firstRow + rowIndex - 1) * mask.cell + mask.originZ
    end
    local stream, pool, miss
    for i, row in ipairs(mask.rows) do
        for k = 1, #row - 1, 2 do
            local start, len = row[k], row[k + 1]
            local x, z = cellXZ(i, start + math.floor(len / 2))
            if len <= 3 and not stream and J.WakeSurface(x, z) == "water" then stream = { x = x, z = z } end
            if len >= 8 and not pool and J.WakeSurface(x, z) == "water" then pool = { x = x, z = z } end
            if not miss and start >= 2 then
                -- the cell left of a run is dry (runs are maximal); skip it if the river covers it
                local mx, mz = cellXZ(i, start - 1)
                if J.WakeSurface(mx, mz) == "grass" and not J.WakeInWaterMask(mx, mz) then miss = { x = mx, z = mz } end
            end
        end
        if stream and pool and miss then break end
    end
    check(stream ~= nil, "a narrow (stream) run in the mask resolves to water")
    check(pool ~= nil, "a wide (pool) run in the mask resolves to water")
    check(miss ~= nil, "the cell just outside a run resolves to grass")

    if stream and pool and miss then
        w.Wake.Init({ surface = J.WakeSurface, surfaces = { "water", "grass" } })
        w.objects.player.x, w.objects.player.z = pool.x, pool.z
        w.Add("poolcraft", pool.x + 5.0, pool.z, 20.0, 0.0)
        w.Add("streamcraft", stream.x, stream.z + 5.0, 20.0, 0.0)
        w.Run(2.0)
        check(w.Live("CRWake/WaterSpray") >= 1, "craft over mask water get the spray through the real module")
        -- Elsewhere on the map (player moved there), a craft on a dry cell beside the mask.
        w.Wake.Stop()
        w.Wake.Init({ surface = J.WakeSurface, surfaces = { "water", "grass" } })
        w.objects.player.x, w.objects.player.z = miss.x, miss.z
        w.Add("misscraft", miss.x, miss.z, 20.0, 0.0)
        w.Run(2.0)
        check(w.Live("CRWake/GrassBits") >= 1, "a craft on the dry cell beside the mask gets grass debris")
        w.Wake.Stop()
    end
end

-- =============================================================================
-- 11. Payload and profile consistency
-- =============================================================================

do
    local function readAll(path)
        local f = io.open(path, "rb")
        if not f then return nil end
        local t = f:read("*a")
        f:close()
        return t
    end
    local payload = readAll(scriptDir .. "/../Materials/cr_wake.particle.payload")
    check(payload ~= nil, "Materials/cr_wake.particle.payload exists")
    if payload then
        local materialsText = ""
        for _, f in ipairs({ "CR_reactive.material", "crwx_precip.material" }) do
            materialsText = materialsText .. (readAll(scriptDir .. "/../Materials/" .. f) or "")
        end
        local declared = {}
        for name, body in payload:gmatch("particle_system%s+([^%s{]+)%s*(%b{})") do
            declared[name] = body
            local material = body:match("material%s+([^%s]+)")
            check(material ~= nil and materialsText:find("material%s+" .. material:gsub("[%-%./]", "%%%0") .. "[%s:]") ~= nil,
                name .. " uses an existing material (" .. tostring(material) .. ")")
            local quota = tonumber(body:match("quota%s+(%d+)"))
            check(quota ~= nil and quota <= 100, name .. " has a small quota (" .. tostring(quota) .. ")")
            check(body:find("emission_rate%s+0") ~= nil, name .. " starts silent (the module drives the rate)")
            local _, emitters = body:gsub("emitter%s+%a+", "")
            check(emitters >= 1, name .. " has an emitter")
        end
        local w = NewWorld()
        for surface, profile in pairs(w.Wake.Profiles) do
            if profile.payload then
                check(declared[profile.template] ~= nil, surface .. " template " .. profile.template .. " is in the payload")
                if profile.accent then
                    check(declared[profile.accent] ~= nil, surface .. " accent " .. profile.accent .. " is in the payload")
                end
                local _, emitters = declared[profile.template]:gsub("emitter%s+%a+", "")
                check(emitters >= #profile.shares, surface .. " template has an emitter for every share")
            end
        end
        -- Regolith lives in the Moon's own payload: it needs dust (emitter 0) and chips (emitter 1),
        -- with the chips under a weaker gravity pull than Mars' (lunar arcs).
        local moon = readAll(scriptDir .. "/../Materials/cr_moon.particle.payload")
        check(moon ~= nil, "Materials/cr_moon.particle.payload exists")
        if moon then
            local body = moon:match("particle_system%s+CR/Moon/HoverDust%s*(%b{})")
            check(body ~= nil, "CR/Moon/HoverDust is in cr_moon")
            if body then
                local _, emitters = body:gsub("emitter%s+%a+", "")
                check(emitters >= #w.Wake.Profiles.regolith.shares, "regolith template has an emitter for every share (dust + chips)")
                local fy = tonumber(body:match("force_vector%s+%S+%s+(%S+)"))
                local mars = tonumber(declared["CRWake/MarsDust"]:match("force_vector%s+%S+%s+(%S+)"))
                check(fy and mars and fy > mars, "lunar gravity pull is weaker than Mars'")
            end
        end
        -- Mission 18's mud: dark wet dirt (emitter 0) and clods (emitter 1) on an existing material,
        -- heavier than the grass bits, with a complete interpolator (Ogre fills missing stages with black).
        local mud = declared["CRWake/MudClods"]
        check(mud ~= nil and w.Wake.Profiles.mud and w.Wake.Profiles.mud.template == "CRWake/MudClods", "mud profile and its template exist")
        if mud then
            local _, mudEmitters = mud:gsub("emitter%s+%a+", "")
            check(mudEmitters == 2 and #w.Wake.Profiles.mud.shares == 2, "mud has a dirt emitter and a clod emitter")
            check(mud:match("material%s+(%S+)") == "CR_FX/KickClod", "mud uses the clod sprite")
            for i = 0, 3 do check(mud:find("time" .. i, 1, true) and mud:find("colour" .. i, 1, true), "mud states interpolator stage " .. i) end
            local fy = tonumber(mud:match("force_vector%s+%S+%s+(%S+)"))
            local gy = tonumber(declared["CRWake/GrassBits"]:match("force_vector%s+%S+%s+(%S+)"))
            check(fy and gy and fy < gy, "clods fall harder than grass bits (drag-softened)")
            local r, g, bl = mud:match("colour_range_start%s+(%S+)%s+(%S+)%s+(%S+)")
            check(tonumber(r) <= 0.7 and tonumber(r) >= tonumber(bl), "mud tints the brown clod sprite warm and darker than grass")
            local mudQuota = tonumber(mud:match("quota%s+(%d+)"))
            check(mudQuota and mudQuota <= 72, "mud quota is within the load budget (" .. tostring(mudQuota) .. ")")
        end
        -- A craft the resolver calls mud gets the mud template, and only the shared payload is requested.
        local wm = NewWorld()
        wm.Wake.Init({ surface = function(x) if x > 100.0 then return "water", 1.0, 0.5 end return "mud", 0.7, 0.0 end,
                       surfaces = { "water", "mud" } })
        check(#wm.extra == 1 and wm.extra[1] == "cr_wake", "water + mud request the shared payload once")
        wm.Add("slog", 50.0, 0.0, 20.0, 0.0)
        wm.Run(2.0)
        check(wm.Live("CRWake/MudClods") == 1 and wm.Live("CRWake/WaterSpray") == 0, "a craft over mud gets the mud wake")
        for _, sy in pairs(wm.systems) do
            if sy.template == "CRWake/MudClods" then check((sy.rates[0] or 0) > 0, "the mud wake emits") end
        end
        wm.Wake.Stop()
        check(wm.Live() == 0, "mud wakes are destroyed on Stop")
        -- Balanced braces (Ogre skips a malformed template silently).
        local open, close = 0, 0
        for _ in payload:gmatch("{") do open = open + 1 end
        for _ in payload:gmatch("}") do close = close + 1 end
        check(open == close, "payload braces balance (" .. open .. "/" .. close .. ")")
    end
end

-- =============================================================================
-- 12. Aim, launch speed and ballistic TTL (stubbed exu)
-- =============================================================================

local function norm(d) return math.sqrt((d.x * d.x) + (d.y * d.y) + (d.z * d.z)) end
local function only(w) return w.systems[next(w.systems)] end

do
    -- Moon craft at 20 m/s along +x: the sheet and chips trail behind (-x), not straight up.
    local w = NewWorld()
    w.Wake.Init({ surface = "regolith" })
    w.Add("c", 30.0, 0.0, 20.0, 0.0)
    w.Run(1.0)
    local s = only(w)
    local d0, d1 = s.dirs[0], s.dirs[1]
    check(d0 ~= nil and d1 ~= nil, "both emitters are aimed")
    if d0 and d1 then
        check(math.abs(norm(d0) - 1.0) < 1e-6 and math.abs(norm(d1) - 1.0) < 1e-6, "directions are unit vectors")
        check(d0.x < 0 and math.abs(d0.z) < 1e-9 and d0.y > 0, "the sheet leaves up and BACK, opposite the velocity")
        check(math.abs(d0.y / -d0.x - 0.35) < 1e-6, "sheet = back + up * 0.35")
        check(math.abs(d1.y / -d1.x - (1.0 / 0.6)) < 1e-6, "chips = back * 0.6 + up")
        check(d1.y > d0.y, "the chips leave steeper than the sheet")
    end
    -- Launch speed: sheet clamp(2 + 0.35 v, 2, 12) = 9, chips clamp(2.5 + 0.25 v, 2.5, 9) = 7.5, +/- 30 %.
    local v0, v1 = s.vel[0], s.vel[1]
    check(v0 and math.abs(v0[1] - 6.3) < 1e-6 and math.abs(v0[2] - 11.7) < 1e-6, "sheet speed range is 9 +/- 30 %")
    check(v1 and math.abs(v1[1] - 5.25) < 1e-6 and math.abs(v1[2] - 9.75) < 1e-6, "chip speed range is 7.5 +/- 30 %")
    -- Vacuum TTL = 2 v sin(el) / g, set +/- 20 % around it.
    local sin0 = 0.35 / math.sqrt(1.0 + 0.35 * 0.35)
    local t0 = 2.0 * 9.0 * sin0 / 1.62
    check(s.ttl[0] and math.abs(s.ttl[0][1] - 0.8 * t0) < 1e-6 and math.abs(s.ttl[0][2] - 1.2 * t0) < 1e-6,
        "Moon TTL is the ballistic flight time (" .. tostring(s.ttl[0] and s.ttl[0][1]) .. ")")
    -- Throttled: steady flight makes no further setter calls; a turn does.
    local before = w.aimCalls
    w.Run(2.0)
    check(w.aimCalls == before, "steady speed and heading re-aim nothing")
    w.objects.c.vx, w.objects.c.vz = 0.0, 20.0
    w.Run(1.0)
    check(w.aimCalls > before, "a turn of 90 degrees re-aims")
    check(only(w).dirs[0].z < 0 and math.abs(only(w).dirs[0].x) < 1e-9, "the spray now trails behind along -z")
    w.objects.c.vx, w.objects.c.vz = 0.0, 5.0
    local steady = w.aimCalls
    w.Run(1.0)
    check(w.aimCalls > steady, "a big speed change re-aims")
    -- Slower than MinSpeed (idle share): the last heading is kept.
    w.objects.c.vx, w.objects.c.vz = 1.0, 0.0
    w.Run(1.0)
    check(only(w).dirs[0].z < 0, "below MinSpeed the previous heading is kept")
end

do
    -- Ballistic TTL clamp: very fast Moon craft hit the 4 s ceiling (x 1.2), never beyond.
    local w = NewWorld()
    w.Wake.Init({ surface = "regolith" })
    w.Add("c", 30.0, 0.0, 40.0, 0.0)
    w.Run(1.0)
    local s = only(w)
    check(s.ttl[1] and math.abs(s.ttl[1][1] - 3.2) < 1e-6 and math.abs(s.ttl[1][2] - 4.8) < 1e-6, "TTL is clamped at 4 s")
    -- Air profiles keep their template TTL: no TTL setter for a vehicle on Mars, but aim and speed are set.
    local m = NewWorld()
    m.Wake.Init({ surface = "mars" })
    m.Add("c", 30.0, 0.0, 20.0, 0.0)
    m.Run(1.0)
    local ms = only(m)
    check(next(ms.ttl) == nil, "an air profile keeps the template TTLs")
    check(ms.dirs[0] ~= nil and ms.vel[1] ~= nil, "but is still aimed")
    -- Water keeps its own emitters (aim = false) for a vehicle.
    local wt = NewWorld()
    wt.Wake.Init({ surface = "water" })
    wt.Add("c", 30.0, 0.0, 20.0, 0.0)
    wt.Run(1.0)
    check(next(only(wt).dirs) == nil, "a water wake is not re-aimed")
    -- Without the aim API everything still works (no-ops).
    local na = NewWorld({ noAim = true })
    na.Wake.Init({ surface = "regolith" })
    na.Add("c", 30.0, 0.0, 20.0, 0.0)
    na.Run(1.0)
    check(na.Live("CR/Moon/HoverDust") == 1 and #na.Emitting() == 1, "a missing aim API is a no-op, the wake still emits")
end

-- =============================================================================
-- 13. Pilots on foot (every world)
-- =============================================================================

do
    local WorldG = { regolith = 1.62, ganymede = 1.43, ice = 1.31, sulfur = 1.80, mars = 3.71, ash = 8.87,
                     water = 9.81, mud = 9.81, grass = 9.81 }
    local function expectedFall(profile) return profile.fall or profile.g end
    local names = {}
    for name in pairs(NewWorld().Wake.Profiles) do names[#names + 1] = name end
    table.sort(names)
    check(#names == 9, "nine surfaces: " .. table.concat(names, ","))
    for _, name in ipairs(names) do
        local w = NewWorld()
        local profile = w.Wake.Profiles[name]
        check(profile.g == WorldG[name], name .. " carries its real gravity (" .. tostring(profile.g) .. ")")
        check(type(profile.vacuum) == "boolean", name .. " says whether it is a vacuum")
        w.Wake.Init({ surface = name })
        -- Standing still: nothing, even right after having walked.
        w.AddPerson("pilot", 20.0, 0.0, 0.0, 0.0)
        w.Run(2.0)
        check(w.created == 0, name .. ": a standing pilot creates nothing (no idle emission)")
        -- Walking.
        w.objects.pilot.vx = 5.0
        w.Run(1.0)
        check(w.Live() == 1 and #w.Emitting() == 1, name .. ": a walking pilot emits")
        local s = only(w)
        check(s.dims ~= nil and s.dims[1] >= 0.25 and s.dims[1] <= 0.35, name .. ": a pilot's sprite is 0.25-0.35 m")
        check(s.params.width and s.params.width <= 0.6 and s.angle and s.angle <= 25, name .. ": a pilot's emitter is tight")
        local rateMax = 0
        for _, r in pairs(s.rates) do rateMax = math.max(rateMax, r) end
        check(rateMax > 0 and rateMax <= profile.rate * 0.12 + 1e-9, name .. ": pilot rate is 12 % of the profile (" .. rateMax .. ")")
        -- Apex of the fastest grain of each emitter never exceeds 0.6 m.
        local g = expectedFall(profile)
        for i = 0, 1 do
            local d, v = s.dirs[i], s.vel[i]
            check(d ~= nil and v ~= nil, name .. ": pilot emitter " .. i .. " is aimed")
            if d and v then
                local vy = v[2] * d.y
                check(vy * vy / (2.0 * g) <= 0.6 + 1e-9, string.format("%s: apex cap on emitter %d (%.3f m)", name, i, vy * vy / (2.0 * g)))
                check(d.x < 0, name .. ": pilot spray trails behind")
            end
            if s.ttl[i] then check(s.ttl[i][1] >= 0.6 * 0.8 - 1e-9 and s.ttl[i][2] <= 4.0 * 1.2 + 1e-9, name .. ": pilot TTL is clamped") end
        end
        check(s.ttl[0] ~= nil, name .. ": pilot TTL is ballistic on every world")
        -- Airborne (above FootMaxHeight) emits nothing.
        w.objects.pilot.y = GROUND + 2.0
        w.Run(1.0)
        check(#w.Emitting() == 0, name .. ": an airborne pilot emits nothing")
        -- Stopped: silent immediately.
        w.objects.pilot.y, w.objects.pilot.vx = GROUND, 0.0
        w.Run(1.0)
        check(#w.Emitting() == 0, name .. ": a stopped pilot goes silent")
        w.Wake.Stop()
    end
    -- A vehicle on the same world is not a pilot: it keeps the full-size template.
    local w = NewWorld()
    w.Wake.Init({ surface = "regolith" })
    w.Add("c", 30.0, 0.0, 20.0, 0.0)
    w.Run(1.0)
    check(only(w).dims == nil, "a vehicle keeps the template sprite size")
end

do
    -- Pool reuse needs the same template AND mode.
    local w = NewWorld()
    w.Wake.Init({ surface = "regolith" })
    w.Add("craft", 30.0, 0.0, 20.0, 0.0)
    w.Run(1.0)
    check(w.created == 1, "one vehicle system")
    w.objects.craft.x = 500.0      -- out of range: unselected but valid, so its system idles and lingers
    w.AddPerson("pilot", 25.0, 0.0, 5.0, 0.0)
    w.Run(1.0)
    check(w.created == 2, "a pilot never takes a vehicle's idle system (created " .. w.created .. ")")
    local feet, craft = 0, 0
    for _, sy in pairs(w.systems) do if sy.dims then feet = feet + 1 else craft = craft + 1 end end
    check(feet == 1 and craft == 1, "one foot system and one vehicle system are live")
    w.Add("craft2", 40.0, 5.0, 20.0, 0.0)
    w.Run(1.0)
    check(w.created == 2, "the next vehicle reuses the idle vehicle system (created " .. w.created .. ")")
    w.objects.pilot.x = 500.0
    w.Run(0.5)
    w.AddPerson("pilot2", 22.0, 3.0, 5.0, 0.0)
    w.Run(1.0)
    check(w.created == 2, "the next pilot reuses the idle foot system (created " .. w.created .. ")")
    local sys = nil
    for _, sy in pairs(w.systems) do if sy.dims then sys = sy end end
    check(sys ~= nil and sys.dims[1] == 0.3, "and it keeps the pilot size")
end

do
    -- Persons count toward the system cap.
    local w = NewWorld()
    w.Wake.Init({ surface = "mars", maxSystems = 3 })
    for i = 1, 3 do w.AddPerson("p" .. i, 10.0 + i, 0.0, 5.0, 0.0) end
    for i = 1, 3 do w.Add("c" .. i, 60.0 + i, 0.0, 20.0, 0.0) end
    w.Run(2.0)
    check(w.Live() <= 3, "pilots and vehicles share the system cap (" .. w.Live() .. ")")

    -- The local player's own pilot outranks nearer vehicles when the camera is elsewhere.
    local c = NewWorld({ camera = { x = 100.0, z = 0.0, fx = 1.0, fz = 0.0 } })
    c.Wake.Init({ surface = "regolith", maxSystems = 2, tuning = { cullBehind = false } })
    c.persons.player = true
    c.objects.player.y, c.objects.player.vx = GROUND, 5.0
    c.Add("n1", 98.0, 0.0, 20.0, 0.0)
    c.Add("n2", 102.0, 0.0, 20.0, 0.0)
    c.Add("n3", 104.0, 0.0, 20.0, 0.0)
    c.Run(2.0)
    local foot = false
    for _, sy in pairs(c.systems) do if sy.dims then foot = true end end
    check(foot and c.Live() == 2, "the player's pilot keeps a system ahead of nearer vehicles")
end

-- =============================================================================
-- 14. Ganymede and the vacuum / air template contracts
-- =============================================================================

do
    local w = NewWorld()
    w.Wake.Init({ surface = "ganymede" })
    check(#w.extra == 1 and w.extra[1] == "cr_wake", "ganymede loads the shared payload")
    w.Add("c", 30.0, 0.0, 12.0, 0.0)
    w.Run(1.0)
    check(w.Live("CRWake/GanymedeSpray") == 1 and w.Live("CRWake/IceSpray") == 0, "Ganymede uses its own template")
    local s = only(w)
    check(s.ttl[0] ~= nil, "Ganymede is a vacuum: ballistic TTL")
    local sin0 = 0.35 / math.sqrt(1.0 + 0.35 * 0.35)
    check(s.ttl[0] and math.abs(s.ttl[0][1] - 0.8 * (2.0 * 6.2 * sin0 / 1.43)) < 1e-6, "using g = 1.43")

    local function readAll(path)
        local f = io.open(path, "rb")
        if not f then return nil end
        local t = f:read("*a")
        f:close()
        return t
    end
    local runtime = readAll(scriptDir .. "/CRCCARuntime.lua") or ""
    check(runtime:find("wakeSurface = w.wakeSurface", 1, true) ~= nil and runtime:find("^CRGanymedeSites", 1, true) ~= nil,
        "CRCCARuntime passes wakeSurface (explicit, or from a CRGanymedeSites* module)")
    local europa = readAll(scriptDir .. "/CREuropaWeather.lua") or ""
    check(europa:find('surface = options.wakeSurface or "ice"', 1, true) ~= nil, "CREuropaWeather forwards options.wakeSurface")

    local wake = readAll(scriptDir .. "/../Materials/cr_wake.particle.payload") or ""
    local moon = readAll(scriptDir .. "/../Materials/cr_moon.particle.payload") or ""
    local reactive = readAll(scriptDir .. "/../Materials/CR_reactive.material") or ""
    local bodies = {}
    for name, body in wake:gmatch("particle_system%s+([^%s{]+)%s*(%b{})") do bodies[name] = body end
    bodies["CR/Moon/HoverDust"] = moon:match("particle_system%s+CR/Moon/HoverDust%s*(%b{})")

    local kickMaterial = { regolith = "CR_FX/KickRegolith", ganymede = "CR_FX/KickIce", ice = "CR_FX/KickIce",
                           sulfur = "CR_FX/KickRegolith", mars = "CR_FX/KickPuff", ash = "CR_FX/KickPuff", grass = "CR_FX/KickClod",
                           mud = "CR_FX/KickClod" }
    for name, profile in pairs(w.Wake.Profiles) do
        local body = bodies[profile.template]
        check(body ~= nil, name .. " template exists")
        if body then
            local fy = tonumber(body:match("force_vector%s+%S+%s+(%S+)"))
            check(fy and math.abs(fy + (profile.fall or profile.g)) < 1e-9, name .. " LinearForce matches its profile gravity (" .. tostring(fy) .. ")")
            if profile.vacuum then
                check(not body:find("affector%s+Scaler"), name .. " (vacuum) has no Scaler growth")
                check(body:find("affector%s+ColourFader2") and body:find("state_change") and body:find("alpha1%s+0%s"),
                    name .. " (vacuum) holds alpha then fades at the end")
            end
            if name ~= "water" then
                check(body:match("material%s+(%S+)") == kickMaterial[name], name .. " uses " .. tostring(kickMaterial[name]))
            end
            if name ~= "water" then
                check(body:find("affector%s+Rotator") and body:find("rotation_range_end%s+360"), name .. " rotates its sprites randomly")
                local size = tonumber(body:match("particle_width%s+(%S+)"))
                check(size and size <= 1.0, name .. " vehicle sprites are small (" .. tostring(size) .. " m)")
            end
        end
    end
    for _, m in ipairs({ "CR_FX/KickRegolith", "CR_FX/KickIce", "CR_FX/KickClod", "CR_FX/KickPuff" }) do
        check(reactive:find("material%s+" .. m .. "%s*:%s*BZSprite/AlphaBlend") ~= nil, m .. " is an AlphaBlend sprite material")
    end
    for _, tex in ipairs({ "cr_kick_regolith.dds", "cr_kick_ice.dds", "cr_kick_clod.dds", "cr_kick_puff.dds" }) do
        check(reactive:find(tex, 1, true) ~= nil, tex .. " is named by a material")
        local f = io.open(scriptDir .. "/../Assets/Textures/" .. tex, "rb")
        check(f ~= nil, tex .. " ships in Assets/Textures")
        if f then f:close() end
    end
    -- Ganymede: dark dirty dust (emitter 0) and bright ice (emitter 1).
    local gb = bodies["CRWake/GanymedeSpray"]
    if gb then
        local first = gb:match("colour_range_start%s+(%S+)%s+%S+%s+%S+")
        local second = gb:match("emitter.-emitter.-colour_range_start%s+(%S+)%s+%S+%s+%S+")
        check(tonumber(first) and tonumber(first) < 0.4, "Ganymede emitter 0 is dark grey-brown")
        check(tonumber(second) and tonumber(second) > 0.6, "Ganymede emitter 1 is bright blue-white")
    end
    -- Moon mist stays below an on-foot eye: top of every layer <= 0.6 m.
    local moonWeather = readAll(scriptDir .. "/CRMoonWeather.lua") or ""
    local mistHeight = tonumber(moonWeather:match("V%.MistHeight%s*=%s*([%d%.]+)"))
    local maxThickness = 0
    for name in pairs({ ["CR/Moon/GroundMist"] = true, ["CR/Moon/LocalMist"] = true }) do
        local body = moon:match("particle_system%s+" .. name:gsub("/", "%%/") .. "%s*(%b{})")
        check(body ~= nil, name .. " exists")
        for h in (body or ""):gmatch("%sheight%s+([%d%.]+)") do maxThickness = math.max(maxThickness, tonumber(h)) end
    end
    check(mistHeight and maxThickness > 0 and mistHeight + maxThickness / 2.0 <= 0.6 + 1e-9,
        "the Moon's mist top stays at or below 0.6 m (" .. tostring(mistHeight) .. " + " .. maxThickness .. "/2)")
end

-- =============================================================================

if #failures > 0 then
    for _, message in ipairs(failures) do print("FAIL: " .. message) end
    print(#failures .. " of " .. assertions .. " expectation(s) failed")
    os.exit(1)
end
print("VEHICLE WAKES OK (" .. assertions .. " expectations)")
