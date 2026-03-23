-- Environment.lua
-- Dynamic atmosphere system for Battlezone 98 Redux
-- Handles Day/Night cycles, time-of-day fog, and gameplay impacts.

local exu = require("exu")
local RuntimeEnhancements = require("RuntimeEnhancements")

-- =============================================================================
-- Lighting keyframe layout (progress = seconds into the 900s cycle):
--
--   0 ──────────── 450   500   550 ───────────── 850   875   900
--   |<─── Day ────>|<─Sunset─>|<───── Night ─────>|<─Sunrise─>|
--   D              D    SP    N                   N    SR      D
--
--   D  = DayAmbient / DayDiffuse        (white, 1.0 across the board)
--   SP = SunsetPeak                     (orange-amber)
--   N  = NightAmbient / NightDiffuse    (near-black blue tint)
--   SR = SunrisePeak                    (pink-gold)
--
-- Fog follows the same time-of-day rhythm:
--   clear by day, thicker and warmer at sunset, very thick and blue at night,
--   then cooler pink at sunrise before clearing again.
-- =============================================================================

Environment = {
    -- Cycle config
    CycleDuration        = 900, -- seconds (15 min)

    EnableSunLighting    = true,
    EnableVisualRuntime  = true,
    PresetMode           = "auto", -- "auto", "earth", or "moon"
    WorldPreset          = "earth",
    WorldPalette         = "",
    SunDirectionMode     = "ogre", -- "ogre" (safe default) or "legacy"
    NativeTimeOfDayOnInit = false, -- optional one-shot sync to EXU native time-of-day
    MapTimeOfDay         = 1200,
    DaySunPowerScale     = 1.15,
    NightSunPowerScale   = 0.22,
    DayShadowFarDistance = 900.0,
    NightShadowFarDistance = 220.0,

    -- Gameplay modifiers (night)
    RadarRangeNerf       = 0.7, -- 30% range reduction
    RadarPeriodNerf      = 2.0, -- 100% slower scan
    VelocJamBuff         = 1.5, -- 50% stealthier

    -- ── Lighting keyframes ────────────────────────────────────────────────────
    -- Day: standard neutral white
    DayAmbient           = { r = 0.5, g = 0.5, b = 0.5 },
    DayDiffuse           = { r = 0.5, g = 0.5, b = 0.5 },
    DaySpecular          = { r = 0.5, g = 0.5, b = 0.5 },
    -- Sunset peak (hit at progress = 500, midpoint of the 100s sunset window)
    SunsetAmbient        = { r = 0.46, g = 0.23, b = 0.12 },
    SunsetDiffuse        = { r = 1.00, g = 0.56, b = 0.18 },
    SunsetSpecular       = { r = 0.64, g = 0.30, b = 0.12 },
    -- Night: near-black with a faint blue tint
    NightAmbient         = { r = 0.02, g = 0.02, b = 0.05 },
    NightDiffuse         = { r = 0.08, g = 0.10, b = 0.18 },
    NightSpecular        = { r = 0.03, g = 0.04, b = 0.08 },
    -- Sunrise peak (hit at progress = 875, midpoint of the 50s sunrise window)
    SunriseAmbient       = { r = 0.30, g = 0.22, b = 0.30 },
    SunriseDiffuse       = { r = 0.98, g = 0.72, b = 0.64 },
    SunriseSpecular      = { r = 0.70, g = 0.46, b = 0.42 },

    -- ── Fog keyframes ─────────────────────────────────────────────────────────
    -- Day fog is overwritten from the map TRN at init time, then the other
    -- presets are derived from it to preserve each map's baseline feel.
    DayFog               = { r = 0.65, g = 0.45, b = 0.25, fogStart = 200, fogEnd = 700 },
    SunsetFog            = { r = 0.78, g = 0.58, b = 0.38, fogStart = 120, fogEnd = 460 },
    NightFog             = { r = 0.10, g = 0.12, b = 0.20, fogStart = 40, fogEnd = 220 },
    SunriseFog           = { r = 0.82, g = 0.66, b = 0.72, fogStart = 90, fogEnd = 400 },
    DustStormFog         = { r = 0.50, g = 0.30, b = 0.12, fogStart = 5, fogEnd = 45 },
    FogManualOverride    = nil,

    -- Night / gameplay state
    IsNight              = false,
    NightBlend           = 0, -- 0 = full day, 1 = full night (continuous)
    LastNightBlend       = -1,

    OriginalRadarRanges  = {},
    OriginalRadarPeriods = {},
    OriginalVelocJams    = {},
    CraftHandles         = {},
    CraftCursor          = 1,
    PendingGameplaySync  = false,
    GameplayBatchSize    = 32,
    GameplayRefreshAt    = 0.0,
    GameplayBatchAt      = 0.0,

    -- Dust storm (gravity wobble and heavy dust override)
    DustStormTimer       = 0,
    IsDustStorm          = false,
    LastGravity          = nil,

    -- Dirty-check caches
    LastAmbient          = nil,
    LastDiffuse          = nil,
    LastSpecular         = nil,
    LastFog              = nil,
    LastSunDirection     = nil,
    LastSunPowerScale    = nil,
    LastShadowFarDistance = nil,
    LastViewportShadows  = nil,

    DebugScale           = 1.0,
    Initialized          = false,
    LastPhase            = "Initial",
}

