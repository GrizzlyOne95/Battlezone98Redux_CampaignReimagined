-- Deterministic regression coverage for aiCore queue and bookkeeping behavior.
local source = arg[1] or "Scripts/aiCore.lua"
local now = 0.0
local timeStep = 0.1
local builds = {}
local commands = {}
local costs = {}

package.preload.DiffUtils = function()
    return { Get = function() return { enemy = 1.0 } end }
end

local function valid(h) return type(h) == "table" and h.valid ~= false end
local function alive(h) return valid(h) and h.alive ~= false end
local function position(ref)
    if type(ref) ~= "table" then return { x = 0, y = 0, z = 0 } end
    return ref.pos or ref
end
local function distance(a, b)
    local ap, bp = position(a), position(b)
    local dx = (ap.x or 0) - (bp.x or 0)
    local dy = (ap.y or 0) - (bp.y or 0)
    local dz = (ap.z or 0) - (bp.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
local function emptyIterator() return function() return nil end end

AiCommand = {
    NONE = 0, BUILD = 1, GO = 2, GET_REPAIR = 3, GET_RELOAD = 4,
    DEPLOY = 5, UNDEPLOY = 6, GO_TO_GEYSER = 7, DEFEND = 8, FOLLOW = 9,
    ATTACK = 10, FORMATION = 11
}
for name, value in pairs(AiCommand) do AiCommand[value] = name end

GetTime = function() return now end
GetTimeStep = function() return timeStep end
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
GetPosition = position
GetCurrentCommand = function(h) return valid(h) and (h.command or AiCommand.NONE) or AiCommand.NONE end
GetCurrentWho = function(h) return valid(h) and h.target or nil end
GetHealth = function(h) return valid(h) and (h.health or 1.0) or 0 end
GetMaxHealth = function() return 1.0 end
GetCurHealth = GetHealth
GetCurAmmo = function() return 1.0 end
GetMaxAmmo = function() return 1.0 end
GetAmmo = GetCurAmmo
GetTeamSlot = function() return nil end
GetScrap = function(team) return team == 2 and 20 or 100 end
GetMaxScrap = function() return 200 end
GetPilot = function() return 20 end
GetPlayerHandle = function() return nil end
GetNearestEnemy = function() return nil end
GetNearestBuilding = function() return nil end
GetNearestObject = function() return nil end
GetWeaponClass = function() return "" end
GetCurrentWeapon = function() return 0 end
GetTerrainHeight = function() return 0 end
GetCommandableAttackPriority = function() return 1 end
GetUncommandablePriority = function() return 1 end
SetVector = function(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
SetCommand = function(h, command, priority, who, where, param, odf)
    h.command, h.target = command, who
    table.insert(commands, { handle = h, command = command, target = who, position = where, odf = odf })
end
Build = function(h, odf)
    table.insert(builds, { builder = h, odf = odf })
end
Stop = function(h) h.command = AiCommand.NONE end
IsOdf = function(h, odf) return string.lower(GetOdf(h)) == string.lower(tostring(odf)) end
IsTeamAllied = function(a, b) return a == b end
IsAlly = function(a, b) return GetTeamNum(a) == GetTeamNum(b) end
IsCloaked = function() return false end
CanBuild = function(h) return valid(h) and h.canBuild ~= false end
OpenODF = function(odf) return { odf = odf } end
GetODFInt = function(handle, _, key, default)
    if key == "scrapCost" then return costs[handle.odf] or 0 end
    if key == "pilotCost" then return 0 end
    return default
end
GetODFFloat = function(_, _, _, default) return default end
GetODFBool = function(_, _, _, default) return default end
GetODFString = function(_, _, _, default) return default end
ObjectsInRange = emptyIterator
AllObjects = emptyIterator
AllCraft = emptyIterator

local coreHandles = { recycler = {}, factory = {}, constructor = {}, armory = {} }
GetRecyclerHandle = function(team) return coreHandles.recycler[team] end
GetFactoryHandle = function(team) return coreHandles.factory[team] end
GetConstructorHandle = function(team) return coreHandles.constructor[team] end
GetArmoryHandle = function(team) return coreHandles.armory[team] end

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
    builds = {}
    commands = {}
end
local function teamStub(team, recycler, constructor)
    return {
        teamNum = team,
        faction = 2,
        Config = { manageFactories = true, requireConstructorFirst = false, minScavengers = 0 },
        recyclerMgr = { handle = recycler },
        factoryMgr = { handle = nil },
        constructorMgr = { handle = constructor, queue = {} },
        scavengers = {},
        UpdateBuildAccountState = function() end,
        CanIssueUnitByRules = function() return true end
    }
end

local recycler = handle { team = 2, odf = "svrecy", class = "recycler", craft = true, deployed = true }
coreHandles.recycler[2] = recycler
aiCore.Units[2] = {
    recycler = "svrecy", factory = "svfact", constructor = "svcons",
    scavenger = "svscav", scout = "svfigh", turret = "svturr"
}

-- An unaffordable head item must not prevent a later affordable job from running.
resetProducer()
costs.expensive, costs.svscav = 150, 5
producer.QueueJob("expensive", 2, nil, nil, { priority = 1, type = "unit", producer = "recycler" })
producer.QueueJob("svscav", 2, nil, nil, { priority = 2, type = "unit", producer = "recycler" })
producer.ProcessQueues(teamStub(2, recycler))
check("unaffordable job does not starve affordable work",
    #builds == 1 and builds[1].odf == "svscav" and #producer.Queue[2] == 1)

-- Requiring a constructor must still allow the scavengers that fund it.
resetProducer()
local bootstrapTeam = teamStub(2, recycler)
bootstrapTeam.Config.requireConstructorFirst = true
producer.QueueJob("svscav", 2, nil, nil, { priority = 1, type = "unit", producer = "recycler" })
producer.ProcessQueues(bootstrapTeam)
check("constructor-first policy does not block scavenger bootstrap",
    #builds == 1 and builds[1].odf == "svscav")

-- A lost builder must restore its issued job once, and only for its owner team.
resetProducer()
local lostBuilder = handle { team = 2, odf = "svrecy", class = "recycler", craft = true }
producer.QueueJob("svtank", 2, nil, nil, { priority = 3, type = "unit", producer = "recycler" })
local lostJob = producer.Queue[2][1]
producer.Queue[2] = {}
producer.Orders[lostBuilder] = { job = lostJob, issuedAt = now, team = 2 }
lostBuilder.valid = false
producer.ProcessQueues(teamStub(3, nil))
local untouchedByOtherTeam = producer.Orders[lostBuilder] ~= nil
producer.ProcessQueues(teamStub(2, nil))
producer.ProcessQueues(teamStub(2, nil))
check("lost builder recovery is owner-scoped and idempotent",
    untouchedByOtherTeam and producer.Orders[lostBuilder] == nil and #producer.Queue[2] == 1)

-- Ownership changes are treated as loss by the original team, not completion by the new team.
resetProducer()
local transferredBuilder = handle { team = 2, odf = "svrecy", class = "recycler", craft = true }
producer.QueueJob("svtank", 2, nil, nil, { priority = 4, type = "unit", producer = "recycler" })
local transferredJob = producer.Queue[2][1]
producer.Queue[2] = {}
producer.Orders[transferredBuilder] = { job = transferredJob, issuedAt = now, team = 2 }
transferredBuilder.team = 3
producer.ProcessQueues(teamStub(3, nil))
local notClaimedByNewTeam = producer.Orders[transferredBuilder] ~= nil
producer.ProcessQueues(teamStub(2, nil))
check("producer ownership change requeues work for original team",
    notClaimedByNewTeam and producer.Orders[transferredBuilder] == nil and #producer.Queue[2] == 1)

-- Creation callbacks are matched to the order's recorded team, not proximity alone.
resetProducer()
local creatingBuilder = handle { team = 2, odf = "svrecy", class = "recycler", craft = true }
local creatingJob = { odf = "svtank", data = { priority = 4, type = "unit", producer = "recycler" } }
producer.Orders[creatingBuilder] = { job = creatingJob, issuedAt = now, team = 2 }
local foreignCreation = handle { team = 3, odf = "svtank", class = "wingman", craft = true }
local ownCreation = handle { team = 2, odf = "svtank", class = "wingman", craft = true }
local foreignIgnored = producer.ProcessCreated(foreignCreation) == false
check("production completion is team-scoped",
    foreignIgnored and producer.ProcessCreated(ownCreation) == true
        and producer.Orders[creatingBuilder] == nil)

-- Save/load preserves valid issued work and recovers it if the builder vanished.
resetProducer()
local savedBuilder = handle { team = 2, odf = "svrecy", class = "recycler", craft = true }
local savedJob = { odf = "svtank", data = { priority = 5, type = "unit", producer = "recycler" } }
producer.Orders[savedBuilder] = { job = savedJob, issuedAt = 12, team = 2 }
local snapshot = producer.ExportState()
producer.ImportState(snapshot)
check("valid issued production survives save-load", producer.Orders[savedBuilder] ~= nil)
savedBuilder.valid = false
producer.ImportState(snapshot)
producer.ImportState(producer.ExportState())
check("missing saved builder requeues production once",
    producer.Orders[savedBuilder] == nil and #producer.Queue[2] == 1)

-- Team reset cleanup must not discard another team's outstanding work.
local otherBuilder = handle { team = 3, odf = "avrecy", class = "recycler", craft = true }
producer.Queue[3] = { { odf = "avtank", data = { priority = 1 } } }
producer.Orders[otherBuilder] = { job = producer.Queue[3][1], issuedAt = now, team = 3 }
local resetBuilder = handle { team = 2, odf = "svrecy", class = "recycler", craft = true }
producer.Orders[resetBuilder] = { job = { odf = "svtank" }, issuedAt = now, team = 2 }
aiCore.ActiveTeams[2] = { faction = 2, Config = {} }
aiCore.ResetTeam(2, 2, {})
check("team production cleanup is isolated",
    #producer.Queue[2] == 0 and producer.Orders[resetBuilder] == nil
        and #producer.Queue[3] == 1 and producer.Orders[otherBuilder] ~= nil)

-- CheckConstruction must count the active job and avoid queuing it again each maintenance pass.
local constructionTeam = setmetatable({
    teamNum = 2,
    buildingList = { [10] = { odf = "svtowe", path = { x = 20, y = 0, z = 20 }, priority = 10 } },
    constructorMgr = {
        queue = {},
        activeJob = { odf = "svtowe", path = { x = 20, y = 0, z = 20 }, priority = 10 }
    },
    CanQueueBuildingByRules = function() return true end
}, aiCore.Team)
constructionTeam:CheckConstruction()
constructionTeam:CheckConstruction()
check("active constructor job is not duplicated by maintenance", #constructionTeam.constructorMgr.queue == 0)
constructionTeam.constructorMgr.activeJob = nil
constructionTeam:CheckConstruction()
constructionTeam:CheckConstruction()
check("destroyed planned defense queues one replacement", #constructionTeam.constructorMgr.queue == 1)

-- A permanently bad placement is delayed so the next valid job can run.
local constructor = handle { team = 2, odf = "svcons", class = "constructionrig", craft = true, canBuild = true }
local constructorTeam = {
    teamNum = 2,
    Config = { manageConstructor = true, buildingPlacementRetryDelay = 4 },
    CanIssueBuildingByRules = function() return true end,
    ValidateBuildingPlacement = function() return true end
}
local constructorMgr = aiCore.ConstructorManager:new(2)
constructorMgr.teamObj = constructorTeam
constructorMgr.handle = constructor
constructorMgr.queue = {
    { odf = "badsite", path = nil, priority = 1 },
    { odf = "goodsite", path = { x = 0, y = 0, z = 0 }, priority = 2 }
}
constructorMgr:update()
local delayedBadJob = nil
for _, queued in ipairs(constructorMgr.queue) do
    if queued.odf == "badsite" then delayedBadJob = queued; break end
end
check("invalid constructor path becomes a delayed retry",
    constructorMgr.activeJob == nil and #constructorMgr.queue == 2
        and delayedBadJob and delayedBadJob.blockedReason == "invalid_path")
constructorMgr:update()
check("delayed constructor retry does not starve later work",
    constructorMgr.activeJob and constructorMgr.activeJob.odf == "goodsite")

-- Destroyed or transferred defensive bookkeeping must be pruned deterministically.
local staleDepot = handle { team = 2, odf = "svhang", class = "repairdepot", building = true, alive = false }
local foreignDepot = handle { team = 3, odf = "svhang", class = "repairdepot", building = true }
local depotMgr = aiCore.DepotManager.new(2)
depotMgr.depots[staleDepot] = { type = "repair", range = 50, amount = 5 }
depotMgr.depots[foreignDepot] = { type = "repair", range = 50, amount = 5 }
depotMgr.updatePeriod = 0
depotMgr:Update()
check("dead and ownership-changed depots are removed", next(depotMgr.depots) == nil)

commands = {}
local damagedUnit = handle { team = 2, odf = "svtank", class = "wingman", craft = true, health = 0.2 }
local retreatTeam = setmetatable({
    teamNum = 2,
    combatUnits = { damagedUnit },
    depotMgr = { depots = { [foreignDepot] = { type = "repair" } } },
    retreatTimer = 0
}, aiCore.Team)
retreatTeam:UpdateRetreat()
local rejectedForeignRetreat = #commands == 0
local ownDepot = handle { team = 2, odf = "svhang", class = "repairdepot", building = true }
retreatTeam.depotMgr.depots = { [ownDepot] = { type = "repair" } }
now = now + 3
retreatTeam:UpdateRetreat()
check("retreat uses only a live same-team repair destination",
    rejectedForeignRetreat and #commands == 1 and commands[1].command == AiCommand.GET_REPAIR
        and commands[1].target == ownDepot)

local staleGuard = handle { team = 3, odf = "svfigh", class = "wingman", craft = true }
local guardMgr = aiCore.GuardManager.new(2)
guardMgr.teamObj = { Config = { manageFactories = true, autoManage = true }, combatUnits = {} }
guardMgr.recyclerGuards = { staleGuard }
guardMgr.updatePeriod = 0
coreHandles.recycler[2], coreHandles.constructor[2] = nil, nil
guardMgr:Update()
check("ownership-changed guard no longer fills defensive quota", #guardMgr.recyclerGuards == 0)

io.write(string.format("%d aiCore state-management checks passed\n", passed))
