-- Pure Lua 5.1 tests for the optional assetSets/assetFiles manifest sections.
package.path = "Scripts/?.lua;" .. package.path

local working = "C:\\Users\\Alice\\Games\\Battlezone 98 Redux"
local markers = {}

package.preload["bzfile"] = function()
    return {
        GetWorkingDirectory = function() return working end,
        GetWorkshopDirectory = function() return "C:\\Workshop" end,
        Exists = function() return false end,
        GetFileHash = function() return nil, "missing" end,
        GetFileVersion = function() return nil, "missing" end,
        Open = function(path)
            local content = markers[path]
            if content == nil then error("test file unavailable: " .. tostring(path)) end
            local consumed = false
            return {
                Read = function()
                    if consumed then return "" end
                    consumed = true
                    return content
                end,
                Close = function() end,
            }
        end,
    }
end
package.preload["LogPaths"] = function()
    return { Path = function(name) return working .. "\\logs\\\\" .. tostring(name) end }
end

local function Hex(char) return string.rep(char, 64) end

local function BaseManifest()
    return {
        formatVersion = 3, size = 1234, version = "1.0.0.99", architecture = "x86", sha256 = Hex("a"),
        payloads = {
            winmm = { size = 1234, source = "winmm.dll", destination = "winmm.dll", sha256 = Hex("a"),
                version = "1.0.0.99", architecture = "x86" },
            loader = { source = "bzloader.dll", destination = "bzloader.dll", sha256 = Hex("1"),
                size = 2345, version = "1.0.0.99", architecture = "x86" },
            plugin = { source = "openshim.dll", destination = "plugins\\openshim.dll", sha256 = Hex("2"),
                size = 3456, version = "1.0.0.99", architecture = "x86" },
            helper = { source = "bzfile_replace_helper.exe", sha256 = Hex("3"), size = 4567 },
            network = { size = 100, source = "openshim_net.ini.payload", destination = "net.ini", sha256 = Hex("b") },
            patches = { size = 100, source = "openshim_patches.json.payload",
                destination = "scripts\\patches.json", sha256 = Hex("c") },
            playerConfig = { size = 100, source = "openshim.ini.payload", destination = "openshim.ini",
                sha256 = Hex("d"), overwrite = false },
            assetManifest = { size = 100, source = "OpenShimAssets.ini.payload",
                destination = "openshim\\OpenShimAssets.ini", sha256 = Hex("4") },
        },
    }
end

local function WithAssets(manifest)
    manifest.assetSets = {
        renderer = { source = "openshim\\renderer\\enhanced", destination = "openshim\\renderer\\enhanced",
            sha256 = Hex("e"), files = 2 },
        customWidgets = { source = "BZ_ASSETS_CORE\\common\\ui\\CustomWidgets",
            destination = "BZ_ASSETS_CORE\\common\\ui\\CustomWidgets", sha256 = Hex("f"), files = 1 },
    }
    manifest.assetFiles = {
        { set = "renderer", path = "resources.version", sha256 = Hex("5"), size = 2 },
        { set = "renderer", path = "sub\\a-b_1.glsl", sha256 = string.upper(Hex("6")), size = 10 },
        { set = "customWidgets", path = "uibtn.png", sha256 = Hex("7"), size = 99 },
    }
    return manifest
end

local function Inspect(manifest)
    package.loaded["OpenShimInstaller"] = nil
    package.preload["OpenShimManifest"] = function() return manifest end
    package.loaded["OpenShimManifest"] = nil
    return require("OpenShimInstaller").Inspect(), require("OpenShimInstaller")
end

local function Valid(report) return report.manifest.valid == true end

-- Without the sections the manifest stays valid and reports no asset status.
local report = Inspect(BaseManifest())
assert(Valid(report), "manifest without sections must parse")
assert(next(report.assets) == nil)

-- With the sections it parses; hashes are lowercased; the marker states report.
markers = {}
report = Inspect(WithAssets(BaseManifest()))
assert(Valid(report))
assert(report.assets.renderer.state == "MISSING", report.assets.renderer.state)
assert(report.assets.renderer.files == 2)
assert(report.assets.customWidgets.expectedSha256 == Hex("f"))

markers[working .. "\\openshim\\renderer\\enhanced\\openshim_set.sha256"] = Hex("e") .. "\n"
markers[working .. "\\BZ_ASSETS_CORE\\common\\ui\\CustomWidgets\\openshim_widgets.sha256"] = Hex("0") .. "\n"
local installer
report, installer = Inspect(WithAssets(BaseManifest()))
assert(report.assets.renderer.state == "CURRENT", report.assets.renderer.state)
assert(report.assets.customWidgets.state == "REFRESH_PENDING", report.assets.customWidgets.state)
local text = installer.FormatDiagnosticReport(report)
assert(text:find("ASSET_RENDERER_STATE=CURRENT", 1, true), text)
assert(text:find("ASSET_CUSTOMWIDGETS_STATE=REFRESH_PENDING", 1, true), text)
assert(not text:find("Alice", 1, true), text)

-- Malformed sections are dropped (not fatal): the payload suite still parses.
local mutations = {
    function(m) m.assetFiles = nil end,
    function(m) m.assetSets = nil end,
    function(m) m.assetSets.renderer.sha256 = "xyz" end,
    function(m) m.assetSets.renderer.files = 3 end,
    function(m) m.assetSets.renderer.files = 1.5 end,
    function(m) m.assetFiles[1].set = "unknown" end,
    function(m) m.assetFiles[1].path = "bad path.txt" end,
    function(m) m.assetFiles[1].path = "..\\evil.dll" end,
    function(m) m.assetFiles[1].path = "a/b" end,
    function(m) m.assetFiles[1].sha256 = Hex("g") end,
    function(m) m.assetFiles[1].size = -1 end,
    function(m) m.assetSets.renderer.destination = "" end,
    function(m) m.assetFiles = "nope" end,
}
for index, mutate in ipairs(mutations) do
    local manifest = WithAssets(BaseManifest())
    mutate(manifest)
    report = Inspect(manifest)
    assert(Valid(report), "mutation " .. index .. " must not invalidate the payload suite")
    assert(next(report.assets) == nil, "mutation " .. index .. " must drop the asset sections")
end

-- The committed manifest parses with the sections and passes the same checks.
package.loaded["OpenShimInstaller"] = nil
package.loaded["OpenShimManifest"] = nil
package.preload["OpenShimManifest"] = nil
local committed = dofile("Scripts/OpenShimManifest.lua")
assert(committed.formatVersion == 3)
assert(type(committed.assetSets) == "table" and type(committed.assetFiles) == "table",
    "committed manifest must carry asset sections")
report = Inspect(committed)
assert(Valid(report))
assert(report.assets.renderer and report.assets.renderer.files >= 1)
assert(report.assets.customWidgets and report.assets.customWidgets.files >= 1)

print("OpenShim manifest asset section tests passed")
