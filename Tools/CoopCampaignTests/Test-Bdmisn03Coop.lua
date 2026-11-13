-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and the co-op script. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/CoopCampaignTests/Test-Bdmisn03Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/CoopCampaignTests/Bdmisn03Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local function extrasFor(n) return math.min(math.floor(n / 2), 2) end
local DT = 0.5

local function setup(n, options)
    options = options or {}
    local w = F.reset()
    w.audioBusy = options.busy == true
    w.busyFile = options.busyFile
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
local function run(seconds) F.run(seconds, DT) end
local function runTo(w, when) run(math.max(DT, when - w.now + 1)) end
-- Calls of one kind since a mark.
local function since(peer, name, mark)
    local out = {}
    for i = (mark or 0) + 1, #peer.calls do
        if peer.calls[i][1] == name then out[#out + 1] = peer.calls[i] end
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
        for _, name in ipairs({"BuildObject", "SetScrap", "SetAIP", "Goto", "Follow", "Attack", "Hunt", "Defend2", "SetCloaked",
            "SetIndependence", "Retreat"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on the authored enemy team 2") end
end
local function atPathEnd() F.place("recycler", 536.9, 101063) end
local function forgetLive(m) m.crcca.live = {} end -- the earlier raiders have been destroyed (the cap is tested on its own)

-- ------------------------------------------------------------------ offline == faithful
-- One signature per run: every build (enemy team 5 read as the map's 2), order, audio line, objective and result.
-- The restored scavenger and turret are the only difference, so they are left out here and tested below.
local function signature(peer)
    local entries, audio = {}, {}
    for _, c in ipairs(peer.calls) do
        local n = c[1]
        if n == "BuildObject" then
            if c[3] ~= "bvscav" and c[3] ~= "bvturr" then
                entries[#entries + 1] = "B:" .. c[3] .. ":" .. (c[4] == 5 and 2 or c[4]) .. ":" .. tostring(c[5])
            end
        elseif n == "Play" or n == "Queue" or n == "AudioMessage" then
            audio[#audio + 1] = c[2]
        elseif n == "SucceedMission" or n == "FailMission" then
            entries[#entries + 1] = n .. ":" .. tostring(c[3])
        elseif n == "AddObjective" then
            entries[#entries + 1] = "O:" .. c[2] .. ":" .. c[3]
        elseif n == "Goto" or n == "Follow" or n == "Attack" or n == "Hunt" or n == "Defend2" or n == "SetCloaked" then
            entries[#entries + 1] = n
        end
    end
    table.sort(entries)
    return table.concat(entries, ","), table.concat(audio, ",")
end
local function outcome(options, scenario)
    local w = F.reset()
    local peer = F.makePeer(1, 1, false, options)
    F.run(1, DT)
    scenario(w, peer, peer.env.Save())
    return peer, w
end
-- The body re-arms its timers to 999999.9 once they fire, so the scenarios read them up front.
local function timers(m)
    return { raid2 = m.spawnRecyclerAttackTime2, raid3 = m.spawnRecyclerAttackTime3, apc = m.apcAttackTime, random = m.randomDelay }
end
local scenarios = {
    -- the whole mission: guards, deploy, gate, raids, APC, ambush, random raids, arrival
    win = function(w, p, m)
        local t = timers(m)
        atPathEnd(); run(2)
        w.objects.recycler.deployed = true; run(35)
        F.nearTo(p.player, "recycler", 30, 0); run(2)
        runTo(w, t.raid2); w.objects[m.apc].health = 0.9; run(2)
        F.nearTo(m.apc, "trigger_ambush", 10, 0); run(2)
        runTo(w, t.apc)
        runTo(w, t.random); run(100)
        runTo(w, t.raid3)
        F.nearTo(m.apc, "nav_delta", 20, 0); run(20)
    end,
    recyclerlost = function(w, p, m) run(20); F.kill("recycler"); run(20) end,
    apclost = function(w, p, m)
        local t = timers(m)
        atPathEnd(); run(2)
        w.objects.recycler.deployed = true; run(5)
        runTo(w, t.raid2); run(3); F.kill(m.apc); run(20)
    end,
    wreck = function(w, p, m)
        local t = timers(m)
        runTo(w, t.raid2); run(3) -- the wave is built over a few frames; a loss drops the rest
        F.nearTo(m.apc, "nav_delta", 20, 0); F.kill(m.apc); run(20)
    end,
}
for name, scenario in pairs(scenarios) do
    local faithful = outcome({ faithful = true, script = F.FAITHFUL }, scenario)
    local offline = outcome({}, scenario)
    local fs, fa = signature(faithful)
    local os, oa = signature(offline)
    check(fs == os, "offline plays the faithful mission (" .. name .. "): builds/orders/objectives/results differ")
    check(fa == oa, "offline plays the faithful audio (" .. name .. "): " .. fa .. " / " .. oa)
    check(fs:find("Mission", 1, true) ~= nil, "the scenario reaches a result (" .. name .. ")")
end
do
    local win = outcome({}, scenarios.win)
    check(F.count(win, "SucceedMission") == 1 and F.last(win, "SucceedMission")[3] == "bd03win.des", "offline victory")
    check(F.count(win, "FailMission") == 0, "no failure after a win")
    noEnemyTeamTwo(win)
    check(F.count(win, "SetAIControl", 5) == 1 and F.count(win, "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
    local wreck = outcome({}, scenarios.wreck)
    check(F.count(wreck, "SucceedMission") == 0 and F.count(wreck, "FailMission") == 1, "an APC wreck at the nav point is a loss, not a win")
    check(F.last(wreck, "FailMission")[3] == "bd03lseb.des", "...with the APC debrief")
end

-- ------------------------------------------------------------------ teams, ownership, humans as the player
do
    local w, p, m = setup(4, {})
    F.runUntil(function() return m.startDone end, 30, DT)
    check(m.startDone and m.coopMissionStarted, "leader starts the shared mission")
    check(m.user == "crcca_players", "the player handle is the nearest-human token")
    check(F.count(p[1], "SetAIControl", 5) == 1 and F.count(p[1], "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
    check(F.index(p[1], "SetAIControl") <= p[1].chunkCalls, "SetAIControl runs at chunk root, before Start")
    check(F.count(p[1], "SetAIP") == 0, "the mission has no AIP")
    -- shared scrap: the stock 8 plus 10 per guest
    check(F.last(p[1], "SetScrap")[2] == 1 and F.last(p[1], "SetScrap")[3] == 8 + 10 * 3, "shared scrap grows per guest")
    check(p[1].rally ~= nil and p[1].rally[0] == "recycler", "respawn rallies on the recycler")
    for i = 1, 4 do
        check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
        check(F.heardCount(p[i], "bd03001.wav") == 1 and F.heardCount(p[i], "bd03002.wav") == 1, "both briefings once on peer " .. i)
        local o = F.callsOf(p[i], "AddObjective")
        check(o[1][2] == "bd03001.otf", "objective on peer " .. i)
        check(F.count(p[i], "SetObjectiveName", "nav_delta") >= 1, "the Nav Delta name reaches peer " .. i)
    end
    guestsPassive(p)
end

-- ------------------------------------------------------------------ the two films are shared; a skip is offline only
do
    local w, p, m = setup(3, { busy = true })
    F.runUntil(function() return F.count(p[1], "CameraReady") >= 1 end, 30, DT)
    run(1)
    for i = 1, 3 do
        local c = F.last(p[i], "CameraPath")
        check(c and c[2] == "camera_intro" and p[i].camera == 1, "peer " .. i .. " is in the intro shot")
        check(w.objects[c[5]] == w.objects[p[1].player], "the intro looks at the host's ship on peer " .. i)
    end
    -- unskippable in a network game: a skip never ends the shared intro
    w.cancel = true; run(1)
    check(not m.soundComplete[0] and F.count(p[1], "StopAudioMessage") == 0, "a skip never ends the shared intro in a network game")
    w.cancel = false
    w.audioBusy = false; w.busyFile = "bd03002.wav"; run(1)
    check(m.soundComplete[0] and not m.soundComplete[1], "the intro ends with its audio, the recycler shot begins")
    run(2) -- the camera stream reaches the guests
    for i = 1, 3 do
        local c = F.last(p[i], "CameraPath")
        check(c[2] == "camera_recycler" and w.objects[c[5]] == w.objects.recycler and p[i].camera == 1, "peer " .. i .. " follows the recycler")
    end
    check(F.count(p[1], "Goto", "recycler") == 1, "the recycler sets out once")
    w.busyFile = nil; run(1)
    check(m.soundComplete[1], "the recycler shot ends with its audio")
    run(2)
    for i = 1, 3 do check(p[i].camera == 0, "film cameras balanced on peer " .. i) end
    check(F.count(p[1], "RemoveObject", "bobcat_kill_me_now") == 1 and F.count(p[1], "RemoveObject", "scout_kill_me_now") == 1, "the escort is removed")
    heardAll(p, "bd03001.wav"); heardAll(p, "bd03002.wav")
end
do -- offline: the same layer, skippable
    local w, p, m = setup(1, { busy = true })
    run(1)
    check(p[1].camera == 1, "offline intro opens")
    w.cancel = true; run(1)
    check(F.count(p[1], "StopAudioMessage") >= 1, "offline skip stops the line")
    w.busyFile = nil
end
do -- offline skip: the body ends the intro once the audio stops
    local w = F.reset()
    local peer = F.makePeer(1, 1, false, {})
    w.audioBusy = true
    F.run(1, DT)
    w.cancel = true
    F.tick(DT)
    w.audioBusy = false; w.cancel = false
    F.run(2, DT)
    check(peer.camera == 0 and peer.env.Save().soundComplete[0], "the intro ends after a skip")
end

-- ------------------------------------------------------------------ the mission timeline, 1-4 humans
for n = 1, 4 do
    local w, p, m = setup(n, {})
    local e = extrasFor(n)
    forgetLive(m)
    local t3 = m.spawnRecyclerAttackTime3

    -- the recycler reaches the end of its path: two turrets and four cloaked guards (+ extras of the first guard)
    local mark = #p[1].calls
    atPathEnd(); run(2)
    local turrets = F.builds(p[1], mark, "cvturr")
    check(#turrets == 2 and turrets[1].team == 5, n .. " human(s): two enemy turrets, never scaled")
    local guards = F.builds(p[1], mark, "cvfigh")
    check(#guards == 4 + e, n .. " human(s): four guards + " .. e .. " extras, got " .. #guards)
    allSafe(p, guards)
    local cloaked = 0
    for _, g in ipairs(guards) do
        check(g.team == 5, "guards are team 5")
        if w.objects[g.h].cloaked then cloaked = cloaked + 1 end
    end
    check(cloaked == #guards, "every guard is cloaked, extras included (orders replay on tickets)")
    check(#since(p[1], "Defend2", mark) == #guards, "every guard defends a turret")
    local geyserTrips = 0
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[2] == "recycler" and c[3] == "geyser1" then geyserTrips = geyserTrips + 1 end end
    check(geyserTrips == 1, "the recycler heads for the geyser once")

    -- the recycler deploys: the cut scavenger and turret (team 1), then the first raid after 30 s
    mark = #p[1].calls
    w.objects.recycler.deployed = true; run(2)
    local scav, turr = F.builds(p[1], mark, "bvscav"), F.builds(p[1], mark, "bvturr")
    check(#scav == 1 and scav[1].team == 1 and scav[1].where == "spawn_scav", n .. " human(s): restored scavenger at the base")
    check(#turr == 1 and turr[1].team == 1 and turr[1].where == "spawn_turret", n .. " human(s): restored turret at the base")
    run(40)
    check(#F.builds(p[1], mark, "bvscav") == 1 and #F.builds(p[1], mark, "bvturr") == 1, "the base units are built once")
    local raid = F.builds(p[1], mark, "cvfigh")
    check(#raid == 2 + e, n .. " human(s): raid 1 = 2 fighters + extras, got " .. #raid)
    for _, b in ipairs(raid) do check(b.where == "spawn_recycler_attack" and b.team == 5, "raid 1 is team 5 at its entry") end
    allSafe(p, raid)
    local atk = 0
    for _, c in ipairs(since(p[1], "Attack", mark)) do if c[3] == "recycler" and c[4] == 1 then atk = atk + 1 end end
    check(atk == #raid, "every raid-1 unit attacks the recycler (extras mirror the order)")

    -- any human at the recycler completes the gate once
    forgetLive(m)
    F.nearTo(p[n].player, "recycler", 30, 0); run(2)
    check(m.objective1Complete and m.objective2Complete, "the highest team's human at the recycler completes the gate")
    heardAll(p, "bd03006.wav")
    run(5)
    heardAll(p, "bd03006.wav")
    F.place(p[n].player, 1407 + 18 * (n - 1), 99591 + 17 * (n - 1))

    -- 7 minutes: the cloaked raid (5 + extras) and the APC with two escorts
    local t2 = m.spawnRecyclerAttackTime2
    runTo(w, t2 - 3)
    forgetLive(m)
    mark = #p[1].calls
    runTo(w, t2)
    run(3)
    local wave2 = F.builds(p[1], mark, "cvfigh")
    for _, b in ipairs(F.builds(p[1], mark, "cvtnk")) do wave2[#wave2 + 1] = b end
    check(#wave2 == 5 + e, n .. " human(s): raid 2 = 5 + extras, got " .. #wave2)
    allSafe(p, wave2)
    local c2 = 0
    for _, b in ipairs(wave2) do if w.objects[b.h].cloaked then c2 = c2 + 1 end end
    check(c2 == #wave2, "raid 2 is cloaked")
    check(#since(p[1], "Goto", mark) >= #wave2, "raid 2 takes the attack path")
    check(m.apcSpawned and type(m.apc) == "string" and F.team(m.apc) == 1, n .. " human(s): the APC is a real team-1 unit")
    check(#F.builds(p[1], mark, "bvraz") == 2 and F.builds(p[1], mark, "bvraz")[1].team == 1, "two friendly escorts")
    for i = 1, n do
        check(F.count(p[i], "SetObjectiveOn") >= 1, "the APC marker reaches peer " .. i)
        check(F.count(p[i], "AddObjective", "bd03003.otf") >= 1, "the APC objective reaches peer " .. i)
    end
    heardAll(p, "bd03007.wav")
    local escorts = 0
    for _, c in ipairs(F.callsOf(p[1], "Defend2")) do if c[3] == m.apc then escorts = escorts + 1 end end
    check(escorts == 2, "the escorts defend the APC")

    -- 9 minutes: the fast fighter hunts the APC
    forgetLive(m)
    mark = #p[1].calls
    runTo(w, m.apcAttackTime)
    run(3) -- two builds per frame
    local fast = F.builds(p[1], mark, "cvfighf")
    check(#fast == 1 + e, n .. " human(s): the APC hunter + extras, got " .. #fast)
    allSafe(p, fast)

    -- 10 minutes on: four random units every 90 s
    forgetLive(m)
    mark = #p[1].calls
    local r1 = m.randomDelay
    runTo(w, r1)
    run(3)
    local rnd = F.builds(p[1], mark)
    check(#rnd == 4 + e, n .. " human(s): random raid = 4 + extras, got " .. #rnd)
    allSafe(p, rnd)
    local hunts, apcAttacks = #since(p[1], "Hunt", mark), 0
    for _, c in ipairs(since(p[1], "Attack", mark)) do if c[3] == m.apc then apcAttacks = apcAttacks + 1 end end
    check(hunts >= 2 and apcAttacks >= 2, "the random raid hunts and attacks the APC")
    -- 11 minutes: the third raid (two fighters on the attack path)
    forgetLive(m)
    local mark3 = #p[1].calls
    runTo(w, t3 - 2)
    local before3 = #F.builds(p[1], mark3, "cvfigh")
    run(4)
    local third = F.builds(p[1], mark3, "cvfigh")
    check(#third - before3 == 2 + e, n .. " human(s): the third raid = 2 fighters + extras, got " .. (#third - before3))
    allSafe(p, third)

    -- the random raid repeats 90 s after the first
    forgetLive(m)
    local mark2 = #p[1].calls
    runTo(w, r1 + 90)
    run(3)
    check(#F.builds(p[1], mark2) >= 4 + e, "a second random raid follows 90 s later")

    -- the ambush on the APC's route
    forgetLive(m)
    mark = #p[1].calls
    F.nearTo(m.apc, "trigger_ambush", 10, 0); run(3)
    check(m.triggerAmbush, "the APC at the pass springs the ambush")
    local amb = F.builds(p[1], mark)
    local follows = 0
    for _, c in ipairs(since(p[1], "Follow", mark)) do if c[3] == m.apc and c[4] == 0 then follows = follows + 1 end end
    check(follows == 2 + e and #amb == follows, n .. " human(s): ambush = 2 + extras follow the APC, got " .. follows)
    allSafe(p, amb)

    -- the first hit on the APC is reported once
    w.objects[m.apc].health = 0.9; run(2)
    heardAll(p, "bd03008.wav")
    run(5)
    heardAll(p, "bd03008.wav")
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end

-- ------------------------------------------------------------------ a team-3 human at the recycler is "the player"
do
    local w, p, m = setup(4, {})
    F.nearTo(p[3].player, "recycler", 40, 0); run(2)
    check(m.objective1Complete, "any human within 75 m of the recycler completes the objective")
    heardAll(p, "bd03006.wav")
    local greens = 0
    for _, c in ipairs(F.callsOf(p[1], "AddObjective")) do if c[3] == "green" then greens = greens + 1 end end
    check(greens == 2, "both objectives turn green once")
end
do -- nobody near: nothing happens
    local w, p, m = setup(3, {})
    run(10)
    check(not m.objective1Complete and F.heardCount(p[1], "bd03006.wav") == 0, "no human at the recycler, no message")
end

-- ------------------------------------------------------------------ restored base units
do
    local w, p, m = setup(2, {})
    check(#F.builds(p[1], 0, "bvscav") == 0 and #F.builds(p[1], 0, "bvturr") == 0, "nothing before the recycler deploys")
    w.objects.recycler.deployed = true; run(2)
    check(#F.builds(p[1], 0, "bvscav") == 1 and #F.builds(p[1], 0, "bvturr") == 1, "built on deployment")
    check(#F.builds(p[1], 0, "bvscav") == 1 and p[1].env.Save().crcca.r.base, "latched in the saved state")
end
do -- a map without the paths runs the faithful mission
    local w, p, m = setup(1, {})
    w.missingPaths = { spawn_scav = true, spawn_turret = true }
    w.objects.recycler.deployed = true; run(5)
    check(#F.builds(p[1], 0, "bvscav") == 0 and #F.builds(p[1], 0, "bvturr") == 0, "no path, no restored units")
    check(m.recyclerDeployed and F.count(p[1], "print") <= 2, "no error is raised")
end

-- ------------------------------------------------------------------ concealed arrivals: nothing within 460 m
do -- a human stands at the first raid's entry: it comes from another authored approach
    local w, p, m = setup(3, {})
    atPathEnd(); run(2)
    F.place(p[2].player, 941, 101858)
    w.objects.recycler.deployed = true
    local mark = #p[1].calls
    run(40)
    local raid = F.builds(p[1], mark, "cvfigh")
    check(#raid == 3, "the raid still comes, 2 + 1 extra, got " .. #raid)
    for _, b in ipairs(raid) do check(b.where == "spawn_attack_apc", "from the first clear authored entry, not in front of the watcher") end
    allSafe(p, raid)
end
-- Every enemy entry is "at" one spot where a hidden human stands; the returned function sends the watcher away.
local ENTRIES = { "spawn_recycler_attack", "spawn_attack_apc", "spawn_random_1", "spawn_random_2", "spawn_random_3", "spawn_random_4",
    "spawn_turret_guard1", "spawn_turret_guard2" }
local function watchEverything(w, p)
    F.place(p[2].player, 4000, 98000)
    F.world().objects[p[2].player].craft = false
    local saved = {}
    for _, name in ipairs(ENTRIES) do
        saved[name] = w.pathPos[name]
        w.pathPos[name] = { x = 4000, y = saved[name].y, z = 98000 }
    end
    return function()
        for _, name in ipairs(ENTRIES) do w.pathPos[name] = saved[name] end
        F.place(p[2].player, 20000, 20000)
    end
end
do
    local w, p, m = setup(4, {})
    w.objects.recycler.deployed = true
    local release = watchEverything(w, p)
    run(40)
    check(#F.builds(p[1], 0, "cvfigh") == 0, "a fully watched map defers every raid")
    check(type(m.crcca.serial) == "number" and m.crcca.serial >= 4, "the requests wait in the saved state")
    local pending = m.crcca.serial
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); run(3)
    check(m.crcca.serial == pending and #F.builds(p[1], 0, "cvfigh") == 0, "save/load keeps the pending raid without duplicating it")
    release(); run(5)
    check(#F.builds(p[1], 0, "cvfigh") == 2 + 2, "the whole raid is built exactly once when the watcher leaves, got " .. #F.builds(p[1], 0, "cvfigh"))
end
do -- live cap: extras are the only requests dropped
    local w, p, m = setup(4, {})
    m.crcca.live = {}
    for i = 1, 16 do m.crcca.live[i] = F.spawn("cvfigh", 5, 9000 + i, 9000) end
    w.objects.recycler.deployed = true
    run(40)
    check(#F.builds(p[1], 0, "cvfigh") == 2, "at the live cap the raid keeps its primaries and drops the extras: " .. #F.builds(p[1], 0, "cvfigh"))
end

-- ------------------------------------------------------------------ cut hunt block stays cut
do
    local w, p, m = setup(2, {})
    run(60)
    check(F.count(p[1], "Attack", "evil_scout1") == 0 and F.count(p[1], "Hunt") == 0, "the cut hunt of the roadside ambush is not restored")
end

-- ------------------------------------------------------------------ results
local function toNav(m) F.nearTo(m.apc, "nav_delta", 20, 0) end
do -- victory: one shared result, no reinforcements afterwards, a late recycler loss is ignored
    local w, p, m = setup(4, {})
    runTo(w, m.spawnRecyclerAttackTime2); run(3)
    forgetLive(m)
    w.audioBusy = true
    toNav(m); run(2)
    check(m.won, "the APC at Nav Delta wins")
    F.kill("recycler"); run(2)
    check(not m.lost, "the recycler lost after the arrival is ignored")
    local before = #F.builds(p[1])
    w.audioBusy = false; run(12)
    check(#F.builds(p[1]) == before, "no reinforcement is built after the arrival")
    for i = 1, 4 do
        check(F.count(p[i], "SucceedMission") == 1 and F.count(p[i], "FailMission") == 0, "one shared victory on peer " .. i)
        check(F.last(p[i], "SucceedMission")[3] == "bd03win.des", "victory debrief on peer " .. i)
        check((p[i].env.Save().coopUnresolved or 0) == 0, "no unresolved presentation identities on peer " .. i)
    end
    heardAll(p, "bd03009.wav"); heardAll(p, "bd03012.wav", 0)
    guestsPassive(p)
end
do -- recycler lost
    local w, p, m = setup(3, {})
    run(5)
    F.kill("recycler"); run(12)
    heardAll(p, "bd03012.wav")
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd03lsea.des", "one shared recycler-loss failure on peer " .. i)
        check(F.count(p[i], "SucceedMission") == 0, "no victory after the loss")
    end
end
do -- APC lost: both lines, then the failure
    local w, p, m = setup(3, {})
    runTo(w, m.spawnRecyclerAttackTime2); run(3)
    F.kill(m.apc); run(25)
    heardAll(p, "bd03010.wav"); heardAll(p, "bd03011.wav")
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd03lseb.des", "one shared APC-loss failure on peer " .. i)
    end
    local before = #F.builds(p[1])
    run(120)
    check(#F.builds(p[1]) == before, "no raid is built after the loss")
end

-- ------------------------------------------------------------------ saves during the films, leader leaves
do -- a load in the intro ends it and starts the recycler shot
    local w, p, m = setup(3, { busy = true })
    run(3)
    check(p[1].camera == 1, "the intro is running")
    w.audioBusy = false
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); run(3)
    check(m.soundComplete[0] and F.count(p[1], "CameraReady") <= 2, "the intro ends after a load")
    check(m.soundComplete[1], "the mission carries on to the recycler shot")
    for i = 1, 3 do check(p[i].camera == 0, "no camera is left open on peer " .. i) end
    check(F.heardCount(p[1], "bd03001.wav") == 1, "the first line is not replayed")
end
do -- a load in the recycler shot removes the escort and arms the first message
    local w, p, m = setup(2, { busyFile = "bd03002.wav" })
    run(3)
    check(m.soundComplete[0] and not m.soundComplete[1], "the recycler shot is running")
    w.busyFile = nil
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); run(3)
    check(m.soundComplete[1] and m.sound1Delay < 1e6, "the shot ends after a load and arms the next line")
    check(F.count(p[1], "RemoveObject", "bobcat_kill_me_now") == 1, "the escort is removed once")
end
do
    local w, p, m = setup(3, {})
    for i = 2, 3 do p[i].env.DeletePlayer(1) end
    run(3)
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
local function europa(record, mode)
    return function(peer)
        local V = { Seed = 4242, Initialized = true }
        local vents = dofile("Scripts/CRGanymedeSitesBD03.lua").vents
        function V.Init(o)
            peer.init = o
            record("EuropaInit", o.authority, o.send ~= nil, o.seed)
            if mode == "initfail" then error("boom") end
        end
        function V.Update(dt)
            if peer.init and peer.init.authority and peer.init.send and not V.sent then
                V.sent = true; peer.init.send("EuropaPlume", 1, 2, 3)
            end
            if mode == "updatefail" then error("update boom") end
        end
        function V.AnnounceState() record("EuropaAnnounce") end
        function V.ApplyNetEvent(op, ...) record("EuropaEvent", op, ...) end
        function V.SetTargetLevel(n) record("EuropaLevel", n) end
        function V.GetVentSites() return vents end
        function V.TriggerPlume(index) record("EuropaPlumeAt", index) end
        function V.Quake(strength, duration) record("EuropaQuakeCall", strength, duration) end
        function V.Surge(duration, strength) record("EuropaSurgeCall", duration, strength) end
        function V.ReleaseForcedLevel() record("EuropaRelease") end
        function V.OnObjectCreated(h) record("EuropaCreated", h) end
        function V.Save() return { saved = true } end
        function V.Load(s) record("EuropaLoad", s and s.saved) end
        function V.Shutdown() record("EuropaShutdown") end
        return V
    end
end
do
    -- the real generated sites: the recycler's geyser is the major vent
    local sites = dofile("Scripts/CRGanymedeSitesBD03.lua")
    check(sites.mission == "bdmisn03" and #sites.vents == 2 and sites.vents[1].label == "geyser1" and sites.vents[1].major,
        "the generated sites carry the geyser the recycler deploys on")
    local weather = { module = function(peer, record) return europa(record)(peer) end, sites = sites }
    local w, p, m = setup(3, { weather = weather })
    check(F.count(p[1], "EuropaInit", true) == 1 and F.last(p[1], "EuropaInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.count(p[2], "EuropaInit", false) == 1, "guests render only (not the authority)")
    check(F.count(p[1], "EuropaAnnounce") == 1 and F.count(p[2], "EuropaAnnounce") == 0, "the leader announces its weather state once")
    local env = F.last(p[1], "EnvironmentInit")[2]
    check(F.count(p[1], "EnvironmentInit") == 1 and env.lightingMode == "orbit", "Jupiter-lit orbit lighting is initialised")
    check(F.count(p[1], "WeatherSensors", "Ganymede") == 1 and F.count(p[2], "WeatherSensors", "Ganymede") == 1,
        "the weather slows radar on every peer, once")
    for i = 2, 3 do
        local e = F.last(p[i], "EuropaEvent")
        check(e and e[2] == "EuropaPlume" and e[3] == 1 and e[4] == 2 and e[5] == 3, "weather events reach guest " .. i)
    end
    check(p[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    check(F.count(p[1], "EuropaLevel") == 0, "calm until the story moves")
    atPathEnd(); run(2)
    w.objects.recycler.deployed = true; run(2)
    check(F.count(p[1], "EuropaLevel", 2) == 1 and F.count(p[1], "EuropaPlumeAt", 1) == 1, "the deployed recycler stirs the sky and wakes its geyser")
    check(F.count(p[1], "EuropaCreated") > 0, "new objects are offered to the weather")
    runTo(w, m.spawnRecyclerAttackTime2); run(3)
    check(F.count(p[1], "EuropaLevel", 3) == 1, "the APC setting out raises the weather")
    check(F.count(p[1], "EuropaLevel", 4) == 0, "...but not yet the storm")
    F.nearTo(m.apc, "trigger_ambush", 10, 0); run(2)
    check(F.count(p[1], "EuropaLevel", 4) == 1 and F.count(p[1], "EuropaQuakeCall") == 1 and F.count(p[1], "EuropaSurgeCall") == 1,
        "the ambush brings the storm, a quake and a surge")
    w.objects[m.apc].health = 0.9; run(2)
    check(F.count(p[1], "EuropaLevel", 4) == 1, "the storm beat fires once")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); run(3)
    check(F.count(p[1], "EuropaShutdown") >= 1 and F.count(p[1], "EuropaLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(p[1], "EuropaLevel", 4) == 1 and F.count(p[1], "EuropaLevel", 3) == 1, "beats already played are not replayed after a load")
    toNav(m); run(4)
    check(F.count(p[1], "EuropaRelease") == 1 and F.count(p[1], "EuropaLevel", 1) == 1, "arrival eases the weather")
end
do -- sites module missing: no weather, never an error
    local w, p, m = setup(2, { weather = { module = function(peer, record) return europa(record)(peer) end } })
    check(F.count(p[1], "EuropaInit") == 0 and m.startDone, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local w, p, m = setup(2, { weather = { module = function(peer, record) return europa(record, mode)(peer) end,
        sites = dofile("Scripts/CRGanymedeSitesBD03.lua") } })
    runTo(w, m.spawnRecyclerAttackTime2); run(3)
    toNav(m); run(14)
    check(F.count(p[1], "SucceedMission") == 1 and F.count(p[2], "SucceedMission") == 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("bdmisn03 co-op: " .. checks .. " checks passed")
