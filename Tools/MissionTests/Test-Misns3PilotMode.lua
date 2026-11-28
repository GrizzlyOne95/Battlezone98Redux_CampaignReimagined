-- Execute misns3cr's N64 Pilot Mode branch (the `-- CR pilot mode >>` region: Pilot.Update / Pilot.Mode) with
-- stubbed natives: the four bombers follow the player (start, craft change, every 30 s), the nav user target
-- (Black Dog outpost, then the home base once the recycler is dead), and enable/disable cycles.
local file = assert(io.open("Scripts/misns3cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("\n(%-%- CR pilot mode >>\n.-\n%-%- CR pilot mode <<)\n"))
assert(not block:find("%f[%w]" .. "go" .. "to" .. "%f[%W]"), "the Lua 5.1 jump statement is banned by the validator")
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local now = 10
local objs, orders = {}, {}
local function obj(name, odf, team)
    objs[name] = { odf = odf, team = team or 1, alive = true, cmd = 0, craft = true }
    return name
end
local player = obj("player", "svtank")
local bombers = { obj("bomb1", "svhraz"), obj("bomb2", "svhraz"), obj("bomb3", "svhraz"), obj("bomb4", "svhraz") }
local outpost, basenav = obj("avrecy", "spcamr", 1), obj("basenav", "spcamr", 1)
objs[outpost].craft, objs[basenav].craft = false, false

local env = setmetatable({}, { __index = _G })
env.M = { missionstart = true, bomb1 = bombers[1], bomb2 = bombers[2], bomb3 = bombers[3], bomb4 = bombers[4],
    cam1 = basenav, cam2 = outpost, recyclerdestroyed = false }
env.AiCommand = { NONE = 0, SELECT = 1, FOLLOW = 5, GO = 3 }
env.GetTime = function() return now end
env.GetPlayerHandle = function() return player end
env.IsAlive = function(h) return objs[h] ~= nil and objs[h].alive end
env.IsValid = env.IsAlive
env.GetTeamNum = function(h) return objs[h].team end
env.GetCurrentCommand = function(h) return objs[h].cmd end
env.GetCurrentWho = function() return nil end
env.SetCommand = function(h, c, p) orders[#orders + 1] = { "setcommand", h, c, p } end
env.AllCraft = function()
    local names = {}
    for k, o in pairs(objs) do if o.alive and o.craft then names[#names + 1] = k end end
    table.sort(names)
    local i = 0
    return function() i = i + 1; return names[i] end
end
env.Follow = function(h, t, p) orders[#orders + 1] = { "follow", h, t, p }; objs[h].cmd = 5 end
env.SetUserTarget = function(h) orders[#orders + 1] = { "target", h } end

local Branch = setfenv(assert(loadfile("Scripts/CRPilotBranch.lua")), env)()
local chunk = assert(loadstring(block .. "\nreturn Pilot"))
setfenv(chunk, env)
local Pilot = chunk()
check(Pilot.Branch == nil, "the branch module is only set by the co-op runtime region")
Pilot.Branch = Branch
local mode = Pilot.Mode
check(mode.update and mode.enable and mode.disable and mode.addObject == nil,
    "update/enable/disable hooks only: the mission's AddObject is empty on the cart")

local function count(kind, first)
    local n = 0
    for _, o in ipairs(orders) do if o[1] == kind and (first == nil or o[2] == first) then n = n + 1 end end
    return n
end

-- Before the body's first frame nothing happens.
env.M.missionstart = false
mode.update()
check(#orders == 0, "no pilot action before the mission starts")
env.M.missionstart = true

-- First frame: user target is the outpost nav, the four bombers follow the player.
mode.update()
check(count("target", outpost) == 1, "the Black Dog outpost nav becomes the user target")
for _, b in ipairs(bombers) do check(count("follow", b) == 1, b .. " follows the player") end
mode.update()
check(count("target") == 1 and count("follow") == 4, "nothing repeats on the next frame")

-- Every 30 s the bombers follow again; a craft change re-follows at once.
now = now + 29; mode.update()
check(count("follow") == 4, "no re-follow before 30 s")
now = now + 2; mode.update()
check(count("follow") == 8, "all four re-follow after 30 s")
local other = obj("other", "svtank")
player = other
mode.update()
check(count("follow") == 12 and orders[#orders][3] == other, "a craft change re-follows at once")
-- A dead bomber is skipped; the rest still follow.
objs[bombers[2]].alive = false
now = now + 31; mode.update()
check(count("follow") == 15 and count("follow", bombers[2]) == 3, "a dead bomber is skipped")
-- A bomber handle the body never resolved leaves the list intact for the others (no hole stops the loop).
env.M.bomb1 = nil
now = now + 31; mode.update()
check(count("follow") == 17, "the remaining bombers still follow past a nil handle")
env.M.bomb1 = bombers[1]

-- Lock sweep: the bombers' orders are re-issued at priority 1.
local locked = false
for _, o in ipairs(orders) do if o[1] == "setcommand" and o[4] == 1 then locked = true end end
check(locked, "Lock re-issues the bombers' orders at priority 1")

-- Recycler destroyed: the base nav takes over the user target, once.
env.M.recyclerdestroyed = true
mode.update()
check(count("target", basenav) == 1 and count("target") == 2, "the home base nav becomes the user target")
mode.update()
check(count("target") == 2, "retargeted once")

-- Off/on cycles: no duplicate user targets and no immediate follow storm other than the re-enable follow.
local follows, targets = count("follow"), count("target")
for _ = 1, 50 do
    mode.disable()
    mode.enable()
end
check(count("follow") == follows and count("target") == targets, "toggling issues no follow or target orders itself")
now = now + 1
mode.update()
check(count("follow") == follows + 3 and count("target") == targets, "re-enable re-follows once, no new target")
mode.update()
check(count("follow") == follows + 3, "and only once after 50 cycles")
check(env.M.pilot.nextSweep ~= nil, "state kept in M.pilot")

-- A mid-mission toggle after the recycler died targets the base nav straight away.
env.M.pilot = nil
orders = {}
mode.update()
check(count("target", basenav) == 1 and count("target", outpost) == 0, "a late toggle goes straight to the home base nav")

-- Release: disable re-issues each locked order at priority 0.
local set = {}
env.SetCommand = function(h, c, p) set[#set + 1] = { h, c, p } end
objs.bomb1.cmd = 5
mode.disable()
local released = false
for _, s in ipairs(set) do if s[1] == "bomb1" and s[3] == 0 then released = true end end
check(released, "disable hands the bombers back at priority 0")

print("misns3 Pilot Mode branch checks passed: " .. checks)
