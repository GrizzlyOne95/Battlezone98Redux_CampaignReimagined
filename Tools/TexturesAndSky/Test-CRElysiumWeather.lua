-- Test-CRElysiumWeather.lua
--
-- Drives the real CRElysiumWeather (over CRVenusWeather, CRVenusMap), CRWeather and Environment
-- against a stubbed exu and a stubbed BZ Lua runtime. No game, no Ogre.
--
-- Usage, from the repository root:
--
--     lua Tools/TexturesAndSky/Test-CRElysiumWeather.lua Scripts
--
-- Every "peer" below is a fully isolated Lua environment with its own copy of
-- every module and its own globals, which is what a second machine is. Peers
-- share only a World table (the craft that exist and who owns them) and the
-- messages one sends the other.
--
-- Prints ELYSIUM WEATHER OK on success; prints each failed expectation and exits
-- 1 otherwise.

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
        if h == 1 then return UD(peer.playerPos) end
        local o = world.objects[h]
        if o then return UD({ x = o.x, y = o.y, z = o.z }) end
        return nil
    end
    env.GetVelocity = function(h)
        local o = world.objects[h]
        return UD(o and { x = o.vx, y = o.vy, z = o.vz } or { x = 0, y = 0, z = 0 })
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
    peer.Elysium = load("CRElysiumWeather")
    peer.Map = load("CRVenusMap")
    peer.Environment.EnableVisualRuntime = false

    function peer.step(dt)
        peer.now = peer.now + dt
        peer.Elysium.Update(dt)
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

local SITE_FILES = { "BD07", "BD09", "BD10", "BD11" }
local ELYSIUM_PRESETS = { "ElysiumCalm", "ElysiumHaze", "ElysiumRising", "ElysiumStorm", "ElysiumSevere" }

local function Sites(tag)
    return dofile(scriptDir .. "/CRElysiumSites" .. tag .. ".lua")
end

local function StartPeer(name, world, options, initOptions)
    local peer = NewPeer(name, world, options)
    local init = { seed = 4242, authority = true, bounds = BOUNDS, startLevel = 1, targetLevel = 4 }
    for k, v in pairs(initOptions or {}) do init[k] = v end
    init.sites = init.sites or Sites("BD07")
    peer.Elysium.Init(init)
    return peer
end

