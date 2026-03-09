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
    PdaTextSizePreset = 2,          -- 1=Small 2=Medium 3=Large 4=Huge
    PdaWindowSizePreset = 2,        -- 1=Narrow 2=Normal 3=Wide 4=Ultra
    PdaColorPreset = 2,             -- 1=Dark Green 2=Green 3=Blue 4=White
}

local PdaPages = {
    STATS = 1,
    TARGET = 2,
    SETTINGS = 3,
    PRESETS = 4,
    COUNT = 4,
}

local PresetProducerKinds = {
    [1] = { name = "RECYCLER", getter = GetRecyclerHandle, short = "REC" },
    [2] = { name = "FACTORY", getter = GetFactoryHandle, short = "FAC" },
}

PersistentConfig.UnitPresets = {}

local PdaTextSizePresets = {
    [1] = { name = "SMALL", scale = 0.85 },
    [2] = { name = "MEDIUM", scale = 1.00 },
    [3] = { name = "LARGE", scale = 1.15 },
    [4] = { name = "HUGE", scale = 1.30 },
}

local PdaWindowSizePresets = {
    [1] = { name = "NARROW", width = 0.88 },
    [2] = { name = "NORMAL", width = 1.00 },
    [3] = { name = "WIDE", width = 1.16 },
    [4] = { name = "ULTRA", width = 1.30 },
}

