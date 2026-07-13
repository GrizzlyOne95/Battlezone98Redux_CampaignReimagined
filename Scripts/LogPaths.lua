-- Central location for Campaign Reimagined runtime diagnostics.
local bzfileOk, bzfile = pcall(require, "bzfile")
if not bzfileOk then bzfile = nil end

local LogPaths = {}
local cachedDirectory = nil

local function GetWorkingDirectory()
    if bzfile and type(bzfile.GetWorkingDirectory) == "function" then
        local ok, value = pcall(bzfile.GetWorkingDirectory)
        if ok and type(value) == "string" and value ~= "" then
            return value:gsub("[\\/]+$", "")
        end
    end
    return "."
end

function LogPaths.GetDirectory()
    if cachedDirectory then return cachedDirectory end

    local directory = GetWorkingDirectory() .. "\\logs"
    if bzfile and type(bzfile.MakeDirectory) == "function" then
        local ok = pcall(bzfile.MakeDirectory, directory)
        if not ok then
            cachedDirectory = GetWorkingDirectory()
            return cachedDirectory
        end
    end

    cachedDirectory = directory
    return cachedDirectory
end

function LogPaths.Path(fileName)
    local leaf = tostring(fileName or "campaignReimagined.log")
        :match("([^\\/]+)$") or "campaignReimagined.log"
    return LogPaths.GetDirectory() .. "\\" .. leaf
end

return LogPaths
