-- aiCore must never manage human teams or human-piloted craft, must not shadow engine
-- globals (SetAIP), and must serve every human player (co-op guests included).
local H = dofile("Tools/AiCoreTestHarness.lua")
local source = arg and arg[1] or "Scripts/aiCore.lua"

-- Use the real DiffUtils so DiffUtils.SetupTeams is covered.
package.preload.DiffUtils = nil
package.preload.exu = function() return exu end
package.path = "Scripts/?.lua;" .. package.path

-- Co-op stand-in: CRCoop reports which teams are human and which handles are players.
local coop = { network = false, teams = {}, players = {}, humanCraft = {} }
function coop.IsNetworkGame() return coop.network end
function coop.IsHumanTeam(t) return t >= 1 and t <= 4 end
function coop.ForEachHumanTeam(fn)
    for _, t in ipairs(coop.teams) do fn(t) end
end
function coop.ForEachPlayerHandle(fn)
    for _, p in ipairs(coop.players) do fn(p) end
end
function coop.IsHumanCraft(h) return coop.humanCraft[h] == true end
package.loaded.CRCoop = coop

local aiCore = H.load(source)
local check, handle = H.check, H.handle
aiCore.Units[1] = { recycler = "avrecy", factory = "avmuf", constructor = "avcnst", armory = "avslf",
    scavenger = "avscav", scout = "avfigh", turret = "avturr", pilot = "aspilo", tank = "avtank", soldier = "aspilo" }
aiCore.Units[2] = aiCore.Units[1]
aiCore.Units[3] = aiCore.Units[1]

-- SetAIP shadow: the engine global must survive, and the shim has a new name.
H.try("setaip", function()
    check("aiCore does not replace the engine's global SetAIP", SetAIP == H.engineSetAIP)
    check("the .aip shim is aiCore.SetStrategyFromAip (no aiCore.SetAIP)",
        type(aiCore.SetStrategyFromAip) == "function" and aiCore.SetAIP == nil)
    local t = aiCore.AddTeam(5, 1)
    check("SetStrategyFromAip maps the .aip name to an aiCore strategy",
        aiCore.SetStrategyFromAip("misn05.aip", 5) == true and t.baseStrategy == "Balanced")
    check("SetStrategyFromAip ignores teams aiCore does not run", aiCore.SetStrategyFromAip("misn05.aip", 12) == false)
    aiCore.ActiveTeams[5] = nil
end)

-- Which teams are human.
H.try("human teams", function()
    check("team 1 is always human; AI teams are not", aiCore.IsHumanTeam(1) and not aiCore.IsHumanTeam(5)
        and not aiCore.IsHumanTeam(3))
    coop.network, coop.teams = true, { 1, 3 }
    check("co-op teams come from the CRCoop human set", aiCore.IsHumanTeam(3) and not aiCore.IsHumanTeam(2)
        and not aiCore.IsHumanTeam(4) and not aiCore.IsHumanTeam(5))
    coop.network, coop.teams = false, {}
    aiCore.SetHumanTeam(6, true)
    check("a mission can mark a team human explicitly", aiCore.IsHumanTeam(6))
    aiCore.SetHumanTeam(6, nil)
end)

-- Defaults: human teams are unmanaged from creation, AI teams are not.
H.try("defaults", function()
    local human = aiCore.AddTeam(1, 1)
    local ai = aiCore.AddTeam(5, 1)
    local off = true
    for _, key in ipairs({ "manageBase", "autoBuild", "manageConstructor", "manageFactories",
        "manageTacticalOrders", "manageSpecialCombat" }) do
        if human.Config[key] ~= false then off = false end
    end
    check("a human team starts with every base/tactics manager off", off)
    check("an AI team keeps the normal defaults", ai.Config.manageBase and ai.Config.manageFactories
        and ai.Config.manageTacticalOrders and ai.Config.manageSpecialCombat and ai.Config.autoBuild)
    aiCore.ActiveTeams[1], aiCore.ActiveTeams[5] = nil, nil
end)

-- DiffUtils.SetupTeams applies the same defaults without the mission asking.
H.try("setupteams", function()
    local DiffUtils = require("DiffUtils")
    local player, enemy = DiffUtils.SetupTeams(1, 2, 5)
    check("SetupTeams leaves team 1 unmanaged", player.Config.manageBase == false
        and player.Config.manageFactories == false and player.Config.manageTacticalOrders == false
        and player.Config.manageSpecialCombat == false)
    check("SetupTeams keeps the enemy team managed", enemy.Config.manageBase ~= false)
    player:SetConfig("manageFactories", true)
    check("an explicit SetConfig afterwards is an opt-in that still works", player.Config.manageFactories == true)
    aiCore.ActiveTeams = {}
end)

