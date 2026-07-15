local source = arg[1] or "Scripts/aiCore.lua"
local now = 0.0

package.preload.DiffUtils = function()
    return { Get = function() return { enemy = 1.0 } end }
end

local function valid(h) return type(h) == "table" and h.valid ~= false end
local function alive(h) return valid(h) and h.alive ~= false end
local function distance(a, b)
    local ap = (type(a) == "table" and a.pos) or a or { x = 0, y = 0, z = 0 }
    local bp = (type(b) == "table" and b.pos) or b or { x = 0, y = 0, z = 0 }
    local dx, dy, dz = (ap.x or 0) - (bp.x or 0), (ap.y or 0) - (bp.y or 0), (ap.z or 0) - (bp.z or 0)
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
GetTeamSlot = function() return -1 end
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
GetCommandableAttackPriority = function() return 1 end
GetUncommandablePriority = function() return 1 end
SetVector = function(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
SetCommand = function() end
Build = function() end
Stop = function() end
IsOdf = function(h, odf) return GetOdf(h):lower() == tostring(odf):lower() end
IsTeamAllied = function(a, b) return a == b end
IsAlly = function(a, b) return GetTeamNum(a) == GetTeamNum(b) end
IsCloaked = function() return false end
CanBuild = function() return true end
OpenODF = function() return {} end
GetODFInt = function(_, _, key, default)
    if key == "scrapCost" then return 0 end
    if key == "pilotCost" then return 0 end
    return default
end
GetODFString = function(_, _, _, default) return default end
ObjectsInRange = function() return function() return nil end end
AllObjects = function() return function() return nil end end
AllCraft = function() return function() return nil end end

assert(loadfile(source))()

local passed = 0
local function check(name, condition)
    assert(condition, "FAILED: " .. name)
    passed = passed + 1
    io.write("ok - ", name, "\n")
end

local function handle(fields)
    fields = fields or {}
    fields.valid = fields.valid ~= false
    fields.alive = fields.alive ~= false
    fields.pos = fields.pos or { x = 0, y = 0, z = 0 }
    return fields
end

local function resetProducer()
    producer.Queue = {}
    producer.Orders = {}
    producer.Intents = {}
    producer.NextIntentId = 1
    producer.Stats = {}
end

local function teamStub(team)
    return {
        teamNum = team,
        faction = 2,
        Config = { manageFactories = true },
        recyclerMgr = { handle = nil },
        factoryMgr = { handle = nil },
        constructorMgr = { handle = nil },
        UpdateBuildAccountState = function() end,
        IsSingletonProducerOdf = function(_, odf) return odf:lower() == "svslf" end,
        HasLiveObjectOfOdf = function(_, odf) return aiCore.HasIndexedLiveObject(team, odf) end
    }
end

-- Recovery must run even after the issued job has emptied the pending queue.
resetProducer()
local builder = handle { team = 2, odf = "svrecy", craft = true }
local job = producer.QueueJob("svtank", 2, nil, nil, { priority = 1, type = "unit", producer = "recycler" })
producer.Queue[2] = {}
producer.Orders[builder] = { job = job, issuedAt = 0, intentId = job.intentId }
producer.SetIntentState(producer.Intents[job.intentId], "issued", "test")
now = 21
producer.ProcessQueues(teamStub(2))
check("empty-queue stuck order is recovered", #producer.Queue[2] == 1 and producer.Orders[builder] == nil)

-- Existing singleton objects cancel stale work rather than requeueing it.
resetProducer()
aiCore.ObjectIndex = { byTeamOdf = {}, handleMeta = {} }
local armory = handle { team = 2, odf = "svslf", craft = true, deployed = false }
aiCore.IndexWorldObject(armory)
local singletonJob = producer.QueueJob("svslf", 2, nil, nil, { priority = 1, type = "unit", producer = "recycler" })
producer.Queue[2] = {}
producer.Orders[builder] = { job = singletonJob, issuedAt = 0, intentId = singletonJob.intentId }
producer.SetIntentState(producer.Intents[singletonJob.intentId], "issued", "test")
now = 42
producer.ProcessQueues(teamStub(2))
check("undeployed singleton suppresses rebuild", producer.Orders[builder] == nil and #producer.Queue[2] == 0)

-- A nearby creation on another team must not satisfy this team's order.
resetProducer()
local crossJob = producer.QueueJob("avtank", 2, nil, nil, { priority = 1 })
producer.Queue[2] = {}
producer.Orders[builder] = { job = crossJob, issuedAt = now, intentId = crossJob.intentId }
local foreignUnit = handle { team = 3, odf = "avtank", craft = true }
check("create matching is team-scoped", producer.ProcessCreated(foreignUnit) == false and producer.Orders[builder] ~= nil)

local createdUnit = handle { team = 2, odf = "avtank", craft = true, class = "wingman" }
check("ordinary unit creation completes its intent", producer.ProcessCreated(createdUnit) == true
    and producer.Intents[crossJob.intentId].state == "completed")

-- Issued jobs count toward category caps after leaving the queue.
aiCore.Units[2] = aiCore.Units[2] or {}
aiCore.Units[2].tank = "avtank"
local capJob = producer.QueueJob("avtank", 2, nil, nil, { priority = 2 })
producer.Queue[2] = {}
producer.Orders[builder] = { job = capJob, issuedAt = now, intentId = capJob.intentId, team = 2 }
producer.SetIntentState(producer.Intents[capJob.intentId], "issued", "test")
local countTeam = setmetatable({
    teamNum = 2, faction = 2, combatUnits = {}, pool = {}, howitzers = {}, scavengers = {},
    apcs = {}, minelayers = {}, turrets = {}, tugHandles = {}
}, aiCore.Team)
check("issued jobs count toward caps", countTeam:GetUnitCountByCategory("tank") == 1)

-- Save/load preserves an issued order; if its builder vanished, it is requeued once.
local snapshot = producer.ExportState()
producer.ImportState(snapshot)
check("valid issued order survives save/load", producer.Orders[builder] ~= nil and #producer.Queue[2] == 0)
builder.valid = false
producer.ImportState(snapshot)
check("missing builder is requeued on load", producer.Queue[2] and #producer.Queue[2] == 1)
builder.valid = true

-- An invalid builder is recovered only by its owning team.
resetProducer()
local deadBuilder = handle { valid = true, team = 2, odf = "svrecy", craft = true }
local ownerJob = producer.QueueJob("svtank", 2, nil, nil, { priority = 1 })
producer.Queue[2] = {}
producer.Orders[deadBuilder] = { job = ownerJob, issuedAt = now, intentId = ownerJob.intentId, team = 2 }
producer.SetIntentState(producer.Intents[ownerJob.intentId], "issued", "test")
deadBuilder.valid = false
producer.ProcessQueues(teamStub(3))
local untouched = producer.Orders[deadBuilder] ~= nil
producer.ProcessQueues(teamStub(2))
check("invalid builder recovery is owner-scoped", untouched and producer.Orders[deadBuilder] == nil and #producer.Queue[2] == 1)

-- The ODF index sees independence-locked undeployed craft by design.
aiCore.ObjectIndex = { byTeamOdf = {}, handleMeta = {} }
local locked = handle { team = 2, odf = "svfigh", craft = true, locked = true, deployed = false }
aiCore.IndexWorldObject(locked)
check("ODF index includes independence-locked craft", aiCore.HasIndexedLiveObject(2, "SVFIGH") == true)
aiCore.UnindexWorldObject(locked)
check("destroyed object leaves ODF index", aiCore.HasIndexedLiveObject(2, "svfigh") == false)

resetProducer()
local transientJob = producer.QueueJob("svslf", 2, nil, nil, { priority = 1 })
producer.Queue[2] = {}
local transientIntent = producer.Intents[transientJob.intentId]
producer.SetIntentState(transientIntent, "object_created", "test")
transientIntent.object = armory
producer.ProcessDeleted(armory)
check("destroyed transient producer releases pending intent",
    transientIntent.state == "failed" and producer.HasPendingIntent(2, "svslf") == false)

-- Maintenance queues one replacement for a genuinely absent armory, then deduplicates it.
resetProducer()
aiCore.ObjectIndex = { byTeamOdf = {}, handleMeta = {} }
local recycler = handle { team = 2, odf = "svrecy", craft = true, deployed = true, class = "recycler" }
local factory = handle { team = 2, odf = "svfact", craft = true, deployed = true, class = "factory" }
coreHandles.recycler[2], coreHandles.factory[2] = recycler, factory
coreHandles.constructor[2], coreHandles.armory[2] = nil, nil
aiCore.Units[2] = { recycler = "svrecy", factory = "svfact", constructor = "svcons", armory = "svslf" }
local maintenanceTeam = setmetatable({
    teamNum = 2,
    faction = 2,
    Config = { autoBuild = true, manageFactories = true, manageConstructor = false, allowProducerRelocation = false },
    buildingList = {},
    baseMaintenanceAt = 0
}, aiCore.Team)
maintenanceTeam.recyclerMgr = aiCore.FactoryManager:new(2, true)
maintenanceTeam.recyclerMgr.handle, maintenanceTeam.recyclerMgr.teamObj = recycler, maintenanceTeam
maintenanceTeam.factoryMgr = aiCore.FactoryManager:new(2, false)
maintenanceTeam.factoryMgr.handle, maintenanceTeam.factoryMgr.teamObj = factory, maintenanceTeam
maintenanceTeam.constructorMgr = { handle = nil, queue = {} }
now = 100
maintenanceTeam:UpdateBaseMaintenance()
now = 102
maintenanceTeam:UpdateBaseMaintenance()
local armoryJobs = 0
for _, queued in ipairs(producer.Queue[2] or {}) do
    if queued.odf == "svslf" then armoryJobs = armoryJobs + 1 end
end
check("destroyed singleton queues exactly one replacement", armoryJobs == 1)

-- Saturation reduces the score once a weak target already has excess attackers.
aiCore.EstimateCombatStrength = function() return 1.0 end
local attacker = handle { team = 2, odf = "svfigh", craft = true }
local target = handle { team = 1, odf = "avfigh", craft = true, class = "wingman" }
aiCore.TargetAssignments = { [2] = { [target] = 4 } }
local saturated = aiCore.ScoreTarget(attacker, target, {})
aiCore.TargetAssignments = { [2] = {} }
local available = aiCore.ScoreTarget(attacker, target, {})
check("target saturation lowers score", saturated < available)

io.write(string.format("%d regression checks passed\n", passed))
