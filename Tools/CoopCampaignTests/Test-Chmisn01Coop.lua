-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/ch01cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/CoopCampaignTests/Test-Chmisn01Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/CoopCampaignTests/Chmisn01Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local SCALED = { svfigh = true, svtank = true, svltnk = true, svhraz = true, svturrb = true }
local function extrasFor(n) return math.min(math.floor(n / 2), 2) end
local function run(seconds) F.run(seconds, 0.5) end

local function setup(n, options)
    options = options or {}
    local w = F.reset()
    w.audioBusy = options.busy == true
    w.realTimer = options.faithful == true
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); run(1)
    return w, p, p[1].env.Save()
end
local function lead(p, m) return p[1].player end

-- ------------------------------------------------------------------ scripted steps (shared by every scenario)
-- Opening line, "CCA Base" nav, hangar inspected, armoury delivered.
local function reachArmoury(w, p, m)
    run(7)
    p[#p].info.sbhanga = true; run(1); p[#p].info.sbhanga = false
    run(18)
end
-- The comm array falls: the Recycler arrives.
local function reachRecycler(w, p, m)
    reachArmoury(w, p, m)
    F.kill("target_2"); run(1)
end
local function reachDeployed(w, p, m)
    reachRecycler(w, p, m)
    w.objects[m.recycler].deployed = true; run(1)
end
-- wave 1 +60 s, wave 2 +300, wave 3 +300, aerial 1 +180, aerial 2 +30, wave 4 +60, tug +120
local function reachTug(w, p, m)
    reachDeployed(w, p, m)
    run(60 + 300 + 300 + 180 + 30 + 60 + 120 + 6)
end
local function killEnemies(m)
    for _, h in ipairs(m.crcca.live) do if F.alive(h) then F.kill(h) end end
end
-- A human (default the host) steals the tug and brings it home to the Recycler.
local function captureTug(w, p, m, who)
    who = who or 1
    w.objects[m.tug].team = p[who].team
    F.nearTo(m.tug, "nav_tug", 0, 0); run(1)
    F.nearTo(m.tug, m.recycler, 10, 0); run(1)
end
-- Every human stands next to the tug (a convoy).
local function gather(p, m, spread)
    for i, q in ipairs(p) do F.nearTo(q.player, m.tug, (i - 1) * (spread or 10), 0) end
end
local function escortParty(w, p, m, leadIndex)
    F.follow(m.escort1, p[leadIndex or 1].player); F.follow(m.escort2, p[leadIndex or 1].player)
end
local function takeRelic(w, p, m)
    w.cargo[m.tug] = m.relic; run(1)
end
-- Everything is quiet: the safe-distance run ends the way the test asks.
local function relicSafe(w, m) F.nearTo(m.relic, "nav_end", 0, 0) end

local function scaledBuilds(peer, mark)
    local out = {}
    for _, b in ipairs(F.builds(peer, mark or 0)) do
        if SCALED[b.odf] and type(b.where) == "string" then out[#out + 1] = b end
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
            check(q.env.GetDistance(q.player, b.h) >= 460, "no scripted unit is built within 460 m of any human")
        end
    end
end
local function heardAll(p, file, count)
    for i, q in ipairs(p) do check(F.heardCount(q, file) == (count or 1), "peer " .. i .. " hears " .. file .. " x" .. (count or 1)) end
end
local function guestsPassive(p)
    for i = 2, #p do
        for _, name in ipairs({"BuildObject", "SetScrap", "SetAIP", "Goto", "Attack", "Defend2", "SetIndependence", "AddScrap"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on the authored enemy team 2") end
    -- a perceived team is the co-op enemy (never the DLL's literal 2) or the human's own team (guests are 2-4)
    for _, c in ipairs(F.callsOf(peer, "SetPerceivedTeam")) do
        check(c[3] == 5 or c[3] == F.team(c[2]), "perceived team 5 or the object's own team, got " .. tostring(c[3]))
    end
end
local function noBadPath(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.where ~= "M.recycler", "the Recycler is never built at the port's slipped path") end
end

-- ------------------------------------------------------------------ offline == faithful
local function outcomes(options, scenario)
    local w, p, m = setup(1, options)
    scenario(w, p, m)
    local out = {}
    for _, name in ipairs({"SucceedMission", "FailMission"}) do
        for _, c in ipairs(F.callsOf(p[1], name)) do out[#out + 1] = name .. ":" .. tostring(c[3]) end
    end
    return table.concat(out, ","), p[1], w
end
local function winRun(w, p, m)
    reachTug(w, p, m)
    captureTug(w, p, m); escortParty(w, p, m); run(1)
    takeRelic(w, p, m); relicSafe(w, m)
    run(185)
end
local scenarios = {
    win = winRun,
    tugKilled = function(w, p, m) reachTug(w, p, m); F.kill(m.tug); run(3) end,
    tugEscaped = function(w, p, m) reachTug(w, p, m); F.nearTo(m.tug, "tug_fail", 10, 0); run(3) end,
    recyclerLost = function(w, p, m) reachDeployed(w, p, m); F.kill(m.recycler); run(3) end,
    detected = function(w, p, m)
        reachTug(w, p, m); captureTug(w, p, m)
        F.nearTo(p[1].player, "sp_tower_1", 40, 0); run(3)
    end,
    blastLoss = function(w, p, m)
        reachTug(w, p, m); captureTug(w, p, m); escortParty(w, p, m); run(1)
        takeRelic(w, p, m); F.nearTo(m.relic, "target_1", 100, 0); F.nearTo(p[1].player, "nav_end", 0, 0); run(185)
    end,
}
local names = {}
for name in pairs(scenarios) do names[#names + 1] = name end
table.sort(names)
local results = {}
for _, name in ipairs(names) do
    local faithful = outcomes({ faithful = true, script = "Scripts/ch01.lua" }, scenarios[name])
    local offline = outcomes({}, scenarios[name])
    check(faithful == offline and faithful ~= "", "offline completes like the faithful port (" .. name .. "): " .. faithful .. " / " .. offline)
    results[name] = offline
end
check(results.win:match("^SucceedMission:ch01win%.des$"), "offline victory: " .. results.win)
check(results.tugKilled == "FailMission:ch01lseb.des", "offline tug lost: " .. results.tugKilled)
check(results.tugEscaped == "FailMission:ch01lsea.des", "offline tug escaped: " .. results.tugEscaped)
check(results.recyclerLost == "FailMission:ch01lsed.des", "offline recycler lost: " .. results.recyclerLost)
check(results.detected == "FailMission:ch01lsec.des", "offline detected: " .. results.detected)
check(results.blastLoss == "FailMission:ch01lsee.des", "offline relic too close: " .. results.blastLoss)
do
    local _, peer = outcomes({}, scenarios.win)
    check(F.count(peer, "SucceedMission") == 1 and F.count(peer, "FailMission") == 0, "offline: one result")
    noEnemyTeamTwo(peer); noBadPath(peer)
    check(F.count(peer, "SetAIControl", 5) == 1 and F.count(peer, "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
    check(F.index(peer, "SetAIControl") <= peer.chunkCalls, "SetAIControl runs at chunk root, before Start")
end

-- ------------------------------------------------------------------ teams, ownership, the shared start
for n = 1, 4 do
    local w, p, m = setup(n, {})
    check(m.startDone and m.coopMissionStarted, "the host starts the shared mission")
    check(m.user == "crcca_players", "the body's player is the nearest-human token")
    local scrap = F.last(p[1], "SetScrap")
    check(F.count(p[1], "SetScrap") == 1 and scrap[2] == 1 and scrap[3] == 0, "the mission starts with no scrap, guests add none")
    check(F.count(p[1], "SetPilot") == n, n .. " human(s): pilots for every human team")
    check(F.count(p[1], "SetAIP") == 0, "this mission has no AIP")
    for i = 1, n do
        check(F.count(p[i], "DisableStartingRecycler") == (n > 1 and 1 or 0), "extra starting recyclers disabled in a network game, peer " .. i)
    end
    run(8)
    heardAll(p, "ch01001.wav")
    for i = 1, n do
        local cloak = F.last(p[i], "EnableAllCloaking")
        check(cloak ~= nil and cloak[2] == false, "cloaking is disabled on peer " .. i)
        local o = F.callsOf(p[i], "AddObjective")
        check(o[1] and o[1][2] == "ch01001.otf" and o[1][3] == "white", "first objective on peer " .. i)
    end
    local nav = F.builds(p[1], 0, "cpcamr")
    check(#nav == 1 and nav[1].team == 1 and nav[1].where == "nav_start", "the CCA Base nav is built once on team 1")
    for i = 1, n do check(F.count(p[i], "SetObjectiveName", m.navStart) == 1, "the nav is named on peer " .. i) end
    if n > 1 then check(p[1].rally and p[1].rally[0] == "recycler", "respawn rally point is the Chinese beachhead") end
    guestsPassive(p)
end

-- ------------------------------------------------------------------ the hangar inspection (local UI state)
for n = 2, 4 do
    local w, p, m = setup(n, {})
    run(8)
    p[n].info.sbhanga = true; run(1)
    check(m.hangarIdentified and m.objective1Complete, n .. " humans: the last guest inspecting the hangar completes the objective")
    check(F.count(p[n], "Send", "I") >= 1, "the guest reports its inspection")
    p[n].info.sbhanga = false
    run(2)
    heardAll(p, "ch01002.wav")
    local greens = 0
    for _, c in ipairs(F.callsOf(p[2], "AddObjective")) do if c[2] == "ch01001.otf" and c[3] == "green" then greens = greens + 1 end end
    check(greens == 1, "the objective turns green on the guest")
    run(17)
    heardAll(p, "ch01003.wav")
    run(2)
    check(#F.builds(p[1], 0, "cvslfb") == 1 and F.builds(p[1], 0, "cvslfb")[1].team == 1, "the armoury is delivered once on team 1")
    heardAll(p, "ch01004.wav")
    check(F.count(p[1], "AddScrap", 1) == 1 and F.last(p[1], "AddScrap")[3] == 99, "99 scrap")
    guestsPassive(p)
end
do -- a stranger's report (a non-human sender) and an unknown ODF change nothing
    local w, p, m = setup(2, {})
    run(8)
    p[1].env.Receive(2, "I", "sbcomm"); run(1)
    check(not m.hangarIdentified, "an ODF the layer does not relay is ignored")
    p[1].env.Receive(9, "I", "sbhanga"); run(1)
    check(not m.hangarIdentified, "a sender that is not a human is ignored")
    p[1].env.Receive(2, "I", "sbhanga"); run(1)
    check(m.hangarIdentified, "a human guest's report counts")
end

-- ------------------------------------------------------------------ the comm array, the Recycler, the restored objectives
for n = 1, 4 do
    local w, p, m = setup(n, {})
    reachRecycler(w, p, m)
    check(m.objective2Complete and F.alive(m.recycler), "the Recycler is delivered when the comm array falls")
    local rec = F.builds(p[1], 0, "cvrecyd")
    check(#rec == 1 and rec[1].team == 1 and rec[1].where == "recycler", "the Recycler is built once, at the path 'recycler' (not the port's slip)")
    noBadPath(p[1])
    heardAll(p, "ch01005.wav")
    for i = 1, n do
        local c = F.last(p[i], "AddObjective")
        check(c[2] == "ch01006.otf" and c[3] == "white", "restored: 'Deploy your Recycler' is the open objective on peer " .. i)
    end
    w.objects[m.recycler].deployed = true; run(1)
    for i = 1, n do
        local c = F.last(p[i], "AddObjective")
        check(c[2] == "ch01007.otf" and c[3] == "white", "restored: 'Protect your Recycler' follows the deployment on peer " .. i)
    end
    local before = F.count(p[1], "AddObjective")
    run(5)
    check(F.count(p[1], "AddObjective") == before, "the restored objectives are published once")
    check(m.wave1Time < 1e9, "the deployment starts the wave clock")
end

-- ------------------------------------------------------------------ the waves: scaling, no pop-in, orders
for n = 1, 4 do
    local e = extrasFor(n)
    local w, p, m = setup(n, {})
    reachDeployed(w, p, m)
    local mark = #p[1].calls
    run(66)
    local wave1 = at(scaledBuilds(p[1], mark), "wave_1")
    check(#wave1 == 8 + e, n .. " human(s): wave 1 = 8 + " .. e .. " extras, got " .. #wave1)
    allSafe(p, wave1)
    for _, b in ipairs(wave1) do check(b.team == 5, "wave 1 is the co-op enemy") end
    local gotos = 0
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[3] == "follow_1" and c[4] == 1 then gotos = gotos + 1 end end
    check(gotos == 8 + e, "every wave-1 unit (extras included) takes the follow_1 order: " .. gotos)
    killEnemies(m)
    mark = #p[1].calls
    run(300)
    local wave2 = at(scaledBuilds(p[1], mark), "wave_2")
    check(#wave2 == 9 + e, n .. " human(s): wave 2 = 9 + " .. e .. ", got " .. #wave2)
    killEnemies(m)
    mark = #p[1].calls
    run(300)
    check(#at(scaledBuilds(p[1], mark), "wave_3") == 12 + e, n .. " human(s): wave 3 = 12 + " .. e)
    killEnemies(m)
    -- the paratroopers: built at a height, not scaled
    mark = #p[1].calls
    run(185)
    local pilots = F.builds(p[1], mark, "sspilo")
    check(#pilots == 6, "six paratrooper pilots: " .. #pilots)
    for _, b in ipairs(pilots) do
        check(b.team == 5 and type(b.where) == "table" and b.where.y == F.PATHS.aerial_1[2] + 200, "pilots drop 200 m over aerial_1 on team 5")
    end
    run(32)
    check(#F.builds(p[1], mark, "sssold") == 4, "four paratrooper soldiers")
    local attacks = 0
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do if c[3] == m.recycler and c[4] == 1 then attacks = attacks + 1 end end
    check(attacks == 10, "every paratrooper attacks the Recycler: " .. attacks)
    killEnemies(m)
    mark = #p[1].calls
    run(62)
    check(#at(scaledBuilds(p[1], mark), "wave_4") == 12 + e, n .. " human(s): wave 4 = 12 + " .. e)
    killEnemies(m)
    mark = #p[1].calls
    run(122)
    local tug = F.builds(p[1], mark, "svhaula")
    check(#tug == 1 and tug[1].team == 5 and tug[1].where == "relic_tug" and type(m.tug) == "string", "the tug is one direct enemy unit")
    check(F.count(p[1], "Goto", m.tug) == 1, "the tug rolls down tug_path")
    local defenders = at(scaledBuilds(p[1], mark), "tug_defend")
    check(#defenders == 2 + e, n .. " human(s): the tug's escort = 2 + " .. e)
    for _, b in ipairs(defenders) do
        check(F.count(p[1], "Defend2", b.h) == 1, "each defender guards the tug")
    end
    allSafe(p, scaledBuilds(p[1], mark))
    noEnemyTeamTwo(p[1]); noBadPath(p[1])
    guestsPassive(p)
end
do -- a human at the wave entry gets the wave from the next hidden approach; nobody anywhere waits
    local w, p, m = setup(2, {})
    reachDeployed(w, p, m)
    F.nearTo(p[2].player, "wave_1", 0, 0)
    local mark = #p[1].calls
    run(66)
    local wave1 = scaledBuilds(p[1], mark)
    check(#wave1 == 8 + 1 and #at(wave1, "wave_1") == 0 and #at(wave1, "wave_5") == 9, "the watched entry yields to the next safe one (wave_5)")
    allSafe(p, wave1)
end
do
    local w, p, m = setup(2, {})
    reachDeployed(w, p, m)
    F.nearTo(p[1].player, "wave_1", 0, 0); F.nearTo(p[2].player, "wave_5", 0, 0)
    local mark = #p[1].calls
    run(66)
    check(#scaledBuilds(p[1], mark) == 0, "every approach watched: the wave waits")
    local pending = m.crcca.serial
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); run(3)
    check(m.crcca.serial == pending and #scaledBuilds(p[1], mark) == 0, "save/load keeps the pending wave without duplicating it")
    F.place(p[1].player, 3000, 100000); F.place(p[2].player, 3000, 100000); run(6)
    check(#scaledBuilds(p[1], mark) == 8 + 1, "the whole wave is built exactly once when the watchers leave")
end

-- ------------------------------------------------------------------ the tug, the capture, the escorts
for n = 1, 4 do
    local e = extrasFor(n)
    local w, p, m = setup(n, {})
    reachTug(w, p, m)
    F.nearTo(m.tug, "nav_tug", 0, 0); run(1)
    check(m.tugNearNav, "the tug reaches the nav")
    heardAll(p, "ch01006.wav")
    local navTug = F.builds(p[1], 0, "cpcamr")
    check(#navTug == 2 and navTug[2].where == "nav_tug" and navTug[2].team == 1, "the sniper nav is built on team 1")
    local last = F.last(p[n], "AddObjective")
    check(last[2] == "ch01003.otf" and last[3] == "white", "get the tug home")
    -- the tug is still the CCA's (team 5 here, 2 for the body): no loss while it rolls
    check(not m.lost and F.count(p[1], "FailMission") == 0, "an enemy tug at the nav is not a failure")
    killEnemies(m)
    local mark = #p[1].calls
    w.objects[m.tug].team = p[n].team -- the last guest snipes the pilot and drives off
    F.nearTo(m.tug, m.recycler, 80, 0); run(1)
    check(not m.objective3Complete, "80 m from the Recycler is not home yet (75 m)")
    F.nearTo(m.tug, m.recycler, 10, 0); run(8)
    check(m.objective3Complete, n .. " humans: the last guest bringing the tug home starts the infiltration")
    heardAll(p, "ch01007.wav")
    local esc = F.builds(p[1], mark, "svfigh")
    local escorts = {}
    for _, b in ipairs(esc) do if b.where == "fighters" then escorts[#escorts + 1] = b end end
    check(#escorts == 2 and escorts[1].team == 1 and escorts[2].team == 1, "two captured fighters, built directly on team 1")
    check(F.perceived(m.escort1) == 5 and F.perceived(m.escort2) == 5, "the escorts are perceived as the CCA (5, never 2)")
    check(F.count(p[1], "SetIndependence", m.escort1) == 1 and F.count(p[1], "Goto", m.escort1) == 1, "escorts are told to wait at fighters_to")
    local relic = F.builds(p[1], mark, "obdata")
    check(#relic == 1 and relic[1].team == 0 and relic[1].where == "relic_loc", "the relic is spawned for nobody at relic_loc")
    local w5 = at(scaledBuilds(p[1], mark), "wave_5")
    check(#w5 >= 16 and #w5 <= 16 + e, n .. " human(s): the base reinforcements = 16 + up to " .. e .. ", got " .. #w5)
    allSafe(p, w5)
    for i = 1, n do
        local c = F.last(p[i], "AddObjective")
        check(c[2] == "ch01004.otf" and c[3] == "white", "infiltration objective on peer " .. i)
    end
    guestsPassive(p)
end

-- ------------------------------------------------------------------ the cover is one for the party
do
    local w, p, m = setup(3, {})
    reachTug(w, p, m); captureTug(w, p, m, 2)
    gather(p, m, 10); run(1)
    -- nobody commanded the fighters yet: every human is perceived as their own team
    for i = 1, 3 do check(F.perceived(p[i].player) == i, "no escort, no cover: human " .. i .. " is perceived as its own team") end
    escortParty(w, p, m, 2); run(1)
    for i = 1, 3 do
        check(F.perceived(p[i].player) == 5, "the convoy is perceived as the CCA on peer's human " .. i)
        for j = 1, 3 do
            local last
            for _, c in ipairs(F.callsOf(p[j], "SetPerceivedTeam")) do if c[2] == p[i].player then last = c end end
            check(last ~= nil and last[3] == 5, "peer " .. j .. " applies the cover to human " .. i)
        end
    end
    local calls = F.count(p[1], "SetPerceivedTeam")
    run(5)
    check(F.count(p[1], "SetPerceivedTeam") == calls, "an unchanged cover is not re-published every frame")
    -- a straggler breaks the party's cover
    F.nearTo(p[3].player, m.tug, 250, 0); run(1)
    for i = 1, 3 do check(F.perceived(p[i].player) == i, "a human 250 m from the convoy uncovers everyone") end
    F.nearTo(p[3].player, m.tug, 30, 0); run(1)
    for i = 1, 3 do check(F.perceived(p[i].player) == 5, "rejoining the convoy restores the cover") end
    -- only one fighter following is not an escort
    F.follow(m.escort2, nil); run(1)
    for i = 1, 3 do check(F.perceived(p[i].player) == i, "one fighter is not an escort") end
    F.follow(m.escort2, p[2].player); run(1)
    -- a respawned human (new handle) is covered again
    local spawned = F.spawn("csusera", 3, 2900, 100400)
    p[3].player = spawned; F.world().objects[p[3].player].craft = true
    F.nearTo(p[3].player, m.tug, 30, 0); run(4)
    check(F.perceived(spawned) == 5, "a new human handle gets the cover")
    -- detected: uncovered and within 150 m of a detector
    F.follow(m.escort1, nil); F.nearTo(p[1].player, "sp_tower_1", 120, 0)
    F.nearTo(p[2].player, "sp_tower_1", 130, 0); F.nearTo(p[3].player, "sp_tower_1", 140, 0)
    run(2)
    check(m.lost and m.arialsSpawned, "uncovered next to a detector: the cover is blown")
    heardAll(p, "ch01008.wav")
    run(2)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "ch01lsec.des", "one shared failure on peer " .. i)
    end
    noEnemyTeamTwo(p[1])
end
do -- covered next to a detector: the reinforcements come, the cover holds
    local w, p, m = setup(2, {})
    reachTug(w, p, m); captureTug(w, p, m, 1); gather(p, m, 10); escortParty(w, p, m, 1); run(1)
    local mark = #p[1].calls
    F.nearTo(p[1].player, "sp_tower_1", 120, 0); F.nearTo(p[2].player, "sp_tower_1", 130, 0); run(2)
    check(m.arialsSpawned and not m.lost, "a covered party is not detected")
    local aerial = 0
    for _, b in ipairs(F.builds(p[1], mark)) do if b.odf == "sspilo" or b.odf == "sssold" then aerial = aerial + 1; check(b.team == 5 and type(b.where) == "table", "paratroopers drop on team 5 at a height") end end
    check(aerial == 10, "ten paratroopers answer the approach: " .. aerial)
    run(5)
    check(F.count(p[1], "FailMission") == 0, "no failure while covered")
end

-- ------------------------------------------------------------------ the relic, the decoys, the countdown, the blast
local function reachRelic(n, options)
    local w, p, m = setup(n, options or {})
    reachTug(w, p, m); captureTug(w, p, m, n > 1 and 2 or 1); gather(p, m, 10); escortParty(w, p, m, n > 1 and 2 or 1); run(1)
    killEnemies(m)
    takeRelic(w, p, m)
    return w, p, m
end
for n = 1, 4 do
    local w, p, m = reachRelic(n)
    check(m.objective4Complete and m.navEnd ~= nil, "the relic aboard completes the objective")
    for i = 1, n do
        check(F.count(p[i], "SetObjectiveName", m.navEnd) == 1, "'Safe Distance' is named on peer " .. i)
        check(F.count(p[i], "SetObjectiveOn", m.navEnd) == 1, "the safe nav is marked on peer " .. i)
        local t = F.last(p[i], "StartCockpitTimer")
        check(t ~= nil and t[2] == 180 and t[3] == 15 and t[4] == 5, "the 180 s countdown starts on peer " .. i)
        local c = F.last(p[i], "AddObjective")
        check(c[2] == "ch01005.otf" and c[3] == "white", "evacuation objective on peer " .. i)
    end
    -- decoys: once, when any human is within 300 m of a detector
    check(not m.decoySpawned, "no decoys while everyone is far from the detectors")
    F.nearTo(p[n].player, "sp_tower_1", 250, 0); run(1)
    check(m.decoySpawned, n .. " humans: ONE human within 300 m of a detector triggers the decoys")
    heardAll(p, "ch01009.wav")
    local decoys = F.builds(p[1], 0, "cvhtnk")
    check(#decoys == 7 and decoys[1].team == 1 and decoys[1].where == "decoy_units", "seven decoy tanks on team 1")
    check(F.count(p[1], "Goto") >= 7, "the decoys are sent at the detectors")
    run(2)
    check(#F.builds(p[1], 0, "cvhtnk") == 7, "the decoys come once")
    -- the party stays far enough away from the blast for the film
    for _, q in ipairs(p) do F.nearTo(q.player, "nav_end", 0, 0) end
    relicSafe(w, m)
    run(172)
    heardAll(p, "ch01010.wav") -- restored: before the blast, once
    local line = F.index(p[1], "Play", "ch01010.wav")
    check(line ~= nil and not m.doingExplosion, "the restored line plays ahead of the blast")
    run(7)
    check(m.doingExplosion or m.won, "the countdown ends the mission")
    for i = 1, n do
        check(F.count(p[i], "ColorFade") == 1, "the white flash plays on peer " .. i)
        local boom = F.last(p[i], "MakeExplosion")
        check(boom ~= nil and boom[2] == "xpltrsn" and boom[3] == "relic_loc", "the blast goes off at the relic (the map has no spawn_explosion1) on peer " .. i)
        check(F.count(p[i], "HideCockpitTimer") == 1, "the countdown is hidden on peer " .. i)
    end
    run(6)
    for i = 1, n do
        check(F.count(p[i], "SucceedMission") == 1 and F.count(p[i], "FailMission") == 0, "one shared victory on peer " .. i)
        check(F.last(p[i], "SucceedMission")[3] == "ch01win.des", "victory debrief on peer " .. i)
        check((p[i].env.Save().coopUnresolved or 0) == 0, "no unresolved presentation identities on peer " .. i)
        check(p[i].camera == 0, "cameras balanced on peer " .. i)
    end
    check(F.count(p[1], "CameraReady") == 1, "the blast shot opens once")
    local shot = F.callsOf(p[1], "CameraPath")
    check(shot[1][2] == "cut_end" and shot[1][3] == 3000 and shot[1][4] == 0 and shot[1][5] == "bb_tower", "the shot is the old tower seen from cut_end")
    for i = 2, n do check(F.count(p[i], "CameraPath") >= 1 and p[i].camera == 0, "guest " .. i .. " saw the same shot") end
    guestsPassive(p)
    noEnemyTeamTwo(p[1])
end
do -- cinematics are shared and unskippable in a network game, skippable offline
    local w, p, m = reachRelic(3)
    for _, q in ipairs(p) do F.nearTo(q.player, "nav_end", 0, 0) end
    relicSafe(w, m)
    run(179)
    check(m.focusOnExplosion and p[1].camera == 1 and p[3].camera == 1, "the blast shot is running everywhere")
    w.cancel = true; run(1); w.cancel = false
    check(m.focusOnExplosion, "a skip never ends the shared blast shot in a network game")
    check(p[1].camera == 0, "a skip releases only the skipper's own camera")
    run(8)
    check(not m.focusOnExplosion, "the shot ends at its own time (three seconds after the blast)")
end
do
    local w, p, m = reachRelic(1)
    F.nearTo(p[1].player, "nav_end", 0, 0); relicSafe(w, m)
    run(178)
    check(m.focusOnExplosion and p[1].camera == 1, "offline: the blast shot runs")
    w.cancel = true; run(1); w.cancel = false
    check(not m.focusOnExplosion and p[1].camera == 0, "offline: the blast shot is skippable")
end
do -- a human near the hangar when it blows: no film, the relic distance still decides
    local w, p, m = reachRelic(2)
    relicSafe(w, m)
    F.nearTo(p[1].player, "target_1", 100, 0); F.nearTo(p[2].player, "nav_end", 0, 0)
    run(192)
    check(F.count(p[1], "CameraReady") == 0, "someone inside the blast radius: no film")
    check(F.count(p[1], "SucceedMission") == 1, "the relic's distance, not the humans', decides the result")
end
do -- the relic left near the hangar: shared failure
    local w, p, m = reachRelic(3)
    F.nearTo(m.relic, "target_1", 100, 0)
    for _, q in ipairs(p) do F.nearTo(q.player, "nav_end", 0, 0) end
    run(192)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "ch01lsee.des", "blast failure on peer " .. i)
        check(F.count(p[i], "SucceedMission") == 0, "no victory on a loss")
    end
end

-- ------------------------------------------------------------------ defeats
do -- the tug dies: its line, then one shared failure
    local w, p, m = setup(3, {})
    reachTug(w, p, m)
    F.kill(m.tug); run(2)
    heardAll(p, "ch01011.wav")
    run(4)
    for i = 1, 3 do check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "ch01lseb.des", "tug-lost failure on peer " .. i) end
    local before = #F.builds(p[1])
    run(20)
    check(#F.builds(p[1]) == before, "no reinforcement is built after the failure")
end
do -- the tug reaches the CCA hangar uncaptured (it is team 5 here, team 2 in the body)
    local w, p, m = setup(3, {})
    reachTug(w, p, m)
    F.nearTo(m.tug, "tug_fail", 100, 0); run(3)
    for i = 1, 3 do check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "ch01lsea.des", "escape failure on peer " .. i) end
end
do -- a captured tug may enter the CCA hangar area
    local w, p, m = setup(2, {})
    reachTug(w, p, m)
    w.objects[m.tug].team = 2
    F.nearTo(m.tug, "tug_fail", 100, 0); run(3)
    check(F.count(p[1], "FailMission") == 0, "a tug on a human team is not 'got away'")
end
do -- the Recycler dies before the infiltration
    local w, p, m = setup(3, {})
    reachDeployed(w, p, m)
    F.kill(m.recycler); run(3)
    for i = 1, 3 do check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "ch01lsed.des", "Recycler-lost failure on peer " .. i) end
end
do -- a win cannot be overwritten, a loss cannot be won
    local w, p, m = reachRelic(2)
    for _, q in ipairs(p) do F.nearTo(q.player, "nav_end", 0, 0) end
    relicSafe(w, m)
    run(192)
    check(F.count(p[1], "SucceedMission") == 1, "won")
    F.kill(m.tug); run(5)
    check(F.count(p[1], "FailMission") == 0, "a tug lost after the victory is not a failure")
end
do -- the decoy order needs a live target: destroyed detectors are skipped, never an error
    local w, p, m = reachRelic(2)
    for _, label in ipairs({"sp_turret_1", "sp_turret_2", "sp_turret_3", "sp_tower_2", "sp_tower_3", "sp_tower_4", "sp_tower_5", "sp_tower_6", "sp_tower_7"}) do F.kill(label) end
    F.nearTo(p[1].player, "sp_tower_1", 250, 0); run(2)
    check(m.decoySpawned and #F.builds(p[1], 0, "cvhtnk") == 7, "the decoys come with one detector left")
    local targets = 0
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[3] == "sp_tower_1" then targets = targets + 1 end end
    check(targets <= 7, "orders aim only at the live detector")
    local printed = false
    for _, c in ipairs(p[1].calls) do if c[1] == "print" and tostring(c[2]):find("failed", 1, true) then printed = true end end
    check(not printed, "no layer error")
end

-- ------------------------------------------------------------------ saves and loads
do -- a load during the countdown republishes objectives, the clock and the disguise
    local w, p, m = reachRelic(2)
    for _, q in ipairs(p) do F.nearTo(q.player, "nav_end", 0, 0) end
    relicSafe(w, m)
    run(60)
    local timers, covers, objectives = F.count(p[1], "StartCockpitTimer"), F.count(p[2], "SetPerceivedTeam"), F.count(p[2], "AddObjective")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); run(3)
    check(F.count(p[1], "StartCockpitTimer") == timers + 1, "the load shows the remaining countdown again")
    local t = F.last(p[2], "StartCockpitTimer")
    check(t[2] > 110 and t[2] < 125, "...with the true remaining time: " .. tostring(t[2]))
    check(F.count(p[2], "SetPerceivedTeam") > covers, "the cover is applied again after a load")
    check(F.count(p[2], "AddObjective") > objectives, "the objective list is published again")
    local c = F.last(p[2], "AddObjective")
    check(c[2] == "ch01005.otf" and c[3] == "white", "the list is the saved one")
    run(130)
    check(F.count(p[1], "SucceedMission") == 1, "the saved countdown still ends the mission")
end
do -- a load during the blast shot gets the camera back
    local w, p, m = reachRelic(2)
    for _, q in ipairs(p) do F.nearTo(q.player, "nav_end", 0, 0) end
    relicSafe(w, m)
    run(178)
    check(m.focusOnExplosion and p[1].camera == 1, "the shot is running")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); run(1)
    check(p[1].camera == 1, "the host's blast shot is restored after a load")
    run(10)
    for i = 1, 2 do check(p[i].camera == 0, "cameras balanced after the shot on peer " .. i) end
end

-- ------------------------------------------------------------------ leader leaves
do
    local w, p, m = setup(3, {})
    for i = 2, 3 do p[i].env.DeletePlayer(1) end
    run(3)
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
        local V = { Seed = 4242, level = 1 }
        function V.Init(o) peer.weatherInit = o; record("EuropaInit", o.authority, o.send ~= nil, o.seed, o.startLevel, o.targetLevel); if mode == "initfail" then error("boom") end end
        function V.Update(dt)
            if peer.weatherInit and peer.weatherInit.authority and peer.weatherInit.send and not V.sent then
                V.sent = true; peer.weatherInit.send("EuropaQuake", 3, 4)
            end
            if mode == "updatefail" then error("update boom") end
        end
        function V.AnnounceState() record("EuropaAnnounce") end
        function V.ApplyNetEvent(op, ...) record("EuropaEvent", op, ...) end
        function V.SetTargetLevel(n) V.level = n; record("EuropaLevel", n) end
        function V.GetTargetLevel() return V.level end
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
    local sites = dofile("Scripts/CRGanymedeSitesCH01.lua")
    check(sites.mission == "chmisn01" and #sites.vents == 7 and sites.vents[1].label == "eggeizr19_geyser", "the generated sites carry the seven map geysers")
    local weather = { module = function(peer, record) return europa(record, nil, sites.vents)(peer) end, sites = sites }
    local w, p, m = setup(3, { weather = weather })
    run(3)
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
    reachRecycler(w, p, m)
    check(F.count(p[1], "EuropaLevel", 2) == 1 and F.count(p[1], "EuropaQuakeCall") == 1, "the comm array's fall stirs the vapour and shakes the ice")
    w.objects[m.recycler].deployed = true; run(1)
    check(F.count(p[1], "EuropaLevel", 3) == 1 and F.count(p[1], "EuropaPlume", 5) == 1, "the deployment raises the weather and blows the beachhead geyser")
    run(60 + 300 + 300 + 180 + 30 + 60 + 120 + 6)
    F.nearTo(m.tug, "nav_tug", 0, 0); run(1)
    check(F.count(p[1], "EuropaSurgeCall") == 1, "the inbound tug brings a surge")
    check(F.count(p[1], "EuropaCreated") > 0, "new objects are offered to the weather")
    captureTug(w, p, m, 2); gather(p, m, 10); escortParty(w, p, m, 2); run(1)
    killEnemies(m)
    takeRelic(w, p, m)
    check(F.count(p[1], "EuropaLevel", 4) == 1 and F.count(p[1], "EuropaQuakeCall") == 2, "the relic aboard brings the heaviest rung")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); run(3)
    check(F.count(p[1], "EuropaShutdown") >= 1 and F.count(p[1], "EuropaLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(p[1], "EuropaLevel", 4) == 1 and F.count(p[1], "EuropaQuakeCall") == 2, "beats are not repeated after a load")
    for _, q in ipairs(p) do F.nearTo(q.player, "nav_end", 0, 0) end
    relicSafe(w, m)
    run(190)
    check(F.count(p[1], "EuropaPlume", 1) == 1 and F.count(p[1], "EuropaSurgeCall") == 2, "the blast blows the base vent")
    run(6)
    check(F.count(p[1], "EuropaRelease") == 1 and F.count(p[1], "EuropaLevel", 1) == 1, "the victory eases the sky back")
end
do -- a site list with too few vents: the plumes are skipped, the rest of the weather still follows
    local weather = { module = function(peer, record) return europa(record, nil, {})(peer) end, sites = { mission = "chmisn01", vents = {} } }
    local w, p, m = setup(2, { weather = weather })
    reachDeployed(w, p, m)
    check(F.count(p[1], "EuropaPlume") == 0 and F.count(p[1], "EuropaLevel", 3) == 1, "no vents: no plume, the level still follows")
end
do -- sites module missing: no weather, never an error
    local w, p, m = setup(2, { weather = { module = function(peer, record) return europa(record, nil, {})(peer) end } })
    check(F.count(p[1], "EuropaInit") == 0 and m.startDone, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local weather = { module = function(peer, record) return europa(record, mode, {})(peer) end, sites = {} }
    local w, p, m = reachRelic(2, { weather = weather })
    for _, q in ipairs(p) do F.nearTo(q.player, "nav_end", 0, 0) end
    relicSafe(w, m)
    run(196)
    check(F.count(p[1], "SucceedMission") == 1 and F.count(p[2], "SucceedMission") == 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("chmisn01 co-op: " .. checks .. " checks passed")
