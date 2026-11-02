-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/chmisn08cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/Test-Chmisn08Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Chmisn08Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local function extrasFor(n) return math.min(math.floor(n / 2), 2) end
local function setup(n, options)
    options = options or {}
    local w = F.reset()
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    local m = p[1].env.Save()
    return w, p, m
end
-- Cloak/Decloak/SetPerceivedTeam/MakeExplosion are presentation ops: every peer legitimately applies them to
-- its own copy (Docs/CHMISN08_COOP.md), so they are not checked here.
local function guestsPassive(p)
    for i = 2, #p do
        for _, name in ipairs({"BuildObject", "SetScrap", "SetAIP", "Goto", "Attack", "Defend2", "SetPilot"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end

-- ------------------------------------------------------------------ timeline helpers (verified against the real body)
-- Triggers the opening cut-scene and drives the mission to MS_WAITFORSCAP (all five APCs built).
local function toConvoy(w, m)
    F.nearTo("west_1_1", "cut_trigger", 0, 0)
    F.run(1)  -- MS_CAMERATRIGGER (stateTimer = +22)
    F.run(23) -- -> MS_SPAWNAPC1 (stateTimer = +30)
    F.run(31) -- apc[0] + 2 escorts built -> MS_SPAWNAPC2 (+5 each)
    F.run(24) -- apc[1..4] built across MS_SPAWNAPC2..5 -> MS_WAITFORSCAP
    check(m.missionState == 10, "the convoy is built and the mission waits for capture")
    for i = 0, 4 do check(m.apc[i] ~= nil, "apc[" .. i .. "] exists") end
end
-- All five APCs move together (CheckAPCs' formation/ConvoyBroken gates compare apc[3] and apc[4]; moving the
-- whole convoy as one group is a fixture simplification -- the body does not simulate convoy spacing itself).
local function moveConvoy(m, target, dx, dz)
    for i = 0, 4 do if m.apc[i] then F.nearTo(m.apc[i], target, dx or 0, dz or 0) end end
end
-- Boards peer onto APC #5, drives the convoy to the "Base" nav and to trigger_1: MS_WAITFORSCAP -> MS_WAITFORJUMPOUT.
local function capture(w, m, peer)
    F.board(peer, m.apc[4])
    moveConvoy(m, "nav")
    F.run(1) -- capture: MS_WAITSTARTSOUND4 (+5)
    check(m.missionState == 11, "the capture beat fires for the APC-5 driver")
    F.run(6) -- ch08004.wav, scrap 100 -> MS_WAITFORSOUND4 -> MS_TRIGGER1 (audio done instantly in the fixture)
    check(m.missionState == 15, "trigger1 reached")
    moveConvoy(m, "trigger_1")
    F.run(1) -- ch08006.wav -> MS_WAITFORJUMPOUT (stateTimer = +20)
    check(m.missionState == 16, "the jump-out window opens")
end
-- WAITFORWRECKER -> MS_BANGCAMERA -> MS_BANGCAMERA2 -> MS_TRIGGERNWNE (stateTimer = +300).
local function bang(w, m)
    F.run(21) -- WAITFORWRECKER's own 20 s -> MS_BANGCAMERA (+5)
    check(m.missionState == 18, "the bang camera starts")
    F.run(6) -- explosion, military base built -> MS_BANGCAMERA2 (+5)
    check(m.missionState == 19 or m.missionState == 21, "past the bang")
    F.run(6) -- -> MS_TRIGGERNWNE
    check(m.missionState == 21, "the fort-approach wait begins")
end
-- The fort assault: 5-minute scrap wait, the nw/ne trigger, then all four power/comm kills, then demolition.
local function assaultFort(w, m, approachHandle, trigger)
    F.run(301) -- team-2 scrap 100 at the 5-minute mark
    F.nearTo(approachHandle, trigger, 0, 0)
    F.run(1)
    check(m.missionState == 23, "the fort-approach trigger fires (" .. trigger .. ")")
end
local function destroyFort(w, m)
    F.kill("west_power"); F.kill("east_power"); F.kill("west_comm"); F.kill("east_comm")
    F.run(1)
    check(m.west_powerDead and m.east_powerDead and m.west_commDead and m.east_commDead, "all four fall")
    check(m.missionState == 27, "demolition begins")
end
local function demolition(w, m)
    F.run(41) -- MS_WRECKER10's 40 s wait
    F.run(13); F.run(12); F.run(10); F.run(14); F.run(16); F.run(16); F.run(8); F.run(9); F.run(7)
    check(m.missionState == 100, "the demolition sequence ends in victory")
end

-- ------------------------------------------------------------------ the setfenv/RealEnv sandbox restore
-- (Docs/CHMISN08_COOP.md, "the 60-upvalue limit"): after loading the wrapper over the REAL CRCCARuntime/CRCoop
-- modules, every entry point the host engine looks up by name must be a real function in the peer's global
-- table, never trapped inside the wrapper's private MissionEnv sandbox (which would make the mission invisible
-- to the engine -- a total failure, not a subtle one).
do
    local w, p, m = setup(1, {})
    for _, name in ipairs({"Start", "Update", "Save", "Load", "AddObject", "CreatePlayer", "AddPlayer",
        "DeletePlayer", "Receive"}) do
        check(type(p[1].env[name]) == "function", name .. " is a real function in the real global table")
    end
end

-- ------------------------------------------------------------------ offline == faithful (full win, 1 peer)
local function winRun(options)
    local w, p, m = setup(1, options)
    toConvoy(w, m)
    capture(w, m, p[1])
    F.board(p[1], p[1].player) -- jump out well inside the 20 s window
    F.run(1)
    bang(w, m)
    assaultFort(w, m, p[1].player, "nw_trigger")
    destroyFort(w, m)
    demolition(w, m)
    local lines = {}
    for _, c in ipairs(p[1].calls) do
        if c[1] == "AudioMessage" or c[1] == "Play" or c[1] == "Queue" then lines[#lines + 1] = c[2] end
    end
    local results = {}
    for _, name in ipairs({"SucceedMission", "FailMission"}) do
        for _, c in ipairs(F.callsOf(p[1], name)) do results[#results + 1] = name .. ":" .. tostring(c[3]) end
    end
    return table.concat(lines, ","), table.concat(results, ","), m, p[1]
end
do
    local faithfulLines, faithfulResults = winRun({faithful = true})
    local coopLines, coopResults, m, p1 = winRun({})
    check(faithfulResults == "SucceedMission:ch08win.des", "the faithful port wins: " .. faithfulResults)
    check(coopResults == faithfulResults, "offline CR == faithful result: " .. coopResults)
    check(coopLines == faithfulLines, "offline CR plays the faithful lines: " .. coopLines .. " vs " .. faithfulLines)
    check(coopLines:find("ch08001.wav", 1, true) and coopLines:find("ch08009.wav", 1, true), "opening and win lines")
    check(m.coopWon, "coopWon latches")
end

-- ------------------------------------------------------------------ nothing is built on the authored enemy team 2
do
    local w, p, m = setup(2, {})
    toConvoy(w, m)
    for _, b in ipairs(F.builds(p[1])) do check(b.team ~= 2, "no unit is built on the authored enemy team 2: " .. b.odf) end
    capture(w, m, p[1])
    for _, b in ipairs(F.builds(p[1])) do check(b.team ~= 2, "still team 5 after capture: " .. b.odf) end
    guestsPassive(p)
end

-- ------------------------------------------------------------------ the convoy and its escorts stay direct, real handles
for n = 1, 4 do
    local w, p, m = setup(n, {})
    toConvoy(w, m)
    local apcs, escorts = 0, 0
    for _, b in ipairs(F.builds(p[1])) do
        if b.odf == "svapc" then apcs = apcs + 1; check(b.h:sub(1, 5) == "built", "a real handle, not a ticket") end
        if b.odf == "svfigh" and b.where == "apc_escort" then escorts = escorts + 1 end
    end
    check(apcs == 5 and escorts == 2, "exactly five APCs and two escorts regardless of " .. n .. " humans (got " .. apcs .. "/" .. escorts .. ")")
end

-- ------------------------------------------------------------------ reinforcement waves scale with human count
-- and GetNearestUnitOnTeam checks every human team, not just team 1 (the last human is on team n, not team 1).
for n = 1, 4 do
    local w, p, m = setup(n, {})
    F.nearTo(p[n].player, "spawn_2", 50, 0)
    F.run(1)
    check(m.spawn_2, "the trigger fires for a human on team " .. n)
    -- Concealed arrival: a ticket waits while a human is within 460 m of its own wave path (same no-pop-in
    -- rule every CR mission's scaling uses); the player moving on to the fort lets it resolve.
    F.nearTo(p[n].player, "military_path", 0, 0)
    F.run(5)
    local svfigh, svtank = 0, 0
    for _, c in ipairs(F.builds(p[1])) do
        if c.odf == "svfigh" then svfigh = svfigh + 1 end
        if c.odf == "svtank" then svtank = svtank + 1 end
    end
    check(svfigh == 3 + extrasFor(n), "wave_2 svfigh x" .. (3 + extrasFor(n)) .. " with " .. n .. " humans (got " .. svfigh .. ")")
    check(svtank == 5, "wave_2 svtank is not scaled past its own authored count (got " .. svtank .. ")")
    guestsPassive(p)
end

-- ------------------------------------------------------------------ M.user: humans as whoever captures APC #5
-- a human driving a different vehicle never triggers the capture beat, even parked at the "Base" nav
do
    local w, p, m = setup(2, {})
    toConvoy(w, m)
    moveConvoy(m, "nav")
    F.run(1)
    check(m.missionState == 10, "nobody has boarded apc[4]: no capture")
    -- peer 2's own craft at the nav does nothing either: only the apc[4] driver's distance counts
    F.nearTo(p[2].player, "nav", 0, 0)
    F.run(1)
    check(m.missionState == 10, "a human who isn't driving apc[4] never triggers the capture beat")
end
-- boarding, driving to the capture point, and the 20 s jump-out window (stay in -> fail)
do
    local w, p, m = setup(2, {})
    toConvoy(w, m)
    capture(w, m, p[2]) -- peer 2 (not the host) is the one who captured it
    F.run(19)
    check(m.missionState == 16, "still inside the 20 s window")
    F.run(2)
    check(m.missionState == 100, "staying inside APC #5 past the window fails")
    for i, q in ipairs(p) do
        check(F.count(q, "FailMission") == 1 and F.last(q, "FailMission")[3] == "ch08lseg.des", "shared defeat on peer " .. i)
    end
end
-- jumping out in time: the sticky driver (peer 2) is perceived as the Soviet side (5) on every peer, re-boarding fails
do
    local w, p, m = setup(3, {})
    toConvoy(w, m)
    capture(w, m, p[2])
    F.board(p[2], p[2].player) -- jump out with time to spare
    F.run(1)
    check(m.missionState == 17, "the jump-out is accepted")
    for i, q in ipairs(p) do check(F.perceived(p[2].player) == 5, "every peer perceives the driver as the Soviet side") end
    -- another human near the fort triggers (sticky-by-peer-identity: it stays peer 2, resolved to their CURRENT craft)
    F.nearTo(p[1].player, "nw_trigger", 0, 0)
    F.run(1)
    check(m.missionState == 17, "a different human near the fort trigger does nothing: the driver is still peer 2")
    -- re-boarding apc[4] during the wrecker wait fails immediately
    F.board(p[2], m.apc[4])
    F.run(1)
    check(m.missionState == 100, "re-entering apc[4] after jumping out fails")
    check(F.last(p[1], "FailMission")[3] == "ch08lseg.des", "the same re-entry failure")
end
-- sticky driver: the fort-approach trigger and the howitzer objective both still key off the SAME human
-- after they dismount (this is the fix for the "M.user goes nil forever" gap)
do
    local w, p, m = setup(2, {})
    toConvoy(w, m)
    capture(w, m, p[1])
    F.board(p[1], p[1].player)
    F.run(1)
    bang(w, m)
    -- a different human standing at the trigger does nothing; the sticky driver (peer 1) must be the one there
    F.nearTo(p[2].player, "nw_trigger", 0, 0)
    F.run(301)
    check(m.missionState == 21, "a non-driver human at the trigger never fires the fort approach")
    F.nearTo(p[1].player, "nw_trigger", 0, 0)
    F.run(1)
    check(m.missionState == 23, "the sticky driver's own current craft (on foot) still fires it")
    check(m.howitzerobjectiveon, "the howitzer marker is set")
    -- IsUser(howitzer_nw) clears the marker once the sticky driver (not anyone else) captures/drives it
    F.board(p[2], m.howitzer_nw)
    F.run(1)
    check(m.howitzerobjectiveon, "a non-driver boarding the howitzer does not clear the marker")
    F.board(p[2], p[2].player) -- undo: peer 2 is not the sticky driver and must not affect M.user at all
    F.board(p[1], m.howitzer_nw)
    F.run(1)
    check(not m.howitzerobjectiveon, "the sticky driver boarding it clears the marker")
end

-- ------------------------------------------------------------------ CheckAPCs: losing any APC fails
do
    local w, p, m = setup(2, {})
    toConvoy(w, m)
    F.kill(m.apc[0])
    F.run(1)
    check(m.missionState == 100, "losing apc[0] fails the mission")
    check(F.last(p[1], "FailMission")[3] == "ch08lsed.des", "the APC-lost debrief")
end
-- the convoy breaking off early (apc[4] at trigger_1 while apc[3] is far from apc_fail) fails
do
    local w, p, m = setup(1, {})
    toConvoy(w, m)
    F.board(p[1], m.apc[4])
    F.nearTo(m.apc[4], "trigger_1", 0, 0) -- only apc[4] moves: the rest of the convoy is left behind
    F.run(1)
    check(m.missionState == 100, "breaking off the convoy early fails")
    check(F.last(p[1], "FailMission")[3] == "ch08lsec.des", "the convoy-break debrief")
    check(F.heard(p[1], "ch08005.wav"), "the straggler warning plays")
end

-- ------------------------------------------------------------------ the cockpit timer: losing the fort window fails
do
    local w, p, m = setup(1, {})
    w.realTimer = true
    toConvoy(w, m)
    capture(w, m, p[1])
    F.board(p[1], p[1].player)
    F.run(1)
    bang(w, m)
    assaultFort(w, m, p[1].player, "nw_trigger")
    F.kill("west_power")
    F.run(1)
    check(m.west_powerDead, "the clock starts on the first plant")
    F.run(60 * 4.6) -- past the 4.5-minute cockpit timer, the rest of the fort left standing
    check(m.missionState == 100, "the cockpit timer expiring fails the mission")
    check(F.last(p[1], "FailMission")[3] == "ch08lsef.des", "the timer-expiry debrief")
end

-- ------------------------------------------------------------------ out of lives: the runtime, not the body, fails
do
    local w, p, m = setup(2, {})
    toConvoy(w, m)
    p[1].coop.ReportOutOfLives()
    F.run(8) -- EndMission's network retry/flush delay
    check(m.coopFailed and not m.coopWon, "the runtime fails the mission, not the faithful body")
    for i, q in ipairs(p) do
        check(F.count(q, "FailMission") == 1 and F.last(q, "FailMission")[3] == "ch08lsea.des", "the shared runtime debrief on peer " .. i)
    end
end

-- ------------------------------------------------------------------ saves: a load never replays a build, a camera or a line
local function copy(t, seen)
    if type(t) ~= "table" then return t end
    seen = seen or {}
    if seen[t] then return seen[t] end
    local out = {}
    seen[t] = out
    for k, v in pairs(t) do out[copy(k, seen)] = copy(v, seen) end
    return out
end
-- mid convoy spawn (apc[0] and apc[1] already built, the rest still pending)
do
    local w, p, m = setup(1, {})
    F.nearTo("west_1_1", "cut_trigger", 0, 0)
    F.run(1); F.run(23); F.run(31); F.run(6) -- apc[0] built, apc[1] just built (MS_SPAWNAPC3)
    check(m.apc[0] ~= nil and m.apc[1] ~= nil and m.apc[2] == nil, "exactly two APCs exist so far")
    local apcCount = #F.builds(p[1], 0, "svapc")
    local saved = copy(p[1].env.Save())
    p[1].env.Load(saved)
    F.run(17) -- past the remaining three 5 s waits for apc[2..4]
    local after = #F.builds(p[1], 0, "svapc")
    check(after == 5, "the remaining APCs still arrive after a load (got " .. after .. ")")
    check(apcCount == 2, "nothing was built twice by the load itself")
end
-- mid capture (inside the jump-out window)
do
    local w, p, m = setup(2, {})
    toConvoy(w, m)
    capture(w, m, p[2])
    local heard6 = F.heardCount(p[2], "ch08006.wav")
    local saved = copy(p[1].env.Save())
    p[1].env.Load(saved)
    m = saved -- Load(state) replaces the body's own M with this table; follow the live reference, like Save()'s caller must
    local saved2 = copy(p[2].env.Save())
    p[2].env.Load(saved2)
    F.run(1)
    check(m.missionState == 16, "the load keeps the jump-out window open")
    check(F.heardCount(p[2], "ch08006.wav") == heard6, "the trigger line is not replayed by the load")
    F.board(p[2], p[2].player)
    F.run(1)
    check(m.missionState == 17, "the mission still progresses normally after the load")
end
-- during the demolition sequence (a few stages in)
do
    local w, p, m = setup(1, {})
    toConvoy(w, m)
    capture(w, m, p[1])
    F.board(p[1], p[1].player)
    F.run(1)
    bang(w, m)
    assaultFort(w, m, p[1].player, "ne_trigger")
    destroyFort(w, m)
    F.run(41) -- MS_WRECKER22 reached (day_1/day_1a already exploded)
    check(m.missionState == 28, "mid-demolition")
    local booms = F.count(p[1], "MakeExplosion")
    local saved = copy(p[1].env.Save())
    p[1].env.Load(saved)
    m = saved -- Load(state) replaces the body's own M with this table
    F.run(0.1)
    check(F.count(p[1], "MakeExplosion") == booms, "the load does not repeat an already-played demolition blast")
    demolition(w, m)
end

-- ------------------------------------------------------------------ weather beats (this map's sites DO have vents)
do
    local w, p, m = setup(1, {})
    toConvoy(w, m)
    local raised = {}
    for _, c in ipairs(p[1].weatherCalls) do if c[1] == "SetTargetLevel" then raised[#raised + 1] = c[2] end end
    check(raised[1] == 2, "the convoy rolling out stirs the ice (level 2)")
    capture(w, m, p[1])
    F.board(p[1], p[1].player)
    F.run(1)
    bang(w, m)
    local quaked = false
    for _, c in ipairs(p[1].weatherCalls) do if c[1] == "Quake" then quaked = true end end
    check(quaked, "the bang shakes the ice")
    assaultFort(w, m, p[1].player, "nw_trigger")
    destroyFort(w, m)
    local surged, plumed = false, false
    for _, c in ipairs(p[1].weatherCalls) do
        if c[1] == "Surge" then surged = true end
        if c[1] == "TriggerPlume" then plumed = true end
    end
    check(surged, "a fallen plant/tower starts the radiation surge")
    check(plumed, "this map's generated sites have vents, so the plume beat fires (unlike chmisn07's empty list)")
    demolition(w, m)
    local calmed = false
    for _, c in ipairs(p[1].weatherCalls) do if c[1] == "ReleaseForcedLevel" then calmed = true end end
    check(calmed, "victory eases the sky back")
end
-- a loss (without a win) leaves the ice restless instead
do
    local w, p, m = setup(1, {})
    toConvoy(w, m)
    F.kill(m.apc[0])
    F.run(1)
    check(m.missionState == 100 and not m.coopWon, "a defeat, not a victory")
    local raisedTo4 = false
    for _, c in ipairs(p[1].weatherCalls) do if c[1] == "SetTargetLevel" and c[2] == 4 then raisedTo4 = true end end
    check(raisedTo4, "a loss without a win intensifies the weather instead of calming it")
end

print("chmisn08 co-op: " .. checks .. " checks passed")
