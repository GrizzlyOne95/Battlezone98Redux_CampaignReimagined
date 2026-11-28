-- Win-path simulation for misns1cr's N64 Pilot Mode branch. The win (misns1cr.lua ~1280) is the player
-- destroying the factory, silo and Colorado; a lost Soviet recycler or a lost howitzer fails (~1344, 269).
-- AI duties the pilot cannot do alone (all checked here):
--   1. the Soviet recycler builds two scavengers (topping scrap/pilots up with AddScrap/AddPilot, ~314),
--   2. replaces a lost fighter (needs scrap >= 6 and a pilot, ~326) and builds one repair and one ammo
--      pod when the player is hurt (WatchSupply/BuildSupply, ~262/~320),
--   3. the walker (walker1) drives to the cut-off nav when Colorado reaches it (~340),
--   4. once Colorado is dead a howitzer (svartl) is built, driven to the tower approach (Goto, ~282),
--      deploys, and attacks tower 1 then tower 2 (~287); it must survive (its loss fails).
-- Hand-set / assumed: M.* flags the real opening sets; the howitzer deploys by itself on arrival (engine
-- artillery AI, as the N64 branch relies on; UNVERIFIED), a deployed howitzer kills its Attack target after
-- 15 s when within 600 m (shell range UNVERIFIED); Colorado is teleported to the walker nav and then killed.
-- Run from the repo root:  lua5.1 Tools/MissionTests/Test-Misns1PilotSim.lua
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")
local CMD = PilotSim.AiCommand

