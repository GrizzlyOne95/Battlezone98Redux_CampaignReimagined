-- Execute misns4cr's N64 Pilot Mode branch (PilotUpdate/PilotAddObject) with
-- stubbed natives: the recycler queue, the armory's geyser, fighter follows,
-- the bridge supply pods, adoption on enable and off/on cycles.
local file = assert(io.open("Scripts/misns4cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("%-%- CR pilot mode >>\n(.-)\n%-%- CR pilot mode <<"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end
check(source:find("pilotMode = PilotAdapter", 1, true), "the runtime config hands over the adapter")

local now, scrap, pilots = 0, 100, 30
local objs, built, orders = {}, {}, {}
local function obj(name, odf, x, team)
    objs[name] = { odf = odf, team = team or 1, alive = true, x = x or 0, deployed = false, busy = false, cmd = 0 }
    return name
end
local player = obj("player", "svtank")
local rec = obj("svrecy0_recycler", "svrecy")
obj("cam1", "spcamr")
-- Seven geysers; the armory is built next to the third.
for i = 12, 18 do obj("eggeizr" .. i .. "_geyser", "eggeizr1", (i - 12) * 100, 0) end

local env = setmetatable({}, { __index = _G })
env.M = { start_done = true, cam1 = "cam1", warning = false }
env.AiCommand = { NONE = 0, GO = 3, FOLLOW = 5 }
env.GetTime = function() return now end
env.GetPlayerHandle = function() return player end
env.GetHandle = function(n) return objs[n] and n or nil end
env.IsAlive = function(h) return objs[h] ~= nil and objs[h].alive end
env.IsValid = function(h) return objs[h] ~= nil and objs[h].alive end
env.IsDeployed = function(h) return objs[h].deployed end
env.IsBusy = function(h) return objs[h].busy end
env.IsOdf = function(h, odf) return objs[h].odf == odf end
env.GetTeamNum = function(h) return objs[h].team end
env.GetScrap = function() return scrap end
env.GetPilot = function() return pilots end
env.GetCurrentCommand = function(h) return objs[h].cmd end
env.GetCurrentWho = function() return nil end
env.GetDistance = function(a, b) return math.abs(objs[a].x - objs[b].x) end
env.AllCraft = function() return function() return nil end end
env.AllObjects = function()
    local names = {}
    for k, o in pairs(objs) do if o.alive then names[#names + 1] = k end end
    table.sort(names)
    local i = 0
    return function() i = i + 1; return names[i] end
end
env.SetCommand = function() end
env.SetUserTarget = function(h) orders[#orders + 1] = { "target", h } end
env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
env.GetTerrainHeightAndNormal = function() return 7 end
env.Goto = function(h, t) orders[#orders + 1] = { "go_to", h, t }; objs[h].cmd = 3 end
env.Follow = function(h, t) orders[#orders + 1] = { "follow", h, t } end
env.Build = function(h, odf) built[#built + 1] = odf; objs[h].busy = true end
env.BuildAt = function(h, odf, where) built[#built + 1] = odf .. "@" .. where.x .. "," .. where.y .. "," .. where.z; objs[h].busy = true end
local PB = assert(loadfile("Scripts/CRPilotBranch.lua"))()
for _, name in ipairs({ "Lock", "Release", "alive", "Ready", "Resend", "FollowPlayer", "Claim", "Adopt" }) do
    setfenv(PB[name], env)
end
env.require = function(name) assert(name == "CRPilotBranch"); return PB end
-- The region must load with no runtime: its helper is required on use, not at chunk load.
local bare = setmetatable({ M = {}, require = function() error("required at load") end }, { __index = _G })
local loadOnly = assert(loadstring("local M = M\n" .. block .. "\nreturn PilotAdapter"))
setfenv(loadOnly, bare)
check(loadOnly().update, "the region loads without the runtime")

local chunk = assert(loadstring("local M = M\n" .. block .. "\nreturn PilotAdapter"))
setfenv(chunk, env)
local adapter = chunk()
check(adapter.update and adapter.addObject and adapter.enable and adapter.disable, "all four hooks")
local function spawn(name, odf, x) obj(name, odf, x); adapter.addObject(name) end
local function finish(h) objs[h].busy = false end
local function count(kind, h, t)
    local n = 0
    for _, o in ipairs(orders) do
        if o[1] == kind and (h == nil or o[2] == h) and (t == nil or o[3] == t) then n = n + 1 end
    end
    return n
end

-- Start: user target is the bridge beacon; the recycler is not deployed, so nothing is built.
adapter.update()
check(orders[1][1] == "target" and orders[1][2] == "cam1", "SetUserTarget(cam1) first")
now = now + 1; adapter.update()
check(#built == 0, "nothing built before the recycler deploys")
objs[rec].deployed = true

-- Queue: armory (7 scrap), scavenger (5), then four fighters (7 scrap and a pilot each).
scrap = 6; now = now + 1; adapter.update()
check(#built == 0, "armory waits for 7 scrap")
scrap = 100
now = now + 1; adapter.update()
check(built[1] == "svslf", "armory first")
now = now + 1; adapter.update()
check(#built == 1, "recycler busy: no second build")
finish(rec)
now = now + 1; adapter.update()
check(built[2] == "svscav", "scavenger second")
finish(rec)
pilots = 0; now = now + 1; adapter.update()
check(#built == 2, "a fighter needs a pilot")
pilots = 30
for i = 1, 4 do
    now = now + 1; adapter.update()
    check(built[2 + i] == "svfigh", "fighter " .. i)
    finish(rec)
end
now = now + 1; adapter.update()
check(#built == 6, "no fifth fighter")

-- The armory arrives next to geyser 14 (x = 200): it heads for that geyser.
spawn("armory", "svslf", 190)
check(count("go_to", "armory", "eggeizr14_geyser") == 1, "armory sent to the nearest geyser")
-- A scavenger and a fighter are claimed without orders other than the fighter's follow.
spawn("scav", "svscav", 0)
for i = 1, 5 do spawn("f" .. i, "svfigh", 0) end
check(count("follow", nil, player) == 5, "every fighter follows the player")
-- Re-send: the undeployed armory knocked off its order is sent again after 6 s.
objs.armory.cmd = 0
local n = count("go_to")
now = now + 1; adapter.update(); now = now + 7; adapter.update()
check(count("go_to") == n + 1, "armory re-sent to its geyser")
-- Escorts re-follow every 30 s: the four slots only (the fifth fighter is not tracked).
n = count("follow")
now = now + 31; adapter.update()
check(count("follow") == n + 4, "the four escort slots re-follow")

-- Supply pods wait for the bridge (warn1), then three ammo and three repair pods from the armory.
objs.armory.deployed = true
finish("armory")
local before = #built
now = now + 1; adapter.update()
check(#built == before, "no pods before the bridge")
env.M.warning = true
local expect = { "sspammo", "sspammo", "sspammo", "ssprepa", "ssprepa", "ssprepa" }
for i, odf in ipairs(expect) do
    now = now + 1; adapter.update()
    check(built[#built] == odf .. "@2474,7,99038", "pod " .. i .. " is " .. odf .. " at the N64 spot, got " .. tostring(built[#built]))
    check(#built == before + i, "one pod per order")
    now = now + 1; adapter.update()
    check(#built == before + i, "armory busy: no stacked order")
    finish("armory")
end
now = now + 1; adapter.update()
check(#built == before + 6, "no seventh pod")

-- Adoption: units that existed before the mode was on are registered when enable runs, once.
local p = env.M.pilot
objs.late = nil
obj("late", "svfigh", 0)
local slots = #p.escorts
adapter.enable()
check(env.M.pilot.fightersBuilt == 4 and #p.escorts == slots, "slots already full: nothing changes")
adapter.enable(); adapter.addObject("late")
local follows = count("follow")
adapter.enable()
check(count("follow") == follows, "no second follow order from a second enable")

-- Rapid toggling gives no new placement orders.
local o0, b0 = #orders, #built
for _ = 1, 50 do
    adapter.disable(); adapter.addObject("armory")
    adapter.enable(); adapter.addObject("armory")
end
check(#orders == o0 and #built == b0, "no new orders or builds from 50 toggles")
check(env.M.pilot.nextSweep == 0, "disable re-arms the lock sweep at once")

-- A toggle on mid-mission with the armory and scavenger already built does not build them again.
do
    local fresh = setmetatable({}, { __index = env })
    fresh.M = { start_done = true, cam1 = "cam1", warning = false }
    local c = assert(loadstring("local M = M\n" .. block .. "\nreturn PilotAdapter"))
    setfenv(c, fresh)
    local a = c()
    local nb = #built
    a.enable(); a.update()
    for i = nb + 1, #built do check(built[i] ~= "svslf" and built[i] ~= "svscav", "no armory or scavenger rebuilt") end
    check(fresh.M.pilot.builtArmory and fresh.M.pilot.builtScav, "existing armory and scavenger are adopted")
end
print("misns4 Pilot Mode branch checks passed: " .. checks)
