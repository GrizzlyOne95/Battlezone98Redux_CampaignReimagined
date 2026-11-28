-- Win-path simulation for misn08cr's N64 Pilot Mode branch (misn08cr.lua ~1224-1458).
-- AI duties (the player is only a pilot):
--   1. the Utah recycler (avrecycle) drives to the nearest free geyser and deploys (Goto, then
--      PilotBranch.Resend);
--   2. it builds the replacement factory (avmu8, 10 scrap), which goes to a second geyser and
--      deploys; then two scavengers (scrap/pilot top-up), two tanks, and once both Soviet walkers
--      are dead the howitzer (avartl);
--   3. the howitzer drives to (1869,99301), deploys and shells the three power plants in turn
--      (the branch fails the mission if the howitzer dies).
-- The win itself (CCA recycler and factory destroyed, a player at the relic) is player combat.
-- The scenario hand-sets what the mission does: SetScrap(1,30) at start (misn08cr.lua ~1753; the
-- difficulty scaler may lower it, so scrap 15 runs too), pilots 10 (UNVERIFIED start value), the
-- walkers dying (killed by the player at t=100).
-- Engine assumptions (UNVERIFIED): a howitzer deploys by itself when idle for 3 s; a deployed howitzer
-- kills a target within 460 m (avartl rangeScan) in 10 s. avmu8 (the factory ODF) is not recognised as a
-- producer by PilotSim, so the scenario deploys it on arrival at its geyser.
-- Run from the repo root:
--   lua5.1 Tools/MissionTests/Test-Misn08PilotSim.lua
-- PILOTSIM_PROBE=1 also runs the known gap (a start with no pilots).
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")
local CMD = PilotSim.AiCommand
local RANGE = 460
local PLANTS = { "power1", "sblpow2_powerplant", "sblpow4_powerplant" }

