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
    if durationCsv then
        Subtitles.LoadDurations(durationCsv)
    end
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
        subtitles.submit(content, dur, r, g, b)
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
            currentAudioHandle = nil
        end
    end
end

return Subtitles
