-- PersistentConfig.lua
---@diagnostic disable: lowercase-global, undefined-global
local bzfile = require("bzfile")
local exu = require("exu")
local subtitles = require("subtitles")
local autosave = require("AutoSave")
local RuntimeEnhancements = require("RuntimeEnhancements")
local ConservativeCulling = require("ConservativeCulling")

local PersistentConfig = {}
local WEAPON_STATS_CHANNEL = 1
local PDA_FEEDBACK_CHANNEL = 2
PersistentConfig.Debug = false
local InputState
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
    AutoSaveSlot = 10,              -- Default to slot 10
    AutoSaveEnabled = false,        -- AutoSave disabled by default
    AutoSaveInterval = 300,         -- Auto-save every 5 minutes
    AutoRepairBuildings = false,    -- Toggle to auto-repair buildings near power
    RetroLighting = false,          -- Disables PBR and custom shader lighting equations
    WeaponStatsHud = true,          -- Persistent weapon stats panel
    PilotModeEnabled = false,       -- Player-side pilot mode automation
    SubtitleOpacity = 0.50,         -- Main subtitle opacity
    SubtitleFontScale = 2.00,       -- Subtitle font scale (0.85-2.00)
    PdaOpacity = 1.00,              -- PDA/weapon HUD opacity
    PdaFontScale = 1.30,            -- PDA font/window scale (0.85-1.30)
    PdaColorPreset = 2,             -- 1=Dark Green 2=Green 3=Blue 4=White
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

local PRESET_SURCHARGE_CONFIG = {
    mortarFlat = 1.0,
    multipliers = { 0.5, 0.25 },
    tailMultiplier = 0.1,
}

local PRESET_BUILD_CONFIG = {
    keyWindow = 0.5,
    refundGrace = 1.0,
    scrapConfirmTolerance = 0.5,
}

PersistentConfig.UnitPresets = {}
local GetSettingsPageEntries
local GetProducerQueueState
local CleanString

