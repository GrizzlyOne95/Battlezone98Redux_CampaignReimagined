---@diagnostic disable: lowercase-global, undefined-global
local exu = require("exu")

local RuntimeEnhancements = {
    Initialized = false,
    SupportsDynamicMaterials = false,
    SupportsAutoLevel = false,
    SupportsPilotVisuals = false,
    ResourceGroup = "General",

    TeamProfiles = {
        [2] = {
            name = "team2_nsdf",
            add = { r = 0.06, g = 0.12, b = 0.22 },
            ambientScale = 0.92,
            diffuseScale = 0.90,
            specularScale = 0.95,
            emissiveScale = 0.90,
        },
        [3] = {
            name = "team3_nsdf",
            add = { r = 0.22, g = 0.08, b = 0.03 },
            ambientScale = 0.95,
            diffuseScale = 0.90,
            specularScale = 0.98,
            emissiveScale = 1.00,
        },
    },

    MaterialVariants = {},
    MaterialBaseColors = {},
    ObjectStates = {},
    VisualHandles = {},
    VisualHandleSet = {},
    VisualRefreshAt = 0.0,
    VisualBatchAt = 0.0,
    VisualCursor = 1,
    VisualBatchSize = 16,

    ThreatScanAt = 0.0,
    ThreatenedUntil = 0.0,
    AutoLevelManaged = false,
    AutoLevelRestoreState = false,
    AutoLevelHoldUntil = 0.0,
    LastUpdateAt = -1.0,
}

local function Clamp01(value)
    if value < 0.0 then return 0.0 end
    if value > 1.0 then return 1.0 end
    return value
end

local function CopyColor(color)
    if type(color) ~= "table" then
        return { r = 0.0, g = 0.0, b = 0.0, a = 1.0 }
    end

    return {
        r = tonumber(color.r) or 0.0,
        g = tonumber(color.g) or 0.0,
        b = tonumber(color.b) or 0.0,
        a = tonumber(color.a) or 1.0,
    }
end

local function ApplyProfile(color, profile, scale, addScale)
    local result = CopyColor(color)
    if not profile then
        return result
    end

    local add = profile.add or { r = 0.0, g = 0.0, b = 0.0 }
    result.r = Clamp01((result.r * (scale or 1.0)) + (add.r or 0.0) * (addScale or 0.0))
    result.g = Clamp01((result.g * (scale or 1.0)) + (add.g or 0.0) * (addScale or 0.0))
    result.b = Clamp01((result.b * (scale or 1.0)) + (add.b or 0.0) * (addScale or 0.0))
    return result
end

local function BuildPassColors(baseColors, profile, occupied)
    local colors = type(baseColors) == "table" and baseColors or {}

    local ambient = ApplyProfile(colors.ambient or colors.diffuse, profile, profile and profile.ambientScale or 1.0, 0.35)
    local diffuse = ApplyProfile(colors.diffuse or colors.ambient, profile, profile and profile.diffuseScale or 1.0, 0.60)
    local specular = ApplyProfile(colors.specular or colors.diffuse, profile, profile and profile.specularScale or 1.0, 0.20)
    local emissive

    if occupied then
        emissive = ApplyProfile(colors.emissive or colors.selfIllumination, profile, profile and profile.emissiveScale or 1.0, 0.45)
    else
        emissive = { r = 0.0, g = 0.0, b = 0.0, a = 1.0 }
    end

    return {
        ambient = ambient,
        diffuse = diffuse,
        specular = specular,
        emissive = emissive,
    }
end

local function SanitizeMaterialName(materialName)
    local sanitized = tostring(materialName or "material")
    sanitized = sanitized:gsub("[^%w_]+", "_")
    sanitized = sanitized:gsub("_+", "_")
    return sanitized
end

local function GetMaterialVariantKey(materialName, profile, occupied)
    local profileName = profile and profile.name or "neutral"
    local occupancy = occupied and "occupied" or "empty"
    return table.concat({ materialName, profileName, occupancy }, "|")
