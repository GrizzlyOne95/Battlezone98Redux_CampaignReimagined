-- CRMarsWeather.lua
-- Mars weather director for Campaign Reimagined.
--
-- CRWeather.lua is a renderer: hand it a preset and it draws that weather. It
-- has no opinion about when weather should happen, and its wind is one frozen
-- vector per preset. This module is the half that was missing -- the thing that
-- decides what the sky is doing minute to minute and keeps the air moving while
-- it does.
--
-- Five parts:
--
--   severity   a continuous 1..5 ladder (calm -> breezy -> rising -> storm ->
--              severe). Integer crossings swap the CRWeather preset; the
--              fractional value drives everything else, so wind, sensors and
--              visibility slide smoothly through a transition instead of
--              stepping when the preset changes.
--   wind       a live bearing and speed: a prevailing direction that wanders,
--              a base speed from the ladder, and discrete gusts with a real
--              rise/hold/fall envelope. Pushed into CRWeather so the dust
--              actually blows the way the wind is blowing.
--   devils     dust devils, placed in the world near the player and drifting
--              downwind. Convective, so they only occur in the calmer half of
--              the ladder -- inside a real storm there is no boundary layer to
--              form one and you could not see it anyway.
--   fronts     haboob walls: a dust front crossing the map on the wind, visible
--              for a minute before it arrives and then passing over the player.
--              Only while the ladder is climbing, because a front is the
--              leading edge of a storm and one followed by calm is a lie.
--   coupling   what the weather does to the mission: sensor degradation through
--              Environment's gameplay-modifier hook, and a lateral gravity
--              component so a gale is something you feel through the controls.
--
-- Ownership rules this module obeys:
--   * Fog, ambient and sun belong to Environment.lua. We never write them; we
--     set a CRWeather preset and CRWeather contributes through Environment's
--     modifier hook.
--   * Radar range/period and velocity jamming belong to Environment.lua's
--     ProcessObjectNightEffects. We never write them either; we register a
--     gameplay modifier and return scales.
--   * Gravity has no owner, so we take it -- but only while Environment's own
--     legacy dust-storm path is not running, and we restore it on shutdown.

local exu = require("exu")
local CRWeather = require("CRWeather")

local CRMarsWeather = {}

-- =============================================================================
-- Configuration
-- =============================================================================

CRMarsWeather.Enabled              = true

-- Log one line per state change. Off by default so a normal run is quiet.
CRMarsWeather.Debug                = false

-- Sub-systems, each independently switchable so a mission (or a settings page)
-- can take the visuals without the gameplay coupling.
CRMarsWeather.AllowDustDevils      = true
CRMarsWeather.AllowSensorDegrade   = true
CRMarsWeather.AllowWindPush        = true

-- Lateral acceleration per unit of wind speed, in world units/second^2. Small
-- on purpose: this is meant to read as buffeting, not as being shoved. It also
-- deflects unguided ordnance downwind, which is the point -- a mortar arc in a
-- gale should not land where it does in still air.
CRMarsWeather.WindPushScale        = 0.010
CRMarsWeather.MaxWindPush          = 1.20

-- Sensor degradation is expressed as the scales handed to Environment. These
-- are the values at the top of the ladder; everything below interpolates.
CRMarsWeather.MinRadarRangeScale   = 0.42
CRMarsWeather.MaxRadarPeriodScale  = 1.85
CRMarsWeather.MaxVelocJamScale     = 1.40

-- How fast the ladder position itself moves. The preset crossfade is handled by
-- CRWeather; this is the smoothing for wind, sensors and visibility so they do
-- not step at the moment the preset swaps.
CRMarsWeather.SeverityRate         = 0.055   -- ladder steps per second

-- Dust devils.
CRMarsWeather.MaxDevils            = 2
CRMarsWeather.DevilMinRange        = 140.0
CRMarsWeather.DevilMaxRange        = 430.0
CRMarsWeather.DevilCullRange       = 780.0
CRMarsWeather.DevilLife            = { 26.0, 58.0 }
CRMarsWeather.DevilSpinUp          = 6.0
CRMarsWeather.DevilSpinDown        = 9.0
CRMarsWeather.DevilDriftFraction   = 0.30    -- of wind speed

-- Haboob fronts. One at a time, always: two fronts on the same wind is not a
-- thing, and two overlapping thousand-unit walls is not a thing to ask the
-- renderer for either.
CRMarsWeather.AllowHaboob          = true
CRMarsWeather.HaboobMinLevel       = 2.4     -- ladder position before one can form
CRMarsWeather.HaboobSpawnRange     = { 900.0, 1300.0 }
CRMarsWeather.HaboobApproachRange  = 900.0   -- distance over which it builds to full
CRMarsWeather.HaboobArrivalRange   = 120.0   -- distance at which it counts as landed
CRMarsWeather.HaboobCullRange      = 650.0   -- downwind distance before it is retired
CRMarsWeather.HaboobSpeedFactor    = 0.85    -- of wind speed
CRMarsWeather.HaboobGap            = { 240.0, 520.0 }
CRMarsWeather.HaboobChance         = 0.55
-- How wide the emitter face is held, from first sighting to arrival. A wall
-- pinned at one width reads as a finite object receding in perspective; a
-- widening one keeps spanning the horizon the way an approaching front does.
CRMarsWeather.HaboobFaceWidth      = { 620.0, 1150.0 }
CRMarsWeather.HaboobTurbulence     = { 3.0, 12.0 }

-- Optional gust one-shot. Left nil because guessing a stock filename fails
-- silently: a wrong name plays nothing and looks exactly like working code.
-- Docs/CR_MARS_WEATHER.md lists the wanted asset.
CRMarsWeather.GustSound            = nil
CRMarsWeather.GustSoundMinSpeed    = 26.0
CRMarsWeather.GustSoundVolume      = 70

-- =============================================================================
-- The ladder
--
-- One row per rung. Everything the director needs to know about "how bad is it
-- right now" lives here, and every continuous value is interpolated between
-- adjacent rows using the fractional ladder position.
-- =============================================================================

CRMarsWeather.Levels = {
    {
        name        = "Calm",
        preset      = "MarsHaze",
        windSpeed   = 6.0,
        gustPeak    = { 4.0, 10.0 },
        gustGap     = { 9.0, 22.0 },
        duration    = { 70.0, 160.0 },
        devilChance = 0.55,
        maxDevils   = 2,
        visibility  = 520.0,
        radarRange  = 1.00,
        radarPeriod = 1.00,
        velocJam    = 1.00,
    },
    {
        name        = "Breezy",
        preset      = "MarsHaze",
        windSpeed   = 15.0,
        gustPeak    = { 8.0, 18.0 },
        gustGap     = { 7.0, 16.0 },
        duration    = { 60.0, 140.0 },
        devilChance = 0.75,
        maxDevils   = 2,
        visibility  = 490.0,
        radarRange  = 0.96,
        radarPeriod = 1.03,
        velocJam    = 1.03,
    },
    {
        name        = "Rising",
        preset      = "MarsDustRising",
        windSpeed   = 25.0,
        gustPeak    = { 12.0, 26.0 },
        gustGap     = { 6.0, 13.0 },
        duration    = { 55.0, 120.0 },
        devilChance = 0.40,
        maxDevils   = 1,
        visibility  = 380.0,
        radarRange  = 0.82,
        radarPeriod = 1.18,
        velocJam    = 1.10,
    },
    {
        name        = "Storm",
        preset      = "MarsDustStorm",
        windSpeed   = 38.0,
        gustPeak    = { 16.0, 34.0 },
        gustGap     = { 5.0, 11.0 },
        duration    = { 50.0, 105.0 },
        devilChance = 0.0,
        maxDevils   = 0,
        visibility  = 320.0,
        radarRange  = 0.62,
        radarPeriod = 1.45,
        velocJam    = 1.22,
    },
    {
        name        = "Severe",
        preset      = "MarsDustStormSevere",
        windSpeed   = 58.0,
        gustPeak    = { 22.0, 46.0 },
        gustGap     = { 4.0, 9.0 },
        duration    = { 35.0, 75.0 },
        devilChance = 0.0,
        maxDevils   = 0,
        visibility  = 130.0,
        radarRange  = 0.42,
        radarPeriod = 1.85,
        velocJam    = 1.40,
    },
}

