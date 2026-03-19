-- PersistentConfig.lua
---@diagnostic disable: lowercase-global, undefined-global
local bzfile = require("bzfile")
local exu = require("exu")
local autosave = require("AutoSave")
local RuntimeEnhancements = require("RuntimeEnhancements")
local ConservativeCulling = require("ConservativeCulling")

local PersistentConfig = {}
PersistentConfig.D = require("PersistentConfigD")
PersistentConfig.ReactiveReticleModule = require("ReactiveReticle")
PersistentConfig.Channels = {
    WeaponStats = 1,
    PdaFeedback = 2,
}
PersistentConfig.Debug = false
PersistentConfig.ExperimentalOverlayReady = false
PersistentConfig.ExperimentalOverlayFailed = false
PersistentConfig.ExperimentalOverlayVisible = false
PersistentConfig.ExperimentalOverlayExpireAt = 0.0
PersistentConfig.ExperimentalOverlayDebugBox = false
PersistentConfig.ExperimentalOverlayForcePixelMetrics = true
PersistentConfig.ExperimentalOverlayDebugZOrder = 650
PersistentConfig.ExperimentalOverlayPending = nil
PersistentConfig.PdaOverlay = {
    ready = false,
    failed = false,
    font = "CRBZoneOverlayFont",
    useCustomFont = true,
    zOrder = 645,
    structureVersion = 7,
    statsVisible = false,
    feedbackVisible = false,
    feedbackExpireAt = 0.0,
    ids = {
        stats = {
            overlay = "cr_pda_stats_overlay",
            root = "cr_pda_stats_overlay_root",
            frame = "cr_pda_stats_overlay_frame",
            backdrop = "cr_pda_stats_overlay_backdrop",
            header = "cr_pda_stats_overlay_header",
            title = "cr_pda_stats_overlay_title",
            tabs = "cr_pda_stats_overlay_tabs",
            text = "cr_pda_stats_overlay_text",
            footer = "cr_pda_stats_overlay_footer",
        },
        feedback = {
            overlay = "cr_pda_feedback_overlay",
            root = "cr_pda_feedback_overlay_root",
            backdrop = "cr_pda_feedback_overlay_backdrop",
            text = "cr_pda_feedback_overlay_text",
        },
    },
}
local InputState
local ShowFeedback
PersistentConfig.PlayerChargeWeaponState = PersistentConfig.PlayerChargeWeaponState or nil

-- Internal Feedback Queue
PersistentConfig.FeedbackQueue = {}

-- Default Settings (cloned into Settings to allow reset)
local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for k, v in pairs(value) do
        result[k] = DeepCopy(v)
    end
    return result
end

PersistentConfig.DefaultSettings = {
    HeadlightDiffuse = { R = 5.0, G = 5.0, B = 5.0 },                         -- White
    HeadlightSpecular = { R = 5.0, G = 5.0, B = 5.0 },                         -- White specular
    HeadlightRange = { InnerAngle = 0.6, OuterAngle = 0.9, Falloff = 0.35 },   -- Default to Wide
    HeadlightBeamMode = 2,                                                      -- 1 = Focused, 2 = Wide
    HeadlightVisible = true,
    SubtitlesEnabled = true,
    OtherHeadlightsDisabled = true, -- AI Lights Off by default
    AutoRepairWingmen = true,       -- Auto-repair wingmen on by default
    RainbowMode = false,            -- Special color effect
    ScavengerAssistEnabled = true,  -- Auto-scavenge for player scavengers
    AutoSaveSlot = 10,              -- Legacy setting kept for config compatibility
    AutoSaveEnabled = false,        -- AutoSave disabled by default
    AutoSaveInterval = 300,         -- Auto-save every 5 minutes
    AutoRepairBuildings = false,    -- Toggle to auto-repair buildings near power
    LightingMode = 1,               -- 1=Default 2=Enhanced 3=Retro
    RetroLighting = false,          -- Legacy compatibility mirror for LightingMode=Retro
    WeaponStatsHud = true,          -- Persistent weapon stats panel
    PilotModeEnabled = false,       -- Player-side pilot mode automation
    UnitVerbosity = 1,              -- 1=Normal 2=Decreased 3=None
    SubtitleOpacity = 0.50,         -- Main subtitle opacity
    SubtitleFontScale = 2.00,       -- Subtitle font scale (0.85-2.00)
    PdaOpacity = 1.00,              -- PDA/weapon HUD opacity
    PdaFontScale = 1.30,            -- PDA font/window scale (0.85-1.30)
    PdaColorPreset = 2,             -- 1=Dark Green 2=Green 3=Blue 4=White
    TargetReticlePopupMode = 1,     -- 1=Default 3=Explicit Only (legacy 2 downgrades to Default)
    ScrapPilotHudLayout = 2,        -- 1=Stock 2=Legacy
    RadarSizeScale = 1.00,          -- Independent radar size scale
    DynamicFactionFlameColors = false, -- Team flame colors from faction nation codes
}

PersistentConfig.Settings = DeepCopy(PersistentConfig.DefaultSettings)

local PdaPages = {
    STATS = 1,
    TARGET = 2,
    SETTINGS = 3,
    PRESETS = 4,
    QUEUE = 5,
    COMMAND = 6,
    COUNT = 6,
}

local PresetProducerKinds = {
    [1] = { name = "RECYCLER", getter = GetRecyclerHandle, short = "REC" },
    [2] = { name = "FACTORY", getter = GetFactoryHandle, short = "FAC" },
}

PersistentConfig.PresetConfig = {
    surcharge = {
        mortarFlat = 1.0,
        multipliers = { 0.5, 0.25 },
        tailMultiplier = 0.1,
    },
    build = {
        keyWindow = 0.5,
        refundGrace = 1.0,
        scrapConfirmTolerance = 0.5,
    },
}

PersistentConfig.UnitPresets = {}
PersistentConfig._SettingsActions = {}
local GetSettingsPageEntries
local GetProducerQueueState
local CleanString
local ClampUnitInterval
local GetPlayerTeamNum

PersistentConfig.FontScale = {
    pda = { min = 0.85, max = 1.30, step = 0.05 },
    subtitle = { min = 0.85, max = 2.00, step = 0.05 },
}
PersistentConfig.RadarUi = {
    min = 0.50,
    max = 2.00,
    step = 0.05,
}
PersistentConfig.AutoSaveUi = {
    filePath = "Save\\auto.sav",
    fileLabel = "AUTO.SAV",
    slotMin = 1,
    slotMax = 10,
    intervalOptions = {
        { seconds = 120, label = "2 min" },
        { seconds = 300, label = "5 min" },
        { seconds = 600, label = "10 min" },
    },
}
PersistentConfig.UnitVoUi = {
    applyTeam = 1,
    fallbackBaseline = {
        throttleMs = 0,
        queueDepthLimit = 2,
        queueStaleMs = 2000,
    },
}

PersistentConfig.OpenShimInstaller = {
    bundledRootName = "winmm.dll",
    restartObjectiveId = "openshim_restart_required",
    updateObjectiveId = "openshim_update_required",
    manualObjectiveId = "openshim_install_manual",
    restartMessage = "OpenShim installed. Restart Battlezone to enable native AutoSave UI.",
    updateMessage = "OpenShim updated. Restart Battlezone to enable the latest native AutoSave UI.",
}

local LEGACY_TEXT_PRESET_SCALES = {
    [1] = 0.85,
    [2] = 1.00,
    [3] = 1.15,
    [4] = 1.30,
}

local PdaColorPresets = {
    [1] = { name = "DARK GREEN", r = 0.10, g = 0.42, b = 0.10 },
    [2] = { name = "GREEN", r = 0.18, g = 0.92, b = 0.18 },
    [3] = { name = "BLUE", r = 0.35, g = 0.65, b = 1.00 },
    [4] = { name = "WHITE", r = 1.00, g = 1.00, b = 1.00 },
}

PersistentConfig.UnitVerbosityPresets = {
    [1] = { name = "NORMAL", useBaseline = true },
    [2] = { name = "DECREASED", throttleMs = 750, queueDepthLimit = 1, queueStaleMs = 1200 },
    [3] = { name = "NONE", muted = true, throttleMs = 60000, queueDepthLimit = 1, queueStaleMs = 0 },
}

PersistentConfig.TargetReticlePopupPresets = {
    [1] = { name = "DEFAULT", mode = 1 },
    [2] = { name = "EXPLICIT ONLY", mode = 3 },
}

local PdaPanelMaterialFamilies = {
    { key = "DG", r = 0.10, g = 0.42, b = 0.10 },
    { key = "G", r = 0.18, g = 0.92, b = 0.18 },
    { key = "B", r = 0.35, g = 0.65, b = 1.00 },
    { key = "W", r = 1.00, g = 1.00, b = 1.00 },
    { key = "R", r = 1.00, g = 0.35, b = 0.35 },
}

local ScrapPilotHudLayouts = {
    [1] = { name = "STOCK" },
    [2] = { name = "LEGACY" },
}
local ScrapPilotHudMaterialNames = {
    "HUDcombi",
    "HUDcomba",
}
local StockScrapPilotHudTexture = "GreenHUD.png"

local HeadlightColorPresets = {
    [1] = { name = "WHITE", r = 5.0, g = 5.0, b = 5.0 },
    [2] = { name = "RED", r = 5.0, g = 1.0, b = 1.0 },
    [3] = { name = "GREEN", r = 1.0, g = 5.0, b = 1.0 },
    [4] = { name = "BLUE", r = 1.0, g = 1.0, b = 5.0 },
    [5] = { name = "YELLOW", r = 5.0, g = 5.0, b = 1.0 },
    [6] = { name = "CYAN", r = 1.0, g = 5.0, b = 5.0 },
    [7] = { name = "MAGENTA", r = 5.0, g = 1.0, b = 5.0 },
    [8] = { name = "ORANGE", r = 5.0, g = 2.5, b = 1.0 },
    [9] = { name = "PURPLE", r = 2.5, g = 1.0, b = 5.0 },
    [10] = { name = "TEAL", r = 1.0, g = 5.0, b = 2.5 },
    [11] = { name = "RAINBOW", rainbow = true, feedbackR = 1.0, feedbackG = 0.5, feedbackB = 1.0 },
}

local function getWorkingDirectory()
    return (bzfile and bzfile.GetWorkingDirectory and bzfile.GetWorkingDirectory()) or "."
end
PersistentConfig.ConfigPath = getWorkingDirectory() .. "\\campaignReimagined_settings.cfg"

local function BzFileExists(path)
    if not path or path == "" then
        return false
    end

    if bzfile and type(bzfile.Exists) == "function" then
        local ok, exists = pcall(bzfile.Exists, path)
        if ok then
            return not not exists
        end
    end

    if io and type(io.open) == "function" then
        local file = io.open(path, "rb")
        if file then
            file:close()
            return true
        end
    end

    if bzfile and type(bzfile.Open) == "function" then
        local ok = pcall(function()
            local handle = bzfile.Open(path, "r")
            handle:Read(1)
            handle:Close()
        end)
        if ok then
            return true
        end
    end

    return false
end

local function GetBzFileHash(path)
    if not path or path == "" then
        return nil
    end

    if bzfile and type(bzfile.GetFileHash) == "function" then
        local ok, hashOrNil, errorMessage = pcall(bzfile.GetFileHash, path, "sha256")
        if ok and type(hashOrNil) == "string" and hashOrNil ~= "" then
            return string.lower(hashOrNil)
        end

        local detail = ok and tostring(errorMessage or "unknown error") or tostring(hashOrNil)
        print("PersistentConfig: GetFileHash failed for " .. tostring(path) .. ": " .. detail)
    end

    return nil
end

local function GetBundledOpenShimSourcePath()
    local workingDirectory = getWorkingDirectory()
    local candidates = {
        workingDirectory .. "\\addon\\campaignReimagined\\" .. PersistentConfig.OpenShimInstaller.bundledRootName,
        workingDirectory .. "\\addon\\campaignReimagined\\_Release\\" .. PersistentConfig.OpenShimInstaller.bundledRootName,
        workingDirectory .. "\\addon\\campaignReimagined\\_Source\\Bin\\" .. PersistentConfig.OpenShimInstaller.bundledRootName,
    }

    for _, candidate in ipairs(candidates) do
        if BzFileExists(candidate) then
            return candidate
        end
    end

    return nil
end

local function ConfirmBundledOpenShimCopy(sourcePath, destinationPath)
    if not BzFileExists(destinationPath) then
        return false
    end

    local sourceHash = GetBzFileHash(sourcePath)
    local destinationHash = GetBzFileHash(destinationPath)
    if sourceHash and destinationHash then
        return sourceHash == destinationHash
    end

    return true
end

local function ShowOpenShimInstallMissionOutcome(state)
    local missionTime = (GetTime and GetTime()) or 0.0
    if state == "installed" then
        if SucceedMission then
            SucceedMission(missionTime, "install.des")
            return
        end
        ShowFeedback(PersistentConfig.OpenShimInstaller.restartMessage, 1.0, 0.85, 0.2, 12.0, true)
        return
    end

    if state == "updated" or state == "staged" then
        ShowFeedback(PersistentConfig.OpenShimInstaller.updateMessage, 1.0, 0.85, 0.2, 12.0, true)
        return
    end

    if FailMission then
        FailMission(missionTime, "nocopy.des")
        return
    end

    ShowFeedback("OpenShim self-install failed.", 1.0, 0.35, 0.35, 12.0, true)
end

local function StageBundledOpenShimReplaceOnExit(sourcePath, destinationPath)
    if not (bzfile and type(bzfile.ReplaceFileOnExit) == "function") then
        return false, "bzfile.ReplaceFileOnExit unavailable"
    end

    local ok, scheduled, scheduleError = pcall(bzfile.ReplaceFileOnExit, sourcePath, destinationPath)
    if ok and scheduled then
        return true
    end

    local errorText = ok and tostring(scheduleError or "deferred replacement failed") or tostring(scheduled)
    return false, errorText
end

local function EnsureBundledOpenShimInstalled()
    if PersistentConfig.OpenShimInstallChecked then
        return
    end
    PersistentConfig.OpenShimInstallChecked = true

    if not (bzfile and type(bzfile.CopyFile) == "function") then
        print("PersistentConfig: bzfile.CopyFile unavailable; skipping OpenShim self-install.")
        return
    end

    local workingDirectory = getWorkingDirectory()
    local destinationPath = workingDirectory .. "\\winmm.dll"
    local sourcePath = GetBundledOpenShimSourcePath()
    if not sourcePath then
        print("PersistentConfig: No bundled OpenShim winmm.dll found; skipping self-install.")
        return
    end

    local destinationExists = BzFileExists(destinationPath)
    local shouldOverwrite = false
    local installState = destinationExists and "updated" or "installed"
    if destinationExists then
        local sourceHash = GetBzFileHash(sourcePath)
        local destinationHash = GetBzFileHash(destinationPath)
        if sourceHash and destinationHash and sourceHash == destinationHash then
            return
        end
        if not (sourceHash and destinationHash) then
            print("PersistentConfig: OpenShim hash comparison unavailable; attempting overwrite anyway.")
        end

        shouldOverwrite = true
    end

    local ok, copied, copyError = pcall(bzfile.CopyFile, sourcePath, destinationPath, shouldOverwrite)
    if ok and copied and ConfirmBundledOpenShimCopy(sourcePath, destinationPath) then
        print("PersistentConfig: Installed bundled OpenShim to " .. destinationPath)
        ShowOpenShimInstallMissionOutcome(installState)
        return
    end

    if shouldOverwrite then
        local staged, stageError = StageBundledOpenShimReplaceOnExit(sourcePath, destinationPath)
        if staged then
            print("PersistentConfig: Queued bundled OpenShim replacement for next game restart at " .. destinationPath)
            ShowOpenShimInstallMissionOutcome("staged")
            return
        end

        local immediateError = ok and tostring(copyError or "copy failed or could not be confirmed") or tostring(copied)
        print("PersistentConfig: Deferred OpenShim self-install also failed. Immediate error: " .. immediateError .. "; deferred error: " .. tostring(stageError))
    end

    local errorText = ok and tostring(copyError or "copy failed or could not be confirmed") or tostring(copied)
    print("PersistentConfig: OpenShim self-install failed: " .. errorText)
    ShowOpenShimInstallMissionOutcome("failed")
end

-- Logging Helper
local function Log(msg)
    if Print then
        Print(msg)
    else
        print(msg)
    end
end

PersistentConfig._BuildLuaTrace = function(err)
    local text = tostring(err)
    if debug and type(debug.traceback) == "function" then
        return debug.traceback(text, 2)
    end
    return text
end

