---@diagnostic disable: lowercase-global, undefined-global
local bzfile = require("bzfile")
local exu = require("exu")

local CareerStats = {
    FileName = "career_stats.cfg",
    SaveInterval = 5.0,
    PendingTimeout = 1.5,
    Data = {},
    PendingVictims = {},
    Dirty = false,
    Initialized = false,
    HookInstalled = false,
    Log = nil,
    RegisterHitCallback = nil,
    ResolveProfileKey = nil,
    Session = {
        profileKey = "offline",
        missionKey = "unknown_mission",
        lastSaveAt = 0.0,
        missionResultRecorded = false,
        lastPlayerHandle = nil,
        lastPlayerAlive = false,
        playerDeathRecorded = false,
    },
}

local function LogMessage(message)
    if type(CareerStats.Log) == "function" then
        CareerStats.Log(message)
    end
end

local function trim(value)
    value = tostring(value or "")
    value = value:gsub("%z.*", "")
    value = value:gsub("^%s+", "")
    value = value:gsub("%s+$", "")
    return value
end

local function cleanString(value)
    return trim(value)
end

local function sanitizeKey(value, fallback)
    local cleaned = string.lower(cleanString(value))
    cleaned = cleaned:gsub("[^%w%._%-]", "_")
    cleaned = cleaned:gsub("_+", "_")
    cleaned = cleaned:gsub("^_+", "")
    cleaned = cleaned:gsub("_+$", "")
    if cleaned == "" then
        return fallback or "unknown"
    end
    return cleaned
end

local function joinPath(lhs, rhs)
    lhs = trim(lhs)
    rhs = trim(rhs)
    if lhs == "" then
        return rhs
    end
    if rhs == "" then
        return lhs
    end
    if lhs:sub(-1) == "\\" or lhs:sub(-1) == "/" then
        return lhs .. rhs
    end
    return lhs .. "\\" .. rhs
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end

    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    return nil
end

local function getTimeNow()
    local now = safeCall(GetTime)
    return tonumber(now) or 0.0
end

local function isValidHandle(handle)
    if handle == nil or handle == 0 then
        return false
    end
    if type(IsValid) == "function" then
        return not not safeCall(IsValid, handle)
    end
    return true
end

local function isAliveHandle(handle)
    if not isValidHandle(handle) then
        return false
    end
    if type(IsAlive) == "function" then
        return not not safeCall(IsAlive, handle)
    end
    return true
end

local function getHandleNumber(handle)
    local number = tonumber(handle)
    if number ~= nil then
        return number
    end
    return handle
end

local function getCurrentHealth(handle)
    if not isValidHandle(handle) then
        return nil
    end

    local health = safeCall(GetCurHealth, handle)
    if health == nil then
        health = safeCall(GetHealth, handle)
    end
    return tonumber(health)
end

local function getPlayerHandleSafe()
    return safeCall(GetPlayerHandle)
end

local function getWhoShotMeSafe(handle)
    if not isValidHandle(handle) then
        return nil
    end
    return safeCall(GetWhoShotMe, handle)
end

local function getClassLabelSafe(handle)
    if not isValidHandle(handle) then
        return ""
    end
    return cleanString(safeCall(GetClassLabel, handle) or "")
end

local function getPilotClassSafe(handle)
    if not isValidHandle(handle) then
        return ""
    end
    return cleanString(safeCall(GetPilotClass, handle) or "")
end

local function getOdfSafe(handle)
    if not isValidHandle(handle) then
        return ""
    end
    return cleanString(safeCall(GetOdf, handle) or "")
end

local function resolveFilePath()
    local workingDirectory = safeCall(bzfile.GetWorkingDirectory) or "."
    return joinPath(workingDirectory, CareerStats.FileName)
end

local function fileExists(path)
    if path == nil or path == "" then
        return false
    end

    if bzfile and type(bzfile.Exists) == "function" then
        local ok, exists = pcall(bzfile.Exists, path)
        if ok then
            return not not exists
        end
    end

    if io and type(io.open) == "function" then
        local file = io.open(path, "rb")
        if file then
            file:close()
            return true
        end
    end

    return false
end

