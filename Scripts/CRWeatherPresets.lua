-- CRWeatherPresets.lua
-- Data-driven weather presets for the Campaign Reimagined weather controller.
--
-- A preset is pure data. It owns the precipitation systems, the sky state, the
-- fog/ambient/sun targets, a wind vector, transition times, and an optional
-- lightning policy. CRWeather.lua reads these and owns all runtime behaviour;
-- nothing in this file talks to exu directly, so a mission or a settings page
-- can add a preset without touching the controller.
--
-- Coordinate note: Battlezone world space is Y-up, so a falling wind vector has
-- a negative y. Wind is a *direction*; speed lives in windSpeed.
--
-- Particle template names refer to particle_system blocks in
-- Materials/cr_weather.particle. Sky material names refer to
-- Materials/CR_weather.material. Both currently point at placeholder textures --
-- see docs/CR_REACTIVE_PRESENTATION.md for the art request list.

local CRWeatherPresets = {}

-- Emitter tables are keyed by emitter index, which is zero based to match
-- Ogre's own ordering and exu.SetParticleEmitter*. Index 0 is the emitter
-- declared first in the .particle block.
--
-- Every field is optional. Anything omitted keeps whatever the .particle script
-- authored, which is how a preset stays readable: it only states what it
-- changes about the shared template.
--
--   rate      particles per second at full intensity
--   velocity  { min, max } world units per second
--   ttl       { min, max } seconds
--   angle     emission cone half-angle in degrees
--   color     { r, g, b, a } or { start = {...}, finish = {...} }

