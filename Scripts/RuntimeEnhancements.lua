---@diagnostic disable: lowercase-global, undefined-global
local exu = require("exu")
local bzfile = require("bzfile")

local DEFAULT_TEAM_PROFILES = {
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
}

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}
    for key, entry in pairs(value) do
        result[key] = DeepCopy(entry)
    end
    return result
end

local RuntimeEnhancements = {
    Initialized = false,
    SupportsDynamicMaterials = false,
    SupportsAutoLevel = false,
    SupportsPilotVisuals = false,
    ResourceGroup = "General",
    DebugVisualLogging = true,
    DebugLogPath = nil,
    DebugSessionStarted = false,

    TeamProfiles = DeepCopy(DEFAULT_TEAM_PROFILES),

    MaterialVariants = {},
    MaterialBaseColors = {},
    MaterialFailureCount = 0,
    MaterialFailureLimit = 3,
    MaterialFailureReported = false,
    ObjectStates = {},
    VisualHandles = {},
    VisualHandleSet = {},
    VisualRefreshAt = 0.0,
    VisualBatchAt = 0.0,
    VisualCursor = 1,
    VisualBatchSize = 16,
    VisualNeedsRebuild = true,
    VisualCompactAt = 0.0,

    ThreatScanAt = 0.0,
    ThreatenedUntil = 0.0,
    AutoLevelManaged = false,
    AutoLevelRestoreState = false,
    AutoLevelHoldUntil = 0.0,
    LastUpdateAt = -1.0,
}

local VARIANT_PREFIX = "campaignReimagined_rt_"

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

local function ApplyProfile(color, profile, scale, addScale, allowTint)
    local result = CopyColor(color)
    result.r = Clamp01(result.r * (scale or 1.0))
    result.g = Clamp01(result.g * (scale or 1.0))
    result.b = Clamp01(result.b * (scale or 1.0))

    if not profile then
        return result
    end

    if allowTint and profile.tint then
        local tint = profile.tint
        local mix = Clamp01(profile.tintMix or addScale or 0.0)
        result.r = Clamp01((result.r * (1.0 - mix)) + (tonumber(tint.r) or 0.0) * mix)
        result.g = Clamp01((result.g * (1.0 - mix)) + (tonumber(tint.g) or 0.0) * mix)
        result.b = Clamp01((result.b * (1.0 - mix)) + (tonumber(tint.b) or 0.0) * mix)
        return result
    end

    local add = profile.add or { r = 0.0, g = 0.0, b = 0.0 }
    result.r = Clamp01(result.r + (add.r or 0.0) * (addScale or 0.0))
    result.g = Clamp01(result.g + (add.g or 0.0) * (addScale or 0.0))
    result.b = Clamp01(result.b + (add.b or 0.0) * (addScale or 0.0))
    return result
end

local function BuildPassColors(baseColors, profile, occupied)
    local colors = type(baseColors) == "table" and baseColors or {}
    local baseEmissive = colors.emissive or colors.selfIllumination

    local ambient = ApplyProfile(colors.ambient or colors.diffuse, profile, profile and profile.ambientScale or 1.0, 0.35, false)
    local diffuse = ApplyProfile(colors.diffuse or colors.ambient, profile, profile and profile.diffuseScale or 1.0, 0.60, true)
    local specular = ApplyProfile(colors.specular or colors.diffuse, profile, profile and profile.specularScale or 1.0, 0.20, false)
    local emissive

    if occupied then
        emissive = baseEmissive
            and ApplyProfile(baseEmissive, profile, profile and profile.emissiveScale or 1.0, 0.45, false)
            or { r = 1.0, g = 1.0, b = 1.0, a = 1.0 }
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

local function CleanScriptString(value)
    if type(value) ~= "string" then
        return ""
    end

    local cleaned = value:match("^[^%z]*") or ""
    cleaned = cleaned:match("^%s*(.-)%s*$") or ""
    return cleaned
end

