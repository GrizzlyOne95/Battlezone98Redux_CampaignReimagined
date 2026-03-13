-- AutoSave.lua
---@diagnostic disable: lowercase-global, undefined-global

local bzfile = require("bzfile")
local exu = require("exu")

local AutoSave = {}

AutoSave.Config = {
    enabled = true,
    autoSaveInterval = 300,
    currentSlot = 1,
    initialSaveDelay = 15,
    createBackups = false
}

local function getSlotPaths(slot)
    local saveDir = bzfile.GetWorkingDirectory() .. "\\Save\\"
    return saveDir .. "game" .. slot .. ".sav", saveDir
end

local function backupOriginalSave(filename, backupDir, slot)
    local existingSave = bzfile.Open(filename, "r")
    if not existingSave then
        return true
    end

    local data = existingSave:Read()
    existingSave:Close()
    if not data or #data == 0 then
        return true
    end

    local backupIndex = 1
    local backupname = nil
    while true do
        backupname = string.format("%sgame%d.%03d.bak", backupDir, slot, backupIndex)
        local existingBackup = bzfile.Open(backupname, "r")
        if not existingBackup then
            break
        end
        existingBackup:Close()
        backupIndex = backupIndex + 1
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
    local filename, backupDir = getSlotPaths(slotNum)

    if AutoSave.Config.createBackups then
        if not backupOriginalSave(filename, backupDir, slotNum) then
            print("AutoSave: backup failed, aborting native save for " .. filename)
            return false
        end
    end

    if type(exu) ~= "table" or type(exu.SaveGame) ~= "function" then
        print("AutoSave: native save unavailable, exu.SaveGame is missing")
        return false
    end

    print("AutoSave: calling native save for " .. filename .. " (type 1 first)")
    local callOk, ok, pathOrError = pcall(exu.SaveGame, filename, 1)
    if callOk and ok == false then
        print("AutoSave: native save type 1 returned false, retrying default type")
        ok, pathOrError = exu.SaveGame(filename)
    elseif not callOk then
        print("AutoSave: native save type 1 call failed, retrying default type: " .. tostring(ok))
        ok, pathOrError = exu.SaveGame(filename)
    end
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
        AutoSave._initialSaveDone = false
        AutoSave._enabledAt = nil
        return
    end

    local now = GetTime()
    local missionName = GetMissionFilename():gsub("%.bzn$", "")
    local missionTime = math.floor(now)

    if not AutoSave._wasEnabled then
        AutoSave._wasEnabled = true
        AutoSave._initialSaveDone = false
        AutoSave._enabledAt = now
        AutoSave._lastSaveTime = now
    end

    if not AutoSave._initialSaveDone then
        local enabledAt = AutoSave._enabledAt or now
        local initialDelay = AutoSave.Config.initialSaveDelay or 15
        if (now - enabledAt) < initialDelay then
            return
        end

        print("AutoSave: initial save at " .. missionTime .. "s")
        if AutoSave.CreateSave(nil, string.format("%s AutoSave %ds", missionName, missionTime)) then
            AutoSave._lastSaveTime = now
            AutoSave._initialSaveDone = true
        end
        return
    end

    if (now - AutoSave._lastSaveTime) < AutoSave.Config.autoSaveInterval then
        return
    end

    print("AutoSave: saving at " .. missionTime .. "s")

    if AutoSave.CreateSave(nil, string.format("%s AutoSave %ds", missionName, missionTime)) then
        AutoSave._lastSaveTime = now
    end
end

_G.AutoSave = AutoSave
return AutoSave
