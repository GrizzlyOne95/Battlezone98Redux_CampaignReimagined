-- Test-CRMoonWeather.lua
--
-- Drives the real CRVenusMap (shared pure half) and CRMoonWeather modules, and
-- the generated CRMoonSites02b / CRMoonSites03 map data, against a stubbed exu
-- and a stubbed BZ Lua runtime. No game, no Ogre.
--
-- Usage, from the repository root:
--
--     lua5.1 Tools/Test-CRMoonWeather.lua Scripts
--
-- Every "peer" below is a fully isolated Lua environment with its own copy of
-- every module and its own globals, which is what a second machine is. Peers
-- share only a World table (the craft that exist) and the messages one sends the
-- other.
--
-- The no-gameplay contract is enforced by AUDIT, not by hope: every function the
-- BZ and exu stubs expose is wrapped and recorded, and the suite asserts that the
-- set of calls the director made is a subset of a short allowlist of particle /
-- read-only calls, that a long list of damaging, retargeting, team, perception,
-- sensor and fog / light calls was never made, and that a mutation (a forbidden
-- call inserted into the director) is caught.
--
-- Prints MOON WEATHER OK on success; prints each failed expectation and exits 1
-- otherwise.

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

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- =============================================================================
-- Map data
-- =============================================================================

local SITES = {
    misn02b = dofile(scriptDir .. "/CRMoonSites02b.lua"),
    misn03 = dofile(scriptDir .. "/CRMoonSites03.lua"),
}
local SITE = SITES.misn02b

-- =============================================================================
-- Synthetic terrain: flat shelf, a bowl, a hill, a steep face
-- =============================================================================

local SHELF = 40.0
local BOWL = { x = 3000.0, z = 98900.0, radius = 140.0, depth = 14.0 }
local HILL = { x = 3600.0, z = 98900.0, radius = 140.0, height = 14.0 }
local FACE_X = 4200.0     -- east of this the ground climbs at 35 degrees

local function SyntheticHeight(x, z)
    local h = SHELF
    local d = math.sqrt(((x - BOWL.x) ^ 2) + ((z - BOWL.z) ^ 2))
    if d < BOWL.radius then h = h - (BOWL.depth * (1.0 - ((d / BOWL.radius) ^ 2))) end
    d = math.sqrt(((x - HILL.x) ^ 2) + ((z - HILL.z) ^ 2))
    if d < HILL.radius then h = h + (HILL.height * (1.0 - ((d / HILL.radius) ^ 2))) end
    if x > FACE_X then h = h + ((x - FACE_X) * math.tan(math.rad(35.0))) end
    return h
end

local function SyntheticNormal(x, z)
    local e = 1.0
    local gx = (SyntheticHeight(x + e, z) - SyntheticHeight(x - e, z)) / (2.0 * e)
    local gz = (SyntheticHeight(x, z + e) - SyntheticHeight(x, z - e)) / (2.0 * e)
    local len = math.sqrt((gx * gx) + 1.0 + (gz * gz))
    return { x = -gx / len, y = 1.0 / len, z = -gz / len }
end

-- Everything that could hurt, move, create, remove, retarget, re-team or change
-- what anything can perceive. The director must call none of it.
local FORBIDDEN = {
    "Damage", "SetCurHealth", "AddHealth", "SetMaxHealth", "SetCurAmmo", "AddAmmo", "SetMaxAmmo",
    "MakeExplosion", "RemoveObject", "SetCurPilot", "Kill", "BuildObject", "SetVelocity", "SetOmega",
    "SetPosition", "SetTransform", "Stop", "Goto", "Attack", "SetCommand", "SetTeamNum", "SetLifespan",
    "SetIndependence", "SetAvoidType", "Follow", "Defend", "Retreat", "Patrol", "Dropoff",
    "Pickup", "Service", "Mine", "Scavenge", "Hide", "Cloak", "Decloak", "SetCloaked",
    "SetPerceivedTeam", "SetCanSnipe", "SetObjectiveOn", "SetObjectiveOff", "SetObjectiveName",
    "SetUserTarget", "SetTarget", "SetScrap", "AddScrap", "SetPilot", "GiveWeapon", "SetWeaponMask",
    "StartEarthquake", "UpdateEarthQuake", "StopEarthquake", "StartEarthquakeAt", "StartSound",
    "FailMission", "SucceedMission", "SetAIP", "AddObjective", "UpdateObjective",
}
-- exu functions the director may call at all. Anything else (fog, light, sun,
-- radar, velocity jam, gravity, health, teams ...) is forbidden by omission.
local ALLOWED_EXU = {
    CreateParticleSystem = true, DestroyParticleSystem = true,
    SetParticleSystemKeepLocalSpace = true, SetParticleSystemNonVisibleUpdateTimeout = true,
    SetParticleSystemPosition = true, SetParticleEmitterEmissionRate = true,
    SetParticleEmitterPosition = true, SetParticleAffectorParameter = true,
}
-- Every global BZ function the director may call: read-only queries.
local ALLOWED_GLOBALS = {
    GetTime = true, SetVector = true, GetPlayerHandle = true, IsValid = true, GetPosition = true,
    GetTerrainHeightAndNormal = true, GetVelocity = true, AllCraft = true,
}

-- =============================================================================
-- Isolated peers
-- =============================================================================

local function NewWorld()
    return { objects = {}, order = {}, serial = 0 }
end

