-- CRGeysers.lua
-- Per-world visual effects on the stock scrap geysers (ODF eggeizr1, class
-- "geyser"). A geyser is the building pad a Recycler, Factory or Armory
-- deploys onto. This module only DRAWS something on the free ones:
--
--     achilles  earth-brown dust column, a dirt skirt and thrown clods
--     mars      rust-red dust column and skirt, thrown grit
--     titan     slow tan methane/nitrogen haze billow in the dense air
--     moon      no air: pale grit thrown on long low arcs, a faint dust skirt
--
-- Europa, Io and Venus already draw their own vents (CREuropaWeather,
-- CRIoWeather, CRVenusWeather). This module draws nothing there and only
-- answers IsOccupiedAt() so those directors can hide a vent while something
-- is deployed on it (Europa and Io ask; Venus is wired once the Venus sky
-- stack has merged -- see Docs/WORLD_GEYSERS.md).
--
-- WHAT "OCCUPIED" MEANS. Nothing in the Lua API says a geyser is taken, so it
-- is read from the objects around it the same way aiCore.IsGeyserOpen reads
-- it: a live Recycler / Factory / Armory / Construction Rig, or any deployed
-- craft, within OccupyRadius of the geyser. Scrap, powerups, nav beacons and
-- other geysers never count. The effect goes away the moment that is true
-- and comes back the moment it stops being true (the building was destroyed
-- or undeployed).
--
-- GAMEPLAY EFFECTS: NONE. This module never builds, removes, moves, damages,
-- retargets or re-teams anything and creates no sim objects. It reads handles
-- and positions, and owns a few Ogre particle systems. It uses no random
-- numbers: each geyser's spurt period and phase come from a hash of its map
-- position, so every peer draws the same rhythm with no network traffic.
--
-- LIFECYCLE. CRWeather.Init/Update/Shutdown/ResetSystems/OnObjectCreated call
-- into this module (CRWeather already runs in every weather-enabled mission),
-- so no mission needs an edit.
--
-- PUBLIC API
--   Init{ world, quality, enabled, debug }   idempotent per mission
--   Update(dt, quality)                      every frame; does work ~1 Hz
--   Shutdown()                               destroys every system
--   ResetSystems()                           forget systems (save-load path)
--   OnObjectCreated(h)                       register a geyser the moment it exists
--   IsOccupiedAt(x, z, radius)               true when every known geyser within
--                                            radius (default MatchRadius) is taken
--   getters: GetWorld GetLook GetGeysers GetLive GetSystemCount IsOwnedByDirector
--            Describe

local exu = require("exu")

local CRGeysers = {}
local G = CRGeysers

-- =============================================================================
-- Configuration
-- =============================================================================

G.Enabled      = true
G.Debug        = false
G.Quality      = 1.0     -- CRWeather.Quality; scales live count, rate and quota

G.MaxLive      = 8       -- geysers drawn at once at quality 1
G.MaxSystems   = 24      -- every particle system this module owns, at once
G.MaxFailuresPerTemplate = 3

G.StreamIn     = 900.0   -- a free geyser this close to the local player is drawn
G.StreamOut    = 1100.0  -- ... and dropped beyond this (hysteresis)
G.SwapMargin   = 120.0   -- a free geyser this much nearer replaces the farthest one drawn
G.TickPeriod   = 1.0     -- seconds between streaming / occupancy passes
G.FxPeriod     = 0.5     -- seconds between spurt-envelope updates
G.PollBudget   = 12      -- occupancy queries per pass
G.RescanPeriod = 20.0    -- seconds between whole-world geyser scans

G.OccupyRadius = 11.0    -- same reach aiCore.IsGeyserOpen uses
G.OccupancyTtl = 1.0     -- a cached answer older than this is re-read on demand
G.MatchRadius  = 40.0    -- IsOccupiedAt: geysers this near a point stand for it
G.GroundLift   = 0.6
G.PayloadName  = "cr_geyser"

-- Building classes that deploy onto a geyser. Any craft that reports itself
-- deployed counts too, whatever its class.
G.OccupantClasses = {
    recycler = true, factory = true, armory = true, constructionrig = true,
}

-- Classes that are never an occupant even if they are buildings or sit close.
local NEVER_OCCUPANT = {
    scrap = true, powerup = true, dropoff = true, camerapod = true, i76sign = true,
    specialitem = true, spraybomb = true, geyser = true, person = true,
}
local NEVER_ODF = { crping = true }

