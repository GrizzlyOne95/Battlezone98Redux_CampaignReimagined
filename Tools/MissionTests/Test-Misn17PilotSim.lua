-- Win-path simulation for misn17cr's N64 Pilot Mode branch. The win (misn17cr.lua ~1309: the Fury
-- factory parts destroyed after the seven power towers) is the player's, but the pilot block must keep
-- the force that makes it winnable going. The AI duties:
--   * the recycler and the factory deploy on eggeizr1133 / eggeizr1132 (Goto + 6 s Resend),
--   * the recycler builds two scavengers and a constructor (misn17cr has none at the start), the
--     constructor rebuilds the 8-item base table (Build, then Dropoff next update),
--   * the four wingmen are re-ordered every 20 s onto the first standing Fury tower (C 438-822), so the
--     seven towers all fall (towers are killed here when an escort has been within 70 m for 5 s),
--   * a lost tank is replaced by the factory and follows the player.
-- Stalls: the recycler's and the factory's geyser Goto (sim:stallOnce) and one wingman's Attack order,
-- dropped once (scenario-local; the 20 s escort block must re-send it).
-- Model limits: towers never shoot back, the wingmen need no repair, and the player holds at the base.
-- Scenario assumptions, UNVERIFIED against the engine: start scrap 40 (SetScrap, ~754); start pilots 10.
-- Run from the repo root:
--   lua5.1 Tools/MissionTests/Test-Misn17PilotSim.lua
-- PILOTSIM_PROBE=1 also runs a zero-pilot start (informational, never fatal).
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")
local CMD = PilotSim.AiCommand

-- The mission's own helpers the block calls (misn17cr.lua ~408-418).
local PRELUDE = table.concat({
    "local function Distance(a, b) if not IsValid(a) or not IsValid(b) then return math.huge end return GetDistance(a, b) end",
    "local function NearestEnemy(f) if IsValid(f) then return GetNearestEnemy(f) end return nil end",
}, "\n") .. "\n"

