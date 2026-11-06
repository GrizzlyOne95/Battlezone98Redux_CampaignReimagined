-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/ch03cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/Test-Chmisn03Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Chmisn03Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

-- The body picks the General's APC with rand() % 6: the tests choose the slot.
local realRandom, forcedApc = math.random, 0
math.random = function(a, b)
    if a == 0 and b == 5 then return forcedApc end
    return realRandom(a, b)
end

local function extrasFor(n) return math.min(math.floor(n / 2), 2) end
local ESCORT_PATHS = { east_defend = true, north_defend = true, west_defend = true }
local ROUTE = { [0] = { exit = "east_exit", fail = "east_fail", back = "east_back", sound = "ch03003.wav" },
    { exit = "north_exit", fail = "north_fail", back = "north_back", sound = "ch03004.wav" },
    { exit = "west_exit", fail = "west_fail", back = "west_back", sound = "ch03005.wav" } }

local function setup(n, options, general)
    options = options or {}
    forcedApc = general or 0
    local w = F.reset()
    w.audioBusy = options.busy == true
    w.timerUp = options.timerUp == true
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    -- the first events (objectives, six markers, the timer) need a few passes of the stream to reach the guests
    F.connect(); F.run(3)
    return w, p, p[1].env.Save()
end
local function rearmAll() for i = 1, 6 do F.rearm("howitzer_" .. i) end end
-- All six howitzers ready: the beacon, then (next frame) the six APCs and their escorts.
-- (the runtime builds two tickets per frame: thirty escorts need a few seconds of 4 Hz test frames)
local function reachConvoy(w) rearmAll(); F.run(8) end
-- The General's APC is taken by a human of the given team.
local function capture(w, m, team)
    w.objects[m.general].team = team or 1
    F.run(1)
