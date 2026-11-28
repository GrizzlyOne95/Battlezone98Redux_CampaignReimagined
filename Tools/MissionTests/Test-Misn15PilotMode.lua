-- Execute CRMisn15's N64 Pilot Mode branch (PilotUpdate/PilotAddObject) with
-- stubbed natives: start follows, convoy join, rescue, geyser re-send, scav /
-- pod / silo build chain, constructor drops, RECYCLE orders, extra fails,
-- the CR withdraw adaptation and adoption/disable cycles.
local file = assert(io.open("Scripts/CRMisn15.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("%-%- CR pilot mode >>\n(.-)\n%-%- CR pilot mode <<"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local now, scrap, pilots, enabled, health, ammo = 0, 100, 5, true, 1, 1
local objs, built, orders, fails = {}, {}, {}, {}
local function obj(name, odf, t, x, z)
    objs[name] = { odf = odf, team = t or 1, alive = true, deployed = false, busy = false, cmd = 0, x = x or 0, z = z or 0 }
    return name
end
local player = obj("player", "avtank", 1, 3000, 99000)
local rec = obj("avrecy0_recycler", "avrecy", 1, 3223, 98909)
local cons = obj("avcnst0_constructionrig", "avcnst", 1, 3167, 98937)
local geyser = obj("eggeizr19_geyser", "eggeizr1", 0, 4059, 100232)
local cam2, cam5, cam6 = obj("cam2", "apcamr", 1), obj("cam5", "apcamr", 1), obj("cam6", "apcamr", 1)
local tank1 = obj("svtank0_wingman", "svtank", 7)
local tank2 = obj("svtank1_wingman", "svtank", 7)
local apc = obj("svapc0_apc", "svapc", 7)
local nwScav = obj("cr15_nw_scav", "avscav", 7)
local nwApc = obj("cr15_nw_apc", "avapc", 7)

local env = setmetatable({}, { __index = _G })
env.M = { recy = rec, cam2 = cam2, cam5 = cam5, cam6 = cam6, start_done = true }
env.CR = { convoy = { tank1, tank2, apc } }
env.FailRecord = function(r) fails[#fails + 1] = r; env.M.lost = true end
env.AiCommand = { NONE = 0, GO = 3, FOLLOW = 5, RECYCLE = 18 }
env.GetTime = function() return now end
env.GetPlayerHandle = function() return player end
env.GetHandle = function(l) return objs[l] and l end
env.IsValid = function(h) return objs[h] ~= nil and objs[h].alive end
env.IsAlive = function(h) return objs[h] ~= nil and objs[h].alive end
env.IsDeployed = function(h) return objs[h].deployed end
env.IsBusy = function(h) return objs[h].busy end
env.IsOdf = function(h, odf) return objs[h].odf == odf end
env.GetTeamNum = function(h) return objs[h].team end
env.GetScrap = function() return scrap end
env.AddScrap = function(_, n) scrap = scrap + n end
env.GetPilot = function() return pilots end
env.AddPilot = function(_, n) pilots = pilots + n end
env.GetHealth = function() return health end
env.GetAmmo = function() return ammo end
env.GetCurrentCommand = function(h) return objs[h].cmd end
env.GetDistance = function(a, b)
    local dx, dz = objs[a].x - objs[b].x, objs[a].z - objs[b].z
    return math.sqrt(dx * dx + dz * dz)
end
env.GetCurrentWho = function() return nil end
env.AllCraft = function() return function() return nil end end
env.AllObjects = function()
    local names = {}
    for k, o in pairs(objs) do if o.alive then names[#names + 1] = k end end
    table.sort(names)
    local i = 0
    return function() i = i + 1; return names[i] end
end
env.SetCommand = function(h, c, p, w) orders[#orders + 1] = { "cmd", h, c, w } end
env.SetUserTarget = function(h) orders[#orders + 1] = { "target", h } end
env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
env.GetTerrainHeightAndNormal = function() return 7 end
env.Goto = function(h, t) orders[#orders + 1] = { "go_to", h, t }; objs[h].cmd = 3; objs[h].deployed = false end
env.Follow = function(h, t) orders[#orders + 1] = { "follow", h, t } end
env.Dropoff = function(h, pos) orders[#orders + 1] = { "dropoff", h, pos } end
env.Build = function(h, odf) built[#built + 1] = odf .. "@" .. h; objs[h].busy = true end
local adapter
env.PlayerPilotMode = { IsEnabled = function() return enabled end, Initialize = function(a) adapter = a end }
env.PilotBranch = assert(loadfile("Scripts/CRPilotBranch.lua"))()
for _, f in pairs(env.PilotBranch) do if type(f) == "function" then setfenv(f, env) end end
local chunk = assert(loadstring(table.concat({
    "local M, PlayerPilotMode, PilotBranch, CR = M, PlayerPilotMode, PilotBranch, CR",
    "local function Valid(h) return h ~= nil and h ~= 0 and IsValid(h) end",
    "local function Alive(h) return Valid(h) and IsAlive(h) end",
    "local function IsOdfBase(h, n) return Valid(h) and (IsOdf(h, n) or IsOdf(h, n .. '.odf')) end",
    "local function State() return CR end",
    "local function FinishFailure(r) FailRecord(r) end",
    block, "return { update = PilotUpdate, add = PilotAddObject, init = InitializePilotMode }" }, "\n")))
setfenv(chunk, env)
local api = chunk()
api.init()
local P
local function step(dt) now = now + (dt or 1); api.update(); P = env.M.pilot end
local function spawn(name, odf, team) obj(name, odf, team); api.add(name) end
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

-- Start: nav 21 targeted, recycler and constructor follow the player.
step(1)
check(count("target", cam6) == 1, "first frame targets nav 21")
check(count("follow", rec, player) == 1 and count("follow", cons, player) == 1, "recycler and constructor follow the player")
check(#built == 0, "an undeployed recycler builds nothing")
local n = #orders; step(1)
check(#orders == n, "start orders run once")

-- Regroup every 30 s while the rescue has not happened.
step(31)
check(count("follow", rec, player) == 2 and count("follow", cons, player) == 2, "30 s regroup follows again")
check(count("follow", tank1) == 0, "convoy not ordered before it joins")

-- Convoy joins (CR s.cca): tanks and APC follow, nav 18 is the target.
env.CR.cca = true
for _, h in ipairs({ tank1, tank2, apc }) do objs[h].team = 1 end
step(1)
check(count("target", cam2) == 1, "nav 18 targeted when the convoy joins")
check(count("follow", tank1, player) == 1 and count("follow", tank2, player) == 1 and count("follow", apc, player) == 1,
      "convoy follows the player once it joins")
step(31)
check(count("follow", tank1, player) == 2 and count("follow", rec, player) == 3, "regroup includes the convoy")

-- Scavenger top-up: recycler deployed, scrap below 4, no pilots -> topped up.
objs[rec].deployed = true; scrap = 0; pilots = 0
step(1)
check(builds("avscav@" .. rec) == 1 and scrap == 4 and pilots == 1, "scav top-up raises scrap to 4 and a pilot, builds avscav")
objs[rec].busy = false
step(1)
check(builds("avscav@" .. rec) == 2, "second scavenger queued while neither escort exists")
objs[rec].busy = false

-- Rescue group joins team 1: each tank guards a scavenger.
objs[nwScav].team, objs[nwApc].team = 1, 1
api.add(nwScav); api.add(nwApc)
check(count("follow", tank1, nwScav) == 1, "tank 1 guards the rescued scavenger")
spawn("scavB", "avscav", 1)
check(count("follow", tank2, "scavB") == 1, "tank 2 guards the second scavenger")
api.add("scavB")
check(count("follow", tank2, "scavB") == 1, "no double registration of a scavenger")
env.CR.nw = true
objs[rec].deployed = false; objs[rec].cmd = 5
step(1)
check(count("go_to", rec, geyser) == 1, "recycler sent to geyser 11 at the rescue")
check(count("follow", tank1, nwScav) == 2, "rescue re-sends tank 1 to the scavenger")
objs[rec].cmd = 0
step(1); step(7)
check(count("go_to", rec, geyser) == 2, "recycler re-sent to the geyser after 6 s")
objs[rec].cmd = 0
step(1)
check(count("go_to", rec, geyser) == 2, "re-send waits another 6 s")
check(count("follow", rec, player) == 3, "no more regroup follows after the rescue")

-- Supply pods: below 75 percent health the recycler builds a repair pod.
objs[rec].deployed = true; objs[rec].cmd = 0; objs[rec].busy = false
health = 0.5
step(1)
check(builds("aprepa@" .. rec) == 1, "repair pod built when health is below 75 percent")
objs[rec].busy = false; step(1)
check(builds("aprepa@" .. rec) == 1, "no second pod while the first is requested")
spawn("pod1", "aprepa", 1)
health = 1; ammo = 0.5; objs[rec].busy = false
step(1)
check(builds("apammo@" .. rec) == 1, "ammo pod built when ammo is below 75 percent")
spawn("pod2", "apammo", 1); ammo = 1; objs[rec].busy = false

-- Silos: constructor builds two, dropped at the N64 spots (the first silo was
-- queued as soon as the pod requests were served).
check(builds("absilo@" .. cons) == 1, "constructor builds the first silo")
step(1)
local d
for _, o in ipairs(orders) do if o[1] == "dropoff" then d = o end end
check(d and d[2] == cons and d[3].x == 4066 and d[3].z == 100266 and d[3].y == 7, "first silo dropped at (4066, 100266)")
check(count("dropoff") == 1, "one dropoff per silo build")
objs[cons].busy = false
step(1)
check(builds("absilo@" .. cons) == 1, "second silo waits for the first to appear")
spawn("silo1", "absilo", 1)
step(1)
check(builds("absilo@" .. cons) == 2, "second silo built once the first stands")
step(1)
d = orders[#orders]
check(d[1] == "dropoff" and d[3].x == 4057 and d[3].z == 100180, "second silo dropped at (4057, 100180)")
spawn("silo2", "absilo", 1); objs[cons].busy = false
step(1); step(1)
check(builds("absilo@" .. cons) == 2, "no third silo")

-- RECYCLE: the rescued APC and the CCA APC recycle themselves, once each.
check(count("cmd", nwApc, 18) == 1 and count("cmd", apc, 18) == 1, "both APCs ordered to RECYCLE once")

-- Fails: a silo lost.
check(#fails == 0, "no fail so far")
objs.silo2.alive = false
step(1)
check(#fails == 1 and fails[1]:find("silo", 1, true), "losing a silo fails the mission")

-- CR withdraw adaptation (fresh state): rig lost before both silos fails; withdraw sends the recycler to the Supply beacon.
env.M.lost = nil; fails = {}
objs.silo2.alive = true; objs.silo1.alive = true
env.CR.withdraw = true
n = #orders
step(1)
check(count("go_to", rec, cam5) == 1 and count("target", cam5) == 1, "withdraw sends the recycler to the Supply beacon")
objs[rec].deployed = false; objs[rec].cmd = 0
step(1); step(10)
-- CR adaptation: the withdraw order is re-sent after 10 s (idle and far), so cam5 now has two orders.
check(count("go_to", rec, cam5) == 2 and count("go_to", rec, geyser) == 2, "no geyser re-send after withdraw; withdraw re-sent once")
-- Not while GO, not inside 10 s, not when within 200 m.
objs[rec].cmd = 3; step(10)
check(count("go_to", rec, cam5) == 2, "no withdraw resend while the recycler is on its way (GO)")
objs[rec].cmd = 0; step(5)
check(count("go_to", rec, cam5) == 2, "no withdraw resend inside 10 s")
step(5)
check(count("go_to", rec, cam5) == 3, "withdraw re-sent when idle and far")
objs[rec].cmd = 0; objs[rec].x, objs[rec].z = objs[cam5].x + 150, objs[cam5].z; step(10)
check(count("go_to", rec, cam5) == 3, "no withdraw resend within 200 m")

-- Disable/enable cycles issue no duplicate placement orders.
check(adapter and adapter.enable and adapter.disable, "adapter has enable/disable hooks")
local function followsOf(h) return count("follow", nil, nil) and count("follow", h) end
enabled = false
spawn("pre", "avscav", 1)
env.M.pilot.escort1, env.M.pilot.escort2 = nil, nil
check(not env.M.pilot.claimed or #env.M.pilot.claimed > 0, "claimed list persists")
local before = #orders
api.add("pre")
check(#orders == before, "no registration while off")
enabled = true
adapter.enable()
local after = #orders
adapter.disable(); adapter.enable()
check(#orders == after, "disable/enable cycle adds no duplicate tank orders")
api.add("pre")
check(#orders == after, "already claimed unit is not registered twice")

-- Constructor lost before both silos (fresh branch state).
env.M.pilot = nil; env.M.lost = nil; fails = {}
env.CR.withdraw = nil
objs[cons].alive = false
step(1); step(1); step(1)
check(#fails == 0, "rig already dead when the mode turns on: no instant fail")
env.M.pilot = nil; objs[cons].alive = true
step(1); step(1); step(1)
objs[cons].alive = false
step(1)
check(#fails == 1 and fails[1]:find("rig", 1, true), "constructor lost before both silos fails the mission")
print("misn15 Pilot Mode branch checks passed: " .. checks)
