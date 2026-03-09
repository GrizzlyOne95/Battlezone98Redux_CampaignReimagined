-- Subtitles.lua
-- Wrapper for subtitles.dll with automated text loading
local subtitles = require("subtitles")
local exu = require("exu")

local Subtitles = {}
local SUBTITLE_CHANNEL = 3
local TEXT_PRESETS = {
    [1] = { scale = 0.85 },
    [2] = { scale = 1.00 },
    [3] = { scale = 1.15 },
    [4] = { scale = 1.30 },
}

-- State
local currentAudioHandle = nil
local DEFAULT_DURATION = 8.0
local durations = {}
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

local function ApplySubtitleLayout()
    if not subtitles.set_channel_layout or not subtitles.submit_to then
        return false
    end

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
    local uiScaleFactor = Clamp((uiScale / 2.0) ^ 0.42, 0.85, 1.45)
    local textScale = Clamp(0.27 * aspectScale * uiScaleFactor * preset.scale, 0.20, 0.48)
    local wrapWidth = Clamp(0.46 * Clamp(1.0 / aspectScale, 0.92, 1.18) * uiScaleFactor, 0.34, 0.72)
    local paddingX = 6.0 * preset.scale
    local paddingY = 5.0 * preset.scale
    local opacity = Clamp(tonumber(Subtitles.Config.opacity) or 0.5, 0.0, 1.0)

    subtitles.set_channel_layout(SUBTITLE_CHANNEL, 0.5, 0.95, 0.5, 1.0, textScale, wrapWidth, paddingX, paddingY, opacity)
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

local function SubmitSubtitleText(text, duration, r, g, b)
    if ApplySubtitleLayout() then
        ClearSubtitleChannel()
        subtitles.submit_to(SUBTITLE_CHANNEL, text, duration, r, g, b)
    else
        subtitles.clear_queue()
        if subtitles.clear_current then subtitles.clear_current() end
        subtitles.set_opacity(Clamp(tonumber(Subtitles.Config.opacity) or 0.5, 0.0, 1.0))
        subtitles.submit(text, duration, r, g, b)
    end
end

function Subtitles.SetOpacity(value)
    Subtitles.Config.opacity = Clamp(tonumber(value) or 0.5, 0.0, 1.0)
    if subtitles.set_opacity then
        subtitles.set_opacity(Subtitles.Config.opacity)
    end
end

function Subtitles.SetTextSizePreset(preset)
    local idx = math.floor(tonumber(preset) or 2)
    if idx < 1 then idx = 1 end
    if idx > #TEXT_PRESETS then idx = #TEXT_PRESETS end
    Subtitles.Config.textSizePreset = idx
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
    subtitles.clear_queue()
    ClearSubtitleChannel()
    Subtitles.SetOpacity(Subtitles.Config.opacity)

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

    local wrapped = Subtitles.WrapText(text, 50)
    SubmitSubtitleText(wrapped, duration, r, g, b)
    Subtitles.LastEndTime = GetTime() + duration
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

        -- Submit with looked up duration
        local final_text = Subtitles.WrapText(content, 50)

        -- Split into pages if too long (max 2 lines per page for better readability)
        local lines = {}
        for line in string.gmatch(final_text, "[^\r\n]+") do
            table.insert(lines, line)
        end

        local chunks = {}
        local current_chunk = {}

        for _, line in ipairs(lines) do
            table.insert(current_chunk, line)
            if #current_chunk >= 2 then
                table.insert(chunks, table.concat(current_chunk, "\n"))
                current_chunk = {}
            end
        end
        if #current_chunk > 0 then
            table.insert(chunks, table.concat(current_chunk, "\n"))
        end

        -- Submit chunks with weighted duration (longer chunks get more time)
        local total_chars = #content
        if total_chars > 0 then
            if ApplySubtitleLayout() then
                ClearSubtitleChannel()
            end
            for _, chunk in ipairs(chunks) do
                local chunk_weight = #chunk / total_chars
                local chunk_dur = dur * chunk_weight
                local final_dur = math.max(1.5, chunk_dur)
                if ApplySubtitleLayout() then
                    subtitles.submit_to(SUBTITLE_CHANNEL, chunk, final_dur, r, g, b)
                else
                    subtitles.submit(chunk, final_dur, r, g, b)
                end
                Subtitles.LastEndTime = GetTime() + final_dur
            end
        end
    else
        print("Subtitles: Could not find text file " .. txtFilename)
        -- Optionally clear queue if we want silence to clear previous subs
    end

    return handle
end

--- Update loop to synchronize subtitles with audio
function Subtitles.Update()
    if currentAudioHandle then
        if IsAudioMessageDone(currentAudioHandle) then
            subtitles.clear_queue()
            if subtitles.clear_current then subtitles.clear_current() end
            ClearSubtitleChannel()
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
    subtitles.clear_queue()
    if subtitles.clear_current then subtitles.clear_current() end
    ClearSubtitleChannel()
    -- subtitles.set_opacity(0.0) -- Hide immediately (No longer needed with clear_current)
end

return Subtitles
