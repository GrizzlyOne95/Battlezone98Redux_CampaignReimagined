-- Win-path simulation for misn13cr's N64 Pilot Mode branch. The win (misn13cr.lua ~2314: the CCA
-- Unit Factory and base destroyed) is the player's job, so the AI duties are the build-up that
-- makes it winnable: the recycler drives to eggeizr114_geyser and deploys, two scavengers are
-- built and earn scrap, the factory is built, drives to eggeizr112_geyser and deploys, four turrets
-- are built and walk to the spot orders, and two tanks come from the factory and follow the player.
-- Each Goto (recycler, factory, turrets) is also run with the order dropped once (stall injector).
-- Run from the repo root:
--   lua5.1 Tools/MissionTests/Test-Misn13PilotSim.lua
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")
local CMD = PilotSim.AiCommand

local function run(stall)
    local sim = PilotSim.new{ name = "misn13" .. (stall and "+stall" or ""), script = "Scripts/misn13cr.lua",
        bzn = "Missions/misn13cr.bzn",
        pattern = "(local Pilot = {.-)\n%-%- N64 Pilot Mode branch end",
        -- the block asks require() for PlayerPilotMode; the harness supplies it as a local
        transform = function(s) return (s:gsub('require%("PlayerPilotMode"%)', "PlayerPilotMode")) end,
        exports = "update = Pilot.Update, add = Pilot.AddObject",
        scrap = 40, pilots = 10 } -- misn13cr.lua ~1491: SetPilot(1, 10) / SetScrap(1, 40)
    local M = sim.M
    M.nsdfrecycle, M.nav1 = "avrecycle", "apcamr20_camerapod"
    -- the top-up natives the block calls when the pilot or scrap count is short
    sim.env.AddScrap = function(_, n) sim.scrap[1] = math.min(sim.maxScrap, sim.scrap[1] + n) end
    sim.env.AddPilot = function(_, n) sim.pilots[1] = sim.pilots[1] + n end
    sim:hook(function(h) return sim.api.add(h) end)
    local rec = M.nsdfrecycle
    sim:track("rec", rec); sim:track("player", sim.player)

    local fac, turrets, tanks, scavs = nil, {}, {}, {}
    sim.onSpawn = function(h)
        local o = sim:unit(h)
        if o.odf == "avmuf" then fac = h; sim:track("factory", h) end
        if o.odf == "avturr" then turrets[#turrets + 1] = h end
        if o.odf == "avtank" then tanks[#tanks + 1] = h end
        if o.odf == "avscav" then scavs[#scavs + 1] = h end
    end
    sim:expect(not sim:unit(rec).deployed, "the BZN recycler starts undeployed")
    if stall then sim:stallOnce(rec, function(s) return s.t > 1 end) end -- the first Goto to the geyser is dropped
    return sim, M, rec, function() return fac, turrets, tanks, scavs end
end

local function scenario(stall, turretStall)
    local sim, M, rec, units = run(stall)
    local gR, gF = "eggeizr114_geyser", "eggeizr112_geyser"
    local facStallArmed, turStallArmed = false, false
    sim:each(function(s)
        local fac, tur = units()
        if turretStall and tur[1] and not turStallArmed then
            turStallArmed = true -- the first turret's spot Goto is dropped once
            s:stallOnce(tur[1], function(_, u) return u.tgt ~= nil end)
        end
        if stall and fac and not facStallArmed then
            facStallArmed = true
            s:stallOnce(fac, function() return true end) -- the factory's Goto is dropped once
        end
    end)
    sim:runUntil(function(s) return s:unit(rec).deployed end, 60, "the recycler to deploy on eggeizr114_geyser")
    sim:expect(sim:dist(rec, gR) < 15, "the recycler stands on its geyser")
    local recT = sim.t
    sim:runUntil(function() local _, _, _, sc = units(); return #sc >= 2 end, 120, "two scavengers to be built")
    sim:runUntil(function() return (units()) ~= nil end, 150, "the factory (avmuf) to be built")
    local facBuilt = sim.t
    local fac = units()
    sim:runUntil(function(s) return s:unit(fac).deployed end, 200, "the factory to deploy on eggeizr112_geyser")
    sim:expect(sim:dist(fac, gF) < 15, "the factory stands on its geyser")
    local facT = sim.t
    sim:runUntil(function() local _, t = units(); return #t >= 4 end, 200, "four turrets to be built")
    -- turret placement: the first to (3498, 97864), the rest to (3472, 97953); all must arrive.
    local _, turrets, tanks = units()
    local function nearXZ(h, x, z) return sim:dist(h, { x = x, z = z }) < 15 end
    sim:runUntil(function(s)
        if not nearXZ(turrets[1], 3498, 97864) then return false end
        for i = 2, 4 do if not nearXZ(turrets[i], 3472, 97953) then return false end end
        return true
    end, 120, "the four turrets to reach their spots")
    local turretT = sim.t
    sim:runUntil(function() local _, _, tk = units(); return #tk >= 2 end, 200, "two tanks to be built by the factory")
    _, _, tanks = units()
    sim:runFor(1)
    for i, h in ipairs(tanks) do
        sim:expect(sim:unit(h).cmd == CMD.FOLLOW and sim:unit(h).tgt == sim.player, "tank " .. i .. " follows the player")
    end
    sim:expect(sim.refused == 0, "no build order was refused (refused " .. sim.refused .. ")")
    sim:expect(sim.income > 0, "the scavengers earned scrap")
    if stall then
        local fired, total = sim:stallsFired()
        sim:expect(fired == total and total == 2, "both injected stalls fired (" .. fired .. "/" .. total .. ")")
    end
    sim:runFor(60) -- the branch keeps running (fighters, regroup) with no unmodelled native or failure
    sim:expect(not sim.failed, "the branch did not fail the mission")
    return sim, recT, facBuilt, facT, turretT
end

for _, stall in ipairs({ false, true }) do
    local sim, recT, facBuilt, facT, turretT = scenario(stall)
    print(string.format("misn13 PilotSim OK%s: recycler deployed t=%.0f s, factory built t=%.0f s deployed t=%.0f s, turrets placed t=%.0f s, tanks following t=%.0f s, scrap earned %.1f, script %s",
        stall and " (stall injected: recycler + factory Goto dropped once)" or "", recT, facBuilt, facT, turretT, sim.t - 60, sim.income, sim.scriptPath))
end

-- A turret Goto dropped once is re-sent by PilotBranch.KeepSpots.
scenario(false, true)
print("misn13 PilotSim OK: turret Goto dropped once recovers")
