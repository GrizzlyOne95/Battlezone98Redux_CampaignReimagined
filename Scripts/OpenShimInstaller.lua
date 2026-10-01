-- OpenShimInstaller.lua
-- Campaign Reimagined installation diagnostics and explicit setup actions.
-- Normal missions inspect only; the dedicated setup mission applies updates. Keep this module independent of
-- EXU, aiCore, HUD/overlay systems, and campaign gameplay initialization.
---@diagnostic disable: lowercase-global, undefined-global

local bzfileOk, bzfile = pcall(require, "bzfile")
if not bzfileOk then bzfile = nil end
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
            type(payload.size) ~= "number" or payload.size <= 0 or
            type(payload.source) ~= "string" or payload.source == "" or
            type(payload.destination) ~= "string" or payload.destination == "" then
            return nil
        end
        return payload
    end

    manifest.sha256 = type(manifest.sha256) == "string" and string.lower(manifest.sha256) or nil
    local payloads = manifest.payloads
    local winmm = payloads and NormalizePayload(payloads.winmm) or nil
    local loader = payloads and NormalizePayload(payloads.loader) or nil
    local plugin = payloads and NormalizePayload(payloads.plugin) or nil
    local helper = payloads and payloads.helper
    local network = payloads and NormalizePayload(payloads.network) or nil
    local patches = payloads and NormalizePayload(payloads.patches) or nil
    local playerConfig = payloads and NormalizePayload(payloads.playerConfig) or nil
    local assetManifest = payloads and NormalizePayload(payloads.assetManifest) or nil
    if manifest.formatVersion ~= 3 or
        not manifest.sha256 or not manifest.sha256:match("^[0-9a-f]+$") or #manifest.sha256 ~= 64 or
        type(manifest.version) ~= "string" or manifest.version == "" or
        manifest.architecture ~= "x86" or
        not winmm or not loader or not plugin or not network or not patches or not playerConfig or
        not assetManifest or
        winmm.source ~= "winmm.dll" or winmm.destination ~= "winmm.dll" or
        loader.source ~= "bzloader.dll" or loader.destination ~= "bzloader.dll" or
        plugin.source ~= "openshim.dll" or plugin.destination ~= "plugins\\openshim.dll" or
        loader.version ~= manifest.version or plugin.version ~= manifest.version or
        loader.architecture ~= "x86" or plugin.architecture ~= "x86" or
        type(helper) ~= "table" or helper.source ~= "bzfile_replace_helper.exe" or
        type(helper.sha256) ~= "string" or #helper.sha256 ~= 64 or
        not helper.sha256:match("^[0-9a-fA-F]+$") or
        type(helper.size) ~= "number" or helper.size <= 0 or
        network.source ~= "openshim_net.ini.payload" or network.destination ~= "net.ini" or
        patches.source ~= "openshim_patches.json.payload" or patches.destination ~= "scripts\\patches.json" or
        playerConfig.source ~= "openshim.ini.payload" or playerConfig.destination ~= "openshim.ini" or
        type(playerConfig.overwrite) ~= "boolean" or
        assetManifest.source ~= "OpenShimAssets.ini.payload" or
        assetManifest.destination ~= "openshim\\OpenShimAssets.ini" or
        winmm.sha256 ~= manifest.sha256 or winmm.version ~= manifest.version or winmm.size ~= manifest.size or
        winmm.architecture ~= "x86" then
        print("PersistentConfig: OpenShim manifest is malformed or unsupported.")
        return nil
    end

    helper.sha256 = string.lower(helper.sha256)
    return manifest
end

