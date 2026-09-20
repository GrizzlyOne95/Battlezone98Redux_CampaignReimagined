-- Test-CRWeatherParameters.lua
--
-- Drives the real CRWeather.lua against a stubbed exu that implements EXU's
-- Ogre StringInterface bridge, and checks the part of preset tuning that is
-- invisible in-game when it goes wrong.
--
-- Usage, from the repository root:
--
--     lua Tools/Test-CRWeatherParameters.lua Scripts
--
-- Every failure mode here is silent on a real install. Ogre ignores a parameter
-- name it does not recognise and an index that is out of range without saying
-- anything, so a preset that addresses the wrong affector simply renders
-- without that tuning and looks like art that needs another pass. The same goes
-- for the cache: re-sending an unchanged value costs a string parse per
-- parameter per emitter per frame and shows up as a frame-time cost nobody can
-- attribute. So this checks what is written, what is written only once, and
-- what is refused.
--
-- Prints WEATHER PARAMETERS OK on success; prints each failed expectation and
-- exits 1 otherwise.

local scriptDir = ... or "Scripts"
package.path = scriptDir .. "\\?.lua;" .. scriptDir .. "/?.lua;" .. package.path

-- =============================================================================
-- Recording exu stub
-- =============================================================================

-- What each template declares, so the stub can answer the introspection calls
-- the way a real Ogre build would and the index validation has something to
-- disagree with.
local TEMPLATES = {
    ["CR/Test/Two"] = { emitters = 2, affectors = 2 },
}

local rec = {
    systems        = {},   -- name -> template
    emitterParams  = {},   -- name -> index -> parameter -> value
    affectorParams = {},   -- name -> index -> parameter -> value
    enabled        = {},   -- name -> index -> boolean
    rates          = {},   -- name -> index -> rate
    writes         = 0,    -- every accepted StringInterface write
    enableWrites   = 0,
}

local function bucket(into, name, index)
    into[name] = into[name] or {}
    into[name][index] = into[name][index] or {}
    return into[name][index]
end

local exu = {}
setmetatable(exu, { __index = function() return nil end })

exu.GetFog = function() return { r = 0.5, g = 0.4, b = 0.3, fogStart = 100, fogEnd = 800 } end
exu.SetFog = function() return true end
exu.GetAmbientLight = function() return { r = 0.5, g = 0.5, b = 0.5 } end
exu.SetAmbientLight = function() return true end
exu.GetSunDiffuse = function() return { r = 0.6, g = 0.6, b = 0.6 } end
exu.SetSunDiffuse = function() return true end
exu.GetSunPowerScale = function() return 1.0 end
exu.SetSunPowerScale = function() return true end

exu.CreateParticleSystem = function(name, template)
    rec.systems[name] = template
    return true
end
exu.HasParticleSystem = function(name) return rec.systems[name] ~= nil end
exu.DestroyParticleSystem = function(name) rec.systems[name] = nil return true end
exu.DetachParticleSystem = function() return true end
exu.AttachParticleSystemToCamera = function() return true end
exu.UpdateParticleFollowers = function() return 0 end

exu.SetParticleSystemParticleQuota = function() return true end
exu.SetParticleSystemKeepLocalSpace = function() return true end
exu.SetParticleSystemNonVisibleUpdateTimeout = function() return true end
exu.SetParticleSystemEmitting = function() return true end

exu.SetParticleEmitterEmissionRate = function(name, index, rate)
    rec.rates[name] = rec.rates[name] or {}
    rec.rates[name][index] = rate
    return true
end
exu.SetParticleEmitterDirection = function() return true end
exu.SetParticleEmitterVelocity = function() return true end
exu.SetParticleEmitterTimeToLive = function() return true end
exu.SetParticleEmitterAngle = function() return true end
exu.SetParticleEmitterColor = function() return true end

exu.SetParticleEmitterEnabled = function(name, index, wanted)
    rec.enabled[name] = rec.enabled[name] or {}
    rec.enabled[name][index] = wanted
    rec.enableWrites = rec.enableWrites + 1
    return true
end

-- The bridge itself. A real setter refuses an index Ogre does not have, so the
-- stub does too: a test whose stub accepts everything cannot tell a correct
-- preset from one addressing a non-existent affector.
local function countFor(name, kind)
    local template = TEMPLATES[rec.systems[name] or ""]
    return template and template[kind] or 0