-- =============================================================================
-- Helpers
-- =============================================================================

local function Lerp(a, b, t)
    return a + (b - a) * t
end

local function LerpColor(c1, c2, t)
    return {
        r = Lerp(c1.r, c2.r, t),
        g = Lerp(c1.g, c2.g, t),
        b = Lerp(c1.b, c2.b, t),
    }
end

local function LerpFog(f1, f2, t)
    return {
        r        = Lerp(f1.r, f2.r, t),
        g        = Lerp(f1.g, f2.g, t),
        b        = Lerp(f1.b, f2.b, t),
        fogStart = Lerp(f1.fogStart, f2.fogStart, t),
        fogEnd   = Lerp(f1.fogEnd, f2.fogEnd, t),
    }
end

local function CopyFog(f)
    return { r = f.r, g = f.g, b = f.b, fogStart = f.fogStart, fogEnd = f.fogEnd }
end

local function CopyColor(c)
    return { r = c.r, g = c.g, b = c.b }
end

local function FogEqual(a, b)
    return a.r == b.r and a.g == b.g and a.b == b.b
        and a.fogStart == b.fogStart and a.fogEnd == b.fogEnd
end

local function FloatChanged(a, b, epsilon)
    return a == nil or b == nil or math.abs(a - b) > (epsilon or 0.001)
end

local function ColorChanged(a, b, epsilon)
    if not a or not b then
        return true
    end
    return FloatChanged(a.r, b.r, epsilon)
        or FloatChanged(a.g, b.g, epsilon)
        or FloatChanged(a.b, b.b, epsilon)
end

local function NormalizeDirection(direction)
    local length = math.sqrt((direction.x * direction.x) + (direction.y * direction.y) + (direction.z * direction.z))
    if length <= 0.0001 then
        return { x = 0.0, y = -1.0, z = 0.0 }
    end

    return {
        x = direction.x / length,
        y = direction.y / length,
        z = direction.z / length,
    }
end

local function GetSunDirectionSetter()
    if Environment.SunDirectionMode == "ogre" and exu.SetOgreSunDirection then
        return exu.SetOgreSunDirection
    end

    return exu.SetSunDirection
end

local function GetAmbientLightSetter()
    return exu.SetAmbientLight or exu.SetSunAmbient
end

local function Clamp01(value)
    return math.max(0.0, math.min(1.0, value))
end

local function ClampColor(color)
    return {
        r = Clamp01(color.r),
        g = Clamp01(color.g),
        b = Clamp01(color.b),
    }
end

local function ModulateColor(base, tint, scale)
    local appliedScale = scale or 1.0
    return ClampColor({
        r = base.r * tint.r * appliedScale,
        g = base.g * tint.g * appliedScale,
        b = base.b * tint.b * appliedScale,
    })
end

local function ClampFog(fog)
    local start = math.max(1.0, fog.fogStart)
    local ending = math.max(start + 1.0, fog.fogEnd)
    return {
        r = Clamp01(fog.r),
        g = Clamp01(fog.g),
        b = Clamp01(fog.b),
        fogStart = start,
        fogEnd = ending,
    }
end

local function StringContainsAny(value, needles)
    if not value or value == "" then
        return false
    end

    local lower = string.lower(value)
    for _, needle in ipairs(needles) do
        if string.find(lower, needle, 1, true) then
            return true
        end
    end

    return false
end

