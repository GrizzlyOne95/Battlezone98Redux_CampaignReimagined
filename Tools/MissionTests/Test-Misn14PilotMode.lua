-- Execute misn14cr's N64 Pilot Mode branch (Pilot.AddObject/Pilot.Update) with stubbed natives:
-- build-queue order, turret spots, APC/tank follow, rescue-beacon events, geysers and adoption.
local file = assert(io.open("Scripts/misn14cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("(local Pilot = {.-)\n%-%- N64 Pilot Mode branch end"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local now, scrap, pilots, enabled = 0, 100, 5, true
local objs, built, orders = {}, {}, {}
local function obj(name, odf, t) objs[name] = { odf = odf, team = t or 1, alive = true, deployed = false, busy = false, cmd = 0, health = 1, ammo = 1 }; return name end
local player = obj("player", "avtank")
local rec = obj("rec", "avrecy"); objs[rec].deployed = true
local geysers = { eggeizr116_geyser = 5, eggeizr117_geyser = 40, eggeizr118_geyser = 25 }
for g in pairs(geysers) do obj(g, "eggeizr1", 0) end
local env = setmetatable({}, { __index = _G })
env.NEVER = 99999.0
env.M = { recy = rec, rescue1 = false, rescue2 = false, rescue3 = false,
    rescue_finish1 = 99999.0, rescue_finish2 = 99999.0, rescue_finish3 = 99999.0 }
env.AiCommand = { NONE = 0, GO = 3 }
env.CRCoop = { IsNetworkGame = function() return false end }
env.pcall = pcall
env.require = function(name)
    if name == "PlayerPilotMode" then
        return { IsEnabled = function() return enabled end,
                 Initialize = function(adapter, state) env.adapter, env.initState = adapter, state end,
                 Update = function() env.ticked = true end, Save = function() return { saved = true } end }
    elseif name == "CRPilotBranch" then
        local B = setfenv(assert(loadfile("Scripts/CRPilotBranch.lua")), env)()
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
env.GetDistance = function(a, b) return geysers[b] or 500 end
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
env.Goto = function(h, t) orders[#orders + 1] = { "go_to", h, t }; objs[h].cmd = 3 end
env.Follow = function(h, t) orders[#orders + 1] = { "follow", h, t } end
env.Build = function(h, odf) built[#built + 1] = { odf, h }; objs[h].busy = true end
local chunk = assert(loadstring("local M = M\nlocal NEVER = NEVER\n" .. block .. "\nreturn Pilot"))
setfenv(chunk, env)
local Pilot = chunk()
local function spawn(name, odf) obj(name, odf); Pilot.AddObject(name) end
local function last() return built[#built] and built[#built][1] end
local function step() objs[rec].busy = false; if objs.fac then objs.fac.busy = false end; now = now + 1; Pilot.Update() end

Pilot.Init()
check(env.adapter and env.adapter.scripted == true and env.adapter.update == Pilot.Update, "scripted adapter")
check(Pilot.Save().saved and env.M.pilotModeSaved.saved, "Save keeps the PlayerPilotMode state")
Pilot.Tick(); check(env.ticked, "Tick drives PlayerPilotMode.Update")

-- Queue: scavengers x2 (with top-up), factory, 2 turrets.
scrap, pilots = 2, 0
Pilot.Update()
check(#built == 1 and last() == "avscav" and scrap == 6 and pilots == 1, "scavenger after the top-up")
check(#orders == 0, "deployed recycler gets no geyser order")
scrap, pilots = 100, 5
spawn("s1", "avscav"); step(); check(#built == 2 and last() == "avscav", "second scavenger")
spawn("s2", "avscav"); step(); check(last() == "avmuf" and #built == 3, "factory (n64p087) after two scavengers")
step(); check(last() == "avturr" and #built == 4, "turret 1")
step(); check(last() == "avturr" and #built == 5, "turret 2")
local before = #built
step(); check(#built == before, "nothing until the factory exists")

-- Turret spots.
spawn("t1", "avturr")
local o = orders[#orders]
check(o[1] == "go_to" and o[3].x == 2489 and o[3].z == 99475 and o[3].y == 20, "turret 1 spot")
spawn("t2", "avturr"); check(orders[#orders][3].x == 2686 and orders[#orders][3].z == 99509, "turret 2 spot")

-- Factory: sent to the nearest geyser the recycler is not on (116 is 5 m away -> 118 at 25 m), re-sent after 6 s.
spawn("fac", "avmuf")
local n = #orders
now = now + 1; Pilot.Update(); now = now + 7; Pilot.Update()
check(#orders == n + 1 and orders[#orders][2] == "fac" and orders[#orders][3] == "eggeizr118_geyser", "factory to a free geyser")
objs.fac.deployed = true

-- Factory queue: APC first (none alive), then tanks.
before = #built; step()
check(last() == "avapc" and built[#built][2] == "fac" and #built == before + 1, "APC from the factory")
spawn("apc", "avapc")
check(orders[#orders][1] == "follow" and orders[#orders][2] == "apc" and orders[#orders][3] == player, "APC follows")
step(); check(last() == "avtank", "tank 1")
spawn("tk1", "avtank"); check(orders[#orders][1] == "follow" and orders[#orders][2] == "tk1", "tank follows")
step(); check(last() == "avtank", "tank 2")
spawn("tk2", "avtank")
before = #built; step(); check(#built == before, "queue empty once the squad stands")

-- Rescue-beacon event: the APC follows the player when a beacon's rescue timer ends.
n = #orders
env.M.rescue1, env.M.rescue_finish1 = true, now + 25
Pilot.Update(); check(#orders == n, "rescue running: no event yet")
env.M.rescue_finish1 = 99999.0
Pilot.Update()
check(orders[#orders][1] == "follow" and orders[#orders][2] == "apc" and orders[#orders][3] == player, "APC follows at the rescue event")
n = #orders; Pilot.Update(); check(#orders == n, "the event fires once")

-- Wingmen follow every 30 s.
n = #orders; now = now + 31; Pilot.Update()
local follows = 0
for i = n + 1, #orders do if orders[i][1] == "follow" then follows = follows + 1 end end
check(follows == 3, "regroup after 30 s: " .. follows)

-- A lost APC is rebuilt.
objs.apc.alive = false
before = #built; step(); check(last() == "avapc" and #built == before + 1, "lost APC rebuilt")

-- Adoption without duplicates.
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

enabled = false; n = #orders
spawn("off", "avturr")
check(#orders == n, "no orders while Pilot Mode is off")
enabled = true
obj("foe", "avturr", 5); Pilot.AddObject("foe")
check(#orders == n, "enemy turret ignored")
print("misn14 Pilot Mode branch checks passed: " .. checks)
