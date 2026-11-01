-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/misns1cr.lua. Engine AI, rendering and combat remain mocked. Run from the repository root:
--   lua5.1 Tools/Test-Misns1Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Misns1Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local COLORADO, MUF, SILO, SVREC = "avrecy1_recycler", "avmuf1_factory", "absilo1_i76building", "svrecy2_recycler"
local CINEMATIC_SECONDS = 70

local function setup(n, options)
    options = options or {}
    local w = F.reset()
    w.cavalry = options.cavalry or 0; w.route = options.route or 0
    if options.setup then options.setup(w) end
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    if not options.inCinematic then F.run(CINEMATIC_SECONDS) end
    return w, p, p[1].env.Save()
end
local function builtAt(peer, where, mark)
    local out = {}
    for _, b in ipairs(F.builds(peer, mark or 0)) do if b.where == where then out[#out + 1] = b end end
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
        for _, name in ipairs({"BuildObject", "SetScrap", "SetAIP", "Goto", "Follow", "Attack", "SetIndependence", "RemoveObject"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function onCavalry(p, route, humansFar)
    -- Colorado dies before it ever sets off: the cavalry follows 180 s later.
    F.kill(COLORADO)
    F.kill(MUF) -- no factory waves: the cavalry alone is under test
end
local function scrub(p)
    for _, q in ipairs(p) do F.place(q.player, 20 * q.id, 40) end
end

-- ------------------------------------------------------------------ offline == faithful
local function outcomes(options, scenario)
    local w, p, m = setup(1, options)
    scenario(w, p, m)
    local out = {}
    for _, name in ipairs({"SucceedMission", "FailMission"}) do
        for _, c in ipairs(F.callsOf(p[1], name)) do out[#out + 1] = name .. ":" .. tostring(c[3]) end
    end
    return table.concat(out, ","), p[1], m
end
local scenarios = {
    win = function(w, p, m)
        F.kill(COLORADO); F.run(2); F.kill(MUF); F.kill(SILO); F.run(10)
    end,
    recycler = function(w, p, m) F.kill(SVREC); F.run(10) end,
    escape = function(w, p, m)
        F.run(185)
        m.halfwaywarn = true; m.path = 0
        F.nearTo(COLORADO, "hidcamupper", 10, 0); F.run(2)
        F.nearTo(COLORADO, "safepoint", 10, 0); F.run(6)
    end,
}
for name, scenario in pairs(scenarios) do
    local faithful, fpeer = outcomes({ faithful = true, script = "Scripts/misns1.lua" }, scenario)
    local offline, peer, m = outcomes({}, scenario)
    check(faithful == offline and faithful ~= "", "offline completes like the faithful port (" .. name .. "): " .. faithful .. " / " .. offline)
    -- the DLL never finishes the loss shot itself (the engine ends it with the result): same camera stack as stock
    check(peer.camera == fpeer.camera, "offline camera stack matches the faithful port (" .. name .. ")")
end
do
    local out, peer, m = outcomes({}, scenarios.win)
    check(out == "SucceedMission:misns1w1.des", "offline victory: " .. out)
    check(F.count(peer, "SucceedMission") == 1, "one victory request")
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is left on the authored enemy team 2") end
end
do -- offline: the same layer, skippable cinematic
    local w, p, m = setup(1, { inCinematic = true })
    check(p[1].camera == 1 and F.last(p[1], "CameraObject") ~= nil, "offline cinematic opens")
    w.cancel = true; F.run(1)
    check(p[1].camera == 0, "offline skip ends the cinematic")
    w.cancel = false; F.run(70)
    check(p[1].camera == 0 and F.count(p[1], "CameraReady") == 1, "a skipped cinematic never restarts")
end

-- ------------------------------------------------------------------ opening, ownership, teams
local w, p, m = setup(4, { inCinematic = true })
check(m.missionstart and m.coopMissionStarted, "leader starts the shared mission")
check(m.crcca.r.cinT0 ~= nil and m.crcca.r.cinEnd == 50, "the shipped map lacks the cinematic paths: the film runs its object shots only")
check(F.count(p[1], "SetAIControl", 5) == 1 and F.count(p[1], "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
check(F.index(p[1], "SetAIControl") <= p[1].chunkCalls, "SetAIControl runs at chunk root, before Start")
do
    local scraps = {}
    for _, c in ipairs(F.callsOf(p[1], "SetScrap")) do scraps[c[2] .. ":" .. c[3]] = true end
    check(scraps["1:50"] and scraps["5:50"] and not scraps["2:50"], "shared scrap 20 + 10 per guest on team 1, enemy scrap on team 5")
end
for i = 1, 4 do
    check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
    check(F.heardCount(p[i], "misns101.wav") == 1, "briefing once on peer " .. i)
end
guestsPassive(p)
-- The opening cinematic is shared: every guest follows the streamed shot and it ends together.
F.run(2)
for i = 1, 4 do
    check(p[i].camera == 1 and F.last(p[i], "CameraObject") ~= nil, "peer " .. i .. " is in the opening shot")
end
-- A skip releases only the skipping player's own camera; the shared timeline keeps running for everyone.
w.cancel = true; F.run(1)
check(m.crcca.r.cinDone ~= true and m.crcca.r.cinT0 ~= nil, "a skip never ends the shared cinematic in a network game")
check(p[1].camera == 0, "the skipping player's own camera is released")
w.cancel = false
F.run(30)
check(F.count(p[1], "CameraReady") == 1, "the released camera does not restart")
F.run(40)
for i = 1, 4 do check(p[i].camera == 0, "opening cameras balanced on peer " .. i) end
check(m.crcca.r.cinDone, "the shared cinematic ends on the clock")
-- Objectives reach every peer, the base pods are named, nothing arrives on team 2
for i = 1, 4 do
    check(F.callsOf(p[i], "AddObjective")[1][2] == "misns101.otf" and F.callsOf(p[i], "AddObjective")[3][2] == "misns103.otf", "objective list on peer " .. i)
    check(F.count(p[i], "SetObjectiveName") >= 5, "pod names replicate to peer " .. i)
end
for _, b in ipairs(F.builds(p[1])) do check(b.team == 1 or b.team == 5, "builds are on team 1 or 5") end
-- the DLL's two extra escorts survive and later follow Colorado
check(F.alive("avtank7_wingman") and F.alive("avtank8_wingman"), "restored escorts stay")
F.run(115)
check(m.pickpath and F.count(p[1], "Follow", "avtank7_wingman") == 1 and F.count(p[1], "Follow", "avtank8_wingman") == 1, "restored escorts follow Colorado")
check(m.pickpath and F.last(p[1], "Goto") ~= nil, "convoy sets off")
heardAll(p, "misns125.wav")

do -- the map carries the DLL's cinematic paths: the full film, path shots first
    local w2, q, m2 = setup(3, { inCinematic = true, setup = function(world) F.addCinematicPaths(world) end })
    check(m2.crcca.r.cinEnd == 66 and q[1].camera == 1 and F.last(q[1], "CameraPath")[2] == "cinpath3", "full film opens on cinpath3")
    for i = 2, 3 do check(q[i].camera == 1 and F.last(q[i], "CameraPath")[2] == "cinpath3", "guest " .. i .. " follows the path shot") end
    F.run(30)
    check(F.last(q[1], "CameraPath")[2] == "geyserpath" or F.last(q[1], "CameraObject") ~= nil, "film advances")
    F.run(45)
    for i = 1, 3 do check(q[i].camera == 0, "full film ends balanced on peer " .. i) end
end

-- ------------------------------------------------------------------ nearest / farthest semantics
do
    local w2, q = setup(4, {})
    local runtime = q[1].modules.CRCCARuntime.Create(function() return q[1].env.Save() end,
        { id = "t", farthestTargets = { "safepoint", "gate" } })
    local d = runtime.WrapDistance(function() return -1 end)
    local token = runtime.GetPlayerHandle()
    F.nearTo(q[1].player, "safepoint", 100, 0)
    F.nearTo(q[2].player, "safepoint", 900, 0)
    F.nearTo(q[3].player, "safepoint", 300, 0)
    F.nearTo(q[4].player, "safepoint", 500, 0)
    check(math.abs(d(token, "retreat1") - math.min(unpack({
        q[1].env.GetDistance(q[1].player, "retreat1"), q[1].env.GetDistance(q[2].player, "retreat1"),
        q[1].env.GetDistance(q[3].player, "retreat1"), q[1].env.GetDistance(q[4].player, "retreat1") }))) < 1e-6,
        "ordinary target: nearest human")
    check(math.abs(d(token, "safepoint") - 900) < 1e-6, "reach-gate target: farthest human, got " .. d(token, "safepoint"))
    F.nearTo(q[2].player, "safepoint", 50, 0)
    check(math.abs(d(token, "safepoint") - 500) < 1e-6, "farthest moves with the stragglers")
    check(d(token, nil) == math.huge and d(token, 0) == math.huge, "missing targets are infinitely far")
    check(d("not-the-token", "safepoint") == -1, "other origins fall through to the original")
    F.kill(q[4].player)
    check(d(token, "safepoint") == math.huge, "a human without a ship keeps a reach gate closed")
    check(math.abs(d(token, "retreat1") - math.min(q[1].env.GetDistance(q[1].player, "retreat1"), q[1].env.GetDistance(q[2].player, "retreat1"),
        q[1].env.GetDistance(q[3].player, "retreat1"))) < 1e-6, "nearest ignores the dead ship")
end

-- ------------------------------------------------------------------ retreat trigger: any human counts
w, p, m = setup(4, {})
F.nearTo(p[3].player, COLORADO, 150, 0); F.run(3)
check(m.retreat, "any human within 200 m of Colorado starts the retreat")
heardAll(p, "misns114.wav")
check(F.count(p[1], "Goto", COLORADO) >= 1, "Colorado is ordered to retreat by the leader")
guestsPassive(p)
F.nearTo(COLORADO, "eggeizr10_geyser", 10, 0); F.run(2)
check(m.coloradosafe and F.count(p[1], "SetAIP", "misn09.aip") == 1 and F.last(p[1], "SetAIP")[3] == 5, "misn09.aip is handed to team 5")
for i = 1, 4 do check(F.count(p[i], "SetObjectiveOn") >= 3, "objective markers reach peer " .. i) end
heardAll(p, "misns106.wav")
-- wave dispatch: aw1 (tank + two fighters) attack the Soviet recycler together, extras included
scrub(p); F.run(40)
local dispatched = 0
for _, c in ipairs(F.callsOf(p[1], "Attack")) do if c[3] == SVREC then dispatched = dispatched + 1 end end
check(dispatched == 3 + 2, "first factory wave (3 + 2 extras) attacks the Soviet recycler: " .. dispatched)
local fac = builtAt(p[1], MUF)
check(#fac == 5, "wave one at the factory: three units + floor(4/2) extras, got " .. #fac)
for _, b in ipairs(fac) do check(b.team == 5, "factory units are team 5") end
guestsPassive(p)

-- ------------------------------------------------------------------ scaling by head count and the cavalry
local expectedCavalry = { 5, 6, 6, 7 } -- 3 + extras + restored cav4/cav5
for n, expect in ipairs(expectedCavalry) do
    local w2, q, m2 = setup(n, {})
    onCavalry(q, 0)
    F.run(190)
    local wave = builtAt(q[1], "cavspawn")
    check(#wave == expect, n .. " human(s): " .. expect .. " cavalry craft at cavspawn, got " .. #wave)
    allSafe(q, wave)
    for _, b in ipairs(wave) do check(b.team == 5, "cavalry is team 5") end
    check(type(m2.cav1) == "string", "tickets were replaced by real units")
    local routed = 0
    for _, c in ipairs(F.callsOf(q[1], "Goto")) do if c[3] == "cavpath1" then routed = routed + 1 end end
    check(routed == expect, "extras mirror the route (" .. routed .. " of " .. expect .. ")")
    if n == 1 then check(not q[1].net, "one peer is offline") end
end

-- ------------------------------------------------------------------ nothing within 460 m: deferral, fallback, saves
do
    local w2, q, m2 = setup(4, {})
    -- every authored entrance is watched: cavspawn, cavpath1, cavpath2
    F.nearTo(q[2].player, "cavspawn", 100, 0)
    F.nearTo(q[3].player, "cavpath1", 100, 0)
    F.nearTo(q[4].player, "cavpath2", 100, 0)
    onCavalry(q, 0)
    F.run(190)
    check(#builtAt(q[1], "cavspawn") == 0 and #builtAt(q[1], "cavpath1") == 0 and #builtAt(q[1], "cavpath2") == 0, "watched entrances defer every cavalry craft")
    check(type(m2.cav1) == "number" and m2.cav1 < 0 and m2.crcca.serial >= 5, "the body holds tickets while the wave waits")
    local pending = m2.crcca.serial
    for _, r in ipairs(q) do r.env.Load(r.env.Save()) end
    F.connect(); F.run(3)
    check(m2.crcca.serial == pending and #builtAt(q[1], "cavspawn") == 0, "save/load keeps the pending wave without duplicating it")
    -- an unwatched fallback entrance is used
    F.place(q[3].player, 20 * 3, 40); F.run(3)
    local fell = builtAt(q[1], "cavpath1")
    check(#fell > 0 and #builtAt(q[1], "cavspawn") == 0, "a watched cavspawn falls back to another authored approach")
    allSafe(q, fell)
    scrub(q); F.run(6)
    local total = #builtAt(q[1], "cavspawn") + #builtAt(q[1], "cavpath1") + #builtAt(q[1], "cavpath2")
    check(total == 7, "the whole wave is built exactly once, got " .. total)
    check(type(m2.cav1) == "string", "tickets resolve to real units")
end
-- live cap: extras are the only requests dropped
do
    local w2, q, m2 = setup(4, {})
    m2.crcca.live = {}
    for i = 1, 12 do m2.crcca.live[i] = F.spawn("avtank", 5, 9000 + i, 9000) end
    onCavalry(q, 0)
    F.run(190)
    check(#builtAt(q[1], "cavspawn") == 5, "at the live cap the wave keeps its primaries and drops the extras: " .. #builtAt(q[1], "cavspawn"))
end

-- ------------------------------------------------------------------ shared audio, objectives, results
w, p, m = setup(4, {})
F.kill(COLORADO); F.run(2)
check(m.safety1 and F.count(p[1], "SetAIP", "misn14.aip") == 1 and F.last(p[1], "SetAIP")[3] == 5, "misn14.aip is handed to team 5")
heardAll(p, "misns105.wav")
F.kill(MUF); F.run(1); F.kill(SILO); F.run(1)
for i = 1, 4 do check(F.heard(p[i], "misns108.wav") and F.heard(p[i], "misns107.wav"), "destruction lines on peer " .. i) end
-- the DLL asks for the same objective rebuild every frame from here on: the stream must not grow
F.run(2)
local before = {}
for i = 1, 4 do before[i] = F.count(p[i], "AddObjective") end
F.run(20)
for i = 1, 4 do check(F.count(p[i], "AddObjective") == before[i], "an unchanged objective list is not re-sent (peer " .. i .. ")") end
F.run(8)
heardAll(p, "misns110.wav")
for i = 1, 4 do
    check(F.count(p[i], "SucceedMission") == 1 and F.count(p[i], "FailMission") == 0, "one shared victory on peer " .. i)
    check(F.last(p[i], "SucceedMission")[3] == "misns1w1.des", "victory debrief on peer " .. i)
    check((p[i].env.Save().coopUnresolved or 0) == 0, "no unresolved presentation identities on peer " .. i)
end
guestsPassive(p)

-- recycler loss
w, p, m = setup(3, {})
w.audioBusy = true; F.kill(SVREC); F.run(1); w.audioBusy = false; F.run(12)
for i = 1, 3 do
    check(F.heardCount(p[i], "misns112.wav") == 1 and F.heardCount(p[i], "misns113.wav") == 1, "recycler-loss lines on peer " .. i)
    check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "misns1l2.des", "one shared recycler-loss failure on peer " .. i)
end
check(F.index(p[2], "Queue", "misns113.wav") ~= nil, "the second line queues behind the first")

-- escape loss: the held shot reaches every peer
do
    local w2, q, m2 = setup(4, {})
    F.run(185)
    m2.halfwaywarn = true; m2.path = 0
    F.nearTo(COLORADO, "hidcamupper", 10, 0); F.run(2)
    check(m2.blockaderun, "blockade run")
    w2.audioBusy = true
    F.nearTo(COLORADO, "safepoint", 10, 0); F.run(2)
    check(m2.coloradoreachedsafepoint, "Colorado reaches the safe point")
    for i = 1, 4 do
        check(q[i].camera == 1, "loss shot on peer " .. i)
        check(#F.callsOf(q[i], "CameraObject") > 3, "the one-shot CameraObject is held for peer " .. i)
    end
    check(F.count(q[1], "FailMission") == 0, "the failure waits for both radio lines")
    w2.audioBusy = false; F.run(12)
    for i = 1, 4 do
        check(F.count(q[i], "FailMission") == 1 and F.last(q[i], "FailMission")[3] == "misns1l1.des", "escape failure on peer " .. i)
        check(q[i].camera == 0, "result balances the camera on peer " .. i)
    end
end
-- geyser2 is preferred as the camera anchor when the map carries it
do
    local w2, q, m2 = setup(2, { setup = function() F.LABELS["geyser2"] = { odf = "eggeizr1", team = 0, pos = { 2550, 94, 50 }, craft = false } end })
    check(m2.geyser2 == "geyser2", "the commented-out geyser2 lookup is restored")
    F.run(185); m2.halfwaywarn = true; m2.path = 0
    F.nearTo(COLORADO, "hidcamupper", 10, 0); F.run(2)
    F.nearTo(COLORADO, "safepoint", 10, 0); F.run(2)
    check(F.last(q[1], "CameraObject")[2] == "geyser2", "loss shot anchors on geyser2")
    F.LABELS["geyser2"] = nil
end

-- ------------------------------------------------------------------ leader leaves
w, p, m = setup(3, {})
for i = 2, 3 do p[i].env.DeletePlayer(1) end
F.run(3)
for i = 2, 3 do check(F.count(p[i], "FailMission") == 1, "the mission fails for guest " .. i .. " when the leader leaves") end
check(F.count(p[1], "FailMission") == 0, "the leader itself keeps playing")

-- ------------------------------------------------------------------ save/load mid-mission
w, p, m = setup(4, {})
F.run(185)
local pathBefore, randoms = m.path, F.count(p[1], "random")
for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
F.connect(); F.run(5)
check(p[1].env.Save().path == pathBefore and F.count(p[1], "random") == randoms, "load keeps the saved route and never redraws it")
check(F.count(p[1], "SetScrap") == 4 and F.count(p[1], "BuildObject") == 10, "load does not rerun the first frame")
F.kill(COLORADO); F.kill(MUF); F.kill(SILO); F.run(12)
for i = 1, 4 do check(F.count(p[i], "SucceedMission") == 1, "the loaded mission still ends once on peer " .. i) end
-- a load during the cinematic ends it (cameras are gone) and restarts nothing
w, p, m = setup(3, { inCinematic = true })
F.run(10)
for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
F.connect(); F.run(3)
check(F.count(p[1], "CameraReady") == 1, "no second cinematic after a load")
F.run(5)
for i = 1, 3 do check(p[i].camera == 0, "cameras balanced after a load mid-cinematic, peer " .. i) end

-- ------------------------------------------------------------------ weather: absent, present, broken
do
    w, p, m = setup(3, {})
    check(F.count(p[1], "EnvironmentInit") == 0 and m.missionstart, "no weather module: the mission runs and touches no Environment")
    local printed = false
    for _, c in ipairs(p[1].calls) do if c[1] == "print" and tostring(c[2]):find("weather disabled", 1, true) then printed = true end end
    check(printed, "missing weather is logged, not fatal")
end
local function venus(record, mode)
    return function(peer)
        local V = { Seed = 4242, level = {} }
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
    local weather = { module = function(peer, record) return venus(record)(peer) end, sites = { bounds = {} } }
    w, p, m = setup(3, { weather = weather })
    check(F.count(p[1], "VenusInit", true) == 1 and F.last(p[1], "VenusInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.count(p[2], "VenusInit", false) == 1, "guests render only (not the authority)")
    check(F.count(p[1], "VenusAnnounce") == 1 and F.count(p[2], "VenusAnnounce") == 0, "the leader announces its weather state once")
    check(F.count(p[1], "EnvironmentInit") == 1, "Venus lighting is initialised")
    for i = 2, 3 do
        local e = F.last(p[i], "VenusEvent")
        check(e and e[2] == "VenusStrike" and e[3] == 3 and e[4] == 4, "weather events reach guest " .. i)
    end
    check(F.count(p[1], "VenusEvent") == 0, "the leader's director applied its own event; the stream is for guests")
    check(p[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    F.nearTo(p[2].player, COLORADO, 150, 0); F.run(3)
    check(F.count(p[1], "VenusLevel", 3) == 1, "the retreat raises the weather")
    check(F.count(p[1], "VenusCreated") > 0, "new objects are offered to the weather")
    local seed = p[1].env.Save().crcca
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "VenusShutdown") >= 1 and F.count(p[1], "VenusLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(p[1], "VenusInit") == 2, "the weather re-initialises after a load")
end
do -- sites module missing: no weather, never an error
    w, p, m = setup(2, { weather = { module = function(peer, record) return venus(record)(peer) end } })
    check(F.count(p[1], "VenusInit") == 0 and m.missionstart, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    w, p, m = setup(2, { weather = { module = function(peer, record) return venus(record, mode)(peer) end, sites = {} } })
    F.kill(COLORADO); F.kill(MUF); F.kill(SILO); F.run(12)
    check(F.count(p[1], "SucceedMission") == 1 and F.count(p[2], "SucceedMission") == 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("misns1 co-op: " .. checks .. " checks passed")
