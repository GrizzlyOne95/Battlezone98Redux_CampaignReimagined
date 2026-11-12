-- misns1 dropship opening: the real Scripts/misns1cr.lua with the real Scripts/CRDropIn.lua (CCA svdrop) over the
-- multi-peer fixture. Engine physics, floor collision and SDF animation are mocks: this proves script decisions only
-- (the hold gate, what may not happen during the drop, the clocks counting from the landing, co-op ownership, fallbacks,
-- save/load). Pure choreography has its own test: Tools/Test-CRDropIn.lua. Run from the repository root:
--   lua5.1 Tools/Test-Misns1DropIn.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Misns1Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

local RECY, RECY_AT = "svrecy2_recycler", { x = 1887.73, z = 98605.6 }
local SPOT = { x = 1929.36, z = 98586.8 }
local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) end
local function stock(w)   -- the stock start (Missions/misns1cr.bzn): the recycler beside the player spot
    F.place(RECY, RECY_AT.x, RECY_AT.z)
end
local function ships(peer, odf)
    return F.builds(peer, 0, odf)
end
local function aliveOdf(w, pattern)
    local n = 0
    for _, o in pairs(w.objects) do if o.alive and o.odf:find(pattern) then n = n + 1 end end
    return n
end
local function firstIndex(peer, names)
    local best
    for i, c in ipairs(peer.calls) do
        if names[c[1]] and (not best or i < best) then best = i; break end
    end
    return best
end
local BODY = { SetAIP = true, SetScrap = true, AudioMessage = true, Goto = true, Attack = true, Follow = true,
    SetIndependence = true, ClearObjectives = true, AddObjective = true, SetObjectiveName = true }
-- Send the carried craft out of the hold: the mock has no physics, so the test drives them away.
local function driveOff(w, peers)
    F.place(RECY, 1700, 99100)
    for _, q in ipairs(peers) do F.place(q.player, 2300 + 40 * q.id, 99100) end
end

