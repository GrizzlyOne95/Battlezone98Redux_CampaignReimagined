-- Subtitles.lua
-- Wrapper for subtitles.dll with automated text loading
local subtitles = require("subtitles")
local exu = require("exu")

local Subtitles = {}
local SUBTITLE_CHANNEL = 3
local TEXT_PRESETS = {
    [1] = { scale = 0.85, wrapScale = 1.00, charLimit = 54 },
    [2] = { scale = 1.00, wrapScale = 1.35, charLimit = 78 },
    [3] = { scale = 1.15, wrapScale = 1.95, charLimit = 114 },
    [4] = { scale = 1.30, wrapScale = 3.00, charLimit = 150 },
}

-- State
local currentAudioHandle = nil
local DEFAULT_DURATION = 8.0
local durations = {}
local activeSequenceSource = nil
Subtitles.LastEndTime = 0
Subtitles.Config = {
    opacity = 0.5,
    textSizePreset = 2,
}

local function Clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function GetTextPreset()
    local idx = math.floor(tonumber(Subtitles.Config.textSizePreset) or 2)
    return TEXT_PRESETS[idx] or TEXT_PRESETS[2]
end

local function GetWrapCharacterLimit()
    return GetTextPreset().charLimit or 78
end

local function GetSubtitleLayoutMetrics()
    local width, height = 1920, 1080
    local uiScale = 2.0
    local preset = GetTextPreset()

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
    local aspectScale = Clamp((16.0 / 9.0) / aspect, 0.78, 1.35)
    local uiScaleFactor = Clamp((uiScale / 2.0) ^ 0.32, 0.90, 1.30)

    return {
        textScale = Clamp(0.38 * aspectScale * uiScaleFactor * preset.scale, 0.28, 0.58),
        wrapWidth = Clamp(0.84 * Clamp(1.0 / aspectScale, 0.90, 1.22) * preset.wrapScale, 0.68, 2.60),
        paddingX = 10.0 * preset.scale,
        paddingY = 8.0 * preset.scale,
        opacity = Clamp(tonumber(Subtitles.Config.opacity) or 0.5, 0.0, 1.0),
    }
end

local function ApplySubtitleLayout()
    if not subtitles.set_channel_layout or not subtitles.submit_to then
        return false
    end

    local layout = GetSubtitleLayoutMetrics()
    subtitles.set_channel_layout(SUBTITLE_CHANNEL, 0.5, 0.97, 0.5, 1.0, layout.textScale, layout.wrapWidth, layout.paddingX,
        layout.paddingY, layout.opacity)
    return true
end

local function ClearSubtitleChannel()
    if subtitles.clear_queue then
        subtitles.clear_queue(SUBTITLE_CHANNEL)
    end
    if subtitles.clear_current then
        subtitles.clear_current(SUBTITLE_CHANNEL)
    end
end

local function ClearDefaultSubtitleQueue()
    subtitles.clear_queue()
    if subtitles.clear_current then
        subtitles.clear_current()
    end
end

local function SubmitSequenceEntries(entries)
    if not entries or #entries == 0 then
        return
    end

    if ApplySubtitleLayout() then
        ClearSubtitleChannel()
        for _, entry in ipairs(entries) do
            subtitles.submit_to(SUBTITLE_CHANNEL, entry.text, entry.duration, entry.r, entry.g, entry.b)
        end
    else
        ClearDefaultSubtitleQueue()
        subtitles.set_opacity(Clamp(tonumber(Subtitles.Config.opacity) or 0.5, 0.0, 1.0))
        for _, entry in ipairs(entries) do
            subtitles.submit(entry.text, entry.duration, entry.r, entry.g, entry.b)
        end
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

    SubmitSequenceEntries(remaining)
    Subtitles.LastEndTime = GetTime() + remainingDuration
end

local function StartSequence(source)
    activeSequenceSource = source
    activeSequenceSource.startedAt = GetTime()
    local entries, totalDuration = BuildSequenceEntries(activeSequenceSource)
    SubmitSequenceEntries(entries)
    Subtitles.LastEndTime = activeSequenceSource.startedAt + totalDuration
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
    if subtitles.set_opacity then
        subtitles.set_opacity(Subtitles.Config.opacity)
    end
    ResubmitActiveSequence()
end

function Subtitles.SetTextSizePreset(preset)
    local idx = math.floor(tonumber(preset) or 2)
    if idx < 1 then idx = 1 end
    if idx > #TEXT_PRESETS then idx = #TEXT_PRESETS end
    Subtitles.Config.textSizePreset = idx
    ResubmitActiveSequence()
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
    Subtitles.SetTextSizePreset(Subtitles.Config.textSizePreset)

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

--- Update loop to synchronize subtitles with audio
function Subtitles.Update()
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
