-- Execute misn18cr's N64 Pilot Mode branch (PilotUpdate/PilotAddObject) with
-- stubbed natives: tanks follow, the four free turrets (once), the 10 s
-- fighter orders near/away from the transport, the recycler queue, adoption
-- on enable and off/on cycles.
local file = assert(io.open("Scripts/misn18cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("(local PILOT_TURRET_SPOTS.-)\n%-%- CR pilot mode <<"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local now, scrap, pilots, enabled = 0, 100, 5, true
local objs, built, orders, turrets = {}, {}, {}, {}
local dists = {}
local function obj(name, odf, t)
    objs[name] = { odf = odf, team = t or 1, alive = true, deployed = false, busy = false, cmd = 0 }
    return name
end
local player = obj("player", "avhover")
local rec = obj("avrecy2_recycler", "avrecy"); objs[rec].deployed = true
local tank1, tank2 = obj("avtank0_wingman", "avtank"), obj("avtank1_wingman", "avtank")
local transport = obj("hbtran0038_i76building", "hbtran00", 2)
local th = {}
for i, n in ipairs({ "hbtrn20049_i76building", "hbtrn20050_i76building", "hbtrn20051_i76building", "hbtrn20052_i76building" }) do
    th[i] = obj(n, "hbtrn200", 2)
end
local env = setmetatable({}, { __index = _G })
env.M = { missionstart = true, avrec = rec, transport = transport,
    thrusterone = th[1], thrustertwo = th[2], thrusterthree = th[3], thrusterfour = th[4] }
env.AiCommand = { NONE = 0, GO = 3, RECYCLE = 12 }
env.GetTime = function() return now end
env.GetPlayerHandle = function() return player end
env.GetHandle = function(n) return objs[n] and n or nil end
env.IsAlive = function(h) return objs[h] ~= nil and objs[h].alive end
env.IsValid = env.IsAlive
env.IsDeployed = function(h) return objs[h].deployed end
env.IsBusy = function(h) return objs[h].busy end
env.IsOdf = function(h, odf) return objs[h].odf == odf end
env.GetTeamNum = function(h) return objs[h].team end
env.GetScrap = function() return scrap end
env.GetPilot = function() return pilots end
env.AddScrap = function(_, n) scrap = scrap + n end
env.AddPilot = function(_, n) pilots = pilots + n end
env.GetCurrentCommand = function(h) return objs[h].cmd end
env.GetCurrentWho = function() return nil end
env.Distance = function(a, b) return dists[a .. ":" .. b] or 10000 end
env.AllCraft = function() return function() return nil end end
env.AllObjects = function()
    local names = {}
    for k, o in pairs(objs) do if o.alive then names[#names + 1] = k end end
    table.sort(names)
    local i = 0
    return function() i = i + 1; return names[i] end
end
env.SetCommand = function(h, cmd) orders[#orders + 1] = { "cmd", h, cmd } end
env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
env.GetTerrainHeightAndNormal = function() return 7 end
env.Follow = function(h, t) orders[#orders + 1] = { "follow", h, t } end
env.Attack = function(h, t) orders[#orders + 1] = { "attack", h, t } end
env.Build = function(h, odf) built[#built + 1] = odf; objs[h].busy = true end
env.BuildObject = function(odf, team, where) turrets[#turrets + 1] = { odf, team, where } end
local initArgs
env.PlayerPilotMode = { IsEnabled = function() return enabled end,
    Initialize = function(adapter, saved) initArgs = { adapter = adapter, saved = saved } end }
env.PilotBranch = assert(loadfile("Scripts/CRPilotBranch.lua"))()
for _, fn in pairs(env.PilotBranch) do if type(fn) == "function" then setfenv(fn, env) end end
local chunk = assert(loadstring("local M, PlayerPilotMode, PilotBranch = M, PlayerPilotMode, PilotBranch\n" ..
    "local campaignRuntime = nil\n" .. block ..
    "\nreturn { update = PilotUpdate, add = PilotAddObject, init = InitializePilotMode }"))
setfenv(chunk, env)
local api = chunk()
local M = env.M
local function spawn(name, odf) obj(name, odf); return api.add(name) end
local function count(kind, who, target)
    local n = 0
    for _, o in ipairs(orders) do
        if o[1] == kind and (who == nil or o[2] == who) and (target == nil or o[3] == target) then n = n + 1 end
    end
    return n
end
local function builtCount(odf) local n = 0 for _, b in ipairs(built) do if b == odf then n = n + 1 end end return n end

-- Disabled: nothing is consumed or ordered.
enabled = false
spawn("off1", "avfigh") -- PlayerPilotMode never calls update while off
check(M.pilot == nil and #orders == 0 and #built == 0 and #turrets == 0, "disabled: nothing happens")
enabled = true
M.pilot = nil; objs.off1 = nil

-- Initialize hands PlayerPilotMode a scripted adapter and the saved state.
M.playerPilotModeState = { baselineConfig = 1 }
api.init()
check(initArgs.adapter.scripted == true and initArgs.adapter.update == api.update
    and initArgs.saved == M.playerPilotModeState, "scripted adapter wired with saved state")

-- Not before the mission start.
M.missionstart = false
api.update()
check(#orders == 0 and #turrets == 0, "nothing before missionstart")
M.missionstart = true

-- Start (C 311-322): the tanks follow, four free avturr on the path 44-47 spots.
api.update()
check(count("follow", tank1, player) == 1 and count("follow", tank2, player) == 1, "tanks follow the player")
check(#turrets == 4 and turrets[1][1] == "avturr" and turrets[1][2] == 1, "four team-1 avturr")
check(turrets[1][3].x == 1824 and turrets[1][3].z == 98036 and turrets[4][3].x == 2019 and turrets[4][3].z == 98044,
    "turrets at the path 44 and 47 positions")

-- Guard: re-enabling, a repeated update and a saved/loaded state cannot spawn them again.
initArgs.adapter.disable(); initArgs.adapter.enable()
api.update()
M.pilot.started = false -- a save/load keeps the flag table but the start block re-runs only if started is lost
api.update()
check(#turrets == 4, "turrets spawn once even if the start block re-runs")
M.pilot.started = true

-- Recycler queue: one scavenger (with top-up), then avfigh while a slot is empty.
check(built[1] == "avscav" and M.pilot.scavBuilt, "the scavenger is the first build")
built = {}; M.pilot.scavBuilt = false; objs[rec].busy = false
scrap, pilots = 2, 0
now = 1; api.update()
check(built[1] == "avscav" and scrap >= 4 and pilots == 1, "scavenger after the scrap/pilot top-up")
objs[rec].busy = false; scrap = 100
now = 2; api.update()
check(built[2] == "avfigh", "first avfigh after the scavenger")
objs[rec].busy = false
now = 3; api.update()
check(builtCount("avscav") == 1 and builtCount("avfigh") == 2, "only one scavenger; fighters while slots are empty")
scrap = 5; objs[rec].busy = false
now = 4; api.update()
check(builtCount("avfigh") == 2, "avfigh waits for 6 scrap")
scrap = 100

-- A new avfigh away from the transport follows the player.
local f = {}
for i = 1, 8 do f[i] = "fig" .. i end
orders = {}
spawn(f[1], "avfigh")
check(count("follow", f[1], player) == 1, "new fighter follows the player")
check(M.pilot.fighterCount == 1 and M.pilot.fighters[1] == f[1], "fighter slot filled")
check(api.add(f[1]) == nil and count("follow", f[1]) == 1, "claimed fighter is not registered twice")

-- Every 10 s: fighters follow away from the transport, tanks always follow.
orders = {}
now = 20; api.update()
check(count("follow", f[1], player) == 1 and count("follow", tank1, player) == 1, "10 s order: follow")
check(count("attack") == 0, "no attack away from the transport")
-- Near the transport: attack the first standing thruster, one at a time.
dists["player:" .. transport] = 100
orders = {}
now = 31; api.update()
check(count("attack", f[1], th[1]) == 1 and count("follow", f[1]) == 0, "near the transport: attack thruster 1")
check(count("follow", tank2, player) == 1, "tanks still follow near the transport")
objs[th[1]].alive = false
orders = {}
now = 42; api.update()
check(count("attack", f[1], th[2]) == 1, "next thruster after the first dies")
orders = {}
spawn(f[2], "avfigh")
check(count("attack", f[2], th[2]) == 1, "new fighter near the transport attacks the first standing thruster")

-- Fill the eight slots: no further fighter is ordered.
for i = 3, 8 do spawn(f[i], "avfigh") end
objs[rec].busy = false
local before = builtCount("avfigh")
now = 43; api.update()
check(builtCount("avfigh") == before, "eight fighters: queue idle")
objs[f[5]].alive = false
now = 44; api.update()
check(builtCount("avfigh") == before + 1, "a lost fighter is rebuilt")

-- Adoption on enable: existing fighters registered once; an off/on cycle repeats nothing.
local builds, turretCount = #built, #turrets
initArgs.adapter.disable()
initArgs.adapter.enable()
orders = {}
objs[rec].busy = true
now = 45; api.update()
check(#built == builds and #turrets == turretCount and count("attack") == 0, "off/on cycle repeats no builds or turrets")
check(M.pilot.fighterCount == 8, "fighters are not counted again on re-adoption")

print("misn18 pilot mode: " .. checks .. " checks passed")
