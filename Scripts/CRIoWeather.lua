-- CRIoWeather.lua
-- Io weather and atmosphere director for Campaign Reimagined (first user: misn10
-- "The Race is On").
--
-- This is the Io counterpart of CRVenusWeather and follows its architecture: a
-- controller that owns the minute-to-minute decisions, CRWeather presets for the
-- fog / light / haze it hands to Environment.lua, and a generated per-mission
-- data file (CRIoSites10) for everything that has to come from the map.
--
-- EVERYTHING HERE IS COSMETIC. The director never damages, shoves, scrambles,
-- slows, spawns or removes anything, registers no gameplay modifier and writes
-- no velocity. It only draws, lights and shakes the view.
--
-- Parts:
--
--   ladder       five rungs -- calm, restless, active, intense, paroxysm -- as a
--                seeded timeline (CRVenusMap.NewLadder) with temporary intense
--                EPISODES. The fractional position drives everything
--                continuous; integer rungs select a CRWeather preset.
--   atmosphere   thin volcanic haze: the five Io* presets (fog, sun power, haze)
--                plus this module's own Environment modifier. The light itself
--                is Environment.lua's orbit (sun, eclipse, Jupiter-shine).
--   lava fog     red, glowing, low fog pools streamed in over the molten lava
--                tiles of the map (anchors generated from the .mat by
--                Tools/Build-IoSites.py), and a lava factor that reddens the
--                global fog and light as the local player drives over lava.
--   fog by       the terrain is height-sampled once (CRVenusMap.NewHeightScan)
--   altitude     and the global fog thickens a little in enclosed lowland.
--   vents        a smoke plume at every geyser object; each vent erupts on its
--                own staggered period (host-decided, replicated): a tall ash
--                column, a glowing core, thrown spatter, rumble, and a red lift
--                on the ambient light near the vent.
--   ash fall     camera-attached CR/Io/AshFall driven by the ladder.
--   quakes       the stock StartEarthquake / UpdateEarthQuake / StopEarthquake
--                natives driven by an envelope, plus dust and extra ash. Quakes
--                are scripted (CRIoWeather.Quake) or random, host-decided and
--                replicated, so every peer shakes at the same time.
--
-- CO-OP. The same hybrid as CRVenusWeather:
--   * The severity timeline is a pure function of a seed; the host announces the
--     seed and its rung (IoState) on change and as a heartbeat, a guest follows
--     the rung for HostOverrideSeconds and then falls back to the seeded timeline.
--   * Eruptions and quakes are decided ONLY by the host and sent as one small
--     event each (IoErupt, IoQuake); every peer renders and shakes on receipt.
--   * Lava fog, ash, haze, plume smoke and altitude fog are local, from static
--     map data.
-- See Docs/IO_WEATHER.md for the wire protocol and the mission wiring.
--
-- Ownership rules (same as CRVenusWeather / CRMarsWeather):
--   * Fog, ambient and sun belong to Environment.lua. We set a CRWeather preset
--     and register an Environment modifier; we never call exu.SetFog and friends.
--   * Nothing in this file calls anything that changes health, ammo, velocity,
--     gravity or sensors.

local exu = require("exu")
local CRWeather = require("CRWeather")
local Wake = require("CRWake")
local CRWeatherPresets = require("CRWeatherPresets")
local Map = require("CRVenusMap")
local PoolFX = require("CRPoolFX")

local CRIoWeather = {}
local V = CRIoWeather

-- =============================================================================
-- Configuration
-- =============================================================================

V.Enabled              = true
V.Debug                = false

-- Each sub-system is independently switchable.
V.AllowLavaFog         = true    -- red fog pools over the lava tiles
V.AllowLavaGlow        = true    -- the additive glow half of a pool
V.AllowLavaTint        = true    -- global fog / light reddens over lava
V.AllowPoolFx          = true    -- bubble pops, rising embers and spatter on the molten pools (CRPoolFX)
V.AllowAltitudeFog     = true    -- global fog density follows the player's altitude
V.AllowAshFall         = true
V.AllowVents           = true    -- smoke plumes at the geysers
V.AllowEruptions       = true
V.AllowEruptLight      = true    -- red ambient lift near an eruption
V.AllowQuakes          = true    -- Quake() and quake events do anything at all
V.AllowRandomQuakes    = true    -- the host schedules unscripted quakes
V.AllowQuakeDust       = true
V.AllowEpisodes        = true    -- temporary intense spells
V.AllowRenderIntents   = true

-- Hard budgets. These are caps, not targets.
V.MaxSystems           = 40      -- every particle system this module owns, at once
V.MaxLiveLava          = 6
V.MaxLiveGlow          = 4       -- additive glow halves among the live lava pools
V.MaxLivePlumes        = 8
V.MaxLiveEruptFx       = 4       -- plumes that may carry a glow core + spatter at once
V.MaxFailuresPerTemplate = 3

-- Streaming: a system is created inside StreamIn and destroyed beyond StreamOut.
V.LavaStreamIn         = 380.0
V.LavaStreamOut        = 500.0
V.PlumeStreamIn        = 1100.0
V.PlumeStreamOut       = 1350.0
V.StreamInterval       = 1.0     -- seconds between streaming passes

-- Severity ladder.
V.SeverityRate         = 0.050   -- rungs per second the smoothed position moves
V.EpisodeChance        = 0.30    -- per rung change at "active" or worse
V.EpisodePeak          = { 4, 5 }
V.EpisodeStepDwell     = { 7.0, 12.0 }
V.EpisodeHold          = { 35.0, 80.0 }
V.EpisodeCooldown      = 170.0
V.EpisodeEruptBoost    = 1.5     -- eruption rate multiplier inside an episode

-- Lava fog.
V.LavaFogRate          = 2.6     -- particles/second of a pool at full weight, before the ladder
V.LavaGlowRate         = 0.8
V.LavaGlowPulse        = { 0.45, 1.0 }   -- glow rate swings between these fractions
V.LavaGlowPulseSeconds = 9.0
-- Pool pops (CRPoolFX through CRGroundFX "lava"): at most PoolFxNear pools within
-- PoolFxRange of the player fire one event each every PoolFxGap seconds (shorter
-- at a higher rung); CRGroundFX caps the live emitters (4 systems, fixed slots).
-- The ladder's lavaFog value (0.60 calm .. 1.60 paroxysm) is the rung scale.
V.PoolFxRange          = 170.0
V.PoolFxNear           = 3
V.PoolFxGap            = { 1.6, 4.0 }
V.PoolFxRadius         = 32.0
V.PoolFxMask           = { smoke = 0.35 }   -- embers, drops and the bubble glow at full; light smoke
V.LavaSampleWindow     = 3       -- cells either side of the player for the lava factor (7x7)
V.LavaResponse         = 0.45    -- factor change per second (smoothing)
V.LavaFogEndScale      = 0.72    -- fog end multiplier standing in the middle of lava
V.LavaFogStartScale    = 0.62
V.LavaFogTint          = 0.55    -- how far fog colour moves toward LavaFogColor
V.LavaFogColor         = { r = 0.46, g = 0.12, b = 0.05 }
V.LavaGlowAmbient      = { r = 0.13, g = 0.034, b = 0.004 }   -- ambient lift at factor 1
V.LavaGlowDiffuse      = { r = 0.07, g = 0.018, b = 0.0 }

-- Fog by altitude (terrain sampling, as Venus). Gentler than Venus: Io's haze is
-- carried by the lava, not by the lowlands.
V.ScanColumns          = 64
V.ScanRows             = 56
V.ScanBudget           = 160     -- terrain queries per frame while scanning
V.ScanInset            = 60.0    -- stay this far inside the playable box
V.PoolFogEndScale      = 0.80
V.PoolFogStartScale    = 0.74
V.PoolFogTint          = 0.20
V.PoolFogColor         = { r = 0.52, g = 0.36, b = 0.12 }
V.PoolBand             = nil     -- metres over the pool level where it is gone; nil = from terrain
V.PoolResponse         = 0.55

-- Atmosphere beyond the presets: the haze darkens and reddens with the ladder.
V.GloomDim             = 0.16
V.GloomRed             = 0.08

-- Wind. Io's air is a trace; the wind is dressing: it leans plumes and drifts fog
-- and ash. It never pushes anything.
V.BearingWander        = 0.7
V.BearingRate          = 0.035

-- Ash fall (CR/Io/AshFall from the base weather payload).
V.AshMaxRate           = 150.0
V.AshMaxQuota          = 2000
V.AshOffset            = 44.0    -- camera-attached height
V.AshTint              = { r = 0.30, g = 0.23, b = 0.19 }
V.QuakeAshBoost        = 1.6     -- extra ash rate (x ash max) at full quake intensity

-- Vents.
V.VentMergeRadius      = 45.0
V.PlumeMajorRate       = 7.0
V.PlumeMinorRate       = 3.2
V.EruptionPeriod       = { 100.0, 200.0 }  -- seconds between one vent's eruptions at rate scale 1
V.EruptionMajorPeriodScale = 0.75          -- relic geysers erupt a little more often
V.EruptionFirstDelay   = 12.0    -- the first staggered eruption no sooner than this
V.EruptionSeconds      = { 10.0, 22.0 }
V.EruptionPower        = { 0.75, 1.0 }
V.EruptionMajorPower   = { 1.0, 1.35 }
V.EruptionMinSpacing   = 3.0     -- never two eruptions starting closer than this
V.EruptionRetry        = { 1.0, 3.0 }      -- wait before a blocked vent tries again
V.EruptionBurstRate    = 150.0
V.EruptionGlowRate     = 90.0
V.EruptionFlareRate    = 40.0
V.EruptionSpatterRate  = 70.0
V.EruptionRumbleSound  = "gquak00.wav"
V.EruptionBurstSound   = "r_exp3.wav"
V.EruptionSoundRange   = 1400.0
V.EruptionVolume       = 85
V.EruptLightRange      = 900.0
V.EruptLightColor      = { r = 0.10, g = 0.034, b = 0.004 }

-- Quakes. All of these are tunables; none is hard-coded in the logic.
V.QuakeGap             = { 90.0, 240.0 }   -- seconds between random quakes
V.QuakeStrength        = { 0.2, 1.0 }      -- random quake strength range
V.QuakeDuration        = { 2.0, 10.0 }     -- random quake duration range, seconds
V.QuakeStrengthBias    = { 1.6, 0.8 }      -- u^bias: calm favours small quakes, paroxysm big ones
V.QuakeMinSpacing      = 20.0              -- never a random quake this soon after one ends
V.QuakeScriptedDefault = { 0.8, 6.0 }      -- Quake() with no arguments
V.QuakeScriptedRange   = { 0.0, 1.0 }      -- Quake() clamps strength here
V.QuakeDurationLimit   = { 0.5, 30.0 }     -- ... and duration here (also applied to events received)
V.QuakeMagnitudeScale  = 3.0               -- native magnitude = strength x this (stock misn18 uses 2.0-6.0)
V.QuakeMinNative       = 0.05              -- native magnitude is never driven below this
V.QuakeRise            = 0.18              -- fraction of the duration spent rising
V.QuakeFall            = 0.40              -- ... and falling away
V.QuakeUpdateInterval  = 0.05              -- seconds between UpdateEarthQuake calls
V.QuakeDustRate        = 380.0             -- dust particles/second at full strength
V.QuakeDustLinger      = 3.0               -- seconds the dust system outlives the shake
V.QuakeEruptStrength   = 0.55              -- a quake at least this strong makes vents erupt
V.QuakeEruptCount      = 3                 -- eruptions at full strength (scaled by strength)
V.QuakeEruptSpread     = 0.9               -- seconds between the vents it sets off

