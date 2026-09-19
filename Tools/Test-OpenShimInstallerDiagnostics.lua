-- Pure Lua 5.1 smoke tests for OpenShimInstaller diagnostics and setup actions.
package.path = "Scripts/?.lua;" .. package.path

local working = "C:\\Users\\Alice\\Games\\Battlezone 98 Redux"
local workshop = "C:\\Users\\Alice\\Steam\\steamapps\\workshop\\content\\301650"
local modRoot = workshop .. "\\3686673790"

local hashes = {
    winmm = string.rep("a", 64),
    network = string.rep("b", 64),
    patches = string.rep("c", 64),
    playerConfig = string.rep("d", 64),
    customConfig = string.rep("e", 64),
}

local manifest = {
    formatVersion = 2,
    version = "1.0.0.99",
    architecture = "x86",
    sha256 = hashes.winmm,
    payloads = {
        winmm = {
            source = "winmm.dll",
            destination = "winmm.dll",
            sha256 = hashes.winmm,
            version = "1.0.0.99",
            architecture = "x86",
        },
        network = {
            source = "openshim_net.ini.payload",
            destination = "net.ini",
            sha256 = hashes.network,
        },
        patches = {
            source = "openshim_patches.json.payload",
            destination = "scripts\\patches.json",
            sha256 = hashes.patches,
        },
        playerConfig = {
            source = "openshim.ini.payload",
            destination = "openshim.ini",
            sha256 = hashes.playerConfig,
            overwrite = false,
        },
    },
}

local exists = {}
local fileHashes = {}
local versions = {}
local statusContent = nil
local stageCalls = 0
local copyCalls = 0

local function Put(path, hash, version)
    exists[path] = true
    fileHashes[path] = hash
    if version then versions[path] = version end
end

local function Remove(path)
    exists[path] = false
    fileHashes[path] = nil
    versions[path] = nil
end

local function ResetInstalledCurrent()
    Put(working .. "\\winmm.dll", hashes.winmm, manifest.version)
    Put(working .. "\\net.ini", hashes.network)
    Put(working .. "\\scripts\\patches.json", hashes.patches)
    Put(working .. "\\openshim.ini", hashes.customConfig)
    statusContent = nil
end

Put(modRoot .. "\\winmm.dll", hashes.winmm, manifest.version)
Put(modRoot .. "\\openshim_net.ini.payload", hashes.network)
Put(modRoot .. "\\openshim_patches.json.payload", hashes.patches)
Put(modRoot .. "\\openshim.ini.payload", hashes.playerConfig)
Put(modRoot .. "\\bzfile_replace_helper.exe", "helper")
ResetInstalledCurrent()

package.preload["bzfile"] = function()
    return {
        GetWorkingDirectory = function() return working end,
        GetWorkshopDirectory = function() return workshop end,
        Exists = function(path) return exists[path] == true end,
        GetFileHash = function(path)
            local value = fileHashes[path]
            if value then return value end
            return nil, "missing"
        end,
        GetFileVersion = function(path)
            local value = versions[path]
            if value then return value end
            return nil, "missing"
        end,
        Open = function(path)
            if path == working .. "\\openshim_update.status" and statusContent then
                local consumed = false
                return {
                    Read = function()
                        if consumed then return "" end
                        consumed = true
                        return statusContent
                    end,
                    Close = function() end,
                }
            end
            error("test file unavailable: " .. tostring(path))
        end,
        CopyFile = function(source, destination)
            copyCalls = copyCalls + 1
            if not exists[source] then return false, "source missing" end
            exists[destination] = true
            fileHashes[destination] = fileHashes[source]
            versions[destination] = versions[source]
            return true
        end,
        StageOpenShimSuiteUpdate = function()
            stageCalls = stageCalls + 1
            statusContent =
                "state=staged\nexpected_sha256=" .. hashes.winmm ..
                "\npayload_count=3\n"
            return true, "staged", working .. "\\logs\\openshim_update.log"
        end,
    }
end

package.preload["LogPaths"] = function()
    return {
        Path = function(name)
            return working .. "\\logs\\" .. tostring(name)
        end,
    }
end

package.preload["OpenShimManifest"] = function()
    return manifest
end

local Installer = require("OpenShimInstaller")

