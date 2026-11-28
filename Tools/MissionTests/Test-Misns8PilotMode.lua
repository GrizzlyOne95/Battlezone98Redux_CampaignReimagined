-- Execute misns8cr's N64 Pilot Mode branch (PilotUpdate/PilotAddObject) with
-- stubbed natives: start orders, geyser re-send, scav/constructor queue, base
-- placement orders, the Fury-event sav, factory sav, adoption and disable cycles.
local file = assert(io.open("Scripts/misns8cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("%-%- CR pilot mode >>\n(.-)\n%-%- CR pilot mode <<"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local now, scrap, pilots = 0, 100, 5
local objs, built, orders = {}, {}, {}
local function obj(name, odf, t)
    objs[name] = { odf = odf, team = t or 1, alive = true, deployed = false, busy = false, cmd = 0 }
    return name
end
local player = obj("player", "svtank")
local rec = obj("svrecycle", "svrecy8")
local fac = obj("svmuf", "savmf")
obj("eggeizr13_geyser", "eggeizr1", 0); obj("eggeizr12_geyser", "eggeizr1", 0); obj("last_geyser", "eggeizr1", 0)

local env = setmetatable({}, { __index = _G })
env.M = { general_spawn = false }
env.AiCommand = { NONE = 0, GO = 3 }
env.GetTime = function() return now end
env.GetPlayerHandle = function() return player end
env.GetHandle = function(l) return objs[l] and l end
env.IsValid = function(h) return objs[h] ~= nil and objs[h].alive end
env.IsAlive = env.IsValid
env.IsDeployed = function(h) return objs[h].deployed end
env.IsBusy = function(h) return objs[h].busy end
env.IsOdf = function(h, odf) return objs[h].odf == odf end
env.GetTeamNum = function(h) return objs[h].team end
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
env.SetCommand = function() end
env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
env.GetTerrainHeightAndNormal = function() return 7 end
env.Goto = function(h, t) orders[#orders + 1] = { "go_to", h, t }; objs[h].cmd = 3; objs[h].deployed = false end
env.Dropoff = function(h, pos) orders[#orders + 1] = { "dropoff", h, pos } end
env.Build = function(h, odf) built[#built + 1] = odf .. "@" .. h; objs[h].busy = true end
local spawned = 0
env.BuildObject = function(odf, team, at)
    spawned = spawned + 1
    local name = "built" .. spawned
    obj(name, odf, team); built[#built + 1] = odf .. "!" .. tostring(at)
    return name
end
local B = assert(loadfile("Scripts/CRPilotBranch.lua"))()
for _, f in pairs(B) do if type(f) == "function" then setfenv(f, env) end end
env.require = function(n) assert(n == "CRPilotBranch"); return B end
local chunk = assert(loadstring(table.concat({ "local M = M", block,
    "return { update = PilotUpdate, add = PilotAddObject }" }, "\n")))
setfenv(chunk, env)
local api = chunk()
local function step(dt) now = now + (dt or 1); api.update() end
local function spawn(name, odf, team) obj(name, odf, team); api.add(name) end
local function count(kind, a, b)
    local c = 0
    for _, o in ipairs(orders) do
        if o[1] == kind and (a == nil or o[2] == a) and (b == nil or o[3] == b) then c = c + 1 end
    end
    return c
end
local function builds(prefix)
    local c = 0
    for _, b in ipairs(built) do if b:find(prefix, 1, true) == 1 then c = c + 1 end end
    return c
end

-- Start: recycler to the label 55 geyser, factory to the label 54 geyser, once.
step(1)
check(count("go_to", rec, "eggeizr13_geyser") == 1, "recycler sent to the label 55 geyser")
check(count("go_to", fac, "eggeizr12_geyser") == 1, "factory sent to the label 54 geyser")
check(#built == 0, "undeployed producers build nothing")
local n = #orders; step(1)
check(#orders == n, "start orders run once")

-- Re-send: knocked off GO, the recycler gets its Goto again after 6 s.
objs[rec].cmd = 0
step(1); step(7)
check(count("go_to", rec, "eggeizr13_geyser") == 2, "recycler re-sent after 6 s")

-- Deployed recycler: scavengers until two (top-up with no scrap / pilots).
objs[rec].deployed, objs[fac].deployed, objs[fac].cmd = true, true, 0
scrap, pilots = 0, 0
step(1)
check(builds("svscav@" .. rec) == 1 and scrap == 4 and pilots == 1, "scav top-up, first svscav queued")
objs[rec].busy = false
spawn("scav1", "svscav")
step(1)
check(builds("svscav@" .. rec) == 2, "second svscav queued")
objs[rec].busy = false
spawn("scav2", "svscav"); scrap = 100
step(1)
check(builds("svcnst@" .. rec) == 1, "constructor queued after two scavengers")
objs[rec].busy = false
step(1)
check(builds("svcnst@" .. rec) == 2, "constructor re-queued while none is alive")
spawn("cnst", "svcnst")
api.add("cnst")
objs[rec].busy = false
step(1)
check(builds("svcnst@" .. rec) == 2, "no third constructor, no double registration")

-- Constructor: hangar first, dropped at its N64 spot; next waits for it.
check(builds("sbhang@cnst") == 1, "hangar built first")
step(1)
local d = orders[#orders]
check(d[1] == "dropoff" and d[2] == "cnst" and d[3].x == 1964 and d[3].z == 100363 and d[3].y == 7, "hangar dropped at (1964, 100363)")
objs.cnst.busy = false
step(1)
check(builds("sbhang@") == 1 and builds("sbsupp@") == 0, "next facility waits for the hangar to appear")
spawn("hang", "sbhang"); step(1)
check(builds("sbsupp@cnst") == 1, "support building once the hangar stands")
local seq = { { "sbsupp", 1897, 100315 }, { "sbspow", 1829, 100314 }, { "sbtowe", 1836, 100351 }, { "sbspow", 1841, 100215 },
    { "sbtowe", 1877, 100180 }, { "sbspow", 2025, 100356 }, { "sbtowe", 2063, 100349 } }
for i, s in ipairs(seq) do
    step(1)
    d = orders[#orders]
    check(d[1] == "dropoff" and d[3].x == s[2] and d[3].z == s[3], s[1] .. " dropped at (" .. s[2] .. ", " .. s[3] .. ")")
    objs.cnst.busy = false
    spawn("b" .. i, s[1]); step(1)
end
check(builds("sbspow@") == 3 and builds("sbtowe@") == 3 and builds("sbsupp@") == 1 and builds("sbhang@") == 1, "full base queued once")
check(count("dropoff") == 8, "one dropoff per facility")

-- Power plant that cannot be afforded blocks the rest of the base.
objs.b2.alive = false; scrap = 5
local nb = #built; step(1)
check(#built == nb, "unaffordable power plant blocks the queue")

-- Factory sav: base complete -> one savtnk (the savmf's build item; CR adaptation), once.
objs.b2.alive = true; scrap = 100
step(1)
check(builds("savtnk@" .. fac) == 1 and builds("svsav@" .. fac) == 0, "factory (savmf) builds one savtnk once the base is complete")
objs[fac].busy = false
spawn("sav", "savtnk"); step(1)
check(builds("savtnk@" .. fac) == 1, "no second factory savtnk while one stands")
check(env.M.pilot.sav == "sav", "the savtnk fills the pilot sav slot")

-- Fury event: one svsav built at last_geyser while the factory stands, once.
check(builds("svsav!") == 0, "no event sav before the Fury event")
env.M.general_spawn = true
step(1)
check(builds("svsav!last_geyser") == 1, "Fury event builds a svsav at last_geyser")
step(1)
check(builds("svsav!") == 1, "event sav built once")

-- A toggle after the event does not build one (fresh state); seen before the event it does.
env.M.pilot = nil
step(1)
check(builds("svsav!") == 1, "late toggle after the Fury event builds no extra sav")
env.M.pilot = nil; env.M.general_spawn = false; step(1); env.M.general_spawn = true; step(1)
check(builds("svsav!") == 2, "armed again when seen before the event")

-- Adoption: Claim registers each unit once; enemy units are ignored.
local P = env.M.pilot
local orig = #orders
spawn("enemyCnst", "svcnst", 2)
check(P.cnst ~= "enemyCnst", "enemy constructor not adopted")
B.Adopt(P, api.add)
check(#orders == orig, "adopt issues no duplicate placement orders")
api.add("cnst"); api.add("hang")
check(#orders == orig, "re-adding claimed units does nothing")

-- Disable/enable cycles issue no duplicate placement orders.
local before = count("dropoff")
for _ = 1, 3 do B.Release(P); B.Adopt(P, api.add); step(1) end
check(count("dropoff") == before, "disable/enable cycles issue no duplicate dropoffs")
print("misns8 Pilot Mode branch checks passed: " .. checks)
