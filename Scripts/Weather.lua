-- Weather.lua
---@diagnostic disable: lowercase-global, undefined-global

local exu = require("exu")

local Weather = {}
Weather.__index = Weather

local function Vec(x, y, z)
    if type(SetVector) == "function" then
        return SetVector(x, y, z)
    end
    return { x = x, y = y, z = z }
end

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

local function MergeTables(base, overrides)
    local result = DeepCopy(base or {})
    if type(overrides) ~= "table" then
        return result
    end

    for k, v in pairs(overrides) do
        if type(v) == "table" and type(result[k]) == "table" then
            result[k] = MergeTables(result[k], v)
        else
            result[k] = DeepCopy(v)
        end
    end
    return result
end

local function Clamp01(value)
    if value < 0.0 then return 0.0 end
    if value > 1.0 then return 1.0 end
    return value
end

local function Lerp(a, b, t)
    return a + ((b - a) * t)
end

local function LerpColor(a, b, t)
    return {
        r = Lerp(a.r, b.r, t),
        g = Lerp(a.g, b.g, t),
        b = Lerp(a.b, b.b, t),
    }
end

local function LerpVector(a, b, t)
    return Vec(
        Lerp(a.x, b.x, t),
        Lerp(a.y, b.y, t),
        Lerp(a.z, b.z, t)
    )
end

local function NormalizeVector(v)
    local x = tonumber(v and v.x) or 0.0
    local y = tonumber(v and v.y) or 0.0
    local z = tonumber(v and v.z) or 0.0
    local len = math.sqrt((x * x) + (y * y) + (z * z))
    if len <= 0.0001 then
        return Vec(0.0, -1.0, 0.0)
    end

    return Vec(x / len, y / len, z / len)
end

local function AddVectors(a, b)
    return Vec(
        (a and a.x or 0.0) + (b and b.x or 0.0),
        (a and a.y or 0.0) + (b and b.y or 0.0),
        (a and a.z or 0.0) + (b and b.z or 0.0)
    )
end

local function NormalizeColor(value, fallback)
    local source = value or fallback or {}
    return {
        r = Clamp01(tonumber(source.r) or tonumber(source[1]) or (fallback and fallback.r) or 0.0),
        g = Clamp01(tonumber(source.g) or tonumber(source[2]) or (fallback and fallback.g) or 0.0),
        b = Clamp01(tonumber(source.b) or tonumber(source[3]) or (fallback and fallback.b) or 0.0),
    }
end

local function NormalizeFog(value, fallback)
    local source = value or fallback or {}
    local defaultFog = fallback or { r = 0.65, g = 0.45, b = 0.25, fogStart = 200.0, fogEnd = 700.0 }
    local fogStart = tonumber(source.fogStart) or tonumber(source.start) or defaultFog.fogStart
    local fogEnd = tonumber(source.fogEnd) or tonumber(source.ending) or defaultFog.fogEnd
    fogStart = math.max(1.0, fogStart)
    fogEnd = math.max(fogStart + 1.0, fogEnd)

    return {
        r = Clamp01(tonumber(source.r) or defaultFog.r),
        g = Clamp01(tonumber(source.g) or defaultFog.g),
        b = Clamp01(tonumber(source.b) or defaultFog.b),
        fogStart = fogStart,
        fogEnd = fogEnd,
    }
end

local function TintScaleColor(base, tint, scale)
    local baseColor = NormalizeColor(base)
    local tintColor = NormalizeColor(tint, { r = 1.0, g = 1.0, b = 1.0 })
    local appliedScale = tonumber(scale) or 1.0
    return NormalizeColor({
        r = baseColor.r * tintColor.r * appliedScale,
        g = baseColor.g * tintColor.g * appliedScale,
        b = baseColor.b * tintColor.b * appliedScale,
    })
end

local function TintFog(base, tint, startScale, endScale)
    local baseFog = NormalizeFog(base)
    local tintColor = NormalizeColor(tint, { r = 1.0, g = 1.0, b = 1.0 })
    local appliedStartScale = tonumber(startScale) or 1.0
    local appliedEndScale = tonumber(endScale) or 1.0
    return NormalizeFog({
        r = baseFog.r * tintColor.r,
        g = baseFog.g * tintColor.g,
        b = baseFog.b * tintColor.b,
        fogStart = baseFog.fogStart * appliedStartScale,
        fogEnd = baseFog.fogEnd * appliedEndScale,
    }, baseFog)
end