-- Human-piloted craft are untouchable, on any team.
H.try("human craft", function()
    local mine = handle { team = 1, odf = "avtank", class = "wingman", craft = true }
    local guest = handle { team = 3, odf = "avtank", class = "wingman", craft = true }
    local stolen = handle { team = 5, odf = "avtank", class = "wingman", craft = true }
    local npc = handle { team = 5, odf = "avtank", class = "wingman", craft = true }
    H.playerHandle = mine
    coop.humanCraft[guest] = true
    IsPlayer = function(h) return h == stolen end
    check("IsHumanCraft covers the local player, CRCoop players and IsPlayer",
        aiCore.IsHumanCraft(mine) and aiCore.IsHumanCraft(guest) and aiCore.IsHumanCraft(stolen)
        and not aiCore.IsHumanCraft(npc))
    H.commands = {}
    check("no command is issued to a human-piloted craft",
        aiCore.TrySetCommand(guest, AiCommand.GO, 1, nil, { x = 1, y = 0, z = 0 }) == false
        and aiCore.TryAttack(stolen, npc, 1) == false and #H.commands == 0)
    check("other craft still receive commands", aiCore.TrySetCommand(npc, AiCommand.GO, 1, nil, { x = 1, y = 0, z = 0 }))
    check("aiCore.GetHumanPlayers lists every human", #aiCore.GetHumanPlayers() >= 1)
    IsPlayer = nil
    H.playerHandle = nil
    coop.humanCraft = {}
end)

-- Bootstrap (misn03 calls it unfiltered) must not register humans' craft.
H.try("bootstrap", function()
    H.objects = {}
    local team = aiCore.AddTeam(3, 1)
    local hostPlayer = H.addObject { team = 1, odf = "avtank", class = "wingman", craft = true }
    local guestPlayer = H.addObject { team = 3, odf = "avtank", class = "wingman", craft = true }
    local guestWingman = H.addObject { team = 3, odf = "avfigh", class = "wingman", craft = true }
    H.playerHandle = hostPlayer
    coop.humanCraft[guestPlayer] = true
    aiCore.AddTeam(1, 1)
    aiCore.Bootstrap()
    local function tracked(t, h) return t and t.trackedSet and t.trackedSet[h] end
    check("Bootstrap does not register the host or a guest's craft",
        not tracked(aiCore.ActiveTeams[1], hostPlayer) and not tracked(aiCore.ActiveTeams[3], guestPlayer))
    check("Bootstrap still registers the guests' wingmen (for wingman support)",
        tracked(aiCore.ActiveTeams[3], guestWingman) == true)
    H.objects, H.playerHandle, coop.humanCraft = {}, nil, {}
    aiCore.ActiveTeams = {}
end)

-- Team:Update runs no base/tactics/special managers on a human team; opt-ins keep working.
H.try("update gating", function()
    local human = aiCore.AddTeam(1, 1)
    local calls = {}
    local function spy(name) return function() calls[name] = (calls[name] or 0) + 1 end end
    human.weaponMgr.Update, human.cloakMgr.Update, human.howitzerMgr.Update = spy("weapon"), spy("cloak"), spy("how")
    human.minelayerMgr.Update, human.apcMgr.Update, human.depotMgr.Update = spy("mine"), spy("apc"), spy("depot")
    for _ = 1, 8 do
        H.now = H.now + 0.1
        pcall(human.Update, human)
    end
    check("a human team runs no weapon/cloak/howitzer/minelayer/APC managers",
        not (calls.weapon or calls.cloak or calls.how or calls.mine or calls.apc))
    check("DepotManager keeps servicing units on a human team", (calls.depot or 0) > 0)
    human:SetConfig("manageSpecialCombat", true)
    for _ = 1, 8 do
        H.now = H.now + 0.1
        pcall(human.Update, human)
    end
    check("an explicit opt-in (manageSpecialCombat) works", (calls.weapon or 0) > 0)
    aiCore.ActiveTeams = {}
end)

-- Howitzers on a human team never get AI fire missions, even when tactical orders are opted in.
H.try("howitzer", function()
    local human = aiCore.AddTeam(1, 1)
    human.Config.manageTacticalOrders = true
    local mgr = human.howitzerMgr
    local list = {}
    for i = 1, 3 do list[i] = handle { team = 1, odf = "avartl", class = "howitzer", craft = true } end
    mgr.howitzers = list
    mgr.squads = { list }
    H.objects = {}
    H.addObject { team = 5, odf = "svrecy", class = "recycler", building = true, pos = { x = 900, y = 0, z = 0 } }
    aiCore.ResetObjectCacheTracking()
    for _, o in ipairs(H.objects) do aiCore.TrackWorldObject(o) end
    aiCore.RefreshObjectCache(true)
    H.commands = {}
    mgr:UpdateSquadOrders()
    check("player howitzer squads are not given GO/ATTACK orders", #H.commands == 0)
    H.objects = {}
    aiCore.ActiveTeams = {}
end)

-- Co-op guests get a team object, so wingman support and rescue serve their units.
H.try("guest support", function()
    coop.network, coop.teams = true, { 1, 3 }
    local host = H.addObject { team = 1, odf = "avtank", class = "wingman", craft = true }
    local guest = H.addObject { team = 3, odf = "aspilo", class = "person", person = true }
    local guestWing = H.addObject { team = 3, odf = "avfigh", class = "wingman", craft = true, health = 0.1,
        pos = { x = 10, y = 0, z = 0 } }
    H.playerHandle = host
    coop.players = { host, guest }
    coop.humanCraft[host], coop.humanCraft[guest] = true, true
    local base = aiCore.AddTeam(1, 1)
    base.Config.autoRepairWingmen = true
    aiCore.EnsureHumanTeams()
    local gt = aiCore.ActiveTeams[3]
    check("a team object is created for the guest's human team", gt ~= nil and gt.humanTeam == true)
    check("the guest team copies wingman autorepair and stays unmanaged",
        gt.Config.autoRepairWingmen == true and gt.Config.manageBase == false)
    check("the guest's wingman is registered with the wingman manager", gt.wingmanMgr.wingmen[guestWing] ~= nil)
    gt.Config.autoRescue = true
    gt.combatUnits = { guestWing }
    H.commands = {}
    gt:UpdateRescue()
    check("auto-rescue picks up a guest who is on foot",
        #H.commands == 1 and H.commands[1].command == AiCommand.RESCUE and H.commands[1].target == guest)
    H.objects, H.playerHandle, coop.humanCraft, coop.players = {}, nil, {}, {}
    coop.network, coop.teams = false, {}
    aiCore.ActiveTeams = {}
end)

H.finish("aiCore human-team")