-- Co-op. The host re-announces its state this often even when nothing changed;
-- a guest trusts the host's rung for 1.5 heartbeats and then falls back to the
-- seeded timeline it has been computing all along.
V.NetHeartbeat         = 30.0
V.HostOverrideSeconds  = 45.0

-- =============================================================================
-- The ladder
--
-- One row per rung. Continuous values interpolate between adjacent rows by the
-- smoothed ladder position, so nothing steps when a preset swaps.
--   ash           ash-fall intensity
--   eruptScale    multiplier on how fast every vent's eruption timer runs
--   maxEruptions  vents allowed to erupt at once
--   lavaFog       multiplier on the lava fog emission
--   gloom         darkening / reddening of the light (Environment modifier)
-- =============================================================================

V.Levels = {
    { name = "Calm",     preset = "IoCalm",     windSpeed = 2.0, ash = 0.10, eruptScale = 0.60,
      maxEruptions = 2, lavaFog = 0.60, gloom = 0.00, visibility = 250.0, duration = { 90.0, 180.0 } },
    { name = "Restless", preset = "IoRestless", windSpeed = 3.0, ash = 0.25, eruptScale = 0.90,
      maxEruptions = 3, lavaFog = 0.80, gloom = 0.15, visibility = 240.0, duration = { 70.0, 150.0 } },
    { name = "Active",   preset = "IoActive",   windSpeed = 5.0, ash = 0.50, eruptScale = 1.25,
      maxEruptions = 4, lavaFog = 1.00, gloom = 0.40, visibility = 215.0, duration = { 60.0, 130.0 } },
    { name = "Intense",  preset = "IoIntense",  windSpeed = 8.0, ash = 0.78, eruptScale = 1.80,
      maxEruptions = 6, lavaFog = 1.30, gloom = 0.70, visibility = 185.0, duration = { 50.0, 110.0 } },
    { name = "Paroxysm", preset = "IoParoxysm", windSpeed = 12.0, ash = 1.00, eruptScale = 2.60,
      maxEruptions = 8, lavaFog = 1.60, gloom = 1.00, visibility = 150.0, duration = { 35.0, 80.0 } },
}

local LEVEL_COUNT = #V.Levels