local function BlendFog(a, b, t)
    return NormalizeFog({
        r = Lerp(a.r, b.r, t),
        g = Lerp(a.g, b.g, t),
        b = Lerp(a.b, b.b, t),
        fogStart = Lerp(a.fogStart, b.fogStart, t),
        fogEnd = Lerp(a.fogEnd, b.fogEnd, t),
    }, a)
end

local function BlendAtmosphere(a, b, t)
    return {
        ambient = LerpColor(a.ambient, b.ambient, t),
        diffuse = LerpColor(a.diffuse, b.diffuse, t),
        specular = LerpColor(a.specular, b.specular, t),
        fog = BlendFog(a.fog, b.fog, t),
        sunDirection = NormalizeVector(LerpVector(a.sunDirection, b.sunDirection, t)),
        powerScale = Lerp(a.powerScale, b.powerScale, t),
        shadowFarDistance = Lerp(a.shadowFarDistance, b.shadowFarDistance, t),
        viewportShadows = (t < 0.5) and a.viewportShadows or b.viewportShadows,
    }
end

local function RandomRange(minimum, maximum)
    local low = tonumber(minimum) or 0.0
    local high = tonumber(maximum) or low
    if high <= low then
        return low
    end
    return low + ((high - low) * math.random())
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then
        return false, "missing"
    end
    return pcall(fn, ...)
end

Weather.DefaultConfig = {
    id = "weather",
    resourceGroup = "General",
    followPlayer = true,
    playerTeam = nil,
    useSkyPlaneWhenSafe = true,
    forceSkyPlaneOverride = false,
    particleTemplates = {
        rain = "Weather/Rain/Heavy",
        snow = "Weather/Snow/Light",
        dust = "Weather/Dust/Loop",
    },
    cloudPlane = {
        normal = Vec(0.0, -1.0, 0.0),
        d = 1450.0,
        scale = 2400.0,
        tiling = 2.2,
        drawFirst = true,
        bow = 0.0,
        xsegments = 8,
        ysegments = 8,
    },
    defaultParticleOffset = Vec(0.0, 60.0, 0.0),
    defaultLightning = {
        enabled = false,
        minInterval = 8.0,
        maxInterval = 15.0,
        intensity = 1.0,
        hold = 0.05,
        fade = 0.18,
        secondaryDelay = 0.24,
        secondaryIntensity = 0.55,
        secondaryHold = 0.03,
        secondaryFade = 0.12,
        ambientColor = { r = 0.80, g = 0.84, b = 1.0 },
        diffuseColor = { r = 1.0, g = 0.97, b = 0.92 },
        specularColor = { r = 1.0, g = 1.0, b = 1.0 },
        fogColor = { r = 0.76, g = 0.80, b = 0.90 },
        powerBoost = 0.95,
    },
}

local function BuildClearPreset(self)
    return {
        atmosphere = DeepCopy(self.state.baseline.atmosphere),
        cloud = nil,
        particles = {},
        lightning = nil,
    }
end

local function BuildOvercastPreset(self)
    local base = self.state.baseline.atmosphere
    return {
        atmosphere = {
            ambient = TintScaleColor(base.ambient, { r = 0.88, g = 0.90, b = 0.96 }, 0.78),
            diffuse = TintScaleColor(base.diffuse, { r = 0.82, g = 0.86, b = 0.94 }, 0.72),
            specular = TintScaleColor(base.specular, { r = 0.78, g = 0.82, b = 0.92 }, 0.50),
            fog = TintFog(base.fog, { r = 0.70, g = 0.76, b = 0.88 }, 0.72, 0.86),
            sunDirection = NormalizeVector(Vec(0.35, -0.84, -0.42)),
            powerScale = (base.powerScale or 1.0) * 0.82,
            shadowFarDistance = (base.shadowFarDistance or 800.0) * 0.72,
            viewportShadows = true,
        },
        cloud = {
            key = "overcast",
            material = "ACLOUD2.MAP",
            scroll = { u = 0.0014, v = 0.0 },
            plane = MergeTables(self.config.cloudPlane, {}),
        },
        particles = {},
        lightning = nil,
    }
end

