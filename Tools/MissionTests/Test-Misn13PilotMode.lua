-- Execute misn13cr's N64 Pilot Mode branch (Pilot.AddObject/Pilot.Update) with stubbed natives:
-- build-queue order, turret spots, wingmen follow, pods, geyser orders and adoption.
local file = assert(io.open("Scripts/misn13cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("(local Pilot = {.-)\n%-%- N64 Pilot Mode branch end"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local now, scrap, pilots, enabled = 0, 100, 5, true
local objs, built, orders = {}, {}, {}
local function obj(name, odf, t) objs[name] = { odf = odf, team = t or 1, alive = true, deployed = false, busy = false, cmd = 0, health = 1, ammo = 1 }; return name end
local player = obj("player", "avtank")
local rec = obj("rec", "avrecy"); objs[rec].deployed = true
obj("cam1", "apcamr")
obj("eggeizr114_geyser", "eggeizr1", 0); obj("eggeizr112_geyser", "eggeizr1", 0)
local env = setmetatable({}, { __index = _G })
env.M = { nsdfrecycle = rec, nav1 = "cam1" }
env.AiCommand = { NONE = 0, GO = 3 }
env.CRCoop = { IsNetworkGame = function() return false end }
env.pcall = pcall
env.require = function(name)
    if name == "PlayerPilotMode" then
        return { IsEnabled = function() return enabled end,
                 Initialize = function(adapter, state) env.adapter, env.initState = adapter, state end,
                 Update = function() env.ticked = true end, Save = function() return { saved = true } end }
    elseif name == "CRPilotBranch" then
        local B = assert(loadfile("Scripts/CRPilotBranch.lua"))()
        for _, f in pairs(B) do if type(f) == "function" then setfenv(f, env) end end
        return B
    end
end
env.GetTime = function() return now end
env.GetPlayerHandle = function() return player end
env.GetHandle = function(l) return objs[l] and l end
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
env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
env.GetTerrainHeightAndNormal = function() return 20 end
env.SetObjectiveOn = function(h) orders[#orders + 1] = { "objective", h } end
env.Goto = function(h, t) orders[#orders + 1] = { "go_to", h, t }; objs[h].cmd = 3 end
env.Follow = function(h, t) orders[#orders + 1] = { "follow", h, t } end
env.Build = function(h, odf) built[#built + 1] = { odf, h }; objs[h].busy = true end
local chunk = assert(loadstring("local M = M\n" .. block .. "\nreturn Pilot"))
setfenv(chunk, env)
local Pilot = chunk()
local function spawn(name, odf) obj(name, odf); Pilot.AddObject(name) end
local function last() return built[#built] and built[#built][1] end
local function step() objs[rec].busy = false; if objs.fac then objs.fac.busy = false end; now = now + 1; Pilot.Update() end

Pilot.Init()
check(env.adapter and env.adapter.scripted == true and env.adapter.update == Pilot.Update, "scripted adapter")
check(Pilot.Save().saved and env.M.playerPilotModeState.saved, "Save keeps the PlayerPilotMode state")
Pilot.Tick(); check(env.ticked, "Tick drives PlayerPilotMode.Update")

-- First frame: nav 16 marked; the deployed recycler gets no geyser order; scavenger one queued with top-up.
scrap, pilots = 2, 0
Pilot.Update()
check(orders[1][1] == "objective" and orders[1][2] == "cam1", "nav marked")
check(#built == 1 and last() == "avscav" and scrap == 6 and pilots == 1, "scavenger after the scrap/pilot top-up")
check(#orders == 1, "deployed recycler is not sent to a geyser")

-- Queue: scavengers x2, factory, 4 turrets.
scrap, pilots = 100, 5
spawn("s1", "avscav"); step(); check(#built == 2 and last() == "avscav", "second scavenger")
spawn("s2", "avscav"); step(); check(last() == "avmuf" and #built == 3, "factory (n64p086) after two scavengers")
for i = 1, 4 do step(); check(last() == "avturr" and #built == 3 + i, "turret " .. i) end
local before = #built
step(); check(#built == before + 1 and last() == "avfigh", "no factory yet: the queue falls through to fighters")

-- Turret spots: the first to (3498, 97864), the rest to (3472, 97953).
spawn("t1", "avturr")
local o = orders[#orders]
check(o[1] == "go_to" and o[2] == "t1" and o[3].x == 3498 and o[3].z == 97864 and o[3].y == 20, "turret 1 spot")
spawn("t2", "avturr"); o = orders[#orders]
check(o[3].x == 3472 and o[3].z == 97953, "turret 2 spot")
spawn("t3", "avturr"); check(orders[#orders][3].x == 3472, "turret 3 spot")

-- Factory: goes to eggeizr112_geyser, re-sent after 6 s while undeployed; then the tank queue.
spawn("fac", "avmuf")
check(orders[#orders][2] == "fac" and orders[#orders][3] == "eggeizr112_geyser", "factory to its geyser")
local n = #orders
spawn("fac", "avmuf"); check(#orders == n, "no second order for the same factory")
objs.fac.cmd = 0
now = now + 1; Pilot.Update(); now = now + 7; Pilot.Update()
check(orders[#orders][2] == "fac" and orders[#orders][3] == "eggeizr112_geyser" and #orders == n + 1, "factory re-sent once")
objs.fac.deployed = true
for _ = 1, 2 do objs.rec.busy = false end
before = #built; step()
check(last() == "avtank" and built[#built][2] == "fac" and #built == before + 1, "tank from the factory")
spawn("tk1", "avtank"); check(orders[#orders][1] == "follow" and orders[#orders][2] == "tk1" and orders[#orders][3] == player, "tank 1 follows")
step(); check(last() == "avtank", "second tank")
spawn("tk2", "avtank")
before = #built; step(); check(last() == "avfigh" and #built == before + 1, "fighters once both tanks stand")
spawn("f1", "avfigh"); check(orders[#orders][1] == "follow" and orders[#orders][2] == "f1", "fighter follows")

-- Rebuild: a lost tank is replaced.
objs.tk1.alive = false
before = #built; step(); check(last() == "avtank" and #built == before + 1, "lost tank rebuilt")

-- Wingmen follow every 30 s.
n = #orders
now = now + 31; Pilot.Update()
local follows = 0
for i = n + 1, #orders do if orders[i][1] == "follow" and orders[i][3] == player then follows = follows + 1 end end
check(follows == 2, "regroup after 30 s: " .. follows)

-- Pods: a hurt player makes the recycler build a repair pod, then an ammo pod.
objs.player.health, objs.player.ammo = 0.5, 0.5
for _ = 1, 4 do
    for _, id in ipairs({ "tk1" }) do end
    objs.rec.busy = false; now = now + 1; Pilot.Update()
end
local podOdfs = {}
for _, b in ipairs(built) do if b[1] == "naprepa" or b[1] == "napammo" then podOdfs[#podOdfs + 1] = b[1] end end
check(podOdfs[1] == "naprepa" and podOdfs[2] == "napammo" and #podOdfs == 2, "repair then ammo pod, one each")

-- Adoption: pre-existing units (fresh branch state, as after a load) are adopted once.
do
    objs.fac.alive = false
    env.M.pilot = nil
    enabled = false
    spawn("pf", "avmuf"); objs.pf.deployed = true; spawn("pt", "avturr")
    enabled = true
    Pilot.Init(); env.adapter.enable()
    local P = env.M.pilot
    check(P.factory == "pf" and P.factoryQueued == true, "factory adopted on enable")
    local count = P.turrets
    env.adapter.enable(); Pilot.AddObject("pt")
    check(P.turrets == count, "no double registration")
    n = #orders
    env.adapter.disable(); env.adapter.enable()
    check(#orders == n, "disable/enable issues no placement orders")
end

-- Off / enemy.
enabled = false; n = #orders
spawn("off", "avturr")
check(#orders == n, "no orders while Pilot Mode is off")
enabled = true
obj("foe", "avturr", 5); Pilot.AddObject("foe")
check(#orders == n, "enemy turret ignored")
print("misn13 Pilot Mode branch checks passed: " .. checks)
