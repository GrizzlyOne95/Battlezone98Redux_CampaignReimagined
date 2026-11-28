-- Win-path simulation for misns8cr's N64 Pilot Mode branch. The win (misns8cr.lua ~2125) is the player killing
-- the enemy recycler; the pilot block supports the player's base. AI duties:
--   1. the recycler (svrecycle) and the factory (svmuf, an savmf hull) each drive to their geyser (eggeizr13 /
--      eggeizr12) and deploy; the opening Goto is sent once (~264) and Branch.Resend repeats it (~269);
--   2. the recycler tops up two scavengers (AddScrap/AddPilot top-up, ~288), then a constructor (8 scrap + the
--      4 scrap reserve, ~292);
--   3. the constructor builds the eight base facilities in C order (hangar, supply, 3 power plants, 3 towers),
--      each needing its cost + 4 scrap, and takes each to its drop point (Dropoff, ~282); a power plant that
--      cannot be afforded blocks the rest, so the scavengers' income must cover the queue;
--   4. the Fury event (M.general_spawn, hand-set) makes the factory build one svsav at last_geyser (~277);
--      without it the factory builds one itself once the base stands (~315).
-- Hand-set / assumed: starting scrap 25 and 10 pilots (SetScrap/SetPilot, ~937-939), both producers start
-- undeployed (the opening orders them), the savmf factory is modelled with the mobile producer speed. The script
-- itself judges the constructor's Dropoff not win-critical (~282), and the sim cannot tell a lost Dropoff from one
-- superseded by the next facility order, so no Dropoff stall run is made (arrivals are printed as information).
-- Run from the repo root:  lua5.1 Tools/MissionTests/Test-Misns8PilotSim.lua
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")
local CMD = PilotSim.AiCommand

local FACILITIES = { { "sbhang", 1964, 100363 }, { "sbsupp", 1897, 100315 }, { "sbspow", 1829, 100314 },
    { "sbtowe", 1836, 100351 }, { "sbspow", 1841, 100215 }, { "sbtowe", 1877, 100180 },
    { "sbspow", 2025, 100356 }, { "sbtowe", 2063, 100349 } }

