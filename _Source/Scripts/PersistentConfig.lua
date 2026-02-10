-- PersistentConfig.lua
local bzfile = require("bzfile")
local exu = require("exu")
local subtitles = require("subtitles")

local PersistentConfig = {}

-- Default Settings
PersistentConfig.Settings = {
    HeadlightDiffuse = {R = 5.0, G = 5.0, B = 5.0}, -- Increased default brightness
    HeadlightSpecular = {R = 5.0, G = 5.0, B = 5.0},
    HeadlightRange = {InnerAngle = 0.1, OuterAngle = 0.2, Falloff = 1.0}, -- Default to Focused
    HeadlightBeamMode = 1, -- 1 = Focused, 2 = Wide
    HeadlightVisible = true,
    SubtitlesEnabled = true,
    OtherHeadlightsDisabled = false
}

local configPath = bzfile.GetWorkingDirectory() .. "\\campaignReimagined_settings.cfg"

-- Logging Helper
local function Log(msg)
    if Print then
        Print(msg)
    else
        print(msg)
    end
end

-- On-Screen Feedback Helper
local function ShowFeedback(msg, r, g, b)
    Log(msg) -- Always log to console/Print
    if subtitles and subtitles.submit then
        subtitles.clear_queue()
        subtitles.set_opacity(0.5) -- 50% opacity for better readability
        subtitles.submit(msg, 2.0, r or 0.8, g or 0.8, b or 1.0)
    end
end

-- Internal State
local InputState = {
    last_f_state = false,
    last_c_state = false,
    last_u_state = false,
    last_b_state = false,
    last_help_state = false,
    SubtitlesPaused = false
}

-- Beam Definitions
local BeamModes = {
    [1] = {Inner = 0.1, Outer = 0.2}, -- Focused
    [2] = {Inner = 0.6, Outer = 0.9}  -- Wide
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

function PersistentConfig.LoadConfig()
    -- Attempt to verify file existence via io if possible, but bzfile is safer context
    -- Use pcall to catch "not open" error if bzfile.Open returns a zombie handle
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
                if key == "HeadlightDiffuseR" then PersistentConfig.Settings.HeadlightDiffuse.R = tonumber(val) or 5.0
                elseif key == "HeadlightDiffuseG" then PersistentConfig.Settings.HeadlightDiffuse.G = tonumber(val) or 5.0
                elseif key == "HeadlightDiffuseB" then PersistentConfig.Settings.HeadlightDiffuse.B = tonumber(val) or 5.0
                elseif key == "HeadlightSpecularR" then PersistentConfig.Settings.HeadlightSpecular.R = tonumber(val) or 5.0
                elseif key == "HeadlightSpecularG" then PersistentConfig.Settings.HeadlightSpecular.G = tonumber(val) or 5.0
                elseif key == "HeadlightSpecularB" then PersistentConfig.Settings.HeadlightSpecular.B = tonumber(val) or 5.0
                elseif key == "HeadlightBeamMode" then PersistentConfig.Settings.HeadlightBeamMode = tonumber(val) or 1
                elseif key == "HeadlightFalloff" then PersistentConfig.Settings.HeadlightRange.Falloff = tonumber(val) or 1.0
                elseif key == "HeadlightVisible" then PersistentConfig.Settings.HeadlightVisible = (val == "true")
                elseif key == "SubtitlesEnabled" then PersistentConfig.Settings.SubtitlesEnabled = (val == "true")
                elseif key == "OtherHeadlightsDisabled" then PersistentConfig.Settings.OtherHeadlightsDisabled = (val == "true")
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
    
    -- Sync ranges based on mode
    local mode = PersistentConfig.Settings.HeadlightBeamMode
    if BeamModes[mode] then
        PersistentConfig.Settings.HeadlightRange.InnerAngle = BeamModes[mode].Inner
        PersistentConfig.Settings.HeadlightRange.OuterAngle = BeamModes[mode].Outer
    end
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
        
        f:Close()
        print("PersistentConfig: File closed successfully")
    end)
    
    if not status then
        print("PersistentConfig: Error saving config: " .. tostring(err))
    else
        print("PersistentConfig: Settings saved successfully to: " .. configPath)
    end
