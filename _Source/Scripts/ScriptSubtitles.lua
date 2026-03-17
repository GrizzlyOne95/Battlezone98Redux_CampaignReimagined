-- Subtitles.lua
-- Wrapper for mission subtitles with EXU/Ogre overlay rendering and subtitles.dll fallback
local subtitles = nil
do
    local ok, module = pcall(require, "subtitles")
    if ok then
        subtitles = module
    end
end
local exu = require("exu")

local Subtitles = {}
local SUBTITLE_CHANNEL = 3
local FONT_SCALE_MIN = 0.85
local FONT_SCALE_MAX = 2.00
local BASE_CHAR_LIMIT = 78
local OVERLAY_FONT_NAME = "CRBZoneOverlayFont"
local OVERLAY_Z_ORDER = 644
local OVERLAY_IDS = {
    overlay = "cr_mission_subtitle_overlay",
    root = "cr_mission_subtitle_overlay_root",
    backdrop = "cr_mission_subtitle_overlay_backdrop",
    text = "cr_mission_subtitle_overlay_text",
}

-- State
local currentAudioHandle = nil
local DEFAULT_DURATION = 8.0
local durations = {}
local activeSequenceSource = nil
local overlayState = {
    ready = false,
    failed = false,
    visible = false,
    currentEntry = nil,
    queue = {},
    effectiveSuspended = false,
    suspendStartedAt = nil,
}
Subtitles.LastEndTime = 0
Subtitles.Config = {
    opacity = 0.5,
    fontScale = 1.0,
    enabled = true,
    suspended = false,
}

local function Clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function ClampRange(value, minimum, maximum, fallback)
    local n = tonumber(value)
    if not n then return fallback end
    if n < minimum then return minimum end
    if n > maximum then return maximum end
    return n
end

local function GetFontScale()
    return ClampRange(Subtitles.Config.fontScale, FONT_SCALE_MIN, FONT_SCALE_MAX, 1.0)
end

local function GetPersistentConfig()
    return package.loaded["PersistentConfig"]
end

local function GetWrapCharacterLimit()
    return BASE_CHAR_LIMIT
end

local function GetUiResolutionMetrics()
    local persistentConfig = GetPersistentConfig()
    if persistentConfig and type(persistentConfig._GetUiResolutionMetrics) == "function" then
        local ok, width, height, uiScale = pcall(persistentConfig._GetUiResolutionMetrics)
        if ok and type(width) == "number" and width > 0 and type(height) == "number" and height > 0 then
            return width, height, uiScale or 2.0
        end
    end

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

    return width, height, uiScale
end

local function NormalizeOverlayText(text)
    local persistentConfig = GetPersistentConfig()
    if persistentConfig and type(persistentConfig._NormalizeOverlayText) == "function" then
        local ok, normalized = pcall(persistentConfig._NormalizeOverlayText, text)
        if ok then
            return normalized
        end
    end

    text = tostring(text or "")
    text = text:gsub("\r\n", "\n")
    text = text:gsub("\r", "\n")
    text = text:gsub("\t", "    ")
    return text
end

local function CountOverlayTextLines(text)
    local persistentConfig = GetPersistentConfig()
    if persistentConfig and type(persistentConfig._CountOverlayTextLines) == "function" then
        local ok, lineCount = pcall(persistentConfig._CountOverlayTextLines, text)
        if ok and type(lineCount) == "number" then
            return lineCount
        end
    end

    local normalized = NormalizeOverlayText(text)
    local count = 1
    for _ in normalized:gmatch("\n") do
        count = count + 1
    end
    return count
end

