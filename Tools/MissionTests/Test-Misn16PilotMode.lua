-- Execute CRMisn16's N64 Pilot Mode branch (PilotUpdate/PilotAddObject) with
-- stubbed natives: start orders, armory removal, geyser re-send, the build
-- chain (scavengers, constructor, tanks), the base rebuild table, the factory
-- fail and adoption/disable cycles.
local file = assert(io.open("Scripts/CRMisn16.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("%-%- CR pilot mode >>\n(.-)\n%-%- CR pilot mode <<"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local function world(startedAt)
    local W = { now = 100, scrap = 50, pilots = 3, enabled = true }
    local objs, built, orders, fails, removed = {}, {}, {}, 0, {}
    W.objs, W.built, W.orders, W.removed = objs, built, orders, removed
    local function obj(name, odf, t, x, z)
        objs[name] = { odf = odf, team = t or 1, alive = true, deployed = false, busy = false, cmd = 0, x = x or 0, z = z or 0 }
        return name
    end
    W.obj = obj
    W.player = obj("player", "avtank", 1, 2900, 99500)
    W.rec = obj("avrecy0_recycler", "avrecy", 1, 2898, 99447)
    W.fac = obj("avmuf26_factory", "avmuf", 1, 2873, 99443)
    W.cons = obj("avcnst0_constructionrig", "avcnst", 1, 2893, 99526)
    W.recGeyser = obj("eggeizr112_geyser", "eggeizr1", 0, 2827, 99118)
    W.facGeyser = obj("eggeizr113_geyser", "eggeizr1", 0, 2923, 99243)
    W.cam = obj("apcamr11_camerapod", "apcamr", 1)
    W.armory = obj("avslf0_armory", "avslf", 1, 2896, 99495)
    local env = setmetatable({}, { __index = _G })
    env.M = { recy = W.rec, muf = W.fac, start_done = true }
    env.CR = { started = startedAt }
    env.AiCommand = { NONE = 0, GO = 3, FOLLOW = 5 }
    env.GetTime = function() return W.now end
    env.GetPlayerHandle = function() return W.player end
    env.GetHandle = function(l) return objs[l] and l end
    env.IsValid = function(h) return objs[h] ~= nil and objs[h].alive end
    env.IsAlive = env.IsValid
    env.IsDeployed = function(h) return objs[h].deployed end
    env.IsBusy = function(h) return objs[h].busy end
    env.IsOdf = function(h, odf) return objs[h].odf == odf end
    env.GetTeamNum = function(h) return objs[h].team end
    env.GetScrap = function() return W.scrap end
    env.AddScrap = function(_, n) W.scrap = W.scrap + n end
    env.GetPilot = function() return W.pilots end
    env.AddPilot = function(_, n) W.pilots = W.pilots + n end
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
    env.SetUserTarget = function(h) orders[#orders + 1] = { "target", h } end
    env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
    env.GetTerrainHeightAndNormal = function() return 7 end
    env.Goto = function(h, t) orders[#orders + 1] = { "go_to", h, t }; objs[h].cmd = 3 end
    env.Follow = function(h, t) orders[#orders + 1] = { "follow", h, t } end
    env.Dropoff = function(h, pos) orders[#orders + 1] = { "dropoff", h, pos } end
    env.Build = function(h, odf) built[#built + 1] = odf; objs[h].busy = true end
    env.RemoveObject = function(h) removed[#removed + 1] = h; objs[h].alive = false end
    env.Failure = function() fails = fails + 1 end
    env.PlayerPilotMode = { IsEnabled = function() return W.enabled end, Initialize = function(a) W.adapter = a end }
    env.PilotBranch = assert(loadfile("Scripts/CRPilotBranch.lua"))()
    for _, f in pairs(env.PilotBranch) do if type(f) == "function" then setfenv(f, env) end end
    local chunk = assert(loadstring(table.concat({
        "local M, PlayerPilotMode, PilotBranch, CR = M, PlayerPilotMode, PilotBranch, CR",
        "local function Valid(h) return h ~= nil and h ~= 0 and IsValid(h) end",
        "local function Alive(h) return Valid(h) and IsAlive(h) end",
        "local function IsOdfBase(h, n) return Valid(h) and (IsOdf(h, n) or IsOdf(h, n .. '.odf')) end",
        "local function State() return CR end",
        block, "return { update = PilotUpdate, add = PilotAddObject, init = InitializePilotMode }" }, "\n")))
    setfenv(chunk, env)
    W.api = chunk()
    W.api.init()
    W.env = env
    W.fails = function() return fails end
    function W.step(dt) W.now = W.now + (dt or 1); W.api.update() end
    function W.spawn(name, odf, team) obj(name, odf, team); W.api.add(name) end
    function W.count(kind, a, b)
        local c = 0
        for _, o in ipairs(orders) do
            if o[1] == kind and (a == nil or o[2] == a) and (b == nil or o[3] == b) then c = c + 1 end
        end
        return c
    end
    function W.builds(odf)
        local c = 0
        for _, b in ipairs(built) do if b == odf then c = c + 1 end end
        return c
    end
    return W
end

-- Start of the mission (mode on): nav target, geyser orders, armory removed.
local W = world(100)
W.step(1)
check(W.count("target", W.cam) == 1, "alien HQ nav is the user target")
check(W.count("go_to", W.rec, W.recGeyser) == 1 and W.count("go_to", W.fac, W.facGeyser) == 1, "recycler and factory sent to geysers 14/15")
check(#W.removed == 1 and W.removed[1] == W.armory, "armory removed when Pilot Mode is on at start")
check(#W.built == 0, "nothing built before the producers deploy")
local n = #W.orders
W.step(1)
check(#W.orders == n, "start orders run once")
W.objs[W.rec].cmd, W.objs[W.fac].cmd = 0, 0
W.step(1); W.step(7)
check(W.count("go_to", W.rec, W.recGeyser) == 2 and W.count("go_to", W.fac, W.facGeyser) == 2, "stalled producers re-sent after 6 s")

-- Deploy: two scavengers first (scrap and pilot topped up), then tanks.
W.objs[W.rec].deployed, W.objs[W.fac].deployed = true, true
W.scrap, W.pilots = 0, 0
W.step(1)
check(W.builds("avscav") == 1 and W.scrap == 4 and W.pilots == 1, "scavenger top-up raises scrap to 4 and a pilot")
W.objs[W.rec].busy = false; W.spawn("scav1", "avscav", 1)
W.step(1)
check(W.builds("avscav") == 2, "second scavenger queued")
W.objs[W.rec].busy = false; W.spawn("scav2", "avscav", 1); W.spawn("scav1b", "avscav", 1)
W.scrap = 11
W.step(1)
check(W.builds("avtank") == 0 and W.builds("avcnst") == 0, "existing constructor: nothing to build below the tank cost")
W.scrap = 12
W.step(1)
check(W.builds("avtank") == 1, "factory builds avtank at 12 scrap")
for i = 1, 4 do
    W.spawn("tank" .. i, "avtank", 1)
    check(W.count("follow", "tank" .. i, W.player) == 1, "new tank follows the player")
    W.objs[W.fac].busy = false; W.scrap = 0; W.step(1)
end
check(W.builds("avtank") == 1, "no fifth tank once four stand")
W.api.add("tank1")
check(W.count("follow", "tank1", W.player) == 1, "no double registration of a tank")
W.step(31)
check(W.count("follow", "tank1", W.player) >= 2, "tanks re-follow every 30 s")

-- Rebuild table: abhang first; falls through to absupp when the hangar is unaffordable.
W.scrap = 9
W.objs[W.cons].busy = false
W.step(1)
check(W.builds("absupp") == 1 and W.builds("abhang") == 0, "unaffordable hangar falls through to the supply depot")
W.step(1)
local d = W.orders[#W.orders]
check(d[1] == "dropoff" and d[2] == W.cons and d[3].x == 2886 and d[3].z == 99286 and d[3].y == 7, "depot dropped at (2886, 99286)")
W.objs[W.cons].busy = false
W.step(1)
check(W.builds("abhang") == 0 and W.builds("abspow") == 0, "one building at a time until the first appears")
W.spawn("supp", "absupp", 1)
W.scrap = 20
W.step(1)
check(W.builds("abhang") == 1, "hangar built when affordable")
W.step(1)
d = W.orders[#W.orders]
check(d[1] == "dropoff" and d[3].x == 3001 and d[3].z == 99204, "hangar dropped at (3001, 99204)")
W.objs[W.cons].busy = false; W.spawn("hang", "abhang", 1)
W.scrap = 7
W.step(1)
check(W.builds("abspow") == 0 and W.builds("abtowe") == 0, "power plant unaffordable ends the chain")
W.scrap = 8
W.step(1)
check(W.builds("abspow") == 1, "power plant built at 8 scrap")
W.step(1)
W.objs[W.cons].busy = false; W.spawn("pow1", "abspow", 1)
W.scrap = 10
W.step(1)
check(W.builds("abtowe") == 1, "first tower built after the power plant")
W.step(1)
d = W.orders[#W.orders]
check(d[1] == "dropoff" and d[3].x == 2903 and d[3].z == 99059, "first tower dropped at (2903, 99059)")

-- Replacement constructor: the old one dies, the recycler builds a new one.
W.objs[W.cons].alive = false
W.objs[W.rec].busy = false
W.scrap = 12
W.step(1)
check(W.builds("avcnst") == 1, "recycler rebuilds a lost constructor")
W.spawn("cons2", "avcnst", 1)
check(W.env.M.pilot.cnst == "cons2" and W.env.M.pilot.buildSlot == 0, "new constructor tracked, slot cleared")

-- Disable/enable cycles issue no duplicate orders.
check(W.adapter and W.adapter.enable and W.adapter.disable, "adapter hooks present")
W.enabled = false
local before = #W.orders
W.spawn("offtank", "avtank", 1)
check(#W.orders == before, "no orders while Pilot Mode is off")
W.enabled = true
W.adapter.enable()
local after = #W.orders
check(W.count("follow", "offtank", W.player) == 1, "tank built while off is adopted once")
W.adapter.disable(); W.adapter.enable()
check(#W.orders == after, "disable/enable cycle adds no duplicate orders")

-- Factory lost fails the mission.
W.objs[W.fac].alive = false
W.step(1)
check(W.fails() == 1, "losing the factory fails the mission")
W.step(1)
check(W.fails() == 1, "factory-loss fail fires once")

-- Pilot Mode switched on mid-mission keeps the armory.
local late = world(0)
late.now = 500
late.step(1)
check(#late.removed == 0 and late.objs[late.armory].alive, "armory stays when Pilot Mode is enabled mid-mission")
print("misn16 Pilot Mode branch checks passed: " .. checks)
