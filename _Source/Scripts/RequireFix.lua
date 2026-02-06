-- This module lets you grab your steam workshop directory 
-- in order to require modules from any mod, including DLLs

-- Module by DivisionByZero, GrizzlyOne95, and VTrider

-- Version 1.0

local RequireFix = {}
do

    local version = "1.0"

    -- Function to print field names of an object
    local function splitAtSemicolon(str)
        local results = {}
        for substr in string.gmatch(str, '([^;]+)') do
            table.insert(results, substr)
        end
        return results
    end

    local function getGameDirectory()
        local path = splitAtSemicolon(package.cpath)[2]
        return string.match(path, "(.*)\\%?")
    end

    -- directory = getGameDirectory()
    -- print("bz directory is: " .. directory)

    local function getSteamWorkshopDirectory()
        local gameDirectory = getGameDirectory()
        -- Try to find Steam library root to locate workshop content
        local commonIndex = string.find(gameDirectory, "steamapps\\common\\Battlezone 98 Redux")
        if commonIndex then
            local steamRoot = gameDirectory:sub(1, commonIndex - 1)
            return steamRoot .. "steamapps\\workshop\\content\\301650"
        end
        return nil
    end

    -- This sets the path and cpath to the user defined value, it can take a 
    -- single workshop ID or a table of IDs and add them sequentially to the 
    -- correct path -VTrider
    local function Initialize(workshopID)
        local gameDirectory = getGameDirectory()
        local workshopDir = getSteamWorkshopDirectory()
        local defaultPath = package.path
        local defaultCPath = package.cpath
        local LuaPath = defaultPath
        local DLLPath = defaultCPath

        local function addPaths(id)
            -- 1. Local Addon Path
            local localPath = gameDirectory .. "\\addon\\" .. id
            LuaPath = LuaPath .. ";" .. localPath .. "\\?.lua"
            DLLPath = DLLPath .. ";" .. localPath .. "\\?.dll"
            
            -- 2. Workshop Path
            if workshopDir then
                local wsPath = workshopDir .. "\\" .. id
                LuaPath = LuaPath .. ";" .. wsPath .. "\\?.lua"
                DLLPath = DLLPath .. ";" .. wsPath .. "\\?.dll"
            end
        end

        if type(workshopID) == "table" then
            for _, id in pairs(workshopID) do
                addPaths(id)
            end
        else
            addPaths(workshopID)
        end

        package.path = LuaPath
        package.cpath = DLLPath
    end

    -- Example usage
    -- local steamWorkshopDirectory = getSteamWorkshopDirectory()
    -- print("Steam Workshop Directory:" .. steamWorkshopDirectory)
    RequireFix.version                   = version
    RequireFix.getSteamWorkshopDirectory = getSteamWorkshopDirectory
    RequireFix.Initialize                = Initialize

end
return RequireFix