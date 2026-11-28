-- Execute misns5cr's N64 Pilot Mode branch (the "-- CR pilot mode" region) with stubbed natives: intro-end
-- follow and position cache, geyser re-send, build queue order, constructor rebuilds, ammo pod, constructor-lost
-- fail, adoption on enable and off/on cycles.
local file = assert(io.open("Scripts/misns5cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("\n(%-%- CR pilot mode >>\n.-\n%-%- CR pilot mode <<)\n"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local now, scrap, pilots = 0, 100, 5
local objs, built, orders, fails = {}, {}, {}, {}
local function obj(name, odf, t, x, z)
    objs[name] = { odf = odf, team = t or 1, alive = true, deployed = false, busy = false, health = 1, ammo = 1,
        cmd = 0, pos = { x = x or 0, y = 5, z = z or 0 } }
    return name
end
local player = obj("player", "svtank")
local rec = obj("svrecy0_recycler", "svrecy"); local muf = obj("svmuf0_factory", "svmuf")
local g1, g2 = obj("eggeizr11_geyser", "eggeizr1", 0), obj("eggeizr12_geyser", "eggeizr1", 0)
obj("svltnk0_wingman", "svltnk"); obj("svtank59_wingman", "svtank"); obj("svtank2_wingman", "svtank")
obj("svscav1_scavenger", "svscav"); obj("svscav2_scavenger", "svscav")
for i, l in ipairs({ "sblpow2_powerplant", "sblpow3_powerplant", "sblpow4_powerplant" }) do obj(l, "sblpow", 1, 100 * i, 50) end
for i, l in ipairs({ "sbtowe0_turret", "sbtowe1_turret", "sbtowe2_turret" }) do obj(l, "sbtowe", 1, 100 * i, 80) end

local enabled = true
local env = setmetatable({}, { __index = _G })
env.M = { start_done = true, camera1 = true, recy = rec, geyser1 = nil, geyser2 = nil }
env.AiCommand = { NONE = 0, GO = 3 }
env.GetTime = function() return now end
env.GetPlayerHandle = function() return player end
env.GetHandle = function(l) return objs[l] and objs[l].alive and l or nil end
env.IsAlive = function(h) return objs[h] ~= nil and objs[h].alive end
env.IsValid = env.IsAlive
env.IsDeployed = function(h) return objs[h].deployed end
env.IsBusy = function(h) return objs[h].busy end
env.IsOdf = function(h, odf) return objs[h].odf == odf end
env.GetTeamNum = function(h) return objs[h].team end
env.GetHealth = function(h) return objs[h].health end
env.GetAmmo = function(h) return objs[h].ammo end
env.GetScrap = function() return scrap end
env.AddScrap = function(_, n) scrap = scrap + n end
env.GetPilot = function() return pilots end
env.AddPilot = function(_, n) pilots = pilots + n end
env.GetPosition = function(h) return objs[h].pos end
env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
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
env.Follow = function(h, t) orders[#orders + 1] = { "follow", h, t } end
env.Dropoff = function(h, pos) orders[#orders + 1] = { "dropoff", h, pos } end
env.Build = function(h, odf) built[#built + 1] = odf; objs[h].busy = true end
env.BuildAt = function(h, odf, t) built[#built + 1] = odf .. "@" .. t; objs[h].busy = true end
env.FailMission = function(when, des) fails[#fails + 1] = { when, des } end
local branchChunk = assert(loadfile("Scripts/CRPilotBranch.lua"))
setfenv(branchChunk, env)
local Branch = branchChunk()
env.require = function(name) assert(name == "CRPilotBranch", name); return Branch end
local chunk = assert(loadstring("local M = M\n" .. block .. "\nreturn Pilot"))
setfenv(chunk, env)
local Pilot = chunk()
local adapter = { enable = Pilot.Enable, disable = Pilot.Disable }
local function spawn(name, odf, x, z) obj(name, odf, 1, x, z); if enabled then Pilot.AddObject(name) end end
local function count(kind, who)
    local n = 0
    for _, o in ipairs(orders) do if o[1] == kind and (who == nil or o[2] == who) then n = n + 1 end end
    return n
end
local before
local function finish(h) objs[h].busy = false end

-- Adopt on enable: the pre-placed units are claimed once; nothing registers twice.
adapter.enable()
local P = env.M.pilot
check(P.tank[1] == "svltnk0_wingman" and P.tank[2] == "svtank59_wingman", "tank slots are labels 27 and 13")
check(not P.tank[3], "the third svtank (label 1) is not an N64 slot")
check(P.scav[1] == "svscav1_scavenger" and P.scav[2] == "svscav2_scavenger", "scavenger slots")
adapter.enable()
check(#orders == 0, "enable adopts without issuing any order")

-- During the intro nothing follows or builds, the base is not cached yet.
Pilot.Update()
check(#orders == 0 and #built == 0 and not P.started, "intro: no orders, no builds")

-- Intro ends: the two starting tanks follow, six positions are cached.
env.M.camera1 = false
env.M.muf, env.M.geyser1, env.M.geyser2 = muf, g1, g2
now = 1; Pilot.Update()
check(count("follow") == 2 and count("follow", "svltnk0_wingman") == 1 and count("follow", "svtank59_wingman") == 1,
    "the two starting tanks follow")
check(P.pos[1].x == 100 and P.pos[6].x == 300 and P.pos[6].z == 80 and not P.pos[7], "six base positions cached")
now = 2; Pilot.Update()
check(count("follow") == 2, "no second follow right away (30 s timer)")

-- Undeployed producers are re-sent to their geysers after 6 s.
now = 4; Pilot.Update(); now = 10; Pilot.Update()
local function sentTo(h, g)
    for _, o in ipairs(orders) do if o[1] == "go_to" and o[2] == h and o[3] == g then return true end end
end
check(sentTo(rec, g1) and count("go_to", rec) == 1, "recycler re-sent to geyser 1")
check(sentTo(muf, g2) and count("go_to", muf) == 1, "factory re-sent to geyser 2")
local sent = count("go_to")
now = 11; Pilot.Update()
check(count("go_to") == sent, "go_to is not repeated while the command is GO")

-- Queue: deployed with a full roster, the recycler builds the constructor first (8 scrap).
objs[rec].deployed, objs[muf].deployed = true, true
now = 12; Pilot.Update()
check(built[#built] == "svcnst", "constructor built when none is alive")
spawn("cnst", "svcnst"); finish(rec)
check(P.cnst == "cnst", "constructor cached")
before = #built
now = 13; Pilot.Update()
check(#built == before, "nothing else to build with a full roster")

-- A destroyed power plant is rebuilt by the constructor at its recorded position.
objs.sblpow3_powerplant.alive = false
now = 14; Pilot.Update()
check(built[#built] == "sbspow" and P.buildSlot == 2 and P.dropPending, "constructor builds the lost plant (slot 2)")
now = 15; Pilot.Update()
check(count("dropoff") == 1 and orders[#orders][3].x == 200 and orders[#orders][3].z == 50, "drop-off at the cached position")
now = 16; Pilot.Update()
check(count("dropoff") == 1, "one drop-off per building")
spawn("newpow", "sbspow"); finish("cnst")
check(P.base[2] == "newpow" and P.buildSlot == 0, "the rebuilt plant takes its slot")
before = #built; now = 17; Pilot.Update()
check(#built == before, "nothing more to rebuild")
-- A tower costs 6 and goes to its own slot.
objs.sbtowe1_turret.alive = false
now = 18; Pilot.Update()
check(built[#built] == "sbtowe" and P.buildSlot == 5, "tower rebuilt in slot 5")
now = 19; Pilot.Update()
spawn("newtow", "sbtowe"); finish("cnst")
check(P.base[5] == "newtow", "the rebuilt tower takes its slot")

-- A lost scavenger is replaced first (with the scrap and pilot top-up); the chain blocks the rest.
objs.svscav2_scavenger.alive = false
objs.svtank59_wingman.alive = false
scrap, pilots = 0, 0
now = 20; Pilot.Update()
check(built[#built] == "svscav" and scrap >= 4 and pilots == 1, "scavenger queued with the top-up")
spawn("scavN", "svscav"); finish(rec)
check(P.scav[2] == "scavN", "new scavenger fills the empty slot")
scrap, pilots = 100, 5

-- Tanks: the factory builds svtank until two stand, and the new tank follows.
now = 21; Pilot.Update()
check(built[#built] == "svtank", "factory builds a tank")
spawn("tankN", "svtank"); finish(muf)
check(P.tank[2] == "tankN" and count("follow", "tankN") == 1, "new tank takes the slot and follows")
before = #built; now = 22; Pilot.Update()
check(#built == before, "two tanks stand: no more built before the last phase")

-- Last phase: slots three and four get filled too.
env.M.last_phase = true
now = 23; Pilot.Update()
check(built[#built] == "svtank", "last phase builds a third tank")
spawn("tank3", "svtank"); finish(muf)
now = 24; Pilot.Update(); spawn("tank4", "svtank"); finish(muf)
before = #built; now = 25; Pilot.Update()
check(#built == before and P.tank[3] == "tank3" and P.tank[4] == "tank4", "four tanks, then idle")

-- Ammo pod: the recycler fires it at the player when low and none stands.
objs[player].ammo = 0.5
now = 26; Pilot.Update()
check(built[#built] == "sspammo@player", "ammo pod via the recycler")
spawn("pod", "sspammo"); finish(rec)
before = #built; now = 27; Pilot.Update()
check(#built == before, "a pod stands: no second request")

-- Escorts re-follow every 30 s (four tank slots, not the scavengers).
local f0 = count("follow")
now = 60; Pilot.Update()
check(count("follow") == f0 + 4 and count("follow", "scavN") == 0, "four tanks re-follow")

-- Constructor lost: fail after 10 s, once.
objs.cnst.alive = false
now = 61; Pilot.Update()
check(#fails == 1 and fails[1][1] == 71 and env.M.lost, "constructor loss fails the mission")
now = 62; Pilot.Update()
check(#fails == 1, "fails once")

-- Mid-mission toggle after the constructor fell: not armed, no fail.
do
    env.M.pilot, env.M.lost = nil, false
    fails = {}
    local P2 = env.M.pilot
    adapter.enable()
    P2 = env.M.pilot
    now = 70; Pilot.Update()
    check(#fails == 0 and not P2.cnstSeen, "constructor not seen alive with the mode on: no fail")
end

-- Off/on cycles register nothing twice and issue no duplicate orders.
adapter.enable()
spawn("late", "svtank")
local n0, b0 = #orders, #built
for _ = 1, 50 do
    enabled = false; adapter.disable(); Pilot.AddObject("late")
    enabled = true; adapter.enable(); Pilot.AddObject("late")
end
check(#orders == n0 and #built == b0, "no new orders or builds from 50 toggles")
check(env.M.pilot.nextSweep == 0, "disable re-arms the lock sweep")
print("misns5 Pilot Mode branch checks passed: " .. checks)
