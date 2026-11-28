-- Win-path simulation for misn05cr's N64 Pilot Mode branch.
-- AI duties (the player is only a pilot; misn05cr.lua ~452-575):
--   1. the recycler (avrecy-1) and the armory (avslf0) deploy on their geysers 118 / 132 (one
--      Goto at start, then PilotBranch.Resend after 6 s);
--   2. the recycler builds turret, scav, scav, turret, turret (24+ scrap, so the two
--      scavengers have to earn the shortfall on the harder difficulties), every item
--      affordable and built;
--   3. each turret reaches its N64 spot (Goto re-sent by KeepSpots).
-- The win itself (all attack waves dead, recycler and Lemnos alive) is player combat.
-- Start resources are DiffUtils.ScaleRes(40)/(10) (misn05cr.lua ~1225): scrap 20..60, pilots 5..15;
-- the scenario runs both extremes. Run from the repo root:
--   lua5.1 Tools/MissionTests/Test-Misn05PilotSim.lua
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")
local CMD = PilotSim.AiCommand
local SPOTS = { { 2214, 100216 }, { 2256, 100292 }, { 2219, 100284 }, { 1591, 100610 }, { 1525, 100610 }, { 1535, 100777 } }

local function run(scrap, pilots, stall, turretStall)
    local sim = PilotSim.new{ name = "misn05/" .. scrap .. (stall and "+stall" or "") .. (turretStall and "+turretstall" or ""),
        script = "Scripts/misn05cr.lua", bzn = "Missions/misn05cr.bzn",
        pattern = "(local PILOT_TURRET_SPOTS =.-)\n%-%- BuildObject invokes",
        exports = "update = PilotUpdate, add = PilotAddObject, init = InitializePilotMode",
        scrap = scrap, pilots = pilots }
    local M = sim.M
    sim.api.init()
    M.avrec, M.cam1 = "avrecy-1_recycler", "cam1"
    local rec, slf = M.avrec, "avslf0_armory"
    sim:track("rec", rec); sim:track("slf", slf); sim:track("player", sim.player)
    sim:hook(function(h) return sim.api.add(h) end)
    local turrets = {}
    sim.onSpawn = function(h) if sim:unit(h).odf == "avturr" then turrets[#turrets + 1] = h; sim:track("turr" .. #turrets, h) end end
    sim:playerEscort(rec, 60)
    if stall then -- both producers lose their Goto once, mid-drive
        sim:stallOnce(rec, function(s, u) return s.t > 2 end)
        sim:stallOnce(slf, function(s, u) return s.t > 2 end)
    end
    if turretStall then -- the first turret drops its one-shot spot order
        sim:each(function(s)
            if turrets[1] and not s.turretStalled and s:unit(turrets[1]).cmd == CMD.GO then
                s.turretStalled = true
                local u = s:unit(turrets[1]); u.cmd, u.tgt, u.route = CMD.NONE, nil, nil
                s:say("STALL injected: " .. turrets[1] .. " drops its spot order")
            end
        end)
    end

    sim:runUntil(function(s) return s:unit(rec).deployed and s:unit(slf).deployed end, 200, "recycler and armory to deploy on their geysers")
    sim:expect(sim:dist(rec, "eggeizr118_geyser") < 15 and sim:dist(slf, "eggeizr132_geyser") < 15, "producers stand on geysers 118 / 132")
    local deployedAt = sim.t
    sim:runUntil(function(s) return #turrets >= 3 and #s.built >= 5 end, 400, "the opening queue (turret, scav, scav, turret, turret) to be built")
    local odfs = {}
    for _, b in ipairs(sim.built) do odfs[#odfs + 1] = b.odf end
    sim:expect(table.concat(odfs, ",", 1, 5) == "avturr,avscav,avscav,avturr,avturr", "queue order: " .. table.concat(odfs, ","))
    sim:expect(sim.income > 0 or scrap >= 26, "scavengers earned scrap when the start scrap did not cover the queue")
    -- Every turret reaches its spot.
    sim:runUntil(function(s)
        for i, h in ipairs(turrets) do
            if s:dist(h, { x = SPOTS[i][1], z = SPOTS[i][2] }) > 15 then return false end
        end
        return true
    end, 300, "all three turrets to reach their N64 spots")
    sim:expect(not sim.failed, "the branch did not fail the mission")
    return sim, deployedAt
end

for _, cfg in ipairs({ { 20, 5 }, { 60, 15 } }) do
    local a, da = run(cfg[1], cfg[2], false)
    local b, db = run(cfg[1], cfg[2], true)
    local fired = b:stallsFired()
    PilotSim.expect(b, fired == 2, "both producer stalls fired (" .. fired .. ")")
    print(string.format("misn05 PilotSim OK scrap=%d pilots=%d: deployed t=%.0f s, queue+turret spots done t=%.0f s (no stall); deployed t=%.0f s, done t=%.0f s (producer stalls, Resend), script %s",
        cfg[1], cfg[2], da, a.t, db, b.t, a.scriptPath))
end

-- A turret that drops its spot Goto still reaches its spot (re-sent by PilotBranch.KeepSpots).
run(40, 10, false, true)
print("misn05 PilotSim OK: turret that drops its spot Goto recovers")
