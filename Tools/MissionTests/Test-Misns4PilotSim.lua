-- Win-path simulation for misns4cr's N64 Pilot Mode branch. The win (misns4cr.lua ~520) is four of the five
-- convoy haulers reaching "goal"; the haulers are driven by the mission itself (AddObject sends them to the
-- "escort" path), so the pilot block's AI duties are the support chain the player cannot do while flying:
--   1. the recycler builds an armory (svslf, 6 scrap), a scavenger, then four fighters (scrap and a pilot each),
--      one blocking chain (~117-131), and the fighters follow the player;
--   2. the armory drives to the nearest of the seven map geysers and deploys (Goto + Resend, ~83, ~110);
--   3. once the player has reached warn1 (M.warning, ~464) the deployed armory builds three ammo and three
--      repair pods (BuildAt at the fixed spot, ~133) one after the other, all affordable.
-- Hand-set / assumed: the recycler stands deployed at the start, starting scrap 50 (the script's AddScrap, ~375;
-- the BZN's own starting scrap is UNVERIFIED), 30 pilots (SetPilot, ~378). M.warning is set by hand when the
-- player is within 200 m of warn1, as the mission does. The convoy itself is not simulated (mission code).
-- Run from the repo root:  lua5.1 Tools/MissionTests/Test-Misns4PilotSim.lua
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")
local CMD = PilotSim.AiCommand

local function run(stall)
    local sim = PilotSim.new{ name = "misns4" .. (stall and "+stall" or ""), script = "Scripts/misns4cr.lua",
        bzn = "Missions/misns4cr.bzn", pattern = "(local PILOT_WHERE =.-)\n%-%- CR pilot mode <<",
        exports = "update = PilotUpdate, add = PilotAddObject", scrap = 50, pilots = 30 }
    local api, M = sim.api, sim.M
    sim:hook(function(h) return api.add(h) end)
    local rec, player = sim:get("svrecy0_recycler"), sim.player
    sim:unit(rec).deployed = true
    M.start_done, M.warning = true, false
    M.cam1 = sim:add("spcamr", 1, sim:pos("camerapt"))
    sim:track("rec", rec); sim:track("player", player)
    sim:each(function(s) -- the player flies to warn1 after 30 s
        if s.t < 30 then return end
        local p, x, z = s:unit(player), s:pos("warn1")
        local dx, dz = x - p.x, z - p.z
        local d = math.sqrt(dx * dx + dz * dz)
        if d > 5 then local k = math.min(p.speed * s.dt, d) / d; p.x, p.z = p.x + dx * k, p.z + dz * k end
    end)
    sim:when(function(s) return s:dist(player, "warn1") < 200 end, function() M.warning = true end)

    local function built(odf) local n = 0; for _, b in ipairs(sim.built) do if b.odf == odf then n = n + 1 end end; return n end
    local armory
    sim.onSpawn = function(h) if sim:unit(h).odf == "svslf" then armory = h; sim:track("armory", h) end end
    if stall then
        -- the armory's Goto to its geyser is dropped as soon as it is given; Resend must send it again
        local seen
        sim:each(function(s)
            if armory and not seen then seen = true; s:stallOnce(armory, function() return true end) end
        end)
    end

    sim:runFor(1)
    sim:runUntil(function() return armory ~= nil end, 30, "the recycler to build the armory")
    sim:runUntil(function(s) return s:unit(armory).deployed end, 120, "the armory to deploy on a geyser")
    sim:expect(sim:dist(armory, "eggeizr14_geyser") < 15, "the armory stands on its nearest geyser (eggeizr14)")
    if stall then sim:expect(sim:stallsFired() >= 1, "the armory's Goto was dropped once") end
    sim:runUntil(function() return built("svscav") == 1 and built("svfigh") == 4 end, 200, "the scavenger and four fighters")
    local fightersAt = sim.t
    sim:expect(sim.refused == 0, "nothing was refused for lack of scrap (" .. sim.refused .. ")")
    -- Pods: held back until the player reaches warn1.
    local podsBefore = built("sspammo") + built("ssprepa")
    sim:expect(M.warning or podsBefore == 0, "no pod before the bridge warning")
    sim:runUntil(function() return M.warning end, 200, "the player to reach warn1")
    sim:runUntil(function() return built("sspammo") == 3 and built("ssprepa") == 3 end, 200, "three ammo and three repair pods")
    sim:runFor(60)
    sim:expect(built("sspammo") == 3 and built("ssprepa") == 3, "exactly six pods")
    sim:expect(sim.refused == 0, "no build refused (" .. sim.refused .. ")")
    -- The order: ammo first, then repair.
    local seq = {}
    for _, b in ipairs(sim.built) do if b.odf:match("^ss") then seq[#seq + 1] = b.odf end end
    sim:expect(table.concat(seq, ",") == "sspammo,sspammo,sspammo,ssprepa,ssprepa,ssprepa", "pod order " .. table.concat(seq, ","))
    sim:expect(not sim.failed, "the branch did not fail the mission")
    return sim, fightersAt
end

local sim, f = run(false)
print(string.format("misns4 PilotSim OK (no stall): armory deployed, scav + 4 fighters by t=%.0f s, six pods done t=%.0f s, script %s", f, sim.t, sim.scriptPath))
sim = run(true)
print(string.format("misns4 PilotSim OK (armory Goto dropped once, Resend recovers): six pods done t=%.0f s", sim.t))
