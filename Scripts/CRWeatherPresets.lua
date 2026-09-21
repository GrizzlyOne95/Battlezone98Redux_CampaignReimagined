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
-- CR template names refer to particle_system blocks in
-- Materials/cr_weather.particle; a preset may also reuse a mounted EXU weather
-- template explicitly, as VenusDenseAtmosphere does with EXU/WeatherMist. Sky
-- material names refer to Materials/CR_weather.material. CR's templates still
-- point at placeholder textures -- see docs/CR_REACTIVE_PRESENTATION.md for the
-- art request list.

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
--   params    type-specific Ogre emitter parameters, under their exact Ogre
--             spelling: a Box's width/height/depth, a Ring's inner_width, a
--             Cylinder's extent. These reach the concrete emitter's own
--             parameter dictionary through EXU's StringInterface bridge.
--   enabledAbove
--             live weight above which the emitter runs at all. Below it Ogre
--             skips the emitter outright instead of emitting zero particles,
--             which is how a preset says "this layer does not exist yet"
--             without paying for it every update.
--
-- A precipitation entry may also carry an `affectors` table, keyed by zero-based
-- affector index in .particle declaration order, each entry a table of that
-- affector's own Ogre parameters -- ColourFader `alpha`, DirectionRandomiser
-- `randomness`/`scope`, Scaler `rate`, Rotator speeds.
--
-- Any params or affectors value may be stated two ways:
--
--   alpha = -0.18              constant: sent once, then left alone
--   alpha = { -0.30, -0.12 }   { calm, full }: interpolated by live weight
--   colour1 = { "1 1 1 0", "1 1 1 0.12" }
--                              numeric text vectors interpolate component-wise
--
-- The pair form is what makes a storm change character as it builds rather than
-- only getting denser. Use CRWeather.DescribeSystem(name) in-game to read the
-- exact parameter spellings a template really exposes: an index or a name that
-- is wrong is ignored by Ogre in silence.

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
    -- Venus dense atmosphere development preset.
    --
    -- Native linear fog supplies almost all of the opacity. EXU/WeatherMist is
    -- deliberately only a sparse, camera-local veil: at full intensity and
    -- quality 1 it emits 6 cards/s into a quota of 72 (about 45 live cards at
    -- the authored mean lifetime). The mist's ColourInterpolator and Scaler
    -- are driven by the same live weight as emission, fog, ambient, diffuse and
    -- sun power, so Intensity is the single 0..1 control for the whole look.
    --
    -- This is intentionally a development preset rather than a mission
    -- schedule. Tune it with Tools/lcbench-venus.lua before assigning it to a
    -- campaign beat.
    -- -------------------------------------------------------------------------
    VenusDenseAtmosphere = {
        name = "VenusDenseAtmosphere",
        precipitation = {
            {
                system   = "cr_wx_venus_dense_mist",
                template = "EXU/WeatherMist",
                -- EXU/WeatherMist's Box emitter is already positioned +12 Y.
                -- A small negative camera offset keeps the cards low in frame
                -- without laying their hard intersections directly on terrain.
                offset   = { x = 0.0, y = -5.0, z = 0.0 },
                quota    = 72,
                emitters = {
                    [0] = {
                        rate     = 6.0,
                        velocity = { 0.8, 2.2 },
                        ttl      = { 5.0, 10.0 },
                        angle    = 38.0,
                        params   = {
                            width  = 360.0,
                            height = 30.0,
                            depth  = 360.0,
                        },
                    },
                },
                affectors = {
                    -- EXU/WeatherMist affector 0: ColourInterpolator. Keeping
                    -- every calm alpha at zero means particle opacity follows
                    -- the same intensity that drives native fog and lighting.
                    [0] = {
                        colour0 = "0.66 0.72 0.26 0.00",
                        colour1 = { "0.66 0.72 0.26 0.00", "0.66 0.72 0.26 0.11" },
                        colour2 = { "0.58 0.64 0.22 0.00", "0.58 0.64 0.22 0.07" },
                        colour3 = "0.54 0.58 0.18 0.00",
                    },
                    -- EXU/WeatherMist affector 1: Scaler.
                    [1] = { rate = { 0.0, 1.5 } },
                },
            },
        },
        sky           = nil,
        fog           = { r = 0.46, g = 0.50, b = 0.20, fogStart = 8.0, fogEnd = 155.0 },
        ambient       = { r = 0.45, g = 0.47, b = 0.29 },
        diffuse       = { r = 0.95, g = 0.98, b = 0.68 },
        sunPowerScale = 1.25,
        wind          = { x = 0.82, y = -0.06, z = -0.57 },
        windSpeed     = 3.0,
        lightning     = nil,
        transitionIn  = 8.0,
        transitionOut = 10.0,
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
                        -- The dust volume grows with the storm. Held at the
                        -- authored size instead, a building storm reads as the
                        -- same small cloud around the player slowly filling in,
                        -- which is the clearest tell that weather is a particle
                        -- effect rather than an atmosphere.
                        params   = {
                            width  = { 160.0, 300.0 },
                            height = {  50.0, 110.0 },
                            depth  = { 160.0, 300.0 },
                        },
                    },
                },
                affectors = {
                    -- ColourFader: alpha lost per second, so a more negative
                    -- number fades faster. Thin dust burns off almost at once;
                    -- storm dust hangs, and that hanging is most of why a storm
                    -- feels heavy.
                    [0] = { alpha = { -0.30, -0.12 } },
                    -- DirectionRandomiser: the turbulence. At calm the dust
                    -- drifts nearly straight; at full it churns.
                    [1] = { randomness = { 2.0, 10.0 }, scope = { 0.20, 0.50 } },
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
                        -- Debris is a threshold effect, not a gradient: wind
                        -- either lifts grit or it does not. Below a quarter
                        -- strength the layer is switched off rather than run at
                        -- a trickle, which also reads more honestly than three
                        -- lonely flecks drifting past.
                        enabledAbove = 0.25,
                        params   = {
                            width = { 120.0, 190.0 },
                            depth = { 120.0, 190.0 },
                        },
                    },
                },
            },
            {
                system   = "cr_wx_dust_sheet",
                template = "CR/Weather/DustSheet",
                offset   = { x = 0.0, y = 6.0, z = 0.0 },
                quota    = 900,
                emitters = {
                    [0] = {
                        rate     = 70.0,
                        velocity = { 58.0, 88.0 },
                        ttl      = { 1.6, 2.6 },
                        angle    = 6.0,
                        params   = {
                            width  = { 220.0, 340.0 },
                            height = {  10.0,  18.0 },
                            depth  = { 220.0, 340.0 },
                        },
                    },
                },
                affectors = {
                    [0] = { alpha = { -0.34, -0.14 } },
                    -- Scaler: how hard a streak stretches along its travel. This
                    -- is the layer that communicates wind speed, so it is the
                    -- one worth driving hardest.
                    [1] = { rate = { 1.2, 3.0 } },
                },
            },
            {
                system   = "cr_wx_mars_haze",
                template = "CR/Weather/MarsHaze",
                offset   = { x = 0.0, y = 55.0, z = 0.0 },
                quota    = 420,
                emitters = {
                    [0] = {
                        rate     = 30.0,
                        velocity = { 6.0, 12.0 },
                        ttl      = { 6.0, 9.0 },
                        angle    = 60.0,
                        color    = {
                            start  = { r = 0.66, g = 0.44, b = 0.26, a = 0.30 },
                            finish = { r = 0.58, g = 0.38, b = 0.22, a = 0.10 },
                        },
                        params   = {
                            width = { 360.0, 470.0 },
                            depth = { 360.0, 470.0 },
                        },
                    },
                },
                affectors = {
                    -- Barely any fade at all: the haze reads as depth in the air
                    -- rather than as particles with a lifetime.
                    [0] = { alpha = { -0.030, -0.010 } },
                },
            },
        },
        gusts = { period = 11.0, depth = 0.30 },
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
    -- Mars haze. The clear-weather baseline for a Mars map, and the reason the
    -- Mars family does not simply transition to Clear: the Martian atmosphere
    -- always carries suspended fines, so "no storm" is still a dusty sky rather
    -- than an empty one. Cheap enough to leave running for a whole mission.
    -- -------------------------------------------------------------------------
    MarsHaze = {
        name = "MarsHaze",
        precipitation = {
            {
                system   = "cr_wx_mars_haze",
                template = "CR/Weather/MarsHaze",
                offset   = { x = 0.0, y = 55.0, z = 0.0 },
                quota    = 420,
                emitters = {
                    [0] = {
                        rate     = 22.0,
                        velocity = { 3.0, 7.0 },
                        ttl      = { 7.0, 11.0 },
                        angle    = 60.0,
                        color    = {
                            start  = { r = 0.70, g = 0.50, b = 0.33, a = 0.16 },
                            finish = { r = 0.62, g = 0.43, b = 0.28, a = 0.06 },
                        },
                    },
                },
            },
        },
        sky = {
            type      = "dome",
            material  = "CR_Sky/MarsHaze",
            curvature = 12.0,
            tiling    = 6.0,
            distance  = 4000.0,
        },
        fog           = { r = 0.63, g = 0.45, b = 0.28, fogStart = 90.0, fogEnd = 520.0 },
        ambient       = { r = 0.48, g = 0.42, b = 0.36 },
        diffuse       = { r = 0.52, g = 0.44, b = 0.34 },
        sunPowerScale = 0.90,
        wind          = { x = -0.96, y = -0.12, z = 0.25 },
        windSpeed     = 10.0,
        gusts         = { period = 19.0, depth = 0.35 },
        lightning     = nil,
        transitionIn  = 30.0,
        transitionOut = 30.0,
    },

    -- -------------------------------------------------------------------------
    -- Mars dust rising. The middle rung: the storm front is visible and the
    -- wind has picked up, but the player can still fight and navigate. This is
    -- where a mission should spend most of its bad-weather time, because a full
    -- storm is a much stronger effect than it can sustain for long.
    -- -------------------------------------------------------------------------
    MarsDustRising = {
        name = "MarsDustRising",
        precipitation = {
            {
                system   = "cr_wx_mars_haze",
                template = "CR/Weather/MarsHaze",
                offset   = { x = 0.0, y = 55.0, z = 0.0 },
                quota    = 420,
                emitters = {
                    [0] = {
                        rate     = 26.0,
                        velocity = { 5.0, 10.0 },
                        ttl      = { 6.5, 10.0 },
                        angle    = 60.0,
                        color    = {
                            start  = { r = 0.68, g = 0.47, b = 0.29, a = 0.23 },
                            finish = { r = 0.60, g = 0.40, b = 0.25, a = 0.08 },
                        },
                    },
                },
            },
            {
                system   = "cr_wx_dust_near",
                template = "CR/Weather/DustNear",
                offset   = { x = 0.0, y = 40.0, z = 0.0 },
                quota    = 2600,
                emitters = {
                    [0] = {
                        rate     = 95.0,
                        velocity = { 20.0, 36.0 },
                        ttl      = { 2.4, 3.8 },
                        angle    = 28.0,
                        color    = {
                            start  = { r = 0.73, g = 0.49, b = 0.28, a = 0.38 },
                            finish = { r = 0.60, g = 0.38, b = 0.22, a = 0.20 },
                        },
                    },
                },
            },
            {
                system   = "cr_wx_dust_sheet",
                template = "CR/Weather/DustSheet",
                offset   = { x = 0.0, y = 6.0, z = 0.0 },
                quota    = 900,
                emitters = {
                    [0] = {
                        rate     = 34.0,
                        velocity = { 40.0, 62.0 },
                        ttl      = { 1.6, 2.6 },
                        angle    = 7.0,
                    },
                },
            },
        },
        sky = {
            type      = "dome",
            material  = "CR_Sky/MarsStorm",
            curvature = 11.0,
            tiling    = 7.0,
            distance  = 4000.0,
        },
        fog           = { r = 0.60, g = 0.40, b = 0.24, fogStart = 45.0, fogEnd = 380.0 },
        ambient       = { r = 0.45, g = 0.35, b = 0.26 },
        diffuse       = { r = 0.52, g = 0.40, b = 0.27 },
        sunPowerScale = 0.74,
        wind          = { x = -0.95, y = -0.20, z = 0.22 },
        windSpeed     = 21.0,
        gusts         = { period = 14.0, depth = 0.34 },
        lightning     = nil,
        transitionIn  = 22.0,
        transitionOut = 30.0,
    },

    -- -------------------------------------------------------------------------
    -- Mars dust storm, severe. The peak of the ladder and deliberately hostile:
    -- visibility falls below weapon range, the sun disc is gone, and sheet dust
    -- dominates the near field. A mission should hold this for a minute or two
    -- at most -- it is a set piece, not a weather condition.
    -- -------------------------------------------------------------------------
    MarsDustStormSevere = {
        name = "MarsDustStormSevere",
        precipitation = {
            {
                system   = "cr_wx_dust_near",
                template = "CR/Weather/DustNear",
                offset   = { x = 0.0, y = 40.0, z = 0.0 },
                quota    = 3200,
                emitters = {
                    [0] = {
                        rate     = 420.0,
                        velocity = { 46.0, 78.0 },
                        ttl      = { 1.8, 3.0 },
                        angle    = 18.0,
                        color    = {
                            start  = { r = 0.66, g = 0.40, b = 0.21, a = 0.74 },
                            finish = { r = 0.50, g = 0.29, b = 0.15, a = 0.52 },
                        },
                    },
                },
            },
            {
                system   = "cr_wx_dust_grit",
                template = "CR/Weather/DustGrit",
                offset   = { x = 0.0, y = 12.0, z = 0.0 },
                quota    = 600,
                emitters = {
                    [0] = {
                        rate     = 64.0,
                        velocity = { 70.0, 104.0 },
                        ttl      = { 1.0, 1.7 },
                        angle    = 8.0,
                    },
                },
            },
            {
                system   = "cr_wx_dust_sheet",
                template = "CR/Weather/DustSheet",
                offset   = { x = 0.0, y = 6.0, z = 0.0 },
                quota    = 1200,
                emitters = {
                    [0] = {
                        rate     = 140.0,
                        velocity = { 84.0, 126.0 },
                        ttl      = { 1.4, 2.2 },
                        angle    = 5.0,
                        color    = {
                            start  = { r = 0.72, g = 0.48, b = 0.27, a = 0.58 },
                            finish = { r = 0.55, g = 0.34, b = 0.19, a = 0.00 },
                        },
                    },
                },
            },
            {
                system   = "cr_wx_mars_haze",
                template = "CR/Weather/MarsHaze",
                offset   = { x = 0.0, y = 55.0, z = 0.0 },
                quota    = 420,
                emitters = {
                    [0] = {
                        rate     = 34.0,
                        velocity = { 9.0, 16.0 },
                        ttl      = { 5.0, 8.0 },
                        angle    = 60.0,
                        color    = {
                            start  = { r = 0.60, g = 0.38, b = 0.21, a = 0.42 },
                            finish = { r = 0.50, g = 0.31, b = 0.17, a = 0.16 },
                        },
                    },
                },
            },
        },
        sky = {
            type      = "dome",
            material  = "CR_Sky/MarsStormSevere",
            curvature = 9.0,
            tiling    = 9.0,
            distance  = 4000.0,
        },
        fog           = { r = 0.47, g = 0.27, b = 0.13, fogStart = 12.0, fogEnd = 130.0 },
        ambient       = { r = 0.30, g = 0.20, b = 0.13 },
        diffuse       = { r = 0.33, g = 0.22, b = 0.13 },
        sunPowerScale = 0.26,
        wind          = { x = -0.93, y = -0.32, z = 0.18 },
        windSpeed     = 54.0,
        gusts         = { period = 7.5, depth = 0.26 },
        lightning     = nil,
        transitionIn  = 18.0,
        transitionOut = 45.0,
    },

    -- =========================================================================
    -- Volcano flank (misn05)
    --
    -- A dormant Martian volcano is not a stormier plain, it is a different kind
    -- of place, and this family exists because reusing the plains ladder would
    -- have said otherwise. Three things separate it:
    --
    --   the ground layer is sheltered. Ridges break up the fast flat sheet dust
    --   that sells wind direction out on the plain, so SlopeDust replaces
    --   DustSheet: slower, taller, far more turbulent, climbing the flank
    --   rather than racing across it.
    --
    --   the suspended layer dominates. Less is being dragged along the ground,
    --   so what the player sees is mostly held in the air, and haze carries
    --   more of the storm here than it does on the plain.
    --
    --   the sky has its own weather. Mars builds orographic water-ice cloud
    --   over its Tharsis volcanoes, and that thin bright veil is the most
    --   recognisable thing about the setting. It is also the first thing the
    --   storm takes away: rising dust chokes it off from below, so it fades out
    --   as the ladder climbs instead of stacking underneath.
    --
    -- Fog stays longer-ranged than the plains equivalents at every rung. On a
    -- flank you are usually looking across open air rather than along the
    -- ground, and contracting visibility as hard as MarsDustStorm does would
    -- flatten the terrain the mission is built around.
    -- =========================================================================

    -- Rung 1. Clear for a volcano: thin haze and a standing ice veil.
    MarsVolcanoClear = {
        name = "MarsVolcanoClear",
        precipitation = {
            {
                system   = "cr_wx_v_veil",
                template = "CR/Weather/OrographicVeil",
                offset   = { x = 0.0, y = 210.0, z = 0.0 },
                quota    = 260,
                emitters = {
                    [0] = {
                        rate     = 9.0,
                        velocity = { 2.0, 6.0 },
                        ttl      = { 26.0, 40.0 },
                        angle    = 18.0,
                        params   = { width = 900.0, depth = 900.0 },
                    },
                },
                affectors = { [0] = { alpha = -0.0025 } },
            },
            {
                system   = "cr_wx_v_haze",
                template = "CR/Weather/MarsHaze",
                offset   = { x = 0.0, y = 60.0, z = 0.0 },
                quota    = 420,
                emitters = {
                    [0] = {
                        rate     = 20.0,
                        velocity = { 3.0, 7.0 },
                        ttl      = { 8.0, 12.0 },
                        angle    = 60.0,
                        color    = {
                            start  = { r = 0.71, g = 0.52, b = 0.36, a = 0.14 },
                            finish = { r = 0.63, g = 0.45, b = 0.30, a = 0.05 },
                        },
                        params   = { width = 420.0, depth = 420.0 },
                    },
                },
                affectors = { [0] = { alpha = -0.012 } },
            },
        },
        fog           = { r = 0.62, g = 0.47, b = 0.33, fogStart = 110.0, fogEnd = 620.0 },
        ambient       = { r = 0.49, g = 0.44, b = 0.39 },
        diffuse       = { r = 0.54, g = 0.47, b = 0.38 },
        sunPowerScale = 0.96,
        wind          = { x = -0.90, y = -0.10, z = 0.42 },
        windSpeed     = 7.0,
        gusts         = { period = 21.0, depth = 0.30 },
        lightning     = nil,
        transitionIn  = 24.0,
        transitionOut = 24.0,
    },

    -- Rung 2. The flank starts to breathe: slope dust appears, veil intact.
    MarsVolcanoBreeze = {
        name = "MarsVolcanoBreeze",
        precipitation = {
            {
                system   = "cr_wx_v_veil",
                template = "CR/Weather/OrographicVeil",
                offset   = { x = 0.0, y = 210.0, z = 0.0 },
                quota    = 260,
                emitters = {
                    [0] = {
                        rate     = 8.0,
                        velocity = { 3.0, 8.0 },
                        ttl      = { 22.0, 34.0 },
                        angle    = 20.0,
                        params   = { width = 900.0, depth = 900.0 },
                    },
                },
                affectors = { [0] = { alpha = -0.0030 } },
            },
            {
                system   = "cr_wx_v_haze",
                template = "CR/Weather/MarsHaze",
                offset   = { x = 0.0, y = 60.0, z = 0.0 },
                quota    = 420,
                emitters = {
                    [0] = {
                        rate     = 26.0,
                        velocity = { 4.0, 9.0 },
                        ttl      = { 7.5, 11.0 },
                        angle    = 60.0,
                        params   = { width = { 420.0, 460.0 }, depth = { 420.0, 460.0 } },
                    },
                },
                affectors = { [0] = { alpha = { -0.020, -0.012 } } },
            },
            {
                system   = "cr_wx_v_slope",
                template = "CR/Weather/SlopeDust",
                offset   = { x = 0.0, y = 14.0, z = 0.0 },
                quota    = 800,
                emitters = {
                    [0] = {
                        rate     = 30.0,
                        velocity = { 20.0, 34.0 },
                        ttl      = { 2.4, 4.0 },
                        angle    = 16.0,
                        params   = {
                            width  = { 190.0, 250.0 },
                            height = {  34.0,  50.0 },
                            depth  = { 190.0, 250.0 },
                        },
                    },
                },
                affectors = {
                    [0] = { alpha = { -0.24, -0.16 } },
                    [1] = { randomness = { 6.0, 11.0 }, scope = { 0.40, 0.55 } },
                    [2] = { rate = { 1.1, 1.6 } },
                },
            },
        },
        fog           = { r = 0.60, g = 0.45, b = 0.31, fogStart = 95.0, fogEnd = 560.0 },
        ambient       = { r = 0.48, g = 0.42, b = 0.36 },
        diffuse       = { r = 0.53, g = 0.45, b = 0.36 },
        sunPowerScale = 0.90,
        wind          = { x = -0.92, y = -0.06, z = 0.39 },
        windSpeed     = 16.0,
        gusts         = { period = 15.0, depth = 0.34 },
        lightning     = nil,
        transitionIn  = 22.0,
        transitionOut = 28.0,
    },

    -- Rung 3. Dust is being lifted up the flank. The veil starts to go.
    MarsVolcanoRising = {
        name = "MarsVolcanoRising",
        precipitation = {
            {
                system   = "cr_wx_v_veil",
                template = "CR/Weather/OrographicVeil",
                offset   = { x = 0.0, y = 210.0, z = 0.0 },
                quota    = 200,
                emitters = {
                    [0] = {
                        -- Choked off from below rather than blown away: the rate
                        -- falls as the layer beneath it thickens.
                        rate     = 3.0,
                        velocity = { 4.0, 10.0 },
                        ttl      = { 16.0, 26.0 },
                        angle    = 24.0,
                        params   = { width = 900.0, depth = 900.0 },
                    },
                },
                affectors = { [0] = { alpha = -0.0060 } },
            },
            {
                system   = "cr_wx_v_haze",
                template = "CR/Weather/MarsHaze",
                offset   = { x = 0.0, y = 58.0, z = 0.0 },
                quota    = 520,
                emitters = {
                    [0] = {
                        rate     = 40.0,
                        velocity = { 5.0, 11.0 },
                        ttl      = { 7.0, 10.5 },
                        angle    = 60.0,
                        color    = {
                            start  = { r = 0.68, g = 0.47, b = 0.30, a = 0.24 },
                            finish = { r = 0.60, g = 0.40, b = 0.25, a = 0.08 },
                        },
                        params   = { width = { 420.0, 480.0 }, depth = { 420.0, 480.0 } },
                    },
                },
                affectors = { [0] = { alpha = { -0.026, -0.014 } } },
            },
            {
                system   = "cr_wx_v_slope",
                template = "CR/Weather/SlopeDust",
                offset   = { x = 0.0, y = 16.0, z = 0.0 },
                quota    = 900,
                emitters = {
                    [0] = {
                        rate     = 64.0,
                        velocity = { 26.0, 44.0 },
                        ttl      = { 2.4, 4.0 },
                        angle    = 18.0,
                        params   = {
                            width  = { 210.0, 290.0 },
                            height = {  40.0,  66.0 },
                            depth  = { 210.0, 290.0 },
                        },
                    },
                },
                affectors = {
                    [0] = { alpha = { -0.26, -0.15 } },
                    [1] = { randomness = { 8.0, 14.0 }, scope = { 0.45, 0.62 } },
                    [2] = { rate = { 1.3, 2.0 } },
                },
            },
        },
        fog           = { r = 0.58, g = 0.41, b = 0.27, fogStart = 70.0, fogEnd = 450.0 },
        ambient       = { r = 0.46, g = 0.37, b = 0.28 },
        diffuse       = { r = 0.53, g = 0.41, b = 0.30 },
        sunPowerScale = 0.76,
        wind          = { x = -0.94, y = -0.02, z = 0.34 },
        windSpeed     = 27.0,
        gusts         = { period = 12.0, depth = 0.36 },
        lightning     = nil,
        transitionIn  = 24.0,
        transitionOut = 36.0,
    },

    -- Rung 4. A storm on the flank. No veil left; the sky is dust.
    MarsVolcanoStorm = {
        name = "MarsVolcanoStorm",
        precipitation = {
            {
                system   = "cr_wx_v_haze",
                template = "CR/Weather/MarsHaze",
                offset   = { x = 0.0, y = 56.0, z = 0.0 },
                quota    = 560,
                emitters = {
                    [0] = {
                        rate     = 54.0,
                        velocity = { 7.0, 14.0 },
                        ttl      = { 6.0, 9.5 },
                        angle    = 62.0,
                        color    = {
                            start  = { r = 0.64, g = 0.42, b = 0.25, a = 0.33 },
                            finish = { r = 0.56, g = 0.36, b = 0.21, a = 0.11 },
                        },
                        params   = { width = { 440.0, 500.0 }, depth = { 440.0, 500.0 } },
                    },
                },
                affectors = { [0] = { alpha = { -0.028, -0.013 } } },
            },
            {
                system   = "cr_wx_v_near",
                template = "CR/Weather/DustNear",
                offset   = { x = 0.0, y = 34.0, z = 0.0 },
                quota    = 2200,
                emitters = {
                    [0] = {
                        rate     = 190.0,
                        velocity = { 26.0, 46.0 },
                        ttl      = { 2.4, 3.8 },
                        angle    = 26.0,
                        color    = {
                            start  = { r = 0.71, g = 0.46, b = 0.26, a = 0.50 },
                            finish = { r = 0.57, g = 0.35, b = 0.20, a = 0.30 },
                        },
                        params   = {
                            width  = { 170.0, 280.0 },
                            height = {  60.0, 120.0 },
                            depth  = { 170.0, 280.0 },
                        },
                    },
                },
                affectors = {
                    [0] = { alpha = { -0.30, -0.13 } },
                    [1] = { randomness = { 4.0, 12.0 }, scope = { 0.28, 0.58 } },
                },
            },
            {
                system   = "cr_wx_v_slope",
                template = "CR/Weather/SlopeDust",
                offset   = { x = 0.0, y = 18.0, z = 0.0 },
                quota    = 1000,
                emitters = {
                    [0] = {
                        rate     = 96.0,
                        velocity = { 34.0, 56.0 },
                        ttl      = { 2.2, 3.6 },
                        angle    = 20.0,
                        params   = {
                            width  = { 230.0, 320.0 },
                            height = {  46.0,  78.0 },
                            depth  = { 230.0, 320.0 },
                        },
                    },
                },
                affectors = {
                    [0] = { alpha = { -0.28, -0.15 } },
                    [1] = { randomness = { 10.0, 17.0 }, scope = { 0.50, 0.68 } },
                    [2] = { rate = { 1.5, 2.4 } },
                },
            },
            {
                system   = "cr_wx_v_grit",
                template = "CR/Weather/DustGrit",
                offset   = { x = 0.0, y = 12.0, z = 0.0 },
                quota    = 400,
                emitters = {
                    [0] = {
                        rate         = 22.0,
                        velocity     = { 40.0, 62.0 },
                        ttl          = { 1.2, 2.0 },
                        angle        = 12.0,
                        -- Grit needs a flow fast enough to carry it, and on a
                        -- sheltered flank that only happens near the top of the
                        -- ladder.
                        enabledAbove = 0.40,
                        params       = { width = { 120.0, 180.0 }, depth = { 120.0, 180.0 } },
                    },
                },
            },
        },
        fog           = { r = 0.54, g = 0.35, b = 0.21, fogStart = 45.0, fogEnd = 340.0 },
        ambient       = { r = 0.42, g = 0.31, b = 0.22 },
        diffuse       = { r = 0.51, g = 0.36, b = 0.23 },
        sunPowerScale = 0.58,
        wind          = { x = -0.95, y = 0.02, z = 0.30 },
        windSpeed     = 40.0,
        gusts         = { period = 10.0, depth = 0.32 },
        lightning     = nil,
        transitionIn  = 26.0,
        transitionOut = 42.0,
    },

    -- Rung 5. Summit blackout. Kept shorter-lived than the plains equivalent:
    -- the mission is fought on ridges above mined gullies, and weather that
    -- makes the ridgeline unreadable for long stops being drama and starts
    -- being an unfair death.
    MarsVolcanoSevere = {
        name = "MarsVolcanoSevere",
        precipitation = {
            {
                system   = "cr_wx_v_haze",
                template = "CR/Weather/MarsHaze",
                offset   = { x = 0.0, y = 54.0, z = 0.0 },
                quota    = 620,
                emitters = {
                    [0] = {
                        rate     = 72.0,
                        velocity = { 9.0, 18.0 },
                        ttl      = { 5.5, 9.0 },
                        angle    = 64.0,
                        color    = {
                            start  = { r = 0.58, g = 0.36, b = 0.20, a = 0.42 },
                            finish = { r = 0.50, g = 0.30, b = 0.17, a = 0.15 },
                        },
                        params   = { width = { 460.0, 520.0 }, depth = { 460.0, 520.0 } },
                    },
                },
                affectors = { [0] = { alpha = { -0.030, -0.012 } } },
            },
            {
                system   = "cr_wx_v_near",
                template = "CR/Weather/DustNear",
                offset   = { x = 0.0, y = 32.0, z = 0.0 },
                quota    = 2600,
                emitters = {
                    [0] = {
                        rate     = 280.0,
                        velocity = { 34.0, 58.0 },
                        ttl      = { 2.2, 3.6 },
                        angle    = 28.0,
                        color    = {
                            start  = { r = 0.68, g = 0.43, b = 0.24, a = 0.62 },
                            finish = { r = 0.54, g = 0.33, b = 0.18, a = 0.38 },
                        },
                        params   = {
                            width  = { 190.0, 300.0 },
                            height = {  70.0, 130.0 },
                            depth  = { 190.0, 300.0 },
                        },
                    },
                },
                affectors = {
                    [0] = { alpha = { -0.28, -0.11 } },
                    [1] = { randomness = { 6.0, 15.0 }, scope = { 0.34, 0.66 } },
                },
            },
            {
                system   = "cr_wx_v_slope",
                template = "CR/Weather/SlopeDust",
                offset   = { x = 0.0, y = 18.0, z = 0.0 },
                quota    = 1100,
                emitters = {
                    [0] = {
                        rate     = 130.0,
                        velocity = { 44.0, 70.0 },
                        ttl      = { 2.0, 3.4 },
                        angle    = 22.0,
                        params   = {
                            width  = { 250.0, 340.0 },
                            height = {  52.0,  88.0 },
                            depth  = { 250.0, 340.0 },
                        },
                    },
                },
                affectors = {
                    [0] = { alpha = { -0.26, -0.14 } },
                    [1] = { randomness = { 12.0, 20.0 }, scope = { 0.54, 0.72 } },
                    [2] = { rate = { 1.7, 2.8 } },
                },
            },
            {
                system   = "cr_wx_v_grit",
                template = "CR/Weather/DustGrit",
                offset   = { x = 0.0, y = 12.0, z = 0.0 },
                quota    = 460,
                emitters = {
                    [0] = {
                        rate         = 40.0,
                        velocity     = { 52.0, 78.0 },
                        ttl          = { 1.1, 1.9 },
                        angle        = 14.0,
                        enabledAbove = 0.25,
                        params       = { width = { 130.0, 200.0 }, depth = { 130.0, 200.0 } },
                    },
                },
            },
        },
        fog           = { r = 0.49, g = 0.30, b = 0.17, fogStart = 24.0, fogEnd = 210.0 },
        ambient       = { r = 0.37, g = 0.26, b = 0.18 },
        diffuse       = { r = 0.46, g = 0.30, b = 0.19 },
        sunPowerScale = 0.42,
        wind          = { x = -0.96, y = 0.05, z = 0.26 },
        windSpeed     = 56.0,
        gusts         = { period = 8.0, depth = 0.30 },
        lightning     = nil,
        transitionIn  = 20.0,
        transitionOut = 46.0,
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
            -- "xthunder.wav" was named here and exists nowhere on a Redux
            -- install; StartSound failed and pcall ate it, so the flash was
            -- always silent. thunder.wav is the real clip. CR ships no audio of
            -- its own, so this resolves only where an addon providing it is
            -- mounted -- CRWeather logs once if it cannot be played.
            thunder     = { sound = "thunder.wav", minDelay = 1.5, maxDelay = 6.0 },
        },
        transitionIn  = 20.0,
        transitionOut = 28.0,
    },

    -- -------------------------------------------------------------------------
    -- Venus. The one world in the set where lightning is the point rather than
    -- a garnish, so it is the reason CRWeather's lightning policy exists at all.
    --
    -- Three things shape this preset, and none of them is "rain with a filter":
    --
    --   nothing falls. Venus has sulphuric acid cloud, but it evaporates
    --   kilometres above the ground -- virga, never precipitation. So there is
    --   no rain layer here at all. What the player sees is suspended.
    --
    --   the air is thick, not fast. Surface wind is slow, but the atmosphere is
    --   ~90x Earth's density, so slow air still drags heavy material. windSpeed
    --   stays low while the grit layer carries unusually large particles.
    --
    --   no direct sun reaches the surface. Everything is scattered. diffuse is
    --   warm and flat and sunPowerScale is the lowest in the file, because a
    --   hard sun angle would read as a different planet.
    --
    -- The MarsHaze template is named for where it debuted, not for what it is:
    -- it is the generic suspended-haze layer and it draws CR_FX/Haze.
    -- -------------------------------------------------------------------------
    VenusSulphurStorm = {
        name = "VenusSulphurStorm",
        precipitation = {
            {
                system   = "cr_wx_venus_haze",
                template = "CR/Weather/MarsHaze",
                offset   = { x = 0.0, y = 30.0, z = 0.0 },
                quota    = 900,
                emitters = {
                    [0] = {
                        rate     = 38.0,
                        velocity = { 1.5, 4.0 },
                        ttl      = { 14.0, 22.0 },
                        angle    = 80.0,
                        color    = {
                            start  = { r = 0.78, g = 0.60, b = 0.26, a = 0.42 },
                            finish = { r = 0.52, g = 0.38, b = 0.16, a = 0.00 },
                        },
                    },
                },
            },
            {
                system   = "cr_wx_venus_grit",
                template = "CR/Weather/DustGrit",
                offset   = { x = 0.0, y = 3.0, z = 0.0 },
                quota    = 420,
                emitters = {
                    [0] = {
                        rate     = 26.0,
                        velocity = { 2.0, 5.0 },
                        ttl      = { 3.5, 6.5 },
                        angle    = 40.0,
                        color    = {
                            start  = { r = 0.62, g = 0.47, b = 0.22, a = 0.70 },
                            finish = { r = 0.40, g = 0.29, b = 0.12, a = 0.15 },
                        },
                    },
                },
            },
        },
        -- No sky block. The CR_Sky domes are still placeholders and the layer
        -- only engages when a mission supplies a baseSky, which none do yet.
        -- Naming an eighth orphan sky material here would add a placeholder
        -- rather than remove one. Add it with the art, not before.
        sky           = nil,
        fog           = { r = 0.42, g = 0.30, b = 0.13, fogStart = 22.0, fogEnd = 260.0 },
        ambient       = { r = 0.38, g = 0.29, b = 0.16 },
        diffuse       = { r = 0.52, g = 0.40, b = 0.20 },
        sunPowerScale = 0.34,
        wind          = { x = 0.46, y = -0.12, z = -0.88 },
        windSpeed     = 5.0,
        gusts         = { period = 19.0, depth = 0.22 },
        -- Frequent, and the flash is warm because it is being scattered through
        -- a great deal of sulphur before it reaches the player. Thunder lags
        -- hard: the strike belongs to the cloud deck, which is a long way up.
        lightning = {
            minInterval = 4.0,
            maxInterval = 13.0,
            -- Held to 0.44 deliberately: ambient is already 0.38 here and the
            -- flash is added, not blended, so 0.62 put the red channel at
            -- exactly 1.00 -- saturated before Intensity or a second layer got
            -- a say. 0.82 peak matches AcidRainVisual and leaves headroom.
            flash       = { r = 0.44, g = 0.36, b = 0.22 },
            flashTime   = 0.30,
            thunder     = { sound = "thunder.wav", minDelay = 2.5, maxDelay = 8.0 },
        },
        transitionIn  = 24.0,
        transitionOut = 30.0,
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