local function parseLine(line)
    local cleaned = trim(line)
    if cleaned == "" or cleaned:sub(1, 1) == "#" then
        return nil, nil
    end

    local split = cleaned:find("=", 1, true)
    if not split then
        return nil, nil
    end

    local key = trim(cleaned:sub(1, split - 1))
    local value = trim(cleaned:sub(split + 1))
    if key == "" then
        return nil, nil
    end

    return key, value
end

local function getKeyNumber(key)
    return tonumber(CareerStats.Data[key]) or 0
end

local function setKeyNumber(key, value)
    CareerStats.Data[key] = tostring(math.floor((tonumber(value) or 0) + 0.5))
    CareerStats.Dirty = true
end

local function incrementKey(key, amount)
    setKeyNumber(key, getKeyNumber(key) + (tonumber(amount) or 1))
end

local function getProfilePrefix()
    return "profile." .. CareerStats.Session.profileKey
end

local function getMissionPrefix()
    return getProfilePrefix() .. ".mission." .. CareerStats.Session.missionKey
end

local function incrementCareerField(field, amount)
    incrementKey(getProfilePrefix() .. ".career." .. field, amount)
end

local function incrementMissionField(field, amount)
    incrementKey(getMissionPrefix() .. "." .. field, amount)
end

local function getCareerField(field)
    return getKeyNumber(getProfilePrefix() .. ".career." .. field)
end

local function getMissionField(field)
    return getKeyNumber(getMissionPrefix() .. "." .. field)
end

local function classifyTargetType(classLabel)
    local lowered = string.lower(cleanString(classLabel))
    if lowered == "" then
        return "vehicle"
    end

    if lowered:find("person", 1, true) or
        lowered:find("pilot", 1, true) or
        lowered:find("sold", 1, true)
    then
        return "pilot"
    end

    if lowered:find("building", 1, true) or
        lowered:find("tower", 1, true) or
        lowered:find("turret", 1, true) or
        lowered:find("recycler", 1, true) or
        lowered:find("factory", 1, true) or
        lowered:find("armory", 1, true) or
        lowered:find("silo", 1, true)
    then
        return "building"
    end

    return "vehicle"
end

local function isSniperOrdnance(odfName)
    local lowered = string.lower(cleanString(odfName))
    return lowered:find("snip", 1, true) ~= nil
end

local function resolveMissionKey()
    local missionFilename = cleanString(safeCall(GetMissionFilename) or "")
    if missionFilename ~= "" then
        return sanitizeKey(missionFilename:gsub("%.bzn$", ""), "unknown_mission")
    end

    local trnFilename = cleanString(safeCall(GetMapTRNFilename) or "")
    if trnFilename ~= "" then
        return sanitizeKey(trnFilename:gsub("%.trn$", ""), "unknown_mission")
    end

    return "unknown_mission"
end

local function resolveProfileKey()
    local resolved = nil
    if type(CareerStats.ResolveProfileKey) == "function" then
        resolved = CareerStats.ResolveProfileKey()
    elseif exu and exu.GetSteam64 then
        resolved = safeCall(exu.GetSteam64)
    end

    resolved = cleanString(resolved or "")
    if resolved == "" or resolved == "0" then
        return "offline"
    end
    return sanitizeKey(resolved, "offline")
end

local function loadData()
    CareerStats.Data = {}

    local path = resolveFilePath()
    if not fileExists(path) then
        return
    end

    local file
    if io and type(io.open) == "function" then
        file = io.open(path, "r")
    else
        file = safeCall(bzfile.Open, path, "r")
    end

    if not file then
        return
    end

    local ok = pcall(function()
        if io and type(io.open) == "function" then
            for line in file:lines() do
                local key, value = parseLine(line)
                if key then
                    CareerStats.Data[key] = value
                end
            end
            file:close()
        else
            local line = file:Readln()
            while line do
                local key, value = parseLine(line)
                if key then
                    CareerStats.Data[key] = value
                end
                line = file:Readln()
            end
            file:Close()
        end
    end)

    if not ok then
        CareerStats.Data = {}
        LogMessage("CareerStats: failed to load career stats file, starting fresh.")
    end
end

