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
                allCraftCalls = 0, extra = {} }
    local env = setmetatable({}, { __index = _G })
    env._G = env

    local exu = {}
    if not options.noExu then
        exu.CreateParticleSystem = function(name, template, position)
            if w.systems[name] ~= nil then return false end
            w.systems[name] = { template = template, position = position, rates = {}, local_ = nil }
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
        -- Balanced braces (Ogre skips a malformed template silently).
        local open, close = 0, 0
        for _ in payload:gmatch("{") do open = open + 1 end
        for _ in payload:gmatch("}") do close = close + 1 end
        check(open == close, "payload braces balance (" .. open .. "/" .. close .. ")")
    end
end

-- =============================================================================

if #failures > 0 then
    for _, message in ipairs(failures) do print("FAIL: " .. message) end
    print(#failures .. " of " .. assertions .. " expectation(s) failed")
    os.exit(1)
end
print("VEHICLE WAKES OK (" .. assertions .. " expectations)")