local function DetectWorldPreset(trnFilename, trn)
    local presetMode = string.lower(Environment.PresetMode or "auto")
    if presetMode ~= "auto" then
        return presetMode, presetMode
    end

    local palette = ""
    if trn and GetODFString then
        palette = string.lower(GetODFString(trn, "Color", "Palette", "") or "")
    end

    local missionFilename = ""
    if GetMissionFilename then
        missionFilename = string.lower((GetMissionFilename() or ""):gsub("%z.*", ""))
    end

    local moonHints = {
        "moon",
        "luna",
        "europa",
        "io",
        "selene",
        "apollo",
        "misn02b",
        "misn03",
    }

    if StringContainsAny(palette, moonHints)
        or StringContainsAny(trnFilename, moonHints)
        or StringContainsAny(missionFilename, moonHints)
    then
        return "moon", palette
    end

    return "earth", palette
end

local function BuildEarthFogKeyframes(baseFog)
    local warmSunsetTint = { r = 0.92, g = 0.58, b = 0.34 }
    local coolNightTint = { r = 0.10, g = 0.12, b = 0.20 }
    local pinkSunriseTint = { r = 0.88, g = 0.68, b = 0.74 }
    local dayColor = { r = baseFog.r, g = baseFog.g, b = baseFog.b }

    Environment.DayFog = CopyFog(baseFog)
    Environment.SunsetFog = ClampFog({
        r = Lerp(dayColor.r, warmSunsetTint.r, 0.38),
        g = Lerp(dayColor.g, warmSunsetTint.g, 0.38),
        b = Lerp(dayColor.b, warmSunsetTint.b, 0.38),
        fogStart = baseFog.fogStart * 0.62,
        fogEnd = baseFog.fogEnd * 0.72,
    })
    Environment.NightFog = ClampFog({
        r = Lerp(dayColor.r, coolNightTint.r, 0.82),
        g = Lerp(dayColor.g, coolNightTint.g, 0.82),
        b = Lerp(dayColor.b, coolNightTint.b, 0.82),
        fogStart = baseFog.fogStart * 0.22,
        fogEnd = baseFog.fogEnd * 0.36,
    })
    Environment.SunriseFog = ClampFog({
        r = Lerp(dayColor.r, pinkSunriseTint.r, 0.48),
        g = Lerp(dayColor.g, pinkSunriseTint.g, 0.48),
        b = Lerp(dayColor.b, pinkSunriseTint.b, 0.48),
        fogStart = baseFog.fogStart * 0.54,
        fogEnd = baseFog.fogEnd * 0.66,
    })
end

local function BuildMoonFogKeyframes(baseFog)
    local dayTint = { r = 0.50, g = 0.52, b = 0.58 }
    local duskTint = { r = 0.46, g = 0.45, b = 0.56 }
    local nightTint = { r = 0.15, g = 0.17, b = 0.24 }
    local dawnTint = { r = 0.54, g = 0.50, b = 0.62 }
    local dayStart = math.max(baseFog.fogStart * 1.75, 420.0)
    local dayEnd = math.max(baseFog.fogEnd * 2.10, dayStart + 700.0)

    Environment.DayFog = ClampFog({
        r = Lerp(baseFog.r, dayTint.r, 0.82),
        g = Lerp(baseFog.g, dayTint.g, 0.82),
        b = Lerp(baseFog.b, dayTint.b, 0.82),
        fogStart = dayStart,
        fogEnd = dayEnd,
    })
    Environment.SunsetFog = ClampFog({
        r = duskTint.r,
        g = duskTint.g,
        b = duskTint.b,
        fogStart = dayStart * 0.90,
        fogEnd = dayEnd * 0.92,
    })
    Environment.NightFog = ClampFog({
        r = nightTint.r,
        g = nightTint.g,
        b = nightTint.b,
        fogStart = dayStart * 0.62,
        fogEnd = dayEnd * 0.68,
    })
    Environment.SunriseFog = ClampFog({
        r = dawnTint.r,
        g = dawnTint.g,
        b = dawnTint.b,
        fogStart = dayStart * 0.86,
        fogEnd = dayEnd * 0.88,
    })
end

