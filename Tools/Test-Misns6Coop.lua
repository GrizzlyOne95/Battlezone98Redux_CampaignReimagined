-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/misns6cr.lua. Engine AI, rendering and combat remain mocked. Run from the repository root:
--   lua5.1 Tools/Test-Misns6Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Misns6Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local GOAL, RECY, SILO = "abcafe8_i76building", "svrecy0_recycler", "absilo0_scrapsilo"
local ART1, ART2 = "avartl3_howitzer", "avartl4_howitzer"

local function setup(n, options)
    options = options or {}
    local w = F.reset()
    if options.setup then options.setup(w) end
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
local function scrub(p)
    for _, q in ipairs(p) do F.place(q.player, 2438 + 20 * q.id, 98560) end
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
        for _, name in ipairs({"BuildObject", "SetScrap", "SetAIP", "Goto", "Attack", "Defend", "Mine", "RemoveObject"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function miners(peer)
    local out = {}
    for _, b in ipairs(F.builds(peer, 0, "bvmine")) do out[#out + 1] = b.h end
    return out
end
local function countGoto(peer, path)
    local n = 0
    for _, c in ipairs(F.callsOf(peer, "Goto")) do if c[3] == path then n = n + 1 end end
    return n
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
    win = function() F.run(12); F.kill(GOAL); F.run(8) end,
    recycler = function() F.run(12); F.kill(RECY); F.run(8) end,
}
for name, scenario in pairs(scenarios) do
    local faithful = outcomes({ faithful = true, script = "Scripts/misns6.lua" }, scenario)
    local offline = outcomes({}, scenario)
    check(faithful == offline and faithful ~= "", "offline completes like the faithful port (" .. name .. "): " .. faithful .. " / " .. offline)
end
do
    local out, peer = outcomes({}, scenarios.win)
    check(out == "SucceedMission:misns6w1.des", "offline victory: " .. out)
    local lost = outcomes({}, scenarios.recycler)
    check(lost == "FailMission:misns6l1.des", "offline loss: " .. lost)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is left on the authored enemy team 2") end
    check(F.count(peer, "SetAIControl", 5) == 1 and F.count(peer, "SetAIControl", 2) == 0, "AI control only for team 5")
end

-- ------------------------------------------------------------------ opening, ownership, teams
local w, p, m = setup(4)
check(m.start_done and m.coopMissionStarted, "leader starts the shared mission")
check(F.index(p[1], "SetAIControl") <= p[1].chunkCalls, "SetAIControl runs at chunk root, before Start")
do
    local scraps = {}
    for _, c in ipairs(F.callsOf(p[1], "SetScrap")) do scraps[c[2] .. ":" .. c[3]] = true end
    check(scraps["1:50"] and not scraps["2:50"], "shared scrap 20 + 10 per guest on team 1")
end
local layers = miners(p[1])
check(#layers == 3, "three mine layers are built")
for _, b in ipairs(F.builds(p[1], 0, "bvmine")) do check(b.team == 5, "mine layers are on team 5, not 2") end
check(m.miners[1] and m.miners[2] and m.miners[3], "three miner handles registered")
check(m.miners[1] ~= m.miners[2] and m.miners[1] ~= m.miners[3] and m.miners[2] ~= m.miners[3], "the three miner handles are distinct")
for _, h in ipairs(layers) do
    check(m.miners[1] == h or m.miners[2] == h or m.miners[3] == h, "layer registered via the team-2 filter: " .. tostring(h))
end
check(countGoto(p[1], "s1") + countGoto(p[1], "s2") + countGoto(p[1], "s3") >= 3, "layers are sent to their sowing paths")
for i = 1, 4 do
    check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
    check(F.heardCount(p[i], "misns601.wav") == 1, "briefing once on peer " .. i)
    local adds = F.callsOf(p[i], "AddObjective")
    check(adds[1][2] == "misns601.otf" and adds[2][2] == "misns602.otf", "objective list on peer " .. i)
end
check(F.count(p[1], "Defend") >= 6, "the enemy guns are told to defend")
guestsPassive(p)
-- AIP after 120 s goes to team 5, once
F.run(121)
check(F.count(p[1], "SetAIP", "crns6.aip") == 1 and F.count(p[1], "SetAIP", "misns6.aip") == 0 and F.last(p[1], "SetAIP")[3] == 5, "crns6.aip (avturr plan) is handed to team 5 once")

-- ------------------------------------------------------------------ mine laying (host only)
do
    local w2, q, m2 = setup(2)
    F.run(12)
    local ms = miners(q[1])
    check(F.count(q[1], "Mine") == 0, "layers keep going to their paths first")
    for _, h in ipairs(ms) do w2.objects[h].command = 0 end
    F.run(4)
    check(F.count(q[1], "Mine") >= 3, "an idle layer is told to lay mines")
    guestsPassive(q)
end

-- ------------------------------------------------------------------ humans as one trigger
do
    local w2, q, m2 = setup(4)
    F.nearTo(q[4].player, "m2", 100, 0); F.run(3)
    check(m2.warning, "any human near the minefield trips the warning")
    heardAll(q, "misns602.wav")
    F.nearTo(q[2].player, "m1", 50, 0); F.run(3)
    heardAll(q, "misns602.wav")
    guestsPassive(q)
    -- the nearest human wins, however far the others are
    F.place(q[4].player, 90000, 90000)
    F.nearTo(q[3].player, ART1, 150, 0)
    F.run(3)
    check(m2.art_found, "a human within 200 m of a howitzer finds the artillery")
    heardAll(q, "misns605.wav")
    -- restored unused line misns606: only once BOTH howitzers are gone, then exactly once
    heardAll(q, "misns606.wav", 0)
    F.kill(ART1); F.run(2)
    heardAll(q, "misns606.wav", 0)
    F.kill(ART2); F.run(2)
    heardAll(q, "misns606.wav")
    F.run(10)
    heardAll(q, "misns606.wav")
end

-- ------------------------------------------------------------------ restored lines misns607 / misns610 / misns813
do
    local w2, q, m2 = setup(3)
    heardAll(q, "misns607.wav", 0)
    F.place(q[2].player, 2492, 101645 - 700); F.run(2)
    heardAll(q, "misns607.wav", 0)
    F.place(q[2].player, 2492, 101645 - 450); F.run(2)
    check(not m2.last_objective, "607 fires before the last-objective trigger")
    heardAll(q, "misns607.wav")
    heardAll(q, "misns612.wav", 0)
    F.place(q[2].player, 2492, 101645 - 100); F.run(5)
    heardAll(q, "misns607.wav")
    check(m2.last_objective, "the last-objective trigger fired")
    heardAll(q, "misns612.wav")
    F.run(5)
    heardAll(q, "misns612.wav")
    -- recycler under heavy attack: 610 once, 813 ten seconds later
    heardAll(q, "misns610.wav", 0)
    F.setHealth("svrecy0_recycler", 0.6); F.run(2)
    heardAll(q, "misns610.wav", 0)
    F.setHealth("svrecy0_recycler", 0.4); F.run(2)
    heardAll(q, "misns610.wav")
    heardAll(q, "misns813.wav", 0)
    F.run(10)
    heardAll(q, "misns813.wav")
    F.setHealth("svrecy0_recycler", 0.3); F.run(15)
    heardAll(q, "misns610.wav"); heardAll(q, "misns813.wav")
    guestsPassive(q)
end
-- 813 is dropped when the recycler dies inside the 10 s gap
do
    local w2, q, m2 = setup(2)
    F.setHealth("svrecy0_recycler", 0.2); F.run(2)
    heardAll(q, "misns610.wav")
    F.kill("svrecy0_recycler"); F.run(15)
    heardAll(q, "misns813.wav", 0)
end

-- ------------------------------------------------------------------ the miner raid (counter1): scaled by head count
local expectedRaid = { 2, 3, 3, 4 }
for n, expect in ipairs(expectedRaid) do
    local w2, q, m2 = setup(n)
    F.run(12)
    local ms = miners(q[1])
    F.shoot(ms[1]); F.run(8)
    check(m2.counter1, "a shot mine layer starts the raid (" .. n .. " human(s))")
    local raid = builtAt(q[1], "counter1")
    for _, b in ipairs(builtAt(q[1], "counter2")) do raid[#raid + 1] = b end
    check(#raid == expect, n .. " human(s): " .. expect .. " raiders, got " .. #raid)
    allSafe(q, raid)
    local hunts = 0
    for _, c in ipairs(F.callsOf(q[1], "Attack")) do
        if w2.objects[c[2]] and w2.objects[c[2]].odf == "bvraz" then
            hunts = hunts + 1
            check(w2.objects[c[3]] and w2.objects[c[3]].team >= 1 and w2.objects[c[3]].team <= 4, "raiders hunt a real human ship")
        end
    end
    check(hunts == expect, "every raider has its hunt order (" .. hunts .. ")")
    for _, b in ipairs(raid) do check(b.team == 5 and b.odf == "bvraz", "raiders are team-5 bvraz") end
    F.shoot(ms[2]); F.run(5)
    check(#builtAt(q[1], "counter1") + #builtAt(q[1], "counter2") == expect, "the raid happens once")
    guestsPassive(q)
end
-- the raid waits for / falls back from a watched entry
do
    local w2, q, m2 = setup(2)
    F.run(12)
    F.nearTo(q[2].player, "counter1", 100, 0)
    F.shoot(miners(q[1])[1]); F.run(8)
    check(#builtAt(q[1], "counter1") == 0 and #builtAt(q[1], "counter3") >= 1, "a watched counter1 falls back to another authored approach")
    allSafe(q, F.builds(q[1], 0, "bvraz"))
end

-- ------------------------------------------------------------------ the silo counter-attack
local expectedAssault = { 5, 6, 6, 7 }
for n, expect in ipairs(expectedAssault) do
    local w2, q, m2 = setup(n)
    F.nearTo(q[n].player, SILO, 0, -300); F.run(8)
    check(m2.counter_attack, "approaching the far silo starts the counter-attack (" .. n .. ")")
    local wave = builtAt(q[1], "counter_attack")
    check(#wave == expect, n .. " human(s): " .. expect .. " attackers, got " .. #wave)
    allSafe(q, wave)
    for _, b in ipairs(wave) do check(b.team == 5, "attackers are team 5") end
    check(countGoto(q[1], "counter_attack_path") == expect, "every attacker marches the authored path (extras mirror the route)")
    heardAll(q, "misns603.wav")
    guestsPassive(q)
end
do -- a watched counter_attack point defers to another authored approach
    local w2, q, m2 = setup(3)
    F.nearTo(q[2].player, "counter_attack", 0, -100)
    F.nearTo(q[3].player, SILO, 0, -300); F.run(8)
    check(#builtAt(q[1], "counter_attack") == 0 and #builtAt(q[1], "counter3") + #builtAt(q[1], "counter4") >= 1, "watched counter_attack falls back")
    heardAll(q, "misns603.wav")
end
-- live cap: extras are the only requests dropped
do
    local w2, q, m2 = setup(4)
    m2.crcca.live = {}
    for i = 1, 12 do m2.crcca.live[i] = F.spawn("bvtank", 5, 9000 + i, 9000) end
    F.nearTo(q[4].player, SILO, 0, -300); F.run(8)
    check(#builtAt(q[1], "counter_attack") == 5, "at the live cap the wave keeps its primaries: " .. #builtAt(q[1], "counter_attack"))
end

-- ------------------------------------------------------------------ last objective, shared audio, results
w, p, m = setup(4)
F.nearTo(p[2].player, GOAL, 0, -250); F.run(3)
check(m.last_objective, "a human near the command centre makes it the objective")
for i = 1, 4 do
    check(F.count(p[i], "SetObjectiveOn", GOAL) == 1, "the goal is marked on peer " .. i)
    local adds = F.callsOf(p[i], "AddObjective")
    check(adds[#adds - 1][2] == "misns601.otf" and adds[#adds - 1][3] == "green", "green main objective on peer " .. i)
end
F.kill(GOAL); F.run(1)
check(m.won and m.won_message, "destroying the command centre wins")
w.audioBusy = true; F.run(2)
check(F.count(p[1], "SucceedMission") == 0, "success waits for the victory line")
w.audioBusy = false; F.run(8)
heardAll(p, "misns609.wav")
for i = 1, 4 do
    check(F.count(p[i], "SucceedMission") == 1 and F.count(p[i], "FailMission") == 0, "one shared victory on peer " .. i)
    check(F.last(p[i], "SucceedMission")[3] == "misns6w1.des", "victory debrief on peer " .. i)
    check(p[i].env.Save().coopUnresolved == 0, "no unresolved presentation identities on peer " .. i)
end
F.run(20)
heardAll(p, "misns609.wav") -- stock bug fixed in the body: the victory line is not replayed
guestsPassive(p)
-- a recycler lost in the victory frame does not fail a won mission
w, p, m = setup(2)
F.kill(GOAL); F.kill(RECY); F.run(8)
check(F.count(p[1], "SucceedMission") == 1 and F.count(p[1], "FailMission") == 0, "victory takes precedence over a simultaneous recycler loss")
-- recycler loss
w, p, m = setup(3)
local killedAt = w.now
F.kill(RECY); F.run(6)
heardAll(p, "misns611.wav")
local failAt = F.last(p[1], "FailMission")[2]
check(failAt - killedAt >= 11.0 and failAt - killedAt < 13.0, "the fail delay lets misns611 finish: " .. tostring(failAt - killedAt))
for i = 1, 3 do
    check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "misns6l1.des", "one shared recycler-loss failure on peer " .. i)
    check(F.count(p[i], "SucceedMission") == 0, "no victory after the loss on peer " .. i)
end
F.kill(GOAL); F.run(8)
check(F.count(p[1], "SucceedMission") == 0, "a decided loss is final")

-- ------------------------------------------------------------------ leader leaves
w, p, m = setup(3)
for i = 2, 3 do p[i].env.DeletePlayer(1) end
F.run(3)
for i = 2, 3 do check(F.count(p[i], "FailMission") == 1, "the mission fails for guest " .. i .. " when the leader leaves") end
check(F.count(p[1], "FailMission") == 0, "the leader itself keeps playing")

-- ------------------------------------------------------------------ save/load mid-mission
w, p, m = setup(4)
F.run(20)
local aipBefore, builds, scraps = F.count(p[1], "SetAIP"), F.count(p[1], "BuildObject"), F.count(p[1], "SetScrap")
for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
F.connect(); F.run(5)
check(F.count(p[1], "SetScrap") == scraps and F.count(p[1], "BuildObject") == builds, "load does not rerun the first frame")
F.run(125)
check(F.count(p[1], "SetAIP") == aipBefore + 1, "the AIP timer survives the load")
F.kill(GOAL); F.run(8)
for i = 1, 4 do check(F.count(p[i], "SucceedMission") == 1, "the loaded mission still ends once on peer " .. i) end

-- ------------------------------------------------------------------ weather: absent, present, broken
do
    w, p, m = setup(3)
    check(F.count(p[1], "EnvironmentInit") == 0 and m.start_done, "no weather module: the mission runs and touches no Environment")
    local printed = false
    for _, c in ipairs(p[1].calls) do if c[1] == "print" and tostring(c[2]):find("weather disabled", 1, true) then printed = true end end
    check(printed, "missing weather is logged, not fatal")
end
local function titan(record, mode)
    return function(peer)
        local V = { Seed = 4242 }
        function V.Init(o) peer.titanInit = o; record("TitanInit", o.authority, o.send ~= nil, o.seed); if mode == "initfail" then error("boom") end end
        function V.Update(dt)
            if peer.titanInit and peer.titanInit.authority and peer.titanInit.send and not V.sent then
                V.sent = true; peer.titanInit.send("TitanState", 3, 4)
            end
            if mode == "updatefail" then error("update boom") end
        end
        function V.AnnounceState() record("TitanAnnounce") end
        function V.ApplyNetEvent(op, ...) record("TitanEvent", op, ...) end
        function V.SetTargetLevel(n) record("TitanLevel", n) end
        function V.OnObjectCreated(h) record("TitanCreated", h) end
        function V.Save() return { saved = true } end
        function V.Load(s) record("TitanLoad", s and s.saved) end
        function V.Shutdown() record("TitanShutdown") end
        return V
    end
end
do
    local weather = { module = function(peer, record) return titan(record)(peer) end, sites = { bounds = {} } }
    w, p, m = setup(3, { weather = weather })
    check(F.count(p[1], "TitanInit", true) == 1 and F.last(p[1], "TitanInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.count(p[2], "TitanInit", false) == 1, "guests render only (not the authority)")
    check(F.count(p[1], "TitanAnnounce") == 1 and F.count(p[2], "TitanAnnounce") == 0, "the leader announces its weather state once")
    check(F.count(p[1], "EnvironmentInit") == 1, "Titan lighting is initialised")
    for i = 2, 3 do
        local e = F.last(p[i], "TitanEvent")
        check(e and e[2] == "TitanState" and e[3] == 3 and e[4] == 4, "weather events reach guest " .. i)
    end
    check(p[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    check(F.count(p[1], "TitanLevel") == 0, "no beat before the story reaches it")
    F.nearTo(p[2].player, "m2", 100, 0); F.run(3)
    check(F.count(p[1], "TitanLevel", 3) == 1, "the minefield warning thickens the weather")
    F.nearTo(p[3].player, SILO, 0, -300); F.run(8)
    check(F.count(p[1], "TitanLevel", 4) == 1, "the counter-attack brings the shroud")
    F.kill(GOAL); F.run(2)
    check(F.count(p[1], "TitanLevel", 2) == 1, "victory eases the weather")
    check(F.count(p[1], "TitanLevel") == 3, "each beat fires exactly once")
    check(F.count(p[1], "TitanCreated") > 0, "new objects are offered to the weather")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "TitanShutdown") >= 1 and F.count(p[1], "TitanLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(p[1], "TitanInit") == 2, "the weather re-initialises after a load")
    check(F.count(p[1], "TitanLevel") == 3, "a load does not replay beats")
end
do -- sites module missing: no weather, never an error
    w, p, m = setup(2, { weather = { module = function(peer, record) return titan(record)(peer) end } })
    check(F.count(p[1], "TitanInit") == 0 and m.start_done, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    w, p, m = setup(2, { weather = { module = function(peer, record) return titan(record, mode)(peer) end, sites = {} } })
    F.run(5); F.kill(GOAL); F.run(8)
    check(F.count(p[1], "SucceedMission") == 1 and F.count(p[2], "SucceedMission") == 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("misns6 co-op: " .. checks .. " checks passed")
