-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/bd01cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/CoopCampaignTests/Test-Bdmisn01Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/CoopCampaignTests/Bdmisn01Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local DIRECT = { spawn_attack_ambush = true, spawn_attack_wave1 = true }
local function extrasFor(n) return math.min(math.floor(n / 2), 2) end

local function setup(n, options)
    options = options or {}
    local w = F.reset()
    w.audioBusy = options.busy == true
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
-- The opening shot ends, the recycler deploys, 20 s later Nav Alpha and the two cloaked ambushers appear.
local function reachNav(w)
    w.cameraDone["camera_start_arc"] = true; F.run(1)
    w.objects["recycler"].deployed = true; F.run(23)
end
-- One ambusher dies: the survivor retreats, 5 s later wave 1 and the attack camera.
local function reachWave1(w, m)
    reachNav(w)
    F.kill(m.badGuy1_ambush); F.run(6)
end
local function reachWave1a(w, m)
    reachWave1(w, m)
    w.cameraDone["camera_attack_view"] = true; F.run(3)
end
-- wave 2 arrives 60 s after wave 1
local function reachWave2(w, m)
    reachWave1a(w, m)
    F.run(62)
end
local function killBody(m)
    for k, v in pairs(m) do
        if type(k) == "string" and k:match("^badGuy") and type(v) == "string" then F.kill(v) end
    end
end
local function killEnemies(m)
    killBody(m)
    for _, h in ipairs(m.crcca.live) do if F.alive(h) then F.kill(h) end end