local function ApplyWorldPreset(presetName, baseAmbient, baseDiffuse, baseSpecular, baseFog)
    if presetName == "moon" then
        Environment.DayAmbient = ModulateColor(baseAmbient, { r = 0.64, g = 0.68, b = 0.82 }, 0.70)
        Environment.DayDiffuse = ModulateColor(baseDiffuse, { r = 1.20, g = 1.16, b = 1.08 }, 1.00)
        Environment.DaySpecular = ModulateColor(baseSpecular, { r = 1.30, g = 1.26, b = 1.18 }, 1.08)

        Environment.SunsetAmbient = ModulateColor(baseAmbient, { r = 0.34, g = 0.36, b = 0.46 }, 0.62)
        Environment.SunsetDiffuse = ModulateColor(baseDiffuse, { r = 0.74, g = 0.78, b = 0.90 }, 0.82)
        Environment.SunsetSpecular = ModulateColor(baseSpecular, { r = 0.86, g = 0.88, b = 0.96 }, 0.86)

        Environment.NightAmbient = { r = 0.01, g = 0.012, b = 0.030 }
        Environment.NightDiffuse = { r = 0.04, g = 0.06, b = 0.11 }
        Environment.NightSpecular = { r = 0.02, g = 0.03, b = 0.06 }

        Environment.SunriseAmbient = ModulateColor(baseAmbient, { r = 0.44, g = 0.40, b = 0.52 }, 0.84)
        Environment.SunriseDiffuse = ModulateColor(baseDiffuse, { r = 0.88, g = 0.82, b = 0.94 }, 0.92)
        Environment.SunriseSpecular = ModulateColor(baseSpecular, { r = 0.96, g = 0.92, b = 1.00 }, 0.94)

        Environment.DaySunPowerScale = 1.32
        Environment.NightSunPowerScale = 0.10
        Environment.DayShadowFarDistance = 1150.0
        Environment.NightShadowFarDistance = 260.0

        BuildMoonFogKeyframes(baseFog)
        return
    end

    Environment.DayAmbient = CopyColor(baseAmbient)
    Environment.DayDiffuse = CopyColor(baseDiffuse)
    Environment.DaySpecular = CopyColor(baseSpecular)

    Environment.SunsetAmbient = { r = 0.46, g = 0.23, b = 0.12 }
    Environment.SunsetDiffuse = { r = 1.00, g = 0.56, b = 0.18 }
    Environment.SunsetSpecular = { r = 0.64, g = 0.30, b = 0.12 }

    Environment.NightAmbient = { r = 0.02, g = 0.02, b = 0.05 }
    Environment.NightDiffuse = { r = 0.08, g = 0.10, b = 0.18 }
    Environment.NightSpecular = { r = 0.03, g = 0.04, b = 0.08 }

    Environment.SunriseAmbient = { r = 0.30, g = 0.22, b = 0.30 }
    Environment.SunriseDiffuse = { r = 0.98, g = 0.72, b = 0.64 }
    Environment.SunriseSpecular = { r = 0.70, g = 0.46, b = 0.42 }

    Environment.DaySunPowerScale = 1.15
    Environment.NightSunPowerScale = 0.22
    Environment.DayShadowFarDistance = 900.0
    Environment.NightShadowFarDistance = 220.0

    BuildEarthFogKeyframes(baseFog)
end

local function ComputeNightBlend(progress)
    if progress < 450 then
        return 0
    elseif progress < 550 then
        return (progress - 450) / 100
    elseif progress < 850 then
        return 1
    end

    return 1 - (progress - 850) / 50
end

-- =============================================================================
-- Init
-- =============================================================================