local function BadTemplates(peer)
    local bad = {}
    for sysName, s in pairs(peer.rec.systems) do
        local t = s.template
        if t:find("SulfurPool", 1, true) or t:find("Plume", 1, true) or t:find("Embers", 1, true) then
            bad[#bad + 1] = sysName .. "=" .. t
        end
    end
    return bad
end

-- 1. Site files: every Black Dog map loads and is sulphur-free in the director.
for _, tag in ipairs(SITE_FILES) do
    local s = Sites(tag)
    check(s.mission == "bdmisn" .. tag:sub(3), "site file " .. tag .. " names its mission")
    check(type(s.bounds) == "table" and s.bounds.maxX > s.bounds.minX and s.bounds.maxZ > s.bounds.minZ,
        tag .. " has playable bounds")
    check(#s.sulfur.runs == 0, tag .. " has no sulphur pool cells")
end

-- 2. Init applies the Elysium dressing; Venus values are restored on Shutdown.
do
    local venusLevels = nil
    local world = NewWorld()
    local peer = NewPeer("host", world)
    venusLevels = peer.Venus.Levels
    local venusRain = peer.Venus.RainTint
    peer.Elysium.Init({ seed = 4242, authority = true, sites = Sites("BD07"), bounds = BOUNDS,
        startLevel = 1, targetLevel = 4 })
    check(peer.Venus.Initialized, "Init starts the shared engine")
    check(peer.Elysium.Seed == 4242, "Seed is readable through the module")
    check(peer.Venus.Levels ~= venusLevels and peer.Venus.Levels[1].preset == "ElysiumCalm"
        and peer.Venus.Levels[5].preset == "ElysiumSevere", "levels use the Elysium presets")
    for _, name in ipairs(ELYSIUM_PRESETS) do
        check(peer.loaded["CRWeatherPresets"].Presets[name] ~= nil, "preset registered: " .. name)
    end
    check(not peer.Venus.AllowSulfur and not peer.Venus.AllowVents and not peer.Venus.AllowEruptions
        and not peer.Venus.AllowPoolFx and not peer.Venus.AllowGlassAcid, "sulphur, volcano and acid layers are off")
    check(#peer.Venus.SulfurSites == 0, "no sulphur emitters from the Elysium sites")
    -- Dust, wind and dry lightning, little rain, cold grey-violet fog (Docs/ELYSIUM_WEATHER.md).
    local calm, severe = peer.Venus.Levels[1], peer.Venus.Levels[5]
    check(severe.rain <= 0.5 and peer.Venus.Levels[4].rain <= 0.25 and peer.Venus.RainMaxRate <= 250, "Elysium rain is light")
    check(peer.Venus.Levels[3].strikesPerMinute > peer.Venus.Levels[3].rain * 10 and severe.strikesPerMinute >= 10,
        "Elysium fronts strike lightning with little rain")
    check(calm.windSpeed >= 4.0 and severe.windSpeed >= 20.0, "Elysium wind is strong")
    local calmPreset = peer.loaded["CRWeatherPresets"].Presets["ElysiumCalm"]
    check(calmPreset.fog.fogStart == 80.0 and calmPreset.fog.fogEnd == 250.0, "calm Elysium fog runs 80 to 250")
    check(calmPreset.fog.r + 0.04 >= calmPreset.fog.g and calmPreset.fog.b - calmPreset.fog.r < 0.12
        and calmPreset.fog.b - calmPreset.fog.r > 0.0, "Elysium fog is a desaturated grey-violet")

    peer.run(60.0)
    peer.Elysium.ForceLevel(5, 120.0)
    peer.run(90.0)
    check(#BadTemplates(peer) == 0, "no sulphur pool / plume / ember systems: " .. table.concat(BadTemplates(peer), ","))
    check(peer.Elysium.GetStats().eruptions == 0, "no eruptions are scheduled")
    check(CountSystems(peer, "cr_vw_sulfur") == 0 and CountSystems(peer, "cr_vw_plume") == 0
        and CountSystems(peer, "cr_vw_embers") == 0, "no sulphur / volcano system names")
    local usesElysium = false
    for _, e in ipairs(peer.log) do
        if e.template:find("CR/Elysium/", 1, true) then usesElysium = true end
        check(not e.template:find("CR/Venus/FogPool", 1, true) and not e.template:find("CR/Venus/CloudDeck", 1, true),
            "sulphur-coloured sheets are never created: " .. e.template)
    end
    check(usesElysium, "the Elysium fog / cloud sheets are created")
    check(peer.Elysium.GetStats().strikes >= 1, "a severe Elysium storm strikes lightning")
    check(CountSystems(peer, "cr_vw_bolt") + CountSystems(peer, "cr_vw_glow") + CountSystems(peer, "cr_vw_rain") >= 1
        or peer.Elysium.GetStats().strikes >= 1, "lightning / rain are produced")
    check(#damageCalls == 0, "the director never damages anything")

    -- Save / Load round trip.
    local state = peer.Elysium.Save()
    check(state.seed == 4242 and type(state.level) == "number", "Save carries the seed and level")
    local again = StartPeer("host", NewWorld(), nil, { seed = 4242 })
    again.Elysium.Load(state)
    check(again.Elysium.Save().seed == 4242 and again.Elysium.Save().level == state.level, "Load restores the state")
    check(again.Venus.Levels[1].preset == "ElysiumCalm", "Load keeps the Elysium levels")
    again.Elysium.Shutdown()

    peer.Elysium.Shutdown()
    check(peer.Venus.Levels == venusLevels, "Shutdown restores the Venus levels")
    check(peer.Venus.AllowSulfur and peer.Venus.AllowVents and peer.Venus.AllowEruptions
        and peer.Venus.AllowPoolFx and peer.Venus.AllowGlassAcid, "Shutdown restores the Venus switches")
    check(peer.Venus.RainTint == venusRain and venusRain.g > 0.6 and venusRain.b < 0.3, "Shutdown restores the Venus rain tint")
    check(peer.Venus.Templates.fog == "CR/Venus/FogPool", "Shutdown restores the Venus templates")
end

-- 3. Each Black Dog map runs through a storm without sulphur or volcano fx.
for _, tag in ipairs(SITE_FILES) do
    local peer = StartPeer("host", NewWorld(), nil, { sites = Sites(tag), startLevel = 4 })
    peer.run(60.0)
    check(#BadTemplates(peer) == 0, tag .. " emits no sulphur / volcano systems")
    check(peer.Elysium.GetLevel() >= 1, tag .. " reports a level")
    peer.Elysium.Shutdown()
end

-- 4. Co-op: host announces, a guest follows the host's rung.
do
    local world = NewWorld()
    local sent = {}
    local host = StartPeer("host", world, { net = true }, { send = function(op, ...)
        sent[#sent + 1] = { op = op, args = { ... }, n = select("#", ...) }
    end })
    host.Elysium.AnnounceState()
    check(#sent >= 1 and sent[#sent].op == "VenusState", "AnnounceState sends VenusState")
    local guest = NewPeer("guest", world, { net = true })
    guest.Elysium.Init({ authority = false, sites = Sites("BD07"), bounds = BOUNDS })
    check(guest.Elysium.Seed == nil, "a guest has no seed until the host speaks")
    local last = sent[#sent]
    check(guest.Elysium.ApplyNetEvent(last.op, unpack(last.args, 1, last.n)) == true, "the guest accepts the host state")
    check(guest.Elysium.Seed == 4242, "the guest adopts the host seed")
    guest.run(10.0)
    host.Elysium.Shutdown()
    guest.Elysium.Shutdown()
end

if #failures > 0 then
    for _, message in ipairs(failures) do print("FAIL: " .. message) end
    print(string.format("%d expectation(s) failed", #failures))
    os.exit(1)
end

print("ELYSIUM WEATHER OK")
