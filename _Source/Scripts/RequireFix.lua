-- This module lets you grab your steam workshop directory 
-- in order to require modules from any mod, including DLLs

-- Module by DivisionByZero, GrizzlyOne95, and VTrider

-- Version 1.1

local RequireFix = {}
do

    local version = "1.1"
    
    -- Cache original paths to prevent bloat on multiple initializations
    local original_path = package.path
    local original_cpath = package.cpath

    local function splitAtSemicolon(str)
        local results = {}
        for substr in string.gmatch(str, '([^;]+)') do
            table.insert(results, substr)
        end
        return results
    end

    local function getGameDirectory()
        -- Resilient scan: check all paths in cpath for common markers
        local paths = splitAtSemicolon(package.cpath)
        for _, path in ipairs(paths) do
            -- Look for the path containing the game engine DLLs or the standard 'addon' folder
            local match = string.match(path, "(.*)\\addon")
            if not match then
                -- Match against the folder containing the executable if possible
                match = string.match(path, "(.*)\\?")
            end
            
            if match then
                -- Simple sanity check: does it look like a BZ98R/BZCC folder?
                -- (We don't do deep file checks here to keep it fast, but we prioritize the addon-related path)
                if string.find(match:lower(), "battlezone") or string.find(path:lower(), "addon") then
                    return match
                end
            end
        end
        
        -- Fallback to original logic if scan fails
        local path = paths[2] or paths[1]
        return string.match(path, "(.*)\\%?") or "."
    end

    local function getSteamWorkshopDirectory()
        local gameDirectory = getGameDirectory()
        -- Improved detection to handle GOG or variations in folder naming
        local steamRootIndex = string.find(gameDirectory:lower(), "steamapps\\common")
        if steamRootIndex then
            local steamRoot = gameDirectory:sub(1, steamRootIndex - 1)
            
            -- Hardcoded for BZ98R (301650)
            local appID = "301650"
            
            return steamRoot .. "steamapps\\workshop\\content\\" .. appID
        end
        return nil
    end

    local function Initialize(workshopID)
        local gameDirectory = getGameDirectory()
        local workshopDir = getSteamWorkshopDirectory()
        
        -- Always start from original paths to prevent duplicates/bloat
        local LuaPath = original_path
        local DLLPath = original_cpath

        local function addPaths(id)
            local roots = {
                gameDirectory .. "\\addon\\" .. id,
                gameDirectory .. "\\mods\\" .. id,
                gameDirectory .. "\\packaged_mods\\" .. id
            }
            
            -- 3rd Party Workshop Path
            if workshopDir then
                table.insert(roots, workshopDir .. "\\" .. id)
            end

            for _, root in ipairs(roots) do
                -- Root level
                LuaPath = LuaPath .. ";" .. root .. "\\?.lua"
                DLLPath = DLLPath .. ";" .. root .. "\\?.dll"
                
                -- Scripts subfolder
                LuaPath = LuaPath .. ";" .. root .. "\\Scripts\\?.lua"
                DLLPath = DLLPath .. ";" .. root .. "\\Scripts\\?.dll"
                
                -- Lua subfolder
                LuaPath = LuaPath .. ";" .. root .. "\\Lua\\?.lua"
                DLLPath = DLLPath .. ";" .. root .. "\\Lua\\?.dll"
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

    RequireFix.version                   = version
    RequireFix.getSteamWorkshopDirectory = getSteamWorkshopDirectory
    RequireFix.Initialize                = Initialize

end
return RequireFix