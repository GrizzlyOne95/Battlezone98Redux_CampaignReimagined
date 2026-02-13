-- aiCore.lua
-- Consolidated AI System for Battlezone 98 Redux
-- Combines functionality from pilotMode, autorepair, aiFacProd, aiRecProd, aiBuildOS, and aiSpecial
-- Supported Factions: NSDF, CCA, CRA, BDOG

local DiffUtils = require("DiffUtils")

-- Polyfills

function AllBuildings()
    local t = {}
    for h in AllObjects() do if IsBuilding(h) then table.insert(t, h) end end
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

local function FireWeaponMask(h, mask)
    SetWeaponMask(h, mask)
    local t = GetTarget(h); if IsValid(t) then FireAt(h, t) end
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
    SPRAYBOMB = "spraybomb"               -- Deployed splinter mortar
}

-- Clean strings of null padding (Engine Bug Fix)
function utility.CleanString(s)
    if not s then return "" end
    -- Some engine functions return strings with trailing null bytes (\0)
    -- This breaks string comparisons (e.g. "avtank\0\0" ~= "avtank")
    local cleaned = tostring(s):gsub("%z.*", "")
    return cleaned
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
}
function utility.IsTable(object) return (type(object) == 'table') end

function utility.IsVector(object)
    if type(object) ~= "userdata" then return false end
    local mt = getmetatable(object)
    return mt and mt.__type == "VECTOR_3D"
end

----------------------------------------------------------------------------------
-- INTEGRATED PATHS
----------------------------------------------------------------------------------
local paths = {}
function paths.GetPosition(p, pt)
    pt = pt or 0
    if GetPathPointCount(p) > pt then return GetPosition(p, pt) end
    return nil
end

function paths.GetPathPointCount(p) return GetPathPointCount(p) or 0 end

function paths.IteratePath(p)
    local count = paths.GetPathPointCount(p)
    local i = 0
    return function()
        if i < count then
            local pos = paths.GetPosition(p, i); i = i + 1; return i, pos
        end
    end
end

----------------------------------------------------------------------------------
-- INTEGRATED PRODUCER
----------------------------------------------------------------------------------
local producer = {
    Queue = {}, -- table<TeamNum, list<Job>>
    Orders = {} -- table<Handle, Job>
}
function producer.QueueJob(odf, team, location, builder, data)
    if not producer.Queue[team] then producer.Queue[team] = {} end
    table.insert(producer.Queue[team], {
        odf = odf,
        location = location,
        builder = builder, -- TeamSlotInteger (Optional)
        data = data
    })
end

function producer.ProcessQueues(teamObj)
    if teamObj.Config and not teamObj.Config.manageFactories then return end
    local team = teamObj.teamNum
    local queue = producer.Queue[team]
    if not queue or #queue == 0 then return end

    -- Identify available producers
    local producers = {}
    if IsValid(teamObj.recyclerMgr.handle) and not IsBusy(teamObj.recyclerMgr.handle) then
        table.insert(producers, teamObj.recyclerMgr.handle)
    end
    if IsValid(teamObj.factoryMgr.handle) and not IsBusy(teamObj.factoryMgr.handle) and IsDeployed(teamObj.factoryMgr.handle) then
        table.insert(producers, teamObj.factoryMgr.handle)
    end
    if IsValid(teamObj.constructorMgr.handle) and not IsBusy(teamObj.constructorMgr.handle) then
        table.insert(producers, teamObj.constructorMgr.handle)
    end

    if #producers == 0 then return end

    local scrap = GetScrap(team)
    local maxScrap = GetMaxScrap(team)
    local pilot = GetPilot(team)

    local removals = {}
    local removals = {}

    -- Helper functions for costs
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

        if cost <= maxScrap and pilotCost <= pilot then
            if cost <= scrap then
                -- Find compatible producer
                local foundProducer = nil
                for _, h in ipairs(producers) do
                    -- Simple compatibility check: constructor for buildings, others for units
                    local isBuilding = IsBuilding(job.odf) or string.match(job.odf, "^[I|i|b|B][B|b]")
                    local procSig = utility.CleanString(GetClassLabel(h))

                    local canBuild = false
                    if isBuilding and procSig == "constructionrig" then
                        canBuild = true
                    elseif not isBuilding and (procSig == "recycler" or procSig == "factory") then
                        canBuild = true
                    end

                    if canBuild and not producer.Orders[h] then
                        foundProducer = h
                        break
                    end
                end

                if foundProducer then
                    if job.location then
                        -- Handle path or position
                        local pos = job.location
                        if type(pos) == "string" then pos = paths.GetPosition(pos, 0) end
                        SetCommand(foundProducer, AiCommand.BUILD, 1, nil, pos, 0, job.odf)
                    else
                        Build(foundProducer, job.odf)
                    end
                    producer.Orders[foundProducer] = job
                    table.insert(removals, i)
                    -- Remove producer from available list for this tick
                    for idx, h in ipairs(producers) do
                        if h == foundProducer then
                            table.remove(producers, idx); break
                        end
                    end
                end
            else
                break -- Wait for scrap if we can't afford the next high-priority item
            end
        end
        if #producers == 0 then break end
    end

    -- Clean up queue
    for i = #removals, 1, -1 do
        table.remove(queue, removals[i])
    end
