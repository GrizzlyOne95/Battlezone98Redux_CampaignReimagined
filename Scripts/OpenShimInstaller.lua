-- OpenShimInstaller.lua
-- Lightweight Campaign Reimagined bootstrap/update path shared by normal
-- missions and the dedicated setup mission. Keep this module independent of
-- EXU, aiCore, HUD/overlay systems, and campaign gameplay initialization.
---@diagnostic disable: lowercase-global, undefined-global

local bzfile = require("bzfile")
local LogPaths = require("LogPaths")

local OpenShimInstaller = {}

OpenShimInstaller.Config = {
    bundledRootName = "winmm.dll",
    bundledWorkshopId = "3686673790",
    installedDescriptionFile = "install.des",
    updatedDescriptionFile = "update.des",
    stagedDescriptionFile = "staged.des",
    failureDescriptionFile = "nocopy.des",
}
OpenShimInstaller.InstallChecked = false

local FeedbackCallback = nil

local function EmitFeedback(msg, r, g, b, duration, bypass, target)
    if type(FeedbackCallback) == "function" then
        return FeedbackCallback(msg, r, g, b, duration, bypass, target)
    end
    print(tostring(msg))
end

local function getWorkingDirectory()
    return (bzfile and bzfile.GetWorkingDirectory and bzfile.GetWorkingDirectory()) or "."
end

