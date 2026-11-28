-- Win-path simulation for CRMisn16's N64 Pilot Mode branch (Missions/misn16.bzn). The win (CRMisn16.lua
-- ~877: the alien HQ and hangar destroyed, then the evacuation film) is the player's job, but the
-- player can only win while the CR base he fights from stands. The AI duties the pilot block performs:
--   * the recycler and the factory drive to eggeizr112 / eggeizr113 and deploy (Goto + 6 s Resend),
--   * the recycler builds two scavengers, the factory builds four tanks that follow the player,
--   * the constructor rebuilds the 11-item base table from scratch (Build, then Dropoff next update)
--     with every build affordable,
--   * the armory is removed at the start of the mission.
-- Stalls: the recycler's and the factory's geyser Goto (sim:stallOnce) and one tank's Follow, dropped
-- once mid-flight (scenario-local; the 30 s regroup must bring it back).
-- Scenario assumptions, UNVERIFIED against the engine: start scrap 50 (SetScrap, ~720); start pilots 10
-- (the script never sets team 1's pilots).
-- Run from the repo root:
--   lua5.1 Tools/MissionTests/Test-Misn16PilotSim.lua
-- PILOTSIM_PROBE=1 also runs a zero-pilot start (informational, never fatal).
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")
local CMD = PilotSim.AiCommand

local PRELUDE = table.concat({
    "local function Valid(h) return h ~= nil and h ~= 0 and IsValid(h) end",
    "local function Alive(h) return Valid(h) and IsAlive(h) end",
    "local function IsOdfBase(h, n) return Valid(h) and IsOdf(h, n) end",
    "local function State() return M.cr end",
    "local function Failure() M.lost = true; FailMission() end",
}, "\n") .. "\n"

local function scenario(stall, pilots)
    local sim = PilotSim.new{ name = "misn16" .. (stall and "+stall" or ""), script = "Scripts/CRMisn16.lua",
        bzn = "Missions/misn16.bzn",
        pattern = "%-%- CR pilot mode >>\n(.-)\n%-%- CR pilot mode <<",
        transform = function(s) return (s:gsub("%-%- CR pilot mode >>\n", function() return "-- CR pilot mode >>\n" .. PRELUDE end, 1)) end,
        exports = "update = PilotUpdate, add = PilotAddObject",
        scrap = 50, pilots = pilots or 10 }
    local M, env = sim.M, sim.env
    env.AddScrap = function(_, n) sim.scrap[1] = math.min(sim.maxScrap, sim.scrap[1] + n) end
    env.AddPilot = function(_, n) sim.pilots[1] = sim.pilots[1] + n end
    env.RemoveObject = function(h) sim:unit(h).alive = false end
    M.cr, M.start_done = { started = 0 }, true
    M.recy, M.muf = "avrecy0_recycler", "avmuf26_factory"
    local rec, fac = M.recy, M.muf
    sim:hook(function(h) return sim.api.add(h) end)
    sim:track("rec", rec); sim:track("fac", fac); sim:track("cons", "avcnst0_constructionrig"); sim:track("player", sim.player)
    local st = { scavs = {}, tanks = {}, built = {} }
    sim.onSpawn = function(h)
        local o = sim:unit(h)
        if o.odf == "avscav" then st.scavs[#st.scavs + 1] = h end
        if o.odf == "avtank" then st.tanks[#st.tanks + 1] = h end
        if o.odf:match("^ab") then st.built[#st.built + 1] = h end
    end
    if stall then
        sim:stallOnce(rec, function(s) return s.t > 1 end)
        sim:stallOnce(fac, function(s) return s.t > 1 end)
    end
    -- After the four tanks stand the player flies to the alien HQ nav (apcamr11); tank 1's Follow is
    -- dropped once on the way (stall run).
    local flying, dropped = false, false
    sim:each(function(s)
        if not flying then return end
        local p = s:unit(s.player)
        local gx, gz = s:pos("apcamr11_camerapod")
        local dx, dz = gx - p.x, gz - p.z
        local d = math.sqrt(dx * dx + dz * dz)
        if d > 40 then local k = math.min(p.speed * s.dt, d - 40) / d; p.x, p.z = p.x + dx * k, p.z + dz * k end
        local t1 = s:unit(st.tanks[1])
        if stall and not dropped and t1.cmd == CMD.FOLLOW and d < 600 then
            dropped = true; t1.cmd, t1.tgt = CMD.NONE, nil; s:say("STALL injected: tank 1 drops its follow")
        end
    end)

    sim:runUntil(function(s) return s:unit(rec).deployed and s:unit(fac).deployed end, 120, "the recycler and factory to deploy")
    sim:expect(sim:dist(rec, "eggeizr112_geyser") < 15 and sim:dist(fac, "eggeizr113_geyser") < 15, "both stand on their geysers")
    sim:expect(not sim:unit("avslf0_armory").alive, "the armory was removed at the start")
    local deployT = sim.t
    sim:runUntil(function() return #st.scavs >= 2 end, 60, "the recycler to build two scavengers")
    sim:runUntil(function() return #st.tanks >= 4 end, 300, "the factory to build four tanks")
    local tanksT = sim.t
    for i, h in ipairs(st.tanks) do
        sim:expect(sim:unit(h).cmd == CMD.FOLLOW and sim:unit(h).tgt == sim.player, "tank " .. i .. " follows the player")
    end
    flying = true
    sim:runUntil(function(s)
        if s:dist(s.player, "apcamr11_camerapod") > 60 then return false end
        for _, h in ipairs(st.tanks) do if s:dist(h, s.player) > 100 then return false end end
        return true
    end, 300, "the player at the HQ nav with all four tanks within 100 m")
    local flyT = sim.t
    sim:runUntil(function() return #st.built >= 11 end, 900, "the constructor to rebuild all 11 base facilities")
    local baseT = sim.t
    sim:expect(sim.refused == 0, "no build order was refused for lack of scrap (refused " .. sim.refused .. ")")
    sim:runFor(5)
    local placed = 0
    for _, h in ipairs(st.built) do if sim:unit(h).alive then placed = placed + 1 end end
    sim:expect(placed == 11, "11 facilities stand (" .. placed .. ")")
    if stall then
        local fired, total = sim:stallsFired()
        sim:expect(fired == total and total == 2 and dropped, "all injected stalls fired (" .. fired .. "/" .. total .. ", follow dropped=" .. tostring(dropped) .. ")")
    end
    sim:expect(not sim.failed and not M.lost, "the branch did not fail the mission")
    return sim, deployT, tanksT, flyT, baseT
end

for _, stall in ipairs({ false, true }) do
    local sim, deployT, tanksT, flyT, baseT = scenario(stall)
    print(string.format("misn16 PilotSim OK%s: recycler+factory deployed t=%.0f s, 4 tanks t=%.0f s, escorted to the HQ nav t=%.0f s, 11 facilities t=%.0f s, scrap earned %.1f, script %s",
        stall and " (stall injected: recycler + factory Goto and a tank Follow dropped once)" or "", deployT, tanksT, flyT, baseT, sim.income, sim.scriptPath))
end

if os.getenv("PILOTSIM_PROBE") then
    local ok, err = pcall(scenario, false, 0)
    print("probe (zero starting pilots, UNVERIFIED start): " .. (ok and "still completes" or ("GAP: " .. tostring(err):match("^[^\n]*"))))
end