local function AddCraft(world, odf, x, y, z, options)
    options = options or {}
    world.serial = world.serial + 1
    local h = world.serial + 1000
    world.objects[h] = {
        h = h, odf = odf, x = x, y = y, z = z, vx = options.vx or 0.0, vz = options.vz or 0.0,
        craft = options.craft ~= false, team = options.team or 1,
    }
    world.order[#world.order + 1] = h
    return h
end

local function NewPeer(name, world, options)
    options = options or {}
    local peer = {
        name = name, now = 0.0, world = world, loaded = {}, preload = {},
        playerPos = options.playerPos or { x = 3000.0, y = SHELF - BOWL.depth, z = BOWL.z },
        playerVel = { x = 0.0, y = 0.0, z = 0.0 },
        log = {}, sent = {}, inbox = {},
        globalCalls = {}, exuCalls = {}, forbidden = {},
        hits = {},
        rec = { systems = {}, destroyed = 0, fogWrites = 0, lightWrites = 0 },
    }
    local rec = peer.rec

    local env = setmetatable({}, { __index = _G })
    env._G = env
    peer.env = env

    -- ---- exu ----------------------------------------------------------------
    local exu = {}
    exu.CreateParticleSystem = function(sysName, template, position)
        if rec.systems[sysName] ~= nil then return false end
        if options.failTemplate and template == options.failTemplate then return false end
        rec.systems[sysName] = {
            template = template, position = position, rates = {}, positions = {}, params = {},
            emitterPositions = {}, created = peer.now, localSpace = nil,
        }
        return true
    end
    exu.DestroyParticleSystem = function(sysName)
        if rec.systems[sysName] == nil then return false end
        rec.systems[sysName] = nil
        rec.destroyed = rec.destroyed + 1
        return true
    end
    exu.SetParticleSystemKeepLocalSpace = function(sysName, v)
        if rec.systems[sysName] then rec.systems[sysName].localSpace = v end
        return true
    end
    exu.SetParticleSystemNonVisibleUpdateTimeout = function() return true end
    exu.SetParticleSystemPosition = function(sysName, v)
        if rec.systems[sysName] then rec.systems[sysName].position = v end
        return true
    end
    exu.SetParticleEmitterEmissionRate = function(sysName, i, r)
        local s = rec.systems[sysName]
        if s then
            s.rates[i] = r
            if r > (s.peak or 0) then s.peak = r end
        end
        return true
    end
    exu.SetParticleEmitterPosition = function(sysName, i, v)
        local s = rec.systems[sysName]
        if s then s.emitterPositions[i] = v end
        return true
    end
    exu.SetParticleAffectorParameter = function(sysName, i, key, value)
        local s = rec.systems[sysName]
        if s then s.params[i .. ":" .. key] = value end
        return true
    end
    -- The functions that would change the sky / fog / light / sensors exist so a
    -- call to one is RECORDED (and fails the audit) rather than being a nil lookup.
    exu.GetFog = function() return { r = 0.5, g = 0.5, b = 0.6, fogStart = 175, fogEnd = 250 } end
    exu.SetFog = function() rec.fogWrites = rec.fogWrites + 1 return true end
    exu.GetAmbientLight = function() return { r = 0.1, g = 0.1, b = 0.1 } end
    exu.SetAmbientLight = function() rec.lightWrites = rec.lightWrites + 1 return true end
    exu.GetSunDiffuse = function() return { r = 0.6, g = 0.6, b = 0.6 } end
    exu.SetSunDiffuse = function() rec.lightWrites = rec.lightWrites + 1 return true end
    exu.SetSunPowerScale = function() rec.lightWrites = rec.lightWrites + 1 return true end
    exu.SetRadarRange = function() return true end
    exu.SetRadarPeriod = function() return true end
    exu.SetVelocJam = function() return true end
    exu.SetGravity = function() return true end

    -- The exu audit: a proxy that records every function the director looks up and
    -- calls. BulletHit is a handler SLOT, not a call, so it passes through untouched.
    local exuProxy = setmetatable({}, {
        __index = function(_, key)
            if key == "BulletHit" then return exu.BulletHit end
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
    peer.preload["CRParticleTemplates"] = {
        Ensure = function() return true end,
        EnsureExtra = function(extra)
            if options.noTemplates then return false, "stub" end
            peer.extraRequested = extra
            return true, "stub"
        end,
    }

    -- ---- optional Environment (the owner of fog / ambient / sun) ---------------
    local modifiers = {}
    if options.environment then
        peer.EnvMock = {
            RegisterEnvironmentModifier = function(modName, fn) modifiers[modName] = fn end,
            UnregisterEnvironmentModifier = function(modName) modifiers[modName] = nil end,
        }
        env.Environment = peer.EnvMock
    end
    function peer.RunModifiers()
        local frame = {
            ambient = { r = 0.10, g = 0.10, b = 0.12 }, diffuse = { r = 0.40, g = 0.40, b = 0.45 },
            specular = { r = 0.3, g = 0.3, b = 0.3 },
            fog = { r = 0.5, g = 0.52, b = 0.58, fogStart = 175.0, fogEnd = 250.0 }, sunPowerScale = 1.0,
        }
        for _, fn in pairs(modifiers) do fn(frame) end
        return frame
    end
    peer.modifiers = modifiers

    -- ---- BZ runtime -----------------------------------------------------------
    env.GetTime = function() return peer.now end
    env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
    env.print = function() end
    env.GetPlayerHandle = function() return 1 end
    env.IsValid = function(h) return h == 1 or world.objects[h] ~= nil end
    env.GetPosition = function(h)
        if h == 1 then return peer.playerPos end
        local o = world.objects[h]
        if o then return { x = o.x, y = o.y, z = o.z } end
        return nil
    end
    env.GetVelocity = function(h)
        if h == 1 then return peer.playerVel end
        local o = world.objects[h]
        if o then return { x = o.vx, y = 0.0, z = o.vz } end
        return nil
    end
    env.GetTerrainHeightAndNormal = function(v)
        return SyntheticHeight(v.x, v.z), SyntheticNormal(v.x, v.z)
    end
    env.AllCraft = function()
        local i = -1
        return function()
            i = i + 1
            if i == 0 then return 1 end
            while true do
                local h = world.order[i]
                if h == nil then return nil end
                local o = world.objects[h]
                if o and o.craft then return h end
                i = i + 1
            end
        end
    end
    for _, fn in ipairs(FORBIDDEN) do
        env[fn] = function()
            peer.forbidden[#peer.forbidden + 1] = name .. ":" .. fn
        end
    end

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
        local path = scriptDir .. "/" .. moduleName .. ".lua"
        local chunk, err
        if options.sourceOverride and options.sourceOverride[moduleName] then
            chunk, err = loadstring(options.sourceOverride[moduleName], "=" .. moduleName)
        else
            chunk, err = loadfile(path)
        end
        if not chunk then error(err) end
        setfenv(chunk, env)
        local result = chunk(moduleName)
        peer.loaded[moduleName] = result == nil and true or result
        return peer.loaded[moduleName]
    end
    env.require = load
    env.unpack = unpack

    peer.Moon = load("CRMoonWeather")
    peer.Map = load("CRVenusMap")

    -- Messages the host sends are queued for the guest.
    peer.send = function(op, ...)
        peer.sent[#peer.sent + 1] = { op = op, args = { ... }, n = select("#", ...) }
        if peer.link then peer.link(op, ...) end
    end

    function peer.Init(initOptions)
        initOptions = initOptions or {}
        initOptions.authority = initOptions.authority ~= false and name == "host"
        if options.net and initOptions.send == nil and initOptions.authority then initOptions.send = peer.send end
        initOptions.sites = initOptions.sites or SITE
        peer.Moon.Init(initOptions)
    end
    function peer.Step(dt)
        peer.now = peer.now + dt
        -- deliver due messages
        local i = 1
        while i <= #peer.inbox do
            local m = peer.inbox[i]
            if m.at <= peer.now then
                table.remove(peer.inbox, i)
                peer.Moon.ApplyNetEvent(m.op, unpack(m.args, 1, m.n))
            else
                i = i + 1
            end
        end
        peer.Moon.Update(dt)
    end
    function peer.Run(seconds, dt)
        dt = dt or 0.1
        local steps = math.floor((seconds / dt) + 0.5)
        for _ = 1, steps do peer.Step(dt) end
    end
    function peer.Systems(template)
        local list = {}
        for sysName, s in pairs(rec.systems) do
            if template == nil or s.template == template then list[#list + 1] = { name = sysName, s = s } end
        end
        table.sort(list, function(a, b) return a.name < b.name end)
        return list
    end
    function peer.Hit(x, y, z)
        local fn = peer.exu.BulletHit
        if fn then fn("ordnance", 2001, 2002, { posit_x = x, posit_y = y, posit_z = z }, 3001) end
    end
    return peer
end

local function Link(from, to, latency)
    from.link = function(op, ...)
        to.inbox[#to.inbox + 1] = { at = from.now + (latency or 0.12), op = op, args = { ... }, n = select("#", ...) }
    end
end

local function SumRates(system)
    local total = 0.0
    for _, r in pairs(system.rates) do total = total + r end
    return total
end

local function SetPlayer(peer, x, z, height)
    local ground = SyntheticHeight(x, z)
    peer.playerPos = { x = x, y = ground + (height or 2.0), z = z }
end

-- =============================================================================
-- 1. Map data
-- =============================================================================

do
    for mission, sites in pairs(SITES) do
        check(sites.mission == mission, mission .. ": data names its mission")
        local b, t = sites.bounds, sites.terrain
        check(b.minX < b.maxX and b.minZ < b.maxZ, mission .. ": bounds are a box")
        check(b.minX >= t.minX and b.maxX <= t.minX + t.width and b.minZ >= t.minZ and b.maxZ <= t.minZ + t.depth,
            mission .. ": bounds sit inside the terrain")
        check(t.sample == 5 and near(t.heightPerCount, 0.1, 1e-9), mission .. ": measured sample spacing and height scale")
        local pools = sites.mist.pools
        check(#pools >= 40, mission .. ": at least 40 mist anchors (" .. #pools .. ")")
        local inside, weights = true, true
        for i = 1, #pools do
            local p = pools[i]
            if p.x < b.minX or p.x > b.maxX or p.z < b.minZ or p.z > b.maxZ then inside = false end
            if p.weight < 0 or p.weight > 1 or p.depth <= 0 then weights = false end
        end
        check(inside, mission .. ": every anchor inside the playable box")
        check(weights, mission .. ": weights are 0..1 and depth positive")
        local apart = true
        for i = 1, #pools do
            for j = i + 1, #pools do
                if math.sqrt(((pools[i].x - pools[j].x) ^ 2) + ((pools[i].z - pools[j].z) ^ 2)) < 63.9 then apart = false end
            end
        end
        check(apart, mission .. ": anchors are at least 64 apart")
    end
end

-- =============================================================================
-- 2. Determinism: the glow timeline is a pure function of the seed
-- =============================================================================

local function Windows(peer, upTo)
    peer.Moon.GlowAt(upTo)
    local out = {}
    for _, w in ipairs(peer.Moon.GetGlowWindows()) do
        out[#out + 1] = string.format("%.6f/%.6f/%.6f/%.6f/%.6f", w.start, w.rise, w.hold, w.fall, w.strength)
    end
    return table.concat(out, ";")
end

do
    local world = NewWorld()
    local a = NewPeer("host", world)
    local b = NewPeer("guest", world, { playerPos = { x = 4000.0, y = 60.0, z = 99000.0 } })
    a.Init({ seed = 424242 })
    b.Init({ seed = 424242, authority = false })
    check(Windows(a, 7200) == Windows(b, 7200), "same seed: identical glow windows on two peers")
    check(#a.Moon.GetGlowWindows() >= 8, "two hours hold at least eight glows (" .. #a.Moon.GetGlowWindows() .. ")")

    local c = NewPeer("host", NewWorld())
    c.Init({ seed = 424243 })
    check(Windows(a, 7200) ~= Windows(c, 7200), "a different seed gives a different timeline")

    -- Frame rate and the local player's position cannot change the timeline.
    local fast, slow = NewPeer("host", NewWorld()), NewPeer("host", NewWorld(), { playerPos = { x = 100.0, y = 1.0, z = 1.0 } })
    fast.Init({ seed = 99 }); slow.Init({ seed = 99 })
    fast.Step(0.001); slow.Step(0.001)   -- the first frame's delta is discarded by design; prime both alike
    local sampleFast, sampleSlow = {}, {}
    for t = 1, 1200 do
        for _ = 1, 10 do fast.Step(0.1) end
        slow.Step(0.5); slow.Step(0.5)
        sampleFast[#sampleFast + 1] = string.format("%.4f", fast.Moon.GetGlow())
        sampleSlow[#sampleSlow + 1] = string.format("%.4f", slow.Moon.GetGlow())
    end
    check(table.concat(sampleFast, ",") == table.concat(sampleSlow, ","),
        "10 Hz and 2 Hz peers (and different players) see the identical glow every second for 20 minutes")
    check(near(fast.Moon.GetBreath(), slow.Moon.GetBreath(), 1e-9), "the mist breath is identical at different frame rates")

    -- Shape of the timeline: rare, slow, calm most of the time.
    local w = a.Moon.GetGlowWindows()
    check(w[1].start >= a.Moon.GlowFirst[1] - 1e-9 and w[1].start <= a.Moon.GlowFirst[2] + 1e-9,
        "the first glow starts inside GlowFirst (" .. string.format("%.1f", w[1].start) .. ")")
    local gapsOk, ramps, strengths = true, true, true
    for i = 2, #w do
        local gap = w[i].start - (w[i - 1].start + w[i - 1].rise + w[i - 1].hold + w[i - 1].fall)
        if gap < a.Moon.GlowGap[1] - 1e-6 or gap > a.Moon.GlowGap[2] + 1e-6 then gapsOk = false end
    end
    for i = 1, #w do
        if w[i].rise < a.Moon.GlowRise[1] - 1e-6 or w[i].fall < a.Moon.GlowFall[1] - 1e-6 then ramps = false end
        if w[i].strength < a.Moon.GlowStrength[1] - 1e-6 or w[i].strength > a.Moon.GlowStrength[2] + 1e-6 then strengths = false end
    end
    check(gapsOk, "glows are separated by GlowGap (minutes apart)")
    check(ramps, "every glow ramps in and out over at least the minimum slow ramp")
    check(strengths, "glow strength stays in GlowStrength")

    local glowing, total, maxStep, last = 0, 0, 0.0, 0.0
    for t = 0, 7199 do
        local g = a.Moon.GlowAt(t)
        total = total + 1
        if g > 0.02 then glowing = glowing + 1 end
        maxStep = math.max(maxStep, math.abs(g - last))
        last = g
    end
    check(glowing / total < 0.25, "calm baseline most of the time: glowing " .. string.format("%.0f%%", 100.0 * glowing / total))
    check(glowing > 0, "but it does glow")
    -- A smoothstep ramp's steepest second is 1.5 x strength / rise.
    check(maxStep <= (1.5 * a.Moon.GlowStrength[2] / a.Moon.GlowRise[1]) + 0.005,
        "the glow ramps smoothly (largest 1 s step " .. string.format("%.3f", maxStep) .. ")")
end

-- =============================================================================
-- 3. Ground mist pools: streamed, snapped, budgeted
-- =============================================================================

do
    local peer = NewPeer("host", NewWorld())
    peer.Init({ seed = 7 })
    check(peer.extraRequested == "cr_moon", "the opt-in cr_moon payload is requested")
    check(peer.Moon.TemplatesReady, "templates are ready")

    -- Stand on a real anchor of the misn02b data.
    local pool = SITE.mist.pools[1]
    SetPlayer(peer, pool.x, pool.z, 2.0)
    peer.Run(8.0)
    local live = peer.Systems("CR/Moon/GroundMist")
    check(#live >= 1, "a pool streams in beside the player")
    check(#live <= peer.Moon.MaxLivePools, "never more live pools than MaxLivePools")
    local snapped, inRange = true, true
    for _, entry in ipairs(live) do
        local p = entry.s.position
        if not near(p.y, SyntheticHeight(p.x, p.z) + peer.Moon.MistHeight, 1e-6) then snapped = false end
        local d = math.sqrt(((p.x - pool.x) ^ 2) + ((p.z - pool.z) ^ 2))
        local dp = math.sqrt(((p.x - peer.playerPos.x) ^ 2) + ((p.z - peer.playerPos.z) ^ 2))
        if dp > peer.Moon.PoolStreamIn + 1 then inRange = false end
        check(entry.s.localSpace == false, "pool particles stay in world space")
    end
    check(snapped, "every pool sits at terrain height + MistHeight (not at y=0)")
    check(inRange, "pools only stream in inside PoolStreamIn")

    -- Rates follow weight and density.
    local entry = live[1]
    local record
    for _, r in pairs(peer.Moon.PoolLive) do if r.name == entry.name then record = r end end
    check(record ~= nil and near(entry.s.rates[0], peer.Moon.PoolRate * (record.pool.weight ^ peer.Moon.PoolWeightPower) * peer.Moon.GetMistScale(), 0.03),
        "pool emission = PoolRate x weight x mist scale")

    -- Leaving frees them.
    SetPlayer(peer, SITE.bounds.maxX + 5000.0, SITE.bounds.maxZ + 5000.0, 2.0)
    peer.Run(6.0)
    check(#peer.Systems("CR/Moon/GroundMist") == 0, "pools are destroyed beyond PoolStreamOut")
    check(peer.Moon.GetSystemCount() == count(peer.rec.systems), "the director's system count matches the engine's")
end

-- =============================================================================
-- 4. Local layer: denser in low ground, thinner over ridges
-- =============================================================================

do
    local function LocalRates(x, z, density)
        local peer = NewPeer("host", NewWorld())
        peer.Init({ seed = 3, density = density, randomGlow = false })
        SetPlayer(peer, x, z, 2.0)
        peer.Run(3.0)
        local sys = peer.Systems("CR/Moon/LocalMist")
        check(#sys == 1, "one local mist system follows the player")
        return sys[1] and sys[1].s or nil, peer
    end

    local bowl, peerBowl = LocalRates(BOWL.x, BOWL.z)
    local ridge, peerRidge = LocalRates(HILL.x, HILL.z)
    local flat = LocalRates(2000.0, 98200.0)
    local face = LocalRates(FACE_X + 600.0, 98900.0)
    check(bowl ~= nil and ridge ~= nil and flat ~= nil and face ~= nil, "local layer exists everywhere")
    if bowl and ridge and flat and face then
        local b, r, f, s = SumRates(bowl), SumRates(ridge), SumRates(flat), SumRates(face)
        check(b > f, "denser over a bowl than over level ground (" .. string.format("%.2f > %.2f", b, f) .. ")")
        check(f > r, "level ground is denser than a hilltop (" .. string.format("%.2f > %.2f", f, r) .. ")")
        check(s < f * 0.15, "steep ground carries almost no sheet (" .. string.format("%.2f vs %.2f", s, f) .. ")")
        check(f > 0, "level ground has mist")
        -- Thirteen emitters, each placed on its own sampled patch.
        local n = 0
        for _ in pairs(flat.emitterPositions) do n = n + 1 end
        check(n == 13, "thirteen emitters each get a terrain-sampled position (" .. n .. ")")
        local mid = flat.emitterPositions[0]
        check(near(mid.y, peerBowl.Moon.MistHeight, 0.5), "the centre patch sits at MistHeight over the player's ground")
        check(bowl.position.y < SHELF and near(bowl.position.y, SyntheticHeight(BOWL.x, BOWL.z), 1e-6),
            "the system is parked on the player's ground height")
    end

    -- Moving the player moves the system but never recreates it.
    local peer = NewPeer("host", NewWorld())
    peer.Init({ seed = 3 })
    SetPlayer(peer, 2000.0, 98200.0, 2.0)
    peer.Run(2.0)
    local before = peer.Systems("CR/Moon/LocalMist")[1].name
    SetPlayer(peer, 2400.0, 98400.0, 2.0)
    peer.Run(2.0)
    local after = peer.Systems("CR/Moon/LocalMist")[1]
    check(after.name == before and near(after.s.position.x, 2400.0, 1e-6), "the local layer follows the player without recreating")
    -- ...and the density control scales it.
    local sum1 = SumRates(after.s)
    peer.Moon.SetDensity(0.0)
    peer.Run(80.0)
    check(SumRates(peer.Systems("CR/Moon/LocalMist")[1].s) < sum1 * 0.05, "density 0 clears the mist (eased out)")
    peer.Moon.SetDensity(2.0)
    peer.Run(80.0)
    check(SumRates(peer.Systems("CR/Moon/LocalMist")[1].s) > sum1 * 1.4, "density 2 thickens it")
end

-- =============================================================================
-- 5. Glow: brighter and a little thicker mist; fog and sky never touched
-- =============================================================================

do
    for _, withEnv in ipairs({ false, true }) do
        local label = withEnv and "with Environment" or "without Environment"
        local peer = NewPeer("host", NewWorld(), { environment = withEnv })
        peer.Init({ seed = 11, randomGlow = false })
        SetPlayer(peer, 2000.0, 98200.0, 2.0)
        peer.Run(5.0)
        local layer = peer.Systems("CR/Moon/LocalMist")[1]
        local calmSum = SumRates(layer.s)
        local calmColour = layer.s.params["0:colour1"]
        check(calmColour ~= nil, label .. ": the calm colour is written once")
        local calmAlpha = tonumber(calmColour:match("%S+ %S+ %S+ (%S+)"))
        local calmBlue = tonumber(calmColour:match("%S+ %S+ (%S+)"))
        check(near(calmAlpha, peer.Moon.MistAlphaA, 0.002), label .. ": calm alpha is MistAlphaA")

        check(peer.Moon.Glow(60.0, 1.0), label .. ": a scripted glow starts")
        local peakRates, peakAlpha, peakBlue, peakGlow, peakAmbient = 0.0, 0.0, 0.0, 0.0, 0.0
        for _ = 1, 700 do
            peer.Step(0.1)
            peakGlow = math.max(peakGlow, peer.Moon.GetGlow())
            local l = peer.Systems("CR/Moon/LocalMist")[1].s
            peakRates = math.max(peakRates, SumRates(l))
            peakAlpha = math.max(peakAlpha, tonumber(l.params["0:colour1"]:match("%S+ %S+ %S+ (%S+)")))
            peakBlue = math.max(peakBlue, tonumber(l.params["0:colour1"]:match("%S+ %S+ (%S+)")))
            if withEnv then peakAmbient = math.max(peakAmbient, peer.RunModifiers().ambient.b) end
        end
        check(near(peakGlow, 1.0, 1e-6), label .. ": the glow reaches the requested strength")
        check(peakRates > calmSum * 1.2 and peakRates < calmSum * 1.7, label .. ": the mist thickens by about GlowRateBoost")
        check(peakAlpha > calmAlpha + 0.03, label .. ": the mist catches more light (alpha up)")
        check(peakBlue > calmBlue, label .. ": and brightens toward the glow colour")
        check(peer.Moon.GetGlow() < 0.001 and not peer.Moon.IsGlowing(), label .. ": the glow ends")
        check(peer.rec.fogWrites == 0 and peer.rec.lightWrites == 0, label .. ": the director never writes fog, sun or ambient itself")
        if withEnv then
            check(peer.EnvMock ~= nil and peer.modifiers["CRMoonWeather"] ~= nil, label .. ": it registers an Environment modifier")
            local calmFrame = peer.RunModifiers()
            check(near(calmFrame.ambient.b, 0.12, 1e-9), label .. ": calm: the modifier adds nothing")
            check(peakAmbient > 0.12 and peakAmbient <= 0.12 + peer.Moon.GlowAmbient.b + 1e-9,
                label .. ": a glow lifts ambient by at most GlowAmbient (" .. string.format("%.4f", peakAmbient - 0.12) .. ")")
            check(near(calmFrame.fog.fogEnd, 250.0, 1e-9) and near(calmFrame.fog.fogStart, 175.0, 1e-9)
                and near(calmFrame.fog.r, 0.5, 1e-9), label .. ": the modifier never changes fog")
            peer.Moon.Glow(60.0, 1.0)
            peer.Run(20.0)
            local frame = peer.RunModifiers()
            check(near(frame.fog.fogEnd, 250.0, 1e-9) and near(frame.fog.g, 0.52, 1e-9) and near(frame.sunPowerScale, 1.0, 1e-9)
                and near(frame.diffuse.r, 0.40, 1e-9), label .. ": mid-glow the modifier still leaves fog, diffuse and sun alone")
            peer.Moon.Shutdown()
            check(peer.modifiers["CRMoonWeather"] == nil, label .. ": shutdown unregisters the modifier")
        else
            check(peer.modifiers["CRMoonWeather"] == nil, label .. ": no Environment, no modifier")
        end
    end
end

-- =============================================================================
-- 6. Impact dust: chained exu.BulletHit
-- =============================================================================

do
    local peer = NewPeer("host", NewWorld())
    local previousCalls = {}
    peer.exu.BulletHit = function(...) previousCalls[#previousCalls + 1] = { ... } end
    local original = peer.exu.BulletHit
    peer.Init({ seed = 5 })
    check(peer.exu.BulletHit ~= original, "Init chains onto exu.BulletHit")
    SetPlayer(peer, 2000.0, 98200.0, 2.0)
    peer.Run(1.0)

    local g = SyntheticHeight(2040.0, 98240.0)
    peer.Hit(2040.0, g + 0.3, 98240.0)
    check(#previousCalls == 1 and previousCalls[1][1] == "ordnance" and previousCalls[1][2] == 2001
        and previousCalls[1][3] == 2002 and previousCalls[1][5] == 3001, "the previous BulletHit handler runs first, with the same arguments")
    local kicks = peer.Systems("CR/Moon/KickDust")
    check(#kicks == 1, "a ground strike kicks up dust")
    check(near(kicks[1].s.position.y, g + peer.Moon.ImpactLift, 1e-6) and near(kicks[1].s.position.x, 2040.0, 1e-6),
        "the puff sits on the ground at the strike")
    check(near(kicks[1].s.rates[0], peer.Moon.ImpactRate, 1e-6), "the burst starts at ImpactRate")
    peer.Run(0.5)
    check(kicks[1].s.rates[0] == 0.0, "the burst parks after ImpactBurstSeconds (the particles keep falling)")

    local n = peer.Moon.GetStats().impacts
    peer.Hit(2040.0, g + 30.0, 98240.0)
    check(peer.Moon.GetStats().impacts == n, "a mid-air hit raises no dust")
    peer.Hit(2040.0 + 9000.0, SyntheticHeight(2040.0 + 9000.0, 98240.0), 98240.0)
    check(peer.Moon.GetStats().impacts == n, "a hit out of range of the player raises no dust")
    peer.Hit(2300.0, SyntheticHeight(2300.0, 98240.0), 98240.0)
    peer.Hit(2300.5, SyntheticHeight(2300.5, 98240.0), 98240.0)
    check(peer.Moon.GetStats().impacts == n + 1, "two strikes in the same instant make one puff (rate limit)")
    peer.exu.BulletHit("x", 1, 2, nil, 4)
    peer.exu.BulletHit("x", 1, 2, { garbage = true }, 4)
    check(true, "a malformed transform is ignored without error")

    -- A storm of strikes stays inside the pool and system budgets.
    local peak = 0
    for i = 1, 400 do
        local x = 1700.0 + (i * 1.7)
        peer.Hit(x, SyntheticHeight(x, 98300.0), 98300.0)
        peer.Step(0.07)
        peak = math.max(peak, peer.Moon.GetSystemCount())
    end
    check(#peer.Systems("CR/Moon/KickDust") <= peer.Moon.MaxImpactSystems, "never more kick systems than MaxImpactSystems")
    check(peak <= peer.Moon.MaxSystems, "a firefight stays inside MaxSystems (" .. peak .. ")")

    peer.Moon.Shutdown()
    check(peer.exu.BulletHit == original, "Shutdown restores the previous BulletHit handler")
    check(count(peer.rec.systems) == 0, "Shutdown destroys every system")
    peer.Hit(2040.0, g, 98240.0)
    check(#previousCalls >= 2, "after Shutdown the original handler still runs")

    -- If another module chained on top of us, our wrapper goes inert instead of
    -- ripping their handler out.
    local peer2 = NewPeer("host", NewWorld())
    peer2.Init({ seed = 5 })
    local ours = peer2.exu.BulletHit
    local onTop = function(...) return ours(...) end
    peer2.exu.BulletHit = onTop
    peer2.Moon.Shutdown()
    check(peer2.exu.BulletHit == onTop, "a handler chained on top of ours is left in place")
    SetPlayer(peer2, 2000.0, 98200.0, 2.0)
    peer2.Hit(2000.0, SyntheticHeight(2000.0, 98200.0), 98200.0)
    check(#peer2.Systems("CR/Moon/KickDust") == 0, "and our wrapper does nothing once shut down")
end

-- =============================================================================
-- 7. Hover dust
-- =============================================================================

do
    local world = NewWorld()
    local peer = NewPeer("host", world)
    peer.Init({ seed = 9 })
    SetPlayer(peer, 2000.0, 98200.0, 2.0)
    local g = SyntheticHeight(2000.0, 98200.0)

    local mover = AddCraft(world, "avtank", 2020.0, g + 2.0, 98220.0, { vx = 20.0, vz = 0.0 })
    local flyer = AddCraft(world, "avfigh", 2030.0, g + 60.0, 98230.0, { vx = 40.0 })
    local turret = AddCraft(world, "avturr", 2040.0, g + 0.0, 98240.0)
    local far = AddCraft(world, "avtank", 2000.0 + 900.0, SyntheticHeight(2900.0, 98200.0) + 2.0, 98200.0, { vx = 20.0 })
    peer.Run(2.0)
    local dust = peer.Systems("CR/Moon/HoverDust")
    check(#dust == 1, "one moving craft near the ground kicks hover dust (" .. #dust .. ")")
    check(dust[1] and near(dust[1].s.position.x, 2020.0, 1.0) and near(dust[1].s.position.y, g + 0.2, 1e-6), "parked on the ground under the craft")
    check(dust[1] and dust[1].s.rates[0] > 5.0, "and emitting")
    check(dust[1] and dust[1].s.localSpace == false, "its dust stays where it was thrown")

    -- A craft that stops goes quiet, then loses its system; a turret never had one.
    world.objects[mover].vx = 0.0
    peer.Run(2.5)
    check(#peer.Systems("CR/Moon/HoverDust") == 1, "a craft that has just slowed still wakes a little")
    peer.Run(8.0)
    check(#peer.Systems("CR/Moon/HoverDust") == 0, "a craft at rest long enough has no dust system")

    -- Budget: many fast craft, only the nearest few.
    for i = 1, 10 do AddCraft(world, "avtank", 2000.0 + i * 6.0, SyntheticHeight(2000.0 + i * 6.0, 98200.0) + 2.0, 98200.0 + i, { vx = 25.0 }) end
    peer.Run(2.0)
    check(#peer.Systems("CR/Moon/HoverDust") == peer.Moon.MaxHoverSystems, "tracked craft are capped at MaxHoverSystems")
    check(peer.Moon.GetSystemCount() <= peer.Moon.MaxSystems, "and the total stays inside MaxSystems")

    -- The player's own craft counts.
    local world2 = NewWorld()
    local p2 = NewPeer("host", world2)
    p2.Init({ seed = 9 })
    SetPlayer(p2, 2000.0, 98200.0, 2.0)
    p2.playerVel = { x = 22.0, y = 0.0, z = 0.0 }
    p2.Run(2.0)
    check(#p2.Systems("CR/Moon/HoverDust") == 1, "the player's own moving craft kicks dust")
    SetPlayer(p2, 2000.0, 98200.0, 90.0)
    p2.Run(6.0)
    check(#p2.Systems("CR/Moon/HoverDust") == 0, "a craft high above the ground does not")
end

-- =============================================================================
-- 8. Co-op: seed, clock, density, scripted glow
-- =============================================================================

do
    local world = NewWorld()
    local host = NewPeer("host", world, { net = true })
    local guest = NewPeer("guest", world, { net = true, playerPos = { x = 2200.0, y = 60.0, z = 98300.0 } })
    Link(host, guest, 0.12)
    host.Init({ seed = 777 })
    guest.Init({ authority = false })
    check(host.sent[1] ~= nil and host.sent[1].op == "MoonState" and host.sent[1].n == 3, "the host announces MoonState (three numbers) at Init")
    check(guest.Moon.Synced == false and guest.Moon.GlowAt(1000) == 0.0, "a guest without a seed shows no seeded glow")
    check(guest.Moon.Seed == nil, "and has no seed of its own")

    host.Step(0.0); guest.Step(0.0)
    host.Moon.AnnounceState()
    for _ = 1, 20 do host.Step(0.1); guest.Step(0.1) end
    check(guest.Moon.Seed == 777 and guest.Moon.Synced, "the guest adopts the host's seed")
    check(Windows(host, 3600) == Windows(guest, 3600), "host and guest now hold the identical glow timeline")

    -- Clock correction: a guest that drifted is pulled back; a small drift is left alone.
    guest.Moon.Clock = guest.Moon.Clock + 1.0
    guest.Moon.ApplyNetState(777, host.Moon.Clock, 1.0)
    check(near(guest.Moon.Clock, host.Moon.Clock + 1.0, 1e-9), "a drift under ClockSnapSeconds is left alone")
    guest.Moon.Clock = guest.Moon.Clock + 30.0
    guest.Moon.ApplyNetState(777, host.Moon.Clock, 1.0)
    check(near(guest.Moon.Clock, host.Moon.Clock, 1e-9), "a larger drift snaps to the host's clock")

    -- Heartbeat.
    local before = #host.sent
    for _ = 1, 700 do host.Step(0.1); guest.Step(0.1) end
    local beats = 0
    for i = before + 1, #host.sent do if host.sent[i].op == "MoonState" then beats = beats + 1 end end
    check(beats >= 2 and beats <= 3, "MoonState repeats about every NetHeartbeat (" .. beats .. " in 70 s)")

    -- Density follows the host.
    host.Moon.SetDensity(1.6)
    for _ = 1, 20 do host.Step(0.1); guest.Step(0.1) end
    check(near(guest.Moon.GetDensity(), 1.6, 1e-9), "the guest follows the host's density target")
    guest.Moon.SetDensity(0.2)
    check(near(guest.Moon.GetDensity(), 1.6, 1e-9), "a guest's own SetDensity is ignored")

    -- A scripted glow: one event, both peers glow together.
    local sentBefore = #host.sent
    check(host.Moon.Glow(60.0, 0.9), "host scripts a glow")
    check(#host.sent == sentBefore + 1 and host.sent[#host.sent].op == "MoonGlow", "it is exactly one MoonGlow event")
    check(not guest.Moon.Glow(60.0, 0.9), "a guest's Glow call is ignored")
    local hostPeak, guestPeak, hostAt, guestAt = 0, 0, nil, nil
    for i = 1, 700 do
        host.Step(0.1); guest.Step(0.1)
        local hg, gg = host.Moon.GetGlow(), guest.Moon.GetGlow()
        if hg > hostPeak + 1e-9 then hostPeak, hostAt = hg, i end
        if gg > guestPeak + 1e-9 then guestPeak, guestAt = gg, i end
    end
    check(near(hostPeak, 0.9, 1e-6) and near(guestPeak, 0.9, 1e-6), "both peers glow to the same strength")
    check(hostAt ~= nil and guestAt ~= nil and math.abs(hostAt - guestAt) <= 3, "and at the same moment (within 0.3 s)")

    -- Wire hygiene.
    local g0 = guest.Moon.GetStats().glows
    guest.Moon.ApplyNetEvent("MoonGlow", 1, 0.9, 60.0)
    check(guest.Moon.GetStats().glows == g0, "a duplicate id is ignored")
    guest.Moon.ApplyNetEvent("MoonGlow", 99, 5.0, 99999.0)
    local last = guest.Moon.Scripted[#guest.Moon.Scripted]
    check(last ~= nil and last.strength <= 1.0 and (last.rise + last.hold + last.fall) <= guest.Moon.GlowDurationLimit[2] + 1e-6,
        "strength and duration are clamped on receipt")
    local h0 = host.Moon.GetStats().glows
    check(host.Moon.ApplyNetEvent("MoonGlow", 50, 1.0, 30.0) == true and host.Moon.GetStats().glows == h0, "the host ignores events sent to it")
    check(not guest.Moon.ApplyNetEvent("Nonsense", 1), "an unknown op is not handled")
    check(guest.Moon.ApplyNetEvent("MoonState", 0, 0, 1) == false, "a MoonState with no seed is refused")
end

-- =============================================================================
-- 9. Save / load
-- =============================================================================

do
    local peer = NewPeer("host", NewWorld())
    peer.Init({ seed = 31337 })
    SetPlayer(peer, 2000.0, 98200.0, 2.0)
    peer.Run(40.0)
    peer.Moon.SetDensity(1.3)
    peer.Moon.Glow(100.0, 0.7)
    peer.Run(30.0)
    local saved = peer.Moon.Save()
    check(type(saved.seed) == "number" and type(saved.clock) == "number" and #saved.scripted == 1, "Save returns plain scalars and the live glow")
    local plain = true
    local function walk(t) for k, v in pairs(t) do if type(v) == "table" then walk(v) elseif type(v) == "function" or type(v) == "userdata" then plain = false end end end
    walk(saved)
    check(plain, "the saved state holds no functions")

    local fresh = NewPeer("host", NewWorld())
    fresh.Init({ seed = 1 })
    SetPlayer(fresh, 2000.0, 98200.0, 2.0)
    fresh.Moon.Load(saved)
    check(fresh.Moon.Seed == 31337 and near(fresh.Moon.Clock, saved.clock, 1e-9), "Load restores seed and clock")
    check(Windows(fresh, 3600) == Windows(peer, 3600), "and the same glow timeline")
    check(near(fresh.Moon.GetDensity(), 1.3, 1e-9), "and the density")
    fresh.Run(1.0)
    check(near(fresh.Moon.GetGlow(), peer.Moon.GetGlow(), 0.05), "a scripted glow in flight survives a load")
    check(#fresh.Systems("CR/Moon/LocalMist") == 1, "systems are rebuilt after a load")
end

-- =============================================================================
-- 10. Switches, missing payload, other mission
-- =============================================================================

do
    local peer = NewPeer("host", NewWorld(), { noTemplates = true })
    peer.Init({ seed = 2 })
    SetPlayer(peer, 2000.0, 98200.0, 2.0)
    peer.Run(10.0)
    peer.Hit(2000.0, SyntheticHeight(2000.0, 98200.0), 98200.0)
    check(not peer.Moon.TemplatesReady and count(peer.rec.systems) == 0, "a build without cr_moon degrades to nothing, without error")
    check(peer.Moon.GetGlow() >= 0.0, "the timeline still runs")

    local off = NewPeer("host", NewWorld())
    off.Init({ seed = 2, groundMist = false, impactDust = false, hoverDust = false })
    SetPlayer(off, SITE.mist.pools[1].x, SITE.mist.pools[1].z, 2.0)
    off.Run(10.0)
    check(count(off.rec.systems) == 0, "every sub-system can be switched off")

    local disabled = NewPeer("host", NewWorld())
    disabled.Init({ seed = 2, enabled = false })
    SetPlayer(disabled, 2000.0, 98200.0, 2.0)
    disabled.Run(10.0)
    check(count(disabled.rec.systems) == 0, "enabled = false does nothing at all")

    local lowQ = NewPeer("host", NewWorld())
    lowQ.Init({ seed = 2, quality = 0.0 })
    SetPlayer(lowQ, 2000.0, 98200.0, 2.0)
    lowQ.Run(5.0)
    local ls = lowQ.Systems("CR/Moon/LocalMist")[1]
    check(ls == nil or SumRates(ls.s) == 0.0, "quality 0 emits nothing")

    -- misn03's data streams too.
    local m3 = NewPeer("host", NewWorld())
    m3.Init({ seed = 2, sites = SITES.misn03 })
    local pool = SITES.misn03.mist.pools[1]
    SetPlayer(m3, pool.x, pool.z, 2.0)
    m3.Run(6.0)
    check(#m3.Systems("CR/Moon/GroundMist") >= 1, "misn03's anchors stream in")

    -- No sites at all: still the local layer.
    local bare = NewPeer("host", NewWorld())
    bare.Init({ seed = 2, sites = false })
    SetPlayer(bare, 2000.0, 98200.0, 2.0)
    bare.Run(5.0)
    check(#bare.Systems("CR/Moon/LocalMist") == 1 and #bare.Systems("CR/Moon/GroundMist") == 0, "a mission with no map data still gets the local mist")

    -- Tune() overrides a tunable and rejects unknown / mistyped names.
    local tune = NewPeer("host", NewWorld())
    tune.Init({ seed = 2 })
    SetPlayer(tune, 2000.0, 98200.0, 2.0)
    tune.Run(3.0)
    local before = tune.Systems("CR/Moon/LocalMist")[1].s.emitterPositions[0].y
    check(tune.Moon.Tune("MistHeight", 1.6) and not tune.Moon.Tune("NoSuchThing", 1) and not tune.Moon.Tune("MistHeight", "x"),
        "Tune accepts a known number and refuses unknown or mistyped names")
    tune.Run(2.0)
    check(near(tune.Systems("CR/Moon/LocalMist")[1].s.emitterPositions[0].y, before + 0.75, 1e-6), "a tuned MistHeight moves the layer live")
end

-- =============================================================================
-- 11. Long run: budget, steadiness
-- =============================================================================

do
    local world = NewWorld()
    local peer = NewPeer("host", world)
    peer.Init({ seed = 123 })
    for i = 1, 14 do
        AddCraft(world, "avtank", 2600.0 + (i * 15.0), SyntheticHeight(2600.0 + i * 15.0, 98600.0) + 2.0, 98600.0, { vx = 5.0 + i })
    end
    local peak = 0
    local x, z = 2000.0, 98200.0
    for step = 1, 12000 do   -- 20 minutes at 10 Hz, driving across the map with strikes
        x = 2000.0 + ((step * 0.35) % 2400.0)
        z = 98200.0 + ((step * 0.2) % 900.0)
        SetPlayer(peer, x, z, 2.0)
        if step % 7 == 0 then peer.Hit(x + 30.0, SyntheticHeight(x + 30.0, z), z) end
        peer.Step(0.1)
        peak = math.max(peak, peer.Moon.GetSystemCount())
    end
    check(peak <= peer.Moon.MaxSystems, "20 minutes of driving and firing never exceed MaxSystems (peak " .. peak .. ")")
    check(peer.Moon.GetSystemCount() == count(peer.rec.systems), "no leaked systems after the long run")
    check(peer.Moon.GetStats().impacts > 20, "it kicked up dust along the way (" .. peer.Moon.GetStats().impacts .. ")")
end

-- =============================================================================
-- 12. The no-gameplay audit
-- =============================================================================

local function Audit(peer, label)
    check(#peer.forbidden == 0, label .. ": no forbidden BZ function was called (" ..
        table.concat(peer.forbidden, ",", 1, math.min(#peer.forbidden, 4)) .. ")")
    local strayGlobals, strayExu = {}, {}
    for key in pairs(peer.globalCalls) do
        if not ALLOWED_GLOBALS[key] then strayGlobals[#strayGlobals + 1] = key end
    end
    for key in pairs(peer.exuCalls) do
        if not ALLOWED_EXU[key] then strayExu[#strayExu + 1] = key end
    end
    table.sort(strayGlobals); table.sort(strayExu)
    check(#strayGlobals == 0, label .. ": every BZ global called is a read-only query (stray: " .. table.concat(strayGlobals, ",") .. ")")
    check(#strayExu == 0, label .. ": every exu call is a particle call (stray: " .. table.concat(strayExu, ",") .. ")")
    check(peer.rec.fogWrites == 0 and peer.rec.lightWrites == 0, label .. ": fog, ambient, sun never written")
end

do
    -- A busy session: craft on two teams, strikes, glows, a guest, a save and a load.
    local world = NewWorld()
    local host = NewPeer("host", world, { net = true, environment = true })
    local guest = NewPeer("guest", world, { net = true, environment = true })
    Link(host, guest, 0.1)
    host.Init({ seed = 4242 })
    guest.Init({ authority = false })
    local a = AddCraft(world, "avtank", 2010.0, SyntheticHeight(2010.0, 98210.0) + 2.0, 98210.0, { vx = 15.0, team = 1 })
    local b = AddCraft(world, "svtank", 2050.0, SyntheticHeight(2050.0, 98250.0) + 2.0, 98250.0, { vx = 15.0, team = 2 })
    SetPlayer(host, 2000.0, 98200.0, 2.0); SetPlayer(guest, 2000.0, 98200.0, 2.0)
    host.Moon.AnnounceState()
    local radarBefore = {}
    for _ = 1, 3000 do
        host.Step(0.1); guest.Step(0.1)
        host.RunModifiers(); guest.RunModifiers()
    end
    for i = 1, 40 do
        host.Hit(2000.0 + i * 4.0, SyntheticHeight(2000.0 + i * 4.0, 98200.0), 98200.0)
        guest.Hit(2000.0 + i * 4.0, SyntheticHeight(2000.0 + i * 4.0, 98200.0), 98200.0)
        host.Step(0.2); guest.Step(0.2)
    end
    host.Moon.Glow(120.0, 1.0)
    host.Moon.SetDensity(1.5)
    host.Run(60.0); guest.Run(60.0)
    local state = host.Moon.Save()
    host.Moon.Load(state)
    host.Run(10.0)
    host.Moon.Shutdown(); guest.Moon.Shutdown()

    Audit(host, "host")
    Audit(guest, "guest")
    check(host.globalCalls.GetPosition ~= nil and host.exuCalls.CreateParticleSystem ~= nil,
        "the audit saw real activity (positions read, particle systems created)")
    check(world.objects[a].x == 2010.0 and world.objects[b].x == 2050.0 and world.objects[a].team == 1 and world.objects[b].team == 2,
        "no craft moved and no team changed")
    check(count(host.rec.systems) == 0 and count(guest.rec.systems) == 0, "everything is cleaned up")

    -- The source text itself never names the dangerous calls.
    local f = io.open(scriptDir .. "/CRMoonWeather.lua", "r")
    local source = f and f:read("*a") or ""
    if f then f:close() end
    check(#source > 1000, "the director's source was read")
    local code = source:gsub("%-%-[^\n]*", "")
    for _, name in ipairs({ "SetRadarRange", "SetRadarPeriod", "SetVelocJam", "SetObjectScramble", "RegisterGameplayModifier",
        "SetPerceivedTeam", "SetTeamNum", "BuildObject", "RemoveObject", "SetCurHealth", "AddHealth", "Damage(", "MakeExplosion",
        "SetFog", "SetAmbientLight", "SetSunDiffuse", "SetSunPowerScale", "SetSunSpecular", "SetGravity", "StartEarthquake",
        "StartSound", "SetVelocity", "SetPosition", "Cloak" }) do
        check(not code:find(name, 1, true), "the director's code never mentions " .. name)
    end
    check(not code:find("exu%.Set[A-Z]%w*Fog") and not code:find("CRWeather"), "and never touches fog or CRWeather at all")
end

do
    -- Mutation check: a forbidden call inserted into the director is caught.
    local f = io.open(scriptDir .. "/CRMoonWeather.lua", "r")
    local source = f:read("*a")
    f:close()
    local function Mutate(find, replace)
        local out, n = source:gsub(find, replace, 1)
        assert(n == 1, "mutation anchor not found: " .. find)
        return out
    end
    local cases = {
        { "a global gameplay call", Mutate("local function UpdateDensity%(dt%)", "local function UpdateDensity(dt)\n    Damage(1)"), "forbidden" },
        { "a fog write", Mutate("local function UpdateDensity%(dt%)", "local function UpdateDensity(dt)\n    exu.SetFog(1,1,1,1,2)"), "fog" },
        { "a radar write", Mutate("local function UpdateDensity%(dt%)", "local function UpdateDensity(dt)\n    exu.SetRadarRange(1, 1)"), "exu" },
        { "an unlisted global read", Mutate("local function UpdateDensity%(dt%)", "local function UpdateDensity(dt)\n    IsAlive(1)"), "global" },
    }
    for _, case in ipairs(cases) do
        local world = NewWorld()
        local peer = NewPeer("host", world, { sourceOverride = { CRMoonWeather = case[2] } })
        peer.env.IsAlive = function() return true end
        local wrapped = peer.env.IsAlive
        peer.env.IsAlive = function(...) peer.globalCalls.IsAlive = (peer.globalCalls.IsAlive or 0) + 1 return wrapped(...) end
        peer.Init({ seed = 1 })
        SetPlayer(peer, 2000.0, 98200.0, 2.0)
        peer.Run(2.0)
        local stray = false
        for key in pairs(peer.globalCalls) do if not ALLOWED_GLOBALS[key] then stray = true end end
        for key in pairs(peer.exuCalls) do if not ALLOWED_EXU[key] then stray = true end end
        local caught = (#peer.forbidden > 0) or stray or peer.rec.fogWrites > 0
        check(caught, "mutation caught: " .. case[1])
    end
end

-- =============================================================================
-- Report
-- =============================================================================

if #failures > 0 then
    for i = 1, #failures do print("FAIL: " .. failures[i]) end
    print(string.format("MOON WEATHER FAILED: %d of %d expectations", #failures, assertions))
    os.exit(1)
end

print(string.format("MOON WEATHER OK (%d expectations)", assertions))
