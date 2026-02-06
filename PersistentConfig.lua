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

local configPath = bzfile.GetWorkingDirectory() .. "config\\campaign_settings.cfg"

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
    last_s_state = false,
    last_l_state = false,
    last_h_state = false,
    last_b_state = false
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
    
    -- Sync ranges based on mode
    local mode = PersistentConfig.Settings.HeadlightBeamMode
    if BeamModes[mode] then
        PersistentConfig.Settings.HeadlightRange.InnerAngle = BeamModes[mode].Inner
        PersistentConfig.Settings.HeadlightRange.OuterAngle = BeamModes[mode].Outer
    end
    
    print("PersistentConfig: Settings loaded.")
end

function PersistentConfig.SaveConfig()
    local f = bzfile.Open(configPath, "w", "trunc")
    if not f then
        print("PersistentConfig: Failed to open config file for writing!")
        return
    end

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
    print("PersistentConfig: Settings saved.")
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
            exu.SetHeadlightVisible(PersistentConfig.Settings.HeadlightVisible)
        end
    end

    if exu.SetSubtitlesEnabled then
        exu.SetSubtitlesEnabled(PersistentConfig.Settings.SubtitlesEnabled)
    end
end

-- Reusable update logic for all missions
function PersistentConfig.UpdateInputs()
    if not exu or not exu.GetGameKey then return end

    -- Toggle Subtitles (CTRL + ALT + S)
    local s_key = exu.GetGameKey("S")
    local s_combo = s_key and exu.GetGameKey("CTRL") and exu.GetGameKey("ALT")
    if s_combo and not InputState.last_s_state then
        PersistentConfig.Settings.SubtitlesEnabled = not PersistentConfig.Settings.SubtitlesEnabled
        PersistentConfig.SaveConfig()
        PersistentConfig.ApplySettings()
        ShowFeedback("Subtitles: " .. (PersistentConfig.Settings.SubtitlesEnabled and "ON" or "OFF"))
    end
    InputState.last_s_state = s_combo

    -- Toggle Non-Player Headlights (L key)
    local l_state = exu.GetGameKey("L")
    if l_state and not InputState.last_l_state then
        PersistentConfig.Settings.OtherHeadlightsDisabled = not PersistentConfig.Settings.OtherHeadlightsDisabled
        PersistentConfig.SaveConfig()
        ShowFeedback("Other Headlights: " .. (PersistentConfig.Settings.OtherHeadlightsDisabled and "DISABLED" or "ENABLED"))
        
        if not PersistentConfig.Settings.OtherHeadlightsDisabled then
            local player = GetPlayerHandle()
            for h in AllCraft() do
                if h ~= player and exu.SetHeadlightVisible then
                    exu.SetHeadlightVisible(h, true)
                end
            end
        end
    end
    InputState.last_l_state = l_state

    -- Cycle Headlight Color (SHIFT + H)
    local h_key = exu.GetGameKey("H")
    local h_combo = h_key and exu.GetGameKey("SHIFT")
    if h_combo and not InputState.last_h_state then
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
    InputState.last_h_state = h_combo

    -- Toggle Headlight Beam Mode (SHIFT + B)
    local b_key = exu.GetGameKey("B")
    local b_combo = b_key and exu.GetGameKey("SHIFT")
    if b_combo and not InputState.last_b_state then
        PersistentConfig.Settings.HeadlightBeamMode = (PersistentConfig.Settings.HeadlightBeamMode % 2) + 1
        PersistentConfig.SaveConfig()
        PersistentConfig.ApplySettings()
        local modeName = PersistentConfig.Settings.HeadlightBeamMode == 1 and "FOCUSED" or "WIDE"
        ShowFeedback("Headlight Beam: " .. modeName)
    end
    InputState.last_b_state = b_combo

    -- Help Popup (SHIFT + / which is ?)
    -- Note: "/" might be mapped as "OEM_2" or similar depending on engine, but "/" is standard attempt.
    local slash_key = exu.GetGameKey("/") or exu.GetGameKey("?")
    local help_combo = slash_key and exu.GetGameKey("SHIFT")
    if help_combo and not InputState.last_help_state then
        local helpMsg = "HOTKEYS:\n" ..
                        "CTRL+ALT+S: Toggle Subtitles\n" ..
                        "L: Toggle NPC Headlights\n" ..
                        "SHIFT+H: Cycle Headlight Color\n" ..
                        "SHIFT+B: Toggle Beam Mode\n" ..
                        "SHIFT+?: Show Help"
        
        -- Show for longer duration (e.g. 5 seconds)
        if subtitles and subtitles.submit then
            subtitles.clear_queue()
            subtitles.set_opacity(0.5)
            subtitles.submit(helpMsg, 5.0, 1.0, 1.0, 1.0)
        end
    end
    InputState.last_help_state = help_combo

    -- Pause Menu Handling (Escape Key)
    -- If ESC is pressed, we hide subtitles. If Update runs again (resume), we restore them.
    if exu.GetGameKey("ESCAPE") then
        if not InputState.SubtitlesPaused then
            if subtitles and subtitles.set_opacity then
                subtitles.set_opacity(0.0)
            end
            InputState.SubtitlesPaused = true
        end
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
    PersistentConfig.ApplySettings()
    
    -- Standardized Steam Greeting
    if exu and exu.GetSteam64 then
        local steamID = exu.GetSteam64()
        if steamID ~= "" then
            Log("Steam User ID Found: " .. steamID)
            ShowFeedback("Welcome back, Commander.", 0.5, 0.8, 1.0)
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