local function BuildRainPreset(self)
    local base = self.state.baseline.atmosphere
    local preset = BuildOvercastPreset(self)
    preset.atmosphere.ambient = TintScaleColor(base.ambient, { r = 0.78, g = 0.82, b = 0.92 }, 0.70)
    preset.atmosphere.diffuse = TintScaleColor(base.diffuse, { r = 0.72, g = 0.78, b = 0.90 }, 0.64)
    preset.atmosphere.specular = TintScaleColor(base.specular, { r = 0.92, g = 0.96, b = 1.0 }, 0.62)
    preset.atmosphere.fog = TintFog(base.fog, { r = 0.60, g = 0.66, b = 0.78 }, 0.48, 0.64)
    preset.atmosphere.powerScale = (base.powerScale or 1.0) * 0.72
    preset.atmosphere.shadowFarDistance = (base.shadowFarDistance or 800.0) * 0.58
    preset.cloud.material = "ACLOUD.MAP"
    preset.cloud.scroll = { u = 0.0019, v = 0.0 }
    preset.particles = {
        rain = {
            template = self.config.particleTemplates.rain,
            offset = Vec(0.0, 70.0, 0.0),
            keepLocalSpace = false,
            speedFactor = 1.0,
            renderQueueGroup = 95,
            dimensions = { width = 1.5, height = 14.0 },
            material = "raindrop.tga",
        },
    }
    return preset
end

local function BuildLightningStormPreset(self)
    local preset = BuildRainPreset(self)
    preset.lightning = MergeTables(self.config.defaultLightning, {
        enabled = true,
        minInterval = 6.0,
        maxInterval = 11.0,
        powerBoost = 1.10,
    })
    return preset
end

local function BuildSnowPreset(self)
    local base = self.state.baseline.atmosphere
    local preset = BuildOvercastPreset(self)
    preset.atmosphere.ambient = TintScaleColor(base.ambient, { r = 0.92, g = 0.94, b = 1.0 }, 0.82)
    preset.atmosphere.diffuse = TintScaleColor(base.diffuse, { r = 0.90, g = 0.94, b = 1.0 }, 0.78)
    preset.atmosphere.specular = TintScaleColor(base.specular, { r = 0.94, g = 0.97, b = 1.0 }, 0.60)
    preset.atmosphere.fog = TintFog(base.fog, { r = 0.82, g = 0.88, b = 0.98 }, 0.56, 0.72)
    preset.atmosphere.powerScale = (base.powerScale or 1.0) * 0.74
    preset.atmosphere.shadowFarDistance = (base.shadowFarDistance or 800.0) * 0.64
    preset.cloud.material = "ACLOUD2.MAP"
    preset.cloud.scroll = { u = 0.0008, v = 0.0 }
    preset.particles = {
        snow = {
            template = self.config.particleTemplates.snow,
            offset = Vec(0.0, 65.0, 0.0),
            keepLocalSpace = false,
            speedFactor = 1.0,
            renderQueueGroup = 95,
            dimensions = { width = 5.0, height = 5.0 },
            material = "particle_bz2.tga",
            direction = Vec(0.0, -1.0, 0.0),
        },
    }
    return preset
end

local function BuildDustStormPreset(self)
    local base = self.state.baseline.atmosphere
    local plane = MergeTables(self.config.cloudPlane, {
        d = 900.0,
        scale = 1800.0,
        tiling = 6.0,
        bow = 0.12,
    })

    return {
        atmosphere = {
            ambient = NormalizeColor({ r = 0.34, g = 0.24, b = 0.14 }),
            diffuse = NormalizeColor({ r = 0.64, g = 0.46, b = 0.24 }),
            specular = NormalizeColor({ r = 0.18, g = 0.12, b = 0.08 }),
            fog = NormalizeFog({
                r = 0.52,
                g = 0.34,
                b = 0.18,
                fogStart = math.max(5.0, base.fog.fogStart * 0.08),
                fogEnd = math.max(60.0, base.fog.fogEnd * 0.14),
            }, base.fog),
            sunDirection = NormalizeVector(Vec(0.24, -0.58, -0.78)),
            powerScale = (base.powerScale or 1.0) * 0.58,
            shadowFarDistance = (base.shadowFarDistance or 800.0) * 0.22,
            viewportShadows = false,
        },
        cloud = {
            key = "dust",
            material = "vsmoke2.tga",
            scroll = { u = 0.008, v = 0.0015 },
            plane = plane,
        },
        particles = {
            dust = {
                template = self.config.particleTemplates.dust,
                offset = Vec(0.0, 38.0, 0.0),
                keepLocalSpace = false,
                speedFactor = 1.0,
                renderQueueGroup = 96,
                dimensions = { width = 22.0, height = 22.0 },
                material = "dust",
            },
        },
        lightning = nil,
    }
end

Weather.PresetBuilders = {
    clear = BuildClearPreset,
    overcast = BuildOvercastPreset,
    rain = BuildRainPreset,
    lightning_storm = BuildLightningStormPreset,
    snow = BuildSnowPreset,
    dust_storm = BuildDustStormPreset,
}

