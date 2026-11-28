-- Win-path simulation for misn14cr's N64 Pilot Mode branch. The win (misn14cr.lua ~2013) needs an
-- APC: it must carry the three rescue beacons' survivors (APC within 100 m of each beacon,
-- ~1698/1764/1806), reach the CCA base (within 200 m, ~1983) and come back within 300 m of the
-- recycler. The player only flies; the AI duties are: the recycler deploys on a base geyser, two
-- scavengers earn scrap, the factory is built, drives to a second geyser and deploys, two turrets
-- reach their spots, the factory builds the APC, and the APC follows the player through all legs.
-- Mission flags the real script sets from the APC's position are hand-set at the positions the
-- script uses (beacon rescue_finish after 25 s, pick_up). Stalls: recycler Goto, factory Goto
-- (sim:stallOnce) and the APC's Follow dropped once mid-route (scenario-local).
-- Run from the repo root:
--   lua5.1 Tools/MissionTests/Test-Misn14PilotSim.lua
-- PILOTSIM_PROBE=1 also runs a zero-pilot start (UNVERIFIED: the script never sets team 1's pilots).
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")
local CMD = PilotSim.AiCommand

local function run(stall, pilots, turretStall)
    local sim = PilotSim.new{ name = "misn14" .. (stall and "+stall" or ""), script = "Scripts/misn14cr.lua",
        bzn = "Missions/misn14cr.bzn",
        pattern = "(local Pilot = {.-)\n%-%- N64 Pilot Mode branch end",
        transform = function(s) return (s:gsub('require%("PlayerPilotMode"%)', "PlayerPilotMode")) end,
        exports = "update = Pilot.Update, add = Pilot.AddObject",
        scrap = 30, pilots = pilots or 10 } -- misn14cr.lua ~1598: SetScrap(1, 30); pilots are never set (UNVERIFIED start)
    local M, env = sim.M, sim.env
    env.NEVER = 99999.0
    env.AddScrap = function(_, n) sim.scrap[1] = math.min(sim.maxScrap, sim.scrap[1] + n) end
    env.AddPilot = function(_, n) sim.pilots[1] = sim.pilots[1] + n end
    M.recy = "avrecy-1_recycler"
    M.rescue1, M.rescue2, M.rescue3 = false, false, false
    M.rescue_finish1, M.rescue_finish2, M.rescue_finish3 = env.NEVER, env.NEVER, env.NEVER
    sim:hook(function(h) return sim.api.add(h) end)
    local rec = M.recy
    sim:track("rec", rec); sim:track("player", sim.player)
    local st = { turrets = {}, tanks = {}, scavs = {} }
    sim.onSpawn = function(h)
        local o = sim:unit(h)
        if o.odf == "avmuf" then st.fac = h; sim:track("factory", h) end
        if o.odf == "avapc" then st.apc = h; M.apc = h; sim:track("apc", h) end
        if o.odf == "avturr" then st.turrets[#st.turrets + 1] = h end
        if o.odf == "avtank" then st.tanks[#st.tanks + 1] = h end
        if o.odf == "avscav" then st.scavs[#st.scavs + 1] = h end
    end
    if stall or turretStall then
        if stall then sim:stallOnce(rec, function(s) return s.t > 1 end) end
        local armed = {}
        sim:each(function(s) -- arm stalls for the factory and the first turret once they exist
            if stall and st.fac and not armed.fac then armed.fac = true; s:stallOnce(st.fac, function() return true end) end
            if turretStall and st.turrets[1] and not armed.tur then armed.tur = true; s:stallOnce(st.turrets[1], function(_, u) return u.tgt ~= nil end) end
        end)
    end
    return sim, M, rec, st
end

local function scenario(stall, pilots, turretStall)
    local sim, M, rec, st = run(stall, pilots, turretStall)
    local env = sim.env
    sim:runUntil(function(s) return s:unit(rec).deployed end, 90, "the recycler to deploy on a base geyser")
    local recT = sim.t
    sim:runUntil(function() return st.fac ~= nil end, 150, "the factory (avmuf) to be built")
    sim:runUntil(function(s) return s:unit(st.fac).deployed end, 250, "the factory to deploy on its geyser")
    local facT = sim.t
    sim:expect(sim:dist(rec, st.fac) > 20, "the factory took a different geyser from the recycler")
    sim:runUntil(function() return #st.turrets >= 2 end, 200, "two turrets to be built")
    sim:runUntil(function(s)
        return s:dist(st.turrets[1], { x = 2489, z = 99475 }) < 15 and s:dist(st.turrets[2], { x = 2686, z = 99509 }) < 15
    end, 150, "the turrets to reach their spots")
    sim:runUntil(function() return st.apc ~= nil end, 200, "the factory to build the APC")
    local apcT = sim.t
    sim:expect(sim.refused == 0, "no build order was refused (refused " .. sim.refused .. ")")

    -- The player flies the rescue leg: beacon 1, 2, 3, the CCA base, then home to the recycler. He waits
    -- when the APC is more than 80 m behind. Rescue flags are set where the script sets them.
    local legs = { { "rescue1", 1958.96, 99175.8 }, { "rescue2", 2597.57, 100244 }, { "rescue3", 3557.57, 99100.4 },
        { "base", 3102.87, 99853.2 }, { "home", nil, nil } }
    local leg, finishAt, legDone, dropped = 1, nil, {}, false
    sim:each(function(s)
        local p, apc = s:unit(s.player), s:unit(st.apc)
        local g = legs[leg]
        if not g then return end
        local gx, gz = g[2], g[3]
        if g[1] == "home" then gx, gz = s:pos(rec) end
        local function dApc() return math.sqrt((apc.x - p.x) ^ 2 + (apc.z - p.z) ^ 2) end
        if dApc() <= 80 then
            local dx, dz = gx - p.x, gz - p.z
            local d = math.sqrt(dx * dx + dz * dz)
            if d > 20 then local k = math.min(p.speed * s.dt, d - 20) / d; p.x, p.z = p.x + dx * k, p.z + dz * k end
        end
        local name = g[1]
        if name:match("^rescue") then
            local n = tonumber(name:sub(-1))
            if not M[name] and s:dist(st.apc, { x = gx, z = gz }) < 100 then
                M[name] = true; M["rescue_finish" .. n] = s.t + 25
                finishAt = s.t + 25
            elseif M[name] and s.t > finishAt and M["rescue_finish" .. n] ~= env.NEVER then
                M["rescue_finish" .. n] = env.NEVER; legDone[name] = s.t; leg = leg + 1
            end
        elseif name == "base" then
            if not M.pick_up and s:dist(st.apc, { x = gx, z = gz }) < 200 then M.pick_up = true; legDone.base = s.t; leg = leg + 1 end
        end
        -- drop the APC's follow order once, mid-route to beacon 2 (the 30 s regroup must bring it back)
        if stall and not dropped and leg == 2 and apc.cmd == CMD.FOLLOW and s:dist(st.apc, { x = 2200, z = 99500 }) < 150 then
            dropped = true; apc.cmd, apc.tgt = CMD.NONE, nil; s:say("STALL injected: apc drops its follow")
        end
    end)
    sim:runUntil(function() return M.rescue1 end, 400, "the APC to reach beacon 1 with the player")
    sim:runUntil(function() return M.rescue2 end, 400, "the APC to reach beacon 2")
    sim:runUntil(function() return M.rescue3 end, 400, "the APC to reach beacon 3")
    sim:runUntil(function() return M.pick_up end, 400, "the APC to reach the CCA base (200 m)")
    sim:runUntil(function(s) return s:dist(rec, st.apc) < 300 end, 400, "the APC within 300 m of the recycler (the win)")
    local winT = sim.t
    if turretStall then local fired = sim:stallsFired(); sim:expect(fired == 1, "the turret stall fired") end
    if stall then
        local fired, total = sim:stallsFired()
        sim:expect(fired == total and total == 2 and dropped, "all injected stalls fired (" .. fired .. "/" .. total .. ", follow dropped=" .. tostring(dropped) .. ")")
    end
    sim:expect(not sim.failed, "the branch did not fail the mission")
    return sim, recT, facT, apcT, winT
end

for _, stall in ipairs({ false, true }) do
    local sim, recT, facT, apcT, winT = scenario(stall)
    print(string.format("misn14 PilotSim OK%s: recycler deployed t=%.0f s, factory deployed t=%.0f s, APC built t=%.0f s, win (APC home) t=%.0f s, script %s",
        stall and " (stall injected: recycler + factory Goto and the APC Follow dropped once)" or "", recT, facT, apcT, winT, sim.scriptPath))
end

-- A turret Goto dropped once is re-sent by PilotBranch.KeepSpots.
scenario(false, nil, true)
print("misn14 PilotSim OK: turret Goto dropped once recovers")
if os.getenv("PILOTSIM_PROBE") then
    local ok, err = pcall(scenario, false, 0)
    print("probe (zero starting pilots, UNVERIFIED start): " .. (ok and "still wins" or ("GAP: " .. tostring(err):match("^[^\n]*"))))
end