function Environment.Init()
    RuntimeEnhancements.Initialize()

    local trnFilename = nil
    local trn = nil
    local baseAmbient = CopyColor(Environment.DayAmbient)
    local baseDiffuse = CopyColor(Environment.DayDiffuse)
    local baseSpecular = CopyColor(Environment.DaySpecular)
    local baseFog = CopyFog(Environment.DayFog)

    -- Read map TRN for the "clear" fog baseline
    if GetMapTRNFilename then
        trnFilename = GetMapTRNFilename()
        if trnFilename and trnFilename ~= "" then
            trn = OpenODF(trnFilename)
            if trn then
                local intensity              = GetODFInt(trn, "NormalView", "Intensity", 128) / 255
                local ambient                = GetODFInt(trn, "NormalView", "Ambient", 96) / 255
                local fogStart               = GetODFFloat(trn, "NormalView", "FogStart", 200)
                local fogEnd                 = GetODFFloat(trn, "NormalView", "FogEnd", 700)
                Environment.MapTimeOfDay     = GetODFInt(trn, "NormalView", "Time", Environment.MapTimeOfDay)
                -- Use TRN fog colour if present, otherwise keep the warm-dust default
                local fr                     = GetODFFloat(trn, "NormalView", "FogColorR", 0.65)
                local fg                     = GetODFFloat(trn, "NormalView", "FogColorG", 0.45)
                local fb                     = GetODFFloat(trn, "NormalView", "FogColorB", 0.25)
                local specular               = Clamp01((intensity * 0.85) + 0.10)
                baseAmbient                  = { r = ambient, g = ambient, b = ambient }
                baseDiffuse                  = { r = intensity, g = intensity, b = intensity }
                baseSpecular                 = { r = specular, g = specular, b = Clamp01(specular * 0.98) }
                baseFog = {
                    r = fr,
                    g = fg,
                    b = fb,
                    fogStart = fogStart,
                    fogEnd = fogEnd,
                }
                print("Environment: TRN loaded – time=" .. tostring(Environment.MapTimeOfDay) .. " fogStart=" .. fogStart .. " fogEnd=" .. fogEnd)
            end
        end
    end

    Environment.WorldPreset, Environment.WorldPalette = DetectWorldPreset(trnFilename, trn)
    ApplyWorldPreset(Environment.WorldPreset, baseAmbient, baseDiffuse, baseSpecular, baseFog)
    print("Environment: Preset -> [" .. Environment.WorldPreset .. "] palette=" .. tostring(Environment.WorldPalette))

    if Environment.NativeTimeOfDayOnInit and exu.SetTimeOfDay then
        exu.SetTimeOfDay(Environment.MapTimeOfDay)
    end

    Environment.CraftHandles   = {}
    Environment.CraftCursor    = 1
    Environment.PendingGameplaySync = true
    Environment.GameplayRefreshAt = 0.0
    Environment.GameplayBatchAt = 0.0

    Environment.Initialized    = true
    print("Environment: Initialized")
end

-- =============================================================================
-- Lighting – keyframe interpolation across the day/night cycle
-- =============================================================================
--
-- Progress windows:
--   0   – 450  : Day (constant)
--   450 – 500  : Day  → SunsetPeak    (t = (p-450)/50)
--   500 – 550  : SunsetPeak → Night   (t = (p-500)/50)
--   550 – 850  : Night (constant)
--   850 – 875  : Night → SunrisePeak  (t = (p-850)/25)
--   875 – 900  : SunrisePeak → Day    (t = (p-875)/25)

local function ComputeLighting(progress)
    local E = Environment
    local ambient, diffuse

    local specular

    if progress < 450 then
        ambient  = E.DayAmbient
        diffuse  = E.DayDiffuse
        specular = E.DaySpecular
    elseif progress < 500 then
        local t  = (progress - 450) / 50
        ambient  = LerpColor(E.DayAmbient, E.SunsetAmbient, t)
        diffuse  = LerpColor(E.DayDiffuse, E.SunsetDiffuse, t)
        specular = LerpColor(E.DaySpecular, E.SunsetSpecular, t)
    elseif progress < 550 then
        local t  = (progress - 500) / 50
        ambient  = LerpColor(E.SunsetAmbient, E.NightAmbient, t)
        diffuse  = LerpColor(E.SunsetDiffuse, E.NightDiffuse, t)
        specular = LerpColor(E.SunsetSpecular, E.NightSpecular, t)
    elseif progress < 850 then
        ambient  = E.NightAmbient
        diffuse  = E.NightDiffuse
        specular = E.NightSpecular
    elseif progress < 875 then
        local t  = (progress - 850) / 25
        ambient  = LerpColor(E.NightAmbient, E.SunriseAmbient, t)
        diffuse  = LerpColor(E.NightDiffuse, E.SunriseDiffuse, t)
        specular = LerpColor(E.NightSpecular, E.SunriseSpecular, t)
    else
        local t  = (progress - 875) / 25
        ambient  = LerpColor(E.SunriseAmbient, E.DayAmbient, t)
        diffuse  = LerpColor(E.SunriseDiffuse, E.DayDiffuse, t)
        specular = LerpColor(E.SunriseSpecular, E.DaySpecular, t)
    end

    return ambient, diffuse, specular
end