end

local function EnsureMaterialVariant(materialName, profile, occupied)
    local variantKey = GetMaterialVariantKey(materialName, profile, occupied)
    local cached = RuntimeEnhancements.MaterialVariants[variantKey]
    if cached then
        return cached
    end

    local cloneName = "campaignReimagined/" .. SanitizeMaterialName(materialName) .. "/" .. (profile and profile.name or "neutral") .. "/" .. (occupied and "occupied" or "empty")
    local group = RuntimeEnhancements.ResourceGroup

    if exu.MaterialExists and exu.MaterialExists(cloneName, group) then
        RuntimeEnhancements.MaterialVariants[variantKey] = cloneName
        return cloneName
    end

    local baseColors = RuntimeEnhancements.MaterialBaseColors[materialName]
    if not baseColors and exu.GetMaterialPassColors then
        baseColors = exu.GetMaterialPassColors(materialName, 0, 0, group)
        if type(baseColors) == "table" then
            RuntimeEnhancements.MaterialBaseColors[materialName] = baseColors
        end
    end

    if type(baseColors) ~= "table" then
        return nil
    end

    if exu.CloneMaterial and not exu.CloneMaterial(materialName, cloneName, group) then
        if not (exu.MaterialExists and exu.MaterialExists(cloneName, group)) then
            return nil
        end
    end

    local passColors = BuildPassColors(baseColors, profile, occupied)
    if exu.SetMaterialPassColors and not exu.SetMaterialPassColors(cloneName, passColors, 0, 0, group) then
        return nil
    end

    RuntimeEnhancements.MaterialVariants[variantKey] = cloneName
    return cloneName
end

local function SupportsPilotVehicleVisuals(h)
    if not h or not IsValid(h) or not IsCraft(h) or IsBuilding(h) then
        return false
    end

    if CanBuild and CanBuild(h) then
        return false
    end

    return GetPilotClass and GetPilotClass(h) ~= nil
end

