-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and the co-op script. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/Test-Bdmisn13Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Bdmisn13Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local function extrasFor(n) return math.min(math.floor(n / 2), 2) end
local DT = 0.5
local WAVE_TIME = { 180, 600, 900, 1800 }
local WAVE_SIZE = { 7, 6, 9, 6 }
local GUARD_ODFS = {
    { "cvfigh", "cvfigh", "cvltnk", "cvltnk" }, { "cvltnk", "cvltnk", "cvltnk", "cvltnk" },
    { "cvfigh", "cvfigh", "cvrckt", "cvrckt" }, { "cvtnk", "cvtnk", "cvltnk", "cvltnk" },
    { "cvfigh", "cvfigh", "cvfigh", "cvfigh" }, { "cvhtnk", "cvhtnk", "cvfigh", "cvfigh" },
}

local function setup(n, options)
    options = options or {}
    local w = F.reset()
    w.audioBusy = options.busy == true
    w.cameraDone = options.hold and {} or { camera_intro = true }
    w.stuckTimer = options.stuck
    if options.stage then options.stage(w) end
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    if options.place then options.place(p) end
    F.connect(); F.run(1)
    local m = p[1].env.Save()
    F.runUntil(function() return m.startDone end, 30, DT)
    return w, p, m
end
local function run(seconds) F.run(seconds, DT) end
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
        for _, name in ipairs({"BuildObject", "SetScrap", "SetAIP", "Goto", "Defend2", "Follow", "Attack", "Retreat", "Stop"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, c in ipairs(peer.calls) do
        if c[1] == "BuildObject" then check(c[4] ~= 2, "no unit is built on the authored enemy team 2") end
    end
end
-- A silo that dies: recycled by a team (or not recycled at all when team is nil).
local function silo(w, i, team)
    F.kill("chin_silo" .. i)
    w.objects["chin_silo" .. i].recycledBy = team
end
local function recycleAll(w, teamOf)
    for i = 1, 6 do silo(w, i, teamOf and teamOf(i) or 1) end
end
local function chinBuilds(peer, wherePrefix)
    local out = {}
    for _, b in ipairs(F.builds(peer)) do
        if wherePrefix == nil or b.where:sub(1, #wherePrefix) == wherePrefix then out[#out + 1] = b end
    end
    return out
end
local function ordersOf(peer, name)
    local map = {}
    for _, c in ipairs(F.callsOf(peer, name)) do map[c[2]] = c[3] end
    return map
end
local function lastFail(peer) local c = F.last(peer, "FailMission"); return c and c[3] end
local function lastWin(peer) local c = F.last(peer, "SucceedMission"); return c and c[3] end

-- ------------------------------------------------------------------ offline == faithful
local function signature(peer)
    local entries, audio = {}, {}
    for _, c in ipairs(peer.calls) do
        local n = c[1]
        if n == "BuildObject" then
            entries[#entries + 1] = "B:" .. c[3] .. ":" .. (c[4] == 5 and 2 or c[4]) .. ":" .. tostring(c[5])
        elseif n == "Goto" or n == "Defend2" then
            entries[#entries + 1] = n .. ":" .. tostring(c[3])
        elseif n == "Play" or n == "Queue" or n == "AudioMessage" then
            if c[2] ~= "bd13006.wav" and c[2] ~= "bd13007.wav" then audio[#audio + 1] = c[2] end
        elseif n == "SucceedMission" or n == "FailMission" then
            entries[#entries + 1] = n .. ":" .. tostring(c[3])
        elseif n == "AddObjective" then
            entries[#entries + 1] = "O:" .. c[2] .. ":" .. c[3]
        elseif n == "StartCockpitTimer" then
            entries[#entries + 1] = "T:" .. c[2] .. ":" .. c[3] .. ":" .. c[4]
        elseif n == "HideCockpitTimer" then
            entries[#entries + 1] = "H"
        elseif n == "SetObjectiveName" then
            entries[#entries + 1] = "N:" .. tostring(c[2]) .. ":" .. tostring(c[3])
        elseif n == "SetScrap" or n == "SetPilot" then
            entries[#entries + 1] = n .. ":" .. c[2] .. ":" .. c[3]
        end
    end
    table.sort(entries)
    return table.concat(entries, ","), table.concat(audio, ",")
end
local function outcome(options, scenario)
    local w = F.reset()
    w.cameraDone = { camera_intro = true }
    local peer = F.makePeer(1, 1, false, options)
    F.run(1, DT)
    scenario(w, peer, peer.env.Save())
    return peer, w
end
local function finishLine(w) w.audioBusy = true; run(2); w.audioBusy = false; run(4) end
local scenarios = {
    win = function(w, p, m) run(10); recycleAll(w); run(3); F.kill("chin_recycler"); run(2); finishLine(w) end,
    recyclerlost = function(w, p, m) run(30); F.kill("recycler"); finishLine(w) end,
    silolost = function(w, p, m) run(30); silo(w, 2, nil); run(10) end,
    earlystrike = function(w, p, m) run(30); w.objects.chin_recycler.health = 0.5; run(10) end,
    timeout = function(w, p, m) run(2720); run(15) end,
    recycledintime = function(w, p, m) run(1000); recycleAll(w); run(1800) end,
}
for name, scenario in pairs(scenarios) do
    local faithful = outcome({ faithful = true, script = F.FAITHFUL }, scenario)
    local offline = outcome({}, scenario)
    local fs, fa = signature(faithful)
    local os, oa = signature(offline)
    check(fs == os, "offline plays the faithful mission (" .. name .. "): " .. fs .. " / " .. os)
    check(fa == oa, "offline plays the faithful audio (" .. name .. "): " .. fa .. " / " .. oa)
    if name ~= "recycledintime" then check(fs:find("Mission", 1, true) ~= nil, "the scenario reaches a result (" .. name .. ")") end
end
do
    local win = outcome({}, scenarios.win)
    check(lastWin(win) == "bd13win.des" and F.count(win, "FailMission") == 0, "offline victory")
    noEnemyTeamTwo(win)
    check(F.count(win, "SetAIControl", 5) == 1 and F.count(win, "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
    local killed = outcome({}, scenarios.silolost)
    check(lastFail(killed) == "bd13lsec.des" and F.heardCount(killed, "bd13006.wav") == 1, "offline: a destroyed silo plays the restored bd13006")
    local early = outcome({}, scenarios.earlystrike)
    check(lastFail(early) == "bd13lsed.des" and F.heardCount(early, "bd13007.wav") == 1, "offline: an early strike plays the restored bd13007")
    local base = outcome({}, scenarios.recyclerlost)
    check(lastFail(base) == "bd13lseb.des" and F.heardCount(base, "bd13004.wav") == 1 and F.heardCount(base, "bd13006.wav") == 0,
        "offline: the lost recycler keeps bd13004")
    local timeout = outcome({}, scenarios.timeout)
    check(lastFail(timeout) == "bd13lsea.des" and F.heardCount(timeout, "bd13005.wav") == 1, "offline: the deadline plays bd13005")
    local stuck = outcome({ faithful = true, script = F.FAITHFUL }, function(w, p, m) w.stuckTimer = true; scenarios.timeout(w, p, m) end)
    check(F.count(stuck, "FailMission") == 0, "the faithful port on a map whose class restarts the timer never expires (the stock bug)")
    local fixed = outcome({}, function(w, p, m) w.stuckTimer = true; scenarios.timeout(w, p, m) end)
    check(lastFail(fixed) == "bd13lsea.des", "the CR layer counts the 45 minutes itself on that map")
end

-- ------------------------------------------------------------------ teams, scrap, the briefing
do
    local w, p, m = setup(4, {})
    run(3)
    check(m.startDone and m.coopMissionStarted, "leader starts the shared mission")
    check(m.user == "crcca_players", "the player handle is the nearest-human token")
    check(F.count(p[1], "SetAIControl", 5) == 1 and F.count(p[1], "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
    check(F.index(p[1], "SetAIControl") <= p[1].chunkCalls, "SetAIControl runs at chunk root, before Start")
    check(F.count(p[1], "SetAIP") == 0, "the mission has no AIP")
    check(F.last(p[1], "SetScrap")[2] == 1 and F.last(p[1], "SetScrap")[3] == 30 + 10 * 3, "shared scrap grows per guest")
    local pilots = {}
    for _, c in ipairs(F.callsOf(p[1], "SetPilot")) do pilots[c[2]] = c[3] end
    check(pilots[1] == 10 and pilots[2] == 10 and pilots[3] == 10 and pilots[4] == 10, "ten pilots for every human team")
    check(p[1].rally ~= nil and p[1].rally[0] == "recycler", "respawn rallies on the recycler")
    for i = 1, 4 do
        check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
        check(F.heardCount(p[i], "bd13001.wav") == 1, "the briefing plays once on peer " .. i)
        check(F.count(p[i], "StartCockpitTimer") == 1 and F.last(p[i], "StartCockpitTimer")[2] == 2700
            and F.last(p[i], "StartCockpitTimer")[3] == 30 and F.last(p[i], "StartCockpitTimer")[4] == 10, "the 45 minute timer is shown on peer " .. i)
        for s = 1, 6 do
            check(F.count(p[i], "SetObjectiveName", "nav_chin_silo" .. s) >= 1, "scrap field " .. s .. " is named on peer " .. i)
        end
    end
    run(2)
    for i = 1, 4 do
        local first = F.callsOf(p[i], "AddObjective")[1]
        check(first and first[2] == "bd13001.otf" and first[3] == "white", "the objective reaches peer " .. i)
        check(p[i].camera == 0, "film cameras balanced on peer " .. i)
    end
    guestsPassive(p)
end

-- ------------------------------------------------------------------ the intro is shared; a skip is offline only
do
    local w, p, m = setup(3, { hold = true })
    F.runUntil(function() return F.count(p[1], "CameraReady") >= 1 end, 30, DT)
    run(1)
    for i = 1, 3 do
        local c = F.last(p[i], "CameraPath")
        check(c and c[2] == "camera_intro" and c[3] == 500 and c[4] == 1500 and p[i].camera == 1, "peer " .. i .. " is in the intro shot")
        check(w.objects[c[5]] == w.objects.chin_silo6, "the intro looks at the last silo on peer " .. i)
    end
    w.cameraDone.camera_intro = true; w.audioBusy = true; run(1)
    check(not m.cameraComplete[1], "the intro waits for its line as well as the path")
    w.audioBusy = false; run(1)
    check(m.cameraComplete[1], "the intro ends when the path and the line are done")
    run(2)
    for i = 1, 3 do check(p[i].camera == 0, "film cameras balanced on peer " .. i) end
    heardAll(p, "bd13001.wav")
end
do -- a host's skip never ends the shared shot, and never hangs it either
    local w, p, m = setup(3, { hold = true })
    F.runUntil(function() return F.count(p[1], "CameraReady") >= 1 end, 30, DT)
    run(1)
    w.audioBusy = true
    w.cancelFor = 1; run(1); w.cancelFor = nil
    check(not m.cameraComplete[1] and F.count(p[1], "StopAudioMessage") == 0, "a skip never ends the shared intro in a network game")
    run(6)
    check(not m.cameraComplete[1] and p[2].camera == 1 and p[3].camera == 1, "the line still gates the end and the guests keep their shot")
    w.audioBusy = false; run(1)
    check(m.cameraComplete[1], "after the skip the intro ends with its line instead of hanging on a missing arrival")
    run(2)
    for i = 1, 3 do check(p[i].camera == 0, "film cameras balanced on peer " .. i) end
end
do -- a skip still latched when the shot begins is not a skip of this shot
    local w, p, m = setup(2, { hold = true, stage = function(w) w.cancelFor = 1 end })
    run(20)
    check(not m.cameraComplete[1], "a cancel latched before the shot never ends it")
    w.cancelFor = nil; run(1)
    w.cancelFor = 1; run(2); w.cancelFor = nil
    check(m.cameraComplete[1], "a fresh skip during the shot still ends it")
end
do -- offline: the same layer, skippable
    local w, p, m = setup(1, { hold = true })
    run(1)
    check(p[1].camera == 1, "offline intro opens")
    w.cancel = true; run(1)
    check(F.count(p[1], "StopAudioMessage") >= 1 and m.cameraComplete[1], "offline skip stops the line and ends the intro")
    run(2)
    check(p[1].camera == 0, "the camera is balanced after the skip")
end

-- ------------------------------------------------------------------ the guards and the waves, 1-4 humans
for n = 1, 4 do
    local w, p, m = setup(n, {})
    local e = extrasFor(n)
    run(20)
    local guards = {}
    for _, b in ipairs(chinBuilds(p[1], "spawn_defend")) do guards[#guards + 1] = b end
    check(#guards == 24 + 6 * e, n .. " human(s): 24 guards plus " .. 6 * e .. " extras (" .. #guards .. ")")
    local defend = ordersOf(p[1], "Defend2")
    local perSilo = {}
    for _, c in ipairs(F.callsOf(p[1], "Defend2")) do perSilo[c[3]] = (perSilo[c[3]] or 0) + 1 end
    for s = 1, 6 do
        check(perSilo["chin_silo" .. s] == 4 + e, n .. " human(s): silo " .. s .. " is guarded by " .. 4 + e)
    end
    for _, b in ipairs(guards) do
        check(b.team == 5 and defend[b.h] ~= nil, n .. " human(s): every guard is a team-5 unit guarding a silo")
        check(b.where == "spawn_defend1" or b.where == "spawn_defend6", n .. " human(s): the guards come from the authored paths")
    end
    check(w.objects[guards[1].h].odf ~= nil and #since(p[1], "BuildObject") == 24 + 6 * e, n .. " human(s): nothing else is built yet")
    -- the waves (the guards are shot up first: they would otherwise fill the live cap)
    for _, b in ipairs(guards) do F.kill(b.h) end
    local mark = #p[1].calls
    for wave = 1, 4 do
        run(WAVE_TIME[wave] - w.now + 12)
        local builds = F.builds(p[1], mark)
        local list = {}
        for _, b in ipairs(builds) do if b.where == "spawn_attack_waves" then list[#list + 1] = b end end
        local expected = 0
        for k = 1, wave do expected = expected + WAVE_SIZE[k] + e end
        check(#list == expected, n .. " human(s): wave " .. wave .. " brings " .. WAVE_SIZE[wave] .. " + " .. e .. " extras (total " .. #list .. " vs " .. expected .. ")")
    end
    local gotos = ordersOf(p[1], "Goto")
    for _, b in ipairs(chinBuilds(p[1], "spawn_attack_waves")) do
        check(b.team == 5 and gotos[b.h] == "recycler", n .. " human(s): every wave unit is team 5 and attacks the recycler")
    end
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end
do -- live cap: only extras are dropped, every primary still comes
    local w, p, m = setup(4, {})
    run(1850)
    local waves = chinBuilds(p[1], "spawn_attack")
    check(#waves >= 28 and #waves <= 28 + 8, "at the live cap every wave primary comes and only extras are dropped (" .. #waves .. ")")
end
do -- a human at an authored guard entry: those guards come from another hidden approach
    local w, p, m = setup(2, { place = function(p) F.place(p[2].player, 1103.66, 99822.8) end })
    run(20)
    local fromOne, fromFive, fromSix = 0, 0, 0
    for _, b in ipairs(chinBuilds(p[1], "spawn_defend")) do
        if b.where == "spawn_defend1" then fromOne = fromOne + 1
        elseif b.where == "spawn_defend5" then fromFive = fromFive + 1
        elseif b.where == "spawn_defend6" then fromSix = fromSix + 1 end
    end
    check(fromOne == 0 and fromFive > 0 and fromSix > 0, "no guard appears beside a human: they use the first hidden approach")
    check(fromFive + fromSix == 24 + 6, "every guard still comes (" .. fromFive + fromSix .. ")")
end
do -- a human at the wave entry: the wave comes from another hidden approach
    local w, p, m = setup(2, { place = function(p) F.place(p[2].player, 2459.58, 102252) end })
    run(190)
    local waves = {}
    for _, b in ipairs(F.builds(p[1])) do
        if b.where ~= "spawn_defend1" and b.where ~= "spawn_defend6" then waves[#waves + 1] = b end
    end
    check(#waves == 7 + 1, "the first wave still arrives with its extra")
    for _, b in ipairs(waves) do check(b.where == "spawn_defend5", "no wave unit appears at the entry beside a human: the first hidden approach") end
end
do -- the distance trigger of the guards is always met (the stock source has no threshold)
    local w, p, m = setup(1, {})
    for i = 1, 6 do check(m.defendersSpawned[i], "silo " .. i .. " guard group spawned on the first frame") end
end

-- ------------------------------------------------------------------ recycling by any human team, the win
for n = 1, 4 do
    local w, p, m = setup(n, {})
    run(5)
    -- each silo is recycled by a different human team (teams 1..n)
    for i = 1, 6 do silo(w, i, ((i - 1) % n) + 1) end
    run(3)
    check(m.silosRecycled, n .. " human(s): silos recycled by any human team count")
    heardAll(p, "bd13002.wav")
    for i = 1, n do
        check(F.count(p[i], "HideCockpitTimer") >= 1, "the timer is hidden on peer " .. i)
        local list = {}
        for _, c in ipairs(F.callsOf(p[i], "AddObjective")) do list[#list + 1] = c[2] .. "/" .. c[3] end
        local tail = table.concat(list, ","):match("bd13001.otf/green,bd13002.otf/white$")
        check(tail ~= nil, "the second objective reaches peer " .. i .. ": " .. table.concat(list, ","))
    end
    check(F.count(p[1], "FailMission") == 0, n .. " human(s): no loss for recycling")
    F.kill("chin_recycler"); run(2)
    check(m.won, n .. " human(s): the Chinese recycler falls: victory")
    w.audioBusy = true; run(2); w.audioBusy = false; run(6)
    heardAll(p, "bd13003.wav")
    for i = 1, n do
        check(F.count(p[i], "SucceedMission") == 1 and lastWin(p[i]) == "bd13win.des", "one shared victory on peer " .. i)
        check(F.count(p[i], "FailMission") == 0, "no failure after the victory on peer " .. i)
    end
end
do -- an enemy-team "recycle" is not one
    local w, p, m = setup(2, {})
    run(5)
    silo(w, 1, 5)
    heardAll(p, "bd13006.wav", 0)
    run(3)
    heardAll(p, "bd13006.wav")
    check(lastFail(p[1]) == "bd13lsec.des", "a silo the Chinese lost on their own is a destroyed silo")
end

-- ------------------------------------------------------------------ the unused voice lines and the other losses
do
    local w, p, m = setup(3, {})
    run(5)
    w.audioBusy = true
    silo(w, 1, nil); silo(w, 2, nil)
    run(4)
    heardAll(p, "bd13006.wav")
    check(m.lost and F.count(p[1], "FailMission") == 0, "the debrief waits for the line")
    w.audioBusy = false; run(4)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and lastFail(p[i]) == "bd13lsec.des", "one shared silo-loss failure on peer " .. i)
        check(F.heardCount(p[i], "bd13007.wav") == 0, "only the silo line plays")
    end
    local before = #chinBuilds(p[1])
    run(60)
    check(#chinBuilds(p[1]) == before, "nothing more is built after the loss")
end
do
    local w, p, m = setup(3, {})
    run(5)
    w.objects.chin_recycler.health = 0.9
    run(4)
    heardAll(p, "bd13007.wav")
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and lastFail(p[i]) == "bd13lsed.des", "one shared early-strike failure on peer " .. i)
        check(F.heardCount(p[i], "bd13006.wav") == 0, "only the strike line plays")
    end
end
do -- after the silos are held a hit on the Chinese base is the plan
    local w, p, m = setup(2, {})
    run(5); recycleAll(w); run(3)
    w.objects.chin_recycler.health = 0.5; run(10)
    check(F.count(p[1], "FailMission") == 0 and F.heardCount(p[1], "bd13007.wav") == 0, "no strike warning once the silos are recycled")
end
do -- a load while the restored line plays still ends in the debrief, once
    local w, p, m = setup(2, {})
    run(5)
    w.audioBusy = true
    silo(w, 4, nil); run(2)
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); run(3)
    check(F.count(p[1], "FailMission") == 0, "the debrief still waits for the line after a load")
    w.audioBusy = false; run(4)
    check(F.count(p[1], "FailMission") == 1 and lastFail(p[1]) == "bd13lsec.des" and F.count(p[2], "FailMission") == 1,
        "the debrief follows the line after a load, once")
    check(F.heardCount(p[1], "bd13006.wav") == 1, "the line is not replayed by the load")
end
do -- the recycler lost
    local w, p, m = setup(3, {})
    run(30); F.kill("recycler"); run(15)
    heardAll(p, "bd13004.wav")
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and lastFail(p[i]) == "bd13lseb.des", "one shared recycler-loss failure on peer " .. i)
        check(F.count(p[i], "SucceedMission") == 0, "no victory after the loss")
    end
end
do -- the deadline: the host counts the 45 minutes (the map class would never expire them)
    local w, p, m = setup(3, { stuck = true })
    run(2690)
    check(F.count(p[1], "FailMission") == 0, "not yet at 44:50")
    run(20)
    heardAll(p, "bd13005.wav")
    run(15)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and lastFail(p[i]) == "bd13lsea.des", "one shared deadline failure on peer " .. i)
    end
end
do -- recycled in time: the deadline passes harmlessly
    local w, p, m = setup(2, { stuck = true })
    run(2000); recycleAll(w); run(800)
    check(F.count(p[1], "FailMission") == 0 and F.heardCount(p[1], "bd13005.wav") == 0, "an all-recycled field never meets the deadline")
end
for _, flag in ipairs({ "RESTORED_SILO_LOSS_VOICE", "RESTORED_EARLY_STRIKE_VOICE" }) do -- the restorations can be switched off
    local f = assert(io.open("Scripts/bdmisn" .. "13cr.lua", "rb")); local source = f:read("*a"); f:close()
    check(source:find("local " .. flag .. " = true", 1, true), "the restoration has its flag: " .. flag)
    source = source:gsub("local " .. flag .. " = true", "local " .. flag .. " = false", 1)
    local saved = F.SCRIPT
    local path = os.tmpname()
    local out = assert(io.open(path, "wb")); out:write(source); out:close()
    F.SCRIPT = path
    local w, p, m = setup(1, {})
    F.SCRIPT = saved
    os.remove(path)
    run(5)
    if flag == "RESTORED_SILO_LOSS_VOICE" then silo(w, 1, nil) else w.objects.chin_recycler.health = 0.5 end
    run(5)
    check(F.heardCount(p[1], "bd13006.wav") + F.heardCount(p[1], "bd13007.wav") == 0, flag .. " = false is the stock silence")
    check(F.count(p[1], "FailMission") == 1, flag .. " = false fails at once, as the DLL does")
end

-- ------------------------------------------------------------------ nil audio never strands a gate
do
    local w, p, m = setup(1, { stage = function(w) w.nilAudio = true end, hold = true })
    w.cameraDone.camera_intro = true; run(3)
    check(m.cameraComplete[1], "an intro whose line returns no handle still ends")
    run(10); recycleAll(w); run(3); F.kill("chin_recycler"); run(4)
    check(lastWin(p[1]) == "bd13win.des", "a nil win line still ends the mission in victory")
    local w2, p2, m2 = setup(1, { stage = function(w) w.nilAudio = true end })
    run(5); F.kill("recycler"); run(6)
    check(lastFail(p2[1]) == "bd13lseb.des", "a nil loss line still fails the mission")
    local w3, p3, m3 = setup(1, { stage = function(w) w.nilAudio = true end })
    run(5); silo(w3, 3, nil); run(6)
    check(lastFail(p3[1]) == "bd13lsec.des", "a nil restored line still fails the mission")
end

-- ------------------------------------------------------------------ loads and the leader leaving
do -- a load in the intro ends it and republishes the opening
    local w, p, m = setup(3, { hold = true })
    run(3)
    check(p[1].camera == 1, "the intro is running")
    local mark, marks = #p[1].calls, {}
    for i, q in ipairs(p) do marks[i] = #q.calls end
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); run(3)
    m = p[1].env.Save()
    check(m.cameraComplete[1], "the intro ends after a load")
    for i = 1, 3 do check(p[i].camera == 0, "no camera is left open on peer " .. i) end
    check(F.heardCount(p[1], "bd13001.wav") == 1, "the briefing is not replayed")
    local objectives = since(p[1], "AddObjective", mark)
    check(#objectives == 1 and objectives[1][2] == "bd13001.otf" and objectives[1][3] == "white", "the objective is published after the load")
    check(#since(p[1], "SetObjectiveName", mark) == 6, "the six scrap field names are republished")
    local timers = since(p[1], "StartCockpitTimer", mark)
    check(#timers == 1 and timers[1][2] > 2690 and timers[1][2] <= 2700, "the running timer is shown again with its remaining time")
    for i = 2, 3 do
        check(#since(p[i], "SetObjectiveName", marks[i]) == 6 and #since(p[i], "StartCockpitTimer", marks[i]) == 1,
            "peer " .. i .. " gets the same republish")
    end
end
do -- a load in the field keeps the stage: first objective, then the second with no timer
    local function afterLoad(w, p, expect, timer)
        local mark = #p[1].calls
        for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
        F.connect(); run(3)
        local list = {}
        for _, c in ipairs(since(p[1], "AddObjective", mark)) do list[#list + 1] = c[2] .. "/" .. c[3] end
        check(table.concat(list, ",") == expect, "the objectives are republished after a load: " .. table.concat(list, ",") .. " vs " .. expect)
        check(#since(p[1], "SetObjectiveName", mark) == 6, "the scrap field names are republished after a load")
        local timers = since(p[1], "StartCockpitTimer", mark)
        if timer then
            check(#timers == 1 and math.abs(timers[1][2] - timer) < 3, "the timer is shown again after a load (" .. (timers[1] and timers[1][2] or "none") .. " vs " .. timer .. ")")
        else
            check(#timers == 0, "no timer after a load once the silos are held")
        end
        run(2)
        check(#since(p[1], "AddObjective", mark) == #list, "the republish happens once")
    end
    local w, p, m = setup(2, {})
    run(600)
    afterLoad(w, p, "bd13001.otf/white", 2700 - w.now + 1)
    check(#chinBuilds(p[1], "spawn_defend") == 24 + 6 and #chinBuilds(p[1], "spawn_attack") == 7 + 1 + 6 + 1, "a load builds nothing twice")
    w, p, m = setup(2, {})
    run(5); recycleAll(w); run(3)
    afterLoad(w, p, "bd13001.otf/green,bd13002.otf/white", nil)
end
do
    local w, p, m = setup(3, {})
    for i = 2, 3 do p[i].env.DeletePlayer(1) end
    run(3)
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
local function europa(record, mode)
    return function(peer)
        local V = { Seed = 4242, Initialized = true }
        local vents = dofile("Scripts/CRGanymedeSitesBD13.lua").vents
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
        function V.TriggerPlume(index) record("EuropaPlumeAt", index, vents[index].label) end
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
local function plumed(peer, label)
    local n = 0
    for _, c in ipairs(F.callsOf(peer, "EuropaPlumeAt")) do if c[3] == label then n = n + 1 end end
    return n
end
do
    local sites = dofile("Scripts/CRGanymedeSitesBD13.lua")
    check(sites.mission == "bdmisn13" and #sites.vents == 15 and sites.vents[1].label == "eggeizr10_geyser",
        "the generated sites carry the fifteen geysers of the map")
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
    run(60); silo(w, 1, 1); run(2)
    check(F.count(p[1], "EuropaSurgeCall") == 1 and F.last(p[1], "EuropaSurgeCall")[2] == 3.0, "the first seized silo surges")
    check(F.count(p[1], "EuropaLevel", 2) == 0, "...the first wave has not come yet")
    run(130)
    check(F.count(p[1], "EuropaLevel", 2) == 1 and plumed(p[1], "eggeizr10_geyser") == 1, "wave one stirs the sky and opens a vent under the base")
    check(F.count(p[1], "EuropaCreated") > 0, "new objects are offered to the weather")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); run(3)
    check(F.count(p[1], "EuropaShutdown") >= 1 and F.count(p[1], "EuropaLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(p[1], "EuropaLevel", 2) == 1 and F.count(p[1], "EuropaSurgeCall") == 1, "beats already played are not replayed after a load")
    run(430)
    check(F.count(p[1], "EuropaLevel", 3) == 1 and F.count(p[1], "EuropaQuakeCall") == 1, "wave two flexes the ice shell")
    run(300)
    check(F.count(p[1], "EuropaSurgeCall") == 2 and plumed(p[1], "eggeizr11_geyser") == 1, "wave three surges and opens the second vent")
    run(900)
    check(F.count(p[1], "EuropaLevel", 4) == 1 and F.count(p[1], "EuropaQuakeCall") == 2 and F.count(p[1], "EuropaSurgeCall") == 3,
        "the last wave brings the worst of the sky")
    recycleAll(w); run(3)
    check(plumed(p[1], "eggeizr1146_geyser") == 1 and plumed(p[1], "eggeizr1147_geyser") == 1 and plumed(p[1], "eggeizr1148_geyser") == 1
        and F.count(p[1], "EuropaSurgeCall") == 4, "the seized silos vent the Chinese base geysers")
    F.kill("chin_recycler"); run(2); w.audioBusy = true; run(2); w.audioBusy = false; run(6)
    check(F.count(p[1], "EuropaRelease") == 1 and F.count(p[1], "EuropaLevel", 1) == 1, "the victory eases the weather")
end
do -- the deadline brings the nuke
    local sites = dofile("Scripts/CRGanymedeSitesBD13.lua")
    local w, p, m = setup(2, { stuck = true, weather = { module = function(peer, record) return europa(record)(peer) end, sites = sites } })
    run(2730)
    check(F.count(p[1], "EuropaQuakeCall") >= 1 and F.count(p[1], "EuropaPlumeAt") >= 15, "the order to nuke Ganymede shakes every vent")
end
do -- sites module missing: no weather, never an error
    local w, p, m = setup(2, { weather = { module = function(peer, record) return europa(record)(peer) end } })
    check(F.count(p[1], "EuropaInit") == 0 and m.startDone, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local w, p, m = setup(2, { weather = { module = function(peer, record) return europa(record, mode)(peer) end,
        sites = dofile("Scripts/CRGanymedeSitesBD13.lua") } })
    run(5); recycleAll(w); run(3); F.kill("chin_recycler"); run(2); w.audioBusy = true; run(2); w.audioBusy = false; run(6)
    check(F.count(p[1], "SucceedMission") == 1 and F.count(p[2], "SucceedMission") == 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("bdmisn13 co-op: " .. checks .. " checks passed")