CRWeatherPresets.Presets = {

    -- -------------------------------------------------------------------------
    -- Clear. Not a no-op: it is the target every other preset transitions out
    -- to, so it has to describe a real sky/fog/light state rather than nothing.
    -- -------------------------------------------------------------------------
    Clear = {
        name = "Clear",
        precipitation = {},
        sky = nil,                  -- nil leaves the map's own sky alone
        fog = nil,                  -- nil means "no weather contribution"
        ambient = nil,
        diffuse = nil,
        sunPowerScale = nil,
        wind = { x = 0.0, y = 0.0, z = 0.0 },
        windSpeed = 0.0,
        lightning = nil,
        transitionIn = 8.0,
        transitionOut = 8.0,
    },

    -- -------------------------------------------------------------------------
    -- Mars dust storm. The design note's recommended first vertical slice:
    -- orange-brown airborne dust, contracted visibility, lowered direct sun,
    -- strong lateral wind, occasional heavier debris flecks.
    -- -------------------------------------------------------------------------
    MarsDustStorm = {
        name = "MarsDustStorm",
        precipitation = {
            {
                system   = "cr_wx_dust_near",
                template = "CR/Weather/DustNear",
                offset   = { x = 0.0, y = 40.0, z = 0.0 },
                quota    = 2600,
                -- Dust is nearly horizontal, so the volume sits low and wide.
                emitters = {
                    [0] = {
                        rate     = 240.0,
                        velocity = { 30.0, 52.0 },
                        ttl      = { 2.2, 3.6 },
                        angle    = 22.0,
                        color    = {
                            start  = { r = 0.72, g = 0.47, b = 0.26, a = 0.55 },
                            finish = { r = 0.58, g = 0.36, b = 0.20, a = 0.35 },
                        },
                    },
                },
            },
            {
                system   = "cr_wx_dust_grit",
                template = "CR/Weather/DustGrit",
                offset   = { x = 0.0, y = 12.0, z = 0.0 },
                quota    = 400,
                emitters = {
                    [0] = {
                        rate     = 26.0,
                        velocity = { 44.0, 68.0 },
                        ttl      = { 1.2, 2.0 },
                        angle    = 10.0,
                    },
                },
            },
        },
        sky = {
            type      = "dome",
            material  = "CR_Sky/MarsStorm",
            curvature = 10.0,
            tiling    = 8.0,
            distance  = 4000.0,
        },
        fog           = { r = 0.55, g = 0.34, b = 0.19, fogStart = 30.0, fogEnd = 320.0 },
        ambient       = { r = 0.42, g = 0.30, b = 0.20 },
        diffuse       = { r = 0.52, g = 0.36, b = 0.22 },
        sunPowerScale = 0.55,
        wind          = { x = -0.94, y = -0.28, z = 0.19 },
        windSpeed     = 34.0,
        lightning     = nil,
        transitionIn  = 25.0,
        transitionOut = 40.0,
    },

    -- -------------------------------------------------------------------------
    -- Luna light snow. Stylised crystalline drift for the low-gravity maps:
    -- sparse, slow, cold sky, long-distance haze rather than a visibility wall.
    -- -------------------------------------------------------------------------
    LunaLightSnow = {
        name = "LunaLightSnow",
        precipitation = {
            {
                system   = "cr_wx_snow_light",
                template = "CR/Weather/SnowLight",
                offset   = { x = 0.0, y = 32.0, z = 0.0 },
                quota    = 1400,
                emitters = {
                    [0] = {
                        rate     = 55.0,
                        velocity = { 3.0, 7.0 },
                        ttl      = { 7.0, 11.0 },
                        angle    = 32.0,
                        color    = {
                            start  = { r = 0.88, g = 0.92, b = 1.00, a = 0.70 },
                            finish = { r = 0.80, g = 0.86, b = 1.00, a = 0.45 },
                        },
                    },
                },
            },
        },
        sky           = nil,
        fog           = { r = 0.30, g = 0.34, b = 0.42, fogStart = 90.0, fogEnd = 760.0 },
        ambient       = { r = 0.34, g = 0.38, b = 0.46 },
        diffuse       = nil,
        sunPowerScale = 0.88,
        wind          = { x = 0.25, y = -0.94, z = 0.20 },
        windSpeed     = 5.0,
        lightning     = nil,
        transitionIn  = 18.0,
        transitionOut = 22.0,
    },

    -- -------------------------------------------------------------------------
    -- Europa blizzard. Dense wind-driven snow, aggressive visibility
    -- contraction, blue-grey ambient shift, gust phases.
    -- -------------------------------------------------------------------------
    EuropaBlizzard = {
        name = "EuropaBlizzard",
        precipitation = {
            {
                system   = "cr_wx_snow_heavy",
                template = "CR/Weather/SnowHeavy",
                offset   = { x = 0.0, y = 36.0, z = 0.0 },
                quota    = 3200,
                emitters = {
                    [0] = {
                        rate     = 320.0,
                        velocity = { 18.0, 30.0 },
                        ttl      = { 2.6, 4.2 },
                        angle    = 26.0,
                        color    = {
                            start  = { r = 0.86, g = 0.90, b = 0.98, a = 0.85 },
                            finish = { r = 0.74, g = 0.80, b = 0.92, a = 0.50 },
                        },
                    },
                },
            },
        },
        sky = {
            type      = "dome",
            material  = "CR_Sky/Blizzard",
            curvature = 12.0,
            tiling    = 10.0,
            distance  = 3600.0,
        },
        fog           = { r = 0.62, g = 0.68, b = 0.78, fogStart = 18.0, fogEnd = 180.0 },
        ambient       = { r = 0.44, g = 0.50, b = 0.60 },
        diffuse       = { r = 0.50, g = 0.56, b = 0.66 },
        sunPowerScale = 0.42,
        wind          = { x = 0.70, y = -0.62, z = -0.35 },
        windSpeed     = 26.0,
        -- Gusts are a wind/rate modulation, not a separate system: one authored
        -- template covers calm and gale because the emitter rate is live.
        gusts = { period = 14.0, depth = 0.45 },
        lightning     = nil,
        transitionIn  = 30.0,
        transitionOut = 35.0,
    },

    -- -------------------------------------------------------------------------
    -- Volcanic ash. Slow dark fall, orange distant sky, drifting embers.
    -- -------------------------------------------------------------------------
    VolcanicAsh = {
        name = "VolcanicAsh",
        precipitation = {
            {
                system   = "cr_wx_ash_fall",
                template = "CR/Weather/AshFall",
                offset   = { x = 0.0, y = 44.0, z = 0.0 },
                quota    = 2000,
                emitters = {
                    [0] = {
                        rate     = 130.0,
                        velocity = { 5.0, 11.0 },
                        ttl      = { 6.0, 9.0 },
                        angle    = 28.0,
                        color    = {
                            start  = { r = 0.24, g = 0.22, b = 0.21, a = 0.80 },
                            finish = { r = 0.16, g = 0.15, b = 0.15, a = 0.45 },
                        },
                    },
                },
            },
            {
                system   = "cr_wx_ash_ember",
                template = "CR/Weather/AshEmber",
                offset   = { x = 0.0, y = 8.0, z = 0.0 },
                quota    = 220,
                emitters = {
                    [0] = {
                        rate     = 9.0,
                        velocity = { 2.0, 6.0 },
                        ttl      = { 2.5, 5.0 },
                        angle    = 55.0,
                        color    = {
                            start  = { r = 1.00, g = 0.55, b = 0.18, a = 0.95 },
                            finish = { r = 0.65, g = 0.16, b = 0.04, a = 0.00 },
                        },
                    },
                },
            },
        },
        sky = {
            type      = "dome",
            material  = "CR_Sky/AshFall",
            curvature = 10.0,
            tiling    = 6.0,
            distance  = 4200.0,
        },
        fog           = { r = 0.26, g = 0.19, b = 0.16, fogStart = 40.0, fogEnd = 420.0 },
        ambient       = { r = 0.28, g = 0.22, b = 0.19 },
        diffuse       = { r = 0.46, g = 0.30, b = 0.18 },
        sunPowerScale = 0.48,
        wind          = { x = -0.35, y = -0.90, z = 0.26 },
        windSpeed     = 9.0,
        lightning     = nil,
        transitionIn  = 28.0,
        transitionOut = 34.0,
    },

    -- -------------------------------------------------------------------------
    -- Fury spore storm. Deliberately not a palette-swapped rain: glowing motes,
    -- cyan-violet haze, biological rather than meteorological motion.
    -- -------------------------------------------------------------------------
    FurySporeStorm = {
        name = "FurySporeStorm",
        precipitation = {
            {
                system   = "cr_wx_spore",
                template = "CR/Weather/Spore",
                offset   = { x = 0.0, y = 26.0, z = 0.0 },
                quota    = 1200,
                emitters = {
                    [0] = {
                        rate     = 70.0,
                        velocity = { 2.0, 6.0 },
                        ttl      = { 8.0, 14.0 },
                        angle    = 75.0,
                        color    = {
                            start  = { r = 0.32, g = 0.90, b = 0.95, a = 0.90 },
                            finish = { r = 0.52, g = 0.30, b = 0.90, a = 0.20 },
                        },
                    },
                },
            },
        },
        sky = {
            type      = "dome",
            material  = "CR_Sky/Spore",
            curvature = 14.0,
            tiling    = 5.0,
            distance  = 3800.0,
        },
        fog           = { r = 0.14, g = 0.30, b = 0.34, fogStart = 55.0, fogEnd = 520.0 },
        ambient       = { r = 0.20, g = 0.34, b = 0.38 },
        diffuse       = { r = 0.26, g = 0.44, b = 0.52 },
        sunPowerScale = 0.62,
        wind          = { x = 0.18, y = -0.30, z = 0.42 },
        windSpeed     = 4.0,
        -- Alien "lightning" is a slow luminous surge, not a hard strike, so it
        -- has a long flash and no thunder.
        lightning = {
            minInterval = 9.0,
            maxInterval = 22.0,
            flash       = { r = 0.18, g = 0.55, b = 0.62 },
            flashTime   = 0.85,
            thunder     = nil,
        },
        transitionIn  = 22.0,
        transitionOut = 26.0,
    },

    -- -------------------------------------------------------------------------
    -- Acid rain. Visual only. If a mission wants acid to hurt, that is an
    -- explicit gameplay rule the mission owns; the weather layer never damages.
    -- -------------------------------------------------------------------------
    AcidRainVisual = {
        name = "AcidRainVisual",
        precipitation = {
            {
                system   = "cr_wx_rain",
                template = "CR/Weather/Rain",
                offset   = { x = 0.0, y = 34.0, z = 0.0 },
                quota    = 4000,
                emitters = {
                    [0] = {
                        rate     = 420.0,
                        velocity = { 46.0, 62.0 },
                        ttl      = { 1.4, 2.2 },
                        angle    = 8.0,
                        color    = {
                            start  = { r = 0.66, g = 0.78, b = 0.38, a = 0.55 },
                            finish = { r = 0.52, g = 0.64, b = 0.28, a = 0.30 },
                        },
                    },
                },
            },
            {
                -- A small bounded splash pool near the camera. The design note
                -- is explicit that we do not try to splash every raindrop.
                system   = "cr_wx_rain_splash",
                template = "CR/Weather/RainSplash",
                offset   = { x = 0.0, y = 0.5, z = 0.0 },
                quota    = 300,
                emitters = {
                    [0] = {
                        rate     = 55.0,
                        velocity = { 1.0, 3.0 },
                        ttl      = { 0.25, 0.45 },
                        angle    = 180.0,
                    },
                },
            },
        },
        sky = {
            type      = "dome",
            material  = "CR_Sky/Storm",
            curvature = 10.0,
            tiling    = 8.0,
            distance  = 3800.0,
        },
        fog           = { r = 0.24, g = 0.28, b = 0.20, fogStart = 35.0, fogEnd = 380.0 },
        ambient       = { r = 0.26, g = 0.30, b = 0.24 },
        diffuse       = { r = 0.34, g = 0.40, b = 0.30 },
        sunPowerScale = 0.44,
        wind          = { x = 0.32, y = -0.93, z = -0.18 },
        windSpeed     = 18.0,
        lightning = {
            minInterval = 6.0,
            maxInterval = 17.0,
            flash       = { r = 0.55, g = 0.60, b = 0.72 },
            flashTime   = 0.22,
            -- Thunder is delayed by distance so the flash reads as far away.
            thunder     = { sound = "xthunder.wav", minDelay = 1.5, maxDelay = 6.0 },
        },
        transitionIn  = 20.0,
        transitionOut = 28.0,
    },
}

-- Case-insensitive lookup so mission scripts and settings strings do not have
-- to match the table key exactly.
function CRWeatherPresets.Get(name)
    if name == nil then
        return nil
    end

    local direct = CRWeatherPresets.Presets[name]
    if direct then
        return direct
    end

    local wanted = string.lower(tostring(name))
    for key, preset in pairs(CRWeatherPresets.Presets) do
        if string.lower(key) == wanted then
            return preset
        end
    end

    return nil
end

function CRWeatherPresets.Names()
    local names = {}
    for key in pairs(CRWeatherPresets.Presets) do
        names[#names + 1] = key
    end
    table.sort(names)
    return names
end

return CRWeatherPresets
