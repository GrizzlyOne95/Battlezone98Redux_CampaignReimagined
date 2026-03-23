---@diagnostic disable: lowercase-global, undefined-global
local exu = require("exu")

local ReactiveReticle = {
    Enabled = true,
    Supported = false,
    HookInstalled = false,
    FlashDuration = 0.12,
    FlashExpireAt = 0.0,
    CurrentMaterial = nil,
    LastAppliedMix = nil,
    MaterialStates = {},
    FailureReported = false,
    ResolveMaterial = nil,
    RegisterHitCallback = nil,
    Log = nil,
}

local function Clamp01(value)
    local numeric = tonumber(value) or 0.0
    if numeric < 0.0 then return 0.0 end
    if numeric > 1.0 then return 1.0 end
    return numeric
end

local function LogMessage(message)
    if type(ReactiveReticle.Log) == "function" then
        ReactiveReticle.Log(message)
    else
        print(message)
    end
end

local function CopyColor(color, fallback)
    local source = (type(color) == "table" and color) or (type(fallback) == "table" and fallback) or {}
    return {
        r = Clamp01(source.r),
        g = Clamp01(source.g),
        b = Clamp01(source.b),
        a = Clamp01(source.a == nil and 1.0 or source.a),
    }
end

local function CopyPassColors(colors)
    if type(colors) ~= "table" then
        return nil
    end

    local diffuse = CopyColor(colors.diffuse, colors.ambient)
    return {
        ambient = CopyColor(colors.ambient, diffuse),
        diffuse = diffuse,
        specular = CopyColor(colors.specular, diffuse),
        emissive = CopyColor(colors.emissive, { r = 0.0, g = 0.0, b = 0.0, a = 1.0 }),
    }
end

local function LerpColor(base, target, mix, scale)
    local source = CopyColor(base)
    local amount = Clamp01(mix)
    local resolvedScale = tonumber(scale) or 1.0
    return {
        r = Clamp01((source.r * resolvedScale * (1.0 - amount)) + ((target.r or 0.0) * amount)),
        g = Clamp01((source.g * resolvedScale * (1.0 - amount)) + ((target.g or 0.0) * amount)),
        b = Clamp01((source.b * resolvedScale * (1.0 - amount)) + ((target.b or 0.0) * amount)),
        a = source.a,
    }
end

local function MaterialCall(fn, materialName, arg, resourceGroup)
    if type(fn) ~= "function" or not materialName or materialName == "" then
        return false, nil
    end

    if resourceGroup ~= nil and arg ~= nil then
        return pcall(fn, materialName, arg, 0, 0, resourceGroup)
    end
    if resourceGroup ~= nil then
        return pcall(fn, materialName, 0, 0, resourceGroup)
    end
    if arg ~= nil then
        return pcall(fn, materialName, arg, 0, 0)
    end
    return pcall(fn, materialName, 0, 0)
end

local function TryResolveMaterialState(materialName)
    if not ReactiveReticle.Supported or not materialName or materialName == "" then
        return nil
    end

    local cached = ReactiveReticle.MaterialStates[materialName]
    if cached then
        return cached
    end

    local resourceGroup = nil
    local okExists, exists = pcall(exu.MaterialExists, materialName)
    if not (okExists and exists) and type(exu.MaterialExists) == "function" then
        local okModable, existsModable = pcall(exu.MaterialExists, materialName, "Modable")
        if okModable and existsModable then
            resourceGroup = "Modable"
        end
    end

    local okColors, colors = MaterialCall(exu.GetMaterialPassColors, materialName, nil, resourceGroup)
    if not okColors or type(colors) ~= "table" then
        if not ReactiveReticle.FailureReported then
            ReactiveReticle.FailureReported = true
            LogMessage("ReactiveReticle: failed to read material colors for " .. tostring(materialName))
        end
        return nil
    end

    cached = {
        group = resourceGroup,
        baseColors = CopyPassColors(colors),
    }
    ReactiveReticle.MaterialStates[materialName] = cached
    return cached
end

local function RestoreMaterial(materialName)
    local materialState = TryResolveMaterialState(materialName)
    if not materialState or type(materialState.baseColors) ~= "table" then
        return false
    end

    local ok, success = MaterialCall(
        exu.SetMaterialPassColors,
        materialName,
        materialState.baseColors,
        materialState.group)
    return ok and success == true
end

local function BuildFlashColors(baseColors, mix)
    local warm = { r = 1.0, g = 0.96, b = 0.42 }
    local white = { r = 1.0, g = 1.0, b = 1.0 }
    local amount = Clamp01(mix)
    local diffuseBase = CopyColor(baseColors.diffuse, baseColors.ambient)
    return {
        ambient = LerpColor(baseColors.ambient, warm, 0.30 * amount, 1.0 + (0.18 * amount)),
        diffuse = LerpColor(diffuseBase, warm, 0.78 * amount, 1.0 + (0.28 * amount)),
        specular = LerpColor(baseColors.specular, white, 0.52 * amount, 1.0 + (0.24 * amount)),
        emissive = LerpColor(baseColors.emissive, warm, 0.92 * amount, 1.0 + (0.40 * amount)),
    }
