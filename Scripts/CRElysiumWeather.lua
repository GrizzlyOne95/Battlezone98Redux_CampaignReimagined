-- CRElysiumWeather.lua
-- Elysium storm weather director for the Black Dog missions (bdmisn07, 09, 10, 11).
--
-- Elysium is a dead, Earth-like world under a thin remnant atmosphere: a bruised
-- violet-grey sky, wind, dust and ash, dry-lightning fronts and ground mist in the
-- ruins of the Chthonian city, and little rain (Docs/ELYSIUM_WEATHER.md). It has
-- no sulphur pools and no volcanoes, so this is NOT a new director: it is CRVenusWeather's
-- engine (seeded severity ladder, strikes, rain, cloud deck, fog banks, co-op
-- wire protocol) re-dressed. Init swaps in Elysium values for everything that was
-- sulphur-coloured, switches the sulphur / volcano layers off, and Shutdown puts
-- the Venus values back, so a later Venus mission in the same Lua state is
-- untouched. The module table inherits every other function from CRVenusWeather
-- (Update, Save, Load, AnnounceState, ApplyNetEvent, SetTargetLevel, ...).
--
-- What changes against Venus:
--   levels     five ElysiumCalm..ElysiumSevere presets (cold grey-violet fog from
--              80 to 250 at calm, cool light, no haze particles), a stronger wind
--              and more lightning than before, and little rain;
--   rain       a thin, ash-grey fall (the shared CR/Weather/Rain system at a
--              fraction of Venus's rate) that only the worst fronts bring, so
--              most strikes are dry; no acid film on the cockpit glass;
--   fog        the ground mist and the dust fronts (fog banks) are grey-violet
--              instead of sulphur; the cloud deck and mist use the CR/Elysium/*
--              templates (cr_elysium payload), the bolt, glow and St. Elmo come
--              from cr_venus (already blue-white);
--   flashes    a cold white-blue scene flash on a strike;
--   off        sulphur pools, pool fx, vents and eruptions.
-- Lightning, thunder, knockback, radar scramble and the net ops (VenusState,
-- VenusStrike, VenusErupt, VenusFog) are the Venus ones, unchanged.
--
-- Mission wiring (Scripts/CRCCARuntime.lua):
--   weather = { module = "CRElysiumWeather", sites = "CRElysiumSitesBD07",
--               startLevel = 1, targetLevel = 2 }
-- (ops defaults to the Venus op names, which this module shares.)
-- See Docs/ELYSIUM_WEATHER.md.

local Venus = require("CRVenusWeather")
local Presets = require("CRWeatherPresets")

local E = setmetatable({}, { __index = Venus })

-- ---- presets ----------------------------------------------------------------

local ROWS = {
    { name = "ElysiumCalm",   fog = { 0.60, 0.61, 0.68, 80.0, 250.0 }, amb = { 0.37, 0.38, 0.43 },
      dif = { 0.62, 0.62, 0.65 }, sun = 0.62, wind = 4.0,  strikes = 0.0,  tin = 20.0, tout = 26.0 },
    { name = "ElysiumHaze",   fog = { 0.52, 0.53, 0.60, 72.0, 215.0 }, amb = { 0.32, 0.33, 0.38 },
      dif = { 0.50, 0.51, 0.55 }, sun = 0.50, wind = 7.0,  strikes = 0.0,  tin = 22.0, tout = 28.0 },
    { name = "ElysiumRising", fog = { 0.42, 0.43, 0.50, 60.0, 180.0 }, amb = { 0.26, 0.27, 0.32 },
      dif = { 0.38, 0.39, 0.44 }, sun = 0.38, wind = 11.0, strikes = 3.0,  tin = 22.0, tout = 28.0 },
    { name = "ElysiumStorm",  fog = { 0.32, 0.33, 0.40, 45.0, 140.0 }, amb = { 0.20, 0.21, 0.26 },
      dif = { 0.27, 0.28, 0.33 }, sun = 0.24, wind = 16.0, strikes = 7.0,  tin = 20.0, tout = 26.0 },
    { name = "ElysiumSevere", fog = { 0.22, 0.23, 0.30, 32.0, 100.0 }, amb = { 0.14, 0.15, 0.20 },
      dif = { 0.18, 0.19, 0.25 }, sun = 0.14, wind = 22.0, strikes = 12.0, tin = 18.0, tout = 26.0 },
}

local function BuildPreset(row)
    return {
        name          = row.name,
        precipitation = {},   -- rain is the director's own layer, so it can follow the continuous severity
        sky           = nil,
        fog           = { r = row.fog[1], g = row.fog[2], b = row.fog[3], fogStart = row.fog[4], fogEnd = row.fog[5] },
        ambient       = { r = row.amb[1], g = row.amb[2], b = row.amb[3] },
        diffuse       = { r = row.dif[1], g = row.dif[2], b = row.dif[3] },
        sunPowerScale = row.sun,
        wind          = { x = 0.46, y = -0.14, z = -0.88 },
        windSpeed     = row.wind,
        lightning     = nil,
        transitionIn  = row.tin,
        transitionOut = row.tout,
    }
end

-- Registered at Init so the shared CRWeatherPresets.lua stays untouched.
function E.RegisterPresets()
    local presets = Presets.Presets
    if type(presets) ~= "table" then return 0 end
    local added = 0
    for i = 1, #ROWS do
        if presets[ROWS[i].name] == nil then
            presets[ROWS[i].name] = BuildPreset(ROWS[i])
            added = added + 1
        end
    end
    return added
end

-- ---- the Venus values this module replaces -----------------------------------

local LEVEL_NAMES = { "Calm", "Haze", "Rising", "Storm", "Severe" }
-- Rain is a trace (the dust is the weather); only a severe front brings real rain.
local LEVEL_FIELDS = {   -- rain, cloud, gloom, visibility, radarRange, velocJam, duration
    { 0.00, 0.20, 0.00, 100.0, 1.00, 1.00, { 80.0, 170.0 } },
    { 0.00, 0.40, 0.12, 92.0,  0.97, 1.03, { 70.0, 150.0 } },
    { 0.08, 0.65, 0.38, 84.0,  0.90, 1.08, { 60.0, 130.0 } },
    { 0.22, 0.88, 0.72, 74.0,  0.78, 1.18, { 50.0, 110.0 } },
    { 0.45, 1.00, 1.00, 60.0,  0.62, 1.32, { 35.0, 80.0 } },
}

local function BuildLevels()
    local levels = {}
    for i = 1, #ROWS do
        local f = LEVEL_FIELDS[i]
        levels[i] = {
            name = LEVEL_NAMES[i], preset = ROWS[i].name, windSpeed = ROWS[i].wind,
            strikesPerMinute = ROWS[i].strikes, rain = f[1], cloud = f[2], gloom = f[3],
            visibility = f[4], radarRange = f[5], velocJam = f[6], duration = f[7],
        }
    end
    return levels
end

local OVERRIDES = {
    AllowSulfur = false, AllowPoolFx = false, AllowVents = false, AllowEruptions = false,
    AllowGlassAcid = false,
    GloomGreen = 0.0,
    RainMaxRate = 210.0, RainSplashRate = 20.0,
    RainTint = { r = 0.62, g = 0.60, b = 0.64 },
    PoolFogColor = { r = 0.42, g = 0.42, b = 0.50 },
    FogBankColor = { r = 0.58, g = 0.57, b = 0.62 },
    FogBankAmbient = { r = 0.35, g = 0.35, b = 0.40 },
    FogBankDiffuse = { r = 0.51, g = 0.51, b = 0.56 },
    FogBankHazeColor = { r = 0.70, g = 0.68, b = 0.72 },
    FogBankHazeAlpha = 0.36,
    FlashAmbient = { r = 0.44, g = 0.44, b = 0.52 },
    FlashDiffuse = { r = 0.52, g = 0.52, b = 0.62 },
    CloudTintClear = { r = 0.36, g = 0.36, b = 0.43, a = 0.14 },
    CloudTintGloom = { r = 0.15, g = 0.15, b = 0.22, a = 0.30 },
    TemplatePayloads = { "cr_venus", "cr_elysium" },
    Templates = {
        fog = "CR/Elysium/FogPool", haze = "CR/Elysium/FogPool", cloud = "CR/Elysium/CloudDeck",
        elmo = "CR/Venus/StElmo", bolt = "CR/Venus/Bolt", glow = "CR/Venus/BoltGlow",
        sulfur = "CR/Venus/SulfurPool", plume = "CR/Venus/Plume", embers = "CR/Venus/Embers",
    },
}

local saved = nil   -- Venus values while Elysium is applied

local function Apply()
    if saved ~= nil then return end   -- a retried Init must not save Elysium values as Venus
    saved = { Levels = Venus.Levels }
    for key in pairs(OVERRIDES) do saved[key] = Venus[key] end
    for key, value in pairs(OVERRIDES) do Venus[key] = value end
    Venus.Levels = BuildLevels()
end

local function Restore()
    if saved == nil then return end
    for key, value in pairs(saved) do Venus[key] = value end
    saved = nil
end

-- ---- lifecycle -----------------------------------------------------------------

function E.Init(options)
    if Venus.Initialized then return end
    E.RegisterPresets()
    Apply()
    Venus.Init(options)
end

function E.Shutdown()
    Venus.Shutdown()
    Restore()
end

return E
