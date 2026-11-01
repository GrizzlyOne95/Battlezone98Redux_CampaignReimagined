-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and the co-op script. Engine AI, rendering, portals and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/Test-Bdmisn08Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Bdmisn08Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local function extrasFor(n) return math.min(math.floor(n / 2), 2) end
local DT = 0.5

local function films(w, hold)
    w.cameraDone = hold and {} or { path_camera_intro = true, path_portalcam = true }
end
local function setup(n, options)
    options = options or {}
    local w = F.reset()
    w.audioBusy = options.busy == true
    w.busyFile = options.busyFile
    films(w, options.hold)
    w.random = options.random or 0
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
local function run(seconds) F.run(seconds, DT) end
local function runTo(w, when) run(math.max(DT, when - w.now + 1)) end
local function since(peer, name, mark)
    local out = {}
    for i = (mark or 0) + 1, #peer.calls do
        if peer.calls[i][1] == name then out[#out + 1] = peer.calls[i] end
    end
    return out
end
local function heardAll(p, file, count)
    for i, q in ipairs(p) do check(F.heardCount(q, file) == (count or 1), "peer " .. i .. " hears " .. file .. " x" .. (count or 1)) end
end
local function guestsPassive(p)
    for i = 2, #p do
        for _, name in ipairs({"BuildObject", "BuildObjectAtPortal", "PortalOut", "PortalIn", "ActivatePortal", "DeactivatePortal",
            "SetScrap", "SetAIP", "Goto", "Follow", "Attack", "Retreat", "Stop", "GetIn", "RemovePilot", "SetPerceivedTeam"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, c in ipairs(peer.calls) do
        if c[1] == "BuildObject" then check(c[4] ~= 2, "no unit is built on the authored enemy team 2") end
        if c[1] == "BuildObjectAtPortal" then check(c[4] ~= 2, "no portal unit is built on the authored enemy team 2") end
        if c[1] == "SetPerceivedTeam" then check(c[3] ~= 2, "nothing is disguised as team 2, a human slot in co-op") end
    end
end
local function portalUnits(peer, mark)
    local out = {}
    for i = (mark or 0) + 1, #peer.calls do
        local c = peer.calls[i]
        if c[1] == "BuildObjectAtPortal" then out[#out + 1] = { h = c[2], odf = c[3], team = c[4], t = c.t } end
    end
    return out
end
local function attackers(peer, mark)
    local out = {}
    for _, b in ipairs(portalUnits(peer, mark)) do if b.odf ~= "cvapc" then out[#out + 1] = b end end
    return out
end
local function primaries(peer) -- one math.random(0, 9) pick per scripted attacker
    local n = 0
    for _, c in ipairs(peer.calls) do if c[1] == "random" and c[2] == 0 and c[3] == 9 then n = n + 1 end end
    return n
end
-- Both films, the portal powers up (the body arms the APC 90 s later).
local function powered(w) run(28) end
local function throughPortal(w, m)
    powered(w)
    runTo(w, m.apcTime); run(2)
    check(m.apc ~= nil, "the APC came through the portal")
end
local function reprogram(w, m)
    throughPortal(w, m)
    runTo(w, m.apcPilotTime1); run(2) -- the pilot gets out and walks into the portal
    check(m.pilotSpawned1 or m.apcPilotTime2 < 1e6, "the engineers' pilot is out")
    run(2)
    check(m.apcPilotTime2 < 1e6, "the pilot reached the portal")
    runTo(w, m.apcPilotTime2); run(2)
    check(m.portalReprogrammed, "the portal is reprogrammed")
end

-- ------------------------------------------------------------------ offline == faithful
local function signature(peer)
    local entries, audio = {}, {}
    for _, c in ipairs(peer.calls) do
        local n = c[1]
        if n == "BuildObject" then
            entries[#entries + 1] = "B:" .. c[3] .. ":" .. (c[4] == 5 and 2 or c[4]) .. ":" .. tostring(c[5])
        elseif n == "BuildObjectAtPortal" then
            entries[#entries + 1] = "P:" .. c[3] .. ":" .. (c[4] == 5 and 2 or c[4])
        elseif n == "SetPerceivedTeam" then
            entries[#entries + 1] = "S:" .. (c[3] == 5 and 2 or c[3])
        elseif n == "Play" or n == "Queue" or n == "AudioMessage" then
            audio[#audio + 1] = c[2] == "bd08005.wav" and "bd08006.wav" or c[2]
        elseif n == "SucceedMission" or n == "FailMission" then
            entries[#entries + 1] = n .. ":" .. tostring(c[3])
        elseif n == "AddObjective" then
            entries[#entries + 1] = "O:" .. c[2] .. ":" .. c[3]
        elseif n == "Goto" or n == "Attack" or n == "Retreat" or n == "Stop" or n == "GetIn" or n == "RemovePilot"
            or n == "PortalIn" or n == "PortalOut" or n == "ActivatePortal" or n == "DeactivatePortal" then
            entries[#entries + 1] = n
        end
    end
    table.sort(entries)
    return table.concat(entries, ","), table.concat(audio, ",")
end
local function outcome(options, scenario)
    local w = F.reset()
    films(w)
    local peer = F.makePeer(1, 1, false, options)
    F.run(1, DT)
    scenario(w, peer, peer.env.Save())
    return peer, w
end
local function board(w, m)
    -- The return pilot gets in: the engine consumes it and the APC has a pilot again.
    run(1)
    w.objects[m.apc].pilot = "cspilo"
    F.kill(m.pilot)
    run(1)
end
local scenarios = {
    -- the whole mission: waves, the APC, the engineers, the capture
    win = function(w, p, m)
        reprogram(w, m)
        w.objects[m.apc].team = 1
        run(2); w.audioBusy = true; run(2); w.audioBusy = false; run(5)
    end,
    recyclerlost = function(w, p, m) run(30); F.kill("recycler"); run(20) end,
    commandlost = function(w, p, m) run(30); F.kill("command"); run(20) end,
    apclost = function(w, p, m) throughPortal(w, m); F.kill(m.apc); run(20) end,
    portallost = function(w, p, m) powered(w); F.kill("portal"); run(5) end,
    pilotkilled = function(w, p, m)
        throughPortal(w, m)
        w.objects.portal.pos = { x = 9000, y = 40, z = 9000 } -- the pilot has a long walk
        runTo(w, m.apcPilotTime1); run(2)
        F.kill(m.pilot); run(20)
    end,
    returned = function(w, p, m)
        reprogram(w, m)
        board(w, m)
        run(30)
    end,
}
for name, scenario in pairs(scenarios) do
    local faithful = outcome({ faithful = true, script = F.FAITHFUL }, scenario)
    local offline = outcome({}, scenario)
    local fs, fa = signature(faithful)
    local os, oa = signature(offline)
    check(fs == os, "offline plays the faithful mission (" .. name .. "): " .. fs .. " / " .. os)
    check(fa == oa, "offline plays the faithful audio (" .. name .. "): " .. fa .. " / " .. oa)
    check(fs:find("Mission", 1, true) ~= nil, "the scenario reaches a result (" .. name .. ")")
end
do
    local win = outcome({}, scenarios.win)
    check(F.count(win, "SucceedMission") == 1 and F.last(win, "SucceedMission")[3] == "bd08win.des", "offline victory")
    check(F.count(win, "FailMission") == 0, "no failure after a win")
    noEnemyTeamTwo(win)
    check(F.count(win, "SetAIControl", 5) == 1 and F.count(win, "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
    local lost = outcome({}, scenarios.apclost)
    check(F.last(lost, "FailMission")[3] == "bd08lseb.des" and F.heardCount(lost, "bd08005.wav") == 1
        and F.heardCount(lost, "bd08006.wav") == 0, "offline: a shot-down APC gets the restored reprimand, then bd08lseb")
    local home = outcome({}, scenarios.returned)
    check(F.last(home, "FailMission")[3] == "bd08lsea.des" and F.heardCount(home, "bd08006.wav") == 1
        and F.heardCount(home, "bd08005.wav") == 0, "offline: an APC that escaped through the portal keeps bd08006")
    local base = outcome({}, scenarios.recyclerlost)
    check(F.last(base, "FailMission")[3] == "bd08lsea.des" and F.heardCount(base, "bd08006.wav") == 1
        and F.heardCount(base, "bd08005.wav") == 0, "offline: a lost recycler keeps bd08006")
    local portal = outcome({}, scenarios.portallost)
    check(F.last(portal, "FailMission")[3] == "bd08lsec.des", "offline: a destroyed portal is bd08lsec")
end

-- ------------------------------------------------------------------ teams, ownership, humans as the player
do
    local w, p, m = setup(4, {})
    F.runUntil(function() return m.startDone end, 30, DT)
    check(m.startDone and m.coopMissionStarted, "leader starts the shared mission")
    check(m.user == "crcca_players", "the player handle is the nearest-human token")
    check(F.count(p[1], "SetAIControl", 5) == 1 and F.count(p[1], "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
    check(F.index(p[1], "SetAIControl") <= p[1].chunkCalls, "SetAIControl runs at chunk root, before Start")
    check(F.count(p[1], "SetAIP") == 0, "the mission has no AIP")
    check(F.last(p[1], "SetScrap")[2] == 1 and F.last(p[1], "SetScrap")[3] == 100 + 10 * 3, "shared scrap grows per guest")
    check(p[1].rally ~= nil and p[1].rally[0] == "recycler", "respawn rallies on the recycler")
    for i = 1, 4 do
        check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
        check(F.heardCount(p[i], "bd08001.wav") == 1, "the briefing plays once on peer " .. i)
        check(F.count(p[i], "SetObjectiveName", "nav_portal") >= 1 and F.count(p[i], "SetObjectiveName", "nav_base") >= 1,
            "both nav names reach peer " .. i)
    end
    run(30)
    for i = 1, 4 do
        check(F.heardCount(p[i], "bd08002.wav") == 1, "the portal briefing plays once on peer " .. i)
        check(F.callsOf(p[i], "AddObjective")[1][2] == "bd08001.otf", "the containment objective reaches peer " .. i)
    end
    guestsPassive(p)
end

-- ------------------------------------------------------------------ the two films are shared; a skip is offline only
do
    local w, p, m = setup(3, { hold = true })
    F.runUntil(function() return F.count(p[1], "CameraReady") >= 1 end, 30, DT)
    run(1)
    for i = 1, 3 do
        local c = F.last(p[i], "CameraPath")
        check(c and c[2] == "path_camera_intro" and c[3] == 800 and c[4] == 1500 and p[i].camera == 1, "peer " .. i .. " is in the intro shot")
        check(w.objects[c[5]] == w.objects[p[1].player], "the intro looks at the host's ship on peer " .. i)
    end
    w.cameraDone.path_camera_intro = true; w.audioBusy = true; run(1)
    check(not m.cameraComplete[0], "the intro waits for its line as well as the path")
    w.audioBusy = false; run(1)
    check(m.cameraComplete[0], "the intro ends when the path and the line are done")
    run(26) -- the second shot opens 25 s later
    for i = 1, 3 do
        local c = F.last(p[i], "CameraPath")
        check(c[2] == "path_portalcam" and c[3] == 4000 and c[4] == 1000 and w.objects[c[5]] == w.objects.portal and p[i].camera == 1,
            "peer " .. i .. " watches the portal power up")
    end
    check(m.activateTime < 1e6 and m.apcTime < 1e6, "the portal and the APC are armed when the second shot opens")
    w.cameraDone.path_portalcam = true; run(2)
    check(m.cameraComplete[1], "the portal shot ends on arrival")
    run(2)
    for i = 1, 3 do check(p[i].camera == 0, "film cameras balanced on peer " .. i) end
    heardAll(p, "bd08001.wav"); heardAll(p, "bd08002.wav")
    check(F.count(p[1], "PortalOut") >= 1 and F.count(p[1], "ActivatePortal") >= 1, "the portal is powered up outwards")
end
do -- a host's skip never ends the shared shot, and never hangs it either
    local w, p, m = setup(3, { hold = true })
    F.runUntil(function() return F.count(p[1], "CameraReady") >= 1 end, 30, DT)
    w.cancelFor = 1; run(1); w.cancelFor = nil
    check(not m.cameraComplete[0] and F.count(p[1], "StopAudioMessage") == 0, "a skip never ends the shared intro in a network game")
    w.audioBusy = true
    run(6)
    check(not m.cameraComplete[0], "the shot is still running for the guests")
    check(p[2].camera == 1 and p[3].camera == 1, "the guests keep their shot ")
    run(8)
    check(not m.cameraComplete[0], "...and the line still gates the end")
    w.audioBusy = false; run(1)
    check(m.cameraComplete[0], "after the skip the intro ends with its line instead of hanging on a missing arrival")
    run(26)
    check(m.cameraReady[1] and not m.cameraComplete[1], "the portal shot is open")
    w.cancelFor = 1; run(1); w.cancelFor = nil
    check(not m.cameraComplete[1], "the skip does not end the portal shot at once")
    run(12)
    check(m.cameraComplete[1], "the portal shot ends 12 s into the shot after a host skip")
    run(2)
    for i = 1, 3 do check(p[i].camera == 0, "film cameras balanced on peer " .. i) end
end
do -- offline: the same layer, skippable
    local w, p, m = setup(1, { hold = true })
    run(1)
    check(p[1].camera == 1, "offline intro opens")
    w.cancel = true; run(1)
    check(F.count(p[1], "StopAudioMessage") >= 1 and m.cameraComplete[0], "offline skip stops the line and ends the intro")
end

-- ------------------------------------------------------------------ the attack waves, 1-4 humans
for n = 1, 4 do
    local w, p, m = setup(n, {})
    local e = extrasFor(n)
    powered(w)
    run(14)
    local list = attackers(p[1])
    check(#list > 0, n .. " human(s): the portal is attacking")
    check(#list == primaries(p[1]) * (1 + e) - 0 or #list >= primaries(p[1]) * (1 + e) - 2 * e,
        n .. " human(s): each attacker is mirrored by " .. e .. " extras (" .. #list .. " vs " .. primaries(p[1]) .. ")")
    for _, b in ipairs(list) do check(b.team == 5, "portal attackers are team 5") end
    -- the first tick: the primary, then its extras 2 s apart, all on the primary's path
    local first = list[1].t
    local ticks = {}
    for _, b in ipairs(list) do
        if b.t <= first + 2.5 * e + 0.01 then ticks[#ticks + 1] = b end
    end
    check(#ticks >= 1 + e, n .. " human(s): the first tick's extras follow")
    check(ticks[1].t == first and (e == 0 or ticks[2].t >= first + 1.9), n .. " human(s): extras are staggered, not stacked on the primary")
    local paths = {}
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do paths[c[2]] = c[3] end
    for i = 1, 1 + e do check(paths[ticks[i].h] == "attack_path1", n .. " human(s): unit " .. i .. " takes the primary's path") end
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end
do -- the other half of the path split and another unit type
    local w, p, m = setup(3, { random = 60 })
    powered(w); run(8)
    local list = attackers(p[1])
    check(#list >= 2 and list[1].odf == "cvtnk", "the weighted pick follows the deterministic roll")
    local paths = {}
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do paths[c[2]] = c[3] end
    check(paths[list[1].h] == "attack_path2" and paths[list[2].h] == "attack_path2", "the extra mirrors a second-path attacker")
end
do -- live cap: extras are the only units dropped
    local w, p, m = setup(4, {})
    m.crcca.r = { live = {} }
    for i = 1, 12 do m.crcca.r.live[i] = F.spawn("cvfigh", 5, 9000 + i, 9000) end
    powered(w); run(14)
    check(primaries(p[1]) >= 1 and #attackers(p[1]) == primaries(p[1]), "at the live cap every primary still comes, the extras are dropped")
end
do -- a save/load between the primary and its extras neither loses nor duplicates them
    local w, p, m = setup(2, {})
    powered(w)
    F.runUntil(function() return #attackers(p[1]) >= 1 end, 60, DT)
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); run(2)
    m = p[1].env.Save()
    local before = #attackers(p[1])
    run(1.5)
    check(#attackers(p[1]) <= primaries(p[1]) * 2, "a load keeps the queued extras without duplicating them")
    check(m.crcca.r ~= nil, "the queue is part of the saved state")
end
do -- waves stop for good once the portal is reprogrammed; no extras arrive afterwards
    local w, p, m = setup(4, {})
    reprogram(w, m)
    local before = #portalUnits(p[1])
    run(60)
    check(#portalUnits(p[1]) == before, "nothing comes through the reprogrammed portal")
    check(m.crcca.r.extras == nil, "the extra queue is cleared")
end

-- ------------------------------------------------------------------ the engineers' APC and the capture by any human
for n = 1, 4 do
    local w, p, m = setup(n, {})
    throughPortal(w, m)
    check(F.team(m.apc) == 5, n .. " human(s): the APC is a team-5 unit")
    check(F.count(p[1], "Goto", m.apc) == 1 and F.last(p[1], "Goto")[3] == "portal_out", n .. " human(s): the APC leaves the portal")
    runTo(w, m.apcPilotTime1); run(2)
    check(w.objects[m.apc].pilot == nil and w.objects[m.apc].perceived == 0, n .. " human(s): the empty APC looks neutral")
    heardAll(p, "bd08003.wav")
    for i = 1, n do
        check(F.count(p[i], "SetObjectiveOn") >= 1, "the APC marker reaches peer " .. i)
        check(F.count(p[i], "AddObjective", "bd08002.otf") >= 1, "the capture objective reaches peer " .. i)
    end
    run(4)
    runTo(w, m.apcPilotTime2); run(2)
    check(m.portalReprogrammed and F.count(p[1], "DeactivatePortal") == 1, n .. " human(s): the portal shuts down")
    heardAll(p, "bd08004.wav")
    check(F.team(m.pilot) == 5, "the return pilot is a team-5 unit")
    board(w, m)
    check(w.objects[m.apc].perceived == 5 and not m.pilotBoarding, n .. " human(s): the boarded APC looks like the co-op enemy, not team 2")
    -- capture by the highest human team
    w.objects[m.apc].team = n
    run(2); w.audioBusy = true; run(2)
    check(m.apcCommandeered and m.won, n .. " human(s): team " .. n .. " capturing the APC wins")
    w.audioBusy = false; run(5)
    for i = 1, n do
        check(F.count(p[i], "SucceedMission") == 1 and F.last(p[i], "SucceedMission")[3] == "bd08win.des", "one shared victory on peer " .. i)
        check(F.count(p[i], "FailMission") == 0, "no failure after the win on peer " .. i)
    end
    heardAll(p, "bd08007.wav")
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end
do -- an APC still owned by the enemy is no victory
    local w, p, m = setup(3, {})
    reprogram(w, m)
    board(w, m)
    check(not m.apcCommandeered and not m.won, "an enemy-owned APC does not win")
end
do -- the engineers' pilot meets an APC with a pilot: it attacks the NEAREST human
    local w, p, m = setup(4, {})
    throughPortal(w, m)
    runTo(w, m.apcPilotTime1); run(2); run(2)
    F.place(m.apc, 4000, 4000)
    runTo(w, m.apcPilotTime2); run(1)
    check(m.pilotSpawned2 or m.portalReprogrammed, "the return pilot is out")
    F.place(p[3].player, 1000, 100000)
    F.place(m.pilot, 1002, 100001)
    w.objects[m.apc].pilot = "cspilo"
    F.nearTo(m.apc, m.pilot, 3, 0)
    run(2)
    local attack = F.last(p[1], "Attack")
    check(attack and attack[2] == m.pilot and attack[3] == p[3].player, "the pilot attacks the nearest human (team 3), not a token")
    check(F.count(p[1], "GetIn") == 0, "...and does not board the occupied APC")
end

-- ------------------------------------------------------------------ the unused voice line: bd08005 for a shot-down APC
do
    local w, p, m = setup(3, {})
    throughPortal(w, m)
    F.kill(m.apc); run(15)
    heardAll(p, "bd08005.wav"); heardAll(p, "bd08006.wav", 0)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd08lseb.des", "one shared APC-loss failure on peer " .. i)
    end
end
do -- base and APC lost in the same frame: the base line wins
    local w, p, m = setup(2, {})
    throughPortal(w, m)
    F.kill(m.apc); F.kill("recycler"); run(15)
    heardAll(p, "bd08006.wav"); heardAll(p, "bd08005.wav", 0)
    check(F.last(p[1], "FailMission")[3] == "bd08lsea.des", "...with the base debrief")
end
do -- the engineers' APC escaping through the portal is not a shot-down APC
    local w, p, m = setup(2, {})
    reprogram(w, m)
    board(w, m)
    run(30)
    heardAll(p, "bd08006.wav"); heardAll(p, "bd08005.wav", 0)
    check(F.last(p[1], "FailMission")[3] == "bd08lsea.des" and m.apc == nil, "the APC is gone and the base debrief is shown")
end
do -- the restoration can be switched off
    local f = assert(io.open("Scripts/bdmisn" .. "08cr.lua", "rb")); local source = f:read("*a"); f:close()
    check(source:find("local RESTORED_APC_LOSS_VOICE = true", 1, true), "the restoration has its flag")
    source = source:gsub("local RESTORED_APC_LOSS_VOICE = true", "local RESTORED_APC_LOSS_VOICE = false", 1)
    local saved = F.SCRIPT
    local path = os.tmpname()
    local out = assert(io.open(path, "wb")); out:write(source); out:close()
    F.SCRIPT = path
    local w, p, m = setup(1, {})
    F.SCRIPT = saved
    os.remove(path)
    throughPortal(w, m)
    F.kill(m.apc); run(15)
    check(F.heardCount(p[1], "bd08006.wav") == 1 and F.heardCount(p[1], "bd08005.wav") == 0, "RESTORED_APC_LOSS_VOICE = false is the stock audio")
end

-- ------------------------------------------------------------------ other results
do -- the recycler lost
    local w, p, m = setup(3, {})
    run(30)
    F.kill("recycler"); run(15)
    heardAll(p, "bd08006.wav")
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd08lsea.des", "one shared recycler-loss failure on peer " .. i)
        check(F.count(p[i], "SucceedMission") == 0, "no victory after the loss")
    end
    local before = #portalUnits(p[1])
    run(60)
    check(#portalUnits(p[1]) == before, "nothing comes through the portal after the loss")
end
do -- the portal destroyed
    local w, p, m = setup(3, {})
    powered(w); F.kill("portal"); run(6)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd08lsec.des", "one shared portal-loss failure on peer " .. i)
    end
end
do -- the pilot is killed on the way to the portal
    local w, p, m = setup(2, {})
    throughPortal(w, m)
    w.objects.portal.pos = { x = 9000, y = 40, z = 9000 }
    runTo(w, m.apcPilotTime1); run(2)
    check(m.pilotSpawned1, "the pilot is walking")
    F.kill(m.pilot); run(15)
    heardAll(p, "bd08006.wav")
    check(F.last(p[1], "FailMission")[3] == "bd08lsea.des", "the engineers' pilot lost: the base debrief")
end

-- ------------------------------------------------------------------ saves during the films, leader leaves
do -- a load in the intro ends it and starts the portal sequence
    local w, p, m = setup(3, { hold = true })
    run(3)
    check(p[1].camera == 1, "the intro is running")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); run(3)
    m = p[1].env.Save()
    check(m.cameraComplete[0] and m.secondCameraTime < 1e6, "the intro ends after a load")
    for i = 1, 3 do check(p[i].camera == 0, "no camera is left open on peer " .. i) end
    check(F.heardCount(p[1], "bd08001.wav") == 1, "the first line is not replayed")
    run(30)
    check(m.cameraReady[1], "the portal shot follows")
end
do -- a load in the portal shot ends it and keeps the armed timers
    local w, p, m = setup(2, { hold = true })
    w.cameraDone.path_camera_intro = true
    run(30)
    check(m.cameraReady[1] and not m.cameraComplete[1], "the portal shot is running")
    local armed = m.apcTime
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); run(3)
    m = p[1].env.Save()
    check(m.cameraComplete[1] and m.apcTime == armed, "the portal shot ends after a load and the APC stays armed")
    check(F.heardCount(p[1], "bd08002.wav") == 1, "the line is not replayed")
end
do
    local w, p, m = setup(3, {})
    for i = 2, 3 do p[i].env.DeletePlayer(1) end
    run(3)
    for i = 2, 3 do check(F.count(p[i], "FailMission") == 1, "the mission fails for guest " .. i .. " when the leader leaves") end
    check(F.count(p[1], "FailMission") == 0, "the leader itself keeps playing")
end

do -- a load keeps the objectives, the nav names and the APC marker of the current stage
    local function afterLoad(w, p, expect, marker)
        local mark, marks = #p[1].calls, {}
        for i, q in ipairs(p) do marks[i] = #q.calls end
        for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
        F.connect(); run(3)
        local m = p[1].env.Save()
        local list = {}
        for i = mark + 1, #p[1].calls do
            local c = p[1].calls[i]
            if c[1] == "AddObjective" then list[#list + 1] = c[2] .. "/" .. c[3] end
        end
        check(table.concat(list, ",") == expect, "the objectives are republished after a load: " .. table.concat(list, ",") .. " vs " .. expect)
        check(#since(p[1], "SetObjectiveName", mark) == 2, "the nav names are republished after a load")
        local on = since(p[1], "SetObjectiveOn", mark)
        if marker then
            check(#on == 1 and on[1][2] == m.apc, "the APC marker is republished after a load")
        else
            check(#on == 0, "no APC marker before the APC exists")
        end
        for i = 2, #p do
            check(#since(p[i], "SetObjectiveOn", marks[i]) == #on, "peer " .. i .. " gets the same marker")
        end
        run(2)
        check(#since(p[1], "AddObjective", mark) == #list, "the republish happens once")
    end
    local w, p, m = setup(2, {})
    powered(w)
    afterLoad(w, p, "bd08001.otf/white", false)
    w, p, m = setup(2, {})
    throughPortal(w, m); runTo(w, m.apcPilotTime1); run(2)
    afterLoad(w, p, "bd08001.otf/white,bd08002.otf/white", true)
    w, p, m = setup(2, {})
    reprogram(w, m)
    afterLoad(w, p, "bd08002.otf/green,bd08003.otf/white", true)
end
do -- a load in the intro waits for the opening before it publishes objectives (none exist yet)
    local w, p, m = setup(2, { hold = true })
    run(3)
    local mark = #p[1].calls
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); run(3)
    check(#since(p[1], "AddObjective", mark) == 0 and #since(p[1], "SetObjectiveOn", mark) == 0, "nothing is published before the portal shot")
end
do -- a nil audio handle (no line played) never strands the win or the loss
    local w, p, m = setup(1, {})
    reprogram(w, m)
    board(w, m)
    w.nilAudio = true -- the engine returns no handle for a line
    w.objects[m.apc].team = 1
    run(5)
    check(m.won and F.count(p[1], "SucceedMission") == 1 and F.last(p[1], "SucceedMission")[3] == "bd08win.des",
        "a nil win line still ends the mission in victory")
    w, p, m = setup(1, {})
    w.nilAudio = true -- the engine returns no handle for a line
    run(30); F.kill("recycler"); run(10)
    check(F.count(p[1], "FailMission") == 1 and F.last(p[1], "FailMission")[3] == "bd08lsea.des", "a nil loss line still fails the mission")
end
do -- a skip still latched from the intro does not end the portal shot early
    local w, p, m = setup(3, { hold = true })
    F.runUntil(function() return F.count(p[1], "CameraReady") >= 1 end, 30, DT)
    w.cancelFor = 1; run(1)
    run(14) -- the intro ends 12 s after the skip, with its line done
    check(m.cameraComplete[0], "the intro ended after the skip")
    run(26)
    check(m.cameraReady[1] and not m.cameraComplete[1], "the portal shot is open while the cancel is still latched")
    run(20)
    check(not m.cameraComplete[1], "a cancel latched from the intro never ends the portal shot")
    w.cancelFor = nil; run(1)
    w.cancelFor = 1; run(1); w.cancelFor = nil
    run(13)
    check(m.cameraComplete[1], "a fresh skip during the portal shot still ends it after 12 s")
end

-- ------------------------------------------------------------------ weather: absent, present, broken
do
    local w, p, m = setup(3, {})
    check(F.count(p[1], "EnvironmentInit") == 0 and m.startDone, "no weather module: the mission runs and touches no Environment")
    local printed = false
    for _, c in ipairs(p[1].calls) do if c[1] == "print" and tostring(c[2]):find("weather disabled", 1, true) then printed = true end end
    check(printed, "missing weather is logged, not fatal")
end
local function europa(record, mode)
    return function(peer)
        local V = { Seed = 4242, Initialized = true }
        local vents = dofile("Scripts/CRGanymedeSitesBD08.lua").vents
        function V.Init(o)
            peer.init = o
            record("EuropaInit", o.authority, o.send ~= nil, o.seed)
            if mode == "initfail" then error("boom") end
        end
        function V.Update(dt)
            if peer.init and peer.init.authority and peer.init.send and not V.sent then
                V.sent = true; peer.init.send("EuropaPlume", 1, 2, 3)
            end
            if mode == "updatefail" then error("update boom") end
        end
        function V.AnnounceState() record("EuropaAnnounce") end
        function V.ApplyNetEvent(op, ...) record("EuropaEvent", op, ...) end
        function V.SetTargetLevel(n) record("EuropaLevel", n) end
        function V.GetVentSites() return vents end
        function V.TriggerPlume(index) record("EuropaPlumeAt", index) end
        function V.Quake(strength, duration) record("EuropaQuakeCall", strength, duration) end
        function V.Surge(duration, strength) record("EuropaSurgeCall", duration, strength) end
        function V.ReleaseForcedLevel() record("EuropaRelease") end
        function V.OnObjectCreated(h) record("EuropaCreated", h) end
        function V.Save() return { saved = true } end
        function V.Load(s) record("EuropaLoad", s and s.saved) end
        function V.Shutdown() record("EuropaShutdown") end
        return V
    end
end
do
    local sites = dofile("Scripts/CRGanymedeSitesBD08.lua")
    check(sites.mission == "bdmisn08" and #sites.vents == 3 and sites.vents[1].label == "eggeizr17_geyser",
        "the generated sites carry the three geysers of the base")
    local weather = { module = function(peer, record) return europa(record)(peer) end, sites = sites }
    local w, p, m = setup(3, { weather = weather })
    check(F.count(p[1], "EuropaInit", true) == 1 and F.last(p[1], "EuropaInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.count(p[2], "EuropaInit", false) == 1, "guests render only (not the authority)")
    check(F.count(p[1], "EuropaAnnounce") == 1 and F.count(p[2], "EuropaAnnounce") == 0, "the leader announces its weather state once")
    local env = F.last(p[1], "EnvironmentInit")[2]
    check(F.count(p[1], "EnvironmentInit") == 1 and env.lightingMode == "orbit", "Jupiter-lit orbit lighting is initialised")
    check(F.count(p[1], "WeatherSensors", "Ganymede") == 1 and F.count(p[2], "WeatherSensors", "Ganymede") == 1,
        "the weather slows radar on every peer, once")
    for i = 2, 3 do
        local e = F.last(p[i], "EuropaEvent")
        check(e and e[2] == "EuropaPlume" and e[3] == 1 and e[4] == 2 and e[5] == 3, "weather events reach guest " .. i)
    end
    check(p[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    check(F.count(p[1], "EuropaLevel") == 0, "calm until the story moves")
    powered(w)
    check(F.count(p[1], "EuropaLevel", 2) == 1 and F.count(p[1], "EuropaSurgeCall") == 1 and F.count(p[1], "EuropaPlumeAt", 1) == 1,
        "the portal powering up stirs the sky and wakes a vent")
    check(F.count(p[1], "EuropaCreated") > 0, "new objects are offered to the weather")
    check(F.count(p[1], "EuropaLevel", 3) == 0, "...but the APC has not come yet")
    runTo(w, m.apcTime); run(2)
    check(F.count(p[1], "EuropaLevel", 3) == 1 and F.count(p[1], "EuropaLevel", 4) == 0, "the APC coming through raises the weather")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); run(3)
    check(F.count(p[1], "EuropaShutdown") >= 1 and F.count(p[1], "EuropaLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(p[1], "EuropaLevel", 2) == 1 and F.count(p[1], "EuropaLevel", 3) == 1, "beats already played are not replayed after a load")
    m = p[1].env.Save()
    runTo(w, m.apcPilotTime1); run(4)
    runTo(w, m.apcPilotTime2); run(2)
    check(F.count(p[1], "EuropaLevel", 4) == 1 and F.count(p[1], "EuropaQuakeCall") == 1 and F.count(p[1], "EuropaSurgeCall") == 2
        and F.count(p[1], "EuropaPlumeAt", 2) == 1 and F.count(p[1], "EuropaPlumeAt", 3) == 1,
        "the reprogrammed portal brings the storm, a quake, a surge and the base vents")
    board(w, m)
    w.objects[m.apc].team = 2
    run(2); w.audioBusy = true; run(2); w.audioBusy = false; run(4)
    check(F.count(p[1], "EuropaRelease") == 1 and F.count(p[1], "EuropaLevel", 1) == 1, "the capture eases the weather")
end
do -- sites module missing: no weather, never an error
    local w, p, m = setup(2, { weather = { module = function(peer, record) return europa(record)(peer) end } })
    check(F.count(p[1], "EuropaInit") == 0 and m.startDone, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local w, p, m = setup(2, { weather = { module = function(peer, record) return europa(record, mode)(peer) end,
        sites = dofile("Scripts/CRGanymedeSitesBD08.lua") } })
    reprogram(w, m)
    board(w, m)
    w.objects[m.apc].team = 2
    run(2); w.audioBusy = true; run(2); w.audioBusy = false; run(4)
    check(F.count(p[1], "SucceedMission") == 1 and F.count(p[2], "SucceedMission") == 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("bdmisn08 co-op: " .. checks .. " checks passed")
