-- Execute misns1cr's N64 Pilot Mode branch (the `-- CR pilot mode >>` region: Pilot.Update / Pilot.AddObject /
-- Pilot.Mode) with stubbed natives: start fighters, recycler queue, supply pods, the howitzer, nav marking,
-- adoption on enable and off/on cycles.
local file = assert(io.open("Scripts/misns1cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("\n(%-%- CR pilot mode >>\n.-\n%-%- CR pilot mode <<)\n"))
assert(not block:find("%f[%w]" .. "go" .. "to" .. "%f[%W]"), "the Lua 5.1 jump statement is banned by the validator")
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local now, scrap, pilots, enabled = 100, 100, 0, true
local objs, orders, builds, fails, nextId = {}, {}, {}, {}, 0
local function obj(name, odf, team, x, z)
    objs[name] = { odf = odf, team = team or 1, alive = true, deployed = false, busy = false, health = 1, ammo = 1, cmd = 0,
        x = x or 0, z = z or 0, craft = true }
    return name
end
local player = obj("player", "svtank")
local rec = obj("rec", "svrecy"); objs[rec].deployed = true
local colorado = obj("colorado", "bvrecy", 5, 3000, 100000)
local walker, walkcam = obj("walker", "svwalk", 1, 2800, 101100), obj("walkcam", "spcamr", 0, 2885, 100559)
local cams = { obj("hidcam1", "spcamr", 0), obj("hidcam2", "spcamr", 0), obj("hidcam3", "spcamr", 0) }
local tower1, tower2 = obj("abtowe0_turret", "bbtowe", 5), obj("abtowe3_turret", "bbtowe", 5)
for _, c in ipairs(cams) do objs[c].craft = false end
objs[walkcam].craft = false

local adapter, mode
local env = setmetatable({}, { __index = _G })
env.M = { missionstart = true, svrec = rec, colorado = colorado, walker1 = walker, walkcam1 = walkcam,
    hidcam1 = cams[1], hidcam2 = cams[2], hidcam3 = cams[3], startconvoy = 280, path = 1,
    pickpath = false, retreat = false }
env.AiCommand = { NONE = 0, SELECT = 1, FOLLOW = 5, GO = 3 }
env.GetTime = function() return now end
env.GetPlayerHandle = function() return player end
env.GetHandle = function(l) return objs[l] and objs[l].alive and l or nil end
env.IsAlive = function(h) return objs[h] ~= nil and objs[h].alive end
env.IsValid = env.IsAlive
env.IsDeployed = function(h) return objs[h].deployed end
env.IsBusy = function(h) return objs[h].busy end
env.IsOdf = function(h, odf) return objs[h].odf == odf end
env.GetTeamNum = function(h) return objs[h].team end
env.GetHealth = function(h) return objs[h].health end
env.GetAmmo = function(h) return objs[h].ammo end
env.GetScrap = function() return scrap end
env.AddScrap = function(_, n) scrap = scrap + n; orders[#orders + 1] = { "addscrap", n } end
env.GetPilot = function() return pilots end
env.AddPilot = function(_, n) pilots = pilots + n end
env.GetCurrentCommand = function(h) return objs[h].cmd end
env.GetCurrentWho = function() return nil end
env.SetCommand = function(h, c, p) orders[#orders + 1] = { "setcommand", h, c, p } end
env.GetDistance = function(a, b)
    local pa, pb = objs[a], objs[b]
    return math.sqrt((pa.x - pb.x) ^ 2 + (pa.z - pb.z) ^ 2)
end
env.AllCraft = function()
    local names = {}
    for k, o in pairs(objs) do if o.alive and o.craft then names[#names + 1] = k end end
    table.sort(names)
    local i = 0
    return function() i = i + 1; return names[i] end
end
env.AllObjects = function()
    local names = {}
    for k, o in pairs(objs) do if o.alive then names[#names + 1] = k end end
    table.sort(names)
    local i = 0
    return function() i = i + 1; return names[i] end
end
env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
env.GetTerrainHeightAndNormal = function() return 7 end
env.Goto = function(h, t, p) orders[#orders + 1] = { "go_to", h, t, p }; objs[h].cmd = 3 end
env.Follow = function(h, t, p) orders[#orders + 1] = { "follow", h, t, p }; objs[h].cmd = 5 end
env.Attack = function(h, t, p) orders[#orders + 1] = { "attack", h, t, p } end
env.SetObjectiveOn = function(h) orders[#orders + 1] = { "on", h } end
env.SetObjectiveOff = function(h) orders[#orders + 1] = { "off", h } end
env.FailMission = function(t, des) fails[#fails + 1] = { t, des } end
env.Build = function(h, odf) builds[#builds + 1] = odf; objs[h].busy = true end
env.BuildObject = function(odf, team, where)
    nextId = nextId + 1
    local name = "b" .. nextId
    obj(name, odf, team, where.x, where.z)
    orders[#orders + 1] = { "buildobject", name, odf, where }
    if enabled and mode and mode.addObject then mode.addObject(name) end -- the engine calls AddObject at once
    return name
end

local Branch = setfenv(assert(loadfile("Scripts/CRPilotBranch.lua")), env)()
local chunk = assert(loadstring(block .. "\nreturn Pilot"))
setfenv(chunk, env)
local Pilot = chunk()
check(Pilot.Branch == nil, "the branch module is only set by the co-op runtime region")
Pilot.Branch = Branch
mode = Pilot.Mode
check(mode.update and mode.addObject and mode.enable and mode.disable, "all four hooks are configured")

local function count(kind, first)
    local n = 0
    for _, o in ipairs(orders) do if o[1] == kind and (first == nil or o[2] == first) then n = n + 1 end end
    return n
end
local function spawn(name, odf, team) obj(name, odf, team or 1); if enabled then mode.addObject(name) end; return name end
local function update() mode.update() end

-- The body already built the stock start: two svtank and one svfigh. Adoption on enable registers them.
spawn("tank1", "svtank"); spawn("tank2", "svtank"); spawn("figh1", "svfigh")
enabled = false
local d = #orders
local pre = obj("pre", "svfigh") -- exists before the mode is on
enabled = true
mode.enable()
check(env.M.pilot.f1 == "figh1" or env.M.pilot.f1 == "pre", "adoption fills a fighter slot")
check(count("follow", "pre") == 1, "an adopted fighter follows the player once")

-- Before the body's first frame (dropship opening) the branch does nothing.
local savedStart = env.M.missionstart
env.M.missionstart = false
local before = #orders
update()
check(#orders == before and #builds == 0 and not env.M.pilot.started, "no pilot action before the mission starts")
env.M.missionstart = savedStart
scrap, pilots = 0, 0

-- First frame: four more fighters (six total with the stock one and the adopted one), the first attack +30 s.
update()
check(env.M.pilot.started, "started")
check(env.M.startconvoy == 130, "first attack timer is +30 s instead of +180 s (280 - 150)")
local fighters = {}
for i = 1, 6 do fighters[#fighters + 1] = env.M.pilot["f" .. i] end
check(#fighters == 6, "six fighter slots filled")
local built = {}
for _, o in ipairs(orders) do if o[1] == "buildobject" and o[3] == "svfigh" then built[#built + 1] = o[4] end end
check(#built == 4, "four extra fighters built (stock one and the adopted one count): " .. #built)
check(built[1].x == 1933 and built[1].z == 98543 and built[1].y == 7, "first extra fighter on N64 path 27, at terrain height")
check(built[4].x == 1917 and built[4].z == 98525, "fourth extra fighter on N64 path 30")
for i = 1, 6 do check(count("follow", fighters[i]) >= 1, "fighter " .. i .. " follows the player") end
check(count("follow", "tank1") == 1 and count("follow", "tank2") == 1, "both tanks follow the player")
update()
check(count("buildobject") == 4, "start units are built only once")
check(env.M.startconvoy == 130, "the timer is shortened only once")

-- Lock sweep: team-1 craft with a lockable order are re-issued at priority 1.
local locked = false
for _, o in ipairs(orders) do if o[1] == "setcommand" and o[4] == 1 then locked = true end end
check(locked, "Lock re-issues orders at priority 1")

-- Recycler queue: scavengers first; the first frame's update already topped up the scrap and pilot and built one.
check(builds[1] == "svscav" and scrap >= 4 and pilots == 1, "scavenger built after the scrap and pilot top-up")
local n = #builds
now = now + 1; update()
check(#builds == n, "busy recycler: no second order")
objs[rec].busy = false; spawn("scav1", "svscav")
now = now + 1; update()
check(builds[#builds] == "svscav" and #builds == n + 1, "second scavenger")
objs[rec].busy = false; spawn("scav2", "svscav")
n = #builds
now = now + 1; update()
check(#builds == n, "all fighters present, two scavengers: queue idle")

-- Supply: a hurt player gets a repair pod (spammo/sprepa in the N64; the CR recycler's ssprepa/sspammo here).
objs[player].health = 0.5
now = now + 1; update()
check(builds[#builds] == "ssprepa", "repair pod requested from the recycler")
objs[rec].busy = false
n = #builds
now = now + 1; update()
check(#builds == n, "one request, one pod")
spawn("pod1", "ssprepa")
objs[player].health = 0.4
now = now + 1; update()
check(#builds == n, "a live pod holds the request")
objs[player].health = 1
objs[player].ammo = 0.2
now = now + 1; update()
check(builds[#builds] == "sspammo", "ammo pod requested")
objs[rec].busy = false
spawn("pod2", "sspammo")
objs[player].ammo = 1

-- A lost fighter is rebuilt by the recycler (scrap 6).
scrap = 100
objs[fighters[2]].alive = false
now = now + 1; update()
check(builds[#builds] == "svfigh", "empty fighter slot rebuilt")
objs[rec].busy = false
local replacement = spawn("figh_new", "svfigh")
check(env.M.pilot.f2 == replacement, "the new fighter fills the empty slot")
n = #builds
now = now + 1; update()
check(#builds == n, "slots full again: no more fighters")

-- Wingmen re-follow every 30 s and on a craft change.
local follows = count("follow")
now = now + 31; update()
check(count("follow") == follows + 8, "six fighters and two tanks re-follow after 30 s")

-- Route navs: the convoy at the first nav marks the route's exit nav and the walker joins; contact clears them.
objs[colorado].x, objs[colorado].z = 2885, 100560
update()
check(count("on", "hidcam2") == 1, "route 1 marks the middle exit nav")
check(count("go_to", walker) == 1, "the walker goes to the first nav")
update()
check(count("on", "hidcam2") == 1 and count("go_to", walker) == 1, "arrival handled once")
env.M.retreat = true
update()
check(count("off", "hidcam1") == 1 and count("off", "hidcam2") == 1 and count("off", "hidcam3") == 1, "contact turns the three navs off")
update()
check(count("off", "hidcam1") == 1, "navs cleared once")

-- Howitzer: not before Colorado dies; a lost howitzer fails only after it was seen alive.
check(count("buildobject", nil) == 4, "no howitzer while Colorado lives")
objs[colorado].alive = false
update()
local how
for _, o in ipairs(orders) do if o[1] == "buildobject" and o[3] == "svartl" then how = o[2]; check(o[4].x == 2817 and o[4].z == 101123, "howitzer on N64 path 25") end end
check(how ~= nil, "howitzer built once Colorado is dead")
check(count("go_to", how) == 1 and count("on", how) == 1, "howitzer sent to the tower approach and marked")
update(); update()
check(count("buildobject") == 5, "only one howitzer")
check(count("attack") == 0, "no shelling before it is deployed")
objs[how].deployed = true
update()
check(count("attack", how) == 1 and orders[#orders][3] == tower1, "first target is the tower at label 23")
update()
check(count("attack", how) == 1, "one attack order per tower")
objs[tower1].alive = false
update()
check(count("attack", how) == 2 and orders[#orders][3] == tower2, "then the tower at label 26")
objs[tower2].alive = false
update()
check(count("off", how) == 1 and env.M.pilot.howDone, "both towers dead: howitzer marker off, branch done")
objs[how].alive = false
update()
check(#fails == 0, "a howitzer lost after the job is not a failure")
check(count("buildobject") == 5, "no second howitzer")

-- Fail: the howitzer lost mid-job (a fresh state), armed only once seen alive.
do
    env.M.pilot = nil
    objs[colorado].alive = false
    objs[tower1].alive, objs[tower2].alive = true, true
    env.M.pilot = Branch.NewState()
    env.M.pilot.started = true; env.M.pilot.tower1 = tower1; env.M.pilot.tower2 = tower2
    update()
    local newHow = count("buildobject")
    check(newHow == 6, "a fresh state builds its own howitzer")
    local h2
    for i = #orders, 1, -1 do if orders[i][1] == "buildobject" and orders[i][3] == "svartl" then h2 = orders[i][2]; break end end
    objs[h2].alive = false
    update()
    check(#fails == 1 and fails[1][2] == "misns1l2.des" and fails[1][1] == now + 5, "howitzer lost: the mission fails after 5 s")
    update()
    check(#fails == 1, "fails once")
end
do
    -- Unseen: a howitzer lost before it was ever observed alive (mid-mission toggle) does not fail.
    local P = Branch.NewState()
    P.started = true; P.howArmed = true; P.how = "gone"
    env.M.pilot = P
    objs.gone = { alive = false, team = 1, odf = "svartl" }
    update()
    check(#fails == 1, "an armed howitzer never seen alive does not fail the mission")
end

-- No fail once the mission is won.
do
    local P = Branch.NewState()
    P.started = true; P.howArmed, P.howSeen, P.how = true, true, "gone"
    env.M.pilot = P
    env.M.missionwon = true
    update()
    check(#fails == 1, "no failure after the win")
    env.M.missionwon = false
end

-- Adoption: no double registration across enable cycles, no new placement orders.
do
    env.M.pilot = nil
    objs.pre.alive, objs.tank1.alive, objs.tank2.alive = true, true, true
    local P = Pilot.State()
    mode.enable()
    local o0 = #orders
    check(P.f1 ~= nil, "fresh adoption fills slots")
    for _ = 1, 50 do
        enabled = false; mode.disable(); mode.addObject("pre")
        enabled = true; mode.enable(); mode.addObject("pre")
    end
    local follows2 = 0
    for i = o0 + 1, #orders do if orders[i][1] == "follow" or orders[i][1] == "go_to" or orders[i][1] == "buildobject" then follows2 = follows2 + 1 end end
    check(follows2 == 0, "50 off/on cycles issue no duplicate placement orders")
    check(P.nextSweep == 0, "disable re-arms the lock sweep")
end

-- Pods: ssprepa/sspammo builds never count as fighters or scavengers.
do
    local P = Pilot.State()
    local before2 = P.f6
    spawn("pod_x", "ssprepa")
    check(P.f6 == before2 and P.scav1 ~= "pod_x", "a pod does not take a unit slot")
end

-- Disabled: units are left alone.
enabled = false
local keep = #orders
local off = obj("off", "svfigh")
if enabled then mode.addObject(off) end
check(#orders == keep, "no orders while Pilot Mode is off")

print("misns1 Pilot Mode branch checks passed: " .. checks)