-- =============================================================================
-- Profiles
--
-- The ladder above describes weather on open Martian ground. A different place
-- is not a different amount of that weather, it is a different kind, so a
-- profile swaps the whole ladder rather than scaling it -- along with the few
-- director behaviours that are genuinely a property of the terrain.
--
-- Plains stays the default and is byte-for-byte the ladder misn04 has always
-- run, so selecting a profile is opt-in and nothing changes for a mission that
-- does not ask.
-- =============================================================================

CRMarsWeather.Profiles = {
    Plains = {
        name          = "Plains",
        levels        = CRMarsWeather.Levels,
        allowHaboob   = true,
        bearingWander = 0.9,
        bearingRate   = 0.055,
        slopeWind     = nil,
    },

    -- A dormant volcano flank. Three terrain facts drive every difference:
    --
    --   Ridges shelter the ground layer, so the fast flat sheet dust is
    --   replaced by slower, more turbulent slope dust and visibility contracts
    --   less hard at every rung -- on a flank you look across open air, and
    --   fogging that in flattens the terrain the mission is built around.
    --
    --   The wind is a slope wind, not a prevailing one. It runs upslope as the
    --   ground heats and drains back down as it cools, so the bearing swings on
    --   a long cycle instead of wandering randomly, and it wanders far less
    --   around wherever that cycle currently points.
    --
    --   Tharsis flanks are dust-devil country. More of them, closer in, and
    --   they persist further up the ladder than they do on the plain.
    --
    -- No haboob. A wall front is a flat-terrain phenomenon that needs a long
    -- unobstructed fetch to organise; a ridge system breaks one up before it
    -- ever becomes a wall.
    Volcano = {
        name          = "Volcano",
        allowHaboob   = false,
        bearingWander = 0.35,
        bearingRate   = 0.030,
        slopeWind     = { period = 260.0, swing = 0.62 },
        devilRange    = { 120.0, 360.0 },
        maxDevils     = 3,
        levels = {
            {
                name        = "Flank Calm",
                preset      = "MarsVolcanoClear",
                windSpeed   = 7.0,
                gustPeak    = { 5.0, 11.0 },
                gustGap     = { 10.0, 24.0 },
                duration    = { 80.0, 170.0 },
                devilChance = 0.70,
                maxDevils   = 2,
                visibility  = 620.0,
                radarRange  = 1.00,
                radarPeriod = 1.00,
                velocJam    = 1.00,
            },
            {
                name        = "Slope Breeze",
                preset      = "MarsVolcanoBreeze",
                windSpeed   = 16.0,
                gustPeak    = { 9.0, 19.0 },
                gustGap     = { 8.0, 18.0 },
                duration    = { 70.0, 150.0 },
                devilChance = 0.85,
                maxDevils   = 3,
                visibility  = 560.0,
                radarRange  = 0.97,
                radarPeriod = 1.02,
                velocJam    = 1.02,
            },
            {
                name        = "Upslope Dust",
                preset      = "MarsVolcanoRising",
                windSpeed   = 27.0,
                gustPeak    = { 13.0, 27.0 },
                gustGap     = { 7.0, 14.0 },
                duration    = { 60.0, 130.0 },
                devilChance = 0.45,
                maxDevils   = 1,
                visibility  = 450.0,
                radarRange  = 0.85,
                radarPeriod = 1.15,
                velocJam    = 1.08,
            },
            {
                name        = "Flank Storm",
                preset      = "MarsVolcanoStorm",
                windSpeed   = 40.0,
                gustPeak    = { 17.0, 35.0 },
                gustGap     = { 6.0, 12.0 },
                duration    = { 50.0, 110.0 },
                devilChance = 0.0,
                maxDevils   = 0,
                visibility  = 340.0,
                radarRange  = 0.66,
                radarPeriod = 1.40,
                velocJam    = 1.20,
            },
            {
                -- Deliberately the shortest rung in either profile. The mission
                -- is fought on ridges above mined gullies, and weather that
                -- makes the ridgeline unreadable for long stops being drama and
                -- starts being an unfair death.
                name        = "Summit Blackout",
                preset      = "MarsVolcanoSevere",
                windSpeed   = 56.0,
                gustPeak    = { 22.0, 44.0 },
                gustGap     = { 5.0, 10.0 },
                duration    = { 30.0, 60.0 },
                devilChance = 0.0,
                maxDevils   = 0,
                visibility  = 210.0,
                radarRange  = 0.48,
                radarPeriod = 1.75,
                velocJam    = 1.34,
            },
        },
    },
}

CRMarsWeather.Profile = "Plains"

-- Not a constant any more: a profile swaps the ladder, so this follows it.
local LEVEL_COUNT = #CRMarsWeather.Levels

-- =============================================================================
-- Runtime state
-- =============================================================================

CRMarsWeather.Initialized      = false
CRMarsWeather.Automatic        = true
CRMarsWeather.Level            = 1      -- integer rung currently selected
CRMarsWeather.TargetLevel      = 2      -- the rung the director trends toward
CRMarsWeather.LevelValue       = 1.0    -- smoothed fractional position
CRMarsWeather.LastRealTime     = nil    -- previous GetTime() sample; see RealDelta
CRMarsWeather.NextLevelAt      = 0.0
CRMarsWeather.ForcedUntil      = nil
CRMarsWeather.ForcedLevel      = nil
CRMarsWeather.Clock            = 0.0

CRMarsWeather.PrevailingBearing = 0.0   -- radians, direction the wind blows TO
CRMarsWeather.Bearing           = 0.0
CRMarsWeather.BearingTarget     = 0.0
CRMarsWeather.BearingWander     = 0.9   -- radians of excursion either side
CRMarsWeather.BearingRate       = 0.055 -- radians/second cap
CRMarsWeather.SlopeWind         = nil   -- { period, swing }; see the Volcano profile
CRMarsWeather.NextBearingAt     = 0.0

CRMarsWeather.WindSpeed         = 0.0
CRMarsWeather.BaseWindSpeed     = 0.0
CRMarsWeather.Gust              = nil   -- { start, rise, hold, fall, peak, veer }
CRMarsWeather.NextGustAt        = 0.0
CRMarsWeather.GustValue         = 0.0

CRMarsWeather.Devils            = {}    -- systemName -> devil record
CRMarsWeather.DevilSerial       = 0
CRMarsWeather.NextDevilAt       = 0.0

-- A create that fails is not a create to retry next tick. When the particle
-- system cannot be made at all -- a missing template, an engine that will not
-- build it -- every attempt costs an SEH-guarded access violation inside Ogre
-- and produces nothing. Give up after a few and say so once.
CRMarsWeather.DevilFailures     = 0
CRMarsWeather.MaxDevilFailures  = 3
CRMarsWeather.DevilsDisabled    = false