end

exu.SetParticleEmitterParameter = function(name, index, parameter, value)
    if index < 0 or index >= countFor(name, "emitters") then
        return false
    end
    bucket(rec.emitterParams, name, index)[parameter] = value
    rec.writes = rec.writes + 1
    return true
end

exu.SetParticleAffectorParameter = function(name, index, parameter, value)
    if index < 0 or index >= countFor(name, "affectors") then
        return false
    end
    bucket(rec.affectorParams, name, index)[parameter] = value
    rec.writes = rec.writes + 1
    return true
end

exu.GetParticleSystemEmitterCount = function(name) return countFor(name, "emitters") end
exu.GetParticleSystemAffectorCount = function(name) return countFor(name, "affectors") end
exu.GetParticleEmitterType = function(name, index)
    if index < 0 or index >= countFor(name, "emitters") then return nil end
    return "Box"
end
exu.GetParticleAffectorType = function(name, index)
    if index < 0 or index >= countFor(name, "affectors") then return nil end
    return index == 0 and "ColourFader" or "Scaler"
end
exu.GetParticleEmitterParameterNames = function() return { "width", "height", "depth" } end
exu.GetParticleAffectorParameterNames = function() return { "alpha", "rate" } end

package.preload["exu"] = function() return exu end

function SetVector(x, y, z) return { x = x, y = y, z = z } end

-- =============================================================================
-- Harness
-- =============================================================================

