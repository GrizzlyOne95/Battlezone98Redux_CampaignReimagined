-- Win-path simulation for misns6cr's N64 Pilot Mode branch. AI duties (the player cannot do these alone):
--   1. the recycler (svrecy0_recycler) is sent to geyser eggeizr13 and deploys (Branch.Resend, 6 s delay);
--      the mission is lost if it dies (misns6cr.lua ~560), and it is the player's only producer.
--   2. the three walkers follow the player to the field HQ, and once the beacon stage starts (human within
--      300 m of the HQ, misns6cr.lua ~536) they are ordered to Attack it and must close to attack range.
-- Hand-set flags: M.start_done, M.last_objective (set when the player is within 300 m of the HQ, as the script
-- does); the HQ's death (the win, ~550) is modelled as "a walker in Attack range for 10 s kills it".
-- The scenario's Attack stall (a walker drops its Attack order once) is re-sent by PilotBranch.Keep.
-- Run from the repo root:  lua5.1 Tools/MissionTests/Test-Misns6PilotSim.lua
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")
local CMD = PilotSim.AiCommand
local WALKERS = { "svwalk0_walker", "svwalk1_walker", "svwalk2_walker" }

local function run(opts)
    local sim = PilotSim.new{ name = "misns6" .. (opts.stall and "+stall" or "") .. (opts.dropAttack and "+dropAttack" or ""),
        script = "Scripts/misns6cr.lua", bzn = "Missions/misns6cr.bzn",
        pattern = "(%-%- CR pilot mode >>\n.-\n%-%- CR pilot mode <<)",
        exports = "pilot = Pilot", scrap = 20, pilots = 0 } -- SetScrap(1, 20) at start (~419)
    local Pilot = sim.api.pilot
    local M = sim.M
    M.start_done, M.last_objective = true, false
    M.recy, M.goal = sim:get("svrecy0_recycler"), sim:get("abcafe8_i76building")
    sim.update = function() Pilot.Update() end
    local rec, geyser, player = M.recy, "eggeizr13_geyser", sim.player
    sim:track("rec", rec); sim:track("player", player); sim:track("goal", M.goal)
    for i, w in ipairs(WALKERS) do sim:track("walker" .. i, w) end
    local goalPos = { x = select(1, sim:pos(M.goal)), z = select(2, sim:pos(M.goal)) }

    if opts.stall then sim:stallOnce(rec, function() return true end) end -- the Goto to the geyser is dropped once

    -- The player flies from the start to a point 280 m short of the HQ (inside the 300 m trigger).
    local px, pz = sim:pos(player)
    local len = math.sqrt((goalPos.x - px) ^ 2 + (goalPos.z - pz) ^ 2)
    local stopAt = { x = goalPos.x + (px - goalPos.x) / len * 280, z = goalPos.z + (pz - goalPos.z) / len * 280 }
    local flying = false
    sim:each(function(s)
        if not flying then return end
        local p = s:unit(player)
        local dx, dz = stopAt.x - p.x, stopAt.z - p.z
        local d = math.sqrt(dx * dx + dz * dz)
        if d > 1 then local k = math.min(p.speed * s.dt, d) / d; p.x, p.z = p.x + dx * k, p.z + dz * k end
    end)
    -- Beacon stage as the script does it (~536): a human within 300 m of the HQ.
    sim:when(function(s) return not M.last_objective and s:dist(player, M.goal) < 300 end, function() M.last_objective = true end)
    -- Win model: a walker attacking within range for 10 s destroys the field HQ.
    local inRange
    sim:each(function(s)
        local firing = false
        for _, w in ipairs(WALKERS) do
            local u = s:unit(w)
            if u.alive and u.cmd == CMD.ATTACK and u.tgt == M.goal and s:dist(w, M.goal) <= 65 then firing = true end
        end
        if firing then inRange = inRange or s.t; if s.t - inRange >= 10 then s:unit(M.goal).alive = false end
        else inRange = nil end
    end)
    local dropped = {}
    if opts.dropAttack then -- each walker loses its Attack order once, 5 s after receiving it
        local seen = {}
        sim:each(function(s)
            for _, w in ipairs(WALKERS) do
                local u = s:unit(w)
                if u.cmd == CMD.ATTACK and not seen[w] then seen[w] = s.t end
                if seen[w] and not dropped[w] and s.t >= seen[w] + 5 and u.cmd == CMD.ATTACK then
                    u.cmd, u.tgt = CMD.NONE, nil; dropped[w] = true; s:say("Attack order dropped by " .. w)
                end
            end
        end)
    end

    -- Duty 1: the recycler deploys on the geyser.
    sim:runUntil(function(s) return s:unit(rec).deployed end, 120, "the recycler to deploy on eggeizr13")
    sim:expect(sim:dist(rec, geyser) < 15, "recycler stands on the geyser")
    if opts.stall then sim:expect(sim:stallsFired() == 1, "the Goto stall fired") end
    local deployedAt = sim.t
    -- Duty 2: the walkers follow the player while it flies to the HQ.
    flying = true
    sim:runUntil(function() return M.last_objective end, 200, "the player to come within 300 m of the field HQ")
    local beacon = sim.t
    for _, w in ipairs(WALKERS) do
        sim:expect(sim:unit(w).cmd == CMD.FOLLOW, w .. " is following the player (it lags behind at walker speed)")
    end
    sim:runUntil(function(s) return not s:unit(M.goal).alive end, 400, "the walkers to close on and destroy the field HQ")
    sim:expect(not sim.failed, "the branch did not fail the mission")
    return sim, deployedAt, beacon
end

local sim, d1, b1 = run({})
print(string.format("misns6 PilotSim OK (no stall): recycler deployed t=%.0f s, beacon stage t=%.0f s, HQ down t=%.0f s, script %s", d1, b1, sim.t, sim.scriptPath))
sim, d1, b1 = run({ stall = true })
print(string.format("misns6 PilotSim OK (recycler Goto dropped once): recycler deployed t=%.0f s (Resend), HQ down t=%.0f s", d1, sim.t))

-- A walker's Attack order dropped once is re-sent by PilotBranch.Keep.
sim = run({ dropAttack = true })
print(string.format("misns6 PilotSim OK (a walker's Attack order dropped once): HQ down t=%.0f s", sim.t))