end

function producer.ProcessCreated(h)
    local odf = string.lower(utility.CleanString(GetOdf(h)))
    for proc, job in pairs(producer.Orders) do
        if IsValid(proc) and string.lower(job.odf) == odf then
            local dist = GetDistance(h, proc)
            if dist < 100 then
                -- Match found
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

local Tokenizer = {}
Tokenizer.__index = Tokenizer
function Tokenizer.new(data)
    return setmetatable({ data = data, pos = 1, version = 1000, type_size = 2, size_size = 2 }, Tokenizer)
end

function Tokenizer:ReadToken()
    if self.pos > #self.data then return nil end
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
            local b1, b2, b3, b4 = string.byte(s.data, 1, 4); return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
        end,
        GetBoolean = function(s) return string.byte(s.data, 1) ~= 0 end,
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


local aiCore = {}
aiCore.Debug = false

function aiCore.Save()
    return {
        teams = aiCore.ActiveTeams,
        globalDefense = aiCore.GlobalDefenseManagers,
        globalDepot = aiCore.GlobalDepotManagers
    }
end

function aiCore.NilToString(s)
    if s == nil then return "" end
    return tostring(s)
end

function aiCore.GetWeaponMask(h, search)
    if type(search) == "string" then search = { search } end
    for i = 0, 4 do
        local w = utility.CleanString(GetWeaponClass(h, i))
        if w ~= "" then
            w = string.lower(w)
            for _, s in ipairs(search) do
                if string.find(w, string.lower(s)) then
                    return 2 ^ i
                end
            end
        end
    end
    return 0
end

function aiCore.Load(data)
    if not data then return end

    if data.teams then
        aiCore.ActiveTeams = data.teams
        aiCore.GlobalDefenseManagers = data.globalDefense or {}
        aiCore.GlobalDepotManagers = data.globalDepot or {}
    else
        aiCore.ActiveTeams = data
        aiCore.GlobalDefenseManagers = {}
        aiCore.GlobalDepotManagers = {}
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
        if team.weaponMgr then setmetatable(team.weaponMgr, aiCore.WeaponManager) end
        if team.cloakMgr then setmetatable(team.cloakMgr, aiCore.CloakingManager) end
        if team.howitzerMgr then setmetatable(team.howitzerMgr, aiCore.HowitzerManager) end
        if team.minelayerMgr then setmetatable(team.minelayerMgr, aiCore.MinelayerManager) end

        -- Restore Phase 2 Managers
        if team.apcMgr then
            setmetatable(team.apcMgr, aiCore.APCManager); team.apcMgr.teamObj = team
        end
        if team.turretMgr then setmetatable(team.turretMgr, aiCore.TurretManager) end
        if team.guardMgr then setmetatable(team.guardMgr, aiCore.GuardManager) end
        if team.wingmanMgr then setmetatable(team.wingmanMgr, aiCore.WingmanManager) end
        if team.defenseMgr then setmetatable(team.defenseMgr, aiCore.DefenseManager) end
        if team.depotMgr then setmetatable(team.depotMgr, aiCore.DepotManager) end

        -- Restore Squad Metatables
        if team.squads then
            for _, squad in ipairs(team.squads) do
                setmetatable(squad, aiCore.Squad)
            end
        end
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
        if string.find(terrain, "venus") then
            aiCore.WorldPowerKey = "lPower"
        elseif string.find(terrain, "mars") or string.find(terrain, "titan") or string.find(terrain, "achilles") or string.find(terrain, "elysium") then
            aiCore.WorldPowerKey = "wPower"
        else
            aiCore.WorldPowerKey = "sPower"
        end
        if aiCore.Debug then print("aiCore: Smart Power Detection (BZN Metadata) -> " .. aiCore.WorldPowerKey) end
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
        Factory = { "lighttank", "lighttank", "lighttank", "lighttank", "lighttank", "scout", "scout", "bomber", "bomber", "bomber", "bomber", "rockettank", "rockettank", "rockettank", "rockettank", "rockettank", "rockettank", "rockettank", "rockettank" }
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
    local thumperMask = aiCore.GetWeaponMask(h, "gthumper")
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
        if GetWeaponClass(h, i) then weaponCount = weaponCount + 1 end
    end
    if weaponCount >= 2 then
        table.insert(self.doubleUsers, h)
        if aiCore.Debug then print("Team " .. self.teamNum .. " added double weapon user: " .. GetOdf(h)) end
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
end

