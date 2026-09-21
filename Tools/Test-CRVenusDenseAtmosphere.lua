-- Test-CRVenusDenseAtmosphere.lua
--
-- Deterministic host checks for the VenusDenseAtmosphere development preset.
-- It verifies that one intensity drives atmosphere and particles, that
-- CRWeather uses Environment's modifier path instead of writing renderer state
-- directly, and that a weather -> clear transition restores the fresh
-- Environment frame exactly.
--
-- Usage, from the repository root:
--
--     lua Tools/Test-CRVenusDenseAtmosphere.lua Scripts

local scriptDir = ... or "Scripts"
package.path = scriptDir .. "\\?.lua;" .. scriptDir .. "/?.lua;" .. package.path

local BASE = {
    fog = { r = 0.62, g = 0.43, b = 0.27, fogStart = 140.0, fogEnd = 680.0 },
    ambient = { r = 0.31, g = 0.30, b = 0.29 },
    diffuse = { r = 0.72, g = 0.70, b = 0.66 },
    sunPowerScale = 1.10,
}

local modifier = nil
local unregistered = false

Environment = {
    RegisterEnvironmentModifier = function(name, callback)
        assert(name == "CRWeather", "unexpected modifier name")
        modifier = callback
    end,
    UnregisterEnvironmentModifier = function(name)
        assert(name == "CRWeather", "unexpected modifier removal")
        modifier = nil
        unregistered = true
    end,
    GetFogHorizon = function() return 900.0 end,
}

local rec = {
    systems = {},
    quotas = {},
    rates = {},
    affectors = {},
    emitterPositions = {},
    visible = {},
    destroyed = 0,
    directFogWrites = 0,
}

local function bucket(into, name, index)
    into[name] = into[name] or {}
    into[name][index] = into[name][index] or {}
    return into[name][index]
end

local exu = {}
exu.GetFog = function()
    return {
        r = BASE.fog.r, g = BASE.fog.g, b = BASE.fog.b,
        fogStart = BASE.fog.fogStart, fogEnd = BASE.fog.fogEnd,
    }
end
exu.GetAmbientLight = function()
    return { r = BASE.ambient.r, g = BASE.ambient.g, b = BASE.ambient.b }
end
exu.GetSunDiffuse = function()
    return { r = BASE.diffuse.r, g = BASE.diffuse.g, b = BASE.diffuse.b }
end
exu.GetSunPowerScale = function() return BASE.sunPowerScale end
exu.GetCameraTransformMatrix = function()
    return { posit_x = 0.0, posit_y = 10.0, posit_z = 0.0 }
end
exu.SetFog = function() rec.directFogWrites = rec.directFogWrites + 1 return true end
exu.SetAmbientLight = function() return true end
exu.SetSunDiffuse = function() return true end
exu.SetSunPowerScale = function() return true end

exu.CreateParticleSystem = function(name, template)
    rec.systems[name] = template
    return true
end
exu.DestroyParticleSystem = function(name)
    if rec.systems[name] ~= nil then rec.destroyed = rec.destroyed + 1 end
    rec.systems[name] = nil
    return true
end
exu.DetachParticleSystem = function() return true end
exu.AttachParticleSystemToCamera = function() return true end
exu.UpdateParticleFollowers = function() return 0 end
exu.HasParticleSystem = function(name) return rec.systems[name] ~= nil end
exu.SetParticleSystemParticleQuota = function(name, quota)
    rec.quotas[name] = quota
    return true
end
exu.SetParticleSystemKeepLocalSpace = function() return true end
exu.SetParticleSystemNonVisibleUpdateTimeout = function() return true end
exu.SetParticleSystemEmitting = function() return true end
exu.SetParticleSystemVisible = function(name, visible)
    rec.visible[name] = visible
    return true
end
exu.SetParticleEmitterEmissionRate = function(name, index, rate)
    rec.rates[name] = rec.rates[name] or {}
    rec.rates[name][index] = rate
    return true
end
exu.SetParticleEmitterDirection = function() return true end
exu.SetParticleEmitterPosition = function(name, index, position)
    rec.emitterPositions[name] = rec.emitterPositions[name] or {}
    rec.emitterPositions[name][index] = position
    return true