end

function PersistentConfig.ApplySettings()
    if not exu then return end

    local h = GetPlayerHandle()
    if IsValid(h) then
        -- Sync ranges based on mode before applying
        local mode = PersistentConfig.Settings.HeadlightBeamMode
        if BeamModes[mode] then
            PersistentConfig.Settings.HeadlightRange.InnerAngle = BeamModes[mode].Inner
            PersistentConfig.Settings.HeadlightRange.OuterAngle = BeamModes[mode].Outer
        end

        if exu.SetHeadlightDiffuse then
            exu.SetHeadlightDiffuse(h, PersistentConfig.Settings.HeadlightDiffuse.R, PersistentConfig.Settings.HeadlightDiffuse.G, PersistentConfig.Settings.HeadlightDiffuse.B)
        end
        if exu.SetHeadlightSpecular then
            exu.SetHeadlightSpecular(h, PersistentConfig.Settings.HeadlightSpecular.R, PersistentConfig.Settings.HeadlightSpecular.G, PersistentConfig.Settings.HeadlightSpecular.B)
        end
        if exu.SetHeadlightRange then
            exu.SetHeadlightRange(h, PersistentConfig.Settings.HeadlightRange.InnerAngle, PersistentConfig.Settings.HeadlightRange.OuterAngle, PersistentConfig.Settings.HeadlightRange.Falloff)
        end
        if exu.SetHeadlightVisible then
            exu.SetHeadlightVisible(h, PersistentConfig.Settings.HeadlightVisible)
        end
    end

    if exu.SetSubtitlesEnabled then
        exu.SetSubtitlesEnabled(PersistentConfig.Settings.SubtitlesEnabled)
    end
end

