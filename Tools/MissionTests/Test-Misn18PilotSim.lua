-- Win-path simulation for misn18cr's N64 Pilot Mode branch. The win (misn18cr.lua ~742, ~903: the four
-- thrusters destroyed, then the player within 200 m of the recycler when the 180 s cockpit timer runs
-- out) is the player's, but the thrusters sit behind Fury defences and the branch's fighters are the
-- help. The AI duties:
--   * the four free avturr are placed at their spots at the start (C 311-322),
--   * the recycler builds one scavenger and then fighters up to the eight slots, all affordable,
--   * the fighters follow the player until he is within 150 m of the transport, then (10 s block) go
--     for the first standing thruster, thruster after thruster, until none stand,
--   * the tanks follow the player.
-- The pilot block gives no move order the sim can stall, so the stall run drops one fighter's Attack
-- once (scenario-local); the 10 s fighter block must re-send it.
-- Model limits: a thruster dies when a fighter ordered to attack it has been within 70 m for 5 s (the player's own fire
-- is not modelled), the thrusters shoot back at nobody, and the recycler already stands deployed on
-- its geyser (3 m away in the BZN; the unit test assumes the same, UNVERIFIED for the BZN's saved state).
-- Scenario assumptions, UNVERIFIED against the engine: start scrap 80 (SetScrap, ~492); start pilots 10.
-- Run from the repo root:
--   lua5.1 Tools/MissionTests/Test-Misn18PilotSim.lua
-- PILOTSIM_PROBE=1 also runs a zero-pilot start (informational, never fatal).
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")
local CMD = PilotSim.AiCommand

local PRELUDE = "local function Distance(a, b) if not IsValid(a) or not IsValid(b) then return math.huge end return GetDistance(a, b) end\n"

local function scenario(stall, pilots)
    local sim = PilotSim.new{ name = "misn18" .. (stall and "+stall" or ""), script = "Scripts/misn18cr.lua",
        bzn = "Missions/misn18cr.bzn",
        pattern = "(local function Distance%(a, b%) if not IsValid.-)\n%-%- CR pilot mode <<",
        transform = function(s) return (s:gsub("local PILOT_TURRET_SPOTS", function() return PRELUDE .. "local PILOT_TURRET_SPOTS" end, 1)) end,
        exports = "update = PilotUpdate, add = PilotAddObject",
        scrap = 80, pilots = pilots or 10 }
    local M, env = sim.M, sim.env
    env.AddScrap = function(_, n) sim.scrap[1] = math.min(sim.maxScrap, sim.scrap[1] + n) end
    env.AddPilot = function(_, n) sim.pilots[1] = sim.pilots[1] + n end
    local turrets = {}
    env.BuildObject = function(odf, team, where)
        local h = sim:add(odf, team, where.x, where.z)
        if odf == "avturr" then turrets[#turrets + 1] = h end
        sim.api.add(h) -- the engine calls AddObject for every new object
        return h
    end
    M.missionstart = true
    M.avrec = "avrecy2_recycler"
    sim:unit(M.avrec).deployed = true
    M.thrusterone, M.thrustertwo = "hbtrn20049_i76building", "hbtrn20050_i76building"
    M.thrusterthree, M.thrusterfour = "hbtrn20051_i76building", "hbtrn20052_i76building"
    M.transport = "hbtran0038_i76building"
    local thr = { M.thrusterone, M.thrustertwo, M.thrusterthree, M.thrusterfour }
    sim:hook(function(h) return sim.api.add(h) end)
    sim:track("rec", M.avrec); sim:track("player", sim.player); sim:track("tank0", "avtank0_wingman")
    local st = { figh = {}, scavs = {} }
    sim.onSpawn = function(h)
        local o = sim:unit(h)
        if o.odf == "avfigh" then st.figh[#st.figh + 1] = h end
        if o.odf == "avscav" then st.scavs[#st.scavs + 1] = h end
    end

    -- The player flies to the transport, waits for the thrusters to fall, then flies home to the recycler.
    local homeBound = false
    sim:each(function(s)
        local p = s:unit(s.player)
        local gx, gz = s:pos(homeBound and M.avrec or M.transport)
        local dx, dz = gx - p.x, gz - p.z
        local d = math.sqrt(dx * dx + dz * dz)
        local hold = homeBound and 20 or 100 -- parks 100 m from the transport: inside the 150 m near radius
        if d > hold then local k = math.min(p.speed * s.dt, d - hold) / d; p.x, p.z = p.x + dx * k, p.z + dz * k end
    end)
    -- Thruster deaths and the one dropped fighter order.
    local near, dropped, killedAt, order = {}, false, {}, {}
    sim:each(function(s)
        for i, t in ipairs(thr) do
            if sim:unit(t).alive then
                local close = false
                for _, f in ipairs(st.figh) do if sim:unit(f).alive and sim:unit(f).tgt == t and sim:dist(f, t) < 70 then close = true end end
                if close then
                    near[i] = near[i] or s.t
                    if s.t - near[i] >= 5 then sim:unit(t).alive = false; killedAt[i] = s.t; order[#order + 1] = i; sim:say("thruster " .. i .. " destroyed") end
                else near[i] = nil end
            end
        end
        if stall and not dropped and st.figh[1] and sim:unit(st.figh[1]).cmd == CMD.ATTACK then
            dropped = true; local f = sim:unit(st.figh[1]); f.cmd, f.tgt = CMD.NONE, nil; s:say("STALL injected: fighter 1 drops its attack")
        end
    end)

    sim:runUntil(function() return #turrets == 4 end, 5, "the four free turrets to be placed")
    local spots = { { 1824, 98036 }, { 1916, 98010 }, { 1931, 98060 }, { 2019, 98044 } }
    for i, sp in ipairs(spots) do sim:expect(sim:dist(turrets[i], { x = sp[1], z = sp[2] }) < 1, "turret " .. i .. " is at its spot") end
    sim:runUntil(function() return #st.scavs >= 1 end, 30, "the recycler to build the scavenger")
    sim:runUntil(function() return #st.figh >= 8 end, 300, "the recycler to build eight fighters")
    sim:expect(sim.refused == 0, "no build order was refused (refused " .. sim.refused .. ")")
    for i, h in ipairs({ "avtank0_wingman", "avtank1_wingman" }) do
        sim:expect(sim:unit(h).cmd == CMD.FOLLOW and sim:unit(h).tgt == sim.player, "tank " .. i .. " follows the player")
    end
    local figT = sim.t
    sim:runUntil(function() return #order == 4 end, 600, "the fighters to bring down all four thrusters")
    sim:expect(table.concat(order, ",") == "1,2,3,4", "the thrusters fell in order, got " .. table.concat(order, ","))
    if stall then sim:expect(dropped, "the fighter attack stall fired") end
    local thrT = sim.t
    homeBound = true
    -- The win: the player within 200 m of the recycler before the 180 s timer ends (and within 400 m at its end).
    local started = sim.t
    sim:runUntil(function(s) return s:dist(s.player, M.avrec) < 200 end, 180, "the player back within 200 m of the recycler")
    sim:expect(sim.t - started < 180, "home inside the cockpit timer")
    sim:expect(not sim.failed, "the branch did not fail the mission")
    return sim, figT, thrT, sim.t
end

for _, stall in ipairs({ false, true }) do
    local sim, figT, thrT, winT = scenario(stall)
    print(string.format("misn18 PilotSim OK%s: 4 turrets placed, 8 fighters t=%.0f s, four thrusters down t=%.0f s, player home t=%.0f s (win), script %s",
        stall and " (stall injected: one fighter Attack dropped once)" or "", figT, thrT, winT, sim.scriptPath))
end

if os.getenv("PILOTSIM_PROBE") then
    local ok, err = pcall(scenario, false, 0)
    print("probe (zero starting pilots, UNVERIFIED start): " .. (ok and "still completes" or ("GAP: " .. tostring(err):match("^[^\n]*"))))
end
