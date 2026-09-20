-- Test-CRWeatherFogHorizon.lua
--
-- Drives the real CRWeather.lua and checks that weather fog -- and only weather
-- fog -- is limited to the terrain draw distance the map authored.
--
-- Usage, from the repository root:
--
--     lua Tools/Test-CRWeatherFogHorizon.lua Scripts
--
-- The defect this guards against is visible and was measured in game: stock
-- .trn files set VisibilityRange, FlatRange and FogEnd to the same number
-- (misn04: all 250) so that fog finishes exactly where geometry does, but the
-- weather presets are authored for far more open ground -- MarsHaze finishes at
-- 520, MarsDustRising 380, MarsDustStorm 320. On misn04 that leaves MarsHaze
-- only 37% opaque at the distance terrain is cut off, and the remaining 63%
-- reads as a bright band along the horizon.
--
-- The regression running the other way matters just as much. Environment.lua's
-- own DayFog finishes at 700 on the same 250-unit map, and clamping that too
-- would change the established look of every mission whether or not weather is
-- running. So the rule under test is narrow:
--
--     weatherFogEnd = min(requestedWeatherFogEnd, authoredTerrainHorizon)
--
-- with base Environment fog left exactly as it was.
--
-- Prints FOG HORIZON OK on success; prints each failed expectation and exits 1.

local scriptDir = ... or "Scripts"
package.path = scriptDir .. "\\?.lua;" .. scriptDir .. "/?.lua;" .. package.path

-- misn04.trn, which is the map the defect was observed on.
local MAP_FOG = { r = 0.55, g = 0.40, b = 0.25, fogStart = 120.0, fogEnd = 250.0 }
local CULL = 250.0

-- CRWeather reaches the engine through the exu table, never through a global,
-- so stubbing a global Call here would silently test nothing.
package.preload["exu"] = function()
    return {
        GetFog = function()
            return { r = MAP_FOG.r, g = MAP_FOG.g, b = MAP_FOG.b,
                     fogStart = MAP_FOG.fogStart, fogEnd = MAP_FOG.fogEnd }
        end,
        GetAmbientLight  = function() return { r = 0.2, g = 0.2, b = 0.2 } end,
        GetSunDiffuse    = function() return { r = 0.6, g = 0.6, b = 0.6 } end,
        GetSunPowerScale = function() return 1.0 end,
    }
end

function SetVector(x, y, z) return { x = x, y = y, z = z } end

