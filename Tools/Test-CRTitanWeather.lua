-- Test-CRTitanWeather.lua
--
-- Drives the real CRVenusMap (shared pure half), CRTitanWeather, CRWeather,
-- CRWeatherPresets and Environment modules against a stubbed exu and a stubbed
-- BZ Lua runtime. No game, no Ogre.
--
-- Usage, from the repository root:
--
--     lua5.1 Tools/Test-CRTitanWeather.lua Scripts
--
-- Every "peer" is a fully isolated Lua environment with its own copy of every
-- module and its own globals, which is what a second machine is. Peers share
-- only a World table (the craft that exist) and the messages one sends the other.
--
-- The no-gameplay contract is enforced by AUDIT: every function the BZ and exu
-- stubs expose is wrapped and recorded, and the suite asserts that the set of
-- calls the director (and the modules it drives) made is a subset of a short
-- allowlist, and that a long list of damaging, moving, retargeting, team,
-- perception and sensor calls was never made.
--
-- Prints TITAN WEATHER OK on success; prints each failed expectation and exits 1
-- otherwise.

local scriptDir = ... or "Scripts"
local repoRoot = scriptDir:gsub("[/\\]?Scripts$", "")
if repoRoot == "" then repoRoot = "." end

local failures = {}
local assertions = 0
local function check(condition, message)
    assertions = assertions + 1
    if not condition then failures[#failures + 1] = message end
end

local function near(a, b, tolerance)
    return math.abs(a - b) <= tolerance
end

local sites = dofile(scriptDir .. "/CRTitanSites14.lua")
local SEA = sites.sea.level

-- =============================================================================
-- A synthetic world over misn14's real playable box
-- =============================================================================

local function NewWorld()
    return { objects = {}, order = {}, serial = 0 }
end

local function AddObject(world, odf, x, y, z, options)
    options = options or {}
    world.serial = world.serial + 1
    local h = world.serial + 1000
    world.objects[h] = { h = h, odf = odf, x = x, y = y, z = z, craft = options.craft ~= false,
        owner = options.owner or "host", team = options.team or 1 }
    world.order[#world.order + 1] = h
    return h
end

-- The terrain answers from the generated wet mask: wet cells are the flat sea
-- floor at SEA, everything else is an island 12 units higher. That is enough for
-- the director's terrain queries to agree with the static data.
local IsWetStatic
do
    local rows, cell, ox, oz = sites.wet.rows, sites.sea.cell, sites.sea.originX, sites.sea.originZ
    IsWetStatic = function(x, z)
        local row = rows[math.floor((z - oz) / cell)]
        if row == nil then return false end
        local col = math.floor((x - ox) / cell)
        for i = 1, #row - 1, 2 do
            if col >= row[i] and col < row[i] + row[i + 1] then return true end
        end
        return false
    end
end
local function SyntheticHeight(x, z)
    if IsWetStatic(x, z) then return SEA end
    return SEA + 12.0
end

-- A wet point and a dry point inside the playable box, found from the data.
local WET_POINT, DRY_POINT, WADE_POINT
do
    -- The best anchor sits on a shore, so dry ground is a cell or two away.
    WET_POINT = { x = sites.pools[1].x, z = sites.pools[1].z }
    -- Open liquid near the wet point: five wet cells in a row, for a wader.
    for dz = -200, 200, 20 do
        for dx = -200, 200, 20 do
            local x, z = WET_POINT.x + dx, WET_POINT.z + dz
            local open = true
            for k = -2, 2 do
                if not IsWetStatic(x + (k * 20), z) then open = false end
            end
            if open and WADE_POINT == nil then WADE_POINT = { x = x, z = z } end
        end
    end
    -- The nearest dry cell to the wet point, so a craft there is in splash range.
    local best
    for dz = -200, 200, 20 do
        for dx = -200, 200, 20 do
            local x, z = WET_POINT.x + dx, WET_POINT.z + dz
            local d = dx * dx + dz * dz
            if not IsWetStatic(x, z) and (best == nil or d < best) then
                best, DRY_POINT = d, { x = x, z = z }
            end
        end
    end
end

-- A stock misn14.trn, as Environment would read it through the ODF natives.
local TITAN_TRN = {
    NormalView = { Time = 1000, FogStart = 50, FogEnd = 175, VisibilityRange = 250, Intensity = 50, Ambient = 0 },
    Atlases = { MaterialName = "ti_detail_atlas" },
    Sky = { SkyTexture = "titan.map" },
    Color = { Palette = "TITAN.ACT" },
}
local EARTH_TRN = {
    NormalView = { Time = 1200, FogStart = 200, FogEnd = 250, VisibilityRange = 250, Intensity = 128, Ambient = 96 },
    Atlases = { MaterialName = "ma_detail_atlas" },
    Sky = { SkyTexture = "mars.map" },
    Color = { Palette = "MARS.ACT" },
}

local FORBIDDEN = {
    "Damage", "SetCurHealth", "AddHealth", "SetMaxHealth", "SetCurAmmo", "AddAmmo", "SetMaxAmmo",
    "MakeExplosion", "RemoveObject", "SetCurPilot", "Kill", "BuildObject", "SetVelocity", "SetOmega",
    "SetPosition", "SetTransform", "Stop", "Goto", "Attack", "SetCommand", "SetTeamNum", "SetLifespan",
    "SetIndependence", "SetAvoidType", "Follow", "Defend", "Retreat", "Patrol", "Dropoff",
    "Pickup", "Service", "Mine", "Scavenge", "Hide", "Cloak", "Decloak", "SetCloaked",
    "SetPerceivedTeam", "SetCanSnipe", "SetObjectiveOn", "SetObjectiveOff", "SetObjectiveName",
    "SetUserTarget", "SetTarget", "SetScrap", "AddScrap", "SetPilot", "GiveWeapon", "SetWeaponMask",
    "StartEarthquake", "UpdateEarthQuake", "StopEarthquake", "FailMission", "SucceedMission", "SetAIP",
    "AddObjective", "UpdateObjective", "SetGravity",
}
local FORBIDDEN_EXU_PATTERNS = {
    "Gravity", "Health", "Team", "Cloak", "Perceiv", "Stealth", "Target", "Command", "Velocity$",
    "Scramble", "Damage", "Ammo", "Scrap", "Pilot", "Owner", "Radar", "VelocJam",
}
-- Every global BZ function the director and the modules it drives may call.
local ALLOWED_GLOBALS = {
    GetTime = true, SetVector = true, GetPlayerHandle = true, IsValid = true, GetPosition = true,
    GetTerrainHeightAndNormal = true, IsNetGame = true, IsLocal = true, GetOdf = true, IsCraft = true,
    IsPerson = true, AllCraft = true, AllObjects = true, GetMapTRNFilename = true, OpenODF = true,
    GetODFString = true, GetODFInt = true, GetODFFloat = true, GetMissionFilename = true,
}

local function NewPeer(name, world, options)
    options = options or {}
    local peer = {
        name = name, now = 0.0, world = world, loaded = {}, preload = {},
        playerPos = { x = WET_POINT.x, y = SEA + 2.0, z = WET_POINT.z },
        sent = {}, globalCalls = {}, exuCalls = {}, forbidden = {},
        rec = { systems = {}, fog = nil, ambient = nil, diffuse = nil, sunPower = nil, radar = {}, jam = {} },
    }
    local rec = peer.rec

    local env = setmetatable({}, { __index = _G })
    env._G = env
    peer.env = env

    -- ---- exu ----------------------------------------------------------------
    local exu = {}
    setmetatable(exu, { __index = function(_, key)
        if type(key) == "string" and (key:match("^SetParticle") or key:match("^Detach")) then
            return function() return true end
        end
        return nil
    end })
    exu.GetFog = function() return { r = 0.50, g = 0.40, b = 0.30, fogStart = 50, fogEnd = 175 } end
    exu.SetFog = function(r, g, b, s, e) rec.fog = { r = r, g = g, b = b, fogStart = s, fogEnd = e } return true end
    exu.GetAmbientLight = function() return { r = 0.0, g = 0.0, b = 0.0 } end
    exu.SetAmbientLight = function(r, g, b) rec.ambient = { r = r, g = g, b = b } return true end
    exu.GetSunDiffuse = function() return { r = 0.2, g = 0.2, b = 0.2 } end
    exu.SetSunDiffuse = function(r, g, b) rec.diffuse = { r = r, g = g, b = b } return true end
    exu.GetSunSpecular = function() return { r = 0.3, g = 0.3, b = 0.3 } end
    exu.SetSunSpecular = function() return true end
    exu.GetSunDirection = function() return { x = 0, y = -1, z = 0 } end
    exu.SetOgreSunDirection = function(v) rec.sunDir = v return true end
    exu.GetSunPowerScale = function() return 1.0 end
    exu.SetSunPowerScale = function(v) rec.sunPower = v return true end
    exu.GetSunShadowFarDistance = function() return 900 end
    exu.SetSunShadowFarDistance = function() return true end
    exu.SetViewportShadowsEnabled = function() return true end
    exu.GetRadarRange = function(h) return rec.radar[h] or 400.0 end
    exu.SetRadarRange = function(h, v) rec.radar[h] = v return true end
    exu.GetRadarPeriod = function() return 1.0 end
    exu.SetRadarPeriod = function() return true end
    exu.GetVelocJam = function(h) return rec.jam[h] or 10.0 end
    exu.SetVelocJam = function(h, v) rec.jam[h] = v return true end

    exu.HasParticleTemplate = function() return true end
    exu.CreateParticleSystem = function(sysName, template, position)
        if rec.systems[sysName] ~= nil then return false end
        if options.failTemplate and template == options.failTemplate then return false end
        rec.systems[sysName] = { template = template, position = position, rates = {}, peaks = {},
            emitting = true, visible = true, created = peer.now }
        return true
    end
    exu.DestroyParticleSystem = function(sysName)
        if rec.systems[sysName] == nil then return false end
        rec.systems[sysName] = nil
        return true
    end
    exu.HasParticleSystem = function(sysName) return rec.systems[sysName] ~= nil end
    exu.SetParticleSystemPosition = function(sysName, v)
        if rec.systems[sysName] then rec.systems[sysName].position = v end
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
    exu.SetParticleSystemEmitting = function(sysName, on)
        if rec.systems[sysName] then rec.systems[sysName].emitting = on end
        return true
    end
    exu.SetParticleSystemVisible = function(sysName, on)
        if rec.systems[sysName] then rec.systems[sysName].visible = on end
        return true
    end
    exu.UpdateParticleFollowers = function() return 0 end

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
    peer.exu = exu
    peer.preload["exu"] = exuProxy
    peer.preload["RuntimeEnhancements"] = {
        Initialize = function() end, Update = function() end, OnObjectCreated = function() end,
    }
    peer.preload["CRParticleTemplates"] = {
        Ensure = function() return true end,
        EnsureExtra = function(extra)
            if options.noTemplates then return false, "stub" end
            peer.extraRequested = extra
            return true, "stub"
        end,
    }

    -- ---- BZ runtime -----------------------------------------------------------
    local trn = options.trn
    env.GetTime = function() return peer.now end
    env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
    env.print = function(...) if options.verbose then print(...) end end
    env.GetPlayerHandle = function() return 1 end
    env.IsValid = function(h) return h == 1 or world.objects[h] ~= nil end
    env.GetPosition = function(h)
        if h == 1 then return { x = peer.playerPos.x, y = peer.playerPos.y, z = peer.playerPos.z } end
        local o = world.objects[h]
        if o then return { x = o.x, y = o.y, z = o.z } end
        return nil
    end
    env.GetOdf = function(h) local o = world.objects[h]; return o and o.odf or "" end
    env.IsCraft = function(h) local o = world.objects[h]; return o ~= nil and o.craft end
    env.IsPerson = function() return false end
    env.IsNetGame = function() return options.net == true end
    env.IsLocal = function(h) local o = world.objects[h]; return o ~= nil and o.owner == name end
    env.GetTerrainHeightAndNormal = function(v) return SyntheticHeight(v.x, v.z), { x = 0, y = 1, z = 0 } end
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
        return function() i = i + 1; return world.order[i] end
    end
    if trn ~= nil then
        env.GetMapTRNFilename = function() return options.trnName or "misn14.trn" end
        env.GetMissionFilename = function() return options.missionName or "misn14.bzn" end
        env.OpenODF = function() return trn end
        env.GetODFString = function(t, section, key, default)
            local s = t[section]; local v = s and s[key]
            if v == nil then return default end
            return tostring(v)
        end
        env.GetODFInt = function(t, section, key, default)
            local s = t[section]; local v = s and s[key]
            return tonumber(v) or default
        end
        env.GetODFFloat = env.GetODFInt
    end
    for _, fn in ipairs(FORBIDDEN) do
        env[fn] = function() peer.forbidden[#peer.forbidden + 1] = name .. ":" .. fn end
    end

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
    peer.load = load

    if options.environment ~= false then
        peer.Environment = load("Environment")
        peer.Environment.EnableVisualRuntime = false
    end
    peer.CRWeather = load("CRWeather")
    peer.Presets = load("CRWeatherPresets")
    peer.Ti = load("CRTitanWeather")
    peer.Map = load("CRVenusMap")

    function peer.init(initOptions)
        initOptions = initOptions or {}
        initOptions.sites = initOptions.sites or sites
        if initOptions.send == nil and initOptions.authority ~= false and options.record ~= false then
            initOptions.send = function(op, ...)
                peer.sent[#peer.sent + 1] = { op = op, t = peer.now, args = { ... }, n = select("#", ...) }
                if peer.link then peer.link(op, ...) end
            end
        end
        if peer.Environment then peer.Environment.Init() end
        peer.Ti.Init(initOptions)
    end

    function peer.step(dt)
        peer.now = peer.now + dt
        peer.Ti.Update(dt)
        if peer.Environment then peer.Environment.Update(dt) end
    end

    function peer.run(seconds, dt)
        dt = dt or (1.0 / 20.0)
        for _ = 1, math.floor(seconds / dt) do peer.step(dt) end
    end

    function peer.events(op)
        local list = {}
        for _, m in ipairs(peer.sent) do if m.op == op then list[#list + 1] = m end end
        return list
    end

    return peer
end

local allPeers = {}
local function Track(peer) allPeers[#allPeers + 1] = peer; return peer end

local function SystemsOfTemplate(peer, template)
    local list = {}
    for sysName, s in pairs(peer.rec.systems) do
        if s.template == template then list[#list + 1] = sysName end
    end
    table.sort(list)
    return list
end

-- =============================================================================
-- 1. misn14 map data (CRTitanSites14, generated by Tools/Build-TitanSites.py)
-- =============================================================================

do
    check(sites.mission == "misn14", "CRTitanSites14 describes misn14")
    check(sites.materialLabels[0] == "Methane Ocean" and sites.materialLabels[3] == "Rock",
        "the TextureType labels the wet rule is based on")
    check(#sites.sea.types == 1 and sites.sea.types[1] == 0, "only TextureType 0 (Methane Ocean) is methane")
    check(sites.sea.level == 5, "misn14's sea floor is 5.0 units (raw 50), got " .. tostring(sites.sea.level))
    check(sites.sea.cols == 256 and sites.sea.rows == 256 and sites.sea.cell == 20, "256x256 cells of 20 units")
    check(sites.sea.methaneCells == 58956, "58,956 pure methane cells, got " .. tostring(sites.sea.methaneCells))
    check(sites.sea.wetCells > 50000 and sites.sea.wetCells < sites.sea.methaneCells,
        "most methane is the flat sea; the raised methane ground round the bases is not wet")
    check(sites.sea.lakes >= 1, "enclosed lakes exist between the islands")
    check(#sites.pools > 40 and #sites.pools <= 160, "pool anchors were placed, got " .. #sites.pools)
    local b = sites.bounds
    check(b.minX < b.maxX and b.minZ < b.maxZ, "a playable box exists")
    local inside, wetAnchors, lakes = true, true, 0
    for i, p in ipairs(sites.pools) do
        if p.x < b.minX or p.x > b.maxX or p.z < b.minZ or p.z > b.maxZ then inside = false end
        if not IsWetStatic(p.x, p.z) then wetAnchors = false end
        check(p.weight > 0 and p.weight <= 1.0, "pool " .. i .. " weight is in (0, 1]")
        if p.lake then lakes = lakes + 1 end
        if i > 1 then check(p.weight <= sites.pools[i - 1].weight + 1e-9, "anchors are sorted best first") end
    end
    check(inside, "every anchor lies inside the playable box")
    check(wetAnchors, "every anchor lies on a wet cell")
    check(lakes >= 1, "at least one anchor sits on an enclosed lake")
    for i = 1, #sites.pools do
        for j = i + 1, #sites.pools do
            local dx, dz = sites.pools[i].x - sites.pools[j].x, sites.pools[i].z - sites.pools[j].z
            if (dx * dx + dz * dz) < (80 * 80 - 1) then
                check(false, "anchors " .. i .. " and " .. j .. " are closer than the 80-unit spacing")
            end
        end
    end
    check(WET_POINT ~= nil and DRY_POINT ~= nil and WADE_POINT ~= nil, "the box holds both wet and dry ground")
end

-- =============================================================================
-- 2. Environment: Titan is detected and gets its own preset
-- =============================================================================

do
    local peer = Track(NewPeer("envtitan", NewWorld(), { trn = TITAN_TRN, environment = true }))
    local E = peer.Environment
    E.Init()
    check(E.WorldPreset == "titan", "a TITAN.ACT .trn selects the titan preset, got " .. tostring(E.WorldPreset))
    check(E.LockDaylight == true, "the titan preset holds the cycle at day")
    check(E.DayAmbient.r > 0.2 and E.DayAmbient.r > E.DayAmbient.b, "Titan ambient is warm and not black (stock Ambient=0)")
    check(E.DayDiffuse.r > E.DayDiffuse.g and E.DayDiffuse.g > E.DayDiffuse.b, "Titan sunlight is orange")
    check(E.DayFog.r > E.DayFog.g and E.DayFog.g > E.DayFog.b, "Titan fog is amber")
    check(E.DayFog.fogStart == 50 and E.DayFog.fogEnd == 175, "the .trn's own fog range is kept (50-175)")
    check((E.DayFog.fogEnd - E.DayFog.fogStart) <= 160, "fog range stays within the DX11 terrain-IBL reference (160)")
    check(E.GetFogHorizon() == 250, "the terrain horizon comes from VisibilityRange")
    check(E.DaySunDirection.y > -0.5, "the Titan sun is low over the horizon")

    -- A whole 15-minute cycle: never dusk, never night, never a night nerf.
    local maxNight = 0.0
    for _ = 1, 950 do
        peer.now = peer.now + 1.0
        E.Update(1.0)
        if E.NightBlend > maxNight then maxNight = E.NightBlend end
    end
    check(maxNight == 0.0, "no night on Titan over a full cycle, got night blend " .. tostring(maxNight))
    check(E.LastPhase == "Day", "the phase stays Day, got " .. tostring(E.LastPhase))

    -- Opting back into the cycle.
    local opt = Track(NewPeer("envtitannight", NewWorld(), { trn = TITAN_TRN, environment = true }))
    opt.Environment.TitanAllowNight = true
    opt.Environment.Init()
    check(opt.Environment.WorldPreset == "titan" and opt.Environment.LockDaylight == false,
        "TitanAllowNight keeps the ordinary cycle")

    -- Regressions: an earth map stays earth, a moon map stays moon, and the
    -- Titan fallback by mission name works when the .trn is unhelpful.
    local earth = Track(NewPeer("envearth", NewWorld(), { trn = EARTH_TRN, trnName = "misn04.trn",
        missionName = "misn04.bzn", environment = true }))
    earth.Environment.Init()
    check(earth.Environment.WorldPreset == "earth" and earth.Environment.LockDaylight == false,
        "a Mars map is still earth with the cycle running")
    local moonTrn = { NormalView = EARTH_TRN.NormalView, Atlases = { MaterialName = "mn_detail_atlas" },
        Sky = {}, Color = { Palette = "MOON.ACT" } }
    local moon = Track(NewPeer("envmoon", NewWorld(), { trn = moonTrn, trnName = "misn03.trn",
        missionName = "misn03.bzn", environment = true }))
    moon.Environment.Init()
    check(moon.Environment.WorldPreset == "moon", "a moon map is still moon")
    local bare = { NormalView = TITAN_TRN.NormalView, Atlases = {}, Sky = {}, Color = {} }
    local byName = Track(NewPeer("envname", NewWorld(), { trn = bare, trnName = "convtd.trn",
        missionName = "misn16b.bzn", environment = true }))
    byName.Environment.Init()
    check(byName.Environment.WorldPreset == "titan", "a stock Titan mission name is a fallback hint")
end

-- =============================================================================
-- 3. Presets
-- =============================================================================

do
    local peer = Track(NewPeer("presets", NewWorld()))
    local added = peer.Ti.RegisterPresets()
    check(added == 8, "eight presets (four rungs and their roll variants), got " .. added)
    check(peer.Ti.RegisterPresets() == 0, "registration is idempotent")
    local names = peer.Ti.GetPresetNames()
    check(#names == 8, "GetPresetNames lists all eight")
    for _, n in ipairs(names) do
        local p = peer.Presets.Get(n)
        check(p ~= nil, n .. " is registered with CRWeatherPresets")
        if p then
            local range = p.fog.fogEnd - p.fog.fogStart
            check(range > 0 and range <= 160, n .. " fog range " .. range .. " stays within the IBL reference (160)")
            check(p.fog.r > p.fog.g and p.fog.g > p.fog.b, n .. " fog is amber")
            check(p.fog.fogEnd >= 100, n .. " never closes the view below 100 units")
            check(p.lightning == nil and p.sky == nil, n .. " has no lightning and keeps the map's sky")
            check(p.diffuse.r > p.diffuse.b, n .. " light is warm")
            local drizzle = #p.precipitation > 0
            local wantsDrizzle = n:find("Drizzle", 1, true) ~= nil or n:find("Shroud", 1, true) ~= nil
            check(drizzle == wantsDrizzle, n .. " drizzles only on the Drizzle / Shroud rungs")
            if drizzle then
                local e = p.precipitation[1].emitters[0]
                check(p.precipitation[1].template == "CR/Titan/Drizzle", n .. " uses the Titan drizzle")
                check(e.rate <= 60, n .. " drizzle is sparse (" .. e.rate .. "/s)")
                check(e.velocity[2] <= 16, n .. " drops fall slowly")
            end
        end
    end
    for _, base in ipairs({ "TitanStill", "TitanHazy", "TitanDrizzle", "TitanShroud" }) do
        local a, r = peer.Presets.Get(base), peer.Presets.Get(base .. "Roll")
        check(r.fog.fogEnd < a.fog.fogEnd and r.fog.fogStart < a.fog.fogStart, base .. "Roll pulls the fog in")
        check(r.sunPowerScale < a.sunPowerScale, base .. "Roll dims the sun")
        check(#r.precipitation == #a.precipitation, base .. "Roll keeps the rung's drizzle")
    end
end

-- =============================================================================
-- 4. Determinism: same seed, same weather; another seed, other weather
-- =============================================================================

local function Timeline(seed, minutes)
    local peer = Track(NewPeer("det" .. seed, NewWorld()))
    peer.init({ seed = seed, targetLevel = 3 })
    local levels, presets = {}, {}
    for _ = 1, minutes * 6 do
        peer.run(10.0, 0.25)
        levels[#levels + 1] = peer.Ti.GetLevel()
        presets[#presets + 1] = peer.CRWeather.GetPreset()
    end
    local rolls = {}
    for _, m in ipairs(peer.events("TitanRoll")) do
        rolls[#rolls + 1] = string.format("%.2f:%d:%.3f:%.3f", m.t, m.args[1], m.args[2], m.args[3])
    end
    return table.concat(levels, ","), table.concat(presets, ","), table.concat(rolls, ";"), peer
end

do
    local l1, p1, r1, a = Timeline(424242, 40)
    local l2, p2, r2 = Timeline(424242, 40)
    local l3, _, r3 = Timeline(777, 40)
    check(l1 == l2, "same seed: identical rung sequence")
    check(p1 == p2, "same seed: identical preset sequence")
    check(r1 == r2, "same seed: identical roll events")
    check(l1 ~= l3 or r1 ~= r3, "a different seed gives different weather")
    check(#r1 > 0, "rolls happen in 40 minutes")
    local seen = {}
    for lv in l1:gmatch("%d+") do seen[tonumber(lv)] = true end
    check(seen[3] or seen[4], "the timeline reaches the drizzle rungs with target 3")
    check(p1:find("Roll", 1, true) ~= nil, "a roll variant preset is selected during a roll")
    check(a.Ti.GetStats().randomRolls > 0, "random rolls are counted")
    local spaced = true
    local events = a.events("TitanRoll")
    for i = 2, #events do
        if events[i].t - events[i - 1].t < 45.0 then spaced = false end
    end
    check(spaced, "random rolls respect the minimum spacing")
end

-- =============================================================================
-- 5. Co-op: host decides, guest follows, nothing doubles
-- =============================================================================

do
    local world = NewWorld()
    local host = Track(NewPeer("host", world, { net = true }))
    local guest = Track(NewPeer("guest", world, { net = true }))
    local delivered = {}
    host.link = function(op, ...)
        delivered[#delivered + 1] = op
        guest.Ti.ApplyNetEvent(op, ...)
    end
    guest.init({ authority = false, startLevel = 1 })
    check(guest.Ti.Synced == false and guest.Ti.Seed == nil, "a guest without the host's seed waits")
    guest.run(5.0)
    check(guest.Ti.GetLevel() == 1, "a waiting guest shows the calm rung")
    check(#guest.sent == 0, "a guest never sends")

    host.init({ authority = true, seed = 99, targetLevel = 3 })
    check(guest.Ti.Seed == 99 and guest.Ti.Synced, "the host's TitanState seeds the guest")

    for _ = 1, 120 do
        host.step(0.5)
        guest.step(0.5)
    end
    -- Run long enough for several rolls.
    for _ = 1, 2400 do
        host.step(0.5)
        guest.step(0.5)
    end
    check(guest.Ti.GetStats().randomRolls == 0, "a guest schedules no rolls of its own")
    check(guest.Ti.GetStats().rolls == host.Ti.GetStats().rolls,
        "every host roll reached the guest exactly once (" .. host.Ti.GetStats().rolls .. " / " ..
        guest.Ti.GetStats().rolls .. ")")
    check(host.Ti.GetStats().rolls > 0, "the host rolled")
    check(guest.Ti.GetLevel() == host.Ti.GetLevel(), "guest and host stand on the same rung")
    check(math.abs(guest.Ti.GetRollIntensity() - host.Ti.GetRollIntensity()) < 0.05,
        "guest and host see the same roll intensity")

    -- A replayed roll does nothing; a guest's own Roll() is ignored.
    local before = guest.Ti.GetStats().rolls
    local last = host.events("TitanRoll")[#host.events("TitanRoll")]
    guest.Ti.ApplyNetEvent("TitanRoll", unpack(last.args, 1, last.n))
    check(guest.Ti.GetStats().rolls == before, "a duplicate roll event is dropped")
    check(guest.Ti.Roll(30, 1.0) == false, "a guest's Roll() is ignored")
    check(guest.Ti.SetTargetLevel(4) ~= 4 or guest.Ti.GetTargetLevel() == host.Ti.GetTargetLevel(),
        "a guest cannot move the target")
    check(guest.Ti.ApplyNetEvent("TitanRoll", "garbage", nil) ~= nil, "a malformed event is handled without raising")
    check(guest.Ti.ApplyNetEvent("SomethingElse", 1) == false, "foreign ops are not claimed")
    local hostBefore = host.Ti.GetStats().rolls
    check(host.Ti.ApplyNetEvent("TitanRoll", 9999, 1.0, 30.0) == true and host.Ti.GetStats().rolls == hostBefore,
        "the host ignores a roll event echoed back to it")

    -- Scripted roll replicates.
    local hostRolls = host.Ti.GetStats().rolls
    check(host.Ti.Roll(30, 0.9) == true, "the host can roll on cue")
    check(host.Ti.GetStats().rolls == hostRolls + 1, "a scripted roll counts")
    check(guest.Ti.IsRolling(), "the scripted roll reached the guest")
end

-- =============================================================================
-- 6. Pools stream in near the player and stay within budget
-- =============================================================================

do
    local peer = Track(NewPeer("pools", NewWorld()))
    local p = sites.pools[1]
    peer.playerPos = { x = p.x, y = SEA + 2.0, z = p.z }
    peer.init({ seed = 5, startLevel = 3, targetLevel = 3 })
    peer.Ti.ForceLevel(3, 600)
    peer.run(20.0)
    local live = peer.Ti.GetLivePoolCount()
    check(live >= 1 and live <= peer.Ti.MaxLivePools, "pools streamed in near the player (" .. live .. ")")
    check(peer.Ti.GetSystemCount() <= peer.Ti.MaxSystems, "the system budget holds")
    local sheens = SystemsOfTemplate(peer, "CR/Titan/PoolSheen")
    check(#sheens == live, "one sheen per live pool")
    local s = peer.rec.systems[sheens[1]]
    check(s and near(s.position.y, SEA + peer.Ti.PoolSheenHeight, 0.01), "the sheen lies just over the liquid")
    check(s and (s.rates[0] or 0) > 0, "the sheen emits")
    local ripples = SystemsOfTemplate(peer, "CR/Titan/PoolRipple")
    check(#ripples == live and (peer.rec.systems[ripples[1]].rates[0] or 0) > 10,
        "drizzle rung: pools ripple")
    check(#SystemsOfTemplate(peer, "CR/Titan/HazeBank") == 1, "one camera-attached haze bank")
    local haze = peer.rec.systems[SystemsOfTemplate(peer, "CR/Titan/HazeBank")[1]]
    check(haze.camera ~= nil, "the haze bank follows the camera")
    check(peer.extraRequested == "cr_titan", "the cr_titan payload is requested")

    -- Dry rung: ripples stop.
    peer.Ti.ForceLevel(1, 600)
    peer.run(200.0)
    local rip = SystemsOfTemplate(peer, "CR/Titan/PoolRipple")
    check(#rip > 0 and (peer.rec.systems[rip[1]].rates[0] or 0) < 1.0, "a dry rung stops the ripples")

    -- Far away: every pool goes.
    peer.playerPos = { x = sites.bounds.minX - 3000, y = 50, z = sites.bounds.minZ - 3000 }
    peer.run(5.0)
    check(peer.Ti.GetLivePoolCount() == 0, "pools stream out when the player leaves")
    check(#SystemsOfTemplate(peer, "CR/Titan/PoolSheen") == 0, "their systems are destroyed")
end

-- =============================================================================
-- 7. Splashes: moving craft on wet ground, nothing else
-- =============================================================================

do
    local world = NewWorld()
    local peer = Track(NewPeer("splash", world))
    peer.playerPos = { x = WET_POINT.x, y = SEA + 2.0, z = WET_POINT.z }
    local wader = AddObject(world, "avtank", WADE_POINT.x, SEA + 2.0, WADE_POINT.z)
    local parked = AddObject(world, "avtank", WET_POINT.x - 30, SEA + 2.0, WET_POINT.z)
    local flyer = AddObject(world, "avtank", WADE_POINT.x, SEA + 40.0, WADE_POINT.z)
    local dryRunner = AddObject(world, "avtank", DRY_POINT.x, SEA + 14.0, DRY_POINT.z)
    peer.init({ seed = 8, startLevel = 1 })

    -- Drive the wader back and forth across wet ground at ~15 u/s; the flyer
    -- moves too but is high; the dry runner moves on an island.
    local t = 0.0
    local function move(dt)
        t = t + dt
        local o = world.objects[wader]
        local nx = WADE_POINT.x + 15.0 * math.sin(t) -- stays inside the five wet cells
        o.x = nx
        local f = world.objects[flyer]; f.x = WADE_POINT.x + 15.0 * math.cos(t) -- over the same liquid, 38 up
        local d = world.objects[dryRunner]; d.z = DRY_POINT.z + 2.0 * math.sin(t * 6.0)
    end
    for _ = 1, 60 do move(0.05); peer.step(0.05) end
    local splashes = SystemsOfTemplate(peer, "CR/Titan/Splash")
    check(#splashes >= 1, "a moving craft on wet ground gets a wake")
    local wake = splashes[1] and peer.rec.systems[splashes[1]]
    check(wake and (wake.rates[0] or 0) > 0, "the wake emits")
    check(wake and near(wake.position.y, SEA + peer.Ti.SplashHeight, 0.01), "the wake sits on the liquid")
    check(peer.Ti.GetSplashCount() == 1, "only the wader splashes (parked, flying and dry craft do not), got " ..
        peer.Ti.GetSplashCount())
    local dp = world.objects[dryRunner]
    check(math.sqrt((dp.x - WET_POINT.x) ^ 2 + (dp.z - WET_POINT.z) ^ 2) < peer.Ti.SplashRange,
        "the dry runner is within splash range, so only the mask keeps it dry")
    check(peer.Ti.IsWet(WET_POINT.x, WET_POINT.z) and not peer.Ti.IsWet(DRY_POINT.x, DRY_POINT.z),
        "IsWet agrees with the generated mask")

    -- The wader stops: the wake falls silent and is eventually released.
    for _ = 1, 20 do peer.step(0.05) end
    check(peer.Ti.GetSplashCount() == 0, "a stopped craft makes no wake")
    peer.run(12.0)
    check(#SystemsOfTemplate(peer, "CR/Titan/Splash") == 0, "an idle wake system is destroyed")

    -- A craft that dies mid-wake is released without error.
    for _ = 1, 30 do move(0.05); peer.step(0.05) end
    world.objects[wader] = nil
    peer.run(1.0)
    check(peer.Ti.GetSplashCount() == 0 and not peer.Ti.Disabled, "a destroyed craft releases its wake cleanly")
    check(world.objects[parked] ~= nil, "the parked craft is untouched")
end

-- =============================================================================
-- 8. Standalone (no Environment.lua): CRWeather owns the renderer, still amber
-- =============================================================================

do
    local peer = Track(NewPeer("standalone", NewWorld(), { environment = false }))
    peer.init({ seed = 12, startLevel = 2, targetLevel = 2 })
    check(peer.CRWeather.OwnsEnvironment == true, "without Environment, CRWeather writes the renderer")
    peer.run(40.0)
    local fog = peer.rec.fog
    check(fog ~= nil and fog.r > fog.g and fog.g > fog.b, "standalone fog is amber")
    check(fog ~= nil and fog.fogEnd <= 250.01, "standalone fog respects the 175-unit baseline horizon")
    peer.Ti.Shutdown()
    check(next(peer.rec.systems) == nil, "Shutdown destroys every system")
end

-- =============================================================================
-- 9. Save / load continues the same weather
-- =============================================================================

do
    local a = Track(NewPeer("savea", NewWorld()))
    a.init({ seed = 31337, targetLevel = 3 })
    a.run(300.0, 0.25)
    local state = a.Ti.Save()
    local b = Track(NewPeer("saveb", NewWorld()))
    b.init({ seed = 1, targetLevel = 1 })
    b.Ti.Load(state)
    check(b.Ti.Seed == 31337 and near(b.Ti.Clock, a.Ti.Clock, 0.001), "a load restores seed and clock")
    a.run(600.0, 0.25)
    b.now = a.now - 600.0
    b.run(600.0, 0.25)
    check(a.Ti.GetLevel() == b.Ti.GetLevel(), "the loaded timeline continues identically")
end

-- =============================================================================
-- 10. Degradation and fault containment
-- =============================================================================

do
    local peer = Track(NewPeer("notemplates", NewWorld(), { noTemplates = true }))
    peer.init({ seed = 3, startLevel = 3 })
    peer.run(30.0)
    check(next(peer.rec.systems) == nil or #SystemsOfTemplate(peer, "CR/Titan/PoolSheen") == 0,
        "without the payload no Titan systems are made")
    check(peer.CRWeather.GetPreset() ~= nil and peer.CRWeather.GetPreset():find("Titan", 1, true) == 1,
        "without the payload the presets still run")

    local broken = Track(NewPeer("broken", NewWorld()))
    local bad = { sea = sites.sea, wet = sites.wet, pools = { { x = "nope", z = 1 } } }
    broken.init({ seed = 4, sites = bad })
    local raised = false
    for _ = 1, 100 do
        local ok = pcall(broken.step, 0.05)
        if not ok then raised = true end
    end
    check(not raised, "a fault in the director never raises into the mission")
    check(broken.Ti.Disabled == true, "repeated faults stand the director down")
end

-- =============================================================================
-- 11. Particle payload: every template the director names exists
-- =============================================================================

do
    local f = io.open(repoRoot .. "/Materials/cr_titan.particle.payload", "rb")
    check(f ~= nil, "Materials/cr_titan.particle.payload exists")
    if f then
        local text = f:read("*a")
        f:close()
        local mats = io.open(repoRoot .. "/Materials/CR_reactive.material", "rb")
        local matText = mats and mats:read("*a") or ""
        if mats then mats:close() end
        for _, tpl in ipairs({ "CR/Titan/Drizzle", "CR/Titan/HazeBank", "CR/Titan/PoolSheen",
            "CR/Titan/PoolMist", "CR/Titan/PoolRipple", "CR/Titan/Splash" }) do
            local s, e = text:find("particle_system " .. tpl .. "%s*{")
            check(s ~= nil, tpl .. " is declared")
            if s then
                local body = text:sub(e, (text:find("\nparticle_system ", e) or #text))
                local material = body:match("material%s+(%S+)")
                check(material and matText:find("material " .. material:gsub("%p", "%%%0") .. " ", 1) ~= nil,
                    tpl .. " material " .. tostring(material) .. " exists in CR_reactive.material")
                local emitters = 0
                for _ in body:gmatch("\n%s*emitter%s+%a+") do emitters = emitters + 1 end
                check(emitters == 1, tpl .. " has exactly one emitter (the director drives index 0)")
            end
        end
        local opens, closes = select(2, text:gsub("{", "")), select(2, text:gsub("}", ""))
        check(opens == closes, "payload braces balance")
    end
end

-- =============================================================================
-- 12. The audit: no gameplay effect, ever
-- =============================================================================

do
    for _, peer in ipairs(allPeers) do
        check(#peer.forbidden == 0, peer.name .. " made forbidden calls: " .. table.concat(peer.forbidden, ", "))
        for fn in pairs(peer.globalCalls) do
            check(ALLOWED_GLOBALS[fn], peer.name .. " called a BZ function outside the allowlist: " .. fn)
        end
        for fn in pairs(peer.exuCalls) do
            -- Particle setters are cosmetic by definition (a particle's velocity
            -- is not a craft's), so they are not matched against the patterns.
            local particle = fn:find("Particle", 1, true) ~= nil
            for _, pattern in ipairs(particle and {} or FORBIDDEN_EXU_PATTERNS) do
                -- Environment's own sync pass reads/writes radar with no director
                -- involvement; it is audited by value below, not by name.
                if fn:find(pattern) and not (peer.Environment and (fn:find("Radar") or fn:find("VelocJam"))) then
                    check(false, peer.name .. " called a forbidden exu function: " .. fn)
                end
            end
        end
        local E = peer.Environment
        if E and E.Initialized then
            local s = E.GameplayScales
            check(s.radarRange == 1.0 and s.radarPeriod == 1.0 and s.velocJam == 1.0,
                peer.name .. ": gameplay scales stay at identity")
            check(next(E.GameplayModifiers) == nil, peer.name .. ": no gameplay modifier registered")
            check(next(E.ObjectScrambles or {}) == nil, peer.name .. ": no per-craft scramble")
            check((E.Modifiers or {})["CRTitanWeather"] == nil,
                peer.name .. ": the director registers no Environment modifier of its own")
        end
        for _, v in pairs(peer.rec.radar) do
            check(v == 400.0, peer.name .. ": radar values are written back unchanged")
        end
    end
end

-- =============================================================================

if #failures > 0 then
    for _, message in ipairs(failures) do print("FAIL: " .. message) end
    print(string.format("TITAN WEATHER FAILED (%d of %d assertions)", #failures, assertions))
    os.exit(1)
end
print(string.format("TITAN WEATHER OK (%d assertions)", assertions))