-- Reusable update logic for all missions
function PersistentConfig.UpdateInputs()
    if not exu or not exu.GetGameKey then return end

    -- Toggle Player Headlight (F)
    local f_key = exu.GetGameKey("F")
    if f_key and not InputState.last_f_state then
        PersistentConfig.Settings.HeadlightVisible = not PersistentConfig.Settings.HeadlightVisible
        PersistentConfig.SaveConfig()
        PersistentConfig.ApplySettings()
        ShowFeedback("Player Light: " .. (PersistentConfig.Settings.HeadlightVisible and "ON" or "OFF"))
    end
    InputState.last_f_state = f_key

    -- Cycle Headlight Color (C)
    local c_key = exu.GetGameKey("C")
    if c_key and not InputState.last_c_state then
        local colors = {
            {5.0, 5.0, 5.0}, -- Bright White
            {5.0, 1.0, 1.0}, -- Bright Red
            {1.0, 5.0, 1.0}, -- Bright Green
            {1.0, 1.0, 5.0}, -- Bright Blue
            {5.0, 5.0, 1.0}  -- Bright Yellow
        }
        
        local currentIdx = 1
        for i, c in ipairs(colors) do
            if math.abs(PersistentConfig.Settings.HeadlightDiffuse.R - c[1]) < 0.1 and
               math.abs(PersistentConfig.Settings.HeadlightDiffuse.G - c[2]) < 0.1 and
               math.abs(PersistentConfig.Settings.HeadlightDiffuse.B - c[3]) < 0.1 then
                currentIdx = i
                break
            end
        end
        
        local nextIdx = (currentIdx % #colors) + 1
        PersistentConfig.Settings.HeadlightDiffuse.R = colors[nextIdx][1]
        PersistentConfig.Settings.HeadlightDiffuse.G = colors[nextIdx][2]
        PersistentConfig.Settings.HeadlightDiffuse.B = colors[nextIdx][3]
        PersistentConfig.SaveConfig()
        PersistentConfig.ApplySettings()
        ShowFeedback("Headlight Color Cycled", PersistentConfig.Settings.HeadlightDiffuse.R, PersistentConfig.Settings.HeadlightDiffuse.G, PersistentConfig.Settings.HeadlightDiffuse.B)
    end
    InputState.last_c_state = c_key

    -- Toggle AI/NPC Headlights (U)
    local u_key = exu.GetGameKey("U")
    if u_key and not InputState.last_u_state then
        PersistentConfig.Settings.OtherHeadlightsDisabled = not PersistentConfig.Settings.OtherHeadlightsDisabled
        PersistentConfig.SaveConfig()
        ShowFeedback("AI Lights: " .. (PersistentConfig.Settings.OtherHeadlightsDisabled and "OFF" or "ON"))
        
        if not PersistentConfig.Settings.OtherHeadlightsDisabled then
            local player = GetPlayerHandle()
            for h in AllCraft() do
                if h ~= player and exu.SetHeadlightVisible then
                    exu.SetHeadlightVisible(h, true)
                end
            end
        end
    end
    InputState.last_u_state = u_key

    -- Toggle Headlight Beam Mode (B for "Beams")
    local b_key = exu.GetGameKey("B")
    if b_key and not InputState.last_b_state then
        PersistentConfig.Settings.HeadlightBeamMode = (PersistentConfig.Settings.HeadlightBeamMode % 2) + 1
        PersistentConfig.SaveConfig()
        PersistentConfig.ApplySettings()
        local modeName = PersistentConfig.Settings.HeadlightBeamMode == 1 and "FOCUSED" or "WIDE"
        ShowFeedback("Beam: " .. modeName)
    end
    InputState.last_b_state = b_key

    -- Help Popup (/ or ? key) - using stock BZ API
    local help_pressed = (LastGameKey == "/" or LastGameKey == "?")
    if help_pressed and not InputState.last_help_state then
        -- Condensed Help Text
        local helpMsg = "KEYS: F:Light | C:Color | U:AI-Lights\n" ..
                        "B:Beam | /:Help | ESC:Hide-Subs"
        
        -- Show for longer duration (e.g. 5 seconds)
        if subtitles and subtitles.submit then
            subtitles.clear_queue()
            subtitles.set_opacity(0.5)
            subtitles.submit(helpMsg, 5.0, 1.0, 1.0, 1.0)
        end
    end
    InputState.last_help_state = help_pressed

    -- Pause Menu Handling (Escape Key) - IMMEDIATE effect
    if exu.GetGameKey("ESCAPE") then
        if subtitles and subtitles.set_opacity then
            subtitles.set_opacity(0.0)
        end
        if subtitles and subtitles.clear_queue then
            subtitles.clear_queue()
        end
        InputState.SubtitlesPaused = true
    else
        if InputState.SubtitlesPaused then
            if subtitles and subtitles.set_opacity then
                subtitles.set_opacity(0.5)
            end
            InputState.SubtitlesPaused = false
        end
    end
end

function PersistentConfig.UpdateHeadlights()
    if not exu or not exu.SetHeadlightVisible then return end
    if not PersistentConfig.Settings.OtherHeadlightsDisabled then return end

    local player = GetPlayerHandle()
    for h in AllObjects() do
        if h ~= player then
            exu.SetHeadlightVisible(h, false)
        end
    end
end

function PersistentConfig.Initialize()
    PersistentConfig.LoadConfig()
    -- Ensure config file is created if it doesn't exist
    PersistentConfig.SaveConfig()
    PersistentConfig.ApplySettings()
    
    -- Standardized Steam Greeting
    if exu and exu.GetSteam64 then
        local steamID = exu.GetSteam64()
        -- Valid Steam64 IDs are 17 digits long, so check for at least 10 to be safe
        if steamID and steamID ~= "" and steamID ~= "0" and #steamID >= 10 then
            print("Steam User ID Found: " .. steamID)
            ShowFeedback("Welcome back, Commander.", 0.5, 0.8, 1.0)
        else
            print("Steam ID not available or invalid: " .. tostring(steamID))
        end
    end

    -- Hook Mission End Functions to clear subtitles
    if not PersistentConfig.HooksInstalled then
        if SucceedMission then
            local oldSucceed = SucceedMission
            SucceedMission = function(...)
                if subtitles and subtitles.clear_queue then subtitles.clear_queue() end
                oldSucceed(...)
            end
        end
        if FailMission then
            local oldFail = FailMission
            FailMission = function(...)
                if subtitles and subtitles.clear_queue then subtitles.clear_queue() end
                oldFail(...)
            end
        end
        PersistentConfig.HooksInstalled = true
    end
end

return PersistentConfig
