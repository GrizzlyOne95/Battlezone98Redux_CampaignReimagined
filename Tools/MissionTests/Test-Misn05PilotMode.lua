-- Execute misn05cr's N64 Pilot Mode branch (PilotUpdate/PilotAddObject) with
-- stubbed natives: build-queue order, turret spots, armory pods, escorts.
local file = assert(io.open("Scripts/misn05cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("(local PILOT_TURRET_SPOTS =.-)\n%-%- BuildObject invokes"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local now, scrap, enabled = 0, 100, true
local objs, built, orders = {}, {}, {}
local function obj(name, odf, t) objs[name] = { odf = odf, team = t or 1, alive = true, deployed = false, busy = false, health = 1, ammo = 1, cmd = 0 }; return name end
local player = obj("player", "avtank")
local rec = obj("rec", "avrecy"); local slf = obj("slf", "avslf")
obj("eggeizr118_geyser", "eggeizr", 0); obj("eggeizr132_geyser", "eggeizr", 0)
local env = setmetatable({}, { __index = _G })
env.M = { avrec = rec, cam1 = "cam1" }
env.AiCommand = { NONE = 0, GO = 3 }
env.GetTime = function() return now end
env.GetPlayerHandle = function() return player end
env.GetHandle = function(l) return l == "avslf0_armory" and slf or (objs[l] and l) end
env.IsAlive = function(h) return objs[h] ~= nil and objs[h].alive end
env.IsDeployed = function(h) return objs[h].deployed end
env.IsBusy = function(h) return objs[h].busy end
env.IsOdf = function(h, odf) return objs[h].odf == odf end
env.GetTeamNum = function(h) return objs[h].team end
env.GetHealth = function(h) return objs[h].health end
env.GetAmmo = function(h) return objs[h].ammo end
env.GetScrap = function() return scrap end
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
env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
env.GetTerrainHeightAndNormal = function() return 7 end
env.Goto = function(h, t, p) orders[#orders + 1] = { "go_to", h, t }; if objs[h] then objs[h].cmd = 3 end end
env.Follow = function(h, t) orders[#orders + 1] = { "follow", h, t } end
env.Build = function(h, odf) built[#built + 1] = odf; objs[h].busy = true end
env.BuildAt = function(h, odf, t) built[#built + 1] = odf .. "@" .. t end
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
setfenv(env.PilotBranch.Lock, env); setfenv(env.PilotBranch.Ready, env); setfenv(env.PilotBranch.Resend, env)
setfenv(env.PilotBranch.FollowPlayer, env); setfenv(env.PilotBranch.TryBuild, env); setfenv(env.PilotBranch.alive, env); setfenv(env.PilotBranch.Adopt, env)
local chunk = assert(loadstring("local M, PlayerPilotMode, PilotBranch = M, PlayerPilotMode, PilotBranch\n" .. block ..
    "\nreturn { update = PilotUpdate, add = PilotAddObject, init = InitializePilotMode }"))
setfenv(chunk, env)
local api = chunk()
api.init()
local function spawn(name, odf) obj(name, odf); api.add(name) end
local function finishBuild() objs[rec].busy = false end

-- Start: target cam1, armory and recycler head to their geysers.
api.update()
check(orders[1][1] == "target" and orders[1][2] == "cam1", "SetUserTarget(cam1) first")
check(orders[2][2] == slf and orders[2][3] == "eggeizr132_geyser", "armory to geyser 132")
check(orders[3][2] == rec and orders[3][3] == "eggeizr118_geyser", "recycler to geyser 118")
check(#built == 0, "nothing built before the recycler deploys")

-- Re-send: an undeployed recycler knocked off GO gets Goto again after 6 s.
objs[rec].cmd = 0; local n = #orders
now = 1; api.update(); now = 8; api.update()
check(#orders == n + 1 and orders[#orders][2] == rec, "recycler re-sent to its geyser")

-- Queue: turret, scav, scav, turret, turret, then waits for new orders.
objs[rec].deployed, objs[slf].deployed = true, true
local expect = { "avturr", "avscav", "avscav", "avturr", "avturr" }
for i, odf in ipairs(expect) do
    now = now + 1; api.update()
    check(built[#built] == odf, "queue item " .. i .. " is " .. odf .. ", got " .. tostring(built[#built]))
    spawn("u" .. i, odf); finishBuild()
end
local before = #built
now = now + 1; api.update()
check(#built == before, "queue idles until new orders")
check(orders[#orders - 0][1] ~= nil, "orders recorded")
-- Turrets go to the N64 spots, in order, at terrain height.
local turretGotos = {}
for _, o in ipairs(orders) do if o[1] == "go_to" and type(o[3]) == "table" then turretGotos[#turretGotos + 1] = o[3] end end
check(#turretGotos == 3 and turretGotos[1].x == 2214 and turretGotos[1].z == 100216 and turretGotos[1].y == 7, "turret 1 spot")
check(turretGotos[3].x == 2219, "turret 3 spot")

-- New orders: two fighters that follow the player, then turrets up to six.
env.M.neworders = true
for i, odf in ipairs({ "avfigh", "avfigh", "avturr", "avturr", "avturr" }) do
    now = now + 1; api.update()
    check(built[#built] == odf, "new-orders item " .. i .. " is " .. odf .. ", got " .. tostring(built[#built]))
    spawn("n" .. i, odf); finishBuild()
end
check(orders[#orders][1] == "go_to", "sixth turret placed")
before = #built; now = now + 1; api.update()
check(#built == before, "no seventh turret")

-- Supply: player under 75% gets two repair pods from the armory, 3 s apart.
objs[player].health = 0.5
now = now + 1; api.update()
check(built[#built] == "naprepa@player", "repair pod via armory BuildAt")
before = #built; now = now + 1; api.update()
check(#built == before, "3 s cooldown between pods")
now = now + 3; api.update()
check(built[#built] == "naprepa@player" and #built == before + 1, "second repair pod")
spawn("p1", "naprepa"); spawn("p2", "naprepa")
before = #built; now = now + 5; api.update()
check(#built == before, "two live pods: no more requested")

-- Escorts re-follow every 30 s.
local follows = 0
for _, o in ipairs(orders) do if o[1] == "follow" then follows = follows + 1 end end
now = now + 31; api.update()
local after = 0
for _, o in ipairs(orders) do if o[1] == "follow" then after = after + 1 end end
check(after == follows + 2, "both escorts re-follow")

-- Adoption: a scavenger that exists before the mode is on is counted when the
-- adapter's enable runs; enabling again or re-adding it does not count it twice.
check(adapter and adapter.enable, "adapter has an enable hook")
enabled = false
spawn("pre", "avscav")
local scavs = env.M.pilot.scavengers
enabled = true
adapter.enable()
check(env.M.pilot.scavengers == scavs + 1, "pre-existing scavenger adopted on enable")
adapter.enable(); api.add("pre")
check(env.M.pilot.scavengers == scavs + 1, "no double count after a second enable or AddObject")

-- Rapid toggling: many off/on cycles with AddObject between them register
-- nothing twice and give no new placement orders.
check(adapter.disable, "adapter has a disable hook")
setfenv(env.PilotBranch.Release, env)
local o0 = #orders
for _ = 1, 50 do
    enabled = false; adapter.disable(); api.add("pre")
    enabled = true; adapter.enable(); api.add("pre")
end
check(env.M.pilot.scavengers == scavs + 1, "no double count after 50 toggles")
check(#orders == o0, "no new orders from 50 toggles")
check(env.M.pilot.nextSweep == 0, "disable re-arms the lock sweep at once")

-- Release: each locked order is re-issued at priority 0 (player-commandable);
-- the player and other teams are left alone.
do
    local saved = _G.AiCommand
    _G.AiCommand = { NONE = 0, SELECT = 1, FOLLOW = 5, GO = 3 }
    local B = assert(loadfile("Scripts/CRPilotBranch.lua"))()
    local renv = setmetatable({ AiCommand = _G.AiCommand }, { __index = env })
    local set = {}
    local craft = { player, "w1", "w2", "e1" }
    obj("w1", "avfigh"); objs.w1.cmd = 5
    obj("w2", "avfigh"); objs.w2.cmd = 3
    obj("e1", "svfigh", 2); objs.e1.cmd = 5
    renv.AllCraft = function() local i = 0; return function() i = i + 1; return craft[i] end end
    renv.SetCommand = function(h, c, p) set[#set + 1] = { h, c, p } end
    setfenv(B.Release, renv); setfenv(B.alive, renv)
    B.Release({ nextSweep = 9 })
    check(#set == 1 and set[1][1] == "w1" and set[1][2] == 5 and set[1][3] == 0,
        "Release re-issued only the lockable team-1 order, at priority 0")
    _G.AiCommand = saved
end

-- Disabled: AddObject leaves units alone.
enabled = false; n = #orders
spawn("off", "avturr")
check(#orders == n, "no orders while Pilot Mode is off")
print("misn05 Pilot Mode branch checks passed: " .. checks)