local function saveData(force)
    local now = getTimeNow()
    if not CareerStats.Dirty and not force then
        return true
    end

    if not force and (now - (CareerStats.Session.lastSaveAt or 0.0)) < CareerStats.SaveInterval then
        return false
    end

    CareerStats.Data["meta.version"] = "1"

    local keys = {}
    for key in pairs(CareerStats.Data) do
        table.insert(keys, key)
    end
    table.sort(keys)

    local path = resolveFilePath()
    local file = safeCall(bzfile.Open, path, "w", "trunc")
    if not file then
        LogMessage("CareerStats: failed to open career stats file for writing: " .. tostring(path))
        return false
    end

    local ok = pcall(function()
        for _, key in ipairs(keys) do
            file:Writeln(tostring(key) .. "=" .. tostring(CareerStats.Data[key]))
        end
        if type(file.Flush) == "function" then
            file:Flush()
        end
        file:Close()
    end)

    if not ok then
        LogMessage("CareerStats: failed while writing career stats file: " .. tostring(path))
        return false
    end

    CareerStats.Dirty = false
    CareerStats.Session.lastSaveAt = now
    return true
end

local function recordMissionPlay()
    incrementCareerField("missionsPlayed", 1)
    incrementMissionField("plays", 1)
end

local function recordMissionResult(success)
    if CareerStats.Session.missionResultRecorded then
        return
    end

    CareerStats.Session.missionResultRecorded = true
    if success then
        incrementCareerField("missionsWon", 1)
        incrementMissionField("wins", 1)
    else
        incrementCareerField("missionsLost", 1)
        incrementMissionField("losses", 1)
    end
end

local function recordPlayerDeath()
    incrementCareerField("totalDeaths", 1)
    incrementCareerField("spDeaths", 1)
    incrementMissionField("deaths", 1)
end

local function recordKill(victim)
    incrementCareerField("totalKills", 1)
    incrementCareerField("spKills", 1)
    incrementMissionField("kills", 1)

    if victim.targetType == "pilot" then
        incrementCareerField("pilotKills", 1)
        incrementMissionField("pilotKills", 1)
    elseif victim.targetType == "building" then
        incrementCareerField("buildingKills", 1)
        incrementMissionField("buildingKills", 1)
    else
        incrementCareerField("vehicleKills", 1)
        incrementMissionField("vehicleKills", 1)
    end

    if victim.isSniper then
        incrementCareerField("sniperKills", 1)
        incrementMissionField("sniperKills", 1)
    end
end

local function recordSnipe(victim)
    incrementCareerField("snipes", 1)
    incrementMissionField("snipes", 1)
    if victim.isSniper then
        incrementCareerField("sniperKills", 1)
        incrementMissionField("sniperKills", 1)
    end
end

local function removePendingVictim(key)
    CareerStats.PendingVictims[key] = nil
end

local function updatePlayerDeathTracking()
    local player = getPlayerHandleSafe()
    if player ~= CareerStats.Session.lastPlayerHandle then
        CareerStats.Session.lastPlayerHandle = player
        CareerStats.Session.lastPlayerAlive = isAliveHandle(player) and ((getCurrentHealth(player) or 1) > 0)
        CareerStats.Session.playerDeathRecorded = false
        return
    end

    local alive = isAliveHandle(player) and ((getCurrentHealth(player) or 1) > 0)
    if CareerStats.Session.lastPlayerAlive and not alive and not CareerStats.Session.playerDeathRecorded then
        recordPlayerDeath()
        CareerStats.Session.playerDeathRecorded = true
    elseif alive then
        CareerStats.Session.playerDeathRecorded = false
    end

    CareerStats.Session.lastPlayerAlive = alive
end

local function updatePendingVictims()
    local now = getTimeNow()
    local player = getPlayerHandleSafe()

    for key, victim in pairs(CareerStats.PendingVictims) do
        local stillValid = isValidHandle(victim.handle)
        local alive = stillValid and isAliveHandle(victim.handle) or false
        local currentHealth = stillValid and getCurrentHealth(victim.handle) or nil
        local currentPilot = stillValid and getPilotClassSafe(victim.handle) or ""

        if stillValid and not victim.snipeRecorded and victim.pilotBefore ~= "" and victim.targetType ~= "pilot" then
            local whoShotMe = getWhoShotMeSafe(victim.handle)
            local pilotRemoved = currentPilot == ""
            local shooterConfirmed = (not isValidHandle(player)) or whoShotMe == nil or whoShotMe == player
            if alive and pilotRemoved and shooterConfirmed then
                recordSnipe(victim)
                victim.snipeRecorded = true
            end
        end

        local killed = (not stillValid) or (not alive) or (currentHealth ~= nil and currentHealth <= 0)
        if killed and not victim.killRecorded then
            recordKill(victim)
            removePendingVictim(key)
        elseif now > (victim.expiresAt or 0.0) then
            removePendingVictim(key)
        end
    end