function Weather.New(config)
    local self = setmetatable({}, Weather)
    self.config = MergeTables(Weather.DefaultConfig, config or {})
    self.state = {
        baseline = nil,
        currentAtmosphere = nil,
        currentPresetName = "clear",
        currentPreset = nil,
        transition = nil,
        anchor = nil,
        ownedMaterials = {},
        activeParticles = {},
        activeCloud = nil,
        warnings = {},
        lightning = nil,
        lightningFlash = nil,
        lastUpdateTime = nil,
    }
    self:CaptureBaseline()
    self:ApplyPreset("clear")
    return self
end

Weather.Create = Weather.New

function Weather:_warnOnce(key, message)
    if self.state.warnings[key] then
        return
    end
    self.state.warnings[key] = true
    print("Weather: " .. tostring(message))
end

function Weather:_supportsEnvironment()
    return type(exu) == "table"
        and type(exu.SetFog) == "function"
        and (type(exu.SetAmbientLight) == "function" or type(exu.SetSunAmbient) == "function")
        and type(exu.SetSunDiffuse) == "function"
        and type(exu.SetSunSpecular) == "function"
        and (type(exu.SetOgreSunDirection) == "function" or type(exu.SetSunDirection) == "function")
end

function Weather:_getAmbientSetter()
    return exu.SetAmbientLight or exu.SetSunAmbient
end

function Weather:_getSunDirectionSetter()
    return exu.SetOgreSunDirection or exu.SetSunDirection
end

function Weather:_captureAtmosphere()
    local fogOk, fogValue = SafeCall(exu.GetFog)
    local ambientOk, ambientValue = SafeCall(exu.GetAmbientLight or exu.GetSunAmbient)
    local diffuseOk, diffuseValue = SafeCall(exu.GetSunDiffuse)
    local specularOk, specularValue = SafeCall(exu.GetSunSpecular)
    local directionOk, directionValue = SafeCall(exu.GetSunDirection)
    local powerOk, powerValue = SafeCall(exu.GetSunPowerScale)
    local shadowOk, shadowValue = SafeCall(exu.GetSunShadowFarDistance)
    local viewportOk, viewportValue = SafeCall(exu.GetViewportShadowsEnabled)

    return {
        ambient = NormalizeColor(ambientOk and ambientValue or nil, { r = 0.5, g = 0.5, b = 0.5 }),
        diffuse = NormalizeColor(diffuseOk and diffuseValue or nil, { r = 0.5, g = 0.5, b = 0.5 }),
        specular = NormalizeColor(specularOk and specularValue or nil, { r = 0.5, g = 0.5, b = 0.5 }),
        fog = NormalizeFog(fogOk and fogValue or nil, { r = 0.65, g = 0.45, b = 0.25, fogStart = 200.0, fogEnd = 700.0 }),
        sunDirection = NormalizeVector(directionOk and directionValue or Vec(0.62, -0.73, -0.29)),
        powerScale = tonumber(powerOk and powerValue or nil) or 1.0,
        shadowFarDistance = tonumber(shadowOk and shadowValue or nil) or 800.0,
        viewportShadows = viewportOk and not not viewportValue or true,
    }
end

function Weather:_captureSkyState()
    local skyPlaneEnabledOk, skyPlaneEnabled = SafeCall(exu.GetSkyPlaneEnabled)
    local skyDomeEnabledOk, skyDomeEnabled = SafeCall(exu.GetSkyDomeEnabled)
    local skyBoxEnabledOk, skyBoxEnabled = SafeCall(exu.GetSkyBoxEnabled)
    local skyPlaneParamsOk, skyPlaneParams = SafeCall(exu.GetSkyPlaneParams)

    return {
        skyPlaneEnabled = skyPlaneEnabledOk and not not skyPlaneEnabled or false,
        skyDomeEnabled = skyDomeEnabledOk and not not skyDomeEnabled or false,
        skyBoxEnabled = skyBoxEnabledOk and not not skyBoxEnabled or false,
        skyPlaneParams = skyPlaneParamsOk and skyPlaneParams or nil,
    }
end

function Weather:CaptureBaseline()
    if not self:_supportsEnvironment() then
        self:_warnOnce("missing_exu_environment", "EXU weather environment controls are unavailable")
        return false
    end

    self.state.baseline = {
        atmosphere = self:_captureAtmosphere(),
        sky = self:_captureSkyState(),
    }
    self.state.currentAtmosphere = DeepCopy(self.state.baseline.atmosphere)
    return true
end

function Weather:SetAnchor(anchor)
    self.state.anchor = anchor
end

