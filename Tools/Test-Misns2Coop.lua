-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/misns2cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/Test-Misns2Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Misns2Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local APCS = { "svapc0_apc", "svapc1_apc", "svapc2_apc" }
local PAD = "sblpad59_i76building"
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
-- Raiders (never camera pods or mines) built at a path.
local function builtAt(peer, where, odf)
    local out = {}
    for _, b in ipairs(F.builds(peer, 0, odf)) do
        if b.where == where and b.odf:sub(1, 2) == "bv" then out[#out + 1] = b end
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
        for _, name in ipairs({"BuildObject", "SetScrap", "SetAIP", "Goto", "Follow", "Attack", "SetIndependence", "Retreat", "RemoveObject"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on the authored enemy team 2") end
end
local function toPad() for _, a in ipairs(APCS) do F.nearTo(a, PAD, 30, 0) end end
-- the convoy never leaves the start unless a test moves it; keep the humans there too
local function scrub(p) for _, q in ipairs(p) do F.place(q.player, 1064 + 18 * (q.id - 1), 99463 + 17 * (q.id - 1)) end end

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
local scenarios = {
    win = function(w, p, m) toPad(); F.run(12) end,
    apclost = function(w, p, m) F.kill("svapc1_apc"); F.run(8) end,
    wavesThenWin = function(w, p, m) F.run(14); F.nearTo("svapc0_apc", "nav1", 50, 0); F.run(2); toPad(); F.run(12) end,
}
for name, scenario in pairs(scenarios) do
    local faithful = outcomes({ faithful = true, script = "Scripts/misns2.lua" }, scenario)
    local offline = outcomes({}, scenario)
    check(faithful == offline and faithful ~= "", "offline completes like the faithful port (" .. name .. "): " .. faithful .. " / " .. offline)
end
do
    local out, peer = outcomes({}, scenarios.win)
    check(out == "SucceedMission:misns2w1.des", "offline victory: " .. out)
    check(F.count(peer, "SucceedMission") == 1, "one victory request")
    local lost, lpeer = outcomes({}, scenarios.apclost)
    check(lost == "FailMission:misns2l1.des" and F.count(lpeer, "FailMission") == 1, "offline APC loss: " .. lost)
    noEnemyTeamTwo(peer)
end
check(F.count(select(2, outcomes({}, scenarios.win)), "SetAIControl", 5) == 1, "AI control only for enemy team 5 at chunk load")

-- ------------------------------------------------------------------ teams, ownership, humans as the player
do
    local w, p, m = setup(4, {})
    check(m.missionstart and m.coopMissionStarted, "leader starts the shared mission")
    check(m.player == "crcca_players", "the authored player tank label is the nearest-human token")
    check(F.count(p[1], "SetAIControl", 5) == 1 and F.count(p[1], "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
    check(F.index(p[1], "SetAIControl") <= p[1].chunkCalls, "SetAIControl runs at chunk root, before Start")
    check(F.count(p[1], "SetAIP") == 0 and F.count(p[1], "SetScrap") == 0, "the mission neither sets scrap nor an AIP")
    for i = 1, 4 do
        check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
        check(F.heardCount(p[i], "misns200.wav") == 1, "briefing once on peer " .. i)
    end
    for i = 1, 4 do
        local o = F.callsOf(p[i], "AddObjective")
        check(o[1][2] == "misns201.otf" and o[3][2] == "misns203.otf", "objective list on peer " .. i)
        check(F.count(p[i], "SetObjectiveName") >= 1, "the launch pad name replicates to peer " .. i)
    end
    guestsPassive(p)
end

-- ------------------------------------------------------------------ the opening film is shared; the cut shots come back
do
    local w, p, m = setup(3, { busy = true })
    check(p[1].camera == 1 and F.count(p[1], "CameraReady") == 1, "the opening cinematic opens")
    local function shot(peer) local c = F.last(peer, "CameraPath"); return c[2], c[5] end
    check(shot(p[1]) == "cinpath1", "the first shot is the body's cinpath1")
    F.run(m.cam1t - w.now + 1.5)
    for i = 1, 3 do
        local path, target = shot(p[i])
        check(path == "cinpath2" and target == "apcamr5_camerapod", "restored shot 2 on peer " .. i .. ": " .. tostring(path))
    end
    F.run(m.cam3t - w.now + 1.5)
    for i = 1, 3 do
        local path, target = shot(p[i])
        check(path == "cinpath4" and target == PAD, "restored shot 3 on peer " .. i .. ": " .. tostring(path))
    end
    F.run(m.cam4t - w.now + 1.5)
    for i = 1, 3 do check(shot(p[i]) == "cinpath1", "the film falls back to cinpath1 until the audio ends (peer " .. i .. ")") end
    -- unskippable in a network game: a skip releases only the skipper's own camera
    w.cancel = true; F.run(1)
    check(not m.openingcindone, "a skip never ends the shared opening in a network game")
    w.cancel = false
    w.audioBusy = false; F.run(2)
    check(m.openingcindone, "the opening ends with the audio")
    for i = 1, 3 do
        check(p[i].camera == 0, "opening cameras balanced on peer " .. i)
        check(F.heardCount(p[i], "misns202.wav") == 1, "follow-up line on peer " .. i)
    end
end
do -- offline: the same layer, skippable
    local w, p, m = setup(1, { busy = true })
    check(p[1].camera == 1, "offline opening opens")
    w.cancel = true; F.run(1)
    check(m.openingcindone and p[1].camera == 0, "offline skip ends the opening")
    w.cancel = false; F.run(40)
    check(F.count(p[1], "CameraReady") == 1, "a skipped opening never restarts")
end

-- ------------------------------------------------------------------ wave 1: scaling, restored raiders, no pop-in
for n = 1, 4 do
    local w, p, m = setup(n, {})
    F.run(12)
    local wave = builtAt(p[1], "bdsp1")
    local e = extrasFor(n)
    check(#wave == 4 + e, n .. " human(s): wave 1 is tank + raider + 2 restored raiders + " .. e .. " extras, got " .. #wave)
    check(#builtAt(p[1], "bdsp1", "bvtank") == 1 + e and #builtAt(p[1], "bdsp1", "bvraz") == 3, "wave 1 composition at " .. n)
    allSafe(p, wave)
    for _, b in ipairs(wave) do check(b.team == 5, "wave 1 is team 5") end
    check(type(m.bd1) == "string" and type(m.bd3) == "string", "tickets resolved to real units")
    -- orders mirror: the tank attacks APC 1, the extras too
    local atk1 = 0
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do if c[2] == m.bd1 or (c[3] == "svapc0_apc" and c[4] == 1) then atk1 = atk1 + 1 end end
    check(atk1 == 1 + e, "the extras mirror the first unit's attack order: " .. atk1)
    local ind3 = 0
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do if c[3] == "svapc2_apc" and c[4] == 1 then ind3 = ind3 + 1 end end
    check(ind3 >= 2, "restored raiders attack APC 3")
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end

-- ------------------------------------------------------------------ wave 2 (convoy at nav1), wave 3 (nav3: artillery, mines, cutoff)
for n = 1, 4 do
    local w, p, m = setup(n, {})
    F.run(11)
    F.nearTo("svapc1_apc", "nav1", 20, 0); F.run(5)
    check(m.wave2gone and not m.wave3gone, "the convoy at nav1 springs wave 2")
    local wave2 = builtAt(p[1], "bdsp2")
    check(#wave2 == 4 + extrasFor(n), n .. " human(s): wave 2 = 4 + extras, got " .. #wave2)
    check(wave2[1].odf == "bvraz", "extras copy the first unit (a raider)")
    allSafe(p, wave2)
    m.crcca.live = {} -- the earlier raiders have been destroyed (the live cap is tested on its own)
    F.nearTo("svapc2_apc", "nav3", 20, 0); F.run(6)
    check(m.wave3gone and m.alerttime < 1e9, "the convoy at nav3 springs wave 3")
    local arty = builtAt(p[1], "bdsp3")
    check(#arty == 3 + extrasFor(n) and arty[1].odf == "bvartl", n .. " human(s): wave 3 = 3 + extras")
    local cutoff = builtAt(p[1], "nav5")
    check(#cutoff == 3 + extrasFor(n) and cutoff[1].odf == "bvraz", n .. " human(s): restored nav5 cutoff = 3 + extras, got " .. #cutoff)
    allSafe(p, arty); allSafe(p, cutoff)
    local mines = 0
    for _, b in ipairs(F.builds(p[1])) do
        if b.odf == "proxmine" then mines = mines + 1; check(b.team == 5, "mines belong to the enemy team") end
    end
    check(mines == 19, "all nineteen mines are laid, got " .. mines)
    -- the artillery warning marks the guns (they are real units by then) on every peer
    F.run(16)
    check(m.artwarning and F.count(p[1], "SetObjectiveOn") >= 2, "artillery is marked")
    heardAll(p, "misns210.wav")
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end
do -- the third cutoff raider attacks APC 3 (the cut line named a variable that never existed)
    local w, p, m = setup(1, {})
    F.run(11); F.nearTo("svapc2_apc", "nav3", 20, 0); F.run(3)
    check(type(m.bdcutoff3) == "string", "three cutoff raiders exist")
    local a = {}
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do a[c[2]] = c[3] end
    check(a[m.bdcutoff1] == "svapc0_apc" and a[m.bdcutoff2] == "svapc1_apc" and a[m.bdcutoff3] == "svapc2_apc", "cutoff raiders attack APC 1, 2, 3")
end

-- ------------------------------------------------------------------ any human triggers the nearest-vehicle gates (team mapping)
do
    local w, p, m = setup(4, {})
    -- a team-3 human drives to bdsp3; nothing else is near. The body asks for a team-1 vehicle: humans are 1-4.
    F.place(p[3].player, 3076, 99936 - 300); F.run(2)
    check(m.wave3gone, "a team-3 human at the artillery pass springs wave 3")
    check(#builtAt(p[1], "bdsp3") == 0, "...but the pass is watched, so the wave does not appear in front of that human")
    local wave = {}
    for _, b in ipairs(F.builds(p[1])) do if b.odf == "bvartl" or b.odf == "bvtank" then wave[#wave + 1] = b end end
    check(#wave >= 3, "the wave comes from another hidden staging point instead")
    allSafe(p, wave)
    for _, b in ipairs(wave) do check(b.where ~= "bdsp3", "no wave unit was built at the watched entry") end
end
do -- an enemy vehicle at the pass is not a Soviet vehicle
    local w, p, m = setup(2, {})
    F.spawn("bvtank", 5, 2703, 100885 + 30); F.run(2)
    check(not m.wave4gone, "a team-5 vehicle near bdsp4 never springs wave 4")
end

-- ------------------------------------------------------------------ cutoff ambush at bdnet4, camera net 1, bug fix
do
    local w, p, m = setup(4, {})
    F.place(p[3].player, 2207, 101698 - 500); F.run(2)
    check(m.camnet1found, "any human within 550 m of bdnet4 springs the cutoff")
    check(m.wave4gone and not m.wave3gone, "stock bug fixed: the bdnet4 ambush latches wave 4, not wave 3")
    check(#builtAt(p[1], "bdnet4") == 6 + 2, "cutoff group = 6 + 2 extras, got " .. #builtAt(p[1], "bdnet4"))
    check(#builtAt(p[1], "bdsp4") == 3 + 2, "wave 4 group = 3 + 2 extras")
    allSafe(p, builtAt(p[1], "bdnet4")); allSafe(p, builtAt(p[1], "bdsp4"))
    -- camera net 1: bdnet6 is within 460 m of the human, so that one pod waits; nothing is built in view
    local pods = F.builds(p[1], 0, "bpcamr")
    check(#pods == 5, "five of the six restored net-1 pods are built, one waits for the watcher: " .. #pods)
    allSafe(p, pods)
    for _, b in ipairs(pods) do check(b.team == 5 and b.where:match("^bdnet%d$"), "net-1 pods are enemy cameras at bdnet1..6") end
    F.place(p[3].player, 1064, 99463); F.run(2)
    check(#F.builds(p[1], 0, "bpcamr") == 6, "the last pod is built once the watcher leaves")
    F.run(5)
    check(#F.builds(p[1], 0, "bpcamr") == 6, "each pod is built exactly once")
    check(type(m.nav6) == "string", "the pods fill the body's nav1..nav6 fields")
end

-- ------------------------------------------------------------------ wave 5 at the launch pad (+ restored tanks)
for n = 1, 4 do
    local w, p, m = setup(n, {})
    F.place(p[n].player, 3995, 100398); F.run(2)
    check(m.wave5gone, "a human near the launch pad springs wave 5")
    local wave = builtAt(p[1], "bdsp5")
    check(#wave == 3 + 2 + extrasFor(n), n .. " human(s): wave 5 = 3 raiders + 2 restored tanks + extras, got " .. #wave)
    check(#builtAt(p[1], "bdsp5", "bvtank") == 2, "the restored tanks")
    heardAll(p, "misns211.wav")
    F.run(5)
    heardAll(p, "misns211.wav") -- still once
    allSafe(p, wave)
end

-- ------------------------------------------------------------------ camera net 2, the patrol and the main platoon
do
    local w, p, m = setup(3, {})
    F.place(p[2].player, 3002, 98477 - 380); F.run(2)
    check(m.camnet2found, "any human near bdnet9 reveals the second camera net")
    local pods = F.builds(p[1], 0, "bpcamr")
    check(#pods == 8 and pods[1].team == 5, "eight enemy camera pods")
    heardAll(p, "misns207.wav")
    F.kill(m.nav7); F.run(2)
    check(m.sneaktimeset, "a destroyed pod starts the patrol timer")
    heardAll(p, "misns208.wav")
    F.run(48)
    check(m.patrolsent and #F.builds(p[1], 0, "svfigh") == 2, "two patrol fighters are sent")
    for _, b in ipairs(F.builds(p[1], 0, "svfigh")) do check(b.team == 5 and b.where == "bdspmain", "patrol is enemy team") end
    check(F.count(p[1], "Goto", m.pat1) == 1 and F.count(p[1], "Goto", m.pat2) == 1, "patrol orders")
    guestsPassive(p)
end
do
    local w, p, m = setup(4, {})
    F.place(p[2].player, 2621, 99189 - 300); F.run(2) -- a team-2 human 300 m from the main spawn
    check(m.bdplatoonspawned, "any human near bdspmain springs the main platoon")
    local plat = {}
    for _, b in ipairs(F.builds(p[1])) do if b.odf:sub(1, 2) == "bv" then plat[#plat + 1] = b end end
    check(#plat >= 7 and #builtAt(p[1], "bdspmain") == 0, "the platoon is built from a hidden alternative entry, not in front of the watcher")
    allSafe(p, plat)
end

-- ------------------------------------------------------------------ the surrender film: a real platoon, shared camera, removals
do
    local w, p, m = setup(3, {})
    F.run(12)
    local first = m.bd1
    w.audioBusy = true
    F.kill(m.bd1); F.kill(m.bd2); F.run(4)
    check(m.surrender and p[1].camera == 1, "wave 1 destroyed: the surrender film opens")
    local plat = {}
    for _, b in ipairs(F.builds(p[1], 0, "bvtank")) do if b.where:match("^1%d%d$") then plat[#plat + 1] = b end end
    check(#plat == 11, "the platoon is eleven tanks (stage props, never scaled), got " .. #plat)
    for _, b in ipairs(plat) do check(b.team == 5, "platoon is the enemy team") end
    for i = 1, 3 do
        check(p[i].camera == 1 and F.last(p[i], "CameraPath")[2] == "platooncam", "peer " .. i .. " is in the platoon shot")
    end
    -- save/load during the film: the cameras are gone, the film ends as the body would end it
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(m.bdcindone, "a load during the surrender film finishes it")
    heardAll(p, "misns206.wav")
    local removed = F.count(p[1], "RemoveObject")
    check(removed == 9, "nine platoon tanks are removed, two attack: " .. removed)
    check(F.count(p[1], "Attack", m.bd103) == 1 and F.count(p[1], "Attack", m.bd104) == 1, "the two survivors are sent against the APCs")
end
do -- the film ends on its own with the audio
    local w, p, m = setup(2, {})
    F.run(12)
    w.audioBusy = true
    F.kill(m.bd1); F.kill(m.bd2); F.run(4)
    w.audioBusy = false; F.run(2)
    check(m.bdcindone and F.count(p[1], "RemoveObject") == 9, "the film ends with its audio and removes nine tanks")
    for i = 1, 2 do check(p[i].camera == 0, "film cameras balanced on peer " .. i) end
    heardAll(p, "misns206.wav")
end
do -- a load in the opening ends it
    local w, p, m = setup(3, { busy = true })
    F.run(5)
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(m.openingcindone and F.heardCount(p[1], "misns202.wav") == 1, "the opening ends after a load and plays its follow-up")
    check(F.count(p[1], "CameraReady") == 1, "no second opening after a load")
end

-- ------------------------------------------------------------------ results
do -- victory: extras retreat, reinforcements stop, one shared result
    local w, p, m = setup(4, {})
    F.run(12)
    F.nearTo("svapc2_apc", "nav3", 20, 0); F.run(2)
    local live = p[1].env.Save().crcca.live
    check(#live >= 4, "there are scaled raiders alive")
    -- a request that is still waiting must never be built after the victory
    F.nearTo("svapc0_apc", "bdsp4", 2000, 0)
    w.audioBusy = true
    toPad(); F.run(2)
    check(m.missionwon, "all three APCs at the launch pad win")
    for _, h in ipairs(live) do
        local retreated = false
        for _, c in ipairs(F.callsOf(p[1], "Retreat")) do if c[2] == h then retreated = true end end
        check(retreated or not F.alive(h), "every live raider retreats, extras included: " .. tostring(h))
    end
    local before = #F.builds(p[1])
    w.audioBusy = false; F.run(12)
    check(#F.builds(p[1]) == before, "no reinforcement is built after the victory")
    for i = 1, 4 do
        check(F.count(p[i], "SucceedMission") == 1 and F.count(p[i], "FailMission") == 0, "one shared victory on peer " .. i)
        check(F.last(p[i], "SucceedMission")[3] == "misns2w1.des", "victory debrief on peer " .. i)
        check((p[i].env.Save().coopUnresolved or 0) == 0, "no unresolved presentation identities on peer " .. i)
    end
    heardAll(p, "misns213.wav"); heardAll(p, "misns215.wav")
    guestsPassive(p)
end
do -- APC loss
    local w, p, m = setup(3, {})
    F.kill("svapc1_apc"); F.run(3)
    heardAll(p, "misns212.wav")
    F.run(10)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "misns2l1.des", "one shared failure on peer " .. i)
        check(F.count(p[i], "SucceedMission") == 0, "no victory after a loss")
    end
end
do -- an APC lost while the victory radio plays: the port's failure precedence is kept
    local w, p, m = setup(2, {})
    w.audioBusy = true
    toPad(); F.run(2)
    check(m.missionwon, "victory queued")
    F.kill("svapc2_apc"); F.run(2)
    w.audioBusy = false; F.run(12)
    for i = 1, 2 do
        check(F.count(p[i], "FailMission") == 1 and F.count(p[i], "SucceedMission") == 0, "the lost APC still fails the mission on peer " .. i)
    end
end

-- ------------------------------------------------------------------ nothing within 460 m, saves, the cap
-- Every staging point is "at" one spot where a hidden human stands; the returned function sends the watcher away
-- and puts the points back.
local STAGING = { "bdsp1", "bdsp2", "bdsp3", "bdsp4", "bdsp5", "bdspmain" }
local function watchEverything(w, p)
    F.place(p[2].player, 4000, 98000)
    F.world().objects[p[2].player].craft = false -- hidden from GetNearestVehicle, so no wave gate fires
    local saved = {}
    for _, name in ipairs(STAGING) do
        saved[name] = w.pathPos[name]
        w.pathPos[name] = { x = 4000, y = saved[name].y, z = 98000 }
    end
    return function()
        for _, name in ipairs(STAGING) do w.pathPos[name] = saved[name] end
        F.place(p[2].player, 20000, 20000)
    end
end
do
    local w, p, m = setup(4, {})
    local release = watchEverything(w, p)
    F.run(12)
    check(#F.builds(p[1], 0, "bvtank") == 0 and #F.builds(p[1], 0, "bvraz") == 0, "a fully watched map defers every wave")
    check(type(m.bd1) == "number" and m.bd1 < 0 and m.crcca.serial >= 4, "the body holds tickets while the wave waits")
    local pending = m.crcca.serial
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(m.crcca.serial == pending and #F.builds(p[1], 0, "bvraz") == 0, "save/load keeps the pending wave without duplicating it")
    release(); F.run(5)
    local total = #F.builds(p[1], 0, "bvtank") + #F.builds(p[1], 0, "bvraz")
    check(total == 4 + 2, "the whole wave is built exactly once when the watcher leaves, got " .. total)
    check(type(m.bd1) == "string", "tickets resolve to real units")
end
do -- a marker for a unit that is still a ticket waits for the unit
    local w, p, m = setup(2, {})
    F.run(11)
    local release = watchEverything(w, p)
    F.nearTo("svapc2_apc", "nav3", 20, 0); F.run(18)
    check(m.artwarning and type(m.bd9) == "number", "the alert fires while the artillery is still a ticket")
    check(F.count(p[1], "SetObjectiveOn") == 0, "no marker is sent for a ticket")
    release(); F.run(4)
    check(type(m.bd9) == "string" and F.count(p[1], "SetObjectiveOn", m.bd9) == 1 and F.count(p[1], "SetObjectiveOn", m.bd10) == 1,
        "the markers are applied when the artillery arrives")
end
do -- live cap: extras are the only requests dropped
    local w, p, m = setup(4, {})
    m.crcca.live = {}
    for i = 1, 16 do m.crcca.live[i] = F.spawn("bvtank", 5, 9000 + i, 9000) end
    F.run(12)
    check(#builtAt(p[1], "bdsp1") == 4, "at the live cap the wave keeps its primaries and drops the extras: " .. #builtAt(p[1], "bdsp1"))
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
    check(F.count(p[1], "EnvironmentInit") == 0 and m.missionstart, "no weather module: the mission runs and touches no Environment")
    local printed = false
    for _, c in ipairs(p[1].calls) do if c[1] == "print" and tostring(c[2]):find("weather disabled", 1, true) then printed = true end end
    check(printed, "missing weather is logged, not fatal")
end
local function venus(record, mode)
    return function(peer)
        local V = { Seed = 4242 }
        function V.Init(o) peer.venusInit = o; record("VenusInit", o.authority, o.send ~= nil, o.seed); if mode == "initfail" then error("boom") end end
        function V.Update(dt)
            if peer.venusInit and peer.venusInit.authority and peer.venusInit.send and not V.sent then
                V.sent = true; peer.venusInit.send("VenusStrike", 3, 4)
            end
            if mode == "updatefail" then error("update boom") end
        end
        function V.AnnounceState() record("VenusAnnounce") end
        function V.ApplyNetEvent(op, ...) record("VenusEvent", op, ...) end
        function V.SetTargetLevel(n) record("VenusLevel", n) end
        function V.OnObjectCreated(h) record("VenusCreated", h) end
        function V.Save() return { saved = true } end
        function V.Load(s) record("VenusLoad", s and s.saved) end
        function V.Shutdown() record("VenusShutdown") end
        return V
    end
end
do
    -- the real generated sites: empty tables are legal
    local sites = dofile("Scripts/CRVenusSitesS2.lua")
    check(sites.mission == "misns2" and #sites.sulfur.runs == 0 and #sites.vents == 0, "the generated sites for this map are empty tables")
    local weather = { module = function(peer, record) return venus(record)(peer) end, sites = sites }
    local w, p, m = setup(3, { weather = weather })
    check(F.count(p[1], "VenusInit", true) == 1 and F.last(p[1], "VenusInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.count(p[2], "VenusInit", false) == 1, "guests render only (not the authority)")
    check(F.count(p[1], "VenusAnnounce") == 1 and F.count(p[2], "VenusAnnounce") == 0, "the leader announces its weather state once")
    check(F.count(p[1], "EnvironmentInit") == 1, "Venus lighting is initialised")
    for i = 2, 3 do
        local e = F.last(p[i], "VenusEvent")
        check(e and e[2] == "VenusStrike" and e[3] == 3 and e[4] == 4, "weather events reach guest " .. i)
    end
    check(p[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    F.run(11)
    check(F.count(p[1], "VenusLevel", 3) == 0, "calm until the first ambush")
    F.nearTo("svapc1_apc", "nav1", 20, 0); F.run(2)
    check(F.count(p[1], "VenusLevel", 3) == 1, "the first ambush raises the weather")
    F.nearTo("svapc2_apc", "nav3", 20, 0); F.run(2)
    check(F.count(p[1], "VenusLevel", 4) == 1, "the artillery pass brings the storm")
    check(F.count(p[1], "VenusCreated") > 0, "new objects are offered to the weather")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "VenusShutdown") >= 1 and F.count(p[1], "VenusLoad", true) == 1, "load restores the leader's weather state")
    toPad(); F.run(4)
    check(F.count(p[1], "VenusLevel", 2) == 1, "arrival eases the weather")
end
do -- sites module missing: no weather, never an error
    local w, p, m = setup(2, { weather = { module = function(peer, record) return venus(record)(peer) end } })
    check(F.count(p[1], "VenusInit") == 0 and m.missionstart, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local w, p, m = setup(2, { weather = { module = function(peer, record) return venus(record, mode)(peer) end, sites = {} } })
    toPad(); F.run(14)
    check(F.count(p[1], "SucceedMission") == 1 and F.count(p[2], "SucceedMission") == 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("misns2 co-op: " .. checks .. " checks passed")