function aiCore.WeaponManager:UpdateThumpers(dt)
    for i = #self.thumperUsers, 1, -1 do
        local user = self.thumperUsers[i]
        if not IsValid(user.handle) then
            table.remove(self.thumperUsers, i)
        else
            user.timer = user.timer + dt

            -- Pulse cycle: fire for duration, wait for period
            local cycleTime = user.timer % self.thumperPeriod
            if cycleTime < self.thumperDuration then
                -- Fire thumper
                if math.random(100) < self.thumperRate then
                    FireWeaponMask(user.handle, user.mask)
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
                if math.random(100) < self.fieldRate then
                    FireWeaponMask(user.handle, user.mask)
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
                if math.random(100) < self.mortarRate then
                    FireWeaponMask(user.handle, user.mask)
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
            -- NOTE: FireWeaponMask doesn't exist in BZ98R API - feature disabled
            -- local cycleTime = user.timer % self.minePeriod
            -- if cycleTime < self.mineDuration then
            --     if math.random(100) < self.mineRate then
            --         FireWeaponMask(user.handle, user.mask)
            --     end
            -- end
        end
    end
end

function aiCore.WeaponManager:UpdateDoubleWeapons(dt)
    -- NOTE: FireWeaponMask doesn't exist in BZ98R API - feature disabled
    -- for i = #self.doubleUsers, 1, -1 do
    --     local h = self.doubleUsers[i]
    --     if not IsValid(h) then
    --         table.remove(self.doubleUsers, i)
    --     else
    --         -- Fire both weapons with probability
    --         if math.random(100) < self.doubleRate then
    --             FireWeaponMask(h, 15) -- Fire all hardpoints (bits 0-3)
    --         end
    --     end
    -- end
end

----------------------------------------------------------------------------------
-- CLOAKING MANAGER (from aiSpecial)
-- Auto-cloak and coward mode for cloak-capable units
----------------------------------------------------------------------------------

aiCore.CloakingManager = {}
aiCore.CloakingManager.__index = aiCore.CloakingManager

