-- Shared mock engine for the aiCore regression tests (Test-AiCoreFixes.lua,
-- Test-AiCoreHumanTeams.lua). Not a test itself: the Test-*.lua files dofile() it.
--
-- Handles are plain tables. Useful fields: team, odf, class, craft, building, person,
-- alive/valid, busy, deployed, health, command, target, weapons = {[slot]="name"}, mask, pos.
local H = {}
H.now = 0.0
H.timeStep = 0.1
H.builds, H.buildAts, H.commands, H.weaponMasks, H.cloaks = {}, {}, {}, {}, {}
H.costs = {}
H.objects = {}        -- every world object (AllObjects / AllCraft / ObjectsInRange)
H.playerHandle = nil
H.isPlayer = {}       -- handle -> true
H.openOdfCalls = {}   -- odf name -> count
H.exuMass = {}        -- handle -> mass set through exu.SetMass
H.turbo = {}          -- handle -> turbo flag set through exu.SetUnitTurbo
H.lowerTurboCalls = 0

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
local function iterate(list)
    local i = 0
    return function()
        i = i + 1
        return list[i]
    end
end

package.preload.DiffUtils = function()
    return {
        Get = function() return { enemy = 1.0 } end,
        ApplyAiCoreDifficulty = function(team, role)
            H.lastDifficultyRole = role
            return {}
        end,
    }
end

AiCommand = {
    NONE = 0, BUILD = 1, GO = 2, GET_REPAIR = 3, GET_RELOAD = 4,
    DEPLOY = 5, UNDEPLOY = 6, GO_TO_GEYSER = 7, DEFEND = 8, FOLLOW = 9,
    ATTACK = 10, FORMATION = 11, RESCUE = 12, PICKUP = 13, STOP = 14, HUNT = 15,
    PATROL = 16, SCAVENGE = 17
}
for name, value in pairs(AiCommand) do AiCommand[value] = name end

GetTime = function() return H.now end
GetTimeStep = function() return H.timeStep end
IsValid, IsAlive = valid, alive
IsCraft = function(h) return valid(h) and h.craft == true end
IsBuilding = function(h) return valid(h) and h.building == true end
IsPerson = function(h) return valid(h) and h.person == true end
IsDeployed = function(h) return valid(h) and h.deployed == true end
IsBusy = function(h) return valid(h) and h.busy == true end
IsIndependenceLocked = function(h) return valid(h) and h.locked == true end
GetTeamNum = function(h) return valid(h) and h.team or -1 end
GetPerceivedTeam = GetTeamNum
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
GetCurAmmo = function(h) return valid(h) and (h.ammo or 1.0) or 0 end
GetMaxAmmo = function() return 1.0 end
GetAmmo = GetCurAmmo
GetTeamSlot = function() return nil end
GetScrap = function() return 100 end
GetMaxScrap = function() return 200 end
GetPilot = function() return 20 end
GetPlayerHandle = function() return H.playerHandle end
GetNearestEnemy = function() return nil end
GetNearestBuilding = function() return nil end
GetNearestObject = function() return nil end
GetWeaponClass = function(h, slot) return valid(h) and h.weapons and h.weapons[slot] or "" end
GetWeaponMask = function(h) return valid(h) and h.mask or 0 end
SetWeaponMask = function(h, mask)
    h.mask = mask
    table.insert(H.weaponMasks, { handle = h, mask = mask })
