-- Execute misn11cr's N64 Pilot Mode branch (Pilot.AddObject/Pilot.Update) with
-- stubbed natives: wingmen follow (start, craft change, every 30 s), the armory's
-- three ammo then three repair pods after the first transport reaches check2, adoption.
local file = assert(io.open("Scripts/misn11cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("(local Pilot = {.-)\n%-%- N64 Pilot Mode branch end"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local now, scrap, enabled = 0, 100, true
local objs, built, orders = {}, {}, {}
local function obj(name, odf, t) objs[name] = { odf = odf, team = t or 1, alive = true, deployed = false, busy = false, cmd = 0 }; return name end
local player = obj("player", "avhover")
local slf = obj("avslf0_armory", "avslf"); objs[slf].deployed = true
local env = setmetatable({}, { __index = _G })
env.M = { check2 = false }
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
env.Follow = function(h, t, p) orders[#orders + 1] = { "follow", h, t, p } end
env.BuildAt = function(h, odf, t, p) built[#built + 1] = odf; orders[#orders + 1] = { "buildat", h, odf, t, p }; objs[h].busy = true end
local chunk = assert(loadstring("local M = M\n" .. block .. "\nreturn Pilot"))
setfenv(chunk, env)
local Pilot = chunk()
local function spawn(name, odf) obj(name, odf); Pilot.AddObject(name) end
local function count(kind, who)
    local n = 0
    for _, o in ipairs(orders) do if o[1] == kind and (who == nil or o[2] == who) then n = n + 1 end end
    return n
end

-- Init hands the scripted adapter to PlayerPilotMode (no aiCore).
Pilot.Init()
check(env.adapter and env.adapter.scripted == true and env.adapter.update == Pilot.Update, "scripted adapter")
check(Pilot.Save().saved and env.M.playerPilotModeState.saved, "Save keeps the PlayerPilotMode state")
Pilot.Tick(); check(env.ticked, "Tick drives PlayerPilotMode.Update")

-- The three wingmen follow the player when registered; a fourth tank and other ODFs are ignored.
spawn("lt", "avltnk"); spawn("t1", "avtank"); spawn("t2", "avtank")
check(count("follow") == 3 and orders[1][3] == player and orders[1][4] == 1, "three wingmen follow at priority 1")
spawn("t3", "avtank"); check(count("follow") == 3, "only three escorts")
spawn("tug", "avhaul"); check(count("follow") == 3, "tugs are not escorts")
Pilot.AddObject("lt"); check(count("follow") == 3, "no duplicate registration")

-- First frame: escorts follow again (C 96-98); then every 30 s and on a craft change.
Pilot.Update()
check(count("follow") == 6, "start follow")
check(#built == 0, "no pods before the first transport reaches check2")
now = 10; Pilot.Update(); check(count("follow") == 6, "no re-follow before 30 s")
now = 31; Pilot.Update(); check(count("follow") == 9, "re-follow after 30 s")
obj("player2", "avhover"); player = "player2"
now = 32; Pilot.Update(); check(count("follow") == 12 and orders[#orders][3] == "player2", "re-follow on a craft change")

-- check2 arms three ammo then three repair pods, one every 3 s, via the armory.
env.M.check2 = true
now = 40; Pilot.Update()
check(#built == 1 and built[1] == "napammo" and orders[#orders][2] == "avslf0_armory" and orders[#orders][4] == "player2", "first pod is ammo, aimed at the player")
objs[slf].busy = false
now = 41; Pilot.Update(); check(#built == 1, "3 s gap between pods")
for t = 44, 60, 4 do objs[slf].busy = false; now = t; Pilot.Update() end
check(#built == 6, "six pods in all")
check(built[1] == "napammo" and built[2] == "napammo" and built[3] == "napammo" and built[4] == "naprepa" and built[6] == "naprepa", "ammo first, then repair")
objs[slf].busy = false; now = 80; Pilot.Update(); check(#built == 6, "no pods beyond three of each")
-- Busy armory or no scrap holds the next pod.
env.M.pilot.reloadLeft = 1; scrap = 0; now = 90; Pilot.Update(); check(#built == 6, "no scrap, no pod")
scrap = 100; objs[slf].busy = true; Pilot.Update(); check(#built == 6, "busy armory waits")
objs[slf].busy = false; Pilot.Update(); check(#built == 7 and built[7] == "napammo", "pod once ready")

-- Adoption: wingmen that exist before the mode is on (fresh state, as after a load) are adopted on
-- enable; a second enable or AddObject does not register or order them twice.
do
    objs.lt.alive, objs.t1.alive, objs.t2.alive, objs.t3.alive = false, false, false, false
    env.M.pilot = nil
    enabled = false
    spawn("a1", "avtank"); spawn("a2", "avtank"); spawn("a3", "avltnk")
    enabled = true
    Pilot.Init()
    env.adapter.enable()
    local P = env.M.pilot
    check(#P.escorts == 3, "pre-existing wingmen adopted on enable")
    local n = count("follow")
    env.adapter.enable(); Pilot.AddObject("a1")
    check(#P.escorts == 3 and count("follow") == n, "no duplicate registration after a second enable")
    -- disable/enable cycles issue no pod orders
    local pods = #built
    env.adapter.disable(); env.adapter.enable()
    check(#built == pods, "toggle cycles issue no pod orders")
end

-- Disabled: AddObject leaves units alone; enemy-team objects are ignored.
enabled = false
local n = count("follow")
spawn("off", "avtank")
check(count("follow") == n, "no orders while Pilot Mode is off")
enabled = true
obj("foe", "svtank", 2); Pilot.AddObject("foe")
check(count("follow") == n, "enemy ignored")
print("misn11 Pilot Mode branch checks passed: " .. checks)
