-- AutoSave.lua
---@diagnostic disable: lowercase-global, undefined-global

local bzfile = require("bzfile")

local AutoSave = {}
local AUTOSAVE_SUBTITLE_DURATION = 3.0
local AUTOSAVE_INITIAL_DELAY_SECONDS = 10.0
local SUBTITLE_FONT_SCALE_MIN = 0.85
local SUBTITLE_FONT_SCALE_MAX = 2.00

AutoSave.Config = {
    enabled = true,
    autoSaveInterval = 300,
    currentSlot = 1,
    currentPath = "Save\\auto.sav",
}
AutoSave._forceInitialSave = false

local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

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
        return file:Dump()
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

local function getSubtitleSettings()
    local persistentConfig = package.loaded["PersistentConfig"]
    local scriptSubtitles = package.loaded["ScriptSubtitles"]
    local settings = {
        enabled = false,
        opacity = 0.5,
        fontScale = 1.0,
    }

    if persistentConfig and persistentConfig.Settings then
        if persistentConfig.Settings.SubtitlesEnabled ~= nil then
            settings.enabled = not not persistentConfig.Settings.SubtitlesEnabled
        end
        if persistentConfig.Settings.SubtitleOpacity ~= nil then
            settings.opacity = tonumber(persistentConfig.Settings.SubtitleOpacity) or settings.opacity
        end
        if persistentConfig.Settings.SubtitleFontScale ~= nil then
            settings.fontScale = tonumber(persistentConfig.Settings.SubtitleFontScale) or settings.fontScale
        end
    end

    if scriptSubtitles and scriptSubtitles.Config then
        if scriptSubtitles.Config.enabled ~= nil then
            settings.enabled = not not scriptSubtitles.Config.enabled
        end
        if scriptSubtitles.Config.opacity ~= nil then
            settings.opacity = tonumber(scriptSubtitles.Config.opacity) or settings.opacity
        end
        if scriptSubtitles.Config.fontScale ~= nil then
            settings.fontScale = tonumber(scriptSubtitles.Config.fontScale) or settings.fontScale
        end
    end

    settings.opacity = clamp(settings.opacity, 0.0, 1.0)
    settings.fontScale = clamp(settings.fontScale, SUBTITLE_FONT_SCALE_MIN, SUBTITLE_FONT_SCALE_MAX)
    return settings
end

local function tryExperimentalAutoSaveOverlay(duration)
    local persistentConfig = package.loaded["PersistentConfig"]
    if not persistentConfig or type(persistentConfig.TryShowAutoSaveOverlayInfo) ~= "function" then
        print("AutoSave: EXU overlay unavailable (PersistentConfig helper missing)")
        return false
    end

    local ok, shown = pcall(persistentConfig.TryShowAutoSaveOverlayInfo, "Autosaving...", duration or
        AUTOSAVE_SUBTITLE_DURATION, 0.82, 1.0, 0.82)
    if not ok then
        print("AutoSave: EXU overlay call failed: " .. tostring(shown))
        return false
    end
    if shown == true then
        print("AutoSave: notification using EXU overlay")
        return true
    end
    print("AutoSave: EXU overlay not shown; mission overlay fallback will be used")
    return false
end

local function showAutoSaveNotification()
    local settings = getSubtitleSettings()
    if not settings.enabled then
        print("AutoSave: notification suppressed because subtitles are disabled")
        return
    end

    if tryExperimentalAutoSaveOverlay(AUTOSAVE_SUBTITLE_DURATION) then
        return
    end

    local scriptSubtitles = package.loaded["ScriptSubtitles"]
    if not scriptSubtitles or type(scriptSubtitles.Display) ~= "function" then
        print("AutoSave: mission overlay notification unavailable")
        return
    end

    print("AutoSave: notification using mission overlay fallback")
    pcall(scriptSubtitles.Display, "Autosaving...", 0.82, 1.0, 0.82, AUTOSAVE_SUBTITLE_DURATION)
end

