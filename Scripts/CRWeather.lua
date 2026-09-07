-- CRWeather.lua
-- Campaign Reimagined weather controller.
--
-- Weather here is an atmospheric renderer, not a sequence of scripted
-- explosions. It is built from four cooperating layers:
--
--   near-field   camera-attached Ogre particle systems (rain, snow, dust, ash,
--                spores). Density is bounded to a volume around the camera; we
--                never simulate precipitation map-wide.
--   atmosphere   fog colour and distance, which is what actually sells storm
--                depth beyond the emitter.
--   sky          an optional runtime skydome swap.
--   lighting     ambient / sun diffuse / sun power, plus lightning flashes.
--
-- Ownership: when Environment.lua is loaded, it is the single writer for fog
-- and sun state. CRWeather registers an environment modifier and contributes a
-- weighted blend into Environment's own per-frame targets, so the day/night
-- cycle and the storm cannot fight over the same renderer calls. When
-- Environment is absent, CRWeather writes fog and lighting itself and restores
-- the captured baseline on shutdown.
--
-- Nothing in this module creates a game-world object, applies damage, or
-- changes gameplay state. A mission that wants hazardous weather implements
-- that damage rule itself.

local exu = require("exu")
local CRWeatherPresets = require("CRWeatherPresets")

local CRWeather = {}

-- =============================================================================
-- Configuration
-- =============================================================================

CRWeather.Enabled            = true

-- Quality scales emitter rate and particle quota. 1.0 is the authored density.
-- A settings page or a low-end profile can drop this without editing presets.
CRWeather.Quality            = 1.0

