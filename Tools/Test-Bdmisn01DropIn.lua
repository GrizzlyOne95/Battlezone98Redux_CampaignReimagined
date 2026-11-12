-- bd01 dropship opening: the real Scripts/bd01cr.lua with the real Scripts/CRDropIn.lua (Black Dog bvdrop) over the
-- multi-peer fixture. Engine physics, floor collision and SDF animation are mocks: this proves script decisions only
-- (the hold gate, nothing before the landing, co-op ownership, fallbacks, save/load). Run from the repository root:
--   lua5.1 Tools/Test-Bdmisn01DropIn.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Bdmisn01Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local RECY, W1, W2, SPOT = "recycler", "wingman1_bobcat", "wingman2_bobcat", "player_grizzly"
local function ships(peer, odf) return F.builds(peer, 0, odf) end
local function aliveOdf(w, pattern)
    local n = 0
    for _, o in pairs(w.objects) do if o.alive and o.odf:find(pattern) then n = n + 1 end end
    return n
end
-- the body's first calls: orders, briefing, objectives, scrap, enemy
local BODY = { Goto = true, AudioMessage = true, Play = true, Queue = true, SetScrap = true, ClearObjectives = true,
    AddObjective = true, Attack = true, CameraPath = true }
local function firstBody(peer)
    for i, c in ipairs(peer.calls) do if BODY[c[1]] then return i end end
end
local function landedAt(peer, odf)
    for i, c in ipairs(peer.calls) do if c[1] == "BuildObject" and c[3] == odf then return i end end
end
local function driveOff(peers)
    for _, h in ipairs({ RECY, W1, W2, SPOT }) do F.place(h, 3000, 99000) end
    for _, q in ipairs(peers) do F.place(q.player, 3100 + 40 * q.id, 99100) end
end

