-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/bd07cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/Test-Bdmisn07Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Bdmisn07Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local function extrasFor(n) return math.min(math.floor(n / 2), 2) end
local WAVE1 = { "chin_scout1", "chin_scout2", "chin_scout3" }
local WAVE2 = { "chin_scout4", "chin_scout5", "chin_scout6", "chin_ltnk1", "chin_ltnk2", "chin_tank1", "chin_bomber1", "chin_bomber2" }
local TARGETS = { "chin_recycler", "chin_factory", "chin_solar1", "chin_solar2", "chin_solar3", "chin_tower1", "chin_tower2",
    "chin_tower3", "chin_supply", "chin_hq", "chin_hangar" }
local SAVE = { "recycler", "myfactory", "my_hq" }

local function setup(n, options)
    options = options or {}
    local w = F.reset()
    w.audioBusy = options.busy == true
    if options.scrapOf then w.scrapOf = options.scrapOf end
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
local function killAll(list) for _, label in ipairs(list) do F.kill(label) end end
-- Chinese craft the script built (never map objects) at a path.
local function builtAt(peer, where, odf)
    local out = {}
    for _, b in ipairs(F.builds(peer, 0, odf)) do
        if b.where == where then out[#out + 1] = b end
    end
    return out
end
local function allSafe(p, builds)
    for _, b in ipairs(builds) do
        for _, q in ipairs(p) do
            check(q.env.GetDistance(q.player, b.h) >= 460, "no scripted unit is built within 460 m of any human")
        end
    end
end
local function heardAll(p, file, count)
    for i, q in ipairs(p) do check(F.heardCount(q, file) == (count or 1), "peer " .. i .. " hears " .. file .. " x" .. (count or 1)) end
end
local function guestsPassive(p)
    for i = 2, #p do
        for _, name in ipairs({"BuildObject", "SetScrap", "Goto", "Attack", "SetAIP"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on the authored enemy team 2") end
end
-- The moment the objectives first appear on the host (the briefing is over).
local function briefedAt(peer)
    local first = F.callsOf(peer, "AddObjective")[1]
    return first and first.t
end
local function gotosTo(peer, path)
    local n = 0
    for _, c in ipairs(F.callsOf(peer, "Goto")) do if c[3] == path then n = n + 1 end end
    return n
end
local function firstGoto(peer, path)
    for _, c in ipairs(F.callsOf(peer, "Goto")) do if c[3] == path then return c.t end end
end
local function humansOf(p)
    local set = {}
    for _, q in ipairs(p) do set[q.player] = true end
    return set
end

-- ------------------------------------------------------------------ offline == faithful
local function summary(peer)
    local out, objectives = {}, {}
    for _, c in ipairs(peer.calls) do
        if c[1] == "BuildObject" then
            out[#out + 1] = "B:" .. c[3] .. ":" .. (c[4] == 2 and 5 or c[4]) .. ":" .. tostring(c[5])
        elseif c[1] == "SucceedMission" or c[1] == "FailMission" then
            out[#out + 1] = c[1] .. ":" .. tostring(c[3])
        elseif c[1] == "AddObjective" then
            objectives[#objectives + 1] = "O:" .. c[2] .. ":" .. tostring(c[3]) -- published at the end of the frame
        elseif c[1] == "SetScrap" then
            out[#out + 1] = "S:" .. (c[2] == 2 and 5 or c[2]) .. ":" .. c[3]
        elseif c[1] == "SetPilot" then
            out[#out + 1] = "P:" .. (c[2] == 2 and 5 or c[2]) .. ":" .. c[3]
        elseif c[1] == "SetAIP" then
            out[#out + 1] = "AIP:" .. c[2]
        end
    end
    local lines = {}
    for _, c in ipairs(peer.calls) do
        if c[1] == "AudioMessage" or c[1] == "Play" then lines[#lines + 1] = c[2] end
    end
    return table.concat(out, ",") .. "|" .. table.concat(objectives, ",") .. "|" .. table.concat(lines, ",")
end
local function fullRun(options)
    local w = F.reset()
    local peer = F.makePeer(1, 1, false, options)
    F.connect(); F.run(1)
    -- both waves are beaten before the restored attack would set out, so the run is the faithful one
    F.run(40)
    killAll(WAVE1); killAll(WAVE2)
    F.run(310) -- two harassment raids
    killAll(TARGETS)
    F.run(5)
    return summary(peer), peer
end
do
    local faithful = fullRun({ faithful = true, script = "Scripts/bdmisn07.lua" })
    local offline, peer = fullRun({})
    check(faithful == offline and faithful:find("SucceedMission:bd07win.des", 1, true) and faithful:find("bd07004.wav", 1, true),
        "offline completes like the faithful port:\n" .. faithful .. "\n" .. offline)
    check(F.count(peer, "SucceedMission") == 1 and F.count(peer, "FailMission") == 0, "one victory, no failure")
    check(#F.builds(peer) == 10, "two raids of five")
    noEnemyTeamTwo(peer)
    check(F.count(peer, "SetAIControl", 5) == 1 and F.count(peer, "SetAIControl", 2) == 0, "AI control only for enemy team 5")
    check(F.index(peer, "SetAIControl") <= peer.chunkCalls, "SetAIControl runs at chunk root, before Start")
end

-- ------------------------------------------------------------------ teams, scrap, pilots, the briefing
do
    local w, p, m = setup(4, {})
    F.run(20)
    check(m.startDone and m.coopMissionStarted, "the leader starts the shared mission")
    check(F.count(p[1], "SetScrap", 1) == 1 and F.last(p[1], "SetScrap")[3] == 8 + 10 * 3, "starting scrap: 8 plus 10 per guest")
    for team = 1, 4 do check(F.count(p[1], "SetPilot", team) == 1 and F.callsOf(p[1], "SetPilot")[1][3] == 10, "10 pilots for human team " .. team) end
    check(F.count(p[1], "SetAIP", "bdmisn07.aip") == 1 and F.last(p[1], "SetAIP")[3] == 5, "the AIP drives the co-op enemy team 5")
    check(F.count(p[1], "SetObjectiveName") == 2, "both nav beacons are named")
    for i = 1, 4 do
        check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
        local lines = F.lines(p[i])
        check(lines[1] == "bd07001.wav" and lines[2] == "bd07002.wav" and lines[3] == "bd07003.wav" and #lines == 3,
            "the briefing plays in order on peer " .. i)
        local o = F.callsOf(p[i], "AddObjective")
        check(o[1] and o[1][2] == "bd07001.otf" and o[1][3] == "white", "objective on peer " .. i)
    end
    check(m.crcca and m.crcca.serial == 0, "nothing is spawned before the go-ahead")
    guestsPassive(p)
end

-- ------------------------------------------------------------------ restored: the two map waves set out
do
    local w, p, m = setup(2, {})
    F.run(20)
    local t0 = briefedAt(p[1])
    check(t0 ~= nil and t0 < 15, "the briefing ends within seconds: " .. tostring(t0))
    F.runUntil(function() return w.now > t0 + 100 end)
    check(gotosTo(p[1], "attack_path1") == 0 and gotosTo(p[1], "attack_path2") == 0, "no wave before the delay")
    F.runUntil(function() return w.now > t0 + 125 end)
    check(gotosTo(p[1], "attack_path1") == 3 and gotosTo(p[1], "attack_path2") == 0, "wave 1 (three scouts) sets out 120 s after the objectives")
    check(math.abs(firstGoto(p[1], "attack_path1") - (t0 + 120)) < 1.5, "...at the delay, " .. tostring(firstGoto(p[1], "attack_path1")))
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do check(c[4] == 1, "the source's priority 1") end
    F.runUntil(function() return w.now > t0 + 155 end)
    check(gotosTo(p[1], "attack_path2") == 8, "wave 2 (eight units) follows 30 s later")
    check(math.abs(firstGoto(p[1], "attack_path2") - firstGoto(p[1], "attack_path1") - 30) < 1.5, "the source's 30 s gap")
    F.run(60)
    check(gotosTo(p[1], "attack_path1") == 3 and gotosTo(p[1], "attack_path2") == 8, "each wave is sent once")
    local r = m.crcca.r
    check(r.waveArmed and r.waveSet and r.wave1 and r.wave2, "the weather flags follow the waves")
    check(F.count(p[2], "Goto") == 0, "the guest never orders")
end
do -- the waves are already beaten: nothing is armed
    local w, p, m = setup(1, {})
    F.run(5); killAll(WAVE1); killAll(WAVE2); F.run(150)
    check(m.objective1Complete and gotosTo(p[1], "attack_path1") == 0 and gotosTo(p[1], "attack_path2") == 0, "beaten waves are not sent")
    check(m.waveDelay[0] >= 999999.9, "the dormant timer stays dormant")
end
do -- a map without the wave paths runs the faithful mission
    local w = F.reset()
    w.missingPaths = { attack_path2 = true }
    local peer = F.makePeer(1, 1, false, {})
    F.connect(); F.run(200)
    check(gotosTo(peer, "attack_path1") == 0 and gotosTo(peer, "attack_path2") == 0, "no path, no restored wave")
end
do -- a save/load mid-countdown neither loses nor repeats the wave
    local w, p, m = setup(2, {})
    F.run(20)
    local t0 = briefedAt(p[1])
    F.runUntil(function() return w.now > t0 + 60 end)
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    F.runUntil(function() return w.now > t0 + 200 end)
    check(gotosTo(p[1], "attack_path1") == 3 and gotosTo(p[1], "attack_path2") == 8, "the wave is sent once across a load")
end
do -- a load republishes the objectives of the phase earned
    local w, p, m = setup(2, {})
    F.run(20)
    local before = #F.callsOf(p[1], "AddObjective")
    check(before >= 1 and m.crcca.r.briefDone, "the briefing is done and recorded")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    local o = F.callsOf(p[1], "AddObjective")
    check(#o > before and o[#o][2] == "bd07001.otf" and o[#o][3] == "white", "the patrol objective is back after a load")
    killAll(WAVE1); killAll(WAVE2); F.run(2)
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    o = F.callsOf(p[1], "AddObjective")
    check(o[#o][2] == "bd07002.otf" and o[#o][3] == "white", "the destroy objective is back after a load")
end
do -- a load before the briefing ends does not show objectives early
    local w, p, m = setup(1, {})
    F.run(2)
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(1)
    check(#F.callsOf(p[1], "AddObjective") == 0 and not m.crcca.r.briefDone, "no objectives before the briefing is over")
end
do -- an absent audio handle still advances the briefing; waves arm only after the objectives
    local w = F.reset()
    w.audioNil = true
    local peer = F.makePeer(1, 1, false, {})
    F.connect(); F.run(3)
    check(#F.callsOf(peer, "AddObjective") == 0 and gotosTo(peer, "attack_path1") == 0, "nothing before the briefing times")
    F.run(20)
    local t0 = briefedAt(peer)
    check(t0 ~= nil, "objectives shown despite nil audio handles")
    F.runUntil(function() return w.now > t0 + 125 end)
    check(gotosTo(peer, "attack_path1") == 3, "waves arm from the objectives, not before")
    check(math.abs(firstGoto(peer, "attack_path1") - (t0 + 120)) < 1.5, "...120 s after them")
end

-- ------------------------------------------------------------------ the go-ahead, the shared Chinese scrap, the raids
do
    local w, p, m = setup(3, { scrapOf = { [2] = 500, [5] = 10 } })
    F.run(20)
    killAll(WAVE1); killAll(WAVE2); F.run(2)
    check(m.objective1Complete, "the waves are beaten")
    heardAll(p, "bd07004.wav")
    check(F.count(p[1], "GetScrap", 2) == 0 and F.count(p[1], "GetScrap", 5) == 1, "the Chinese scrap is read from team 5, not from a guest's team 2")
    check(F.count(p[1], "SetScrap", 5) == 1 and F.last(p[1], "SetScrap")[3] == 40, "poor Chinese get 40 scrap")
    local o = F.callsOf(p[1], "AddObjective")
    check(o[#o][2] == "bd07002.otf" and o[#o][3] == "white", "the destroy objective appears")
end
do
    local w, p, m = setup(2, { scrapOf = { [2] = 0, [5] = 500 } })
    F.run(20); killAll(WAVE1); killAll(WAVE2); F.run(2)
    check(F.count(p[1], "SetScrap", 5) == 0, "a guest team's empty scrap does not top up the Chinese")
end
for humans = 1, 4 do
    local w, p, m = setup(humans, {})
    F.run(20)
    killAll(WAVE1); killAll(WAVE2); F.run(10)
    local e = extrasFor(humans)
    local raid = builtAt(p[1], "annoy_1")
    check(#raid == 5 + e, humans .. " human(s): the raid is 5 + " .. e .. " extras, got " .. #raid)
    allSafe(p, raid)
    local fighters, tanks = 0, 0
    for _, b in ipairs(raid) do
        check(b.team == 5, "raiders are Chinese craft on team 5")
        if b.odf == "cvfigh" then fighters = fighters + 1 else tanks = tanks + 1 end
    end
    check(fighters == 3 + e and tanks == 2, "three fighters (the first mirrored) and two light tanks")
    local set, ordered = humansOf(p), 0
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do
        for _, b in ipairs(raid) do if c[2] == b.h and set[c[3]] then ordered = ordered + 1 end end
    end
    check(ordered >= #raid, "every raider (extras too) hunts a human: " .. ordered)
    F.run(300)
    check(#builtAt(p[1], "annoy_1") == 2 * (5 + e), "a second raid five minutes later")
    guestsPassive(p)
    noEnemyTeamTwo(p[1])
end
do -- a human at the entry: the raid comes from another hidden approach, never in view
    local w, p, m = setup(2, {})
    F.run(20)
    F.place(p[2].player, 2100, 99500)
    killAll(WAVE1); killAll(WAVE2); F.run(10)
    check(#builtAt(p[1], "annoy_1") == 0, "nothing is built within 460 m of a human")
    local raid = builtAt(p[1], "attack_path2")
    check(#raid == 5 + 1, "the raid uses the next clear approach: " .. #raid)
    allSafe(p, raid)
end
do -- everything watched: the raid waits (and survives a load), then arrives once
    local w, p, m = setup(2, {})
    F.run(20)
    F.world().objects[p[2].player].craft = false
    F.place(p[2].player, 4000, 98000)
    for _, name in ipairs({ "annoy_1", "attack_path1", "attack_path2" }) do w.pathPos[name] = { x = 4000, y = 10, z = 98000 } end
    killAll(WAVE1); killAll(WAVE2); F.run(10)
    check(#F.builds(p[1], 0, "cvfigh") == 0 and #F.builds(p[1], 0, "cvltnk") == 0, "a fully watched map defers the raid")
    check(type(m.crcca.serial) == "number" and m.crcca.serial >= 5, "tickets are held")
    check(F.count(p[1], "Attack") == 0, "no native call ever sees a ticket")
    local pending = m.crcca.serial
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(m.crcca.serial == pending and #F.builds(p[1], 0, "cvfigh") == 0, "save/load keeps the pending raid without duplicating it")
    w.pathPos.annoy_1 = { x = 2145, y = 10, z = 99485 }
    F.place(p[2].player, 20000, 20000)
    F.run(8)
    check(#F.builds(p[1], 0, "cvfigh") + #F.builds(p[1], 0, "cvltnk") == 5 + 1, "the whole raid is built exactly once when the watcher leaves")
    local hunts = 0
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do if humansOf(p)[c[3]] then hunts = hunts + 1 end end
    check(hunts >= 6, "the orders waited for the units and were replayed on them: " .. hunts)
end
do -- live cap: extras are the only requests dropped
    local w, p, m = setup(4, {})
    F.run(20)
    m.crcca.live = {}
    for i = 1, 16 do m.crcca.live[i] = F.spawn("cvtnk", 5, 9000 + i, 9000) end
    killAll(WAVE1); killAll(WAVE2); F.run(10)
    check(#builtAt(p[1], "annoy_1") == 5, "at the live cap the raid keeps its primaries and drops the extras: " .. #builtAt(p[1], "annoy_1"))
end

-- ------------------------------------------------------------------ stock bug: idle raiders hunt again
do
    local w, p, m = setup(2, {})
    F.run(20); killAll(WAVE1); killAll(WAVE2); F.run(10)
    local raid = builtAt(p[1], "annoy_1")
    local set = humansOf(p)
    local function attacksOn(h)
        local n = 0
        for _, c in ipairs(F.callsOf(p[1], "Attack")) do if c[2] == h and set[c[3]] then n = n + 1 end end
        return n
    end
    local busy = raid[1].h
    F.world().objects[busy].command = 3
    local idle = raid[2].h
    local before, busyBefore = attacksOn(idle), attacksOn(busy)
    F.run(45)
    check(attacksOn(idle) > before, "an idle raider is sent out again")
    check(attacksOn(busy) == busyBefore, "a raider that is busy keeps its order")
    -- the nearest human is chosen
    F.place(p[2].player, 1900, 99500); F.place(p[1].player, 1373, 100138)
    F.nearTo(idle, p[2].player, 100, 0)
    F.run(25)
    local last
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do if c[2] == idle then last = c[3] end end
    check(last == p[2].player, "the nearest living human is the target: " .. tostring(last))
    -- no hunt after the win
    killAll(TARGETS); F.run(3)
    local frozen = #F.callsOf(p[1], "Attack")
    F.run(60)
    check(#F.callsOf(p[1], "Attack") == frozen, "no hunt once the mission is won")
end

-- ------------------------------------------------------------------ result: win, loss, nothing after
for humans = 1, 3 do
    local w, p, m = setup(humans, {})
    F.run(20); killAll(WAVE1); killAll(WAVE2); F.run(3)
    killAll(TARGETS); F.run(5)
    check(m.won, "every Chinese structure is down")
    for i = 1, humans do
        check(F.count(p[i], "SucceedMission") == 1 and F.count(p[i], "FailMission") == 0, "one shared victory on peer " .. i)
        check(F.last(p[i], "SucceedMission")[3] == "bd07win.des", "victory debrief on peer " .. i)
        local o = F.callsOf(p[i], "AddObjective")
        check(o[#o][2] == "bd07002.otf" and o[#o][3] == "green", "the destroy objective turns green on peer " .. i)
        check((p[i].env.Save().coopUnresolved or 0) == 0, "no unresolved presentation identities on peer " .. i)
    end
    killAll(SAVE); F.run(5)
    for i = 1, humans do check(F.count(p[i], "FailMission") == 0, "a loss after the win is ignored") end
    local builds = #F.builds(p[1])
    F.run(320)
    check(#F.builds(p[1]) == builds, "no raid after the win")
    guestsPassive(p)
end
do
    local w, p, m = setup(2, {})
    F.run(20); killAll(WAVE1); killAll(WAVE2); F.run(3)
    killAll(SAVE); F.run(5)
    check(m.lost, "the base is lost")
    for i = 1, 2 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd07lose.des", "one shared defeat on peer " .. i)
        check(F.count(p[i], "SucceedMission") == 0, "no victory on peer " .. i)
    end
    local builds = #F.builds(p[1])
    F.run(320)
    check(#F.builds(p[1]) == builds, "no raid after the defeat")
end
do -- one of the three protected structures is enough
    local w, p, m = setup(1, {})
    F.run(20); F.kill("recycler"); F.kill("myfactory"); F.run(5)
    check(not m.lost and F.count(p[1], "FailMission") == 0, "the HQ alone keeps the base")
end
do -- the leader leaves
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
        function V.Init(o)
            peer.weatherInit = o; V.Initialized = true
            record("ElysiumInit", o.authority, o.send ~= nil, o.seed, o.startLevel, o.targetLevel)
            if mode == "initfail" then error("boom") end
        end
        function V.Update()
            if peer.weatherInit and peer.weatherInit.authority and peer.weatherInit.send and not V.sent then
                V.sent = true; peer.weatherInit.send("VenusStrike", 1, 2, 3, 4, 3, 1.0, 1.0)
            end
            if mode == "updatefail" then error("update boom") end
        end
        function V.AnnounceState() record("ElysiumAnnounce") end
        function V.ApplyNetEvent(op, ...) record("ElysiumEvent", op, ...) end
        function V.SetTargetLevel(n) record("ElysiumLevel", n) end
        function V.TriggerStrike(target) record("ElysiumStrike", target.x, target.z) end
        function V.OnObjectCreated(h) record("ElysiumCreated", h) end
        function V.Save() return { saved = true } end
        function V.Load(s) record("ElysiumLoad", s and s.saved) end
        function V.Shutdown() record("ElysiumShutdown") end
        return V
    end
end
do
    local sites = dofile("Scripts/CRElysiumSitesBD07.lua")
    check(sites.mission == "bdmisn07" and #sites.vents == 6, "the generated sites belong to bdmisn07")
    local weather = { module = function(peer, record) return elysium(record, nil)(peer) end, sites = sites }
    local w, p, m = setup(3, { weather = weather })
    check(F.count(p[1], "ElysiumInit", true) == 1 and F.last(p[1], "ElysiumInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.last(p[1], "ElysiumInit")[5] == 1 and F.last(p[1], "ElysiumInit")[6] == 2, "the weather starts calm and drifts to haze")
    check(F.count(p[2], "ElysiumInit", false) == 1, "guests render only (not the authority)")
    check(F.count(p[1], "ElysiumAnnounce") == 1 and F.count(p[2], "ElysiumAnnounce") == 0, "the leader announces its weather state once")
    check(F.count(p[1], "EnvironmentInit") == 1 and F.last(p[1], "EnvironmentInit")[2].lightingMode == "subtle", "the default lighting is initialised")
    for i = 2, 3 do
        local e = F.last(p[i], "ElysiumEvent")
        check(e and e[2] == "VenusStrike", "weather events reach guest " .. i)
    end
    check(F.count(p[1], "WeatherSensors") == 0, "the Venus engine owns the sensor modifier: nothing is bound here")
    check(p[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    F.run(15)
    local t0 = briefedAt(p[1])
    check(F.count(p[1], "ElysiumLevel") == 0, "calm until the first wave")
    F.runUntil(function() return w.now > t0 + 125 end)
    check(F.count(p[1], "ElysiumLevel", 3) == 1, "the first wave closes the sky in")
    F.runUntil(function() return w.now > t0 + 155 end)
    check(F.count(p[1], "ElysiumLevel", 4) == 1, "the second wave breaks the storm")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "ElysiumShutdown") >= 1 and F.count(p[1], "ElysiumLoad", true) == 1, "load restores the leader's weather state")
    killAll(WAVE1); killAll(WAVE2); F.run(5)
    check(F.count(p[1], "ElysiumCreated") > 0, "new objects are offered to the weather")
    local strikes = F.callsOf(p[1], "ElysiumStrike")
    local nav = F.world().objects["nav_chinbase"].pos
    check(strikes[1] and strikes[1][2] == nav.x and strikes[1][3] == nav.z, "the go-ahead: lightning over the Chinese base")
    check(#strikes == 2, "...and one strike under the first raid, got " .. #strikes)
    F.run(300)
    check(#F.callsOf(p[1], "ElysiumStrike") == 3, "every raid arrives under a strike")
    killAll(TARGETS); F.run(5)
    check(F.count(p[1], "ElysiumLevel", 2) == 1, "the victory eases the weather")
end
do -- the beats are tied to the story, not to the clock
    local sites = dofile("Scripts/CRElysiumSitesBD07.lua")
    local w, p, m = setup(1, { weather = { module = function(peer, record) return elysium(record, nil)(peer) end, sites = sites } })
    F.run(20); killAll(WAVE1); killAll(WAVE2); F.run(2)
    check(F.count(p[1], "ElysiumLevel", 3) == 0 and F.count(p[1], "ElysiumLevel", 4) == 1, "waves beaten before they set out: straight to the storm of the go-ahead")
end
do -- sites module missing: no weather, never an error
    local sites = dofile("Scripts/CRElysiumSitesBD07.lua")
    local w, p, m = setup(2, { weather = { module = function(peer, record) return elysium(record, nil)(peer) end } })
    check(F.count(p[1], "ElysiumInit") == 0 and m.startDone, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local sites = dofile("Scripts/CRElysiumSitesBD07.lua")
    local w, p, m = setup(2, { weather = { module = function(peer, record) return elysium(record, mode)(peer) end, sites = sites } })
    F.run(20); killAll(WAVE1); killAll(WAVE2); F.run(10)
    check(#builtAt(p[1], "annoy_1") == 5 + 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("bdmisn07 co-op: " .. checks .. " checks passed")