local PDA_FONT_SCALE_MIN = 0.85
local PDA_FONT_SCALE_MAX = 1.30
local PDA_FONT_SCALE_STEP = 0.05
local SUBTITLE_FONT_SCALE_MIN = 0.85
local SUBTITLE_FONT_SCALE_MAX = 2.00
local SUBTITLE_FONT_SCALE_STEP = 0.05
PersistentConfig.AutoSaveUi = {
    slotMin = 1,
    slotMax = 10,
    intervalOptions = {
        { seconds = 120, label = "2 MIN" },
        { seconds = 300, label = "5 MIN" },
        { seconds = 600, label = "10 MIN" },
    },
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
local configPath = getWorkingDirectory() .. "\\campaignReimagined_settings.cfg"

-- Logging Helper
local function Log(msg)
    if Print then
        Print(msg)
    else
        print(msg)
    end
end

-- On-Screen Feedback Helper
local function ShowFeedback(msg, r, g, b, duration, bypass, target)
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
    return ClampRange(PersistentConfig.Settings.PdaFontScale, PDA_FONT_SCALE_MIN, PDA_FONT_SCALE_MAX, 1.0)
end

local function GetPdaColorPreset()
    return PdaColorPresets[ClampIndex(PersistentConfig.Settings.PdaColorPreset, 1, #PdaColorPresets, 2)]
end

local function GetSubtitleFontScale()
    return ClampRange(PersistentConfig.Settings.SubtitleFontScale, SUBTITLE_FONT_SCALE_MIN, SUBTITLE_FONT_SCALE_MAX, 1.0)
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
    if PersistentConfig.Settings.AutoSaveEnabled then
        return "ON"
    end
    if InputState and InputState.autoSaveEnableArmed then
        return "CONFIRM"
    end
    return "OFF"
end

function PersistentConfig._GetAutoSaveEnterHint()
    if PersistentConfig.Settings.AutoSaveEnabled then
        return "LEFT DISABLE"
    end

    local slot = PersistentConfig._GetAutoSaveSlot()
    if InputState and InputState.autoSaveEnableArmed then
        return string.format("ENTER CONFIRM SLOT %d", slot)
    end
    return string.format("ENTER ARM SLOT %d", slot)
end

function PersistentConfig._BuildAutoSaveWarningLines(selectedEntry)
    local slot = PersistentConfig._GetAutoSaveSlot()
    local showDetails = PersistentConfig.Settings.AutoSaveEnabled
        or (InputState and InputState.autoSaveEnableArmed)
        or (selectedEntry and (selectedEntry.key == "autosave" or selectedEntry.key == "autosave_slot" or
            selectedEntry.key == "autosave_interval"))

    if not showDetails then
        return nil
    end

    local lines = {}
    if InputState and InputState.autoSaveEnableArmed then
        lines[#lines + 1] = string.format("WARNING ENTER AGAIN TO USE SLOT %d", slot)
    elseif PersistentConfig.Settings.AutoSaveEnabled then
        lines[#lines + 1] = string.format("WARNING AUTOSAVE RESERVES SLOT %d", slot)
    else
        lines[#lines + 1] = string.format("AUTOSAVE CAN RESERVE SLOT %d", slot)
    end
    lines[#lines + 1] = string.format("FIRST USE BACKS UP game%d.sav", slot)
    lines[#lines + 1] = "BACKUP PATH Save\\AutoSaveBackups"
    return lines
end

local function ClampUnitInterval(value, fallback)
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
    local target = ClampRange(scale, SUBTITLE_FONT_SCALE_MIN, SUBTITLE_FONT_SCALE_MAX, 1.0)
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
        [PdaPages.STATS] = "STATS",
        [PdaPages.TARGET] = "TARGET",
        [PdaPages.SETTINGS] = "SETTINGS",
        [PdaPages.PRESETS] = "PRESETS",
        [PdaPages.QUEUE] = "QUEUE",
        [PdaPages.COMMAND] = "COMMAND",
    }
    local parts = { "PDA" }
    for page = 1, PdaPages.COUNT do
        local label = labels[page]
        if page == activePage then
            table.insert(parts, "[" .. label .. "]")
        else
            table.insert(parts, label)
        end
    end
    return "**BATTLEZONE PDA**\n" .. table.concat(parts, "  ")
end

local function FormatHotkeyValue(value, key)
    if not key or key == "" then
        return value
    end
    return string.format("%s (%s)", value, key)
end

local function AppendPdaNavHints(lines)
    table.insert(lines, "")
    table.insert(lines, "ARROWS MOVE")
    table.insert(lines, "ENTER ACTION")
    table.insert(lines, "[ / ] SWITCH PAGE")
end

local function GetPdaLayoutMetrics(page)
    local width, height = 1920, 1080
    local uiScale = 2
    local activePage = ClampIndex(page or (InputState and InputState.pdaPage) or PdaPages.STATS, 1, PdaPages.COUNT,
        PdaPages.STATS)
    local fontScale = GetPdaFontScale()

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

    local function Clamp(value, minimum, maximum)
        if value < minimum then return minimum end
        if value > maximum then return maximum end
        return value
    end

    local aspect = width / math.max(height, 1)
    local aspectScale = Clamp((16.0 / 9.0) / aspect, 0.80, 1.35)
    local uiScaleFactor = Clamp((uiScale / 2.0) ^ 0.45, 0.85, 1.45)
    local textScale = Clamp(0.30 * aspectScale * uiScaleFactor * fontScale, 0.22, 0.60)
    local wrapWidth = Clamp(0.31 * Clamp(1.0 / aspectScale, 0.9, 1.2) * uiScaleFactor * fontScale, 0.24, 0.70)
    local panelX = Clamp(0.01, 0.0, math.max(0.0, 1.0 - wrapWidth))

    return {
        textScale = textScale,
        wrapWidth = wrapWidth,
        panelX = panelX,
        paddingX = 6.0 * fontScale,
        paddingY = 5.0 * fontScale,
        opacity = ClampUnitInterval(PersistentConfig.Settings.PdaOpacity, 1.0),
        feedbackTextScale = Clamp(textScale * 0.86, 0.20, 0.46),
        feedbackY = 0.90,
    }
end

local EXPERIMENTAL_OVERLAY = {
    overlay = "cr_experimental_overlay",
    root = "cr_experimental_overlay_root",
    text = "cr_experimental_overlay_text",
}

local function DestroyExperimentalOverlay()
    if not exu then
        return
    end

    if exu.HideOverlay then
        pcall(exu.HideOverlay, EXPERIMENTAL_OVERLAY.overlay)
    end
    if exu.RemoveOverlayElementChild then
        pcall(exu.RemoveOverlayElementChild, EXPERIMENTAL_OVERLAY.root, EXPERIMENTAL_OVERLAY.text)
    end
    if exu.RemoveOverlay2D then
        pcall(exu.RemoveOverlay2D, EXPERIMENTAL_OVERLAY.overlay, EXPERIMENTAL_OVERLAY.root)
    end
    if exu.DestroyOverlayElement then
        pcall(exu.DestroyOverlayElement, EXPERIMENTAL_OVERLAY.text)
        pcall(exu.DestroyOverlayElement, EXPERIMENTAL_OVERLAY.root)
    end
    if exu.DestroyOverlay then
        pcall(exu.DestroyOverlay, EXPERIMENTAL_OVERLAY.overlay)
    end
end

local function TryCreateExperimentalOverlay()
    if not exu or not exu.CreateOverlay or not exu.CreateOverlayElement or not exu.AddOverlay2D then
        return false
    end

    DestroyExperimentalOverlay()

    local layout = GetPdaLayoutMetrics(PdaPages.STATS)
    local metricsMode = (exu.OVERLAY_METRICS and exu.OVERLAY_METRICS.RELATIVE) or 0
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

    SafeCall(exu.CreateOverlay, EXPERIMENTAL_OVERLAY.overlay)
    SafeCall(exu.CreateOverlayElement, "Panel", EXPERIMENTAL_OVERLAY.root)
    SafeCall(exu.CreateOverlayElement, "TextArea", EXPERIMENTAL_OVERLAY.text)
    SafeCall(exu.AddOverlay2D, EXPERIMENTAL_OVERLAY.overlay, EXPERIMENTAL_OVERLAY.root)
    SafeCall(exu.AddOverlayElementChild, EXPERIMENTAL_OVERLAY.root, EXPERIMENTAL_OVERLAY.text)
    SafeCall(exu.SetOverlayZOrder, EXPERIMENTAL_OVERLAY.overlay, 640)

    SafeCall(exu.SetOverlayMetricsMode, EXPERIMENTAL_OVERLAY.root, metricsMode)
    SafeCall(exu.SetOverlayPosition, EXPERIMENTAL_OVERLAY.root, layout.panelX, 0.03)
    SafeCall(exu.SetOverlayDimensions, EXPERIMENTAL_OVERLAY.root, math.max(layout.wrapWidth, 0.24), 0.08)

    SafeCall(exu.SetOverlayMetricsMode, EXPERIMENTAL_OVERLAY.text, metricsMode)
    SafeCall(exu.SetOverlayPosition, EXPERIMENTAL_OVERLAY.text, 0.0, 0.0)
    SafeCall(exu.SetOverlayDimensions, EXPERIMENTAL_OVERLAY.text, math.max(layout.wrapWidth, 0.24), 0.08)
    SafeCall(exu.SetOverlayTextFont, EXPERIMENTAL_OVERLAY.text, "BZONE")
    SafeCall(exu.SetOverlayTextCharHeight, EXPERIMENTAL_OVERLAY.text, 0.03)
    SafeCall(exu.SetOverlayColor, EXPERIMENTAL_OVERLAY.text, 0.18, 0.92, 0.18, 1.0)
    SafeCall(exu.SetOverlayCaption, EXPERIMENTAL_OVERLAY.text, "EXPERIMENTAL OGRE OVERLAY")
    SafeCall(exu.ShowOverlayElement, EXPERIMENTAL_OVERLAY.root)
    SafeCall(exu.ShowOverlayElement, EXPERIMENTAL_OVERLAY.text)
    SafeCall(exu.ShowOverlay, EXPERIMENTAL_OVERLAY.overlay)

    if ok then
        Log("PersistentConfig: Experimental EXU overlay probe created.")
    end

    return ok
end

local function ShowPdaFeedback(msg, r, g, b, duration)
    if subtitles and subtitles.set_channel_layout and subtitles.submit_to then
        local colorPreset = GetPdaColorPreset()
        local layout = GetPdaLayoutMetrics(InputState and InputState.pdaPage or PdaPages.SETTINGS)
        subtitles.set_channel_layout(PDA_FEEDBACK_CHANNEL, layout.panelX, layout.feedbackY, 0.0, 1.0, layout.feedbackTextScale,
            layout.wrapWidth, layout.paddingX, layout.paddingY, layout.opacity)
        subtitles.clear_queue(PDA_FEEDBACK_CHANNEL)
        if subtitles.clear_current then
            subtitles.clear_current(PDA_FEEDBACK_CHANNEL)
        end
        subtitles.submit_to(PDA_FEEDBACK_CHANNEL, msg, duration or 2.5, r or colorPreset.r, g or colorPreset.g, b or colorPreset.b)
        return
    end

    if subtitles and subtitles.submit then
        subtitles.clear_queue()
        if subtitles.clear_current then subtitles.clear_current() end
        subtitles.set_opacity(ClampUnitInterval(PersistentConfig.Settings.SubtitleOpacity, 0.5))
        subtitles.submit(msg, duration or 2.5, r or 1.0, g or 1.0, b or 1.0)
    end
end

local function ShowWeaponStats(msg, duration)
    if subtitles and subtitles.set_channel_layout and subtitles.submit_to then
        local layout = GetPdaLayoutMetrics(InputState and InputState.pdaPage or PdaPages.STATS)
        local colorPreset = GetPdaColorPreset()

        -- Anchor the panel on the left-middle of the screen with left alignment.
        subtitles.set_channel_layout(WEAPON_STATS_CHANNEL, layout.panelX, 0.50, 0.0, 0.5, layout.textScale, layout.wrapWidth,
            layout.paddingX, layout.paddingY, layout.opacity)
        subtitles.clear_queue(WEAPON_STATS_CHANNEL)
        if subtitles.clear_current then
            subtitles.clear_current(WEAPON_STATS_CHANNEL)
        end
        subtitles.submit_to(WEAPON_STATS_CHANNEL, msg, duration or 2.4, colorPreset.r, colorPreset.g, colorPreset.b)
    else
        local colorPreset = GetPdaColorPreset()
        ShowFeedback(msg, colorPreset.r, colorPreset.g, colorPreset.b, duration or 2.4, false)
    end
end

local function ClearWeaponStats()
    if subtitles and subtitles.clear_queue then
        subtitles.clear_queue(WEAPON_STATS_CHANNEL)
    end
    if subtitles and subtitles.clear_current then
        subtitles.clear_current(WEAPON_STATS_CHANNEL)
    end
end

local function ClearPdaFeedback()
    if subtitles and subtitles.clear_queue then
        subtitles.clear_queue(PDA_FEEDBACK_CHANNEL)
    end
    if subtitles and subtitles.clear_current then
        subtitles.clear_current(PDA_FEEDBACK_CHANNEL)
    end
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
    nextWeaponHudCheck = 0.0,
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

-- Beam Definitions
local BeamModes = {
    [1] = { Inner = 0.2, Outer = 0.4, Multiplier = 2.0 }, -- Focused (Brighter/Longer)
    [2] = { Inner = 1.1, Outer = 1.5, Multiplier = 0.8 }  -- Wide (Wider/Shorter)
}

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

local function GetPlayerTeamNum()
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
        local mortarFlat = (PRESET_SURCHARGE_CONFIG and PRESET_SURCHARGE_CONFIG.mortarFlat) or 1.0
        total = total + (mortarUpgrades * mortarFlat)
    end

    if #manualExtras > 0 then
        table.sort(manualExtras, function(a, b) return a > b end)
        local multipliers = (PRESET_SURCHARGE_CONFIG and PRESET_SURCHARGE_CONFIG.multipliers) or { 0.5, 0.25 }
        local tailMultiplier = (PRESET_SURCHARGE_CONFIG and PRESET_SURCHARGE_CONFIG.tailMultiplier) or 0.1
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

local function GetInstalledWeaponMask(h)
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

local function FormatWholeNumber(value)
    if value == nil then return "n/a" end
    return tostring(math.floor(value + 0.5))
end

local function FormatDps(value)
    if value == nil then return "n/a" end
    if value >= 100 then
        return FormatWholeNumber(value)
    end
    return string.format("%.1f", value)
end

local function BuildMeterBar(label, fraction, currentValue, maxValue)
    local width = 28
    local clamped = math.max(0.0, math.min(1.0, fraction or 0.0))
    local filled = math.floor((clamped * width) + 0.5)
    if filled > width then filled = width end
    local empty = width - filled
    local currentText = currentValue and FormatWholeNumber(currentValue) or nil
    local maxText = maxValue and FormatWholeNumber(maxValue) or nil
    local numericText = ""
    if currentText and maxText then
        numericText = " " .. currentText .. "/" .. maxText
    end
    return string.format("%-4s [%s%s] %3d%%%s", label, string.rep("=", filled), string.rep(".", empty),
        math.floor((clamped * 100.0) + 0.5), numericText)
end

local function FormatWeaponRangeText(weaponStats, effectiveRange)
    local minRange = weaponStats and weaponStats.rangeMin or nil
    local maxRange = weaponStats and weaponStats.rangeMax or nil
    local baseRange = weaponStats and weaponStats.range or nil
    local rangeText = FormatWholeNumber(baseRange)

    if minRange and maxRange and math.abs(maxRange - minRange) >= 5.0 then
        rangeText = FormatWholeNumber(minRange) .. "-" .. FormatWholeNumber(maxRange)
    end

    if weaponStats and weaponStats.ballistic and effectiveRange and baseRange and
        math.abs(effectiveRange - baseRange) >= 5.0 then
        rangeText = rangeText .. ">" .. FormatWholeNumber(effectiveRange)
    end

    return rangeText
end

local function FormatWeaponDamageText(weaponStats)
    if not weaponStats then return "n/a" end
    if weaponStats.damageMin and weaponStats.damageMax and math.abs(weaponStats.damageMax - weaponStats.damageMin) >= 1.0 then
        return FormatWholeNumber(weaponStats.damageMin) .. "-" .. FormatWholeNumber(weaponStats.damageMax)
    end
    return FormatWholeNumber(weaponStats.damage)
end

local function FormatWeaponDpsText(weaponStats)
    if not weaponStats then return "n/a" end
    if weaponStats.dpsMin and weaponStats.dpsMax and math.abs(weaponStats.dpsMax - weaponStats.dpsMin) >= 0.1 then
        return FormatDps(weaponStats.dpsMin) .. "-" .. FormatDps(weaponStats.dpsMax)
    end
    return FormatDps(weaponStats.dps)
end

local function FormatWeaponSplashText(weaponStats)
    if not weaponStats then return nil end

    local minRadius = weaponStats.splashRadiusMin or weaponStats.splashRadius
    local maxRadius = weaponStats.splashRadiusMax or weaponStats.splashRadius
    if not maxRadius or maxRadius <= 0.0 then
        return nil
    end
    if minRadius and math.abs(maxRadius - minRadius) >= 1.0 then
        return FormatWholeNumber(minRadius) .. "-" .. FormatWholeNumber(maxRadius) .. "m"
    end
    return FormatWholeNumber(maxRadius) .. "m"
end

local function FormatWeaponShotsLeftText(weaponStats, currentAmmo)
    if not weaponStats then return nil end

    local function ComputeShots(ammoCost)
        if ammoCost == nil then
            return nil
        end
        ammoCost = tonumber(ammoCost) or 0.0
        if ammoCost <= 0.001 then
            return math.huge
        end
        if type(currentAmmo) ~= "number" then
            return nil
        end
        return math.max(0, math.floor((currentAmmo / ammoCost) + 0.0001))
    end

    local minShots = ComputeShots(weaponStats.ammoCostMax or weaponStats.ammoCost)
    local maxShots = ComputeShots(weaponStats.ammoCostMin or weaponStats.ammoCost)
    if minShots == nil and maxShots == nil then
        return nil
    end

    local function FormatShots(value)
        if value == math.huge then
            return "INF"
        end
        if value == nil then
            return "n/a"
        end
        return tostring(value)
    end

    if minShots == maxShots then
        return FormatShots(minShots)
    end

    if minShots == nil then
        return FormatShots(maxShots)
    end
    if maxShots == nil then
        return FormatShots(minShots)
    end

    local low = math.min(minShots, maxShots)
    local high = math.max(minShots, maxShots)
    return FormatShots(low) .. "-" .. FormatShots(high)
end

local function BuildChargeSummaryText(weaponStats)
    local levels = weaponStats and weaponStats.chargeLevels or nil
    if not levels or #levels <= 0 then return nil end

    local picks = {}
    local candidateIndices = { 1, math.floor((#levels + 1) * 0.5), #levels }
    local currentChargeLevel = weaponStats and weaponStats.currentChargeLevel or nil
    for _, idx in ipairs(candidateIndices) do
        idx = math.max(1, math.min(#levels, idx))
        if not picks[idx] then
            picks[idx] = true
        end
    end
    if currentChargeLevel then
        for idx, level in ipairs(levels) do
            if (level.chargeIndex or idx) == currentChargeLevel then
                picks[idx] = true
                break
            end
        end
    end

    local parts = { "  CHG" }
    for idx = 1, #levels do
        if picks[idx] then
            local level = levels[idx]
            local statText = FormatWholeNumber(level.damage)
            if level.dps then
                statText = statText .. "/" .. FormatDps(level.dps)
            end
            local levelLabel = string.format("L%d", level.chargeIndex or idx)
            if currentChargeLevel and (level.chargeIndex or idx) == currentChargeLevel then
                levelLabel = levelLabel .. "*"
            end
            table.insert(parts, string.format("%s %s", levelLabel, statText))
        end
    end

    return table.concat(parts, "  ")
end

local function AppendWeaponStatsLines(lines, h, installedMask, activeMask, compareTarget, comparePosition, compareDistance)
    local hardpointCount = 0
    local shooterPos = type(GetPosition) == "function" and GetPosition(h) or nil
    local currentAmmo = type(GetCurAmmo) == "function" and GetCurAmmo(h) or nil

    for slot = 0, 4 do
        if IsMaskBitSet(installedMask, slot) then
            local weapon = CleanString(GetWeaponClass(h, slot))
            if weapon ~= "" then
                hardpointCount = hardpointCount + 1
                local weaponStats = GetDisplayedWeaponStats(h, weapon, GetWeaponStats(weapon) or {}) or {}
                local effectiveRange = weaponStats.range
                local distanceForCompare = compareDistance
                if compareTarget and IsValid(compareTarget) then
                    local targetPos = type(GetPosition) == "function" and GetPosition(compareTarget) or nil
                    effectiveRange = GetEffectiveWeaponRangeMeters(weaponStats, shooterPos, targetPos) or weaponStats.range
                    distanceForCompare = GetHorizontalDistanceBetweenHandles(h, compareTarget) or compareDistance
                elseif comparePosition then
                    effectiveRange = GetEffectiveWeaponRangeMeters(weaponStats, shooterPos, comparePosition) or weaponStats.range
                    distanceForCompare = GetHorizontalDistanceBetweenPositions(shooterPos, comparePosition) or compareDistance
                end
                local status = "  "
                if distanceForCompare then
                    if effectiveRange then
                        status = (distanceForCompare <= effectiveRange) and "+ " or "- "
                    else
                        status = "? "
                    end
                end
                if activeMask and IsMaskBitSet(activeMask, slot) then
                    status = status:sub(1, 1) .. "*"
                end

                local rangeText = FormatWeaponRangeText(weaponStats, effectiveRange)

                table.insert(lines, string.format("S%d %s %s", slot + 1, status, weaponStats.displayName or weapon))
                table.insert(lines,
                    string.format("  RNG %sm  DMG %s  DPS %s", rangeText,
                        FormatWeaponDamageText(weaponStats), FormatWeaponDpsText(weaponStats)))
                local shotsText = FormatWeaponShotsLeftText(weaponStats, currentAmmo)
                local splashText = FormatWeaponSplashText(weaponStats)
                if shotsText or splashText then
                    local detailParts = {}
                    if shotsText then
                        detailParts[#detailParts + 1] = "SHOTS " .. shotsText
                    end
                    if splashText then
                        detailParts[#detailParts + 1] = "AOE " .. splashText
                    end
                    table.insert(lines, "  " .. table.concat(detailParts, "  "))
                end
                local chargeSummary = BuildChargeSummaryText(weaponStats)
                if chargeSummary then
                    table.insert(lines, chargeSummary)
                end
            end
        end
    end

    if hardpointCount == 0 then
        table.insert(lines, "NONE")
    end

    return hardpointCount
end

local function GetPrimaryReticleLine(player)
    if not IsValid(player) then return nil end

    local activeMask = GetCurrentWeaponMask(player)
    local installedMask = GetInstalledWeaponMask(player)
    local searchMask = (activeMask and activeMask > 0) and activeMask or installedMask
    if not searchMask or searchMask <= 0 then
        return nil
    end

    for slot = 0, 4 do
        if IsMaskBitSet(searchMask, slot) then
            local weapon = CleanString(GetWeaponClass(player, slot))
            if weapon ~= "" then
                local displayedStats = GetDisplayedWeaponStats(player, weapon, GetWeaponStats(weapon) or {}) or {}
                local reticle = GetWeaponReticleName(weapon, displayedStats.currentChargeLevel)
                if reticle and reticle ~= "" then
                    return string.format("RET  S%d %s", slot + 1, reticle)
                end
            end
        end
    end

    return nil
end

local function DescribeAimMode(aimInfo)
    if not aimInfo then
        return "NO TARGET"
    end
    if aimInfo.source == "target" then
        return "TARGET LOCK"
    end
    if aimInfo.source == "reticle_object" then
        return "SMART RETICLE"
    end
    if aimInfo.source == "reticle_pos" then
        return "GROUND RETICLE"
    end
    return "TARGET"
end

local function BuildStatsPageText(player, mask)
    local lines = { BuildPdaHeader(PdaPages.STATS) }
    local speed = math.floor(GetPlayerSpeedMeters(player) + 0.5)
    local unitName = GetVehicleDisplayName(player) or "Unknown"
    local playerHealth = (type(GetHealth) == "function") and (GetHealth(player) or 0.0) or 0.0
    local playerAmmo = (type(GetAmmo) == "function") and (GetAmmo(player) or 0.0) or 0.0
    local curHealth = type(GetCurHealth) == "function" and GetCurHealth(player) or nil
    local maxHealth = type(GetMaxHealth) == "function" and GetMaxHealth(player) or nil
    local curAmmo = type(GetCurAmmo) == "function" and GetCurAmmo(player) or nil
    local maxAmmo = type(GetMaxAmmo) == "function" and GetMaxAmmo(player) or nil
    local installedMask = GetInstalledWeaponMask(player)

    table.insert(lines, "UNIT " .. unitName)
    table.insert(lines, "SPD  " .. tostring(speed) .. "m/s")
    table.insert(lines, BuildMeterBar("HULL", playerHealth, curHealth, maxHealth))
    table.insert(lines, BuildMeterBar("AMMO", playerAmmo, curAmmo, maxAmmo))
    table.insert(lines, "")
    table.insert(lines, "HARDPOINTS")
    table.insert(lines, "LEGEND * ACTIVE")

    local hardpointCount = AppendWeaponStatsLines(lines, player, installedMask, mask, nil, nil, nil)
    table.insert(lines, "TOTAL " .. tostring(hardpointCount))
    AppendPdaNavHints(lines)
    return table.concat(lines, "\n")
end

local function BuildTargetPageText(player)
    local lines = { BuildPdaHeader(PdaPages.TARGET) }
    local aimInfo = GetAimInfo(player, true)
    local target = aimInfo and aimInfo.handle or nil
    local targetDistance = aimInfo and aimInfo.distance or nil
    local aimPosition = aimInfo and aimInfo.position or nil
    local reticleLine = GetPrimaryReticleLine(player)

    table.insert(lines, "MODE " .. DescribeAimMode(aimInfo))
    if reticleLine then
        table.insert(lines, reticleLine)
    end

    if not aimInfo or not targetDistance then
        table.insert(lines, "NO TARGET")
        table.insert(lines, "Aim at a unit to inspect it.")
        AppendPdaNavHints(lines)
        return table.concat(lines, "\n")
    end

    if not target and aimPosition then
        local playerPos = type(GetPosition) == "function" and GetPosition(player) or nil
        local deltaY = playerPos and ((aimPosition.y or 0.0) - (playerPos.y or 0.0)) or 0.0
        table.insert(lines, "UNIT AIM POINT")
        table.insert(lines, "ROLE TERRAIN")
        table.insert(lines, "DST  " .. tostring(math.floor(targetDistance + 0.5)) .. "m")
        table.insert(lines, "ELV  " .. tostring(math.floor(deltaY + (deltaY >= 0 and 0.5 or -0.5))) .. "m")
        table.insert(lines,
            string.format("POS  %d %d %d", math.floor((aimPosition.x or 0.0) + 0.5), math.floor((aimPosition.y or 0.0) + 0.5),
                math.floor((aimPosition.z or 0.0) + 0.5)))
        table.insert(lines, "Reticle position")
        AppendPdaNavHints(lines)
        return table.concat(lines, "\n")
    end

    local speed = math.floor(GetPlayerSpeedMeters(target) + 0.5)
    local unitName = GetVehicleDisplayName(target) or "Unknown"
    local role = CleanString((type(GetClassLabel) == "function" and GetClassLabel(target)) or "")
    local targetHealth = (type(GetHealth) == "function") and (GetHealth(target) or 0.0) or 0.0
    local targetAmmo = (type(GetAmmo) == "function") and (GetAmmo(target) or 0.0) or 0.0
    local curHealth = type(GetCurHealth) == "function" and GetCurHealth(target) or nil
    local maxHealth = type(GetMaxHealth) == "function" and GetMaxHealth(target) or nil
    local curAmmo = type(GetCurAmmo) == "function" and GetCurAmmo(target) or nil
    local maxAmmo = type(GetMaxAmmo) == "function" and GetMaxAmmo(target) or nil
    local installedMask = GetInstalledWeaponMask(target)
    local activeMask = GetCurrentWeaponMask(target)
    local closureRate, eta = GetTargetClosureInfo(player, target, targetDistance)

    table.insert(lines, "UNIT " .. unitName)
    if role ~= "" then
        table.insert(lines, "ROLE " .. role)
    end
    table.insert(lines, "DST  " .. tostring(math.floor(targetDistance + 0.5)) .. "m")
    table.insert(lines, "SPD  " .. tostring(speed) .. "m/s")
    table.insert(lines, "CLS  " .. (closureRate and tostring(math.floor(math.max(0.0, closureRate) + 0.5)) .. "m/s" or "--") ..
        "  ETA " .. (eta and string.format("%.1fs", eta) or "--"))
    table.insert(lines, "CLS = closing rate")
    table.insert(lines, "HARDPOINTS")
    table.insert(lines, "LEGEND + IN RNG  - OUT  * ACTIVE")

    local hardpointCount = AppendWeaponStatsLines(lines, target, installedMask, activeMask, player, nil, targetDistance)
    table.insert(lines, "TOTAL " .. tostring(hardpointCount))
    table.insert(lines, BuildMeterBar("AMMO", targetAmmo, curAmmo, maxAmmo))
    table.insert(lines, BuildMeterBar("HULL", targetHealth, curHealth, maxHealth))
    AppendPdaNavHints(lines)
    return table.concat(lines, "\n")
end

local function BuildSettingsPageText()
    local lines = { BuildPdaHeader(PdaPages.SETTINGS) }
    local settingsEntries = (GetSettingsPageEntries and GetSettingsPageEntries()) or {}
    local count = math.max(#settingsEntries, 1)
    local selection = ClampIndex(InputState.pdaSettingsIndex, 1, count, 1)
    local visibleRows = 10
    local startIndex = math.max(1, math.min(selection - math.floor(visibleRows / 2), math.max(1, count - visibleRows + 1)))
    local endIndex = math.min(count, startIndex + visibleRows - 1)

    table.insert(lines, string.format("ITEM %02d/%02d", selection, count))

    if #settingsEntries == 0 then
        table.insert(lines, "NO SETTINGS AVAILABLE")
    else
        for index = startIndex, endIndex do
            local entry = settingsEntries[index]
            local prefix = (selection == index) and ">" or ((entry and entry.warning) and "!" or " ")
            table.insert(lines, string.format("%s %-12s %s", prefix, entry.label, entry.value))
        end
    end

    local selectedEntry = settingsEntries[selection]
    local autoSaveWarningLines = PersistentConfig._BuildAutoSaveWarningLines(selectedEntry)
    if autoSaveWarningLines and #autoSaveWarningLines > 0 then
        table.insert(lines, "")
        for _, line in ipairs(autoSaveWarningLines) do
            table.insert(lines, line)
        end
    end

    table.insert(lines, "")
    table.insert(lines, string.format("SHOWING %02d-%02d OF %02d", startIndex, endIndex, count))
    table.insert(lines, "UP/DOWN SELECT")
    table.insert(lines, "LEFT/RIGHT CHANGE")
    table.insert(lines, (selectedEntry and selectedEntry.actionHint) or "ENTER ACTION")
    table.insert(lines, "[ / ] SWITCH PAGE")
    return table.concat(lines, "\n")
end

local function BuildPresetPageText()
    local lines = { BuildPdaHeader(PdaPages.PRESETS) }
    local context = GetPresetPageContext()

    if not context.available then
        table.insert(lines, "ARMORY NOT AVAILABLE")
        table.insert(lines, "Build an Armory to edit")
        table.insert(lines, "unit upgrade presets.")
        AppendPdaNavHints(lines)
        return table.concat(lines, "\n")
    end

    if #context.producerKinds == 0 then
        table.insert(lines, "NO PRODUCERS AVAILABLE")
        table.insert(lines, "Recycler/Factory missing.")
        AppendPdaNavHints(lines)
        return table.concat(lines, "\n")
    end

    local selectedEntry = context.selectedEntry
    local rowIndex = ClampIndex(InputState.presetRow, 1, math.max(#context.rows, 1), 1)

    local function RowPrefix(index)
        return (rowIndex == index) and ">" or " "
    end

    table.insert(lines, string.format("%s %-11s %s", RowPrefix(1), "PRODUCER", context.producerInfo.label))
    if selectedEntry then
        table.insert(lines, string.format("%s %-11s %s", RowPrefix(2), "UNIT", selectedEntry.displayName))
        local unitPreset = GetUnitPresetRecord(selectedEntry.odf)
        for slotOffset, slotInfo in ipairs(selectedEntry.slots or {}) do
            local option = GetPresetSlotOption(slotInfo, context.armoryOptions, unitPreset)
            table.insert(lines,
                string.format("%s S%d %-8s %s", RowPrefix(2 + slotOffset), slotInfo.slotIndex,
                    GetHardpointCategoryLabel(slotInfo.category), FormatPresetSlotValue(slotInfo, option)))
        end
        local surchargeRow = 2 + #(selectedEntry.slots or {}) + 1
        table.insert(lines,
            string.format("%s %-11s +%s", RowPrefix(surchargeRow), "SURCHARGE",
                FormatWholeNumber(GetPresetSurchargeForEntry(selectedEntry)) .. " scrap"))
    else
        table.insert(lines, string.format("%s %-11s %s", RowPrefix(2), "UNIT", "NONE"))
    end

    local selectedRow = context.rows and context.rows[rowIndex] or nil
    if selectedRow and selectedRow.kind == "slot" and selectedEntry then
        local slotInfo = selectedRow.slotInfo
        local unitPreset = GetUnitPresetRecord(selectedEntry.odf)
        local option = GetPresetSlotOption(slotInfo, context.armoryOptions, unitPreset)
        local selectedWeapon = option and option.weaponName or ""
        local stockWeapon = slotInfo and slotInfo.stockWeapon or ""
        if selectedWeapon == "" then
            selectedWeapon = stockWeapon
        end
        local stockStats = (stockWeapon ~= "" and GetWeaponStats(stockWeapon)) or nil
        local selectedStats = (selectedWeapon ~= "" and GetWeaponStats(selectedWeapon)) or nil

        local function FormatDelta(value, unit, decimals)
            if value == nil then return "n/a" end
            local format = "%+.0f"
            if decimals and decimals > 0 then
                format = "%+." .. tostring(decimals) .. "f"
            end
            return string.format(format, value) .. (unit or "")
        end

        local baseSurcharge = math.floor(GetPresetSurchargeForEntry(selectedEntry) + 0.5)
        local original = unitPreset and unitPreset[slotInfo.slotIndex] or nil
        if unitPreset then
            unitPreset[slotInfo.slotIndex] = nil
        end
        local withoutSurcharge = math.floor(GetPresetSurchargeForEntry(selectedEntry) + 0.5)
        if unitPreset then
            unitPreset[slotInfo.slotIndex] = original
        end
        local deltaCost = math.max(0, baseSurcharge - withoutSurcharge)

        local dpsDelta = (selectedStats and selectedStats.dps or nil) and
            ((selectedStats.dps or 0.0) - (stockStats and stockStats.dps or 0.0)) or nil
        local rangeDelta = (selectedStats and selectedStats.range or nil) and
            ((selectedStats.range or 0.0) - (stockStats and stockStats.range or 0.0)) or nil
        local delayDelta = (selectedStats and selectedStats.shotDelay or nil) and
            ((selectedStats.shotDelay or 0.0) - (stockStats and stockStats.shotDelay or 0.0)) or nil

        table.insert(lines, "")
        table.insert(lines, string.format("COMPARE S%d", slotInfo.slotIndex))
        table.insert(lines, string.format("COST +%d scrap", deltaCost))
        table.insert(lines, string.format("DPS  %s", FormatDelta(dpsDelta, "", 1)))
        table.insert(lines, string.format("RNG  %s", FormatDelta(rangeDelta, "m", 0)))
        table.insert(lines, string.format("DEL  %s", FormatDelta(delayDelta, "s", 2)))
    end

    table.insert(lines, "")
    table.insert(lines, "Preset applies after build.")
    table.insert(lines, "No refunds for downgrades.")
    table.insert(lines, "UP/DOWN SELECT  LEFT/RIGHT CHANGE")
    table.insert(lines, "ENTER ACTION")
    table.insert(lines, "[ / ] SWITCH PAGE")
    return table.concat(lines, "\n")
end

local function BuildQueuePageText()
    local lines = { BuildPdaHeader(PdaPages.QUEUE) }
    local context = GetQueuePageContext()

    if not context.available then
        table.insert(lines, "")
        table.insert(lines, "UNDEPLOYED")
        AppendPdaNavHints(lines)
        return table.concat(lines, "\n")
    end

    local rowIndex = ClampIndex(InputState.queueRow, 1, math.max(#context.rows, 1), 1)
    local queue = GetProducerQueueState(context.producerInfo.kindIndex)

    local function RowPrefix(index)
        return (rowIndex == index) and ">" or " "
    end

    local queueItemName = "NONE"
    if #context.unitEntries > 0 then
        local queueEntry = context.unitEntries[ClampIndex(queue.itemIndex or 1, 1, #context.unitEntries, 1)]
        queueItemName = queueEntry and (queueEntry.displayName or queueEntry.odf) or "NONE"
    end

    table.insert(lines, string.format("%s %-11s %s", RowPrefix(1), "PRODUCER", context.producerInfo.label))
    table.insert(lines, string.format("%s %-11s %s", RowPrefix(2), "QUEUE ITEM", queueItemName))
    table.insert(lines, string.format("%s %-11s %d", RowPrefix(3), "QUEUE COUNT", queue.count or 0))
    table.insert(lines, string.format("%s %-11s %s", RowPrefix(4), "QUEUE", queue.status or "Queue Off"))

    table.insert(lines, "")
    table.insert(lines, "ENTER TO LOCK/UNLOCK")
    table.insert(lines, "UP/DOWN SELECT  LEFT/RIGHT CHANGE")
    table.insert(lines, "[ / ] SWITCH PAGE")
    return table.concat(lines, "\n")
end

local function RefreshWeaponHud()
    InputState.lastWeaponMask = nil
    InputState.lastWeaponPlayer = nil
    InputState.lastWeaponText = nil
    InputState.lastWeaponTarget = nil
    InputState.nextWeaponHudCheck = 0.0
end

local function GetAnyGameKey(names)
    if not exu or not exu.GetGameKey then return false end
    for _, name in ipairs(names) do
        local ok, pressed = pcall(exu.GetGameKey, name)
        if ok and pressed then
            return true
        end
    end
    return false
end

local function NormalizeGameKey(key)
    if type(key) ~= "string" then return "" end
    return string.upper(CleanString(key))
end

local function QueueGameKey(key)
    local normalized = NormalizeGameKey(key)
    if normalized == "" then return end
    InputState.pendingGameKeys = InputState.pendingGameKeys or {}
    table.insert(InputState.pendingGameKeys, normalized)
    if #InputState.pendingGameKeys > 32 then
        table.remove(InputState.pendingGameKeys, 1)
    end
end

local function ConsumePendingGameKeyMatch(variants)
    local queue = InputState.pendingGameKeys
    if not queue or #queue == 0 then
        return false
    end
    for index, key in ipairs(queue) do
        for _, variant in ipairs(variants) do
            if key == variant then
                table.remove(queue, index)
                return true
            end
        end
    end
    return false
end

local function ConsumePendingNumberKey()
    local queue = InputState.pendingGameKeys
    if not queue or #queue == 0 then
        return nil
    end
    for index, key in ipairs(queue) do
        local digit = nil
        if #key == 1 and key:match("%d") then
            digit = tonumber(key)
        else
            local match = key:match("NUMPAD(%d)") or key:match("KP(%d)") or key:match("NUM(%d)")
            if match then
                digit = tonumber(match)
            end
        end
        if digit and digit >= 1 and digit <= 9 then
            table.remove(queue, index)
            return digit
        end
    end
    return nil
end

local function GetSelectedProducerHandle(team)
    if type(IsSelected) ~= "function" then return nil end
    for kindIndex, _ in ipairs(PresetProducerKinds) do
        local producer = GetProducerHandleForKind(kindIndex, team)
        if IsValid(producer) and IsSelected(producer) then
            return producer
        end
    end
    return nil
end

local function GetBuildEntryForProducer(producer, index)
    if not IsValid(producer) or not index then return nil end
    local entries = GetProducerBuildEntries(producer)
    return entries and entries[index] or nil
end

GetProducerQueueState = function(kindIndex)
    InputState.producerQueues = InputState.producerQueues or {}
    if not InputState.producerQueues[kindIndex] then
        InputState.producerQueues[kindIndex] = {
            itemIndex = 1,
            count = 0,
            remaining = 0,
            unitOdf = "",
            status = "Queue Off",
            pendingIssue = nil,
            inProgress = false,
            locked = false,
        }
    end
    return InputState.producerQueues[kindIndex]
end

local function GetUnitBuildTimeSeconds(unitOdfName)
    if not unitOdfName or unitOdfName == "" then return 0.0 end
    PersistentConfig.UnitBuildTimeCache = PersistentConfig.UnitBuildTimeCache or {}
    local key = string.lower(unitOdfName)
    if PersistentConfig.UnitBuildTimeCache[key] ~= nil then
        return PersistentConfig.UnitBuildTimeCache[key]
    end
    local buildTime = 0.0
    if OpenODF and GetODFFloat then
        local odf = OpenODF(unitOdfName)
        if odf then
            local val, found = GetODFFloat(odf, nil, "buildTime", 0.0)
            if found then
                buildTime = val
            end
        end
    end
    PersistentConfig.UnitBuildTimeCache[key] = buildTime
    return buildTime
end

local function UpdateTeamScrapSnapshot(team)
    if type(GetScrap) ~= "function" then return nil end
    local current = GetScrap(team) or 0.0
    local last = InputState.lastTeamScrap[team]
    if last == nil then
        InputState.lastTeamScrap[team] = current
        return 0.0
    end
    InputState.lastTeamScrap[team] = current
    return last - current
end

local function StartPresetSurchargeForEntry(team, producer, entry)
    if not entry then return end
    local now = GetTime()
    local surcharge = math.floor(GetPresetSurchargeForEntry(entry) + 0.5)
    local applyAllowed = true
    local charged = false
    if surcharge > 0 and type(GetScrap) == "function" then
        local currentScrap = GetScrap(team)
        if currentScrap < surcharge then
            applyAllowed = false
            ShowFeedback("Not enough scrap for upgrades. Building stock loadout.", 1.0, 0.35, 0.35, 2.5, false, "pda")
        elseif type(AddScrap) == "function" then
            AddScrap(team, -surcharge)
            charged = true
        end
    end

    if surcharge > 0 or not applyAllowed then
        local buildTime = GetUnitBuildTimeSeconds(entry.odf)
        local expectedFinish = now + (buildTime or 0.0)
        table.insert(InputState.pendingBuilds, {
            producer = producer,
            team = team,
            unitOdf = entry.odf,
            unitKey = string.lower(CleanString(entry.odf or "")),
            surcharge = surcharge,
            charged = charged,
            applyAllowed = applyAllowed,
            startedAt = now,
            expectedFinishAt = expectedFinish,
        })
    end
end

local function RecordBuildKeyIfPressed(team)
    local keyIndex = ConsumePendingNumberKey()
    if not keyIndex then return end
    local producer = GetSelectedProducerHandle(team)
    if not producer then return end
    InputState.lastBuildKey = {
        producer = producer,
        keyIndex = keyIndex,
        time = GetTime(),
        team = team,
    }
end

local function TryStartBuildForProducer(producer, team, scrapDelta)
    local keyInfo = InputState.lastBuildKey
    if not keyInfo or keyInfo.producer ~= producer or keyInfo.team ~= team then return end
    local now = GetTime()
    if (now - (keyInfo.time or 0.0)) > (PRESET_BUILD_CONFIG.keyWindow or 0.5) then
        return
    end
    local entry = GetBuildEntryForProducer(producer, keyInfo.keyIndex)
    if not entry then return end

    local stockCost = entry.scrapCost or 0.0
    local tolerance = (PRESET_BUILD_CONFIG and PRESET_BUILD_CONFIG.scrapConfirmTolerance) or 0.5
    if type(scrapDelta) == "number" and stockCost > 0.0 then
        if scrapDelta < (stockCost - tolerance) then
            return
        end
    end

    StartPresetSurchargeForEntry(team, producer, entry)
    InputState.lastBuildKey = nil
end

local function UpdateProducerQueues(team)
    local now = GetTime()
    for kindIndex, _ in ipairs(PresetProducerKinds) do
        local producer = GetProducerHandleForKind(kindIndex, team)
        local queue = GetProducerQueueState(kindIndex)
        queue.handle = producer
        local entries = IsValid(producer) and GetProducerBuildEntries(producer) or {}
        local entryCount = #entries
        local selectedEntry = nil
        if entryCount == 0 then
            queue.itemIndex = 1
            queue.unitOdf = ""
            queue.status = "Queue Off"
            queue.remaining = 0
            queue.pendingIssue = nil
            queue.inProgress = false
            queue.count = 0
            queue.locked = false
        else
            queue.itemIndex = ClampIndex(queue.itemIndex, 1, entryCount, 1)
            selectedEntry = entries[queue.itemIndex]
            queue.unitOdf = selectedEntry and selectedEntry.odf or ""
        end

        if queue.count <= 0 then
            queue.remaining = 0
            queue.status = "Queue Off"
            queue.pendingIssue = nil
            queue.inProgress = false
            queue.locked = false
        elseif not IsValid(producer) then
            queue.status = "Queue Paused: Producer Missing"
        else
            if not queue.locked then
                queue.status = "Queue Ready: Press Enter"
            else
                if queue.pendingIssue and not IsBusy(producer) then
                    local window = (PRESET_BUILD_CONFIG and PRESET_BUILD_CONFIG.keyWindow) or 0.5
                    if (now - (queue.pendingIssue.time or 0.0)) > window then
                        queue.remaining = queue.remaining + 1
                        queue.pendingIssue = nil
                    end
                end

                if IsSelected(producer) then
                    queue.status = "Queue Paused: Prod Selected"
                elseif IsBusy(producer) then
                    if queue.inProgress then
                        queue.status = "Queue Building"
                    else
                        queue.status = "Queue Paused: Manual Build"
                    end
                else
                    if queue.remaining <= 0 then
                        queue.status = "Queue Complete"
                    else
                        local stockCost = selectedEntry and selectedEntry.scrapCost or 0.0
                        local pilotCost = selectedEntry and selectedEntry.pilotCost or 0.0
                        local lowScrap = type(GetScrap) == "function" and stockCost > 0.0 and GetScrap(team) < stockCost
                        local lowPilots = type(GetPilot) == "function" and pilotCost > 0.0 and GetPilot(team) < pilotCost
                        if lowScrap and lowPilots then
                            queue.status = "Queue Paused: Low Scrap/Pilots"
                        elseif lowScrap then
                            queue.status = "Queue Paused: Low Scrap"
                        elseif lowPilots then
                            queue.status = "Queue Paused: Low Pilots"
                        elseif not queue.pendingIssue then
                            if queue.unitOdf and queue.unitOdf ~= "" and type(Build) == "function" then
                                Build(producer, queue.unitOdf)
                                queue.pendingIssue = { unitOdf = queue.unitOdf, time = now }
                                queue.remaining = math.max(0, (queue.remaining or 0) - 1)
                                queue.status = "Queue Starting..."
                            end
                        else
                            queue.status = "Queue Starting..."
                        end
                    end
                end
            end
            if queue.count > 0 then
                local remaining = math.max(0, queue.remaining or 0)
                queue.status = string.format("%s (%d/%d)", queue.status, remaining, queue.count)
            end
        end
    end
end

local function UpdateProducerBuildState(team, scrapDelta)
    local busyState = InputState.producerBusyState
    for kindIndex, _ in ipairs(PresetProducerKinds) do
        local producer = GetProducerHandleForKind(kindIndex, team)
        if IsValid(producer) then
            local isBusy = IsBusy(producer)
            local wasBusy = busyState[producer] or false
            if not wasBusy and isBusy then
                local queue = GetProducerQueueState(kindIndex)
                local window = (PRESET_BUILD_CONFIG and PRESET_BUILD_CONFIG.keyWindow) or 0.5
                if queue and queue.pendingIssue and (GetTime() - (queue.pendingIssue.time or 0.0)) <= window then
                    queue.inProgress = true
                    local entry = GetUnitBuildEntry(queue.pendingIssue.unitOdf)
                    StartPresetSurchargeForEntry(team, producer, entry)
                    queue.pendingIssue = nil
                else
                    TryStartBuildForProducer(producer, team, scrapDelta)
                end
            elseif wasBusy and not isBusy then
                local queue = GetProducerQueueState(kindIndex)
                if queue and queue.inProgress then
                    queue.inProgress = false
                end
            end
            busyState[producer] = isBusy
        end
    end
    for handle, _ in pairs(busyState) do
        if not IsValid(handle) then
            busyState[handle] = nil
        end
    end
end

local function FindPendingBuildForUnit(team, unitOdfName, h)
    local pending = InputState.pendingBuilds
    if not pending or #pending == 0 then return nil end
    local wanted = string.lower(CleanString(unitOdfName or ""))
    local now = GetTime()
    local grace = (PRESET_BUILD_CONFIG and PRESET_BUILD_CONFIG.refundGrace) or 1.0
    local bestIndex = nil
    for index, record in ipairs(pending) do
        if record.team == team and record.unitKey == wanted then
            if now <= ((record.expectedFinishAt or 0.0) + grace) then
                if IsValid(h) and IsValid(record.producer) and type(GetDistance) == "function" then
                    local distance = GetDistance(h, record.producer)
                    if distance and distance <= 12.0 then
                        return index, record
                    end
                end
                if not bestIndex then
                    bestIndex = index
                end
            end
        end
    end
    if bestIndex then
        return bestIndex, pending[bestIndex]
    end
    return nil
end

local function UpdatePendingBuildRefunds()
    local pending = InputState.pendingBuilds
    if not pending or #pending == 0 then return end
    local now = GetTime()
    local grace = (PRESET_BUILD_CONFIG and PRESET_BUILD_CONFIG.refundGrace) or 1.0
    for index = #pending, 1, -1 do
        local record = pending[index]
        local expireAt = (record.expectedFinishAt or 0.0) + grace
        local producerValid = IsValid(record.producer)
        local earlyExpire = (not producerValid) and now > ((record.startedAt or 0.0) + 0.5)
        if now > expireAt or earlyExpire then
            if record.charged and record.surcharge and record.surcharge > 0 and type(AddScrap) == "function" then
                AddScrap(record.team, record.surcharge)
            end
            table.remove(pending, index)
        end
    end
end

IsCommanderTrackedHandle = function(h)
    if not IsValid(h) then return false end
    if type(IsBuilding) == "function" and IsBuilding(h) then
        return true
    end
    local label = CleanString((type(GetClassLabel) == "function" and GetClassLabel(h)) or "")
    return label == "turret" or label == "commtower" or label == "powerplant"
end

RegisterCommanderHandle = function(h)
    local overview = InputState.commanderOverview
    if not overview or not IsCommanderTrackedHandle(h) then return end
    if overview.handleSet[h] then return end
    overview.handleSet[h] = true
    table.insert(overview.handles, h)
end

RemoveCommanderHandle = function(h)
    local overview = InputState.commanderOverview
    if not overview or not h or not overview.handleSet[h] then
        return
    end

    overview.handleSet[h] = nil
    for index = #overview.handles, 1, -1 do
        if overview.handles[index] == h then
            table.remove(overview.handles, index)
            break
        end
    end
end

local function ResetCommanderOverview()
    local overview = InputState.commanderOverview
    if not overview then
        return
    end

    overview.initialized = false
    overview.lastUpdate = 0.0
    overview.handles = {}
    overview.handleSet = {}
    overview.stats = {
        counts = {},
        unpoweredTurrets = 0,
        unpoweredComm = 0,
        powerSources = 0,
    }
end

local function InitializeCommanderOverview()
    local overview = InputState.commanderOverview
    if not overview or overview.initialized then return end
    InitializeTrackedWorldHandles()
    overview.initialized = true
end

local function UpdateCommanderOverview()
    local overview = InputState.commanderOverview
    if not overview then return end
    InitializeCommanderOverview()
    local now = GetTime()
    if now - (overview.lastUpdate or 0.0) < (overview.interval or 1.0) then return end
    overview.lastUpdate = now
    local playerTeam = GetPlayerTeamNum()

    local counts = {
        hangar = 0,
        supply = 0,
        comm = 0,
        silo = 0,
        barracks = 0,
        turret = 0,
    }
    local powerSources = {}
    local turrets = {}
    local comms = {}

    for index = #overview.handles, 1, -1 do
        local h = overview.handles[index]
        if not IsValid(h) or (type(IsAlive) == "function" and not IsAlive(h)) then
            overview.handleSet[h] = nil
            table.remove(overview.handles, index)
        elseif type(GetTeamNum) == "function" and GetTeamNum(h) ~= playerTeam then
            -- Keep the handle tracked for future team changes/captures, but skip counting it for the current player team.
        else
            local label = CleanString((type(GetClassLabel) == "function" and GetClassLabel(h)) or "")
            if label == "powerplant" then
                local odf = type(GetOdf) == "function" and GetOdf(h) or nil
                local radius = GetPowerRadius(odf)
                table.insert(powerSources, { handle = h, radius = radius })
            elseif label == "repairdepot" then
                counts.hangar = counts.hangar + 1
            elseif label == "supplydepot" then
                counts.supply = counts.supply + 1
            elseif label == "commtower" then
                counts.comm = counts.comm + 1
                table.insert(comms, h)
            elseif label == "turret" then
                counts.turret = counts.turret + 1
                table.insert(turrets, h)
            elseif label == "scrapsilo" then
                counts.silo = counts.silo + 1
            elseif label == "barracks" then
                counts.barracks = counts.barracks + 1
            end
        end
    end

    local unpoweredTurrets = 0
    local unpoweredComm = 0
    if #powerSources > 0 then
        for _, turret in ipairs(turrets) do
            local powered = false
            for _, power in ipairs(powerSources) do
                if GetDistance(turret, power.handle) < power.radius then
                    powered = true
                    break
                end
            end
            if not powered then
                unpoweredTurrets = unpoweredTurrets + 1
            end
        end
        for _, comm in ipairs(comms) do
            local powered = false
            for _, power in ipairs(powerSources) do
                if GetDistance(comm, power.handle) < power.radius then
                    powered = true
                    break
                end
            end
            if not powered then
                unpoweredComm = unpoweredComm + 1
            end
        end
    else
        unpoweredTurrets = #turrets
        unpoweredComm = #comms
    end

    overview.stats = {
        counts = counts,
        unpoweredTurrets = unpoweredTurrets,
        unpoweredComm = unpoweredComm,
        powerSources = #powerSources,
    }
end

local function BuildCommandPageText()
    local lines = { BuildPdaHeader(PdaPages.COMMAND) }
    local overview = InputState.commanderOverview
    if not overview or not overview.initialized then
        table.insert(lines, "Commander Overview")
        table.insert(lines, "Scanning structures...")
        AppendPdaNavHints(lines)
        return table.concat(lines, "\n")
    end

    local stats = overview.stats or {}
    local counts = stats.counts or {}
    table.insert(lines, "Commander Overview")
    table.insert(lines, string.format("HANGAR   %d", counts.hangar or 0))
    table.insert(lines, string.format("SUPPLY   %d", counts.supply or 0))
    table.insert(lines, string.format("COMM     %d", counts.comm or 0))
    table.insert(lines, string.format("SILO     %d", counts.silo or 0))
    table.insert(lines, string.format("BARRACKS %d", counts.barracks or 0))
    table.insert(lines, string.format("TOWER    %d", counts.turret or 0))
    table.insert(lines, "")
    table.insert(lines, string.format("UNPOWERED TOWERS %d", stats.unpoweredTurrets or 0))
    table.insert(lines, string.format("UNPOWERED COMM   %d", stats.unpoweredComm or 0))
    AppendPdaNavHints(lines)
    return table.concat(lines, "\n")
end

local function BuildWeaponStatsText(player, mask)
    local page = ClampIndex(InputState.pdaPage, 1, PdaPages.COUNT, PdaPages.STATS)
    if page == PdaPages.TARGET then
        return BuildTargetPageText(player)
    end
    if page == PdaPages.SETTINGS then
        return BuildSettingsPageText()
    end
    if page == PdaPages.PRESETS then
        return BuildPresetPageText()
    end
    if page == PdaPages.QUEUE then
        return BuildQueuePageText()
    end
    if page == PdaPages.COMMAND then
        return BuildCommandPageText()
    end
    return BuildStatsPageText(player, mask)
end

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

    local mask = GetCurrentWeaponMask(player)
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

    local msg = BuildWeaponStatsText(player, mask)
    local textChanged = (InputState.lastWeaponText ~= msg)

    InputState.lastWeaponMask = mask
    InputState.lastWeaponPlayer = player
    InputState.lastWeaponText = msg
    InputState.lastWeaponTarget = target

    if (playerChanged or maskChanged or targetChanged or textChanged) and msg then
        ShowWeaponStats(msg, 86400.0)
    elseif not msg then
        ClearWeaponStats()
    end
end

local function RefreshPdaOverlay()
    RefreshWeaponHud()
    UpdateWeaponStatsDisplay(GetPlayerHandle())
end

local function CommitPdaSettingChange(options)
    PersistentConfig.SaveConfig()

    if options and options.applySettings then
        PersistentConfig.ApplySettings()
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
    end

    RefreshPdaOverlay()
end

local function GetHeadlightColorPresetIndex()
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

local function CycleHeadlightColor(delta)
    local nextIndex = CycleIndex(GetHeadlightColorPresetIndex(), #HeadlightColorPresets, delta, 1)
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

    CommitPdaSettingChange({ applySettings = true })
    return true
end

local function SetPlayerHeadlightVisible(enabled)
    local visible = not not enabled
    if PersistentConfig.Settings.HeadlightVisible == visible then
        return false
    end

    PersistentConfig.Settings.HeadlightVisible = visible
    CommitPdaSettingChange({ applySettings = true })
    ShowFeedback("Player Light: " .. (visible and "ON" or "OFF"))
    return true
end

local function SetOtherHeadlightsEnabled(enabled)
    local showOthers = not not enabled
    if PersistentConfig.Settings.OtherHeadlightsDisabled == (not showOthers) then
        return false
    end

    PersistentConfig.Settings.OtherHeadlightsDisabled = not showOthers
    CommitPdaSettingChange({ markOtherHeadlightsDirty = true })
    ShowFeedback("AI Lights: " .. (showOthers and "ON" or "OFF"))
    return true
end

local function CycleHeadlightBeamMode(delta)
    local nextMode = CycleIndex(PersistentConfig.Settings.HeadlightBeamMode, #BeamModes, delta, 2)
    if PersistentConfig.Settings.HeadlightBeamMode == nextMode then
        return false
    end

    PersistentConfig.Settings.HeadlightBeamMode = nextMode
    CommitPdaSettingChange({ applySettings = true })
    ShowFeedback("Beam: " .. (nextMode == 1 and "FOCUSED" or "WIDE"))
    return true
end

local function SetWeaponStatsHudEnabled(enabled)
    local visible = not not enabled
    if PersistentConfig.Settings.WeaponStatsHud == visible then
        return false
    end

    PersistentConfig.Settings.WeaponStatsHud = visible
    CommitPdaSettingChange()
    if visible then
        RefreshPdaOverlay()
    else
        RefreshWeaponHud()
        ClearWeaponStats()
        ClearPdaFeedback()
    end
    ShowFeedback("PDA: " .. (visible and "ON" or "OFF"), 0.35, 0.65, 1.0, 2.5, false)
    return true
end

local function SetSubtitlesEnabled(enabled)
    local value = not not enabled
    if PersistentConfig.Settings.SubtitlesEnabled == value then
        return false
    end

    PersistentConfig.Settings.SubtitlesEnabled = value
    CommitPdaSettingChange({ applySettings = true })
    if not value then
        local subtit = package.loaded["ScriptSubtitles"]
        if subtit and subtit.ClearActive then
            subtit.ClearActive()
        end
        if subtitles and subtitles.clear_queue then subtitles.clear_queue() end
        if subtitles and subtitles.clear_current then subtitles.clear_current() end
    end
    ShowFeedback("Subtitles: " .. (value and "ON" or "OFF"), 0.8, 1.0, 0.8)
    return true
end

local function SetAutoRepairBuildingsEnabled(enabled)
    local value = not not enabled
    if PersistentConfig.Settings.AutoRepairBuildings == value then
        return false
    end

    PersistentConfig.Settings.AutoRepairBuildings = value
    CommitPdaSettingChange()
    ShowFeedback("Building Repair: " .. (value and "ON" or "OFF"), 0.8, 1.0, 0.8)
    return true
end

local function SetAutoRepairWingmenEnabled(enabled)
    local value = not not enabled
    if PersistentConfig.Settings.AutoRepairWingmen == value then
        return false
    end

    PersistentConfig.Settings.AutoRepairWingmen = value
    CommitPdaSettingChange({ syncAutoRepairWingmen = true })
    ShowFeedback("Wingman Auto-Repair: " .. (value and "ON" or "OFF"), 0.8, 1.0, 0.8)
    return true
end

local function SetScavengerAssistEnabled(enabled)
    local value = not not enabled
    if PersistentConfig.Settings.ScavengerAssistEnabled == value then
        return false
    end

    PersistentConfig.Settings.ScavengerAssistEnabled = value
    CommitPdaSettingChange({ syncScavengerAssist = true })
    ShowFeedback("Scavenger Assist: " .. (value and "ON" or "OFF"), 0.8, 1.0, 0.8)
    return true
end

local function SetAutoSaveEnabled(enabled)
    local value = not not enabled
    local slot = PersistentConfig._GetAutoSaveSlot()
    local interval = PersistentConfig._GetAutoSaveIntervalOption()

    if not value then
        PersistentConfig._ClearAutoSaveEnablePrompt()
    end
    if PersistentConfig.Settings.AutoSaveEnabled == value then
        return false
    end

    PersistentConfig.Settings.AutoSaveEnabled = value
    CommitPdaSettingChange({ syncAutoSave = true })
    if value then
        ShowFeedback(string.format("Auto-Save: ON (slot %d, %s)", slot, interval.label), 1.0, 0.35, 0.35, 3.5, false,
            "pda")
    else
        ShowFeedback("Auto-Save: OFF", 0.8, 1.0, 0.8, 2.5, false, "pda")
    end
    return true
end

function PersistentConfig._AdjustAutoSaveSlot(delta)
    local direction = ((delta or 0) < 0) and -1 or 1
    local current = PersistentConfig._GetAutoSaveSlot()
    local nextSlot = ClampIndex(current + direction, PersistentConfig.AutoSaveUi.slotMin, PersistentConfig.AutoSaveUi.slotMax,
        current)
    if nextSlot == current then
        return false
    end

    PersistentConfig.Settings.AutoSaveSlot = nextSlot
    PersistentConfig._ClearAutoSaveEnablePrompt()
    CommitPdaSettingChange({ syncAutoSave = true })

    local active = PersistentConfig.Settings.AutoSaveEnabled
    ShowFeedback(string.format("Auto-Save Slot: %d%s", nextSlot, active and " (ACTIVE)" or ""), active and 1.0 or 0.8,
        active and 0.35 or 1.0, active and 0.35 or 0.8, 3.0, false, "pda")
    return true
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
    CommitPdaSettingChange({ syncAutoSave = true })
    ShowFeedback("Auto-Save Interval: " .. option.label, 0.8, 1.0, 0.8, 2.5, false, "pda")
    return true
end

function PersistentConfig._HandleAutoSaveEnableAction()
    if PersistentConfig.Settings.AutoSaveEnabled then
        ShowFeedback(string.format("Auto-Save is active in slot %d. Press LEFT to disable.", PersistentConfig._GetAutoSaveSlot()), 1.0,
            0.35, 0.35, 3.5, false, "pda")
        return false
    end

    local slot = PersistentConfig._GetAutoSaveSlot()
    if not (InputState and InputState.autoSaveEnableArmed and InputState.autoSaveConfirmSlot == slot) then
        InputState.autoSaveEnableArmed = true
        InputState.autoSaveConfirmSlot = slot
        RefreshPdaOverlay()
        ShowFeedback(string.format("Confirm Auto-Save: slot %d will be backed up and used. Press ENTER again.", slot),
            1.0, 0.25, 0.25, 4.0, false, "pda")
        return true
    end

    PersistentConfig._ClearAutoSaveEnablePrompt()
    return SetAutoSaveEnabled(true)
end

local function SetPilotModeEnabled(enabled)
    local value = not not enabled
    if PersistentConfig.Settings.PilotModeEnabled == value then
        return false
    end

    PersistentConfig.Settings.PilotModeEnabled = value
    CommitPdaSettingChange()
    ShowFeedback("Pilot Mode: " .. (value and "ON" or "OFF"), 0.8, 1.0, 0.8)
    return true
end

GetSettingsPageEntries = function()
    local function DirectionEnabled(delta)
        return (delta or 0) > 0
    end

    return {
        {
            label = "PDA SIZE",
            value = FormatScale(PersistentConfig.Settings.PdaFontScale, PDA_FONT_SCALE_MIN, PDA_FONT_SCALE_MAX),
            adjust = function(delta)
                PersistentConfig.Settings.PdaFontScale = AdjustScale(PersistentConfig.Settings.PdaFontScale, delta,
                    PDA_FONT_SCALE_MIN, PDA_FONT_SCALE_MAX, PDA_FONT_SCALE_STEP)
                CommitPdaSettingChange({ applySettings = true })
                return true
            end,
        },
        {
            label = "PDA ALPHA",
            value = FormatOpacity(PersistentConfig.Settings.PdaOpacity),
            adjust = function(delta)
                PersistentConfig.Settings.PdaOpacity = AdjustOpacity(PersistentConfig.Settings.PdaOpacity, delta)
                CommitPdaSettingChange({ applySettings = true })
                return true
            end,
        },
        {
            label = "HUD COLOR",
            value = GetPdaColorPreset().name,
            adjust = function(delta)
                PersistentConfig.Settings.PdaColorPreset = CycleIndex(PersistentConfig.Settings.PdaColorPreset,
                    #PdaColorPresets, delta, 2)
                CommitPdaSettingChange({ applySettings = true })
                return true
            end,
        },
        {
            label = "PDA HUD",
            value = FormatHotkeyValue(PersistentConfig.Settings.WeaponStatsHud and "ON" or "OFF", "Y"),
            adjust = function(delta)
                return SetWeaponStatsHudEnabled(DirectionEnabled(delta))
            end,
        },
        {
            label = "SUBTITLES",
            value = PersistentConfig.Settings.SubtitlesEnabled and "ON" or "OFF",
            adjust = function(delta)
                return SetSubtitlesEnabled(DirectionEnabled(delta))
            end,
        },
        {
            label = "SUB SIZE",
            value = FormatScale(PersistentConfig.Settings.SubtitleFontScale, SUBTITLE_FONT_SCALE_MIN, SUBTITLE_FONT_SCALE_MAX),
            adjust = function(delta)
                PersistentConfig.Settings.SubtitleFontScale = AdjustScale(PersistentConfig.Settings.SubtitleFontScale, delta,
                    SUBTITLE_FONT_SCALE_MIN, SUBTITLE_FONT_SCALE_MAX, SUBTITLE_FONT_SCALE_STEP)
                CommitPdaSettingChange({ applySettings = true })
                return true
            end,
        },
        {
            label = "SUB ALPHA",
            value = FormatOpacity(PersistentConfig.Settings.SubtitleOpacity),
            adjust = function(delta)
                PersistentConfig.Settings.SubtitleOpacity = AdjustOpacity(PersistentConfig.Settings.SubtitleOpacity, delta)
                CommitPdaSettingChange({ applySettings = true })
                return true
            end,
        },
        {
            label = "PLAYER LIGHT",
            value = FormatHotkeyValue(PersistentConfig.Settings.HeadlightVisible and "ON" or "OFF", "V"),
            adjust = function(delta)
                return SetPlayerHeadlightVisible(DirectionEnabled(delta))
            end,
        },
        {
            label = "LIGHT COLOR",
            value = FormatHotkeyValue(HeadlightColorPresets[GetHeadlightColorPresetIndex()].name, "Z"),
            adjust = function(delta)
                return CycleHeadlightColor(delta)
            end,
        },
        {
            label = "AI LIGHTS",
            value = FormatHotkeyValue(PersistentConfig.Settings.OtherHeadlightsDisabled and "OFF" or "ON", "J"),
            adjust = function(delta)
                return SetOtherHeadlightsEnabled(DirectionEnabled(delta))
            end,
        },
        {
            label = "BEAM",
            value = FormatHotkeyValue(PersistentConfig.Settings.HeadlightBeamMode == 1 and "FOCUSED" or "WIDE", "B"),
            adjust = function(delta)
                return CycleHeadlightBeamMode(delta)
            end,
        },
        {
            label = "WING REPAIR",
            value = FormatHotkeyValue(PersistentConfig.Settings.AutoRepairWingmen and "ON" or "OFF", "X"),
            adjust = function(delta)
                return SetAutoRepairWingmenEnabled(DirectionEnabled(delta))
            end,
        },
        {
            label = "BLDG REPAIR",
            value = PersistentConfig.Settings.AutoRepairBuildings and "ON" or "OFF",
            adjust = function(delta)
                return SetAutoRepairBuildingsEnabled(DirectionEnabled(delta))
            end,
        },
        {
            label = "SCAV ASSIST",
            value = FormatHotkeyValue(PersistentConfig.Settings.ScavengerAssistEnabled and "ON" or "OFF", "U"),
            adjust = function(delta)
                return SetScavengerAssistEnabled(DirectionEnabled(delta))
            end,
        },
        {
            label = "PILOT MODE",
            value = PersistentConfig.Settings.PilotModeEnabled and "ON" or "OFF",
            adjust = function(delta)
                return SetPilotModeEnabled(DirectionEnabled(delta))
            end,
        },
        {
            key = "autosave_slot",
            label = PersistentConfig.Settings.AutoSaveEnabled and "AUTO SLOT !" or "AUTO SLOT",
            value = PersistentConfig.Settings.AutoSaveEnabled and string.format("!! SLOT %d !!", PersistentConfig._GetAutoSaveSlot())
                or string.format("SLOT %d", PersistentConfig._GetAutoSaveSlot()),
            warning = PersistentConfig.Settings.AutoSaveEnabled or (InputState and InputState.autoSaveEnableArmed) or false,
            adjust = function(delta)
                return PersistentConfig._AdjustAutoSaveSlot(delta)
            end,
        },
        {
            key = "autosave_interval",
            label = "AUTO INT",
            value = PersistentConfig._GetAutoSaveIntervalOption().label,
            warning = (InputState and InputState.autoSaveEnableArmed) or false,
            adjust = function(delta)
                return PersistentConfig._AdjustAutoSaveInterval(delta)
            end,
        },
        {
            key = "autosave",
            label = "AUTOSAVE",
            value = PersistentConfig._GetAutoSaveStatusValue(),
            warning = PersistentConfig.Settings.AutoSaveEnabled or (InputState and InputState.autoSaveEnableArmed) or false,
            actionHint = PersistentConfig._GetAutoSaveEnterHint(),
            adjust = function(delta)
                if PersistentConfig.Settings.AutoSaveEnabled and (delta or 0) < 0 then
                    return SetAutoSaveEnabled(false)
                end

                ShowFeedback("Auto-Save enable requires ENTER confirmation.", 1.0, 0.35, 0.35, 3.0, false, "pda")
                return false
            end,
            action = function()
                return PersistentConfig._HandleAutoSaveEnableAction()
            end,
        },
        {
            label = "RESET CFG",
            value = "RIGHT TO RESET",
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
local function HueToRGB(h)
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
    local status, err = pcall(function()
        local f = bzfile.Open(configPath, "r")
        if not f then
            print("PersistentConfig: No config file found at " .. configPath .. ". Using defaults.")
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
                elseif key == "RetroLighting" then
                    PersistentConfig.Settings.RetroLighting = (val == "true")
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

    -- Sync ranges based on mode
    local mode = PersistentConfig.Settings.HeadlightBeamMode
    if BeamModes[mode] then
        PersistentConfig.Settings.HeadlightRange.InnerAngle = BeamModes[mode].Inner
        PersistentConfig.Settings.HeadlightRange.OuterAngle = BeamModes[mode].Outer
    end
    PersistentConfig.Settings.SubtitleOpacity = ClampUnitInterval(PersistentConfig.Settings.SubtitleOpacity, 0.50)
    PersistentConfig.Settings.PdaOpacity = ClampUnitInterval(PersistentConfig.Settings.PdaOpacity, 1.00)
    PersistentConfig.Settings.SubtitleFontScale = ClampRange(PersistentConfig.Settings.SubtitleFontScale,
        SUBTITLE_FONT_SCALE_MIN, SUBTITLE_FONT_SCALE_MAX, 1.0)
    PersistentConfig.Settings.PdaFontScale = ClampRange(PersistentConfig.Settings.PdaFontScale,
        PDA_FONT_SCALE_MIN, PDA_FONT_SCALE_MAX, 1.0)
    PersistentConfig.Settings.PdaColorPreset = ClampIndex(PersistentConfig.Settings.PdaColorPreset, 1, #PdaColorPresets, 2)
    PersistentConfig.Settings.AutoSaveSlot = PersistentConfig._GetAutoSaveSlot()
    PersistentConfig.Settings.AutoSaveInterval = PersistentConfig._GetAutoSaveIntervalOption().seconds
end

function PersistentConfig.SaveConfig()
    print("=== PersistentConfig: Attempting to save config ===")
    print("Config path: " .. tostring(configPath))
    print("Working directory: " .. tostring(bzfile.GetWorkingDirectory()))

    local status, err = pcall(function()
        local f = bzfile.Open(configPath, "w", "trunc")
        if not f then
            print("PersistentConfig: Failed to open config file for writing!")
            print("Attempted path: " .. configPath)
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
        f:Writeln("OtherHeadlightsDisabled=" .. tostring(PersistentConfig.Settings.OtherHeadlightsDisabled))
        f:Writeln("AutoRepairWingmen=" .. tostring(PersistentConfig.Settings.AutoRepairWingmen))
        f:Writeln("RainbowMode=" .. tostring(PersistentConfig.Settings.RainbowMode))
        f:Writeln("AutoSaveSlot=" .. tostring(PersistentConfig.Settings.AutoSaveSlot))
        f:Writeln("AutoSaveEnabled=" .. tostring(PersistentConfig.Settings.AutoSaveEnabled))
        f:Writeln("AutoSaveInterval=" .. tostring(PersistentConfig.Settings.AutoSaveInterval))
        f:Writeln("ScavengerAssistEnabled=" .. tostring(PersistentConfig.Settings.ScavengerAssistEnabled))
        f:Writeln("AutoRepairBuildings=" .. tostring(PersistentConfig.Settings.AutoRepairBuildings))
        f:Writeln("RetroLighting=" .. tostring(PersistentConfig.Settings.RetroLighting))
        f:Writeln("WeaponStatsHud=" .. tostring(PersistentConfig.Settings.WeaponStatsHud))
        f:Writeln("PilotModeEnabled=" .. tostring(PersistentConfig.Settings.PilotModeEnabled))
        f:Writeln("SubtitleOpacity=" .. tostring(PersistentConfig.Settings.SubtitleOpacity))
        f:Writeln("SubtitleFontScale=" .. tostring(PersistentConfig.Settings.SubtitleFontScale))
        f:Writeln("PdaOpacity=" .. tostring(PersistentConfig.Settings.PdaOpacity))
        f:Writeln("PdaFontScale=" .. tostring(PersistentConfig.Settings.PdaFontScale))
        f:Writeln("PdaColorPreset=" .. tostring(PersistentConfig.Settings.PdaColorPreset))
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
        print("PersistentConfig: Settings saved successfully to: " .. configPath)
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
    end

    ShowFeedback("Settings reset to defaults.", 0.7, 1.0, 0.7, 4.0, false)
end

function PersistentConfig.ApplySettings()
    if exu then
        local h = GetPlayerHandle()
        if IsValid(h) then
        -- Sync ranges based on mode before applying
            local mode = PersistentConfig.Settings.HeadlightBeamMode
            if BeamModes[mode] then
                PersistentConfig.Settings.HeadlightRange.InnerAngle = BeamModes[mode].Inner
                PersistentConfig.Settings.HeadlightRange.OuterAngle = BeamModes[mode].Outer
            end

            local mult = BeamModes[mode] and BeamModes[mode].Multiplier or 1.0

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

        if exu.SetRetroLightingMode then
            exu.SetRetroLightingMode(PersistentConfig.Settings.RetroLighting)
        end
    end

    local subtit = package.loaded["ScriptSubtitles"]
    if subtit and subtit.SetOpacity then
        subtit.SetOpacity(PersistentConfig.Settings.SubtitleOpacity)
    elseif subtitles and subtitles.set_opacity then
        subtitles.set_opacity(PersistentConfig.Settings.SubtitleOpacity)
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

    InputState.SubtitlesPaused = pauseMenuOpen or escapePressed
    if subtitles and subtitles.set_suspended then
        subtitles.set_suspended(InputState.SubtitlesPaused)
    end

    if pauseMenuOpen then
        ClearWeaponStats()
        ClearPdaFeedback()
    else
        UpdateWeaponStatsDisplay(currentPlayerHandle)
    end

    -- Process Feedback Queue
    if not pauseMenuOpen and #PersistentConfig.FeedbackQueue > 0 then
        -- Check if mission subtitles are active
        local subtit = package.loaded["ScriptSubtitles"]
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
            elseif subtitles and subtitles.submit then
                subtitles.clear_queue()
                if subtitles.clear_current then subtitles.clear_current() end
                subtitles.set_opacity(ClampUnitInterval(PersistentConfig.Settings.SubtitleOpacity, 0.5))
                subtitles.submit(item.msg, item.duration, item.r, item.g, item.b)
                if subtit then
                    subtit.LastEndTime = GetTime() + item.duration
                end
            end
        end
    end

    local team = GetPlayerTeamNum()
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
        SetPlayerHeadlightVisible(not PersistentConfig.Settings.HeadlightVisible)
    end
    InputState.last_v_state = v_key

    -- Cycle Headlight Color (Z) - Moved from Alt+C to Z
    local z_key = exu.GetGameKey("Z")
    if z_key and not InputState.last_z_state then
        CycleHeadlightColor(1)
    end
    InputState.last_z_state = z_key

    -- Toggle AI/NPC Headlights (J) - Moved from Alt+U to J
    local j_key = exu.GetGameKey("J")
    if j_key and not InputState.last_j_state then
        SetOtherHeadlightsEnabled(PersistentConfig.Settings.OtherHeadlightsDisabled)
    end
    InputState.last_j_state = j_key

    -- Toggle Headlight Beam Mode (B) - Removed Alt requirement, but check for Bail (Ctrl+B)
    local b_key = exu.GetGameKey("B")
    local ctrl_down = exu.GetGameKey("CTRL")
    local y_key = exu.GetGameKey("Y")

    if b_key and not ctrl_down and not InputState.last_b_state then
        CycleHeadlightBeamMode(1)
    end
    InputState.last_b_state = b_key

    if y_key and not ctrl_down and not InputState.last_y_state then
        SetWeaponStatsHudEnabled(not PersistentConfig.Settings.WeaponStatsHud)
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
        SetAutoRepairWingmenEnabled(not PersistentConfig.Settings.AutoRepairWingmen)
    end
    InputState.last_x_state = x_key

    -- Toggle Scavenger Assist (U)
    local u_key = exu.GetGameKey("U")
    if u_key and not InputState.last_u_state then
        SetScavengerAssistEnabled(not PersistentConfig.Settings.ScavengerAssistEnabled)
    end
    InputState.last_u_state = u_key

    -- AutoSave and Reset are settings-menu only (no hotkeys).

    -- Help Popup (/ or ? key) - using stock BZ API
    local help_pressed = (LastGameKey == "/" or LastGameKey == "?")
    if help_pressed and not InputState.last_help_state then
        PersistentConfig.ShowHelp()
    end
    InputState.last_help_state = help_pressed

    if InputState.SubtitlesPaused then
        ClearWeaponStats()
        ClearPdaFeedback()
    end

    -- Update Rainbow Color if active
    if PersistentConfig.Settings.RainbowMode and PersistentConfig.Settings.HeadlightVisible then
        local hue = (GetTime() * 0.2) % 1.0 -- Cycle every 5 seconds
        local r, g, b = HueToRGB(hue)
        local mode = PersistentConfig.Settings.HeadlightBeamMode
        local mult = BeamModes[mode] and BeamModes[mode].Multiplier or 1.0
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

local function IsBuildablePlayerUnitOdf(unitOdfName, team)
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

local function HasNearbyProducingStructureForUnit(unitOdfName, team, h, maxDistance)
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

local function ApplyUnitPresetToObject(h)
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
    if not IsBuildablePlayerUnitOdf(odfName, team) then
        return false
    end
    if not HasNearbyProducingStructureForUnit(odfName, team, h, 10.0) then
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

    RuntimeEnhancements.OnObjectCreated(h)
    ConservativeCulling.OnObjectCreated(h)
    RegisterTrackedWorldHandle(h)
    if aiCore and type(aiCore.TrackWorldObject) == "function" then
        aiCore.TrackWorldObject(h)
    end

    if exu and exu.SetHeadlightVisible and PersistentConfig.Settings.OtherHeadlightsDisabled then
        local player = GetPlayerHandle()
        ApplyOtherHeadlightVisibility(h, false, player)
    end

    ApplyUnitPresetToObject(h)
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

local function InstallPlayerChargeTrackingHook()
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
    ResetTrackedWorldHandles()
    ResetCommanderOverview()
    InputState.processedCreationHandles = {}
    InputState.otherHeadlightVisibility = {}
    RuntimeEnhancements.Initialize()
    RuntimeEnhancements.RebuildVisuals()
    ConservativeCulling.Initialize()
    PersistentConfig.LoadConfig()
    WarnIfNativeFeaturesUnavailable()

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
    PersistentConfig.ApplySettings()
    TryCreateExperimentalOverlay()
    InstallPlayerChargeTrackingHook()
    MarkOtherHeadlightsDirty()

    -- Sync AutoSave config from settings
    if autosave and autosave.Config then
        autosave.Config.enabled = PersistentConfig.Settings.AutoSaveEnabled
        autosave.Config.autoSaveInterval = PersistentConfig.Settings.AutoSaveInterval
        autosave.Config.currentSlot = PersistentConfig.Settings.AutoSaveSlot
        print("PersistentConfig: AutoSave synced - enabled=" .. tostring(autosave.Config.enabled) ..
            " interval=" .. tostring(autosave.Config.autoSaveInterval) ..
            " slot=" .. tostring(autosave.Config.currentSlot))
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
                PersistentConfig.OnObjectCreated(h)
                return oldAddObject(h)
            end
        end
        local oldCreateObject = CreateObject
        if type(oldCreateObject) == "function" then
            CreateObject = function(h)
                PersistentConfig.OnObjectCreated(h)
                return oldCreateObject(h)
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
                if subtitles and subtitles.clear_queue then subtitles.clear_queue() end
                if subtitles and subtitles.clear_current then subtitles.clear_current() end
                oldSucceed(...)
            end
        end
        if FailMission then
            local oldFail = FailMission
            FailMission = function(...)
                if subtitles and subtitles.clear_queue then subtitles.clear_queue() end
                if subtitles and subtitles.clear_current then subtitles.clear_current() end
                oldFail(...)
            end
        end
        PersistentConfig.HooksInstalled = true
    end
end

return PersistentConfig