CRMarsWeather.Haboob            = nil   -- the single live front, or nil
CRMarsWeather.HaboobSerial      = 0
CRMarsWeather.NextHaboobAt      = 0.0
CRMarsWeather.HaboobFailures    = 0
CRMarsWeather.MaxHaboobFailures = 3
CRMarsWeather.HaboobDisabled    = false

CRMarsWeather.GameplayRegistered = false
CRMarsWeather.LastSyncSeverity   = -1.0
CRMarsWeather.GravityOwned       = false
CRMarsWeather.BaseGravity        = nil
CRMarsWeather.LastGustSoundAt    = -1.0

-- =============================================================================
-- Helpers
-- =============================================================================

local function Clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function Clamp01(value)
    return Clamp(value or 0.0, 0.0, 1.0)
end

local function Lerp(a, b, t)
    return a + ((b - a) * t)
end

local function SmoothStep(t)
    t = Clamp01(t)
    return t * t * (3.0 - (2.0 * t))
end

local function RandomRange(low, high)
    return low + (math.random() * (high - low))
end

local function Log(message)
    if CRMarsWeather.Debug then
        print("CRMarsWeather: " .. tostring(message))
    end
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

-- Selects a profile's ladder and the director behaviour that goes with it.
-- Returns the profile actually applied, which is Plains for an unknown name:
-- a mission that asks for weather and silently gets none is worse than one that
-- gets the default.
local function ApplyProfile(name)
    local profile = name and CRMarsWeather.Profiles[name] or nil
    if profile == nil then
        if name ~= nil then
            print("CRMarsWeather: unknown profile '" .. tostring(name) .. "'; using Plains")
        end
        profile = CRMarsWeather.Profiles.Plains
    end

    CRMarsWeather.Profile = profile.name
    CRMarsWeather.Levels = profile.levels
    LEVEL_COUNT = #profile.levels

    CRMarsWeather.AllowHaboob = profile.allowHaboob ~= false
    CRMarsWeather.BearingWander = profile.bearingWander or CRMarsWeather.BearingWander
    CRMarsWeather.BearingRate = profile.bearingRate or CRMarsWeather.BearingRate
    CRMarsWeather.SlopeWind = profile.slopeWind

    if profile.devilRange ~= nil then
        CRMarsWeather.DevilMinRange = profile.devilRange[1]
        CRMarsWeather.DevilMaxRange = profile.devilRange[2]
    end
    if profile.maxDevils ~= nil then
        CRMarsWeather.MaxDevils = profile.maxDevils
    end

    return profile
end

function CRMarsWeather.GetProfile()
    return CRMarsWeather.Profile
end

local function Level(index)
    return CRMarsWeather.Levels[Clamp(index, 1, LEVEL_COUNT)]
end

-- Reads a field off the ladder at the smoothed fractional position, so a value
-- that differs between rungs slides rather than steps. At an integer position
-- this returns that rung's authored value exactly.
local function LadderValue(field)
    local position = Clamp(CRMarsWeather.LevelValue, 1.0, LEVEL_COUNT)
    local low = math.floor(position)
    local high = math.min(low + 1, LEVEL_COUNT)
    local t = position - low
    return Lerp(Level(low)[field], Level(high)[field], t)
end

-- Same, for a ladder field authored as a { low, high } pair.
local function LadderPair(field)
    local position = Clamp(CRMarsWeather.LevelValue, 1.0, LEVEL_COUNT)
    local low = math.floor(position)
    local high = math.min(low + 1, LEVEL_COUNT)
    local t = position - low
    local a = Level(low)[field]
    local b = Level(high)[field]
    return Lerp(a[1], b[1], t), Lerp(a[2], b[2], t)
end

-- 0 at the bottom of the ladder, 1 at the top.
function CRMarsWeather.GetSeverity()
    if LEVEL_COUNT <= 1 then
        return 0.0
    end
    return Clamp01((CRMarsWeather.LevelValue - 1.0) / (LEVEL_COUNT - 1))
end

-- =============================================================================
-- Wind
-- =============================================================================

-- Direction the wind blows toward, as a unit vector. The downward component
-- grows with speed: harder wind drives dust down onto the deck rather than
-- letting it hang, which is what makes a severe storm feel like it has weight.
-- Where the wind is blowing FROM this moment, before the random wander is added.
--
-- On open ground that is simply the prevailing bearing. On a slope it is not
-- fixed at all: the flow runs uphill as the ground heats and drains back down
-- as it cools, so the bearing swings across a long cycle and the ordinary
-- bounded wander rides on top of that instead of around a constant.
local function PrevailingBearingNow()
    local slope = CRMarsWeather.SlopeWind
    if slope == nil then
        return CRMarsWeather.PrevailingBearing
    end

    local period = math.max(1.0, slope.period or 260.0)
    local phase = (CRMarsWeather.Clock / period) * 2.0 * math.pi
    return CRMarsWeather.PrevailingBearing + (math.sin(phase) * (slope.swing or 0.5))
end

local function WindDirection()
    local bearing = CRMarsWeather.Bearing
    local fall = -0.08 - (0.24 * Clamp01(CRMarsWeather.WindSpeed / 60.0))
    local horizontal = math.sqrt(math.max(0.0, 1.0 - (fall * fall)))
    return {
        x = math.sin(bearing) * horizontal,
        y = fall,
        z = math.cos(bearing) * horizontal,
    }
end

local function ScheduleNextGust()
    local gapLow, gapHigh = LadderPair("gustGap")
    CRMarsWeather.NextGustAt = CRMarsWeather.Clock + RandomRange(gapLow, gapHigh)
end

-- The gust envelope. A gust is not a sine wave: it arrives fast, holds, and
-- trails off slowly, and it veers the bearing while it passes.
local function GustMagnitude()
    local gust = CRMarsWeather.Gust
    if gust == nil then
        return 0.0, 0.0
    end

    local age = CRMarsWeather.Clock - gust.start
    if age < 0.0 then
        return 0.0, 0.0
    end

    local shape
    if age < gust.rise then
        shape = SmoothStep(age / gust.rise)
    elseif age < (gust.rise + gust.hold) then
        shape = 1.0
    elseif age < (gust.rise + gust.hold + gust.fall) then
        shape = 1.0 - SmoothStep((age - gust.rise - gust.hold) / gust.fall)
    else
        CRMarsWeather.Gust = nil
        ScheduleNextGust()
        return 0.0, 0.0
    end

    return gust.peak * shape, gust.veer * shape
end

local function StartGust()
    local peakLow, peakHigh = LadderPair("gustPeak")
    local severity = CRMarsWeather.GetSeverity()

    CRMarsWeather.Gust = {
        start = CRMarsWeather.Clock,
        peak  = RandomRange(peakLow, peakHigh),
        -- Stronger weather gusts harder and more abruptly.
        rise  = Lerp(1.3, 0.7, severity),
        hold  = Lerp(1.7, 1.0, severity),
        fall  = Lerp(3.2, 1.8, severity),
        veer  = RandomRange(-0.22, 0.22),
    }
    Log(string.format("gust peak=%.1f", CRMarsWeather.Gust.peak))
end

