-- Environment.lua
-- Smooth dynamic atmosphere system for Battlezone 98 Redux.
--
-- Design goals:
--   * Continuous dusk/dawn with no hard lighting or sun-direction snaps.
--   * Stable PSSM configuration: viewport shadows stay enabled and shadow range
--     remains fixed for the active world preset.
--   * One shared cycle state drives lighting, fog, sun power, sun direction, and
--     gameplay night effects so the environment cannot drift out of sync.
--   * TRN-derived map baselines and Earth/Moon visual presets remain supported.
--   * Existing public entry points are preserved for mission compatibility.

local exu = require("exu")
local RuntimeEnhancements = require("RuntimeEnhancements")

Environment = {
    -- -------------------------------------------------------------------------
    -- Cycle configuration
    -- -------------------------------------------------------------------------
    -- Default remains 15 minutes so existing mission pacing is preserved.
    -- The phase fractions below produce approximately:
    --   Day   : 0:00 - 6:00
    --   Dusk  : 6:00 - 9:00
    --   Night : 9:00 - 13:00
    --   Dawn  : 13:00 - 15:00
    -- Set CycleDuration = 1200 for the same proportions over a 20 minute cycle.
    CycleDuration          = 900.0,
    DuskStartFraction      = 0.40,
    NightStartFraction     = 0.60,
    DawnStartFraction      = 13.0 / 15.0,

    EnableSunLighting      = true,
    EnableVisualRuntime    = true,
    PresetMode             = "auto", -- "auto", "earth", or "moon"
    WorldPreset            = "earth",
    WorldPalette           = "",
    SunDirectionMode       = "ogre", -- "ogre" preferred; "legacy" fallback
    NativeTimeOfDayOnInit  = false,
    MapTimeOfDay           = 1200,

    -- Keep the directional-light/shadow pipeline stable throughout the cycle.
    -- Night is made visually dark through light color/power, not by rebuilding
    -- the viewport shadow configuration.
    KeepViewportShadowsEnabled = true,
    DayShadowFarDistance   = 900.0,
    NightShadowFarDistance = 220.0, -- retained for compatibility; not animated
    StableShadowFarDistance = 900.0,

    DaySunPowerScale       = 1.15,
    NightSunPowerScale     = 0.16,

    -- Direction keyframes. Full day and full night are intentionally stable;
    -- only dusk/dawn animate the directional light. This minimizes PSSM crawl.
    DaySunDirection        = { x = 0.62, y = -0.73, z = -0.29 },
    SunsetSunDirection     = { x = -0.92, y = -0.18, z = -0.34 },
    NightSunDirection      = { x = -0.18, y = -0.42, z = -0.89 },
    SunriseSunDirection    = { x = 0.92, y = -0.18, z = -0.34 },

    -- Accent strength controls how strongly the twilight target colors pull
    -- the underlying day<->night blend toward sunset/sunrise coloration.
    SunsetAccentStrength   = 0.58,
    SunriseAccentStrength  = 0.48,
    SunsetFogAccentStrength = 0.55,
    SunriseFogAccentStrength = 0.48,

    -- -------------------------------------------------------------------------
    -- Gameplay modifiers at full night
    -- -------------------------------------------------------------------------
    RadarRangeNerf         = 0.70,
    RadarPeriodNerf        = 2.00,
    VelocJamBuff           = 1.50,

    -- -------------------------------------------------------------------------
    -- Lighting presets
    -- Day values are replaced from the map TRN at initialization where possible.
    -- Sunset/Sunrise values are accent targets, not mandatory hard keyframes.
    -- -------------------------------------------------------------------------
    DayAmbient             = { r = 0.50, g = 0.50, b = 0.50 },
    DayDiffuse             = { r = 0.50, g = 0.50, b = 0.50 },
    DaySpecular            = { r = 0.50, g = 0.50, b = 0.50 },

    SunsetAmbient          = { r = 0.46, g = 0.23, b = 0.12 },
    SunsetDiffuse          = { r = 1.00, g = 0.56, b = 0.18 },
    SunsetSpecular         = { r = 0.64, g = 0.30, b = 0.12 },

    NightAmbient           = { r = 0.02, g = 0.02, b = 0.05 },
    NightDiffuse           = { r = 0.08, g = 0.10, b = 0.18 },
    NightSpecular          = { r = 0.03, g = 0.04, b = 0.08 },

    SunriseAmbient         = { r = 0.30, g = 0.22, b = 0.30 },
    SunriseDiffuse         = { r = 0.98, g = 0.72, b = 0.64 },
    SunriseSpecular        = { r = 0.70, g = 0.46, b = 0.42 },

    -- -------------------------------------------------------------------------
    -- Fog presets
    -- -------------------------------------------------------------------------
    DayFog                 = { r = 0.65, g = 0.45, b = 0.25, fogStart = 200, fogEnd = 700 },
    SunsetFog              = { r = 0.78, g = 0.58, b = 0.38, fogStart = 120, fogEnd = 460 },
    NightFog               = { r = 0.10, g = 0.12, b = 0.20, fogStart = 40, fogEnd = 220 },
    SunriseFog             = { r = 0.82, g = 0.66, b = 0.72, fogStart = 90, fogEnd = 400 },
    DustStormFog           = { r = 0.50, g = 0.30, b = 0.12, fogStart = 5, fogEnd = 45 },

    -- Public compatibility field. When non-nil this is the fixed target preset.
    FogManualOverride      = nil,
    FogTransition          = nil,

    -- -------------------------------------------------------------------------
    -- Runtime state
    -- -------------------------------------------------------------------------
    IsNight                = false,
    NightBlend             = 0.0,
    LastNightBlend         = -1.0,

    OriginalRadarRanges    = {},
    OriginalRadarPeriods   = {},
    OriginalVelocJams      = {},
    CraftHandles           = {},
    CraftCursor            = 1,
    PendingGameplaySync    = false,
    GameplayBatchSize      = 32,
    GameplayRefreshAt      = 0.0,
    GameplayBatchAt        = 0.0,

    DustStormTimer         = 0.0,
    IsDustStorm            = false,
    LastGravity            = nil,

    -- Dirty-check caches.
    LastAmbient            = nil,
    LastDiffuse            = nil,
    LastSpecular           = nil,
    LastFog                = nil,
    LastSunDirection       = nil,
    LastSunPowerScale      = nil,
    LastShadowFarDistance  = nil,
    LastViewportShadows    = nil,

    DebugScale             = 1.0,
    Initialized            = false,
    LastPhase              = "Initial",
}

