-- Test-CRMarsWeather.lua
--
-- Drives the real Environment.lua, CRWeather.lua and CRMarsWeather.lua against
-- a stubbed exu and a stubbed BZ Lua runtime. No game, no Ogre, no install.
--
-- Usage, from the repository root:
--
--     lua Tools/Test-CRMarsWeather.lua Scripts
--
-- What this checks is the part that is expensive to discover in-game: that the
-- ladder only ever moves one rung at a time, that wind never snaps, that
-- Environment stays the single writer for both fog and radar, that a save load
-- across a scene teardown rebuilds rather than adopting dead particle systems,
-- and that nothing at all is left behind after Shutdown.
--
-- Prints MARS WEATHER OK and a weather trace on success; prints each failed
-- expectation and exits 1 otherwise.

local scriptDir = ... or "Scripts"
package.path = scriptDir .. "\\?.lua;" .. scriptDir .. "/?.lua;" .. package.path

-- =============================================================================
-- Recording exu stub
-- =============================================================================

local rec = {
    systems      = {},   -- name -> { template, position, emitting, quota, rates }
    fog          = nil,
    ambient      = nil,
    sunPower     = nil,
    gravity      = { x = 0.0, y = -9.8, z = 0.0 },
    radarRange   = {},   -- handle -> value
    radarPeriod  = {},
    velocJam     = {},
    sky          = nil,
    windDirs     = {},   -- last direction pushed per system
}

local exu = {}
setmetatable(exu, { __index = function() return nil end })

exu.GetFog = function() return { r = 0.5, g = 0.5, b = 0.55, fogStart = 120, fogEnd = 900 } end
exu.SetFog = function(r, g, b, s, e) rec.fog = { r = r, g = g, b = b, fogStart = s, fogEnd = e } return true end
exu.GetAmbientLight = function() return { r = 0.5, g = 0.5, b = 0.5 } end
exu.SetAmbientLight = function(r, g, b) rec.ambient = { r = r, g = g, b = b } return true end
exu.GetSunDiffuse = function() return { r = 0.5, g = 0.5, b = 0.5 } end
exu.SetSunDiffuse = function() return true end
exu.GetSunSpecular = function() return { r = 0.5, g = 0.5, b = 0.5 } end
exu.SetSunSpecular = function() return true end
exu.GetSunDirection = function() return { x = 0, y = -1, z = 0 } end
exu.SetOgreSunDirection = function() return true end
exu.GetSunPowerScale = function() return 1.0 end
exu.SetSunPowerScale = function(v) rec.sunPower = v return true end
exu.GetSunShadowFarDistance = function() return 900 end
exu.SetSunShadowFarDistance = function() return true end
exu.SetViewportShadowsEnabled = function() return true end

exu.GetGravity = function() return { x = 0.0, y = -9.8, z = 0.0 } end
exu.SetGravity = function(x, y, z) rec.gravity = { x = x, y = y, z = z } return true end

local STOCK_RADAR_RANGE = 400.0
local STOCK_RADAR_PERIOD = 1.0
local STOCK_VELOC_JAM = 10.0

exu.GetRadarRange = function(h) return rec.radarRange[h] or STOCK_RADAR_RANGE end
exu.SetRadarRange = function(h, v) rec.radarRange[h] = v return true end
exu.GetRadarPeriod = function(h) return rec.radarPeriod[h] or STOCK_RADAR_PERIOD end
exu.SetRadarPeriod = function(h, v) rec.radarPeriod[h] = v return true end
exu.GetVelocJam = function(h) return rec.velocJam[h] or STOCK_VELOC_JAM end
exu.SetVelocJam = function(h, v) rec.velocJam[h] = v return true end

exu.CreateParticleSystem = function(name, template, position)
    if rec.systems[name] ~= nil then return false end
    rec.systems[name] = {
        template = template,
        position = position,
        emitting = false,
        rates    = {},
    }
    return true
end
exu.DestroyParticleSystem = function(name)
    if rec.systems[name] == nil then return false end
    rec.systems[name] = nil
    return true
end
exu.HasParticleSystem = function(name) return rec.systems[name] ~= nil end
exu.DetachParticleSystem = function() return true end
exu.AttachParticleSystemToCamera = function() return true end
exu.SetParticleSystemKeepLocalSpace = function() return true end
exu.SetParticleSystemParticleQuota = function(name, q)
    if rec.systems[name] then rec.systems[name].quota = q end
    return true