local function getMissionTitleFromLocalization(missionFilename)
    local workingDir = bzfile.GetWorkingDirectory()
    local localizationPath = joinPath(workingDir, "localization_table.csv")
    local data = readAllText(localizationPath)
    if not data then
        return nil
    end

    local normalizedMission = missionFilename:lower()
    local targets = {
        "mission_title:" .. normalizedMission
    }
    if not normalizedMission:match("%.bzn$") then
        targets[#targets + 1] = "mission_title:" .. normalizedMission .. ".bzn"
    end

    for line in data:gmatch("[^\r\n]+") do
        local normalized = trim(line)
        local lowered = normalized:lower()
        for _, target in ipairs(targets) do
            if lowered:sub(1, #target) == target then
                local title = normalized:match("^[^~]*~([^~]+)")
                title = trim(title)
                if title ~= "" then
                    return title
                end
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

local function formatMissionMinutesLabel(missionSeconds)
    local wholeMinutes = math.floor(math.max(0.0, tonumber(missionSeconds) or 0.0) / 60.0)
    return tostring(wholeMinutes)
end

local function buildAutoSaveDescription(missionSeconds)
    local missionName = trim(resolveMissionDisplayName())
    if missionName == "" then
        missionName = "Unknown Mission"
    end
    local missionMinutes = formatMissionMinutesLabel(missionSeconds)
    local minuteLabel = (missionMinutes == "1") and "min" or "min"
    return string.format("%s - AutoSave - %s %s", missionName, missionMinutes, minuteLabel)
end

local function getAutoSavePaths()
    local saveDir = joinPath(bzfile.GetWorkingDirectory(), "Save")
    local backupDir = joinPath(saveDir, "AutoSaveBackups")
    local configuredPath = trim(AutoSave.Config.currentPath)
    local relativePath = configuredPath ~= "" and configuredPath or "Save\\auto.sav"
    local filename = relativePath
    if not relativePath:match("^[A-Za-z]:[\\/]")
        and not relativePath:match("^[\\/]")
        and not relativePath:lower():match("^save[\\/]") then
        filename = joinPath(saveDir, relativePath)
    elseif relativePath:lower():match("^save[\\/]") then
        filename = joinPath(bzfile.GetWorkingDirectory(), relativePath)
    end

    local basename = filename:match("([^\\/]+)$") or "auto.sav"
    local backupStem = basename:gsub("%.sav$", "")
    local backupname = joinPath(backupDir, backupStem .. ".pre_autosave.sav")
    local labelPath = joinPath(saveDir, backupStem .. ".label.txt")
    return filename, backupname, backupDir, labelPath
end

local function writeAutoSaveLabel(labelPath, desc)
    local trimmed = trim(desc)
    if labelPath == "" or trimmed == "" then
        return
    end

    local labelFile = bzfile.Open(labelPath, "w", "trunc")
    if not labelFile then
        print("AutoSave: WARNING - could not open autosave label file for writing: " .. labelPath)
        return
    end

    labelFile:Write(trimmed)
    labelFile:Close()
end

local function ensureBackupDirectory(backupDir)
    if not backupDir or backupDir == "" or type(bzfile) ~= "table" or type(bzfile.MakeDirectory) ~= "function" then
        return
    end

    local ok, err = pcall(bzfile.MakeDirectory, backupDir)
    if not ok then
        print("AutoSave: NOTE - could not pre-create backup directory " .. tostring(backupDir) .. ": " .. tostring(err))
    end
end

local function backupOriginalSaveIfNeeded(filename, backupname, backupDir)
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

    local data = existingSave:Dump()
    existingSave:Close()
    if not data or #data == 0 then
        return true
    end

    ensureBackupDirectory(backupDir)
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
    local filename, backupname, backupDir, labelPath = getAutoSavePaths()

    if not backupOriginalSaveIfNeeded(filename, backupname, backupDir) then
        print("AutoSave: backup failed, aborting native save for " .. filename)
        return false
    end

    if type(exu) ~= "table" or type(exu.SaveGame) ~= "function" then
        print("AutoSave: native save unavailable, exu.SaveGame is missing")
        return false
    end

    local ok, pathOrError = exu.SaveGame(filename, desc)
    if ok then
        writeAutoSaveLabel(labelPath, desc)
        print("AutoSave: native save completed to " .. tostring(pathOrError or filename))
        showAutoSaveNotification()
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
        AutoSave._initialDelayDeadline = nil
        return
    end

    local now = GetTime()
    local missionTime = math.floor(now)

    if AutoSave._forceInitialSave or not AutoSave._wasEnabled or not AutoSave._lastSaveTime then
        if not AutoSave._initialDelayDeadline then
            AutoSave._initialDelayDeadline = now + AUTOSAVE_INITIAL_DELAY_SECONDS
            print(string.format("AutoSave: delaying initial save for %.1fs", AUTOSAVE_INITIAL_DELAY_SECONDS))
        end
        if now < AutoSave._initialDelayDeadline then
            return
        end

        print("AutoSave: initial save at " .. missionTime .. "s")
        AutoSave.CreateSave(nil, buildAutoSaveDescription(now))
        AutoSave._lastSaveTime = now
        AutoSave._wasEnabled = true
        AutoSave._forceInitialSave = false
        AutoSave._initialDelayDeadline = nil
        return
    end

    if (now - AutoSave._lastSaveTime) < AutoSave.Config.autoSaveInterval then
        return
    end

    print("AutoSave: saving at " .. missionTime .. "s")

    AutoSave.CreateSave(nil, buildAutoSaveDescription(now))
    AutoSave._lastSaveTime = now
end

_G.AutoSave = AutoSave
return AutoSave
