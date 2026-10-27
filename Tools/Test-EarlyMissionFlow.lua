-- Focused regression tests using blocks extracted from the actual mission
-- scripts. Engine calls are mocked; EXU/weather/co-op and map pathfinding still
-- require in-game qualification. Run from repository root with Lua 5.1.
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    -- A Windows checkout (core.autocrlf) has CRLF; the anchors below use "\n".
    return (s:gsub("\r\n", "\n"))
end
local sources = {}
for _, name in ipairs({ "02b", "03", "04", "05" }) do
    local path = "Scripts/misn" .. name .. ".lua"
    check(loadfile(path) ~= nil, path .. " must compile on Lua 5.1")
    sources[name] = read(path)
end
local function between(name, first, last)
    local s = sources[name]
    local i = assert(s:find(first, 1, true), first)
    local j = assert(s:find(last, i + #first, true), last)
    return s:sub(i, j - 1)
end
local world
local function reset()
    world = { now = 100, alive = {}, distances = {}, calls = {}, serial = 0, health = {} }
end
local function record(name, ...)
    world.calls[#world.calls + 1] = { name, ... }
end
function GetTime() return world.now end
function IsAlive(h) return h ~= nil and world.alive[h] == true end
function IsValid(h) return h ~= nil end
function GetDistance(a, b) return world.distances[tostring(a) .. ":" .. tostring(b)] or 1000 end
function GetPosition(h) return h end
function GetPositionNear(h) return h end
function GetCurrentCommand() return 0 end
function BuildObject(odf, team, pos)
    world.serial = world.serial + 1
    local h = odf .. world.serial
    world.alive[h] = true
    record("BuildObject", h, odf, team, pos)
    return h
end
function AudioDone() return world.audioDone == true end
function IsAudioMessageDone() return world.audioDone == true end
function GetHealth(h) return world.health[h] or 1 end
function CameraCancelled() return false end
function CameraFinish() record("CameraFinish") end
native = { RemoveObject = function(h) record("RemoveObject", h) end }
for _, name in ipairs({ "Attack", "Goto", "Patrol", "Defend", "Follow", "Retreat", "Stop",
    "SetIndependence", "SetCritical", "SetLabel", "SetObjectiveOn", "SetObjectiveOff",
    "SetObjectiveName", "ClearObjectives", "AddObjective", "AddHealth", "SetUserTarget",
    "Damage", "FailMission", "SucceedMission" }) do
    local n = name
    _G[n] = function(...) record(n, ...) end
end
local subtitles = {
    Play = function(file) record("Audio", file, "play"); return file end,
    Queue = function(file) record("Audio", file, "queue"); return file end,
    Stop = function() record("AudioStop") end,
}
local diff = {
    Get = function() return { index = 2 } end,
    ScaleEnemy = function(n) return n + (world.extraEnemies or 0) end,
    ScaleTimer = function(n) return n end,
}
local function count(name, handle)
    local n = 0
    for _, c in ipairs(world.calls) do
        if c[1] == name and (handle == nil or c[2] == handle) then n = n + 1 end
    end
    return n
end
local function last(name)
    for i = #world.calls, 1, -1 do
        if world.calls[i][1] == name then return world.calls[i] end
    end
end
local anyAlive = between("05", "local function AnyAlive(list)", "local function RefreshDifficulty()")
local function compile(code)
    local prefix = [[
return function(M, ctx)
    ctx = ctx or {}
    local player = ctx.player
    local solarCount, required = ctx.solarCount, ctx.required
    local missionData = ctx.missionData
    local subtit, DiffUtils = ctx.subtitles, ctx.diff
    local LABEL_SCAV2 = "misn02b_scav2"
    local CRCoop = { IsNetworkGame = function() return false end,
        AnyPlayerSatisfies = function(pred)
            for _, h in ipairs(ctx.players or {}) do
                if pred(h) then return true end
            end
            return false
        end }
    local ENEMY_TEAM = 2
    local SpawnScriptedEnemy = ctx.spawn
]]
    return assert(loadstring(prefix .. anyAlive .. code .. "\nreturn M\nend"))()
end
local function context(extra)
    extra = extra or {}
    extra.subtitles, extra.diff = subtitles, diff
    extra.spawn = function(odf, pos) return BuildObject(odf, 2, pos) end
    return extra
end
local function live(...)
    for _, h in ipairs({ ... }) do world.alive[h] = true end
end

-- Tran05 grouping and shared terminal audio.
local convoy = compile(between("02b", "    -- Loss Condition", "\nend\n"))
local function convoyState()
    return { bhome = "home", recycler = "rec", last_wave_time = 99999,
        NextSecond = 99999, wave_timer = 99999 }
end
for _, destroyed in ipairs({ "home", "rec" }) do
    reset(); live("player", "home", "rec")
    world.alive[destroyed] = false
    local m = convoyState()
    convoy(m, context({ player = "player" }))
    check(m.mission_lost and m.audmsg == "misn0227.wav", "base loss before first scav is tracked")
    check(count("SucceedMission") == 0 and count("BuildObject") == 0, "failure cannot rescue or win")
    world.audioDone = true
    convoy(m, context({ player = "player" }))
    check(last("FailMission")[3] == "misn02l1.des", "original failure debrief retained")
end
reset(); live("home", "rec")
local m = convoyState()
convoy(m, context({ player = "missingPlayer" }))
check(not m.mission_lost, "unit loss checks still wait for the first scavenger")
reset(); live("player", "home", "scav", "scav2")
m = convoyState(); m.bscav, m.scav2, m.message3 = "scav", "scav2", true
world.distances["home:scav2"] = 50
convoy(m, context({ player = "player" }))
check(m.mission_lost and not m.mission_won, "same-frame recycler loss beats convoy return")
check(m.audmsg == "misn0227.wav", "win does not replace failure audio")
reset(); live("player", "home", "rec", "scav", "scav2")
m = convoyState(); m.bscav, m.scav2, m.message3 = "scav", "scav2", true
world.distances["home:scav2"] = 50; world.audioDone = true
convoy(m, context({ player = "player" }))
check(m.mission_won and last("SucceedMission")[3] == "misn02w1.des", "healthy convoy victory unchanged")
check(count("AddHealth") == 2, "both scavenger victory repairs remain")
world.alive.rec = false
convoy(m, context({ player = "player" }))
check(not m.mission_lost, "settled win cannot change to loss")
reset(); live("player", "home", "rec", "scav")
m = convoyState(); m.bscav, m.message1, m.message4 = "scav", true, true
world.distances["home:scav"] = 100
convoy(m, context({ player = "player" }))
check(m.message3 and IsAlive(m.scav2), "healthy rescue still spawns second scavenger")
check(m.last_wave_time == 110 and m.NextSecond == 101, "rescue timers retained")

-- Living-scavenger fallback; do not attack a dead scavenger.
local hunt = compile(between("03", "    if not M.scavhunt2", "    if not M.help_spawn"))
for _, survivor in ipairs({ "scav1", "scav2", "none" }) do
    reset(); live("hunter")
    if survivor ~= "none" then live(survivor) end
    m = { wave5_1 = "hunter", scav1 = "scav1", scav2 = "scav2", fourth_wave_done = true }
    hunt(m, context())
    check(m.scavhunt2, "hunt remains one-shot")
    check(count("Attack") == (survivor == "none" and 0 or 1), "hunt only attacks a living target")
    if survivor ~= "none" then check(last("Attack")[3] == survivor, "hunt selects available scavenger") end
end

-- The stock solar2 failure must respect the existing difficulty count rule.
local solarFailure = compile(between("03", "    if not M.dead2 and not M.tanks_go", "    if M.movie_over"))
for required = 1, 3 do
    for survivors = 0, 3 do
        reset()
        m = {}
        solarFailure(m, context({ required = required, solarCount = survivors }))
        check((m.lost == true) == (survivors < required), "solar2 loss honors required survivor count")
        if survivors < required then
            check(last("FailMission")[3] == "misn03f3.des", "stock array-loss debrief retained")
        else
            check(count("FailMission") == 0, "sufficient backup arrays do not fail")
        end
    end
end
reset(); m = { second_objective = true }
solarFailure(m, context({ required = 1, solarCount = 0 }))
check(not m.lost, "stock array-loss phase gate retained")

-- Outro advances through its normal delays even with a dead tower/prop.
local outro = compile(between("03", "    if M.camera_2 and not M.show_tank_attack", "    if M.camera_on and not M.camera_off"))
for _, towerAlive in ipairs({ false, true }) do
    reset(); live("prop2", "prop3")
    if towerAlive then live("tower") end
    m = { camera_2 = true, solar1 = "tower", prop1 = "deadProp", prop2 = "prop2", prop3 = "prop3", cam_geyser = "geyser" }
    outro(m, context())
    check(m.show_tank_attack and m.kill_tower == 107, "dead-prop shot arms normal tower delay")
    check(not m.tower_dead and not m.end_shot, "outro cannot skip destruction delay")
    world.now = 108; world.alive.tower = false
    outro(m, context())
    check(m.tower_dead and m.climax1 and m.climax2, "already-dead tower/prop advances climax")
    check(m.clear_debis_time == 111 and not m.end_shot, "climax retains debris delay")
    world.now = 112
    outro(m, context())
    check(m.last_blown and m.end_shot and m.camera_off_time == 118, "outro reaches existing six-second closing shot")
    check(count("SucceedMission") == 0, "visual blocks do not bypass camera completion")
end
reset(); live("tower", "prop1", "prop2")
m = { camera_2 = true, solar1 = "tower", prop1 = "prop1", prop2 = "prop2", shot_geyser = "shot" }
outro(m, context())
check(not m.show_tank_attack, "living prop still has to reach the QOL 80m trigger")
world.distances["prop1:shot"] = 79
outro(m, context())
check(m.show_tank_attack and m.kill_tower == 107, "healthy outro keeps QOL trigger and delay")
world.now = 108
outro(m, context())
check(count("Damage", "tower") == 1 and m.tower_dead, "healthy outro destroys tower once")

-- Relic secure latches must not override a loss or pending loss audio.
local relicWin = compile(between("04", "    if M.relicsecure and M.basesecure", "    if M.missionwon and not M.endmission"))
for _, scenario in ipairs({ "healthy", "relicDead", "recDead", "pendingFail", "pendingTheft", "notSecure" }) do
    reset(); live("relic", "rec")
    m = { relicsecure = true, basesecure = true, relic = "relic", avrec = "rec" }
    if scenario == "relicDead" then world.alive.relic = false end
    if scenario == "recDead" then world.alive.rec = false end
    if scenario == "pendingFail" then m.missionfail = true end
    if scenario == "pendingTheft" then m.missionfail2 = true end
    if scenario == "notSecure" then m.relicsecure = false end
    relicWin(m, context())
    check((m.missionwon == true) == (scenario == "healthy"), "relic win gate: " .. scenario)
end

-- Wave 2 patrol checks work whichever shuffled wave spawns first.
local waves = compile(between("05", "    -- Wave 1", "    -- Post-Recon Logic"))
for _, first in ipairs({ 1, 2 }) do
    reset()
    local second = first == 1 and 2 or 1
    m = { difficulty = 2, svrec = "enemyRec", sendTime = { 9999, 9999, 9999, 9999 } }
    m.sendTime[first] = 99
    waves(m, context())
    check((first == 1 and m.check1 and m.check2) or (first == 2 and m.check3 and m.check4), "own wave arms own checks")
    check(count("Patrol") == 0, "absent/approaching turrets cannot consume escort transition")
    m.sendTime[second] = 99
    waves(m, context())
    check(m.check1 and m.check2 and m.check3 and m.check4, "both waves retain pending checks")
    world.distances[m.w1u3 .. ":defendrim2"] = 39
    world.alive[m.w1u4] = false
    world.distances[m.w2u3 .. ":defendrim3"] = 39
    world.alive[m.w2u4] = false
    waves(m, context())
    for _, h in ipairs({ m.w1u1, m.w1u2, m.w2u1, m.w2u2 }) do
        check(count("Patrol", h) == 1, "fighter/tank patrol transition fires exactly once")
    end
    waves(m, context())
    check(count("Patrol") == 4, "settled checks do not repeat patrol orders")
end

-- One scheduled main assault, with the existing supplemental timetable.
local assault = compile(between("05", "    -- Spawn Final Attackers", "    -- Platoon Closing In Warning"))
for _, difficulty in ipairs({ 2, 3 }) do
    reset(); live("enemyRec", "factory")
    world.extraEnemies = 1
    m = { difficulty = difficulty, svrec = "enemyRec", lemnos = "factory", platoonhere = 101, go = true, bombtime = 99999 }
    assault(m, context())
    check(count("BuildObject") == 0 and m.go, "assault waits for scheduled time")
    world.now = 102
    assault(m, context())
    local total = difficulty == 3 and 6 or 4
    check(count("BuildObject") == total and #m.razorAttackers == total, "main assault and difficulty extras registered")
    check(not m.go and m.aw1t == 117 and m.aw2t == 157 and m.aw3t == 212 and m.aw4t == 262, "one-shot assault retains supplemental timers")
    local firstTimer = m.aw1t
    for _, h in ipairs(m.razorAttackers) do world.alive[h] = false end
    world.now = 120
    assault(m, context())
    check(count("BuildObject") == total and m.aw1t == firstTimer, "main casualties cannot respawn assault or reset reinforcements")
end

-- Independent order dispatch, late arrivals, both destinations, and dead units.
local attack = compile(between("05", "    -- Attack Command Switch", "    -- Platoon Closing In Warning"))
reset(); live("r1", "r2", "r3", "r4", "r5", "extra")
m = { aw1 = "r1", aw2 = "r2", aw3 = "r3", aw4 = "r4", aw5 = "r5", lemnos = "factory", bombtime = 99,
    razorAttackers = { "r1", "r2", "r3", "r4", "r5", "extra" } }
for _, h in ipairs({ "r1", "r2", "r3", "r4", "extra" }) do world.distances[h .. ":dest1"] = 59 end
attack(m, context())
check(count("Attack") == 5 and not m.attackcmd, "all eligible razors ordered without short-circuit; late arrival remains pending")
check(count("SetIndependence") == 5 and m.bombtime == 103, "independence and three-second polling retained")
world.now = 102; world.distances["r5:dest2"] = 59
attack(m, context())
check(count("Attack") == 5, "polling does not run early")
world.now = 104
attack(m, context())
check(count("Attack") == 6 and count("Attack", "r5") == 1 and m.attackcmd, "late arrival uses alternate destination")
attack(m, context())
check(count("Attack") == 6, "issued orders stay one-shot")
reset(); live("r2")
m = { aw1 = "deadR1", aw2 = "r2", bombtime = 99, lemnos = "factory" }
world.distances["r2:dest1"] = 59
attack(m, context())
check(#m.razorAttackers == 2 and count("Attack") == 1 and m.attackcmd, "old save seeds named survivors, skipping dead units")

-- Actual Load body migrates old latches while preserving new saved progress.
local loadBody = assert(sources["05"]:match("function Load%(missionData, _%)\n(.-)\nend"))
local loadMission = compile(loadBody)
reset()
m = { attacktimeset = true, aw1 = "deadR1", go = true, attackcmd = true }
loadMission(m, context({ missionData = m }))
check(not m.go and not m.attackcmd, "old save cannot replay main assault and rechecks partial attack orders")
check(m.loadGracePeriod == 102 and not m.loading_done, "existing load grace/rehydration retained")
m = { attacktimeset = true, aw1t = 117, go = true, attackcmd = true }
loadMission(m, context({ missionData = m }))
check(not m.go, "old save with cleared dead handles still cannot replay assault")
m = { attacktimeset = true, aw1 = "r1", go = false, attackcmd = true,
    razorAttackers = { "r1" }, razorAttackIssued = { true } }
loadMission(m, context({ missionData = m }))
check(m.attackcmd and m.razorAttackIssued[1], "new save preserves issued orders")
m = { attacktimeset = true, go = true, attackcmd = false }
loadMission(m, context({ missionData = m }))
check(m.go, "save during pre-assault wait retains pending spawn")

-- Failure-first result without changing the fleet/commander win sequence.
local factoryWin = compile(between("05", "    -- Win Condition.", "    -- Mission win sequence:"))
for _, scenario in ipairs({ "healthy", "recDead", "factoryDead", "pendingFail", "extraAlive" }) do
    reset(); live("rec", "factory")
    m = { sent1Done = true, sent2Done = true, sent3Done = true, sent4Done = true,
        aw1sent = true, aw2sent = true, aw3sent = true, aw4sent = true,
        avrec = "rec", lemnos = "factory", victoryEnemies = {} }
    if scenario == "recDead" then world.alive.rec = false end
    if scenario == "factoryDead" then world.alive.factory = false end
    if scenario == "pendingFail" then m.missionfail = true end
    if scenario == "extraAlive" then live("extra"); m.victoryEnemies = { "extra" } end
    factoryWin(m, context())
    check((m.missionwon == true) == (scenario == "healthy"), "factory win gate: " .. scenario)
    check(count("SucceedMission") == 0, "win still requires QOL end sequence")
end
-- Sequence of subtitle calls as "play:file"/"queue:file" strings.
local function audioLog()
    local out = {}
    for _, c in ipairs(world.calls) do
        -- Strip the extension: "op:name.wav" would read as an over-long engine filename.
        if c[1] == "Audio" then out[#out + 1] = c[3] .. ":" .. (c[2]:gsub("%.wav$", "")) end
    end
    return table.concat(out, ",")
end

-- CR restored VO: misn02b skip plays the 0232 alt take; clean escort plays 0226 then 0234.
local introEnd = compile(between("02b", "            -- Stop previous audio if the user skipped", '            --subtit.Play("misn0224.wav")'))
reset(); m = { intro_skipped = true }
introEnd(m, context())
check(audioLog() == "play:misn0232" and m.audmsg == "misn0232.wav", "02b skipped intro plays 0232")
reset(); m = {}
introEnd(m, context())
check(audioLog() == "play:misn0201", "02b unskipped intro still plays only 0201")
for _, scenario in ipairs({ "clean", "damaged" }) do
    reset(); live("player", "home", "rec", "scav", "scav2")
    m = convoyState(); m.bscav, m.scav2, m.message3 = "scav", "scav2", true
    world.distances["home:scav2"] = 50
    if scenario == "damaged" then world.health.scav2 = 0.5 end
    convoy(m, context({ player = "player" }))
    check(m.mission_won and m.audmsg == "misn0234.wav", "02b win always waits on 0234")
    if scenario == "clean" then
        check(audioLog() == "play:misn0226,queue:misn0234", "02b clean escort plays 0226 then 0234")
    else
        check(audioLog() == "play:misn0234", "02b damaged scavenger plays only 0234")
    end
end

-- CR restored VO: misn03 0309 reminder only while no player is near a transport, max twice.
local reminder = compile(between("03", "    -- CR restored VO: misn0309.wav", "    if M.recycler_follow_transport and not M.third_objective and"))
local function reminderState()
    return { remove_props = true, transport_reminders = 0, transport_reminder_time = 99999.0,
        rescue1 = "t1", rescue2 = "t2", aud306 = "a306" }
end
reset(); live("t1", "t2"); world.audioDone = false
m = reminderState()
reminder(m, context({ players = { "p1" } }))
check(m.transport_reminder_time == 99999.0, "03 reminder waits for 0306 to finish")
world.audioDone = true
reminder(m, context({ players = { "p1" } }))
check(m.transport_reminder_time == 160, "03 reminder armed 60 s after 0306 finishes")
world.now = 159
reminder(m, context({ players = { "p1" } }))
check(audioLog() == "", "03 reminder not early")
world.now = 160; world.distances["p1:t2"] = 200
reminder(m, context({ players = { "p1" } }))
check(audioLog() == "" and m.transport_reminders == 0, "03 no reminder while a player is within 300 m of a transport")
world.distances["p1:t2"] = 1000
world.now = 175
reminder(m, context({ players = { "p1" } }))
check(audioLog() == "play:misn0309" and m.transport_reminders == 1 and m.transport_reminder_time == 265, "03 first reminder fires once")
world.now = 200
reminder(m, context({ players = { "p1" } }))
check(m.transport_reminders == 1, "03 reminder honors 90 s spacing")
world.now = 265
reminder(m, context({ players = { "p1" } }))
check(m.transport_reminders == 2, "03 second reminder fires")
world.now = 1000
reminder(m, context({ players = { "p1" } }))
check(m.transport_reminders == 2 and audioLog() == "play:misn0309,play:misn0309", "03 reminder capped at two")
for _, gate in ipairs({ "third_objective", "lost", "final_objective" }) do
    reset(); live("t1", "t2"); world.audioDone = true
    m = reminderState(); m[gate] = true; m.transport_reminder_time = 50
    reminder(m, context({ players = {} }))
    check(audioLog() == "", "03 reminder suppressed after " .. gate)
end

-- CR restored VO: misn04 relic discovery by a wingman plays 0407, by a player 0408.
local discover = compile(between("04", "        local humanNearRelic", "        M.relicseen = true"))
for _, finder in ipairs({ "player", "wingman" }) do
    reset(); live("relic", "player")
    if finder == "player" then world.distances["player:relic"] = 100 end
    m = { relic = "relic" }
    discover(m, context({ players = { "player" } }))
    if finder == "player" then
        check(audioLog() == "play:misn0408,queue:misn0409", "04 player discovery plays 0408 then 0409")
    else
        check(audioLog() == "play:misn0407,queue:misn0409", "04 wingman discovery plays 0407 then 0409")
    end
    check(m.aud2 and m.aud3 == "misn0409.wav", "04 discovery keeps aud2/aud3 handles")
end

-- CR restored VO: misn04 relic destroyed plays 0428 (not the CCA-theft lines).
local relicLost = compile(between("04", "    if not IsAlive(M.relic) and not M.missionfail then",
    "    if not M.basesecure and not M.secureloopbreak and finalWaveCleared and not IsAlive(M.svrec)"))
reset(); m = { relic = "relic" }
relicLost(m, context())
check(audioLog() == "play:misn0428" and m.missionfail, "04 relic destroyed plays only 0428")
check(last("FailMission")[3] == "misn04l2.des" and last("FailMission")[2] == 120, "04 relic failure timing and debrief kept")
for _, wav in ipairs({ "misn0431.wav", "misn0432.wav", "misn0433.wav", "misn0434.wav" }) do
    check(sources["04"]:find('subtit.Queue("' .. wav .. '")', 1, true) or sources["04"]:find('subtit.Play("' .. wav .. '")', 1, true),
        "04 theft path still references " .. wav)
end

-- CR restored VO: misn04 recon-warning failure plays 0436 then 0694 and waits on both.
local reconFail = compile(between("04", "    if M.warn == 4 and M.notfound < GetTime() and not M.missionfail then",
    "    if not M.discoverrelic and M.investigate < GetTime()"))
reset(); m = { warn = 4, notfound = 0 }
reconFail(m, context())
check(audioLog() == "play:misn0436,queue:misn0694" and m.aud14 == "misn0694.wav", "04 recon failure plays 0436 then 0694")
check(count("FailMission") == 0, "04 recon failure waits for audio")
world.audioDone = true
reconFail(m, context())
check(count("FailMission") == 1 and last("FailMission")[3] == "misn04l4.des", "04 recon failure resolves after audio")

-- CR restored VO: misn04 success plays 0424 after the end cinematic and before the result.
local endCin = compile(between("04", "        if GetTime() > M.startendcin or CameraCancelled() then",
    "    end\n\n    if M.endmission and not M.endsucceeded"))
local endResult = compile(between("04", "    if M.endmission and not M.endsucceeded", "    if not M.missionwon and not IsAlive(M.avrec) and not M.missionfail then"))
reset(); m = { startendcin = 0 }; world.audioDone = false
endCin(m, context())
check(audioLog() == "play:misn0424" and m.endmission and count("SucceedMission") == 0, "04 end cinematic starts 0424, no result yet")
endResult(m, context())
check(count("SucceedMission") == 0, "04 success waits for 0424")
world.audioDone = true
endResult(m, context()); endResult(m, context())
check(count("SucceedMission") == 1 and last("SucceedMission")[3] == "misn04w1.des", "04 success after 0424, exactly once")

-- CR restored VO: misn05 wave alert 0505 throttled to once per 150 s and skipped in cutscenes.
local randomWave = compile(between("05", "    -- Random Spawns (Start of mission)", "    -- Not Found Warning"))
reset(); live("enemyRec", "avRec")
m = { svrec = "enemyRec", avrec = "avRec", difficulty = 2, needtospawn = true, randomwave = 0, next505 = 0 }
randomWave(m, context())
check(audioLog() == "queue:misn0505" and m.next505 == 250, "05 first wave alert queues 0505 behind the briefing and sets 150 s throttle")
world.alive[m.rand1], world.alive[m.rand2] = false, false
randomWave(m, context())
world.now = 140
randomWave(m, context())
check(count("Audio") == 1, "05 second wave within 150 s stays silent")
world.alive[m.rand1], world.alive[m.rand2] = false, false
randomWave(m, context())
world.now = 300
randomWave(m, context())
check(count("Audio") == 2 and m.next505 == 450, "05 wave alert plays again after 150 s")
reset(); live("enemyRec", "avRec")
m = { svrec = "enemyRec", avrec = "avRec", difficulty = 2, needtospawn = true, randomwave = 0, next505 = 0, lemcin1 = true }
randomWave(m, context())
check(count("Audio") == 0 and m.next505 == 0 and m.rand1, "05 wave alert skipped during cutscene, spawn still happens")

-- Consecutive subtit.Play lines drop earlier subtitles; none may remain in active code.
for _, name in ipairs({ "02b", "03", "04", "05" }) do
    local active = sources[name]:match("^(.-)\n%-%-%[==%[") or sources[name]
    local prev, n = false, 0
    for line in (active .. "\n"):gmatch("(.-)\n") do
        local isPlay = line:find("subtit.Play(", 1, true) and not line:match("^%s*%-%-")
        if isPlay and prev then check(false, "back-to-back subtit.Play in misn" .. name .. ": " .. line) end
        if line:match("%S") then prev = isPlay and true or false end
        n = n + 1
    end
    check(n > 100, "scanned active code of misn" .. name)
end

print("early missions: " .. checks .. " focused Lua 5.1 flow checks passed")
