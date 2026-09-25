-- Regression coverage for idempotent PlayerPilotMode transitions and save/load.
local source = arg[1] or "Scripts/PlayerPilotMode.lua"
local now = 10.0
local objects = {}
local worldObjects = {}
local resetCalls = 0
local buildCalls = 0
local resourceCalls = 0

local function valid(h) return type(h) == "table" and h.valid ~= false end
local function alive(h) return valid(h) and h.alive ~= false end
local function iterator(list)
    local index = 0
    return function()
        index = index + 1
        return list[index]
    end
end

AiCommand = { NONE = 0, GO = 2, DEFEND = 8, FOLLOW = 9, ATTACK = 10, PICKUP = 12 }
GetTime = function() return now end
IsValid, IsAlive = valid, alive
IsCraft = function(h) return valid(h) and h.craft == true end
IsPerson = function(h) return valid(h) and h.person == true end
IsBusy = function(h) return valid(h) and h.busy == true end
GetTeamNum = function(h) return valid(h) and h.team or -1 end
GetClassLabel = function(h) return valid(h) and (h.class or "wingman") or "" end
GetPlayerHandle = function() return objects.player end
GetCurrentCommand = function(h) return h.command or AiCommand.NONE end
GetCurrentWho = function(h) return h.target end
GetCommandableAttackPriority = function() return 1 end
SetCommand = function(h, command, _, target) h.command, h.target = command, target end
Stop = function(h) h.command, h.target = AiCommand.NONE, nil end
AllObjects = function() return iterator(worldObjects) end
GetDistance = function() return 0 end

local team = {
    teamNum = 1,
    faction = 1,
    Config = {
        autoManage = false,
        manageBase = false,
        manageTacticalOrders = false,
        manageSpecialCombat = true,
        customValue = 17,
    },
    SetConfig = function(self, key, value) self.Config[key] = value end,
}

local aiStub = {
    ActiveTeams = { [1] = team },
    Units = { [1] = { tug = "avhaul" } },
    AddObject = function() end,
    RefreshObjectCache = function() end,
    ReapplyNativeTactics = function() end,
    RemoveDead = function() end,
    TrySetCommand = function(h, command, _, target)
        h.command, h.target = command, target
        return true
    end,
    TryAttack = function(h, _, _, _) h.command = AiCommand.ATTACK; return true end,
}
function aiStub.ResetTeam()
    resetCalls = resetCalls + 1
    error("PlayerPilotMode must not reset the live team")
end

package.preload.aiCore = function() return aiStub end
package.preload.PersistentConfig = function()
    return { Settings = { PilotModeEnabled = false, AutoRepairWingmen = false, ScavengerAssistEnabled = false } }
end
PersistentConfig = require("PersistentConfig")

local player = { valid = true, alive = true, team = 1, craft = true, class = "wingman" }
local wingman = { valid = true, alive = true, team = 1, craft = true, class = "wingman" }
local target = { valid = true, alive = true, team = 0, craft = true, class = "turrettank" }
objects.player, objects.wingman, objects.target = player, wingman, target
worldObjects[1], worldObjects[2], worldObjects[3] = player, wingman, target

local PilotMode = assert(loadfile(source))()
local objectiveCalls = 0
local adapter = {
    profile = { autoManage = true, manageBase = true },
    shouldManageHandle = function(h) return h ~= player end,
    getObjectiveContext = function()
        objectiveCalls = objectiveCalls + 1
        return { key = "test", actions = { { id = "test-defend", command = "defend", target = target } } }
    end,
}

PilotMode.Initialize(adapter)
local originalTeam = aiStub.ActiveTeams[1]
PersistentConfig.Settings.PilotModeEnabled = true
PilotMode.Update()
assert(aiStub.ActiveTeams[1] == originalTeam, "enable replaced the live team")
assert(resetCalls == 0, "enable called ResetTeam")
assert(team.Config.autoManage == true and team.Config.manageBase == true, "enable did not apply profile")
assert(objectiveCalls > 0 and wingman.command == AiCommand.DEFEND, "objective action was not issued")

for _ = 1, 5 do
    PersistentConfig.Settings.PilotModeEnabled = false
    PilotMode.Update()
    PersistentConfig.Settings.PilotModeEnabled = true
    PilotMode.Update()
end
assert(aiStub.ActiveTeams[1] == originalTeam, "rapid toggle replaced the live team")
assert(resetCalls == 0, "rapid toggle reset a team")
assert(team.Config.autoManage == true, "rapid re-enable lost the profile")

PersistentConfig.Settings.PilotModeEnabled = false
PilotMode.Update()
assert(team.Config.autoManage == false and team.Config.manageBase == false and team.Config.customValue == 17,
    "disable did not restore the baseline config")
assert(buildCalls == 0 and resourceCalls == 0, "mode transition created resources")

PersistentConfig.Settings.PilotModeEnabled = true
PilotMode.Update()
local saved = PilotMode.Save()
saved.tugBuildCooldowns.test = 4.0
PersistentConfig.Settings.PilotModeEnabled = false
PilotMode.Initialize(adapter, saved)
assert(PersistentConfig.Settings.PilotModeEnabled == true, "save/load lost the enabled selection")
local restored = PilotMode.Save()
assert(restored.tugBuildCooldowns.test > 3.0, "save/load lost the tug build cooldown")
PilotMode.Update()
PersistentConfig.Settings.PilotModeEnabled = false
PilotMode.Update()
assert(team.Config.customValue == 17, "save/load lost the baseline config")
assert(resetCalls == 0, "save/load reset a team")

io.write("PlayerPilotMode checks passed\n")