local function StripKnownVariantSuffixes(name)
    local stripped = tostring(name or "")
    local changed = true
    while changed and stripped ~= "" do
        changed = false

        local withoutOccupancy = stripped:gsub("_occupied$", "", 1)
        if withoutOccupancy ~= stripped then
            stripped = withoutOccupancy
            changed = true
        end

        withoutOccupancy = stripped:gsub("_empty$", "", 1)
        if withoutOccupancy ~= stripped then
            stripped = withoutOccupancy
            changed = true
        end

        local withoutNeutral = stripped:gsub("_neutral$", "", 1)
        if withoutNeutral ~= stripped then
            stripped = withoutNeutral
            changed = true
        end

        local withoutTeam = stripped:gsub("_team%d+_[0-9a-fA-F]+$", "", 1)
        if withoutTeam ~= stripped then
            stripped = withoutTeam
            changed = true
        end
    end

    return stripped
end

local function RecoverRuntimeVariantBaseName(segment)
    local recovered = tostring(segment or "")
    local changed = true
    while changed and recovered ~= "" do
        changed = false

        if recovered:sub(1, #"campaignReimagined_") == "campaignReimagined_" then
            recovered = recovered:sub(#"campaignReimagined_" + 1)
            changed = true
        end

        if recovered:sub(1, #VARIANT_PREFIX) == VARIANT_PREFIX then
            recovered = recovered:sub(#VARIANT_PREFIX + 1)
            changed = true
        end

        local stripped = StripKnownVariantSuffixes(recovered)
        if stripped ~= recovered then
            recovered = stripped
            changed = true
        end
    end

    return recovered
end

local function IsRuntimeVariantMaterialName(materialName)
    local name = CleanScriptString(materialName)
    if name == "" then
        return false
    end

    if name:sub(1, #VARIANT_PREFIX) == VARIANT_PREFIX then
        return true
    end

    if name:sub(1, #"campaignReimagined/") ~= "campaignReimagined/" then
        return false
    end

    return name:match("/occupied$") ~= nil or name:match("/empty$") ~= nil
end

local function NormalizeBaseMaterialName(materialName)
    local name = CleanScriptString(materialName)
    if name == "" then
        return nil
    end

    if not IsRuntimeVariantMaterialName(name) then
        return name
    end

    local segment = name
    if name:sub(1, #"campaignReimagined/") == "campaignReimagined/" then
        segment = name:sub(#"campaignReimagined/" + 1)
        segment = segment:match("^([^/]+)") or segment
    end

    local recovered = RecoverRuntimeVariantBaseName(segment)
    if recovered ~= "" then
        return recovered
    end

    return name
end

local function BuildVariantMaterialName(baseMaterialName, profile, occupied)
    local profileName = profile and profile.name or "neutral"
    local occupancy = occupied and "occupied" or "empty"
    return VARIANT_PREFIX
        .. SanitizeMaterialName(baseMaterialName)
        .. "_"
        .. SanitizeMaterialName(profileName)
        .. "_"
        .. occupancy
end

local function GetDebugLogPath()
    if RuntimeEnhancements.DebugLogPath then
        return RuntimeEnhancements.DebugLogPath
    end

    local workingDirectory = "."
    if bzfile and type(bzfile.GetWorkingDirectory) == "function" then
        local ok, result = pcall(bzfile.GetWorkingDirectory)
        if ok and type(result) == "string" and result ~= "" then
            workingDirectory = result
        end
    end

    RuntimeEnhancements.DebugLogPath = workingDirectory .. "\\runtime_enhancements_debug.log"
    return RuntimeEnhancements.DebugLogPath
end

local function DebugVisualLog(message)
    if not RuntimeEnhancements.DebugVisualLogging then
        return
    end

    local now = type(GetTime) == "function" and tonumber(GetTime() or 0.0) or 0.0
    local line = string.format("[%.3f] %s\n", now, tostring(message or ""))
    local path = GetDebugLogPath()

    if bzfile and type(bzfile.Open) == "function" then
        local ok, file = pcall(bzfile.Open, path, "w", "app")
        if ok and file then
            local writeOk = pcall(function()
                if type(file.Writeln) == "function" then
                    file:Writeln(line:gsub("\n$", ""))
                elseif type(file.Write) == "function" then
                    file:Write(line)
                end
                if type(file.Flush) == "function" then
                    file:Flush()
                end
                if type(file.Close) == "function" then
                    file:Close()
                end
            end)
            if writeOk then
                return
            end
        end
    end

    if print then
        print("RuntimeEnhancements: " .. tostring(message or ""))
    end
end

local function DescribeHandle(h)
    local odf = CleanScriptString(GetOdf and GetOdf(h) or "")
    local team = type(GetTeamNum) == "function" and tostring(GetTeamNum(h)) or "?"
    return string.format("handle=%s odf=%s team=%s", tostring(h), odf ~= "" and odf or "?", team)
end

local function GetMaterialVariantKey(materialName, profile, occupied)
    local profileName = profile and profile.name or "neutral"
    local occupancy = occupied and "occupied" or "empty"
    return table.concat({ materialName, profileName, occupancy }, "|")
end

local function ReadbackMaterialName(handle, subIndex)
    if not handle or not IsValid(handle) then
        return nil
    end

    if subIndex ~= nil and exu.GetSubEntityMaterial then
        local ok, materialName = pcall(exu.GetSubEntityMaterial, handle, subIndex)
        if ok and type(materialName) == "string" and materialName ~= "" then
            return materialName
        end
    elseif exu.GetMaterialName then
        local ok, materialName = pcall(exu.GetMaterialName, handle)
        if ok and type(materialName) == "string" and materialName ~= "" then
            return materialName
        end
    end

    return nil
end

local function ApplyMaterialToHandle(handle, subIndex, materialName)
    local group = RuntimeEnhancements.ResourceGroup
    local setterOk = false

    if subIndex ~= nil then
        if exu.SetSubEntityMaterial then
            local ok, result = pcall(exu.SetSubEntityMaterial, handle, subIndex, materialName, group)
            setterOk = setterOk or (ok and result ~= false)
        end
        if exu.SetMaterialName then
            local ok, result = pcall(exu.SetMaterialName, handle, materialName, subIndex, group)
            setterOk = setterOk or (ok and result ~= false)
        end
    else
        if exu.SetEntityMaterial then
            local ok, result = pcall(exu.SetEntityMaterial, handle, materialName, group)
            setterOk = setterOk or (ok and result ~= false)
        end
        if exu.SetMaterialName then
            local ok, result = pcall(exu.SetMaterialName, handle, materialName, nil, group)
            setterOk = setterOk or (ok and result ~= false)
        end
    end

    local readback = ReadbackMaterialName(handle, subIndex)
    return readback == materialName or setterOk, readback
end

local function DisableDynamicMaterials(reason)
    if not RuntimeEnhancements.SupportsDynamicMaterials then
        return
    end

    RuntimeEnhancements.SupportsDynamicMaterials = false
    RuntimeEnhancements.SupportsPilotVisuals = false
    RuntimeEnhancements.MaterialVariants = {}
    RuntimeEnhancements.MaterialBaseColors = {}
    RuntimeEnhancements.ObjectStates = {}
    RuntimeEnhancements.VisualHandles = {}
    RuntimeEnhancements.VisualHandleSet = {}
    RuntimeEnhancements.VisualCursor = 1
    RuntimeEnhancements.VisualNeedsRebuild = false

    if not RuntimeEnhancements.MaterialFailureReported and print then
        print("RuntimeEnhancements: disabled dynamic materials after native material failure (" .. tostring(reason or "unknown") .. ")")
    end
    RuntimeEnhancements.MaterialFailureReported = true
end

local function NoteMaterialFailure(stage, materialName)
    RuntimeEnhancements.MaterialFailureCount = (RuntimeEnhancements.MaterialFailureCount or 0) + 1
    if RuntimeEnhancements.MaterialFailureCount >= (RuntimeEnhancements.MaterialFailureLimit or 3) then
        DisableDynamicMaterials(tostring(stage or "material") .. ":" .. tostring(materialName or "unknown"))
    end
end

local function EnsureMaterialVariant(materialName, profile, occupied)
    local baseMaterialName = NormalizeBaseMaterialName(materialName)
    if not baseMaterialName or baseMaterialName == "" then
        return nil
    end

    local variantKey = GetMaterialVariantKey(baseMaterialName, profile, occupied)
    local cached = RuntimeEnhancements.MaterialVariants[variantKey]
    if cached then
        return cached
    end

    local cloneName = BuildVariantMaterialName(baseMaterialName, profile, occupied)
    local group = RuntimeEnhancements.ResourceGroup

    if exu.MaterialExists then
        local okExists, exists = pcall(exu.MaterialExists, cloneName, group)
        if okExists and exists then
            RuntimeEnhancements.MaterialVariants[variantKey] = cloneName
            return cloneName
        end
    end

    local baseColors = RuntimeEnhancements.MaterialBaseColors[baseMaterialName]
    if not baseColors and exu.GetMaterialPassColors then
        local okColors, value = pcall(exu.GetMaterialPassColors, baseMaterialName, 0, 0, group)
        baseColors = okColors and value or nil
        if type(baseColors) == "table" then
            RuntimeEnhancements.MaterialBaseColors[baseMaterialName] = baseColors
        else
            NoteMaterialFailure("GetMaterialPassColors", baseMaterialName)
        end
    end

    if type(baseColors) ~= "table" then
        return nil
    end

    if exu.CloneMaterial then
        local okClone, cloned = pcall(exu.CloneMaterial, baseMaterialName, cloneName, group)
        local cloneExists = false
        if exu.MaterialExists then
            local okExists, exists = pcall(exu.MaterialExists, cloneName, group)
            cloneExists = okExists and exists or false
        end
        if (not okClone or cloned == false) and not cloneExists then
            NoteMaterialFailure("CloneMaterial", baseMaterialName)
            return nil
        end
    end

    local passColors = BuildPassColors(baseColors, profile, occupied)
    if exu.SetMaterialPassColors then
        local okSetColors, setResult = pcall(exu.SetMaterialPassColors, cloneName, passColors, 0, 0, group)
        if not okSetColors or setResult == false then
            NoteMaterialFailure("SetMaterialPassColors", cloneName)
            DebugVisualLog(string.format("variant-fail material=%s base=%s clone=%s stage=SetMaterialPassColors occupied=%s", tostring(materialName), tostring(baseMaterialName), tostring(cloneName), tostring(occupied)))
            return nil
        end
    end

    RuntimeEnhancements.MaterialVariants[variantKey] = cloneName
    DebugVisualLog(string.format("variant-ready material=%s base=%s clone=%s occupied=%s profile=%s", tostring(materialName), tostring(baseMaterialName), tostring(cloneName), tostring(occupied), tostring(profile and profile.name or "neutral")))
    return cloneName
end

local function SupportsPilotVehicleVisuals(h)
    if not h or not IsValid(h) or not IsCraft(h) or IsBuilding(h) then
        return false
    end

    if CanBuild and CanBuild(h) then
        return false
    end

    return true
end

local function GetPilotVehicleOccupancy(h)
    local valid = h and IsValid(h) or false
    if not valid then
        return false, false, false
    end

    local alive = IsAlive and IsAlive(h) or false
    local aliveAndPilot = IsAliveAndPilot and IsAliveAndPilot(h) or false
    local occupied = aliveAndPilot

    if not IsAliveAndPilot and IsAlive then
        occupied = alive
    end

    return occupied, alive, aliveAndPilot
end

local function RegisterHandle(h)
    if not h or not IsValid(h) then
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
        DebugVisualLog("register " .. DescribeHandle(h) .. string.format(" profile=%s supportsPilot=%s", tostring(profile and profile.name or "none"), tostring(supportsPilot)))
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
    if not state then
        return false
    end

    if state.prepared and state.materials ~= nil then
        return state and state.materials ~= nil
    end

    if not RuntimeEnhancements.SupportsDynamicMaterials then
        return false
    end

    local h = state.handle
    if not h or not IsValid(h) then
        return false
    end

    state.prepared = true
    local materials = {}
    local subCount = (exu.GetSubEntityCount and exu.GetSubEntityCount(h))
        or (exu.GetNumSubEntities and exu.GetNumSubEntities(h))
        or 0
    subCount = math.max(0, math.floor(tonumber(subCount) or 0))

    if subCount > 0 then
        for index = 0, subCount - 1 do
            local baseMaterial = NormalizeBaseMaterialName(ReadbackMaterialName(h, index))
            if type(baseMaterial) == "string" and baseMaterial ~= "" then
                materials[#materials + 1] = {
                    index = index,
                    base = baseMaterial,
                    occupied = EnsureMaterialVariant(baseMaterial, state.profile, true),
                    empty = state.supportsPilot and EnsureMaterialVariant(baseMaterial, state.profile, false) or nil,
                }
            end
        end
    else
        local baseMaterial = NormalizeBaseMaterialName(ReadbackMaterialName(h, nil))
        if type(baseMaterial) == "string" and baseMaterial ~= "" then
            materials[#materials + 1] = {
                index = nil,
                base = baseMaterial,
                occupied = EnsureMaterialVariant(baseMaterial, state.profile, true),
                empty = state.supportsPilot and EnsureMaterialVariant(baseMaterial, state.profile, false) or nil,
            }
        end
    end

    if #materials == 0 then
        state.prepared = false
        DebugVisualLog("prepare-empty " .. DescribeHandle(h))
        return false
    end

    state.materials = materials
    DebugVisualLog("prepare-ready " .. DescribeHandle(h) .. string.format(" materialCount=%d firstOccupied=%s firstEmpty=%s", #materials, tostring(materials[1] and materials[1].occupied or "nil"), tostring(materials[1] and materials[1].empty or "nil")))
    return true
end

local function ApplyStateVisuals(state)
    if not state or not PrepareState(state) then
        return
    end

    local occupied, alive, aliveAndPilot = state.supportsPilot and GetPilotVehicleOccupancy(state.handle) or true, true, true
    local desiredMode = occupied and "occupied" or "empty"
    if state.visualMode == desiredMode then
        return
    end

    DebugVisualLog("apply-begin " .. DescribeHandle(state.handle) .. string.format(" supportsPilot=%s occupied=%s alive=%s aliveAndPilot=%s previous=%s desired=%s materials=%d", tostring(state.supportsPilot), tostring(occupied), tostring(alive), tostring(aliveAndPilot), tostring(state.visualMode), tostring(desiredMode), #(state.materials or {})))

    local allApplied = true
    for _, material in ipairs(state.materials) do
        local target = occupied and material.occupied or material.empty or material.occupied
        if target then
            local applied, readback = ApplyMaterialToHandle(state.handle, material.index, target)
            allApplied = allApplied and applied
            DebugVisualLog("apply-material " .. DescribeHandle(state.handle) .. string.format(" index=%s target=%s ok=%s readback=%s", tostring(material.index), tostring(target), tostring(applied), tostring(readback)))
        else
            allApplied = false
            DebugVisualLog("apply-material-missing " .. DescribeHandle(state.handle) .. string.format(" index=%s desired=%s", tostring(material.index), tostring(desiredMode)))
        end
    end

    state.visualMode = allApplied and desiredMode or nil
    DebugVisualLog("apply-done " .. DescribeHandle(state.handle) .. string.format(" visualMode=%s allApplied=%s", tostring(state.visualMode), tostring(allApplied)))
end

local function RefreshVisualHandleList()
    RuntimeEnhancements.ObjectStates = {}
    RuntimeEnhancements.VisualHandles = {}
    RuntimeEnhancements.VisualHandleSet = {}

    if not AllObjects then
        return
    end

    for h in AllObjects() do
        RegisterHandle(h)
    end

    RuntimeEnhancements.VisualCursor = 1
    RuntimeEnhancements.VisualNeedsRebuild = false
end

local function CompactVisualHandleList()
    local compactedHandles = {}
    local compactedSet = {}

    for _, h in ipairs(RuntimeEnhancements.VisualHandles) do
        if h and IsValid(h) and not compactedSet[h] then
            compactedSet[h] = true
            compactedHandles[#compactedHandles + 1] = h
        else
            RuntimeEnhancements.ObjectStates[h] = nil
        end
    end

    RuntimeEnhancements.VisualHandles = compactedHandles
    RuntimeEnhancements.VisualHandleSet = compactedSet
    if RuntimeEnhancements.VisualCursor > #compactedHandles then
        RuntimeEnhancements.VisualCursor = 1
    end
end

local function UpdateVisualStates(now)
    if now < (RuntimeEnhancements.VisualBatchAt or 0.0) then
        return
    end
    RuntimeEnhancements.VisualBatchAt = now + 0.05

    if RuntimeEnhancements.VisualNeedsRebuild or #RuntimeEnhancements.VisualHandles == 0 then
        RefreshVisualHandleList()
    elseif now >= (RuntimeEnhancements.VisualCompactAt or 0.0) then
        CompactVisualHandleList()
        RuntimeEnhancements.VisualCompactAt = now + 5.0
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
    if not RuntimeEnhancements.DebugSessionStarted then
        RuntimeEnhancements.DebugSessionStarted = true
        DebugVisualLog("=== RuntimeEnhancements session start ===")
    end
    RuntimeEnhancements.SupportsDynamicMaterials = exu
        and not exu.isStub
        and exu.MaterialExists
        and exu.CloneMaterial
        and exu.GetMaterialPassColors
        and exu.SetMaterialPassColors
        and (exu.GetSubEntityCount or exu.GetNumSubEntities)
        and exu.GetSubEntityMaterial
        and exu.GetMaterialName
        and exu.SetMaterialName
        and exu.SetSubEntityMaterial
        and exu.SetEntityMaterial

    RuntimeEnhancements.SupportsAutoLevel = exu
        and not exu.isStub
        and exu.GetAutoLevel
        and exu.SetAutoLevel

    RuntimeEnhancements.SupportsPilotVisuals = RuntimeEnhancements.SupportsDynamicMaterials
    DebugVisualLog(string.format("initialize supportsDynamicMaterials=%s supportsAutoLevel=%s", tostring(RuntimeEnhancements.SupportsDynamicMaterials), tostring(RuntimeEnhancements.SupportsAutoLevel)))
end

local function NormalizeTeamColorComponent(value)
    local numeric = tonumber(value) or 0.0
    if numeric > 1.0 then
        numeric = numeric / 255.0
    end
    return Clamp01(numeric)
end

local function TeamColorName(teamNum, color)
    local r = math.floor((Clamp01(color.r) * 255.0) + 0.5)
    local g = math.floor((Clamp01(color.g) * 255.0) + 0.5)
    local b = math.floor((Clamp01(color.b) * 255.0) + 0.5)
    return string.format("team%d_%02x%02x%02x", teamNum, r, g, b)
end

local function ResolveTeamColorProfile(teamNum)
    local resolvedTeam = math.max(0, math.floor(tonumber(teamNum) or 0))
    return resolvedTeam, RuntimeEnhancements.TeamProfiles[resolvedTeam]
end

function RuntimeEnhancements.ResetVisualState()
    for _, state in pairs(RuntimeEnhancements.ObjectStates or {}) do
        if state and state.handle and IsValid(state.handle) and type(state.materials) == "table" then
            for _, material in ipairs(state.materials) do
                if material and material.base then
                    ApplyMaterialToHandle(state.handle, material.index, material.base)
                end
            end
        end
    end

    RuntimeEnhancements.MaterialVariants = {}
    RuntimeEnhancements.ObjectStates = {}
    RuntimeEnhancements.VisualHandles = {}
    RuntimeEnhancements.VisualHandleSet = {}
    RuntimeEnhancements.VisualCursor = 1
    RuntimeEnhancements.VisualRefreshAt = 0.0
    RuntimeEnhancements.VisualBatchAt = 0.0
    RuntimeEnhancements.VisualCompactAt = 0.0
    RuntimeEnhancements.VisualNeedsRebuild = true
end

function RuntimeEnhancements.ResetTeamColors()
    RuntimeEnhancements.TeamProfiles = DeepCopy(DEFAULT_TEAM_PROFILES)
    DebugVisualLog("team-color-reset all")
    RuntimeEnhancements.ResetVisualState()
end

function RuntimeEnhancements.SetTeamColor(teamNum, r, g, b)
    local resolvedTeam = math.max(0, math.floor(tonumber(teamNum) or 0))
    local color = {
        r = NormalizeTeamColorComponent(r),
        g = NormalizeTeamColorComponent(g),
        b = NormalizeTeamColorComponent(b),
    }

    RuntimeEnhancements.TeamProfiles[resolvedTeam] = {
        name = TeamColorName(resolvedTeam, color),
        tint = color,
        tintMix = 0.72,
        ambientScale = 0.95,
        diffuseScale = 0.98,
        specularScale = 0.95,
        emissiveScale = 1.00,
    }
    DebugVisualLog(string.format("team-color-set team=%d profile=%s", resolvedTeam,
        tostring(RuntimeEnhancements.TeamProfiles[resolvedTeam] and RuntimeEnhancements.TeamProfiles[resolvedTeam].name or "nil")))

    RuntimeEnhancements.ResetVisualState()
    if RuntimeEnhancements.Initialized and RuntimeEnhancements.SupportsDynamicMaterials then
        RefreshVisualHandleList()
    end

    return true
end

function RuntimeEnhancements.ClearTeamColor(teamNum)
    local resolvedTeam = math.max(0, math.floor(tonumber(teamNum) or 0))
    RuntimeEnhancements.TeamProfiles[resolvedTeam] = nil
    DebugVisualLog(string.format("team-color-clear team=%d", resolvedTeam))
    RuntimeEnhancements.ResetVisualState()
    if RuntimeEnhancements.Initialized and RuntimeEnhancements.SupportsDynamicMaterials then
        RefreshVisualHandleList()
    end
    return true
end

function RuntimeEnhancements.GetTeamColorProfileName(teamNum)
    local _, profile = ResolveTeamColorProfile(teamNum)
    return profile and profile.name or nil
end

function RuntimeEnhancements.RebuildVisuals()
    RuntimeEnhancements.Initialize()
    RuntimeEnhancements.ResetVisualState()
    if RuntimeEnhancements.SupportsDynamicMaterials then
        RefreshVisualHandleList()
    end
end

function RuntimeEnhancements.OnObjectCreated(h)
    RuntimeEnhancements.Initialize()
    if not (RuntimeEnhancements.SupportsDynamicMaterials or RuntimeEnhancements.SupportsAutoLevel) then
        return
    end

    RegisterHandle(h)
    if RuntimeEnhancements.SupportsDynamicMaterials then
        ApplyStateVisuals(RuntimeEnhancements.ObjectStates[h])
    end
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

    if exu and exu.UpdateCommandReplacements then
        exu.UpdateCommandReplacements()
    end
end

SetTeamColor = function(teamNum, r, g, b)
    return RuntimeEnhancements.SetTeamColor(teamNum, r, g, b)
end

ClearTeamColor = function(teamNum)
    return RuntimeEnhancements.ClearTeamColor(teamNum)
end

GetTeamColorProfileName = function(teamNum)
    return RuntimeEnhancements.GetTeamColorProfileName(teamNum)
end

ResetTeamColors = function()
    return RuntimeEnhancements.ResetTeamColors()
end

return RuntimeEnhancements
