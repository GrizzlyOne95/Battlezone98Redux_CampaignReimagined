-- PersistentConfig.lua
---@diagnostic disable: lowercase-global, undefined-global
local bzfile = require("bzfile")
local exu = require("exu")
local subtitles = require("subtitles")
local autosave = require("AutoSave")

local PersistentConfig = {}
local WEAPON_STATS_CHANNEL = 1
PersistentConfig.Debug = false
local InputState

-- Internal Feedback Queue
PersistentConfig.FeedbackQueue = {}

-- Default Settings
PersistentConfig.Settings = {
    HeadlightDiffuse = { R = 5.0, G = 5.0, B = 5.0 },                         -- White
    HeadlightSpecular = { R = 8.0, G = 8.0, B = 8.0 },                         -- Brighter specular
    HeadlightRange = { InnerAngle = 0.6, OuterAngle = 0.9, Falloff = 0.35 },   -- Default to Wide
    HeadlightBeamMode = 2,                                                      -- 1 = Focused, 2 = Wide
    HeadlightVisible = true,
    SubtitlesEnabled = true,
    OtherHeadlightsDisabled = true, -- AI Lights Off by default
    AutoRepairWingmen = true,       -- Auto-repair wingmen on by default
    RainbowMode = false,            -- Special color effect
    ScavengerAssistEnabled = false, -- Auto-scavenge for player scavengers
    AutoSaveSlot = 10,              -- Default to slot 10
    AutoSaveEnabled = false,        -- AutoSave disabled by default
    AutoSaveInterval = 200,         -- Auto-save every 200 seconds
    AutoRepairBuildings = false,    -- Toggle to auto-repair buildings near power
    RetroLighting = false,          -- Disables PBR and custom shader lighting equations
    WeaponStatsHud = true,          -- Persistent weapon stats panel
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
local function ShowFeedback(msg, r, g, b, duration, bypass)
    -- Push to queue instead of displaying immediately
    table.insert(PersistentConfig.FeedbackQueue, {
        msg = msg,
        r = r or 0.8,
        g = g or 0.8,
        b = b or 1.0,
        duration = duration or 2.0,
        bypass = (bypass == nil) and true or bypass -- Default to true for responsiveness
    })
    Log(msg)                                        -- Always log to console
end

local function ShowWeaponStats(msg, duration)
    if subtitles and subtitles.set_channel_layout and subtitles.submit_to then
        subtitles.set_channel_layout(WEAPON_STATS_CHANNEL, 0.985, 0.11, 1.0, 0.0, 0.6, 0.14, 6.0, 5.0, 1.0)
        subtitles.clear_queue(WEAPON_STATS_CHANNEL)
        if subtitles.clear_current then
            subtitles.clear_current(WEAPON_STATS_CHANNEL)
        end
        subtitles.submit_to(WEAPON_STATS_CHANNEL, msg, duration or 2.4, 0.35, 0.65, 1.0)
    else
        ShowFeedback(msg, 0.35, 0.65, 1.0, duration or 2.4, false)
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

local function MarkOtherHeadlightsDirty()
    InputState.otherHeadlightsDirty = true
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
    last_l_state = false,    -- Retro Lighting (Shift+L)
    last_s_state = false,    -- Weapon HUD toggle (Ctrl+S)
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
    otherHeadlightVisibility = {},
    otherHeadlightsDirty = true,
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

local function CleanString(s)
    if not s then return "" end
    return string.gsub(tostring(s), "%z", "")
end

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
        if found and value and value > 0 then
            if not best or value > best then best = value end
        end
    end
    return best
end

local function ProbeTravelRangeFromOdf(odf)
    if not odf or not GetODFFloat then return nil end

    local lifeSpan, lifeFound = GetODFFloat(odf, "OrdnanceClass", "lifeSpan", 0.0)
    if not lifeFound or not lifeSpan or lifeSpan <= 0 then
        lifeSpan, lifeFound = GetODFFloat(odf, nil, "lifeSpan", 0.0)
    end

    local shotSpeed, speedFound = GetODFFloat(odf, "OrdnanceClass", "shotSpeed", 0.0)
    if not speedFound or not shotSpeed or shotSpeed <= 0 then
        shotSpeed, speedFound = GetODFFloat(odf, nil, "shotSpeed", 0.0)
    end

    if lifeFound and speedFound and lifeSpan and shotSpeed and lifeSpan > 0 and shotSpeed > 0 then
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
    if found and cleaned ~= "" then
        return string.lower(cleaned)
    end

    value, found = GetODFString(odf, "WeaponClass", "classLabel", "")
    cleaned = CleanString(value)
    if found and cleaned ~= "" then
        return string.lower(cleaned)
    end

    value, found = GetODFString(odf, nil, "classLabel", "")
    cleaned = CleanString(value)
    if found and cleaned ~= "" then
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
    if not speedFound or not shotSpeed or shotSpeed <= 0 then
        shotSpeed, speedFound = GetODFFloat(odf, nil, "shotSpeed", 0.0)
    end
    if not speedFound or not shotSpeed or shotSpeed <= 0 then
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
            if found and cleaned ~= "" then
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

local function ResolveOrdnanceName(odf)
    if not odf or not GetODFString then return nil end
    local sections = { "WeaponClass", "OrdnanceClass", "GunClass", "RocketClass", "MissileClass", "MortarClass", nil }
    local labels = { "ordName", "ordnanceName", "shotClass", "projectileClass" }

    for _, section in ipairs(sections) do
        for _, label in ipairs(labels) do
            local value, found = GetODFString(odf, section, label, "")
            local cleaned = CleanString(value)
            if found and cleaned ~= "" then
                return cleaned
            end
        end
    end
    return nil
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
            range = ProbeRangeFromOdf(weaponOdf)
            if not range then
                local ordName = ResolveOrdnanceName(weaponOdf)
                if ordName then
                    local ordOdf = OpenODF(ordName)
                    if ordOdf then
                        range = ProbeRangeFromOdf(ordOdf)
                        if not range then
                            range = ProbeBallisticRangeFromOdf(ordOdf)
                        end
                        if not range then
                            range = ProbeTravelRangeFromOdf(ordOdf)
                        end
                    end
                end
            end
        end
    end

    PersistentConfig.WeaponRangeCache[key] = range
    return range
end

local function GetHudTargetInfo(player)
    if not IsValid(player) or type(GetUserTarget) ~= "function" then
        return nil, nil
    end

    local target = GetUserTarget()
    if not IsValid(target) or not IsAlive(target) then
        return nil, nil
    end

    if target == player then
        return nil, nil
    end

    if type(IsAlly) == "function" and IsAlly(player, target) then
        return nil, nil
    end

    local distance = GetDistance(player, target)
    if not distance or distance <= 0 then
        return nil, nil
    end

    return target, distance
end

local function BuildWeaponStatsText(player, mask)
    local lines = { "WPN" }
    local target, targetDistance = GetHudTargetInfo(player)
    if target and targetDistance then
        table.insert(lines, "TGT " .. tostring(math.floor(targetDistance + 0.5)) .. "m")
    end

    for slot = 0, 4 do
        if IsMaskBitSet(mask, slot) then
            local weapon = CleanString(GetWeaponClass(player, slot))
            if weapon ~= "" then
                local displayName = GetWeaponDisplayName(weapon)
                local range = GetWeaponRangeMeters(weapon)
                local rangeText = range and tostring(math.floor(range + 0.5)) .. "m" or "n/a"
                local status = "."
                if target and targetDistance then
                    if range then
                        status = (targetDistance <= range) and "+" or "-"
                    else
                        status = "?"
                    end
                end
                table.insert(lines, "S" .. tostring(slot + 1) .. " " .. status .. " " .. displayName .. " " .. rangeText)
            end
        end
    end

    if #lines <= 1 then
        return nil
    end
    return table.concat(lines, "\n")
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

    if mask <= 0 then
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
                    PersistentConfig.Settings.HeadlightSpecular.R = tonumber(val) or 8.0
                elseif key == "HeadlightSpecularG" then
                    PersistentConfig.Settings.HeadlightSpecular.G = tonumber(val) or 8.0
                elseif key == "HeadlightSpecularB" then
                    PersistentConfig.Settings.HeadlightSpecular.B = tonumber(val) or 8.0
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
                    PersistentConfig.Settings.AutoSaveInterval = tonumber(val) or 200
                elseif key == "AutoRepairBuildings" then
                    PersistentConfig.Settings.AutoRepairBuildings = (val == "true")
                elseif key == "RetroLighting" then
                    PersistentConfig.Settings.RetroLighting = (val == "true")
                elseif key == "WeaponStatsHud" then
                    PersistentConfig.Settings.WeaponStatsHud = (val == "true")
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
        f:Writeln("AutoSaveSlot=" .. tostring(PersistentConfig.Settings.AutoSaveSlot))
        f:Writeln("AutoSaveEnabled=" .. tostring(PersistentConfig.Settings.AutoSaveEnabled))
        f:Writeln("AutoSaveInterval=" .. tostring(PersistentConfig.Settings.AutoSaveInterval))
        f:Writeln("ScavengerAssistEnabled=" .. tostring(PersistentConfig.Settings.ScavengerAssistEnabled))
        f:Writeln("AutoRepairBuildings=" .. tostring(PersistentConfig.Settings.AutoRepairBuildings))
        f:Writeln("RetroLighting=" .. tostring(PersistentConfig.Settings.RetroLighting))
        f:Writeln("WeaponStatsHud=" .. tostring(PersistentConfig.Settings.WeaponStatsHud))

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

-- Show help overlay
function PersistentConfig.ShowHelp()
    -- Condensed Help Text
    local helpMsg = "KEYS: V:Headlight On/Off | Z:Color | J:AI-Lights\n" ..
        "B:Beam | X:Auto-Repair | Shift+X:Build-Repair | U:Scav-Assist | Ctrl+S:Weapon HUD | Shift+L:AutoSave | /:Help"

    ShowFeedback(helpMsg, 1.0, 1.0, 1.0, 8.0, false)
end

-- Reusable update logic for all missions
function PersistentConfig.UpdateInputs()
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

    UpdateWeaponStatsDisplay(currentPlayerHandle)

    -- Process Feedback Queue
    if #PersistentConfig.FeedbackQueue > 0 then
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

        if not isBusy or PersistentConfig.FeedbackQueue[1].bypass then
            local item = table.remove(PersistentConfig.FeedbackQueue, 1)
            if subtitles and subtitles.submit then
                subtitles.clear_queue()
                if subtitles.clear_current then subtitles.clear_current() end
                subtitles.set_opacity(0.5)
                subtitles.submit(item.msg, item.duration, item.r, item.g, item.b)
                if subtit then
                    subtit.LastEndTime = GetTime() + item.duration
                end
            end
        end
    end

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
        MarkOtherHeadlightsDirty()
    end
    InputState.last_j_state = j_key

    -- Toggle Headlight Beam Mode (B) - Removed Alt requirement, but check for Bail (Ctrl+B)
    local b_key = exu.GetGameKey("B")
    local ctrl_down = exu.GetGameKey("CTRL")
    local s_key = exu.GetGameKey("S")

    if b_key and not ctrl_down and not InputState.last_b_state then
        PersistentConfig.Settings.HeadlightBeamMode = (PersistentConfig.Settings.HeadlightBeamMode % 2) + 1
        PersistentConfig.SaveConfig()
        PersistentConfig.ApplySettings()
        local modeName = PersistentConfig.Settings.HeadlightBeamMode == 1 and "FOCUSED" or "WIDE"
        ShowFeedback("Beam: " .. modeName)
    end
    InputState.last_b_state = b_key

    if ctrl_down and s_key and not InputState.last_s_state then
        PersistentConfig.Settings.WeaponStatsHud = not PersistentConfig.Settings.WeaponStatsHud
        PersistentConfig.SaveConfig()
        InputState.lastWeaponMask = nil
        InputState.lastWeaponPlayer = nil
        InputState.lastWeaponText = nil
        InputState.lastWeaponTarget = nil
        InputState.nextWeaponHudCheck = 0.0
        if PersistentConfig.Settings.WeaponStatsHud then
            UpdateWeaponStatsDisplay(GetPlayerHandle())
        else
            ClearWeaponStats()
        end
        ShowFeedback("Weapon HUD: " .. (PersistentConfig.Settings.WeaponStatsHud and "ON" or "OFF"), 0.35, 0.65, 1.0, 2.5, false)
    end
    InputState.last_s_state = s_key

    -- Toggle Auto-Repair for Wingmen (X for "Auto-fiX")
    local x_key = exu.GetGameKey("X")
    local shift_down = false
    if exu.GetGameKey("SHIFT") then shift_down = true end

    if x_key and not InputState.last_x_state then
        if shift_down then
            -- Shift+X: Toggle Building Repair
            PersistentConfig.Settings.AutoRepairBuildings = not PersistentConfig.Settings.AutoRepairBuildings
            PersistentConfig.SaveConfig()
            ShowFeedback("Building Repair: " .. (PersistentConfig.Settings.AutoRepairBuildings and "ON" or "OFF"), 0.8,
                1.0, 0.8)
        else
            -- X: Toggle Wingman Repair
            PersistentConfig.Settings.AutoRepairWingmen = not PersistentConfig.Settings.AutoRepairWingmen
            PersistentConfig.SaveConfig()

            -- Apply to player team (team 1) immediately via aiCore
            if aiCore and aiCore.ActiveTeams and aiCore.ActiveTeams[1] then
                aiCore.ActiveTeams[1]:SetConfig("autoRepairWingmen", PersistentConfig.Settings.AutoRepairWingmen)
            end

            ShowFeedback("Wingman Auto-Repair: " .. (PersistentConfig.Settings.AutoRepairWingmen and "ON" or "OFF"), 0.8,
                1.0, 0.8)
        end
    end
    InputState.last_x_state = x_key

    -- Toggle Scavenger Assist (U)
    local u_key = exu.GetGameKey("U")
    if u_key and not InputState.last_u_state then
        PersistentConfig.Settings.ScavengerAssistEnabled = not PersistentConfig.Settings.ScavengerAssistEnabled
        PersistentConfig.SaveConfig()

        -- Apply to player team (team 1) immediately via aiCore
        if aiCore and aiCore.ActiveTeams and aiCore.ActiveTeams[1] then
            aiCore.ActiveTeams[1]:SetConfig("scavengerAssist", PersistentConfig.Settings.ScavengerAssistEnabled)
        end

        ShowFeedback("Scavenger Assist: " .. (PersistentConfig.Settings.ScavengerAssistEnabled and "ON" or "OFF"), 0.8,
            1.0, 0.8)
    end
    InputState.last_u_state = u_key

    -- Toggle AutoSave (Shift+L)
    local l_key = exu.GetGameKey("L")
    local shift_down_l = false
    if exu.GetGameKey("SHIFT") then shift_down_l = true end

    if l_key and shift_down_l and not InputState.last_l_state then
        PersistentConfig.Settings.AutoSaveEnabled = not PersistentConfig.Settings.AutoSaveEnabled
        PersistentConfig.SaveConfig()
        -- Propagate immediately to AutoSave module
        if autosave and autosave.Config then
            autosave.Config.enabled = PersistentConfig.Settings.AutoSaveEnabled
        end
        ShowFeedback("Auto-Save: " .. (PersistentConfig.Settings.AutoSaveEnabled and "ON" or "OFF"), 0.8, 1.0, 0.8)
    end
    InputState.last_l_state = l_key

    -- Help Popup (/ or ? key) - using stock BZ API
    local help_pressed = (LastGameKey == "/" or LastGameKey == "?")
    if help_pressed and not InputState.last_help_state then
        PersistentConfig.ShowHelp()
    end
    InputState.last_help_state = help_pressed

    -- Pause Menu Handling (Escape Key) - IMMEDIATE effect
    if exu.GetGameKey("ESCAPE") or LastGameKey == "ESCAPE" then
        InputState.SubtitlesPaused = true
    else
        if InputState.SubtitlesPaused then
            InputState.SubtitlesPaused = false
        end
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

local function GetPowerRadius(odfname)
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
    local playerTeam = 1
    local powerSources = {}
    local repairTargets = {}
    local healAmount = 20 -- 20 HP per second

    -- Collect power sources and damaged repair targets in one world pass.
    for h in AllObjects() do
        if GetTeamNum(h) == playerTeam and IsAlive(h) then
            local label = GetClassLabel(h)
            if label == "powerplant" then
                -- Store handle AND its specific radius
                local odf = GetOdf(h)
                local rad = GetPowerRadius(odf)
                table.insert(powerSources, { handle = h, radius = rad })
            elseif (IsBuilding(h) or label == "turret") and GetHealth(h) < 1.0 then
                repairTargets[#repairTargets + 1] = h
            end
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
    for h in AllObjects() do
        if ApplyOtherHeadlightVisibility(h, false, player) then
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

function PersistentConfig.OnObjectCreated(h)
    if not exu or not exu.SetHeadlightVisible then return end
    if not PersistentConfig.Settings.OtherHeadlightsDisabled then return end

    local player = GetPlayerHandle()
    ApplyOtherHeadlightVisibility(h, false, player)
end

function PersistentConfig.Initialize()
    PersistentConfig.LoadConfig()

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