local function run(opts)
    opts = opts or {}
    local sim = PilotSim.new{ name = "misns1" .. (opts.dropHow and "+dropHowitzerGoto" or "") .. (opts.dropWalker and "+dropWalkerGoto" or ""),
        script = "Scripts/misns1cr.lua", bzn = "Missions/misns1cr.bzn",
        pattern = "(%-%- CR pilot mode >>\n.-\n%-%- CR pilot mode <<)",
        exports = "pilot = Pilot", scrap = 20, pilots = 10 } -- SetScrap(1, 20) at start (~790)
    local Pilot = sim.api.pilot
    Pilot.Branch = sim.env.PilotBranch
    sim.update = function() Pilot.Update() end
    local M, env = sim.M, sim.env
    -- The engine natives the block needs beyond the harness.
    env.BuildObject = function(odf, team, where)
        local x, z
        if type(where) == "table" then x, z = where.x, where.z else x, z = sim:pos(where) end
        local h = sim:add(odf, team, x, z)
        sim:say("BuildObject " .. h)
        return h
    end
    env.AddScrap = function(team, n) sim.scrap[team] = math.min(sim.maxScrap, (sim.scrap[team] or 0) + n) end
    env.AddPilot = function(team, n) sim.pilots[team] = (sim.pilots[team] or 0) + n end
    sim:hook(function(h) return Pilot.AddObject(h) end)

    local svrec, col = sim:get("svrecy2_recycler"), sim:get("avrecy1_recycler")
    local player = sim.player
    sim:unit(svrec).deployed = true -- the player's base recycler stands deployed at the start
    M.svrec, M.colorado = svrec, col
    M.missionstart, M.pickpath, M.startconvoy, M.path, M.retreat = true, true, 1000, 0, false
    M.walker1 = sim:add("svwalk", 1, sim:pos("spawnwalker1"))
    M.walkcam1 = sim:add("spcamr", 1, sim:pos("walkcam1"))
    M.hidcam1 = sim:add("spcamr", 1, sim:pos("hidcamupper"))
    M.hidcam2 = sim:add("spcamr", 1, sim:pos("hidcammiddle"))
    M.hidcam3 = sim:add("spcamr", 1, sim:pos("hidcamlower"))
    local t1, t2 = sim:get("abtowe0_turret"), sim:get("abtowe3_turret")
    sim:track("svrec", svrec); sim:track("col", col); sim:track("walker", M.walker1)
    sim:track("t1", t1); sim:track("t2", t2); sim:track("player", player)

    -- Scenario model: deployed-on-arrival howitzer, and its shells kill the attacked tower.
    local how, hit = nil, {}
    sim:each(function(s)
        for _, h in ipairs(s.order) do
            local u = s.objs[h]
            if u.alive and u.odf == "svartl" then
                if not how then
                    how = h
                    if opts.dropHow then s:stallOnce(h, function() return true end) end -- its Goto is dropped once
                end
                if u.cmd == CMD.NONE and not u.deployed and s:dist(h, { x = 3815, z = 100219 }) < 20 then
                    u.deployed = true; s:say("howitzer deployed")
                end
                if u.cmd == CMD.ATTACK and u.deployed then
                    local tgt = s.objs[u.tgt]
                    if tgt and tgt.alive then
                        hit[u.tgt] = hit[u.tgt] or s.t
                        if s.t - hit[u.tgt] >= 15 and s:dist(h, u.tgt) <= 600 then tgt.alive = false; s:say("tower down " .. u.tgt) end
                    end
                end
            end
        end
    end)
    if opts.dropWalker then sim:stallOnce(M.walker1, function() return true end) end -- its Goto is dropped once

    local function built(odf) local n = 0; for _, b in ipairs(sim.built) do if b.odf == odf then n = n + 1 end end; return n end
    local function count(odf) local n = 0; for _, h in ipairs(sim.order) do local u = sim.objs[h]; if u.alive and u.odf == odf and u.team == 1 then n = n + 1 end end; return n end
    local times = {}
    -- The opening (~822) builds two tanks and a fighter on the player's team; the engine passes them to AddObject.
    for _, spec in ipairs({ { "svtank", "tank1" }, { "svtank", "tank2" }, { "svfigh", "figh1" } }) do
        local x, z = sim:pos(spec[2])
        Pilot.AddObject(sim:add(spec[1], 1, x, z))
    end
    sim:runFor(1)
    local P = M.pilot
    sim:expect(P and P.started, "the branch started")
    sim:expect(count("svfigh") == 6, "six fighters stand at the start (" .. count("svfigh") .. ")")

    -- Duty 1: two scavengers from the recycler.
    sim:runUntil(function() return P.scav1 and P.scav2 and sim:unit(P.scav2).alive end, 60, "the recycler to build two scavengers")
    sim:expect(built("svscav") == 2, "exactly two scavengers built")
    times.scavs = sim.t
    -- Duty 2a: a lost fighter is replaced.
    sim:unit(P.f1).alive = false
    sim:runUntil(function() return built("svfigh") == 1 end, 150, "the recycler to replace the lost fighter")
    sim:expect(count("svfigh") == 6, "six fighters again")
    times.fighter = sim.t
    -- Duty 2b: repair and ammo pods when the player is hurt, one each.
    local pl = sim:unit(player)
    pl.health, pl.ammo = 0.5, 0.5
    sim:runUntil(function() return built("ssprepa") == 1 and built("sspammo") == 1 end, 100, "the recycler to build a repair and an ammo pod")
    sim:runFor(120)
    sim:expect(built("ssprepa") == 1 and built("sspammo") == 1, "no second pod while the first ones stand")
    times.pods = sim.t
    -- Duty 3: Colorado reaches the walker's nav (the player's chase); the walker joins it.
    local wx, wz = sim:pos(M.walkcam1)
    sim:unit(col).x, sim:unit(col).z = wx, wz
    sim:runUntil(function() return sim:unit(M.walker1).cmd == CMD.NONE and sim:dist(M.walker1, M.walkcam1) < 15 end, 120, "the walker to reach the cut-off nav")
    sim:expect(sim.marked[M.hidcam1], "the route's exit nav is marked")
    times.walker = sim.t
    -- Duty 4: Colorado dies -> the howitzer shells both towers.
    sim:unit(col).alive = false
    sim:runUntil(function() return how ~= nil end, 10, "the howitzer to be built")
    sim:expect(sim.marked[how], "the howitzer is marked")
    sim:runUntil(function() return sim:unit(how).deployed end, 150, "the howitzer to reach its firing spot and deploy")
    sim:expect(sim:unit(t1).alive, "tower 1 still stands when the howitzer arrives")
    sim:runUntil(function() return not sim:unit(t1).alive and not sim:unit(t2).alive end, 200, "the howitzer to destroy both towers")
    sim:runFor(5)
    sim:expect(P.howDone, "the branch finished the howitzer job")
    sim:expect(not sim.failed, "the branch did not fail the mission")
    times.towers = sim.t
    return sim, times
end

local sim, t = run()
print(string.format("misns1 PilotSim OK: scavengers t=%.0f s, fighter replaced t=%.0f s, pods t=%.0f s, walker at nav t=%.0f s, towers down t=%.0f s, script %s",
    t.scavs, t.fighter, t.pods, t.walker, t.towers, sim.scriptPath))
-- Both orders dropped once are re-sent (the howitzer Goto by PilotBranch.KeepSpots, the walker Goto by KeepGoto).
for _, v in ipairs({ { "howitzer Goto dropped once", { dropHow = true } },
                     { "walker Goto dropped once", { dropWalker = true } } }) do
    run(v[2])
    print("misns1 PilotSim OK: " .. v[1] .. " and still wins")
end
