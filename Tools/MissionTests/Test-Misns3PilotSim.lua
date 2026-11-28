-- Long-run simulation for misns3cr's N64 Pilot Mode branch. AI duties: NONE.
-- Reason: the pilot block only gives the four bombers (svhraz) follow orders on the player and sets the
-- user target (outpost nav, then the base nav). The win (misns3cr.lua ~497) is the player reaching
-- "homesweethome" after the Black Dog recycler died (~455), and the loss conditions (~505-521) are
-- player-side too (10 min timer, don't-go-here zones). No unit has to reach a place, deploy or build
-- on its own, so there is nothing to assert beyond: the block runs for a long simulated period without
-- errors or unmodelled natives, the bombers stay on the player, and the user target flips once.
-- Whether the pilot alone can kill the recycler is a balance question this sim does not model (UNVERIFIED).
-- Run from the repo root:  lua5.1 Tools/MissionTests/Test-Misns3PilotSim.lua
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")

local function run()
    local sim = PilotSim.new{ name = "misns3" , script = "Scripts/misns3cr.lua",
        bzn = "Missions/misns3cr.bzn", pattern = "(%-%- CR pilot mode >>\n.-\n%-%- CR pilot mode <<)",
        exports = "pilot = Pilot", scrap = 0, pilots = 0,
        update = nil }
    local Pilot = sim.api.pilot
    Pilot.Branch = sim.env.PilotBranch -- the co-op runtime region sets this in the real script
    local mode = Pilot.Mode
    sim.update = function() mode.update() end
    local M = sim.M
    M.missionstart, M.recyclerdestroyed = true, false
    M.cam1, M.cam2 = sim:get("basenav"), sim:get("avrecy")
    local bombers = { sim:get("bomb1"), sim:get("bomb2"), sim:get("bomb3"), sim:get("bomb4") }
    for i, b in ipairs(bombers) do M["bomb" .. i] = b; sim:track(b, b) end
    local player = sim.player
    sim:unit(player).speed = 12 -- slower than the bombers (15), so they can keep up
    -- The player flies to the Black Dog outpost, "kills" the recycler, then returns to homesweethome.
    local dest = { x = 3854, z = 101037 }
    sim:each(function(s)
        local p = s:unit(player)
        local dx, dz = dest.x - p.x, dest.z - p.z
        local d = math.sqrt(dx * dx + dz * dz)
        if d > 5 then local k = math.min(p.speed * s.dt, d) / d; p.x, p.z = p.x + dx * k, p.z + dz * k end
    end)
    local targets = {}
    local nativeTarget = sim.env.SetUserTarget
    sim.env.SetUserTarget = function(h) targets[#targets + 1] = h; nativeTarget(h) end
    sim:runFor(5)
    sim:expect(targets[1] == "avrecy", "the outpost nav is the first user target")
    sim:runUntil(function(s) return s:dist(player, dest) < 6 end, 400, "the player to reach the outpost")
    for _, b in ipairs(bombers) do
        sim:expect(sim:dist(b, player) < 80, b .. " followed the player to the outpost (dist " .. math.floor(sim:dist(b, player)) .. ")")
    end
    M.recyclerdestroyed = true
    dest = { x = 1208, z = 98940 }
    sim:runUntil(function(s) return s:dist(player, dest) < 6 end, 500, "the player to reach homesweethome")
    sim:runFor(60)
    for _, b in ipairs(bombers) do
        sim:expect(sim:dist(b, player) < 80, b .. " stayed with the player at home")
    end
    sim:expect(#targets == 2 and targets[2] == "basenav", "user target: outpost nav once, then the base nav once")
    sim:runFor(1800) -- a long idle stretch: periodic re-follow and Lock sweeps keep running without errors
    sim:expect(not sim.failed, "the branch did not fail the mission")
    -- Disable/enable cycles do not error and do not break the follow.
    for _ = 1, 20 do mode.disable(); mode.enable() end
    sim:runFor(10)
    return sim
end

local sim = run()
print(string.format("misns3 PilotSim OK (no AI duties; long run, bombers follow the player to the outpost and home): t=%.0f s, script %s",
    sim.t, sim.scriptPath))
