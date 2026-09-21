-- Test-CRMarsVolcano.lua
--
-- Drives the real CRMarsWeather.lua volcano profile against a stubbed exu and a
-- stubbed BZ runtime. No game, no Ogre, no install.
--
-- Usage, from the repository root:
--
--     lua Tools/Test-CRMarsVolcano.lua Scripts
--
-- A profile swaps the whole ladder, which means it can fail in two directions
-- and neither raises an error. Select the wrong family and the mission runs
-- plains weather on a volcano, which just looks like weather. Leak the volcano
-- ladder into the default and misn04 silently changes, which looks like nothing
-- at all until someone plays it. Both are checked here, along with the
-- behaviours the profile carries beyond its presets.
--
-- Prints MARS VOLCANO OK on success; prints each failed expectation and exits 1.

local scriptDir = ... or "Scripts"
package.path = scriptDir .. "\\?.lua;" .. scriptDir .. "/?.lua;" .. package.path

-- =============================================================================
-- Stubs
-- =============================================================================

local rec = { systems = {} }

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
exu.GetGravity = function() return { x = 0.0, y = -3.7, z = 0.0 } end
exu.SetGravity = function() return true end

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
exu.SetParticleSystemPosition = function() return true end
exu.SetParticleSystemDirection = function() return true end
exu.SetParticleEmitterEmissionRate = function() return true end
exu.SetParticleEmitterDirection = function() return true end
exu.SetParticleEmitterVelocity = function() return true end
exu.SetParticleEmitterTimeToLive = function() return true end
exu.SetParticleEmitterAngle = function() return true end
exu.SetParticleEmitterColor = function() return true end
exu.SetParticleEmitterEnabled = function() return true end
exu.SetParticleEmitterParameter = function() return true end
exu.SetParticleAffectorParameter = function() return true end
exu.GetParticleSystemEmitterCount = function() return 2 end
exu.GetParticleSystemAffectorCount = function() return 4 end

package.preload["exu"] = function() return exu end

local PLAYER = "player"
local playerPos = { x = 0.0, y = 0.0, z = 0.0 }
local clock = 0.0

function SetVector(x, y, z) return { x = x, y = y, z = z } end
function GetPlayerHandle() return PLAYER end
function IsValid(h) return h == PLAYER end
function GetPosition(h) return h == PLAYER and playerPos or nil end
function GetTime() return clock end
function StartSound() end
function GetTerrainHeightAndNormal() return 0.0 end

-- =============================================================================
-- Harness
-- =============================================================================

