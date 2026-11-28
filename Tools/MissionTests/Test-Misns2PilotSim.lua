-- Win-path simulation for misns2cr's N64 Pilot Mode branch: the three transports must reach the
-- last nav of the chain (player flying along), halt at the minefield until the five tracked
-- mines die, and return to nav 1 after the ambush film. Run from the repo root:
--   lua5.1 Tools/MissionTests/Test-Misns2PilotSim.lua
-- Evidence runs against older code:
--   PILOTSIM_PREFIX=all|nonudge|noresend   strips the CR adaptations from the current script
--   PILOTSIM_SCRIPT=<path>                 any other script file (misns2cr had no pilot block before 676199e9)
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")

-- Derive the pre-adaptation variants by removing the two CR adaptation blocks in memory.
local function strip(source)
    local mode = os.getenv("PILOTSIM_PREFIX")
    if not mode then return source end
    local function cut(s, from, to)
        local i = assert(s:find(from, 1, true), "anchor not found: " .. from)
        local j = assert(s:find(to, i, true), "anchor not found: " .. to)
        return s:sub(1, i - 1) .. s:sub(j)
    end
    if mode == "all" or mode == "nonudge" then
        source = cut(source, "elseif not k and not P.nudged", "\n        end\n    end\n")
    end
    if mode == "all" or mode == "noresend" then
        source = cut(source, "    if P.target and IsAlive(P.target) and now >= (P.resendAt or 0) then", "    if not P.ambushSent then")
    end
    return source
end

local NAVS = { "apcamr4_camerapod", "apcamr5_camerapod", "apcamr6_camerapod", "apcamr7_camerapod",
    "apcamr8_camerapod", "apcamr9_camerapod", "cam1" }

local function newSim()
    local sim = PilotSim.new{ name = "misns2", script = "Scripts/misns2cr.lua", bzn = "Missions/misns2cr.bzn",
        pattern = "%-%- CR pilot mode >>\n(.-)\n%-%- CR pilot mode <<", exports = "update = PilotAdapter.update",
        transform = strip, scrap = 0, pilots = 0 }
    local M = sim.M
    M.missionstart, M.bdcindone = true, false
    M.t1, M.t2, M.t3 = sim:get("svapc0_apc"), sim:get("svapc1_apc"), sim:get("svapc2_apc")
    -- Escorts in the labels the branch expects (their identity does not matter to the convoy).
    local wing = { "svfigh2_wingman", "svfigh3_wingman", "svtank4_wingman", "svtank5_wingman", "svfigh5_wingman",
        "svfigh6_wingman", "svtank12_wingman" }
    for i, key in ipairs({ "e2a", "lu", "e1b", "e1a", "e3b", "e2b", "e3a" }) do M[key] = wing[i] end
    for i, t in ipairs({ M.t1, M.t2, M.t3 }) do sim:track("t" .. i, t) end
    sim:playerEscort(M.t1, 60) -- the branch only orders the convoy on while the player is within 100 m
    -- The mission builds the 19 mines (team 2) on their BZN paths when the convoy nears nav3 (misns2cr.lua ~1058).
    sim:when(function(s) return s:dist(M.t3, "nav3") < 400 end, function(s)
        for n = 1, 19 do
            local x, z = s:pos("mine" .. n)
            s.mines = s.mines or {}
            s.mines[n] = s:add("proxmine", 2, x, z)
        end
    end)
    return sim, M
end

local function nearAll(sim, M, nav, radius)
    for _, t in ipairs({ M.t1, M.t2, M.t3 }) do
        if sim:dist(t, nav) > radius then return false end
    end
    return true
end
local function anyNear(sim, M, nav, radius)
    for _, t in ipairs({ M.t1, M.t2, M.t3 }) do
        if sim:dist(t, nav) <= radius then return true end
    end
    return false
end

local function scenario(withStalls)
    local sim, M = newSim()
    if withStalls then -- every transport loses its order once on leg 1 and once between nav 3 and nav 4
        for _, t in ipairs({ M.t1, M.t2, M.t3 }) do
            sim:stallOnce(t, function(s, u) return u.x > 1350 and u.x < 1560 end)
            sim:stallOnce(t, function(s, u) return u.x > 2250 and u.x < 2400 end)
        end
    end
    sim:runFor(1) -- the first updates; the player is already beside the convoy
    local started = sim.t
    sim:runUntil(function(s) return anyNear(s, M, NAVS[1], 70) end, 150, "a transport to reach nav 1 (apcamr4)")
    sim:expect(sim.t - started > 5, "nav 1 is ~500 m away, so the convoy had to travel")
    for k = 2, 4 do
        sim:runUntil(function(s) return anyNear(s, M, NAVS[k], 70) end, 150, "a transport to reach nav " .. k)
    end
    -- Minefield nav (apcamr8, 100 m): the convoy halts and does not move on while the mines stand.
    sim:runUntil(function(s) return M.pilot and M.pilot.minefield end, 200, "the convoy to latch the minefield nav")
    sim:runFor(2)
    sim:expect(#M.pilot.mines == 5, "five mines tracked, got " .. #M.pilot.mines)
    local x0 = sim:unit(M.t1).x
    sim:runFor(40)
    sim:expect(sim:unit(M.t1).x == x0 and sim:unit(M.t1).cmd == 0, "convoy halted at the minefield while the mines stand")
    sim:expect(sim:dist(M.t1, NAVS[6]) > 300, "the convoy did not run past the minefield")
    for i, h in ipairs(M.pilot.mines) do -- the player clears them one by one
        sim:unit(h).alive = false
        sim:runFor(2)
        if i < 5 then sim:expect(sim:unit(M.t1).x == x0, "still halted with mines left (" .. (5 - i) .. ")") end
    end
    sim:runUntil(function(s) return anyNear(s, M, NAVS[6], 70) end, 200, "the convoy to reach nav 6 after the mines died")
    -- Final nav: all three arrive at the launch pad beacon.
    sim:runUntil(function(s) return nearAll(s, M, NAVS[7], 15) end, 200, "all three transports at cam1 (the final nav)")
    -- Ambush film ends: all three return to nav 1.
    M.bdcindone = true
    sim:runUntil(function(s) return nearAll(s, M, NAVS[1], 15) end, 400, "all three transports back at nav 1 after the ambush")
    if withStalls then
        local fired, total = sim:stallsFired()
        sim:expect(fired == total and total == 6, "every injected stall fired (" .. fired .. "/" .. total .. ")")
    end
    return sim
end

local sim = scenario(false)
print(string.format("misns2 PilotSim OK (no stalls): convoy done at t=%.0f s, script %s%s", sim.t, sim.scriptPath,
    os.getenv("PILOTSIM_PREFIX") and (" [prefix=" .. os.getenv("PILOTSIM_PREFIX") .. "]") or ""))
sim = scenario(true)
print(string.format("misns2 PilotSim OK (stall injector, 2 waves x 3 units): done at t=%.0f s", sim.t))