end
FireWeaponMask = function() end
GetWhoShotMe = function(h) return valid(h) and h.shotBy or nil end
GetLastEnemyShot = function(h) return valid(h) and h.lastShot or -999 end
GetCurrentWeapon = function() return 0 end
GetTerrainHeight = function() return 0 end
GetTerrainHeightAndNormal = function() return 0, { x = 0, y = 1, z = 0 } end
GetCommandableAttackPriority = function() return 1 end
GetUncommandablePriority = function() return 1 end
GetPositionNear = function(p) return p end
SetVector = function(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
SetCommand = function(h, command, priority, who, where, param, odf)
    h.command, h.target = command, who
    table.insert(H.commands, { handle = h, command = command, target = who, position = where, odf = odf })
end
Attack = function(h, target)
    h.command, h.target = AiCommand.ATTACK, target
    table.insert(H.commands, { handle = h, command = AiCommand.ATTACK, target = target })
end
Build = function(h, odf) table.insert(H.builds, { builder = h, odf = odf }) end
BuildAt = function(h, odf, where) table.insert(H.buildAts, { builder = h, odf = odf, where = where }) end
Stop = function(h) h.command = AiCommand.NONE end
SetCloaked = function(h) table.insert(H.cloaks, { handle = h, cloak = true }) end
SetDecloaked = function(h) table.insert(H.cloaks, { handle = h, cloak = false }) end
IsCloaked = function() return false end
IsOdf = function(h, odf) return string.lower(GetOdf(h)) == string.lower(tostring(odf)) end
IsTeamAllied = function(a, b) return a == b end
IsAlly = function(a, b) return GetTeamNum(a) == GetTeamNum(b) end
CanBuild = function(h) return valid(h) and h.canBuild ~= false end
OpenODF = function(odf)
    H.openOdfCalls[odf] = (H.openOdfCalls[odf] or 0) + 1
    return { odf = odf }
end
GetODFInt = function(handle, _, key, default)
    if key == "scrapCost" then return H.costs[handle.odf] or 0 end
    if key == "pilotCost" then return 0 end
    return default
end
GetODFFloat = function(_, _, _, default) return default end
GetODFBool = function(_, _, _, default) return default end
GetODFString = function(_, _, _, default) return default end
ObjectsInRange = function(range, ref)
    local out = {}
    for _, o in ipairs(H.objects) do
        if valid(o) and distance(o, ref) <= range then out[#out + 1] = o end
    end
    return iterate(out)
end
H.allObjectsCalls = 0
AllObjects = function()
    H.allObjectsCalls = H.allObjectsCalls + 1
    return iterate(H.objects)
end
AllCraft = function()
    local out = {}
    for _, o in ipairs(H.objects) do
        if valid(o) and o.craft then out[#out + 1] = o end
    end
    return iterate(out)
end
Length = function(v) return math.sqrt((v.x or 0) ^ 2 + (v.y or 0) ^ 2 + (v.z or 0) ^ 2) end

-- Sentinel for "aiCore must not shadow engine globals": the engine's own SetAIP.
H.engineSetAIP = function() end
SetAIP = H.engineSetAIP

exu = {
    SetMass = function(h, m) H.exuMass[h] = m end,
    GetMass = function(h) return H.exuMass[h] or 1750 end,
    SetUnitTurbo = function(h, on) H.turbo[h] = on end,
    setunitturbo = function() H.lowerTurboCalls = H.lowerTurboCalls + 1 end,
}

H.core = { recycler = {}, factory = {}, constructor = {}, armory = {} }
GetRecyclerHandle = function(team) return H.core.recycler[team] end
GetFactoryHandle = function(team) return H.core.factory[team] end
GetConstructorHandle = function(team) return H.core.constructor[team] end
GetArmoryHandle = function(team) return H.core.armory[team] end

-- Minimal stand-in for the native-tactics bridge so cache behaviour can be observed.
H.nativeApplied = 0
package.preload.aiNative = function()
    local policies = {}
    return {
        IsAvailable = function() return true end,
        GetUnitPolicy = function(h) return policies[h] end,
        ApplyUnitPolicy = function(h, policy)
            H.nativeApplied = H.nativeApplied + 1
            policies[h] = policy
            return true
        end,
        ClearAll = function() policies = {} end,
        ClearUnit = function(h) policies[h] = nil end,
        UnwatchTaskState = function() end,
        Update = function() end,
    }
end

function H.load(source)
    assert(loadfile(source or "Scripts/aiCore.lua"))()
    H.aiCore = aiCore
    return aiCore
end

H.passed = 0
H.failures = {}
-- TEST_CONTINUE=1 records failures instead of stopping at the first one (used when running
-- the tests against the pre-fix aiCore.lua to see which cases catch which bug).
function H.check(name, condition)
    if not condition then
        if os.getenv("TEST_CONTINUE") then
            H.failures[#H.failures + 1] = name
            io.write("FAIL - ", name, "\n")
            return
        end
        error("FAILED: " .. name, 2)
    end
    H.passed = H.passed + 1
    io.write("ok - ", name, "\n")
end

-- Run a test body; with TEST_CONTINUE an error counts as one failure instead of aborting.
function H.try(name, fn)
    local ok, err = pcall(fn)
    if not ok then
        if os.getenv("TEST_CONTINUE") then
            H.failures[#H.failures + 1] = name .. " (error: " .. tostring(err) .. ")"
            io.write("FAIL - ", name, " (error: ", tostring(err), ")\n")
        else
            error(err, 0)
        end
    end
end

function H.finish(label)
    if #H.failures > 0 then
        io.write(string.format("%d failed, %d passed (%s)\n", #H.failures, H.passed, label or ""))
        os.exit(1)
    end
    io.write(string.format("%d %s checks passed\n", H.passed, label or "aiCore"))
end

function H.handle(fields)
    fields = fields or {}
    fields.valid = fields.valid ~= false
    fields.alive = fields.alive ~= false
    fields.pos = fields.pos or { x = 0, y = 0, z = 0 }
    return fields
end

function H.addObject(fields)
    local h = H.handle(fields)
    H.objects[#H.objects + 1] = h
    return h
end

function H.reset()
    H.builds, H.buildAts, H.commands, H.weaponMasks, H.cloaks = {}, {}, {}, {}, {}
    if producer then producer.Queue, producer.Orders = {}, {} end
end

return H
