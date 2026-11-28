-- Win-path simulation for misn07cr's N64 Pilot Mode branch (misn07cr.lua ~1545-1784).
-- AI duties (the player is only a pilot):
--   1. the armory (avslf) deploys on eggeizr1238_geyser, the two wing turrets reach their spots;
--   2. once the radar array falls the mission spawns the Utah recycler and the factory and sends
--      them down their paths; the branch re-sends both to recycle_spawn_geyz / show_geyser to deploy;
--   3. the recycler builds 2 scavengers (scrap/pilot top-up), 4 turrets (each to its spot), the
--      factory builds howitzer 1, which goes to (2466,99919), deploys and kills the power plant;
--   4. howitzer 2 and the light tank follow once the plant is down; both howitzers drive to the
--      end of paths 16/18, deploy and shell the Soviet recycler (the win: svrecycler dead).
-- The scenario hand-sets the flags the mission raises (first_objective; next_mission with
-- AddScrap(1,30)/SetPilot(1,20); the Utah and nav spawns) at the places the script does.
-- Engine assumptions (UNVERIFIED): a howitzer deploys by itself when idle for 3 s (the branch never
-- orders a deploy), a deployed howitzer kills a target within 460 m (avartl rangeScan) in 10 s.
-- avsl7 and avmu7 (the armory and factory ODFs) are not recognised as producers by PilotSim, so the
-- scenario deploys them on arrival at their geysers.
-- Run from the repo root:
--   lua5.1 Tools/MissionTests/Test-Misn07PilotSim.lua
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")
local CMD = PilotSim.AiCommand
local RANGE = 460

-- Drop one unit's order the first tick it has a GO order and `ready(sim)` holds (a one-shot stall).
local function dropOnce(sim, getHandle, label, ready)
    local done = false
    sim:each(function(s)
        local h = getHandle()
        if h and not done and (not ready or ready(s)) and s:unit(h).cmd == CMD.GO then
            done = true
            local u = s:unit(h); u.cmd, u.tgt, u.route = CMD.NONE, nil, nil
            s:say("STALL injected: " .. label)
        end
    end)
end

