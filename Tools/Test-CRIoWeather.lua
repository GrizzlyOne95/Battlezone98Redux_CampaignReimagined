-- Test-CRIoWeather.lua
--
-- Drives the real CRVenusMap (shared pure half), CRIoWeather, CRWeather,
-- CRWeatherPresets and Environment modules against a stubbed exu and a stubbed
-- BZ Lua runtime. No game, no Ogre.
--
-- Usage, from the repository root:
--
--     lua Tools/Test-CRIoWeather.lua Scripts
--
-- Every "peer" below is a fully isolated Lua environment with its own copy of
-- every module and its own globals, which is what a second machine is. Peers
-- share only a World table (the craft that exist) and the messages one sends
-- the other.
--
-- Prints IO WEATHER OK on success; prints each failed expectation and exits 1
-- otherwise.

-- The engine returns VECTOR_3D userdata (not tables) from GetPosition, GetVelocity,
-- GetTerrainHeightAndNormal normals, etc. Mocks must do the same or a
-- type(p) == "table" gate passes here and silently fails in game.
local function UD(t)
    if t == nil then return nil end
    local u = newproxy(true)
    getmetatable(u).__index = function(_, k) return t[k] end
    return u
end

local scriptDir = ... or "Scripts"

local failures = {}
local function check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

local function near(a, b, tolerance)
    return math.abs(a - b) <= tolerance
end