end
exu.SetParticleSystemNonVisibleUpdateTimeout = function() return true end
exu.SetParticleSystemEmitting = function(name, on)
    if rec.systems[name] then rec.systems[name].emitting = on end
    return true
end
exu.SetParticleSystemPosition = function(name, p)
    if rec.systems[name] then rec.systems[name].position = p end
    return true
end
exu.SetParticleEmitterEmissionRate = function(name, i, r)
    if rec.systems[name] then rec.systems[name].rates[i] = r end
    return true
end
exu.SetParticleEmitterDirection = function(name, i, d)
    rec.windDirs[name] = d
    return true
end
exu.SetParticleEmitterVelocity = function() return true end
exu.SetParticleEmitterTimeToLive = function() return true end
exu.SetParticleEmitterAngle = function() return true end
exu.SetParticleEmitterColor = function() return true end
exu.UpdateParticleFollowers = function() return 0 end
exu.SetSkyDome = function(m) rec.sky = m return true end
exu.SetSkyBox = function(m) rec.sky = m return true end

package.preload["exu"] = function() return exu end
package.preload["RuntimeEnhancements"] = function()
    return { Initialize = function() end, Update = function() end, OnObjectCreated = function() end }
end

-- =============================================================================
-- BZ runtime stub
-- =============================================================================

local now = 0.0
local PLAYER = 1001
local CRAFT = { 1001, 1002, 1003 }

function GetTime() return now end
function SetVector(x, y, z) return { x = x, y = y, z = z } end
function AddTMsg() end
function StartSound() end
function GetPlayerHandle() return PLAYER end
function IsValid(h) return h ~= nil end
function IsCraft() return true end
function GetPosition() return { x = 3800.0, y = 2.0, z = 99700.0 } end
function GetTerrainHeightAndNormal() return 2.0, { x = 0, y = 1, z = 0 } end
function AllCraft()
    local i = 0
    return function()
        i = i + 1
        return CRAFT[i]
    end
end
function ObjectsInRange() return function() return nil end end

-- =============================================================================

local Environment = require("Environment")
local CRWeather = require("CRWeather")
local CRMarsWeather = require("CRMarsWeather")

local failures = {}
local function check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

local function countSystems()
    local n = 0
    for _ in pairs(rec.systems) do n = n + 1 end
    return n
end

local function countDevils()
    local n = 0
    for name in pairs(rec.systems) do
        if string.find(name, "cr_wx_devil_", 1, true) == 1 then n = n + 1 end
    end
    return n
end

-- =============================================================================
-- Run
-- =============================================================================

math.randomseed(20260907)

Environment.EnableVisualRuntime = false
Environment.Init()

CRMarsWeather.Init({
    startLevel        = 1,
    targetLevel       = 3,
    prevailingBearing = 1.0,
    baseSky           = { type = "dome", material = "CR_Sky/MarsBase", curvature = 12, tiling = 6, distance = 4000 },
})

check(Environment.Modifiers["CRWeather"] ~= nil, "CRWeather should register an environment modifier")
check(Environment.GameplayModifiers["CRMarsWeather"] ~= nil, "CRMarsWeather should register a gameplay modifier")
check(CRWeather.GetPreset() == "MarsHaze", "the ladder should open on MarsHaze, got " .. tostring(CRWeather.GetPreset()))

local dt = 1.0 / 30.0
local lastBearing = CRMarsWeather.Bearing
local lastLevel = CRMarsWeather.GetLevel()
local maxTurnRate = 0.0
local maxLevelJump = 0
local minWind, maxWind = 1e9, -1e9
local gustCount = 0
local sawGust = false
local presetsSeen = {}
local maxDevilsSeen = 0
local devilLevels = {}
local samples = {}

-- 25 minutes of mission time.
for step = 1, 30 * 60 * 25 do
    now = now + dt
    CRMarsWeather.Update(dt)
    Environment.Update(dt)

    local bearing = CRMarsWeather.Bearing
    local delta = math.abs(bearing - lastBearing)
    if delta > math.pi then delta = (2.0 * math.pi) - delta end
    if (delta / dt) > maxTurnRate then maxTurnRate = delta / dt end
    lastBearing = bearing

    local level = CRMarsWeather.GetLevel()
    local jump = math.abs(level - lastLevel)
    if jump > maxLevelJump then maxLevelJump = jump end
    lastLevel = level

    local wind = CRMarsWeather.GetWindSpeed()
    if wind < minWind then minWind = wind end
    if wind > maxWind then maxWind = wind end

    if CRMarsWeather.Gust ~= nil then
        if not sawGust then gustCount = gustCount + 1 end
        sawGust = true
    else
        sawGust = false
    end

    presetsSeen[CRWeather.GetPreset()] = true

    local devils = countDevils()
    if devils > maxDevilsSeen then maxDevilsSeen = devils end
    if devils > 0 then devilLevels[level] = true end

    if (step % 4500) == 0 then
        samples[#samples + 1] = {
            level = CRMarsWeather.LevelValue,
            fogEnd = rec.fog and rec.fog.fogEnd or 0,
            radar = rec.radarRange[PLAYER] or STOCK_RADAR_RANGE,
            wind = wind,
        }
    end
