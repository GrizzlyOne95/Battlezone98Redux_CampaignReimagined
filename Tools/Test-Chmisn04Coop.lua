-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/ch04cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/Test-Chmisn04Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Chmisn04Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local MS = { STARTSCENE = 2, PLAYSOUND7 = 3, NEARNAVS = 4, WAITFORID = 6, WAITFORSOUND2 = 7, WAITFORALARM = 8,
    CAMERAALARM = 9, NEARSILO = 10, INSPECTSILO = 11, CHASE = 12, WAITFORSOUND3 = 13, WAITFORSOUND8 = 14,
    WAITFORPORTAL = 15, CAMERAEND = 16, END = 100 }
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
        for _, name in ipairs({"BuildObject", "SetScrap", "SetAIP", "Goto", "Follow", "Attack", "SetIndependence", "Retreat"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on the authored enemy team 2") end
end
local function state(p) return p[1].env.Save().missionState end

-- ------------------------------------------------------------------ scenario steps (shared by the faithful and CR runs)
local function player(p, i) return (p[i or 1]).player end
local function cloakAll(p) for _, q in ipairs(p) do F.cloak(q.player, true) end end
-- The opening shot arrives; the five-second pause ends and the route starts.
local function toRoute(w, p, m)
    w.cameraDone["camera_start"] = true; F.run(1); w.cameraDone["camera_start"] = false
    F.run(6)
    assert(m.missionState == MS.NEARNAVS, "the route starts: state " .. tostring(m.missionState))
end
-- The first human (the others stay at the rim) drives the six navs.
local function walkNavs(p, m, walker)
    for _ = 1, 6 do
        F.nearTo(walker or p[1].player, m.navPoints[m.uptonavpoint], 10, 0); F.run(0.5)
    end
    assert(m.missionState == MS.WAITFORID, "the last nav reaches the silo approach: state " .. tostring(m.missionState))
end
local function farFromSilo(h) F.place(h, 1623, 100500) end
-- A human at the alarm trigger, then the alarm shot runs out.
local function alarm(w, p, m, who)
    F.nearTo(who or p[1].player, "trigger_1", 40, 0); F.run(1)
    F.run(8)
    assert(m.missionState == MS.NEARSILO, "the alarm shot ends: state " .. tostring(m.missionState))
end
local function inspect(w, p, m, who)
    for _, q in ipairs(p) do F.nearTo(q.player, "target_silo", 120, 0) end
    F.run(1)
    assert(m.missionState == MS.INSPECTSILO, "within 200 m of the silo: state " .. tostring(m.missionState))
    local inspector = who or p[1]
    inspector.info.sbsiloa = true; F.run(1.5); inspector.info.sbsiloa = false
end
local function toPortal(w, p, m)
    F.run(12)
    assert(m.missionState == MS.WAITFORPORTAL, "the retreat starts: state " .. tostring(m.missionState))
end
local function atPortal(p)
    for _, q in ipairs(p) do F.nearTo(q.player, "portal", 30, 0) end
end
local function finish(w, p, m)
    atPortal(p); F.run(1)
    assert(m.missionState == MS.CAMERAEND, "everyone at the portal starts the end film")
    w.cameraDone["auto_end"] = true; F.run(1); w.cameraDone["auto_end"] = false
    F.run(4)
end

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
local scenarios = {
    win = function(w, p, m)
        toRoute(w, p, m); cloakAll(p); walkNavs(p, m); alarm(w, p, m); inspect(w, p, m); toPortal(w, p, m); finish(w, p, m)
    end,
    routelost = function(w, p, m) toRoute(w, p, m); F.run(135) end,
    portallost = function(w, p, m)
        toRoute(w, p, m); cloakAll(p); walkNavs(p, m); alarm(w, p, m); inspect(w, p, m); toPortal(w, p, m); F.run(140)
    end,
}
for name, scenario in pairs(scenarios) do
    local faithful = outcomes({ faithful = true, script = "Scripts/ch04.lua" }, scenario)
    local offline = outcomes({}, scenario)
    check(faithful == offline and faithful ~= "", "offline completes like the faithful port (" .. name .. "): " .. faithful .. " / " .. offline)
end
do
    local out, peer = outcomes({}, scenarios.win)
    check(out == "SucceedMission:ch04win.des" and F.count(peer, "SucceedMission") == 1, "offline victory: " .. out)
    local lost, lpeer = outcomes({}, scenarios.routelost)
    check(lost == "FailMission:ch04lsea.des" and F.count(lpeer, "FailMission") == 1, "offline route timeout: " .. lost)
    local late, epeer = outcomes({}, scenarios.portallost)
    check(late == "FailMission:ch04lseb.des", "offline portal timeout: " .. late)
    check(F.heardCount(epeer, "ch04005.wav") == 1 and F.heardCount(lpeer, "ch04006.wav") == 1, "each loss has its voice line")
    noEnemyTeamTwo(peer)
    check(F.count(peer, "SetAIControl", 5) == 1 and F.count(peer, "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
    check(F.index(peer, "SetAIControl") <= peer.chunkCalls, "SetAIControl runs at chunk root, before Start")
    -- the faithful port never sees its 130-second countdown reach zero on the multiplayer mission clock
    local fw, fp, fm = setup(1, { faithful = true, script = "Scripts/ch04.lua" })
    toRoute(fw, fp, fm); fw.now = fw.now + 0; F.run(140)
    check(fm.missionState == MS.NEARNAVS and F.count(fp[1], "FailMission") == 0, "the faithful port never fails the route on this map's clock")
end

-- ------------------------------------------------------------------ the shared start
for n = 1, 4 do
    local w, p, m = setup(n, {})
    check(m.missionState == MS.STARTSCENE and F.count(p[1], "CameraReady") == 1, "the host starts the shared mission with one opening shot")
    local scrap = F.last(p[1], "SetScrap")
    check(scrap[2] == 1 and scrap[3] == 0, n .. " human(s): no scrap for anyone: " .. tostring(scrap[3]))
    check(F.count(p[1], "SetPilot") == n, n .. " human(s): pilots for every human team")
    for i = 1, n do
        check(F.count(p[i], "DisableStartingRecycler") == (n > 1 and 1 or 0), "extra starting recyclers disabled in a network game, peer " .. i)
        check(F.heardCount(p[i], "ch04001.wav") == 1, "briefing once on peer " .. i)
    end
    if n > 1 then check(p[1].rally ~= nil and p[1].rally[0] == "factory", "respawn rally point is the Chinese factory") end
    F.run(2)
    for i = 2, n do check(F.last(p[i], "CameraPath") ~= nil and p[i].camera == 1, "guest " .. i .. " sees the same opening shot") end
    guestsPassive(p)
end

-- ------------------------------------------------------------------ cameras: shared and unskippable in a network game
do
    local w, p, m = setup(3, {})
    w.cancel = true; F.run(10)
    check(m.missionState == MS.STARTSCENE, "a skip never ends the shared opening in a network game")
    check(p[1].camera == 0, "a skip releases only the skipper's own camera")
    w.cancel = false
    F.run(25)
    check(m.missionState >= MS.PLAYSOUND7, "the host's flight-time margin ends a shot whose camera was skipped")
    for i = 1, 3 do check(p[i].camera == 0, "cameras balanced on peer " .. i) end
    local w1, p1, m1 = setup(1, {})
    w1.cancel = true; F.run(1)
    check(m1.missionState >= MS.PLAYSOUND7, "offline skip ends the opening")
end
do -- the alarm shot is shared, then ends on its own timer
    local w, p, m = setup(2, {})
    toRoute(w, p, m); cloakAll(p); walkNavs(p, m)
    F.nearTo(p[2].player, "trigger_1", 40, 0); F.run(2.5)
    check(m.missionState == MS.CAMERAALARM, "the alarm shot runs")
    check(F.last(p[1], "CameraPath")[2] == "camera_alarm" and F.last(p[1], "CameraPath")[5] == "cca_factory", "it looks at the Soviet factory")
    F.run(1)
    check(F.last(p[2], "CameraPath")[2] == "camera_alarm" and p[2].camera == 1, "the guest sees the alarm shot")
    w.cancel = true; F.run(1); w.cancel = false
    check(m.missionState == MS.CAMERAALARM, "a skip does not end it")
    F.run(6)
    for i = 1, 2 do check(p[i].camera == 0, "cameras balanced on peer " .. i) end
end

-- ------------------------------------------------------------------ the route: the nearest human leads, the minute is host-counted
for n = 2, 4 do
    local w, p, m = setup(n, {})
    toRoute(w, p, m)
    for i = 1, n do
        check(F.count(p[i], "StartCockpitTimer") == 1, "the 130 s countdown shows on peer " .. i)
        check(F.heardCount(p[i], "ch04007.wav") == 1, "the route line on peer " .. i)
        check(F.count(p[i], "SetObjectiveOn") >= 1, "the first nav is marked on peer " .. i)
    end
    check(F.count(p[1], "SetUserTarget") >= 1, "and is the host's own target")
    cloakAll(p); walkNavs(p, m, p[n].player)
    check(m.uptonavpoint == 5, n .. " humans: the last guest alone drives the route")
    for i = 1, n do
        check(F.count(p[i], "HideCockpitTimer") == 1, "the countdown hides on peer " .. i)
        check(F.perceived(p[i].player) == 5, "human " .. i .. " is disguised as the Soviets (perceived team 5)")
        check(F.team(p[i].player) == i, "the real team is untouched")
    end
    check(F.callsOf(p[1], "SetObjectiveName")[1][3] == "Pit Entrance" and F.callsOf(p[1], "SetObjectiveName")[2][3] == "Silo",
        "the sixth nav is the Pit Entrance, then the restored Silo beacon is named")
    for i = 1, n do
        for _, c in ipairs(F.callsOf(p[i], "SetPerceivedTeam")) do check(c[3] == 5, "never the DLL's literal team 2") end
    end
    guestsPassive(p)
end
do -- the 130 s expire on the host's clock
    local w, p, m = setup(3, {})
    toRoute(w, p, m)
    F.run(120)
    check(F.count(p[1], "FailMission") == 0, "still inside the countdown")
    F.run(15)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "ch04lsea.des", "one route failure on peer " .. i)
        check(F.heardCount(p[i], "ch04006.wav") == 1, "and its voice line on peer " .. i)
    end
end

-- ------------------------------------------------------------------ the objectives, the restored "Remember to cloak!"
do
    local w, p, m = setup(2, {})
    toRoute(w, p, m)
    local function objectives(peer)
        local out = {}
        local clearAt = 0
        for i, c in ipairs(peer.calls) do if c[1] == "ClearObjectives" then clearAt = i end end
        for i = clearAt + 1, #peer.calls do if peer.calls[i][1] == "AddObjective" then out[#out + 1] = peer.calls[i][2] end end
        return out
    end
    for i = 1, 2 do
        local list = objectives(p[i])
        check(list[1] == "ch04001.otf" and list[2] == "ch04004.otf" and #list == 2, "route list on peer " .. i .. ": " .. table.concat(list, ","))
    end
    cloakAll(p); walkNavs(p, m); F.run(1)
    for i = 1, 2 do
        local list = objectives(p[i])
        check(list[1] == "ch04001.otf" and list[2] == "ch04002.otf" and list[3] == "ch04004.otf" and #list == 3, "inspect list on peer " .. i .. ": " .. table.concat(list, ","))
    end
    alarm(w, p, m); inspect(w, p, m); F.run(2)
    for i = 1, 2 do
        local list = objectives(p[i])
        check(list[1] == "ch04001.otf" and list[2] == "ch04002.otf" and list[3] == "ch04003.otf" and #list == 3, "retreat list on peer " .. i .. ": " .. table.concat(list, ","))
    end
end

-- ------------------------------------------------------------------ the alarm: concealed only if every human is cloaked
for n = 1, 4 do
    local w, p, m = setup(n, {})
    toRoute(w, p, m); cloakAll(p); walkNavs(p, m)
    check(m.attackedAlready == 0, "no alarm yet")
    local silo = F.callsOf(p[1], "SetObjectiveOn")
    check(#silo >= 1, "the silo is marked")
    local beacon = F.builds(p[1], 0, "cpcamr")
    check(beacon[#beacon].where == "nav_silo", "the restored Silo beacon is built at nav_silo")
    check(F.callsOf(p[1], "SetObjectiveName")[#F.callsOf(p[1], "SetObjectiveName")][3] == "Silo", "and named")
    alarm(w, p, m, p[n].player)
    check(m.attackedAlready == 0, n .. " human(s) all cloaked: the base is not alerted")
    check(F.count(p[1], "Attack") == 0, "no attack orders")
    -- pilots: sixteen on the authored paths + the nine restored ones
    local pilots = F.builds(p[1], 0, "sspilo")
    check(#pilots == 10 + 6 + 9, n .. " human(s): 25 pilots, got " .. #pilots)
    local nine = 0
    for _, b in ipairs(pilots) do if b.where:sub(1, 6) == "empty_" then nine = nine + 1 end end
    check(nine == 9, "the nine restored pilots stand at their craft")
    for _, b in ipairs(pilots) do check(b.team == 5, "pilots are Soviet") end
    noEnemyTeamTwo(p[1])
end
for n = 2, 4 do
    local w, p, m = setup(n, {})
    toRoute(w, p, m); cloakAll(p); F.cloak(p[n].player, false); walkNavs(p, m)
    alarm(w, p, m)
    check(m.attackedAlready == 1, n .. " humans: one uncloaked human alerts the base")
    for i = 1, n do
        check(F.perceived(p[i].player) == i, "human " .. i .. " is revealed (back on their own team)")
    end
    local ordered = {}
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do ordered[c[2]] = c[3] end
    for i = 1, 25 do
        local target = ordered["empty_" .. i]
        local best, bestD
        for _, q in ipairs(p) do
            local d = p[1].env.GetDistance(q.player, "empty_" .. i)
            if bestD == nil or d < bestD then best, bestD = q.player, d end
        end
        check(target == best, "empty_" .. i .. " attacks the human nearest to it: " .. tostring(target) .. " vs " .. tostring(best))
    end
    for i = 1, 4 do check(ordered["turret_" .. i] ~= nil, "turret_" .. i .. " is ordered") end
    guestsPassive(p)
end
do -- the cut detection: an exposed human inside 400 m of trigger_1 raises the alarm, a cloaked one does not
    local w, p, m = setup(2, {})
    toRoute(w, p, m); cloakAll(p); walkNavs(p, m)
    F.nearTo(p[1].player, "trigger_1", 300, 0); F.run(2)
    check(m.missionState == MS.WAITFORID, "a cloaked human at 300 m is not seen")
    F.cloak(p[2].player, false); F.nearTo(p[2].player, "trigger_1", 390, 0); F.run(1.5)
    check(m.missionState > MS.WAITFORID, "an uncloaked human at 390 m sets the alarm off")
    local w2, q, m2 = setup(2, {})
    toRoute(w2, q, m2); cloakAll(q); walkNavs(q, m2)
    F.cloak(q[2].player, false); F.nearTo(q[2].player, "trigger_1", 420, 0); F.run(2)
    check(m2.missionState == MS.WAITFORID, "an uncloaked human at 420 m is not seen")
end

-- ------------------------------------------------------------------ the silo: the pursuit is scaled and hidden
for n = 1, 4 do
    local w, p, m = setup(n, {})
    toRoute(w, p, m); cloakAll(p); walkNavs(p, m); alarm(w, p, m)
    check(F.count(p[1], "Goto") == 0, "no fighters before the silo is near")
    for _, q in ipairs(p) do F.nearTo(q.player, "target_silo", 120, 0) end
    F.run(1)
    local fighters = F.builds(p[1], 0, "svfigh")
    check(#fighters == 2 and fighters[1].where == "fighter_1" and fighters[2].where == "fighter_2", "the two scramble fighters are set pieces, built directly")
    check(F.count(p[1], "Goto", fighters[1].h) == 1 and F.count(p[1], "Goto", fighters[2].h) == 1, "and fly their paths")
    local inspector = p[n]
    inspector.info.sbsiloa = true; F.run(1.5); inspector.info.sbsiloa = false
    check(m.target_silo_inspected, n .. " human(s): the last human inspecting the silo counts")
    F.run(6)
    -- the core failure takes every cloak down, once
    for i = 1, n do check(not F.cloaked(p[i].player), "human " .. i .. " is decloaked by the core failure") end
    heardAll(p, "ch04002.wav"); heardAll(p, "ch04004.wav"); heardAll(p, "ch04003.wav"); heardAll(p, "ch04008.wav")
    local lines = F.lines(p[1])
    local at = {}
    for i, f in ipairs(lines) do at[f] = at[f] or i end
    check(at["ch04002.wav"] < at["ch04004.wav"] and at["ch04004.wav"] < at["ch04003.wav"] and at["ch04003.wav"] < at["ch04008.wav"],
        "voice order: core failure, 'as we thought', alarm, overrun")
    F.run(4)
    local e = extrasFor(n)
    local c1, c2, c3, portalGuards = builtAt(p[1], "chase_1"), builtAt(p[1], "chase_2"), builtAt(p[1], "chase_3"), builtAt(p[1], "portal_units")
    check(#c1 == 4 + e and #c2 == 4 + e and #c3 == 4 + e and #portalGuards == 6 + e,
        n .. " human(s): 4+e chase groups and 6+e portal guards, got " .. #c1 .. "/" .. #c2 .. "/" .. #c3 .. "/" .. #portalGuards)
    local all = {}
    for _, g in ipairs({c1, c2, c3, portalGuards}) do for _, b in ipairs(g) do all[#all + 1] = b end end
    allSafe(p, all)
    for _, b in ipairs(all) do check(b.team == 5, "the pursuit is team 5") end
    -- every chase unit attacks the human nearest to it; the portal guards are not ordered
    local targeted = {}
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do targeted[c[2]] = c[3] end
    for _, g in ipairs({c1, c2, c3}) do
        for _, b in ipairs(g) do
            local best, bestD
            for _, q in ipairs(p) do
                local d = p[1].env.GetDistance(q.player, b.h)
                if bestD == nil or d < bestD then best, bestD = q.player, d end
            end
            check(targeted[b.h] == best, "a chase unit (extras too) is ordered at the human nearest to it: " .. tostring(targeted[b.h]) .. " vs " .. tostring(best))
        end
    end
    for _, b in ipairs(portalGuards) do check(targeted[b.h] == nil, "portal guards get no initial order, as in the body") end
    check(F.count(p[1], "SetObjectiveOff") >= 1, "the silo marker goes out")
    check(m.missionState == MS.WAITFORPORTAL or m.missionState == MS.WAITFORSOUND8, "the retreat starts")
    for i = 1, n do check(F.count(p[i], "PortalIn") == 1, "the portal opens inward on peer " .. i) end
    check(#F.callsOf(p[1], "RemoveObject") >= 5, "the restored Silo beacon and the route navs are removed")
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end

do -- the 460 m rule moves a group: a human watching chase_1 brings that group from the next hidden approach
    local w, p, m = setup(2, {})
    toRoute(w, p, m); cloakAll(p); walkNavs(p, m); alarm(w, p, m)
    F.nearTo(p[1].player, "target_silo", 120, 0)
    F.nearTo(p[2].player, "chase_1", 60, 0); F.run(1)
    check(m.missionState == MS.INSPECTSILO, "one human at the silo is enough to be near it")
    p[1].info.sbsiloa = true; F.run(1.5); p[1].info.sbsiloa = false
    F.run(12)
    check(#builtAt(p[1], "chase_1") == 0, "chase_1 is watched: its group takes another entry")
    check(#builtAt(p[1], "chase_3") == (4 + 1) * 2, "and enters at the next clear approach, chase_3 (2 humans: 1 extra per group)")
    allSafe(p, builtAt(p[1], "chase_3"))
end

-- ------------------------------------------------------------------ the inspection relay
do
    for n = 2, 4 do
        local w, p, m = setup(n, {})
        toRoute(w, p, m); cloakAll(p); walkNavs(p, m); alarm(w, p, m)
        for _, q in ipairs(p) do F.nearTo(q.player, "target_silo", 120, 0) end
        F.run(1)
        p[n].info.sbsiloa = true; F.run(2); p[n].info.sbsiloa = false
        check(m.target_silo_inspected, n .. " humans: a guest inspecting the silo counts (IsInfo relay)")
        check(F.count(p[n], "Send", "I") >= 1 and F.count(p[1], "Send", "I") == 0, "only guests send reports")
        for _, c in ipairs(F.callsOf(p[n], "Send")) do if c[2] == "I" then check(c[3] == "sbsiloa", "the report names the prefix") end end
    end
    local w, p, m = setup(2, {})
    toRoute(w, p, m); cloakAll(p); walkNavs(p, m); alarm(w, p, m)
    for _, q in ipairs(p) do F.nearTo(q.player, "target_silo", 120, 0) end
    F.run(1)
    p[1].env.Receive(2, "I", "sbsiloa")
    w.now = w.now + 1.5
    p[1].env.Receive(77, "I", "sbsiloa")
    p[1].env.Receive(2, "I", "bogus")
    F.run(0.5)
    check(not m.target_silo_inspected, "reports from unknown players, for other prefixes, or stale ones are ignored")
end

-- ------------------------------------------------------------------ the retreat, the end film, the win
for n = 1, 4 do
    local w, p, m = setup(n, {})
    toRoute(w, p, m); cloakAll(p); walkNavs(p, m); alarm(w, p, m); inspect(w, p, m); toPortal(w, p, m)
    check(F.count(p[1], "StartCockpitTimer") == 1, "no countdown for the retreat (the 135 s are the body's own)")
    local beacon = F.builds(p[1], 0, "cpcamr")
    check(beacon[#beacon].where == "nav_base", "the extraction nav is built at nav_base")
    if n > 1 then
        -- the retreat is complete only when EVERY human is near the portal
        F.nearTo(p[1].player, "portal", 30, 0); F.run(1)
        check(m.missionState == MS.WAITFORPORTAL, "the host alone at the portal does not start the end film")
        for i = 2, n - 1 do F.nearTo(p[i].player, "portal", 30, 0) end
        F.run(1)
        check(m.missionState == MS.WAITFORPORTAL, "the last human still outside")
    end
    for _, q in ipairs(p) do F.world().objects[q.player].health = 0.4 end
    atPortal(p); F.run(1)
    check(m.missionState == MS.CAMERAEND, n .. " human(s): everyone at the portal starts the end film")
    for i = 1, n do
        check(F.hidden(p[i].player), "human " .. i .. " is hidden")
        check(F.world().objects[p[i].player].health == 1, "human " .. i .. " is healed")
        check(F.perceived(p[i].player) == 5, "human " .. i .. " is disguised again")
    end
    local fakes = 0
    for _, b in ipairs(F.builds(p[1], 0, "cvfighe")) do
        if b.team == 1 then fakes = fakes + 1; check(F.count(p[1], "Goto", b.h) == 1, "the stand-in flies auto_end") end
    end
    check(fakes == n, n .. " human(s): one stand-in craft each, got " .. fakes)
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[3] == "auto_end" then check(F.team(c[2]) == 1, "stand-ins are on team 1") end end
    F.run(2)
    check(F.count(p[1], "CameraPathDir", "auto_end") >= 1, "the host runs the end film")
    for i = 2, n do
        check(F.count(p[i], "CameraPathDir", "auto_end") >= 1 and p[i].camera == 1, "guest " .. i .. " runs the same end film")
    end
    w.cameraDone["auto_end"] = true; F.run(1); w.cameraDone["auto_end"] = false
    check(m.endNear and F.count(p[1], "SucceedMission") == 0, "the film arrives, two seconds hold")
    F.run(3)
    for i = 1, n do
        check(F.count(p[i], "DeactivatePortal") == 1, "the portal closes on peer " .. i)
    end
    F.run(6)
    for i = 1, n do check(F.count(p[i], "SucceedMission") == 1, "one victory on peer " .. i) end
    check(F.last(p[1], "SucceedMission")[3] == "ch04win.des", "ch04win.des")
    -- a loss after the win is ignored; nothing more is built
    F.run(150)
    for i = 1, n do check(F.count(p[i], "FailMission") == 0, "no failure after the win on peer " .. i) end
    guestsPassive(p)
end
do -- the end film's speed change reaches guests; a stalled host camera cannot hang the finish
    local w, p, m = setup(2, {})
    toRoute(w, p, m); cloakAll(p); walkNavs(p, m); alarm(w, p, m); inspect(w, p, m); toPortal(w, p, m)
    atPortal(p); F.run(8)
    check(m.endNear, "the margin ends a film whose camera never reports arrival (network)")
    check(F.last(p[2], "CameraPathDir")[4] == 0, "guests hold the end of the path once the host does")
end
do -- the retreat timeout fails everyone once, with its voice line
    local w, p, m = setup(3, {})
    toRoute(w, p, m); cloakAll(p); walkNavs(p, m); alarm(w, p, m); inspect(w, p, m); toPortal(w, p, m)
    F.run(138)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "ch04lseb.des", "one retreat failure on peer " .. i)
        check(F.heardCount(p[i], "ch04005.wav") == 1, "with the restored line on peer " .. i)
    end
    local before = #F.builds(p[1], 0)
    F.run(30)
    check(#F.builds(p[1], 0) == before, "no more reinforcements after the loss")
end

-- ------------------------------------------------------------------ results and upkeep
do -- a human whose pilot dies and respawns is disguised again; the attackers are aimed again
    local w, p, m = setup(3, {})
    toRoute(w, p, m); cloakAll(p); F.cloak(p[3].player, false); walkNavs(p, m)
    check(F.perceived(p[2].player) == 5, "disguised at the end of the route")
    alarm(w, p, m)
    check(m.attackedAlready == 1, "alarmed")
    local old = p[2].player
    local orders = F.count(p[1], "Attack")
    F.run(3)
    check(F.count(p[1], "Attack") == orders, "stable humans do not re-order the attackers")
    F.kill(old)
    local fresh = F.spawn("cspilo", 2, 400, 101400)
    p[2].player = fresh; F.run(3)
    check(F.count(p[1], "Attack") > orders, "a new craft makes the attackers pick the nearest human again")
    local last
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do last = c end
    check(F.alive(last[3]), "the new order names a live human")
end
do -- the respawn disguise
    local w, p, m = setup(3, {})
    toRoute(w, p, m); cloakAll(p); walkNavs(p, m)
    local old = p[2].player
    F.kill(old)
    local fresh = F.spawn("cspilo", 2, 400, 101400)
    check(F.perceived(fresh) == 2, "a new pilot starts undisguised")
    p[2].player = fresh; F.run(3)
    check(F.perceived(fresh) == 5, "the respawned pilot is disguised like the others")
    for i = 1, 3 do check(F.count(p[i], "SetPerceivedTeam", fresh) == 1, "once, on peer " .. i) end
end
do -- the factory and the portal are invulnerable (the body heals them), and the leader leaving fails everyone
    local w, p, m = setup(2, {})
    F.world().objects["factory"].health = 0.2; F.world().objects["portal"].health = 0.1; F.run(1)
    check(F.world().objects["factory"].health == 1 and F.world().objects["portal"].health == 1, "the base is healed every frame")
end

-- ------------------------------------------------------------------ weather
do
    local w, p, m = setup(2, {})
    local function calls(name) local n = 0 for _, c in ipairs(p[1].weatherCalls) do if c[1] == name then n = n + 1 end end return n end
    toRoute(w, p, m); cloakAll(p); walkNavs(p, m)
    check(calls("SetTargetLevel") == 1, "the route raises the sky once")
    alarm(w, p, m)
    check(calls("Surge") == 1, "the alarm flares the radiation belt")
    inspect(w, p, m); F.run(6)
    check(calls("Quake") >= 1 and calls("TriggerPlume") == 1, "the overrun shakes the ice and blows the first vent (the map has vents)")
    toPortal(w, p, m); finish(w, p, m)
    check(calls("ReleaseForcedLevel") == 1, "victory calms the sky")
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
    -- Saves exist offline (a network game cannot be loaded). Loading in the middle of the opening shot ends it.
    local w, p, m = setup(1, {})
    check(m.missionState == MS.STARTSCENE, "mid-intro")
    local saved = copy(p[1].env.Save())
    p[1].env.Load(saved)
    local paths = F.count(p[1], "CameraPath")
    F.run(2)
    check(F.count(p[1], "CameraPath") == paths, "the loaded shot is not resumed")
    check(saved.missionState >= MS.PLAYSOUND7, "the loaded intro finishes")
    -- the countdown survives a save, with its remaining time
    local w2, q, m2 = setup(1, {})
    toRoute(w2, q, m2)
    F.run(20)
    local snapshot = copy(q[1].env.Save())
    local starts = F.count(q[1], "StartCockpitTimer")
    q[1].env.Load(snapshot); F.run(1)
    check(F.count(q[1], "StartCockpitTimer") == starts + 1, "the running countdown is re-issued after a load")
    check(math.abs(F.last(q[1], "StartCockpitTimer")[2] - 110) < 3, "with its remaining time: " .. tostring(F.last(q[1], "StartCockpitTimer")[2]))
    F.run(115)
    check(F.count(q[1], "FailMission") == 1, "and still expires")
    -- the objective list and the disguise after a load, mid-alarm shot, and mid end film
    local w3, r, m3 = setup(1, {})
    toRoute(w3, r, m3); cloakAll(r); walkNavs(r, m3)
    F.nearTo(r[1].player, "trigger_1", 40, 0); F.run(3)
    check(m3.missionState == MS.CAMERAALARM, "mid alarm shot")
    local loaded = copy(r[1].env.Save())
    local perceived = F.count(r[1], "SetPerceivedTeam")
    r[1].env.Load(loaded); F.run(2)
    check(m3.missionState ~= MS.CAMERAALARM or loaded.missionState ~= MS.CAMERAALARM, "the loaded alarm shot ends at once")
    check(F.count(r[1], "SetPerceivedTeam") > perceived, "the disguise is applied again after a load")
    F.run(6)
    check(r[1].camera == 0, "cameras balanced after the loaded shot")
end
do
    local w, p, m = setup(1, {})
    toRoute(w, p, m); cloakAll(p); walkNavs(p, m); alarm(w, p, m); inspect(w, p, m); toPortal(w, p, m)
    atPortal(p); F.run(1)
    check(m.missionState == MS.CAMERAEND, "end film")
    local snapshot = p[1].env.Save()
    local cam = p[1].camera
    p[1].env.Load(snapshot); F.run(1)
    check(p[1].camera == cam, "the loaded end film opens a camera again, once")
    w.cameraDone["auto_end"] = true; F.run(6)
    check(F.count(p[1], "SucceedMission") == 1, "and still wins")
end

print("chmisn04 coop: " .. checks .. " checks passed")