end
exu.SetParticleEmitterVelocity = function() return true end
exu.SetParticleEmitterTimeToLive = function() return true end
exu.SetParticleEmitterAngle = function() return true end
exu.SetParticleEmitterColor = function() return true end
exu.SetParticleEmitterParameter = function() return true end
exu.SetParticleAffectorParameter = function(name, index, parameter, value)
    bucket(rec.affectors, name, index)[parameter] = value
    return true
end
exu.GetParticleSystemEmitterCount = function() return 1 end
exu.GetParticleSystemAffectorCount = function() return 4 end
exu.GetParticleEmitterType = function() return "Box" end
exu.GetParticleAffectorType = function(_, index)
    local names = { [0] = "ColourInterpolator", [1] = "Scaler",
        [2] = "LinearForce", [3] = "DirectionRandomiser" }
    return names[index]
end

package.preload["exu"] = function() return exu end

function SetVector(x, y, z) return { x = x, y = y, z = z } end

local terrainMode = "basin"
function GetTerrainHeightAndNormal(position)
    local center = math.abs(position.x) < 1.0 and math.abs(position.z) < 1.0
    if terrainMode == "basin" then
        return center and 0.0 or 10.0, { x = 0.0, y = 1.0, z = 0.0 }
    elseif terrainMode == "hill" then
        return center and 10.0 or 0.0, { x = 0.0, y = 1.0, z = 0.0 }
    end
    return 0.0, { x = 0.0, y = 0.75, z = 0.0 }
end

local failures = {}
local function check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

local function near(actual, expected, tolerance)
    return actual ~= nil and math.abs(actual - expected) <= (tolerance or 1e-6)
end

local function copyFrame()
    return {
        fog = {
            r = BASE.fog.r, g = BASE.fog.g, b = BASE.fog.b,
            fogStart = BASE.fog.fogStart, fogEnd = BASE.fog.fogEnd,
        },
        ambient = { r = BASE.ambient.r, g = BASE.ambient.g, b = BASE.ambient.b },
        diffuse = { r = BASE.diffuse.r, g = BASE.diffuse.g, b = BASE.diffuse.b },
        sunPowerScale = BASE.sunPowerScale,
    }
end

local function alphaFrom(text)
    local last = nil
    for token in string.gmatch(tostring(text or ""), "%S+") do last = tonumber(token) end
    return last
end

local CRWeatherPresets = require("CRWeatherPresets")
local CRWeather = require("CRWeather")
local preset = CRWeatherPresets.Get("VenusDenseAtmosphere")
local systemName = "cr_wx_venus_dense_mist"