-- ---------------------------------------------------------------- offline
do
    local w = F.reset()
    local p = F.makePeer(1, 1, false, { dropIn = true })
    local m = p.env.Save()
    F.run(1)
    check(not m.startDone and m.dropHold == true, "the stock opening waits for the landing")
    check(#ships(p, "bvdropc") == 2 and #ships(p, "apcamr") == 1 and #ships(p, "avdropc") == 0, "two flying bvdrop and the camera pod")
    F.run(14)
    check(not m.startDone and F.heardCount(p, "bd01001.wav") == 0, "no briefing while the ships descend")
    for _, c in ipairs(p.calls) do check(not BODY[c[1]], "nothing of the stock body ran before the landing: " .. c[1]) end
    for _, b in ipairs(F.builds(p)) do
        check(b.team ~= 2 and b.team ~= 5 and (b.odf == "bvdropc" or b.odf == "apcamr"), "only ships and the pod exist: " .. b.odf)
    end
    check(w.objects[RECY].pos.y > 5 and w.objects[p.player].pos.y > 5, "the Recycler and the player ride the ships")
    F.runUntil(function() return m.startDone end, 60)
    local flown = w.now - m.dropin.t0
    check(flown >= 2.5 + 16 + 2.6 - 0.3 and flown <= 2.5 + 16 + 2.6 + 0.6, "the stock opening follows the second ship's ramps (" .. flown .. " s)")
    check(#ships(p, "bvdropo") == 2, "both ships landed as new landed-model objects")
    check(firstBody(p) > landedAt(p, "bvdropo"), "the stock body starts only after the landing")
    check(F.heardCount(p, "bd01001.wav") == 1, "the briefing plays once, at the landing")
    check(F.count(p, "Goto", RECY) == 1 and F.count(p, "Goto", W1) == 1 and F.count(p, "Goto", W2) == 1,
        "the start paths are issued at the landing")
    local c = m.dropin.lead.cargo
    check(#c == 4 and c[1].along == 0 and c[1].lat == -8 and c[2].along == 2 and c[2].lat == 10 and c[3].along == -9,
        "ship 1 carries the Recycler and the Bobcats; the stock tank rides ship 2")
    check(m.dropin.crew[1].ship == 2, "the player rides ship 2")
    F.run(8)
    check(aliveOdf(w, "^bvdrop") == 2, "the ships wait while the craft are beside them")
    driveOff({ p })
    F.runUntil(function() return F.state(p).dropin.phase == "done" end, 120)
    check(#ships(p, "bvdropx") == 2 and aliveOdf(w, "^bvdrop") == 0, "ramps fold and both ships leave")
end

-- ---------------------------------------------------------------- the stock start without the module
do
    local w = F.reset()
    local p = F.makePeer(1, 1, false, {})
    local m = p.env.Save()
    F.run(1)
    check(m.startDone and not m.dropHold and #ships(p, "bvdropc") == 0 and F.heardCount(p, "bd01001.wav") == 1,
        "no CRDropIn: the stock opening runs at once")
end

-- ---------------------------------------------------------------- co-op: host + two guests
do
    local w = F.reset()
    local peers = {}
    for i = 1, 3 do
        peers[i] = F.makePeer(i, i, true, { dropIn = true })
        F.place(peers[i].player, 1045 + 24 * (i - 1), 101448 + 5 * (i - 1))
    end
    F.connect()
    local host = peers[1]
    local m = host.env.Save()
    F.run(2)
    check(not m.startDone and m.dropHold == true and #ships(host, "bvdropc") == 2, "the leader holds the opening and builds both ships")
    for i = 2, 3 do
        local g = peers[i]
        check(F.count(g, "BuildObject") == 0, "guest " .. i .. " builds nothing")
        local s = F.state(g).dropin
        check(s and s.go and s.n == 2 and s.ships[2].prof == "bvdrop" and s.crew[1] and s.crew[2] and s.crew[3], "guest " .. i .. " has the plan")
    end
    F.run(5)
    for i = 1, 3 do
        check(w.objects[peers[i].player].pos.y > 5, "peer " .. i .. " rides a descending ship")
        for _, c in ipairs(peers[i].calls) do check(not BODY[c[1]], "no stock body call before the landing on peer " .. i .. ": " .. c[1]) end
    end
    for i = 2, 3 do
        for _, c in ipairs(F.callsOf(peers[i], "SetTransform")) do check(c[2] == peers[i].player, "guest " .. i .. " moves only its own craft") end
        for _, name in ipairs({ "BuildObject", "SetScrap", "RemoveObject", "Goto", "Stop" }) do
            check(F.count(peers[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
    F.runUntil(function() return m.startDone end, 60)
    local flown = w.now - m.dropin.t0
    check(flown >= 2.5 + 16 + 2.6 - 0.3 and flown <= 2.5 + 16 + 2.6 + 0.6, "co-op: the stock opening follows the ramps")
    F.run(2)
    for i = 1, 3 do
        check(F.state(peers[i]).dropin.released, "peer " .. i .. " released")
        check(F.heardCount(peers[i], "bd01001.wav") == 1, "peer " .. i .. " hears the briefing once, after the landing")
    end
    local after = F.count(peers[2], "SetTransform")
    F.run(2)
    check(F.count(peers[2], "SetTransform") == after, "a released guest no longer pins")
    driveOff(peers)
    F.runUntil(function() return F.state(host).dropin.phase == "done" end, 120)
    check(aliveOdf(w, "^bvdrop") == 0, "the ships leave in co-op")
end

-- ---------------------------------------------------------------- co-op: the host leaves mid-drop
do
    local w = F.reset()
    local peers = {}
    for i = 1, 2 do peers[i] = F.makePeer(i, i, true, { dropIn = true }) end
    F.connect()
    F.run(3)
    local g = peers[2]
    check(F.state(g).dropin and F.state(g).dropin.go and not F.state(g).dropin.released, "the guest is held")
    g.env.DeletePlayer(1)
    F.run(1)
    check(F.state(g).dropin.phase == "done", "a departed host takes the drop down: no guest stays held")
end

-- ---------------------------------------------------------------- save and load
do
    local w = F.reset()
    local p = F.makePeer(1, 1, false, { dropIn = true })
    local m = p.env.Save()
    F.run(8)
    check(not m.startDone and aliveOdf(w, "^bvdrop") == 2, "mid-drop save point")
    p.env.Load(m)
    F.run(1)
    check(m.dropin.phase == "done" and m.startDone and aliveOdf(w, "^bvdrop") == 0, "a load mid-drop ends the drop and starts the mission")
    check(near(w.objects[RECY].pos.x, 905.8, 5) and w.objects[RECY].pos.y < 10, "the Recycler is set down on its stock spot")
    local w2 = F.reset()
    local q = F.makePeer(1, 1, false, { dropIn = true })
    F.run(30)
    local old = q.env.Save()
    old.dropin = nil
    local before = #ships(q, "bvdropc")
    q.env.Load(old)
    F.run(2)
    check(#ships(q, "bvdropc") == before, "an old save of a started mission never starts a drop")
end

print(string.format("bdmisn01 dropship opening: %d checks passed", checks))
