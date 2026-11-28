-- Win-path simulation for misns5cr's N64 Pilot Mode branch. The win (misns5cr.lua ~582) is the player killing
-- the final-phase target; the loss is the recycler dying (~587) or, in Pilot Mode, the constructor dying (~141).
-- AI duties (the player cannot do these while flying):
--   1. recycler and factory deploy on their geysers: the mission sends each one Goto once when the intro ends
--      (~450); Branch.Resend sends it again if the order is lost (~135);
--   2. the recycler tops up the two scavengers (with AddScrap/AddPilot, ~174) and so the scrap income exists;
--   3. the recycler builds an sspammo ammo pod at the player when ammo < 75% (BuildAt, ~182);
--   4. the factory replaces the two start tanks (~186) and, from the last phase (M.last_phase), fills tank
--      slots 3 and 4 (~188), each needing 8 scrap and a pilot;
--   5. the recycler builds the constructor (~190), which rebuilds a destroyed tower (Build + Dropoff, ~155).
-- Hand-set / assumed: recycler and factory start undeployed (the mission Gotos them, ~450), starting scrap 10
-- (~414; the BZN's own scrap is UNVERIFIED), 10 pilots (UNVERIFIED), the BZN scavengers are scavenging.
-- The tower rebuild is judged not win-critical by the script itself (~151); its Dropoff stall is a probe.
-- Run from the repo root:  lua5.1 Tools/MissionTests/Test-Misns5PilotSim.lua
--   PILOTSIM_PROBE=1 also runs the known-gap probe (a dropped constructor Dropoff is never re-sent).
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")
local CMD = PilotSim.AiCommand

local function run(opts)
    opts = opts or {}
    local sim = PilotSim.new{ name = "misns5" .. (opts.stall and "+stall" or "") .. (opts.dropDropoff and "+dropDropoff" or ""),
        script = "Scripts/misns5cr.lua", bzn = "Missions/misns5cr.bzn",
        pattern = "(local Pilot = { module = \"CRPilotBranch\" }.-)\n%-%- CR pilot mode <<",
        exports = "pilot = Pilot", scrap = 10, pilots = 10 }
    local Pilot, M, env = sim.api.pilot, sim.M, sim.env
    sim.update = function() Pilot.Update() end
    env.AddScrap = function(team, n) sim.scrap[team] = math.min(sim.maxScrap, (sim.scrap[team] or 0) + n) end
    env.AddPilot = function(team, n) sim.pilots[team] = (sim.pilots[team] or 0) + n end
    sim:hook(function(h) return Pilot.AddObject(h) end)
    local rec, muf, player = sim:get("svrecy0_recycler"), sim:get("svmuf0_factory"), sim.player
    local g1, g2 = sim:get("eggeizr11_geyser"), sim:get("eggeizr12_geyser")
    for _, k in ipairs({ "svscav1_scavenger", "svscav2_scavenger" }) do sim:unit(k).cmd = CMD.SCAVENGE end
    M.start_done, M.camera1, M.recy, M.muf, M.last_phase = true, true, rec, muf, false
    sim:track("rec", rec); sim:track("muf", muf); sim:track("player", player)
    local function built(odf) local n = 0; for _, b in ipairs(sim.built) do if b.odf == odf then n = n + 1 end end; return n end

    if opts.stall then -- the mission's one Goto for each producer is dropped
        sim:stallOnce(rec, function() return true end)
        sim:stallOnce(muf, function() return true end)
    end
    if opts.dropDropoff then -- the constructor loses its Dropoff once
        local done
        sim:each(function(s)
            for _, h in ipairs(s.order) do
                local u = s.objs[h]
                if not done and u.alive and u.odf == "svcnst" and u.cmd == CMD.DROPOFF then
                    u.cmd, u.tgt = CMD.NONE, nil; done = true; s:say("constructor Dropoff dropped")
                end
            end
        end)
    end

    sim:runFor(20) -- the intro camera
    M.camera1, M.geyser1, M.geyser2 = false, g1, g2 -- as the mission sets them (~447)
    env.Goto(rec, g1); env.Goto(muf, g2) -- misns5cr.lua ~450
    sim:runUntil(function(s) return s:unit(rec).deployed and s:unit(muf).deployed end, 60, "the recycler and factory to deploy on their geysers")
    sim:expect(sim:dist(rec, g1) < 15 and sim:dist(muf, g2) < 15, "producers stand on their geysers")
    if opts.stall then sim:expect(sim:stallsFired() == 2, "both Gotos were dropped once") end
    sim:runFor(2)
    local P = M.pilot
    sim:expect(P and P.started, "the branch started after the intro")

    -- Duty 2: a lost scavenger is replaced.
    sim:unit(P.scav[1]).alive = false
    sim:runUntil(function() return built("svscav") == 1 end, 60, "the recycler to replace the lost scavenger")
    -- Duty 3: ammo pod at the player.
    sim:unit(player).ammo = 0.5
    sim:runUntil(function() return built("sspammo") == 1 end, 60, "the recycler to build an ammo pod")
    sim:expect(sim:dist(sim.built[#sim.built].h, player) < 5, "the pod was placed at the player")
    -- Duty 4: both start tanks lost -> the factory rebuilds them.
    sim:unit(P.tank[1]).alive, sim:unit(P.tank[2]).alive = false, false
    sim:runUntil(function() return built("svtank") == 2 end, 400, "the factory to replace both start tanks")
    -- Duty 5: the constructor, then a lost tower is rebuilt.
    sim:runUntil(function() return built("svcnst") == 1 end, 200, "the recycler to build the constructor")
    sim:expect(sim:unit(P.cnst).alive, "the constructor lives")
    local towerPos = { sim:pos(P.base[4]) }
    sim:unit(P.base[4]).alive = false
    sim:runUntil(function() return built("sbtowe") == 1 end, 100, "the constructor to build a replacement tower")
    sim:runUntil(function(s) return s:unit(P.cnst).cmd == CMD.NONE and s:dist(P.cnst, { x = towerPos[1], z = towerPos[2] }) < 15 end,
        100, "the constructor to drop the tower off at its old position")
    -- Last phase: tank slots 3 and 4.
    M.last_phase = true
    sim:runUntil(function() return built("svtank") == 4 end, 400, "the factory to fill tank slots 3 and 4")
    sim:runFor(60)
    sim:expect(built("svtank") == 4 and built("svcnst") == 1, "no extra tanks or constructors")
    sim:expect(not sim.failed, "the branch did not fail the mission")
    return sim
end

local sim = run()
print(string.format("misns5 PilotSim OK: producers deployed, scav/ammo/tanks/constructor/tower rebuild and last-phase tanks done t=%.0f s, scrap earned %.0f, script %s",
    sim.t, sim.income, sim.scriptPath))
sim = run({ stall = true })
print(string.format("misns5 PilotSim OK (both producer Gotos dropped once, Resend recovers): done t=%.0f s", sim.t))

if os.getenv("PILOTSIM_PROBE") then
    local ok, err = pcall(run, { dropDropoff = true })
    print("probe (constructor Dropoff dropped once, misns5cr.lua ~151): " ..
        (ok and "recovers" or ("GAP: " .. tostring(err):match("^[^\n]*"))))
end
