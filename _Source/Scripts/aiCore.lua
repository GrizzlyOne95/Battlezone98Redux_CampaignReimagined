-- aiCore.lua
---@diagnostic disable: lowercase-global
-- Consolidated AI System for Battlezone 98 Redux
-- Combines functionality from pilotMode, autorepair, aiFacProd, aiRecProd, aiBuildOS, and aiSpecial
-- Supported Factions: NSDF, CCA, CRA, BDOG

local DiffUtils = require("DiffUtils")

-- Polyfills

function AllBuildings()
    local t = (aiCore and aiCore.GetCachedBuildings and aiCore.GetCachedBuildings()) or {}
    local i = 0
    return function()
        i = i + 1; return t[i]
    end
end

---@diagnostic disable-next-line: undefined-global
local bit = bit
if not bit then
    -- Minimal bitwise operations for float parsing (if native bit lib missing)
    bit = {}
    function bit.band(a, b)
        local r = 0
        local p = 1
        for i = 1, 32 do
            local ra, rb = a % 2, b % 2
            if ra == 1 and rb == 1 then r = r + p end
            a, b, p = (a - ra) / 2, (b - rb) / 2, p * 2
        end
        return r
    end

    function bit.lshift(a, b) return math.floor(a * (2 ^ b)) end

    function bit.rshift(a, b) return math.floor(a / (2 ^ b)) end
end

----------------------------------------------------------------------------------
-- INTEGRATED UTILITY
----------------------------------------------------------------------------------
local utility = {}
utility.ClassLabel = {
    HOWITZER = "howitzer",
    APC = "apc",
    MINELAYER = "minelayer",
    TURRET = "turret",          -- Stationary (Gun Towers)
    TURRET_TANK = "turrettank", -- Mobile
    SCAVENGER = "scavenger",
    TUG = "tug",
    WINGMAN = "wingman",
    WALKER = "walker",
    PERSON = "person",
    SCRAP = "scrap",
    BUILDING = "i76building",
    RECYCLER = "recycler",
    FACTORY = "factory",
    ARMORY = "armory",
    CONSTRUCTOR = "constructionrig",
    BARRACKS = "barracks",
    POWERPLANT = "powerplant",
    SUPPLY_DEPOT = "supplydepot",
    REPAIR_DEPOT = "repairdepot",
    BUILDING_RADAR_SAFE = "i76building2", -- Prop buildings that don't ping on radar
    SPECIAL_ITEM = "specialitem",         -- Dummy special weapon for scripting
    POWERUP_GENERIC = "powerup",          -- Generic powerup (no pickup/reject sounds)
    DROPOFF = "dropoff",                  -- Inert powerup useful for scripting
    SIGN = "i76sign",                     -- Small building/prop type (pylons)
    CAMERA_POD = "camerapod",
    SPRAYBOMB = "spraybomb",              -- Deployed splinter mortar
    SCRAP_SILO = "scrapsilo"
}

-- Clean strings of null padding (Engine Bug Fix)
function utility.CleanString(s)
    if not s then return "" end
    local s2 = string.gsub(s, "%z", "")
    return s2
end

---@diagnostic disable-next-line: undefined-global
local exu = exu

-- Gets the mass of the given object (most ships default to 1750 KG)
function GetMass(h)
    if exu and exu.getmass then
        return exu.getmass(h)
    end
    return 1750
end

-- Sets the mass of the given object. This affects collisions and knockback.
function SetMass(h, m)
    if exu and exu.setmass then
        exu.setmass(h, m)
    end
end

-- Evaluate whether a given target can be sniped
function utility.CanSnipe(h)
    if not IsValid(h) then return false end
    local cls = string.lower(utility.CleanString(GetClassLabel(h)))
    if IsCraft(h) and
        not string.find(cls, "walker") and
        not string.find(cls, "recycler") and
        not string.find(cls, "factory") and
        not string.find(cls, "armory") and
        not string.find(cls, "constructionrig") and
        not string.find(cls, "turret") and
        not (string.find(cls, "turrettank") and IsDeployed(h)) and
        not string.find(string.lower(GetOdf(h)), "hvsat") and
        not string.find(cls, "sav") then
        return true
    end
    return false
end

local function FireWeaponMask(h, mask)
    SetWeaponMask(h, mask)
end

-- ScriptUtils command priority values:
-- 0 = commandable, 1 = uncommandable
local COMMAND_PRIORITY_COMMANDABLE = 0
local COMMAND_PRIORITY_UNCOMMANDABLE = 1

local function GetCommandableAttackPriority()
    return COMMAND_PRIORITY_COMMANDABLE
end

local function GetUncommandablePriority()
    return COMMAND_PRIORITY_UNCOMMANDABLE
end

local function NormalizeScriptPriority(h, priority)
    if not IsValid(h) then return priority end
    if GetTeamNum(h) == 1 then
        return COMMAND_PRIORITY_COMMANDABLE
    end
    if priority == nil then
        return COMMAND_PRIORITY_UNCOMMANDABLE
    end
    return priority
end

local function GetDefaultWeaponMask(h)
    local w0 = utility and utility.CleanString(GetWeaponClass(h, 0)) or ""
    local w1 = utility and utility.CleanString(GetWeaponClass(h, 1)) or ""
    local w2 = utility and utility.CleanString(GetWeaponClass(h, 2)) or ""
    local w3 = utility and utility.CleanString(GetWeaponClass(h, 3)) or ""

    if w0 ~= "" and w0 == w3 then return 15 end
    if w0 ~= "" and w0 == w2 then return 7 end
    if w0 ~= "" and w0 == w1 then return 3 end
    if w1 ~= "" and w1 == w2 then return 6 end

    -- Fallback to the first non-empty hardpoint.
    for i = 0, 4 do
        local w = utility and utility.CleanString(GetWeaponClass(h, i)) or ""
        if w ~= "" then
            return 2 ^ i
        end
    end
    return 1
end

local WeaponRangeCache = {}
local MissileWeaponProfileCache = {}
local WeaponHardpointCache = {}

local function GetWeaponHardpointCode(h, slot)
    if not IsValid(h) or type(slot) ~= "number" then return nil end

    local odfName = string.lower(utility.CleanString(GetOdf(h)))
    if odfName == "" then return nil end

    local cache = WeaponHardpointCache[odfName]
    if not cache then
        cache = {}
        if OpenODF and GetODFString then
            local odf = OpenODF(odfName)
            if odf then
                for i = 0, 4 do
                    local value, found = GetODFString(odf, "GameObjectClass", "weaponHard" .. tostring(i + 1), "")
                    local cleaned = utility.CleanString(value)
                    if (type(found) == "boolean" and found and cleaned ~= "") or (type(found) ~= "boolean" and cleaned ~= "") then
                        cache[i] = string.lower(cleaned)
                    end
                end
            end
        end
        WeaponHardpointCache[odfName] = cache
    end

    return cache[slot]
end

local function IsMaskBitSet(mask, slot)
    local div = 2 ^ slot
    return (math.floor(mask / div) % 2) >= 1
end

local function GetCurrentWeaponMaskValue(h)
    if not IsValid(h) then return 0 end

    if type(GetWeaponMask) == "function" then
        local ok, value = pcall(GetWeaponMask, h)
        if ok and type(value) == "number" then
            return math.max(0, math.floor(value + 0.5))
        end
    end

    local fallback = GetDefaultWeaponMask(h)
    if fallback and fallback > 0 then
        return fallback
    end
    return 0
end

local function HasOdfNumber(value, found)
    if type(found) == "boolean" then
        return found and type(value) == "number" and value > 0
    end
    return type(value) == "number" and value > 0
end

local function HasOdfString(value, found)
    local cleaned = utility.CleanString(value)
    if type(found) == "boolean" then
        return found and cleaned ~= ""
    end
    return cleaned ~= ""
end

local function IsIndependenceLocked(h)
    if not IsValid(h) then return false end
    if type(GetIndependence) ~= "function" then return false end
    local ok, value = pcall(GetIndependence, h)
    if ok and type(value) == "number" then
        return value <= 0
    end
    return false
end

local function RemoveMaskBits(mask, removeMask)
    local result = 0
    for slot = 0, 4 do
        local bit = 2 ^ slot
        if IsMaskBitSet(mask, slot) and not IsMaskBitSet(removeMask or 0, slot) then
            result = result + bit
        end
    end
    return result
end

local function MergeMaskBits(maskA, maskB)
    local result = maskA or 0
    for slot = 0, 4 do
        local bit = 2 ^ slot
        if IsMaskBitSet(maskB or 0, slot) and not IsMaskBitSet(result, slot) then
            result = result + bit
        end
    end
    return result
end

local function ProbeLifeSpanFromOdf(odf)
    if not odf or not GetODFFloat then return nil end

    local value, found = GetODFFloat(odf, "OrdnanceClass", "lifeSpan", 0.0)
    if HasOdfNumber(value, found) then
        return value
    end

    value, found = GetODFFloat(odf, nil, "lifeSpan", 0.0)
    if HasOdfNumber(value, found) then
        return value
    end

    return nil
end

local function ProbeDamageFromOdf(odf)
    if not odf or not GetODFFloat then return nil end

    local genericDamage, genericFound = GetODFFloat(odf, "OrdnanceClass", "damage", 0.0)
    if not HasOdfNumber(genericDamage, genericFound) then
        genericDamage, genericFound = GetODFFloat(odf, nil, "damage", 0.0)
    end

    local typedDamage = 0.0
    local typedLabels = {
        "damageBallistic",
        "damageConcussion",
        "damageFlame",
        "damageImpact",
        "damageArea",
        "damageEM",
        "damageThermal",
        "damageExplosive",
        "damageShields",
    }

    for _, label in ipairs(typedLabels) do
        local value, found = GetODFFloat(odf, "OrdnanceClass", label, 0.0)
        if not HasOdfNumber(value, found) then
            value, found = GetODFFloat(odf, nil, label, 0.0)
        end
        if HasOdfNumber(value, found) then
            typedDamage = typedDamage + value
        end
    end

    if typedDamage > 0.0 then
        return typedDamage
    end
    if HasOdfNumber(genericDamage, genericFound) then
        return genericDamage
    end

    local stagedDamage = 0.0
    for i = 1, 8 do
        local label = "damage" .. i
        local value, found = GetODFFloat(odf, "OrdnanceClass", label, 0.0)
        if not HasOdfNumber(value, found) then
            value, found = GetODFFloat(odf, nil, label, 0.0)
        end
        if HasOdfNumber(value, found) then
            stagedDamage = stagedDamage + value
        end
    end

    if stagedDamage > 0.0 then
        return stagedDamage
    end
    return nil
end

local function ProbeSalvoCountFromOdf(odf)
    if not odf or not GetODFFloat then return 1.0 end

    local sections = { "WeaponClass", "LauncherClass", "RocketClass", "MissileClass", nil }
    local labels = { "salvoCount", "shotCount", "burstCount" }
    local best = 1.0

    for _, section in ipairs(sections) do
        for _, label in ipairs(labels) do
            local value, found = GetODFFloat(odf, section, label, 0.0)
            if HasOdfNumber(value, found) and value > best then
                best = value
            end
        end
    end

    return math.max(1.0, best)
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
        if HasOdfNumber(value, found) and (not best or value > best) then
            best = value
        end
    end
    return best
end

local function ProbeTravelRangeFromOdf(odf)
    if not odf or not GetODFFloat then return nil end

    local lifeSpan, lifeFound = GetODFFloat(odf, "OrdnanceClass", "lifeSpan", 0.0)
    if not HasOdfNumber(lifeSpan, lifeFound) then
        lifeSpan, lifeFound = GetODFFloat(odf, nil, "lifeSpan", 0.0)
    end

    local shotSpeed, speedFound = GetODFFloat(odf, "OrdnanceClass", "shotSpeed", 0.0)
    if not HasOdfNumber(shotSpeed, speedFound) then
        shotSpeed, speedFound = GetODFFloat(odf, nil, "shotSpeed", 0.0)
    end

    if HasOdfNumber(lifeSpan, lifeFound) and HasOdfNumber(shotSpeed, speedFound) then
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
    local cleaned = utility.CleanString(value)
    if HasOdfString(cleaned, found) then
        return string.lower(cleaned)
    end

    value, found = GetODFString(odf, "WeaponClass", "classLabel", "")
    cleaned = utility.CleanString(value)
    if HasOdfString(cleaned, found) then
        return string.lower(cleaned)
    end

    value, found = GetODFString(odf, nil, "classLabel", "")
    cleaned = utility.CleanString(value)
    if HasOdfString(cleaned, found) then
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
    if not HasOdfNumber(shotSpeed, speedFound) then
        shotSpeed, speedFound = GetODFFloat(odf, nil, "shotSpeed", 0.0)
    end
    if not HasOdfNumber(shotSpeed, speedFound) then
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

local function ResolveOrdnanceName(odf)
    if not odf or not GetODFString then return nil end
    local sections = { "WeaponClass", "OrdnanceClass", "CannonClass", "GunClass", "RocketClass", "MissileClass", "MortarClass", nil }
    local labels = { "ordName", "ordnanceName", "shotClass", "projectileClass" }

    for _, section in ipairs(sections) do
        for _, label in ipairs(labels) do
            local value, found = GetODFString(odf, section, label, "")
            local cleaned = utility.CleanString(value)
            if HasOdfString(cleaned, found) then
                return cleaned
            end
        end
    end
    return nil
end

local function GetMissileWeaponProfile(odfName)
    local cleanedName = string.lower(utility.CleanString(odfName))
    if cleanedName == "" then return nil end

    local cached = MissileWeaponProfileCache[cleanedName]
    if cached ~= nil then
        return cached or nil
    end

    local profile = nil
    if OpenODF then
        local baseOdf = OpenODF(cleanedName)
        if baseOdf then
            local ordName = ResolveOrdnanceName(baseOdf)
            local ordOdf = nil
            if ordName and ordName ~= "" then
                ordOdf = OpenODF(ordName)
            else
                ordName = cleanedName
                ordOdf = baseOdf
            end

            if ordOdf then
                local damage = ProbeDamageFromOdf(ordOdf)
                local lifeSpan = ProbeLifeSpanFromOdf(ordOdf)
                local salvoCount = ProbeSalvoCountFromOdf(baseOdf)
                if damage and damage > 0.0 then
                    profile = {
                        weaponOdf = cleanedName,
                        ordName = string.lower(utility.CleanString(ordName)),
                        damage = damage * salvoCount,
                        damagePerProjectile = damage,
                        lifeSpan = lifeSpan or 10.0,
                        salvoCount = salvoCount,
                    }
                end
            end
        end
    end

    MissileWeaponProfileCache[cleanedName] = profile or false
    return profile
end

local function GetUnitCurrentHealthPoints(h)
    if not IsValid(h) then return nil end

    local maxHealth = GetMaxHealth(h)
    local curHealth = GetCurHealth(h)
    if type(curHealth) == "number" and curHealth > 0.0 then
        return curHealth
    end

    if type(maxHealth) == "number" and maxHealth > 0.0 then
        local normalized = GetHealth(h)
        if type(normalized) == "number" and normalized > 0.0 and normalized <= 2.0 then
            return maxHealth * normalized
        end
        return maxHealth
    end

    return nil
end

local function GetWeaponRangeMeters(weaponOdfName)
    if not weaponOdfName or weaponOdfName == "" then return nil end
    local key = string.lower(weaponOdfName)
    if WeaponRangeCache[key] ~= nil then
        return WeaponRangeCache[key]
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

    WeaponRangeCache[key] = range
    return range
end

local function GetCurrentWeaponRangeMeters(h)
    if not IsValid(h) then return nil end

    local mask = GetCurrentWeaponMaskValue(h)
    if mask <= 0 then
        mask = GetDefaultWeaponMask(h)
    end

    local bestRange = nil
    for slot = 0, 4 do
        if IsMaskBitSet(mask, slot) then
            local weapon = utility.CleanString(GetWeaponClass(h, slot))
            if weapon ~= "" then
                local range = GetWeaponRangeMeters(weapon)
                if range and range > 0 and (not bestRange or range > bestRange) then
                    bestRange = range
                end
            end
        end
    end

    if bestRange then
        return bestRange
    end

    for slot = 0, 4 do
        local weapon = utility.CleanString(GetWeaponClass(h, slot))
        if weapon ~= "" then
            local range = GetWeaponRangeMeters(weapon)
            if range and range > 0 and (not bestRange or range > bestRange) then
                bestRange = range
            end
        end
    end

    return bestRange
end

-- Math / Vector Utils

function Normalize(v)
    local len = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if len == 0 then return SetVector(0, 0, 0) end
    return SetVector(v.x / len, v.y / len, v.z / len)
end

local function DotProduct(a, b)
    return (a.x * b.x) + (a.y * b.y) + (a.z * b.z)
end

local function MatrixToPosition(m)
    if not m then return nil end
    return SetVector(m.posit_x, m.posit_y, m.posit_z)
end

local function DeepCopyValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = DeepCopyValue(v)
    end
    return copy
end

local function UniqueInsert(list, value)
    if not list then return false end
    for _, existing in ipairs(list) do
        if existing == value then
            return false
        end
    end
    table.insert(list, value)
    return true
end

aiCore = {}
function aiCore.GetDistance(h1, h2)
    if not IsValid(h1) or not IsValid(h2) then return 999999 end
    return GetDistance(h1, h2)
end

function aiCore.SafeGetTeamSlot(slot, teamNum)
    if not GetTeamSlot then return nil end
    local ok, h = pcall(GetTeamSlot, slot, teamNum)
    if ok and IsValid(h) then
        return h
    end
    return nil
end

-- Polyfill for GetTerrainHeight if missing
function GetTerrainHeight(x, z)
    local h, n = GetTerrainHeightAndNormal(SetVector(x, 0, z))
    return h
end

aiCore.OdfMetaCache = aiCore.OdfMetaCache or {}

function aiCore.GetOdfMeta(odfName)
    local cleanOdf = string.lower(utility.CleanString(odfName or ""))
    if cleanOdf == "" then
        return nil
    end

    local cached = aiCore.OdfMetaCache[cleanOdf]
    if cached then
        return cached
    end

    local meta = {
        odf = cleanOdf,
        classLabel = "",
        unitName = "",
        pilotCost = 0,
        weaponNames = {},
        personRole = nil
    }

    local odf = OpenODF(cleanOdf)
    if odf then
        meta.classLabel = string.lower(utility.CleanString(GetODFString(odf, "GameObjectClass", "classLabel", "")))
        meta.unitName = string.lower(utility.CleanString(GetODFString(odf, "GameObjectClass", "unitName", "")))
        local pilotCost = GetODFInt(odf, "GameObjectClass", "pilotCost", 0)
        meta.pilotCost = tonumber(pilotCost) or 0

        for i = 1, 5 do
            local weaponName = string.lower(utility.CleanString(GetODFString(odf, "GameObjectClass", "weaponName" .. i, "")))
            if weaponName ~= "" then
                table.insert(meta.weaponNames, weaponName)
            end
        end

        if meta.classLabel == utility.ClassLabel.PERSON then
            local hasSniper = false
            local hasSoldierWeapon = false
            for _, weaponName in ipairs(meta.weaponNames) do
                if string.find(weaponName, "snipe") then
                    hasSniper = true
                end
                if string.find(weaponName, "minig")
                    or string.find(weaponName, "stab")
                    or string.find(weaponName, "mortar")
                    or string.find(weaponName, "rkt")
                    or string.find(weaponName, "bomb") then
                    hasSoldierWeapon = true
                end
            end

            if meta.pilotCost <= 0 or hasSoldierWeapon then
                meta.personRole = "soldier"
            elseif hasSniper or string.find(meta.unitName, "player") then
                meta.personRole = "sniper"
            else
                meta.personRole = "pilot"
            end
        end
    end

    aiCore.OdfMetaCache[cleanOdf] = meta
    return meta
end

utility.ClassId = {
    NONE = 0,

    HELICOPTER = 1,
    STRUCTURE1 = 2, -- Wooden Structures
    POWERUP = 3,
    PERSON = 4,
    SIGN = 5,
    VEHICLE = 6,
    SCRAP = 7,
    BRIDGE = 8,      -- A structure which can contain the floor
    FLOOR = 9,       -- The floor in a bridge
    STRUCTURE2 = 10, -- Metal Structures
    SCROUNGE = 11,
    SPINNER = 15,

    HEADLIGHT_MASK = 38,

    EYEPOINT = 40,
    COM = 42,

    WEAPON = 50,
    ORDNANCE = 51,
    EXPLOSION = 52,
    CHUNK = 53,
    SORT_OBJECT = 54,
    NONCOLLIDABLE = 55,

    VEHICLE_GEOMETRY = 60,
    STRUCTURE_GEOMETRY = 61,
    WEAPON_GEOMETRY = 63,
    ORDNANCE_GEOMETRY = 64,
    TURRET_GEOMETRY = 65,
    ROTOR_GEOMETRY = 66,
    NACELLE_GEOMETRY = 67,
    FIN_GEOMETRY = 68,
    COCKPIT_GEOMETRY = 69,

    WEAPON_HARDPOINT = 70,
    CANNON_HARDPOINT = 71,
    ROCKET_HARDPOINT = 72,
    MORTAR_HARDPOINT = 73,
    SPECIAL_HARDPOINT = 74,

    FLAME_EMITTER = 75,
    SMOKE_EMITTER = 76,
    DUST_EMITTER = 77,

    PARKING_LOT = 81,

    [0] = "NONE",
    [1] = "HELICOPTER",
    [2] = "STRUCTURE1", -- Wooden Structures
    [3] = "POWERUP",
    [4] = "PERSON",
    [5] = "SIGN",
    [6] = "VEHICLE",
    [7] = "SCRAP",
    [8] = "BRIDGE",      -- A structure which can contain the floor
    [9] = "FLOOR",       -- The floor in a bridge
    [10] = "STRUCTURE2", -- Metal Structures
    [11] = "SCROUNGE",
    [15] = "SPINNER",
    [38] = "HEADLIGHT_MASK",
    [40] = "EYEPOINT",
    [42] = "COM",
    [50] = "WEAPON",
    [51] = "ORDNANCE",
    [52] = "EXPLOSION",
    [53] = "CHUNK",
    [54] = "SORT_OBJECT",
    [55] = "NONCOLLIDABLE",
    [60] = "VEHICLE_GEOMETRY",
    [61] = "STRUCTURE_GEOMETRY",
    [63] = "WEAPON_GEOMETRY",
    [64] = "ORDNANCE_GEOMETRY",
    [65] = "TURRET_GEOMETRY",
    [66] = "ROTOR_GEOMETRY",
    [67] = "NACELLE_GEOMETRY",
    [68] = "FIN_GEOMETRY",
    [69] = "COCKPIT_GEOMETRY",
    [70] = "WEAPON_HARDPOINT",
    [71] = "CANNON_HARDPOINT",
    [72] = "ROCKET_HARDPOINT",
    [73] = "MORTAR_HARDPOINT",
    [74] = "SPECIAL_HARDPOINT",
    [75] = "FLAME_EMITTER",
    [76] = "SMOKE_EMITTER",
    [77] = "DUST_EMITTER",
    [81] = "PARKING_LOT",
}
utility.ClassSig = {
    RECYCLER = "RCYC",
    FACTORY = "FACT",
    ARMORY = "ARMR",
    CONSTRUCTOR = "CNST",
    SUPPLY_DEPOT = "SDEP",
    REPAIR_DEPOT = "RDEP"
}
utility.AiCommand = {
    NONE = 0,
    SELECT = 1,
    STOP = 2,
    GO = 3,
    ATTACK = 4,
    FOLLOW = 5,
    FORMATION = 6,
    PICKUP = 7,
    DROPOFF = 8,
    NO_DROPOFF = 9,
    GET_REPAIR = 10,
    GET_RELOAD = 11,
    GET_WEAPON = 12,
    GET_CAMERA = 13,
    GET_BOMB = 14,
    DEFEND = 15,
    GO_TO_GEYSER = 16,
    RESCUE = 17,
    RECYCLE = 18,
    SCAVENGE = 19,
    HUNT = 20,
    BUILD = 21,
    PATROL = 22,
    STAGE = 23,
    SEND = 24,
    GET_IN = 25,
    LAY_MINES = 26,
    CLOAK = 27,   -- {VERSION 2.1+}
    DECLOAK = 28, -- {VERSION 2.1+}
    [0] = "NONE",
    [1] = "SELECT",
    [2] = "STOP",
    [3] = "GO",
    [4] = "ATTACK",
    [5] = "FOLLOW",
    [6] = "FORMATION",
    [7] = "PICKUP",
    [8] = "DROPOFF",
    [9] = "NO_DROPOFF",
    [10] = "GET_REPAIR",
    [11] = "GET_RELOAD",
    [12] = "GET_WEAPON",
    [13] = "GET_CAMERA",
    [14] = "GET_BOMB",
    [15] = "DEFEND",
    [16] = "GO_TO_GEYSER",
    [17] = "RESCUE",
    [18] = "RECYCLE",
    [19] = "SCAVENGE",
    [20] = "HUNT",
    [21] = "BUILD",
    [22] = "PATROL",
    [23] = "STAGE",
    [24] = "SEND",
    [25] = "GET_IN",
    [26] = "LAY_MINES",
    [27] = "CLOAK",   -- {VERSION 2.1+}
    [28] = "DECLOAK", -- {VERSION 2.1+}
    -- Missing Constants
    DEPLOY = 29,
    UNDEPLOY = 30,
    [29] = "DEPLOY",
    [30] = "UNDEPLOY"
}

----------------------------------------------------------------------------------
-- GLOBAL ALIASES & RECENT INFRASTRUCTURE
----------------------------------------------------------------------------------

-- Global Aliases (Restore access for code below)
AiCommand = utility.AiCommand

-- Lightweight command arbitration/throttling shared by managers.
aiCore.CommandState = aiCore.CommandState or {}
aiCore.CommandConfig = aiCore.CommandConfig or {
    minInterval = 0.6
}

local function IsProtectedCommand(cmd)
    return cmd == AiCommand.GET_REPAIR
        or cmd == AiCommand.GET_RELOAD
        or cmd == AiCommand.RESCUE
        or cmd == AiCommand.BUILD
        or cmd == AiCommand.RECYCLE
        or cmd == AiCommand.PICKUP
        or cmd == AiCommand.DROPOFF
        or cmd == AiCommand.GET_IN
end

function aiCore.CanIssueCommand(h, newCmd, opts)
    if not IsValid(h) or not IsAlive(h) then return false end
    opts = opts or {}
    local now = GetTime()
    local state = aiCore.CommandState[h]
    if not state then
        state = { time = -999.0, cmd = AiCommand.NONE, target = nil }
        aiCore.CommandState[h] = state
    end

    local minInterval = opts.minInterval or aiCore.CommandConfig.minInterval or 0.6
    if not opts.ignoreThrottle and (now - state.time) < minInterval then
        return false
    end

    local cur = GetCurrentCommand(h)
    if not opts.overrideProtected and cur ~= newCmd and IsProtectedCommand(cur) then
        return false
    end

    return true
end

function aiCore.RecordCommand(h, cmd, target)
    aiCore.CommandState[h] = aiCore.CommandState[h] or {}
    local state = aiCore.CommandState[h]
    state.time = GetTime()
    state.cmd = cmd
    state.target = target
end

function aiCore.TryAttack(h, target, priority, opts)
    opts = opts or {}
    if not IsValid(h) or not IsValid(target) then return false end
    if not aiCore.CanIssueCommand(h, AiCommand.ATTACK, opts) then return false end
    if not opts.forceIssue and GetCurrentCommand(h) == AiCommand.ATTACK and GetCurrentWho(h) == target then return false end
    priority = NormalizeScriptPriority(h, priority)
    Attack(h, target, priority)
    aiCore.RecordCommand(h, AiCommand.ATTACK, target)
    return true
end

function aiCore.TryPickup(h, target, priority, opts)
    if not IsValid(h) or not IsValid(target) then return false end
    if not aiCore.CanIssueCommand(h, AiCommand.PICKUP, opts) then return false end
    if GetCurrentCommand(h) == AiCommand.PICKUP and GetCurrentWho(h) == target then return false end
    priority = NormalizeScriptPriority(h, priority)
    Pickup(h, target, priority)
    aiCore.RecordCommand(h, AiCommand.PICKUP, target)
    return true
end

function aiCore.TryScavenge(h, target, priority, opts)
    if not IsValid(h) or not IsValid(target) then return false end
    if not aiCore.CanIssueCommand(h, AiCommand.SCAVENGE, opts) then return false end
    if GetCurrentCommand(h) == AiCommand.SCAVENGE and GetCurrentWho(h) == target then return false end
    priority = NormalizeScriptPriority(h, priority)
    SetCommand(h, AiCommand.SCAVENGE, priority, target, nil, nil, nil)
    aiCore.RecordCommand(h, AiCommand.SCAVENGE, target)
    return true
end

function aiCore.TrySetCommand(h, command, priority, who, where, when, param, opts)
    if not IsValid(h) then return false end
    if not aiCore.CanIssueCommand(h, command, opts) then return false end
    priority = NormalizeScriptPriority(h, priority)
    SetCommand(h, command, priority, who, where, when, param)
    aiCore.RecordCommand(h, command, who)
    return true
end

function aiCore.TrySetTurbo(h, enabled)
    if not IsValid(h) or not exu then return false end
    local setTurbo = exu.SetUnitTurbo or exu.setunitturbo
    if not setTurbo then return false end
    local teamNum = GetTeamNum(h)
    if teamNum == 1 then
        enabled = true
    else
        local team = aiCore and aiCore.ActiveTeams and aiCore.ActiveTeams[teamNum] or nil
        local difficulty = (team and team.Config and team.Config.difficulty) or 2
        if difficulty < 4 then
            enabled = false
        end
    end
    local ok = pcall(setTurbo, h, enabled and true or false)
    return ok
end

function aiCore.IsMissileThreat(attacker)
    if not IsValid(attacker) then return false end
    for i = 0, 4 do
        local w = string.lower(utility.CleanString(GetWeaponClass(attacker, i)))
        if w ~= "" then
            if string.find(w, "heat") or string.find(w, "image") or string.find(w, "hornet") or string.find(w, "shad")
                or string.find(w, "comet") or string.find(w, "radar") or string.find(w, "missile") then
                return true
            end
        end
    end
    return false
end

function aiCore.GetMissileThreatTypeFromHandle(attacker)
    if not IsValid(attacker) then return nil end
    for i = 0, 4 do
        local w = utility.CleanString(GetWeaponClass(attacker, i))
        if w ~= "" then
            local threatType = aiCore.GetMissileThreatType(w)
            if threatType then
                return threatType
            end
        end
    end
    return nil
end

function aiCore.GetMissileThreatType(odf)
    local s = string.lower(utility.CleanString(odf))
    if s == "" then return nil end

    if string.find(s, "comet") or string.find(s, "radar") or string.find(s, "radarmsl") then
        return "radar"
    end
    if string.find(s, "hornet") or string.find(s, "heat") or string.find(s, "heatmsl") then
        return "heat"
    end
    if string.find(s, "shad") or string.find(s, "image") or string.find(s, "imagemsl") then
        return "image"
    end
    if string.find(s, "msl") or string.find(s, "missile") then
        return "tracking"
    end

    local odfHandle = OpenODF(s)
    if odfHandle then
        local weaponClass = string.lower(utility.CleanString(GetODFString(odfHandle, "WeaponClass", "classLabel", "")))
        local ordName = string.lower(utility.CleanString(GetODFString(odfHandle, "WeaponClass", "ordName", "")))
        local radarObject = string.lower(utility.CleanString(GetODFString(odfHandle, "RadarLauncherClass", "objectClass", "")))

        if weaponClass == "radarlauncher" or radarObject == "radarmsl" or string.find(ordName, "radar") then
            return "radar"
        end
        if weaponClass == "thermallauncher" or string.find(ordName, "heat") then
            return "heat"
        end
        if weaponClass == "imagelauncher" or string.find(ordName, "image") then
            return "image"
        end
        if string.find(ordName, "msl") or string.find(ordName, "missile") then
            return "tracking"
        end
    end

    return nil
end

function aiCore.GetDecoyOdfForUnit(h)
    if OpenODF("apdecoy") then return "apdecoy" end
    return nil
end

aiCore.DecoyState = aiCore.DecoyState or {}
function aiCore.TryDeployDecoy(h, cooldown)
    if not IsValid(h) or not IsAlive(h) or not IsCraft(h) then return false end
    if h == GetPlayerHandle() then return false end
    local now = GetTime()
    local state = aiCore.DecoyState[h] or { nextTime = 0.0 }
    aiCore.DecoyState[h] = state
    cooldown = cooldown or 8.0
    if now < (state.nextTime or 0.0) then return false end

    local odf = aiCore.GetDecoyOdfForUnit(h)
    if odf then
        local pos = GetPosition(h)
        if pos then
            local decoy = BuildObject(odf, GetTeamNum(h), pos)
            if IsValid(decoy) then
                state.nextTime = now + cooldown
                return true
            end
        end
    end

    return false
end

function aiCore.IsTrackingMissileOdf(odf)
    return aiCore.GetMissileThreatType(odf) ~= nil
end

aiCore.CountermeasureState = aiCore.CountermeasureState or {}
aiCore.TrackedOrdnanceThreats = aiCore.TrackedOrdnanceThreats or {}
aiCore.TrackedMissileAllocations = aiCore.TrackedMissileAllocations or {}

function aiCore.GetCountermeasureMask(h, threatType)
    if not IsValid(h) then return 0 end
    if threatType == "radar" then
        return aiCore.GetWeaponMask(h, { "redfld" })
    end
    if threatType == "heat" or threatType == "image" then
        return aiCore.GetWeaponMask(h, { "phantom" })
    end
    return 0
end

function aiCore.TryUseMissileCountermeasure(h, threatType, distance)
    if not IsValid(h) or not IsAlive(h) then return false end
    if h == GetPlayerHandle() then return false end

    local now = GetTime()
    local state = aiCore.CountermeasureState[h] or {
        nextFieldTime = 0.0,
        nextDecoyTime = 0.0
    }
    aiCore.CountermeasureState[h] = state

    local dedicatedMask = aiCore.GetCountermeasureMask(h, threatType)
    if dedicatedMask > 0 and now >= (state.nextFieldTime or 0.0) then
        FireWeaponMask(h, dedicatedMask)
        state.nextFieldTime = now + 3.5
        return true
    end

    local decoyThreshold = (threatType == "radar") and 150.0 or 120.0
    if distance <= decoyThreshold and now >= (state.nextDecoyTime or 0.0) then
        if aiCore.TryDeployDecoy(h, 5.0) then
            state.nextDecoyTime = now + 1.0
            return true
        end
    end

    return false
end

function aiCore.SelectLikelyMissileTarget(shooter, transform)
    if not IsValid(shooter) or not transform then return nil end

    local directTarget = GetCurrentWho(shooter)
    if IsValid(directTarget) and IsAlive(directTarget) and IsCraft(directTarget) and not IsAlly(shooter, directTarget) then
        return directTarget
    end

    local ordPos = MatrixToPosition(transform) or GetPosition(shooter)
    if not ordPos then return nil end

    local front = Normalize(SetVector(transform.front_x, transform.front_y, transform.front_z))
    local bestTarget = nil
    local bestScore = 999999

    for candidate in ObjectsInRange(650.0, ordPos) do
        if IsValid(candidate) and IsAlive(candidate) and IsCraft(candidate) and not IsAlly(shooter, candidate) then
            local toTarget = GetPosition(candidate) - ordPos
            local forwardDist = DotProduct(front, toTarget)
            if forwardDist > 0 then
                local lateralVec = toTarget - (front * forwardDist)
                local lateralDist = Length(lateralVec)
                if lateralDist < 140.0 then
                    local score = lateralDist + (forwardDist * 0.12)
                    if score < bestScore then
                        bestScore = score
                        bestTarget = candidate
                    end
                end
            end
        end
    end

    return bestTarget
end

function aiCore.RegisterTrackedOrdnanceThreat(odf, shooter, transform, ordnanceHandle)
    if not exu or not exu.GetOrdnanceAttribute then return false end
    if not ordnanceHandle or not IsValid(shooter) then return false end

    local threatType = aiCore.GetMissileThreatType(odf)
    if not threatType then return false end

    local target = aiCore.SelectLikelyMissileTarget(shooter, transform)
    if not IsValid(target) then return false end

    aiCore.TrackedOrdnanceThreats[ordnanceHandle] = {
        odf = string.lower(utility.CleanString(odf)),
        shooter = shooter,
        target = target,
        threatType = threatType,
        createdAt = GetTime(),
        expiresAt = GetTime() + 12.0,
        lastDistance = 999999.0
    }
    return true
end

function aiCore.RegisterTrackedMissileAllocation(odf, shooter, transform, ordnanceHandle)
    if not ordnanceHandle or not IsValid(shooter) or not IsAlive(shooter) then return false end

    local target = aiCore.SelectLikelyMissileTarget(shooter, transform)
    if not IsValid(target) or not IsAlive(target) or IsAlly(shooter, target) then
        return false
    end

    local profile = GetMissileWeaponProfile(odf)
    if not profile or not profile.damage or profile.damage <= 0.0 then
        return false
    end

    local now = GetTime()
    aiCore.TrackedMissileAllocations[ordnanceHandle] = {
        ordnanceHandle = ordnanceHandle,
        odf = string.lower(utility.CleanString(profile.ordName or odf)),
        shooter = shooter,
        teamNum = GetTeamNum(shooter),
        target = target,
        damage = profile.damage,
        createdAt = now,
        expiresAt = now + math.max(1.0, profile.lifeSpan or 10.0) + 0.35,
    }
    return true
end

function aiCore.UpdateTrackedMissileAllocations()
    local now = GetTime()
    for ordnanceHandle, entry in pairs(aiCore.TrackedMissileAllocations) do
        local shooter = entry.shooter
        local target = entry.target
        if now > (entry.expiresAt or 0.0)
            or not IsValid(target)
            or not IsAlive(target)
            or not IsValid(shooter)
            or not IsAlive(shooter)
            or IsAlly(shooter, target) then
            aiCore.TrackedMissileAllocations[ordnanceHandle] = nil
        end
    end
end

function aiCore.GetPendingMissileDamage(teamNum, target)
    if not IsValid(target) then return 0.0 end

    local total = 0.0
    for _, entry in pairs(aiCore.TrackedMissileAllocations) do
        if entry.teamNum == teamNum and entry.target == target then
            total = total + (entry.damage or 0.0)
        end
    end
    return total
end

function aiCore.GetPendingMissileDamageForShooter(shooter, target)
    if not IsValid(shooter) or not IsValid(target) then return 0.0 end

    local total = 0.0
    for _, entry in pairs(aiCore.TrackedMissileAllocations) do
        if entry.shooter == shooter and entry.target == target then
            total = total + (entry.damage or 0.0)
        end
    end
    return total
end

function aiCore.GetPendingMissileCountForShooter(shooter, target)
    if not IsValid(shooter) or not IsValid(target) then return 0 end

    local count = 0
    for _, entry in pairs(aiCore.TrackedMissileAllocations) do
        if entry.shooter == shooter and entry.target == target then
            count = count + 1
        end
    end
    return count
end

function aiCore.FindMissileRetargetCandidate(shooter, currentTarget, teamNum, searchRadius, killBuffer)
    if not IsValid(shooter) or not IsAlive(shooter) then return nil end

    searchRadius = tonumber(searchRadius) or 200.0
    killBuffer = tonumber(killBuffer) or 1.1

    local bestTarget = nil
    local bestScore = nil
    for candidate in ObjectsInRange(searchRadius, shooter) do
        if IsValid(candidate)
            and IsAlive(candidate)
            and candidate ~= currentTarget
            and not IsAlly(shooter, candidate)
            and (IsCraft(candidate) or IsBuilding(candidate)) then
            local targetHealth = GetUnitCurrentHealthPoints(candidate)
            if targetHealth and targetHealth > 0.0 then
                local pendingDamage = aiCore.GetPendingMissileDamage(teamNum, candidate)
                local deficit = (targetHealth * killBuffer) - pendingDamage
                if deficit > 0.0 then
                    local dist = GetDistance(shooter, candidate)
                    local score = dist + math.min(deficit, 1200.0) * 0.05
                    if not bestScore or score < bestScore then
                        bestScore = score
                        bestTarget = candidate
                    end
                end
            end
        end
    end

    return bestTarget
end

function aiCore.UpdateTrackedOrdnanceThreats()
    if not exu or not exu.GetOrdnanceAttribute then return end

    local now = GetTime()
    local transformAttr = (exu.ORDNANCE and exu.ORDNANCE.TRANSFORM) or 1
    for ordnanceHandle, threat in pairs(aiCore.TrackedOrdnanceThreats) do
        local target = threat.target
        if not IsValid(target) or not IsAlive(target) or now > (threat.expiresAt or 0.0) then
            aiCore.TrackedOrdnanceThreats[ordnanceHandle] = nil
        else
            local ok, transform = pcall(exu.GetOrdnanceAttribute, ordnanceHandle, transformAttr)
            local ordPos = ok and transform and MatrixToPosition(transform) or nil
            if not ordPos then
                if now > ((threat.createdAt or now) + 1.5) then
                    aiCore.TrackedOrdnanceThreats[ordnanceHandle] = nil
                end
            else
                local distance = Length(GetPosition(target) - ordPos)
                local closing = distance < ((threat.lastDistance or distance) - 2.0)
                threat.lastDistance = distance

                local responseDistance = (threat.threatType == "radar") and 220.0 or 180.0
                if closing and distance <= responseDistance then
                    if aiCore.TryUseMissileCountermeasure(target, threat.threatType, distance) then
                        aiCore.TrackedOrdnanceThreats[ordnanceHandle] = nil
                    end
                end
            end
        end
    end
end

aiCore.ExuCallbackMux = aiCore.ExuCallbackMux or {
    installed = false,
    callbacks = {}
}

local function EnsureMuxSlot(name)
    local mux = aiCore.ExuCallbackMux
    local slot = mux.callbacks[name]
    if not slot then
        slot = {
            handlers = {},
            wrapper = nil,
            external = nil
        }
        mux.callbacks[name] = slot
    end
    return slot
end

function aiCore.InstallExuCallbackMultiplexer()
    if not exu then return false end

    local callbackNames = { "BulletInit", "BulletHit", "AddScrap" }
    for _, name in ipairs(callbackNames) do
        local slot = EnsureMuxSlot(name)
        if not slot.wrapper then
            slot.external = exu[name]
            slot.wrapper = function(...)
                local current = aiCore.ExuCallbackMux.callbacks[name]
                if not current then return end

                if type(current.external) == "function" and current.external ~= current.wrapper then
                    local ok, err = pcall(current.external, ...)
                    if not ok and aiCore.Debug then
                        print("aiCore exu mux external callback error (" .. name .. "): " .. tostring(err))
                    end
                end

                for _, fn in ipairs(current.handlers) do
                    local ok, err = pcall(fn, ...)
                    if not ok and aiCore.Debug then
                        print("aiCore exu mux handler error (" .. name .. "): " .. tostring(err))
                    end
                end
            end
        end

        if exu[name] ~= slot.wrapper then
            if type(exu[name]) == "function" and exu[name] ~= slot.wrapper then
                slot.external = exu[name]
            end
            exu[name] = slot.wrapper
        end
    end

    aiCore.ExuCallbackMux.installed = true
    return true
end

function aiCore.EnsureExuCallbackMultiplexer()
    if not exu then return false end
    if not aiCore.ExuCallbackMux.installed then
        return aiCore.InstallExuCallbackMultiplexer()
    end

    for name, slot in pairs(aiCore.ExuCallbackMux.callbacks) do
        if slot.wrapper and exu[name] ~= slot.wrapper then
            if type(exu[name]) == "function" and exu[name] ~= slot.wrapper then
                slot.external = exu[name]
            end
            exu[name] = slot.wrapper
        end
    end
    return true
end

function aiCore.RegisterExuCallback(name, fn)
    if type(fn) ~= "function" then return false end
    if not aiCore.InstallExuCallbackMultiplexer() then return false end

    local slot = EnsureMuxSlot(name)
    for _, existing in ipairs(slot.handlers) do
        if existing == fn then return true end
    end
    table.insert(slot.handlers, fn)
    return true
end

function aiCore.SetupOrdnanceHooks()
    if aiCore._ordnanceHooksInstalled then return end
    local initInstalled = aiCore.RegisterExuCallback("BulletInit", function(odf, shooter, transform, ordnanceHandle)
        if not aiCore.IsTrackingMissileOdf(odf) then return end
        aiCore.RegisterTrackedOrdnanceThreat(odf, shooter, transform, ordnanceHandle)
        aiCore.RegisterTrackedMissileAllocation(odf, shooter, transform, ordnanceHandle)
    end)

    local hitInstalled = aiCore.RegisterExuCallback("BulletHit", function(odf, shooter, hitObject, transform, ordnanceHandle)
        if ordnanceHandle and aiCore.TrackedOrdnanceThreats then
            aiCore.TrackedOrdnanceThreats[ordnanceHandle] = nil
        end
        if ordnanceHandle and aiCore.TrackedMissileAllocations then
            aiCore.TrackedMissileAllocations[ordnanceHandle] = nil
        end
    end)

    aiCore._ordnanceHooksInstalled = (initInstalled or hitInstalled) and true or false
end

-- Path Utilities
paths = {}
function paths.GetPosition(p, pt)
    if type(p) ~= "string" then
        if IsValid(p) then return GetPosition(p) end -- Native GetPosition for handles
        return p                                     -- Already a vector or other data
    end
    pt = pt or 0
    local count = paths.GetPathPointCount(p)
    if count > pt then return GetPosition(p, pt) end
    return nil
end

function paths.GetPathPointCount(p)
    if type(p) ~= "string" then return 0 end
    return GetPathPointCount(p) or 0
end

function paths.IteratePath(p)
    local count = paths.GetPathPointCount(p)
    local i = 0
    if count == 0 then return function() end end
    return function()
        if i < count then
            local pos = paths.GetPosition(p, i); i = i + 1; return i, pos
        end
    end
end

local function ResolveReferencePosition(ref)
    if ref == nil then return nil end
    if type(ref) == "string" then
        return paths.GetPosition(ref, 0)
    end
    if type(ref) == "lightuserdata" and IsValid(ref) then
        return GetPosition(ref)
    end
    if type(ref) == "userdata" then
        local okValid, isValidRef = pcall(IsValid, ref)
        if okValid and isValidRef then
            local okPos, pos = pcall(GetPosition, ref)
            if okPos and pos ~= nil then
                return pos
            end
        end
        local ok, x, y, z = pcall(function()
            return ref.posit_x, ref.posit_y, ref.posit_z
        end)
        if ok and x ~= nil and y ~= nil and z ~= nil then
            return SetVector(x, y, z)
        end
    end
    return ref
end

local function DistanceBetweenRefs(a, b)
    local aPos = ResolveReferencePosition(a)
    local bPos = ResolveReferencePosition(b)
    if not aPos or not bPos then return 999999 end
    local ok, distance = pcall(function()
        return Length(aPos - bPos)
    end)
    if ok and distance ~= nil then
        return distance
    end

    local okA, validA = pcall(IsValid, a)
    local okB, validB = pcall(IsValid, b)
    if okA and validA and okB and validB then
        local okDist, handleDistance = pcall(GetDistance, a, b)
        if okDist and handleDistance ~= nil then
            return handleDistance
        end
    end

    return 999999
end

local function RemoveFromList(list, value)
    if not list then return false end
    for i = #list, 1, -1 do
        if list[i] == value then
            table.remove(list, i)
            return true
        end
    end
    return false
end

local function IsSpecializedPoolClass(classLabel)
    if not classLabel or classLabel == "" then return false end
    return string.find(classLabel, utility.ClassLabel.MINELAYER) ~= nil
        or string.find(classLabel, utility.ClassLabel.HOWITZER) ~= nil
        or string.find(classLabel, utility.ClassLabel.TURRET) ~= nil
        or string.find(classLabel, utility.ClassLabel.TURRET_TANK) ~= nil
        or string.find(classLabel, utility.ClassLabel.APC) ~= nil
        or string.find(classLabel, utility.ClassLabel.TUG) ~= nil
        or string.find(classLabel, utility.ClassLabel.WALKER) ~= nil
end

local function PruneSpecializedPoolUnits(list)
    if not list then return end
    for i = #list, 1, -1 do
        local h = list[i]
        local cls = string.lower(utility.CleanString(GetClassLabel(h)))
        if not IsValid(h) or IsSpecializedPoolClass(cls) then
            table.remove(list, i)
        end
    end
end

local function Clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function GetStrategicRefKey(ref)
    if ref == nil then return nil end
    if type(ref) == "string" then
        return "path:" .. ref
    end
    if IsValid(ref) then
        return ref
    end

    local pos = ResolveReferencePosition(ref)
    if pos then
        return string.format("pos:%d:%d", math.floor(pos.x + 0.5), math.floor(pos.z + 0.5))
    end

    return tostring(ref)
end

function aiCore.EstimateCombatStrength(h)
    if not IsValid(h) or not IsAlive(h) then return 0.0 end

    local classLabel = string.lower(utility.CleanString(GetClassLabel(h)))
    local maxHealth = math.max(GetMaxHealth(h) or 0.0, 1.0)
    local healthRatio = Clamp((GetCurHealth(h) or maxHealth) / maxHealth, 0.15, 1.5)

    if IsBuilding(h) then
        local base = 1.5
        if string.find(classLabel, utility.ClassLabel.RECYCLER)
            or string.find(classLabel, utility.ClassLabel.FACTORY)
            or string.find(classLabel, utility.ClassLabel.ARMORY)
            or string.find(classLabel, utility.ClassLabel.CONSTRUCTOR) then
            base = 4.5
        elseif string.find(classLabel, utility.ClassLabel.REPAIR_DEPOT)
            or string.find(classLabel, utility.ClassLabel.SUPPLY_DEPOT)
            or string.find(classLabel, utility.ClassLabel.HOWITZER)
            or string.find(classLabel, utility.ClassLabel.TURRET) then
            base = 3.5
        elseif string.find(classLabel, utility.ClassLabel.POWERPLANT)
            or string.find(classLabel, utility.ClassLabel.BARRACKS) then
            base = 2.5
        end
        return base * healthRatio
    end

    if not IsCraft(h) then
        return 0.5 * healthRatio
    end

    local weaponScore = 0.0
    for i = 0, 4 do
        local w = string.lower(utility.CleanString(GetWeaponClass(h, i)))
        if w ~= "" then
            weaponScore = weaponScore + 0.45
            if string.find(w, "msl") or string.find(w, "missile") then
                weaponScore = weaponScore + 0.2
            elseif string.find(w, "mortar") or string.find(w, "howitzer") then
                weaponScore = weaponScore + 0.35
            elseif string.find(w, "thump") then
                weaponScore = weaponScore + 0.6
            end
        end
    end

    local classBonus = 0.8
    if string.find(classLabel, utility.ClassLabel.WALKER) then
        classBonus = 3.0
    elseif string.find(classLabel, utility.ClassLabel.HOWITZER) then
        classBonus = 2.7
    elseif string.find(classLabel, "tank") or string.find(classLabel, "rocket") or string.find(classLabel, "bomber") then
        classBonus = 2.0
    elseif string.find(classLabel, utility.ClassLabel.APC) or string.find(classLabel, utility.ClassLabel.MINELAYER) then
        classBonus = 1.4
    elseif string.find(classLabel, utility.ClassLabel.SCAVENGER) or string.find(classLabel, utility.ClassLabel.TUG) then
        classBonus = 0.7
    elseif string.find(classLabel, utility.ClassLabel.PERSON) then
        classBonus = 0.4
    end

    return (classBonus + weaponScore) * healthRatio
end

aiCore.EmptyList = aiCore.EmptyList or {}
aiCore.ObjectCache = aiCore.ObjectCache or {
    dirty = true,
    lastCraftUpdate = -999.0,
    craftUpdateInterval = 1.0,
    lastObjectUpdate = -999.0,
    objectUpdateInterval = 8.0,
    handles = {},
    handleSet = {},
    teamCraft = {},
    teamBuildings = {},
    teamTargets = {},
    pilotPersons = {},
    scrapObjects = {},
    allBuildings = {}
}

function aiCore.InvalidateObjectCache()
    aiCore.ObjectCache.dirty = true
    aiCore.ObjectCache.lastCraftUpdate = -999.0
    aiCore.ObjectCache.lastObjectUpdate = -999.0
end

local function AddCachedHandle(list, set, h)
    if not h or not IsValid(h) or set[h] then
        return false
    end

    set[h] = true
    list[#list + 1] = h
    return true
end

local function RemoveCachedHandle(list, set, h)
    if not h or not set[h] then
        return
    end

    set[h] = nil
    for index = #list, 1, -1 do
        if list[index] == h then
            table.remove(list, index)
            break
        end
    end
end

function aiCore.ResetObjectCacheTracking()
    local cache = aiCore.ObjectCache
    cache.handles = {}
    cache.handleSet = {}
    cache.teamCraft = {}
    cache.teamBuildings = {}
    cache.teamTargets = {}
    cache.pilotPersons = {}
    cache.scrapObjects = {}
    cache.allBuildings = {}
    aiCore.InvalidateObjectCache()
end

function aiCore.TrackWorldObject(h)
    if AddCachedHandle(aiCore.ObjectCache.handles, aiCore.ObjectCache.handleSet, h) then
        aiCore.InvalidateObjectCache()
        return true
    end

    return false
end

function aiCore.UntrackWorldObject(h)
    RemoveCachedHandle(aiCore.ObjectCache.handles, aiCore.ObjectCache.handleSet, h)
    aiCore.InvalidateObjectCache()
end

local function RebuildTeamTargetCache(cache)
    local teamTargets = {}

    for teamNum, craftList in pairs(cache.teamCraft or {}) do
        local merged = {}
        for i = 1, #craftList do
            merged[#merged + 1] = craftList[i]
        end
        teamTargets[teamNum] = merged
    end

    for teamNum, buildingList in pairs(cache.teamBuildings or {}) do
        local merged = teamTargets[teamNum]
        if not merged then
            merged = {}
            teamTargets[teamNum] = merged
        end
        for i = 1, #buildingList do
            merged[#merged + 1] = buildingList[i]
        end
    end

    cache.teamTargets = teamTargets
end

function aiCore.RefreshObjectCache(force)
    local cache = aiCore.ObjectCache
    local now = GetTime()
    local refreshCraft = force or now >= ((cache.lastCraftUpdate or -999.0) + (cache.craftUpdateInterval or 1.0))
    local refreshObjects = force or now >= ((cache.lastObjectUpdate or -999.0) + (cache.objectUpdateInterval or 8.0))
    if not force and not cache.dirty and not refreshCraft and not refreshObjects then
        return
    end

    local teamCraft = {}
    local teamBuildings = {}
    local allBuildings = {}
    local pilotPersons = {}
    local scrapObjects = {}

    for index = #cache.handles, 1, -1 do
        local h = cache.handles[index]
        if not IsValid(h) then
            RemoveCachedHandle(cache.handles, cache.handleSet, h)
        elseif IsAlive(h) then
            if IsCraft(h) then
                if not IsIndependenceLocked(h) then
                    local team = GetTeamNum(h)
                    if team and team >= 0 then
                        local craftList = teamCraft[team]
                        if not craftList then
                            craftList = {}
                            teamCraft[team] = craftList
                        end
                        craftList[#craftList + 1] = h
                    end
                end
            elseif IsBuilding(h) then
                allBuildings[#allBuildings + 1] = h
                local team = GetTeamNum(h)
                if team and team >= 0 then
                    local buildingList = teamBuildings[team]
                    if not buildingList then
                        buildingList = {}
                        teamBuildings[team] = buildingList
                    end
                    buildingList[#buildingList + 1] = h
                end
            elseif IsPerson(h) then
                if not IsIndependenceLocked(h) then
                    pilotPersons[#pilotPersons + 1] = h
                end
            else
                local cls = string.lower(utility.CleanString(GetClassLabel(h)))
                if cls == utility.ClassLabel.SCRAP then
                    scrapObjects[#scrapObjects + 1] = h
                end
            end
        end
    end

    cache.teamCraft = teamCraft
    cache.teamBuildings = teamBuildings
    cache.allBuildings = allBuildings
    cache.pilotPersons = pilotPersons
    cache.scrapObjects = scrapObjects
    cache.lastCraftUpdate = now
    cache.lastObjectUpdate = now
    cache.dirty = false

    RebuildTeamTargetCache(cache)
end

function aiCore.GetCachedBuildings(teamNum)
    aiCore.RefreshObjectCache(false)
    if teamNum == nil then
        return aiCore.ObjectCache.allBuildings or aiCore.EmptyList
    end
    local list = aiCore.ObjectCache.teamBuildings[teamNum]
    if list then return list end
    return aiCore.EmptyList
end

function aiCore.GetCachedScrapObjects()
    aiCore.RefreshObjectCache(false)
    local list = aiCore.ObjectCache.scrapObjects
    if list then return list end
    return aiCore.EmptyList
end

function aiCore.GetCachedPilotPersons()
    aiCore.RefreshObjectCache(false)
    local list = aiCore.ObjectCache.pilotPersons
    if list then return list end
    return aiCore.EmptyList
end

function aiCore.GetCachedTeamCraft(teamNum)
    aiCore.RefreshObjectCache(false)
    local list = aiCore.ObjectCache.teamCraft[teamNum]
    if list then return list end
    return aiCore.EmptyList
end

function aiCore.GetCachedTeamTargets(teamNum)
    aiCore.RefreshObjectCache(false)
    local list = aiCore.ObjectCache.teamTargets[teamNum]
    if list then return list end
    return aiCore.EmptyList
end


-- Integrated Producer Logic
producer = {
    Queue = {}, -- table<TeamNum, list<Job>>
    Orders = {} -- table<Handle, Job>
}

function producer.GetQueueOwner(teamNum, teamObj)
    if teamObj and teamObj.teamNum == teamNum then return teamObj end
    if aiCore and aiCore.ActiveTeams then
        return aiCore.ActiveTeams[teamNum]
    end
    return nil
end

function producer.GetJobSortScore(job, teamObj)
    local basePriority = (job and job.data and job.data.priority) or 999999
    if teamObj and teamObj.GetEffectiveBuildPriority then
        return teamObj:GetEffectiveBuildPriority((job.data and job.data.account) or nil, basePriority, job.data)
    end
    return basePriority
end

function producer.SortQueue(teamNum, teamObj)
    local queue = producer.Queue[teamNum]
    if not queue then return end
    local owner = producer.GetQueueOwner(teamNum, teamObj)
    table.sort(queue, function(a, b)
        local ap = producer.GetJobSortScore(a, owner)
        local bp = producer.GetJobSortScore(b, owner)
        if ap == bp then
            local apr = (a.data and a.data.priority) or 999999
            local bpr = (b.data and b.data.priority) or 999999
            return apr < bpr
        end
        return ap < bp
    end)
end

function producer.QueueJob(odf, team, location, builder, data)
    if not producer.Queue[team] then producer.Queue[team] = {} end
    table.insert(producer.Queue[team], {
        odf = odf,
        location = location,
        builder = builder, -- TeamSlotInteger (Optional)
        data = data
    })
    producer.SortQueue(team)
end

function producer.ProcessQueues(teamObj)
    if teamObj.Config and not teamObj.Config.manageFactories then return end
    local team = teamObj.teamNum
    local queue = producer.Queue[team]
    if not queue or #queue == 0 then return end
    if teamObj.UpdateBuildAccountState then
        teamObj:UpdateBuildAccountState()
    end

    -- Recover from stuck/failed build orders so one bad command cannot block a producer forever.
    for proc, active in pairs(producer.Orders) do
        local job = active
        local issuedAt = 0
        if type(active) == "table" and active.job then
            job = active.job
            issuedAt = active.issuedAt or 0
        end

        if not IsValid(proc) then
            producer.Orders[proc] = nil
        elseif job and GetTeamNum(proc) == team and (GetTime() - issuedAt) > 20.0 and not IsBusy(proc) then
            local exists = false
            for _, q in ipairs(queue) do
                if q.odf == job.odf and q.data and job.data and q.data.priority == job.data.priority then
                    exists = true
                    break
                end
            end
            if not exists then
                table.insert(queue, 1, job)
                producer.SortQueue(team, teamObj)
            end
            producer.Orders[proc] = nil
        end
    end

    producer.SortQueue(team, teamObj)

    -- Identify available producers
    local producers = {}
    if teamObj.recyclerMgr and IsValid(teamObj.recyclerMgr.handle) and not IsBusy(teamObj.recyclerMgr.handle) then
        table.insert(producers, teamObj.recyclerMgr.handle)
    end
    if teamObj.factoryMgr and IsValid(teamObj.factoryMgr.handle) and not IsBusy(teamObj.factoryMgr.handle) and IsDeployed(teamObj.factoryMgr.handle) then
        table.insert(producers, teamObj.factoryMgr.handle)
    end
    if teamObj.constructorMgr and IsValid(teamObj.constructorMgr.handle) and not IsBusy(teamObj.constructorMgr.handle) then
        table.insert(producers, teamObj.constructorMgr.handle)
    end

    if #producers == 0 then return end

    local scrap = GetScrap(team)
    local maxScrap = GetMaxScrap(team)
    local pilotCharge = GetPilot(team)

    local removals = {}

    local function GetScrapCost(odf)
        local h = OpenODF(odf)
        if not h then return 0 end
        return GetODFInt(h, "GameObjectClass", "scrapCost", 0)
    end
    local function GetPilotCost(odf)
        local h = OpenODF(odf)
        if not h then return 0 end
        return GetODFInt(h, "GameObjectClass", "pilotCost", 0)
    end

    for i, job in ipairs(queue) do
        local cost = GetScrapCost(job.odf)
        local pilotCost = GetPilotCost(job.odf)
        local factionUnits = aiCore.Units and aiCore.Units[teamObj.faction] or nil
        local constructorOdf = factionUnits and factionUnits.constructor or nil
        local scavengerOdf = factionUnits and factionUnits.scavenger or nil
        local constructorReady = teamObj.constructorMgr and IsValid(teamObj.constructorMgr.handle)
        local recyclerOnlyUnit = factionUnits and (job.odf == factionUnits.scout or job.odf == factionUnits.turret)
        local requiredProducer = job.data and job.data.producer or nil
        local scavengerCount = 0
        if teamObj.scavengers then
            for _, s in ipairs(teamObj.scavengers) do
                if IsValid(s) and IsAlive(s) then
                    scavengerCount = scavengerCount + 1
                end
            end
        end
        local minScavengers = (teamObj.Config and teamObj.Config.minScavengers) or 0
        local shouldDeferForScavengers = minScavengers > 0 and requiredProducer == "recycler" and scavengerOdf and
            scavengerCount < minScavengers and recyclerOnlyUnit and job.odf ~= scavengerOdf
        local shouldDeferForConstructor = teamObj.Config and teamObj.Config.requireConstructorFirst and
            not constructorReady and requiredProducer == "recycler" and constructorOdf and job.odf ~= constructorOdf

        if not shouldDeferForConstructor and not shouldDeferForScavengers and cost <= maxScrap and pilotCost <= pilotCharge then
            if cost <= scrap then
                local foundProducer = nil
                for _, h in ipairs(producers) do
                    local isBuildingJob = (job.data and job.data.type == "building")
                    local procSig = utility.CleanString(GetClassLabel(h))

                    local canBuild = false
                    if requiredProducer and procSig ~= requiredProducer then
                        canBuild = false
                    elseif isBuildingJob and procSig == "constructionrig" then
                        canBuild = true
                    elseif not isBuildingJob and procSig == "recycler" then
                        canBuild = true
                    elseif not isBuildingJob and procSig == "factory" and not recyclerOnlyUnit then
                        canBuild = true
                    end

                    if canBuild and not producer.Orders[h] then
                        foundProducer = h
                        break
                    end
                end

                if foundProducer then
                    if job.location then
                        local pos = job.location
                        if type(pos) == "string" then pos = paths.GetPosition(pos, 0) end
                        aiCore.TrySetCommand(foundProducer, AiCommand.BUILD, 1, nil, pos, 0, job.odf,
                            { minInterval = 0.4, ignoreThrottle = true, overrideProtected = true })
                    else
                        Build(foundProducer, job.odf)
                    end
                    if teamObj.RecordBuildAccountSpend then
                        teamObj:RecordBuildAccountSpend((job.data and job.data.account) or nil, cost + (pilotCost * 4))
                    end
                    producer.Orders[foundProducer] = { job = job, issuedAt = GetTime() }
                    table.insert(removals, i)
                    for idx, h in ipairs(producers) do
                        if h == foundProducer then
                            table.remove(producers, idx); break
                        end
                    end
                end
            else
                -- Skip jobs we cannot currently afford and continue scanning the queue.
            end
        end
        if #producers == 0 then break end
    end

    for i = #removals, 1, -1 do
        table.remove(queue, removals[i])
    end
end

function producer.ProcessCreated(h)
    local odf = string.lower(utility.CleanString(GetOdf(h)))
    for proc, active in pairs(producer.Orders) do
        local job = active
        if type(active) == "table" and active.job then
            job = active.job
        end

        if IsValid(proc) and job and string.lower(job.odf) == odf then
            local dist = GetDistance(h, proc)
            if dist < 150 then
                producer.Orders[proc] = nil
                return true
            end
        end
    end
    return false
end

----------------------------------------------------------------------------------
-- INTEGRATED BZN PARSER & MISSION DATA
----------------------------------------------------------------------------------
local bzn = {}
local BinaryFieldType = { DATA_VOID = 0, DATA_ID = 1, DATA_CHAR = 2, DATA_BOOL = 3, DATA_SHORT = 4, DATA_LONG = 5, DATA_FLOAT = 6, DATA_VEC2D = 7, DATA_VEC3D = 8, DATA_MAT3DOLD = 9, DATA_PTR = 10 }

local function parseFloatLE(str, offset)
    local b1, b2, b3, b4 = string.byte(str, offset + 1, offset + 4)
    if not b4 then return 0 end
    local sign = bit.band(b4, 0x80) == 0x80 and 1 or 0
    local exponent = bit.lshift(bit.band(b4, 0x7F), 1) + bit.rshift(bit.band(b3, 0x80), 7)
    local mantissa = bit.lshift(bit.band(b3, 0x7F), 16) + bit.lshift(b2, 8) + b1
    if exponent == 0 then return 0 end
    if exponent == 255 then return mantissa == 0 and (sign == 1 and -math.huge or math.huge) or 0 / 0 end
    return ((-1) ^ sign) * (1 + mantissa / 2 ^ 23) * 2 ^ (exponent - 127)
end

local nullToken = {
    type = 0,
    data = "",
    GetString = function() return "" end,
    GetInt32 = function() return 0 end,
    GetBoolean = function() return false end,
    GetVector2D = function() return SetVector(0, 0, 0) end
}

local Tokenizer = {}
Tokenizer.__index = Tokenizer
function Tokenizer.new(data)
    return setmetatable({ data = data, pos = 1, version = 1000, type_size = 2, size_size = 2 }, Tokenizer)
end

function Tokenizer:ReadToken()
    if self.pos > #self.data then return nullToken end
    local type = string.byte(self.data, self.pos)
    self.pos = self.pos + self.type_size
    local size = string.byte(self.data, self.pos) + bit.lshift(string.byte(self.data, self.pos + 1), 8)
    self.pos = self.pos + self.size_size
    local value = self.data:sub(self.pos, self.pos + size - 1)
    self.pos = self.pos + size
    return {
        type = type,
        data = value,
        GetString = function(s) return s.data:gsub("%z.*", "") end,
        GetInt32 = function(s)
            local b1, b2, b3, b4 = string.byte(s.data, 1, 4); return (b1 or 0) + (b2 or 0) * 256 + (b3 or 0) * 65536 +
                (b4 or 0) * 16777216
        end,
        GetBoolean = function(s) return (string.byte(s.data, 1) or 0) ~= 0 end,
        GetVector2D = function(s, i)
            local off = (i or 0) * 8; return SetVector(parseFloatLE(s.data, off), 0, parseFloatLE(s.data, off + 4))
        end
    }
end

function bzn.Open(name)
    local filedata = UseItem(name)
    if not filedata then return nil end
    local reader = Tokenizer.new(filedata)
    local res = { AiPaths = {} }
    local tok = reader:ReadToken() -- version
    if not tok then return nil end
    res.version = tok:GetInt32(); reader.version = res.version
    if res.version > 1022 then
        reader:ReadToken(); tok = reader:ReadToken(); if tok then res.msn_filename = tok:GetString() end
    end
    reader:ReadToken()                                 -- seq_count
    if res.version >= 1016 then reader:ReadToken() end -- missionSave
    if res.version ~= 1001 then
        tok = reader:ReadToken(); if tok then res.TerrainName = tok:GetString() end
    end
    return res
end

local mission = {
    MapBaseType = { Deathmatch = "D", KingOfTheHill = "K", Strategy = "S", Single = "*" },
    ModTypes = { Multiplayer = "multiplayer", InstantAction = "instant_action", Campaign = "campaign", Mod = "mod" },
    Bzn = nil
}
function mission.TryLoadBZN()
    if not mission.Bzn then mission.Bzn = bzn.Open(GetMissionFilename()) end
end

-- Paths moved up


-- aiCore Logic
aiCore.Debug = false

-- Helper to strip circular references before serializing
function aiCore.StripCircular(data, seen)
    if type(data) ~= "table" then return data end
    seen = seen or {}
    if seen[data] then return nil end
    seen[data] = true

    local res = {}
    for k, v in pairs(data) do
        -- Skip keys known to contain circular references
        -- teamObj points from manager to team; team points to managers
        if k ~= "teamObj" then
            res[k] = aiCore.StripCircular(v, seen)
        end
    end
    return res
end

function aiCore.Save()
    local data = {
        teams = aiCore.ActiveTeams,
        globalDefense = aiCore.GlobalDefenseManagers,
        globalDepot = aiCore.GlobalDepotManagers,
        globalOffense = aiCore.GlobalOffenseManagers,
        producer = (producer and producer.Queue) or {} -- Save producer queue state
    }
    return aiCore.StripCircular(data)
end

function aiCore.NilToString(s)
    if s == nil then return "" end
    return tostring(s)
end

function aiCore.HasWeapon(h, slot, weapon)
    local w = utility.CleanString(GetWeaponClass(h, slot))
    if w == "" then return false end
    if weapon == nil then return true end
    if type(weapon) == "table" then
        for _, v in ipairs(weapon) do
            if string.find(string.lower(w), string.lower(v)) then return true end
        end
        return false
    end
    return string.find(string.lower(w), string.lower(weapon)) ~= nil
end

function aiCore.GetWeaponMask(h, search)
    if not IsValid(h) then return 0 end
    if search == nil then
        for i = 0, 4 do
            if aiCore.HasWeapon(h, i) then return 2 ^ i end
        end
        return 0
    end

    if type(search) == "string" then search = { search } end
    for _, s in ipairs(search) do
        for i = 0, 4 do
            if aiCore.HasWeapon(h, i, s) then
                return 2 ^ i
            end
        end
    end
    return 0
end

function aiCore.GetOdfWeaponMask(h)
    local odf = OpenODF(GetOdf(h))
    if not odf then return nil end
    local maskStr = GetODFString(odf, "GameObjectClass", "weaponMask", "")
    if maskStr == "" then return nil end

    -- ODF mask is binary string, e.g. "00001". Last char is slot 1 (mask 1).
    local mask = 0
    local len = #maskStr
    for i = 1, len do
        local char = maskStr:sub(len - i + 1, len - i + 1)
        if char == "1" then
            mask = mask + 2 ^ (i - 1)
        end
    end
    return (mask > 0) and mask or nil
end

-- Automatically adjusts the mass of a craft based on its classification.
function aiCore.ApplyDynamicMass(h)
    if not IsValid(h) or not IsCraft(h) then return end

    local cls = string.lower(utility.CleanString(GetClassLabel(h)))
    local mass = 1750 -- Baseline for vehicle mass is 1750 KG

    -- Special handling: Use ODF unitName for generic 'wingman' classes
    if string.find(cls, "wingman") then
        local odf = OpenODF(GetOdf(h))
        if odf then
            local unitName = string.lower(GetODFString(odf, "GameObjectClass", "unitName", ""))

            if string.find(unitName, "scout") or string.find(unitName, "fighter") then
                mass = 1200
            elseif string.find(unitName, "light tank") then
                mass = 1500
            elseif string.find(unitName, "tank") then -- Catch-all for "Tank", "Assault Tank", etc.
                mass = 1750
            elseif string.find(unitName, "rocket") or string.find(unitName, "missile") then
                mass = 1850
            elseif string.find(unitName, "bomber") then
                mass = 2000
            elseif string.find(unitName, "walker") then
                mass = 4000
            elseif string.find(unitName, "apc") then
                mass = 3000
            end
        end
    elseif string.find(cls, "walker") then
        mass = 4000
    elseif string.find(cls, "apc") then
        mass = 3000
    elseif string.find(cls, "howitzer") or string.find(cls, "artillery") then
        mass = 2200
    end

    if aiCore.Debug then
        print("aiCore: Dynamic Mass Applied -> " .. utility.CleanString(GetOdf(h)) .. " (" .. mass .. " KG)")
    end

    SetMass(h, mass)
end

function aiCore.Load(data)
    if not data then return end

    if data.teams then
        aiCore.ActiveTeams = data.teams
        aiCore.GlobalDefenseManagers = data.globalDefense or {}
        aiCore.GlobalDepotManagers = data.globalDepot or {}
        aiCore.GlobalOffenseManagers = data.globalOffense or {}
        if data.producer and producer then
            producer.Queue = data.producer
        end
    else
        aiCore.ActiveTeams = data
        aiCore.GlobalDefenseManagers = {}
        aiCore.GlobalDepotManagers = {}
        aiCore.GlobalOffenseManagers = {}
    end

    -- Restore Metatables
    for _, team in pairs(aiCore.ActiveTeams) do
        setmetatable(team, aiCore.Team)
        if team.recyclerMgr then
            setmetatable(team.recyclerMgr, aiCore.FactoryManager); team.recyclerMgr.teamObj = team
        end
        if team.factoryMgr then
            setmetatable(team.factoryMgr, aiCore.FactoryManager); team.factoryMgr.teamObj = team
        end
        if team.constructorMgr then
            setmetatable(team.constructorMgr, aiCore.ConstructorManager); team.constructorMgr.teamObj = team
        end

        -- Restore Phase 1 Managers
        if team.weaponMgr then
            setmetatable(team.weaponMgr, aiCore.WeaponManager); team.weaponMgr.teamObj = team
        end
        if team.cloakMgr then
            setmetatable(team.cloakMgr, aiCore.CloakingManager); team.cloakMgr.teamObj = team
        end
        if team.howitzerMgr then
            setmetatable(team.howitzerMgr, aiCore.HowitzerManager); team.howitzerMgr.teamObj = team
        end
        if team.minelayerMgr then
            setmetatable(team.minelayerMgr, aiCore.MinelayerManager); team.minelayerMgr.teamObj = team
        end

        -- Restore Phase 2 Managers
        if team.apcMgr then
            setmetatable(team.apcMgr, aiCore.APCManager); team.apcMgr.teamObj = team
        end
        if team.turretMgr then
            setmetatable(team.turretMgr, aiCore.TurretManager); team.turretMgr.teamObj = team
        end
        if team.guardMgr then
            setmetatable(team.guardMgr, aiCore.GuardManager); team.guardMgr.teamObj = team
        end
        if team.wingmanMgr then
            setmetatable(team.wingmanMgr, aiCore.WingmanManager); team.wingmanMgr.teamObj = team
        end
        if team.defenseMgr then
            setmetatable(team.defenseMgr, aiCore.DefenseManager); team.defenseMgr.teamObj = team
        end
        if team.depotMgr then
            setmetatable(team.depotMgr, aiCore.DepotManager); team.depotMgr.teamObj = team
        end

        -- Restore Squad Metatables
        if team.squads then
            for _, squad in ipairs(team.squads) do
                setmetatable(squad, aiCore.Squad)
            end
        end
    end

    -- Restore Global Manager Metatables
    for _, mgr in pairs(aiCore.GlobalDefenseManagers) do
        setmetatable(mgr, aiCore.DefenseManager)
    end
    for _, mgr in pairs(aiCore.GlobalDepotManagers) do
        setmetatable(mgr, aiCore.DepotManager)
    end
    for _, mgr in pairs(aiCore.GlobalOffenseManagers) do
        setmetatable(mgr, aiCore.OffenseRetaliationManager)
    end

    -- RE-APPLY DYNAMIC MASS (Persistence Workaround)
    -- This ensures that mass is restored after a save-load cycle.
    for h in AllCraft() do
        aiCore.ApplyDynamicMass(h)
    end
end

----------------------------------------------------------------------------------
-- CONFIGURATION & CONSTANTS
----------------------------------------------------------------------------------

aiCore.Factions = { NSDF = 1, CCA = 2, CRA = 3, BDOG = 4 }
aiCore.FactionNames = { [1] = "NSDF", [2] = "CCA", [3] = "CRA", [4] = "BDOG" }

-- Smart Power Detection
function aiCore.DetectWorldPower()
    if aiCore.WorldPowerKey then return aiCore.WorldPowerKey end

    -- Try to leverage mission module if Bzn is loaded
    mission.TryLoadBZN()
    if mission.Bzn and mission.Bzn.TerrainName then
        local terrain = string.lower(mission.Bzn.TerrainName)

        -- Lightning Power: High-energy, chaotic, or electromagnetic worlds
        if string.find(terrain, "venus") or string.find(terrain, "ganymede") or string.find(terrain, "elysium") then
            aiCore.WorldPowerKey = "lPower"

            -- Wind Power: Atmospheric pressure and high-velocity gas worlds
        elseif string.find(terrain, "mars") or string.find(terrain, "titan") or string.find(terrain, "achilles") then
            aiCore.WorldPowerKey = "wPower"

            -- Solar Power: Default for low-atmosphere/high-visibility (Moon, Io, Europa)
        else
            aiCore.WorldPowerKey = "sPower"
        end

        if aiCore.Debug then
            print("aiCore: Smart Power Detection (BZN Metadata) -> " .. aiCore.WorldPowerKey)
        end
        return aiCore.WorldPowerKey
    end

    local trnFile = GetMapTRNFilename()
    if not trnFile or trnFile == "" then
        aiCore.WorldPowerKey = "sPower" -- Default
        return aiCore.WorldPowerKey
    end

    local odf = OpenODF(trnFile)
    if not odf then
        aiCore.WorldPowerKey = "sPower"
        return aiCore.WorldPowerKey
    end

    local palette = GetODFString(odf, "Color", "Palette", "")
    if palette == "" then
        -- Fallback: try filename guessing if palette is missing
        local lowerTrn = string.lower(trnFile)
        if string.find(lowerTrn, "venus") then
            palette = "venus"
        elseif string.find(lowerTrn, "mars") then
            palette = "mars"
        elseif string.find(lowerTrn, "titan") then
            palette = "titan"
        else
            palette = "moon"
        end
    end
    palette = string.lower(palette)

    -- Map Palette/World to Power Type
    -- Solar: Moon, Io, Europa, Ganymede
    -- Lightning: Venus
    -- Wind: Mars, Titan, Achilles, Elysium

    local powerKey = "sPower" -- Default to Solar
    if string.find(palette, "venus") then
        powerKey = "lPower"
    elseif string.find(palette, "mars") or string.find(palette, "titan") or string.find(palette, "achilles") or string.find(palette, "elysium") then
        powerKey = "wPower"
    end

    aiCore.WorldPowerKey = powerKey
    if aiCore.Debug then print("aiCore: Smart Power Detection based on " .. palette .. " -> " .. aiCore.WorldPowerKey) end
    return aiCore.WorldPowerKey
end

-- Directional Building Support (from aiBuildOS)
-- Table of directional vectors for oriented building placement
aiCore.VecFacing = {
    N = SetVector(0, 0, 1),
    NE = SetVector(0.70, 0, 0.70),
    E = SetVector(1, 0, 0),
    SE = SetVector(0.70, 0, -0.70),
    S = SetVector(0, 0, -1),
    SW = SetVector(-0.70, 0, -0.70),
    W = SetVector(-1, 0, 0),
    NW = SetVector(-0.70, 0, 0.70)
}

-- Convert position + facing vector/string into directional matrix for BuildAt
function aiCore.BuildDirectionalMatrix(position, facing)
    if type(facing) == "string" then
        facing = aiCore.VecFacing[facing] or aiCore.VecFacing.N
    end
    return BuildDirectionalMatrix(position, facing)
end

-- Unit ODF Tables (Consolidated)
aiCore.Units = {}

aiCore.Units[aiCore.Factions.NSDF] = {
    -- Buildings
    recycler = "avrecy",
    factory = "avmuf",
    armory = "avslf",
    constructor = "avcnst",
    sPower = "abspow",
    lPower = "ablpow",
    wPower = "abwpow",
    gunTower = "abtowe",
    gunTower2 = "abtowe",
    silo = "absilo",
    supply = "absupp",
    hangar = "abhang",
    barracks = "abbarr",
    commTower = "abcomm",
    hq = "abhqcp",
    -- Units
    scavenger = "avscav",
    turret = "avturr",
    scout = "avfigh",
    tank = "avtank",
    lighttank = "avltnk",
    tug = "avhaul",
    howitzer = "avartl",
    minelayer = "avmine",
    rockettank = "avrckt",
    apc = "avapc",
    bomber = "avhraz",
    walker = "avwalk",
    unique = "avltmp",
    repair = "aprepa",
    ammo = "apammo",
    pilot = "aspilo",
    soldier = "assold",
    mine = "proxmine",
    wrecker = "apwrck",
    mortar = "gmortar",
    artillery = "ghartill"
}

aiCore.Units[aiCore.Factions.CCA] = {
    recycler = "svrecy",
    factory = "svmuf",
    armory = "svslf",
    constructor = "svcnst",
    sPower = "sbspow",
    lPower = "sblpow",
    wPower = "sbwpow",
    gunTower = "sbtowe",
    gunTower2 = "sbtowe",
    silo = "sbsilo",
    supply = "sbsupp",
    hangar = "sbhang",
    barracks = "sbbarr",
    commTower = "sbcomm",
    hq = "sbhqcp",
    scavenger = "svscav",
    turret = "svturr",
    scout = "svfigh",
    tank = "svtank",
    lighttank = "svltnk",
    tug = "svhaul",
    howitzer = "svartl",
    minelayer = "svmine",
    rockettank = "svrckt",
    apc = "svapc",
    bomber = "svhraz",
    walker = "svwalk",
    unique = "svsav",
    repair = "aprepa",
    ammo = "apammo",
    pilot = "sspilo",
    soldier = "sssold",
    mine = "proxmine",
    wrecker = "apwrck",
    mortar = "gmortar",
    artillery = "ghartill"
}

aiCore.Units[aiCore.Factions.CRA] = {
    recycler = "cvrecy",
    factory = "cvmuf",
    armory = "cvslf",
    constructor = "cvcnst",
    sPower = "cbspow",
    lPower = "cblpow",
    wPower = "cbwpow",
    gunTower = "cbtowe",
    gunTower2 = "cblasr",
    silo = "cbsilo",
    supply = "cbmbld",
    hangar = "cbhang",
    barracks = "cbbarr",
    commTower = "cbcomm",
    hq = "cbhqcp",
    scavenger = "cvscav",
    turret = "cvturr",
    scout = "cvfigh",
    tank = "cvtnk",
    lighttank = "cvltnk",
    tug = "cvhaul",
    howitzer = "cvartl",
    minelayer = "cvmine",
    rockettank = "cvrckt",
    apc = "cvapc",
    bomber = "cvhraz",
    walker = "cvwalk",
    unique = "cvhtnk",
    repair = "aprepa",
    ammo = "apammo",
    pilot = "cspilo",
    soldier = "cssold",
    mine = "proxmine",
    wrecker = "apwrck",
    mortar = "gmortar",
    artillery = "ghartill"
}

aiCore.Units[aiCore.Factions.BDOG] = {
    recycler = "bvrecy",
    factory = "bvmuf",
    armory = "bvslf",
    constructor = "bvcnst",
    sPower = "bbspow",
    lPower = "bblpow",
    wPower = "bbwpow",
    gunTower = "bbtowe",
    gunTower2 = "bbtowe",
    silo = "bbsilo",
    supply = "bbmbld",
    hangar = "bbhang",
    barracks = "bbbarr",
    commTower = "bbcomm",
    hq = "bbhqcp",
    scavenger = "bvscav",
    turret = "bvturr",
    scout = "bvfigh",
    tank = "bvtank",
    lighttank = "bvltnk",
    tug = "bvhaul",
    howitzer = "bvartl",
    minelayer = "bvmine",
    rockettank = "bvrckt",
    apc = "bvapc",
    bomber = "bvhraz",
    walker = "bvwalk",
    unique = "bvrdev",
    repair = "aprepa",
    ammo = "apammo",
    pilot = "bspilo",
    soldier = "bssold",
    mine = "proxmine",
    wrecker = "apwrck",
    mortar = "gmortar",
    artillery = "ghartill"
}

-- Tactical AIP Strategies (from aiSpecial)
-- These lists define unit composition priorities for different strategies
aiCore.Strategies = {
    Balanced = {
        Recycler = { "turret", "turret", "turret", "turret", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger" },
        Factory = { "howitzer", "unique", "unique", "rockettank", "rockettank", "bomber", "bomber", "bomber", "apc", "apc", "lighttank", "lighttank", "lighttank", "scout", "scout", "scout", "tank", "tank", "tank", "tank", "tank", "tank", "minelayer" }
    },
    APC_Heavy = {
        Recycler = { "scout", "scout", "turret", "turret", "turret", "turret", "turret", "turret", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger" },
        Factory = { "walker", "lighttank", "scout", "scout", "scout", "tank", "tank", "tank", "apc", "apc", "apc", "apc", "apc", "apc", "apc", "apc", "apc", "apc" }
    },
    Minelayer_Heavy = {
        Recycler = { "turret", "turret", "turret", "turret", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger" },
        Factory = { "minelayer", "minelayer", "minelayer", "minelayer", "minelayer", "tank", "tank", "tank", "lighttank", "lighttank", "lighttank", "scout", "scout" }
    },
    Tank_Heavy = {
        Recycler = { "scout", "turret", "turret", "turret", "turret", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger" },
        Factory = { "rockettank", "unique", "lighttank", "tank", "tank", "tank", "tank", "tank", "tank", "tank", "tank", "tank" }
    },
    Light_Force = {
        Recycler = { "scout", "scout", "scout", "scout", "scout", "turret", "turret", "turret", "turret", "scout", "scout", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger" },
        Factory = { "rockettank", "rockettank", "rockettank", "rockettank", "scout", "scout", "scout", "scout", "scout", "lighttank", "minelayer", "lighttank", "lighttank", "lighttank", "lighttank", "lighttank", "tank" }
    },
    Howitzer_Heavy = {
        Recycler = { "scout", "turret", "turret", "turret", "turret", "scout", "scout", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger" },
        Factory = { "rockettank", "rockettank", "rockettank", "lighttank", "lighttank", "lighttank", "scout", "scout", "scout", "tank", "minelayer", "tank", "tank", "howitzer", "howitzer", "howitzer", "howitzer", "howitzer", "howitzer" }
    },
    Bomber_Heavy = {
        Recycler = { "scout", "turret", "turret", "turret", "turret", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger" },
        Factory = { "unique", "apc", "lighttank", "scout", "scout", "scout", "tank", "tank", "tank", "tank", "bomber", "bomber", "bomber", "bomber", "bomber", "bomber", "bomber", "bomber" }
    },
    Rocket_Heavy = {
        Recycler = { "scout", "scout", "turret", "turret", "turret", "turret", "turret", "turret", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger" },
        Factory = { "apc", "apc", "tank", "tank", "lighttank", "lighttank", "lighttank", "lighttank", "lighttank", "scout", "scout", "bomber", "bomber", "bomber", "bomber", "rockettank", "rockettank", "rockettank", "rockettank", "rockettank", "rockettank", "rockettank", "rockettank" }
    },
    Anti_APC_Spam = {
        Recycler = { "turret", "turret", "turret", "turret", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger" },
        Factory = { "minelayer", "minelayer", "minelayer", "minelayer", "apc", "apc", "apc", "apc", "bomber", "bomber", "bomber", "bomber", "tank", "tank", "tank" }
    },
    Siege_Counter = {
        Recycler = { "scout", "scout", "turret", "turret", "turret", "turret", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger" },
        Factory = { "howitzer", "howitzer", "howitzer", "apc", "apc", "apc", "bomber", "bomber", "bomber", "tank", "tank", "tank", "lighttank", "lighttank" }
    },
    Howitzer_Counter = {
        Recycler = { "scout", "scout", "scout", "scout", "turret", "turret", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger" },
        Factory = { "scout", "scout", "scout", "scout", "tank", "tank", "tank", "tank", "bomber", "bomber", "bomber", "bomber", "lighttank", "lighttank" }
    }
}

----------------------------------------------------------------------------------
-- WEAPON MANAGER (from aiSpecial)
-- Manages advanced weapon systems: thumpers, field projectors, mortars, double weapons
----------------------------------------------------------------------------------

aiCore.WeaponManager = {}
aiCore.WeaponManager.__index = aiCore.WeaponManager

function aiCore.WeaponManager.new(teamNum)
    local self = setmetatable({}, aiCore.WeaponManager)
    self.teamNum = teamNum

    -- Thumper users (pulse weapon)
    self.thumperUsers = {}
    self.thumperActive = {}
    self.thumperPeriod = 15.0
    self.thumperDuration = 0.5
    self.thumperRate = 30
    self.thumperWeapons = { "gquake", "gthumper", "quake", "thump" }

    -- Field projector users
    self.fieldUsers = {}
    self.fieldActive = {}
    self.fieldPeriod = 40.0
    self.fieldDuration = 10.0
    self.fieldRate = 10
    self.fieldWeapons = { "gphantom", "gredfld", "gsitecam" }

    -- Mortar users
    self.mortarUsers = {}
    self.mortarActive = {}
    self.mortarPeriod = 15.0
    self.mortarDuration = 5.0
    self.mortarRate = 50
    self.mortarWeapons = { "gmortar", "gmdmgun", "gsplint" }

    -- Mine layers (weapon-based, not vehicle minelayers)
    self.mineUsers = {}
    self.mineActive = {}
    self.minePeriod = 25.0
    self.mineDuration = 0.5
    self.mineRate = 20
    self.mineWeapons = { "gproxmin", "gmitsmin", "gmcurmin", "gflare", "gnavdrop" }

    -- Double weapon users
    self.doubleUsers = {}
    self.doubleRate = 20
    self.doubleMaskCheckAt = {}
    self.doubleMaskInterval = 0.9

    -- Missile users with non-missile fallback
    self.missileUsers = {}
    self.missileClampState = {}
    self.missileUpdateAt = 0.0
    self.missileUpdatePeriod = 0.2
    self.missileKillBuffer = 1.1
    self.missileRetargetRadius = 200.0

    -- Retaliation sweeps can touch every combat unit, so keep them off the per-frame path.
    self.retaliationUpdateAt = 0.0
    self.retaliationUpdatePeriod = 0.25

    -- Timers
    self.thumperTimer = 0.0
    self.fieldTimer = 0.0
    self.mortarTimer = 0.0
    self.mineTimer = 0.0

    return self
end

function aiCore.WeaponManager:AddObject(h)
    if not IsValid(h) or GetTeamNum(h) ~= self.teamNum then return end

    -- Check for thumper weapons
    local thumperMask = aiCore.GetWeaponMask(h, self.thumperWeapons)
    if thumperMask > 0 then
        table.insert(self.thumperUsers, { handle = h, mask = thumperMask, timer = 0.0 })
        if aiCore.Debug then print("Team " .. self.teamNum .. " added thumper user: " .. GetOdf(h)) end
    end

    -- Check for field weapons
    for _, weapon in ipairs(self.fieldWeapons) do
        local mask = aiCore.GetWeaponMask(h, weapon)
        if mask > 0 then
            table.insert(self.fieldUsers, { handle = h, mask = mask, timer = 0.0 })
            if aiCore.Debug then print("Team " .. self.teamNum .. " added field user: " .. GetOdf(h)) end
            break
        end
    end

    -- Check for mortar weapons
    for _, weapon in ipairs(self.mortarWeapons) do
        local mask = aiCore.GetWeaponMask(h, weapon)
        if mask > 0 then
            table.insert(self.mortarUsers, { handle = h, mask = mask, timer = 0.0 })
            if aiCore.Debug then print("Team " .. self.teamNum .. " added mortar user: " .. GetOdf(h)) end
            break
        end
    end

    -- Check for mine weapons
    for _, weapon in ipairs(self.mineWeapons) do
        local mask = aiCore.GetWeaponMask(h, weapon)
        if mask > 0 then
            table.insert(self.mineUsers, { handle = h, mask = mask, timer = 0.0 })
            if aiCore.Debug then print("Team " .. self.teamNum .. " added mine user: " .. GetOdf(h)) end
            break
        end
    end

    -- Check for double weapons (hardpoints >= 2)
    local weaponCount = 0
    for i = 0, 4 do
        if utility.CleanString(GetWeaponClass(h, i)) ~= "" then
            weaponCount = weaponCount + 1
        end
    end
    if weaponCount >= 2 then
        table.insert(self.doubleUsers, h)
        if aiCore.Debug then print("Team " .. self.teamNum .. " added double weapon user: " .. GetOdf(h)) end
    end

    local missileSlots = {}
    local missileMask = 0
    local supportMask = 0
    local unresolvedMissile = false
    local maxMissileDamage = 0.0
    for i = 0, 4 do
        local weapon = string.lower(utility.CleanString(GetWeaponClass(h, i)))
        if weapon ~= "" then
            local bit = 2 ^ i
            local hardpoint = GetWeaponHardpointCode(h, i) or ""
            local isSpecialSlot = string.sub(hardpoint, 1, 2) == "gs"
            if aiCore.GetMissileThreatType(weapon) then
                local profile = GetMissileWeaponProfile(weapon)
                if profile and profile.damage and profile.damage > 0.0 then
                    if profile.damage > maxMissileDamage then
                        maxMissileDamage = profile.damage
                    end
                    table.insert(missileSlots, {
                        slot = i,
                        mask = bit,
                        weapon = weapon,
                        damage = profile.damage,
                    })
                    missileMask = missileMask + bit
                else
                    unresolvedMissile = true
                end
            elseif not isSpecialSlot then
                supportMask = supportMask + bit
            end
        end
    end

    if not unresolvedMissile and #missileSlots > 0 then
        table.sort(missileSlots, function(a, b)
            if a.damage == b.damage then
                return a.slot < b.slot
            end
            return a.damage < b.damage
        end)

        table.insert(self.missileUsers, {
            handle = h,
            missileSlots = missileSlots,
            missileMask = missileMask,
            supportMask = supportMask,
            missileOnly = supportMask <= 0,
            missileMaxDamage = maxMissileDamage,
        })
        if aiCore.Debug then
            print("Team " .. self.teamNum .. " added missile efficiency user: " .. GetOdf(h))
        end
    end
end

function aiCore.WeaponManager:Update()
    local dt = GetTime() - (self.lastUpdate or 0)
    self.lastUpdate = GetTime()

    -- Update thumper users
    self:UpdateThumpers(dt)

    -- Update field users
    self:UpdateFields(dt)

    -- Update mortar users
    self:UpdateMortars(dt)

    -- Update mine users
    self:UpdateMines(dt)

    -- Update double weapon users
    self:UpdateDoubleWeapons(dt)

    -- Clamp missile launchers after the normal mask selection pass.
    self:UpdateMissileEfficiency(dt)

    -- Targeted Retaliation (New)
    self:UpdateRetaliation(dt)
end

function aiCore.WeaponManager:UpdateRetaliation(dt)
    if not self.teamObj or not self.teamObj.combatUnits then return end
    local now = GetTime()
    if now < (self.retaliationUpdateAt or 0.0) then return end
    self.retaliationUpdateAt = now + (self.retaliationUpdatePeriod or 0.25)

    -- Check for attackers and switch weapons reactively
    for _, u in ipairs(self.teamObj.combatUnits) do
        if IsValid(u) and IsAlive(u) then
            local attacker = GetWhoShotMe(u)
            if IsValid(attacker) and IsAlive(attacker) and (now - GetLastEnemyShot(u)) < 5.0 then
                local cls = string.lower(utility.CleanString(GetClassLabel(attacker)))
                local isPlayerHandle = (u == GetPlayerHandle())

                if aiCore.IsMissileThreat(attacker) then
                    local threatType = aiCore.GetMissileThreatTypeFromHandle(attacker) or "tracking"
                    aiCore.TryUseMissileCountermeasure(u, threatType, GetDistance(u, attacker))
                end

                -- Person -> Mortar
                if cls == utility.ClassLabel.PERSON and not isPlayerHandle then
                    local popgunMask = aiCore.GetWeaponMask(u, { "popgun" })
                    local blastMask = aiCore.GetWeaponMask(u, { "mdmgun", "mortar", "splint", "acidcl", "thrower", "arblst", "rktbomb" })
                    local mineMask = aiCore.GetWeaponMask(u, { "proxmin", "mitsmin", "mcurmin" })
                    if popgunMask > 0 then
                        SetWeaponMask(u, popgunMask)
                        FireWeaponMask(u, popgunMask)
                        if aiCore.Debug then
                            print("WeaponManager: Using popgun against infantry/sniper (" .. GetOdf(u) .. ")")
                        end
                    elseif blastMask > 0 then
                        SetWeaponMask(u, blastMask)
                        FireWeaponMask(u, blastMask)
                        if aiCore.Debug then
                            print("WeaponManager: Retaliating against Person with explosive weapon (" ..
                                GetOdf(u) .. ")")
                        end
                    elseif mineMask > 0 then
                        SetWeaponMask(u, mineMask)
                        FireWeaponMask(u, mineMask)
                        if aiCore.Debug then
                            print("WeaponManager: Retaliating against Person with mine fallback (" .. GetOdf(u) .. ")")
                        end
                    end

                    -- Walker -> Thumper
                elseif cls == utility.ClassLabel.WALKER and not isPlayerHandle then
                    local thumperMask = aiCore.GetWeaponMask(u, self.thumperWeapons)
                    if thumperMask > 0 then
                        SetWeaponMask(u, thumperMask)
                        FireWeaponMask(u, thumperMask)
                        if aiCore.Debug then
                            print("WeaponManager: Disorienting Walker with Thumper (" ..
                                GetOdf(u) .. ")")
                        end
                    end
                end
            end
        end
    end
end

function aiCore.WeaponManager:UpdateThumpers(dt)
    for i = #self.thumperUsers, 1, -1 do
        local user = self.thumperUsers[i]
        if not IsValid(user.handle) then
            table.remove(self.thumperUsers, i)
        else
            user.timer = user.timer + dt
            local isPlayerHandle = (user.handle == GetPlayerHandle())
            local shouldPulse = false
            local target = GetCurrentWho(user.handle)
            if IsValid(target) and IsAlive(target) then
                local targetCls = string.lower(utility.CleanString(GetClassLabel(target)))
                if string.find(targetCls, utility.ClassLabel.WALKER) then
                    shouldPulse = true
                end
            end
            if not shouldPulse then
                local nearest = GetNearestEnemy(user.handle)
                if IsValid(nearest) and GetDistance(user.handle, nearest) <= 200.0 then
                    local nearestCls = string.lower(utility.CleanString(GetClassLabel(nearest)))
                    shouldPulse = string.find(nearestCls, utility.ClassLabel.WALKER) ~= nil or math.random(100) < self.thumperRate
                end
            end

            -- Pulse cycle: fire for duration, wait for period
            local cycleTime = user.timer % self.thumperPeriod
            if cycleTime < self.thumperDuration then
                -- Fire thumper
                if not isPlayerHandle and shouldPulse then
                    SetWeaponMask(user.handle, user.mask)
                    FireWeaponMask(user.handle, user.mask)
                end
            else
                -- Reset mask when outside firing window
                if self.teamObj then
                    self.teamObj:ResetWeaponMask(user.handle)
                end
            end
        end
    end
end

function aiCore.WeaponManager:UpdateFields(dt)
    for i = #self.fieldUsers, 1, -1 do
        local user = self.fieldUsers[i]
        if not IsValid(user.handle) then
            table.remove(self.fieldUsers, i)
        else
            user.timer = user.timer + dt

            -- Field deployment: deploy for duration, wait for period
            local cycleTime = user.timer % self.fieldPeriod
            if cycleTime < self.fieldDuration then
                if user.handle ~= GetPlayerHandle() and math.random(100) < self.fieldRate then
                    FireWeaponMask(user.handle, user.mask)
                end
            else
                -- Reset mask when outside firing window
                if self.teamObj then
                    self.teamObj:ResetWeaponMask(user.handle)
                end
            end
        end
    end
end

function aiCore.WeaponManager:UpdateMortars(dt)
    for i = #self.mortarUsers, 1, -1 do
        local user = self.mortarUsers[i]
        if not IsValid(user.handle) then
            table.remove(self.mortarUsers, i)
        else
            user.timer = user.timer + dt

            -- Mortar firing: fire for duration, wait for period
            local cycleTime = user.timer % self.mortarPeriod
            if cycleTime < self.mortarDuration then
                if user.handle ~= GetPlayerHandle() and math.random(100) < self.mortarRate then
                    FireWeaponMask(user.handle, user.mask)
                end
            else
                -- Reset mask when outside firing window
                if self.teamObj then
                    self.teamObj:ResetWeaponMask(user.handle)
                end
            end
        end
    end
end

function aiCore.WeaponManager:UpdateMines(dt)
    for i = #self.mineUsers, 1, -1 do
        local user = self.mineUsers[i]
        if not IsValid(user.handle) then
            table.remove(self.mineUsers, i)
        else
            user.timer = user.timer + dt

            -- Mine deployment: deploy for duration, wait for period
            local cycleTime = user.timer % self.minePeriod
            if cycleTime < self.mineDuration then
                if user.handle ~= GetPlayerHandle() and math.random(100) < self.mineRate then
                    FireWeaponMask(user.handle, user.mask)
                end
            else
                -- Reset mask when outside firing window
                if self.teamObj then
                    self.teamObj:ResetWeaponMask(user.handle)
                end
            end
        end
    end
end

function aiCore.WeaponManager:UpdateDoubleWeapons(dt)
    -- Cycle through double weapon users and apply masks
    local now = GetTime()
    for i = #self.doubleUsers, 1, -1 do
        local h = self.doubleUsers[i]
        if not IsValid(h) then
            table.remove(self.doubleUsers, i)
            self.doubleMaskCheckAt[h] = nil
        else
            if self.teamObj and now >= (self.doubleMaskCheckAt[h] or 0.0) then
                self.doubleMaskCheckAt[h] = now + (self.doubleMaskInterval or 0.9) + math.random() * 0.35
                self.teamObj:SetDoubleWeaponMask(h, self.doubleRate)
            end
        end
    end
end

----------------------------------------------------------------------------------
-- CLOAKING MANAGER (from aiSpecial)
-- Auto-cloak and coward mode for cloak-capable units
----------------------------------------------------------------------------------

aiCore.CloakingManager = {}
aiCore.CloakingManager.__index = aiCore.CloakingManager

-- Legacy fallback list for mods/ODFs that do not expose CraftClass.cloakAllowed.
aiCore.CloakCapableODFs = {
    "cvfigh", "cvtnk", "cvhraz", "cvhtnk", "cvltnk", "cvrckt", "cvwalk"
}

function aiCore.CloakingManager.new(teamNum)
    local self = setmetatable({}, aiCore.CloakingManager)
    self.teamNum = teamNum
    self.cloakers = {}
    self.cowardMode = true          -- Cloak when damaged
    self.autoCloakEnabled = true    -- Auto-cloak when not in combat
    self.cloakHealthThreshold = 0.5 -- Cloak below 50% health
    self.pulseTimer = 0.0
    self.pulsePeriod = 3.0
    return self
end

function aiCore.CloakingManager:AddObject(h)
    if not IsValid(h) or GetTeamNum(h) ~= self.teamNum then return end

    for _, existing in ipairs(self.cloakers) do
        if existing == h then return end
    end

    local odfName = string.lower(utility.CleanString(GetOdf(h)))
    local canCloak = false
    local odf = OpenODF(odfName)
    if odf then
        canCloak = GetODFBool(odf, "CraftClass", "cloakAllowed", false)
        if not canCloak then
            local rawFlag = string.lower(utility.CleanString(GetODFString(odf, "CraftClass", "cloakAllowed", "false")))
            canCloak = (rawFlag == "true" or rawFlag == "1" or rawFlag == "yes")
        end
    end

    if not canCloak then
        for _, cloakOdf in ipairs(aiCore.CloakCapableODFs) do
            if odfName == cloakOdf then
                canCloak = true
                break
            end
        end
    end

    if canCloak then
        table.insert(self.cloakers, h)
        if aiCore.Debug then print("Team " .. self.teamNum .. " added cloaker: " .. GetOdf(h)) end
    end
end

function aiCore.CloakingManager:Update()
    if not self.autoCloakEnabled then return end

    self.pulseTimer = self.pulseTimer + GetTimeStep()
    if self.pulseTimer < self.pulsePeriod then return end
    self.pulseTimer = 0.0

    for i = #self.cloakers, 1, -1 do
        local h = self.cloakers[i]
        if not IsValid(h) then
            table.remove(self.cloakers, i)
        else
            local health = GetCurHealth(h) / GetMaxHealth(h)
            local cmd = GetCurrentCommand(h)
            local inCombat = (cmd == AiCommand.ATTACK)
            local isCloaked = IsCloaked(h)

            -- Coward mode: cloak when damaged
            if self.cowardMode and health < self.cloakHealthThreshold and not isCloaked then
                SetCloaked(h)
                if aiCore.Debug then print("Team " .. self.teamNum .. " cloaking damaged unit: " .. GetOdf(h)) end
            end

            -- Auto-cloak when not in combat
            if not inCombat and not isCloaked and health > self.cloakHealthThreshold then
                SetCloaked(h)
            end

            -- Uncloak when in combat (let AI handle it)
            if inCombat and isCloaked then
                SetDecloaked(h)
            end
        end
    end
end

----------------------------------------------------------------------------------
-- HOWITZER MANAGER (from aiSpecial)
-- Squadron-based artillery coordination
----------------------------------------------------------------------------------

aiCore.HowitzerManager = {}
aiCore.HowitzerManager.__index = aiCore.HowitzerManager

function aiCore.HowitzerManager.new(teamNum)
    local self = setmetatable({}, aiCore.HowitzerManager)
    self.teamNum = teamNum
    self.howitzers = {}
    self.squads = {} -- Organized squads
    self.squadSize = 3
    self.orderPeriod = 30.0
    self.orderTimer = 0.0
    self.playerAttackRange = 480.0
    self.playerStandoffRange = 450.0
    self.playerOrderState = {}
    return self
end

function aiCore.HowitzerManager:AddObject(h)
    if not IsValid(h) or GetTeamNum(h) ~= self.teamNum then return end

    local cls = aiCore.NilToString(GetClassLabel(h))
    if string.find(cls, utility.ClassLabel.HOWITZER) or string.find(cls, "artillery") then
        table.insert(self.howitzers, h)
        if aiCore.Debug then print("Team " .. self.teamNum .. " added howitzer: " .. GetOdf(h)) end
    end
end

function aiCore.HowitzerManager:Update()
    -- Remove invalid howitzers
    for i = #self.howitzers, 1, -1 do
        if not IsValid(self.howitzers[i]) then
            self.playerOrderState[self.howitzers[i]] = nil
            table.remove(self.howitzers, i)
        end
    end

    if self.teamNum == 1 then
        self:UpdatePlayerHowitzerOrders()
    end

    -- Organize into squads
    if #self.howitzers >= self.squadSize then
        self:OrganizeSquads()
    end

    -- Update squad orders periodically
    self.orderTimer = self.orderTimer + GetTimeStep()
    if self.orderTimer >= self.orderPeriod then
        self.orderTimer = 0.0
        self:UpdateSquadOrders()
    end
end

function aiCore.HowitzerManager:UpdatePlayerHowitzerOrders()
    for _, h in ipairs(self.howitzers) do
        if IsValid(h) and IsAlive(h) then
            local range = GetCurrentWeaponRangeMeters(h) or self.playerAttackRange or 480.0
            local standoff = math.max(80.0, math.min(self.playerStandoffRange or 450.0, range - 30.0))
            local state = self.playerOrderState[h] or {}
            local cmd = GetCurrentCommand(h)
            local currentTarget = GetCurrentWho(h)

            if cmd == AiCommand.ATTACK and IsValid(currentTarget) and IsAlive(currentTarget) and not IsAlly(h, currentTarget) then
                state.target = currentTarget
            elseif cmd == AiCommand.NONE then
                local movePos = state.movePos
                if not movePos or Length(GetPosition(h) - movePos) > 60.0 then
                    state.target = nil
                    state.movePos = nil
                end
            elseif cmd ~= AiCommand.GO then
                state.target = nil
                state.movePos = nil
            end

            local target = state.target
            if IsValid(target) and IsAlive(target) and not IsAlly(h, target) then
                local dist = GetDistance(h, target)
                if dist > range then
                    local targetPos = GetPosition(target)
                    local unitPos = GetPosition(h)
                    local dir = Normalize(unitPos - targetPos)
                    if dir.x == 0 and dir.y == 0 and dir.z == 0 then
                        dir = SetVector(1, 0, 0)
                    end

                    local movePos = targetPos + (dir * standoff)
                    local groundY = GetTerrainHeight(movePos.x, movePos.z)
                    movePos.y = math.max(groundY + 2.0, movePos.y)

                    state.target = target
                    state.movePos = movePos
                    self.playerOrderState[h] = state

                    aiCore.TrySetCommand(h, AiCommand.GO, GetCommandableAttackPriority(), nil, movePos, nil, nil,
                        { minInterval = 0.35 })
                else
                    if cmd ~= AiCommand.ATTACK or currentTarget ~= target then
                        aiCore.TryAttack(h, target, GetCommandableAttackPriority(),
                            { minInterval = 0.35, overrideProtected = true })
                    end
                    state.target = nil
                    state.movePos = nil
                    self.playerOrderState[h] = state
                end
            else
                self.playerOrderState[h] = nil
            end
        else
            self.playerOrderState[h] = nil
        end
    end
end

function aiCore.HowitzerManager:OrganizeSquads()
    self.squads = {}
    local squadIndex = 1
    local currentSquad = {}

    for i, h in ipairs(self.howitzers) do
        table.insert(currentSquad, h)
        if #currentSquad >= self.squadSize then
            self.squads[squadIndex] = currentSquad
            squadIndex = squadIndex + 1
            currentSquad = {}
        end
    end

    -- Add remaining howitzers as final squad
    if #currentSquad > 0 then
        self.squads[squadIndex] = currentSquad
    end
end

function aiCore.HowitzerManager:UpdateSquadOrders()
    local Cmd = utility.AiCommand

    -- Prioritize support infrastructure and constructors before core production.
    local targets = {}
    local seenTargets = {}
    local function AddTarget(h)
        if IsValid(h) and IsAlive(h) and not seenTargets[h] then
            seenTargets[h] = true
            table.insert(targets, h)
        end
    end

    local enemyTeam = -1
    if self.teamObj and self.teamObj.GetPrimaryEnemyTeam then
        enemyTeam = self.teamObj:GetPrimaryEnemyTeam()
    end
    if enemyTeam < 0 then
        enemyTeam = (self.teamNum == 1) and 2 or 1
    end

    -- Tier 1: Sustainment and field support.
    for _, obj in ipairs(aiCore.GetCachedTeamTargets(enemyTeam)) do
        if IsValid(obj) and IsAlive(obj) then
            local cls = string.lower(utility.CleanString(GetClassLabel(obj)))
            if cls == utility.ClassLabel.REPAIR_DEPOT or cls == utility.ClassLabel.SUPPLY_DEPOT
                or cls == utility.ClassLabel.CONSTRUCTOR or cls == utility.ClassLabel.SCRAP_SILO
                or string.find(cls, utility.ClassLabel.HOWITZER) then
                AddTarget(obj)
            end
        end
    end

    local con = GetConstructorHandle(enemyTeam)
    AddTarget(con)

    -- Tier 2: Defensive network and other high-value battlefield assets.
    for _, obj in ipairs(aiCore.GetCachedTeamTargets(enemyTeam)) do
        if IsValid(obj) and IsAlive(obj) then
            local cls = string.lower(utility.CleanString(GetClassLabel(obj)))
            if string.find(cls, "turret") or string.find(cls, "turrettank") or string.find(cls, utility.ClassLabel.HOWITZER)
                or cls == utility.ClassLabel.POWERPLANT or cls == utility.ClassLabel.BARRACKS
                or string.find(cls, "commtower") or string.find(cls, "proximity") then
                AddTarget(obj)
            end
        end
    end

    -- Tier 3: Core production and command buildings.
    AddTarget(GetRecyclerHandle(enemyTeam))
    AddTarget(GetFactoryHandle(enemyTeam))
    AddTarget(GetArmoryHandle(enemyTeam))

    for _, obj in ipairs(aiCore.GetCachedTeamTargets(enemyTeam)) do
        if IsValid(obj) and IsAlive(obj) and IsBuilding(obj) then
            AddTarget(obj)
        end
    end

    if #targets == 0 then return end

    -- Assign targets to squads in round-robin order to maximize map coverage.
    local targetCursor = self.targetCursor or 1
    for squadNum, squad in ipairs(self.squads) do
        if #squad > 0 then
            local targetIndex = ((targetCursor + squadNum - 2) % #targets) + 1
            local target = targets[targetIndex]

            for _, h in ipairs(squad) do
                if IsValid(h) and IsValid(target) then
                    local dist = GetDistance(h, target)
                    if dist > 500 then
                        -- Move to engagement range (approx 450m)
                        -- Calculate approach vector
                        local tPos = GetPosition(target)
                        local hPos = GetPosition(h)
                        local dir = Normalize(hPos - tPos)
                        local movePos = tPos + dir * 450

                        -- Use pathfinding safe-move
                        if GetCurrentCommand(h) ~= Cmd.GO or GetDistance(h, movePos) > 20 then
                            aiCore.TrySetCommand(h, Cmd.GO, GetUncommandablePriority(), nil, movePos, nil, nil,
                                { minInterval = 0.9 })
                        end
                    else
                        -- In range, clear to engage
                        if GetCurrentCommand(h) ~= Cmd.ATTACK or GetCurrentWho(h) ~= target then
                            aiCore.TryAttack(h, target, GetCommandableAttackPriority(), { minInterval = 0.8 })
                        end
                    end
                end
            end
        end
    end

    self.targetCursor = ((targetCursor + #self.squads - 1) % #targets) + 1
end

----------------------------------------------------------------------------------
-- MINELAYER MANAGER (from aiSpecial)
-- Automated minefield deployment and reloading
----------------------------------------------------------------------------------

aiCore.MinelayerManager = {}
aiCore.MinelayerManager.__index = aiCore.MinelayerManager

function aiCore.MinelayerManager.new(teamNum)
    local self = setmetatable({}, aiCore.MinelayerManager)
    self.teamNum = teamNum
    self.minelayers = {}
    self.minefields = {}   -- Configured minefield positions
    self.currentField = {} -- Track which field each minelayer is working on
    self.outbound = {}     -- Traveling to field
    self.laying = {}       -- Laying mines
    self.reloading = {}    -- Returning to supply
    self.mineOrderTime = {}
    return self
end

function aiCore.MinelayerManager:AddObject(h)
    if not IsValid(h) or GetTeamNum(h) ~= self.teamNum then return end

    local cls = string.lower(GetClassLabel(h) or "")
    if string.find(cls, "minelayer") then
        table.insert(self.minelayers, h)
        self.currentField[h] = 0
        self.outbound[h] = false
        self.laying[h] = false
        self.reloading[h] = false
        self.mineOrderTime[h] = 0.0
        if aiCore.Debug then print("Team " .. self.teamNum .. " added minelayer: " .. GetOdf(h)) end
    end
end

function aiCore.MinelayerManager:SetMinefields(positions)
    self.minefields = positions
end

-- Dynamically calculate minefield positions (like pilotMode)
function aiCore.MinelayerManager:CalculateMinefields()
    if #self.minefields > 0 then return end -- Already configured

    local recycler = GetRecyclerHandle(self.teamNum)
    if not IsValid(recycler) then return end

    local recPos = GetPosition(recycler)
    local enemyBase = nil

    -- Find enemy recycler as reference point
    for i = 1, 15 do
        if i ~= self.teamNum and i ~= 0 then
            local enemyRec = GetRecyclerHandle(i)
            if IsValid(enemyRec) then
                enemyBase = paths.GetPosition(enemyRec)
                break
            end
        end
    end

    if enemyBase then
        -- Strategic minefields: between base and enemy, and flanking positions
        local toEnemy = Normalize(enemyBase - recPos)
        local perpendicular = SetVector(-toEnemy.z, 0, toEnemy.x)
        local midDist = Length(recPos - enemyBase) * 0.4

        -- Field 1: Forward defensive position
        self.minefields[1] = recPos + toEnemy * midDist

        -- Field 2 & 3: Flanking positions
        self.minefields[2] = recPos + toEnemy * midDist + perpendicular * 150
        self.minefields[3] = recPos + toEnemy * midDist - perpendicular * 150
    else
        -- No enemy found: defensive perimeter around base
        local angles = { 0, 120, 240 } -- 3 fields, evenly spaced
        for i, angle in ipairs(angles) do
            local rad = math.rad(angle)
            self.minefields[i] = SetVector(
                recPos.x + math.cos(rad) * 200,
                recPos.y,
                recPos.z + math.sin(rad) * 200
            )
        end
    end

    if aiCore.Debug then
        print("Team " .. self.teamNum .. " calculated " .. #self.minefields .. " dynamic minefield positions")
    end
end

function aiCore.MinelayerManager:Update()
    -- Auto-calculate minefields if none set
    if #self.minefields == 0 then
        self:CalculateMinefields()
    end

    if #self.minefields == 0 then return end -- Still no fields (no recycler yet)

    for i = #self.minelayers, 1, -1 do
        local h = self.minelayers[i]
        if not IsValid(h) then
            table.remove(self.minelayers, i)
            self.currentField[h] = nil
            self.outbound[h] = nil
            self.laying[h] = nil
            self.reloading[h] = nil
            self.mineOrderTime[h] = nil
        else
            self:UpdateMinelayer(h)
        end
    end
end

function aiCore.MinelayerManager:UpdateMinelayer(h)
    local ammo = GetCurAmmo(h)
    local maxAmmo = GetMaxAmmo(h)

    -- Need to reload?
    if ammo < (maxAmmo * 0.2) and not self.reloading[h] then
        self.reloading[h] = true
        self.laying[h] = false
        self.outbound[h] = false
        self.mineOrderTime[h] = 0.0

        -- Find nearest supply depot
        local supply = nil
        local bestDist = 1000 -- Max search range
        local myPos = GetPosition(h)
        for obj in ObjectsInRange(1000, myPos) do
            if IsValid(obj) and GetTeamNum(obj) == GetTeamNum(h) then
                local objClass = string.lower(utility.CleanString(GetClassLabel(obj)))
                local objSig = string.upper(utility.CleanString(GetClassSig(obj)))
                if objClass == utility.ClassLabel.SUPPLY_DEPOT or objSig == utility.ClassSig.SUPPLY_DEPOT then
                    local dist = GetDistance(h, obj)
                    if dist < bestDist then
                        bestDist = dist
                        supply = obj
                    end
                end
            end
        end
        if supply and IsValid(supply) then
            aiCore.TrySetCommand(h, AiCommand.GO, GetUncommandablePriority(), supply, nil, nil, nil,
                { minInterval = 1.0 })
            if aiCore.Debug then print("Minelayer returning to reload") end
        end
        return
    end

    -- Done reloading?
    if self.reloading[h] and ammo >= maxAmmo then
        self.reloading[h] = false
    end

    -- If idle or done reloading, assign to minefield
    if not self.outbound[h] and not self.laying[h] and not self.reloading[h] then
        -- Cycle to next field
        local fieldNum = (self.currentField[h] % #self.minefields) + 1
        self.currentField[h] = fieldNum
        self.outbound[h] = true

        local fieldPos = self.minefields[fieldNum]
        aiCore.TrySetCommand(h, AiCommand.GO, GetUncommandablePriority(), nil, fieldPos, nil, nil,
            { minInterval = 1.0 })
        if aiCore.Debug then print("Minelayer heading to field " .. fieldNum) end
    end

    -- Arrived at field?
    if self.outbound[h] then
        local fieldPos = self.minefields[self.currentField[h]]
        if GetDistance(h, fieldPos) < 80 then
            self.outbound[h] = false
            self.laying[h] = true
            local minePos = GetPositionNear(fieldPos, 20, 70) or fieldPos
            if Mine then
                Mine(h, minePos, 1)
            else
                aiCore.TrySetCommand(h, AiCommand.GO, GetCommandableAttackPriority(), nil, minePos, nil, nil,
                    { minInterval = 0.8 })
            end
            self.mineOrderTime[h] = GetTime() + 7.0
            if aiCore.Debug then print("Minelayer laying mines") end
        end
    end

    -- Laying mines with explicit Mine() orders for denser/controlled fields.
    if self.laying[h] and ammo > (maxAmmo * 0.2) then
        if GetTime() >= (self.mineOrderTime[h] or 0.0) then
            local fieldPos = self.minefields[self.currentField[h]]
            local minePos = GetPositionNear(fieldPos, 20, 80) or fieldPos
            if Mine then
                Mine(h, minePos, 1)
            else
                aiCore.TrySetCommand(h, AiCommand.GO, GetCommandableAttackPriority(), nil, minePos, nil, nil,
                    { minInterval = 0.8 })
            end
            self.mineOrderTime[h] = GetTime() + 7.0
        end
    end
end

----------------------------------------------------------------------------------
-- APC MANAGER (from aiSpecial)
-- Autonomous pilot pickup and transport system
----------------------------------------------------------------------------------

aiCore.APCManager = {}
aiCore.APCManager.__index = aiCore.APCManager

function aiCore.APCManager.new(teamNum)
    local self = setmetatable({}, aiCore.APCManager)
    self.teamNum = teamNum
    self.apcs = {}
    self.attackRange = 120 -- Distance to enemy before switching from GO to ATTACK
    self.updatePeriod = 5.0
    self.updateTimer = 0.0
    return self
end

function aiCore.APCManager:AddObject(h)
    if not IsValid(h) or GetTeamNum(h) ~= self.teamNum then return end

    local cls = string.lower(GetClassLabel(h) or "")
    if string.find(cls, "apc") or string.find(cls, "transport") then
        table.insert(self.apcs, h)
        if aiCore.Debug then print("Team " .. self.teamNum .. " added APC: " .. GetOdf(h)) end
    end
end

function aiCore.APCManager:Update()
    self.updateTimer = self.updateTimer + GetTimeStep()
    if self.updateTimer < self.updatePeriod then return end
    self.updateTimer = 0.0

    local attackTargets = {}
    for target in AllCraft() do
        if self:IsAttackableEnemyUnit(nil, target) then
            attackTargets[#attackTargets + 1] = target
        end
    end

    for i = #self.apcs, 1, -1 do
        local apc = self.apcs[i]
        if not IsValid(apc) then
            table.remove(self.apcs, i)
        else
            self:UpdateAPC(apc, attackTargets)
        end
    end
end

function aiCore.APCManager:IsAttackableEnemyUnit(apc, target)
    if not IsValid(target) or not IsAlive(target) then return false end
    if IsValid(apc) and IsAlly(apc, target) then return false end
    if IsBuilding(target) then return false end

    local cls = string.lower(utility.CleanString(GetClassLabel(target)))
    if cls == utility.ClassLabel.CAMERA_POD
        or cls == utility.ClassLabel.SPECIAL_ITEM
        or cls == utility.ClassLabel.POWERUP_GENERIC
        or cls == utility.ClassLabel.DROPOFF
        or cls == utility.ClassLabel.SIGN
        or cls == "wpnpower"
        or cls == "ammopack"
        or cls == "repairkit" then
        return false
    end

    return IsCraft(target)
end

function aiCore.APCManager:GetNearestAttackableEnemy(apc, candidates)
    local best = nil
    local bestDist = 999999

    local attacker = GetWhoShotMe(apc)
    if self:IsAttackableEnemyUnit(apc, attacker) then
        return attacker, DistanceBetweenRefs(apc, attacker)
    end

    for i = 1, #(candidates or aiCore.EmptyList) do
        local target = candidates[i]
        if self:IsAttackableEnemyUnit(apc, target) then
            local dist = DistanceBetweenRefs(apc, target)
            if dist < bestDist then
                best = target
                bestDist = dist
            end
        end
    end

    return best, bestDist
end

function aiCore.APCManager:UpdateAPC(apc, attackTargets)
    local currentCmd = GetCurrentCommand(apc)

    if IsBusy(apc) and currentCmd ~= AiCommand.GET_RELOAD and currentCmd ~= AiCommand.GET_REPAIR then
        return
    end

    local enemyTarget, enemyDist = self:GetNearestAttackableEnemy(apc, attackTargets)

    -- Find safe position
    local pos = GetPosition(apc)
    ---@diagnostic disable-next-line: param-type-mismatch
    local h = GetTerrainHeightAndNormal(pos)
    ---@diagnostic disable-next-line: undefined-global
    local waterH = 0.0 -- GetWaterLevel() -- BZ1 doesn't have this function
    if h < waterH then
        -- In water, fall back to the recycler instead of relying on an unavailable path API.
        local recycler = GetRecyclerHandle(self.teamNum)
        if IsValid(recycler) then
            aiCore.TrySetCommand(apc, AiCommand.GO, GetUncommandablePriority(), recycler, nil, nil, nil,
                { minInterval = 1.0 })
        else
            local landPos = GetPositionNear(pos, 60, 140)
            if landPos then
                landPos.y = GetTerrainHeight(landPos.x, landPos.z)
                aiCore.TrySetCommand(apc, AiCommand.GO, GetUncommandablePriority(), nil, landPos, nil, nil,
                    { minInterval = 1.0 })
            end
        end
    end

    if enemyTarget and IsValid(enemyTarget) then
        if enemyDist <= (self.attackRange or 120.0) then
            if aiCore.TryAttack(apc, enemyTarget, GetUncommandablePriority(), { minInterval = 0.7 }) and aiCore.Debug then
                print("APC attacking enemy unit " .. tostring(GetOdf(enemyTarget)))
            end
        elseif currentCmd ~= AiCommand.GO or GetCurrentWho(apc) ~= enemyTarget then
            aiCore.TrySetCommand(apc, AiCommand.GO, GetUncommandablePriority(), enemyTarget, nil, nil, nil,
                { minInterval = 0.9 })
        end
    end
end

----------------------------------------------------------------------------------
-- TURRET MANAGER (from aiSpecial)
-- Auto-deployment of turret tanks near base perimeter
----------------------------------------------------------------------------------

aiCore.TurretManager = {}
aiCore.TurretManager.__index = aiCore.TurretManager

function aiCore.TurretManager.new(teamNum)
    local self = setmetatable({}, aiCore.TurretManager)
    self.teamNum = teamNum
    self.turrets = {}
    self.deployPositions = {} -- Calculated deployment positions
    self.deployRadius = 150   -- Distance from recycler
    self.updatePeriod = 8.0
    self.updateTimer = 0.0
    return self
end

function aiCore.TurretManager:AddObject(h)
    if not IsValid(h) or GetTeamNum(h) ~= self.teamNum then return end

    local odf = string.lower(GetOdf(h))
    -- Turret tanks: units with "turr" in name (turretanks can deploy into stationary turrets)
    if string.find(odf, "turr") then
        table.insert(self.turrets, h)
        if aiCore.Debug then print("Team " .. self.teamNum .. " added turret: " .. GetOdf(h)) end
    end
end

function aiCore.TurretManager:CalculateDeployPositions()
    local recycler = GetRecyclerHandle(self.teamNum)
    if not IsValid(recycler) then return end

    local recPos = GetPosition(recycler)
    self.deployPositions = {}

    -- Create perimeter positions
    local angles = { 0, 60, 120, 180, 240, 300 } -- 6 positions
    for i, angle in ipairs(angles) do
        local rad = math.rad(angle)
        local pos = SetVector(
            recPos.x + math.cos(rad) * self.deployRadius,
            recPos.y,
            recPos.z + math.sin(rad) * self.deployRadius
        )
        table.insert(self.deployPositions, pos)
    end
end

function aiCore.TurretManager:Update()
    -- Skip if production management is disabled for this team
    if self.teamObj and self.teamObj.Config and not self.teamObj.Config.manageFactories then return end

    if #self.deployPositions == 0 then
        self:CalculateDeployPositions()
    end

    self.updateTimer = self.updateTimer + GetTimeStep()
    if self.updateTimer < self.updatePeriod then return end
    self.updateTimer = 0.0

    for i = #self.turrets, 1, -1 do
        local turret = self.turrets[i]
        if not IsValid(turret) then
            table.remove(self.turrets, i)
        elseif not IsDeployed(turret) and not IsBusy(turret) then
            self:DeployTurret(turret, i)
        end
    end
end

function aiCore.TurretManager:DeployTurret(turret, index)
    if #self.deployPositions == 0 then return end

    -- Assign to position based on index
    local posIndex = ((index - 1) % #self.deployPositions) + 1
    local targetPos = self.deployPositions[posIndex]

    -- Move to position and deploy
    if Length(GetPosition(turret) - targetPos) > 20 then
        aiCore.TrySetCommand(turret, AiCommand.GO, GetUncommandablePriority(), nil, targetPos, nil, nil,
            { minInterval = 1.0 })
    else
        Deploy(turret)
        if aiCore.Debug then print("Turret deployed at position " .. posIndex) end
    end
end

----------------------------------------------------------------------------------
-- GUARD MANAGER (from aiSpecial)
-- Manages guard squads for recyclers and constructors
----------------------------------------------------------------------------------

aiCore.GuardManager = {}
aiCore.GuardManager.__index = aiCore.GuardManager

function aiCore.GuardManager.new(teamNum)
    local self = setmetatable({}, aiCore.GuardManager)
    self.teamNum = teamNum
    self.recyclerGuards = {}
    self.constructorGuards = {}
    self.guardsPerTarget = 3
    self.updatePeriod = 10.0
    self.updateTimer = 0.0
    return self
end

function aiCore.GuardManager:AssignGuard(unit, target)
    if not IsValid(unit) or not IsValid(target) then return false end

    aiCore.TrySetCommand(unit, AiCommand.FOLLOW, GetUncommandablePriority(), target, nil, nil, nil,
        { minInterval = 0.8 })
    if aiCore.Debug then print("Team " .. self.teamNum .. " guard assigned to " .. GetOdf(target)) end
    return true
end

----------------------------------------------------------------------------------
-- DEFENSE MANAGER
-- Smart targeting for Turrets and Gun Towers: switch targets if stuck or shot
----------------------------------------------------------------------------------

aiCore.DefenseManager = {}
aiCore.DefenseManager.__index = aiCore.DefenseManager

function aiCore.DefenseManager.new(teamNum)
    local self = setmetatable({}, aiCore.DefenseManager)
    self.teamNum = teamNum
    self.defenses = {} -- {handle = {lastAmmo=f, lastHealth=f, nextCheckTime=f, stuckTimer=f, classLabel=s}}
    self.updatePeriod = 0.5
    self.detectionRadius = 275.0
    self.rangeBuffer = 30.0
    self.shotCheckDelay = 0.5
    self.switchCheckDelay = 0.5
    self.keepCheckDelay = 0.5
    self.idleCheckDelay = 0.5
    self.stuckSwitchDelay = 1.0
    self.updateTimer = 0.0
    return self
end

function aiCore.DefenseManager:AddObject(h)
    if not IsValid(h) then return end
    if self.defenses[h] then return end

    local odf = string.lower(utility.CleanString(GetOdf(h)))
    local cls = string.lower(utility.CleanString(GetClassLabel(h)))

    if string.find(cls, "turret") or string.find(cls, "tower") or string.match(odf, "gtow") then
        self.defenses[h] = {
            lastAmmo = GetCurAmmo(h),
            lastHealth = GetCurHealth(h),
            nextCheckTime = 0.0,
            stuckTimer = 0.0,
            classLabel = cls
        }
        if aiCore.Debug then print("DefenseManager (Team " .. self.teamNum .. ") registered: " .. GetOdf(h)) end
    end
end

function aiCore.DefenseManager:RemoveObject(h)
    self.defenses[h] = nil
end

function aiCore.DefenseManager:Update()
    -- Defense management is generally safe (target switching), but respect autoManage for player
    if self.teamNum == 1 and self.teamObj and self.teamObj.Config and not self.teamObj.Config.autoManage then return end

    self.updateTimer = self.updateTimer + GetTimeStep()
    if self.updateTimer < self.updatePeriod then return end
    self.updateTimer = 0.0

    local now = GetTime()
    local baseDetectionRadius = self.detectionRadius or 275.0
    local function FindBestTarget(defense, currentTarget, searchRadius)
        local closest = nil
        local closestDist = searchRadius
        local personOnly = true

        for candidate in ObjectsInRange(searchRadius, defense) do
            if IsValid(candidate) and IsAlive(candidate) and candidate ~= currentTarget and not IsAlly(defense, candidate) and
                not IsCloaked(candidate) then
                local isEnemyPerceived = not IsTeamAllied(GetTeamNum(defense), GetPerceivedTeam(candidate))
                local isSelfPerceived = not IsTeamAllied(GetPerceivedTeam(defense), GetTeamNum(candidate))
                if isEnemyPerceived and isSelfPerceived then
                    local d = GetDistance(defense, candidate)
                    if IsCraft(candidate) then
                        if d < closestDist or personOnly then
                            closest = candidate
                            closestDist = d
                        end
                        personOnly = false
                    elseif personOnly and IsPerson(candidate) and d < closestDist then
                        local front = GetFront(defense)
                        local disp = GetPosition(candidate) - GetPosition(defense)
                        if (front.x * disp.x + front.y * disp.y + front.z * disp.z) > 0 then
                            closest = candidate
                            closestDist = d
                        end
                    end
                end
            end
        end

        return closest
    end

    for h, data in pairs(self.defenses) do
        if not IsValid(h) then
            self.defenses[h] = nil
        elseif IsAlive(h) and IsLocal(h) then
            local curAmmo = GetCurAmmo(h)
            local curHealth = GetCurHealth(h)
            local target = GetCurrentWho(h)
            local classLabel = data.classLabel or string.lower(utility.CleanString(GetClassLabel(h)))
            local isTurretTank = string.find(classLabel, "turrettank") ~= nil
            local weaponRange = GetCurrentWeaponRangeMeters(h) or 0.0
            local detectionRadius = math.max(baseDetectionRadius, weaponRange + (self.rangeBuffer or 30.0))
            if not (isTurretTank and not IsDeployed(h)) then
                local isFiring = curAmmo < (data.lastAmmo - 0.05)
                if isFiring then
                    data.nextCheckTime = now + (self.shotCheckDelay or 0.5)
                end

                local targetValid = IsValid(target) and IsAlive(target) and not IsCloaked(target) and
                    not IsAlly(h, target) and GetDistance(h, target) < detectionRadius
                if not targetValid then
                    if target and IsValid(target) then
                        Stop(h)
                    end
                    target = nil
                    data.nextCheckTime = math.min(data.nextCheckTime or 0, now)
                    data.stuckTimer = 0.0
                elseif isFiring then
                    data.stuckTimer = 0.0
                else
                    data.stuckTimer = data.stuckTimer + self.updatePeriod
                end

                if now >= (data.nextCheckTime or 0) then
                    local attacker = GetWhoShotMe(h)
                    local justShot = (now - GetLastEnemyShot(h)) < 5.0
                    local forceSwitch = data.stuckTimer >= (self.stuckSwitchDelay or 2.0)
                    local bestTarget = FindBestTarget(h, forceSwitch and target or nil, detectionRadius)

                    if IsValid(attacker) and IsAlive(attacker) and not IsAlly(h, attacker) and
                        ((not IsValid(target) and justShot) or (forceSwitch and justShot) or (curHealth < data.lastHealth - 100)) then
                        bestTarget = attacker
                    end

                    if IsValid(bestTarget) then
                        if bestTarget ~= target then
                            if aiCore.TryAttack(h, bestTarget, GetCommandableAttackPriority(),
                                    { minInterval = 0.15, ignoreThrottle = true, forceIssue = true }) then
                                data.stuckTimer = 0.0
                                data.nextCheckTime = now + (self.switchCheckDelay or 0.5)
                            end
                        else
                            data.nextCheckTime = now + (self.keepCheckDelay or 0.5)
                        end
                    elseif forceSwitch and targetValid then
                        if aiCore.TryAttack(h, target, GetCommandableAttackPriority(),
                                { minInterval = 0.15, ignoreThrottle = true, forceIssue = true }) then
                            data.stuckTimer = 0.0
                            data.nextCheckTime = now + (self.switchCheckDelay or 0.5)
                        else
                            data.nextCheckTime = now + (self.keepCheckDelay or 0.5)
                        end
                    else
                        data.nextCheckTime = now + (self.idleCheckDelay or 0.5)
                    end
                end
            else
                data.stuckTimer = 0.0
            end

            data.lastAmmo = curAmmo
            data.lastHealth = curHealth
        end
    end
end

----------------------------------------------------------------------------------
-- OFFENSE RETALIATION MANAGER
-- For teams not registered with aiCore.AddTeam: wingman/walker retaliation logic
----------------------------------------------------------------------------------
aiCore.OffenseRetaliationManager = {}
aiCore.OffenseRetaliationManager.__index = aiCore.OffenseRetaliationManager

function aiCore.OffenseRetaliationManager.new(teamNum)
    local self = setmetatable({}, aiCore.OffenseRetaliationManager)
    self.teamNum = teamNum
    self.units = {} -- {handle = {lastAmmo=f, lastHealth=f, nextRetaliateTime=f}}
    self.updatePeriod = 0.5
    self.updateTimer = 0.0
    return self
end

function aiCore.OffenseRetaliationManager:AddObject(h)
    if not IsValid(h) or GetTeamNum(h) ~= self.teamNum then return end
    if self.units[h] then return end

    local cls = string.lower(utility.CleanString(GetClassLabel(h)))
    if string.find(cls, "wingman") or string.find(cls, "walker") then
        self.units[h] = {
            lastAmmo = GetCurAmmo(h),
            lastHealth = GetCurHealth(h),
            nextRetaliateTime = 0.0
        }
    end
end

function aiCore.OffenseRetaliationManager:RemoveObject(h)
    self.units[h] = nil
end

function aiCore.OffenseRetaliationManager:Update()
    self.updateTimer = self.updateTimer + GetTimeStep()
    if self.updateTimer < self.updatePeriod then return end
    self.updateTimer = 0.0

    local now = GetTime()
    local retaliationCooldown = aiCore.GetRetaliationCooldown()
    local cmdPriority = GetCommandableAttackPriority()
    for u, state in pairs(self.units) do
        if not IsValid(u) or not IsAlive(u) then
            self.units[u] = nil
        else
            local curAmmo = GetCurAmmo(u)
            local curHealth = GetCurHealth(u)
            local cmd = GetCurrentCommand(u)
            local currentTarget = GetCurrentWho(u)
            local attacker = GetWhoShotMe(u)
            local justShot = (now - GetLastEnemyShot(u)) < 5.0
            local takingDamage = curHealth < (state.lastHealth - 0.01)
            local canRetaliate = aiCore.CanRetaliateToAttacker(u, self.teamNum, cmd, currentTarget, attacker)

            if justShot and takingDamage and IsValid(attacker) and aiCore.IsMissileThreat(attacker) then
                aiCore.TryDeployDecoy(u, 8.0)
            end

            local shouldRetaliate = false
            if self.teamNum == 1 then
                shouldRetaliate = canRetaliate and justShot and aiCore.IsIdleRetaliationCommand(cmd)
            else
                shouldRetaliate = canRetaliate and justShot and takingDamage
            end

            if now >= (state.nextRetaliateTime or 0.0) and shouldRetaliate then
                if aiCore.TryAttack(u, attacker, cmdPriority, { minInterval = 0.4 }) then
                    state.nextRetaliateTime = now + retaliationCooldown
                end
            end

            state.lastAmmo = curAmmo
            state.lastHealth = curHealth
        end
    end
end

----------------------------------------------------------------------------------
-- DEPOT MANAGER
-- AOE Repair/Supply: service all allied units in range simultaneously
----------------------------------------------------------------------------------

aiCore.DepotManager = {}
aiCore.DepotManager.__index = aiCore.DepotManager

function aiCore.DepotManager.new(teamNum)
    local self = setmetatable({}, aiCore.DepotManager)
    self.teamNum = teamNum
    self.depots = {} -- {handle = {range=f, amount=f, type="repair"|"supply"}}
    self.updatePeriod = 1.0
    self.updateTimer = 0.0
    return self
end

function aiCore.DepotManager:AddObject(h)
    if not IsValid(h) then return end
    if self.depots[h] then return end

    local odfName = string.lower(utility.CleanString(GetOdf(h)))
    local cls = string.lower(utility.CleanString(GetClassLabel(h)))

    local isRepair = (cls == utility.ClassLabel.REPAIR_DEPOT or string.match(odfName, "hang"))
    local isSupply = (cls == utility.ClassLabel.SUPPLY_DEPOT or string.match(odfName, "supp"))

    if isRepair or isSupply then
        local odf = OpenODF(odfName)
        local range, amount
        if isRepair then
            range = GetODFFloat(odf, "RepairDepotClass", "repairRange", 50.0)
            amount = GetODFFloat(odf, "RepairDepotClass", "repairAmount", 50.0)
        else
            range = GetODFFloat(odf, "SupplyDepotClass", "supplyRange", 50.0)
            amount = GetODFFloat(odf, "SupplyDepotClass", "supplyAmount", 50.0)
        end

        self.depots[h] = {
            range = range,
            amount = amount,
            type = isRepair and "repair" or "supply"
        }
        if aiCore.Debug then
            print("DepotManager (Team " ..
                self.teamNum .. ") registered: " .. GetOdf(h) .. " (Range: " .. range .. ", Amount: " .. amount .. ")")
        end
    end
end

function aiCore.DepotManager:RemoveObject(h)
    self.depots[h] = nil
end

function aiCore.DepotManager:Update()
    self.updateTimer = self.updateTimer + GetTimeStep()
    if self.updateTimer < self.updatePeriod then return end
    self.updateTimer = 0.0

    for h, data in pairs(self.depots) do
        if not IsValid(h) then
            self.depots[h] = nil
        else
            -- Find all objects in range
            for near in ObjectsInRange(data.range, h) do
                if IsAlive(near) and (GetTeamNum(near) == self.teamNum or IsAlly(near, h)) then
                    -- Only buff craft, not buildings
                    if not IsBuilding(near) then
                        local nOdf = utility.CleanString(GetOdf(near)) -- Not strictly needed for logic but good for consistency
                        if data.type == "repair" then
                            if GetCurHealth(near) < GetMaxHealth(near) then
                                AddHealth(near, data.amount)
                                if aiCore.Debug and near == GetPlayerHandle() then print("Depot AOE: Healing Player") end
                            end
                        else
                            if GetCurAmmo(near) < GetMaxAmmo(near) then
                                AddAmmo(near, data.amount)
                                if aiCore.Debug and near == GetPlayerHandle() then print("Depot AOE: Supplying Player") end
                            end
                        end
                    end
                end
            end
        end
    end
end

function aiCore.GuardManager:Update()
    -- Skip if production or auto-management is disabled
    if self.teamObj and self.teamObj.Config and not self.teamObj.Config.manageFactories then return end
    if self.teamObj and self.teamObj.Config and not self.teamObj.Config.autoManage then return end

    self.updateTimer = self.updateTimer + GetTimeStep()
    if self.updateTimer < self.updatePeriod then return end
    self.updateTimer = 0.0

    -- Clean up invalid guards
    for i = #self.recyclerGuards, 1, -1 do
        if not IsValid(self.recyclerGuards[i]) then
            table.remove(self.recyclerGuards, i)
        end
    end

    for i = #self.constructorGuards, 1, -1 do
        if not IsValid(self.constructorGuards[i]) then
            table.remove(self.constructorGuards, i)
        end
    end

    -- Assign guards to recycler if needed
    local recycler = GetRecyclerHandle(self.teamNum)
    if IsValid(recycler) and #self.recyclerGuards < self.guardsPerTarget then
        self:FindAndAssignGuards(recycler, self.recyclerGuards, self.guardsPerTarget - #self.recyclerGuards)
    end

    -- Assign guards to constructor if needed (simplified - just one constructor)
    local constructor = GetConstructorHandle(self.teamNum)
    if IsValid(constructor) and #self.constructorGuards < self.guardsPerTarget then
        self:FindAndAssignGuards(constructor, self.constructorGuards, self.guardsPerTarget - #self.constructorGuards)
    end
end

function aiCore.GuardManager:FindAndAssignGuards(target, guardList, needed)
    local assigned = 0

    -- Look for idle combat units (Optimized to use team list)
    local sourceList = {}
    -- If we have a team object with a combat list, use it
    if self.teamObj and self.teamObj.combatUnits then
        sourceList = self.teamObj.combatUnits
    else
        sourceList = aiCore.GetCachedTeamCraft(self.teamNum)
    end

    for _, obj in pairs(sourceList) do
        if assigned >= needed then break end

        if IsValid(obj) and GetTeamNum(obj) == self.teamNum and not IsBusy(obj) then
            local cls = aiCore.NilToString(GetClassLabel(obj))
            -- Wingmen or turrets make good guards
            if (string.find(cls, utility.ClassLabel.WINGMAN) or string.find(cls, utility.ClassLabel.TURRET))
                and not IsBuilding(obj) and not IsDeployed(obj) then
                -- Make sure not already guarding
                local alreadyGuarding = false
                for _, guard in ipairs(guardList) do
                    if guard == obj then
                        alreadyGuarding = true
                        break
                    end
                end

                if not alreadyGuarding and self:AssignGuard(obj, target) then
                    table.insert(guardList, obj)
                    assigned = assigned + 1
                end
            end
        end
    end
end

----------------------------------------------------------------------------------
-- AIP COMPATIBILITY SYSTEM
-- Maps legacy .aip filenames to modern Strategy system
----------------------------------------------------------------------------------

aiCore.AIPMappings = {
    -- NSDF Campaign
    ["misn02.aip"] = "Balanced",
    ["misn02b.aip"] = "Tank_Heavy", -- Missing from original
    ["misn03.aip"] = "Balanced",    -- Missing from original
    ["misn05.aip"] = "Balanced",
    ["misn07.aip"] = "Howitzer_Heavy",
    ["misn08.aip"] = "APC_Heavy",
    ["misn08a.aip"] = "Bomber_Heavy",
    ["misn08b.aip"] = "Tank_Heavy",
    ["misn09.aip"] = "Balanced",
    ["misn09a.aip"] = "Rocket_Heavy",
    ["misn09b.aip"] = "Howitzer_Heavy",
    ["misn10.aip"] = "Tank_Heavy",
    ["misn10a.aip"] = "APC_Heavy",
    ["misn10b.aip"] = "Bomber_Heavy", -- Missing from original
    ["misn13.aip"] = "Balanced",
    ["misn13a.aip"] = "Rocket_Heavy",
    ["misn13b.aip"] = "Howitzer_Heavy", -- Missing from original
    ["misn13c.aip"] = "Howitzer_Heavy",
    ["misn14.aip"] = "Tank_Heavy",
    ["misn15.aip"] = "Balanced", -- Missing from original
    ["misn16.aip"] = "Balanced",
    ["misn17.aip"] = "Howitzer_Heavy",

    -- Black Dog Campaign
    ["bdmisn07.aip"] = "Balanced", -- Fixed filename (was bdmisn7.aip)
    ["bdmisn14.aip"] = "Tank_Heavy",

    -- CCA Campaign
    ["chmisn06.aip"] = "Balanced",

    -- Mission Select (NSDF)
    ["misns4.aip"] = "Balanced",
    ["misns5.aip"] = "Tank_Heavy",
    ["misns6.aip"] = "Howitzer_Heavy",
    ["misns7.aip"] = "Balanced",      -- Missing from original
    ["misns7a.aip"] = "Tank_Heavy",   -- Missing from original
    ["misns7b.aip"] = "APC_Heavy",    -- Missing from original
    ["misns7c.aip"] = "Rocket_Heavy", -- Missing from original
    ["misns8.aip"] = "Balanced",
    ["misns8a.aip"] = "APC_Heavy",
    ["misns8b.aip"] = "Rocket_Heavy",
    ["misns8c.aip"] = "Tank_Heavy",
    ["misns8d.aip"] = "Bomber_Heavy",
    ["misns8e.aip"] = "Light_Force", -- Missing from original
    ["misns8f.aip"] = "Howitzer_Heavy",
    ["misns8g.aip"] = "Light_Force",

    -- Special/Training
    ["bowl.aip"] = "Balanced",   -- Missing from original
    ["demo01.aip"] = "Balanced", -- Missing from original
    ["inst01.aip"] = "Balanced", -- Missing from original
    ["tran03.aip"] = "Balanced", -- Missing from original
}

function aiCore.SetAIP(aipFile, teamNum)
    teamNum = teamNum or 2 -- Default to team 2 (enemy)

    if not aiCore.ActiveTeams or not aiCore.ActiveTeams[teamNum] then
        if aiCore.Debug then
            print("SetAIP: Team " .. teamNum .. " not initialized yet, deferring AIP: " .. aipFile)
        end
        return false
    end

    -- Look up strategy mapping (fallback to Balanced)
    local strategyName = aiCore.AIPMappings[aipFile] or "Balanced"

    -- Apply strategy to team
    local team = aiCore.ActiveTeams[teamNum]
    team.baseStrategy = strategyName
    team:SetStrategy(strategyName)

    if aiCore.Debug then
        print("SetAIP: Team " .. teamNum .. " using '" .. strategyName .. "' (from " .. aipFile .. ")")
    end

    return true
end

----------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
----------------------------------------------------------------------------------


function aiCore.IsTracked(h, teamNum)
    local team = aiCore.ActiveTeams[teamNum]
    if not team then return false end

    if team.recyclerMgr and team.recyclerMgr.handle == h then return true end
    if team.factoryMgr and team.factoryMgr.handle == h then return true end
    if team.constructorMgr and team.constructorMgr.handle == h then return true end

    -- Check tactical lists
    local lists = {
        team.scavengers, team.howitzers, team.apcs, team.minelayers,
        team.cloakers, team.turrets, team.doubleUsers, team.soldiers,
        team.mortars, team.thumpers, team.fields, team.pilots, team.pool, team.combatUnits
    }

    for _, list in ipairs(lists) do
        if list then
            for _, unit in ipairs(list) do
                if unit == h then return true end
            end
        end
    end

    -- Check build list handles
    for _, item in pairs(team.recyclerBuildList) do if item.handle == h then return true end end
    for _, item in pairs(team.factoryBuildList) do if item.handle == h then return true end end
    for _, item in pairs(team.buildingList) do if item.handle == h then return true end end

    return false
end

function aiCore.Bootstrap()
    if aiCore.Debug then print("aiCore: Bootstrapping world state...") end
    aiCore.ResetObjectCacheTracking()
    local count = 0
    local registered = 0

    for h in AllObjects() do
        count = count + 1
        aiCore.TrackWorldObject(h)
        local skip = false
        if IsCraft(h) then
            if IsIndependenceLocked(h) then
                skip = true
            else
                aiCore.ApplyDynamicMass(h)
            end
        end

        if not skip then
            local team = GetTeamNum(h)
            if aiCore.ActiveTeams[team] then
                if not aiCore.IsTracked(h, team) then
                    aiCore.AddObject(h)
                    registered = registered + 1
                end
            else
                aiCore.AddObject(h)
                registered = registered + 1
            end
        end
    end

    if aiCore.Debug then
        print("aiCore: Bootstrap complete. Processed " ..
            count .. " objects, registered " .. registered .. " new units.")
    end
    aiCore.RefreshObjectCache(true)
end

----------------------------------------------------------------------------------
-- UTILITY FUNCTIONS (RESTORED)
----------------------------------------------------------------------------------

function aiCore.GetNearestInTable(h, table)
    if next(table) ~= nil then
        local nearest = nil
        local minDist = 999999
        for i = 1, #table do
            if IsValid(table[i]) then
                local d = GetDistance(h, table[i])
                if d < minDist then
                    minDist = d
                    nearest = table[i]
                end
            end
        end
        return nearest
    end
    return nil
end

function aiCore.RemoveDead(tbl)
    if not tbl then return end
    for i = #tbl, 1, -1 do
        if not IsAlive(tbl[i]) then
            table.remove(tbl, i)
        end
    end
end

function aiCore.Lift(h, height)
    if not IsValid(h) then return end
    local pos = GetPosition(h)
    pos.y = pos.y + height
    SetPosition(h, pos)
end

function aiCore.GuessPilotOdf(barracksHandle)
    local teamNum = GetTeamNum(barracksHandle)
    local team = aiCore.ActiveTeams[teamNum]
    if team and team.faction and aiCore.Units[team.faction] then
        return aiCore.Units[team.faction].pilot
    end

    -- Fallback: Prefix guessing
    local fac = GetOdf(barracksHandle)
    local prefix = string.sub(fac, 1, 1)
    local guessed = prefix .. "spilo"
    if OpenODF(guessed) then
        return guessed
    end
    return "aspilo"
end

-- Vector Helpers
function aiCore.GetFlankPosition(target, dist, angleDeg)
    if not target or not IsValid(target) then return nil end
    local tPos = GetPosition(target)
    local rad = math.rad(angleDeg)
    return SetVector(tPos.x + math.cos(rad) * dist, tPos.y, tPos.z + math.sin(rad) * dist)
end

-- Upgrade Turret Logic (Ported from aiSpecial)
function aiCore.UpgradeTurret(h)
    if not IsValid(h) then return false end

    local success = false
    local odf = GetOdf(h)

    if odf == "avturr" then
        for i = 0, 3 do GiveWeapon(h, "gXinigun", i) end; success = true
    elseif odf == "svturr"
    then
        for i = 0, 2 do GiveWeapon(h, "gXinisov", i) end; success = true
    elseif odf == "cvturr" then
        for i = 0, 3 do GiveWeapon(h, "gXinisov", i) end; success = true
    elseif odf == "bvturr" then
        for i = 0, 3 do GiveWeapon(h, "gXinigun", i) end; success = true
    elseif odf == "bvtump" then
        for i = 0, 1 do GiveWeapon(h, "gXtstab", i) end; success = true
    elseif odf == "mvturr" then
        for i = 0, 1 do GiveWeapon(h, "gshadow", i) end; success = true
    elseif odf == "dvturr" then
        for i = 0, 3 do GiveWeapon(h, "gXinisov", i) end; success = true
    elseif odf == "rvturr" then
        for i = 0, 2 do GiveWeapon(h, "ghailgn", i) end; success = true
    elseif odf == "fvturr" then
        for i = 0, 3 do GiveWeapon(h, "gXongun", i) end; success = true
    elseif odf == "sbtowe" then
        for i = 0, 1 do GiveWeapon(h, "gX2nisov", i) end; success = true
    elseif odf == "cbtowe" then
        GiveWeapon(h, "gXtstabt", 0); success = true
    end

    if success and aiCore.Debug then
        print("Turret " .. odf .. " upgraded.")
    end
    return success
end

-- Replace Unit Logic (Ported from aiSpecial)
function aiCore.ReplaceUnit(h, newUnitOdf, chargeExpense, teamObj)
    if not IsValid(h) then return nil end

    local teamNum = GetTeamNum(h)
    local pos = GetPosition(h)
    local rot = GetTransform(h)

    local oldOdf = GetOdf(h)
    local oldScrapCost = GetODFInt(OpenODF(oldOdf), "GameObjectClass", "scrapCost")
    local newScrapCost = GetODFInt(OpenODF(newUnitOdf), "GameObjectClass", "scrapCost")

    RemoveObject(h)

    local replacement = BuildObject(newUnitOdf, teamNum, pos)
    SetTransform(replacement, rot)

    -- Charge expense?
    if chargeExpense and teamObj then
        local diff = newScrapCost - oldScrapCost
        if diff > 0 then
            AddScrap(teamNum, -diff)
            if aiCore.Debug then print("Team " .. teamNum .. " paid " .. diff .. " for replacement.") end
        end
    end

    return replacement
end

-- CLASSES
----------------------------------------------------------------------------------

-- Constants for magic numbers
aiCore.Constants = {
    CONSTRUCTOR_IDLE_DISTANCE = 100,   -- Distance to recycler before returning when idle
    CONSTRUCTOR_TRAVEL_THRESHOLD = 60, -- Distance before traveling to build site
    BUILDING_DETECTION_RANGE = 40,     -- Range to check for existing buildings
    BUILDING_SPACING = 50,             -- Spacing between buildings
    STRATEGY_ROTATION_INTERVAL = 180,  -- Seconds between strategy changes (3 minutes)
    PILOT_RESOURCE_INTERVAL = 20,      -- Seconds between pilot checks
    RESCUE_CHECK_INTERVAL = 10         -- Seconds between rescue checks
}

function aiCore.GetDifficultyLevel()
    local d = (exu and exu.GetDifficulty and tonumber(exu.GetDifficulty())) or 2
    if d < 0 then d = 0 end
    if d > 4 then d = 4 end
    return d
end

function aiCore.GetRetaliationCooldown()
    local d = aiCore.GetDifficultyLevel()
    if d <= 0 then return 2.2 end
    if d == 1 then return 1.8 end
    if d == 2 then return 1.5 end
    if d == 3 then return 1.2 end
    return 1.0
end

function aiCore.GetOrbitalReinforceChance()
    local d = aiCore.GetDifficultyLevel()
    if d <= 0 then return 15 end
    if d == 1 then return 22 end
    if d == 2 then return 30 end
    if d == 3 then return 38 end
    return 45
end

function aiCore.GetPlayerRushFormationChance()
    local d = aiCore.GetDifficultyLevel()
    if d == 3 then return 14 end -- Hard
    if d >= 4 then return 24 end -- Very Hard+
    return 0
end

function aiCore.IsIdleRetaliationCommand(cmd)
    return cmd == AiCommand.NONE or cmd == AiCommand.STOP
end

function aiCore.CanRetaliateToAttacker(unit, teamNum, cmd, currentTarget, attacker)
    if not IsValid(attacker) or not IsAlive(attacker) then return false end
    if attacker == currentTarget then return false end
    if IsAlly(unit, attacker) then return false end
    if teamNum == 1 and not aiCore.IsIdleRetaliationCommand(cmd) then
        return false
    end
    return true
end

function aiCore.UpdatePlayerRushAggression()
    local chance = aiCore.GetPlayerRushFormationChance()
    if chance <= 0 then return end

    local now = GetTime()
    aiCore.PlayerRushState = aiCore.PlayerRushState or {
        nextCheck = 0.0,
        cleanupTime = 0.0,
        shooterCooldown = {}
    }

    local state = aiCore.PlayerRushState
    if now < (state.nextCheck or 0.0) then return end
    state.nextCheck = now + 0.25

    local player = GetPlayerHandle()
    if not IsValid(player) or not IsAlive(player) then return end

    local shooter = GetWhoShotMe(player)
    if not IsValid(shooter) or not IsAlive(shooter) or not IsCraft(shooter) then return end

    local playerTeam = GetTeamNum(player)
    local shooterTeam = GetTeamNum(shooter)
    if shooterTeam == playerTeam or IsTeamAllied(shooterTeam, playerTeam) then return end
    if GetDistance(player, shooter) > 900 then return end

    local nextAllowed = state.shooterCooldown[shooter] or 0.0
    if now < nextAllowed then return end

    local didRush = false
    if math.random(100) <= chance then
        didRush = aiCore.TrySetCommand(shooter, AiCommand.FORMATION, GetCommandableAttackPriority(), player, nil, nil, nil,
            { minInterval = 0.6, overrideProtected = true })
    end

    if didRush then
        state.shooterCooldown[shooter] = now + 8.0
        if aiCore.Debug then
            print("Aggro Rush: " .. utility.CleanString(GetOdf(shooter)) .. " formation-rushing player.")
        end
    else
        state.shooterCooldown[shooter] = now + 2.5
    end

    if now >= (state.cleanupTime or 0.0) then
        state.cleanupTime = now + 30.0
        for h, t in pairs(state.shooterCooldown) do
            if (not IsValid(h)) or now > (t + 30.0) then
                state.shooterCooldown[h] = nil
            end
        end
    end
end

function aiCore.IsEnemyOfPlayerTeam(teamNum)
    local player = GetPlayerHandle()
    if not IsValid(player) then
        return teamNum ~= 1
    end
    local playerTeam = GetTeamNum(player)
    return teamNum ~= playerTeam and not IsTeamAllied(teamNum, playerTeam)
end

function aiCore.GetPlayerRecyclerHandle()
    local player = GetPlayerHandle()
    if not IsValid(player) then return nil end
    return GetRecyclerHandle(GetTeamNum(player))
end

function aiCore.IsGeyserObject(h)
    if not IsValid(h) then return false end
    local cls = string.lower(utility.CleanString(GetClassLabel(h)))
    if cls ~= "" and string.find(cls, "geyser") then return true end
    local label = string.lower(utility.CleanString(GetLabel(h)))
    if label ~= "" and string.find(label, "geyser") then return true end
    local odf = string.lower(utility.CleanString(GetOdf(h)))
    if odf ~= "" and string.find(odf, "geyser") then return true end
    return false
end

function aiCore.IsGeyserOpen(geyser)
    if not IsValid(geyser) then return false end
    local radius = 10.0
    for obj in ObjectsInRange(radius, geyser) do
        if IsValid(obj) and IsAlive(obj) then
            local cls = string.lower(utility.CleanString(GetClassLabel(obj)))
            if (string.find(cls, utility.ClassLabel.RECYCLER)
                    or string.find(cls, utility.ClassLabel.FACTORY)
                    or string.find(cls, utility.ClassLabel.ARMORY)) and (IsDeployed(obj) or IsBuilding(obj)) then
                return false
            end
        end
    end
    return true
end

function aiCore.FindClosestOpenGeyser(reference)
    if not IsValid(reference) then return nil end
    local best = nil
    local bestDist = 999999.0

    for obj in AllObjects() do
        if IsValid(obj) and aiCore.IsGeyserObject(obj) and aiCore.IsGeyserOpen(obj) then
            local d = DistanceBetweenRefs(reference, obj)
            if d < bestDist then
                best = obj
                bestDist = d
            end
        end
    end

    return best, bestDist
end

function aiCore.GetSniperRoleChancePercent(teamObj)
    local base = math.floor(((teamObj and teamObj.Config and teamObj.Config.pilotZeal) or 0.4) * 100)
    if aiCore.IsEnemyOfPlayerTeam(teamObj and teamObj.teamNum or -1) then
        base = base + (aiCore.GetDifficultyLevel() * 12)
    end
    if base < 5 then base = 5 end
    if base > 95 then base = 95 end
    return base
end

function aiCore.GetSniperAttackChancePercent(teamObj)
    local base = math.floor((teamObj and teamObj.Config and teamObj.Config.sniperTraining) or 75)
    if aiCore.IsEnemyOfPlayerTeam(teamObj and teamObj.teamNum or -1) then
        base = base + (aiCore.GetDifficultyLevel() * 6)
    end
    if base < 10 then base = 10 end
    if base > 98 then base = 98 end
    return base
end

-- Generic Build Queue Item
---@class aiCore.BuildItem
---@field odf string
---@field priority number
---@field path any
aiCore.BuildItem = {
    odf = "",
    priority = 0,
    path = nil -- for constructor builds
}
aiCore.BuildItem.__index = aiCore.BuildItem

-- Factory Manager (Handles Factory & Recycler Unit Production)
---@class aiCore.FactoryManager
---@field team number
---@field handle any
---@field queue aiCore.BuildItem[]
---@field isRecycler boolean
---@field teamObj aiCore.Team
---@field pulseTimer number
---@field pulsePeriod number
---@field lastDeployCommandTime number
aiCore.FactoryManager = {
    handle = nil,
    team = 0,
    queue = {},
    pulseTimer = 0.0,
    pulsePeriod = 3.0,
    isRecycler = false
}
aiCore.FactoryManager.__index = aiCore.FactoryManager

function aiCore.FactoryManager:new(team, isRecycler)
    local fm = setmetatable({}, self)
    fm.team = team
    -- We need a reference to the team object to check config, but it might not be fully initialized yet.
    -- We will bind it later or look it up.
    -- fm.teamObj will be assigned in aiCore.Team:new
    fm.isRecycler = isRecycler
    fm.queue = {}
    fm.lastDeployCommandTime = 0
    return fm
end

function aiCore.FactoryManager:update()
    if not IsValid(self.handle) then
        if self.isRecycler then
            self.handle = GetRecyclerHandle(self.team)
        else
            self.handle = GetFactoryHandle(self.team)
        end
        return
    end

    -- Deployment is still managed here if needed
    if self.teamObj and self.teamObj.Config and not self.teamObj.Config.manageFactories then return end

    if not IsDeployed(self.handle) then
        local currentTime = GetTime()
        if self.teamObj and self.teamObj.ShouldDeferProducerDeploy and self.teamObj:ShouldDeferProducerDeploy(self.handle, currentTime) then
            return
        end

        local cmd = GetCurrentCommand(self.handle)
        local allowRelocation = not (self.teamObj and self.teamObj.Config and self.teamObj.Config.allowProducerRelocation == false)
        local deployCommand = allowRelocation and AiCommand.GO_TO_GEYSER or AiCommand.DEPLOY
        -- Only issue Deploy command if not already deploying or undeploying
        -- AND not moving/defending (to prevent loops if unit is scripted to move while undeployed)
        if cmd ~= AiCommand.DEPLOY and cmd ~= AiCommand.UNDEPLOY and
            cmd ~= AiCommand.GO and cmd ~= AiCommand.GO_TO_GEYSER and
            cmd ~= AiCommand.DEFEND and cmd ~= AiCommand.FOLLOW then
            if currentTime >= (self.lastDeployCommandTime or 0) + 10 then
                if aiCore.TrySetCommand(self.handle, deployCommand, GetUncommandablePriority(), nil, nil, nil, nil,
                        { minInterval = 1.0, overrideProtected = true }) then
                    if self.teamObj and self.teamObj.MarkProducerDeployGrace then
                        self.teamObj:MarkProducerDeployGrace(self.handle, currentTime, deployCommand)
                    end
                    self.lastDeployCommandTime = currentTime
                end
            end
        end
        return -- Wait for deployment
    end

    -- Building is now handled by integrated producer via jobs queued in CheckBuildList
end

function aiCore.FactoryManager:addUnit(odf, priority)
    priority = priority or 999999
    local producerType = self.isRecycler and "recycler" or "factory"
    local account = "offense"
    local category = nil
    if self.teamObj and self.teamObj.GetBuildAccountForUnit then
        account = self.teamObj:GetBuildAccountForUnit(nil, odf, producerType)
    end
    if self.teamObj and self.teamObj.CanQueueUnitByRules then
        local allowed = self.teamObj:CanQueueUnitByRules(category, odf)
        if not allowed then
            return
        end
    end

    for _, item in ipairs(self.queue) do
        if item.odf == odf and item.priority == priority then
            return
        end
    end

    table.insert(self.queue, { odf = odf, priority = priority, account = account, category = category })
    table.sort(self.queue, function(a, b)
        local ap = a.priority or 999999
        local bp = b.priority or 999999
        if self.teamObj and self.teamObj.GetEffectiveBuildPriority then
            ap = self.teamObj:GetEffectiveBuildPriority(a.account, ap, a)
            bp = self.teamObj:GetEffectiveBuildPriority(b.account, bp, b)
        end
        if ap == bp then return (a.priority or 999999) < (b.priority or 999999) end
        return ap < bp
    end)

    local existingQueue = producer.Queue[self.team]
    if existingQueue then
        for _, job in ipairs(existingQueue) do
            if job.odf == odf and job.data and job.data.priority == priority and job.data.producer == producerType then
                return
            end
        end
    end

    producer.QueueJob(odf, self.team, nil, nil, {
        source = "FactoryManager:addUnit",
        priority = priority,
        type = "unit",
        producer = producerType,
        account = account,
        category = category
    })
end

-- Constructor Manager
---@class aiCore.ConstructorManager
---@field team number
---@field handle any
---@field queue aiCore.BuildItem[]
---@field sentToRecycler boolean
---@field teamObj aiCore.Team
---@field pulseTimer number
---@field pulsePeriod number
---@field activeJob aiCore.BuildItem|nil
---@field jobState string|nil
aiCore.ConstructorManager = {
    handle = nil,
    team = 0,
    queue = {},
    pulseTimer = 0.0,
    pulsePeriod = 8.0,
    sentToRecycler = false,
    activeJob = nil,
    jobState = nil -- "moving" or "building"
}
aiCore.ConstructorManager.__index = aiCore.ConstructorManager

function aiCore.ConstructorManager:new(team)
    local cm = setmetatable({}, self)
    cm.team = team
    -- cm.teamObj will be assigned in aiCore.Team:new
    cm.queue = {}
    return cm
end

function aiCore.ConstructorManager:update()
    if not IsValid(self.handle) then
        self.handle = GetConstructorHandle(self.team)
        if IsValid(self.handle) then
            -- self.pulseTimer = self.pulsePeriod + math.random((0*self.pulsePeriod), self.pulsePeriod) + GetTime()
        end
        self.sentToRecycler = false
        self.activeJob = nil
        return
    end

    if self.teamObj and self.teamObj.Config and not self.teamObj.Config.manageConstructor then return end

    -- Check if the active job has been completed
    if self.activeJob then
        local pos = self.activeJob.path
        local posVec = nil
        if type(pos) == "string" then
            posVec = paths.GetPosition(pos, 0)
        elseif type(pos) == "table" and pos.posit_x ~= nil then
            posVec = MatrixToPosition(pos)
        else
            posVec = pos
        end
        local building_exists = false
        if posVec then -- Check if pos is valid
            for obj in ObjectsInRange(40, posVec) do
                if IsOdf(obj, self.activeJob.odf) and GetTeamNum(obj) == self.team then
                    building_exists = true
                    break
                end
            end
        end
        if building_exists then
            if aiCore.Debug then print("Constructor job " .. self.activeJob.odf .. " verified complete.") end
            self.activeJob = nil
            self.jobState = nil
        end
    end

    -- If no active job, try to get one from the queue
    if not self.activeJob and #self.queue > 0 then
        table.sort(self.queue, function(one, two)
            local ap = one.priority or 999999
            local bp = two.priority or 999999
            if self.teamObj and self.teamObj.GetEffectiveBuildPriority then
                ap = self.teamObj:GetEffectiveBuildPriority(one.account, ap, one)
                bp = self.teamObj:GetEffectiveBuildPriority(two.account, bp, two)
            end
            if ap == bp then
                return (one.priority or 999999) < (two.priority or 999999)
            end
            return ap < bp
        end)
        self.activeJob = table.remove(self.queue, 1)
        self.sentToRecycler = false
        if aiCore.Debug then print("Constructor starts job: " .. self.activeJob.odf) end
    end

    -- Manage the active job
    if self.activeJob then
        local constructor = self.handle

        -- If constructor is busy OR cannot build (e.g. deploying), do nothing and let it finish.
        if not CanBuild(constructor) or IsBusy(constructor) then
            return
        end

        -- If we are here, the constructor is IDLE and ABLE to take a command.
        local pos = self.activeJob.path
        local posVec = nil
        local buildPos = pos
        if type(pos) == "string" then
            posVec = paths.GetPosition(pos, 0)
            buildPos = posVec
        elseif type(pos) == "table" and pos.posit_x ~= nil then
            posVec = MatrixToPosition(pos)
        else
            posVec = pos
            buildPos = pos
        end

        if not posVec then -- If path is invalid, junk the job
            self.activeJob = nil
            self.jobState = nil
            return
        end

        local cmd = GetCurrentCommand(constructor)
        if cmd == AiCommand.BUILD then
            return
        end
        local cmdName = AiCommand[cmd] or ""

        if not string.match(cmdName, "GO") and GetDistance(constructor, posVec) > 60.0 then
            -- Move to site
            aiCore.TrySetCommand(constructor, AiCommand.GO, GetUncommandablePriority(), nil, posVec, nil, nil,
                { minInterval = 1.0 })
            if aiCore.Debug then print("Constructor GOTO " .. self.activeJob.odf .. " site.") end
        elseif GetDistance(constructor, posVec) <= 60.0 then
            -- At site, try to build
            -- Pre-build checks
            local scrapCost = GetODFInt(OpenODF(self.activeJob.odf), "GameObjectClass", "scrapCost")
            if GetScrap(self.team) >= scrapCost then
                -- Check for existing building
                local existingBuilding = nil
                for obj in ObjectsInRange(40, posVec) do
                    if IsOdf(obj, self.activeJob.odf) and GetTeamNum(obj) == self.team then
                        existingBuilding = obj
                        break
                    end
                end

                if existingBuilding then
                    if aiCore.Debug then print("Constructor job " .. self.activeJob.odf .. " cancelled (already exists).") end
                    -- Associate and remove from queue is complex, just aborting job is safer for aiCore
                    self.activeJob = nil
                    self.jobState = nil
                    return
                else
                    -- Only build if pulse timer conditions are met
                    if GetTime() <= self.pulseTimer then
                        -- Keep waiting
                    else
                        -- Issue BuildAt command
                        if aiCore.Debug then print("Constructor issuing BuildAt for " .. self.activeJob.odf) end
                        BuildAt(constructor, self.activeJob.odf, buildPos)
                        self.pulseTimer = self.pulsePeriod + math.random((0 * self.pulsePeriod), self.pulsePeriod) +
                            GetTime()
                    end
                end
            end
        end
    else
        -- No active job and queue is empty: idle at recycler
        local recycler = GetRecyclerHandle(self.team)
        if IsValid(recycler) and not self.sentToRecycler then
            if GetDistance(self.handle, recycler) > aiCore.Constants.CONSTRUCTOR_IDLE_DISTANCE then
                aiCore.TrySetCommand(self.handle, AiCommand.GO, GetUncommandablePriority(), recycler, nil, nil, nil,
                    { minInterval = 1.0 })
                self.sentToRecycler = true
            end
        end
    end
end

-- Squad Class (Formations & Flanking)
aiCore.Squad = {
    leader = nil,
    members = {},
    state = "idling", -- idling, moving_to_flank, attacking
    targetPos = nil,
    formation = "V",
    maxSize = 3,
    flankStartTime = 0.0,
    flankTimeout = 22.0,
    attackStyle = "independent", -- independent | formation_rush
    formationLead = nil,
    teamObj = nil,
    goalMode = nil,
    goalKey = nil,
    goalAnchor = nil,
    goalTarget = nil,
    goalPos = nil,
    goalRadius = 220.0,
    estimatedStrength = 0.0,
    currentTarget = nil
}
aiCore.Squad.__index = aiCore.Squad

function aiCore.Squad:new(leader)
    local s = setmetatable({}, self)
    s.leader = leader
    s.members = {}
    s.maxSize = 3 + math.random(0, 1)
    s.flankStartTime = 0.0
    s.flankTimeout = 22.0
    s.attackStyle = "independent"
    s.formationLead = nil
    s.teamObj = nil
    s.goalMode = nil
    s.goalKey = nil
    s.goalAnchor = nil
    s.goalTarget = nil
    s.goalPos = nil
    s.goalRadius = 220.0
    s.estimatedStrength = 0.0
    s.currentTarget = nil
    return s
end

function aiCore.Squad:SetAttackStyle(style)
    if style == "formation_rush" then
        self.attackStyle = "formation_rush"
    else
        self.attackStyle = "independent"
    end
    self.formationLead = nil
end

function aiCore.Squad:GetActiveUnits()
    local units = {}
    if IsValid(self.leader) then table.insert(units, self.leader) end
    for _, m in ipairs(self.members) do
        if IsValid(m) then table.insert(units, m) end
    end
    return units
end

function aiCore.Squad:ChooseFormationLead()
    local units = self:GetActiveUnits()
    if #units == 0 then return nil end
    return units[math.random(1, #units)]
end

function aiCore.Squad:IsAttackLaneCrowded(target)
    if not self.teamObj or not IsValid(self.leader) or not IsValid(target) then return false end

    local leaderPos = GetPosition(self.leader)
    local targetPos = GetPosition(target)
    local toTarget = targetPos - leaderPos
    local dist = Length(toTarget)
    if dist <= 1.0 then return false end

    local dir = Normalize(toTarget)
    local dotThreshold = self.teamObj.Config.tacticalFormationOcclusionDot or 0.92
    local crowdRadius = self.teamObj.Config.tacticalFormationOcclusionRadius or 35.0

    for _, ally in ipairs(self.teamObj.combatUnits or aiCore.EmptyList) do
        if IsValid(ally) and ally ~= self.leader and GetTeamNum(ally) == self.teamObj.teamNum then
            local allyPos = GetPosition(ally)
            local toAlly = allyPos - leaderPos
            local allyDist = Length(toAlly)
            if allyDist > 10.0 and allyDist < dist then
                local dirDot = DotProduct(dir, Normalize(toAlly))
                local lateral = Length(toAlly - (dir * allyDist))
                if dirDot >= dotThreshold and lateral <= crowdRadius then
                    return true
                end
            end
        end
    end

    return false
end

function aiCore.Squad:IssueAttackOrders(target)
    if not IsValid(target) then return end
    self.currentTarget = target

    if self.attackStyle == "formation_rush" or (IsCraft(target) and self:IsAttackLaneCrowded(target)) then
        if not IsValid(self.formationLead) then
            self.formationLead = self:ChooseFormationLead()
        end
        local lead = self.formationLead
        if not IsValid(lead) then return end

        aiCore.TryAttack(lead, target, GetCommandableAttackPriority(), { minInterval = 0.65, overrideProtected = true })
        for _, unit in ipairs(self:GetActiveUnits()) do
            if unit ~= lead then
                aiCore.TrySetCommand(unit, AiCommand.FORMATION, GetCommandableAttackPriority(), lead, nil, nil, nil,
                    { minInterval = 0.65, overrideProtected = true })
            end
        end
        return
    end

    aiCore.TryAttack(self.leader, target, GetCommandableAttackPriority(), { minInterval = 0.7 })
    for _, m in ipairs(self.members) do
        if IsValid(m) then
            aiCore.TryAttack(m, target, GetCommandableAttackPriority(), { minInterval = 0.7 })
        end
    end
end

function aiCore.Squad:AddMember(h)
    table.insert(self.members, h)
    -- Order follow
    if IsValid(self.leader) then
        aiCore.TrySetCommand(h, AiCommand.FOLLOW, GetUncommandablePriority(), self.leader, nil, nil, nil,
            { minInterval = 0.8 })
    end
end

function aiCore.Squad:SetStrategicGoal(goal, teamObj)
    self.teamObj = teamObj
    self.goalMode = goal and goal.mode or nil
    self.goalKey = goal and goal.key or nil
    self.goalAnchor = goal and goal.anchor or nil
    self.goalTarget = goal and goal.target or nil
    self.goalPos = goal and goal.position or nil
    self.goalRadius = goal and goal.radius or 220.0
    self.currentTarget = nil
end

function aiCore.Squad:ResolveStrategicTarget()
    if IsValid(self.currentTarget) and IsAlive(self.currentTarget) and self.teamObj then
        local retain = self.teamObj:GetEconomicTargetValue(self.currentTarget, self.goalPos or ResolveReferencePosition(self.goalAnchor))
        if retain > 0.0 then
            return self.currentTarget
        end
    end
    if IsValid(self.goalTarget) and IsAlive(self.goalTarget) then
        return self.goalTarget
    end
    if self.teamObj and self.teamObj.ResolveStrategicGoalTarget then
        self.goalTarget = self.teamObj:ResolveStrategicGoalTarget(self)
        if IsValid(self.goalTarget) then
            self.currentTarget = self.goalTarget
            return self.goalTarget
        end
    end
    return nil
end

function aiCore.Squad:IssueDefendOrders()
    local anchor = self.goalAnchor
    local defendPos = ResolveReferencePosition(anchor) or self.goalPos

    if IsValid(anchor) then
        aiCore.TrySetCommand(self.leader, AiCommand.DEFEND, GetCommandableAttackPriority(), anchor, nil, nil, nil,
            { minInterval = 0.8 })
        for _, m in ipairs(self.members) do
            if IsValid(m) then
                aiCore.TrySetCommand(m, AiCommand.DEFEND, GetCommandableAttackPriority(), anchor, nil, nil, nil,
                    { minInterval = 0.8 })
            end
        end
        return
    end

    if defendPos then
        aiCore.TrySetCommand(self.leader, AiCommand.GO, GetUncommandablePriority(), nil, defendPos, nil, nil,
            { minInterval = 0.8 })
        for _, m in ipairs(self.members) do
            if IsValid(m) then
                aiCore.TrySetCommand(m, AiCommand.GO, GetUncommandablePriority(), nil, defendPos, nil, nil,
                    { minInterval = 0.8 })
            end
        end
    end
end

function aiCore.Squad:Update()
    if not IsValid(self.leader) then
        -- Promote new leader if possible
        if #self.members > 0 then
            local oldLeader = self.leader
            self.leader = table.remove(self.members, 1)
            if oldLeader and self.formationLead == oldLeader then
                self.formationLead = nil
            end
            -- Re-order followers
            for _, m in ipairs(self.members) do
                if IsValid(m) then
                    aiCore.TrySetCommand(m, AiCommand.FOLLOW, GetUncommandablePriority(), self.leader, nil, nil, nil,
                        { minInterval = 0.8 })
                end
            end
        else
            return false -- Dead squad
        end
    end

    -- State Machine
    if self.state == "moving_to_flank" then
        if self.targetPos then
            if self.flankStartTime == 0.0 then self.flankStartTime = GetTime() end

            local allArrived = IsValid(self.leader) and GetDistance(self.leader, self.targetPos) < 120
            for _, m in ipairs(self.members) do
                if IsValid(m) and GetDistance(m, self.targetPos) >= 120 then
                    allArrived = false
                    break
                end
            end
            local timedOut = (GetTime() - self.flankStartTime) >= self.flankTimeout

            if allArrived or timedOut then
                self.state = "attacking"
                local enemy = self:ResolveStrategicTarget()
                if not IsValid(enemy) then
                    enemy = GetNearestEnemy(self.leader)
                end
                if IsValid(enemy) then
                    self:IssueAttackOrders(enemy)
                end
            else
                -- Keep squad co-located at flank rally point.
                if IsValid(self.leader) and not string.match(aiCore.NilToString(AiCommand[GetCurrentCommand(self.leader)]), "GO") then
                    aiCore.TrySetCommand(self.leader, AiCommand.GO, GetUncommandablePriority(), nil, self.targetPos, nil,
                        nil, { minInterval = 0.8 })
                end
                for _, m in ipairs(self.members) do
                    if IsValid(m) and not string.match(aiCore.NilToString(AiCommand[GetCurrentCommand(m)]), "GO") then
                        aiCore.TrySetCommand(m, AiCommand.GO, GetUncommandablePriority(), nil, self.targetPos, nil, nil,
                            { minInterval = 0.8 })
                    end
                end
            end
        else
            -- Failed flank point generation: fall back to immediate attack.
            self.state = "attacking"
        end
    elseif self.state == "attacking" then
        local enemy = self:ResolveStrategicTarget()
        if IsValid(enemy) and (not IsBusy(self.leader) or GetCurrentWho(self.leader) ~= enemy) then
            self:IssueAttackOrders(enemy)
        elseif self.goalMode == "defend" and not IsBusy(self.leader) then
            self:IssueDefendOrders()
        end

        if not IsBusy(self.leader) then
            enemy = IsValid(enemy) and enemy or GetNearestEnemy(self.leader)
            if IsValid(enemy) then
                self:IssueAttackOrders(enemy)
            elseif self.goalMode == "defend" then
                self:IssueDefendOrders()
            end
        end
    end

    return true
end

----------------------------------------------------------------------------------
-- WINGMAN MANAGER (from autorepair.lua)
-- Auto-repair and rearm system for wingmen
----------------------------------------------------------------------------------

aiCore.WingmanManager = {}
aiCore.WingmanManager.__index = aiCore.WingmanManager

function aiCore.WingmanManager.new(teamNum)
    local self = setmetatable({}, aiCore.WingmanManager)
    self.teamNum = teamNum
    self.wingmen = {} -- Track wingmen with their state

    -- Depot/Pod tables (shared across team)
    self.repairDepots = {}
    self.supplyDepots = {}
    self.repairPods = {}
    self.ammoPods = {}

    -- Config (based on autorepair.lua)
    self.checkPeriod = 0.25
    self.updateTimer = 0.0
    self.podChance = 1.0
    self.podSearchRadius = 275.0
    self.depotSearchRadius = 650.0
    self.followThreshold = 110
    self.enemySearchRadius = 200
    self.commandDelay = 10
    self.followVelocity = 3
    self.followVelocityThreshold = 250

    return self
end

function aiCore.WingmanManager:AddObject(h)
    if not IsValid(h) or GetTeamNum(h) ~= self.teamNum then return end

    local cls = string.lower(GetClassLabel(h) or "")

    -- Wingmen
    if cls == "wingman" then
        self.wingmen[h] = {
            unit = h,
            lastCommandTime = 0,
            previousCommand = nil,
            previousTarget = nil,
            restorePriority = GetTeamNum(h) == 1 and GetCommandableAttackPriority() or GetUncommandablePriority()
        }
        if aiCore.Debug then
            print("Team " .. self.teamNum .. " added wingman: " .. GetOdf(h))
        end
        -- Depots and Pods
    elseif cls == "repairdepot" then
        self.repairDepots[h] = true
    elseif cls == "supplydepot" then
        self.supplyDepots[h] = true
    elseif cls == "repairkit" then
        self.repairPods[h] = true
    elseif cls == "ammopack" then
        self.ammoPods[h] = true
    end
end

function aiCore.WingmanManager:RemoveObject(h)
    self.wingmen[h] = nil
    self.repairDepots[h] = nil
    self.supplyDepots[h] = nil
    self.repairPods[h] = nil
    self.ammoPods[h] = nil
end

function aiCore.WingmanManager:Update()
    self.updateTimer = self.updateTimer + GetTimeStep()
    if self.updateTimer < self.checkPeriod then return end
    self.updateTimer = 0.0

    for h, entry in pairs(self.wingmen) do
        if not IsValid(h) or not IsAlive(h) then
            self.wingmen[h] = nil
        else
            self:UpdateWingman(entry)
        end
    end
end

function aiCore.WingmanManager:UpdateWingman(entry)
    local unit = entry.unit
    local health = GetHealth(unit)
    local ammo = GetAmmo(unit)
    local currentCommand = GetCurrentCommand(unit)

    -- Determine thresholds based on combat status
    local healthThreshold, ammoThreshold
    if self:IsInBattle(unit) then
        healthThreshold = 0.05 -- Only critical repairs in combat
        ammoThreshold = 0.025
    else
        healthThreshold = 0.75 -- More relaxed when safe
        ammoThreshold = 0.75
    end

    -- Calculate search radius based on follow state
    local searchRadii = self:GetSearchRadii(unit, currentCommand)

    -- Check if unit can act independently
    if self:CanSeekSupplies(unit, currentCommand, health, ammo) then
        local commandIssued = false

        -- Priority 1: Health (repair depot)
        if health <= healthThreshold then
            local depot = self:FindNearestRepairDepot(unit, searchRadii.depot)
            if depot and GetTime() >= entry.lastCommandTime + self.commandDelay then
                self:SavePreviousCommand(entry)
                aiCore.TrySetCommand(unit, AiCommand.GET_REPAIR, GetUncommandablePriority(), depot, nil, nil, nil,
                    { minInterval = 0.6, overrideProtected = true })
                entry.lastCommandTime = GetTime()
                commandIssued = true
            end
        end

        -- Priority 2: Ammo (supply depot)
        if not commandIssued and ammo <= ammoThreshold then
            local depot = self:FindNearestSupplyDepot(unit, searchRadii.depot)
            if depot and GetTime() >= entry.lastCommandTime + self.commandDelay then
                self:SavePreviousCommand(entry)
                aiCore.TrySetCommand(unit, AiCommand.GET_RELOAD, GetUncommandablePriority(), depot, nil, nil, nil,
                    { minInterval = 0.6, overrideProtected = true })
                entry.lastCommandTime = GetTime()
                commandIssued = true
            end
        end

        -- Fallback: Repair pods
        if not commandIssued and health <= healthThreshold then
            local pod = self:FindNearestRepairPod(unit, searchRadii.pod)
            if pod and GetTime() >= entry.lastCommandTime + self.commandDelay then
                if math.random() <= self.podChance then
                    self:SavePreviousCommand(entry)
                    aiCore.TrySetCommand(unit, AiCommand.GO, GetUncommandablePriority(), pod, nil, nil, nil,
                        { minInterval = 0.7 })
                    entry.lastCommandTime = GetTime()
                    commandIssued = true
                end
            end
        end

        -- Fallback: Ammo pods
        if not commandIssued and ammo <= ammoThreshold then
            local pod = self:FindNearestAmmoPod(unit, searchRadii.pod)
            if pod and GetTime() >= entry.lastCommandTime + self.commandDelay then
                if math.random() <= self.podChance then
                    self:SavePreviousCommand(entry)
                    aiCore.TrySetCommand(unit, AiCommand.GO, GetUncommandablePriority(), pod, nil, nil, nil,
                        { minInterval = 0.7 })
                    entry.lastCommandTime = GetTime()
                end
            end
        end
    end

    -- Restore command when done
    if self:ShouldRestoreCommand(unit, currentCommand, health, ammo, entry) then
        self:RestorePreviousCommand(entry)
    end
end

-- Helper: Is unit in battle?
function aiCore.WingmanManager:IsInBattle(unit)
    local enemy = GetNearestEnemy(unit)
    if enemy and GetDistance(enemy, unit) <= self.enemySearchRadius and IsCraft(enemy) then
        return true
    end
    local cmd = GetCurrentCommand(unit)
    if cmd == AiCommand.ATTACK or cmd == AiCommand.HUNT then
        return true
    end
    return false
end

-- Helper: Calculate pod/depot search radii based on follow state
function aiCore.WingmanManager:GetSearchRadii(unit, currentCommand)
    local podSearchRadius = self.podSearchRadius
    local depotSearchRadius = math.max(self.depotSearchRadius or self.podSearchRadius, self.podSearchRadius)

    if currentCommand == AiCommand.FOLLOW or currentCommand == AiCommand.DEFEND or currentCommand == AiCommand.FORMATION then
        local target = GetCurrentWho(unit)
        if IsValid(target) then
            local vel = GetVelocity(target) or { x = 0, y = 0, z = 0 }
            local velMag = math.sqrt(vel.x ^ 2 + vel.y ^ 2 + vel.z ^ 2)

            if velMag < self.followVelocity then
                podSearchRadius = math.min(self.podSearchRadius, self.followVelocityThreshold)
            else
                local movingFollowRadius = math.min(self.podSearchRadius, self.followThreshold * 0.8)
                podSearchRadius = movingFollowRadius
                depotSearchRadius = math.min(depotSearchRadius, movingFollowRadius)
            end
        end
    end

    return {
        pod = podSearchRadius,
        depot = depotSearchRadius,
    }
end

function aiCore.WingmanManager:GetSearchRadius(unit, currentCommand)
    local radii = self:GetSearchRadii(unit, currentCommand)
    return radii and radii.pod or self.podSearchRadius
end

-- Helper: Can unit seek supplies?
function aiCore.WingmanManager:CanSeekSupplies(unit, cmd, health, ammo)
    return cmd == AiCommand.NONE
        or cmd == AiCommand.FOLLOW
        or cmd == AiCommand.DEFEND
        or cmd == AiCommand.FORMATION
        or cmd == AiCommand.ATTACK
        or cmd == AiCommand.HUNT
        or cmd == AiCommand.PATROL
        or (cmd == AiCommand.GET_REPAIR and health >= 0.95)
        or (cmd == AiCommand.GET_RELOAD and ammo >= 0.95)
end

-- Helper: Should restore previous command?
function aiCore.WingmanManager:ShouldRestoreCommand(unit, cmd, health, ammo, entry)
    return (cmd == AiCommand.NONE
            or (cmd == AiCommand.GET_REPAIR and health >= 0.95)
            or (cmd == AiCommand.GET_RELOAD and ammo >= 0.95))
        and entry.previousCommand ~= nil
        and (entry.previousTarget == nil or IsValid(entry.previousTarget))
end

-- Helper: Save command
function aiCore.WingmanManager:SavePreviousCommand(entry)
    entry.previousCommand = GetCurrentCommand(entry.unit)
    entry.previousTarget = GetCurrentWho(entry.unit)
    entry.restorePriority = GetTeamNum(entry.unit) == 1 and GetCommandableAttackPriority() or GetUncommandablePriority()
end

-- Helper: Restore command
function aiCore.WingmanManager:RestorePreviousCommand(entry)
    if entry.previousCommand then
        aiCore.TrySetCommand(entry.unit, entry.previousCommand, entry.restorePriority, entry.previousTarget, nil,
            nil, nil, { minInterval = 0.5, overrideProtected = true })
        entry.previousCommand = nil
        entry.previousTarget = nil
        entry.restorePriority = nil
    end
end

-- Find nearest repair depot
function aiCore.WingmanManager:FindNearestRepairDepot(unit, searchRadius)
    local nearest = nil
    local closestDist = searchRadius

    for depot, _ in pairs(self.repairDepots) do
        if IsValid(depot) and (GetTeamNum(unit) == GetTeamNum(depot) or IsAlly(unit, depot)) then
            local dist = GetDistance(unit, depot)
            if dist < closestDist then
                closestDist = dist
                nearest = depot
            end
        end
    end

    return nearest
end

-- Find nearest supply depot
function aiCore.WingmanManager:FindNearestSupplyDepot(unit, searchRadius)
    local nearest = nil
    local closestDist = searchRadius

    for depot, _ in pairs(self.supplyDepots) do
        if IsValid(depot) and (GetTeamNum(unit) == GetTeamNum(depot) or IsAlly(unit, depot)) then
            local dist = GetDistance(unit, depot)
            if dist < closestDist then
                closestDist = dist
                nearest = depot
            end
        end
    end

    return nearest
end

-- Find nearest repair pod
function aiCore.WingmanManager:FindNearestRepairPod(unit, searchRadius)
    local nearest = nil
    local closestDist = searchRadius

    for pod, _ in pairs(self.repairPods) do
        if IsValid(pod) then
            local dist = GetDistance(unit, pod)
            local podHeight, _ = GetTerrainHeightAndNormal(pod)
            local podAboveGround = GetPosition(pod).y - podHeight

            if dist < closestDist and podAboveGround <= 5.0 then
                closestDist = dist
                nearest = pod
            end
        end
    end

    return nearest
end

-- Find nearest ammo pod
function aiCore.WingmanManager:FindNearestAmmoPod(unit, searchRadius)
    local nearest = nil
    local closestDist = searchRadius

    for pod, _ in pairs(self.ammoPods) do
        if IsValid(pod) then
            local dist = GetDistance(unit, pod)
            local podHeight, _ = GetTerrainHeightAndNormal(pod)
            local podAboveGround = GetPosition(pod).y - podHeight

            if dist < closestDist and podAboveGround <= 5.0 then
                closestDist = dist
                nearest = pod
            end
        end
    end

    return nearest
end

----------------------------------------------------------------------------------
-- GUARD MANAGER (from aiSpecial)
----------------------------------------------------------------------------------

----------------------------------------------------------------------------------
-- TEAM CLASS (The Brain)
----------------------------------------------------------------------------------
---@class aiCore.Team
---@field teamNum number
---@field faction number
---@field recyclerMgr aiCore.FactoryManager|nil
---@field factoryMgr aiCore.FactoryManager|nil
---@field constructorMgr aiCore.ConstructorManager|nil
---@field weaponMgr any
---@field cloakMgr any
---@field howitzerMgr any
---@field minelayerMgr any
---@field apcMgr any
---@field turretMgr any
---@field guardMgr any
---@field wingmanMgr any
---@field defenseMgr any
---@field depotMgr any
---@field recyclerBuildList table
---@field factoryBuildList table
---@field buildingList table
---@field strategy string
---@field strategyLocked boolean
---@field Config any
---@field combatUnits any
---@field scavengers any
---@field howitzers any
---@field howitzerGuards any
---@field apcs any
---@field minelayers any
---@field pilots any
---@field cloakers any
---@field mortars any
---@field thumpers any
---@field fields any
---@field turrets any
---@field doubleUsers any
---@field soldiers any
---@field tugHandles any
---@field pool any
---@field squads any
---@field guards any
---@field activeTugJobs any
---@field cargoJobs any
---@field assistedUnits any
---@field basePositions any
---@field enemyTargets any
---@field stealthState any
---@field offensiveRetaliation any
---@field offensiveRetaliationTimer number
---@field wreckerTimer number
---@field upgradeTimer number
---@field strategyTimer number
---@field weaponTimer number
---@field resourceBoostTimer number
---@field scavAssistTimer number
---@field techTimer number
---@field pilotResTimer number
---@field rescueTimer number
---@field paratrooperTimer number
---@field tugTimer number
---@field stickTimer number
---@field currentRescueVehicle any
---@field rescueAttemptExpiry number
aiCore.Team = {
    teamNum = 0,
    faction = 0,
    recyclerMgr = nil,
    factoryMgr = nil,
    constructorMgr = nil,

    -- Managers (Explicitly defined to satisfy linter)
    weaponMgr = nil,
    cloakMgr = nil,
    howitzerMgr = nil,
    minelayerMgr = nil,
    apcMgr = nil,
    turretMgr = nil,
    guardMgr = nil,
    wingmanMgr = nil,
    defenseMgr = nil,
    depotMgr = nil,

    -- Tactical Lists
    combatUnits = {},
    scavengers = {},
    howitzers = {},
    howitzerGuards = {},
    apcs = {},
    minelayers = {},
    pilots = {},   -- technicians/snipers
    cloakers = {}, -- CRA cloaked units
    thumpers = {}, -- Advanced Weapons
    mortars = {},
    fields = {},
    turrets = {}, -- Tracking for upgrades
    doubleUsers = {},
    soldiers = {},
    tugHandles = {},
    pool = {},
    squads = {},
    guards = {},

    -- Jobs / State
    activeTugJobs = {},
    cargoJobs = {},
    assistedUnits = {}, -- For StickToPlayer
    basePositions = {}, -- For AutoBuild
    enemyTargets = {},  -- prioritized list of enemy buildings
    offensiveRetaliation = {},
    offensiveRetaliationTimer = 0.0,
    strategicGoals = {},
    strategicGoalCache = {},
    strategicGoalTimer = 0.0,
    baseCenter = nil,
    baseCenterUpdateAt = 0.0,
    lastLaunchedGoalKey = nil,
    strategicMode = "balanced",
    strategicModeReason = "default",
    strategicModeTimer = 0.0,
    strategicModeStrategy = nil,
    scrapHotspots = {},
    scrapMemory = {},
    scrapHotspotTimer = 0.0,
    scrapTrackedUnits = {},
    scrapOrderState = {},
    scrapOutpostTimer = 0.0,
    producerDeployState = {},
    buildAccountWeights = {},
    buildAccountSpend = {},
    buildAccountTimer = 0.0,
    buildAccountUpdatedAt = 0.0,
    baseStrategy = "Balanced",

    -- Production Lists (Desired State)
    recyclerBuildList = {}, -- {priority = {odf="", handle=nil}}
    factoryBuildList = {},
    buildingList = {},      -- {priority = {odf="", handle=nil, path=""}}

    -- Tactics
    strategy = "Balanced",
    strategyLocked = false,
    Config = nil,

    -- Tactical State
    howitzerState = {}, -- {attacking=bool, outbound=bool, target=handle}
    wreckerTimer = 0,
    upgradeTimer = 0,
    strategyTimer = 0, -- For rotation
    weaponTimer = 0,   -- For mask cycling

    -- pilotMode State
    roleTimer = 0,
    rescueTimer = 0,
    currentRescueVehicle = nil,
    rescueAttemptExpiry = 0.0,
    tugTimer = 0,
    stickTimer = 0,

    -- Stealth Management (Legacy Misn12)
    stealthState = {
        discovered = false,
        warnings = 0,
        playerInVehicle = true,
        lastCheckPos = nil
    }
}
aiCore.Team.__index = aiCore.Team

---@return aiCore.Team
function aiCore.Team:new(teamNum, faction)
    ---@type aiCore.Team
    local t = setmetatable({}, self)
    t.teamNum = teamNum

    -- Configuration (Defaults)
    t.Config = {
        difficulty = 1,
        race = "nsdf",
        kc = 0,
        stratMultiplier = 1.0,
        autoBuild = true,

        -- Advanced Settings
        thumperChance = 10,
        mortarChance = 20,
        fieldChance = 10,
        doubleWeaponChance = 20,
        howitzerChance = 50,

        -- AI Behavior Settings
        soldierRange = 50,
        sniperSteal = true,
        pilotZeal = 0.4,
        sniperTraining = 75,
        sniperStealth = 0.5,
        sniperTimeout = 8.0,
        pilotEmergencyBarracksThreshold = 3,
        pilotEmergencyBarracksPriority = 3,
        pilotEmergencyCheckInterval = 6.0,
        flankFormationRushChance = 40, -- Chance a flank squad attacks in formation-rush mode
        flankAttackChance = 55, -- Chance a squad attempts a staged flank instead of direct attack
        resourceBoost = false,

        -- Timers
        upgradeInterval = 240,
        wreckerInterval = 600,
        techInterval = 60,
        techMax = 4,

        -- Toggles
        passiveRegen = false,
        autoManage = false,
        autoRepairWingmen = false,
        offensiveRetaliation = true,
        autoRescue = false,
        autoTugs = false,
        allowProducerRelocation = true,
        stickToPlayer = false,
        dynamicMinefields = false,
        scavengerAssist = false,

        -- Minefield positions
        minefields = {}, -- List of positions for minelayers

        -- Automation Sub-config
        followPercentage = 30,
        patrolPercentage = 30,
        guardPercentage = 40,
        scavengerCount = 4,
        tugCount = 2,
        buildingSpacing = 80,
        rescueDelay = 2.0,
        rescueAttemptTimeout = 20.0,
        pilotTopoff = 4,
        tacticalRecomputeInterval = 8.0,
        tacticalThreatPriority = 150.0,
        tacticalDistancePriority = 3.0,
        tacticalDefendBuildingsPriority = 30.0,
        tacticalAttackEnemyBasePriority = 75.0,
        tacticalPersistencePriority = 30.0,
        tacticalScriptedPriority = 50.0,
        tacticalMinMatchingForceRatio = 1.0,
        tacticalMaxMatchingForceRatio = 2.25,
        tacticalBuildingDefenseForceMin = 1.0,
        tacticalBuildingDefenseForceMax = 2.0,
        tacticalThreatRadius = 220.0,
        tacticalGoalRadius = 260.0,
        tacticalRelaxationCycles = 2,
        tacticalRelaxationStep = 180.0,
        tacticalRelaxationCoefficient = 0.45,
        tacticalMinSquadUnits = 3,
        tacticalMaxSquadUnits = 5,
        tacticalDefenseBias = 15.0,
        strategicFsmInterval = 18.0,
        strategicPressureThreshold = 4.0,
        strategicSiegeTime = 900.0,
        strategicRecoverScrapRatio = 0.22,
        strategicAttackRatio = 1.15,
        strategicRecoverRatio = 0.72,
        buildAccountBias = 2.2,
        buildAccountSpendDecay = 0.09,
        buildAccountSpendScale = 18.0,
        scrapAwareness = true,
        scrapHotspotInterval = 12.0,
        scrapHotspotRadius = 110.0,
        scrapHotspotMinValue = 8.0,
        scrapHotspotMemoryDuration = 120.0,
        scrapHotspotBattleWeight = 1.4,
        scrapHotspotSiloValue = 14.0,
        scrapHotspotSiloDropoffDistance = 260.0,
        scrapHotspotClaimRadius = 200.0,
        scrapHotspotExtraScavengerValue = 16.0,
        scrapHotspotExtraScavengerStep = 10.0,
        scrapHotspotMaxExtraScavengers = 3,
        scrapDenyRadius = 160.0,
        scrapHotspotOutpostValue = 24.0,
        scrapHotspotOutpostDropoffDistance = 330.0,
        scrapHotspotOutpostEnemyProducerRadius = 600.0,
        scrapHotspotOutpostContestedThreat = 2.5,
        scrapHotspotOutpostTowerCount = 2,
        scrapHotspotOutpostSupportRadius = 120.0,
        scrapHotspotOutpostCooldown = 10.0,
        tacticalEconomicPriority = 70.0,
        tacticalHotspotDenialPriority = 55.0,
        tacticalSiegePriority = 35.0,
        tacticalSiegeAvoidance = 18.0,
        tacticalSiegeForceFactor = 0.8,
        tacticalTargetRetentionPriority = 45.0,
        tacticalFormationOcclusionRadius = 35.0,
        tacticalFormationOcclusionDot = 0.92,
        strategicSiegeRiskThreshold = 5.5,
        baseCenterRefreshInterval = 4.0,
        basePlanMoveThreshold = 20.0,
        basePlanRecenterRadius = 360.0,
        producerDeployGrace = 18.0,

        -- Reinforcements
        orbitalReinforce = false,

        -- Legacy Features
        regenRate = 0.0,
        reclaimEngineers = false,

        -- Factory Management
        manageFactories = true, -- Default to true for AI teams
        manageConstructor = true,
        requireConstructorFirst = false,
        minScavengers = 0,
        unitCaps = {},
        slotCaps = {
            offense = 10,
            defense = 10,
            utility = 10,
            recycler = 1,
            factory = 1,
            armory = 1,
            constructor = 1
        },
        buildingCaps = {
            power = 7,
            comm = 7,
            repair = 7,
            supply = 7,
            silo = 7,
            barracks = 7,
            guntower = 7
        },

        -- Wreckers & Paratroopers
        enableWreckers = false,
        enableParatroopers = false,
        paratrooperChance = 0,
        paratrooperInterval = 600,

        -- Construction Defaults
        siloMinDistance = 250.0,
        siloMaxDistance = 450.0
    }

    -- Tactical Lists
    t.scavengers = {}
    t.howitzers = {}
    t.howitzerGuards = {}
    t.apcs = {}
    t.minelayers = {}
    t.cloakers = {}
    t.mortars = {}
    t.thumpers = {}
    t.fields = {}
    t.turrets = {}
    t.doubleUsers = {}
    t.soldiers = {}
    t.tugHandles = {}
    t.pool = {}
    t.squads = {}
    t.combatUnits = {}
    t.guards = {}
    t.offensiveRetaliation = {}
    t.offensiveRetaliationTimer = 0.0
    t.strategicGoals = {}
    t.strategicGoalCache = {}
    t.strategicGoalTimer = 0.0
    t.baseCenter = nil
    t.baseCenterUpdateAt = 0.0
    t.lastLaunchedGoalKey = nil
    t.strategicMode = "balanced"
    t.strategicModeReason = "default"
    t.strategicModeTimer = 0.0
    t.strategicModeStrategy = nil
    t.scrapHotspots = {}
    t.scrapMemory = {}
    t.scrapHotspotTimer = 0.0
    t.scrapTrackedUnits = {}
    t.scrapOrderState = {}
    t.scrapOutpostTimer = 0.0
    t.armorySuicideStates = {}
    t.producerDeployState = {}
    t.buildAccountWeights = { offense = 1.0, defense = 1.0, rebuild = 1.0, economy = 1.0 }
    t.buildAccountSpend = { offense = 0.0, defense = 0.0, rebuild = 0.0, economy = 0.0 }
    t.buildAccountTimer = 0.0
    t.buildAccountUpdatedAt = GetTime()
    t.baseStrategy = "Balanced"

    -- Tactical State
    t.howitzerState = {}
    t.wreckerTimer = GetTime() + (t.Config.wreckerInterval or 600)
    t.upgradeTimer = GetTime() + (t.Config.upgradeInterval or 240)
    t.strategyTimer = GetTime() + aiCore.Constants.STRATEGY_ROTATION_INTERVAL
    t.weaponTimer = GetTime() + 1.0
    t.resourceBoostTimer = GetTime() + 10.0
    t.scavAssistTimer = 0
    t.techTimer = 0
    t.pilotResTimer = 0
    t.rescueTimer = 0
    t.currentRescueVehicle = nil
    t.rescueAttemptExpiry = 0.0
    t.paratrooperTimer = 0

    t.stealthState = {
        discovered = false,
        warnings = 0,
        playerInVehicle = true,
        lastCheckPos = nil
    }

    if not faction then
        -- Simple detection based on recycler ODF
        local rec = GetRecyclerHandle(teamNum)
        if IsValid(rec) then
            local odf = GetOdf(rec)
            local char = string.sub(odf, 1, 1)
            if char == "a" then
                faction = 1
            elseif char == "s" then
                faction = 2
            elseif char == "c" then
                faction = 3
            elseif char == "b" then
                faction = 4
            end
        end
    end
    t.faction = faction or 1 -- Default to NSDF if unknown

    t.recyclerMgr = aiCore.FactoryManager:new(teamNum, true)
    t.recyclerMgr.teamObj = t    -- Bind reference
    t.factoryMgr = aiCore.FactoryManager:new(teamNum, false)
    t.factoryMgr.teamObj = t     -- Bind reference
    t.constructorMgr = aiCore.ConstructorManager:new(teamNum)
    t.constructorMgr.teamObj = t -- Bind reference

    -- Initialize Managers
    t.weaponMgr = aiCore.WeaponManager.new(teamNum)
    t.weaponMgr.teamObj = t -- Bind reference
    t.cloakMgr = aiCore.CloakingManager.new(teamNum)
    t.cloakMgr.teamObj = t
    t.howitzerMgr = aiCore.HowitzerManager.new(teamNum)
    t.howitzerMgr.teamObj = t
    t.minelayerMgr = aiCore.MinelayerManager.new(teamNum)
    t.minelayerMgr.teamObj = t
    t.apcMgr = aiCore.APCManager.new(teamNum)
    t.apcMgr.teamObj = t
    t.turretMgr = aiCore.TurretManager.new(teamNum)
    t.turretMgr.teamObj = t
    t.guardMgr = aiCore.GuardManager.new(teamNum)
    t.guardMgr.teamObj = t
    t.wingmanMgr = aiCore.WingmanManager.new(teamNum)
    t.wingmanMgr.teamObj = t
    t.defenseMgr = aiCore.DefenseManager.new(teamNum)
    t.defenseMgr.teamObj = t
    t.depotMgr = aiCore.DepotManager.new(teamNum)
    t.depotMgr.teamObj = t

    -- Initialize Integrated Producer Queue
    if not producer.Queue[teamNum] then producer.Queue[teamNum] = {} end

    t.recyclerBuildList = {}
    t.factoryBuildList = {}
    t.buildingList = {}

    t.lastFactoryDeployTime = 0
    return t
end

local function CopyVector(pos)
    if not pos then return nil end
    return SetVector(pos.x, pos.y, pos.z)
end

local function AddWeightedPosition(accum, pos, weight)
    if not pos or not weight or weight <= 0.0 then return end
    accum.x = accum.x + (pos.x * weight)
    accum.y = accum.y + (pos.y * weight)
    accum.z = accum.z + (pos.z * weight)
    accum.weight = accum.weight + weight
end

function aiCore.Team:GetProducerDeployGrace()
    return math.max(6.0, (self.Config and self.Config.producerDeployGrace) or 18.0)
end

function aiCore.Team:MarkProducerDeployGrace(h, now, command)
    if not IsValid(h) then return end
    self.producerDeployState = self.producerDeployState or {}
    self.producerDeployState[h] = self.producerDeployState[h] or {}
    local state = self.producerDeployState[h]
    state.holdUntil = (now or GetTime()) + self:GetProducerDeployGrace()
    state.command = command or GetCurrentCommand(h)
end

function aiCore.Team:ShouldDeferProducerDeploy(h, now)
    if not IsValid(h) then return false end

    self.producerDeployState = self.producerDeployState or {}
    local state = self.producerDeployState[h]
    if not state then
        state = { holdUntil = 0.0, command = AiCommand.NONE }
        self.producerDeployState[h] = state
    end

    if IsDeployed(h) then
        self.producerDeployState[h] = nil
        return false
    end

    local currentTime = now or GetTime()
    local cmd = GetCurrentCommand(h)
    if cmd == AiCommand.GO_TO_GEYSER or cmd == AiCommand.DEPLOY or cmd == AiCommand.UNDEPLOY then
        state.holdUntil = math.max(state.holdUntil or 0.0, currentTime + self:GetProducerDeployGrace())
        state.command = cmd
    end

    if currentTime < (state.holdUntil or 0.0) then
        return true
    end

    return false
end

function aiCore.Team:RefreshPlannedBaseStructures(previousCenter, newCenter)
    if not previousCenter or not newCenter then return end

    local delta = newCenter - previousCenter
    local moveDist = Length(delta)
    if moveDist < (self.Config.basePlanMoveThreshold or 20.0) then return end

    local localRadius = self.Config.basePlanRecenterRadius or 360.0

    local function ShiftPath(path)
        if type(path) == "string" or not path then return path end

        local isMatrixLike = path.posit_x ~= nil and path.posit_y ~= nil and path.posit_z ~= nil
        local pathPos = isMatrixLike and MatrixToPosition(path) or path
        if not pathPos then return path end
        if DistanceBetweenRefs(pathPos, previousCenter) > localRadius then return path end

        local shifted = SetVector(pathPos.x + delta.x, pathPos.y + delta.y, pathPos.z + delta.z)
        shifted.y = GetTerrainHeight(shifted.x, shifted.z)

        if isMatrixLike then
            local facing = Normalize(shifted - newCenter)
            if Length(facing) <= 0.01 then
                facing = aiCore.VecFacing.N
            end
            return aiCore.BuildDirectionalMatrix(shifted, facing)
        end

        return shifted
    end

    for _, item in pairs(self.buildingList or aiCore.EmptyList) do
        if item and not IsValid(item.handle) then
            item.path = ShiftPath(item.path)
        end
    end

    for _, qItem in ipairs(self.constructorMgr and self.constructorMgr.queue or aiCore.EmptyList) do
        if qItem and not IsValid(qItem.handle) then
            qItem.path = ShiftPath(qItem.path)
        end
    end
end

function aiCore.WeaponManager:UpdateMissileEfficiency(dt)
    local now = GetTime()
    if now < (self.missileUpdateAt or 0.0) then return end
    self.missileUpdateAt = now + (self.missileUpdatePeriod or 0.2)

    for i = #self.missileUsers, 1, -1 do
        local user = self.missileUsers[i]
        local h = user.handle
        if not IsValid(h) or not IsAlive(h) then
            self.missileClampState[h] = nil
            table.remove(self.missileUsers, i)
        else
            local state = self.missileClampState[h]
            local currentMask = GetCurrentWeaponMaskValue(h)
            if currentMask <= 0 then
                currentMask = GetDefaultWeaponMask(h)
            end

            local baseMask = currentMask
            if state and state.active and state.lastMask == currentMask and state.baseMask and state.baseMask > 0 then
                baseMask = state.baseMask
            end

            local target = GetCurrentWho(h)
            local validTarget = IsValid(target) and IsAlive(target) and not IsAlly(h, target)
            if not validTarget then
                if state and state.active and state.baseMask and state.baseMask > 0 then
                    SetWeaponMask(h, state.baseMask)
                end
                self.missileClampState[h] = nil
            else
                local targetHealth = GetUnitCurrentHealthPoints(target)
                if not targetHealth or targetHealth <= 0.0 then
                    if state and state.active and state.baseMask and state.baseMask > 0 then
                        SetWeaponMask(h, state.baseMask)
                    end
                    self.missileClampState[h] = nil
                else
                    local pendingDamage = aiCore.GetPendingMissileDamage(self.teamNum, target)
                    local neededDamage = (targetHealth * (self.missileKillBuffer or 1.1)) - pendingDamage
                    local selfPendingCount = aiCore.GetPendingMissileCountForShooter(h, target)

                    if user.missileMaxDamage and user.missileMaxDamage > 0.0 then
                        local lowHealthThreshold = user.missileMaxDamage * (self.missileKillBuffer or 1.1)
                        if targetHealth <= lowHealthThreshold and selfPendingCount >= 1 then
                            neededDamage = -1.0
                        end
                    end

                    local supportMask = RemoveMaskBits(baseMask, user.missileMask)
                    if supportMask <= 0 then
                        supportMask = user.supportMask or 0
                    end

                    if neededDamage <= 0.0 and user.missileOnly then
                        local alternateTarget = aiCore.FindMissileRetargetCandidate(h, target, self.teamNum,
                            self.missileRetargetRadius or 200.0, self.missileKillBuffer or 1.1)
                        if IsValid(alternateTarget) then
                            aiCore.TryAttack(h, alternateTarget, GetCommandableAttackPriority(),
                                { minInterval = 0.35, overrideProtected = true })
                            target = alternateTarget
                            targetHealth = GetUnitCurrentHealthPoints(target)
                            pendingDamage = aiCore.GetPendingMissileDamage(self.teamNum, target)
                            neededDamage = (targetHealth and targetHealth > 0.0)
                                and ((targetHealth * (self.missileKillBuffer or 1.1)) - pendingDamage)
                                or 0.0
                        end
                    end

                    local desiredMissileMask = 0
                    if neededDamage > 0.0 then
                        for _, slotInfo in ipairs(user.missileSlots) do
                            desiredMissileMask = MergeMaskBits(desiredMissileMask, slotInfo.mask)
                            neededDamage = neededDamage - (slotInfo.damage or 0.0)
                            if neededDamage <= 0.0 then
                                break
                            end
                        end
                    end

                    if supportMask <= 0 then
                        if desiredMissileMask <= 0 then
                            if state and state.active and state.baseMask and currentMask == state.lastMask then
                                SetWeaponMask(h, state.baseMask)
                            end
                            self.missileClampState[h] = nil
                        else
                            local desiredMask = desiredMissileMask
                            if desiredMask ~= baseMask then
                                SetWeaponMask(h, desiredMask)
                                self.missileClampState[h] = {
                                    active = true,
                                    baseMask = baseMask,
                                    lastMask = desiredMask,
                                }
                            else
                                if state and state.active and state.baseMask and currentMask == state.lastMask then
                                    SetWeaponMask(h, state.baseMask)
                                end
                                self.missileClampState[h] = nil
                            end
                        end
                    else
                        local desiredMask = MergeMaskBits(supportMask, desiredMissileMask)
                        if desiredMask ~= baseMask then
                            SetWeaponMask(h, desiredMask)
                            self.missileClampState[h] = {
                                active = true,
                                baseMask = baseMask,
                                lastMask = desiredMask,
                            }
                        else
                            if state and state.active and state.baseMask and currentMask == state.lastMask then
                                SetWeaponMask(h, state.baseMask)
                            end
                            self.missileClampState[h] = nil
                        end
                    end
                end
            end
        end
    end
end

function aiCore.Team:UpdateBaseCenter(force)
    local now = GetTime()
    if not force and now < (self.baseCenterUpdateAt or 0.0) then
        return self.baseCenter
    end

    self.baseCenterUpdateAt = now + (self.Config.baseCenterRefreshInterval or 4.0)

    local accum = { x = 0.0, y = 0.0, z = 0.0, weight = 0.0 }
    local recycler = GetRecyclerHandle(self.teamNum)
    local factory = GetFactoryHandle(self.teamNum)
    local armory = GetArmoryHandle(self.teamNum)
    local constructor = GetConstructorHandle(self.teamNum)

    local function AddRef(ref, weight)
        if IsValid(ref) and IsAlive(ref) then
            AddWeightedPosition(accum, GetPosition(ref), weight)
        end
    end

    AddRef(recycler, IsValid(recycler) and (IsDeployed(recycler) and 6.0 or 5.0) or 0.0)
    AddRef(factory, IsValid(factory) and (IsDeployed(factory) and 4.5 or 3.0) or 0.0)
    AddRef(armory, 2.0)

    for _, obj in ipairs(aiCore.GetCachedBuildings(self.teamNum)) do
        if IsValid(obj) and IsAlive(obj) and IsBuilding(obj) then
            local cls = string.lower(utility.CleanString(GetClassLabel(obj)))
            local weight = 1.0
            if cls == utility.ClassLabel.POWERPLANT or cls == utility.ClassLabel.SCRAP_SILO then
                weight = 0.75
            elseif cls == utility.ClassLabel.SUPPLY_DEPOT or cls == utility.ClassLabel.REPAIR_DEPOT then
                weight = 0.9
            end
            AddRef(obj, weight)
        end
    end

    if accum.weight <= 0.0 then
        AddRef(constructor, 1.5)
    end

    if accum.weight <= 0.0 then
        return self.baseCenter
    end

    local center = SetVector(accum.x / accum.weight, accum.y / accum.weight, accum.z / accum.weight)
    center.y = GetTerrainHeight(center.x, center.z)

    local previousCenter = self.baseCenter and CopyVector(self.baseCenter) or nil
    self.baseCenter = center
    self.basePositions = self.basePositions or {}
    self.basePositions.center = CopyVector(center)
    if IsValid(recycler) then self.basePositions.recycler = CopyVector(GetPosition(recycler)) end
    if IsValid(factory) then self.basePositions.factory = CopyVector(GetPosition(factory)) end
    if previousCenter then
        self:RefreshPlannedBaseStructures(previousCenter, center)
    end

    return self.baseCenter
end

function aiCore.Team:GetBaseCenter(force)
    return self:UpdateBaseCenter(force)
end

function aiCore.Team:GetBaseReference(force)
    local recycler = GetRecyclerHandle(self.teamNum)
    if IsValid(recycler) then return recycler end

    local factory = GetFactoryHandle(self.teamNum)
    if IsValid(factory) then return factory end

    return self:GetBaseCenter(force)
end

function aiCore.Team:UpdateOffensiveRetaliation()
    if self.Config.offensiveRetaliation == false then return end

    self.offensiveRetaliationTimer = (self.offensiveRetaliationTimer or 0.0) + GetTimeStep()
    if self.offensiveRetaliationTimer < 0.5 then return end
    self.offensiveRetaliationTimer = 0.0

    local now = GetTime()
    local retaliationCooldown = aiCore.GetRetaliationCooldown()
    for _, u in ipairs(self.combatUnits) do
        if IsValid(u) and IsAlive(u) then
            local cls = string.lower(utility.CleanString(GetClassLabel(u)))
            if string.find(cls, "wingman") or string.find(cls, "walker") then
                local state = self.offensiveRetaliation[u]
                if not state then
                    state = {
                        lastAmmo = GetCurAmmo(u),
                        lastHealth = GetCurHealth(u),
                        nextRetaliateTime = 0.0
                    }
                    self.offensiveRetaliation[u] = state
                end

                local curAmmo = GetCurAmmo(u)
                local curHealth = GetCurHealth(u)
                local cmd = GetCurrentCommand(u)
                local currentTarget = GetCurrentWho(u)
                local attacker = GetWhoShotMe(u)
                local justShot = (now - GetLastEnemyShot(u)) < 5.0
                local takingDamage = curHealth < (state.lastHealth - 0.01)
                local cmdPriority = GetCommandableAttackPriority()
                local canRetaliate = aiCore.CanRetaliateToAttacker(u, self.teamNum, cmd, currentTarget, attacker)

                if justShot and takingDamage and IsValid(attacker) and aiCore.IsMissileThreat(attacker) then
                    aiCore.TryDeployDecoy(u, 8.0)
                end

                local shouldRetaliate = false
                if self.teamNum == 1 then
                    shouldRetaliate = canRetaliate and justShot and aiCore.IsIdleRetaliationCommand(cmd)
                else
                    shouldRetaliate = canRetaliate and justShot and takingDamage
                end

                if now >= (state.nextRetaliateTime or 0.0) and shouldRetaliate then
                    if aiCore.TryAttack(u, attacker, cmdPriority, { minInterval = 0.4 }) then
                        state.nextRetaliateTime = now + retaliationCooldown
                    end
                end

                state.lastAmmo = curAmmo
                state.lastHealth = curHealth
            end
        end
    end

    for h, _ in pairs(self.offensiveRetaliation) do
        if not IsValid(h) or not IsAlive(h) then
            self.offensiveRetaliation[h] = nil
        end
    end
end

function aiCore.Team:SetStrategy(stratName)
    if self.strategyLocked then return end

    local appliedName = stratName
    local strat = aiCore.Strategies[stratName]
    if not strat then
        strat = aiCore.Strategies.Balanced
        appliedName = "Balanced"
    end
    self.strategy = appliedName
    if not self._applyingFsmStrategy then
        self.baseStrategy = appliedName
    end

    -- Reset Lists
    self.recyclerBuildList = {}
    self.factoryBuildList = {}
    self.recyclerMgr.queue = {}
    self.factoryMgr.queue = {}

    -- Populate Build Lists (Prioritized from back to front in the arrays)
    -- Recycler List
    for i = #strat.Recycler, 1, -1 do
        local unitType = strat.Recycler[i]
        local odf = aiCore.Units[self.faction][unitType]
        if odf then
            self:AddUnitToBuildList(self.recyclerBuildList, odf, i, unitType, "recycler")
        end
    end

    local recyclerOnlyTypes = {
        scout = true,
        turret = true
    }

    -- Factory List
    for i = #strat.Factory, 1, -1 do
        local unitType = strat.Factory[i]
        local odf = aiCore.Units[self.faction][unitType]
        if odf then
            if recyclerOnlyTypes[unitType] then
                -- Keep recycler-only units off the factory list, even if templates include them.
                local priority = i + #strat.Recycler
                while self.recyclerBuildList[priority] do
                    priority = priority + 1
                end
                self:AddUnitToBuildList(self.recyclerBuildList, odf, priority, unitType, "recycler")
            else
                self:AddUnitToBuildList(self.factoryBuildList, odf, i, unitType, "factory")
            end
        end
    end

    self.strategyHistory = self.strategyHistory or {}
    if #self.strategyHistory == 0 or self.strategyHistory[#self.strategyHistory] ~= appliedName then
        table.insert(self.strategyHistory, appliedName)
        if #self.strategyHistory > 6 then
            table.remove(self.strategyHistory, 1)
        end
    end

    if aiCore.Debug then print("Team " .. self.teamNum .. " strategy set to " .. appliedName) end
end

function aiCore.Team:SetCustomStrategy(stratData, locked)
    self.strategyLocked = false -- Temporarily unlock to apply
    aiCore.Strategies["__custom__" .. self.teamNum] = stratData
    self:SetStrategy("__custom__" .. self.teamNum)
    if locked ~= nil then self.strategyLocked = locked end
end

function aiCore.Team:SetMaintainList(recyclerUnits, factoryUnits, locked)
    local strat = { Recycler = {}, Factory = {} }

    if recyclerUnits then
        for type, count in pairs(recyclerUnits) do
            for i = 1, count do table.insert(strat.Recycler, type) end
        end
    end

    if factoryUnits then
        for type, count in pairs(factoryUnits) do
            for i = 1, count do table.insert(strat.Factory, type) end
        end
    end

    self:SetCustomStrategy(strat, locked)
end

function aiCore.Team:AddUnitToBuildList(list, odf, priority, category, producerType)
    list[priority] = {
        odf = odf,
        priority = priority,
        handle = nil,
        category = category,
        producer = producerType,
        account = self:GetBuildAccountForUnit(category, odf, producerType)
    }
end

function aiCore.Team:AddBuilding(odf, path, priority)
    if priority == nil then
        -- Default to lowest priority so explicit scripted priorities remain dominant.
        local hasPriority = false
        local lowestPriority = 1
        for p, _ in pairs(self.buildingList) do
            if type(p) == "number" then
                if not hasPriority or p < lowestPriority then
                    lowestPriority = p
                end
                hasPriority = true
            end
        end
        priority = hasPriority and (lowestPriority - 1) or 1
    else
        while self.buildingList[priority] do
            priority = priority + 1
        end
    end

    self.buildingList[priority] = {
        odf = odf,
        priority = priority,
        path = path,
        handle = nil,
        account = self:GetBuildAccountForBuilding(odf)
    }
end

-- Enhanced terrain validation (from pilotMode.lua)
-- Checks multiple points around a position to ensure area is flat enough
function aiCore.IsAreaFlat(centerPos, radius, checkPoints, flatThreshold, flatPercentage)
    -- Defaults for building placement
    radius = radius or 10
    checkPoints = checkPoints or 8
    flatThreshold = flatThreshold or 0.966  -- cos(15°) - strict for buildings
    flatPercentage = flatPercentage or 0.75 -- 75% of points must be flat

    -- Check center point first
    local centerHeight, centerNormal = GetTerrainHeightAndNormal(centerPos)
    if centerNormal.y < flatThreshold then
        return false, 0.0
    end

    -- Check points in a circle around center
    local flatPoints = 1 -- Center is flat
    local totalPoints = 1 + checkPoints

    for i = 0, checkPoints - 1 do
        local angle = (i / checkPoints) * 2 * math.pi
        local x = centerPos.x + radius * math.cos(angle)
        local z = centerPos.z + radius * math.sin(angle)
        local testPos = SetVector(x, centerPos.y, z)

        local height, normal = GetTerrainHeightAndNormal(testPos)

        if normal.y >= flatThreshold then
            flatPoints = flatPoints + 1
        end
    end

    local actualFlatPercentage = flatPoints / totalPoints
    local isFlat = actualFlatPercentage >= flatPercentage

    return isFlat, actualFlatPercentage
end

-- Find optimal location for silo near scrap (enhanced from pilotMode)
function aiCore.Team:FindOptimalSiloLocation(minDist, maxDist)
    minDist = minDist or self.Config.siloMinDistance or 250.0
    maxDist = maxDist or self.Config.siloMaxDistance or 450.0
    maxDist = math.max(maxDist, 500.0) -- Ensure broad search around base.
    if minDist > maxDist then
        local t = minDist
        minDist = maxDist
        maxDist = t
    end

    local recycler = GetRecyclerHandle(self.teamNum)
    local recPos = self:GetBaseCenter(true) or (IsValid(recycler) and GetPosition(recycler) or nil)
    if not recPos then return nil end
    local bestPos = nil
    local bestScrapDensity = 0
    local scrapScanRadius = 120
    local candidates = {}

    -- Primary candidates: positions near scrap clusters within a broad radius.
    local scrapCount = 0
    for obj in ObjectsInRange(maxDist, recPos) do
        if GetClassLabel(obj) == "scrap" then
            scrapCount = scrapCount + 1
            if scrapCount % 2 == 0 then
                local sPos = GetPosition(obj)
                table.insert(candidates, GetPositionNear(sPos, 25, 70))
            end
        end
    end

    -- Fallback ring samples to avoid dead-ends on sparse maps.
    for angle = 0, 345, 15 do
        local dist = minDist + math.random() * (maxDist - minDist)
        local rad = math.rad(angle)
        table.insert(candidates, SetVector(
            recPos.x + math.cos(rad) * dist,
            recPos.y,
            recPos.z + math.sin(rad) * dist
        ))
    end

    for _, testPos in ipairs(candidates) do
        local distToRec = DistanceBetweenRefs(testPos, recPos)
        if distToRec >= minDist and distToRec <= maxDist then
            testPos.y = GetTerrainHeight(testPos.x, testPos.z)
            local isFlat = aiCore.IsAreaFlat(testPos, 20, 6, 0.940, 0.70)
            if isFlat then
                local totalScrapValue = 0
                for obj in ObjectsInRange(scrapScanRadius, testPos) do
                    if GetClassLabel(obj) == "scrap" then
                        local d = GetDistance(obj, testPos)
                        local weight = 1.0 - (d / scrapScanRadius)
                        if d < 30.0 then weight = weight + 0.35 end -- Favor dense clusters.
                        totalScrapValue = totalScrapValue + weight
                    end
                end

                if totalScrapValue > bestScrapDensity then
                    bestScrapDensity = totalScrapValue
                    bestPos = testPos
                end
            end
        end
    end

    if aiCore.Debug and bestPos then
        print("Team " .. self.teamNum .. " found silo location with scrap density: " .. bestScrapDensity)
    end

    return bestPos
end

-- Check if building position has proper spacing from existing buildings
function aiCore.Team:CheckBuildingSpacing(odf, position, minSpacing)
    minSpacing = minSpacing or 85 -- Safer default for larger structures

    -- 1. Check against existing buildings in buildingList
    for _, building in pairs(self.buildingList) do
        if building.path and DistanceBetweenRefs(position, building.path) < minSpacing then
            return false, "Too close to planned building"
        end
        if IsValid(building.handle) and DistanceBetweenRefs(position, building.handle) < minSpacing then
            return false, "Too close to existing building"
        end
    end

    -- 2. Check against all buildings in range
    for obj in ObjectsInRange(minSpacing, position) do
        if IsBuilding(obj) and GetTeamNum(obj) == self.teamNum then
            -- Same type strict spacing
            if IsOdf(obj, odf) then
                return false, "Same type too close"
            end
            -- General crowding
            if GetDistance(obj, position) < (minSpacing * 0.8) then
                return false, "Area too crowded"
            end
        end
    end

    return true, "OK"
end

-- Get power range from ODF
function aiCore.Team:GetPowerRange(odf)
    local h = OpenODF(odf)
    if not h then return 200.0 end -- Default
    return GetODFFloat(h, "PowerPlantClass", "powerRange", 200.0)
end

-- Find a flat location for a base building
function aiCore.Team:FindFlatBaseLocation(odf, minDist, maxDist, spacing)
    local recycler = GetRecyclerHandle(self.teamNum)
    local recPos = self:GetBaseCenter(true) or (IsValid(recycler) and GetPosition(recycler) or nil)
    if not recPos then return nil end

    -- Relaxed loop: try to find a spot, increasing distance if needed
    local currentMax = maxDist
    local attempts = 0
    while attempts < 3 do
        for angle = 0, 360, 20 do
            local dist = minDist + math.random() * (currentMax - minDist)
            local rad = math.rad(angle)
            local testPos = SetVector(
                recPos.x + math.cos(rad) * dist,
                recPos.y,
                recPos.z + math.sin(rad) * dist
            )
            testPos.y = GetTerrainHeight(testPos.x, testPos.z)

            -- Check flatness and spacing
            local isFlat, _ = aiCore.IsAreaFlat(testPos, 15, 8, 0.95, 0.75)
            if isFlat then
                local ok, _ = self:CheckBuildingSpacing(odf, testPos, spacing)
                if ok then
                    return testPos
                end
            end
        end
        -- If not found, expand search
        minDist = currentMax
        currentMax = currentMax + 100
        attempts = attempts + 1
    end

    return nil
end

-- Base Planning Functions

function aiCore.Team:PlanPowerPlant(priority)
    local powerKey = aiCore.DetectWorldPower()
    local powerOdf = aiCore.Units[self.faction][powerKey] or aiCore.Units[self.faction].sPower
    local pos = self:FindFlatBaseLocation(powerOdf, 80, 150, 60)
    if pos then
        self:AddBuilding(powerOdf, pos, priority)
        return true
    end
    return false
end

function aiCore.Team:PlanGunTower(priority, powerHandle)
    local towerOdf = aiCore.Units[self.faction].gunTower
    local powerOdf = aiCore.Units[self.faction][aiCore.DetectWorldPower()] or aiCore.Units[self.faction].sPower
    local range = self:GetPowerRange(powerOdf)

    local centerPos
    if IsValid(powerHandle) then
        centerPos = GetPosition(powerHandle)
    else
        -- Fallback to finding a power plant
        local powerPlant = nil
        for _, obj in ipairs(aiCore.GetCachedBuildings(self.teamNum)) do
            if GetClassLabel(obj) == "powerplant" or IsOdf(obj, powerOdf) then
                powerPlant = obj
                break
            end
        end

        if powerPlant then
            centerPos = GetPosition(powerPlant)
        else
            -- Proactively plan power if none exists or is planned
            local powerPlanned = false
            for _, b in pairs(self.buildingList) do
                if b.odf == powerOdf then
                    powerPlanned = true; break
                end
            end
            if not powerPlanned then
                if aiCore.Debug then print("Team " .. self.teamNum .. ": No power for Gun Tower. Planning power.") end
                self:PlanPowerPlant(priority - 1)
            end
            return false
        end
    end

    if not centerPos then return false end

    -- Find spot within range of power, but away from base center
    local recycler = GetRecyclerHandle(self.teamNum)
    local recPos = IsValid(recycler) and GetPosition(recycler) or centerPos
    local dirToBase = Normalize(recPos - centerPos)

    for angle = 0, 360, 30 do
        local rad = math.rad(angle)
        local dist = 30 + math.random() * (range - 50) -- Keep well within range
        local testPos = SetVector(
            centerPos.x + math.cos(rad) * dist,
            centerPos.y,
            centerPos.z + math.sin(rad) * dist
        )
        testPos.y = GetTerrainHeight(testPos.x, testPos.z)

        local isFlat, _ = aiCore.IsAreaFlat(testPos, 10, 6, 0.94, 0.7)
        if isFlat then
            local ok, _ = self:CheckBuildingSpacing(towerOdf, testPos, 40)
            if ok then
                self:AddBuilding(towerOdf, testPos, priority)
                return true
            end
        end
    end
    return false
end

function aiCore.Team:PlanHangar(priority)
    local odf = aiCore.Units[self.faction].hangar
    local pos = self:FindFlatBaseLocation(odf, 130, 260, 120)
    if pos then
        self:AddBuilding(odf, pos, priority); return true
    end
    return false
end

function aiCore.Team:PlanSupplyDepot(priority)
    local odf = aiCore.Units[self.faction].supply
    local pos = self:FindFlatBaseLocation(odf, 120, 240, 110)
    if pos then
        self:AddBuilding(odf, pos, priority); return true
    end
    return false
end

function aiCore.Team:PlanCommTower(priority)
    local odf = aiCore.Units[self.faction].commTower
    local powerOdf = aiCore.Units[self.faction][aiCore.DetectWorldPower()] or aiCore.Units[self.faction].sPower
    local range = self:GetPowerRange(powerOdf)

    -- 1. Find existing power
    local powerPlant = nil
    for _, obj in ipairs(aiCore.GetCachedBuildings(self.teamNum)) do
        if GetClassLabel(obj) == "powerplant" or IsOdf(obj, powerOdf) then
            powerPlant = obj
            break
        end
    end

    if not powerPlant then
        -- Check if a power plant is already in the build list
        local powerPlanned = false
        for _, b in pairs(self.buildingList) do
            if b.odf == powerOdf then
                powerPlanned = true; break
            end
        end

        if not powerPlanned then
            if aiCore.Debug then print("Team " .. self.teamNum .. ": No power for Comm Tower. Planning power.") end
            self:PlanPowerPlant(priority - 1)
        end
        return false -- Wait for power to be built or planned
    end

    -- 2. Find spot near powerPlant
    local centerPos = GetPosition(powerPlant)
    local recycler = GetRecyclerHandle(self.teamNum)
    local recPos = IsValid(recycler) and GetPosition(recycler) or centerPos

    for angle = 0, 360, 30 do
        local rad = math.rad(angle)
        local dist = 30 + math.random() * (range - 60)
        local testPos = SetVector(
            centerPos.x + math.cos(rad) * dist,
            centerPos.y,
            centerPos.z + math.sin(rad) * dist
        )
        testPos.y = GetTerrainHeight(testPos.x, testPos.z)

        local isFlat, _ = aiCore.IsAreaFlat(testPos, 12, 8, 0.95, 0.75)
        if isFlat then
            local ok, _ = self:CheckBuildingSpacing(odf, testPos, 70)
            if ok then
                self:AddBuilding(odf, testPos, priority)
                return true
            end
        end
    end
    return false
end

function aiCore.Team:PlanBarracks(priority)
    local odf = aiCore.Units[self.faction].barracks
    local pos = self:FindFlatBaseLocation(odf, 80, 150, 60)
    if pos then
        self:AddBuilding(odf, pos, priority); return true
    end
    return false
end

function aiCore.Team:PlanHQ(priority)
    local odf = aiCore.Units[self.faction].hq
    local pos = self:FindFlatBaseLocation(odf, 150, 250, 100)
    if pos then
        self:AddBuilding(odf, pos, priority); return true
    end
    return false
end

function aiCore.Team:HasBuilding(typeKey)
    local odf = aiCore.Units[self.faction][typeKey]
    if not odf then return false end

    -- Check planned
    for _, b in pairs(self.buildingList) do
        if b.odf == odf then return true end
    end

    -- Check existing
    for _, obj in ipairs(aiCore.GetCachedBuildings(self.teamNum)) do
        if IsOdf(obj, odf) then
            return true
        end
    end

    return false
end

function aiCore.Team:ExpandBase()
    if not self.Config.autoBuild then return end

    -- Level 1: Core Infrastructure
    if not self:HasBuilding("barracks") then
        if self:PlanBarracks(10) then return end
    end

    if not self:HasBuilding("supply") then -- ODF key is 'supply' in aiCore.Units
        if self:PlanSupplyDepot(12) then return end
    end

    if not self:HasBuilding("commTower") then -- ODF key is 'commTower'
        if self:PlanCommTower(15) then return end
    end

    -- Level 2: Advanced Infrastructure
    if not self:HasBuilding("hangar") then
        if self:PlanHangar(20) then return end
    end

    if not self:HasBuilding("hq") then
        if self:PlanHQ(30) then return end
    end
end

-- ANALYZE ENEMY COMPOSITION
function aiCore.Team:AnalyzeEnemy()
    local counts = { scout = 0, tank = 0, missile = 0, bomber = 0, heavy = 0, defense = 0, siege = 0, apc = 0 }

    local enemyTeam = self:GetPrimaryEnemyTeam()
    if enemyTeam < 0 then
        enemyTeam = (self.teamNum == 1) and 2 or 1
    end

    for _, h in ipairs(aiCore.GetCachedTeamCraft(enemyTeam)) do
        if IsValid(h) and IsAlive(h) then
            local odfName = GetOdf(h)
            local odf = OpenODF(odfName)
            if odf then
                local unitName = string.lower(utility.CleanString(GetODFString(odf, "GameObjectClass", "unitName", "")))
                local classLabel = string.lower(utility.CleanString(GetODFString(odf, "GameObjectClass", "classLabel", "")))

                if classLabel == "wingman" then
                    if string.find(unitName, "scout") or string.find(unitName, "fighter") then
                        counts.scout = counts.scout + 1
                    elseif string.find(unitName, "rocket") or string.find(unitName, "missile") then
                        counts.missile = counts.missile + 1
                    elseif string.find(unitName, "bomber") then
                        counts.bomber = counts.bomber + 1
                    elseif string.find(unitName, "tank") or string.find(unitName, "light tank") then
                        counts.tank = counts.tank + 1
                    else
                        counts.tank = counts.tank + 1
                    end
                elseif classLabel == "walker" then
                    counts.heavy = counts.heavy + 1
                elseif classLabel == "apc" then
                    counts.apc = counts.apc + 1
                elseif classLabel == "howitzer" or classLabel == "artillery" then
                    counts.siege = counts.siege + 1
                elseif classLabel == "turrettank" or classLabel == "minelayer" then
                    counts.defense = counts.defense + 1
                end
            end
        end
    end

    -- Count static defenses
    for _, h in ipairs(aiCore.GetCachedBuildings(enemyTeam)) do
        if IsValid(h) and IsAlive(h) then
            local odfName = GetOdf(h)
            local odf = OpenODF(odfName)
            if odf then
                local classLabel = string.lower(utility.CleanString(GetODFString(odf, "GameObjectClass", "classLabel", "")))
                if classLabel == "turret" or string.find(classLabel, "tower") or classLabel == "gun tower" then
                    counts.defense = counts.defense + 1
                end
            end
        end
    end

    return counts
end

function aiCore.Team:GetPrimaryEnemyTeam()
    local player = GetPlayerHandle()
    local playerTeam = IsValid(player) and GetTeamNum(player) or -1
    local bestTeam = -1
    local bestScore = -1

    for team = 1, 15 do
        if team ~= self.teamNum and not IsTeamAllied(team, self.teamNum) then
            local score = 0
            score = score + #aiCore.GetCachedTeamCraft(team)
            score = score + (#aiCore.GetCachedBuildings(team) * 0.5)

            -- Bias toward the player team in campaign/single-player.
            if team == playerTeam then
                score = score + 3
            end

            if score > bestScore then
                bestScore = score
                bestTeam = team
            end
        end
    end

    return bestTeam
end

-- DETERMINE COUNTER STRATEGY
function aiCore.Team:GetCounterStrategy()
    local counts = self:AnalyzeEnemy()

    -- Priority 1: Fast Units or Walkers -> Rocket Heavy (Sensitive to lock-on)
    if counts.scout >= 4 or counts.heavy >= 2 then
        return "Rocket_Heavy"
    end

    -- Priority 2: APC Spam -> Minelayer, APC, or Bomber
    if counts.apc >= 3 then
        return "Anti_APC_Spam"
    end

    -- Priority 3: Siege (Static defenses) -> Howitzer, APC, or Bomber
    if counts.defense >= 3 then
        return "Siege_Counter"
    end

    -- Priority 4: Howitzer Spam -> Scout, Tank, Bomber heavy pushback
    if counts.siege >= 2 then
        return "Howitzer_Counter"
    end

    -- Priority 5: Tanks -> Tank Heavy (Trade blows equally)
    if counts.tank >= 4 then
        return "Tank_Heavy"
    end

    return nil
end

-- ECONOMY RAIDER LOGIC
function aiCore.Team:UpdateRaiders()
    -- Only run occasionally
    if not self.raiderTimer then self.raiderTimer = 0 end
    if GetTime() < self.raiderTimer then return end
    self.raiderTimer = GetTime() + 15.0

    local enemyTeam = self:GetPrimaryEnemyTeam()
    if enemyTeam < 0 then enemyTeam = (self.teamNum == 1) and 2 or 1 end

    local denyTargets = {}
    for _, hotspot in ipairs(self.scrapHotspots or aiCore.EmptyList) do
        if IsValid(hotspot.denyTarget) then
            table.insert(denyTargets, hotspot.denyTarget)
        end
    end

    if #denyTargets == 0 then
        for h in AllCraft() do
            if IsValid(h) and IsAlive(h) and GetTeamNum(h) == enemyTeam and string.find(string.lower(GetClassLabel(h)), "scavenger") then
                table.insert(denyTargets, h)
            end
        end
    end

    if #denyTargets > 0 and #self.pool > 0 then
        -- Detach unit from pool to hunt
        local raider = nil
        -- Prefer Scouts, then Tanks
        for i, u in ipairs(self.pool) do
            if IsValid(u) and GetCurrentCommand(u) == AiCommand.NONE then
                local label = string.lower(GetClassLabel(u))
                if string.find(label, "wingman") or string.find(label, "scout") then
                    raider = table.remove(self.pool, i)
                    break
                end
            end
        end

        if not raider and #self.pool > 0 then
            for i, u in ipairs(self.pool) do
                if IsValid(u) and GetCurrentCommand(u) == AiCommand.NONE then
                    raider = table.remove(self.pool, i)
                    break
                end
            end
        end

        if raider and IsValid(raider) then
            local target = denyTargets[math.random(#denyTargets)]
            if GetCurrentCommand(raider) ~= AiCommand.ATTACK or GetCurrentWho(raider) ~= target then
                aiCore.TryAttack(raider, target, GetCommandableAttackPriority(), { minInterval = 0.75 })
                if aiCore.Debug then
                    print("Team " .. self.teamNum .. " dispatching raider against scrap denial target.")
                end
            end
        end
    end
end

function aiCore.Team:UpdateRetreat()
    -- Check combat units for low health
    if not self.retreatTimer then self.retreatTimer = 0 end
    if GetTime() < self.retreatTimer then return end
    self.retreatTimer = GetTime() + 2.0

    -- Find a repair source
    local depot = nil
    if self.depotMgr then
        for h, data in pairs(self.depotMgr.depots) do
            if IsValid(h) and data.type == "repair" then
                depot = h
                break
            end
        end
    end

    if not depot then return end -- No repair depot, no retreat logic

    for _, u in ipairs(self.combatUnits) do
        if IsValid(u) and IsAlive(u) and not IsBuilding(u) then
            local health = GetHealth(u)
            local cmd = GetCurrentCommand(u)
            -- Retreat if critical and not already getting help
            if health < 0.25 and cmd ~= AiCommand.GET_REPAIR and cmd ~= AiCommand.GET_RELOAD then
                aiCore.TrySetCommand(u, AiCommand.GET_REPAIR, 1, depot, nil, nil, nil,
                    { minInterval = 0.7, overrideProtected = true })
            end
        end
    end
end

function aiCore.Team:Update()
    local now = GetTime()
    self:UpdateBaseCenter()
    self:UpdateStrategicFSM()

    if now >= (self.buildMaintenanceAt or 0.0) then
        self.buildMaintenanceAt = now + 0.35

        -- Replenish Queues from Build Lists
        self:CheckBuildList(self.recyclerBuildList, self.recyclerMgr)
        self:CheckBuildList(self.factoryBuildList, self.factoryMgr)
        self:CheckConstruction()
    end

    -- Manager Updates
    self.recyclerMgr:update()
    self.factoryMgr:update()
    self.constructorMgr:update()

    if now >= (self.producerProcessAt or 0.0) then
        self.producerProcessAt = now + 0.25
        -- MODIFIED: Process Integrated Production Queues
        producer.ProcessQueues(self)
    end

    -- Strategy rotation
    self:UpdateStrategyRotation()
    self:UpdateScrapAwareness()
    if self.Config.autoManage then self:UpdateRaiders() end

    -- Update Phase 1 Managers
    if self.weaponMgr then self.weaponMgr:Update() end
    if self.cloakMgr then self.cloakMgr:Update() end
    if self.howitzerMgr then self.howitzerMgr:Update() end
    if self.minelayerMgr then self.minelayerMgr:Update() end
    if self.apcMgr then self.apcMgr:Update() end

    -- MODIFIED: Only manage turrets/guards/defense if autoManage is enabled
    if self.Config.autoManage then
        if self.turretMgr then self.turretMgr:Update() end
        if self.guardMgr then self.guardMgr:Update() end
        if self.defenseMgr then self.defenseMgr:Update() end
    end

    if self.wingmanMgr and self.Config.autoRepairWingmen then self.wingmanMgr:Update() end
    if self.depotMgr then self.depotMgr:Update() end

    -- pilotMode Automations
    if self.Config.autoManage then self:UpdateUnitRoles() end
    if self.Config.autoManage then self:UpdateSquads() end
    if self.Config.autoRescue then self:UpdateRescue() end
    if self.Config.autoTugs then self:UpdateTugs() end
    if self.teamNum == 1 then self:UpdateStickToPlayer() end
    if self.Config.autoBuild then self:UpdateAutoBase() end
    if self.Config.autoManage then self:UpdateRetreat() end
    self:UpdateOffensiveRetaliation()

    -- Legacy Proximity/Maintenance
    if self.Config.dynamicMinefields then self:UpdateDynamicMinefields() end
    if self.Config.passiveRegen then self:UpdateRegen() end

    self:UpdateBaseMaintenance()
    self:UpdatePilotResources()
    self:UpdatePilots()
    self:UpdateResourceBoosting()
    self:UpdateUpgrades()
    self:UpdateWrecker()
    self:UpdateArmorySuicide()
    self:UpdateParatroopers()
    self:UpdateSoldiers()

    -- Scavenger Assist (Player QOL)
    if self.Config.scavengerAssist then self:UpdateScavengerAssist() end
end

function aiCore.Team:UpdateStickToPlayer()
    if self.teamNum ~= 1 then return end

    local assistStep = 0.15
    local now = GetTime()
    self.stickAssistState = self.stickAssistState or {}
    if not self.stickToPlayerTimer then self.stickToPlayerTimer = 0.0 end
    if now < self.stickToPlayerTimer then return end
    self.stickToPlayerTimer = now + assistStep

    local player = GetPlayerHandle()
    if not IsValid(player) or IsPerson(player) then
        self.stickAssistState = {}
        return
    end

    local pPos = GetPosition(player)
    local pVel = GetVelocity(player)
    local pFront = GetFront(player)
    if not pFront then pFront = Normalize(pVel) end
    pFront = Normalize(SetVector(pFront.x, 0, pFront.z))
    if pFront.x == 0 and pFront.y == 0 and pFront.z == 0 then
        pFront = SetVector(0, 0, 1)
    end

    local nextState = {}
    aiCore.RemoveDead(self.combatUnits)
    for _, u in ipairs(self.combatUnits) do
        if IsValid(u) and IsCraft(u) then
            local cmd = GetCurrentCommand(u)
            local target = GetCurrentWho(u)
            local cls = string.lower(utility.CleanString(GetClassLabel(u)))
            local isWingman = (cls == "wingman")
            local isPlayerAnchorOrder = target == player and
                (cmd == AiCommand.FOLLOW or cmd == AiCommand.FORMATION or cmd == AiCommand.DEFEND)
            local state = self.stickAssistState[u] or {
                lastDist = 999999.0,
                stuckTime = 0.0,
                nextSnapTime = 0.0,
                noMoveTime = 0.0,
                lastPos = nil,
                lastPlayerY = nil
            }
            nextState[u] = state

            -- Wingmen always get this QoL assist on player anchor orders.
            -- Other units keep the old behavior, gated behind stickToPlayer.
            if isPlayerAnchorOrder and (isWingman or self.Config.stickToPlayer) then
                local uPos = GetPosition(u)
                local dist = GetDistance(u, player)
                local assistRange = isWingman and 300.0 or 150.0
                local movement = math.huge
                if state.lastPos then
                    movement = Length(uPos - state.lastPos)
                end
                local progress = (state.lastDist or dist) - dist
                local verticalGap = pPos.y - uPos.y
                local playerVerticalDelta = state.lastPlayerY and (pPos.y - state.lastPlayerY) or 0.0
                local moveThreshold = isWingman and 3.5 or 1.8
                local farAway = dist > assistRange

                if farAway and movement < moveThreshold then
                    state.noMoveTime = (state.noMoveTime or 0.0) + assistStep
                else
                    state.noMoveTime = 0.0
                end

                local stuckAssist = farAway and (state.noMoveTime or 0.0) > (isWingman and 1.2 or 1.6)
                local elevationAssist = isWingman and
                    math.abs(verticalGap) > 18.0 and
                    dist > 80.0 and
                    (math.abs(playerVerticalDelta) > 5.0 or math.abs(progress) < 3.0)

                if stuckAssist or elevationAssist then
                    local shouldAssist = true

                    -- Don't interfere while the unit is actively fighting nearby threats.
                    local enemy = GetNearestEnemy(u)
                    if IsValid(enemy) and GetDistance(u, enemy) < 130 then
                        shouldAssist = false
                    end

                    if shouldAssist then
                        -- Pull toward a trailing anchor instead of the player's exact center.
                        local backOff = math.min(isWingman and 72.0 or 55.0, (isWingman and 26.0 or 32.0) + dist * 0.06)
                        local anchorPos = pPos - (pFront * backOff)
                        local anchorGround = GetTerrainHeight(anchorPos.x, anchorPos.z)
                        anchorPos.y = math.max(anchorGround + 1.0, math.min(pPos.y, anchorGround + 7.0))

                        local dir = Normalize(anchorPos - uPos)
                        local vel = GetVelocity(u)
                        local lookNear = uPos + (dir * 10.0)
                        local lookFar = uPos + (dir * 22.0)
                        local climbNear = math.max(0.0, GetTerrainHeight(lookNear.x, lookNear.z) - uPos.y)
                        local climbFar = math.max(0.0, GetTerrainHeight(lookFar.x, lookFar.z) - uPos.y)
                        local playerClimb = pPos.y - uPos.y
                        dir.y = Clamp(dir.y + (climbNear * 0.10) + (climbFar * 0.06) + (playerClimb * 0.02), -0.08, 0.18)
                        dir = Normalize(dir)

                        local desiredVel
                        local blend
                        if stuckAssist then
                            local catchupSpeed = math.min(isWingman and 44.0 or 24.0,
                                (isWingman and 13.0 or 8.0) + math.max(0.0, dist - assistRange) * (isWingman and 0.11 or 0.08))
                            local verticalVel = Clamp((anchorPos.y - uPos.y) * 0.14, -2.5, 4.0)
                            desiredVel = (pVel * (isWingman and 0.92 or 0.80)) +
                                (dir * catchupSpeed) +
                                SetVector(0, verticalVel, 0)
                            blend = isWingman and 0.62 or 0.38
                            if dist > 500 then
                                blend = blend + 0.10
                            end
                        else
                            local horizontalDir = Normalize(SetVector(dir.x, 0, dir.z))
                            local terrainPush = horizontalDir * (isWingman and 7.5 or 4.0)
                            local verticalVel = Clamp(verticalGap * 0.22, -4.0, 5.5)
                            desiredVel = (vel * 0.55) + (pVel * (isWingman and 0.45 or 0.30)) +
                                terrainPush +
                                SetVector(0, verticalVel, 0)
                            blend = isWingman and 0.26 or 0.18
                        end

                        SetVelocity(u, (vel * (1.0 - blend)) + (desiredVel * blend))

                        if stuckAssist and progress < 1.0 then
                            state.stuckTime = (state.stuckTime or 0.0) + assistStep
                        else
                            state.stuckTime = 0.0
                        end

                        if now >= (state.nextSnapTime or 0.0) and
                            (dist > 520.0 or (state.stuckTime > 1.2 and dist > 180.0)) then
                            local snapPos = anchorPos - (dir * (isWingman and 10.0 or 16.0))
                            snapPos.y = GetTerrainHeight(snapPos.x, snapPos.z) + 2.0
                            SetPosition(u, snapPos)
                            SetVelocity(u, desiredVel)
                            state.stuckTime = 0.0
                            state.noMoveTime = 0.0
                            state.nextSnapTime = now + 2.5
                        end

                        if aiCore.Debug and math.random() < 0.01 then
                            print("StickToPlayer Assist: " .. GetOdf(u) .. " dist=" .. math.floor(dist) ..
                                " stuck=" .. tostring(stuckAssist) .. " elev=" .. tostring(elevationAssist))
                        end
                    end
                else
                    state.stuckTime = 0.0
                    state.noMoveTime = 0.0
                end
                state.lastDist = dist
                state.lastPos = SetVector(uPos.x, uPos.y, uPos.z)
                state.lastPlayerY = pPos.y
            else
                state.stuckTime = 0.0
                state.noMoveTime = 0.0
                state.lastPos = nil
                state.lastPlayerY = nil
            end
        end
    end
    self.stickAssistState = nextState
end

function aiCore.Team:UpdateResourceBoosting()
    if not self.Config.resourceBoost then return end

    if GetTime() > (self.resourceBoostTimer or 0) then
        local m = DiffUtils.Get()
        -- Randomize next interval around 120s, scaled by timer difficulty
        local interval = DiffUtils.ScaleTimer(120.0) + math.random(-20, 40)
        self.resourceBoostTimer = GetTime() + interval

        local scrapBoost = math.floor(20 * m.enemy)
        local pilotBoost = math.floor(5 * m.enemy)

        AddScrap(self.teamNum, scrapBoost)
        AddPilot(self.teamNum, pilotBoost)

        if aiCore.Debug then
            print("Team " ..
                self.teamNum ..
                " resource boost: +" .. scrapBoost ..
                " scrap, +" .. pilotBoost .. " pilots (Next in " .. math.floor(interval) .. "s)")
        end
    end
end

function aiCore.Team:UpdateScavengerAssist()
    -- Initialize state table for multi-frame workaround
    if not self.scavengerResetState then self.scavengerResetState = {} end

    -- Process pending resets (Staggered over frames)
    for h, step in pairs(self.scavengerResetState) do
        if not IsValid(h) then
            self.scavengerResetState[h] = nil
        else
            if step == 1 then
                self.scavengerResetState[h] = nil
            end
        end
    end

    -- Check if it's time to issue new scavenge commands
    if (self.scavAssistTimer or 0) > GetTime() then return end
    self.scavAssistTimer = GetTime() + 15.0 -- Refresh every 5s

    if not self.scavengers then self.scavengers = {} end

    -- Clean dead
    aiCore.RemoveDead(self.scavengers)

    for _, h in ipairs(self.scavengers) do
        -- Only assist if not selected, not processing a reset, and valid
        if IsValid(h) and not IsSelected(h) and not self.scavengerResetState[h] then
            local cmd = GetCurrentCommand(h)

            if self.teamNum == 1 and SetIndependence then
                SetIndependence(h, 0)
            end

            if cmd == AiCommand.NONE or cmd == AiCommand.SCAVENGE then
                SetCommand(h, AiCommand.SCAVENGE, 0, nil, nil, nil, nil)
                aiCore.RecordCommand(h, AiCommand.SCAVENGE, nil)
                if self.teamNum == 1 and SetIndependence then
                    SetIndependence(h, 0)
                end
                self.scavengerResetState[h] = 1 -- One-frame guard to prevent double-trigger
            end
        end
    end
end

function aiCore.Team:RegisterScavenger(h)
    if not self.scavengers then self.scavengers = {} end
    UniqueInsert(self.scavengers, h)

    if not self.Config.scavengerAssist or not IsValid(h) then return end
    if self.teamNum == 1 and SetIndependence then
        SetIndependence(h, 0)
    end

    SetCommand(h, AiCommand.SCAVENGE, 0, nil, nil, nil, nil)
    aiCore.RecordCommand(h, AiCommand.SCAVENGE, nil)

    if self.teamNum == 1 and SetIndependence then
        SetIndependence(h, 0)
    end

    self.scavengerResetState = self.scavengerResetState or {}
    self.scavengerResetState[h] = 1
end

function aiCore.Team:UpdateBaseMaintenance()
    local now = GetTime()
    if now < (self.baseMaintenanceAt or 0.0) then return end
    self.baseMaintenanceAt = now + 1.0

    -- Ensure critical units exist (Constructor, Factory, Armory)
    -- Only runs if we have a Recycler
    local recycler = GetRecyclerHandle(self.teamNum)
    if not IsValid(recycler) then return end
    if not self.Config.autoBuild then return end
    self.recyclerMgr.handle = recycler

    local function NormalizeOdfKey(odf)
        if type(odf) ~= "string" then return "" end
        return string.lower(utility.CleanString(odf))
    end

    local queuedOdFs = {}
    local function MarkQueued(list)
        for i = 1, #(list or aiCore.EmptyList) do
            local item = list[i]
            local odfKey = NormalizeOdfKey(item and (item.odf or item))
            if odfKey ~= "" then
                queuedOdFs[odfKey] = true
            end
        end
    end
    MarkQueued(self.recyclerMgr.queue)
    if self.constructorMgr then
        MarkQueued(self.constructorMgr.queue)
    end
    for _, item in pairs(self.buildingList or aiCore.EmptyList) do
        local odfKey = NormalizeOdfKey(item and (item.odf or item))
        if odfKey ~= "" then
            queuedOdFs[odfKey] = true
        end
    end

    local function QueueProducerIfMissing(handle, odf, priority)
        local odfKey = NormalizeOdfKey(odf)
        if IsValid(handle) or odfKey == "" or queuedOdFs[odfKey] then
            return false
        end
        self.recyclerMgr:addUnit(odf, priority)
        return true
    end

    local function DeployProducerIfReady(handle, command)
        if not IsValid(handle) or IsDeployed(handle) or IsBusy(handle) then
            return false
        end
        if GetCurrentCommand(handle) == command then
            return false
        end
        return aiCore.TrySetCommand(handle, command, GetUncommandablePriority(), nil, nil, nil, nil,
            { minInterval = 1.0, overrideProtected = true })
    end

    -- 1. Constructor
    local constructor = GetConstructorHandle(self.teamNum)
    self.constructorMgr.handle = constructor
    if self.Config.manageConstructor and not IsValid(constructor) then
        local odf = aiCore.Units[self.faction].constructor
        if odf and QueueProducerIfMissing(constructor, odf, 0) then
            if aiCore.Debug then print("Team " .. self.teamNum .. " ordering replacement Constructor.") end
        end
    end

    if not self.Config.manageFactories then return end

    -- 2. Factory
    local factory = GetFactoryHandle(self.teamNum)
    self.factoryMgr.handle = factory
    if IsValid(factory) then
        local allowRelocation = self.Config.allowProducerRelocation ~= false
        local deployCommand = allowRelocation and AiCommand.GO_TO_GEYSER or AiCommand.DEPLOY
        local deferDeploy = self:ShouldDeferProducerDeploy(factory, now)
        if not deferDeploy and now >= (self.lastFactoryDeployTime or 0) + 10 then
            if DeployProducerIfReady(factory, deployCommand) then
                self:MarkProducerDeployGrace(factory, now, deployCommand)
                self.lastFactoryDeployTime = now
            end
        end
    else
        local odf = aiCore.Units[self.faction].factory
        if odf and QueueProducerIfMissing(factory, odf, 0) then
            if aiCore.Debug then print("Team " .. self.teamNum .. " ordering replacement Factory.") end
        end
    end

    -- 3. Armory
    local armory = GetArmoryHandle(self.teamNum)
    if IsValid(armory) then
        if now >= (self.lastArmoryDeployTime or 0) + 10 then
            if DeployProducerIfReady(armory, AiCommand.DEPLOY) then
                self.lastArmoryDeployTime = now
            end
        end
    else
        local odf = aiCore.Units[self.faction].armory
        if odf and QueueProducerIfMissing(armory, odf, 0.5) then
            if aiCore.Debug then print("Team " .. self.teamNum .. " ordering replacement Armory.") end
        end
    end
end

-- Configuration / Dynamic Difficulty Hooks

-- Setter for Difficulty Tweaking
function aiCore.Team:SetConfig(key, value)
    if self.Config[key] ~= nil then
        self.Config[key] = value
        if aiCore.Debug then print("Team " .. self.teamNum .. " config " .. key .. " set to " .. tostring(value)) end
    end
end

function aiCore.Team:SetMinefields(fields)
    -- fields can be a table of path names {"path1", "path2"}
    self.Config.minefields = fields
end

function aiCore.GetTeamCombatStrength(teamNum)
    local total = 0.0
    for _, obj in ipairs(aiCore.GetCachedTeamCraft(teamNum)) do
        if IsValid(obj) and IsAlive(obj) then
            total = total + aiCore.EstimateCombatStrength(obj)
        end
    end
    return total
end

function aiCore.Team:GetBuildAccountForUnit(category, odf, producerType)
    local normalized = string.lower(utility.CleanString(category or ""))
    local cleanOdf = string.lower(utility.CleanString(odf or ""))
    local units = aiCore.Units[self.faction] or {}

    if normalized == "scavenger" or normalized == "tug"
        or (units.scavenger and cleanOdf == string.lower(units.scavenger))
        or (units.tug and cleanOdf == string.lower(units.tug)) then
        return "economy"
    end
    if normalized == "constructor"
        or (units.constructor and cleanOdf == string.lower(units.constructor))
        or (units.factory and cleanOdf == string.lower(units.factory))
        or (units.armory and cleanOdf == string.lower(units.armory))
        or (units.recycler and cleanOdf == string.lower(units.recycler)) then
        return "rebuild"
    end
    if normalized == "tower" or normalized == "turret" or normalized == "minelayer" then
        return "defense"
    end
    if normalized == "scout" and producerType == "recycler" then
        return "defense"
    end
    if normalized == "howitzer" or normalized == "siege" then
        return "offense"
    end
    if normalized == "apc" or normalized == "bomber" or normalized == "tank" or normalized == "lighttank"
        or normalized == "rockettank" or normalized == "unique" or normalized == "heavy" or normalized == "walker" then
        return "offense"
    end
    return "offense"
end

function aiCore.Team:GetBuildAccountForBuilding(odf)
    local cleanOdf = string.lower(utility.CleanString(odf or ""))
    local units = aiCore.Units[self.faction] or {}
    local meta = aiCore.GetOdfMeta(cleanOdf)
    local classLabel = meta and meta.classLabel or ""

    if cleanOdf == string.lower(units.recycler or "")
        or cleanOdf == string.lower(units.factory or "")
        or cleanOdf == string.lower(units.armory or "")
        or cleanOdf == string.lower(units.constructor or "") then
        return "rebuild"
    end
    if cleanOdf == string.lower(units.silo or "")
        or cleanOdf == string.lower(units.supply or "")
        or cleanOdf == string.lower(units.power or "")
        or cleanOdf == string.lower(units.sPower or "")
        or cleanOdf == string.lower(units.barracks or "")
        or cleanOdf == string.lower(units.commTower or "")
        or cleanOdf == string.lower(units.hangar or "")
        or cleanOdf == string.lower(units.hq or "") then
        return "economy"
    end
    if cleanOdf == string.lower(units.repair or "")
        or cleanOdf == string.lower(units.howitzer or "")
        or cleanOdf == string.lower(units.turret or "")
        or cleanOdf == string.lower(units.gunTower or "") then
        return "defense"
    end

    if classLabel == utility.ClassLabel.RECYCLER
        or classLabel == utility.ClassLabel.FACTORY
        or classLabel == utility.ClassLabel.ARMORY
        or classLabel == utility.ClassLabel.CONSTRUCTOR then
        return "rebuild"
    end
    if classLabel == utility.ClassLabel.SCRAP_SILO
        or classLabel == utility.ClassLabel.SUPPLY_DEPOT
        or classLabel == utility.ClassLabel.POWERPLANT
        or classLabel == utility.ClassLabel.BARRACKS
        or classLabel == "commtower" then
        return "economy"
    end
    if classLabel == utility.ClassLabel.REPAIR_DEPOT
        or classLabel == utility.ClassLabel.HOWITZER
        or classLabel == utility.ClassLabel.TURRET
        or classLabel == utility.ClassLabel.TURRET_TANK then
        return "defense"
    end

    return "economy"
end

function aiCore.Team:GetRuleUnitRoleBucket(category, odf)
    local normalized = string.lower(utility.CleanString(category or ""))
    local cleanOdf = string.lower(utility.CleanString(odf or ""))
    local units = aiCore.Units[self.faction] or {}
    local meta = aiCore.GetOdfMeta(cleanOdf)
    local classLabel = meta and meta.classLabel or ""

    if normalized == "" then
        if units.scavenger and cleanOdf == string.lower(units.scavenger) then normalized = "scavenger" end
        if units.tug and cleanOdf == string.lower(units.tug) then normalized = "tug" end
        if units.apc and cleanOdf == string.lower(units.apc) then normalized = "apc" end
        if units.minelayer and cleanOdf == string.lower(units.minelayer) then normalized = "minelayer" end
        if units.howitzer and cleanOdf == string.lower(units.howitzer) then normalized = "howitzer" end
        if units.turret and cleanOdf == string.lower(units.turret) then normalized = "turret" end
        if units.gunTower and cleanOdf == string.lower(units.gunTower) then normalized = "tower" end
        if units.constructor and cleanOdf == string.lower(units.constructor) then normalized = "constructor" end
        if units.recycler and cleanOdf == string.lower(units.recycler) then normalized = "recycler" end
        if units.factory and cleanOdf == string.lower(units.factory) then normalized = "factory" end
        if units.armory and cleanOdf == string.lower(units.armory) then normalized = "armory" end
    end

    if normalized == "" then
        if classLabel == utility.ClassLabel.PERSON then
            normalized = meta and meta.personRole or "pilot"
        elseif classLabel == utility.ClassLabel.SCAVENGER then
            normalized = "scavenger"
        elseif classLabel == utility.ClassLabel.TUG then
            normalized = "tug"
        elseif classLabel == utility.ClassLabel.APC then
            normalized = "apc"
        elseif classLabel == utility.ClassLabel.MINELAYER then
            normalized = "minelayer"
        elseif classLabel == utility.ClassLabel.HOWITZER then
            normalized = "howitzer"
        elseif classLabel == utility.ClassLabel.TURRET or classLabel == utility.ClassLabel.TURRET_TANK then
            normalized = "turret"
        elseif classLabel == utility.ClassLabel.CONSTRUCTOR then
            normalized = "constructor"
        elseif classLabel == utility.ClassLabel.RECYCLER then
            normalized = "recycler"
        elseif classLabel == utility.ClassLabel.FACTORY then
            normalized = "factory"
        elseif classLabel == utility.ClassLabel.ARMORY then
            normalized = "armory"
        end
    end

    if normalized == "recycler" or normalized == "factory" or normalized == "armory" or normalized == "constructor" then
        return normalized
    end
    if normalized == "pilot" or normalized == "sniper" or normalized == "soldier" then
        return nil
    end
    if normalized == "scavenger" or normalized == "tug" or normalized == "apc" or normalized == "minelayer" then
        return "utility"
    end
    if normalized == "howitzer" or normalized == "siege" or normalized == "turret" or normalized == "tower" then
        return "defense"
    end
    if normalized ~= "" then
        return "offense"
    end
    return (cleanOdf ~= "") and "offense" or nil
end

function aiCore.Team:GetRuleUnitRoleBucketForHandle(h)
    if not IsValid(h) or not IsAlive(h) or not IsCraft(h) then return nil end

    local cls = string.lower(utility.CleanString(GetClassLabel(h)))
    if cls == utility.ClassLabel.RECYCLER then return "recycler" end
    if cls == utility.ClassLabel.FACTORY then return "factory" end
    if cls == utility.ClassLabel.ARMORY then return "armory" end
    if cls == utility.ClassLabel.CONSTRUCTOR then return "constructor" end
    if string.find(cls, utility.ClassLabel.SCAVENGER) or string.find(cls, utility.ClassLabel.TUG)
        or string.find(cls, utility.ClassLabel.APC) or string.find(cls, utility.ClassLabel.MINELAYER) then
        return "utility"
    end
    if string.find(cls, utility.ClassLabel.HOWITZER) or string.find(cls, utility.ClassLabel.TURRET)
        or string.find(cls, utility.ClassLabel.TURRET_TANK) then
        return "defense"
    end
    if string.find(cls, utility.ClassLabel.PERSON) then
        return nil
    end
    return "offense"
end

function aiCore.Team:GetRuleSlotCap(bucket)
    local caps = self.Config.slotCaps or aiCore.EmptyList
    return caps[bucket]
end

function aiCore.Team:GetRuleUnitRoleCount(bucket)
    if not bucket then return 0 end

    if bucket == "recycler" then
        return IsValid(GetRecyclerHandle(self.teamNum)) and 1 or 0
    elseif bucket == "factory" then
        local count = IsValid(GetFactoryHandle(self.teamNum)) and 1 or 0
        for _, job in ipairs((producer.Queue and producer.Queue[self.teamNum]) or aiCore.EmptyList) do
            if self:GetRuleUnitRoleBucket(job.data and job.data.category, job.odf) == bucket then
                count = count + 1
            end
        end
        return count
    elseif bucket == "armory" then
        local count = IsValid(GetArmoryHandle(self.teamNum)) and 1 or 0
        for _, job in ipairs((producer.Queue and producer.Queue[self.teamNum]) or aiCore.EmptyList) do
            if self:GetRuleUnitRoleBucket(job.data and job.data.category, job.odf) == bucket then
                count = count + 1
            end
        end
        return count
    elseif bucket == "constructor" then
        local count = IsValid(GetConstructorHandle(self.teamNum)) and 1 or 0
        for _, job in ipairs((producer.Queue and producer.Queue[self.teamNum]) or aiCore.EmptyList) do
            if self:GetRuleUnitRoleBucket(job.data and job.data.category, job.odf) == bucket then
                count = count + 1
            end
        end
        return count
    end

    local count = 0
    for _, obj in ipairs(aiCore.GetCachedTeamCraft(self.teamNum)) do
        if IsValid(obj) and IsAlive(obj) and self:GetRuleUnitRoleBucketForHandle(obj) == bucket then
            count = count + 1
        end
    end

    for _, job in ipairs((producer.Queue and producer.Queue[self.teamNum]) or aiCore.EmptyList) do
        if self:GetRuleUnitRoleBucket(job.data and job.data.category, job.odf) == bucket then
            count = count + 1
        end
    end

    return count
end

function aiCore.Team:GetRuleBuildingKey(odf, obj)
    local units = aiCore.Units[self.faction] or {}
    local cleanOdf = string.lower(utility.CleanString(odf or ""))
    local cls = obj and string.lower(utility.CleanString(GetClassLabel(obj))) or ""
    local meta = aiCore.GetOdfMeta(cleanOdf)
    local metaClass = meta and meta.classLabel or ""

    if cls == "" then
        cls = metaClass
    end

    if cls == utility.ClassLabel.RECYCLER or cleanOdf == string.lower(units.recycler or "") then return "recycler" end
    if cls == utility.ClassLabel.FACTORY or cleanOdf == string.lower(units.factory or "") then return "factory" end
    if cls == utility.ClassLabel.ARMORY or cleanOdf == string.lower(units.armory or "") then return "armory" end
    if cls == utility.ClassLabel.CONSTRUCTOR or cleanOdf == string.lower(units.constructor or "") then return "constructor" end
    if cls == utility.ClassLabel.POWERPLANT or cleanOdf == string.lower(units.power or "") or cleanOdf == string.lower(units.sPower or "") then return "power" end
    if cls == utility.ClassLabel.REPAIR_DEPOT or cleanOdf == string.lower(units.hangar or "") then return "repair" end
    if cls == utility.ClassLabel.SUPPLY_DEPOT or cleanOdf == string.lower(units.supply or "") then return "supply" end
    if cls == utility.ClassLabel.SCRAP_SILO or cleanOdf == string.lower(units.silo or "") then return "silo" end
    if cls == utility.ClassLabel.BARRACKS or cleanOdf == string.lower(units.barracks or "") then return "barracks" end
    if cls == "commtower" or cleanOdf == string.lower(units.commTower or "") then return "comm" end
    if cls == utility.ClassLabel.TURRET or cleanOdf == string.lower(units.gunTower or "") or cleanOdf == string.lower(units.gunTower2 or "") then return "guntower" end
    return nil
end

function aiCore.Team:GetRuleBuildingCap(key)
    if not key then return nil end
    if key == "recycler" or key == "factory" or key == "armory" or key == "constructor" then
        return (self.Config.slotCaps or aiCore.EmptyList)[key] or 1
    end
    return (self.Config.buildingCaps or aiCore.EmptyList)[key]
end

function aiCore.Team:GetRuleBuildingCount(key)
    if not key then return 0 end

    local count = 0
    for _, obj in ipairs(aiCore.GetCachedTeamTargets(self.teamNum)) do
        if IsValid(obj) and IsAlive(obj) and IsBuilding(obj) and self:GetRuleBuildingKey(GetOdf(obj), obj) == key then
            count = count + 1
        end
    end

    if key == "recycler" then
        if IsValid(GetRecyclerHandle(self.teamNum)) then count = math.max(count, 1) end
    elseif key == "factory" then
        if IsValid(GetFactoryHandle(self.teamNum)) then count = math.max(count, 1) end
    elseif key == "armory" then
        if IsValid(GetArmoryHandle(self.teamNum)) then count = math.max(count, 1) end
    elseif key == "constructor" then
        if IsValid(GetConstructorHandle(self.teamNum)) then count = math.max(count, 1) end
    end

    for _, qItem in ipairs(self.constructorMgr.queue or aiCore.EmptyList) do
        if self:GetRuleBuildingKey(qItem.odf) == key then
            count = count + 1
        end
    end
    if self.constructorMgr.activeJob and self:GetRuleBuildingKey(self.constructorMgr.activeJob.odf) == key then
        count = count + 1
    end

    return count
end

function aiCore.Team:CanQueueUnitByRules(category, odf)
    local bucket = self:GetRuleUnitRoleBucket(category, odf)
    local cap = self:GetRuleSlotCap(bucket)
    if bucket and cap and self:GetRuleUnitRoleCount(bucket) >= cap then
        return false, string.format("%s cap %d reached", bucket, cap)
    end
    return true, nil
end

function aiCore.Team:CanQueueBuildingByRules(odf)
    local key = self:GetRuleBuildingKey(odf)
    local cap = self:GetRuleBuildingCap(key)
    if key and cap and self:GetRuleBuildingCount(key) >= cap then
        return false, string.format("%s cap %d reached", key, cap)
    end
    return true, nil
end

function aiCore.Team:GetInfrastructureDeficit()
    local deficit = 0.0
    if not IsValid(GetRecyclerHandle(self.teamNum)) then deficit = deficit + 4.0 end
    if not IsValid(GetFactoryHandle(self.teamNum)) then deficit = deficit + 2.0 end
    if not IsValid(GetArmoryHandle(self.teamNum)) then deficit = deficit + 1.5 end
    if not IsValid(GetConstructorHandle(self.teamNum)) then deficit = deficit + 2.0 end
    return deficit
end

function aiCore.Team:GetStrategicPressureSummary()
    local defendPressure = 0.0
    local attackPressure = 0.0
    local bestDefend = 0.0
    local bestAttack = 0.0

    for _, goal in ipairs(self:RecomputeStrategicGoals(false)) do
        local value = (goal.threat or 0.0) + ((goal.scriptedValue or 0.0) * 0.5)
        if goal.mode == "defend" then
            defendPressure = defendPressure + value
            if value > bestDefend then bestDefend = value end
        else
            attackPressure = attackPressure + value + ((goal.enemyBuildings or 0.0) * 0.35)
            if value > bestAttack then bestAttack = value end
        end
    end

    return {
        defend = defendPressure,
        attack = attackPressure,
        peakDefend = bestDefend,
        peakAttack = bestAttack
    }
end

function aiCore.Team:ChooseModeStrategy(mode)
    local counter = self:GetCounterStrategy()
    local baseStrategy = self.baseStrategy or self.strategy or "Balanced"
    local scrapRatio = GetScrap(self.teamNum) / math.max(GetMaxScrap(self.teamNum), 1)

    if mode == "recover" then
        if counter == "Tank_Heavy" or counter == "Rocket_Heavy" then
            return counter
        end
        return "Balanced"
    end
    if mode == "defend" then
        return counter or "Tank_Heavy"
    end
    if mode == "harass" then
        if counter == "Rocket_Heavy" or counter == "APC_Heavy" then
            return counter
        end
        return "Light_Force"
    end
    if mode == "siege" then
        if scrapRatio > 0.55 then
            return "Howitzer_Heavy"
        end
        return "Bomber_Heavy"
    end
    if mode == "pressure" then
        return counter or baseStrategy
    end
    return counter or baseStrategy
end

function aiCore.Team:EvaluateStrategicMode()
    local enemyTeam = self:GetPrimaryEnemyTeam()
    if enemyTeam < 0 then enemyTeam = (self.teamNum == 1) and 2 or 1 end

    local ownStrength = aiCore.GetTeamCombatStrength(self.teamNum)
    local enemyStrength = aiCore.GetTeamCombatStrength(enemyTeam)
    local unitRatio = ownStrength / math.max(enemyStrength, 1.0)
    local scrapRatio = GetScrap(self.teamNum) / math.max(GetMaxScrap(self.teamNum), 1)
    local pressure = self:GetStrategicPressureSummary()
    local deficit = self:GetInfrastructureDeficit()
    local missionTime = GetTime()
    local hotspotScore = (self.scrapHotspots and self.scrapHotspots[1] and self.scrapHotspots[1].score) or 0.0
    local pressureThreshold = self.Config.strategicPressureThreshold or 4.0
    local bestSiege = 0.0

    for _, goal in ipairs(self:RecomputeStrategicGoals(false)) do
        if goal.mode == "attack" and (goal.siegeRisk or 0.0) > bestSiege then
            bestSiege = goal.siegeRisk or 0.0
        end
    end

    if deficit >= 3.5 or (scrapRatio <= (self.Config.strategicRecoverScrapRatio or 0.22) and unitRatio < 1.0)
        or unitRatio <= (self.Config.strategicRecoverRatio or 0.72) then
        return "recover",
            string.format("recover deficit=%.1f scrap=%.2f ratio=%.2f", deficit, scrapRatio, unitRatio)
    end

    if pressure.peakDefend >= pressureThreshold or pressure.defend >= (pressureThreshold * 1.5) then
        return "defend",
            string.format("defend pressure=%.2f ratio=%.2f", pressure.peakDefend, unitRatio)
    end

    if (missionTime >= (self.Config.strategicSiegeTime or 900.0) or bestSiege >= (self.Config.strategicSiegeRiskThreshold or 5.5))
        and unitRatio >= 0.95
        and pressure.attack >= (pressureThreshold * 0.8) then
        return "siege",
            string.format("siege t=%.0f attack=%.2f ratio=%.2f risk=%.2f", missionTime, pressure.attack, unitRatio, bestSiege)
    end

    if hotspotScore >= (self.Config.scrapHotspotMinValue or 8.0) and unitRatio >= 0.9 then
        return "harass",
            string.format("harass hotspot=%.2f ratio=%.2f", hotspotScore, unitRatio)
    end

    if unitRatio >= (self.Config.strategicAttackRatio or 1.15) and scrapRatio >= 0.30 then
        return "pressure",
            string.format("pressure ratio=%.2f scrap=%.2f", unitRatio, scrapRatio)
    end

    return "balanced",
        string.format("balanced ratio=%.2f scrap=%.2f defend=%.2f", unitRatio, scrapRatio, pressure.defend)
end

function aiCore.Team:UpdateBuildAccountState()
    self.buildAccountWeights = self.buildAccountWeights or { offense = 1.0, defense = 1.0, rebuild = 1.0, economy = 1.0 }
    self.buildAccountSpend = self.buildAccountSpend or { offense = 0.0, defense = 0.0, rebuild = 0.0, economy = 0.0 }

    local now = GetTime()
    local last = self.buildAccountUpdatedAt or now
    local delta = math.max(0.0, now - last)
    self.buildAccountUpdatedAt = now

    if delta > 0 then
        local decay = self.Config.buildAccountSpendDecay or 0.09
        local factor = math.exp(-decay * delta)
        for account, spent in pairs(self.buildAccountSpend) do
            self.buildAccountSpend[account] = math.max(0.0, (spent or 0.0) * factor)
        end
    end

    if now < (self.buildAccountTimer or 0.0) then
        return
    end
    self.buildAccountTimer = now + math.max(2.0, (self.Config.strategicFsmInterval or 18.0) * 0.25)

    local weights = { offense = 1.0, defense = 1.0, rebuild = 1.0, economy = 1.0 }
    local mode = self.strategicMode or "balanced"

    if mode == "recover" then
        weights.rebuild = 3.0
        weights.economy = 2.2
        weights.defense = 1.8
        weights.offense = 0.7
    elseif mode == "defend" then
        weights.defense = 2.8
        weights.rebuild = 1.8
        weights.economy = 1.2
        weights.offense = 0.9
    elseif mode == "harass" then
        weights.offense = 1.9
        weights.economy = 1.5
        weights.defense = 1.1
    elseif mode == "pressure" then
        weights.offense = 2.4
        weights.defense = 1.1
        weights.economy = 1.0
        weights.rebuild = 0.9
    elseif mode == "siege" then
        weights.offense = 2.6
        weights.defense = 1.0
        weights.economy = 0.9
        weights.rebuild = 0.9
    end

    local deficit = self:GetInfrastructureDeficit()
    if deficit > 0 then
        weights.rebuild = weights.rebuild + deficit
    end

    local pressure = self:GetStrategicPressureSummary()
    if pressure.defend > 0 then
        weights.defense = weights.defense + math.min(2.5, pressure.defend * 0.12)
    end

    local scrapRatio = GetScrap(self.teamNum) / math.max(GetMaxScrap(self.teamNum), 1)
    if scrapRatio < 0.25 then
        weights.economy = weights.economy + 0.7
        weights.offense = math.max(0.5, weights.offense - 0.25)
    end

    if self.Config.scrapAwareness and self.scrapHotspots and #self.scrapHotspots > 0 then
        weights.economy = weights.economy + 0.4
    end

    for account, value in pairs(weights) do
        self.buildAccountWeights[account] = math.max(0.25, value)
    end
end

function aiCore.Team:GetEffectiveBuildPriority(account, basePriority, data)
    self:UpdateBuildAccountState()

    local acct = account or (data and data.account) or "offense"
    local priority = tonumber(basePriority) or 999999
    local weight = (self.buildAccountWeights and self.buildAccountWeights[acct]) or 1.0
    local spent = (self.buildAccountSpend and self.buildAccountSpend[acct]) or 0.0
    local spendScale = self.Config.buildAccountSpendScale or 18.0
    local spendPenalty = spent / math.max(spendScale, 1.0)
    local weightBias = self.Config.buildAccountBias or 2.2

    return priority - ((weight - 1.0) * weightBias) + spendPenalty
end

function aiCore.Team:RecordBuildAccountSpend(account, amount)
    local acct = account or "offense"
    self.buildAccountSpend = self.buildAccountSpend or {}
    self.buildAccountSpend[acct] = (self.buildAccountSpend[acct] or 0.0) + math.max(0.0, amount or 0.0)
end

function aiCore.Team:UpdateStrategicFSM()
    if self.strategyLocked then
        self.strategicMode = self.strategicMode or "balanced"
        self:UpdateBuildAccountState()
        return
    end

    local now = GetTime()
    if now < (self.strategicModeTimer or 0.0) then
        return
    end
    self.strategicModeTimer = now + (self.Config.strategicFsmInterval or 18.0)

    local mode, reason = self:EvaluateStrategicMode()
    if mode ~= self.strategicMode then
        self.buildAccountTimer = 0.0
    end
    self.strategicMode = mode or "balanced"
    self.strategicModeReason = reason or "n/a"
    self.strategicModeStrategy = self:ChooseModeStrategy(self.strategicMode)
    self:UpdateBuildAccountState()

    if self.strategicModeStrategy and self.strategicModeStrategy ~= self.strategy then
        self._applyingFsmStrategy = true
        self:SetStrategy(self.strategicModeStrategy)
        self._applyingFsmStrategy = nil
    end
end

function aiCore.Team:AddStrategicGoal(ref, priority, minForce, maxForce, mode, radius)
    self.strategicGoals = self.strategicGoals or {}
    table.insert(self.strategicGoals, {
        ref = ref,
        priority = priority or 0.0,
        minForce = minForce,
        maxForce = maxForce,
        mode = mode or "attack",
        radius = radius or self.Config.tacticalGoalRadius or 260.0
    })
    self.strategicGoalTimer = 0.0
end

function aiCore.Team:AdjustRegionPriority(ref, priority, minForce, maxForce, mode, radius)
    self:AddStrategicGoal(ref, priority, minForce, maxForce, mode, radius)
end

function aiCore.Team:SetRegionPriority(ref, priority, minForce, maxForce, mode, radius)
    self:AddStrategicGoal(ref, priority, minForce, maxForce, mode, radius)
end

function aiCore.Team:ClearStrategicGoals()
    self.strategicGoals = {}
    self.strategicGoalCache = {}
    self.strategicGoalTimer = 0.0
    self.lastLaunchedGoalKey = nil
end

function aiCore.Team:GetEnemyThreatAtPosition(pos, enemyTeam, radius)
    if not pos then return 0.0, nil, 999999 end

    local bestThreat = nil
    local bestDist = 999999
    local total = 0.0
    radius = radius or self.Config.tacticalThreatRadius or 220.0

    for _, obj in ipairs(aiCore.GetCachedTeamTargets(enemyTeam)) do
        if IsValid(obj) and IsAlive(obj) and (IsCraft(obj) or IsBuilding(obj)) then
            local cls = string.lower(utility.CleanString(GetClassLabel(obj)))
            local canProjectThreat = IsCraft(obj)
                or string.find(cls, utility.ClassLabel.HOWITZER)
                or string.find(cls, utility.ClassLabel.TURRET)
                or string.find(cls, utility.ClassLabel.TURRET_TANK)
            if canProjectThreat then
                local d = DistanceBetweenRefs(obj, pos)
                if d <= radius then
                    total = total + aiCore.EstimateCombatStrength(obj)
                    if d < bestDist then
                        bestThreat = obj
                        bestDist = d
                    end
                end
            end
        end
    end

    return total, bestThreat, bestDist
end

function aiCore.Team:GetRelaxedThreatAtPosition(pos, enemyTeam, radius)
    local baseRadius = radius or self.Config.tacticalThreatRadius or 220.0
    local total, bestThreat, bestDist = self:GetEnemyThreatAtPosition(pos, enemyTeam, baseRadius)
    local cycles = math.max(0, math.floor(self.Config.tacticalRelaxationCycles or 0))
    local coeff = self.Config.tacticalRelaxationCoefficient or 0.0
    local step = self.Config.tacticalRelaxationStep or baseRadius

    if not pos or cycles <= 0 or coeff <= 0.0 then
        return total, bestThreat, bestDist
    end

    local maxRadius = baseRadius + (step * cycles)
    for _, obj in ipairs(aiCore.GetCachedTeamTargets(enemyTeam)) do
        if IsValid(obj) and IsAlive(obj) and (IsCraft(obj) or IsBuilding(obj)) then
            local cls = string.lower(utility.CleanString(GetClassLabel(obj)))
            local canProjectThreat = IsCraft(obj)
                or string.find(cls, utility.ClassLabel.HOWITZER)
                or string.find(cls, utility.ClassLabel.TURRET)
                or string.find(cls, utility.ClassLabel.TURRET_TANK)

            if canProjectThreat then
                local d = DistanceBetweenRefs(obj, pos)
                if d > baseRadius and d <= maxRadius then
                    local ring = math.ceil((d - baseRadius) / math.max(step, 1.0))
                    local bleed = coeff ^ math.max(ring, 1)
                    total = total + (aiCore.EstimateCombatStrength(obj) * bleed)
                    if bestThreat == nil or not IsValid(bestThreat) or d < bestDist then
                        bestThreat = obj
                        bestDist = d
                    end
                end
            end
        end
    end

    return total, bestThreat, bestDist
end

function aiCore.Team:CountBuildingsNearPosition(teamNum, pos, radius)
    if not pos then return 0 end
    local count = 0
    for _, obj in ipairs(aiCore.GetCachedTeamTargets(teamNum)) do
        if IsValid(obj) and IsAlive(obj) and IsBuilding(obj) and DistanceBetweenRefs(obj, pos) <= radius then
            count = count + 1
        end
    end
    return count
end

function aiCore.Team:GetBuildingGoalWeight(obj)
    if not IsValid(obj) then return 0 end
    local cls = string.lower(utility.CleanString(GetClassLabel(obj)))
    if string.find(cls, utility.ClassLabel.RECYCLER)
        or string.find(cls, utility.ClassLabel.FACTORY)
        or string.find(cls, utility.ClassLabel.ARMORY)
        or string.find(cls, utility.ClassLabel.CONSTRUCTOR) then
        return 3
    end
    if string.find(cls, utility.ClassLabel.REPAIR_DEPOT)
        or string.find(cls, utility.ClassLabel.SUPPLY_DEPOT)
        or string.find(cls, utility.ClassLabel.HOWITZER)
        or string.find(cls, utility.ClassLabel.TURRET)
        or string.find(cls, utility.ClassLabel.TURRET_TANK) then
        return 2
    end
    if string.find(cls, utility.ClassLabel.POWERPLANT)
        or string.find(cls, utility.ClassLabel.BARRACKS) then
        return 1.5
    end
    return 1
end

function aiCore.Team:GetEconomicTargetValue(obj, hotspotPos)
    if not IsValid(obj) or not IsAlive(obj) then return 0.0 end

    local cls = string.lower(utility.CleanString(GetClassLabel(obj)))
    local value = 0.0

    if string.find(cls, utility.ClassLabel.CONSTRUCTOR) then
        value = 5.5
    elseif cls == utility.ClassLabel.REPAIR_DEPOT or cls == utility.ClassLabel.SUPPLY_DEPOT then
        value = 5.0
    elseif cls == utility.ClassLabel.SCRAP_SILO or string.find(cls, "silo") then
        value = 4.5
    elseif cls == utility.ClassLabel.POWERPLANT then
        value = 3.75
    elseif cls == utility.ClassLabel.BARRACKS then
        value = 2.5
    elseif string.find(cls, utility.ClassLabel.RECYCLER)
        or string.find(cls, utility.ClassLabel.FACTORY)
        or string.find(cls, utility.ClassLabel.ARMORY) then
        value = 3.25
    end

    if hotspotPos and value > 0.0 and DistanceBetweenRefs(obj, hotspotPos) <= (self.Config.scrapDenyRadius or 160.0) then
        value = value + 1.75
    end

    return value
end

function aiCore.Team:GetHotspotDenialValue(pos)
    if not pos or not self.scrapHotspots then return 0.0 end

    local best = 0.0
    local radius = self.Config.scrapDenyRadius or 160.0
    for _, hotspot in ipairs(self.scrapHotspots) do
        local d = DistanceBetweenRefs(hotspot.position, pos)
        if d <= radius then
            local value = (hotspot.totalValue or 0.0) + ((hotspot.denyScore or 0.0) * 0.5)
            value = value * (1.0 - (d / math.max(radius, 1.0)))
            if value > best then
                best = value
            end
        end
    end

    return best
end

function aiCore.Team:GetSiegeRiskAtPosition(pos, enemyTeam, radius)
    if not pos then return 0.0 end

    local risk = 0.0
    radius = radius or (self.Config.tacticalThreatRadius or 220.0)

    for _, obj in ipairs(aiCore.GetCachedTeamTargets(enemyTeam)) do
        if IsValid(obj) and IsAlive(obj) and DistanceBetweenRefs(obj, pos) <= radius then
            local cls = string.lower(utility.CleanString(GetClassLabel(obj)))
            if cls == utility.ClassLabel.TURRET or string.find(cls, utility.ClassLabel.TURRET_TANK) then
                risk = risk + 1.5
            elseif string.find(cls, utility.ClassLabel.HOWITZER) then
                risk = risk + 2.0
            elseif cls == utility.ClassLabel.POWERPLANT then
                risk = risk + 0.85
            elseif string.find(cls, utility.ClassLabel.WALKER) then
                risk = risk + 1.75
            elseif IsCraft(obj) and (string.find(cls, utility.ClassLabel.RECYCLER) or string.find(cls, utility.ClassLabel.FACTORY)) and IsDeployed(obj) then
                risk = risk + 1.1
            end
        end
    end

    return risk
end

function aiCore.Team:FinalizeStrategicGoal(goal)
    local minRatio = self.Config.tacticalMinMatchingForceRatio or 1.0
    local maxRatio = self.Config.tacticalMaxMatchingForceRatio or 2.25
    local buildingMin = self.Config.tacticalBuildingDefenseForceMin or 1.0
    local buildingMax = self.Config.tacticalBuildingDefenseForceMax or 2.0
    local buildingWeight = (goal.friendlyBuildings or 0) + (goal.enemyBuildings or 0)

    local minForce = (goal.threat or 0.0) * minRatio + (buildingWeight * buildingMin)
    local maxForce = (goal.threat or 0.0) * maxRatio + (buildingWeight * buildingMax)

    if goal.mode == "attack" then
        minForce = math.max(minForce, 2.0)
        local siegeForce = (goal.siegeRisk or 0.0) * (self.Config.tacticalSiegeForceFactor or 0.8)
        minForce = minForce + siegeForce
        maxForce = maxForce + (siegeForce * 1.35)
    elseif goal.mode == "defend" then
        minForce = math.max(minForce, 1.5)
    end

    if goal.minForce then
        minForce = math.max(minForce, goal.minForce)
    end
    if goal.maxForce then
        maxForce = math.max(maxForce, goal.maxForce)
    end

    goal.requiredMinForce = minForce
    goal.requiredMaxForce = math.max(maxForce, minForce)
    return goal
end

function aiCore.Team:RecomputeStrategicGoals(force)
    local now = GetTime()
    if not force and now < (self.strategicGoalTimer or 0.0) and self.strategicGoalCache then
        return self.strategicGoalCache
    end

    local goals = {}
    local enemyTeam = self:GetPrimaryEnemyTeam()
    if enemyTeam < 0 then enemyTeam = (self.teamNum == 1) and 2 or 1 end
    local goalRadius = self.Config.tacticalGoalRadius or 260.0

    for _, obj in ipairs(aiCore.GetCachedTeamTargets(enemyTeam)) do
        if IsValid(obj) and IsAlive(obj) and IsBuilding(obj) then
            local pos = GetPosition(obj)
            local threat = 0.0
            local siegeRisk = 0.0
            if pos then
                threat = self:GetRelaxedThreatAtPosition(pos, enemyTeam, self.Config.tacticalThreatRadius or 220.0)
                siegeRisk = self:GetSiegeRiskAtPosition(pos, enemyTeam, (self.Config.tacticalThreatRadius or 220.0) * 1.1)
            end
            local hotspotDenial = self:GetHotspotDenialValue(pos)
            local economicValue = self:GetEconomicTargetValue(obj, pos)
            table.insert(goals, self:FinalizeStrategicGoal({
                key = obj,
                mode = "attack",
                target = obj,
                anchor = obj,
                position = pos,
                radius = goalRadius,
                threat = threat,
                friendlyBuildings = 0,
                enemyBuildings = self:GetBuildingGoalWeight(obj),
                scriptedValue = economicValue + hotspotDenial,
                economicValue = economicValue,
                hotspotDenial = hotspotDenial,
                siegeRisk = siegeRisk
            }))
        end
    end

    for _, obj in ipairs(aiCore.GetCachedTeamTargets(self.teamNum)) do
        if IsValid(obj) and IsAlive(obj) and IsBuilding(obj) then
            local pos = GetPosition(obj)
            local threat, attacker = self:GetRelaxedThreatAtPosition(pos, enemyTeam, self.Config.tacticalThreatRadius or 220.0)
            local healthRatio = Clamp((GetCurHealth(obj) or GetMaxHealth(obj) or 1.0) / math.max(GetMaxHealth(obj) or 1.0, 1.0), 0.0,
                1.0)
            local pressure = (1.0 - healthRatio) * 4.0
            if threat > 0.0 or pressure > 0.25 then
                table.insert(goals, self:FinalizeStrategicGoal({
                    key = "defend:" .. tostring(obj),
                    mode = "defend",
                    target = attacker,
                    anchor = obj,
                    position = pos,
                    radius = goalRadius,
                    threat = threat + pressure,
                    friendlyBuildings = self:GetBuildingGoalWeight(obj),
                    enemyBuildings = 0,
                    scriptedValue = pressure
                }))
            end
        end
    end

    for _, goal in ipairs(self.strategicGoals or aiCore.EmptyList) do
        local pos = ResolveReferencePosition(goal.ref)
        if pos then
            local threat, attacker = self:GetRelaxedThreatAtPosition(pos, enemyTeam, goal.radius or goalRadius)
            local enemyBuildings = self:CountBuildingsNearPosition(enemyTeam, pos, goal.radius or goalRadius)
            local friendlyBuildings = self:CountBuildingsNearPosition(self.teamNum, pos, goal.radius or goalRadius)
            local target = attacker
            local siegeRisk = self:GetSiegeRiskAtPosition(pos, enemyTeam, goal.radius or goalRadius)
            local hotspotDenial = self:GetHotspotDenialValue(pos)
            local economicValue = IsValid(goal.ref) and self:GetEconomicTargetValue(goal.ref, pos) or 0.0

            if goal.mode ~= "defend" and IsValid(goal.ref) then
                target = goal.ref
            end

            table.insert(goals, self:FinalizeStrategicGoal({
                key = GetStrategicRefKey(goal.ref),
                mode = goal.mode or "attack",
                target = target,
                anchor = goal.ref,
                position = pos,
                radius = goal.radius or goalRadius,
                threat = threat,
                friendlyBuildings = friendlyBuildings,
                enemyBuildings = enemyBuildings,
                scriptedValue = (goal.priority or 0.0) + hotspotDenial + economicValue,
                economicValue = economicValue,
                hotspotDenial = hotspotDenial,
                siegeRisk = siegeRisk,
                minForce = goal.minForce,
                maxForce = goal.maxForce
            }))
        end
    end

    self.strategicGoalCache = goals
    self.strategicGoalTimer = now + (self.Config.tacticalRecomputeInterval or 8.0)
    return goals
end

function aiCore.Team:ScoreStrategicGoal(goal, originRef, previousGoalKey)
    local goalPos = goal.position or ResolveReferencePosition(goal.anchor or goal.target)
    if not goalPos then return -999999 end

    local distance = DistanceBetweenRefs(originRef, goalPos)
    local score = 0.0
    score = score + ((self.Config.tacticalThreatPriority or 150.0) * (goal.threat or 0.0))
    score = score - ((self.Config.tacticalDistancePriority or 3.0) * (distance / 50.0))
    score = score + ((self.Config.tacticalDefendBuildingsPriority or 30.0) * (goal.friendlyBuildings or 0.0))
    score = score + ((self.Config.tacticalAttackEnemyBasePriority or 75.0) * (goal.enemyBuildings or 0.0))
    score = score + ((self.Config.tacticalScriptedPriority or 50.0) * (goal.scriptedValue or 0.0))
    score = score + ((self.Config.tacticalEconomicPriority or 70.0) * (goal.economicValue or 0.0))
    score = score + ((self.Config.tacticalHotspotDenialPriority or 55.0) * (goal.hotspotDenial or 0.0))

    if previousGoalKey ~= nil and previousGoalKey == goal.key then
        score = score + (self.Config.tacticalPersistencePriority or 30.0)
    end
    if self.lastLaunchedGoalKey ~= nil and self.lastLaunchedGoalKey == goal.key then
        score = score + ((self.Config.tacticalPersistencePriority or 30.0) * 0.5)
    end
    if goal.mode == "defend" then
        score = score + (self.Config.tacticalDefenseBias or 15.0)
    elseif (goal.siegeRisk or 0.0) > 0.0 then
        if self.strategicMode == "siege" then
            score = score + ((self.Config.tacticalSiegePriority or 35.0) * (goal.siegeRisk or 0.0))
        else
            score = score - ((self.Config.tacticalSiegeAvoidance or 18.0) * (goal.siegeRisk or 0.0))
        end
    end

    return score
end

function aiCore.Team:SelectStrategicGoal(originRef, availableStrength, opts)
    opts = opts or {}
    local bestGoal = nil
    local bestScore = -999999

    for _, goal in ipairs(self:RecomputeStrategicGoals(opts.forceRecompute)) do
        local includeGoal = true
        if opts.attackOnly and goal.mode ~= "attack" then includeGoal = false end
        if opts.defenseOnly and goal.mode ~= "defend" then includeGoal = false end

        if includeGoal then
            local requiredMin = goal.requiredMinForce or 0.0
            local enoughForce = opts.allowUnderstrength or availableStrength == nil or availableStrength >= requiredMin
            if enoughForce then
                local score = self:ScoreStrategicGoal(goal, originRef, opts.previousGoalKey)
                if score > bestScore then
                    bestGoal = goal
                    bestScore = score
                end
            end
        end
    end

    return bestGoal, bestScore
end

function aiCore.Team:GetPoolStrength()
    local total = 0.0
    for _, u in ipairs(self.pool) do
        local cls = string.lower(utility.CleanString(GetClassLabel(u)))
        if IsValid(u) and IsAlive(u) and not IsSpecializedPoolClass(cls) then
            total = total + aiCore.EstimateCombatStrength(u)
        end
    end
    return total
end

function aiCore.Team:BuildSquadFromPoolForGoal(goal)
    local ranked = {}
    for _, u in ipairs(self.pool) do
        local cls = string.lower(utility.CleanString(GetClassLabel(u)))
        if IsValid(u) and IsAlive(u) and not IsSpecializedPoolClass(cls) then
            table.insert(ranked, { unit = u, strength = aiCore.EstimateCombatStrength(u) })
        end
    end

    table.sort(ranked, function(a, b) return a.strength > b.strength end)

    local minUnits = self.Config.tacticalMinSquadUnits or 3
    local maxUnits = self.Config.tacticalMaxSquadUnits or 5
    local neededForce = goal and goal.requiredMinForce or 0.0
    local chosen = {}
    local totalStrength = 0.0

    for _, entry in ipairs(ranked) do
        table.insert(chosen, entry.unit)
        totalStrength = totalStrength + entry.strength
        if #chosen >= maxUnits then break end
        if #chosen >= minUnits and totalStrength >= neededForce then
            break
        end
    end

    if #chosen < minUnits then
        return nil, nil, 0.0
    end
    if goal and totalStrength + 0.01 < (goal.requiredMinForce or 0.0) then
        return nil, nil, totalStrength
    end

    for _, unit in ipairs(chosen) do
        RemoveFromList(self.pool, unit)
    end

    local leader = table.remove(chosen, 1)
    if not IsValid(leader) then
        for _, unit in ipairs(chosen) do
            UniqueInsert(self.pool, unit)
        end
        return nil, nil, 0.0
    end

    local squad = aiCore.Squad:new(leader)
    squad.teamObj = self
    squad.estimatedStrength = totalStrength
    for _, member in ipairs(chosen) do
        if IsValid(member) then
            squad:AddMember(member)
        end
    end

    return squad, leader, totalStrength
end

function aiCore.Team:ResolveStrategicGoalTarget(goalState)
    local mode = goalState.goalMode or goalState.mode or "attack"
    local anchor = goalState.goalAnchor or goalState.anchor
    local pos = goalState.goalPos or goalState.position or ResolveReferencePosition(anchor)
    local radius = goalState.goalRadius or goalState.radius or self.Config.tacticalGoalRadius or 260.0
    if not pos then return nil end

    local enemyTeam = self:GetPrimaryEnemyTeam()
    if enemyTeam < 0 then enemyTeam = (self.teamNum == 1) and 2 or 1 end

    local best = nil
    local bestScore = 999999
    for _, obj in ipairs(aiCore.GetCachedTeamTargets(enemyTeam)) do
        if IsValid(obj) and IsAlive(obj) and (IsCraft(obj) or IsBuilding(obj)) then
            local d = DistanceBetweenRefs(obj, pos)
            if mode ~= "defend" or d <= radius then
                local score = d
                if IsBuilding(obj) then score = score - 20.0 end
                if mode ~= "defend" then
                    score = score - ((self:GetEconomicTargetValue(obj, pos) or 0.0) * 55.0)
                    score = score - (self:GetHotspotDenialValue(GetPosition(obj)) * 40.0)
                end
                if mode == "defend" and not IsCraft(obj) then score = score + 40.0 end
                if score < bestScore then
                    best = obj
                    bestScore = score
                end
            end
        end
    end

    return best
end

function aiCore.Team:GetObjectScrapValue(obj)
    if not IsValid(obj) then return 0.0 end
    local odf = OpenODF(GetOdf(obj))
    if not odf then return 1.0 end
    local value = GetODFInt(odf, "GameObjectClass", "scrapValue", 0)
    if value <= 0 then
        value = GetODFInt(odf, "GameObjectClass", "scrapCost", 0)
    end
    return math.max(1.0, value)
end

function aiCore.Team:AddScrapMemory(pos, value, sourceTag)
    if not pos or value <= 0 then return end
    self.scrapMemory = self.scrapMemory or {}
    table.insert(self.scrapMemory, {
        position = SetVector(pos.x, pos.y, pos.z),
        value = value,
        source = sourceTag or "battle",
        expiresAt = GetTime() + (self.Config.scrapHotspotMemoryDuration or 120.0)
    })
end

function aiCore.Team:TrackCombatLossesForScrap()
    self.scrapTrackedUnits = self.scrapTrackedUnits or {}

    for h, state in pairs(self.scrapTrackedUnits) do
        if not IsValid(h) or not IsAlive(h) then
            if state.position and (state.strength or 0.0) >= 1.5 then
                self:AddScrapMemory(state.position, state.strength, "loss")
            end
            self.scrapTrackedUnits[h] = nil
        end
    end

    for _, u in ipairs(self.combatUnits or aiCore.EmptyList) do
        if IsValid(u) and IsAlive(u) then
            self.scrapTrackedUnits[u] = self.scrapTrackedUnits[u] or {}
            local state = self.scrapTrackedUnits[u]
            local pos = GetPosition(u)
            if pos then
                state.position = SetVector(pos.x, pos.y, pos.z)
                state.time = GetTime()
                state.strength = aiCore.EstimateCombatStrength(u)
            end
        end
    end
end

function aiCore.Team:GetNearestFriendlyScrapDropoff(pos)
    local best = nil
    local bestDist = 999999

    local recycler = GetRecyclerHandle(self.teamNum)
    if IsValid(recycler) then
        best = recycler
        bestDist = DistanceBetweenRefs(recycler, pos)
    end

    for _, obj in ipairs(aiCore.GetCachedTeamTargets(self.teamNum)) do
        if IsValid(obj) and IsAlive(obj) and IsBuilding(obj) then
            local cls = string.lower(utility.CleanString(GetClassLabel(obj)))
            if cls == utility.ClassLabel.SCRAP_SILO then
                local d = DistanceBetweenRefs(obj, pos)
                if d < bestDist then
                    best = obj
                    bestDist = d
                end
            end
        end
    end

    return best, bestDist
end

function aiCore.Team:HasPlannedSiloNear(pos, radius)
    local siloOdf = aiCore.Units[self.faction].silo
    if not siloOdf then return false end
    radius = radius or 120.0

    for _, building in pairs(self.buildingList) do
        if building.odf == siloOdf and DistanceBetweenRefs(building.path, pos) <= radius then
            return true
        end
    end
    for _, obj in ipairs(aiCore.GetCachedTeamTargets(self.teamNum)) do
        if IsValid(obj) and IsAlive(obj) and IsBuilding(obj) then
            local cls = string.lower(utility.CleanString(GetClassLabel(obj)))
            if (cls == utility.ClassLabel.SCRAP_SILO or IsOdf(obj, siloOdf)) and DistanceBetweenRefs(obj, pos) <= radius then
                return true
            end
        end
    end
    return false
end

function aiCore.Team:HasPlannedBuildingNear(odf, pos, radius)
    if not odf or not pos then return false end
    radius = radius or 120.0

    for _, building in pairs(self.buildingList) do
        if building.odf == odf and DistanceBetweenRefs(building.path, pos) <= radius then
            return true
        end
    end

    return false
end

function aiCore.Team:CountExistingOrPlannedBuildingsNear(pos, radius, matcher)
    if not pos or not matcher then return 0 end

    local count = 0
    for _, building in pairs(self.buildingList) do
        if DistanceBetweenRefs(building.path, pos) <= radius and matcher(building.odf, nil, true) then
            count = count + 1
        end
    end

    for _, obj in ipairs(aiCore.GetCachedTeamTargets(self.teamNum)) do
        if IsValid(obj) and IsAlive(obj) and IsBuilding(obj) and DistanceBetweenRefs(obj, pos) <= radius then
            if matcher(GetOdf(obj), obj, false) then
                count = count + 1
            end
        end
    end

    return count
end

function aiCore.Team:GetNearestEnemyProducerDistance(pos)
    local enemyTeam = self:GetPrimaryEnemyTeam()
    if enemyTeam < 0 then enemyTeam = (self.teamNum == 1) and 2 or 1 end

    local best = 999999
    local recycler = GetRecyclerHandle(enemyTeam)
    if IsValid(recycler) then
        best = math.min(best, DistanceBetweenRefs(recycler, pos))
    end

    local factory = GetFactoryHandle(enemyTeam)
    if IsValid(factory) then
        best = math.min(best, DistanceBetweenRefs(factory, pos))
    end

    if best >= 999999 then
        local enemyAi = aiCore.ActiveTeams and aiCore.ActiveTeams[enemyTeam] or nil
        local enemyCenter = enemyAi and enemyAi:GetBaseCenter(true) or nil
        if enemyCenter then
            best = math.min(best, DistanceBetweenRefs(enemyCenter, pos))
        end
    end

    return best
end

function aiCore.Team:FindOutpostStructureLocation(anchorPos, focusPos, odf, minDist, maxDist)
    if not anchorPos or not odf then return nil end

    minDist = minDist or 28.0
    maxDist = maxDist or 80.0
    local facingBase = focusPos or anchorPos

    for dist = minDist, maxDist, 12.0 do
        for angle = 0, 315, 45 do
            local rad = math.rad(angle)
            local testPos = SetVector(
                anchorPos.x + math.cos(rad) * dist,
                anchorPos.y,
                anchorPos.z + math.sin(rad) * dist
            )
            testPos.y = GetTerrainHeight(testPos.x, testPos.z)
            if aiCore.IsAreaFlat(testPos, 12, 6, 0.92, 0.65) and self:CheckBuildingSpacing(odf, testPos, 45) then
                return aiCore.BuildDirectionalMatrix(testPos, Normalize(facingBase - testPos))
            end
        end
    end

    return nil
end

function aiCore.Team:FindSiloLocationNearHotspot(centerPos)
    if not centerPos then return nil end
    local distances = { 25.0, 40.0, 55.0, 70.0 }

    for _, dist in ipairs(distances) do
        for angle = 0, 315, 45 do
            local rad = math.rad(angle)
            local testPos = SetVector(
                centerPos.x + math.cos(rad) * dist,
                centerPos.y,
                centerPos.z + math.sin(rad) * dist
            )
            testPos.y = GetTerrainHeight(testPos.x, testPos.z)
            local isFlat = aiCore.IsAreaFlat(testPos, 14, 6, 0.94, 0.68)
            if isFlat then
                local ok = self:CheckBuildingSpacing(aiCore.Units[self.faction].silo, testPos, 65)
                if ok then
                    return testPos
                end
            end
        end
    end

    return nil
end

function aiCore.Team:GetEnemyScrapDenyTarget(centerPos, radius)
    local enemyTeam = self:GetPrimaryEnemyTeam()
    if enemyTeam < 0 then enemyTeam = (self.teamNum == 1) and 2 or 1 end

    local best = nil
    local bestScore = -999999
    radius = radius or (self.Config.scrapDenyRadius or 160.0)

    for _, obj in ipairs(aiCore.GetCachedTeamTargets(enemyTeam)) do
        if IsValid(obj) and IsAlive(obj) and DistanceBetweenRefs(obj, centerPos) <= radius then
            local cls = string.lower(utility.CleanString(GetClassLabel(obj)))
            local score = -DistanceBetweenRefs(obj, centerPos)
            if string.find(cls, utility.ClassLabel.SCAVENGER) then
                score = score + 12.0
            elseif string.find(cls, utility.ClassLabel.CONSTRUCTOR) then
                score = score + 10.0
            elseif cls == utility.ClassLabel.SCRAP_SILO or string.find(cls, "silo") then
                score = score + 9.0
            elseif IsBuilding(obj) then
                score = score + 2.0
            end
            if score > bestScore then
                best = obj
                bestScore = score
            end
        end
    end

    return best, bestScore
end

function aiCore.Team:RefreshScrapHotspots()
    self.scrapHotspots = {}
    self.scrapMemory = self.scrapMemory or {}

    local now = GetTime()
    local survivors = {}
    for _, memory in ipairs(self.scrapMemory) do
        if now < (memory.expiresAt or 0.0) then
            table.insert(survivors, memory)
        end
    end
    self.scrapMemory = survivors

    local clusterRadius = self.Config.scrapHotspotRadius or 110.0
    local minValue = self.Config.scrapHotspotMinValue or 8.0
    local clusters = {}

    for _, obj in ipairs(aiCore.GetCachedScrapObjects()) do
        if IsValid(obj) and IsAlive(obj) then
            local pos = GetPosition(obj)
            local value = self:GetObjectScrapValue(obj)
            local chosen = nil
            for _, cluster in ipairs(clusters) do
                if DistanceBetweenRefs(cluster.position, pos) <= clusterRadius then
                    chosen = cluster
                    break
                end
            end

            if not chosen then
                chosen = {
                    position = SetVector(pos.x, pos.y, pos.z),
                    scrapValue = 0.0,
                    scrapCount = 0,
                    targetScrap = obj,
                    targetScrapValue = value,
                    scrapHandles = {}
                }
                table.insert(clusters, chosen)
            end

            chosen.scrapHandles[#chosen.scrapHandles + 1] = obj
            chosen.scrapValue = chosen.scrapValue + value
            chosen.scrapCount = chosen.scrapCount + 1
            if chosen.targetScrap == nil or not IsValid(chosen.targetScrap) or value > (chosen.targetScrapValue or 0.0) then
                chosen.targetScrap = obj
                chosen.targetScrapValue = value
            end

            local weight = value / math.max(chosen.scrapValue, 1.0)
            chosen.position = chosen.position + ((pos - chosen.position) * weight)
            chosen.position.y = GetTerrainHeight(chosen.position.x, chosen.position.z)
        end
    end

    for _, cluster in ipairs(clusters) do
        local battleValue = 0.0
        for _, memory in ipairs(self.scrapMemory) do
            if DistanceBetweenRefs(memory.position, cluster.position) <= (clusterRadius * 1.35) then
                battleValue = battleValue + (memory.value or 0.0)
            end
        end

        local enemyTeam = self:GetPrimaryEnemyTeam()
        if enemyTeam < 0 then enemyTeam = (self.teamNum == 1) and 2 or 1 end
        local _, dropoffDist = self:GetNearestFriendlyScrapDropoff(cluster.position)
        local denyTarget, denyScore = self:GetEnemyScrapDenyTarget(cluster.position)
        local enemyThreat = self:GetRelaxedThreatAtPosition(cluster.position, enemyTeam, self.Config.tacticalThreatRadius or 220.0)
        cluster.battleValue = battleValue
        cluster.dropoffDist = dropoffDist or 999999
        cluster.totalValue = cluster.scrapValue + (battleValue * (self.Config.scrapHotspotBattleWeight or 1.4))
        cluster.denyTarget = denyTarget
        cluster.denyScore = math.max(0.0, denyScore or 0.0)
        cluster.enemyThreat = enemyThreat or 0.0
        cluster.contested = IsValid(denyTarget) or (cluster.enemyThreat >= (self.Config.scrapHotspotOutpostContestedThreat or 2.5))
        cluster.score = cluster.totalValue - ((cluster.dropoffDist or 0.0) / 80.0)
        if IsValid(denyTarget) then
            cluster.score = cluster.score + 4.0
        end
        cluster.score = cluster.score + (cluster.denyScore * 0.35) + (cluster.enemyThreat * 0.5)

        if cluster.totalValue >= minValue then
            table.insert(self.scrapHotspots, cluster)
        end
    end

    table.sort(self.scrapHotspots, function(a, b) return (a.score or 0.0) > (b.score or 0.0) end)
end

function aiCore.Team:GetBestAvailableHotspotScrap(hotspot, seeker, claimed)
    if not hotspot or not seeker then return nil end

    local bestScrap = nil
    local bestDist = 999999
    for _, obj in ipairs(hotspot.scrapHandles or aiCore.EmptyList) do
        if IsValid(obj) and IsAlive(obj) and (not claimed or not claimed[obj]) then
            local d = DistanceBetweenRefs(seeker, obj)
            if d < bestDist then
                bestDist = d
                bestScrap = obj
            end
        end
    end

    if IsValid(bestScrap) then
        return bestScrap
    end

    if IsValid(hotspot.targetScrap) and IsAlive(hotspot.targetScrap) and (not claimed or not claimed[hotspot.targetScrap]) then
        return hotspot.targetScrap
    end

    return nil
end

function aiCore.Team:AssignScavengersToHotspots()
    if not self.scavengers or #self.scavengers == 0 then return end
    if not self.scrapHotspots or #self.scrapHotspots == 0 then return end

    self.scrapOrderState = self.scrapOrderState or {}
    local claimed = {}

    for _, hotspot in ipairs(self.scrapHotspots) do
        local assigned = 0
        local maxAssignments = math.min(3, math.max(1, math.floor((hotspot.totalValue or 0.0) / 8.0)))

        for _, scav in ipairs(self.scavengers) do
            if assigned >= maxAssignments then break end
            if IsValid(scav) and IsAlive(scav) and not IsSelected(scav) then
                local currentCmd = GetCurrentCommand(scav)
                local currentWho = GetCurrentWho(scav)
                local currentState = self.scrapOrderState[scav]
                local busyOnThisHotspot = currentState and currentState.hotspotPos and
                    DistanceBetweenRefs(currentState.hotspotPos, hotspot.position) <= 40.0 and
                    currentCmd == AiCommand.SCAVENGE and IsValid(currentWho)

                if busyOnThisHotspot then
                    assigned = assigned + 1
                elseif currentCmd == AiCommand.NONE or currentCmd == AiCommand.SCAVENGE or currentCmd == AiCommand.GO
                    or (currentCmd == AiCommand.SCAVENGE and not IsValid(currentWho)) then
                    local bestScrap = self:GetBestAvailableHotspotScrap(hotspot, scav, claimed)
                    if IsValid(bestScrap) then
                        if aiCore.TryScavenge(scav, bestScrap, GetUncommandablePriority(),
                                { minInterval = 1.0, overrideProtected = true }) then
                            claimed[bestScrap] = true
                            self.scrapOrderState[scav] = {
                                hotspotPos = hotspot.position,
                                target = bestScrap,
                                issuedAt = GetTime()
                            }
                            assigned = assigned + 1
                        end
                    end
                end
            end
        end
    end
end

function aiCore.Team:PlanHotspotOutpost()
    if not self.Config.autoBuild or not self.Config.manageConstructor then return end
    if not IsValid(self.constructorMgr.handle) or IsBusy(self.constructorMgr.handle) then return end
    if GetTime() < (self.scrapOutpostTimer or 0.0) then return end

    local units = aiCore.Units[self.faction] or {}
    local siloOdf = units.silo
    local powerOdf = units.power or units.sPower
    local repairOdf = units.repair
    local supplyOdf = units.supply
    local towerOdf = units.gunTower
    local supportRadius = self.Config.scrapHotspotOutpostSupportRadius or 120.0

    for _, hotspot in ipairs(self.scrapHotspots or aiCore.EmptyList) do
        local producerDist = self:GetNearestEnemyProducerDistance(hotspot.position)
        local richEnough = (hotspot.totalValue or 0.0) >= (self.Config.scrapHotspotOutpostValue or 24.0)
        local remoteEnough = (hotspot.dropoffDist or 0.0) >= (self.Config.scrapHotspotOutpostDropoffDistance or 330.0)
        local safeEnough = producerDist >= (self.Config.scrapHotspotOutpostEnemyProducerRadius or 600.0)

        if richEnough and remoteEnough and (safeEnough or hotspot.contested) then
            local anchor = hotspot.outpostAnchor
            if not anchor then
                anchor = self:FindSiloLocationNearHotspot(hotspot.position)
                hotspot.outpostAnchor = anchor
            end

            if anchor then
                local needSilo = not self:HasPlannedSiloNear(anchor, supportRadius)
                if needSilo and siloOdf then
                    self:AddBuilding(siloOdf, aiCore.BuildDirectionalMatrix(anchor, Normalize(hotspot.position - anchor)))
                    self.scrapOutpostTimer = GetTime() + (self.Config.scrapHotspotOutpostCooldown or 10.0)
                    return
                end

                if powerOdf then
                    local powerCount = self:CountExistingOrPlannedBuildingsNear(anchor, supportRadius,
                        function(odf, obj)
                            local cls = obj and string.lower(utility.CleanString(GetClassLabel(obj))) or ""
                            return (obj and cls == utility.ClassLabel.POWERPLANT) or odf == powerOdf
                        end)
                    if powerCount == 0 then
                        local powerPos = self:FindOutpostStructureLocation(anchor, hotspot.position, powerOdf, 30.0, 70.0)
                        if powerPos then
                            self:AddBuilding(powerOdf, powerPos)
                            self.scrapOutpostTimer = GetTime() + (self.Config.scrapHotspotOutpostCooldown or 10.0)
                            return
                        end
                    end
                end

                if hotspot.contested and repairOdf then
                    local repairCount = self:CountExistingOrPlannedBuildingsNear(anchor, supportRadius,
                        function(odf, obj)
                            local cls = obj and string.lower(utility.CleanString(GetClassLabel(obj))) or ""
                            return (obj and cls == utility.ClassLabel.REPAIR_DEPOT) or odf == repairOdf
                        end)
                    if repairCount == 0 then
                        local repairPos = self:FindOutpostStructureLocation(anchor, hotspot.position, repairOdf, 34.0, 78.0)
                        if repairPos then
                            self:AddBuilding(repairOdf, repairPos)
                            self.scrapOutpostTimer = GetTime() + (self.Config.scrapHotspotOutpostCooldown or 10.0)
                            return
                        end
                    end
                end

                if supplyOdf and ((hotspot.totalValue or 0.0) >= ((self.Config.scrapHotspotOutpostValue or 24.0) + 8.0) or hotspot.contested) then
                    local supplyCount = self:CountExistingOrPlannedBuildingsNear(anchor, supportRadius,
                        function(odf, obj)
                            local cls = obj and string.lower(utility.CleanString(GetClassLabel(obj))) or ""
                            return (obj and cls == utility.ClassLabel.SUPPLY_DEPOT) or odf == supplyOdf
                        end)
                    if supplyCount == 0 then
                        local supplyPos = self:FindOutpostStructureLocation(anchor, hotspot.position, supplyOdf, 40.0, 84.0)
                        if supplyPos then
                            self:AddBuilding(supplyOdf, supplyPos)
                            self.scrapOutpostTimer = GetTime() + (self.Config.scrapHotspotOutpostCooldown or 10.0)
                            return
                        end
                    end
                end

                if towerOdf then
                    local desiredTowers = math.max(1, math.floor(self.Config.scrapHotspotOutpostTowerCount or 2))
                    local towerCount = self:CountExistingOrPlannedBuildingsNear(anchor, supportRadius,
                        function(odf, obj)
                            local cls = obj and string.lower(utility.CleanString(GetClassLabel(obj))) or ""
                            return (obj and (cls == utility.ClassLabel.TURRET or string.find(cls, utility.ClassLabel.TURRET_TANK))) or odf == towerOdf
                        end)
                    if towerCount < desiredTowers then
                        local towerPos = self:FindOutpostStructureLocation(anchor, hotspot.position, towerOdf, 44.0, 92.0)
                        if towerPos then
                            self:AddBuilding(towerOdf, towerPos)
                            self.scrapOutpostTimer = GetTime() + (self.Config.scrapHotspotOutpostCooldown or 10.0)
                            return
                        end
                    end
                end
            end
        end
    end
end

function aiCore.Team:PlanHotspotSilo()
    if not self.Config.autoBuild or not self.Config.manageConstructor then return end
    if not IsValid(self.constructorMgr.handle) then return end
    if IsBusy(self.constructorMgr.handle) then return end

    for _, hotspot in ipairs(self.scrapHotspots or aiCore.EmptyList) do
        local totalValue = hotspot.totalValue or 0.0
        local dropoffDist = hotspot.dropoffDist or 999999
        if totalValue >= (self.Config.scrapHotspotSiloValue or 14.0)
            and dropoffDist >= (self.Config.scrapHotspotSiloDropoffDistance or 260.0)
            and not self:HasPlannedSiloNear(hotspot.position, 130.0) then
            local siloPos = self:FindSiloLocationNearHotspot(hotspot.position)
            if siloPos then
                self:AddBuilding(aiCore.Units[self.faction].silo, siloPos, 11)
                if aiCore.Debug then
                    print("Team " .. self.teamNum .. " planning silo near contested scrap field.")
                end
                return
            end
        end
    end
end

function aiCore.Team:GetDesiredScavengerCountFromHotspots()
    local baseDesired = math.max(self.Config.scavengerCount or 0, self.Config.minScavengers or 0)
    if not self.scrapHotspots or #self.scrapHotspots == 0 then
        return baseDesired, 0
    end

    local threshold = self.Config.scrapHotspotExtraScavengerValue or 16.0
    local step = math.max(1.0, self.Config.scrapHotspotExtraScavengerStep or 10.0)
    local maxExtra = math.max(0, math.floor(self.Config.scrapHotspotMaxExtraScavengers or 3))
    local extraWanted = 0

    for _, hotspot in ipairs(self.scrapHotspots) do
        local totalValue = hotspot.totalValue or 0.0
        if totalValue >= threshold then
            extraWanted = extraWanted + (1 + math.floor((totalValue - threshold) / step))
            if extraWanted >= maxExtra then
                extraWanted = maxExtra
                break
            end
        end
    end

    return baseDesired + extraWanted, extraWanted
end

function aiCore.Team:UpdateScavengerProductionFromHotspots()
    if not self.Config.autoBuild or not self.Config.manageFactories then return end

    local scavengerOdf = aiCore.Units[self.faction] and aiCore.Units[self.faction].scavenger or nil
    if not scavengerOdf then return end

    local desiredCount, extraWanted = self:GetDesiredScavengerCountFromHotspots()
    if extraWanted <= 0 then return end

    local currentCount = self:GetUnitCountByCategory("scavenger")
    local missing = desiredCount - currentCount
    if missing <= 0 then return end

    local caps = self.Config.unitCaps
    if caps and caps.scavenger then
        missing = math.min(missing, math.max(0, caps.scavenger - currentCount))
        if missing <= 0 then return end
    end

    for i = 1, missing do
        self.recyclerMgr:addUnit(scavengerOdf, 1.10 + (i * 0.05))
    end

    if aiCore.Debug then
        print("Team " ..
            self.teamNum ..
            " ordering " .. missing .. " extra scavenger(s) for rich scrap hotspot(s).")
    end
end

function aiCore.Team:UpdateScavengerFieldMicro()
    if not self.scavengers then return end

    for _, scav in ipairs(self.scavengers) do
        if IsValid(scav) and IsAlive(scav) and not IsSelected(scav) then
            local cmd = GetCurrentCommand(scav)
            local target = GetCurrentWho(scav)
            local shouldTurbo = true

            if cmd == AiCommand.SCAVENGE then
                local nearDropoff = false
                local dropoff = GetNearestBuilding(scav)
                if IsValid(dropoff) then
                    local cls = string.lower(utility.CleanString(GetClassLabel(dropoff)))
                    nearDropoff = (cls == utility.ClassLabel.SCRAP_SILO or cls == utility.ClassLabel.RECYCLER) and GetDistance(scav, dropoff) <= 55.0
                end

                local nearScrap = IsValid(target) and string.lower(utility.CleanString(GetClassLabel(target))) == utility.ClassLabel.SCRAP and GetDistance(scav, target) <= 45.0
                shouldTurbo = not (nearDropoff or nearScrap)

                if not IsValid(target) then
                    for _, hotspot in ipairs(self.scrapHotspots or aiCore.EmptyList) do
                        if DistanceBetweenRefs(scav, hotspot.position) <= (self.Config.scrapHotspotClaimRadius or 200.0) then
                            local bestScrap = self:GetBestAvailableHotspotScrap(hotspot, scav)
                            if IsValid(bestScrap) then
                                aiCore.TryScavenge(scav, bestScrap, GetUncommandablePriority(),
                                    { minInterval = 1.0, overrideProtected = true })
                                break
                            end
                        end
                    end
                end
            end

            aiCore.TrySetTurbo(scav, shouldTurbo)
        end
    end
end

function aiCore.Team:UpdateScrapAwareness()
    if self.Config.scrapAwareness == false then return end

    if GetTime() >= (self.scrapLossTrackAt or 0.0) then
        self.scrapLossTrackAt = GetTime() + 0.5
        self:TrackCombatLossesForScrap()
    end

    if GetTime() < (self.scrapHotspotTimer or 0.0) then return end
    self.scrapHotspotTimer = GetTime() + (self.Config.scrapHotspotInterval or 12.0)

    self:RefreshScrapHotspots()
    self:AssignScavengersToHotspots()
    self:UpdateScavengerFieldMicro()
    self:UpdateScavengerProductionFromHotspots()
    self:PlanHotspotOutpost()
    self:PlanHotspotSilo()
end

-- Building Spacing Helper (from aiBuildOS)

function aiCore.Team:UpdateRegen()
    -- Consolidated Regen: Recycler/Factory (High Rate) + Combat Units (Low Rate)
    local recycler = self.recyclerMgr.handle
    if IsValid(recycler) then
        AddHealth(recycler, (self.Config.regenRate or 0.0) * 0.05)
    end

    local factory = self.factoryMgr.handle
    if IsValid(factory) then
        AddHealth(factory, (self.Config.regenRate or 0.0) * 0.05)
    end

    if self.Config.passiveRegen then
        if not self.regenTimer or GetTime() > self.regenTimer then
            self.regenTimer = GetTime() + 1.0
            aiCore.RemoveDead(self.combatUnits)
            for _, u in ipairs(self.combatUnits) do
                if IsAlive(u) and GetHealth(u) < GetMaxHealth(u) then
                    AddHealth(u, 5) -- Small flat regen for all combat units
                end
            end
        end
    end
end

function aiCore.Team:UpdateDynamicMinefields()
    -- Ported from Misn07: Spawn mines near enemies in designated zones
    if #self.Config.minefields == 0 then return end
    if GetTime() < (self.dynamicMinefieldAt or 0.0) then return end
    self.dynamicMinefieldAt = GetTime() + 0.75

    for _, zone in ipairs(self.Config.minefields) do
        -- zone can be a path name or {x,y,z}
        local pos = zone
        if type(zone) == "string" then pos = GetPosition(zone) end

        local enemy = GetNearestEnemy(zone) -- Uses position if string
        if IsValid(enemy) and GetDistance(enemy, pos) < 150 then
            -- Spawn a mine if not too many nearby
            local mines = 0
            for obj in ObjectsInRange(40, pos) do
                if IsOdf(obj, "proxmine") or IsOdf(obj, "svmine") then
                    mines = mines + 1
                end
            end

            if mines < 3 then
                local odf = aiCore.Units[self.faction].minelayer .. "m" -- Guessing mine ODF
                if self.faction == 2 then odf = "svmine" end            -- CCA specific
                BuildObject(odf, self.teamNum, pos)
            end
        end
    end
end

-- Helper for Engineer Base Capturing (Legacy Misns7)
function aiCore.Team:ReclaimBuilding(building, engineer)
    if not IsValid(building) or not IsValid(engineer) then return end

    local cls = aiCore.NilToString(GetClassLabel(building))
    if string.find(cls, utility.ClassLabel.BUILDING) or IsBuilding(building) then
        -- ...
    end
end

-- Stealth Logic (Legacy Misn12)
function aiCore.Team:UpdateStealth(checkpoints)
    -- checkpoints = {{handle=h, range=r, order=i}, ...}
    local player = GetPlayerHandle()
    if not IsValid(player) then return end

    local inVehicle = not IsPerson(player)
    if inVehicle ~= self.stealthState.playerInVehicle then
        self.stealthState.playerInVehicle = inVehicle
        if not inVehicle and not self.stealthState.discovered then
            -- Trigger "Grumpy" alert if they leave the ship in a restricted zone
            return "LEFT_VEHICLE"
        end
    end

    -- Checkpoint Verification
    for _, cp in ipairs(checkpoints) do
        local dist = GetDistance(player, cp.handle)
        if dist < cp.range then
            if self.stealthState.lastOrder and cp.order > self.stealthState.lastOrder + 1 then
                -- Player skipped a checkpoint or went out of order
                return "OUT_OF_ORDER", cp.order
            end
            self.stealthState.lastOrder = cp.order
            return "AT_CHECKPOINT", cp.order
        end
    end

    return "STAYING_STEALTHY"
end

----------------------------------------------------------------------------------
-- TACTICAL LOGIC EXTENSIONS
----------------------------------------------------------------------------------

-- DEPRECATED: Combined into MinelayerManager:Update

-- DEPRECATED: Combined into WeaponManager:Update

function aiCore.Team:ResetWeaponMask(h)
    if not IsValid(h) then return end

    -- Priority 1: ODF weaponMask line
    local odfMask = aiCore.GetOdfWeaponMask(h)
    if odfMask then
        SetWeaponMask(h, odfMask)
        return
    end

    -- Priority 2: Refined Smart Detection logic from aiSpecial.lua
    local w0 = utility.CleanString(GetWeaponClass(h, 0))
    local w1 = utility.CleanString(GetWeaponClass(h, 1))
    local w2 = utility.CleanString(GetWeaponClass(h, 2))
    local w3 = utility.CleanString(GetWeaponClass(h, 3))

    if w0 ~= "" and w3 ~= "" and w0 == w3 then
        SetWeaponMask(h, 15) -- Link 4 (Mammoth)
    elseif w0 ~= "" and w2 ~= "" and w0 == w2 then
        SetWeaponMask(h, 7)  -- Link 3 (Kodiak)
    elseif w0 ~= "" and w1 ~= "" and w0 == w1 then
        SetWeaponMask(h, 3)  -- Link 2 (Fighter)
    elseif w1 ~= "" and w2 ~= "" and w1 == w2 then
        SetWeaponMask(h, 6)  -- Link 2 (Bomber)
    else
        -- Priority 3: First non-empty slot
        local defaultMask = aiCore.GetWeaponMask(h)
        if defaultMask > 0 then
            SetWeaponMask(h, defaultMask)
        else
            SetWeaponMask(h, 1) -- Absolute fallback
        end
    end
end

function aiCore.Team:SetDoubleWeaponMask(h, rate, popgunrate)
    if not IsValid(h) then return end

    local newMask = 1
    local w0 = utility.CleanString(GetWeaponClass(h, 0))
    local w1 = utility.CleanString(GetWeaponClass(h, 1))
    local w2 = utility.CleanString(GetWeaponClass(h, 2))
    local w3 = utility.CleanString(GetWeaponClass(h, 3))

    if aiCore.HasWeapon(h, 0) and aiCore.HasWeapon(h, 1) and w0 ~= w1 then
        newMask = 1 + 2
    elseif aiCore.HasWeapon(h, 0) and aiCore.HasWeapon(h, 2) and not aiCore.HasWeapon(h, 3) and w0 ~= w2 then
        newMask = 1 + 4
    elseif not aiCore.HasWeapon(h, 0) and aiCore.HasWeapon(h, 1) and aiCore.HasWeapon(h, 2) and w1 == w2 then
        newMask = 2 + 4
    elseif aiCore.HasWeapon(h, 0) and aiCore.HasWeapon(h, 1) and aiCore.HasWeapon(h, 2) and aiCore.HasWeapon(h, 3) and w0 == w1 and w1 == w2 and w2 == w3 then
        newMask = 1 + 2 + 4 + 8
    elseif aiCore.HasWeapon(h, 0) and aiCore.HasWeapon(h, 1) and aiCore.HasWeapon(h, 2) and w0 == w1 and w1 == w2 then
        newMask = 1 + 2 + 4
    elseif aiCore.HasWeapon(h, 0) and aiCore.HasWeapon(h, 1) and w0 == w1 then
        newMask = 1 + 2
    end

    -- Popgun logic
    popgunrate = popgunrate or (self.Config.popgunRate or 50)
    if math.random(100) <= popgunrate then
        local popMask = aiCore.GetWeaponMask(h, "gpopgun")
        if popMask > 0 then
            newMask = newMask + popMask
        end
    end

    rate = rate or (self.Config.doubleRate or 50)
    if math.random(100) <= rate and newMask > 1 then
        SetWeaponMask(h, newMask)
        if not self.doubleUsers then self.doubleUsers = {} end
        table.insert(self.doubleUsers, h)
    end
end

function aiCore.Team:UpdateParatroopers()
    if not self.Config.enableParatroopers or (self.Config.paratrooperChance or 0) <= 0 then return end

    if GetTime() > (self.paratrooperTimer or 0) then
        self.paratrooperTimer = GetTime() + (self.Config.paratrooperInterval or 600)

        -- Roll for drop
        if math.random(100) > self.Config.paratrooperChance then return end

        -- Find critical target
        local target = self:FindCriticalTarget()
        ---@cast target any
        if not IsValid(target) then return end

        local pos = GetPosition(target)
        pos.y = pos.y + 400.0 -- 400M in the sky

        local count = math.random(3, 8)
        local soldierOdf = aiCore.Units[self.faction].soldier or "aspilo" -- Fallback

        if aiCore.Debug then
            print("Team " ..
                self.teamNum .. " launching paratrooper drop (" .. count .. ") on " .. GetOdf(target))
        end

        for i = 1, count do
            local spawnPos = GetPositionNear(target, 5, 20) or GetPosition(target)
            if spawnPos then
                spawnPos.y = spawnPos.y + 400.0
                local s = BuildObject(soldierOdf, self.teamNum, spawnPos)
                if IsValid(s) then
                    ---@cast s handle
                    table.insert(self.soldiers, s)
                    aiCore.TryAttack(s, target, GetUncommandablePriority(), { minInterval = 0.4, ignoreThrottle = true })
                    -- Give them a little drift/random velocity so they don't fall in a perfect line
                    --SetVelocity(s, SetVector(math.random(-5, 5), -2, math.random(-5, 5))) no they just fall lmao

                    -- MODIFED: Paratroopers technically "created" in sky - if they were powerups we'd swap team,
                    -- but soldiers are fine. However, we'll ensure they are on AI team.
                end
            end
        end
    end
end

-- DEPRECATED: Combined into HowitzerManager:Update

function aiCore.Team:UpdateAPCs()
    -- DEPRECATED: Combined into APCManager:UpdateAPC
end

function aiCore.Team:UpdateWrecker()
    if not self.Config.enableWreckers then return end

    if not self.wreckerTimer then self.wreckerTimer = GetTime() + (self.Config.wreckerInterval or 600) end
    if GetTime() > self.wreckerTimer then
        self.wreckerTimer = GetTime() + (self.Config.wreckerInterval or 600)
        local armory = GetArmoryHandle(self.teamNum)
        if IsValid(armory) and CanBuild(armory) then
            ---@type any
            local enemyTeam = self:GetPrimaryEnemyTeam()
            if enemyTeam < 0 then enemyTeam = (self.teamNum == 1) and 2 or 1 end
            local target = GetRecyclerHandle(enemyTeam)
            if not IsValid(target) then target = self:FindCriticalTarget() end

            if IsValid(target) then
                ---@cast target handle
                -- BUG FIX: Record target for Team 1 workaround in AddObject
                self.lastArmoryTarget = target
                local wreckerOdf = aiCore.Units[self.faction].wrecker or "apwrck"
                BuildAt(armory, wreckerOdf, target, 1)
            end
        end
    end
end

function aiCore.Team:StartArmorySuicide(armory)
    if not IsValid(armory) or not IsAlive(armory) then return false end
    if not aiCore.IsEnemyOfPlayerTeam(self.teamNum) then return false end
    self.armorySuicideStates = self.armorySuicideStates or {}
    if self.armorySuicideStates[armory] then return true end

    local playerRecycler = aiCore.GetPlayerRecyclerHandle()
    if not IsValid(playerRecycler) then return false end

    local geyser = aiCore.FindClosestOpenGeyser(playerRecycler)
    if not IsValid(geyser) then return false end

    self.armorySuicideStates[armory] = {
        geyser = geyser,
        stage = "moving",
        nextOrderTime = 0.0,
        built = 0,
        granted = false
    }

    aiCore.TrySetCommand(armory, AiCommand.GO_TO_GEYSER, GetUncommandablePriority(), geyser, nil, nil, nil,
        { minInterval = 1.0, overrideProtected = true })
    return true
end

function aiCore.Team:UpdateArmorySuicide()
    if not self.armorySuicideStates then return end
    local now = GetTime()

    for armory, state in pairs(self.armorySuicideStates) do
        if not IsValid(armory) or not IsAlive(armory) then
            self.armorySuicideStates[armory] = nil
        else
            local geyser = state.geyser
            if not IsValid(geyser) then
                local playerRecycler = aiCore.GetPlayerRecyclerHandle()
                if IsValid(playerRecycler) then
                    geyser = aiCore.FindClosestOpenGeyser(playerRecycler)
                    state.geyser = geyser
                end
            end

            if not IsValid(geyser) then
                self.armorySuicideStates[armory] = nil
            else
                if state.stage == "moving" then
                    if IsDeployed(armory) and DistanceBetweenRefs(armory, geyser) <= 35.0 then
                        state.stage = "detonate"
                    elseif now >= (state.nextOrderTime or 0.0) then
                        aiCore.TrySetCommand(armory, AiCommand.GO_TO_GEYSER, GetUncommandablePriority(), geyser, nil, nil, nil,
                            { minInterval = 1.0, overrideProtected = true })
                        state.nextOrderTime = now + 6.0
                    end
                end

                if state.stage == "detonate" then
                    if not state.granted then
                        AddScrap(self.teamNum, 60)
                        state.granted = true
                    end

                    if state.built < 3 and CanBuild(armory) then
                        local wreckerOdf = "apwrck"
                        self.lastArmoryTarget = armory
                        for i = state.built + 1, 3 do
                            BuildAt(armory, wreckerOdf, armory, 1)
                        end
                        state.built = 3
                    end

                    if state.built >= 3 then
                        self.armorySuicideStates[armory] = nil
                    end
                end
            end
        end
    end
end

function aiCore.Team:ChooseFallbackStrategy()
    local options = { "Balanced", "Tank_Heavy", "Howitzer_Heavy", "Bomber_Heavy" }
    local weights = {
        Balanced = 1.0,
        Tank_Heavy = 1.0,
        Howitzer_Heavy = 1.0,
        Bomber_Heavy = 1.0
    }

    local scrap = GetScrap(self.teamNum)
    local maxScrap = math.max(GetMaxScrap(self.teamNum), 1)
    local pilots = GetPilot(self.teamNum)
    local maxPilots = math.max(GetMaxPilot(self.teamNum), 1)
    local scrapRatio = scrap / maxScrap
    local pilotRatio = pilots / maxPilots
    local missionTime = GetTime()

    if scrapRatio < 0.25 then
        weights.Balanced = weights.Balanced + 2.0
        weights.Tank_Heavy = weights.Tank_Heavy + 1.0
        weights.Howitzer_Heavy = math.max(0.2, weights.Howitzer_Heavy - 0.6)
        weights.Bomber_Heavy = math.max(0.2, weights.Bomber_Heavy - 0.5)
    elseif scrapRatio > 0.7 then
        weights.Howitzer_Heavy = weights.Howitzer_Heavy + 1.2
        weights.Bomber_Heavy = weights.Bomber_Heavy + 1.0
    end

    if pilotRatio < 0.3 then
        weights.Balanced = weights.Balanced + 1.0
        weights.Tank_Heavy = weights.Tank_Heavy + 0.7
        weights.Bomber_Heavy = math.max(0.2, weights.Bomber_Heavy - 0.4)
    end

    if missionTime < 600 then
        weights.Balanced = weights.Balanced + 1.5
        weights.Tank_Heavy = weights.Tank_Heavy + 0.8
        weights.Howitzer_Heavy = math.max(0.2, weights.Howitzer_Heavy - 0.4)
    elseif missionTime > 1500 then
        weights.Howitzer_Heavy = weights.Howitzer_Heavy + 1.2
        weights.Bomber_Heavy = weights.Bomber_Heavy + 1.2
    end

    local history = self.strategyHistory or {}
    for i = #history, math.max(1, #history - 1), -1 do
        local recent = history[i]
        if weights[recent] then
            weights[recent] = math.max(0.1, weights[recent] * 0.35)
        end
    end
    if weights[self.strategy] then
        weights[self.strategy] = math.max(0.1, weights[self.strategy] * 0.5)
    end

    local total = 0.0
    for _, name in ipairs(options) do
        total = total + (weights[name] or 0)
    end
    if total <= 0 then return "Balanced" end

    local roll = math.random() * total
    local cumulative = 0.0
    for _, name in ipairs(options) do
        cumulative = cumulative + (weights[name] or 0)
        if roll <= cumulative then
            return name
        end
    end

    return "Balanced"
end

function aiCore.Team:UpdateStrategyRotation()
    if self.strategyLocked then return end
    if not self.strategyTimer then self.strategyTimer = GetTime() + aiCore.Constants.STRATEGY_ROTATION_INTERVAL end
    if GetTime() > self.strategyTimer then
        self.strategyTimer = GetTime() + aiCore.Constants.STRATEGY_ROTATION_INTERVAL

        local desired = self:ChooseModeStrategy(self.strategicMode or "balanced")
        local counter = self:GetCounterStrategy()

        if self.strategicMode == "pressure" or self.strategicMode == "defend" then
            desired = counter or desired
        elseif self.strategicMode == "balanced" or not desired then
            desired = counter or self:ChooseFallbackStrategy()
        end

        if desired then
            self.strategicModeStrategy = desired
            if desired ~= self.strategy then
                self._applyingFsmStrategy = true
                self:SetStrategy(desired)
                self._applyingFsmStrategy = nil
            end
        end
    end
end

function aiCore.Team:UpdateAutoBase()
    if not self.Config.autoBuild then return end
    local constructor = self.constructorMgr.handle

    if self.Config.autoManage then
        if not self.pilotEmergencyCheckAt or GetTime() > self.pilotEmergencyCheckAt then
            self.pilotEmergencyCheckAt = GetTime() + (self.Config.pilotEmergencyCheckInterval or 6.0)
            local pilots = GetPilot(self.teamNum)
            if pilots >= 0 and pilots < (self.Config.pilotEmergencyBarracksThreshold or 3) then
                if not self:HasBuilding("barracks") then
                    self:PlanBarracks(self.Config.pilotEmergencyBarracksPriority or 3)
                end
            end
        end
    end

    if not IsValid(constructor) or IsBusy(constructor) then return end

    -- Periodic Base Expansion Check
    if not self.expandTimer or GetTime() > self.expandTimer then
        self.expandTimer = GetTime() + 30.0 -- Check every 30 seconds
        self:ExpandBase()
    end

    -- Rebuild Factory if lost
    local factory = GetFactoryHandle(self.teamNum)
    if not IsAlive(factory) and self.basePositions.factory then
        local found = false
        for _, q in ipairs(self.constructorMgr.queue) do
            if q.odf == aiCore.Units[self.faction].factory then
                found = true
                break
            end
        end
        if not found and self.recyclerMgr then
            for _, q in ipairs(self.recyclerMgr.queue) do
                if q.odf == aiCore.Units[self.faction].factory then
                    found = true
                    break
                end
            end
        end
        if not found then self:AddBuilding(aiCore.Units[self.faction].factory, self.basePositions.factory, 5) end
    end
end

function aiCore.Team:UpdatePilotResources()
    if GetTime() > (self.pilotResTimer or 0) then
        self.pilotResTimer = GetTime() + aiCore.Constants.PILOT_RESOURCE_INTERVAL
        aiCore.RemoveDead(self.pilots)
        if #self.pilots < (self.Config.pilotTopoff or 4) then
            local pilotOdf = aiCore.Units[self.faction].pilot
            if pilotOdf then self.recyclerMgr:addUnit(pilotOdf, 0) end
        end
    end
end

function aiCore.Team:UpdateCloakers()
    aiCore.RemoveDead(self.cloakers)
end

function aiCore.Team:UpdateSoldiers()
    if GetTime() < (self.soldierUpdateAt or 0.0) then return end
    self.soldierUpdateAt = GetTime() + 0.4

    aiCore.RemoveDead(self.soldiers)
    for _, s in ipairs(self.soldiers) do
        if IsAlive(s) then
            local enemy = GetNearestEnemy(s)
            if IsValid(enemy) and GetDistance(s, enemy) < 100 then
                if GetCurrentCommand(s) ~= AiCommand.ATTACK or GetCurrentWho(s) ~= enemy then
                    aiCore.TryAttack(s, enemy, GetCommandableAttackPriority(), { minInterval = 0.6 })
                end
            end
        end
    end
end

function aiCore.Team:UpdateGuards()
end

function aiCore.Team:UpdateUnitRoles()
    local now = GetTime()
    if now < (self.roleTimer or 0) then return end
    self.roleTimer = now + 5.0

    local squadUnits = {}
    for _, sq in ipairs(self.squads or aiCore.EmptyList) do
        if sq then
            if IsValid(sq.leader) then squadUnits[sq.leader] = true end
            for _, m in ipairs(sq.members or aiCore.EmptyList) do
                if IsValid(m) then squadUnits[m] = true end
            end
        end
    end

    local enemyTeam = self:GetPrimaryEnemyTeam()
    if enemyTeam < 0 then enemyTeam = (self.teamNum == 1) and 2 or 1 end

    local recycler = GetRecyclerHandle(self.teamNum)
    local baseRef = self:GetBaseReference()
    local player = (self.Config.stickToPlayer and self.teamNum == 1) and GetPlayerHandle() or nil

    local recyclerThreat = nil
    local recyclerThreatDist = 999999
    if IsValid(recycler) then
        for _, h in ipairs(aiCore.GetCachedTeamCraft(enemyTeam)) do
            if IsValid(h) and IsAlive(h) then
                local d = GetDistance(recycler, h)
                if d < recyclerThreatDist then
                    recyclerThreat = h
                    recyclerThreatDist = d
                end
            end
        end
    end

    local recyclerUnderAttack = IsValid(recyclerThreat) and recyclerThreatDist < 250
    local threatenedFront = recyclerThreat
    local threatenedAnchor = recycler
    if not IsValid(threatenedFront) and IsValid(recycler) then
        local bestDist = 999999
        for _, obj in ipairs(aiCore.GetCachedTeamTargets(enemyTeam)) do
            if IsValid(obj) and IsAlive(obj) and (IsCraft(obj) or IsBuilding(obj)) then
                local d = GetDistance(recycler, obj)
                if d < bestDist then
                    threatenedFront = obj
                    bestDist = d
                end
            end
        end
    end

    local strategicDefenseGoal = self:SelectStrategicGoal(recycler or baseRef or self.recyclerMgr.handle, math.huge,
        { defenseOnly = true, allowUnderstrength = true })
    if strategicDefenseGoal then
        threatenedFront = strategicDefenseGoal.target or threatenedFront
        threatenedAnchor = strategicDefenseGoal.anchor or threatenedAnchor
        recyclerUnderAttack = recyclerUnderAttack or ((strategicDefenseGoal.threat or 0.0) > 0.0)
    end

    local walkerHotspot = nil
    for _, hotspot in ipairs(self.scrapHotspots or aiCore.EmptyList) do
        if hotspot and (hotspot.contested or IsValid(hotspot.denyTarget)) then
            walkerHotspot = hotspot
            break
        end
    end

    local walkerAttackGoal = nil
    local walkerAttackTarget = nil
    if not recyclerUnderAttack then
        walkerAttackGoal = self:SelectStrategicGoal(recycler or baseRef or self.recyclerMgr.handle, math.huge,
            { attackOnly = true, allowUnderstrength = true })
        walkerAttackTarget = walkerAttackGoal and (walkerAttackGoal.target or self:ResolveStrategicGoalTarget(walkerAttackGoal)) or nil
    end
    local walkerFlankAngle = ((self.teamNum * 97) + 45) % 360

    local function AssignRole(u)
        if not IsValid(u) or not IsAlive(u) or IsBuilding(u) then return end
        local classLabel = string.lower(utility.CleanString(GetClassLabel(u)))
        local isWalker = string.find(classLabel, utility.ClassLabel.WALKER) ~= nil
        if isWalker then
            local cmd = GetCurrentCommand(u)
            local idle = (cmd == AiCommand.NONE or cmd == AiCommand.GO or cmd == AiCommand.PATROL)
            if recyclerUnderAttack and IsValid(recycler) then
                aiCore.TrySetCommand(u, AiCommand.DEFEND, 1, recycler, nil, nil, nil, { minInterval = 1.1 })
                return
            end

            if walkerHotspot then
                if IsValid(walkerHotspot.denyTarget) then
                    aiCore.TryAttack(u, walkerHotspot.denyTarget, GetCommandableAttackPriority(), { minInterval = 1.1 })
                    return
                elseif idle and walkerHotspot.position then
                    aiCore.TrySetCommand(u, AiCommand.GO, 0, nil, walkerHotspot.position, nil, nil, { minInterval = 1.4 })
                    return
                end
            end

            if IsValid(walkerAttackTarget) then
                if GetDistance(u, walkerAttackTarget) > 260 then
                    local flankPos = self:GetValidFlankPosition(walkerAttackTarget, walkerFlankAngle)
                    if flankPos then
                        aiCore.TrySetCommand(u, AiCommand.GO, GetUncommandablePriority(), nil, flankPos, nil, nil,
                            { minInterval = 1.3 })
                        return
                    end
                end
                aiCore.TryAttack(u, walkerAttackTarget, GetCommandableAttackPriority(), { minInterval = 1.1 })
                return
            end

            if IsValid(threatenedAnchor) then
                aiCore.TrySetCommand(u, AiCommand.DEFEND, 1, threatenedAnchor, nil, nil, nil, { minInterval = 1.1 })
                return
            end

            if idle and IsValid(recycler) then
                local patrolPos = GetPositionNear(GetPosition(recycler), 80, 220)
                if patrolPos then
                    aiCore.TrySetCommand(u, AiCommand.GO, 0, nil, patrolPos, nil, nil, { minInterval = 1.5 })
                end
            end
            return
        end

        if IsSpecializedPoolClass(classLabel) then return end
        local cmd = GetCurrentCommand(u)
        local idle = (cmd == AiCommand.NONE or cmd == AiCommand.GO or cmd == AiCommand.PATROL)

        if self.Config.stickToPlayer and self.teamNum == 1 and IsValid(player) and idle and GetDistance(u, player) > 220 then
            aiCore.TrySetCommand(u, AiCommand.FOLLOW, 1, player, nil, nil, nil, { minInterval = 1.0 })
            return
        end

        if recyclerUnderAttack and IsValid(recycler) and (idle or GetDistance(u, recycler) < 450) then
            aiCore.TrySetCommand(u, AiCommand.DEFEND, 1, recycler, nil, nil, nil, { minInterval = 0.8 })
            return
        end

        if idle and IsValid(threatenedFront) then
            aiCore.TryAttack(u, threatenedFront, GetCommandableAttackPriority(), { minInterval = 0.8 })
            return
        end

        if idle and IsValid(threatenedAnchor) then
            aiCore.TrySetCommand(u, AiCommand.DEFEND, 1, threatenedAnchor, nil, nil, nil, { minInterval = 0.9 })
            return
        end

        if idle and IsValid(recycler) then
            local patrolPos = GetPositionNear(GetPosition(recycler), 40, 170)
            if patrolPos then
                aiCore.TrySetCommand(u, AiCommand.GO, 0, nil, patrolPos, nil, nil, { minInterval = 1.2 })
            end
        end
    end

    local processed = {}
    for _, u in ipairs(self.combatUnits) do
        if not processed[u] and not squadUnits[u] then
            processed[u] = true
            AssignRole(u)
        end
    end
    for _, u in ipairs(self.pool) do
        if not processed[u] and not squadUnits[u] then
            processed[u] = true
            AssignRole(u)
        end
    end
end

function aiCore.Team:UpdateRescue()
    if self.teamNum ~= 1 or not self.Config.autoRescue then return end
    local player = GetPlayerHandle()
    local now = GetTime()

    if not IsPerson(player) then
        self.currentRescueVehicle = nil
        self.rescueAttemptExpiry = 0.0
        return
    end

    local activeRescue = self.currentRescueVehicle
    if IsValid(activeRescue) and IsAlive(activeRescue) then
        local activeCmd = GetCurrentCommand(activeRescue)
        local activeTarget = GetCurrentWho(activeRescue)
        if activeCmd == AiCommand.RESCUE and activeTarget == player and now < (self.rescueAttemptExpiry or 0.0) then
            return
        end
    else
        self.currentRescueVehicle = nil
        self.rescueAttemptExpiry = 0.0
    end

    if now < (self.rescueTimer or 0.0) then return end
    self.rescueTimer = now + aiCore.Constants.RESCUE_CHECK_INTERVAL

    local bestVehicle = nil
    local bestScore = math.huge
    local seen = {}

    local function ConsiderRescueVehicle(veh)
        if not IsValid(veh) or not IsAlive(veh) or seen[veh] then return end
        seen[veh] = true
        if veh == player or IsPerson(veh) or IsBuilding(veh) or IsDeployed(veh) then return end

        local cls = string.lower(utility.CleanString(GetClassLabel(veh)))
        if string.find(cls, utility.ClassLabel.SCAVENGER) ~= nil
            or string.find(cls, utility.ClassLabel.CONSTRUCTOR) ~= nil
            or string.find(cls, utility.ClassLabel.TUG) ~= nil
            or IsSpecializedPoolClass(cls) then
            return
        end

        local dist = GetDistance(veh, player)
        local cmd = GetCurrentCommand(veh)
        local score = dist
        if cmd == AiCommand.NONE or cmd == AiCommand.STOP then
            score = score - 60.0
        elseif cmd == AiCommand.FOLLOW or cmd == AiCommand.DEFEND or cmd == AiCommand.FORMATION then
            score = score - 25.0
        end

        if score < bestScore then
            bestScore = score
            bestVehicle = veh
        end
    end

    PruneSpecializedPoolUnits(self.pool)
    for _, veh in ipairs(self.pool or aiCore.EmptyList) do
        ConsiderRescueVehicle(veh)
    end
    for _, veh in ipairs(self.combatUnits or aiCore.EmptyList) do
        ConsiderRescueVehicle(veh)
    end

    if IsValid(bestVehicle) then
        local didSend = aiCore.TrySetCommand(bestVehicle, AiCommand.RESCUE, GetCommandableAttackPriority(), player, nil, nil, nil,
            { minInterval = 0.5, overrideProtected = true })
        if didSend then
            self.currentRescueVehicle = bestVehicle
            self.rescueAttemptExpiry = now + (self.Config.rescueAttemptTimeout or 20.0)
        end
    end
end

function aiCore.Team:UpdateTugs()
end

function aiCore.Team:UpdatePilots()
    local now = GetTime()
    if now < (self.pilotUpdateAt or 0.0) then return end
    self.pilotUpdateAt = now + 0.35

    -- Consolidated Pilot Management: technician spawning + sniper logic + craft stealing
    aiCore.RemoveDead(self.pilots)
    if not self.pilotActionTimer then self.pilotActionTimer = {} end
    if not self.sniperEquipTime then self.sniperEquipTime = {} end
    if not self.sniperState then self.sniperState = {} end
    if not self.sniperAttackTarget then self.sniperAttackTarget = {} end
    if not self.pilotStealScanAt then self.pilotStealScanAt = {} end
    if not self.pilotPatrolTimer then self.pilotPatrolTimer = {} end
    local sniperRoleChance = aiCore.GetSniperRoleChancePercent(self)
    local sniperAttackChance = aiCore.GetSniperAttackChancePercent(self)
    local sniperRange = self.Config.sniperRange or 200
    local player = GetPlayerHandle()

    -- Clean stale pilot action cooldown entries.
    for h, _ in pairs(self.pilotActionTimer) do
        if not IsValid(h) then
            self.pilotActionTimer[h] = nil
        end
    end
    for h, _ in pairs(self.sniperEquipTime) do
        if not IsValid(h) then
            self.sniperEquipTime[h] = nil
        end
    end
    for h, _ in pairs(self.sniperState) do
        if not IsValid(h) then
            self.sniperState[h] = nil
        end
    end
    for h, _ in pairs(self.sniperAttackTarget) do
        if not IsValid(h) then
            self.sniperAttackTarget[h] = nil
        end
    end
    for h, _ in pairs(self.pilotStealScanAt) do
        if not IsValid(h) then
            self.pilotStealScanAt[h] = nil
        end
    end
    for h, _ in pairs(self.pilotPatrolTimer) do
        if not IsValid(h) then
            self.pilotPatrolTimer[h] = nil
        end
    end

    -- 1. Technician Spawning (from Barracks)
    local barracks = {}
    if now >= (self.barracksRefreshAt or 0.0) then
        self.barracksRefreshAt = now + 3.0
        local recycler = self.recyclerMgr.handle
        if IsValid(recycler) then
            for _, obj in ipairs(aiCore.GetCachedBuildings(self.teamNum)) do
                if IsValid(obj) and IsAlive(obj) and GetDistance(obj, recycler) <= 300 then
                    local cls = string.lower(utility.CleanString(GetClassLabel(obj)))
                    if string.find(cls, utility.ClassLabel.BARRACKS) or string.find(cls, "training") then
                        barracks[#barracks + 1] = obj
                    end
                end
            end
        end
        self.cachedBarracks = barracks
    else
        local cachedBarracks = self.cachedBarracks or aiCore.EmptyList
        for i = 1, #cachedBarracks do
            local barracksHandle = cachedBarracks[i]
            if IsValid(barracksHandle) and IsAlive(barracksHandle) then
                barracks[#barracks + 1] = barracksHandle
            end
        end
        self.cachedBarracks = barracks
    end

    if #barracks > 0 then
        local dispensingBarracks = barracks[math.random(#barracks)]

        -- A. Technician Spawning (from Barracks)
        if #self.pilots < (self.Config.techMax or 4) then
            if not self.techTimer then self.techTimer = now + (self.Config.techInterval or 60) end
            if now > self.techTimer then
                if IsValid(dispensingBarracks) and IsAlive(dispensingBarracks) then
                    local pilotOdf = aiCore.GuessPilotOdf(dispensingBarracks)
                    local pos = GetPosition(dispensingBarracks)
                    pos.z = pos.z + 15
                    local pilot = BuildObject(pilotOdf, self.teamNum, pos)
                    if IsValid(pilot) then
                        table.insert(self.pilots, pilot)
                        aiCore.TrySetCommand(pilot, AiCommand.GO, GetUncommandablePriority(), nil, GetPositionNear(pos, 50, 150),
                            nil, nil, { minInterval = 0.5, ignoreThrottle = true })

                        -- Initial role assignment
                        if math.random(100) <= sniperRoleChance then
                            self.sniperState[pilot] = true
                        end
                    end
                end
                self.techTimer = now + (self.Config.techInterval or 60) + math.random(10)
            end
        end

        -- B. Orbital Reinforcements (from aiSpecial.lua)
        if self.Config.orbitalReinforce then
            local currentPilots = GetPilot(self.teamNum)
            local maxPilots = GetMaxPilot(self.teamNum)

            if currentPilots < (maxPilots / 3) then
                if not self.orbitalTimer or now > self.orbitalTimer then
                    local diff = aiCore.GetDifficultyLevel()
                    local intervalScale = 1.0
                    if diff <= 1 then
                        intervalScale = 1.2
                    elseif diff >= 3 then
                        intervalScale = 0.85
                    end
                    self.orbitalTimer = now + ((self.Config.techInterval or 60) * intervalScale)

                    if math.random(100) <= aiCore.GetOrbitalReinforceChance() then
                        local maxReinforcements = 3
                        local needed = maxPilots - currentPilots
                        local reinforcingPilots = math.random(0, math.min(needed, maxReinforcements))

                        local dropPoint = GetPositionNear(GetPosition(dispensingBarracks), 20, 150)
                        for j = 1, reinforcingPilots do
                            local droppedPilot = BuildObject(aiCore.GuessPilotOdf(dispensingBarracks), self.teamNum,
                                dropPoint)
                            if IsValid(droppedPilot) then
                                aiCore.TrySetCommand(droppedPilot, AiCommand.FOLLOW, GetUncommandablePriority(),
                                    dispensingBarracks, nil, nil, nil, { minInterval = 0.6, ignoreThrottle = true })
                                table.insert(self.pilots, droppedPilot)
                                aiCore.Lift(droppedPilot, 200) -- Arrival from orbit
                                if aiCore.Debug then print("Team " .. self.teamNum .. " orbital reinforcement deployed.") end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2. Individual Pilot Logic
    for _, p in ipairs(self.pilots) do
        if IsAlive(p) and IsPerson(p) then
            if p ~= player and not IsOdf(p, "aspiloh") then
                local weapon0 = utility.CleanString(GetWeaponClass(p, 0))
                local cmd = GetCurrentCommand(p)
                local enemy = GetNearestEnemy(p)
                local dist = IsValid(enemy) and GetDistance(p, enemy) or 9999
                if IsValid(player) and aiCore.IsEnemyOfPlayerTeam(self.teamNum) and utility.CanSnipe(player) then
                    local playerDist = GetDistance(p, player)
                    if playerDist <= (sniperRange + 120) and (not IsValid(enemy) or playerDist < dist) then
                        enemy = player
                        dist = playerDist
                    end
                end
                local ammo = GetAmmo(p)
                local actionReady = now >= (self.pilotActionTimer[p] or 0)
                local isSniper = self.sniperState[p]
                if isSniper == nil then
                    isSniper = math.random(100) <= sniperRoleChance
                    self.sniperState[p] = isSniper
                end

                local pos = GetPosition(p)
                local grounded = false
                if pos then
                    grounded = (pos.y - GetTerrainHeight(pos.x, pos.z)) < 5.0
                end
                local attackTarget = nil
                if cmd == utility.AiCommand.ATTACK then
                    local who = GetCurrentWho(p)
                    if IsValid(who) then
                        attackTarget = who
                    end
                end
                local currentTarget = GetTarget(p)
                local function IsOccupiedSniperTarget(target)
                    return IsValid(target) and utility.CanSnipe(target) and IsAliveAndPilot(target)
                end
                local sniperCandidate = nil
                if IsOccupiedSniperTarget(currentTarget) then
                    sniperCandidate = currentTarget
                elseif IsOccupiedSniperTarget(attackTarget) then
                    sniperCandidate = attackTarget
                elseif IsOccupiedSniperTarget(enemy) and dist < sniperRange then
                    sniperCandidate = enemy
                end
                local sniperTarget = self.sniperAttackTarget[p]
                if not IsOccupiedSniperTarget(sniperTarget) then
                    self.sniperAttackTarget[p] = nil
                    sniperTarget = nil
                end
                if not IsValid(sniperTarget) and isSniper and actionReady and grounded and ammo >= 0.3 and
                    IsValid(sniperCandidate) and GetDistance(p, sniperCandidate) < sniperRange and not IsCloaked(sniperCandidate) and
                    math.random(100) <= sniperAttackChance then
                    self.sniperAttackTarget[p] = sniperCandidate
                    sniperTarget = sniperCandidate
                end
                local targetDist = IsValid(sniperTarget) and GetDistance(p, sniperTarget) or 9999
                local targetCloaked = IsValid(sniperTarget) and IsCloaked(sniperTarget)
                local canStartSniperAttack = isSniper and IsOccupiedSniperTarget(sniperTarget) and grounded and
                    not targetCloaked and targetDist < sniperRange and ammo >= 0.3
                local canMaintainSniperCombat = canStartSniperAttack

                -- Sniper behavior: first commit to a specific snipe target, then arm the rifle once attacking it.
                if weapon0 ~= "" and string.find(weapon0, "handgun") then
                    self.sniperEquipTime[p] = nil
                    if canStartSniperAttack then
                        if currentTarget ~= sniperTarget then
                            SetTarget(p, sniperTarget)
                        end
                        if actionReady and (cmd ~= utility.AiCommand.ATTACK or GetCurrentWho(p) ~= sniperTarget) then
                            aiCore.TryAttack(p, sniperTarget, GetCommandableAttackPriority(), { minInterval = 0.5 })
                            self.pilotActionTimer[p] = now + 0.6
                        elseif actionReady then
                            GiveWeapon(p, "gsnipe", 0)
                            self.sniperEquipTime[p] = now
                            self.pilotActionTimer[p] = now + 0.4
                            if aiCore.Debug then print("Pilot " .. tostring(p) .. " equipping sniper rifle.") end
                        end
                    end
                elseif weapon0 ~= "" and string.find(weapon0, "gsnipe") then
                    local target = GetTarget(p)
                    local stealthRoll = self.Config.sniperStealth or 50
                    if stealthRoll <= 1.0 then stealthRoll = stealthRoll * 100 end
                    local emptyCraftTarget = IsValid(target) and IsCraft(target) and not IsAliveAndPilot(target)

                    -- Legacy handoff: if the marked target is now empty craft, commandeer it.
                    if emptyCraftTarget then
                        self.sniperAttackTarget[p] = nil
                        GiveWeapon(p, "handgun", 0)
                        weapon0 = "handgun"
                        self.sniperEquipTime[p] = nil
                        if actionReady and cmd ~= utility.AiCommand.GET_IN then
                            GetIn(p, target)
                            self.pilotActionTimer[p] = now + 1.2
                        end
                    elseif ammo <= 0.3 then
                        self.sniperAttackTarget[p] = nil
                        GiveWeapon(p, "handgun", 0)
                        weapon0 = "handgun"
                        self.sniperEquipTime[p] = nil
                        if math.random(100) <= stealthRoll then
                            Stop(p)
                        end
                    elseif not canMaintainSniperCombat then
                        self.sniperAttackTarget[p] = nil
                        GiveWeapon(p, "handgun", 0)
                        weapon0 = "handgun"
                        self.sniperEquipTime[p] = nil
                        if cmd == utility.AiCommand.ATTACK then
                            Stop(p)
                        end
                    end
                end

                -- Craft Stealing (Refined: Any unoccupied vehicle)
                local focusingSniperCombat = isSniper and IsValid(sniperTarget) and targetDist < (sniperRange + 40) and grounded and not targetCloaked
                if self.Config.sniperSteal and not focusingSniperCombat then
                    local target = GetTarget(p)
                    -- If they have no target or current target is not stealable, look for nearby empty craft
                    if not IsValid(target) or not IsCraft(target) or IsAliveAndPilot(target) then
                        if now >= (self.pilotStealScanAt[p] or 0.0) then
                            self.pilotStealScanAt[p] = now + 1.25
                            for obj in ObjectsInRange(150, p) do
                                if IsCraft(obj) and not IsAliveAndPilot(obj) then
                                    target = obj
                                    SetTarget(p, obj) -- Record finding
                                    break
                                end
                            end
                        end
                        target = GetTarget(p)
                    end

                    if IsValid(target) and IsCraft(target) and not IsAliveAndPilot(target) then
                        -- A pilot cannot move with a sniper rifle equipped.
                        if weapon0 ~= "" and string.find(weapon0, "gsnipe") then
                            self.sniperAttackTarget[p] = nil
                            GiveWeapon(p, "handgun", 0)
                            weapon0 = "handgun"
                            self.sniperEquipTime[p] = nil
                            if actionReady then
                                self.pilotActionTimer[p] = now + 0.6
                            end
                        elseif GetDistance(p, target) < 10 then -- Narrowed for GetIn
                            if actionReady then
                                GetIn(p, target)
                                self.pilotActionTimer[p] = now + 1.5
                                if aiCore.Debug then print("Team " .. self.teamNum .. " pilot stealing craft: " .. GetOdf(target)) end
                            end
                        else
                            if actionReady and (GetCurrentCommand(p) ~= utility.AiCommand.GO or GetCurrentWho(p) ~= target) then
                                aiCore.TrySetCommand(p, utility.AiCommand.GO, GetCommandableAttackPriority(), target, nil, nil, nil,
                                    { minInterval = 0.8, overrideProtected = true }) -- High priority move to craft
                                self.pilotActionTimer[p] = now + 1.0
                            end
                        end
                    end
                end

                -- Idle Patrol / Wander (Refined: Stay near base)
                if not IsBusy(p) then
                    if now > (self.pilotPatrolTimer[p] or 0) then
                        self.pilotPatrolTimer[p] = now + 15.0 + math.random(10)

                        local base = self.recyclerMgr.handle
                        if IsValid(base) then
                            local center = GetPosition(base)
                            local roamPos = GetPositionNear(center, 40, 150)
                            aiCore.TrySetCommand(p, utility.AiCommand.GO, GetUncommandablePriority(), nil, roamPos, nil, nil,
                                { minInterval = 1.0 })
                        end
                    end
                end
            end
        end
    end
end

----------------------------------------------------------------------------------
-- TACTICAL LOGIC EXTENSIONS
----------------------------------------------------------------------------------

function aiCore.Team:GetValidFlankPosition(target, angle)
    local distances = { 600, 450, 320 }
    for _, dist in ipairs(distances) do
        local flankPos = aiCore.GetFlankPosition(target, dist, angle)
        if flankPos then
            flankPos.y = GetTerrainHeight(flankPos.x, flankPos.z)
            local isFlat = aiCore.IsAreaFlat(flankPos, 16, 8, 0.90, 0.60)
            if isFlat then
                return flankPos
            end
        end
    end
    return nil
end

function aiCore.Team:UpdateSquads()
    local function RollFlankAttackStyle()
        local chance = self.Config.flankFormationRushChance
        if chance == nil then chance = 40 end
        if chance < 0 then chance = 0 end
        if chance > 100 then chance = 100 end

        -- Apply this aggression variant primarily to enemies of the player.
        if not aiCore.IsEnemyOfPlayerTeam(self.teamNum) then
            chance = math.min(chance, 15)
        end
        return (math.random(100) <= chance) and "formation_rush" or "independent"
    end

    local function RollFlankEngagement()
        local chance = self.Config.flankAttackChance
        if chance == nil then chance = 55 end
        if chance < 0 then chance = 0 end
        if chance > 100 then chance = 100 end

        -- Prefer fewer staged flanks for non-player enemies.
        if not aiCore.IsEnemyOfPlayerTeam(self.teamNum) then
            chance = math.min(chance, 25)
        end
        return (math.random(100) <= chance)
    end

    local function IssueGoalOrders(squad, leader, goal, angle)
        if not squad or not goal then return false end

        squad:SetStrategicGoal(goal, self)

        if goal.mode == "attack" then
            local target = squad:ResolveStrategicTarget()
            if not IsValid(target) then return false end

            if RollFlankEngagement() then
                local flankPos = self:GetValidFlankPosition(target, angle)
                squad.flankStartTime = GetTime()
                if flankPos then
                    squad.targetPos = flankPos
                    squad.state = "moving_to_flank"
                    aiCore.TrySetCommand(leader, AiCommand.GO, GetUncommandablePriority(), nil, flankPos, nil, nil,
                        { minInterval = 0.7, ignoreThrottle = true })
                    for _, m in ipairs(squad.members) do
                        if IsValid(m) then
                            aiCore.TrySetCommand(m, AiCommand.GO, GetUncommandablePriority(), nil, flankPos, nil, nil,
                                { minInterval = 0.7, ignoreThrottle = true })
                        end
                    end
                else
                    squad.state = "attacking"
                    squad:IssueAttackOrders(target)
                end
            else
                squad.state = "attacking"
                squad:IssueAttackOrders(target)
            end
            self.lastLaunchedGoalKey = goal.key
            return true
        end

        squad.state = "attacking"
        local target = squad:ResolveStrategicTarget()
        if IsValid(target) then
            squad:IssueAttackOrders(target)
        else
            squad:IssueDefendOrders()
        end
        self.lastLaunchedGoalKey = goal.key
        return true
    end

    -- 1. Manage Pool (Form Squads)
    aiCore.RemoveDead(self.pool)
    PruneSpecializedPoolUnits(self.pool)
    local poolStrength = self:GetPoolStrength()
    if poolStrength > 0.0 then
        local launchOrigin = IsValid(self.recyclerMgr.handle) and self.recyclerMgr.handle or self.pool[1]
        local goal = self:SelectStrategicGoal(launchOrigin, poolStrength, { previousGoalKey = self.lastLaunchedGoalKey })
        if goal then
            local newSquad, leader = self:BuildSquadFromPoolForGoal(goal)
            if leader and IsValid(leader) then
                newSquad:SetAttackStyle((goal.mode == "attack") and RollFlankAttackStyle() or "independent")
                local baseAngle = math.random(0, 359)
                if IssueGoalOrders(newSquad, leader, goal, baseAngle) then
                    table.insert(self.squads, newSquad)
                    if aiCore.Debug then
                        print("Team " .. self.teamNum .. " formed squad for " .. tostring(goal.mode) .. " goal.")
                    end
                else
                    UniqueInsert(self.pool, leader)
                    for _, member in ipairs(newSquad.members) do
                        if IsValid(member) then
                            UniqueInsert(self.pool, member)
                        end
                    end
                end

                local remainingStrength = self:GetPoolStrength()
                if goal.mode == "attack" and remainingStrength > 0.0 and math.random(100) <= 35 then
                    local pincerGoal = self:SelectStrategicGoal(launchOrigin, remainingStrength,
                        { previousGoalKey = goal.key })
                    if pincerGoal and pincerGoal.key == goal.key then
                        local pincerSquad, pincerLeader = self:BuildSquadFromPoolForGoal(pincerGoal)
                        if pincerLeader and IsValid(pincerLeader) then
                            pincerSquad:SetAttackStyle(RollFlankAttackStyle())
                            local oppositeAngle = (baseAngle + 180) % 360
                            if IssueGoalOrders(pincerSquad, pincerLeader, pincerGoal, oppositeAngle) then
                                table.insert(self.squads, pincerSquad)
                                if aiCore.Debug then
                                    print("Team " .. self.teamNum .. " launched pincer flank.")
                                end
                            else
                                UniqueInsert(self.pool, pincerLeader)
                                for _, member in ipairs(pincerSquad.members) do
                                    if IsValid(member) then
                                        UniqueInsert(self.pool, member)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2. Update Squads
    for i = #self.squads, 1, -1 do
        local sq = self.squads[i]
        if not sq:Update() or (#sq.members == 0 and not IsValid(sq.leader)) then
            table.remove(self.squads, i)
        end
    end
end

function aiCore.Team:UpdateUpgrades()
    -- Logic from aiSpecial: Upgrade turrets and launch powerups
    if not self.upgradeTimer then self.upgradeTimer = GetTime() + (self.Config.upgradeInterval or 240) end

    if GetTime() > self.upgradeTimer then
        self.upgradeTimer = GetTime() + (self.Config.upgradeInterval or 240)

        -- Launch Powerups from Armory
        local armory = GetArmoryHandle(self.teamNum)
        if IsValid(armory) and CanBuild(armory) then
            -- Find targets (Turrets without ammo, damaged buildings)
            local target = nil
            local powerup = "apammo"

            -- 1. Heal/Resupply Turrets
            for obj in ObjectsInRange(500, armory) do -- Range check optimization
                if GetTeamNum(obj) == self.teamNum then
                    local isBuilding = IsBuilding(obj)
                    if GetHealth(obj) < 0.5 then
                        target = obj
                        powerup = "aprepa"
                        break
                    elseif not isBuilding and GetAmmo(obj) < 0.3 then
                        target = obj
                        powerup = "apammo"
                        break
                    end
                end
            end

            ---@cast target any
            if IsValid(target) then
                -- BUG FIX: Record target for Team 1 workaround in AddObject
                self.lastArmoryTarget = target
                if IsValid(armory) then
                    ---@cast armory any
                    ---@cast powerup any
                    BuildAt(armory, powerup, target, 1)
                end
                if aiCore.Debug then print("Team " .. self.teamNum .. " launching " .. powerup) end
            end
        end
    end
end

function aiCore.Team:GetUnitCountByCategory(category)
    local count = 0
    -- Treat 'heavy' as 'walker' and 'siege' as 'howitzer' for ODF lookup
    local effectiveCategory = category
    if category == "heavy" then
        effectiveCategory = "walker"
    elseif category == "siege" then
        effectiveCategory = "howitzer"
    end
    local odfToMatch = aiCore.Units[self.faction][effectiveCategory]
    local seen = {}
    local function CountUnit(unit)
        if odfToMatch and IsValid(unit) and IsAlive(unit) and not seen[unit] and IsOdf(unit, odfToMatch) then
            seen[unit] = true
            count = count + 1
        end
    end

    -- 1. Check Tactical Lists (Active Units)
    if category == "scout" or category == "tank" or category == "lighttank" or category == "rockettank" or
        category == "bomber" or category == "unique" or category == "heavy" or category == "walker" then
        for _, u in ipairs(self.combatUnits) do
            CountUnit(u)
        end
        for _, u in ipairs(self.pool) do
            CountUnit(u)
        end
    elseif category == "siege" or category == "howitzer" then
        count = #self.howitzers
    elseif category == "scavenger" then
        count = #self.scavengers
    elseif category == "apc" then
        count = #self.apcs
    elseif category == "minelayer" then
        count = #self.minelayers
    elseif category == "tower" or category == "turret" then
        count = #self.turrets
    elseif category == "tug" then
        count = #self.tugHandles
    end

    -- 2. Check Integrated Producer (Units in progress)
    if odfToMatch and producer.Queue[self.teamNum] then
        for _, job in ipairs(producer.Queue[self.teamNum]) do
            if job.odf == odfToMatch then
                count = count + 1
            end
        end
    end

    return count
end

function aiCore.Team:CheckBuildList(list, mgr)
    local priorities = {}
    for p in pairs(list) do table.insert(priorities, p) end
    table.sort(priorities, function(a, b) return a < b end)

    for _, p in ipairs(priorities) do
        local item = list[p]
        if not IsValid(item.handle) then
            -- Link-up logic for existing objects
            local anchor = mgr.handle or GetRecyclerHandle(self.teamNum)
            local nearby = IsValid(anchor) and GetNearestObject(anchor) or nil
            if IsValid(anchor) and IsValid(nearby) and IsOdf(nearby, item.odf) and GetDistance(nearby, anchor) < 150 and GetTeamNum(nearby) == self.teamNum then
                local taken = false
                for _, other in pairs(list) do
                    if other.handle == nearby then
                        taken = true
                        break
                    end
                end
                if not taken then
                    item.handle = nearby
                end
            end

            if not IsValid(item.handle) then
                local inQueue = false
                -- Check aiCore shadow queue
                for _, qItem in ipairs(mgr.queue) do
                    if qItem.priority == p then
                        inQueue = true
                        break
                    end
                end

                if not inQueue then
                    -- DIFFICULTY CAP CHECK
                    local cap_reached = false
                    local allowed, ruleReason = self:CanQueueUnitByRules(item.category, item.odf)
                    if not allowed then
                        cap_reached = true
                        if aiCore.Debug then
                            print("aiCore: Team " .. self.teamNum .. " skipping " .. item.odf .. " (" .. tostring(ruleReason) .. ")")
                        end
                    end
                    local caps = self.Config.unitCaps
                    if not cap_reached and caps and item.category then
                        local cap = caps[item.category]
                        if cap then
                            local currentCount = self:GetUnitCountByCategory(item.category)
                            if currentCount >= cap then
                                cap_reached = true
                                if aiCore.Debug then
                                    print("aiCore: Team " ..
                                        self.teamNum ..
                                        " skipping " ..
                                        item.odf .. " (Cap reached: " .. currentCount .. "/" .. cap .. ")")
                                end
                            end
                        end
                    end

                    if not cap_reached then
                        -- Record in shadow queue to prevent double-ordering
                        table.insert(mgr.queue, {
                            odf = item.odf,
                            priority = p,
                            account = item.account,
                            category = item.category,
                            producer = item.producer
                        })
                        table.sort(mgr.queue, function(a, b)
                            local ap = a.priority or 999999
                            local bp = b.priority or 999999
                            if self.GetEffectiveBuildPriority then
                                ap = self:GetEffectiveBuildPriority(a.account, ap, a)
                                bp = self:GetEffectiveBuildPriority(b.account, bp, b)
                            end
                            if ap == bp then return (a.priority or 999999) < (b.priority or 999999) end
                            return ap < bp
                        end)

                        -- Hand off to integrated producer
                        producer.QueueJob(item.odf, self.teamNum, nil, nil,
                            {
                                source = "aiCore",
                                priority = p,
                                type = "unit",
                                producer = (mgr.isRecycler and "recycler" or "factory"),
                                account = item.account,
                                category = item.category
                            })

                        if aiCore.Debug then print("aiCore: Team " .. self.teamNum .. " queued " .. item.odf .. " (unit)") end
                    end
                end
            end
        end
    end
end

function aiCore.Team:CheckConstruction()
    local priorities = {}
    for p in pairs(self.buildingList) do table.insert(priorities, p) end
    table.sort(priorities, function(a, b) return a < b end)

    for _, p in ipairs(priorities) do
        local item = self.buildingList[p]
        if not IsValid(item.handle) then
            local pos = item.path
            if type(pos) == "string" then pos = paths.GetPosition(pos, 0) end

            local found = nil
            if pos then
                for obj in ObjectsInRange(60, pos) do
                    if IsOdf(obj, item.odf) and GetTeamNum(obj) == self.teamNum then
                        found = obj
                        break
                    end
                end
            end

            if found then
                item.handle = found
            else
                local inQueue = false
                for _, qItem in ipairs(self.constructorMgr.queue) do
                    if qItem.priority == p then
                        inQueue = true
                        break
                    end
                end
                if not inQueue then
                    local allowed, ruleReason = self:CanQueueBuildingByRules(item.odf)
                    if allowed then
                        table.insert(self.constructorMgr.queue, {
                            odf = item.odf,
                            path = item.path,
                            priority = p,
                            account = item.account
                        })
                        table.sort(self.constructorMgr.queue, function(a, b)
                            local ap = a.priority or 999999
                            local bp = b.priority or 999999
                            if self.GetEffectiveBuildPriority then
                                ap = self:GetEffectiveBuildPriority(a.account, ap, a)
                                bp = self:GetEffectiveBuildPriority(b.account, bp, b)
                            end
                            if ap == bp then return (a.priority or 999999) < (b.priority or 999999) end
                            return ap < bp
                        end)

                        if aiCore.Debug then
                            print("aiCore: Team " .. self.teamNum .. " queued building for constructor: " .. item.odf)
                        end
                    elseif aiCore.Debug then
                        print("aiCore: Team " .. self.teamNum .. " skipping building " .. item.odf .. " (" .. tostring(ruleReason) .. ")")
                    end
                end
            end
        end
    end
end

function aiCore.Team:AddObject(h)
    -- Duplicate check
    if aiCore.IsTracked(h, self.teamNum) then return end
    if (IsCraft(h) or IsPerson(h)) and IsIndependenceLocked(h) then return end

    local odf = string.lower(utility.CleanString(GetOdf(h)))
    local cls = string.lower(utility.CleanString(GetClassLabel(h)))
    local isApc = string.find(cls, utility.ClassLabel.APC) ~= nil
    local isSpecializedPoolUnit = IsSpecializedPoolClass(cls)
    local units = aiCore.Units[self.faction] or {}
    local isArmory = (cls == utility.ClassLabel.ARMORY) or
        (units.armory and odf == string.lower(utility.CleanString(units.armory)))

    -- BUG FIX: Day Wrecker / Powerup Workaround (Team 1 + GO command)
    -- As seen in aiSpecial.CreateWrecker: projectiles need Team 1 to receive GO commands properly in BZR
    if (cls == "daywrecker" or cls == "ammopack" or cls == "repairkit" or cls == "wpnpower" or cls == "camerapod") then
        if self.teamNum ~= 1 then -- If it belongs to an AI team
            SetTeamNum(h, 1)      -- Swap to player team
            if IsValid(self.lastArmoryTarget) then
                aiCore.TrySetCommand(h, AiCommand.GO, 1, self.lastArmoryTarget, nil, nil, nil,
                    { minInterval = 0.6, ignoreThrottle = true, overrideProtected = true })
                if aiCore.Debug then
                    print("AI Powerup Workaround Applied: " ..
                        odf .. " -> Team 1 (Target: " .. utility.CleanString(GetOdf(self.lastArmoryTarget)) .. ")")
                end
            end
        end
    end

    -- MODIFIED: Integrated Producer Tracking
    if producer.ProcessCreated(h) then
        if aiCore.Debug then print("aiCore: Integrated Producer -> Built " .. odf) end
    end

    if isArmory and aiCore.IsEnemyOfPlayerTeam(self.teamNum) then
        if math.random(100) <= 10 then
            self:StartArmorySuicide(h)
        end
    end

    -- Link to build lists
    local linked = false
    local function link(list, mgr)
        if not IsValid(mgr.handle) or GetDistance(h, mgr.handle) >= 150 then return end

        local matchedIndex = nil
        local matchedPriority = nil
        for i, q in ipairs(mgr.queue) do
            if q.odf == odf then
                matchedIndex = i
                matchedPriority = q.priority
                break
            end
        end

        if matchedIndex and matchedPriority and list[matchedPriority] then
            list[matchedPriority].handle = h
            table.remove(mgr.queue, matchedIndex)
            linked = true
        end
    end

    link(self.recyclerBuildList, self.recyclerMgr)
    link(self.factoryBuildList, self.factoryMgr)

    -- Constructor linking checks path distance
    for i, qItem in ipairs(self.constructorMgr.queue) do
        if qItem.odf == odf and GetDistance(h, qItem.path) < 60 then
            if self.buildingList[qItem.priority] then
                self.buildingList[qItem.priority].handle = h
            end
            table.remove(self.constructorMgr.queue, i)
            linked = true
            break
        end
    end

    -- Direct Manager Handle Assignments
    if cls == utility.ClassLabel.CONSTRUCTOR then
        if self.constructorMgr then
            self.constructorMgr.handle = h
        end
    end

    -- Scavenger Assist (Auto-Registration)
    if cls == utility.ClassLabel.SCAVENGER then
        self:RegisterScavenger(h)
    end

    -- Add to tactical lists
    if string.find(cls, utility.ClassLabel.HOWITZER) then
        UniqueInsert(self.howitzers, h)
    elseif isApc then
        UniqueInsert(self.apcs, h)
    elseif string.find(cls, utility.ClassLabel.MINELAYER) then
        UniqueInsert(self.minelayers, h)
    elseif string.match(odf, "^cv") or string.match(odf, "^mv") or string.match(odf, "^dv") then
        UniqueInsert(self.cloakers, h)
        if linked then UniqueInsert(self.pool, h) end
    elseif string.find(cls, utility.ClassLabel.TURRET) or string.find(cls, "tower") or string.match(odf, "turr") then
        UniqueInsert(self.turrets, h)
    elseif string.find(cls, utility.ClassLabel.TUG) or string.find(cls, "haul") then
        UniqueInsert(self.tugHandles, h)
    elseif IsPerson(h) and odf == string.lower(aiCore.Units[self.faction].soldier or "") then
        UniqueInsert(self.soldiers, h)
    end

    -- Advanced Weapon Users (from aiSpecial patterns)
    if aiCore.GetWeaponMask(h, { "mortar", "splint", "acidcl", "mdmgun" }) > 0 then UniqueInsert(self.mortars, h) end
    if aiCore.GetWeaponMask(h, { "gquake", "gthumper", "quake", "thump" }) > 0 then UniqueInsert(self.thumpers, h) end
    if aiCore.GetWeaponMask(h, { "phantom", "redfld", "sitecam" }) > 0 then UniqueInsert(self.fields, h) end

    -- Double Weapon Tracking (Wingmen/Walkers)
    if string.find(cls, utility.ClassLabel.WINGMAN) or string.find(cls, utility.ClassLabel.WALKER) then
        UniqueInsert(self.doubleUsers, h)
        if linked and not string.find(cls, utility.ClassLabel.WALKER) then
            UniqueInsert(self.pool, h)
            if IsValid(self.recyclerMgr.handle) and self.teamNum ~= 1 then -- Don't force player units to base
                aiCore.TrySetCommand(h, AiCommand.GO, GetUncommandablePriority(), self.recyclerMgr.handle, nil, nil, nil,
                    { minInterval = 0.8, ignoreThrottle = true })
            end
        end
    end

    -- Soldier Tracking (Person class, excluding pilots/snipers)
    if string.find(cls, utility.ClassLabel.PERSON) then
        local w0 = GetWeaponClass(h, 0)
        local isSniper = w0 and (string.find(string.lower(w0), "snipe") or string.find(string.lower(w0), "handgun"))
        if not isSniper then
            UniqueInsert(self.soldiers, h)
        else
            UniqueInsert(self.pilots, h)
        end
    end

    local isCombatCraft = IsCraft(h) and not IsBuilding(h) and
        not string.find(cls, utility.ClassLabel.SCAVENGER) and
        not string.find(cls, utility.ClassLabel.RECYCLER) and
        not string.find(cls, utility.ClassLabel.FACTORY) and
        not string.find(cls, utility.ClassLabel.CONSTRUCTOR) and
        not string.find(cls, utility.ClassLabel.TUG) and
        not isApc and
        not string.find(cls, utility.ClassLabel.PERSON)
    if isCombatCraft then
        UniqueInsert(self.combatUnits, h)
    end

    if linked and IsCraft(h) then
        local isSupport = string.find(cls, utility.ClassLabel.SCAVENGER) or
            string.find(cls, utility.ClassLabel.RECYCLER) or
            string.find(cls, utility.ClassLabel.FACTORY) or
            string.find(cls, utility.ClassLabel.CONSTRUCTOR) or
            isSpecializedPoolUnit

        if not isSupport then
            local inPool = false
            for _, pooled in ipairs(self.pool) do
                if pooled == h then
                    inPool = true; break
                end
            end
            if not inPool then
                UniqueInsert(self.pool, h)
            end
        end
    end

    if isApc then
        RemoveFromList(self.combatUnits, h)
    end
    if isSpecializedPoolUnit then
        RemoveFromList(self.pool, h)
    end

    -- Route to Phase 1 Managers
    if self.weaponMgr then self.weaponMgr:AddObject(h) end
    if self.cloakMgr then self.cloakMgr:AddObject(h) end
    if self.howitzerMgr then self.howitzerMgr:AddObject(h) end
    if self.minelayerMgr then self.minelayerMgr:AddObject(h) end

    -- Route to Phase 2 Managers
    if self.apcMgr then self.apcMgr:AddObject(h) end
    if self.turretMgr then self.turretMgr:AddObject(h) end
    if self.wingmanMgr then self.wingmanMgr:AddObject(h) end
    if self.defenseMgr then self.defenseMgr:AddObject(h) end
    if self.depotMgr then self.depotMgr:AddObject(h) end
end

---@return any
function aiCore.Team:FindCriticalTarget()
    local origin = self:GetBaseReference() or self.factoryMgr.handle
    local strategicGoal = self:SelectStrategicGoal(origin, math.huge, { attackOnly = true, allowUnderstrength = true })
    if strategicGoal then
        local target = strategicGoal.target
        if IsValid(target) and IsAlive(target) then
            return target
        end
        target = self:ResolveStrategicGoalTarget(strategicGoal)
        if IsValid(target) and IsAlive(target) then
            return target
        end
    end

    local enemyTeam = self:GetPrimaryEnemyTeam()
    if enemyTeam < 0 then enemyTeam = (self.teamNum == 1) and 2 or 1 end
    local recycler = GetRecyclerHandle(enemyTeam)
    if IsAlive(recycler) then return recycler end

    local factory = GetFactoryHandle(enemyTeam)
    if IsAlive(factory) then return factory end

    local armory = GetArmoryHandle(enemyTeam)
    if IsAlive(armory) then return armory end

    local best = nil
    local bestScore = -999999
    for _, obj in ipairs(aiCore.GetCachedTeamTargets(enemyTeam)) do
        if IsValid(obj) and IsBuilding(obj) and IsAlive(obj) then
            local score = self:GetEconomicTargetValue(obj, GetPosition(obj))
            score = score + self:GetHotspotDenialValue(GetPosition(obj))
            if score > bestScore then
                best = obj
                bestScore = score
            end
        end
    end

    return best
end

function aiCore.Team:PlanDefensivePerimeter(powerCount, towersPerPower)
    -- Default to 4 powers and 4 towers (1 per power) if not specified
    powerCount = powerCount or 4
    towersPerPower = towersPerPower or 1

    local recycler = GetRecyclerHandle(self.teamNum)
    local recyclerPos = self:GetBaseCenter(true) or (IsValid(recycler) and GetPosition(recycler) or nil)
    if not recyclerPos then return end

    -- Smart Power Selection
    local powerKey = aiCore.DetectWorldPower()
    local powerOdf = aiCore.Units[self.faction][powerKey]
    -- Fallback if specific power ODF missing for faction
    if not powerOdf then powerOdf = aiCore.Units[self.faction].sPower end

    local towerOdf = aiCore.Units[self.faction].gunTower

    local foundPowers = 0
    local startPriority = 10 -- Start building after core infrastructure

    -- Use math.pi / 4 (45 degrees) for 8 points, or more if powerCount is high
    local step = (powerCount > 8) and (2 * math.pi / powerCount) or (math.pi / 4)

    for angle = 0, 2 * math.pi, step do
        if foundPowers >= powerCount then break end

        local dist = 120.0
        local x = recyclerPos.x + dist * math.cos(angle)
        local z = recyclerPos.z + dist * math.sin(angle)
        local pPos = SetVector(x, GetTerrainHeight(x, z), z)

        if aiCore.IsAreaFlat(pPos, 12, 8, 0.96, 0.7) and self:CheckBuildingSpacing(powerOdf, pPos, 60) then
            -- Found spot for power
            local pMat = BuildDirectionalMatrix(pPos, Normalize(pPos - recyclerPos))
            foundPowers = foundPowers + 1

            -- Interleaved Priority: One Power then its Towers
            -- Power gets 10, 20, 30... Towers get 11, 12, 21, 22...
            local pPrio = startPriority + (foundPowers * 10)
            self:AddBuilding(powerOdf, pMat, pPrio)

            -- Find spots for towers nearby
            local foundTowers = 0
            for tAngle = angle - 0.5, angle + 0.5, 0.2 do
                if foundTowers >= towersPerPower then break end

                local tX = pPos.x + 40.0 * math.cos(tAngle)
                local tZ = pPos.z + 40.0 * math.sin(tAngle)
                local tPos = SetVector(tX, GetTerrainHeight(tX, tZ), tZ)

                if aiCore.IsAreaFlat(tPos, 8, 4, 0.92, 0.5) and self:CheckBuildingSpacing(towerOdf, tPos, 35) then
                    local tMat = BuildDirectionalMatrix(tPos, Normalize(tPos - recyclerPos))
                    foundTowers = foundTowers + 1
                    self:AddBuilding(towerOdf, tMat, pPrio + foundTowers)
                end
            end
        end
    end
end

----------------------------------------------------------------------------------
-- MAIN INTERFACE
----------------------------------------------------------------------------------

aiCore.ActiveTeams = {}
aiCore.GlobalDefenseManagers = {} -- team -> DefenseManager for non-AI teams (like Team 1)
aiCore.GlobalDepotManagers = {}   -- team -> DepotManager
aiCore.GlobalOffenseManagers = {} -- team -> OffenseRetaliationManager

function aiCore.AddTeam(teamNum, faction)
    local t = aiCore.Team:new(teamNum, faction)
    if DiffUtils and DiffUtils.ApplyAiCoreDifficulty then
        DiffUtils.ApplyAiCoreDifficulty(t, nil, teamNum)
    end
    aiCore.ActiveTeams[teamNum] = t
    return t
end

function aiCore.ResetTeam(teamNum, faction, configTemplate)
    local previous = aiCore.ActiveTeams[teamNum]
    local nextFaction = faction or (previous and previous.faction) or 1
    local t = aiCore.Team:new(teamNum, nextFaction)
    local sourceConfig = configTemplate or (previous and previous.Config) or nil

    if sourceConfig then
        t.Config = DeepCopyValue(sourceConfig)
    end

    if previous then
        t.strategy = previous.strategy
        t.baseStrategy = previous.baseStrategy
        t.strategyLocked = previous.strategyLocked
    end

    if producer and producer.Queue then
        producer.Queue[teamNum] = {}
    end

    aiCore.ActiveTeams[teamNum] = t
    return t
end

function aiCore.SyncPilotPersonTracking()
    local player = GetPlayerHandle()
    for _, h in ipairs(aiCore.GetCachedPilotPersons()) do
        if IsValid(h) and IsAlive(h) and IsPerson(h) and h ~= player and not IsOdf(h, "aspiloh") then
            local teamNum = GetTeamNum(h)
            local team = aiCore.ActiveTeams[teamNum]
            if team and not aiCore.IsTracked(h, teamNum) then
                local w0 = string.lower(utility.CleanString(GetWeaponClass(h, 0)))
                local odf = string.lower(utility.CleanString(GetOdf(h)))
                local isPilotLike = string.find(w0, "handgun")
                    or string.find(w0, "gsnipe")
                    or string.find(odf, "spilo")
                    or string.find(odf, "pilot")

                if isPilotLike then
                    team:AddObject(h)
                    if aiCore.Debug then
                        print("aiCore: late-registered pilot/person " .. tostring(GetOdf(h)) .. " for team " .. tostring(teamNum))
                    end
                end
            end
        end
    end
end

function aiCore.Update()
    aiCore.SetupOrdnanceHooks()

    local now = GetTime()
    if now >= (aiCore._exuMuxCheckTimer or 0.0) then
        aiCore._exuMuxCheckTimer = now + 1.0
        aiCore.EnsureExuCallbackMultiplexer()
    end

    aiCore.RefreshObjectCache(false)
    aiCore.UpdateTrackedOrdnanceThreats()
    aiCore.UpdateTrackedMissileAllocations()
    aiCore.UpdatePlayerRushAggression()

    if now >= (aiCore._commandStateCleanupTimer or 0.0) then
        aiCore._commandStateCleanupTimer = now + 60.0
        for h, _ in pairs(aiCore.CommandState) do
            if not IsValid(h) then
                aiCore.CommandState[h] = nil
            end
        end
        for h, _ in pairs(aiCore.CountermeasureState or {}) do
            if not IsValid(h) then
                aiCore.CountermeasureState[h] = nil
            end
        end
    end

    if now >= (aiCore._pilotSyncTimer or 0.0) then
        aiCore._pilotSyncTimer = now + 5.0
        aiCore.SyncPilotPersonTracking()
    end

    -- Update AI Teams
    for _, team in pairs(aiCore.ActiveTeams) do
        team:Update()
    end

    -- Update Global/Player Defenses
    for team = 0, 15 do
        if not aiCore.ActiveTeams[team] then
            if not aiCore.GlobalDefenseManagers[team] then
                aiCore.GlobalDefenseManagers[team] = aiCore.DefenseManager.new(team)
            end
            if not aiCore.GlobalDepotManagers[team] then
                aiCore.GlobalDepotManagers[team] = aiCore.DepotManager.new(team)
            end
            if not aiCore.GlobalOffenseManagers[team] then
                aiCore.GlobalOffenseManagers[team] = aiCore.OffenseRetaliationManager.new(team)
            end
            aiCore.GlobalDefenseManagers[team]:Update()
            aiCore.GlobalDepotManagers[team]:Update()
            aiCore.GlobalOffenseManagers[team]:Update()
        end
    end

    local exuLib = rawget(_G, "exu")
    if exuLib and exuLib.UpdateCommandReplacements then
        exuLib.UpdateCommandReplacements()
    end
end

function aiCore.AddObject(h)
    if not IsValid(h) then return end
    if (IsCraft(h) or IsPerson(h)) and IsIndependenceLocked(h) then return end
    aiCore.TrackWorldObject(h)

    -- Apply Dynamic Mass to all crafts registered
    if IsCraft(h) then
        aiCore.ApplyDynamicMass(h)
    end

    local teamNum = GetTeamNum(h)

    -- AI Team Logic
    local team = aiCore.ActiveTeams[teamNum]
    if team then
        team:AddObject(h)
    end

    -- Global/Player Logic (Ensure Team 1 turrets are tracked)
    if not team then
        if not aiCore.GlobalDefenseManagers[teamNum] then
            aiCore.GlobalDefenseManagers[teamNum] = aiCore.DefenseManager.new(teamNum)
        end
        if not aiCore.GlobalDepotManagers[teamNum] then
            aiCore.GlobalDepotManagers[teamNum] = aiCore.DepotManager.new(teamNum)
        end
        if not aiCore.GlobalOffenseManagers[teamNum] then
            aiCore.GlobalOffenseManagers[teamNum] = aiCore.OffenseRetaliationManager.new(teamNum)
        end

        -- Safely call manager methods
        local defMgr = aiCore.GlobalDefenseManagers[teamNum]
        local depMgr = aiCore.GlobalDepotManagers[teamNum]
        local offMgr = aiCore.GlobalOffenseManagers[teamNum]

        if defMgr and defMgr.AddObject then defMgr:AddObject(h) end
        if depMgr and depMgr.AddObject then depMgr:AddObject(h) end
        if offMgr and offMgr.AddObject then offMgr:AddObject(h) end
    end
end

function aiCore.DeleteObject(h)
    aiCore.UntrackWorldObject(h)
end

-- Helper to set up construction
function aiCore.SetupBase(teamNum, buildings)
    -- buildings = {{odf="avrecy", path="path1"}, ...}
    local team = aiCore.ActiveTeams[teamNum]
    if not team then return end

    for i, b in ipairs(buildings) do
        team:AddBuilding(b.odf, b.path, i)
    end
end

-- Phased Construction Helper
function aiCore.Team:QueuePhasedBuildings(buildingList)
    local startPriority = #self.buildingList + 1
    for i, b in ipairs(buildingList) do
        self:AddBuilding(b.odf, b.path, startPriority + i - 1)
    end
end

----------------------------------------------------------------------------------
-- GLOBAL API WRAPPERS
----------------------------------------------------------------------------------

-- Make SetAIP available globally for mission scripts
function SetAIP(aipFile, teamNum)
    if aiCore and aiCore.SetAIP then
        return aiCore.SetAIP(aipFile, teamNum)
    end
    return false
end

return aiCore