end
local function atTrigger(w, m) F.nearTo(m.general, "trigger_1"); F.run(6) end
local function scaled(peer, mark)
    local out = {}
    for _, b in ipairs(F.builds(peer, mark or 0)) do
        if b.odf == "svtank" or b.odf == "svfigh" or b.odf == "svhraz" then out[#out + 1] = b end
    end
    return out
end
local function at(builds, where)
    local out = {}
    for _, b in ipairs(builds) do if b.where == where then out[#out + 1] = b end end
    return out
end
local function allSafe(p, builds)
    for _, b in ipairs(builds) do
        for _, q in ipairs(p) do
            check(q.env.GetDistance(q.player, b.h) >= 250, "no scripted unit is built within 250 m of any human: " .. b.where)
        end
    end
end
local function heardAll(p, file, count)
    for i, q in ipairs(p) do check(F.heardCount(q, file) == (count or 1), "peer " .. i .. " hears " .. file .. " x" .. (count or 1)) end
end
local function guestsPassive(p)
    for i = 2, #p do
        for _, name in ipairs({"BuildObject", "SetScrap", "SetAIP", "Goto", "Attack", "Defend2", "Stop", "SetPilotClass", "SetPerceivedTeam"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on the authored enemy team 2") end
end
local function killTickets(m)
    for _, h in ipairs(m.crcca.live) do if F.alive(h) then F.kill(h) end end
end

-- ------------------------------------------------------------------ offline == faithful
local function audioOf(peer)
    local out = {}
    for _, c in ipairs(peer.calls) do
        if (c[1] == "AudioMessage" or c[1] == "Play" or c[1] == "Queue") and c[2] ~= "ch03007.wav" then out[#out + 1] = c[2] end
    end
    return table.concat(out, ",")
end
local function outcomes(options, scenario)
    local w, p, m = setup(1, options, 2)
    scenario(w, p, m)
    local out = {}
    for _, name in ipairs({"SucceedMission", "FailMission"}) do
        for _, c in ipairs(F.callsOf(p[1], name)) do out[#out + 1] = name .. ":" .. tostring(c[2]) .. ":" .. tostring(c[3]) end
    end
    return table.concat(out, ","), p[1], w, audioOf(p[1])
end
local scenarios = {
    win = function(w, p, m) reachConvoy(w); capture(w, m); atTrigger(w, m); F.nearTo(m.general, "won_mission"); F.run(3) end,
    timeout = function(w, p, m) F.run(790) end,
    generalKilled = function(w, p, m) reachConvoy(w); F.kill(m.general); F.run(4) end,
    factoryLost = function(w, p, m) reachConvoy(w); F.run(485); F.kill(m.factory); F.run(4) end,
    baseFail = function(w, p, m) reachConvoy(w); F.run(125); F.nearTo(m.general, "base_fail"); F.run(4) end,
    board = function(w, p, m)
        F.board(p[1], "howitzer_1"); F.run(2)
        F.rearm("howitzer_1"); F.run(2)
        F.unboard(p[1]); F.run(3)
    end,
    bombard = function(w, p, m)
        reachConvoy(w); F.nearTo(m.apc[2], "north_exit"); F.run(25)
    end,
}
for name, scenario in pairs(scenarios) do
    local faithful, fp, _, faudio = outcomes({ faithful = true, script = "Scripts/ch03.lua" }, scenario)
    local offline, op, _, oaudio = outcomes({}, scenario)
    check(faithful == offline, "offline completes like the faithful port (" .. name .. "): " .. faithful .. " / " .. offline)
    check(faudio == oaudio, "offline plays the faithful audio (" .. name .. "): " .. faudio .. " / " .. oaudio)
    for _, call in ipairs({"SetPilotClass", "Stop", "MakeExplosion", "Goto", "Attack", "Defend2", "SetObjectiveOn", "SetObjectiveOff",
        "StartCockpitTimer", "StopCockpitTimer", "SetScrap", "AddScrap"}) do
        check(F.count(fp, call) == F.count(op, call) or (call == "Attack" or call == "Defend2" or call == "Goto"),
            "offline makes the faithful " .. call .. " calls (" .. name .. "): " .. F.count(fp, call) .. " / " .. F.count(op, call))
    end
end
do
    local out, peer = outcomes({}, scenarios.win)
    check(out:match("^SucceedMission:[%d%.]+:ch03win%.des$") and F.count(peer, "SucceedMission") == 1, "offline victory: " .. out)
    check(outcomes({}, scenarios.timeout):match("^FailMission:[%d%.]+:ch03lsea%.des$"), "offline: the rearming time ran out")
    check(outcomes({}, scenarios.generalKilled):match("ch03lsec%.des"), "offline: the General's APC destroyed")
    check(outcomes({}, scenarios.factoryLost):match("ch03lsee%.des"), "offline: the factory destroyed")
    check(outcomes({}, scenarios.baseFail):match("ch03lsed%.des"), "offline: the General is taken back to the Soviet base")
    noEnemyTeamTwo(peer)
    -- the restored rebuke plays before the timeout debrief
    local w, p, m = setup(1, { busy = true })
    F.run(790)
    check(F.heardCount(p[1], "ch03007.wav") == 1 and F.count(p[1], "FailMission") == 0, "the timeout rebuke plays first, the debrief waits for it")
    w.audioBusy = false; F.run(2)
    check(F.count(p[1], "FailMission") == 1 and F.last(p[1], "FailMission")[3] == "ch03lsea.des", "...and the debrief follows")
end
do -- offline the layer adds nothing visible
    local w, p, m = setup(1, {})
    check(F.count(p[1], "SetAIControl", 5) == 1 and F.count(p[1], "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
    check(F.index(p[1], "SetAIControl") <= p[1].chunkCalls, "SetAIControl runs at chunk root, before Start")
    check(F.count(p[1], "SetPerceivedTeam", "howitzer_1") == 1 and F.callsOf(p[1], "SetPerceivedTeam")[1][3] == 5, "howitzers are perceived as the Soviets (team 5)")
end

-- ------------------------------------------------------------------ teams, ownership, the opening
for n = 2, 4 do
    local w, p, m = setup(n, {})
    check(m.startDone and m.coopMissionStarted, "leader starts the shared mission")
    check(m.user ~= nil, "the body has a player token")
    check(F.count(p[1], "SetAIControl", 5) == 1 and F.count(p[1], "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
    check(F.count(p[1], "SetAIP") == 0, "this mission has no AIP")
    check(F.count(p[1], "SetScrap") == 1 and F.last(p[1], "SetScrap")[2] == 1 and F.last(p[1], "SetScrap")[3] == 0 + 10 * (n - 1),
        "shared scrap on team 1 with the guest bonus")
    check(F.count(p[1], "SetPilot") == n, "pilots set for every human team")
    for i = 1, n do
        check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
        local o = F.callsOf(p[i], "AddObjective")
        check(o[1] and o[1][2] == "ch03001.otf" and o[1][3] == "white", "first objective on peer " .. i)
        check(F.count(p[i], "StartCockpitTimer") == 1 and F.last(p[i], "StartCockpitTimer")[2] == 780, "the 13 minute timer on peer " .. i)
        for k = 1, 6 do check(F.count(p[i], "SetObjectiveOn", "howitzer_" .. k) == 1, "howitzer " .. k .. " marked on peer " .. i) end
    end
    check(p[1].rally and p[1].rally[0] == "won_mission", "respawn rally point is the starting base")
    for _, c in ipairs(F.callsOf(p[1], "SetPerceivedTeam")) do check(c[3] == 5, "howitzers are perceived as the Soviets (5)") end
    F.run(2)
    heardAll(p, "ch03001.wav")
    guestsPassive(p)
end

-- ------------------------------------------------------------------ the timer is the host's own clock
do
    local w, p, m = setup(3, { timerUp = true })
    F.run(700)
    check(F.count(p[1], "FailMission") == 0 and not m.lost, "before 13 minutes nothing fails (the engine clock counts up)")
    F.run(90)
    heardAll(p, "ch03007.wav")
    F.run(3)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "ch03lsea.des", "timeout debrief on peer " .. i)
        check(F.count(p[i], "SucceedMission") == 0, "no victory after a loss")
    end
end
do -- a rearmed set stops the clock for everyone and the timeout can no longer happen
    local w, p, m = setup(3, { timerUp = true })
    reachConvoy(w)
    for i = 1, 3 do
        check(F.count(p[i], "StopCockpitTimer") == 1 and F.count(p[i], "HideCockpitTimer") >= 1, "the timer stops on peer " .. i)
    end
    F.run(800)
    check(F.count(p[1], "FailMission") == 0, "the timeout never fires after the rearming")
end

-- ------------------------------------------------------------------ any human in any howitzer
do
    local w, p, m = setup(3, {})
    F.board(p[2], "howitzer_2"); F.run(2)
    check(m.inHowitzer[1] and not m.inHowitzer[0] and not m.inHowitzer[2], "a team-2 human in howitzer 2 is noticed")
    heardAll(p, "ch03002.wav")
    F.board(p[3], "howitzer_5"); F.run(2)
    check(m.inHowitzer[4], "a team-3 human in howitzer 5 is noticed")
    heardAll(p, "ch03002.wav", 2)
    F.rearm("howitzer_2"); F.run(2)
    check(m.howitzerReady[1] and F.count(p[1], "SetObjectiveOff", "howitzer_2") == 1, "howitzer 2 is ready")
    for i = 1, 3 do check(F.count(p[i], "SetObjectiveOff", "howitzer_2") == 1, "...and unmarked on peer " .. i) end
    check(F.count(p[1], "SetPilotClass", "howitzer_2") == 0, "no AI while the human is aboard")
    F.unboard(p[2]); F.run(3)
    check(F.count(p[1], "SetPilotClass", "howitzer_2") == 1 and F.count(p[1], "Stop", "howitzer_2") == 1,
        "leaving a ready howitzer restores its AI once")
    F.run(5)
    check(F.count(p[1], "SetPilotClass", "howitzer_2") == 1, "...and never again")
    check(F.count(p[1], "SetPilotClass", "howitzer_5") == 0, "an unready howitzer keeps its human")
    F.unboard(p[3]); F.rearm("howitzer_5"); F.run(3)
    check(F.count(p[1], "SetPilotClass", "howitzer_5") == 1, "the second howitzer restores its AI")
    guestsPassive(p)
end
do -- stock bug: the AI is restored even when the last howitzer is repaired after the phase ended
    local w, p, m = setup(2, {})
    F.board(p[2], "howitzer_6"); F.run(2)
    for i = 1, 5 do F.rearm("howitzer_" .. i) end
    F.rearm("howitzer_6"); F.run(2)
    check(m.objective1Complete, "all six ready while a guest is aboard")
    F.unboard(p[2]); F.run(3)
    check(F.count(p[1], "SetPilotClass", "howitzer_6") == 1, "the last howitzer gets its AI after the phase ended")
end
do -- without the OpenShim label-id hooks a guest in an authored craft is invisible: the body pauses, nothing breaks
    local w, p, m = setup(2, { nilAuthoredHandles = true })
    F.board(p[2], "howitzer_3"); F.run(3)
    check(not m.inHowitzer[2], "an unresolvable guest handle is not counted (the session pauses, see the doc)")
    F.unboard(p[2]); F.run(3)
    check(m.coopMissionStarted, "...and the mission resumes when the guest leaves the craft")
end

-- ------------------------------------------------------------------ the convoys: scaling, no pop-in
for n = 1, 4 do
    local e = extrasFor(n)
    local w, p, m = setup(n, {}, 3)
    reachConvoy(w)
    check(m.objective1Complete and m.generalApc == 3 and m.general == m.apc[3], "the General is APC 3 (north)")
    local beacon = F.builds(p[1], 0, "apcamr")
    check(#beacon == 1 and beacon[1].team == 1 and beacon[1].where == "nav_base", n .. ": the CCA base beacon is built once on team 1")
    for i = 1, n do
        check(F.count(p[i], "SetObjectiveName", m.nav or beacon[1].h) == 1, "the beacon is named on peer " .. i)
        local rebuild = F.callsOf(p[i], "AddObjective")
        check(rebuild[#rebuild][2] == "ch03002.otf" and rebuild[#rebuild][3] == "white" and rebuild[#rebuild - 1][3] == "green",
            "objective 2 is current on peer " .. i)
    end
    local apcs = {}
    for _, b in ipairs(F.builds(p[1], 0)) do if b.odf == "svapcr" or b.odf == "svapcq" then apcs[#apcs + 1] = b end end
    check(#apcs == 6 and #F.builds(p[1], 0, "svapcq") == 1, n .. ": six APCs, one of them the General's")
    for _, b in ipairs(apcs) do check(b.team == 5, "APCs are the co-op enemy") end
    check(F.builds(p[1], 0, "svapcq")[1].h == m.general, "the General's APC is the svapcq")
    check(F.count(p[1], "SetPerceivedTeam", m.apc[0]) == 1 and F.callsOf(p[1], "SetPerceivedTeam")[7][3] == 1, "APCs are perceived as friendly")
    local escorts = scaled(p[1])
    check(#escorts == 24 + 3 * e, n .. " human(s): 24 escorts + 3 events x " .. e .. " extras, got " .. #escorts)
    for _, b in ipairs(escorts) do check(b.team == 5 and ESCORT_PATHS[b.where], "escorts are team 5 at the Soviet base") end
    allSafe(p, escorts)
    check(#F.builds(p[1], 0, "svhraz") == 6 and #F.builds(p[1], 0, "svtank") >= 12, n .. ": the escorts include six bombers")
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end
do -- a human at the Soviet base: the escorts wait for another hidden approach
    local w, p, m = setup(2, {})
    F.place(p[2].player, 2060, 97330)
    reachConvoy(w)
    local escorts = scaled(p[1])
    check(#escorts == 24 + 3, "every escort is still built")
    for _, b in ipairs(escorts) do check(b.where == "east_fail", "...from the first clear hidden approach: " .. b.where) end
    allSafe(p, escorts)
end

-- ------------------------------------------------------------------ the turn-around, the bombardment, the gas
for n = 2, 3 do
    for route = 0, 2 do
        local w, p, m = setup(n, {}, route * 2)
        reachConvoy(w)
        local r = ROUTE[route]
        F.nearTo(m.apc[2 * route + 1], r.exit, 10, 0); F.run(1)
        check(m.turnedAround[route], "route " .. route .. " turns around when one APC of the pair is close")
        heardAll(p, r.sound)
        local gotos = 0
        for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[3] == r.back then gotos = gotos + 1 end end
        check(gotos == 2, "both APCs of the pair drive back")
        local attacks = 0
        for _, c in ipairs(F.callsOf(p[1], "Attack")) do
            if c[2] == m.howitzers[2 * route] and c[3] == m.apc[2 * route] or c[2] == m.howitzers[2 * route + 1] and c[3] == m.apc[2 * route + 1] then attacks = attacks + 1 end
        end
        check(attacks == 2, "the pair of howitzers attacks the pair of APCs")
        F.run(22)
        check(F.count(p[1], "MakeExplosion") == 5, "five gas explosions on the host, got " .. F.count(p[1], "MakeExplosion"))
        for i = 2, n do check(F.count(p[i], "MakeExplosion") == 5, "...and five on guest " .. i) end
        for _, c in ipairs(F.callsOf(p[1], "MakeExplosion")) do check(c[2] == "xgasxpl" and c[3] == r.exit, "ODF first, the route's exit second") end
    end
end

-- ------------------------------------------------------------------ the General: any human team captures it
for team = 2, 4 do
    local w, p, m = setup(4, {}, 1)
    reachConvoy(w)
    check(not m.objective2Complete, "the General is Soviet at first")
    capture(w, m, team)
    check(m.objective2Complete, "a team-" .. team .. " human takes the General's APC")
    heardAll(p, "ch03006.wav")
    for i = 1, 4 do
        local o = F.callsOf(p[i], "AddObjective")
        check(o[#o][2] == "ch03003.otf" and o[#o][3] == "white", "the escort objective is current on peer " .. i)
    end
end
do -- another APC changing hands is not the General
    local w, p, m = setup(2, {}, 1)
    reachConvoy(w)
    w.objects[m.apc[0]].team = 2
    F.run(2)
    check(not m.objective2Complete, "only the General's APC counts")
end

-- ------------------------------------------------------------------ the ambush at trigger_1 (scaled, no pop-in) and the win
for n = 1, 4 do
    local e = extrasFor(n)
    local w, p, m = setup(n, {}, 0)
    reachConvoy(w); F.run(485)
    local factory = F.builds(p[1], 0, "cvmufa")
    check(#factory == 1 and factory[1].team == 1 and factory[1].where == "factory", n .. ": the factory arrives on team 1")
    check(#F.builds(p[1], 0, "cvslfa") == 1, "...with the armory")
    local scavs = F.builds(p[1], 0, "cvscav")
    check(#scavs == 4 and scavs[1].team == 1 and scavs[1].where == "factory", "the four cut scavengers are restored")
    capture(w, m, 1)
    killTickets(m) -- the escorts are dead by now (the live cap only drops extras while they are alive)
    local mark = #p[1].calls
    atTrigger(w, m)
    check(m.trigger1Done, "the General reaches trigger_1")
    local raid = scaled(p[1], mark)
    check(#raid == 15 + 3 * e, n .. " human(s): 15 raiders + 3 events x " .. e .. " extras, got " .. #raid)
    check(#at(raid, "apc_attack") == 6 + e and #at(raid, "apc_attack_2") == 4 + e and #at(raid, "factory_attack") == 5 + e, "raiders per approach")
    allSafe(p, raid)
    local attacksGeneral, attacksFactory = 0, 0
    for i = mark + 1, #p[1].calls do
        local c = p[1].calls[i]
        if c[1] == "Attack" and c[3] == m.general then attacksGeneral = attacksGeneral + 1 end
        if c[1] == "Attack" and c[3] == m.factory then attacksFactory = attacksFactory + 1 end
    end
    check(attacksGeneral == 10 + 2 * e and attacksFactory == 5 + e, "raiders attack the General and the factory: " .. attacksGeneral .. "/" .. attacksFactory)
    noEnemyTeamTwo(p[1])
    -- victory
    F.nearTo(m.general, "won_mission"); F.run(4)
    for i = 1, n do
        check(F.count(p[i], "SucceedMission") == 1 and F.count(p[i], "FailMission") == 0, "one shared victory on peer " .. i)
        check(F.last(p[i], "SucceedMission")[3] == "ch03win.des", "victory debrief on peer " .. i)
        check((p[i].env.Save().coopUnresolved or 0) == 0, "no unresolved presentation identities on peer " .. i)
    end
    local before = #F.builds(p[1])
    F.kill(m.factory); F.run(8)
    check(F.count(p[1], "FailMission") == 0 and #F.builds(p[1]) == before, "a won mission cannot be lost and builds nothing more")
    guestsPassive(p)
end
do -- a human within 250 m of an authored approach: the raid comes from the next hidden one
    local w, p, m = setup(3, {}, 0)
    reachConvoy(w); F.run(485)
    capture(w, m, 1)
    F.place(p[2].player, 3800, 99300)
    F.nearTo(m.general, "trigger_1"); F.run(2)
    local raid = scaled(p[1], 0)
    local fromAuthored = at(raid, "apc_attack")
    check(#fromAuthored == 0, "nothing is built at the watched approach")
    check(#at(raid, "east_fail") >= 6, "...the raiders come from the map edge instead")
    allSafe(p, raid)
end

-- ------------------------------------------------------------------ defeats
do -- the General's APC destroyed
    local w, p, m = setup(3, {}, 4)
    reachConvoy(w)
    F.kill(m.general); F.run(3)
    heardAll(p, "ch03008.wav")
    F.run(6)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "ch03lsec.des", "one shared failure on peer " .. i)
        check(F.count(p[i], "SucceedMission") == 0, "no victory after a loss")
    end
    local before = #F.builds(p[1])
    F.run(10)
    check(#F.builds(p[1]) == before, "no reinforcement is built after the failure")
end
do -- the factory destroyed
    local w, p, m = setup(2, {}, 0)
    reachConvoy(w); F.run(485)
    F.kill(m.factory); F.run(4)
    for i = 1, 2 do check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "ch03lsee.des", "factory loss on peer " .. i) end
end
do -- taken back to the Soviet base
    local w, p, m = setup(2, {}, 0)
    reachConvoy(w)
    F.nearTo(m.general, "base_fail"); F.run(3)
    check(F.count(p[1], "FailMission") == 0, "the 120 s grace period holds")
    F.run(125); F.nearTo(m.general, "base_fail"); F.run(3)
    heardAll(p, "ch03009.wav")
    F.run(3)
    for i = 1, 2 do check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "ch03lsed.des", "base loss on peer " .. i) end
end
for route = 0, 2 do -- restored: the General's APC drives off the map edge
    local w, p, m = setup(2, {}, route * 2 + 1)
    reachConvoy(w)
    F.nearTo(m.general, ROUTE[route].fail, 20, 0); F.run(2)
    check(m.lost, "route " .. route .. ": the General escapes at the end of his route")
    heardAll(p, "ch03007.wav")
    F.run(3)
    for i = 1, 2 do check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "ch03lseb.des", "escape debrief on peer " .. i) end
end
do -- a captured General at the map edge is not an escape; and a won mission is never lost to it
    local w, p, m = setup(2, {}, 0)
    reachConvoy(w); capture(w, m, 2)
    F.nearTo(m.general, "east_fail"); F.run(3)
    check(not m.lost and F.count(p[1], "FailMission") == 0, "our own General at the edge is not an escape")
end

-- ------------------------------------------------------------------ save / load
do
    local w, p, m = setup(3, { timerUp = true })
    F.board(p[2], "howitzer_1"); F.run(2)
    F.run(300)
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "StartCockpitTimer") == 2, "a load shows the remaining time again")
    local left = F.last(p[1], "StartCockpitTimer")[2]
    check(left > 470 and left < 480, "...from the host's own clock: " .. left)
    for k = 1, 6 do check(F.count(p[1], "SetObjectiveOn", "howitzer_" .. k) == 2, "markers are shown again after a load") end
    F.run(480)
    check(F.count(p[1], "FailMission") == 1 and F.last(p[1], "FailMission")[3] == "ch03lsea.des", "the timeout still falls at the original time")
end
do
    local w, p, m = setup(2, {}, 2)
    reachConvoy(w)
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    local o = F.callsOf(p[1], "AddObjective")
    check(o[#o][2] == "ch03002.otf" and o[#o][3] == "white", "the escort-phase objectives are shown again after a load")
    check(F.count(p[1], "SetObjectiveName", m.crcca and F.builds(p[1], 0, "apcamr")[1].h) == 2, "the beacon is named again after a load")
    check(#F.builds(p[1], 0, "svapcr") + #F.builds(p[1], 0, "svapcq") == 6, "a load builds no second convoy")
end

-- ------------------------------------------------------------------ leader leaves
do
    local w, p, m = setup(3, {})
    for i = 2, 3 do p[i].env.DeletePlayer(1) end
    F.run(3)
    for i = 2, 3 do check(F.count(p[i], "FailMission") == 1, "the mission fails for guest " .. i .. " when the leader leaves") end
    check(F.count(p[1], "FailMission") == 0, "the leader itself keeps playing")
end

-- ------------------------------------------------------------------ weather: Ganymede
do
    local w, p, m = setup(3, {})
    check(F.count(p[1], "EnvironmentInit") == 0 and m.startDone, "no weather module: the mission runs and touches no Environment")
    local printed = false
    for _, c in ipairs(p[1].calls) do if c[1] == "print" and tostring(c[2]):find("weather disabled", 1, true) then printed = true end end
    check(printed, "missing weather is logged, not fatal")
end
local function europa(record, mode, vents)
    return function(peer)
        local V = { Seed = 4242 }
        function V.Init(o) peer.weatherInit = o; record("EuropaInit", o.authority, o.send ~= nil, o.seed, o.startLevel, o.targetLevel); if mode == "initfail" then error("boom") end end
        function V.Update(dt)
            if peer.weatherInit and peer.weatherInit.authority and peer.weatherInit.send and not V.sent then
                V.sent = true; peer.weatherInit.send("EuropaQuake", 3, 4)
            end
            if mode == "updatefail" then error("update boom") end
        end
        function V.AnnounceState() record("EuropaAnnounce") end
        function V.ApplyNetEvent(op, ...) record("EuropaEvent", op, ...) end
        function V.SetTargetLevel(n) record("EuropaLevel", n) end
        function V.ReleaseForcedLevel() record("EuropaRelease") end
        function V.GetVentSites() return vents end
        function V.TriggerPlume(i) record("EuropaPlume", i) end
        function V.Quake(a, b) record("EuropaQuakeCall", a, b) end
        function V.Surge(a, b) record("EuropaSurgeCall", a, b) end
        function V.OnObjectCreated(h) record("EuropaCreated", h) end
        function V.Save() return { saved = true } end
        function V.Load(s) record("EuropaLoad", s and s.saved) end
        function V.Shutdown() record("EuropaShutdown") end
        return V
    end
end
do
    local sites = dofile("Scripts/CRGanymedeSitesCH03.lua")
    check(sites.mission == "chmisn03" and #sites.vents == 4 and sites.vents[1].label == "eggeizr17_geyser", "the generated sites carry the base geysers")
    local weather = { module = function(peer, record) return europa(record, nil, sites.vents)(peer) end, sites = sites }
    local w, p, m = setup(3, { weather = weather }, 0)
    check(F.count(p[1], "EuropaInit", true) == 1 and F.last(p[1], "EuropaInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.last(p[1], "EuropaInit")[5] == 1 and F.last(p[1], "EuropaInit")[6] == 1, "the sky starts quiescent")
    check(F.count(p[2], "EuropaInit", false) == 1, "guests render only (not the authority)")
    check(F.count(p[1], "EuropaAnnounce") == 1 and F.count(p[2], "EuropaAnnounce") == 0, "the leader announces its weather state once")
    local env = F.last(p[1], "EnvironmentInit")[2]
    check(F.count(p[1], "EnvironmentInit") == 1 and env.lightingMode == "orbit", "Ganymede lighting is initialised")
    for i = 2, 3 do
        local e = F.last(p[i], "EuropaEvent")
        check(e and e[2] == "EuropaQuake" and e[3] == 3 and e[4] == 4, "weather events reach guest " .. i)
    end
    check(m.crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    check(F.count(p[1], "EuropaLevel") == 0, "calm until the story starts")
    for i = 1, 3 do F.rearm("howitzer_" .. i) end
    F.run(2)
    check(F.count(p[1], "EuropaLevel", 2) == 1, "three guns ready stir the vapour")
    check(F.count(p[1], "EuropaPlume") == 0, "no plume before the convoys")
    for i = 4, 6 do F.rearm("howitzer_" .. i) end
    F.run(2)
    check(F.count(p[1], "EuropaLevel", 3) == 1 and F.count(p[1], "EuropaPlume", 1) == 1 and F.count(p[1], "EuropaQuakeCall") == 1,
        "all six ready: a higher rung, the base vent blows, the ground shakes")
    F.nearTo(m.apc[0], "east_exit"); F.run(2)
    check(F.count(p[1], "EuropaLevel", 4) == 1 and F.count(p[1], "EuropaSurgeCall") == 1, "the first bombardment brings the surge")
    check(F.count(p[1], "EuropaCreated") > 0, "new objects are offered to the weather")
    capture(w, m, 1)
    check(F.count(p[1], "EuropaLevel", 3) == 2, "the General in hand eases the sky")
    F.run(485)
    atTrigger(w, m)
    check(F.count(p[1], "EuropaLevel", 4) == 2 and F.count(p[1], "EuropaPlume", 2) == 1 and F.count(p[1], "EuropaQuakeCall") == 2, "the ambush brings the heaviest rung and a second vent")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "EuropaShutdown") >= 1 and F.count(p[1], "EuropaLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(p[1], "EuropaPlume") == 2 and F.count(p[1], "EuropaLevel", 3) == 2, "beats are not repeated after a load")
    F.nearTo(m.general, "won_mission"); F.run(3)
    check(F.count(p[1], "EuropaRelease") == 1 and F.count(p[1], "EuropaLevel", 1) == 1, "the victory eases the sky back")
end
do -- out of lives: the runtime fails the mission and the sky still calms
    local weather = { module = function(peer, record) return europa(record, nil, {})(peer) end, sites = { mission = "chmisn03", vents = {} } }
    local w, p, m = setup(2, { weather = weather })
    reachConvoy(w)
    p[1].coop.ReportOutOfLives(); F.run(3)
    check(m.coopFailed and not m.lost, "the runtime, not the body, failed the mission")
    check(F.count(p[1], "EuropaRelease") == 1 and F.count(p[1], "EuropaLevel", 1) == 1, "an out-of-lives defeat eases the sky back")
end
do -- a site list without vents: the plume is skipped, the rest of the weather still follows
    local weather = { module = function(peer, record) return europa(record, nil, {})(peer) end, sites = { mission = "chmisn03", vents = {} } }
    local w, p, m = setup(2, { weather = weather })
    reachConvoy(w)
    check(F.count(p[1], "EuropaPlume") == 0 and F.count(p[1], "EuropaLevel", 3) == 1 and F.count(p[1], "EuropaQuakeCall") == 1,
        "no vents: no plume, the level and the quake still follow")
end
do -- sites module missing: no weather, never an error
    local w, p, m = setup(2, { weather = { module = function(peer, record) return europa(record, nil, {})(peer) end } })
    check(F.count(p[1], "EuropaInit") == 0 and m.startDone, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local weather = { module = function(peer, record) return europa(record, mode, {})(peer) end, sites = {} }
    local w, p, m = setup(2, { weather = weather }, 0)
    reachConvoy(w); capture(w, m, 1); atTrigger(w, m); F.nearTo(m.general, "won_mission"); F.run(6)
    check(F.count(p[1], "SucceedMission") == 1 and F.count(p[2], "SucceedMission") == 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

math.random = realRandom
print("chmisn03 co-op: " .. checks .. " checks passed")