end

local function HandleBulletHit(odf, shooter, hitObject, transform, ordnanceHandle)
    if not ReactiveReticle.Enabled then
        return
    end

    if type(GetPlayerHandle) ~= "function" or type(IsValid) ~= "function" then
        return
    end

    local player = GetPlayerHandle()
    if not IsValid(shooter) or shooter ~= player then
        return
    end

    if not IsValid(hitObject) or hitObject == shooter then
        return
    end

    local now = (type(GetTime) == "function" and GetTime()) or 0.0
    ReactiveReticle.FlashExpireAt = math.max(
        ReactiveReticle.FlashExpireAt or 0.0,
        now + math.max(ReactiveReticle.FlashDuration or 0.12, 0.01))
end

local function InstallHook()
    if ReactiveReticle.HookInstalled or not ReactiveReticle.Supported then
        return
    end

    if type(ReactiveReticle.RegisterHitCallback) == "function" and ReactiveReticle.RegisterHitCallback(HandleBulletHit) then
        ReactiveReticle.HookInstalled = true
        return
    end

    local oldBulletHit = exu.BulletHit
    exu.BulletHit = function(...)
        HandleBulletHit(...)
        if oldBulletHit then
            return oldBulletHit(...)
        end
    end
    ReactiveReticle.HookInstalled = true
end

function ReactiveReticle.Initialize(config)
    if type(config) == "table" then
        if config.enabled ~= nil then
            ReactiveReticle.Enabled = config.enabled and true or false
        end
        if type(config.log) == "function" then
            ReactiveReticle.Log = config.log
        end
        if type(config.resolveMaterial) == "function" then
            ReactiveReticle.ResolveMaterial = config.resolveMaterial
        end
        if type(config.registerHitCallback) == "function" then
            ReactiveReticle.RegisterHitCallback = config.registerHitCallback
        end
    end

    ReactiveReticle.Supported = exu
        and not exu.isStub
        and type(exu.MaterialExists) == "function"
        and type(exu.GetMaterialPassColors) == "function"
        and type(exu.SetMaterialPassColors) == "function"

    if ReactiveReticle.Supported then
        InstallHook()
    end

    return ReactiveReticle.Supported
end

function ReactiveReticle.Reset()
    if ReactiveReticle.CurrentMaterial then
        RestoreMaterial(ReactiveReticle.CurrentMaterial)
    end
    ReactiveReticle.FlashExpireAt = 0.0
    ReactiveReticle.CurrentMaterial = nil
    ReactiveReticle.LastAppliedMix = nil
end

function ReactiveReticle.Update()
    if not (ReactiveReticle.Enabled and ReactiveReticle.Supported) then
        return
    end
    if type(ReactiveReticle.ResolveMaterial) ~= "function" then
        return
    end

    local activeMaterial = ReactiveReticle.ResolveMaterial()
    if activeMaterial ~= ReactiveReticle.CurrentMaterial then
        if ReactiveReticle.CurrentMaterial then
            RestoreMaterial(ReactiveReticle.CurrentMaterial)
        end
        ReactiveReticle.CurrentMaterial = activeMaterial
        ReactiveReticle.LastAppliedMix = nil
    end

    if not activeMaterial or activeMaterial == "" then
        return
    end

    local materialState = TryResolveMaterialState(activeMaterial)
    if not materialState or type(materialState.baseColors) ~= "table" then
        return
    end

    local now = (type(GetTime) == "function" and GetTime()) or 0.0
    local mix = 0.0
    if now < (ReactiveReticle.FlashExpireAt or 0.0) then
        mix = Clamp01((ReactiveReticle.FlashExpireAt - now) / math.max(ReactiveReticle.FlashDuration or 0.12, 0.01))
        mix = 1.0 - ((1.0 - mix) * (1.0 - mix))
    end

    if mix <= 0.001 then
        if ReactiveReticle.LastAppliedMix ~= nil then
            RestoreMaterial(activeMaterial)
            ReactiveReticle.LastAppliedMix = nil
        end
        return
    end

    if ReactiveReticle.LastAppliedMix ~= nil and math.abs(ReactiveReticle.LastAppliedMix - mix) < 0.05 then
        return
    end

    local flashColors = BuildFlashColors(materialState.baseColors, mix)
    local ok, success = MaterialCall(
        exu.SetMaterialPassColors,
        activeMaterial,
        flashColors,
        materialState.group)
    if ok and success == true then
        ReactiveReticle.LastAppliedMix = mix
    elseif not ReactiveReticle.FailureReported then
        ReactiveReticle.FailureReported = true
        LogMessage("ReactiveReticle: failed to write material colors for " .. tostring(activeMaterial))
    end
end

return ReactiveReticle
