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
-- How far a preset can reach into a template: the typed emitter setters cover
-- rate, velocity, lifetime, spread, direction and colour. Beyond those, an
-- emitter's `params` and a system's `affectors` block reach the concrete Ogre
-- type's own dictionary through EXU's StringInterface bridge -- Box extents,
-- Ring inner_width, ColourFader alpha, DirectionRandomiser randomness, Scaler
-- rate. Those are what let a storm grow and churn rather than only thicken.
-- Both are optional, and both fail soft on an EXU that predates the bridge.
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
CRWeather.Layers             = {}    -- ordered oldest -> newest: { preset, weight }
CRWeather.Blend              = 0.0   -- Active's own weight; 1 = fully applied
CRWeather.BlendTarget        = 0.0
CRWeather.BlendRate          = 0.0
CRWeather.SkyApplied         = false
CRWeather.LiveSystems        = {}    -- systemName -> { spec = ..., preset = ... }
CRWeather.ModifierRegistered = false
CRWeather.OwnsEnvironment    = false -- true when Environment.lua is not present
CRWeather.BaselineFog        = nil

-- Terrain draw distance, from Environment.GetFogHorizon() when Environment.lua
-- is present and from the map's own fogEnd otherwise. Weather fog is clamped to
-- it; nothing else is. Init{ fogHorizon = false } opts out, a number overrides.
CRWeather.FogHorizon         = nil
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

-- Live wind supplied by a director (see CRMarsWeather.lua). A preset's own wind
-- is a single frozen vector, which is right for "this weather blows that way"
-- but cannot express a bearing that drifts or a gust that arrives. When an
-- override is set it replaces the preset vector for emitter direction, for
-- GetWind, and for the velocity scale below.
CRWeather.WindOverride       = nil   -- { x, y, z } unit direction
CRWeather.WindOverrideSpeed  = nil   -- world units/second
CRWeather.WindVelocityScale  = 1.0   -- live speed / preset speed, clamped
CRWeather.LastWindApplied    = nil

-- Last value written to each Ogre StringInterface parameter, keyed
-- "system|kind|index|parameter". Ogre parses every one of these back out of a
-- string, so re-sending an unchanged value costs a parse and an allocation, per
-- emitter and per affector, per frame. A storm has enough of both for that to
-- matter, and none of these values change on most frames.
CRWeather.ParamCache         = {}

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
-- Ogre StringInterface parameters
-- =============================================================================
--
-- The typed emitter setters reach the properties every emitter shares. What an
-- authored template declares beyond those -- a Box's width/height/depth, a
-- Ring's inner_width, a ColourFader's alpha rate, a DirectionRandomiser's
-- randomness, a Scaler's rate -- lives only in the concrete emitter's or
-- affector's own parameter dictionary. Before EXU exposed StringInterface those
-- were fixed for the life of the mission, so a storm could only ever get
-- denser: never larger, never more turbulent, never slower to settle.
--
-- A preset states a parameter either as a plain value, which is sent once and
-- then left alone, or as { calm, full }, which is interpolated by the layer's
-- live weight the same way rate already is.

local function ResolveParam(value, weight)
    if type(value) == "table" then
        local calm = tonumber(value[1])
        local full = tonumber(value[2])
        if calm == nil or full == nil then
            return nil
        end
        return Lerp(calm, full, Clamp01(weight))
    end
    return value
end

local function ParamKey(systemName, kind, index, parameter)
    return systemName .. "|" .. kind .. "|" .. tostring(index) .. "|" .. parameter
end

-- Ogre stores every parameter as text, so two values that differ below the
-- precision it will parse back are the same value. Comparing the formatted form
-- is therefore both cheaper and more honest than an epsilon on the number.
local function FormatParam(value)
    local kind = type(value)
    if kind == "number" then
        return string.format("%.4g", value)
    elseif kind == "boolean" then
        return value and "true" or "false"
    elseif kind == "string" then
        return value
    end
    return nil
