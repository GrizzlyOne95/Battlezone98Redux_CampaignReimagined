-- Win-path simulation for misn09cr's N64 Pilot Mode branch: after the artillery is cleared the
-- factory deploys on the cut-off geyser, the scavengers must earn scrap, and the build queue
-- (tank, tank, tug, tank, walker) must complete with the tug affordable. Run from the repo root:
--   lua5.1 Tools/MissionTests/Test-Misn09PilotSim.lua
-- Evidence against the old script: PILOTSIM_SCRIPT=<file from `git show 676199e9^:Scripts/misn09cr.lua`>
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")

local sim = PilotSim.new{ name = "misn09", script = "Scripts/misn09cr.lua", bzn = "Missions/misn09cr.bzn",
    pattern = "(local function PilotState%(%).-)\n%-%- CR pilot mode <<",
    exports = "update = PilotUpdate, add = PilotAddObject",
    scrap = 20, pilots = 7 } -- misn09cr.lua ~2076: SetScrap(1, 20) / SetPilot(1, 7) when the factory meets the player
local M = sim.M
M.start_done = true
M.nsdfmuf, M.nsdfrig, M.nsdfslf = "avmuf", "rig", "avslf"
M.avscav1, M.avscav2, M.avscav3 = "scav1", "scav2", "scav3"
M.cut_off_geyser, M.nav1 = "cut_off_geyser", "cam1"
M.recon_artil = true
M.objective1 = true -- the player cleared the artillery (the branch's trigger for the factory move)
for _, k in ipairs({ "avmuf", "rig", "avslf", "scav1", "scav2", "scav3" }) do sim:track(k, k) end
sim:track("player", sim.player)

-- The engine's AddObject call; the mission itself tracks the silo as M.avsilo after the branch declines it.
sim:hook(function(h) return sim.api.add(h) end)
local tug, tanks, scrapAtTug = nil, 0, nil
sim.onSpawn = function(h, consumed)
    local o = sim:unit(h)
    if o.odf == "absilo" and M.avsilo == nil then M.avsilo = h end
    if o.odf == "avhaul" then tug = h; sim:track("tug", h) end
    if o.odf == "avtank" then tanks = tanks + 1 end
end
-- Record the scrap the moment the tug is ordered (it must have been affordable, not refused).
local nativeBuild = sim.env.Build
sim.env.Build = function(h, odf, ...)
    if odf == "avhaul" then scrapAtTug = sim.env.GetScrap(1) end
    return nativeBuild(h, odf, ...)
end

sim:runUntil(function(s) return s:unit("avmuf").deployed end, 300, "the factory to deploy on the cut-off geyser")
local deployedAt = sim.t
sim:expect(sim:dist("avmuf", "cut_off_geyser") < 15, "factory stands on the cut-off geyser")
local incomeAtDeploy = sim.income
sim:expect(incomeAtDeploy == 0, "no scrap was earned before the factory deployed (scavengers followed it)")

sim:runUntil(function(s) return tug ~= nil end, 250, "the tug (avhaul) to be built")
sim:expect(sim.refused == 0, "no build order was refused for lack of scrap (refused " .. sim.refused .. ")")
sim:expect(scrapAtTug and scrapAtTug >= 6, "the tug was ordered with 6+ scrap on hand")
sim:expect(sim.income > 0, "the scavengers earned scrap after the factory deployed")
local scavving = 0
for _, k in ipairs({ "scav1", "scav2", "scav3" }) do if sim:unit(k).cmd == PilotSim.AiCommand.SCAVENGE then scavving = scavving + 1 end end
sim:expect(scavving == 3, "all three scavengers are in SCAVENGE mode (" .. scavving .. ")")
sim:expect(M.pilot.plHaul == tug and M.pilot.tugFailArmed, "the branch registered the tug")

-- The queue completes: three tanks, the tug and the walker; the rig recycled itself after the silo.
local function built(odf) local n = 0; for _, b in ipairs(sim.built) do if b.odf == odf then n = n + 1 end end; return n end
sim:runUntil(function(s) return built("avwalk") == 1 and not s:unit("avmuf").build end, 300, "the build queue to complete (3 avtank, avhaul, avwalk)")
sim:expect(built("avtank") == 3 and built("avhaul") == 1 and built("avwalk") == 1, "queue built 3 tanks, 1 tug, 1 walker")
sim:expect(built("absilo") == 1 and not sim:unit("rig").alive, "silo built, rig recycled")
-- Order check: the tug comes before the third tank (the CR adaptation).
local order = {}
for _, b in ipairs(sim.built) do if b.odf ~= "absilo" then order[#order + 1] = b.odf end end
sim:expect(table.concat(order, ",") == "avtank,avtank,avhaul,avtank,avwalk", "queue order: " .. table.concat(order, ","))
sim:expect(not sim.failed, "the branch did not fail the mission")
print(string.format("misn09 PilotSim OK: factory deployed t=%.0f s, tug built with %d scrap in hand, queue done t=%.0f s, scrap earned %.1f, script %s",
    deployedAt, scrapAtTug, sim.t, sim.income, sim.scriptPath))
