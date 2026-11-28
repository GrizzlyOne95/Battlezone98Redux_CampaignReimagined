-- Execute misn09cr's N64 Pilot Mode branch (PilotUpdate/PilotAddObject) with
-- stubbed natives: start orders, build-queue order, escorts, supply pods, tug,
-- silo/constructor chain, fail conditions and the disabled path.
local file = assert(io.open("Scripts/misn09cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("(local function PilotState%(%).-)\n%-%- CR pilot mode <<"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local now, scrap, pilots, enabled = 0, 100, 10, true
local objs, built, orders, failed = {}, {}, {}, 0
local dists = {}
local function obj(name, odf, t) objs[name] = { odf = odf, team = t or 1, alive = true, deployed = false, busy = false, health = 1, ammo = 1, cmd = 0 }; return name end
local player = obj("player", "avhover")
local fact, cnst, slf = obj("fact", "avmuf"), obj("cnst", "avcns9"), obj("slf", "avslf")
local scav = { obj("s1", "avscav"), obj("s2", "avscav"), obj("s3", "avscav") }
obj("geyser", "eggeizr", 0); obj("cam1", "apcamr")
local relic = obj("relic", "obdata", 0)
local env = setmetatable({}, { __index = _G })
env.M = { start_done = true, nsdfmuf = fact, nsdfrig = cnst, nsdfslf = slf, nav1 = "cam1", cut_off_geyser = "geyser",
    avscav1 = scav[1], avscav2 = scav[2], avscav3 = scav[3], relic = relic }
env.AiCommand = { NONE = 0, GO = 3, RECYCLE = 12, SCAVENGE = 8 }
env.GetTime = function() return now end
env.GetPlayerHandle = function() return player end
env.IsAlive = function(h) return objs[h] ~= nil and objs[h].alive end
env.IsDeployed = function(h) return objs[h].deployed end
env.IsBusy = function(h) return objs[h].busy end
env.IsOdfBase = function(h, odf) return objs[h].odf == odf end
env.GetTeamNum = function(h) return objs[h].team end
env.GetHealth = function(h) return objs[h].health end
env.GetAmmo = function(h) return objs[h].ammo end
env.GetScrap = function() return scrap end
env.GetPilot = function() return pilots end
env.GetCurrentCommand = function(h) return objs[h].cmd end
env.GetCurrentWho = function() return nil end
env.GetDistance = function(a, b) return dists[a .. ":" .. b] or 10000 end
env.GetTug = function(h) return objs[h].tug end
env.AllCraft = function() return function() return nil end end
env.AllObjects = function()
    local names = {}
    for k, o in pairs(objs) do if o.alive then names[#names + 1] = k end end
    table.sort(names)
    local i = 0
    return function() i = i + 1; return names[i] end
end
env.IsValid = function(h) return objs[h] ~= nil and objs[h].alive end
env.SetCommand = function(h, cmd, pri, who) orders[#orders + 1] = { "cmd", h, cmd, who } end
env.SetUserTarget = function(h) orders[#orders + 1] = { "target", h } end
env.SetObjectiveOn = function(h) orders[#orders + 1] = { "objon", h } end
env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
env.GetTerrainHeightAndNormal = function() return 7 end
env.Goto = function(h, t) orders[#orders + 1] = { "go_to", h, t }; objs[h].cmd = 3 end
env.Follow = function(h, t) orders[#orders + 1] = { "follow", h, t } end
env.Attack = function(h, t) orders[#orders + 1] = { "attack", h, t } end
env.Pickup = function(h, t) orders[#orders + 1] = { "pickup", h, t } end
env.Dropoff = function(h, t) orders[#orders + 1] = { "dropoff", h, t } end
env.Build = function(h, odf) built[#built + 1] = odf; objs[h].busy = true end
env.BuildAt = function(h, odf, t) built[#built + 1] = odf .. "@" .. t end
env.FailMission = function() failed = failed + 1 end
local initArgs
env.PlayerPilotMode = { IsEnabled = function() return enabled end,
    Initialize = function(adapter, saved) initArgs = { adapter = adapter, saved = saved } end }
env.PilotBranch = assert(loadfile("Scripts/CRPilotBranch.lua"))()
for _, fn in pairs(env.PilotBranch) do if type(fn) == "function" then setfenv(fn, env) end end
local chunk = assert(loadstring("local M, PlayerPilotMode, PilotBranch = M, PlayerPilotMode, PilotBranch\n" .. block ..
    "\nreturn { update = PilotUpdate, add = PilotAddObject, init = InitializePilotMode }"))
setfenv(chunk, env)
local api = chunk()
local M = env.M
local function spawn(name, odf) obj(name, odf); return api.add(name) end
local function count(kind, who)
    local n = 0
    for _, o in ipairs(orders) do if o[1] == kind and (who == nil or o[2] == who) then n = n + 1 end end
    return n
end
local function lastOrder(kind) for i = #orders, 1, -1 do if orders[i][1] == kind then return orders[i] end end end

-- Disabled: nothing is consumed or ordered.
enabled = false
check(spawn("off1", "avtank") == false and spawn("off2", "avwalk") == false, "disabled: objects not consumed")
check(#orders == 0 and #built == 0, "disabled: no orders")
enabled = true
spawn("enemy1", "avtank"); objs.enemy1.team = 5
check(api.add("enemy1") == false and #orders == 0, "other teams ignored")
M.pilot = nil

-- Initialize hands PlayerPilotMode a scripted adapter and the saved state.
M.playerPilotModeState = { baselineConfig = 1 }
api.init()
check(initArgs.adapter.scripted == true and initArgs.adapter.update == api.update and initArgs.saved == M.playerPilotModeState,
    "scripted adapter wired with saved state")

-- Before the mission start nothing happens.
M.start_done = false
api.update()
check(#orders == 0 and #built == 0, "no orders before start_done")
M.start_done = true

-- Undeployed factory: nothing to build yet.
api.update()
check(#built == 0 and #orders == 0, "nothing built before the factory deploys")
check(M.pilot.cnstFailArmed == true, "constructor fail armed from the start")

-- Voice 542 stand-in: the recon message sets the user target to cam1 once.
M.recon_artil = true
api.update(); api.update()
check(count("target") == 1 and orders[1][2] == "cam1", "SetUserTarget(cam1) once on the recon message")

-- Artillery cleared: factory to geyser 13, rig and scavengers follow; re-sent after 6 s.
M.objective1 = true
now = 1; api.update()
check(lastOrder("go_to")[2] == fact and lastOrder("go_to")[3] == "geyser", "factory sent to cut_off_geyser")
check(count("follow", cnst) == 1 and count("follow", scav[1]) == 1 and count("follow", scav[3]) == 1, "rig and scavengers follow the factory")
check(count("target") == 2, "SetUserTarget(cam1) when the artillery is cleared")
objs[fact].cmd = 0; local gotos = count("go_to")
now = 2; api.update(); now = 9; api.update()
check(count("go_to") == gotos + 1, "undeployed factory re-sent to the geyser")

-- Deployed: the rig builds the silo once, the factory starts its queue.
objs[fact].deployed = true
now = 10; api.update()
check(built[1] == "absilo" and built[2] == "avtank", "silo ordered, then the first avtank: " .. table.concat(built, ","))
-- CR adaptation: deployed factory releases the three scavengers once.
check(count("cmd") == 3 and count("cmd", scav[1]) == 1 and count("cmd", scav[3]) == 1 and lastOrder("cmd")[3] == 8, "scavengers released to scavenge once the factory deploys")
check(M.pilot.dropPending == true, "silo drop-off pending")
now = 11; api.update()
check(lastOrder("dropoff")[2] == cnst and lastOrder("dropoff")[3].x == 2836 and lastOrder("dropoff")[3].z == 99811
    and lastOrder("dropoff")[3].y == 7, "rig drops off at the N64 silo spot")
check(#built == 2 and count("cmd") == 3, "busy factory and rig order nothing new; scavengers released only once")

-- The silo appears: it is not consumed (the mission tracks it) but arms recycle and silo-fail.
check(spawn("silo", "absilo") == false and M.pilot.recycleArmed and M.pilot.siloFailArmed, "silo arms recycle and silo-fail")
M.avsilo = "silo"
objs[cnst].busy = true
now = 12; api.update()
check(count("cmd", cnst) == 0, "no recycle while the rig is busy")
objs[cnst].busy = false
now = 13; api.update()
check(lastOrder("cmd")[2] == cnst and lastOrder("cmd")[3] == 12 and lastOrder("cmd")[4] == cnst, "rig recycled")
check(M.pilot.cnstFailArmed == false and M.pilot.recycleArmed == false, "recycle disarms the rig-loss fail")

-- CR adaptation: queue is tank, tank, tug, tank, then the avwalk.
local tanks = 1
check(spawn("t1", "avtank") == true and lastOrder("follow")[2] == "t1" and lastOrder("follow")[3] == fact, "tank 1 follows the factory")
objs[fact].busy = false
now = now + 1; api.update()
check(built[#built] == "avtank" and #built == 3, "queue item avtank 2")
check(spawn("t2", "avtank") == true, "tank 2 consumed"); objs[fact].busy = false
now = now + 1; api.update()
check(built[#built] == "avhaul" and #built == 4, "third item is the avhaul: " .. table.concat(built, ","))
check(M.pilot.siloFailArmed == false, "avhaul order disarms the silo-fail")
check(spawn("tug", "avhaul") == true and M.pilot.plHaul == "tug" and M.pilot.tugFailArmed, "tug recorded, tug-fail armed")
objs[fact].busy = false
now = now + 1; api.update()
check(built[#built] == "avtank" and #built == 5, "fourth item is the third avtank")
check(spawn("t3", "avtank") == true and M.pilot.ptank[3] == "t3", "tank 3 consumed as ptank[3]"); objs[fact].busy = false
now = now + 1; api.update()
check(built[#built] == "avwalk" and #built == 6, "fifth item is the avwalk")
check(spawn("walk", "avwalk") == true and lastOrder("follow")[2] == "walk" and M.nsdfgech1 == nil, "walker follows the factory, not tracked")
objs[fact].busy = false
local before = #built
now = now + 1; api.update()
check(#built == before, "queue idles when done")
scrap = 0
pilots = 0

-- Tug: picks up the free relic, follows the factory once the player side holds it.
M.relic_free = true
now = now + 1; api.update()
check(lastOrder("pickup")[2] == "tug" and lastOrder("pickup")[3] == relic, "tug picks up the free relic")
M.relic_free, M.relic_secure = false, true
now = now + 1; api.update()
check(lastOrder("follow")[2] == "tug" and lastOrder("follow")[3] == fact, "tug follows the factory with the relic")
M.relic_secure = false

-- Escorts attack the Soviet tug within 300 m, in N64 order, then follow the free relic.
objs.sv = { odf = "svhaul", team = 5, alive = true }
objs[relic].tug = "sv"; M.relic_seized = true
dists["fact:relic"] = 250
now = now + 1; api.update()
local attacks = {}
for _, o in ipairs(orders) do if o[1] == "attack" then attacks[#attacks + 1] = o[2] end end
check(#attacks == 4 and attacks[1] == "t1" and attacks[2] == "t2" and attacks[3] == "walk" and attacks[4] == "t3"
    and lastOrder("attack")[3] == "sv", "escorts attack the holder in N64 order")
M.relic_seized, M.relic_free = false, true
objs[relic].tug = nil
local follows = count("follow")
now = now + 1; api.update()
check(count("follow") == follows + 4, "escorts follow the freed relic")
M.relic_free = false

-- Supply: ammo first, one pod per 3 s from the armory, via BuildAt.
objs[slf].deployed = true; scrap = 50
objs[player].health, objs[player].ammo = 0.5, 0.5
now = now + 5; api.update()
check(built[#built] == "apammo@player", "ammo pod first: " .. table.concat(built, ","))
before = #built; now = now + 1; api.update()
check(#built == before, "3 s cooldown between pods")
now = now + 3; api.update()
check(built[#built] == "apammo@player" and #built == before + 1, "second ammo pod")
now = now + 3; api.update()
check(built[#built] == "aprepa@player", "then the repair pods")
now = now + 3; api.update()
check(built[#built] == "aprepa@player" and #built == before + 3, "second repair pod")
check(spawn("a1", "apammo") == true and spawn("r1", "aprepa") == true and lastOrder("objon")[2] == "r1", "pods consumed and highlighted")
check(M.pilot.ammoPending == 1 and M.pilot.repairPending == 1, "pending counts drop per delivered pod")

-- Losing the player tug fails the mission (once).
objs.tug.alive = false
M.pilot.cnstFailArmed = false
now = now + 1; api.update()
check(failed == 1 and M.game_over == true, "tug loss fails the mission")
now = now + 1; api.update()
check(failed == 1, "fail only once")

-- Constructor loss before the recycle also fails the mission.
M.game_over = false; M.pilot.tugFailArmed = false; M.pilot.cnstFailArmed = true
objs[cnst].alive = false
now = now + 1; api.update()
check(failed == 2, "rig loss fails the mission")

-- Adoption: units that exist before the mode is on (fresh branch state, as after
-- a load) are registered when the adapter's enable runs, and only once.
do
    local adapter = initArgs.adapter
    check(adapter and adapter.enable, "adapter has an enable hook")
    enabled = false
    check(spawn("pw", "avwalk") == false and spawn("pa", "apammo") == false, "not consumed while off")
    enabled = true
    M.pilot = nil
    adapter.enable()
    check(count("follow", "pw") == 1, "pre-existing walker adopted on enable")
    local P = M.pilot
    local a1, a2 = P.ammo1, P.ammo2
    check(a1 ~= nil and a2 ~= nil and a1 ~= a2, "ammo pod slots filled with two units")
    local total = #orders
    adapter.enable()
    check(api.add("pw") == false and api.add("pa") == false, "claimed units fall through to the mission tracking")
    check(#orders == total and count("follow", "pw") == 1 and P.ammo1 == a1 and P.ammo2 == a2, "no double registration")
end

print("misn09 Pilot Mode branch checks passed: " .. checks)
