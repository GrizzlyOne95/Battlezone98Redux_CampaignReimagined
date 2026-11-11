-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/bd15cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/Test-Bdmisn15Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Bdmisn15Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local function extrasFor(n) return math.min(math.floor(n / 2), 2) end
-- The body's eight scripted spawn events: where, units in the event (primaries only).
local EVENTS = {
    { at = 20, where = "spawn_west_wave", units = 1 },
    { at = 60, where = "spawn_south_wave", units = 6 },
    { at = 180, where = "spawn_north_wave", units = 7 },
    { at = 360, where = "spawn_east_wave", units = 6 },
    { at = 420, where = "spawn_east_wave", units = 6 },
    { at = 603, where = "spawn_south_wave", units = 1 },
    { at = 603, where = "spawn_north_wave", units = 2 },
    { at = 603, where = "spawn_west_wave", units = 3 },
}

local function setup(n, options)
    options = options or {}
    local w = F.reset()
    w.audioBusy = options.busy == true
    w.timerUpward = options.upward == true
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
local function runTo(t) local w = F.world(); if t > w.now then F.run(t - w.now) end end
local function builtAt(peer, where, odf)
    local out = {}
    for _, b in ipairs(F.builds(peer, 0, odf)) do
        if b.where == where then out[#out + 1] = b end
    end
    return out
end
local function enemies(peer)
    local out = {}
    for _, b in ipairs(F.builds(peer)) do if b.team == 5 then out[#out + 1] = b end end
    return out
end
local function guestsPassive(p)
    for i = 2, #p do
        for _, name in ipairs({"BuildObject", "SetScrap", "Goto", "Hide", "SetMaxHealth", "MakeExplosion_host"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on the authored enemy team 2") end
end
-- Every Chinese craft the script built dies.
local function reap()
    for h, o in pairs(F.world().objects) do
        if o.alive and h:match("^built") and o.odf:match("^cv") then o.alive = false end
    end
end
local function wins(peer)
    local n = 0
    for _, c in ipairs(F.callsOf(peer, "SucceedMission")) do if c[3] == "bd15win.des" then n = n + 1 end end
    return n
end
local function listOf(peer, fromIndex)
    local out = {}
    for i = fromIndex or 1, #peer.calls do
        local c = peer.calls[i]
        if c[1] == "AddObjective" then out[c[2]] = c[3] end
    end
    return out
end
-- A full battle to the finale: every wave arrives, is killed, and the countdown starts.
local function toCountdown(w, p)
    runTo(606)
    reap(); F.run(1)
end

-- ------------------------------------------------------------------ offline == faithful
local RESTORED_LINES = { ["bd15008.wav"] = true, ["bd15009.wav"] = true, ["bd15013.wav"] = true }
local function summary(peer)
    local builds, lines, results = {}, {}, {}
    for _, c in ipairs(peer.calls) do
        if c[1] == "BuildObject" then
            builds[#builds + 1] = c[3] .. ":" .. (c[4] == 2 and 5 or c[4]) .. ":" .. tostring(c[5])
        elseif c[1] == "AudioMessage" or c[1] == "Play" or c[1] == "Queue" then
            if not RESTORED_LINES[c[2]] then lines[#lines + 1] = c[2] end
        elseif c[1] == "SucceedMission" or c[1] == "FailMission" then
            results[#results + 1] = c[1] .. ":" .. tostring(c[3])
        elseif c[1] == "StartCockpitTimer" then
            results[#results + 1] = "T:" .. c[2] .. "," .. c[3] .. "," .. c[4]
        elseif c[1] == "ColorFade" or c[1] == "MakeExplosion" or c[1] == "HideCockpitTimer" then
            results[#results + 1] = c[1] .. ":" .. tostring(c[2]) .. ":" .. tostring(c[3])
        elseif c[1] == "CameraPath" then
            results[#results + 1] = "CP:" .. c[2] .. ":" .. c[3] .. ":" .. c[4]
        end
    end
    table.sort(builds)
    -- Orders and markers are issued when the ticket is built, not when the body asks: compare how many.
    return table.concat(builds, ",") .. "|" .. table.concat(lines, ",") .. "|" .. table.concat(results, ",")
        .. "|G" .. F.count(peer, "Goto") .. "|M" .. F.count(peer, "SetObjectiveOn")
end
local function fullRun(options)
    local w = F.reset()
    local peer = F.makePeer(1, 1, false, options)
    F.connect(); F.run(1)
    toCountdown(w, { peer })
    -- one human far from the blast would only add the restored line; the offline run stays put
    F.run(45)
    return summary(peer), peer, w
end
do
    local faithful = fullRun({ faithful = true, script = "Scripts/bdmisn15.lua" })
    faithful = faithful:gsub("apcamr", "bpcamr") -- intentional CR rename: the nav beacon matches the player faction
    local offline, peer = fullRun({})
    check(faithful == offline and faithful:find("SucceedMission:bd15win.des", 1, true),
        "offline completes like the faithful port:\n" .. faithful .. "\n" .. offline)
    check(wins(peer) == 1 and F.count(peer, "FailMission") == 0, "one victory, no failure")
    noEnemyTeamTwo(peer)
    check(F.count(peer, "SetAIControl", 5) == 1 and F.count(peer, "SetAIControl", 2) == 0, "AI control only for enemy team 5")
    check(F.index(peer, "SetAIControl") <= peer.chunkCalls, "SetAIControl runs at chunk root, before Start")
    local hunters = 0
    for _, b in ipairs(enemies(peer)) do hunters = hunters + 1 end
    check(hunters == 32 and F.count(peer, "Goto") == 32 and F.count(peer, "SetObjectiveOn") == 32,
        "32 attackers, each sent along its road and marked")
    -- the restored lines are offline too
    check(F.heardCount(peer, "bd15008.wav") == 1 and F.heardCount(peer, "bd15009.wav") == 1, "the countdown lines play offline")
    check(F.heardCount(peer, "bd15013.wav") == 0, "the human stayed within 800 m of the blast: no safe-distance line")
    local win = F.last(peer, "SucceedMission")
    local boom = F.last(peer, "MakeExplosion")
    check(math.abs((win[2] - boom.t) - 7.0) < 0.3, "the victory follows the blast by 5 s plus the 2 s hold for the meltdown line")
end
do -- the stock bug: on this map the engine clock counts upward, so the faithful countdown never ends
    local w = F.reset()
    w.timerUpward = true
    local peer = F.makePeer(1, 1, false, { faithful = true, script = "Scripts/bdmisn15.lua" })
    F.connect(); F.run(1)
    toCountdown(w, { peer })
    F.run(90)
    check(F.count(peer, "StartCockpitTimer") == 1 and F.count(peer, "SucceedMission") == 0 and F.count(peer, "MakeExplosion") == 0,
        "faithful port on an upward engine clock: the countdown never ends (documented stock bug)")
end

-- ------------------------------------------------------------------ teams, scrap, pilots, opening
do
    local w, p, m = setup(4, {})
    F.run(3) -- the guests receive the stream
    check(m.startDone and m.coopMissionStarted, "the leader starts the shared mission")
    check(F.count(p[1], "SetScrap", 1) == 1 and F.callsOf(p[1], "SetScrap")[1][3] == 50 + 10 * 3, "starting scrap: 50 plus 10 per guest")
    check(F.count(p[1], "SetScrap", 2) == 0, "no scrap is set on a guest's team 2")
    for team = 1, 4 do check(F.count(p[1], "SetPilot", team) == 1 and F.callsOf(p[1], "SetPilot")[1][3] == 10, "10 pilots for human team " .. team) end
    for i = 1, 4 do
        check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
        check(F.heardCount(p[i], "bd15001.wav") == 1, "briefing once on peer " .. i)
        local o = F.callsOf(p[i], "AddObjective")
        check(o[1] and o[1][2] == "bd15001.otf" and o[1][3] == "white", "objective on peer " .. i)
        check(p[i].camera == 0, "no film before the finale: peer " .. i)
    end
    guestsPassive(p)
    check(p[1].rally ~= nil and p[1].rally[0] == "bvslfd0_armory", "respawns at the Black Dog armory")
end

-- ------------------------------------------------------------------ the waves
for _, n in ipairs({ 1, 2, 4 }) do
    local w, p, m = setup(n, {})
    local e = extrasFor(n)
    local total = 0
    for index, event in ipairs(EVENTS) do
        runTo(event.at + 3)
        local mine = {}
        for _, b in ipairs(builtAt(p[1], event.where)) do mine[#mine + 1] = b end
        -- Only the events up to this one have arrived; count what this spot has received so far.
        local expectedHere = 0
        for j = 1, index do
            if EVENTS[j].where == event.where then expectedHere = expectedHere + EVENTS[j].units + e end
        end
        check(#mine == expectedHere, n .. " humans, event " .. index .. " at " .. event.where .. ": " .. #mine .. " vs " .. expectedHere)
        total = total + event.units + e
        reap()
    end
    check(#enemies(p[1]) == total, n .. " humans: every wave arrived with its extras: " .. #enemies(p[1]) .. " vs " .. total)
    check(m.allUnitsSpawned and m.numUnits == 32, "the body counts its 32 attackers")
    for _, b in ipairs(enemies(p[1])) do
        for _, q in ipairs(p) do check(q.env.GetDistance(q.player, b.h) >= 460, "no attacker is built within 460 m of any human") end
    end
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end
do -- the waves keep their time table: wave audio, then the strict delays
    local w, p, m = setup(1, {})
    runTo(19); check(#enemies(p[1]) == 0, "nothing before the first delay")
    runTo(22); check(#enemies(p[1]) == 1 and F.heardCount(p[1], "bd15002.wav") == 1, "20 s after the briefing: the west fighter and bd15002")
    runTo(62); check(#enemies(p[1]) == 7 and F.heardCount(p[1], "bd15003.wav") == 1, "40 s later: six units from the south")
    runTo(182); check(#enemies(p[1]) == 14 and F.heardCount(p[1], "bd15004.wav") == 1, "120 s later: seven from the north")
    runTo(362); check(#enemies(p[1]) == 20 and F.heardCount(p[1], "bd15005.wav") == 1, "180 s later: six from the east")
    runTo(424); check(#enemies(p[1]) == 26, "60 s later: six more from the east")
    runTo(606); check(#enemies(p[1]) == 32 and F.heardCount(p[1], "bd15006.wav") == 1 and m.allUnitsSpawned, "180 s later: the last six")
end
do -- a human on a spawn: the wave comes from another hidden approach
    local w, p, m = setup(2, {})
    F.nearTo(p[2].player, "spawn_south_wave", 100, 0)
    runTo(64)
    check(#builtAt(p[1], "spawn_south_wave") == 0 and #builtAt(p[1], "spawn_east_wave") == 6 + 1, "the south wave arrives from the east approach while a human holds its spawn")
    for _, b in ipairs(enemies(p[1])) do
        for _, q in ipairs(p) do check(q.env.GetDistance(q.player, b.h) >= 460, "still no pop-in") end
    end
    check(F.count(p[1], "Goto") >= 6, "the displaced wave still marches its own road")
end
do -- markers: every attacker, extras included, on every peer
    local w, p, m = setup(3, {})
    runTo(64)
    check(#enemies(p[1]) == 1 + 1 + 6 + 1, "west and south waves with their extras")
    F.run(2)
    check(F.count(p[1], "SetObjectiveOn") == #enemies(p[1]), "every attacker is marked on the host")
    check(F.count(p[2], "SetObjectiveOn") == #enemies(p[1]) and F.count(p[3], "SetObjectiveOn") == #enemies(p[1]), "and on every guest")
end
do -- live cap bounds the extras, never the primaries
    local w, p, m = setup(4, {})
    runTo(612) -- nothing is killed
    local total = #enemies(p[1])
    check(m.numUnits == 32 and total >= 32 and total <= 32 + 8 * 2, "all 32 primaries arrive, extras are bounded: " .. total)
    local live = 0
    for h, o in pairs(F.world().objects) do if o.alive and h:match("^built") and o.odf:match("^cv") then live = live + 1 end end
    check(live == total, "nothing died in this run")
    check(total < 32 + 8 * 2, "the live cap of 30 dropped some extras of the big overlapping waves: " .. total)
end

-- ------------------------------------------------------------------ the launch-site warning and the breach
do
    local w, p, m = setup(3, {})
    F.nearTo(p[2].player, "chin_launch", 250, 0)
    F.run(2)
    for i = 1, 3 do check(F.heardCount(p[i], "bd15010.wav") == 1, "any human near the transport draws the warning, on every peer " .. i) end
    F.run(10)
    check(F.heardCount(p[1], "bd15010.wav") == 1, "the warning plays once")
end
do -- a breach by the body's own unit: bd15011, +5 s, bd15012, defeat; never a victory
    local w, p, m = setup(2, {})
    runTo(22)
    local unit = enemies(p[1])[1].h
    F.nearTo(unit, "chin_launch", 60, 0)
    F.run(1)
    check(m.wonLost and F.heardCount(p[1], "bd15011.wav") == 1 and F.heardCount(p[2], "bd15011.wav") == 1, "a unit within 100 m of the launch site: bd15011 on every peer")
    F.run(2)
    check(F.heardCount(p[1], "bd15012.wav") == 0, "the second line waits five seconds")
    F.run(6)
    check(F.heardCount(p[1], "bd15012.wav") == 1, "bd15012")
    F.run(2)
    for i = 1, 2 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd15lose.des", "one defeat with its debrief on peer " .. i)
    end
    reap(); F.run(3)
    check(F.count(p[1], "SucceedMission") == 0, "killing the rest after a breach never wins")
end
do -- a wave due during the loss lines never spawns: the loss latch ends the mission's spawning at once
    local w, p, m = setup(2, {})
    runTo(22)
    local unit = enemies(p[1])[1].h
    F.nearTo(unit, "chin_launch", 60, 0)
    F.run(1)
    check(m.wonLost and F.count(p[1], "FailMission") == 0, "breached, the defeat still pending")
    local before = #enemies(p[1])
    m.sound4Time = F.world().now + 1
    F.run(3)
    check(#enemies(p[1]) == before, "the north wave due after the breach builds nothing")
end
do -- a breach by a mirror unit (not tracked by the body) counts too
    local w, p, m = setup(4, {})
    runTo(22)
    local tracked = {}
    for i = 1, m.numUnits do tracked[m.units[i]] = true end
    local mirror
    for _, b in ipairs(enemies(p[1])) do if not tracked[b.h] then mirror = b.h end end
    check(mirror ~= nil, "the west fighter has mirrors at four humans")
    F.nearTo(mirror, "chin_launch", 40, 0)
    F.run(1)
    check(m.wonLost and F.heardCount(p[1], "bd15011.wav") == 1, "a mirror within 100 m breaches the launch site")
end
do -- a dead attacker's stale position never breaches
    local w, p, m = setup(1, {})
    runTo(22)
    local unit = enemies(p[1])[1].h
    F.nearTo(unit, "chin_launch", 10, 0)
    F.kill(unit)
    F.run(2)
    check(not m.wonLost, "a dead unit is not a breach")
end

-- ------------------------------------------------------------------ victory, the host-counted countdown, the finale
local function finale(n, options)
    local w, p, m = setup(n, options)
    toCountdown(w, p)
    return w, p, m
end
do
    local w, p, m = finale(3, { upward = true })
    check(m.objective1Complete and not m.wonLost, "all 32 down: the defence objective is complete")
    for i = 1, 3 do
        local list = listOf(p[i])
        check(list["bd15001.otf"] == "green" and list["bd15002.otf"] == "white", "the escape objective appears on peer " .. i)
        check(F.heardCount(p[i], "bd15007.wav") == 1, "bd15007 on peer " .. i)
    end
    check(m.doingCountdown and F.count(p[1], "StartCockpitTimer") == 1, "the countdown starts")
    for i = 1, 3 do
        check(F.count(p[i], "StartCockpitTimer") == 1 and F.last(p[i], "StartCockpitTimer")[2] == 30, "every peer shows the 30 s timer: " .. i)
        check(F.heardCount(p[i], "bd15008.wav") == 1, "the restored opening line of the countdown on peer " .. i)
    end
    check(not m.doingCamera and not m.doingExplosion, "nothing before the end of the clock")
    F.run(26)
    check(not m.doingCamera, "28 s in: still no finale camera")
    F.run(3)
    check(m.doingCamera and not m.doingExplosion, "2 s from the end: the finale camera")
    for i = 1, 3 do
        check(p[i].camera == 1, "the finale shot is shared on peer " .. i)
        check(F.last(p[i], "CameraPath")[2] == "camera_finale" and F.last(p[i], "CameraPath")[3] == 2400, "the shot is camera_finale on peer " .. i)
    end
    local target = F.builds(p[1], 0, "bpcamr")
    check(#target == 1 and target[1].team == 0 and target[1].where == "spawn_explosion1", "one neutral hidden camera target at the blast")
    check(F.count(p[1], "Hide") == 1 and F.count(p[1], "SetMaxHealth") == 1, "the target is hidden and durable")
    F.run(4)
    check(m.doingExplosion, "the clock ran out although the engine counts upward")
    for i = 1, 3 do
        check(F.count(p[i], "ColorFade") == 1, "the white flash on peer " .. i)
        check(F.count(p[i], "MakeExplosion") == 1 and F.last(p[i], "MakeExplosion")[2] == "xpltrso" and F.last(p[i], "MakeExplosion")[3] == "spawn_explosion1",
            "the blast on peer " .. i)
        check(F.count(p[i], "HideCockpitTimer") == 1, "the timer hides on peer " .. i)
        check(F.heardCount(p[i], "bd15009.wav") == 1, "the restored meltdown line on peer " .. i)
    end
    check(F.heardCount(p[1], "bd15013.wav") == 0, "the humans are within 800 m of the blast: no safe-distance line")
    check(not m.objective2Complete and listOf(p[1])["bd15002.otf"] == "white", "the escape objective stays open")
    F.run(12)
    for i = 1, 3 do
        check(wins(p[i]) == 1 and F.count(p[i], "FailMission") == 0, "one shared victory on peer " .. i)
    end
    check(F.count(p[1], "BuildObject") == #enemies(p[1]) + 1, "nothing but the camera target is built after the last wave")
    guestsPassive(p)
end
do -- every human beyond 800 m: bd15013 and a green escape objective
    local w, p, m = setup(3, {})
    for i = 1, 3 do F.place(p[i].player, 2336, 98000 - 30 * i) end
    toCountdown(w, p)
    F.run(31)
    check(m.doingCamera and m.objective2Complete, "the check ran at the finale camera: all humans safe")
    for i = 1, 3 do
        check(F.heardCount(p[i], "bd15013.wav") == 1, "minimum safe distance reached, heard on peer " .. i)
        check(listOf(p[i])["bd15002.otf"] == "green", "the escape entry turns green on peer " .. i)
    end
    F.run(12)
    check(wins(p[1]) == 1, "and the mission is won")
end
do -- one human still near the blast: the nearest human decides
    local w, p, m = setup(3, {})
    F.place(p[1].player, 2336, 98000); F.place(p[2].player, 2336, 98000); F.place(p[3].player, 2420, 99500)
    toCountdown(w, p)
    F.run(31)
    check(m.doingCamera and not m.objective2Complete and F.heardCount(p[1], "bd15013.wav") == 0, "one human inside 800 m: not safe")
end
do -- the mirrors count in the victory gate
    local w, p, m = setup(4, {})
    runTo(606)
    local tracked = {}
    for i = 1, m.numUnits do tracked[m.units[i]] = true end
    local keep
    for h, o in pairs(F.world().objects) do
        if o.alive and h:match("^built") and o.odf:match("^cv") then
            if keep == nil and not tracked[h] then keep = h else o.alive = false end
        end
    end
    check(keep ~= nil, "a mirror survives")
    F.run(6)
    check(not m.objective1Complete and F.heardCount(p[1], "bd15007.wav") == 0, "a living mirror keeps the defence open")
    F.kill(keep); F.run(4)
    check(m.objective1Complete and F.heardCount(p[1], "bd15007.wav") == 1, "the last mirror down completes it")
end
do -- the lines and the objective list can be switched off by their flags (the body is unchanged)
    local f = io.open("Scripts/bd15cr.lua", "rb"); local text = f:read("*a"); f:close()
    check(text:find("local RESTORED_COUNTDOWN_LINES = true", 1, true) and text:find("local RESTORED_SAFE_DISTANCE = true", 1, true),
        "both restorations are behind a flag")
end

-- ------------------------------------------------------------------ absent narration and failures of audio
do
    local w, p, m = setup(1, { silentAudio = true })
    runTo(25)
    check(#enemies(p[1]) == 1, "without audio the first delay still runs")
    runTo(612)
    check(m.allUnitsSpawned and m.numUnits == 32, "a mission whose lines never play still runs every wave")
    reap(); F.run(40)
    check(m.doingCountdown and m.doingExplosion and wins(p[1]) == 1, "and still ends in the victory")
end
do -- a busy narrator: the delays wait for each line
    local w, p, m = setup(1, { busy = true })
    runTo(100)
    check(#enemies(p[1]) == 0 and m.sound1 ~= nil, "no wave while the briefing is still playing")
    w.audioBusy = false
    runTo(125)
    check(#enemies(p[1]) == 1, "20 s after the briefing ends: the first fighter")
end

-- ------------------------------------------------------------------ save / load
do
    local w, p, m = setup(2, {})
    runTo(66)
    local objectives, marks, lines = F.count(p[1], "AddObjective"), F.count(p[1], "SetObjectiveOn"), F.heardCount(p[1], "bd15001.wav")
    local living = #enemies(p[1])
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "AddObjective") >= objectives + 1, "a load republishes the objective list")
    check(F.count(p[1], "SetObjectiveOn") == marks + living, "a load marks every living attacker again")
    check(F.heardCount(p[1], "bd15001.wav") == lines, "a load does not replay the briefing")
    runTo(185)
    check(#builtAt(p[1], "spawn_north_wave") == 7 + 1 and #enemies(p[1]) == living + 8, "the timeline continues after a load, no wave repeats")
end
do -- a load in the countdown: the timer returns with its remaining time, the finale is not repeated
    local w, p, m = setup(2, { upward = true })
    toCountdown(w, p)
    F.run(10)
    local timers = F.count(p[1], "StartCockpitTimer")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "StartCockpitTimer") == timers + 1, "a load shows the timer again")
    local left = F.last(p[1], "StartCockpitTimer")
    check(left[2] > 10 and left[2] < 20.5 and left[3] == 10 and left[4] == 5, "with the remaining time and its warnings: " .. tostring(left[2]))
    local list = listOf(p[1], 1)
    check(list["bd15001.otf"] == "green" and list["bd15002.otf"] == "white", "the escape objective list is rebuilt")
    F.run(30)
    check(m.doingExplosion and F.count(p[1], "MakeExplosion") == 1 and wins(p[1]) == 1, "the countdown completes once after a load")
    check(F.heardCount(p[1], "bd15008.wav") == 1 and F.heardCount(p[1], "bd15007.wav") == 1, "no line is replayed")
end
do -- a load during the finale shot reopens the camera
    local w, p, m = setup(1, { upward = true })
    toCountdown(w, p)
    F.run(29)
    check(m.doingCamera and p[1].camera == 1, "the finale shot is running")
    local readies = F.count(p[1], "CameraReady")
    p[1].env.Load(p[1].env.Save())
    F.run(1)
    check(F.count(p[1], "CameraReady") == readies + 1 and p[1].camera == 1, "the running shot reopens after a load")
    F.run(10)
    check(wins(p[1]) == 1 and p[1].camera <= 1, "the mission still ends")
end
do -- a load during a breach does not replay or lose the defeat
    local w, p, m = setup(1, {})
    runTo(22)
    F.nearTo(enemies(p[1])[1].h, "chin_launch", 30, 0)
    F.run(1)
    check(m.wonLost, "breached")
    p[1].env.Load(p[1].env.Save()); F.run(12)
    check(F.count(p[1], "FailMission") == 1 and F.heardCount(p[1], "bd15011.wav") == 1, "one defeat after a load")
end

-- ------------------------------------------------------------------ leader leaves
do
    local w, p, m = setup(3, {})
    runTo(5)
    p[2].env.DeletePlayer(1); p[3].env.DeletePlayer(1)
    F.run(3)
    for i = 2, 3 do check(F.count(p[i], "FailMission") == 1, "the mission fails for guest " .. i .. " when the leader leaves") end
    check(F.count(p[1], "FailMission") == 0, "the leader itself keeps playing")
end

-- ------------------------------------------------------------------ weather: Ganymede
local function ganymede(record, mode, sites)
    return function(peer)
        local V = { Seed = 4242, Initialized = false }
        function V.Init(o)
            peer.weatherInit = o; V.Initialized = true
            record("EuropaInit", o.authority, o.send ~= nil, o.seed, o.startLevel, o.targetLevel)
            if mode == "initfail" then error("boom") end
        end
        function V.Update() if mode == "updatefail" then error("update boom") end end
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
    local w, p, m = setup(3, {})
    check(F.count(p[1], "EnvironmentInit") == 0 and m.startDone, "no weather module: the mission runs and touches no Environment")
end
do
    local sites = dofile("Scripts/CRGanymedeSitesBD15.lua")
    check(sites.mission == "bdmisn15" and #sites.vents == 6, "the generated sites carry the six geysers")
    local ventIndex = {}
    for i, v in ipairs(sites.vents) do ventIndex[v.label] = i end
    local weather = { module = function(peer, record) return ganymede(record, nil, sites)(peer) end, sites = sites }
    local w, p, m = setup(3, { weather = weather })
    check(F.count(p[1], "EuropaInit", true) == 1 and F.last(p[1], "EuropaInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.last(p[1], "EuropaInit")[5] == 1 and F.last(p[1], "EuropaInit")[6] == 1, "the moon starts quiet")
    check(F.count(p[2], "EuropaInit", false) == 1, "guests render only (not the authority)")
    check(p[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    check(F.count(p[1], "WeatherSensors", "Ganymede") == 1, "the sensor modifier is bound once")
    check(F.count(p[1], "EuropaLevel") == 0 and F.count(p[1], "EuropaPlume") == 0, "quiet before the first wave")
    runTo(22)
    check(F.count(p[1], "EuropaLevel", 2) == 1, "the first fighter: the moon stirs")
    runTo(62)
    check(F.count(p[1], "EuropaPlume", ventIndex["eggeizr10_geyser"]) == 1, "the south wave opens the south vent")
    runTo(182)
    check(F.count(p[1], "EuropaLevel", 3) == 1 and F.count(p[1], "EuropaPlume", ventIndex["eggeizr15_geyser"]) == 1
        and F.count(p[1], "EuropaQuakeCall") == 1, "the north squad: a quake and the north vent")
    runTo(362)
    check(F.count(p[1], "EuropaLevel", 4) == 1 and F.count(p[1], "EuropaPlume", ventIndex["eggeizr18_geyser"]) == 1, "the east tanks: the sky darkens")
    runTo(424)
    check(F.count(p[1], "EuropaSurgeCall") == 1, "the second east wave: a surge")
    runTo(606)
    check(F.count(p[1], "EuropaPlume", ventIndex["eggeizr14_geyser"]) == 1 and F.count(p[1], "EuropaPlume", ventIndex["eggeizr17_geyser"]) == 1
        and F.count(p[1], "EuropaQuakeCall") == 2, "the survivors' run: the western vents")
    reap(); F.run(8)
    check(F.count(p[1], "EuropaLevel", 3) == 2 and F.count(p[1], "EuropaSurgeCall") == 2, "the last attacker down: a surge over the field")
    check(F.count(p[1], "EuropaLevel", 5) == 1 and F.count(p[1], "EuropaQuakeCall") == 3, "the countdown: the worst sky")
    local plumes = F.count(p[1], "EuropaPlume")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "EuropaShutdown") >= 1 and F.count(p[1], "EuropaLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(p[1], "WeatherSensors", "Ganymede") == 2, "the sensor modifier is bound again after a load")
    check(F.count(p[1], "EuropaPlume") == plumes and F.count(p[1], "EuropaLevel", 5) == 1, "a load repeats no beat")
    F.run(33)
    check(m.doingExplosion and F.count(p[1], "EuropaQuakeCall") == 4 and F.count(p[1], "EuropaSurgeCall") == 3, "the blast: a quake and a surge")
    check(F.count(p[1], "EuropaPlume") == plumes + 2, "and the two vents near the launch site")
    check(F.count(p[1], "EuropaCreated") > 0, "new objects are offered to the weather")
end
do -- a breach darkens the sky
    local sites = dofile("Scripts/CRGanymedeSitesBD15.lua")
    local w, p, m = setup(2, { weather = { module = function(peer, record) return ganymede(record, nil, sites)(peer) end, sites = sites } })
    runTo(22)
    F.nearTo(enemies(p[1])[1].h, "chin_launch", 30, 0)
    F.run(2)
    check(F.count(p[1], "EuropaLevel", 5) == 1 and F.count(p[1], "EuropaSurgeCall") == 1, "the transport lifts off under the worst sky")
end
do -- sites module missing: no weather, never an error
    local sites = dofile("Scripts/CRGanymedeSitesBD15.lua")
    local w, p, m = setup(2, { weather = { module = function(peer, record) return ganymede(record, nil, sites)(peer) end } })
    check(F.count(p[1], "EuropaInit") == 0 and m.startDone, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local sites = dofile("Scripts/CRGanymedeSitesBD15.lua")
    local w, p, m = setup(2, { weather = { module = function(peer, record) return ganymede(record, mode, sites)(peer) end, sites = sites } })
    runTo(22)
    check(#enemies(p[1]) == 1 + 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("bdmisn15 co-op: " .. checks .. " checks passed")
