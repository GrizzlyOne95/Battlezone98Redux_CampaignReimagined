-- Test-CRMarsHaboob.lua
--
-- Drives the real CRMarsWeather.lua haboob front against a stubbed exu and a
-- stubbed BZ runtime. No game, no Ogre, no install.
--
-- Usage, from the repository root:
--
--     lua Tools/Test-CRMarsHaboob.lua Scripts
--
-- A haboob is the only weather event in Campaign Reimagined with a geometry
-- problem: it has to spawn upwind, cross the map along the wind axis, pass over
-- the player, and then be retired -- and every one of those can be wrong in a
-- way that still looks like a dust wall on screen. A front that spawns downwind
-- simply never arrives. A front whose node is never turned draws its face along
-- the wrong axis. A front that is never retired is an Ogre system leaking for
-- the rest of the mission. None of that raises an error anywhere.
--
-- Prints MARS HABOOB OK on success; prints each failed expectation and exits 1.

local scriptDir = ... or "Scripts"
package.path = scriptDir .. "\\?.lua;" .. scriptDir .. "/?.lua;" .. package.path

-- =============================================================================
-- Recording exu stub
-- =============================================================================

local rec = {
    systems      = {},   -- name -> { template, position }
    directions   = {},   -- name -> last direction pushed
    emitterParam = {},   -- name -> index -> parameter -> value
    affectorParam = {},  -- name -> index -> parameter -> value
    rates        = {},   -- name -> index -> last rate
    destroyed    = {},   -- name -> true
}

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

exu.CreateParticleSystem = function(name, template, position)
    rec.systems[name] = { template = template, position = position }
    return true
end
exu.HasParticleSystem = function(name) return rec.systems[name] ~= nil end
exu.DestroyParticleSystem = function(name)
    rec.systems[name] = nil
    rec.destroyed[name] = true
    return true
end
exu.DetachParticleSystem = function() return true end
exu.AttachParticleSystemToCamera = function() return true end
exu.UpdateParticleFollowers = function() return 0 end

exu.SetParticleSystemParticleQuota = function() return true end
exu.SetParticleSystemKeepLocalSpace = function() return true end
exu.SetParticleSystemNonVisibleUpdateTimeout = function() return true end
exu.SetParticleSystemEmitting = function() return true end
exu.SetParticleSystemPosition = function(name, position)
    if rec.systems[name] then rec.systems[name].position = position end
    return true
end
exu.SetParticleSystemDirection = function(name, direction)
    rec.directions[name] = direction
    return true
end

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
exu.SetParticleEmitterEnabled = function() return true end

exu.SetParticleEmitterParameter = function(name, index, parameter, value)
    rec.emitterParam[name] = rec.emitterParam[name] or {}
    rec.emitterParam[name][index] = rec.emitterParam[name][index] or {}
    rec.emitterParam[name][index][parameter] = value
    return true
end
exu.SetParticleAffectorParameter = function(name, index, parameter, value)
    rec.affectorParam[name] = rec.affectorParam[name] or {}
    rec.affectorParam[name][index] = rec.affectorParam[name][index] or {}
    rec.affectorParam[name][index][parameter] = value
    return true
end
exu.GetParticleSystemEmitterCount = function() return 2 end
exu.GetParticleSystemAffectorCount = function() return 4 end

package.preload["exu"] = function() return exu end

-- =============================================================================
-- BZ runtime stub
-- =============================================================================

local PLAYER = "player"
local playerPos = { x = 0.0, y = 0.0, z = 0.0 }
local clock = 0.0

function SetVector(x, y, z) return { x = x, y = y, z = z } end
function GetPlayerHandle() return PLAYER end
function IsValid(h) return h == PLAYER end
function GetPosition(h) return h == PLAYER and playerPos or nil end
function GetTime() return clock end
function StartSound() end
-- Flat ground: terrain height is not what this test is about, but the front
-- refuses to spawn without one, so it has to answer.
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

local CRMarsWeather = require("CRMarsWeather")

local function liveFronts()
    local count = 0
    for name in pairs(rec.systems) do
        if string.find(name, "cr_wx_haboob_", 1, true) == 1 then
            count = count + 1
        end
    end
    return count
end

-- =============================================================================
-- Run
-- =============================================================================

-- Start high on the ladder so a front is allowed to form, and take the devils
-- and the gameplay coupling out of the way so this measures one thing.
CRMarsWeather.Init({
    debug             = false,
    dustDevils        = false,
    sensorDegrade     = false,
    windPush          = false,
    startLevel        = 3,
    targetLevel       = 3,
    prevailingBearing = 0.0,
})

-- A front must not be able to form below the ladder threshold, whatever the
-- timer says. Rewinding the timer is the only way to ask that question directly.
CRMarsWeather.LevelValue = 1.0
CRMarsWeather.NextHaboobAt = 0.0
CRMarsWeather.HaboobChance = 1.0

local dt = 1.0 / 20.0
for _ = 1, 40 do
    clock = clock + dt
    CRMarsWeather.Update(dt)
end
check(liveFronts() == 0, "no front may form while the ladder is below HaboobMinLevel")

-- Now let it form.
CRMarsWeather.LevelValue = 3.0
CRMarsWeather.NextHaboobAt = 0.0

