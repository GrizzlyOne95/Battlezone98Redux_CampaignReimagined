-- Win-path simulation for misn10cr's N64 Pilot Mode branch (misn10cr.lua ~160-300).
-- The win (misn10cr.lua ~2002): the relic is tugged (GetTug(sav) a team-1 craft -> sav_secure) to
-- within 100 m of the Utah recycler. The player is only a pilot, so the branch must supply the tug:
-- AI duties:
--   1. the Utah (starts deployed) builds two scavengers (scrap/pilot top-up), the factory (avmuf,
--      10 scrap) and two turrets; the factory is re-sent to the nearest free geyser (Resend) and
--      deploys;
--   2. the factory builds the tug (avhaul, 6 scrap, a pilot) and the tug follows the player;
--   3. with the tug within 100 m of the relic it is ordered to Pickup the relic and picks it up;
--   4. once the relic is secure the tug follows the player home, carrying the relic into the
--      100 m ring around the Utah.
-- The scenario flies the player to the relic once the tug exists (the real player would), sets
-- sav_secure when the tug holds the relic (misn10cr.lua ~1165) and checks the win condition.
-- Start resources are SetScrap(1,30)/SetPilot(1,10) (~1482). avmuf is a producer to PilotSim.
-- Run from the repo root:
--   lua5.1 Tools/MissionTests/Test-Misn10PilotSim.lua
-- Side note (not tested, UNVERIFIED intent): the built turrets Goto "main_return_path", whose last
-- point (1183,100502) is next to the CCA recycler (1164,100560).
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")
local CMD = PilotSim.AiCommand

-- The block calls require() at load; the harness provides the same modules as upvalues.
local function transform(source)
    source = source:gsub('require%("PlayerPilotMode"%)', "PlayerPilotMode")
    source = source:gsub('require%("CRPilotBranch"%)', "PilotBranch")
    return source
end

local function run(opt)
    opt = opt or {}
    local sim = PilotSim.new{ name = "misn10/" .. (opt.name or "plain"),
        script = "Scripts/misn10cr.lua", bzn = "Missions/misn10cr.bzn",
        pattern = "(local Pilot = {.-)\n%-%- N64 Pilot Mode branch end", transform = transform,
        exports = "update = Pilot.Update, add = Pilot.AddObject",
        scrap = 30, pilots = 10 }
    local M, env = sim.M, sim.env
    env.AddScrap = function(team, n) sim.scrap[team] = math.min(sim.maxScrap, (sim.scrap[team] or 0) + n) end
    env.AddPilot = function(team, n) sim.pilots[team] = (sim.pilots[team] or 0) + n end
    M.nsdfrecycle, M.sav, M.nav1, M.nav3 = "avrecycler", "relic", "cam1", "cam3"
    M.sav_free, M.sav_secure = true, false
    local rec = M.nsdfrecycle
    sim:unit(rec).deployed = true -- the Utah starts deployed
    sim:track("rec", rec); sim:track("player", sim.player); sim:track("relic", "relic")
    sim:hook(function(h) return sim.api.add(h) end)
    local u = { scavs = 0, turrets = 0 }
    sim.onSpawn = function(h)
        local o = sim:unit(h).odf
        if o == "avmuf" then u.muf = h; sim:track("factory", h) end
        if o == "avhaul" then u.tug = h; sim:track("tug", h) end
        if o == "avscav" then u.scavs = u.scavs + 1 end
        if o == "avturr" then u.turrets = u.turrets + 1 end
    end

    -- The mission's own relic bookkeeping (misn10cr.lua ~1165-1170).
    sim:each(function(s)
        local relic = s:unit("relic")
        if M.sav_free and relic.tug and s:unit(relic.tug).team == 1 then
            M.sav_free, M.sav_secure, M.tugger = false, true, relic.tug
            s:say("relic secure: tug holds it")
        end
    end)
    -- The player flies to the relic once the tug exists, then home to the Utah once it is secure.
    local function flyTo(s, ref, offset)
        local p = s:unit(s.player)
        local x, z = s:pos(ref)
        local dx, dz = x - p.x, z - p.z
        local d = math.sqrt(dx * dx + dz * dz)
        if d > offset then local k = math.min(p.speed * s.dt, d - offset) / d; p.x, p.z = p.x + dx * k, p.z + dz * k end
    end
    sim:each(function(s)
        if not u.tug then return end
        if M.sav_secure then flyTo(s, rec, 40) else flyTo(s, "relic", 20) end
    end)

    -- Stall injections.
    if opt.stall then
        sim:when(function() return u.muf end, function(s)
            sim:stallOnce(u.muf, function(ss, x) return x.tgt ~= nil end)
        end)
    end
    if opt.dropCmd then -- drop the tug's first order of that kind once (not a GO, so done here)
        local done = false
        sim:each(function(s)
            if u.tug and not done and s:unit(u.tug).cmd == opt.dropCmd and (not opt.dropWhen or opt.dropWhen(s)) then
                done = true
                local t = s:unit(u.tug); t.cmd, t.tgt, t.route = CMD.NONE, nil, nil
                s:say("STALL injected: tug drops its order " .. opt.dropCmd)
            end
        end)
    end

    sim:runUntil(function(s) return u.muf end, 200, "the factory to be built (scavengers first)")
    sim:runUntil(function(s) return s:unit(u.muf).deployed end, 100, "the factory to deploy on a geyser")
    sim:expect(u.scavs >= 2, "two scavengers were built before the factory")
    local mufAt = sim.t
    sim:runUntil(function(s) return u.tug end, 200, "the tug (avhaul) to be built")
    sim:expect(u.turrets >= 2, "two turrets were built before the tug")
    local tugAt = sim.t
    sim:runUntil(function(s) return s:unit("relic").tug == u.tug end, 300, "the tug to pick the relic up")
    local pickAt = sim.t
    sim:runUntil(function(s) return M.sav_secure and s:dist("relic", rec) < 100 end, 300, "the carried relic to come within 100 m of the Utah (the win)")
    sim:expect(not sim.failed and sim:unit(rec).alive, "the mission did not fail")
    return sim, mufAt, tugAt, pickAt
end

local a, m1, t1, p1 = run{ name = "plain" }
local b, m2, t2, p2 = run{ name = "stall", stall = true }
local fired, total = b:stallsFired()
b:expect(fired == 1 and total == 1, "the factory stall fired (" .. fired .. "/" .. total .. ")")
print(string.format("misn10 PilotSim OK: factory deployed t=%.0f s, tug built t=%.0f s, relic picked up t=%.0f s, relic home t=%.0f s (no stall); %.0f / %.0f / %.0f / %.0f s (factory Goto dropped once, Resend), script %s",
    m1, t1, p1, a.t, m2, t2, p2, b.t, a.scriptPath))

-- The tug's Pickup and Follow orders dropped once are re-sent by PilotBranch.Keep.
local probes = {
    { "tug drops its Follow(player) before the pickup", { dropCmd = CMD.FOLLOW } },
    { "tug drops its Pickup(relic) order", { dropCmd = CMD.PICKUP } },
    { "tug drops its Follow(player) after the pickup", { dropCmd = CMD.FOLLOW,
        dropWhen = function(s) return s:unit("relic").tug ~= nil end } },
}
for _, p in ipairs(probes) do
    p[2].name = "probe"
    run(p[2])
    print("misn10 PilotSim OK: " .. p[1] .. " and still delivers the relic")
end
