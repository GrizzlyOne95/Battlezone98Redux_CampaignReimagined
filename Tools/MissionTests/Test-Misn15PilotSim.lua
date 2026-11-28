-- Win-path simulation for CRMisn15's N64 Pilot Mode branch (Missions/misn15.bzn, the misn15b map).
-- The win (CRMisn15.lua ~985) needs: a live recycler within 200 m of the Supply nav (cam5), the CCA
-- convoy joined (s.cca), the Massachusetts survivors recovered (s.nw), 75 team-1 scrap, and the
-- player within 300 m of cam5. The AI duties the pilot block performs for a player who only flies:
--   * the recycler drives to the geyser eggeizr19 after the rescue and deploys (Goto + 6 s Resend),
--   * the recycler builds the second scavenger, the constructor builds three silos (75 scrap needs more than two),
--   * scrap rises to 50, which starts the withdraw phase, and the recycler drives to cam5
--     (the 10 s withdraw resend) and stops within 200 m of it.
-- Mission code the real script runs (convoy walking tank_path, s.cca at 100 m of cam6/cam4, Recover of
-- the nw group, s.withdraw at 50 scrap) is emulated by hand at the positions the script uses.
-- Scenario assumptions, UNVERIFIED against the engine: start scrap 10 (AddScrap, ~936), start pilots 10,
-- an idle recovered scavenger earns nothing, team-1 scrap capacity = recycler 30 + silo 20 + factory 10
-- (the numbers Docs/MISN15_COOP.md gives for the current ODFs).
-- Run from the repo root:
--   lua5.1 Tools/MissionTests/Test-Misn15PilotSim.lua
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")

local PRELUDE = table.concat({
    "local function Valid(h) return h ~= nil and h ~= 0 and IsValid(h) end",
    "local function Alive(h) return Valid(h) and IsAlive(h) end",
    "local function IsOdfBase(h, n) return Valid(h) and IsOdf(h, n) end",
    "local function State() return M.cr end",
    "local function FinishFailure(r) M.lost = true; M.failReason = r; FailMission() end",
}, "\n") .. "\n"

