-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/bd05cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/Test-Bdmisn05Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Bdmisn05Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local function extrasFor(n) return math.min(math.floor(n / 2), 2) end
local FIRST_WAVE_UNITS = 4

local function setup(n, options)
    options = options or {}
    local w = F.reset()
    w.audioBusy = options.busy == true
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
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
        for _, name in ipairs({"BuildObject", "SetScrap", "SetCloaked", "Goto", "Attack", "Retreat"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on the authored enemy team 2") end
end
-- Destroy every unit the script built, or every enemy there is (map units too).
local function reap(everything)
    for h, o in pairs(F.world().objects) do
        if o.alive and (h:match("^built") or (everything and h:match("^unit_"))) then o.alive = false end
    end
end
local function finishIntro(w) w.cameraDone["camera_start_arc"] = true; F.run(1) end

-- ------------------------------------------------------------------ offline == faithful
local function summary(peer)
    local out = {}
    for _, c in ipairs(peer.calls) do
        if c[1] == "BuildObject" then
            out[#out + 1] = "B:" .. c[3] .. ":" .. (c[4] == 2 and 5 or c[4]) .. ":" .. tostring(c[5])
        elseif c[1] == "SucceedMission" or c[1] == "FailMission" then
            out[#out + 1] = c[1] .. ":" .. tostring(c[3])
        elseif c[1] == "SetCloaked" then
            out[#out + 1] = "C"
        elseif c[1] == "Retreat" then
            out[#out + 1] = "R:" .. tostring(c[3])
        elseif c[1] == "PortalIn" then
            out[#out + 1] = "P"
        end
    end
    local lines = {}
    for _, c in ipairs(peer.calls) do
        if c[1] == "AudioMessage" or c[1] == "Play" then lines[#lines + 1] = c[2] end
    end
    -- the two unused voice lines are the only audio the CR layer adds
    local kept = {}
    for _, l in ipairs(lines) do if l ~= "bd05003.wav" and l ~= "bd05007.wav" then kept[#kept + 1] = l end end
    return table.concat(out, ",") .. "|" .. table.concat(kept, ",")
end
local function fullRun(options)
    local w = F.reset()
    local peer = F.makePeer(1, 1, false, options)
    F.connect(); F.run(1)
    -- the human is away from every staging point, so no entry is watched and the offline run equals the faithful one
    F.place(peer.player, 2500, 99000)
    w.cameraDone["camera_start_arc"] = true
    -- every wave is beaten as it comes; the base is cleared at the end
    for _ = 1, 1300 do F.run(1); reap(false) end
    reap(true)
    F.run(5)
    -- the retreating column reaches the portal
    for h, o in pairs(w.objects) do if h:match("^built") and o.alive then F.nearTo(h, "portal", 5, 0) end end
    F.run(60)
    return summary(peer), peer
end
do
    local faithful = fullRun({ faithful = true, script = "Scripts/bd05.lua" })
    local offline, peer = fullRun({})
    check(faithful == offline and faithful:find("SucceedMission:bd05win.des", 1, true),
        "offline completes like the faithful port:\n" .. faithful .. "\n" .. offline)
    check(F.count(peer, "SucceedMission") == 1 and F.count(peer, "FailMission") == 0, "one victory, no failure")
    noEnemyTeamTwo(peer)
    check(F.count(peer, "SetAIControl", 5) == 1 and F.count(peer, "SetAIControl", 2) == 0, "AI control only for enemy team 5")
    check(F.index(peer, "SetAIControl") <= peer.chunkCalls, "SetAIControl runs at chunk root, before Start")
end

-- ------------------------------------------------------------------ teams, scrap, pilots, the opening film
do
    local w, p, m = setup(4, {})
    check(m.startDone and m.coopMissionStarted, "the leader starts the shared mission")
    check(F.count(p[1], "SetScrap", 1) == 1 and F.last(p[1], "SetScrap")[3] == 8 + 10 * 3, "starting scrap: 8 plus 10 per guest")
    for team = 1, 4 do check(F.count(p[1], "SetPilot", team) == 1 and F.callsOf(p[1], "SetPilot")[1][3] == 10, "10 pilots for human team " .. team) end
    for i = 1, 4 do
        check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
        check(F.heardCount(p[i], "bd05001.wav") == 1, "briefing once on peer " .. i)
        check(p[i].camera == 1, "the opening film is shared: peer " .. i)
        check(F.last(p[i], "CameraPath")[2] == "camera_start_arc" and F.last(p[i], "CameraPath")[5] == "recycler", "opening shot on peer " .. i)
        local o = F.callsOf(p[i], "AddObjective")
        check(o[1] and o[1][2] == "bd05001.otf", "objective on peer " .. i)
    end
    -- the shot ends when the path arrives; a guest cannot skip the shared film
    check(not m.cameraComplete[0], "the opening runs until its shot arrives")
    finishIntro(w)
    check(m.cameraComplete[0], "the opening ends when the path is done")
    for i = 1, 4 do check(p[i].camera == 0, "opening cameras balanced on peer " .. i) end
    guestsPassive(p)
end
do -- a host skip releases only the host's camera and the runtime stops driving the shot: the opening ends for all
    local w, p, m = setup(3, {})
    w.cancel = true; F.run(2)
    w.cancel = false; F.run(1)
    check(m.cameraComplete[0], "a host skip ends the shared opening instead of stalling it")
    for i = 1, 3 do check(p[i].camera == 0, "no peer is left in the film after a host skip: " .. i) end
end
do -- offline: skippable
    local w, p, m = setup(1, {})
    check(p[1].camera == 1, "offline opening opens")
    w.cancel = true; F.run(1)
    check(m.cameraComplete[0] and p[1].camera == 0, "offline skip ends the opening")
    w.cancel = false; F.run(40)
    check(F.count(p[1], "CameraReady") == 1, "a skipped opening never restarts")
end

-- ------------------------------------------------------------------ the waves: scaling, cloak, orders, no pop-in
local WAVES = {
    { at = 300, where = "first_wave", n = 4, order = "Goto" },
    { at = 540, where = "second_wave", n = 4, order = "Attack" },
    { at = 840, where = "third_wave", n = 5, order = "Goto" },
    { at = 1140, where = "fourth_wave", n = 6, order = "Goto" },
}
for humans = 1, 4 do
    local w, p, m = setup(humans, {})
    finishIntro(w)
    local e = extrasFor(humans)
    local total = 0
    for _, wave in ipairs(WAVES) do
        F.runUntil(function() return w.now > wave.at + 4 end, 2000)
        local units = builtAt(p[1], wave.where)
        check(#units == wave.n + e, humans .. " human(s): " .. wave.where .. " is " .. wave.n .. " + " .. e .. " extras, got " .. #units)
        allSafe(p, units)
        for _, b in ipairs(units) do
            check(b.team == 5 and b.odf:sub(1, 2) == "cv", "wave units are Chinese craft on team 5")
            check(F.world().objects[b.h].cloaked, "every wave unit is cloaked (extras too)")
        end
        local orders = 0
        for _, c in ipairs(F.callsOf(p[1], wave.order)) do
            if c[3] == "recycler" and c[4] == 1 then
                for _, b in ipairs(units) do if c[2] == b.h then orders = orders + 1 end end
            end
        end
        check(orders == wave.n + e, wave.where .. ": the extras mirror the orders against the recycler: " .. orders)
        total = total + wave.n + e
        reap(false) -- the wave is beaten (the live cap is tested on its own)
        p[1].env.Save().crcca.live = {}
    end
    -- artillery (420 s) and the two rear attacks (450 s, 660 s): next to the base, so another hidden approach is used
    check(#builtAt(p[1], "howit") == 0 and #builtAt(p[1], "rear_attack") == 0, "the base-side points are watched by the humans: nothing is built there")
    local artillery = F.builds(p[1], 0, "cvartl")
    check(#artillery == 2 + e, humans .. " human(s): artillery pair + extras: " .. #artillery)
    allSafe(p, artillery)
    local scaled = 0
    for _, b in ipairs(F.builds(p[1])) do if b.odf:sub(1, 2) == "cv" then scaled = scaled + 1 end end
    check(scaled == 31 + 7 * e, humans .. " human(s): 31 wave units plus 7 events x " .. e .. " extras, got " .. scaled)
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end

-- ------------------------------------------------------------------ unused voice lines and the retreat of the radio
do -- bd05002 at 240 s, bd05003 (restored) only once the first wave shows itself
    local w, p, m = setup(2, {})
    finishIntro(w)
    F.runUntil(function() return w.now > 245 end)
    heardAll(p, "bd05002.wav")
    check(F.heardCount(p[1], "bd05003.wav") == 0, "no 'paydirt' before the wave")
    F.runUntil(function() return w.now > 300 + 60 end)
    check(F.heardCount(p[1], "bd05003.wav") == 0, "...nor while the wave is far from everybody")
    F.runUntil(function() return w.now > 300 + 95 end)
    heardAll(p, "bd05003.wav")
    F.run(60)
    heardAll(p, "bd05003.wav")
end
do -- contact: a human within 600 m (but outside the 460 m of the entry) of a first-wave unit
    local w, p, m = setup(2, {})
    finishIntro(w)
    F.place(p[2].player, 1104 + 500, 100937)
    F.runUntil(function() return w.now > 300 + 3 end)
    heardAll(p, "bd05003.wav")
    check(F.index(p[1], "Play", "bd05002.wav") < F.index(p[1], "Play", "bd05003.wav"), "after 'Where are they?'")
end
do
    local w, p, m = setup(2, {})
    finishIntro(w)
    F.runUntil(function() return w.now > 320 end)
    local before = F.heardCount(p[1], "bd05003.wav")
    local state = p[1].env.Save()
    state.coopFailed = true; F.run(1) -- the out-of-lives result the runtime publishes
    heardAll(p, "bd05007.wav")
    F.run(5)
    heardAll(p, "bd05007.wav")
    check(before == 0, "no paydirt line yet")
end
do -- after the victory neither line plays
    local w, p, m = setup(1, {})
    finishIntro(w)
    m.won = true
    F.run(130 + 300)
    check(F.heardCount(p[1], "bd05003.wav") == 0, "no 'paydirt' after the win")
    m.coopFailed = true; F.run(2)
    check(F.heardCount(p[1], "bd05007.wav") == 0, "no 'blown it' after the win")
end

-- ------------------------------------------------------------------ the gate: extras and waiting arrivals count
do
    local w, p, m = setup(4, {})
    finishIntro(w)
    F.runUntil(function() return w.now > 1145 end, 2000)
    reap(true)
    -- a co-op extra the body does not track stays alive (it is in the runtime's live list, not in the body's)
    local spare = F.spawn("cvtnk", 5, 3000, 98000)
    local live = m.crcca.live
    live[#live + 1] = spare
    F.run(3)
    check(m.waitOver[4] and not m.objective2Complete, "an extra the body does not track keeps the base from being 'cleared'")
    F.kill(spare); F.run(2)
    check(m.objective2Complete, "the base is cleared once the extra is dead too")
end
do -- a request still waiting for a hidden entry also counts
    local w, p, m = setup(2, {})
    finishIntro(w)
    F.runUntil(function() return w.now > 1145 end, 2000)
    reap(true)
    m.crcca.arrivals[999] = { odf = "cvtnk", team = 5, where = "fourth_wave", orders = {}, extra = true }
    m.crcca.serial = 999
    local before = #F.builds(p[1], 0, "cvtnk")
    F.runUntil(function() return #F.builds(p[1], 0, "cvtnk") > before end, 5)
    -- the waiting extra is built, then it must die before the base counts as cleared
    reap(false)
    F.run(2)
    check(m.objective2Complete, "the base is cleared once the late extra is dead")
end
do
    local w, p, m = setup(2, {})
    finishIntro(w)
    F.runUntil(function() return w.now > 1145 end, 2000)
    reap(true)
    m.crcca.arrivals[999] = { odf = "cvtnk", team = 5, where = "fourth_wave", orders = {}, extra = true }
    m.crcca.serial = 999
    -- watched everywhere, so the arrival cannot be built yet
    F.place(p[2].player, 4000, 98000)
    for _, name in ipairs({ "first_wave", "second_wave", "third_wave", "fourth_wave", "howit", "rear_attack" }) do
        w.pathPos[name] = { x = 4000, y = 10, z = 98000 }
    end
    F.run(3)
    check(not m.objective2Complete and next(m.crcca.arrivals) ~= nil, "a waiting arrival keeps the base from being 'cleared'")
end

-- ------------------------------------------------------------------ the retreat: portal, quitters, shared film, victory
for humans = 1, 4 do
    local w, p, m = setup(humans, {})
    finishIntro(w)
    F.runUntil(function() return w.now > 1145 end, 2000)
    reap(true)
    w.audioBusy = true
    F.run(3)
    check(m.objective2Complete and m.objective1Complete and m.quittersSpawned, humans .. ": the cleared base sends the Chinese to the portal")
    heardAll(p, "bd05004.wav")
    local quitters = builtAt(p[1], "quitters")
    check(#quitters == 6, "exactly six quitters, no extras, got " .. #quitters)
    for _, b in ipairs(quitters) do
        check(b.team == 5, "the quitters are the enemy team")
        check(F.world().objects[b.h].cloaked ~= true, "the quitters are not cloaked")
    end
    check(type(m.quitters[0]) == "string", "the quitters are real units (stage props), never tickets")
    local retreats = 0
    for _, c in ipairs(F.callsOf(p[1], "Retreat")) do if c[3] == "portal_in" and c[4] == 1 then retreats = retreats + 1 end end
    check(retreats == 6, "six retreat orders to portal_in")
    for i = 1, humans do
        check(F.count(p[i], "PortalIn") == 1, "the portal pulse runs once on peer " .. i)
        check(p[i].camera == 1 and F.last(p[i], "CameraPath")[2] == "camera_retreat" and F.last(p[i], "CameraPath")[5] == "portal",
            "the retreat film is shared: peer " .. i)
        check(F.heardCount(p[i], "bd05005.wav") == 1, "retreat narration on peer " .. i)
    end
    -- one quitter reaches the portal and is removed
    F.nearTo(quitters[1].h, "portal", 5, 0); F.run(1)
    check(F.count(p[1], "RemoveObject", quitters[1].h) == 1 and m.quitters[0] == nil, "a quitter touching the portal is removed")
    if humans > 1 then
        w.cancel = true; F.run(1)
        check(not m.quitterMovieDone, "the shared retreat film cannot be skipped in a network game")
        w.cancel = false
    end
    w.audioBusy = false
    F.runUntil(function() return m.quitterMovieDone end, 60)
    check(m.quitterMovieDone, "the film ends on its own: 15 s and 3 s after the narration")
    w.audioBusy = true
    for i = 1, humans do check(p[i].camera == 0, "retreat cameras balanced on peer " .. i) end
    F.run(2)
    heardAll(p, "bd05006.wav")
    check(m.won, "the victory narration plays")
    w.audioBusy = false; F.run(3)
    for i = 1, humans do
        check(F.count(p[i], "SucceedMission") == 1 and F.count(p[i], "FailMission") == 0, "one shared victory on peer " .. i)
        check(F.last(p[i], "SucceedMission")[3] == "bd05win.des", "victory debrief on peer " .. i)
        check((p[i].env.Save().coopUnresolved or 0) == 0, "no unresolved presentation identities on peer " .. i)
    end
    guestsPassive(p)
end
do -- offline the film is skippable
    local w, p, m = setup(1, {})
    finishIntro(w)
    F.runUntil(function() return w.now > 1145 end, 2000)
    reap(true); F.run(3)
    check(m.quittersSpawned and p[1].camera == 1, "retreat film open")
    w.cancel = true; F.run(1)
    check(m.quitterMovieDone and p[1].camera == 0, "offline skip ends the retreat film")
end

-- ------------------------------------------------------------------ stock bug: no recycler, the waves hunt the humans
do
    local w, p, m = setup(3, {})
    finishIntro(w)
    F.kill("recycler")
    F.runUntil(function() return w.now > 300 + 25 end)
    local units = builtAt(p[1], "first_wave")
    check(#units == FIRST_WAVE_UNITS + 1, "wave 1 is still built without a recycler")
    local gotos = 0
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[3] == "recycler" then gotos = gotos + 1 end end
    check(gotos == 0, "no order is aimed at the dead recycler")
    local humans = {}
    for _, q in ipairs(p) do humans[q.player] = true end
    local hunts = 0
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do if humans[c[3]] and c[4] == 1 then hunts = hunts + 1 end end
    check(hunts >= #units, "every wave unit is sent against the nearest human: " .. hunts)
    local again = hunts
    F.run(45)
    local more = 0
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do if humans[c[3]] then more = more + 1 end end
    check(more > again, "the hunt is re-issued")
end
do -- with the recycler standing nothing is retargeted
    local w, p, m = setup(3, {})
    finishIntro(w)
    F.runUntil(function() return w.now > 340 end)
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do check(c[3] ~= p[1].player and c[3] ~= p[2].player, "waves go for the recycler while it stands") end
end

-- ------------------------------------------------------------------ concealment, saves, the cap
local STAGING = { "first_wave", "second_wave", "third_wave", "fourth_wave", "howit", "rear_attack" }
local function watchEverything(w, p)
    F.place(p[2].player, 4000, 98000)
    F.world().objects[p[2].player].craft = false
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
    finishIntro(w)
    local release = watchEverything(w, p)
    F.runUntil(function() return w.now > 310 end)
    check(#F.builds(p[1], 0, "cvfigh") == 0 and #F.builds(p[1], 0, "cvltnk") == 0, "a fully watched map defers every wave")
    check(type(m.units[15]) == "number" and m.units[15] < 0 and m.crcca.serial >= 4, "the body holds tickets while the wave waits")
    check(F.count(p[1], "SetCloaked") == 0 and F.count(p[1], "Goto") == 0, "no native call ever sees a ticket")
    local pending = m.crcca.serial
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(m.crcca.serial == pending and #F.builds(p[1], 0, "cvfigh") == 0, "save/load keeps the pending wave without duplicating it")
    release(); F.run(5)
    local total = #F.builds(p[1], 0, "cvfigh") + #F.builds(p[1], 0, "cvltnk")
    check(total == FIRST_WAVE_UNITS + 2, "the whole wave is built exactly once when the watcher leaves, got " .. total)
    check(type(m.units[15]) == "string", "tickets resolve to real units")
    local cloaked = 0
    for _, o in pairs(F.world().objects) do if o.cloaked then cloaked = cloaked + 1 end end
    check(cloaked == 4 + 2, "the deferred cloak is applied to the primaries and their extras: " .. cloaked)
end
do -- live cap: extras are the only requests dropped
    local w, p, m = setup(4, {})
    finishIntro(w)
    m.crcca.live = {}
    for i = 1, 20 do m.crcca.live[i] = F.spawn("cvtnk", 5, 9000 + i, 9000) end
    F.runUntil(function() return w.now > 305 end)
    check(#builtAt(p[1], "first_wave") == 4, "at the live cap the wave keeps its primaries and drops the extras: " .. #builtAt(p[1], "first_wave"))
end
do -- a load during the opening film opens the camera again, once, and the film still ends
    local w, p, m = setup(3, {})
    F.run(3)
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(p[1].camera == 1, "the film's camera is reopened after a load")
    finishIntro(w)
    for i = 1, 3 do check(p[i].camera == 0, "camera balanced after the load on peer " .. i) end
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
    check(F.count(p[1], "EnvironmentInit") == 0 and m.startDone, "no weather module: the mission runs and touches no Environment")
    local printed = false
    for _, c in ipairs(p[1].calls) do if c[1] == "print" and tostring(c[2]):find("weather disabled", 1, true) then printed = true end end
    check(printed, "missing weather is logged, not fatal")
end
local function ganymede(record, mode, sites)
    return function(peer)
        local V = { Seed = 4242, Initialized = false }
        function V.Init(o)
            peer.weatherInit = o; V.Initialized = true
            record("EuropaInit", o.authority, o.send ~= nil, o.seed, o.startLevel, o.targetLevel)
            if mode == "initfail" then error("boom") end
        end
        function V.Update()
            if peer.weatherInit and peer.weatherInit.authority and peer.weatherInit.send and not V.sent then
                V.sent = true; peer.weatherInit.send("EuropaQuake", 0.5, 2)
            end
            if mode == "updatefail" then error("update boom") end
        end
        function V.AnnounceState() record("EuropaAnnounce") end
        function V.ApplyNetEvent(op, ...) record("EuropaEvent", op, ...) end
        function V.SetTargetLevel(n) record("EuropaLevel", n) end
        function V.GetVentSites() return sites.vents end
        function V.TriggerPlume(index) record("EuropaPlume", index) end
        function V.Quake(strength, seconds) record("EuropaQuakeCall", strength, seconds) end
        function V.Surge(a, b) record("EuropaSurgeCall", a, b) end
        function V.OnObjectCreated(h) record("EuropaCreated", h) end
        function V.Save() return { saved = true } end
        function V.Load(s) record("EuropaLoad", s and s.saved) end
        function V.Shutdown() record("EuropaShutdown") end
        return V
    end
end
do
    -- the real generated sites: three geyser vents next to the base
    local sites = dofile("Scripts/CRGanymedeSitesBD05.lua")
    check(sites.mission == "bdmisn05" and #sites.vents == 3 and sites.vents[2].label == "eggeizr14_geyser", "the generated sites carry the three geysers")
    local weather = { module = function(peer, record) return ganymede(record, nil, sites)(peer) end, sites = sites }
    local w, p, m = setup(3, { weather = weather })
    check(F.count(p[1], "EuropaInit", true) == 1 and F.last(p[1], "EuropaInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.last(p[1], "EuropaInit")[5] == 1 and F.last(p[1], "EuropaInit")[6] == 1, "the moon starts quiet")
    check(F.count(p[2], "EuropaInit", false) == 1, "guests render only (not the authority)")
    check(F.count(p[1], "EuropaAnnounce") == 1 and F.count(p[2], "EuropaAnnounce") == 0, "the leader announces its weather state once")
    local env = F.last(p[1], "EnvironmentInit")[2]
    check(F.count(p[1], "EnvironmentInit") == 1 and env.lightingMode == "orbit", "orbit lighting is initialised")
    for i = 2, 3 do
        local e = F.last(p[i], "EuropaEvent")
        check(e and e[2] == "EuropaQuake" and e[3] == 0.5, "weather events reach guest " .. i)
    end
    check(F.count(p[1], "WeatherSensors", "Ganymede") == 1, "the sensor modifier is bound once")
    check(p[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    finishIntro(w)
    F.runUntil(function() return w.now > 295 end)
    check(F.count(p[1], "EuropaLevel", 2) == 0, "calm until the first wave")
    F.runUntil(function() return w.now > 305 end)
    check(F.count(p[1], "EuropaLevel", 2) == 1, "the first wave stirs the moon")
    F.runUntil(function() return w.now > 545 end)
    check(F.count(p[1], "EuropaLevel", 3) == 1 and F.count(p[1], "EuropaQuakeCall", 0.35) == 1 and F.count(p[1], "EuropaPlume", 2) == 1,
        "the second wave: level 3, a quake and the vent under the base")
    F.runUntil(function() return w.now > 845 end)
    check(F.count(p[1], "EuropaPlume", 3) == 1, "the third wave opens the next vent")
    F.runUntil(function() return w.now > 1145 end, 2000)
    check(F.count(p[1], "EuropaLevel", 4) == 1 and F.count(p[1], "EuropaSurgeCall", 5.0) == 1, "the last wave: level 4 and a surge")
    check(F.count(p[1], "EuropaCreated") > 0, "new objects are offered to the weather")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "EuropaShutdown") >= 1 and F.count(p[1], "EuropaLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(p[1], "WeatherSensors", "Ganymede") == 2, "the sensor modifier is bound again after a load")
    reap(true); w.audioBusy = true; F.run(3)
    check(F.count(p[1], "EuropaSurgeCall", 6.0) == 1 and F.count(p[1], "EuropaPlume", 1) == 1, "the portal pulse: a surge and the first vent")
    w.audioBusy = false
    F.runUntil(function() return m.won end, 80)
    F.run(3)
    check(F.count(p[1], "EuropaLevel", 2) == 2, "the victory eases the weather")
end
do -- an empty vent list is legal: plumes are skipped, everything else runs
    local sites = { vents = {} }
    local w, p, m = setup(2, { weather = { module = function(peer, record) return ganymede(record, nil, sites)(peer) end, sites = sites } })
    finishIntro(w)
    F.runUntil(function() return w.now > 560 end)
    check(F.count(p[1], "EuropaPlume") == 0 and F.count(p[1], "EuropaLevel", 3) == 1, "no vents, no plumes")
end
do -- sites module missing: no weather, never an error
    local sites = dofile("Scripts/CRGanymedeSitesBD05.lua")
    local w, p, m = setup(2, { weather = { module = function(peer, record) return ganymede(record, nil, sites)(peer) end } })
    check(F.count(p[1], "EuropaInit") == 0 and m.startDone, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local sites = dofile("Scripts/CRGanymedeSitesBD05.lua")
    local w, p, m = setup(2, { weather = { module = function(peer, record) return ganymede(record, mode, sites)(peer) end, sites = sites } })
    finishIntro(w)
    F.runUntil(function() return w.now > 305 end)
    check(#builtAt(p[1], "first_wave") == 4 + 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("bdmisn05 co-op: " .. checks .. " checks passed")
