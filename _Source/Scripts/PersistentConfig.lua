-- PersistentConfig.lua
---@diagnostic disable: lowercase-global, undefined-global
local bzfile = require("bzfile")
local exu = require("exu")
local subtitles = require("subtitles")
local autosave = require("AutoSave")

local PersistentConfig = {}

-- Default Settings
PersistentConfig.Settings = {
    HeadlightDiffuse = { R = 5.0, G = 5.0, B = 5.0 },                       -- White
    HeadlightSpecular = { R = 5.0, G = 5.0, B = 5.0 },
    HeadlightRange = { InnerAngle = 0.6, OuterAngle = 0.9, Falloff = 1.0 }, -- Default to Wide
    HeadlightBeamMode = 2,                                                  -- 1 = Focused, 2 = Wide
    HeadlightVisible = true,
    SubtitlesEnabled = true,
    OtherHeadlightsDisabled = true, -- AI Lights Off by default
    AutoRepairWingmen = nil,        -- Initialized via difficulty if not in config
    RainbowMode = false,            -- Special color effect
    enableAutoSave = false          -- Experimental: ON/OFF
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
local function ShowFeedback(msg, r, g, b)
    Log(msg) -- Always log to console/Print
    if subtitles and subtitles.submit then
        subtitles.clear_queue()
        subtitles.set_opacity(0.5) -- 50% opacity for better readability
        subtitles.submit(msg, 2.0, r or 0.8, g or 0.8, b or 1.0)
    end
end

-- Helper to parse bzlogger.txt for Steam ID/Username
local function ParseBzLogger()
    if not bzfile or not bzfile.Open then return nil, nil end
    local logPath = "bzlogger.txt"
    local f = bzfile.Open(logPath, "r")

    if not f then
        print("PersistentConfig: Could not find " .. logPath .. " for parsing.")
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

-- Shared Greeting Logic
function PersistentConfig.TriggerGreeting(steamID, username)
    local CustomNames = {
        ["76561198241259700"] = "GlizzyJuan",   -- GrizzlyOne95
        ["76561198104781489"] = "British Twat", --JJ
        ["76561199014392897"] = "Car Nerd",     --DriveLine
    }

    local displayName = CustomNames[steamID] or username

    if displayName then
        ShowFeedback("Welcome back, Commander " .. displayName .. ".", 0.5, 0.8, 1.0)
        print("Steam User: " .. displayName .. " (" .. steamID .. ")")
    else
        ShowFeedback("Welcome back, Commander.", 0.5, 0.8, 1.0)
        print("Steam User ID: " .. steamID)
    end
end

-- Internal State
local InputState = {
    last_v_state = false, -- Headlight (V)
    last_z_state = false, -- Color (Z)
    last_j_state = false, -- AI Lights (J)
    last_b_state = false, -- Beam (B)
    last_help_state = false,
    last_x_state = false, -- Auto-repair toggle
    last_n_state = false, -- Manual Save (N)
    SubtitlesPaused = false,
    SteamIDFound = false,
    GreetingTriggered = false,
    PollingStartTime = 0
}

-- Beam Definitions
local BeamModes = {
    [1] = { Inner = 0.1, Outer = 0.2 }, -- Focused
    [2] = { Inner = 0.6, Outer = 0.9 }  -- Wide
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
                    PersistentConfig.Settings.HeadlightBeamMode = tonumber(val) or 1
                elseif key == "HeadlightFalloff" then
                    PersistentConfig.Settings.HeadlightRange.Falloff = tonumber(val) or 1.0
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
                elseif key == "enableAutoSave" then
                    PersistentConfig.Settings.enableAutoSave = (val == "true")
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
        f:Writeln("AutoRepairWingmen=" .. tostring(PersistentConfig.Settings.AutoRepairWingmen))
        f:Writeln("RainbowMode=" .. tostring(PersistentConfig.Settings.RainbowMode))
        f:Writeln("enableAutoSave=" .. tostring(PersistentConfig.Settings.enableAutoSave))

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
            exu.SetHeadlightDiffuse(h, PersistentConfig.Settings.HeadlightDiffuse.R,
                PersistentConfig.Settings.HeadlightDiffuse.G, PersistentConfig.Settings.HeadlightDiffuse.B)
        end
        if exu.SetHeadlightSpecular then
            exu.SetHeadlightSpecular(h, PersistentConfig.Settings.HeadlightSpecular.R,
                PersistentConfig.Settings.HeadlightSpecular.G, PersistentConfig.Settings.HeadlightSpecular.B)
        end
        if exu.SetHeadlightRange then
            exu.SetHeadlightRange(h, PersistentConfig.Settings.HeadlightRange.InnerAngle,
                PersistentConfig.Settings.HeadlightRange.OuterAngle, PersistentConfig.Settings.HeadlightRange.Falloff)
        end
        if exu.SetHeadlightVisible then
            exu.SetHeadlightVisible(h, PersistentConfig.Settings.HeadlightVisible)
        end
    end
end

-- Show help overlay
function PersistentConfig.ShowHelp()
    -- Condensed Help Text
    local helpMsg = "KEYS: V:Headlight On/Off | Z:Color | J:AI-Lights\n" ..
        "B:Beam | X:Auto-Repair | N:AutoSave | /:Help | ESC:Hide-Subs"

    -- Show with high precedence (clear queue, force opacity)
    if subtitles and subtitles.submit then
        subtitles.clear_queue()
        subtitles.set_opacity(0.5)
        subtitles.submit(helpMsg, 8.0, 1.0, 1.0, 1.0) -- Show for 8 seconds at start
    end
end

-- Reusable update logic for all missions
function PersistentConfig.UpdateInputs()
    if not exu or not exu.GetGameKey then return end

    -- Toggle Player Headlight (V)
    local v_key = exu.GetGameKey("V")
    if v_key and not InputState.last_v_state then
        PersistentConfig.Settings.HeadlightVisible = not PersistentConfig.Settings.HeadlightVisible
        PersistentConfig.SaveConfig()
        PersistentConfig.ApplySettings()
        ShowFeedback("Player Light: " .. (PersistentConfig.Settings.HeadlightVisible and "ON" or "OFF"))
    end
    InputState.last_v_state = v_key

    -- Cycle Headlight Color (Z) - Moved from Alt+C to Z
    local z_key = exu.GetGameKey("Z")
    if z_key and not InputState.last_z_state then
        local colors = {
            { 5.0, 5.0, 5.0 }, -- Bright White
            { 5.0, 1.0, 1.0 }, -- Bright Red
            { 1.0, 5.0, 1.0 }, -- Bright Green
            { 1.0, 1.0, 5.0 }, -- Bright Blue
            { 5.0, 5.0, 1.0 }, -- Bright Yellow
            { 1.0, 5.0, 5.0 }, -- Cyan
            { 5.0, 1.0, 5.0 }, -- Magenta
            { 5.0, 2.5, 1.0 }, -- Orange
            { 2.5, 1.0, 5.0 }, -- Purple
            { 1.0, 5.0, 2.5 }, -- Teal
            { -1,  -1,  -1 }   -- [SPECIAL] Rainbow Mode
        }

        local currentIdx = 1
        if PersistentConfig.Settings.RainbowMode then
            currentIdx = #colors
        else
            for i, c in ipairs(colors) do
                if math.abs(PersistentConfig.Settings.HeadlightDiffuse.R - c[1]) < 0.1 and
                    math.abs(PersistentConfig.Settings.HeadlightDiffuse.G - c[2]) < 0.1 and
                    math.abs(PersistentConfig.Settings.HeadlightDiffuse.B - c[3]) < 0.1 then
                    currentIdx = i
                    break
                end
            end
        end

        local nextIdx = (currentIdx % #colors) + 1
        if nextIdx == #colors then
            PersistentConfig.Settings.RainbowMode = true
            ShowFeedback("Rainbow Mode: ACTIVATE", 1.0, 0.5, 1.0)
        else
            PersistentConfig.Settings.RainbowMode = false
            PersistentConfig.Settings.HeadlightDiffuse.R = colors[nextIdx][1]
            PersistentConfig.Settings.HeadlightDiffuse.G = colors[nextIdx][2]
            PersistentConfig.Settings.HeadlightDiffuse.B = colors[nextIdx][3]
            ShowFeedback("Headlight Color Cycled", PersistentConfig.Settings.HeadlightDiffuse.R,
                PersistentConfig.Settings.HeadlightDiffuse.G, PersistentConfig.Settings.HeadlightDiffuse.B)
        end

        PersistentConfig.SaveConfig()
        PersistentConfig.ApplySettings()
    end
    InputState.last_z_state = z_key

    -- Toggle AI/NPC Headlights (J) - Moved from Alt+U to J
    local j_key = exu.GetGameKey("J")
    if j_key and not InputState.last_j_state then
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
    InputState.last_j_state = j_key

    -- Toggle Headlight Beam Mode (B) - Removed Alt requirement
    local b_key = exu.GetGameKey("B")
    if b_key and not InputState.last_b_state then
        PersistentConfig.Settings.HeadlightBeamMode = (PersistentConfig.Settings.HeadlightBeamMode % 2) + 1
        PersistentConfig.SaveConfig()
        PersistentConfig.ApplySettings()
        local modeName = PersistentConfig.Settings.HeadlightBeamMode == 1 and "FOCUSED" or "WIDE"
        ShowFeedback("Beam: " .. modeName)
    end
    InputState.last_b_state = b_key

    -- Toggle Auto-Repair for Wingmen (X for "Auto-fiX")
    local x_key = exu.GetGameKey("X")
    if x_key and not InputState.last_x_state then
        PersistentConfig.Settings.AutoRepairWingmen = not PersistentConfig.Settings.AutoRepairWingmen
        PersistentConfig.SaveConfig()

        -- Apply to player team (team 1) immediately via aiCore
        if aiCore and aiCore.ActiveTeams and aiCore.ActiveTeams[1] then
            aiCore.ActiveTeams[1]:SetConfig("autoRepairWingmen", PersistentConfig.Settings.AutoRepairWingmen)
        end

        ShowFeedback("Auto-Repair: " .. (PersistentConfig.Settings.AutoRepairWingmen and "ON" or "OFF"), 0.8, 1.0, 0.8)
    end
    InputState.last_x_state = x_key

    -- Toggle AutoSave (N for "New AutoSave")
    local n_key = exu.GetGameKey("N")
    if n_key and not InputState.last_n_state then
        PersistentConfig.Settings.enableAutoSave = not PersistentConfig.Settings.enableAutoSave
        PersistentConfig.SaveConfig()
        ShowFeedback("AutoSave: " .. (PersistentConfig.Settings.enableAutoSave and "ON (5m)" or "OFF"), 0.6, 1.0, 0.6)
    end
    InputState.last_n_state = n_key

    -- Help Popup (/ or ? key) - using stock BZ API
    local help_pressed = (LastGameKey == "/" or LastGameKey == "?")
    if help_pressed and not InputState.last_help_state then
        PersistentConfig.ShowHelp()
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

    -- Update Rainbow Color if active
    if PersistentConfig.Settings.RainbowMode and PersistentConfig.Settings.HeadlightVisible then
        local hue = (GetTime() * 0.2) % 1.0 -- Cycle every 5 seconds
        local r, g, b = HueToRGB(hue)
        local h = GetPlayerHandle()
        if IsValid(h) and exu.SetHeadlightDiffuse then
            exu.SetHeadlightDiffuse(h, r, g, b)
            if exu.SetHeadlightSpecular then
                exu.SetHeadlightSpecular(h, r, g, b)
            end
        end
    end

    -- Steam ID Polling (Try for first 10 seconds)
    if not InputState.GreetingTriggered then
        local now = GetTime()
        if now - InputState.PollingStartTime < 10.0 then
            local steamID, username
            if exu and exu.GetSteam64 then
                steamID = exu.GetSteam64()
            end

            if not steamID or steamID == "" or steamID == "0" then
                steamID, username = ParseBzLogger()
            end

            if steamID and #steamID >= 10 then
                PersistentConfig.TriggerGreeting(steamID, username)
                InputState.GreetingTriggered = true
                InputState.SteamIDFound = true
            end
        else
            -- Polling timeout
            InputState.GreetingTriggered = true
            print("PersistentConfig: Steam ID polling timed out.")
        end
    end
end

function PersistentConfig.UpdateHeadlights()
    if not exu or not exu.SetHeadlightVisible then return end
    if not PersistentConfig.Settings.OtherHeadlightsDisabled then return end

    local player = GetPlayerHandle()
    for h in AllObjects() do
        if h ~= player and exu.SetHeadlightVisible then
            exu.SetHeadlightVisible(h, false)
        end
    end
end

function PersistentConfig.Initialize()
    PersistentConfig.LoadConfig()

    -- Default Auto-Repair based on difficulty if not explicitly set in config
    if PersistentConfig.Settings.AutoRepairWingmen == nil then
        local d = (exu and exu.GetDifficulty and exu.GetDifficulty()) or 2
        PersistentConfig.Settings.AutoRepairWingmen = (d <= 1)
        print("PersistentConfig: Defaulted Auto-Repair to " ..
            (PersistentConfig.Settings.AutoRepairWingmen and "ON" or "OFF") .. " based on difficulty.")
    end

    -- Ensure config file is created/updated
    PersistentConfig.SaveConfig()
    PersistentConfig.ApplySettings()

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

    -- 2. Immediate check
    if steamID and #steamID >= 10 then
        PersistentConfig.TriggerGreeting(steamID, username)
        InputState.GreetingTriggered = true
        InputState.SteamIDFound = true
    else
        print("PersistentConfig: Initial Steam ID retrieval failed. Starting background polling...")
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