-- =============================================================================
-- Scalar / color / fog helpers
-- =============================================================================

local function Clamp01(value)
    return math.max(0.0, math.min(1.0, value or 0.0))
end

local function Lerp(a, b, t)
    return a + (b - a) * t
end

local function InverseLerp(a, b, value)
    local span = b - a
    if math.abs(span) <= 0.000001 then
        return 0.0
    end
    return Clamp01((value - a) / span)
end

-- Zero first and second derivative at both ends. This removes the mechanical
-- "start moving / stop moving" look of linear atmosphere transitions.
local function SmootherStep(t)
    t = Clamp01(t)
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
end

-- Smooth 0 -> 1 -> 0 pulse used for sunset/sunrise accent overlays.
local function SmoothBell(t)
    t = Clamp01(t)
    if t <= 0.5 then
        return SmootherStep(t * 2.0)
    end
    return SmootherStep((1.0 - t) * 2.0)
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
    return {
        r = f.r,
        g = f.g,
        b = f.b,
        fogStart = f.fogStart,
        fogEnd = f.fogEnd,
    }
end

local function CopyColor(c)
    return { r = c.r, g = c.g, b = c.b }
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

local function FogChanged(a, b, colorEpsilon, distanceEpsilon)
    if not a or not b then
        return true
    end

    local ce = colorEpsilon or 0.00035
    local de = distanceEpsilon or 0.25
    return FloatChanged(a.r, b.r, ce)
        or FloatChanged(a.g, b.g, ce)
        or FloatChanged(a.b, b.b, ce)
        or FloatChanged(a.fogStart, b.fogStart, de)
        or FloatChanged(a.fogEnd, b.fogEnd, de)
end

