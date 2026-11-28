-- Win-path simulation for misn06cr's N64 Pilot Mode branch: the recycler drives paths 35 and 36,
-- deploys on its geyser, then (player beside it) convoys down path 38 and must end within 100 m
-- of the dust-off beacon, also when it drops its order once on the way. Run from the repo root:
--   lua5.1 Tools/MissionTests/Test-Misn06PilotSim.lua
-- Evidence against the old script: PILOTSIM_SCRIPT=<file from `git show 676199e9^:Scripts/misn06cr.lua`>
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")

-- Mission flags the real script sets from the player's actions are hand-placed at the spots
-- the script itself uses: heph inspected near its last path-35 point, starport inspected at the
-- end of path 36 (misn06cr.lua ~1911, ~2020), launch pad inspected once the recycler deploys.
local function run(extractpoint, stall, probe)
    local sim = PilotSim.new{ name = "misn06/bugout" .. (extractpoint + 1) .. (stall and "+stall" or ""),
        script = "Scripts/misn06cr.lua", bzn = "Missions/misn06cr.bzn",
        pattern = "(local PILOT_ROUTES =.-)\n%-%- CR pilot mode <<",
        exports = "update = PilotUpdate, add = PilotAddObject, init = InitializePilotMode",
        scrap = 5, pilots = 10 } -- misn06cr.lua ~1516: SetScrap(1, 5)
    local M = sim.M
    sim.api.init()
    M.avrec, M.rendezvous = "avrecy-1_recycler", "eggeizr1-1_geyser"
    M.missionstart, M.opencamdone, M.hephikey = true, true, false
    M.starportreconed, M.launchpadreconed = false, false
    local rec = M.avrec
    sim:track("rec", rec); sim:track("player", sim.player)
    sim:hook(function(h) return sim.api.add(h) end)
    local escort = rec -- the player flies beside the recycler, then on to the dust-off beacon
    sim:each(function(s)
        local x, z = s:pos(escort)
        local pl = s:unit(s.player)
        local dx, dz = x - pl.x, z - pl.z
        local d = math.sqrt(dx * dx + dz * dz)
        if d > 50 then local k = math.min(pl.speed * s.dt, d - 50) / d; pl.x, pl.z = pl.x + dx * k, pl.z + dz * k end
    end)

    local function at(x, z, r) return function(s) return s:dist(rec, { x = x, z = z }) < r end end
    sim:when(function(s) return s.t >= 2 end, function() M.missionstart, M.opencamdone = false, false end) -- intro camera ends
    sim:when(at(1851, 99550, 70), function() M.hephikey = true end)
    sim:when(at(2861, 99215, 70), function(s)
        M.starportreconed = true
        M.starportcam = s:add("apcamr", 1, s:pos("cam1spawn"))
    end)
    sim:when(function(s) return s:unit(rec).deployed end, function() M.launchpadreconed = true end)
    -- The extract beacon appears while the convoy drives (platoon event); bugout3 is the worst case:
    -- the recycler latches path 38's last point ~60 m short and is then ~130 m from it.
    local dust, stallDist
    sim:when(function() return M.pilot and M.pilot.convoy end, function(s)
        local x, z = s:pos("bugout" .. (extractpoint + 1))
        dust = s:add("apcamr", 1, x, z)
        M.dustoffcam = dust
        sim:track("dustoff", dust)
    end)
    if stall then -- the Goto to the dust-off beacon is dropped once, a second after it was given
        local seen
        sim:stallOnce(rec, function(s, u)
            if u.tgt ~= dust then return false end
            seen = seen or s.t
            if s.t >= seen + 1 then stallDist = s:dist(rec, dust); return true end
            return false
        end)
    end

    if probe then -- the recycler drops its order once when it is near this point of path 35/36
        sim:stallOnce(rec, function(s) return s:dist(rec, { x = probe[2], z = probe[3] }) < 40 end)
    end
    sim:runUntil(function(s) return M.pilot and M.pilot.introDone end, 20, "the branch to start path 35")
    sim:runUntil(function(s) return M.hephikey end, 200, "the recycler to finish path 35")
    sim:runUntil(function(s) return M.starportreconed end, 200, "the recycler to finish path 36")
    sim:runUntil(function(s) return s:unit(rec).deployed end, 250, "the recycler to deploy on its geyser")
    sim:runUntil(function() return M.pilot.convoy end, 120, "the convoy (path 38) to start with the player beside the recycler")
    sim:runUntil(function() return M.pilot.route == nil end, 400, "path 38 to end and the recycler to be sent to the dust-off beacon")
    local armed = sim.t
    escort = dust
    local nearAtArm = sim:dist(rec, dust) < 100
    -- The win: recycler and player within 100 m of the dust-off beacon (misn06cr.lua ~2547).
    sim:runUntil(function(s) return s:dist(rec, dust) < 100 and s:dist(s.player, dust) < 100 end, 120,
        "the recycler within 100 m of the dust-off beacon")
    if stall then
        local fired = sim:stallsFired()
        sim:expect(fired == 1 or nearAtArm, "the stall injector fired (or the recycler was already within 100 m)")
        sim.needsResend = fired == 1 and stallDist > 100 -- stopped within 100 m: the win holds without the resend
        if sim.needsResend then sim:expect(sim.t - armed >= 8, "the recycler needed the 10 s resend to finish") end
    end
    sim:expect(not sim.failed, "the branch did not fail the mission")
    return sim
end

for ep = 0, 3 do
    local plain = run(ep, false)
    local stalled = run(ep, true)
    print(string.format("misn06 PilotSim OK bugout%d: dust-off reached t=%.0f s (no stall), t=%.0f s (stall injected; resend %s), script %s",
        ep + 1, plain.t, stalled.t, stalled.needsResend and "needed" or "not needed", plain.scriptPath))
end

-- One dropped order mid-leg on paths 35 and 36 (re-sent by PilotBranch.KeepGoto) must still reach the dust-off.
for _, probe in ipairs({ { "path 35", 860, 99770 }, { "path 36", 2150, 99340 } }) do
    run(2, false, probe)
    print(string.format("misn06 PilotSim OK: order dropped once mid-%s recovers", probe[1]))
end
