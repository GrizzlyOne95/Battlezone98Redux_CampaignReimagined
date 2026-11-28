-- Execute misns7cr's N64 Pilot Mode branch (Pilot.Update/Pilot.Add) with stubbed natives: APC follow,
-- engineer pickup chain, the pilot-only engineer fail, restored recycler/factory follows, geyser sends and
-- re-sends at the supply cache, the tank/fighter queue, 30 s regroup, adoption and disable/enable cycles.
local file = assert(io.open("Scripts/misns7cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("%-%- CR pilot mode >>\n(.-)\n%-%- CR pilot mode <<"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local now, scrap, pilots = 0, 100, 5
local objs, built, orders, fails = {}, {}, {}, {}
local function obj(name, odf, t, x)
    objs[name] = { odf = odf, team = t or 1, alive = true, deployed = false, busy = false, cmd = 0, x = x or 0 }
    return name
end
local player = obj("player", "svtank", 1, 0)
local apc = obj("svapc", "svap7", 1, 0)
local rec0 = obj("svrecycle", "svrecy", 0, 500)
local muf0 = obj("svmuf", "svmuf", 0, 600)
local hut = obj("supply", "sbhang", 0, 2000)
local recGeyser = obj("eggeizr13_geyser", "eggeizr1", 0, 2040)
local mufGeyser = obj("con_geyser", "eggeizr1", 0, 2030)
local con1, con2, con3 = obj("con1", "sssold", 1, 300), obj("con2", "sssold", 1, 320), obj("con3", "sssold", 1, 340)

local env = setmetatable({}, { __index = _G })
env.M = { start_done = true, apc = apc, svrecycle = rec0, svmuf = muf0, supply = hut }
env.AiCommand = { NONE = 0, GO = 3, FOLLOW = 5 }
env.GetTime = function() return now end
env.GetPlayerHandle = function() return player end
env.GetHandle = function(l) return objs[l] and l or nil end
env.IsValid = function(h) return objs[h] ~= nil and objs[h].alive end
env.IsAlive = function(h) return objs[h] ~= nil and objs[h].alive end
env.IsDeployed = function(h) return objs[h].deployed end
env.IsBusy = function(h) return objs[h].busy end
env.IsOdf = function(h, odf) return objs[h].odf == odf end
env.GetTeamNum = function(h) return objs[h].team end
env.GetScrap = function() return scrap end
env.GetPilot = function() return pilots end
env.GetDistance = function(a, b) return math.abs(objs[a].x - objs[b].x) end
env.GetCurrentCommand = function(h) return objs[h].cmd end
env.GetCurrentWho = function() return nil end
env.AllCraft = function() return function() return nil end end
env.AllObjects = function()
    local names = {}
    for k, o in pairs(objs) do if o.alive then names[#names + 1] = k end end
    table.sort(names)
    local i = 0
    return function() i = i + 1; return names[i] end
end
env.SetCommand = function() end
env.Goto = function(h, t) orders[#orders + 1] = { "go_to", h, t }; objs[h].cmd = 3 end
env.Follow = function(h, t) orders[#orders + 1] = { "follow", h, t }; objs[h].cmd = 5 end
env.Build = function(h, odf) built[#built + 1] = odf .. "@" .. h; objs[h].busy = true end
env.FailMission = function(_, des) fails[#fails + 1] = des end
local PilotBranch = assert(loadfile("Scripts/CRPilotBranch.lua"))()
for _, f in pairs(PilotBranch) do if type(f) == "function" then setfenv(f, env) end end
local chunk = assert(loadstring("local M = M\n" .. block .. "\nreturn PilotAdapter, Pilot"))
setfenv(chunk, env)
local adapter, Pilot = chunk()
Pilot.B = PilotBranch
check(adapter.update and adapter.addObject and adapter.enable and adapter.disable, "adapter has all four hooks")
local enabled = true
local function step(dt) now = now + (dt or 1); adapter.update() end
local function spawn(name, odf, team) obj(name, odf, team); adapter.addObject(name) end
local function count(kind, a, b)
    local c = 0
    for _, o in ipairs(orders) do
        if o[1] == kind and (a == nil or o[2] == a) and (b == nil or o[3] == b) then c = c + 1 end
    end
    return c
end
local function builds(prefix)
    local c = 0
    for _, b in ipairs(built) do if b:find(prefix, 1, true) == 1 then c = c + 1 end end
    return c
end
local M = env.M

-- Start: the APC follows the player, once.
step(1)
check(count("follow", apc, player) == 1, "APC follows the player from the start")
local n = #orders; step(1)
check(#orders == n, "start orders run once")
check(#built == 0 and #fails == 0, "no builds or fails yet")
step(31)
check(count("follow", apc, player) == 2, "30 s regroup follows the APC again")
check(count("follow", rec0) == 0 and count("follow", muf0) == 0, "neutral recycler and factory are not ordered")

-- Jail down: the APC drives to engineer 1, then 2, then 3.
M.con1, M.con2, M.con3 = con1, con2, con3
M.jail_unit_spawn = true
step(1)
check(count("go_to", apc, con1) == 1, "APC drives to the first engineer")
step(31)
check(count("follow", apc, player) == 2, "APC keeps its pickup order while engineers are loading")
M.con1_safe = true; objs[con1].alive = false
step(1)
check(count("go_to", apc, con2) == 1, "APC drives to the second engineer after the first pickup")
step(1)
check(count("go_to", apc, con2) == 1, "pickup order is sent once")
M.con2_safe = true; objs[con2].alive = false
step(1)
check(count("go_to", apc, con3) == 1, "APC drives to the third engineer")
check(#fails == 0, "delivered engineers do not fail the mission")
M.con3_safe = true; objs[con3].alive = false
M.first_message_done = true
step(1)
check(count("follow", apc, player) == 3, "APC follows the player again once every engineer is aboard")
check(#fails == 0, "no fail after three deliveries")

-- Recycler restored: it follows the player (the outpost is not up).
local rec = obj("svrecy_new", "svrecy", 1, 700)
M.svrecycle, M.camera_off_recycle = rec, true
step(1)
check(count("follow", rec, player) == 1, "restored recycler follows the player")
step(31)
check(count("follow", rec, player) == 2, "restored recycler is included in the 30 s regroup")

-- Factory restored: the three-frame follow request fires on its last frame.
local muf = obj("svmuf_new", "svmuf", 1, 800)
M.svmuf, M.camera_off_muf = muf, true
step(1)
check(count("follow", muf, player) == 0, "follow request not consumed on its first frame")
step(1)
check(count("follow", muf, player) == 0, "nor on its second frame")
step(1)
check(count("follow", muf, player) == 1, "restored factory follows the player on the request's third frame")
check(builds("svtank") == 0 and builds("svfigh") == 0, "nothing builds before the supply cache")

-- Supply cache stands: both producers are sent to their geysers, the APC follows.
M.supplies_spawned = true
step(1)
check(count("go_to", muf, mufGeyser) == 1 and count("go_to", rec, recGeyser) == 1, "producers sent to the geysers by the hangar")
local f = count("follow", muf)
step(31)
local fr = count("follow", rec)
step(31)
check(count("follow", muf) == f and count("follow", rec) == fr, "producers leave the regroup after the cache")
-- Re-send after 6 s when undeployed and not underway.
objs[muf].cmd = 0
step(1); step(7)
check(count("go_to", muf, mufGeyser) == 2, "factory re-sent to its geyser after 6 s")

-- Queue: tanks first (8 scrap + pilot), two at most; then fighters.
objs[muf].deployed, objs[rec].deployed = true, true
objs[muf].busy, objs[rec].busy = false, false
step(1)
check(builds("svtank@" .. muf) == 1, "factory builds a tank")
step(1)
check(builds("svtank@" .. muf) == 1, "no second order while the factory is busy")
objs[muf].busy = false; step(1)
check(builds("svtank@" .. muf) == 2, "second tank")
objs[muf].busy = false; step(1)
check(builds("svtank@" .. muf) == 2 and builds("svfigh@" .. rec) == 1, "no third tank; the recycler builds a fighter")
objs[rec].busy = false; step(1)
objs[rec].busy = false; step(1)
check(builds("svfigh@" .. rec) == 2, "two fighters at most")
pilots = 0; scrap = 0
check(builds("svtank@" .. muf) == 2, "queue idle")

-- New units follow the player, no double registration.
spawn("tankA", "svtank", 1)
check(count("follow", "tankA", player) == 1, "new tank follows the player")
adapter.addObject("tankA")
check(count("follow", "tankA", player) == 1, "no double registration of a tank")
spawn("fighterA", "svfigh", 1)
check(count("follow", "fighterA", player) == 1, "new fighter follows the player")
spawn("foe", "bvraz", 5)
check(count("follow", "foe") == 0, "other teams are ignored")

-- Disable/enable cycles add no duplicate registration orders.
adapter.disable()
local after = #orders
adapter.enable()
local afterEnable = #orders
adapter.disable(); adapter.enable()
check(#orders == afterEnable, "disable/enable cycle adds no duplicate follow orders")
check(count("follow", "tankA", player) == 1 and count("follow", "fighterA", player) == 1, "adopted units are not re-followed")

-- Pilot-only fail: an engineer seen alive and then lost before pickup. Fresh state and fresh engineers.
env.M = nil
M = { start_done = true, apc = apc, svrecycle = rec0, svmuf = muf0, supply = hut, jail_unit_spawn = true }
-- rebind the region's M: re-run the block against the new table
local chunk2 = assert(loadstring("local M = M\n" .. block .. "\nreturn PilotAdapter, Pilot"))
env.M = M
setfenv(chunk2, env)
local adapter2, Pilot2 = chunk2()
Pilot2.B = PilotBranch
local e1, e2, e3 = obj("e1", "sssold", 1, 300), obj("e2", "sssold", 1, 320), obj("e3", "sssold", 1, 340)
M.con1, M.con2, M.con3 = e1, e2, e3
fails = {}
objs[e2].alive = false -- lost before the mode saw it alive
adapter2.update(); adapter2.update()
check(#fails == 0, "an engineer already dead when the mode turns on does not fail at once")
objs[e2].alive = true
now = now + 1; adapter2.update()
objs[e1].alive = false
now = now + 1; adapter2.update()
check(#fails == 1 and fails[1] == "misns7f1.des", "losing an engineer seen alive fails the mission")
now = now + 1; adapter2.update()
check(#fails == 1 and M.game_over, "the fail is raised once")
print("misns7 Pilot Mode branch checks passed: " .. checks)