function Weather:_resolveAnchorPosition()
    local anchor = self.state.anchor
    if type(anchor) == "function" then
        local ok, resolved = pcall(anchor, self)
        if ok then
            anchor = resolved
        else
            self:_warnOnce("anchor_callback_failed", "anchor callback failed: " .. tostring(resolved))
            anchor = nil
        end
    end

    if type(anchor) == "table" and anchor.x ~= nil and anchor.y ~= nil and anchor.z ~= nil then
        return Vec(anchor.x, anchor.y, anchor.z)
    end

    if type(anchor) == "string" and type(GetPosition) == "function" then
        local ok, pos = pcall(GetPosition, anchor)
        if ok and type(pos) == "table" and pos.x ~= nil then
            return Vec(pos.x, pos.y, pos.z)
        end
    end

    if type(anchor) == "userdata" and type(IsValid) == "function" and IsValid(anchor) and type(GetPosition) == "function" then
        local ok, pos = pcall(GetPosition, anchor)
        if ok and type(pos) == "table" and pos.x ~= nil then
            return Vec(pos.x, pos.y, pos.z)
        end
    end

    if self.config.followPlayer and type(GetPlayerHandle) == "function" and type(GetPosition) == "function" then
        local player = GetPlayerHandle(self.config.playerTeam)
        if player and type(IsValid) == "function" and IsValid(player) then
            local ok, pos = pcall(GetPosition, player)
            if ok and type(pos) == "table" and pos.x ~= nil then
                return Vec(pos.x, pos.y, pos.z)
            end
        end
    end

    return nil
end

function Weather:_canOverrideSkyPlane()
    if not self.config.useSkyPlaneWhenSafe then
        return false
    end

    local baselineSky = self.state.baseline and self.state.baseline.sky or nil
    if not baselineSky then
        return false
    end

    local anySkyEnabled = baselineSky.skyPlaneEnabled or baselineSky.skyDomeEnabled or baselineSky.skyBoxEnabled
    if anySkyEnabled and not self.config.forceSkyPlaneOverride then
        return false
    end

    if anySkyEnabled and self.config.forceSkyPlaneOverride then
        self:_warnOnce("forced_sky_override", "forcing sky-plane weather over an existing map sky; restore may be incomplete")
    end

    return true
end

function Weather:_materialExists(materialName)
    local ok, exists = SafeCall(exu.MaterialExists, materialName, self.config.resourceGroup)
    return ok and exists == true
end

function Weather:_resolveOwnedMaterial(key, baseMaterial)
    if type(baseMaterial) ~= "string" or baseMaterial == "" then
        return nil
    end

    local owned = self.state.ownedMaterials[key]
    if owned and self:_materialExists(owned) then
        return owned
    end

    if not self:_materialExists(baseMaterial) then
        self:_warnOnce("missing_material_" .. key, "material not found: " .. tostring(baseMaterial))
        return nil
    end

    if type(exu.CloneMaterial) ~= "function" then
        return baseMaterial
    end

    local cloneName = "__weather_" .. tostring(self.config.id or "weather") .. "_" .. tostring(key)
    if not self:_materialExists(cloneName) then
        local ok, cloned = SafeCall(exu.CloneMaterial, baseMaterial, cloneName, self.config.resourceGroup)
        if not ok or cloned == false then
            self:_warnOnce("clone_failed_" .. key, "failed to clone weather material " .. tostring(baseMaterial) .. "; using the source material directly")
            return baseMaterial
        end
    end

    self.state.ownedMaterials[key] = cloneName
    return cloneName
end