local assertions = 0
local rawCheck = check
check = function(condition, message)
    assertions = assertions + 1
    rawCheck(condition, message)
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
    }
    world.order[#world.order + 1] = h
    return h
end

local sites = dofile(scriptDir .. "/CRIoSites10.lua")
local BOUNDS = sites.bounds

-- Synthetic terrain over misn10's real playable box: a flat shelf at 40, one
-- enclosed pit, one ridge, and a very low apron outside the box that must never
-- be mistaken for a basin.
local PIT = { x = 2200.0, z = 99600.0 }
local HILL = { x = 3300.0, z = 100300.0 }

local function SyntheticHeight(x, z)
    if x < BOUNDS.minX or x > BOUNDS.maxX or z < BOUNDS.minZ or z > BOUNDS.maxZ then
        return -80.0
    end
    local h = 40.0
    local pit = math.sqrt(((x - PIT.x) ^ 2) + ((z - PIT.z) ^ 2))
    if pit < 260.0 then h = h - (30.0 * (1.0 - (pit / 260.0))) end
    local hill = math.sqrt(((x - HILL.x) ^ 2) + ((z - HILL.z) ^ 2))
    if hill < 300.0 then h = h + (60.0 * (1.0 - (hill / 300.0))) end
    return h
end

-- Anything that could hurt, move, create or remove something. The Io director
-- must call none of it.
local forbiddenCalls = {}
local FORBIDDEN = {
    "Damage", "SetCurHealth", "AddHealth", "SetMaxHealth", "SetCurAmmo", "AddAmmo", "SetMaxAmmo",
    "MakeExplosion", "RemoveObject", "SetCurPilot", "Kill", "BuildObject", "SetVelocity", "SetOmega",
    "SetPosition", "SetTransform", "Stop", "Goto", "Attack", "SetCommand", "SetTeamNum", "SetLifespan",
    "Handle", "SetIndependence", "SetAvoidType",
}

local function NewPeer(name, world, options)
    options = options or {}
    local peer = {
        name = name, now = 0.0, world = world, loaded = {}, preload = {},
        playerPos = { x = 2000.0, y = 40.0, z = 99000.0 },
        sounds = {}, log = {}, quakeCalls = {},
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
    exu.GetFog = function() return { r = 0.5, g = 0.4, b = 0.2, fogStart = 175, fogEnd = 250 } end
    exu.SetFog = function(r, g, b, s, e) rec.fog = { r = r, g = g, b = b, fogStart = s, fogEnd = e } return true end
    exu.GetAmbientLight = function() return { r = 0.1, g = 0.1, b = 0.1 } end
    exu.SetAmbientLight = function(r, g, b) rec.ambient = { r = r, g = g, b = b } return true end
    exu.GetSunDiffuse = function() return { r = 0.6, g = 0.6, b = 0.6 } end
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
    exu.SetGravity = function() forbiddenCalls[#forbiddenCalls + 1] = name .. ":exu.SetGravity" end

    local STOCK_RANGE, STOCK_PERIOD, STOCK_JAM = 400.0, 1.0, 10.0
    exu.GetRadarRange = function(h) return rec.radarRange[h] or STOCK_RANGE end
    exu.SetRadarRange = function(h, v) rec.radarRange[h] = v return true end
    exu.GetRadarPeriod = function(h) return rec.radarPeriod[h] or STOCK_PERIOD end
    exu.SetRadarPeriod = function(h, v) rec.radarPeriod[h] = v return true end
    exu.GetVelocJam = function(h) return rec.velocJam[h] or STOCK_JAM end
    exu.SetVelocJam = function(h, v) rec.velocJam[h] = v return true end

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
    exu.AttachParticleSystemToCamera = function(sysName, offset)
        if rec.systems[sysName] then rec.systems[sysName].camera = offset end
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
        EnsureExtra = function(extra)
            if options.noIoTemplates then return false, "stub" end
            peer.extraRequested = extra
            return true, "stub"
        end,
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
        if h == 1 then return UD(peer.playerPos) end
        local o = world.objects[h]
        if o then return UD({ x = o.x, y = o.y, z = o.z }) end
        return nil
    end
    env.GetVelocity = function(h)
        local o = world.objects[h]
        return UD(o and { x = o.vx, y = o.vy, z = o.vz } or { x = 0, y = 0, z = 0 })
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
        return SyntheticHeight(v.x, v.z), UD({ x = 0, y = 1, z = 0 })
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
    for _, fn in ipairs(FORBIDDEN) do
        env[fn] = function(...)
            forbiddenCalls[#forbiddenCalls + 1] = name .. ":" .. fn
        end
    end

    -- The stock earthquake natives (Docs/BZR_LUA_AGENT_REFERENCE.md). Recorded so
    -- a test can see exactly what the engine would have been told, and when.
    env.StartEarthquake = function(m) peer.quakeCalls[#peer.quakeCalls + 1] = { t = peer.now, op = "start", mag = m } end
    env.UpdateEarthQuake = function(m) peer.quakeCalls[#peer.quakeCalls + 1] = { t = peer.now, op = "update", mag = m } end
    env.StopEarthquake = function() peer.quakeCalls[#peer.quakeCalls + 1] = { t = peer.now, op = "stop" } end

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
    peer.Presets = load("CRWeatherPresets")
    peer.Io = load("CRIoWeather")
    peer.Map = load("CRVenusMap")
    peer.Environment.EnableVisualRuntime = false

    function peer.step(dt)
        peer.now = peer.now + dt
        peer.Io.Update(dt)
        peer.Environment.Update(dt)
    end

    function peer.run(seconds, dt)
        dt = dt or (1.0 / 30.0)
        local steps = math.floor(seconds / dt)
        for _ = 1, steps do peer.step(dt) end
    end

    function peer.calls(op)
        local list = {}
        for _, c in ipairs(peer.quakeCalls) do if c.op == op then list[#list + 1] = c end end
        return list
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

local function SystemsOfTemplate(peer, template)
    local list = {}
    for sysName, s in pairs(peer.rec.systems) do
        if s.template == template then list[#list + 1] = sysName end
    end
    table.sort(list)
    return list
end

local function NoForbidden(label)
    check(next(forbiddenCalls) == nil, label .. ": a damaging / moving / spawning function was called: " .. tostring(forbiddenCalls[1]))
end

-- Cosmetic means the sensors are Environment's own business: the global
-- gameplay scales stay at identity, no per-craft scramble exists, and no
-- gameplay modifier is registered. (Environment's own night pass may rewrite a
-- craft's sensors; that is not this module's doing, so the values are not
-- compared.)
local function SensorsUntouched(peer)
    local env = peer.Environment
    local scales = env.GameplayScales
    if scales.radarRange ~= 1.0 or scales.radarPeriod ~= 1.0 or scales.velocJam ~= 1.0 then return false end
    if next(env.ObjectScrambles) ~= nil then return false end
    if env.GameplayModifiers["CRIoWeather"] ~= nil then return false end
    return true
end

local function Dist2(ax, az, bx, bz)
    return math.sqrt(((ax - bx) ^ 2) + ((az - bz) ^ 2))
end

-- =============================================================================
-- 1. misn10 map data (CRIoSites10, generated by Tools/Build-IoSites.py)
-- =============================================================================

local Probe = NewPeer("probe", NewWorld())
local Map = Probe.Map
local lavaCells, lavaTotal = Map.ExpandRuns(sites.lava)

do
    check(sites.mission == "misn10", "CRIoSites10 should describe misn10")
    check(sites.materialLabels[0] == "Lava" and sites.materialLabels[1] == "Lava Pool"
        and sites.materialLabels[3] == "Sulphur Deposits" and sites.materialLabels[4] == "Hardened Lava",
        "the TextureType labels are the ones lava classification was based on")
    check(#sites.lava.types == 1 and sites.lava.types[1] == 1,
        "only TextureType 1 (Lava Pool) marks a place; type 0 is 58% of the map")
    check(sites.lava.cols == 256 and sites.lava.rows == 256 and sites.lava.cell == 20, "misn10 mat is 256x256 cells of 20 units")
    check(sites.bounds.minX < sites.bounds.maxX and sites.bounds.minZ < sites.bounds.maxZ, "a playable box exists")

    local solid, transition = 0, 0
    for _, w in pairs(lavaCells) do
        if w >= 1.0 then solid = solid + 1 else transition = transition + 1 end
    end
    check(solid == 18944 and sites.lava.solidCells == 18944, "misn10 has 18,944 molten Lava Pool cells, got " .. solid)
    check(transition == 1272, "misn10 has 1,272 Lava->Lava Pool transition cells, got " .. transition)
    check(lavaTotal == solid + transition, "ExpandRuns agrees with the census")

    -- Vents: 21 eggeizr1 objects; the seven named geyser<N> are the relic sites.
    check(#sites.vents == 21, "misn10 has 21 eggeizr1 geysers, got " .. #sites.vents)
    local major = 0
    for _, v in ipairs(sites.vents) do
        if v.major then
            major = major + 1
            check(string.match(v.label, "^geyser%d$") ~= nil, "only geyser<N> are major, saw " .. v.label)
        end
        check(v.x >= sites.bounds.minX and v.x <= sites.bounds.maxX and v.z >= sites.bounds.minZ and v.z <= sites.bounds.maxZ,
            v.label .. " lies inside the playable box")
    end
    check(major == 7, "seven geysers are major, got " .. major)
    local merged = Map.MergeVents(sites.vents, 45.0)
    check(#merged == 21, "no misn10 geysers sit within 45 units of each other, got " .. #merged)

    -- Orientation: the stock geysers stand on Sulphur Deposits tiles, never in
    -- the molten pool. A flipped or swapped .mat would put several in the lava.
    local inLava = 0
    for _, v in ipairs(sites.vents) do
        local col = math.floor((v.x - sites.lava.originX) / sites.lava.cell)
        local row = math.floor((v.z - sites.lava.originZ) / sites.lava.cell)
        if (lavaCells[(row * sites.lava.cols) + col] or 0) >= 1.0 then inLava = inLava + 1 end
    end
    check(inLava <= 2, "geysers do not stand in molten lava under the generator's orientation, saw " .. inLava)

    -- Lava pool anchors.
    local pools = sites.lava.pools
    check(#pools >= 150, "the molten expanses should carry plenty of fog anchors, got " .. #pools)
    local clusterIds = {}
    for _, k in ipairs(sites.lava.clusters) do clusterIds[k.id] = true end
    local minSpacing, onLava, outside, weights = 1e9, 0, 0, true
    local seen = {}
    for i, p in ipairs(pools) do
        local col = math.floor((p.x - sites.lava.originX) / sites.lava.cell)
        local row = math.floor((p.z - sites.lava.originZ) / sites.lava.cell)
        if (lavaCells[(row * sites.lava.cols) + col] or 0) >= 1.0 then onLava = onLava + 1 end
        if p.x < sites.bounds.minX or p.x > sites.bounds.maxX or p.z < sites.bounds.minZ or p.z > sites.bounds.maxZ then
            outside = outside + 1
        end
        if p.weight < 0.55 - 1e-6 or p.weight > 1.0 + 1e-6 then weights = false end
        check(p.cluster == 0 or clusterIds[p.cluster], "pool " .. i .. " names a real cluster")
        local key = p.x .. ":" .. p.z
        check(not seen[key], "pool " .. i .. " is not a duplicate")
        seen[key] = true
        for j = i + 1, math.min(#pools, i + 400) do
            minSpacing = math.min(minSpacing, Dist2(p.x, p.z, pools[j].x, pools[j].z))
        end
    end
    check(onLava == #pools, string.format("every pool anchor sits on a molten tile (%d of %d)", onLava, #pools))
    check(outside == 0, "no pool anchor lies outside the playable box, saw " .. outside)
    check(weights, "pool weights are the local lava fraction, 0.55 .. 1")
    check(minSpacing >= 109.9, string.format("pools are kept at least 110 units apart, closest %.1f", minSpacing))

    -- Coverage: most molten ground inside the box is near an anchor, so the
    -- streamed pools actually carpet the lava rather than leave bare patches.
    local covered, sampled = 0, 0
    for key, w in pairs(lavaCells) do
        if w >= 1.0 then
            local row = math.floor(key / sites.lava.cols)
            local col = key - (row * sites.lava.cols)
            if (row + col) % 7 == 0 then
                local x = sites.lava.originX + ((col + 0.5) * sites.lava.cell)
                local z = sites.lava.originZ + ((row + 0.5) * sites.lava.cell)
                if x >= sites.bounds.minX and x <= sites.bounds.maxX and z >= sites.bounds.minZ and z <= sites.bounds.maxZ then
                    sampled = sampled + 1
                    for _, p in ipairs(pools) do
                        if math.abs(p.x - x) < 130 and math.abs(p.z - z) < 130 and Dist2(p.x, p.z, x, z) < 130 then
                            covered = covered + 1
                            break
                        end
                    end
                end
            end
        end
    end
    check(sampled > 500 and covered >= sampled * 0.97,
        string.format("lava pool anchors should cover most molten ground: %d of %d samples", covered, sampled))
end

-- =============================================================================
-- 2. Presets: a sulphur-amber ladder, no lightning, nothing else
-- =============================================================================

do
    local peer = NewPeer("presets", NewWorld())
    peer.Environment.Init()
    peer.Io.Init({ seed = 5, sites = sites, bounds = BOUNDS })
    local names = peer.Io.GetPresetNames()
    check(#names == 5, "five Io presets")
    local lastSun, lastEnd, lastRed = 2.0, 1e9, 0.0
    for i, presetName in ipairs(names) do
        local preset = peer.Presets.Get(presetName)
        check(preset ~= nil, presetName .. " is registered in CRWeatherPresets")
        check(preset.name == presetName, presetName .. " names itself")
        check(preset.lightning == nil, presetName .. " carries no lightning")
        check(preset.sky == nil, presetName .. " leaves the Jupiter sky alone")
        check(peer.Io.Levels[i].preset == presetName, "ladder rung " .. i .. " selects " .. presetName)
        check(preset.fog.fogEnd <= 250.0, presetName .. " fog ends inside misn10's 250 horizon")
        check(preset.fog.fogStart < preset.fog.fogEnd, presetName .. " fog start under end")
        check(preset.sunPowerScale < lastSun, presetName .. " is dimmer than the rung below")
        check(preset.fog.fogEnd <= lastEnd, presetName .. " is no clearer than the rung below")
        local redness = preset.fog.r / math.max(0.001, preset.fog.g)
        check(redness >= lastRed - 1e-6, presetName .. " is no less red than the rung below")
        -- Sulphur haze under Jupiter light: warm, red >= green >= blue everywhere.
        for _, key in ipairs({ "fog", "ambient", "diffuse" }) do
            local c = preset[key]
            check(c.r >= c.g and c.g >= c.b, presetName .. "." .. key .. " is a warm sulphur / ember colour")
        end
        lastSun, lastEnd, lastRed = preset.sunPowerScale, preset.fog.fogEnd, redness
        check(#preset.precipitation >= 1 and preset.precipitation[1].template == "CR/Weather/MarsHaze",
            presetName .. " carries the sulphur haze layer")
        for _, layer in ipairs(preset.precipitation) do
            check(string.find(layer.system, "cr_wx_io_", 1, true) == 1, "Io layers use cr_wx_io_ system names")
        end
    end
    check(peer.CRWeather.GetPreset() == "IoCalm", "opens on IoCalm, got " .. tostring(peer.CRWeather.GetPreset()))
    check(peer.extraRequested == "cr_io", "the director loads the cr_io particle payload through EnsureExtra")
    -- Idempotent: a second registration adds nothing.
    check(peer.Io.RegisterPresets() == 0, "registering the presets twice adds nothing")
    peer.Io.Shutdown()
end

-- =============================================================================
-- 3. Ladder: determinism, one rung at a time, beats
-- =============================================================================

local function LevelTrace(seed, target, seconds, forceAt)
    local peer = NewPeer("trace", NewWorld())
    peer.Environment.Init()
    peer.Io.Init({ seed = seed, sites = sites, bounds = BOUNDS, targetLevel = target })
    local trace, episodes = {}, 0
    for s = 1, seconds do
        if forceAt and s == forceAt then peer.Io.ForceLevel(5, 40.0, 5.0) end
        peer.run(1.0)
        trace[#trace + 1] = peer.Io.GetLevel()
        if peer.Io.IsEpisode() then episodes = episodes + 1 end
    end
    peer.Io.Shutdown()
    return trace, episodes
end

do
    local a, ea = LevelTrace(7001, 4, 1800)
    local b = LevelTrace(7001, 4, 1800)
    local c = LevelTrace(7002, 4, 1800)
    local identical, differs, maxJump, maxLevel = true, false, 0, 0
    for i = 1, #a do
        if a[i] ~= b[i] then identical = false end
        if a[i] ~= c[i] then differs = true end
        if i > 1 then maxJump = math.max(maxJump, math.abs(a[i] - a[i - 1])) end
        maxLevel = math.max(maxLevel, a[i])
    end
    check(identical, "the same seed gives the same ladder")
    check(differs, "different seeds give different ladders")
    check(maxJump <= 1, "the Io ladder moves one rung at a time, saw " .. maxJump)
    check(maxLevel >= 4, "a target of 4 reaches the intense rungs, peak " .. maxLevel)
    check(ea >= 0, "episodes are counted")

    -- A mission beat: ForceLevel pins the rung, then releases.
    local forced = LevelTrace(7003, 2, 200, 60)
    check(forced[70] == 5, "ForceLevel(5, 40, 5) pins the paroxysm rung, got " .. tostring(forced[70]))
    check(forced[150] < 5 or forced[150] <= 3, "the forced rung lapses after its time, got " .. tostring(forced[150]))
end

-- =============================================================================
-- 4. Director on one peer: lava, vents, ash, light
-- =============================================================================

local LavaPool = sites.lava.pools[1]
for _, p in ipairs(sites.lava.pools) do
    -- A pool well inside the box, so streaming has neighbours on every side.
    if p.x > 2000 and p.x < 3000 and p.z > 99300 and p.z < 100300 and p.weight >= 1.0 then LavaPool = p; break end
end

-- A spot on dry ground: no molten tile within the lava sample window.
local DryX, DryZ
do
    local g = sites.lava
    for _, v in ipairs(sites.vents) do
        local col = math.floor((v.x - g.originX) / g.cell)
        local row = math.floor((v.z - g.originZ) / g.cell)
        local clean = true
        for dr = -5, 5 do for dc = -5, 5 do
            if (lavaCells[((row + dr) * g.cols) + col + dc] or 0) > 0 then clean = false end
        end end
        if clean then DryX, DryZ = v.x, v.z; break end
    end
    check(DryX ~= nil, "misn10 has dry ground (a geyser surrounded by Sulphur Deposits) to test against")
end

local function Rung(peer, rung)
    peer.Io.ForceLevel(rung, 100000.0, 0.05)
    peer.run(40.0)       -- let the smoothed severity arrive
end

do
    local world = NewWorld()
    local peer = NewPeer("host", world)
    local IO = peer.Io
    local Env = peer.Environment

    local tank = AddObject(world, "avtank", LavaPool.x, 40, LavaPool.z, { owner = "host" })
    local tank2 = AddObject(world, "svtank", LavaPool.x + 30, 40, LavaPool.z, { owner = "host" })
    local tower = AddObject(world, "sbtowe", DryX, 40, DryZ, { building = true })

    peer.playerPos = { x = DryX, y = 40, z = DryZ }
    Env.Init()
    IO.Init({ seed = 424242, authority = true, sites = sites, startLevel = 1, targetLevel = 3 })
    check(Env.Modifiers["CRWeather"] ~= nil, "CRWeather should contribute through Environment")
    check(Env.Modifiers["CRIoWeather"] ~= nil, "the director should register an environment modifier")
    check(Env.GameplayModifiers["CRIoWeather"] == nil, "the director registers NO gameplay modifier: it is cosmetic")
    check(peer.CRWeather.GetPreset() == "IoCalm", "opens on IoCalm")
    check(#IO.GetVentSites() == 21, "the director loads all 21 misn10 vents, got " .. #IO.GetVentSites())
    check(#IO.GetLavaPools() == #sites.lava.pools, "the director loads the lava pool anchors")

    -- ---- off the lava: no lava systems, plumes stream near the geysers ---------
    peer.run(30.0)
    check(IO.GetLavaFactor() < 0.02, "dry ground has no lava factor, got " .. IO.GetLavaFactor())
    check(#SystemsOfTemplate(peer, "CR/Io/Plume") >= 1, "a plume streams in at the geyser the player stands by")
    local plumeOk = true
    for _, sysName in ipairs(SystemsOfTemplate(peer, "CR/Io/Plume")) do
        local pos = peer.rec.systems[sysName].position
        if Dist2(pos.x, pos.z, DryX, DryZ) > IO.PlumeStreamIn + 1 then plumeOk = false end
    end
    check(plumeOk, "only plumes within the stream-in distance exist")
    check(CountSystems(peer, "cr_iw_plume") <= IO.MaxLivePlumes, "plume cap respected")

    -- ---- lava: fog pools stream in, tint rises ---------------------------------
    peer.playerPos = { x = LavaPool.x, y = 40, z = LavaPool.z }
    peer.run(40.0)
    local fog = SystemsOfTemplate(peer, "CR/Io/LavaFog")
    check(#fog >= 3 and #fog <= IO.MaxLiveLava, "lava fog pools stream in over the lava, got " .. #fog)
    local nearOk = true
    for _, sysName in ipairs(fog) do
        local pos = peer.rec.systems[sysName].position
        if Dist2(pos.x, pos.z, LavaPool.x, LavaPool.z) > IO.LavaStreamIn + 1 then nearOk = false end
        -- Low: just above the ground (the terrain here is 40).
        check(pos.y >= 40.0 and pos.y <= 46.0, "lava fog hangs low over the ground, got y=" .. tostring(pos.y))
    end
    check(nearOk, "lava fog is only created within LavaStreamIn")
    check(#SystemsOfTemplate(peer, "CR/Io/LavaGlow") >= 1 and #SystemsOfTemplate(peer, "CR/Io/LavaGlow") <= IO.MaxLiveGlow,
        "lava glow accompanies the pools, capped")
    check(IO.GetLavaFactor() > 0.8, "standing in a molten expanse gives a strong lava factor, got " .. IO.GetLavaFactor())
    local fogRate = peer.rec.systems[fog[1]].rates[0]
    check(fogRate ~= nil and fogRate > 0.5, "lava fog emits")

    -- The global fog closes in and reddens over lava, and opens again off it.
    peer.run(6.0)
    local overFog = { r = peer.rec.fog.r, g = peer.rec.fog.g, b = peer.rec.fog.b, fogEnd = peer.rec.fog.fogEnd, fogStart = peer.rec.fog.fogStart }
    local overAmbient = peer.rec.ambient.r
    peer.playerPos = { x = DryX, y = 40, z = DryZ }
    peer.run(12.0)
    local offFog = peer.rec.fog
    check(overFog.fogEnd < offFog.fogEnd * 0.92, string.format("fog is denser over lava (%.1f) than off it (%.1f)", overFog.fogEnd, offFog.fogEnd))
    check(overFog.fogStart < overFog.fogEnd, "fog start stays under fog end over lava")
    check((overFog.r - overFog.g) > (offFog.r - offFog.g) - 1e-6, "fog is redder over lava")
    check(overAmbient > peer.rec.ambient.r, "lava lights the ambient over it")
    check(IO.GetLavaFactor() < 0.05, "the lava factor falls away off the lava")

    -- Pools stream back out when the player leaves, never above the cap.
    peer.playerPos = { x = LavaPool.x, y = 40, z = LavaPool.z }
    peer.run(20.0)
    local fogNear = CountSystems(peer, "cr_iw_lava_")
    peer.playerPos = { x = 700, y = 40, z = 98450 }
    peer.run(20.0)
    for _, sysName in ipairs(SystemsOfTemplate(peer, "CR/Io/LavaFog")) do
        local pos = peer.rec.systems[sysName].position
        check(Dist2(pos.x, pos.z, 700, 98450) <= IO.LavaStreamOut + 1, "a lava pool far from the player must stream out")
    end
    check(fogNear >= 1 and fogNear <= IO.MaxLiveLava, "lava fog cap respected, got " .. fogNear)

    -- ---- altitude fog from terrain sampling -------------------------------------
    peer.playerPos = { x = PIT.x, y = 12, z = PIT.z }
    peer.run(20.0)
    check(IO.GetBasins() ~= nil, "the terrain scan finished and found basins")
    local pitLava = IO.GetLavaFactor()
    peer.playerPos = { x = HILL.x, y = 100, z = HILL.z }
    peer.run(20.0)
    check(IO.GetPoolFactor() < 0.05, "no altitude fog on the ridge, got " .. IO.GetPoolFactor())
    check(pitLava >= 0.0, "pit lava factor is sane")

    -- ---- the ladder drives ash, fog, light and eruption rate --------------------
    peer.playerPos = { x = DryX, y = 40, z = DryZ }
    local ashRate, sun, fogEnd, eruptScale, lavaDensity = {}, {}, {}, {}, {}
    for rung = 1, 5 do
        Rung(peer, rung)
        peer.run(8.0)
        local ash = SystemsOfTemplate(peer, "CR/Weather/AshFall")[1]
        ashRate[rung] = ash and peer.rec.systems[ash].rates[0] or 0.0
        sun[rung] = peer.rec.sunPower or 1.0
        fogEnd[rung] = peer.rec.fog.fogEnd
        eruptScale[rung] = IO.Levels[rung].eruptScale
        check(peer.CRWeather.GetPreset() == "Io" .. IO.Levels[rung].name, "rung " .. rung .. " selects " .. IO.Levels[rung].preset .. ", got " .. tostring(peer.CRWeather.GetPreset()))
    end
    for rung = 2, 5 do
        check(ashRate[rung] >= ashRate[rung - 1] - 0.01, "ash fall never lightens as the ladder climbs: " .. ashRate[rung - 1] .. " -> " .. ashRate[rung])
        check(sun[rung] < sun[rung - 1] + 1e-6, "the sun dims as the ladder climbs")
        check(fogEnd[rung] <= fogEnd[rung - 1] + 0.5, "fog closes in as the ladder climbs: " .. fogEnd[rung - 1] .. " -> " .. fogEnd[rung])
    end
    check(ashRate[5] > ashRate[1] * 3.0, string.format("paroxysm ash (%.0f) is far heavier than calm (%.0f)", ashRate[5], ashRate[1]))
    local ashSys = SystemsOfTemplate(peer, "CR/Weather/AshFall")[1]
    check(ashSys ~= nil and peer.rec.systems[ashSys].camera ~= nil, "ash fall rides the camera")
    check(CountSystems(peer, "cr_iw_ash") == 1, "exactly one ash system")

    -- Ash can be switched off.
    IO.AllowAshFall = false
    peer.run(2.0)
    check(peer.rec.systems[ashSys].emitting == false, "ash fall switches off")
    IO.AllowAshFall = true
    peer.run(2.0)

    -- ---- twenty minutes of ladder: caps hold, nothing is touched ----------------
    IO.ReleaseForcedLevel()
    IO.SetTargetLevel(4)
    peer.run(120.0)          -- releasing a forced rung is the one deliberate jump
    local maxSystems, maxJump, lastLevel = 0, 0, IO.GetLevel()
    for _ = 1, 30 * 60 * 20 do
        peer.step(1.0 / 30.0)
        maxJump = math.max(maxJump, math.abs(IO.GetLevel() - lastLevel))
        lastLevel = IO.GetLevel()
        maxSystems = math.max(maxSystems, TotalSystems(peer))
    end
    check(maxJump <= 1, "the ladder moves one rung at a time on the live director")
    check(maxSystems <= IO.MaxSystems, "particle systems exceeded the hard cap: " .. maxSystems)
    check(IO.GetStats().eruptions > 20, "twenty minutes of an active volcano should erupt many times, saw " .. IO.GetStats().eruptions)
    check(IO.GetStats().quakes >= 3, "twenty minutes should include random quakes, saw " .. IO.GetStats().quakes)

    -- Cosmetic: no craft was pushed, no sensors changed, no gameplay modifier.
    for _, h in ipairs({ tank, tank2 }) do
        local o = world.objects[h]
        check((o.velocityWrites or 0) == 0 and o.vx == 0 and o.vy == 0 and o.vz == 0, "no craft was ever pushed")
    end
    check(SensorsUntouched(peer), "the director never changes radar range, period or velocity jamming")
    check(Env.GameplayModifiers["CRIoWeather"] == nil, "still no gameplay modifier")
    NoForbidden("one-peer director")

    IO.Shutdown()
    check(TotalSystems(peer) == 0 or CountSystems(peer, "cr_iw_") == 0, "Shutdown destroys every Io system")
    check(Env.Modifiers["CRIoWeather"] == nil, "Shutdown unregisters the environment modifier")
end

-- =============================================================================
-- 5. Eruptions: periodic, staggered, bounded, cosmetic
-- =============================================================================

do
    local world = NewWorld()
    local peer = NewPeer("host", world)
    local IO = peer.Io
    peer.playerPos = { x = 2500, y = 40, z = 99500 }
    peer.Environment.Init()
    local sent = {}
    IO.Init({ seed = 1357, authority = true, sites = sites, bounds = BOUNDS, startLevel = 3, targetLevel = 3,
              send = function(op, ...) sent[#sent + 1] = { op = op, t = peer.now, args = { ... } } end })
    IO.AllowRandomQuakes = false

    -- Stagger: the timers are spread across a period, not bunched.
    local timers = {}
    for i = 1, #IO.VentSites do timers[#timers + 1] = IO.VentTimers[i] end
    table.sort(timers)
    check(#timers == 21, "every vent has a timer")
    check(timers[1] >= IO.EruptionFirstDelay, "no eruption before EruptionFirstDelay")
    local gaps, minGap = {}, 1e9
    for i = 2, #timers do
        gaps[#gaps + 1] = timers[i] - timers[i - 1]
        minGap = math.min(minGap, timers[i] - timers[i - 1])
    end
    check(timers[#timers] - timers[1] > 60.0, "first eruptions are spread over more than a minute, span " .. (timers[#timers] - timers[1]))
    check(minGap > 0.02, "no two vents share a start time")

    peer.run(60.0 * 30.0)
    local erupts = {}
    for _, m in ipairs(sent) do if m.op == "IoErupt" then erupts[#erupts + 1] = m end end
    check(#erupts == IO.GetStats().eruptions, "every host eruption was announced to the guests")
    check(#erupts >= 80, "thirty minutes of an active Io: many eruptions, saw " .. #erupts)

    -- Spacing, periodicity and concurrency.
    local perVent, minSpacing = {}, 1e9
    local siteMajor, majorCount, minorCount = {}, 0, 0
    for i, v in ipairs(IO.VentSites) do siteMajor[i] = v.major end
    for i, m in ipairs(erupts) do
        local id, site, duration, power = m.args[1], m.args[2], m.args[3], m.args[4]
        check(id == i, "eruption ids are sequential")
        check(site >= 1 and site <= 21, "eruption names a real vent")
        check(duration >= IO.EruptionSeconds[1] - 1e-6 and duration <= IO.EruptionSeconds[2] + 1e-6, "eruption duration in range")
        local range = siteMajor[site] and IO.EruptionMajorPower or IO.EruptionPower
        check(power >= range[1] * 0.99 and power <= range[2] * 1.16 + 1e-6, "eruption power in range, got " .. power)
        perVent[site] = (perVent[site] or 0) + 1
        if siteMajor[site] then majorCount = majorCount + 1 else minorCount = minorCount + 1 end
        if i > 1 then minSpacing = math.min(minSpacing, m.t - erupts[i - 1].t) end
    end
    check(minSpacing >= IO.EruptionMinSpacing - 0.1, string.format("eruptions start at least %.1f s apart, closest %.2f", IO.EruptionMinSpacing, minSpacing))
    local erupting = 0
    for _ in pairs(perVent) do erupting = erupting + 1 end
    check(erupting == 21, "every geyser erupts over thirty minutes, saw " .. erupting)
    check(majorCount / 7 > minorCount / 14, "relic geysers erupt more often than the rest")

    -- Each vent is periodic: successive eruptions of one vent are roughly a period apart.
    local last, periods = {}, {}
    for _, m in ipairs(erupts) do
        local site = m.args[2]
        if last[site] and not siteMajor[site] then periods[#periods + 1] = m.t - last[site] end
        last[site] = m.t
    end
    local sum = 0
    for _, p in ipairs(periods) do sum = sum + p end
    local meanPeriod = sum / math.max(1, #periods)
    check(#periods > 40 and meanPeriod > 40 and meanPeriod < 200, "minor vents erupt on a period of the order of the tunable, mean " .. meanPeriod)

    -- An eruption's life: a burst on the plume, a glowing core, then back to a wisp.
    peer.playerPos = { x = IO.VentSites[1].x, y = 40, z = IO.VentSites[1].z }
    peer.run(15.0)
    IO.VentTimers = {}                         -- hold the schedule still for the lifecycle check
    for i = 1, #IO.VentSites do IO.VentTimers[i] = 1e9 end
    peer.run(30.0)
    IO.Eruptions = {}
    local before = IO.GetStats().eruptions
    check(IO.TriggerEruption(1, 1.0), "TriggerEruption fires a host eruption")
    peer.run(4.0)
    check(IO.GetStats().eruptions == before + 1, "the triggered eruption began")
    local plume = IO.PlumeLive[1]
    check(plume ~= nil, "the erupting vent is streamed in")
    local plumeSys = peer.rec.systems[plume.name]
    check(plumeSys.rates[1] > 50.0, "the eruption column emits, got " .. tostring(plumeSys.rates[1]))
    check(plume.glow ~= nil and peer.rec.systems[plume.glow].rates[0] > 10.0, "the eruption has a glowing core")
    check(plume.spatter ~= nil and peer.rec.systems[plume.spatter].rates[0] > 10.0, "the eruption throws spatter")
    peer.run(40.0)
    check(#IO.GetActiveEruptions() == 0, "the eruption ends")
    check((plumeSys.rates[1] or 0) == 0, "the column stops")
    check(plume.glow == nil and plume.spatter == nil, "the glow and spatter systems are released")
    check(near(plumeSys.rates[0], IO.PlumeMinorRate, 0.01) or near(plumeSys.rates[0], IO.PlumeMajorRate, 0.01),
        "the vent returns to a steady wisp")

    -- The red light near an erupting vent.
    IO.Eruptions = {}
    local ambientQuiet = peer.rec.ambient.r
    IO.TriggerEruption(1, 1.0)
    peer.run(4.0)
    check(peer.rec.ambient.r > ambientQuiet, "an erupting vent lifts the red ambient light near it")

    -- Concurrency cap: a high count never exceeds the rung's allowance.
    local peakConcurrent = 0
    for _ = 1, 30 * 600 do
        peer.step(1.0 / 30.0)
        peakConcurrent = math.max(peakConcurrent, #IO.GetActiveEruptions())
    end
    check(peakConcurrent <= IO.Levels[4].maxEruptions + 2, "concurrent eruptions stay bounded, peak " .. peakConcurrent)
    NoForbidden("eruptions")
    IO.Shutdown()
end

-- =============================================================================
-- 6. Quakes: API, natives, ranges, randomness
-- =============================================================================

do
    local world = NewWorld()
    local peer = NewPeer("quake", world)
    local IO = peer.Io
    local tank = AddObject(world, "avtank", 2000, 40, 99500, { owner = "quake" })
    peer.playerPos = { x = 2000, y = 40, z = 99500 }
    peer.Environment.Init()
    local sent = {}
    IO.Init({ seed = 2468, authority = true, sites = sites, bounds = BOUNDS, startLevel = 2, targetLevel = 2,
              send = function(op, ...) sent[#sent + 1] = { op = op, t = peer.now, args = { ... } } end })
    IO.AllowRandomQuakes = false
    peer.run(5.0)

    -- ---- the scripted quake the relic pickup calls -----------------------------
    check(IO.Quake(0.8, 6.0) == true, "CRIoWeather.Quake(strength, duration) begins a quake")
    check(IO.IsQuaking(), "the quake is in progress")
    peer.run(0.2)
    local starts = peer.calls("start")
    check(#starts == 1, "the stock StartEarthquake native is called exactly once")
    check(starts[1].mag >= IO.QuakeMinNative - 1e-6, "StartEarthquake gets a positive magnitude")
    peer.run(7.0)
    check(not IO.IsQuaking(), "the quake ends after its duration")
    local stops = peer.calls("stop")
    check(#stops == 1, "StopEarthquake is called exactly once")
    local updates = peer.calls("update")
    check(#updates >= 60, "UpdateEarthQuake follows the envelope every " .. IO.QuakeUpdateInterval .. " s, got " .. #updates)
    local peak, last = 0.0, 0.0
    for _, c in ipairs(updates) do
        peak = math.max(peak, c.mag)
        check(c.mag >= IO.QuakeMinNative - 1e-6, "native magnitude never drops to zero before the stop")
        check(c.mag <= 0.8 * IO.QuakeMagnitudeScale + 1e-6, "native magnitude never exceeds strength x scale")
    end
    check(near(peak, 0.8 * IO.QuakeMagnitudeScale, 0.15), string.format("the shake reaches strength x scale, peak %.2f", peak))
    check(starts[1].t < updates[1].t and updates[#updates].t < stops[1].t, "start, updates, stop are in order")
    check(near(stops[1].t - starts[1].t, 6.0, 0.25), "the shake lasts its duration, got " .. (stops[1].t - starts[1].t))
    -- Rises then falls (an envelope, not a square wave).
    local first, mid = updates[1].mag, updates[math.floor(#updates / 2)].mag
    check(first < mid * 0.6, "the shake builds up from the start")
    check(updates[#updates].mag < peak * 0.4, "and dies away at the end")
    -- It was announced, once, to the guests.
    local quakeMsgs = {}
    for _, m in ipairs(sent) do if m.op == "IoQuake" then quakeMsgs[#quakeMsgs + 1] = m end end
    check(#quakeMsgs == 1 and quakeMsgs[1].args[2] == 0.8 and quakeMsgs[1].args[3] == 6.0 and quakeMsgs[1].args[4] == 1,
        "the scripted quake is announced once with its strength and duration")
    check(IO.GetStats().scriptedQuakes == 1 and IO.GetStats().randomQuakes == 0, "stats count it as scripted")

    -- ---- dust and ash during a quake --------------------------------------------
    peer.quakeCalls = {}
    local ashBefore = IO.GetAshIntensity()
    IO.Quake(1.0, 8.0)
    peer.run(3.0)
    local dust = SystemsOfTemplate(peer, "CR/Io/QuakeDust")
    check(#dust == 1, "a quake shakes loose dust")
    check(peer.rec.systems[dust[1]].camera ~= nil, "the dust rides the camera")
    check(peer.rec.systems[dust[1]].rates[0] > 100.0, "the dust is thick at the height of a strong quake, got " .. tostring(peer.rec.systems[dust[1]].rates[0]))
    check(IO.GetAshIntensity() > ashBefore * 1.5, "extra ash falls during the quake")
    local ash = SystemsOfTemplate(peer, "CR/Weather/AshFall")[1]
    check(peer.rec.systems[ash].rates[0] > IO.AshMaxRate * ashBefore, "the ash system's rate rises with the quake")
    peer.run(12.0)
    check(#SystemsOfTemplate(peer, "CR/Io/QuakeDust") == 0, "the dust clears after the shake")
    check(IO.GetAshIntensity() < ashBefore * 1.2, "the ash settles back")

    -- ---- merging, clamping, dedupe ------------------------------------------------
    peer.quakeCalls = {}
    local stopsBefore = #peer.calls("stop")
    IO.Quake(0.4, 4.0)
    peer.run(1.0)
    IO.Quake(0.9, 5.0)
    peer.run(0.5)
    check(IO.GetStats().mergedQuakes >= 1, "a quake during a quake merges into it")
    check(#peer.calls("start") == 1, "merged quakes share one native shake")
    local q = IO.GetQuake()
    check(q ~= nil and q.strength >= 0.9 - 1e-9, "the merged shake takes the stronger strength")
    check(q.duration >= 5.0 + 1.0, "the merged shake lasts to the later end, got " .. q.duration)
    peer.run(15.0)
    check(#peer.calls("stop") == 1, "and stops once")

    peer.quakeCalls = {}
    check(IO.Quake(5.0, 500.0) == true, "an absurd quake is clamped, not refused")
    local qq = IO.GetQuake()
    check(qq.strength <= 1.0 and qq.duration <= IO.QuakeDurationLimit[2], "strength and duration are clamped")
    peer.run(0.5)
    IO.StopQuake()
    check(not IO.IsQuaking() and #peer.calls("stop") == 1, "StopQuake ends a shake at once")
    check(IO.Quake(0.0, 5.0) == false, "a zero-strength quake does nothing")
    check(IO.Quake() == true, "Quake() with no arguments uses the scripted defaults")
    local defaults = IO.GetQuake()
    check(defaults.strength == IO.QuakeScriptedDefault[1] and defaults.duration == IO.QuakeScriptedDefault[2], "scripted defaults applied")
    IO.StopQuake()

    -- Same event id is never played twice.
    IO.StopQuake()
    peer.quakeCalls = {}
    check(IO.BeginQuake(900, 0.5, 3.0, 1) == true, "an event begins a quake")
    IO.StopQuake()
    check(IO.BeginQuake(900, 0.5, 3.0, 1) == false, "the same id is a duplicate")
    IO.StopQuake()

    -- Switch off.
    IO.AllowQuakes = false
    peer.quakeCalls = {}
    check(IO.Quake(1.0, 5.0) == false, "quakes switch off")
    peer.run(3.0)
    check(#peer.quakeCalls == 0, "no native calls with quakes switched off")
    IO.AllowQuakes = true

    -- A strong quake sets vents off; a weak one does not.
    IO.StopQuake()
    IO.VentTimers = {}
    for i = 1, #IO.VentSites do IO.VentTimers[i] = 1e9 end
    local erupt0, quakeErupt0 = IO.GetStats().eruptions, IO.GetStats().quakeEruptions
    IO.Quake(0.2, 5.0)
    peer.run(8.0)
    check(IO.GetStats().eruptions == erupt0, "a weak quake does not open the vents")
    IO.Quake(1.0, 8.0)
    peer.run(10.0)
    local opened = IO.GetStats().eruptions - erupt0
    check(opened >= 1 and opened <= IO.QuakeEruptCount, "a strong quake opens up to " .. IO.QuakeEruptCount .. " vents, opened " .. opened)
    check(IO.GetStats().quakeEruptions - quakeErupt0 == opened, "those eruptions are counted as quake-triggered")

    -- Shutdown during a quake stops the native shake.
    peer.run(30.0)
    peer.quakeCalls = {}
    IO.Quake(0.7, 20.0)
    peer.run(3.0)
    IO.Shutdown()
    check(#peer.calls("stop") == 1, "Shutdown stops a quake in progress so it cannot outlive the mission")
    check(CountSystems(peer, "cr_iw_") == 0, "and destroys the dust")

    check((world.objects[tank].velocityWrites or 0) == 0, "a quake never moves a craft")
    NoForbidden("quakes")
end

-- ---- random quakes: ranges, variety, cadence ---------------------------------

do
    local world = NewWorld()
    local peer = NewPeer("random", world)
    local IO = peer.Io
    peer.Environment.Init()
    local sent = {}
    IO.Init({ seed = 97531, authority = true, sites = sites, bounds = BOUNDS, startLevel = 1, targetLevel = 4,
              send = function(op, ...) sent[#sent + 1] = { op = op, t = peer.now, args = { ... } } end })
    peer.run(60.0 * 60.0 * 4.0, 0.25)       -- four hours at 4 fps: the schedule does not depend on frame rate

    -- The brief's ranges are the defaults, and the test holds the module to the
    -- brief itself rather than to whatever the tunables currently say.
    check(IO.QuakeGap[1] == 90.0 and IO.QuakeGap[2] == 240.0, "default quake gap is 90-240 s")
    check(IO.QuakeStrength[1] == 0.2 and IO.QuakeStrength[2] == 1.0, "default quake strength is 0.2-1.0")
    check(IO.QuakeDuration[1] == 2.0 and IO.QuakeDuration[2] == 10.0, "default quake duration is 2-10 s")

    local quakes = {}
    for _, m in ipairs(sent) do if m.op == "IoQuake" then quakes[#quakes + 1] = m end end
    check(#quakes >= 60 and #quakes <= 160, "four hours holds roughly 14400/165 random quakes, saw " .. #quakes)
    local minS, maxS, minD, maxD, minGap, maxGap = 9, -9, 99, -9, 1e9, 0
    local sumGap = 0
    for i, m in ipairs(quakes) do
        local s, d, kind = m.args[2], m.args[3], m.args[4]
        minS, maxS = math.min(minS, s), math.max(maxS, s)
        minD, maxD = math.min(minD, d), math.max(maxD, d)
        check(kind == 2, "unscripted quakes are marked random")
        check(s >= 0.2 - 1e-9 and s <= 1.0 + 1e-9, "random strength within 0.2 .. 1.0, got " .. s)
        check(d >= 2.0 - 1e-9 and d <= 10.0 + 1e-9, "random duration within 2 .. 10 s, got " .. d)
        if i > 1 then
            local gap = m.t - quakes[i - 1].t
            minGap, maxGap = math.min(minGap, gap), math.max(maxGap, gap)
            sumGap = sumGap + gap
        end
    end
    check(minGap >= 90.0 - 0.5 and maxGap <= 240.0 + 0.5,
        string.format("random quakes come every 90-240 s, saw %.1f .. %.1f", minGap, maxGap))
    check(near(sumGap / (#quakes - 1), 165.0, 12.0), "the mean gap is the middle of the range")
    check(minS < 0.35 and maxS > 0.85, string.format("strengths vary (%.2f .. %.2f)", minS, maxS))
    check(minD < 3.5 and maxD > 8.5, string.format("durations vary (%.1f .. %.1f)", minD, maxD))
    check(IO.GetStats().randomQuakes == #quakes and IO.GetStats().scriptedQuakes == 0, "stats count them as random")

    -- Strength tracks the ladder: calmer sky, gentler quakes (on average).
    local function MeanStrength(rung)
        local p = NewPeer("bias", NewWorld())
        p.Environment.Init()
        local got = {}
        p.Io.Init({ seed = 1234, authority = true, sites = sites, bounds = BOUNDS, startLevel = rung, targetLevel = rung,
                    send = function(op, ...) if op == "IoQuake" then got[#got + 1] = select(2, ...) end end })
        p.Io.ForceLevel(rung, 1e9, 0.05)
        p.run(60.0 * 60.0 * 6.0, 0.25)
        local sum = 0
        for _, s in ipairs(got) do sum = sum + s end
        return sum / math.max(1, #got), #got
    end
    local calmMean = MeanStrength(1)
    local fierceMean = MeanStrength(5)
    check(fierceMean > calmMean + 0.08, string.format("paroxysm quakes (%.2f) are stronger on average than calm ones (%.2f)", fierceMean, calmMean))
    check(calmMean >= 0.2 and fierceMean <= 1.0, "mean strengths stay inside the range")

    -- Random quakes can be switched off, and a scripted one is unaffected.
    local p2 = NewPeer("norandom", NewWorld())
    p2.Environment.Init()
    p2.Io.Init({ seed = 42, authority = true, sites = sites, bounds = BOUNDS, randomQuakes = false })
    p2.run(60.0 * 20.0, 0.25)
    check(p2.Io.GetStats().quakes == 0 and #p2.calls("start") == 0, "no random quakes when switched off")
    check(p2.Io.Quake(0.6, 3.0), "a scripted quake still works with random quakes off")
    NoForbidden("random quakes")
end

-- =============================================================================
-- 7. Determinism: same seed, same host decisions
-- =============================================================================

local function HostScript(seed)
    local peer = NewPeer("det", NewWorld())
    peer.Environment.Init()
    local events = {}
    peer.Io.Init({ seed = seed, authority = true, sites = sites, bounds = BOUNDS, targetLevel = 4,
                   send = function(op, ...)
                       local parts = { op }
                       for i = 1, select("#", ...) do parts[#parts + 1] = string.format("%.4f", select(i, ...)) end
                       events[#events + 1] = string.format("%.2f ", peer.now) .. table.concat(parts, ",")
                   end })
    peer.run(60.0 * 25.0)
    peer.Io.Shutdown()
    return events
end

do
    local a, b, c = HostScript(31337), HostScript(31337), HostScript(31338)
    check(#a > 100, "a host emits many events over twenty-five minutes, saw " .. #a)
    local same = (#a == #b)
    if same then
        for i = 1, #a do if a[i] ~= b[i] then same = false; break end end
    end
    check(same, "the same seed gives byte-identical eruption, quake and state events")
    local differs = (#a ~= #c)
    if not differs then
        for i = 1, #a do if a[i] ~= c[i] then differs = true; break end end
    end
    check(differs, "a different seed gives different events")
    local haveErupt, haveQuake, haveState = false, false, false
    for _, line in ipairs(a) do
        if string.find(line, " IoErupt,", 1, true) then haveErupt = true end
        if string.find(line, " IoQuake,", 1, true) then haveQuake = true end
        if string.find(line, " IoState,", 1, true) then haveState = true end
    end
    check(haveErupt and haveQuake and haveState, "the stream carries all three ops")
end

-- =============================================================================
-- 8. Co-op: the host decides, guests shake and erupt at the same time
-- =============================================================================

do
    local world = NewWorld()
    local hostPeer = NewPeer("host", world, { net = true })
    local guestPeer = NewPeer("guest", world, { net = true })
    local H, G = hostPeer.Io, guestPeer.Io
    hostPeer.playerPos = { x = 2400, y = 40, z = 99400 }
    guestPeer.playerPos = { x = 2420, y = 40, z = 99410 }

    local hostTank = AddObject(world, "avtank", 2400, 40, 99400, { owner = "host" })
    local guestTank = AddObject(world, "avtank", 2420, 40, 99410, { owner = "guest" })

    -- A delayed, ordered link from host to guest that can lose chosen ops.
    local LATENCY = 0.12
    local queue, sent, dropStates = {}, {}, false
    local function HostSend(op, ...)
        sent[#sent + 1] = { op = op, t = hostPeer.now, args = { ... }, n = select("#", ...) }
        if dropStates and op == "IoState" then return end
        queue[#queue + 1] = { at = hostPeer.now + LATENCY, op = op, args = { ... }, n = select("#", ...) }
    end
    local unpackArgs = unpack

    hostPeer.Environment.Init()
    guestPeer.Environment.Init()
    H.Init({ seed = 555777, authority = true, send = HostSend, sites = sites, bounds = BOUNDS, targetLevel = 4 })
    G.Init({ authority = false, sites = sites, bounds = BOUNDS, targetLevel = 4 })      -- no seed: waits for the host

    check(not G.Synced, "a guest with no seed must wait for the host rather than invent a timeline")
    check(sent[1] ~= nil and sent[1].op == "IoState", "the host announces its seed and state at start")

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
    check(G.Synced and G.Seed == 555777, "the guest adopts the host's seed")

    -- The scripted quake: one call on the host shakes both peers, together.
    RunBoth(10.0)
    hostPeer.quakeCalls, guestPeer.quakeCalls = {}, {}
    H.AllowRandomQuakes = false
    check(H.Quake(0.9, 7.0), "the host's scripted quake begins")
    check(G.Quake(0.9, 7.0) == false, "a guest's own Quake() call is ignored (the host's event is the authority)")
    RunBoth(10.0)
    local hs, gs = hostPeer.calls("start"), guestPeer.calls("start")
    check(#hs == 1 and #gs == 1, "both peers start the shake exactly once")
    hs[1] = hs[1] or { t = -1e9 }; gs[1] = gs[1] or { t = 1e9 }
    check(near(hs[1].t, gs[1].t, 0.25), string.format("both peers start shaking at the same time (host %.2f, guest %.2f)", hs[1].t, gs[1].t))
    local he, ge = hostPeer.calls("stop"), guestPeer.calls("stop")
    he[1] = he[1] or { t = -1e9 }; ge[1] = ge[1] or { t = 1e9 }
    check(#he == 1 and #ge == 1 and near(he[1].t, ge[1].t, 0.25), "and stop together")
    local hp, gp = 0, 0
    for _, c in ipairs(hostPeer.calls("update")) do hp = math.max(hp, c.mag) end
    for _, c in ipairs(guestPeer.calls("update")) do gp = math.max(gp, c.mag) end
    check(near(hp, gp, 0.15) and hp > 2.0, string.format("and with the same strength (host %.2f, guest %.2f)", hp, gp))
    check(G.GetStats().quakes == 1 and H.GetStats().quakes == 1, "one quake on each peer")

    -- Dust on the guest too.
    RunBoth(30.0)
    guestPeer.quakeCalls, hostPeer.quakeCalls = {}, {}
    H.Quake(1.0, 6.0)
    RunBoth(2.5)
    check(#SystemsOfTemplate(guestPeer, "CR/Io/QuakeDust") == 1, "the guest sees the quake's dust")
    RunBoth(15.0)

    -- A long shared run: levels, eruptions and random quakes all match.
    H.AllowRandomQuakes = true
    H.NextQuakeAt = H.Clock + 5.0
    local mismatches, samples, hostHadActive = 0, 0, false
    for _ = 1, 25 * 60 do
        RunBoth(1.0)
        samples = samples + 1
        if H.GetLevel() ~= G.GetLevel() then mismatches = mismatches + 1 end
        if H.GetLevel() >= 3 then hostHadActive = true end
    end
    check(mismatches <= samples * 0.02, string.format("guest rung must track the host (%d of %d seconds differ)", mismatches, samples))
    check(hostHadActive, "the shared run includes active weather")

    local hostErupts, hostQuakes = 0, 0
    for _, m in ipairs(sent) do
        if m.op == "IoErupt" then hostErupts = hostErupts + 1 end
        if m.op == "IoQuake" then hostQuakes = hostQuakes + 1 end
    end
    check(hostErupts > 20, "the host sent eruption events, saw " .. hostErupts)
    check(near(G.GetStats().eruptions, H.GetStats().eruptions, 1), string.format("the guest renders the host's eruptions (%d vs %d)", G.GetStats().eruptions, H.GetStats().eruptions))
    check(hostQuakes >= 5, "the host sent random quakes, saw " .. hostQuakes)
    check(near(G.GetStats().quakes, H.GetStats().quakes, 1), string.format("the guest shakes for the host's quakes (%d vs %d)", G.GetStats().quakes, H.GetStats().quakes))
    check(near(G.GetStats().peakQuake, H.GetStats().peakQuake, 1e-9), "guest and host saw the same strongest quake")
    local hStarts, gStarts = hostPeer.calls("start"), guestPeer.calls("start")
    check(near(#hStarts, #gStarts, 1), "both peers drove the engine's quake the same number of times")
    local worst = 0
    for i = 1, math.min(#hStarts, #gStarts) do worst = math.max(worst, math.abs(hStarts[i].t - gStarts[i].t)) end
    check(worst < 0.3, string.format("every shake starts within the link latency on both peers, worst %.2f s", worst))

    -- The guest never decides anything of its own.
    local guestAlone = NewPeer("lonely", world, { net = true })
    guestAlone.Environment.Init()
    guestAlone.Io.Init({ seed = 555777, authority = false, sites = sites, bounds = BOUNDS, targetLevel = 4 })
    guestAlone.Io.ForceLevel(5, 1000.0, 1.0)
    guestAlone.run(60.0 * 20.0)
    check(guestAlone.Io.GetStats().eruptions == 0, "a guest decides no eruptions; it only replays the host's")
    check(guestAlone.Io.GetStats().quakes == 0 and #guestAlone.calls("start") == 0, "a guest decides no quakes; it only replays the host's")
    check(guestAlone.Io.ForceLevel(5, 10.0) == false, "a guest's ForceLevel is ignored")

    -- Replaying an event twice does nothing the second time.
    local before = G.GetStats().quakes
    local sample
    for i = #sent, 1, -1 do if sent[i].op == "IoQuake" then sample = sent[i]; break end end
    G.ApplyNetEvent("IoQuake", unpackArgs(sample.args, 1, sample.n))
    check(G.GetStats().quakes == before, "a duplicated quake event is ignored")

    -- Losing every state message after the first still leaves the guest tracking.
    dropStates = true
    hostPeer.Io.SetTargetLevel(2)
    RunBoth(200.0)
    local lag = 0
    for _ = 1, 120 do
        RunBoth(1.0)
        if H.GetLevel() ~= G.GetLevel() then lag = lag + 1 end
    end
    check(lag <= 40, "the guest keeps following the seeded timeline when state messages are lost, differed " .. lag .. "/120 s")
    dropStates = false

    -- A guest that initialised late is caught up by AnnounceState.
    local late = NewPeer("late", world, { net = true })
    late.Environment.Init()
    late.Io.Init({ authority = false, sites = sites, bounds = BOUNDS, targetLevel = 4 })
    check(not late.Io.Synced, "a late guest starts unsynced")
    local before2 = #sent
    H.AnnounceState()
    check(#sent == before2 + 1 and sent[#sent].op == "IoState", "AnnounceState re-sends the state on demand")
    local m = sent[#sent]
    late.Io.ApplyNetEvent(m.op, unpackArgs(m.args, 1, m.n))
    check(late.Io.Synced and late.Io.Seed == 555777, "the late guest syncs from the announcement")

    check((world.objects[hostTank].velocityWrites or 0) == 0 and (world.objects[guestTank].velocityWrites or 0) == 0,
        "no craft was moved on either peer")
    check(SensorsUntouched(hostPeer) and SensorsUntouched(guestPeer), "no sensors were changed on either peer")
    NoForbidden("co-op")
    H.Shutdown(); G.Shutdown(); guestAlone.Io.Shutdown(); late.Io.Shutdown()
end

-- =============================================================================
-- 9. Degradation, solo, save / load
-- =============================================================================

do
    -- A build that has not shipped the cr_io payload still gets presets, ash and quakes.
    local world = NewWorld()
    local peer = NewPeer("notemplates", world, { noIoTemplates = true })
    peer.playerPos = { x = LavaPool.x, y = 40, z = LavaPool.z }
    peer.Environment.Init()
    peer.Io.Init({ seed = 11, sites = sites, bounds = BOUNDS, startLevel = 3, targetLevel = 3 })
    peer.run(60.0)
    check(CountSystems(peer, "cr_iw_lava") == 0 and CountSystems(peer, "cr_iw_plume") == 0, "without the payload there are no lava or plume systems")
    check(peer.CRWeather.GetPreset() ~= nil, "presets still work without the payload")
    check(peer.Io.Quake(0.7, 3.0), "quakes still work without the payload")
    peer.run(5.0)
    check(#peer.calls("start") == 1 and #peer.calls("stop") == 1, "and still drive the engine's quake")
    peer.Io.Shutdown()

    -- A failing template is disabled after three tries instead of retrying forever.
    local failing = NewPeer("failing", NewWorld(), { failTemplate = "CR/Io/LavaFog" })
    failing.playerPos = { x = LavaPool.x, y = 40, z = LavaPool.z }
    failing.Environment.Init()
    failing.Io.Init({ seed = 12, sites = sites, bounds = BOUNDS })
    failing.run(30.0)
    check(failing.Io.TemplateFailures["CR/Io/LavaFog"] == failing.Io.MaxFailuresPerTemplate, "a failing template is given up on after three tries")
    failing.Io.Shutdown()

    -- Offline solo is the host path with no sender.
    local solo = NewPeer("solo", NewWorld())
    solo.Environment.Init()
    solo.Io.Init({ seed = 31415, sites = sites, bounds = BOUNDS, targetLevel = 4 })
    check(solo.Io.IsAuthority and solo.Io.Synced and solo.Io.NetSend == nil, "offline is the authority and sends nothing")
    solo.run(60.0 * 12.0)
    check(solo.Io.GetStats().eruptions > 0 and solo.Io.GetStats().quakes >= 1, "offline weather erupts and quakes")
    solo.Io.Shutdown()

    -- Save / load.
    local a = NewPeer("save", NewWorld())
    a.Environment.Init()
    a.Io.Init({ seed = 8080, sites = sites, bounds = BOUNDS, targetLevel = 4 })
    a.Io.ForceLevel(4, 500.0, 0.5)
    a.run(120.0)
    a.Io.Quake(0.9, 30.0)
    a.run(2.0)
    local state = a.Io.Save()
    check(state.seed == 8080 and state.level == 4 and state.forcedLevel == 4 and state.quakeSerial == 1, "Save captures the director's scalars")
    local b = NewPeer("load", NewWorld())
    b.Environment.Init()
    b.Io.Init({ seed = 1, sites = sites, bounds = BOUNDS })
    b.Io.Load(state)
    b.run(1.0)
    check(b.Io.Seed == 8080 and b.Io.GetLevel() == 4 and b.Io.ForcedLevel == 4, "Load restores the seed, rung and forced level")
    check(b.Io.QuakeSerial == 1, "Load restores the quake serial so ids never collide")
    check(#b.calls("stop") >= 1 and #b.calls("start") == 0, "Load stops any quake the engine replays and does not start one")
    check(not b.Io.IsQuaking(), "a quake in progress at save time is not resumed")
    b.Io.Shutdown(); a.Io.Shutdown()
end

-- =============================================================================
-- 9b. Pool pops: bubbles, embers and spatter on the molten pools (CRPoolFX)
-- =============================================================================

do
    local function Recording(rec)
        return {
            Event = function(kind, pos, scale, mask)
                rec[#rec + 1] = { kind = kind, x = pos.x, y = pos.y, z = pos.z, scale = scale, mask = mask }
                return true
            end,
            Update = function() end,
            StopKind = function(kind) rec.stopped = kind end,
        }
    end

    local function Run(label, setup, rung, seconds)
        local world = NewWorld()
        local peer = NewPeer(label, world)
        local rec = {}
        peer.preload["CRGroundFX"] = Recording(rec)
        peer.playerPos = { x = LavaPool.x, y = 40, z = LavaPool.z }
        peer.Environment.Init()
        peer.Io.Init({ seed = 77, authority = true, sites = sites, startLevel = rung, targetLevel = rung })
        if setup then setup(peer) end
        peer.run(seconds)
        return peer, rec
    end

    local peer, rec = Run("poolfx", nil, 1, 120.0)
    local IO = peer.Io
    check(#rec > 20, "molten pools pop while the player is near them, got " .. #rec .. " events in 120 s")
    check(#rec <= (120.0 / 0.35) + 1, "events are rate limited by the minimum spacing")
    local weightOk, nearOk, kindOk, maskOk = true, true, true, true
    for _, e in ipairs(rec) do
        if IO.LavaWeightAt(e.x, e.z) < 0.5 then weightOk = false end
        if Dist2(e.x, e.z, LavaPool.x, LavaPool.z) > IO.PoolFxRange + IO.PoolFxRadius + 1 then nearOk = false end
        if e.kind ~= "lava" then kindOk = false end
        if e.mask == nil or e.mask.smoke == nil or e.mask.smoke >= 1.0 then maskOk = false end
    end
    check(weightOk, "every pop lands on a molten cell (weight >= 0.5)")
    check(nearOk, "pops happen only near the player")
    check(kindOk and maskOk, "pops use the lava kind with the light-smoke mask")

    local _, high = Run("poolfx-high", nil, 5, 120.0)
    check(#high > #rec, "a higher rung pops more often (" .. #high .. " vs " .. #rec .. ")")

    local _, off = Run("poolfx-off", function(p) p.Io.AllowPoolFx = false end, 3, 60.0)
    check(#off == 0, "AllowPoolFx = false silences the pops")

    local _, noq = Run("poolfx-q0", function(p) p.CRWeather.Quality = 0.0 end, 3, 60.0)
    check(#noq == 0, "weather quality 0 silences the pops")

    local peerFar, far = Run("poolfx-far", nil, 3, 1.0)
    peerFar.playerPos = { x = 100, y = 40, z = 99000 }
    local before = #far
    peerFar.run(60.0)
    check(#far == before, "no pops while every pool is out of range")

    -- Shutdown stops the kind's systems; the option switches it off at Init.
    peer.Io.Shutdown()
    check(rec.stopped == "lava", "Shutdown removes the lava systems it owns")
    local world2 = NewWorld()
    local p2 = NewPeer("poolfx-init-off", world2)
    local rec2 = {}
    p2.preload["CRGroundFX"] = Recording(rec2)
    p2.playerPos = { x = LavaPool.x, y = 40, z = LavaPool.z }
    p2.Environment.Init()
    p2.Io.Init({ seed = 77, authority = true, sites = sites, poolFx = false, startLevel = 3, targetLevel = 3 })
    p2.run(60.0)
    check(#rec2 == 0, "Init{ poolFx = false } silences the pops")
end

-- =============================================================================
-- 10. The module never reaches for anything damaging (static check)
-- =============================================================================

do
    local handle = io.open(scriptDir .. "/CRIoWeather.lua", "rb")
    local source = handle:read("*a")
    handle:close()
    local stripped = source:gsub("%-%-[^\n]*", "")
    for _, word in ipairs({ "SetCurHealth", "AddHealth", "Damage", "SetVelocity", "SetCurAmmo", "AddAmmo", "SetGravity",
                            "MakeExplosion", "RemoveObject", "BuildObject", "SetRadarRange", "SetVelocJam",
                            "RegisterGameplayModifier", "SetObjectScramble", "SetPosition(", "SetCommand" }) do
        check(not string.find(stripped, word, 1, true), "CRIoWeather.lua must not mention " .. word)
    end
    for _, word in ipairs({ "StartEarthquake", "UpdateEarthQuake", "StopEarthquake" }) do
        check(string.find(stripped, word, 1, true) ~= nil, "CRIoWeather.lua uses the stock " .. word .. " native")
    end
end

-- =============================================================================
-- Report
-- =============================================================================

if #failures > 0 then
    for _, message in ipairs(failures) do print("FAIL: " .. message) end
    print(string.format("%d of %d expectation(s) failed", #failures, assertions))
    os.exit(1)
end

print(string.format("IO WEATHER OK (%d assertions)", assertions))
