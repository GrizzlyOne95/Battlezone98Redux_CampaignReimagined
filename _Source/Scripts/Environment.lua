-- Environment.lua
-- Dynamic atmosphere system for Battlezone 98 Redux
-- Handles Day/Night cycles, weather events, and gameplay impacts.

local exu = require("exu")

Environment = {
    -- Configuration
    CycleDuration = 1200,  -- 20 minutes (in seconds)
    RadarRangeNerf = 0.7,  -- 30% reduction
    RadarPeriodNerf = 2.0, -- 100% increase (slower scan)
    VelocJamBuff = 1.5,    -- 50% increase (sneakier)

    -- State
    IsNight = false,
    OriginalRadarRanges = {},  -- table<handle, number>
    OriginalRadarPeriods = {}, -- table<handle, number>
    OriginalVelocJams = {},    -- table<handle, number>
    DustStormTimer = 0,

    -- Colors and Fog conform to user-provided structures
    DayAmbient = { r = 0.4, g = 0.4, b = 0.4 },
    DayDiffuse = { r = 1.0, g = 1.0, b = 1.0 },
    DayFog = { r = 0.5, g = 0.5, b = 0.6, start = 100, ending = 800 },

    NightAmbient = { r = 0.05, g = 0.05, b = 0.1 },
    NightDiffuse = { r = 0.2, g = 0.2, b = 0.4 },
    NightFog = { r = 0.02, g = 0.02, b = 0.05, start = 10, ending = 200 },

    DustStormFog = { r = 0.4, g = 0.3, b = 0.1, start = 5, ending = 50 },

    DebugScale = 1.0, -- Set to 60.0 for 1 second = 1 minute testing
    Initialized = false
}

local function Lerp(a, b, t)
    return a + (b - a) * t
end

local function LerpColor(c1, c2, t)
    return {
        r = Lerp(c1.r, c2.r, t),
        g = Lerp(c1.g, c2.g, t),
        b = Lerp(c1.b, c2.b, t)
    }
end

local function LerpFog(f1, f2, t)
    return {
        r = Lerp(f1.r, f2.r, t),
        g = Lerp(f1.g, f2.g, t),
        b = Lerp(f1.b, f2.b, t),
        start = Lerp(f1.start, f2.start, t),
        ending = Lerp(f1.ending, f2.ending, t)
    }
end

function Environment.Init()
    if not GetMapTRNFilename then return end

    local trnFilename = GetMapTRNFilename()
    if not trnFilename or trnFilename == "" then return end

    local trn = OpenODF(trnFilename)
    if not trn then return end

    -- Read Intensity (Diffuse) and Ambient from [NormalView]
    local intensity = GetODFInt(trn, "NormalView", "Intensity", 200) / 255
    local ambient = GetODFInt(trn, "NormalView", "Ambient", 100) / 255

    Environment.DayDiffuse = { r = intensity, g = intensity, b = intensity }
    Environment.DayAmbient = { r = ambient, g = ambient, b = ambient }

    -- Read Fog parameters
    local fogStart = GetODFFloat(trn, "NormalView", "FogStart", 100)
    local fogEnd = GetODFFloat(trn, "NormalView", "FogEnd", 800)

    Environment.DayFog.start = fogStart
    Environment.DayFog.ending = fogEnd

    Environment.Initialized = true
    print("Environment: Initialized from " .. trnFilename)
end