local function UpdateWind(dt)
    -- Bearing: a bounded random walk around the prevailing direction, rate
    -- limited so the dust never visibly snaps to a new heading.
    if CRMarsWeather.Clock >= (CRMarsWeather.NextBearingAt or 0.0) then
        local wander = CRMarsWeather.BearingWander
        CRMarsWeather.BearingTarget = PrevailingBearingNow() + RandomRange(-wander, wander)
        CRMarsWeather.NextBearingAt = CRMarsWeather.Clock + RandomRange(14.0, 40.0)
    end

    local gustMagnitude, gustVeer = GustMagnitude()

    local target = CRMarsWeather.BearingTarget + gustVeer
    local delta = target - CRMarsWeather.Bearing
    -- Take the short way round the circle.
    while delta > math.pi do delta = delta - (2.0 * math.pi) end
    while delta < -math.pi do delta = delta + (2.0 * math.pi) end

    local maxStep = CRMarsWeather.BearingRate * dt
    if delta > maxStep then delta = maxStep end
    if delta < -maxStep then delta = -maxStep end
    CRMarsWeather.Bearing = CRMarsWeather.Bearing + delta

    -- Speed: ladder base plus the live gust, smoothed so the base itself never
    -- steps when the ladder moves.
    CRMarsWeather.BaseWindSpeed = LadderValue("windSpeed")
    CRMarsWeather.GustValue = gustMagnitude

    local wanted = CRMarsWeather.BaseWindSpeed + gustMagnitude
    local blend = Clamp01(dt * 1.6)
    CRMarsWeather.WindSpeed = Lerp(CRMarsWeather.WindSpeed, wanted, blend)

    if CRMarsWeather.Gust == nil and CRMarsWeather.Clock >= CRMarsWeather.NextGustAt then
        StartGust()
    end

    -- Hand the live wind to the renderer so the dust follows it.
    CRWeather.SetWindOverride(WindDirection(), CRMarsWeather.WindSpeed)
end

-- =============================================================================
-- Ladder scheduling
-- =============================================================================

-- Weather drifts one rung at a time, biased toward the mission's target. A
-- direct jump would read as a cut; the ladder is the whole point.
local function PickNextLevel()
    local current = CRMarsWeather.Level
    local target = CRMarsWeather.TargetLevel

    local up, same, down
    if target > current then
        up, same, down = 6, 3, 1
    elseif target < current then
        up, same, down = 1, 3, 6
    else
        up, same, down = 2, 5, 2
    end

    -- At an end of the ladder the unavailable move folds into staying put,
    -- rather than being silently redistributed toward the other direction.
    if current >= LEVEL_COUNT then
        same = same + up
        up = 0
    end
    if current <= 1 then
        same = same + down
        down = 0
    end

    local roll = math.random() * (up + same + down)
    if roll < up then
        return current + 1
    elseif roll < (up + same) then
        return current
    end
    return current - 1
end

local function ApplyLevel(index, transitionSeconds)
    index = Clamp(index, 1, LEVEL_COUNT)
    local level = Level(index)
    local previous = CRMarsWeather.Level
    CRMarsWeather.Level = index

    if previous ~= index or CRWeather.GetPreset() ~= level.preset then
        CRWeather.SetPreset(level.preset, transitionSeconds)
        Log("level -> " .. level.name .. " (" .. level.preset .. ")")
    end

    CRMarsWeather.NextLevelAt = CRMarsWeather.Clock
        + RandomRange(level.duration[1], level.duration[2])
end

local function UpdateLadder(dt)
    -- A forced level holds until its timer runs out, then automatic scheduling
    -- resumes from wherever the force left it.
    if CRMarsWeather.ForcedUntil ~= nil then
        if CRMarsWeather.Clock >= CRMarsWeather.ForcedUntil then
            CRMarsWeather.ForcedUntil = nil
            CRMarsWeather.ForcedLevel = nil
            Log("forced level released")
            ApplyLevel(CRMarsWeather.Level, nil)
        end
    elseif CRMarsWeather.Automatic and CRMarsWeather.Clock >= CRMarsWeather.NextLevelAt then
        ApplyLevel(PickNextLevel(), nil)
    end

    -- Track the selected rung with a rate limit. This is what everything
    -- continuous reads, so it has to move smoothly even when the rung jumps.
    local wanted = CRMarsWeather.Level
    local step = CRMarsWeather.SeverityRate * dt
    local delta = wanted - CRMarsWeather.LevelValue
    if delta > step then delta = step end
    if delta < -step then delta = -step end
    CRMarsWeather.LevelValue = Clamp(CRMarsWeather.LevelValue + delta, 1.0, LEVEL_COUNT)
end

-- =============================================================================
-- Dust devils
-- =============================================================================

local function TerrainHeightAt(x, z)
    if type(GetTerrainHeightAndNormal) ~= "function" then
        return nil
    end
    local ok, height = pcall(GetTerrainHeightAndNormal, SetVector(x, 0.0, z))
    if not ok or type(height) ~= "number" then
        return nil
    end
    return height
end

local function DestroyDevil(systemName)
    Call("DestroyParticleSystem", systemName)
    CRMarsWeather.Devils[systemName] = nil
end

