-- Pure Lua 5.1 smoke tests for OpenShimInstaller diagnostics.
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

local function Put(path, hash, version)
    exists[path] = true
    fileHashes[path] = hash
    if version then versions[path] = version end
end

Put(modRoot .. "\\winmm.dll", hashes.winmm, manifest.version)
Put(modRoot .. "\\openshim_net.ini.payload", hashes.network)
Put(modRoot .. "\\openshim_patches.json.payload", hashes.patches)
Put(modRoot .. "\\openshim.ini.payload", hashes.playerConfig)
Put(modRoot .. "\\bzfile_replace_helper.exe", "helper")
Put(working .. "\\winmm.dll", hashes.winmm, manifest.version)
Put(working .. "\\net.ini", hashes.network)
Put(working .. "\\scripts\\patches.json", hashes.patches)
Put(working .. "\\openshim.ini", hashes.customConfig)

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
            error("test file unavailable: " .. tostring(path))
        end,
        StageOpenShimSuiteUpdate = function() return true, "staged" end,
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

local report = Installer.Inspect()
assert(report.state == Installer.States.CURRENT, report.state)
assert(report.installed.playerConfig.state == "CUSTOMIZED", report.installed.playerConfig.state)
assert(report.helper.exists == true)
assert(report.stagingAvailable == true)

local formatted = Installer.FormatDiagnosticReport(report)
assert(not formatted:find("Alice", 1, true), formatted)
assert(formatted:find("INSTALLED_WINMM_PATH=<GAME>\\winmm.dll", 1, true), formatted)
assert(formatted:find("PAYLOAD_WINMM_SOURCE=<MOD>\\winmm.dll", 1, true), formatted)
assert(formatted:find("WORKSHOP_DIRECTORY=<WORKSHOP>", 1, true), formatted)
assert(formatted:find("INSTALLED_PLAYER_CONFIG_STATE=CUSTOMIZED", 1, true), formatted)

exists[working .. "\\winmm.dll"] = false
fileHashes[working .. "\\winmm.dll"] = nil
versions[working .. "\\winmm.dll"] = nil
report = Installer.Inspect()
assert(report.state == Installer.States.INSTALL_REQUIRED, report.state)

exists[working .. "\\winmm.dll"] = true
fileHashes[working .. "\\winmm.dll"] = hashes.winmm
versions[working .. "\\winmm.dll"] = manifest.version
fileHashes[modRoot .. "\\winmm.dll"] = string.rep("f", 64)
report = Installer.Inspect()
assert(report.state == Installer.States.PAYLOAD_HASH_MISMATCH, report.state)

print("OpenShimInstaller diagnostics tests passed")