-- =============================================================================
-- Presets
--
-- Io is nearly airless: its sky is black, and the light is Environment's orbit
-- (a small, far sun by day, Jupiter at night), so the presets carry no ambient
-- or diffuse of their own. What they do carry is the volcanic haze: barely
-- there when calm, thickening with each rung, the fog dark and the sun dimmer,
-- from a faint sulphur tint toward ash-brown until a paroxysm is a dim gloom
-- (the module's gloom modifier darkens and reddens the light on top). Fog ends
-- are authored for misn10's VisibilityRange=250; CRWeather clamps them to
-- whatever horizon a map really has. No preset carries lightning or a sky.
--
-- They are registered into CRWeatherPresets.Presets at Init rather than
-- appended to CRWeatherPresets.lua, so this module is self-contained and the
-- shared file stays untouched.
-- =============================================================================

local PRESET_ROWS = {
    { name = "IoCalm", haze = { rate = 10.0, quota = 260, a = 0.16, c = { 0.70, 0.60, 0.42 } },
      grit = nil,
      fog = { 0.22, 0.17, 0.10, 140.0, 250.0 }, sun = 0.85, wind = { 0.50, -0.04, -0.86 }, speed = 2.0,
      tin = 22.0, tout = 28.0 },
    { name = "IoRestless", haze = { rate = 18.0, quota = 380, a = 0.22, c = { 0.68, 0.56, 0.38 } },
      grit = { rate = 8.0, quota = 180, a = 0.40, c = { 0.50, 0.36, 0.20 } },
      fog = { 0.22, 0.16, 0.09, 120.0, 240.0 }, sun = 0.75, wind = { 0.50, -0.05, -0.86 }, speed = 3.0,
      tin = 22.0, tout = 28.0 },
    { name = "IoActive", haze = { rate = 32.0, quota = 600, a = 0.32, c = { 0.62, 0.48, 0.32 } },
      grit = { rate = 14.0, quota = 240, a = 0.48, c = { 0.46, 0.30, 0.16 } },
      fog = { 0.21, 0.14, 0.08, 95.0, 215.0 }, sun = 0.62, wind = { 0.52, -0.07, -0.85 }, speed = 5.0,
      tin = 20.0, tout = 26.0 },
    { name = "IoIntense", haze = { rate = 48.0, quota = 780, a = 0.44, c = { 0.56, 0.40, 0.26 } },
      grit = { rate = 22.0, quota = 300, a = 0.56, c = { 0.42, 0.24, 0.12 } },
      fog = { 0.19, 0.12, 0.07, 70.0, 185.0 }, sun = 0.48, wind = { 0.54, -0.10, -0.83 }, speed = 8.0,
      tin = 18.0, tout = 26.0 },
    { name = "IoParoxysm", haze = { rate = 64.0, quota = 900, a = 0.54, c = { 0.50, 0.34, 0.22 } },
      grit = { rate = 30.0, quota = 360, a = 0.62, c = { 0.38, 0.18, 0.09 } },
      fog = { 0.17, 0.10, 0.06, 45.0, 150.0 }, sun = 0.36, wind = { 0.56, -0.14, -0.81 }, speed = 12.0,
      tin = 16.0, tout = 26.0 },
}

local function BuildPreset(row)
    local precipitation = {
        {
            system   = "cr_wx_io_haze",
            template = "CR/Io/Haze",
            offset   = { x = 0.0, y = 26.0, z = 0.0 },
            quota    = row.haze.quota,
            emitters = {
                [0] = {
                    rate     = row.haze.rate,
                    velocity = { 1.0, 3.5 },
                    ttl      = { 14.0, 22.0 },
                    angle    = 80.0,
                    color    = {
                        start  = { r = row.haze.c[1], g = row.haze.c[2], b = row.haze.c[3], a = row.haze.a },
                        finish = { r = row.haze.c[1] * 0.65, g = row.haze.c[2] * 0.62, b = row.haze.c[3] * 0.6, a = 0.0 },
                    },
                },
            },
        },
    }
    if row.grit ~= nil then
        precipitation[#precipitation + 1] = {
            system   = "cr_wx_io_grit",
            template = "CR/Io/Grit",
            offset   = { x = 0.0, y = 3.0, z = 0.0 },
            quota    = row.grit.quota,
            emitters = {
                [0] = {
                    rate     = row.grit.rate,
                    velocity = { 2.0, 4.0 },
                    ttl      = { 3.5, 6.0 },
                    angle    = 40.0,
                    color    = {
                        start  = { r = row.grit.c[1], g = row.grit.c[2], b = row.grit.c[3], a = row.grit.a },
                        finish = { r = row.grit.c[1] * 0.65, g = row.grit.c[2] * 0.62, b = row.grit.c[3] * 0.6, a = 0.10 },
                    },
                },
            },
        }
    end
    return {
        name          = row.name,
        precipitation = precipitation,
        sky           = nil,
        fog           = { r = row.fog[1], g = row.fog[2], b = row.fog[3], fogStart = row.fog[4], fogEnd = row.fog[5] },
        ambient       = nil,
        diffuse       = nil,
        sunPowerScale = row.sun,
        wind          = { x = row.wind[1], y = row.wind[2], z = row.wind[3] },
        windSpeed     = row.speed,
        lightning     = nil,
        transitionIn  = row.tin,
        transitionOut = row.tout,
    }
end

-- Exposed so a test (or a settings page) can inspect what was registered.
function V.RegisterPresets()
    local presets = CRWeatherPresets.Presets
    if type(presets) ~= "table" then return 0 end
    local added = 0
    for i = 1, #PRESET_ROWS do
        local row = PRESET_ROWS[i]
        if presets[row.name] == nil then
            presets[row.name] = BuildPreset(row)
            added = added + 1
        end
    end
    return added
end

function V.GetPresetNames()
    local names = {}
    for i = 1, #PRESET_ROWS do names[i] = PRESET_ROWS[i].name end
    return names
end

-- =============================================================================
-- Runtime state
-- =============================================================================

V.Initialized      = false
V.Seed             = nil
V.Synced           = true        -- false on a guest until the host's state arrives
V.IsAuthority      = true        -- host / offline; guests only follow
V.NetSend          = nil         -- function(op, ...) the mission adapter provides

V.Clock            = 0.0
V.LastRealTime     = nil
V.Ladder           = nil
V.Level            = 1
V.Episode          = false
V.TargetLevel      = 2
V.LevelValue       = 1.0
V.ForcedLevel      = nil
V.ForcedUntil      = nil
V.HostOverride     = nil         -- guest: { level, episode, expires }

V.Bearing          = 0.0
V.BearingTarget    = 0.0
V.NextBearingAt    = 0.0
V.WindSpeed        = 0.0

V.Basins           = nil
V.Scan             = nil
V.PoolFactor       = 0.0
V.PoolFactorTarget = 0.0
V.NextPoolSampleAt = 0.0

V.LavaCells        = {}          -- row * cols + col -> weight
V.LavaGeom         = nil
V.LavaPools        = {}
V.LavaFactor       = 0.0
V.LavaFactorTarget = 0.0
V.NextLavaSampleAt = 0.0

V.EruptionSerial   = 0
V.Eruptions        = {}
V.VentTimers       = {}          -- site index -> seconds until its next eruption (host)
V.LastEruptionAt   = -100.0
V.SeenEruptions    = {}
V.QuakeEruptQueue  = {}          -- host: { at, site } set off by a strong quake

V.QuakeSerial      = 0
V.Quake_           = nil         -- the quake in progress, if any
V.SeenQuakes       = {}
V.NextQuakeAt      = 0.0
V.LastQuakeEndAt   = -1000.0
V.NativeQuakeOn    = false
V.NextNativeAt     = 0.0
V.QuakeMagnitude   = 0.0         -- last magnitude handed to the engine
V.QuakeLog         = {}          -- every quake that began on this peer (bounded)

V.Stats = {
    eruptions = 0, quakes = 0, scriptedQuakes = 0, randomQuakes = 0,
    mergedQuakes = 0, quakeEruptions = 0, peakQuake = 0.0,
}

V.Systems          = {}          -- name -> kind
V.SystemCount      = 0
V.TemplateFailures = {}
V.TemplatesReady   = false
V.EnvModifierRegistered = false
V.Serial           = 0
V.NextStreamAt     = 0.0
V.NextNetStateAt   = 0.0
V.LastStateKey     = nil

V.LavaLive         = {}          -- pool index -> record
V.VentSites        = {}
V.PlumeLive        = {}          -- site index -> record
V.Ash              = nil
V.QuakeFx          = nil

-- =============================================================================
-- Helpers
-- =============================================================================

local Clamp = Map.Clamp
local SmoothStep = Map.SmoothStep
local floor = math.floor

local function Lerp(a, b, t)
    return a + ((b - a) * t)
end

local function Log(message)
    if V.Debug then
        print("CRIoWeather: " .. tostring(message))
    end
end

local function Vec(x, y, z)
    if type(SetVector) == "function" then
        return SetVector(x, y, z)
    end
    return { x = x, y = y, z = z }
end

local function Call(name, ...)
    if exu == nil or type(exu[name]) ~= "function" then
        return nil
    end
    local ok, result = pcall(exu[name], ...)
    if not ok then
        Log("exu." .. name .. " failed: " .. tostring(result))
        return nil
    end
    return result
end

local function Level(index)
    return V.Levels[Clamp(index, 1, LEVEL_COUNT)]
end

local function LadderValue(field)
    local position = Clamp(V.LevelValue, 1.0, LEVEL_COUNT)
    local low = floor(position)
    local high = math.min(low + 1, LEVEL_COUNT)
    return Lerp(Level(low)[field], Level(high)[field], position - low)
end

-- 0 at the bottom of the ladder, 1 at the top.
function V.GetSeverity()
    if LEVEL_COUNT <= 1 then return 0.0 end
    return Clamp((V.LevelValue - 1.0) / (LEVEL_COUNT - 1), 0.0, 1.0)
end

-- The engine hands back VECTOR_3D userdata, not a table: read x/y/z inside a
-- pcall and return a plain table (nil unless x and z are numbers).
local function ReadVector(p)
    if p == nil then return nil end
    local okX, x, y, z = pcall(function() return p.x, p.y, p.z end)
    if okX and type(x) == "number" and type(z) == "number" then
        return { x = x, y = tonumber(y) or 0.0, z = z }
    end
    return nil
end

local function PositionOf(h)
    if h == nil or type(GetPosition) ~= "function" then return nil end
    local ok, p = pcall(GetPosition, h)
    if not ok then return nil end
    return ReadVector(p)
end

local function ValidHandle(h)
    if h == nil then return false end
    if type(IsValid) == "function" then
        local ok, valid = pcall(IsValid, h)
        return ok and valid and true or false
    end
    return true
end

local function TerrainHeight(x, z)
    if type(GetTerrainHeightAndNormal) ~= "function" then return nil end
    local ok, height = pcall(GetTerrainHeightAndNormal, Vec(x, 0.0, z))
    if not ok or type(height) ~= "number" then return nil end
    return height
end

local function LocalPlayerHandle()
    if type(GetPlayerHandle) ~= "function" then return nil end
    local ok, h = pcall(GetPlayerHandle)
    if ok and ValidHandle(h) then return h end
    return nil
end

local function LocalPlayerPosition()
    return PositionOf(LocalPlayerHandle())
end

local function Distance2D(ax, az, bx, bz)
    local dx, dz = ax - bx, az - bz
    return math.sqrt((dx * dx) + (dz * dz))
end

local function Send(op, ...)
    if V.NetSend ~= nil and V.IsAuthority then
        local ok, err = pcall(V.NetSend, op, ...)
        if not ok then Log("net send failed: " .. tostring(err)) end
    end
end

-- =============================================================================
-- Particle systems (budgeted)
-- =============================================================================

local function Fx_Create(kind, template, x, y, z)
    if V.SystemCount >= V.MaxSystems then
        return nil
    end
    if (V.TemplateFailures[template] or 0) >= V.MaxFailuresPerTemplate then
        return nil
    end

    V.Serial = V.Serial + 1
    local name = "cr_iw_" .. kind .. "_" .. tostring(V.Serial)
    if Call("CreateParticleSystem", name, template, Vec(x, y, z)) ~= true then
        local failures = (V.TemplateFailures[template] or 0) + 1
        V.TemplateFailures[template] = failures
        if failures >= V.MaxFailuresPerTemplate then
            print("CRIoWeather: " .. template .. " disabled after " .. tostring(failures) ..
                " failed particle creates (template unavailable)")
        end
        return nil
    end

    V.TemplateFailures[template] = 0
    V.Systems[name] = kind
    V.SystemCount = V.SystemCount + 1
    Call("SetParticleSystemKeepLocalSpace", name, false)
    Call("SetParticleSystemNonVisibleUpdateTimeout", name, 3.0)
    return name
end

local function Fx_Destroy(name)
    if name == nil or V.Systems[name] == nil then return end
    Call("DestroyParticleSystem", name)
    V.Systems[name] = nil
    V.SystemCount = V.SystemCount - 1
end

local function Fx_DestroyAll()
    local names = {}
    for name in pairs(V.Systems) do names[#names + 1] = name end
    for i = 1, #names do Fx_Destroy(names[i]) end
    V.SystemCount = 0
end

local function WindVector()
    return math.sin(V.Bearing), math.cos(V.Bearing)
end

local function SetWindOnSystem(name, strength, affector)
    local wx, wz = WindVector()
    Call("SetParticleAffectorParameter", name, affector or 2, "force_vector",
        string.format("%.3f 0 %.3f", wx * strength, wz * strength))
end

-- =============================================================================
-- Wind
-- =============================================================================

local function UpdateWind(dt)
    local rng = V.WindRng
    if V.Clock >= V.NextBearingAt then
        V.BearingTarget = V.PrevailingBearing + rng.Range(-V.BearingWander, V.BearingWander)
        V.NextBearingAt = V.Clock + rng.Range(18.0, 50.0)
    end

    local delta = V.BearingTarget - V.Bearing
    while delta > math.pi do delta = delta - (2.0 * math.pi) end
    while delta < -math.pi do delta = delta + (2.0 * math.pi) end
    local maxStep = V.BearingRate * dt
    if delta > maxStep then delta = maxStep end
    if delta < -maxStep then delta = -maxStep end
    V.Bearing = V.Bearing + delta

    local wanted = LadderValue("windSpeed")
    V.WindSpeed = Lerp(V.WindSpeed, wanted, Clamp(dt * 1.2, 0.0, 1.0))

    local wx, wz = WindVector()
    local fall = -0.04 - (0.10 * Clamp(V.WindSpeed / 12.0, 0.0, 1.0))
    local horizontal = math.sqrt(math.max(0.0, 1.0 - (fall * fall)))
    CRWeather.SetWindOverride({ x = wx * horizontal, y = fall, z = wz * horizontal }, V.WindSpeed)
end

-- =============================================================================
-- Ladder
-- =============================================================================

local function LadderConfig()
    local durations = {}
    for i = 1, LEVEL_COUNT do durations[i] = V.Levels[i].duration end
    local cfg = { levels = LEVEL_COUNT, start = 1, durations = durations }
    if V.AllowEpisodes then
        cfg.episode = {
            chance = V.EpisodeChance, minLevel = 3, minTarget = 3,
            peak = V.EpisodePeak, stepDwell = V.EpisodeStepDwell,
            hold = V.EpisodeHold, cooldown = V.EpisodeCooldown,
        }
    end
    return cfg
end

local function BuildLadder(seed)
    V.Seed = seed
    V.Ladder = Map.NewLadder(seed, LadderConfig())
    V.WindRng = Map.NewRng(Map.DeriveSeed(seed, 4))
    V.EruptionRng = Map.NewRng(Map.DeriveSeed(seed, 3))
    V.QuakeRng = Map.NewRng(Map.DeriveSeed(seed, 6))
    V.FxRng = Map.NewRng(Map.DeriveSeed(seed, 5))
    V.PrevailingBearing = V.WindRng.Range(0.0, 2.0 * math.pi)
    V.Bearing = V.PrevailingBearing
    V.BearingTarget = V.PrevailingBearing
    V.NextBearingAt = 0.0
end

local function ApplyRung(index, transitionSeconds)
    index = Clamp(index, 1, LEVEL_COUNT)
    local row = Level(index)
    if V.Level ~= index or CRWeather.GetPreset() ~= row.preset then
        CRWeather.SetPreset(row.preset, transitionSeconds)
        Log("level -> " .. row.name .. " (" .. row.preset .. ")")
    end
    V.Level = index
end

-- The rung in force right now, and whether it is part of an intense episode.
local function ResolveLevel()
    if V.Ladder == nil then
        return 1, false
    end

    local scheduled, episode = V.Ladder:Advance(V.Clock, V.TargetLevel)

    if V.ForcedLevel ~= nil then
        if V.ForcedUntil ~= nil and V.Clock >= V.ForcedUntil then
            V.ForcedLevel = nil
            V.ForcedUntil = nil
        else
            return V.ForcedLevel, false
        end
    end

    if not V.IsAuthority and V.HostOverride ~= nil then
        if V.Clock < V.HostOverride.expires then
            return V.HostOverride.level, V.HostOverride.episode
        end
        V.HostOverride = nil
    end

    return scheduled, episode
end

local function UpdateLadder(dt)
    if not V.Synced then
        return
    end

    local level, episode = ResolveLevel()
    V.Episode = episode
    if level ~= V.Level then
        ApplyRung(level, nil)
    end

    local step = V.SeverityRate * dt
    local delta = V.Level - V.LevelValue
    if delta > step then delta = step end
    if delta < -step then delta = -step end
    V.LevelValue = Clamp(V.LevelValue + delta, 1.0, LEVEL_COUNT)
end

-- =============================================================================
-- Terrain scan (fog by altitude) -- the Venus technique, gentler
-- =============================================================================

local function ResolveBounds(options)
    if options.bounds ~= nil then
        return options.bounds
    end
    local sites = options.sites
    if sites ~= nil and sites.bounds ~= nil then
        return sites.bounds
    end
    if type(GetPathPointCount) == "function" and type(GetPosition) == "function" then
        local ok, count = pcall(GetPathPointCount, "edge_path")
        if ok and type(count) == "number" and count >= 2 then
            local minX, maxX, minZ, maxZ = 1e30, -1e30, 1e30, -1e30
            for i = 0, count - 1 do
                local okPoint, p = pcall(GetPosition, "edge_path", i)
                if okPoint then p = ReadVector(p) end
                if okPoint and p ~= nil then
                    if p.x < minX then minX = p.x end
                    if p.x > maxX then maxX = p.x end
                    if p.z < minZ then minZ = p.z end
                    if p.z > maxZ then maxZ = p.z end
                end
            end
            if maxX > minX and maxZ > minZ then
                return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
            end
        end
    end
    return nil
end

local function StartTerrainScan(bounds)
    if bounds == nil or type(GetTerrainHeightAndNormal) ~= "function" then
        return
    end
    V.Bounds = bounds
    V.Scan = Map.NewHeightScan(bounds, V.ScanColumns, V.ScanRows, TerrainHeight, V.ScanInset)
    V.Basins = nil
end

local function UpdateTerrainScan()
    local scan = V.Scan
    if scan == nil then return end
    if scan:Step(V.ScanBudget) then
        V.Basins = Map.AnalyseBasins(scan, { maxAnchors = 24 })
        V.Scan = nil
        if V.Basins ~= nil then
            Log(string.format("basins: %d clusters, %d anchors, pool level %.1f, ridge %.1f",
                #V.Basins.clusters, #V.Basins.anchors, V.Basins.poolLevel, V.Basins.ridgeLevel))
        end
    end
end

local function UpdatePoolFactor(dt)
    if not V.AllowAltitudeFog or V.Basins == nil then
        V.PoolFactorTarget = 0.0
    elseif V.Clock >= V.NextPoolSampleAt then
        V.NextPoolSampleAt = V.Clock + 0.25
        local p = LocalPlayerPosition()
        if p ~= nil then
            V.PoolFactorTarget = Map.PoolFactor(V.Basins, p.x, p.y, p.z, { band = V.PoolBand })
        end
    end

    local step = V.PoolResponse * dt
    local delta = V.PoolFactorTarget - V.PoolFactor
    if delta > step then delta = step end
    if delta < -step then delta = -step end
    V.PoolFactor = Clamp(V.PoolFactor + delta, 0.0, 1.0)
end

-- =============================================================================
-- Lava: density lookup, global tint, streamed fog pools
-- =============================================================================

-- Mean lava weight in a (2k+1)^2 window of .mat cells around (x, z): 0 off the
-- lava, 1 in the middle of a molten expanse.
function V.LavaDensityAt(x, z, window)
    local g = V.LavaGeom
    if g == nil then return 0.0 end
    local col = floor((x - g.originX) / g.cell)
    local row = floor((z - g.originZ) / g.cell)
    local k = window or V.LavaSampleWindow
    local sum, n = 0.0, 0
    for dr = -k, k do
        for dc = -k, k do
            local r, c = row + dr, col + dc
            if r >= 0 and r < g.rows and c >= 0 and c < g.cols then
                sum = sum + (V.LavaCells[(r * g.cols) + c] or 0.0)
            end
            n = n + 1
        end
    end
    return sum / n
end

function V.LavaWeightAt(x, z)
    local g = V.LavaGeom
    if g == nil then return 0.0 end
    local col = floor((x - g.originX) / g.cell)
    local row = floor((z - g.originZ) / g.cell)
    if row < 0 or row >= g.rows or col < 0 or col >= g.cols then return 0.0 end
    return V.LavaCells[(row * g.cols) + col] or 0.0
end

local function UpdateLavaFactor(dt)
    if not V.AllowLavaTint or V.LavaGeom == nil then
        V.LavaFactorTarget = 0.0
    elseif V.Clock >= V.NextLavaSampleAt then
        V.NextLavaSampleAt = V.Clock + 0.25
        local p = LocalPlayerPosition()
        if p ~= nil then
            V.LavaFactorTarget = Clamp(V.LavaDensityAt(p.x, p.z), 0.0, 1.0)
        end
    end

    local step = V.LavaResponse * dt
    local delta = V.LavaFactorTarget - V.LavaFactor
    if delta > step then delta = step end
    if delta < -step then delta = -step end
    V.LavaFactor = Clamp(V.LavaFactor + delta, 0.0, 1.0)
end

-- Generic streaming pass: keep up to `maxLive` systems for the sites nearest the
-- player, create inside `inRange`, destroy beyond `outRange`. One creation per
-- pass, so a long list never costs a frame spike.
local function StreamSites(sites, live, maxLive, inRange, outRange, create, destroy, playerPos)
    if playerPos == nil then return end

    local count = 0
    local drop = {}
    for index in pairs(live) do
        local site = sites[index]
        local d = site and Distance2D(site.x, site.z, playerPos.x, playerPos.z) or nil
        if d == nil or d > outRange then
            drop[#drop + 1] = index
        else
            count = count + 1
        end
    end
    for i = 1, #drop do
        destroy(drop[i], live[drop[i]])
        live[drop[i]] = nil
    end

    if count >= maxLive then return end

    local best, bestDistance = nil, inRange
    for index = 1, #sites do
        if live[index] == nil then
            local d = Distance2D(sites[index].x, sites[index].z, playerPos.x, playerPos.z)
            if d < bestDistance then
                best, bestDistance = index, d
            end
        end
    end
    if best ~= nil then
        local record = create(best, sites[best])
        if record ~= nil then live[best] = record end
    end
end

local function GlowCount()
    local n = 0
    for _, record in pairs(V.LavaLive) do
        if record.glow ~= nil then n = n + 1 end
    end
    return n
end

local function LavaCreate(_, pool)
    local y = TerrainHeight(pool.x, pool.z) or 0.0
    local name = Fx_Create("lava", "CR/Io/LavaFog", pool.x, y + 2.0, pool.z)
    if name == nil then return nil end
    Call("SetParticleSystemParticleQuota", name, 70)
    local record = {
        name = name, x = pool.x, z = pool.z, weight = pool.weight or 1.0, wind = -1.0,
        phase = ((pool.x * 0.013) + (pool.z * 0.007)) % (2.0 * math.pi), glowRate = -1.0, rate = -1.0,
    }
    if V.AllowLavaGlow and GlowCount() < V.MaxLiveGlow then
        record.glow = Fx_Create("lavaglow", "CR/Io/LavaGlow", pool.x, y + 1.5, pool.z)
    end
    return record
end

local function LavaDestroy(_, record)
    Fx_Destroy(record.name)
    if record.glow ~= nil then
        Fx_Destroy(record.glow)
        record.glow = nil
    end
end

-- Bubble pops, rising embers and spatter on the nearest molten pools. Cosmetic
-- and local; the rung scales how often and how hard they pop.
local function UpdatePoolFx(dt)
    if V.PoolFx == nil then return end
    PoolFX.Update(V.PoolFx, dt, LocalPlayerPosition(), {
        enabled = V.AllowPoolFx and V.TemplatesReady,
        scale = LadderValue("lavaFog"),
        quality = CRWeather.Quality,
    })
end

local function UpdateLavaSystems()
    if not V.AllowLavaFog or not V.TemplatesReady then
        for index, record in pairs(V.LavaLive) do
            LavaDestroy(index, record)
            V.LavaLive[index] = nil
        end
        return
    end

    local lavaFog = LadderValue("lavaFog")
    local pulseLow, pulseHigh = V.LavaGlowPulse[1], V.LavaGlowPulse[2]
    for _, record in pairs(V.LavaLive) do
        local rate = V.LavaFogRate * lavaFog * (0.6 + (0.8 * record.weight))
        if math.abs(rate - record.rate) > 0.1 then
            record.rate = rate
            Call("SetParticleEmitterEmissionRate", record.name, 0, rate)
        end

        if record.glow ~= nil then
            local pulse = 0.5 + (0.5 * math.sin((V.Clock * 2.0 * math.pi / V.LavaGlowPulseSeconds) + record.phase))
            local glow = V.LavaGlowRate * lavaFog * Lerp(pulseLow, pulseHigh, pulse) * (0.6 + (0.8 * record.weight))
            if math.abs(glow - record.glowRate) > 0.05 then
                record.glowRate = glow
                Call("SetParticleEmitterEmissionRate", record.glow, 0, glow)
            end
        end

        -- Re-aim only when the wind has moved enough to see.
        if math.abs(V.Bearing - record.wind) > 0.06 then
            record.wind = V.Bearing
            local wx, wz = WindVector()
            Call("SetParticleEmitterDirection", record.name, 0, Vec(wx, 0.0, wz))
            SetWindOnSystem(record.name, 0.3 + (V.WindSpeed * 0.04), 2)
        end
    end
end

-- =============================================================================
-- Quake intensity (read by ash, dust, lighting)
-- =============================================================================

local function QuakeEnvelopeAt(q, age)
    local d = q.duration
    local rise = math.max(0.15, d * V.QuakeRise)
    local fall = math.max(0.4, d * V.QuakeFall)
    if rise + fall > d then
        local k = d / (rise + fall)
        rise, fall = rise * k, fall * k
    end
    if age <= 0.0 then return 0.0 end
    if age < rise then return SmoothStep(age / rise) end
    if age < (d - fall) then return 1.0 end
    if age < d then return 1.0 - SmoothStep((age - (d - fall)) / fall) end
    return 0.0
end

-- 0 with no quake; otherwise strength x envelope (0..1).
function V.GetQuakeIntensity()
    local q = V.Quake_
    if q == nil then return 0.0 end
    return q.strength * QuakeEnvelopeAt(q, V.Clock - q.start)
end

-- =============================================================================
-- Ash fall (visual only)
-- =============================================================================

local function EnsureAsh()
    if V.Ash ~= nil then return V.Ash end
    local name = Fx_Create("ash", "CR/Io/AshFall", 0.0, 0.0, 0.0)
    if name == nil then return nil end
    Call("SetParticleSystemParticleQuota", name, V.AshMaxQuota)
    Call("AttachParticleSystemToCamera", name, Vec(0.0, V.AshOffset, 0.0))
    -- Camera-attached: a timeout would freeze an idle volume culled forever.
    Call("SetParticleSystemNonVisibleUpdateTimeout", name, 0)
    local t = V.AshTint
    Call("SetParticleEmitterColor", name, 0,
        { r = t.r, g = t.g, b = t.b, a = 0.80 }, { r = t.r * 0.7, g = t.g * 0.7, b = t.b * 0.7, a = 0.45 })
    V.Ash = { name = name, rate = -1.0, lean = -1.0 }
    return V.Ash
end

local function DestroyAsh()
    if V.Ash == nil then return end
    Fx_Destroy(V.Ash.name)
    V.Ash = nil
end

function V.GetAshIntensity()
    if not V.AllowAshFall then return 0.0 end
    local boost = 1.0 + (V.QuakeAshBoost * V.GetQuakeIntensity())
    return Clamp(LadderValue("ash") * boost, 0.0, 1.0 + V.QuakeAshBoost)
end

local function UpdateAsh()
    local intensity = V.GetAshIntensity()
    if intensity < 0.02 or not V.TemplatesReady then
        if V.Ash ~= nil then
            Call("SetParticleSystemEmitting", V.Ash.name, false)
            Call("SetParticleSystemVisible", V.Ash.name, false)
            V.Ash.rate = 0.0
        end
        return
    end

    local ash = EnsureAsh()
    if ash == nil then return end

    local rate = V.AshMaxRate * intensity
    if math.abs(rate - ash.rate) > 4.0 then
        ash.rate = rate
        Call("SetParticleSystemEmitting", ash.name, true)
        Call("SetParticleSystemVisible", ash.name, true)
        Call("SetParticleEmitterEmissionRate", ash.name, 0, rate)
    end

    -- Ash leans with the wind: a gentle slant that follows the bearing.
    if math.abs(V.Bearing - ash.lean) > 0.08 then
        ash.lean = V.Bearing
        local wx, wz = WindVector()
        local lean = Clamp(V.WindSpeed / 24.0, 0.1, 0.5)
        Call("SetParticleEmitterDirection", ash.name, 0, Vec(wx * lean, -0.9, wz * lean))
    end
end

-- =============================================================================
-- Volcanic vents and eruptions
-- =============================================================================

local function PlumeBaseRate(site)
    return site.major and V.PlumeMajorRate or V.PlumeMinorRate
end

local function PlumeCreate(index, site)
    local name = Fx_Create("plume", "CR/Io/Plume", site.x, site.y + 1.0, site.z)
    if name == nil then return nil end
    local rate = PlumeBaseRate(site)
    Call("SetParticleEmitterEmissionRate", name, 0, rate)
    SetWindOnSystem(name, 0.6 + (V.WindSpeed * 0.08), 2)
    return { name = name, site = index, rate = rate, windAt = V.Bearing }
end

local function DestroyEruptFx(record)
    if record.glow ~= nil then Fx_Destroy(record.glow); record.glow = nil end
    if record.spatter ~= nil then Fx_Destroy(record.spatter); record.spatter = nil end
end

local function PlumeDestroy(_, record)
    DestroyEruptFx(record)
    Fx_Destroy(record.name)
end

local function EruptFxCount()
    local n = 0
    for _, record in pairs(V.PlumeLive) do
        if record.glow ~= nil or record.spatter ~= nil then n = n + 1 end
    end
    return n
end

local function EruptionEnvelope(e)
    local age = V.Clock - e.start
    local rise = 1.6
    local fall = math.min(8.0, e.duration * 0.4)
    if age < 0.0 then return 0.0 end
    if age < rise then return SmoothStep(age / rise) end
    if age < (e.duration - fall) then return 1.0 end
    if age < e.duration then return 1.0 - SmoothStep((age - (e.duration - fall)) / fall) end
    return 0.0
end

local function ActiveEruptionCount()
    return #V.Eruptions
end

-- An eruption begins (host, and by event guests). Purely visual and audible.
function V.BeginEruption(id, siteIndex, duration, power)
    if not V.AllowEruptions then return false end
    siteIndex = floor(tonumber(siteIndex) or 0)
    local site = V.VentSites[siteIndex]
    if site == nil then return false end
    if id ~= nil then
        id = tonumber(id)
        if id ~= nil then
            if V.SeenEruptions[id] then return false end
            V.SeenEruptions[id] = true
            V.SeenEruptions[id - 200] = nil
        end
    end

    duration = Clamp(tonumber(duration) or 16.0, 3.0, 60.0)
    power = Clamp(tonumber(power) or 1.0, 0.2, 2.0)
    V.Eruptions[#V.Eruptions + 1] = {
        id = id, site = siteIndex, start = V.Clock, duration = duration,
        power = power, bursted = false,
    }
    V.Stats.eruptions = V.Stats.eruptions + 1
    V.LastEruptionAt = V.Clock

    local p = LocalPlayerPosition()
    if p ~= nil and type(StartSound) == "function" then
        local d = Distance2D(site.x, site.z, p.x, p.z)
        if d < V.EruptionSoundRange then
            local volume = floor(Clamp(V.EruptionVolume * (1.0 - (d / V.EruptionSoundRange)) + 20, 20, V.EruptionVolume))
            if V.EruptionRumbleSound then pcall(StartSound, V.EruptionRumbleSound, nil, 1, false, volume, 80) end
        end
    end
    return true
end

local function UpdateEruptions()
    if #V.Eruptions == 0 then return end

    local keep = {}
    for i = 1, #V.Eruptions do
        local e = V.Eruptions[i]
        local envelope = EruptionEnvelope(e)
        local record = V.PlumeLive[e.site]
        local site = V.VentSites[e.site]
        local age = V.Clock - e.start

        if record ~= nil then
            Call("SetParticleEmitterEmissionRate", record.name, 1, V.EruptionBurstRate * e.power * envelope)
            Call("SetParticleEmitterEmissionRate", record.name, 0, PlumeBaseRate(site) * (1.0 + (1.5 * envelope)))

            -- The glowing core and the spatter are only worth a system while
            -- something is being thrown, and only a few vents carry them.
            if age < 5.0 and record.glow == nil and record.spatter == nil
                and EruptFxCount() < V.MaxLiveEruptFx
            then
                record.glow = Fx_Create("glow", "CR/Io/PlumeGlow", site.x, site.y + 1.5, site.z)
                record.spatter = Fx_Create("spatter", "CR/Io/Spatter", site.x, site.y + 2.0, site.z)
            end
            if record.glow ~= nil then
                Call("SetParticleEmitterEmissionRate", record.glow, 0, V.EruptionGlowRate * e.power * envelope)
                Call("SetParticleEmitterEmissionRate", record.glow, 1, V.EruptionFlareRate * e.power * envelope)
            end
            if record.spatter ~= nil then
                local thrown = (age < (e.duration * 0.6)) and (V.EruptionSpatterRate * e.power * envelope) or 0.0
                Call("SetParticleEmitterEmissionRate", record.spatter, 0, thrown)
            end

            if not e.bursted and age > 0.6 then
                e.bursted = true
                local p = LocalPlayerPosition()
                if p ~= nil and V.EruptionBurstSound and type(StartSound) == "function"
                    and Distance2D(site.x, site.z, p.x, p.z) < V.EruptionSoundRange
                then
                    pcall(StartSound, V.EruptionBurstSound, nil, 1, false, floor(V.EruptionVolume * 0.8), 70)
                end
            end
        end

        if age < e.duration then
            keep[#keep + 1] = e
        elseif record ~= nil then
            Call("SetParticleEmitterEmissionRate", record.name, 1, 0.0)
            Call("SetParticleEmitterEmissionRate", record.name, 0, PlumeBaseRate(site))
            DestroyEruptFx(record)
        end
    end
    V.Eruptions = keep
end

-- Host: a vent's timer, shared by the periodic schedule and the quake trigger.
local function EruptVent(siteIndex, powerScale)
    local site = V.VentSites[siteIndex]
    if site == nil then return false end
    local rng = V.EruptionRng
    local range = site.major and V.EruptionMajorPower or V.EruptionPower
    local duration = rng.Range(V.EruptionSeconds[1], V.EruptionSeconds[2])
    local power = rng.Range(range[1], range[2]) * (powerScale or 1.0)
    V.EruptionSerial = V.EruptionSerial + 1
    local id = V.EruptionSerial
    if V.BeginEruption(id, siteIndex, duration, power) then
        Send("IoErupt", id, siteIndex, duration, power)
        return true
    end
    return false
end

-- The host spreads each vent's first eruption evenly across one period, in a
-- seeded random order, so the vents are staggered from the first minute and not
-- all erupting on the same beat. After that each runs on its own jittered period.
local function VentPeriod(site)
    local rng = V.EruptionRng
    local period = rng.Range(V.EruptionPeriod[1], V.EruptionPeriod[2])
    if site.major then period = period * V.EruptionMajorPeriodScale end
    return period
end

local function InitVentTimers()
    V.VentTimers = {}
    local n = #V.VentSites
    if n == 0 then return end
    local rng = V.EruptionRng
    local order = {}
    for i = 1, n do order[i] = i end
    for i = n, 2, -1 do
        local j = rng.Int(1, i)
        order[i], order[j] = order[j], order[i]
    end
    for rank = 1, n do
        local site = order[rank]
        local span = (V.EruptionPeriod[1] + V.EruptionPeriod[2]) * 0.5
        V.VentTimers[site] = V.EruptionFirstDelay + (((rank - 1) + rng.Range(0.1, 0.9)) / n) * span
    end
end

local function UpdateVentSchedule(dt)
    if not (V.IsAuthority and V.Synced and V.AllowEruptions) then return end
    local n = #V.VentSites
    if n == 0 then return end

    local rate = LadderValue("eruptScale")
    if V.Episode then rate = rate * V.EpisodeEruptBoost end
    local cap = floor(LadderValue("maxEruptions") + 0.5)

    for i = 1, n do
        local t = V.VentTimers[i]
        if t == nil then
            t = VentPeriod(V.VentSites[i])
        end
        t = t - (dt * rate)
        if t <= 0.0 then
            local blocked = ActiveEruptionCount() >= cap or (V.Clock - V.LastEruptionAt) < V.EruptionMinSpacing
            if blocked then
                t = V.EruptionRng.Range(V.EruptionRetry[1], V.EruptionRetry[2])
            else
                EruptVent(i, 1.0)
                t = VentPeriod(V.VentSites[i])
            end
        end
        V.VentTimers[i] = t
    end

    -- Vents a strong quake set off.
    if #V.QuakeEruptQueue > 0 then
        local keep = {}
        for i = 1, #V.QuakeEruptQueue do
            local item = V.QuakeEruptQueue[i]
            if V.Clock >= item.at then
                if EruptVent(item.site, 1.15) then V.Stats.quakeEruptions = V.Stats.quakeEruptions + 1 end
            else
                keep[#keep + 1] = item
            end
        end
        V.QuakeEruptQueue = keep
    end
end

local function UpdateVents(dt)
    if not V.AllowVents or not V.TemplatesReady then
        for index, record in pairs(V.PlumeLive) do
            PlumeDestroy(index, record)
            V.PlumeLive[index] = nil
        end
    else
        for _, record in pairs(V.PlumeLive) do
            if math.abs(V.Bearing - record.windAt) > 0.08 then
                record.windAt = V.Bearing
                SetWindOnSystem(record.name, 0.6 + (V.WindSpeed * 0.08), 2)
            end
        end
    end
    UpdateVentSchedule(dt)
    UpdateEruptions()
end

-- =============================================================================
-- Quakes
-- =============================================================================

local function NativeStartQuake(magnitude)
    V.QuakeMagnitude = magnitude
    V.NativeQuakeOn = true
    if type(StartEarthquake) == "function" then
        pcall(StartEarthquake, magnitude)
    end
end

local function NativeUpdateQuake(magnitude)
    V.QuakeMagnitude = magnitude
    if type(UpdateEarthQuake) == "function" then
        pcall(UpdateEarthQuake, magnitude)
    end
end

-- Idempotent. `force` also stops a quake this module did not start; used only
-- when a save is loaded, because the engine replays a persisted quake then.
local function NativeStopQuake(force)
    if not V.NativeQuakeOn and not force then return end
    V.NativeQuakeOn = false
    V.QuakeMagnitude = 0.0
    if type(StopEarthquake) == "function" then
        pcall(StopEarthquake)
    end
end

local function DestroyQuakeFx()
    if V.QuakeFx ~= nil then
        Fx_Destroy(V.QuakeFx.dust)
        V.QuakeFx = nil
    end
end

-- A quake begins (host, and by event guests). Several quakes in a row merge into
-- one longer, stronger shake rather than stacking natives.
-- kind: 1 scripted, 2 random.
function V.BeginQuake(id, strength, duration, kind)
    if not V.AllowQuakes then return false end
    strength = Clamp(tonumber(strength) or 0.0, 0.0, 1.0)
    duration = Clamp(tonumber(duration) or 0.0, V.QuakeDurationLimit[1], V.QuakeDurationLimit[2])
    if strength < 0.02 then return false end
    id = tonumber(id)
    if id ~= nil then
        if V.SeenQuakes[id] then return false end
        V.SeenQuakes[id] = true
        V.SeenQuakes[id - 200] = nil
    end
    kind = tonumber(kind) or 1

    V.Stats.quakes = V.Stats.quakes + 1
    if kind == 2 then V.Stats.randomQuakes = V.Stats.randomQuakes + 1
    else V.Stats.scriptedQuakes = V.Stats.scriptedQuakes + 1 end
    if strength > V.Stats.peakQuake then V.Stats.peakQuake = strength end
    V.QuakeLog[#V.QuakeLog + 1] = { id = id, strength = strength, duration = duration, kind = kind, at = V.Clock }
    if #V.QuakeLog > 64 then table.remove(V.QuakeLog, 1) end

    local q = V.Quake_
    if q ~= nil and (V.Clock - q.start) < q.duration then
        -- Merge: the shake gets as strong as the strongest and lasts until the
        -- later of the two ends. It never shortens a quake already running.
        q.strength = math.max(q.strength, strength)
        q.duration = math.max(q.duration, (V.Clock - q.start) + duration)
        V.Stats.mergedQuakes = V.Stats.mergedQuakes + 1
    else
        V.Quake_ = { id = id, strength = strength, start = V.Clock, duration = duration, kind = kind }
    end
    return true
end

-- Host: a strong quake opens the vents.
local function QueueQuakeEruptions(strength, duration)
    if not (V.IsAuthority and V.AllowEruptions) or strength < V.QuakeEruptStrength then return end
    local n = #V.VentSites
    if n == 0 then return end
    local count = math.max(1, floor((V.QuakeEruptCount * strength) + 0.5))
    local rng = V.QuakeRng
    local items = {}
    for i = 1, n do items[i] = { weight = V.VentSites[i].major and 3.0 or 1.0, index = i } end
    local at = V.Clock + 0.4
    for _ = 1, count do
        local pick = Map.PickWeighted(rng, items)
        if pick == nil then break end
        V.QuakeEruptQueue[#V.QuakeEruptQueue + 1] = { at = at, site = pick.index }
        pick.weight = 0.0   -- a vent goes off once per quake
        at = at + V.QuakeEruptSpread
        if at > V.Clock + duration then break end
    end
end

-- The scripted entry point: ONE shake, now. Host / offline only (a guest's call
-- is ignored; the host's IoQuake event shakes everyone). Returns true if a quake
-- began.
--   strength  0..1 (clamped); default QuakeScriptedDefault[1]
--   duration  seconds (clamped); default QuakeScriptedDefault[2]
function V.Quake(strength, duration)
    if not V.Initialized then V.Init() end
    if not V.IsAuthority or not V.AllowQuakes then return false end
    strength = Clamp(tonumber(strength) or V.QuakeScriptedDefault[1], V.QuakeScriptedRange[1], V.QuakeScriptedRange[2])
    duration = Clamp(tonumber(duration) or V.QuakeScriptedDefault[2], V.QuakeDurationLimit[1], V.QuakeDurationLimit[2])
    V.QuakeSerial = V.QuakeSerial + 1
    local id = V.QuakeSerial
    if not V.BeginQuake(id, strength, duration, 1) then return false end
    Send("IoQuake", id, strength, duration, 1)
    QueueQuakeEruptions(strength, duration)
    return true
end

local function ScheduleNextQuake()
    local gap = V.QuakeRng.Range(V.QuakeGap[1], V.QuakeGap[2])
    V.NextQuakeAt = V.Clock + gap
end

local function RandomQuakeStrength()
    local rng = V.QuakeRng
    local bias = Lerp(V.QuakeStrengthBias[1], V.QuakeStrengthBias[2], V.GetSeverity())
    local u = rng.Next() ^ bias
    return V.QuakeStrength[1] + ((V.QuakeStrength[2] - V.QuakeStrength[1]) * u)
end

local function UpdateRandomQuakes()
    if not (V.IsAuthority and V.Synced and V.AllowQuakes and V.AllowRandomQuakes) then return end
    if V.Clock < V.NextQuakeAt then return end

    -- Not while a shake is running or just ended; try again shortly.
    if V.Quake_ ~= nil or (V.Clock - V.LastQuakeEndAt) < V.QuakeMinSpacing then
        V.NextQuakeAt = V.Clock + 5.0
        return
    end

    local rng = V.QuakeRng
    local strength = RandomQuakeStrength()
    local duration = rng.Range(V.QuakeDuration[1], V.QuakeDuration[2])
    ScheduleNextQuake()
    V.QuakeSerial = V.QuakeSerial + 1
    local id = V.QuakeSerial
    if V.BeginQuake(id, strength, duration, 2) then
        Send("IoQuake", id, strength, duration, 2)
        QueueQuakeEruptions(strength, duration)
    end
end

local function UpdateQuake()
    local q = V.Quake_
    if q == nil then
        if V.QuakeFx ~= nil and V.Clock >= V.QuakeFx.until_ then DestroyQuakeFx() end
        return
    end

    local age = V.Clock - q.start
    if age >= q.duration then
        NativeStopQuake(false)
        V.Quake_ = nil
        V.LastQuakeEndAt = V.Clock
        if V.QuakeFx ~= nil then
            Call("SetParticleEmitterEmissionRate", V.QuakeFx.dust, 0, 0.0)
            V.QuakeFx.until_ = V.Clock + V.QuakeDustLinger
        end
        return
    end

    local intensity = q.strength * QuakeEnvelopeAt(q, age)
    local magnitude = math.max(V.QuakeMinNative, intensity * V.QuakeMagnitudeScale)
    if not V.NativeQuakeOn then
        NativeStartQuake(magnitude)
        V.NextNativeAt = V.Clock + V.QuakeUpdateInterval
    elseif V.Clock >= V.NextNativeAt then
        V.NextNativeAt = V.Clock + V.QuakeUpdateInterval
        NativeUpdateQuake(magnitude)
    end

    -- Dust shaken loose rides the same envelope.
    if V.AllowQuakeDust and V.TemplatesReady then
        if V.QuakeFx == nil then
            local name = Fx_Create("dust", "CR/Io/QuakeDust", 0.0, 0.0, 0.0)
            if name ~= nil then
                Call("AttachParticleSystemToCamera", name, Vec(0.0, 22.0, 0.0))
                Call("SetParticleSystemNonVisibleUpdateTimeout", name, 0)
                V.QuakeFx = { name = name, dust = name, rate = -1.0, until_ = math.huge }
            end
        end
        if V.QuakeFx ~= nil then
            V.QuakeFx.until_ = math.huge
            local rate = V.QuakeDustRate * intensity
            if math.abs(rate - V.QuakeFx.rate) > 5.0 then
                V.QuakeFx.rate = rate
                Call("SetParticleEmitterEmissionRate", V.QuakeFx.dust, 0, rate)
            end
        end
    end
end

function V.IsQuaking() return V.Quake_ ~= nil end
function V.GetQuake()
    local q = V.Quake_
    if q == nil then return nil end
    return { strength = q.strength, duration = q.duration, elapsed = V.Clock - q.start, kind = q.kind }
end
function V.GetQuakeMagnitude() return V.QuakeMagnitude end

-- Ends any shake at once (a cutscene, a mission end). Local to this peer.
function V.StopQuake()
    NativeStopQuake(false)
    if V.Quake_ ~= nil then
        V.Quake_ = nil
        V.LastQuakeEndAt = V.Clock
    end
    DestroyQuakeFx()
end

-- =============================================================================
-- Environment contribution
-- =============================================================================

local function EruptionLight()
    if not V.AllowEruptLight or #V.Eruptions == 0 then return 0.0 end
    local p = LocalPlayerPosition()
    if p == nil then return 0.0 end
    local total = 0.0
    for i = 1, #V.Eruptions do
        local e = V.Eruptions[i]
        local site = V.VentSites[e.site]
        if site ~= nil then
            local d = Distance2D(site.x, site.z, p.x, p.z)
            local near = 1.0 - Clamp(d / V.EruptLightRange, 0.0, 1.0)
            total = total + (EruptionEnvelope(e) * e.power * near * near)
        end
    end
    return Clamp(total, 0.0, 1.0)
end

local function EnvironmentModifier(frame)
    if not V.Enabled then return end

    -- Darker and redder as the activity builds.
    local gloom = LadderValue("gloom")
    if gloom > 0.001 then
        local dim = 1.0 - (V.GloomDim * gloom)
        local red = 1.0 + (V.GloomRed * gloom)
        local blue = 1.0 - (V.GloomRed * gloom)
        for _, key in ipairs({ "ambient", "diffuse" }) do
            local c = frame[key]
            if c ~= nil then
                c.r = c.r * dim * red
                c.g = c.g * dim
                c.b = c.b * dim * blue
            end
        end
    end

    local fog = frame.fog

    -- Thicker fog in enclosed lowland, as on Venus but gentler.
    local f = V.PoolFactor
    if V.AllowAltitudeFog and f > 0.001 and fog ~= nil then
        fog.fogEnd = fog.fogEnd * Lerp(1.0, V.PoolFogEndScale, f)
        fog.fogStart = math.min(fog.fogEnd - 1.0, fog.fogStart * Lerp(1.0, V.PoolFogStartScale, f))
        local tint = V.PoolFogTint * f
        fog.r = Lerp(fog.r, V.PoolFogColor.r, tint)
        fog.g = Lerp(fog.g, V.PoolFogColor.g, tint)
        fog.b = Lerp(fog.b, V.PoolFogColor.b, tint)
    end

    -- Standing over the molten lava: the fog closes in and goes red, and the
    -- lava lights the air.
    local lava = V.LavaFactor
    if V.AllowLavaTint and lava > 0.001 then
        if fog ~= nil then
            fog.fogEnd = fog.fogEnd * Lerp(1.0, V.LavaFogEndScale, lava)
            fog.fogStart = math.min(fog.fogEnd - 1.0, fog.fogStart * Lerp(1.0, V.LavaFogStartScale, lava))
            local tint = V.LavaFogTint * lava
            fog.r = Lerp(fog.r, V.LavaFogColor.r, tint)
            fog.g = Lerp(fog.g, V.LavaFogColor.g, tint)
            fog.b = Lerp(fog.b, V.LavaFogColor.b, tint)
        end
        local a, d = V.LavaGlowAmbient, V.LavaGlowDiffuse
        if frame.ambient then
            frame.ambient.r = frame.ambient.r + (a.r * lava)
            frame.ambient.g = frame.ambient.g + (a.g * lava)
            frame.ambient.b = frame.ambient.b + (a.b * lava)
        end
        if frame.diffuse then
            frame.diffuse.r = frame.diffuse.r + (d.r * lava)
            frame.diffuse.g = frame.diffuse.g + (d.g * lava)
            frame.diffuse.b = frame.diffuse.b + (d.b * lava)
        end
    end

    -- An eruption throws red light on the air around it.
    local glow = EruptionLight()
    if glow > 0.001 and frame.ambient then
        local c = V.EruptLightColor
        frame.ambient.r = frame.ambient.r + (c.r * glow)
        frame.ambient.g = frame.ambient.g + (c.g * glow)
        frame.ambient.b = frame.ambient.b + (c.b * glow)
    end
end

V.EnvironmentModifier = EnvironmentModifier

local function UpdateRenderIntents()
    if not V.AllowRenderIntents or type(exu.SetRenderEffectFloat) ~= "function" then return end
    if V.Clock < (V.NextIntentAt or 0.0) then return end
    V.NextIntentAt = V.Clock + 2.0
    -- Depth haze strength follows severity and the lava underfoot. Status
    -- "not-implemented" in OpenShim today, so a no-op until the renderer lands.
    pcall(exu.SetRenderEffectFloat, "depth_haze", "strength",
        0.30 + (0.40 * V.GetSeverity()) + (0.20 * V.LavaFactor))
end

-- =============================================================================
-- Networking
--
-- Primitive arguments only; the mission adapter owns transport and ordering.
-- =============================================================================

-- Everything a peer needs to rebuild the same weather: seven numbers.
function V.GetNetState()
    local forcedFor = 0.0
    if V.ForcedLevel ~= nil and V.ForcedUntil ~= nil then
        forcedFor = math.max(0.0, V.ForcedUntil - V.Clock)
    end
    return V.Seed or 0, V.Clock, V.Level, V.Episode and 1 or 0, V.TargetLevel,
        V.ForcedLevel or 0, forcedFor
end

function V.ApplyNetState(seed, clock, level, episode, target, forcedLevel, forcedFor)
    seed = tonumber(seed)
    if seed == nil or seed <= 0 then return false end

    if V.Seed ~= seed or V.Ladder == nil then
        BuildLadder(seed)
        V.Clock = tonumber(clock) or V.Clock
        V.Synced = true
    end

    clock = tonumber(clock) or V.Clock
    if math.abs(clock - V.Clock) > 2.0 then V.Clock = clock end

    V.TargetLevel = Clamp(tonumber(target) or V.TargetLevel, 1, LEVEL_COUNT)
    forcedLevel = tonumber(forcedLevel) or 0
    forcedFor = tonumber(forcedFor) or 0
    if forcedLevel > 0 and forcedFor > 0 then
        V.ForcedLevel = Clamp(forcedLevel, 1, LEVEL_COUNT)
        V.ForcedUntil = V.Clock + forcedFor
    elseif not V.IsAuthority then
        V.ForcedLevel = nil
        V.ForcedUntil = nil
    end

    if not V.IsAuthority then
        V.HostOverride = {
            level = Clamp(tonumber(level) or 1, 1, LEVEL_COUNT),
            episode = tonumber(episode) == 1,
            expires = V.Clock + V.HostOverrideSeconds,
        }
    end
    return true
end

-- Dispatch for the mission adapter's receive path. Returns true when handled.
function V.ApplyNetEvent(op, ...)
    if op == "IoState" then
        return V.ApplyNetState(...)
    elseif op == "IoErupt" then
        if V.IsAuthority then return true end
        return V.BeginEruption(...)
    elseif op == "IoQuake" then
        if V.IsAuthority then return true end
        return V.BeginQuake(...)
    end
    return false
end

local function StateKey()
    return (V.Level * 1) + (V.Episode and 10 or 0) + (V.TargetLevel * 100) + ((V.ForcedLevel or 0) * 1000)
end

local function BroadcastState(force)
    if not V.IsAuthority or V.NetSend == nil then return end
    -- Announce on a change of rung / episode / target / forced level, and as a
    -- heartbeat. Comparing one number keeps the idle frame allocation-free.
    local key = StateKey()
    if force or key ~= V.LastStateKey or V.Clock >= V.NextNetStateAt then
        V.LastStateKey = key
        V.NextNetStateAt = V.Clock + V.NetHeartbeat
        Send("IoState", V.GetNetState())
    end
end

-- The host re-announces on demand: call this when a guest reports it is ready,
-- so a guest that initialised after the first announcement is not left on calm
-- weather until the next heartbeat.
function V.AnnounceState()
    BroadcastState(true)
end

function V.SetNetwork(options)
    options = options or {}
    if options.send ~= nil then V.NetSend = options.send end
    if options.authority ~= nil then V.IsAuthority = options.authority and true or false end
end

-- =============================================================================
-- Lifecycle
-- =============================================================================

-- options:
--   seed            number; the host's. Guests in a network game omit it and wait
--                   for the host's IoState.
--   authority       true on the host / offline, false on a guest
--   send            function(op, ...) -- delivers an IoState / IoErupt / IoQuake
--                   event to every guest (host only)
--   sites           the generated CRIoSites table (bounds, lava, vents)
--   bounds          { minX, maxX, minZ, maxZ } override for the playable box
--   startLevel, targetLevel
--   enabled, debug, quality, baseSky     passthrough
--   lavaFog, lavaGlow, lavaTint, altitudeFog, ashFall, vents, eruptions,
--   eruptLight, quakes, randomQuakes, quakeDust, episodes
--                   sub-system switches
function V.Init(options)
    if V.Initialized then return end
    options = options or {}

    if options.enabled ~= nil then V.Enabled = options.enabled and true or false end
    if options.debug ~= nil then V.Debug = options.debug and true or false end
    local switches = {
        lavaFog = "AllowLavaFog", lavaGlow = "AllowLavaGlow", lavaTint = "AllowLavaTint",
        altitudeFog = "AllowAltitudeFog", ashFall = "AllowAshFall", vents = "AllowVents",
        poolFx = "AllowPoolFx", eruptions = "AllowEruptions", eruptLight = "AllowEruptLight", quakes = "AllowQuakes",
        randomQuakes = "AllowRandomQuakes", quakeDust = "AllowQuakeDust", episodes = "AllowEpisodes",
    }
    for key, field in pairs(switches) do
        if options[key] ~= nil then V[field] = options[key] and true or false end
    end

    V.SetNetwork({ send = options.send, authority = options.authority })

    V.RegisterPresets()
    CRWeather.Init({
        enabled = V.Enabled,
        quality = options.quality,
        debug   = options.debug,
        baseSky = options.baseSky,
    })

    -- Vehicle wakes: render-only debris under low, moving craft near the viewer
    -- (shared CRWake module). options.vehicleWakes = false switches them off.
    pcall(Wake.Init, {
        surface = "sulfur", enabled = options.vehicleWakes ~= false, quality = options.quality,
        debug = options.debug,
    })

    -- Our particle templates are an opt-in payload, so a build that has not
    -- shipped it degrades to presets + quakes rather than failing weather.
    V.TemplatesReady = false
    local okTemplates, templates = pcall(require, "CRParticleTemplates")
    if okTemplates and type(templates) == "table" and type(templates.EnsureExtra) == "function" then
        local ready, reason = templates.EnsureExtra("cr_io")
        V.TemplatesReady = ready and true or false
        if not ready then
            print("CRIoWeather: cr_io particle templates unavailable (" .. tostring(reason) ..
                "); lava fog, plumes and quake dust are off")
        end
    end

    V.Clock = 0.0
    V.LastRealTime = nil
    V.TargetLevel = Clamp(tonumber(options.targetLevel) or 2, 1, LEVEL_COUNT)
    V.ForcedLevel = nil
    V.ForcedUntil = nil
    V.HostOverride = nil
    V.Eruptions, V.SeenEruptions, V.SeenQuakes = {}, {}, {}
    V.QuakeEruptQueue, V.QuakeLog = {}, {}
    V.Quake_, V.QuakeFx = nil, nil
    V.NativeQuakeOn, V.QuakeMagnitude = false, 0.0
    V.LastEruptionAt, V.LastQuakeEndAt = -100.0, -1000.0
    V.Stats = { eruptions = 0, quakes = 0, scriptedQuakes = 0, randomQuakes = 0,
                mergedQuakes = 0, quakeEruptions = 0, peakQuake = 0.0 }
    V.LavaLive, V.PlumeLive = {}, {}
    V.Ash = nil
    V.PoolFactor, V.PoolFactorTarget = 0.0, 0.0
    V.LavaFactor, V.LavaFactorTarget = 0.0, 0.0
    V.EruptionSerial, V.QuakeSerial = 0, 0
    V.LastStateKey = nil
    V.NextStreamAt, V.NextNetStateAt = 0.0, 0.0

    -- A guest in a network game has no seed until the host's state arrives; it
    -- shows calm weather until then rather than inventing a timeline that
    -- would diverge. Offline and host always have one.
    local seed = tonumber(options.seed)
    if seed == nil and V.IsAuthority then
        seed = math.random(1, 2000000000)
    end
    if seed ~= nil then
        BuildLadder(seed)
        V.Synced = true
    else
        V.Seed = nil
        V.Ladder = nil
        V.Synced = false
        V.WindRng = Map.NewRng(1)
        V.EruptionRng = Map.NewRng(3)
        V.QuakeRng = Map.NewRng(6)
        V.FxRng = Map.NewRng(5)
        V.PrevailingBearing = 0.0
        V.Bearing, V.BearingTarget = 0.0, 0.0
    end

    V.Level = Clamp(tonumber(options.startLevel) or 1, 1, LEVEL_COUNT)
    V.LevelValue = V.Level
    V.WindSpeed = Level(V.Level).windSpeed

    -- Map data.
    local sites = options.sites
    V.LavaPools, V.VentSites, V.LavaCells, V.LavaGeom = {}, {}, {}, nil
    V.PoolFx = nil
    if sites ~= nil then
        if sites.lava ~= nil then
            V.LavaCells = Map.ExpandRuns(sites.lava)
            V.LavaGeom = {
                cols = sites.lava.cols, rows = sites.lava.rows, cell = sites.lava.cell,
                originX = sites.lava.originX, originZ = sites.lava.originZ,
            }
            V.LavaPools = sites.lava.pools or {}
        end
        -- The rng is looked up per call: BuildLadder replaces V.FxRng when a guest's seed arrives.
        local poolRng = { Range = function(lo, hi)
            if V.FxRng == nil then return (lo + hi) * 0.5 end
            return V.FxRng.Range(lo, hi)
        end }
        V.PoolFx = PoolFX.New({
            kind = "lava", sites = V.LavaPools, rng = poolRng, weightAt = V.LavaWeightAt,
            heightAt = TerrainHeight, range = V.PoolFxRange, maxNear = V.PoolFxNear,
            gap = V.PoolFxGap, radius = V.PoolFxRadius, mask = V.PoolFxMask,
        })
        if sites.vents ~= nil then
            V.VentSites = Map.MergeVents(sites.vents, V.VentMergeRadius)
        end
    end
    StartTerrainScan(ResolveBounds(options))

    local environment = rawget(_G, "Environment")
    if environment ~= nil and type(environment.RegisterEnvironmentModifier) == "function" then
        environment.RegisterEnvironmentModifier("CRIoWeather", EnvironmentModifier)
        V.EnvModifierRegistered = true
    end

    InitVentTimers()
    V.QuakeEruptQueue = {}
    ScheduleNextQuake()

    ApplyRung(V.Level, 0.05)
    CRWeather.SetWindOverride({ x = 0.0, y = -0.05, z = 1.0 }, V.WindSpeed)

    V.Initialized = true
    Log("initialised; seed=" .. tostring(V.Seed) .. " authority=" .. tostring(V.IsAuthority))
    BroadcastState(true)
end

-- Same real-clock treatment as CRMarsWeather / CRVenusWeather: misn04-style
-- adapters pass a fixed 1/TPS dt that is really a frame count, so take elapsed
-- time from GetTime.
local function RealDelta(fallbackDt)
    if type(GetTime) ~= "function" then return fallbackDt end
    local now = GetTime()
    if type(now) ~= "number" then return fallbackDt end
    local last = V.LastRealTime
    V.LastRealTime = now
    if last == nil then return 0.0 end
    local delta = now - last
    if delta <= 0.0 or delta > 1.0 then return 0.0 end
    return delta
end

function V.Update(dt)
    if not V.Initialized then V.Init() end
    if not V.Enabled then return end

    dt = tonumber(dt) or 0.0
    if dt > 0.0 then dt = RealDelta(dt) end
    if dt <= 0.0 then
        CRWeather.Update(0.0)
        return
    end

    V.Clock = V.Clock + dt

    UpdateLadder(dt)
    UpdateWind(dt)
    UpdateTerrainScan()
    UpdatePoolFactor(dt)
    UpdateLavaFactor(dt)
    UpdateRandomQuakes()
    UpdateQuake()
    UpdateAsh()
    UpdateVents(dt)
    UpdateLavaSystems()
    UpdatePoolFx(dt)

    if V.Clock >= V.NextStreamAt then
        V.NextStreamAt = V.Clock + V.StreamInterval
        local playerPos = LocalPlayerPosition()
        if V.TemplatesReady then
            if V.AllowLavaFog and #V.LavaPools > 0 then
                StreamSites(V.LavaPools, V.LavaLive, V.MaxLiveLava, V.LavaStreamIn, V.LavaStreamOut,
                    LavaCreate, LavaDestroy, playerPos)
            end
            if V.AllowVents then
                StreamSites(V.VentSites, V.PlumeLive, V.MaxLivePlumes, V.PlumeStreamIn, V.PlumeStreamOut,
                    PlumeCreate, PlumeDestroy, playerPos)
            end
        end
        UpdateRenderIntents()
    end

    BroadcastState(false)
    Wake.Update(dt)
    CRWeather.Update(dt)
end

function V.Shutdown()
    if not V.Initialized then return end

    -- A shake must not outlive the mission.
    NativeStopQuake(false)
    V.Quake_, V.QuakeFx = nil, nil

    Fx_DestroyAll()
    PoolFX.Stop(V.PoolFx)
    V.LavaLive, V.PlumeLive = {}, {}
    V.Ash = nil

    local environment = rawget(_G, "Environment")
    if V.EnvModifierRegistered and environment ~= nil
        and type(environment.UnregisterEnvironmentModifier) == "function"
    then
        environment.UnregisterEnvironmentModifier("CRIoWeather")
    end
    V.EnvModifierRegistered = false

    if V.AllowRenderIntents and type(exu.SetRenderEffectFloat) == "function" then
        pcall(exu.SetRenderEffectFloat, "depth_haze", "strength", 0.0)
    end

    CRWeather.ClearWindOverride()
    Wake.Stop()
    CRWeather.Shutdown()
    V.Initialized = false
end

-- =============================================================================
-- Mission API
-- =============================================================================

-- The rung the weather trends toward. Host / offline only; a guest ignores it
-- because the host's state event carries the target.
function V.SetTargetLevel(index)
    if not V.IsAuthority then return V.TargetLevel end
    V.TargetLevel = Clamp(tonumber(index) or 1, 1, LEVEL_COUNT)
    BroadcastState(true)
    return V.TargetLevel
end

function V.GetTargetLevel()
    return V.TargetLevel
end

-- Pins the ladder to a rung for a fixed time -- for a set piece on cue.
function V.ForceLevel(index, seconds, transitionSeconds)
    if not V.Initialized then V.Init() end
    if not V.IsAuthority then return false end
    index = Clamp(tonumber(index) or 1, 1, LEVEL_COUNT)
    V.ForcedLevel = index
    V.ForcedUntil = V.Clock + math.max(1.0, tonumber(seconds) or 60.0)
    ApplyRung(index, transitionSeconds)
    BroadcastState(true)
    return true
end

function V.ReleaseForcedLevel()
    V.ForcedLevel = nil
    V.ForcedUntil = nil
    BroadcastState(true)
end

-- Forces one eruption now, from the host. For set pieces and for tests.
-- power: optional multiplier on the seeded power.
function V.TriggerEruption(siteIndex, power)
    if not V.IsAuthority or not V.Initialized then return false end
    return EruptVent(floor(tonumber(siteIndex) or 0), tonumber(power))
end

function V.GetLevel() return V.Level end
function V.GetLevelName() return Level(V.Level).name end
function V.IsEpisode() return V.Episode end
function V.GetVisibility() return LadderValue("visibility") end
function V.GetWindSpeed() return V.WindSpeed end
function V.GetPoolFactor() return V.PoolFactor end
function V.GetLavaFactor() return V.LavaFactor end
function V.GetBasins() return V.Basins end
function V.GetLavaPools() return V.LavaPools end
function V.GetVentSites() return V.VentSites end
function V.GetActiveEruptions() return V.Eruptions end
function V.GetStats() return V.Stats end
function V.GetSystemCount() return V.SystemCount end

-- Present for adapters that forward every object creation to every module.
function V.OnObjectCreated(h)
    CRWeather.OnObjectCreated(h)
end

function V.Describe()
    return string.format("%s (%.2f)%s wind %.1f lava %.2f pool %.2f systems %d eruptions %d quakes %d",
        Level(V.Level).name, V.LevelValue, V.Episode and " EPISODE" or "",
        V.WindSpeed, V.LavaFactor, V.PoolFactor, V.SystemCount, V.Stats.eruptions, V.Stats.quakes)
end

-- =============================================================================
-- Save / load
--
-- Particle systems and the engine's quake do not survive a save; only the
-- director's scalars persist.
-- =============================================================================

function V.Save()
    return {
        seed        = V.Seed,
        clock       = V.Clock,
        level       = V.Level,
        levelValue  = V.LevelValue,
        targetLevel = V.TargetLevel,
        bearing     = V.Bearing,
        prevailing  = V.PrevailingBearing,
        windSpeed   = V.WindSpeed,
        forcedLevel = V.ForcedLevel,
        forcedFor   = V.ForcedUntil and (V.ForcedUntil - V.Clock) or nil,
        ladder      = V.Ladder and V.Ladder:Save() or nil,
        eruptionSerial = V.EruptionSerial,
        quakeSerial = V.QuakeSerial,
    }
end

function V.Load(state)
    if type(state) ~= "table" then return end
    if not V.Initialized then V.Init() end

    if state.seed ~= nil and (V.Seed ~= state.seed or V.Ladder == nil) then
        BuildLadder(state.seed)
        V.Synced = true
    end
    V.Clock = tonumber(state.clock) or 0.0
    V.TargetLevel = Clamp(tonumber(state.targetLevel) or 2, 1, LEVEL_COUNT)
    if V.Ladder ~= nil and state.ladder ~= nil then V.Ladder:Load(state.ladder) end
    V.Bearing = tonumber(state.bearing) or V.Bearing
    V.PrevailingBearing = tonumber(state.prevailing) or V.PrevailingBearing
    V.BearingTarget = V.PrevailingBearing
    V.NextBearingAt = V.Clock
    V.WindSpeed = tonumber(state.windSpeed) or V.WindSpeed
    V.EruptionSerial = tonumber(state.eruptionSerial) or 0
    V.QuakeSerial = tonumber(state.quakeSerial) or 0

    if state.forcedLevel ~= nil and (tonumber(state.forcedFor) or 0.0) > 0.0 then
        V.ForcedLevel = Clamp(tonumber(state.forcedLevel), 1, LEVEL_COUNT)
        V.ForcedUntil = V.Clock + tonumber(state.forcedFor)
    else
        V.ForcedLevel, V.ForcedUntil = nil, nil
    end

    -- Loading rebuilds the Ogre scene: every system we held is already gone, and
    -- the engine may replay a quake that was running at save time. Stop it.
    Fx_DestroyAll()
    PoolFX.Stop(V.PoolFx)
    V.LavaLive, V.PlumeLive = {}, {}
    V.Ash, V.QuakeFx, V.Quake_ = nil, nil, nil
    NativeStopQuake(true)
    V.Eruptions, V.QuakeEruptQueue = {}, {}
    InitVentTimers()
    ScheduleNextQuake()
    if type(CRWeather.ResetSystems) == "function" then CRWeather.ResetSystems() end

    V.Level = Clamp(tonumber(state.level) or 1, 1, LEVEL_COUNT)
    V.LevelValue = Clamp(tonumber(state.levelValue) or V.Level, 1.0, LEVEL_COUNT)
    CRWeather.SetPreset(Level(V.Level).preset, 0.05)
    CRWeather.Blend = 1.0
    V.LastStateKey = nil
end

return CRIoWeather
