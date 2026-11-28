-- Execute misn08cr's N64 Pilot Mode branch (PilotUpdate/PilotAddObject) with
-- stubbed natives: start orders, build-queue order, unit placement, follow
-- orders, supply pods, howitzer orders, and silence while the toggle is off.
local file = assert(io.open("Scripts/misn08cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("(local PILOT_TURRET_SPOTS =.-)\n%-%- CR PDA <<"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local now, scrap, pilots, enabled = 0, 100, 0, true
local objs, built, orders, fails = {}, {}, {}, {}
local function obj(name, odf, t, x, z)
    objs[name] = { odf = odf, team = t or 1, alive = true, deployed = false, busy = false,
                   health = 1, ammo = 1, cmd = 0, x = x or 0, z = z or 0 }
    return name
end
local player = obj("player", "avtank")
local rec = obj("rec", "avrec8", 1, 2326, 101138)
obj("rig", "avcnst9", 1, 2350, 101140)
obj("eggeizr112_geyser", "eggeizr", 0, 2373, 101111)
obj("eggeizr113_geyser", "eggeizr", 0, 2322, 101196)
obj("eggeizr116_geyser", "eggeizr", 0, 2494, 100930)
obj("eggeizr117_geyser", "eggeizr", 0, 2373, 100889)
obj("power1", "sblpow", 2); obj("sblpow2_powerplant", "sblpow", 2); obj("sblpow4_powerplant", "sblpow", 2)
obj("walk1", "svwalk", 2); obj("walk2", "svwalk", 2); obj("cam2", "apcamr", 1)

local env = setmetatable({}, { __index = _G })
env.M = { nsdfrecycle = rec, ccagech1 = "walk1", ccagech2 = "walk2", nav4 = "cam2" }
env.AiCommand = { NONE = 0, GO = 3 }
env.GetTime = function() return now end
env.GetPlayerHandle = function() return player end
env.GetHandle = function(l)
    if l == "avcnst0_constructionrig" then return "rig" end
    return objs[l] and l or nil
end
env.IsAlive = function(h) return objs[h] ~= nil and objs[h].alive end
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
env.GetDistance = function(a, b)
    return math.sqrt((objs[a].x - objs[b].x) ^ 2 + (objs[a].z - objs[b].z) ^ 2)
end
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
env.IsValid = function(h) return objs[h] ~= nil and objs[h].alive end
env.SetCommand = function() end
env.SetUserTarget = function(h) orders[#orders + 1] = { "target", h } end
env.RemoveObject = function(h) orders[#orders + 1] = { "remove", h }; objs[h].alive = false end
env.SetObjectiveOn = function(h) orders[#orders + 1] = { "objective", h } end
env.FailMission = function(t) fails[#fails + 1] = t end
env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
env.GetTerrainHeightAndNormal = function() return 7 end
env.Goto = function(h, t, p) orders[#orders + 1] = { "go_to", h, t }; if objs[h] then objs[h].cmd = 3 end end
env.Follow = function(h, t) orders[#orders + 1] = { "follow", h, t } end
env.Attack = function(h, t) orders[#orders + 1] = { "attack", h, t } end
env.Build = function(h, odf) built[#built + 1] = odf .. "@" .. h; objs[h].busy = true end
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
for _, fn in ipairs({ "Lock", "Ready", "Resend", "FollowPlayer", "TryBuild", "alive", "Adopt" }) do
    setfenv(env.PilotBranch[fn], env)
end
local chunk = assert(loadstring("local M, PlayerPilotMode, PilotBranch = M, PlayerPilotMode, PilotBranch\n" .. block ..
    "\nreturn { update = PilotUpdate, add = PilotAddObject, init = InitializePilotMode }"))
setfenv(chunk, env)
local api = chunk()
local function spawn(name, odf, x, z) obj(name, odf, 1, x, z); api.add(name) end
local function finish(h) objs[h].busy = false end
local function count(kind)
    local n = 0
    for _, o in ipairs(orders) do if o[1] == kind then n = n + 1 end end
    return n
end

-- Disabled: neither AddObject nor the units get orders.
enabled = false
spawn("off", "avturr")
check(#orders == 0, "no orders while Pilot Mode is off")
enabled = true

-- Start: the construction rig goes, cam2 is the user target, the recycler heads
-- for the nearest geyser (label 7, eggeizr112).
api.update()
check(orders[1][1] == "remove" and orders[1][2] == "rig", "construction rig removed")
check(orders[2][1] == "target" and orders[2][2] == "cam2", "SetUserTarget(cam2)")
check(orders[3][1] == "go_to" and orders[3][2] == rec and orders[3][3] == "eggeizr112_geyser", "recycler to nearest geyser")
check(#built == 0, "nothing built before the recycler deploys")

-- Re-send: an undeployed recycler knocked off GO gets Goto again after 6 s.
objs[rec].cmd = 0; local n = #orders
now = 1; api.update(); now = 8; api.update()
check(#orders == n + 1 and orders[#orders][2] == rec, "recycler re-sent to its geyser")

-- Recycler deploys on geyser 112; the queue starts with the factory.
objs[rec].deployed, objs[rec].x, objs[rec].z = true, 2373, 101111
now = now + 1; api.update()
check(built[#built] == "avmu8@rec", "factory first")
finish(rec)
spawn("muf", "avmu8", 2380, 101120)
check(orders[#orders][1] == "go_to" and orders[#orders][2] == "muf" and orders[#orders][3] == "eggeizr113_geyser",
    "factory goes to the free geyser (not the recycler's)")
now = now + 1; api.update()
check(built[#built] == "avscav@rec" and scrap >= 4 and pilots == 1, "scavenger with the pilot top-up")
spawn("s1", "avscav"); finish(rec)
now = now + 1; api.update()
check(built[#built] == "avscav@rec", "second scavenger")
spawn("s2", "avscav"); finish(rec)
check(count("follow") == 0, "scavengers are not told to follow")

-- Tanks wait for the factory to deploy, then follow the player.
local before = #built
now = now + 1; api.update()
check(#built == before, "queue holds while the factory is undeployed")
objs.muf.deployed = true
for i = 1, 2 do
    now = now + 1; api.update()
    check(built[#built] == "avtank@muf", "tank " .. i)
    spawn("t" .. i, "avtank"); finish("muf")
    check(orders[#orders][1] == "follow" and orders[#orders][2] == "t" .. i and orders[#orders][3] == player, "tank follows")
end

-- Howitzer only once both walkers are dead; it goes to its spot and is an objective.
before = #built
objs.walk1.alive, objs.walk2.alive = false, false
now = now + 1; api.update()
check(built[#built] == "avartl@muf" and #built == before + 1, "howitzer after the walkers fall")
spawn("how", "avartl"); finish("muf")
local g = orders[#orders - 1]
check(g[1] == "go_to" and g[2] == "how" and g[3].x == 1869 and g[3].z == 99301 and g[3].y == 7, "howitzer spot")
check(orders[#orders][1] == "objective" and orders[#orders][2] == "how", "howitzer set as objective")
now = now + 1; api.update()
check(built[#built] == "avturr@rec", "turrets next")

-- Turrets go to the N64 spots in order.
local spots = { { 2352, 101153 }, { 2413, 101095 }, { 2293, 101204 } }
spawn("u1", "avturr"); finish(rec)
for i = 2, 3 do
    now = now + 1; api.update()
    check(built[#built] == "avturr@rec", "turret " .. i .. " built")
    spawn("u" .. i, "avturr"); finish(rec)
end
for i = 1, 3 do
    local found
    for _, o in ipairs(orders) do if o[1] == "go_to" and o[2] == "u" .. i then found = o[3] end end
    check(found and found.x == spots[i][1] and found.z == spots[i][2] and found.y == 7, "turret " .. i .. " spot")
end

-- Fighters up to eight, each following the player.
for i = 1, 8 do
    now = now + 1; api.update()
    check(built[#built] == "avfigh@rec", "fighter " .. i)
    spawn("f" .. i, "avfigh"); finish(rec)
    check(orders[#orders][1] == "follow" and orders[#orders][2] == "f" .. i, "fighter follows")
end
before = #built; now = now + 1; api.update()
check(#built == before, "queue idles once everything is built")

-- Howitzer shells the first live power plant once deployed.
objs.how.deployed = true
now = now + 1; api.update()
check(orders[#orders][1] == "attack" and orders[#orders][2] == "how" and orders[#orders][3] == "power1", "howitzer attacks power1")

-- Supply: a hurt player gets one repair pod from the recycler, not a second.
objs[player].health = 0.5
now = now + 1; api.update()
check(built[#built] == "naprepa@rec", "repair pod from the recycler")
finish(rec); spawn("pod", "naprepa"); before = #built
now = now + 1; api.update()
check(#built == before, "one live pod: no more requested")

-- Wingmen re-follow every 30 s (two tanks and eight fighters).
local follows = count("follow")
now = now + 31; api.update()
check(count("follow") == follows + 10, "all ten escorts re-follow")

-- Losing the howitzer fails the mission five seconds later.
objs.how.alive = false
now = now + 1; api.update()
check(#fails == 1 and fails[1] == now + 5.0, "howitzer loss fails the mission")
api.update()
check(#fails == 1, "fails only once")

-- Adoption: a factory that exists before the mode is on (fresh branch state, as
-- after a load) is adopted when the adapter's enable runs; no second factory
-- is built and a second enable does not duplicate slots.
do
    api.init()
    check(adapter and adapter.enable, "adapter has an enable hook")
    objs.muf.alive = false
    env.M.pilot = nil
    enabled = false
    obj("pmuf", "avmu8", 1, 2380, 101120); objs.pmuf.deployed = true; api.add("pmuf")
    enabled = true
    adapter.enable()
    local P = env.M.pilot
    check(P.muf == "pmuf", "pre-existing factory adopted on enable")
    local s1, s2 = P.scav[1], P.scav[2]
    check(s1 ~= nil and s2 ~= nil and s1 ~= s2, "scavenger slots filled with two units")
    adapter.enable(); api.add("pmuf")
    check(P.muf == "pmuf" and P.scav[1] == s1 and P.scav[2] == s2, "no duplicate slots after a second enable or AddObject")
    objs[rec].deployed, objs[rec].busy = true, false
    local first = #built
    for _ = 1, 4 do now = now + 1; api.update(); finish(rec) end
    for i = first + 1, #built do check(not built[i]:find("^avmu8"), "no second factory built: " .. built[i]) end
end

-- Disabled again: AddObject leaves units alone.
enabled = false; n = #orders
spawn("late", "avturr")
check(#orders == n, "no orders while Pilot Mode is off")
print("misn08 Pilot Mode branch checks passed: " .. checks)
