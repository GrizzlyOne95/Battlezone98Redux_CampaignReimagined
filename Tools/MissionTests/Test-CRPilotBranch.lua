-- Unit test for the CR re-send helpers of CRPilotBranch (Keep, KeepGoto, AssignSpot, KeepSpots) with stubbed natives.
--   lua5.1 Tools/MissionTests/Test-CRPilotBranch.lua
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local objs, sent = {}, {}
local function obj(name, x, z) objs[name] = { alive = true, deployed = false, cmd = 0, x = x or 0, z = z or 0 }; return name end
local env = setmetatable({}, { __index = _G })
env.AiCommand = { NONE = 0, GO = 3 }
env.IsAlive = function(h) return objs[h] ~= nil and objs[h].alive end
env.IsDeployed = function(h) return objs[h].deployed end
env.GetCurrentCommand = function(h) return objs[h].cmd end
env.GetDistance = function(a, b)
    local pa, pb = objs[a], objs[b] or b
    return math.sqrt((pa.x - pb.x) ^ 2 + (pa.z - pb.z) ^ 2)
end
env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
env.GetTerrainHeightAndNormal = function() return 7 end
env.Goto = function(h, t, p) sent[#sent + 1] = { h, t, p }; objs[h].cmd = 3 end
local B = setfenv(assert(loadfile("Scripts/CRPilotBranch.lua")), env)()

-- Keep: sends at once, then at most every `period` s, only while alive and needed.
local S = B.NewState()
local u = obj("u")
local calls, need = 0, true
local function needFn(h) return need end
local function sendFn(h) calls = calls + 1 end
check(B.Keep(S, "k", u, 0, 10, needFn, sendFn) == true and calls == 1, "first call sends at once")
check(B.Keep(S, "k", u, 5, 10, needFn, sendFn) == false and calls == 1, "no re-send before the period")
check(B.Keep(S, "k", u, 10, 10, needFn, sendFn) == true and calls == 2, "re-send once the period passed")
need = false
check(B.Keep(S, "k", u, 30, 10, needFn, sendFn) == false and calls == 2, "no send when not needed")
need = true
check(B.Keep(S, "other", u, 30, nil, needFn, sendFn) == true and calls == 3, "keys are independent")
check(B.Keep(S, "other", u, 39, nil, needFn, sendFn) == false, "the default period is 10 s")
check(B.Keep(S, "other", u, 40, nil, needFn, sendFn) == true and calls == 4, "default period elapsed")
objs[u].alive = false
check(B.Keep(S, "k", u, 100, 10, needFn, sendFn) == false and calls == 4, "no send to a dead unit")
check(B.Keep(S, "k", nil, 100, 10, needFn, sendFn) == false, "no send to a nil handle")

-- KeepGoto: far, undeployed and not on a GO order.
S = B.NewState()
local g = obj("g", 0, 0)
local spot = { x = 500, y = 0, z = 0 }
sent = {}
check(B.KeepGoto(S, "g", g, spot, 0, 50, 10) and #sent == 1 and sent[1][3] == 1, "far idle unit is sent")
check(B.KeepGoto(S, "g", g, spot, 20, 50, 10) == false and #sent == 1, "no re-send while it is on a GO order")
objs[g].cmd = 0
check(B.KeepGoto(S, "g", g, spot, 25, 50, 10) and #sent == 2, "a dropped order is re-sent")
objs[g].cmd = 0; objs[g].x = 480
check(B.KeepGoto(S, "g", g, spot, 40, 50, 10) == false and #sent == 2, "no re-send within the radius")
objs[g].x = 0; objs[g].deployed = true
check(B.KeepGoto(S, "g", g, spot, 60, 50, 10) == false and #sent == 2, "no re-send to a deployed unit")
objs[g].deployed = false
check(B.KeepGoto(S, "g", g, nil, 80, 50, 10) == false, "no send without a target")

-- AssignSpot / KeepSpots: first Goto at once, re-sent until arrival, then forgotten.
S = B.NewState()
local t1, h1 = obj("t1", 0, 0), obj("h1", 0, 0)
sent = {}
B.AssignSpot(S, t1, { 300, 0 })
check(#sent == 1 and sent[1][1] == t1 and sent[1][2].x == 300 and sent[1][2].y == 7, "AssignSpot sends the first Goto on the terrain")
B.KeepSpots(S, 1)
check(#sent == 1, "no re-send while the unit obeys")
objs[t1].cmd = 0
B.KeepSpots(S, 2)
check(#sent == 2 and S.spots[1].tries == 1, "a dropped spot order is re-sent at once")
objs[t1].cmd = 0
B.KeepSpots(S, 5)
check(#sent == 2, "then at most every period")
objs[t1].cmd = 0; objs[t1].x = 295
B.KeepSpots(S, 30)
check(#S.spots == 0 and #sent == 2, "arrived: forgotten, no re-send")
-- A unit deployed short of its spot (lost its order, deployed where it stood) is re-sent: the Goto undeploys it.
objs[h1].deployed = true
B.AssignSpot(S, h1, { 400, 0 })
check(#sent == 3, "a deployed unit is still sent its first Goto")
objs[h1].cmd = 0
B.KeepSpots(S, 40)
check(#S.spots == 1 and #sent == 4, "deployed 400 m short: re-sent")
-- Deployed within 25 m counts as arrived.
objs[h1].cmd = 0; objs[h1].x = 380
B.KeepSpots(S, 70)
check(#S.spots == 0 and #sent == 4, "deployed within 25 m: forgotten")
-- A blocked spot gives up after 6 re-sends.
local hb = obj("hb", 0, 0)
B.AssignSpot(S, hb, { 700, 0 })
local before = #sent
for k = 0, 9 do objs[hb].cmd = 0; B.KeepSpots(S, 100 + 10 * k) end
check(#S.spots == 0 and #sent - before == 6, "blocked: 6 re-sends after the first Goto, then forgotten")
objs[h1].deployed = false
-- A unit the mission re-tasks (e.g. a howitzer's Attack) is forgotten, never overridden.
local ha = obj("ha", 0, 0)
B.AssignSpot(S, ha, { 700, 0 })
before = #sent
objs[ha].cmd = 4 -- ATTACK
B.KeepSpots(S, 300)
check(#S.spots == 0 and #sent == before, "re-tasked: forgotten, no Goto over the new order")
-- A newer spot replaces the unit's old one; a dead unit is dropped.
local h2 = obj("h2", 0, 0)
B.AssignSpot(S, h2, { 100, 0 }); B.AssignSpot(S, h2, { 900, 0 })
check(#S.spots == 1 and S.spots[1].t[1] == 900, "a newer spot replaces the old one")
objs[h2].alive = false
B.KeepSpots(S, 50)
check(#S.spots == 0, "a dead unit is dropped")
-- Path names and handles are used as is.
local h3 = obj("h3", 0, 0); obj("beacon", 800, 0)
sent = {}
B.AssignSpot(S, h3, "beacon")
check(sent[1][2] == "beacon", "a handle target is used as is")

print("CRPilotBranch helper checks passed: " .. checks)