local PdaColorPresets = {
    [1] = { name = "DARK GREEN", r = 0.10, g = 0.42, b = 0.10 },
    [2] = { name = "GREEN", r = 0.18, g = 0.92, b = 0.18 },
    [3] = { name = "BLUE", r = 0.35, g = 0.65, b = 1.00 },
    [4] = { name = "WHITE", r = 1.00, g = 1.00, b = 1.00 },
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

local function CycleIndex(value, count, delta, fallback)
    local index = ClampIndex(value, 1, count, fallback or 1)
    local step = math.floor(tonumber(delta) or 0)
    return ((index - 1 + step) % count) + 1
end

local function GetPdaTextSizePreset()
    return PdaTextSizePresets[ClampIndex(PersistentConfig.Settings.PdaTextSizePreset, 1, #PdaTextSizePresets, 2)]
end

local function GetPdaWindowSizePreset()
    return PdaWindowSizePresets[ClampIndex(PersistentConfig.Settings.PdaWindowSizePreset, 1, #PdaWindowSizePresets, 2)]
end

local function GetPdaColorPreset()
    return PdaColorPresets[ClampIndex(PersistentConfig.Settings.PdaColorPreset, 1, #PdaColorPresets, 2)]
end

local function BuildPdaHeader(activePage)
    local labels = {
        [PdaPages.STATS] = "STATS",
        [PdaPages.TARGET] = "TARGET",
        [PdaPages.SETTINGS] = "SETTINGS",
        [PdaPages.PRESETS] = "PRESETS",
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
    return table.concat(parts, "  ")
end

local function ShowWeaponStats(msg, duration)
    if subtitles and subtitles.set_channel_layout and subtitles.submit_to then
        local width, height = 1920, 1080
        local uiScale = 2
        local textPreset = GetPdaTextSizePreset()
        local windowPreset = GetPdaWindowSizePreset()
        local colorPreset = GetPdaColorPreset()
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
        local textScale = Clamp(0.30 * aspectScale * uiScaleFactor * textPreset.scale, 0.22, 0.52)
        local wrapWidth = Clamp(0.31 * Clamp(1.0 / aspectScale, 0.9, 1.2) * uiScaleFactor * windowPreset.width, 0.24, 0.56)
        local panelX = Clamp(0.02, 0.0, math.max(0.0, 1.0 - wrapWidth))
        local paddingX = 6.0 * textPreset.scale
        local paddingY = 5.0 * textPreset.scale

        -- Anchor the panel on the left-middle of the screen with left alignment.
        subtitles.set_channel_layout(WEAPON_STATS_CHANNEL, panelX, 0.50, 0.0, 0.5, textScale, wrapWidth, paddingX, paddingY,
            1.0)
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
    last_y_state = false,    -- Weapon HUD toggle (Y)
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
    pendingGameKeys = {},
    processedCreationHandles = {},
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
    local sections = { "WeaponClass", "OrdnanceClass", "CannonClass", "GunClass", "RocketClass", "MissileClass", "MortarClass", nil }
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

local function ProbeValueFromOdf(odf, labels, sections)
    if not odf or not GetODFFloat then return nil end
    sections = sections or { "WeaponClass", "OrdnanceClass", "CannonClass", "GunClass", "RocketClass", "MissileClass", "MortarClass", nil }
    for _, section in ipairs(sections) do
        for _, label in ipairs(labels) do
            local value, found = GetODFFloat(odf, section, label, 0.0)
            if found and value and value > 0 then
                return value
            end
        end
    end
    return nil
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
        if found and value and value > 0.0 then
            return true
        end
    end

    return false
end

local function ProbeDamageFromOdf(odf)
    if not odf or not GetODFFloat then return nil end
    local sections = { "WeaponClass", "OrdnanceClass", "CannonClass", "GunClass", "RocketClass", "MissileClass", "MortarClass", nil }
    local labels = { "damage", "damage1", "damage2", "damage3", "damage4", "damage5", "damage6", "damage7", "damage8" }

    for _, section in ipairs(sections) do
        local totalDamage = 0.0
        local foundAny = false
        for _, label in ipairs(labels) do
            local value, found = GetODFFloat(odf, section, label, 0.0)
            if found and value and value > 0 then
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
                if found and cleaned ~= "" and string.upper(cleaned) ~= "NULL" then
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
        damage = nil,
        dps = nil,
        shotDelay = nil,
        shotSpeed = nil,
        ballistic = false,
    }

    if OpenODF then
        local weaponOdf = OpenODF(weaponOdfName)
        local ordOdf = nil
        if weaponOdf then
            local ordName = ResolveOrdnanceName(weaponOdf)
            if ordName then
                ordOdf = OpenODF(ordName)
            end

            stats.shotDelay = ProbeValueFromOdf(weaponOdf, { "shotDelay", "reloadTime", "reloadDelay" })
            stats.damage = ProbeDamageFromOdf(weaponOdf)
            stats.shotSpeed = ProbeShotSpeedFromOdf(weaponOdf)
        end

        if ordOdf then
            if not stats.damage then
                stats.damage = ProbeDamageFromOdf(ordOdf)
            end
            if not stats.shotDelay then
                stats.shotDelay = ProbeValueFromOdf(ordOdf, { "shotDelay", "reloadTime", "reloadDelay" })
            end
            if not stats.shotSpeed then
                stats.shotSpeed = ProbeShotSpeedFromOdf(ordOdf)
            end
        end

        stats.ballistic = IsBallisticWeaponData(weaponOdf, ordOdf)
    end

    if stats.damage and stats.shotDelay and stats.shotDelay > 0.001 then
        stats.dps = stats.damage / stats.shotDelay
    end

    PersistentConfig.WeaponDataCache[key] = stats
    return stats
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
        if found and cleaned ~= "" then
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
            if unitNameFound and CleanString(unitName) ~= "" and string.upper(CleanString(unitName)) ~= "NULL" then
                displayName = CleanString(unitName)
            end

            local scrapCost, costFound = GetODFFloat(odf, "GameObjectClass", "scrapCost", 0.0)
            local slots = {}
            for slotIndex = 1, 5 do
                local hardpoint, hardpointFound = GetODFString(odf, "GameObjectClass", "weaponHard" .. tostring(slotIndex), "")
                local weaponName, _ = GetODFString(odf, "GameObjectClass", "weaponName" .. tostring(slotIndex), "")
                local cleanedHardpoint = CleanString(hardpoint)
                if hardpointFound and cleanedHardpoint ~= "" then
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
                scrapCost = (costFound and scrapCost) or 0.0,
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
            if found and cleanedWeapon ~= "" then
                local scrapCost, costFound = GetODFFloat(odf, "GameObjectClass", "scrapCost", 0.0)
                info = {
                    powerupOdf = powerupOdfName,
                    powerupKey = key,
                    weaponName = cleanedWeapon,
                    displayName = GetWeaponDisplayName(cleanedWeapon) or cleanedWeapon,
                    scrapCost = (costFound and scrapCost) or 0.0,
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
    for _, slotInfo in ipairs(entry.slots or {}) do
        local selectedPowerup = preset[slotInfo.slotIndex]
        if selectedPowerup and selectedPowerup ~= "" then
            local options = armoryOptions[slotInfo.category] and armoryOptions[slotInfo.category].options or {}
            local selectedOption = options[FindWeaponOptionIndex(options, selectedPowerup)]
            if selectedOption and selectedOption.weaponName and selectedOption.weaponName ~= "" then
                local extra = (selectedOption.scrapCost or 0.0) - GetStockWeaponUpgradeCost(slotInfo, options)
                if extra > 0.0 then
                    total = total + extra
                end
            end
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

local function AppendWeaponStatsLines(lines, h, installedMask, activeMask, compareTarget, comparePosition, compareDistance)
    local hardpointCount = 0
    local shooterPos = type(GetPosition) == "function" and GetPosition(h) or nil

    for slot = 0, 4 do
        if IsMaskBitSet(installedMask, slot) then
            local weapon = CleanString(GetWeaponClass(h, slot))
            if weapon ~= "" then
                hardpointCount = hardpointCount + 1
                local weaponStats = GetWeaponStats(weapon) or {}
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

                local rangeText = FormatWholeNumber(weaponStats.range)
                if weaponStats.ballistic and effectiveRange and weaponStats.range and
                    math.abs(effectiveRange - weaponStats.range) >= 5.0 then
                    rangeText = rangeText .. ">" .. FormatWholeNumber(effectiveRange)
                end

                table.insert(lines, string.format("S%d %s %s", slot + 1, status, weaponStats.displayName or weapon))
                table.insert(lines,
                    string.format("  RNG %sm  DMG %s  DPS %s", rangeText,
                        FormatWholeNumber(weaponStats.damage), FormatDps(weaponStats.dps)))
            end
        end
    end

    if hardpointCount == 0 then
        table.insert(lines, "NONE")
    end

    return hardpointCount
end

local function BuildStatsPageText(player, mask)
    local lines = { BuildPdaHeader(PdaPages.STATS) }
    local aimInfo = GetAimInfo(player, false)
    local target = aimInfo and aimInfo.handle or nil
    local targetDistance = aimInfo and aimInfo.distance or nil
    local aimPosition = aimInfo and aimInfo.position or nil
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
    if target and targetDistance then
        local label = (aimInfo and aimInfo.source == "target") and "TGT" or "AIM"
        table.insert(lines, label .. "  " .. GetVehicleDisplayName(target) .. "  " .. tostring(math.floor(targetDistance + 0.5)) .. "m")
        local closureRate, eta = GetTargetClosureInfo(player, target, targetDistance)
        local closureText = closureRate and tostring(math.floor(math.max(0.0, closureRate) + 0.5)) .. "m/s" or "--"
        local etaText = eta and string.format("%.1fs", eta) or "--"
        table.insert(lines, "CLS  " .. closureText .. "  ETA " .. etaText)
    elseif aimPosition and targetDistance then
        local playerPos = type(GetPosition) == "function" and GetPosition(player) or nil
        local deltaY = playerPos and ((aimPosition.y or 0.0) - (playerPos.y or 0.0)) or 0.0
        table.insert(lines, "AIM  GROUND  " .. tostring(math.floor(targetDistance + 0.5)) .. "m")
        table.insert(lines, "ELV  " .. tostring(math.floor(deltaY + (deltaY >= 0 and 0.5 or -0.5))) .. "m")
    end
    table.insert(lines, "HARDPOINTS")

    local hardpointCount = AppendWeaponStatsLines(lines, player, installedMask, mask, target, aimPosition, targetDistance)
    table.insert(lines, "TOTAL " .. tostring(hardpointCount))
    table.insert(lines, BuildMeterBar("AMMO", playerAmmo, curAmmo, maxAmmo))
    table.insert(lines, BuildMeterBar("HULL", playerHealth, curHealth, maxHealth))
    return table.concat(lines, "\n")
end

local function BuildTargetPageText(player)
    local lines = { BuildPdaHeader(PdaPages.TARGET) }
    local aimInfo = GetAimInfo(player, true)
    local target = aimInfo and aimInfo.handle or nil
    local targetDistance = aimInfo and aimInfo.distance or nil
    local aimPosition = aimInfo and aimInfo.position or nil

    if not aimInfo or not targetDistance then
        table.insert(lines, "NO TARGET")
        table.insert(lines, "Aim at a unit to inspect it.")
        table.insert(lines, "[ / ] SWITCH PAGE")
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
    table.insert(lines, "HARDPOINTS")

    local hardpointCount = AppendWeaponStatsLines(lines, target, installedMask, activeMask, player, nil, targetDistance)
    table.insert(lines, "TOTAL " .. tostring(hardpointCount))
    table.insert(lines, BuildMeterBar("AMMO", targetAmmo, curAmmo, maxAmmo))
    table.insert(lines, BuildMeterBar("HULL", targetHealth, curHealth, maxHealth))
    return table.concat(lines, "\n")
end

local function BuildSettingsPageText()
    local lines = { BuildPdaHeader(PdaPages.SETTINGS) }
    local selection = ClampIndex(InputState.pdaSettingsIndex, 1, 3, 1)
    local textPreset = GetPdaTextSizePreset()
    local windowPreset = GetPdaWindowSizePreset()
    local colorPreset = GetPdaColorPreset()

    local function AddSetting(index, label, value)
        local prefix = (selection == index) and ">" or " "
        table.insert(lines, string.format("%s %-11s %s", prefix, label, value))
    end

    AddSetting(1, "TEXT SIZE", textPreset.name)
    AddSetting(2, "WINDOW", windowPreset.name)
    AddSetting(3, "HUD COLOR", colorPreset.name)
    table.insert(lines, "")
    table.insert(lines, "UP/DOWN SELECT")
    table.insert(lines, "LEFT/RIGHT CHANGE")
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
        table.insert(lines, "[ / ] SWITCH PAGE")
        return table.concat(lines, "\n")
    end

    if #context.producerKinds == 0 then
        table.insert(lines, "NO PRODUCERS AVAILABLE")
        table.insert(lines, "Recycler/Factory missing.")
        table.insert(lines, "[ / ] SWITCH PAGE")
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

    table.insert(lines, "")
    table.insert(lines, "Preset applies after build.")
    table.insert(lines, "No refunds for downgrades.")
    table.insert(lines, "UP/DOWN SELECT  LEFT/RIGHT CHANGE")
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
    local page = ClampIndex(InputState.pdaPage, 1, PdaPages.COUNT, PdaPages.STATS)
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
                elseif key == "PdaTextSizePreset" then
                    PersistentConfig.Settings.PdaTextSizePreset = tonumber(val) or 2
                elseif key == "PdaWindowSizePreset" then
                    PersistentConfig.Settings.PdaWindowSizePreset = tonumber(val) or 2
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

    -- Sync ranges based on mode
    local mode = PersistentConfig.Settings.HeadlightBeamMode
    if BeamModes[mode] then
        PersistentConfig.Settings.HeadlightRange.InnerAngle = BeamModes[mode].Inner
        PersistentConfig.Settings.HeadlightRange.OuterAngle = BeamModes[mode].Outer
    end
    PersistentConfig.Settings.PdaTextSizePreset = ClampIndex(PersistentConfig.Settings.PdaTextSizePreset, 1, #PdaTextSizePresets, 2)
    PersistentConfig.Settings.PdaWindowSizePreset = ClampIndex(PersistentConfig.Settings.PdaWindowSizePreset, 1,
        #PdaWindowSizePresets, 2)
    PersistentConfig.Settings.PdaColorPreset = ClampIndex(PersistentConfig.Settings.PdaColorPreset, 1, #PdaColorPresets, 2)
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
        f:Writeln("PdaTextSizePreset=" .. tostring(PersistentConfig.Settings.PdaTextSizePreset))
        f:Writeln("PdaWindowSizePreset=" .. tostring(PersistentConfig.Settings.PdaWindowSizePreset))
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
        "B:Beam | X:Auto-Repair | Shift+X:Build-Repair | U:Scav-Assist | Y:Weapon HUD | Shift+L:AutoSave\n" ..
        "[:Prev Page | ]:Next Page | Settings/Presets: Arrows Edit | /:Help"

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
    local y_key = exu.GetGameKey("Y")

    if b_key and not ctrl_down and not InputState.last_b_state then
        PersistentConfig.Settings.HeadlightBeamMode = (PersistentConfig.Settings.HeadlightBeamMode % 2) + 1
        PersistentConfig.SaveConfig()
        PersistentConfig.ApplySettings()
        local modeName = PersistentConfig.Settings.HeadlightBeamMode == 1 and "FOCUSED" or "WIDE"
        ShowFeedback("Beam: " .. modeName)
    end
    InputState.last_b_state = b_key

    if y_key and not ctrl_down and not InputState.last_y_state then
        PersistentConfig.Settings.WeaponStatsHud = not PersistentConfig.Settings.WeaponStatsHud
        PersistentConfig.SaveConfig()
        RefreshWeaponHud()
        if PersistentConfig.Settings.WeaponStatsHud then
            UpdateWeaponStatsDisplay(GetPlayerHandle())
        else
            ClearWeaponStats()
        end
        ShowFeedback("Weapon HUD: " .. (PersistentConfig.Settings.WeaponStatsHud and "ON" or "OFF"), 0.35, 0.65, 1.0, 2.5, false)
    end
    InputState.last_y_state = y_key

    local left_bracket_pressed = ConsumePendingGameKeyMatch({ "[", "{", "SHIFT+[", "OEM_4", "LBRACKET", "LEFTBRACKET" })
    local right_bracket_pressed = ConsumePendingGameKeyMatch({ "]", "}", "SHIFT+]", "OEM_6", "RBRACKET", "RIGHTBRACKET" })

    if left_bracket_pressed then
        InputState.pdaPage = CycleIndex(InputState.pdaPage, PdaPages.COUNT, -1, PdaPages.STATS)
        PlayPdaSound("mnu_back.wav")
        RefreshWeaponHud()
        if PersistentConfig.Settings.WeaponStatsHud then
            UpdateWeaponStatsDisplay(GetPlayerHandle())
        end
    end
    if right_bracket_pressed then
        InputState.pdaPage = CycleIndex(InputState.pdaPage, PdaPages.COUNT, 1, PdaPages.STATS)
        PlayPdaSound("mnu_next.wav")
        RefreshWeaponHud()
        if PersistentConfig.Settings.WeaponStatsHud then
            UpdateWeaponStatsDisplay(GetPlayerHandle())
        end
    end
    local pda_up_key = ConsumePendingGameKeyMatch({ "UP", "UPARROW" })
    local pda_down_key = ConsumePendingGameKeyMatch({ "DOWN", "DOWNARROW" })
    local pda_left_key = ConsumePendingGameKeyMatch({ "LEFT", "LEFTARROW" })
    local pda_right_key = ConsumePendingGameKeyMatch({ "RIGHT", "RIGHTARROW" })

    if InputState.pdaPage == PdaPages.SETTINGS then
        if pda_up_key then
            InputState.pdaSettingsIndex = CycleIndex(InputState.pdaSettingsIndex, 3, -1, 1)
            PlayPdaSound("mnu_clik.wav")
            RefreshWeaponHud()
            if PersistentConfig.Settings.WeaponStatsHud then
                UpdateWeaponStatsDisplay(GetPlayerHandle())
            end
        elseif pda_down_key then
            InputState.pdaSettingsIndex = CycleIndex(InputState.pdaSettingsIndex, 3, 1, 1)
            PlayPdaSound("mnu_clik.wav")
            RefreshWeaponHud()
            if PersistentConfig.Settings.WeaponStatsHud then
                UpdateWeaponStatsDisplay(GetPlayerHandle())
            end
        end

        local sizeChanged = false
        local selection = ClampIndex(InputState.pdaSettingsIndex, 1, 3, 1)
        if pda_left_key then
            if selection == 1 then
                PersistentConfig.Settings.PdaTextSizePreset = CycleIndex(PersistentConfig.Settings.PdaTextSizePreset,
                    #PdaTextSizePresets, -1, 2)
            elseif selection == 2 then
                PersistentConfig.Settings.PdaWindowSizePreset = CycleIndex(PersistentConfig.Settings.PdaWindowSizePreset,
                    #PdaWindowSizePresets, -1, 2)
            else
                PersistentConfig.Settings.PdaColorPreset = CycleIndex(PersistentConfig.Settings.PdaColorPreset,
                    #PdaColorPresets, -1, 2)
            end
            sizeChanged = true
        elseif pda_right_key then
            if selection == 1 then
                PersistentConfig.Settings.PdaTextSizePreset = CycleIndex(PersistentConfig.Settings.PdaTextSizePreset,
                    #PdaTextSizePresets, 1, 2)
            elseif selection == 2 then
                PersistentConfig.Settings.PdaWindowSizePreset = CycleIndex(PersistentConfig.Settings.PdaWindowSizePreset,
                    #PdaWindowSizePresets, 1, 2)
            else
                PersistentConfig.Settings.PdaColorPreset = CycleIndex(PersistentConfig.Settings.PdaColorPreset,
                    #PdaColorPresets, 1, 2)
            end
            sizeChanged = true
        end

        if sizeChanged then
            PlayPdaSound("mnu_enab.wav")
            PersistentConfig.SaveConfig()
            RefreshWeaponHud()
            if PersistentConfig.Settings.WeaponStatsHud then
                UpdateWeaponStatsDisplay(GetPlayerHandle())
            end
        end
    elseif InputState.pdaPage == PdaPages.PRESETS then
        local context = GetPresetPageContext()
        local rowCount = math.max(#(context.rows or {}), 1)

        if pda_up_key then
            InputState.presetRow = CycleIndex(InputState.presetRow, rowCount, -1, 1)
            PlayPdaSound("mnu_clik.wav")
            RefreshWeaponHud()
            if PersistentConfig.Settings.WeaponStatsHud then
                UpdateWeaponStatsDisplay(GetPlayerHandle())
            end
        elseif pda_down_key then
            InputState.presetRow = CycleIndex(InputState.presetRow, rowCount, 1, 1)
            PlayPdaSound("mnu_clik.wav")
            RefreshWeaponHud()
            if PersistentConfig.Settings.WeaponStatsHud then
                UpdateWeaponStatsDisplay(GetPlayerHandle())
            end
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
            PersistentConfig.SaveConfig()
            RefreshWeaponHud()
            if PersistentConfig.Settings.WeaponStatsHud then
                UpdateWeaponStatsDisplay(GetPlayerHandle())
            end
        end
    end

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

    local surcharge = math.floor(GetPresetSurchargeForEntry(entry) + 0.5)
    if surcharge > 0 and type(GetScrap) == "function" and GetScrap(team) < surcharge then
        ShowFeedback("Preset skipped: need +" .. tostring(surcharge) .. " scrap", 1.0, 0.35, 0.35, 2.5, false)
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

    if applied and surcharge > 0 and type(AddScrap) == "function" then
        AddScrap(team, -surcharge)
    end
    if applied then
        ShowFeedback("Preset applied: " .. (entry.displayName or odfName) .. " +" .. tostring(surcharge) .. " scrap",
            0.35, 1.0, 0.35, 2.5, false)
    end
    return applied
end

function PersistentConfig.OnObjectCreated(h)
    if InputState.processedCreationHandles[h] then
        return
    end
    InputState.processedCreationHandles[h] = true

    if exu and exu.SetHeadlightVisible and PersistentConfig.Settings.OtherHeadlightsDisabled then
        local player = GetPlayerHandle()
        ApplyOtherHeadlightVisibility(h, false, player)
    end

    ApplyUnitPresetToObject(h)
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