check(preset ~= nil, "VenusDenseAtmosphere must be registered")
check(preset and #preset.precipitation == 1, "the dense preset must use one sparse veil")
check(preset and preset.precipitation[1].template == "CR/VenusGroundHaze",
    "the terrain-pooled veil must use CR/VenusGroundHaze")
check(preset and preset.fog == nil,
    "the ground-haze preset must leave the map's native fog untouched")

CRWeather.Init({ quality = 1.0 })
check(modifier ~= nil, "CRWeather must register an Environment modifier")
check(CRWeather.OwnsEnvironment == false,
    "Environment must remain the renderer atmosphere owner")

CRWeather.SetPreset("VenusDenseAtmosphere", 0.1)
CRWeather.Update(0.1)

check(rec.systems[systemName] == "CR/VenusGroundHaze", "the CR ground haze must be created")
check(rec.quotas[systemName] == 96, "the active quota must remain 96")
local pool = CRWeather.GetTerrainPoolState(systemName)
check(pool and near(pool.weight, 1.0) and near(pool.basinDepth, 10.0),
    "a ten-unit basin must reach full pool weight")
local emitterPosition = (rec.emitterPositions[systemName] or {})[0]
check(emitterPosition and near(emitterPosition.y, -7.5),
    "the emitter must sit 2.5 units above ground relative to the camera")

-- Half intensity: every authored atmosphere target is exactly halfway from the
-- fresh Environment frame, while emission, alpha and scale are halfway too.
CRWeather.SetIntensity(0.5)
CRWeather.Update(0.0)

local half = copyFrame()
modifier(half)
check(near(half.fog.r, BASE.fog.r) and near(half.fog.g, BASE.fog.g)
        and near(half.fog.b, BASE.fog.b),
    "ground haze must not recolour native fog")
check(near(half.fog.fogStart, BASE.fog.fogStart)
        and near(half.fog.fogEnd, BASE.fog.fogEnd),
    "ground haze must not change native fog distances")
check(near(half.ambient.g, (BASE.ambient.g + preset.ambient.g) * 0.5),
    "ambient must interpolate with intensity")
check(near(half.diffuse.b, (BASE.diffuse.b + preset.diffuse.b) * 0.5),
    "sun diffuse must interpolate with intensity")
check(near(half.sunPowerScale, (BASE.sunPowerScale + preset.sunPowerScale) * 0.5),
    "sun power must interpolate with intensity")
check(near((rec.rates[systemName] or {})[0], 3.5),
    "basin haze emission must be 3.5/s at half intensity")

local colour = ((rec.affectors[systemName] or {})[0] or {}).colour1
local scale = ((rec.affectors[systemName] or {})[1] or {}).rate
check(near(alphaFrom(colour), 0.07, 0.0001),
    "ground-haze alpha must be half of 0.14, got " .. tostring(colour))
check(near(scale, 0.625, 0.0001),
    "ground-haze scaler rate must be half of 1.25, got " .. tostring(scale))
local windForce = ((rec.affectors[systemName] or {})[2] or {}).force_vector
check(type(windForce) == "string" and windForce ~= "0 0 0",
    "the LinearForce must receive the live wind vector")
check(rec.directFogWrites == 0,
    "CRWeather must not write fog directly while Environment owns it")

CRWeather.SetIntensity(0.0)
CRWeather.Update(0.0)
local zero = copyFrame()
modifier(zero)
check(near(zero.fog.fogStart, BASE.fog.fogStart)
        and near(zero.sunPowerScale, BASE.sunPowerScale),
    "zero intensity must leave the Environment atmosphere untouched")
check(near((rec.rates[systemName] or {})[0], 0.0) and rec.visible[systemName] == false,
    "zero intensity must stop emission and hide retained particles")

-- Move the same flat camera point from a basin to a local high spot. Pooling
-- must fade away even though intensity is restored to one.
CRWeather.SetIntensity(1.0)
terrainMode = "hill"
for _ = 1, 12 do CRWeather.Update(0.3) end
pool = CRWeather.GetTerrainPoolState(systemName)
check(pool and pool.target == 0.0 and pool.weight < 0.01,
    "a point ten units above its surrounding ring must drain the haze")
check((rec.rates[systemName] or {})[0] < 0.1,
    "a drained high point must have negligible emission")

-- Weather -> clear. At the midpoint both atmosphere and particles must be
-- halfway home; at completion the modifier must leave a fresh frame untouched
-- and the now-costless system must be destroyed.
terrainMode = "basin"
preset.precipitation[1].terrainPool.response = 0.0
CRWeather.Update(0.3)
CRWeather.SetPreset("Clear", 0.2)
CRWeather.Update(0.1)

local clearing = copyFrame()
modifier(clearing)
check(near(clearing.fog.g, BASE.fog.g),
    "clear transition must leave Environment fog untouched")
check(near((rec.rates[systemName] or {})[0], 3.5),
    "clear transition must fade particle emission with the same weight")

CRWeather.Update(0.1)
local cleared = copyFrame()
modifier(cleared)
check(near(cleared.fog.r, BASE.fog.r) and near(cleared.fog.g, BASE.fog.g)
        and near(cleared.fog.b, BASE.fog.b),
    "clear must restore baseline fog RGB exactly")
check(near(cleared.fog.fogStart, BASE.fog.fogStart)
        and near(cleared.fog.fogEnd, BASE.fog.fogEnd),
    "clear must restore baseline fog distances exactly")
check(near(cleared.ambient.r, BASE.ambient.r)
        and near(cleared.diffuse.r, BASE.diffuse.r)
        and near(cleared.sunPowerScale, BASE.sunPowerScale),
    "clear must restore baseline lighting exactly")
check(rec.systems[systemName] == nil and rec.destroyed == 1,
    "clear must destroy the retired mist system")
check(CRWeather.GetPreset() == "Clear", "the public preset state must report Clear")
check(rec.directFogWrites == 0,
    "the complete weather-clear cycle must stay on the modifier path")

CRWeather.Shutdown()
check(unregistered, "shutdown must unregister the Environment modifier")

if #failures == 0 then
    print("VENUS DENSE ATMOSPHERE OK")
    print("  native fog preserved  basin=1.0  hill<0.01  quota=96  clear restored")
else
    for i = 1, #failures do print("FAIL: " .. failures[i]) end
    os.exit(1)
end
