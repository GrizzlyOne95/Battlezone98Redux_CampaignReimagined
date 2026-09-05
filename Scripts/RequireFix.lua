-- This module resolves Workshop / mod Lua paths and installs safe fallbacks
-- when Windows-only native DLLs are unavailable.
--
-- Module by DivisionByZero, GrizzlyOne95, and VTrider

local RequireFix = {}
do
    local version = "1.3"
    local workshopAppId = "301650"
    local originalPath = package.path or ""
    local originalCPath = package.cpath or ""
    local warnedMessages = {}
    local initialized = false
    local lastGameDirectory = "."
    local lastWorkshopDirectory = nil
    local lastActiveModRoot = nil
    local moduleDirectory = nil

    -- Redux can load the entry mission from an enabled Steam Workshop item
    -- without adding that item's directory to package.path/package.cpath.  Use
    -- this module's own source path as the authoritative runtime root so every
    -- subsequent Lua/native require resolves from the same enabled item.
    if debug and type(debug.getinfo) == "function" then
        local info = debug.getinfo(1, "S")
        local source = info and info.source
        if type(source) == "string" and source:sub(1, 1) == "@" then
            source = source:sub(2):gsub("/", "\\")
            moduleDirectory = source:match("^(.*)\\[^\\]+$")
        end
    end

    local function WarnOnce(key, message)
        if warnedMessages[key] then
            return
        end
        warnedMessages[key] = true

        if Print then
            Print(message)
        else
            print(message)
        end

        if AddTMsg then
            AddTMsg(message)
        end
    end

    local function SplitAtSemicolon(value)
        local results = {}
        for part in string.gmatch(value or "", "([^;]+)") do
            results[#results + 1] = part
        end
        return results
    end

    local function NormalizePath(value)
        if type(value) ~= "string" or value == "" then
            return nil
        end

        local normalized = value:gsub("/", "\\")
        normalized = normalized:gsub("\\+", "\\")
        normalized = normalized:gsub("\\%?%.dll$", "")
        normalized = normalized:gsub("\\%?%.lua$", "")
        normalized = normalized:gsub("\\%?%.so$", "")
        normalized = normalized:gsub("\\%?%.dylib$", "")
        normalized = normalized:gsub("\\$", "")
        return normalized
    end

    local function TrimKnownSuffix(path)
        if not path then
            return nil
        end

        local lower = string.lower(path)
        local markers = {
            "\\addon\\",
            "\\mods\\",
            "\\packaged_mods\\",
            "\\workshop\\content\\" .. workshopAppId .. "\\",
        }

        for _, marker in ipairs(markers) do
            local markerStart = string.find(lower, marker, 1, true)
            if markerStart then
                return path:sub(1, markerStart - 1)
            end
        end

        local commonMarkers = {
            "\\scripts\\",
            "\\lua\\",
            "\\bin\\",
        }
        for _, marker in ipairs(commonMarkers) do
            local markerStart = string.find(lower, marker, 1, true)
            if markerStart then
                return path:sub(1, markerStart - 1)
            end
        end

        local tailStart = string.match(path, "^.*()\\")
        if tailStart then
            return path:sub(1, tailStart - 1)
        end

        return path
    end

    local function DetectGameDirectory()
        local searchLists = { package.cpath or "", package.path or "", originalCPath, originalPath }
        local relativeFallback = nil
        local absoluteFallback = nil
        for _, pathList in ipairs(searchLists) do
            for _, entry in ipairs(SplitAtSemicolon(pathList)) do
                local normalized = NormalizePath(entry)
                local root = TrimKnownSuffix(normalized)
                if root and root ~= "" then
                    -- Relative entries such as `.\?.lua` appear first in
                    -- Redux and used to make us return `.` before reaching
                    -- the absolute Steam game path.  Prefer an absolute path
                    -- so the sibling Workshop content directory can be
                    -- derived reliably.
                    if root:match("^%a:\\") or root:match("^\\\\") then
                        absoluteFallback = absoluteFallback or root
                        if string.lower(root):match("\\battlezone 98 redux$") then
                            lastGameDirectory = root
                            return root
                        end
                    else
                        relativeFallback = relativeFallback or root
                    end
                end
            end
        end

        lastGameDirectory = absoluteFallback or relativeFallback or lastGameDirectory
        return lastGameDirectory
    end

    local function DetectActiveModRoot()
        local normalized = NormalizePath(moduleDirectory)
        if not normalized then
            return lastActiveModRoot
        end

        local lower = string.lower(normalized)
        local markers = {
            "\\steamapps\\workshop\\content\\" .. workshopAppId .. "\\",
            "\\addon\\",
            "\\mods\\",
            "\\packaged_mods\\",
        }

        for _, marker in ipairs(markers) do
            local markerStart = string.find(lower, marker, 1, true)
            if markerStart then
                local itemStart = markerStart + #marker
                if itemStart <= #normalized then
                    local itemEnd = string.find(normalized, "\\", itemStart, true)
                    local root = itemEnd and normalized:sub(1, itemEnd - 1) or normalized
                    if root and root ~= "" then
                        lastActiveModRoot = root
                        return root
                    end
                end
            end
        end

        return lastActiveModRoot
    end

    local function DetectWorkshopDirectory(gameDirectory)
        local paths = {
            moduleDirectory or "",
            package.cpath or "",
            package.path or "",
            originalCPath,
            originalPath,
        }
        for _, pathList in ipairs(paths) do
            for _, entry in ipairs(SplitAtSemicolon(pathList)) do
                local normalized = NormalizePath(entry)
                if normalized then
                    local lower = string.lower(normalized)
                    local marker = "\\steamapps\\workshop\\content\\" .. workshopAppId .. "\\"
                    local markerStart = string.find(lower, marker, 1, true)
                    if markerStart then
                        local root = normalized:sub(1, markerStart + #marker - 2)
                        lastWorkshopDirectory = root
                        return root
                    end
                end
            end
        end

        if type(gameDirectory) == "string" then
            local lower = string.lower(gameDirectory)
            local marker = "\\steamapps\\common\\"
            local markerStart = string.find(lower, marker, 1, true)
            if markerStart then
                local steamRoot = gameDirectory:sub(1, markerStart - 1)
                lastWorkshopDirectory = steamRoot .. "\\steamapps\\workshop\\content\\" .. workshopAppId
                return lastWorkshopDirectory
            end
        end

        return lastWorkshopDirectory
    end

    local function InsertUnique(target, seen, value)
        if not value or value == "" or seen[value] then
            return
        end
        seen[value] = true
        target[#target + 1] = value
    end

    local function BuildPathLists(workshopIDs)
        local gameDirectory = DetectGameDirectory()
        local workshopDirectory = DetectWorkshopDirectory(gameDirectory)
        local activeModRoot = DetectActiveModRoot()

        local originalLuaPaths = SplitAtSemicolon(originalPath)
        local originalDllPaths = SplitAtSemicolon(originalCPath)
        local luaPaths = {}
        local dllPaths = {}
        local seenLua = {}
        local seenDll = {}

        local function AddSearchRoot(root)
            if not root or root == "" then
                return
            end

            InsertUnique(luaPaths, seenLua, root .. "\\?.lua")
            InsertUnique(luaPaths, seenLua, root .. "\\Scripts\\?.lua")
            InsertUnique(luaPaths, seenLua, root .. "\\Lua\\?.lua")

            InsertUnique(dllPaths, seenDll, root .. "\\?.dll")
            InsertUnique(dllPaths, seenDll, root .. "\\Scripts\\?.dll")
            InsertUnique(dllPaths, seenDll, root .. "\\Lua\\?.dll")
        end

        -- Resolve the active Workshop/mod item from this module's physical source
        -- path.  The containing item root is authoritative and is always searched
        -- before optional external dependency IDs.  This makes Initialize() agnostic
        -- to Workshop republishing or local addon/mod/packaged_mod names.
        AddSearchRoot(activeModRoot)

        -- Keep the exact module directory as a fallback for unusual nested layouts.
        -- For the normal <root>\Scripts layout this is already covered above.
        AddSearchRoot(moduleDirectory)

        local ids = {}
        if type(workshopIDs) == "table" then
            -- Workshop IDs are an ordered search-precedence list.  ipairs keeps
            -- that precedence deterministic; pairs does not guarantee array order.
            for _, id in ipairs(workshopIDs) do
                ids[#ids + 1] = tostring(id)
            end
        elseif workshopIDs ~= nil then
            ids[#ids + 1] = tostring(workshopIDs)
        end

        if #ids == 0 then
            ids = { "campaignReimagined", "3686673790" }
        end

        for _, id in ipairs(ids) do
            AddSearchRoot(gameDirectory and (gameDirectory .. "\\addon\\" .. id) or nil)
            AddSearchRoot(gameDirectory and (gameDirectory .. "\\mods\\" .. id) or nil)
            AddSearchRoot(gameDirectory and (gameDirectory .. "\\packaged_mods\\" .. id) or nil)
            AddSearchRoot(workshopDirectory and (workshopDirectory .. "\\" .. id) or nil)
        end

        -- The enabled mod should win resolution.  Keep Redux's stock paths as
        -- fallbacks, but do not make every missing-module error enumerate them
        -- before reaching the Workshop item.
        for _, value in ipairs(originalLuaPaths) do
            InsertUnique(luaPaths, seenLua, value)
        end
        for _, value in ipairs(originalDllPaths) do
            InsertUnique(dllPaths, seenDll, value)
        end

        return table.concat(luaPaths, ";"), table.concat(dllPaths, ";"), gameDirectory, workshopDirectory, activeModRoot
    end

    local function CreateExuStub()
        local stub = {
            isStub = true,
            version = "stub",
            CAMERA = {},
            DEFAULTS = {},
            DIFFICULTY = {},
            OGRE = {},
            OVERLAY_METRICS = {},
            ORDNANCE = { TRANSFORM = 1 },
            RADAR = {},
            SATELLITE = {},
            BulletInit = nil,
            BulletHit = nil,
        }

        function stub.GetVersion()
            return "stub"
        end

        function stub.GetDifficulty()
            return 2
        end

        function stub.GetAutoLevel()
            return false
        end

        function stub.GetGameKey()
            return false
        end

        function stub.IsPauseMenuOpen()
            return false
        end

        -- Keep a small set of side-effect-only compatibility calls safe for
        -- scripts that invoke them unconditionally.  Do not manufacture an
        -- arbitrary function for every missing key: unsupported capabilities
        -- must remain nil so ordinary `if exu.SomeFeature then` checks are true
        -- capability checks rather than false positives.
        local function NoOp()
            return nil
        end

        stub.SetShotConvergence = NoOp
        stub.SetReticleRange = NoOp
        stub.SetOrdnanceVelocInheritance = NoOp
        stub.SetGlobalTurbo = NoOp
        stub.SetUnitTurbo = NoOp
        stub.UpdateOrdnance = NoOp
        stub.UpdateCommandReplacements = NoOp

        return stub
    end

    local function CreateBzfileStub(gameDirectory, workshopDirectory)
        local stub = { isStub = true }

        function stub.GetWorkingDirectory()
            return gameDirectory or "."
        end

        function stub.GetWorkshopDirectory()
            return workshopDirectory
        end

        function stub.Open()
            return nil
        end

        function stub.MakeDirectory()
            -- Match the native bzfile contract: success/no-op returns nil.
            return nil
        end

        return setmetatable(stub, {
            __index = function()
                return function()
                    return nil
                end
            end,
        })
    end

    local function InstallFallbackModule(name, module)
        package.preload[name] = function()
            return module
        end
        package.loaded[name] = module
        return module
    end

    local function EnsureNativeModule(name, factory, message)
        local loaded = package.loaded[name]
        if loaded ~= nil then
            return loaded
        end

        local ok, module = pcall(require, name)
        if ok then
            package.loaded[name] = module
            return module
        end

        WarnOnce(name, message .. " Native features will be reduced.")
        return InstallFallbackModule(name, factory())
    end

    local function Initialize(workshopID)
        if not initialized then
            -- Preserve legitimate package search-path changes made after this
            -- module was required but before initialization.  Do this only on
            -- the first initialization so subsequent calls do not treat our own
            -- injected paths as the stock/fallback baseline.
            originalPath = package.path or originalPath
            originalCPath = package.cpath or originalCPath
        end

        local luaPath, dllPath, gameDirectory, workshopDirectory, activeModRoot = BuildPathLists(workshopID)
        package.path = luaPath
        package.cpath = dllPath
        lastGameDirectory = gameDirectory or lastGameDirectory
        lastWorkshopDirectory = workshopDirectory or lastWorkshopDirectory
        lastActiveModRoot = activeModRoot or lastActiveModRoot
        initialized = true

        EnsureNativeModule(
            "exu",
            function()
                return CreateExuStub()
            end,
            "EXU.DLL could not be loaded. If you are on Linux, use Steam with Proton. Native macOS and native Linux DLL support are not available."
        )

        EnsureNativeModule(
            "bzfile",
            function()
                return CreateBzfileStub(lastGameDirectory, lastWorkshopDirectory)
            end,
            "bzfile.dll could not be loaded. Save/config features that depend on native file I/O will be disabled."
        )
    end

    local function SafeRequire(name)
        if not initialized then
            Initialize()
        end

        local ok, module = pcall(require, name)
        if ok then
            return module
        end
        return nil, module
    end

    RequireFix.version = version
    RequireFix.getGameDirectory = DetectGameDirectory
    RequireFix.getSteamWorkshopDirectory = function()
        return DetectWorkshopDirectory(DetectGameDirectory())
    end
    RequireFix.getActiveModRoot = DetectActiveModRoot
    RequireFix.Initialize = Initialize
    RequireFix.SafeRequire = SafeRequire
end

return RequireFix
