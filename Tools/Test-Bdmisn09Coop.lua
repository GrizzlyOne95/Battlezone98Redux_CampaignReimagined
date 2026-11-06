-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/bd09cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/Test-Bdmisn09Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Bdmisn09Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local function extrasFor(n) return math.min(math.floor(n / 2), 2) end
local FAITHFUL = { faithful = true, script = F.FAITHFUL }
local SCALED = { cvfigh = true, cvltnk = true, cvhtnk = true, cvrckt = true, cvtnk = true }

local function setup(n, options)
    options = options or {}
    local w = F.reset()
    w.audioBusy = options.busy == true
    w.nilAudio = options.nilAudio == true
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
local function isHuman(p, h) for _, q in ipairs(p) do if q.player == h then return true end end return false end
local function heardAll(p, file, count)
    for i, q in ipairs(p) do check(F.heardCount(q, file) == (count or 1), "peer " .. i .. " hears " .. file .. " x" .. (count or 1)) end
end
local function guestsPassive(p)
    for i = 2, #p do
        for _, name in ipairs({"BuildObject", "SetScrap", "SetAIP", "Goto", "Attack", "SetPerceivedTeam"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on the authored enemy team 2") end
end
local function allSafe(p, builds)
    for _, b in ipairs(builds) do
        for _, q in ipairs(p) do
            check(q.env.GetDistance(q.player, b.h) >= 460, "no scripted unit is built within 460 m of any human: " .. tostring(b.where))
        end
    end
end
local function perceivedAll(p, expect)
    for i, q in ipairs(p) do
        local want = expect == "own" and q.team or expect
        check(F.perceived(q.player) == want, "human " .. i .. " is perceived as " .. tostring(want) .. ", got " .. tostring(F.perceived(q.player)))
    end
end
-- The player steps out of the APC into the tracked tank (the engine hands the tank to the human's team).
local function hop(peer)
    peer.player = "cvtnk1"
    F.world().objects.cvtnk1.team = peer.team
end
local function eject(peer, x, z)
    peer.player = F.spawn("bspilo", peer.team, x or 860, z or 102000)
end
local function capture(w, p, m, who)
    F.runUntil(function() return m.sound2Played end, 60)
    hop(p[who or 1])
    F.runUntil(function() return m.objective1Complete end, 10)
end
local function moveAway(p)
    for i, q in ipairs(p) do F.place(q.player, 3000 + 40 * i, 100000) end
end

-- ------------------------------------------------------------------ offline == faithful
local function outcomes(options, scenario)
    local w, p, m = setup(1, options)
    scenario(w, p, m)
    local out = {}
    for _, name in ipairs({"SucceedMission", "FailMission"}) do
        for _, c in ipairs(F.callsOf(p[1], name)) do out[#out + 1] = name .. ":" .. tostring(c[3]) end
    end
    local audio = table.concat(F.lines(p[1]), ",")
    return table.concat(out, ","), audio, p[1], w
end
local function convoyToBeacons(w, p, m)
    -- the pack travels with the player (a human with no tank within 75 m would be straying)
    local function step(tank, beacon)
        F.nearTo(tank, beacon, 10, 0); F.nearTo("cvtnk4", beacon, 30, 0); F.nearTo(p[1].player, beacon, 20, 0); F.run(1)
    end
    F.run(8)
    step("cvtnk2", m.beacon1)
    step("cvtnk3", m.beacon2); F.run(6)
    step("cvtnk5", m.beacon3)
end
local scenarios = {
    win = function(w, p, m)
        capture(w, p, m); convoyToBeacons(w, p, m)
        F.nearTo("cvtnk4", "portal", 150, 0); F.nearTo(p[1].player, "portal", 100, 0); F.run(1)
        F.touch(p[1].player, "portal"); F.run(4)
    end,
    timeout = function(w, p, m)
        capture(w, p, m); F.run(8)
        eject(p[1]); F.run(605)
    end,
    portallost = function(w, p, m)
        capture(w, p, m); F.run(3); F.kill("portal"); F.run(4)
    end,
    ambush = function(w, p, m)
        F.run(2); eject(p[1]); F.run(8)
        F.nearTo(p[1].player, "trigger_1", 50, 0); F.run(3)
    end,
}
for name, scenario in pairs(scenarios) do
    local faithful, faudio = outcomes(FAITHFUL, scenario)
    local offline, oaudio = outcomes({}, scenario)
    check(faithful == offline, "offline completes like the faithful port (" .. name .. "): " .. faithful .. " / " .. offline)
    check(faudio == oaudio, "offline plays the faithful audio sequence (" .. name .. "): " .. faudio .. " / " .. oaudio)
end
do
    local win, audio = outcomes({}, scenarios.win)
    check(win == "SucceedMission:bd09win.des", "offline victory: " .. win)
    local expected = {}
    for _, n in ipairs({1, 2, 3, 4, 5, 6, 8}) do expected[#expected + 1] = "bd0900" .. n .. ".wav" end
    check(audio == table.concat(expected, ","), "the whole briefing in order: " .. audio)
    check(outcomes({}, scenarios.timeout) == "FailMission:bd09lose.des", "offline ten-minute departure")
    check(outcomes({}, scenarios.portallost) == "FailMission:bd09lseb.des", "offline portal loss")
    local _, _, peer = outcomes({}, scenarios.win)
    noEnemyTeamTwo(peer)
    check(F.count(peer, "SetAIControl", 5) == 1 and F.count(peer, "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
end

-- ------------------------------------------------------------------ setup, teams, ownership
do
    local w, p, m = setup(4, {})
    F.run(3)
    check(m.coopMissionStarted and m.startDone, "leader starts the shared mission")
    check(m.user == "crcca_players", "the player is the nearest-human token")
    check(F.count(p[1], "SetAIControl", 5) == 1 and F.count(p[1], "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
    check(F.index(p[1], "SetAIControl") <= p[1].chunkCalls, "SetAIControl runs at chunk root, before Start")
    local scrap = F.callsOf(p[1], "SetScrap")
    check(#scrap == 1 and scrap[1][2] == 1 and scrap[1][3] == 0, "the mission's zero scrap is not topped up per guest: " .. tostring(scrap[1] and scrap[1][3]))
    check(F.count(p[1], "SetPilot") == 0, "pilots are the shared lives in a network game")
    check(p[1].rally and p[1].rally[0] == "cvtnk1", "respawns gather with the convoy")
    for i = 1, 4 do
        check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
        local o = F.callsOf(p[i], "AddObjective")
        check(o[1][2] == "bd09001.otf" and o[1][3] == "white", "first objective on peer " .. i)
        check(F.count(p[i], "SetObjectiveOn", "cvtnk1") == 1, "the first tank is marked on peer " .. i)
    end
    heardAll(p, "bd09001" .. ".wav")
    guestsPassive(p)
end
do -- offline keeps the DLL's pilots
    local w, p, m = setup(1, {})
    check(F.count(p[1], "SetPilot") == 1 and F.last(p[1], "SetPilot")[2] == 1 and F.last(p[1], "SetPilot")[3] == 0, "offline the body sets its own pilots")
    check(F.last(p[1], "SetScrap")[3] == 0, "offline starting scrap is 0")
end

-- ------------------------------------------------------------------ the disguise reaches every human
for n = 1, 4 do
    local w, p, m = setup(n, {})
    perceivedAll(p, 5)
    F.runUntil(function() return m.sound2Played end, 60); F.run(1)
    check(m.oneOfTheEnemy, n .. " human(s): every human sits in the stolen APC, the line is played")
    heardAll(p, "bd09002" .. ".wav")
    perceivedAll(p, 5)
    -- the pilot (or any new ship of a human) is disguised too while the cover holds
    eject(p[n], 870, 102000); F.run(2)
    check(F.perceived(p[n].player) == 5, "a human's new ship (the pilot) is disguised")
    guestsPassive(p)
    noEnemyTeamTwo(p[1])
end
do -- one human leaving the APC before the briefing exposes everyone (the DLL's single-player rule, shared)
    local w, p, m = setup(3, {})
    F.run(3)
    perceivedAll(p, 5)
    eject(p[2], 870, 102000); F.run(2)
    check(m.sound2Played == false and m.oneOfTheEnemy == false, "no briefing and no cover once someone left early")
    perceivedAll(p, "own")
    check(F.perceived("player2") == 2 or F.perceived(p[2].player) ~= 5, "the exposed human is not disguised")
    F.run(20)
    check(m.deviateSpawned == true, "the ambush follows the exposure")
    check(F.heardCount(p[1], "bd09007" .. ".wav") == 1 and F.heardCount(p[1], "bd09002" .. ".wav") == 0, "the exposure line, not the briefing")
    local hunters = 0
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do
        if isHuman(p, c[3]) then hunters = hunters + 1 end
    end
    check(hunters >= 4, "the convoy and the ambush hunt a human: " .. hunters)
    -- the cover is never restored
    F.run(5)
    perceivedAll(p, "own")
    noEnemyTeamTwo(p[1])
end

-- ------------------------------------------------------------------ capture of the first tank by any human
for who = 1, 3 do
    local w, p, m = setup(3, {})
    capture(w, p, m, who)
    check(m.objective1Complete and m.oneOfTheEnemy == false, "human " .. who .. " takes the tank: objective 1 complete")
    local nav = F.builds(p[1], 0, "apcamr")
    check(#nav == 1 and nav[1].team == 1 and nav[1].where == "spawn_beacon1", "the first beacon is a team-1 nav")
    F.run(8)
    for i = 1, 3 do check(F.count(p[i], "SetObjectiveOff", "cvtnk1") == 1, "the marker is lifted on peer " .. i) end
    check(m.user == "crcca_players", "afterwards the player is the token again")
    heardAll(p, "bd09003" .. ".wav")
    -- the restored green first line, then the second objective; identical lists on every peer
    for i = 1, 3 do
        local adds, idx = F.callsOf(p[i], "AddObjective"), F.index(p[i], "ClearObjectives", nil)
        check(adds[#adds][2] == "bd09002.otf" and adds[#adds][3] == "white" and adds[#adds - 1][2] == "bd09001.otf" and adds[#adds - 1][3] == "green",
            "peer " .. i .. " shows the finished objective in green, then the next in white")
    end
    -- the convoy sets out; a tank a human drives is never ordered
    local ordered = {}
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do
        if c[3] == "tank_path" then ordered[c[2]] = (ordered[c[2]] or 0) + 1 end
    end
    check(ordered.cvtnk2 == 1 and ordered.cvtnk3 == 1 and ordered.cvtnk4 == 1 and ordered.cvtnk5 == 1 and ordered.cvtnk1 == nil, "the four tanks of the pack are sent along the path")
    perceivedAll(p, 5) -- the cover holds through the capture
    guestsPassive(p)
end
do -- a tank another human drives keeps its driver
    local w, p, m = setup(3, {})
    F.runUntil(function() return m.sound2Played end, 60)
    p[2].player = "cvtnk3"; w.objects.cvtnk3.team = 2
    hop(p[1]); F.runUntil(function() return m.objective1Complete end, 10); F.run(8)
    local sent = {}
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[3] == "tank_path" then sent[c[2]] = true end end
    check(sent.cvtnk2 and sent.cvtnk4 and sent.cvtnk5 and not sent.cvtnk3, "the convoy skips the tank a human drives")
end

-- ------------------------------------------------------------------ the beacons, the portal's line, the finished objectives
do
    local w, p, m = setup(3, {})
    capture(w, p, m); F.run(8)
    F.nearTo("cvtnk2", m.beacon1, 10, 0); F.run(1)
    check(type(m.beacon2) == "string" and F.builds(p[1], 0, "apcamr")[2].where == "spawn_beacon2", "a tank at beacon 1 spawns beacon 2")
    check(F.heardCount(p[1], "bd09004" .. ".wav") == 0, "no line until a human arrives")
    F.nearTo(p[2].player, m.beacon1, 20, 0); F.run(1)
    heardAll(p, "bd09004" .. ".wav")
    F.nearTo("cvtnk3", m.beacon2, 10, 0); F.run(1)
    check(type(m.beacon3) == "string", "a tank at beacon 2 spawns beacon 3")
    F.nearTo(p[3].player, m.beacon2, 20, 0); F.run(1)
    heardAll(p, "bd09005" .. ".wav")
    F.run(6)
    heardAll(p, "bd09006" .. ".wav")
    for i = 1, 3 do check(F.count(p[i], "SetObjectiveOn", "portal") == 1, "the portal is marked on peer " .. i) end
    F.nearTo(p[1].player, m.beacon3, 20, 0); F.run(1)
    check(m.objective2Complete, "the third beacon completes the second objective")
    for i = 1, 3 do
        local adds = F.callsOf(p[i], "AddObjective")
        check(adds[#adds][2] == "bd09003.otf" and adds[#adds][3] == "white" and adds[#adds - 2][3] == "green", "the third objective is published on peer " .. i)
    end
    check(m.deviateSpawned ~= true and m.won ~= true, "nothing else fired")
end

-- ------------------------------------------------------------------ straying: nearest human, one reveal, one ambush
for n = 1, 4 do
    local w, p, m = setup(n, {})
    capture(w, p, m); F.run(8)
    if n > 1 then
        -- one human stays with the pack: the convoy is not abandoned
        moveAway(p)
        F.place(p[n].player, 540, 101930); F.run(3)
        check(not m.strayed and not m.deviateSpawned, n .. " human(s): one human with the pack is not straying")
    end
    moveAway(p); F.run(1)
    local mark = #p[1].calls
    F.run(3)
    check(m.strayed, "no human near the pack: strayed")
    perceivedAll(p, "own")
    F.run(3)
    check(m.deviateSpawned, "the ambush follows two seconds later")
    local e = extrasFor(n)
    local wave = {}
    for _, b in ipairs(F.builds(p[1], mark)) do if SCALED[b.odf] then wave[#wave + 1] = b end end
    check(#wave == 11 + e, n .. " human(s): the ambush is eleven units + " .. e .. " extras, got " .. #wave)
    allSafe(p, wave)
    local counts = {}
    for _, b in ipairs(wave) do counts[b.odf] = (counts[b.odf] or 0) + 1; check(b.team == 5, "ambush units are the co-op enemy team") end
    check(counts.cvfigh >= 4 and counts.cvltnk >= 2 and counts.cvhtnk == 1 and counts.cvrckt >= 2 and counts.cvtnk >= 2, "the wave keeps the original mix")
    local attackers = {}
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do
        if isHuman(p, c[3]) and F.team(c[2]) == 5 then attackers[c[2]] = true end
    end
    for _, b in ipairs(wave) do check(attackers[b.h], "an ambush unit hunts a human, extras included: " .. b.h) end
    -- the whole sweep of the turret tanks, once, each at the human nearest to it
    for _, turret in ipairs({"cvturrb9_turrettank", "cvturrb12_turrettank", "cvturrb13_turrettank"}) do
        check(attackers[turret], "turret tank " .. turret .. " is ordered at a human")
    end
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do
        if isHuman(p, c[3]) then
            local nearest, best
            for _, q in ipairs(p) do
                local d = q.env.GetDistance(c[2], q.player)
                if best == nil or d < best then nearest, best = q.player, d end
            end
            check(c[3] == nearest, "an order at the player goes to the human nearest the unit")
        end
    end
    heardAll(p, "bd09007" .. ".wav")
    local total = #F.builds(p[1], 0)
    F.run(10)
    check(#F.builds(p[1], 0) == total and F.heardCount(p[1], "bd09007" .. ".wav") == 1, "the ambush fires once")
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end

-- ------------------------------------------------------------------ the last five at the final trigger
for n = 1, 4 do
    local w, p, m = setup(n, {})
    capture(w, p, m); F.run(8)
    for i, q in ipairs(p) do F.place(q.player, 1080 + 30 * i, 100947) end
    local mark = #p[1].calls
    F.run(3)
    check(m.trigger1, "a human at trigger_1 springs the last stand")
    local function atLast() local out = {} for _, b in ipairs(F.builds(p[1], mark, "cvtnk")) do if b.where == "last_one" then out[#out + 1] = b end end return out end
    local last = atLast()
    local e = extrasFor(n)
    check(#last == 5 + e, n .. " human(s): five tanks + " .. e .. " extras, got " .. #last)
    allSafe(p, last)
    for _, b in ipairs(last) do check(b.team == 5, "the last five are the co-op enemy") end
    local hunting = 0
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do if isHuman(p, c[3]) then hunting = hunting + 1 end end
    check(hunting >= 5 + e, "all of them hunt a human: " .. hunting)
    F.run(5)
    check(#atLast() == 5 + e, "the last stand fires once")
end

-- ------------------------------------------------------------------ the portal: everyone goes through
for n = 1, 4 do
    local w, p, m = setup(n, {})
    capture(w, p, m); F.run(8)
    F.nearTo(p[1].player, "portal", 120, 0)
    for i = 2, n do F.nearTo(p[i].player, "portal", 120 + 8 * i, 0) end
    F.run(2)
    check(m.portalActive, "a human within 250 m opens the portal")
    for i = 1, n do
        check(F.count(p[i], "ActivatePortal", "portal") == 1, "peer " .. i .. " opens its own copy of the portal")
        check(F.heardCount(p[i], "bd09008" .. ".wav") == 1, "peer " .. i .. " hears the order to go through")
    end
    F.run(3)
    check(F.count(p[1], "ActivatePortal") == 1, "the portal opens once")
    if n > 1 then
        F.touch(p[1].player, "portal"); F.run(3)
        check(not m.won and F.count(p[1], "SucceedMission") == 0, n .. " human(s): the first through does not end the mission")
        for i = 2, n - 1 do F.touch(p[i].player, "portal"); F.run(2) end
        check(not m.won, "still waiting for the last human")
        F.touch(p[n].player, "portal"); F.run(10)
    else
        F.touch(p[1].player, "portal"); F.run(10)
    end
    check(m.won, n .. " human(s): the mission is won when every human is through")
    for i = 1, n do
        check(F.count(p[i], "SucceedMission") == 1 and F.last(p[i], "SucceedMission")[3] == "bd09win.des", "one shared victory on peer " .. i)
        check(F.count(p[i], "FailMission") == 0, "no failure after the win")
        check((p[i].env.Save().coopUnresolved or 0) == 0, "no unresolved presentation identities on peer " .. i)
    end
    local total = #F.builds(p[1], 0)
    F.run(20)
    check(#F.builds(p[1], 0) == total, "nothing is built after the result")
end
do -- a human who went through and left (or died) still counts; the dead are not waited for
    local w, p, m = setup(3, {})
    capture(w, p, m); F.run(8)
    for i = 1, 3 do F.nearTo(p[i].player, "portal", 100 + i, 0) end
    F.run(2)
    F.touch(p[2].player, "portal"); F.run(1)
    F.place(p[2].player, 3000, 99000); F.run(1)
    F.touch(p[1].player, "portal"); F.run(2)
    check(not m.won, "one human is still outside")
    F.kill(p[3].player); F.run(3)
    check(F.count(p[1], "FailMission") == 0, "a death does not fail the shared mission")
    -- the third respawns and goes through
    local newShip = F.spawn("cvapc", 3, 520, 100900)
    p[3].player = newShip
    F.run(2)
    F.touch(newShip, "portal"); F.run(8)
    check(m.won and F.count(p[1], "SucceedMission") == 1, "the respawned human goes through and the mission is won")
end

-- ------------------------------------------------------------------ results
do -- the portal lost
    local w, p, m = setup(3, {})
    capture(w, p, m); F.run(3)
    F.kill("portal"); F.run(10)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd09lseb.des", "one shared failure on peer " .. i)
        check(F.count(p[i], "SucceedMission") == 0, "no victory after a loss")
    end
    local builds = #F.builds(p[1])
    moveAway(p); F.run(30)
    check(#F.builds(p[1]) == builds, "no reinforcement is built after the loss")
end
do -- the ten-minute rule: any human in a tracked tank keeps the party alive
    local w, p, m = setup(3, {})
    capture(w, p, m); F.run(8)
    F.run(700)
    check(m.tankTimeout == -1 and F.count(p[1], "FailMission") == 0, "one human in the tank is enough: the timer never starts")
    eject(p[1]); F.run(5)
    check(m.tankTimeout > 0, "the timer starts when no human is in a tracked tank")
    local at = m.tankTimeout
    F.run(at - w.now - 30)
    check(F.count(p[1], "FailMission") == 0, "no failure before ten minutes")
    p[1].player = "cvtnk1"; F.run(2)
    check(m.tankTimeout == -1, "a human back in a tank resets it")
    eject(p[1]); F.run(5)
    local at2 = m.tankTimeout
    F.run(at2 - w.now + 3)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd09lose.des", "one shared failure on peer " .. i)
    end
end
do -- the lives are the shared ones: one dead human fails nothing, every human out of lives fails the mission
    local w, p, m = setup(3, {})
    capture(w, p, m); F.run(3)
    F.kill(p[1].player); F.run(10)
    check(F.count(p[1], "FailMission") == 0 and F.count(p[2], "FailMission") == 0, "one dead human never fails a network mission")
    check(m.lost ~= true, "the body is not told")
end

-- ------------------------------------------------------------------ stock bugs: a line that never starts, loads
do
    local w, p, m = setup(1, { nilAudio = true })
    F.run(25)
    check(m.sound2Played == true, "a briefing the engine cannot play does not stall the chain")
    local fw, fp, fm = setup(1, { faithful = true, script = F.FAITHFUL, nilAudio = true })
    F.run(25)
    check(fm.sound2Played == false, "(the faithful body does stall on a line without a handle)")
end
do -- the audio chain gate: a busy line holds the next
    local w, p, m = setup(2, { busy = true })
    F.run(30)
    check(m.sound2Time == 999999.9 or m.sound2Played == false, "a line that is still playing holds the chain")
    w.audioBusy = false; F.run(25)
    check(m.sound2Played == true, "the chain resumes when the line is done")
end
do -- a load before the capture republishes the objective and the tank marker
    local w, p, m = setup(3, {})
    F.run(5)
    local marks = {}
    for i, q in ipairs(p) do marks[i] = #q.calls end
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    for i, q in ipairs(p) do
        local clears, adds, ons = 0, {}, 0
        for k = marks[i] + 1, #q.calls do
            local c = q.calls[k]
            if c[1] == "ClearObjectives" then clears = clears + 1 end
            if c[1] == "AddObjective" then adds[#adds + 1] = c end
            if c[1] == "SetObjectiveOn" and c[2] == "cvtnk1" then ons = ons + 1 end
        end
        check(clears == 1 and #adds == 1 and adds[1][2] == "bd09001.otf" and adds[1][3] == "white", "peer " .. i .. " republishes the objective after a load")
        check(ons == 1, "peer " .. i .. " sees the tank marker again")
    end
    capture(w, p, m)
    check(m.objective1Complete, "the mission goes on after the load")
end
do -- a load on the way to the portal republishes the finished objectives and the portal marker
    local w, p, m = setup(2, {})
    capture(w, p, m); F.run(8)
    F.nearTo("cvtnk2", m.beacon1, 10, 0); F.run(1); F.nearTo(p[1].player, m.beacon1, 20, 0); F.run(1)
    F.nearTo("cvtnk3", m.beacon2, 10, 0); F.run(1); F.nearTo(p[1].player, m.beacon2, 20, 0); F.run(8)
    local marks = {}
    for i, q in ipairs(p) do marks[i] = #q.calls end
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    for i, q in ipairs(p) do
        local adds, portal, tank = {}, 0, 0
        for k = marks[i] + 1, #q.calls do
            local c = q.calls[k]
            if c[1] == "AddObjective" then adds[#adds + 1] = c[2] .. "/" .. c[3] end
            if c[1] == "SetObjectiveOn" and c[2] == "portal" then portal = portal + 1 end
            if c[1] == "SetObjectiveOn" and c[2] == "cvtnk1" then tank = tank + 1 end
        end
        check(table.concat(adds, ",") == "bd09001.otf/green,bd09002.otf/white", "peer " .. i .. " republishes " .. table.concat(adds, ","))
        check(portal == 1 and tank == 0, "peer " .. i .. " marks the portal, not the lifted tank marker")
    end
    F.nearTo(p[1].player, m.beacon3, 20, 0); F.run(1)
    local adds = F.callsOf(p[1], "AddObjective")
    check(adds[#adds][2] == "bd09003.otf", "the mission continues after the load")
end

-- ------------------------------------------------------------------ nothing within 460 m of a human
do
    local w, p, m = setup(3, {})
    capture(w, p, m); F.run(8)
    -- every approach of the ambush is at one spot where a hidden human stands: the wave waits as tickets
    local saved = {}
    for i = 1, 6 do
        local name = "spawn_deviate" .. i
        saved[name] = w.pathPos[name]
        w.pathPos[name] = { x = 4000, y = saved[name].y, z = 98000 }
    end
    F.place(p[2].player, 4000, 98000)
    F.place(p[1].player, 20000, 20000); F.place(p[3].player, 20000, 20000)
    F.run(3)
    m.strayed = false -- (the human near the entries is far from the pack too)
    F.run(4)
    check(m.deviateSpawned, "the ambush has fired")
    local wave = 0
    for _, b in ipairs(F.builds(p[1], 0)) do if SCALED[b.odf] then wave = wave + 1 end end
    check(wave == 0, "a fully watched map defers the whole ambush")
    local pending = m.crcca.serial
    check(pending >= 11, "the tickets are saved")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(m.crcca.serial == pending, "save/load keeps the pending wave without duplicating it")
    for name, pos in pairs(saved) do w.pathPos[name] = pos end
    F.place(p[2].player, 20000, 20000); F.run(8)
    local built = 0
    local attackers = 0
    for _, b in ipairs(F.builds(p[1], 0)) do if SCALED[b.odf] then built = built + 1 end end
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do if isHuman(p, c[3]) and F.team(c[2]) == 5 then attackers = attackers + 1 end end
    check(built == 11 + 1, "the whole wave is built exactly once when the watcher leaves: " .. built)
    check(attackers >= 11 + 1, "the remembered orders reach the nearest human when the tickets are built: " .. attackers)
end
do -- live cap: extras are the only requests dropped
    local w, p, m = setup(4, {})
    capture(w, p, m); F.run(8)
    m.crcca.live = {}
    for i = 1, 16 do m.crcca.live[i] = F.spawn("cvfigh", 5, 9000 + i, 9000) end
    moveAway(p); F.run(8)
    local built = 0
    for _, b in ipairs(F.builds(p[1], 0)) do if SCALED[b.odf] then built = built + 1 end end
    check(built == 11, "at the live cap the wave keeps its primaries and drops the extras: " .. built)
end

-- ------------------------------------------------------------------ leader leaves
do
    local w, p, m = setup(3, {})
    for i = 2, 3 do p[i].env.DeletePlayer(1) end
    F.run(3)
    for i = 2, 3 do check(F.count(p[i], "FailMission") == 1, "the mission fails for guest " .. i .. " when the leader leaves") end
    check(F.count(p[1], "FailMission") == 0, "the leader itself keeps playing")
end

-- ------------------------------------------------------------------ weather: absent, present, broken
do
    local w, p, m = setup(3, {})
    check(F.count(p[1], "EnvironmentInit") == 0 and m.startDone, "no weather module: the mission runs and touches no Environment")
    local printed = false
    for _, c in ipairs(p[1].calls) do if c[1] == "print" and tostring(c[2]):find("weather disabled", 1, true) then printed = true end end
    check(printed, "missing weather is logged, not fatal")
end
local function elysium(record, mode)
    return function(peer)
        local V = { Seed = 4242, Initialized = false }
        function V.Init(o) peer.weatherInit = o; V.Initialized = true; record("ElysiumInit", o.authority, o.send ~= nil, o.seed, o.startLevel, o.targetLevel)
            if mode == "initfail" then error("boom") end end
        function V.Update(dt)
            if peer.weatherInit and peer.weatherInit.authority and peer.weatherInit.send and not V.sent then
                V.sent = true; peer.weatherInit.send("VenusStrike", 1, 0.3, 3, 1)
            end
            if mode == "updatefail" then error("update boom") end
        end
        function V.AnnounceState() record("ElysiumAnnounce") end
        function V.ApplyNetEvent(op, ...) record("ElysiumEvent", op, ...) end
        function V.SetTargetLevel(n) record("ElysiumLevel", n) end
        function V.ForceLevel(n, seconds, blend) record("ElysiumForce", n, seconds, blend) end
        function V.TriggerStrike(target) record("ElysiumStrike", target.x, target.z) end
        function V.OnObjectCreated(h) record("ElysiumCreated", h) end
        function V.Save() return { saved = true } end
        function V.Load(s) record("ElysiumLoad", s and s.saved) end
        function V.Shutdown() record("ElysiumShutdown") end
        return V
    end
end
do
    local sites = dofile("Scripts/CRElysiumSitesBD09.lua")
    check(sites.mission == "bdmisn09" and #sites.vents == 2, "the generated sites for this map carry its two geysers")
    local weather = { module = function(peer, record) return elysium(record)(peer) end, sites = sites }
    local w, p, m = setup(3, { weather = weather })
    check(F.count(p[1], "ElysiumInit", true) == 1 and F.last(p[1], "ElysiumInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.last(p[1], "ElysiumInit")[5] == 1 and F.last(p[1], "ElysiumInit")[6] == 1, "the weather starts calm and holds")
    check(F.count(p[2], "ElysiumInit", false) == 1, "guests render only (not the authority)")
    check(F.count(p[1], "ElysiumAnnounce") == 1 and F.count(p[2], "ElysiumAnnounce") == 0, "the leader announces its weather state once")
    check(F.count(p[1], "EnvironmentInit") == 1, "the environment is initialised once")
    for i = 2, 3 do
        local e = F.last(p[i], "ElysiumEvent")
        check(e and e[2] == "VenusStrike" and e[3] == 1, "weather events reach guest " .. i)
    end
    check(p[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    check(F.count(p[1], "ElysiumLevel") == 0, "calm until the tank is taken")
    capture(w, p, m); F.run(1)
    check(F.count(p[1], "ElysiumLevel", 2) == 1, "the stolen tank brings the haze")
    F.run(8)
    F.nearTo("cvtnk2", m.beacon1, 10, 0); F.run(1); F.nearTo(p[1].player, m.beacon1, 20, 0); F.run(1)
    check(F.count(p[1], "ElysiumLevel", 3) == 1, "the first beacon darkens the sky")
    F.nearTo("cvtnk3", m.beacon2, 10, 0); F.run(1); F.nearTo(p[1].player, m.beacon2, 20, 0); F.run(1)
    check(F.count(p[1], "ElysiumLevel", 4) == 1, "the unexpected path builds the storm")
    moveAway(p); F.run(8)
    check(m.deviateSpawned and F.count(p[1], "ElysiumForce", 5, 100.0, 12.0) == 1, "the blown cover forces a level-5 burst")
    check(F.count(p[1], "ElysiumStrike") == 1 and F.last(p[1], "ElysiumStrike")[2] == 983.333, "a strike lands where the ambush springs")
    check(F.count(p[1], "ElysiumLevel", 4) == 2, "the ladder returns to the storm after the burst")
    for i, q in ipairs(p) do F.place(q.player, 1100, 100947) end
    F.run(3)
    check(F.count(p[1], "ElysiumLevel", 5) == 1, "the last stand at the portal is the worst of it")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "ElysiumShutdown") >= 1 and F.count(p[1], "ElysiumLoad", true) == 1, "load restores the leader's weather state")
    for i, q in ipairs(p) do F.nearTo(q.player, "portal", 100 + 5 * i, 0) end
    F.run(2)
    for _, q in ipairs(p) do F.touch(q.player, "portal") end
    F.run(8)
    check(m.won and F.count(p[1], "ElysiumLevel", 2) == 2, "the debrief eases the sky")
    check(F.count(p[1], "ElysiumCreated") > 0, "new objects are offered to the weather")
    check(F.count(p[2], "ElysiumLevel") == 0 and F.count(p[2], "ElysiumForce") == 0 and F.count(p[2], "ElysiumStrike") == 0, "guests never decide weather events")
end
do -- sites module missing: no weather, never an error
    local w, p, m = setup(2, { weather = { module = function(peer, record) return elysium(record)(peer) end } })
    check(F.count(p[1], "ElysiumInit") == 0 and m.startDone, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local w, p, m = setup(2, { weather = { module = function(peer, record) return elysium(record, mode)(peer) end, sites = dofile("Scripts/CRElysiumSitesBD09.lua") } })
    scenarios.win(w, { p[1] }, m)
    for i = 1, 2 do F.nearTo(p[i].player, "portal", 100 + i, 0) end
    F.run(1)
    for i = 1, 2 do F.touch(p[i].player, "portal") end
    F.run(8)
    check(F.count(p[1], "SucceedMission") == 1 and F.count(p[2], "SucceedMission") == 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("bdmisn09 co-op: " .. checks .. " checks passed")