end

-- --- wind --------------------------------------------------------------------
check(maxTurnRate <= (CRMarsWeather.BearingRate + 1e-6),
    string.format("wind bearing turned at %.4f rad/s, cap is %.4f", maxTurnRate, CRMarsWeather.BearingRate))
check(minWind >= 0.0, "wind speed must never go negative, saw " .. tostring(minWind))
check(gustCount > 10, "gusts should fire repeatedly over 25 minutes, saw " .. tostring(gustCount))
check(maxWind > 20.0, "the ladder should reach real wind at some point, peak was " .. tostring(maxWind))

-- --- ladder ------------------------------------------------------------------
check(maxLevelJump <= 1, "the ladder must move one rung at a time, saw a jump of " .. tostring(maxLevelJump))
for preset in pairs(presetsSeen) do
    check(string.find(preset, "Mars", 1, true) == 1,
        "a Mars mission should only ever select Mars presets, saw " .. preset)
end

-- --- dust devils -------------------------------------------------------------
check(maxDevilsSeen > 0, "dust devils should have appeared in the calm half of the ladder")
check(maxDevilsSeen <= CRMarsWeather.MaxDevils,
    "dust devils exceeded the cap: " .. tostring(maxDevilsSeen))
for level in pairs(devilLevels) do
    check(level <= 3, "dust devils must not form inside a storm, saw one at level " .. tostring(level))
end

-- --- severity actually drives the world --------------------------------------
local worst, best = nil, nil
for i = 1, #samples do
    if worst == nil or samples[i].level > worst.level then worst = samples[i] end
    if best == nil or samples[i].level < best.level then best = samples[i] end
end
check(worst ~= nil and best ~= nil, "expected sampled weather over the run")
if worst ~= nil and best ~= nil and worst.level > (best.level + 0.5) then
    check(worst.fogEnd < best.fogEnd,
        string.format("worse weather should contract visibility (%.0f vs %.0f)", worst.fogEnd, best.fogEnd))
    check(worst.radar <= best.radar,
        string.format("worse weather should not improve radar (%.1f vs %.1f)", worst.radar, best.radar))
end

-- --- forced level ------------------------------------------------------------
CRMarsWeather.ForceLevel(5, 30.0, 2.0)
check(CRMarsWeather.GetLevel() == 5, "ForceLevel should select the severe rung immediately")
for _ = 1, 30 * 20 do
    now = now + dt
    CRMarsWeather.Update(dt)
    Environment.Update(dt)
end
check(CRMarsWeather.GetLevel() == 5, "a forced level must hold for its whole duration")
check(CRWeather.GetPreset() == "MarsDustStormSevere", "the severe rung should select the severe preset")

local function NightOnlyRadar()
    local blend = Environment.NightBlend or 0.0
    return STOCK_RADAR_RANGE * (1.0 + ((Environment.RadarRangeNerf - 1.0) * blend))
end

local stormRadar = rec.radarRange[PLAYER]
local nightOnly = NightOnlyRadar()
check(stormRadar < nightOnly * 0.95,
    string.format("a severe storm should degrade radar beyond the night nerf, got %.1f against %.1f",
        stormRadar or -1, nightOnly))

local lateral = math.sqrt((rec.gravity.x * rec.gravity.x) + (rec.gravity.z * rec.gravity.z))
check(lateral > 0.05, string.format("a severe storm should push laterally, got %.4f", lateral))
check(math.abs(rec.gravity.y + 9.8) < 1e-6, "vertical gravity must be left alone")

-- --- save / load -------------------------------------------------------------
local saved = CRMarsWeather.Save()
local savedLevel = CRMarsWeather.GetLevel()
local savedBearing = CRMarsWeather.Bearing