local failures = {}
local function check(condition, what)
    if not condition then failures[#failures + 1] = what end
end

local function approx(a, b)
    return math.abs(a - b) < 0.001
end

-- Ogre's linear fog: 0 at fogStart, 1 at fogEnd.
local function densityAt(fog, distance)
    if distance <= fog.fogStart then return 0.0 end
    if distance >= fog.fogEnd then return 1.0 end
    return (distance - fog.fogStart) / (fog.fogEnd - fog.fogStart)
end

local function newFrame()
    return {
        fog = { r = MAP_FOG.r, g = MAP_FOG.g, b = MAP_FOG.b,
                fogStart = MAP_FOG.fogStart, fogEnd = MAP_FOG.fogEnd },
        ambient = { r = 0.2, g = 0.2, b = 0.2 },
    }
end

local CRWeatherPresets = require("CRWeatherPresets")
local CRWeather = require("CRWeather")

-- =============================================================================
-- The horizon is sourced from Environment when Environment.lua is present
-- =============================================================================

Environment = { GetFogHorizon = function() return CULL end }

CRWeather.Init({ enabled = true })

-- =============================================================================
-- Weather fog is clamped; density reaches 1.0 exactly where terrain stops
-- =============================================================================

local overrun = { "MarsHaze", "MarsDustRising", "MarsDustStorm" }
for i = 1, #overrun do
    local name = overrun[i]
    local preset = CRWeatherPresets.Get(name)
    check(preset ~= nil, name .. " must exist")
    check(preset.fog.fogEnd > CULL,
        name .. " is only a useful case while it is authored past the horizon")

    CRWeather.Layers = { { preset = preset, weight = 1.0 } }
    local frame = newFrame()
    CRWeather.ApplyEnvironmentContribution(frame)

    check(approx(frame.fog.fogEnd, CULL),
        name .. " fogEnd must be clamped to the horizon, got " .. tostring(frame.fog.fogEnd))
    check(frame.fog.fogStart < frame.fog.fogEnd,
        name .. " must keep a real fog range after clamping")
    check(approx(densityAt(frame.fog, CULL), 1.0),
        name .. " must be fully opaque at the cut-off")
end

-- =============================================================================
-- A preset that already fits is left exactly as authored
-- =============================================================================

local severe = CRWeatherPresets.Get("MarsDustStormSevere")
check(severe.fog.fogEnd < CULL, "MarsDustStormSevere is the inside-the-horizon case")
CRWeather.Layers = { { preset = severe, weight = 1.0 } }
local severeFrame = newFrame()
CRWeather.ApplyEnvironmentContribution(severeFrame)
check(approx(severeFrame.fog.fogEnd, severe.fog.fogEnd),
    "a preset inside the horizon must not be touched")
check(approx(severeFrame.fog.fogStart, severe.fog.fogStart),
    "its fogStart must not be touched either")

-- =============================================================================
-- The regression guard: base Environment fog is NOT clamped
--
-- This is the whole reason the clamp is applied to the preset's requested value
-- before the blend rather than to the composed frame afterwards.
-- =============================================================================

CRWeather.Layers = {}
local baseFrame = { fog = { r = 0.65, g = 0.45, b = 0.25, fogStart = 200.0, fogEnd = 700.0 },
                    ambient = { r = 0.2, g = 0.2, b = 0.2 } }
CRWeather.ApplyEnvironmentContribution(baseFrame)
check(approx(baseFrame.fog.fogEnd, 700.0),
    "Environment's own fog must survive untouched with no weather, got " ..
    tostring(baseFrame.fog.fogEnd))
check(approx(baseFrame.fog.fogStart, 200.0),
    "Environment's fogStart must survive untouched too")

-- Same again at zero weight, which is what a preset standing down looks like on
-- its final frames.
CRWeather.Layers = { { preset = CRWeatherPresets.Get("MarsHaze"), weight = 0.0 } }
local zeroFrame = { fog = { r = 0.65, g = 0.45, b = 0.25, fogStart = 200.0, fogEnd = 700.0 },
                    ambient = { r = 0.2, g = 0.2, b = 0.2 } }
CRWeather.ApplyEnvironmentContribution(zeroFrame)
check(approx(zeroFrame.fog.fogEnd, 700.0),
    "a zero-weight weather layer must not pull base fog toward the horizon")

-- =============================================================================
-- Partial weight blends toward the clamped value, not the authored one
-- =============================================================================

CRWeather.Layers = { { preset = CRWeatherPresets.Get("MarsHaze"), weight = 0.5 } }
local halfFrame = newFrame()
CRWeather.ApplyEnvironmentContribution(halfFrame)
-- Base 250 lerped halfway to the clamped 250 is still 250; the authored 520
-- would have produced 385, so this distinguishes the two.
check(halfFrame.fog.fogEnd <= CULL + 0.001,
    "a half-weight layer must not push fogEnd past the horizon, got " ..
    tostring(halfFrame.fog.fogEnd))

-- =============================================================================
-- Opting out restores the authored values exactly
-- =============================================================================

CRWeather.FogHorizon = false
CRWeather.Layers = { { preset = CRWeatherPresets.Get("MarsHaze"), weight = 1.0 } }
local optOut = newFrame()
CRWeather.ApplyEnvironmentContribution(optOut)
check(approx(optOut.fog.fogEnd, 520.0),
    "fogHorizon=false must apply the preset as authored, got " .. tostring(optOut.fog.fogEnd))

-- A numeric override wins over whatever Environment reports.
CRWeather.FogHorizon = 180.0
local overridden = newFrame()
CRWeather.ApplyEnvironmentContribution(overridden)
check(approx(overridden.fog.fogEnd, 180.0),
    "a numeric fogHorizon must override Environment, got " .. tostring(overridden.fog.fogEnd))

-- =============================================================================
-- Without Environment.lua the map's own captured fogEnd is the fallback
-- =============================================================================

Environment = nil
CRWeather.Initialized = false
CRWeather.FogHorizon = nil
CRWeather.Init({ enabled = true })
CRWeather.Layers = { { preset = CRWeatherPresets.Get("MarsHaze"), weight = 1.0 } }
local standalone = newFrame()
CRWeather.ApplyEnvironmentContribution(standalone)
check(approx(standalone.fog.fogEnd, MAP_FOG.fogEnd),
    "the standalone path must fall back to the captured map fogEnd, got " ..
    tostring(standalone.fog.fogEnd))

-- =============================================================================

if #failures == 0 then
    print("FOG HORIZON OK")
    print(string.format("  horizon=%.0f  clamped=%d presets  base fog preserved", CULL, #overrun))
else
    for i = 1, #failures do print("FAIL: " .. failures[i]) end
    os.exit(1)
end