-- Healthy custom config: inspect current, no-op apply, no config overwrite.
local report = Installer.Inspect()
assert(report.state == Installer.States.CURRENT, report.state)
assert(report.installed.playerConfig.state == "CUSTOMIZED", report.installed.playerConfig.state)
assert(report.helper.exists == true)
assert(report.stagingAvailable == true)
local result = Installer.Apply(report)
assert(result.success == true)
assert(result.action == "none")
assert(stageCalls == 0)
assert(copyCalls == 0)

local formatted = Installer.FormatDiagnosticReport(report)
assert(not formatted:find("Alice", 1, true), formatted)
assert(formatted:find("INSTALLED_WINMM_PATH=<GAME>\\winmm.dll", 1, true), formatted)
assert(formatted:find("PAYLOAD_WINMM_SOURCE=<MOD>\\winmm.dll", 1, true), formatted)
assert(formatted:find("WORKSHOP_DIRECTORY=<WORKSHOP>", 1, true), formatted)
assert(formatted:find("INSTALLED_PLAYER_CONFIG_STATE=CUSTOMIZED", 1, true), formatted)

-- Missing player config only: install it directly without staging/restart.
Remove(working .. "\\openshim.ini")
report = Installer.Inspect()
assert(report.state == Installer.States.UPDATE_REQUIRED, report.state)
result = Installer.Apply(report)
assert(result.success == true)
assert(result.action == "config_installed", result.action)
assert(result.restartRequired == false)
assert(result.after.state == Installer.States.CURRENT, result.after.state)
assert(stageCalls == 0)
assert(copyCalls == 1)

-- Missing OpenShim: stage the core suite and preserve an existing custom config.
ResetInstalledCurrent()
Remove(working .. "\\winmm.dll")
report = Installer.Inspect()
assert(report.state == Installer.States.INSTALL_REQUIRED, report.state)
local copiesBeforeInstall = copyCalls
result = Installer.Apply(report)
assert(result.success == true)
assert(result.action == "install_staged", result.action)
assert(result.restartRequired == true)
assert(result.after.state == Installer.States.RESTART_REQUIRED, result.after.state)
assert(stageCalls == 1)
assert(copyCalls == copiesBeforeInstall)

-- Existing staged update: do not launch a duplicate helper.
local stagesBeforePending = stageCalls
report = Installer.Inspect()
assert(report.state == Installer.States.RESTART_REQUIRED, report.state)
result = Installer.Apply(report)
assert(result.success == true)
assert(result.action == "already_staged")
assert(result.restartRequired == true)
assert(stageCalls == stagesBeforePending)

-- Newer manual install: preserve it and do not stage older support files.
ResetInstalledCurrent()
Put(working .. "\\winmm.dll", string.rep("9", 64), "2.0.0.0")
report = Installer.Inspect()
assert(report.state == Installer.States.NEWER_THAN_BUNDLED, report.state)
local stagesBeforeNewer = stageCalls
result = Installer.Apply(report)
assert(result.success == true)
assert(result.action == "none")
assert(stageCalls == stagesBeforeNewer)

-- Corrupt bundled payload: fail closed without touching the install.
ResetInstalledCurrent()
fileHashes[modRoot .. "\\winmm.dll"] = string.rep("f", 64)
report = Installer.Inspect()
assert(report.state == Installer.States.PAYLOAD_HASH_MISMATCH, report.state)
local stagesBeforeCorrupt = stageCalls
result = Installer.Apply(report)
assert(result.success == false)
assert(result.action == "blocked")
assert(stageCalls == stagesBeforeCorrupt)
fileHashes[modRoot .. "\\winmm.dll"] = hashes.winmm

-- Previous failed update plus an outdated support file: retry by staging once.
ResetInstalledCurrent()
Put(working .. "\\net.ini", string.rep("7", 64))
statusContent =
    "state=failed\nexpected_sha256=" .. hashes.winmm ..
    "\ndetail=previous replacement failed\n"
report = Installer.Inspect()
assert(report.state == Installer.States.UPDATE_FAILED, report.state)
local stagesBeforeRetry = stageCalls
result = Installer.Apply(report)
assert(result.success == true)
assert(result.action == "update_staged", result.action)
assert(result.restartRequired == true)
assert(stageCalls == stagesBeforeRetry + 1)

print("OpenShimInstaller diagnostics/action tests passed")