local function run(opts)
    opts = opts or {}
    local sim = PilotSim.new{ name = "misns8" .. (opts.stall and "+stall" or "") .. (opts.fury and "+fury" or "")
            ,
        script = "Scripts/misns8cr.lua", bzn = "Missions/misns8cr.bzn",
        pattern = "(local PILOT_RESERVE =.-)\n%-%- CR pilot mode <<",
        exports = "update = PilotUpdate, add = PilotAddObject", scrap = 25, pilots = 10,
        costs = { savtnk = { scrap = 15, time = 15 } } } -- stock savtnk.odf (not in the repo): scrapCost 15, buildTime 15
    local api, M, env = sim.api, sim.M, sim.env
    env.AddScrap = function(team, n) sim.scrap[team] = math.min(sim.maxScrap, (sim.scrap[team] or 0) + n) end
    env.AddPilot = function(team, n) sim.pilots[team] = (sim.pilots[team] or 0) + n end
    env.BuildObject = function(odf, team, where)
        local x, z = sim:pos(where)
        local h = sim:add(odf, team, x, z)
        sim:say("BuildObject " .. h)
        if sim.addHook then sim.addHook(h) end
        return h
    end
    sim:hook(function(h) return api.add(h) end)
    local rec, fac, player = sim:get("svrecycle"), sim:get("svmuf"), sim.player
    local fu = sim:unit(fac) -- the BZN's savmf hull: give it the mobile producer's model
    fu.odf, fu.speed, fu.craft = "svmuf", 10, true
    M.general_spawn = false
    sim:track("rec", rec); sim:track("fac", fac)
    local function built(odf) local n = 0; for _, b in ipairs(sim.built) do if b.odf == odf then n = n + 1 end end; return n end

    if opts.stall then sim:stallOnce(rec, function() return true end); sim:stallOnce(fac, function() return true end) end
    -- The constructor's arrivals at the eight drop points, (informational).
    local arrived = {}
    sim:each(function(s)
        for _, h in ipairs(s.order) do
            local u = s.objs[h]
            if u.alive and u.odf == "svcnst" then
                for i, f in ipairs(FACILITIES) do
                    if not arrived[i] and s:dist(h, { x = f[2], z = f[3] }) < 12 then arrived[i] = s.t end
                end
            end
        end
    end)
    if opts.fury then sim:when(function(s) return s.t >= 40 end, function() M.general_spawn = true end) end

    sim:runUntil(function(s) return s:unit(rec).deployed and s:unit(fac).deployed end, 60, "the recycler and factory to deploy on their geysers")
    sim:expect(sim:dist(rec, "eggeizr13_geyser") < 15 and sim:dist(fac, "eggeizr12_geyser") < 15, "producers stand on their geysers")
    if opts.stall then sim:expect(sim:stallsFired() == 2, "both opening Gotos were dropped once and re-sent") end
    local deployed = sim.t
    sim:runUntil(function() return built("svscav") == 2 and built("svcnst") == 1 end, 100, "two scavengers and the constructor")
    local P = M.pilot
    -- The whole base: eight facilities, then the factory's savtnk (or the Fury svsav).
    sim:runUntil(function()
        for _, k in ipairs({ "hangar", "supp", "pow1", "pow2", "pow3", "tow1", "tow2", "tow3" }) do
            if not (P[k] and sim:unit(P[k]).alive) then return false end
        end
        return true
    end, 1500, "the constructor to build all eight base facilities")
    local baseAt = sim.t
    sim:expect(sim.refused == 0, "no build refused for lack of scrap (" .. sim.refused .. ")")
    sim:runUntil(function() return P.sav and sim:unit(P.sav).alive end, 200, "the svsav to exist")
    if opts.fury then
        sim:expect(built("svsav") == 0, "the Fury svsav (BuildObject at last_geyser) stood in; the factory built none")
        sim:expect(built("savtnk") == 0, "the factory built no savtnk either")
        sim:expect(sim:dist(P.sav, "last_geyser") < 5, "the Fury svsav stands at last_geyser")
    else
        sim:expect(built("savtnk") == 1 and built("svsav") == 0, "the factory (a savmf) built the savtnk, not an svsav")
    end
    sim:runFor(60)
    sim:expect(built("svsav") + built("savtnk") <= 1 and built("svcnst") == 1 and built("svscav") == 2, "no extra svsav, constructor or scavengers")
    local missed = {}
    for i = 1, #FACILITIES do if not arrived[i] then missed[#missed + 1] = FACILITIES[i][1] .. "#" .. i end end
    -- The Dropoff to a facility's spot is superseded when the next facility is ordered as soon as the building
    -- (default 5 s build in the sim, no buildTime in the ODFs) completes; whether the real build outlasts the
    -- drive is UNVERIFIED, and the script judges the Dropoff not win-critical, so this is reported, not asserted.
    sim.missedDrops = missed
    sim:expect(arrived[#FACILITIES], "the constructor reached the last drop point")
    sim:expect(not sim.failed, "the branch did not fail the mission")
    return sim, deployed, baseAt
end

local sim, d, b = run()
print(string.format("misns8 PilotSim OK: producers deployed t=%.0f s, base of 8 facilities done t=%.0f s, factory savtnk t<=%.0f s, scrap earned %.0f, script %s",
    d, b, sim.t, sim.income, sim.scriptPath))
print("  (informational) drop points not reached before the next order: " .. (#sim.missedDrops == 0 and "none" or table.concat(sim.missedDrops, ",")))
sim = run({ stall = true, fury = true })
print(string.format("misns8 PilotSim OK (opening Gotos dropped once, Resend recovers; Fury svsav): done t=%.0f s", sim.t))

