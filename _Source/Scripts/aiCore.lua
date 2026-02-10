-- aiCore.lua
-- Consolidated AI System for Battlezone 98 Redux
-- Combines functionality from pilotMode, autorepair, aiFacProd, aiRecProd, aiBuildOS, and aiSpecial
-- Supported Factions: NSDF, CCA, CRA, BDOG

local DiffUtils = require("DiffUtils")

----------------------------------------------------------------------------------
-- INTEGRATED UTILITY
----------------------------------------------------------------------------------
local utility = {}
utility.ClassLabel = {
    HOWITZER = "howitzer",
    APC = "apc",
    MINELAYER = "minelayer",
    TURRET = "turret", -- Stationary (Gun Towers)
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
    BRIDGE = 8, -- A structure which can contain the floor
    FLOOR = 9, -- The floor in a bridge
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
    [8] = "BRIDGE", -- A structure which can contain the floor
    [9] = "FLOOR", -- The floor in a bridge
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
    CLOAK = 27, -- {VERSION 2.1+}
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
    [27] = "CLOAK", -- {VERSION 2.1+}
    [28] = "DECLOAK", -- {VERSION 2.1+}
}
function utility.IsTable(object) return (type(object) == 'table') end
function utility.IsVector(object)
    if type(object) ~= "userdata" then return false end
    local mt = getmetatable(object)
    return mt and mt.__type == "VECTOR_3D"
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
                    if isBuilding and procSig == "constructionrig" then canBuild = true
                    elseif not isBuilding and (procSig == "recycler" or procSig == "factory") then canBuild = true end
                    
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
                        Build(foundProducer, job.odf, 1, pos)
                    else
                        Build(foundProducer, job.odf)
                    end
                    producer.Orders[foundProducer] = job
                    table.insert(removals, i)
                    -- Remove producer from available list for this tick
                    for idx, h in ipairs(producers) do
                        if h == foundProducer then table.remove(producers, idx); break end
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
    if exponent == 255 then return mantissa == 0 and (sign == 1 and -math.huge or math.huge) or 0/0 end
    return ((-1)^sign) * (1 + mantissa / 2^23) * 2^(exponent - 127)
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
        GetInt32 = function(s) local b1,b2,b3,b4 = string.byte(s.data,1,4); return b1+b2*256+b3*65536+b4*16777216 end, 
        GetBoolean = function(s) return string.byte(s.data,1) ~= 0 end, 
        GetVector2D = function(s, i) local off = (i or 0) * 8; return SetVector(parseFloatLE(s.data, off), 0, parseFloatLE(s.data, off + 4)) end 
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
    if res.version > 1022 then reader:ReadToken(); tok = reader:ReadToken(); res.msn_filename = tok:GetString() end
    reader:ReadToken() -- seq_count
    if res.version >= 1016 then reader:ReadToken() end -- missionSave
    if res.version ~= 1001 then tok = reader:ReadToken(); res.TerrainName = tok:GetString() end
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

aiCore = {}
aiCore.Debug = false

function aiCore.Save()
    return aiCore.ActiveTeams
end

function aiCore.NilToString(s)
    if s == nil then return "" end
    return tostring(s)
end

function aiCore.GetWeaponMask(h, search)
    if type(search) == "string" then search = {search} end
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
    aiCore.ActiveTeams = data
    
    -- Restore Metatables
    for _, team in pairs(aiCore.ActiveTeams) do
        setmetatable(team, aiCore.Team)
        if team.recyclerMgr then setmetatable(team.recyclerMgr, aiCore.FactoryManager) end
        if team.factoryMgr then setmetatable(team.factoryMgr, aiCore.FactoryManager) end
        if team.constructorMgr then setmetatable(team.constructorMgr, aiCore.ConstructorManager) end
        
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

aiCore.Factions = {NSDF = 1, CCA = 2, CRA = 3, BDOG = 4}
aiCore.FactionNames = {[1] = "NSDF", [2] = "CCA", [3] = "CRA", [4] = "BDOG"}

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
        if string.find(lowerTrn, "venus") then palette = "venus"
        elseif string.find(lowerTrn, "mars") then palette = "mars"
        elseif string.find(lowerTrn, "titan") then palette = "titan"
        else palette = "moon" end
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
    recycler = "avrecy", factory = "avmuf", armory = "avslf", constructor = "avcnst",
    sPower = "abspow", lPower = "ablpow", wPower = "abwpow",
    gunTower = "abtowe", gunTower2 = "abtowe", 
    silo = "absilo", supply = "absupp", hangar = "abhang",
    barracks = "abbarr", commTower = "abcomm", hq = "abhqcp",
    -- Units
    scavenger = "avscav", turret = "avturr", scout = "avfigh",
    tank = "avtank", lighttank = "avltnk", tug = "avhaul",
    howitzer = "avartl", minelayer = "avmine", rockettank = "avrckt",
    apc = "avapc", bomber = "avhraz", walker = "avwalk",
    unique = "avltmp", repair = "aprepa",
    ammo = "apammo", pilot = "aspilo", soldier = "assold",
    mine = "proxmine", wrecker = "apwrck", mortar = "gmortar", artillery = "ghartill"
}

aiCore.Units[aiCore.Factions.CCA] = {
    recycler = "svrecy", factory = "svmuf", armory = "svslf", constructor = "svcnst",
    sPower = "sbspow", lPower = "sblpow", wPower = "sbwpow",
    gunTower = "sbtowe", gunTower2 = "sbtowe",
    silo = "sbsilo", supply = "sbsupp", hangar = "sbhang",
    barracks = "sbbarr", commTower = "sbcomm", hq = "sbhqcp",
    scavenger = "svscav", turret = "svturr", scout = "svfigh",
    tank = "svtank", lighttank = "svltnk", tug = "svhaul",
    howitzer = "svartl", minelayer = "svmine", rockettank = "svrckt",
    apc = "svapc", bomber = "svhraz", walker = "svwalk",
    unique = "svsav", repair = "aprepa",
    ammo = "apammo", pilot = "sspilo", soldier = "sssold",
    mine = "proxmine", wrecker = "apwrck", mortar = "gmortar", artillery = "ghartill"
}

aiCore.Units[aiCore.Factions.CRA] = {
    recycler = "cvrecy", factory = "cvmuf", armory = "cvslf", constructor = "cvcnst",
    sPower = "cbspow", lPower = "cblpow", wPower = "cbwpow",
    gunTower = "cbtowe", gunTower2 = "cblasr",
    silo = "cbsilo", supply = "cbmbld", hangar = "cbhang",
    barracks = "cbbarr", commTower = "cbcomm", hq = "cbhqcp",
    scavenger = "cvscav", turret = "cvturr", scout = "cvfigh",
    tank = "cvtnk", lighttank = "cvltnk", tug = "cvhaul",
    howitzer = "cvartl", minelayer = "cvmine", rockettank = "cvrckt",
    apc = "cvapc", bomber = "cvhraz", walker = "cvwalk",
    unique = "cvhtnk", repair = "aprepa",
    ammo = "apammo", pilot = "cspilo", soldier = "cssold",
    mine = "proxmine", wrecker = "apwrck", mortar = "gmortar", artillery = "ghartill"
}

aiCore.Units[aiCore.Factions.BDOG] = {
    recycler = "bvrecy", factory = "bvmuf", armory = "bvslf", constructor = "bvcnst",
    sPower = "bbspow", lPower = "bblpow", wPower = "bbwpow",
    gunTower = "bbtowe", gunTower2 = "bbtowe",
    silo = "bbsilo", supply = "bbmbld", hangar = "bbhang",
    barracks = "bbbarr", commTower = "bbcomm", hq = "bbhqcp",
    scavenger = "bvscav", turret = "bvturr", scout = "bvfigh",
    tank = "bvtank", lighttank = "bvltnk", tug = "bvhaul",
    howitzer = "bvartl", minelayer = "bvmine", rockettank = "bvrckt",
    apc = "bvapc", bomber = "bvhraz", walker = "bvwalk",
    unique = "bvrdev", repair = "aprepa",
    ammo = "apammo", pilot = "bspilo", soldier = "bssold",
    mine = "proxmine", wrecker = "apwrck", mortar = "gmortar", artillery = "ghartill"
}