local function ComputeSunState(progress, nightBlend)
    local cycle = progress / Environment.CycleDuration
    local sunAngle = (cycle * math.pi * 2.0) - (math.pi * 0.5)
    local elevation = math.max(0.0, math.sin(sunAngle))
    local horizon = math.cos(sunAngle)
    local daylight = 1.0 - nightBlend

    if nightBlend <= 0.02 then
        return {
            direction = NormalizeDirection({ x = 0.62, y = -0.73, z = -0.29 }),
            powerScale = Environment.DaySunPowerScale,
            shadowFarDistance = Environment.DayShadowFarDistance,
            viewportShadows = true,
        }
    end

    if nightBlend >= 0.98 then
        return {
            direction = NormalizeDirection({ x = -0.18, y = -0.42, z = -0.89 }),
            powerScale = Environment.NightSunPowerScale,
            shadowFarDistance = Environment.NightShadowFarDistance,
            viewportShadows = false,
        }
    end

    local direction = NormalizeDirection({
        x = (horizon * 0.65) + 0.18,
        y = -((0.18 * (1.0 - daylight)) + (0.95 * elevation) + (0.12 * daylight)),
        z = -0.30 + (horizon * 0.20),
    })

    local lightFactor = math.min(1.0, (daylight * 0.6) + (elevation * 0.4))
    local shadowFactor = math.min(1.0, (daylight * 0.45) + (elevation * 0.55))

    return {
        direction = direction,
        powerScale = Lerp(Environment.NightSunPowerScale, Environment.DaySunPowerScale, lightFactor),
        shadowFarDistance = Lerp(Environment.NightShadowFarDistance, Environment.DayShadowFarDistance, shadowFactor),
        viewportShadows = daylight > 0.10,
    }
end

-- =============================================================================
-- Fog – keyed to time of day
-- =============================================================================

local function ComputeFog(progress)
    local E = Environment

    if progress < 450 then
        return CopyFog(E.DayFog)
    elseif progress < 500 then
        return LerpFog(E.DayFog, E.SunsetFog, (progress - 450) / 50)
    elseif progress < 550 then
        return LerpFog(E.SunsetFog, E.NightFog, (progress - 500) / 50)
    elseif progress < 850 then
        return CopyFog(E.NightFog)
    elseif progress < 875 then
        return LerpFog(E.NightFog, E.SunriseFog, (progress - 850) / 25)
    end

    return LerpFog(E.SunriseFog, E.DayFog, (progress - 875) / 25)
end

-- =============================================================================
-- Main Update
-- =============================================================================