local function NormalizeDirection(direction)
    local length = math.sqrt(
        (direction.x * direction.x)
        + (direction.y * direction.y)
        + (direction.z * direction.z)
    )

    if length <= 0.0001 then
        return { x = 0.0, y = -1.0, z = 0.0 }
    end

    return {
        x = direction.x / length,
        y = direction.y / length,
        z = direction.z / length,
    }
end

local function LerpDirection(a, b, t)
    return NormalizeDirection({
        x = Lerp(a.x, b.x, t),
        y = Lerp(a.y, b.y, t),
        z = Lerp(a.z, b.z, t),
    })
end

local function DirectionChanged(a, b, epsilon)
    if not a or not b then
        return true
    end

    local e = epsilon or 0.0005
    return FloatChanged(a.x, b.x, e)
        or FloatChanged(a.y, b.y, e)
        or FloatChanged(a.z, b.z, e)
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

local function GetSunDirectionSetter()
    if Environment.SunDirectionMode == "ogre" and exu.SetOgreSunDirection then
        return exu.SetOgreSunDirection
    end
    return exu.SetSunDirection
end

local function GetAmbientLightSetter()
    return exu.SetAmbientLight or exu.SetSunAmbient
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

-- =============================================================================
-- World-preset setup
-- =============================================================================

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
    local coolNightTint  = { r = 0.10, g = 0.12, b = 0.20 }
    local pinkSunriseTint = { r = 0.88, g = 0.68, b = 0.74 }
    local dayColor = { r = baseFog.r, g = baseFog.g, b = baseFog.b }

    Environment.DayFog = CopyFog(baseFog)
    Environment.SunsetFog = ClampFog({
        r = Lerp(dayColor.r, warmSunsetTint.r, 0.38),
        g = Lerp(dayColor.g, warmSunsetTint.g, 0.38),
        b = Lerp(dayColor.b, warmSunsetTint.b, 0.38),
        fogStart = baseFog.fogStart * 0.70,
        fogEnd = baseFog.fogEnd * 0.78,
    })
    Environment.NightFog = ClampFog({
        r = Lerp(dayColor.r, coolNightTint.r, 0.82),
        g = Lerp(dayColor.g, coolNightTint.g, 0.82),
        b = Lerp(dayColor.b, coolNightTint.b, 0.82),
        fogStart = baseFog.fogStart * 0.30,
        fogEnd = baseFog.fogEnd * 0.46,
    })
    Environment.SunriseFog = ClampFog({
        r = Lerp(dayColor.r, pinkSunriseTint.r, 0.48),
        g = Lerp(dayColor.g, pinkSunriseTint.g, 0.48),
        b = Lerp(dayColor.b, pinkSunriseTint.b, 0.48),
        fogStart = baseFog.fogStart * 0.62,
        fogEnd = baseFog.fogEnd * 0.74,
    })
end

