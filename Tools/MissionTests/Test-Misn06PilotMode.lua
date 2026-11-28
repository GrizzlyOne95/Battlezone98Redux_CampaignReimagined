-- Execute misn06cr's N64 Pilot Mode branch (PilotUpdate/PilotAddObject) with
-- stubbed natives: escorts, path chains, geyser re-send, build queue, convoy.
local file = assert(io.open("Scripts/misn06cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("(local PILOT_ROUTES =.-)\n%-%- CR pilot mode <<"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local now, scrap, pilots, enabled = 0, 100, 10, true
local objs, built, orders = {}, {}, {}
local function obj(name, odf, t, x, z)
    objs[name] = { odf = odf, team = t or 1, alive = true, deployed = false, busy = false, cmd = 0, x = x or 0, z = z or 0 }
    return name
end
local player = obj("player", "avtank", 1, 900, 100000)
local rec = obj("rec", "avrec6", 1, 888, 100050)
local esc1 = obj("avtank0_wingman", "avtank")
local esc2 = obj("avtank1_wingman", "avtank")
local geyser = obj("geyser", "eggeizr1", 0)
local env = setmetatable({}, { __index = _G })
env.M = { avrec = rec, rendezvous = geyser, missionstart = true, opencamdone = false }
env.AiCommand = { NONE = 0, GO = 3 }
env.GetTime = function() return now end
env.GetPlayerHandle = function() return player end
env.GetHandle = function(l) return objs[l] and l end
env.IsAlive = function(h) return objs[h] ~= nil and objs[h].alive end
env.IsDeployed = function(h) return objs[h].deployed end
env.IsBusy = function(h) return objs[h].busy end
env.IsOdf = function(h, odf) return objs[h].odf == odf end
env.GetTeamNum = function(h) return objs[h].team end
env.GetScrap = function() return scrap end
env.GetPilot = function() return pilots end
env.GetCurrentCommand = function(h) return objs[h].cmd end
env.GetCurrentWho = function() return nil end
env.GetPosition = function(h) return { x = objs[h].x, y = 0, z = objs[h].z } end
env.GetDistance = function(a, b)
    local dx, dz = objs[a].x - objs[b].x, objs[a].z - objs[b].z
    return math.sqrt(dx * dx + dz * dz)
end
env.AllCraft = function() return function() return nil end end
env.AllObjects = function()
    local names = {}
    for k, o in pairs(objs) do if o.alive then names[#names + 1] = k end end
    table.sort(names)
    local i = 0
    return function() i = i + 1; return names[i] end
end
env.IsValid = function(h) return objs[h] ~= nil and objs[h].alive end
env.SetCommand = function() end
env.SetUserTarget = function(h) orders[#orders + 1] = { "target", h } end
env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
env.GetTerrainHeightAndNormal = function() return 7 end
env.Goto = function(h, t) orders[#orders + 1] = { "go_to", h, t }; objs[h].cmd = 3; objs[h].deployed = false end
env.Follow = function(h, t) orders[#orders + 1] = { "follow", h, t } end
env.Build = function(h, odf) built[#built + 1] = odf; objs[h].busy = true end
local adapter
env.PlayerPilotMode = { IsEnabled = function() return enabled end, Initialize = function(a) adapter = a end }
-- Spot orders (PilotBranch.KeepSpots/KeepGoto) measure the distance to a vector: from the object's x/z when it has them, else far away.
do
    local baseDistance = env.GetDistance
    env.GetDistance = function(a, b)
        if type(b) == "table" then
            local o = objs[a]
            if o and o.x and o.z then return math.sqrt((o.x - b.x) ^ 2 + (o.z - b.z) ^ 2) end
            return 1e9
        end
        if baseDistance then return baseDistance(a, b) end
        return 1e9
    end
end
env.PilotBranch = setfenv(assert(loadfile("Scripts/CRPilotBranch.lua")), env)()
for _, f in ipairs({ "Lock", "Ready", "Resend", "TryBuild", "alive", "Adopt" }) do setfenv(env.PilotBranch[f], env) end
local chunk = assert(loadstring("local M, PlayerPilotMode, PilotBranch = M, PlayerPilotMode, PilotBranch\n" .. block ..
    "\nreturn { update = PilotUpdate, add = PilotAddObject, init = InitializePilotMode }"))
setfenv(chunk, env)
local api = chunk()
api.init()
local function spawn(name, odf, team) obj(name, odf, team); api.add(name) end
local function gotoTo(i) local o = orders[i]; return o[1] == "go_to" and o[2] == rec and o[3] end
local function at(x, z) objs[rec].x, objs[rec].z = x, z end

-- Mission start frame and the intro camera: nothing yet.
api.update(); env.M.missionstart = false; env.M.opencamdone = true; now = 1; api.update()
check(#orders == 0 and #built == 0, "no orders during the intro camera")

-- Intro camera ends: both escorts follow the recycler, recycler down path 35.
env.M.opencamdone = false; now = 2; api.update()
check(orders[1][1] == "follow" and orders[1][2] == esc1 and orders[1][3] == rec, "escort 1 follows the recycler")
check(orders[2][1] == "follow" and orders[2][2] == esc2 and orders[2][3] == rec, "escort 2 follows the recycler")
local g = gotoTo(3)
check(g and g.x == 888 and g.z == 99868 and g.y == 7, "path 35 first leg (recycler already at point 1)")
check(#orders == 3, "one order per leg")
now = 3; api.update()
check(#orders == 3, "no re-send while heading for the waypoint")
for _, p in ipairs({ { 888, 99868 }, { 844, 99673 }, { 841, 99509 }, { 960, 99498 } }) do
    at(p[1], p[2]); now = now + 1; api.update()
end
g = gotoTo(#orders)
check(g.x == 1851 and g.z == 99550, "path 35 last point after walking the chain")
local n; at(1851, 99550); n = #orders; now = now + 1; api.update()
check(#orders == n, "path 35 finished: no more legs")

-- Object inspected: path 36. Starport inspected: recycler to its geyser.
env.M.hephikey = true; now = now + 1; api.update()
g = gotoTo(#orders)
check(g and g.x == 1835 and g.z == 99490, "path 36 first leg")
env.M.starportreconed = true; now = now + 1; api.update()
check(orders[#orders][1] == "go_to" and orders[#orders][2] == rec and orders[#orders][3] == geyser, "recycler to its geyser")
objs[rec].cmd = 0; n = #orders
now = now + 1; api.update(); now = now + 7; api.update()
check(#orders == n + 1 and orders[#orders][3] == geyser, "recycler re-sent to its geyser after 6 s")
check(#built == 0, "nothing built before the recycler deploys")

-- Build queue: scavenger, ammo x2, repair x2, turret, fighters x8, then idle.
objs[rec].deployed = true
scrap = 3; now = now + 1; api.update()
check(#built == 0, "scavenger waits for 4 scrap")
scrap = 100
local expect = { "avscav", "napammo", "napammo", "naprepa", "naprepa", "avturr" }
for _ = 1, 8 do expect[#expect + 1] = "avfigh" end
for i, odf in ipairs(expect) do
    now = now + 1; api.update()
    check(built[#built] == odf and #built == i, "queue item " .. i .. " is " .. odf .. ", got " .. tostring(built[#built]))
    objs[rec].busy = false
end
local before = #built; now = now + 1; api.update()
check(#built == before, "queue done after eight fighters")

-- Fighters go to the recycler; other teams are ignored.
n = #orders; spawn("f1", "avfigh", 1)
check(orders[#orders][1] == "follow" and orders[#orders][2] == "f1" and orders[#orders][3] == rec, "new fighter follows the recycler")
spawn("t1", "avturr", 1); spawn("e1", "avfigh", 2)
check(#orders == n + 1, "only team 1 fighters get orders")

-- Nav beacons become the user target.
env.M.starportcam = obj("cam", "apcamr"); now = now + 1; api.update()
check(orders[#orders][1] == "target" and orders[#orders][2] == "cam", "starport beacon is the user target")
n = #orders; now = now + 1; api.update()
check(#orders == n, "beacon targeted once")

-- Launch pad inspected, player near: convoy down path 38, ending on the dust-off beacon.
env.M.launchpadreconed = true
at(2000, 99200); objs[player].x, objs[player].z = 2050, 99200
now = now + 1; api.update()
g = gotoTo(#orders)
check(g and g.x == 2780 and g.z == 99160, "path 38 first leg once the player is near")
local legs = #orders
now = now + 5; api.update()
check(#orders == legs, "path 38 not re-sent inside 10 s")
now = now + 6; api.update()
check(#orders == legs + 1 and gotoTo(#orders).x == 2780, "path 38 re-sent every 10 s")
for _, p in ipairs({ { 2780, 99160 }, { 2800, 99345 }, { 3228, 99350 } }) do
    at(p[1], p[2]); now = now + 1; api.update()
end
check(gotoTo(#orders).x == 3380 and gotoTo(#orders).z == 99483, "path 38 last point")
env.M.dustoffcam = obj("dust", "apcamr"); at(3380, 99483); now = now + 1; api.update()
check(orders[#orders - 1][1] == "target" and orders[#orders - 1][2] == "dust", "dust-off beacon is the user target")
check(gotoTo(#orders) == "dust", "recycler goes on to the dust-off beacon")
n = #orders; now = now + 1; api.update()
check(#orders == n, "convoy finished")
-- CR adaptation: dust-off resend every 10 s while idle and far; not while GO or near.
n = #orders; now = now + 11; api.update()
check(#orders == n, "no dust-off resend while the recycler is on its way (GO)")
objs[rec].cmd = 0; now = now + 10; api.update()
check(#orders == n + 1 and gotoTo(#orders) == "dust", "dust-off re-sent 10 s on when idle and far")
objs[rec].cmd = 0; now = now + 5; api.update()
check(#orders == n + 1, "no dust-off resend inside 10 s")
objs[rec].cmd = 0; now = now + 6; api.update()
check(#orders == n + 2, "dust-off re-sent again after another 10 s")
objs[rec].cmd = 0; objs[rec].x, objs[rec].z = 3380, 99483; objs["dust"].x, objs["dust"].z = 3400, 99483
now = now + 11; api.update()
check(#orders == n + 2, "no dust-off resend when within 100 m")

-- Adoption: a fighter that exists before the mode is on follows the recycler
-- once the adapter's enable runs, and only once.
check(adapter and adapter.enable, "adapter has an enable hook")
local function followsOf(h)
    local c = 0
    for _, o in ipairs(orders) do if o[1] == "follow" and o[2] == h then c = c + 1 end end
    return c
end
enabled = false
spawn("pre", "avfigh", 1)
check(followsOf("pre") == 0, "no order while off")
enabled = true
adapter.enable()
check(followsOf("pre") == 1 and followsOf("f1") == 1, "pre-existing fighter adopted once, earlier ones untouched")
n = #orders
adapter.enable(); api.add("pre")
check(#orders == n and followsOf("pre") == 1, "no double registration after a second enable or AddObject")

-- Disabled: AddObject leaves units alone.
enabled = false; n = #orders
spawn("off", "avfigh", 1)
check(#orders == n, "no orders while Pilot Mode is off")
print("misn06 Pilot Mode branch checks passed: " .. checks)