CRMarsWeather.Level = 1
CRMarsWeather.Bearing = 0.0
CRMarsWeather.Load(saved)
check(CRMarsWeather.GetLevel() == savedLevel, "load should restore the ladder rung")
check(math.abs(CRMarsWeather.Bearing - savedBearing) < 1e-6, "load should restore the wind bearing")
check(countDevils() == 0, "load should not leave stale dust devils behind")

-- --- save / load across a scene teardown -------------------------------------
-- This is the case that actually bites: loading a save rebuilds the Ogre scene,
-- so every particle system is gone even though the module still has them in its
-- bookkeeping. Simulate that by clearing the recorder behind the module's back,
-- then assert the weather comes back rather than silently rendering nothing.
rec.systems = {}
CRMarsWeather.Load(saved)
check(countSystems() > 0,
    "a load across a scene teardown must rebuild the particle systems, got " .. tostring(countSystems()))

local rebuiltPreset = CRWeather.GetPreset()
check(rebuiltPreset == CRMarsWeather.Levels[CRMarsWeather.GetLevel()].preset,
    "the rebuilt weather should match the saved rung, got " .. tostring(rebuiltPreset))

for _ = 1, 60 do
    now = now + dt
    CRMarsWeather.Update(dt)
    Environment.Update(dt)
end

local emitting = false
for _, system in pairs(rec.systems) do
    if system.emitting then emitting = true end
end
check(emitting, "the rebuilt weather should actually be emitting")

-- --- forced level releases back to automatic ---------------------------------
CRMarsWeather.ForceLevel(5, 4.0, 1.0)
check(CRMarsWeather.ForcedUntil ~= nil, "ForceLevel should set a hold")
for _ = 1, 30 * 8 do
    now = now + dt
    CRMarsWeather.Update(dt)
    Environment.Update(dt)
end
check(CRMarsWeather.ForcedUntil == nil, "a forced level must release when its timer expires")

-- --- teardown ----------------------------------------------------------------
CRMarsWeather.Shutdown()

check(countSystems() == 0, "shutdown must destroy every particle system, " .. tostring(countSystems()) .. " left")
check(Environment.Modifiers["CRWeather"] == nil, "shutdown should unregister the environment modifier")
check(Environment.GameplayModifiers["CRMarsWeather"] == nil, "shutdown should unregister the gameplay modifier")
check(math.abs(rec.gravity.x) < 1e-6 and math.abs(rec.gravity.z) < 1e-6,
    "shutdown must restore gravity, left at " .. string.format("%.4f, %.4f", rec.gravity.x, rec.gravity.z))

-- Radar has to come back on its own once the storm is gone, without the mission
-- having to know anything about it.
now = now + 5.0
Environment.Update(dt)
Environment.SyncGameplayImpacts()
Environment.SyncGameplayImpacts()
local restored = rec.radarRange[PLAYER] or -1
local expected = NightOnlyRadar()
check(math.abs(restored - expected) < 0.5,
    string.format("radar should fall back to the night-only value after the storm, got %.1f against %.1f",
        restored, expected))

-- --- restart in the same process ---------------------------------------------
-- misn04's Start stands the weather down and brings it straight back up. The
-- second life has to be a real one, not a module that thinks it is already
-- running and skips its own init.
CRMarsWeather.Init({ startLevel = 3, targetLevel = 3 })
check(CRMarsWeather.Initialized, "the module should come back up after a shutdown")
check(CRMarsWeather.GetLevel() == 3, "a restart should honour the new start level")

for _ = 1, 30 * 5 do
    now = now + dt
    CRMarsWeather.Update(dt)
    Environment.Update(dt)
end
check(countSystems() > 0, "a restarted weather system should be rendering again")
check(Environment.GameplayModifiers["CRMarsWeather"] ~= nil,
    "a restart should re-register the gameplay modifier")

-- --- atmosphere continuity across a preset change ----------------------------
-- The contribution used to read only the incoming preset at weight Blend, and
-- SetPreset restarts Blend at 0, so every rung change dropped fog, ambient,
-- diffuse and sun straight back to the bare mission baseline for a frame and
-- then ramped the new preset in over the next 20-odd seconds. In game that read
-- as the weather snapping. Weather has to hand over without a step -- including
-- when the change interrupts a transition that is still running.

local function BaselineFrame()
    return {
        fog = { r = 0.50, g = 0.42, b = 0.34, fogStart = 100.0, fogEnd = 900.0 },
        ambient = { r = 0.30, g = 0.28, b = 0.26 },
        diffuse = { r = 0.80, g = 0.76, b = 0.70 },
        sunPowerScale = 1.0,
    }
