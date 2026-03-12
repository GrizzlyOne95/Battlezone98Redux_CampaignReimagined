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

    local ok, pathOrError = exu.SaveGame(filename)
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
        return
    end

    local now = GetTime()
    if not AutoSave._lastSaveTime then
        AutoSave._lastSaveTime = now
    end

    if (now - AutoSave._lastSaveTime) < AutoSave.Config.autoSaveInterval then
        return
    end

    local missionName = GetMissionFilename():gsub("%.bzn$", "")
    local missionTime = math.floor(now)
    print("AutoSave: saving at " .. missionTime .. "s")

    AutoSave.CreateSave(nil, string.format("%s AutoSave %ds", missionName, missionTime))
    AutoSave._lastSaveTime = now
end

_G.AutoSave = AutoSave
return AutoSave