PersistentConfig._DescribeHandleForLog = function(h)
    local parts = { "handle=" .. tostring(h) }

    if type(IsValid) == "function" then
        local ok, value = pcall(IsValid, h)
        parts[#parts + 1] = "valid=" .. tostring(ok and value or ("error:" .. tostring(value)))
    end

    if type(GetOdf) == "function" then
        local ok, value = pcall(GetOdf, h)
        if ok and value then
            parts[#parts + 1] = "odf=" .. tostring(value)
        end
    end

    if type(GetClassSig) == "function" then
        local ok, value = pcall(GetClassSig, h)
        if ok and value then
            parts[#parts + 1] = "class=" .. tostring(value)
        end
    end

    if type(GetTeamNum) == "function" then
        local ok, value = pcall(GetTeamNum, h)
        if ok and value ~= nil then
            parts[#parts + 1] = "team=" .. tostring(value)
        end
    end

    return table.concat(parts, " ")
end

PersistentConfig._InvokeWithTrace = function(label, fn, ...)
    if type(fn) ~= "function" then
        return nil
    end

    local args = { ... }
    local ok, result = xpcall(function()
        return fn((table.unpack or unpack)(args))
    end, PersistentConfig._BuildLuaTrace)

    if not ok then
        Log("[lua-trace] " .. label .. " failed: " .. tostring(result))
        error(result, 0)
    end

    return result
end

-- On-Screen Feedback Helper
ShowFeedback = function(msg, r, g, b, duration, bypass, target)
    -- Push to queue instead of displaying immediately
    table.insert(PersistentConfig.FeedbackQueue, {
        msg = msg,
        r = r or 0.8,
        g = g or 0.8,
        b = b or 1.0,
        duration = duration or 2.0,
        bypass = (bypass == nil) and true or bypass, -- Default to true for responsiveness
        target = target or "subtitle",
    })
    Log(msg)                                        -- Always log to console
end

local function WarnIfNativeFeaturesUnavailable()
    if InputState and InputState.NativeFeatureWarningShown then
        return
    end

    if not ((exu and exu.isStub) or (bzfile and bzfile.isStub)) then
        return
    end

    if InputState then
        InputState.NativeFeatureWarningShown = true
    end

    local message =
        "Unsupported runtime detected. Supported: Windows, or Linux via Steam/Proton. Native-only features are degraded and performance may be worse."

    if AddObjective then
        AddObjective("native_runtime_warning", "red", 15.0, message)
    end

    ShowFeedback(message, 1.0, 0.2, 0.2, 10.0, true)
end

local function PlayPdaSound(filename)
    if type(StartSound) ~= "function" or not filename or filename == "" then return end
    pcall(StartSound, filename, nil, 80, false, 100)
end

local function ClampIndex(value, minimum, maximum, fallback)
    local n = tonumber(value)
    if not n then return fallback end
    n = math.floor(n + 0.5)
    if n < minimum then return minimum end
    if n > maximum then return maximum end
    return n
end

local function ClampRange(value, minimum, maximum, fallback)
    local n = tonumber(value)
    if not n then return fallback end
    if n < minimum then return minimum end
    if n > maximum then return maximum end
    return n
end

local function CycleIndex(value, count, delta, fallback)
    local index = ClampIndex(value, 1, count, fallback or 1)
    local step = math.floor(tonumber(delta) or 0)
    return ((index - 1 + step) % count) + 1
end

local function GetPdaFontScale()
    return ClampRange(PersistentConfig.Settings.PdaFontScale, PersistentConfig.FontScale.pda.min,
        PersistentConfig.FontScale.pda.max, 1.0)
end

local function GetScriptSubtitles()
    local subtit = package.loaded["ScriptSubtitles"]
    if type(subtit) == "table" then
        return subtit
    end
    return nil
end

function PersistentConfig._GetPdaOverlaySpaceWidth(charHeight)
    local height = math.max(tonumber(charHeight) or 0, 1)
    return math.max(4, math.floor((height * 0.70) + 0.5))
end

local function GetPdaColorPreset()
    return PdaColorPresets[ClampIndex(PersistentConfig.Settings.PdaColorPreset, 1, #PdaColorPresets, 2)]
end

function PersistentConfig._GetTargetReticlePopupPresetIndex()
    if PersistentConfig.Settings.TargetReticlePopupMode == 3 then
        return 2
    end
    return 1
end

function PersistentConfig._GetTargetReticlePopupPreset()
    return PersistentConfig.TargetReticlePopupPresets[PersistentConfig._GetTargetReticlePopupPresetIndex()]
end

local function GetPdaPanelMaterialTargetColor(r, g, b)
    local preset = GetPdaColorPreset()
    return ClampUnitInterval(r, preset.r), ClampUnitInterval(g, preset.g), ClampUnitInterval(b, preset.b)
end

function PersistentConfig._GetPdaOverlayMaterialAlphaStep()
    local opacity = ClampUnitInterval(PersistentConfig.Settings.PdaOpacity, 1.0)
    return ClampRange(math.floor((opacity / 0.05) + 0.5), 0, 20, 20)
end

function PersistentConfig._GetPdaOverlayMaterialFamily(r, g, b)
    local targetR, targetG, targetB = GetPdaPanelMaterialTargetColor(r, g, b)
    local bestFamily = PdaPanelMaterialFamilies[2]
    local bestDistance = math.huge

    for _, family in ipairs(PdaPanelMaterialFamilies) do
        local dr = family.r - targetR
        local dg = family.g - targetG
        local db = family.b - targetB
        local distance = (dr * dr) + (dg * dg) + (db * db)
        if distance < bestDistance then
            bestDistance = distance
            bestFamily = family
        end
    end

    return bestFamily
end

function PersistentConfig._GetPdaOverlayPanelMaterial(section, r, g, b)
    local family = PersistentConfig._GetPdaOverlayMaterialFamily(r, g, b)
    local alphaStep = PersistentConfig._GetPdaOverlayMaterialAlphaStep()
    return string.format("CRPda%s_%s_A%02d", tostring(section or "Backdrop"), family.key, alphaStep)
end

local function GetScrapPilotHudLayout()
    return ScrapPilotHudLayouts[ClampIndex(PersistentConfig.Settings.ScrapPilotHudLayout, 1, #ScrapPilotHudLayouts, 2)]
end

local function GetSubtitleFontScale()
    return ClampRange(PersistentConfig.Settings.SubtitleFontScale, PersistentConfig.FontScale.subtitle.min,
        PersistentConfig.FontScale.subtitle.max, 1.0)
end

function PersistentConfig._CaptureUnitVoBaseline()
    if PersistentConfig.UnitVoBaseline then
        return PersistentConfig.UnitVoBaseline
    end

    local fallback = PersistentConfig.UnitVoUi.fallbackBaseline or {
        throttleMs = 0,
        queueDepthLimit = 2,
        queueStaleMs = 2000,
    }
    local baseline = {
        throttleMs = tonumber(fallback.throttleMs) or 0,
        queueDepthLimit = tonumber(fallback.queueDepthLimit) or 2,
        queueStaleMs = tonumber(fallback.queueStaleMs) or 2000,
    }

    if exu then
        local okThrottle, throttle = pcall(exu.GetUnitVoThrottle)
        local okDepth, depth = pcall(exu.GetUnitVoQueueDepthLimit)
        local okStale, staleMs = pcall(exu.GetUnitVoQueueStaleMs)

        if okThrottle and tonumber(throttle) ~= nil then
            baseline.throttleMs = math.max(0, math.floor(tonumber(throttle) + 0.5))
        end
        if okDepth and tonumber(depth) ~= nil then
            baseline.queueDepthLimit = math.max(0, math.floor(tonumber(depth) + 0.5))
        end
        if okStale and tonumber(staleMs) ~= nil then
            baseline.queueStaleMs = math.max(0, math.floor(tonumber(staleMs) + 0.5))
        end
    end

    PersistentConfig.UnitVoBaseline = baseline
    return baseline
end

function PersistentConfig._GetUnitVerbosityPreset()
    return PersistentConfig.UnitVerbosityPresets[ClampIndex(PersistentConfig.Settings.UnitVerbosity, 1,
        #PersistentConfig.UnitVerbosityPresets, 1)]
end

function PersistentConfig._GetLightingModePreset()
    return PersistentConfig.LightingModePresets[ClampIndex(
        PersistentConfig.Settings.LightingMode,
        1,
        #PersistentConfig.LightingModePresets,
        PersistentConfig.DefaultSettings.LightingMode or 1
    )]
end

function PersistentConfig._SetLightingModeIndex(value)
    local index = ClampIndex(value, 1, #PersistentConfig.LightingModePresets,
        PersistentConfig.DefaultSettings.LightingMode or 1)
    local preset = PersistentConfig.LightingModePresets[index] or PersistentConfig.LightingModePresets[1]
    PersistentConfig.Settings.LightingMode = index
    PersistentConfig.Settings.RetroLighting = not not (preset and preset.retro)
    return index, preset
end

function PersistentConfig._ResolveUnitVoProfileForCurrentTeam()
    local baseline = PersistentConfig._CaptureUnitVoBaseline()
    local preset = PersistentConfig._GetUnitVerbosityPreset()
    if not preset then
        return baseline
    end

    if GetPlayerTeamNum() ~= (PersistentConfig.UnitVoUi.applyTeam or 1) or preset.useBaseline then
        return {
            name = preset.name or "NORMAL",
            muted = false,
            throttleMs = baseline.throttleMs,
            queueDepthLimit = baseline.queueDepthLimit,
            queueStaleMs = baseline.queueStaleMs,
        }
    end

    return {
        name = preset.name or "QUIET",
        muted = not not preset.muted,
        throttleMs = math.max(0, math.floor(tonumber(preset.throttleMs) or baseline.throttleMs)),
        queueDepthLimit = math.max(0, math.floor(tonumber(preset.queueDepthLimit) or baseline.queueDepthLimit)),
        queueStaleMs = math.max(0, math.floor(tonumber(preset.queueStaleMs) or baseline.queueStaleMs)),
    }
end

function PersistentConfig._ApplyUnitVoSettings()
    if not exu then
        return false
    end
    if type(exu.SetUnitVoThrottle) ~= "function" or
        type(exu.SetUnitVoQueueDepthLimit) ~= "function" or
        type(exu.SetUnitVoQueueStaleMs) ~= "function" then
        return false
    end

    local profile = PersistentConfig._ResolveUnitVoProfileForCurrentTeam()
    local okMuted = true
    if type(exu.SetUnitVoMuted) == "function" then
        okMuted = pcall(exu.SetUnitVoMuted, not not profile.muted)
    end
    local okThrottle = pcall(exu.SetUnitVoThrottle, profile.throttleMs)
    local okDepth = pcall(exu.SetUnitVoQueueDepthLimit, profile.queueDepthLimit)
    local okStale = pcall(exu.SetUnitVoQueueStaleMs, profile.queueStaleMs)

    return okMuted and okThrottle and okDepth and okStale
end

function PersistentConfig._GetAutoSaveSlot()
    return ClampIndex(PersistentConfig.Settings.AutoSaveSlot, PersistentConfig.AutoSaveUi.slotMin,
        PersistentConfig.AutoSaveUi.slotMax, PersistentConfig.DefaultSettings.AutoSaveSlot)
end

function PersistentConfig._GetAutoSaveIntervalOptionIndex(value)
    local requested = math.floor((tonumber(value) or PersistentConfig.DefaultSettings.AutoSaveInterval) + 0.5)
    if requested == 200 then
        return 2
    end

    local bestIndex = 1
    local bestDiff = math.huge
    for index, option in ipairs(PersistentConfig.AutoSaveUi.intervalOptions) do
        local diff = math.abs(requested - option.seconds)
        if diff < bestDiff then
            bestIndex = index
            bestDiff = diff
        end
    end
    return bestIndex
end

function PersistentConfig._GetAutoSaveIntervalOption()
    local index = PersistentConfig._GetAutoSaveIntervalOptionIndex(PersistentConfig.Settings.AutoSaveInterval)
    return PersistentConfig.AutoSaveUi.intervalOptions[index], index
end

function PersistentConfig._GetAutoSavePath()
    return PersistentConfig.AutoSaveUi.filePath or "Save\\auto.sav"
end

function PersistentConfig._GetAutoSaveFileLabel()
    return PersistentConfig.AutoSaveUi.fileLabel or "AUTO.SAV"
end

function PersistentConfig._ClearAutoSaveEnablePrompt()
    if not InputState then
        return false
    end

    local hadPrompt = InputState.autoSaveEnableArmed or InputState.autoSaveConfirmSlot
    InputState.autoSaveEnableArmed = false
    InputState.autoSaveConfirmSlot = nil
    return not not hadPrompt
end

function PersistentConfig._GetAutoSaveStatusValue()
    return PersistentConfig.Settings.AutoSaveEnabled and "On" or "Off"
end

function PersistentConfig._GetAutoSaveEnterHint()
    return "Enter Toggle"
end

function PersistentConfig._BuildAutoSaveWarningLines(selectedEntry)
    return nil
end

function ClampUnitInterval(value, fallback)
    local n = tonumber(value)
    if not n then return fallback end
    if n < 0.0 then return 0.0 end
    if n > 1.0 then return 1.0 end
    return n
end

local function AdjustOpacity(value, delta)
    local step = 0.05
    local current = ClampUnitInterval(value, 1.0)
    local direction = (delta or 0) < 0 and -1 or 1
    return ClampUnitInterval(math.floor((current / step) + 0.5 + direction) * step, current)
end

local function FormatOpacity(value)
    return string.format("%d%%", math.floor((ClampUnitInterval(value, 1.0) * 100.0) + 0.5))
end

local function AdjustScale(value, delta, minimum, maximum, step)
    local stepValue = step or 0.05
    local current = ClampRange(value, minimum, maximum, 1.0)
    local snapped = math.floor((current / stepValue) + 0.5) * stepValue
    if (delta or 0) == 0 then
        return ClampRange(snapped, minimum, maximum, current)
    end
    local direction = (delta or 0) < 0 and -1 or 1
    return ClampRange(snapped + (direction * stepValue), minimum, maximum, snapped)
end

local function FormatScale(value, minimum, maximum)
    local n = ClampRange(value, minimum, maximum, 1.0)
    return string.format("%d%%", math.floor((n * 100.0) + 0.5))
end

local function LegacyPresetFromScale(scale)
    local target = ClampRange(scale, PersistentConfig.FontScale.subtitle.min, PersistentConfig.FontScale.subtitle.max, 1.0)
    local bestIndex = 2
    local bestDiff = math.huge
    for idx, value in pairs(LEGACY_TEXT_PRESET_SCALES) do
        local diff = math.abs(target - value)
        if diff < bestDiff then
            bestDiff = diff
            bestIndex = idx
        end
    end
    return bestIndex
end

local function BuildPdaHeader(activePage)
    local labels = {
        [PdaPages.STATS] = "Stats",
        [PdaPages.TARGET] = "Target",
        [PdaPages.SETTINGS] = "Settings",
        [PdaPages.PRESETS] = "Presets",
        [PdaPages.QUEUE] = "Queue",
        [PdaPages.COMMAND] = "Command",
    }
    local parts = {}
    for page = 1, PdaPages.COUNT do
        local label = labels[page]
        if page == activePage then
            table.insert(parts, "[" .. label .. "]")
        else
            table.insert(parts, label)
        end
    end
    return "**Battlezone PDA**\n" .. table.concat(parts, " ")
end

local function FormatHotkeyValue(value, key)
    if not key or key == "" then
        return value
    end
    return string.format("%s (%s)", value, key)
end

local function AppendPdaFooter(lines, line1, line2, line3)
    table.insert(lines, "")
    table.insert(lines, line1 or "--------------------------------")
    table.insert(lines, line2 or "[ / ] SWITCH PAGE")
    table.insert(lines, line3 or "Y Toggle PDA")
end

local function AppendPdaNavHints(lines)
    AppendPdaFooter(lines, "--------------------------------", "[ / ] Switch Page", "Y Toggle PDA")
end

function PersistentConfig._GetUiResolutionMetrics()
    local width, height = 1920, 1080
    local uiScale = 2

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

    return width, height, uiScale
end

local function GetPdaLayoutMetrics(page)
    local width, height, uiScale = PersistentConfig._GetUiResolutionMetrics()
    local activePage = ClampIndex(page or (InputState and InputState.pdaPage) or PdaPages.STATS, 1, PdaPages.COUNT,
        PdaPages.STATS)
    local fontScale = GetPdaFontScale()

    local aspect = width / math.max(height, 1)
    local aspectScale = math.min(1.35, math.max(0.80, (16.0 / 9.0) / aspect))
    local uiScaleFactor = math.min(1.45, math.max(0.85, (uiScale / 2.0) ^ 0.45))
    local textScale = math.min(0.60, math.max(0.22, 0.30 * aspectScale * uiScaleFactor * fontScale))
    local wrapWidth = math.min(0.70, math.max(0.24,
        0.31 * math.min(1.2, math.max(0.9, 1.0 / aspectScale)) * uiScaleFactor * fontScale))
    local panelX = math.min(math.max(0.0, 1.0 - wrapWidth), math.max(0.0, 0.01))

    return {
        textScale = textScale,
        wrapWidth = wrapWidth,
        panelX = panelX,
        paddingX = 6.0 * fontScale,
        paddingY = 5.0 * fontScale,
        opacity = ClampUnitInterval(PersistentConfig.Settings.PdaOpacity, 1.0),
        feedbackTextScale = math.min(0.46, math.max(0.20, textScale * 0.86)),
        feedbackY = 0.90,
    }
end

function PersistentConfig._GetAutoSaveOverlayLayout(pixelMode)
    local width, height, uiScale = PersistentConfig._GetUiResolutionMetrics()
    local fontScale = GetSubtitleFontScale()
    local aspect = width / math.max(height, 1)
    local aspectScale = math.min(1.35, math.max(0.82, (16.0 / 9.0) / aspect))
    local uiScaleFactor = math.min(1.30, math.max(0.90, (uiScale / 2.0) ^ 0.32))
    local compactFontScale = math.min(1.20, math.max(0.92, fontScale ^ 0.45))
    if pixelMode then
        local horizontalMargin = math.max(18, math.floor(width * 0.015))
        local verticalMargin = math.max(18, math.floor(height * 0.028))
        local wrapWidth = math.max(220, math.floor(width * 0.16))
        local charHeight = math.max(18, math.floor(18 * uiScaleFactor * compactFontScale))
        local panelHeight = math.max(42, math.floor(charHeight * 2.1))
        return {
            panelX = horizontalMargin,
            panelY = math.max(12, height - panelHeight - verticalMargin),
            wrapWidth = wrapWidth,
            panelHeight = panelHeight,
            charHeight = charHeight,
            textOffsetX = math.max(8, math.floor(charHeight * 0.45)),
            textOffsetY = math.max(5, math.floor(charHeight * 0.24)),
        }
    end

    local wrapWidth = math.min(0.24, math.max(0.14,
        0.16 * math.min(1.18, math.max(0.90, 1.0 / aspectScale)) * compactFontScale))
    local charHeight = math.min(0.026, math.max(0.016, 0.018 * aspectScale * uiScaleFactor * compactFontScale))
    local panelHeight = math.min(0.060, math.max(0.036, charHeight * 2.1))

    return {
        panelX = 0.018,
        panelY = math.max(0.90, 0.97 - panelHeight),
        wrapWidth = wrapWidth,
        panelHeight = panelHeight,
        charHeight = charHeight,
        textOffsetX = 0.006,
        textOffsetY = 0.003,
    }
end

PersistentConfig.ExperimentalOverlayIds = {
    overlay = "cr_experimental_autosave_overlay",
    root = "cr_experimental_autosave_overlay_root",
    text = "cr_experimental_autosave_overlay_text",
}
PersistentConfig.ExperimentalOverlayFont = "CRBZoneOverlayFont"
PersistentConfig.ExperimentalOverlayUseCustomFont = true

function PersistentConfig._HideExperimentalOverlay()
    local ids = PersistentConfig.ExperimentalOverlayIds
    PersistentConfig.ExperimentalOverlayVisible = false
    PersistentConfig.ExperimentalOverlayExpireAt = 0.0
    if exu and exu.HideOverlay then
        pcall(exu.HideOverlay, ids.overlay)
    end
end

function PersistentConfig._DestroyExperimentalOverlay()
    local ids = PersistentConfig.ExperimentalOverlayIds
    PersistentConfig.ExperimentalOverlayReady = false
    PersistentConfig.ExperimentalOverlayVisible = false
    PersistentConfig.ExperimentalOverlayExpireAt = 0.0

    if not exu then
        return
    end

    PersistentConfig._HideExperimentalOverlay()
    if exu.RemoveOverlayElementChild then
        pcall(exu.RemoveOverlayElementChild, ids.root, ids.text)
    end
    if exu.RemoveOverlay2D then
        pcall(exu.RemoveOverlay2D, ids.overlay, ids.root)
    end
    if exu.DestroyOverlayElement then
        pcall(exu.DestroyOverlayElement, ids.text)
        pcall(exu.DestroyOverlayElement, ids.root)
    end
    if exu.DestroyOverlay then
        pcall(exu.DestroyOverlay, ids.overlay)
    end
end

function PersistentConfig._TryCreateExperimentalOverlay()
    local ids = PersistentConfig.ExperimentalOverlayIds
    if PersistentConfig.ExperimentalOverlayReady then
        return true
    end

    if PersistentConfig.ExperimentalOverlayFailed then
        return false
    end

    if not exu or not exu.CreateOverlay or not exu.CreateOverlayElement or not exu.AddOverlay2D
        or not exu.AddOverlayElementChild or not exu.SetOverlayZOrder or not exu.SetOverlayMetricsMode
        or not exu.SetOverlayPosition or not exu.SetOverlayDimensions or not exu.SetOverlayTextFont
        or not exu.SetOverlayTextCharHeight or not exu.SetOverlayColor or not exu.SetOverlayCaption
        or not exu.ShowOverlayElement or not exu.ShowOverlay or not exu.HideOverlay then
        PersistentConfig.ExperimentalOverlayFailed = true
        return false
    end

    PersistentConfig._DestroyExperimentalOverlay()

    local metricsMode = (exu.OVERLAY_METRICS and exu.OVERLAY_METRICS.RELATIVE) or 0
    if PersistentConfig.ExperimentalOverlayForcePixelMetrics and exu.OVERLAY_METRICS and exu.OVERLAY_METRICS.PIXELS then
        metricsMode = exu.OVERLAY_METRICS.PIXELS
    end
    local layout = PersistentConfig._GetAutoSaveOverlayLayout(
        metricsMode == (exu.OVERLAY_METRICS and exu.OVERLAY_METRICS.PIXELS))
    local ok = true

    local function SafeCall(fn, ...)
        if not ok or type(fn) ~= "function" then
            return nil
        end

        local success, result = pcall(fn, ...)
        if not success then
            ok = false
            Log("PersistentConfig: Experimental overlay call failed: " .. tostring(result))
            return nil
        end
        return result
    end

    if SafeCall(exu.CreateOverlay, ids.overlay) == false then
        ok = false
        Log("PersistentConfig: Experimental overlay creation returned false for overlay " .. tostring(ids.overlay))
    end
    if SafeCall(exu.CreateOverlayElement, "Panel", ids.root) == false then
        ok = false
        Log("PersistentConfig: Experimental overlay creation returned false for root " .. tostring(ids.root))
    end
    if SafeCall(exu.CreateOverlayElement, "TextArea", ids.text) == false then
        ok = false
        Log("PersistentConfig: Experimental overlay creation returned false for text " .. tostring(ids.text))
    end
    if exu.HasOverlayElement then
        if SafeCall(exu.HasOverlayElement, ids.root) ~= true or SafeCall(exu.HasOverlayElement, ids.text) ~= true then
            ok = false
            Log("PersistentConfig: Experimental overlay elements failed to materialize after creation.")
        end
    end
    SafeCall(exu.AddOverlay2D, ids.overlay, ids.root)
    SafeCall(exu.AddOverlayElementChild, ids.root, ids.text)
    local overlayZOrder = ClampRange(PersistentConfig.ExperimentalOverlayDebugZOrder, 0, 650, 640)
    SafeCall(exu.SetOverlayZOrder, ids.overlay, overlayZOrder)

    SafeCall(exu.SetOverlayMetricsMode, ids.root, metricsMode)
    SafeCall(exu.SetOverlayPosition, ids.root, layout.panelX, layout.panelY)
    SafeCall(exu.SetOverlayDimensions, ids.root, layout.wrapWidth, layout.panelHeight)
    if PersistentConfig.ExperimentalOverlayDebugBox and exu.SetOverlayMaterial then
        SafeCall(exu.SetOverlayMaterial, ids.root, "BaseWhiteNoLighting")
    end
    if PersistentConfig.ExperimentalOverlayDebugBox then
        SafeCall(exu.SetOverlayColor, ids.root, 0.85, 0.10, 0.10, 0.88)
    else
        SafeCall(exu.SetOverlayColor, ids.root, 0.0, 0.0, 0.0, 0.55)
    end

    SafeCall(exu.SetOverlayMetricsMode, ids.text, metricsMode)
    SafeCall(exu.SetOverlayPosition, ids.text, layout.textOffsetX or 0.010, layout.textOffsetY or 0.006)
    SafeCall(exu.SetOverlayDimensions, ids.text, layout.wrapWidth, layout.panelHeight)
    if PersistentConfig.ExperimentalOverlayUseCustomFont then
        if SafeCall(exu.SetOverlayTextFont, ids.text, PersistentConfig.ExperimentalOverlayFont) ~= true then
            ok = false
            Log("PersistentConfig: Experimental overlay font bind failed for " .. tostring(PersistentConfig.ExperimentalOverlayFont))
        end
    end
    SafeCall(exu.SetOverlayTextCharHeight, ids.text, layout.charHeight)
    if exu.SetOverlayTextColor then
        SafeCall(exu.SetOverlayTextColor, ids.text, 0.82, 1.0, 0.82, 1.0)
    else
        SafeCall(exu.SetOverlayColor, ids.text, 0.82, 1.0, 0.82, 1.0)
    end
    SafeCall(exu.SetOverlayCaption, ids.text, "")
    SafeCall(exu.ShowOverlayElement, ids.root)
    SafeCall(exu.ShowOverlayElement, ids.text)
    SafeCall(exu.HideOverlay, ids.overlay)

    if ok then
        PersistentConfig.ExperimentalOverlayReady = true
        PersistentConfig.ExperimentalOverlayFailed = false
        Log("PersistentConfig: Experimental EXU overlay initialized for notifications.")
    else
        PersistentConfig.ExperimentalOverlayFailed = true
        PersistentConfig._DestroyExperimentalOverlay()
    end

    return ok
end

function PersistentConfig._ShowAutoSaveOverlayNow(msg, duration, r, g, b)
    local ids = PersistentConfig.ExperimentalOverlayIds
    if not msg or msg == "" then
        return false
    end

    if not PersistentConfig.ExperimentalOverlayUseCustomFont then
        Log("PersistentConfig: Autosave overlay skipped because custom font rendering is disabled.")
        return false
    end

    if not PersistentConfig._TryCreateExperimentalOverlay() then
        return false
    end

    local metricsMode = (exu.OVERLAY_METRICS and exu.OVERLAY_METRICS.RELATIVE) or 0
    if PersistentConfig.ExperimentalOverlayForcePixelMetrics and exu.OVERLAY_METRICS and exu.OVERLAY_METRICS.PIXELS then
        metricsMode = exu.OVERLAY_METRICS.PIXELS
    end
    local layout = PersistentConfig._GetAutoSaveOverlayLayout(
        metricsMode == (exu.OVERLAY_METRICS and exu.OVERLAY_METRICS.PIXELS))
    local ok = true

    local function SafeCall(fn, ...)
        if not ok or type(fn) ~= "function" then
            return nil
        end

        local success, result = pcall(fn, ...)
        if not success then
            ok = false
            Log("PersistentConfig: Autosave overlay call failed: " .. tostring(result))
            return nil
        end
        return result
    end

    SafeCall(exu.SetOverlayPosition, ids.root, layout.panelX, layout.panelY)
    SafeCall(exu.SetOverlayDimensions, ids.root, layout.wrapWidth, layout.panelHeight)
    if PersistentConfig.ExperimentalOverlayDebugBox and exu.SetOverlayMaterial then
        SafeCall(exu.SetOverlayMaterial, ids.root, "BaseWhiteNoLighting")
    end
    if PersistentConfig.ExperimentalOverlayDebugBox then
        SafeCall(exu.SetOverlayColor, ids.root, 0.85, 0.10, 0.10, 0.88)
    else
        SafeCall(exu.SetOverlayColor, ids.root, 0.0, 0.0, 0.0, 0.55)
    end
    SafeCall(exu.SetOverlayDimensions, ids.text, layout.wrapWidth, layout.panelHeight)
    SafeCall(exu.SetOverlayPosition, ids.text, layout.textOffsetX or 0.010, layout.textOffsetY or 0.006)
    SafeCall(exu.SetOverlayTextCharHeight, ids.text, layout.charHeight)
    local textR, textG, textB = r or 0.82, g or 1.0, b or 0.82
    if PersistentConfig.ExperimentalOverlayDebugBox then
        textR, textG, textB = 0.0, 0.0, 0.0
    end
    if exu.SetOverlayTextColor then
        SafeCall(exu.SetOverlayTextColor, ids.text, textR, textG, textB, 1.0)
    else
        SafeCall(exu.SetOverlayColor, ids.text, textR, textG, textB, 1.0)
    end
    SafeCall(exu.SetOverlayCaption, ids.text, msg)
    SafeCall(exu.ShowOverlayElement, ids.root)
    SafeCall(exu.ShowOverlayElement, ids.text)
    SafeCall(exu.ShowOverlay, ids.overlay)

    if not ok then
        PersistentConfig.ExperimentalOverlayReady = false
        PersistentConfig.ExperimentalOverlayFailed = true
        PersistentConfig._DestroyExperimentalOverlay()
        return false
    end

    PersistentConfig.ExperimentalOverlayVisible = true
    PersistentConfig.ExperimentalOverlayExpireAt = GetTime() + math.max(tonumber(duration) or 3.0, 0.1)
    Log(string.format("PersistentConfig: Autosave overlay shown text=%q font=%s panelMaterial=BaseWhiteNoLighting pos=(%.3f,%.3f) size=(%.3f,%.3f) debugBox=%s",
        msg, PersistentConfig.ExperimentalOverlayUseCustomFont and tostring(PersistentConfig.ExperimentalOverlayFont) or "disabled",
        layout.panelX, layout.panelY, layout.wrapWidth, layout.panelHeight,
        tostring(PersistentConfig.ExperimentalOverlayDebugBox)))
    return true
end

function PersistentConfig.TryShowAutoSaveOverlayInfo(msg, duration, r, g, b)
    if not msg or msg == "" then
        return false
    end

    if not PersistentConfig.ExperimentalOverlayUseCustomFont then
        return false
    end

    local now = GetTime()
    if now < 0.75 then
        PersistentConfig.ExperimentalOverlayPending = nil
        Log("PersistentConfig: Autosave overlay deferred to mission overlay fallback because startup is too early.")
        return false
    end

    return PersistentConfig._ShowAutoSaveOverlayNow(msg, duration, r, g, b)
end

function PersistentConfig._NormalizeOverlayText(text)
    text = tostring(text or "")
    text = text:gsub("\r\n", "\n")
    text = text:gsub("\r", "\n")
    return text
end

function PersistentConfig._CountOverlayTextLines(text)
    local normalized = PersistentConfig._NormalizeOverlayText(text)
    local count = 0
    for _ in (normalized .. "\n"):gmatch("(.-)\n") do
        count = count + 1
    end
    return math.max(count, 1)
end

function PersistentConfig._GetOverlayLongestLineLength(text)
    local longest = 0
    for line in (PersistentConfig._NormalizeOverlayText(text) .. "\n"):gmatch("(.-)\n") do
        longest = math.max(longest, #line)
    end
    return longest
end

function PersistentConfig._SplitOverlayToken(token, maxCharsPerLine)
    local parts = {}
    token = tostring(token or "")
    maxCharsPerLine = math.max(tonumber(maxCharsPerLine) or 12, 4)

    while #token > maxCharsPerLine do
        local take = math.max(maxCharsPerLine - 1, 1)
        parts[#parts + 1] = token:sub(1, take) .. "-"
        token = token:sub(take + 1)
    end

    if token ~= "" then
        parts[#parts + 1] = token
    end
    if #parts == 0 then
        parts[1] = ""
    end
    return parts
end

function PersistentConfig._WrapOverlayText(text, maxCharsPerLine)
    text = PersistentConfig._NormalizeOverlayText(text)
    maxCharsPerLine = math.max(tonumber(maxCharsPerLine) or 32, 8)

    local wrappedLines = {}
    for paragraph in (text .. "\n"):gmatch("(.-)\n") do
        if paragraph == "" then
            wrappedLines[#wrappedLines + 1] = ""
        else
            local current = ""
            for word in paragraph:gmatch("%S+") do
                local pieces = PersistentConfig._SplitOverlayToken(word, maxCharsPerLine)
                for _, piece in ipairs(pieces) do
                    if current == "" then
                        current = piece
                    elseif (#current + 1 + #piece) <= maxCharsPerLine then
                        current = current .. " " .. piece
                    else
                        wrappedLines[#wrappedLines + 1] = current
                        current = piece
                    end
                end
            end
            if current ~= "" then
                wrappedLines[#wrappedLines + 1] = current
            end
        end
    end

    return table.concat(wrappedLines, "\n")
end

function PersistentConfig._EstimateOverlayCharsPerLine(widthPixels, charHeightPixels, widthFactor, horizontalPadding)
    widthPixels = math.max(tonumber(widthPixels) or 0, 16)
    charHeightPixels = math.max(tonumber(charHeightPixels) or 0, 1)
    widthFactor = math.max(tonumber(widthFactor) or 0.82, 0.55)
    horizontalPadding = math.max(tonumber(horizontalPadding) or 0, 0)

    local usableWidth = math.max(widthPixels - (horizontalPadding * 2), charHeightPixels * 4)
    return math.max(8, math.floor(usableWidth / (charHeightPixels * widthFactor)))
end

function PersistentConfig._EstimateOverlayTextPixelWidth(text, charHeightPixels, widthFactor, horizontalPadding)
    local longestLine = PersistentConfig._GetOverlayLongestLineLength(text)
    if longestLine <= 0 then
        return 0
    end

    charHeightPixels = math.max(tonumber(charHeightPixels) or 0, 1)
    widthFactor = math.max(tonumber(widthFactor) or 0.82, 0.55)
    horizontalPadding = math.max(tonumber(horizontalPadding) or 0, 0)

    local textWidth = math.floor((longestLine * charHeightPixels * widthFactor) + 10 + 0.5)
    return math.max(charHeightPixels * 4, textWidth + (horizontalPadding * 2))
end

function PersistentConfig._WrapOverlayTextToPixels(text, widthPixels, charHeightPixels, widthFactor, horizontalPadding)
    local maxCharsPerLine = PersistentConfig._EstimateOverlayCharsPerLine(widthPixels, charHeightPixels, widthFactor,
        horizontalPadding)
    return PersistentConfig._WrapOverlayText(text, maxCharsPerLine)
end

function PersistentConfig._GetOverlayTextBlockHeight(charHeightPixels, lineCount, lineSpacing)
    charHeightPixels = math.max(tonumber(charHeightPixels) or 0, 1)
    lineCount = math.max(tonumber(lineCount) or 0, 1)
    lineSpacing = math.max(tonumber(lineSpacing) or 1.10, 1.0)
    return math.max(charHeightPixels + 4, math.floor(charHeightPixels * lineSpacing * lineCount + 6))
end

function PersistentConfig._CanUsePdaOverlay()
    if PersistentConfig.PdaOverlay.failed then
        return false
    end

    return exu and exu.CreateOverlay and exu.DestroyOverlay and exu.ShowOverlay and exu.HideOverlay
        and exu.CreateOverlayElement and exu.DestroyOverlayElement and exu.AddOverlay2D and exu.RemoveOverlay2D
        and exu.AddOverlayElementChild and exu.RemoveOverlayElementChild and exu.SetOverlayZOrder
        and exu.SetOverlayMetricsMode and exu.SetOverlayPosition and exu.SetOverlayDimensions
        and exu.SetOverlayColor and exu.SetOverlayCaption and exu.SetOverlayMaterial
        and exu.SetOverlayTextCharHeight and exu.SetOverlayTextFont and exu.ShowOverlayElement
        and exu.HideOverlayElement and exu.SetOverlayParameter and exu.OVERLAY_METRICS
        and exu.OVERLAY_METRICS.PIXELS
end

function PersistentConfig._GetPdaOverlayMetricsMode()
    if not (exu and exu.OVERLAY_METRICS) then
        return nil
    end
    return exu.OVERLAY_METRICS.PIXELS
end

function PersistentConfig._SplitPdaOverlaySections(rawText)
    local lines = {}
    for line in (PersistentConfig._NormalizeOverlayText(rawText) .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end

    local title = lines[1] or "BATTLEZONE PDA"
    title = title:gsub("^%*%*(.-)%*%*$", "%1")
    local tabs = lines[2] or ""
    local footer = ""
    local bodyStart = 3
    local bodyEnd = #lines

    if #lines >= 6 and lines[#lines - 3] == "" then
        footer = table.concat({ lines[#lines - 2] or "", lines[#lines - 1] or "", lines[#lines] or "" }, "\n")
        bodyEnd = #lines - 4
    end

    if bodyEnd < bodyStart then
        bodyEnd = bodyStart - 1
    end

    local bodyLines = {}
    for index = bodyStart, bodyEnd do
        bodyLines[#bodyLines + 1] = lines[index]
    end

    return {
        title = title,
        tabs = tabs,
        body = table.concat(bodyLines, "\n"),
        footer = footer,
    }
end

function PersistentConfig._GetPdaOverlayColorSet(r, g, b)
    local preset = GetPdaColorPreset()
    local baseR = ClampUnitInterval(r, preset.r)
    local baseG = ClampUnitInterval(g, preset.g)
    local baseB = ClampUnitInterval(b, preset.b)
    local opacity = ClampUnitInterval(PersistentConfig.Settings.PdaOpacity, 1.0)

    local backgroundAlpha = math.min(0.82, 0.22 + (opacity * 0.38))
    local headerAlpha = math.min(0.76, 0.20 + (opacity * 0.34))
    local borderAlpha = math.min(1.0, 0.68 + (opacity * 0.28))
    local textAlpha = math.min(1.0, 0.92 + (opacity * 0.08))

    return {
        backdrop = {
            r = math.min(0.14, 0.012 + (baseR * 0.05)),
            g = math.min(0.14, 0.012 + (baseG * 0.05)),
            b = math.min(0.14, 0.012 + (baseB * 0.05)),
            a = backgroundAlpha,
        },
        header = {
            r = math.min(0.18, 0.018 + (baseR * 0.08)),
            g = math.min(0.18, 0.018 + (baseG * 0.08)),
            b = math.min(0.18, 0.018 + (baseB * 0.08)),
            a = headerAlpha,
        },
        border = {
            r = math.min(1.0, 0.30 + (baseR * 0.85)),
            g = math.min(1.0, 0.30 + (baseG * 0.85)),
            b = math.min(1.0, 0.30 + (baseB * 0.85)),
            a = borderAlpha,
        },
        text = {
            r = math.min(1.0, 0.10 + (baseR * 0.92)),
            g = math.min(1.0, 0.10 + (baseG * 0.92)),
            b = math.min(1.0, 0.10 + (baseB * 0.92)),
            a = textAlpha,
        },
        title = {
            r = math.min(1.0, 0.14 + (baseR * 0.94)),
            g = math.min(1.0, 0.14 + (baseG * 0.94)),
            b = math.min(1.0, 0.14 + (baseB * 0.94)),
            a = 1.0,
        },
        footer = {
            r = math.min(1.0, 0.08 + (baseR * 0.88)),
            g = math.min(1.0, 0.08 + (baseG * 0.88)),
            b = math.min(1.0, 0.08 + (baseB * 0.88)),
            a = textAlpha,
        },
    }
end

function PersistentConfig._GetPdaOverlayPixelLayout(kind, rawText, page)
    local screenW, screenH, uiScale = PersistentConfig._GetUiResolutionMetrics()
    local layout = GetPdaLayoutMetrics(page)
    local isFeedback = (kind == "feedback")
    local alignmentY = isFeedback and 1.0 or 0.5
    local anchorY = isFeedback and layout.feedbackY or 0.50
    local marginX = math.max(18, math.floor(screenW * 0.010))
    local marginY = math.max(16, math.floor(screenH * 0.014))
    local screenScale = math.min(1.40, math.max(0.85, screenH / 1080.0))
    local uiScaleFactor = math.min(1.30, math.max(0.90, (uiScale / 2.0) ^ 0.25))
    local pdaScale = GetPdaFontScale()

    if isFeedback then
        local maxTextWidth = ClampRange(math.floor(screenW * math.min(0.34, layout.wrapWidth * 0.95)), 260,
            math.floor(screenW * 0.42), 420)
        local charHeight = ClampRange(math.floor((12.0 * pdaScale * uiScaleFactor * screenScale) + 0.5), 14, 24, 16)
        local paddingX = math.max(14, math.floor(charHeight * 0.70))
        local paddingY = math.max(10, math.floor(charHeight * 0.48))
        local borderSize = math.max(2, math.floor(charHeight * 0.12))
        local wrappedText = PersistentConfig._WrapOverlayTextToPixels(rawText, maxTextWidth, charHeight, 0.72, 0)
        local textHeight = PersistentConfig._GetOverlayTextBlockHeight(charHeight,
            PersistentConfig._CountOverlayTextLines(wrappedText), 1.08)
        local longestLine = PersistentConfig._GetOverlayLongestLineLength(wrappedText)
        local estimatedTextWidth = math.min(maxTextWidth,
            math.max(charHeight * 10, math.floor((longestLine * charHeight * 0.72) + 10)))
        local panelWidth = estimatedTextWidth + (paddingX * 2) + (borderSize * 2)
        local panelHeight = textHeight + (paddingY * 2) + (borderSize * 2)
        local panelX = math.max(marginX, math.floor(screenW * layout.panelX))
        local panelY = math.floor((screenH * anchorY) - (panelHeight * alignmentY))
        panelY = ClampRange(panelY, marginY, screenH - panelHeight - marginY, marginY)
        panelX = ClampRange(panelX, marginX, screenW - panelWidth - marginX, marginX)

        return {
            panelX = panelX,
            panelY = panelY,
            panelWidth = panelWidth,
            panelHeight = panelHeight,
            borderSize = borderSize,
            backdropX = borderSize,
            backdropY = borderSize,
            backdropWidth = math.max(panelWidth - (borderSize * 2), 2),
            backdropHeight = math.max(panelHeight - (borderSize * 2), 2),
            textX = borderSize + paddingX,
            textY = borderSize + paddingY,
            textWidth = math.max(panelWidth - ((borderSize + paddingX) * 2), 32),
            textHeight = textHeight,
            charHeight = charHeight,
            wrappedText = wrappedText,
        }
    end

    local sections = PersistentConfig._SplitPdaOverlaySections(rawText)
    local bodyCharHeight = ClampRange(math.floor((14.5 * pdaScale * uiScaleFactor * screenScale) + 0.5), 16, 28, 19)
    local titleCharHeight = math.max(bodyCharHeight + 3, math.floor(bodyCharHeight * 1.14))
    local tabsCharHeight = math.max(12, math.floor(bodyCharHeight * 0.70))
    local footerCharHeight = math.max(11, math.floor(bodyCharHeight * 0.68))
    local commandMenuWidth = math.floor(171 * math.max(uiScale, 1))
    local baseContentWidth = ClampRange(commandMenuWidth + math.max(22, math.floor(screenW * 0.012)), 280,
        math.min(540, screenW - 110), 360)
    local maxContentWidth = math.min(720, screenW - 90)
    local tabLineWidth = PersistentConfig._EstimateOverlayTextPixelWidth(sections.tabs, tabsCharHeight, 0.62, 0)
    local bodyLineWidth = PersistentConfig._EstimateOverlayTextPixelWidth(sections.body, bodyCharHeight, 0.68, 0)
    local footerLineWidth = PersistentConfig._EstimateOverlayTextPixelWidth(sections.footer, footerCharHeight, 0.72, 0)
    local contentWidth = ClampRange(math.max(baseContentWidth, tabLineWidth + 12, bodyLineWidth + 10, footerLineWidth + 10),
        baseContentWidth, maxContentWidth, baseContentWidth)
    local paddingX = math.max(16, math.floor(bodyCharHeight * 0.62))
    local paddingY = math.max(12, math.floor(bodyCharHeight * 0.44))
    local borderSize = math.max(2, math.floor(bodyCharHeight * 0.10))
    local headerPaddingTop = math.max(6, math.floor(bodyCharHeight * 0.18))
    local sectionGap = math.max(6, math.floor(bodyCharHeight * 0.18))

    local wrappedTabs = PersistentConfig._WrapOverlayTextToPixels(sections.tabs, contentWidth, tabsCharHeight, 0.72, 0)
    local wrappedBody = PersistentConfig._WrapOverlayTextToPixels(sections.body, contentWidth, bodyCharHeight, 0.68, 0)
    local wrappedFooter = PersistentConfig._WrapOverlayTextToPixels(sections.footer, contentWidth, footerCharHeight, 0.72, 0)

    local titleHeight = PersistentConfig._GetOverlayTextBlockHeight(titleCharHeight, 1, 1.0)
    local tabsHeight = PersistentConfig._GetOverlayTextBlockHeight(tabsCharHeight,
        PersistentConfig._CountOverlayTextLines(wrappedTabs), 1.02)
    local bodyHeight = PersistentConfig._GetOverlayTextBlockHeight(bodyCharHeight,
        PersistentConfig._CountOverlayTextLines(wrappedBody), 1.08)
    local footerHeight = 0
    if wrappedFooter ~= "" then
        footerHeight = PersistentConfig._GetOverlayTextBlockHeight(footerCharHeight,
            PersistentConfig._CountOverlayTextLines(wrappedFooter), 1.05)
    end

    local headerHeight = titleHeight + tabsHeight + headerPaddingTop + 8
    local panelWidth = contentWidth + (paddingX * 2) + (borderSize * 2)
    local panelHeight = headerHeight + bodyHeight + footerHeight + (paddingY * 2) + (borderSize * 2) + sectionGap
    if footerHeight > 0 then
        panelHeight = panelHeight + sectionGap
    end

    local panelX = math.max(marginX, math.floor(screenW * layout.panelX))
    local panelY = math.floor((screenH * anchorY) - (panelHeight * alignmentY))
    panelY = ClampRange(panelY, marginY, screenH - panelHeight - marginY, marginY)
    panelX = ClampRange(panelX, marginX, screenW - panelWidth - marginX, marginX)

    local headerX = borderSize
    local headerY = borderSize
    local headerWidth = math.max(panelWidth - (borderSize * 2), 2)
    local backdropY = borderSize
    local backdropHeight = math.max(panelHeight - (borderSize * 2), 2)
    local bodyTextY = borderSize + headerHeight + paddingY
    local footerTextY = bodyTextY + bodyHeight + sectionGap

    return {
        panelX = panelX,
        panelY = panelY,
        panelWidth = panelWidth,
        panelHeight = panelHeight,
        borderSize = borderSize,
        backdropX = borderSize,
        backdropY = backdropY,
        backdropWidth = math.max(panelWidth - (borderSize * 2), 2),
        backdropHeight = backdropHeight,
        headerX = headerX,
        headerY = headerY,
        headerWidth = headerWidth,
        headerHeight = headerHeight,
        titleX = borderSize + math.floor(headerWidth * 0.5),
        titleY = borderSize + headerPaddingTop,
        titleWidth = headerWidth,
        titleHeight = titleHeight,
        titleCharHeight = titleCharHeight,
        titleText = sections.title,
        tabsX = borderSize + math.floor(headerWidth * 0.5),
        tabsY = borderSize + headerPaddingTop + titleHeight - 4,
        tabsWidth = headerWidth,
        tabsHeight = tabsHeight,
        tabsCharHeight = tabsCharHeight,
        tabsText = wrappedTabs,
        textX = borderSize + paddingX,
        textY = bodyTextY,
        textWidth = contentWidth,
        textHeight = bodyHeight,
        charHeight = bodyCharHeight,
        wrappedText = wrappedBody,
        footerX = borderSize + paddingX,
        footerY = footerTextY,
        footerWidth = contentWidth,
        footerHeight = footerHeight,
        footerCharHeight = footerCharHeight,
        footerText = wrappedFooter,
    }
end

function PersistentConfig._HidePdaOverlay(kind)
    local state = PersistentConfig.PdaOverlay
    local ids = state.ids[kind]
    if not ids or not (exu and exu.HideOverlay) then
        return
    end

    if kind == "stats" then
        state.statsVisible = false
    elseif kind == "feedback" then
        state.feedbackVisible = false
        state.feedbackExpireAt = 0.0
    end

    pcall(exu.HideOverlay, ids.overlay)
end

function PersistentConfig._DestroyPdaOverlay(kind)
    local state = PersistentConfig.PdaOverlay
    local ids = state.ids[kind]
    if not ids or not exu then
        return
    end
    local childIds = { ids.frame, ids.backdrop, ids.header, ids.title, ids.tabs, ids.text, ids.footer }

    PersistentConfig._HidePdaOverlay(kind)
    if exu.RemoveOverlayElementChild then
        for _, childId in ipairs(childIds) do
            if childId then
                pcall(exu.RemoveOverlayElementChild, ids.root, childId)
            end
        end
    end
    if exu.RemoveOverlay2D then
        pcall(exu.RemoveOverlay2D, ids.overlay, ids.root)
    end
    if exu.DestroyOverlayElement then
        for index = #childIds, 1, -1 do
            local childId = childIds[index]
            if childId then
                pcall(exu.DestroyOverlayElement, childId)
            end
        end
        pcall(exu.DestroyOverlayElement, ids.root)
    end
    if exu.DestroyOverlay then
        pcall(exu.DestroyOverlay, ids.overlay)
    end

    state.ready = false
    state.created = state.created or {}
    state.createdVersion = state.createdVersion or {}
    state.created[kind] = false
    state.createdVersion[kind] = nil
end

function PersistentConfig._DestroyAllPdaOverlays()
    PersistentConfig._DestroyPdaOverlay("feedback")
    PersistentConfig._DestroyPdaOverlay("stats")
end

function PersistentConfig._ResetPdaOverlayState()
    local state = PersistentConfig.PdaOverlay
    state.ready = false
    state.failed = false
    state.created = {}
    state.createdVersion = {}
    state.statsVisible = false
    state.feedbackVisible = false
    state.feedbackExpireAt = 0.0
end

function PersistentConfig._TryCreatePdaOverlay(kind)
    local state = PersistentConfig.PdaOverlay
    state.created = state.created or {}
    state.createdVersion = state.createdVersion or {}
    local ids = state.ids[kind]
    if state.created[kind] then
        local expectedVersion = state.structureVersion or 1
        local versionMatches = (state.createdVersion[kind] == expectedVersion)
        local frameOk = true
        if ids and ids.frame and exu and exu.HasOverlayElement then
            local ok, hasFrame = pcall(exu.HasOverlayElement, ids.frame)
            frameOk = ok and hasFrame == true
        end
        if versionMatches and frameOk then
            return true
        end
        state.created[kind] = false
    end

    if not PersistentConfig._CanUsePdaOverlay() then
        state.failed = true
        return false
    end

    if not ids then
        state.failed = true
        return false
    end

    PersistentConfig._DestroyPdaOverlay(kind)

    local metricsMode = PersistentConfig._GetPdaOverlayMetricsMode()
    local overlayZOrder = state.zOrder or 645
    if kind == "feedback" then
        overlayZOrder = overlayZOrder + 1
    end
    local panelIds = { ids.frame, ids.backdrop, ids.header }
    local textIds = { ids.text, ids.title, ids.tabs, ids.footer }
    local childIds = { ids.frame, ids.backdrop, ids.header, ids.title, ids.tabs, ids.text, ids.footer }
    local ok = true

    local function SafeCall(fn, ...)
        if not ok or type(fn) ~= "function" then
            return nil
        end

        local success, result = pcall(fn, ...)
        if not success then
            ok = false
            Log("PersistentConfig: PDA overlay call failed: " .. tostring(result))
            return nil
        end
        return result
    end

    if SafeCall(exu.CreateOverlay, ids.overlay) == false then
        ok = false
    end
    local rootTypeName = ids.frame and "Panel" or "BorderPanel"
    if SafeCall(exu.CreateOverlayElement, rootTypeName, ids.root) == false then
        ok = false
    end
    for _, panelId in ipairs(panelIds) do
        local panelTypeName = "Panel"
        if panelId == ids.frame then
            panelTypeName = "BorderPanel"
        end
        if panelId and SafeCall(exu.CreateOverlayElement, panelTypeName, panelId) == false then
            ok = false
        end
    end
    for _, textId in ipairs(textIds) do
        if textId and SafeCall(exu.CreateOverlayElement, "TextArea", textId) == false then
            ok = false
        end
    end
    if exu.HasOverlayElement then
        if SafeCall(exu.HasOverlayElement, ids.root) ~= true then
            ok = false
        end
        for _, childId in ipairs(childIds) do
            if childId and SafeCall(exu.HasOverlayElement, childId) ~= true then
                ok = false
            end
        end
    end

    SafeCall(exu.AddOverlay2D, ids.overlay, ids.root)
    for _, childId in ipairs(childIds) do
        if childId then
            SafeCall(exu.AddOverlayElementChild, ids.root, childId)
        end
    end
    SafeCall(exu.SetOverlayZOrder, ids.overlay, ClampRange(overlayZOrder, 0, 650, 645))

    SafeCall(exu.SetOverlayMetricsMode, ids.root, metricsMode)
    for _, childId in ipairs(childIds) do
        if childId then
            SafeCall(exu.SetOverlayMetricsMode, childId, metricsMode)
        end
    end

    SafeCall(exu.SetOverlayParameter, ids.root, "transparent", true)
    SafeCall(exu.SetOverlayColor, ids.root, 0.0, 0.0, 0.0, 0.0)
    
    local preset = GetPdaColorPreset()
    local backdropMaterial = PersistentConfig._GetPdaOverlayPanelMaterial("Backdrop", preset.r, preset.g, preset.b)
    local headerMaterial = PersistentConfig._GetPdaOverlayPanelMaterial("Header", preset.r, preset.g, preset.b)
    local borderMaterial = PersistentConfig._GetPdaOverlayPanelMaterial("Border", preset.r, preset.g, preset.b)
    for _, panelId in ipairs(panelIds) do
        if panelId then
            if panelId == ids.frame then
                SafeCall(exu.SetOverlayMaterial, panelId, "BaseWhiteNoLighting")
                SafeCall(exu.SetOverlayParameter, panelId, "transparent", true)
            elseif panelId == ids.backdrop or panelId == ids.header then
                local panelMaterial = (panelId == ids.header) and headerMaterial or backdropMaterial
                if panelMaterial then
                    SafeCall(exu.SetOverlayMaterial, panelId, panelMaterial)
                end
            end
        end
    end
    if ids.frame then
        SafeCall(exu.SetOverlayParameter, ids.frame, "border_size", "2 2 2 2")
        SafeCall(exu.SetOverlayParameter, ids.frame, "border_material", borderMaterial)
    else
        SafeCall(exu.SetOverlayParameter, ids.root, "border_size", "2 2 2 2")
        SafeCall(exu.SetOverlayParameter, ids.root, "border_material", borderMaterial)
    end
    for _, textId in ipairs(textIds) do
        if textId then
            local alignment = "left"
            if textId == ids.title or textId == ids.tabs then
                alignment = "center"
            end
            SafeCall(exu.SetOverlayParameter, textId, "alignment", alignment)
        end
    end

    if state.useCustomFont then
        for _, textId in ipairs(textIds) do
            if textId and SafeCall(exu.SetOverlayTextFont, textId, state.font) ~= true then
                ok = false
                Log("PersistentConfig: PDA overlay font bind failed for " .. tostring(state.font))
            end
        end
    end

    for _, textId in ipairs(textIds) do
        if textId then
            SafeCall(exu.SetOverlayCaption, textId, "")
        end
    end
    SafeCall(exu.ShowOverlayElement, ids.root)
    for _, childId in ipairs(childIds) do
        if childId then
            SafeCall(exu.ShowOverlayElement, childId)
        end
    end
    SafeCall(exu.HideOverlay, ids.overlay)

    if not ok then
        state.failed = true
        PersistentConfig._DestroyPdaOverlay(kind)
        return false
    end

    state.ready = true
    state.failed = false
    state.created[kind] = true
    state.createdVersion[kind] = state.structureVersion or 1
    return true
end

function PersistentConfig._ShowPdaOverlay(kind, rawText, duration, r, g, b, page)
    if not rawText or rawText == "" then
        return false
    end

    if GetTime() < 0.25 then
        return false
    end

    if not PersistentConfig._TryCreatePdaOverlay(kind) then
        return false
    end

    local ids = PersistentConfig.PdaOverlay.ids[kind]
    local layout = PersistentConfig._GetPdaOverlayPixelLayout(kind, rawText, page)
    local colors = PersistentConfig._GetPdaOverlayColorSet(r, g, b)
    local panelR, panelG, panelB = GetPdaPanelMaterialTargetColor(r, g, b)
    local backdropMaterial = PersistentConfig._GetPdaOverlayPanelMaterial("Backdrop", panelR, panelG, panelB)
    local headerMaterial = PersistentConfig._GetPdaOverlayPanelMaterial("Header", panelR, panelG, panelB)
    local borderMaterial = PersistentConfig._GetPdaOverlayPanelMaterial("Border", panelR, panelG, panelB)
    local ok = true

    local function SafeCall(fn, ...)
        if not ok or type(fn) ~= "function" then
            return nil
        end

        local success, result = pcall(fn, ...)
        if not success then
            ok = false
            Log("PersistentConfig: PDA overlay update failed: " .. tostring(result))
            return nil
        end
        return result
    end

    local borderSizeString = string.format("%d %d %d %d", layout.borderSize, layout.borderSize, layout.borderSize,
        layout.borderSize)

    SafeCall(exu.SetOverlayPosition, ids.root, layout.panelX, layout.panelY)
    SafeCall(exu.SetOverlayDimensions, ids.root, layout.panelWidth, layout.panelHeight)
    SafeCall(exu.SetOverlayParameter, ids.root, "transparent", true)
    SafeCall(exu.SetOverlayColor, ids.root, 1.0, 1.0, 1.0, 1.0)

    if ids.frame then
        SafeCall(exu.SetOverlayPosition, ids.frame, 0, 0)
        SafeCall(exu.SetOverlayDimensions, ids.frame, layout.panelWidth, layout.panelHeight)
        SafeCall(exu.SetOverlayMaterial, ids.frame, "BaseWhiteNoLighting")
        SafeCall(exu.SetOverlayParameter, ids.frame, "transparent", true)
        SafeCall(exu.SetOverlayParameter, ids.frame, "border_size", borderSizeString)
        SafeCall(exu.SetOverlayParameter, ids.frame, "border_material", borderMaterial)
        SafeCall(exu.SetOverlayColor, ids.frame, 1.0, 1.0, 1.0, 1.0)
    else
        SafeCall(exu.SetOverlayParameter, ids.root, "border_size", borderSizeString)
        SafeCall(exu.SetOverlayParameter, ids.root, "border_material", borderMaterial)
        SafeCall(exu.SetOverlayColor, ids.root, 1.0, 1.0, 1.0, 1.0)
    end

    SafeCall(exu.SetOverlayPosition, ids.backdrop, layout.backdropX, layout.backdropY)
    SafeCall(exu.SetOverlayDimensions, ids.backdrop, layout.backdropWidth, layout.backdropHeight)
    if backdropMaterial then
        SafeCall(exu.SetOverlayMaterial, ids.backdrop, backdropMaterial)
    end
    SafeCall(exu.SetOverlayColor, ids.backdrop, 1.0, 1.0, 1.0, 1.0)

    if ids.header and layout.headerWidth and layout.headerHeight then
        SafeCall(exu.SetOverlayPosition, ids.header, layout.headerX, layout.headerY)
        SafeCall(exu.SetOverlayDimensions, ids.header, layout.headerWidth, layout.headerHeight)
        if headerMaterial then
            SafeCall(exu.SetOverlayMaterial, ids.header, headerMaterial)
        end
        SafeCall(exu.SetOverlayColor, ids.header, 1.0, 1.0, 1.0, 1.0)
    end

    if ids.title and layout.titleText then
        SafeCall(exu.SetOverlayPosition, ids.title, layout.titleX, layout.titleY)
        SafeCall(exu.SetOverlayDimensions, ids.title, layout.titleWidth, layout.titleHeight)
        SafeCall(exu.SetOverlayTextCharHeight, ids.title, layout.titleCharHeight)
        SafeCall(exu.SetOverlayParameter, ids.title, "space_width",
            PersistentConfig._GetPdaOverlaySpaceWidth(layout.titleCharHeight))
        if exu.SetOverlayTextColor then
            SafeCall(exu.SetOverlayTextColor, ids.title, colors.title.r, colors.title.g, colors.title.b, colors.title.a)
        else
            SafeCall(exu.SetOverlayColor, ids.title, colors.title.r, colors.title.g, colors.title.b, colors.title.a)
        end
        SafeCall(exu.SetOverlayCaption, ids.title, layout.titleText)
    end

    if ids.tabs and layout.tabsText then
        SafeCall(exu.SetOverlayPosition, ids.tabs, layout.tabsX, layout.tabsY)
        SafeCall(exu.SetOverlayDimensions, ids.tabs, layout.tabsWidth, layout.tabsHeight)
        SafeCall(exu.SetOverlayTextCharHeight, ids.tabs, layout.tabsCharHeight)
        SafeCall(exu.SetOverlayParameter, ids.tabs, "space_width",
            PersistentConfig._GetPdaOverlaySpaceWidth(layout.tabsCharHeight))
        if exu.SetOverlayTextColor then
            SafeCall(exu.SetOverlayTextColor, ids.tabs, colors.text.r, colors.text.g, colors.text.b, colors.text.a)
        else
            SafeCall(exu.SetOverlayColor, ids.tabs, colors.text.r, colors.text.g, colors.text.b, colors.text.a)
        end
        SafeCall(exu.SetOverlayCaption, ids.tabs, layout.tabsText)
    end

    SafeCall(exu.SetOverlayPosition, ids.text, layout.textX, layout.textY)
    SafeCall(exu.SetOverlayDimensions, ids.text, layout.textWidth, layout.textHeight)
    SafeCall(exu.SetOverlayTextCharHeight, ids.text, layout.charHeight)
    SafeCall(exu.SetOverlayParameter, ids.text, "space_width",
        PersistentConfig._GetPdaOverlaySpaceWidth(layout.charHeight))
    if exu.SetOverlayTextColor then
        SafeCall(exu.SetOverlayTextColor, ids.text, colors.text.r, colors.text.g, colors.text.b, colors.text.a)
    else
        SafeCall(exu.SetOverlayColor, ids.text, colors.text.r, colors.text.g, colors.text.b, colors.text.a)
    end
    SafeCall(exu.SetOverlayCaption, ids.text, layout.wrappedText)

    if ids.footer and layout.footerText and layout.footerText ~= "" then
        SafeCall(exu.SetOverlayPosition, ids.footer, layout.footerX, layout.footerY)
        SafeCall(exu.SetOverlayDimensions, ids.footer, layout.footerWidth, layout.footerHeight)
        SafeCall(exu.SetOverlayTextCharHeight, ids.footer, layout.footerCharHeight)
        SafeCall(exu.SetOverlayParameter, ids.footer, "space_width",
            PersistentConfig._GetPdaOverlaySpaceWidth(layout.footerCharHeight))
        if exu.SetOverlayTextColor then
            SafeCall(exu.SetOverlayTextColor, ids.footer, colors.footer.r, colors.footer.g, colors.footer.b,
                colors.footer.a)
        else
            SafeCall(exu.SetOverlayColor, ids.footer, colors.footer.r, colors.footer.g, colors.footer.b, colors.footer.a)
        end
        SafeCall(exu.SetOverlayCaption, ids.footer, layout.footerText)
    elseif ids.footer then
        SafeCall(exu.SetOverlayCaption, ids.footer, "")
    end

    SafeCall(exu.ShowOverlayElement, ids.root)
    if ids.frame then
        SafeCall(exu.ShowOverlayElement, ids.frame)
    end
    SafeCall(exu.ShowOverlayElement, ids.backdrop)
    if ids.header then
        SafeCall(exu.ShowOverlayElement, ids.header)
    end
    if ids.title then
        SafeCall(exu.ShowOverlayElement, ids.title)
    end
    if ids.tabs then
        SafeCall(exu.ShowOverlayElement, ids.tabs)
    end
    SafeCall(exu.ShowOverlayElement, ids.text)
    if ids.footer then
        SafeCall(exu.ShowOverlayElement, ids.footer)
    end
    SafeCall(exu.ShowOverlay, ids.overlay)

    if not ok then
        PersistentConfig.PdaOverlay.ready = false
        PersistentConfig.PdaOverlay.failed = true
        PersistentConfig._DestroyPdaOverlay(kind)
        return false
    end

    if kind == "stats" then
        PersistentConfig.PdaOverlay.statsVisible = true
    elseif kind == "feedback" then
        PersistentConfig.PdaOverlay.feedbackVisible = true
        PersistentConfig.PdaOverlay.feedbackExpireAt = GetTime() + math.max(tonumber(duration) or 2.5, 0.10)
    end

    return true
end

function PersistentConfig._UpdatePdaOverlayTimers()
    if not PersistentConfig.PdaOverlay.feedbackVisible then
        return
    end

    local hideAt = PersistentConfig.PdaOverlay.feedbackExpireAt or 0.0
    if GetTime() >= hideAt then
        PersistentConfig._HidePdaOverlay("feedback")
    end
end

local function ShowPdaFeedback(msg, r, g, b, duration)
    if PersistentConfig.Settings.WeaponStatsHud
        and PersistentConfig._ShowPdaOverlay("feedback", msg, duration or 2.5, r, g, b,
            InputState and InputState.pdaPage or PdaPages.SETTINGS) then
        return
    end

    local subtit = GetScriptSubtitles()
    local colorPreset = GetPdaColorPreset()
    if subtit and subtit.Display then
        subtit.Display(msg, r or colorPreset.r, g or colorPreset.g, b or colorPreset.b, duration or 2.5)
        return
    end

    if msg and msg ~= "" then
        Log(string.format("PersistentConfig: ScriptSubtitles unavailable; dropped PDA feedback '%s'.",
            tostring(msg or "")))
    end
end

local function ShowWeaponStats(msg, duration)
    if PersistentConfig._ShowPdaOverlay("stats", msg, duration or 86400.0, nil, nil, nil,
            InputState and InputState.pdaPage or PdaPages.STATS) then
        return
    end

    -- Avoid spawning the legacy PDA window during the brief startup window where the
    -- EXU overlay path has not finished coming online yet. A later refresh will show
    -- the proper overlay instead of leaving both renderers visible at once.
    if GetTime() < 0.25 or PersistentConfig._CanUsePdaOverlay() then
        return
    end

    local colorPreset = GetPdaColorPreset()
    ShowFeedback(msg, colorPreset.r, colorPreset.g, colorPreset.b, duration or 2.4, false)
end

local function ClearWeaponStats()
    PersistentConfig._HidePdaOverlay("stats")
end

local function ClearPdaFeedback()
    PersistentConfig._HidePdaOverlay("feedback")
end

local function MarkOtherHeadlightsDirty()
    InputState.otherHeadlightsDirty = true
end

local function AddTrackedHandle(list, set, h)
    if not h or not IsValid(h) or set[h] then
        return false
    end

    set[h] = true
    list[#list + 1] = h
    return true
end

local function RemoveTrackedHandle(list, set, h)
    if not h or not set[h] then
        return
    end

    set[h] = nil
    for index = #list, 1, -1 do
        if list[index] == h then
            table.remove(list, index)
            break
        end
    end
end

local function IsHeadlightTrackedHandle(h)
    if not h or not IsValid(h) then
        return false
    end

    if type(IsCraft) == "function" and IsCraft(h) then
        return true
    end

    local label = CleanString((type(GetClassLabel) == "function" and GetClassLabel(h)) or "")
    return label == "turret"
end

local function IsRepairPowerHandle(h)
    if not h or not IsValid(h) then
        return false
    end

    local label = CleanString((type(GetClassLabel) == "function" and GetClassLabel(h)) or "")
    return label == "powerplant"
end

local function IsRepairTargetHandle(h)
    if not h or not IsValid(h) then
        return false
    end

    if type(IsBuilding) == "function" and IsBuilding(h) then
        return true
    end

    local label = CleanString((type(GetClassLabel) == "function" and GetClassLabel(h)) or "")
    return label == "turret"
end

local function ApplyOtherHeadlightVisibility(h, visible, player)
    if not exu or not exu.SetHeadlightVisible or not IsValid(h) then return false end
    if h == player then
        InputState.otherHeadlightVisibility[h] = nil
        return false
    end
    if InputState.otherHeadlightVisibility[h] == visible then
        return false
    end

    exu.SetHeadlightVisible(h, visible)
    InputState.otherHeadlightVisibility[h] = visible
    return true
end

local IsCommanderTrackedHandle
local RegisterCommanderHandle
local RemoveCommanderHandle

local function RegisterTrackedWorldHandle(h)
    local tracking = InputState and InputState.worldTracking
    if not tracking or not h or not IsValid(h) then
        return
    end

    if not AddTrackedHandle(tracking.handles, tracking.handleSet, h) then
        return
    end

    if IsHeadlightTrackedHandle(h) then
        AddTrackedHandle(tracking.headlightHandles, tracking.headlightHandleSet, h)
    end

    if IsCommanderTrackedHandle(h) then
        RegisterCommanderHandle(h)
    end

    if IsRepairPowerHandle(h) then
        AddTrackedHandle(tracking.repairPowerHandles, tracking.repairPowerHandleSet, h)
    end

    if IsRepairTargetHandle(h) then
        AddTrackedHandle(tracking.repairTargetHandles, tracking.repairTargetHandleSet, h)
    end
end

local function RemoveTrackedWorldHandle(h)
    local tracking = InputState and InputState.worldTracking
    if not tracking or not h then
        return
    end

    RemoveTrackedHandle(tracking.handles, tracking.handleSet, h)
    RemoveTrackedHandle(tracking.headlightHandles, tracking.headlightHandleSet, h)
    RemoveTrackedHandle(tracking.repairPowerHandles, tracking.repairPowerHandleSet, h)
    RemoveTrackedHandle(tracking.repairTargetHandles, tracking.repairTargetHandleSet, h)
    RemoveCommanderHandle(h)
    InputState.otherHeadlightVisibility[h] = nil
end

local function ResetTrackedWorldHandles()
    local tracking = InputState and InputState.worldTracking
    if not tracking then
        return
    end

    tracking.initialized = false
    tracking.handles = {}
    tracking.handleSet = {}
    tracking.headlightHandles = {}
    tracking.headlightHandleSet = {}
    tracking.repairPowerHandles = {}
    tracking.repairPowerHandleSet = {}
    tracking.repairTargetHandles = {}
    tracking.repairTargetHandleSet = {}
end

local function InitializeTrackedWorldHandles()
    local tracking = InputState and InputState.worldTracking
    if not tracking or tracking.initialized then
        return
    end

    tracking.initialized = true
    if not AllObjects then
        return
    end

    for h in AllObjects() do
        RegisterTrackedWorldHandle(h)
    end
end

-- Helper to parse bzlogger.txt for Steam ID/Username
local function ParseBzLogger()
    if not bzfile or not bzfile.Open then return nil, nil end
    local logPath = "bzlogger.txt"
    local f = bzfile.Open(logPath, "r")

    -- Fallback to parent directory if not found
    if not f then
        logPath = "../bzlogger.txt"
        f = bzfile.Open(logPath, "r")
    end

    if not f then
        print("PersistentConfig: Could not find bzlogger.txt for parsing.")
        return nil, nil
    end

    print("PersistentConfig: Scanning " .. logPath .. " for Steam credentials...")
    local steamID, username

    local line = f:Readln()
    while line do
        local id, name = line:match("Authenticated to BZRNet As S(%d+):(.+)")
        if id and name then
            steamID = id
            username = name
            break -- Found it, stop scanning
        end
        line = f:Readln()
    end

    f:Close()
    return steamID, username
end

-- Storage for User Info
PersistentConfig.User = {
    SteamID = nil,
    Username = nil
}

-- Shared Greeting Logic
function PersistentConfig.TriggerGreeting(steamID, username)
    PersistentConfig.User.SteamID = steamID
    PersistentConfig.User.Username = username
    local CustomNames = {
        ["76561198241259700"] = "GlizzyJuan",   -- GrizzlyOne95
        ["76561198104781489"] = "British Twat", --JJ
        ["76561199014392897"] = "Car Nerd",     --DriveLine
        ["76561198095046296"] = "HF Imperium",  --HyperFighter
        ["76561198884003346"] = "Linux Nerd",        --Piercing
    }

    local displayName = CustomNames[tostring(steamID)] or username

    if displayName then
        ShowFeedback("Welcome back, Commander " .. displayName .. ".", 0.5, 0.8, 1.0, 5.0, false)
        print("Steam User: " .. displayName .. " (" .. tostring(steamID) .. ")")
    else
        ShowFeedback("Welcome back, Commander.", 0.5, 0.8, 1.0, 5.0, false)
        print("Steam User ID: " .. tostring(steamID))
    end
end

-- Internal State
InputState = {
    last_v_state = false,    -- Headlight (V)
    last_z_state = false,    -- Color (Z)
    last_j_state = false,    -- AI Lights (J)
    last_b_state = false,    -- Beam (B)
    last_help_state = false, --/ or ? on keyboard
    last_x_state = false,    -- Auto-repair toggle
    last_u_state = false,    -- Scavenger Assist (U)
    last_l_state = false,    -- Reserved
    last_y_state = false,    -- PDA toggle (Y)
    last_left_bracket_state = false,
    last_right_bracket_state = false,
    last_pda_up_state = false,
    last_pda_down_state = false,
    last_pda_left_state = false,
    last_pda_right_state = false,
    SubtitlesPaused = false,
    SteamIDFound = false,
    GreetingTriggered = false,
    PollingStartTime = 0,
    last_poll_time = 0,
    last_repair_time = 0,
    repair_interval = 1.0,  -- Run repair logic every 1 second
    lastPlayerHandle = nil, -- Track player handle to detect craft changes
    lastWeaponMask = nil,
    lastWeaponPlayer = nil,
    lastWeaponText = nil,
    lastWeaponTarget = nil,
    lastUnitVoTeam = nil,
    autoSaveStartupPending = false,
    nextWeaponHudCheck = 0.0,
    nextPdaOverlayRefresh = 0.0,
    pdaOverlayRefreshPending = false,
    pdaOverlayRefreshReason = nil,
    nextRadarScaleCheck = 0.0,
    radarScaleSyncPending = false,
    nextRetroLightingCheck = 0.0,
    nextRetroLightingStabilizeUntil = 0.0,
    lightingModeSyncPending = false,
    nextFactionFlameRefresh = 0.0,
    pdaPage = PdaPages.STATS,
    pdaSettingsIndex = 1,
    presetProducerIndex = 1,
    presetUnitIndex = 1,
    presetRow = 1,
    queueProducerIndex = 1,
    queueRow = 1,
    pendingGameKeys = {},
    autoSaveEnableArmed = false,
    autoSaveConfirmSlot = nil,
    processedCreationHandles = {},
    otherHeadlightVisibility = {},
    otherHeadlightsDirty = true,
    worldTracking = {
        initialized = false,
        handles = {},
        handleSet = {},
        headlightHandles = {},
        headlightHandleSet = {},
        repairPowerHandles = {},
        repairPowerHandleSet = {},
        repairTargetHandles = {},
        repairTargetHandleSet = {},
    },
    lastTeamScrap = {},
    lastBuildKey = nil,
    producerBusyState = {},
    pendingBuilds = {},
    producerQueues = {},
    commanderOverview = {
        initialized = false,
        lastUpdate = 0,
        interval = 1.0,
        handles = {},
        handleSet = {},
        stats = {
            counts = {},
            unpoweredTurrets = 0,
            unpoweredComm = 0,
            powerSources = 0,
        },
    },
}

PersistentConfig.RetroLightingIntervals = PersistentConfig.D.RetroLightingIntervals
PersistentConfig.LightingModePresets = PersistentConfig.D.LightingModePresets

-- Beam Definitions
PersistentConfig.HeadlightBeamModes = PersistentConfig.D.BeamModes

-- Helper to parse a simple key=value line
local function ParseLine(line)
    local key, value = line:match("([^=]+)=(.+)")
    if key then
        key = key:match("^%s*(.-)%s*$")
        value = value:match("^%s*(.-)%s*$")
        return key, value
    end
    return nil
end

CleanString = function(s)
    if not s then return "" end
    return string.gsub(tostring(s), "%z", "")
end

local function HasOdfNumber(value, found)
    if type(found) == "boolean" then
        return found and type(value) == "number" and value > 0
    end
    return type(value) == "number" and value > 0
end

local function HasOdfString(value, found)
    local cleaned = CleanString(value)
    if type(found) == "boolean" then
        return found and cleaned ~= ""
    end
    return cleaned ~= ""
end

-- Forward declaration (used by commander overview before definition).
local GetPowerRadius

local function IsMaskBitSet(mask, slot)
    local div = 2 ^ slot
    return (math.floor(mask / div) % 2) >= 1
end

local function GetCurrentWeaponMask(player)
    if not IsValid(player) then return 0 end

    if type(GetWeaponMask) == "function" then
        local ok, value = pcall(GetWeaponMask, player)
        if ok and type(value) == "number" then
            return math.max(0, math.floor(value + 0.5))
        end
    end

    -- Fallback if GetWeaponMask isn't available in this environment.
    local mask = 0
    for slot = 0, 4 do
        local weapon = CleanString(GetWeaponClass(player, slot))
        if weapon ~= "" then
            mask = mask + (2 ^ slot)
        end
    end
    return mask
end

local function NormalizeWeaponMask(mask)
    if type(mask) ~= "number" then
        return 0
    end
    return math.max(0, math.floor(mask + 0.5))
end

local function FilterWeaponMaskToInstalled(mask, installedMask)
    local filtered = 0
    local sourceMask = NormalizeWeaponMask(mask)
    local mountedMask = NormalizeWeaponMask(installedMask)
    for slot = 0, 4 do
        if IsMaskBitSet(sourceMask, slot) and IsMaskBitSet(mountedMask, slot) then
            filtered = filtered + (2 ^ slot)
        end
    end
    return filtered
end

local GetInstalledWeaponMask

local function ResolveLiveSelectedWeaponMask(player, fallbackMask)
    if not IsValid(player) then
        return 0
    end

    local installedMask = GetInstalledWeaponMask(player)

    if exu and type(exu.GetWeaponSelectionInfo) == "function" then
        local ok, info = pcall(exu.GetWeaponSelectionInfo, player)
        if ok and type(info) == "table" then
            local selectedReadyMask = FilterWeaponMaskToInstalled(info.selectedReadyMask, installedMask)
            if selectedReadyMask > 0 then
                return selectedReadyMask
            end

            local selectedMountedMask = FilterWeaponMaskToInstalled(info.selectedMountedMask, installedMask)
            if selectedMountedMask > 0 then
                return selectedMountedMask
            end

            local activeSlot = tonumber(info.modeListActiveSlot)
            if activeSlot and activeSlot >= 0 and activeSlot <= 4 and IsMaskBitSet(installedMask, activeSlot) then
                return 2 ^ activeSlot
            end
        end
    end

    if exu and type(exu.GetSelectedWeaponMask) == "function" then
        local ok, selectedMask = pcall(exu.GetSelectedWeaponMask, player)
        if ok then
            local filteredMask = FilterWeaponMaskToInstalled(selectedMask, installedMask)
            if filteredMask > 0 then
                return filteredMask
            end
        end
    end

    return FilterWeaponMaskToInstalled(fallbackMask, installedMask)
end

local function ProbeRangeFromOdf(odf)
    if not odf or not GetODFFloat then return nil end

    local probes = {
        { "WeaponClass", "maxRange" },
        { "WeaponClass", "engageRange" },
        { "WeaponClass", "maxDist" },
        { "WeaponClass", "engageDist" },
        { "WeaponClass", "shotRange" },
        { "WeaponClass", "range" },
        { "OrdnanceClass", "maxRange" },
        { "OrdnanceClass", "engageRange" },
        { "OrdnanceClass", "maxDist" },
        { "OrdnanceClass", "engageDist" },
        { "OrdnanceClass", "shotRange" },
        { "OrdnanceClass", "range" },
        { "CannonClass", "maxRange" },
        { "CannonClass", "maxDist" },
        { "CannonClass", "shotRange" },
        { "CannonClass", "range" },
        { "GunClass", "maxRange" },
        { "GunClass", "maxDist" },
        { "GunClass", "shotRange" },
        { "GunClass", "range" },
        { "RocketClass", "maxRange" },
        { "RocketClass", "maxDist" },
        { "RocketClass", "shotRange" },
        { "RocketClass", "range" },
        { "MissileClass", "maxRange" },
        { "MissileClass", "maxDist" },
        { "MissileClass", "shotRange" },
        { "MissileClass", "range" },
        { "MortarClass", "maxRange" },
        { "MortarClass", "maxDist" },
        { "MortarClass", "shotRange" },
        { "MortarClass", "range" },
        { nil, "maxRange" },
        { nil, "engageRange" },
        { nil, "maxDist" },
        { nil, "engageDist" },
        { nil, "shotRange" },
        { nil, "range" }
    }

    local best = nil
    for _, probe in ipairs(probes) do
        local value, found = GetODFFloat(odf, probe[1], probe[2], 0.0)
        if HasOdfNumber(value, found) then
            if not best or value > best then best = value end
        end
    end
    return best
end

local function ProbeTravelRangeFromOdf(odf)
    if not odf or not GetODFFloat then return nil end

    local lifeSpan, lifeFound = GetODFFloat(odf, "OrdnanceClass", "lifeSpan", 0.0)
    if not HasOdfNumber(lifeSpan, lifeFound) then
        lifeSpan, lifeFound = GetODFFloat(odf, nil, "lifeSpan", 0.0)
    end

    local shotSpeed, speedFound = GetODFFloat(odf, "OrdnanceClass", "shotSpeed", 0.0)
    if not HasOdfNumber(shotSpeed, speedFound) then
        shotSpeed, speedFound = GetODFFloat(odf, nil, "shotSpeed", 0.0)
    end

    if HasOdfNumber(lifeSpan, lifeFound) and HasOdfNumber(shotSpeed, speedFound) then
        if lifeSpan >= 120.0 then
            return nil
        end
        return lifeSpan * shotSpeed
    end

    return nil
end

local function GetOdfClassLabel(odf)
    if not odf or not GetODFString then return nil end

    local value, found = GetODFString(odf, "OrdnanceClass", "classLabel", "")
    local cleaned = CleanString(value)
    if HasOdfString(cleaned, found) then
        return string.lower(cleaned)
    end

    value, found = GetODFString(odf, "WeaponClass", "classLabel", "")
    cleaned = CleanString(value)
    if HasOdfString(cleaned, found) then
        return string.lower(cleaned)
    end

    value, found = GetODFString(odf, nil, "classLabel", "")
    cleaned = CleanString(value)
    if HasOdfString(cleaned, found) then
        return string.lower(cleaned)
    end

    return nil
end

local function ProbeBallisticRangeFromOdf(odf)
    if not odf or not GetODFFloat then return nil end

    local classLabel = GetOdfClassLabel(odf)
    local ballisticClasses = {
        grenade = true,
        bouncebomb = true,
        spraybomb = true,
    }
    if not ballisticClasses[classLabel] then
        return nil
    end

    local shotSpeed, speedFound = GetODFFloat(odf, "OrdnanceClass", "shotSpeed", 0.0)
    if not HasOdfNumber(shotSpeed, speedFound) then
        shotSpeed, speedFound = GetODFFloat(odf, nil, "shotSpeed", 0.0)
    end
    if not HasOdfNumber(shotSpeed, speedFound) then
        return nil
    end

    local coeff = 4.9
    if exu and exu.GetCoeffBallistic then
        local ok, value = pcall(exu.GetCoeffBallistic)
        if ok and type(value) == "number" and value > 0.0 then
            coeff = value
        end
    end
    if coeff <= 0.0 then
        return nil
    end

    return (shotSpeed * shotSpeed) / (2.0 * coeff)
end

local function GetBallisticCoeff()
    local coeff = 4.9
    if exu and exu.GetCoeffBallistic then
        local ok, value = pcall(exu.GetCoeffBallistic)
        if ok and type(value) == "number" and value > 0.0 then
            coeff = value
        end
    end
    return coeff
end

local function GetWeaponDisplayName(weaponOdfName)
    if not weaponOdfName or weaponOdfName == "" then return nil end
    PersistentConfig.WeaponNameCache = PersistentConfig.WeaponNameCache or {}

    local key = string.lower(weaponOdfName)
    if PersistentConfig.WeaponNameCache[key] ~= nil then
        return PersistentConfig.WeaponNameCache[key]
    end

    local displayName = nil
    if OpenODF and GetODFString then
        local weaponOdf = OpenODF(weaponOdfName)
        if weaponOdf then
            local value, found = GetODFString(weaponOdf, "WeaponClass", "wpnName", "")
            local cleaned = CleanString(value)
            if HasOdfString(cleaned, found) then
                displayName = cleaned
            end
        end
    end

    if not displayName or displayName == "" then
        displayName = weaponOdfName
    end

    PersistentConfig.WeaponNameCache[key] = displayName
    return displayName
end

local WEAPON_VALUE_SECTIONS = {
    "WeaponClass", "OrdnanceClass", "CannonClass", "ChargeGunClass", "GunClass", "RocketClass", "MissileClass",
    "MortarClass", "DispenserClass", "LauncherClass", "TargetingGunClass", "RadarLauncherClass", "PopperGunClass",
    "ObjectLobberClass", "RemoteDetonatorClass", "LeaderRoundClass", nil
}

local WEAPON_REFERENCE_LABELS = { "ordName", "ordnanceName", "shotClass", "projectileClass", "objectClass" }
local WEAPON_RANGE_LABELS = { "maxRange", "engageRange", "maxDist", "engageDist", "shotRange", "range", "lockRange" }
local WEAPON_DELAY_LABELS = { "shotDelay", "reloadTime", "reloadDelay", "firstDelay" }
local DAMAGE_LABELS = {
    "damage",
    "damage1", "damage2", "damage3", "damage4", "damage5", "damage6", "damage7", "damage8",
    "damageBallistic", "damageConcussion", "damageFlame", "damageImpact", "damageArea", "damageEM"
}
local DAMAGE_SECTIONS = { "WeaponClass", "OrdnanceClass", "ExplosionClass", "CannonClass", "GunClass", "RocketClass", "MissileClass", "MortarClass", nil }
local EXPLOSION_REFERENCE_LABELS = { "xplVehicle", "xplCar", "xplBuilding", "xplGround", "xplPilot" }
local EXPLOSION_RADIUS_LABELS = { "damageRadius", "explRadius" }

local function ResolveOrdnanceName(odf)
    if not odf or not GetODFString then return nil end
    for _, section in ipairs(WEAPON_VALUE_SECTIONS) do
        for _, label in ipairs(WEAPON_REFERENCE_LABELS) do
            local value, found = GetODFString(odf, section, label, "")
            local cleaned = CleanString(value)
            if HasOdfString(cleaned, found) then
                return cleaned
            end
        end
    end
    return nil
end

local function ProbeStringFromOdf(odf, labels, sections)
    if not odf or not GetODFString then return nil end
    sections = sections or WEAPON_VALUE_SECTIONS
    for _, section in ipairs(sections) do
        for _, label in ipairs(labels or {}) do
            local value, found = GetODFString(odf, section, label, "")
            local cleaned = CleanString(value)
            if HasOdfString(cleaned, found) then
                return cleaned
            end
        end
    end
    return nil
end

local function ProbeValueFromOdf(odf, labels, sections)
    if not odf or not GetODFFloat then return nil end
    sections = sections or WEAPON_VALUE_SECTIONS
    for _, section in ipairs(sections) do
        for _, label in ipairs(labels) do
            local value, found = GetODFFloat(odf, section, label, 0.0)
            if HasOdfNumber(value, found) then
                return value
            end
        end
    end
    return nil
end

local function ProbeMaxValueFromOdf(odf, labels, sections)
    if not odf or not GetODFFloat then return nil end
    sections = sections or WEAPON_VALUE_SECTIONS
    local best = nil
    for _, section in ipairs(sections) do
        for _, label in ipairs(labels) do
            local value, found = GetODFFloat(odf, section, label, 0.0)
            if HasOdfNumber(value, found) and (not best or value > best) then
                best = value
            end
        end
    end
    return best
end

local function ProbeIndexedFloatFromOdf(odf, sections, prefix, index)
    if not odf or not GetODFFloat then return nil end
    sections = sections or WEAPON_VALUE_SECTIONS
    local label = tostring(prefix or "") .. tostring(index or "")
    for _, section in ipairs(sections) do
        local value, found = GetODFFloat(odf, section, label, 0.0)
        if HasOdfNumber(value, found) then
            return value
        end
    end
    return nil
end

local function ProbeIndexedStringFromOdf(odf, sections, prefixes, index)
    if not odf or not GetODFString then return nil end
    sections = sections or WEAPON_VALUE_SECTIONS
    prefixes = prefixes or WEAPON_REFERENCE_LABELS
    for _, section in ipairs(sections) do
        for _, prefix in ipairs(prefixes) do
            local value, found = GetODFString(odf, section, tostring(prefix) .. tostring(index or ""), "")
            local cleaned = CleanString(value)
            if HasOdfString(cleaned, found) then
                return cleaned
            end
        end
    end
    return nil
end

local function GetResolvedWeaponRangeFromOdf(odf)
    if not odf then return nil end
    local range = ProbeMaxValueFromOdf(odf, WEAPON_RANGE_LABELS)
    if not range then
        range = ProbeBallisticRangeFromOdf(odf)
    end
    if not range then
        range = ProbeTravelRangeFromOdf(odf)
    end
    return range
end

local function GetResolvedWeaponRangeByName(odfName)
    if not odfName or odfName == "" or not OpenODF then return nil end
    local odf = OpenODF(odfName)
    if not odf then return nil end
    return GetResolvedWeaponRangeFromOdf(odf)
end

local function GetBurstCycleTime(shotDelay, salvoCount, salvoDelay)
    local count = math.max(1, math.floor((tonumber(salvoCount) or 1) + 0.5))
    local delay = math.max(0.0, tonumber(shotDelay) or 0.0)
    local intraBurst = math.max(0.0, tonumber(salvoDelay) or 0.0) * math.max(0, count - 1)
    local cycleTime = delay + intraBurst
    if cycleTime <= 0.001 then
        cycleTime = delay > 0.001 and delay or nil
    end
    return cycleTime, count
end

local function ProbeShotSpeedFromOdf(odf)
    return ProbeValueFromOdf(odf, { "shotSpeed" })
end

local function IsBallisticWeaponData(weaponOdf, ordOdf)
    local ballisticLabels = {
        grenade = true,
        bouncebomb = true,
        spraybomb = true,
        mortar = true,
    }

    local function MatchesBallisticLabel(odf)
        local classLabel = GetOdfClassLabel(odf)
        if not classLabel or classLabel == "" then return false end
        if ballisticLabels[classLabel] then return true end
        return string.find(classLabel, "mortar", 1, true) ~= nil
    end

    if MatchesBallisticLabel(weaponOdf) or MatchesBallisticLabel(ordOdf) then
        return true
    end

    if GetODFFloat and ordOdf then
        local value, found = GetODFFloat(ordOdf, "MortarClass", "shotSpeed", 0.0)
        if HasOdfNumber(value, found) then
            return true
        end
    end

    return false
end

local function ProbeDamageFromOdf(odf, sections)
    if not odf or not GetODFFloat then return nil end
    sections = sections or DAMAGE_SECTIONS

    for _, section in ipairs(sections) do
        local totalDamage = 0.0
        local foundAny = false
        for _, label in ipairs(DAMAGE_LABELS) do
            local value, found = GetODFFloat(odf, section, label, 0.0)
            if HasOdfNumber(value, found) then
                totalDamage = totalDamage + value
                foundAny = true
            end
        end
        if foundAny then
            return totalDamage
        end
    end

    return nil
end

local function ProbeExplosionProfilesFromOdf(odf)
    if not odf or not OpenODF then return nil end

    local profiles = {}
    local seen = {}
    for _, label in ipairs(EXPLOSION_REFERENCE_LABELS) do
        local explosionName = ProbeStringFromOdf(odf, { label }, WEAPON_VALUE_SECTIONS)
        if explosionName and explosionName ~= "" then
            local key = string.lower(explosionName)
            if not seen[key] then
                seen[key] = true
                local explosionOdf = OpenODF(explosionName)
                if explosionOdf then
                    local damage = ProbeDamageFromOdf(explosionOdf, { "ExplosionClass", nil })
                    local radius = ProbeMaxValueFromOdf(explosionOdf, EXPLOSION_RADIUS_LABELS, { "ExplosionClass", nil })
                    if damage or radius then
                        profiles[#profiles + 1] = {
                            name = explosionName,
                            damage = damage or 0.0,
                            radius = radius or 0.0,
                        }
                    end
                end
            end
        end
    end

    if #profiles <= 0 then
        return nil
    end

    return profiles
end

local function MergeExplosionProfiles(...)
    local merged = {}
    local seen = {}

    for i = 1, select("#", ...) do
        local profiles = select(i, ...)
        if profiles then
            for _, profile in ipairs(profiles) do
                local key = string.lower(CleanString(profile.name or ""))
                if key == "" then
                    key = tostring(#merged + 1)
                end
                if not seen[key] then
                    seen[key] = true
                    merged[#merged + 1] = profile
                end
            end
        end
    end

    if #merged <= 0 then
        return nil
    end

    return merged
end

local function BuildImpactDamageSummary(baseDamage, explosionProfiles)
    local summary = {
        damage = baseDamage,
        damageMin = baseDamage,
        damageMax = baseDamage,
        splashRadius = nil,
        splashRadiusMin = nil,
        splashRadiusMax = nil,
    }

    local totals = {}
    if type(baseDamage) == "number" and baseDamage > 0.0 then
        totals[#totals + 1] = baseDamage
    end

    if explosionProfiles then
        for _, profile in ipairs(explosionProfiles) do
            local radius = tonumber(profile.radius) or 0.0
            local damage = tonumber(profile.damage) or 0.0
            if radius > 0.0 then
                summary.splashRadiusMin = summary.splashRadiusMin and math.min(summary.splashRadiusMin, radius) or radius
                summary.splashRadiusMax = summary.splashRadiusMax and math.max(summary.splashRadiusMax, radius) or radius
            end
            if damage > 0.0 or (type(baseDamage) == "number" and baseDamage and baseDamage > 0.0) then
                totals[#totals + 1] = math.max(0.0, (baseDamage or 0.0) + damage)
            end
        end
    end

    if #totals > 0 then
        table.sort(totals)
        summary.damageMin = totals[1]
        summary.damageMax = totals[#totals]
        summary.damage = totals[#totals]
    end

    summary.splashRadius = summary.splashRadiusMax or summary.splashRadiusMin
    return summary
end

local function GetWeaponAmmoCostPerProjectile(weaponOdf, ordOdf)
    local value = ordOdf and ProbeValueFromOdf(ordOdf, { "ammoCost" }) or nil
    if value and value >= 0.0 then
        return value
    end

    value = weaponOdf and ProbeValueFromOdf(weaponOdf, { "ammoCost" }) or nil
    if value and value >= 0.0 then
        return value
    end

    return nil
end

local function GetWeaponReticleName(weaponOdfName, chargeIndex)
    if not weaponOdfName or weaponOdfName == "" or not OpenODF then return nil end
    PersistentConfig.WeaponReticleCache = PersistentConfig.WeaponReticleCache or {}

    local cacheKey = string.lower(weaponOdfName) .. ":" .. tostring(chargeIndex or 0)
    if PersistentConfig.WeaponReticleCache[cacheKey] ~= nil then
        return PersistentConfig.WeaponReticleCache[cacheKey]
    end

    local reticle = nil
    local weaponOdf = OpenODF(weaponOdfName)
    if weaponOdf then
        if chargeIndex and chargeIndex > 0 then
            reticle = ProbeIndexedStringFromOdf(weaponOdf, { "ChargeGunClass", "WeaponClass" }, { "wpnReticle" }, chargeIndex)
        end
        if not reticle then
            reticle = ProbeStringFromOdf(weaponOdf, { "wpnReticle" }, { "WeaponClass", "ChargeGunClass", "TargetingGunClass", nil })
        end
    end

    PersistentConfig.WeaponReticleCache[cacheKey] = reticle or false
    return reticle
end

local function BuildChargeWeaponLevels(weaponOdf)
    if not weaponOdf or not OpenODF then return nil end

    local classLabel = GetOdfClassLabel(weaponOdf)
    if classLabel ~= "chargegun" then return nil end

    local ordnanceCount = math.floor((ProbeValueFromOdf(weaponOdf, { "ordnanceCount" }, { "ChargeGunClass", "WeaponClass" }) or 0.0) + 0.5)
    if ordnanceCount <= 0 then return nil end

    local levels = {}
    for index = 1, ordnanceCount do
        local ordName = ProbeIndexedStringFromOdf(weaponOdf, { "ChargeGunClass", "WeaponClass" }, WEAPON_REFERENCE_LABELS, index)
        if ordName and ordName ~= "" and string.upper(ordName) ~= "NULL" then
            local ordOdf = OpenODF(ordName)
            if ordOdf then
                local perProjectileDamage = ProbeDamageFromOdf(ordOdf)
                local damageSummary = BuildImpactDamageSummary(perProjectileDamage, ProbeExplosionProfilesFromOdf(ordOdf))
                local shotDelay = ProbeIndexedFloatFromOdf(weaponOdf, { "ChargeGunClass", "WeaponClass" }, "shotDelay", index)
                local salvoCount = ProbeIndexedFloatFromOdf(weaponOdf, { "ChargeGunClass", "WeaponClass" }, "salvoCount", index) or 1.0
                local salvoDelay = ProbeIndexedFloatFromOdf(weaponOdf, { "ChargeGunClass", "WeaponClass" }, "salvoDelay", index) or 0.0
                local cycleTime, shotCount = GetBurstCycleTime(shotDelay, salvoCount, salvoDelay)
                local damageMin = damageSummary.damageMin and (damageSummary.damageMin * shotCount) or nil
                local damageMax = damageSummary.damageMax and (damageSummary.damageMax * shotCount) or nil
                local totalDamage = damageMax or damageMin
                local ammoCostPerProjectile = GetWeaponAmmoCostPerProjectile(nil, ordOdf)
                local ammoCost = ammoCostPerProjectile and (ammoCostPerProjectile * shotCount) or nil

                table.insert(levels, {
                    chargeIndex = index,
                    ordName = ordName,
                    range = GetResolvedWeaponRangeFromOdf(ordOdf),
                    perProjectileDamage = damageSummary.damage,
                    damage = totalDamage,
                    damageMin = damageMin,
                    damageMax = damageMax,
                    shotDelay = shotDelay,
                    salvoCount = shotCount,
                    salvoDelay = salvoDelay,
                    cycleTime = cycleTime,
                    dps = (totalDamage and cycleTime and cycleTime > 0.001) and (totalDamage / cycleTime) or nil,
                    dpsMin = (damageMin and cycleTime and cycleTime > 0.001) and (damageMin / cycleTime) or nil,
                    dpsMax = (damageMax and cycleTime and cycleTime > 0.001) and (damageMax / cycleTime) or nil,
                    shotSpeed = ProbeShotSpeedFromOdf(ordOdf),
                    ballistic = IsBallisticWeaponData(weaponOdf, ordOdf),
                    ammoCostPerProjectile = ammoCostPerProjectile,
                    ammoCost = ammoCost,
                    ammoCostMin = ammoCost,
                    ammoCostMax = ammoCost,
                    splashRadius = damageSummary.splashRadius,
                    splashRadiusMin = damageSummary.splashRadiusMin,
                    splashRadiusMax = damageSummary.splashRadiusMax,
                })
            end
        end
    end

    if #levels <= 0 then
        return nil
    end

    return levels
end

local function GetVehicleDisplayName(h)
    if not IsValid(h) then return nil end

    local odfName = CleanString((type(GetOdf) == "function" and GetOdf(h)) or "")
    if odfName ~= "" then
        PersistentConfig.UnitNameCache = PersistentConfig.UnitNameCache or {}
        local key = string.lower(odfName)
        if PersistentConfig.UnitNameCache[key] ~= nil then
            return PersistentConfig.UnitNameCache[key]
        end

        if OpenODF and GetODFString then
            local odf = OpenODF(odfName)
            if odf then
                local value, found = GetODFString(odf, "GameObjectClass", "unitName", "")
                local cleaned = CleanString(value)
                if HasOdfString(cleaned, found) and string.upper(cleaned) ~= "NULL" then
                    PersistentConfig.UnitNameCache[key] = cleaned
                    return cleaned
                end
            end
        end

        PersistentConfig.UnitNameCache[key] = odfName
        return odfName
    end

    local classLabel = CleanString((type(GetClassLabel) == "function" and GetClassLabel(h)) or "")
    if classLabel ~= "" then
        return classLabel
    end

    return "Unknown"
end

local function GetWeaponRangeMeters(weaponOdfName)
    if not weaponOdfName or weaponOdfName == "" then return nil end
    PersistentConfig.WeaponRangeCache = PersistentConfig.WeaponRangeCache or {}

    local key = string.lower(weaponOdfName)
    if PersistentConfig.WeaponRangeCache[key] ~= nil then
        return PersistentConfig.WeaponRangeCache[key]
    end

    local range = nil
    if OpenODF then
        local weaponOdf = OpenODF(weaponOdfName)
        if weaponOdf then
            range = ProbeMaxValueFromOdf(weaponOdf, WEAPON_RANGE_LABELS)
            if not range then
                local chargeLevels = BuildChargeWeaponLevels(weaponOdf)
                if chargeLevels and #chargeLevels > 0 then
                    for _, level in ipairs(chargeLevels) do
                        if level.range and (not range or level.range > range) then
                            range = level.range
                        end
                    end
                end
            end
            if not range then
                local ordName = ResolveOrdnanceName(weaponOdf)
                if ordName then
                    range = GetResolvedWeaponRangeByName(ordName)
                end
            end
        end
    end

    PersistentConfig.WeaponRangeCache[key] = range
    return range
end

local function GetWeaponStats(weaponOdfName)
    if not weaponOdfName or weaponOdfName == "" then return nil end
    PersistentConfig.WeaponDataCache = PersistentConfig.WeaponDataCache or {}

    local key = string.lower(weaponOdfName)
    if PersistentConfig.WeaponDataCache[key] ~= nil then
        return PersistentConfig.WeaponDataCache[key]
    end

    local stats = {
        displayName = GetWeaponDisplayName(weaponOdfName) or weaponOdfName,
        range = GetWeaponRangeMeters(weaponOdfName),
        rangeMin = nil,
        rangeMax = nil,
        damage = nil,
        damageMin = nil,
        damageMax = nil,
        dps = nil,
        dpsMin = nil,
        dpsMax = nil,
        ammoCost = nil,
        ammoCostMin = nil,
        ammoCostMax = nil,
        shotDelay = nil,
        shotSpeed = nil,
        ballistic = false,
        salvoCount = 1,
        salvoDelay = 0.0,
        splashRadius = nil,
        splashRadiusMin = nil,
        splashRadiusMax = nil,
        chargeLevels = nil,
    }

    if OpenODF then
        local weaponOdf = OpenODF(weaponOdfName)
        local ordOdf = nil
        if weaponOdf then
            local chargeLevels = BuildChargeWeaponLevels(weaponOdf)
            if chargeLevels and #chargeLevels > 0 then
                stats.chargeLevels = chargeLevels
                for _, level in ipairs(chargeLevels) do
                    if level.range then
                        stats.rangeMin = stats.rangeMin and math.min(stats.rangeMin, level.range) or level.range
                        stats.rangeMax = stats.rangeMax and math.max(stats.rangeMax, level.range) or level.range
                    end
                    local levelDamageMin = level.damageMin or level.damage
                    local levelDamageMax = level.damageMax or level.damage
                    if levelDamageMin then
                        stats.damageMin = stats.damageMin and math.min(stats.damageMin, levelDamageMin) or levelDamageMin
                    end
                    if levelDamageMax then
                        stats.damageMax = stats.damageMax and math.max(stats.damageMax, levelDamageMax) or levelDamageMax
                    end
                    local levelDpsMin = level.dpsMin or level.dps
                    local levelDpsMax = level.dpsMax or level.dps
                    if levelDpsMin then
                        stats.dpsMin = stats.dpsMin and math.min(stats.dpsMin, levelDpsMin) or levelDpsMin
                    end
                    if levelDpsMax then
                        stats.dpsMax = stats.dpsMax and math.max(stats.dpsMax, levelDpsMax) or levelDpsMax
                    end
                    if level.shotSpeed and (not stats.shotSpeed or level.shotSpeed > stats.shotSpeed) then
                        stats.shotSpeed = level.shotSpeed
                    end
                    local levelAmmoMin = level.ammoCostMin or level.ammoCost
                    local levelAmmoMax = level.ammoCostMax or level.ammoCost
                    if levelAmmoMin ~= nil then
                        stats.ammoCostMin = stats.ammoCostMin and math.min(stats.ammoCostMin, levelAmmoMin) or levelAmmoMin
                    end
                    if levelAmmoMax ~= nil then
                        stats.ammoCostMax = stats.ammoCostMax and math.max(stats.ammoCostMax, levelAmmoMax) or levelAmmoMax
                    end
                    local splashMin = level.splashRadiusMin or level.splashRadius
                    local splashMax = level.splashRadiusMax or level.splashRadius
                    if splashMin then
                        stats.splashRadiusMin = stats.splashRadiusMin and math.min(stats.splashRadiusMin, splashMin) or splashMin
                    end
                    if splashMax then
                        stats.splashRadiusMax = stats.splashRadiusMax and math.max(stats.splashRadiusMax, splashMax) or splashMax
                    end
                    stats.ballistic = stats.ballistic or level.ballistic
                end
                stats.range = stats.rangeMax or stats.rangeMin or stats.range
                stats.damage = stats.damageMax or stats.damageMin
                stats.dps = stats.dpsMax or stats.dpsMin
                stats.ammoCost = stats.ammoCostMax or stats.ammoCostMin
                stats.splashRadius = stats.splashRadiusMax or stats.splashRadiusMin
                PersistentConfig.WeaponDataCache[key] = stats
                return stats
            end

            local ordName = ResolveOrdnanceName(weaponOdf)
            if ordName then
                ordOdf = OpenODF(ordName)
            end

            stats.shotDelay = ProbeValueFromOdf(weaponOdf, WEAPON_DELAY_LABELS)
            stats.salvoCount = ProbeValueFromOdf(weaponOdf, { "salvoCount" }) or 1.0
            stats.salvoDelay = ProbeValueFromOdf(weaponOdf, { "salvoDelay" }) or 0.0
            stats.damage = ProbeDamageFromOdf(weaponOdf)
            stats.ammoCost = GetWeaponAmmoCostPerProjectile(weaponOdf, nil)
            stats.shotSpeed = ProbeShotSpeedFromOdf(weaponOdf)
        end

        if ordOdf then
            if not stats.damage then
                stats.damage = ProbeDamageFromOdf(ordOdf)
            end
            if stats.ammoCost == nil then
                stats.ammoCost = GetWeaponAmmoCostPerProjectile(weaponOdf, ordOdf)
            end
            if not stats.shotDelay then
                stats.shotDelay = ProbeValueFromOdf(ordOdf, WEAPON_DELAY_LABELS)
            end
            if stats.salvoCount <= 1.0 then
                stats.salvoCount = ProbeValueFromOdf(ordOdf, { "salvoCount" }) or stats.salvoCount
            end
            if stats.salvoDelay <= 0.0 then
                stats.salvoDelay = ProbeValueFromOdf(ordOdf, { "salvoDelay" }) or stats.salvoDelay
            end
            if not stats.shotSpeed then
                stats.shotSpeed = ProbeShotSpeedFromOdf(ordOdf)
            end
        end

        stats.ballistic = IsBallisticWeaponData(weaponOdf, ordOdf)

        local damageSummary = BuildImpactDamageSummary(stats.damage,
            MergeExplosionProfiles(ProbeExplosionProfilesFromOdf(weaponOdf), ProbeExplosionProfilesFromOdf(ordOdf)))
        stats.damage = damageSummary.damage
        stats.damageMin = damageSummary.damageMin
        stats.damageMax = damageSummary.damageMax
        stats.splashRadius = damageSummary.splashRadius
        stats.splashRadiusMin = damageSummary.splashRadiusMin
        stats.splashRadiusMax = damageSummary.splashRadiusMax
    end

    local cycleTime, shotCount = GetBurstCycleTime(stats.shotDelay, stats.salvoCount, stats.salvoDelay)
    if stats.damageMin or stats.damageMax or stats.damage then
        stats.damageMin = (stats.damageMin or stats.damage) and ((stats.damageMin or stats.damage) * shotCount) or nil
        stats.damageMax = (stats.damageMax or stats.damage) and ((stats.damageMax or stats.damage) * shotCount) or nil
        stats.damage = stats.damageMax or stats.damageMin
    end
    if stats.range then
        stats.rangeMin = stats.range
        stats.rangeMax = stats.range
    end
    if stats.ammoCost ~= nil then
        local totalAmmoCost = stats.ammoCost * shotCount
        stats.ammoCost = totalAmmoCost
        stats.ammoCostMin = totalAmmoCost
        stats.ammoCostMax = totalAmmoCost
    end
    if cycleTime and cycleTime > 0.001 then
        if stats.damageMin then
            stats.dpsMin = stats.damageMin / cycleTime
        end
        if stats.damageMax then
            stats.dpsMax = stats.damageMax / cycleTime
        end
        stats.dps = stats.dpsMax or stats.dpsMin
    end

    PersistentConfig.WeaponDataCache[key] = stats
    return stats
end

local function FindChargeLevelForWeapon(weaponStats, chargeIndex, ordName)
    local levels = weaponStats and weaponStats.chargeLevels or nil
    if not levels or #levels <= 0 then return nil end

    local ordKey = string.lower(CleanString(ordName))
    for _, level in ipairs(levels) do
        if chargeIndex and (level.chargeIndex == chargeIndex) then
            return level
        end
        if ordKey ~= "" and string.lower(CleanString(level.ordName)) == ordKey then
            return level
        end
    end

    return nil
end

local function GetDisplayedWeaponStats(player, weaponOdfName, weaponStats)
    if not weaponStats or not weaponStats.chargeLevels or not IsValid(player) or player ~= GetPlayerHandle() then
        return weaponStats
    end

    local state = PersistentConfig.PlayerChargeWeaponState
    if not state then
        return weaponStats
    end

    if string.lower(CleanString(state.weaponOdf)) ~= string.lower(CleanString(weaponOdfName)) then
        return weaponStats
    end

    local level = FindChargeLevelForWeapon(weaponStats, state.chargeIndex, state.ordName)
    if not level then
        return weaponStats
    end

    return {
        displayName = weaponStats.displayName,
        range = level.range or weaponStats.range,
        rangeMin = level.range or weaponStats.rangeMin,
        rangeMax = level.range or weaponStats.rangeMax,
        damage = level.damage or weaponStats.damage,
        damageMin = level.damageMin or level.damage or weaponStats.damageMin,
        damageMax = level.damageMax or level.damage or weaponStats.damageMax,
        dps = level.dpsMax or level.dps or weaponStats.dps,
        dpsMin = level.dpsMin or level.dps or weaponStats.dpsMin,
        dpsMax = level.dpsMax or level.dps or weaponStats.dpsMax,
        ammoCost = level.ammoCost or weaponStats.ammoCost,
        ammoCostMin = level.ammoCostMin or level.ammoCost or weaponStats.ammoCostMin,
        ammoCostMax = level.ammoCostMax or level.ammoCost or weaponStats.ammoCostMax,
        shotDelay = level.shotDelay or weaponStats.shotDelay,
        shotSpeed = level.shotSpeed or weaponStats.shotSpeed,
        ballistic = (level.ballistic == nil) and weaponStats.ballistic or level.ballistic,
        salvoCount = level.salvoCount or weaponStats.salvoCount,
        salvoDelay = level.salvoDelay or weaponStats.salvoDelay,
        splashRadius = level.splashRadius or weaponStats.splashRadius,
        splashRadiusMin = level.splashRadiusMin or level.splashRadius or weaponStats.splashRadiusMin,
        splashRadiusMax = level.splashRadiusMax or level.splashRadius or weaponStats.splashRadiusMax,
        chargeLevels = weaponStats.chargeLevels,
        currentChargeLevel = level.chargeIndex,
        currentChargeOrdName = level.ordName,
    }
end

local function UpdatePlayerChargeWeaponState(odf, shooter)
    if not IsValid(shooter) or shooter ~= GetPlayerHandle() then return end

    local ordKey = string.lower(CleanString(odf))
    if ordKey == "" then return end

    for slot = 0, 4 do
        local weapon = CleanString(GetWeaponClass(shooter, slot))
        if weapon ~= "" then
            local weaponStats = GetWeaponStats(weapon)
            local level = FindChargeLevelForWeapon(weaponStats, nil, ordKey)
            if level then
                PersistentConfig.PlayerChargeWeaponState = {
                    weaponOdf = string.lower(CleanString(weapon)),
                    chargeIndex = level.chargeIndex,
                    ordName = string.lower(CleanString(level.ordName or ordKey)),
                    slot = slot,
                    updatedAt = GetTime(),
                }
                return
            end
        end
    end
end

local function GetHorizontalDistanceBetweenHandles(a, b)
    if not IsValid(a) or not IsValid(b) or type(GetPosition) ~= "function" then
        return nil
    end
    local aPos = GetPosition(a)
    local bPos = GetPosition(b)
    if not aPos or not bPos then
        return nil
    end
    local dx = (bPos.x or 0.0) - (aPos.x or 0.0)
    local dz = (bPos.z or 0.0) - (aPos.z or 0.0)
    return math.sqrt((dx * dx) + (dz * dz))
end

local function GetHorizontalDistanceBetweenPositions(aPos, bPos)
    if not aPos or not bPos then
        return nil
    end
    local dx = (bPos.x or 0.0) - (aPos.x or 0.0)
    local dz = (bPos.z or 0.0) - (aPos.z or 0.0)
    return math.sqrt((dx * dx) + (dz * dz))
end

local function GetEffectiveWeaponRangeMeters(weaponStats, shooterPos, targetPos)
    if not weaponStats or not weaponStats.range then return nil end
    if not weaponStats.ballistic or not weaponStats.shotSpeed or weaponStats.shotSpeed <= 0.0 then
        return weaponStats.range
    end
    if not shooterPos or not targetPos then
        return weaponStats.range
    end

    local coeff = GetBallisticCoeff()
    if coeff <= 0.0 then
        return weaponStats.range
    end

    local deltaY = (shooterPos.y or 0.0) - (targetPos.y or 0.0)
    local discriminant = (weaponStats.shotSpeed * weaponStats.shotSpeed) + (4.0 * coeff * deltaY)
    if discriminant <= 0.0 then
        return 0.0
    end

    return (weaponStats.shotSpeed * math.sqrt(discriminant)) / (2.0 * coeff)
end

GetPlayerTeamNum = function()
    local player = GetPlayerHandle()
    if IsValid(player) and type(GetTeamNum) == "function" then
        local team = GetTeamNum(player)
        if type(team) == "number" then
            return team
        end
    end
    return 1
end

local function GetProducerHandleForKind(kindIndex, team)
    local kind = PresetProducerKinds[kindIndex]
    if not kind or type(kind.getter) ~= "function" then return nil end
    local ok, handle = pcall(kind.getter, team)
    if ok and IsValid(handle) then
        return handle
    end
    return nil
end

local function GetRadarSizeScaleSetting()
    return ClampRange(PersistentConfig.Settings.RadarSizeScale, PersistentConfig.RadarUi.min,
        PersistentConfig.RadarUi.max, PersistentConfig.DefaultSettings.RadarSizeScale)
end

local function GetAppliedRadarSizeScaleSetting()
    local requestedScale = GetRadarSizeScaleSetting()
    if requestedScale > 1.01 then
        return requestedScale
    end

    -- The stock radar background art only lines up cleanly at the built-in small/medium/full sizes.
    -- Snap reduced scales to the nearest supported shrink preset so the sweep and frame stay aligned.
    local supportedScales = {
        139.0 / 223.0,
        179.0 / 223.0,
        1.0,
    }
    local bestScale = supportedScales[#supportedScales]
    local bestDiff = math.abs(bestScale - requestedScale)
    for _, scale in ipairs(supportedScales) do
        local diff = math.abs(scale - requestedScale)
        if diff < bestDiff then
            bestDiff = diff
            bestScale = scale
        end
    end
    return bestScale
end

local function ApplyLegacyScrapPilotHudTopLeft()
    if not exu then
        return false
    end

    if type(exu.SetScrapHudTopLeft) == "function" and type(exu.SetPilotHudTopLeft) == "function" then
        local screenW, screenH, uiScale = PersistentConfig._GetUiResolutionMetrics()
        uiScale = math.max(tonumber(uiScale) or 1, 1)

        -- Keep the legacy counter aligned to the stock command menu footprint, which scales with the HUD rather than
        -- the current screen resolution. This prevents the text from drifting back into the menu at higher HUD scales.
        local commandMenuLeft = math.floor(8 * uiScale)
        local commandMenuTop = math.floor(10 * uiScale)
        local estimatedCommandMenuWidth = math.floor(171 * uiScale)
        local commandMenuGap = math.floor(10 * uiScale)
        local anchorX = commandMenuLeft + estimatedCommandMenuWidth + commandMenuGap
        local scrapY = commandMenuTop + math.floor(2 * uiScale)
        local pilotY = scrapY + math.floor(48 * uiScale)

        anchorX = ClampRange(anchorX, 0, math.max(0, screenW - math.floor(96 * uiScale)), anchorX)
        scrapY = ClampRange(scrapY, 0, math.max(0, screenH - math.floor(80 * uiScale)), scrapY)
        pilotY = ClampRange(pilotY, 0, math.max(0, screenH - math.floor(32 * uiScale)), pilotY)

        local scrapOk, scrapResult = pcall(exu.SetScrapHudTopLeft, anchorX, scrapY)
        local pilotOk, pilotResult = pcall(exu.SetPilotHudTopLeft, anchorX, pilotY)
        return scrapOk and pilotOk and scrapResult ~= false and pilotResult ~= false
    end

    if type(exu.SetScrapPilotHudTopLeft) == "function" then
        local ok, result = pcall(exu.SetScrapPilotHudTopLeft, 500, 22)
        return ok and result ~= false
    end

    if type(exu.SetScrapPilotHudOffset) == "function" then
        local ok, result = pcall(exu.SetScrapPilotHudOffset, -400, -220)
        return ok and result ~= false
    end

    return false
end

local StockScrapPilotHudSpriteNames = {
    "scrap_panel",
    "pilot_panel",
    "sscrap_panel",
    "spilot_panel",
    "fscrap_panel",
    "fpilot_panel",
}

local function SetStockScrapPilotHudSpritesVisible(visible)
    if not exu or type(exu.SetHudSpriteVisible) ~= "function" then
        return false
    end

    local anySucceeded = false
    for _, spriteName in ipairs(StockScrapPilotHudSpriteNames) do
        local ok, result = pcall(exu.SetHudSpriteVisible, spriteName, visible)
        if ok and result ~= false then
            anySucceeded = true
        end
    end
    return anySucceeded
end

function PersistentConfig._SyncLightingMode(force)
    if not exu then
        return false
    end

    local preset = PersistentConfig._GetLightingModePreset()
    local targetMode = (preset and preset.mode) or "default"
    if not force and PersistentConfig._AppliedLightingMode == targetMode then
        return false
    end

    local applied = false
    if type(exu.SetLightingMode) == "function" then
        local ok, result = pcall(exu.SetLightingMode, targetMode)
        applied = ok and result ~= false
    end
    if not applied and type(exu.SetRetroLightingMode) == "function" then
        local ok, result = pcall(exu.SetRetroLightingMode, targetMode == "retro")
        applied = ok and result ~= false
    end

    if applied then
        PersistentConfig._AppliedLightingMode = targetMode
        PersistentConfig.Settings.RetroLighting = targetMode == "retro"
    else
        PersistentConfig._AppliedLightingMode = nil
    end
    return applied
end

PersistentConfig._SyncRetroLighting = PersistentConfig._SyncLightingMode

function PersistentConfig._RequestLightingModeResync(duration)
    local now = (type(GetTime) == "function" and GetTime()) or 0.0
    local window = tonumber(duration) or PersistentConfig.RetroLightingIntervals.stabilizeDuration

    InputState.lightingModeSyncPending = true
    InputState.nextRetroLightingCheck = 0.0
    if window > 0 then
        InputState.nextRetroLightingStabilizeUntil = math.max(
            tonumber(InputState.nextRetroLightingStabilizeUntil) or 0.0,
            now + window
        )
    end
end

PersistentConfig._RequestRetroLightingResync = PersistentConfig._RequestLightingModeResync

function PersistentConfig._CancelLightingModeResync()
    InputState.lightingModeSyncPending = false
    InputState.nextRetroLightingCheck = 0.0
    InputState.nextRetroLightingStabilizeUntil = 0.0
end

function PersistentConfig._RequestRadarScaleResync()
    InputState.radarScaleSyncPending = true
    InputState.nextRadarScaleCheck = 0.0
end

function PersistentConfig._CancelRadarScaleResync()
    InputState.radarScaleSyncPending = false
    InputState.nextRadarScaleCheck = 0.0
end

function PersistentConfig._SyncRadarSizeScale(force)
    if not exu or type(exu.SetRadarSizeScale) ~= "function" then
        return false
    end

    local targetScale = GetAppliedRadarSizeScaleSetting()
    if not force and type(exu.GetRadarSizeScale) == "function" then
        local ok, currentScale = pcall(exu.GetRadarSizeScale)
        if ok and type(currentScale) == "number" and math.abs(currentScale - targetScale) < 0.01 then
            return false
        end
    end

    print(string.format("PersistentConfig: _SyncRadarSizeScale begin force=%s requested=%.3f applied=%.3f",
        tostring(force), tonumber(PersistentConfig.Settings.RadarSizeScale) or -1, targetScale))
    local callOk, result = pcall(exu.SetRadarSizeScale, targetScale)
    local ok = callOk and result ~= false
    print(string.format("PersistentConfig: _SyncRadarSizeScale result ok=%s callOk=%s result=%s",
        tostring(ok), tostring(callOk), tostring(result)))
    if ok and ClampIndex(PersistentConfig.Settings.ScrapPilotHudLayout, 1, #ScrapPilotHudLayouts, 2) == 2 then
        -- Radar refreshes can snap the stock scrap/pilot counters and legacy HUD art back to their default anchor.
        print("PersistentConfig: _SyncRadarSizeScale reapplying legacy scrap/pilot HUD layout")
        PersistentConfig.ApplyScrapPilotHudLayout()
    end
    return ok
end

local function RefreshWorldTeamNationCache(force)
    local cache = PersistentConfig.TeamNationCache or {
        nextRefreshAt = 0.0,
        namesByTeam = {},
    }
    PersistentConfig.TeamNationCache = cache

    local now = (type(GetTime) == "function" and GetTime()) or 0.0
    if not force and now < (cache.nextRefreshAt or 0.0) then
        return cache.namesByTeam
    end

    local namesByTeam = {}
    if type(AllObjects) == "function" and type(GetTeamNum) == "function" and type(GetNation) == "function" then
        for h in AllObjects() do
            if IsValid(h) then
                local teamNum = tonumber(GetTeamNum(h))
                if teamNum and teamNum >= 1 and teamNum <= 15 and not namesByTeam[teamNum] then
                    local nation = string.lower(CleanString(GetNation(h)))
                    if nation ~= "" then
                        namesByTeam[teamNum] = nation
                    end
                end
            end
        end
    end

    cache.namesByTeam = namesByTeam
    cache.nextRefreshAt = now + 2.0
    return namesByTeam
end

local function GetTeamNationName(team)
    local player = GetPlayerHandle()
    if team == GetPlayerTeamNum() and IsValid(player) then
        return string.lower(CleanString(GetNation(player)))
    end

    local getters = { GetRecyclerHandle, GetFactoryHandle, GetArmoryHandle, GetConstructorHandle }
    for _, getter in ipairs(getters) do
        if type(getter) == "function" then
            local ok, handle = pcall(getter, team)
            if ok and IsValid(handle) then
                local nation = string.lower(CleanString(GetNation(handle)))
                if nation ~= "" then
                    return nation
                end
            end
        end
    end

    local namesByTeam = RefreshWorldTeamNationCache(false)
    return namesByTeam[team]
end

local function GetFactionFlameColorForTeam(team)
    if type(GetNation) ~= "function" then
        return "default"
    end

    local nation = GetTeamNationName(team)
    if not nation or nation == "" then
        return "default"
    end

    local code = string.sub(nation, 1, 1)
    if code == "a" or code == "b" then
        return "blue"
    end
    if code == "c" then
        return "green"
    end
    if code == "s" then
        return "red"
    end

    return "default"
end

function PersistentConfig._ApplyDynamicFactionFlameColors()
    if not exu or type(exu.SetTeamEngineFlameColor) ~= "function" or type(exu.ClearTeamEngineFlameColor) ~= "function" then
        return false
    end

    for team = 1, 15 do
        if PersistentConfig.Settings.DynamicFactionFlameColors then
            local color = GetFactionFlameColorForTeam(team)
            if color == "default" then
                pcall(exu.ClearTeamEngineFlameColor, team)
            else
                pcall(exu.SetTeamEngineFlameColor, team, color)
            end
        else
            pcall(exu.ClearTeamEngineFlameColor, team)
        end
    end

    return true
end

local function GetHardpointCategory(hardpointName)
    local hardpoint = string.upper(CleanString(hardpointName or ""))
    if string.sub(hardpoint, 1, 2) == "GC" then return "cannon" end
    if string.sub(hardpoint, 1, 2) == "GR" then return "rocket" end
    if string.sub(hardpoint, 1, 2) == "GM" then return "mortar" end
    if string.sub(hardpoint, 1, 2) == "GS" then return "special" end
    return nil
end

local function GetHardpointCategoryLabel(category)
    local labels = {
        cannon = "CANNON",
        rocket = "ROCKET",
        mortar = "MORTAR",
        special = "SPECIAL",
    }
    return labels[category] or string.upper(CleanString(category or "SLOT"))
end

local function ReadIndexedOdfStrings(odf, section, prefix, maxCount)
    local items = {}
    if not odf or not GetODFString then return items end
    local misses = 0
    maxCount = maxCount or 24

    for i = 1, maxCount do
        local value, found = GetODFString(odf, section, prefix .. tostring(i), "")
        local cleaned = CleanString(value)
        if HasOdfString(cleaned, found) then
            table.insert(items, cleaned)
            misses = 0
        else
            misses = misses + 1
            if misses >= 4 then
                break
            end
        end
    end

    return items
end

local function GetUnitBuildEntry(unitOdfName)
    if not unitOdfName or unitOdfName == "" then return nil end
    PersistentConfig.UnitBuildCache = PersistentConfig.UnitBuildCache or {}
    local key = string.lower(unitOdfName)
    if PersistentConfig.UnitBuildCache[key] ~= nil then
        return PersistentConfig.UnitBuildCache[key]
    end

    local entry = nil
    if OpenODF then
        local odf = OpenODF(unitOdfName)
        if odf then
            local displayName = unitOdfName
            local unitName, unitNameFound = GetODFString(odf, "GameObjectClass", "unitName", "")
            if HasOdfString(unitName, unitNameFound) and string.upper(CleanString(unitName)) ~= "NULL" then
                displayName = CleanString(unitName)
            end

            local scrapCost, costFound = GetODFFloat(odf, "GameObjectClass", "scrapCost", 0.0)
            local pilotCost = 0.0
            if GetODFInt then
                pilotCost = GetODFInt(odf, "GameObjectClass", "pilotCost", 0) or 0
            end
            local slots = {}
            for slotIndex = 1, 5 do
                local hardpoint, hardpointFound = GetODFString(odf, "GameObjectClass", "weaponHard" .. tostring(slotIndex), "")
                local weaponName, _ = GetODFString(odf, "GameObjectClass", "weaponName" .. tostring(slotIndex), "")
                local cleanedHardpoint = CleanString(hardpoint)
                if HasOdfString(cleanedHardpoint, hardpointFound) then
                    local stockWeapon = CleanString(weaponName)
                    table.insert(slots, {
                        slot = slotIndex - 1,
                        slotIndex = slotIndex,
                        hardpoint = cleanedHardpoint,
                        category = GetHardpointCategory(cleanedHardpoint),
                        stockWeapon = stockWeapon,
                        stockDisplay = (stockWeapon ~= "" and (GetWeaponDisplayName(stockWeapon) or stockWeapon)) or "EMPTY",
                    })
                end
            end

            entry = {
                odf = unitOdfName,
                key = key,
                displayName = displayName or unitOdfName,
                scrapCost = tonumber(scrapCost) or 0.0,
                pilotCost = tonumber(pilotCost) or 0.0,
                slots = slots,
            }
        end
    end

    PersistentConfig.UnitBuildCache[key] = entry
    return entry
end

local function GetProducerBuildEntries(handle)
    if not IsValid(handle) then return {} end
    PersistentConfig.ProducerBuildCache = PersistentConfig.ProducerBuildCache or {}
    local odfName = CleanString((type(GetOdf) == "function" and GetOdf(handle)) or "")
    local key = string.lower(odfName)
    if key ~= "" and PersistentConfig.ProducerBuildCache[key] ~= nil then
        return PersistentConfig.ProducerBuildCache[key]
    end

    local entries = {}
    if odfName ~= "" and OpenODF then
        local odf = OpenODF(odfName)
        if odf then
            for _, unitOdfName in ipairs(ReadIndexedOdfStrings(odf, "ProducerClass", "buildItem", 24)) do
                local entry = GetUnitBuildEntry(unitOdfName)
                if entry then
                    table.insert(entries, entry)
                end
            end
        end
    end

    if key ~= "" then
        PersistentConfig.ProducerBuildCache[key] = entries
    end
    return entries
end

local function ResolveWeaponPowerupInfo(powerupOdfName)
    if not powerupOdfName or powerupOdfName == "" then return nil end
    PersistentConfig.WeaponPowerupCache = PersistentConfig.WeaponPowerupCache or {}
    local key = string.lower(powerupOdfName)
    if PersistentConfig.WeaponPowerupCache[key] ~= nil then
        return PersistentConfig.WeaponPowerupCache[key]
    end

    local info = nil
    if OpenODF then
        local odf = OpenODF(powerupOdfName)
        if odf then
            local weaponName, found = GetODFString(odf, "WeaponPowerupClass", "weaponName", "")
            local cleanedWeapon = CleanString(weaponName)
            if HasOdfString(cleanedWeapon, found) then
                local scrapCost, costFound = GetODFFloat(odf, "GameObjectClass", "scrapCost", 0.0)
                info = {
                    powerupOdf = powerupOdfName,
                    powerupKey = key,
                    weaponName = cleanedWeapon,
                    displayName = GetWeaponDisplayName(cleanedWeapon) or cleanedWeapon,
                    scrapCost = tonumber(scrapCost) or 0.0,
                }
            end
        end
    end

    PersistentConfig.WeaponPowerupCache[key] = info
    return info
end

local function GetArmoryWeaponOptions(handle)
    if not IsValid(handle) then return nil end
    PersistentConfig.ArmoryOptionCache = PersistentConfig.ArmoryOptionCache or {}
    local odfName = CleanString((type(GetOdf) == "function" and GetOdf(handle)) or "")
    local key = string.lower(odfName)
    if key ~= "" and PersistentConfig.ArmoryOptionCache[key] ~= nil then
        return PersistentConfig.ArmoryOptionCache[key]
    end

    local categories = {
        cannon = { prefix = "cannonItem", options = {} },
        rocket = { prefix = "rocketItem", options = {} },
        mortar = { prefix = "mortarItem", options = {} },
        special = { prefix = "specialItem", options = {} },
    }

    if odfName ~= "" and OpenODF then
        local odf = OpenODF(odfName)
        if odf then
            for category, data in pairs(categories) do
                table.insert(data.options, {
                    powerupOdf = "",
                    powerupKey = "",
                    weaponName = "",
                    displayName = "STOCK",
                    scrapCost = 0.0,
                })
                for _, powerupOdfName in ipairs(ReadIndexedOdfStrings(odf, "ArmoryClass", data.prefix, 24)) do
                    local info = ResolveWeaponPowerupInfo(powerupOdfName)
                    if info then
                        table.insert(data.options, info)
                    end
                end
            end
        end
    end

    if key ~= "" then
        PersistentConfig.ArmoryOptionCache[key] = categories
    end
    return categories
end

local function GetUnitPresetRecord(unitOdfName)
    local key = string.lower(CleanString(unitOdfName or ""))
    if key == "" then return nil end
    PersistentConfig.UnitPresets[key] = PersistentConfig.UnitPresets[key] or {}
    return PersistentConfig.UnitPresets[key]
end

local function FindWeaponOptionIndex(options, powerupOdfName)
    local wanted = string.lower(CleanString(powerupOdfName or ""))
    if wanted == "" then return 1 end
    for index, option in ipairs(options or {}) do
        if string.lower(CleanString(option.powerupOdf or "")) == wanted then
            return index
        end
    end
    return 1
end

local function GetStockWeaponUpgradeCost(slotInfo, options)
    if not slotInfo or not slotInfo.stockWeapon or slotInfo.stockWeapon == "" then
        return 0.0
    end
    local wanted = string.lower(slotInfo.stockWeapon)
    for _, option in ipairs(options or {}) do
        if string.lower(CleanString(option.weaponName or "")) == wanted then
            return option.scrapCost or 0.0
        end
    end
    return 0.0
end

local function GetPresetSurchargeForEntry(entry)
    if not entry then return 0.0 end
    local team = GetPlayerTeamNum()
    local armory = GetArmoryHandle(team)
    local armoryOptions = GetArmoryWeaponOptions(armory)
    if not armoryOptions then return 0.0 end

    local preset = PersistentConfig.UnitPresets[string.lower(entry.odf or "")]
    if not preset then return 0.0 end

    local total = 0.0
    local manualExtras = {}
    local mortarUpgrades = 0
    local function IsDifferentWeapon(slotInfo, selectedOption)
        if not slotInfo or not selectedOption or not selectedOption.weaponName or selectedOption.weaponName == "" then
            return false
        end
        local selected = string.lower(CleanString(selectedOption.weaponName))
        local stock = string.lower(CleanString(slotInfo.stockWeapon or ""))
        if stock == "" then
            return true
        end
        return selected ~= stock
    end

    for _, slotInfo in ipairs(entry.slots or {}) do
        local selectedPowerup = preset[slotInfo.slotIndex]
        if selectedPowerup and selectedPowerup ~= "" then
            local options = armoryOptions[slotInfo.category] and armoryOptions[slotInfo.category].options or {}
            local selectedOption = options[FindWeaponOptionIndex(options, selectedPowerup)]
            if selectedOption and selectedOption.weaponName and selectedOption.weaponName ~= "" then
                if slotInfo.category == "special" then
                    -- Special slots are free.
                elseif slotInfo.category == "mortar" then
                    -- Mortar slots have a flat +1 surcharge when upgraded.
                    if IsDifferentWeapon(slotInfo, selectedOption) then
                        mortarUpgrades = mortarUpgrades + 1
                    end
                else
                    local extra = (selectedOption.scrapCost or 0.0) - GetStockWeaponUpgradeCost(slotInfo, options)
                    if extra > 0.0 and (slotInfo.category == "cannon" or slotInfo.category == "rocket") then
                        table.insert(manualExtras, extra)
                    end
                end
            end
        end
    end

    if mortarUpgrades > 0 then
        local surchargeConfig = PersistentConfig.PresetConfig and PersistentConfig.PresetConfig.surcharge
        local mortarFlat = (surchargeConfig and surchargeConfig.mortarFlat) or 1.0
        total = total + (mortarUpgrades * mortarFlat)
    end

    if #manualExtras > 0 then
        table.sort(manualExtras, function(a, b) return a > b end)
        local multipliers = (surchargeConfig and surchargeConfig.multipliers) or { 0.5, 0.25 }
        local tailMultiplier = (surchargeConfig and surchargeConfig.tailMultiplier) or 0.1
        for index, extra in ipairs(manualExtras) do
            local mult = multipliers[index] or tailMultiplier
            total = total + (extra * mult)
        end
    end

    return total
end

local function GetPresetPageContext()
    local team = GetPlayerTeamNum()
    local armory = GetArmoryHandle(team)
    if not IsValid(armory) then
        return {
            available = false,
            team = team,
        }
    end

    local availableKinds = {}
    for kindIndex, kind in ipairs(PresetProducerKinds) do
        local producer = GetProducerHandleForKind(kindIndex, team)
        if IsValid(producer) then
            table.insert(availableKinds, {
                kindIndex = kindIndex,
                label = kind.name,
                handle = producer,
                entries = GetProducerBuildEntries(producer),
            })
        end
    end

    if #availableKinds == 0 then
        return {
            available = true,
            team = team,
            armory = armory,
            producerKinds = {},
            armoryOptions = GetArmoryWeaponOptions(armory),
        }
    end

    InputState.presetProducerIndex = ClampIndex(InputState.presetProducerIndex, 1, #availableKinds, 1)
    local producerInfo = availableKinds[InputState.presetProducerIndex]
    local unitEntries = producerInfo.entries or {}
    if #unitEntries > 0 then
        InputState.presetUnitIndex = ClampIndex(InputState.presetUnitIndex, 1, #unitEntries, 1)
    else
        InputState.presetUnitIndex = 1
    end

    local selectedEntry = unitEntries[InputState.presetUnitIndex]
    local rows = {
        { kind = "producer" },
        { kind = "unit" },
    }
    if selectedEntry then
        for _, slotInfo in ipairs(selectedEntry.slots or {}) do
            table.insert(rows, {
                kind = "slot",
                slotInfo = slotInfo,
            })
        end
        table.insert(rows, { kind = "cost" })
    end
    InputState.presetRow = ClampIndex(InputState.presetRow, 1, math.max(#rows, 1), 1)

    return {
        available = true,
        team = team,
        armory = armory,
        armoryOptions = GetArmoryWeaponOptions(armory),
        producerKinds = availableKinds,
        producerInfo = producerInfo,
        unitEntries = unitEntries,
        selectedEntry = selectedEntry,
        rows = rows,
    }
end

local function GetQueuePageContext()
    local team = GetPlayerTeamNum()
    local availableKinds = {}
    for kindIndex, kind in ipairs(PresetProducerKinds) do
        local producer = GetProducerHandleForKind(kindIndex, team)
        local deployed = true
        if type(IsDeployed) == "function" then
            local ok, result = pcall(IsDeployed, producer)
            if ok then
                deployed = result and true or false
            end
        end
        if IsValid(producer) and deployed then
            table.insert(availableKinds, {
                kindIndex = kindIndex,
                label = kind.name,
                handle = producer,
                entries = GetProducerBuildEntries(producer),
            })
        end
    end

    if #availableKinds == 0 then
        return {
            available = false,
            team = team,
            producerKinds = {},
        }
    end

    InputState.queueProducerIndex = ClampIndex(InputState.queueProducerIndex, 1, #availableKinds, 1)
    local producerInfo = availableKinds[InputState.queueProducerIndex]
    local unitEntries = producerInfo.entries or {}
    local rows = {
        { kind = "producer" },
        { kind = "queue_item" },
        { kind = "queue_count" },
        { kind = "queue_status" },
    }
    InputState.queueRow = ClampIndex(InputState.queueRow, 1, math.max(#rows, 1), 1)

    return {
        available = true,
        team = team,
        producerKinds = availableKinds,
        producerInfo = producerInfo,
        unitEntries = unitEntries,
        rows = rows,
    }
end

local function GetPresetSlotOption(slotInfo, armoryOptions, unitPreset)
    if not slotInfo or not armoryOptions then
        return nil, 1
    end
    local options = armoryOptions[slotInfo.category] and armoryOptions[slotInfo.category].options or {}
    local selectedPowerup = unitPreset and unitPreset[slotInfo.slotIndex] or ""
    local index = FindWeaponOptionIndex(options, selectedPowerup)
    return options[index], index, options
end

local function FormatPresetSlotValue(slotInfo, option)
    if not slotInfo then return "n/a" end
    if not option or not option.powerupOdf or option.powerupOdf == "" then
        return "STOCK/" .. (slotInfo.stockDisplay or "EMPTY")
    end
    return option.displayName or option.weaponName or option.powerupOdf
end

local function ApplyPresetDelta(unitOdfName, slotIndex, delta, context)
    local entry = context and context.selectedEntry or nil
    if not entry then return false end
    local unitPreset = GetUnitPresetRecord(unitOdfName)
    local slotInfo = nil
    for _, candidate in ipairs(entry.slots or {}) do
        if candidate.slotIndex == slotIndex then
            slotInfo = candidate
            break
        end
    end
    if not slotInfo then return false end

    local _, currentIndex, options = GetPresetSlotOption(slotInfo, context.armoryOptions, unitPreset)
    if not options or #options == 0 then return false end
    local newIndex = CycleIndex(currentIndex, #options, delta, 1)
    local selected = options[newIndex]
    if selected and selected.powerupOdf and selected.powerupOdf ~= "" then
        unitPreset[slotIndex] = selected.powerupOdf
    else
        unitPreset[slotIndex] = nil
    end
    return true
end

local function AdjustQueueItem(context, delta)
    if not context or not context.producerInfo or not context.unitEntries or #context.unitEntries == 0 then
        return false
    end
    local queue = GetProducerQueueState(context.producerInfo.kindIndex)
    if queue.locked then return false end
    local newIndex = CycleIndex(queue.itemIndex or 1, #context.unitEntries, delta, 1)
    if newIndex == queue.itemIndex then return false end
    queue.itemIndex = newIndex
    local entry = context.unitEntries[newIndex]
    queue.unitOdf = entry and entry.odf or ""
    if (queue.count or 0) > 0 then
        queue.remaining = queue.count
        queue.pendingIssue = nil
        queue.inProgress = false
    end
    return true
end

local function AdjustQueueCount(context, delta)
    if not context or not context.producerInfo then return false end
    local queue = GetProducerQueueState(context.producerInfo.kindIndex)
    if queue.locked then return false end
    local current = queue.count or 0
    local newCount = math.max(0, math.min(99, current + delta))
    if newCount == current then return false end
    queue.count = newCount
    if newCount <= 0 then
        queue.remaining = 0
        queue.pendingIssue = nil
        queue.inProgress = false
    else
        queue.remaining = newCount
        queue.pendingIssue = nil
        queue.inProgress = false
    end
    return true
end

local function ToggleQueueLock(context)
    if not context or not context.producerInfo then return false end
    local queue = GetProducerQueueState(context.producerInfo.kindIndex)
    queue.locked = not queue.locked
    if not queue.locked then
        queue.pendingIssue = nil
        queue.inProgress = false
    elseif (queue.remaining or 0) <= 0 and (queue.count or 0) > 0 then
        queue.remaining = queue.count
    end
    return true
end

local function ValidateAimHandle(player, target, allowAllies)
    if not IsValid(player) or not IsValid(target) or target == player then
        return nil
    end
    if type(IsAlive) == "function" and not IsAlive(target) then
        return nil
    end
    if not allowAllies and type(IsAlly) == "function" and IsAlly(player, target) then
        return nil
    end
    return target
end

local function GetExplicitTargetInfo(player, allowAllies)
    if not IsValid(player) or type(GetUserTarget) ~= "function" then
        return nil
    end

    local target = ValidateAimHandle(player, GetUserTarget(), allowAllies)
    if not target then
        return nil
    end

    local distance = GetDistance(player, target)
    if not distance or distance <= 0 then
        return nil
    end

    return {
        handle = target,
        position = type(GetPosition) == "function" and GetPosition(target) or nil,
        distance = distance,
        source = "target",
    }
end

local function GetReticleAimInfo(player, allowAllies)
    if not IsValid(player) or not exu then
        return nil
    end

    if exu.GetReticleObject then
        local ok, reticleObject = pcall(exu.GetReticleObject)
        if ok then
            local target = ValidateAimHandle(player, reticleObject, allowAllies)
            if target then
                local distance = GetDistance(player, target)
                if distance and distance > 0 then
                    return {
                        handle = target,
                        position = type(GetPosition) == "function" and GetPosition(target) or nil,
                        distance = distance,
                        source = "reticle_object",
                    }
                end
            end
        end
    end

    if exu.GetReticlePos then
        local ok, reticlePos = pcall(exu.GetReticlePos)
        if ok and reticlePos then
            local distance = GetDistance(player, reticlePos)
            if distance and distance > 0 then
                return {
                    handle = nil,
                    position = reticlePos,
                    distance = distance,
                    source = "reticle_pos",
                }
            end
        end
    end

    return nil
end

local function GetAimInfo(player, allowAllies)
    local explicit = GetExplicitTargetInfo(player, allowAllies)
    if explicit then
        return explicit
    end
    return GetReticleAimInfo(player, allowAllies)
end

local function GetHudTargetInfo(player)
    local aimInfo = GetAimInfo(player, true)
    if not aimInfo or not aimInfo.handle then
        return nil, nil
    end
    return aimInfo.handle, aimInfo.distance
end

local function GetAnyHudTargetInfo(player)
    local aimInfo = GetAimInfo(player, true)
    if not aimInfo or not aimInfo.handle then
        return nil, nil
    end
    return aimInfo.handle, aimInfo.distance
end

GetInstalledWeaponMask = function(h)
    if not IsValid(h) then return 0 end
    local mask = 0
    for slot = 0, 4 do
        local weapon = CleanString(GetWeaponClass(h, slot))
        if weapon ~= "" then
            mask = mask + (2 ^ slot)
        end
    end
    return mask
end

local function GetPlayerSpeedMeters(player)
    if not IsValid(player) then return 0 end
    local vel = GetVelocity(player) or { x = 0, y = 0, z = 0 }
    return math.sqrt((vel.x * vel.x) + (vel.y * vel.y) + (vel.z * vel.z))
end

local function GetTargetClosureInfo(player, target, targetDistance)
    if not IsValid(player) or not IsValid(target) or not targetDistance or targetDistance <= 0 then
        return nil, nil
    end

    local playerPos = GetPosition(player)
    local targetPos = GetPosition(target)
    if not playerPos or not targetPos then
        return nil, nil
    end

    local toTarget = targetPos - playerPos
    local distance = math.sqrt((toTarget.x * toTarget.x) + (toTarget.y * toTarget.y) + (toTarget.z * toTarget.z))
    if distance <= 0.001 then
        return nil, 0.0
    end

    local dir = SetVector(toTarget.x / distance, toTarget.y / distance, toTarget.z / distance)
    local playerVel = GetVelocity(player) or { x = 0, y = 0, z = 0 }
    local targetVel = GetVelocity(target) or { x = 0, y = 0, z = 0 }
    local relVel = SetVector(playerVel.x - targetVel.x, playerVel.y - targetVel.y, playerVel.z - targetVel.z)
    local closure = (relVel.x * dir.x) + (relVel.y * dir.y) + (relVel.z * dir.z)

    if closure <= 0.1 then
        return closure, nil
    end

    return closure, targetDistance / closure
end

function PersistentConfig._EstimateSplashAverageValue(minValue, maxValue, splashRadius)
    local minDamage = tonumber(minValue)
    local maxDamage = tonumber(maxValue)
    if minDamage == nil then return maxDamage end
    if maxDamage == nil then return minDamage end

    local radius = math.max(0.0, tonumber(splashRadius) or 0.0)
    local splashWeight = ClampRange(0.35 + (math.min(radius, 30.0) / 100.0), 0.35, 0.65, 0.45)
    return minDamage + ((maxDamage - minDamage) * splashWeight)
end

PersistentConfig.R = require("PersistentConfigR").Create({
    PersistentConfig = PersistentConfig,
    InputState = InputState,
    PresetProducerKinds = PresetProducerKinds,
    CleanString = CleanString,
    ClampIndex = ClampIndex,
    ShowFeedback = ShowFeedback,
    GetProducerHandleForKind = GetProducerHandleForKind,
    GetProducerBuildEntries = GetProducerBuildEntries,
    GetPresetSurchargeForEntry = GetPresetSurchargeForEntry,
    GetUnitBuildEntry = GetUnitBuildEntry,
    InitializeTrackedWorldHandles = InitializeTrackedWorldHandles,
    GetPlayerTeamNum = GetPlayerTeamNum,
    GetPowerRadius = function(...)
        return GetPowerRadius(...)
    end,
})

GetProducerQueueState = PersistentConfig.R.GetProducerQueueState
IsCommanderTrackedHandle = PersistentConfig.R.IsCommanderTrackedHandle
RegisterCommanderHandle = PersistentConfig.R.RegisterCommanderHandle
RemoveCommanderHandle = PersistentConfig.R.RemoveCommanderHandle
local QueueGameKey = PersistentConfig.R.QueueGameKey
local ConsumePendingGameKeyMatch = PersistentConfig.R.ConsumePendingGameKeyMatch
local UpdateTeamScrapSnapshot = PersistentConfig.R.UpdateTeamScrapSnapshot
local RecordBuildKeyIfPressed = PersistentConfig.R.RecordBuildKeyIfPressed
local UpdateProducerQueues = PersistentConfig.R.UpdateProducerQueues
local UpdateProducerBuildState = PersistentConfig.R.UpdateProducerBuildState
local FindPendingBuildForUnit = PersistentConfig.R.FindPendingBuildForUnit
local UpdatePendingBuildRefunds = PersistentConfig.R.UpdatePendingBuildRefunds
local ResetCommanderOverview = PersistentConfig.R.ResetCommanderOverview
local UpdateCommanderOverview = PersistentConfig.R.UpdateCommanderOverview

PersistentConfig.P = require("PersistentConfigP").Create({
    PersistentConfig = PersistentConfig,
    InputState = InputState,
    PdaPages = PdaPages,
    AppendPdaFooter = AppendPdaFooter,
    AppendPdaNavHints = AppendPdaNavHints,
    BuildPdaHeader = BuildPdaHeader,
    ClampIndex = ClampIndex,
    ClampRange = ClampRange,
    CleanString = CleanString,
    FormatPresetSlotValue = FormatPresetSlotValue,
    GetAimInfo = GetAimInfo,
    GetDisplayedWeaponStats = GetDisplayedWeaponStats,
    GetEffectiveWeaponRangeMeters = GetEffectiveWeaponRangeMeters,
    GetHardpointCategoryLabel = GetHardpointCategoryLabel,
    GetHudTargetInfo = GetHudTargetInfo,
    GetHorizontalDistanceBetweenHandles = GetHorizontalDistanceBetweenHandles,
    GetHorizontalDistanceBetweenPositions = GetHorizontalDistanceBetweenPositions,
    GetInstalledWeaponMask = GetInstalledWeaponMask,
    GetPlayerSpeedMeters = GetPlayerSpeedMeters,
    GetPresetPageContext = GetPresetPageContext,
    GetPresetSlotOption = GetPresetSlotOption,
    GetPresetSurchargeForEntry = GetPresetSurchargeForEntry,
    GetProducerQueueState = GetProducerQueueState,
    GetQueuePageContext = GetQueuePageContext,
    GetSettingsPageEntries = function()
        if GetSettingsPageEntries then
            return GetSettingsPageEntries()
        end
        return {}
    end,
    GetTargetClosureInfo = GetTargetClosureInfo,
    GetUnitPresetRecord = GetUnitPresetRecord,
    GetVehicleDisplayName = GetVehicleDisplayName,
    GetWeaponReticleName = GetWeaponReticleName,
    GetWeaponStats = GetWeaponStats,
    IsMaskBitSet = IsMaskBitSet,
    ResolveLiveSelectedWeaponMask = ResolveLiveSelectedWeaponMask,
})

local function UpdateWeaponStatsDisplay(player)
    if not PersistentConfig.Settings.WeaponStatsHud then
        if InputState.lastWeaponMask ~= nil or InputState.lastWeaponPlayer ~= nil or InputState.lastWeaponText ~= nil then
            InputState.lastWeaponMask = nil
            InputState.lastWeaponPlayer = nil
            InputState.lastWeaponText = nil
            InputState.lastWeaponTarget = nil
            ClearWeaponStats()
        end
        return
    end

    if not IsValid(player) then
        if InputState.lastWeaponMask ~= nil or InputState.lastWeaponPlayer ~= nil or InputState.lastWeaponText ~= nil then
            InputState.lastWeaponMask = nil
            InputState.lastWeaponPlayer = nil
            InputState.lastWeaponText = nil
            InputState.lastWeaponTarget = nil
            ClearWeaponStats()
        end
        return
    end

    local now = GetTime()
    if now < (InputState.nextWeaponHudCheck or 0.0) then return end
    InputState.nextWeaponHudCheck = now + 0.10

    local page = ClampIndex(InputState.pdaPage, 1, PdaPages.COUNT, PdaPages.STATS)
    local mask = GetCurrentWeaponMask(player)
    if page == PdaPages.TARGET and exu and type(exu.GetSelectedWeaponMask) == "function" then
        local ok, selectedMask = pcall(exu.GetSelectedWeaponMask, player)
        if ok and type(selectedMask) == "number" then
            selectedMask = math.max(0, math.floor(selectedMask + 0.5))
            if selectedMask > 0 then
                mask = selectedMask
            end
        end
    end
    local target = nil
    local targetDistance = nil
    if type(GetUserTarget) == "function" then
        target, targetDistance = GetHudTargetInfo(player)
    end
    local playerChanged = (InputState.lastWeaponPlayer ~= player)
    local maskChanged = (InputState.lastWeaponMask ~= mask)
    local targetChanged = (InputState.lastWeaponTarget ~= target)

    if mask <= 0 and page == PdaPages.STATS then
        InputState.lastWeaponMask = mask
        InputState.lastWeaponPlayer = player
        InputState.lastWeaponText = nil
        InputState.lastWeaponTarget = target
        ClearWeaponStats()
        return
    end

    local msg = PersistentConfig.P.BuildWeaponStatsText(player, mask)
    local textChanged = (InputState.lastWeaponText ~= msg)
    local overlayNeedsRefresh = PersistentConfig._CanUsePdaOverlay() and not PersistentConfig.PdaOverlay.statsVisible

    InputState.lastWeaponMask = mask
    InputState.lastWeaponPlayer = player
    InputState.lastWeaponText = msg
    InputState.lastWeaponTarget = target

    if (playerChanged or maskChanged or targetChanged or textChanged or overlayNeedsRefresh) and msg then
        ShowWeaponStats(msg, 86400.0)
    elseif not msg then
        ClearWeaponStats()
    end
end

local function RefreshWeaponHud()
    InputState.lastWeaponMask = nil
    InputState.lastWeaponPlayer = nil
    InputState.lastWeaponText = nil
    InputState.lastWeaponTarget = nil
    InputState.nextWeaponHudCheck = 0.0
end

local function RefreshPdaOverlay()
    RefreshWeaponHud()
    UpdateWeaponStatsDisplay(GetPlayerHandle())
end

local function RequestPdaOverlayRefresh(reason, delaySeconds)
    local now = (type(GetTime) == "function" and GetTime()) or 0.0
    local delay = math.max(tonumber(delaySeconds) or 0.05, 0.0)
    InputState.pdaOverlayRefreshPending = true
    InputState.nextPdaOverlayRefresh = now + delay
    InputState.pdaOverlayRefreshReason = reason or "unspecified"
    print(string.format("PersistentConfig: queued PDA overlay refresh (%s) for %.3f",
        tostring(InputState.pdaOverlayRefreshReason), InputState.nextPdaOverlayRefresh))
end

local function ProcessPendingPdaOverlayRefresh()
    if not InputState.pdaOverlayRefreshPending then
        return false
    end

    local now = (type(GetTime) == "function" and GetTime()) or 0.0
    if now < (InputState.nextPdaOverlayRefresh or 0.0) then
        return false
    end

    local reason = InputState.pdaOverlayRefreshReason or "unspecified"
    InputState.pdaOverlayRefreshPending = false
    InputState.nextPdaOverlayRefresh = 0.0
    InputState.pdaOverlayRefreshReason = nil

    print(string.format("PersistentConfig: processing PDA overlay refresh (%s)", tostring(reason)))
    ClearWeaponStats()
    ClearPdaFeedback()
    RefreshWeaponHud()
    return true
end

local function RebuildPdaOverlay()
    PersistentConfig._DestroyAllPdaOverlays()
    PersistentConfig._ResetPdaOverlayState()
    ClearWeaponStats()
    ClearPdaFeedback()
    RefreshPdaOverlay()
end

function PersistentConfig.ApplyScrapPilotHudLayout()
    if not exu then
        return
    end

    local layoutIndex = ClampIndex(PersistentConfig.Settings.ScrapPilotHudLayout, 1, #ScrapPilotHudLayouts, 2)
    if exu.SetMaterialTexture then
        local hudTexture = StockScrapPilotHudTexture
        if PersistentConfig._AppliedScrapPilotHudTexture ~= hudTexture then
            for _, materialName in ipairs(ScrapPilotHudMaterialNames) do
                pcall(exu.SetMaterialTexture, materialName, hudTexture)
            end
            PersistentConfig._AppliedScrapPilotHudTexture = hudTexture
        end
    end

    if exu.SetScrapHudColor then
        if layoutIndex == 2 then
            exu.SetScrapHudColor(0xFF007FFF)
        else
            exu.SetScrapHudColor(0xFFFFFFFF)
        end
    end

    if exu.SetPilotHudColor then
        if layoutIndex == 2 then
            exu.SetPilotHudColor(0xFF00FF00)
        else
            exu.SetPilotHudColor(0xFFFFFFFF)
        end
    end

    if layoutIndex ~= 2 then
        SetStockScrapPilotHudSpritesVisible(true)
        if exu.SetScrapPilotHudOffset then
            exu.SetScrapPilotHudOffset(0, 0)
        end
        return
    end

    ApplyLegacyScrapPilotHudTopLeft()
    SetStockScrapPilotHudSpritesVisible(false)
end

function PersistentConfig._SettingsActions.CommitPdaSettingChange(options)
    PersistentConfig.SaveConfig()

    local needsApplySettings = options and (
        options.applySettings or
        options.applyHeadlights or
        options.applyTargetReticle or
        options.applyFactionFlames or
        options.applyUnitVo or
        options.applyScrapPilotHud or
        options.applySubtitles or
        options.syncLightingMode or
        options.syncRadarSize
    )
    if needsApplySettings then
        PersistentConfig.ApplySettings(options)
    end
    if options and options.markOtherHeadlightsDirty then
        MarkOtherHeadlightsDirty()
    end
    if options and options.syncAutoRepairWingmen and aiCore and aiCore.ActiveTeams and aiCore.ActiveTeams[1] then
        aiCore.ActiveTeams[1]:SetConfig("autoRepairWingmen", PersistentConfig.Settings.AutoRepairWingmen)
    end
    if options and options.syncScavengerAssist and aiCore and aiCore.ActiveTeams and aiCore.ActiveTeams[1] then
        aiCore.ActiveTeams[1]:SetConfig("scavengerAssist", PersistentConfig.Settings.ScavengerAssistEnabled)
    end
    if options and options.syncAutoSave and autosave and autosave.Config then
        autosave.Config.enabled = PersistentConfig.Settings.AutoSaveEnabled
        autosave.Config.autoSaveInterval = PersistentConfig.Settings.AutoSaveInterval
        autosave.Config.currentSlot = PersistentConfig.Settings.AutoSaveSlot
        autosave.Config.currentPath = PersistentConfig._GetAutoSavePath()
    end

    if options and options.rebuildOverlay then
        RebuildPdaOverlay()
        return
    end

    -- Defer the live redraw until the next update tick so settings actions do not
    -- mutate the overlay while the input handler is still unwinding.
    RequestPdaOverlayRefresh("settings-commit", 0.05)
end

function PersistentConfig._SettingsActions.GetHeadlightColorPresetIndex()
    if PersistentConfig.Settings.RainbowMode then
        return #HeadlightColorPresets
    end

    for index, preset in ipairs(HeadlightColorPresets) do
        if not preset.rainbow and
            math.abs(PersistentConfig.Settings.HeadlightDiffuse.R - preset.r) < 0.1 and
            math.abs(PersistentConfig.Settings.HeadlightDiffuse.G - preset.g) < 0.1 and
            math.abs(PersistentConfig.Settings.HeadlightDiffuse.B - preset.b) < 0.1 then
            return index
        end
    end

    return 1
end

function PersistentConfig._SettingsActions.CycleHeadlightColor(delta)
    local nextIndex = CycleIndex(PersistentConfig._SettingsActions.GetHeadlightColorPresetIndex(), #HeadlightColorPresets,
        delta, 1)
    local preset = HeadlightColorPresets[nextIndex]

    if preset.rainbow then
        PersistentConfig.Settings.RainbowMode = true
        ShowFeedback("Rainbow Mode: ACTIVATE", preset.feedbackR or 1.0, preset.feedbackG or 0.5, preset.feedbackB or 1.0)
    else
        PersistentConfig.Settings.RainbowMode = false
        PersistentConfig.Settings.HeadlightDiffuse.R = preset.r
        PersistentConfig.Settings.HeadlightDiffuse.G = preset.g
        PersistentConfig.Settings.HeadlightDiffuse.B = preset.b
        ShowFeedback("Headlight Color: " .. preset.name, preset.r, preset.g, preset.b)
    end

    PersistentConfig._SettingsActions.CommitPdaSettingChange({ applyHeadlights = true })
    return true
end

function PersistentConfig._SettingsActions.SetPlayerHeadlightVisible(enabled)
    local visible = not not enabled
    if PersistentConfig.Settings.HeadlightVisible == visible then
        return false
    end

    PersistentConfig.Settings.HeadlightVisible = visible
    PersistentConfig._SettingsActions.CommitPdaSettingChange({ applyHeadlights = true })
    ShowFeedback("Player Light: " .. (visible and "ON" or "OFF"))
    return true
end

function PersistentConfig._SettingsActions.SetOtherHeadlightsEnabled(enabled)
    local showOthers = not not enabled
    if PersistentConfig.Settings.OtherHeadlightsDisabled == (not showOthers) then
        return false
    end

    PersistentConfig.Settings.OtherHeadlightsDisabled = not showOthers
    PersistentConfig._SettingsActions.CommitPdaSettingChange({ markOtherHeadlightsDirty = true })
    ShowFeedback("AI Lights: " .. (showOthers and "ON" or "OFF"))
    return true
end

function PersistentConfig._SettingsActions.CycleHeadlightBeamMode(delta)
    local nextMode = CycleIndex(PersistentConfig.Settings.HeadlightBeamMode, #PersistentConfig.HeadlightBeamModes, delta, 2)
    if PersistentConfig.Settings.HeadlightBeamMode == nextMode then
        return false
    end

    PersistentConfig.Settings.HeadlightBeamMode = nextMode
    PersistentConfig._SettingsActions.CommitPdaSettingChange({ applyHeadlights = true })
    ShowFeedback("Beam: " .. (nextMode == 1 and "FOCUSED" or "WIDE"))
    return true
end

function PersistentConfig._SettingsActions.SetWeaponStatsHudEnabled(enabled)
    local visible = not not enabled
    if PersistentConfig.Settings.WeaponStatsHud == visible then
        return false
    end

    PersistentConfig.Settings.WeaponStatsHud = visible
    PersistentConfig._SettingsActions.CommitPdaSettingChange()
    if visible then
        RequestPdaOverlayRefresh("weapon-stats-toggle-on", 0.05)
    else
        RefreshWeaponHud()
        ClearWeaponStats()
        ClearPdaFeedback()
    end
    ShowFeedback("PDA: " .. (visible and "ON" or "OFF"), 0.35, 0.65, 1.0, 2.5, false)
    return true
end

function PersistentConfig._SettingsActions.CycleScrapPilotHudLayout(delta)
    local nextIndex = CycleIndex(PersistentConfig.Settings.ScrapPilotHudLayout, #ScrapPilotHudLayouts, delta, 2)
    if PersistentConfig.Settings.ScrapPilotHudLayout == nextIndex then
        return false
    end

    PersistentConfig.Settings.ScrapPilotHudLayout = nextIndex
    PersistentConfig._SettingsActions.CommitPdaSettingChange({ applyScrapPilotHud = true })
    ShowFeedback("Scrap/Pilot: " .. GetScrapPilotHudLayout().name, 0.8, 1.0, 0.8, 2.5, false, "pda")
    return true
end

function PersistentConfig._SettingsActions.SetSubtitlesEnabled(enabled)
    local value = not not enabled
    if PersistentConfig.Settings.SubtitlesEnabled == value then
        return false
    end

    PersistentConfig.Settings.SubtitlesEnabled = value
    PersistentConfig._SettingsActions.CommitPdaSettingChange({ applySubtitles = true })
    if not value then
        local subtit = GetScriptSubtitles()
        if subtit and subtit.ClearActive then
            subtit.ClearActive()
        end
    end
    ShowFeedback("Subtitles: " .. (value and "ON" or "OFF"), 0.8, 1.0, 0.8)
    return true
end

function PersistentConfig._CycleUnitVerbosity(delta)
    local nextIndex = CycleIndex(PersistentConfig.Settings.UnitVerbosity, #PersistentConfig.UnitVerbosityPresets, delta,
        1)
    if PersistentConfig.Settings.UnitVerbosity == nextIndex then
        return false
    end

    PersistentConfig.Settings.UnitVerbosity = nextIndex
    PersistentConfig._SettingsActions.CommitPdaSettingChange({ applyUnitVo = true })
    ShowFeedback("Unit Verbosity: " .. PersistentConfig._GetUnitVerbosityPreset().name, 0.8, 1.0, 0.8, 2.5, false, "pda")
    return true
end

function PersistentConfig._CycleTargetReticlePopupMode(delta)
    local currentIndex = PersistentConfig._GetTargetReticlePopupPresetIndex()
    local nextIndex = CycleIndex(currentIndex, #PersistentConfig.TargetReticlePopupPresets, delta, 1)
    if currentIndex == nextIndex then
        return false
    end

    PersistentConfig.Settings.TargetReticlePopupMode = PersistentConfig.TargetReticlePopupPresets[nextIndex].mode
    PersistentConfig._SettingsActions.CommitPdaSettingChange({ applyTargetReticle = true })
    ShowFeedback("Hit Reticle: " .. PersistentConfig._GetTargetReticlePopupPreset().name, 0.8, 1.0, 0.8, 2.5, false,
        "pda")
    return true
end

function PersistentConfig._SettingsActions.SetAutoRepairBuildingsEnabled(enabled)
    local value = not not enabled
    if PersistentConfig.Settings.AutoRepairBuildings == value then
        return false
    end

    PersistentConfig.Settings.AutoRepairBuildings = value
    PersistentConfig._SettingsActions.CommitPdaSettingChange()
    ShowFeedback("Building Repair: " .. (value and "ON" or "OFF"), 0.8, 1.0, 0.8)
    return true
end

function PersistentConfig._SettingsActions.SetAutoRepairWingmenEnabled(enabled)
    local value = not not enabled
    if PersistentConfig.Settings.AutoRepairWingmen == value then
        return false
    end

    PersistentConfig.Settings.AutoRepairWingmen = value
    PersistentConfig._SettingsActions.CommitPdaSettingChange({ syncAutoRepairWingmen = true })
    ShowFeedback("Wingman Auto-Repair: " .. (value and "ON" or "OFF"), 0.8, 1.0, 0.8)
    return true
end

function PersistentConfig._SettingsActions.SetScavengerAssistEnabled(enabled)
    local value = not not enabled
    if PersistentConfig.Settings.ScavengerAssistEnabled == value then
        return false
    end

    PersistentConfig.Settings.ScavengerAssistEnabled = value
    PersistentConfig._SettingsActions.CommitPdaSettingChange({ syncScavengerAssist = true })
    ShowFeedback("Scavenger Assist: " .. (value and "ON" or "OFF"), 0.8, 1.0, 0.8)
    return true
end

function PersistentConfig._SettingsActions.AdjustRadarSizeScale(delta)
    local nextScale = AdjustScale(PersistentConfig.Settings.RadarSizeScale, delta,
        PersistentConfig.RadarUi.min, PersistentConfig.RadarUi.max, PersistentConfig.RadarUi.step)
    nextScale = ClampRange(nextScale, PersistentConfig.RadarUi.min, PersistentConfig.RadarUi.max,
        PersistentConfig.DefaultSettings.RadarSizeScale)
    if math.abs(PersistentConfig.Settings.RadarSizeScale - nextScale) < 0.001 then
        return false
    end

    PersistentConfig.Settings.RadarSizeScale = nextScale
    PersistentConfig._SettingsActions.CommitPdaSettingChange({ syncRadarSize = true })
    ShowFeedback("Radar Size: " .. FormatScale(nextScale, PersistentConfig.RadarUi.min, PersistentConfig.RadarUi.max),
        0.8, 1.0, 0.8, 2.5, false, "pda")
    return true
end

function PersistentConfig._SettingsActions.SetDynamicFactionFlameColorsEnabled(enabled)
    local value = not not enabled
    if PersistentConfig.Settings.DynamicFactionFlameColors == value then
        return false
    end

    PersistentConfig.Settings.DynamicFactionFlameColors = value
    PersistentConfig._SettingsActions.CommitPdaSettingChange({ applyFactionFlames = true })
    ShowFeedback("Faction Flames: " .. (value and "ON" or "OFF"), 0.8, 1.0, 0.8, 2.5, false, "pda")
    return true
end

function PersistentConfig._SettingsActions.CycleLightingMode(delta)
    local nextIndex = CycleIndex(
        PersistentConfig.Settings.LightingMode,
        #PersistentConfig.LightingModePresets,
        delta,
        PersistentConfig.DefaultSettings.LightingMode or 1
    )
    if nextIndex == PersistentConfig.Settings.LightingMode then
        return false
    end

    local _, preset = PersistentConfig._SetLightingModeIndex(nextIndex)
    PersistentConfig._SettingsActions.CommitPdaSettingChange({ syncLightingMode = true })
    ShowFeedback("Lighting Mode: " .. ((preset and preset.name) or "DEFAULT"),
        0.8, 1.0, 0.8, 3.0, false, "pda")
    return true
end

function PersistentConfig._SettingsActions.SetAutoSaveEnabled(enabled)
    local value = not not enabled
    local interval = PersistentConfig._GetAutoSaveIntervalOption()

    if not value then
        PersistentConfig._ClearAutoSaveEnablePrompt()
    end
    if PersistentConfig.Settings.AutoSaveEnabled == value then
        return false
    end

    PersistentConfig.Settings.AutoSaveEnabled = value
    PersistentConfig._SettingsActions.CommitPdaSettingChange({ syncAutoSave = true })
    if value then
        ShowFeedback(string.format("Auto-Save: ON (%s)", interval.label), 0.8, 1.0, 0.8, 2.5, false, "pda")
    else
        ShowFeedback("Auto-Save: OFF", 0.8, 1.0, 0.8, 2.5, false, "pda")
    end
    return true
end

function PersistentConfig._AdjustAutoSaveSlot(delta)
    ShowFeedback("Auto-Save file is fixed to Save\\auto.sav.", 0.8, 1.0, 0.8, 3.0, false, "pda")
    return false
end

function PersistentConfig._AdjustAutoSaveInterval(delta)
    local direction = ((delta or 0) < 0) and -1 or 1
    local _, currentIndex = PersistentConfig._GetAutoSaveIntervalOption()
    local nextIndex = CycleIndex(currentIndex, #PersistentConfig.AutoSaveUi.intervalOptions, direction, currentIndex)
    if nextIndex == currentIndex then
        return false
    end

    local option = PersistentConfig.AutoSaveUi.intervalOptions[nextIndex]
    PersistentConfig.Settings.AutoSaveInterval = option.seconds
    PersistentConfig._ClearAutoSaveEnablePrompt()
    PersistentConfig._SettingsActions.CommitPdaSettingChange({ syncAutoSave = true })
    ShowFeedback("Auto-Save Interval: " .. option.label, 0.8, 1.0, 0.8, 2.5, false, "pda")
    return true
end

function PersistentConfig._HandleAutoSaveEnableAction()
    PersistentConfig._ClearAutoSaveEnablePrompt()
    return PersistentConfig._SettingsActions.SetAutoSaveEnabled(not PersistentConfig.Settings.AutoSaveEnabled)
end

function PersistentConfig._SetPilotModeEnabled(enabled)
    local value = not not enabled
    if PersistentConfig.Settings.PilotModeEnabled == value then
        return false
    end

    PersistentConfig.Settings.PilotModeEnabled = value
    PersistentConfig._SettingsActions.CommitPdaSettingChange()
    ShowFeedback("Pilot Mode: " .. (value and "ON" or "OFF"), 0.8, 1.0, 0.8)
    return true
end

GetSettingsPageEntries = function()
    local function DirectionEnabled(delta)
        return (delta or 0) > 0
    end

    return {
        {
            label = "PDA Size",
            value = FormatScale(PersistentConfig.Settings.PdaFontScale, PersistentConfig.FontScale.pda.min,
                PersistentConfig.FontScale.pda.max),
            adjust = function(delta)
                PersistentConfig.Settings.PdaFontScale = AdjustScale(PersistentConfig.Settings.PdaFontScale, delta,
                    PersistentConfig.FontScale.pda.min, PersistentConfig.FontScale.pda.max,
                    PersistentConfig.FontScale.pda.step)
                PersistentConfig._SettingsActions.CommitPdaSettingChange()
                return true
            end,
        },
        {
            label = "PDA Alpha",
            value = FormatOpacity(PersistentConfig.Settings.PdaOpacity),
            adjust = function(delta)
                PersistentConfig.Settings.PdaOpacity = AdjustOpacity(PersistentConfig.Settings.PdaOpacity, delta)
                PersistentConfig._SettingsActions.CommitPdaSettingChange()
                return true
            end,
        },
        {
            label = "HUD Color",
            value = GetPdaColorPreset().name,
            adjust = function(delta)
                PersistentConfig.Settings.PdaColorPreset = CycleIndex(PersistentConfig.Settings.PdaColorPreset,
                    #PdaColorPresets, delta, 2)
                PersistentConfig._SettingsActions.CommitPdaSettingChange()
                return true
            end,
        },
        {
            label = "Scrap/Pilot HUD",
            value = GetScrapPilotHudLayout().name,
            adjust = function(delta)
                return PersistentConfig._SettingsActions.CycleScrapPilotHudLayout(delta)
            end,
        },
        {
            label = "Radar Size",
            value = FormatScale(PersistentConfig.Settings.RadarSizeScale, PersistentConfig.RadarUi.min,
                PersistentConfig.RadarUi.max),
            adjust = function(delta)
                return PersistentConfig._SettingsActions.AdjustRadarSizeScale(delta)
            end,
        },
        {
            label = "PDA Panel",
            value = FormatHotkeyValue(PersistentConfig.Settings.WeaponStatsHud and "On" or "Off", "Y"),
            adjust = function(delta)
                return PersistentConfig._SettingsActions.SetWeaponStatsHudEnabled(DirectionEnabled(delta))
            end,
        },
        {
            label = "Hit Reticle",
            value = PersistentConfig._GetTargetReticlePopupPreset().name,
            adjust = function(delta)
                return PersistentConfig._CycleTargetReticlePopupMode(delta)
            end,
        },
        {
            label = "Lighting Mode",
            value = PersistentConfig._GetLightingModePreset().name,
            adjust = function(delta)
                return PersistentConfig._SettingsActions.CycleLightingMode(delta)
            end,
        },
        {
            label = "Subtitles",
            value = PersistentConfig.Settings.SubtitlesEnabled and "On" or "Off",
            adjust = function(delta)
                return PersistentConfig._SettingsActions.SetSubtitlesEnabled(DirectionEnabled(delta))
            end,
        },
        {
            label = "Unit Voices",
            value = PersistentConfig._GetUnitVerbosityPreset().name,
            adjust = function(delta)
                return PersistentConfig._CycleUnitVerbosity(delta)
            end,
        },
        {
            label = "Faction Flames",
            value = PersistentConfig.Settings.DynamicFactionFlameColors and "On" or "Off",
            adjust = function(delta)
                return PersistentConfig._SettingsActions.SetDynamicFactionFlameColorsEnabled(DirectionEnabled(delta))
            end,
        },
        {
            label = "Subtitle Size",
            value = FormatScale(PersistentConfig.Settings.SubtitleFontScale, PersistentConfig.FontScale.subtitle.min,
                PersistentConfig.FontScale.subtitle.max),
            adjust = function(delta)
                PersistentConfig.Settings.SubtitleFontScale = AdjustScale(PersistentConfig.Settings.SubtitleFontScale, delta,
                    PersistentConfig.FontScale.subtitle.min, PersistentConfig.FontScale.subtitle.max,
                    PersistentConfig.FontScale.subtitle.step)
                PersistentConfig._SettingsActions.CommitPdaSettingChange({ applySubtitles = true })
                return true
            end,
        },
        {
            label = "Subtitle Alpha",
            value = FormatOpacity(PersistentConfig.Settings.SubtitleOpacity),
            adjust = function(delta)
                PersistentConfig.Settings.SubtitleOpacity = AdjustOpacity(PersistentConfig.Settings.SubtitleOpacity, delta)
                PersistentConfig._SettingsActions.CommitPdaSettingChange({ applySubtitles = true })
                return true
            end,
        },
        {
            label = "Player Light",
            value = FormatHotkeyValue(PersistentConfig.Settings.HeadlightVisible and "On" or "Off", "V"),
            adjust = function(delta)
                return PersistentConfig._SettingsActions.SetPlayerHeadlightVisible(DirectionEnabled(delta))
            end,
        },
        {
            label = "Light Color",
            value = FormatHotkeyValue(
                HeadlightColorPresets[PersistentConfig._SettingsActions.GetHeadlightColorPresetIndex()].name, "Z"),
            adjust = function(delta)
                return PersistentConfig._SettingsActions.CycleHeadlightColor(delta)
            end,
        },
        {
            label = "AI Lights",
            value = FormatHotkeyValue(PersistentConfig.Settings.OtherHeadlightsDisabled and "Off" or "On", "J"),
            adjust = function(delta)
                return PersistentConfig._SettingsActions.SetOtherHeadlightsEnabled(DirectionEnabled(delta))
            end,
        },
        {
            label = "Beam",
            value = FormatHotkeyValue(PersistentConfig.Settings.HeadlightBeamMode == 1 and "Focused" or "Wide", "B"),
            adjust = function(delta)
                return PersistentConfig._SettingsActions.CycleHeadlightBeamMode(delta)
            end,
        },
        {
            label = "Wingman Repair",
            value = FormatHotkeyValue(PersistentConfig.Settings.AutoRepairWingmen and "On" or "Off", "X"),
            adjust = function(delta)
                return PersistentConfig._SettingsActions.SetAutoRepairWingmenEnabled(DirectionEnabled(delta))
            end,
        },
        {
            label = "Building Repair",
            value = PersistentConfig.Settings.AutoRepairBuildings and "On" or "Off",
            adjust = function(delta)
                return PersistentConfig._SettingsActions.SetAutoRepairBuildingsEnabled(DirectionEnabled(delta))
            end,
        },
        {
            label = "Scavenger Assist",
            value = FormatHotkeyValue(PersistentConfig.Settings.ScavengerAssistEnabled and "On" or "Off", "U"),
            adjust = function(delta)
                return PersistentConfig._SettingsActions.SetScavengerAssistEnabled(DirectionEnabled(delta))
            end,
        },
        {
            label = "Pilot Mode",
            value = PersistentConfig.Settings.PilotModeEnabled and "On" or "Off",
            adjust = function(delta)
                return PersistentConfig._SetPilotModeEnabled(DirectionEnabled(delta))
            end,
        },
        {
            key = "autosave_interval",
            label = "Auto Interval",
            value = PersistentConfig._GetAutoSaveIntervalOption().label,
            adjust = function(delta)
                return PersistentConfig._AdjustAutoSaveInterval(delta)
            end,
        },
        {
            key = "autosave",
            label = "Autosave",
            value = PersistentConfig._GetAutoSaveStatusValue(),
            actionHint = PersistentConfig._GetAutoSaveEnterHint(),
            adjust = function(delta)
                return PersistentConfig._SettingsActions.SetAutoSaveEnabled((delta or 0) > 0)
            end,
            action = function()
                return PersistentConfig._HandleAutoSaveEnableAction()
            end,
        },
        {
            label = "Reset Config",
            value = "Right to reset",
            adjust = function(delta)
                if DirectionEnabled(delta) then
                    PersistentConfig.ResetToDefaults()
                    return true
                end
                return false
            end,
        },
    }
end

-- Helper to convert Hue to RGB (Simple Rainbow)
function PersistentConfig._HueToRGB(h)
    local r, g, b
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local q = 1 - f
    local t = f

    i = i % 6
    if i == 0 then
        r, g, b = 1, t, 0
    elseif i == 1 then
        r, g, b = q, 1, 0
    elseif i == 2 then
        r, g, b = 0, 1, t
    elseif i == 3 then
        r, g, b = 0, q, 1
    elseif i == 4 then
        r, g, b = t, 0, 1
    elseif i == 5 then
        r, g, b = 1, 0, q
    end
    return r * 5.0, g * 5.0, b * 5.0 -- Scale to bright BZ intensities
end

function PersistentConfig.LoadConfig()
    -- Attempt to verify file existence via io if possible, but bzfile is safer context
    -- Use pcall to catch "not open" error if bzfile.Open returns a zombie handle
    PersistentConfig.UnitPresets = {}
    local loadedSubtitleFontScale
    local loadedPdaFontScale
    local legacySubtitlePreset
    local legacyPdaTextPreset
    local loadedLightingMode
    local legacyRetroLighting
    local status, err = pcall(function()
        local f = bzfile.Open(PersistentConfig.ConfigPath, "r")
        if not f then
            print("PersistentConfig: No config file found at " .. PersistentConfig.ConfigPath .. ". Using defaults.")
            return
        end

        local line = f:Readln()
        while line do
            local key, val = ParseLine(line)
            if key then
                if key == "HeadlightDiffuseR" then
                    PersistentConfig.Settings.HeadlightDiffuse.R = tonumber(val) or 5.0
                elseif key == "HeadlightDiffuseG" then
                    PersistentConfig.Settings.HeadlightDiffuse.G = tonumber(val) or 5.0
                elseif key == "HeadlightDiffuseB" then
                    PersistentConfig.Settings.HeadlightDiffuse.B = tonumber(val) or 5.0
                elseif key == "HeadlightSpecularR" then
                    PersistentConfig.Settings.HeadlightSpecular.R = tonumber(val) or 5.0
                elseif key == "HeadlightSpecularG" then
                    PersistentConfig.Settings.HeadlightSpecular.G = tonumber(val) or 5.0
                elseif key == "HeadlightSpecularB" then
                    PersistentConfig.Settings.HeadlightSpecular.B = tonumber(val) or 5.0
                elseif key == "HeadlightBeamMode" then
                    PersistentConfig.Settings.HeadlightBeamMode = tonumber(val) or 2
                elseif key == "HeadlightFalloff" then
                    PersistentConfig.Settings.HeadlightRange.Falloff = tonumber(val) or 0.35
                elseif key == "HeadlightVisible" then
                    PersistentConfig.Settings.HeadlightVisible = (val == "true")
                elseif key == "SubtitlesEnabled" then
                    PersistentConfig.Settings.SubtitlesEnabled = (val == "true")
                elseif key == "UnitVerbosity" then
                    PersistentConfig.Settings.UnitVerbosity = tonumber(val) or 1
                elseif key == "OtherHeadlightsDisabled" then
                    PersistentConfig.Settings.OtherHeadlightsDisabled = (val == "true")
                elseif key == "AutoRepairWingmen" then
                    PersistentConfig.Settings.AutoRepairWingmen = (val == "true")
                elseif key == "RainbowMode" then
                    PersistentConfig.Settings.RainbowMode = (val == "true")
                elseif key == "ScavengerAssistEnabled" then
                    PersistentConfig.Settings.ScavengerAssistEnabled = (val == "true")
                elseif key == "AutoSaveSlot" then
                    PersistentConfig.Settings.AutoSaveSlot = tonumber(val) or 10
                elseif key == "AutoSaveEnabled" then
                    PersistentConfig.Settings.AutoSaveEnabled = (val == "true")
                elseif key == "AutoSaveInterval" then
                    PersistentConfig.Settings.AutoSaveInterval = tonumber(val) or 300
                elseif key == "AutoRepairBuildings" then
                    PersistentConfig.Settings.AutoRepairBuildings = (val == "true")
                elseif key == "LightingMode" then
                    local numericValue = tonumber(val)
                    if numericValue then
                        loadedLightingMode = numericValue
                    else
                        local lowered = string.lower(CleanString(val))
                        if lowered == "default" then
                            loadedLightingMode = 1
                        elseif lowered == "enhanced" then
                            loadedLightingMode = 2
                        elseif lowered == "retro" then
                            loadedLightingMode = 3
                        end
                    end
                elseif key == "RetroLighting" then
                    legacyRetroLighting = (val == "true")
                elseif key == "WeaponStatsHud" then
                    PersistentConfig.Settings.WeaponStatsHud = (val == "true")
                elseif key == "PilotModeEnabled" then
                    PersistentConfig.Settings.PilotModeEnabled = (val == "true")
                elseif key == "SubtitleOpacity" then
                    PersistentConfig.Settings.SubtitleOpacity = tonumber(val) or 0.50
                elseif key == "SubtitleFontScale" then
                    loadedSubtitleFontScale = tonumber(val)
                elseif key == "SubtitleTextSizePreset" then
                    legacySubtitlePreset = tonumber(val)
                elseif key == "PdaOpacity" then
                    PersistentConfig.Settings.PdaOpacity = tonumber(val) or 1.00
                elseif key == "PdaFontScale" then
                    loadedPdaFontScale = tonumber(val)
                elseif key == "PdaTextSizePreset" then
                    legacyPdaTextPreset = tonumber(val)
                elseif key == "PdaColorPreset" then
                    PersistentConfig.Settings.PdaColorPreset = tonumber(val) or 2
                elseif key == "TargetReticlePopupMode" then
                    PersistentConfig.Settings.TargetReticlePopupMode = tonumber(val) or 1
                elseif key == "ScrapPilotHudLayout" then
                    PersistentConfig.Settings.ScrapPilotHudLayout = tonumber(val) or 2
                elseif key == "RadarSizeScale" then
                    PersistentConfig.Settings.RadarSizeScale = tonumber(val) or 1.0
                elseif key == "DynamicFactionFlameColors" then
                    PersistentConfig.Settings.DynamicFactionFlameColors = (val == "true")
                elseif key == "UnitPreset" then
                    local unitOdf, slotIndex, powerupOdf = string.match(val, "([^|]+)|([^|]+)|(.+)")
                    local unitKey = string.lower(CleanString(unitOdf or ""))
                    local slotNumber = tonumber(slotIndex)
                    local powerup = CleanString(powerupOdf or "")
                    if unitKey ~= "" and slotNumber and slotNumber >= 1 and slotNumber <= 5 and powerup ~= "" then
                        PersistentConfig.UnitPresets[unitKey] = PersistentConfig.UnitPresets[unitKey] or {}
                        PersistentConfig.UnitPresets[unitKey][slotNumber] = powerup
                    end
                end
            end
            line = f:Readln()
        end
        f:Close()
    end)

    if not status then
        if tostring(err):find("not open") then
            print("PersistentConfig: No config found (first run), creating new defaults.")
        else
            print("PersistentConfig: Error loading config: " .. tostring(err))
        end
    else
        print("PersistentConfig: Settings loaded.")
    end

    if loadedSubtitleFontScale then
        PersistentConfig.Settings.SubtitleFontScale = loadedSubtitleFontScale
    elseif legacySubtitlePreset then
        local idx = ClampIndex(legacySubtitlePreset, 1, #LEGACY_TEXT_PRESET_SCALES, 2)
        PersistentConfig.Settings.SubtitleFontScale = LEGACY_TEXT_PRESET_SCALES[idx] or 1.0
    end

    if loadedPdaFontScale then
        PersistentConfig.Settings.PdaFontScale = loadedPdaFontScale
    elseif legacyPdaTextPreset then
        local idx = ClampIndex(legacyPdaTextPreset, 1, #LEGACY_TEXT_PRESET_SCALES, 2)
        PersistentConfig.Settings.PdaFontScale = LEGACY_TEXT_PRESET_SCALES[idx] or 1.0
    end

    if loadedLightingMode ~= nil then
        PersistentConfig._SetLightingModeIndex(loadedLightingMode)
    elseif legacyRetroLighting ~= nil then
        PersistentConfig._SetLightingModeIndex(legacyRetroLighting and 3 or 1)
    else
        PersistentConfig._SetLightingModeIndex(PersistentConfig.Settings.LightingMode)
    end

    -- Sync ranges based on mode
    local mode = PersistentConfig.Settings.HeadlightBeamMode
    if PersistentConfig.HeadlightBeamModes[mode] then
        PersistentConfig.Settings.HeadlightRange.InnerAngle = PersistentConfig.HeadlightBeamModes[mode].Inner
        PersistentConfig.Settings.HeadlightRange.OuterAngle = PersistentConfig.HeadlightBeamModes[mode].Outer
    end
    PersistentConfig.Settings.SubtitleOpacity = ClampUnitInterval(PersistentConfig.Settings.SubtitleOpacity, 0.50)
    PersistentConfig.Settings.PdaOpacity = ClampUnitInterval(PersistentConfig.Settings.PdaOpacity, 1.00)
    PersistentConfig.Settings.UnitVerbosity = ClampIndex(PersistentConfig.Settings.UnitVerbosity, 1,
        #PersistentConfig.UnitVerbosityPresets, 1)
    PersistentConfig.Settings.SubtitleFontScale = ClampRange(PersistentConfig.Settings.SubtitleFontScale,
        PersistentConfig.FontScale.subtitle.min, PersistentConfig.FontScale.subtitle.max, 1.0)
    PersistentConfig.Settings.PdaFontScale = ClampRange(PersistentConfig.Settings.PdaFontScale,
        PersistentConfig.FontScale.pda.min, PersistentConfig.FontScale.pda.max, 1.0)
    PersistentConfig.Settings.PdaColorPreset = ClampIndex(PersistentConfig.Settings.PdaColorPreset, 1, #PdaColorPresets, 2)
    PersistentConfig.Settings.TargetReticlePopupMode = PersistentConfig._GetTargetReticlePopupPreset().mode
    PersistentConfig.Settings.ScrapPilotHudLayout = ClampIndex(PersistentConfig.Settings.ScrapPilotHudLayout, 1,
        #ScrapPilotHudLayouts, 2)
    PersistentConfig.Settings.RadarSizeScale = GetRadarSizeScaleSetting()
    PersistentConfig.Settings.AutoSaveSlot = PersistentConfig._GetAutoSaveSlot()
    PersistentConfig.Settings.AutoSaveInterval = PersistentConfig._GetAutoSaveIntervalOption().seconds
    PersistentConfig._SetLightingModeIndex(PersistentConfig.Settings.LightingMode)
end

function PersistentConfig.SaveConfig()
    print("=== PersistentConfig: Attempting to save config ===")
    print("Config path: " .. tostring(PersistentConfig.ConfigPath))
    print("Working directory: " .. tostring(bzfile.GetWorkingDirectory()))

    local status, err = pcall(function()
        local f = bzfile.Open(PersistentConfig.ConfigPath, "w", "trunc")
        if not f then
            print("PersistentConfig: Failed to open config file for writing!")
            print("Attempted path: " .. PersistentConfig.ConfigPath)
            return
        end

        print("PersistentConfig: File opened successfully, writing settings...")

        f:Writeln("HeadlightDiffuseR=" .. tostring(PersistentConfig.Settings.HeadlightDiffuse.R))
        f:Writeln("HeadlightDiffuseG=" .. tostring(PersistentConfig.Settings.HeadlightDiffuse.G))
        f:Writeln("HeadlightDiffuseB=" .. tostring(PersistentConfig.Settings.HeadlightDiffuse.B))
        f:Writeln("HeadlightSpecularR=" .. tostring(PersistentConfig.Settings.HeadlightSpecular.R))
        f:Writeln("HeadlightSpecularG=" .. tostring(PersistentConfig.Settings.HeadlightSpecular.G))
        f:Writeln("HeadlightSpecularB=" .. tostring(PersistentConfig.Settings.HeadlightSpecular.B))
        f:Writeln("HeadlightBeamMode=" .. tostring(PersistentConfig.Settings.HeadlightBeamMode))
        f:Writeln("HeadlightFalloff=" .. tostring(PersistentConfig.Settings.HeadlightRange.Falloff))
        f:Writeln("HeadlightVisible=" .. tostring(PersistentConfig.Settings.HeadlightVisible))
        f:Writeln("SubtitlesEnabled=" .. tostring(PersistentConfig.Settings.SubtitlesEnabled))
        f:Writeln("UnitVerbosity=" .. tostring(PersistentConfig.Settings.UnitVerbosity))
        f:Writeln("OtherHeadlightsDisabled=" .. tostring(PersistentConfig.Settings.OtherHeadlightsDisabled))
        f:Writeln("AutoRepairWingmen=" .. tostring(PersistentConfig.Settings.AutoRepairWingmen))
        f:Writeln("RainbowMode=" .. tostring(PersistentConfig.Settings.RainbowMode))
        f:Writeln("AutoSaveSlot=" .. tostring(PersistentConfig.Settings.AutoSaveSlot))
        f:Writeln("AutoSaveEnabled=" .. tostring(PersistentConfig.Settings.AutoSaveEnabled))
        f:Writeln("AutoSaveInterval=" .. tostring(PersistentConfig.Settings.AutoSaveInterval))
        f:Writeln("ScavengerAssistEnabled=" .. tostring(PersistentConfig.Settings.ScavengerAssistEnabled))
        f:Writeln("AutoRepairBuildings=" .. tostring(PersistentConfig.Settings.AutoRepairBuildings))
        f:Writeln("LightingMode=" .. tostring(PersistentConfig.Settings.LightingMode))
        f:Writeln("RetroLighting=" .. tostring(PersistentConfig.Settings.RetroLighting))
        f:Writeln("WeaponStatsHud=" .. tostring(PersistentConfig.Settings.WeaponStatsHud))
        f:Writeln("PilotModeEnabled=" .. tostring(PersistentConfig.Settings.PilotModeEnabled))
        f:Writeln("SubtitleOpacity=" .. tostring(PersistentConfig.Settings.SubtitleOpacity))
        f:Writeln("SubtitleFontScale=" .. tostring(PersistentConfig.Settings.SubtitleFontScale))
        f:Writeln("PdaOpacity=" .. tostring(PersistentConfig.Settings.PdaOpacity))
        f:Writeln("PdaFontScale=" .. tostring(PersistentConfig.Settings.PdaFontScale))
        f:Writeln("PdaColorPreset=" .. tostring(PersistentConfig.Settings.PdaColorPreset))
        f:Writeln("TargetReticlePopupMode=" .. tostring(PersistentConfig.Settings.TargetReticlePopupMode))
        f:Writeln("ScrapPilotHudLayout=" .. tostring(PersistentConfig.Settings.ScrapPilotHudLayout))
        f:Writeln("RadarSizeScale=" .. tostring(PersistentConfig.Settings.RadarSizeScale))
        f:Writeln("DynamicFactionFlameColors=" .. tostring(PersistentConfig.Settings.DynamicFactionFlameColors))
        for unitKey, preset in pairs(PersistentConfig.UnitPresets) do
            for slotIndex = 1, 5 do
                local powerupOdf = preset[slotIndex]
                if powerupOdf and powerupOdf ~= "" then
                    f:Writeln("UnitPreset=" .. tostring(unitKey) .. "|" .. tostring(slotIndex) .. "|" .. tostring(powerupOdf))
                end
            end
        end

        f:Close()
        print("PersistentConfig: File closed successfully")
    end)

    if not status then
        print("PersistentConfig: Error saving config: " .. tostring(err))
    else
        print("PersistentConfig: Settings saved successfully to: " .. PersistentConfig.ConfigPath)
    end
end

function PersistentConfig.ResetToDefaults()
    PersistentConfig.Settings = DeepCopy(PersistentConfig.DefaultSettings)
    PersistentConfig.UnitPresets = {}
    PersistentConfig.SaveConfig()
    PersistentConfig.ApplySettings()
    MarkOtherHeadlightsDirty()

    if autosave and autosave.Config then
        autosave.Config.enabled = PersistentConfig.Settings.AutoSaveEnabled
        autosave.Config.autoSaveInterval = PersistentConfig.Settings.AutoSaveInterval
        autosave.Config.currentSlot = PersistentConfig.Settings.AutoSaveSlot
        autosave.Config.currentPath = PersistentConfig._GetAutoSavePath()
    end

    ShowFeedback("Settings reset to defaults.", 0.7, 1.0, 0.7, 4.0, false)
end

function PersistentConfig.ApplySettings(options)
    local applyAll = not options

    if exu then
        local h = GetPlayerHandle()
        if (applyAll or (options and options.applyHeadlights)) and IsValid(h) then
        -- Sync ranges based on mode before applying
            local mode = PersistentConfig.Settings.HeadlightBeamMode
            if PersistentConfig.HeadlightBeamModes[mode] then
                PersistentConfig.Settings.HeadlightRange.InnerAngle = PersistentConfig.HeadlightBeamModes[mode].Inner
                PersistentConfig.Settings.HeadlightRange.OuterAngle = PersistentConfig.HeadlightBeamModes[mode].Outer
            end

            local mult = PersistentConfig.HeadlightBeamModes[mode] and PersistentConfig.HeadlightBeamModes[mode].Multiplier or 1.0

            if exu.SetHeadlightDiffuse then
                exu.SetHeadlightDiffuse(h, PersistentConfig.Settings.HeadlightDiffuse.R * mult,
                    PersistentConfig.Settings.HeadlightDiffuse.G * mult, PersistentConfig.Settings.HeadlightDiffuse.B * mult)
            end
            if exu.SetHeadlightSpecular then
                exu.SetHeadlightSpecular(h, PersistentConfig.Settings.HeadlightSpecular.R * mult,
                    PersistentConfig.Settings.HeadlightSpecular.G * mult,
                    PersistentConfig.Settings.HeadlightSpecular.B * mult)
            end
            if exu.SetHeadlightRange then
                exu.SetHeadlightRange(h, PersistentConfig.Settings.HeadlightRange.InnerAngle,
                    PersistentConfig.Settings.HeadlightRange.OuterAngle, PersistentConfig.Settings.HeadlightRange.Falloff)
            end
            if exu.SetHeadlightVisible then
                exu.SetHeadlightVisible(h, PersistentConfig.Settings.HeadlightVisible)
            end
        end

        if applyAll or (options and options.syncLightingMode) then
            PersistentConfig._RequestLightingModeResync()
            PersistentConfig._SyncLightingMode(true)
        end
        if (applyAll or (options and options.applyTargetReticle)) and exu.SetTargetReticlePopupMode then
            exu.SetTargetReticlePopupMode(PersistentConfig.Settings.TargetReticlePopupMode)
        end

        if applyAll or (options and options.syncRadarSize) then
            PersistentConfig._RequestRadarScaleResync()
            PersistentConfig._SyncRadarSizeScale(true)
        end
        if applyAll or (options and options.applyFactionFlames) then
            PersistentConfig._ApplyDynamicFactionFlameColors()
        end
        if applyAll or (options and options.applyUnitVo) then
            PersistentConfig._ApplyUnitVoSettings()
        end
    end

    if applyAll or (options and options.applyScrapPilotHud) then
        PersistentConfig.ApplyScrapPilotHudLayout()
    end

    if applyAll or (options and options.applySubtitles) then
        local subtit = GetScriptSubtitles()
        if subtit and subtit.SetOpacity then
            subtit.SetOpacity(PersistentConfig.Settings.SubtitleOpacity)
        end
        if subtit then
            if subtit.SetEnabled then
                subtit.SetEnabled(PersistentConfig.Settings.SubtitlesEnabled)
            end
            if subtit.SetFontScale then
                subtit.SetFontScale(PersistentConfig.Settings.SubtitleFontScale)
            elseif subtit.SetTextSizePreset then
                subtit.SetTextSizePreset(LegacyPresetFromScale(PersistentConfig.Settings.SubtitleFontScale))
            end
        end
    end
end

-- Show help overlay
function PersistentConfig.ShowHelp()
    -- Condensed Help Text
    local helpMsg = "Use Y to toggle PDA. Reset in Settings."

    ShowFeedback(helpMsg, 1.0, 1.0, 1.0, 8.0, false)
end

-- Reusable update logic for all missions
function PersistentConfig.UpdateInputs()
    RuntimeEnhancements.Update()
    ConservativeCulling.Update()

    -- Detect player craft change and reapply headlight settings
    local currentPlayerHandle = GetPlayerHandle()
    if currentPlayerHandle ~= InputState.lastPlayerHandle then
        if InputState.lastPlayerHandle then
            InputState.otherHeadlightVisibility[InputState.lastPlayerHandle] = nil
        end
        if currentPlayerHandle then
            InputState.otherHeadlightVisibility[currentPlayerHandle] = nil
        end
        if IsValid(currentPlayerHandle) then
            print("PersistentConfig: Player entered new craft, reapplying headlight settings.")
            PersistentConfig.ApplySettings()
        end
        MarkOtherHeadlightsDirty()
        InputState.lastPlayerHandle = currentPlayerHandle
        InputState.lastWeaponMask = nil
        InputState.lastWeaponPlayer = nil
        InputState.lastWeaponText = nil
        InputState.lastWeaponTarget = nil
    end

    local pauseMenuOpen = false
    if exu and exu.IsPauseMenuOpen then
        pauseMenuOpen = exu.IsPauseMenuOpen()
    end
    local escapePressed = LastGameKey == "ESCAPE"
    if exu and exu.GetGameKey and exu.GetGameKey("ESCAPE") then
        escapePressed = true
    end
    local uiInteractionSuppressed = pauseMenuOpen or escapePressed

    if InputState.autoSaveStartupPending then
        if not (autosave and autosave.Config and autosave.Config.enabled and autosave.Update) then
            InputState.autoSaveStartupPending = false
        elseif not uiInteractionSuppressed then
            InputState.autoSaveStartupPending = false
            autosave.Update(0.0)
        end
    end

    if PersistentConfig.ExperimentalOverlayVisible then
        local hideAt = PersistentConfig.ExperimentalOverlayExpireAt or 0.0
        if uiInteractionSuppressed or GetTime() >= hideAt then
            PersistentConfig._HideExperimentalOverlay()
        end
    end

    InputState.SubtitlesPaused = uiInteractionSuppressed
    local scriptSubtitles = GetScriptSubtitles()
    if scriptSubtitles and scriptSubtitles.SetSuspended then
        scriptSubtitles.SetSuspended(InputState.SubtitlesPaused)
    end

    local pendingOverlay = PersistentConfig.ExperimentalOverlayPending
    if pendingOverlay and not InputState.SubtitlesPaused and GetTime() >= (pendingOverlay.readyAt or 0.0) then
        PersistentConfig.ExperimentalOverlayPending = nil
        PersistentConfig._ShowAutoSaveOverlayNow(pendingOverlay.msg, pendingOverlay.duration, pendingOverlay.r,
            pendingOverlay.g, pendingOverlay.b)
    end

    PersistentConfig._UpdatePdaOverlayTimers()
    PersistentConfig.ReactiveReticleModule.Update()

    if uiInteractionSuppressed then
        ClearWeaponStats()
        ClearPdaFeedback()
    else
        ProcessPendingPdaOverlayRefresh()
        UpdateWeaponStatsDisplay(currentPlayerHandle)
    end

    -- Process Feedback Queue
    if not uiInteractionSuppressed and #PersistentConfig.FeedbackQueue > 0 then
        -- Check if mission subtitles are active
        local subtit = GetScriptSubtitles()
        local isBusy = false

        if subtit and subtit.IsActive then
            if subtit.IsActive() then
                isBusy = true
            else
                -- Check for 5 second silence after last subtitle
                local endTime = subtit.GetLastEndTime() or 0
                if GetTime() < endTime + 5.0 then
                    isBusy = true
                end
            end
        end

        local nextItem = PersistentConfig.FeedbackQueue[1]
        if nextItem and (nextItem.target == "pda" or not isBusy or nextItem.bypass) then
            local item = table.remove(PersistentConfig.FeedbackQueue, 1)
            if item.target == "pda" then
                if PersistentConfig.Settings.WeaponStatsHud then
                    ShowPdaFeedback(item.msg, item.r, item.g, item.b, item.duration)
                end
            elseif not PersistentConfig.Settings.SubtitlesEnabled then
                -- Drop subtitle messages while subtitles are disabled.
            elseif subtit and subtit.Display then
                subtit.Display(item.msg, item.r, item.g, item.b, item.duration)
            end
        end
    end

    local team = GetPlayerTeamNum()
    if InputState.lastUnitVoTeam ~= team then
        PersistentConfig._ApplyUnitVoSettings()
        InputState.lastUnitVoTeam = team
    end
    local now = GetTime()
    if InputState.radarScaleSyncPending and now >= (InputState.nextRadarScaleCheck or 0.0) then
        InputState.nextRadarScaleCheck = now + 0.5
        if PersistentConfig._SyncRadarSizeScale(false) ~= false then
            InputState.radarScaleSyncPending = false
        end
    end
    if InputState.lightingModeSyncPending and now >= (InputState.nextRetroLightingCheck or 0.0) then
        local stabilizeUntil = tonumber(InputState.nextRetroLightingStabilizeUntil) or 0.0
        local interval = PersistentConfig.RetroLightingIntervals.heartbeat
        if now < stabilizeUntil then
            interval = PersistentConfig.RetroLightingIntervals.stabilize
        end
        InputState.nextRetroLightingCheck = now + interval
        PersistentConfig._SyncLightingMode(true)
        if now >= stabilizeUntil then
            InputState.lightingModeSyncPending = false
            InputState.nextRetroLightingStabilizeUntil = 0.0
        end
    end
    if now >= (InputState.nextFactionFlameRefresh or 0.0) then
        InputState.nextFactionFlameRefresh = now + 1.0
        PersistentConfig._ApplyDynamicFactionFlameColors()
    end
    local scrapDelta = UpdateTeamScrapSnapshot(team)
    RecordBuildKeyIfPressed(team)
    UpdateProducerQueues(team)
    UpdateProducerBuildState(team, scrapDelta)
    UpdatePendingBuildRefunds()
    UpdateCommanderOverview()

    if not exu or not exu.GetGameKey then return end

    -- Toggle Player Headlight (V)
    local v_key = exu.GetGameKey("V")
    if v_key and not InputState.last_v_state then
        PersistentConfig._SettingsActions.SetPlayerHeadlightVisible(not PersistentConfig.Settings.HeadlightVisible)
    end
    InputState.last_v_state = v_key

    -- Cycle Headlight Color (Z) - Moved from Alt+C to Z
    local z_key = exu.GetGameKey("Z")
    if z_key and not InputState.last_z_state then
        PersistentConfig._SettingsActions.CycleHeadlightColor(1)
    end
    InputState.last_z_state = z_key

    -- Toggle AI/NPC Headlights (J) - Moved from Alt+U to J
    local j_key = exu.GetGameKey("J")
    if j_key and not InputState.last_j_state then
        PersistentConfig._SettingsActions.SetOtherHeadlightsEnabled(PersistentConfig.Settings.OtherHeadlightsDisabled)
    end
    InputState.last_j_state = j_key

    -- Toggle Headlight Beam Mode (B) - Removed Alt requirement, but check for Bail (Ctrl+B)
    local b_key = exu.GetGameKey("B")
    local ctrl_down = exu.GetGameKey("CTRL")
    local y_key = exu.GetGameKey("Y")

    if b_key and not ctrl_down and not InputState.last_b_state then
        PersistentConfig._SettingsActions.CycleHeadlightBeamMode(1)
    end
    InputState.last_b_state = b_key

    if y_key and not ctrl_down and not InputState.last_y_state then
        PersistentConfig._SettingsActions.SetWeaponStatsHudEnabled(not PersistentConfig.Settings.WeaponStatsHud)
    end
    InputState.last_y_state = y_key

    if not PersistentConfig.Settings.WeaponStatsHud then
        return
    end

    local left_bracket_pressed = ConsumePendingGameKeyMatch({ "[", "{", "SHIFT+[", "OEM_4", "LBRACKET", "LEFTBRACKET" })
    local right_bracket_pressed = ConsumePendingGameKeyMatch({ "]", "}", "SHIFT+]", "OEM_6", "RBRACKET", "RIGHTBRACKET" })

    if left_bracket_pressed then
        PersistentConfig._ClearAutoSaveEnablePrompt()
        InputState.pdaPage = CycleIndex(InputState.pdaPage, PdaPages.COUNT, -1, PdaPages.STATS)
        PlayPdaSound("mnu_back.wav")
        ClearPdaFeedback()
        RefreshPdaOverlay()
    end
    if right_bracket_pressed then
        PersistentConfig._ClearAutoSaveEnablePrompt()
        InputState.pdaPage = CycleIndex(InputState.pdaPage, PdaPages.COUNT, 1, PdaPages.STATS)
        PlayPdaSound("mnu_next.wav")
        ClearPdaFeedback()
        RefreshPdaOverlay()
    end
    local pda_up_key = ConsumePendingGameKeyMatch({ "UP", "UPARROW" })
    local pda_down_key = ConsumePendingGameKeyMatch({ "DOWN", "DOWNARROW" })
    local pda_left_key = ConsumePendingGameKeyMatch({ "LEFT", "LEFTARROW" })
    local pda_right_key = ConsumePendingGameKeyMatch({ "RIGHT", "RIGHTARROW" })
    local enterPressed = ConsumePendingGameKeyMatch({ "ENTER", "RETURN", "NUMPADENTER", "KPENTER", "KP_ENTER" })

    if InputState.pdaPage == PdaPages.SETTINGS then
        local settingsEntries = GetSettingsPageEntries()
        local settingsCount = math.max(#settingsEntries, 1)

        if pda_up_key then
            PersistentConfig._ClearAutoSaveEnablePrompt()
            InputState.pdaSettingsIndex = CycleIndex(InputState.pdaSettingsIndex, settingsCount, -1, 1)
            PlayPdaSound("mnu_clik.wav")
            RefreshPdaOverlay()
        elseif pda_down_key then
            PersistentConfig._ClearAutoSaveEnablePrompt()
            InputState.pdaSettingsIndex = CycleIndex(InputState.pdaSettingsIndex, settingsCount, 1, 1)
            PlayPdaSound("mnu_clik.wav")
            RefreshPdaOverlay()
        end

        local settingChanged = false
        local selection = ClampIndex(InputState.pdaSettingsIndex, 1, settingsCount, 1)
        local entry = settingsEntries[selection]
        if pda_left_key then
            settingChanged = entry and entry.adjust and entry.adjust(-1) or false
        elseif pda_right_key then
            settingChanged = entry and entry.adjust and entry.adjust(1) or false
        elseif enterPressed then
            settingChanged = entry and entry.action and entry.action() or false
        end

        if settingChanged then
            PlayPdaSound("mnu_enab.wav")
        end
    elseif InputState.pdaPage == PdaPages.PRESETS then
        local context = GetPresetPageContext()
        local rowCount = math.max(#(context.rows or {}), 1)

        if pda_up_key then
            InputState.presetRow = CycleIndex(InputState.presetRow, rowCount, -1, 1)
            PlayPdaSound("mnu_clik.wav")
            RefreshPdaOverlay()
        elseif pda_down_key then
            InputState.presetRow = CycleIndex(InputState.presetRow, rowCount, 1, 1)
            PlayPdaSound("mnu_clik.wav")
            RefreshPdaOverlay()
        end

        local changedPreset = false
        local row = context.rows and context.rows[ClampIndex(InputState.presetRow, 1, rowCount, 1)] or nil
        local delta = pda_left_key and -1 or (pda_right_key and 1 or 0)
        if delta ~= 0 and row then
            if row.kind == "producer" and #context.producerKinds > 0 then
                InputState.presetProducerIndex = CycleIndex(InputState.presetProducerIndex, #context.producerKinds, delta, 1)
                InputState.presetUnitIndex = 1
                InputState.presetRow = 1
                changedPreset = true
            elseif row.kind == "unit" and #context.unitEntries > 0 then
                InputState.presetUnitIndex = CycleIndex(InputState.presetUnitIndex, #context.unitEntries, delta, 1)
                changedPreset = true
            elseif row.kind == "slot" and context.selectedEntry then
                changedPreset = ApplyPresetDelta(context.selectedEntry.odf, row.slotInfo.slotIndex, delta, context)
            end
        end

        if changedPreset then
            PlayPdaSound("mnu_enab.wav")
            if changedPreset then
                PersistentConfig.SaveConfig()
            end
            RefreshPdaOverlay()
        end
    elseif InputState.pdaPage == PdaPages.QUEUE then
        local context = GetQueuePageContext()
        local rowCount = math.max(#(context.rows or {}), 1)

        if pda_up_key then
            InputState.queueRow = CycleIndex(InputState.queueRow, rowCount, -1, 1)
            PlayPdaSound("mnu_clik.wav")
            RefreshPdaOverlay()
        elseif pda_down_key then
            InputState.queueRow = CycleIndex(InputState.queueRow, rowCount, 1, 1)
            PlayPdaSound("mnu_clik.wav")
            RefreshPdaOverlay()
        end

        local changedQueue = false
        local row = context.rows and context.rows[ClampIndex(InputState.queueRow, 1, rowCount, 1)] or nil
        local delta = pda_left_key and -1 or (pda_right_key and 1 or 0)
        if delta ~= 0 and row then
            if row.kind == "producer" and #context.producerKinds > 0 then
                InputState.queueProducerIndex = CycleIndex(InputState.queueProducerIndex, #context.producerKinds, delta, 1)
                InputState.queueRow = 1
                changedQueue = true
            elseif row.kind == "queue_item" then
                changedQueue = AdjustQueueItem(context, delta)
            elseif row.kind == "queue_count" then
                changedQueue = AdjustQueueCount(context, delta)
            end
        end

        if enterPressed then
            if ToggleQueueLock(context) then
                PlayPdaSound("mnu_enab.wav")
                RefreshPdaOverlay()
            end
        elseif changedQueue then
            PlayPdaSound("mnu_enab.wav")
            RefreshPdaOverlay()
        end
    end

    -- Toggle Auto-Repair for Wingmen (X for "Auto-fiX")
    local x_key = exu.GetGameKey("X")
    if x_key and not InputState.last_x_state then
        PersistentConfig._SettingsActions.SetAutoRepairWingmenEnabled(not PersistentConfig.Settings.AutoRepairWingmen)
    end
    InputState.last_x_state = x_key

    -- Toggle Scavenger Assist (U)
    local u_key = exu.GetGameKey("U")
    if u_key and not InputState.last_u_state then
        PersistentConfig._SettingsActions.SetScavengerAssistEnabled(not PersistentConfig.Settings.ScavengerAssistEnabled)
    end
    InputState.last_u_state = u_key

    -- AutoSave and Reset are settings-menu only (no hotkeys).

    -- Help Popup (/ or ? key) - using stock BZ API
    local help_pressed = (LastGameKey == "/" or LastGameKey == "?")
    if help_pressed and not InputState.last_help_state then
        PersistentConfig.ShowHelp()
    end
    InputState.last_help_state = help_pressed

    if InputState.SubtitlesPaused and not keepPdaOverlayLive then
        ClearWeaponStats()
        ClearPdaFeedback()
    end

    -- Update Rainbow Color if active
    if PersistentConfig.Settings.RainbowMode and PersistentConfig.Settings.HeadlightVisible then
        local hue = (GetTime() * 0.2) % 1.0 -- Cycle every 5 seconds
        local r, g, b = PersistentConfig._HueToRGB(hue)
        local mode = PersistentConfig.Settings.HeadlightBeamMode
        local mult = PersistentConfig.HeadlightBeamModes[mode] and PersistentConfig.HeadlightBeamModes[mode].Multiplier or 1.0
        local h = GetPlayerHandle()
        if IsValid(h) and exu.SetHeadlightDiffuse then
            exu.SetHeadlightDiffuse(h, r * mult, g * mult, b * mult)
            if exu.SetHeadlightSpecular then
                exu.SetHeadlightSpecular(h, r * mult, g * mult, b * mult)
            end
        end
    end

    -- Steam ID Polling (Try for first 10 seconds, once per second)
    if not InputState.GreetingTriggered then
        local now = GetTime()
        if now - InputState.PollingStartTime < 10.0 then
            if now - (InputState.last_poll_time or 0) > 1.0 then
                InputState.last_poll_time = now
                local steamID, username
                if exu and exu.GetSteam64 then
                    steamID = exu.GetSteam64()
                end

                if not steamID or steamID == "" or steamID == "0" then
                    -- Fallback to log for ID
                    local logID, logName = ParseBzLogger()
                    if logID then steamID = logID end
                    if logName then username = logName end
                elseif not username then
                    -- Have ID but no name, check log for name
                    local _, logName = ParseBzLogger()
                    if logName then username = logName end
                end

                if steamID and #steamID >= 10 then
                    PersistentConfig.TriggerGreeting(steamID, username)
                    InputState.GreetingTriggered = true
                    InputState.SteamIDFound = true
                end
            end
        else
            -- Polling timeout
            InputState.GreetingTriggered = true
            print("PersistentConfig: Steam ID polling timed out.")
        end
    end


    -- Run Building Repair Logic
    if PersistentConfig.Settings.AutoRepairBuildings then
        local now = GetTime()
        if now - InputState.last_repair_time > InputState.repair_interval then
            InputState.last_repair_time = now
            PersistentConfig.UpdateBuildingRepair()
        end
    end
end

-- ODF Property Cache to avoid repeated file I/O
PersistentConfig.ODFCache = {}

GetPowerRadius = function(odfname)
    if not odfname then return 200.0 end

    -- Check Cache
    if PersistentConfig.ODFCache[odfname] then
        return PersistentConfig.ODFCache[odfname]
    end

    -- Default
    local radius = 200.0

    -- Try to read ODF using native API
    if OpenODF and GetODFFloat then
        local odf = OpenODF(odfname)
        if odf then
            -- GetODFFloat(odf, section, label, default)
            local val, found = GetODFFloat(odf, "PowerPlantClass", "powerRadius", 200.0)
            if found then
                radius = val
            end
        else
            print("PersistentConfig: Could not open ODF " .. odfname)
        end
    end

    -- Cache it
    PersistentConfig.ODFCache[odfname] = radius
    return radius
end

function PersistentConfig.UpdateBuildingRepair()
    -- Logic: Heal player buildings (Team 1) if within powerRadius of a power source (classLabel "powerplant")
    InitializeTrackedWorldHandles()

    local playerTeam = 1
    local powerSources = {}
    local repairTargets = {}
    local healAmount = 20 -- 20 HP per second
    local tracking = InputState.worldTracking

    for index = #tracking.repairPowerHandles, 1, -1 do
        local h = tracking.repairPowerHandles[index]
        if not IsValid(h) then
            RemoveTrackedWorldHandle(h)
        elseif GetTeamNum(h) == playerTeam and IsAlive(h) then
            local odf = GetOdf(h)
            powerSources[#powerSources + 1] = { handle = h, radius = GetPowerRadius(odf) }
        end
    end

    for index = #tracking.repairTargetHandles, 1, -1 do
        local h = tracking.repairTargetHandles[index]
        if not IsValid(h) then
            RemoveTrackedWorldHandle(h)
        elseif GetTeamNum(h) == playerTeam and IsAlive(h) and GetHealth(h) < 1.0 then
            repairTargets[#repairTargets + 1] = h
        end
    end

    if #powerSources == 0 or #repairTargets == 0 then return end

    -- Heal Buildings AND Turrets (Gun Towers are vehicles with class 'turret')
    for i = 1, #repairTargets do
        local h = repairTargets[i]
        local nearPower = false
        for j = 1, #powerSources do
            local p = powerSources[j]
            if GetDistance(h, p.handle) < p.radius then
                nearPower = true
                break
            end
        end

        if nearPower then
            AddHealth(h, healAmount)
        end
    end
end

function PersistentConfig.UpdateHeadlights()
    if not exu or not exu.SetHeadlightVisible then return end
    InitializeTrackedWorldHandles()

    local player = GetPlayerHandle()
    if IsValid(player) then
        exu.SetHeadlightVisible(player, PersistentConfig.Settings.HeadlightVisible)
        InputState.otherHeadlightVisibility[player] = nil
    end

    if not PersistentConfig.Settings.OtherHeadlightsDisabled then
        if not InputState.otherHeadlightsDirty then return end

        local restored = 0
        for h, visible in pairs(InputState.otherHeadlightVisibility) do
            if not IsValid(h) or h == player then
                InputState.otherHeadlightVisibility[h] = nil
            elseif visible == false then
                exu.SetHeadlightVisible(h, true)
                InputState.otherHeadlightVisibility[h] = true
                restored = restored + 1
            end
        end
        InputState.otherHeadlightsDirty = false
        if PersistentConfig.Debug and restored > 0 then
            print("PersistentConfig: restored headlights for " .. tostring(restored) .. " handle(s).")
        end
        return
    end

    if not InputState.otherHeadlightsDirty then return end

    local updated = 0
    local tracking = InputState.worldTracking
    for index = #tracking.headlightHandles, 1, -1 do
        local h = tracking.headlightHandles[index]
        if not IsValid(h) then
            RemoveTrackedWorldHandle(h)
        elseif ApplyOtherHeadlightVisibility(h, false, player) then
            updated = updated + 1
        end
    end

    for h, _ in pairs(InputState.otherHeadlightVisibility) do
        if not IsValid(h) or h == player then
            InputState.otherHeadlightVisibility[h] = nil
        end
    end

    InputState.otherHeadlightsDirty = false
    if PersistentConfig.Debug and updated > 0 then
        print("PersistentConfig: disabled headlights for " .. tostring(updated) .. " handle(s).")
    end
end

function PersistentConfig._IsBuildablePlayerUnitOdf(unitOdfName, team)
    local wanted = string.lower(CleanString(unitOdfName or ""))
    if wanted == "" then return false end
    for kindIndex, _ in ipairs(PresetProducerKinds) do
        local producer = GetProducerHandleForKind(kindIndex, team)
        if IsValid(producer) then
            for _, entry in ipairs(GetProducerBuildEntries(producer)) do
                if string.lower(entry.odf or "") == wanted then
                    return true
                end
            end
        end
    end
    return false
end

function PersistentConfig._HasNearbyProducingStructureForUnit(unitOdfName, team, h, maxDistance)
    local wanted = string.lower(CleanString(unitOdfName or ""))
    if wanted == "" or not IsValid(h) or type(GetDistance) ~= "function" then
        return false
    end

    local distanceLimit = tonumber(maxDistance) or 10.0
    for kindIndex, _ in ipairs(PresetProducerKinds) do
        local producer = GetProducerHandleForKind(kindIndex, team)
        if IsValid(producer) and GetDistance(h, producer) <= distanceLimit then
            for _, entry in ipairs(GetProducerBuildEntries(producer)) do
                if string.lower(entry.odf or "") == wanted then
                    return true
                end
            end
        end
    end

    return false
end

function PersistentConfig._ApplyUnitPresetToObject(h)
    if not IsValid(h) or not IsCraft(h) or IsBuilding(h) or IsPerson(h) then return false end

    local team = GetPlayerTeamNum()
    if type(GetTeamNum) == "function" and GetTeamNum(h) ~= team then
        return false
    end

    local odfName = CleanString((type(GetOdf) == "function" and GetOdf(h)) or "")
    local odfKey = string.lower(odfName)
    local preset = PersistentConfig.UnitPresets[odfKey]
    if odfKey == "" or not preset then
        return false
    end
    if not PersistentConfig._IsBuildablePlayerUnitOdf(odfName, team) then
        return false
    end
    if not PersistentConfig._HasNearbyProducingStructureForUnit(odfName, team, h, 10.0) then
        return false
    end

    local armory = GetArmoryHandle(team)
    if not IsValid(armory) then
        return false
    end

    local entry = GetUnitBuildEntry(odfName)
    local armoryOptions = GetArmoryWeaponOptions(armory)
    if not entry or not armoryOptions then
        return false
    end

    local pendingIndex, pending = FindPendingBuildForUnit(team, odfName, h)
    if pending and not pending.applyAllowed then
        if pendingIndex then
            table.remove(InputState.pendingBuilds, pendingIndex)
        end
        return false
    end

    local surcharge = math.floor(GetPresetSurchargeForEntry(entry) + 0.5)
    if pending and pending.surcharge then
        surcharge = pending.surcharge
    end
    local skipCharge = pending and pending.charged
    if surcharge > 0 and not skipCharge and type(GetScrap) == "function" and GetScrap(team) < surcharge then
        ShowFeedback("Preset skipped: need +" .. tostring(surcharge) .. " scrap", 1.0, 0.35, 0.35, 2.5, false, "pda")
        return false
    end

    local applied = false
    for _, slotInfo in ipairs(entry.slots or {}) do
        local selectedPowerup = preset[slotInfo.slotIndex]
        if selectedPowerup and selectedPowerup ~= "" then
            local options = armoryOptions[slotInfo.category] and armoryOptions[slotInfo.category].options or {}
            local option = options[FindWeaponOptionIndex(options, selectedPowerup)]
            if option and option.weaponName and option.weaponName ~= "" and type(GiveWeapon) == "function" then
                GiveWeapon(h, option.weaponName, slotInfo.slot)
                applied = true
            end
        end
    end

    if applied and surcharge > 0 and type(AddScrap) == "function" and not skipCharge then
        AddScrap(team, -surcharge)
    end
    if applied then
        ShowFeedback("Preset applied: " .. (entry.displayName or odfName) .. " +" .. tostring(surcharge) .. " scrap",
            0.35, 1.0, 0.35, 2.5, false, "pda")
    end
    if pendingIndex then
        if not applied and pending and pending.charged and type(AddScrap) == "function" and pending.surcharge > 0 then
            AddScrap(team, pending.surcharge)
        end
        table.remove(InputState.pendingBuilds, pendingIndex)
    end
    return applied
end

function PersistentConfig.OnObjectCreated(h)
    if InputState.processedCreationHandles[h] then
        return
    end
    InputState.processedCreationHandles[h] = true

    local handleInfo = PersistentConfig._DescribeHandleForLog(h)

    PersistentConfig._InvokeWithTrace("PersistentConfig.OnObjectCreated RuntimeEnhancements " .. handleInfo,
        RuntimeEnhancements.OnObjectCreated, h)
    PersistentConfig._InvokeWithTrace("PersistentConfig.OnObjectCreated ConservativeCulling " .. handleInfo,
        ConservativeCulling.OnObjectCreated, h)
    PersistentConfig._InvokeWithTrace("PersistentConfig.OnObjectCreated RegisterTrackedWorldHandle " .. handleInfo,
        RegisterTrackedWorldHandle, h)
    if aiCore and type(aiCore.TrackWorldObject) == "function" then
        PersistentConfig._InvokeWithTrace("PersistentConfig.OnObjectCreated aiCore.TrackWorldObject " .. handleInfo,
            aiCore.TrackWorldObject, h)
    end

    if exu and exu.SetHeadlightVisible and PersistentConfig.Settings.OtherHeadlightsDisabled then
        local player = GetPlayerHandle()
        PersistentConfig._InvokeWithTrace("PersistentConfig.OnObjectCreated ApplyOtherHeadlightVisibility " .. handleInfo,
            ApplyOtherHeadlightVisibility, h, false, player)
    end

    PersistentConfig._InvokeWithTrace("PersistentConfig.OnObjectCreated ApplyUnitPresetToObject " .. handleInfo,
        PersistentConfig._ApplyUnitPresetToObject, h)
end

function PersistentConfig.OnObjectDeleted(h)
    if not h then
        return
    end

    InputState.processedCreationHandles[h] = nil
    RemoveTrackedWorldHandle(h)

    if aiCore and type(aiCore.DeleteObject) == "function" then
        aiCore.DeleteObject(h)
    end
end

function PersistentConfig._InstallPlayerChargeTrackingHook()
    if PersistentConfig.PlayerChargeHookInstalled or not exu then
        return
    end

    local handler = function(odf, shooter, transform, ordnanceHandle)
        UpdatePlayerChargeWeaponState(odf, shooter)
    end

    if aiCore and type(aiCore.RegisterExuCallback) == "function" then
        if aiCore.RegisterExuCallback("BulletInit", handler) then
            PersistentConfig.PlayerChargeHookInstalled = true
            return
        end
    end

    local oldBulletInit = exu.BulletInit
    exu.BulletInit = function(...)
        handler(...)
        if oldBulletInit then
            return oldBulletInit(...)
        end
    end
    PersistentConfig.PlayerChargeHookInstalled = true
end

function PersistentConfig.Initialize()
    PersistentConfig._DestroyAllPdaOverlays()
    PersistentConfig._ResetPdaOverlayState()
    ResetTrackedWorldHandles()
    ResetCommanderOverview()
    InputState.processedCreationHandles = {}
    InputState.otherHeadlightVisibility = {}
    RuntimeEnhancements.Initialize()
    RuntimeEnhancements.RebuildVisuals()
    ConservativeCulling.Initialize()
    PersistentConfig.LoadConfig()
    WarnIfNativeFeaturesUnavailable()
    EnsureBundledOpenShimInstalled()

    -- Reset Passive Tracking in AutoSave
    if autosave then
        autosave.ActiveObjectives = {}
    end

    -- Default Auto-Repair based on difficulty if not explicitly set in config
    if PersistentConfig.Settings.AutoRepairWingmen == nil then
        local d = (exu and exu.GetDifficulty and exu.GetDifficulty()) or 2
        PersistentConfig.Settings.AutoRepairWingmen = (d <= 1)
        print("PersistentConfig: Defaulted Auto-Repair to " ..
            (PersistentConfig.Settings.AutoRepairWingmen and "ON" or "OFF") .. " based on difficulty.")
    end
    PersistentConfig.SaveConfig()
    PersistentConfig.ApplySettings({ syncLightingMode = true, syncRadarSize = true })
    -- Keep EXU overlay/font initialization lazy so startup does not touch the
    -- custom Ogre font path before the UI runtime is fully ready.
    PersistentConfig._InstallPlayerChargeTrackingHook()
    PersistentConfig.ReactiveReticleModule.Reset()
    PersistentConfig.ReactiveReticleModule.Initialize({
        log = Log,
        registerHitCallback = function(fn)
            if aiCore and type(aiCore.RegisterExuCallback) == "function" then
                return aiCore.RegisterExuCallback("BulletHit", fn)
            end
            return false
        end,
        resolveMaterial = function()
            if not exu or exu.isStub then
                return nil
            end

            local player = GetPlayerHandle and GetPlayerHandle() or nil
            if not IsValid(player) then
                return nil
            end

            local searchMask = ResolveLiveSelectedWeaponMask(player, GetCurrentWeaponMask(player))
            if not searchMask or searchMask <= 0 then
                return nil
            end

            for slot = 0, 4 do
                if IsMaskBitSet(searchMask, slot) then
                    local weapon = CleanString(GetWeaponClass(player, slot))
                    if weapon ~= "" then
                        local displayedStats = GetDisplayedWeaponStats(player, weapon, GetWeaponStats(weapon) or {}) or {}
                        local reticle = CleanString(GetWeaponReticleName(weapon, displayedStats.currentChargeLevel))
                        if reticle ~= "" then
                            return reticle
                        end
                    end
                end
            end

            return nil
        end,
    })
    MarkOtherHeadlightsDirty()

    -- Sync AutoSave config from settings
    if autosave and autosave.Config then
        autosave.Config.enabled = PersistentConfig.Settings.AutoSaveEnabled
        autosave.Config.autoSaveInterval = PersistentConfig.Settings.AutoSaveInterval
        autosave.Config.currentSlot = PersistentConfig.Settings.AutoSaveSlot
        autosave.Config.currentPath = PersistentConfig._GetAutoSavePath()
        autosave._forceInitialSave = autosave.Config.enabled and true or false
        InputState.autoSaveStartupPending = autosave.Config.enabled and true or false
        print("PersistentConfig: AutoSave synced - enabled=" .. tostring(autosave.Config.enabled) ..
            " interval=" .. tostring(autosave.Config.autoSaveInterval) ..
            " path=" .. tostring(autosave.Config.currentPath))
    end

    -- Show help reminder on every mission start
    PersistentConfig.ShowHelp()

    -- Initial Steam Check & Init Polling
    InputState.PollingStartTime = GetTime()

    local steamID
    local username

    -- 1. Try Engine Call immediately
    if exu and exu.GetSteam64 then
        steamID = exu.GetSteam64()
    end

    -- 2. Try to get name from log if missing (or ID if EXU failed)
    local logID, logName = ParseBzLogger()
    if logName then username = logName end
    if (not steamID or steamID == "" or steamID == "0") and logID then
        steamID = logID
    end

    -- 3. Immediate check
    if steamID and #steamID >= 10 then
        PersistentConfig.TriggerGreeting(steamID, username)
        InputState.GreetingTriggered = true
        InputState.SteamIDFound = true
    else
        print("PersistentConfig: Initial Steam ID retrieval failed. Starting background polling...")
    end

    -- Hook Mission End Functions to clear subtitles
    if not PersistentConfig.HooksInstalled then
        local oldGameKey = GameKey
        GameKey = function(key)
            QueueGameKey(key)
            if oldGameKey then
                return oldGameKey(key)
            end
        end
        local oldAddObject = AddObject
        if type(oldAddObject) == "function" then
            AddObject = function(h)
                local handleInfo = PersistentConfig._DescribeHandleForLog(h)
                PersistentConfig._InvokeWithTrace("PersistentConfig.AddObjectHook OnObjectCreated " .. handleInfo,
                    PersistentConfig.OnObjectCreated, h)
                return PersistentConfig._InvokeWithTrace("PersistentConfig.AddObjectHook oldAddObject " .. handleInfo,
                    oldAddObject, h)
            end
        end
        local oldCreateObject = CreateObject
        if type(oldCreateObject) == "function" then
            CreateObject = function(h)
                local handleInfo = PersistentConfig._DescribeHandleForLog(h)
                PersistentConfig._InvokeWithTrace("PersistentConfig.CreateObjectHook OnObjectCreated " .. handleInfo,
                    PersistentConfig.OnObjectCreated, h)
                return PersistentConfig._InvokeWithTrace("PersistentConfig.CreateObjectHook oldCreateObject " .. handleInfo,
                    oldCreateObject, h)
            end
        end
        local oldDeleteObject = DeleteObject
        DeleteObject = function(h)
            PersistentConfig.OnObjectDeleted(h)
            if oldDeleteObject then
                return oldDeleteObject(h)
            end
        end
        if SucceedMission then
            local oldSucceed = SucceedMission
            SucceedMission = function(...)
                PersistentConfig._DestroyAllPdaOverlays()
                PersistentConfig.ReactiveReticleModule.Reset()
                local subtit = GetScriptSubtitles()
                if subtit and subtit.ClearActive then
                    subtit.ClearActive()
                end
                oldSucceed(...)
            end
        end
        if FailMission then
            local oldFail = FailMission
            FailMission = function(...)
                PersistentConfig._DestroyAllPdaOverlays()
                PersistentConfig.ReactiveReticleModule.Reset()
                local subtit = GetScriptSubtitles()
                if subtit and subtit.ClearActive then
                    subtit.ClearActive()
                end
                oldFail(...)
            end
        end
        PersistentConfig.HooksInstalled = true
    end
end

return PersistentConfig