-- Tactical AIP Strategies (from aiSpecial)
-- These lists define unit composition priorities for different strategies
aiCore.Strategies = {
    Balanced = {
        Recycler = {"turret", "turret", "turret", "turret", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger"},
        Factory = {"howitzer", "unique", "unique", "rockettank", "rockettank", "bomber", "bomber", "bomber", "apc", "apc", "lighttank", "lighttank", "lighttank", "scout", "scout", "scout", "tank", "tank", "tank", "tank", "tank", "tank", "minelayer"}
    },
    APC_Heavy = {
        Recycler = {"scout", "scout", "turret", "turret", "turret", "turret", "turret", "turret", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger"},
        Factory = {"walker", "lighttank", "scout", "scout", "scout", "tank", "tank", "tank", "apc", "apc", "apc", "apc", "apc", "apc", "apc", "apc", "apc", "apc"}
    },
    Minelayer_Heavy = {
        Recycler = {"turret", "turret", "turret", "turret", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger"},
        Factory = {"minelayer", "minelayer", "minelayer", "minelayer", "minelayer", "tank", "tank", "tank", "lighttank", "lighttank", "lighttank", "scout", "scout"}
    },
    Tank_Heavy = {
        Recycler = {"scout", "turret", "turret", "turret", "turret", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger"},
        Factory = {"rockettank", "unique", "lighttank", "tank", "tank", "tank", "tank", "tank", "tank", "tank", "tank", "tank"}
    },
    Light_Force = {
        Recycler = {"scout", "scout", "scout", "scout", "scout", "turret", "turret", "turret", "turret", "scout", "scout", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger"},
        Factory = {"rockettank", "rockettank", "rockettank", "rockettank", "scout", "scout", "scout", "scout", "scout", "lighttank", "minelayer", "lighttank", "lighttank", "lighttank", "lighttank", "lighttank", "tank"}
    },
    Howitzer_Heavy = {
        Recycler = {"scout", "turret", "turret", "turret", "turret", "scout", "scout", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger"},
        Factory = {"rockettank", "rockettank", "rockettank", "lighttank", "lighttank", "lighttank", "scout", "scout", "scout", "tank", "minelayer", "tank", "tank", "howitzer", "howitzer", "howitzer", "howitzer", "howitzer", "howitzer"}
    },
    Bomber_Heavy = {
        Recycler = {"scout", "turret", "turret", "turret", "turret", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger"},
        Factory = {"unique", "apc", "lighttank", "scout", "scout", "scout", "tank", "tank", "tank", "tank", "bomber", "bomber", "bomber", "bomber", "bomber", "bomber", "bomber", "bomber"}
    },
    Rocket_Heavy = {
        Recycler = {"scout", "scout", "turret", "turret", "turret", "turret", "turret", "turret", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger"},
        Factory = {"lighttank", "lighttank", "lighttank", "lighttank", "lighttank", "scout", "scout", "bomber", "bomber", "bomber", "bomber", "rockettank", "rockettank", "rockettank", "rockettank", "rockettank", "rockettank", "rockettank", "rockettank"}
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
    self.fieldWeapons = {"gphantom", "gredfld", "gsitecam"}
    
    -- Mortar users
    self.mortarUsers = {}
    self.mortarActive = {}
    self.mortarPeriod = 15.0
    self.mortarDuration = 5.0
    self.mortarRate = 50
    self.mortarWeapons = {"gmortar", "gmdmgun", "gsplint"}
    
    -- Mine layers (weapon-based, not vehicle minelayers)
    self.mineUsers = {}
    self.mineActive = {}
   self.minePeriod = 25.0
    self.mineDuration = 0.5
    self.mineRate = 20
    self.mineWeapons = {"gproxmin", "gmitsmin", "gmcurmin", "gflare", "gnavdrop"}
    
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
        table.insert(self.thumperUsers, {handle = h, mask = thumperMask, timer = 0.0})
        if aiCore.Debug then print("Team " .. self.teamNum .. " added thumper user: " .. GetOdf(h)) end
    end
    
    -- Check for field weapons
    for _, weapon in ipairs(self.fieldWeapons) do
        local mask = aiCore.GetWeaponMask(h, weapon)
        if mask > 0 then
            table.insert(self.fieldUsers, {handle = h, mask = mask, timer = 0.0})
           if aiCore.Debug then print("Team " .. self.teamNum .. " added field user: " .. GetOdf(h)) end
            break
        end
    end
    
    -- Check for mortar weapons
    for _, weapon in ipairs(self.mortarWeapons) do
        local mask = aiCore.GetWeaponMask(h, weapon)
        if mask > 0 then
            table.insert(self.mortarUsers, {handle = h, mask = mask, timer = 0.0})
            if aiCore.Debug then print("Team " .. self.teamNum .. " added mortar user: " .. GetOdf(h)) end
            break
        end
    end
    
    -- Check for mine weapons
    for _, weapon in ipairs(self.mineWeapons) do
        local mask = aiCore.GetWeaponMask(h, weapon)
        if mask > 0 then
            table.insert(self.mineUsers, {handle = h, mask = mask, timer = 0.0})
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
    self.cowardMode = true  -- Cloak when damaged
    self.autoCloakEnabled = true  -- Auto-cloak when not in combat
    self.cloakHealthThreshold = 0.5  -- Cloak below 50% health
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
            local inCombat = (cmd == AiCommand.ATTACK or cmd == AiCommand.ATTACK_TARGET)
            local isCloaked = IsCloaked(h)
            
            -- Coward mode: cloak when damaged
            if self.cowardMode and health < self.cloakHealthThreshold and not isCloaked then
                SetCloaked(h, true)
                if aiCore.Debug then print("Team " .. self.teamNum .. " cloaking damaged unit: " .. GetOdf(h)) end
            end
            
            -- Auto-cloak when not in combat
            if not inCombat and not isCloaked and health > self.cloakHealthThreshold then
                SetCloaked(h, true)
            end
            
            -- Uncloak when in combat (let AI handle it)
            if inCombat and isCloaked then
                SetCloaked(h, false)
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
    self.squads = {}  -- Organized squads
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
    for i = 1, 15 do
        if i ~= self.teamNum and i ~= 0 then
            for obj in GetHandleByTeam(i) do
                if IsValid(obj) and IsBuilding(obj) then
                    table.insert(enemyBuildings, obj)
                end
            end
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
                    Attack(h, target, 1)  -- Priority attack
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
    self.minefields = {}  -- Configured minefield positions
    self.currentField = {}  -- Track which field each minelayer is working on
    self.outbound = {}  -- Traveling to field
    self.laying = {}  -- Laying mines
    self.reloading = {}  -- Returning to supply
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
    if #self.minefields > 0 then return end  -- Already configured
    
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
        local midDist = GetDistance(recPos, enemyBase) * 0.4
        
        -- Field 1: Forward defensive position
        self.minefields[1] = recPos + toEnemy * midDist
        
        -- Field 2 & 3: Flanking positions
        self.minefields[2] = recPos + toEnemy * midDist + perpendicular * 150
        self.minefields[3] = recPos + toEnemy * midDist - perpendicular * 150
    else
        -- No enemy found: defensive perimeter around base
        local angles = {0, 120, 240}  -- 3 fields, evenly spaced
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
    
    if #self.minefields == 0 then return end  -- Still no fields (no recycler yet)
    
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
        local supply = GetNearestVehicle(h, GetTeamNum(h), utility.ClassSig.SUPPLY_DEPOT)
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
    self.deployRange = 120  -- Distance to enemy before deploying
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
            Undeploy(apc)
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
            if string.find(cls, utility.ClassLabel.PERSON) and not IsInCargo(obj) then
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
    if not IsValid(target) then target = GetNearestEnemy(apc) end
    
    if IsValid(target) then
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
    self.deployPositions = {}  -- Calculated deployment positions
    self.deployRadius = 150  -- Distance from recycler
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
    local angles = {0, 60, 120, 180, 240, 300}  -- 6 positions
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
    if GetDistance(GetPosition(turret), targetPos) > 20 then
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
        if aiCore.Debug then print("DefenseManager (Team "..self.teamNum..") registered: " .. GetOdf(h)) end
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
                        if aiCore.Debug then print("DefenseManager: " .. GetOdf(h) .. " switching to attacker: " .. GetOdf(attacker)) end
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
        if aiCore.Debug then print("DepotManager (Team "..self.teamNum..") registered: " .. GetOdf(h) .. " (Range: "..range..", Amount: "..amount..")") end
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
    ["misn02b.aip"] = "Tank_Heavy",      -- Missing from original
    ["misn03.aip"] = "Balanced",          -- Missing from original
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
    ["misn10b.aip"] = "Bomber_Heavy",     -- Missing from original
    ["misn13.aip"] = "Balanced",
    ["misn13a.aip"] = "Rocket_Heavy",
    ["misn13b.aip"] = "Howitzer_Heavy",   -- Missing from original
    ["misn13c.aip"] = "Howitzer_Heavy",
    ["misn14.aip"] = "Tank_Heavy",
    ["misn15.aip"] = "Balanced",          -- Missing from original
    ["misn16.aip"] = "Balanced",
    ["misn17.aip"] = "Howitzer_Heavy",
    
    -- Black Dog Campaign
    ["bdmisn07.aip"] = "Balanced",        -- Fixed filename (was bdmisn7.aip)
    ["bdmisn14.aip"] = "Tank_Heavy",
    
    -- CCA Campaign
    ["chmisn06.aip"] = "Balanced",
    
    -- Mission Select (NSDF)
    ["misns4.aip"] = "Balanced",
    ["misns5.aip"] = "Tank_Heavy",
    ["misns6.aip"] = "Howitzer_Heavy",
    ["misns7.aip"] = "Balanced",          -- Missing from original
    ["misns7a.aip"] = "Tank_Heavy",       -- Missing from original
    ["misns7b.aip"] = "APC_Heavy",        -- Missing from original
    ["misns7c.aip"] = "Rocket_Heavy",     -- Missing from original
    ["misns8.aip"] = "Balanced",
    ["misns8a.aip"] = "APC_Heavy",
    ["misns8b.aip"] = "Rocket_Heavy",
    ["misns8c.aip"] = "Tank_Heavy",
    ["misns8d.aip"] = "Bomber_Heavy",
    ["misns8e.aip"] = "Light_Force",      -- Missing from original
    ["misns8f.aip"] = "Howitzer_Heavy",
    ["misns8g.aip"] = "Light_Force",
    
    -- Special/Training
    ["bowl.aip"] = "Balanced",            -- Missing from original
    ["demo01.aip"] = "Balanced",          -- Missing from original
    ["inst01.aip"] = "Balanced",          -- Missing from original
    ["tran03.aip"] = "Balanced",          -- Missing from original
}

function aiCore.SetAIP(aipFile, teamNum)
    teamNum = teamNum or 2  -- Default to team 2 (enemy)
    
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

function aiCore.IsAreaFlat(centerPos, radius, checkPoints, flatThreshold, flatPercentage)
    radius = radius or 10.0
    checkPoints = checkPoints or 8
    flatThreshold = flatThreshold or 0.966 -- cos(15 degrees)
    flatPercentage = flatPercentage or 0.75
    
    local centerHeight, centerNormal = GetTerrainHeightAndNormal(centerPos)
    if centerNormal.y < flatThreshold then return false, 0.0 end
    
    local flatPoints = 1
    local totalPoints = 1 + checkPoints
    
    for i = 0, checkPoints - 1 do
        local angle = (i / checkPoints) * 2 * math.pi
        local x = centerPos.x + radius * math.cos(angle)
        local z = centerPos.z + radius * math.sin(angle)
        local testPos = SetVector(x, centerPos.y, z)
        local _, normal = GetTerrainHeightAndNormal(testPos)
        if normal.y >= flatThreshold then flatPoints = flatPoints + 1 end
    end
    
    local actual = flatPoints / totalPoints
    return actual >= flatPercentage, actual
end

function aiCore.IsTracked(h, teamNum)
    local team = aiCore.ActiveTeams[teamNum]
    if not team then return false end
    
    -- Check Manager Handle
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
    
    if aiCore.Debug then print("aiCore: Bootstrap complete. Processed " .. count .. " objects, registered " .. registered .. " new units.") end
end

function aiCore.GetNearestInTable(h, table)
    if next(table) ~= nil then
        local nearest = nil
        local minDist = 999999
        for i=1, #table do
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
    if not IsValid(target) then return nil end
    local tPos = GetPosition(target)
    local rad = math.rad(angleDeg)
    return {
        x = tPos.x + math.cos(rad) * dist,
        y = tPos.y, -- Assume flat for now, or use GetTerrainHeight
        z = tPos.z + math.sin(rad) * dist
    }
end

-- Find the most valuable enemy building for tactical strikes
function aiCore.Team:FindCriticalTarget()
    local bestTarget = nil
    local bestPrio = 99
    
    -- Search for non-allied buildings
    for i = 1, 15 do
        if i ~= self.teamNum and i ~= 0 and not IsAlly(self.teamNum, i) then
            -- 1. Recycler (Ultimate Priority)
            local r = GetRecyclerHandle(i)
            if IsValid(r) then return r end
            
            -- 2. Factory (High Priority)
            local f = GetFactoryHandle(i)
            if IsValid(f) then return f end
            
            -- 3. Scan for Power and others
            for h in GetHandleByTeam(i) do
                if IsValid(h) and IsBuilding(h) then
                    local cls = string.lower(aiCore.NilToString(GetClassLabel(h)))
                    local prio = 99
                    
                    if string.find(cls, "powerplant") or string.find(cls, "generator") then
                        prio = 3
                    elseif string.find(cls, "armory") or string.find(cls, "constructionrig") then
                        prio = 4
                    elseif string.find(cls, "training") or string.find(cls, "barracks") then
                        prio = 5
                    end
                    
                    if prio < bestPrio then
                        bestPrio = prio
                        bestTarget = h
                        if prio == 3 then break end -- Power is good enough to stop looking in this team
                    end
                end
            end
        end
    end
    
    return bestTarget
end


-- Upgrade Turret Logic (Ported from aiSpecial)
function aiCore.UpgradeTurret(h) 
    if not IsValid(h) then return false end
    
    local success = false
    local odf = GetOdf(h)
    
    if odf == "avturr" then
        for i = 0,3 do GiveWeapon(h,"gXinigun",i) end; success = true
    elseif odf == "svturr" then
        for i = 0,2 do GiveWeapon(h,"gXinisov",i) end; success = true
    elseif odf == "cvturr" then
        for i = 0,3 do GiveWeapon(h,"gXinisov",i) end; success = true
    elseif odf == "bvturr" then
        for i = 0,3 do GiveWeapon(h,"gXinigun",i) end; success = true
    elseif odf == "bvtump" then
        for i = 0,1 do GiveWeapon(h,"gXtstab",i) end; success = true
    elseif odf == "mvturr" then
        for i = 0,1 do GiveWeapon(h,"gshadow",i) end; success = true
    elseif odf == "dvturr" then
        for i = 0,3 do GiveWeapon(h,"gXinisov",i) end; success = true
    elseif odf == "rvturr" then
        for i = 0,2 do GiveWeapon(h,"ghailgn",i) end; success = true
    elseif odf == "fvturr" then
        for i = 0,3 do GiveWeapon(h,"gXongun",i) end; success = true
    elseif odf == "sbtowe" then
        for i = 0,1 do GiveWeapon(h,"gX2nisov",i) end; success = true
    elseif odf == "cbtowe" then
        GiveWeapon(h,"gXtstabt",0); success = true 
    end
    
    if success and aiCore.Debug then
        print("Turret "..odf.." upgraded.")
    end
    return success
end

-- Replace Unit Logic (Ported from aiSpecial)
function aiCore.ReplaceUnit(h, newUnitOdf, chargeExpense, teamObj)
    if not IsValid(h) then return nil end
    
    local teamNum = GetTeamNum(h)
    local pos = GetPosition(h)
    local rot = GetTransform(h) -- Actually checking if GetTransform returns matrix or we need SetTransform(h, matrix)
    -- BZ Lua API GetTransform returns a matrix/userdata usually compatible with SetTransform.
    
    local oldOdf = GetOdf(h)
    local oldScrapCost = GetODFInt(OpenODF(oldOdf),"GameObjectClass","scrapCost")
    local newScrapCost = GetODFInt(OpenODF(newUnitOdf),"GameObjectClass","scrapCost")
    
    RemoveObject(h)
    
    local replacement = BuildObject(newUnitOdf, teamNum, pos)
    SetTransform(replacement, rot)
    
    -- Charge expense?
    if chargeExpense and teamObj then
        local diff = newScrapCost - oldScrapCost
        if diff > 0 then
            AddScrap(teamNum, -diff)
            if aiCore.Debug then print("Team "..teamNum.." paid "..diff.." for replacement.") end
        end
    end
    
    return replacement
end



----------------------------------------------------------------------------------
-- CLASSES
----------------------------------------------------------------------------------

-- Constants for magic numbers
aiCore.Constants = {
    CONSTRUCTOR_IDLE_DISTANCE = 100,  -- Distance to recycler before returning when idle
    CONSTRUCTOR_TRAVEL_THRESHOLD = 60, -- Distance before traveling to build site
    BUILDING_DETECTION_RANGE = 40,     -- Range to check for existing buildings
    BUILDING_SPACING = 50,             -- Spacing between buildings
    STRATEGY_ROTATION_INTERVAL = 600,  -- Seconds between strategy changes
    PILOT_RESOURCE_INTERVAL = 20,      -- Seconds between pilot checks
    RESCUE_CHECK_INTERVAL = 10         -- Seconds between rescue checks
}

-- Generic Build Queue Item
aiCore.BuildItem = {
    odf = "",
    priority = 0,
    path = nil -- for constructor builds
}
aiCore.BuildItem.__index = aiCore.BuildItem

-- Factory Manager (Handles Factory & Recycler Unit Production)
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
        local cmd = GetCurrentCommand(self.handle)
        -- Only issue Deploy command if not already deploying or undeploying
        if cmd ~= AiCommand.DEPLOY and cmd ~= AiCommand.UNDEPLOY then
             Deploy(self.handle)
        end
        return -- Wait for deployment
    end

    -- Building is now handled by integrated producer via jobs queued in CheckBuildList
end

function aiCore.FactoryManager:addUnit(odf, priority)
    table.insert(self.queue, {odf = odf, priority = priority})
    table.sort(self.queue, function(a,b) return a.priority < b.priority end)
end

-- Constructor Manager
aiCore.ConstructorManager = {
    handle = nil,
    team = 0,
    queue = {},
    pulseTimer = 0.0,
    pulsePeriod = 8.0,
    sentToRecycler = false
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
        self.sentToRecycler = false
        return
    end

    -- MODIFIED: Do not manage constructor if disabled
    if self.teamObj and self.teamObj.Config and not self.teamObj.Config.manageFactories then return end

    if #self.queue == 0 then
        -- Robust idling: Return to recycler if idle
        local recycler = GetRecyclerHandle(self.team)
        if IsValid(recycler) and not self.sentToRecycler then
            if GetDistance(self.handle, recycler) > aiCore.Constants.CONSTRUCTOR_IDLE_DISTANCE then
                Goto(self.handle, recycler, 0)
                self.sentToRecycler = true
            end
        end
        return
    end

    self.sentToRecycler = false
    -- Building is now handled by integrated producer via jobs queued in CheckConstruction
end



-- Squad Class (Formations & Flanking)
aiCore.Squad = {
    leader = nil,
    members = {},
    state = "idling", -- idling, moving_to_flank, attacking
    targetPos = nil,
    formation = "V",
    maxSize = 3
}
aiCore.Squad.__index = aiCore.Squad

function aiCore.Squad:new(leader)
    local s = setmetatable({}, self)
    s.leader = leader
    s.members = {}
    return s
end

function aiCore.Squad:AddMember(h)
    table.insert(self.members, h)
    -- Order follow
    if IsValid(self.leader) then
        Follow(h, self.leader, 0)
    end
end

function aiCore.Squad:Update()
    if not IsValid(self.leader) then
        -- Promote new leader if possible
        if #self.members > 0 then
            self.leader = table.remove(self.members, 1)
            -- Re-order followers
            for _, m in ipairs(self.members) do
                if IsValid(m) then Follow(m, self.leader, 0) end
            end
        else
            return false -- Dead squad
        end
    end
    
    -- State Machine
    if self.state == "moving_to_flank" then
        if self.targetPos then
            if GetDistance(self.leader, self.targetPos) < 60 then
                self.state = "attacking"
                -- Find nearest enemy to flank pos
                local enemy = GetNearestEnemy(self.leader)
                if IsValid(enemy) then
                    Attack(self.leader, enemy)
                    for _, m in ipairs(self.members) do Attack(m, enemy) end
                end
            else
                 -- Ensure moving
                 if not string.match(aiCore.NilToString(AiCommand[GetCurrentCommand(self.leader)]), "GO") then
                    Goto(self.leader, self.targetPos)
                 end
            end
        end
    elseif self.state == "attacking" then
        -- If idle, attack nearest
        if not IsBusy(self.leader) then
             local enemy = GetNearestEnemy(self.leader)
             if IsValid(enemy) then
                Attack(self.leader, enemy)
                for _, m in ipairs(self.members) do Attack(m, enemy) end
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
    self.wingmen = {}  -- Track wingmen with their state
    
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
            previousTarget = nil
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
        healthThreshold = 0.05  -- Only critical repairs in combat
        ammoThreshold = 0.025
    else
        healthThreshold = 0.75  -- More relaxed when safe
        ammoThreshold = 0.75
    end
    
    -- Calculate search radius based on follow state
    local searchRadius = self:GetSearchRadius(unit, currentCommand)
    
    -- Check if unit can act independently
    if self:CanSeekSupplies(unit, currentCommand, health, ammo) then
        local commandIssued = false
        
        -- Priority 1: Health (repair depot)
        if health <= healthThreshold then
            local depot = self:FindNearestRepairDepot(unit, searchRadius)
            if depot and GetTime() >= entry.lastCommandTime + self.commandDelay then
                self:SavePreviousCommand(entry)
                SetCommand(unit, AiCommand.GET_REPAIR, 0, depot)
                entry.lastCommandTime = GetTime()
                commandIssued = true
            end
        end
        
        -- Priority 2: Ammo (supply depot)
        if not commandIssued and ammo <= ammoThreshold then
            local depot = self:FindNearestSupplyDepot(unit, searchRadius)
            if depot and GetTime() >= entry.lastCommandTime + self.commandDelay then
                self:SavePreviousCommand(entry)
                SetCommand(unit, AiCommand.GET_RELOAD, 0, depot)
                entry.lastCommandTime = GetTime()
                commandIssued = true
            end
        end
        
        -- Fallback: Repair pods
        if not commandIssued and health <= healthThreshold then
            local pod = self:FindNearestRepairPod(unit, searchRadius)
            if pod and GetTime() >= entry.lastCommandTime + self.commandDelay then
                if math.random() <= self.podChance then
                    self:SavePreviousCommand(entry)
                    Goto(unit, pod, 0)
                    entry.lastCommandTime = GetTime()
                    commandIssued = true
                end
            end
        end
        
        -- Fallback: Ammo pods
        if not commandIssued and ammo <= ammoThreshold then
            local pod = self:FindNearestAmmoPod(unit, searchRadius)
            if pod and GetTime() >= entry.lastCommandTime + self.commandDelay then
                if math.random() <= self.podChance then
                    self:SavePreviousCommand(entry)
                    Goto(unit, pod, 0)
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

-- Helper: Calculate search radius based on follow state
function aiCore.WingmanManager:GetSearchRadius(unit, currentCommand)
    local searchRadius = self.podSearchRadius
    
    if currentCommand == AiCommand.FOLLOW or currentCommand == AiCommand.DEFEND or currentCommand == AiCommand.FORMATION then
        local target = GetCurrentWho(unit)
        if IsValid(target) then
            local vel = GetVelocity(target) or {x=0, y=0, z=0}
            local velMag = math.sqrt(vel.x^2 + vel.y^2 + vel.y^2)
            
            if velMag < self.followVelocity then
                searchRadius = math.min(self.podSearchRadius, self.followThreshold)
            else
                searchRadius = math.min(self.podSearchRadius, self.followThreshold * 0.8)
            end
        end
    end
    
    return searchRadius
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
        and IsValid(entry.previousTarget)
        and entry.previousCommand ~= nil
end

-- Helper: Save command
function aiCore.WingmanManager:SavePreviousCommand(entry)
    entry.previousCommand = GetCurrentCommand(entry.unit)
    entry.previousTarget = GetCurrentWho(entry.unit)
end

-- Helper: Restore command
function aiCore.WingmanManager:RestorePreviousCommand(entry)
    if entry.previousCommand then
        SetCommand(entry.unit, entry.previousCommand, 0, entry.previousTarget)
        entry.previousCommand = nil
        entry.previousTarget = nil
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

aiCore.Team = {
    teamNum = 0,
    faction = 0,
    recyclerMgr = nil,
    factoryMgr = nil,
    constructorMgr = nil,
    
    -- Production Lists (Desired State)
    recyclerBuildList = {}, -- {priority = {odf="", handle=nil}}
    factoryBuildList = {},
    buildingList = {},      -- {priority = {odf="", handle=nil, path=""}}
    
    -- Tactics
    strategy = "Balanced",
    strategyLocked = false,
    
    -- Tactical Groups (from aiSpecial)
    howitzers = {},     -- list of handles
    howitzerGuards = {},
    apcs = {},
    minelayers = {},
    pilots = {},        -- technicians/snipers
    cloakers = {},      -- CRA cloaked units
    thumpers = {},      -- Advanced Weapons
    mortars = {},
    fields = {},
    turrets = {},       -- Tracking for upgrades
    
    -- Tactical State
    howitzerState = {}, -- {attacking=bool, outbound=bool, target=handle}
    wreckerTimer = 0,
    upgradeTimer = 0,
    strategyTimer = 0,  -- For rotation
    weaponTimer = 0,    -- For mask cycling
    
    -- pilotMode State
    roleTimer = 0,
    rescueTimer = 0,
    tugTimer = 0,
    stickTimer = 0,
    
    cargoJobs = {},
    tugHandles = {},
    activeTugJobs = {},
    assistedUnits = {}, -- For StickToPlayer
    basePositions = {}, -- For AutoBuild
    
    -- Targets
    enemyTargets = {},  -- prioritized list of enemy buildings
    
    -- Stealth Management (Legacy Misn12)
    stealthState = {
        discovered = false,
        warnings = 0,
        playerInVehicle = true,
        lastCheckPos = nil
    }
}
aiCore.Team.__index = aiCore.Team

function aiCore.Team:new(teamNum, faction)
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
        resourceBoost = false,
        
        -- Timers
        upgradeInterval = 240,
        wreckerInterval = 600,
        techInterval = 60,
        techMax = 4,
        
        -- Toggles
        passiveRegen = false,
        autoManage = false,
        autoRescue = false,
        autoTugs = false,
        stickToPlayer = false,
        dynamicMinefields = false,
        
        -- Minefield positions
        minefields = {},  -- List of positions for minelayers
        
        -- Automation Sub-config
        followPercentage = 30,
        patrolPercentage = 30,
        guardPercentage = 40,
        scavengerCount = 4,
        tugCount = 2,
        buildingSpacing = 80,
        rescueDelay = 2.0,
        pilotTopoff = 4,
        
        -- Reinforcements
        orbitalReinforce = true,
        
        -- Legacy Features
        regenRate = 20.0,
        reclaimEngineers = false,
        
        -- Factory Management
        manageFactories = true -- Default to true for AI teams
    }

    -- Tactical Lists
    t.scavengers = {}
    t.howitzers = {}
    t.apcs = {}
    t.minelayers = {}
    t.cloakers = {}
    t.mortars = {}
    t.thumpers = {}
    t.fields = {}
    t.pilots = {}
    t.turrets = {}
    t.doubleUsers = {}
    t.soldiers = {}
    t.tugHandles = {}
    if not faction then
        -- Simple detection based on recycler ODF
        local rec = GetRecyclerHandle(teamNum)
        if IsValid(rec) then
            local odf = GetOdf(rec)
            local char = string.sub(odf, 1, 1)
            if char == "a" then faction = 1
            elseif char == "s" then faction = 2
            elseif char == "c" then faction = 3
            elseif char == "b" then faction = 4
            end
        end
    end
    t.faction = faction or 1 -- Default to NSDF if unknown
    
    t.recyclerMgr = aiCore.FactoryManager:new(teamNum, true)
    t.recyclerMgr.teamObj = t -- Bind reference
    t.factoryMgr = aiCore.FactoryManager:new(teamNum, false)
    t.factoryMgr.teamObj = t -- Bind reference
    t.constructorMgr = aiCore.ConstructorManager:new(teamNum)
    t.constructorMgr.teamObj = t -- Bind reference
    
    -- Initialize Integrated Producer Queue
    if not producer.Queue[teamNum] then producer.Queue[teamNum] = {} end
    
    t.recyclerBuildList = {}
    t.factoryBuildList = {}
    t.buildingList = {}
    
    t.combatUnits = {} 
    
    t.pool = {} -- Units waiting for assignment
    t.squads = {} -- Active squads
    
    t.resourceBoostTimer = GetTime() + 10.0 -- Randomized boost starts soon
    t.lastArmoryTarget = nil -- Track for Day Wrecker fix
    t.defenseMgr = aiCore.DefenseManager.new(teamNum)
    t.depotMgr = aiCore.DepotManager.new(teamNum)
    
    return t
end

function aiCore.Team:SetStrategy(stratName)
    if self.strategyLocked then return end
    
    local strat = aiCore.Strategies[stratName]
    if not strat then strat = aiCore.Strategies.Balanced end
    self.strategy = stratName
    
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
            self:AddUnitToBuildList(self.recyclerBuildList, odf, i) 
        end
    end
    
    -- Factory List
    for i = #strat.Factory, 1, -1 do
        local unitType = strat.Factory[i]
        local odf = aiCore.Units[self.faction][unitType]
        if odf then 
            self:AddUnitToBuildList(self.factoryBuildList, odf, i) 
        end
    end
    
    if aiCore.Debug then print("Team " .. self.teamNum .. " strategy set to " .. stratName) end
end

function aiCore.Team:AddUnitToBuildList(list, odf, priority)
    list[priority] = {odf = odf, priority = priority, handle = nil}
end

function aiCore.Team:AddBuilding(odf, path, priority)
    self.buildingList[priority] = {odf = odf, priority = priority, path = path, handle = nil}
end

-- Enhanced terrain validation (from pilotMode.lua)
-- Checks multiple points around a position to ensure area is flat enough
function aiCore.IsAreaFlat(centerPos, radius, checkPoints, flatThreshold, flatPercentage)
    -- Defaults for building placement
    radius = radius or 10
    checkPoints = checkPoints or 8
    flatThreshold = flatThreshold or 0.966  -- cos(15°) - strict for buildings
    flatPercentage = flatPercentage or 0.75  -- 75% of points must be flat
    
    -- Check center point first
    local centerHeight, centerNormal = GetTerrainHeightAndNormal(centerPos)
    if centerNormal.y < flatThreshold then
        return false, 0.0
    end
    
    -- Check points in a circle around center
    local flatPoints = 1  -- Center is flat
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
    if not IsValid(self.recyclerMgr.handle) then return nil end
    
    local recPos = GetPosition(self.recyclerMgr.handle)
    local bestPos = nil
    local bestScrapDensity = 0
    local scrapScanRadius = 100  -- Scan radius for scrap density
    
    -- Sample positions in a ring around recycler (more samples for better coverage)
    for angle = 0, 360, 30 do  -- Every 30 degrees
        local dist = minDist + math.random() * (maxDist - minDist)
        local rad = math.rad(angle)
        local testPos = SetVector(
            recPos.x + math.cos(rad) * dist,
            recPos.y,
            recPos.z + math.sin(rad) * dist
        )
        
        -- Check terrain flatness with relaxed parameters for silo
        local isFlat, flatness = aiCore.IsAreaFlat(testPos, 20, 6, 0.940, 0.70)
        if isFlat then
            -- Calculate scrap density score
            local scrapCount = 0
            local totalScrapValue = 0
            
            for obj in ObjectsInRange(scrapScanRadius, testPos) do
                if GetClassLabel(obj) == "scrap" then
                    scrapCount = scrapCount + 1
                    -- Weight closer scrap higher
                    local dist = GetDistance(obj, testPos)
                    local weight = 1.0 - (dist / scrapScanRadius)
                    totalScrapValue = totalScrapValue + weight
                end
            end
            
            -- Scrap density = weighted scrap value
            local scrapDensity = totalScrapValue
            
            if scrapDensity > bestScrapDensity then
                bestScrapDensity = scrapDensity
                bestPos = testPos
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
    minSpacing = minSpacing or 70  -- Default from pilotMode
    
    -- Check against existing buildings in buildingList
    for _, building in pairs(self.buildingList) do
        if building.path and GetDistance(position, building.path) < minSpacing then
            return false, "Too close to planned building"
        end
        if IsValid(building.handle) and GetDistance(position, building.handle) < minSpacing then
            return false, "Too close to existing building"
        end
    end
    
    -- Check against all buildings in range
    for obj in ObjectsInRange(minSpacing, position) do
        if GetTeamNum(obj) == self.teamNum and IsBuilding(obj) then
            return false, "Too close to building: " .. GetOdf(obj)
        end
    end
    
    return true, "OK"
end


-- Plan defensive perimeter with power generators and gun towers
function aiCore.Team:PlanDefensivePerimeter(powerCount, towerCount)
    if not IsValid(self.recyclerMgr.handle) then return end
    
    local recPos = GetPosition(self.recyclerMgr.handle)
    local powerOdf = aiCore.Units[self.faction][aiCore.DetectWorldPower()]
    local towerOdf = aiCore.Units[self.faction].gunTower
    
    if not powerOdf or not towerOdf then
        if aiCore.Debug then print("Team " .. self.teamNum .. " missing power or tower ODF") end
        return
    end
    
    -- Place power generators in a circle
    local powerRadius = 120
    local angleStep = 360 / powerCount
    for i = 0, powerCount - 1 do
        local angle = i * angleStep + math.random(-15, 15)
        local rad = math.rad(angle)
        local pos = SetVector(
            recPos.x + math.cos(rad) * powerRadius,
            recPos.y,
            recPos.z + math.sin(rad) * powerRadius
        )
        
        -- Validate position
        local isFlat, flatness = aiCore.IsAreaFlat(pos, 20, 6, 0.95, 0.80)
        if isFlat then
            self:AddBuilding(powerOdf, pos, i + 1)
        end
    end
    
    -- Place gun towers further out
    local towerRadius = 180
    local towersPerPower = math.ceil(towerCount / powerCount)
    local priority = powerCount + 1
    
    for i = 0, powerCount - 1 do
        local baseAngle = i * angleStep
        for j = 1, towersPerPower do
            if priority - powerCount > towerCount then break end
            
            local offset = (j - (towersPerPower / 2)) * 25
            local angle = baseAngle + offset + math.random(-10, 10)
            local rad = math.rad(angle)
            local pos = SetVector(
                recPos.x + math.cos(rad) * towerRadius,
                recPos.y,
                recPos.z + math.sin(rad) * towerRadius
            )
            
            -- Validate position
            local isFlat, flatness = aiCore.IsAreaFlat(pos, 15, 6, 0.95, 0.75)
            if isFlat then
                self:AddBuilding(towerOdf, pos, priority)
                priority = priority + 1
            end
        end
    end
    
    if aiCore.Debug then 
        print("Team " .. self.teamNum .. " planned defensive perimeter: " .. powerCount .. " powers, " .. towerCount .. " towers") 
    end
end


function aiCore.Team:Update()
    -- Lazy Initialization for Retrofitting (Fixes crashes on existing saves/teams)
    if not self.fields then self.fields = {} end
    if not self.doubleUsers then self.doubleUsers = {} end
    if not self.soldiers then self.soldiers = {} end
    if not self.cloakers then self.cloakers = {} end
    if not self.howitzers then self.howitzers = {} end
    if not self.apcs then self.apcs = {} end
    if not self.minelayers then self.minelayers = {} end
    if not self.thumpers then self.thumpers = {} end
    if not self.mortars then self.mortars = {} end
    if not self.turrets then self.turrets = {} end
    if not self.scavengers then self.scavengers = {} end
    if not self.pilots then self.pilots = {} end
    if not self.tugHandles then self.tugHandles = {} end
    if not self.pool then self.pool = {} end
    if not self.guards then self.guards = {} end
    
    -- Initialize Phase 1 Managers
    if not self.weaponMgr then self.weaponMgr = aiCore.WeaponManager.new(self.teamNum) end
    if not self.cloakMgr then self.cloakMgr = aiCore.CloakingManager.new(self.teamNum) end
    if not self.howitzerMgr then self.howitzerMgr = aiCore.HowitzerManager.new(self.teamNum) end
    if not self.minelayerMgr then self.minelayerMgr = aiCore.MinelayerManager.new(self.teamNum) end
    
    -- Initialize Phase 2 Managers
    if not self.apcMgr then self.apcMgr = aiCore.APCManager.new(self.teamNum) end
    if not self.turretMgr then self.turretMgr = aiCore.TurretManager.new(self.teamNum) end
    if not self.guardMgr then self.guardMgr = aiCore.GuardManager.new(self.teamNum) end
    if not self.wingmanMgr then self.wingmanMgr = aiCore.WingmanManager.new(self.teamNum) end
    
    -- Ensure Config has new keys if missing
    if self.Config.fieldChance == nil then
        self.Config.fieldChance = 10
        self.Config.doubleWeaponChance = 20
        self.Config.soldierRange = 50
        self.Config.sniperSteal = true
        self.Config.pilotZeal = 0.4
        self.Config.sniperTraining = 75
        self.Config.sniperStealth = 0.5
        self.Config.autoRepairWingmen = false  -- Disabled by default, user can enable
        self.Config.resourceBoost = false
        
        -- New Features
        self.Config.enableWreckers = false
        self.Config.paratrooperChance = 0
        self.Config.paratrooperInterval = 600
    end

    -- Manager Updates
    self.recyclerMgr:update()
    self.factoryMgr:update()
    self.constructorMgr:update()
    
    -- Replenish Queues from Build Lists
    self:CheckBuildList(self.recyclerBuildList, self.recyclerMgr)
    self:CheckBuildList(self.factoryBuildList, self.factoryMgr)
    self:CheckConstruction()
    
    -- MODIFIED: Process Integrated Production Queues
    producer.ProcessQueues(self)
    
    -- Strategy rotation
    self:UpdateStrategyRotation()
    
    -- Update Phase 1 Managers
    if self.weaponMgr then self.weaponMgr:Update() end
    if self.cloakMgr then self.cloakMgr:Update() end
    if self.howitzerMgr then self.howitzerMgr:Update() end
    if self.minelayerMgr then self.minelayerMgr:Update() end
    if self.apcMgr then self.apcMgr:Update() end
    if self.turretMgr then self.turretMgr:Update() end
    if self.wingmanMgr then self.wingmanMgr:Update() end
    if self.guardMgr then self.guardMgr:Update() end
    if self.defenseMgr then self.defenseMgr:Update() end
    if self.depotMgr then self.depotMgr:Update() end
    
    -- Update Wingman Manager (toggleable)
    if self.Config.autoRepairWingmen and self.wingmanMgr then
        self.wingmanMgr:Update()
    end
    
    -- pilotMode Automations
    if self.Config.autoManage then self:UpdateUnitRoles() end
    if self.Config.autoRescue then self:UpdateRescue() end
    if self.Config.autoTugs then self:UpdateTugs() end
    if self.Config.stickToPlayer then self:UpdateStickToPlayer() end
    if self.Config.autoBuild then self:UpdateAutoBase() end
    
    -- Legacy Proximity/Maintenance
    if self.Config.dynamicMinefields then self:UpdateDynamicMinefields() end
    if self.Config.passiveRegen then self:UpdateRegen() end
    
    self:UpdateBaseMaintenance()
    self:UpdatePilotResources()
    self:UpdateResourceBoosting()
    self:UpdateWrecker()
    self:UpdateParatroopers()
    self:UpdateSoldiers()
    
    -- Scavenger Assist (Player QOL)
    if self.Config.scavengerAssist then self:UpdateScavengerAssist() end
end

function aiCore.Team:UpdateStickToPlayer()
    -- Placeholder for future stick-to-player behavior
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
            print("Team "..self.teamNum.." resource boost: +"..scrapBoost.." scrap, +"..pilotBoost.." pilots (Next in "..math.floor(interval).."s)") 
        end
    end
end

function aiCore.Team:UpdateScavengerAssist()
    if (self.scavAssistTimer or 0) > GetTime() then return end
    self.scavAssistTimer = GetTime() + 10.0 -- Refresh every 10s
    
    if not self.scavengers then self.scavengers = {} end
    
    -- Clean dead
    aiCore.RemoveDead(self.scavengers)
    
    for _, h in ipairs(self.scavengers) do
        if IsValid(h) and not IsSelected(h) then
            local cmd = GetCurrentCommand(h)
            
            -- Check if Idle (0) or already Scavenging
            -- We refresh every 10s to ensure they recalculate paths to nearest scrap
            if (cmd == 0) or (cmd == AiCommand.SCAVENGE) then
                -- Issue high-priority command (1) to suppress radio voice-over
                SetCommand(h, AiCommand.SCAVENGE, 1)
                -- Immediately restore independence (1) so player can override
                SetIndependence(h, 1)
            end
        end
    end
end

function aiCore.Team:RegisterScavenger(h)
    if not self.scavengers then self.scavengers = {} end
    table.insert(self.scavengers, h)
end

function aiCore.Team:UpdateBaseMaintenance()
    -- Ensure critical units exist (Constructor, Factory, Armory)
    -- Only runs if we have a Recycler
    if not IsValid(self.recyclerMgr.handle) then return end
    if not self.Config.autoBuild then return end
    if not self.Config.manageFactories then return end -- MODIFIED: Skip if disabled
    
    -- Helper to check if item is already in queue
    local function IsInQueue(mgr, odf)
        for _, item in ipairs(mgr.queue) do
            if item.odf == odf then return true end
        end
        return false
    end
    
    -- 1. Constructor
    if not IsValid(self.constructorMgr.handle) then
        local odf = aiCore.Units[self.faction].constructor
        if not IsInQueue(self.recyclerMgr, odf) then
            -- Check if one exists but just isn't linked (e.g. just built)
            -- (AddObject should link it, but let's be safe: Object scanning is slow, so we rely on manager state)
            -- Priority 0 (High)
            if aiCore.Debug then print("Team " .. self.teamNum .. " ordering replacement Constructor.") end
            table.insert(self.recyclerMgr.queue, 1, {odf = odf, priority = 0}) 
        end
    end
    
    -- 2. Factory
    if not IsValid(self.factoryMgr.handle) then
        -- Are we supposed to have one? Yes, usually.
        -- Check if we merely haven't deployed it yet (e.g. "avmuf" vehicle exists)
        local odf = aiCore.Units[self.faction].factory
        local pending = false
        
        -- Check if an undeployed factory vehicle exists
        local nearby = GetNearestObject(self.recyclerMgr.handle)
        if IsValid(nearby) and GetTeamNum(nearby) == self.teamNum and IsOdf(nearby, odf) then
            -- Factory exists but not deployed - send to geyser
            if not IsDeployed(nearby) and not IsBusy(nearby) then
                SetCommand(nearby, AiCommand.GO_TO_GEYSER, 1)
            end
            pending = true
        end
        
        if not pending and not IsInQueue(self.recyclerMgr, odf) then
             if aiCore.Debug then print("Team " .. self.teamNum .. " ordering replacement Factory.") end
             table.insert(self.recyclerMgr.queue, 1, {odf = odf, priority = 0})
        end
    end
    
    -- 3. Armory (Optional? Assume yes for AI)
    local armory = GetArmoryHandle(self.teamNum)
    if not IsValid(armory) then
        local odf = aiCore.Units[self.faction].armory
        
        -- Similar check for undeployed armory vehicle
        local pending = false
        local nearby = GetNearestObject(self.recyclerMgr.handle)
         -- Reuse nearby check is flimsy if they are far apart, but usually they build near recycler.
         -- Ideally we scan, but for now rely on queue.
         
        if not IsInQueue(self.recyclerMgr, odf) then
            -- Only build armory if we assume we need one. 
            -- Let's check config or just default to yes.
             if aiCore.Debug then print("Team " .. self.teamNum .. " ordering replacement Armory.") end
             -- Insert at priority 2 (lower than constructor/factory)
             table.insert(self.recyclerMgr.queue, {odf = odf, priority = 0.5})
             table.sort(self.recyclerMgr.queue, function(a,b) return a.priority < b.priority end) -- Sort for priority
        end
    end
end

-- Configuration / Dynamic Difficulty Hooks
aiCore.Team.Config = {
    -- Pilots
    pilotZeal = 0.4,       -- Chance to be a sniper
    sniperStealth = 0.5,   -- Chance to retreat
    techInterval = 60,     -- Seconds between technician spawns
    techMax = 4,           -- Max technicians to spawn
    
    -- Weapons
    thumperChance = 20,    -- % Chance to use thumper
    mortarChance = 30,     -- % Chance to use mortar
    doubleWeaponChance = 20, -- % Chance for double weapon mask
    
    -- Minelayers
    minefields = {},       -- List of path names or positions
    
    howitzerChance = 50,
    upgradeInterval = 180,
    wreckerInterval = 600,
    
    -- pilotMode Automation (Default OFF)
    autoManage = false,       -- Enable unit role distribution
    autoBuild = false,        -- Enable automatic base building
    autoRescue = false,       -- Enable player rescue system
    autoTugs = false,         -- Enable automatic cargo management
    stickToPlayer = false,    -- Enable physics assistance for wingmen
    
    -- Sub-config for automation
    followPercentage = 30,
    patrolPercentage = 30,
    guardPercentage = 40,
    scavengerCount = 4,
    tugCount = 2,
    buildingSpacing = 80,
    rescueDelay = 2.0,
    
    -- New Features
    enableWreckers = false,
    paratrooperChance = 0,
    paratrooperInterval = 600,
    
    -- Reinforcements
    orbitalReinforce = true,
    
    -- Legacy Features (C++ Gems)
    passiveRegen = false,      -- Enable Recycler health regeneration
    regenRate = 20.0,          -- Health per second
    reclaimEngineers = false,  -- Enable auto-reclaim for engineers
    dynamicMinefields = false, -- Enable proximity-based mine spawning
    
    scavengerAssist = false,    -- Enable automanagement of friendly scavengers
    
    -- Construction Defaults
    buildingSpacing = 70.0,
    siloMinDistance = 250.0,
    siloMaxDistance = 450.0
}

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

-- Building Spacing Helper (from aiBuildOS)
function aiCore.Team:CheckBuildingSpacing(odf, position, minDistance)
    minDistance = minDistance or 50
    
    for obj in ObjectsInRange(minDistance, position) do
        if IsBuilding(obj) and GetTeamNum(obj) == self.teamNum then
            -- Same type strict spacing
            if IsOdf(obj, odf) then
                return false, "Same type too close"
            end
            -- General crowding
            if GetDistance(obj, position) < (minDistance * 0.6) then
                return false, "Area too crowded"
            end
        end
    end
    return true, "OK"
end

function aiCore.Team:UpdateRegen()
    -- Consolidated Regen: Recycler (High Rate) + Combat Units (Low Rate)
    local recycler = self.recyclerMgr.handle
    if IsValid(recycler) then
        AddHealth(recycler, (self.Config.regenRate or 20.0) * 0.05) 
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
                if self.faction == 2 then odf = "svmine" end -- CCA specific
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

function aiCore.Team:UpdateMinelayers()
    aiCore.RemoveDead(self.minelayers)
    if #self.minelayers == 0 then return end
    
    -- 1. Ensure minefields exist
    if #self.Config.minefields == 0 then
        if IsValid(self.recyclerMgr.handle) then
            for i=1, 3 do
                local pos = GetPositionNear(GetPosition(self.recyclerMgr.handle), 150, 400)
                table.insert(self.Config.minefields, pos)
            end
        end
        return 
    end
    
    for i, m in ipairs(self.minelayers) do
        if IsAlive(m) and not IsBusy(m) then
            -- A. Reactive Mining (Self defense)
            local enemy = GetNearestEnemy(m)
            if IsValid(enemy) and GetDistance(m, enemy) < 200 and GetDistance(m, enemy) > 60 then
                 local mineOdf = aiCore.Units[self.faction].mine or "proxmine"
                 BuildObject(mineOdf, 0, GetPosition(m))
                 local dir = Normalize(GetPosition(m) - GetPosition(enemy))
                 Goto(m, GetPosition(m) + dir * 100)
            
            -- B. Systematic Mining (Laying Fields)
            elseif GetAmmo(m) > 0.8 then
                local field = self.Config.minefields[math.random(#self.Config.minefields)]
                Mine(m, field, 1)
            
            -- C. Resupply
            elseif GetAmmo(m) < 0.2 then
                -- Search for supply depot or return to base
                local foundSupp = false
                local supplyOdf = aiCore.Units[self.faction].supply
                for obj in ObjectsInRange(500, m) do
                    if IsOdf(obj, supplyOdf) and IsAlive(obj) then
                        Goto(m, obj, 1)
                        foundSupp = true
                        break
                    end
                end
                
                if not foundSupp and IsValid(self.recyclerMgr.handle) then
                    Goto(m, self.recyclerMgr.handle, 1)
                end
            end
        end
    end
end

function aiCore.Team:UpdateAdvancedWeapons()
    -- Consolidated Special Weapon Management (Duration/Period from aiSpecial)
    aiCore.RemoveDead(self.mortars)
    aiCore.RemoveDead(self.thumpers)
    aiCore.RemoveDead(self.fields)

    if not self.weaponTimer then self.weaponTimer = GetTime() + 1.0 end
    if GetTime() < self.weaponTimer then return end

    if not self.specialActive then
        -- Logic to ACTIVATE special weapons
        self.specialActive = true
        self.weaponTimer = GetTime() + (self.Config.specialDuration or 5.0)
        
        -- Activate for random subset
        local lists = {self.mortars, self.thumpers, self.fields}
        for _, list in ipairs(lists) do
            for _, u in ipairs(list) do
                if IsAlive(u) and math.random() < 0.7 then
                    local mask = 0
                    if list == self.thumpers then mask = aiCore.GetWeaponMask(u, {"quake", "thump"})
                    elseif list == self.mortars then mask = aiCore.GetWeaponMask(u, {"mortar", "splint", "mdmgun"})
                    elseif list == self.fields then mask = aiCore.GetWeaponMask(u, {"phantom", "redfld", "sitecam"})
                    end
                    if mask > 0 then SetWeaponMask(u, mask) end
                end
            end
        end
        
        -- Double Weapon Users
        aiCore.RemoveDead(self.doubleUsers)
        for _, u in ipairs(self.doubleUsers) do
             if math.random() < (self.Config.doubleWeaponChance or 0.2) then
                SetWeaponMask(u, 3) -- Link 1+2
             end
        end
    else
        -- Logic to DEACTIVATE
        self.specialActive = false
        self.weaponTimer = GetTime() + (self.Config.specialPeriod or 25.0)
        
        local allSpecial = {}
        for _, list in ipairs({self.mortars, self.thumpers, self.fields, self.doubleUsers}) do
            for _, u in ipairs(list) do table.insert(allSpecial, u) end
        end
        
        for _, u in ipairs(allSpecial) do
            if IsAlive(u) then
                self:ResetWeaponMask(u)
            end
        end
    end
end

function aiCore.Team:ResetWeaponMask(h)
    local w0 = utility.CleanString(GetWeaponClass(h, 0))
    local w1 = utility.CleanString(GetWeaponClass(h, 1))
    local w2 = utility.CleanString(GetWeaponClass(h, 2))
    local w3 = utility.CleanString(GetWeaponClass(h, 3))
    
    if w0 ~= "" and w3 ~= "" and w0 == w3 then SetWeaponMask(h, 15) -- Link 4
    elseif w0 ~= "" and w2 ~= "" and w0 == w2 then SetWeaponMask(h, 7) -- Link 3
    elseif w0 ~= "" and w1 ~= "" and w0 == w1 then SetWeaponMask(h, 3) -- Link 2
    elseif w1 ~= "" and w2 ~= "" and w1 == w2 then SetWeaponMask(h, 6) -- Link 2
    else
        -- Check if it should be in double mode
        for _, du in ipairs(self.doubleUsers) do
            if du == h then SetWeaponMask(h, 3) return end
        end
        SetWeaponMask(h, 1) -- Baseline
    end
end

function aiCore.Team:UpdateParatroopers()
    if (self.Config.paratrooperChance or 0) <= 0 then return end
    
    if GetTime() > (self.paratrooperTimer or 0) then
        self.paratrooperTimer = GetTime() + (self.Config.paratrooperInterval or 600)
        
        -- Roll for drop
        if math.random(100) > self.Config.paratrooperChance then return end
        
        -- Find critical target
        local target = self:FindCriticalTarget()
        if not IsValid(target) then return end
        
        local pos = GetPosition(target)
        pos.y = pos.y + 400.0 -- 400M in the sky
        
        local count = math.random(3, 8)
        local soldierOdf = aiCore.Units[self.faction].soldier or "aspilo" -- Fallback
        
        if aiCore.Debug then print("Team " .. self.teamNum .. " launching paratrooper drop ("..count..") on " .. GetOdf(target)) end
        
        for i = 1, count do
            local spawnPos = GetPositionNear(pos, 5, 20)
            local s = BuildObject(soldierOdf, self.teamNum, spawnPos)
            if IsValid(s) then
                table.insert(self.soldiers, s)
                Attack(s, target, 0)
                -- Give them a little drift/random velocity so they don't fall in a perfect line
                SetVelocity(s, SetVector(math.random(-5, 5), -2, math.random(-5, 5)))
                
                -- MODIFED: Paratroopers technically "created" in sky - if they were powerups we'd swap team, 
                -- but soldiers are fine. However, we'll ensure they are on AI team.
            end
        end
    end
end

function aiCore.Team:UpdateHowitzers()
    aiCore.RemoveDead(self.howitzers)
    if #self.howitzers == 0 then return end
    
    local target = nil
    -- Find nearest enemy building or unit
    for h in ObjectsInRange(2000, self.howitzers[1]) do
        if GetTeamNum(h) ~= self.teamNum and IsAlive(h) and IsBuilding(h) then
            target = h
            break
        end
    end
    
    if not target then target = GetNearestEnemy(self.howitzers[1]) end
    if not IsValid(target) then return end
    
    for i, h in ipairs(self.howitzers) do
        if not IsBusy(h) then
            local dist = GetDistance(h, target)
            if dist > 350 then
                Attack(h, target)
            elseif dist < 120 then
                -- Tactical Retreat (from aiSpecial)
                local dir = Normalize(GetPosition(h) - GetPosition(target))
                Goto(h, GetPosition(h) + dir * 100)
            end
        end
    end
end

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
            local target = GetRecyclerHandle(3 - self.teamNum) -- Default enemy
            if not IsValid(target) then target = self:FindCriticalTarget() end
            
            if IsValid(target) then 
                -- BUG FIX: Record target for Team 1 workaround in AddObject
                self.lastArmoryTarget = target
                local wreckerOdf = aiCore.Units[self.faction].wrecker or "apwrck"
                BuildAt(armory, wreckerOdf, target, 1) 
            end
        end
    end
end

function aiCore.Team:UpdateStrategyRotation()
    if self.strategyLocked then return end
    if not self.strategyTimer then self.strategyTimer = GetTime() + aiCore.Constants.STRATEGY_ROTATION_INTERVAL end
    if GetTime() > self.strategyTimer then
        self.strategyTimer = GetTime() + aiCore.Constants.STRATEGY_ROTATION_INTERVAL
        local strats = {"Balanced", "Tank_Heavy", "Howitzer_Heavy", "Bomber_Heavy"}
        self:SetStrategy(strats[math.random(#strats)])
    end
end

function aiCore.Team:UpdateAutoBase()
    if not self.Config.autoBuild then return end
    local constructor = self.constructorMgr.handle
    if not IsValid(constructor) or IsBusy(constructor) then return end
    
    -- Rebuild Factory if lost
    local factory = GetFactoryHandle(self.teamNum)
    if not IsAlive(factory) and self.basePositions.factory then
        local found = false
        for _, q in ipairs(self.constructorMgr.queue) do
            if q.odf == aiCore.Units[self.faction].factory then found = true break end
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
    aiCore.RemoveDead(self.cloakers) -- Simple stub, usually handled by engine
end

function aiCore.Team:UpdateSoldiers()
    aiCore.RemoveDead(self.soldiers)
    for _, s in ipairs(self.soldiers) do
        if IsAlive(s) then
            local enemy = GetNearestEnemy(s)
            if IsValid(enemy) and GetDistance(s, enemy) < 100 then Attack(s, enemy) end
        end
    end
end

function aiCore.Team:UpdateGuards()
    -- Maintain squad/howitzer guards
end

function aiCore.Team:UpdateUnitRoles()
    -- Handled by pool/squad logic
end

function aiCore.Team:UpdateRescue()
    -- Send vehicle to player if they are a person
    if self.teamNum ~= 1 or not self.Config.autoRescue then return end
    local player = GetPlayerHandle()
    if IsPerson(player) and GetTime() > (self.rescueTimer or 0) then
        self.rescueTimer = GetTime() + aiCore.Constants.RESCUE_CHECK_INTERVAL
        local veh = self.pool[1]
        if IsValid(veh) then SetCommand(veh, AiCommand.RESCUE, 1, player) end
    end
end

function aiCore.Team:UpdateTugs()
    -- Auto-pickup relics
end

function aiCore.Team:UpdatePilots()
    -- Consolidated Pilot Management: technician spawning + sniper logic + craft stealing
    aiCore.RemoveDead(self.pilots)

    -- 1. Technician Spawning (from Barracks)
    local barracks = {}
    if IsValid(self.recyclerMgr.handle) then
        for obj in ObjectsInRange(300, self.recyclerMgr.handle) do
            local cls = string.lower(utility.CleanString(GetClassLabel(obj)))
            if string.find(cls, utility.ClassLabel.BARRACKS) or string.find(cls, "training") then
                table.insert(barracks, obj)
            end
        end
    end
    
    if #barracks > 0 and #self.pilots < (self.Config.techMax or 4) then
        if not self.techTimer then self.techTimer = GetTime() + (self.Config.techInterval or 60) end
        if GetTime() > self.techTimer then
            local fac = barracks[math.random(#barracks)]
            if IsValid(fac) and IsAlive(fac) then
                local pilotOdf = aiCore.GuessPilotOdf(fac)
                local pos = GetPosition(fac)
                pos.z = pos.z + 15 
                local pilot = BuildObject(pilotOdf, self.teamNum, pos)
                if IsValid(pilot) then
                    table.insert(self.pilots, pilot)
                    Goto(pilot, GetPositionNear(pos, 50, 150))
                end
            end
            self.techTimer = GetTime() + (self.Config.techInterval or 60) + math.random(10)
        end
    end
    
    -- 2. Individual Pilot Logic
    for _, p in ipairs(self.pilots) do
        if IsAlive(p) and IsPerson(p) then
            -- Individual Pilot Logic (Technician Behavior)
            local weapon0 = utility.CleanString(GetWeaponClass(p, 0))
            local enemy = GetNearestEnemy(p)
            local dist = IsValid(enemy) and GetDistance(p, enemy) or 9999
            
            -- Sniper Modification
            if weapon0 ~= "" and string.find(weapon0, "handgun") then
                if IsValid(enemy) and dist < 200 and math.random() < (self.Config.pilotZeal or 0.4) then
                    GiveWeapon(p, "gsnipe", 0)
                end
            elseif weapon0 ~= "" and string.find(weapon0, "gsnipe") then
                -- Sniper Tactics
                if GetAmmo(p) < 0.1 or dist > 300 then
                    GiveWeapon(p, "handgun", 0)
                elseif IsValid(enemy) then
                    Attack(p, enemy)
                end
            end

            -- Craft Stealing (from aiSpecial)
            if self.Config.sniperSteal then
                local target = GetTarget(p)
                if IsValid(target) and IsCraft(target) and GetTeamNum(target) == 0 then
                    if GetDistance(p, target) < 150 then
                        GetIn(p, target)
                        if aiCore.Debug then print("Team "..self.teamNum.." pilot stealing neutral craft.") end
                    else
                        Goto(p, target)
                    end
                end
            end
            
            if not IsBusy(p) and dist > 300 then
                 -- Roam or wander back to base
                 if IsValid(self.recyclerMgr.handle) then
                    Goto(p, GetPositionNear(GetPosition(self.recyclerMgr.handle), 50, 100))
                 end
            end
        end
    end
end

----------------------------------------------------------------------------------
-- TACTICAL LOGIC EXTENSIONS
----------------------------------------------------------------------------------

function aiCore.Team:UpdateSquads()
    -- 1. Manage Pool (Form Squads)
    aiCore.RemoveDead(self.pool)
    if #self.pool >= 3 then
        local leader = table.remove(self.pool, 1)
        if IsValid(leader) then
            local newSquad = aiCore.Squad:new(leader)
            
            -- Add 2 members
            for i=1, 2 do
                local m = table.remove(self.pool, 1)
                if IsValid(m) then newSquad:AddMember(m) end
            end
            
            -- Assign Flank Mission
            -- Find target (Player Recycler/Factory or just Enemy)
            local target = GetNearestEnemy(leader)
            if IsValid(target) then
                -- Pick random angle
                local angle = math.random(0, 360)
                local dist = 300 + math.random(200)
                local flankPos = aiCore.GetFlankPosition(target, dist, angle)
                
                newSquad.targetPos = flankPos
                newSquad.state = "moving_to_flank"
                Goto(leader, flankPos)
                if aiCore.Debug then print("Team " .. self.teamNum .. " formed squad. Flanking...") end
            end
            
            table.insert(self.squads, newSquad)
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
                    if GetHealth(obj) < 0.5 then
                        target = obj
                        powerup = "aprepa"
                        break
                    elseif GetAmmo(obj) < 0.3 then
                        target = obj
                        powerup = "apammo"
                        break
                    end
                end
            end
            
            if IsValid(target) then
                -- BUG FIX: Record target for Team 1 workaround in AddObject
                self.lastArmoryTarget = target
                BuildAt(armory, powerup, target, 1)
                if aiCore.Debug then print("Team " .. self.teamNum .. " launching " .. powerup) end
            end
        end
    end
end


function aiCore.Team:CheckBuildList(list, mgr)
    for p, item in pairs(list) do
        if not IsValid(item.handle) then
            -- Link-up logic for existing objects
            local nearby = GetNearestObject(mgr.handle or GetRecyclerHandle(self.teamNum))
            if IsValid(nearby) and IsOdf(nearby, item.odf) and GetDistance(nearby, mgr.handle) < 150 and GetTeamNum(nearby) == self.teamNum then
                 local taken = false
                 for _, other in pairs(list) do 
                    if other.handle == nearby then taken = true break end 
                 end
                 if not taken then
                    item.handle = nearby
                 end
            end
            
            if not IsValid(item.handle) then
                local inQueue = false
                -- Check aiCore shadow queue
                for _, qItem in ipairs(mgr.queue) do
                    if qItem.priority == p then inQueue = true break end
                end
                
                if not inQueue then
                    -- Record in shadow queue to prevent double-ordering
                    table.insert(mgr.queue, {odf = item.odf, priority = p})
                    
                    -- Hand off to integrated producer
                    producer.QueueJob(item.odf, self.teamNum, nil, nil, {source = "aiCore", priority = p, type = "unit"})
                    
                    if aiCore.Debug then print("aiCore: Team " .. self.teamNum .. " queued " .. item.odf .. " (unit)") end
                end
            end
        end
    end
end

function aiCore.Team:CheckConstruction()
    for p, item in pairs(self.buildingList) do
        if not IsValid(item.handle) then
            local pos = item.path
            if type(pos) == "string" then pos = paths.GetPosition(pos, 0) end

            local found = nil
            for obj in ObjectsInRange(60, pos) do
                if IsOdf(obj, item.odf) and GetTeamNum(obj) == self.teamNum then
                    found = obj
                    break
                end
            end
            
            if found then
                item.handle = found
            else
                local inQueue = false
                for _, qItem in ipairs(self.constructorMgr.queue) do
                    if qItem.priority == p then inQueue = true break end
                end
                if not inQueue then
                    table.insert(self.constructorMgr.queue, {odf = item.odf, path = item.path, priority = p})
                    
                    -- Queue building via integrated producer
                    producer.QueueJob(item.odf, self.teamNum, item.path, nil, {source = "aiCore", priority = p, type = "building"})
                    
                    if aiCore.Debug then print("aiCore: Team " .. self.teamNum .. " queued building " .. item.odf) end
                end
            end
        end
    end
end

function aiCore.Team:AddObject(h)
    -- Duplicate check
    if aiCore.IsTracked(h, self.teamNum) then return end
    
    local odf = string.lower(utility.CleanString(GetOdf(h)))
    local cls = string.lower(utility.CleanString(GetClassLabel(h)))
    
    -- BUG FIX: Day Wrecker / Powerup Workaround (Team 1 + GO command)
    -- As seen in aiSpecial.CreateWrecker: projectiles need Team 1 to receive GO commands properly in BZR
    if (cls == "daywrecker" or cls == "ammopack" or cls == "repairkit" or cls == "wpnpower" or cls == "camerapod") then
        if self.teamNum ~= 1 then -- If it belongs to an AI team
            SetTeamNum(h, 1) -- Swap to player team
            if IsValid(self.lastArmoryTarget) then
                Goto(h, self.lastArmoryTarget, 1)
                if aiCore.Debug then print("AI Powerup Workaround Applied: " .. odf .. " -> Team 1 (Target: " .. utility.CleanString(GetOdf(self.lastArmoryTarget)) .. ")") end
            end
        end
    end

    -- MODIFIED: Integrated Producer Tracking
    if producer.ProcessCreated(h) then
        if aiCore.Debug then print("aiCore: Integrated Producer -> Built " .. odf) end
    end
    
    -- Link to build lists
    local linked = false
    local function link(list, mgr)
        if mgr.queue[1] and mgr.queue[1].odf == odf then
            if IsValid(mgr.handle) and GetDistance(h, mgr.handle) < 150 then
                local priority = mgr.queue[1].priority
                list[priority].handle = h
                table.remove(mgr.queue, 1)
                linked = true
            end
        end
    end
    
    link(self.recyclerBuildList, self.recyclerMgr)
    link(self.factoryBuildList, self.factoryMgr)
    
    -- Constructor linking checks path distance
    if self.constructorMgr.queue[1] and self.constructorMgr.queue[1].odf == odf then
        local qItem = self.constructorMgr.queue[1]
        if GetDistance(h, qItem.path) < 60 then
            self.buildingList[qItem.priority].handle = h
            table.remove(self.constructorMgr.queue, 1)
            linked = true
        end
    end
    
    -- Scavenger Assist (Auto-Registration)
    if cls == utility.ClassLabel.SCAVENGER then
        self:RegisterScavenger(h)
    end
    
    -- Add to tactical lists
    if string.find(cls, utility.ClassLabel.HOWITZER) then
        table.insert(self.howitzers, h)
    elseif string.find(cls, utility.ClassLabel.APC) then
        table.insert(self.apcs, h)
    elseif string.find(cls, utility.ClassLabel.MINELAYER) then
        table.insert(self.minelayers, h)
    elseif string.match(odf, "^cv") or string.match(odf, "^mv") or string.match(odf, "^dv") then
        table.insert(self.cloakers, h)
        if linked then table.insert(self.pool, h) end
    elseif string.find(cls, utility.ClassLabel.TURRET) or string.find(cls, "tower") or string.match(odf, "turr") then
        table.insert(self.turrets, h)
    elseif string.find(cls, utility.ClassLabel.TUG) or string.find(cls, "haul") then
        table.insert(self.tugHandles, h)
    elseif IsPerson(h) and odf == string.lower(aiCore.Units[self.faction].soldier or "") then
        table.insert(self.soldiers, h)
    end
    
    -- Advanced Weapon Users (from aiSpecial patterns)
    if aiCore.GetWeaponMask(h, {"mortar", "splint", "acidcl", "mdmgun"}) > 0 then table.insert(self.mortars, h) end
    if aiCore.GetWeaponMask(h, {"quake", "thump"}) > 0 then table.insert(self.thumpers, h) end
    if aiCore.GetWeaponMask(h, {"phantom", "redfld", "sitecam"}) > 0 then table.insert(self.fields, h) end
    
    -- Double Weapon Tracking (Wingmen/Walkers)
    if string.find(cls, utility.ClassLabel.WINGMAN) or string.find(cls, utility.ClassLabel.WALKER) then
        table.insert(self.doubleUsers, h) 
        if linked then
            table.insert(self.pool, h)
            if IsValid(self.recyclerMgr.handle) and self.teamNum ~= 1 then -- Don't force player units to base
                Goto(h, self.recyclerMgr.handle)
            end
        end
    end

    -- Soldier Tracking (Person class, excluding pilots/snipers)
    if string.find(cls, utility.ClassLabel.PERSON) then
        local w0 = GetWeaponClass(h, 0)
        local isSniper = w0 and (string.find(string.lower(w0), "snipe") or string.find(string.lower(w0), "handgun"))
        if not isSniper then
            table.insert(self.soldiers, h)
        else
            table.insert(self.pilots, h)
        end
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

function aiCore.Team:FindCriticalTarget()
    local enemyTeam = 3 - self.teamNum
    local recycler = GetRecyclerHandle(enemyTeam)
    if IsAlive(recycler) then return recycler end
    
    local factory = GetFactoryHandle(enemyTeam)
    if IsAlive(factory) then return factory end
    
    local armory = GetArmoryHandle(enemyTeam)
    if IsAlive(armory) then return armory end
    
    -- Fallback: any building
    for obj in AllObjects() do
        if GetTeamNum(obj) == enemyTeam and IsBuilding(obj) and IsAlive(obj) then
            return obj
        end
    end
    
    return nil
end


function aiCore.Team:PlanDefensivePerimeter(powerCount, towersPerPower)
    local recycler = self.recyclerMgr.handle
    if not IsValid(recycler) then return end
    local recyclerPos = GetPosition(recycler)
    
    -- Smart Power Selection
    local powerKey = aiCore.DetectWorldPower()
    local powerOdf = aiCore.Units[self.faction][powerKey]
    -- Fallback if specific power ODF missing for faction
    if not powerOdf then powerOdf = aiCore.Units[self.faction].sPower end
    
    local towerOdf = aiCore.Units[self.faction].gunTower
    
    local foundPowers = 0
    local startPriority = 10 -- Start building after core infrastructure
    
    for angle = 0, 2 * math.pi, math.pi / 4 do
        if foundPowers >= powerCount then break end
        
        local dist = 120.0
        local x = recyclerPos.x + dist * math.cos(angle)
        local z = recyclerPos.z + dist * math.sin(angle)
        local pPos = SetVector(x, GetTerrainHeight(x, z), z)
        
        if aiCore.IsAreaFlat(pPos, 12, 8, 0.96, 0.7) and self:CheckBuildingSpacing(powerOdf, pPos, 60) then
            -- Found spot for power
            local pMat = BuildDirectionalMatrix(pPos, Normalize(pPos - recyclerPos))
            foundPowers = foundPowers + 1
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
aiCore.GlobalDepotManagers = {} -- team -> DepotManager

function aiCore.AddTeam(teamNum, faction)
    local t = aiCore.Team:new(teamNum, faction)
    aiCore.ActiveTeams[teamNum] = t
    return t
end

function aiCore.Update()
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
            aiCore.GlobalDefenseManagers[team]:Update()
            aiCore.GlobalDepotManagers[team]:Update()
        end
    end
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
-- Allows mission scripts to queue a series of buildings that depend on each other
-- Example: team:QueuePhasedBuildings({{odf="abtowe", path="p1"}, {odf="abwpow", path="p2"}})
function aiCore.Team:QueuePhasedBuildings(buildingList)
    -- We'll just add them to the buildingList with increasing priority
    -- The ConstructorManager already builds in order of priority (implied by queue indexing)
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