function Weather:_applyCloudState(cloud)
    if type(exu.SetSkyPlane) ~= "function" or type(exu.SetSkyPlaneEnabled) ~= "function" then
        if cloud then
            self:_warnOnce("missing_skyplane_support", "sky-plane controls are unavailable; skipping cloud layer")
        end
        return
    end

    if not cloud then
        if self.state.activeCloud and self.state.activeCloud.created and self.state.baseline and not self.state.baseline.sky.skyPlaneEnabled then
            SafeCall(exu.SetSkyPlaneEnabled, false)
        end
        self.state.activeCloud = nil
        return
    end

    if not self:_canOverrideSkyPlane() then
        self:_warnOnce("clouds_skipped_existing_sky", "cloud layer skipped because the map already has a sky system; set forceSkyPlaneOverride=true to override anyway")
        self.state.activeCloud = nil
        return
    end

    local plane = MergeTables(self.config.cloudPlane, cloud.plane or {})
    local materialName = self:_resolveOwnedMaterial("cloud_" .. tostring(cloud.key or "layer"), cloud.material)
    if not materialName then
        return
    end

    local ok, result = SafeCall(
        exu.SetSkyPlane,
        materialName,
        {
            normal = plane.normal or Vec(0.0, -1.0, 0.0),
            d = plane.d or plane.distance or self.config.cloudPlane.d,
        },
        plane.scale or self.config.cloudPlane.scale,
        plane.tiling or self.config.cloudPlane.tiling,
        plane.drawFirst ~= false,
        plane.bow or self.config.cloudPlane.bow,
        plane.xsegments or self.config.cloudPlane.xsegments,
        plane.ysegments or self.config.cloudPlane.ysegments,
        self.config.resourceGroup
    )

    if not ok or result == false then
        self:_warnOnce("cloud_apply_failed", "failed to apply weather cloud layer")
        return
    end

    SafeCall(exu.SetSkyPlaneEnabled, true)
    if cloud.scroll and type(exu.SetMaterialTextureScrollAnimation) == "function" then
        SafeCall(exu.SetMaterialTextureScrollAnimation, materialName, cloud.scroll.u or 0.0, cloud.scroll.v or 0.0, 0, 0, 0, self.config.resourceGroup)
    end

    self.state.activeCloud = {
        created = true,
        materialName = materialName,
    }
end

function Weather:_applyAtmosphere(atmosphere)
    if not atmosphere or not self:_supportsEnvironment() then
        return
    end

    local ambientSetter = self:_getAmbientSetter()
    local sunDirectionSetter = self:_getSunDirectionSetter()

    SafeCall(ambientSetter, atmosphere.ambient.r, atmosphere.ambient.g, atmosphere.ambient.b)
    SafeCall(exu.SetSunDiffuse, atmosphere.diffuse.r, atmosphere.diffuse.g, atmosphere.diffuse.b)
    SafeCall(exu.SetSunSpecular, atmosphere.specular.r, atmosphere.specular.g, atmosphere.specular.b)
    SafeCall(exu.SetFog, atmosphere.fog.r, atmosphere.fog.g, atmosphere.fog.b, atmosphere.fog.fogStart, atmosphere.fog.fogEnd)
    SafeCall(sunDirectionSetter, atmosphere.sunDirection.x, atmosphere.sunDirection.y, atmosphere.sunDirection.z)
    if type(exu.SetSunPowerScale) == "function" then
        SafeCall(exu.SetSunPowerScale, atmosphere.powerScale)
    end
    if type(exu.SetSunShadowFarDistance) == "function" then
        SafeCall(exu.SetSunShadowFarDistance, atmosphere.shadowFarDistance)
    end
    if type(exu.SetViewportShadowsEnabled) == "function" then
        SafeCall(exu.SetViewportShadowsEnabled, atmosphere.viewportShadows)
    end
end

function Weather:_resolveParticleTemplate(spec, slot)
    if spec and spec.template and spec.template ~= "" then
        return spec.template
    end

    local configured = self.config.particleTemplates and self.config.particleTemplates[slot]
    if configured and configured ~= "" then
        return configured
    end

    self:_warnOnce("missing_particle_template_" .. tostring(slot), "no particle template configured for weather slot '" .. tostring(slot) .. "'")
    return nil
end

function Weather:_syncParticles(particles)
    local desired = {}
    for slot, spec in pairs(particles or {}) do
        local template = self:_resolveParticleTemplate(spec, slot)
        if template then
            desired[slot] = MergeTables(spec, { template = template })
        end
    end

    for slot, active in pairs(self.state.activeParticles) do
        if not desired[slot] then
            SafeCall(exu.DestroyParticleSystem, active.name)
            self.state.activeParticles[slot] = nil
        end
    end

    for slot, spec in pairs(desired) do
        local particleName = "__weather_" .. tostring(self.config.id or "weather") .. "_ps_" .. tostring(slot)
        local initialPos = AddVectors(self:_resolveAnchorPosition() or Vec(0.0, 0.0, 0.0), spec.offset or self.config.defaultParticleOffset)
        local ready = true
        local okHas, exists = SafeCall(exu.HasParticleSystem, particleName)
        if not okHas or exists ~= true then
            local okCreate, created = SafeCall(exu.CreateParticleSystem, particleName, spec.template, initialPos)
            if not okCreate or created == false then
                self:_warnOnce("particle_create_failed_" .. tostring(slot), "failed to create particle system '" .. tostring(spec.template) .. "' for slot '" .. tostring(slot) .. "'")
                ready = false
            end
        end

        if ready then
            if type(exu.SetParticleSystemKeepLocalSpace) == "function" then
                SafeCall(exu.SetParticleSystemKeepLocalSpace, particleName, spec.keepLocalSpace == true)
            end
            if type(exu.SetParticleSystemSpeedFactor) == "function" and spec.speedFactor then
                SafeCall(exu.SetParticleSystemSpeedFactor, particleName, spec.speedFactor)
            end
            if type(exu.SetParticleSystemRenderQueueGroup) == "function" and spec.renderQueueGroup then
                SafeCall(exu.SetParticleSystemRenderQueueGroup, particleName, spec.renderQueueGroup)
            end
            if type(exu.SetParticleSystemDefaultDimensions) == "function" and spec.dimensions then
                SafeCall(exu.SetParticleSystemDefaultDimensions, particleName, spec.dimensions.width, spec.dimensions.height)
            end
            if type(exu.SetParticleSystemMaterial) == "function" and spec.material then
                SafeCall(exu.SetParticleSystemMaterial, particleName, spec.material, self.config.resourceGroup)
            end
            if type(exu.SetParticleSystemEmitting) == "function" then
                SafeCall(exu.SetParticleSystemEmitting, particleName, true)
            end
            if type(exu.SetParticleSystemVisible) == "function" then
                SafeCall(exu.SetParticleSystemVisible, particleName, true)
            end

            self.state.activeParticles[slot] = {
                name = particleName,
                spec = DeepCopy(spec),
            }
        end
    end
