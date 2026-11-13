-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/misns4cr.lua. Engine AI, rendering and combat remain mocked. Run from the repository root:
--   lua5.1 Tools/MissionTests/Test-Misns4Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/MissionTests/Misns4Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local function setup(n, options)
    options = options or {}
    local w = F.reset()
    if options.setup then options.setup(w) end
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
local function builtAt(peer, where, odf, mark)
    local out = {}
    for _, b in ipairs(F.builds(peer, mark or 0, odf)) do if b.where == where then out[#out + 1] = b end end
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
        for _, name in ipairs({"BuildObject", "AddScrap", "SetPilot", "SetAIP", "Goto", "RemoveObject"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function expectedExtras(n) return math.min(math.floor(n / 2), 2) end
-- Runs to the first convoy spawn (420 s) and then the next four (45 s apart).
local function toConvoy(n_haulers)
    F.run(421)
    F.run(45 * ((n_haulers or 1) - 1) + 1)
end
local function haulers(peer) return builtAt(peer, "spawn1", "svhaul") end
local function arrive(h) F.nearTo(h, "goal", 20, 0) end

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
    win = function(w, p)
        toConvoy(5)
        local hs = haulers(p[1])
        for i = 1, 4 do arrive(hs[i].h) end
        F.run(12)
    end,
    lose = function(w, p)
        toConvoy(3)
        local hs = haulers(p[1])
        F.kill(hs[1].h); F.run(1); F.kill(hs[2].h); F.run(20)
    end,
}
for name, scenario in pairs(scenarios) do
    local faithful = outcomes({ faithful = true, script = "Scripts/misns4.lua" }, scenario)
    local offline = outcomes({}, scenario)
    check(faithful == offline and faithful ~= "", "offline completes like the faithful port (" .. name .. "): " .. faithful .. " / " .. offline)
end
do
    local out, peer = outcomes({}, scenarios.win)
    check(out == "SucceedMission:misns4w1.des", "offline victory: " .. out)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is left on the authored enemy team 2") end
    local lost = outcomes({}, scenarios.lose)
    check(lost == "FailMission:misns4l1.des", "offline defeat: " .. lost)
    -- offline there are no extras: the faithful counts
    check(#builtAt(peer, "spawn4", "bvraz") == 3 and #builtAt(peer, "sbridge", "bvtank") == 2, "offline builds the faithful counts")
end

-- ------------------------------------------------------------------ opening, ownership, teams, scrap
local w, p, m = setup(4)
check(m.start_done and m.coopMissionStarted, "leader starts the shared mission")
check(F.count(p[1], "SetAIControl", 5) == 1 and F.count(p[1], "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
check(F.index(p[1], "SetAIControl") <= p[1].chunkCalls, "SetAIControl runs at chunk root, before Start")
do
    local scraps = {}
    for _, c in ipairs(F.callsOf(p[1], "AddScrap")) do scraps[c[2] .. ":" .. c[3]] = true end
    check(scraps["1:80"] and not scraps["1:50"], "shared scrap 50 + 10 per guest on team 1")
    local pilots = {}
    for _, c in ipairs(F.callsOf(p[1], "SetPilot")) do pilots[c[2] .. ":" .. c[3]] = true end
    check(pilots["1:30"] and pilots["2:30"] and pilots["3:30"] and pilots["4:30"], "pilots for every human team")
    check(pilots["5:30"], "the enemy team 5 gets the DLL's team 2 pilots")
    local twos = 0
    for _, c in ipairs(F.callsOf(p[1], "SetPilot")) do if c[2] == 5 then twos = twos + 1 end end
    check(twos == 1, "exactly one enemy pilot grant")
end
for i = 1, 4 do
    check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
    heardAll({p[i]}, "misns401.wav"); heardAll({p[i]}, "misns410.wav")
    check(F.count(p[i], "StartCockpitTimer") == 1 and F.last(p[i], "StartCockpitTimer")[2] == 420, "the 420 s countdown shows on peer " .. i)
    check(F.callsOf(p[i], "AddObjective")[1][2] == "misns4.otf", "objective on peer " .. i)
    check(F.count(p[i], "SetObjectiveName") >= 1 and F.last(p[i], "SetObjectiveName")[3] == "Bridge", "the Bridge pod is named on peer " .. i)
end
for _, b in ipairs(F.builds(p[1])) do check(b.team == 1 or b.team == 5, "builds are on team 1 or 5") end
check(#builtAt(p[1], "spawn2", "bvartl") == 1 and #builtAt(p[1], "tower1", "bbtowe") == 1 and #builtAt(p[1], "power2", "bblpow") == 1,
    "the opening structures are built (towers, power, howitzer)")
check(#builtAt(p[1], "svcnst", "svcnst") == 1 and #builtAt(p[1], "camerapt", "spcamr") == 1, "the Soviet constructor and the Bridge pod")
for _, b in ipairs(F.builds(p[1], 0, "bbtowe")) do check(b.team == 5, "enemy structures are team 5") end
guestsPassive(p)
-- reminder fighter, raiders (+ extras), restored light tank
F.run(40)
check(F.alive(m.cam1), "pod alive")
local figh = builtAt(p[1], "spawn4", "bvraz")
check(#figh == 1 + 2 + expectedExtras(4), "wakeup fighter + two raiders + 2 extras at spawn4: " .. #figh)
check(#builtAt(p[1], "spawn4", "bvltnk") == 1, "restored light tank rides with the raiders")
local wake = 0
for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[3] == "wakeup" then wake = wake + 1 end end
check(wake == 1, "only the reminder fighter is sent down the wakeup path")
for _, b in ipairs(figh) do check(b.team == 5, "raiders are team 5") end
allSafe(p, figh)
guestsPassive(p)
-- bridge guard at 100 s
F.run(65)
local tanks = builtAt(p[1], "sbridge", "bvtank")
check(#tanks == 2 + expectedExtras(4), "bridge guard: two tanks + 2 extras, got " .. #tanks)
check(#builtAt(p[1], "sbridge", "bvhraz") == 2, "bridge guard howitzer + the restored second howitzer")
check(type(m.t1) == "string" and type(m.b1) == "string" and type(m.b2) == "string", "tickets resolved to real handles")
allSafe(p, tanks)

-- ------------------------------------------------------------------ scaling by head count
local expectedFigh = { 3, 4, 4, 5 }
local expectedTanks = { 2, 3, 3, 4 }
local expectedRockets = { 4, 5, 5, 6 }
for n = 1, 4 do
    local w2, q, m2 = setup(n)
    F.run(110)
    check(#builtAt(q[1], "spawn4", "bvraz") == expectedFigh[n], n .. " human(s): fighters at spawn4 = " .. expectedFigh[n])
    check(#builtAt(q[1], "sbridge", "bvtank") == expectedTanks[n], n .. " human(s): bridge tanks = " .. expectedTanks[n])
    -- counterattack on the third hauler's deadline
    toConvoy(3)
    -- the live cap is tested separately: clear the field so each event is measured on its own
    for _, o in pairs(F.world().objects) do if o.team == 5 and o.craft and o.alive then o.alive = false end end
    F.run(1)
    F.nearTo(q[1].player, "sbridge", 100, 0); F.run(3)
    check(m2.north_bridge, "approach starts the north force")
    local north = builtAt(q[1], "spawn3", "bvltnk")
    check(#north == 1 + expectedExtras(n), "north force: light tank + extras, got " .. #north)
    for _, odf in ipairs({"bvturr", "bvscav", "bvrecy"}) do check(#builtAt(q[1], "spawn3", odf) == 1, "one " .. odf .. " at spawn3") end
    check(#builtAt(q[1], "spawn3", "bvtank") == 1, "restored north tank")
    for _, o in pairs(F.world().objects) do if o.team == 5 and o.craft and o.alive then o.alive = false end end
    F.run(1)
    F.nearTo(haulers(q[1])[3].h, "warn1", 50, 0); F.run(3)
    local rockets = builtAt(q[1], "counter", "bvrckt")
    check(#rockets == expectedRockets[n], n .. " human(s): counter rockets = " .. expectedRockets[n] .. ", got " .. #rockets)
    allSafe(q, rockets)
    local routed = 0
    for _, c in ipairs(F.callsOf(q[1], "Goto")) do if c[3] == "sbridge" then routed = routed + 1 end end
    check(routed == expectedRockets[n], "rocket extras mirror the Goto sbridge order (" .. routed .. ")")
    check(type(m2.counter1) == "string" and m2.counter, "counter tickets resolve")
    if n == 1 then check(not q[1].net, "one peer is offline") end
end

-- ------------------------------------------------------------------ nothing within 460 m: deferral, fallback, saves
do
    local w2, q, m2 = setup(4)
    -- a human sits at the north force's entrance; another is at the bridge
    F.nearTo(q[2].player, "spawn3", 100, 0)
    F.nearTo(q[1].player, "sbridge", 150, 0)
    F.run(2)
    check(m2.north_bridge, "any human near the bridge starts the north force")
    local north = {}
    for _, b in ipairs(F.builds(q[1])) do
        if b.odf == "bvltnk" or b.odf == "bvturr" or b.odf == "bvscav" or b.odf == "bvrecy" then north[#north + 1] = b end
    end
    check(#builtAt(q[1], "spawn3", "bvltnk") == 0, "a watched spawn3 never pops units in beside a human")
    allSafe(q, north)
    check(#builtAt(q[1], "spawn4", "bvltnk") >= 2 and #builtAt(q[1], "spawn4", "bvrecy") == 1, "they fall back to another authored approach")
    -- save/load keeps what is pending
    F.nearTo(q[3].player, "spawn4", 100, 0)
    F.nearTo(q[4].player, "counter", 100, 0)
    F.run(1)
    local before = #F.builds(q[1])
    toConvoy(1)
    F.nearTo(haulers(q[1])[1].h, "warn1", 10, 0)
    F.run(4)
    for _, r in ipairs(q) do r.env.Load(r.env.Save()) end
    F.connect(); F.run(3)
    check(#F.builds(q[1]) >= before, "a load never repeats the first frame")
    check(F.count(q[1], "SetPilot") == 5 and F.count(q[1], "AddScrap") == 1, "load does not rerun the opening grants")
end
-- watched everywhere: the rockets wait as saved tickets, built once when a way opens
do
    local w2, q, m2 = setup(4)
    toConvoy(3)
    for _, o in pairs(F.world().objects) do if o.team == 5 and o.craft and o.alive then o.alive = false end end
    F.run(1)
    F.nearTo(q[1].player, "counter", 50, 0)
    F.nearTo(q[2].player, "spawn3", 50, 0)
    F.nearTo(q[3].player, "spawn4", 50, 0)
    F.nearTo(haulers(q[1])[3].h, "warn1", 10, 0)
    F.run(4)
    check(m2.counter and type(m2.counter1) == "number" and m2.counter1 < 0, "the body holds tickets while every entrance is watched")
    check(#builtAt(q[1], "counter", "bvrckt") == 0 and #builtAt(q[1], "spawn3", "bvrckt") == 0, "no rocket is built beside a human")
    local pending = m2.crcca.serial
    for _, r in ipairs(q) do r.env.Load(r.env.Save()) end
    F.connect(); F.run(3)
    check(m2.crcca.serial == pending and #builtAt(q[1], "counter", "bvrckt") == 0, "save/load keeps the pending wave without duplicating it")
    for i = 1, 3 do F.place(q[i].player, 20 * i, 40) end
    F.run(6)
    local total = 0
    for _, where in ipairs({"counter", "spawn3", "spawn4"}) do total = total + #builtAt(q[1], where, "bvrckt") end
    check(total == 6, "the whole wave is built exactly once, got " .. total)
    check(type(m2.counter1) == "string", "tickets resolve to real units")
end
-- live cap: extras are the only requests dropped
do
    local w2, q, m2 = setup(4)
    m2.crcca.live = {}
    for i = 1, 12 do m2.crcca.live[i] = F.spawn("avtank", 5, 9000 + i, 9000) end
    F.run(40)
    check(#builtAt(q[1], "spawn4", "bvraz") == 3, "at the live cap the raiders keep their primaries and drop the extras: " .. #builtAt(q[1], "spawn4", "bvraz"))
end

-- ------------------------------------------------------------------ the convoy: shared orders and markers
w, p, m = setup(4)
F.run(421)
local hs = haulers(p[1])
check(#hs == 1 and m.first and m.convoy_count == 1, "first transport at 420 s")
check(F.count(p[1], "Goto") >= 1, "the leader orders the hauler down the escort path")
heardAll(p, "misns402.wav")
for i = 1, 4 do
    check(F.count(p[i], "StopCockpitTimer") == 1 and F.count(p[i], "HideCockpitTimer") >= 1, "the countdown stops on peer " .. i)
    check(F.count(p[i], "SetObjectiveOn") >= 1, "the transport marker reaches peer " .. i)
    check(F.count(p[i], "StartCockpitTimer") == 1, "the countdown showed once")
end
local escortOrders = 0
for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[3] == "escort" then escortOrders = escortOrders + 1 end end
check(escortOrders == 1, "exactly one escort order per hauler despite per-peer AddObject callbacks")
F.run(45 * 4 + 1)
hs = haulers(p[1])
check(#hs == 5 and m.convoy_count == 5, "five transports, 45 s apart")
escortOrders = 0
for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[3] == "escort" then escortOrders = escortOrders + 1 end end
check(escortOrders == 5, "five escort orders")
F.run(60)
check(#haulers(p[1]) == 5, "no sixth transport")
guestsPassive(p)

-- warning: any human near warn1
w, p, m = setup(4)
F.nearTo(p[3].player, "warn1", 100, 0); F.run(2)
check(m.warning, "any human within 200 m of warn1 triggers the warning")
heardAll(p, "misns409.wav")

-- bridge guard destroyed after the approach: line + AIP on team 5 + counter timer
w, p, m = setup(4)
F.run(110)
F.nearTo(p[2].player, "sbridge", 80, 0); F.run(3)
check(m.north_bridge, "approach")
F.kill(m.t1); F.kill(m.t2); F.kill(m.b1); F.run(2)
check(m.bridge_clear, "bridge clear")
heardAll(p, "misns405.wav")
heardAll(p, "misns408.wav") -- restored unused line: the convoy nears the bridge, once
check(F.count(p[1], "SetAIP", "crns4.aip") == 1 and F.count(p[1], "SetAIP", "misns4.aip") == 0 and F.last(p[1], "SetAIP")[3] == 5, "crns4.aip (the avturr plan) is handed to team 5")
check(F.count(p[2], "SetAIP") == 0, "guests never set the AIP")
check(math.abs(m.counter_time - (F.world().now + 150) ) < 2, "counterattack in 150 s")
F.run(10)
heardAll(p, "misns408.wav") -- still once

-- counterattack by deadline needs the third hauler alive
w, p, m = setup(2)
F.run(110)
F.nearTo(p[1].player, "sbridge", 80, 0); F.run(3)
F.kill(m.t1); F.kill(m.t2); F.kill(m.b1); F.run(2)
F.run(300)
check(not m.counter and m.counter_time < 300, "the deadline has passed but no third hauler exists yet")
F.run(520 - F.world().now)
check(m.counter, "the third transport meets the passed deadline: the counterattack comes")
w, p, m = setup(2)
toConvoy(3)
F.kill(haulers(p[1])[3].h); F.run(1)
F.nearTo(haulers(p[1])[1].h, "warn1", 50, 0); F.nearTo(haulers(p[1])[2].h, "warn1", 50, 0); F.run(60)
check(not m.counter, "a dead third hauler disables the counterattack (faithful)")

-- ------------------------------------------------------------------ results
w, p, m = setup(4)
toConvoy(5)
hs = haulers(p[1])
F.kill(hs[1].h); F.run(1)
heardAll(p, "misns403.wav")
heardAll(p, "misns406.wav") -- restored unused line: first convoy loss, once
check(F.count(p[1], "FailMission") == 0, "one loss does not fail")
F.kill(hs[2].h); F.run(1)
for i = 1, 4 do heardAll({p[i]}, "misns403.wav", 2) end
heardAll(p, "misns406.wav") -- still once
F.run(25)
for i = 1, 4 do
    check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "misns4l1.des", "one shared defeat on peer " .. i)
    check((p[i].env.Save().coopUnresolved or 0) == 0, "no unresolved presentation identities on peer " .. i)
end
F.kill(hs[3].h); F.run(30)
check(F.count(p[1], "FailMission") == 1, "later casualties never reschedule the defeat")
guestsPassive(p)

w, p, m = setup(4)
toConvoy(5)
hs = haulers(p[1])
arrive(hs[1].h); F.run(1)
heardAll(p, "misns404.wav") -- restored unused line: first hauler home, once
arrive(hs[2].h); arrive(hs[3].h)
F.run(1)
heardAll(p, "misns404.wav")
check(F.count(p[1], "SucceedMission") == 0, "three arrivals are not enough")
F.world().audioBusy = true -- a line is still playing: the win line queues behind it
arrive(hs[4].h); F.run(15)
F.world().audioBusy = false
heardAll(p, "misns407.wav") -- restored unused line: the win, once
heardAll(p, "misns404.wav")
check(F.count(p[1], "Queue", "misns407.wav") == 1, "the win line queues behind a line still playing")
for i = 1, 4 do
    check(F.count(p[i], "SucceedMission") == 1 and F.count(p[i], "FailMission") == 0, "one shared victory on peer " .. i)
    check(F.last(p[i], "SucceedMission")[3] == "misns4w1.des", "victory debrief on peer " .. i)
end
F.kill(hs[1].h); F.kill(hs[2].h); F.run(30)
check(F.count(p[1], "FailMission") == 0, "a won mission is never failed afterwards")
guestsPassive(p)
-- four and five arrive together
w, p, m = setup(2)
toConvoy(5)
hs = haulers(p[1])
for i = 1, 3 do arrive(hs[i].h) end
F.run(1)
arrive(hs[4].h); arrive(hs[5].h); F.run(15)
check(F.count(p[1], "SucceedMission") == 1, "simultaneous fourth and fifth arrival still wins")

-- leader leaves
w, p, m = setup(3)
for i = 2, 3 do p[i].env.DeletePlayer(1) end
F.run(3)
for i = 2, 3 do check(F.count(p[i], "FailMission") == 1, "the mission fails for guest " .. i .. " when the leader leaves") end
check(F.count(p[1], "FailMission") == 0, "the leader itself keeps playing")

-- ------------------------------------------------------------------ save/load mid-mission
w, p, m = setup(4)
toConvoy(2)
local buildsBefore = F.count(p[1], "BuildObject")
local convoyBefore = m.convoy_count
for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
F.connect(); F.run(5)
m = p[1].env.Save()
check(m.convoy_count == convoyBefore and F.count(p[1], "AddScrap") == 1, "load keeps the convoy and never reruns the opening")
check(F.count(p[1], "BuildObject") >= buildsBefore, "builds continue")
F.run(45 * 4)
check(m.convoy_count == 5, "the loaded convoy completes: " .. m.convoy_count)

-- ------------------------------------------------------------------ a map without the spawn3 path skips the restored tank
-- (the RESTORED_* flags are chunk locals, so only the missing-path guard is exercised here)
do
    local w2, q, m2 = setup(2, { setup = function(world) world.missingPaths = { spawn3 = true } end })
    F.run(110)
    F.nearTo(q[1].player, "sbridge", 100, 0); F.run(3)
    check(#builtAt(q[1], "spawn3", "bvtank") == 0, "a map without the path skips the restored tank")
end

-- ------------------------------------------------------------------ weather: absent, present, broken
do
    w, p, m = setup(3)
    check(F.count(p[1], "EnvironmentInit") == 0 and m.start_done, "no weather module: the mission runs and touches no Environment")
    local printed = false
    for _, c in ipairs(p[1].calls) do if c[1] == "print" and tostring(c[2]):find("weather disabled", 1, true) then printed = true end end
    check(printed, "missing weather is logged, not fatal")
end
local function io(record, mode)
    return function(peer)
        local V = { Seed = 4242 }
        function V.Init(o) peer.ioInit = o; record("IoInit", o.authority, o.send ~= nil, o.seed); if mode == "initfail" then error("boom") end end
        function V.Update(dt)
            if peer.ioInit and peer.ioInit.authority and peer.ioInit.send and not V.sent then
                V.sent = true; peer.ioInit.send("IoQuake", 3, 0.5, 4, 1)
            end
            if mode == "updatefail" then error("update boom") end
        end
        function V.AnnounceState() record("IoAnnounce") end
        function V.ApplyNetEvent(op, ...) record("IoEvent", op, ...) end
        function V.SetTargetLevel(n) record("IoLevel", n) end
        function V.ForceLevel(n, s, t) record("IoForce", n, s, t) end
        function V.Quake(s, d) record("IoQuakeCall", s, d); return true end
        function V.TriggerEruption(i, power) record("IoEruptCall", i, power); return true end
        function V.GetVentSites() return { {}, {}, {} } end
        function V.OnObjectCreated(h) record("IoCreated", h) end
        function V.Save() return { saved = true } end
        function V.Load(s) record("IoLoad", s and s.saved) end
        function V.Shutdown() record("IoShutdown") end
        return V
    end
end
do
    local weather = { module = function(peer, record) return io(record)(peer) end, sites = { bounds = {} } }
    w, p, m = setup(3, { weather = weather })
    check(F.count(p[1], "IoInit", true) == 1 and F.last(p[1], "IoInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.count(p[2], "IoInit", false) == 1, "guests render only (not the authority)")
    check(F.count(p[1], "IoAnnounce") == 1 and F.count(p[2], "IoAnnounce") == 0, "the leader announces its weather state once")
    check(F.count(p[1], "EnvironmentInit") == 1 and F.last(p[1], "EnvironmentInit")[2].lightingMode == "orbit", "Io lighting is initialised")
    for i = 1, 3 do
        local sensors = F.callsOf(p[i], "WeatherSensors")
        check(#sensors == 1 and sensors[1][2] == "Io", "the Io sensors are bound once on peer " .. i)
    end
    for i = 2, 3 do
        local e = F.last(p[i], "IoEvent")
        check(e and e[2] == "IoQuake" and e[3] == 3, "weather events reach guest " .. i)
    end
    check(F.count(p[1], "IoEvent") == 0, "the leader's director applied its own event")
    check(p[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    check(F.count(p[1], "IoLevel") == 0, "calm until the convoy rolls")
    F.run(420)
    check(F.count(p[1], "IoLevel", 2) == 1, "the first transport restlessly raises the weather")
    F.nearTo(p[2].player, "sbridge", 100, 0); F.run(3)
    check(F.count(p[1], "IoLevel", 3) == 1, "the bridge approach raises it again")
    F.kill(m.t1); F.kill(m.t2); F.kill(m.b1); F.run(2)
    check(F.count(p[1], "IoQuakeCall") == 1, "the cleared bridge shakes the view once")
    F.nearTo(haulers(p[1])[1].h, "warn1", 10, 0)
    F.run(44)
    toConvoy(3)
    F.nearTo(haulers(p[1])[3].h, "warn1", 10, 0); F.run(3)
    check(m.counter and F.count(p[1], "IoLevel", 4) == 1 and F.count(p[1], "IoQuakeCall") == 2 and F.count(p[1], "IoEruptCall") == 1,
        "the counterattack is intense: level, quake and an eruption")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "IoShutdown") >= 1 and F.count(p[1], "IoLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(p[1], "IoInit") == 2, "the weather re-initialises after a load")
    check(#F.callsOf(p[1], "WeatherSensors") == 2, "the sensors are rebound after a load")
    check(F.count(p[1], "IoLevel", 2) == 1, "saved beats are not replayed after a load")
    F.kill(haulers(p[1])[1].h); F.run(1)
    check(F.count(p[1], "IoEruptCall") == 2, "a lost transport makes a vent erupt")
    F.kill(haulers(p[1])[2].h); F.run(2)
    check(m.lost and F.count(p[1], "IoForce", 5) == 1, "defeat is paroxysm")
    check(F.count(p[2], "IoLevel") == 0 and F.count(p[2], "IoEruptCall") == 0, "only the leader decides the weather beats")
end
do -- victory eases the sky
    local weather = { module = function(peer, record) return io(record)(peer) end, sites = { bounds = {} } }
    w, p, m = setup(2, { weather = weather })
    toConvoy(5)
    hs = haulers(p[1])
    for i = 1, 4 do arrive(hs[i].h) end
    F.run(15)
    check(F.count(p[1], "IoLevel", 2) == 2, "a win eases the weather back to restless")
end
do -- sites module missing: no weather, never an error
    w, p, m = setup(2, { weather = { module = function(peer, record) return io(record)(peer) end } })
    check(F.count(p[1], "IoInit") == 0 and m.start_done, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    w, p, m = setup(2, { weather = { module = function(peer, record) return io(record, mode)(peer) end, sites = {} } })
    toConvoy(5)
    hs = haulers(p[1])
    for i = 1, 4 do arrive(hs[i].h) end
    F.run(15)
    check(F.count(p[1], "SucceedMission") == 1 and F.count(p[2], "SucceedMission") == 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("misns4 co-op: " .. checks .. " checks passed")
