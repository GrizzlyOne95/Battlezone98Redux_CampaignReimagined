-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/misns5cr.lua. Engine AI, rendering and combat remain mocked. Run from the repository root:
--   lua5.1 Tools/MissionTests/Test-Misns5Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/MissionTests/Misns5Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local RECY, MUF, DEPOT = "svrecy0_recycler", "svmuf0_factory", "sbhang0_repairdepot"
local PLANTS = { "sblpow2_powerplant", "sblpow3_powerplant", "sblpow4_powerplant" }

-- options.briefing: keep the opening audio busy (the cutscene runs until released)
local function setup(n, options)
    options = options or {}
    local w = F.reset()
    w.chaff = options.chaff or 0
    if options.briefing then w.audioBusy = true end
    if options.setup then options.setup(w) end
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
local function builtAt(peer, where, mark, odf)
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
        for _, name in ipairs({"BuildObject", "SetScrap", "AddScrap", "SetAIP", "SetPilot", "Goto", "Attack", "Defend2", "RemoveObject"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function untilMission(m, field, limit) F.runUntil(function() return m[field] end, limit or 800) end
-- Everything the enemy ever built stays off the DLL's team 2.
local function noTeam2(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is left on the authored enemy team 2: " .. tostring(b.odf)) end
end
-- The mock has no combat: thin the field so the live cap (12) never hides the scaling under test.
local function clearField()
    local w = F.world()
    for _, o in pairs(w.objects) do
        if o.team == 5 and (o.odf == "bvraz" or o.odf == "bvapc" or o.odf == "bvhraz" or o.odf == "bvltnk") then o.alive = false end
    end
end
-- Drives the mission to its final phase (commander dead, three waves) and returns the mission table.
local function toLastPhase(m)
    F.runUntil(function() return m.defender end, 60)
    F.kill(m.commander)
    F.runUntil(function() return m.last_phase end, 900)
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
    win = function(w, p, m) toLastPhase(m); F.kill(m.killme); F.run(12) end,
    recycler = function(w, p, m) F.run(3); F.kill(RECY); F.run(12) end,
}
for name, scenario in pairs(scenarios) do
    local faithful, fpeer = outcomes({ faithful = true, script = "Scripts/misns5.lua" }, scenario)
    local offline, peer = outcomes({}, scenario)
    check(faithful == offline and faithful ~= "", "offline completes like the faithful port (" .. name .. "): " .. faithful .. " / " .. offline)
    check(peer.camera == fpeer.camera, "offline camera stack matches the faithful port (" .. name .. ")")
end
do
    local out, peer = outcomes({}, scenarios.win)
    check(out == "SucceedMission:misns5w1.des", "offline victory: " .. out)
    check(F.count(peer, "SucceedMission") == 1, "one victory request")
    noTeam2(peer)
    local out2 = outcomes({}, scenarios.recycler)
    check(out2 == "FailMission:misns5l1.des", "offline recycler loss: " .. out2)
end
do -- offline: the same layer, skippable opening
    local w, p, m = setup(1, { briefing = true })
    check(p[1].camera == 1 and F.last(p[1], "CameraPath") ~= nil, "offline opening shot runs")
    w.cancel = true; F.run(1)
    check(p[1].camera == 0, "offline skip ends the opening shot")
    w.cancel = false; F.run(5)
    check(p[1].camera == 0 and F.count(p[1], "CameraReady") == 1, "a skipped opening never restarts")
end

-- ------------------------------------------------------------------ opening, ownership, teams
local w, p, m = setup(4, { briefing = true })
check(m.start_done and m.camera1 and m.coopMissionStarted, "leader starts the shared mission")
check(F.count(p[1], "SetAIControl", 5) == 1 and F.count(p[1], "SetAIControl", 2) == 0, "AI control only for enemy team 5, at chunk load")
check(F.index(p[1], "SetAIControl") <= p[1].chunkCalls, "SetAIControl runs at chunk root, before Start")
check(F.count(p[1], "AddScrap", 1) == 1 and F.last(p[1], "AddScrap")[3] == 40, "10 starting scrap + 10 per guest on the shared team: " .. tostring(F.last(p[1], "AddScrap") and F.last(p[1], "AddScrap")[3]))
check(F.count(p[1], "AddScrap", 2) == 0, "no scrap for the authored team 2")
local arty = F.builds(p[1], 0, "bvartl")
check(#arty == 2 and arty[1].team == 5 and arty[2].team == 5, "both artillery pieces are on team 5")
for i = 1, 4 do
    check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
    check(p[i].camera == 1 and F.last(p[i], "CameraPath") ~= nil and F.last(p[i], "CameraPath")[2] == "campath", "peer " .. i .. " follows the shared opening shot")
end
heardAll(p, "misns501.wav")
guestsPassive(p)
-- A skip is not available in a network game: the shared opening keeps running for everyone.
w.cancel = true; F.run(2)
check(m.camera1 and not m.third_message, "a skip never ends the shared opening in a network game")
check(p[1].camera == 0 and F.count(p[1], "CameraReady") == 1, "a skip releases only the skipping player's own camera; the mission keeps its opening")
w.cancel = false
w.audioBusy = false; F.run(3)
for i = 1, 4 do
    check(p[i].camera == 0, "opening cameras balanced on peer " .. i)
    check(F.callsOf(p[i], "AddObjective")[1][2] == "misns501.otf", "first objective on peer " .. i)
end
check(not m.camera1 and F.count(p[1], "Goto", RECY) >= 1 and F.count(p[1], "Goto", MUF) >= 1, "the base producers deploy to the geysers")
heardAll(p, "misns503.wav")
-- artillery orders go to the leader only; they follow the plants
do
    local a = F.callsOf(p[1], "Attack")
    check(#a == 2 and a[1][3] == PLANTS[1] and a[2][3] == PLANTS[2], "artillery attack the first two power plants")
    F.kill(PLANTS[1]); F.kill(PLANTS[2])
    F.runUntil(function() return m.defender end, 60); F.run(1)
    check(m.third_attack and m.fourth_attack, "artillery redirect after the plants fall")
    check(F.last(p[1], "Attack")[3] == DEPOT, "second artillery turns on the repair depot")
end
-- the commander: the stock team-2 filter would never see a team-5 walker
check(type(m.commander) == "string" and F.team(m.commander) == 5, "the first enemy walker is captured as the commander (team 5)")
check(F.last(p[1], "SetPilot")[2] == 5 and F.count(p[1], "SetPilot", 2) == 0, "the enemy pilot reserve is team 5")
heardAll(p, "misns504.wav", 0)
F.kill(m.a1); F.kill(m.a2); F.run(1)
heardAll(p, "misns504.wav")
guestsPassive(p)
noTeam2(p[1])

-- ------------------------------------------------------------------ chaff and the APC strike scale with head count
for n = 1, 4 do
    local extras = math.min(math.floor(n / 2), 2)
    local w2, q, m2 = setup(n, {})
    F.runUntil(function() return m2.h1 ~= nil and type(m2.h1) == "string" end, 200)
    F.run(2)
    local apcs = builtAt(q[1], "spawn6", 0, "bvapc")
    check(#apcs == 2 + extras, n .. " human(s): two APCs plus " .. extras .. " extras, got " .. #apcs)
    allSafe(q, apcs)
    for _, b in ipairs(apcs) do check(b.team == 5, "APCs are team 5") end
    local attacks = 0
    for _, c in ipairs(F.callsOf(q[1], "Attack")) do if c[3] == MUF then attacks = attacks + 1 end end
    check(attacks == 2 + extras, "extras mirror the attack on the factory (" .. attacks .. ")")
    check(type(m2.killme) == "string" and F.team(m2.killme) == 5 and F.alive(m2.killme), "the enemy recycler is a single real team-5 unit")
    check(#builtAt(q[1], "spawn7", 0, "bvtank") == 2 and #F.callsOf(q[1], "Defend2") == 2, "two recycler guards, never scaled")
    -- the first chaff fighters (180 s after the opening): one plus extras, same entry
    clearField() -- the early ladder fills the live cap; the mock has no combat to thin it
    F.runUntil(function() return F.count(q[1], "BuildObject") > 0 and #builtAt(q[1], "spawn5", 0, "bvraz") > 0 end, 400)
    F.run(2)
    local fighters = builtAt(q[1], "spawn5", 0, "bvraz")
    check(#fighters == 1 + extras, n .. " human(s): chaff fighters " .. #fighters)
    allSafe(q, fighters)
    local routed = 0
    for _, c in ipairs(F.callsOf(q[1], "Goto")) do if c[3] == RECY then routed = routed + 1 end end
    check(routed >= 1 + extras, "chaff fighters route to the player recycler (AddObject maps team 5)")
    if n == 1 then check(not q[1].net, "one peer is offline") end
    if n > 1 then guestsPassive(q) end
    noTeam2(q[1])
end

-- ------------------------------------------------------------------ waves, final phase, victory
w, p, m = setup(4, {})
F.runUntil(function() return m.defender end, 60)
check(m.commander ~= nil and F.alive(m.commander), "the commander walker stands")
F.kill(m.commander)
F.runUntil(function() return m.com_dead end, 20)
local waveStart = w.now
F.runUntil(function() return m.wave_count == 1 end, 200)
F.run(3)
check(w.now - waveStart > 119.5, "the first wave comes 120 s after the commander falls")
do
    local razors = builtAt(p[1], "spawn6", 0, "bvhraz")
    check(#razors == 3 + 2, "wave one: three razors + floor(4/2) extras at spawn6, got " .. #razors)
    allSafe(p, razors)
    for _, b in ipairs(razors) do check(b.team == 5, "wave units are team 5") end
    local routed = 0
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[3] == RECY then routed = routed + 1 end end
    check(routed >= 5, "razors (extras included) route to the player recycler")
end
F.runUntil(function() return w.now >= m.wave - 1 end, 400); clearField()
F.runUntil(function() return m.wave_count == 2 end, 400); F.run(3)
do
    local tanks = builtAt(p[1], "spawn5", 0, "bvltnk")
    check(#tanks == 3 + 2, "wave two: three light tanks + extras at spawn5, got " .. #tanks)
    check(not m.last_phase, "two waves are not the last phase")
end
F.runUntil(function() return w.now >= m.wave - 1 end, 400); clearField()
F.runUntil(function() return m.last_phase end, 400); F.run(3)
check(#builtAt(p[1], "spawn5", 0, "bvltnk") == 10, "wave three adds three light tanks + extras, got " .. #builtAt(p[1], "spawn5", 0, "bvltnk"))
check(#builtAt(p[1], "spawn7", 0, "bvscav") == 2, "two enemy scavengers (never scaled)")
check(F.team(builtAt(p[1], "spawn7", 0, "bvscav")[1].h) == 5, "scavengers are team 5")
do
    local aip = F.callsOf(p[1], "SetAIP")
    check(#aip == 1 and aip[1][2] == "crns5.aip" and aip[1][3] == 5, "misns5.aip is replaced by the Black Dog crns5.aip for team 5, once")
end
local podBuilt = F.builds(p[1], 0, "spcamr")
check(#podBuilt == 1 and podBuilt[1].team == 1 and podBuilt[1].where == "camera1", "the intelligence pod is built for the humans")
for i = 1, 4 do
    local marks = F.callsOf(p[i], "SetObjectiveOn")
    check(#marks >= 2, "both the enemy recycler and the restored pod are marked on peer " .. i)
    local named = false
    for _, c in ipairs(F.callsOf(p[i], "SetObjectiveName")) do if c[3] == "Intelligence Camera" then named = true end end
    check(named, "the restored intelligence pod is named on peer " .. i)
    check(F.heard(p[i], "misns506.wav"), "intelligence briefing on peer " .. i)
    local final = false
    for _, c in ipairs(F.callsOf(p[i], "AddObjective")) do if c[2] == "misns502.otf" then final = true end end
    check(final, "final objective reaches peer " .. i)
end
guestsPassive(p)
noTeam2(p[1])
do -- the final win
    F.kill(m.killme); F.run(3)
    check(m.won and not m.lost, "destroying the enemy recycler wins")
    F.run(12)
    for i = 1, 4 do
        check(F.count(p[i], "SucceedMission") == 1 and F.count(p[i], "FailMission") == 0, "one shared victory on peer " .. i)
        check(F.last(p[i], "SucceedMission")[3] == "misns5w1.des", "victory debrief on peer " .. i)
        check(F.heard(p[i], "misns508.wav"), "victory line on peer " .. i)
        check((p[i].env.Save().coopUnresolved or 0) == 0, "no unresolved presentation identities on peer " .. i)
    end
    F.kill(RECY); F.run(12)
    check(F.count(p[1], "FailMission") == 0, "victory suppresses a later loss")
end

-- stock behaviour kept: the enemy recycler dying before the last phase wins only when the last phase opens
do
    local w2, q, m2 = setup(2, {})
    F.runUntil(function() return type(m2.killme) == "string" end, 200)
    F.kill(m2.killme); F.run(20)
    check(not m2.won and F.count(q[1], "SucceedMission") == 0, "no early victory before the final phase")
end

-- ------------------------------------------------------------------ losing
w, p, m = setup(3, {})
F.run(3); w.audioBusy = true; F.kill(RECY); F.run(2); w.audioBusy = false; F.run(12)
for i = 1, 3 do
    check(F.heardCount(p[i], "misns507.wav") == 1, "recycler-loss line on peer " .. i)
    check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "misns5l1.des", "one shared failure on peer " .. i)
end
check(m.lost and not m.won, "the loss latches")

-- ------------------------------------------------------------------ nothing within 460 m: deferral, fallback, saves
do
    local w2, q, m2 = setup(4, {})
    -- the APC strike's entrance is watched: spawn6 defers to the next authored approach (spawn5)
    F.nearTo(q[2].player, "spawn6", 100, 0)
    F.runUntil(function() return #F.builds(q[1], 0, "bvapc") > 0 end, 200)
    F.run(2)
    local apcs = F.builds(q[1], 0, "bvapc")
    check(#apcs == 4 and #builtAt(q[1], "spawn6", 0, "bvapc") == 0, "a watched spawn6 falls back to another authored approach")
    allSafe(q, apcs)
end
do
    local w2, q, m2 = setup(4, {})
    F.nearTo(q[1].player, "spawn6", 100, 0)
    F.nearTo(q[2].player, "spawn5", 100, 0)
    F.nearTo(q[3].player, "spawn7", 100, 0)
    F.nearTo(q[4].player, "edge_path", 100, 0)
    F.runUntil(function() return m2.apc_wave >= 99999 end, 200)
    F.run(2)
    check(#F.builds(q[1], 0, "bvapc") == 0, "every entrance watched: the strike waits")
    check(type(m2.h1) == "number" and m2.h1 < 0, "the body holds tickets while the strike waits")
    local pending = m2.crcca.serial
    for _, r in ipairs(q) do r.env.Load(r.env.Save()) end
    F.connect(); F.run(3)
    check(m2.crcca.serial == pending and #F.builds(q[1], 0, "bvapc") == 0, "save/load keeps the pending strike without duplicating it")
    for i, r in ipairs(q) do F.place(r.player, 20 * i, 40) end
    F.run(4)
    check(#F.builds(q[1], 0, "bvapc") == 4, "the whole strike is built exactly once, got " .. #F.builds(q[1], 0, "bvapc"))
    check(type(m2.h1) == "string", "tickets resolve to real units")
end
do -- live cap: extras are the only requests dropped
    local w2, q, m2 = setup(4, {})
    m2.crcca.live = {}
    for i = 1, 12 do m2.crcca.live[i] = F.spawn("avtank", 5, 9000 + i, 9000) end
    F.runUntil(function() return type(m2.h1) == "string" end, 200); F.run(2)
    check(#builtAt(q[1], "spawn6", 0, "bvapc") == 2, "at the live cap the strike keeps its primaries and drops the extras")
end

-- ------------------------------------------------------------------ saves
do
    local w2, q, m2 = setup(2, {})
    F.run(80)
    local ready, scrap, builds = F.count(q[1], "CameraReady"), F.count(q[1], "AddScrap"), F.count(q[1], "BuildObject")
    for _, r in ipairs(q) do r.env.Load(r.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(q[1], "CameraReady") == ready and F.count(q[1], "AddScrap") == scrap, "load does not replay the startup")
    check(F.count(q[1], "BuildObject") == builds, "load does not rebuild the artillery or the strike")
end

-- ------------------------------------------------------------------ leader leaves
w, p, m = setup(3, {})
for i = 2, 3 do p[i].env.DeletePlayer(1) end
F.run(3)
for i = 2, 3 do check(F.count(p[i], "FailMission") == 1, "the mission fails for guest " .. i .. " when the leader leaves") end
check(F.count(p[1], "FailMission") == 0, "the leader itself keeps playing")

-- ------------------------------------------------------------------ weather: absent, present, broken
do
    w, p, m = setup(3, {})
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
                V.sent = true; peer.titanInit.send("TitanRoll", 3, 4)
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
    F.run(2)
    check(F.count(p[1], "TitanAnnounce") == 1 and F.count(p[2], "TitanAnnounce") == 0, "the leader announces its weather state once")
    for i = 2, 3 do
        local e = F.last(p[i], "TitanEvent")
        check(e and e[2] == "TitanRoll" and e[3] == 3 and e[4] == 4, "weather events reach guest " .. i)
    end
    check(p[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    -- beats: hazy once the defenders are out, drizzle with the APC strike, shroud for the final phase, easing on the win
    F.runUntil(function() return m.defender end, 60); F.run(1)
    check(F.count(p[1], "TitanLevel", 2) == 1 and F.count(p[1], "TitanLevel", 3) == 0, "the defenders raise the weather to hazy")
    F.runUntil(function() return m.h1 ~= nil end, 200); F.run(1)
    check(F.count(p[1], "TitanLevel", 3) == 1, "the APC strike brings the drizzle")
    F.kill(m.commander)
    F.runUntil(function() return m.last_phase end, 900); F.run(1)
    check(F.count(p[1], "TitanLevel", 4) == 1, "the last phase brings the shroud")
    check(F.count(p[1], "TitanCreated") > 0, "new objects are offered to the weather")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "TitanShutdown") >= 1 and F.count(p[1], "TitanLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(p[1], "TitanInit") == 2, "the weather re-initialises after a load")
    check(F.count(p[1], "TitanLevel", 4) == 1, "a load does not replay a beat")
    F.kill(m.killme); F.run(3)
    check(F.count(p[1], "TitanLevel", 2) == 2, "victory eases the weather")
    F.run(12)
    for i = 1, 3 do check(F.count(p[i], "SucceedMission") == 1, "the victory still lands with weather on (peer " .. i .. ")") end
end
do -- sites module missing: no weather, never an error
    w, p, m = setup(2, { weather = { module = function(peer, record) return titan(record)(peer) end } })
    check(F.count(p[1], "TitanInit") == 0 and m.start_done, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    w, p, m = setup(2, { weather = { module = function(peer, record) return titan(record, mode)(peer) end, sites = {} } })
    F.run(3); F.kill(RECY); F.run(12)
    check(F.count(p[1], "FailMission") == 1 and F.count(p[2], "FailMission") == 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

-- ------------------------------------------------------------------ early ladder, patrols and sniper (CR early ladder)
do
    local w2, q, m2 = setup(1, {})
    local t0 = m2.cr_t0
    check(t0 ~= nil and m2.cr_step == 1, "the opening stamps the ladder clock once")
    for i = 1, 3 do
        local patrol = builtAt(q[1], "cr_patrol" .. i, 0, "bvtank")
        check(#patrol == 1 and patrol[1].team == 5, "one team-5 tank starts on cr_patrol" .. i)
        local ordered = 0
        for _, c in ipairs(F.callsOf(q[1], "Patrol")) do if c[3] == "cr_patrol" .. i then ordered = ordered + 1 end end
        check(ordered == 1, "that tank patrols cr_patrol" .. i)
        allSafe(q, patrol)
    end
    local sniper = builtAt(q[1], "cr_sniper", 0, "bsheav")
    check(#sniper == 1 and sniper[1].team == 5, "one team-5 sniper on cr_sniper")
    allSafe(q, sniper)
    local function count(where, odf) return #builtAt(q[1], where, 0, odf) end
    local function stepAt(step, at)
        F.runUntil(function() return m2.cr_step == step + 1 end, 1000); clearField()
        check(w2.now - t0 >= at and w2.now - t0 < at + 3, "ladder step " .. step .. " fires " .. at .. " s in, got " .. (w2.now - t0))
        F.run(2) -- the runtime builds the queued arrivals on the next frames
    end
    F.runUntil(function() return w2.now - t0 >= 100 end, 200)
    local apc0 = count("spawn6", "bvapc")
    check(apc0 == 2 and m2.cr_step == 1, "the stock APC strike came first; the ladder waits for 105 s")
    stepAt(1, 105)
    check(count("spawn6", "bvapc") == apc0 + 1, "the 105 s raid is one APC at spawn6")
    stepAt(2, 180)
    check(count("spawn5", "bvhraz") == 2, "bombers at 180 s: two")
    stepAt(3, 300)
    check(count("spawn6", "bvhraz") == 1, "one bomber at 300 s")
    local how = builtAt(q[1], "cr_howitzer", 0, "bvartl")
    check(#how == 1 and how[1].team == 5 and F.count(q[1], "Deploy") == 1, "a team-5 howitzer deploys at 300 s")
    local recyAttacks = 0
    for _, c in ipairs(F.callsOf(q[1], "Attack")) do if c[3] == RECY then recyAttacks = recyAttacks + 1 end end
    check(recyAttacks == 1, "the 300 s bomber attacks the player recycler")
    -- A save/load keeps the clock: no patrol is built again and the ladder carries on.
    for _, r in ipairs(q) do r.env.Load(r.env.Save()) end
    F.run(2)
    check(m2.cr_t0 == t0 and count("cr_patrol1", "bvtank") == 1 and count("cr_sniper", "bsheav") == 1, "load never replays the opening")
    stepAt(4, 600)
    stepAt(5, 900)
    check(count("spawn5", "bvhraz") == 4 and count("spawn6", "bvhraz") == 1 + 3, "bombers at 600 s (two) and 900 s (three)")
    F.run(60)
    check(m2.cr_step == 6 and count("cr_howitzer", "bvartl") == 1, "the ladder has five rungs")
    noTeam2(q[1])
end
do -- a guest never builds the ladder
    local w2, q, m2 = setup(2, {})
    F.run(200)
    check(m2.cr_step == 3, "the host runs the ladder")
    check(F.count(q[2], "Patrol") == 0 and F.count(q[2], "Deploy") == 0, "a guest never orders patrols or deploys")
    guestsPassive(q)
end
do -- the final phase stops the ladder
    local w2, q, m2 = setup(1, {})
    F.runUntil(function() return m2.cr_step == 2 end, 400)
    m2.last_phase = true
    F.run(900)
    check(m2.cr_step == 2 and #F.builds(q[1], 0, "bvhraz") == 0, "no rung fires once the final phase has begun")
end
do -- a lost mission stops it too
    local w2, q, m2 = setup(1, {})
    F.run(3); F.kill(RECY); F.run(12)
    F.run(300) -- stock waves may still arrive in the result delay; the ladder must not
    check(m2.lost and m2.cr_step == 1 and #F.builds(q[1], 0, "bvhraz") == 0, "no rung fires after the mission ends")
end

do -- combat-only aiCore: the host registers the enemy team, a guest does nothing, saves stay compatible
    local w2, q, m2 = setup(2, {})
    F.run(3)
    check(F.count(q[1], "EnableCombatOnly") == 1 and F.count(q[1], "BootstrapCombatOnly") == 1, "the host enables combat-only mode once")
    local enable = F.callsOf(q[1], "EnableCombatOnly")[1]
    check(enable[2] == 5 and enable[3] == 2, "combat-only covers the real enemy team 5 as CCA")
    check(F.count(q[1], "aiCoreUpdateCombatOnly") > 0 and F.count(q[1], "aiCoreUpdate") == 0
        and F.count(q[1], "aiCoreAddObject") == 0, "the host runs aiCore.UpdateCombatOnly, never Update or AddObject")
    local mark = #q[1].calls
    F.run(300)
    local added = 0
    for _, c in ipairs(F.callsOf(q[1], "AddCombatObject")) do
        added = added + 1
        check(w2.objects[c[2]].team == 5, "only enemy-team units reach AddCombatObject")
    end
    check(added > 0, "units built later reach AddCombatObject")
    check(F.count(q[1], "TrackWorldObject") >= added, "every new object (any team) is cached through TrackWorldObject")
    for _, name in ipairs({"EnableCombatOnly", "BootstrapCombatOnly", "AddCombatObject", "TrackWorldObject", "aiCoreUpdate", "aiCoreUpdateCombatOnly"}) do
        check(F.count(q[2], name) == 0, "a guest never runs aiCore: " .. name)
    end
    local state, aiData = q[1].env.Save()
    check(type(aiData) == "table" and aiData.marker == "aiCoreData", "Save returns the aiCore data as a trailing value")
    check(select("#", q[2].env.Save()) == 1, "a guest saves no aiCore data")
end
do -- save compatibility (offline: a co-op reload needs the session to re-form)
    local w2, q, m2 = setup(1, {})
    F.run(3)
    local state, aiData = q[1].env.Save()
    check(type(aiData) == "table" and aiData.marker == "aiCoreData", "Save returns the aiCore data as a trailing value")
    local before = F.count(q[1], "aiCoreLoad")
    q[1].env.Load(state, aiData)
    check(F.count(q[1], "aiCoreLoad") == before + 1, "Load hands the aiCore data back")
    F.run(2)
    check(F.count(q[1], "EnableCombatOnly") == 1, "a load with aiCore data does not re-enable combat-only mode")
    q[1].env.Load(state)
    check(F.count(q[1], "aiCoreLoad") == before + 1, "an old save without aiCore data loads without aiCore.Load")
    F.run(10)
    check(F.count(q[1], "EnableCombatOnly") == 2 and F.count(q[1], "BootstrapCombatOnly") == 2, "an old save enables combat-only mode on its first Update")
end

print("misns5 co-op: " .. checks .. " checks passed")
