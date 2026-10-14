-- Test-CRVenusWeather.lua
--
-- Drives the real CRVenusMap, CRVenusWeather, CRWeather and Environment modules
-- against a stubbed exu and a stubbed BZ Lua runtime. No game, no Ogre.
--
-- Usage, from the repository root:
--
--     lua Tools/Test-CRVenusWeather.lua Scripts
--
-- Every "peer" below is a fully isolated Lua environment with its own copy of
-- every module and its own globals, which is what a second machine is. Peers
-- share only a World table (the craft that exist and who owns them) and the
-- messages one sends the other.
--
-- Prints VENUS WEATHER OK on success; prints each failed expectation and exits
-- 1 otherwise.

local scriptDir = ... or "Scripts"

local failures = {}
local function check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

local function near(a, b, tolerance)
    return math.abs(a - b) <= tolerance
end

-- =============================================================================
-- Isolated peers
-- =============================================================================

local function NewWorld()
    return { objects = {}, order = {}, serial = 0 }
end

local function AddObject(world, odf, x, y, z, options)
    options = options or {}
    world.serial = world.serial + 1
    local h = world.serial + 1000
    world.objects[h] = {
        h = h, odf = odf, x = x, y = y, z = z,
        vx = 0.0, vy = 0.0, vz = 0.0,
        craft = options.craft ~= false and options.building ~= true,
        person = options.person or false,
        owner = options.owner or "host",
        mass = options.mass,
    }
    world.order[#world.order + 1] = h
    return h
end

-- Synthetic terrain: a flat shelf at 40, a pit around (500,500), a ridge around
-- (1500,1500), and a very low apron outside the playable box that must never
-- be mistaken for a basin.
local BOUNDS = { minX = 0.0, maxX = 2000.0, minZ = 0.0, maxZ = 2000.0 }

local function SyntheticHeight(x, z)
    if x < BOUNDS.minX or x > BOUNDS.maxX or z < BOUNDS.minZ or z > BOUNDS.maxZ then
        return -80.0
    end
    local h = 40.0
    local pit = math.sqrt(((x - 500.0) ^ 2) + ((z - 500.0) ^ 2))
    if pit < 220.0 then h = h - (30.0 * (1.0 - (pit / 220.0))) end
    local hill = math.sqrt(((x - 1500.0) ^ 2) + ((z - 1500.0) ^ 2))
    if hill < 260.0 then h = h + (60.0 * (1.0 - (hill / 260.0))) end
    return h
end

local damageCalls = {}

local function NewPeer(name, world, options)
    options = options or {}
    local peer = {
        name = name, now = 0.0, world = world, loaded = {}, preload = {},
        playerPos = { x = 500.0, y = 12.0, z = 500.0 },
        sounds = {}, log = {},
        rec = {
            systems = {}, fog = nil, ambient = nil, diffuse = nil, sunPower = nil,
            radarRange = {}, radarPeriod = {}, velocJam = {},
        },
    }
    local rec = peer.rec

    local env = setmetatable({}, { __index = _G })
    env._G = env
    peer.env = env

    -- ---- exu ----------------------------------------------------------------
    local exu = {}
    setmetatable(exu, { __index = function(_, key)
        if type(key) == "string" and (key:match("^SetParticle") or key:match("^Attach")
            or key:match("^Detach") or key:match("^UpdateParticle")) then
            return function() return true end
        end
        return nil
    end })
    exu.GetFog = function() return { r = 0.5, g = 0.4, b = 0.2, fogStart = 30, fogEnd = 100 } end
    exu.SetFog = function(r, g, b, s, e) rec.fog = { r = r, g = g, b = b, fogStart = s, fogEnd = e } return true end
    exu.GetAmbientLight = function() return { r = 0.0, g = 0.0, b = 0.0 } end
    exu.SetAmbientLight = function(r, g, b) rec.ambient = { r = r, g = g, b = b } return true end
    exu.GetSunDiffuse = function() return { r = 0.2, g = 0.2, b = 0.2 } end
    exu.SetSunDiffuse = function(r, g, b) rec.diffuse = { r = r, g = g, b = b } return true end
    exu.GetSunSpecular = function() return { r = 0.5, g = 0.5, b = 0.5 } end
    exu.SetSunSpecular = function() return true end
    exu.GetSunDirection = function() return { x = 0, y = -1, z = 0 } end
    exu.SetOgreSunDirection = function() return true end
    exu.GetSunPowerScale = function() return 1.0 end
    exu.SetSunPowerScale = function(v) rec.sunPower = v return true end
    exu.GetSunShadowFarDistance = function() return 900 end
    exu.SetSunShadowFarDistance = function() return true end
    exu.SetViewportShadowsEnabled = function() return true end
    exu.GetGravity = function() return { x = 0.0, y = -9.8, z = 0.0 } end
    exu.SetGravity = function() error("the Venus director must never touch gravity") end

    local STOCK_RANGE, STOCK_PERIOD, STOCK_JAM = 400.0, 1.0, 10.0
    exu.GetRadarRange = function(h) return rec.radarRange[h] or STOCK_RANGE end
    exu.SetRadarRange = function(h, v) rec.radarRange[h] = v return true end
    exu.GetRadarPeriod = function(h) return rec.radarPeriod[h] or STOCK_PERIOD end
    exu.SetRadarPeriod = function(h, v) rec.radarPeriod[h] = v return true end
    exu.GetVelocJam = function(h) return rec.velocJam[h] or STOCK_JAM end
    exu.SetVelocJam = function(h, v) rec.velocJam[h] = v return true end
    peer.STOCK_RANGE, peer.STOCK_JAM = STOCK_RANGE, STOCK_JAM

    exu.HasParticleTemplate = function() return true end
    exu.CreateParticleSystem = function(sysName, template, position)
        if rec.systems[sysName] ~= nil then return false end
        if options.failTemplate and template == options.failTemplate then return false end
        rec.systems[sysName] = {
            template = template, position = position, emitting = true, visible = true,
            rates = {}, params = {}, created = peer.now,
        }
        peer.log[#peer.log + 1] = { t = peer.now, op = "create", name = sysName, template = template, pos = position }
        return true
    end
    exu.DestroyParticleSystem = function(sysName)
        if rec.systems[sysName] == nil then return false end
        rec.systems[sysName] = nil
        return true
    end
    exu.HasParticleSystem = function(sysName) return rec.systems[sysName] ~= nil end
    exu.SetParticleSystemParticleQuota = function(sysName, q)
        if rec.systems[sysName] then rec.systems[sysName].quota = q end
        return true
    end
    exu.SetParticleSystemEmitting = function(sysName, on)
        if rec.systems[sysName] then rec.systems[sysName].emitting = on end
        return true
    end
    exu.SetParticleSystemVisible = function(sysName, on)
        if rec.systems[sysName] then rec.systems[sysName].visible = on end
        return true
    end
    exu.SetParticleSystemPosition = function(sysName, p)
        if rec.systems[sysName] then rec.systems[sysName].position = p end
        return true
    end
    exu.SetParticleEmitterEmissionRate = function(sysName, i, r)
        local s = rec.systems[sysName]
        if s then
            s.rates[i] = r
            s.peaks = s.peaks or {}
            if r > (s.peaks[i] or 0) then s.peaks[i] = r end
        end
        return true
    end
    exu.SetParticleAffectorParameter = function(sysName, i, key, value)
        local s = rec.systems[sysName]
        if s then s.params[i .. ":" .. key] = value end
        return true
    end
    exu.UpdateParticleFollowers = function() return 0 end
    exu.SetSkyDome = function() return true end
    exu.SetSkyBox = function() return true end
    exu.SetRenderEffectFloat = function() return true end

    peer.preload["exu"] = exu
    peer.preload["RuntimeEnhancements"] = {
        Initialize = function() end, Update = function() end, OnObjectCreated = function() end,
    }
    peer.preload["CRParticleTemplates"] = {
        Ensure = function() return true end,
        EnsureExtra = function() return not options.noVenusTemplates, "stub" end,
    }

    -- ---- BZ runtime -----------------------------------------------------------
    env.GetTime = function() return peer.now end
    env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
    env.print = function() end
    env.AddTMsg = function() end
    env.StartSound = function(file, h, priority, loop, volume, rate)
        peer.sounds[#peer.sounds + 1] = { t = peer.now, file = file, volume = volume, rate = rate }
    end
    env.GetPlayerHandle = function() return 1 end
    env.IsValid = function(h) return h == 1 or world.objects[h] ~= nil end
    env.GetPosition = function(h)
        if h == 1 then return peer.playerPos end
        local o = world.objects[h]
        if o then return { x = o.x, y = o.y, z = o.z } end
        return nil
    end
    env.GetVelocity = function(h)
        local o = world.objects[h]
        return o and { x = o.vx, y = o.vy, z = o.vz } or { x = 0, y = 0, z = 0 }
    end
    env.SetVelocity = function(h, v)
        local o = world.objects[h]
        if o then
            o.vx, o.vy, o.vz = v.x, v.y, v.z
            o.velocityWrites = (o.velocityWrites or 0) + 1
            o.lastWriter = name
        end
    end
    env.GetOdf = function(h)
        local o = world.objects[h]
        return o and o.odf or ""
    end
    env.IsCraft = function(h) local o = world.objects[h]; return o ~= nil and o.craft end
    env.IsPerson = function(h) local o = world.objects[h]; return o ~= nil and o.person end
    env.IsNetGame = function() return options.net == true end
    env.IsLocal = function(h)
        local o = world.objects[h]
        return o ~= nil and o.owner == name
    end
    env.GetTerrainHeightAndNormal = function(v)
        return SyntheticHeight(v.x, v.z), { x = 0, y = 1, z = 0 }
    end
    env.AllCraft = function()
        local i = 0
        return function()
            while true do
                i = i + 1
                local h = world.order[i]
                if h == nil then return nil end
                local o = world.objects[h]
                if o and o.craft then return h end
            end
        end
    end
    env.AllObjects = function()
        local i = 0
        return function()
            i = i + 1
            return world.order[i]
        end
    end
    -- Anything that could hurt something. The Venus director must call none.
    for _, fn in ipairs({ "Damage", "SetCurHealth", "AddHealth", "SetMaxHealth", "SetCurAmmo", "AddAmmo",
                          "MakeExplosion", "RemoveObject", "SetCurPilot", "Kill" }) do
        env[fn] = function(...)
            damageCalls[#damageCalls + 1] = name .. ":" .. fn
        end
    end

    -- ---- module loader ---------------------------------------------------------
    local function load(moduleName)
        if peer.loaded[moduleName] ~= nil then return peer.loaded[moduleName] end
        if peer.preload[moduleName] ~= nil then
            peer.loaded[moduleName] = peer.preload[moduleName]
            return peer.loaded[moduleName]
        end
        local chunk, err = loadfile(scriptDir .. "/" .. moduleName .. ".lua")
        if not chunk then error(err) end
        setfenv(chunk, env)
        local result = chunk(moduleName)
        peer.loaded[moduleName] = result == nil and true or result
        return peer.loaded[moduleName]
    end
    env.require = load
    env.unpack = unpack

    peer.Environment = load("Environment")
    peer.CRWeather = load("CRWeather")
    peer.Venus = load("CRVenusWeather")
    peer.Map = load("CRVenusMap")
    peer.Environment.EnableVisualRuntime = false

    function peer.step(dt)
        peer.now = peer.now + dt
        peer.Venus.Update(dt)
        peer.Environment.Update(dt)
    end

    function peer.run(seconds, dt)
        dt = dt or (1.0 / 30.0)
        local steps = math.floor(seconds / dt)
        for _ = 1, steps do peer.step(dt) end
    end

    return peer
end

local function CountSystems(peer, pattern)
    local n = 0
    for sysName in pairs(peer.rec.systems) do
        if string.find(sysName, pattern, 1, true) then n = n + 1 end
    end
    return n
end

local function TotalSystems(peer)
    local n = 0
    for _ in pairs(peer.rec.systems) do n = n + 1 end
    return n
end

-- A recorded template list, to spot which systems exist.
local function SystemsOfTemplate(peer, template)
    local list = {}
    for sysName, s in pairs(peer.rec.systems) do
        if s.template == template then list[#list + 1] = sysName end
    end
    table.sort(list)
    return list
end

local sites = dofile(scriptDir .. "/CRVenusSites07.lua")

-- =============================================================================
-- 1. Pure map module: rng, picks
-- =============================================================================

do
    local world = NewWorld()
    local peer = NewPeer("pure", world)
    local Map = peer.Map

    local a, b, c = Map.NewRng(12345), Map.NewRng(12345), Map.NewRng(54321)
    local same, diff = true, false
    for _ = 1, 200 do
        local x, y, z = a.Next(), b.Next(), c.Next()
        if x ~= y then same = false end
        if x ~= z then diff = true end
    end
    check(same, "two generators with the same seed must produce identical streams")
    check(diff, "different seeds must produce different streams")
    check(Map.DeriveSeed(7, 1) ~= Map.DeriveSeed(7, 2), "derived seeds for different salts must differ")

    local items = { { weight = 100.0, tag = "power" }, { weight = 1.0, tag = "ground" }, { weight = 0.0, tag = "never" } }
    local rng = Map.NewRng(99)
    local counts = { power = 0, ground = 0, never = 0 }
    for _ = 1, 4000 do counts[Map.PickWeighted(rng, items).tag] = counts[Map.PickWeighted(rng, items).tag] + 0 end
    for _ = 1, 4000 do
        local pick = Map.PickWeighted(rng, items)
        counts[pick.tag] = counts[pick.tag] + 1
    end
    check(counts.never == 0, "a zero-weight candidate must never be picked")
    check(counts.power > counts.ground * 40, "a 100:1 weighting must be overwhelmingly respected")
    check(Map.PickWeighted(rng, {}) == nil, "an empty candidate list picks nothing")
end

-- =============================================================================
-- 2. Severity ladder: transitions, episodes, determinism
-- =============================================================================

do
    local world = NewWorld()
    local peer = NewPeer("ladder", world)
    local Map = peer.Map

    local function Config(episodes)
        local durations = {}
        for i = 1, 5 do durations[i] = { 40.0, 90.0 } end
        local cfg = { levels = 5, start = 1, durations = durations }
        if episodes then
            cfg.episode = { chance = 0.5, minLevel = 3, minTarget = 3, peak = { 4, 5 },
                            stepDwell = { 7.0, 12.0 }, hold = { 35.0, 80.0 }, cooldown = 100.0 }
        end
        return cfg
    end

    -- One rung at a time, for an hour, with episodes on.
    local ladder = Map.NewLadder(20261013, Config(true))
    local last, maxJump, seen, episodes, maxLevel = 1, 0, {}, 0, 1
    local wasEpisode = false
    for t = 0, 3600, 1 do
        local level, episode = ladder:Advance(t, 4)
        maxJump = math.max(maxJump, math.abs(level - last))
        last = level
        seen[level] = true
        maxLevel = math.max(maxLevel, level)
        if episode and not wasEpisode then episodes = episodes + 1 end
        wasEpisode = episode
    end
    check(maxJump <= 1, "the ladder must never skip a rung, saw a jump of " .. maxJump)
    check(seen[1] and seen[2] and seen[3] and seen[4], "the ladder should visit calm through storm over an hour with target 4")
    check(episodes >= 2, "temporary storm episodes should occur, saw " .. episodes)
    check(maxLevel >= 4, "an episode or the ladder should reach the storm rung")

    -- A target of 1 never starts an episode.
    local calm = Map.NewLadder(1, Config(true))
    local calmEpisodes = 0
    for t = 0, 3600, 1 do
        local _, ep = calm:Advance(t, 1)
        if ep then calmEpisodes = calmEpisodes + 1 end
    end
    check(calmEpisodes == 0, "no episodes when the mission target is calm")

    -- Same seed, queried at different cadences: identical timeline.
    local a = Map.NewLadder(777, Config(true))
    local b = Map.NewLadder(777, Config(true))
    local c = Map.NewLadder(778, Config(true))
    local mismatch, differs = 0, 0
    for step = 1, 7200 do
        local ta = step * 0.5          -- 2 Hz
        local la = a:Advance(ta, 4)
        local lb
        for sub = 1, 15 do lb = b:Advance(((step - 1) * 0.5) + (sub * (0.5 / 15)), 4) end  -- 30 Hz
        if la ~= lb then mismatch = mismatch + 1 end
        if la ~= c:Advance(ta, 4) then differs = differs + 1 end
    end
    check(mismatch == 0, "two peers with one seed must hold the same ladder at any frame rate, mismatches " .. mismatch)
    check(differs > 0, "a different seed should produce a different ladder")

    -- Save / load continues the same timeline.
    local d = Map.NewLadder(31337, Config(true))
    local ref = Map.NewLadder(31337, Config(true))
    for t = 0, 900, 1 do d:Advance(t, 3); ref:Advance(t, 3) end
    local saved = d:Save()
    local e = Map.NewLadder(31337, Config(true))
    check(e:Load(saved), "a saved ladder should load")
    local loadMismatch = 0
    for t = 901, 3000, 1 do
        if e:Advance(t, 3) ~= ref:Advance(t, 3) then loadMismatch = loadMismatch + 1 end
    end
    check(loadMismatch == 0, "a loaded ladder must continue the identical timeline, mismatches " .. loadMismatch)
end

-- =============================================================================
-- 3. Fog pool detection on a synthetic heightfield
-- =============================================================================

do
    local world = NewWorld()
    local peer = NewPeer("fog", world)
    local Map = peer.Map

    local queried = 0
    local scan = Map.NewHeightScan(BOUNDS, 64, 64, function(x, z)
        queried = queried + 1
        return SyntheticHeight(x, z)
    end, 60.0)
    local steps = 0
    while not scan:Step(100) do steps = steps + 1 end
    check(steps >= 30, "the terrain scan must be spread over many frames, took " .. steps .. " steps")
    check(queried == 64 * 64, "the scan should sample every grid point exactly once")

    local result = Map.AnalyseBasins(scan, { minRelief = 2.0 })
    check(result ~= nil, "basin analysis should complete")
    check(#result.clusters >= 1, "the pit should be found as a basin")

    local nearPit = false
    for _, c in ipairs(result.clusters) do
        if math.sqrt(((c.cx - 500) ^ 2) + ((c.cz - 500) ^ 2)) < 150 then nearPit = true end
        check(c.cz > 0 and c.cz < 2000 and c.cx > 0 and c.cx < 2000, "a basin must be inside the playable box")
        check(c.minHeight > -10, "the out-of-bounds apron (-80) must never form a basin")
    end
    check(nearPit, "a basin should be centred on the pit at (500, 500)")
    check(result.poolLevel < result.median, "the pool level must sit under the median ground")
    check(result.ridgeLevel >= result.median, "the ridge level must not sit under the median ground")

    for _, anchor in ipairs(result.anchors) do
        local onHill = math.sqrt(((anchor.x - 1500) ^ 2) + ((anchor.z - 1500) ^ 2)) < 260
        check(not onHill, "no fog system belongs on the ridge")
    end
    check(#result.anchors >= 1 and #result.anchors <= 24, "anchors must be present and capped")

    -- Altitude factor: dense in the pit, gone on the ridge, monotonic between.
    local deep = Map.PoolFactor(result, 500, 12, 500)
    local ridge = Map.PoolFactor(result, 1500, 100, 1500)
    local mid = Map.PoolFactor(result, 500, 12 + 8, 500)
    check(deep > 0.9, "standing in the pit should be full pool fog, got " .. deep)
    check(ridge < 0.05, "standing on the ridge should be clear, got " .. ridge)
    check(deep >= mid and mid >= ridge, "pool factor must fall as altitude rises")

    -- A flat map has nothing worth fogging.
    local flat = Map.NewHeightScan(BOUNDS, 32, 32, function() return 40.0 end, 0.0)
    flat:Step(1e9)
    local none = Map.AnalyseBasins(flat, {})
    check(none ~= nil and #none.clusters == 0 and #none.anchors == 0, "a flat map has no basins")
end

-- =============================================================================
-- 3b. The real misn07 heightfield (skipped when the HG2 is not in the checkout)
-- =============================================================================

do
    local path = scriptDir .. "/../Missions/misn07.hg2"
    local file = io.open(path, "rb")
    if file == nil then
        print("note: " .. path .. " not found; skipping the real-terrain basin check")
    else
        local data = file:read("*a")
        file:close()
        -- HG2: 12-byte header, then 4x4 zones of 256x256 uint16 samples, zones
        -- row-major, each zone row-major, low z first, 5 world units per sample.
        -- Metres = 0.09838 * raw + 0.465 (fitted against BZN object elevations).
        local function Height(x, z)
            local col = math.floor(x / 5.0)
            local row = math.floor((z - 97280.0) / 5.0)
            if col < 0 or row < 0 or col > 1023 or row > 1023 then return nil end
            local zoneIndex = (math.floor(row / 256) * 4) + math.floor(col / 256)
            local within = ((row % 256) * 256) + (col % 256)
            local offset = 12 + (((zoneIndex * 65536) + within) * 2)
            local lo, hi = data:byte(offset + 1, offset + 2)
            return (((hi * 256) + lo) * 0.09838) + 0.465
        end

        local world = NewWorld()
        local peer = NewPeer("misn07terrain", world)
        local Map = peer.Map
        local scan = Map.NewHeightScan(sites.bounds, 64, 56, Height, 60.0)
        scan:Step(1e9)
        local result = Map.AnalyseBasins(scan, { maxAnchors = 24 })
        check(result ~= nil and #result.clusters >= 8, "misn07 should have many enclosed lowland basins")
        check(result.poolLevel > 15.0 and result.poolLevel < 26.0,
            string.format("misn07 pool level should be ~20 m, got %.1f", result.poolLevel))
        check(result.median > 25.0 and result.median < 36.0, "misn07 median ground should be ~30 m")
        check(result.ridgeLevel > 60.0, "misn07 ridges should stand well over the pools")
        check(#result.anchors > 0 and #result.anchors <= 24, "misn07 should yield a bounded anchor list")
        local central = 0
        for _, a in ipairs(result.anchors) do
            check(a.x >= sites.bounds.minX and a.x <= sites.bounds.maxX and a.z >= sites.bounds.minZ and a.z <= sites.bounds.maxZ,
                "an anchor must be inside the playable box")
            if a.x > 1500 and a.x < 3700 and a.z > 98500 and a.z < 100500 then central = central + 1 end
        end
        check(central >= 5, "the central play area should carry fog pools, found " .. central)
        print(string.format("  misn07 basins: %d clusters, %d anchors, pool %.1f m, median %.1f m, ridge %.1f m (%d central)",
            #result.clusters, #result.anchors, result.poolLevel, result.median, result.ridgeLevel, central))
    end
end

-- =============================================================================
-- 4. Sulfur clustering on a synthetic mat grid
-- =============================================================================

do
    local world = NewWorld()
    local peer = NewPeer("sulfur", world)
    local Map = peer.Map

    -- 64x64 grid of 20-unit cells at origin (1000, 5000). Material 1 = liquid
    -- sulphur. Two pools, one stray single cell, and some "transition" edges.
    local grid = {}
    local function put(col, row, base, nxt) grid[(row * 64) + col] = (base * 4096) + (nxt * 256) end
    for row = 10, 15 do for col = 10, 16 do put(col, row, 1, 1) end end         -- pool A: 42 solid
    for row = 40, 44 do for col = 30, 35 do put(col, row, 1, 1) end end         -- pool B: 30 solid
    for row = 9, 16 do put(9, row, 0, 1) put(17, row, 0, 1) end                 -- A's transition rim
    put(55, 55, 1, 1)                                                           -- stray cell
    put(2, 2, 0, 3)                                                             -- hardened sulphur: not a pool

    local cells, count = Map.CellsFromMat(64, 64, function(c, r) return grid[(r * 64) + c] or 0 end, { 1 }, 0.5)
    check(count == 42 + 30 + 16 + 1, "expected 89 liquid-sulphur cells, got " .. count)
    local clustered = Map.ClusterSulfur(cells, { cols = 64, rows = 64, cell = 20, originX = 1000, originZ = 5000 },
        { minCells = 4, maxPerCluster = 4, emitterSpacing = 40.0, maxEmitters = 6 })
    check(#clustered.clusters == 2, "two pools expected (stray cell dropped), got " .. #clustered.clusters)

    local a, b = clustered.clusters[1], clustered.clusters[2]
    check(near(a.cx, 1000 + (13.0 * 20), 25.0) and near(a.cz, 5000 + (12.5 * 20), 25.0),
        string.format("pool A centre wrong: %.0f, %.0f", a.cx, a.cz))
    check(near(b.cx, 1000 + (33.0 * 20), 25.0) and near(b.cz, 5000 + (42.5 * 20), 25.0),
        string.format("pool B centre wrong: %.0f, %.0f", b.cx, b.cz))
    check(#clustered.emitters <= 6, "emitters must respect the global cap")
    for i = 1, #clustered.emitters do
        for j = i + 1, #clustered.emitters do
            local e1, e2 = clustered.emitters[i], clustered.emitters[j]
            if e1.cluster == e2.cluster then
                local d = math.sqrt(((e1.x - e2.x) ^ 2) + ((e1.z - e2.z) ^ 2))
                check(d >= 39.9, "emitters in one pool must be spaced apart")
            end
        end
    end
    check(clustered.emitters[1].weight == 1.0, "solid cells are placed before transition cells")

    -- The shipped misn07 data: two big clusters, as the .mat analysis found.
    local expanded, total = Map.ExpandRuns(sites.sulfur)
    check(total == 734, "misn07 should have 734 liquid-sulphur cells, got " .. total)
    local real = Map.ClusterSulfur(expanded, sites.sulfur, {})
    check(#real.clusters == 2, "misn07 should have two sulfur pools, got " .. #real.clusters)

    -- Vent merging: five geysers a few metres apart are one volcano.
    local merged = Map.MergeVents(sites.vents, 45.0)
    check(#merged == 16, "21 misn07 vent objects should merge to 16 sites, got " .. #merged)
    local majors = 0
    for _, v in ipairs(merged) do if v.major then majors = majors + 1 end end
    check(majors == 2, "misn07 has two named volcano vents, got " .. majors)
end

-- =============================================================================
-- 5. Director on one peer
-- =============================================================================

local function ForceRung(peer, rung)
    peer.Venus.ForceLevel(rung, 100000.0, 0.05)
    peer.run(40.0)       -- let the smoothed severity arrive
end

do
    local world = NewWorld()
    local peer = NewPeer("host", world)
    local V = peer.Venus
    local Env = peer.Environment

    -- Three generators far from the player, a tower, and craft to test blast on.
    local power1 = AddObject(world, "sblpow", 900, 40, 900, { building = true, owner = "host" })
    local power2 = AddObject(world, "ablpow", 1000, 40, 950, { building = true, owner = "host" })
    local power3 = AddObject(world, "cblpow", 1100, 40, 880, { building = true, owner = "host" })
    local tower = AddObject(world, "sbtowe", 700, 40, 1200, { building = true, owner = "host" })
    local ground1 = AddObject(world, "avtank", 1300, 40, 300, { owner = "host" })
    local ground2 = AddObject(world, "avtank", 1350, 40, 320, { owner = "host" })
    local ground3 = AddObject(world, "svtank", 400, 12, 560, { owner = "host" })

    Env.Init()
    V.Init({
        seed = 424242, authority = true, sites = sites, startLevel = 1, targetLevel = 4,
        bounds = BOUNDS,
    })
    check(Env.Modifiers["CRWeather"] ~= nil, "CRWeather should contribute through Environment")
    check(Env.Modifiers["CRVenusWeather"] ~= nil, "the director should register an environment modifier")
    check(Env.GameplayModifiers["CRVenusWeather"] ~= nil, "the director should register a gameplay modifier")
    check(peer.CRWeather.GetPreset() == "VenusCalm", "should open on VenusCalm, got " .. tostring(peer.CRWeather.GetPreset()))

    -- ---- lightning power ODFs ---------------------------------------------------
    for _, odf in ipairs({ "ablpow", "bblpow", "cblpow", "sblpow", "sblpowa", "sblpowb" }) do
        local h = AddObject(world, odf, 10, 0, 10, { building = true })
        check(V.IsLightningPower(h), odf .. " should be recognised as a Lightning Power generator")
        world.objects[h] = nil
        for i = #world.order, 1, -1 do if world.order[i] == h then table.remove(world.order, i) end end
    end
    check(not V.IsLightningPower(tower), "a tower is not a Lightning Power generator")

    -- ---- target weighting --------------------------------------------------------
    V.Powers = {}
    for _, h in ipairs({ power1, power2, power3 }) do V.Powers[h] = true end
    local picks = { power = 0, other = 0 }
    for _ = 1, 600 do
        local pick = V.PickStrikeTarget()
        if pick.kind == 1 then picks.power = picks.power + 1 else picks.other = picks.other + 1 end
    end
    check(picks.power >= 540, string.format("generators must draw the overwhelming share of strikes: %d of 600", picks.power))
    check(picks.other > 0, "other targets should still be struck now and then")

    local candidates = V.BuildStrikeCandidates()
    local kinds = {}
    for _, c in ipairs(candidates) do kinds[c.kind] = (kinds[c.kind] or 0) + 1 end
    check(kinds[1] == 3, "all three generators should be candidates")
    check((kinds[2] or 0) >= 1, "the tower should be an exposed candidate")
    check((kinds[3] or 0) == V.GroundCandidates, "random ground near the player should be offered")

    -- With no generators the other targets are all that remains.
    V.Powers = {}
    local noPower = V.PickStrikeTarget()
    check(noPower ~= nil and noPower.kind ~= 1, "with no generators strikes fall on other targets")
    for _, h in ipairs({ power1, power2, power3 }) do V.Powers[h] = true end

    -- ---- the ladder drives presets, severity and gameplay ------------------------
    local presetsSeen = {}
    local maxJump, lastLevel = 0, V.GetLevel()
    local stormStrikes, calmStrikes = 0, 0
    local maxSystems = 0
    for step = 1, 30 * 60 * 20 do
        peer.step(1.0 / 30.0)
        local level = V.GetLevel()
        maxJump = math.max(maxJump, math.abs(level - lastLevel))
        lastLevel = level
        presetsSeen[peer.CRWeather.GetPreset()] = true
        maxSystems = math.max(maxSystems, TotalSystems(peer))
    end
    check(maxJump <= 1, "the Venus ladder must move one rung at a time, saw " .. maxJump)
    for preset in pairs(presetsSeen) do
        check(string.find(preset, "Venus", 1, true) == 1, "a Venus mission should only select Venus presets, saw " .. tostring(preset))
    end
    check(V.GetStats().strikes > 5, "twenty minutes toward a storm should produce strikes, saw " .. V.GetStats().strikes)
    check(V.GetStats().powerStrikes >= V.GetStats().strikes * 0.8,
        string.format("generators should take most strikes: %d of %d", V.GetStats().powerStrikes, V.GetStats().strikes))
    check(maxSystems <= V.MaxSystems, "particle systems exceeded the hard cap: " .. maxSystems)
    check(next(damageCalls) == nil, "weather must never call a damaging function: " .. tostring(damageCalls[1]))
    check(CountSystems(peer, "cr_vw_fog") <= V.MaxLiveFog, "live fog systems exceeded the cap")

    -- ---- strike lifecycle: telegraph, then bolt, flash, thunder ------------------
    ForceRung(peer, 4)
    V.NextStrikeAt = 1e9
    peer.run(10.0)          -- let any strike already in flight finish cleanly
    peer.log = {}
    peer.sounds = {}
    V.Flashes = {}
    local startedAt = peer.now
    V.TriggerStrike({ x = 1000, y = 40, z = 950, kind = 1 })
    peer.step(1.0 / 30.0)
    check(#SystemsOfTemplate(peer, "CR/Venus/StElmo") == 1, "a strike must open with the St Elmo's fire telegraph")
    check(#SystemsOfTemplate(peer, "CR/Venus/Bolt") == 0, "the bolt must not exist before the telegraph ends")
    peer.run(0.9)
    check(#SystemsOfTemplate(peer, "CR/Venus/Bolt") == 0, "still telegraphing after 0.9 s")
    peer.run(1.3)
    local boltAt, elmoAt = nil, nil
    for _, entry in ipairs(peer.log) do
        if entry.template == "CR/Venus/Bolt" and boltAt == nil then boltAt = entry.t end
        if entry.template == "CR/Venus/StElmo" and elmoAt == nil then elmoAt = entry.t end
    end
    check(boltAt ~= nil, "the bolt should appear when the telegraph ends")
    check(boltAt ~= nil and elmoAt ~= nil and (boltAt - elmoAt) >= 1.15 and (boltAt - elmoAt) <= 2.1,
        string.format("telegraph should last 1.2-2.0 s, was %.2f", (boltAt or 0) - (elmoAt or 0)))
    peer.run(4.0)
    local sawThunder = false
    for _, s in ipairs(peer.sounds) do
        if s.file == "lstart.wav" then sawThunder = true end
    end
    check(sawThunder, "a strike should be followed by thunder (lstart.wav, a stock sound)")
    check(#SystemsOfTemplate(peer, "CR/Venus/Bolt") == 0, "bolt systems must be cleaned up after the strike")

    -- ---- the flash: a local spike on ambient --------------------------------------
    peer.playerPos = { x = 1000, y = 40, z = 900 }     -- right next to the next strike
    peer.run(1.0)
    V.TriggerStrike({ x = 1000, y = 40, z = 950, kind = 1 })
    local baseAmbient = nil
    local peakAmbient = 0
    for _ = 1, 30 * 4 do
        peer.step(1.0 / 30.0)
        if peer.rec.ambient then
            if baseAmbient == nil then baseAmbient = peer.rec.ambient.r end
            peakAmbient = math.max(peakAmbient, peer.rec.ambient.r)
        end
    end
    check(baseAmbient ~= nil and peakAmbient > baseAmbient + 0.15,
        string.format("a nearby strike should spike ambient light (%.3f -> %.3f)", baseAmbient or 0, peakAmbient))
    peer.run(2.0)
    check(near(peer.rec.ambient.r, baseAmbient, 0.05), "ambient must return to normal after the flash")

    -- ---- knockback: radius, direction, falloff, cap, no damage ---------------------
    local function Reset(h, x, z, vx, vz)
        local o = world.objects[h]
        o.x, o.z, o.vx, o.vy, o.vz, o.velocityWrites = x, z, vx or 0, 0, vz or 0, nil
    end
    local sx, sz = 1000.0, 950.0
    local near1 = AddObject(world, "avtank", sx + 15, 40, sz, { owner = "host" })
    local near2 = AddObject(world, "avtank", sx + 0, 40, sz + 45, { owner = "host" })
    local edge = AddObject(world, "avtank", sx - 66, 40, sz, { owner = "host" })
    local outside = AddObject(world, "avtank", sx + 95, 40, sz, { owner = "host" })
    local beyond = AddObject(world, "avtank", sx + 140, 40, sz, { owner = "host" })
    local pilot = AddObject(world, "ispilo", sx + 10, 40, sz, { owner = "host", person = true })
    local fast = AddObject(world, "avtank", sx + 20, 40, sz + 5, { owner = "host" })
    world.objects[fast].vx = 60.0
    local heavy = AddObject(world, "avhaul", sx + 15, 40, sz + 10, { owner = "host", mass = 8000 })

    local moved = V.ApplyStrikeEffects(sx, 40, sz, 1.0)
    local o1, o2, oe, oo = world.objects[near1], world.objects[near2], world.objects[edge], world.objects[outside]
    local speed = function(o) return math.sqrt((o.vx ^ 2) + (o.vz ^ 2)) end
    check(o1.vx > 5.0 and near(o1.vz, 0.0, 0.5), "a craft east of the strike is shoved east")
    check(o2.vz > 5.0, "a craft north of the strike is shoved north")
    check(oe.vx < 0.0, "a craft west of the strike is shoved west (away)")
    check(speed(o1) > speed(oe), "the shove falls off with distance")
    check(oe.vx ~= 0.0 and speed(oe) < 3.0, "the edge of the radius is barely a nudge, got " .. speed(oe))
    check((oo.velocityWrites or 0) == 0, "a craft outside the radius must not be touched")
    check((world.objects[pilot].velocityWrites or 0) == 0, "a pilot on foot is not flung")
    check(o1.vy > 0.0 and o1.vy < speed(o1), "the lift is a fraction of the shove (hover-safe)")
    check(speed(o1) <= V.KnockMaxSpeed * 1.01, "the shove never exceeds the configured maximum")
    check(math.sqrt((world.objects[fast].vx ^ 2) + (world.objects[fast].vz ^ 2)) <= 60.0 + 0.01,
        "a craft already above the speed cap must not be accelerated further")
    check(speed(world.objects[heavy]) < speed(o1), "a heavy hauler is shoved less than a tank")
    check(moved >= 5, "the shove count should reflect the craft moved, got " .. moved)
    check(next(damageCalls) == nil, "knockback must not damage anything")

    -- Knockback can be switched off without touching sensors.
    V.AllowKnockback = false
    Reset(near1, sx + 15, sz)
    V.ApplyStrikeEffects(sx, 40, sz, 1.0)
    check(world.objects[near1].velocityWrites == nil, "AllowKnockback=false must stop the shove")
    V.AllowKnockback = true

    -- ---- radar scramble: applies, scales, expires -----------------------------------
    for h in pairs(peer.rec.radarRange) do peer.rec.radarRange[h] = nil end
    Env.ObjectScrambles = {}
    Env.PendingGameplaySync = true
    peer.run(2.0)
    local before = peer.rec.radarRange[near1] or peer.STOCK_RANGE
    V.ApplyStrikeEffects(sx, 40, sz, 1.0)
    local scrambled = peer.rec.radarRange[near1]
    check(scrambled ~= nil and scrambled < before * 0.25,
        string.format("a strike should scramble nearby radar hard (%s -> %s)", tostring(before), tostring(scrambled)))
    check((peer.rec.velocJam[near1] or 0) > peer.STOCK_JAM * 1.5, "velocity jam should rise during the scramble")
    check(peer.rec.radarRange[beyond] == nil or peer.rec.radarRange[beyond] > before * 0.5,
        "a craft beyond the scramble radius keeps its radar")
    peer.run(V.ScrambleSeconds[2] + 1.0)
    local restored = peer.rec.radarRange[near1]
    check(restored ~= nil and restored > scrambled * 3.0,
        string.format("the scramble must expire on its own (%s -> %s)", tostring(scrambled), tostring(restored)))
    check(Env.GetObjectScramble(near1) == nil, "the scramble entry should be gone after expiry")

    -- A second strike never shortens the first's scramble.
    Env.SetObjectScramble(near2, 8.0, { radarRange = 0.1 })
    Env.SetObjectScramble(near2, 1.0, { radarRange = 0.1 })
    peer.run(3.0)
    check(Env.GetObjectScramble(near2) ~= nil, "a short scramble must not cut a long one short")
    V.AllowRadarScramble = false
    Env.ObjectScrambles = {}
    local rangeBefore = peer.rec.radarRange[near1]
    V.ApplyStrikeEffects(sx, 40, sz, 1.0)
    check(peer.rec.radarRange[near1] == rangeBefore, "AllowRadarScramble=false must leave sensors alone")
    V.AllowRadarScramble = true

    -- ---- fog by altitude ------------------------------------------------------------
    ForceRung(peer, 2)
    V.Flashes = {}
    V.ForcedLevel = nil
    ForceRung(peer, 2)
    V.Flashes = {}
    peer.playerPos = { x = 500.0, y = 12.0, z = 500.0 }       -- down in the pit
    peer.run(15.0)
    local pitEnd = peer.rec.fog.fogEnd
    peer.playerPos = { x = 1500.0, y = 120.0, z = 1500.0 }    -- up on the ridge
    peer.run(15.0)
    local ridgeEnd = peer.rec.fog.fogEnd
    check(pitEnd < ridgeEnd * 0.8, string.format("fog should be denser in the pit (%.1f) than on the ridge (%.1f)", pitEnd, ridgeEnd))
    check(V.GetPoolFactor() < 0.1, "the pool factor on the ridge should be near zero")
    check(peer.rec.fog.fogStart < peer.rec.fog.fogEnd, "fog start must stay under fog end")

    -- Pooled fog systems stream in near the player and stay capped.
    peer.playerPos = { x = 500.0, y = 12.0, z = 500.0 }
    peer.run(30.0)
    local fogNear = CountSystems(peer, "cr_vw_fog")
    check(fogNear >= 1 and fogNear <= V.MaxLiveFog, "fog systems should stream in around the player, got " .. fogNear)
    peer.playerPos = { x = 1950.0, y = 40.0, z = 150.0 }
    peer.run(20.0)
    check(CountSystems(peer, "cr_vw_fog") <= fogNear, "fog systems far from the player must stream out")

    -- ---- acid rain: visual only, tied to severity -------------------------------------
    local function RainRate()
        local rainSystems = SystemsOfTemplate(peer, "CR/Weather/Rain")
        if #rainSystems == 0 then return 0.0 end
        local s = peer.rec.systems[rainSystems[1]]
        if not s.emitting then return 0.0 end
        return s.rates[0] or 0.0
    end
    peer.playerPos = { x = 500.0, y = 12.0, z = 500.0 }
    ForceRung(peer, 1)
    local calmRain = RainRate()
    ForceRung(peer, 3)
    local risingRain = RainRate()
    ForceRung(peer, 5)
    local severeRain = RainRate()
    check(calmRain == 0.0, "no rain in the calm")
    check(risingRain > 50.0 and severeRain > risingRain, string.format("rain should grow with severity (%.0f -> %.0f)", risingRain, severeRain))
    check(severeRain <= V.RainMaxRate + 0.01, "rain rate is capped")
    check(next(damageCalls) == nil, "acid rain must do no damage")
    V.AllowAcidRain = false
    peer.run(2.0)
    check(RainRate() == 0.0, "AllowAcidRain=false must stop the rain")
    V.AllowAcidRain = true
    ForceRung(peer, 5)
    check(RainRate() > 100.0, "rain returns when re-enabled")

    -- ---- sulfur pools and burps -------------------------------------------------------
    peer.playerPos = { x = 3415.0, y = 20.0, z = 99064.0 }
    -- (The synthetic terrain offsets differ from the real map; site streaming is
    -- by distance only, so move the sites into the test box instead.)
    local sulfurSites = {}
    for i = 1, 12 do sulfurSites[i] = { x = 300 + (i * 40), z = 300 + (i * 25), weight = (i % 2 == 0) and 1.0 or 0.5, cluster = 1 } end
    V.SulfurSites = sulfurSites
    V.SulfurLive = {}
    peer.playerPos = { x = 400.0, y = 20.0, z = 400.0 }
    peer.run(40.0)
    local sulfurLive = CountSystems(peer, "cr_vw_sulfur")
    check(sulfurLive >= 1 and sulfurLive <= V.MaxLiveSulfur, "sulfur pools stream in, capped at " .. V.MaxLiveSulfur .. ", got " .. sulfurLive)
    local burps = 0
    for _, name in ipairs(SystemsOfTemplate(peer, "CR/Venus/SulfurPool")) do
        local s = peer.rec.systems[name]
        if (s.peaks and s.peaks[1] or 0) >= V.SulfurBurpRate - 1 then burps = burps + 1 end
        check((s.rates[0] or 0) > 0.5, "a pool steams continuously")
    end
    check(burps >= 1, "sulfur pools should burp periodically")

    -- ---- volcanic vents and eruptions ---------------------------------------------------
    local ventSites = {
        { x = 300, y = 40, z = 300, major = true, count = 1, label = "v1" },
        { x = 340, y = 40, z = 350, major = false, count = 1, label = "v2" },
    }
    V.VentSites = ventSites
    V.PlumeLive = {}
    peer.playerPos = { x = 320.0, y = 40.0, z = 320.0 }
    peer.run(5.0)
    check(#SystemsOfTemplate(peer, "CR/Venus/Plume") == 2, "plumes should stand over nearby vents")
    local plume1 = peer.rec.systems[SystemsOfTemplate(peer, "CR/Venus/Plume")[1]]
    check((plume1.rates[0] or 0) > 1.0, "a vent smokes constantly")
    V.TriggerEruption(1)
    peer.run(4.0)
    local erupting = false
    for _, name in ipairs(SystemsOfTemplate(peer, "CR/Venus/Plume")) do
        if (peer.rec.systems[name].rates[1] or 0) > 20.0 then erupting = true end
    end
    check(erupting, "an eruption raises the ash burst")
    check(#SystemsOfTemplate(peer, "CR/Venus/Embers") >= 1, "an eruption throws embers")
    local rumble = false
    for _, s in ipairs(peer.sounds) do if s.file == "gquak00.wav" then rumble = true end end
    check(rumble, "an eruption rumbles (gquak00.wav, a stock sound)")
    peer.run(40.0)
    for _, name in ipairs(SystemsOfTemplate(peer, "CR/Venus/Plume")) do
        check((peer.rec.systems[name].rates[1] or 0) == 0.0, "the burst stops when the eruption ends")
    end
    check(#SystemsOfTemplate(peer, "CR/Venus/Embers") == 0, "embers are released when the eruption ends")
    check(next(damageCalls) == nil, "eruptions are visual only")

    -- ---- save / load ----------------------------------------------------------------------
    ForceRung(peer, 3)
    local saved = V.Save()
    local seedBefore = V.Seed
    V.Level = 1
    V.Load(saved)
    check(V.Seed == seedBefore, "load restores the seed")
    check(V.GetLevel() == 3 or V.ForcedLevel == 3, "load restores the rung")
    check(CountSystems(peer, "cr_vw_") == 0, "load must drop every Venus system; the scene they lived in is gone")

    -- ---- shutdown leaves nothing -----------------------------------------------------------
    V.Shutdown()
    check(TotalSystems(peer) == 0, "shutdown must destroy every particle system, left " .. TotalSystems(peer))
    check(Env.Modifiers["CRVenusWeather"] == nil, "shutdown must unregister the environment modifier")
    check(Env.GameplayModifiers["CRVenusWeather"] == nil, "shutdown must unregister the gameplay modifier")
end

-- =============================================================================
-- 6. Template failure: the director degrades instead of breaking
-- =============================================================================

do
    local world = NewWorld()
    local peer = NewPeer("degraded", world, { noVenusTemplates = true })
    local V = peer.Venus
    peer.Environment.Init()
    AddObject(world, "sblpow", 900, 40, 900, { building = true })
    V.Init({ seed = 5, authority = true, sites = sites, bounds = BOUNDS, targetLevel = 4 })
    peer.run(60.0)
    check(not V.TemplatesReady, "missing cr_venus payload should be detected")
    check(CountSystems(peer, "cr_vw_fog") == 0 and CountSystems(peer, "cr_vw_plume") == 0,
        "no Venus-template systems without the payload")
    ForceRung(peer, 4)
    local before = V.GetStats().strikes
    V.TriggerStrike({ x = 500, y = 12, z = 500, kind = 3 })
    peer.run(3.0)
    check(V.GetStats().strikes == before + 1, "strikes still land (flash, thunder, knockback) without the particle payload")
    V.Shutdown()

    -- A template that fails to create is given up on after a few tries.
    local world2 = NewWorld()
    local peer2 = NewPeer("failing", world2, { failTemplate = "CR/Venus/FogPool" })
    peer2.Environment.Init()
    peer2.Venus.Init({ seed = 6, authority = true, sites = sites, bounds = BOUNDS, targetLevel = 2 })
    peer2.playerPos = { x = 500, y = 12, z = 500 }
    peer2.run(60.0)
    check((peer2.Venus.TemplateFailures["CR/Venus/FogPool"] or 0) >= peer2.Venus.MaxFailuresPerTemplate,
        "a template that never builds should be abandoned after a few attempts")
    peer2.Venus.Shutdown()
end

-- =============================================================================
-- 7. Co-op: two peers, host decides, guest follows
-- =============================================================================

do
    local world = NewWorld()
    local hostPeer = NewPeer("host", world, { net = true })
    local guestPeer = NewPeer("guest", world, { net = true })
    local H, G = hostPeer.Venus, guestPeer.Venus

    local gen = AddObject(world, "sblpow", 900, 40, 900, { building = true, owner = "host" })
    local hostTank = AddObject(world, "avtank", 1000, 40, 940, { owner = "host" })
    local guestTank = AddObject(world, "avtank", 1030, 40, 950, { owner = "guest" })
    local guestFar = AddObject(world, "avtank", 1500, 40, 950, { owner = "guest" })

    -- A delayed, ordered link from host to guest that can lose chosen ops.
    local queue = {}
    local sent, dropStates = {}, false
    local function HostSend(op, ...)
        sent[#sent + 1] = { op = op, args = { ... }, n = select("#", ...) }
        if dropStates and op == "VenusState" then return end
        queue[#queue + 1] = { at = hostPeer.now + 0.12, op = op, args = { ... }, n = select("#", ...) }
    end
    local unpackArgs = unpack

    hostPeer.Environment.Init()
    guestPeer.Environment.Init()
    H.Init({ seed = 987654, authority = true, send = HostSend, sites = sites, bounds = BOUNDS, targetLevel = 4 })
    G.Init({ authority = false, sites = sites, bounds = BOUNDS, targetLevel = 4 })      -- no seed: waits for the host

    check(not G.Synced, "a guest with no seed must wait for the host rather than invent a timeline")
    check(sent[1] ~= nil and sent[1].op == "VenusState", "the host announces its seed and state at start")

    local function Pump()
        local keep = {}
        for i = 1, #queue do
            local m = queue[i]
            if guestPeer.now >= m.at then
                G.ApplyNetEvent(m.op, unpackArgs(m.args, 1, m.n))
            else
                keep[#keep + 1] = m
            end
        end
        queue = keep
    end

    -- One shared wall clock; each peer renders frames at its own rate against it.
    local hostDt, guestDt = 1.0 / 30.0, 1.0 / 47.0
    local wall, hostNext, guestNext = 0.0, hostDt, guestDt
    local function RunBoth(seconds)
        local target = wall + seconds
        while true do
            local nextFrame = math.min(hostNext, guestNext)
            if nextFrame > target then break end
            wall = nextFrame
            if hostNext <= guestNext then
                hostPeer.step(hostDt); hostNext = hostNext + hostDt
            else
                guestPeer.step(guestDt); guestNext = guestNext + guestDt
            end
            Pump()
        end
        wall = target
    end

    RunBoth(2.0)
    check(G.Synced and G.Seed == 987654, "the guest adopts the host's seed")

    -- Levels match throughout a long run, at different frame rates.
    local mismatches, samples = 0, 0
    local hostHadStorm = false
    for _ = 1, 15 * 60 do
        RunBoth(1.0)
        samples = samples + 1
        if H.GetLevel() ~= G.GetLevel() then mismatches = mismatches + 1 end
        if H.GetLevel() >= 4 then hostHadStorm = true end
    end
    check(mismatches <= samples * 0.02, string.format("guest rung must track the host (%d of %d seconds differ)", mismatches, samples))
    check(hostHadStorm, "the shared run should include storm weather")

    -- Strikes: host decides, guest replays identical events.
    local hostStrikes, guestStrikes = 0, 0
    for _, m in ipairs(sent) do if m.op == "VenusStrike" then hostStrikes = hostStrikes + 1 end end
    guestStrikes = G.GetStats().strikes
    check(hostStrikes > 5, "the host should have sent strike events, saw " .. hostStrikes)
    check(near(guestStrikes, H.GetStats().strikes, 1), string.format("the guest renders the host's strikes (%d vs %d)", guestStrikes, H.GetStats().strikes))
    check(G.GetStats().powerStrikes == H.GetStats().powerStrikes, "guest and host agree on strike targets")

    -- The guest never schedules strikes of its own.
    local guestAlone = NewPeer("lonely", world, { net = true })
    guestAlone.Environment.Init()
    guestAlone.Venus.Init({ seed = 987654, authority = false, sites = sites, bounds = BOUNDS, targetLevel = 4 })
    guestAlone.Venus.ForcedLevel = 5
    guestAlone.Venus.ForcedUntil = 1e9
    guestAlone.run(300.0)
    check(guestAlone.Venus.GetStats().strikes == 0, "a guest decides no strikes; it only replays the host's")

    -- Knockback is applied by the OWNING peer only, exactly once.
    world.objects[guestTank].vx, world.objects[guestTank].vz = 0, 0
    world.objects[hostTank].vx, world.objects[hostTank].vz = 0, 0
    world.objects[guestTank].velocityWrites, world.objects[hostTank].velocityWrites = nil, nil
    hostPeer.Venus.NextStrikeAt = 1e9
    H.TriggerStrike({ x = 1010, y = 40, z = 945, kind = 3 })
    RunBoth(4.0)
    local gt, ht = world.objects[guestTank], world.objects[hostTank]
    check(gt.velocityWrites == 1 and gt.lastWriter == "guest", "a guest's craft is shoved by the guest, once")
    check(ht.velocityWrites == 1 and ht.lastWriter == "host", "a host's craft is shoved by the host, once")
    check((world.objects[guestFar].velocityWrites or 0) == 0, "distant craft are untouched on both peers")
    check(gt.vx > 0 or gt.vz ~= 0, "the guest's craft actually moved")

    -- Radar scramble likewise lands on the owner.
    check(guestPeer.rec.radarRange[guestTank] ~= nil and hostPeer.rec.radarRange[guestTank] == nil,
        "the guest scrambles its own craft's radar and the host leaves it alone")

    -- Eruptions are host-chosen and replayed.
    local ventSitesH = { { x = 400, y = 40, z = 400, major = true, count = 1, label = "v" } }
    H.VentSites, G.VentSites = ventSitesH, ventSitesH
    local before = G.GetStats().eruptions
    H.TriggerEruption(1)
    RunBoth(3.0)
    check(G.GetStats().eruptions == before + 1, "the guest replays the host's eruption")

    -- Ground strikes are offered near EVERY human player, not just the host's.
    H.PlayersProvider = function() return { guestFar } end
    local savedPowers = H.Powers
    H.Powers = {}
    local farCandidates = H.BuildStrikeCandidates()
    local nearGuest = 0
    for _, c in ipairs(farCandidates) do
        if c.kind == 3 then
            local d = math.sqrt(((c.x - 1500) ^ 2) + ((c.z - 950) ^ 2))
            if d >= H.GroundRing[1] - 0.1 and d <= H.GroundRing[2] + 0.1 then nearGuest = nearGuest + 1 end
        end
    end
    check(nearGuest == H.GroundCandidates, "ground candidates should surround the guest's player, got " .. nearGuest)
    H.PlayersProvider = nil
    H.Powers = savedPowers

    -- The host can re-announce on demand (a guest that came up late).
    local sentBefore = #sent
    H.AnnounceState()
    check(#sent == sentBefore + 1 and sent[#sent].op == "VenusState", "AnnounceState sends the state immediately")

    -- Losing every later state message must not freeze the guest: the seeded
    -- timeline carries it, and it still agrees with the host.
    dropStates = true
    local divergent, checks = 0, 0
    for _ = 1, 20 * 60 do
        RunBoth(1.0)
        checks = checks + 1
        if H.GetLevel() ~= G.GetLevel() then divergent = divergent + 1 end
    end
    check(divergent <= checks * 0.03,
        string.format("with state messages lost the guest should hold the host's timeline from its own seed (%d of %d differ)", divergent, checks))

    -- The guest cannot set targets or forced levels of its own.
    local targetBefore = G.GetTargetLevel()
    G.SetTargetLevel(1)
    check(G.GetTargetLevel() == targetBefore, "a guest cannot change the mission's weather target")
    check(G.ForceLevel(5, 30.0) == false, "a guest cannot force a rung")

    -- GetNetState / ApplyNetState round trip on a fresh peer.
    local fresh = NewPeer("fresh", world, { net = true })
    fresh.Environment.Init()
    fresh.Venus.Init({ authority = false, sites = sites, bounds = BOUNDS })
    fresh.Venus.ApplyNetState(H.GetNetState())
    check(fresh.Venus.Seed == H.Seed and near(fresh.Venus.Clock, H.Clock, 0.5), "ApplyNetState adopts the host's seed and clock")
    check(select("#", H.GetNetState()) == 7, "GetNetState returns seven primitives")
    for _, v in ipairs({ H.GetNetState() }) do
        check(type(v) == "number", "net state values are primitives")
    end

    -- Only primitives ever cross the wire.
    for _, m in ipairs(sent) do
        for i = 1, m.n do
            check(type(m.args[i]) == "number", m.op .. " argument " .. i .. " must be a number")
        end
    end

    check(next(damageCalls) == nil, "co-op weather must not damage anything: " .. tostring(damageCalls[1]))
    H.Shutdown(); G.Shutdown(); guestAlone.Venus.Shutdown(); fresh.Venus.Shutdown()
end

-- =============================================================================
-- 8. Offline solo is the host path
-- =============================================================================

do
    local world = NewWorld()
    local solo = NewPeer("solo", world)       -- no IsNetGame: every craft is "local"
    solo.Environment.Init()
    AddObject(world, "sblpow", 900, 40, 900, { building = true })
    solo.Venus.Init({ seed = 31415, sites = sites, bounds = BOUNDS, targetLevel = 4 })
    check(solo.Venus.IsAuthority and solo.Venus.Synced, "offline is the authority and needs no sync")
    solo.run(60.0 * 12.0)
    check(solo.Venus.GetStats().strikes > 0, "offline weather produces strikes")
    check(solo.Venus.NetSend == nil, "offline sends nothing")
    solo.Venus.Shutdown()
end

-- =============================================================================
-- 9. misn08 map data
-- =============================================================================

do
    local sites08 = dofile(scriptDir .. "/CRVenusSites08.lua")
    check(sites08.mission == "misn08", "CRVenusSites08 should describe misn08")
    local world = NewWorld()
    local peer = NewPeer("sites08", world)
    local Map = peer.Map
    local expanded, total = Map.ExpandRuns(sites08.sulfur)
    check(total == 505, "misn08 should have 505 liquid-sulphur cells, got " .. total)
    local pools = Map.ClusterSulfur(expanded, sites08.sulfur, {})
    check(#pools.clusters == 3, "misn08 should have three sulfur pools, got " .. #pools.clusters)
    check(#pools.emitters >= 8, "misn08 should offer sulfur emitter sites, got " .. #pools.emitters)
    local merged = Map.MergeVents(sites08.vents, 45.0)
    check(#merged == 23 and #sites08.vents == 23, "23 misn08 vents stay 23 sites, got " .. #merged)
    check(sites08.bounds.minX < sites08.bounds.maxX and sites08.bounds.minZ < sites08.bounds.maxZ,
        "misn08 has a playable box")

    -- The director accepts the data: host and guest agree on the vent table and the host schedules eruptions.
    peer.Environment.Init()
    AddObject(world, "avtank", 2100, 30, 99800, { owner = "host" })
    peer.Venus.Init({ seed = 8080, authority = true, sites = sites08, startLevel = 1, targetLevel = 4 })
    peer.run(60.0 * 12.0)
    check(#peer.Venus.VentSites == 23, "the director should load all 23 misn08 vents, got " .. #peer.Venus.VentSites)
    check(peer.Venus.GetStats().strikes > 0, "misn08 weather produces strikes in a storm")
    check(CountSystems(peer, "cr_vw_") > 0, "misn08 weather streams in Venus systems")
    peer.Venus.Shutdown()
end

-- =============================================================================
-- 10. misn09 map data
-- =============================================================================

do
    local sites09 = dofile(scriptDir .. "/CRVenusSites09.lua")
    check(sites09.mission == "misn09", "CRVenusSites09 should describe misn09")
    local world = NewWorld()
    local peer = NewPeer("sites09", world)
    local Map = peer.Map
    local expanded, total = Map.ExpandRuns(sites09.sulfur)
    check(total == 179, "misn09 should have 179 liquid-sulphur cells, got " .. total)
    local pools = Map.ClusterSulfur(expanded, sites09.sulfur, {})
    check(#pools.clusters == 1, "misn09 should have one sulfur pool, got " .. #pools.clusters)
    check(#pools.emitters >= 3, "misn09 should offer sulfur emitter sites, got " .. #pools.emitters)
    local merged = Map.MergeVents(sites09.vents, 45.0)
    check(#sites09.vents == 6 and #merged == 6, "6 misn09 geysers stay 6 vent sites, got " .. #merged)
    local labels = {}
    for _, vent in ipairs(sites09.vents) do labels[vent.label or ""] = true end
    check(labels.cut_off_geyser and labels.convoy_geyser, "the two named mission geysers are vent sites")
    check(sites09.bounds.minX < sites09.bounds.maxX and sites09.bounds.minZ < sites09.bounds.maxZ,
        "misn09 has a playable box")

    -- The director accepts the data and the host schedules eruptions at the geysers.
    peer.Environment.Init()
    AddObject(world, "avtank", 2100, 30, 99800, { owner = "host" })
    peer.Venus.Init({ seed = 9090, authority = true, sites = sites09, startLevel = 1, targetLevel = 4 })
    peer.run(60.0 * 12.0)
    check(#peer.Venus.VentSites == 6, "the director should load all 6 misn09 vents, got " .. #peer.Venus.VentSites)
    check(peer.Venus.GetStats().strikes > 0, "misn09 weather produces strikes in a storm")
    check(CountSystems(peer, "cr_vw_") > 0, "misn09 weather streams in Venus systems")
    peer.Venus.Shutdown()
end

-- =============================================================================
-- 11. Fog banks: rare, short, dense sulphur fog moments
-- =============================================================================

do
    local peer_events
    local FOG_CFG = {
        firstDelay = { 150.0, 330.0 }, gap = { 300.0, 660.0 }, total = { 30.0, 75.0 },
        rollIn = { 8.0, 14.0 }, rollOut = { 10.0, 18.0 }, power = { 0.85, 1.0 },
    }

    -- ---- 11a. the pure schedule -------------------------------------------------
    local pure = NewPeer("fogpure", NewWorld())
    local Map = pure.Map

    -- Deterministic: the same seed gives the same banks, a different seed does not.
    do
        local a = Map.NewFogBanks(4242, FOG_CFG):Events(7200.0)
        local b = Map.NewFogBanks(4242, FOG_CFG):Events(7200.0)
        local c = Map.NewFogBanks(4243, FOG_CFG):Events(7200.0)
        local same = #a == #b
        for i = 1, math.min(#a, #b) do
            same = same and a[i].start == b[i].start and a[i].dur == b[i].dur
                and a[i].power == b[i].power and a[i].rollIn == b[i].rollIn
        end
        check(same, "the bank schedule must be identical for one seed")
        check(a[1].start ~= c[1].start, "a different seed should schedule different banks")

        -- Asking in a different order (a peer that joined late, a load) changes nothing.
        local late = Map.NewFogBanks(4242, FOG_CFG)
        late:Active(5000.0)
        late:Active(10.0)
        local lateEvents = late:Events(7200.0)
        check(#lateEvents == #a and lateEvents[3].start == a[3].start, "query order must not change the schedule")
    end

    -- Rarity, duration bounds, gaps: across 300 seeds, over a 30 minute mission.
    do
        local total, maxCount, minCount, coverage = 0, 0, 99, 0.0
        local durOk, rollOk, gapOk, firstOk, powerOk = true, true, true, true, true
        for seed = 1, 300 do
            local events = Map.NewFogBanks(seed * 7919 + 13, FOG_CFG):Events(1800.0)
            local count = 0
            for i, e in ipairs(events) do
                if e.start < 1800.0 then
                    count = count + 1
                    coverage = coverage + math.min(e.dur, 1800.0 - e.start)
                end
                if e.dur < 30.0 - 1e-6 or e.dur > 75.0 + 1e-6 then durOk = false end
                if e.rollIn < 8.0 - 1e-6 or e.rollIn > 14.0 + 1e-6 then rollOk = false end
                if e.rollOut < 10.0 - 1e-6 or e.rollOut > 18.0 + 1e-6 then rollOk = false end
                if e.hold < 4.0 - 1e-6 then rollOk = false end
                if e.power < 0.85 - 1e-6 or e.power > 1.0 + 1e-6 then powerOk = false end
                if i == 1 and (e.start < 150.0 - 1e-6 or e.start > 330.0 + 1e-6) then firstOk = false end
                if i > 1 then
                    local gap = e.start - (events[i - 1].start + events[i - 1].dur)
                    if gap < 300.0 - 1e-6 or gap > 660.0 + 1e-6 then gapOk = false end
                end
            end
            total = total + count
            if count > maxCount then maxCount = count end
            if count < minCount then minCount = count end
        end
        local mean = total / 300.0
        check(durOk, "every bank must last between 30 and 75 seconds")
        check(rollOk, "roll-in / roll-out lengths stay inside their ranges")
        check(powerOk, "bank power stays inside its range")
        check(gapOk, "the gap between banks stays between 300 and 660 seconds")
        check(firstOk, "the first bank never starts before 150 s or after 330 s")
        check(mean >= 2.5 and mean <= 5.0, string.format("a 30 minute mission should see a few banks, mean %.2f", mean))
        check(maxCount <= 6 and minCount >= 1, string.format("bank count per 30 minutes must stay in 1..6, saw %d..%d", minCount, maxCount))
        local share = coverage / (300.0 * 1800.0)
        check(share < 0.14, string.format("fog banks must be rare: %.1f%% of the time", share * 100.0))
    end

    -- Smooth roll-in / roll-out: bounded step at 20 Hz, monotone, 0 outside, 1 on the hold.
    do
        local worstStep, monotone, outsideZero = 0.0, true, true
        for seed = 1, 40 do
            local sched = Map.NewFogBanks(seed * 31 + 7, FOG_CFG)
            local e = sched:Events(10.0)[1]
            local prev = 0.0
            local t = e.start - 5.0
            local peak = 0.0
            while t < e.start + e.dur + 5.0 do
                local v = Map.FogEnvelope(e, t)
                if v < 0.0 or v > 1.0 then monotone = false end
                if (t <= e.start or t >= e.start + e.dur) and v ~= 0.0 then outsideZero = false end
                worstStep = math.max(worstStep, math.abs(v - prev))
                if t < e.start + e.rollIn and v < prev - 1e-9 then monotone = false end
                if t > e.start + e.rollIn + e.hold and v > prev + 1e-9 then monotone = false end
                if v > peak then peak = v end
                prev = v
                t = t + 0.05
            end
            check(peak == 1.0, "the envelope reaches full strength on the hold")
            check(Map.FogEnvelope(e, e.start + e.rollIn + (e.hold * 0.5)) == 1.0, "the hold is flat at 1")
        end
        check(worstStep < 0.011, string.format("roll-in / roll-out must be smooth, worst 50 ms step %.4f", worstStep))
        check(monotone, "the envelope rises through the roll-in and falls through the roll-out, never dips")
        check(outsideZero, "no fog outside a bank's window")
    end

    -- ---- 11b. one peer through a scheduled bank --------------------------------------
    local function Quiet(seed, extra)
        local world = NewWorld()
        local peer = NewPeer("fog" .. tostring(seed), world)
        peer.Environment.Init()
        peer.Environment.FogHorizon = (extra and extra.horizon) or 100.0
        local options = { seed = seed, sites = sites, bounds = BOUNDS, startLevel = 1, targetLevel = 1 }
        for k, v in pairs(extra or {}) do options[k] = v end
        peer.Venus.Init(options)
        peer.world = world
        return peer
    end

    local seedA = 5150
    do
        local peer = Quiet(seedA)
        local V = peer.Venus
        local bank = V.GetFogSchedule(1000.0)[1]
        check(bank ~= nil, "the director exposes its bank schedule")
        peer.run(bank.start - 4.0, 0.1)
        local pre = { fog = peer.rec.fog, sun = peer.rec.sunPower, ambient = peer.rec.ambient }
        check(V.GetFogIntensity() == 0.0 and not V.IsFogBankActive(), "no fog bank before the schedule says so")
        check(CountSystems(peer, "cr_vw_haze") == 0, "no ground haze before the first bank")

        peer.run(4.0 + bank.rollIn + (bank.hold * 0.6), 0.1)
        local at = peer.rec
        check(V.GetFogIntensity() > 0.8, "the bank is at full strength mid-hold, got " .. V.GetFogIntensity())
        check(at.fog.fogEnd <= 100.5, "the bank never pushes fog past the 100 m terrain horizon, end " .. at.fog.fogEnd)
        check(at.fog.fogEnd <= pre.fog.fogEnd + 0.5, "a bank only ever thickens fog, end " .. at.fog.fogEnd .. " vs " .. pre.fog.fogEnd)
        check(at.fog.fogStart <= 12.0, "pea soup starts almost at the camera, start " .. at.fog.fogStart)
        check(at.fog.g > at.fog.r and at.fog.g > at.fog.b * 1.8,
            string.format("bank fog must be sulphur green-yellow (%.2f %.2f %.2f)", at.fog.r, at.fog.g, at.fog.b))
        check(near(at.fog.g, 0.44, 0.06) and near(at.fog.r, 0.40, 0.07), "fog colour should sit near the concept's olive green-yellow")
        check(at.sunPower >= pre.sun - 1e-6, string.format("a bank never dims the sun (%.3f -> %.3f)", pre.sun, at.sunPower))
        check(at.sunPower >= peer.Venus.FogBankSunPower - 0.02, "the sun stays bright inside a bank, got " .. at.sunPower)
        check(at.ambient.g >= pre.ambient.g - 1e-6, "ground light glows ochre rather than dimming")

        local haze = CountSystems(peer, "cr_vw_haze")
        check(haze >= 1 and haze <= V.MaxLiveHaze, "a ground-haze ring streams in around the player, got " .. haze)
        for _, name in ipairs(SystemsOfTemplate(peer, "CR/Venus/FogPool")) do
            local s = peer.rec.systems[name]
            if string.find(name, "cr_vw_haze", 1, true) then
                check(s.rates[0] ~= nil and s.rates[0] > 3.0, "haze systems emit hard at full strength")
            end
        end
        check(TotalSystems(peer) <= V.MaxSystems, "a bank must stay inside the particle budget")

        -- After the bank: the air returns, the haze lingers then goes.
        peer.run((bank.hold * 0.4) + bank.rollOut + 30.0, 0.1)
        check(not V.IsFogBankActive(), "the bank is over")
        check(near(peer.rec.fog.fogEnd, pre.fog.fogEnd, 2.5) and near(peer.rec.fog.fogStart, pre.fog.fogStart, 3.0),
            "fog returns to the rung's values after the bank")
        peer.run(V.FogBankHazeLinger + 5.0, 0.1)
        check(CountSystems(peer, "cr_vw_haze") == 0, "ground haze is released after its linger")
        peer.Venus.Shutdown()
    end

    -- A tighter horizon is honoured; a wider one does not clear the rung's fog.
    do
        local tight = Quiet(seedA, { horizon = 80.0 })
        local bank = tight.Venus.GetFogSchedule(1000.0)[1]
        tight.run(bank.start + bank.rollIn + (bank.hold * 0.6), 0.1)
        check(tight.rec.fog.fogEnd <= 80.5, "the bank is clamped to a short terrain horizon, end " .. tight.rec.fog.fogEnd)
        tight.Venus.Shutdown()

        local wide = Quiet(seedA, { horizon = 130.0 })
        wide.run(bank.start - 4.0, 0.1)
        local pre = wide.rec.fog.fogEnd
        wide.run(4.0 + bank.rollIn + (bank.hold * 0.6), 0.1)
        check(wide.rec.fog.fogEnd <= pre + 0.5, "a bank on a wide map still cannot clear the rung's fog")
        check(wide.rec.fog.fogEnd <= 120.5, "the bank's own fog end (120 m) is respected")
        wide.Venus.Shutdown()
    end

    -- Switched off: nothing happens and nothing can be requested.
    do
        local off = Quiet(seedA, { fogBanks = false })
        local bank = off.Venus.GetFogSchedule(1000.0)[1]
        off.run(bank.start + bank.rollIn + (bank.hold * 0.6), 0.1)
        check(off.Venus.GetFogIntensity() == 0.0, "AllowFogBanks = false removes the banks")
        local ok, why = off.Venus.RequestFogBank({ force = true })
        check(ok == false and why == "disabled", "a disabled director refuses RequestFogBank")
        off.Venus.Shutdown()
    end

    -- ---- 11c. precedence: storms, forced levels, smoothness --------------------------
    do
        -- Forced storm rung: the whole schedule is suppressed (no lightning-peak fog).
        local storm = Quiet(seedA, { startLevel = 5, targetLevel = 5 })
        storm.Venus.ForceLevel(5, 100000.0, 1.0)
        local worst = 0.0
        for _ = 1, 2400 do
            storm.step(0.5)
            worst = math.max(worst, storm.Venus.GetFogIntensity())
        end
        check(worst <= 0.02, "no fog bank during a forced severe storm, saw " .. worst)
        check(select(1, storm.Venus.RequestFogBank()) == false, "a plain request is refused during a forced level")
        storm.Venus.Shutdown()

        -- A natural storm (not forced) suppresses the schedule on its own: while the
        -- ladder sits at the storm rungs a scheduled bank must not show.
        do
            local nat = Quiet(seedA, { targetLevel = 5 })
            -- Pin the seeded ladder on the severe rung without ForceLevel, so only
            -- the natural suppression path is under test.
            nat.Venus.Ladder.timeline[1] = { t = 0.0, dur = 1e9, level = 5, episode = false }
            local sched = nat.Venus.GetFogSchedule(2000.0)
            local overlap, worstInStorm = 0.0, 0.0
            for _ = 1, 2400 do
                nat.step(0.5)
                local V = nat.Venus
                local scheduled = V.FogBanks:Active(V.Clock) ~= nil
                if V.LevelValue >= 4.5 then
                    if scheduled then overlap = overlap + 0.5 end
                    worstInStorm = math.max(worstInStorm, V.GetFogIntensity())
                end
            end
            check(overlap >= 20.0, "the storm test must actually overlap a scheduled bank, overlap " .. overlap)
            check(worstInStorm <= 0.05, "a scheduled bank is suppressed while the ladder sits at storm rungs, saw " .. worstInStorm)
            check(#sched >= 2, "schedule extends over the run")
            nat.Venus.Shutdown()
        end

        -- A forced CALM rung is a set piece too: the schedule stays out of it,
        -- but a script that wants fog can force one explicitly.
        local calm = Quiet(seedA)
        calm.Venus.ForceLevel(1, 100000.0, 1.0)
        local calmWorst = 0.0
        for _ = 1, 1200 do
            calm.step(0.5)
            calmWorst = math.max(calmWorst, calm.Venus.GetFogIntensity())
        end
        check(calmWorst <= 0.02, "a ForceLevel set piece is not interrupted by the schedule, saw " .. calmWorst)
        local ok, id = calm.Venus.RequestFogBank({ force = true, seconds = 40.0 })
        check(ok == true, "a script may force a bank inside a set piece")
        calm.run(25.0, 0.1)
        check(calm.Venus.GetFogIntensity() > 0.8, "the forced bank shows inside the set piece")
        calm.Venus.Shutdown()

        -- An episode / storm that arrives mid-bank eases it away, smoothly.
        local mid = Quiet(seedA)
        local bank = mid.Venus.GetFogSchedule(1000.0)[1]
        mid.run(bank.start + bank.rollIn + 2.0, 0.1)
        check(mid.Venus.GetFogIntensity() > 0.8, "mid-bank sanity")
        mid.Venus.ForceLevel(5, 600.0, 1.0)
        local prev, worstStep = mid.Venus.GetFogIntensity(), 0.0
        for _ = 1, 30 * 20 do
            mid.step(1.0 / 30.0)
            local v = mid.Venus.GetFogIntensity()
            worstStep = math.max(worstStep, math.abs(v - prev))
            prev = v
        end
        check(prev < 0.05, "a bank gives way to a forced storm, still " .. prev)
        check(worstStep < 0.01, string.format("the bank eases away, not cuts: worst frame step %.4f", worstStep))
        mid.Venus.Shutdown()

        -- Per-frame smoothness of the whole director output across a full natural bank.
        local smooth = Quiet(seedA)
        local sb = smooth.Venus.GetFogSchedule(1000.0)[1]
        smooth.run(sb.start - 5.0, 0.1)
        local last, steps = smooth.Venus.GetFogIntensity(), 0.0
        for _ = 1, math.floor((sb.dur + 10.0) * 30.0) do
            smooth.step(1.0 / 30.0)
            local v = smooth.Venus.GetFogIntensity()
            steps = math.max(steps, math.abs(v - last))
            last = v
        end
        check(steps < 0.008, string.format("intensity is smooth at 30 fps, worst step %.4f", steps))
        smooth.Venus.Shutdown()
    end

    -- ---- 11d. no gameplay side effects ----------------------------------------------
    -- Same seed and mission, with and without banks: identical rungs, strikes and
    -- sensor scales, and nothing damaged, moved or ordered.
    do
        local function Run(fogBanks)
            local peer = Quiet(777, { fogBanks = fogBanks, targetLevel = 3 })
            local tank = AddObject(peer.world, "avtank", 500, 12, 520, { owner = "fog777" })
            local rungs, radar = {}, {}
            for i = 1, 1200 do
                peer.step(1.0)
                rungs[i] = peer.Venus.GetLevel()
                radar[i] = peer.rec.radarRange[tank] or -1
            end
            local out = { rungs = rungs, radar = radar, strikes = peer.Venus.GetStats().strikes, peer = peer }
            return out
        end
        local with, without = Run(true), Run(false)
        local same = true
        for i = 1, #with.rungs do
            if with.rungs[i] ~= without.rungs[i] or with.radar[i] ~= without.radar[i] then same = false end
        end
        check(same, "fog banks must not change the ladder or any sensor scale")
        check(with.strikes == without.strikes, "fog banks must not change the strike schedule")
        check(next(damageCalls) == nil, "fog banks must call nothing that damages: " .. tostring(damageCalls[1]))
        with.peer.Venus.Shutdown()
        without.peer.Venus.Shutdown()

        -- The module's gameplay modifier never mentions fog.
        local g = io.open(scriptDir .. "/CRVenusWeather.lua", "rb")
        local text = g:read("*a")
        g:close()
        local body = text:match("local function GameplayContribution.-\nend") or ""
        check(not body:lower():find("fog", 1, true), "GameplayContribution must not read fog state")
    end

    -- ---- 11e. co-op: peer-identical banks, one small event for a requested one --------
    do
        local world = NewWorld()
        local hostPeer = NewPeer("host", world, { net = true })
        local guestPeer = NewPeer("guest", world, { net = true })
        local H, G = hostPeer.Venus, guestPeer.Venus
        AddObject(world, "avtank", 520, 12, 520, { owner = "host" })
        AddObject(world, "avtank", 540, 12, 530, { owner = "guest" })

        local queue, sent = {}, {}
        local function HostSend(op, ...)
            sent[#sent + 1] = { op = op, n = select("#", ...), args = { ... } }
            queue[#queue + 1] = { at = hostPeer.now + 0.12, op = op, args = { ... }, n = select("#", ...) }
        end
        hostPeer.Environment.Init(); guestPeer.Environment.Init()
        hostPeer.Environment.FogHorizon = 100.0; guestPeer.Environment.FogHorizon = 100.0
        H.Init({ seed = seedA, authority = true, send = HostSend, sites = sites, bounds = BOUNDS, startLevel = 1, targetLevel = 1 })
        G.Init({ authority = false, sites = sites, bounds = BOUNDS, startLevel = 1, targetLevel = 1 })

        local function Pump()
            local keep = {}
            for i = 1, #queue do
                local m = queue[i]
                if guestPeer.now >= m.at then G.ApplyNetEvent(m.op, unpack(m.args, 1, m.n)) else keep[#keep + 1] = m end
            end
            queue = keep
        end
        local hostDt, guestDt = 1.0 / 30.0, 1.0 / 47.0
        local wall, hostNext, guestNext = 0.0, hostDt, guestDt
        local function RunBoth(seconds)
            local target = wall + seconds
            while true do
                local nextFrame = math.min(hostNext, guestNext)
                if nextFrame > target then break end
                wall = nextFrame
                if hostNext <= guestNext then hostPeer.step(hostDt); hostNext = hostNext + hostDt
                else guestPeer.step(guestDt); guestNext = guestNext + guestDt end
                Pump()
            end
            wall = target
        end

        RunBoth(2.0)
        check(G.Synced, "guest synced for the fog test")
        local bank = H.GetFogSchedule(1000.0)[1]
        local gbank = G.GetFogSchedule(1000.0)[1]
        check(bank.start == gbank.start and bank.dur == gbank.dur and bank.power == gbank.power,
            "host and guest derive the same scheduled bank from the seed")

        -- Through the natural bank the two peers agree frame by frame (within link skew).
        RunBoth(bank.start - 4.0 - wall)
        local worst, peakSeen = 0.0, 0.0
        while wall < bank.start + bank.dur + 6.0 do
            RunBoth(0.5)
            worst = math.max(worst, math.abs(H.GetFogIntensity() - G.GetFogIntensity()))
            peakSeen = math.max(peakSeen, G.GetFogIntensity())
        end
        check(peakSeen > 0.8, "the guest sees the scheduled bank too")
        check(worst < 0.06, string.format("host and guest fog intensity agree through a bank, worst %.3f", worst))
        local fogEvents = 0
        for _, m in ipairs(sent) do if m.op == "VenusFog" then fogEvents = fogEvents + 1 end end
        check(fogEvents == 0, "a scheduled bank costs no traffic at all")

        -- A requested bank is ONE small all-numbers event, applied once.
        RunBoth(60.0)
        local ok, id = H.RequestFogBank({ seconds = 50.0, reason = "test" })
        check(ok == true, "the host can request a bank")
        local ev
        for _, m in ipairs(sent) do if m.op == "VenusFog" then ev = m end end
        check(ev ~= nil and ev.n == 6, "a requested bank rides one six-number event")
        local numeric = true
        for i = 1, ev.n do if type(ev.args[i]) ~= "number" then numeric = false end end
        check(numeric, "the fog event carries numbers only")
        check(select(1, G.RequestFogBank()) == false, "a guest cannot request a bank")
        RunBoth(30.0)
        worst = 0.0
        peakSeen = 0.0
        for _ = 1, 40 do
            RunBoth(1.0)
            worst = math.max(worst, math.abs(H.GetFogIntensity() - G.GetFogIntensity()))
            peakSeen = math.max(peakSeen, G.GetFogIntensity())
        end
        check(peakSeen > 0.7, "the guest renders the host's requested bank")
        check(worst < 0.08, string.format("requested bank agrees on both peers, worst %.3f", worst))
        local before = #G.FogRequests
        G.ApplyNetEvent("VenusFog", unpack(ev.args, 1, ev.n))
        check(#G.FogRequests == before, "a duplicate fog event is ignored")
        check(next(damageCalls) == nil, "co-op fog damages nothing")
        H.Shutdown(); G.Shutdown()
    end

    -- ---- 11f. the drama hook ---------------------------------------------------------
    do
        -- A seed whose first scheduled bank is late enough to leave room for a
        -- drama bank before it.
        local seedLate
        for seed = 100, 5000 do
            local e = Map.NewFogBanks(seed, FOG_CFG):Events(10.0)[1]
            if e.start >= 305.0 then seedLate = seed; break end
        end
        check(seedLate ~= nil, "found a seed with a late first bank")

        local moveCalls = {}
        local function Scenario(label)
            local peer
            peer = Quiet(seedLate, { targetLevel = 1, send = function(op, ...)
                if op == "VenusFog" then
                    peer_events = peer_events or {}
                    peer_events[#peer_events + 1] = { clock = peer.Venus.Clock, args = { ... }, n = select("#", ...) }
                end
            end })
            peer.env.GetTeamNum = function(h)
                if h == 1 then return 1 end
                local o = peer.world.objects[h]
                return o and o.team or 0
            end
            peer.env.IsAlly = function(a, b)
                return peer.env.GetTeamNum(a) == peer.env.GetTeamNum(b)
            end
            for _, fn in ipairs({ "Goto", "Attack", "Follow", "Retreat", "Defend", "Stop", "SetCommand",
                                  "SetPosition", "SetTeamNum", "SetTransform" }) do
                peer.env[fn] = function() moveCalls[#moveCalls + 1] = label .. ":" .. fn end
            end
            return peer
        end

        local function AddHostile(peer, odf, x, z, team)
            local h = AddObject(peer.world, odf, x, 12, z, { owner = "fog" })
            peer.world.objects[h].team = team or 5
            return h
        end

        -- Drives units for `seconds`: each object moves by (dx, dz) per second.
        local function Drive(peer, movers, seconds)
            local steps = math.floor(seconds / 0.5)
            for _ = 1, steps do
                for h, m in pairs(movers) do
                    local o = peer.world.objects[h]
                    o.x = o.x + m.dx * 0.5
                    o.z = o.z + m.dz * 0.5
                end
                peer.run(0.5, 0.1)
            end
        end

        -- 1. A walker closing on the human from 380 m triggers a bank, early.
        do
            peer_events = nil
            local peer = Scenario("walker")
            local V = peer.Venus
            local walker = AddHostile(peer, "svwalk", 500 + 380, 500)
            peer.run(95.0, 0.1)
            check(not V.IsFogBankActive(), "no fog before anything approaches")
            local startX = peer.world.objects[walker].x
            Drive(peer, { [walker] = { dx = -5.0, dz = 0.0 } }, 40.0)
            local count, info = V.GetDramaStats()
            check(count == 1 and info ~= nil and info.walkers >= 1, "a closing walker makes the host choose a fog bank")
            check(peer_events ~= nil and #peer_events == 1 and peer_events[1].n == 6, "the choice is one small event")
            check(peer_events[1].clock >= 95.0 and peer_events[1].clock < 140.0, "the bank starts while the walker is still far")
            check(V.FogLastActiveAt > 95.0, "the drama bank actually rolled in")
            -- Timing only: the walker moved exactly as the test moved it.
            check(near(peer.world.objects[walker].x, startX - (5.0 * 40.0), 1e-6), "the hook never moves a unit")
            check(peer.world.objects[walker].velocityWrites == nil, "the hook never pushes a unit")
            check(#moveCalls == 0, "the hook issues no order: " .. tostring(moveCalls[1]))

            peer.Venus.Shutdown()
        end

        -- 2. Things that must not trigger it.
        do
            local function Quiet2(label, build, forced)
                peer_events = nil
                local peer = Scenario(label)
                local movers = build(peer)
                if forced then peer.Venus.ForceLevel(forced, 100000.0, 1.0) end
                peer.run(95.0, 0.1)
                Drive(peer, movers, 60.0)
                local n = peer_events and #peer_events or 0
                peer.Venus.Shutdown()
                return n
            end
            check(Quiet2("stationary", function(p)
                AddHostile(p, "svwalk", 750, 500); return {} end) == 0, "a parked walker does not trigger a bank")
            check(Quiet2("receding", function(p)
                local h = AddHostile(p, "svwalk", 700, 500); return { [h] = { dx = 5.0, dz = 0.0 } } end) == 0,
                "a retreating walker does not trigger a bank")
            check(Quiet2("friendly", function(p)
                local h = AddHostile(p, "avwalk", 880, 500, 1); return { [h] = { dx = -5.0, dz = 0.0 } } end) == 0,
                "a friendly walker never triggers a bank")
            check(Quiet2("neutral", function(p)
                local h = AddHostile(p, "svwalk", 880, 500, 0); return { [h] = { dx = -5.0, dz = 0.0 } } end) == 0,
                "a neutral walker never triggers a bank")
            check(Quiet2("single", function(p)
                local h = AddHostile(p, "svtank", 880, 500); return { [h] = { dx = -5.0, dz = 0.0 } } end) == 0,
                "one ordinary tank is not a group")
            check(Quiet2("storm", function(p)
                local h = AddHostile(p, "svwalk", 880, 500); return { [h] = { dx = -5.0, dz = 0.0 } } end, 5) == 0,
                "no drama bank is requested during a forced storm")
            check(Quiet2("far", function(p)
                local h = AddHostile(p, "svwalk", 1500, 500); return { [h] = { dx = -2.0, dz = 0.0 } } end) == 0,
                "a walker outside the drama range does not trigger a bank")
        end

        -- 3. A hostile GROUP counts; the same group parked does not.
        do
            peer_events = nil
            local peer = Scenario("group")
            local movers = {}
            for i = 1, 4 do movers[AddHostile(peer, "svtank", 860 + (i * 6), 500 + (i * 8))] = { dx = -5.0, dz = 0.0 } end
            peer.run(95.0, 0.1)
            Drive(peer, movers, 40.0)
            check(peer.Venus.GetDramaStats() == 1, "four hostile craft closing on a human count as a group")
            peer.Venus.Shutdown()
        end

        -- 4. Cooldown, mission cap, and clearance from the scheduled bank.
        do
            peer_events = nil
            local peer = Scenario("cap")
            local V = peer.Venus
            -- Six walkers that keep closing: re-seeded every 20 s for 40 minutes.
            local movers = {}
            for i = 1, 6 do movers[AddHostile(peer, "svwalk", 880, 500 + i)] = { dx = -5.0, dz = 0.0 } end
            for _ = 1, 120 do
                for h in pairs(movers) do peer.world.objects[h].x = 880 end
                Drive(peer, movers, 20.0)
            end
            local starts = {}
            for _, e in ipairs(peer_events or {}) do starts[#starts + 1] = e end
            check(#starts <= V.DramaMaxPerMission, "drama banks per mission are capped, saw " .. #starts)
            for i = 2, #starts do
                local prevEnd = starts[i - 1].clock + starts[i - 1].args[2] + starts[i - 1].args[3] + starts[i - 1].args[4]
                check(starts[i].clock - prevEnd >= V.DramaCooldown - 1.0, "drama banks respect the cooldown")
            end
            -- Never overlapping a scheduled bank (peers all share the schedule).
            local sched = V.GetFogSchedule(4000.0)
            for _, ev in ipairs(starts) do
                local total = ev.args[2] + ev.args[3] + ev.args[4]
                for _, e in ipairs(sched) do
                    local overlaps = ev.clock < (e.start + e.dur) and (ev.clock + total) > e.start
                    check(not overlaps, "a drama bank never stacks on a scheduled one")
                end
            end
            peer.Venus.Shutdown()
        end

        check(next(damageCalls) == nil, "the drama hook damages nothing")
    end

    -- ---- 11g. save / load keeps a requested bank -----------------------------------------
    do
        local peer = Quiet(seedA)
        peer.run(30.0, 0.1)
        local ok = peer.Venus.RequestFogBank({ seconds = 60.0, force = true })
        peer.run(20.0, 0.1)
        local state = peer.Venus.Save()
        local before = peer.Venus.GetFogIntensity()
        local again = Quiet(seedA)
        again.Venus.Load(state)
        again.run(0.5, 0.1)
        check(ok and #state.fogRequests == 1, "a requested bank is part of the save")
        check(near(again.Venus.GetFogIntensity(), before, 0.1), "a loaded game resumes the bank where it was")
        peer.Venus.Shutdown(); again.Venus.Shutdown()
    end
end

-- =============================================================================
-- Report
-- =============================================================================

if #failures > 0 then
    for _, message in ipairs(failures) do print("FAIL: " .. message) end
    print(string.format("%d expectation(s) failed", #failures))
    os.exit(1)
end

print("VENUS WEATHER OK")
