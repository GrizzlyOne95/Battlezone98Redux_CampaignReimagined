-- This module resolves Workshop / mod Lua paths and installs safe fallbacks
-- when Windows-only native DLLs are unavailable.
--
-- Module by DivisionByZero, GrizzlyOne95, and VTrider

local RequireFix = {}
do
    local version = "1.2"
    local workshopAppId = "301650"
    local originalPath = package.path or ""
    local originalCPath = package.cpath or ""
    local warnedMessages = {}
    local initialized = false
    local lastGameDirectory = "."
    local lastWorkshopDirectory = nil

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
        for _, pathList in ipairs(searchLists) do
            for _, entry in ipairs(SplitAtSemicolon(pathList)) do
                local normalized = NormalizePath(entry)
                local root = TrimKnownSuffix(normalized)
                if root and root ~= "" then
                    lastGameDirectory = root
                    return root
                end
            end
        end

        return lastGameDirectory
    end

    local function DetectWorkshopDirectory(gameDirectory)
        local paths = { package.cpath or "", package.path or "", originalCPath, originalPath }
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

        local luaPaths = SplitAtSemicolon(originalPath)
        local dllPaths = SplitAtSemicolon(originalCPath)
        local seenLua = {}
        local seenDll = {}

        for _, value in ipairs(luaPaths) do
            seenLua[value] = true
        end
        for _, value in ipairs(dllPaths) do
            seenDll[value] = true
        end

        local ids = {}
        if type(workshopIDs) == "table" then
            for _, id in pairs(workshopIDs) do
                ids[#ids + 1] = tostring(id)
            end
        elseif workshopIDs ~= nil then
            ids[#ids + 1] = tostring(workshopIDs)
        end

        for _, id in ipairs(ids) do
            local roots = {
                gameDirectory and (gameDirectory .. "\\addon\\" .. id) or nil,
                gameDirectory and (gameDirectory .. "\\mods\\" .. id) or nil,
                gameDirectory and (gameDirectory .. "\\packaged_mods\\" .. id) or nil,
                workshopDirectory and (workshopDirectory .. "\\" .. id) or nil,
            }

            for _, root in ipairs(roots) do
                if root then
                    InsertUnique(luaPaths, seenLua, root .. "\\?.lua")
                    InsertUnique(luaPaths, seenLua, root .. "\\Scripts\\?.lua")
                    InsertUnique(luaPaths, seenLua, root .. "\\Lua\\?.lua")

                    InsertUnique(dllPaths, seenDll, root .. "\\?.dll")
                    InsertUnique(dllPaths, seenDll, root .. "\\Scripts\\?.dll")
                    InsertUnique(dllPaths, seenDll, root .. "\\Lua\\?.dll")
                end
            end
        end

        return table.concat(luaPaths, ";"), table.concat(dllPaths, ";"), gameDirectory, workshopDirectory
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

        return setmetatable(stub, {
            __index = function()
                return function()
                    return nil
                end
            end,
        })
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
            return false
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
        local luaPath, dllPath, gameDirectory, workshopDirectory = BuildPathLists(workshopID)
        package.path = luaPath
        package.cpath = dllPath
        lastGameDirectory = gameDirectory or lastGameDirectory
        lastWorkshopDirectory = workshopDirectory or lastWorkshopDirectory
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
    RequireFix.Initialize = Initialize
    RequireFix.SafeRequire = SafeRequire
end

return RequireFix
