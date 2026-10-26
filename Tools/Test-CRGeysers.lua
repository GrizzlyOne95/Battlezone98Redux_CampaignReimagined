-- Test-CRGeysers.lua
--
-- Drives the real CRGeysers module (and, for the lifecycle hook, the real
-- CRWeather) against a stubbed exu and a stubbed BZ Lua runtime. No game, no Ogre.
--
-- Usage, from the repository root:
--
--     lua Tools/Test-CRGeysers.lua Scripts
--
-- Prints GEYSERS OK on success; prints each failed expectation and exits 1
-- otherwise.

-- The engine returns VECTOR_3D userdata (not tables) from GetPosition, so the
-- mocks must too, or a type(p) == "table" gate passes here and fails in game.
local function UD(t)
    if t == nil then return nil end
    local u = newproxy(true)
    getmetatable(u).__index = function(_, k) return t[k] end
    return u
end

local realPrint = print
local scriptDir = ... or "Scripts"
package.path = scriptDir .. "/?.lua;" .. package.path

local failures = {}
local assertions = 0
local function check(condition, message)
    assertions = assertions + 1
    if not condition then failures[#failures + 1] = message end
end

local function near(a, b, tolerance) return math.abs(a - b) <= tolerance end

-- =============================================================================
-- Stub engine
-- =============================================================================

local world, rec, printed, forbidden, counters

local function NewWorld()
    world = { objects = {}, order = {}, serial = 0 }
    forbidden = {}
    counters = { objectsInRange = 0 }
end

local function Add(odf, class, x, z, options)
    options = options or {}
    world.serial = world.serial + 1
    local h = world.serial + 1000
    world.objects[h] = {
        h = h, odf = odf, class = class, x = x, y = options.y or 0.0, z = z,
        building = options.building == true, craft = options.craft == true,
        deployed = options.deployed == true, alive = options.alive ~= false,
    }
    world.order[#world.order + 1] = h
    return h
end

local function AddGeyser(x, z, odf) return Add(odf or "eggeizr1", "geyser", x, z, { building = true }) end
local function Remove(h) world.objects[h] = nil end

local playerPos = { x = 0.0, y = 20.0, z = 0.0 }

-- A recycler deployed on a geyser (the thing that must hide the effect).
local function DeployRecycler(geyser, dx)
    local g = world.objects[geyser]
    return Add("avrecy", "recycler", g.x + (dx or 2.0), g.z, { craft = true, deployed = true })
end

local function Dist(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt((dx * dx) + (dz * dz))
end

local function InstallGlobals()
    _G.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
    _G.GetPlayerHandle = function() return 1 end
    _G.IsValid = function(h) return h == 1 or world.objects[h] ~= nil end
    _G.IsAlive = function(h) local o = world.objects[h]; return o ~= nil and o.alive end
    _G.IsBuilding = function(h) local o = world.objects[h]; return o ~= nil and o.building end
    _G.IsCraft = function(h) local o = world.objects[h]; return o ~= nil and o.craft end
    _G.IsDeployed = function(h) local o = world.objects[h]; return o ~= nil and o.deployed end
    _G.GetOdf = function(h) local o = world.objects[h]; return o and (o.odf .. "\0\0") or "" end
    _G.GetClassLabel = function(h) local o = world.objects[h]; return o and o.class or "" end
    _G.GetPosition = function(h)
        if h == 1 then return UD(playerPos) end
        local o = world.objects[h]
        if o then return UD({ x = o.x, y = o.y, z = o.z }) end
        return nil
    end
    _G.GetTerrainHeightAndNormal = function() return 10.0, UD({ x = 0, y = 1, z = 0 }) end
    _G.AllObjects = function()
        local i = 0
        return function()
            while true do
                i = i + 1
                local h = world.order[i]
                if h == nil then return nil end
                if world.objects[h] ~= nil then return h end
            end
        end
    end
    _G.ObjectsInRange = function(range, ref)
        counters.objectsInRange = counters.objectsInRange + 1
        local origin = world.objects[ref]
        local i = 0
        return function()
            while true do
                i = i + 1
                local h = world.order[i]
                if h == nil then return nil end
                local o = world.objects[h]
                if o ~= nil and origin ~= nil and Dist(o, origin) <= range then return h end
            end
        end
    end
    for _, name in ipairs({ "BuildObject", "RemoveObject", "SetPosition", "SetTransform", "Damage",
        "SetCurHealth", "MakeExplosion", "SetVelocity", "SetTeamNum", "Goto", "Attack", "Stop",
        "SetObjectiveOn", "SetLabel", "SetScrap", "AddScrap" }) do
        _G[name] = function() forbidden[#forbidden + 1] = name end
    end
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        printed[#printed + 1] = table.concat(parts, " ")
    end
end

local function NewExu(options)
    options = options or {}
    rec = { systems = {}, creates = 0, destroys = 0, failedCreates = 0 }
    local exu = setmetatable({}, { __index = function(_, key)
        if type(key) == "string" and key:match("^SetParticle") then
            return function(name, a, b, c, d)
                local s = rec.systems[name]
                if s == nil then return false end
                s.calls[#s.calls + 1] = { key, a, b, c, d }
                if key == "SetParticleEmitterEmissionRate" then
                    s.rates[a] = b
                    if b > (s.peak[a] or 0) then s.peak[a] = b end
                elseif key == "SetParticleSystemParticleQuota" then
                    s.quota = a
                elseif key == "SetParticleEmitterColor" then
                    s.colors[a] = b
                end
                return true
            end
        end
        return nil
    end })
    exu.CreateParticleSystem = function(name, template, position)
        if options.failTemplate and options.failTemplate == template then
            rec.failedCreates = rec.failedCreates + 1
            return false
        end
        if rec.systems[name] ~= nil then return false end
        rec.creates = rec.creates + 1
        rec.systems[name] = { template = template, position = position, rates = {}, peak = {}, colors = {}, calls = {} }
        return true
    end
    exu.DestroyParticleSystem = function(name)
        if rec.systems[name] == nil then return false end
        rec.systems[name] = nil
        rec.destroys = rec.destroys + 1
        return true
    end
    exu.HasParticleTemplate = function() return true end
    return exu
end

local function CountSystems()
    local n = 0
    for _ in pairs(rec.systems) do n = n + 1 end
    return n
end

local function SystemsAt(x, z)
    local out = {}
    for name, s in pairs(rec.systems) do
        if near(s.position.x, x, 0.01) and near(s.position.z, z, 0.01) then out[#out + 1] = name end
    end
    return out
end

-- Fresh module, fresh stubs.
local function Fresh(options)
    options = options or {}
    printed = {}
    NewWorld()
    playerPos = { x = 0.0, y = 20.0, z = 0.0 }
    InstallGlobals()
    package.loaded.exu = NewExu(options)
    package.loaded.CRGeysers = nil
    package.loaded.CRParticleTemplates = {
        Ensure = function() return true end,
        EnsureExtra = function(name)
            printed.extra = name
            if options.noPayload then return false, "stub: payload missing" end
            return true
        end,
    }
    local G = dofile(scriptDir .. "/CRGeysers.lua")
    return G
end

local function Run(G, seconds, quality, dt)
    dt = dt or 0.25
    local t = 0.0
    while t < seconds - 1e-9 do
        G.Update(dt, quality)
        t = t + dt
    end
end

-- Pins the bare-minimum rule the effects depend on: no randomness anywhere.
local realRandom = math.random
math.random = function() error("CRGeysers must not use math.random") end

-- =============================================================================
-- 1. The right look per world
-- =============================================================================

local function SystemTemplates()
    local set = {}
    for _, s in pairs(rec.systems) do set[s.template] = (set[s.template] or 0) + 1 end
    return set
end

do
    local expected = {
        achilles = { ["CR/Geyser/Plume"] = 1, ["CR/Geyser/Dust"] = 1, ["CR/Geyser/Grit"] = 1 },
        mars     = { ["CR/Geyser/Plume"] = 1, ["CR/Geyser/Dust"] = 1, ["CR/Geyser/Grit"] = 1 },
        titan    = { ["CR/Geyser/Plume"] = 1 },
        moon     = { ["CR/Geyser/Grit"] = 1, ["CR/Geyser/Dust"] = 1 },
    }
    for world_, templates in pairs(expected) do
        local G = Fresh()
        AddGeyser(30.0, 40.0)
        G.Init({ world = world_ })
        Run(G, 3.0)
        local seen = SystemTemplates()
        for template, count in pairs(templates) do
            check(seen[template] == count, world_ .. " draws " .. template .. " once, saw " .. tostring(seen[template]))
        end
        for template in pairs(seen) do
            check(templates[template] ~= nil, world_ .. " draws only its own layers, saw extra " .. template)
        end
        check(printed.extra == "cr_geyser", "the geyser payload is the one requested")
        G.Shutdown()
    end

    -- Colours differ per world: rust red on Mars, brown on Achilles, grey on the Moon.
    local function PlumeColor(world_)
        local G = Fresh()
        AddGeyser(30.0, 40.0)
        G.Init({ world = world_ })
        Run(G, 3.0)
        local c
        for _, s in pairs(rec.systems) do
            if s.template == "CR/Geyser/Plume" or s.template == "CR/Geyser/Grit" then c = c or s.colors[0] end
        end
        G.Shutdown()
        return c
    end
    local mars, titan, moon = PlumeColor("mars"), PlumeColor("titan"), PlumeColor("moon")
    check(mars and mars.r > mars.b + 0.2, "Mars dust is red-brown, not blue")
    check(titan and titan.r > titan.b + 0.3, "Titan haze is orange-tan")
    check(moon and near(moon.r, moon.g, 0.1), "lunar grit is a neutral grey")

    -- Worlds whose director already draws vents: nothing here, and the module says so.
    for _, world_ in ipairs({ "europa", "io", "venus" }) do
        local G = Fresh()
        AddGeyser(30.0, 40.0)
        G.Init({ world = world_ })
        Run(G, 5.0)
        check(CountSystems() == 0, world_ .. " is drawn by its weather director, not by CRGeysers")
        check(G.IsOwnedByDirector(world_), world_ .. " is flagged as director-owned")
        check(#G.GetGeysers() == 1, world_ .. " still tracks its geysers for occupancy")
        G.Shutdown()
    end

    -- A world with no look stays stock.
    for _, world_ in ipairs({ "ganymede", "elysium", false }) do
        local G = Fresh()
        AddGeyser(30.0, 40.0)
        G.Init({ world = world_ or nil })
        Run(G, 5.0)
        check(CountSystems() == 0, tostring(world_) .. " has no look and stays stock")
        G.Shutdown()
    end
    check(true, "")
end

-- =============================================================================
-- 2. Discovery
-- =============================================================================

do
    local G = Fresh()
    local a = AddGeyser(30.0, 40.0)                          -- by class label and ODF
    local b = Add("modvent", "geyser", 60.0, 60.0, { building = true })   -- class label only
    local c = Add("mygeyser2", "i76building", 90.0, 60.0, { building = true })  -- ODF name only
    Add("avscrap", "scrap", 30.0, 45.0)
    Add("abwpow", "powerplant", 120.0, 50.0, { building = true })
    Add("avtank", "wingman", 150.0, 50.0, { craft = true })
    G.Init({ world = "mars" })
    Run(G, 1.0)
    local found = {}
    for _, r in ipairs(G.GetGeysers()) do found[r.h] = true end
    check(found[a] and found[b] and found[c], "geysers are found by class label or ODF name")
    check(#G.GetGeysers() == 3, "scrap, power plants and craft are not geysers")

    -- A geyser that appears mid-mission: by the forwarded hook at once...
    local late = AddGeyser(70.0, 20.0)
    G.OnObjectCreated(late)
    check(#G.GetGeysers() == 4, "OnObjectCreated registers a new geyser immediately")
    -- ...and by the periodic rescan otherwise.
    local later = AddGeyser(75.0, 25.0)
    Run(G, G.RescanPeriod + 1.0)
    check(#G.GetGeysers() == 5, "the periodic rescan finds geysers nobody forwarded")

    -- A removed geyser is forgotten and its systems go with it.
    Remove(late)
    Run(G, G.RescanPeriod + 1.0)
    check(#G.GetGeysers() == 4, "a vanished geyser is forgotten")
    for _, name in ipairs(SystemsAt(70.0, 20.0)) do check(false, "no system left at a vanished geyser " .. name) end
    G.Shutdown()
end

-- =============================================================================
-- 3. Occupancy: a building takes the effect away, losing it brings it back
-- =============================================================================

do
    local G = Fresh()
    local geyser = AddGeyser(30.0, 40.0)
    G.Init({ world = "achilles" })
    Run(G, 3.0)
    check(CountSystems() == 3, "a free geyser draws its three layers, saw " .. CountSystems())
    check(#SystemsAt(30.0, 40.0) == 3, "the systems sit on the geyser")
    for _, name in ipairs(SystemsAt(30.0, 40.0)) do
        check(near(rec.systems[name].position.y, 10.0 + G.GroundLift, 0.01), "systems sit on the terrain height")
    end

    -- Things that must NOT hide it.
    Add("avscrap", "scrap", 32.0, 40.0)
    Add("apcamr", "camerapod", 31.0, 41.0, { building = true })
    Add("crping", "i76building", 31.0, 39.0, { building = true })
    Add("eggeizr1", "geyser", 34.0, 40.0, { building = true })       -- a neighbouring geyser
    Add("avtank", "wingman", 33.0, 40.0, { craft = true })            -- an undeployed craft
    local travelling = Add("avrecy", "recycler", 36.0, 40.0, { craft = true, deployed = false })  -- recycler en route
    DeployRecycler(world.order[1], 80.0)                              -- deployed, but 80 m away
    Run(G, 3.0)
    check(#SystemsAt(30.0, 40.0) == 3, "scrap, nav pods, markers, geysers, tanks, a recycler still driving and a recycler 80 m away do not hide a geyser")

    -- A recycler deploys on it.
    local recycler = DeployRecycler(geyser, 2.0)
    Run(G, 3.0)
    check(#SystemsAt(30.0, 40.0) == 0, "the effect goes away while a recycler is deployed on the geyser")
    check(CountSystems() == 0, "and no system leaks")

    -- The recycler goes (destroyed): back.
    world.objects[recycler].alive = false
    Run(G, 3.0)
    check(#SystemsAt(30.0, 40.0) == 3, "the effect comes back when the building is destroyed")

    -- Each kind of occupant, one after another.
    for _, case in ipairs({
        { "factory building", function() return Add("abfact", "factory", 31.0, 40.0, { building = true }) end },
        { "armory building", function() return Add("abarmo", "armory", 29.0, 41.0, { building = true }) end },
        { "construction rig building", function() return Add("abcons", "constructionrig", 30.0, 38.0, { building = true }) end },
        { "any deployed craft", function() return Add("avmine", "minelayer", 31.0, 41.0, { craft = true, deployed = true }) end },
    }) do
        local h = case[2]()
        Run(G, 3.0)
        check(#SystemsAt(30.0, 40.0) == 0, "a " .. case[1] .. " hides the effect")
        Remove(h)
        Run(G, 3.0)
        check(#SystemsAt(30.0, 40.0) == 3, "removing the " .. case[1] .. " brings it back")
    end

    -- Undeploying (the recycler lifts off) also frees it.
    local deployed = DeployRecycler(geyser, 1.0)
    Run(G, 3.0)
    check(#SystemsAt(30.0, 40.0) == 0, "deployed again: hidden")
    world.objects[deployed].deployed = false
    Run(G, 3.0)
    check(#SystemsAt(30.0, 40.0) == 3, "an undeployed recycler no longer hides it")
    G.Shutdown()
end

-- A building already standing on a geyser at mission start: it is never drawn.
do
    local G = Fresh()
    local geyser = AddGeyser(30.0, 40.0)
    DeployRecycler(geyser, 1.0)
    AddGeyser(200.0, 40.0)
    G.Init({ world = "mars" })
    Run(G, 3.0)
    check(#SystemsAt(30.0, 40.0) == 0, "a geyser taken at the start draws nothing")
    check(#SystemsAt(200.0, 40.0) == 3, "its free neighbour does")
    G.Shutdown()
end

-- =============================================================================
-- 4. IsOccupiedAt (what the Europa and Io directors ask)
-- =============================================================================

do
    local G = Fresh()
    local g1 = AddGeyser(30.0, 40.0)
    local g2 = AddGeyser(45.0, 40.0)            -- a clump neighbour
    local lone = AddGeyser(900.0, 900.0)
    G.Init({ world = "europa" })
    check(G.IsOccupiedAt(30.0, 40.0) == false, "a free geyser is not occupied")
    check(G.IsOccupiedAt(5000.0, 5000.0) == false, "no geyser known there: fail open")
    DeployRecycler(g1, 1.0)
    G.Clock = G.Clock + 2.0                      -- let the cached answer expire
    check(G.IsOccupiedAt(30.0, 40.0, 8.0) == true, "a geyser with a recycler on it is occupied")
    check(G.IsOccupiedAt(37.0, 40.0, 20.0) == false, "a merged site stays open while one of its geysers is free")
    DeployRecycler(g2, 1.0)
    G.Clock = G.Clock + 2.0
    check(G.IsOccupiedAt(37.0, 40.0, 20.0) == true, "a merged site is taken once all of its geysers are")
    check(G.IsOccupiedAt(900.0, 900.0) == false, "another geyser is unaffected")

    -- Cheap: repeated asks within the TTL cost one read.
    local before = counters.objectsInRange
    for _ = 1, 20 do G.IsOccupiedAt(900.0, 900.0) end
    check(counters.objectsInRange - before <= 1, "repeated asks within a second share one occupancy read")

    G.Enabled = false
    check(G.IsOccupiedAt(30.0, 40.0) == false, "disabled: nothing is reported occupied")
    G.Enabled = true
    G.Shutdown()
    check(G.IsOccupiedAt(30.0, 40.0) == false, "shut down: nothing is reported occupied")
end

-- =============================================================================
-- 5. Polling cost, caps and quality
-- =============================================================================

do
    -- 40 geysers in a ring around the player: occupancy is polled about once a
    -- second per drawn geyser, never every frame.
    local G = Fresh()
    for i = 1, 40 do
        local a = (i / 40) * math.pi * 2
        AddGeyser(300.0 * math.cos(a), 300.0 * math.sin(a))
    end
    G.Init({ world = "mars" })
    Run(G, 10.0, nil, 1.0 / 60.0)          -- ten seconds of 60 fps frames
    local reads = counters.objectsInRange
    check(reads <= 10 * (G.MaxLive + G.PollBudget), "occupancy is polled about once a second, not per frame: " .. reads .. " reads in 10 s")
    check(reads >= G.MaxLive, "and it does poll")
    local live = #G.GetLive()
    check(live == G.MaxLive, "live geysers are capped at MaxLive, saw " .. live)
    check(CountSystems() <= G.MaxSystems, "systems respect MaxSystems")
    check(CountSystems() == live * 3, "every drawn geyser has all three layers")

    -- Nearest first: the player moves, the near ones are drawn and the far ones dropped.
    playerPos = { x = 300.0, y = 20.0, z = 0.0 }
    Run(G, 12.0)
    local nearest = 0
    for _, r in ipairs(G.GetLive()) do
        if Dist(r, playerPos) < 450.0 then nearest = nearest + 1 end
    end
    check(nearest == #G.GetLive(), "after moving, the nearest geysers are the ones drawn")

    -- Quality scales how many are drawn and how fast they emit.
    Run(G, 4.0, 0.5)
    check(#G.GetLive() == 4, "quality 0.5 halves the live geysers, saw " .. #G.GetLive())
    check(CountSystems() == 12, "and tears the extras down, saw " .. CountSystems())
    Run(G, 4.0, 0.0)
    check(#G.GetLive() == 0 and CountSystems() == 0, "quality 0 draws nothing")
    Run(G, 4.0, 1.0)
    check(#G.GetLive() == G.MaxLive, "quality back to 1 restores them")

    local steady = {}
    for name, s in pairs(rec.systems) do
        if s.template == "CR/Geyser/Plume" then steady[#steady + 1] = s.rates[0] end
    end
    Run(G, 3.0, 0.5)
    local lowered = true
    for name, s in pairs(rec.systems) do
        if s.template == "CR/Geyser/Plume" and s.rates[0] >= steady[1] then lowered = false end
    end
    check(lowered and #steady > 0, "lower quality lowers the steady emission rate")
    G.Shutdown()
end

do
    -- A tight system budget is never exceeded, and no geyser is left half-drawn
    -- in a way that leaks bookkeeping.
    local G = Fresh()
    for i = 1, 6 do AddGeyser(20.0 * i, 30.0) end
    G.Init({ world = "mars" })
    G.MaxSystems = 7
    Run(G, 8.0)
    check(CountSystems() <= 7, "MaxSystems is a hard ceiling, saw " .. CountSystems())
    local counted = 0
    for _, r in ipairs(G.GetLive()) do counted = counted + 1 end
    check(counted >= 2, "geysers still draw within a small budget")
    G.Shutdown()
    check(CountSystems() == 0, "shutdown frees a budgeted run too")
end

-- =============================================================================
-- 6. Spurts: periodic, deterministic, no RNG
-- =============================================================================

do
    local function Trace()
        local G = Fresh()
        AddGeyser(77.0, 123.0)
        G.Init({ world = "mars" })
        local samples, peak = {}, 0
        for i = 1, 400 do
            G.Update(0.25)
            local value = 0
            for _, s in pairs(rec.systems) do
                if s.template == "CR/Geyser/Plume" then value = s.rates[1] or 0 end
            end
            samples[#samples + 1] = value
            if value > peak then peak = value end
        end
        G.Shutdown()
        return samples, peak
    end
    local a, peakA = Trace()
    local b = Trace()
    local identical = #a == #b
    for i = 1, #a do if a[i] ~= b[i] then identical = false end end
    check(identical, "two peers draw the same spurt rhythm for the same geyser")
    check(peakA > 5.0, "a spurt reaches a real emission rate, peak " .. peakA)
    local quiet, loud = 0, 0
    for i = 1, #a do if a[i] == 0 then quiet = quiet + 1 elseif a[i] > 1.0 then loud = loud + 1 end end
    check(quiet > loud, "most of the time the geyser is between spurts")
    check(loud > 0, "and it does spurt within 100 s")
end

-- =============================================================================
-- 7. Shutdown and save-load
-- =============================================================================

do
    local G = Fresh()
    for i = 1, 5 do AddGeyser(20.0 * i, 30.0) end
    G.Init({ world = "achilles" })
    Run(G, 5.0)
    check(CountSystems() > 0, "systems are up before shutdown")
    local created = rec.creates
    G.Shutdown()
    check(CountSystems() == 0, "shutdown destroys every particle system")
    check(rec.creates == rec.destroys, "every system created was destroyed, " .. rec.creates .. "/" .. rec.destroys)
    check(G.GetSystemCount() == 0 and #G.GetGeysers() == 0 and #G.GetLive() == 0, "shutdown clears all bookkeeping")
    G.Update(1.0)
    check(CountSystems() == 0, "updates after shutdown do nothing")

    -- A new mission in the same Lua state starts clean.
    NewWorld()
    AddGeyser(50.0, 50.0)
    G.Init({ world = "titan" })
    Run(G, 3.0)
    check(#G.GetLive() == 1 and CountSystems() == 1, "a second mission re-initialises cleanly")
    G.Shutdown()

    -- Save-load drops the Ogre scene: the bookkeeping forgets, the next pass rebuilds.
    local H = Fresh()
    AddGeyser(30.0, 40.0)
    H.Init({ world = "mars" })
    Run(H, 3.0)
    check(CountSystems() == 3, "systems up before the reload")
    H.ResetSystems()
    check(CountSystems() == 0 and #H.GetLive() == 0, "ResetSystems forgets the systems")
    Run(H, 3.0)
    check(CountSystems() == 3, "and the next pass rebuilds them")
    H.Shutdown()

    -- Disabling at run time tears everything down.
    local D = Fresh()
    AddGeyser(30.0, 40.0)
    D.Init({ world = "mars" })
    Run(D, 3.0)
    D.Enabled = false
    Run(D, 1.0)
    check(CountSystems() == 0, "disabling removes the effects")
    D.Shutdown()
end

-- =============================================================================
-- 8. Failure handling
-- =============================================================================

do
    -- The payload is missing: nothing is drawn, one message, no retry storm.
    local G = Fresh({ noPayload = true })
    AddGeyser(30.0, 40.0)
    G.Init({ world = "mars" })
    Run(G, 10.0)
    check(CountSystems() == 0, "no payload: no systems")
    local msgs = 0
    for _, m in ipairs(printed) do if m:find("payload is unavailable", 1, true) then msgs = msgs + 1 end end
    check(msgs == 1, "the missing payload is reported once, saw " .. msgs)
    G.Shutdown()

    -- One template that will not create is given up on; the others still draw.
    local H = Fresh({ failTemplate = "CR/Geyser/Dust" })
    AddGeyser(30.0, 40.0)
    H.Init({ world = "mars" })
    Run(H, 20.0)
    local seen = SystemTemplates()
    check(seen["CR/Geyser/Dust"] == nil, "the broken template draws nothing")
    check(seen["CR/Geyser/Plume"] == 1 and seen["CR/Geyser/Grit"] == 1, "the working templates still draw")
    check(rec.failedCreates <= H.MaxFailuresPerTemplate, "a failing template is retried only a few times, saw " .. rec.failedCreates)
    H.Shutdown()
end

-- =============================================================================
-- 9. Cosmetic only
-- =============================================================================

do
    local G = Fresh()
    local geyser = AddGeyser(30.0, 40.0)
    G.Init({ world = "achilles" })
    Run(G, 5.0)
    DeployRecycler(geyser, 1.0)
    Run(G, 5.0)
    check(#forbidden == 0, "no sim-affecting call was made: " .. table.concat(forbidden, ","))
    check(world.serial == 2, "no sim object was created")   -- the test's geyser and recycler only
end

-- =============================================================================
-- 10. The CRWeather lifecycle hook
-- =============================================================================

do
    Fresh()
    AddGeyser(30.0, 40.0)
    local exu = package.loaded.exu
    exu.GetFog = function() return { r = 0.5, g = 0.4, b = 0.3, fogStart = 100, fogEnd = 900 } end
    -- The map TRN says Mars.
    _G.GetMapTRNFilename = function() return "misn04.trn" end
    _G.OpenODF = function() return 1 end
    _G.GetODFString = function() return "ma_detail_atlas" end
    _G.GetODFFloat = function(_, _, _, d) return d end
    package.loaded.CRWeather, package.loaded.CRWorldArt, package.loaded.CRWeatherPresets = nil, nil, nil
    package.loaded.CRGeysers = nil
    local W = dofile(scriptDir .. "/CRWeather.lua")
    W.Init({ quality = 1.0 })
    local G = package.loaded.CRGeysers
    check(G ~= nil and G.Initialized, "CRWeather.Init starts CRGeysers")
    check(G and G.GetWorld() == "mars", "with the world its terrain atlas names, saw " .. tostring(G and G.GetWorld()))
    for _ = 1, 20 do W.Update(0.25) end
    check(CountSystems() >= 3, "CRWeather.Update drives the geyser effects, saw " .. CountSystems())
    local weatherSystems = 0
    for _, s in pairs(rec.systems) do if s.template:find("^CR/Geyser/") then weatherSystems = weatherSystems + 1 end end
    check(weatherSystems >= 3, "the geyser systems are present")
    W.OnObjectCreated(AddGeyser(500.0, 500.0))
    check(#G.GetGeysers() == 2, "CRWeather.OnObjectCreated forwards new geysers")
    W.ResetSystems()
    check(CountSystems() == 0, "CRWeather.ResetSystems drops the geyser systems")
    for _ = 1, 8 do W.Update(0.25) end
    check(CountSystems() >= 3, "and they return")
    W.Shutdown()
    check(CountSystems() == 0, "CRWeather.Shutdown removes every geyser system")
    check(not G.Initialized, "and shuts CRGeysers down")

    -- A broken CRGeysers must never break weather.
    package.loaded.CRGeysers = { Init = function() error("boom") end, Update = function() error("boom") end,
        Shutdown = function() error("boom") end }
    package.loaded.CRWeather = nil
    local W2 = dofile(scriptDir .. "/CRWeather.lua")
    local ok = pcall(function()
        W2.Init({})
        W2.Update(0.25)
        W2.Update(0.25)
        W2.Shutdown()
    end)
    check(ok, "a failing CRGeysers never breaks CRWeather")
    local booms = 0
    for _, m in ipairs(printed) do if m:find("CRGeysers", 1, true) then booms = booms + 1 end end
    check(booms == 1, "and it is reported once, then latched off, saw " .. booms)

    -- CRWeather disabled: the geyser effects are not started either.
    Fresh()
    AddGeyser(30.0, 40.0)
    package.loaded.CRWeather = nil
    local W3 = dofile(scriptDir .. "/CRWeather.lua")
    W3.Init({ enabled = false })
    for _ = 1, 12 do W3.Update(0.25) end
    check(CountSystems() == 0, "a mission that turns weather off gets no geyser effects")
    W3.Shutdown()
end

math.random = realRandom

if #failures > 0 then
    for _, message in ipairs(failures) do io.stderr:write("FAIL: " .. message .. "\n") end
    io.stderr:write(string.format("%d of %d expectations failed\n", #failures, assertions))
    os.exit(1)
end

realPrint(string.format("GEYSERS OK (%d assertions)", assertions))