function CRMarsWeather.DestroyAllDevils()
    local names = {}
    for systemName in pairs(CRMarsWeather.Devils) do
        names[#names + 1] = systemName
    end
    for i = 1, #names do
        DestroyDevil(names[i])
    end
end

local function CountDevils()
    local count = 0
    for _ in pairs(CRMarsWeather.Devils) do
        count = count + 1
    end
    return count
end

local function SpawnDevil(player)
    local origin = GetPosition(player)
    if origin == nil then
        return false
    end

    -- Upwind of the player by preference: a devil that drifts across the view
    -- is worth far more than one that spawns behind and never comes back.
    local bearing = CRMarsWeather.Bearing + math.pi + RandomRange(-1.1, 1.1)
    local range = RandomRange(CRMarsWeather.DevilMinRange, CRMarsWeather.DevilMaxRange)
    local x = origin.x + (math.sin(bearing) * range)
    local z = origin.z + (math.cos(bearing) * range)
    local y = TerrainHeightAt(x, z)
    if y == nil then
        return false
    end

    CRMarsWeather.DevilSerial = CRMarsWeather.DevilSerial + 1
    local systemName = "cr_wx_devil_" .. tostring(CRMarsWeather.DevilSerial)

    if Call("CreateParticleSystem", systemName, "CR/Weather/DustDevil", SetVector(x, y, z)) ~= true then
        CRMarsWeather.DevilFailures = CRMarsWeather.DevilFailures + 1
        if CRMarsWeather.DevilFailures >= CRMarsWeather.MaxDevilFailures then
            CRMarsWeather.DevilsDisabled = true
            print("CRMarsWeather: dust devils disabled after " ..
                tostring(CRMarsWeather.DevilFailures) ..
                " failed particle creates (template CR/Weather/DustDevil unavailable)")
        else
            Log("could not create " .. systemName)
        end
        return false
    end

    -- Only a success clears the tally; a run of failures should still stop.
    CRMarsWeather.DevilFailures = 0

    Call("SetParticleSystemKeepLocalSpace", systemName, true)
    Call("SetParticleSystemNonVisibleUpdateTimeout", systemName, 3.0)

    CRMarsWeather.Devils[systemName] = {
        x       = x,
        z       = z,
        born    = CRMarsWeather.Clock,
        life    = RandomRange(CRMarsWeather.DevilLife[1], CRMarsWeather.DevilLife[2]),
        skirt   = 55.0,   -- authored emitter 0 rate
        column  = 40.0,   -- authored emitter 1 rate
    }

    Log("dust devil " .. systemName .. " at " .. string.format("%.0f, %.0f", x, z))
    return true
end

local function UpdateDevils(dt, player)
    if not CRMarsWeather.AllowDustDevils or CRMarsWeather.DevilsDisabled then
        if next(CRMarsWeather.Devils) ~= nil then
            CRMarsWeather.DestroyAllDevils()
        end
        return
    end

    local playerPos = player and GetPosition(player) or nil
    local direction = WindDirection()
    local drift = CRMarsWeather.WindSpeed * CRMarsWeather.DevilDriftFraction

    local expired = {}
    for systemName, devil in pairs(CRMarsWeather.Devils) do
        local age = CRMarsWeather.Clock - devil.born

        devil.x = devil.x + (direction.x * drift * dt)
        devil.z = devil.z + (direction.z * drift * dt)

        local tooFar = false
        if playerPos ~= nil then
            local dx = devil.x - playerPos.x
            local dz = devil.z - playerPos.z
            tooFar = ((dx * dx) + (dz * dz)) > (CRMarsWeather.DevilCullRange * CRMarsWeather.DevilCullRange)
        end

        if age >= devil.life or tooFar then
            expired[#expired + 1] = systemName
        else
            local y = TerrainHeightAt(devil.x, devil.z)
            if y ~= nil then
                Call("SetParticleSystemPosition", systemName, SetVector(devil.x, y, devil.z))
            end

            -- Spin up, hold, spin down. A devil that appears and vanishes at
            -- full strength reads as a bug rather than as weather.
            local envelope = 1.0
            if age < CRMarsWeather.DevilSpinUp then
                envelope = SmoothStep(age / CRMarsWeather.DevilSpinUp)
            elseif age > (devil.life - CRMarsWeather.DevilSpinDown) then
                envelope = SmoothStep((devil.life - age) / CRMarsWeather.DevilSpinDown)
            end

            Call("SetParticleEmitterEmissionRate", systemName, 0, devil.skirt * envelope)
            Call("SetParticleEmitterEmissionRate", systemName, 1, devil.column * envelope)
            Call("SetParticleEmitterDirection", systemName, 0, SetVector(0.0, 1.0, 0.0))
        end
    end

    for i = 1, #expired do
        DestroyDevil(expired[i])
    end

    -- The cap is a cap, not merely a spawn gate. The ladder steps between rungs
    -- rather than sliding up to them, and a devil lives far longer than a rung
    -- change takes, so one born in the calm half is routinely still turning when
    -- the storm rung arrives. That contradicts the reason this module spawns
    -- them at all: inside a storm there is no boundary layer to hold a devil
    -- together, and nobody could see it through the dust if there were.
    --
    -- The cap has to come from the rung the director has actually SELECTED, not
    -- from the smoothed ladder position. LevelValue lags the rung by design --
    -- that lag is what keeps wind and sensors from stepping when the preset
    -- changes -- so reading the cap from it means the director has already
    -- declared a storm while the interpolated cap still says devils are fine.
    -- Taking the minimum of both keeps the smooth taper on the way up and the
    -- hard stop the moment a storm rung is chosen.
    --
    -- Oldest first, so the survivors are the ones with the most life left.
    local rung = Level(CRMarsWeather.Level)
    local maxDevils = math.min(CRMarsWeather.MaxDevils,
        math.floor(LadderValue("maxDevils") + 0.5),
        rung.maxDevils or 0)
    local live = {}
    for systemName, devil in pairs(CRMarsWeather.Devils) do
        live[#live + 1] = { name = systemName, born = devil.born }
    end
    if #live > maxDevils then
        table.sort(live, function(a, b) return a.born < b.born end)
        for i = 1, #live - maxDevils do
            DestroyDevil(live[i].name)
        end
    end

    if player == nil or playerPos == nil then
        return
    end

    if CountDevils() >= maxDevils then
        return
    end

    if CRMarsWeather.Clock < CRMarsWeather.NextDevilAt then
        return
    end
    CRMarsWeather.NextDevilAt = CRMarsWeather.Clock + RandomRange(18.0, 45.0)

    if math.random() <= LadderValue("devilChance") then
        SpawnDevil(player)
    end
end

-- =============================================================================
-- Haboob fronts
-- =============================================================================
--
-- A dust devil is something happening nearby. A haboob is something happening to
-- you: a wall of dust tall enough to hide the sky, crossing the map on the wind,
-- in view for a minute before it arrives and then swallowing everything. It is
-- the one Mars weather event with a before and an after, which is what earns it
-- the bookkeeping an ambient layer does not need.
--
-- The front is world-placed and local_space, so the whole wall translates
-- intact, and the node is turned to face along the wind so the template's
-- `width` spans the front while its `depth` is the thickness through it.

local function DestroyHaboob()
    local front = CRMarsWeather.Haboob
    if front == nil then
        return
    end
    Call("DestroyParticleSystem", front.system)
    CRMarsWeather.Haboob = nil
end

function CRMarsWeather.DestroyHaboobFront()
    DestroyHaboob()
end

local function SpawnHaboob(player)
    local origin = player and GetPosition(player) or nil
    if origin == nil then
        return false
    end

    -- Directly upwind, on the wind axis rather than scattered around it like a
    -- devil. A front that spawns off-axis drifts past instead of over, which
    -- wastes the entire event.
    local bearing = CRMarsWeather.Bearing + math.pi
    local range = RandomRange(CRMarsWeather.HaboobSpawnRange[1], CRMarsWeather.HaboobSpawnRange[2])
    local x = origin.x + (math.sin(bearing) * range)
    local z = origin.z + (math.cos(bearing) * range)
    local y = TerrainHeightAt(x, z)
    if y == nil then
        return false
    end

    CRMarsWeather.HaboobSerial = CRMarsWeather.HaboobSerial + 1
    local systemName = "cr_wx_haboob_" .. tostring(CRMarsWeather.HaboobSerial)

    if Call("CreateParticleSystem", systemName, "CR/Weather/HaboobWall", SetVector(x, y, z)) ~= true then
        CRMarsWeather.HaboobFailures = CRMarsWeather.HaboobFailures + 1
        if CRMarsWeather.HaboobFailures >= CRMarsWeather.MaxHaboobFailures then
            CRMarsWeather.HaboobDisabled = true
            print("CRMarsWeather: haboob fronts disabled after " ..
                tostring(CRMarsWeather.HaboobFailures) ..
                " failed particle creates (template CR/Weather/HaboobWall unavailable)")
        else
            Log("could not create " .. systemName)
        end
        return false
    end
    CRMarsWeather.HaboobFailures = 0

    Call("SetParticleSystemKeepLocalSpace", systemName, true)
    Call("SetParticleSystemNonVisibleUpdateTimeout", systemName, 4.0)

    CRMarsWeather.Haboob = {
        system  = systemName,
        x       = x,
        z       = z,
        born    = CRMarsWeather.Clock,
        arrived = false,
        skirt   = 70.0,   -- authored emitter 0 rate
        crest   = 34.0,   -- authored emitter 1 rate
    }

    Log("haboob front " .. systemName .. " at " .. string.format("%.0f, %.0f", x, z))
    return true
end

local function UpdateHaboob(dt, player)
    if not CRMarsWeather.AllowHaboob or CRMarsWeather.HaboobDisabled then
        DestroyHaboob()
        return
    end

    local playerPos = player and GetPosition(player) or nil
    local direction = WindDirection()
    local front = CRMarsWeather.Haboob

    if front ~= nil then
        -- The front rides the wind, slightly slower than the air inside it.
        local speed = CRMarsWeather.WindSpeed * CRMarsWeather.HaboobSpeedFactor
        front.x = front.x + (direction.x * speed * dt)
        front.z = front.z + (direction.z * speed * dt)

        -- Distance measured ALONG the wind axis, signed: positive while the
        -- front is still upwind and closing, negative once it has passed over.
        -- Plain range would make an arriving front and a departing one look
        -- identical, and the whole point of the event is that they are not.
        local along = CRMarsWeather.HaboobApproachRange
        if playerPos ~= nil then
            along = ((playerPos.x - front.x) * direction.x)
                  + ((playerPos.z - front.z) * direction.z)
        end

        if along < -CRMarsWeather.HaboobCullRange then
            Log("haboob front " .. front.system .. " passed downwind")
            DestroyHaboob()
            return
        end

        local approach = Clamp01(1.0 - (math.max(0.0, along) / CRMarsWeather.HaboobApproachRange))
        local depart = Clamp01(1.0 + (math.min(0.0, along) / CRMarsWeather.HaboobCullRange))
        local envelope = approach * depart

        local y = TerrainHeightAt(front.x, front.z)
        if y ~= nil then
            Call("SetParticleSystemPosition", front.system, SetVector(front.x, y, front.z))
        end

        -- Re-aim only when the bearing has actually moved. The wind wanders
        -- slowly, and a node rotation every frame is work for nothing.
        if front.dirX == nil
            or ((front.dirX * direction.x) + (front.dirZ * direction.z)) < 0.9995
        then
            front.dirX = direction.x
            front.dirZ = direction.z
            Call("SetParticleSystemDirection", front.system, SetVector(direction.x, 0.0, direction.z))
        end

        Call("SetParticleEmitterEmissionRate", front.system, 0, front.skirt * envelope)
        Call("SetParticleEmitterEmissionRate", front.system, 1, front.crest * envelope)

        -- The face widens and the air inside it churns harder as the front
        -- closes. Both go through EXU's StringInterface bridge, and both are
        -- written only when they have moved enough to see: Ogre parses every
        -- one of these out of a string, so a per-frame write is a per-frame
        -- parse for a change nobody could notice.
        local width = Lerp(CRMarsWeather.HaboobFaceWidth[1], CRMarsWeather.HaboobFaceWidth[2], envelope)
        if front.width == nil or math.abs(width - front.width) > 5.0 then
            front.width = width
            Call("SetParticleEmitterParameter", front.system, 0, "width", width)
            Call("SetParticleEmitterParameter", front.system, 1, "width", width * 0.98)
        end

        local turbulence = Lerp(CRMarsWeather.HaboobTurbulence[1], CRMarsWeather.HaboobTurbulence[2], envelope)
        if front.turbulence == nil or math.abs(turbulence - front.turbulence) > 0.4 then
            front.turbulence = turbulence
            -- Affector 3 is the DirectionRandomiser; see CR/Weather/HaboobWall.
            Call("SetParticleAffectorParameter", front.system, 3, "randomness", turbulence)
        end

        if not front.arrived and along <= CRMarsWeather.HaboobArrivalRange then
            front.arrived = true
            Log("haboob front " .. front.system .. " arrived")
            -- The front is the visible cause of the storm behind it, so the
            -- ladder steps up as it lands rather than on its own timer. Only
            -- when the director is actually driving: a mission that has forced
            -- a level has already said what it wants the sky to do.
            if CRMarsWeather.Automatic and CRMarsWeather.ForcedLevel == nil then
                CRMarsWeather.SetTargetLevel(CRMarsWeather.TargetLevel + 1)
            end
        end

        return
    end

    if playerPos == nil then
        return
    end

    if CRMarsWeather.LevelValue < CRMarsWeather.HaboobMinLevel then
        -- Hold the timer off while the ladder is low, so a storm that builds an
        -- hour into a mission does not immediately produce a front from a
        -- countdown that has been running through all the calm weather.
        CRMarsWeather.NextHaboobAt = math.max(CRMarsWeather.NextHaboobAt, CRMarsWeather.Clock + 30.0)
        return
    end

    if CRMarsWeather.Clock < CRMarsWeather.NextHaboobAt then
        return
    end
    CRMarsWeather.NextHaboobAt = CRMarsWeather.Clock +
        RandomRange(CRMarsWeather.HaboobGap[1], CRMarsWeather.HaboobGap[2])

    if math.random() <= CRMarsWeather.HaboobChance then
        SpawnHaboob(player)
    end
end

-- =============================================================================
-- Gameplay coupling
-- =============================================================================

-- Environment owns radar; we only contribute scales. See the gameplay-modifier
-- comment block in Environment.lua for why this cannot be a direct write.
local function GameplayContribution(frame)
    if not CRMarsWeather.AllowSensorDegrade then
        return
    end

    -- Range and jamming only. Radar PERIOD is the sweep animation, and
    -- Environment rewrites radar state on every sync, so scaling it made the
    -- sweep restart each time the storm severity moved -- which reads as the
    -- radar pulsing every few seconds rather than as degraded sensors.
    frame.radarRange = frame.radarRange * LadderValue("radarRange")
    frame.velocJam   = frame.velocJam * LadderValue("velocJam")
end

local function UpdateSensors()
    local environment = rawget(_G, "Environment")
    if environment == nil or not CRMarsWeather.GameplayRegistered then
        return
    end

    -- Only ask for a resync when the contribution actually moved. A sync pass
    -- walks every craft in the mission.
    -- Coarse on purpose: a sync pass rewrites radar state on every craft, and
    -- severity moves about 0.014 per second, so a 0.02 threshold resynced
    -- roughly every 1.5 seconds for a change no player could perceive.
    local severity = CRMarsWeather.GetSeverity()
    if math.abs(severity - CRMarsWeather.LastSyncSeverity) > 0.10 then
        CRMarsWeather.LastSyncSeverity = severity
        if type(environment.RequestGameplaySync) == "function" then
            environment.RequestGameplaySync()
        end
    end
end

local function UpdateWindPush()
    if not CRMarsWeather.AllowWindPush or type(exu.SetGravity) ~= "function" then
        return
    end

    -- Environment's legacy dust-storm path also writes gravity. Nothing in CR
    -- calls TriggerDustStorm today, but if something does, it wins for as long
    -- as it runs rather than the two of us alternating writes every frame.
    local environment = rawget(_G, "Environment")
    if environment ~= nil and (environment.DustStormTimer or 0.0) > 0.0 then
        return
    end

    local direction = WindDirection()
    local push = Clamp(CRMarsWeather.WindSpeed * CRMarsWeather.WindPushScale,
        0.0, CRMarsWeather.MaxWindPush)

    local base = CRMarsWeather.BaseGravity or { x = 0.0, y = -9.8, z = 0.0 }
    Call("SetGravity",
        base.x + (direction.x * push),
        base.y,
        base.z + (direction.z * push))
    CRMarsWeather.GravityOwned = true
end

local function UpdateGustSound()
    if CRMarsWeather.GustSound == nil or type(StartSound) ~= "function" then
        return
    end
    if CRMarsWeather.Gust == nil then
        return
    end
    if CRMarsWeather.WindSpeed < CRMarsWeather.GustSoundMinSpeed then
        return
    end
    -- One shot per gust, at its onset.
    if CRMarsWeather.LastGustSoundAt == CRMarsWeather.Gust.start then
        return
    end
    CRMarsWeather.LastGustSoundAt = CRMarsWeather.Gust.start

    pcall(StartSound, CRMarsWeather.GustSound, nil, CRMarsWeather.GustSoundVolume, false, 100)
end

-- =============================================================================
-- Lifecycle
-- =============================================================================

-- options:
--   enabled, debug, quality       passthrough to CRWeather where relevant
--   startLevel, targetLevel       where the ladder begins and trends
--   prevailingBearing             radians; omit for a random prevailing wind
--   baseSky                       the map's own sky, so the sky layer can engage
--   dustDevils, sensorDegrade, windPush    sub-system switches
function CRMarsWeather.Init(options)
    if CRMarsWeather.Initialized then
        return
    end

    options = options or {}

    -- The profile goes first so an explicit option below still wins: a profile
    -- states what the terrain implies, and the mission gets the last word.
    ApplyProfile(options.profile)

    if options.enabled ~= nil then CRMarsWeather.Enabled = options.enabled and true or false end
    if options.debug ~= nil then CRMarsWeather.Debug = options.debug and true or false end
    if options.dustDevils ~= nil then CRMarsWeather.AllowDustDevils = options.dustDevils and true or false end
    if options.haboob ~= nil then CRMarsWeather.AllowHaboob = options.haboob and true or false end
    if options.sensorDegrade ~= nil then CRMarsWeather.AllowSensorDegrade = options.sensorDegrade and true or false end
    if options.windPush ~= nil then CRMarsWeather.AllowWindPush = options.windPush and true or false end

    CRWeather.Init({
        enabled = CRMarsWeather.Enabled,
        quality = options.quality,
        debug   = options.debug,
        baseSky = options.baseSky,
    })

    CRMarsWeather.Clock = 0.0
    CRMarsWeather.Level = Clamp(tonumber(options.startLevel) or 1, 1, LEVEL_COUNT)
    CRMarsWeather.TargetLevel = Clamp(tonumber(options.targetLevel) or 2, 1, LEVEL_COUNT)
    CRMarsWeather.LevelValue = CRMarsWeather.Level
    CRMarsWeather.Automatic = true
    CRMarsWeather.ForcedLevel = nil
    CRMarsWeather.ForcedUntil = nil
    CRMarsWeather.Devils = {}
    CRMarsWeather.DevilSerial = 0
    CRMarsWeather.DevilFailures = 0
    CRMarsWeather.DevilsDisabled = false
    CRMarsWeather.NextDevilAt = 12.0
    CRMarsWeather.Gust = nil
    CRMarsWeather.GustValue = 0.0
    CRMarsWeather.LastGustSoundAt = -1.0
    CRMarsWeather.LastSyncSeverity = -1.0

    CRMarsWeather.PrevailingBearing = tonumber(options.prevailingBearing)
        or RandomRange(0.0, 2.0 * math.pi)
    CRMarsWeather.Bearing = CRMarsWeather.PrevailingBearing
    CRMarsWeather.BearingTarget = CRMarsWeather.PrevailingBearing
    CRMarsWeather.NextBearingAt = 0.0

    CRMarsWeather.BaseWindSpeed = Level(CRMarsWeather.Level).windSpeed
    CRMarsWeather.WindSpeed = CRMarsWeather.BaseWindSpeed
    ScheduleNextGust()

    -- Capture the map's gravity before we start bending it sideways.
    if type(exu.GetGravity) == "function" then
        local gravity = Call("GetGravity")
        if type(gravity) == "table" then
            CRMarsWeather.BaseGravity = { x = gravity.x or 0.0, y = gravity.y or -9.8, z = gravity.z or 0.0 }
        end
    end
    if CRMarsWeather.BaseGravity == nil then
        CRMarsWeather.BaseGravity = { x = 0.0, y = -9.8, z = 0.0 }
    end

    local environment = rawget(_G, "Environment")
    if environment ~= nil and type(environment.RegisterGameplayModifier) == "function" then
        environment.RegisterGameplayModifier("CRMarsWeather", GameplayContribution)
        CRMarsWeather.GameplayRegistered = true
    else
        CRMarsWeather.GameplayRegistered = false
        if CRMarsWeather.AllowSensorDegrade then
            Log("Environment has no gameplay modifier hook; sensor degradation is off")
        end
    end

    -- Seed the opening weather without a fade-in: the mission starts in this
    -- weather, it does not transition into it from clear air.
    ApplyLevel(CRMarsWeather.Level, 0.05)
    CRWeather.SetWindOverride(WindDirection(), CRMarsWeather.WindSpeed)

    CRMarsWeather.Initialized = true
    Log("initialised at level " .. Level(CRMarsWeather.Level).name)
end

-- misn04 hands every module a fixed 1.0 / M.TPS as its delta, but Update runs
-- once per rendered frame rather than TPS times a second, so that number is a
-- frame count wearing seconds' clothing: at 120 fps the weather clock advanced
-- six seconds per real second. Rungs whose dwell is 35-160 s re-rolled every
-- 6-25 s, gusts fired several times a second, and the whole ladder read as
-- flapping rather than as weather. Mission logic elsewhere uses GetTime(), so
-- take the delta from the same clock and be framerate-independent.
--
-- Returns the caller's dt unchanged when GetTime is unavailable (the offline
-- test harness), and 0 across a discontinuity -- a load, a pause or a restart
-- hands back a jump or a negative, and neither is an elapsed second.
local function RealDelta(fallbackDt)
    if type(GetTime) ~= "function" then
        return fallbackDt
    end

    local now = GetTime()
    if type(now) ~= "number" then
        return fallbackDt
    end

    local last = CRMarsWeather.LastRealTime
    CRMarsWeather.LastRealTime = now
    if last == nil then
        return 0.0
    end

    local delta = now - last
    if delta <= 0.0 or delta > 1.0 then
        return 0.0
    end
    return delta
end

function CRMarsWeather.Update(dt)
    if not CRMarsWeather.Initialized then
        CRMarsWeather.Init()
    end
    if not CRMarsWeather.Enabled then
        return
    end

    -- A caller passing 0 still means "settle the scene, do not advance time",
    -- so honour that before consulting the real clock.
    dt = tonumber(dt) or 0.0
    if dt > 0.0 then
        dt = RealDelta(dt)
    end

    if dt <= 0.0 then
        -- A zero-length frame still has to drive the renderer, because missions
        -- call Update(0) once during load to settle the scene before the first
        -- real frame.
        CRWeather.Update(0.0)
        return
    end

    CRMarsWeather.Clock = CRMarsWeather.Clock + dt

    UpdateLadder(dt)
    UpdateWind(dt)
    UpdateSensors()
    UpdateWindPush()
    UpdateGustSound()

    local player = nil
    if type(GetPlayerHandle) == "function" then
        player = GetPlayerHandle()
        if player ~= nil and type(IsValid) == "function" and not IsValid(player) then
            player = nil
        end
    end
    UpdateDevils(dt, player)
    UpdateHaboob(dt, player)

    CRWeather.Update(dt)
end

function CRMarsWeather.Shutdown()
    if not CRMarsWeather.Initialized then
        return
    end

    CRMarsWeather.DestroyAllDevils()
    DestroyHaboob()

    local environment = rawget(_G, "Environment")
    if CRMarsWeather.GameplayRegistered and environment ~= nil
        and type(environment.UnregisterGameplayModifier) == "function"
    then
        environment.UnregisterGameplayModifier("CRMarsWeather")
        -- Unregistering is not enough on its own: the scales we contributed are
        -- still on every craft until a sync pass rewrites them.
        if type(environment.RequestGameplaySync) == "function" then
            environment.RequestGameplaySync()
        end
        if type(environment.SyncGameplayImpacts) == "function" then
            pcall(environment.SyncGameplayImpacts)
        end
    end
    CRMarsWeather.GameplayRegistered = false

    if CRMarsWeather.GravityOwned and CRMarsWeather.BaseGravity ~= nil then
        Call("SetGravity", CRMarsWeather.BaseGravity.x, CRMarsWeather.BaseGravity.y, CRMarsWeather.BaseGravity.z)
        CRMarsWeather.GravityOwned = false
    end

    CRWeather.ClearWindOverride()
    CRWeather.Shutdown()

    CRMarsWeather.Gust = nil
    CRMarsWeather.ForcedLevel = nil
    CRMarsWeather.ForcedUntil = nil
    CRMarsWeather.Initialized = false
end

-- =============================================================================
-- Mission API
-- =============================================================================

-- The rung the director trends toward. Mission beats move this rather than
-- setting the level directly, so the weather still walks there over a few
-- minutes instead of cutting.
function CRMarsWeather.SetTargetLevel(index)
    CRMarsWeather.TargetLevel = Clamp(tonumber(index) or 1, 1, LEVEL_COUNT)
    Log("target level -> " .. Level(CRMarsWeather.TargetLevel).name)
    return CRMarsWeather.TargetLevel
end

function CRMarsWeather.GetTargetLevel()
    return CRMarsWeather.TargetLevel
end

-- Pins the ladder to a rung for a fixed time -- for a set piece that has to
-- happen on cue. Automatic scheduling resumes when it expires.
function CRMarsWeather.ForceLevel(index, seconds, transitionSeconds)
    if not CRMarsWeather.Initialized then
        CRMarsWeather.Init()
    end

    index = Clamp(tonumber(index) or 1, 1, LEVEL_COUNT)
    CRMarsWeather.ForcedLevel = index
    CRMarsWeather.ForcedUntil = CRMarsWeather.Clock + math.max(1.0, tonumber(seconds) or 60.0)
    ApplyLevel(index, transitionSeconds)
    Log("forced to " .. Level(index).name .. " for " ..
        string.format("%.0f", CRMarsWeather.ForcedUntil - CRMarsWeather.Clock) .. "s")
    return true
end

function CRMarsWeather.ReleaseForcedLevel()
    CRMarsWeather.ForcedUntil = nil
    CRMarsWeather.ForcedLevel = nil
end

function CRMarsWeather.SetAutomatic(enabled)
    CRMarsWeather.Automatic = enabled and true or false
end

function CRMarsWeather.GetLevel()
    return CRMarsWeather.Level
end

function CRMarsWeather.GetLevelName()
    return Level(CRMarsWeather.Level).name
end

function CRMarsWeather.GetWind()
    local direction = WindDirection()
    local speed = CRMarsWeather.WindSpeed
    return SetVector(direction.x * speed, direction.y * speed, direction.z * speed)
end

function CRMarsWeather.GetWindSpeed()
    return CRMarsWeather.WindSpeed
end

-- Approximate view distance in world units. Useful to a mission that wants to
-- hold a cinematic until the player can actually see the thing it points at.
function CRMarsWeather.GetVisibility()
    return LadderValue("visibility")
end

function CRMarsWeather.Describe()
    return string.format(
        "[%s] %s (%.2f) wind %.1f bearing %.0f deg gust %.1f vis %.0f devils %d",
        CRMarsWeather.Profile,
        Level(CRMarsWeather.Level).name,
        CRMarsWeather.LevelValue,
        CRMarsWeather.WindSpeed,
        math.deg(CRMarsWeather.Bearing) % 360.0,
        CRMarsWeather.GustValue,
        CRMarsWeather.GetVisibility(),
        CountDevils())
end

-- =============================================================================
-- Save / load
--
-- Particle systems and Ogre state do not survive a save, so only the director's
-- own scalars persist; everything visual is rebuilt from them on load.
-- =============================================================================

function CRMarsWeather.Save()
    return {
        profile      = CRMarsWeather.Profile,
        level        = CRMarsWeather.Level,
        targetLevel  = CRMarsWeather.TargetLevel,
        levelValue   = CRMarsWeather.LevelValue,
        clock        = CRMarsWeather.Clock,
        nextLevelAt  = CRMarsWeather.NextLevelAt,
        automatic    = CRMarsWeather.Automatic,
        bearing      = CRMarsWeather.Bearing,
        prevailing   = CRMarsWeather.PrevailingBearing,
        windSpeed    = CRMarsWeather.WindSpeed,
        forcedLevel  = CRMarsWeather.ForcedLevel,
        forcedFor    = CRMarsWeather.ForcedUntil and (CRMarsWeather.ForcedUntil - CRMarsWeather.Clock) or nil,
    }
end

function CRMarsWeather.Load(state)
    if type(state) ~= "table" then
        return
    end

    if not CRMarsWeather.Initialized then
        CRMarsWeather.Init()
    end

    -- Before anything reads the ladder: a save taken under one profile must not
    -- be restored against another profile's rungs, which would put the mission
    -- on a preset from the wrong family.
    if state.profile ~= nil and state.profile ~= CRMarsWeather.Profile then
        ApplyProfile(state.profile)
    end

    CRMarsWeather.Level = Clamp(tonumber(state.level) or 1, 1, LEVEL_COUNT)
    CRMarsWeather.TargetLevel = Clamp(tonumber(state.targetLevel) or 2, 1, LEVEL_COUNT)
    CRMarsWeather.LevelValue = Clamp(tonumber(state.levelValue) or CRMarsWeather.Level, 1.0, LEVEL_COUNT)
    CRMarsWeather.Clock = tonumber(state.clock) or 0.0
    CRMarsWeather.NextLevelAt = tonumber(state.nextLevelAt) or CRMarsWeather.Clock
    CRMarsWeather.Automatic = state.automatic ~= false
    CRMarsWeather.Bearing = tonumber(state.bearing) or CRMarsWeather.Bearing
    CRMarsWeather.PrevailingBearing = tonumber(state.prevailing) or CRMarsWeather.PrevailingBearing
    CRMarsWeather.BearingTarget = CRMarsWeather.PrevailingBearing
    CRMarsWeather.NextBearingAt = CRMarsWeather.Clock
    CRMarsWeather.WindSpeed = tonumber(state.windSpeed) or CRMarsWeather.WindSpeed

    -- Devils and fronts are not persisted: they are short-lived set dressing,
    -- and restoring half-aged ones is more code than it is worth. A front in
    -- particular would have to restore its approach state to mean anything, and
    -- a save taken mid-arrival is not worth that.
    CRMarsWeather.DestroyAllDevils()
    DestroyHaboob()

    -- Loading a save rebuilds the Ogre scene, so every particle system we were
    -- tracking is already gone. Clear the bookkeeping before reapplying the
    -- preset or CRWeather will adopt systems that no longer exist.
    if type(CRWeather.ResetSystems) == "function" then
        CRWeather.ResetSystems()
    end
    CRMarsWeather.NextDevilAt = CRMarsWeather.Clock + 10.0
    CRMarsWeather.Gust = nil
    ScheduleNextGust()

    if state.forcedLevel ~= nil and (tonumber(state.forcedFor) or 0.0) > 0.0 then
        CRMarsWeather.ForcedLevel = Clamp(tonumber(state.forcedLevel), 1, LEVEL_COUNT)
        CRMarsWeather.ForcedUntil = CRMarsWeather.Clock + tonumber(state.forcedFor)
    else
        CRMarsWeather.ForcedLevel = nil
        CRMarsWeather.ForcedUntil = nil
    end

    -- Snap rather than fade: the player saved in this weather and expects to
    -- load back into it.
    local level = Level(CRMarsWeather.ForcedLevel or CRMarsWeather.Level)
    CRWeather.SetPreset(level.preset, 0.05)
    CRWeather.Blend = 1.0
    CRWeather.SetWindOverride(WindDirection(), CRMarsWeather.WindSpeed)
    CRMarsWeather.LastSyncSeverity = -1.0
end

function CRMarsWeather.OnObjectCreated(h)
    CRWeather.OnObjectCreated(h)
end

return CRMarsWeather
