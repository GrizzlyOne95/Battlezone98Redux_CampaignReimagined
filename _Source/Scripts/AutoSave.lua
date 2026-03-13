-- AutoSave.lua
---@diagnostic disable: lowercase-global, undefined-global

local bzfile = require("bzfile")
local exu = require("exu")

local AutoSave = {}

AutoSave.Config = {
    enabled = true,
    autoSaveInterval = 300,
    currentSlot = 1
}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function readAllText(path)
    if not path or path == "" then
        return nil
    end

    local file = bzfile.Open(path, "r")
    if not file then
        return nil
    end

    local ok, data = pcall(function()
        return file:Read()
    end)
    file:Close()

    if not ok or type(data) ~= "string" or data == "" then
        return nil
    end

    return data
end

local function joinPath(root, leaf)
    if not root or root == "" then
        return leaf
    end

    local lastChar = root:sub(-1)
    if lastChar == "\\" or lastChar == "/" then
        return root .. leaf
    end

    return root .. "\\" .. leaf
end

local function getMissionTitleFromLocalization(missionFilename)
    local workingDir = bzfile.GetWorkingDirectory()
    local localizationPath = joinPath(workingDir, "localization_table.csv")
    local data = readAllText(localizationPath)
    if not data then
        return nil
    end

    local target = ("mission_title:" .. missionFilename):lower()
    for line in data:gmatch("[^\r\n]+") do
        local normalized = trim(line)
        if normalized:lower():sub(1, #target) == target then
            local title = normalized:match("^[^~]*~([^~]+)")
            title = trim(title)
            if title ~= "" then
                return title
            end
        end
    end

    return nil
end

local function getMissionTitleFromIni(missionBase)
    local candidates = {
        missionBase .. ".ini",
        joinPath(bzfile.GetWorkingDirectory(), missionBase .. ".ini")
    }

    for _, path in ipairs(candidates) do
        local data = readAllText(path)
        if data then
            local inDescription = false
            for line in data:gmatch("[^\r\n]+") do
                local normalized = trim(line)
                if normalized:sub(1, 1) == ";" or normalized == "" then
                    -- Skip comments and empty lines.
                elseif normalized:match("^%[.-%]$") then
                    inDescription = normalized:lower() == "[description]"
                elseif inDescription then
                    local missionName = normalized:match('^missionName%s*=%s*"(.-)"%s*$')
                        or normalized:match("^missionName%s*=%s*(.-)%s*$")
                    missionName = trim(missionName)
                    if missionName ~= "" then
                        return missionName
                    end
                end
            end
        end
    end

    return nil
end

local function resolveMissionDisplayName()
    local missionFilename = trim((GetMissionFilename() or ""):gsub("%z.*", ""))
    if missionFilename == "" then
        return "Unknown Mission"
    end

    if AutoSave._cachedMissionFilename == missionFilename and AutoSave._cachedMissionTitle then
        return AutoSave._cachedMissionTitle
    end

    local missionBase = missionFilename:gsub("%.bzn$", "")
    local displayName = getMissionTitleFromLocalization(missionFilename)
        or getMissionTitleFromIni(missionBase)
        or missionBase

    AutoSave._cachedMissionFilename = missionFilename
    AutoSave._cachedMissionTitle = displayName
    return displayName
end

local function getSlotPaths(slot)
    local saveDir = bzfile.GetWorkingDirectory() .. "\\Save\\"
    return saveDir .. "game" .. slot .. ".sav", saveDir .. "game" .. slot .. ".bak"
end

local function backupOriginalSaveIfNeeded(filename, backupname)
    local existingBackup = bzfile.Open(backupname, "r")
    if existingBackup then
        existingBackup:Close()
        print("AutoSave: backup already exists, skipping backup of " .. filename)
        return true
    end

    local existingSave = bzfile.Open(filename, "r")
    if not existingSave then
        return true
    end

    local data = existingSave:Read()
    existingSave:Close()
    if not data or #data == 0 then
        return true
    end

    local backupFile = bzfile.Open(backupname, "w", "trunc")
    if not backupFile then
        print("AutoSave: WARNING - could not open backup file for writing: " .. backupname)
        return false
    end

    backupFile:Write(data)
    backupFile:Close()
    print("AutoSave: backed up existing save to " .. backupname)
    return true
end

function AutoSave.CreateSave(slot, desc)
    local slotNum = slot or AutoSave.Config.currentSlot
    local filename, backupname = getSlotPaths(slotNum)

    if not backupOriginalSaveIfNeeded(filename, backupname) then
        print("AutoSave: backup failed, aborting native save for " .. filename)
        return false
    end

    if type(exu) ~= "table" or type(exu.SaveGame) ~= "function" then
        print("AutoSave: native save unavailable, exu.SaveGame is missing")
        return false
    end

    local ok, pathOrError = exu.SaveGame(slotNum, desc)
    if ok then
        print("AutoSave: native save completed to " .. tostring(pathOrError or filename))
        return true
    end

    print("AutoSave: native save failed: " .. tostring(pathOrError))
    if desc then
        print("AutoSave: native save ignores requested description: " .. tostring(desc))
    end
    return false
end

function AutoSave.Update(dtime)
    if not AutoSave.Config.enabled then
        AutoSave._wasEnabled = false
        return
    end

    local now = GetTime()
    local missionName = resolveMissionDisplayName()
    local missionTime = math.floor(now)

    if not AutoSave._wasEnabled or not AutoSave._lastSaveTime then
        print("AutoSave: initial save at " .. missionTime .. "s")
        AutoSave.CreateSave(nil, string.format("%s AutoSave %ds", missionName, missionTime))
        AutoSave._lastSaveTime = now
        AutoSave._wasEnabled = true
        return
    end

    if (now - AutoSave._lastSaveTime) < AutoSave.Config.autoSaveInterval then
        return
    end

    print("AutoSave: saving at " .. missionTime .. "s")

    AutoSave.CreateSave(nil, string.format("%s AutoSave %ds", missionName, missionTime))
    AutoSave._lastSaveTime = now
end

_G.AutoSave = AutoSave
return AutoSave