local function run(stall)
    local sim = PilotSim.new{ name = "misn15" .. (stall and "+stall" or ""), script = "Scripts/CRMisn15.lua",
        bzn = "Missions/misn15.bzn", speeds = { avhraz = 25 }, -- the BZN player craft is a hover
        pattern = "%-%- CR pilot mode >>\n(.-)\n%-%- CR pilot mode <<",
        transform = function(s) return (s:gsub("%-%- CR pilot mode >>\n", function() return "-- CR pilot mode >>\n" .. PRELUDE end, 1)) end,
        exports = "update = PilotUpdate, add = PilotAddObject",
        scrap = 10, pilots = 10 }
    local M, env = sim.M, sim.env
    env.AddScrap = function(_, n) sim.scrap[1] = math.min(sim.maxScrap, sim.scrap[1] + n) end
    env.AddPilot = function(_, n) sim.pilots[1] = sim.pilots[1] + n end
    local s = { convoy = { "svtank0_wingman", "svtank1_wingman", "svapc0_apc" } }
    M.cr, M.start_done = s, true
    M.recy = "avrecy0_recycler"
    for i = 1, 6 do M["cam" .. i] = "apcamr" .. (i - 1) .. "_camerapod" end
    local rec, cons = M.recy, "avcnst0_constructionrig"
    for _, h in ipairs(s.convoy) do sim:unit(h).team = 7; sim.env.Goto(h, "tank_path") end
    sim:hook(function(h) return sim.api.add(h) end)
    sim:track("rec", rec); sim:track("cons", cons); sim:track("player", sim.player)
    sim:track("tank1", s.convoy[1]); sim:track("apc", s.convoy[3])

    local st = { silos = {}, scavs = {}, rec = rec, cons = cons }
    sim.onSpawn = function(h)
        local o = sim:unit(h)
        if o.odf == "absilo" then st.silos[#st.silos + 1] = h end
        if o.odf == "avscav" then st.scavs[#st.scavs + 1] = h; sim:track("scav", h) end
    end
    local function nearAll(h, pt, r) return sim:dist(h, pt) < r end

    -- Mission code, emulated: capacity from the stores, s.cca, Recover("nw"), s.withdraw.
    sim:each(function(sm)
        local cap = 30 + 20 * #st.silos -- silos are never lost in this scenario
        sm.maxScrap = cap
        if not s.cca then
            for _, h in ipairs(s.convoy) do
                if sm:dist(h, M.cam6) < 100 or sm:dist(h, M.cam4) < 100 then s.cca = true end
            end
            if s.cca then
                for _, h in ipairs(s.convoy) do sim:unit(h).team = 1; sim:unit(h).cmd = 0 end
                st.ccaAt = sm.t
            end
        end
        if not s.nw and nearAll(sm.player, M.cam2, 150) then
            s.nw, st.nwAt = true, sm.t
            for _, h in ipairs({ "cr15_nw_scav", "cr15_nw_apc", "cr15_nw_turret" }) do
                sim:unit(h).team, sim:unit(h).cmd = 1, 0
                sim.api.add(h)
            end
        end
        if not s.withdraw and math.floor(sm.scrap[1]) >= 50 then s.withdraw, st.withdrawAt = true, sm.t end
    end)
    -- The player flies: first to the Massachusetts survivors (cam2), later to Supply (cam5) once the
    -- withdraw phase starts. He is not asked to wait for anything.
    sim:each(function(sm)
        local p = sm:unit(sm.player)
        local goal = s.withdraw and M.cam5 or M.cam2
        local gx, gz = sm:pos(goal)
        local dx, dz = gx - p.x, gz - p.z
        local d = math.sqrt(dx * dx + dz * dz)
        if d > 40 then local k = math.min(p.speed * sm.dt, d - 40) / d; p.x, p.z = p.x + dx * k, p.z + dz * k end
    end)
    if stall then -- the rescue Goto to the geyser and the withdraw Goto to cam5 are each dropped once
        for _, target in ipairs({ "eggeizr19_geyser", M.cam5 }) do
            local seen
            sim:stallOnce(rec, function(sm, u)
                if u.tgt ~= target then return false end
                seen = seen or sm.t
                return sm.t >= seen + 3
            end)
        end
    end
    return sim, M, s, st
end

local function scenario(stall)
    local sim, M, s, st = run(stall)
    local rec = st.rec
    sim:runUntil(function() return s.cca end, 150, "the CCA convoy to reach cam6 and join")
    sim:runUntil(function() return s.nw end, 200, "the player to recover the Massachusetts survivors")
    sim:runUntil(function(sm) return sm:unit(rec).deployed end, 400, "the recycler to deploy on eggeizr19_geyser")
    sim:expect(sim:dist(rec, "eggeizr19_geyser") < 15, "the recycler stands on the geyser")
    local deployT = sim.t
    sim:runUntil(function() return #st.scavs >= 1 end, 60, "the recycler to build the second scavenger")
    sim:runUntil(function() return #st.silos >= 2 end, 200, "the constructor to build the first two silos")
    local silosT = sim.t
    sim:runUntil(function() return s.withdraw end, 900, "scrap to reach 50 (the withdraw phase)")
    local withdrawT = sim.t
    sim:runUntil(function(sm) return sm:dist(rec, M.cam5) < 200 and sm:unit(rec).cmd ~= 3 end, 600,
        "the recycler within 200 m of cam5 (Supply)")
    local rec5T = sim.t
    sim:runUntil(function(sm) return sm:dist(sm.player, M.cam5) < 300 end, 120, "the player within 300 m of cam5")
    if stall then
        local fired, total = sim:stallsFired()
        sim:expect(fired == total and total == 2, "both injected stalls fired (" .. fired .. "/" .. total .. ")")
    end
    sim:expect(not sim.failed, "the branch did not fail the mission")
    return sim, st.ccaAt, st.nwAt, deployT, silosT, withdrawT, rec5T
end

for _, stall in ipairs({ false, true }) do
    local sim, ccaT, nwT, deployT, silosT, withdrawT, rec5T = scenario(stall)
    print(string.format("misn15 PilotSim OK%s: convoy joined t=%.0f s, rescue t=%.0f s, recycler deployed t=%.0f s, silos t=%.0f s, withdraw (50 scrap) t=%.0f s, recycler at Supply t=%.0f s, script %s",
        stall and " (stall injected: geyser Goto + withdraw Goto dropped once)" or "", ccaT, nwT, deployT, silosT, withdrawT, rec5T, sim.scriptPath))
end

-- The 75-scrap win condition is reachable: the branch builds a third silo (recycler 30 + 3 x 20 = 90 capacity).
do
    local sim, M, s, st = run(false)
    sim:runUntil(function() return s.withdraw end, 900, "the withdraw phase")
    sim:runUntil(function(sm) return sm.scrap[1] >= 75 end, 1500,
        "75 team-1 scrap (capacity " .. sim.maxScrap .. ": recycler 30 + " .. #st.silos .. " silos)")
    sim:expect(#st.silos == 3, "three silos were built (" .. #st.silos .. ")")
    print(string.format("misn15 PilotSim OK: 75 scrap reached t=%.0f s with capacity %d (recycler 30 + %d silos)", sim.t, sim.maxScrap, #st.silos))
end
