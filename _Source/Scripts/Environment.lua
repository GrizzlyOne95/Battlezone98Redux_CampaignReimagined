-- Environment.lua
-- Dynamic atmosphere system for Battlezone 98 Redux
-- Handles Day/Night cycles, weather events, and gameplay impacts.

local exu = require("exu")

Environment = {
    -- Configuration
    CycleDuration = 900,   -- 15 minutes (Mars sol is ~24h 37m, scaled for gameplay)
    RadarRangeNerf = 0.7,  -- 30% reduction
    RadarPeriodNerf = 2.0, -- 100% increase (slower scan)
    VelocJamBuff = 1.5,    -- 50% increase (sneakier)

    -- State
    IsNight = false,
    OriginalRadarRanges = {},  -- table<handle, number>
    OriginalRadarPeriods = {}, -- table<handle, number>
    OriginalVelocJams = {},    -- table<handle, number>
    DustStormTimer = 0,

    -- Mars-themed Colors and Fog
    -- Bright Martian day - warm orange-white light
    DayAmbient = { r = 0.35, g = 0.30, b = 0.25 },
    DayDiffuse = { r = 1.0, g = 0.9, b = 0.75 },
    DayFog = { r = 0.65, g = 0.45, b = 0.25, start = 200, ending = 700 },

    -- Martian night - very dark blue-black for immersive feel
    NightAmbient = { r = 0.01, g = 0.01, b = 0.02 },
    NightDiffuse = { r = 0.04, g = 0.04, b = 0.08 },
    NightFog = { r = 0.02, g = 0.02, b = 0.03, start = 50, ending = 120 },

    -- Dust storm - thick orange-brown
    DustStormFog = { r = 0.5, g = 0.3, b = 0.12, start = 5, ending = 45 },

    DebugScale = 1.0, -- Set to 60.0 for 1 second = 1 minute testing
    Initialized = false,

    LastGravity = nil,
    IsDustStorm = false,
    LastPhase = "Initial"
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

    -- Scale Intensity/Ambient to make day feel brighter
    Environment.DayDiffuse = {
        r = math.min(1, intensity * 1.5),
        g = math.min(1, intensity * 1.5),
        b = math.min(1,
            intensity * 1.5)
    }
    Environment.DayAmbient = {
        r = math.min(1, ambient * 1.2),
        g = math.min(1, ambient * 1.2),
        b = math.min(1,
            ambient * 1.2)
    }

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

    local currentPhase = "Unknown"
    if progress < 450 then
        currentPhase = "Day"
    elseif progress < 550 then
        currentPhase = "Sunset"
    elseif progress < 850 then
        currentPhase = "Night"
    else
        currentPhase = "Sunrise"
    end

    if currentPhase ~= Environment.LastPhase then
        local msg = "Environment: Entering Phase [" .. currentPhase .. "]"
        print(msg)
        if AddTMsg then
            AddTMsg(msg)
        end
        Environment.LastPhase = currentPhase
    end

    local targetAmbient, targetDiffuse, targetFog
    local wasNight = Environment.IsNight
    local wasDustStorm = Environment.IsDustStorm

    -- Cycle Phases (scaled for 900s cycle)
    if progress < 450 then
        -- Day (bright Mars)
        Environment.IsNight = false
        Environment.IsDustStorm = false
        targetAmbient = Environment.DayAmbient
        targetDiffuse = Environment.DayDiffuse
        targetFog = Environment.DayFog
    elseif progress < 550 then
        -- Sunset (100s transition - Mars orange/red)
        local t = (progress - 450) / 100
        Environment.IsNight = (t > 0.5)
        Environment.IsDustStorm = false
        -- Vibrant Mars sunset (purple-orange)
        local sunsetAmbient = { r = 0.15, g = 0.05, b = 0.15 }
        local sunsetDiffuse = { r = 1.0, g = 0.4, b = 0.1 }
        local sunsetFog = { r = 0.3, g = 0.1, b = 0.2, start = 30, ending = 300 }
        targetAmbient = LerpColor(Environment.DayAmbient, sunsetAmbient, t)
        targetDiffuse = LerpColor(Environment.DayDiffuse, sunsetDiffuse, t)
        targetFog = LerpFog(Environment.DayFog, sunsetFog, t)
    elseif progress < 850 then
        -- Night (dim red)
        Environment.IsNight = true
        Environment.IsDustStorm = false
        targetAmbient = Environment.NightAmbient
        targetDiffuse = Environment.NightDiffuse
        targetFog = Environment.NightFog
    else
        -- Sunrise (50s transition)
        local t = (progress - 850) / 50
        Environment.IsNight = (t < 0.5)
        Environment.IsDustStorm = false
        -- Sharp Mars sunrise (orange-gold)
        local sunriseAmbient = { r = 0.1, g = 0.1, b = 0.05 }
        local sunriseDiffuse = { r = 1.0, g = 0.6, b = 0.2 }
        local sunriseFog = { r = 0.4, g = 0.2, b = 0.1, start = 40, ending = 350 }
        targetAmbient = LerpColor(Environment.NightAmbient, sunriseAmbient, t)
        targetDiffuse = LerpColor(Environment.NightDiffuse, sunriseDiffuse, t)
        targetFog = LerpFog(Environment.NightFog, sunriseFog, t)
        if t > 0.5 then
            targetAmbient = LerpColor(sunriseAmbient, Environment.DayAmbient, (t - 0.5) * 2)
            targetDiffuse = LerpColor(sunriseDiffuse, Environment.DayDiffuse, (t - 0.5) * 2)
            targetFog = LerpFog(sunriseFog, Environment.DayFog, (t - 0.5) * 2)
        end
    end

    -- Handle Dust Storm Overlay
    local gravityChanged = false
    if Environment.DustStormTimer > 0 then
        Environment.DustStormTimer = Environment.DustStormTimer - timestep
        targetFog = Environment.DustStormFog
        Environment.IsDustStorm = true

        -- Throttle gravity updates to every 0.5 seconds
        if not Environment.LastGravity or (curTime - Environment.LastGravity) > 0.5 then
            local t = GetTime()
            local wobbleX = math.sin(t * 5.0) * 0.5
            local wobbleZ = math.cos(t * 4.3) * 0.5
            exu.SetGravity(wobbleX, -9.8, wobbleZ)
            Environment.LastGravity = curTime
            gravityChanged = true
        end
    elseif wasDustStorm and not Environment.IsDustStorm then
        -- Storm just ended, reset gravity
        exu.SetGravity(0, -9.8, 0)
        Environment.LastGravity = nil
        gravityChanged = true
    end

    -- Only update atmosphere if values changed (dirty flag check)
    local ambientChanged = not Environment.LastAmbient or
        targetAmbient.r ~= Environment.LastAmbient.r or
        targetAmbient.g ~= Environment.LastAmbient.g or
        targetAmbient.b ~= Environment.LastAmbient.b

    local diffuseChanged = not Environment.LastDiffuse or
        targetDiffuse.r ~= Environment.LastDiffuse.r or
        targetDiffuse.g ~= Environment.LastDiffuse.g or
        targetDiffuse.b ~= Environment.LastDiffuse.b

    local fogChanged = not Environment.LastFog or
        targetFog.r ~= Environment.LastFog.r or
        targetFog.g ~= Environment.LastFog.g or
        targetFog.b ~= Environment.LastFog.b or
        targetFog.start ~= Environment.LastFog.start or
        targetFog.ending ~= Environment.LastFog.ending

    if ambientChanged then
        exu.SetSunAmbient(targetAmbient.r, targetAmbient.g, targetAmbient.b)
        Environment.LastAmbient = { r = targetAmbient.r, g = targetAmbient.g, b = targetAmbient.b }
    end

    if diffuseChanged then
        exu.SetSunDiffuse(targetDiffuse.r, targetDiffuse.g, targetDiffuse.b)
        Environment.LastDiffuse = { r = targetDiffuse.r, g = targetDiffuse.g, b = targetDiffuse.b }
    end

    if fogChanged then
        exu.SetFog(targetFog.r, targetFog.g, targetFog.b, targetFog.start, targetFog.ending)
        Environment.LastFog = {
            r = targetFog.r,
            g = targetFog.g,
            b = targetFog.b,
            start = targetFog.start,
            ending =
                targetFog.ending
        }
    end

    -- Gameplay Impact: Radar and Stealth (only on night toggle)
    if Environment.IsNight ~= wasNight then
        Environment.SyncGameplayImpacts()
    end
end

function Environment.SyncGameplayImpacts()
    local count = 0
    local maxObjects = 200 -- Safety limit to prevent lag/crash
    for h in AllObjects() do
        if count >= maxObjects then break end
        Environment.ProcessObjectNightEffects(h)
        count = count + 1
    end
end

function Environment.ProcessObjectNightEffects(h)
    if not h or not IsValid(h) or not IsCraft(h) then return end

    -- Safety check for exu functions
    if not exu.SetRadarRange or not exu.SetRadarPeriod or not exu.SetVelocJam then return end

    if Environment.IsNight then
        -- Apply Radar Range Nerf
        local currentRange = exu.GetRadarRange(h)
        if currentRange and currentRange > 0 and not Environment.OriginalRadarRanges[h] then
            Environment.OriginalRadarRanges[h] = currentRange
            exu.SetRadarRange(h, currentRange * Environment.RadarRangeNerf)
        end

        -- Apply Radar Period Nerf (Slower)
        local currentPeriod = exu.GetRadarPeriod(h)
        if currentPeriod and currentPeriod > 0 and not Environment.OriginalRadarPeriods[h] then
            Environment.OriginalRadarPeriods[h] = currentPeriod
            exu.SetRadarPeriod(h, currentPeriod * Environment.RadarPeriodNerf)
        end

        -- Apply VelocJam Buff (Sneakier)
        local currentVelocJam = exu.GetVelocJam(h)
        if currentVelocJam and currentVelocJam > 0 and not Environment.OriginalVelocJams[h] then
            Environment.OriginalVelocJams[h] = currentVelocJam
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
            exu.SetVelocJam(h, Environment.OriginalVelocJams[h])
            Environment.OriginalVelocJams[h] = nil
        end
    end
end

function Environment.OnObjectCreated(h)
    if not h or not IsValid(h) then return end
    Environment.ProcessObjectNightEffects(h)
end

function Environment.TriggerDustStorm(duration)
    Environment.DustStormTimer = duration or 30
end

return Environment