local function InsertUniquePath(target, seen, value)
    if not value or value == "" or seen[value] then
        return
    end

    seen[value] = true
    target[#target + 1] = value
end

local function SplitInstallerPathList(value)
    local results = {}
    for part in string.gmatch(value or "", "([^;]+)") do
        results[#results + 1] = part
    end
    return results
end

local function NormalizeInstallerPath(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end

    local normalized = value:gsub("/", "\\")
    normalized = normalized:gsub("\\+", "\\")
    normalized = normalized:gsub("\\$", "")
    return normalized
end

local function GetWorkshopContentDirectory()
    if bzfile and type(bzfile.GetWorkshopDirectory) == "function" then
        local ok, path = pcall(bzfile.GetWorkshopDirectory)
        if ok and type(path) == "string" and path ~= "" then
            return NormalizeInstallerPath(path)
        end
    end

    local pathLists = { package.cpath or "", package.path or "" }
    local marker = "\\steamapps\\workshop\\content\\301650\\"

    for _, pathList in ipairs(pathLists) do
        for entry in string.gmatch(pathList, "([^;]+)") do
            local normalized = NormalizeInstallerPath(entry)
            if normalized then
                local lower = string.lower(normalized)
                local markerStart = string.find(lower, marker, 1, true)
                if markerStart then
                    return normalized:sub(1, markerStart + #marker - 2)
                end
            end
        end
    end

    local workingDirectory = NormalizeInstallerPath(getWorkingDirectory())
    if workingDirectory then
        local lower = string.lower(workingDirectory)
        local commonMarker = "\\steamapps\\common\\"
        local markerStart = string.find(lower, commonMarker, 1, true)
        if markerStart then
            local steamRoot = workingDirectory:sub(1, markerStart - 1)
            return steamRoot .. "\\steamapps\\workshop\\content\\301650"
        end
    end

    return nil
end

local function ExtractInstallerRootFromPath(path, workshopId)
    if not path then
        return nil
    end

    local lower = string.lower(path)
    local workshopMarker = "\\steamapps\\workshop\\content\\301650\\"
    local workshopStart = string.find(lower, workshopMarker, 1, true)
    if workshopStart then
        local suffix = path:sub(workshopStart + #workshopMarker)
        local slashIndex = string.find(suffix, "\\", 1, true)
        local itemId = slashIndex and suffix:sub(1, slashIndex - 1) or suffix
        if itemId ~= "" and (workshopId == "" or string.lower(itemId) == string.lower(workshopId)) then
            return path:sub(1, workshopStart + #workshopMarker + #itemId - 1)
        end
    end

    local markers = {
        "\\addon\\",
        "\\mods\\",
        "\\packaged_mods\\",
    }

    for _, marker in ipairs(markers) do
        local markerStart = string.find(lower, marker, 1, true)
        if markerStart then
            local suffix = path:sub(markerStart + #marker)
            local slashIndex = string.find(suffix, "\\", 1, true)
            if slashIndex then
                return path:sub(1, markerStart + #marker + slashIndex - 2)
            end
            if suffix ~= "" then
                return path
            end
        end
    end

    return nil
end

local function CollectInstallerRoots(workshopId)
    local roots = {}
    local seenRoots = {}
    local pathLists = { package.cpath or "", package.path or "" }

    for _, pathList in ipairs(pathLists) do
        for _, entry in ipairs(SplitInstallerPathList(pathList)) do
            local normalized = NormalizeInstallerPath(entry)
            local root = ExtractInstallerRootFromPath(normalized, workshopId)
            InsertUniquePath(roots, seenRoots, root)
        end
    end

    return roots, seenRoots
end

local function BzFileExists(path)
    if not path or path == "" then
        return false
    end

    if bzfile and type(bzfile.Exists) == "function" then
        local ok, exists = pcall(bzfile.Exists, path)
        if ok then
            return not not exists
        end
    end

    if io and type(io.open) == "function" then
        local file = io.open(path, "rb")
        if file then
            file:close()
            return true
        end
    end

    if bzfile and type(bzfile.Open) == "function" then
        local ok = pcall(function()
            local handle = bzfile.Open(path, "r")
            handle:Read(1)
            handle:Close()
        end)
        if ok then
            return true
        end
    end

    return false
end

local function GetBzFileHash(path)
    if not path or path == "" then
        return nil
    end

    if bzfile and type(bzfile.GetFileHash) == "function" then
        local ok, hashOrNil, errorMessage = pcall(bzfile.GetFileHash, path, "sha256")
        if ok and type(hashOrNil) == "string" and hashOrNil ~= "" then
            return string.lower(hashOrNil)
        end

        local detail = ok and tostring(errorMessage or "unknown error") or tostring(hashOrNil)
        print("PersistentConfig: GetFileHash failed for " .. tostring(path) .. ": " .. detail)
    end

    return nil
end

local function GetPathLeaf(path)
    if not path or path == "" then
        return nil
    end

    return path:match("([^\\/]+)$") or path
end

local function GetOpenShimReplaceLogPath(destinationPath)
    local normalized = NormalizeInstallerPath(destinationPath)
    if not normalized or normalized == "" then
        return nil
    end

    local fileName = GetPathLeaf(normalized) or "winmm.dll"
    local stem = fileName:gsub("%.[^.]+$", "")
    local logFile = stem .. "_replace.log"
    return LogPaths.Path(logFile)
end

local function WriteOpenShimInstallerDescriptionFile(relativePath, text)
    if not relativePath or relativePath == "" or type(text) ~= "string" or text == "" then
        return nil
    end

    local workingDirectory = NormalizeInstallerPath(getWorkingDirectory())
    if not workingDirectory or workingDirectory == "" then
        return nil
    end

    local fullPath = workingDirectory .. "\\" .. relativePath
    if bzfile and type(bzfile.Open) == "function" then
        local ok, err = pcall(function()
            local handle = bzfile.Open(fullPath, "w", "trunc")
            handle:Write(text)
            handle:Close()
        end)
        if ok then
            return relativePath
        end

        print("PersistentConfig: Failed to write OpenShim installer description via bzfile: " .. tostring(err))
    end

    if io and type(io.open) == "function" then
        local handle = io.open(fullPath, "w")
        if handle then
            handle:write(text)
            handle:close()
            return relativePath
        end
    end

    return nil
end

local function GetBundledOpenShimPayloadPath(payloadName)
    if type(payloadName) ~= "string" or payloadName == "" or
        payloadName:find("[\\/]") then
        return nil
    end

    local workingDirectory = NormalizeInstallerPath(getWorkingDirectory())
    local workshopDirectory = GetWorkshopContentDirectory()
    local workshopId = tostring(OpenShimInstaller.Config.bundledWorkshopId or "")
    local roots, seenRoots = CollectInstallerRoots(workshopId)
    local candidates = {}

    InsertUniquePath(roots, seenRoots, workingDirectory and (workingDirectory .. "\\addon\\" .. workshopId) or nil)
    InsertUniquePath(roots, seenRoots, workingDirectory and (workingDirectory .. "\\mods\\" .. workshopId) or nil)
    InsertUniquePath(roots, seenRoots, workingDirectory and (workingDirectory .. "\\packaged_mods\\" .. workshopId) or nil)

    if workshopDirectory then
        local normalizedWorkshop = NormalizeInstallerPath(workshopDirectory)
        local lowerWorkshop = string.lower(normalizedWorkshop or "")
        if workshopId ~= "" and lowerWorkshop:sub(-#workshopId) == string.lower(workshopId) then
            InsertUniquePath(roots, seenRoots, normalizedWorkshop)
        else
            InsertUniquePath(roots, seenRoots, normalizedWorkshop and (normalizedWorkshop .. "\\" .. workshopId) or nil)
        end
    end

    for _, root in ipairs(roots) do
        candidates[#candidates + 1] = root .. "\\" .. payloadName
        candidates[#candidates + 1] = root .. "\\_Release\\" .. payloadName
    end

    for _, candidate in ipairs(candidates) do
        if BzFileExists(candidate) then
            return candidate
        end
    end

    return nil
end

local function ShowOpenShimInstallMissionOutcome(state, failureLogPath)
    local missionTime = (GetTime and GetTime()) or 0.0
    if state == "installed" or state == "updated" or state == "staged" then
        local descriptionFile = OpenShimInstaller.Config.installedDescriptionFile
        local fallbackMessage = "OpenShim installed. Restart Battlezone before continuing."

        if state == "updated" then
            descriptionFile = OpenShimInstaller.Config.updatedDescriptionFile
            fallbackMessage = "OpenShim updated. Restart Battlezone before continuing."
        elseif state == "staged" then
            descriptionFile = OpenShimInstaller.Config.stagedDescriptionFile
            fallbackMessage = "OpenShim update is queued for game exit. Close Battlezone, then relaunch before continuing."
        end

        if SucceedMission then
            SucceedMission(missionTime, descriptionFile)
            return
        end
        EmitFeedback(fallbackMessage, 1.0, 0.85, 0.2, 12.0, true)
        return
    end

    local failureMessage = "OpenShim self-install failed. Restart Battlezone and verify the mod files."
    if failureLogPath and failureLogPath ~= "" then
        local logFileName = GetPathLeaf(failureLogPath) or "winmm_replace.log"
        failureMessage = "OpenShim self-install failed. Check logs\\" .. logFileName .. "."

        WriteOpenShimInstallerDescriptionFile(
            "shimfail.des",
            "Campaign Reimagined could not install or update OpenShim. Check " ..
            failureLogPath ..
            " for details, then restart Battlezone and verify the mod files before continuing.")
    end

    -- A self-update failure must not abort the active campaign mission. The
    -- installed shim may already be newer than the bundled copy, and installs
    -- under Program Files can legitimately reject an in-process replacement.
    EmitFeedback(failureMessage, 1.0, 0.35, 0.35, 12.0, true)
end

local function GetBzFileVersion(path)
    if not path or path == "" then
        return nil
    end

    if bzfile and type(bzfile.GetFileVersion) == "function" then
        local ok, versionOrNil, errorMessage = pcall(bzfile.GetFileVersion, path)
        if ok and type(versionOrNil) == "string" and versionOrNil ~= "" then
            return versionOrNil
        end

        local detail = ok and tostring(errorMessage or "unknown error") or tostring(versionOrNil)
        print("PersistentConfig: GetFileVersion failed for " .. tostring(path) .. ": " .. detail)
    end

    return nil
end

local function CompareInstallerVersions(left, right)
    local function Parts(value)
        local parts = {}
        for number in tostring(value or ""):gmatch("%d+") do
            parts[#parts + 1] = tonumber(number) or 0
        end
        return parts
    end

    local leftParts = Parts(left)
    local rightParts = Parts(right)
    if #leftParts == 0 or #rightParts == 0 then
        return nil
    end

    local count = math.max(#leftParts, #rightParts)
    for index = 1, count do
        local leftValue = leftParts[index] or 0
        local rightValue = rightParts[index] or 0
        if leftValue < rightValue then return -1 end
        if leftValue > rightValue then return 1 end
    end
    return 0
end

local function GetOpenShimManifest()
    local ok, manifestOrError = pcall(require, "OpenShimManifest")
    if not ok or type(manifestOrError) ~= "table" then
        print("PersistentConfig: OpenShim manifest unavailable: " .. tostring(manifestOrError))
        return nil
    end

    local manifest = manifestOrError
    local function NormalizePayload(payload)
        if type(payload) ~= "table" then return nil end
        payload.sha256 = type(payload.sha256) == "string" and string.lower(payload.sha256) or nil
        if not payload.sha256 or not payload.sha256:match("^[0-9a-f]+$") or #payload.sha256 ~= 64 or
            type(payload.source) ~= "string" or payload.source == "" or
            type(payload.destination) ~= "string" or payload.destination == "" then
            return nil
        end
        return payload
    end

    manifest.sha256 = type(manifest.sha256) == "string" and string.lower(manifest.sha256) or nil
    local payloads = manifest.payloads
    local winmm = payloads and NormalizePayload(payloads.winmm) or nil
    local network = payloads and NormalizePayload(payloads.network) or nil
    local patches = payloads and NormalizePayload(payloads.patches) or nil
    local playerConfig = payloads and NormalizePayload(payloads.playerConfig) or nil
    if manifest.formatVersion ~= 2 or
        not manifest.sha256 or not manifest.sha256:match("^[0-9a-f]+$") or #manifest.sha256 ~= 64 or
        type(manifest.version) ~= "string" or manifest.version == "" or
        manifest.architecture ~= "x86" or
        not winmm or not network or not patches or not playerConfig or
        winmm.source ~= "winmm.dll" or winmm.destination ~= "winmm.dll" or
        network.source ~= "openshim_net.ini.payload" or network.destination ~= "net.ini" or
        patches.source ~= "openshim_patches.json.payload" or patches.destination ~= "scripts\\patches.json" or
        playerConfig.source ~= "openshim.ini.payload" or playerConfig.destination ~= "openshim.ini" or
        type(playerConfig.overwrite) ~= "boolean" or
        winmm.sha256 ~= manifest.sha256 or winmm.version ~= manifest.version or
        winmm.architecture ~= "x86" then
        print("PersistentConfig: OpenShim manifest is malformed or unsupported.")
        return nil
    end

    return manifest
end

local function ReadOpenShimInstallerStatus(path)
    if not path or path == "" or not io or type(io.open) ~= "function" then
        return nil
    end

    local handle = io.open(path, "r")
    if not handle then
        return nil
    end

    local values = {}
    for line in handle:lines() do
        local key, value = line:match("^([^=]+)=(.*)$")
        if key then values[key] = value end
    end
    handle:close()
    return values
end

local function AcknowledgeCompletedOpenShimUpdate(statusPath, expectedHash)
    local status = ReadOpenShimInstallerStatus(statusPath)
    if not status or status.state ~= "complete" or status.expected_sha256 ~= expectedHash then
        return
    end

    print("PersistentConfig: Verified the staged OpenShim update after restart.")
    EmitFeedback("OpenShim update verified.", 0.35, 1.0, 0.35, 8.0, true)
    if bzfile and type(bzfile.Delete) == "function" then
        pcall(bzfile.Delete, statusPath)
    end
end

local function EnsureBundledOpenShimInstalled()
    if OpenShimInstaller.InstallChecked then
        return
    end
    OpenShimInstaller.InstallChecked = true

    if not (bzfile and type(bzfile.StageOpenShimSuiteUpdate) == "function") then
        print("PersistentConfig: hardened OpenShim suite staging is unavailable; leaving the active mission running.")
        return
    end

    local workingDirectory = getWorkingDirectory()
    local manifest = GetOpenShimManifest()
    local statusPath = workingDirectory .. "\\openshim_update.status"
    local replaceLogPath = LogPaths.Path("openshim_update.log")
    if not manifest then
        ShowOpenShimInstallMissionOutcome("failed", replaceLogPath)
        return
    end

    local orderedPayloads = {
        manifest.payloads.winmm,
        manifest.payloads.network,
        manifest.payloads.patches,
        manifest.payloads.playerConfig,
    }
    local sourcePaths = {}
    for index, payload in ipairs(orderedPayloads) do
        local sourcePath = GetBundledOpenShimPayloadPath(payload.source)
        if not sourcePath then
            print("PersistentConfig: Bundled OpenShim suite payload is missing: " .. tostring(payload.source))
            ShowOpenShimInstallMissionOutcome("failed", replaceLogPath)
            return
        end

        local sourceHash = GetBzFileHash(sourcePath)
        if not sourceHash or sourceHash ~= payload.sha256 then
            print("PersistentConfig: Bundled OpenShim suite payload does not match the manifest: " ..
                tostring(payload.source))
            ShowOpenShimInstallMissionOutcome("failed", replaceLogPath)
            return
        end
        sourcePaths[index] = sourcePath
    end

    local destinationPaths = {
        workingDirectory .. "\\winmm.dll",
        workingDirectory .. "\\net.ini",
        workingDirectory .. "\\scripts\\patches.json",
        workingDirectory .. "\\openshim.ini",
    }
    -- openshim.ini is the player's file. Only its ABSENCE means the suite is out
    -- of date; a differing hash just means a setting was changed, and letting
    -- that count here dragged the whole suite into a staged replacement every
    -- launch -- which then overwrote the edit that triggered it.
    local playerConfigIndex = 4
    local allCurrent = true
    for index, payload in ipairs(orderedPayloads) do
        local destinationExists = BzFileExists(destinationPaths[index])
        if index == playerConfigIndex then
            if not destinationExists then
                allCurrent = false
            end
        else
            local destinationHash = destinationExists and
                GetBzFileHash(destinationPaths[index]) or nil
            if destinationHash ~= payload.sha256 then
                allCurrent = false
            end
        end
    end
    if allCurrent then
        AcknowledgeCompletedOpenShimUpdate(statusPath, manifest.sha256)
        return
    end

    if BzFileExists(destinationPaths[1]) then
        local destinationHash = GetBzFileHash(destinationPaths[1])
        local destinationVersion = GetBzFileVersion(destinationPaths[1])
        local versionComparison = CompareInstallerVersions(destinationVersion, manifest.version)
        if destinationHash ~= manifest.sha256 and versionComparison and versionComparison > 0 then
            print("PersistentConfig: Installed OpenShim " .. tostring(destinationVersion) ..
                " is newer than bundled suite version " .. tostring(manifest.version) .. "; skipping downgrade.")
            return
        end
    end

    local ok, staged, stageState, helperLogPath = pcall(
        bzfile.StageOpenShimSuiteUpdate,
        sourcePaths[1], orderedPayloads[1].sha256,
        sourcePaths[2], orderedPayloads[2].sha256,
        sourcePaths[3], orderedPayloads[3].sha256)
    if ok and staged then
        local configDestination = destinationPaths[playerConfigIndex]
        local configExists = BzFileExists(configDestination)
        -- Install the shipped INI only when the player has none. Absent keys
        -- already fall back to OpenShim's in-code defaults, so a new release
        -- reaches an existing player without touching what they set. Honour an
        -- explicit overwrite = true if a manifest ever asks for one.
        local overwritePlayerConfig = orderedPayloads[playerConfigIndex].overwrite == true
        local configAction = "left alone"

        if (not configExists) or overwritePlayerConfig then
            if configExists then
                local backupOk, backupCopied, backupError = pcall(
                    bzfile.CopyFile,
                    configDestination,
                    configDestination .. ".pre-workshop.bak",
                    true)
                if not backupOk or not backupCopied then
                    print("PersistentConfig: Could not back up the existing OpenShim player INI: " ..
                        tostring(backupOk and backupError or backupCopied))
                end
            end

            local copyOk, configCopied, configError = pcall(
                bzfile.CopyFile,
                sourcePaths[playerConfigIndex],
                configDestination,
                true)
            local installedConfigHash = copyOk and configCopied and GetBzFileHash(configDestination) or nil
            if not copyOk or not configCopied or
                installedConfigHash ~= orderedPayloads[playerConfigIndex].sha256 then
                local configFailure = not copyOk and tostring(configCopied) or
                    tostring(configError or "installed hash mismatch")
                print("PersistentConfig: OpenShim player INI install failed: " .. configFailure)
                ShowOpenShimInstallMissionOutcome("failed", replaceLogPath)
                return
            end
            configAction = configExists and "overwritten" or "installed"
        end

        print("PersistentConfig: OpenShim suite " .. tostring(manifest.version) ..
            " staged for verified replacement on exit; player openshim.ini " .. configAction .. "." ..
            (helperLogPath and (" Helper log: " .. tostring(helperLogPath)) or ""))
        ShowOpenShimInstallMissionOutcome(stageState == "staged" and "staged" or "updated")
        return
    end

    local errorText = ok and tostring(stageState or "staging failed") or tostring(staged)
    print("PersistentConfig: Hardened OpenShim suite staging failed: " .. errorText ..
        (replaceLogPath and ("; check " .. replaceLogPath) or ""))
    ShowOpenShimInstallMissionOutcome("failed", replaceLogPath)
end


function OpenShimInstaller.EnsureOnce(showFeedback)
    local previousFeedback = FeedbackCallback
    FeedbackCallback = showFeedback

    local ok, result = pcall(EnsureBundledOpenShimInstalled)

    FeedbackCallback = previousFeedback
    if not ok then
        error(result, 0)
    end
    return result
end

return OpenShimInstaller