local function run(opt)
    opt = opt or {}
    local sim = PilotSim.new{ name = "misn08/" .. (opt.name or "plain"),
        script = "Scripts/misn08cr.lua", bzn = "Missions/misn08cr.bzn",
        pattern = "(local PILOT_TURRET_SPOTS =.-)\n%-%- CR PDA <<",
        exports = "update = PilotUpdate, add = PilotAddObject, init = InitializePilotMode",
        scrap = opt.scrap or 30, pilots = opt.pilots or 10 }
    local M, env = sim.M, sim.env
    sim.api.init()
    env.AddScrap = function(team, n) sim.scrap[team] = math.min(sim.maxScrap, (sim.scrap[team] or 0) + n) end
    env.AddPilot = function(team, n) sim.pilots[team] = (sim.pilots[team] or 0) + n end
    env.RemoveObject = function(h) sim:unit(h).alive = false end
    M.nsdfrecycle, M.ccagech1, M.ccagech2, M.nav4 = "avrecycle", "sovgech1", "sovgech2", "cam2"
    local rec = M.nsdfrecycle
    sim:track("rec", rec); sim:track("player", sim.player)
    sim:hook(function(h) return sim.api.add(h) end)
    local u = { turrets = {}, tanks = 0, scavs = 0 }
    sim.onSpawn = function(h)
        local o = sim:unit(h).odf
        if o == "avmu8" then u.muf = h; M.nsdfmuf = h; sim:track("muf", h) end
        if o == "avartl" then u.how = h; sim:track("howitzer", h) end
        if o == "avturr" then u.turrets[#u.turrets + 1] = h end
        if o == "avtank" then u.tanks = u.tanks + 1 end
        if o == "avscav" then u.scavs = u.scavs + 1 end
    end

    -- Engine stand-ins: the factory deploys on its geyser; the howitzer deploys when idle and shells
    -- its target when in range.
    sim:each(function(s)
        local m = u.muf and s:unit(u.muf)
        if m and m.alive and m.cmd == CMD.NONE and not m.deployed and M.pilot and M.pilot.mufGeyser
            and s:dist(u.muf, M.pilot.mufGeyser) < 15 then m.deployed = true end
        local h = u.how and s:unit(u.how)
        if h and h.alive then
            if not h.deployed and h.speed == 0 then h.speed = 15 end
            if not h.deployed and h.cmd == CMD.NONE and not h.build then
                h.idle = h.idle or s.t
                if s.t - h.idle >= 3 then h.deployed, h.speed, h.idle = true, 0, nil; s:say("howitzer deployed (idle)") end
            else h.idle = nil end
            if h.deployed and h.cmd == CMD.ATTACK and s.objs[h.tgt] and s.objs[h.tgt].alive then
                if s:dist(u.how, h.tgt) <= RANGE then
                    h.atkAt = h.atkAt or s.t
                    if s.t - h.atkAt >= 10 then s.objs[h.tgt].alive = false; h.atkAt = nil; s:say("howitzer killed " .. h.tgt) end
                elseif not h.oor then
                    h.oor = true; s:say(string.format("howitzer deployed %.0f m from %s: out of range", s:dist(u.how, h.tgt), h.tgt))
                end
            end
        end
    end)
    sim:when(function(s) return s.t >= 100 end, function(s) -- the player kills both Soviet walkers
        s:unit("sovgech1").alive = false; s:unit("sovgech2").alive = false
    end)
    if opt.stall then
        sim:stallOnce(rec, function(s) return s.t > 2 end)
        sim:when(function() return u.muf end, function(s)
            sim:stallOnce(u.muf, function(ss, x) return x.tgt ~= nil end)
        end)
    end
    if opt.probe then opt.probe(sim, u) end

    sim:runUntil(function(s) return s:unit(rec).deployed end, 150, "the Utah recycler to deploy on a geyser")
    local recAt = sim.t
    sim:runUntil(function(s) return u.muf and s:unit(u.muf).deployed end, 150, "the replacement factory to be built and deploy on a geyser")
    sim:expect(sim:dist(u.muf, rec) > 15, "the factory took a different geyser from the recycler")
    local mufAt = sim.t
    sim:runUntil(function(s) return u.scavs >= 2 and u.tanks >= 2 end, 300, "2 scavengers and 2 tanks to be built")
    sim:runUntil(function(s) return u.how end, 200, "the howitzer to be built once the walkers are dead")
    sim:runUntil(function(s) return s:unit(u.how).deployed end, 300, "the howitzer to reach (1869,99301) and deploy")
    sim:expect(sim:dist(u.how, { x = 1869, z = 99301 }) < 15, "howitzer deployed at its firing spot")
    sim:runUntil(function(s)
        for _, p in ipairs(PLANTS) do if s:unit(p).alive then return false end end
        return true
    end, 300, "the howitzer to destroy all three power plants")
    sim:runUntil(function(s) return #u.turrets >= 3 end, 200, "three turrets to be built")
    sim:runUntil(function(s)
        local spots = { { 2352, 101153 }, { 2413, 101095 }, { 2293, 101204 } }
        for i = 1, 3 do if s:dist(u.turrets[i], { x = spots[i][1], z = spots[i][2] }) > 15 then return false end end
        return true
    end, 100, "the turrets to reach their spots")
    sim:expect(not sim.failed and sim:unit(rec).alive and sim:unit(u.how).alive, "mission not failed, recycler and howitzer alive")
    return sim, recAt, mufAt
end

for _, cfg in ipairs({ { 30, 10 }, { 15, 10 } }) do
    local a, r1, m1 = run{ name = "scrap" .. cfg[1], scrap = cfg[1], pilots = cfg[2] }
    local b, r2, m2 = run{ name = "scrap" .. cfg[1] .. "+stall", scrap = cfg[1], pilots = cfg[2], stall = true }
    local fired, total = b:stallsFired()
    b:expect(fired == 2 and total == 2, "both injected stalls fired (" .. fired .. "/" .. total .. ")")
    print(string.format("misn08 PilotSim OK scrap=%d: recycler deployed t=%.0f s, factory deployed t=%.0f s, plants+turrets done t=%.0f s (no stall); %.0f / %.0f / %.0f s (recycler and factory Goto dropped once, Resend), script %s",
        cfg[1], r1, m1, a.t, r2, m2, b.t, a.scriptPath))
end

local function drop(sim, u, label, get, ready)
    local done = false
    sim:each(function(s)
        local h = get()
        if h and not done and (not ready or ready()) and s:unit(h).cmd == CMD.GO then
            done = true; local x = s:unit(h); x.cmd, x.tgt, x.route = CMD.NONE, nil, nil; s:say("STALL injected: " .. label)
        end
    end)
end
-- The howitzer spot Goto dropped once is re-sent by PilotBranch.KeepSpots.
run({ name = "howitzer-stall", probe = function(sim, u)
    drop(sim, u, "howitzer spot order", function() return u.how end) end })
print("misn08 PilotSim OK: howitzer that drops its spot Goto recovers")
if os.getenv("PILOTSIM_PROBE") then
    -- Unfixed gap, UNVERIFIED if the map can start that way: the factory (~1399) and tanks (~1429) have no pilot top-up.
    local ok, err = pcall(run, { name = "probe", pilots = 0 })
    print("probe (no starting pilots): " .. (ok and "recovers" or ("GAP: " .. tostring(err):match("^[^\n]*"))))
end
