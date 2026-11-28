-- Win-path simulation for misns7cr's N64 Pilot Mode branch. The win (misns7cr.lua ~1757) is the player killing
-- the enemy recycler; the Pilot-only loss is an engineer dying (pilot block ~324), and the APC dying before
-- the recycler is restored fails (~1768). AI duties the pilot cannot do alone:
--   1. the APC (svapc) follows the player to the jail, then, once the jail is down (M.jail_unit_spawn), drives
--      to each engineer in turn (Goto one engineer, then the next when it is safe, ~305-322) and goes back to
--      following the player once all are aboard (~332);
--   2. the restored recycler and factory follow the player and, once the supply cache stands
--      (M.supplies_spawned, ~357), each drives to its geyser by the hangar (eggeizr13 / con_geyser) and
--      deploys, with Branch.Resend as the retry (~364); a missing geyser is skipped, not an error (~360);
--   3. the deployed factory builds two tanks and the recycler two fighters (scrap >= 8 / 6 and a pilot, ~379).
-- Hand-set (the real game sets them from the player's actions, at the spots the script uses): jail_unit_spawn
-- when the player is within 150 m of the jail, the engineers' boarding (APC within 20 m, safe after 0.2 s, ~1078),
-- first_message_done, the restorations (camera_off_recycle / camera_off_muf, built at the neutral objects'
-- positions, +20 scrap each, ~1281/~1380), supplies_spawned when the player reaches the hangar. Assumed:
-- 8 pilots (SetPilot, ~809; each rescued engineer adds one), starting scrap 0 (UNVERIFIED), engineers
-- stand still (conservative: in the game they are also ordered GetIn(apc), ~921, which the sim does not model).
-- Run from the repo root:  lua5.1 Tools/MissionTests/Test-Misns7PilotSim.lua
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")
local CMD = PilotSim.AiCommand

local function run(opts)
    opts = opts or {}
    local sim = PilotSim.new{ name = "misns7" .. (opts.stall and "+stall" or "") .. (opts.dropApc and "+dropApcGoto" or "")
            .. (opts.noGeyser and "+noMufGeyser" or ""),
        script = "Scripts/misns7cr.lua", bzn = "Missions/misns7cr.bzn",
        pattern = "(%-%- CR pilot mode >>\n.-\n%-%- CR pilot mode <<)",
        exports = "pilot = Pilot, adapter = PilotAdapter", scrap = 0, pilots = 8 }
    local Pilot, M, env = sim.api.pilot, sim.M, sim.env
    Pilot.B = env.PilotBranch
    sim.update = function() sim.api.adapter.update() end
    env.AddScrap = function(team, n) sim.scrap[team] = math.min(sim.maxScrap, (sim.scrap[team] or 0) + n) end
    env.AddPilot = function(team, n) sim.pilots[team] = (sim.pilots[team] or 0) + n end
    sim:hook(function(h) return sim.api.adapter.addObject(h) end)
    local apc, player = sim:get("svapc"), sim.player
    sim:unit(player).speed = 12
    M.start_done = true
    M.apc, M.svrecycle, M.svmuf, M.supply = apc, sim:get("svrecycle"), sim:get("svmuf"), sim:get("supply")
    local recGeyser, mufGeyser = "eggeizr13_geyser", "con_geyser"
    sim:track("apc", apc); sim:track("player", player)
    local function built(odf) local n = 0; for _, b in ipairs(sim.built) do if b.odf == odf then n = n + 1 end end; return n end
    local function fly(x, z)
        sim.dest = { x = x, z = z }
    end
    sim:each(function(s)
        if not s.dest then return end
        local p = s:unit(player)
        local dx, dz = s.dest.x - p.x, s.dest.z - p.z
        local d = math.sqrt(dx * dx + dz * dz)
        if d > 3 then local k = math.min(p.speed * s.dt, d) / d; p.x, p.z = p.x + dx * k, p.z + dz * k end
    end)

    -- The mission's engineer boarding (~1078): the APC within 20 m, safe 0.2 s later (the engineer is removed).
    local cons, pickAt = {}, {}
    sim:each(function(s)
        for i, c in ipairs(cons) do
            local u = s:unit(c)
            if u.alive and not pickAt[i] and s:dist(c, apc) < 20 then pickAt[i] = s.t + 0.2; M["con" .. i .. "_in_apc"] = true end
            if pickAt[i] and s.t >= pickAt[i] and not M["con" .. i .. "_safe"] then
                u.alive = false; M["con" .. i .. "_safe"] = true; env.AddPilot(1, 1)
                if M.con1_safe and M.con2_safe and M.con3_safe then M.first_message_done = true end
            end
        end
    end)

    if opts.stall then -- every producer Goto the pilot sends is dropped once (Resend must repeat it)
        local added = {}
        sim:each(function(s)
            for _, k in ipairs({ "rec", "muf" }) do
                local h = M[k]
                if h and not added[h] and s.objs[h] and s.objs[h].team == 1 then added[h] = true; s:stallOnce(h, function(_, u) return u.tgt == (k == "rec" and recGeyser or mufGeyser) end) end
            end
        end)
    end
    if opts.dropApc then sim:stallOnce(apc, function() return true end) end -- the APC's first engineer Goto is dropped

    -- Phase 1: the jail.
    sim:runFor(2)
    fly(sim:pos("jail"))
    sim:runUntil(function(s) return s:dist(player, "jail") < 150 end, 200, "the player to reach the jail")
    local jailX, jailZ = sim:pos("jail")
    for i = 1, 3 do cons[i] = sim:add("sssold", 1, sim:pos("con" .. i .. "_spot")) end
    M.con1, M.con2, M.con3 = cons[1], cons[2], cons[3]
    M.jail_unit_spawn = true
    sim:runUntil(function() return M.first_message_done end, 150, "the APC to pick up all three engineers")
    local rescued = sim.t
    sim:runFor(3)
    sim:expect(sim:unit(apc).cmd == CMD.FOLLOW, "the APC follows the player again once the engineers are aboard")
    -- Phase 2: the recycler is restored beside the jail.
    local rx, rz = sim:pos(M.svrecycle)
    fly(rx, rz)
    sim:runUntil(function(s) return s:dist(player, M.svrecycle) < 50 and s:dist(apc, M.svrecycle) < 40 end, 100, "the player and APC at the neutral recycler")
    sim:unit(M.svrecycle).alive = false
    M.svrecycle = sim:add("svrecy", 1, rx, rz)
    M.camera_off_recycle = true
    env.AddScrap(1, 20)
    sim:runFor(5)
    sim:expect(sim:unit(M.svrecycle).cmd == CMD.FOLLOW, "the restored recycler follows the player")
    -- Phase 3: the factory is restored.
    local mx, mz = sim:pos(M.svmuf)
    fly(mx, mz)
    sim:runUntil(function(s) return s:dist(player, M.svmuf) < 50 and s:dist(apc, M.svmuf) < 40 end, 300, "the player and APC at the neutral factory")
    sim:unit(M.svmuf).alive = false
    M.svmuf = sim:add("svmuf", 1, mx, mz)
    M.camera_off_muf = true
    env.AddScrap(1, 20)
    M.rec, M.muf = M.svrecycle, M.svmuf
    sim:track("rec", M.rec); sim:track("muf", M.muf)
    sim:runFor(5)
    sim:expect(sim:unit(M.svmuf).cmd == CMD.FOLLOW, "the restored factory follows the player")
    -- Phase 4: the player reaches the supply cache; the producers go to their geysers and deploy.
    fly(sim:pos(M.supply))
    sim:runUntil(function(s) return s:dist(player, M.supply) < 100 end, 200, "the player to reach the supply cache")
    if opts.noGeyser then sim:unit(mufGeyser).alive = false end
    M.supplies_spawned = true
    sim:runUntil(function(s) return s:unit(M.rec).deployed end, 400, "the recycler to deploy on its geyser")
    sim:expect(sim:dist(M.rec, recGeyser) < 15, "the recycler stands on eggeizr13")
    if opts.noGeyser then
        sim:runFor(60)
        sim:expect(not sim:unit(M.muf).deployed and built("svtank") == 0, "no factory geyser: the factory is left alone, no error")
        -- Note: the queue is one if/elseif (~380), so an up-but-undeployed factory also holds back the recycler's fighters.
        sim:expect(built("svfigh") == 0, "informational: the undeployed factory blocks the fighter queue (~380 if/elseif)")
        return sim, rescued
    end
    sim:runUntil(function(s) return s:unit(M.muf).deployed end, 400, "the factory to deploy on con_geyser")
    sim:expect(sim:dist(M.muf, mufGeyser) < 15, "the factory stands on con_geyser")
    if opts.stall then sim:expect(sim:stallsFired() == 2, "both producer Gotos were dropped once and re-sent (" .. sim:stallsFired() .. ")") end
    sim:runUntil(function() return built("svtank") == 2 and built("svfigh") == 2 end, 300, "two tanks and two fighters")
    sim:runFor(60)
    sim:expect(built("svtank") == 2 and built("svfigh") == 2, "exactly two tanks and two fighters")
    sim:expect(sim.refused == 0, "no build refused (" .. sim.refused .. ")")
    sim:expect(not sim.failed, "the branch did not fail the mission")
    return sim, rescued
end

local sim, rescued = run()
print(string.format("misns7 PilotSim OK: engineers rescued t=%.0f s, producers deployed and queue built t=%.0f s, script %s", rescued, sim.t, sim.scriptPath))
sim = run({ stall = true })
print(string.format("misns7 PilotSim OK (producer Gotos dropped once, Resend recovers): done t=%.0f s", sim.t))
sim = run({ noGeyser = true })
print(string.format("misns7 PilotSim OK (factory geyser missing: skipped without error, recycler deploys; the blocked fighter queue is noted in the test): t=%.0f s", sim.t))

-- The APC's engineer Goto dropped once is re-sent by PilotBranch.Keep.
sim = run({ dropApc = true })
print(string.format("misns7 PilotSim OK (APC's engineer Goto dropped once, Keep recovers): done t=%.0f s", sim.t))
