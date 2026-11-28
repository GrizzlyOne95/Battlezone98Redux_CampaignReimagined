-- Execute misn10cr's N64 Pilot Mode branch (Pilot.AddObject/Pilot.Update) with
-- stubbed natives: build-queue order, turret path, tug orders, factory deploy.
local file = assert(io.open("Scripts/misn10cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("(local Pilot = {.-)\n%-%- N64 Pilot Mode branch end"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local now, scrap, pilots, enabled = 0, 100, 5, true
local objs, built, orders, positions = {}, {}, {}, {}
local function obj(name, odf, t) objs[name] = { odf = odf, team = t or 1, alive = true, deployed = false, busy = false, cmd = 0 }; return name end
local player = obj("player", "avtank")
local rec = obj("rec", "avrecy"); objs[rec].deployed = true
obj("relic", "hvsrb", 0); obj("cam1", "apcamr"); obj("cam3", "apcamr")
local geysers = { eggeizr136_geyser = 5, eggeizr144_geyser = 40, eggeizr152_geyser = 25, eggeizr160_geyser = 60 }
for label in pairs(geysers) do obj(label, "eggeizr1", 0) end
local dist = { }
local env = setmetatable({}, { __index = _G })
env.M = { nsdfrecycle = rec, nav1 = "cam1", nav3 = "cam3", sav = "relic", sav_free = true, sav_secure = false }
env.AiCommand = { NONE = 0, GO = 3, FOLLOW = 5, PICKUP = 7 }
env.GetTug = function(h) return objs[h] and objs[h].tug end
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
env.GetScrap = function() return scrap end
env.AddScrap = function(_, n) scrap = scrap + n end
env.GetPilot = function() return pilots end
env.AddPilot = function(_, n) pilots = pilots + n end
env.GetDistance = function(a, b)
    if dist[a .. ">" .. b] then return dist[a .. ">" .. b] end
    return geysers[b] or 500
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
env.SetObjectiveOn = function(h) orders[#orders + 1] = { "objective", h } end
env.Goto = function(h, t) orders[#orders + 1] = { "go_to", h, t }; objs[h].cmd = 3 end
env.Follow = function(h, t) orders[#orders + 1] = { "follow", h, t }; objs[h].cmd = 5 end
env.Pickup = function(h, t) orders[#orders + 1] = { "pickup", h, t }; objs[h].cmd = 7 end
env.Build = function(h, odf) built[#built + 1] = odf; objs[h].busy = true end
local chunk = assert(loadstring("local M = M\n" .. block .. "\nreturn Pilot"))
setfenv(chunk, env)
local Pilot = chunk()
local function spawn(name, odf) obj(name, odf); Pilot.AddObject(name) end
local function finish() objs[rec].busy = false end

-- Init hands the scripted adapter to PlayerPilotMode (no aiCore).
Pilot.Init()
check(env.adapter and env.adapter.scripted == true and env.adapter.update == Pilot.Update, "scripted adapter")
check(Pilot.Save().saved and env.M.playerPilotModeState.saved, "Save keeps the PlayerPilotMode state")
Pilot.Tick(); check(env.ticked, "Tick drives PlayerPilotMode.Update")

-- First frame: navcams 1 and 3 become objectives; no scavengers yet, so scavenger one is queued
-- with the AddScrap/AddPilot top-ups.
scrap, pilots = 2, 0
Pilot.Update()
check(orders[1][1] == "objective" and orders[1][2] == "cam1" and orders[2][2] == "cam3", "navcam objectives")
check(built[1] == "avscav" and scrap == 6 and pilots == 1, "scavenger built after the scrap/pilot top-up")
check(#built == 1, "one build per frame")

-- Queue: scavenger, scavenger, factory, turret, turret.
scrap, pilots = 100, 5
spawn("s1", "avscav"); finish(); now = now + 1; Pilot.Update()
check(#built == 2 and built[2] == "avscav", "second scavenger while one is missing")
spawn("s2", "avscav"); finish(); now = now + 1; Pilot.Update()
check(built[#built] == "avmuf" and #built == 3, "factory (n64p085) after two scavengers")
finish(); now = now + 1; Pilot.Update()
check(built[#built] == "avturr" and #built == 4, "first turret"); finish()
now = now + 1; Pilot.Update(); check(built[#built] == "avturr" and #built == 5, "second turret"); finish()
local before = #built
now = now + 1; Pilot.Update()
check(#built == before, "no tug until the factory exists")
-- A dead scavenger is replaced (the chain restarts at its first item).
objs.s1.alive = false
now = now + 1; Pilot.Update()
check(built[#built] == "avscav" and #built == before + 1, "replacement scavenger"); finish()
spawn("s3", "avscav")

-- Turrets go to path(3).
spawn("t1", "avturr")
check(orders[#orders][1] == "go_to" and orders[#orders][2] == "t1" and orders[#orders][3] == "main_return_path", "turret path")

-- Factory: sent to the nearest base geyser Utah is not sitting on (136 is 5 m away), re-sent after 6 s.
spawn("fac", "avmuf")
local n = #orders
now = now + 1; Pilot.Update(); now = now + 7; Pilot.Update()
check(#orders == n + 1 and orders[#orders][2] == "fac" and orders[#orders][3] == "eggeizr152_geyser", "factory to the nearest free geyser")
objs.fac.deployed = true
before = #built; now = now + 1; Pilot.Update()
check(built[#built] == "avhaul" and #built == before + 1, "tug built from the deployed factory")
objs.fac.busy = false; now = now + 1; Pilot.Update()
check(#built == before + 1, "the tug is only built once")

-- Tug: follows the player when built, picks the relic up within 100 m, follows home once secured.
-- CR adaptation: the Follow(player) is sent by Pilot.Update (re-sent every 10 s), not by AddObject.
spawn("tug", "avhaul")
check(orders[#orders][1] == "objective" and orders[#orders][2] == "tug", "tug marked")
Pilot.Update()
check(orders[#orders][1] == "follow" and orders[#orders][2] == "tug" and orders[#orders][3] == player, "tug follows the player")
n = #orders; Pilot.Update(); check(#orders == n, "tug far from the relic: no pickup")
objs.tug.cmd = 0; now = now + 5; Pilot.Update(); check(#orders == n, "a dropped Follow is not re-sent before 10 s")
now = now + 6; Pilot.Update(); check(orders[#orders][1] == "follow" and #orders == n + 1, "a dropped Follow is re-sent after 10 s")
dist["tug>relic"] = 60
Pilot.Update(); check(orders[#orders][1] == "pickup" and orders[#orders][2] == "tug" and orders[#orders][3] == "relic", "pickup within 100 m")
n = #orders; Pilot.Update(); check(#orders == n, "pickup once while the tug obeys it")
objs.tug.cmd = 0; now = now + 11; Pilot.Update()
check(orders[#orders][1] == "pickup" and #orders == n + 1, "a dropped Pickup is re-sent after 10 s")
objs.relic.tug = "tug"; objs.tug.cmd = 0; n = #orders
now = now + 11; Pilot.Update(); check(#orders == n, "no more Pickups once the tug holds the relic")
env.M.sav_free, env.M.sav_secure = false, true
Pilot.Update(); check(orders[#orders][1] == "follow" and orders[#orders][3] == player, "tug follows the player once secured")

-- Adoption: a factory that exists before the mode is on (fresh branch state, as
-- after a load) is adopted when the adapter's enable runs; no second factory is
-- built and a second enable does not duplicate slots.
do
    objs.fac.alive = false
    env.M.pilot = nil
    enabled = false
    spawn("pfac", "avmuf"); objs.pfac.deployed = true
    enabled = true
    Pilot.Init()
    check(env.adapter.enable ~= nil, "adapter has an enable hook")
    env.adapter.enable()
    local P = env.M.pilot
    check(P.factory == "pfac" and P.factoryBuilt == true, "pre-existing factory adopted on enable")
    local s1, s2 = P.scav1, P.scav2
    check(s1 ~= nil and s2 ~= nil and s1 ~= s2, "scavenger slots filled with two units")
    env.adapter.enable(); Pilot.AddObject("pfac")
    check(P.factory == "pfac" and P.scav1 == s1 and P.scav2 == s2, "no duplicate slots after a second enable or AddObject")
    scrap, pilots = 100, 5
    local first = #built
    for _ = 1, 4 do finish(); now = now + 1; Pilot.Update() end
    for i = first + 1, #built do check(built[i] ~= "avmuf", "no second factory built") end
end

-- Disabled: AddObject leaves units alone; enemy-team objects are ignored.
enabled = false; n = #orders
spawn("off", "avturr")
check(#orders == n, "no orders while Pilot Mode is off")
enabled = true
obj("foe", "avturr", 5); Pilot.AddObject("foe")
check(#orders == n, "enemy turret ignored")
print("misn10 Pilot Mode branch checks passed: " .. checks)