end
-- Scaled enemy builds (tickets), never the cloaked ambushers or the camera pair.
local function scaled(peer)
    local out = {}
    for _, b in ipairs(F.builds(peer, 0)) do
        if (b.odf == "cvfigh" or b.odf == "cvltnk") and not DIRECT[b.where] then out[#out + 1] = b end
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
        for _, name in ipairs({"BuildObject", "SetScrap", "SetAIP", "Goto", "Attack", "Retreat", "Patrol", "Cloak", "SetCloaked", "Decloak"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on the authored enemy team 2") end
end

-- ------------------------------------------------------------------ offline == faithful
local function outcomes(options, scenario)
    local w, p, m = setup(1, options)
    scenario(w, p, m)
    local out = {}
    for _, name in ipairs({"SucceedMission", "FailMission"}) do
        for _, c in ipairs(F.callsOf(p[1], name)) do out[#out + 1] = name .. ":" .. tostring(c[2]) .. ":" .. tostring(c[3]) end
    end
    return table.concat(out, ","), p[1], w
end
local scenarios = {
    win = function(w, p, m) reachWave2(w, m); killBody(m); F.run(10) end,
    recyclerLost = function(w, p, m) F.run(2); F.kill("recycler"); F.run(8) end,
    neverDeployed = function(w, p, m) w.cameraDone["camera_start_arc"] = true; F.run(250) end,
    navIgnored = function(w, p, m) reachNav(w); F.run(200) end,
}
for name, scenario in pairs(scenarios) do
    local faithful = outcomes({ faithful = true, script = "Scripts/bd01.lua" }, scenario)
    local offline = outcomes({}, scenario)
    check(faithful == offline and faithful ~= "", "offline completes like the faithful port (" .. name .. "): " .. faithful .. " / " .. offline)
end
do
    local out, peer = outcomes({}, scenarios.win)
    check(out:match("^SucceedMission:[%d%.]+:bd01win%.des$") and F.count(peer, "SucceedMission") == 1, "offline victory: " .. out)
    local lost = outcomes({}, scenarios.recyclerLost)
    check(lost:match("FailMission:[%d%.]+:bd01lsea%.des"), "offline recycler loss: " .. lost)
    check(outcomes({}, scenarios.neverDeployed):match("bd01lseb%.des"), "offline: recycler never deployed")
    check(outcomes({}, scenarios.navIgnored):match("bd01lsec%.des"), "offline: Nav Alpha ignored")
    noEnemyTeamTwo(peer)
end
do -- offline the layer adds nothing visible: no objective marker on the beacon, one local selection
    local w, p, m = setup(1, {})
    reachNav(w)
    check(F.count(p[1], "SetUserTarget") == 1 and F.count(p[1], "SetObjectiveOn") == 0, "offline: the beacon is selected, not marked")
    check(F.count(p[1], "SetAIControl", 5) == 1 and F.count(p[1], "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
end

-- ------------------------------------------------------------------ teams, ownership, humans as the player
for n = 2, 4 do
    local w, p, m = setup(n, {})
    check(m.startDone and m.coopMissionStarted, "leader starts the shared mission")
    check(m.user == "crcca_players", "the body's player is the nearest-human token")
    check(F.count(p[1], "SetAIControl", 5) == 1 and F.count(p[1], "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
    check(F.index(p[1], "SetAIControl") <= p[1].chunkCalls, "SetAIControl runs at chunk root, before Start")
    check(F.count(p[1], "SetAIP") == 0, "this mission has no AIP")
    check(F.count(p[1], "SetScrap") == 1 and F.last(p[1], "SetScrap")[2] == 1 and F.last(p[1], "SetScrap")[3] == 12 + 10 * (n - 1),
        "shared scrap on team 1 with the guest bonus")
    check(F.count(p[1], "SetPilot") == 1, "pilots set once")
    for i = 1, n do
        check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
        check(F.heardCount(p[i], "bd01001.wav") == 1, "briefing once on peer " .. i)
        local o = F.callsOf(p[i], "AddObjective")
        check(o[1] and o[1][2] == "bd01001.otf" and o[1][3] == "white", "first objective on peer " .. i)
    end
    check(p[1].rally and p[1].rally[0] == "recycler", "respawn rally point is the shared recycler")
    guestsPassive(p)
end

-- ------------------------------------------------------------------ the opening shot is shared; skippable only offline
do
    local w, p, m = setup(3, { busy = true })
    for i = 1, 3 do
        local c = F.last(p[i], "CameraPath")
        check(p[i].camera == 1 and c[2] == "camera_start_arc" and c[3] == 3000 and c[4] == 3500 and c[5] == "recycler",
            "the opening shot is the same on peer " .. i)
    end
    w.cancel = true; F.run(1)
    check(not m.cameraComplete[0], "a skip never ends the shared opening in a network game")
    w.cancel = false
    -- the host's own camera was released, so its native path never arrives: the shot ends at its flight time
    F.run(16)
    check(not m.cameraComplete[0], "the shared opening still runs for its 15.6 s flight")
    F.run(10)
    check(m.cameraComplete[0] and m.sound8Time < 1e9, "the opening ends at its flight time after a skip")
    for i = 1, 3 do check(p[i].camera == 0, "opening cameras balanced on peer " .. i) end
end
do -- no skip: the shot ends when the native path arrives
    local w, p, m = setup(3, {})
    F.run(5)
    check(not m.cameraComplete[0], "still flying")
    w.cameraDone["camera_start_arc"] = true; F.run(2)
    check(m.cameraComplete[0], "the opening ends when the shot arrives")
    for i = 1, 3 do check(p[i].camera == 0, "opening cameras balanced on peer " .. i) end
end
do -- offline: skippable
    local w, p, m = setup(1, {})
    check(p[1].camera == 1, "offline opening opens")
    w.cancel = true; F.run(1)
    check(m.cameraComplete[0] and p[1].camera == 0 and F.count(p[1], "StopAudioMessage") == 1, "offline skip ends the opening")
    w.cancel = false; F.run(5)
    check(F.count(p[1], "CameraReady") == 1, "a skipped opening never restarts")
end

-- ------------------------------------------------------------------ Nav Alpha, the cloaked ambush, any human
for n = 1, 4 do
    local w, p, m = setup(n, {})
    reachNav(w)
    local beacon = F.builds(p[1], 0, "bpcamr")
    check(#beacon == 1 and beacon[1].team == 1 and beacon[1].where == "spawn_nav_beacon", "Nav Alpha is built once on team 1")
    local amb = at(F.builds(p[1], 0, "cvfigh"), "spawn_attack_ambush")
    check(#amb == 2, n .. " human(s): the ambush is the two source units, no extras, got " .. #amb)
    for _, b in ipairs(amb) do
        check(b.team == 5, "ambushers are the co-op enemy")
        check(F.count(p[1], "SetPilotClass", b.h) == 1 and F.count(p[1], "Patrol", b.h) == 1 and F.count(p[1], "Cloak", b.h) == 1,
            "ambusher keeps its pilot class, patrol and cloak")
    end
    check(m.beaconSpawned1 and m.beaconSpawned2 and m.sound6Time < 1e9, "the second objective is revealed")
    for i = 1, n do
        check(F.count(p[i], "SetObjectiveName", m.beacon) == 1, "Nav Alpha is named on peer " .. i)
        check(F.heardCount(p[i], "BD01002.WAV") == 1, "the Nav line plays once on peer " .. i)
    end
    if n > 1 then
        for i = 1, n do check(F.count(p[i], "SetObjectiveOn", m.beacon) == 1, "Nav Alpha is marked for peer " .. i) end
        check(F.count(p[1], "SetUserTarget") == 1 and F.count(p[2], "SetUserTarget") == 0, "the host selects it, guests get the marker")
    end
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end
do -- any human reaching the beacon completes the objective (the stock body asks one player)
    local w, p, m = setup(3, {})
    reachNav(w)
    check(not m.objective2Complete, "nobody at Nav Alpha yet")
    F.world().objects[p[3].player].craft = false -- hidden from the unit search: only the player-distance test can see it
    F.nearTo(p[3].player, "spawn_nav_beacon", 60, 0); F.run(1)
    check(m.objective2Complete, "a team-3 human at the beacon completes Nav Alpha")
end
do -- stock bug: the body only looks for team-1 units near the beacon; humans are teams 1-4
    local w, p, m = setup(4, {})
    reachNav(w)
    check(not m.objective2Complete, "nobody at Nav Alpha yet")
    F.spawn("bvtank", 4, 1540 + 40, 100903); F.run(1)
    check(m.objective2Complete, "a team-4 unit near the beacon completes Nav Alpha")
end
do -- the survivor retreats cloaked, as in the body
    local w, p, m = setup(2, {})
    reachNav(w)
    local survivor = m.badGuy2_ambush
    F.kill(m.badGuy1_ambush); F.run(1)
    check(m.ambushRetreat and F.count(p[1], "Retreat", survivor) == 1, "the surviving ambusher retreats")
    check(F.count(p[1], "Cloak", survivor) == 2, "...and cloaks again")
end

-- ------------------------------------------------------------------ wave 1: the camera pair, wave 1a, wave 2 (scaling, no pop-in)
for n = 1, 4 do
    local e = extrasFor(n)
    local w, p, m = setup(n, {})
    reachWave1(w, m)
    local pair = at(F.builds(p[1], 0, "cvfigh"), "spawn_attack_wave1")
    check(#pair == 2 and pair[1].team == 5 and pair[2].team == 5, n .. " human(s): the attack camera's pair is two direct enemy fighters")
    check(m.wave1Ready and m.cameraReady and #scaled(p[1]) == 0, "wave 1a waits for the shot to arrive")
    for i = 1, n do
        local c = F.last(p[i], "CameraPath")
        check(p[i].camera == 1 and c[2] == "camera_attack_view" and c[3] == 2000 and c[4] == 1000 and c[5] == m.badGuy1_wave1,
            "the attack shot follows the first fighter on peer " .. i)
    end
    heardAll(p, "bd01003.wav")
    if n > 1 then
        w.cancel = true; F.run(1); w.cancel = false
        check(not m.cameraComplete[1], "the attack shot cannot be skipped in a network game")
        F.run(13) -- the host's camera is released: the shot ends at its 7.3 s flight time
    else
        w.cameraDone["camera_attack_view"] = true; F.run(3)
    end
    check(m.cameraComplete[1], "the attack shot ends")
    for i = 1, n do check(p[i].camera == 0, "attack cameras balanced on peer " .. i) end
    local wave1a = at(scaled(p[1]), "spawn_attack_wave1a")
    check(#wave1a == 2 + e, n .. " human(s): wave 1a = 2 + " .. e .. " extras, got " .. #wave1a)
    allSafe(p, wave1a)
    for _, b in ipairs(wave1a) do check(b.team == 5 and b.odf == "cvfigh", "wave 1a are enemy fighters") end
    check(type(m.badGuy3_wave1) == "string" and type(m.badGuy4_wave1) == "string", "tickets resolved to real units")
    -- orders mirror, extras included: attack the recycler, decloak
    local attacks = 0
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do if c[3] == "recycler" and c[4] == 1 then attacks = attacks + 1 end end
    check(attacks >= 2 + 2 + e, "every wave-1 fighter attacks the recycler, extras included: " .. attacks)
    check(F.count(p[1], "SetCloaked") == 4 + e and F.count(p[1], "Decloak") == 4 + e,
        "every wave-1 fighter decloaks: " .. F.count(p[1], "Decloak"))
    -- wave 2: three on the main path, two on the west path (watched at the base, so they arrive by the hidden path)
    F.run(62)
    check(m.wave2Ready, "wave 2 follows 60 s after wave 1")
    local wave2 = {}
    for _, b in ipairs(scaled(p[1])) do if b.where ~= "spawn_attack_wave1a" then wave2[#wave2 + 1] = b end end
    check(#wave2 == 5 + 2 * e, n .. " human(s): wave 2 = 5 + " .. 2 * e .. " extras, got " .. #wave2)
    check(#at(wave2, "spawn_attack_wave2a") == 0, "the west path is within 460 m of the base: it is never used while watched")
    allSafe(p, wave2)
    local tanks = 0
    for _, b in ipairs(wave2) do if b.odf == "cvltnk" then tanks = tanks + 1 end end
    check(tanks == 1, "the one light tank is not mirrored")
    check(#F.builds(p[1], 0, "cvfigh") <= 4 + 2 + 2 + 4 + 4 * 2, "bounded")
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end
do -- a human at the west approach gets the wave from there only when nobody watches it
    local w, p, m = setup(2, {})
    reachWave1(w, m)
    for _, q in ipairs(p) do F.place(q.player, 1900, 101800) end
    w.cameraDone["camera_attack_view"] = true; F.run(63)
    local wave2 = {}
    for _, b in ipairs(scaled(p[1])) do if b.where ~= "spawn_attack_wave1a" then wave2[#wave2 + 1] = b end end
    check(#at(wave2, "spawn_attack_wave2a") == 2 + 1, "with the base empty the west approach is used: " .. #at(wave2, "spawn_attack_wave2a"))
    allSafe(p, scaled(p[1]))
end

-- ------------------------------------------------------------------ nothing within 460 m: a fully watched map defers every wave
local APPROACHES = { "spawn_attack_wave1a", "spawn_attack_wave2", "spawn_attack_wave2a", "spawn_attack_ambush", "spawn_attack_wave1",
    "spawn_attack_wave1_1" }
local function watchEverything(w, p)
    F.place(p[2].player, 4000, 98000)
    local saved = {}
    for _, name in ipairs(APPROACHES) do
        saved[name] = w.pathPos[name]
        w.pathPos[name] = { x = 4000, y = saved[name].y, z = 98000 }
    end
    return function()
        for _, name in ipairs(APPROACHES) do w.pathPos[name] = saved[name] end
        F.place(p[2].player, 20000, 20000)
    end
end
do
    local w, p, m = setup(4, {})
    reachWave1(w, m)
    w.cameraDone["camera_attack_view"] = true
    local release = watchEverything(w, p)
    F.run(3)
    check(#scaled(p[1]) == 0 and m.cameraComplete[1], "a fully watched map defers wave 1a")
    check(type(m.badGuy3_wave1) == "number" and m.badGuy3_wave1 < 0, "the body holds a ticket while the wave waits")
    local pending = m.crcca.serial
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(m.crcca.serial == pending and #scaled(p[1]) == 0, "save/load keeps the pending wave without duplicating it")
    release(); F.run(5)
    check(#scaled(p[1]) == 2 + 2, "the whole wave is built exactly once when the watcher leaves, got " .. #scaled(p[1]))
    check(type(m.badGuy3_wave1) == "string", "tickets resolve to real units")
end

-- ------------------------------------------------------------------ victory (the co-op extras count) and defeat
do
    local w, p, m = setup(4, {})
    reachWave2(w, m)
    local live = m.crcca.live
    check(#live >= 8, "there are scaled fighters alive: " .. #live)
    local body = {}
    for k, v in pairs(m) do if type(k) == "string" and k:match("^badGuy") then body[v] = true end end
    local extras = {}
    for _, h in ipairs(live) do if not body[h] then extras[#extras + 1] = h end end
    check(#extras >= 4, "co-op extras are not in the body's lists: " .. #extras)
    killBody(m); F.run(4)
    check(F.heardCount(p[1], "bd01004.wav") == 0 and not m.objective3Complete, "no victory while a co-op extra lives")
    for i = 2, #extras do F.kill(extras[i]) end
    F.run(4)
    check(F.heardCount(p[1], "bd01004.wav") == 0, "one extra is still enough to hold the victory")
    F.kill(extras[1]); F.run(2)
    heardAll(p, "bd01004.wav")
    check(m.objective3Complete, "the last enemy dying completes the objective")
    F.run(12)
    for i = 1, 4 do
        check(F.count(p[i], "SucceedMission") == 1 and F.count(p[i], "FailMission") == 0, "one shared victory on peer " .. i)
        check(F.last(p[i], "SucceedMission")[3] == "bd01win.des", "victory debrief on peer " .. i)
        check((p[i].env.Save().coopUnresolved or 0) == 0, "no unresolved presentation identities on peer " .. i)
    end
    guestsPassive(p)
end
do -- recycler lost: the line plays, one shared failure, no victory
    local w, p, m = setup(3, {})
    reachWave2(w, m)
    F.kill("recycler"); F.run(3)
    heardAll(p, "bd01005.wav")
    F.run(12)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd01lsea.des", "one shared failure on peer " .. i)
        check(F.count(p[i], "SucceedMission") == 0, "no victory after a loss")
    end
    killBody(m); F.run(10)
    check(F.count(p[1], "SucceedMission") == 0, "a failed mission cannot be won")
    local before = #F.builds(p[1])
    F.run(10)
    check(#F.builds(p[1]) == before, "no reinforcement is built after the failure")
end
do -- the recycler is never deployed
    local w, p, m = setup(2, {})
    w.cameraDone["camera_start_arc"] = true; F.run(250)
    heardAll(p, "bd01008.wav"); heardAll(p, "bd01009.wav")
    for i = 1, 2 do check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd01lseb.des", "deployment failure on peer " .. i) end
end
do -- Nav Alpha is ignored
    local w, p, m = setup(2, {})
    reachNav(w); F.run(200)
    heardAll(p, "bd01006.wav"); heardAll(p, "bd01007.wav")
    for i = 1, 2 do check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd01lsec.des", "Nav failure on peer " .. i) end
end

-- ------------------------------------------------------------------ a load during a shot ends the shot as the body would
do
    local w, p, m = setup(3, { busy = true })
    F.run(3)
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(m.cameraComplete[0] and F.count(p[1], "CameraReady") == 1, "a load in the opening ends the shot without a second opening")
    for i = 1, 3 do check(p[i].camera == 0, "camera balanced after the load on peer " .. i) end
end
do
    local w, p, m = setup(2, {})
    reachWave1(w, m)
    check(m.cameraReady and not m.cameraComplete[1], "the attack shot is running")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(4)
    check(m.cameraComplete[1] and #scaled(p[1]) == 2 + 1, "a load during the attack shot releases wave 1a")
    for i = 1, 2 do check(p[i].camera == 0, "attack camera balanced after the load on peer " .. i) end
    -- a later shot is never skipped: wave 2 still comes 60 s after wave 1
    F.run(60)
    check(m.wave2Ready, "wave 2 still follows")
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
    local sites = dofile("Scripts/CRGanymedeSitesBD01.lua")
    check(sites.mission == "bdmisn01" and #sites.vents == 1 and sites.vents[1].label == "eggeizr11_geyser", "the generated sites carry the base geyser")
    local weather = { module = function(peer, record) return europa(record, nil, sites.vents)(peer) end, sites = sites }
    local w, p, m = setup(3, { weather = weather })
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
    reachNav(w)
    check(F.count(p[1], "EuropaLevel", 2) == 1, "Nav Alpha stirs the vapour")
    check(F.count(p[1], "EuropaPlume") == 0, "no plume before the attack")
    F.kill(m.badGuy1_ambush); F.run(6)
    check(F.count(p[1], "EuropaLevel", 3) == 1 and F.count(p[1], "EuropaPlume", 1) == 1, "the first wave raises the weather and blows the base vent")
    check(F.count(p[1], "EuropaQuakeCall") == 1 and F.count(p[1], "EuropaSurgeCall") == 1, "...with a quake and a surge")
    w.cameraDone["camera_attack_view"] = true; F.run(63)
    check(F.count(p[1], "EuropaLevel", 4) == 1, "the second wave brings the heaviest rung")
    check(F.count(p[1], "EuropaCreated") > 0, "new objects are offered to the weather")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "EuropaShutdown") >= 1 and F.count(p[1], "EuropaLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(p[1], "EuropaPlume") == 1 and F.count(p[1], "EuropaLevel", 3) == 1, "beats are not repeated after a load")
    killEnemies(m)
    F.run(3)
    check(F.count(p[1], "EuropaRelease") == 1 and F.count(p[1], "EuropaLevel", 1) == 1, "the victory line eases the sky back")
end
do -- a site list without vents: the plume is skipped, the rest of the weather still follows
    local weather = { module = function(peer, record) return europa(record, nil, {})(peer) end, sites = { mission = "bdmisn01", vents = {} } }
    local w, p, m = setup(2, { weather = weather })
    reachWave1(w, m)
    check(F.count(p[1], "EuropaPlume") == 0 and F.count(p[1], "EuropaLevel", 3) == 1 and F.count(p[1], "EuropaQuakeCall") == 1,
        "no vents: no plume, the level and the quake still follow")
end
do -- sites module missing: no weather, never an error
    local w, p, m = setup(2, { weather = { module = function(peer, record) return europa(record, nil, {})(peer) end } })
    check(F.count(p[1], "EuropaInit") == 0 and m.startDone, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local weather = { module = function(peer, record) return europa(record, mode, {})(peer) end, sites = {} }
    local w, p, m = setup(2, { weather = weather })
    reachWave2(w, m); killEnemies(m); F.run(14)
    check(F.count(p[1], "SucceedMission") == 1 and F.count(p[2], "SucceedMission") == 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("bdmisn01 co-op: " .. checks .. " checks passed")
