-- Focused regression derived from the historical aiCore test harness.
local source = arg[1] or "Scripts/aiCore.lua"
local now = 0.0
local worldObjects = {}
local buildCounts = {}

package.preload.DiffUtils = function()
    return { Get = function() return { enemy = 1.0 } end }
end

local function valid(h) return type(h) == "table" and h.valid ~= false end
local function alive(h) return valid(h) and h.alive ~= false end
local function distance(a, b)
    local ap = (type(a) == "table" and a.pos) or a or { x = 0, y = 0, z = 0 }
    local bp = (type(b) == "table" and b.pos) or b or { x = 0, y = 0, z = 0 }
    local dx = (ap.x or 0) - (bp.x or 0)
    local dy = (ap.y or 0) - (bp.y or 0)
    local dz = (ap.z or 0) - (bp.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

GetTime = function() return now end
GetTimeStep = function() return 0.1 end
IsValid, IsAlive = valid, alive
IsCraft = function(h) return valid(h) and h.craft == true end
IsBuilding = function(h) return valid(h) and h.building == true end
IsPerson = function(h) return valid(h) and h.person == true end
IsDeployed = function(h) return valid(h) and h.deployed == true end
IsBusy = function(h) return valid(h) and h.busy == true end
IsIndependenceLocked = function(h) return valid(h) and h.locked == true end
GetTeamNum = function(h) return valid(h) and h.team or -1 end
GetOdf = function(h) return valid(h) and h.odf or "" end
GetClassLabel = function(h) return valid(h) and (h.class or "wingman") or "" end
GetClassSig = function() return "" end
GetLabel = function() return "" end
GetDistance = distance
GetPosition = function(h) return (valid(h) and h.pos) or { x = 0, y = 0, z = 0 } end
GetCurrentCommand = function(h) return (valid(h) and h.command) or 0 end
GetCurrentWho = function(h) return valid(h) and h.target or nil end
GetHealth = function(h) return valid(h) and (h.health or 1.0) or 0 end
GetMaxHealth = function() return 1.0 end
GetCurHealth = GetHealth
GetCurAmmo = function() return 1.0 end
GetMaxAmmo = function() return 1.0 end
GetAmmo = GetCurAmmo
GetTeamSlot = function() return nil end
GetScrap = function() return 100 end
GetMaxScrap = function() return 200 end
GetPilot = function() return 20 end
GetPlayerHandle = function() return nil end

local coreHandles = { recycler = {}, factory = {}, constructor = {}, armory = {} }
GetRecyclerHandle = function(team) return coreHandles.recycler[team] end
GetFactoryHandle = function(team) return coreHandles.factory[team] end
GetConstructorHandle = function(team) return coreHandles.constructor[team] end
GetArmoryHandle = function(team) return coreHandles.armory[team] end
GetNearestEnemy = function() return nil end
GetNearestBuilding = function() return nil end
GetNearestObject = function() return nil end
GetWeaponClass = function() return "" end
GetCurrentWeapon = function() return 0 end
GetTerrainHeight = function() return 0 end
SetVector = function(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
SetCommand = function() end
Build = function(_, odf)
    local key = string.lower(tostring(odf))
    buildCounts[key] = (buildCounts[key] or 0) + 1
end
Stop = function() end
IsOdf = function(h, odf) return GetOdf(h):lower() == tostring(odf):lower() end
IsTeamAllied = function(a, b) return a == b end
IsAlly = function(a, b) return GetTeamNum(a) == GetTeamNum(b) end
IsCloaked = function() return false end
CanBuild = function() return true end
OpenODF = function() return {} end
GetODFInt = function(_, _, _, default) return default end
GetODFFloat = function(_, _, _, default) return default end
GetODFBool = function(_, _, _, default) return default end
GetODFString = function(_, _, _, default) return default end
ObjectsInRange = function() return function() return nil end end
AllCraft = function() return function() return nil end end
AllObjects = function()
    local index = 0
    return function()
        index = index + 1
        return worldObjects[index]
    end
end

assert(loadfile(source))()

local function handle(fields)
    fields = fields or {}
    fields.valid = fields.valid ~= false
    fields.alive = fields.alive ~= false
    fields.pos = fields.pos or { x = 0, y = 0, z = 0 }
    return fields
end

local function countQueued(team, odf)
    local count = 0
    for _, job in ipairs(producer.Queue[team] or {}) do
        if string.lower(job.odf or "") == string.lower(odf) then count = count + 1 end
    end
    return count
end

local function countOrdered(team, odf)
    local count = 0
    for builder, active in pairs(producer.Orders or {}) do
        local job = (type(active) == "table" and active.job) or active
        if valid(builder) and GetTeamNum(builder) == team and job
            and string.lower(job.odf or "") == string.lower(odf) then
            count = count + 1
        end
    end
    return count
end

local recycler = handle {
    team = 2,
    odf = "svrecy",
    class = "recycler",
    craft = true,
    deployed = true
}
local factory = handle {
    team = 2,
    odf = "svfact",
    class = "factory",
    craft = true,
    deployed = true
}
coreHandles.recycler[2] = recycler
coreHandles.factory[2] = factory
aiCore.Units[2] = {
    recycler = "svrecy",
    factory = "svfact",
    constructor = "svcons",
    armory = "svslf"
}

local team = setmetatable({
    teamNum = 2,
    faction = 2,
    Config = {
        autoBuild = true,
        manageFactories = true,
        manageConstructor = false,
        allowProducerRelocation = false,
        slotCaps = {}
    },
    buildingList = {},
    baseMaintenanceAt = 0,
    naturalProducerObjects = {}
}, aiCore.Team)
team.recyclerMgr = aiCore.FactoryManager:new(2, true)
team.recyclerMgr.handle, team.recyclerMgr.teamObj = recycler, team
team.factoryMgr = aiCore.FactoryManager:new(2, false)
team.factoryMgr.handle, team.factoryMgr.teamObj = factory, team
team.constructorMgr = { handle = nil, queue = {} }

-- A destroyed singleton is unavailable, so maintenance must queue one replacement.
producer.Queue = { [2] = {} }
producer.Orders = {}
team:UpdateBaseMaintenance()
assert(countQueued(2, "svslf") == 1, "destroyed armory should queue one replacement")

-- The recycler issues that replacement exactly once.
producer.ProcessQueues(team)
assert((buildCounts.svslf or 0) == 1, "replacement armory should be issued once")
assert(countOrdered(2, "svslf") == 1, "replacement armory should remain tracked while building")

-- Model the engine state behind the bug: the replacement exists as an undeployed
-- craft, but GetArmoryHandle still returns nil and its create callback did not match
-- the outstanding order.
local rebuiltArmory = handle {
    team = 2,
    odf = "svslf",
    class = "armory",
    craft = true,
    deployed = false
}
worldObjects = { recycler, factory, rebuiltArmory }

assert(team:HasLiveObjectOfOdf("svslf"), "team should see its rebuilt armory")
rebuiltArmory.team = 3
assert(not team:HasLiveObjectOfOdf("svslf"), "another team's armory must not satisfy this team")
rebuiltArmory.team = 2

-- Recovery must reconcile outstanding orders even when no other jobs are queued.
now = 21
producer.ProcessQueues(team)
assert((buildCounts.svslf or 0) == 1, "recovery must not reissue a live singleton")
assert(countOrdered(2, "svslf") == 0, "live singleton recovery order must be cleared")

for cycle = 2, 4 do
    now = cycle * 21
    producer.QueueJob("svtank" .. cycle, 2, nil, nil, {
        priority = 10 + cycle,
        type = "unit",
        producer = "factory"
    })
    producer.ProcessQueues(team)
    team:UpdateBaseMaintenance()
end

assert((buildCounts.svslf or 0) == 1,
    "live undeployed singleton must not be rebuilt on later recovery cycles")
assert(countQueued(2, "svslf") == 0,
    "live undeployed singleton must not be re-enqueued")
assert(countOrdered(2, "svslf") == 0,
    "completed singleton recovery order must be cleared")

-- Once that producer is genuinely destroyed, the reconciled shadow queue must
-- no longer suppress a legitimate replacement.
rebuiltArmory.alive = false
now = 100
team:UpdateBaseMaintenance()
assert(countQueued(2, "svslf") == 1,
    "destroyed rebuilt singleton should become eligible for replacement")
producer.ProcessQueues(team)
assert((buildCounts.svslf or 0) == 2,
    "genuinely destroyed singleton should be rebuilt once")

io.write("ok - singleton producer rebuild loop\n")
