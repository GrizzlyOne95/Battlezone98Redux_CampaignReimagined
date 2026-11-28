-- Execute misn17cr's N64 Pilot Mode branch (PilotUpdate/PilotAddObject) with
-- stubbed natives: start orders, the 20 s wingman attack timer, the recycler
-- and factory queues, the constructor's facility table, the factory fail
-- condition, adoption on enable and off/on cycles.
local file = assert(io.open("Scripts/misn17cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("(local PILOT_RESERVE.-)\n%-%- CR pilot mode <<"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local now, scrap, enabled = 0, 100, true
local pilots, topups = 0, 0
local objs, built, orders, failed = {}, {}, {}, 0
local dists, nearestEnemy = {}, nil
local function obj(name, odf, t)
    objs[name] = { odf = odf, team = t or 1, alive = true, deployed = false, busy = false, cmd = 0 }
    return name
end
local player = obj("player", "avhover")
local rec = obj("avrecy18_recycler", "avrecy")
local fact = obj("avmuf0_factory", "avmuf")
local wing = { obj("avtank134_wingman", "avtank"), obj("avltnk134_wingman", "avltnk"),
               obj("avfigh18_wingman", "avfigh"), obj("avfigh19_wingman", "avfigh") }
obj("eggeizr1133_geyser", "eggeizr1", 0); obj("eggeizr1132_geyser", "eggeizr1", 0)
obj("factorynav", "apcamr")
local towers = {}
for i = 1, 7 do towers[i] = obj("tower" .. i, "hbptow", 2) end
local env = setmetatable({}, { __index = _G })
env.M = { missionstart = true, avrec = rec, factorynav = "factorynav", missionfail = false, missionwon = false }
for i = 1, 7 do env.M["tower" .. i] = towers[i] end
env.AiCommand = { NONE = 0, GO = 3, RECYCLE = 12 }
env.GetTime = function() return now end
env.GetPlayerHandle = function() return player end
env.GetHandle = function(n) return objs[n] and n or nil end
env.IsAlive = function(h) return objs[h] ~= nil and objs[h].alive end
env.IsValid = env.IsAlive
env.IsDeployed = function(h) return objs[h].deployed end
env.IsBusy = function(h) return objs[h].busy end
env.IsOdf = function(h, odf) return objs[h].odf == odf end
env.GetTeamNum = function(h) return objs[h].team end
env.GetScrap = function() return scrap end
env.GetPilot = function() return pilots end
env.AddScrap = function(_, n) scrap = scrap + n; topups = topups + 1 end
env.AddPilot = function(_, n) pilots = pilots + n end
env.GetHealth = function() return 1 end
env.GetAmmo = function() return 1 end
env.GetCurrentCommand = function(h) return objs[h].cmd end
env.GetCurrentWho = function() return nil end
env.GetDistance = function(a, b) return dists[a .. ":" .. b] or 10000 end
env.AllCraft = function() return function() return nil end end
env.AllObjects = function()
    local names = {}
    for k, o in pairs(objs) do if o.alive then names[#names + 1] = k end end
    table.sort(names)
    local i = 0
    return function() i = i + 1; return names[i] end
end
env.SetCommand = function(h, cmd, pri, who) orders[#orders + 1] = { "cmd", h, cmd } end
env.SetUserTarget = function(h) orders[#orders + 1] = { "target", h } end
env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
env.GetTerrainHeightAndNormal = function() return 7 end
env.Goto = function(h, t) orders[#orders + 1] = { "go_to", h, t }; objs[h].cmd = 3 end
env.Follow = function(h, t) orders[#orders + 1] = { "follow", h, t } end
env.Attack = function(h, t) orders[#orders + 1] = { "attack", h, t } end
env.Dropoff = function(h, t) orders[#orders + 1] = { "dropoff", h, t } end
env.Build = function(h, odf) built[#built + 1] = odf; objs[h].busy = true end
env.FailMission = function() failed = failed + 1 end
env.NearestEnemy = function() return nearestEnemy end
env.Distance = function(a, b) return env.GetDistance(a, b) end
local initArgs
env.PlayerPilotMode = { IsEnabled = function() return enabled end,
    Initialize = function(adapter, saved) initArgs = { adapter = adapter, saved = saved } end }
env.PilotBranch = assert(loadfile("Scripts/CRPilotBranch.lua"))()
for _, fn in pairs(env.PilotBranch) do if type(fn) == "function" then setfenv(fn, env) end end
local chunk = assert(loadstring("local M, PlayerPilotMode, PilotBranch = M, PlayerPilotMode, PilotBranch\n" .. block ..
    "\nreturn { update = PilotUpdate, add = PilotAddObject, init = InitializePilotMode }"))
setfenv(chunk, env)
local api = chunk()
local M = env.M
local function spawn(name, odf) obj(name, odf); return api.add(name) end
local function count(kind, who, target)
    local n = 0
    for _, o in ipairs(orders) do
        if o[1] == kind and (who == nil or o[2] == who) and (target == nil or o[3] == target) then n = n + 1 end
    end
    return n
end
local function lastOrder(kind) for i = #orders, 1, -1 do if orders[i][1] == kind then return orders[i] end end end
local function builtCount(odf) local n = 0 for _, b in ipairs(built) do if b == odf then n = n + 1 end end return n end

-- Disabled: nothing is consumed or ordered.
enabled = false
spawn("off1", "avscav")
check(M.pilot == nil and #orders == 0 and #built == 0, "disabled: objects not consumed")
enabled = true
obj("enemy1", "avtank", 5); api.add("enemy1")
check(#orders == 0 and (M.pilot == nil or M.pilot.scav1 == nil), "other teams ignored")
M.pilot = nil
objs.off1 = nil

-- Initialize hands PlayerPilotMode a scripted adapter and the saved state.
M.playerPilotModeState = { baselineConfig = 1 }
api.init()
check(initArgs.adapter.scripted == true and initArgs.adapter.update == api.update
    and initArgs.saved == M.playerPilotModeState, "scripted adapter wired with saved state")

-- Adoption on enable registers existing units once (wingmen follow once more
-- through the tank slot only for the avtank).
initArgs.adapter.enable()
initArgs.adapter.enable()
check(count("follow", wing[1]) == 1, "double enable: the avtank is adopted once")
check(M.pilot.tank1 == wing[1], "adopted avtank fills slot 1")
orders = {}

-- Before the mission start nothing happens.
M.missionstart = false
api.update()
check(#orders == 0 and #built == 0, "no orders before missionstart")
M.missionstart = true

-- Start (C 414-424): user target nav 18, producers to their geysers, wingmen follow.
api.update()
check(count("target") == 1 and lastOrder("target")[2] == "factorynav", "SetUserTarget(factorynav)")
check(count("go_to", rec, "eggeizr1133_geyser") == 1, "recycler sent to label 12 geyser")
check(count("go_to", fact, "eggeizr1132_geyser") == 1, "factory sent to label 11 geyser")
for _, w in ipairs(wing) do check(count("follow", w, player) == 1, "wingman follows the player: " .. w) end
check(M.pilot.tank2 == wing[2], "avltnk is the second tank slot")
check(#built == 0, "undeployed producers build nothing")

-- Idle producer: re-sent after 6 s.
objs[rec].cmd = 0; objs[fact].cmd = 0
local gotos = count("go_to")
now = 1; api.update(); now = 8; api.update()
check(count("go_to") == gotos + 2, "undeployed producers re-sent to their geysers")
objs[rec].deployed, objs[fact].deployed = true, true

-- Recycler queue: scavengers until two, then the constructor.
scrap = 2
now = 9; api.update()
check(built[1] == "avscav" and scrap >= 4 and pilots == 1, "first scavenger after the scrap/pilot top-up")
scrap = 100
objs[rec].busy = false; spawn("scav1", "avscav"); now = 10; api.update()
check(built[2] == "avscav", "second scavenger")
objs[rec].busy = false; spawn("scav2", "avscav"); now = 11; api.update()
check(built[3] == "avcnst" and #built == 3, "constructor after two scavengers: " .. table.concat(built, ","))
objs[rec].busy = false
scrap = 11; now = 12; api.update()
check(#built == 3, "constructor waits for 12 scrap")
scrap = 100; spawn("cnst", "avcnst"); now = 13; api.update()
check(M.pilot.cnst == "cnst" and builtCount("avcnst") == 1, "constructor is not rebuilt while alive")

-- Facility table: the constructor builds each missing facility in order and drops it off.
check(built[4] == "abhang" and M.pilot.dropPending and M.pilot.facilityPending, "hangar first")
now = 15; api.update()
check(lastOrder("dropoff")[2] == "cnst" and lastOrder("dropoff")[3].x == 1818 and lastOrder("dropoff")[3].z == 99499,
    "hangar drop-off position")
objs.cnst.busy = false
now = 16; api.update()
check(#built == 4, "no second facility while the first is pending")
spawn("hangar1", "abhang"); check(M.pilot.hangar == "hangar1" and not M.pilot.facilityPending, "hangar fills its slot")
local plan = { { "absupp", 1769, 99349 }, { "abspow", 1808, 99330 }, { "abtowe", 1836, 99288 }, { "abtowe", 1852, 99372 },
    { "abspow", 1830, 99565 }, { "abtowe", 1766, 99539 }, { "abtowe", 1875, 99530 } }
for i, f in ipairs(plan) do
    objs.cnst.busy = false
    now = now + 1; api.update()
    check(built[#built] == f[1], "facility " .. i .. " is " .. f[1] .. " got " .. tostring(built[#built]))
    now = now + 1; api.update()
    local d = lastOrder("dropoff")
    check(d[3].x == f[2] and d[3].z == f[3], "facility " .. i .. " drop-off position")
    spawn("fac" .. i, f[1])
end
local total = #built
objs.cnst.busy = false
now = now + 1; api.update()
check(#built == total, "full base: nothing more built")
check(builtCount("abtowe") == 4 and builtCount("abspow") == 2, "two power plants and four towers")

-- A destroyed tower is rebuilt where it was missing.
objs.fac3.alive = false
now = now + 1; api.update()
check(built[#built] == "abtowe", "destroyed tower rebuilt")
now = now + 1; api.update(); spawn("fac3b", "abtowe"); objs.cnst.busy = false

-- Tank top-up: avtank when a tank slot is empty and nothing else is pending.
objs[wing[1]].alive = false
local tanks = builtCount("avtank")
now = now + 1; api.update()
check(builtCount("avtank") == tanks + 1, "factory rebuilds the lost tank")
objs[fact].busy = false
spawn("newtank", "avtank")
check(M.pilot.tank1 == "newtank" and count("follow", "newtank", player) == 1, "rebuilt tank takes the slot and follows")
now = now + 1; api.update()
check(builtCount("avtank") == tanks + 1, "no further tank once both slots are filled")

-- Wingman timer: first attack at +20 s from start, enemy within 120 m wins, else the first standing tower.
objs[wing[3]].cmd = 0
now = 21 + 20 -- past the start timer
orders = {}
api.update()
local expect = count("attack", wing[2], "tower1")
check(expect == 1 and count("attack", wing[3], "tower1") == 1 and count("attack", wing[4], "tower1") == 1,
    "no enemy near: wingmen attack the first standing tower")
check(count("attack", wing[1]) == 0, "dead wingman gets no order")
local nowAt = now
api.update()
check(count("attack") == 3, "the timer fires once per 20 s")
obj("enemy2", "avfigh", 2); nearestEnemy = "enemy2"; dists["player:enemy2"] = 100
now = nowAt + 20; orders = {}; api.update()
check(count("attack", wing[2], "enemy2") == 1 and count("attack", wing[3], "enemy2") == 1, "enemy within 120 m is attacked")
dists["player:enemy2"] = 150
now = now + 20; orders = {}; api.update()
check(count("attack", wing[3], "tower1") == 1, "enemy beyond 120 m is ignored")
objs.tower1.alive = false
now = now + 20; orders = {}; api.update()
check(count("attack", wing[3], "tower2") == 1, "next standing tower in order")
for i = 2, 7 do objs["tower" .. i].alive = false end
now = now + 20; orders = {}; api.update()
check(count("attack") == 0 and count("follow", wing[3], player) == 1, "no tower left: wingmen follow")

-- Off/on cycles issue no duplicate placement orders.
local builtBefore, dropBefore = #built, count("dropoff")
initArgs.adapter.disable()
initArgs.adapter.enable()
orders = {}
now = now + 1; api.update()
check(#built == builtBefore and count("dropoff") == 0 and count("go_to") == 0, "off/on cycle repeats no builds or placement orders")
check(count("follow", "newtank") == 0 and count("follow", "scav1") == 0, "off/on cycle re-adopts nothing")

-- The factory lost is the extra fail.
objs[fact].alive = false
now = now + 1; api.update(); now = now + 1; api.update()
check(failed == 1 and env.M.missionfail == true, "factory lost fails the mission once")

print("misn17 pilot mode: " .. checks .. " checks passed")