local function RegisterHandle(h)
    if not h or not IsValid(h) or not IsCraft(h) then
        return
    end

    local profile = RuntimeEnhancements.TeamProfiles[GetTeamNum(h)]
    local supportsPilot = SupportsPilotVehicleVisuals(h)
    if not profile and not supportsPilot then
        return
    end

    if not RuntimeEnhancements.VisualHandleSet[h] then
        RuntimeEnhancements.VisualHandleSet[h] = true
        RuntimeEnhancements.VisualHandles[#RuntimeEnhancements.VisualHandles + 1] = h
    end

    local state = RuntimeEnhancements.ObjectStates[h]
    if not state then
        state = { handle = h }
        RuntimeEnhancements.ObjectStates[h] = state
    elseif state.profile ~= profile or state.supportsPilot ~= supportsPilot then
        state.prepared = false
        state.materials = nil
        state.visualMode = nil
    end

    state.profile = profile
    state.supportsPilot = supportsPilot
    state.prepared = state.prepared or false
end

local function PrepareState(state)
    if not state or state.prepared then
        return state and state.materials ~= nil
    end

    state.prepared = true
    if not RuntimeEnhancements.SupportsDynamicMaterials then
        return false
    end

    local h = state.handle
    if not h or not IsValid(h) then
        return false
    end

    local materials = {}
    local subCount = (exu.GetSubEntityCount and exu.GetSubEntityCount(h))
        or (exu.GetNumSubEntities and exu.GetNumSubEntities(h))
        or 0
    subCount = math.max(0, math.floor(tonumber(subCount) or 0))

    if subCount > 0 then
        for index = 0, subCount - 1 do
            local baseMaterial = exu.GetSubEntityMaterial and exu.GetSubEntityMaterial(h, index)
            if type(baseMaterial) == "string" and baseMaterial ~= "" then
                materials[#materials + 1] = {
                    index = index,
                    occupied = EnsureMaterialVariant(baseMaterial, state.profile, true),
                    empty = state.supportsPilot and EnsureMaterialVariant(baseMaterial, state.profile, false) or nil,
                }
            end
        end
    else
        local baseMaterial = exu.GetMaterialName and exu.GetMaterialName(h)
        if type(baseMaterial) == "string" and baseMaterial ~= "" then
            materials[#materials + 1] = {
                index = nil,
                occupied = EnsureMaterialVariant(baseMaterial, state.profile, true),
                empty = state.supportsPilot and EnsureMaterialVariant(baseMaterial, state.profile, false) or nil,
            }
        end
    end

    if #materials == 0 then
        return false
    end

    state.materials = materials
    return true
end

local function ApplyStateVisuals(state)
    if not state or not PrepareState(state) then
        return
    end

    local occupied = state.supportsPilot and IsAliveAndPilot(state.handle) or true
    local desiredMode = occupied and "occupied" or "empty"
    if state.visualMode == desiredMode then
        return
    end

    for _, material in ipairs(state.materials) do
        local target = occupied and material.occupied or material.empty or material.occupied
        if target then
            if material.index ~= nil then
                if exu.SetSubEntityMaterial then
                    exu.SetSubEntityMaterial(state.handle, material.index, target, RuntimeEnhancements.ResourceGroup)
                end
            elseif exu.SetEntityMaterial then
                exu.SetEntityMaterial(state.handle, target, RuntimeEnhancements.ResourceGroup)
            end
        end
    end

    state.visualMode = desiredMode
end

local function RefreshVisualHandleList()
    RuntimeEnhancements.VisualHandles = {}
    RuntimeEnhancements.VisualHandleSet = {}

    if not AllCraft then
        return
    end

    for h in AllCraft() do
        RegisterHandle(h)
    end

    RuntimeEnhancements.VisualCursor = 1
end

local function UpdateVisualStates(now)
    if now < (RuntimeEnhancements.VisualBatchAt or 0.0) then
        return
    end
    RuntimeEnhancements.VisualBatchAt = now + 0.05

    if now >= (RuntimeEnhancements.VisualRefreshAt or 0.0) or #RuntimeEnhancements.VisualHandles == 0 then
        RefreshVisualHandleList()
        RuntimeEnhancements.VisualRefreshAt = now + 2.0
    end

    local processed = 0
    local cursor = RuntimeEnhancements.VisualCursor or 1
    while cursor <= #RuntimeEnhancements.VisualHandles and processed < (RuntimeEnhancements.VisualBatchSize or 16) do
        local h = RuntimeEnhancements.VisualHandles[cursor]
        local state = RuntimeEnhancements.ObjectStates[h]
        if h and IsValid(h) and state then
            RegisterHandle(h)
            ApplyStateVisuals(state)
        else
            RuntimeEnhancements.ObjectStates[h] = nil
        end
        processed = processed + 1
        cursor = cursor + 1
    end

    if cursor > #RuntimeEnhancements.VisualHandles then
        RuntimeEnhancements.VisualCursor = 1
    else
        RuntimeEnhancements.VisualCursor = cursor
    end
end

local function HasSeismicPayload(player)
    if not player or not IsValid(player) then
        return false
    end

    for slot = 0, 3 do
        local weapon = string.lower(tostring(GetWeaponClass and GetWeaponClass(player, slot) or ""))
        if weapon == "gquake" or weapon == "seismic" or weapon == "thumper" then
            return true
        end
    end

    return false
end

local function WasRecentlyShotByEnemy(player, now)
    if not player or not IsValid(player) or not GetLastEnemyShot then
        return false
    end

    local lastShot = tonumber(GetLastEnemyShot(player) or 0.0) or 0.0
    if lastShot <= 0.0 or (now - lastShot) > 2.5 then
        return false
    end

    local attacker = GetWhoShotMe and GetWhoShotMe(player) or nil
    return IsValid(attacker) and IsAlive(attacker) and not IsAlly(player, attacker)
end

local function IsPlayerTargeted(player, now)
    if WasRecentlyShotByEnemy(player, now) then
        RuntimeEnhancements.ThreatenedUntil = now + 1.5
        return true
    end

    if now < (RuntimeEnhancements.ThreatScanAt or 0.0) then
        return now < (RuntimeEnhancements.ThreatenedUntil or 0.0)
    end

    RuntimeEnhancements.ThreatScanAt = now + 0.25
    RuntimeEnhancements.ThreatenedUntil = 0.0

    if not AllCraft then
        return false
    end

    for h in AllCraft() do
        if IsValid(h) and IsAlive(h) and not IsAlly(player, h) then
            local currentTarget = GetCurrentWho and GetCurrentWho(h) or nil
            local command = GetCurrentCommand and GetCurrentCommand(h) or AiCommand.NONE
            if currentTarget == player
                and (command == AiCommand.ATTACK or command == AiCommand.HUNT or command == AiCommand.DEFEND)
            then
                RuntimeEnhancements.ThreatenedUntil = now + 1.5
                return true
            end
        end
    end

    return false
end

local function UpdateAutoLevel(now)
    local player = GetPlayerHandle and GetPlayerHandle() or nil
    if not player or not IsValid(player) or not IsCraft(player) then
        if RuntimeEnhancements.AutoLevelManaged then
            exu.SetAutoLevel(RuntimeEnhancements.AutoLevelRestoreState and true or false)
            RuntimeEnhancements.AutoLevelManaged = false
        end
        return
    end

    local shouldEnable = HasSeismicPayload(player) and IsPlayerTargeted(player, now)
    if shouldEnable then
        if not RuntimeEnhancements.AutoLevelManaged then
            RuntimeEnhancements.AutoLevelRestoreState = exu.GetAutoLevel and exu.GetAutoLevel() and true or false
            RuntimeEnhancements.AutoLevelManaged = true
        end

        RuntimeEnhancements.AutoLevelHoldUntil = now + 4.0
        if not (exu.GetAutoLevel and exu.GetAutoLevel()) then
            exu.SetAutoLevel(true)
        end
        return
    end

    if RuntimeEnhancements.AutoLevelManaged and now >= (RuntimeEnhancements.AutoLevelHoldUntil or 0.0) then
        exu.SetAutoLevel(RuntimeEnhancements.AutoLevelRestoreState and true or false)
        RuntimeEnhancements.AutoLevelManaged = false
    end
end

function RuntimeEnhancements.Initialize()
    if RuntimeEnhancements.Initialized then
        return
    end

    RuntimeEnhancements.Initialized = true
    RuntimeEnhancements.SupportsDynamicMaterials = exu
        and not exu.isStub
        and exu.MaterialExists
        and exu.CloneMaterial
        and exu.GetMaterialPassColors
        and exu.SetMaterialPassColors
        and (exu.GetSubEntityCount or exu.GetNumSubEntities)
        and exu.GetSubEntityMaterial
        and exu.SetSubEntityMaterial
        and exu.SetEntityMaterial

    RuntimeEnhancements.SupportsAutoLevel = exu
        and not exu.isStub
        and exu.GetAutoLevel
        and exu.SetAutoLevel

    RuntimeEnhancements.SupportsPilotVisuals = RuntimeEnhancements.SupportsDynamicMaterials
end

function RuntimeEnhancements.OnObjectCreated(h)
    RuntimeEnhancements.Initialize()
    if not (RuntimeEnhancements.SupportsDynamicMaterials or RuntimeEnhancements.SupportsAutoLevel) then
        return
    end

    RegisterHandle(h)
end

function RuntimeEnhancements.Update()
    RuntimeEnhancements.Initialize()
    local now = GetTime and GetTime() or 0.0
    if now == RuntimeEnhancements.LastUpdateAt then
        return
    end
    RuntimeEnhancements.LastUpdateAt = now

    if RuntimeEnhancements.SupportsDynamicMaterials then
        UpdateVisualStates(now)
    end

    if RuntimeEnhancements.SupportsAutoLevel then
        UpdateAutoLevel(now)
    end
end

return RuntimeEnhancements