-- Extra multiplier a mission can animate for storm phase ("it gets worse as you
-- approach the objective") without swapping presets.
CRWeather.Intensity          = 1.0

-- The sky layer is opt-in. Ogre exposes the skydome's generation parameters but
-- not its material name, so once we swap the sky we cannot discover what to
-- swap back to. A mission must state its own base sky before the sky layer will
-- engage; otherwise weather runs as particles + fog + light only, which still
-- reads as a full storm.
CRWeather.BaseSky            = nil

-- Log one line per state change. Off by default so a normal mission run is quiet.
CRWeather.Debug              = false

-- =============================================================================
-- Runtime state
-- =============================================================================

CRWeather.Initialized        = false
CRWeather.Active             = nil   -- preset table currently blending in
CRWeather.Previous           = nil   -- preset table currently blending out
CRWeather.Blend              = 0.0   -- 0 = no weather, 1 = Active fully applied
CRWeather.BlendTarget        = 0.0
CRWeather.BlendRate          = 0.0
CRWeather.SkyApplied         = false
CRWeather.LiveSystems        = {}    -- systemName -> { spec = ..., preset = ... }
CRWeather.ModifierRegistered = false
CRWeather.OwnsEnvironment    = false -- true when Environment.lua is not present
CRWeather.BaselineFog        = nil
CRWeather.BaselineAmbient    = nil
CRWeather.BaselineDiffuse    = nil
CRWeather.BaselineSunPower   = nil
CRWeather.NextStrikeAt       = nil
CRWeather.FlashUntil         = nil
CRWeather.FlashColor         = nil
CRWeather.FlashTime          = 0.0
CRWeather.PendingThunder     = nil
CRWeather.GustPhase          = 0.0
CRWeather.Clock              = 0.0

-- =============================================================================
-- Small helpers
-- =============================================================================

local function Clamp01(value)
    if value < 0.0 then return 0.0 end
    if value > 1.0 then return 1.0 end
    return value
end

local function Lerp(a, b, t)
    return a + (b - a) * t
end

local function Log(message)
    if not CRWeather.Debug then
        return
    end
    print("CRWeather: " .. tostring(message))
end

-- Every exu entry point below is optional: EXU may be older than these APIs, or
-- absent entirely on a stripped install. A missing function must degrade the
-- weather, never abort the mission.
local function Call(name, ...)
    local fn = exu and exu[name]
    if type(fn) ~= "function" then
        return nil
    end

    local ok, result = pcall(fn, ...)
    if not ok then
        Log("exu." .. name .. " failed: " .. tostring(result))
        return nil
    end
    return result
end

local function HasExu(name)
    return exu ~= nil and type(exu[name]) == "function"
end

local function Vec(v)
    if v == nil then
        return nil
    end
    return SetVector(v.x or 0.0, v.y or 0.0, v.z or 0.0)
end

local function Normalized(v)
    local length = math.sqrt((v.x * v.x) + (v.y * v.y) + (v.z * v.z))
    if length < 0.0001 then
        return { x = 0.0, y = -1.0, z = 0.0 }
    end
    return { x = v.x / length, y = v.y / length, z = v.z / length }
end

-- =============================================================================
-- Particle layer
-- =============================================================================

local function DestroySystem(systemName)
    Call("DetachParticleSystem", systemName)
    Call("DestroyParticleSystem", systemName)
    CRWeather.LiveSystems[systemName] = nil
end

local function DestroyAllSystems()
    local names = {}
    for systemName in pairs(CRWeather.LiveSystems) do
        names[#names + 1] = systemName
    end
    for i = 1, #names do
        DestroySystem(names[i])
    end
end

-- Applies the authored emitter values scaled by the live weight. Rate is the
-- only field that scales: velocity, lifetime, spread and colour are what the
-- weather *is*, and fading those instead of the rate makes a storm look like a
-- broken storm rather than a light one.
local function ApplyEmitterSpec(systemName, emitterIndex, emitter, weight)
    if emitter.rate ~= nil then
        Call("SetParticleEmitterEmissionRate", systemName, emitterIndex, math.max(0.0, emitter.rate * weight))
    end

    if weight <= 0.0 then
        -- Leave the rest alone while the system is silent; there is nothing to
        -- see and the writes would just be renderer churn.
        return
    end

    if emitter.velocity ~= nil then
        Call("SetParticleEmitterVelocity", systemName, emitterIndex, emitter.velocity[1], emitter.velocity[2])
    end
    if emitter.ttl ~= nil then
        Call("SetParticleEmitterTimeToLive", systemName, emitterIndex, emitter.ttl[1], emitter.ttl[2])
    end
    if emitter.angle ~= nil then
        Call("SetParticleEmitterAngle", systemName, emitterIndex, emitter.angle)
    end
    if emitter.color ~= nil then
        local startColor = emitter.color.start or emitter.color
        local endColor = emitter.color.finish or startColor
        Call("SetParticleEmitterColor", systemName, emitterIndex, startColor, endColor)
    end
end

local function ApplyWindToSystem(systemName, spec, preset)
    local direction = preset.wind and Normalized(preset.wind) or { x = 0.0, y = -1.0, z = 0.0 }
    local emitters = spec.emitters or {}
    for emitterIndex in pairs(emitters) do
        Call("SetParticleEmitterDirection", systemName, emitterIndex, Vec(direction))
    end
end

local function CreateSystem(spec, preset)
    local existing = CRWeather.LiveSystems[spec.system]
    if existing ~= nil then
        -- Two presets can name the same system (a blizzard and a light snow
        -- both want cr_wx_snow_heavy). Retarget the live one at the incoming
        -- preset, or the crossfade would drive it off the outgoing weight and
        -- the new storm would never appear.
        existing.spec = spec
        existing.preset = preset
        ApplyWindToSystem(spec.system, spec, preset)
        return true
    end

    if Call("CreateParticleSystem", spec.system, spec.template) ~= true then
        Log("could not create particle system " .. tostring(spec.system) ..
            " from template " .. tostring(spec.template))
        return false
    end

    if spec.quota ~= nil then
        Call("SetParticleSystemParticleQuota", spec.system, math.max(1, math.floor(spec.quota * CRWeather.Quality)))
    end

    -- Precipitation emits into world space: the emitter travels with the view,
    -- the particles it has already produced do not.
    Call("SetParticleSystemKeepLocalSpace", spec.system, false)

    -- An off-screen storm should not keep simulating.
    Call("SetParticleSystemNonVisibleUpdateTimeout", spec.system, 2.0)

    if HasExu("AttachParticleSystemToCamera") then
        Call("AttachParticleSystemToCamera", spec.system, Vec(spec.offset or { x = 0, y = 0, z = 0 }))
    else
        -- Pre-attachment EXU: park the volume at the origin offset and accept
        -- that it does not follow the player. Better than nothing, and the
        -- mission still runs.
        Log("EXU has no camera attachment; " .. tostring(spec.system) .. " will not follow the view")
    end

    CRWeather.LiveSystems[spec.system] = { spec = spec, preset = preset }
    ApplyWindToSystem(spec.system, spec, preset)

    local emitters = spec.emitters or {}
    for emitterIndex, emitter in pairs(emitters) do
        ApplyEmitterSpec(spec.system, emitterIndex, emitter, 0.0)
    end

    return true
end

local function SyncSystems(dt)
    for systemName, live in pairs(CRWeather.LiveSystems) do
        local isIncoming = (live.preset == CRWeather.Active)
        local presetWeight = isIncoming and CRWeather.Blend or (1.0 - CRWeather.Blend)
        local weight = Clamp01(presetWeight) * Clamp01(CRWeather.Intensity) * math.max(0.0, CRWeather.Quality)

        -- Gusts modulate rate only, so one authored template covers calm and gale.
        local gusts = live.preset.gusts
        if gusts and weight > 0.0 then
            local period = math.max(0.5, gusts.period or 12.0)
            local depth = Clamp01(gusts.depth or 0.0)
            local wave = 0.5 + (0.5 * math.sin((CRWeather.Clock / period) * 6.2831853))
            weight = weight * (1.0 - depth + (depth * wave))
        end

        local emitters = live.spec.emitters or {}
        for emitterIndex, emitter in pairs(emitters) do
            ApplyEmitterSpec(systemName, emitterIndex, emitter, weight)
        end

        Call("SetParticleSystemEmitting", systemName, weight > 0.001)
    end

    -- One call per frame moves every camera follower. It returns 0 when the
    -- camera attachment resolved to a real scene-graph parent and nothing needs
    -- chasing, which is the normal case.
    Call("UpdateParticleFollowers")
end

-- =============================================================================
-- Sky layer
-- =============================================================================

local function ApplySky(sky)
    if sky == nil then
        return
    end

    if sky.type == "box" then
        Call("SetSkyBox", sky.material, sky.distance, sky.drawFirst ~= false)
    else
        Call("SetSkyDome", sky.material, sky.curvature, sky.tiling, sky.distance, sky.drawFirst ~= false)
    end
end

local function SyncSky()
    local wantSky = CRWeather.Active ~= nil and CRWeather.Active.sky ~= nil and CRWeather.BaseSky ~= nil

    -- The swap is a hard cut either way, so do it at the midpoint of the
    -- transition where the fog has already contracted enough to hide it.
    if wantSky and not CRWeather.SkyApplied and CRWeather.Blend >= 0.5 then
        ApplySky(CRWeather.Active.sky)
        CRWeather.SkyApplied = true
        Log("sky -> " .. tostring(CRWeather.Active.sky.material))
    elseif CRWeather.SkyApplied and (not wantSky or CRWeather.Blend < 0.5) then
        ApplySky(CRWeather.BaseSky)
        CRWeather.SkyApplied = false
        Log("sky restored")
    end
end

-- =============================================================================
-- Atmosphere and lighting contribution
-- =============================================================================

local function CurrentWeight()
    return Clamp01(CRWeather.Blend) * Clamp01(CRWeather.Intensity)
end

-- Mutates an Environment frame in place. Also used by the standalone path,
-- where the "frame" is a baseline snapshot instead of Environment's live target.
function CRWeather.ApplyEnvironmentContribution(frame)
    local preset = CRWeather.Active
    local weight = CurrentWeight()

    if preset ~= nil and weight > 0.0 then
        if preset.fog and frame.fog then
            frame.fog.r = Lerp(frame.fog.r, preset.fog.r, weight)
            frame.fog.g = Lerp(frame.fog.g, preset.fog.g, weight)
            frame.fog.b = Lerp(frame.fog.b, preset.fog.b, weight)
            frame.fog.fogStart = Lerp(frame.fog.fogStart, preset.fog.fogStart, weight)
            frame.fog.fogEnd = Lerp(frame.fog.fogEnd, preset.fog.fogEnd, weight)
        end

        if preset.ambient and frame.ambient then
            frame.ambient.r = Lerp(frame.ambient.r, preset.ambient.r, weight)
            frame.ambient.g = Lerp(frame.ambient.g, preset.ambient.g, weight)
            frame.ambient.b = Lerp(frame.ambient.b, preset.ambient.b, weight)
        end

        if preset.diffuse and frame.diffuse then
            frame.diffuse.r = Lerp(frame.diffuse.r, preset.diffuse.r, weight)
            frame.diffuse.g = Lerp(frame.diffuse.g, preset.diffuse.g, weight)
            frame.diffuse.b = Lerp(frame.diffuse.b, preset.diffuse.b, weight)
        end

        if preset.sunPowerScale and frame.sunPowerScale then
            frame.sunPowerScale = Lerp(frame.sunPowerScale, preset.sunPowerScale, weight)
        end
    end

    -- Lightning is an illumination event, not an explosion: a brief additive
    -- lift on ambient is what actually sells the strike.
    if CRWeather.FlashUntil ~= nil and frame.ambient then
        local remaining = CRWeather.FlashUntil - CRWeather.Clock
        if remaining > 0.0 and CRWeather.FlashTime > 0.0 then
            local flashCurve = Clamp01(remaining / CRWeather.FlashTime)
            flashCurve = flashCurve * flashCurve
            local flash = CRWeather.FlashColor or { r = 0.5, g = 0.5, b = 0.6 }
            frame.ambient.r = frame.ambient.r + (flash.r * flashCurve)
            frame.ambient.g = frame.ambient.g + (flash.g * flashCurve)
            frame.ambient.b = frame.ambient.b + (flash.b * flashCurve)
        end
    end

    return frame
end

local function CaptureBaseline()
    local fog = Call("GetFog")
    if type(fog) == "table" then
        CRWeather.BaselineFog = {
            r = fog.r or 0.5, g = fog.g or 0.5, b = fog.b or 0.5,
            fogStart = fog.fogStart or fog.start or 100.0,
            fogEnd = fog.fogEnd or fog["end"] or 900.0,
        }
    end

    local ambient = Call("GetAmbientLight") or Call("GetSunAmbient")
    if type(ambient) == "table" then
        CRWeather.BaselineAmbient = { r = ambient.r or 0.5, g = ambient.g or 0.5, b = ambient.b or 0.5 }
    end

    local diffuse = Call("GetSunDiffuse")
    if type(diffuse) == "table" then
        CRWeather.BaselineDiffuse = { r = diffuse.r or 0.5, g = diffuse.g or 0.5, b = diffuse.b or 0.5 }
    end

    CRWeather.BaselineSunPower = Call("GetSunPowerScale")
end

-- Standalone path: no Environment.lua, so CRWeather owns the renderer writes.
local function WriteEnvironmentDirect()
    if CRWeather.BaselineFog == nil then
        return
    end

    local frame = {
        fog = {
            r = CRWeather.BaselineFog.r, g = CRWeather.BaselineFog.g, b = CRWeather.BaselineFog.b,
            fogStart = CRWeather.BaselineFog.fogStart, fogEnd = CRWeather.BaselineFog.fogEnd,
        },
        ambient = CRWeather.BaselineAmbient and {
            r = CRWeather.BaselineAmbient.r, g = CRWeather.BaselineAmbient.g, b = CRWeather.BaselineAmbient.b,
        } or nil,
        diffuse = CRWeather.BaselineDiffuse and {
            r = CRWeather.BaselineDiffuse.r, g = CRWeather.BaselineDiffuse.g, b = CRWeather.BaselineDiffuse.b,
        } or nil,
        sunPowerScale = CRWeather.BaselineSunPower,
    }

    CRWeather.ApplyEnvironmentContribution(frame)

    Call("SetFog", frame.fog.r, frame.fog.g, frame.fog.b, frame.fog.fogStart, frame.fog.fogEnd)
    if frame.ambient then
        if HasExu("SetAmbientLight") then
            Call("SetAmbientLight", frame.ambient.r, frame.ambient.g, frame.ambient.b)
        else
            Call("SetSunAmbient", frame.ambient.r, frame.ambient.g, frame.ambient.b)
        end
    end
    if frame.diffuse then
        Call("SetSunDiffuse", frame.diffuse.r, frame.diffuse.g, frame.diffuse.b)
    end
    if frame.sunPowerScale then
        Call("SetSunPowerScale", frame.sunPowerScale)
    end
end

-- =============================================================================
-- Lightning
-- =============================================================================

local function ScheduleNextStrike(policy)
    local minInterval = policy.minInterval or 8.0
    local maxInterval = math.max(minInterval, policy.maxInterval or (minInterval + 10.0))
    CRWeather.NextStrikeAt = CRWeather.Clock + minInterval + (math.random() * (maxInterval - minInterval))
end

local function UpdateLightning()
    local preset = CRWeather.Active
    local policy = preset and preset.lightning
    local weight = CurrentWeight()

    if policy == nil or weight < 0.35 then
        CRWeather.NextStrikeAt = nil
        return
    end

    if CRWeather.NextStrikeAt == nil then
        ScheduleNextStrike(policy)
        return
    end

    if CRWeather.Clock >= CRWeather.NextStrikeAt then
        CRWeather.FlashTime = policy.flashTime or 0.2
        CRWeather.FlashUntil = CRWeather.Clock + CRWeather.FlashTime
        CRWeather.FlashColor = policy.flash or { r = 0.5, g = 0.55, b = 0.65 }

        if policy.thunder ~= nil and policy.thunder.sound ~= nil then
            local minDelay = policy.thunder.minDelay or 1.0
            local maxDelay = math.max(minDelay, policy.thunder.maxDelay or (minDelay + 3.0))
            CRWeather.PendingThunder = {
                sound = policy.thunder.sound,
                at = CRWeather.Clock + minDelay + (math.random() * (maxDelay - minDelay)),
            }
        end

        ScheduleNextStrike(policy)
    end

    if CRWeather.FlashUntil ~= nil and CRWeather.Clock >= CRWeather.FlashUntil then
        CRWeather.FlashUntil = nil
        CRWeather.FlashColor = nil
        CRWeather.FlashTime = 0.0
    end

    local thunder = CRWeather.PendingThunder
    if thunder ~= nil and CRWeather.Clock >= thunder.at then
        CRWeather.PendingThunder = nil
        if StartSound then
            pcall(StartSound, thunder.sound)
        end
    end
end

-- =============================================================================
-- Public API
-- =============================================================================

-- options:
--   enabled  boolean
--   quality  number, scales emitter rate and particle quota
--   debug    boolean
--   baseSky  { type = "dome"|"box", material = "...", curvature, tiling, distance }
--            The map's own sky, so the sky layer knows what to restore.
function CRWeather.Init(options)
    if CRWeather.Initialized then
        return
    end

    options = options or {}
    if options.enabled ~= nil then CRWeather.Enabled = options.enabled and true or false end
    if options.quality ~= nil then CRWeather.Quality = math.max(0.0, tonumber(options.quality) or 1.0) end
    if options.debug ~= nil then CRWeather.Debug = options.debug and true or false end
    if options.baseSky ~= nil then CRWeather.BaseSky = options.baseSky end

    CRWeather.Clock = 0.0
    CRWeather.Blend = 0.0
    CRWeather.BlendTarget = 0.0
    CRWeather.BlendRate = 0.0
    CRWeather.Active = nil
    CRWeather.Previous = nil
    CRWeather.LiveSystems = {}
    CRWeather.SkyApplied = false

    CaptureBaseline()

    -- Environment.lua, when the mission loads it, is the single writer for fog
    -- and sun state. Contribute through its modifier hook rather than writing
    -- the same renderer state from two places on the same frame.
    local environment = rawget(_G, "Environment")
    if environment ~= nil and type(environment.RegisterEnvironmentModifier) == "function" then
        environment.RegisterEnvironmentModifier("CRWeather", function(frame)
            CRWeather.ApplyEnvironmentContribution(frame)
        end)
        CRWeather.ModifierRegistered = true
        CRWeather.OwnsEnvironment = false
        Log("contributing through Environment.lua")
    else
        CRWeather.OwnsEnvironment = true
        Log("no Environment.lua modifier hook; owning fog and lighting directly")
    end

    CRWeather.Initialized = true
end

-- Switches to a named preset. Pass nil, "clear", or "Clear" to stand the
-- weather down. transitionSeconds overrides the preset's own transition time.
function CRWeather.SetPreset(name, transitionSeconds)
    if not CRWeather.Initialized then
        CRWeather.Init()
    end

    local preset = nil
    if name ~= nil and string.lower(tostring(name)) ~= "clear" then
        preset = CRWeatherPresets.Get(name)
        if preset == nil then
            print("CRWeather: unknown preset '" .. tostring(name) .. "'")
            return false
        end
    end

    if preset == CRWeather.Active then
        return true
    end

    -- The outgoing preset keeps its systems alive so its particles fade rather
    -- than vanish; SyncSystems drives them off the inverse blend.
    CRWeather.Previous = CRWeather.Active
    CRWeather.Active = preset

    local duration
    if preset ~= nil then
        duration = tonumber(transitionSeconds) or preset.transitionIn or 20.0
        CRWeather.BlendTarget = 1.0
    else
        local outgoing = CRWeather.Previous
        duration = tonumber(transitionSeconds) or (outgoing and outgoing.transitionOut) or 20.0
        CRWeather.BlendTarget = 0.0
    end

    duration = math.max(0.05, duration)
    CRWeather.BlendRate = 1.0 / duration
    CRWeather.Blend = 0.0

    if preset ~= nil then
        for i = 1, #preset.precipitation do
            CreateSystem(preset.precipitation[i], preset)
        end
    end

    Log("preset -> " .. tostring(preset and preset.name or "Clear") ..
        " over " .. string.format("%.1f", duration) .. "s")
    return true
end

function CRWeather.GetPreset()
    return CRWeather.Active and CRWeather.Active.name or "Clear"
end

-- 0..1 storm-phase multiplier layered on top of the active preset.
function CRWeather.SetIntensity(scale)
    CRWeather.Intensity = Clamp01(tonumber(scale) or 1.0)
end

function CRWeather.GetIntensity()
    return CRWeather.Intensity
end

-- The map's own sky, so the sky layer knows what to restore. Without this the
-- sky layer stays off and weather runs as particles + fog + light.
function CRWeather.SetBaseSky(description)
    CRWeather.BaseSky = description
end

function CRWeather.GetWind()
    local preset = CRWeather.Active
    if preset == nil or preset.wind == nil then
        return SetVector(0.0, 0.0, 0.0)
    end

    local direction = Normalized(preset.wind)
    local speed = (preset.windSpeed or 0.0) * CurrentWeight()
    return SetVector(direction.x * speed, direction.y * speed, direction.z * speed)
end

function CRWeather.Update(dt)
    if not CRWeather.Initialized then
        CRWeather.Init()
    end

    if not CRWeather.Enabled then
        return
    end

    dt = tonumber(dt) or 0.0
    CRWeather.Clock = CRWeather.Clock + dt

    if CRWeather.Blend < 1.0 and CRWeather.BlendRate > 0.0 then
        CRWeather.Blend = Clamp01(CRWeather.Blend + (CRWeather.BlendRate * dt))
    end

    -- The outgoing preset's systems are only worth keeping while they still
    -- contribute; once the crossfade is done they are pure cost.
    if CRWeather.Previous ~= nil and CRWeather.Blend >= 1.0 then
        local stale = {}
        for systemName, live in pairs(CRWeather.LiveSystems) do
            if live.preset == CRWeather.Previous then
                stale[#stale + 1] = systemName
            end
        end
        for i = 1, #stale do
            DestroySystem(stale[i])
        end
        CRWeather.Previous = nil
    end

    SyncSystems(dt)
    SyncSky()
    UpdateLightning()

    if CRWeather.OwnsEnvironment then
        WriteEnvironmentDirect()
    end
end

-- Mission teardown. Every EXU-owned particle, the sky swap, and the environment
-- contribution have to be gone before the next mission's scene appears.
function CRWeather.Shutdown()
    if not CRWeather.Initialized then
        return
    end

    if CRWeather.SkyApplied and CRWeather.BaseSky ~= nil then
        ApplySky(CRWeather.BaseSky)
        CRWeather.SkyApplied = false
    end

    DestroyAllSystems()

    local environment = rawget(_G, "Environment")
    if CRWeather.ModifierRegistered and environment ~= nil
        and type(environment.UnregisterEnvironmentModifier) == "function"
    then
        environment.UnregisterEnvironmentModifier("CRWeather")
    end
    CRWeather.ModifierRegistered = false

    if CRWeather.OwnsEnvironment and CRWeather.BaselineFog ~= nil then
        CRWeather.Active = nil
        CRWeather.Previous = nil
        CRWeather.Blend = 0.0
        CRWeather.FlashUntil = nil
        WriteEnvironmentDirect()
    end

    CRWeather.Active = nil
    CRWeather.Previous = nil
    CRWeather.Blend = 0.0
    CRWeather.BlendTarget = 0.0
    CRWeather.BlendRate = 0.0
    CRWeather.NextStrikeAt = nil
    CRWeather.FlashUntil = nil
    CRWeather.PendingThunder = nil
    CRWeather.Initialized = false
end

-- Save/load. Only the scalar storm state is persisted; the particle systems are
-- rebuilt from the preset on load, because Ogre objects do not survive a save.
function CRWeather.Save()
    return {
        preset    = CRWeather.Active and CRWeather.Active.name or nil,
        blend     = CRWeather.Blend,
        intensity = CRWeather.Intensity,
        quality   = CRWeather.Quality,
        clock     = CRWeather.Clock,
    }
end

function CRWeather.Load(state)
    if type(state) ~= "table" then
        return
    end

    if not CRWeather.Initialized then
        CRWeather.Init()
    end

    CRWeather.Quality = tonumber(state.quality) or CRWeather.Quality
    CRWeather.Intensity = Clamp01(tonumber(state.intensity) or 1.0)
    CRWeather.Clock = tonumber(state.clock) or 0.0

    if state.preset ~= nil then
        -- Snap rather than transition: the player saved mid-storm and expects
        -- to load back into it, not into a 25 second fade-in.
        CRWeather.SetPreset(state.preset, 0.05)
        CRWeather.Blend = Clamp01(tonumber(state.blend) or 1.0)
    end
end

-- Compatibility stubs so a mission can call the same lifecycle shape it uses
-- for the other CR modules without guarding every call.
function CRWeather.OnObjectCreated(h) end

return CRWeather
