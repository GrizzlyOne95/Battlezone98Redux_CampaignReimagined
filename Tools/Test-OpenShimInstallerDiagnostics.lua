-- Pure Lua 5.1 smoke tests for OpenShimInstaller diagnostics and setup actions.
package.path = "Scripts/?.lua;" .. package.path

local working = "C:\\Users\\Alice\\Games\\Battlezone 98 Redux"
local workshop = "C:\\Users\\Alice\\Steam\\steamapps\\workshop\\content\\301650"
local modRoot = workshop .. "\\3686673790"

local hashes = {
    winmm = string.rep("a", 64),
    loader = string.rep("1", 64),
    plugin = string.rep("2", 64),
    helper = string.rep("3", 64),
    network = string.rep("b", 64),
    patches = string.rep("c", 64),
    playerConfig = string.rep("d", 64),
    customConfig = string.rep("e", 64),
}

local manifest = {
    formatVersion = 3,
    size = 1234,
    version = "1.0.0.99",
    architecture = "x86",
    sha256 = hashes.winmm,
    payloads = {
        winmm = {
            size = 1234,
            source = "winmm.dll",
            destination = "winmm.dll",
            sha256 = hashes.winmm,
            version = "1.0.0.99",
            architecture = "x86",
        },
        loader = {
            source = "bzloader.dll", destination = "bzloader.dll",
            sha256 = hashes.loader, size = 2345, version = "1.0.0.99", architecture = "x86",
        },
        plugin = {
            source = "openshim.dll", destination = "plugins\\openshim.dll",
            sha256 = hashes.plugin, size = 3456, version = "1.0.0.99", architecture = "x86",
        },
        helper = { source = "bzfile_replace_helper.exe", sha256 = hashes.helper, size = 4567 },
        network = {
            size = 100,
            source = "openshim_net.ini.payload",
            destination = "net.ini",
            sha256 = hashes.network,
        },
        patches = {
            size = 100,
            source = "openshim_patches.json.payload",
            destination = "scripts\\patches.json",
            sha256 = hashes.patches,
        },
        playerConfig = {
            size = 100,
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
local writeCalls = 0
local deleteCalls = 0

-- Installer checks during playable mission startup must never alter progression.
SucceedMission = function() error("installer check completed a playable mission") end
FailMission = function() error("installer check ended a playable mission") end

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
    Put(working .. "\\bzloader.dll", hashes.loader, manifest.version)
    Put(working .. "\\plugins\\openshim.dll", hashes.plugin, manifest.version)
    Put(working .. "\\net.ini", hashes.network)
    Put(working .. "\\scripts\\patches.json", hashes.patches)
    Put(working .. "\\openshim.ini", hashes.customConfig)
    statusContent = nil
end

Put(modRoot .. "\\winmm.dll", hashes.winmm, manifest.version)
Put(modRoot .. "\\bzloader.dll", hashes.loader, manifest.version)
Put(modRoot .. "\\openshim.dll", hashes.plugin, manifest.version)
Put(modRoot .. "\\openshim_net.ini.payload", hashes.network)
Put(modRoot .. "\\openshim_patches.json.payload", hashes.patches)
Put(modRoot .. "\\openshim.ini.payload", hashes.playerConfig)
Put(modRoot .. "\\bzfile_replace_helper.exe", hashes.helper)
ResetInstalledCurrent()

-- Whether an update helper currently owns the update mutex.
local helperActive = true

package.preload["bzfile"] = function()
    return {
        IsOpenShimUpdateActive = function() return helperActive end,
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
        Open = function(path, mode)
            if mode == "w" then writeCalls = writeCalls + 1 end
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
        Delete = function() deleteCalls = deleteCalls + 1 end,
        StageOpenShimSuiteUpdateV3 = function(...)
            local args = {...}
            assert(#args == 11)
            assert(args[7] == modRoot .. "\\bzloader.dll" and args[8] == hashes.loader)
            assert(args[9] == modRoot .. "\\openshim.dll" and args[10] == hashes.plugin)
            assert(args[11] == hashes.helper)
            stageCalls = stageCalls + 1
            statusContent =
                "state=staged\nexpected_sha256=" .. hashes.winmm ..
                "\npayload_count=5\n"
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

-- The same pending status with no helper running was left by a helper that
-- never finished: it must not block a fresh staging forever.
helperActive = false
report = Installer.Inspect()
assert(report.updateStatus.stale == true)
assert(report.state == Installer.States.INSTALL_REQUIRED, report.state)
result = Installer.Apply(report)
assert(result.success == true)
assert(result.action == "install_staged", result.action)
assert(stageCalls == stagesBeforePending + 1)
helperActive = true

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

-- A current bootstrap alone is not a current installation: repair either missing link.
for _, path in ipairs({working .. "\\bzloader.dll", working .. "\\plugins\\openshim.dll"}) do
    ResetInstalledCurrent()
    Remove(path)
    report = Installer.Inspect()
    assert(report.state == Installer.States.UPDATE_REQUIRED, report.state)
    result = Installer.Apply(report)
    assert(result.success and result.restartRequired, result.detail)
end

-- Old protocols and incomplete or mismatched component identities fail closed.
ResetInstalledCurrent()
manifest.formatVersion = 2
assert(Installer.Inspect().state == Installer.States.MANIFEST_INVALID)
manifest.formatVersion = 3
local plugin = manifest.payloads.plugin
manifest.payloads.plugin = nil
assert(Installer.Inspect().state == Installer.States.MANIFEST_INVALID)
manifest.payloads.plugin = plugin
plugin.destination = "openshim.dll"
assert(Installer.Inspect().state == Installer.States.MANIFEST_INVALID)
plugin.destination = "plugins\\openshim.dll"

-- Do not execute a helper changed since packaging or since the inspection.
Put(modRoot .. "\\bzfile_replace_helper.exe", string.rep("f", 64))
assert(Installer.Inspect().state == Installer.States.PAYLOAD_HASH_MISMATCH)
Put(modRoot .. "\\bzfile_replace_helper.exe", hashes.helper)
Remove(working .. "\\bzloader.dll")
report = Installer.Inspect()
Put(modRoot .. "\\bzfile_replace_helper.exe", string.rep("f", 64))
local before = stageCalls
result = Installer.Apply(report)
assert(not result.success and stageCalls == before)
Put(modRoot .. "\\bzfile_replace_helper.exe", hashes.helper)
local bzfile = require("bzfile")
local stageV3 = bzfile.StageOpenShimSuiteUpdateV3
bzfile.StageOpenShimSuiteUpdateV3 = nil
assert(Installer.Inspect().state == Installer.States.STAGING_UNAVAILABLE)
bzfile.StageOpenShimSuiteUpdateV3 = stageV3

-- Gameplay checks are read-only for current, missing, pending and mismatched
-- installs. In particular, a net.ini difference must not stage a suite update
-- or display the old mission-success installation screen.
local function CheckGameplay(expectedState)
    local stages, copies, writes, deletes = stageCalls, copyCalls, writeCalls, deleteCalls
    Installer.InstallChecked = false
    local messages = {}
    local checked = Installer.CheckOnce(function(message) messages[#messages + 1] = message end)
    assert(checked.state == expectedState, checked.state)
    assert(stageCalls == stages and copyCalls == copies)
    assert(writeCalls == writes and deleteCalls == deletes)
    if expectedState ~= Installer.States.CURRENT then
        assert(#messages == 1 and messages[1]:lower():find("setup", 1, true))
    else
        assert(#messages == 0)
    end
    assert(Installer.CheckOnce() == nil, "check should run once per mission Lua state")
end

ResetInstalledCurrent()
CheckGameplay(Installer.States.CURRENT)
Put(working .. "\\net.ini", string.rep("7", 64))
CheckGameplay(Installer.States.UPDATE_REQUIRED)
Installer.InstallChecked = false
assert(Installer.EnsureOnce().state == Installer.States.UPDATE_REQUIRED)
ResetInstalledCurrent()
Remove(working .. "\\winmm.dll")
CheckGameplay(Installer.States.INSTALL_REQUIRED)
ResetInstalledCurrent()
Remove(working .. "\\openshim.ini")
CheckGameplay(Installer.States.UPDATE_REQUIRED)
ResetInstalledCurrent()
statusContent = "state=staged\nexpected_sha256=" .. hashes.winmm .. "\n"
CheckGameplay(Installer.States.RESTART_REQUIRED)
ResetInstalledCurrent()
statusContent = "state=complete\nexpected_sha256=" .. hashes.winmm .. "\n"
CheckGameplay(Installer.States.CURRENT)
assert(statusContent ~= nil, "campaign check must preserve setup status")

print("OpenShimInstaller diagnostics/action/gameplay-check tests passed")
