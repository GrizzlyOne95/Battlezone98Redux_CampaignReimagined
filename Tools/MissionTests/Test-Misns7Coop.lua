-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/misns7cr.lua. Engine AI, rendering and combat remain mocked. Run from the repository root:
--   lua5.1 Tools/MissionTests/Test-Misns7Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/MissionTests/Misns7Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local JAIL, APC, AVREC, SVREC, SVMUF = "jail", "svapc", "avrecycle", "svrecycle", "svmuf"
local SUPPLY, CON_GEYSER, RIG = "supply", "con_geyser", "rig"

local function setup(n, options)
    options = options or {}
    local w = F.reset()
    if options.setup then options.setup(w) end
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
local function heardAll(p, file, count)
    for i, q in ipairs(p) do check(F.heardCount(q, file) == (count or 1), "peer " .. i .. " hears " .. file .. " x" .. (count or 1)) end
end
local function guestsPassive(p)
    for i = 2, #p do
        for _, name in ipairs({"BuildObject", "SetScrap", "AddScrap", "SetAIP", "Goto", "Attack", "SetIndependence",
            "SetPerceivedTeam", "GetIn", "Build", "Dropoff", "Stop", "SetPilot", "AddPilot"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function allSafe(p, builds)
    for _, b in ipairs(builds) do
        for _, q in ipairs(p) do
            check(q.env.GetDistance(q.player, b.h) >= 460, "no scripted unit is built within 460 m of any human")
        end
    end
end
local function camerasBalanced(p, why)
    for i, q in ipairs(p) do check(q.camera == 0, "cameras balanced on peer " .. i .. ": " .. why) end
end
-- Players hold at the prison (the real play area); tests move them as the mission needs.
local function atPrison(p)
    for i, q in ipairs(p) do F.place(q.player, 1480 + 12 * i, 99840) end
end
local function outcomes(peer)
    local out = {}
    for _, name in ipairs({"SucceedMission", "FailMission"}) do
        for _, c in ipairs(F.callsOf(peer, name)) do out[#out + 1] = name .. ":" .. tostring(c[3]) end
    end
    return table.concat(out, ",")
end
-- Drive the rescue far enough to have the three engineers on the APC: returns the con handles.
local function rescue(w, p, m)
    atPrison(p)
    F.run(2)
    F.kill(JAIL)
    F.run(2)
    local cons = {m.con1, m.con2, m.con3}
    for _, c in ipairs(cons) do F.nearTo(c, APC, 5, 0) end
    F.run(1)
    return cons
end
-- Put the APC beside a target and run until the engineer is built.
local function deliver(target, built)
    F.nearTo(APC, target, 30, 0)
    F.runUntil(built, 60)
end

-- ------------------------------------------------------------------ offline == faithful
local scenarios = {
    win = function(w, p, m) F.run(2); F.kill(AVREC); F.run(12) end,
    comrades = function(w, p, m)
        atPrison(p); F.run(2); F.kill(JAIL); F.run(3)
        F.kill(m.con1); F.kill(m.con2); F.kill(m.con3); F.run(12)
    end,
    apc = function(w, p, m) F.run(2); F.kill(APC); F.run(12) end,
}
for name, scenario in pairs(scenarios) do
    local result = {}
    for _, faithful in ipairs({true, false}) do
        local w = F.reset()
        local peer = F.makePeer(1, 1, false, faithful and {faithful = true, script = "Scripts/misns7.lua"} or {})
        F.connect(); F.run(1)
        local m = peer.env.Save()
        scenario(w, {peer}, m)
        result[faithful] = outcomes(peer)
        result[tostring(faithful) .. "camera"] = peer.camera
    end
    check(result[true] == result[false] and result[true] ~= "", "offline completes like the faithful port (" .. name .. "): " .. result[true] .. " / " .. result[false])
    check(result.truecamera == result.falsecamera, "offline camera stack matches the faithful port (" .. name .. ")")
end
do
    local w = F.reset()
    local peer = F.makePeer(1, 1, false, {})
    F.connect(); F.run(3)
    F.kill(AVREC); F.run(12)
    check(outcomes(peer) == "SucceedMission:misns7w1.des", "offline victory: " .. outcomes(peer))
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is left on the authored enemy team 2") end
    check(F.count(peer, "SetPilot", 1) == 1 and F.count(peer, "SetPilot", 5) == 1 and F.count(peer, "SetPilot", 2) == 0,
        "offline keeps the body's pilot bookkeeping, the enemy reserve on team 5")
    check(F.count(peer, "AddScrap") == 0, "offline: no guest scrap")
end

-- ------------------------------------------------------------------ opening, ownership, teams
local w, p, m = setup(4, {})
check(m.start_done and m.coopMissionStarted, "leader starts the shared mission")
check(F.count(p[1], "SetAIControl", 5) == 1 and F.count(p[1], "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
check(F.count(p[1], "SetAIControl") == 1, "the body's Start never repeats SetAIControl")
check(F.index(p[1], "SetAIControl") <= p[1].chunkCalls, "SetAIControl runs at chunk root, before Start")
do
    local scraps = {}
    for _, c in ipairs(F.callsOf(p[1], "SetScrap")) do scraps[c[2] .. ":" .. c[3]] = true end
    check(scraps["5:40"] and not scraps["2:40"], "enemy scrap on team 5, never on the authored team 2")
    check(F.count(p[1], "AddScrap", 1) == 1 and F.callsOf(p[1], "AddScrap")[1][3] == 30, "guests add 10 scrap each to the shared team 1")
    check(F.count(p[1], "SetPilot", 5) == 1 and F.count(p[1], "SetPilot", 2) == 0, "the NSDF pilot reserve is team 5")
    check(F.count(p[1], "SetPilot", 1) == 0 and F.count(p[1], "AddPilot") == 0, "the native lives of the humans are left to CRCoop")
end
for i = 1, 4 do
    check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
    check(F.heardCount(p[i], "misns700.wav") == 1, "briefing once on peer " .. i)
    check(F.callsOf(p[i], "AddObjective")[1][2] == "misns700.otf", "objective on peer " .. i)
end
check(p[1].rally[0] == "svapc", "respawn rallies at the APC")
for _, name in ipairs({"guntower1", "guntower2", "svrecycle"}) do
    check(F.count(p[1], "SetPerceivedTeam", name) == 1, "disguise " .. name)
end
for _, c in ipairs(F.callsOf(p[1], "SetPerceivedTeam")) do check(c[3] == 5, "disguises use team 5") end
guestsPassive(p)
F.run(9)
do -- scavengers arrive on team 5 at the NSDF factory spot
    local scavs = F.builds(p[1], 0, "bvscav")
    check(#scavs == 2 and scavs[1].team == 5 and scavs[1].where == "muf_point", "two NSDF scavengers on team 5")
end

-- ------------------------------------------------------------------ prison, escalation, scaled fighters
atPrison(p)
F.run(3)
heardAll(p, "misns722.wav")
check(m.jail_found, "the prison is found by any human")
local mark = #p[1].calls
F.run(125) -- adjust timer
check(m.nsdf_adjust and m.fight1_built, "the NSDF escalates 120 s after the prison is found")
do
    local fighters = F.builds(p[1], mark, "bvraz")
    check(#fighters == 3, "4 humans: 1 fighter + 2 co-op extras, got " .. #fighters)
    for _, b in ipairs(fighters) do
        check(b.team == 5, "fighters on the co-op enemy team")
        check(b.where == "muf_spawn", "the muf point is within 460 m of the humans: the authored fallback approach is used")
    end
    allSafe(p, fighters)
    for _, b in ipairs(fighters) do
        local attacks = 0
        for _, c in ipairs(F.callsOf(p[1], "Attack")) do
            if c[2] == b.h then
                attacks = attacks + 1
                check(c[3] ~= "crcca_players" and F.alive(c[3]) and F.team(c[3]) >= 1 and F.team(c[3]) <= 4, "attack target is a real human craft")
            end
        end
        check(attacks == 1, "each fighter is ordered to attack once")
    end
end
F.run(45)
check(m.fight3_built and m.build_turret, "fighter wave 2 and 3 and the first turret")
do
    local fighters = F.builds(p[1], mark, "bvraz")
    check(#fighters == 9, "3 events x (1 + 2) fighters, got " .. #fighters)
    local liveCap = 0
    for _, b in ipairs(fighters) do if F.alive(b.h) then liveCap = liveCap + 1 end end
    check(liveCap <= 12, "live scaled units stay under the cap")
    local turret = F.builds(p[1], mark, "bvturr")
    check(#turret == 1 and turret[1].team == 5, "the turret is unscaled and on team 5")
end

-- ------------------------------------------------------------------ prison destroyed, rescue, cutscene
w, p, m = setup(3, {})
atPrison(p)
F.run(3)
F.kill(JAIL)
F.run(1)
for i = 1, 3 do check(p[i].camera == 1, "everyone watches the prison fall (peer " .. i .. ")") end
F.run(1)
do
    local cons = {m.con1, m.con2, m.con3}
    for i, c in ipairs(cons) do
        check(c ~= nil and F.team(c) == 1, "engineer " .. i .. " is a Soviet soldier")
    end
    check(F.count(p[1], "GetIn") == 3, "the engineers are sent to the APC")
end
w.cancel = true; F.run(0.5)
check(not m.jail_camera_off, "a skip never ends the shared prison shot in a network game")
check(p[1].camera == 1, "the held prison shot is unskippable on every peer")
w.cancel = false
F.run(3)
camerasBalanced(p, "prison shot")
check(m.jail_camera_off, "the shared shot ends on the clock")
check(F.count(p[1], "BuildObject") > 0, "the NSDF factory is built")
F.run(6)
check(m.avmuf_built, "the NSDF builds its factory after the prison falls")
do
    local muf = F.builds(p[1], 0, "bvmuf")
    check(#muf == 1 and muf[1].team == 5, "the factory is team 5")
end
heardAll(p, "misns710.wav")

-- ------------------------------------------------------------------ pickup and the engineer deliveries
w, p, m = setup(4, {})
local cons = rescue(w, p, m)
F.run(1)
-- Restored unused lines: first pickup misns701, second misns726, third keeps misns702.
heardAll(p, "misns701.wav")
heardAll(p, "misns726.wav")
heardAll(p, "misns702.wav")
heardAll(p, "misns704.wav")
check(m.fully_loaded and m.con1_safe and m.con2_safe and m.con3_safe, "all three engineers are aboard")
check(F.count(p[1], "AddPilot") == 0, "no native pilot bookkeeping for the humans in co-op")
F.run(8)
check(m.muf_message, "the APC pilot briefs the player when no enemy is near")
do
    local c = F.callsOf(p[1], "CountUnitsNearObject")[1]
    check(c ~= nil and c[3] == 200 and c[4] == 5, "enemy counts use team 5, never team 2")
end
heardAll(p, "misns724.wav"); heardAll(p, "misns717.wav")
F.run(30)
-- recycler
deliver(SVREC, function() return m.svrecycle_unit_spawn end)
for i = 1, 4 do check(p[i].camera == 1, "everyone watches the recycler delivery (peer " .. i .. ")") end
check(F.count(p[1], "Stop", APC) >= 1, "the APC halts for the shared shot")
local engineer = m.engineer
check(F.alive(engineer) and F.team(engineer) == 1, "an engineer steps out")
F.nearTo(engineer, SVREC, 5, 0)
F.run(2)
camerasBalanced(p, "recycler delivery")
check(m.camera_off_recycle, "recycler restored")
do
    local rec = F.builds(p[1], 0, "svrecy")
    check(#rec == 1 and rec[1].team == 1, "the restored recycler is Soviet team 1")
    check(F.last(p[1], "SetPerceivedTeam")[3] == 5, "its disguise is team 5")
    check(F.count(p[1], "AddScrap", 1) >= 2, "reward scrap on the shared base")
end
heardAll(p, "misns727.wav")
do
    local aips = F.callsOf(p[1], "SetAIP")
    check(#aips >= 1 and aips[#aips][2] == "misns7a.aip" and aips[#aips][3] == 5, "the AIP switch is on team 5")
end
-- factory
deliver(SVMUF, function() return m.svmuf_unit_spawn end)
for i = 1, 4 do check(p[i].camera == 1, "everyone watches the factory delivery (peer " .. i .. ")") end
-- stock hang: the engineer dies on the way. The shot would never end; the guard completes it.
F.kill(m.engineer)
F.run(60)
check(p[1].camera == 1 and not m.camera_off_muf, "the shot is still running before the guard")
F.run(20)
camerasBalanced(p, "killed engineer is completed by the guard")
check(m.camera_off_muf, "the guard completes the delivery")
check(#F.builds(p[1], 0, "svmuf") == 1, "the factory is restored")
heardAll(p, "misns714.wav")
-- supply shed
deliver(SUPPLY, function() return m.supply_unit_spawn end)
F.nearTo(m.engineer, CON_GEYSER, 5, 0)
F.run(2)
camerasBalanced(p, "supply delivery")
check(m.camera_off_supply, "the shed is opened")
F.run(16)
check(m.supplies_spawned, "the cache is delivered")
do
    local cache = {}
    for _, b in ipairs(F.builds(p[1], 0)) do cache[b.odf] = (cache[b.odf] or 0) + 1 end
    check(cache.svscav == 2 and cache.svturr == 2 and cache.spammo == 3 and cache.sprepa == 2, "two scavengers, two turrets, three ammo, two repair")
end
heardAll(p, "misns707.wav"); heardAll(p, "misns721.wav")
guestsPassive(p)
do
    local aips = F.callsOf(p[1], "SetAIP")
    check(#aips >= 1, "the delivered mission has set at least one AIP")
    for _, c in ipairs(aips) do check(c[3] == 5, "every AIP addresses team 5: " .. tostring(c[2])) end
end

-- ------------------------------------------------------------------ restorations
do
    local before = F.count(p[1], "Build")
    F.run(10)
    check(m.plan_a, "the NSDF scavenger plan is on")
    -- plan_d: the rig is lost
    F.kill(RIG)
    F.run(2)
    check(m.plan_d, "restored plan_d switches the AIP when the rig dies")
    local aips = F.callsOf(p[1], "SetAIP")
    check(aips[#aips][2] == "misns7a.aip" and aips[#aips][3] == 5, "plan_d AIP is team 5")
end
do -- muf retreat (restored): a damaged undeployed factory falls back to geyser3
    local w2, q, m2 = setup(2, {})
    atPrison(q); F.run(2); F.kill(JAIL); F.run(12)
    local muf = F.builds(q[1], 0, "bvmuf")[1]
    check(muf ~= nil and m2.avmuf_built, "the factory exists")
    F.world().objects[muf.h].health = 0.4
    F.run(2)
    check(m2.muf_redirect and F.count(q[1], "Goto", muf.h) >= 2, "restored retreat sends the damaged factory to geyser3")
    local last
    for _, c in ipairs(F.callsOf(q[1], "Goto")) do if c[2] == muf.h then last = c end end
    check(last[3] == "geyser3", "the retreat target is geyser3")
end
do -- expansion: recycler back, rig builds at power2_spot then tower3_spot
    local w2, q, m2 = setup(2, {})
    m2.camera_off_recycle = true; m2.blah = true
    F.run(2)
    check(m2.b3 and F.count(q[1], "Build", RIG) >= 1, "restored expansion orders the second power plant")
    F.run(6)
    check(m2.rig_show2 and F.count(q[1], "Dropoff", RIG) >= 1, "the plant is placed at power2_spot")
    local drop
    for _, c in ipairs(F.callsOf(q[1], "Dropoff")) do if c[3] == "power2_spot" then drop = c end end
    check(drop ~= nil, "Dropoff names power2_spot")
    F.spawn("bbwpow", 5, 1627, 99652)
    F.run(6)
    check(m2.b4, "the tower follows the plant")
    F.run(6)
    check(m2.rig_show3, "the tower is placed at tower3_spot")
end

-- ------------------------------------------------------------------ results
w, p, m = setup(3, {})
F.run(2)
F.kill(AVREC)
F.run(15)
for i = 1, 3 do
    check(F.count(p[i], "SucceedMission") == 1, "victory reaches peer " .. i .. " once")
    check(F.heardCount(p[i], "misns712.wav") == 1, "victory line on peer " .. i)
end
check(F.callsOf(p[1], "SucceedMission")[1][3] == "misns7w1.des", "victory description")
w, p, m = setup(3, {})
F.run(2)
F.kill(APC)
F.run(15)
for i = 1, 3 do
    check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "misns7f2.des", "losing the APC fails peer " .. i)
end
w, p, m = setup(3, {})
atPrison(p); F.run(2); F.kill(JAIL); F.run(3)
F.kill(m.con1); F.kill(m.con2); F.kill(m.con3)
F.run(15)
for i = 1, 3 do check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "misns7f1.des", "losing every engineer fails peer " .. i) end
-- victory wins a same-frame tie, a result is never replaced
w, p, m = setup(2, {})
F.run(2)
F.kill(AVREC); F.run(1); F.kill(APC); F.run(15)
check(F.count(p[1], "SucceedMission") == 1 and F.count(p[1], "FailMission") == 0, "a won mission is never failed afterwards")

-- ------------------------------------------------------------------ leader leaves
w, p, m = setup(3, {})
for i = 2, 3 do p[i].env.DeletePlayer(1) end
F.run(3)
for i = 2, 3 do check(F.count(p[i], "FailMission") == 1, "the mission fails for guest " .. i .. " when the leader leaves") end
check(F.count(p[1], "FailMission") == 0, "the leader itself keeps playing")

-- ------------------------------------------------------------------ no safe approach: the request waits and survives a load
do
    local w2, q, m2 = setup(4, {})
    -- humans stand near both authored approaches and the factory spot
    F.place(q[1].player, 1620, 99765); F.place(q[2].player, 3070, 99118); F.place(q[3].player, 4720, 102280)
    F.place(q[4].player, 1500, 99790)
    m2.nsdf_adjust = true
    F.run(3)
    check(#F.builds(q[1], 0, "bvraz") == 0, "no fighter pops in while every approach is watched")
    local waiting = 0
    for _ in pairs(m2.crcca.arrivals) do waiting = waiting + 1 end
    check(waiting == 3, "the request (primary + 2 extras) is saved, got " .. waiting)
    for _, r in ipairs(q) do r.env.Load(r.env.Save()) end
    F.connect(); F.run(3)
    check(#F.builds(q[1], 0, "bvraz") == 0, "a load neither loses nor builds the waiting request")
    F.place(q[2].player, 3070, 96000); F.place(q[3].player, 4720, 96000)
    F.run(3)
    check(#F.builds(q[1], 0, "bvraz") >= 1, "the request builds once an approach is clear")
    local seen = {}
    for _, b in ipairs(F.builds(q[1], 0, "bvraz")) do check(not seen[b.h], "no duplicate build after a load"); seen[b.h] = true end
end

-- ------------------------------------------------------------------ save/load mid-mission keeps the body's state
w, p, m = setup(2, {})
atPrison(p); F.run(3)
local scavs = #F.builds(p[1], 0, "bvscav")
F.run(9)
for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
F.connect(); F.run(5)
check(#F.builds(p[1], 0, "bvscav") == 2, "load does not rebuild the scavengers")
check(F.count(p[1], "SetScrap", 5) == 1, "load does not rerun the first frame")
F.kill(AVREC); F.run(15)
for i = 1, 2 do check(F.count(p[i], "SucceedMission") == 1, "the loaded mission still ends once on peer " .. i) end

-- ------------------------------------------------------------------ weather: absent, present (Titan), broken, empty sites
local function titan(record, mode)
    return function(peer)
        local V = { Seed = 777 }
        function V.Init(o) peer.titanInit = o; record("TitanInit", o.authority, o.send ~= nil, o.seed, o.sites ~= nil); if mode == "initfail" then error("boom") end end
        function V.Update(dt)
            if peer.titanInit and peer.titanInit.authority and peer.titanInit.send and not V.sent then
                V.sent = true; peer.titanInit.send("TitanRoll", 1, 0.5, 30)
            end
            if mode == "updatefail" then error("update boom") end
        end
        function V.AnnounceState() record("TitanAnnounce") end
        function V.ApplyNetEvent(op, ...) record("TitanEvent", op, ...) end
        function V.SetTargetLevel(n) record("TitanLevel", n) end
        function V.Roll(d, s) record("TitanRollNow", d, s) end
        function V.OnObjectCreated(h) record("TitanCreated", h) end
        function V.Save() return { saved = true } end
        function V.Load(s) record("TitanLoad", s and s.saved) end
        function V.Shutdown() record("TitanShutdown") end
        return V
    end
end
do
    w, p, m = setup(3, {})
    check(F.count(p[1], "EnvironmentInit") == 0 and m.start_done, "no weather module: the mission runs and touches no Environment")
    local printed = false
    for _, c in ipairs(p[1].calls) do if c[1] == "print" and tostring(c[2]):find("weather disabled", 1, true) then printed = true end end
    check(printed, "missing weather is logged, not fatal")
end
do
    local sites = dofile("Scripts/CRTitanSitesS7.lua")
    check(type(sites) == "table" and #sites.pools == 0 and sites.wet.cells == 0, "the shipped Titan sites file for this map is empty")
    local weather = { module = function(peer, record) return titan(record)(peer) end, sites = sites }
    w, p, m = setup(3, { weather = weather })
    check(F.count(p[1], "TitanInit", true) == 1 and F.last(p[1], "TitanInit")[3] == true and F.last(p[1], "TitanInit")[5] == true,
        "the leader owns the weather and is handed the (empty) sites table")
    check(F.count(p[2], "TitanInit", false) == 1, "guests render only")
    check(F.count(p[1], "TitanAnnounce") == 1 and F.count(p[2], "TitanAnnounce") == 0, "the leader announces its weather state once")
    check(F.count(p[1], "EnvironmentInit") == 0, "Titan runs on its own renderer path: Environment is not initialised")
    for i = 2, 3 do
        local e = F.last(p[i], "TitanEvent")
        check(e and e[2] == "TitanRoll" and e[3] == 1, "weather events reach guest " .. i)
    end
    check(p[1].env.Save().crcca.weatherSeed == 777, "the weather seed is saved with the mission")
    atPrison(p); F.run(3)
    check(F.count(p[1], "TitanRollNow", 60) == 1, "finding the prison rolls a haze bank in")
    check(F.count(p[2], "TitanRollNow") == 0, "only the leader's director is steered")
    F.kill(JAIL); F.run(2)
    check(F.count(p[1], "TitanLevel", 3) == 1, "the breakout raises the weather")
    check(F.count(p[1], "TitanCreated") > 0, "new objects are offered to the weather")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "TitanShutdown") >= 1 and F.count(p[1], "TitanLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(p[1], "TitanInit") == 2, "the weather re-initialises after a load")
    F.kill(AVREC); F.run(15)
    check(F.count(p[1], "TitanLevel", 1) == 1, "victory eases the weather")
end
do -- sites module missing: no weather, never an error
    w, p, m = setup(2, { weather = { module = function(peer, record) return titan(record)(peer) end } })
    check(F.count(p[1], "TitanInit") == 0 and m.start_done, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    w, p, m = setup(2, { weather = { module = function(peer, record) return titan(record, mode)(peer) end, sites = {} } })
    F.run(2); F.kill(AVREC); F.run(15)
    check(F.count(p[1], "SucceedMission") == 1 and F.count(p[2], "SucceedMission") == 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

-- ------------------------------------------------------------------ engineer guards (recycler, supply, load reset)
-- Bring a fresh game to the point where the recycler delivery has started: returns peers and mission state.
local function toRecycle(n)
    local w2, q, m2 = setup(n, {})
    rescue(w2, q, m2)
    F.run(40)
    deliver(SVREC, function() return m2.svrecycle_unit_spawn end)
    return w2, q, m2
end
do -- guardRecycle: a living engineer that is still walking is not removed; a stuck one is released at 180 s
    local w2, q, m2 = toRecycle(2)
    local eng = m2.engineer
    check(F.alive(eng) and not m2.camera_off_recycle, "the recycler engineer is out and walking")
    F.run(100)
    check(F.alive(eng) and F.count(q[1], "RemoveObject", eng) == 0, "a live engineer is not removed after 100 s")
    check(not m2.camera_off_recycle and not m2.svrecycle_on, "the delivery is not completed behind a live engineer")
    F.run(85)
    check(m2.svrecycle_on and F.count(q[1], "RemoveObject", eng) == 1, "a stuck live engineer is released after 180 s")
    F.run(3)
    camerasBalanced(q, "stuck recycler engineer")
    check(m2.camera_off_recycle, "the stuck-engineer delivery completes")
end
do -- guardRecycle: a dead engineer is released at 75 s and nothing is removed
    local w2, q, m2 = toRecycle(2)
    local eng = m2.engineer
    F.kill(eng)
    F.run(60)
    check(not m2.svrecycle_on, "no release before 75 s")
    F.run(20)
    check(m2.svrecycle_on and F.count(q[1], "RemoveObject", eng) == 0, "a dead engineer is released at 75 s without a removal")
end
do -- the load reset: a save/load restarts the guard clock
    local w2, q, m2 = toRecycle(2)
    F.kill(m2.engineer)
    F.run(70)
    for _, r in ipairs(q) do r.env.Load(r.env.Save()) end
    F.run(30)
    check(not m2.svrecycle_on, "the guard clock restarted at the load: 100 s after delivery is not yet released")
    F.run(60)
    check(m2.svrecycle_on, "the restarted guard still releases the delivery")
end
do -- guardSupply: the shed delivery obeys the same rule
    local w2, q, m2 = toRecycle(2)
    F.nearTo(m2.engineer, SVREC, 5, 0); F.run(2)
    check(m2.camera_off_recycle, "recycler restored first")
    deliver(SVMUF, function() return m2.svmuf_unit_spawn end)
    F.nearTo(m2.engineer, SVMUF, 5, 0); F.run(2)
    check(m2.camera_off_muf, "factory restored second")
    deliver(SUPPLY, function() return m2.supply_unit_spawn end)
    local eng = m2.engineer
    F.run(100)
    check(F.alive(eng) and not m2.supply_on and F.count(q[1], "RemoveObject", eng) == 0, "a live supply engineer is not removed at 100 s")
    F.run(85)
    check(m2.supply_on and F.count(q[1], "RemoveObject", eng) == 1, "a stuck live supply engineer is released at 180 s")
    F.run(3)
    camerasBalanced(q, "stuck supply engineer")
end
do -- guardSupply: a dead supply engineer is released at 75 s
    local w2, q, m2 = toRecycle(2)
    F.nearTo(m2.engineer, SVREC, 5, 0); F.run(2)
    deliver(SVMUF, function() return m2.svmuf_unit_spawn end)
    F.nearTo(m2.engineer, SVMUF, 5, 0); F.run(2)
    deliver(SUPPLY, function() return m2.supply_unit_spawn end)
    F.kill(m2.engineer)
    F.run(60)
    check(not m2.supply_on, "no supply release before 75 s")
    F.run(20)
    check(m2.supply_on, "a dead supply engineer is released at 75 s")
end

print("misns7 co-op: " .. checks .. " checks passed")