local failures = {}
local function check(condition, message)
    if not condition then
        failures[#failures + 1] = message
    end
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

local function capturedMatches(text)
    for i = 1, #(captured or {}) do
        if string.find(captured[i], text, 1, true) then return true end
    end
    return false
end

local CRWeather = require("CRWeather")
local CRMarsWeather = require("CRMarsWeather")

local dt = 1.0 / 20.0

-- Runs the director for `seconds`, returning every preset it selected and the
-- full excursion of the wind bearing.
local function run(seconds)
    local presets = {}
    local minBearing, maxBearing = math.huge, -math.huge
    local steps = math.floor(seconds / dt)
    for _ = 1, steps do
        clock = clock + dt
        CRMarsWeather.Update(dt)
        presets[CRWeather.GetPreset()] = true
        local b = CRMarsWeather.Bearing
        if b < minBearing then minBearing = b end
        if b > maxBearing then maxBearing = b end
    end
    return presets, (maxBearing - minBearing)
end

local function names(set)
    local out = {}
    for k in pairs(set) do out[#out + 1] = k end
    table.sort(out)
    return table.concat(out, ", ")
end

-- =============================================================================
-- 1. The default is untouched
-- =============================================================================

CRMarsWeather.Init({ startLevel = 1, targetLevel = 3 })

check(CRMarsWeather.GetProfile() == "Plains",
    "no profile must select Plains, got " .. tostring(CRMarsWeather.GetProfile()))
check(CRMarsWeather.SlopeWind == nil, "Plains must have no slope wind")
check(CRMarsWeather.AllowHaboob == true, "Plains must allow haboob fronts")
check(#CRMarsWeather.Levels == 5, "Plains must have five rungs")

local plainsPresets = run(900.0)
for preset in pairs(plainsPresets) do
    check(string.find(preset, "Volcano", 1, true) == nil,
        "the default ladder must never select a volcano preset, saw " .. preset)
end
check(next(plainsPresets) ~= nil, "the default run must have selected something")

CRMarsWeather.Shutdown()

-- =============================================================================
-- 2. The volcano profile applies its own ladder and behaviour
-- =============================================================================

clock = 0.0
capturePrints(true)
CRMarsWeather.Init({ profile = "Volcano", startLevel = 1, targetLevel = 3 })
capturePrints(false)

check(CRMarsWeather.GetProfile() == "Volcano",
    "the volcano profile must be selected, got " .. tostring(CRMarsWeather.GetProfile()))
check(CRMarsWeather.AllowHaboob == false,
    "a ridge system breaks up a wall front; the volcano profile must disable haboobs")
check(type(CRMarsWeather.SlopeWind) == "table", "the volcano profile must carry a slope wind")
check(CRMarsWeather.MaxDevils == 3, "Tharsis flanks are devil country; the cap must rise")
check(CRMarsWeather.DevilMinRange == 120.0, "the volcano profile must bring devils in closer")
check(#CRMarsWeather.Levels == 5, "the volcano ladder must have five rungs")

local volcanoPresets, bearingRange = run(1200.0)

for preset in pairs(volcanoPresets) do
    check(string.find(preset, "MarsVolcano", 1, true) == 1 or preset == "Clear",
        "the volcano ladder must only select volcano presets, saw " .. preset)
end
check(next(volcanoPresets) ~= nil, "the volcano run must have selected something")

-- Every rung names a preset that actually exists. CRWeather prints and bails on
-- an unknown name rather than raising, so a typo in the ladder would otherwise
-- show up only as weather that never appears.
capturePrints(true)
local CRWeatherPresets = require("CRWeatherPresets")
for i = 1, #CRMarsWeather.Levels do
    local rung = CRMarsWeather.Levels[i]
    check(CRWeatherPresets.Get(rung.preset) ~= nil,
        "volcano rung " .. i .. " names a preset that does not exist: " .. tostring(rung.preset))
end
capturePrints(false)

-- No haboob may have formed at any point in that run.
for name in pairs(rec.systems) do
    check(string.find(name, "cr_wx_haboob_", 1, true) == nil,
        "no haboob front may form under the volcano profile, saw " .. name)
end
check(CRMarsWeather.Haboob == nil, "no front may be live under the volcano profile")

-- =============================================================================
-- 3. The slope wind actually swings the bearing
-- =============================================================================

-- Volcano wander is 0.35 rad either side and a gust veers at most 0.22, so
-- wander plus veer alone cannot exceed 2*(0.35+0.22) = 1.14 rad. Anything above
-- that had to come from the slope oscillation, which is the point of this
-- profile's wind: a slope wind reverses as the ground heats and cools rather
-- than wandering around a fixed prevailing heading.
check(bearingRange > 1.30,
    "the slope wind must swing the bearing well past what wander and gusts allow, got "
    .. string.format("%.2f rad", bearingRange))
check(bearingRange < 3.20,
    "the slope wind must stay bounded, got " .. string.format("%.2f rad", bearingRange))

-- =============================================================================
-- 4. Save and load keep the profile
-- =============================================================================

local saved = CRMarsWeather.Save()
check(saved.profile == "Volcano", "Save must record the active profile")

CRMarsWeather.Shutdown()
clock = 0.0
CRMarsWeather.Init({ startLevel = 1, targetLevel = 2 })
check(CRMarsWeather.GetProfile() == "Plains", "a fresh Init must be back on Plains")

CRMarsWeather.Load(saved)
check(CRMarsWeather.GetProfile() == "Volcano",
    "Load must restore the profile the save was taken under, got "
    .. tostring(CRMarsWeather.GetProfile()))
check(string.find(CRMarsWeather.Levels[1].preset, "MarsVolcano", 1, true) == 1,
    "Load must restore the volcano ladder, not just the name")

CRMarsWeather.Shutdown()

-- =============================================================================
-- 5. An unknown profile falls back rather than going silent
-- =============================================================================

clock = 0.0
capturePrints(true)
CRMarsWeather.Init({ profile = "Atlantis", startLevel = 1, targetLevel = 2 })
capturePrints(false)

check(CRMarsWeather.GetProfile() == "Plains",
    "an unknown profile must fall back to Plains, got " .. tostring(CRMarsWeather.GetProfile()))
check(capturedMatches("unknown profile"),
    "an unknown profile must say so rather than silently running the default")

CRMarsWeather.Shutdown()

-- =============================================================================

if #failures == 0 then
    print("MARS VOLCANO OK")
    print("  plains presets:  " .. names(plainsPresets))
    print("  volcano presets: " .. names(volcanoPresets))
    print(string.format("  slope-wind bearing swing: %.2f rad", bearingRange))
else
    for i = 1, #failures do print("FAIL: " .. failures[i]) end
    os.exit(1)
end