end

local function handleBulletHit(odfName, shooter, hitObject, transform, ordnanceHandle)
    if not CareerStats.Initialized then
        return
    end

    local player = getPlayerHandleSafe()
    if not isValidHandle(player) or shooter ~= player or not isValidHandle(hitObject) then
        return
    end

    local now = getTimeNow()
    local key = tostring(getHandleNumber(hitObject))
    CareerStats.PendingVictims[key] = {
        handle = hitObject,
        hitAt = now,
        expiresAt = now + CareerStats.PendingTimeout,
        ordnanceOdf = cleanString(odfName or ""),
        targetType = classifyTargetType(getClassLabelSafe(hitObject)),
        targetOdf = getOdfSafe(hitObject),
        pilotBefore = getPilotClassSafe(hitObject),
        healthBefore = getCurrentHealth(hitObject),
        isSniper = isSniperOrdnance(odfName),
        killRecorded = false,
        snipeRecorded = false,
    }
end

local function installHook()
    if CareerStats.HookInstalled or not exu then
        return
    end

    if type(CareerStats.RegisterHitCallback) == "function" and CareerStats.RegisterHitCallback(handleBulletHit) then
        CareerStats.HookInstalled = true
        return
    end

    local oldBulletHit = exu.BulletHit
    exu.BulletHit = function(...)
        handleBulletHit(...)
        if oldBulletHit then
            return oldBulletHit(...)
        end
    end
    CareerStats.HookInstalled = true
end

function CareerStats.Initialize(config)
    config = config or {}
    CareerStats.Log = config.log
    CareerStats.RegisterHitCallback = config.registerHitCallback
    CareerStats.ResolveProfileKey = config.resolveProfileKey
    CareerStats.PendingVictims = {}
    CareerStats.Session.profileKey = resolveProfileKey()
    CareerStats.Session.missionKey = resolveMissionKey()
    CareerStats.Session.missionResultRecorded = false
    CareerStats.Session.lastPlayerHandle = nil
    CareerStats.Session.lastPlayerAlive = false
    CareerStats.Session.playerDeathRecorded = false

    loadData()
    recordMissionPlay()
    installHook()
    CareerStats.Initialized = true
    saveData(true)
end

function CareerStats.Update()
    if not CareerStats.Initialized then
        return
    end

    updatePlayerDeathTracking()
    updatePendingVictims()
    saveData(false)
end

function CareerStats.OnMissionEnd(success)
    if not CareerStats.Initialized then
        return
    end

    recordMissionResult(not not success)
    saveData(true)
end

function CareerStats.GetSummary()
    local summary = {
        initialized = CareerStats.Initialized and true or false,
        profileKey = CareerStats.Session.profileKey or "offline",
        missionKey = CareerStats.Session.missionKey or "unknown_mission",
        career = {
            totalKills = getCareerField("totalKills"),
            totalDeaths = getCareerField("totalDeaths"),
            spKills = getCareerField("spKills"),
            mpKills = getCareerField("mpKills"),
            spDeaths = getCareerField("spDeaths"),
            mpDeaths = getCareerField("mpDeaths"),
            pilotKills = getCareerField("pilotKills"),
            vehicleKills = getCareerField("vehicleKills"),
            buildingKills = getCareerField("buildingKills"),
            snipes = getCareerField("snipes"),
            sniperKills = getCareerField("sniperKills"),
            missionsPlayed = getCareerField("missionsPlayed"),
            missionsWon = getCareerField("missionsWon"),
            missionsLost = getCareerField("missionsLost"),
        },
        mission = {
            plays = getMissionField("plays"),
            wins = getMissionField("wins"),
            losses = getMissionField("losses"),
            kills = getMissionField("kills"),
            deaths = getMissionField("deaths"),
            pilotKills = getMissionField("pilotKills"),
            vehicleKills = getMissionField("vehicleKills"),
            buildingKills = getMissionField("buildingKills"),
            snipes = getMissionField("snipes"),
            sniperKills = getMissionField("sniperKills"),
        },
    }

    return summary
end

return CareerStats