function Environment.Update(timestep)
    if not Environment.Initialized then
        Environment.Init()
    end

    local curTime = GetTime() * Environment.DebugScale
    local progress = curTime % Environment.CycleDuration

    local targetAmbient, targetDiffuse, targetFog
    local wasNight = Environment.IsNight

    -- Cycle Phases
    if progress < 600 then
        -- Day
        Environment.IsNight = false
        targetAmbient = Environment.DayAmbient
        targetDiffuse = Environment.DayDiffuse
        targetFog = Environment.DayFog
    elseif progress < 700 then
        -- Sunset (100s transition)
        local t = (progress - 600) / 100
        Environment.IsNight = (t > 0.5)
        targetAmbient = LerpColor(Environment.DayAmbient, Environment.NightAmbient, t)
        targetDiffuse = LerpColor(Environment.DayDiffuse, Environment.NightDiffuse, t)
        targetFog = LerpFog(Environment.DayFog, Environment.NightFog, t)
    elseif progress < 1100 then
        -- Night
        Environment.IsNight = true
        targetAmbient = Environment.NightAmbient
        targetDiffuse = Environment.NightDiffuse
        targetFog = Environment.NightFog
    else
        -- Sunrise (100s transition)
        local t = (progress - 1100) / 100
        Environment.IsNight = (t < 0.5)
        targetAmbient = LerpColor(Environment.NightAmbient, Environment.DayAmbient, t)
        targetDiffuse = LerpColor(Environment.NightDiffuse, Environment.DayDiffuse, t)
        targetFog = LerpFog(Environment.NightFog, Environment.DayFog, t)
    end

    -- Handle Dust Storm Overlay
    if Environment.DustStormTimer > 0 then
        Environment.DustStormTimer = Environment.DustStormTimer - timestep
        targetFog = Environment.DustStormFog -- Override fog

        -- Gravity Wobble
        local t = GetTime()
        local wobbleX = math.sin(t * 5.0) * 0.5
        local wobbleZ = math.cos(t * 4.3) * 0.5
        exu.SetGravity(wobbleX, -9.8, wobbleZ)
    elseif progress < 1100 and progress >= 1100 - timestep then
        -- Clean up gravity if storm ended or sunrise started
        exu.SetGravity(0, -9.8, 0)
    end

    -- Apply Atmosphere
    exu.SetSunAmbient(targetAmbient.r, targetAmbient.g, targetAmbient.b)
    exu.SetSunDiffuse(targetDiffuse.r, targetDiffuse.g, targetDiffuse.b)
    exu.SetFog(targetFog.r, targetFog.g, targetFog.b, targetFog.start, targetFog.ending)

    -- Gameplay Impact: Radar and Stealth
    if Environment.IsNight ~= wasNight then
        Environment.SyncGameplayImpacts()
    end
end

function Environment.SyncGameplayImpacts()
    -- Iterate through all objects and apply adjustments if night
    for h in AllObjects() do
        Environment.ProcessObjectNightEffects(h)
    end
end

function Environment.ProcessObjectNightEffects(h)
    if not IsValid(h) or not IsCraft(h) then return end

    if Environment.IsNight then
        -- Apply Radar Range Nerf
        local currentRange = exu.GetRadarRange(h)
        if currentRange > 0 and not Environment.OriginalRadarRanges[h] then
            Environment.OriginalRadarRanges[h] = currentRange
            exu.SetRadarRange(h, currentRange * Environment.RadarRangeNerf)
        end

        -- Apply Radar Period Nerf (Slower)
        local currentPeriod = exu.GetRadarPeriod(h)
        if currentPeriod > 0 and not Environment.OriginalRadarPeriods[h] then
            Environment.OriginalRadarPeriods[h] = currentPeriod
            exu.SetRadarPeriod(h, currentPeriod * Environment.RadarPeriodNerf)
        end

        -- Apply VelocJam Buff (Sneakier)
        local currentVelocJam = exu.GetVelocJam(h)
        if currentVelocJam > 0 and not Environment.OriginalVelocJams[h] then
            Environment.OriginalVelocJams[h] = currentVelocJam
            -- Using 2 args despite doc ambiguity, following standard BZ 'Set' pattern
            exu.SetVelocJam(h, currentVelocJam * Environment.VelocJamBuff)
        end
    else
        -- Restore original Radar Range
        if Environment.OriginalRadarRanges[h] then
            exu.SetRadarRange(h, Environment.OriginalRadarRanges[h])
            Environment.OriginalRadarRanges[h] = nil
        end

        -- Restore original Radar Period
        if Environment.OriginalRadarPeriods[h] then
            exu.SetRadarPeriod(h, Environment.OriginalRadarPeriods[h])
            Environment.OriginalRadarPeriods[h] = nil
        end

        -- Restore original VelocJam
        if Environment.OriginalVelocJams[h] then
            -- Restore original value if possible, else reset
            exu.SetVelocJam(h, Environment.OriginalVelocJams[h])
            Environment.OriginalVelocJams[h] = nil
        end
    end
end

function Environment.OnObjectCreated(h)
    -- Ensure new units get the current environment's gameplay settings
    Environment.ProcessObjectNightEffects(h)
end

function Environment.TriggerDustStorm(duration)
    Environment.DustStormTimer = duration or 30
end

return Environment
