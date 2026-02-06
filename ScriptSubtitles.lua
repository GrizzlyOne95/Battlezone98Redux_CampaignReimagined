-- Subtitles.lua
-- Wrapper for subtitles.dll with automated text loading
local subtitles = require("subtitles")

local Subtitles = {}

-- State
local currentAudioHandle = nil
local DEFAULT_DURATION = 8.0 
local durations = {}

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
    subtitles.set_opacity(0.5) -- Set to 50% opacity for better readability with borders
    if durationCsv then
        Subtitles.LoadDurations(durationCsv)
    end
end

--- Wrapper for showing a transient message without audio
--- @param text string The text to display
--- @param r number|nil Red (0-1)
--- @param g number|nil Green (0-1)
--- @param b number|nil Blue (0-1)
--- @param duration number|nil Duration in seconds
function Subtitles.Display(text, r, g, b, duration)
    subtitles.clear_queue()
    subtitles.set_opacity(0.5) -- Ensure visible
    
    r = r or 1.0
    g = g or 1.0
    b = b or 1.0
    duration = duration or 3.0
    
    local wrapped = Subtitles.WrapText(text, 50)
    subtitles.submit(wrapped, duration, r, g, b)
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
    -- Clear any existing subtitles to prevent overlaps or stale text from previous messages
    subtitles.clear_queue()
    subtitles.set_opacity(1.0) -- Ensure visible

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
        local dur = durations[string.lower(wavFilename)] or DEFAULT_DURATION
        
        -- Submit with looked up duration
        local final_text = Subtitles.WrapText(content, 50)
        
        -- Split into pages if too long (max 4 lines per page)
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
        
        -- Submit chunks with distributed duration
        local total_chunks = #chunks
        if total_chunks > 0 then
            local chunk_dur = dur / total_chunks
            for _, chunk in ipairs(chunks) do
                subtitles.submit(chunk, chunk_dur, r, g, b)
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
            currentAudioHandle = nil
        end
    end
end

--- Stop the currently playing audio and clear subtitles
function Subtitles.Stop()
    if currentAudioHandle then
        StopAudioMessage(currentAudioHandle)
        currentAudioHandle = nil
    end
    subtitles.clear_queue()
    if subtitles.clear_current then subtitles.clear_current() end
    -- subtitles.set_opacity(0.0) -- Hide immediately (No longer needed with clear_current)
end

return Subtitles