function Environment.Update(timestep)
    if not Environment.Initialized then
        Environment.Init()
    end

    local curTime = GetTime() * Environment.DebugScale
    local progress = curTime % Environment.CycleDuration

    -- ── Phase label (for HUD/log) ─────────────────────────────────────────
    local currentPhase
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
        local msg = "Environment: Phase → [" .. currentPhase .. "]"
        print(msg)
        if AddTMsg then AddTMsg(msg) end
        Environment.LastPhase = currentPhase
    end

    local nightBlend = ComputeNightBlend(progress)
    Environment.IsNight    = (nightBlend > 0.5)
    Environment.NightBlend = nightBlend

    -- ── Lighting ──────────────────────────────────────────────────────────
    local targetAmbient, targetDiffuse, targetSpecular = ComputeLighting(progress)
    local targetFog = ComputeFog(progress)
    local setAmbientLight = GetAmbientLightSetter()

    -- ── Fog / dust storm override ─────────────────────────────────────────
    local wasDustStorm = Environment.IsDustStorm
    local isDustStorm = (Environment.DustStormTimer > 0)
    Environment.IsDustStorm = isDustStorm
    if Environment.FogManualOverride then
        targetFog = CopyFog(Environment.FogManualOverride)
    end

    -- ── Dust storm gravity wobble ─────────────────────────────────────────
    if Environment.DustStormTimer > 0 then
        Environment.DustStormTimer = Environment.DustStormTimer - timestep
        targetFog = CopyFog(Environment.DustStormFog)
        if not Environment.LastGravity or (curTime - Environment.LastGravity) > 0.5 then
            local t    = GetTime()
            local wobX = math.sin(t * 5.0) * 0.5
            local wobZ = math.cos(t * 4.3) * 0.5
            exu.SetGravity(wobX, -9.8, wobZ)
            Environment.LastGravity = curTime
        end
    elseif wasDustStorm and not Environment.IsDustStorm then
        exu.SetGravity(0, -9.8, 0)
        Environment.LastGravity = nil
    end

    -- ── Apply atmosphere (dirty-check to avoid redundant API calls) ────────
    if Environment.EnableSunLighting then
        local lastA = Environment.LastAmbient
        if setAmbientLight and (not lastA
            or targetAmbient.r ~= lastA.r
            or targetAmbient.g ~= lastA.g
            or targetAmbient.b ~= lastA.b)
        then
            setAmbientLight(targetAmbient.r, targetAmbient.g, targetAmbient.b)
            Environment.LastAmbient = { r = targetAmbient.r, g = targetAmbient.g, b = targetAmbient.b }
        end

        local lastD = Environment.LastDiffuse
        if exu.SetSunDiffuse and (not lastD
            or targetDiffuse.r ~= lastD.r
            or targetDiffuse.g ~= lastD.g
            or targetDiffuse.b ~= lastD.b)
        then
            exu.SetSunDiffuse(targetDiffuse.r, targetDiffuse.g, targetDiffuse.b)
            Environment.LastDiffuse = { r = targetDiffuse.r, g = targetDiffuse.g, b = targetDiffuse.b }
        end

        local lastS = Environment.LastSpecular
        if exu.SetSunSpecular and (not lastS
            or targetSpecular.r ~= lastS.r
            or targetSpecular.g ~= lastS.g
            or targetSpecular.b ~= lastS.b)
        then
            exu.SetSunSpecular(targetSpecular.r, targetSpecular.g, targetSpecular.b)
            Environment.LastSpecular = { r = targetSpecular.r, g = targetSpecular.g, b = targetSpecular.b }
        end
    end

    local lastF = Environment.LastFog
    if not lastF or not FogEqual(targetFog, lastF) then
        exu.SetFog(targetFog.r, targetFog.g, targetFog.b, targetFog.fogStart, targetFog.fogEnd)
        Environment.LastFog = CopyFog(targetFog)
    end

    if math.abs(nightBlend - Environment.LastNightBlend) > 0.02 then
        Environment.PendingGameplaySync = true
        Environment.LastNightBlend = nightBlend
    end

    if Environment.PendingGameplaySync then
        Environment.SyncGameplayImpacts()
    end

    if Environment.EnableVisualRuntime then
        RuntimeEnhancements.Update(timestep)
    end

    local sunState = ComputeSunState(progress, nightBlend)
    local setSunDirection = GetSunDirectionSetter()

    if Environment.EnableSunLighting then
        if setSunDirection and (not Environment.LastSunDirection
                or ColorChanged(
                    { r = sunState.direction.x, g = sunState.direction.y, b = sunState.direction.z },
                    { r = Environment.LastSunDirection.x, g = Environment.LastSunDirection.y, b = Environment.LastSunDirection.z },
                    0.002))
        then
            setSunDirection(sunState.direction.x, sunState.direction.y, sunState.direction.z)
            Environment.LastSunDirection = {
                x = sunState.direction.x,
                y = sunState.direction.y,
                z = sunState.direction.z,
            }
        end

        if exu.SetSunPowerScale and FloatChanged(Environment.LastSunPowerScale, sunState.powerScale, 0.002) then
            exu.SetSunPowerScale(sunState.powerScale)
            Environment.LastSunPowerScale = sunState.powerScale
        end

        if exu.SetSunShadowFarDistance and FloatChanged(Environment.LastShadowFarDistance, sunState.shadowFarDistance, 0.5) then
            exu.SetSunShadowFarDistance(sunState.shadowFarDistance)
            Environment.LastShadowFarDistance = sunState.shadowFarDistance
        end

        if exu.SetViewportShadowsEnabled and Environment.LastViewportShadows ~= sunState.viewportShadows then
            exu.SetViewportShadowsEnabled(sunState.viewportShadows)
            Environment.LastViewportShadows = sunState.viewportShadows
        end
    end
end

-- =============================================================================
-- Gameplay impacts (radar / stealth, lerped by NightBlend)
-- =============================================================================