-- ---------------------------------------------------------------- offline
do
    local w = F.reset(); stock(w)
    local p = F.makePeer(1, 1, false, { dropIn = true })
    F.place(p.player, SPOT.x, SPOT.z)
    local m = p.env.Save()
    F.run(1)
    -- The hold gate: the stock body has not run.
    check(not m.missionstart and m.dropHold == true, "the stock opening waits for the landing")
    check(#ships(p, "svdropc") == 1 and #ships(p, "apcamr") == 1, "one flying svdrop and the camera pod")
    check(#ships(p, "avdropc") == 0, "no NSDF ship in the CCA mission")
    check(p.camera == 1, "the drop camera is up")
    -- Nothing of the mission happens while the ship is in the air: no briefing, AIP, scrap, orders, objectives, enemy.
    F.run(4)
    -- the player rides the ship in the hold, the recycler with it
    check(w.objects[p.player].pos.y > 30 and w.objects[RECY].pos.y > 30, "the player and the recycler are carried aloft")
    F.run(10)
    check(not m.missionstart and F.heardCount(p, "misns101.wav") == 0, "no briefing while the ship descends")
    for _, c in ipairs(p.calls) do
        check(not BODY[c[1]], "nothing of the stock body ran before the landing: " .. c[1])
    end
    for _, b in ipairs(F.builds(p)) do
        check(b.team ~= 2 and b.team ~= 5 and (b.odf == "svdropc" or b.odf == "apcamr"), "only the ship and its pod exist: " .. b.odf)
    end
    check(F.state(p).startconvoy == 9999999999.0 and m.cintime == 9999999999.0 and m.wave1 == 999999999.0, "no timer is armed")
    -- Landing, release, then the stock body.
    F.runUntil(function() return m.missionstart end, 60)
    local t = w.now
    check(t >= 16 + 2.6 - 0.3 and t <= 16 + 2.6 + 0.6, "the stock opening follows the ramps (" .. t .. " s)")
    check(#ships(p, "svdropo") == 1, "the ship landed as a new landed-model object")
    check(F.count(p, "CameraReady") == 2 and F.count(p, "CameraFinish") == 1 and p.camera == 1,
        "the drop camera is finished at the release; the opening film's shot is the only one left up")
    local finished
    for i, c in ipairs(p.calls) do if c[1] == "CameraFinish" then finished = finished or i end end
    local filmed
    for i, c in ipairs(p.calls) do if c[1] == "CameraReady" and i > 1 then filmed = i end end
    check(finished < filmed, "the film starts after the drop camera is down")
    local firstBody = firstIndex(p, BODY)
    local ofLanded
    for i, c in ipairs(p.calls) do if c[1] == "BuildObject" and c[3] == "svdropo" then ofLanded = i end end
    check(firstBody and ofLanded and firstBody > ofLanded, "the stock body starts only after the landing")
    check(F.heardCount(p, "misns101.wav") == 1, "the briefing plays once, at the landing")
    -- The clocks count from the landing, not from mission load.
    check(near(m.startconvoy, t + 180) and near(m.cintime, t + 11) and near(m.cintime2, t + 20) and near(m.cintime11, t + 66),
        "the convoy and the opening-film clocks count from the landing")
    check(F.count(p, "SetAIP") == 0, "the enemy AIP is not armed at the landing frame")
    F.run(1)
    check(F.count(p, "SetScrap", 1) >= 1 and F.count(p, "SetScrap", 5) >= 1, "scrap is set once the body runs (team 1, enemy team 5)")
    -- The ship stays until the hold is clear, then closes and leaves.
    F.run(8)
    check(aliveOdf(w, "^svdrop") == 1, "the landed ship waits while the craft are still beside it")
    driveOff(w, { p })
    F.runUntil(function() return F.state(p).dropin.phase == "done" end, 120)
    check(#ships(p, "svdropx") == 1 and aliveOdf(w, "^svdrop") == 0, "ramps fold and the ship leaves")
    check(F.count(p, "RemoveObject") >= 2, "the pod and the ship are removed")
    check(w.objects[p.player].alive and w.objects[RECY].alive, "nobody was lost")
    check(m.dropin.released and m.dropin.phase == "done", "the drop is over")
end

-- ---------------------------------------------------------------- the stock start without the module
do
    local w = F.reset(); stock(w)
    local p = F.makePeer(1, 1, false, {})
    local m = p.env.Save()
    F.run(1)
    check(m.missionstart and not m.dropHold and #ships(p, "svdropc") == 0, "no CRDropIn: the stock opening runs at once")
    check(F.heardCount(p, "misns101.wav") == 1 and near(m.startconvoy, w.now + 180 - 1 + 0.25, 1.01), "stock clocks from load")
    local said = false
    for _, c in ipairs(p.calls) do if c[1] == "print" and tostring(c[2]):find("CRDropIn unavailable", 1, true) then said = true end end
    check(said, "the fallback is logged")
end

-- ---------------------------------------------------------------- co-op: host + two guests, an orphan stock tank rides too
do
    F.LABELS["svtank0_wingman"] = { odf = "svtank", team = 1, pos = { SPOT.x, 66.8, SPOT.z }, craft = true }
    local w = F.reset(); stock(w)
    local peers = {}
    for i = 1, 3 do
        peers[i] = F.makePeer(i, i, true, { dropIn = true })
        F.place(peers[i].player, SPOT.x - 22 * (i - 1), SPOT.z - 11 * (i - 1))
    end
    F.connect()
    local host, g2, g3 = peers[1], peers[2], peers[3]
    local m = host.env.Save()
    F.run(2)
    check(not m.missionstart and m.dropHold == true and #ships(host, "svdropc") == 1, "the leader started the drop and holds the opening")
    for i = 2, 3 do
        local g = peers[i]
        check(#ships(g, "svdropc") == 0 and F.count(g, "BuildObject") == 0, "guest " .. i .. " builds nothing")
        local s = F.state(g).dropin
        check(s and s.go and s.n == 1 and s.ships[1].prof == "svdrop", "guest " .. i .. " has the svdrop plan")
        check(s.crew[1] and s.crew[2] and s.crew[3], "guest " .. i .. " knows every human's slot")
    end
    local lead = m.dropin.lead
    check(#lead.cargo == 2 and lead.cargo[1].along == 10.6 and lead.cargo[1].lat == 0, "the recycler takes the svdrop recycler slot")
    check(lead.cargo[2].h == "svtank0_wingman" and lead.cargo[2].along == -31.7 and lead.cargo[2].lat == 5.5,
        "the orphan stock tank takes the next hold slot after the three humans")
    F.run(3)
    for i = 1, 3 do check(w.objects[peers[i].player].pos.y > 30, "peer " .. i .. " rides the descending ship") end
    -- nothing of the body anywhere, on any peer
    for i = 1, 3 do
        for _, c in ipairs(peers[i].calls) do check(not BODY[c[1]], "no stock body call before the landing on peer " .. i .. ": " .. c[1]) end
        check(F.heardCount(peers[i], "misns101.wav") == 0, "no briefing yet on peer " .. i)
    end
    -- ownership: a guest moves only its own craft
    for i = 2, 3 do
        for _, c in ipairs(F.callsOf(peers[i], "SetTransform")) do
            check(c[2] == peers[i].player, "guest " .. i .. " moves only its own craft")
        end
        for _, c in ipairs(F.callsOf(peers[i], "SetVelocity")) do
            check(c[2] == peers[i].player, "guest " .. i .. " zeroes only its own craft's velocity")
        end
        for _, name in ipairs({ "BuildObject", "SetScrap", "SetAIP", "RemoveObject", "Goto", "Stop" }) do
            check(F.count(peers[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
    F.runUntil(function() return m.missionstart end, 60)
    local t = w.now
    local flown = t - m.dropin.t0
    check(flown >= 16 + 2.6 - 0.3 and flown <= 16 + 2.6 + 0.6, "the leader's stock opening follows the ramps (" .. flown .. " s)")
    check(near(m.startconvoy, t + 180) and near(m.cintime, t + 11), "co-op clocks count from the landing")
    F.run(2)
    for i = 1, 3 do
        local d = F.state(peers[i]).dropin
        check(d.released, "peer " .. i .. " released")
        check(F.heardCount(peers[i], "misns101.wav") == 1, "peer " .. i .. " hears the briefing once, after the landing")
    end
    for i = 1, 3 do
        check(F.count(peers[i], "CameraReady") - F.count(peers[i], "CameraFinish") <= 1, "the drop camera is down on peer " .. i)
    end
    local after = {}
    for i = 2, 3 do after[i] = F.count(peers[i], "SetTransform") end
    F.run(2)
    for i = 2, 3 do check(F.count(peers[i], "SetTransform") == after[i], "a released guest no longer pins") end
    driveOff(w, peers)
    F.place("svtank0_wingman", 2500, 99200)
    F.runUntil(function() return F.state(host).dropin.phase == "done" end, 120)
    check(aliveOdf(w, "^svdrop") == 0 and #ships(host, "svdropx") == 1, "the ship folds its ramps and leaves in co-op")
    for i = 2, 3 do check(F.state(peers[i]).dropin.phase == "done", "guest " .. i .. " is not left in the drop") end
    F.LABELS["svtank0_wingman"] = nil
end

-- ---------------------------------------------------------------- co-op: the host leaves mid-drop, the guest is released
do
    local w = F.reset(); stock(w)
    local peers = {}
    for i = 1, 2 do
        peers[i] = F.makePeer(i, i, true, { dropIn = true })
        F.place(peers[i].player, SPOT.x - 22 * (i - 1), SPOT.z - 11 * (i - 1))
    end
    F.connect()
    F.run(3)
    local g = peers[2]
    check(F.state(g).dropin and F.state(g).dropin.go and not F.state(g).dropin.released, "the guest is held in the hold")
    g.env.DeletePlayer(1)
    F.run(1)
    check(F.state(g).dropin.phase == "done", "a departed host takes the drop down: no guest stays held")
end

-- ---------------------------------------------------------------- save and load mid-drop
do
    local w = F.reset(); stock(w)
    local p = F.makePeer(1, 1, false, { dropIn = true })
    F.place(p.player, SPOT.x, SPOT.z)
    local m = p.env.Save()
    F.run(8)
    check(not m.missionstart and aliveOdf(w, "^svdrop") == 1, "mid-drop save point")
    p.env.Load(m)
    F.run(1)
    check(m.dropin.phase == "done" and m.missionstart and aliveOdf(w, "^svdrop") == 0, "a load mid-drop ends the drop and starts the mission")
    check(dist(w.objects[RECY].pos, RECY_AT) < 5 and w.objects[RECY].pos.y < 30, "the recycler is set down on its stock spot")
    check(F.heardCount(p, "misns101.wav") == 1, "the briefing plays after the load")
    -- a save from before the opening (no drop state, mission already started) never begins one
    local w2 = F.reset(); stock(w2)
    local q = F.makePeer(1, 1, false, { dropIn = true })
    F.run(30)
    local old = q.env.Save()
    old.dropin = nil
    check(old.missionstart, "the mission is under way")
    local before = #ships(q, "svdropc")
    q.env.Load(old)
    F.run(2)
    check(#ships(q, "svdropc") == before and old.dropin == nil, "an old save of a started mission never starts a drop")
end

print(string.format("misns1 dropship opening: %d checks passed", checks))