-- =============================================================================
-- Per-world looks
-- =============================================================================
--
-- A look is a list of layers; a layer is one particle system per geyser built
-- from one of the three CR/Geyser/* templates (see cr_geyser.particle.payload).
-- steady is emitter 0 (always on), spurt is emitter 1 (its rate follows the
-- geyser's spurt envelope). affectors maps an affector index to its parameters.
--
-- A look with `director` set belongs to that weather director: this module
-- draws nothing and only reports occupancy.

local function C(r, g, b, a) return { r = r, g = g, b = b, a = a } end

local function Layer(kind, template, size, quota, steady, spurt, affectors)
    return {
        kind = kind, template = template, size = size, quota = quota,
        steady = steady, spurt = spurt, affectors = affectors,
    }
end

local function Emitter(rate, from, to, velocity, life, angle)
    return { rate = rate, color = { start = from, finish = to }, velocity = velocity, life = life, angle = angle }
end

G.Looks = {
    -- Jungle ground: wet earth thrown up, brown dust hanging low, a grey-brown
    -- column over it.
    achilles = {
        label = "dirt and dust", spurtSeconds = 5.0, spurtPeriod = { 20.0, 38.0 },
        layers = {
            Layer("plume", "CR/Geyser/Plume", { 9, 9 }, 110,
                Emitter(1.6, C(0.52, 0.46, 0.38, 0.20), C(0.44, 0.38, 0.30, 0.0), { 5, 8 }, { 5, 8 }, 7),
                Emitter(9.0, C(0.50, 0.43, 0.34, 0.42), C(0.42, 0.36, 0.28, 0.0), { 15, 24 }, { 3.5, 5.0 }, 12),
                { [0] = { rate = 1.6 }, [1] = { alpha = -0.07 }, [2] = { force_vector = "0 -3 0" } }),
            Layer("dust", "CR/Geyser/Dust", { 7, 7 }, 90,
                Emitter(3.0, C(0.44, 0.34, 0.22, 0.26), C(0.36, 0.28, 0.18, 0.0), { 1, 3 }, { 2.5, 4.5 }, 78),
                Emitter(14.0, C(0.42, 0.32, 0.20, 0.40), C(0.34, 0.26, 0.16, 0.0), { 6, 13 }, { 2.0, 3.5 }, 48),
                { [0] = { rate = 1.4 }, [1] = { alpha = -0.10 }, [2] = { force_vector = "0 -1 0" } }),
            Layer("clods", "CR/Geyser/Grit", { 1.1, 1.1 }, 60,
                nil,
                Emitter(8.0, C(0.30, 0.22, 0.14, 0.95), C(0.24, 0.17, 0.10, 0.0), { 12, 22 }, { 2.2, 3.4 }, 26),
                { [0] = { alpha = -0.20 }, [1] = { force_vector = "0 -9 0" } }),
        },
    },

    -- Thin carbon-dioxide air, red fines: a dusty column and thrown grit.
    mars = {
        label = "rust dust", spurtSeconds = 5.0, spurtPeriod = { 22.0, 40.0 },
        layers = {
            Layer("plume", "CR/Geyser/Plume", { 9, 9 }, 110,
                Emitter(1.6, C(0.74, 0.50, 0.35, 0.22), C(0.62, 0.42, 0.30, 0.0), { 5, 8 }, { 5, 8 }, 7),
                Emitter(10.0, C(0.78, 0.52, 0.36, 0.46), C(0.62, 0.42, 0.30, 0.0), { 16, 26 }, { 3.5, 5.0 }, 12),
                { [0] = { rate = 1.6 }, [1] = { alpha = -0.07 }, [2] = { force_vector = "0 -3.5 0" } }),
            Layer("dust", "CR/Geyser/Dust", { 6, 6 }, 90,
                Emitter(3.0, C(0.70, 0.46, 0.32, 0.20), C(0.58, 0.38, 0.26, 0.0), { 1, 3 }, { 2.5, 4.5 }, 75),
                Emitter(14.0, C(0.72, 0.48, 0.33, 0.34), C(0.58, 0.38, 0.26, 0.0), { 6, 13 }, { 2.0, 3.5 }, 45),
                { [0] = { rate = 1.4 }, [1] = { alpha = -0.10 }, [2] = { force_vector = "0 -1 0" } }),
            Layer("grit", "CR/Geyser/Grit", { 0.9, 0.9 }, 60,
                nil,
                Emitter(9.0, C(0.62, 0.40, 0.26, 0.85), C(0.50, 0.32, 0.20, 0.0), { 12, 24 }, { 2.0, 3.2 }, 24),
                { [0] = { alpha = -0.20 }, [1] = { force_vector = "0 -4 0" } }),
        },
    },

    -- Cold, dense nitrogen air: nothing is thrown far, the vent just breathes a
    -- slow tan haze that billows and hangs.
    titan = {
        label = "tan haze", spurtSeconds = 8.0, spurtPeriod = { 28.0, 52.0 },
        layers = {
            Layer("plume", "CR/Geyser/Plume", { 13, 13 }, 110,
                Emitter(1.4, C(0.90, 0.66, 0.38, 0.16), C(0.80, 0.58, 0.32, 0.0), { 3.5, 6 }, { 8, 12 }, 9),
                Emitter(6.0, C(0.92, 0.68, 0.40, 0.30), C(0.80, 0.58, 0.32, 0.0), { 9, 15 }, { 7, 10 }, 14),
                { [0] = { rate = 1.9 }, [1] = { alpha = -0.04 }, [2] = { force_vector = "0 -0.8 0" } }),
        },
    },

    -- No atmosphere: nothing billows. Grains leave on long ballistic arcs and
    -- a faint electrostatic skirt of fines hangs over the pad.
    moon = {
        label = "ballistic grit", spurtSeconds = 3.0, spurtPeriod = { 24.0, 46.0 },
        layers = {
            Layer("grit", "CR/Geyser/Grit", { 0.8, 0.8 }, 70,
                Emitter(0.7, C(0.66, 0.67, 0.70, 0.60), C(0.56, 0.57, 0.60, 0.0), { 3, 7 }, { 3.0, 5.0 }, 30),
                Emitter(16.0, C(0.70, 0.71, 0.74, 0.80), C(0.58, 0.59, 0.62, 0.0), { 10, 26 }, { 3.5, 6.0 }, 32),
                { [0] = { alpha = -0.12 }, [1] = { force_vector = "0 -2 0" } }),
            Layer("dust", "CR/Geyser/Dust", { 4, 4 }, 60,
                Emitter(1.2, C(0.64, 0.66, 0.70, 0.10), C(0.56, 0.58, 0.62, 0.0), { 0.5, 2 }, { 3.0, 5.0 }, 80),
                Emitter(6.0, C(0.66, 0.68, 0.72, 0.16), C(0.56, 0.58, 0.62, 0.0), { 3, 8 }, { 3.0, 5.0 }, 55),
                { [0] = { rate = 0.5 }, [1] = { alpha = -0.07 }, [2] = { force_vector = "0 -0.7 0" } }),
        },
    },

    -- Worlds whose weather director already draws their vents.
    europa = { label = "CREuropaWeather vapour plumes", director = "CREuropaWeather" },
    io     = { label = "CRIoWeather smoke and eruptions", director = "CRIoWeather" },
    venus  = { label = "CRVenusWeather sulphur plumes", director = "CRVenusWeather" },
}

-- =============================================================================
-- State
-- =============================================================================

G.Initialized      = false
G.World            = nil
G.Look             = nil
G.Clock            = 0.0
G.NextTickAt       = 0.0
G.NextFxAt         = 0.0
G.NextScanAt       = 0.0
G.Scanned          = false
G.Geysers          = {}     -- array of records
G.ByHandle         = {}     -- handle -> record
G.Live             = {}     -- record -> { layers = { { name, layer } ... } }
G.Systems          = {}     -- system name -> kind
G.SystemCount      = 0
G.Serial           = 0
G.TemplateFailures = {}
G.TemplatesReady   = false
G.TemplatesFailed  = false
G.AppliedQuality   = nil
G.Stats            = { scans = 0, polls = 0, created = 0, destroyed = 0 }

-- =============================================================================
-- Helpers
-- =============================================================================

local floor = math.floor

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function SmoothStep(t)
    t = Clamp(t, 0.0, 1.0)
    return t * t * (3.0 - (2.0 * t))
end

local function Log(message)
    if G.Debug then print("CRGeysers: " .. tostring(message)) end
end

local function Vec(x, y, z)
    if type(SetVector) == "function" then return SetVector(x, y, z) end
    return { x = x, y = y, z = z }
end

local function Call(name, ...)
    if exu == nil or type(exu[name]) ~= "function" then return nil end
    local ok, result = pcall(exu[name], ...)
    if not ok then
        Log("exu." .. name .. " failed: " .. tostring(result))
        return nil
    end
    return result
end

local function Global(name)
    local f = rawget(_G, name)
    if type(f) == "function" then return f end
    return nil
end

-- The engine hands back VECTOR_3D userdata, not tables: read the fields inside
-- a pcall and return a plain table (nil unless x and z are numbers).
local function ReadVector(p)
    if p == nil then return nil end
    local ok, x, y, z = pcall(function() return p.x, p.y, p.z end)
    if ok and type(x) == "number" and type(z) == "number" then
        return { x = x, y = tonumber(y) or 0.0, z = z }
    end
    return nil
end

local function GCall(name, ...)
    local f = Global(name)
    if f == nil then return nil end
    local ok, a = pcall(f, ...)
    if not ok then return nil end
    return a
end

local function PositionOf(h)
    return ReadVector(GCall("GetPosition", h))
end

local function ValidHandle(h)
    if h == nil then return false end
    local f = Global("IsValid")
    if f == nil then return true end
    local ok, valid = pcall(f, h)
    return ok and valid and true or false
end

local function AliveHandle(h)
    if not ValidHandle(h) then return false end
    local f = Global("IsAlive")
    if f == nil then return true end
    local ok, alive = pcall(f, h)
    return ok and alive and true or false
end

local function CleanLower(s)
    if type(s) ~= "string" then return "" end
    return (string.lower((string.gsub(s, "%z", ""))))
end

local function LocalPlayerPosition()
    local player = GCall("GetPlayerHandle")
    if player == nil or not ValidHandle(player) then return nil end
    return PositionOf(player)
end

local function TerrainHeight(x, z)
    local f = Global("GetTerrainHeightAndNormal")
    if f == nil then return nil end
    local ok, height = pcall(f, Vec(x, 0.0, z))
    if not ok or type(height) ~= "number" then return nil end
    return height
end

local function Distance2D(ax, az, bx, bz)
    local dx, dz = ax - bx, az - bz
    return math.sqrt((dx * dx) + (dz * dz))
end

-- A stable 0..1 value from a map position. Not a random number generator:
-- the same geyser gets the same value on every peer and every run.
local function PositionHash(x, z, salt)
    local v = math.sin((x * 12.9898) + (z * 78.233) + (salt * 37.719)) * 43758.5453
    return v - math.floor(v)
end

-- =============================================================================
-- Geyser discovery
-- =============================================================================

local function IsGeyserHandle(h)
    if not ValidHandle(h) then return false end
    if CleanLower(GCall("GetClassLabel", h)) == "geyser" then return true end
    local odf = CleanLower(GCall("GetOdf", h))
    if odf == "" then return false end
    -- eggeizr1 is the stock geyser (the spelling is the game's); "geyser" in an
    -- ODF name is how a mod names its own.
    return odf:find("^eggeizr") ~= nil or odf:find("geyser", 1, true) ~= nil
end

local function Register(h)
    if h == nil or G.ByHandle[h] ~= nil then return nil end
    if not IsGeyserHandle(h) then return nil end
    local p = PositionOf(h)
    if p == nil then return nil end
    local rec = {
        h = h, x = p.x, y = p.y, z = p.z,
        occupied = false, checked = nil,
        period = 0.0, phase = 0.0,
    }
    G.Geysers[#G.Geysers + 1] = rec
    G.ByHandle[h] = rec
    return rec
end

local function Forget(rec)
    local live = G.Live[rec]
    if live ~= nil then
        for i = 1, #live.layers do G.FxDestroy(live.layers[i].name) end
        G.Live[rec] = nil
    end
    G.ByHandle[rec.h] = nil
    for i = 1, #G.Geysers do
        if G.Geysers[i] == rec then table.remove(G.Geysers, i) break end
    end
end

-- Walks every object once. Called at Init and then every RescanPeriod: geysers
-- can appear mid-mission (misn17 replaces a destroyed tower with one), and
-- OnObjectCreated catches those sooner when a mission forwards it.
function G.Rescan()
    G.Stats.scans = G.Stats.scans + 1
    G.Scanned = true
    local all = Global("AllObjects")
    if all == nil then return end
    local isBuilding = Global("IsBuilding")
    pcall(function()
        for h in all() do
            if G.ByHandle[h] == nil then
                local candidate = true
                if isBuilding ~= nil then
                    local ok, building = pcall(isBuilding, h)
                    candidate = ok and building and true or false
                end
                if candidate then Register(h) end
            end
        end
    end)

    local gone = {}
    for i = 1, #G.Geysers do
        if not ValidHandle(G.Geysers[i].h) then gone[#gone + 1] = G.Geysers[i] end
    end
    for i = 1, #gone do Forget(gone[i]) end
end

function G.OnObjectCreated(h)
    if not G.Initialized then return end
    Register(h)
end

-- =============================================================================
-- Occupancy
-- =============================================================================

local function IsOccupant(obj, geyser)
    if obj == geyser or not AliveHandle(obj) then return false end
    local class = CleanLower(GCall("GetClassLabel", obj))
    if NEVER_OCCUPANT[class] then return false end
    if NEVER_ODF[CleanLower(GCall("GetOdf", obj))] then return false end
    -- A craft counts only once it is deployed (a Recycler still driving over the
    -- pad does not take it); a building counts when it is a kind that deploys on
    -- a geyser. The engine may report a deployed Recycler as either.
    local craft = GCall("IsCraft", obj)
    if craft then
        return GCall("IsDeployed", obj) == true
    end
    return G.OccupantClasses[class] == true
end

local function ReadOccupied(rec)
    local range = Global("ObjectsInRange")
    if range == nil then return false end
    local occupied = false
    pcall(function()
        for obj in range(G.OccupyRadius, rec.h) do
            if IsOccupant(obj, rec.h) then occupied = true break end
        end
    end)
    return occupied
end

-- Re-reads a geyser's occupancy when the cached answer is stale.
local function Refresh(rec, force)
    if not force and rec.checked ~= nil and (G.Clock - rec.checked) < G.OccupancyTtl then
        return rec.occupied
    end
    G.Stats.polls = G.Stats.polls + 1
    rec.occupied = ReadOccupied(rec)
    rec.checked = G.Clock
    return rec.occupied
end

-- True when every known geyser within `radius` of (x, z) is taken. A vent site
-- that merges several nearby geysers stays open while any one of them is free.
-- False when no geyser is known there (fail open: draw the vent).
function G.IsOccupiedAt(x, z, radius)
    if not G.Initialized or not G.Enabled then return false end
    if not G.Scanned then G.Rescan() end
    radius = tonumber(radius) or G.MatchRadius
    local found = 0
    for i = 1, #G.Geysers do
        local rec = G.Geysers[i]
        if Distance2D(rec.x, rec.z, x, z) <= radius then
            found = found + 1
            if not Refresh(rec, false) then return false end
        end
    end
    return found > 0
end

-- =============================================================================
-- Particle systems (budgeted)
-- =============================================================================

function G.FxCreate(kind, template, x, y, z)
    if G.SystemCount >= G.MaxSystems then return nil end
    if (G.TemplateFailures[template] or 0) >= G.MaxFailuresPerTemplate then return nil end

    G.Serial = G.Serial + 1
    local name = "cr_gz_" .. kind .. "_" .. tostring(G.Serial)
    if Call("CreateParticleSystem", name, template, Vec(x, y, z)) ~= true then
        local failures = (G.TemplateFailures[template] or 0) + 1
        G.TemplateFailures[template] = failures
        if failures >= G.MaxFailuresPerTemplate then
            print("CRGeysers: " .. template .. " disabled after " .. tostring(failures) ..
                " failed particle creates (template unavailable)")
        end
        return nil
    end
    G.TemplateFailures[template] = 0
    G.Systems[name] = kind
    G.SystemCount = G.SystemCount + 1
    G.Stats.created = G.Stats.created + 1
    Call("SetParticleSystemKeepLocalSpace", name, false)
    Call("SetParticleSystemNonVisibleUpdateTimeout", name, 3.0)
    return name
end

function G.FxDestroy(name)
    if name == nil or G.Systems[name] == nil then return end
    Call("DestroyParticleSystem", name)
    G.Systems[name] = nil
    G.SystemCount = G.SystemCount - 1
    G.Stats.destroyed = G.Stats.destroyed + 1
end

local function FxDestroyAll()
    local names = {}
    for name in pairs(G.Systems) do names[#names + 1] = name end
    for i = 1, #names do G.FxDestroy(names[i]) end
    G.SystemCount = 0
end

-- =============================================================================
-- Quality
-- =============================================================================

-- How many geysers may be drawn, and how much each one emits.
local function LiveCap()
    local q = Clamp(G.Quality, 0.0, 1.0)
    return floor((G.MaxLive * q) + 0.5)
end

local function RateScale()
    return Clamp(G.Quality, 0.0, 1.5)
end

-- =============================================================================
-- Layers
-- =============================================================================

local function ApplyEmitter(name, index, e, scale)
    if e == nil then return end
    if e.color ~= nil then Call("SetParticleEmitterColor", name, index, e.color.start, e.color.finish) end
    if e.velocity ~= nil then Call("SetParticleEmitterVelocity", name, index, e.velocity[1], e.velocity[2]) end
    if e.life ~= nil then Call("SetParticleEmitterTimeToLive", name, index, e.life[1], e.life[2]) end
    if e.angle ~= nil then Call("SetParticleEmitterAngle", name, index, e.angle) end
end

local function ApplyLayer(name, layer, scale)
    if layer.size ~= nil then
        Call("SetParticleSystemDefaultDimensions", name, layer.size[1], layer.size[2])
    end
    if layer.quota ~= nil then
        Call("SetParticleSystemParticleQuota", name, math.max(8, floor((layer.quota * Clamp(scale, 0.25, 1.5)) + 0.5)))
    end
    ApplyEmitter(name, 0, layer.steady)
    ApplyEmitter(name, 1, layer.spurt)
    if layer.affectors ~= nil then
        for index, params in pairs(layer.affectors) do
            for parameter, value in pairs(params) do
                Call("SetParticleAffectorParameter", name, index, parameter, value)
            end
        end
    end
    Call("SetParticleEmitterEmissionRate", name, 0, layer.steady and (layer.steady.rate * scale) or 0.0)
    Call("SetParticleEmitterEmissionRate", name, 1, 0.0)
end

local function GroundY(rec)
    return (TerrainHeight(rec.x, rec.z) or rec.y or 0.0) + G.GroundLift
end

local function CreateGeyserFx(rec)
    local look = G.Look
    if look == nil or look.layers == nil then return nil end
    local scale = RateScale()
    local y = GroundY(rec)
    local made = {}
    for i = 1, #look.layers do
        local layer = look.layers[i]
        local name = G.FxCreate(layer.kind, layer.template, rec.x, y, rec.z)
        if name ~= nil then
            ApplyLayer(name, layer, scale)
            made[#made + 1] = { name = name, layer = layer, spurt = 0.0 }
        end
    end
    if #made == 0 then return nil end
    return { layers = made, scale = scale }
end

local function DestroyGeyserFx(rec)
    local live = G.Live[rec]
    if live == nil then return end
    for i = 1, #live.layers do G.FxDestroy(live.layers[i].name) end
    G.Live[rec] = nil
end

-- The geyser's spurt: 0 between spurts, a smooth rise and fall during one. The
-- period and the phase come from the map position, so every peer agrees.
local function Envelope(rec)
    local look = G.Look
    if look == nil then return 0.0 end
    if rec.period <= 0.0 then
        local range = look.spurtPeriod or { 20.0, 40.0 }
        rec.period = range[1] + (PositionHash(rec.x, rec.z, 1) * (range[2] - range[1]))
        rec.phase = PositionHash(rec.x, rec.z, 2) * rec.period
    end
    local length = look.spurtSeconds or 4.0
    local t = (G.Clock + rec.phase) % rec.period
    if t >= length then return 0.0 end
    local rise = math.min(1.0, length * 0.25)
    local fall = math.min(2.0, length * 0.4)
    if t < rise then return SmoothStep(t / rise) end
    if t < (length - fall) then return 1.0 end
    return 1.0 - SmoothStep((t - (length - fall)) / fall)
end

local function UpdateSpurts()
    local scale = RateScale()
    for rec, live in pairs(G.Live) do
        local env = Envelope(rec)
        for i = 1, #live.layers do
            local item = live.layers[i]
            local wanted = item.layer.spurt and (item.layer.spurt.rate * env * scale) or 0.0
            if math.abs(wanted - item.spurt) > 0.2 or (wanted == 0.0 and item.spurt ~= 0.0) then
                item.spurt = wanted
                Call("SetParticleEmitterEmissionRate", item.name, 1, wanted)
            end
        end
        -- Quality changed: rescale the steady jets and the quotas.
        if math.abs(scale - live.scale) > 0.01 then
            live.scale = scale
            for i = 1, #live.layers do
                local item = live.layers[i]
                Call("SetParticleEmitterEmissionRate", item.name, 0,
                    item.layer.steady and (item.layer.steady.rate * scale) or 0.0)
                if item.layer.quota ~= nil then
                    Call("SetParticleSystemParticleQuota", item.name,
                        math.max(8, floor((item.layer.quota * Clamp(scale, 0.25, 1.5)) + 0.5)))
                end
            end
        end
    end
end

-- =============================================================================
-- Streaming
-- =============================================================================

local function LiveCount()
    local n = 0
    for _ in pairs(G.Live) do n = n + 1 end
    return n
end

-- One pass: refresh occupancy where it matters, drop what is taken or far,
-- then add the nearest free geysers up to the cap.
local function StreamGeysers()
    local player = LocalPlayerPosition()
    if player == nil then return end
    local cap = LiveCap()
    local budget = G.PollBudget

    -- Live ones first: they must notice a building arriving.
    local drop = {}
    for rec in pairs(G.Live) do
        local d = Distance2D(rec.x, rec.z, player.x, player.z)
        if not ValidHandle(rec.h) or d > G.StreamOut then
            drop[#drop + 1] = rec
        else
            if budget > 0 and (rec.checked == nil or (G.Clock - rec.checked) >= G.OccupancyTtl) then
                budget = budget - 1
            end
            if Refresh(rec, false) then drop[#drop + 1] = rec end
        end
    end
    for i = 1, #drop do DestroyGeyserFx(drop[i]) end
    -- Fewer allowed than drawn (quality dropped): shed the farthest.
    while LiveCount() > cap do
        local worst, worstD = nil, -1.0
        for rec in pairs(G.Live) do
            local d = Distance2D(rec.x, rec.z, player.x, player.z)
            if d > worstD then worst, worstD = rec, d end
        end
        if worst == nil then break end
        DestroyGeyserFx(worst)
    end

    -- Candidates: free geysers in range, nearest first. Occupancy is read only
    -- for as many of them as the budget allows; an unread one waits a pass.
    local candidates = {}
    for i = 1, #G.Geysers do
        local rec = G.Geysers[i]
        if G.Live[rec] == nil then
            local d = Distance2D(rec.x, rec.z, player.x, player.z)
            if d < G.StreamIn then candidates[#candidates + 1] = { rec = rec, d = d } end
        end
    end
    table.sort(candidates, function(a, b) return a.d < b.d end)

    for i = 1, #candidates do
        local rec, d = candidates[i].rec, candidates[i].d
        if LiveCount() >= cap then
            -- Full: a clearly nearer geyser takes the place of the farthest one
            -- drawn, so the effects follow the player instead of staying where
            -- they were first drawn.
            local worst, worstD = nil, -1.0
            for liveRec in pairs(G.Live) do
                local liveD = Distance2D(liveRec.x, liveRec.z, player.x, player.z)
                if liveD > worstD then worst, worstD = liveRec, liveD end
            end
            if worst == nil or (d + G.SwapMargin) >= worstD then break end
            local fresh = rec.checked ~= nil and (G.Clock - rec.checked) < (G.OccupancyTtl * 2.0)
            if not fresh then
                if budget <= 0 then break end
                budget = budget - 1
                Refresh(rec, true)
            end
            if not rec.occupied then
                DestroyGeyserFx(worst)
                local live = CreateGeyserFx(rec)
                if live ~= nil then G.Live[rec] = live end
            end
        else
            local fresh = rec.checked ~= nil and (G.Clock - rec.checked) < (G.OccupancyTtl * 2.0)
            if not fresh then
                if budget <= 0 then break end
                budget = budget - 1
                Refresh(rec, true)
            end
            if not rec.occupied then
                local live = CreateGeyserFx(rec)
                if live ~= nil then G.Live[rec] = live end
            end
        end
    end
end

-- =============================================================================
-- Lifecycle
-- =============================================================================

local function EnsureTemplates()
    if G.TemplatesReady or G.TemplatesFailed then return G.TemplatesReady end
    local ok, templates = pcall(require, "CRParticleTemplates")
    if ok and type(templates) == "table" and type(templates.EnsureExtra) == "function" then
        local ready, reason = templates.EnsureExtra(G.PayloadName)
        if ready then
            G.TemplatesReady = true
            return true
        end
        print("CRGeysers: the " .. G.PayloadName .. " particle payload is unavailable (" ..
            tostring(reason) .. "); geyser effects are off")
    else
        print("CRGeysers: CRParticleTemplates could not be loaded; geyser effects are off")
    end
    G.TemplatesFailed = true
    return false
end

function G.IsOwnedByDirector(world)
    local look = G.Looks[world or G.World]
    return look ~= nil and look.director ~= nil
end

function G.GetWorld() return G.World end
function G.GetLook() return G.Look end
function G.GetGeysers() return G.Geysers end
function G.GetSystemCount() return G.SystemCount end

function G.GetLive()
    local out = {}
    for rec in pairs(G.Live) do out[#out + 1] = rec end
    return out
end

function G.Describe()
    local look = G.Look
    return string.format("CRGeysers world=%s look=%s geysers=%d live=%d systems=%d quality=%.2f",
        tostring(G.World), look and look.label or "stock", #G.Geysers, LiveCount(), G.SystemCount, G.Quality)
end

function G.Init(options)
    options = options or {}
    if options.debug ~= nil then G.Debug = options.debug and true or false end
    if options.enabled ~= nil then G.Enabled = options.enabled and true or false end
    if options.quality ~= nil then G.Quality = math.max(0.0, tonumber(options.quality) or 1.0) end
    if G.Initialized then return end

    G.World = options.world
    G.Look = G.World and G.Looks[G.World] or nil
    G.Clock, G.NextTickAt, G.NextFxAt, G.NextScanAt = 0.0, 0.0, 0.0, 0.0
    G.Scanned = false
    G.Geysers, G.ByHandle, G.Live = {}, {}, {}
    G.Systems, G.SystemCount, G.Serial = {}, 0, 0
    G.TemplateFailures = {}
    G.Stats = { scans = 0, polls = 0, created = 0, destroyed = 0 }
    G.Initialized = true
    Log("init: " .. G.Describe())
end

function G.Update(dt, quality)
    if not G.Initialized then return end
    if quality ~= nil then G.Quality = math.max(0.0, tonumber(quality) or G.Quality) end
    dt = tonumber(dt) or 0.0
    G.Clock = G.Clock + dt

    -- Disabled: tear down what is up and stay quiet.
    if not G.Enabled then
        if G.SystemCount > 0 then
            FxDestroyAll()
            G.Live = {}
        end
        return
    end

    -- A world with no look and no director has nothing to draw or to answer.
    if G.Look == nil then return end

    if G.Clock >= G.NextScanAt then
        G.NextScanAt = G.Clock + G.RescanPeriod
        G.Rescan()
    end

    -- Only the worlds this module draws need streaming.
    local look = G.Look
    if look == nil or look.layers == nil then return end
    if not EnsureTemplates() then return end

    if G.Clock >= G.NextTickAt then
        G.NextTickAt = G.Clock + G.TickPeriod
        StreamGeysers()
    end
    if G.Clock >= G.NextFxAt then
        G.NextFxAt = G.Clock + G.FxPeriod
        UpdateSpurts()
    end
end

-- Save-load tears the Ogre scene down and takes the systems with it; the
-- bookkeeping must forget them so the next pass rebuilds.
function G.ResetSystems()
    FxDestroyAll()
    G.Live = {}
    G.Systems, G.SystemCount = {}, 0
    for i = 1, #G.Geysers do G.Geysers[i].checked = nil end
end

function G.Shutdown()
    if not G.Initialized then return end
    FxDestroyAll()
    G.Live = {}
    G.Geysers, G.ByHandle = {}, {}
    G.Systems, G.SystemCount = {}, 0
    G.Scanned = false
    G.Initialized = false
    G.World, G.Look = nil, nil
end

return CRGeysers
