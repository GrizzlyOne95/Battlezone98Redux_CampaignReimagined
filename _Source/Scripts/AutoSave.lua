-- AutoSave.lua
---@diagnostic disable: lowercase-global, undefined-global

local bzfile = require("bzfile")
local exu = require("exu")
local subtitles = nil

do
    local ok, module = pcall(require, "subtitles")
    if ok and type(module) == "table" then
        subtitles = module
    end
end

local AutoSave = {}
local AUTOSAVE_SUBTITLE_CHANNEL = 4
local AUTOSAVE_SUBTITLE_DURATION = 3.0
local SUBTITLE_FONT_SCALE_MIN = 0.85
local SUBTITLE_FONT_SCALE_MAX = 2.00

AutoSave.Config = {
    enabled = true,
    autoSaveInterval = 300,
    currentSlot = 1,
    currentPath = "Save\\auto.sav",
}

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

local function getAutoSaveSubtitleLayout(fontScale)
    local width, height = 1920, 1080
    local uiScale = 2.0

    if exu and exu.GetScreenResolution then
        local ok, screenW, screenH = pcall(exu.GetScreenResolution)
        if ok and type(screenW) == "number" and screenW > 0 and type(screenH) == "number" and screenH > 0 then
            width, height = screenW, screenH
        end
    elseif exu and exu.GetGameResolution then
        local ok, gameW, gameH = pcall(exu.GetGameResolution)
        if ok and type(gameW) == "number" and gameW > 0 and type(gameH) == "number" and gameH > 0 then
            width, height = gameW, gameH
        end
    end

    if exu and exu.GetUIScaling then
        local ok, value = pcall(exu.GetUIScaling)
        if ok and type(value) == "number" and value > 0 then
            uiScale = value
        end
    end

    local aspect = width / math.max(height, 1)
    local aspectScale = clamp((16.0 / 9.0) / aspect, 0.82, 1.35)
    local uiScaleFactor = clamp((uiScale / 2.0) ^ 0.32, 0.90, 1.30)
    local compactFontScale = clamp(fontScale ^ 0.45, 0.92, 1.20)

    return {
        x = 0.015,
        y = 0.975,
        textScale = clamp(0.20 * aspectScale * uiScaleFactor * compactFontScale, 0.18, 0.32),
        wrapWidth = clamp(0.22 * clamp(1.0 / aspectScale, 0.90, 1.18) * compactFontScale, 0.18, 0.34),
        paddingX = 8.0 * compactFontScale,
        paddingY = 6.0 * compactFontScale,
        borderSize = 1.0,
    }
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
    print("AutoSave: EXU overlay not shown; subtitle fallback will be used")
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

    if not subtitles or not subtitles.submit_to or not subtitles.set_channel_layout then
        print("AutoSave: subtitle notification unavailable")
        return
    end

    print("AutoSave: notification using subtitle fallback")
    local layout = getAutoSaveSubtitleLayout(settings.fontScale)
    if subtitles.set_opacity then
        pcall(subtitles.set_opacity, settings.opacity)
    end
    if subtitles.clear_queue then
        pcall(subtitles.clear_queue, AUTOSAVE_SUBTITLE_CHANNEL)
    end
    if subtitles.clear_current then
        pcall(subtitles.clear_current, AUTOSAVE_SUBTITLE_CHANNEL)
    end
    pcall(subtitles.set_channel_layout, AUTOSAVE_SUBTITLE_CHANNEL, layout.x, layout.y, 0.0, 1.0, layout.textScale,
        layout.wrapWidth, layout.paddingX, layout.paddingY, layout.borderSize)
    pcall(subtitles.submit_to, AUTOSAVE_SUBTITLE_CHANNEL, "Autosaving...", AUTOSAVE_SUBTITLE_DURATION, 0.82, 1.0, 0.82)
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
    return filename, backupname, backupDir
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
    local filename, backupname, backupDir = getAutoSavePaths()

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