local function BuildMoonFogKeyframes(baseFog)
    local dayTint   = { r = 0.50, g = 0.52, b = 0.58 }
    local duskTint  = { r = 0.46, g = 0.45, b = 0.56 }
    local nightTint = { r = 0.15, g = 0.17, b = 0.24 }
    local dawnTint  = { r = 0.54, g = 0.50, b = 0.62 }
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
        fogStart = dayStart * 0.94,
        fogEnd = dayEnd * 0.95,
    })
    Environment.NightFog = ClampFog({
        r = nightTint.r,
        g = nightTint.g,
        b = nightTint.b,
        fogStart = dayStart * 0.70,
        fogEnd = dayEnd * 0.76,
    })
    Environment.SunriseFog = ClampFog({
        r = dawnTint.r,
        g = dawnTint.g,
        b = dawnTint.b,
        fogStart = dayStart * 0.90,
        fogEnd = dayEnd * 0.92,
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
        Environment.NightSunPowerScale = 0.08
        Environment.DayShadowFarDistance = 1150.0
        Environment.NightShadowFarDistance = 260.0
        Environment.StableShadowFarDistance = Environment.DayShadowFarDistance

        Environment.SunsetAccentStrength = 0.35
        Environment.SunriseAccentStrength = 0.35
        Environment.SunsetFogAccentStrength = 0.32
        Environment.SunriseFogAccentStrength = 0.32

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
    Environment.NightSunPowerScale = 0.16
    Environment.DayShadowFarDistance = 900.0
    Environment.NightShadowFarDistance = 220.0
    Environment.StableShadowFarDistance = Environment.DayShadowFarDistance

    Environment.SunsetAccentStrength = 0.58
    Environment.SunriseAccentStrength = 0.48
    Environment.SunsetFogAccentStrength = 0.55
    Environment.SunriseFogAccentStrength = 0.48

    BuildEarthFogKeyframes(baseFog)
end

-- =============================================================================
-- Shared cycle state
-- =============================================================================

local function ValidateCycleFractions()
    local dusk = Clamp01(Environment.DuskStartFraction)
    local night = Clamp01(Environment.NightStartFraction)
    local dawn = Clamp01(Environment.DawnStartFraction)

    if night <= dusk then
        night = math.min(0.99, dusk + 0.05)
    end
    if dawn <= night then
        dawn = math.min(0.995, night + 0.05)
    end

    Environment.DuskStartFraction = dusk
    Environment.NightStartFraction = night
    Environment.DawnStartFraction = dawn
end

local function ComputeCycleState(progress)
    local duration = math.max(1.0, Environment.CycleDuration or 900.0)
    local cycle = Clamp01(progress / duration)
    local duskStart = Environment.DuskStartFraction
    local nightStart = Environment.NightStartFraction
    local dawnStart = Environment.DawnStartFraction

    local state = {
        cycle = cycle,
        phase = "Day",
        phaseProgress = 0.0,
        nightBlend = 0.0,
        daylight = 1.0,
        sunsetAccent = 0.0,
        sunriseAccent = 0.0,
    }

    if cycle < duskStart then
        state.phase = "Day"
        state.phaseProgress = duskStart > 0.0 and (cycle / duskStart) or 0.0
        return state
    end

    if cycle < nightStart then
        local raw = InverseLerp(duskStart, nightStart, cycle)
        state.phase = "Dusk"
        state.phaseProgress = raw
        state.nightBlend = SmootherStep(raw)
        state.daylight = 1.0 - state.nightBlend
        state.sunsetAccent = SmoothBell(raw)
        return state
    end

    if cycle < dawnStart then
        state.phase = "Night"
        state.phaseProgress = InverseLerp(nightStart, dawnStart, cycle)
        state.nightBlend = 1.0
        state.daylight = 0.0
        return state
    end

    local raw = InverseLerp(dawnStart, 1.0, cycle)
    state.phase = "Dawn"
    state.phaseProgress = raw
    state.nightBlend = 1.0 - SmootherStep(raw)
    state.daylight = 1.0 - state.nightBlend
    state.sunriseAccent = SmoothBell(raw)
    return state
end

local function ComputeLighting(state)
    local E = Environment

    local ambient = LerpColor(E.DayAmbient, E.NightAmbient, state.nightBlend)
    local diffuse = LerpColor(E.DayDiffuse, E.NightDiffuse, state.nightBlend)
    local specular = LerpColor(E.DaySpecular, E.NightSpecular, state.nightBlend)

    if state.sunsetAccent > 0.0 then
        local influence = Clamp01(state.sunsetAccent * E.SunsetAccentStrength)
        ambient = LerpColor(ambient, E.SunsetAmbient, influence)
        diffuse = LerpColor(diffuse, E.SunsetDiffuse, influence)
        specular = LerpColor(specular, E.SunsetSpecular, influence)
    end

    if state.sunriseAccent > 0.0 then
        local influence = Clamp01(state.sunriseAccent * E.SunriseAccentStrength)
        ambient = LerpColor(ambient, E.SunriseAmbient, influence)
        diffuse = LerpColor(diffuse, E.SunriseDiffuse, influence)
        specular = LerpColor(specular, E.SunriseSpecular, influence)
    end

    return ClampColor(ambient), ClampColor(diffuse), ClampColor(specular)
end

local function ComputeAutomaticFog(state)
    local E = Environment
    local fog = LerpFog(E.DayFog, E.NightFog, state.nightBlend)

    if state.sunsetAccent > 0.0 then
        local influence = Clamp01(state.sunsetAccent * E.SunsetFogAccentStrength)
        fog = LerpFog(fog, E.SunsetFog, influence)
    end

    if state.sunriseAccent > 0.0 then
        local influence = Clamp01(state.sunriseAccent * E.SunriseFogAccentStrength)
        fog = LerpFog(fog, E.SunriseFog, influence)
    end

    return ClampFog(fog)
end

local function ComputeSunDirection(state)
    local E = Environment

    if state.phase == "Day" then
        return NormalizeDirection(E.DaySunDirection)
    end

    if state.phase == "Night" then
        return NormalizeDirection(E.NightSunDirection)
    end

    -- Split dusk and dawn around the visible horizon accent. The two halves use
    -- smootherstep so direction never snaps at the old 2%/98% thresholds.
    if state.phase == "Dusk" then
        local p = state.phaseProgress
        if p < 0.5 then
            return LerpDirection(E.DaySunDirection, E.SunsetSunDirection, SmootherStep(p * 2.0))
        end
        return LerpDirection(E.SunsetSunDirection, E.NightSunDirection, SmootherStep((p - 0.5) * 2.0))
    end

    local p = state.phaseProgress
    if p < 0.5 then
        return LerpDirection(E.NightSunDirection, E.SunriseSunDirection, SmootherStep(p * 2.0))
    end
    return LerpDirection(E.SunriseSunDirection, E.DaySunDirection, SmootherStep((p - 0.5) * 2.0))
end

local function ComputeSunState(state)
    return {
        direction = ComputeSunDirection(state),
        powerScale = Lerp(Environment.DaySunPowerScale, Environment.NightSunPowerScale, state.nightBlend),
        shadowFarDistance = Environment.StableShadowFarDistance,
        viewportShadows = Environment.KeepViewportShadowsEnabled,
    }
end

-- =============================================================================
-- Fog override blending
-- =============================================================================

local function ResolveFog(autoFog, now)
    local transition = Environment.FogTransition
    if transition then
        local duration = math.max(0.0, transition.duration or 0.0)
        local raw = duration <= 0.0 and 1.0 or Clamp01((now - transition.startTime) / duration)
        local t = SmootherStep(raw)
        local target = transition.toAuto and autoFog or transition.target
        local result = LerpFog(transition.from, target, t)

        if raw >= 1.0 then
            Environment.FogTransition = nil
            if transition.toAuto then
                Environment.FogManualOverride = nil
                return CopyFog(autoFog)
            end
            Environment.FogManualOverride = CopyFog(transition.target)
            return CopyFog(transition.target)
        end

        return ClampFog(result)
    end

    if Environment.FogManualOverride then
        return CopyFog(Environment.FogManualOverride)
    end

    return CopyFog(autoFog)
end

local function GetFogPreset(stateName)
    if stateName == nil then
        return nil
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
    return presets[normalized]
end

-- =============================================================================
-- Initialization
-- =============================================================================

function Environment.Init()
    if Environment.Initialized then
        return
    end

    RuntimeEnhancements.Initialize()
    ValidateCycleFractions()

    local trnFilename = nil
    local trn = nil
    local baseAmbient = CopyColor(Environment.DayAmbient)
    local baseDiffuse = CopyColor(Environment.DayDiffuse)
    local baseSpecular = CopyColor(Environment.DaySpecular)
    local baseFog = CopyFog(Environment.DayFog)

    if GetMapTRNFilename then
        trnFilename = GetMapTRNFilename()
        if trnFilename and trnFilename ~= "" then
            trn = OpenODF(trnFilename)
            if trn then
                local intensity = GetODFInt(trn, "NormalView", "Intensity", 128) / 255
                local ambient = GetODFInt(trn, "NormalView", "Ambient", 96) / 255
                local fogStart = GetODFFloat(trn, "NormalView", "FogStart", 200)
                local fogEnd = GetODFFloat(trn, "NormalView", "FogEnd", 700)
                Environment.MapTimeOfDay = GetODFInt(trn, "NormalView", "Time", Environment.MapTimeOfDay)

                local fr = GetODFFloat(trn, "NormalView", "FogColorR", 0.65)
                local fg = GetODFFloat(trn, "NormalView", "FogColorG", 0.45)
                local fb = GetODFFloat(trn, "NormalView", "FogColorB", 0.25)
                local specular = Clamp01((intensity * 0.85) + 0.10)

                baseAmbient = { r = ambient, g = ambient, b = ambient }
                baseDiffuse = { r = intensity, g = intensity, b = intensity }
                baseSpecular = { r = specular, g = specular, b = Clamp01(specular * 0.98) }
                baseFog = {
                    r = fr,
                    g = fg,
                    b = fb,
                    fogStart = fogStart,
                    fogEnd = fogEnd,
                }

                print(
                    "Environment: TRN loaded - time=" .. tostring(Environment.MapTimeOfDay)
                    .. " fogStart=" .. tostring(fogStart)
                    .. " fogEnd=" .. tostring(fogEnd)
                )
            end
        end
    end

    Environment.WorldPreset, Environment.WorldPalette = DetectWorldPreset(trnFilename, trn)
    ApplyWorldPreset(Environment.WorldPreset, baseAmbient, baseDiffuse, baseSpecular, baseFog)
    print("Environment: Preset -> [" .. Environment.WorldPreset .. "] palette=" .. tostring(Environment.WorldPalette))

    if Environment.NativeTimeOfDayOnInit and exu.SetTimeOfDay then
        exu.SetTimeOfDay(Environment.MapTimeOfDay)
    end

    Environment.DaySunDirection = NormalizeDirection(Environment.DaySunDirection)
    Environment.SunsetSunDirection = NormalizeDirection(Environment.SunsetSunDirection)
    Environment.NightSunDirection = NormalizeDirection(Environment.NightSunDirection)
    Environment.SunriseSunDirection = NormalizeDirection(Environment.SunriseSunDirection)

    Environment.CraftHandles = {}
    Environment.CraftCursor = 1
    Environment.PendingGameplaySync = true
    Environment.GameplayRefreshAt = 0.0
    Environment.GameplayBatchAt = 0.0

    -- Force the first update to apply a coherent full state exactly once.
    Environment.LastAmbient = nil
    Environment.LastDiffuse = nil
    Environment.LastSpecular = nil
    Environment.LastFog = nil
    Environment.LastSunDirection = nil
    Environment.LastSunPowerScale = nil
    Environment.LastShadowFarDistance = nil
    Environment.LastViewportShadows = nil
    Environment.LastNightBlend = -1.0
    Environment.LastPhase = "Initial"

    Environment.Initialized = true
    print("Environment: Initialized (smooth cycle / stable shadows)")
end

-- =============================================================================
-- Main update
-- =============================================================================

function Environment.Update(timestep)
    if not Environment.Initialized then
        Environment.Init()
    end

    timestep = tonumber(timestep) or 0.0
    local gameTime = GetTime()
    local scaledTime = gameTime * (Environment.DebugScale or 1.0)
    local duration = math.max(1.0, Environment.CycleDuration or 900.0)
    local progress = scaledTime % duration
    local state = ComputeCycleState(progress)

    if state.phase ~= Environment.LastPhase then
        local msg = "Environment: Phase -> [" .. state.phase .. "]"
        print(msg)
        if AddTMsg then
            AddTMsg(msg)
        end
        Environment.LastPhase = state.phase
    end

    Environment.IsNight = state.nightBlend >= 0.50
    Environment.NightBlend = state.nightBlend

    local targetAmbient, targetDiffuse, targetSpecular = ComputeLighting(state)
    local automaticFog = ComputeAutomaticFog(state)
    local targetFog = ResolveFog(automaticFog, gameTime)
    local sunState = ComputeSunState(state)

    -- -------------------------------------------------------------------------
    -- Dust storm override
    -- Dust remains intentionally authoritative over a manual fog request while
    -- active, matching the old behavior. Gravity is restored once on exit.
    -- -------------------------------------------------------------------------
    local wasDustStorm = Environment.IsDustStorm
    local isDustStorm = (Environment.DustStormTimer or 0.0) > 0.0
    Environment.IsDustStorm = isDustStorm

    if isDustStorm then
        Environment.DustStormTimer = math.max(0.0, Environment.DustStormTimer - timestep)
        targetFog = CopyFog(Environment.DustStormFog)

        if not Environment.LastGravity or (scaledTime - Environment.LastGravity) > 0.5 then
            local wobX = math.sin(gameTime * 5.0) * 0.5
            local wobZ = math.cos(gameTime * 4.3) * 0.5
            if exu.SetGravity then
                exu.SetGravity(wobX, -9.8, wobZ)
            end
            Environment.LastGravity = scaledTime
        end
    elseif wasDustStorm then
        if exu.SetGravity then
            exu.SetGravity(0, -9.8, 0)
        end
        Environment.LastGravity = nil
    end

    -- -------------------------------------------------------------------------
    -- Lighting / fog writes
    -- Small epsilons avoid redundant renderer writes without reducing visible
    -- smoothness to coarse stepping.
    -- -------------------------------------------------------------------------
    if Environment.EnableSunLighting then
        local setAmbientLight = GetAmbientLightSetter()

        if setAmbientLight and ColorChanged(Environment.LastAmbient, targetAmbient, 0.00025) then
            setAmbientLight(targetAmbient.r, targetAmbient.g, targetAmbient.b)
            Environment.LastAmbient = CopyColor(targetAmbient)
        end

        if exu.SetSunDiffuse and ColorChanged(Environment.LastDiffuse, targetDiffuse, 0.00025) then
            exu.SetSunDiffuse(targetDiffuse.r, targetDiffuse.g, targetDiffuse.b)
            Environment.LastDiffuse = CopyColor(targetDiffuse)
        end

        if exu.SetSunSpecular and ColorChanged(Environment.LastSpecular, targetSpecular, 0.00025) then
            exu.SetSunSpecular(targetSpecular.r, targetSpecular.g, targetSpecular.b)
            Environment.LastSpecular = CopyColor(targetSpecular)
        end
    end

    if exu.SetFog and FogChanged(Environment.LastFog, targetFog, 0.00035, 0.25) then
        exu.SetFog(targetFog.r, targetFog.g, targetFog.b, targetFog.fogStart, targetFog.fogEnd)
        Environment.LastFog = CopyFog(targetFog)
    end

    -- -------------------------------------------------------------------------
    -- Sun / shadow writes
    -- The shadow range and viewport-enable state are deliberately invariant over
    -- the day/night cycle. Only light direction and power animate.
    -- -------------------------------------------------------------------------
    if Environment.EnableSunLighting then
        local setSunDirection = GetSunDirectionSetter()

        if setSunDirection and DirectionChanged(Environment.LastSunDirection, sunState.direction, 0.0005) then
            setSunDirection(sunState.direction.x, sunState.direction.y, sunState.direction.z)
            Environment.LastSunDirection = {
                x = sunState.direction.x,
                y = sunState.direction.y,
                z = sunState.direction.z,
            }
        end

        if exu.SetSunPowerScale and FloatChanged(Environment.LastSunPowerScale, sunState.powerScale, 0.0005) then
            exu.SetSunPowerScale(sunState.powerScale)
            Environment.LastSunPowerScale = sunState.powerScale
        end

        if exu.SetSunShadowFarDistance
            and FloatChanged(Environment.LastShadowFarDistance, sunState.shadowFarDistance, 0.01)
        then
            exu.SetSunShadowFarDistance(sunState.shadowFarDistance)
            Environment.LastShadowFarDistance = sunState.shadowFarDistance
        end

        if exu.SetViewportShadowsEnabled and Environment.LastViewportShadows ~= sunState.viewportShadows then
            exu.SetViewportShadowsEnabled(sunState.viewportShadows)
            Environment.LastViewportShadows = sunState.viewportShadows
        end
    end

    -- Night gameplay effects are intentionally driven by the same smooth blend
    -- that drives the visuals.
    if math.abs(state.nightBlend - (Environment.LastNightBlend or -1.0)) > 0.02 then
        Environment.PendingGameplaySync = true
        Environment.LastNightBlend = state.nightBlend
    end

    if Environment.PendingGameplaySync then
        Environment.SyncGameplayImpacts()
    end

    if Environment.EnableVisualRuntime then
        RuntimeEnhancements.Update(timestep)
    end
end

-- =============================================================================
-- Gameplay impacts (radar / stealth, smoothly lerped by NightBlend)
-- =============================================================================

function Environment.SyncGameplayImpacts()
    local now = GetTime()

    if now >= (Environment.GameplayRefreshAt or 0.0)
        or not Environment.CraftHandles
        or #Environment.CraftHandles == 0
    then
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
    if not h or not IsValid(h) then
        return
    end
    if not exu.SetRadarRange or not exu.SetRadarPeriod or not exu.SetVelocJam then
        return
    end

    local blend = Clamp01(Environment.NightBlend or 0.0)

    if blend > 0.001 then
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

    if Environment.OriginalRadarRanges[h] then
        exu.SetRadarRange(h, Environment.OriginalRadarRanges[h] * Lerp(1.0, Environment.RadarRangeNerf, blend))
    end
    if Environment.OriginalRadarPeriods[h] then
        exu.SetRadarPeriod(h, Environment.OriginalRadarPeriods[h] * Lerp(1.0, Environment.RadarPeriodNerf, blend))
    end
    if Environment.OriginalVelocJams[h] then
        exu.SetVelocJam(h, Environment.OriginalVelocJams[h] * Lerp(1.0, Environment.VelocJamBuff, blend))
    end

    if blend <= 0.001 then
        Environment.OriginalRadarRanges[h] = nil
        Environment.OriginalRadarPeriods[h] = nil
        Environment.OriginalVelocJams[h] = nil
    end
end

function Environment.OnObjectCreated(h)
    if not h or not IsValid(h) then
        return
    end

    if IsCraft(h) then
        Environment.CraftHandles = Environment.CraftHandles or {}
        Environment.CraftHandles[#Environment.CraftHandles + 1] = h
        Environment.PendingGameplaySync = true
    end

    RuntimeEnhancements.OnObjectCreated(h)
    Environment.ProcessObjectNightEffects(h)
end

-- =============================================================================
-- External triggers / compatibility API
-- =============================================================================

function Environment.TriggerDustStorm(duration)
    Environment.DustStormTimer = math.max(0.0, tonumber(duration) or 30.0)
    print("Environment: Dust storm triggered for " .. tostring(Environment.DustStormTimer) .. "s")
end

-- Force a fog preset override ("day", "sunset", "night", "sunrise", "dust").
-- Pass "auto"/nil to return to the live time-of-day curve.
-- Unlike the old implementation, blendDuration is now honored.
function Environment.SetFogState(stateName, blendDuration)
    if not Environment.Initialized then
        Environment.Init()
    end

    local duration = math.max(0.0, tonumber(blendDuration) or 0.0)
    local from = Environment.LastFog and CopyFog(Environment.LastFog) or CopyFog(Environment.DayFog)

    if stateName == nil or string.lower(tostring(stateName)) == "auto" then
        Environment.FogManualOverride = nil
        if duration > 0.0 then
            Environment.FogTransition = {
                from = from,
                target = nil,
                toAuto = true,
                startTime = GetTime(),
                duration = duration,
            }
        else
            Environment.FogTransition = nil
            Environment.LastFog = nil
        end
        return
    end

    local preset = GetFogPreset(stateName)
    if not preset then
        print("Environment: Unknown fog state '" .. tostring(stateName) .. "'")
        return
    end

    local target = CopyFog(preset)
    Environment.FogManualOverride = target

    if duration > 0.0 then
        Environment.FogTransition = {
            from = from,
            target = target,
            toAuto = false,
            startTime = GetTime(),
            duration = duration,
        }
    else
        Environment.FogTransition = nil
        Environment.LastFog = nil
    end
end

-- Useful for test harnesses / mission diagnostics without exposing the private
-- cycle implementation. Returns a copy-like scalar state only.
function Environment.GetCycleState()
    if not Environment.Initialized then
        Environment.Init()
    end

    local duration = math.max(1.0, Environment.CycleDuration or 900.0)
    local scaledTime = GetTime() * (Environment.DebugScale or 1.0)
    local state = ComputeCycleState(scaledTime % duration)
    return {
        cycle = state.cycle,
        phase = state.phase,
        phaseProgress = state.phaseProgress,
        nightBlend = state.nightBlend,
        daylight = state.daylight,
        sunsetAccent = state.sunsetAccent,
        sunriseAccent = state.sunriseAccent,
    }
end

return Environment