local function run(opt)
    opt = opt or {}
    local sim = PilotSim.new{ name = "misn07/" .. (opt.name or "plain"),
        script = "Scripts/misn07cr.lua", bzn = "Missions/misn07cr.bzn",
        pattern = "(local PILOT_WING_SPOTS =.-)\n%-%- CR Pilot Mode <<",
        exports = "update = PilotUpdate, add = PilotAddObject, init = InitializePilotMode",
        scrap = 0, pilots = 0 }
    local M, env = sim.M, sim.env
    sim.api.init()
    env.AddScrap = function(team, n) sim.scrap[team] = math.min(sim.maxScrap, (sim.scrap[team] or 0) + n) end
    env.AddPilot = function(team, n) sim.pilots[team] = (sim.pilots[team] or 0) + n end
    M.nsdfarmory, M.wingturret1, M.wingturret2 = "avslf", "avturret1", "avturret2"
    M.powrplnt1, M.ccarecycle = "power1", "svrecycler"
    M.spawn_point, M.show_geyser, M.nav3 = "recycle_spawn_geyz", "show_geyser", "cam3"
    sim:track("armory", "avslf"); sim:track("player", sim.player)
    sim:hook(function(h) return sim.api.add(h) end)
    local units = { turrets = {}, how = {}, scavs = 0 }
    sim.onSpawn = function(h)
        local o = sim:unit(h).odf
        if o == "avturr" then units.turrets[#units.turrets + 1] = h; sim:track("turr" .. #units.turrets, h) end
        if o == "avartl" then units.how[#units.how + 1] = h; sim:track("how" .. #units.how, h) end
        if o == "avltnk" then units.lt = h end
        if o == "avscav" then units.scavs = units.scavs + 1 end
    end

    -- Engine stand-ins: the armory deploys on its geyser; howitzers deploy when idle and shell
    -- targets in range.
    sim:each(function(s)
        local a = s:unit("avslf")
        if a.alive and a.cmd == CMD.NONE and not a.deployed and s:dist("avslf", "eggeizr1238_geyser") < 15 then a.deployed = true end
        local f = M.nsdfmuf and s:unit(M.nsdfmuf)
        if f and f.alive and f.cmd == CMD.NONE and not f.deployed and s:dist(M.nsdfmuf, "show_geyser") < 15 then f.deployed = true end
        for _, h in ipairs(units.how) do
            local u = s:unit(h)
            if u.alive then
                if not u.deployed and u.speed == 0 then u.speed = 15 end
                if not u.deployed and u.cmd == CMD.NONE and not u.build then
                    u.idle = u.idle or s.t
                    if s.t - u.idle >= 3 then u.deployed, u.speed, u.idle = true, 0, nil; s:say(h .. " deployed (idle)") end
                else u.idle = nil end
                if u.deployed and u.cmd == CMD.ATTACK and s.objs[u.tgt] and s.objs[u.tgt].alive then
                    if s:dist(h, u.tgt) <= RANGE then
                        u.atkAt = u.atkAt or s.t
                        if s.t - u.atkAt >= 10 then s.objs[u.tgt].alive = false; u.atkAt = nil; s:say(h .. " killed " .. u.tgt) end
                    elseif not u.oor then
                        u.oor = true; s:say(string.format("%s deployed %.0f m from %s: out of range", h, s:dist(h, u.tgt), u.tgt))
                    end
                end
            end
        end
    end)

    if opt.stall then -- each producer-style Goto is dropped once
        sim:stallOnce("avslf", function(s) return s.t > 2 end)
    end

    -- The mission raises these when the radar array falls (misn07cr.lua ~3011-3090).
    local utahAt = 20
    sim:when(function(s) return s.t >= utahAt end, function(s)
        M.first_objective = true
        local x, z = s:pos("recycle_spawn"); local rec = s:add("avrec7", 1, x, z)
        x, z = s:pos("muf_spawn"); local fac = s:add("avmu7", 1, x, z)
        M.nsdfrecycle, M.nsdfmuf = rec, fac
        env.Goto(rec, "recycle_path", 0); env.Goto(fac, "muf_path", 0)
        M.nav6 = s:add("apcamr", 1, s:pos("recycle_cam_spawn")); M.nav7 = s:add("apcamr", 1, s:pos("recy_cam_spawn"))
        sim.api.add(rec); sim.api.add(fac)
        env.AddScrap(1, 30); sim.pilots[1] = 20
        M.next_mission = true
        sim:track("utah", rec); sim:track("fac", fac)
        sim:playerEscort(rec, 50)
        if opt.stall then
            sim:stallOnce(rec, function(ss, u) return u.tgt == "recycle_spawn_geyz" end)
            sim:stallOnce(fac, function(ss, u) return u.tgt == "show_geyser" end)
        end
    end)
    if opt.probe then opt.probe(sim, units) end

    -- 1. start: armory and wing turrets.
    sim:runUntil(function(s) return s:unit("avslf").deployed end, 150, "the armory to deploy on eggeizr1238_geyser")
    sim:runUntil(function(s) return s:dist("avturret1", { x = 2033, z = 97882 }) < 15 and s:dist("avturret2", { x = 2015, z = 97837 }) < 15 end,
        120, "both wing turrets to reach their spots")
    -- 2. Utah and factory deploy.
    sim:runUntil(function(s) return M.nsdfrecycle and s:unit(M.nsdfrecycle).deployed and s:unit(M.nsdfmuf).deployed end, 300,
        "the Utah recycler and the factory to deploy on their geysers")
    local deployedAt = sim.t
    sim:expect(sim:dist(M.nsdfrecycle, "recycle_spawn_geyz") < 15 and sim:dist(M.nsdfmuf, "show_geyser") < 15, "producers stand on their geysers")
    -- 3. scavengers, turrets to their spots, howitzer 1.
    local spots = { { 2232, 100262 }, { 2228, 100211 }, { 2252, 100081 }, { 2306, 100083 } }
    sim:runUntil(function(s) return units.scavs >= 2 and #units.turrets >= 4 and #units.how >= 1 end, 400,
        "2 scavengers, 4 turrets and howitzer 1 to be built")
    sim:runUntil(function(s)
        for i = 1, 4 do if s:dist(units.turrets[i], { x = spots[i][1], z = spots[i][2] }) > 15 then return false end end
        return true
    end, 200, "the four turrets to reach their spots")
    sim:runUntil(function(s) return s:unit(units.how[1]).deployed end, 200, "howitzer 1 to deploy at its firing spot")
    sim:expect(sim:dist(units.how[1], { x = 2466, z = 99919 }) < 15, "howitzer 1 deployed at (2466,99919)")
    sim:runUntil(function(s) return not s:unit("power1").alive end, 100, "howitzer 1 to destroy the power plant")
    local plantAt = sim.t
    -- 4. second howitzer, light tank, both howitzers into position and the recycler dies (the win).
    sim:runUntil(function(s) return #units.how >= 2 and units.lt end, 200, "howitzer 2 and the light tank to be built")
    sim:runUntil(function(s) return not s:unit("svrecycler").alive end, 500, "both howitzers to deploy and destroy the Soviet recycler")
    sim:expect(M.pilot.howitzerAttack, "the branch ordered both howitzers to attack the recycler")
    sim:expect(sim:unit(M.nsdfrecycle).alive and not sim.failed, "the Utah survived and the mission did not fail")
    return sim, deployedAt, plantAt
end

local a, d1, p1 = run{ name = "plain" }
local b, d2, p2 = run{ name = "stall", stall = true }
local fired, total = b:stallsFired()
b:expect(fired == total and total == 3, "all three injected stalls fired (" .. fired .. "/" .. total .. ")")
print(string.format("misn07 PilotSim OK: Utah+factory deployed t=%.0f s, power plant down t=%.0f s, Soviet recycler dead t=%.0f s (no stall); %.0f / %.0f / %.0f s (armory, Utah and factory Goto dropped once, Resend), script %s",
    d1, p1, a.t, d2, p2, b.t, a.scriptPath))

-- Spot Gotos dropped once are re-sent by PilotBranch.KeepSpots.
local probes = {
    { "wing turret 1 drops its spot Goto", function(sim, u)
        dropOnce(sim, function() return "avturret1" end, "wing turret 1 spot order") end },
    { "a turret drops its spot Goto", function(sim, u)
        dropOnce(sim, function() return u.turrets[1] end, "turret 1 spot order") end },
    { "howitzer 1 drops its Goto to the firing spot", function(sim, u)
        dropOnce(sim, function() return u.how[1] end, "howitzer 1 spot order") end },
    { "howitzer 1 drops its Goto along path 16", function(sim, u)
        dropOnce(sim, function() return u.how[1] end, "howitzer 1 route order", function() return u.lt ~= nil end) end },
    { "howitzer 2 drops its Goto along path 18", function(sim, u)
        dropOnce(sim, function() return u.how[2] end, "howitzer 2 route order") end },
}
for _, p in ipairs(probes) do
    run({ name = "probe", probe = p[2] })
    print("misn07 PilotSim OK: " .. p[1] .. " and still wins")
end