local failures = {}
local function check(condition, message)
    if not condition then
        failures[#failures + 1] = message
    end
end

local function near(a, b, tolerance)
    return a ~= nil and b ~= nil and math.abs(a - b) <= (tolerance or 1e-6)
end

local realPrint = print
local captured = nil
local function capturePrints(enabled)
    if enabled then
        captured = {}
        print = function(line) captured[#captured + 1] = tostring(line) end
    else
        print = realPrint
    end
end

local function capturedMatches(pattern)
    for i = 1, #(captured or {}) do
        if string.find(captured[i], pattern, 1, true) then
            return true
        end
    end
    return false
end

local CRWeatherPresets = require("CRWeatherPresets")
local CRWeather = require("CRWeather")

-- Two seconds per rung keeps the ramp legible: transitionIn is 10s below, so a
-- step is a tenth of the blend and the interpolated sample lands mid-range.
local function advance(seconds, step)
    step = step or 0.1
    local elapsed = 0.0
    while elapsed < seconds - 1e-9 do
        CRWeather.Update(step)
        elapsed = elapsed + step
    end
end

-- =============================================================================
-- Preset under test
-- =============================================================================

CRWeatherPresets.Presets.ParamProbe = {
    name = "ParamProbe",
    precipitation = {
        {
            system   = "cr_test_params",
            template = "CR/Test/Two",
            offset   = { x = 0.0, y = 10.0, z = 0.0 },
            emitters = {
                [0] = {
                    rate   = 100.0,
                    params = {
                        width = { 100.0, 300.0 },   -- interpolated
                        depth = 250.0,              -- constant
                    },
                },
                [1] = {
                    rate         = 50.0,
                    enabledAbove = 0.50,
                },
            },
            affectors = {
                [0] = { alpha = { -0.40, -0.10 } },
                [1] = { rate = 2.5 },
            },
        },
    },
    wind          = { x = -1.0, y = -0.2, z = 0.0 },
    windSpeed     = 20.0,
    transitionIn  = 10.0,
    transitionOut = 10.0,
}

-- =============================================================================
-- 1. Nothing is written while the storm has no presence
-- =============================================================================

CRWeather.Init({ debug = false })
CRWeather.SetPreset("ParamProbe")

check(rec.systems["cr_test_params"] == "CR/Test/Two", "the probe system must be created")
check(rec.writes == 0,
    "no parameter may be written at zero weight, got " .. tostring(rec.writes))

-- =============================================================================
-- 2. Values interpolate by live weight, and constants arrive as authored
-- =============================================================================

advance(3.0)   -- ~30% of a 10s transition

local emitter0 = (rec.emitterParams["cr_test_params"] or {})[0] or {}
local affector0 = (rec.affectorParams["cr_test_params"] or {})[0] or {}

check(emitter0.depth ~= nil and near(emitter0.depth, 250.0),
    "a constant param must arrive as authored, got " .. tostring(emitter0.depth))
check(emitter0.width ~= nil and emitter0.width > 100.0 and emitter0.width < 300.0,
    "an interpolated param must sit between calm and full mid-transition, got "
    .. tostring(emitter0.width))
check(affector0.alpha ~= nil and affector0.alpha > -0.40 and affector0.alpha < -0.10,
    "an interpolated affector param must interpolate too, got " .. tostring(affector0.alpha))

local affector1 = (rec.affectorParams["cr_test_params"] or {})[1] or {}
check(near(affector1.rate, 2.5), "a constant affector param must arrive as authored")

-- =============================================================================
-- 3. enabledAbove gates the emitter rather than starving it
-- =============================================================================

local enabled = rec.enabled["cr_test_params"] or {}
check(enabled[1] == false, "an emitter below its threshold must be disabled, not rate-zeroed")
check((rec.rates["cr_test_params"] or {})[1] == nil,
    "a disabled emitter must not be given a rate")

advance(8.0)   -- past 0.5 weight and on to fully applied

enabled = rec.enabled["cr_test_params"] or {}
check(enabled[1] == true, "an emitter above its threshold must be enabled again")
check((rec.rates["cr_test_params"] or {})[1] ~= nil,
    "a re-enabled emitter must start receiving its rate")

-- =============================================================================
-- 4. A settled storm stops writing
-- =============================================================================

emitter0 = (rec.emitterParams["cr_test_params"] or {})[0] or {}
check(near(emitter0.width, 300.0, 1e-3),
    "a fully applied param must reach its full value, got " .. tostring(emitter0.width))

local settledWrites = rec.writes
local settledEnables = rec.enableWrites
advance(2.0)
check(rec.writes == settledWrites,
    "a settled storm must not rewrite unchanged parameters, "
    .. tostring(rec.writes - settledWrites) .. " redundant writes")
check(rec.enableWrites == settledEnables,
    "a settled storm must not rewrite emitter enable state")

-- =============================================================================
-- 5. A stale index is reported rather than silently dropped
-- =============================================================================

CRWeather.ResetSystems()

CRWeatherPresets.Presets.ParamDrift = {
    name = "ParamDrift",
    precipitation = {
        {
            system    = "cr_test_drift",
            template  = "CR/Test/Two",
            emitters  = { [0] = { rate = 10.0 } },
            -- The template declares two affectors; this addresses a third.
            affectors = { [2] = { alpha = -0.2 } },
        },
    },
    wind = { x = -1.0, y = 0.0, z = 0.0 }, windSpeed = 5.0,
    transitionIn = 1.0, transitionOut = 1.0,
}

capturePrints(true)
CRWeather.SetPreset("ParamDrift")
capturePrints(false)

check(capturedMatches("addresses affector 2"),
    "a preset addressing an affector the template does not have must say so")

-- =============================================================================
-- 6. Destroying a system forgets what was sent to it
-- =============================================================================

CRWeather.ResetSystems()
rec.writes = 0
CRWeather.SetPreset("ParamProbe")
advance(12.0)
check(rec.writes > 0,
    "a rebuilt system must be re-sent its parameters rather than trusting a stale cache")

-- =============================================================================
-- 7. The introspection dump reports what the system exposes
-- =============================================================================

capturePrints(true)
local described = CRWeather.DescribeSystem("cr_test_params")
capturePrints(false)

check(described == true, "DescribeSystem must succeed on a live system")
check(capturedMatches("emitter[0] Box"), "the dump must name each emitter and its Ogre type")
check(capturedMatches("affector[0] ColourFader"), "the dump must name each affector and its type")
check(capturedMatches("width"), "the dump must list the parameter spellings")

CRWeather.Shutdown()

-- =============================================================================

if #failures == 0 then
    print("WEATHER PARAMETERS OK")
    print(string.format("  parameter writes=%d  enable writes=%d", rec.writes, rec.enableWrites))
else
    for i = 1, #failures do print("FAIL: " .. failures[i]) end
    os.exit(1)
end