end

function Weather:_updateParticles()
    local anchorPos = self:_resolveAnchorPosition()
    if not anchorPos then
        return
    end

    for _, active in pairs(self.state.activeParticles) do
        local particlePos = AddVectors(anchorPos, active.spec.offset or self.config.defaultParticleOffset)
        if type(exu.SetParticleSystemPosition) == "function" then
            SafeCall(exu.SetParticleSystemPosition, active.name, particlePos)
        end
        if type(exu.SetParticleSystemDirection) == "function" and active.spec.direction then
            local dir = NormalizeVector(active.spec.direction)
            SafeCall(exu.SetParticleSystemDirection, active.name, dir)
        end
    end
end

function Weather:_configureLightning(lightning)
    if type(lightning) ~= "table" or not lightning.enabled then
        self.state.lightning = nil
        self.state.lightningFlash = nil
        return
    end

    local now = type(GetTime) == "function" and GetTime() or 0.0
    local config = MergeTables(self.config.defaultLightning, lightning)
    self.state.lightning = {
        config = config,
        nextFlashAt = now + RandomRange(config.minInterval, config.maxInterval),
    }
end

function Weather:TriggerLightning(options)
    local config = MergeTables(self.config.defaultLightning, options or {})
    local now = type(GetTime) == "function" and GetTime() or 0.0
    local pulses = {
        {
            delay = 0.0,
            intensity = config.intensity or 1.0,
            hold = config.hold or 0.05,
            fade = config.fade or 0.18,
        },
    }

    if (config.secondaryIntensity or 0.0) > 0.0 then
        pulses[#pulses + 1] = {
            delay = config.secondaryDelay or 0.24,
            intensity = config.secondaryIntensity,
            hold = config.secondaryHold or 0.03,
            fade = config.secondaryFade or 0.12,
        }
    end

    self.state.lightningFlash = {
        startTime = now,
        pulses = pulses,
        config = config,
    }

    if self.state.lightning and self.state.lightning.config then
        self.state.lightning.nextFlashAt = now + RandomRange(self.state.lightning.config.minInterval, self.state.lightning.config.maxInterval)
    end
end

function Weather:_getLightningAmount(now)
    local flash = self.state.lightningFlash
    if not flash then
        return 0.0, nil
    end

    local elapsed = now - flash.startTime
    local amount = 0.0
    local anyActive = false

    for _, pulse in ipairs(flash.pulses) do
        local pulseElapsed = elapsed - pulse.delay
        if pulseElapsed >= 0.0 then
            if pulseElapsed <= pulse.hold then
                amount = math.max(amount, pulse.intensity)
                anyActive = true
            elseif pulseElapsed <= (pulse.hold + pulse.fade) then
                local t = (pulseElapsed - pulse.hold) / pulse.fade
                amount = math.max(amount, pulse.intensity * (1.0 - t))
                anyActive = true
            end
        else
            anyActive = true
        end
    end

    if not anyActive then
        self.state.lightningFlash = nil
        return 0.0, nil
    end

    return amount, flash.config
end

