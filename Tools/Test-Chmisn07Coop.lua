-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/chmisn07cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/Test-Chmisn07Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Chmisn07Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local function extrasFor(n) return math.min(math.floor(n / 2), 2) end
local function setup(n, options)
    options = options or {}
    local w = F.reset()
    w.audioBusy = options.busy == true
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    local m = p[1].env.Save()
    m.direction, m.relic = options.direction or 0, options.relic or 0
    return w, p, m
end
local function heardAll(p, file, count)
    for i, q in ipairs(p) do check(F.heardCount(q, file) == (count or 1), "peer " .. i .. " hears " .. file .. " x" .. (count or 1)) end
end
local function guestsPassive(p)
    for i = 2, #p do
        for _, name in ipairs({"BuildObject", "SetScrap", "SetAIP", "Goto", "Follow", "Attack", "SetIndependence",
            "Retreat", "Defend2", "SetPilotClass", "MakeExplosion"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
-- The humans stay at the landing point until a test moves them.
local function start(p) for _, q in ipairs(p) do F.place(q.player, F.START[1] - 3.8 * (q.id - 1), F.START[3] - 25 * (q.id - 1)) end end
local function far(h) F.place(h, 2400, 100900) end -- more than 900 m from every trigger and 460 m from every entry used
local function openingDone(w)
    w.cameraDone["cin_start"] = true; F.run(1); w.cameraDone["cin_start"] = false
end
-- Walk human q to the comm tower, run the burglary to its end and the bridge film out.
local function burglary(w, q, m)
    F.nearTo(q.player, "commtower", 5, 0)
    F.run(1)
    check(m.doBurglarSequence and m.cameraReady[1], "a human at the comm tower starts the burglary")
    local fake = m.fakePlayer
    check(fake ~= nil and F.team(fake) == 0, "the stand-in is a neutral pilot")
    F.nearTo(fake, "fake_vanish", 0, 0)
    F.run(1)
    F.run(5)
    check(not m.doBurglarSequence and m.objective1Complete, "the burglary ends")
    local seq = m.direction == 0 and "cin_north" or "cin_east"
    w.cameraDone[seq] = true; F.run(3); w.cameraDone[seq] = false
    check(not m.doNorthSequence and not m.doEastSequence, "the bridge film ends")
end
local function enemies(peer, mark)
    local out = {}
    for _, b in ipairs(F.builds(peer, mark or 0)) do if b.odf:sub(1, 2) == "ss" or b.odf:sub(1, 2) == "sv" then out[#out + 1] = b end end
    return out
end
local function count(list, odf)
    local n = 0
    for _, b in ipairs(list) do if odf == nil or b.odf == odf then n = n + 1 end end
    return n
end

-- ------------------------------------------------------------------ offline == faithful
local function winScenario(options)
    local w, p, m = setup(1, options)
    openingDone(w)
    burglary(w, p[1], m)
    F.run(11)
    F.run(870, 2)
    check(m.convoySpawned and m.relicApc ~= nil, "the convoy rolls out")
    F.kill(m.relicApc)
    F.run(2)
    check(m.objective3Complete, "the relic carrier is down")
    F.nearTo(p[1].player, "nav_end", 60, 0)
    F.run(4)
    for i = 0, 5 do
        local g = m.endGuy[i]
        if g ~= nil and F.alive(g) then F.kill(g) end
    end
    F.nearTo(p[1].player, "nav_end", 20, 0)
    F.run(12)
    local lines = {}
    for _, c in ipairs(p[1].calls) do
        if c[1] == "AudioMessage" or c[1] == "Play" or c[1] == "Queue" then lines[#lines + 1] = c[2] end
    end
    local results = {}
    for _, name in ipairs({"SucceedMission", "FailMission"}) do
        for _, c in ipairs(F.callsOf(p[1], name)) do results[#results + 1] = name .. ":" .. tostring(c[3]) end
    end
    return table.concat(lines, ","), table.concat(results, ","), m
end
do
    local faithfulLines, faithfulResults = winScenario({faithful = true})
    local coopLines, coopResults, m = winScenario({})
    check(faithfulResults == "SucceedMission:ch07win.des", "the faithful port wins: " .. faithfulResults)
    check(coopResults == faithfulResults, "offline CR == faithful result: " .. coopResults)
    check(coopLines == faithfulLines, "offline CR plays the faithful lines: " .. coopLines .. " vs " .. faithfulLines)
    check(coopLines:find("ch07001.wav", 1, true) and coopLines:find("ch07009.wav", 1, true), "opening and win lines")
    check(m.won, "won")
end

-- ------------------------------------------------------------------ teams: nothing is built on the authored enemy team 2
do
    local w, p, m = setup(2, {})
    openingDone(w)
    F.nearTo(p[1].player, "zn_1_trig", -450, 0)
    F.nearTo(p[2].player, "zn_1_trig", -550, 0)
    F.run(8)
    check(m.znAttacked[0] and not m.znAttacked[4], "a zone ambush springs")
    for _, b in ipairs(F.builds(p[1])) do check(b.team ~= 2, "no unit is built on the authored enemy team 2: " .. b.odf) end
    local list = enemies(p[1])
    check(count(list, "svturr") == 3, "the three turrets are built directly")
    for _, b in ipairs(list) do check(b.team == 5, "the Soviets are team 5") end
    guestsPassive(p)
end

-- ------------------------------------------------------------------ nearest human triggers, scaling and the 460 m rule
for n = 2, 4 do
    local w, p, m = setup(n, {})
    openingDone(w)
    start(p)
    -- the last human walks to zone 1 (5 snipers, 2 soldiers, 3 pilots, 3 turrets); some entries are within 460 m
    -- of him, so those come from the hidden approaches
    F.nearTo(p[n].player, "zn_1_trig", -450, 0)
    F.run(10)
    check(m.znAttacked[0] and not m.znAttacked[1], "only the zone near the human springs: " .. n)
    local list = enemies(p[1])
    check(count(list, "ssusera") == 5 + extrasFor(n), "zone 1 snipers x" .. 5 + extrasFor(n) .. " with " .. n .. " humans (got " .. count(list, "ssusera") .. ")")
    check(count(list, "svturr") == 3, "its three turrets are not scaled")
    for _, b in ipairs(list) do
        if b.odf == "ssusera" then
            for _, q in ipairs(p) do
                check(q.env.GetDistance(q.player, b.h) >= 460, "no concealed unit is built within 460 m of any human")
            end
        end
    end
    guestsPassive(p)
end

-- ------------------------------------------------------------------ the burglary is shared; every human is disguised as team 5
for n = 1, 4 do
    local w, p, m = setup(n, {})
    openingDone(w)
    start(p)
    -- the first-frame disguise 1 is each human's own team
    for _, q in ipairs(p) do check(F.perceived(q.player) == q.team, "perceived team starts as the human's own team") end
    local mark = {}
    for i, q in ipairs(p) do mark[i] = #q.calls end
    -- the LAST human reaches the tower: any human starts it
    F.nearTo(p[n].player, "commtower", 5, 0)
    F.run(1)
    check(m.doBurglarSequence, "the nearest human starts the burglary")
    for i, q in ipairs(p) do
        check(F.perceived(q.player) == 5, "human " .. i .. " is perceived as the Soviet side (team 5)")
        check(F.hidden(q.player), "human " .. i .. " is hidden")
        local sent2 = false
        for k = mark[i] + 1, #q.calls do
            local c = q.calls[k]
            if c[1] == "SetPerceivedTeam" and c[3] == 2 then sent2 = true end
        end
        check(not sent2, "peer " .. i .. " never perceives anyone as team 2 during the burglary (the co-op Soviets are 5)")
        check(F.count(q, "SetPerceivedTeam") >= n, "peer " .. i .. " disguises every human on its own copy")
    end
    F.nearTo(m.fakePlayer, "fake_vanish", 0, 0)
    F.run(6)
    check(not m.doBurglarSequence, "the burglary ends")
    for i, q in ipairs(p) do
        check(F.perceived(q.player) == q.team, "human " .. i .. " gets its own team back")
        check(not F.hidden(q.player), "human " .. i .. " is visible again")
        local pos = F.posOf(q.player)
        check(math.abs(pos.x - 1000 - (q.team > 1 and 4 * (q.team - 1) or 0)) < 1.5 and math.abs(pos.z - 99638) < 1.5,
            "human " .. i .. " leaves the tower at its own spot beside burglar_exit")
    end
    heardAll(p, "ch07002.wav", m.direction == 0 and 1 or 0)
    for _, q in ipairs(p) do check(q.camera >= 0, "balanced cameras") end
end

-- ------------------------------------------------------------------ cinematics are shared and unskippable (offline skippable)
do
    local w, p, m = setup(2, {})
    w.cancel = true
    F.run(20)
    check(not m.cameraComplete[0], "a skip key does not end the shared opening")
    check(F.count(p[2], "CameraPath", "cin_start") > 0, "the guest sees the opening")
    F.run(20)
    check(m.cameraComplete[0], "the opening still ends at its flight time (the host's skip cannot hang it)")
    w.cancel = false
    local w1, q, m1 = setup(1, {})
    w1.cancel = true
    F.run(1)
    check(m1.cameraComplete[0], "offline the opening is skippable")
end
-- a stand-in that never reaches the vanish point cannot hold the humans for ever
do
    local w, p, m = setup(2, {})
    openingDone(w)
    F.nearTo(p[1].player, "commtower", 5, 0)
    F.run(1)
    check(m.doBurglarSequence, "burglary starts")
    F.run(20)
    check(m.doBurglarSequence, "still within the limit")
    F.run(10)
    check(not m.doBurglarSequence and m.objective1Complete, "the never-hang guard ends it")
end

-- ------------------------------------------------------------------ fighters and the foot patrol go for the nearest human
do
    local w, p, m = setup(3, {})
    openingDone(w)
    F.nearTo(p[3].player, "figh_1_1", 100, 0)
    F.run(1)
    local fighter = m.fighters[0]
    local ordered
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do if c[2] == fighter then ordered = c end end
    check(ordered and ordered[3] == p[3].player and ordered[4] == 1, "the fighter attacks the human who came near")
    guestsPassive({p[1], p[2], p[3]}) -- peer 1 is the host: it may order; guests 2 and 3 may not
end

-- ------------------------------------------------------------------ pickups refill the human who stands at them
do
    local w, p, m = setup(2, {})
    openingDone(w)
    w.objects[p[2].player].maxHealth = 2
    w.objects[p[2].player].health = 1
    F.nearTo(p[2].player, "repair_1", 1, 0)
    F.run(2)
    check(w.objects[p[2].player].health == 2, "the guest's ship is repaired, not the host's")
    check(m.repair1 == nil and not F.alive("repair_1"), "the pickup is used up")
    check(F.count(p[2], "ColorFade") == 1 and F.count(p[2], "StartSound", "repair.wav") == 1, "only the guest sees the flash")
    check(F.count(p[1], "ColorFade") == 0, "the host does not")
    local hostSet = 0
    for _, c in ipairs(F.callsOf(p[1], "SetCurHealth")) do if c[2] == p[1].player then hostSet = hostSet + 1 end end
    check(hostSet == 0, "the host is untouched")
    -- a full ship leaves the pickup in place
    F.nearTo(p[2].player, "ammo_1", 1, 0)
    F.run(2)
    check(m.ammo1 ~= nil and F.alive("ammo_1"), "a full ship does not use the pickup up")
end

-- ------------------------------------------------------------------ the convoy and the bridge
do
    local w, p, m = setup(2, {direction = 1, relic = 2})
    openingDone(w)
    burglary(w, p[1], m)
    check(m.objective1Complete and F.heard(p[2], "ch07003.wav") and not F.heard(p[2], "ch07002.wav"), "the east sequence plays on both peers")
    check(F.count(p[2], "AddObjective", "ch07002e.otf") == 1, "the guest gets the east objective")
    F.run(870, 2)
    local convoy = enemies(p[1])
    check(m.convoyCount == 3 and m.convoySpawned, "three convoy APCs")
    check(m.relicApc ~= nil, "the relic is the third APC (relic = 2)")
    local apcs, escorts = 0, 0
    for _, b in ipairs(convoy) do
        if b.odf:sub(1, 5) == "svapc" then apcs = apcs + 1; check(b.team == 5, "convoy on team 5") end
        if b.odf == "svfigh" then escorts = escorts + 1 end
    end
    check(apcs == 3 and escorts == 3, "three APCs with three escorts")
    check(F.count(p[1], "SetPilotClass") == 6, "the convoy keeps escort AI (pilot class cleared)")
    guestsPassive(p)
end
-- the bomb
do
    local w, p, m = setup(2, {})
    openingDone(w)
    burglary(w, p[1], m)
    F.kill("bomb_north")
    F.run(2)
    check(m.bombDestroyed, "the crate goes")
    check(F.count(p[1], "MakeExplosion") == 1 and F.count(p[2], "MakeExplosion") == 1, "the blast shows on every peer")
    local list = enemies(p[1])
    check(count(list, "sssold") >= 3, "the troops come out of the bridge")
    local levels = 0
    for _, c in ipairs(p[1].weatherCalls) do if c[1] == "Quake" then levels = levels + 1 end end
    check(levels == 1, "the crates shake the ice")
end

-- ------------------------------------------------------------------ the loss
do
    local w, p, m = setup(3, {relic = 0})
    openingDone(w)
    burglary(w, p[1], m)
    F.run(870, 2)
    check(m.relicApc ~= nil, "the relic APC is on the road")
    F.nearTo(m.relicApc, "north_wav", 0, 0)
    F.run(2)
    heardAll(p, "ch07006.wav")
    F.nearTo(m.relicApc, "north_fail", 0, 0)
    F.run(8)
    check(m.lost, "the relic APC passes the failure point")
    heardAll(p, "ch07007.wav")
    for i, q in ipairs(p) do
        check(F.count(q, "FailMission") == 1 and F.last(q, "FailMission")[3] == "ch07lose.des", "one shared defeat on peer " .. i)
    end
    check(F.count(p[1], "SucceedMission") == 0, "no victory after a defeat")
end

-- ------------------------------------------------------------------ the win needs every human at the drop zone and every guard dead
for n = 2, 4 do
    local w, p, m = setup(n, {relic = 0})
    openingDone(w)
    burglary(w, p[1], m)
    F.run(870, 2)
    F.kill(m.relicApc)
    F.run(2)
    check(m.objective3Complete, "the carrier is down")
    heardAll(p, "ch07008.wav")
    -- the first approach (900 m) springs the pilot ambush in its own frame; then the guards' frame is its own event
    for i = 1, n do F.nearTo(p[i].player, "nav_end", 500 + 3 * i, 0) end
    F.run(6)
    for i = 1, n do F.nearTo(p[i].player, "nav_end", 100 + 3 * i, 0) end
    F.run(8)
    check(m.snipersSpawned and m.rescue, "the end guards and the rescue pilots appear")
    for i = 0, 5 do
        local g = m.endGuy[i]
        check(g ~= nil, "end guard " .. i .. " exists")
    end
    F.run(4)
    local guards = 0
    for i = 0, 5 do
        local g = m.endGuy[i]
        if type(g) == "string" and F.alive(g) then guards = guards + 1; F.kill(g) end
    end
    check(guards == 6, "the six end guards are real units after their entries clear: " .. guards)
    -- co-op extras of the first sniper keep the extraction closed
    local extras = m.crcca.r and m.crcca.r.endExtras or {}
    check(#extras == extrasFor(n), "the first end guard is mirrored by " .. extrasFor(n) .. " extras (got " .. #extras .. ")")
    for _, h in ipairs(extras) do check(F.alive(h), "the extras are alive") end
    for i = 1, n do F.nearTo(p[i].player, "nav_end", 20 + i, 0) end
    F.run(4)
    if extrasFor(n) > 0 then check(not m.won, "with " .. n .. " humans the extras keep the extraction closed") end
    for _, h in ipairs(extras) do if F.alive(h) then F.kill(h) end end
    for _, c in ipairs(F.callsOf(p[1], "BuildObject")) do if F.alive(c[2]) and (c[3] == "ssusera" or c[3] == "sssold") then F.kill(c[2]) end end
    -- one human lags behind: no victory
    for i = 1, n do F.nearTo(p[i].player, "nav_end", 20 + i, 0) end
    F.place(p[n].player, 1480 + 300, 99997)
    F.run(4)
    check(not m.won, "a human still on the way keeps the extraction open")
    F.nearTo(p[n].player, "nav_end", 30, 0)
    F.run(10)
    check(m.won, "everyone at the drop zone wins")
    heardAll(p, "ch07009.wav")
    for i, q in ipairs(p) do check(F.count(q, "SucceedMission") == 1 and F.last(q, "SucceedMission")[3] == "ch07win.des", "one shared victory on peer " .. i) end
    check(F.count(p[1], "FailMission") == 0, "no defeat after the victory")
end

-- ------------------------------------------------------------------ weather beats
do
    local w, p, m = setup(1, {})
    openingDone(w)
    burglary(w, p[1], m)
    F.run(1)
    local raised = {}
    for _, c in ipairs(p[1].weatherCalls) do if c[1] == "SetTargetLevel" then raised[#raised + 1] = c[2] end end
    check(raised[1] == 2, "the burglary stirs the ice (level 2)")
    local vents = p[1].modules.CREuropaSitesCH07.vents
    check(#vents == 0, "this Europa map has no vents, so the bomb beat never forces a plume")
end

-- ------------------------------------------------------------------ saves: a load rebuilds the objective list and never replays a film
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
    local w, p, m = setup(1, {})
    local saved = copy(p[1].env.Save())
    p[1].env.Load(saved)
    local shots = F.count(p[1], "CameraPath")
    F.run(2)
    check(F.count(p[1], "CameraPath") == shots and saved.cameraComplete[0], "a loaded opening is not resumed and finishes")
    burglary(w, p[1], saved)
    local before = #p[1].calls
    p[1].env.Load(copy(p[1].env.Save()))
    F.run(1)
    local objective
    for i = before + 1, #p[1].calls do
        local c = p[1].calls[i]
        if c[1] == "AddObjective" and c[2] == "ch07002n.otf" and c[3] == "white" then objective = true end
    end
    check(objective, "the bridge objective is published again after a load")
end

-- ------------------------------------------------------------------ a missing audio handle counts as finished
do
    local w, p, m = setup(1, {})
    openingDone(w)
    m.doNorthSequence = true
    m.cameraReady[2] = true
    m.seqSound = nil
    m.arrived = true
    F.run(1)
    check(not m.doNorthSequence, "a bridge film whose line is absent still ends")
end

print("chmisn07 co-op: " .. checks .. " checks passed")