local spawnPos, spawnName
local maxConcurrent = 0
local widths = {}
local targetBefore = CRMarsWeather.TargetLevel
local targetAfterArrival = nil
local sawDirection = false
local sawTurbulence = false

for step = 1, 20 * 60 * 6 do   -- six minutes at 20 Hz
    clock = clock + dt
    CRMarsWeather.Update(dt)

    local front = CRMarsWeather.Haboob
    if front ~= nil then
        if spawnName == nil then
            spawnName = front.system
            local system = rec.systems[front.system]
            spawnPos = system and system.position or nil
        end
        if front.system == spawnName then
            local params = (rec.emitterParam[front.system] or {})[0]
            if params and params.width then
                widths[#widths + 1] = params.width
            end
            if rec.directions[front.system] ~= nil then
                sawDirection = true
            end
            local affector = (rec.affectorParam[front.system] or {})[3]
            if affector and affector.randomness then
                sawTurbulence = true
            end
            if front.arrived and targetAfterArrival == nil then
                targetAfterArrival = CRMarsWeather.TargetLevel
            end
        end
    end

    local concurrent = liveFronts()
    if concurrent > maxConcurrent then maxConcurrent = concurrent end
end

-- --- it formed, once, upwind ---------------------------------------------
check(spawnName ~= nil, "a front must form once the ladder is high enough")
check(maxConcurrent <= 1, "only one front may exist at a time, saw " .. tostring(maxConcurrent))

if spawnPos ~= nil then
    -- Bearing 0 blows toward +z, so a front that will arrive starts at -z.
    check(spawnPos.z < 0.0,
        "a front must spawn upwind of the player, spawned at z=" .. string.format("%.0f", spawnPos.z))
    local range = math.sqrt((spawnPos.x * spawnPos.x) + (spawnPos.z * spawnPos.z))
    check(range >= CRMarsWeather.HaboobSpawnRange[1] - 1.0
        and range <= CRMarsWeather.HaboobSpawnRange[2] + 1.0,
        "a front must spawn within HaboobSpawnRange, got " .. string.format("%.0f", range))
end

-- --- it was driven through the bridge as it closed -------------------------
check(#widths >= 2, "the face width must be written more than once as the front closes")
local peakWidth, finalWidth = 0.0, widths[#widths] or 0.0
for i = 1, #widths do
    if widths[i] > peakWidth then peakWidth = widths[i] end
end
if #widths >= 2 then
    -- The peak, not the last sample. The face widens on the way in and narrows
    -- again as the front departs, so the final value is a measurement of the
    -- departure and would pass this test on a front that never widened at all.
    check(peakWidth >= CRMarsWeather.HaboobFaceWidth[2] * 0.9,
        "the face must reach near its authored maximum at arrival, peaked at "
        .. string.format("%.0f of %.0f", peakWidth, CRMarsWeather.HaboobFaceWidth[2]))
    check(peakWidth <= CRMarsWeather.HaboobFaceWidth[2] + 1.0,
        "the face must not exceed its authored maximum")
    check(finalWidth < peakWidth,
        "the face must narrow again as the front departs")
end
check(sawDirection, "the front's node must be turned to face along the wind")
check(sawTurbulence, "the front's turbulence affector must be driven")

-- --- arrival pushed the ladder, once --------------------------------------
check(targetAfterArrival ~= nil, "the front must reach the player within six minutes")
if targetAfterArrival ~= nil then
    check(targetAfterArrival == targetBefore + 1,
        "arrival must step the target level exactly one rung, "
        .. tostring(targetBefore) .. " -> " .. tostring(targetAfterArrival))
end

-- --- and it was retired ----------------------------------------------------
check(spawnName ~= nil and rec.destroyed[spawnName] == true,
    "a front that has passed downwind must be destroyed, not left in the scene")

-- --- teardown leaves nothing behind ---------------------------------------
-- Force a front to be ALIVE at teardown. Asking this question at an arbitrary
-- moment answers nothing: fronts spend most of their cycle not existing, so a
-- shutdown that leaks would still look clean most of the time.
CRMarsWeather.LevelValue = 3.0
CRMarsWeather.NextHaboobAt = 0.0
CRMarsWeather.HaboobChance = 1.0
for _ = 1, 20 * 60 do
    clock = clock + dt
    CRMarsWeather.Update(dt)
    if CRMarsWeather.Haboob ~= nil then break end
end
check(CRMarsWeather.Haboob ~= nil, "a front must be live going into the shutdown check")

CRMarsWeather.Shutdown()
check(liveFronts() == 0, "shutdown must destroy any live front")
check(CRMarsWeather.Haboob == nil, "shutdown must clear the front bookkeeping too")

-- =============================================================================

if #failures == 0 then
    print("MARS HABOOB OK")
    print(string.format("  front=%s  spawn=(%.0f, %.0f)  face %.0f -> %.0f -> %.0f",
        tostring(spawnName),
        spawnPos and spawnPos.x or 0.0, spawnPos and spawnPos.z or 0.0,
        widths[1] or 0.0, peakWidth, finalWidth))
else
    for i = 1, #failures do print("FAIL: " .. failures[i]) end
    os.exit(1)
end