local function ReadTextFile(path)
    if not path or path == "" then
        return nil
    end

    if bzfile and type(bzfile.Open) == "function" then
        local ok, contents = pcall(function()
            local handle = bzfile.Open(path, "r")
            local chunks = {}
            while true do
                local chunk = handle:Read(65536)
                if not chunk or chunk == "" then break end
                chunks[#chunks + 1] = chunk
            end
            handle:Close()
            return table.concat(chunks)
        end)
        if ok and type(contents) == "string" then
            return contents
        end
    end

    if io and type(io.open) == "function" then
        local handle = io.open(path, "rb")
        if handle then
            local contents = handle:read("*a")
            handle:close()
            return contents
        end
    end

    return nil
end

local function WriteTextFile(path, text)
    if not path or path == "" or type(text) ~= "string" then
        return false, "invalid path or text"
    end

    if bzfile and type(bzfile.Open) == "function" then
        local ok, err = pcall(function()
            local handle = bzfile.Open(path, "w", "trunc")
            handle:Write(text)
            handle:Close()
        end)
        if ok then
            return true
        end
        if err then
            print("OpenShimInstaller: bzfile write failed for " .. tostring(path) .. ": " .. tostring(err))
        end
    end

    if io and type(io.open) == "function" then
        local handle, err = io.open(path, "wb")
        if handle then
            handle:write(text)
            handle:close()
            return true
        end
        return false, tostring(err or "io.open failed")
    end

    return false, "no writable file API is available"
end

local function ReadOpenShimInstallerStatus(path)
    local contents = ReadTextFile(path)
    if not contents then
        return nil
    end

    local values = {}
    for line in (contents .. "\n"):gmatch("(.-)\r?\n") do
        local key, value = line:match("^([^=]+)=(.*)$")
        if key then values[key] = value end
    end
    return values
end

OpenShimInstaller.States = {
    CURRENT = "CURRENT",
    INSTALL_REQUIRED = "INSTALL_REQUIRED",
    UPDATE_REQUIRED = "UPDATE_REQUIRED",
    RESTART_REQUIRED = "RESTART_REQUIRED",
    UPDATE_FAILED = "UPDATE_FAILED",
    NEWER_THAN_BUNDLED = "NEWER_THAN_BUNDLED",
    MANIFEST_INVALID = "MANIFEST_INVALID",
    PAYLOAD_MISSING = "PAYLOAD_MISSING",
    PAYLOAD_HASH_MISMATCH = "PAYLOAD_HASH_MISMATCH",
    STAGING_UNAVAILABLE = "STAGING_UNAVAILABLE",
    BZFILE_UNAVAILABLE = "BZFILE_UNAVAILABLE",
    HELPER_MISSING = "HELPER_MISSING",
}

local function GetPathDirectory(path)
    if not path or path == "" then
        return nil
    end
    return path:match("^(.*)[\\/][^\\/]+$")
end

local function NewPayloadDiagnostic(name, payload, sourcePath)
    local actualHash = sourcePath and GetBzFileHash(sourcePath) or nil
    local state = "CURRENT"
    if not sourcePath then
        state = "MISSING"
    elseif actualHash ~= payload.sha256 then
        state = "HASH_MISMATCH"
    end

    return {
        name = name,
        source = sourcePath,
        expectedSha256 = payload.sha256,
        actualSha256 = actualHash,
        state = state,
    }
end

local function NewInstalledDiagnostic(name, path, payload, compareVersion)
    local exists = BzFileExists(path)
    local actualHash = exists and GetBzFileHash(path) or nil
    local version = compareVersion and exists and GetBzFileVersion(path) or nil
    local state

    if not exists then
        state = "MISSING"
    elseif name == "playerConfig" then
        state = actualHash == payload.sha256 and "DEFAULT" or "CUSTOMIZED"
    elseif actualHash == payload.sha256 then
        state = "CURRENT"
    else
        local comparison = compareVersion and CompareInstallerVersions(version, payload.version) or nil
        state = comparison and comparison > 0 and "NEWER" or "OUTDATED"
    end

    return {
        name = name,
        path = path,
        exists = exists,
        expectedSha256 = payload.sha256,
        actualSha256 = actualHash,
        version = version,
        expectedVersion = payload.version,
        state = state,
    }
end

--- Inspect the bundled and installed OpenShim suite without changing anything
--- on disk. This intentionally performs no staging, copying, deletion, or
--- update-status acknowledgement so the setup mission can display the report
--- before the user chooses/observes an action.
function OpenShimInstaller.Inspect()
    local workingDirectory = NormalizeInstallerPath(getWorkingDirectory()) or "."
    local report = {
        schemaVersion = 1,
        state = "UNKNOWN",
        workingDirectory = workingDirectory,
        diagnosticLogPath = workingDirectory .. "\\logs\\openpatch_setup.log",
        bzfileAvailable = bzfile ~= nil,
        stagingAvailable = bzfile and type(bzfile.StageOpenShimSuiteUpdateV3) == "function" or false,
        workshopDirectory = GetWorkshopContentDirectory(),
        manifest = { valid = false },
        payloads = {},
        installed = {},
        updateStatus = {
            path = workingDirectory .. "\\openshim_update.status",
            exists = false,
        },
    }

    local status = ReadOpenShimInstallerStatus(report.updateStatus.path)
    if status then
        report.updateStatus.exists = true
        report.updateStatus.state = status.state
        report.updateStatus.expectedSha256 = status.expected_sha256
        report.updateStatus.detail = status.detail
        report.updateStatus.updated = status.updated
        report.updateStatus.payloadCount = status.payload_count
    end

    if not report.bzfileAvailable then
        report.state = OpenShimInstaller.States.BZFILE_UNAVAILABLE
        return report
    end

    local manifest = GetOpenShimManifest()
    if not manifest then
        report.state = OpenShimInstaller.States.MANIFEST_INVALID
        return report
    end

    report.manifest = {
        valid = true,
        formatVersion = manifest.formatVersion,
        version = manifest.version,
        architecture = manifest.architecture,
        sha256 = manifest.sha256,
    }

    local definitions = {
        { name = "winmm", payload = manifest.payloads.winmm, versioned = true },
        { name = "loader", payload = manifest.payloads.loader, versioned = true },
        { name = "plugin", payload = manifest.payloads.plugin, versioned = true },
        { name = "network", payload = manifest.payloads.network },
        { name = "patches", payload = manifest.payloads.patches },
        { name = "playerConfig", payload = manifest.payloads.playerConfig },
        { name = "assetManifest", payload = manifest.payloads.assetManifest },
    }

    local destinationPaths = {
        winmm = workingDirectory .. "\\winmm.dll",
        loader = workingDirectory .. "\\bzloader.dll",
        plugin = workingDirectory .. "\\plugins\\openshim.dll",
        network = workingDirectory .. "\\net.ini",
        patches = workingDirectory .. "\\scripts\\patches.json",
        playerConfig = workingDirectory .. "\\openshim.ini",
        assetManifest = workingDirectory .. "\\openshim\\OpenShimAssets.ini",
    }

    local sourceFailure = nil
    local sourceRoot = nil
    for _, definition in ipairs(definitions) do
        local sourcePath = GetBundledOpenShimPayloadPath(definition.payload.source)
        local sourceDiagnostic = NewPayloadDiagnostic(
            definition.name,
            definition.payload,
            sourcePath)
        report.payloads[definition.name] = sourceDiagnostic
        sourceRoot = sourceRoot or GetPathDirectory(sourcePath)

        if sourceDiagnostic.state == "MISSING" and not sourceFailure then
            sourceFailure = OpenShimInstaller.States.PAYLOAD_MISSING
        elseif sourceDiagnostic.state == "HASH_MISMATCH" and
            sourceFailure ~= OpenShimInstaller.States.PAYLOAD_MISSING then
            sourceFailure = OpenShimInstaller.States.PAYLOAD_HASH_MISMATCH
        end

        report.installed[definition.name] = NewInstalledDiagnostic(
            definition.name,
            destinationPaths[definition.name],
            definition.payload,
            definition.versioned)
    end
    report.sourceRoot = sourceRoot
    report.helper = {
        path = sourceRoot and (sourceRoot .. "\\bzfile_replace_helper.exe") or nil,
        exists = sourceRoot and BzFileExists(sourceRoot .. "\\bzfile_replace_helper.exe") or false,
    }
    report.payloads.helper = NewPayloadDiagnostic("helper", manifest.payloads.helper, report.helper.path)

    if report.updateStatus.exists then
        report.updateStatus.matchesBundled =
            report.updateStatus.expectedSha256 == manifest.sha256
    end

    if sourceFailure then
        report.state = sourceFailure
        return report
    end

    if not report.helper.exists then
        report.state = OpenShimInstaller.States.HELPER_MISSING
        return report
    end
    if report.payloads.helper.state ~= "CURRENT" then
        report.state = OpenShimInstaller.States.PAYLOAD_HASH_MISMATCH
        return report
    end

    local winmm = report.installed.winmm
    local network = report.installed.network
    local patches = report.installed.patches
    local playerConfig = report.installed.playerConfig
    local allCurrent =
        winmm.state == "CURRENT" and
        report.installed.loader.state == "CURRENT" and
        report.installed.plugin.state == "CURRENT" and
        network.state == "CURRENT" and
        patches.state == "CURRENT" and
        playerConfig.state ~= "MISSING" and
        report.installed.assetManifest.state == "CURRENT"

    local pendingState = report.updateStatus.matchesBundled and
        (report.updateStatus.state == "staged" or
         report.updateStatus.state == "waiting_for_exit" or
         report.updateStatus.state == "already_staged")

    -- A pending status with no update helper running was left by a helper
    -- that never finished (crash, kill, power loss). Without this check it
    -- reads as "restart required" forever and the update is never staged
    -- again. Older bzfile builds lack IsOpenShimUpdateActive; keep trusting
    -- the status there.
    if pendingState and bzfile and type(bzfile.IsOpenShimUpdateActive) == "function" then
        local ok, active = pcall(bzfile.IsOpenShimUpdateActive)
        if ok and active == false then
            pendingState = false
            report.updateStatus.stale = true
        end
    end

    if pendingState then
        report.state = OpenShimInstaller.States.RESTART_REQUIRED
        return report
    end

    if report.updateStatus.matchesBundled and
        report.updateStatus.state == "failed" and
        not allCurrent then
        report.state = OpenShimInstaller.States.UPDATE_FAILED
        return report
    end

    if winmm.state == "MISSING" then
        report.state = OpenShimInstaller.States.INSTALL_REQUIRED
        return report
    end

    if winmm.state == "NEWER" or report.installed.loader.state == "NEWER" or
        report.installed.plugin.state == "NEWER" then
        report.state = OpenShimInstaller.States.NEWER_THAN_BUNDLED
        return report
    end

    if allCurrent then
        report.state = OpenShimInstaller.States.CURRENT
        return report
    end

    if not report.stagingAvailable then
        report.state = OpenShimInstaller.States.STAGING_UNAVAILABLE
        return report
    end

    report.state = OpenShimInstaller.States.UPDATE_REQUIRED
    return report
end

local function ReplacePathPrefix(path, prefix, token)
    if type(path) ~= "string" or path == "" or
        type(prefix) ~= "string" or prefix == "" then
        return path
    end

    local normalizedPath = NormalizeInstallerPath(path) or path
    local normalizedPrefix = NormalizeInstallerPath(prefix) or prefix
    local pathLower = string.lower(normalizedPath)
    local prefixLower = string.lower(normalizedPrefix)
    if pathLower:sub(1, #prefixLower) ~= prefixLower then
        return normalizedPath
    end

    local boundary = normalizedPath:sub(#normalizedPrefix + 1, #normalizedPrefix + 1)
    if boundary ~= "" and boundary ~= "\\" then
        return normalizedPath
    end

    return token .. normalizedPath:sub(#normalizedPrefix + 1)
end

local function SafeDiagnosticPath(report, path)
    local value = ReplacePathPrefix(path, report.workingDirectory, "<GAME>")
    value = ReplacePathPrefix(value, report.sourceRoot, "<MOD>")
    value = ReplacePathPrefix(value, report.workshopDirectory, "<WORKSHOP>")
    return value
end

local function BoolText(value)
    return value and "YES" or "NO"
end

local function AddDiagnosticPayloadLine(lines, prefix, entry, report)
    if not entry then return end
    lines[#lines + 1] = prefix .. "_STATE=" .. tostring(entry.state or "UNKNOWN")
    lines[#lines + 1] = prefix .. "_EXPECTED_SHA256=" .. tostring(entry.expectedSha256 or "")
    lines[#lines + 1] = prefix .. "_ACTUAL_SHA256=" .. tostring(entry.actualSha256 or "")
    if entry.source then
        lines[#lines + 1] = prefix .. "_SOURCE=" .. tostring(SafeDiagnosticPath(report, entry.source))
    end
    if entry.path then
        lines[#lines + 1] = prefix .. "_PATH=" .. tostring(SafeDiagnosticPath(report, entry.path))
    end
    if entry.version then
        lines[#lines + 1] = prefix .. "_VERSION=" .. tostring(entry.version)
    end
end

--- Build a deterministic, support-friendly diagnostic report. Paths under the
--- game and mod roots are tokenized so a shared log does not expose a user's
--- profile/install prefix.
function OpenShimInstaller.FormatDiagnosticReport(report)
    report = report or OpenShimInstaller.Inspect()
    local lines = {
        "OPEN COMMUNITY PATCH SETUP DIAGNOSTICS",
        "SCHEMA=" .. tostring(report.schemaVersion or 1),
        "RESULT=" .. tostring(report.state or "UNKNOWN"),
        "BZFILE_AVAILABLE=" .. BoolText(report.bzfileAvailable),
        "STAGING_AVAILABLE=" .. BoolText(report.stagingAvailable),
        "GAME_ROOT=<GAME>",
        "MOD_ROOT=" .. tostring(report.sourceRoot and "<MOD>" or "UNKNOWN"),
        "WORKSHOP_DIRECTORY=" .. tostring(SafeDiagnosticPath(report, report.workshopDirectory or "")),
        "HELPER_PRESENT=" .. BoolText(report.helper and report.helper.exists),
        "HELPER_PATH=" .. tostring(SafeDiagnosticPath(report, report.helper and report.helper.path or "")),
        "BUNDLED_OPENSHIM=" .. tostring(report.manifest and report.manifest.version or "UNKNOWN"),
        "BUNDLED_SHA256=" .. tostring(report.manifest and report.manifest.sha256 or ""),
        "ACTION=" .. tostring(report.action or ""),
        "ACTION_SUCCESS=" .. tostring(report.actionSuccess == true),
        "ACTION_RESTART_REQUIRED=" .. tostring(report.actionRestartRequired == true),
        "ACTION_DETAIL=" .. tostring(report.actionDetail or ""),
        "ACTION_PLAYER_CONFIG=" .. tostring(report.actionPlayerConfig or ""),
        "ACTION_ASSET_MANIFEST=" .. tostring(report.actionAssetManifest or ""),
        "ACTION_STAGE_STATE=" .. tostring(report.actionStageState or ""),
    }

    AddDiagnosticPayloadLine(lines, "PAYLOAD_WINMM", report.payloads and report.payloads.winmm, report)
    AddDiagnosticPayloadLine(lines, "PAYLOAD_LOADER", report.payloads and report.payloads.loader, report)
    AddDiagnosticPayloadLine(lines, "PAYLOAD_PLUGIN", report.payloads and report.payloads.plugin, report)
    AddDiagnosticPayloadLine(lines, "PAYLOAD_HELPER", report.payloads and report.payloads.helper, report)
    AddDiagnosticPayloadLine(lines, "PAYLOAD_NETWORK", report.payloads and report.payloads.network, report)
    AddDiagnosticPayloadLine(lines, "PAYLOAD_PATCHES", report.payloads and report.payloads.patches, report)
    AddDiagnosticPayloadLine(lines, "PAYLOAD_PLAYER_CONFIG", report.payloads and report.payloads.playerConfig, report)
    AddDiagnosticPayloadLine(lines, "PAYLOAD_ASSET_MANIFEST", report.payloads and report.payloads.assetManifest, report)
    AddDiagnosticPayloadLine(lines, "INSTALLED_WINMM", report.installed and report.installed.winmm, report)
    AddDiagnosticPayloadLine(lines, "INSTALLED_LOADER", report.installed and report.installed.loader, report)
    AddDiagnosticPayloadLine(lines, "INSTALLED_PLUGIN", report.installed and report.installed.plugin, report)
    AddDiagnosticPayloadLine(lines, "INSTALLED_NETWORK", report.installed and report.installed.network, report)
    AddDiagnosticPayloadLine(lines, "INSTALLED_PATCHES", report.installed and report.installed.patches, report)
    AddDiagnosticPayloadLine(lines, "INSTALLED_PLAYER_CONFIG", report.installed and report.installed.playerConfig, report)
    AddDiagnosticPayloadLine(lines, "INSTALLED_ASSET_MANIFEST", report.installed and report.installed.assetManifest, report)

    local status = report.updateStatus or {}
    lines[#lines + 1] = "UPDATE_STATUS_PRESENT=" .. BoolText(status.exists)
    lines[#lines + 1] = "UPDATE_STATUS_STATE=" .. tostring(status.state or "")
    lines[#lines + 1] = "UPDATE_STATUS_EXPECTED_SHA256=" .. tostring(status.expectedSha256 or "")
    lines[#lines + 1] = "UPDATE_STATUS_MATCHES_BUNDLED=" .. BoolText(status.matchesBundled)
    lines[#lines + 1] = "UPDATE_STATUS_DETAIL=" .. tostring(status.detail or "")
    lines[#lines + 1] = "UPDATE_STATUS_UPDATED=" .. tostring(status.updated or "")
    lines[#lines + 1] = "UPDATE_STATUS_PAYLOAD_COUNT=" .. tostring(status.payloadCount or "")
    lines[#lines + 1] = "UPDATE_STATUS_PATH=" .. tostring(SafeDiagnosticPath(report, status.path or ""))

    return table.concat(lines, "\r\n") .. "\r\n"
end

--- Write the diagnostic report on explicit request. Inspect() itself remains
--- side-effect free.
function OpenShimInstaller.WriteDiagnosticLog(report)
    report = report or OpenShimInstaller.Inspect()
    local path = LogPaths.Path("openpatch_setup.log")
    report.diagnosticLogPath = path
    local ok, err = WriteTextFile(path, OpenShimInstaller.FormatDiagnosticReport(report))
    if ok then
        return path
    end
    return nil, err
end

local ACTIONABLE_STATES = {
    [OpenShimInstaller.States.INSTALL_REQUIRED] = true,
    [OpenShimInstaller.States.UPDATE_REQUIRED] = true,
    [OpenShimInstaller.States.UPDATE_FAILED] = true,
}

local function CopyPlayerConfigIfNeeded(report, manifest)
    local entry = report.installed and report.installed.playerConfig
    local payload = manifest and manifest.payloads and manifest.payloads.playerConfig
    if not entry or not payload then
        return false, "player config diagnostics are unavailable"
    end

    local configExists = entry.exists == true
    local overwritePlayerConfig = payload.overwrite == true
    if configExists and not overwritePlayerConfig then
        return true, "preserved"
    end

    local sourcePath = report.payloads and report.payloads.playerConfig and
        report.payloads.playerConfig.source or nil
    if not sourcePath then
        return false, "bundled openshim.ini payload is unavailable"
    end
    if not (bzfile and type(bzfile.CopyFile) == "function") then
        return false, "bzfile.CopyFile is unavailable"
    end

    local destinationPath = entry.path
    if configExists and overwritePlayerConfig then
        local backupOk, backupCopied, backupError = pcall(
            bzfile.CopyFile,
            destinationPath,
            destinationPath .. ".pre-workshop.bak",
            true)
        if not backupOk or not backupCopied then
            return false, "could not back up existing openshim.ini: " ..
                tostring(backupOk and backupError or backupCopied)
        end
    end

    local copyOk, configCopied, configError = pcall(
        bzfile.CopyFile,
        sourcePath,
        destinationPath,
        true)
    local installedConfigHash = copyOk and configCopied and
        GetBzFileHash(destinationPath) or nil
    if not copyOk or not configCopied or installedConfigHash ~= payload.sha256 then
        local detail = not copyOk and tostring(configCopied) or
            tostring(configError or "installed hash mismatch")
        return false, "openshim.ini install failed: " .. detail
    end

    return true, configExists and "overwritten" or "installed"
end

-- OpenShim reports its asset pack only when <game>\openshim\OpenShimAssets.ini
-- exists. The Workshop bundle carries every asset, so the sentinel is always
-- replaced with the bundled copy. It is plain text read at startup, so it is
-- copied directly instead of joining the staged (locked-file) suite.
local function CopyAssetManifestIfNeeded(report, manifest)
    local entry = report.installed and report.installed.assetManifest
    local payload = manifest and manifest.payloads and manifest.payloads.assetManifest
    if not entry or not payload then
        return false, "asset manifest diagnostics are unavailable"
    end
    if entry.state == "CURRENT" then
        return true, "current"
    end

    local sourcePath = report.payloads and report.payloads.assetManifest and
        report.payloads.assetManifest.source or nil
    if not sourcePath then
        return false, "bundled OpenShimAssets.ini payload is unavailable"
    end
    if not (bzfile and type(bzfile.CopyFile) == "function") then
        return false, "bzfile.CopyFile is unavailable"
    end

    local destinationPath = entry.path
    local directory = GetPathDirectory(destinationPath)
    if directory and type(bzfile.MakeDirectory) == "function" then
        local dirOk, dirCreated, dirError = pcall(bzfile.MakeDirectory, directory)
        if not dirOk or not dirCreated then
            return false, "could not create openshim folder: " ..
                tostring(dirOk and dirError or dirCreated)
        end
    end

    local copyOk, copied, copyError = pcall(bzfile.CopyFile, sourcePath, destinationPath, true)
    local installedHash = copyOk and copied and GetBzFileHash(destinationPath) or nil
    if not copyOk or not copied or installedHash ~= payload.sha256 then
        local detail = not copyOk and tostring(copied) or
            tostring(copyError or "installed hash mismatch")
        return false, "OpenShimAssets.ini install failed: " .. detail
    end

    return true, entry.exists and "updated" or "installed"
end

local function NewApplyResult(report)
    return {
        before = report,
        after = report,
        state = report and report.state or "UNKNOWN",
        action = "none",
        success = false,
        changed = false,
        restartRequired = false,
        detail = nil,
        helperLogPath = nil,
        stageState = nil,
        playerConfigAction = "preserved",
        assetManifestAction = "current",
    }
end

--- Apply the safe setup action for the current diagnostic state.
---
--- This function never calls mission success/failure APIs. It only mutates the
--- installation for states that Inspect() has already classified as requiring
--- installation/repair. Healthy installs and newer manual installs are no-ops.
function OpenShimInstaller.Apply(report)
    report = report or OpenShimInstaller.Inspect()
    local result = NewApplyResult(report)

    if report.state == OpenShimInstaller.States.CURRENT then
        result.success = true
        result.detail = "installation already current"
        return result
    end

    if report.state == OpenShimInstaller.States.NEWER_THAN_BUNDLED then
        result.success = true
        result.detail = "installed OpenShim is newer than the bundled release; no downgrade performed"
        return result
    end

    if report.state == OpenShimInstaller.States.RESTART_REQUIRED then
        result.success = true
        result.action = "already_staged"
        result.restartRequired = true
        result.detail = "an OpenShim update is already staged or waiting for game exit"
        return result
    end

    if not ACTIONABLE_STATES[report.state] then
        result.action = "blocked"
        result.detail = "setup cannot safely repair diagnostic state " .. tostring(report.state)
        return result
    end

    if not (bzfile and type(bzfile.StageOpenShimSuiteUpdateV3) == "function") then
        result.action = "blocked"
        result.state = OpenShimInstaller.States.STAGING_UNAVAILABLE
        result.detail = "hardened OpenShim suite staging is unavailable"
        return result
    end

    local manifest = GetOpenShimManifest()
    if not manifest then
        result.action = "blocked"
        result.state = OpenShimInstaller.States.MANIFEST_INVALID
        result.detail = "OpenShim manifest is unavailable or invalid"
        return result
    end

    -- Revalidate every bundled payload immediately before any write/staging
    -- action. Inspect() may have happened several frames earlier.
    local payloadOrder = {
        { name = "winmm", payload = manifest.payloads.winmm },
        { name = "loader", payload = manifest.payloads.loader },
        { name = "plugin", payload = manifest.payloads.plugin },
        { name = "helper", payload = manifest.payloads.helper },
        { name = "network", payload = manifest.payloads.network },
        { name = "patches", payload = manifest.payloads.patches },
        { name = "playerConfig", payload = manifest.payloads.playerConfig },
        { name = "assetManifest", payload = manifest.payloads.assetManifest },
    }
    for _, definition in ipairs(payloadOrder) do
        local sourceEntry = report.payloads and report.payloads[definition.name]
        local sourcePath = sourceEntry and sourceEntry.source or nil
        local sourceHash = sourcePath and GetBzFileHash(sourcePath) or nil
        if not sourcePath then
            result.action = "blocked"
            result.state = OpenShimInstaller.States.PAYLOAD_MISSING
            result.detail = "bundled payload missing: " .. tostring(definition.payload.source)
            return result
        end
        if sourceHash ~= definition.payload.sha256 then
            result.action = "blocked"
            result.state = OpenShimInstaller.States.PAYLOAD_HASH_MISMATCH
            result.detail = "bundled payload hash mismatch: " .. tostring(definition.payload.source)
            return result
        end
    end

    local coreCurrent =
        report.installed and report.installed.winmm and report.installed.winmm.state == "CURRENT" and
        report.installed.loader and report.installed.loader.state == "CURRENT" and
        report.installed.plugin and report.installed.plugin.state == "CURRENT" and
        report.installed.network and report.installed.network.state == "CURRENT" and
        report.installed.patches and report.installed.patches.state == "CURRENT"

    -- If only the user config and/or the asset-pack sentinel need installing,
    -- copy them directly. Re-staging a byte-identical DLL/net/patch suite
    -- would force a pointless restart just to create two text files.
    if coreCurrent then
        local configOk, configAction = CopyPlayerConfigIfNeeded(report, manifest)
        local assetsOk, assetsAction = CopyAssetManifestIfNeeded(report, manifest)
        result.playerConfigAction = configAction
        result.assetManifestAction = assetsAction
        result.action = configOk and assetsOk and "config_installed" or "config_failed"
        result.success = configOk and assetsOk
        result.changed = configAction ~= "preserved" or assetsAction ~= "current"
        if not configOk then
            result.detail = configAction
        elseif not assetsOk then
            result.detail = assetsAction
        else
            result.detail = "support files installed (openshim.ini " .. tostring(configAction) ..
                ", OpenShimAssets.ini " .. tostring(assetsAction) ..
                "); core OpenShim files were already current"
        end
        result.after = OpenShimInstaller.Inspect()
        result.state = result.after.state
        return result
    end

    local sourcePaths = {
        report.payloads.winmm.source,
        report.payloads.network.source,
        report.payloads.patches.source,
    }

    local ok, staged, stageState, helperLogPath = pcall(
        bzfile.StageOpenShimSuiteUpdateV3,
        sourcePaths[1], manifest.payloads.winmm.sha256,
        sourcePaths[2], manifest.payloads.network.sha256,
        sourcePaths[3], manifest.payloads.patches.sha256,
        report.payloads.loader.source, manifest.payloads.loader.sha256,
        report.payloads.plugin.source, manifest.payloads.plugin.sha256,
        manifest.payloads.helper.sha256)

    if not ok or not staged then
        result.action = "stage_failed"
        result.detail = ok and tostring(stageState or "staging failed") or tostring(staged)
        result.helperLogPath = LogPaths.Path("openshim_update.log")
        result.after = OpenShimInstaller.Inspect()
        result.state = result.after.state
        return result
    end

    result.action = report.state == OpenShimInstaller.States.INSTALL_REQUIRED and
        "install_staged" or "update_staged"
    result.success = true
    result.changed = true
    result.restartRequired = true
    result.stageState = stageState
    result.helperLogPath = helperLogPath

    local configOk, configAction = CopyPlayerConfigIfNeeded(report, manifest)
    result.playerConfigAction = configAction
    local assetsOk, assetsAction = CopyAssetManifestIfNeeded(report, manifest)
    result.assetManifestAction = assetsAction
    if not assetsOk then
        -- Not fatal: OpenShim still loads every bundled resource; only its
        -- Settings page reports the asset pack missing until setup reruns.
        configOk = false
        configAction = tostring(configAction) .. "; " .. tostring(assetsAction)
    end
    if not configOk then
        -- The core suite is already staged and will still install on exit.
        -- OpenShim has in-code defaults, so a missing player INI is a warning,
        -- not a reason to claim the staged core update failed.
        result.detail = "core suite staged; " .. tostring(configAction)
    else
        result.detail = "OpenShim suite staged for verified replacement on game exit; openshim.ini " ..
            tostring(configAction)
    end

    result.after = OpenShimInstaller.Inspect()
    result.state = result.after.state
    if result.after.state == OpenShimInstaller.States.UPDATE_FAILED then
        result.success = false
        result.restartRequired = false
        result.action = "stage_failed_after_launch"
        result.detail = "OpenShim update helper reported failure: " ..
            tostring(result.after.updateStatus and result.after.updateStatus.detail or "unknown error")
    end
    return result
end

-- Normal campaign startup only inspects the installation. Applying updates is
-- an explicit setup-mission action; never complete a playable mission for it.
local function CheckBundledOpenShimOnce()
    if OpenShimInstaller.InstallChecked then
        return
    end
    OpenShimInstaller.InstallChecked = true

    local report = OpenShimInstaller.Inspect()
    local ready = report.state == OpenShimInstaller.States.CURRENT or
        report.state == OpenShimInstaller.States.NEWER_THAN_BUNDLED
    if not ready then
        local message = "Open Community Patch: run ! SETUP / REPAIR from Single Player > Instant Action."
        if report.state == OpenShimInstaller.States.RESTART_REQUIRED then
            message = "Open Community Patch update is pending. Exit Battlezone, restart, then verify with Setup / Repair."
        end
        print("OpenShimInstaller: campaign check=" .. tostring(report.state) .. "; " .. message)
        EmitFeedback(message, 1.0, 0.85, 0.2, 12.0, true)
    end
    return report
end

function OpenShimInstaller.CheckOnce(showFeedback)
    local previousFeedback = FeedbackCallback
    FeedbackCallback = showFeedback

    local ok, report = pcall(CheckBundledOpenShimOnce)

    FeedbackCallback = previousFeedback
    if not ok then
        error(report, 0)
    end
    return report
end

-- Retain the old entry point for consumers, with the same read-only policy.
function OpenShimInstaller.EnsureOnce(showFeedback)
    return OpenShimInstaller.CheckOnce(showFeedback)
end

return OpenShimInstaller