local function GetOverlayLongestLineLength(text)
    local persistentConfig = GetPersistentConfig()
    if persistentConfig and type(persistentConfig._GetOverlayLongestLineLength) == "function" then
        local ok, lineLength = pcall(persistentConfig._GetOverlayLongestLineLength, text)
        if ok and type(lineLength) == "number" then
            return lineLength
        end
    end

    local best = 0
    for line in (NormalizeOverlayText(text) .. "\n"):gmatch("(.-)\n") do
        best = math.max(best, #line)
    end
    return best
end

local function GetOverlayTextBlockHeight(charHeightPixels, lineCount, lineSpacing)
    local persistentConfig = GetPersistentConfig()
    if persistentConfig and type(persistentConfig._GetOverlayTextBlockHeight) == "function" then
        local ok, blockHeight = pcall(persistentConfig._GetOverlayTextBlockHeight, charHeightPixels, lineCount, lineSpacing)
        if ok and type(blockHeight) == "number" then
            return blockHeight
        end
    end

    charHeightPixels = math.max(tonumber(charHeightPixels) or 0, 1)
    lineCount = math.max(tonumber(lineCount) or 0, 1)
    lineSpacing = math.max(tonumber(lineSpacing) or 1.08, 1.0)
    return math.max(charHeightPixels + 4, math.floor((charHeightPixels * lineSpacing * lineCount) + 6))
end

local function WrapTextToPixels(text, widthPixels, charHeightPixels, widthFactor, horizontalPadding)
    local persistentConfig = GetPersistentConfig()
    if persistentConfig and type(persistentConfig._WrapOverlayTextToPixels) == "function" then
        local ok, wrapped = pcall(persistentConfig._WrapOverlayTextToPixels, text, widthPixels, charHeightPixels, widthFactor,
            horizontalPadding)
        if ok and type(wrapped) == "string" then
            return wrapped
        end
    end

    return Subtitles.WrapText(NormalizeOverlayText(text), GetWrapCharacterLimit())
end

local function GetOverlayFontName()
    local persistentConfig = GetPersistentConfig()
    if persistentConfig then
        if persistentConfig.PdaOverlay and persistentConfig.PdaOverlay.useCustomFont ~= false
            and type(persistentConfig.PdaOverlay.font) == "string" and persistentConfig.PdaOverlay.font ~= "" then
            return persistentConfig.PdaOverlay.font
        end
        if persistentConfig.ExperimentalOverlayUseCustomFont ~= false and type(persistentConfig.ExperimentalOverlayFont) == "string"
            and persistentConfig.ExperimentalOverlayFont ~= "" then
            return persistentConfig.ExperimentalOverlayFont
        end
    end

    return OVERLAY_FONT_NAME
end

local function CanUseOverlayRenderer()
    if overlayState.failed then
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

local function SafeOverlayCall(fn, ...)
    if type(fn) ~= "function" then
        return false, nil
    end

    local ok, result = pcall(fn, ...)
    if not ok then
        print("Subtitles: overlay call failed: " .. tostring(result))
        return false, nil
    end

    return true, result
end

local function HideSubtitleOverlay()
    overlayState.visible = false
    if exu and exu.HideOverlay then
        pcall(exu.HideOverlay, OVERLAY_IDS.overlay)
    end
end

local function ClearOverlayQueueState()
    overlayState.currentEntry = nil
    overlayState.queue = {}
    overlayState.suspendStartedAt = nil
    HideSubtitleOverlay()
end

local function DestroySubtitleOverlay()
    local ids = OVERLAY_IDS
    ClearOverlayQueueState()
    overlayState.ready = false

    if not exu then
        return
    end

    if exu.RemoveOverlayElementChild then
        pcall(exu.RemoveOverlayElementChild, ids.root, ids.backdrop)
        pcall(exu.RemoveOverlayElementChild, ids.root, ids.text)
    end
    if exu.RemoveOverlay2D then
        pcall(exu.RemoveOverlay2D, ids.overlay, ids.root)
    end
    if exu.DestroyOverlayElement then
        pcall(exu.DestroyOverlayElement, ids.text)
        pcall(exu.DestroyOverlayElement, ids.backdrop)
        pcall(exu.DestroyOverlayElement, ids.root)
    end
    if exu.DestroyOverlay then
        pcall(exu.DestroyOverlay, ids.overlay)
    end
end

local function GetSubtitleOverlayLayout(text)
    local width, height, uiScale = GetUiResolutionMetrics()
    local fontScale = GetFontScale()
    local aspect = width / math.max(height, 1)
    local aspectScale = Clamp((16.0 / 9.0) / aspect, 0.78, 1.35)
    local uiScaleFactor = Clamp((uiScale / 2.0) ^ 0.32, 0.90, 1.30)
    local charHeight = Clamp(math.floor((18.0 * aspectScale * uiScaleFactor * fontScale) + 0.5), 16, 40)
    local maxTextWidth = Clamp(math.floor(width * 0.74), 360, math.max(360, width - 72))
    local paddingX = math.max(18, math.floor(charHeight * 0.68))
    local paddingY = math.max(12, math.floor(charHeight * 0.48))
    local wrappedText = WrapTextToPixels(text, maxTextWidth, charHeight, 0.68, 0)
    local textHeight = GetOverlayTextBlockHeight(charHeight, CountOverlayTextLines(wrappedText), 1.08)
    local longestLine = GetOverlayLongestLineLength(wrappedText)
    local estimatedTextWidth = math.min(maxTextWidth,
        math.max(charHeight * 10, math.floor((longestLine * charHeight * 0.68) + 12)))
    local panelWidth = estimatedTextWidth + (paddingX * 2)
    local panelHeight = textHeight + (paddingY * 2)
    local marginY = math.max(20, math.floor(height * 0.035))
    local panelX = math.max(12, math.floor((width - panelWidth) * 0.5))
    local panelY = math.max(12, height - panelHeight - marginY)

    return {
        panelX = panelX,
        panelY = panelY,
        panelWidth = panelWidth,
        panelHeight = panelHeight,
        textX = paddingX,
        textY = paddingY,
        textWidth = math.max(panelWidth - (paddingX * 2), 32),
        textHeight = textHeight,
        charHeight = charHeight,
        wrappedText = wrappedText,
    }
end

local function GetSubtitleOverlayColors(r, g, b)
    local textR = Clamp(tonumber(r) or 1.0, 0.0, 1.0)
    local textG = Clamp(tonumber(g) or 1.0, 0.0, 1.0)
    local textB = Clamp(tonumber(b) or 1.0, 0.0, 1.0)
    local opacity = Clamp(tonumber(Subtitles.Config.opacity) or 0.5, 0.0, 1.0)
    local borderBoost = 0.28 + (opacity * 0.32)

    return {
        backdrop = {
            r = 0.02,
            g = 0.03,
            b = 0.02,
            a = opacity,
        },
        text = {
            r = textR,
            g = textG,
            b = textB,
            a = 1.0,
        },
        border = {
            r = math.min(1.0, textR + borderBoost),
            g = math.min(1.0, textG + borderBoost),
            b = math.min(1.0, textB + borderBoost),
            a = math.min(1.0, 0.40 + (opacity * 0.60)),
        },
    }
end

local function TryCreateSubtitleOverlay()
    if overlayState.ready then
        return true
    end

    if not CanUseOverlayRenderer() then
        return false
    end

    DestroySubtitleOverlay()

    local ok = true
    local ids = OVERLAY_IDS
    local metricsMode = exu.OVERLAY_METRICS.PIXELS
    local fontName = GetOverlayFontName()

    local function Call(fn, ...)
        local success, result = SafeOverlayCall(fn, ...)
        if not success then
            ok = false
        end
        return result
    end

    Call(exu.CreateOverlay, ids.overlay)
    Call(exu.CreateOverlayElement, "Panel", ids.root)
    Call(exu.CreateOverlayElement, "Panel", ids.backdrop)
    Call(exu.CreateOverlayElement, "TextArea", ids.text)
    Call(exu.AddOverlay2D, ids.overlay, ids.root)
    Call(exu.AddOverlayElementChild, ids.root, ids.backdrop)
    Call(exu.AddOverlayElementChild, ids.root, ids.text)
    Call(exu.SetOverlayZOrder, ids.overlay, OVERLAY_Z_ORDER)
    Call(exu.SetOverlayMetricsMode, ids.root, metricsMode)
    Call(exu.SetOverlayMetricsMode, ids.backdrop, metricsMode)
    Call(exu.SetOverlayMetricsMode, ids.text, metricsMode)
    Call(exu.SetOverlayParameter, ids.root, "transparent", true)
    Call(exu.SetOverlayColor, ids.root, 0.0, 0.0, 0.0, 0.0)
    Call(exu.SetOverlayMaterial, ids.backdrop, "BaseWhiteNoLighting")
    Call(exu.SetOverlayParameter, ids.backdrop, "transparent", true)
    Call(exu.SetOverlayParameter, ids.text, "alignment", "center")
    Call(exu.SetOverlayCaption, ids.text, "")
    if Call(exu.SetOverlayTextFont, ids.text, fontName) ~= true then
        ok = false
        print("Subtitles: overlay font bind failed for " .. tostring(fontName))
    end
    Call(exu.ShowOverlayElement, ids.root)
    Call(exu.ShowOverlayElement, ids.backdrop)
    Call(exu.ShowOverlayElement, ids.text)
    Call(exu.HideOverlay, ids.overlay)

    if not ok then
        overlayState.failed = true
        DestroySubtitleOverlay()
        return false
    end

    overlayState.ready = true
    overlayState.failed = false
    return true
end

local function ShowSubtitleOverlay(entry)
    if not entry or not TryCreateSubtitleOverlay() then
        return false
    end

    local ok = true
    local ids = OVERLAY_IDS
    local layout = GetSubtitleOverlayLayout(entry.text)
    local colors = GetSubtitleOverlayColors(entry.r, entry.g, entry.b)

    local function Call(fn, ...)
        local success, result = SafeOverlayCall(fn, ...)
        if not success then
            ok = false
        end
        return result
    end

    Call(exu.SetOverlayPosition, ids.root, layout.panelX, layout.panelY)
    Call(exu.SetOverlayDimensions, ids.root, layout.panelWidth, layout.panelHeight)
    Call(exu.SetOverlayPosition, ids.backdrop, 0, 0)
    Call(exu.SetOverlayDimensions, ids.backdrop, layout.panelWidth, layout.panelHeight)
    Call(exu.SetOverlayColor, ids.backdrop, colors.backdrop.r, colors.backdrop.g, colors.backdrop.b, colors.backdrop.a)
    Call(exu.SetOverlayPosition, ids.text, layout.textX, layout.textY)
    Call(exu.SetOverlayDimensions, ids.text, layout.textWidth, layout.textHeight)
    Call(exu.SetOverlayTextCharHeight, ids.text, layout.charHeight)
    Call(exu.SetOverlayParameter, ids.text, "space_width", math.max(4, math.floor((layout.charHeight * 0.70) + 0.5)))
    if exu.SetOverlayTextColor then
        Call(exu.SetOverlayTextColor, ids.text, colors.text.r, colors.text.g, colors.text.b, colors.text.a)
    else
        Call(exu.SetOverlayColor, ids.text, colors.text.r, colors.text.g, colors.text.b, colors.text.a)
    end
    Call(exu.SetOverlayCaption, ids.text, layout.wrappedText)
    Call(exu.ShowOverlayElement, ids.root)
    Call(exu.ShowOverlayElement, ids.backdrop)
    Call(exu.ShowOverlayElement, ids.text)
    Call(exu.ShowOverlay, ids.overlay)

    if not ok then
        overlayState.failed = true
        DestroySubtitleOverlay()
        return false
    end

    overlayState.visible = true
    return true
end

local function GetOverlayRemainingDuration(now)
    now = now or GetTime()
    local remaining = 0.0

    if overlayState.currentEntry then
        local entryEnd = (overlayState.currentEntry.startTime or now) + (overlayState.currentEntry.duration or 0.0)
        remaining = remaining + math.max(0.0, entryEnd - now)
    end

    for _, entry in ipairs(overlayState.queue) do
        remaining = remaining + math.max(0.0, tonumber(entry.duration) or 0.0)
    end

    return remaining
end

local function UpdateOverlayLastEndTime()
    local now = GetTime()
    local remaining = GetOverlayRemainingDuration(now)
    if remaining > 0.0 then
        Subtitles.LastEndTime = now + remaining
    else
        Subtitles.LastEndTime = now
    end
end

local function StartNextOverlayEntry()
    if overlayState.currentEntry or overlayState.effectiveSuspended then
        return true
    end
    if #overlayState.queue == 0 then
        HideSubtitleOverlay()
        return true
    end

    overlayState.currentEntry = table.remove(overlayState.queue, 1)
    overlayState.currentEntry.startTime = GetTime()
    if not ShowSubtitleOverlay(overlayState.currentEntry) then
        return false
    end

    UpdateOverlayLastEndTime()
    return true
end

local function QueueOverlayEntries(entries, append)
    if not TryCreateSubtitleOverlay() then
        return false
    end

    if not append then
        ClearOverlayQueueState()
    end

    for _, entry in ipairs(entries) do
        overlayState.queue[#overlayState.queue + 1] = {
            text = tostring(entry.text or ""),
            duration = math.max(0.05, tonumber(entry.duration) or 0.05),
            r = tonumber(entry.r) or 1.0,
            g = tonumber(entry.g) or 1.0,
            b = tonumber(entry.b) or 1.0,
        }
    end

    if not overlayState.currentEntry and not StartNextOverlayEntry() then
        return false
    end

    UpdateOverlayLastEndTime()
    return true
end

local function SetOverlayRendererSuspended(suspended)
    suspended = not not suspended
    if overlayState.effectiveSuspended == suspended then
        return
    end

    overlayState.effectiveSuspended = suspended
    if suspended then
        overlayState.suspendStartedAt = GetTime()
        HideSubtitleOverlay()
        return
    end

    local now = GetTime()
    local pausedDuration = 0.0
    if overlayState.suspendStartedAt then
        pausedDuration = math.max(0.0, now - overlayState.suspendStartedAt)
    end
    overlayState.suspendStartedAt = nil

    if overlayState.currentEntry and overlayState.currentEntry.startTime then
        overlayState.currentEntry.startTime = overlayState.currentEntry.startTime + pausedDuration
        ShowSubtitleOverlay(overlayState.currentEntry)
    elseif #overlayState.queue > 0 then
        StartNextOverlayEntry()
    else
        HideSubtitleOverlay()
    end

    UpdateOverlayLastEndTime()
end

local function DetectRuntimeSuspended()
    if exu and exu.IsPauseMenuOpen then
        local ok, paused = pcall(exu.IsPauseMenuOpen)
        if ok and paused then
            return true
        end
    end

    if exu and exu.GetGameKey then
        local ok, escapePressed = pcall(exu.GetGameKey, "ESCAPE")
        if ok and escapePressed then
            return true
        end
    end

    return LastGameKey == "ESCAPE"
end

local function UpdateRendererSuspensionState()
    local suspended = Subtitles.Config.suspended or DetectRuntimeSuspended()

    if subtitles and subtitles.set_suspended then
        pcall(subtitles.set_suspended, suspended)
    end

    if overlayState.currentEntry or #overlayState.queue > 0 or overlayState.ready then
        SetOverlayRendererSuspended(suspended)
    end
end

local function GetSubtitleLayoutMetrics()
    local width, height, uiScale = GetUiResolutionMetrics()
    local fontScale = GetFontScale()

    local aspect = width / math.max(height, 1)
    local aspectScale = Clamp((16.0 / 9.0) / aspect, 0.78, 1.35)
    local uiScaleFactor = Clamp((uiScale / 2.0) ^ 0.32, 0.90, 1.30)

    return {
        textScale = Clamp(0.38 * aspectScale * uiScaleFactor * fontScale, 0.28, 0.90),
        wrapWidth = Clamp(0.84 * Clamp(1.0 / aspectScale, 0.90, 1.22) * fontScale, 0.68, 4.50),
        paddingX = 10.0 * fontScale,
        paddingY = 8.0 * fontScale,
        opacity = Clamp(tonumber(Subtitles.Config.opacity) or 0.5, 0.0, 1.0),
    }
end

local function ApplySubtitleLayout()
    if not subtitles or not subtitles.set_channel_layout or not subtitles.submit_to then
        return false
    end

    local layout = GetSubtitleLayoutMetrics()
    subtitles.set_channel_layout(SUBTITLE_CHANNEL, 0.5, 0.97, 0.5, 1.0, layout.textScale, layout.wrapWidth, layout.paddingX,
        layout.paddingY, layout.opacity)
    return true
end

local function ClearSubtitleChannel()
    if subtitles and subtitles.clear_queue then
        subtitles.clear_queue(SUBTITLE_CHANNEL)
    end
    if subtitles and subtitles.clear_current then
        subtitles.clear_current(SUBTITLE_CHANNEL)
    end
end

local function ClearDefaultSubtitleQueue()
    if not subtitles then
        return
    end

    subtitles.clear_queue()
    if subtitles.clear_current then
        subtitles.clear_current()
    end
end

local function SubmitSequenceEntries(entries, append)
    if not Subtitles.Config.enabled then
        return
    end
    if not entries or #entries == 0 then
        return
    end

    if CanUseOverlayRenderer() and QueueOverlayEntries(entries, append) then
        return "overlay"
    end

    if ApplySubtitleLayout() then
        if not append then
            ClearSubtitleChannel()
        end
        for _, entry in ipairs(entries) do
            subtitles.submit_to(SUBTITLE_CHANNEL, entry.text, entry.duration, entry.r, entry.g, entry.b)
        end
        return "dll"
    else
        if not subtitles or not subtitles.submit then
            return nil
        end
        if not append then
            ClearDefaultSubtitleQueue()
        end
        subtitles.set_opacity(Clamp(tonumber(Subtitles.Config.opacity) or 0.5, 0.0, 1.0))
        for _, entry in ipairs(entries) do
            subtitles.submit(entry.text, entry.duration, entry.r, entry.g, entry.b)
        end
        return "dll"
    end
end

local function BuildSequenceEntries(source)
    if not source or not source.text or source.text == "" then
        return {}, 0.0
    end

    local wrapped = Subtitles.WrapText(source.text, GetWrapCharacterLimit())
    if source.mode == "display" then
        local duration = math.max(0.1, tonumber(source.duration) or DEFAULT_DURATION)
        return {
            { text = wrapped, duration = duration, r = source.r, g = source.g, b = source.b }
        }, duration
    end

    local lines = {}
    for line in string.gmatch(wrapped, "[^\r\n]+") do
        table.insert(lines, line)
    end

    local chunks = {}
    local currentChunk = {}
    for _, line in ipairs(lines) do
        table.insert(currentChunk, line)
        if #currentChunk >= 2 then
            table.insert(chunks, table.concat(currentChunk, "\n"))
            currentChunk = {}
        end
    end
    if #currentChunk > 0 then
        table.insert(chunks, table.concat(currentChunk, "\n"))
    end
    if #chunks == 0 then
        table.insert(chunks, wrapped)
    end

    local totalChars = math.max(#source.text, 1)
    local entries = {}
    local totalDuration = 0.0
    for _, chunk in ipairs(chunks) do
        local chunkWeight = #chunk / totalChars
        local chunkDuration = (tonumber(source.duration) or DEFAULT_DURATION) * chunkWeight
        local finalDuration = math.max(1.5, chunkDuration)
        table.insert(entries, {
            text = chunk,
            duration = finalDuration,
            r = source.r,
            g = source.g,
            b = source.b,
        })
        totalDuration = totalDuration + finalDuration
    end

    return entries, totalDuration
end

local function ResubmitActiveSequence()
    if not Subtitles.Config.enabled then
        return
    end
    if overlayState.currentEntry then
        UpdateRendererSuspensionState()
        if not overlayState.effectiveSuspended then
            ShowSubtitleOverlay(overlayState.currentEntry)
        end
        UpdateOverlayLastEndTime()
        return
    end
    if not activeSequenceSource then
        return
    end

    local entries = BuildSequenceEntries(activeSequenceSource)
    local elapsed = math.max(0.0, GetTime() - (activeSequenceSource.startedAt or GetTime()))
    local remaining = {}
    local remainingDuration = 0.0

    for _, entry in ipairs(entries) do
        local duration = entry.duration
        if elapsed >= duration then
            elapsed = elapsed - duration
        else
            local redrawDuration = duration - elapsed
            if redrawDuration > 0.05 then
                table.insert(remaining, {
                    text = entry.text,
                    duration = redrawDuration,
                    r = entry.r,
                    g = entry.g,
                    b = entry.b,
                })
                remainingDuration = remainingDuration + redrawDuration
            end
            elapsed = 0.0
        end
    end

    if #remaining == 0 then
        activeSequenceSource = nil
        return
    end

    local renderMode = SubmitSequenceEntries(remaining)
    if renderMode == "overlay" then
        UpdateOverlayLastEndTime()
    end
    Subtitles.LastEndTime = GetTime() + remainingDuration
end

local function StartSequence(source, append)
    activeSequenceSource = source
    if not append then
        activeSequenceSource.startedAt = GetTime()
    else
        activeSequenceSource.startedAt = math.max(GetTime(), Subtitles.LastEndTime or 0)
    end
    local entries, totalDuration = BuildSequenceEntries(activeSequenceSource)
    local renderMode = SubmitSequenceEntries(entries, append)
    if renderMode == "overlay" then
        UpdateRendererSuspensionState()
        UpdateOverlayLastEndTime()
    elseif renderMode == "dll" and not append then
        Subtitles.LastEndTime = activeSequenceSource.startedAt + totalDuration
    elseif renderMode == "dll" then
        Subtitles.LastEndTime = Subtitles.LastEndTime + totalDuration
    else
        activeSequenceSource = nil
        Subtitles.LastEndTime = GetTime()
    end
end

local function SubmitSubtitleText(text, duration, r, g, b)
    StartSequence({
        mode = "display",
        text = text,
        duration = duration,
        r = r,
        g = g,
        b = b,
    })
end

local function ClearActiveSequence()
    activeSequenceSource = nil
    ClearOverlayQueueState()
    ClearDefaultSubtitleQueue()
    ClearSubtitleChannel()
end

function Subtitles.RefreshActive()
    ResubmitActiveSequence()
end

function Subtitles.ClearActive()
    ClearActiveSequence()
    Subtitles.LastEndTime = GetTime()
end

function Subtitles.SetOpacity(value)
    Subtitles.Config.opacity = Clamp(tonumber(value) or 0.5, 0.0, 1.0)
    if subtitles and subtitles.set_opacity then
        subtitles.set_opacity(Subtitles.Config.opacity)
    end
    ResubmitActiveSequence()
end

function Subtitles.SetEnabled(value)
    Subtitles.Config.enabled = not not value
    if not Subtitles.Config.enabled then
        ClearActiveSequence()
        Subtitles.LastEndTime = GetTime()
    end
end

function Subtitles.SetFontScale(value)
    Subtitles.Config.fontScale = ClampRange(value, FONT_SCALE_MIN, FONT_SCALE_MAX, 1.0)
    ResubmitActiveSequence()
end

function Subtitles.SetSuspended(value)
    Subtitles.Config.suspended = not not value
    UpdateRendererSuspensionState()
end

function Subtitles.SetTextSizePreset(preset)
    local idx = math.floor(tonumber(preset) or 2)
    if idx < 1 then idx = 1 end
    if idx > 4 then idx = 4 end
    local legacyScale = (idx == 1 and 0.85) or (idx == 3 and 1.15) or (idx == 4 and 1.30) or 1.0
    Subtitles.SetFontScale(legacyScale)
end

--- Helper to read a 4-byte little-endian integer from a string
local function readInt32LE(s, pos)
    local b1, b2, b3, b4 = string.byte(s, pos, pos + 3)
    if not b1 or not b2 or not b3 or not b4 then return 0 end
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

--- Attempt to extract duration from a WAV header
--- @param wavFilename string
local function GetWavDuration(wavFilename)
    local content = UseItem(wavFilename)
    if not content or #content < 44 then return nil end

    -- RIFF Check
    if content:sub(1, 4) ~= "RIFF" or content:sub(9, 12) ~= "WAVE" then return nil end

    local pos = 13
    local byteRate = 0
    -- Scan chunks (fmt, data, etc.)
    while pos + 8 < #content do
        local chunkID = content:sub(pos, pos + 3)
        local chunkSize = readInt32LE(content, pos + 4)

        if chunkID == "fmt " then
            -- ByteRate is at offset 8 in the fmt chunk (pos + 8 + 8)
            byteRate = readInt32LE(content, pos + 16)
        elseif chunkID == "data" then
            if byteRate > 0 then
                return chunkSize / byteRate
            end
        end

        -- Move to next chunk (8 bytes header + data size)
        pos = pos + 8 + chunkSize
        -- Safety breakout for malformed headers
        if chunkSize < 0 or pos > #content then break end
    end
    return nil
end

--- Load durations from a CSV file (Filename,Duration)
--- @param csvFilename string
function Subtitles.LoadDurations(csvFilename)
    local content = UseItem(csvFilename)
    if content then
        for line in string.gmatch(content, "[^\r\n]+") do
            -- Simple comma separation
            local file, dur = string.match(line, "([^,]+),(.+)")
            if file and dur then
                durations[string.lower(file)] = tonumber(dur)
            end
        end
        print("Subtitles: Loaded durations from " .. csvFilename)
    else
        print("Subtitles: Could not load duration file " .. csvFilename)
    end
end

--- Initialize the subtitles system
--- @param durationCsv string|nil Optional path to duration CSV
function Subtitles.Initialize(durationCsv)
    -- Ensure clear queue on start
    ClearActiveSequence()
    Subtitles.SetOpacity(Subtitles.Config.opacity)
    Subtitles.SetFontScale(Subtitles.Config.fontScale)

    -- Load default durations if nothing specified
    durationCsv = durationCsv or "durations.csv"
    Subtitles.LoadDurations(durationCsv)
end

--- Wrapper for showing a transient message without audio
--- @param text string The text to display
--- @param r number|nil Red (0-1)
--- @param g number|nil Green (0-1)
--- @param b number|nil Blue (0-1)
--- @param duration number|nil Duration in seconds
function Subtitles.Display(text, r, g, b, duration)
    if not Subtitles.Config.enabled then
        return
    end
    r = r or 1.0
    g = g or 1.0
    b = b or 1.0

    -- Heuristic for display duration: ~15 chars per second, min 3s
    if not duration then
        duration = math.max(3.0, #text / 18.0)
    end

    SubmitSubtitleText(text, duration, r, g, b)
end

--- Helper to wrap text at a certain character limit
--- @param str string
--- @param limit number
function Subtitles.WrapText(str, limit)
    limit = limit or 50
    local here = 1
    local wrapped = str:gsub("(%s+)()(%S+)()", function(sp, st, word, fi)
        if fi - here > limit then
            here = st
            return "\n" .. word
        end
    end)
    return wrapped
end

--- Play an audio message and display associated subtitles
--- @param wavFilename string The .wav file to play
--- @param r number|nil Red (0-1)
--- @param g number|nil Green (0-1)
--- @param b number|nil Blue (0-1)
--- @return userdata The audio message handle
function Subtitles.Play(wavFilename, r, g, b)
    -- Clear any existing audio and subtitles
    Subtitles.Stop()
    Subtitles.SetOpacity(Subtitles.Config.opacity)

    -- Default to white if not provided
    if r == nil then r = 1.0 end
    if g == nil then g = 1.0 end
    if b == nil then b = 1.0 end

    -- 1. Play the audio
    local handle = AudioMessage(wavFilename)
    currentAudioHandle = handle
    if not Subtitles.Config.enabled then
        return handle
    end

    -- 2. Try to find and load the subtitle text
    -- Convert .wav extension to .txt (case insensitive replacement if needed, but simple sub usually works)
    local txtFilename = string.gsub(wavFilename, "%.[wW][aA][vV]$", ".txt")

    -- If no extension was present, append .txt
    if txtFilename == wavFilename then
        txtFilename = wavFilename .. ".txt"
    end

    -- Use native BZ98R 2.0+ API to read file content
    -- This searches the asset path, so it should find files in addon/ folder
    local content = UseItem(txtFilename)

    if content then
        -- Determine duration
        -- 1. Check CSV database
        local dur = durations[string.lower(wavFilename)]

        -- 2. Try to extract from WAV header
        if not dur then
            dur = GetWavDuration(wavFilename)
        end

        -- 3. Heuristic: Calculate based on character count as final fallback
        if not dur then
            dur = math.max(DEFAULT_DURATION, #content / 18.0)
        end

        StartSequence({
            mode = "play",
            text = content,
            duration = dur,
            r = r,
            g = g,
            b = b,
        })
    else
        activeSequenceSource = nil
        print("Subtitles: Could not find text file " .. txtFilename)
        -- Optionally clear queue if we want silence to clear previous subs
    end

	return handle
end

--- Play an audio message and queue associated subtitles
--- @param wavFilename string The .wav file to play
--- @param r number|nil Red (0-1)
--- @param g number|nil Green (0-1)
--- @param b number|nil Blue (0-1)
--- @return userdata The audio message handle
function Subtitles.Queue(wavFilename, r, g, b)
    Subtitles.SetOpacity(Subtitles.Config.opacity)

    if r == nil then r = 1.0 end
    if g == nil then g = 1.0 end
    if b == nil then b = 1.0 end

    local handle = AudioMessage(wavFilename)
    
    if currentAudioHandle and not IsAudioMessageDone(currentAudioHandle) then
        currentAudioHandle = handle
    else
        currentAudioHandle = handle
    end

    if not Subtitles.Config.enabled then
        return handle
    end

    local txtFilename = string.gsub(wavFilename, "%.[wW][aA][vV]$", ".txt")
    if txtFilename == wavFilename then
        txtFilename = wavFilename .. ".txt"
    end
    local content = UseItem(txtFilename)

    if content then
        local dur = durations[string.lower(wavFilename)]
        if not dur then dur = GetWavDuration(wavFilename) end
        if not dur then dur = math.max(DEFAULT_DURATION, #content / 18.0) end

        StartSequence({
            mode = "play",
            text = content,
            duration = dur,
            r = r,
            g = g,
            b = b,
        }, true)
    else
        activeSequenceSource = nil
        print("Subtitles: Could not find text file " .. txtFilename)
    end

    return handle
end

--- Update loop to synchronize subtitles with audio
function Subtitles.Update()
    UpdateRendererSuspensionState()

    if overlayState.currentEntry and not overlayState.effectiveSuspended then
        local now = GetTime()
        while overlayState.currentEntry and now >= ((overlayState.currentEntry.startTime or now) + overlayState.currentEntry.duration) do
            overlayState.currentEntry = nil
            HideSubtitleOverlay()
            if not StartNextOverlayEntry() then
                break
            end
        end
        UpdateOverlayLastEndTime()
    end

    if currentAudioHandle then
        if IsAudioMessageDone(currentAudioHandle) then
            ClearActiveSequence()
            currentAudioHandle = nil
            -- When audio finishes, we might still have a visual duration pending
        end
    end
end

--- Check if the subtitle system is currently playing audio or displaying text
--- @return boolean
function Subtitles.IsActive()
    if not Subtitles.Config.enabled then
        return false
    end
    if currentAudioHandle and not IsAudioMessageDone(currentAudioHandle) then
        return true
    end
    if GetTime() < Subtitles.LastEndTime then
        return true
    end
    return false
end

--- Returns the time when the current subtitle sequence will finish
--- @return number
function Subtitles.GetLastEndTime()
    return Subtitles.LastEndTime
end

--- Stop the currently playing audio and clear subtitles
function Subtitles.Stop()
    if currentAudioHandle then
        StopAudioMessage(currentAudioHandle)
        currentAudioHandle = nil
    end
    ClearActiveSequence()
    -- subtitles.set_opacity(0.0) -- Hide immediately (No longer needed with clear_current)
end

return Subtitles