local function scenario(stall, pilots)
    local sim = PilotSim.new{ name = "misn17" .. (stall and "+stall" or ""), script = "Scripts/misn17cr.lua",
        bzn = "Missions/misn17cr.bzn",
        pattern = "(local PILOT_RESERVE.-)\n%-%- CR pilot mode <<",
        transform = function(s) return (s:gsub("local PILOT_RESERVE = 4", function() return "local PILOT_RESERVE = 4\n" .. PRELUDE end, 1)) end,
        exports = "update = PilotUpdate, add = PilotAddObject",
        scrap = 40, pilots = pilots or 10 }
    local M, env = sim.M, sim.env
    env.AddScrap = function(_, n) sim.scrap[1] = math.min(sim.maxScrap, sim.scrap[1] + n) end
    env.AddPilot = function(_, n) sim.pilots[1] = sim.pilots[1] + n end
    env.GetNearestEnemy = function(h) -- nearest living team-2 combat object (the BZN co-op spawn markers are not enemies)
        local best, bd
        for _, o in ipairs(sim.order) do
            local u = sim.objs[o]
            if u.alive and u.team == 2 and not u.odf:match("^pspwn") then
                local d = sim:dist(h, o)
                if not bd or d < bd then best, bd = o, d end
            end
        end
        return best
    end
    M.missionstart, M.missionwon, M.missionfail = true, false, false
    M.avrec, M.factorynav = "avrecy18_recycler", "factorynav"
    for i = 1, 7 do
        local x, z = sim:pos("geizer" .. i)
        M["tower" .. i] = sim:add("hbptow", 2, x, z)
    end
    local rec, fac = M.avrec, "avmuf0_factory"
    local wingmen = { "avtank134_wingman", "avltnk134_wingman", "avfigh18_wingman", "avfigh19_wingman" }
    sim:hook(function(h) return sim.api.add(h) end)
    sim:track("rec", rec); sim:track("fac", fac); sim:track("player", sim.player); sim:track("tank1", wingmen[1])
    local st = { scavs = {}, tanks = {}, cnst = nil, fac = {} }
    sim.onSpawn = function(h)
        local o = sim:unit(h)
        if o.odf == "avscav" then st.scavs[#st.scavs + 1] = h end
        if o.odf == "avcnst" then st.cnst = h; sim:track("cnst", h) end
        if o.odf == "avtank" then st.tanks[#st.tanks + 1] = h end
        if o.odf:match("^ab") then st.fac[#st.fac + 1] = h end
    end
    if stall then
        sim:stallOnce(rec, function(s) return s.t > 1 end)
        sim:stallOnce(fac, function(s) return s.t > 1 end)
    end
    -- Tower deaths: an escort within 70 m of the tower for 5 s kills it. A wingman's Attack is dropped once.
    local near, dropped = {}, false
    sim:each(function(s)
        for i = 1, 7 do
            local t = M["tower" .. i]
            if sim:unit(t).alive then
                local close = false
                for _, w in ipairs(wingmen) do
                    if sim:unit(w).alive and sim:dist(w, t) < 70 then close = true end
                end
                if close then
                    near[i] = near[i] or s.t
                    if s.t - near[i] >= 5 then sim:unit(t).alive = false; sim:say("tower " .. i .. " destroyed") end
                else near[i] = nil end
            end
        end
        local w = sim:unit(wingmen[1])
        if stall and not dropped and w.cmd == CMD.ATTACK and sim:dist(wingmen[1], M.tower1) < 600 then
            dropped = true; w.cmd, w.tgt = CMD.NONE, nil; s:say("STALL injected: wingman 1 drops its attack")
        end
    end)

    sim:runUntil(function(s) return s:unit(rec).deployed and s:unit(fac).deployed end, 120, "the recycler and factory to deploy")
    sim:expect(sim:dist(rec, "eggeizr1133_geyser") < 15 and sim:dist(fac, "eggeizr1132_geyser") < 15, "both stand on their geysers")
    local deployT = sim.t
    sim:runUntil(function() return #st.scavs >= 2 end, 80, "the recycler to build two scavengers")
    sim:runUntil(function() return st.cnst ~= nil end, 120, "the recycler to build the constructor")
    sim:runUntil(function() return #st.fac >= 8 end, 900, "the constructor to rebuild all 8 base facilities")
    local baseT = sim.t
    sim:expect(sim.refused == 0, "no build order was refused for lack of scrap (refused " .. sim.refused .. ")")
    sim:runUntil(function(s)
        for i = 1, 7 do if s:unit(M["tower" .. i]).alive then return false end end
        return true
    end, 900, "the wingmen to bring down all seven towers")
    local towersT = sim.t
    if stall then sim:expect(dropped, "the wingman attack stall fired") end
    -- A lost tank is replaced and follows the player.
    local before = #st.tanks
    sim:unit(wingmen[1]).alive = false
    sim:runUntil(function() return #st.tanks > before end, 300, "the factory to replace the lost tank")
    sim:runFor(1)
    local newTank = st.tanks[#st.tanks]
    sim:expect(sim:unit(newTank).cmd == CMD.FOLLOW and sim:unit(newTank).tgt == sim.player, "the replacement tank follows the player")
    if stall then
        local fired, total = sim:stallsFired()
        sim:expect(fired == total and total == 2, "both injected Goto stalls fired (" .. fired .. "/" .. total .. ")")
    end
    sim:expect(not sim.failed and not M.missionfail, "the branch did not fail the mission")
    return sim, deployT, baseT, towersT
end

for _, stall in ipairs({ false, true }) do
    local sim, deployT, baseT, towersT = scenario(stall)
    print(string.format("misn17 PilotSim OK%s: recycler+factory deployed t=%.0f s, 8 facilities t=%.0f s, seven towers down t=%.0f s, tank replaced t=%.0f s, script %s",
        stall and " (stall injected: recycler + factory Goto and a wingman Attack dropped once)" or "", deployT, baseT, towersT, sim.t, sim.scriptPath))
end

if os.getenv("PILOTSIM_PROBE") then
    local ok, err = pcall(scenario, false, 0)
    print("probe (zero starting pilots, UNVERIFIED start): " .. (ok and "still completes" or ("GAP: " .. tostring(err):match("^[^\n]*"))))
end
