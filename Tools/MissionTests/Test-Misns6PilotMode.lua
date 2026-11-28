-- Execute misns6cr's N64 Pilot Mode branch (the "-- CR pilot mode" region) with stubbed natives: walkers follow,
-- re-follow, attack the field HQ at the beacon stage, recycler geyser re-send, off/on cycles.
local file = assert(io.open("Scripts/misns6cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("\n(%-%- CR pilot mode >>\n.-\n%-%- CR pilot mode <<)\n"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local now = 0
local objs, orders = {}, {}
local function obj(name, odf, t)
    objs[name] = { odf = odf, team = t or 1, alive = true, deployed = false, busy = false, cmd = 0 }
    return name
end
local player = obj("player", "svtank")
local rec = obj("svrecy0_recycler", "svrecy")
local g13 = obj("eggeizr13_geyser", "eggeizr1", 0)
local walkers = { obj("svwalk0_walker", "svwalk"), obj("svwalk1_walker", "svwalk"), obj("svwalk2_walker", "svwalk") }
local hq = obj("abcafe8_i76building", "bbmbld", 2)

local env = setmetatable({}, { __index = _G })
env.M = { start_done = false, recy = rec, goal = hq }
env.AiCommand = { NONE = 0, GO = 3 }
env.GetTime = function() return now end
env.GetPlayerHandle = function() return player end
env.GetHandle = function(l) return objs[l] and objs[l].alive and l or nil end
env.IsAlive = function(h) return objs[h] ~= nil and objs[h].alive end
env.IsValid = env.IsAlive
env.IsDeployed = function(h) return objs[h].deployed end
env.GetTeamNum = function(h) return objs[h].team end
env.GetCurrentCommand = function(h) return objs[h].cmd end
env.GetCurrentWho = function() return nil end
env.AllCraft = function() return function() return nil end end
env.SetCommand = function() end
env.Goto = function(h, t) orders[#orders + 1] = { "go_to", h, t }; objs[h].cmd = 3 end
env.Follow = function(h, t) orders[#orders + 1] = { "follow", h, t } end
env.Attack = function(h, t) orders[#orders + 1] = { "attack", h, t } end
local branchChunk = assert(loadfile("Scripts/CRPilotBranch.lua"))
setfenv(branchChunk, env)
local Branch = branchChunk()
env.require = function(name) assert(name == "CRPilotBranch", name); return Branch end
local chunk = assert(loadstring("local M = M\n" .. block .. "\nreturn Pilot"))
setfenv(chunk, env)
local Pilot = chunk()
local function count(kind, who, target)
    local n = 0
    for _, o in ipairs(orders) do
        if o[1] == kind and (who == nil or o[2] == who) and (target == nil or o[3] == target) then n = n + 1 end
    end
    return n
end

-- Before the mission's own setup nothing happens.
Pilot.Enable()
Pilot.Update()
check(#orders == 0, "no orders before start_done")

-- Start: the three walkers follow the player once.
env.M.start_done = true
now = 1; Pilot.Update()
for _, w in ipairs(walkers) do check(count("follow", w, player) == 1, "walker follows at the start: " .. w) end
check(count("follow") == 3, "only the walkers follow")
now = 2; Pilot.Update()
check(count("follow") == 3, "no second follow right away")

-- The undeployed recycler is re-sent to its geyser after 6 s, once.
now = 3; Pilot.Update(); now = 10; Pilot.Update()
check(count("go_to", rec, g13) == 1, "recycler sent to the nearest geyser")
now = 11; Pilot.Update()
check(count("go_to") == 1, "not repeated while the command is GO")
objs[rec].deployed = true
now = 12; Pilot.Update()
check(count("go_to") == 1, "a deployed recycler is left alone")

-- Walkers re-follow after 30 s and when the craft changes.
now = 40; Pilot.Update()
check(count("follow") == 6, "walkers re-follow after 30 s")
player = obj("player2", "svtank")
now = 41; Pilot.Update()
check(count("follow") == 9 and count("follow", walkers[1], "player2") == 1, "walkers follow the new craft")

-- A lost walker is skipped.
objs[walkers[2]].alive = false
now = 80; Pilot.Update()
check(count("follow") == 11, "dead walker is not ordered")

-- Beacon stage: the walkers attack the field HQ once and stop re-following.
env.M.last_objective = true
now = 81; Pilot.Update()
check(count("attack", walkers[1], hq) == 1 and count("attack", walkers[3], hq) == 1 and count("attack") == 2,
    "walkers attack the field HQ")
now = 120; Pilot.Update()
check(count("attack") == 2 and count("follow") == 11, "one attack, no more follow orders")

-- Off/on cycles issue no duplicate orders.
local n0 = #orders
for _ = 1, 50 do
    Pilot.Disable(); Pilot.Enable()
    now = now + 1; Pilot.Update()
end
check(#orders == n0, "no new orders from 50 toggles")
check(env.M.pilot.nextSweep ~= nil, "state survives the toggles")

-- Mid-mission toggle after the beacon stage: no follow, a single attack.
env.M.pilot = nil; orders = {}
Pilot.Enable()
now = now + 1; Pilot.Update(); now = now + 40; Pilot.Update()
check(count("follow") == 0 and count("attack") == 2, "late toggle attacks once, never follows")
print("misns6 Pilot Mode branch checks passed: " .. checks)
