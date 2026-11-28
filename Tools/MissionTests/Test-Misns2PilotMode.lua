-- Execute misns2cr's N64 Pilot Mode branch (PilotUpdate) with stubbed natives: the
-- escort follows, the nav chain gated on the player, the minefield stop and its
-- mine tracking, the post-ambush return, and off/on cycles.
local file = assert(io.open("Scripts/misns2cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("%-%- CR pilot mode >>\n(.-)\n%-%- CR pilot mode <<"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end
check(source:find("pilotMode = PilotAdapter", 1, true), "the runtime config hands over the adapter")

local now, enabled = 0, true
local objs, orders, marked = {}, {}, {}
local function obj(name, odf, x, z, team)
    objs[name] = { odf = odf, team = team or 1, alive = true, x = x or 0, z = z or 0, cmd = 0 }
    return name
end
local function pos(h)
    if objs[h] then return objs[h].x, objs[h].z end
    return nil
end
local paths = { mine6 = { 10, 0 }, mine8 = { 20, 0 }, mine10 = { 30, 0 }, mine11 = { 40, 0 }, mine12 = { 50, 0 },
    mine1 = { 99, 0 } }

local player = obj("player", "svtank", 5000, 0)
local trans = { obj("t1", "svap2", 0, 0), obj("t2", "svap2", 0, 0), obj("t3", "svap2", 0, 0) }
local esc = { e2a = obj("e2a", "svtank"), lu = obj("lu", "svfigh"), e1b = obj("e1b", "svtank"),
    e1a = obj("e1a", "svfigh"), e3b = obj("e3b", "svtank"), e2b = obj("e2b", "svfigh"), e3a = obj("e3a", "svfigh") }
-- Beacons sit on a line, 1000 m apart; every transport starts far from all of them.
local beaconNames = { "apcamr4_camerapod", "apcamr5_camerapod", "apcamr6_camerapod", "apcamr7_camerapod",
    "apcamr8_camerapod", "apcamr9_camerapod", "cam1" }
for i, name in ipairs(beaconNames) do obj(name, "apcamr", 100000 + i * 1000, 0) end
local mines = {}
for name, p in pairs(paths) do mines[name] = obj("m_" .. name, "proxmine", p[1], p[2], 2) end

local env = setmetatable({}, { __index = _G })
env.M = { missionstart = true, bdcindone = false, t1 = trans[1], t2 = trans[2], t3 = trans[3],
    e2a = esc.e2a, lu = esc.lu, e1b = esc.e1b, e1a = esc.e1a, e3b = esc.e3b, e2b = esc.e2b, e3a = esc.e3a }
env.AiCommand = { NONE = 0, GO = 3, FOLLOW = 5 }
env.GetTime = function() return now end
env.GetPlayerHandle = function() return player end
env.GetHandle = function(n) return objs[n] and n or nil end
env.IsAlive = function(h) return objs[h] ~= nil and objs[h].alive end
env.IsValid = env.IsAlive
env.IsOdf = function(h, odf) return objs[h].odf == odf end
env.GetTeamNum = function(h) return objs[h].team end
env.GetCurrentCommand = function(h) return objs[h].cmd end
env.GetCurrentWho = function() return nil end
env.GetDistance = function(a, b)
    local ax, az = pos(a)
    local bx, bz = pos(b)
    if not bx then bx, bz = paths[b][1], paths[b][2] end
    return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end
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
env.SetObjectiveOn = function(h) marked[#marked + 1] = h end
env.Goto = function(h, t) orders[#orders + 1] = { "go_to", h, t }; objs[h].cmd = 3 end
env.Follow = function(h, t) orders[#orders + 1] = { "follow", h, t } end
env.Stop = function(h) orders[#orders + 1] = { "stop", h }; objs[h].cmd = 0 end
local PB = assert(loadfile("Scripts/CRPilotBranch.lua"))()
setfenv(PB.Lock, env); setfenv(PB.Release, env); setfenv(PB.alive, env)
env.require = function(name) assert(name == "CRPilotBranch"); return PB end
-- The region must load with no runtime: its helper is required on use, not at chunk load.
local bare = setmetatable({ M = {}, require = function() error("required at load") end }, { __index = _G })
local loadOnly = assert(loadstring("local M = M\n" .. block .. "\nreturn PilotAdapter"))
setfenv(loadOnly, bare)
check(loadOnly().update, "the region loads without the runtime")

local chunk = assert(loadstring("local M = M\n" .. block .. "\nreturn PilotAdapter"))
setfenv(chunk, env)
local adapter = chunk()
check(adapter.update and adapter.disable and not adapter.addObject, "update and disable only")

local function count(kind, h, t)
    local n = 0
    for _, o in ipairs(orders) do
        if o[1] == kind and (h == nil or o[2] == h) and (t == nil or o[3] == t) then n = n + 1 end
    end
    return n
end
local function moveTransports(x) for _, t in ipairs(trans) do objs[t].x = x end end

-- Not started yet: nothing happens.
env.M.missionstart = false
adapter.update()
check(#orders == 0, "no orders before the mission has started")
env.M.missionstart = true

-- Start (C 268-277): user target cam1, then the escorts follow their transport in the C order.
adapter.update()
check(orders[1][1] == "target" and orders[1][2] == "cam1", "SetUserTarget(cam1) first")
local want = { { "e2a", "t1" }, { "lu", "t1" }, { "e1b", "t2" }, { "e1a", "t2" }, { "e3b", "t3" },
    { "e2b", "t3" }, { "e3a", "t3" } }
check(#orders == 8, "target plus seven follows")
for i, pair in ipairs(want) do
    check(orders[i + 1][1] == "follow" and orders[i + 1][2] == pair[1] and orders[i + 1][3] == pair[2],
        "escort " .. pair[1] .. " follows " .. pair[2])
end
adapter.update(); now = now + 31; adapter.update()
check(#orders == 8, "the escorts are told once, not every 30 s")

-- Nav chain: a nav latches when a transport is near, but the order waits for the player (<100 m).
local function beaconX(i) return objs[beaconNames[i]].x end
moveTransports(beaconX(1) - 50) -- within 70 m of the first nav
now = now + 1; adapter.update()
check(count("go_to") == 0, "no order while the player is far away")
objs[player].x, objs[player].z = beaconX(1) - 50, 60
now = now + 1; adapter.update()
check(count("go_to") == 3 and count("go_to", "t1", "apcamr5_camerapod") == 1, "all three sent to the second nav")
now = now + 1; adapter.update()
check(count("go_to") == 3, "sent once")

-- Navs 2..4 each send the convoy to the next one.
for i = 2, 4 do
    moveTransports(beaconX(i) - 50)
    objs[player].x = beaconX(i) - 50
    now = now + 1; adapter.update()
    check(count("go_to", "t2", beaconNames[i + 1]) == 1, "sent on to " .. beaconNames[i + 1])
end
check(count("go_to") == 12, "twelve orders so far")

-- Minefield nav (100 m): the convoy halts and the five tracked mines are marked; the sixth mine is not.
moveTransports(beaconX(5) - 90)
objs[player].x = beaconX(5) - 90
local before = #marked
now = now + 1; adapter.update()
check(count("stop") == 3, "the convoy stops at the minefield nav")
check(#marked - before == 5, "five mines marked")
local seen = {}
for i = before + 1, #marked do seen[marked[i]] = true end
check(not seen[mines.mine1] and seen[mines.mine6] and seen[mines.mine12], "only the five tracked mines")
now = now + 1; adapter.update()
check(count("stop") == 3 and count("go_to") == 12, "waits while mines stand")
-- CR adaptation: the minefield stop is intentional, so no stall resend follows it.
now = now + 11; adapter.update()
check(env.M.pilot.target == nil and count("go_to") == 12, "no resend after the minefield stop")
for _, name in ipairs({ "mine6", "mine8", "mine10", "mine11" }) do
    objs[mines[name]].alive = false
    now = now + 1; adapter.update()
end
check(count("go_to") == 12, "one mine left: still waiting")
objs[mines.mine12].alive = false
now = now + 1; adapter.update()
check(count("go_to", "t3", "apcamr9_camerapod") == 1, "mines clear: sent to the sixth nav")

-- Sixth nav: on to cam1.
moveTransports(beaconX(6) - 50)
objs[player].x = beaconX(6) - 50
now = now + 1; adapter.update()
check(count("go_to", "t1", "cam1") == 1 and count("go_to") == 18, "sent on to the launch pad")

-- After the ambush film (seen running), all three return to the first nav, once.
env.M.bdcindone = true
now = now + 1; adapter.update()
check(count("go_to", "t1", "apcamr4_camerapod") == 1 and count("go_to") == 21, "ambush: back to the first nav")
now = now + 1; adapter.update()
check(count("go_to") == 21, "the return is sent once")

-- Off/on cycles re-run nothing.
local o0 = #orders
for _ = 1, 50 do
    enabled = false; adapter.disable()
    enabled = true
    now = now + 1; adapter.update()
end
check(#orders == o0, "no new orders from 50 off/on cycles")
check(env.M.pilot.nextSweep ~= nil, "state survives the cycles")

-- A toggle on after the film ended does not turn the convoy around.
do
    local fresh = setmetatable({}, { __index = env })
    fresh.M = { missionstart = true, bdcindone = true, t1 = trans[1], t2 = trans[2], t3 = trans[3] }
    local c = assert(loadstring("local M = M\n" .. block .. "\nreturn PilotAdapter"))
    setfenv(c, fresh)
    local a = c()
    moveTransports(0); objs[player].x = 5000
    local n = count("go_to")
    a.update(); now = now + 1; a.update()
    check(count("go_to") == n, "late toggle after the ambush film sends no return order")
end

-- A transport lost: the rest of the chain still runs on the survivors.
objs.t2.alive = false
local lost = #orders
moveTransports(beaconX(1) - 50)
env.M.pilot.nav, env.M.pilot.sent = {}, {}
objs[player].x = beaconX(1) - 50
now = now + 1; adapter.update()
check(#orders == lost + 2, "a dead transport gets no order")
-- CR adaptation: start nudge and stall resend on a fresh state (transports back at the start, idle).
do
    for _, t in ipairs(trans) do objs[t].alive, objs[t].x, objs[t].z, objs[t].cmd = true, 0, 0, 0 end
    objs[player].x, objs[player].z = 5000, 0
    local fresh = setmetatable({}, { __index = env })
    fresh.M = { missionstart = true, bdcindone = false, t1 = trans[1], t2 = trans[2], t3 = trans[3] }
    local c = assert(loadstring("local M = M\n" .. block .. "\nreturn PilotAdapter"))
    setfenv(c, fresh)
    local a = c()
    local n0 = count("go_to")
    a.update(); now = now + 1; a.update()
    check(count("go_to") == n0, "player far from the transports: no start nudge")
    objs[player].x = 50
    now = now + 1; a.update()
    check(count("go_to") == n0 + 3 and objs.t1.cmd == 3, "start nudge sends all three transports")
    check(fresh.M.pilot.target == "apcamr4_camerapod", "the nudge targets nav 1 and records it")
    now = now + 1; a.update()
    check(count("go_to") == n0 + 3, "the nudge is sent once")
    now = now + 10; a.update()
    check(count("go_to") == n0 + 3, "no stall resend while on their way (GO)")
    objs.t1.cmd = 0; objs.t3.cmd = 0
    now = now + 10; a.update()
    check(count("go_to") == n0 + 5 and objs.t1.cmd == 3, "idle and far transports are re-sent after 10 s; the one on GO is not")
    local n1 = count("go_to")
    objs.t1.cmd = 0; now = now + 5; a.update()
    check(count("go_to") == n1, "no stall resend inside 10 s")
    objs.t1.cmd = 0; objs.t3.cmd = 0; objs.t1.x = objs["apcamr4_camerapod"].x - 30; objs[player].x = 5000 -- player away: the nav latch order is not under test here
    now = now + 5; a.update()
    check(count("go_to") == n1 + 1 and objs.t1.cmd == 0 and objs.t3.cmd == 3, "a transport within 70 m of the target is not re-sent")
end

print("misns2 Pilot Mode branch checks passed: " .. checks)