function Weather:_applyLightningOverlay(atmosphere, amount, lightningConfig)
    if amount <= 0.0 or not lightningConfig then
        return atmosphere
    end

    local result = DeepCopy(atmosphere)
    result.ambient = LerpColor(result.ambient, NormalizeColor(lightningConfig.ambientColor), amount)
    result.diffuse = LerpColor(result.diffuse, NormalizeColor(lightningConfig.diffuseColor), amount)
    result.specular = LerpColor(result.specular, NormalizeColor(lightningConfig.specularColor), amount)
    result.fog = BlendFog(result.fog, NormalizeFog({
        r = lightningConfig.fogColor.r,
        g = lightningConfig.fogColor.g,
        b = lightningConfig.fogColor.b,
        fogStart = result.fog.fogStart,
        fogEnd = result.fog.fogEnd,
    }, result.fog), amount)
    result.powerScale = result.powerScale + ((lightningConfig.powerBoost or 0.95) * amount)
    return result
end

function Weather:_buildPreset(name, overrides)
    local builder = Weather.PresetBuilders[name] or Weather.PresetBuilders.clear
    local preset = builder(self)
    if overrides then
        preset = MergeTables(preset, overrides)
    end
    return preset
end

function Weather:ApplyPreset(name, overrides)
    return self:TransitionToPreset(name, 0.0, overrides)
end

function Weather:TransitionToPreset(name, duration, overrides)
    if not self.state.baseline then
        if not self:CaptureBaseline() then
            return false
        end
    end

    local presetName = tostring(name or "clear")
    local preset = self:_buildPreset(presetName, overrides)
    self.state.currentPresetName = presetName
    self.state.currentPreset = preset
    self:_applyCloudState(preset.cloud)
    self:_syncParticles(preset.particles)
    self:_configureLightning(preset.lightning)

    local appliedDuration = tonumber(duration) or 0.0
    if appliedDuration > 0.0 and self.state.currentAtmosphere then
        self.state.transition = {
            from = DeepCopy(self.state.currentAtmosphere),
            to = DeepCopy(preset.atmosphere),
            elapsed = 0.0,
            duration = appliedDuration,
        }
        return true
    end

    self.state.transition = nil
    self.state.currentAtmosphere = DeepCopy(preset.atmosphere)
    self:_applyAtmosphere(self.state.currentAtmosphere)
    return true
end

function Weather:Clear(duration)
    return self:TransitionToPreset("clear", duration or 0.0)
end

function Weather:SetLightningEnabled(enabled, options)
    if not enabled then
        self.state.lightning = nil
        self.state.lightningFlash = nil
        return
    end

    self:_configureLightning(MergeTables(options or {}, { enabled = true }))
end

function Weather:Update(dt)
    if not self.state.baseline then
        if not self:CaptureBaseline() then
            return
        end
    end

    local now = type(GetTime) == "function" and GetTime() or 0.0
    local timestep = tonumber(dt)
    if not timestep then
        if self.state.lastUpdateTime then
            timestep = math.max(0.0, now - self.state.lastUpdateTime)
        else
            timestep = 0.0
        end
    end
    self.state.lastUpdateTime = now

    if self.state.transition then
        self.state.transition.elapsed = self.state.transition.elapsed + timestep
        local t = Clamp01(self.state.transition.elapsed / self.state.transition.duration)
        self.state.currentAtmosphere = BlendAtmosphere(self.state.transition.from, self.state.transition.to, t)
        if t >= 1.0 then
            self.state.transition = nil
        end
    elseif self.state.currentPreset and self.state.currentPreset.atmosphere then
        self.state.currentAtmosphere = DeepCopy(self.state.currentPreset.atmosphere)
    end

    if self.state.lightning and self.state.lightning.config and now >= (self.state.lightning.nextFlashAt or now + 99999) then
        self:TriggerLightning(self.state.lightning.config)
    end

    local lightningAmount, lightningConfig = self:_getLightningAmount(now)
    local appliedAtmosphere = self:_applyLightningOverlay(self.state.currentAtmosphere, lightningAmount, lightningConfig)
    self:_applyAtmosphere(appliedAtmosphere)
    self:_updateParticles()
end

function Weather:Destroy(restoreBaseline)
    for _, active in pairs(self.state.activeParticles) do
        SafeCall(exu.DestroyParticleSystem, active.name)
    end
    self.state.activeParticles = {}

    self:_applyCloudState(nil)

    if restoreBaseline ~= false and self.state.baseline and self.state.baseline.atmosphere then
        self.state.currentAtmosphere = DeepCopy(self.state.baseline.atmosphere)
        self:_applyAtmosphere(self.state.currentAtmosphere)
    end

    self.state.transition = nil
    self.state.currentPreset = nil
    self.state.lightning = nil
    self.state.lightningFlash = nil
end

return Weather