-- Cloak-capable units (CRA, Omega, PDRA)
aiCore.CloakCapableODFs = {
    "cvfigh", "cvtnk", "cvhraz", "cvhtnk", "cvltnk", "cvrckt", "cvwalk",
    "mvraz", "mvtank", "mvhraz", "mvrdev", "mvltnk", "mvrckt", "mvwalk",
    "dvraz", "dvtank", "dvhraz", "dvrdev", "dvltnk", "dvrckt", "dvwalk"
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

    local odf = string.lower(GetOdf(h))
    for _, cloakOdf in ipairs(aiCore.CloakCapableODFs) do
        if odf == cloakOdf then
            table.insert(self.cloakers, h)
            if aiCore.Debug then print("Team " .. self.teamNum .. " added cloaker: " .. GetOdf(h)) end
            break
        end
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
            table.remove(self.howitzers, i)
        end
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
    -- Find enemy buildings as targets
    local enemyBuildings = {}
    for obj in AllBuildings() do
        local team = GetTeamNum(obj)
        if team ~= self.teamNum and team ~= 0 then
            table.insert(enemyBuildings, obj)
        end
    end

    if #enemyBuildings == 0 then return end

    -- Assign targets to squads
    for squadNum, squad in ipairs(self.squads) do
        if #squad > 0 then
            local targetIndex = ((squadNum - 1) % #enemyBuildings) + 1
            local target = enemyBuildings[targetIndex]

            for _, h in ipairs(squad) do
                if IsValid(h) and IsValid(target) then
                    Attack(h, target, 1) -- Priority attack
                end
            end
        end
    end
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
        else
            self:UpdateMinelayer(h)
        end
    end
end

function aiCore.MinelayerManager:UpdateMinelayer(h)
    local cmd = GetCurrentCommand(h)
    local ammo = GetCurAmmo(h)
    local maxAmmo = GetMaxAmmo(h)

    -- Need to reload?
    if ammo < (maxAmmo * 0.2) and not self.reloading[h] then
        self.reloading[h] = true
        self.laying[h] = false
        self.outbound[h] = false

        -- Find nearest supply depot
        local supply = nil
        local bestDist = 1000 -- Max search range
        local myPos = GetPosition(h)
        for obj in ObjectsInRange(1000, myPos) do
            if IsValid(obj) and GetTeamNum(obj) == GetTeamNum(h) then
                if GetClassLabel(obj) == utility.ClassSig.SUPPLY_DEPOT then
                    local dist = GetDistance(h, obj)
                    if dist < bestDist then
                        bestDist = dist
                        supply = obj
                    end
                end
            end
        end
        if IsValid(supply) then
            Goto(h, supply, 0)
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
        Goto(h, fieldPos, 0)
        if aiCore.Debug then print("Minelayer heading to field " .. fieldNum) end
    end

    -- Arrived at field?
    if self.outbound[h] then
        local fieldPos = self.minefields[self.currentField[h]]
        if GetDistance(h, fieldPos) < 80 then
            self.outbound[h] = false
            self.laying[h] = true
            if aiCore.Debug then print("Minelayer laying mines") end
        end
    end

    -- Laying mines - just patrol area
    if self.laying[h] and ammo > (maxAmmo * 0.2) then
        -- Let minelayer patrol and drop mines naturally
        if cmd ~= AiCommand.PATROL then
            local fieldPos = self.minefields[self.currentField[h]]
            Patrol(h, fieldPos, 1)
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
    self.pickupRange = 150
    self.deployRange = 120 -- Distance to enemy before deploying
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

    for i = #self.apcs, 1, -1 do
        local apc = self.apcs[i]
        if not IsValid(apc) then
            table.remove(self.apcs, i)
        else
            self:UpdateAPC(apc)
        end
    end
end

function aiCore.APCManager:UpdateAPC(apc)
    if IsBusy(apc) then return end

    -- Emergency Deployment (Low Health Protection)
    local health = GetCurHealth(apc) / GetMaxHealth(apc)
    if health < 0.3 and not IsDeployed(apc) then
        local attacker = GetWhoShotMe(apc)
        if IsValid(attacker) then
            Deploy(apc)
            if aiCore.Debug then print("APC Emergency Deployment (Critical Health)") end
            return
        end
    end

    -- If deployed, check if we should undeploy
    if IsDeployed(apc) then
        local enemy = GetNearestEnemy(apc)
        if not IsValid(enemy) or GetDistance(apc, enemy) > (self.deployRange * 2) then
            Deploy(apc) -- Toggle deploy
        end
        return
    end

    -- Not deployed - look for pilots to pick up
    local nearestPilot = nil
    local nearestDist = self.pickupRange

    -- Search for nearby pilots
    for obj in ObjectsInRange(self.pickupRange, GetPosition(apc)) do
        if IsValid(obj) and GetTeamNum(obj) == self.teamNum then
            local cls = aiCore.NilToString(GetClassLabel(obj))
            if string.find(cls, utility.ClassLabel.PERSON) and true --[[ TODO: Check InCargo ]] then
                local dist = GetDistance(apc, obj)
                if dist < nearestDist then
                    nearestPilot = obj
                    nearestDist = dist
                end
            end
        end
    end

    -- Pick up pilot
    if nearestPilot then
        Pickup(apc, nearestPilot)
        if aiCore.Debug then print("APC picking up pilot") end
        return
    end

    -- No pilots nearby - check if we should deploy
    -- Aggressive Targeting (Prioritize Critical Infrastructure)
    local target = (self.teamObj and self.teamObj.FindCriticalTarget) and self.teamObj:FindCriticalTarget() or nil
    if not target or not IsValid(target) then target = GetNearestEnemy(apc) end

    if target and IsValid(target) then
        local dist = GetDistance(apc, target)
        if dist < self.deployRange then
            Deploy(apc)
            if aiCore.Debug then print("APC deploying for assault on " .. GetOdf(target)) end
        else
            Attack(apc, target, 0)
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
        Goto(turret, targetPos, 0)
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

    Follow(unit, target, 0)
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
    self.defenses = {} -- {handle = {lastAmmo=f, lastHealth=f, stuckTimer=f, lastAttacker=h}}
    self.updatePeriod = 2.0
    self.updateTimer = 0.0
    return self
end

function aiCore.DefenseManager:AddObject(h)
    if not IsValid(h) then return end
    if self.defenses[h] then return end

    local odf = string.lower(utility.CleanString(GetOdf(h)))
    local cls = string.lower(utility.CleanString(GetClassLabel(h)))

    if cls == utility.ClassLabel.TURRET or cls == utility.ClassLabel.TURRET_TANK or string.match(odf, "gtow") then
        self.defenses[h] = {
            lastAmmo = GetCurAmmo(h),
            lastHealth = GetCurHealth(h),
            stuckTimer = 0.0
        }
        if aiCore.Debug then print("DefenseManager (Team " .. self.teamNum .. ") registered: " .. GetOdf(h)) end
    end
end

function aiCore.DefenseManager:Update()
    self.updateTimer = self.updateTimer + GetTimeStep()
    if self.updateTimer < self.updatePeriod then return end
    self.updateTimer = 0.0

    for h, data in pairs(self.defenses) do
        if not IsValid(h) then
            self.defenses[h] = nil
        else
            local curAmmo = GetCurAmmo(h)
            local curHealth = GetCurHealth(h)
            local target = GetCurrentWho(h)

            -- 1. Check if "Stuck" (Firing at something blocked but not consuming ammo)
            if IsValid(target) and IsDeployed(h) then
                if math.abs(curAmmo - data.lastAmmo) < 0.1 then -- Ammo not dropping significantly
                    data.stuckTimer = data.stuckTimer + self.updatePeriod
                else
                    data.stuckTimer = 0.0
                end
            else
                data.stuckTimer = 0.0
            end

            -- 2. Check for Incoming Fire
            local attacker = GetWhoShotMe(h)
            local shotTime = GetLastEnemyShot(h)
            local justShot = (GetTime() - shotTime) < 5.0 -- Shot in last 5 seconds

            -- 3. Switch Target Logic
            -- Switch if:
            --   - Stuck for 6+ seconds AND someone is shooting us
            --   - OR taking heavy damage (Health drop) and current target isn't dying
            local switching = false
            if IsValid(attacker) and IsAlive(attacker) and GetTeamNum(attacker) ~= self.teamNum then
                if (data.stuckTimer > 6.0 and justShot) or (curHealth < data.lastHealth - 100) then
                    if target ~= attacker then
                        if aiCore.Debug then
                            print("DefenseManager: " ..
                                GetOdf(h) .. " switching to attacker: " .. GetOdf(attacker))
                        end
                        Attack(h, attacker, 0) -- Force AI switch
                        data.stuckTimer = 0.0
                        switching = true
                    end
                end
            end

            data.lastAmmo = curAmmo
            data.lastHealth = curHealth
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

    -- Look for idle combat units
    for obj in AllObjects() do
        if assigned >= needed then break end

        if IsValid(obj) and GetTeamNum(obj) == self.teamNum and not IsBusy(obj) then
            local cls = aiCore.NilToString(GetClassLabel(obj))
            -- Tanks, scouts, or turrets make good guards
            if (string.find(cls, utility.ClassLabel.TANK) or string.find(cls, utility.ClassLabel.WINGMAN) or string.find(cls, utility.ClassLabel.TURRET))
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
        team.mortars, team.thumpers, team.fields, team.pilots, team.pool
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
    local count = 0
    local registered = 0

    for h in AllObjects() do
        count = count + 1
        local team = GetTeamNum(h)
        if aiCore.ActiveTeams[team] then
            if not aiCore.IsTracked(h, team) then
                aiCore.AddObject(h)
                registered = registered + 1
            end
        end
    end

    if aiCore.Debug then
        print("aiCore: Bootstrap complete. Processed " ..
            count .. " objects, registered " .. registered .. " new units.")
    end
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
    return {
        x = tPos.x + math.cos(rad) * dist,
        y = tPos.y,
        z = tPos.z + math.sin(rad) * dist
    }
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

function aiCore.AddObject(h)
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
        aiCore.GlobalDefenseManagers[teamNum]:AddObject(h)
        aiCore.GlobalDepotManagers[teamNum]:AddObject(h)
    end
end

function aiCore.DeleteObject(h)
    -- Cleanup if needed
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
