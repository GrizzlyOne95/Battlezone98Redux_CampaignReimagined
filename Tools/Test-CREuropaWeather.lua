-- Test-CREuropaWeather.lua
--
-- Drives the real CRVenusMap (shared pure half), CREuropaWeather, CRWeather,
-- CRWeatherPresets and Environment modules against a stubbed exu and a stubbed
-- BZ Lua runtime. No game, no Ogre.
--
-- Usage, from the repository root:
--
--     lua5.1 Tools/Test-CREuropaWeather.lua Scripts
--
-- Every "peer" below is a fully isolated Lua environment with its own copy of
-- every module and its own globals, which is what a second machine is. Peers
-- share only a World table (the craft that exist) and the messages one sends
-- the other.
--
-- The stealth contract is enforced by AUDIT, not by hope: every function the
-- BZ and exu stubs expose is wrapped and recorded, and the suite asserts that
-- the set of calls the director (and the modules it drives) made is a subset of
-- a short allowlist of rendering / sound / earthquake calls, and that a long list
-- of damaging, retargeting, team, perception and sensor calls was never made.
--
-- Prints EUROPA WEATHER OK on success; prints each failed expectation and exits 1
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
local assertions = 0
local function check(condition, message)
    assertions = assertions + 1
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
        craft = options.craft ~= false, owner = options.owner or "host", team = options.team or 1,
        velocityWrites = 0,
    }
    world.order[#world.order + 1] = h
    return h
end

local sites = dofile(scriptDir .. "/CREuropaSites12.lua")
local BOUNDS = sites.bounds
local SHELF = 30.0

-- Synthetic terrain over misn12's real playable box: a flat shelf and one hill.
-- The BZN gives many geysers y = 0, so a director that trusted the data's y would
-- put their plumes 30 units underground; the shelf makes that visible.
local function SyntheticHeight(x, z)
    local hill = math.sqrt(((x - 3300.0) ^ 2) + ((z - 100300.0) ^ 2))
    if hill < 300.0 then return SHELF + (50.0 * (1.0 - (hill / 300.0))) end
    return SHELF
end

-- Anything that could hurt, move, create, remove, retarget, re-team or change
-- what anything can perceive. The director must call none of it.
local FORBIDDEN = {
    "Damage", "SetCurHealth", "AddHealth", "SetMaxHealth", "SetCurAmmo", "AddAmmo", "SetMaxAmmo",
    "MakeExplosion", "RemoveObject", "SetCurPilot", "Kill", "BuildObject", "SetVelocity", "SetOmega",
    "SetPosition", "SetTransform", "Stop", "Goto", "Attack", "SetCommand", "SetTeamNum", "SetLifespan",
    "Handle", "SetIndependence", "SetAvoidType", "Follow", "Defend", "Retreat", "Patrol", "Dropoff",
    "Pickup", "Service", "Mine", "Scavenge", "Hide", "Cloak", "Decloak", "SetCloaked",
    "SetPerceivedTeam", "SetCanSnipe", "SetObjectiveOn", "SetObjectiveOff", "SetObjectiveName",
    "SetUserTarget", "SetTarget", "SetScrap", "AddScrap", "SetPilot", "GiveWeapon", "SetWeaponMask",
    "StartEarthquakeAt", "FailMission", "SucceedMission", "SetAIP", "AddObjective", "UpdateObjective",
}
-- exu functions that touch sensors, physics, perception, health or position.
local FORBIDDEN_EXU_PATTERNS = {
    "Gravity", "Health", "Team", "Cloak", "Perceiv", "Stealth", "Target", "Command", "Position",
    "Scramble", "Damage", "Ammo", "Scrap", "Pilot", "Owner",
}
-- Radar / velocity-jam setters are Environment's identity sync pass; they are
-- audited by VALUE (SensorsUntouched), not banned by name. Particle setters are
-- cosmetic by definition.
-- Every global BZ function the director and the modules it drives may call.
local ALLOWED_GLOBALS = {
    GetTime = true, SetVector = true, GetPlayerHandle = true, IsValid = true, GetPosition = true,
    GetTerrainHeightAndNormal = true, StartSound = true, StartEarthquake = true,
    UpdateEarthQuake = true, StopEarthquake = true, IsNetGame = true, IsLocal = true,
    GetOdf = true, IsCraft = true, IsPerson = true, AllCraft = true, AllObjects = true,
}

local function NewPeer(name, world, options)
    options = options or {}
    local peer = {
        name = name, now = 0.0, world = world, loaded = {}, preload = {},
        playerPos = { x = 2790.0, y = SHELF, z = 99870.0 },
        sounds = {}, log = {}, quakeCalls = {}, sent = {},
        globalCalls = {}, exuCalls = {}, forbidden = {},
        rec = {
            systems = {}, fog = nil, ambient = nil, diffuse = nil, sunPower = nil,
            radarRange = {}, radarPeriod = {}, velocJam = {}, directions = {},
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
    exu.GetFog = function() return { r = 0.5, g = 0.5, b = 0.6, fogStart = 175, fogEnd = 300 } end
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
            rates = {}, peaks = {}, params = {}, created = peer.now,
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
            if r > (s.peaks[i] or 0) then s.peaks[i] = r end
        end
        return true
    end
    exu.SetParticleEmitterDirection = function(sysName, i, v)
        rec.directions[sysName] = rec.directions[sysName] or {}
        rec.directions[sysName][i] = v
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

    -- The exu audit: a proxy that records every function the modules look up
    -- and call. Lookups that return nil (an absent function) are not calls.
    local exuProxy = setmetatable({}, {
        __index = function(_, key)
            local f = exu[key]
            if type(f) == "function" then
                return function(...)
                    peer.exuCalls[key] = (peer.exuCalls[key] or 0) + 1
                    return f(...)
                end
            end
            return f
        end,
        __newindex = function(_, key, value) exu[key] = value end,
    })
    peer.preload["exu"] = exuProxy
    peer.preload["RuntimeEnhancements"] = {
        Initialize = function() end, Update = function() end, OnObjectCreated = function() end,
    }
    peer.preload["CRParticleTemplates"] = {
        Ensure = function() return true end,
        EnsureExtra = function(extra)
            if options.noEuropaTemplates then return false, "stub" end
            peer.extraRequested = extra
            return true, "stub"
        end,
    }

    -- ---- BZ runtime -----------------------------------------------------------
    env.GetTime = function() return peer.now end
    env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
    env.print = function() end
    env.StartSound = function(file, h, priority, loop, volume, rate)
        peer.sounds[#peer.sounds + 1] = { t = peer.now, file = file, handle = h, volume = volume, rate = rate }
    end
    env.GetPlayerHandle = function() return 1 end
    env.IsValid = function(h) return h == 1 or world.objects[h] ~= nil end
    env.GetPosition = function(h)
        if h == 1 then return UD(peer.playerPos) end
        local o = world.objects[h]
        if o then return UD({ x = o.x, y = o.y, z = o.z }) end
        return nil
    end
    env.GetOdf = function(h)
        local o = world.objects[h]
        return o and o.odf or ""
    end
    env.IsCraft = function(h) local o = world.objects[h]; return o ~= nil and o.craft end
    env.IsPerson = function() return false end
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
            peer.forbidden[#peer.forbidden + 1] = name .. ":" .. fn
        end
    end

    -- The stock earthquake natives (Docs/BZR_LUA_AGENT_REFERENCE.md), recorded so
    -- a test can see exactly what the engine would have been told, and when.
    env.StartEarthquake = function(m) peer.quakeCalls[#peer.quakeCalls + 1] = { t = peer.now, op = "start", mag = m } end
    env.UpdateEarthQuake = function(m) peer.quakeCalls[#peer.quakeCalls + 1] = { t = peer.now, op = "update", mag = m } end
    env.StopEarthquake = function() peer.quakeCalls[#peer.quakeCalls + 1] = { t = peer.now, op = "stop" } end

    -- The BZ audit: wrap every mock global (own keys of env) so each call is counted.
    local wrapped = {}
    for key, value in pairs(env) do
        if type(value) == "function" and key ~= "print" then wrapped[key] = value end
    end
    for key, value in pairs(wrapped) do
        env[key] = function(...)
            peer.globalCalls[key] = (peer.globalCalls[key] or 0) + 1
            return value(...)
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
    peer.Presets = load("CRWeatherPresets")
    peer.Eu = load("CREuropaWeather")
    peer.Map = load("CRVenusMap")
    peer.Environment.EnableVisualRuntime = false

    -- Initialise with the host's sender recording every event it emits.
    function peer.init(initOptions)
        initOptions = initOptions or {}
        initOptions.sites = initOptions.sites or sites
        if initOptions.send == nil and initOptions.authority ~= false and options.record ~= false then
            initOptions.send = function(op, ...)
                peer.sent[#peer.sent + 1] = { op = op, t = peer.now, args = { ... }, n = select("#", ...) }
                if peer.link then peer.link(op, ...) end
            end
        end
        peer.Environment.Init()
        peer.Eu.Init(initOptions)
    end

    function peer.step(dt)
        peer.now = peer.now + dt
        peer.Eu.Update(dt)
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

    function peer.events(op)
        local list = {}
        for _, m in ipairs(peer.sent) do if m.op == op then list[#list + 1] = m end end
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

local function SystemsOfTemplate(peer, template)
    local list = {}
    for sysName, s in pairs(peer.rec.systems) do
        if s.template == template then list[#list + 1] = sysName end
    end
    table.sort(list)
    return list
end

-- Every peer made in the run, so the final audit sees all of them.
local allPeers = {}
local function Track(peer)
    allPeers[#allPeers + 1] = peer
    return peer
end

-- Cosmetic means the sensors are Environment's own business: the global
-- gameplay scales stay at identity, no per-craft scramble exists and no
-- gameplay modifier is registered.
local function SensorsUntouched(peer)
    local env = peer.Environment
    local scales = env.GameplayScales
    if scales.radarRange ~= 1.0 or scales.radarPeriod ~= 1.0 or scales.velocJam ~= 1.0 then return false end
    if next(env.ObjectScrambles) ~= nil then return false end
    if next(env.GameplayModifiers) ~= nil then return false end
    -- (Environment's OWN night / time-of-day pass legitimately rewrites craft
    -- sensors with or without any weather director; section 11 compares the
    -- values against a control peer that has no director at all.)
    return true
end

local function Dist2(ax, az, bx, bz)
    return math.sqrt(((ax - bx) ^ 2) + ((az - bz) ^ 2))
end

local function VentIndex(map, label)
    local vents = map.GetVentSites()
    for i = 1, #vents do
        if vents[i].label == label then return i end
    end
    return nil
end

-- =============================================================================
-- 1. misn12 map data (CREuropaSites12, generated by Tools/Build-EuropaSites.py)
-- =============================================================================

local Probe = Track(NewPeer("probe", NewWorld()))
local Map = Probe.Map

do
    check(sites.mission == "misn12", "CREuropaSites12 should describe misn12")
    check(sites.materialLabels[0] == "Thin Ice" and sites.materialLabels[1] == "Frozen Tundra"
        and sites.materialLabels[2] == "Snowy Rock" and sites.materialLabels[3] == "Glacial",
        "the TextureType labels are the ones frost classification was based on")
    check(#sites.frost.types == 1 and sites.frost.types[1] == 1,
        "only TextureType 1 (Frozen Tundra) marks a place; Snowy Rock is 89% of the map")
    check(sites.frost.cols == 256 and sites.frost.rows == 256 and sites.frost.cell == 20,
        "misn12 mat is 256x256 cells of 20 units")
    check(sites.bounds.minX < sites.bounds.maxX and sites.bounds.minZ < sites.bounds.maxZ, "a playable box exists")
    check(sites.frost.solidCells == 1916, "misn12 has 1,916 Frozen Tundra cells, got " .. tostring(sites.frost.solidCells))

    -- Vents: the BZN's eggeizr1 geysers; the labels without the eggeizr prefix are
    -- the mission's named landmark geysers.
    check(#sites.vents == 16, "misn12 has 16 eggeizr1 geysers, got " .. #sites.vents)
    local major = 0
    local expectedMajor = {
        spawn_geyser = true, spawn_geyser1 = true, spawn_geyser2 = true,
        check2_geyser = true, center_geyser = true, choke_geyser = true,
    }
    for _, v in ipairs(sites.vents) do
        if v.major then
            major = major + 1
            check(expectedMajor[v.label], "only the named landmark geysers are major, saw " .. v.label)
        else
            check(string.match(v.label, "^eggeizr") ~= nil, "minor geysers are the eggeizr<N> ones, saw " .. v.label)
        end
        check(v.x >= sites.bounds.minX and v.x <= sites.bounds.maxX and v.z >= sites.bounds.minZ and v.z <= sites.bounds.maxZ,
            v.label .. " lies inside the playable box")
    end
    check(major == 6, "six geysers are named landmarks, got " .. major)
    local merged = Map.MergeVents(sites.vents, 45.0)
    check(#merged == 16, "no misn12 geysers sit within 45 units of each other, got " .. #merged)

    -- Frost anchors.
    local pools = sites.frost.pools
    check(#pools >= 60, "the frosted ground should carry plenty of haze anchors, got " .. #pools)
    local clusterIds, clusterCells = {}, 0
    for _, k in ipairs(sites.frost.clusters) do clusterIds[k.id] = true; clusterCells = clusterCells + k.count end
    check(clusterCells <= sites.frost.solidCells + 1916 and clusterCells > 1500, "clusters account for the frosted ground")
    local minSpacing, outside, weights = 1e9, 0, true
    local seen = {}
    for i, p in ipairs(pools) do
        if p.x < sites.bounds.minX or p.x > sites.bounds.maxX or p.z < sites.bounds.minZ or p.z > sites.bounds.maxZ then
            outside = outside + 1
        end
        if p.weight < 0.45 - 1e-6 or p.weight > 1.0 + 1e-6 then weights = false end
        check(p.cluster == 0 or clusterIds[p.cluster], "anchor " .. i .. " names a real cluster")
        local key = p.x .. ":" .. p.z
        check(not seen[key], "anchor " .. i .. " is not a duplicate")
        seen[key] = true
        for j = i + 1, #pools do
            minSpacing = math.min(minSpacing, Dist2(p.x, p.z, pools[j].x, pools[j].z))
        end
    end
    check(outside == 0, "no frost anchor lies outside the playable box, saw " .. outside)
    check(weights, "anchor weights are the local frost fraction, 0.45 .. 1")
    check(minSpacing >= 69.9, string.format("anchors are kept at least 70 units apart, closest %.1f", minSpacing))
end

-- =============================================================================
-- 2. Presets: cold, windless, no lightning, nothing else
-- =============================================================================

do
    local peer = Track(NewPeer("presets", NewWorld()))
    peer.init({ seed = 5 })
    local names = peer.Eu.GetPresetNames()
    check(#names == 5, "five Europa presets")
    local lastSun, lastEnd = 2.0, 1e9
    for i, presetName in ipairs(names) do
        local preset = peer.Presets.Get(presetName)
        check(preset ~= nil, presetName .. " is registered in CRWeatherPresets")
        check(preset.name == presetName, presetName .. " names itself")
        check(preset.lightning == nil, presetName .. " carries no lightning (no atmosphere)")
        check(preset.sky == nil, presetName .. " leaves the map's own sky alone")
        check(peer.Eu.Levels[i].preset == presetName, "ladder rung " .. i .. " selects " .. presetName)
        check(preset.fog.fogEnd <= 300.0, presetName .. " fog ends inside a plausible horizon")
        check(preset.fog.fogStart < preset.fog.fogEnd, presetName .. " fog start under end")
        check(preset.sunPowerScale <= lastSun, presetName .. " is no brighter than the rung below")
        check(preset.fog.fogEnd <= lastEnd, presetName .. " is no clearer than the rung below")
        lastSun, lastEnd = preset.sunPowerScale, preset.fog.fogEnd
        -- Cold ice under a black sky: a cold, dark haze, and the light left to
        -- Environment's orbit.
        check(preset.fog.b >= preset.fog.r, presetName .. ".fog is a cold colour")
        check(preset.fog.b <= 0.40, presetName .. ".fog stays dark under Europa's black sky")
        check(preset.ambient == nil and preset.diffuse == nil, presetName .. " leaves the light to Environment's orbit")
        -- No wind: straight down, one unit of speed so CRWeather's velocity scale stays 1.
        check(preset.wind.x == 0.0 and preset.wind.z == 0.0 and preset.wind.y < 0.0,
            presetName .. " has no horizontal wind")
        check(preset.windSpeed == 1.0, presetName .. " uses the unit wind speed")
        check(preset.gusts == nil, presetName .. " has no gusts")
        check(#preset.precipitation == 1, presetName .. " carries exactly one precipitation layer")
        local layer = preset.precipitation[1]
        check(layer.template == "CR/Europa/Glitter", presetName .. " uses the DX11-safe Europa glitter template")
        check(string.find(layer.system, "cr_wx_europa_", 1, true) == 1, "Europa layers use cr_wx_europa_ system names")
        check(layer.emitters[0].angle <= 8.0, presetName .. " ice falls near-vertically, not in a blown cone")
        check(layer.emitters[0].velocity[2] <= 3.0, presetName .. " ice falls slowly (low gravity)")
    end
    check(peer.CRWeather.GetPreset() == "EuropaQuiescent", "opens on EuropaQuiescent, got " .. tostring(peer.CRWeather.GetPreset()))
    check(peer.extraRequested == "cr_europa", "the director loads the cr_europa particle payload through EnsureExtra")
    check(peer.Eu.RegisterPresets() == 0, "registering the presets twice adds nothing")

    -- The wind is pinned straight down at the preset's own speed.
    local w = peer.CRWeather.WindOverride
    check(w ~= nil and w.x == 0.0 and w.z == 0.0 and w.y < 0.0, "the wind override points straight down")
    check(peer.CRWeather.WindOverrideSpeed == 1.0 and peer.CRWeather.WindVelocityScale == 1.0,
        "the wind override leaves CRWeather's velocity scale at exactly 1")

    -- And what is actually sent to the ice-glitter emitter is vertical.
    peer.run(40.0)
    local sys = peer.rec.systems["cr_wx_europa_ice"]
    check(sys ~= nil and (sys.rates[0] or 0) > 0, "the ice glitter layer is created and emitting")
    local dir = peer.rec.directions["cr_wx_europa_ice"] and peer.rec.directions["cr_wx_europa_ice"][0]
    check(dir ~= nil and near(dir.x, 0.0, 1e-9) and near(dir.z, 0.0, 1e-9) and dir.y < 0.0,
        "the ice glitter emitter points straight down: no wind drift")
    -- And it is not nudged sideways later, even deep into the busiest level.
    peer.Eu.ForceLevel(5, 500.0, 1.0)
    peer.run(120.0)
    dir = peer.rec.directions["cr_wx_europa_ice"][0]
    check(near(dir.x, 0.0, 1e-9) and near(dir.z, 0.0, 1e-9), "the ice still falls straight down at perijove")
    peer.Eu.Shutdown()
end

-- =============================================================================
-- 3. Ladder: levels, determinism, one rung at a time, beats
-- =============================================================================

do
    local L = Probe.Eu.Levels
    check(#L == 5, "five activity levels")
    for i = 2, #L do
        check(L[i].plumeScale > L[i - 1].plumeScale, "plume rate rises with level " .. i)
        check(L[i].maxPlumes >= L[i - 1].maxPlumes, "allowed simultaneous plumes never fall with level " .. i)
        check(L[i].quakeScale > L[i - 1].quakeScale, "quake rate rises with level " .. i)
        check(L[i].surgeScale > L[i - 1].surgeScale, "surge rate rises with level " .. i)
        check(L[i].glitter > L[i - 1].glitter, "ice glitter rises with level " .. i)
        check(L[i].visibility < L[i - 1].visibility, "visibility falls with level " .. i)
    end
end

local function LevelTrace(seed, target, seconds)
    local peer = Track(NewPeer("trace", NewWorld()))
    peer.init({ seed = seed, targetLevel = target })
    local trace, episodes = {}, 0
    for s = 1, seconds do
        peer.run(1.0, 0.5)
        trace[s] = peer.Eu.GetLevel()
        if peer.Eu.IsEpisode() then episodes = episodes + 1 end
    end
    peer.Eu.Shutdown()
    return trace, episodes
end

do
    local a = LevelTrace(7001, 3, 900)
    local b = LevelTrace(7001, 3, 900)
    local same = true
    for i = 1, #a do if a[i] ~= b[i] then same = false end end
    check(same, "the same seed gives the same activity timeline")
    local c = LevelTrace(7002, 3, 900)
    local differs = false
    for i = 1, #a do if a[i] ~= c[i] then differs = true end end
    check(differs, "a different seed gives a different timeline")

    local jumps = 0
    for i = 2, #a do if math.abs(a[i] - a[i - 1]) > 1 then jumps = jumps + 1 end end
    check(jumps == 0, "the ladder moves one rung at a time, saw " .. jumps .. " jumps")

    local _, episodes = LevelTrace(9, 4, 1800)
    check(episodes >= 0, "episodes are reported")

    -- Beats: SetTargetLevel trends; ForceLevel pins then releases.
    local peer = Track(NewPeer("beats", NewWorld()))
    peer.init({ seed = 31, targetLevel = 1 })
    peer.run(30.0)
    check(peer.Eu.GetLevel() == 1, "starts quiet")
    peer.Eu.ForceLevel(5, 60.0, 2.0)
    peer.run(5.0)
    check(peer.Eu.GetLevel() == 5, "ForceLevel pins perijove")
    check(peer.CRWeather.GetPreset() == "EuropaPerijove", "and selects its preset")
    peer.run(70.0)
    check(peer.Eu.ForcedLevel == nil, "the forced level expires on its own")
    peer.Eu.ForceLevel(4, 500.0)
    peer.Eu.ReleaseForcedLevel()
    check(peer.Eu.ForcedLevel == nil, "ReleaseForcedLevel releases it")
    check(peer.Eu.SetTargetLevel(9) == 5 and peer.Eu.SetTargetLevel(-3) == 1, "SetTargetLevel clamps to 1..5")
    peer.Eu.Shutdown()
end

-- =============================================================================
-- 4. Plumes: periodic, staggered, bounded, ice fall, terrain-snapped, cosmetic
-- =============================================================================

do
    local peer = Track(NewPeer("plumes", NewWorld()))
    local center = nil
    peer.init({ seed = 24681, startLevel = 3, targetLevel = 3 })
    local EU = peer.Eu
    center = VentIndex(EU, "center_geyser")
    check(center ~= nil and #EU.GetVentSites() == 16, "sixteen vent sites are built from the data")
    local site = EU.GetVentSites()[center]
    peer.playerPos = { x = site.x + 40.0, y = SHELF, z = site.z + 30.0 }

    peer.run(20.0)
    check(CountSystems(peer, "cr_ew_plume") >= 1, "plume systems stream in around the player")
    check(CountSystems(peer, "cr_ew_plume") <= EU.MaxLivePlumes, "plume systems respect their cap")
    for name, s in pairs(peer.rec.systems) do
        if s.template == "CR/Europa/Plume" then
            check(near(s.position.y, SHELF + 1.0, 0.01),
                "plumes sit on the real terrain, not on the BZN's y=0: " .. name .. " at y=" .. s.position.y)
        end
    end

    -- A long run at level 3: count, spacing, duration, cap.
    local peer2 = Track(NewPeer("plumes2", NewWorld()))
    peer2.init({ seed = 24681, startLevel = 3, targetLevel = 3 })
    peer2.Eu.AllowRandomQuakes = false
    peer2.Eu.ForceLevel(3, 1e6, 0.1)
    local active, maxActive, maxFall, minGap = 0, 0, 0, 1e9
    local lastStart = nil
    local seenStarts = {}
    peer2.playerPos = { x = site.x, y = SHELF, z = site.z }
    for _ = 1, 3600 do
        peer2.run(1.0, 0.5)
        local n = 0
        for _, e in ipairs(peer2.Eu.GetActivePlumes()) do
            if (peer2.Eu.Clock - e.start) < e.duration then n = n + 1 end
        end
        maxActive = math.max(maxActive, n)
        maxFall = math.max(maxFall, #SystemsOfTemplate(peer2, "CR/Europa/IceFall"))
    end
    local events = peer2.events("EuropaPlume")
    check(#events >= 40, "an hour of venting makes plenty of plumes, saw " .. #events)
    check(#events <= 160, "but not a constant barrage, saw " .. #events)
    local bySite = {}
    for i, m in ipairs(events) do
        local id, siteIndex, duration, power = m.args[1], m.args[2], m.args[3], m.args[4]
        check(duration >= 18.0 - 1e-6 and duration <= 40.0 + 1e-6, "plume duration is 18-40 s, saw " .. duration)
        check(power >= 0.7 - 1e-6 and power <= 1.3 + 1e-6, "plume power is 0.7-1.3, saw " .. power)
        check(siteIndex >= 1 and siteIndex <= 16, "plume site index is valid")
        bySite[siteIndex] = (bySite[siteIndex] or 0) + 1
        if lastStart then minGap = math.min(minGap, m.t - lastStart) end
        lastStart = m.t
        check(not seenStarts[id], "plume ids are unique")
        seenStarts[id] = true
    end
    check(minGap >= peer2.Eu.PlumeMinSpacing - 0.6, string.format("plumes never start closer than the spacing, closest %.2f", minGap))
    local sitesUsed = 0
    for _ in pairs(bySite) do sitesUsed = sitesUsed + 1 end
    check(sitesUsed >= 12, "most vents plume over an hour (staggered), " .. sitesUsed .. " of 16")
    check(maxActive <= 3, "no more than the level's allowance (3) run at once, saw " .. maxActive)
    check(maxActive >= 1, "some plumes ran")
    check(maxFall <= peer2.Eu.MaxLiveFall, "ice-fall systems stay within their cap")
    check(maxFall >= 1, "ice fall appears around an erupting vent the player is near")

    -- The first plume is not before the first-delay and the first minute is staggered, not one beat.
    local firstT = events[1] and events[1].t or 0
    check(firstT >= peer2.Eu.PlumeFirstDelay * 0.4, "no plume in the first few seconds, first at " .. firstT)

    -- Systems are all within the global budget.
    check(peer2.Eu.GetSystemCount() <= peer2.Eu.MaxSystems, "the particle budget is respected")

    -- One plume in detail: ice fall lags the column, outlives it, then is cleaned up.
    local lone = Track(NewPeer("lone", NewWorld()))
    lone.init({ seed = 77, startLevel = 1, targetLevel = 1 })
    lone.Eu.AllowPlumes = true
    lone.Eu.PlumeFirstDelay = 1e6
    local L = lone.Eu
    local ci = VentIndex(L, "center_geyser")
    local cs = L.GetVentSites()[ci]
    lone.playerPos = { x = cs.x + 20, y = SHELF, z = cs.z + 20 }
    for i = 1, #L.VentTimers do L.VentTimers[i] = 1e9 end
    lone.run(5.0)
    check(#SystemsOfTemplate(lone, "CR/Europa/IceFall") == 0, "no ice fall before any plume")
    check(L.TriggerPlume(ci, 1.0), "the host can trigger a plume on cue")
    local ev = lone.events("EuropaPlume")[1]
    check(ev ~= nil and ev.args[2] == ci, "and it is announced with the right site")
    local duration = ev.args[3]
    lone.run(2.0)
    local plumeName = nil
    for _, name in ipairs(SystemsOfTemplate(lone, "CR/Europa/Plume")) do
        local pos = lone.rec.systems[name].position
        if near(pos.x, cs.x, 0.01) and near(pos.z, cs.z, 0.01) then plumeName = name end
    end
    check(plumeName ~= nil and (lone.rec.systems[plumeName].peaks[1] or 0) > 20, "the column emitter is driven up by the plume")
    check(#SystemsOfTemplate(lone, "CR/Europa/IceFall") == 0, "the crystals have not reached the ground yet")
    lone.run(L.FallDelay + L.FallRise + 4.0)
    local fallName = SystemsOfTemplate(lone, "CR/Europa/IceFall")[1]
    check(fallName ~= nil, "ice then falls around the vent")
    check(#SystemsOfTemplate(lone, "CR/Europa/IceFall") == 1, "and only around the one erupting vent")
    if fallName then
        local fs = lone.rec.systems[fallName]
        check(near(fs.position.x, cs.x, 0.01) and near(fs.position.z, cs.z, 0.01), "ice falls over the vent")
        check(near(fs.position.y, SHELF + L.FallHeight, 0.01), "the footprint sits over the real ground")
        check((fs.rates[0] or 0) > 20, "ice is emitted")
    end
    local haze = L.GetVentHaze()
    check(haze > 0.05, "the player beside the vent is in its frost haze, haze=" .. haze)
    check(lone.rec.fog ~= nil and lone.rec.fog.fogEnd < 270.0 and lone.rec.fog.fogEnd > 40.0,
        "and the view thins there but never closes, fogEnd=" .. tostring(lone.rec.fog and lone.rec.fog.fogEnd))
    -- The column ends, the ice lingers.
    lone.run(duration)
    local colRate = plumeName and lone.rec.systems[plumeName] and lone.rec.systems[plumeName].rates[1]
    check(colRate ~= nil and colRate < 1.0, "the column has stopped after its duration")
    check(#SystemsOfTemplate(lone, "CR/Europa/IceFall") == 1, "but the ice is still falling after the column ends")
    lone.run(L.FallLinger + 10.0)
    check(#SystemsOfTemplate(lone, "CR/Europa/IceFall") == 0, "the ice system is destroyed once the fallout is over")
    check(#L.GetActivePlumes() == 0, "the plume is retired")
    check(L.GetVentHaze() < 0.001, "the haze clears")

    -- Far from the vent the fog is untouched.
    lone.playerPos = { x = cs.x + 2000, y = SHELF, z = cs.z }
    L.TriggerPlume(ci, 1.0)
    lone.run(20.0)
    check(L.GetVentHaze() < 0.001, "a player far from the vent sees no haze")
    lone.Eu.Shutdown()
end

-- =============================================================================
-- 5. Frost haze: streamed over frosted ground, bounded
-- =============================================================================

do
    local peer = Track(NewPeer("frost", NewWorld()))
    peer.init({ seed = 99, startLevel = 2, targetLevel = 2 })
    local a = sites.frost.pools[1]
    peer.playerPos = { x = a.x, y = SHELF, z = a.z }
    peer.run(30.0)
    local n = #SystemsOfTemplate(peer, "CR/Europa/FrostHaze")
    check(n >= 1 and n <= peer.Eu.MaxLiveFrost, "frost haze sheets stream in over frosted ground, within the cap (" .. n .. ")")
    for _, name in ipairs(SystemsOfTemplate(peer, "CR/Europa/FrostHaze")) do
        local s = peer.rec.systems[name]
        check(Dist2(s.position.x, s.position.z, a.x, a.z) <= peer.Eu.FrostStreamIn + 1, "a sheet is within the stream-in range")
        check(near(s.position.y, SHELF + peer.Eu.FrostHeight, 0.01), "sheets hang just over the real ground")
    end
    -- Far away: nothing.
    peer.playerPos = { x = 1000, y = SHELF, z = 97600 }
    peer.run(10.0)
    local far = #SystemsOfTemplate(peer, "CR/Europa/FrostHaze")
    check(far <= n, "moving away streams sheets out")
    peer.Eu.Shutdown()
    check(CountSystems(peer, "cr_ew_") == 0, "Shutdown destroys every system the director owns")

    local off = Track(NewPeer("frostoff", NewWorld()))
    off.init({ seed = 99, startLevel = 2, frostHaze = false })
    off.playerPos = { x = a.x, y = SHELF, z = a.z }
    off.run(20.0)
    check(#SystemsOfTemplate(off, "CR/Europa/FrostHaze") == 0, "frostHaze = false switches the sheets off")
    off.Eu.Shutdown()
end

-- =============================================================================
-- 6. Quakes: API, natives, ranges, rarity
-- =============================================================================

do
    local peer = Track(NewPeer("quake", NewWorld()))
    peer.init({ seed = 4242, startLevel = 2, targetLevel = 2, randomQuakes = false, randomSurges = false })
    local EU = peer.Eu
    peer.run(5.0)

    check(EU.Quake(0.8, 6.0), "a scripted quake begins")
    check(EU.IsQuaking(), "and is in progress")
    peer.run(0.5)
    peer.run(7.0)
    local starts, updates, stops = peer.calls("start"), peer.calls("update"), peer.calls("stop")
    check(#starts == 1 and #stops == 1, "the engine's quake is started and stopped exactly once")
    check(#updates >= 60, "and updated along the envelope, saw " .. #updates)
    local peak = 0
    for _, c in ipairs(updates) do peak = math.max(peak, c.mag) end
    check(near(peak, 0.8 * EU.QuakeMagnitudeScale, 0.15), string.format("the peak magnitude is strength x scale, %.2f", peak))
    check(EU.QuakeMagnitudeScale <= 3.0, "Europa quakes are no stronger than Io's scale")
    check(not EU.IsQuaking(), "the quake ends")
    check(near(starts[1].mag, EU.QuakeMinNative, 0.5), "it begins gently, not at full strength")

    -- Ice shaken loose rides the envelope and lingers briefly.
    EU.Quake(1.0, 6.0)
    peer.run(3.0)
    check(#SystemsOfTemplate(peer, "CR/Europa/QuakeIce") == 1, "frost shaken loose appears during a quake")
    local qs = peer.rec.systems[SystemsOfTemplate(peer, "CR/Europa/QuakeIce")[1]]
    check(qs.camera ~= nil, "and it is camera-attached")
    peer.run(15.0)
    check(#SystemsOfTemplate(peer, "CR/Europa/QuakeIce") == 0, "and is cleaned up after the quake")

    -- Ranges.
    peer.quakeCalls = {}
    EU.Quake(5.0, 500.0)
    local q = EU.GetQuake()
    check(q.strength == 1.0 and q.duration == 30.0, "strength and duration are clamped to 0..1 and 30 s")
    peer.run(1.0)
    EU.StopQuake()
    check(not EU.IsQuaking() and #peer.calls("stop") >= 1, "StopQuake ends a shake at once")
    check(EU.Quake(0.0, 3.0) == false, "a zero-strength quake is refused")

    -- Defaults.
    check(EU.Quake(), "Quake() with no arguments uses the defaults")
    local dq = EU.GetQuake()
    check(near(dq.strength, 0.5, 1e-9) and near(dq.duration, 4.0, 1e-9), "default quake is 0.5 for 4 s")
    peer.run(10.0)

    -- Merge: a second quake inside the first joins it; the native starts once.
    peer.quakeCalls = {}
    EU.Quake(0.4, 5.0)
    peer.run(1.0)
    EU.Quake(0.9, 5.0)
    peer.run(12.0)
    check(#peer.calls("start") == 1 and #peer.calls("stop") == 1, "overlapping quakes merge into one native shake")
    check(EU.GetStats().mergedQuakes >= 1, "and are counted as merged")

    -- A strong quake can open a vent; a weak one does not.
    local p0 = #peer.events("EuropaPlume")
    local qp0 = EU.GetStats().quakePlumes
    EU.Quake(0.2, 3.0)
    peer.run(10.0)
    check(#peer.events("EuropaPlume") == p0, "a weak tremor opens no vent")
    EU.Quake(0.9, 3.0)
    peer.run(10.0)
    check(#peer.events("EuropaPlume") == p0 + 1, "a strong quake cracks exactly one vent open")
    check(EU.GetStats().quakePlumes == qp0 + 1, "and counts it")
    peer.Eu.Shutdown()
end

do
    -- Random quakes are rare, gentle, spaced and in range.
    local peer = Track(NewPeer("randomquake", NewWorld()))
    peer.init({ seed = 31337, startLevel = 2, targetLevel = 2, randomSurges = false, plumes = false })
    peer.Eu.SetTargetLevel(2)
    local hours = 3
    peer.run(3600.0 * hours, 0.5)
    local events = peer.events("EuropaQuake")
    check(#events >= 8, "random quakes happen over three hours, saw " .. #events)
    check(#events <= 90, "but they are rare (the gap is minutes), saw " .. #events)
    local lastT = -1e9
    for _, m in ipairs(events) do
        local strength, duration, kind = m.args[2], m.args[3], m.args[4]
        check(strength >= 0.12 - 1e-6 and strength <= 0.70 + 1e-6, "random strength is 0.12-0.70, saw " .. strength)
        check(duration >= 2.0 - 1e-6 and duration <= 7.0 + 1e-6, "random duration is 2-7 s, saw " .. duration)
        check(kind == 2, "random quakes are kind 2")
        check(m.t - lastT >= 29.0, "quakes are at least 30 s apart")
        lastT = m.t
    end
    check(peer.Eu.GetStats().scriptedQuakes == 0, "no scripted quake counted")

    -- Higher level -> more quakes.
    local quiet = Track(NewPeer("qq", NewWorld()))
    quiet.init({ seed = 31337, startLevel = 1, targetLevel = 1, randomSurges = false, plumes = false, episodes = false })
    quiet.Eu.ForceLevel(1, 1e6)
    quiet.run(3600.0 * 2, 0.5)
    local busy = Track(NewPeer("qb", NewWorld()))
    busy.init({ seed = 31337, startLevel = 5, targetLevel = 5, randomSurges = false, plumes = false, episodes = false })
    busy.Eu.ForceLevel(5, 1e6)
    busy.run(3600.0 * 2, 0.5)
    check(#busy.events("EuropaQuake") > #quiet.events("EuropaQuake"),
        string.format("perijove quakes more than quiescent (%d vs %d)", #busy.events("EuropaQuake"), #quiet.events("EuropaQuake")))
    peer.Eu.Shutdown(); quiet.Eu.Shutdown(); busy.Eu.Shutdown()

    local off = Track(NewPeer("quakeoff", NewWorld()))
    off.init({ seed = 1, quakes = false })
    check(off.Eu.Quake(1.0, 5.0) == false, "quakes = false refuses a scripted quake")
    off.run(600.0, 0.5)
    check(#off.calls("start") == 0, "and never shakes")
    off.Eu.Shutdown()
end

-- =============================================================================
-- 7. Surges: visual only
-- =============================================================================

do
    local peer = Track(NewPeer("surge", NewWorld()))
    peer.init({ seed = 606, startLevel = 2, targetLevel = 2, randomQuakes = false, randomSurges = false, plumes = false })
    local EU = peer.Eu
    EU.ForceLevel(2, 1e6, 0.1)     -- hold the preset still so before / after compare
    peer.run(80.0)
    local baseAmbient = { r = peer.rec.ambient.r, g = peer.rec.ambient.g, b = peer.rec.ambient.b }
    local baseFog = { r = peer.rec.fog.r, g = peer.rec.fog.g, b = peer.rec.fog.b, e = peer.rec.fog.fogEnd }

    check(EU.Surge(6.0, 1.0), "a scripted surge begins")
    check(EU.IsSurging() and EU.GetSurge().strength == 1.0, "and is in progress")
    local peakLift, minLift, sawFlicker = 0, 1e9, false
    local lastDiffuse = nil
    local mid = nil
    for _ = 1, 40 do
        peer.run(0.15)
        local lift = peer.rec.ambient.b - baseAmbient.b
        peakLift = math.max(peakLift, lift)
        minLift = math.min(minLift, lift)
        if lastDiffuse and math.abs(peer.rec.diffuse.r - lastDiffuse) > 1e-4 then sawFlicker = true end
        lastDiffuse = peer.rec.diffuse.r
        if EU.GetSurgeIntensity() > 0.9 and mid == nil then mid = { fog = peer.rec.fog } end
    end
    check(peakLift > 0.03, string.format("a surge lifts the ambient light with an auroral cast, peak %.3f", peakLift))
    check(sawFlicker, "and flickers the light")
    check(mid ~= nil and mid.fog.g > baseFog.g - 1e-6 and mid.fog.fogEnd >= baseFog.e - 1e-6,
        "the fog takes a green cast but does not close in: a surge never reduces visibility")
    check(#SystemsOfTemplate(peer, "CR/Europa/SurgeMotes") == 1, "faint auroral motes appear")
    local sm = peer.rec.systems[SystemsOfTemplate(peer, "CR/Europa/SurgeMotes")[1]]
    check(sm.camera ~= nil, "motes are camera-attached")
    local crackle = 0
    for _, s in ipairs(peer.sounds) do if s.file == EU.SurgeSound then crackle = crackle + 1 end end
    check(crackle == 1, "one brief crackle plays, once, saw " .. crackle)
    for _, s in ipairs(peer.sounds) do check(s.handle == nil, "every sound is local and unattached to an object") end
    peer.run(12.0)
    check(not EU.IsSurging(), "the surge ends")
    check(#SystemsOfTemplate(peer, "CR/Europa/SurgeMotes") == 0, "motes are cleaned up")
    check(near(peer.rec.ambient.b, baseAmbient.b, 0.01), "and the light returns to normal")

    -- No sensor, perception or gameplay consequence of a surge.
    check(SensorsUntouched(peer), "a surge does not touch radar, velocity jam, scrambles or gameplay modifiers")

    -- Ranges / clamps / merge.
    EU.Surge(500.0, 5.0)
    local s = EU.GetSurge()
    check(s.strength == 1.0 and s.duration == 20.0, "surge strength and duration are clamped")
    peer.run(1.0)
    EU.Surge(3.0, 0.2)
    check(EU.GetStats().mergedSurges == 1, "overlapping surges merge")
    peer.run(30.0)
    check(EU.Surge(3.0, 0.0) == false, "a zero-strength surge is refused")
    check(EU.Surge() == true, "Surge() with no arguments uses defaults")
    check(near(EU.GetSurge().strength, 0.8, 1e-9) and near(EU.GetSurge().duration, 5.0, 1e-9), "default surge is 0.8 for 5 s")
    EU.AllowSurges = false
    peer.run(10.0)
    check(EU.Surge(3.0, 1.0) == false, "surges = false refuses a surge")
    EU.AllowSurges = true
    peer.Eu.Shutdown()

    -- Random surges: rare, in range, speed up with level.
    local r = Track(NewPeer("randsurge", NewWorld()))
    r.init({ seed = 818, startLevel = 3, targetLevel = 3, randomQuakes = false, plumes = false, episodes = false })
    r.Eu.ForceLevel(3, 1e6)
    r.run(3600.0 * 3, 0.5)
    local ev = r.events("EuropaSurge")
    check(#ev >= 8 and #ev <= 90, "random surges are occasional, saw " .. #ev)
    local last = -1e9
    for _, m in ipairs(ev) do
        check(m.args[2] >= 0.30 - 1e-6 and m.args[2] <= 1.0 + 1e-6, "random surge strength 0.3-1.0")
        check(m.args[3] >= 3.0 - 1e-6 and m.args[3] <= 9.0 + 1e-6, "random surge duration 3-9 s")
        check(m.args[4] == 2, "random surges are kind 2")
        check(m.t - last >= 39.0, "surges are at least 40 s apart")
        last = m.t
    end
    r.Eu.Shutdown()
end

-- =============================================================================
-- 8. Determinism: same seed, same host decisions
-- =============================================================================

local function HostScript(seed, extra)
    local peer = Track(NewPeer("det", NewWorld()))
    peer.init({ seed = seed, startLevel = 2, targetLevel = 3 })
    peer.playerPos = { x = 2500, y = SHELF, z = 99800 }
    if extra then extra(peer) end
    peer.run(3600.0, 0.5)
    local lines = {}
    for _, m in ipairs(peer.sent) do
        local parts = { m.op, string.format("%.3f", m.t) }
        for i = 1, m.n do parts[#parts + 1] = string.format("%.5f", m.args[i]) end
        lines[#lines + 1] = table.concat(parts, ",")
    end
    peer.Eu.Shutdown()
    return lines
end

do
    local a, b = HostScript(1234567), HostScript(1234567)
    check(#a > 30, "the host emits events")
    check(#a == #b, "two hosts with one seed emit the same number of events")
    local identical = true
    for i = 1, math.min(#a, #b) do if a[i] ~= b[i] then identical = false end end
    check(identical, "and the same events at the same times with the same numbers")
    local c = HostScript(7654321)
    local diff = #a ~= #c
    for i = 1, math.min(#a, #c) do if a[i] ~= c[i] then diff = true end end
    check(diff, "a different seed gives different events")

    -- The player's position does not change what the host decides.
    local d = HostScript(1234567, function(p) p.playerPos = { x = 1000, y = SHELF, z = 97600 } end)
    local same = #a == #d
    for i = 1, math.min(#a, #d) do if a[i] ~= d[i] then same = false end end
    check(same, "host decisions do not depend on where the local player is")

    -- The tidal phase is a pure function of the seed and the clock.
    local p1 = Track(NewPeer("tide1", NewWorld())); p1.init({ seed = 55 })
    local p2 = Track(NewPeer("tide2", NewWorld())); p2.init({ seed = 55 })
    local p3 = Track(NewPeer("tide3", NewWorld())); p3.init({ seed = 56 })
    p1.Eu.Clock, p2.Eu.Clock, p3.Eu.Clock = 123.0, 123.0, 123.0
    check(p1.Eu.GetTidalPhase() == p2.Eu.GetTidalPhase(), "the tidal phase agrees across peers with one seed")
    check(p1.Eu.GetTidalPhase() ~= p3.Eu.GetTidalPhase(), "and differs with another seed")
    local lo, hi = 1, 0
    for t = 0, 540 do
        p1.Eu.Clock = t
        local ph = p1.Eu.GetTidalPhase()
        lo, hi = math.min(lo, ph), math.max(hi, ph)
    end
    check(lo < 0.05 and hi > 0.95 and lo >= 0 and hi <= 1, "the tide swings the full 0..1 once per period")
    p1.Eu.Shutdown(); p2.Eu.Shutdown(); p3.Eu.Shutdown()
end

-- =============================================================================
-- 9. Co-op: the host decides, guests render the same events
-- =============================================================================

do
    local world = NewWorld()
    local hostPeer = Track(NewPeer("host", world, { net = true }))
    local guestPeer = Track(NewPeer("guest", world, { net = true }))
    local H, G = hostPeer.Eu, guestPeer.Eu
    hostPeer.playerPos = { x = 2760, y = SHELF, z = 99850 }
    guestPeer.playerPos = { x = 2790, y = SHELF, z = 99870 }
    AddObject(world, "avscav", 2760, SHELF, 99850, { owner = "host" })
    AddObject(world, "avscav", 2790, SHELF, 99870, { owner = "guest" })

    -- A delayed, ordered link from host to guest that can lose chosen ops.
    local LATENCY = 0.12
    local queue, dropStates = {}, false
    hostPeer.link = function(op, ...)
        if dropStates and op == "EuropaState" then return end
        queue[#queue + 1] = { at = hostPeer.now + LATENCY, op = op, args = { ... }, n = select("#", ...) }
    end

    hostPeer.init({ seed = 555777, authority = true, startLevel = 2, targetLevel = 3 })
    guestPeer.init({ authority = false, targetLevel = 3 })      -- no seed: waits for the host

    check(not G.Synced, "a guest with no seed must wait for the host rather than invent a timeline")
    check(hostPeer.sent[1] ~= nil and hostPeer.sent[1].op == "EuropaState", "the host announces its seed and state at start")

    local function Pump()
        local keep = {}
        for i = 1, #queue do
            local m = queue[i]
            if guestPeer.now >= m.at then
                G.ApplyNetEvent(m.op, unpack(m.args, 1, m.n))
            else
                keep[#keep + 1] = m
            end
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
    check(G.GetTidalPhase() ~= nil, "and so shares the tide")

    -- Scripted quake: one call on the host shakes both peers, together.
    RunBoth(10.0)
    hostPeer.quakeCalls, guestPeer.quakeCalls = {}, {}
    H.AllowRandomQuakes = false
    H.AllowRandomSurges = false
    check(H.Quake(0.9, 7.0), "the host's scripted quake begins")
    check(G.Quake(0.9, 7.0) == false, "a guest's own Quake() call is ignored (the host's event is the authority)")
    RunBoth(11.0)
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
    check(near(hp, gp, 0.15) and hp > 1.5, string.format("and with the same strength (host %.2f, guest %.2f)", hp, gp))

    -- Scripted surge and plume.
    check(H.Surge(5.0, 1.0), "the host's scripted surge begins")
    check(G.Surge(5.0, 1.0) == false, "a guest's own Surge() is ignored")
    RunBoth(1.5)
    check(G.IsSurging() and H.IsSurging(), "both peers are in the surge")
    check(near(G.GetSurgeIntensity(), H.GetSurgeIntensity(), 0.12), "with matching intensity")
    check(#SystemsOfTemplate(guestPeer, "CR/Europa/SurgeMotes") == 1, "the guest sees the auroral motes")
    RunBoth(10.0)
    local ci = VentIndex(H, "center_geyser")
    check(H.TriggerPlume(ci, 1.0), "the host triggers a plume")
    check(G.TriggerPlume(ci, 1.0) == false, "a guest's own TriggerPlume is ignored")
    RunBoth(12.0)
    check(#SystemsOfTemplate(guestPeer, "CR/Europa/Plume") >= 1, "the guest sees the plume it was told about")
    check(G.GetVentHaze() > 0.0 or #G.GetActivePlumes() >= 1, "and the guest's own haze follows")

    -- A long shared run: levels, plumes, quakes, surges match.
    H.AllowRandomQuakes, H.AllowRandomSurges = true, true
    H.NextQuakeAt, H.NextSurgeAt = H.Clock + 5.0, H.Clock + 8.0
    local mismatches, samples = 0, 0
    for _ = 1, 25 * 60 do
        RunBoth(1.0)
        samples = samples + 1
        if H.GetLevel() ~= G.GetLevel() then mismatches = mismatches + 1 end
    end
    check(mismatches <= samples * 0.02, string.format("guest rung must track the host (%d of %d seconds differ)", mismatches, samples))
    check(#hostPeer.events("EuropaPlume") > 15, "the host sent plume events, saw " .. #hostPeer.events("EuropaPlume"))
    check(near(G.GetStats().plumes, H.GetStats().plumes, 1), string.format("the guest renders the host's plumes (%d vs %d)", G.GetStats().plumes, H.GetStats().plumes))
    check(#hostPeer.events("EuropaQuake") >= 3, "the host sent random quakes")
    check(near(G.GetStats().quakes, H.GetStats().quakes, 1), string.format("the guest shakes for the host's quakes (%d vs %d)", G.GetStats().quakes, H.GetStats().quakes))
    check(near(G.GetStats().peakQuake, H.GetStats().peakQuake, 1e-9), "guest and host saw the same strongest quake")
    check(#hostPeer.events("EuropaSurge") >= 3, "the host sent random surges")
    check(near(G.GetStats().surges, H.GetStats().surges, 1), string.format("the guest shows the host's surges (%d vs %d)", G.GetStats().surges, H.GetStats().surges))
    check(near(G.GetStats().peakSurge, H.GetStats().peakSurge, 1e-9), "guest and host saw the same strongest surge")
    local hStarts, gStarts = hostPeer.calls("start"), guestPeer.calls("start")
    check(near(#hStarts, #gStarts, 1), "both peers drove the engine's quake the same number of times")
    local worst = 0
    for i = 1, math.min(#hStarts, #gStarts) do worst = math.max(worst, math.abs(hStarts[i].t - gStarts[i].t)) end
    check(worst < 0.3, string.format("every shake starts within the link latency on both peers, worst %.2f s", worst))

    -- The guest never decides anything of its own.
    local lonely = Track(NewPeer("lonely", world, { net = true }))
    lonely.init({ seed = 555777, authority = false, targetLevel = 4 })
    lonely.Eu.ForceLevel(5, 1000.0, 1.0)
    lonely.run(60.0 * 20.0, 0.5)
    check(lonely.Eu.GetStats().plumes == 0, "a guest decides no plumes; it only replays the host's")
    check(lonely.Eu.GetStats().quakes == 0 and #lonely.calls("start") == 0, "a guest decides no quakes")
    check(lonely.Eu.GetStats().surges == 0, "a guest decides no surges")
    check(lonely.Eu.ForceLevel(5, 10.0) == false, "a guest's ForceLevel is ignored")
    check(#lonely.sent == 0, "a guest sends nothing")

    -- Replaying events twice does nothing the second time.
    local sample = {}
    for _, m in ipairs(hostPeer.sent) do sample[m.op] = m end
    local before = { q = G.GetStats().quakes, p = G.GetStats().plumes, s = G.GetStats().surges }
    G.ApplyNetEvent("EuropaQuake", unpack(sample.EuropaQuake.args, 1, sample.EuropaQuake.n))
    G.ApplyNetEvent("EuropaPlume", unpack(sample.EuropaPlume.args, 1, sample.EuropaPlume.n))
    G.ApplyNetEvent("EuropaSurge", unpack(sample.EuropaSurge.args, 1, sample.EuropaSurge.n))
    check(G.GetStats().quakes == before.q and G.GetStats().plumes == before.p and G.GetStats().surges == before.s,
        "duplicated quake, plume and surge events are ignored")
    check(G.ApplyNetEvent("EuropaBogus") == false, "an unknown op is not handled")
    check(H.ApplyNetEvent("EuropaPlume", 999, 1, 20, 1) == true and H.GetStats().plumes == before.p + 0 + (H.GetStats().plumes - before.p),
        "the host ignores a replayed event addressed to it")

    -- Hostile input is clamped, not trusted.
    local fresh = Track(NewPeer("hostile", world, { net = true }))
    fresh.init({ seed = 3, authority = false })
    fresh.Eu.ApplyNetEvent("EuropaState", 3, 0, 1, 0, 3, 0, 0)
    fresh.Eu.ApplyNetEvent("EuropaQuake", 1, 99.0, 99999.0, 2)
    check(fresh.Eu.GetQuake().strength == 1.0 and fresh.Eu.GetQuake().duration == 30.0, "a guest clamps a hostile quake event")
    fresh.Eu.ApplyNetEvent("EuropaSurge", 1, 99.0, 99999.0, 2)
    check(fresh.Eu.GetSurge().strength == 1.0 and fresh.Eu.GetSurge().duration == 20.0, "and a hostile surge event")
    check(fresh.Eu.ApplyNetEvent("EuropaPlume", 1, 9999, 20, 1) == false, "and a plume at a site that does not exist")
    fresh.Eu.ApplyNetEvent("EuropaPlume", 2, 1, 99999.0, 99.0)
    check(fresh.Eu.GetActivePlumes()[1].duration == 90.0 and fresh.Eu.GetActivePlumes()[1].power == 2.0, "and clamps plume duration and power")
    fresh.Eu.Shutdown()

    -- Losing every state message after the first still leaves the guest tracking.
    dropStates = true
    H.SetTargetLevel(2)
    RunBoth(200.0)
    local lag = 0
    for _ = 1, 120 do
        RunBoth(1.0)
        if H.GetLevel() ~= G.GetLevel() then lag = lag + 1 end
    end
    check(lag <= 40, "the guest keeps following the seeded timeline when state messages are lost, differed " .. lag .. "/120 s")
    dropStates = false

    -- A guest that initialised late is caught up by AnnounceState.
    local late = Track(NewPeer("late", world, { net = true }))
    late.init({ authority = false, targetLevel = 4 })
    check(not late.Eu.Synced, "a late guest starts unsynced")
    local before2 = #hostPeer.sent
    H.AnnounceState()
    check(#hostPeer.sent == before2 + 1 and hostPeer.sent[#hostPeer.sent].op == "EuropaState", "AnnounceState re-sends the state on demand")
    local m = hostPeer.sent[#hostPeer.sent]
    late.Eu.ApplyNetEvent(m.op, unpack(m.args, 1, m.n))
    check(late.Eu.Synced and late.Eu.Seed == 555777, "the late guest syncs from the announcement")

    for _, o in pairs(world.objects) do check(o.velocityWrites == 0, "no craft was moved on either peer") end
    check(SensorsUntouched(hostPeer) and SensorsUntouched(guestPeer), "no sensors were changed on either peer")
    H.Shutdown(); G.Shutdown(); lonely.Eu.Shutdown(); late.Eu.Shutdown()
end

-- =============================================================================
-- 10. Degradation, solo, save / load
-- =============================================================================

do
    -- A build that has not shipped the cr_europa payload still gets presets and quakes.
    local peer = Track(NewPeer("notemplates", NewWorld(), { noEuropaTemplates = true }))
    peer.init({ seed = 11, startLevel = 3, targetLevel = 3 })
    peer.run(120.0)
    check(CountSystems(peer, "cr_ew_") == 0, "without the payload there are no director particle systems")
    check(peer.CRWeather.GetPreset() ~= nil, "presets still work without the payload")
    check(peer.Eu.Quake(0.7, 3.0), "quakes still work without the payload")
    peer.run(5.0)
    check(#peer.calls("start") == 1 and #peer.calls("stop") == 1, "and still drive the engine's quake")
    peer.Eu.Shutdown()

    -- A failing template is disabled after three tries instead of retrying forever.
    local failing = Track(NewPeer("failing", NewWorld(), { failTemplate = "CR/Europa/FrostHaze" }))
    local a = sites.frost.pools[1]
    failing.playerPos = { x = a.x, y = SHELF, z = a.z }
    failing.init({ seed = 12 })
    failing.run(40.0)
    check(failing.Eu.TemplateFailures["CR/Europa/FrostHaze"] == failing.Eu.MaxFailuresPerTemplate,
        "a failing template is given up on after three tries")
    failing.Eu.Shutdown()

    -- Offline solo is the host path with no sender.
    local solo = Track(NewPeer("solo", NewWorld(), { record = false }))
    solo.init({ seed = 31415, targetLevel = 4 })
    check(solo.Eu.IsAuthority and solo.Eu.Synced and solo.Eu.NetSend == nil, "offline is the authority and sends nothing")
    solo.run(60.0 * 20.0, 0.5)
    check(solo.Eu.GetStats().plumes > 0 and solo.Eu.GetStats().quakes >= 1, "offline weather vents and quakes")
    solo.Eu.Shutdown()

    -- Save / load.
    local a1 = Track(NewPeer("save", NewWorld()))
    a1.init({ seed = 8080, targetLevel = 4 })
    a1.Eu.ForceLevel(4, 500.0, 0.5)
    a1.run(120.0)
    a1.Eu.Quake(0.9, 30.0)
    a1.Eu.Surge(10.0, 1.0)
    a1.run(2.0)
    local state = a1.Eu.Save()
    check(state.seed == 8080 and state.level == 4 and state.forcedLevel == 4 and state.quakeSerial == 1 and state.surgeSerial == 1,
        "Save captures the director's scalars")
    for k, v in pairs(state) do
        check(type(v) == "number" or type(v) == "table" or type(v) == "string" or type(v) == "boolean",
            "Save holds only plain data: " .. k)
    end
    local b = Track(NewPeer("load", NewWorld()))
    b.init({ seed = 1 })
    b.Eu.Load(state)
    b.run(1.0)
    check(b.Eu.Seed == 8080 and b.Eu.GetLevel() == 4 and b.Eu.ForcedLevel == 4, "Load restores the seed, rung and forced level")
    check(b.Eu.QuakeSerial == 1 and b.Eu.SurgeSerial == 1, "Load restores the serials so ids never collide")
    check(#b.calls("stop") >= 1 and #b.calls("start") == 0, "Load stops any quake the engine replays and does not start one")
    check(not b.Eu.IsQuaking() and not b.Eu.IsSurging(), "a quake or surge in progress at save time is not resumed")
    check(CountSystems(b, "cr_ew_ice") == 0, "no stale systems survive a load")
    b.Eu.Shutdown(); a1.Eu.Shutdown()

    -- Shutdown stops a shake in progress.
    local s = Track(NewPeer("shut", NewWorld()))
    s.init({ seed = 2 })
    s.Eu.Quake(1.0, 20.0)
    s.run(3.0)
    s.Eu.Shutdown()
    check(#s.calls("stop") >= 1, "Shutdown stops the engine's quake")
    check(s.Environment.Modifiers["CREuropaWeather"] == nil, "Shutdown unregisters the Environment modifier")
end

-- =============================================================================
-- 11. STEALTH AUDIT: the director has no gameplay effect whatsoever
-- =============================================================================

do
    -- A dedicated, busy host run with a rival craft on each team standing in the
    -- middle of the action: nothing may touch it.
    local world = NewWorld()
    local tank = AddObject(world, "avtank", 2770, SHELF, 99860, { owner = "host", team = 1 })
    local enemy = AddObject(world, "svfigh", 2750, SHELF, 99840, { owner = "host", team = 2 })
    local peer = Track(NewPeer("stealth", world))
    peer.init({ seed = 808, startLevel = 5, targetLevel = 5 })
    peer.Eu.ForceLevel(5, 1e6)
    peer.playerPos = { x = 2770, y = SHELF, z = 99860 }
    for _ = 1, 40 do
        peer.Eu.Surge(6.0, 1.0)
        peer.Eu.Quake(1.0, 6.0)
        peer.Eu.TriggerPlume(VentIndex(peer.Eu, "center_geyser"), 1.5)
        peer.run(60.0, 0.25)
    end
    check(peer.Eu.GetStats().plumes > 40 and peer.Eu.GetStats().surges > 20 and peer.Eu.GetStats().quakes > 20,
        "the stealth run exercised plumes, surges and quakes")
    check(#peer.forbidden == 0, "no damaging, moving, retargeting, re-teaming, perception or objective function was called: " .. tostring(peer.forbidden[1]))
    check(SensorsUntouched(peer), "radar, velocity jam, scrambles and gameplay modifiers are untouched")
    check(world.objects[tank].velocityWrites == 0 and world.objects[enemy].velocityWrites == 0, "no craft was moved")
    check(world.objects[tank].team == 1 and world.objects[enemy].team == 2, "no team changed")

    -- Control: the same world and clock with NO director. Every sensor value
    -- Environment wrote must be identical, so none of it is the director's.
    local controlWorld = NewWorld()
    AddObject(controlWorld, "avtank", 2770, SHELF, 99860, { owner = "host", team = 1 })
    AddObject(controlWorld, "svfigh", 2750, SHELF, 99840, { owner = "host", team = 2 })
    local control = Track(NewPeer("control", controlWorld))
    control.Environment.Init()
    for _ = 1, 40 * 240 do control.now = control.now + 0.25; control.Environment.Update(0.25) end
    local compared = 0
    for h, v in pairs(peer.rec.radarRange) do
        compared = compared + 1
        check(near(control.rec.radarRange[h] or -1, v, 1e-9), "radar range of craft " .. h .. " matches a peer with no director")
        check(near(control.rec.radarPeriod[h] or -1, peer.rec.radarPeriod[h], 1e-9), "radar period matches the control")
        check(near(control.rec.velocJam[h] or -1, peer.rec.velocJam[h], 1e-9), "velocity jam matches the control")
    end
    check(compared == 2, "both craft's sensors were compared with the control, got " .. compared)
    peer.Eu.Shutdown()
end

do
    -- Light snow on the cockpit glass (CRWetGlass.Weather): a low, slowly varying level that follows the
    -- activity ladder, eased, switchable, and released at Shutdown.
    local function GlassPeer(name, options)
        local g = { snow = 0, updates = 0, stops = 0, calls = 0 }
        local peer = Track(NewPeer(name, NewWorld()))
        peer.preload["CRWetGlass"] = {
            Weather = function(kind, level) if kind == "snow" then g.snow = level; g.calls = g.calls + 1 end end,
            Busy = function() return g.snow > 0 end,
            Update = function(i) g.updates = g.updates + 1; g.rain = i end,
            Splat = function() g.splats = (g.splats or 0) + 1 end,
            Stop = function() g.stops = g.stops + 1 end,
        }
        peer.init(options)
        return peer, g
    end
    local RATE = 0.04
    local peer, g = GlassPeer("glasssnow", { seed = 99, startLevel = 1, targetLevel = 1 })
    peer.Eu.ForceLevel(1, 1e6, 0.1)
    local dt, prev, worst = 0.25, 0, 0
    for _ = 1, 480 do
        peer.step(dt)
        worst = math.max(worst, math.abs(g.snow - prev)); prev = g.snow
    end
    local quiet = g.snow
    check(quiet > 0.1 and quiet < 0.35, string.format("a quiet Europa has a light snow level, got %.3f", quiet))
    check(worst <= RATE * dt + 1e-9, string.format("snow level is eased (largest step %.5f)", worst))
    check(g.rain == 0, "snow never drives the rain layers")
    check(g.updates > 400, "the glass is kept updated while snow is on it")
    check(near(peer.Eu.GetGlassSnow(), g.snow, 1e-9), "GetGlassSnow reports the level")
    peer.Eu.ForceLevel(5, 1e6, 0.1)
    for _ = 1, 4 * 240 do peer.step(dt) end
    check(g.snow > quiet + 0.1 and g.snow < 0.8, string.format("perijove snows more but stays light, got %.3f vs %.3f", g.snow, quiet))
    -- It breathes slowly rather than sitting at one number.
    local a, b = 1, 0
    for _ = 1, 2 * 170 * 4 do
        peer.step(dt)
        a, b = math.min(a, g.snow), math.max(b, g.snow)
    end
    check(b - a > 0.02 and b - a < 0.2, string.format("the level varies slowly, spread %.3f", b - a))
    peer.Eu.Shutdown()
    check(g.snow == 0 and g.stops >= 1, "Shutdown releases the cockpit-glass layers")

    local off, go = GlassPeer("glasssnowoff", { seed = 99, startLevel = 5, targetLevel = 5, glassSnow = false })
    off.run(120.0, dt)
    check(go.snow == 0 and go.updates == 0, "glassSnow = false keeps the glass clear and idle")
    off.Eu.Shutdown()

    local lowq, gq = GlassPeer("glasssnowq", { seed = 99, startLevel = 5, targetLevel = 5, quality = 0 })
    lowq.run(120.0, dt)
    check(gq.snow == 0, "CRWeather quality 0 keeps the glass clear")
    lowq.Eu.Shutdown()

    local disabled, gd = GlassPeer("glasssnowdis", { seed = 99, enabled = false })
    disabled.run(60.0, dt)
    check(gd.snow == 0 and gd.updates == 0, "a disabled director never touches the glass")
    disabled.Eu.Shutdown()
end

do
    -- Everything the whole run called, on every peer, against the allowlists.
    local calledGlobals, calledExu = {}, {}
    local forbiddenTotal = 0
    for _, peer in ipairs(allPeers) do
        for k in pairs(peer.globalCalls) do calledGlobals[k] = true end
        for k in pairs(peer.exuCalls) do calledExu[k] = true end
        forbiddenTotal = forbiddenTotal + #peer.forbidden
    end
    check(forbiddenTotal == 0, "no peer in the whole suite called a forbidden function, saw " .. forbiddenTotal)
    local sawGlobal = 0
    for k in pairs(calledGlobals) do
        sawGlobal = sawGlobal + 1
        check(ALLOWED_GLOBALS[k], "the director and its modules only call allowlisted BZ functions; saw " .. k)
    end
    check(sawGlobal >= 5, "the audit actually recorded calls (" .. sawGlobal .. ")")
    check(calledGlobals.StartEarthquake and calledGlobals.UpdateEarthQuake and calledGlobals.StopEarthquake,
        "the stock earthquake natives are what shakes the view")
    local exuCount = 0
    for k in pairs(calledExu) do
        exuCount = exuCount + 1
        for _, pattern in ipairs(FORBIDDEN_EXU_PATTERNS) do
            check(not string.find(k, pattern, 1, true), "exu." .. k .. " matches the forbidden pattern " .. pattern)
        end
    end
    check(exuCount >= 8, "the exu audit recorded calls (" .. exuCount .. ")")

    -- Source check: the director's code does not even mention the dangerous names.
    local handle = io.open(scriptDir .. "/CREuropaWeather.lua", "rb")
    local source = handle:read("*a")
    handle:close()
    local stripped = source:gsub("%-%-[^\n]*", "")
    for _, word in ipairs({ "SetCurHealth", "AddHealth", "Damage", "SetVelocity", "SetCurAmmo", "AddAmmo", "SetGravity",
                            "MakeExplosion", "RemoveObject", "BuildObject", "SetRadarRange", "SetRadarPeriod", "SetVelocJam",
                            "RegisterGameplayModifier", "SetObjectScramble", "SetPosition(", "SetCommand", "SetPerceivedTeam",
                            "SetTeamNum", "Attack", "Goto", "Cloak", "SetUserTarget", "SetObjective", "GameplayScales",
                            "exu.SetFog", "exu.SetAmbient", "exu.SetSun" }) do
        check(not string.find(stripped, word, 1, true), "CREuropaWeather.lua must not mention " .. word)
    end
    for _, word in ipairs({ "StartEarthquake", "UpdateEarthQuake", "StopEarthquake" }) do
        check(string.find(stripped, word, 1, true) ~= nil, "CREuropaWeather.lua uses the stock " .. word .. " native")
    end
    check(string.find(stripped, "pcall%(StartSound, file, nil,") ~= nil, "the one StartSound call passes no object handle")
end

-- =============================================================================
-- Report
-- =============================================================================

if #failures > 0 then
    for _, message in ipairs(failures) do print("FAIL: " .. message) end
    print(string.format("%d of %d expectation(s) failed", #failures, assertions))
    os.exit(1)
end

print(string.format("EUROPA WEATHER OK (%d assertions)", assertions))