end

local function SampleAtmosphere()
    return CRWeather.ApplyEnvironmentContribution(BaselineFrame())
end

-- Largest single-channel move between two samples, with fog distance put on the
-- same 0..1 footing as the colours so one threshold covers all of them.
local function AtmosphereStep(a, b)
    local step = math.abs(a.fog.fogEnd - b.fog.fogEnd) / 1000.0
    step = math.max(step, math.abs(a.fog.fogStart - b.fog.fogStart) / 1000.0)
    step = math.max(step, math.abs(a.fog.r - b.fog.r))
    step = math.max(step, math.abs(a.ambient.r - b.ambient.r))
    step = math.max(step, math.abs(a.diffuse.r - b.diffuse.r))
    step = math.max(step, math.abs((a.sunPowerScale or 1.0) - (b.sunPowerScale or 1.0)))
    return step
end

-- A change out of a fully settled preset.
CRWeather.SetPreset("MarsHaze", 4.0)
for _ = 1, 30 * 8 do CRWeather.Update(dt) end
local settledBefore = SampleAtmosphere()
CRWeather.SetPreset("MarsDustStorm", 20.0)
local settledAfter = SampleAtmosphere()
check(AtmosphereStep(settledBefore, settledAfter) < 0.005,
    string.format("a preset change must not step the atmosphere, moved %.3f",
        AtmosphereStep(settledBefore, settledAfter)))

-- ... and a change that interrupts a transition still in flight, which is the
-- case the ladder actually produces.
for _ = 1, 30 * 6 do CRWeather.Update(dt) end
check(CRWeather.Blend < 1.0, "the interruption case needs a transition still running")
local midBefore = SampleAtmosphere()
CRWeather.SetPreset("MarsDustRising", 18.0)
local midAfter = SampleAtmosphere()
check(AtmosphereStep(midBefore, midAfter) < 0.005,
    string.format("interrupting a transition must not step the atmosphere, moved %.3f",
        AtmosphereStep(midBefore, midAfter)))

-- A displaced preset keeps its systems while it is still fading -- that is what
-- stops its particles vanishing -- so the invariant is that no live system ever
-- outlives the layer that owns it.
local function HasLayer(preset)
    for i = 1, #CRWeather.Layers do
        if CRWeather.Layers[i].preset == preset then return true end
    end
    return false
end

local unowned = 0
for _, live in pairs(CRWeather.LiveSystems) do
    if not HasLayer(live.preset) then unowned = unowned + 1 end
end
check(unowned == 0,
    string.format("no particle system may outlive its preset's layer, found %d", unowned))

-- Run the interrupted transition out. Displaced presets must actually be
-- retired, not merely sitting at zero weight: the old sweep only ever looked at
-- a single Previous, so a preset displaced mid-transition leaked its systems for
-- the rest of the mission.
for _ = 1, 30 * 40 do CRWeather.Update(dt) end
check(#CRWeather.Layers == 1 and CRWeather.Layers[1].preset == CRWeather.Active,
    string.format("a completed transition should leave exactly one layer, found %d", #CRWeather.Layers))
local foreign = 0
for _, live in pairs(CRWeather.LiveSystems) do
    if live.preset ~= CRWeather.Active then foreign = foreign + 1 end
end
check(foreign == 0,
    string.format("a completed transition must retire every displaced preset's systems, found %d", foreign))

CRMarsWeather.Shutdown()
check(countSystems() == 0, "the second shutdown must clean up too")

-- =============================================================================

if #failures == 0 then
    print("MARS WEATHER OK")
    print(string.format("  gusts=%d  wind=%.1f..%.1f  maxDevils=%d  turnRate=%.4f rad/s",
        gustCount, minWind, maxWind, maxDevilsSeen, maxTurnRate))
    local names = {}
    for preset in pairs(presetsSeen) do names[#names + 1] = preset end
    table.sort(names)
    print("  presets: " .. table.concat(names, ", "))
    for i = 1, #samples do
        print(string.format("  t=%4.1f min  level=%.2f  fogEnd=%5.0f  radar=%5.1f  wind=%4.1f",
            i * 2.5, samples[i].level, samples[i].fogEnd, samples[i].radar, samples[i].wind))
    end
else
    for i = 1, #failures do print("FAIL: " .. failures[i]) end
    os.exit(1)
end