end

local function WriteParam(setter, systemName, kind, index, parameter, value)
    local formatted = FormatParam(value)
    if formatted == nil then
        return
    end

    local key = ParamKey(systemName, kind, index, parameter)
    if CRWeather.ParamCache[key] == formatted then
        return
    end

    -- Send the value itself, not our formatted copy: EXU does its own
    -- conversion, and a round trip through %.4g would quietly truncate what
    -- Ogre ends up parsing. The formatted string is only ever the cache key.
    --
    -- Cache only on a confirmed true, so an EXU too old to have the entry point
    -- and a system Ogre has already torn down both keep retrying instead of
    -- going permanently quiet behind a cache hit.
    if Call(setter, systemName, index, parameter, value) == true then
        CRWeather.ParamCache[key] = formatted
    end
end

local function ApplyParamBlock(setter, systemName, kind, index, params, weight)
    if params == nil then
        return
    end
    for parameter, authored in pairs(params) do
        local value = ResolveParam(authored, weight)
        if value ~= nil then
            WriteParam(setter, systemName, kind, index, parameter, value)
        end
    end
end

local function ForgetParams(systemName)
    local prefix = systemName .. "|"
    local doomed = {}
    for key in pairs(CRWeather.ParamCache) do
        if string.sub(key, 1, #prefix) == prefix then
            doomed[#doomed + 1] = key
        end
    end
    for i = 1, #doomed do
        CRWeather.ParamCache[doomed[i]] = nil
    end
end

-- =============================================================================
-- Particle layer
-- =============================================================================

local function DestroySystem(systemName)
    Call("DetachParticleSystem", systemName)
    Call("DestroyParticleSystem", systemName)
    CRWeather.LiveSystems[systemName] = nil
    -- The next system to take this name is a different Ogre object carrying its
    -- own authored defaults, so nothing we sent to the old one is still true.
    ForgetParams(systemName)
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
-- Disabling an emitter is not the same as asking it for zero particles. Ogre
-- still visits a rate-zero emitter every update; a disabled one it skips
-- outright. That is what a preset means when it says its grit layer does not
-- exist below half strength, and on the templates that carry four emitters it
-- is the difference between a calm preset costing nothing and costing most of
-- what the storm costs.
local function SetEmitterEnabled(systemName, emitterIndex, wanted)
    local key = ParamKey(systemName, "emitter", emitterIndex, "@enabled")
    local formatted = wanted and "true" or "false"
    if CRWeather.ParamCache[key] == formatted then
        return
    end
    if Call("SetParticleEmitterEnabled", systemName, emitterIndex, wanted) == true then
        CRWeather.ParamCache[key] = formatted
    end
end

local function ApplyEmitterSpec(systemName, emitterIndex, emitter, weight)
    if emitter.enabledAbove ~= nil then
        local wanted = weight > emitter.enabledAbove
        SetEmitterEnabled(systemName, emitterIndex, wanted)
        if not wanted then
            -- Nothing below is observable on an emitter Ogre is not visiting,
            -- and the writes would be undone by the enable when it returns.
            return
        end
    end

    if emitter.rate ~= nil then
        Call("SetParticleEmitterEmissionRate", systemName, emitterIndex, math.max(0.0, emitter.rate * weight))
    end

    if weight <= 0.0 then
        -- Leave the rest alone while the system is silent; there is nothing to
        -- see and the writes would just be renderer churn.
        return
    end

    if emitter.velocity ~= nil then
        -- Particles ride the wind: a gust has to actually move them faster, or
        -- the only thing a gust changes is how many there are, which reads as a
        -- density flicker rather than weather.
        local scale = CRWeather.WindVelocityScale or 1.0
        Call("SetParticleEmitterVelocity", systemName, emitterIndex,
            emitter.velocity[1] * scale, emitter.velocity[2] * scale)
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

    -- Type-specific geometry last: a Box's width/height/depth, a Ring's
    -- inner_width, a Cylinder's extent. Growing the emission volume with the
    -- storm is what stops a rising preset reading as the same small cloud of
    -- dust getting thicker around the player.
    ApplyParamBlock("SetParticleEmitterParameter", systemName, "emitter", emitterIndex,
        emitter.params, weight)
end

-- Affector entries are plain parameter tables addressed by index, in the order
-- the .particle template declares them. Ogre exposes no affector names, so index
-- is all there is -- and inserting an affector above an existing one in the
-- template silently retargets whatever a preset had tuned, exactly as the
-- emitter ordering warning in cr_weather.particle describes.
local function ApplyAffectorSpec(systemName, affectorIndex, params, weight)
    if weight <= 0.0 then
        -- Same reasoning as the emitter path: nothing is on screen to affect.
        return
    end
    ApplyParamBlock("SetParticleAffectorParameter", systemName, "affector", affectorIndex,
        params, weight)
end

-- The direction the weather is actually blowing this frame: the director's
-- override when one is set, otherwise the preset's authored vector.
local function ResolveWindDirection(preset)
    if CRWeather.WindOverride ~= nil then
        return Normalized(CRWeather.WindOverride)
    end
    if preset ~= nil and preset.wind ~= nil then
        return Normalized(preset.wind)
    end
    return { x = 0.0, y = -1.0, z = 0.0 }
end

local function ApplyWindToSystem(systemName, spec, preset)
    local direction = ResolveWindDirection(preset)
    local emitters = spec.emitters or {}
    for emitterIndex in pairs(emitters) do
        Call("SetParticleEmitterDirection", systemName, emitterIndex, Vec(direction))
    end
end

-- A preset addresses emitters and affectors by index, and Ogre ignores an index
-- that is out of range without complaint: the storm simply renders with that
-- layer's tuning missing, which looks like art that needs work rather than a
-- preset that has drifted out of step with its template. Checking once, at
-- creation, is what makes that drift visible.
--
-- A nil count means this EXU predates the introspection API, which is an
-- unknown rather than a fault, so it says nothing.
local function ValidateSpecIndices(spec)
    local function check(kind, count, indexed)
        if type(count) ~= "number" then
            return
        end
        for index in pairs(indexed or {}) do
            if type(index) ~= "number" or index < 0 or index >= count then
                print("CRWeather: " .. tostring(spec.system) .. " preset addresses " .. kind ..
                    " " .. tostring(index) .. ", but template '" .. tostring(spec.template) ..
                    "' declares " .. tostring(count))
            end
        end
    end

    check("emitter", Call("GetParticleSystemEmitterCount", spec.system), spec.emitters)
    check("affector", Call("GetParticleSystemAffectorCount", spec.system), spec.affectors)
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
    ValidateSpecIndices(spec)

    local emitters = spec.emitters or {}
    for emitterIndex, emitter in pairs(emitters) do
        ApplyEmitterSpec(spec.system, emitterIndex, emitter, 0.0)
    end

    return true
end

-- Direction is pushed at creation and then only when the bearing has moved
-- enough to see. Re-sending an unchanged vector every frame for every emitter
-- is pure renderer churn, and the storm has several emitters.
local function SyncWindDirection()
    if CRWeather.WindOverride == nil then
        CRWeather.LastWindApplied = nil
        return
    end

    local direction = Normalized(CRWeather.WindOverride)
    local last = CRWeather.LastWindApplied
    if last ~= nil then
        local dot = (last.x * direction.x) + (last.y * direction.y) + (last.z * direction.z)
        -- ~1.3 degrees. Below that the change is not visible on a dust particle.
        if dot > 0.99975 then
            return
        end
    end

    for systemName, live in pairs(CRWeather.LiveSystems) do
        local emitters = live.spec.emitters or {}
        for emitterIndex in pairs(emitters) do
            Call("SetParticleEmitterDirection", systemName, emitterIndex, Vec(direction))
        end
    end

    CRWeather.LastWindApplied = direction
end

-- Every preset that still has any presence on screen, oldest first, each with
-- its own weight. One Active/Previous pair could not express the state that a
-- change part way through a transition actually produces -- the displaced
-- preset was still fading itself -- and losing that residue is what made a
-- change visible as a step.
local function LayerFor(preset)
    for i = 1, #CRWeather.Layers do
        if CRWeather.Layers[i].preset == preset then
            return CRWeather.Layers[i]
        end
    end
    return nil
end

local function LayerWeight(preset)
    local layer = LayerFor(preset)
    return layer and Clamp01(layer.weight) or 0.0
end

-- Moves every layer one step toward its target: the Active preset climbs, all
-- the others fall. Returns the presets that reached zero, whose particle
-- systems are now pure cost. Nothing here ever assigns a weight outright, which
-- is what keeps a preset change continuous.
local function StepLayers(dt)
    local step = CRWeather.BlendRate * dt
    if step <= 0.0 or #CRWeather.Layers == 0 then
        return nil
    end

    local surviving = {}
    local retired = nil
    for i = 1, #CRWeather.Layers do
        local layer = CRWeather.Layers[i]
        if layer.preset == CRWeather.Active then
            layer.weight = Clamp01(layer.weight + step)
        else
            layer.weight = Clamp01(layer.weight - step)
        end

        if layer.weight > 0.0 or layer.preset == CRWeather.Active then
            surviving[#surviving + 1] = layer
        else
            retired = retired or {}
            retired[#retired + 1] = layer.preset
        end
    end

    CRWeather.Layers = surviving
    return retired
end

local function SyncSystems(dt)
    SyncWindDirection()

    for systemName, live in pairs(CRWeather.LiveSystems) do
        local presetWeight = LayerWeight(live.preset)
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

        local affectors = live.spec.affectors or {}
        for affectorIndex, params in pairs(affectors) do
            ApplyAffectorSpec(systemName, affectorIndex, params, weight)
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

-- The horizon belongs to the terrain, so Environment -- which already parses the
-- .trn -- is asked for it first. The captured baseline is only a fallback for
-- the standalone path, where there is no Environment.lua to ask.
--
-- Returns nil when clamping is disabled or the horizon is unknown, in which
-- case weather fog is applied exactly as authored.
local function ResolveFogHorizon()
    if CRWeather.FogHorizon == false then
        return nil
    end

    local override = tonumber(CRWeather.FogHorizon)
    if override ~= nil and override > 0.0 then
        return override
    end

    local environment = rawget(_G, "Environment")
    if environment ~= nil and type(environment.GetFogHorizon) == "function" then
        local ok, horizon = pcall(environment.GetFogHorizon)
        if ok then
            horizon = tonumber(horizon)
            if horizon ~= nil and horizon > 0.0 then
                return horizon
            end
        end
    end

    local baseline = CRWeather.BaselineFog
    local fallback = baseline and tonumber(baseline.fogEnd)
    if fallback ~= nil and fallback > 0.0 then
        return fallback
    end
    return nil
end

local function ApplyPresetToFrame(frame, preset, weight)
    if preset == nil or weight <= 0.0 then
        return
    end

    if preset.fog and frame.fog then
        frame.fog.r = Lerp(frame.fog.r, preset.fog.r, weight)
        frame.fog.g = Lerp(frame.fog.g, preset.fog.g, weight)
        frame.fog.b = Lerp(frame.fog.b, preset.fog.b, weight)

        -- weatherFogEnd = min(requested, authored terrain horizon).
        --
        -- The clamp is applied to the PRESET's requested value before the
        -- blend, not to the composed frame afterwards. That is deliberate: at
        -- weight zero this contributes nothing, so a mission with weather
        -- disabled -- or standing clear -- keeps whatever base fog Environment
        -- asked for, untouched. Only the weather share is limited.
        --
        -- Presets are authored for open ground: MarsHaze finishes at 520,
        -- MarsDustRising 380, MarsDustStorm 320. On a map whose terrain stops
        -- at 250 those never reach full density before the geometry is gone,
        -- and the unfogged remainder reads as a bright band along the horizon.
        -- Measured on misn04, MarsHaze was only 37% opaque at the cut-off.
        local presetStart, presetEnd = preset.fog.fogStart, preset.fog.fogEnd
        local horizon = ResolveFogHorizon()
        if horizon ~= nil and presetEnd > horizon then
            presetEnd = horizon
            if presetStart >= horizon then
                presetStart = horizon * 0.5
            end
        end

        frame.fog.fogStart = Lerp(frame.fog.fogStart, presetStart, weight)
        frame.fog.fogEnd = Lerp(frame.fog.fogEnd, presetEnd, weight)
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

-- Mutates an Environment frame in place. Also used by the standalone path,
-- where the "frame" is a baseline snapshot instead of Environment's live target.
function CRWeather.ApplyEnvironmentContribution(frame)
    -- Oldest layer first, so the newest preset has the last word. A preset
    -- change adds a layer at weight zero and moves no existing weight, so this
    -- produces exactly the previous frame's atmosphere on the frame of the
    -- change -- which is the whole point: weather must not cut.
    local intensity = Clamp01(CRWeather.Intensity)
    for i = 1, #CRWeather.Layers do
        local layer = CRWeather.Layers[i]
        ApplyPresetToFrame(frame, layer.preset, Clamp01(layer.weight) * intensity)
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

-- Sounds are not CR's to ship: every clip a preset names belongs to the game or
-- to an addon that happens to be mounted. Warn once per name so a missing clip
-- is visible in the log without repeating on every strike.
local WarnedSounds = {}

local function WarnSoundOnce(sound, reason)
    local key = tostring(sound)
    if WarnedSounds[key] then
        return
    end
    WarnedSounds[key] = true
    print("CRWeather: thunder sound '" .. key .. "' did not play (" .. tostring(reason) .. ")")
end

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
        if StartSound == nil then
            WarnSoundOnce(thunder.sound, "StartSound is not available")
        else
            -- pcall is still needed -- StartSound raises on a name the engine
            -- cannot resolve -- but swallowing the result made a missing sound
            -- indistinguishable from a working one. A thunder clip that never
            -- plays is exactly the kind of failure nobody notices for a year,
            -- so say so once per sound name rather than once per strike.
            local ok, err = pcall(StartSound, thunder.sound)
            if not ok then
                WarnSoundOnce(thunder.sound, tostring(err))
            end
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
    -- false disables the weather-fog horizon clamp entirely; a number
    -- overrides whatever Environment or the map baseline would report.
    if options.fogHorizon ~= nil then
        CRWeather.FogHorizon = tonumber(options.fogHorizon) or false
    end

    CRWeather.Clock = 0.0
    CRWeather.Blend = 0.0
    CRWeather.BlendTarget = 0.0
    CRWeather.BlendRate = 0.0
    CRWeather.Active = nil
    CRWeather.Layers = {}
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

    -- The outgoing presets keep their systems alive so their particles fade
    -- rather than vanish; SyncSystems drives each off its own layer weight.
    -- Swapping back to a preset that is still fading reuses its layer, so it
    -- climbs from where it is instead of restarting.
    CRWeather.Active = preset
    if preset ~= nil and LayerFor(preset) == nil then
        CRWeather.Layers[#CRWeather.Layers + 1] = { preset = preset, weight = 0.0 }
    end

    local duration
    if preset ~= nil then
        duration = tonumber(transitionSeconds) or preset.transitionIn or 20.0
        CRWeather.BlendTarget = 1.0
    else
        local outgoing = CRWeather.Layers[#CRWeather.Layers]
        outgoing = outgoing and outgoing.preset or nil
        duration = tonumber(transitionSeconds) or (outgoing and outgoing.transitionOut) or 20.0
        CRWeather.BlendTarget = 0.0
    end

    duration = math.max(0.05, duration)
    CRWeather.BlendRate = 1.0 / duration
    CRWeather.Blend = LayerWeight(preset)

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

-- Authoring aid: prints what a live system actually exposes -- every emitter and
-- affector, its Ogre type, and the exact parameter spellings that build
-- registers. Preset tuning is addressed by index and spelled by name, and both
-- fail silently when wrong, so reading the truth off the running system beats
-- inferring it from the .particle file. Call it from a mission console after
-- the weather is up.
function CRWeather.DescribeSystem(systemName)
    if not HasExu("GetParticleSystemEmitterCount") then
        print("CRWeather: this EXU predates the particle introspection API")
        return false
    end

    if Call("HasParticleSystem", systemName) ~= true then
        print("CRWeather: no live particle system named '" .. tostring(systemName) .. "'")
        return false
    end

    local function describe(kind, count, typeGetter, namesGetter)
        if type(count) ~= "number" then
            print(string.format("CRWeather:   %s count unavailable", kind))
            return
        end
        for index = 0, count - 1 do
            local typeName = Call(typeGetter, systemName, index) or "?"
            local names = Call(namesGetter, systemName, index)
            local joined = "(none reported)"
            if type(names) == "table" and #names > 0 then
                table.sort(names)
                joined = table.concat(names, " ")
            end
            print(string.format("CRWeather:   %s[%d] %s: %s", kind, index, tostring(typeName), joined))
        end
    end

    print("CRWeather: " .. tostring(systemName))
    describe("emitter", Call("GetParticleSystemEmitterCount", systemName),
        "GetParticleEmitterType", "GetParticleEmitterParameterNames")
    describe("affector", Call("GetParticleSystemAffectorCount", systemName),
        "GetParticleAffectorType", "GetParticleAffectorParameterNames")
    return true
end

-- Every system the active weather currently has on screen.
function CRWeather.DescribeLiveSystems()
    local names = {}
    for systemName in pairs(CRWeather.LiveSystems) do
        names[#names + 1] = systemName
    end
    table.sort(names)
    for i = 1, #names do
        CRWeather.DescribeSystem(names[i])
    end
    return #names
end

-- Hands live wind to CRWeather. Pass a direction (need not be normalised) and
-- a speed in world units per second. The override outlives preset changes on
-- purpose: a director owns the wind for as long as it is running, and a preset
-- swap mid-gust should not snap the bearing back to the authored vector.
function CRWeather.SetWindOverride(direction, speed)
    if direction == nil then
        return CRWeather.ClearWindOverride()
    end

    CRWeather.WindOverride = {
        x = tonumber(direction.x) or 0.0,
        y = tonumber(direction.y) or 0.0,
        z = tonumber(direction.z) or 0.0,
    }
    CRWeather.WindOverrideSpeed = math.max(0.0, tonumber(speed) or 0.0)

    -- Emitter velocities are authored for the preset's own wind speed, so the
    -- override expresses itself as a ratio against that. Clamped because a calm
    -- preset with a near-zero authored speed would otherwise produce an
    -- unbounded scale the moment any wind arrived.
    local preset = CRWeather.Active
    local authored = preset and preset.windSpeed or 0.0
    if authored > 0.001 then
        local scale = CRWeather.WindOverrideSpeed / authored
        if scale < 0.35 then scale = 0.35 end
        if scale > 2.00 then scale = 2.00 end
        CRWeather.WindVelocityScale = scale
    else
        CRWeather.WindVelocityScale = 1.0
    end

    return true
end

function CRWeather.ClearWindOverride()
    CRWeather.WindOverride = nil
    CRWeather.WindOverrideSpeed = nil
    CRWeather.WindVelocityScale = 1.0
    CRWeather.LastWindApplied = nil
    return true
end

-- The wind as the world sees it: direction * speed, scaled by how much weather
-- is actually present. A director's override supplies its own speed, which it
-- has already shaped, so that path is not weighted again.
function CRWeather.GetWind()
    if CRWeather.WindOverride ~= nil then
        local direction = Normalized(CRWeather.WindOverride)
        local speed = CRWeather.WindOverrideSpeed or 0.0
        return SetVector(direction.x * speed, direction.y * speed, direction.z * speed)
    end

    local preset = CRWeather.Active
    if preset == nil or preset.wind == nil then
        return SetVector(0.0, 0.0, 0.0)
    end

    local direction = Normalized(preset.wind)
    local speed = (preset.windSpeed or 0.0) * CurrentWeight()
    return SetVector(direction.x * speed, direction.y * speed, direction.z * speed)
end

-- Scalar convenience: the same speed GetWind encodes, without the vector.
function CRWeather.GetWindSpeed()
    if CRWeather.WindOverrideSpeed ~= nil then
        return CRWeather.WindOverrideSpeed
    end
    local preset = CRWeather.Active
    return ((preset and preset.windSpeed) or 0.0) * CurrentWeight()
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

    -- A faded-out preset's systems are only worth keeping while they still
    -- contribute; past zero they are pure cost.
    local retired = StepLayers(dt)
    if retired ~= nil then
        local stale = {}
        for systemName, live in pairs(CRWeather.LiveSystems) do
            for i = 1, #retired do
                if live.preset == retired[i] then
                    stale[#stale + 1] = systemName
                    break
                end
            end
        end
        for i = 1, #stale do
            DestroySystem(stale[i])
        end
    end

    CRWeather.Blend = LayerWeight(CRWeather.Active)

    SyncSystems(dt)
    SyncSky()
    UpdateLightning()

    if CRWeather.OwnsEnvironment then
        WriteEnvironmentDirect()
    end
end

-- Drops all particle bookkeeping so the next preset application rebuilds from
-- nothing. This exists for the save-load path: loading a save tears the Ogre
-- scene down and rebuilds it, which takes our particle systems with it, but
-- LiveSystems still names them. CreateSystem would then find an "existing"
-- entry and retarget a system that is no longer there, and the weather would
-- silently never render again.
function CRWeather.ResetSystems()
    DestroyAllSystems()
    CRWeather.Active = nil
    CRWeather.Layers = {}
    CRWeather.Blend = 0.0
    CRWeather.BlendTarget = 0.0
    CRWeather.BlendRate = 0.0
    CRWeather.SkyApplied = false
    CRWeather.LastWindApplied = nil
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
        CRWeather.Layers = {}
        CRWeather.Blend = 0.0
        CRWeather.FlashUntil = nil
        WriteEnvironmentDirect()
    end

    CRWeather.Active = nil
    CRWeather.Layers = {}
    CRWeather.Blend = 0.0
    CRWeather.BlendTarget = 0.0
    CRWeather.BlendRate = 0.0
    CRWeather.NextStrikeAt = nil
    CRWeather.FlashUntil = nil
    CRWeather.PendingThunder = nil
    CRWeather.ClearWindOverride()
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

        -- SetPreset appends the layer at zero and lets Update ramp it. A load is
        -- the one place that legitimately assigns a weight outright.
        local layer = LayerFor(CRWeather.Active)
        if layer ~= nil then
            layer.weight = CRWeather.Blend
        end
    end
end

-- Compatibility stubs so a mission can call the same lifecycle shape it uses
-- for the other CR modules without guarding every call.
function CRWeather.OnObjectCreated(h) end

return CRWeather