function Environment.SyncGameplayImpacts()
    local now = GetTime()
    if now >= (Environment.GameplayRefreshAt or 0.0) or not Environment.CraftHandles or #Environment.CraftHandles == 0 then
        local craftHandles = {}
        for h in AllCraft() do
            craftHandles[#craftHandles + 1] = h
        end
        Environment.CraftHandles = craftHandles
        Environment.CraftCursor = 1
        Environment.GameplayRefreshAt = now + 2.0
    end

    if now < (Environment.GameplayBatchAt or 0.0) then
        return
    end
    Environment.GameplayBatchAt = now + 0.05

    local craftHandles = Environment.CraftHandles or {}
    local count = 0
    local cursor = Environment.CraftCursor or 1

    while cursor <= #craftHandles and count < (Environment.GameplayBatchSize or 32) do
        Environment.ProcessObjectNightEffects(craftHandles[cursor])
        cursor = cursor + 1
        count = count + 1
    end

    if cursor > #craftHandles then
        Environment.CraftCursor = 1
        Environment.PendingGameplaySync = false
    else
        Environment.CraftCursor = cursor
    end
end

function Environment.ProcessObjectNightEffects(h)
    if not h or not IsValid(h) then return end
    if not exu.SetRadarRange or not exu.SetRadarPeriod or not exu.SetVelocJam then return end

    local blend = Environment.NightBlend

    -- Snapshot originals on first encounter during a non-day period
    if blend > 0 then
        local rng = exu.GetRadarRange(h)
        if rng and rng > 0 and not Environment.OriginalRadarRanges[h] then
            Environment.OriginalRadarRanges[h] = rng
        end
        local per = exu.GetRadarPeriod(h)
        if per and per > 0 and not Environment.OriginalRadarPeriods[h] then
            Environment.OriginalRadarPeriods[h] = per
        end
        local vj = exu.GetVelocJam(h)
        if vj and vj > 0 and not Environment.OriginalVelocJams[h] then
            Environment.OriginalVelocJams[h] = vj
        end
    end

    -- Apply blended values
    if Environment.OriginalRadarRanges[h] then
        exu.SetRadarRange(h, Environment.OriginalRadarRanges[h] * Lerp(1, Environment.RadarRangeNerf, blend))
    end
    if Environment.OriginalRadarPeriods[h] then
        exu.SetRadarPeriod(h, Environment.OriginalRadarPeriods[h] * Lerp(1, Environment.RadarPeriodNerf, blend))
    end
    if Environment.OriginalVelocJams[h] then
        exu.SetVelocJam(h, Environment.OriginalVelocJams[h] * Lerp(1, Environment.VelocJamBuff, blend))
    end

    -- Clear snapshots once fully back to day
    if blend == 0 then
        Environment.OriginalRadarRanges[h]  = nil
        Environment.OriginalRadarPeriods[h] = nil
        Environment.OriginalVelocJams[h]    = nil
    end
end

function Environment.OnObjectCreated(h)
    if not h or not IsValid(h) then return end
    if IsCraft(h) then
        Environment.CraftHandles = Environment.CraftHandles or {}
        Environment.CraftHandles[#Environment.CraftHandles + 1] = h
        Environment.PendingGameplaySync = true
    end
    RuntimeEnhancements.OnObjectCreated(h)
    Environment.ProcessObjectNightEffects(h)
end

-- =============================================================================
-- External triggers
-- =============================================================================

-- Start a dust storm (gravity wobble + dust fog override) for `duration` seconds
function Environment.TriggerDustStorm(duration)
    Environment.DustStormTimer = duration or 30
    print("Environment: Dust storm triggered for " .. Environment.DustStormTimer .. "s")
end

-- Force a fog preset override ("day","sunset","night","sunrise","dust"), or
-- pass "auto" / nil to resume the normal time-of-day fog curve.
function Environment.SetFogState(stateName, blendDuration)
    local _ = blendDuration
    if stateName == nil or stateName == "auto" then
        Environment.FogManualOverride = nil
        Environment.LastFog = nil
        return
    end

    local normalized = string.lower(tostring(stateName))
    local presets = {
        clear = Environment.DayFog,
        day = Environment.DayFog,
        sunset = Environment.SunsetFog,
        dusk = Environment.SunsetFog,
        night = Environment.NightFog,
        sunrise = Environment.SunriseFog,
        dawn = Environment.SunriseFog,
        dust = Environment.DustStormFog,
    }
    local preset = presets[normalized]
    if not preset then
        print("Environment: Unknown fog state '" .. tostring(stateName) .. "'")
        return
    end
    Environment.FogManualOverride = CopyFog(preset)
    Environment.LastFog = nil
end

return Environment
