-- Execute misn07cr's N64 Pilot Mode branch (PilotUpdate/PilotAddObject) with
-- stubbed natives: start orders, build-queue order, turret and howitzer
-- placement, wingman follow orders, armory pods, and the disabled case.
local file = assert(io.open("Scripts/misn07cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("(local PILOT_WING_SPOTS =.-)\n%-%- CR Pilot Mode <<"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local now, scrap, pilots, enabled = 0, 100, 5, true
local objs, built, orders = {}, {}, {}
local dists = {}
local before
local function obj(name, odf, t) objs[name] = { odf = odf, team = t or 1, alive = true, deployed = false, busy = false, health = 1, ammo = 1, cmd = 0 }; return name end
local player = obj("player", "avtank")
local slf = obj("avslf", "avsl7")
local rec = obj("rec", "avrec7"); local fac = obj("fac", "avmu7")
local power, svrec = obj("power", "sblpow", 2), obj("svrec", "svrecy", 2)
local geyserSlf = obj("eggeizr1238_geyser", "eggeizr1", 0)
local geyserRec, geyserFac = obj("recycle_spawn_geyz", "eggeizr1", 0), obj("show_geyser", "eggeizr1", 0)
local t1, t2 = obj("avturret1", "avturr"), obj("avturret2", "avturr")
local tank1, tank2 = obj("new_tank1", "avtank"), obj("new_tank2", "avtank")
local nav1, nav3, nav6, nav7 = obj("nav1", "apcamr"), obj("nav3", "apcamr"), obj("nav6", "apcamr"), obj("nav7", "apcamr")

local env = setmetatable({}, { __index = _G })
env.M = { nsdfarmory = slf, wingturret1 = t1, wingturret2 = t2, nav1 = nav1, nav3 = nav3, nav6 = nav6, nav7 = nav7,
          powrplnt1 = power, ccarecycle = svrec, spawn_point = geyserRec, show_geyser = geyserFac }
env.AiCommand = { NONE = 0, GO = 3 }
env.GetTime = function() return now end
env.GetPlayerHandle = function() return player end
env.GetHandle = function(l) return objs[l] and l or nil end
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
env.GetCurrentCommand = function(h) return objs[h].cmd end
env.GetCurrentWho = function() return nil end
env.GetDistance = function(a, b) return dists[a .. ">" .. b] or 1e9 end
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
env.SetObjectiveOn = function(h) orders[#orders + 1] = { "objective", h } end
env.SetUserTarget = function(h) orders[#orders + 1] = { "target", h } end
env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
env.GetTerrainHeightAndNormal = function() return 7 end
env.Goto = function(h, t, p) orders[#orders + 1] = { "go_to", h, t, p }; if objs[h] then objs[h].cmd = 3 end end
env.Follow = function(h, t) orders[#orders + 1] = { "follow", h, t } end
env.Attack = function(h, t) orders[#orders + 1] = { "attack", h, t } end
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
for _, fn in ipairs({ "Lock", "Ready", "Resend", "FollowPlayer", "TryBuild", "alive", "Adopt" }) do setfenv(env.PilotBranch[fn], env) end
local chunk = assert(loadstring("local M, PlayerPilotMode, PilotBranch = M, PlayerPilotMode, PilotBranch\n" .. block ..
    "\nreturn { update = PilotUpdate, add = PilotAddObject, init = InitializePilotMode }"))
setfenv(chunk, env)
local api = chunk()
api.init()
local function spawn(name, odf) obj(name, odf); api.add(name) end
local function find(kind, h)
    for _, o in ipairs(orders) do if o[1] == kind and o[2] == h then return o end end
end
local function count(kind, h)
    local n = 0
    for _, o in ipairs(orders) do if o[1] == kind and (h == nil or o[2] == h) then n = n + 1 end end
    return n
end

-- Start: armory to its geyser, wing turrets to their spots (CR: priority 1, re-sent by KeepSpots).
api.update()
local o = find("go_to", slf)
check(o and o[3] == geyserSlf and o[4] == 1, "armory sent to eggeizr1238_geyser")
o = find("go_to", t1)
check(o and o[3].x == 2033 and o[3].z == 97882 and o[3].y == 7 and o[4] == 1, "wing turret 1 spot")
o = find("go_to", t2)
check(o and o[3].x == 2015 and o[3].z == 97837 and o[4] == 1, "wing turret 2 spot")
check(count("target") == 0, "no user target before the 9 s intro")
now = 10; api.update()
check(find("target", nav3), "intro target is the rendezvous cam")
check(#built == 0, "nothing built before the Utah arrives")

-- Armory re-send: an undeployed armory knocked off GO gets Goto again after 6 s.
objs[slf].cmd = 0; local n = count("go_to", slf)
now = 11; api.update(); now = 18; api.update()
check(count("go_to", slf) == n + 1, "armory re-sent to its geyser")

-- Rendezvous: the replacement tanks follow the player, then the armory at the cam.
env.M.rendezvous, env.M.new_tank1, env.M.new_tank2 = true, tank1, tank2
now = 19; api.update()
check(find("target", nav1), "outpost cam becomes the user target")
check(count("follow", tank1) == 1 and find("follow", tank1)[3] == player, "tank 1 follows the player")
check(find("follow", tank2)[3] == player, "tank 2 follows the player")
now = 40; api.update()
check(count("follow", tank1) == 1, "tanks keep following the player while far from the cam")
dists["player>nav1"] = 60
now = 45; api.update()
local lastFollow
for _, x in ipairs(orders) do if x[1] == "follow" and x[2] == tank1 then lastFollow = x end end
check(count("follow", tank1) == 2 and lastFollow[3] == slf, "tanks follow the armory at the cam")
check(count("follow", tank2) == 2, "second tank follows the armory")

-- The Utah arrives: base cam target, recycler and factory to their geysers.
env.M.next_mission, env.M.nsdfrecycle, env.M.nsdfmuf = true, rec, fac
now = 50; api.update()
check(find("target", nav6), "base cam becomes the user target")
check(find("go_to", rec)[3] == geyserRec and find("go_to", fac)[3] == geyserFac, "recycler and factory sent to geysers")
check(#built == 0, "undeployed recycler builds nothing")
objs[rec].cmd = 0; n = count("go_to", rec)
now = 51; api.update(); now = 58; api.update()
check(count("go_to", rec) == n + 1, "recycler re-sent to its geyser")

-- Queue: scavenger x2 (scrap and pilots topped up), turret x4, avartl.
objs[rec].deployed, objs[fac].deployed, objs[slf].deployed = true, true, true
scrap, pilots = 0, 0
now = 60; api.update()
check(built[#built] == "avscav" and scrap == 4 and pilots == 1, "first scavenger after a scrap and pilot top-up")
spawn("s1", "avscav"); objs[rec].busy = false
now = 61; api.update()
check(built[#built] == "avscav" and #built == 2, "second scavenger")
spawn("s2", "avscav"); objs[rec].busy = false
scrap = 100
local spots = { { 2232, 100262 }, { 2228, 100211 }, { 2252, 100081 }, { 2306, 100083 } }
for i = 1, 4 do
    now = now + 1; api.update()
    check(built[#built] == "avturr" and #built == 2 + i, "turret " .. i)
    spawn("u" .. i, "avturr"); objs[rec].busy = false
    o = find("go_to", "u" .. i)
    check(o[3].x == spots[i][1] and o[3].z == spots[i][2] and o[4] == 1, "turret " .. i .. " spot")
end
before = #built
now = now + 1; api.update()
check(built[#built] == "avartl" and #built == 7, "first howitzer from the factory")
check(find("go_to", "u4") and count("go_to", "u4") == 1, "no fifth turret order")
spawn("how1", "avartl"); objs[fac].busy = false
o = find("go_to", "how1")
check(o[3].x == 2466 and o[3].z == 99919 and o[4] == 1, "howitzer 1 to its spot")
check(find("objective", "how1"), "howitzer marked")
before = #built; now = now + 1; api.update()
check(#built == before, "queue idles while the power plant stands")

-- Howitzer 1 deployed: attacks the power plant.
objs.how1.deployed = true
now = now + 1; api.update()
o = find("attack", "how1")
check(o and o[3] == power, "howitzer 1 attacks the power plant")

-- Power plant lost: second howitzer, then the light tank.
objs[power].alive = false
now = now + 1; api.update() -- the loss is noted after the queue ran, as in the C
now = now + 1; api.update()
check(built[#built] == "avartl" and #built == before + 1, "second howitzer after the plant falls")
spawn("how2", "avartl"); objs[fac].busy = false
check(count("go_to", "how2") == 0, "howitzer 2 gets no spot order")
now = now + 1; api.update()
check(built[#built] == "avltnk", "light tank last")
objs.how1.deployed = false
spawn("lt", "avltnk")
check(find("follow", "lt")[3] == "how2", "light tank follows howitzer 2")
local g2, g1 = find("go_to", "how2"), find("go_to", "how1")
check(g2[3].x == 3159 and g2[4] == 1, "howitzer 2 takes route 18")
check(orders[#orders][1] == "go_to" and orders[#orders][2] == "how1" and orders[#orders][3].x == 3156, "howitzer 1 takes route 16")
before = #built; now = now + 1; api.update()
check(#built == before, "queue complete")
objs.how1.deployed, objs.how2.deployed = true, true
now = now + 1; api.update()
local a1, a2 = nil, nil
for _, x in ipairs(orders) do
    if x[1] == "attack" and x[3] == svrec then if x[2] == "how1" then a1 = x else a2 = x end end
end
check(a1 and a2, "both howitzers attack the Soviet recycler once deployed")

-- Supply: hurt and dry player gets pods from the armory, 3 s apart, ammo first.
objs[player].health, objs[player].ammo = 0.5, 0.5
now = now + 1; api.update()
check(built[#built] == "napammo@player", "ammo pod via armory BuildAt")
before = #built; now = now + 1; api.update()
check(#built == before, "3 s cooldown between pods")
for _ = 1, 3 do now = now + 3.5; api.update() end
local pods = {}
for i = before, #built do pods[#pods + 1] = built[i] end
check(table.concat(pods, ",") == "napammo@player,napammo@player,naprepa@player,naprepa@player", "two ammo then two repair pods: " .. table.concat(pods, ","))
spawn("a1", "napammo"); spawn("a2", "napammo"); spawn("r1", "naprepa"); spawn("r2", "naprepa")
check(find("objective", "a1") and find("objective", "r2"), "pods marked")
before = #built; now = now + 10; api.update()
check(#built == before, "four live pods: no more requested")

-- Adoption: a howitzer that exists before the mode is on is registered when the
-- adapter's enable runs; enabling again or re-adding it does not register it twice.
check(adapter and adapter.enable, "adapter has an enable hook")
do
    enabled = false
    spawn("pre_how", "avartl")
    check(count("objective", "pre_how") == 0, "no order while off")
    local howitzers = env.M.pilot.howitzers
    enabled = true
    adapter.enable()
    check(env.M.pilot.howitzers == howitzers + 1 and count("objective", "pre_how") == 1, "pre-existing howitzer adopted on enable")
    local total = #orders
    adapter.enable(); api.add("pre_how")
    check(env.M.pilot.howitzers == howitzers + 1 and #orders == total, "no double registration after a second enable or AddObject")
end

-- Disabled: AddObject leaves units alone and the update path is not driven.
enabled = false; n = #orders
spawn("off", "avturr")
check(#orders == n, "no orders while Pilot Mode is off")
print("misn07 Pilot Mode branch checks passed: " .. checks)
