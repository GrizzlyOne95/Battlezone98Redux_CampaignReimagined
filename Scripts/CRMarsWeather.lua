-- CRMarsWeather.lua
-- Mars weather director for Campaign Reimagined.
--
-- CRWeather.lua is a renderer: hand it a preset and it draws that weather. It
-- has no opinion about when weather should happen, and its wind is one frozen
-- vector per preset. This module is the half that was missing -- the thing that
-- decides what the sky is doing minute to minute and keeps the air moving while
-- it does.
--
-- Four parts:
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

local LEVEL_COUNT = #CRMarsWeather.Levels

-- =============================================================================
-- Runtime state
-- =============================================================================

CRMarsWeather.Initialized      = false
CRMarsWeather.Automatic        = true
CRMarsWeather.Level            = 1      -- integer rung currently selected
CRMarsWeather.TargetLevel      = 2      -- the rung the director trends toward
CRMarsWeather.LevelValue       = 1.0    -- smoothed fractional position
CRMarsWeather.NextLevelAt      = 0.0
CRMarsWeather.ForcedUntil      = nil
CRMarsWeather.ForcedLevel      = nil
CRMarsWeather.Clock            = 0.0

CRMarsWeather.PrevailingBearing = 0.0   -- radians, direction the wind blows TO
CRMarsWeather.Bearing           = 0.0
CRMarsWeather.BearingTarget     = 0.0
CRMarsWeather.BearingWander     = 0.9   -- radians of excursion either side
CRMarsWeather.BearingRate       = 0.055 -- radians/second cap
CRMarsWeather.NextBearingAt     = 0.0

CRMarsWeather.WindSpeed         = 0.0
CRMarsWeather.BaseWindSpeed     = 0.0
CRMarsWeather.Gust              = nil   -- { start, rise, hold, fall, peak, veer }
CRMarsWeather.NextGustAt        = 0.0
CRMarsWeather.GustValue         = 0.0

CRMarsWeather.Devils            = {}    -- systemName -> devil record
CRMarsWeather.DevilSerial       = 0
CRMarsWeather.NextDevilAt       = 0.0

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
        CRMarsWeather.BearingTarget = CRMarsWeather.PrevailingBearing + RandomRange(-wander, wander)
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
        Log("could not create " .. systemName)
        return false
    end

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
    if not CRMarsWeather.AllowDustDevils then
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

    if player == nil or playerPos == nil then
        return
    end

    local maxDevils = math.min(CRMarsWeather.MaxDevils, math.floor(LadderValue("maxDevils") + 0.5))
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
-- Gameplay coupling
-- =============================================================================

-- Environment owns radar; we only contribute scales. See the gameplay-modifier
-- comment block in Environment.lua for why this cannot be a direct write.
local function GameplayContribution(frame)
    if not CRMarsWeather.AllowSensorDegrade then
        return
    end

    frame.radarRange  = frame.radarRange * LadderValue("radarRange")
    frame.radarPeriod = frame.radarPeriod * LadderValue("radarPeriod")
    frame.velocJam    = frame.velocJam * LadderValue("velocJam")
end

local function UpdateSensors()
    local environment = rawget(_G, "Environment")
    if environment == nil or not CRMarsWeather.GameplayRegistered then
        return
    end

    -- Only ask for a resync when the contribution actually moved. A sync pass
    -- walks every craft in the mission.
    local severity = CRMarsWeather.GetSeverity()
    if math.abs(severity - CRMarsWeather.LastSyncSeverity) > 0.02 then
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
    if options.enabled ~= nil then CRMarsWeather.Enabled = options.enabled and true or false end
    if options.debug ~= nil then CRMarsWeather.Debug = options.debug and true or false end
    if options.dustDevils ~= nil then CRMarsWeather.AllowDustDevils = options.dustDevils and true or false end
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

function CRMarsWeather.Update(dt)
    if not CRMarsWeather.Initialized then
        CRMarsWeather.Init()
    end
    if not CRMarsWeather.Enabled then
        return
    end

    dt = tonumber(dt) or 0.0
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

    CRWeather.Update(dt)
end

function CRMarsWeather.Shutdown()
    if not CRMarsWeather.Initialized then
        return
    end

    CRMarsWeather.DestroyAllDevils()

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
        "%s (%.2f) wind %.1f bearing %.0f deg gust %.1f vis %.0f devils %d",
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

    -- Devils are not persisted: they are short-lived set dressing, and
    -- restoring half-aged ones is more code than it is worth.
    CRMarsWeather.DestroyAllDevils()

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
