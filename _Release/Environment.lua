-- Environment.lua
-- Dynamic atmosphere system for Battlezone 98 Redux
-- Handles Day/Night cycles, independent fog events, and gameplay impacts.

local exu = require("exu")

-- =============================================================================
-- Lighting keyframe layout (progress = seconds into the 900s cycle):
--
--   0 ──────────── 450   500   550 ───────────── 850   875   900
--   |<─── Day ────>|<─Sunset─>|<───── Night ─────>|<─Sunrise─>|
--   D              D    SP    N                   N    SR      D
--
--   D  = DayAmbient / DayDiffuse        (white, 1.0 across the board)
--   SP = SunsetPeak                     (orange-red)
--   N  = NightAmbient / NightDiffuse    (near-black blue tint)
--   SR = SunrisePeak                    (orange-gold)
--
-- Fog is INDEPENDENT of lighting – it runs its own random state machine.
-- =============================================================================

Environment = {
    -- Cycle config
    CycleDuration        = 900, -- seconds (15 min)

    -- EXU sunlight hooks are currently unstable in BZR 2.2.301 and can crash
    -- during phase transitions, so keep dynamic fog/gameplay and disable the
    -- sun mutation path unless explicitly re-enabled after EXU is fixed.
    EnableSunLighting    = true,

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
    SunsetAmbient        = { r = 0.55, g = 0.20, b = 0.08 },
    SunsetDiffuse        = { r = 1.00, g = 0.45, b = 0.10 },
    SunsetSpecular       = { r = 0.50, g = 0.20, b = 0.05 },
    -- Night: near-black with a faint blue tint
    NightAmbient         = { r = 0.01, g = 0.01, b = 0.03 },
    NightDiffuse         = { r = 0.04, g = 0.04, b = 0.10 },
    NightSpecular        = { r = 0.01, g = 0.01, b = 0.03 },
    -- Sunrise peak (hit at progress = 875, midpoint of the 50s sunrise window)
    SunriseAmbient       = { r = 0.45, g = 0.22, b = 0.05 },
    SunriseDiffuse       = { r = 0.90, g = 0.55, b = 0.15 },
    SunriseSpecular      = { r = 0.48, g = 0.30, b = 0.10 },

    -- ── Fog presets ───────────────────────────────────────────────────────────
    -- "clear" values are overwritten from the map TRN at init time.
    FogPresets           = {
        clear = { r = 0.65, g = 0.45, b = 0.25, fogStart = 200, fogEnd = 700 },
        haze  = { r = 0.55, g = 0.35, b = 0.18, fogStart = 80, fogEnd = 350 },
        fog   = { r = 0.30, g = 0.30, b = 0.35, fogStart = 30, fogEnd = 150 },
        dust  = { r = 0.50, g = 0.30, b = 0.12, fogStart = 5, fogEnd = 45 },
    },

    -- Weighted chance (relative, not %) of picking each fog state
    FogWeights           = { clear = 50, haze = 30, fog = 15, dust = 5 },

    -- Fog state machine
    FogStateName         = "clear",
    FogFrom              = nil, -- filled in Init()
    FogTo                = nil, -- filled in Init()
    FogBlendTimer        = 30,   -- starts equal to FogBlendDuration = already at target
    FogBlendDuration     = 30,   -- seconds to crossfade between fog states
    FogChangeTimer       = 0,    -- countdown (seconds) to next random change

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

    -- Dust storm (gravity wobble, separate from fog "dust" state)
    DustStormTimer       = 0,
    IsDustStorm          = false,
    LastGravity          = nil,

    -- Dirty-check caches
    LastAmbient          = nil,
    LastDiffuse          = nil,
    LastSpecular         = nil,
    LastFog              = nil,

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

local function FogEqual(a, b)
    return a.r == b.r and a.g == b.g and a.b == b.b
        and a.fogStart == b.fogStart and a.fogEnd == b.fogEnd
end

-- Weighted random pick from FogWeights, excluding the current state
local function PickNextFogState()
    local weights = Environment.FogWeights
    local current = Environment.FogStateName
    local pool = {}
    local total = 0
    for state, w in pairs(weights) do
        if state ~= current then
            pool[#pool + 1] = { state = state, w = w }
            total = total + w
        end
    end
    local roll = math.random() * total
    local cumul = 0
    for _, entry in ipairs(pool) do
        cumul = cumul + entry.w
        if roll <= cumul then return entry.state end
    end
    return "clear"
end

local function RandomFogInterval()
    return 60 + math.random() * 120  -- 60–180 seconds between fog state changes
end

-- =============================================================================
-- Init
-- =============================================================================

function Environment.Init()
    -- Read map TRN for the "clear" fog baseline
    if GetMapTRNFilename then
        local trnFilename = GetMapTRNFilename()
        if trnFilename and trnFilename ~= "" then
            local trn = OpenODF(trnFilename)
            if trn then
                local fogStart               = GetODFFloat(trn, "NormalView", "FogStart", 200)
                local fogEnd                 = GetODFFloat(trn, "NormalView", "FogEnd", 700)
                -- Use TRN fog colour if present, otherwise keep the warm-dust default
                local fr                     = GetODFFloat(trn, "NormalView", "FogColorR", 0.65)
                local fg                     = GetODFFloat(trn, "NormalView", "FogColorG", 0.45)
                local fb                     = GetODFFloat(trn, "NormalView", "FogColorB", 0.25)
                Environment.FogPresets.clear = {
                    r = fr,
                    g = fg,
                    b = fb,
                    fogStart = fogStart,
                    fogEnd = fogEnd,
                }
                print("Environment: TRN fog loaded – start=" .. fogStart .. " end=" .. fogEnd)
            end
        end
    end

    -- Seed fog state machine at "clear"
    local clearPreset          = Environment.FogPresets.clear
    Environment.FogFrom        = CopyFog(clearPreset)
    Environment.FogTo          = CopyFog(clearPreset)
    Environment.FogBlendTimer  = Environment.FogBlendDuration -- already at target
    Environment.FogChangeTimer = RandomFogInterval()
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

-- =============================================================================
-- Fog – independent random state machine
-- =============================================================================

local function UpdateFogMachine()
    local E  = Environment
    local dt = GetTimeStep()  -- seconds, per scriptutils

    -- Advance blend
    E.FogBlendTimer = math.min(E.FogBlendTimer + dt, E.FogBlendDuration)
    local blendT = E.FogBlendTimer / E.FogBlendDuration

    -- Countdown to next change (only start a new transition once the current one finishes)
    E.FogChangeTimer = E.FogChangeTimer - dt
    if E.FogChangeTimer <= 0 and blendT >= 1 then
        local nextState  = PickNextFogState()
        local preset     = E.FogPresets[nextState]

        E.FogFrom        = CopyFog(E.FogTo) -- freeze current interpolated position as "from"
        E.FogTo          = CopyFog(preset)
        E.FogStateName   = nextState
        E.FogBlendTimer  = 0
        E.FogChangeTimer = RandomFogInterval()
        blendT           = 0

        print("Environment: Fog → [" .. nextState .. "]")
        if AddTMsg then AddTMsg("Environment: Fog → [" .. nextState .. "]") end
    end

    return LerpFog(E.FogFrom, E.FogTo, blendT)
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

    -- ── Lighting ──────────────────────────────────────────────────────────
    local targetAmbient, targetDiffuse, targetSpecular = ComputeLighting(progress)

    -- ── Fog (independent) ─────────────────────────────────────────────────
    local wasDustStorm = Environment.IsDustStorm
    local isDustStorm = (Environment.DustStormTimer > 0)

    -- Blend into/out of the dust preset when a storm starts or ends
    if isDustStorm ~= wasDustStorm then
        Environment.FogFrom       = CopyFog(Environment.FogTo)
        Environment.FogTo         = CopyFog(isDustStorm and Environment.FogPresets.dust or
        Environment.FogPresets[Environment.FogStateName])
        Environment.FogBlendTimer = 0
    end

    Environment.IsDustStorm = isDustStorm

    local targetFog = UpdateFogMachine()

    -- ── Dust storm gravity wobble ─────────────────────────────────────────
    if Environment.DustStormTimer > 0 then
        Environment.DustStormTimer = Environment.DustStormTimer - timestep
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
        if not lastA
            or targetAmbient.r ~= lastA.r
            or targetAmbient.g ~= lastA.g
            or targetAmbient.b ~= lastA.b
        then
            exu.SetSunAmbient(targetAmbient.r, targetAmbient.g, targetAmbient.b)
            Environment.LastAmbient = { r = targetAmbient.r, g = targetAmbient.g, b = targetAmbient.b }
        end

        local lastD = Environment.LastDiffuse
        if not lastD
            or targetDiffuse.r ~= lastD.r
            or targetDiffuse.g ~= lastD.g
            or targetDiffuse.b ~= lastD.b
        then
            exu.SetSunDiffuse(targetDiffuse.r, targetDiffuse.g, targetDiffuse.b)
            Environment.LastDiffuse = { r = targetDiffuse.r, g = targetDiffuse.g, b = targetDiffuse.b }
        end

        local lastS = Environment.LastSpecular
        if not lastS
            or targetSpecular.r ~= lastS.r
            or targetSpecular.g ~= lastS.g
            or targetSpecular.b ~= lastS.b
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

    -- ── Night blend for gameplay effects ──────────────────────────────────
    local nightBlend
    if progress < 450 then
        nightBlend = 0
    elseif progress < 550 then
        nightBlend = (progress - 450) / 100
    elseif progress < 850 then
        nightBlend = 1
    else
        nightBlend = 1 - (progress - 850) / 50
    end

    Environment.IsNight    = (nightBlend > 0.5)
    Environment.NightBlend = nightBlend

    if math.abs(nightBlend - Environment.LastNightBlend) > 0.02 then
        Environment.PendingGameplaySync = true
        Environment.LastNightBlend = nightBlend
    end

    if Environment.PendingGameplaySync then
        Environment.SyncGameplayImpacts()
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

-- Force an immediate fog transition to a named preset ("clear","haze","fog","dust")
function Environment.SetFogState(stateName, blendDuration)
    local preset = Environment.FogPresets[stateName]
    if not preset then
        print("Environment: Unknown fog state '" .. tostring(stateName) .. "'")
        return
    end
    Environment.FogFrom          = CopyFog(Environment.FogTo or preset)
    Environment.FogTo            = CopyFog(preset)
    Environment.FogStateName     = stateName
    Environment.FogBlendTimer    = 0
    Environment.FogBlendDuration = blendDuration or Environment.FogBlendDuration
    Environment.FogChangeTimer   = RandomFogInterval()
end

return Environment
