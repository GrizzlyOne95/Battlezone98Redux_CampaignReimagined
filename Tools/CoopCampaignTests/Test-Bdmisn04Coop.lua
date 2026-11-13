-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/bd04cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/CoopCampaignTests/Test-Bdmisn04Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/CoopCampaignTests/Bdmisn04Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local function extrasFor(n) return math.min(math.floor(n / 2), 2) end
local function setup(n, options)
    options = options or {}
    local w = F.reset()
    w.audioBusy = options.busy == true
    w.realTimer = options.realTimer == true
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
local function builtAt(peer, where, odf)
    local out = {}
    for _, b in ipairs(F.builds(peer, 0, odf)) do
        if b.where == where and b.odf:sub(1, 2) == "cv" then out[#out + 1] = b end
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
        for _, name in ipairs({"BuildObject", "BuildObjectAtPortal", "SetScrap", "SetAIP", "Goto", "Follow", "Attack",
            "SetIndependence", "Retreat"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on the authored enemy team 2") end
    for _, c in ipairs(F.callsOf(peer, "BuildObjectAtPortal")) do check(c[4] ~= 2, "no portal unit on team 2") end
end
-- The humans stay at the crater rim until a test moves them.
local function rim(p) for _, q in ipairs(p) do F.place(q.player, F.START[1] - 3.8 * (q.id - 1), F.START[3] - 25 * (q.id - 1)) end end
-- Finish the opening shot at once and run the portal film out (cameraComplete[1] -> the scav objective).
local function toScav(w, p, m)
    w.cameraDone["camera_start_up"] = true; F.run(1); w.cameraDone["camera_start_up"] = false
    F.run(12)
    check(m.cameraComplete[0] and m.cameraComplete[1] and m.gotoScav, "the intro films end and the scav objective starts")
end
-- Entering a craft hands it to the human's team and makes it the human's handle.
local function enter(q, craft) q.player = craft; F.world().objects[craft].team = q.team end
local function enterScav(q) enter(q, "scav_3") end
-- East edge of the base, more than 400 m from trigger_1; the deep point is inside trigger_1's radius.
local function inBase(h)
    F.place(h, 1780, 101250)
    check(F.inBase(1780, 101250), "the test point is inside base_limit")
    check(math.sqrt((1780 - 1261) ^ 2 + (101250 - 101691) ^ 2) > 400, "and outside the 400 m of trigger_1")
end
local function deepInBase(h) F.place(h, 1400, 101700); check(F.inBase(1400, 101700), "the deep point is inside base_limit") end

-- ------------------------------------------------------------------ offline == faithful
local function outcomes(options, scenario)
    options.realTimer = options.faithful == true
    local w, p, m = setup(1, options)
    scenario(w, p, m)
    local out = {}
    for _, name in ipairs({"SucceedMission", "FailMission"}) do
        for _, c in ipairs(F.callsOf(p[1], name)) do out[#out + 1] = name .. ":" .. tostring(c[3]) end
    end
    return table.concat(out, ","), p[1], w
end
local function winRun(w, p, m)
    toScav(w, p, m)
    enterScav(p[1]); F.run(1)
    p[1].info.cbport = true; F.run(1); p[1].info.cbport = false; F.run(5)
    p[1].info.obdataa = true; F.run(1); p[1].info.obdataa = false; F.run(1)
    enter(p[1], "hauler_1"); F.tug("fragment", "hauler_1"); F.run(1)
    F.run(32)
    check(m.dropZoneReady, "the drop zone appears 30 s after the pickup")
    F.nearTo("fragment", m.navBeacon, 10, 0)
    F.run(2)
end
local scenarios = {
    win = winRun,
    haulerlost = function(w, p, m) toScav(w, p, m); F.kill("hauler_1"); F.run(3) end,
    portallost = function(w, p, m) toScav(w, p, m); F.kill("portal"); F.run(3) end,
}
for name, scenario in pairs(scenarios) do
    local faithful = outcomes({ faithful = true, script = "Scripts/bd04.lua" }, scenario)
    local offline = outcomes({}, scenario)
    check(faithful == offline and faithful ~= "", "offline completes like the faithful port (" .. name .. "): " .. faithful .. " / " .. offline)
end
do
    local out, peer = outcomes({}, scenarios.win)
    check(out == "SucceedMission:bd04win.des" and F.count(peer, "SucceedMission") == 1, "offline victory: " .. out)
    local lost, lpeer = outcomes({}, scenarios.haulerlost)
    check(lost == "FailMission:bd04lose.des" and F.count(lpeer, "FailMission") == 1, "offline hauler loss: " .. lost)
    noEnemyTeamTwo(peer)
    check(F.count(peer, "SetAIControl", 5) == 1 and F.count(peer, "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
    check(F.index(peer, "SetAIControl") <= peer.chunkCalls, "SetAIControl runs at chunk root, before Start")
end

-- ------------------------------------------------------------------ the shared start: scrap, pilots, hidden humans, disguise
for n = 1, 4 do
    local w, p, m = setup(n, {})
    check(m.startDone and m.coopMissionStarted, "the host starts the shared mission")
    local scrap = F.last(p[1], "SetScrap")
    check(scrap[2] == 1 and scrap[3] == 8 + 10 * (n - 1), n .. " human(s): shared scrap grows per guest: " .. tostring(scrap[3]))
    check(F.count(p[1], "SetPilot") == n, n .. " human(s): pilots for every human team")
    check(m.cameraReady[0] and p[1].camera == 1, "the opening shot opens once on the host")
    for i = 1, n do
        check(F.count(p[i], "DisableStartingRecycler") == (n > 1 and 1 or 0), "extra starting recyclers disabled in a network game, peer " .. i)
        check(F.heardCount(p[i], "bd04001.wav") == 1, "briefing once on peer " .. i)
        check(F.count(p[i], "Hide") == n, "all " .. n .. " humans are hidden for the film on peer " .. i)
    end
    for i = 1, n do check(F.hidden(p[i].player), "human " .. i .. " is hidden") end
    if n > 1 then check(p[1].rally ~= nil and p[1].rally[0] == "pilot", "respawn rally point is the crater rim path") end
    toScav(w, p, m)
    for i = 1, n do
        check(not F.hidden(p[i].player), "human " .. i .. " is shown again after the film")
        check(F.perceived(p[i].player) == 5, "human " .. i .. " is disguised as the Chinese (perceived team 5)")
        check(F.team(p[i].player) == i, "the real team is untouched")
    end
    for i = 1, n do
        for _, c in ipairs(F.callsOf(p[i], "SetPerceivedTeam")) do check(c[3] == 5, "never the DLL's literal team 2") end
        check(F.count(p[i], "PortalOut") == 1 and F.count(p[i], "DeactivatePortal") == 1, "the portal opens and closes on peer " .. i)
        check(F.count(p[i], "UnHide") == n, "all humans are shown on peer " .. i)
        check(F.count(p[i], "SetUserTarget") >= 1, "the scav target is set on peer " .. i)
    end
    local portalFighters = F.callsOf(p[1], "BuildObjectAtPortal")
    check(#portalFighters == 2 and portalFighters[1][4] == 5, "two portal fighters on the co-op enemy team")
    check(F.count(p[1], "Goto", portalFighters[1][2]) == 1, "portal fighters fly the unit path")
    heardAll(p, "bd04002.wav"); heardAll(p, "bd04003.wav")
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end

-- ------------------------------------------------------------------ cameras are shared and unskippable in a network game
do
    local w, p, m = setup(3, {})
    check(p[1].camera == 1 and F.count(p[1], "CameraReady") == 1, "the opening shot opens")
    check(F.last(p[1], "CameraPath")[2] == "camera_start_up" and F.last(p[1], "CameraPath")[5] == m.pilot, "the shot follows the walking pilot")
    F.run(1)
    for i = 2, 3 do check(F.last(p[i], "CameraPath") ~= nil and p[i].camera == 1, "guest " .. i .. " sees the same shot") end
    w.cancel = true; F.run(2)
    check(not m.cameraComplete[0], "a skip never ends the shared opening in a network game")
    check(p[1].camera == 0, "a skip releases only the skipper's own camera")
    w.cancel = false
    -- the pilot's walk, not the camera, ends the shared opening: nav_1, then nav_2 + 2 s
    F.nearTo(m.pilot, "nav_1", 0, 0); F.run(1)
    check(m.nav1 ~= nil and not m.cameraComplete[0], "the first beacon is placed by the walking pilot")
    F.nearTo(m.pilot, "nav_2", 0, 0); F.run(1)
    check(m.nav2 ~= nil and not m.cameraComplete[0], "the second beacon starts the 2 s delay")
    F.run(3)
    check(m.cameraComplete[0], "the opening ends with the pilot's walk")
    F.run(1)
    for i = 1, 3 do check(p[i].camera == 1, "the portal shot opens on peer " .. i) end
    F.run(7)
    for i = 1, 3 do check(p[i].camera == 0, "cameras balanced on peer " .. i) end
end
do -- offline: the same layer, skippable
    local w, p, m = setup(1, {})
    check(p[1].camera == 1, "offline opening opens")
    w.cancel = true; F.run(1)
    check(m.cameraComplete[0], "offline skip ends the opening")
    check(F.count(p[1], "UnHide") == 1 and F.perceived(p[1].player) == 5, "the skip still shows and disguises the player")
    w.cancel = false; F.run(40)
    check(F.count(p[1], "CameraReady") == 2, "a skipped opening never restarts (one opening, one portal shot)")
end

-- ------------------------------------------------------------------ the scav objective: any human, the focus follows
for n = 2, 4 do
    local w, p, m = setup(n, {})
    toScav(w, p, m)
    check(not m.objective1Complete and m.user == p[1].player, "nobody in the scav yet: the host is the player")
    enterScav(p[n]); F.run(2)
    check(m.objective1Complete, n .. " humans: the LAST guest commandeering the scav completes the objective")
    check(m.user == "scav_3", "the scav pilot is the body's player")
    heardAll(p, "bd04010.wav")
    check(F.count(p[1], "Goto", "scav_1") == 1 and F.count(p[1], "Goto", "scav_2") == 1, "the other scavs head down the scav path")
    guestsPassive(p)
end
do -- the reminder repeats every 120 s until someone is in the scav
    local w, p, m = setup(2, {})
    toScav(w, p, m)
    local before = F.heardCount(p[2], "bd04003.wav")
    F.run(122)
    check(F.heardCount(p[2], "bd04003.wav") == before + 1, "the 120 s reminder reaches the guest")
end

do -- documented dependency: a guest boarding an authored craft needs the OpenShim label-id hooks. Without them Redux
   -- sends the handle as nil, CRCoop never has all handles again and the runtime pauses the body (no crash, no progress).
    local w, p, m = setup(2, { nilAuthoredHandles = true })
    toScav(w, p, m)
    enterScav(p[2]); F.run(5)
    check(not m.objective1Complete, "without the label-id hooks the guest in the scav is invisible to the host")
    p[2].player = "player2"; F.run(3)
    enterScav(p[1]); F.run(2)
    check(m.objective1Complete, "the host in the scav always counts")
end

-- ------------------------------------------------------------------ the base: trigger_1, warnings, alarm, nearest-human turrets
do -- a scav that went by trigger_1 is safe, any human may then follow
    local w, p, m = setup(3, {})
    toScav(w, p, m)
    enterScav(p[2]); F.nearTo("scav_3", "trigger_1", 100, 0); F.run(1)
    check(m.trigger1, "the scav at trigger_1 latches the safe route")
    deepInBase("scav_3"); deepInBase(p[3].player); F.run(3)
    check(m.inBaseArea and not m.doAttack and F.heardCount(p[1], "bd04005.wav") == 0, "no alarm on the safe route, for the scav or a human on foot")
end
do -- the scav goes straight in: standing order, then the turrets lock on
    local w, p, m = setup(3, {})
    toScav(w, p, m)
    enterScav(p[2]); F.run(1)
    inBase("scav_3"); F.run(1)
    check(m.inBaseArea and not m.doAttack, "the bad entry warns first")
    heardAll(p, "bd04005.wav")
    F.run(3)
    heardAll(p, "bd04006.wav")
    check(m.doAttack, "after the second line the turrets attack")
    -- every turret orders the human nearest to it, priority 1
    for i = 0, 8 do
        local turret = "turret_" .. (i + 1)
        local target
        for _, c in ipairs(F.callsOf(p[1], "Attack")) do if c[2] == turret then target = c[3]; check(c[4] == 1, "priority 1") end end
        local best, bestD
        for _, q in ipairs(p) do
            local h = F.world().objects[q.player] and q.player
            local d = p[1].env.GetDistance(h, turret)
            if bestD == nil or d < bestD then best, bestD = h, d end
        end
        check(target == best, turret .. " attacks the human nearest to it: " .. tostring(target) .. " vs " .. tostring(best))
    end
    guestsPassive(p)
end
do -- a human on foot entering the base sets the alarm at once, even with the scav pilot still outside
    local w, p, m = setup(3, {})
    toScav(w, p, m)
    enterScav(p[2]); F.run(1)
    inBase(p[3].player); F.run(1)
    check(m.doAttack and m.inBaseArea, "a guest on foot in the base starts the attack")
    check(F.heardCount(p[1], "bd04005.wav") == 0, "no scav warning for a human on foot")
    local first = F.callsOf(p[1], "Attack")[1]
    check(first[3] == p[3].player or first[3] == p[2].player or first[3] == p[1].player, "orders name a human")
end
do -- a human who dies or changes craft is not left as a stale target
    local w, p, m = setup(2, {})
    toScav(w, p, m)
    enterScav(p[2]); F.run(1)
    inBase("scav_3"); F.run(5)
    check(m.doAttack, "alarm up")
    local orders = F.count(p[1], "Attack")
    F.run(3)
    check(F.count(p[1], "Attack") == orders, "stable humans do not re-order the turrets")
    local fresh = F.spawn("bsuser", 2, 1400, 101700)
    p[2].player = fresh; F.run(3)
    check(F.count(p[1], "Attack") > orders, "a new craft makes the turrets pick the nearest human again")
    local last
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do last = c end
    check(F.alive(last[3]), "the new order names a live human")
end

-- ------------------------------------------------------------------ inspection relay, the minute, the fragment
for n = 2, 4 do
    local w, p, m = setup(n, {})
    toScav(w, p, m)
    enterScav(p[1]); F.run(1)
    p[n].info.cbport = true; F.run(2); p[n].info.cbport = false; F.run(3)
    check(m.objective2Complete, n .. " humans: a guest inspecting the portal counts (IsInfo relay)")
    for i = 1, n do
        check(F.count(p[i], "StartCockpitTimer") == 1, "the minute shows on peer " .. i)
        check(F.heardCount(p[i], "bd04004.wav") == 1, "briefing line on peer " .. i)
    end
    check(F.count(p[n], "Send", "I") >= 1 and F.count(p[1], "Send", "I") == 0, "only guests send reports")
    local sends = F.callsOf(p[n], "Send")
    for _, c in ipairs(sends) do if c[2] == "I" then check(c[3] == "cbport", "the report names the prefix") end end
    -- the guest inspecting the data fragment stops the clock for everyone
    p[n].info.obdataa = true; F.run(2); p[n].info.obdataa = false
    check(m.idFragment and m.objective3Complete, "a guest identifying the fragment counts")
    for i = 1, n do
        check(F.count(p[i], "StopCockpitTimer") == 1, "the clock stops on peer " .. i)
        check(F.heardCount(p[i], "bd04007.wav") == 1, "bring-it-back line on peer " .. i)
    end
    check(not m.timeoutWarningStarted, "no timeout after the data was found")
    check(F.count(p[1], "Send", "I") == 0, "the host needs no report")
end
do -- an outsider cannot fake a report; a stale report expires
    local w, p, m = setup(2, {})
    toScav(w, p, m)
    p[1].env.Receive(2, "I", "cbport")
    check(F.count(p[1], "Send", "I") == 0, "a report never echoes")
    w.now = w.now + 0.1
    p[1].env.Receive(77, "I", "obdataa")
    p[1].env.Receive(2, "I", "bogus")
    F.run(0.5)
    check(not m.idFragment, "reports from unknown players or for other prefixes are ignored")
    F.run(3)
    check(m.objective2Complete, "the one genuine report counted")
end
do -- the one-minute check-in expires on the host's clock (the engine timer is the mission clock in this map)
    local w, p, m = setup(2, {})
    toScav(w, p, m)
    enterScav(p[1]); F.run(1)
    p[1].info.cbport = true; F.run(1); p[1].info.cbport = false
    F.run(55)
    check(not m.timeoutWarningStarted, "still inside the minute")
    F.run(8)
    check(m.timeoutWarningStarted, "after 60 s the standing order plays")
    heardAll(p, "bd04005.wav")
    F.run(3)
    heardAll(p, "bd04006.wav")
    check(m.doAttack, "and the attack follows")
    check(F.count(p[1], "HideCockpitTimer") >= 1 and F.count(p[2], "HideCockpitTimer") >= 1, "the timer hides everywhere")
    -- the faithful port on this map's clock never reaches the warning
    local fw, fp, fm = setup(1, { faithful = true, script = "Scripts/bd04.lua" })
    toScav(fw, fp, fm)
    enterScav(fp[1]); F.run(1)
    fp[1].info.cbport = true; F.run(1); fp[1].info.cbport = false
    F.run(70)
    check(not fm.timeoutWarningStarted, "the faithful port never sees its timer reach zero under the multiplayer mission clock")
end

-- ------------------------------------------------------------------ the fragment lifted by a guest, the strike, the win
for n = 1, 4 do
    local w, p, m = setup(n, {})
    toScav(w, p, m)
    enterScav(p[1]); F.run(1)
    p[1].info.cbport = true; F.run(1); p[1].info.cbport = false; F.run(2)
    p[1].info.obdataa = true; F.run(2); p[1].info.obdataa = false
    check(m.objective3Complete and m.outOfScav == false, "the data is found with the scav pilot still inside")
    -- every human stands by the hauler and the fragment (inside the base: the entry check comes first)
    for _, q in ipairs(p) do F.place(q.player, 1620, 101400) end
    F.place("scav_3", 1620, 101400); F.run(1)
    local last = p[n]
    enter(last, "hauler_1"); F.tug("fragment", "hauler_1"); F.run(2)
    check(m.gotFragment, n .. " human(s): the last human lifting the fragment counts")
    heardAll(p, "bd04009.wav") -- the restored line, once on every peer
    local mark = #p[1].calls
    local escorts = F.builds(p[1], 0, "bvfigh")
    check(#escorts == 3 and #F.builds(p[1], 0, "bvtank") == 3, "six Black Dog escorts, not scaled")
    for _, b in ipairs(escorts) do check(b.team == 1 and b.where == "escort_units", "escorts are on the humans' team") end
    check(F.count(p[1], "SetUserTarget") >= 1, "the restored rendezvous target is set on the host")
    for i = 1, n do check(F.count(p[i], "SetUserTarget") >= 2, "restored target reaches peer " .. i) end
    -- no attack yet
    check(#builtAt(p[1], "attack_1") == 0, "nothing attacks before the 30 s event")
    F.run(30); F.run(4) -- two tickets are built per frame
    check(m.dropZoneReady and #F.builds(p[1], 0, "bvhraza") == 5, "five bombers, the Drop Zone, then the strike")
    local e = extrasFor(n)
    local scouts, a1, a2, a3 = builtAt(p[1], "chinese_scout_x6_spawn_point"), builtAt(p[1], "attack_1"),
        builtAt(p[1], "attack_2", "cvfighg"), builtAt(p[1], "attack_3", "cvtnk")
    -- attack_1 is 98 m from the humans: that group comes in at the first clear hidden entry (the scout point)
    check(#a1 == 0, "attack_1 is watched: its group takes another entry")
    check(#scouts == 6 + e + 2 + e, n .. " human(s): scout group + the watched attack_1 group enter at the scout point, got " .. #scouts)
    check(#a2 == 4 + e and #a3 == 3 + e, n .. " human(s): attack_2 = " .. (4 + e) .. " and attack_3 = " .. (3 + e) .. ", got " .. #a2 .. "/" .. #a3)
    local all = {}
    for _, group in ipairs({scouts, a2, a3}) do for _, b in ipairs(group) do all[#all + 1] = b end end
    allSafe(p, all)
    for _, b in ipairs(all) do check(b.team == 5, "the strike is team 5") end
    local attackers = {}
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do if c[3] == "hauler_1" then attackers[c[2]] = c[4] end end
    local count = 0
    for _, b in ipairs(all) do
        check(attackers[b.h] == 1, "every striker (extras too) attacks the hauler at priority 1")
        count = count + 1
    end
    check(count == 15 + 4 * e, n .. " human(s): the strike is 15 + 4 x " .. e .. " units, got " .. count)
    check(F.count(p[1], "SetObjectiveName", m.navBeacon) >= 1, "the Drop Zone is named for everyone")
    check(F.count(p[1], "SetUserTarget") >= 2, "the restored Drop Zone target is set")
    for i = 1, n do check(F.count(p[i], "SetUserTarget") >= 3, "restored Drop Zone target reaches peer " .. i) end
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
    -- victory
    F.nearTo("fragment", m.navBeacon, 10, 0); F.run(2)
    check(m.won, "the fragment at the Drop Zone wins")
    heardAll(p, "bd04008.wav")
    F.run(8)
    for i = 1, n do check(F.count(p[i], "SucceedMission") == 1, "one victory on peer " .. i) end
    check(F.last(p[1], "SucceedMission")[3] == "bd04win.des", "bd04win.des")
    -- a hauler lost during the victory radio no longer fails it
    F.kill("hauler_1"); F.kill("portal"); F.run(3)
    for i = 1, n do check(F.count(p[i], "FailMission") == 0, "a loss after the win is ignored on peer " .. i) end
    -- after the win nothing more is sent
    local builds = #F.builds(p[1], 0)
    F.run(30)
    check(#F.builds(p[1], 0) == builds, "no more reinforcements after the win")
end
do -- the strikers go after the hauler even when the hauler is the host's own craft and another human is nearer to them
    local w, p, m = setup(2, {})
    toScav(w, p, m)
    p[1].info.cbport = true; F.run(1); p[1].info.cbport = false
    p[1].info.obdataa = true; F.run(1); p[1].info.obdataa = false; F.run(1)
    F.place(p[1].player, 1620, 101400); F.place(p[2].player, 1983, 100500)
    enter(p[1], "hauler_1"); F.tug("fragment", "hauler_1"); F.run(2)
    check(m.gotFragment and m.user == "hauler_1", "the host in the hauler lifts the fragment")
    F.run(34)
    local strikers = 0
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do
        if F.world().objects[c[2]] and F.world().objects[c[2]].odf:sub(1, 4) == "cvfi" or F.world().objects[c[2]].odf == "cvtnk" then
            strikers = strikers + 1
            check(c[3] == "hauler_1", "a striker keeps the hauler as its target, not the nearest human: " .. tostring(c[3]))
        end
    end
    check(strikers >= 15, "the strike exists: " .. strikers)
end
do -- the 460 m rule moves a group, and a pending group waits for a clear entry
    local w, p, m = setup(2, {})
    toScav(w, p, m)
    enterScav(p[1]); F.run(1)
    p[1].info.cbport = true; F.run(1); p[1].info.cbport = false
    p[1].info.obdataa = true; F.run(1); p[1].info.obdataa = false
    enter(p[1], "hauler_1"); F.tug("fragment", "hauler_1")
    -- surround the strike's entries so nothing is clear
    F.place("hauler_1", 1500, 100800); F.place(p[2].player, 1100, 100700); F.run(1)
    F.run(33)
    check(m.dropZoneReady, "the strike is requested")
    local pending = 0
    for _ in pairs(p[1].env.Save().crcca.arrivals) do pending = pending + 1 end
    local built = #F.builds(p[1], 0, "cvfighg") + #F.builds(p[1], 0, "cvtnk")
    check(built + pending == 15 + 4, "built and waiting add up to the strike (2 humans: 1 extra per group)")
    for _, b in ipairs(F.builds(p[1], 0)) do
        if b.odf:sub(1, 2) == "cv" then
            for _, q in ipairs(p) do check(q.env.GetDistance(q.player, b.h) >= 460, "no pop-in near a human") end
        end
    end
end
do -- route ambushes: ungated, scaled, from a hidden entry
    for n = 1, 3 do
        local w, p, m = setup(n, {})
        F.nearTo("hauler_1", "return_1", 100, 0)
        for _, q in ipairs(p) do F.place(q.player, 2400, 99000) end
        F.run(4)
        check(m.returnAttack[0] and not m.returnAttack[1], "return_1 is sprung by the hauler")
        local fighters = builtAt(p[1], "return_1", "cvfigh")
        check(#fighters == 3 + extrasFor(n), n .. " human(s): three fighters + extras at return_1, got " .. #fighters)
        allSafe(p, fighters)
        for _, b in ipairs(fighters) do check(b.team == 5, "ambushers are team 5") end
        local hits = 0
        for _, c in ipairs(F.callsOf(p[1], "Attack")) do if c[3] == "hauler_1" and c[4] == nil then hits = hits + 1 end end
        check(hits == 3 + extrasFor(n), "every ambusher attacks the hauler (extras mirror the order)")
        F.run(5)
        check(#builtAt(p[1], "return_1", "cvfigh") == #fighters, "an ambush springs once")
    end
end

-- ------------------------------------------------------------------ results
do -- the hauler or the portal lost fails everyone once
    for _, victim in ipairs({"hauler_1", "portal"}) do
        local w, p, m = setup(3, {})
        toScav(w, p, m)
        F.kill(victim); F.run(3)
        for i = 1, 3 do
            check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd04lose.des", victim .. " lost: one failure on peer " .. i)
        end
        F.kill(victim == "portal" and "hauler_1" or "portal"); F.run(3)
        for i = 1, 3 do check(F.count(p[i], "FailMission") == 1, "a second loss does not repeat the failure") end
    end
end

-- ------------------------------------------------------------------ disguise upkeep
do -- a human whose pilot dies and respawns is disguised again; ejecting from the scav is not a respawn
    local w, p, m = setup(3, {})
    toScav(w, p, m)
    check(F.perceived(p[2].player) == 5, "disguised at the film's end")
    local old = p[2].player
    F.kill(old)
    local fresh = F.spawn("bsuser", 2, 1850, 101209)
    check(F.perceived(fresh) == 2, "a new pilot starts undisguised (perceived = real team)")
    p[2].player = fresh; F.run(3)
    check(F.perceived(fresh) == 5, "the respawned pilot is disguised like the others")
    for i = 1, 3 do check(F.count(p[i], "SetPerceivedTeam", fresh) == 1, "once, on peer " .. i) end
    enterScav(p[3]); F.run(2)
    local ejected = F.spawn("aspilo", 3, 2144, 101340)
    p[3].player = ejected; F.run(3)
    check(F.perceived(ejected) == 3, "a pilot ejecting from a live scav is not re-disguised (as in the body)")
end

-- ------------------------------------------------------------------ saves
do
    local function copy(t, seen)
        if type(t) ~= "table" then return t end
        seen = seen or {}
        if seen[t] then return seen[t] end
        local out = {}
        seen[t] = out
        for k, v in pairs(t) do out[copy(k, seen)] = copy(v, seen) end
        return out
    end
    -- Saves exist offline (a network game cannot be loaded). Loading in the middle of the opening shot ends it (the
    -- cameras are gone), without a stuck camera.
    local w, p, m = setup(1, {})
    check(m.cameraReady[0] and not m.cameraComplete[0], "mid-intro")
    local saved = copy(p[1].env.Save())
    p[1].env.Load(saved)
    local paths = F.count(p[1], "CameraPath")
    F.run(2)
    check(F.count(p[1], "CameraPath") == paths, "the loaded shot is not resumed")
    check(saved.cameraComplete[0], "the loaded intro finishes")
    -- and in the middle of the portal shot
    F.run(1)
    check(saved.cameraReady[1], "the portal shot runs")
    local portalShots = F.count(p[1], "CameraPath", "camera_portal")
    p[1].env.Load(copy(p[1].env.Save()))
    F.run(8)
    check(F.count(p[1], "CameraPath", "camera_portal") == portalShots, "a loaded portal shot is not resumed either")
    check(p[1].env.Save().cameraComplete[1] and p[1].env.Save().gotoScav, "it still ends on its own timer")
    check(F.count(p[1], "BuildObjectAtPortal") == 2 and F.count(p[1], "PortalOut") == 1, "the portal film is not replayed")
    -- the minute survives a save
    local w2, q, m2 = setup(1, {})
    toScav(w2, q, m2)
    enterScav(q[1]); F.run(1)
    q[1].info.cbport = true; F.run(1); q[1].info.cbport = false
    F.run(20)
    local snapshot = copy(q[1].env.Save())
    q[1].env.Load(snapshot)
    F.run(30)
    check(not snapshot.timeoutWarningStarted, "40 s into the minute after the load")
    F.run(25)
    check(snapshot.timeoutWarningStarted and F.heardCount(q[1], "bd04005.wav") == 1, "the minute still expires once after a load")
    check(F.count(q[1], "BuildObjectAtPortal") == 2, "a load never replays the portal film")
    -- a load resets the presentation: objectives, the minute and the disguise are published again
    local w3, r, m3 = setup(1, {})
    toScav(w3, r, m3)
    enterScav(r[1]); F.run(1)
    r[1].info.cbport = true; F.run(1); r[1].info.cbport = false
    F.run(20)
    local before = #r[1].calls
    r[1].env.Load(copy(r[1].env.Save()))
    F.run(1)
    local objective, timer, disguise
    for i = before + 1, #r[1].calls do
        local c = r[1].calls[i]
        if c[1] == "AddObjective" and c[2] == "bd04004.otf" then objective = true end
        if c[1] == "StartCockpitTimer" and type(c[2]) == "number" and c[2] > 30 and c[2] < 41 and c[3] == 15 and c[4] == 5 then timer = true end
        if c[1] == "SetPerceivedTeam" then disguise = true end
    end
    check(objective, "the portal objective is published again after a load")
    check(timer, "the minute is re-issued with its remaining time (about 39 s) after a load")
    check(disguise, "the disguise is applied again after a load")
    -- the data found: the fragment objective after a load
    r[1].info.obdataa = true; F.run(1); r[1].info.obdataa = false; F.run(1)
    before = #r[1].calls
    r[1].env.Load(copy(r[1].env.Save()))
    F.run(1)
    local fragment, stale
    for i = before + 1, #r[1].calls do
        local c = r[1].calls[i]
        if c[1] == "AddObjective" and c[2] == "bd04003.otf" and c[3] == "white" then fragment = true end
        if c[1] == "StartCockpitTimer" then stale = true end
    end
    check(fragment and not stale, "the fragment objective returns after a load, and no stopped minute with it")
end

-- ------------------------------------------------------------------ a missing audio handle counts as finished
do
    local w, p, m = setup(1, {})
    toScav(w, p, m)
    enterScav(p[1]); F.run(1)
    p[1].info.cbport = true; F.run(1); p[1].info.cbport = false; F.run(3)
    p[1].info.obdataa = true; F.run(1); p[1].info.obdataa = false; F.run(1)
    enter(p[1], "hauler_1"); F.tug("fragment", "hauler_1"); F.run(34)
    check(m.dropZoneReady, "the drop zone is up")
    w.audioBusy = true -- the congratulation never finishes by itself
    F.nearTo("fragment", m.navBeacon, 10, 0); F.run(1)
    check(m.won and m.congrats ~= nil and F.count(p[1], "SucceedMission") == 0, "the win is declared and waits on its line")
    m.congrats = 0 -- an audio call that returned no handle
    F.run(2)
    check(m.congrats == nil and F.count(p[1], "SucceedMission") == 1, "a congratulation without an audio handle still completes the win")
end

-- ------------------------------------------------------------------ a human killed in a craft respawns as a pilot
do
    -- the shared respawn module places the new pilot; the fixture has no placement mocks
    GetPositionNear = GetPositionNear or function(pos) return { x = pos.x, y = pos.y, z = pos.z } end
    GetTerrainHeightAndNormal = GetTerrainHeightAndNormal or function() return 0, { x = 0, y = 1, z = 0 } end
    local w, p, m = setup(2, {})
    toScav(w, p, m)
    enterScav(p[2]); F.run(2)
    local scav = p[2].player
    F.kill(scav)
    local fresh = F.spawn("bsuser", 2, 1850, 101209)
    p[2].player = fresh; F.run(3)
    check(F.perceived(fresh) == 5, "a human killed in a craft who respawns as a pilot is disguised again")
end

-- ------------------------------------------------------------------ weather: Ganymede, tied to the story
do
    local w, p, m = setup(2, {})
    local host = p[1].weatherCalls
    local function has(name, a) for _, c in ipairs(host) do if c[1] == name and (a == nil or c[2] == a) then return true end end return false end
    check(F.count(p[1], "WeatherSensors", "Ganymede") == 1 and F.count(p[2], "WeatherSensors", "Ganymede") == 1, "sensors follow the Ganymede director on every peer")
    check(has("Init"), "the director starts")
    check(not has("SetTargetLevel"), "calm until the story moves")
    toScav(w, p, m)
    check(has("SetTargetLevel", 2) and has("Quake"), "the portal raises the weather and shakes the ice")
    enterScav(p[1]); F.run(1)
    inBase("scav_3"); F.run(6)
    check(m.doAttack and has("SetTargetLevel", 3) and has("Surge"), "the alarm raises it again with a radiation surge")
    p[1].info.cbport = true; F.run(1); p[1].info.cbport = false
    p[1].info.obdataa = true; F.run(1); p[1].info.obdataa = false
    enter(p[1], "hauler_1"); F.tug("fragment", "hauler_1"); F.run(2)
    local quakes = 0
    for _, c in ipairs(host) do if c[1] == "Quake" then quakes = quakes + 1 end end
    check(quakes >= 2, "lifting the fragment shakes the ice")
    F.run(30)
    check(has("SetTargetLevel", 4), "the strike is the top of this mission's ladder")
    check(not has("TriggerPlume"), "no plume: the generated Ganymede site table has no vents")
    F.nearTo("fragment", m.navBeacon, 5, 0); F.run(2)
    check(has("ReleaseForcedLevel") and host[#host][1] == "SetTargetLevel" and host[#host][2] == 1, "victory eases the sky")
    for _, c in ipairs(p[2].weatherCalls) do
        check(c[1] ~= "SetTargetLevel" and c[1] ~= "Quake" and c[1] ~= "Surge", "a guest never originates weather beats")
    end
end
do -- the weather is optional: a missing module never stops the mission
    local w, p, m = setup(2, { weather = false })
    toScav(w, p, m)
    check(m.gotoScav, "the mission runs without weather")
end

print("bdmisn04 co-op: " .. checks .. " checks passed")
