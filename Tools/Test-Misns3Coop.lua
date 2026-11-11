-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/misns3cr.lua. Engine AI, rendering and combat remain mocked. Run from the repository root:
--   lua5.1 Tools/Test-Misns3Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Misns3Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local RECY, SPAWN = "avrecy1_recycler", "bdspawn1"
local EXTRAS = { 0, 1, 1, 2 } -- min(floor(humans / 2), 2) by head count

local function setup(n, options)
    options = options or {}
    local w = F.reset()
    if options.setup then options.setup(w) end
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
-- Humans parked in open ground that is 400+ m from every trigger and spawn.
local function away(p)
    for _, q in ipairs(p) do F.place(q.player, 2000 + 40 * q.id, 100000) end
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
        for _, name in ipairs({"BuildObject", "SetScrap", "SetAIP", "Goto", "Follow", "Attack", "SetIndependence", "RemoveObject"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function isHuman(p, h)
    for _, q in ipairs(p) do if q.player == h then return true end end
    return false
end

-- ------------------------------------------------------------------ offline == faithful
local MINE_B = { "minetrig1b", "minetrig2b", "minetrig3b" }
local function faithfulSetup(w) for _, name in ipairs(MINE_B) do w.pathPos[name] = { x = 1e7, y = 0, z = 1e7 } end end
local function outcomes(options, scenario)
    options.setup = options.faithful and faithfulSetup or nil
    local w, p, m = setup(1, options)
    scenario(w, p, m)
    local out = {}
    for _, name in ipairs({"SucceedMission", "FailMission"}) do
        for _, c in ipairs(F.callsOf(p[1], name)) do out[#out + 1] = name .. ":" .. tostring(c[3]) end
    end
    return table.concat(out, ","), p[1], m
end
local scenarios = {
    win = function(w, p) away(p); F.kill(RECY); F.run(3); F.nearTo(p[1].player, "homesweethome", 20, 0); F.run(8) end,
    withdraw = function(w, p) away(p); F.run(605) end,
    warn = function(w, p)
        away(p); F.nearTo(p[1].player, "iwarnedyou", 20, 0); F.run(1); F.run(6)
    end,
}
for name, scenario in pairs(scenarios) do
    local faithful = outcomes({ faithful = true, script = "Scripts/misns3.lua" }, scenario)
    local offline = outcomes({}, scenario)
    check(faithful == offline and faithful ~= "", "offline completes like the faithful port (" .. name .. "): " .. faithful .. " / " .. offline)
end
do
    local out, peer = outcomes({}, scenarios.win)
    check(out:find("SucceedMission:misns3w1.des", 1, true) == 1, "offline victory: " .. out)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is left on the authored enemy team 2") end
    out = outcomes({}, scenarios.withdraw)
    check(out:find("FailMission:misns3l1.des", 1, true) == 1, "offline withdrawal deadline: " .. out)
    out = outcomes({}, scenarios.warn)
    check(out:find("FailMission:misns3l2.des", 1, true) == 1, "offline warning failure: " .. out)
end
do -- an audio line without a handle can never hang a result
    local w, p = setup(1, { noAudioHandle = true })
    away(p); F.kill(RECY); F.run(3); F.nearTo(p[1].player, "homesweethome", 20, 0); F.run(6)
    check(F.count(p[1], "SucceedMission") >= 1, "victory does not wait on an absent audio handle")
end

-- ------------------------------------------------------------------ opening, ownership, teams
local w, p, m = setup(4)
check(m.missionstart and m.coopMissionStarted, "leader starts the shared mission")
check(m.player == "crcca_players", "the body holds the shared players token")
check(F.count(p[1], "SetAIControl", 5) == 1 and F.count(p[1], "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
check(F.index(p[1], "SetAIControl") <= p[1].chunkCalls, "SetAIControl runs at chunk root, before Start")
for i = 1, 4 do
    check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
    check(F.heardCount(p[i], "misns301.wav") == 1, "briefing once on peer " .. i)
    local adds = F.callsOf(p[i], "AddObjective")
    check(#adds >= 1 and adds[1][2] == "misns301.otf" and adds[1][3] == "white", "objective on peer " .. i)
    check(F.count(p[i], "SetObjectiveName") == 2, "the two navs are named on peer " .. i)
end
guestsPassive(p)
for _, b in ipairs(F.builds(p[1])) do check(b.team == 1 or b.team == 5, "builds are on team 1 or 5") end
check(F.count(p[1], "SetScrap") == 0, "the body sets no scrap and neither does the layer")
check(p[1].rally and p[1].rally[0] == "basenav", "respawns gather at the home base")

-- ------------------------------------------------------------------ the pleas, withdrawal and warnings
do
    local w2, q, m2 = setup(3)
    away(q)
    F.run(285)
    check(m2.plea1 and m2.plea2 and not m2.plea3, "pleas follow the clock")
    F.run(100)
    heardAll(q, "misns307.wav"); heardAll(q, "misns308.wav"); heardAll(q, "misns309.wav")
    F.run(225)
    for i = 1, 3 do check(F.heardCount(q[i], "misns304.wav") == 1, "withdrawal line on peer " .. i) end
    F.run(6)
    for i = 1, 3 do
        check(F.count(q[i], "FailMission") == 1 and F.last(q[i], "FailMission")[3] == "misns3l1.des", "shared withdrawal failure on peer " .. i)
    end
    guestsPassive(q)
end
do -- any human can trip the warning triggers
    local w2, q, m2 = setup(4)
    away(q)
    F.nearTo(q[3].player, "don'tgohere", 30, 0); F.run(2)
    heardAll(q, "misns305.wav")
    F.nearTo(q[4].player, "iwarnedyou", 20, 0); F.run(1)
    w2.audioBusy = true; F.run(2); w2.audioBusy = false; F.run(8)
    heardAll(q, "misns306.wav")
    for i = 1, 4 do
        check(F.count(q[i], "FailMission") == 1 and F.last(q[i], "FailMission")[3] == "misns3l2.des", "shared warning failure on peer " .. i)
    end
end

-- ------------------------------------------------------------------ defenders: nearest human, scaled, concealed
for n = 1, 4 do
    local w2, q, m2 = setup(n)
    away(q)
    F.nearTo(q[n].player, "bdspawntrig", 150, 0); F.run(3)
    local wave = builtAt(q[1], SPAWN)
    check(m2.bdspawned and #wave == 5 + EXTRAS[n], n .. " human(s): 5 defenders + " .. EXTRAS[n] .. " extras, got " .. #wave)
    allSafe(q, wave)
    local tanks, fighters = builtAt(q[1], SPAWN, 0, "bvtank"), builtAt(q[1], SPAWN, 0, "bvraz")
    check(#tanks == 3 + EXTRAS[n] and #fighters == 2, "extras mirror the first unit (a tank): " .. #tanks .. "/" .. #fighters)
    for _, b in ipairs(wave) do check(b.team == 5, "defenders are team 5") end
    local attackers = {}
    for _, c in ipairs(F.callsOf(q[1], "Attack")) do
        check(isHuman(q, c[3]), "defenders attack a human")
        attackers[c[2]] = true
    end
    for _, b in ipairs(wave) do check(attackers[b.h], "every defender (extras included) is ordered at a human") end
    check(type(m2.bd1) == "string", "tickets were replaced by real units")
    heardAll(q, "misns310.wav")
    guestsPassive(q)
end
do -- the nearest human is the target
    local w2, q, m2 = setup(3)
    away(q)
    F.nearTo(q[2].player, "bdspawntrig", 150, 0); F.run(3)
    F.place(q[3].player, 520, 101300) -- much closer to the defenders than the others
    F.run(16)
    local last
    for _, c in ipairs(F.callsOf(q[1], "Attack")) do if c[2] == m2.bd1 then last = c end end
    check(last and last[3] == q[3].player, "the 8 s re-order picks the human nearest the defender")
end
do -- a human at the defenders' camp holds the spawn back; a save/load neither loses nor duplicates it
    local w2, q, m2 = setup(3)
    away(q)
    F.nearTo(q[2].player, SPAWN, 100, 0)
    F.nearTo(q[3].player, "bdspawntrig", 150, 0)
    F.run(4)
    check(m2.bdspawned and #builtAt(q[1], SPAWN) == 0, "nothing is built in front of a human")
    check(type(m2.bd1) == "number" and m2.bd1 < 0, "the body holds tickets while the wave waits")
    local pending = m2.crcca.serial
    for _, r in ipairs(q) do r.env.Load(r.env.Save()) end
    F.connect(); F.run(3)
    check(m2.crcca.serial == pending and #builtAt(q[1], SPAWN) == 0, "save/load keeps the pending wave without duplicating it")
    -- (the body keeps re-asking for the attack every 8 s; that must not grow the request)
    F.run(20)
    check(m2.crcca.serial == pending, "re-orders on a waiting ticket do not create requests")
    F.place(q[2].player, 2100, 100000); F.run(3)
    local wave = builtAt(q[1], SPAWN)
    check(#wave == 5 + EXTRAS[3], "the whole wave arrives once the way is clear: " .. #wave)
    allSafe(q, wave)
    for _, b in ipairs(wave) do
        local attacked = false
        for _, c in ipairs(F.callsOf(q[1], "Attack")) do if c[2] == b.h then attacked = true end end
        check(attacked, "a late arrival is ordered at a human once built")
    end
end
do -- replacement wave, and the live cap drops extras only
    local w2, q, m2 = setup(4)
    away(q)
    F.nearTo(q[1].player, "bdspawntrig", 150, 0); F.run(3)
    local first = builtAt(q[1], SPAWN)
    check(#first == 7, "first wave of seven")
    for _, b in ipairs(first) do F.kill(b.h) end
    F.run(20)
    check(#builtAt(q[1], SPAWN) == 14, "a wiped-out wave is replaced (with its extras): " .. #builtAt(q[1], SPAWN))
    local w3, r, m3 = setup(4)
    away(r)
    m3.crcca.live = {}
    for i = 1, 12 do m3.crcca.live[i] = F.spawn("avtank", 5, 9000 + i, 9000) end
    F.nearTo(r[1].player, "bdspawntrig", 150, 0); F.run(3)
    check(#builtAt(r[1], SPAWN) == 5, "at the live cap the wave keeps its primaries and drops the extras")
end

-- ------------------------------------------------------------------ the retreat and the return home
for n = 1, 4 do
    local w2, q, m2 = setup(n)
    away(q)
    F.kill(RECY); F.run(3)
    check(m2.recyclerdestroyed and m2.bdspawned2, "recycler loss starts the retreat")
    local groups = builtAt(q[1], SPAWN)
    check(#groups == 4 + 2 * EXTRAS[n], n .. " human(s): four retreat groups + extras for the lead tank and fighter, got " .. #groups)
    allSafe(q, groups)
    local routes = {}
    for _, c in ipairs(F.callsOf(q[1], "Goto")) do routes[c[3]] = (routes[c[3]] or 0) + 1 end
    check(routes.bdpath1 == 1 + EXTRAS[n] and routes.bdpath2 == 1 + EXTRAS[n] and routes.bdpath3 == 1 and routes.bdpath4 == 1,
        "extras follow the lead's route")
    heardAll(q, "misns302.wav")
    local lastObjective = F.callsOf(q[n], "AddObjective")
    check(lastObjective[#lastObjective][2] == "misns301.otf" and lastObjective[#lastObjective][3] == "green", "objective list moves on at peer " .. n)
    -- escorts appear when ANY human closes on the lead of a group
    local lead = m2.bd50
    check(type(lead) == "string", "the lead is a real unit")
    local before = #F.builds(q[1])
    -- The mock names objects with strings, which the runtime reads as paths (a real handle is a number and a
    -- spawn at an object is exempt from the 460 m rule); step the human out of the way after the trigger frame.
    F.nearTo(q[n].player, lead, 300, 0); F.tick(); F.place(q[n].player, 2000 + 40 * n, 100000); F.run(3)
    local escorts = builtAt(q[1], lead, before)
    check(#escorts == 2 and m2.unit1spawned, "the lead's two escorts appear: " .. #escorts)
    check(F.count(q[1], "Follow", escorts[1].h) == 1, "escorts follow their lead")
    if n > 1 then guestsPassive(q) end
end
do -- the retreat waits for a human to leave the camp
    local w2, q, m2 = setup(2)
    away(q)
    F.nearTo(q[2].player, SPAWN, 50, 0)
    F.kill(RECY); F.run(3)
    check(m2.recyclerdestroyed and #builtAt(q[1], SPAWN) == 0, "no retreating unit appears in front of a human")
    F.place(q[2].player, 2100, 100000); F.run(3)
    check(#builtAt(q[1], SPAWN) == 6, "the groups arrive once the camp is unwatched")
end
do -- return home is a reach gate: everyone must be home
    local w2, q, m2 = setup(4)
    away(q)
    F.kill(RECY); F.run(3)
    for i = 1, 3 do F.nearTo(q[i].player, "homesweethome", 30 * i, 0) end
    F.run(4)
    check(not m2.missionwon and F.count(q[1], "SucceedMission") == 0, "one straggler holds the victory back")
    F.nearTo(q[4].player, "homesweethome", 60, 0)
    w2.audioBusy = true; F.run(3)
    check(m2.missionwon and F.heardCount(q[1], "misns303.wav") == 1, "everyone home: the debrief plays")
    check(F.count(q[1], "SucceedMission") == 0, "the victory waits for the debrief line")
    w2.audioBusy = false; F.run(12)
    heardAll(q, "misns303.wav")
    for i = 1, 4 do
        check(F.count(q[i], "SucceedMission") == 1 and F.count(q[i], "FailMission") == 0, "one shared victory on peer " .. i)
        check(F.last(q[i], "SucceedMission")[3] == "misns3w1.des", "victory debrief on peer " .. i)
        check((q[i].env.Save().coopUnresolved or 0) == 0, "no unresolved presentation identities on peer " .. i)
        local ups = F.callsOf(q[i], "UpdateObjective")
        check(#ups >= 1 and ups[1][2] == "misns302.otf" and ups[1][3] == "green", "the return objective turns green on peer " .. i)
    end
    guestsPassive(q)
end
do -- a victory cannot be undone by the failure triggers that follow it (offline: the body keeps running)
    local w2, q, m2 = setup(1)
    away(q)
    F.kill(RECY); F.run(3)
    F.nearTo(q[1].player, "homesweethome", 20, 0)
    F.run(4)
    check(m2.missionwon and F.count(q[1], "SucceedMission") >= 1, "alone at home: the mission is won")
    -- the warn2 trigger needs a living recycler, so rewind that flag and give the mission a living "recycler"
    -- (not re-detected as destroyed), then walk into the warning zone: the trigger reaches FailMission for real
    m2.recyclerdestroyed = false; m2.avrec = q[1].player
    F.nearTo(q[1].player, "iwarnedyou", 10, 0); F.run(6)
    check(m2.warn2, "the failure trigger fired after the win, so FailMission was attempted")
    check(F.count(q[1], "FailMission") == 0, "the won-flag latch swallows the attempted failure")
    check(F.count(q[1], "SucceedMission") >= 1, "the victory stands")
end
do -- a dead ship keeps the reach gate closed
    local w2, q, m2 = setup(2)
    away(q)
    F.kill(RECY); F.run(3)
    F.nearTo(q[1].player, "homesweethome", 20, 0); F.kill(q[2].player); F.run(5)
    check(not m2.missionwon, "a human without a ship is not home")
end

-- ------------------------------------------------------------------ the patrol
do
    local w2, q, m2 = setup(3)
    away(q)
    F.nearTo(q[2].player, "patroltrig1", 40, 0); F.run(9)
    check(m2.patrolspawned, "a human at the first patrol trigger sends the patrol out")
    local patrol = builtAt(q[1], "patrolspawn1")
    check(#patrol == 2, "two razors, never scaled: " .. #patrol)
    for _, b in ipairs(patrol) do
        check(b.odf == "bvraz" and b.team == 5, "patrol is team 5")
        check(F.count(q[1], "Goto", b.h) == 1 and F.count(q[1], "SetIndependence", b.h) == 1, "patrol route and independence")
    end
    heardAll(q, "misns219.wav")
    heardAll(q, "misns311.wav", 0) -- the first route keeps the stock line
    -- a human within 180 m of the patrol sets off the alarm: defenders activate and the patrol attacks
    F.nearTo(q[3].player, m2.pat1, 100, 0); F.run(9)
    heardAll(q, "misns220.wav")
    check(m2.mark1 and m2.bdspawned, "detection raises the alarm")
    check(F.count(q[1], "Attack", m2.pat1) >= 1, "the patrol attacks what saw it")
    guestsPassive(q)
end
do -- an allied bomber at the second trigger counts too
    local w2, q, m2 = setup(2)
    away(q)
    F.nearTo("bomb2", "patroltrig2", 30, 0); F.run(9)
    check(m2.patrolspawned and #builtAt(q[1], "patrolspawn2") == 2, "a wing bomber at patroltrig2 sends the second patrol")
    heardAll(q, "misns311.wav") -- restored: the second route gets its own warning
    heardAll(q, "misns219.wav", 0)
end

-- ------------------------------------------------------------------ the minefields
do
    local w2, q, m2 = setup(3)
    away(q)
    F.run(3)
    check(F.count(q[1], "BuildObject") == 0, "the absent minetrig1b/2b/3b paths never open a minefield")
    F.nearTo(q[2].player, "minetrig2", 100, 0); F.run(2)
    local mines = F.builds(q[1], 0, "proxmine")
    check(m2.minefield2 and #mines == 11 and not m2.minefield1 and not m2.minefield3, "the second field opens with eleven mines")
    for _, b in ipairs(mines) do check(b.team == 5, "mines are team 5") end
    F.nearTo(q[3].player, "minetrig3", 100, 0); F.run(2)
    check(m2.minefield3 and #F.builds(q[1], 0, "proxmine") == 23, "the third field opens with twelve more")
end
do -- if a later map carries the b-triggers they behave as stock
    local w2, q, m2 = setup(2, { setup = function(world) world.pathPos.minetrig1b = { x = 4000, y = 155, z = 100000 } end })
    away(q)
    F.nearTo(q[2].player, "minetrig1b", 50, 0); F.run(2)
    check(m2.minefield1 and #F.builds(q[1], 0, "proxmine") == 11, "a present minetrig1b opens field one")
end

-- ------------------------------------------------------------------ leader leaves, save/load
do
    local w2, q, m2 = setup(3)
    for i = 2, 3 do q[i].env.DeletePlayer(1) end
    F.run(3)
    for i = 2, 3 do check(F.count(q[i], "FailMission") == 1, "the mission fails for guest " .. i .. " when the leader leaves") end
    check(F.count(q[1], "FailMission") == 0, "the leader itself keeps playing")
end
do
    local w2, q, m2 = setup(4)
    away(q)
    F.run(30)
    for _, r in ipairs(q) do r.env.Load(r.env.Save()) end
    F.connect(); F.run(5)
    check(F.count(q[1], "AddObjective") <= 2 and F.heardCount(q[1], "misns301.wav") == 1, "load does not rerun the first frame")
    F.kill(RECY); F.run(2)
    F.nearTo(q[1].player, "homesweethome", 10, 0); F.nearTo(q[2].player, "homesweethome", 20, 0)
    F.nearTo(q[3].player, "homesweethome", 30, 0); F.nearTo(q[4].player, "homesweethome", 40, 0)
    F.run(12)
    for i = 1, 4 do check(F.count(q[i], "SucceedMission") == 1, "the loaded mission still ends once on peer " .. i) end
end

-- ------------------------------------------------------------------ weather: absent, present, broken
local function io(record, mode)
    return function(peer)
        local V = { Seed = 4242, target = 1 }
        function V.Init(o) peer.ioInit = o; record("IoInit", o.authority, o.send ~= nil, o.seed); if mode == "initfail" then error("boom") end end
        function V.Update(dt)
            if peer.ioInit and peer.ioInit.authority and peer.ioInit.send and not V.sent then
                V.sent = true; peer.ioInit.send("IoErupt", 3, 4)
            end
            if mode == "updatefail" then error("update boom") end
        end
        function V.AnnounceState() record("IoAnnounce") end
        function V.ApplyNetEvent(op, ...) record("IoEvent", op, ...) end
        function V.SetTargetLevel(n) V.target = n; record("IoLevel", n); return n end
        function V.GetTargetLevel() return V.target end
        function V.ReleaseForcedLevel() record("IoRelease") end
        function V.Quake(s, d) record("IoQuakeCall", s, d); return true end
        function V.OnObjectCreated(h) record("IoCreated", h) end
        function V.Save() return { saved = true } end
        function V.Load(s) record("IoLoad", s and s.saved) end
        function V.Shutdown() record("IoShutdown") end
        return V
    end
end
do
    local w2, q, m2 = setup(3)
    check(F.count(q[1], "EnvironmentInit") == 0 and m2.missionstart, "no weather module: the mission runs and touches no Environment")
    local printed = false
    for _, c in ipairs(q[1].calls) do if c[1] == "print" and tostring(c[2]):find("weather disabled", 1, true) then printed = true end end
    check(printed, "missing weather is logged, not fatal")
end
do
    local weather = { module = function(peer, record) return io(record)(peer) end, sites = { bounds = {} } }
    local w2, q, m2 = setup(3, { weather = weather })
    away(q)
    check(F.count(q[1], "IoInit", true) == 1 and F.last(q[1], "IoInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.count(q[2], "IoInit", false) == 1, "guests render only (not the authority)")
    check(F.count(q[1], "IoAnnounce") == 1 and F.count(q[2], "IoAnnounce") == 0, "the leader announces its weather state once")
    check(F.count(q[1], "EnvironmentInit") == 1, "Io lighting is initialised")
    check(F.last(q[1], "EnvironmentInit")[2].lightingMode == "orbit", "Io's orbit lighting")
    check(F.count(q[1], "WeatherSensors") == 1, "the sensors bind once to the director")
    for i = 2, 3 do
        local e = F.last(q[i], "IoEvent")
        check(e and e[2] == "IoErupt" and e[3] == 3 and e[4] == 4, "weather events reach guest " .. i)
    end
    check(q[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    -- beats, in mission order
    check(F.count(q[1], "IoLevel") == 0, "calm start")
    F.run(285); check(F.count(q[1], "IoLevel", 2) == 1, "the second plea stirs Io")
    F.nearTo(q[2].player, "bdspawntrig", 150, 0); F.run(3)
    check(F.count(q[1], "IoLevel", 3) == 1, "the defenders' fight raises it")
    away(q)
    F.kill(RECY); F.run(3)
    check(F.count(q[1], "IoLevel", 4) == 1 and F.count(q[1], "IoQuakeCall") == 1, "the retreat raises it again and shakes the ground once")
    for i = 1, 3 do F.nearTo(q[i].player, "homesweethome", 25 * i, 0) end
    F.run(12)
    check(F.count(q[1], "IoLevel", 1) == 1 and F.count(q[1], "IoRelease") == 1, "victory eases the weather")
    check(F.count(q[1], "IoCreated") > 0, "new objects are offered to the weather")
    check(F.count(q[2], "IoLevel") == 0 and F.count(q[2], "IoQuakeCall") == 0, "guests never drive the weather")
end
do
    local weather = { module = function(peer, record) return io(record)(peer) end, sites = { bounds = {} } }
    local w2, q, m2 = setup(2, { weather = weather })
    for _, r in ipairs(q) do r.env.Load(r.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(q[1], "IoShutdown") >= 1 and F.count(q[1], "IoLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(q[1], "IoInit") == 2 and F.count(q[1], "WeatherSensors") == 2, "the weather re-initialises and rebinds after a load")
end
do -- sites module missing: no weather, never an error
    local w2, q, m2 = setup(2, { weather = { module = function(peer, record) return io(record)(peer) end } })
    check(F.count(q[1], "IoInit") == 0 and m2.missionstart, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local w2, q, m2 = setup(2, { weather = { module = function(peer, record) return io(record, mode)(peer) end, sites = {} } })
    away(q)
    F.kill(RECY); F.run(3)
    for i = 1, 2 do F.nearTo(q[i].player, "homesweethome", 25 * i, 0) end
    F.run(12)
    check(F.count(q[1], "SucceedMission") == 1 and F.count(q[2], "SucceedMission") == 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("misns3 co-op: " .. checks .. " checks passed")
