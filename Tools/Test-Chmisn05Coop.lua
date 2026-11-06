-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/ch05cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/Test-Chmisn05Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Chmisn05Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local function extrasFor(n) return math.min(math.floor(n / 2), 2) end
local FAITHFUL = { faithful = true, script = F.FAITHFUL }
local SCALED = { svwalk = true, svhraz = true, svtank = true, svltnk = true, svfigh = true, svrckt = true, svapc = true }
local WAVE_UNITS = { wave_1 = 7, wave_2 = 9, wave_4 = 10, wave_5 = 13, wave_6 = 8, wave_7 = 13, annoy_1 = 6 }

local function setup(n, options)
    options = options or {}
    local w = F.reset()
    w.audioBusy = options.busy == true
    w.nilAudio = options.nilAudio == true
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
local function isHuman(p, h) for _, q in ipairs(p) do if q.player == h then return true end end return false end
local function heardAll(p, file, count)
    for i, q in ipairs(p) do check(F.heardCount(q, file) == (count or 1), "peer " .. i .. " hears " .. file .. " x" .. (count or 1)) end
end
local function guestsPassive(p)
    for i = 2, #p do
        for _, name in ipairs({"BuildObject", "SetScrap", "SetAIP", "Goto", "Attack", "SetPerceivedTeam", "RemoveObject"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on the authored enemy team 2") end
end
local function allSafe(p, builds)
    for _, b in ipairs(builds) do
        for _, q in ipairs(p) do
            check(q.env.GetDistance(q.player, b.h) >= 460, "no scripted unit is built within 460 m of any human: " .. tostring(b.where))
        end
    end
end
local function perceivedAll(p, expect)
    for i, q in ipairs(p) do
        local want = expect == "own" and q.team or expect
        check(F.perceived(q.player) == want, "human " .. i .. " is perceived as " .. tostring(want) .. ", got " .. tostring(F.perceived(q.player)))
    end
end
local function gather(p, target, dx, dz)
    for i, q in ipairs(p) do F.nearTo(q.player, target, (dx or 0) + 6 * (i - 1), dz or 0) end
end
-- Kills every enemy craft the script built (keeps the live cap out of the way).
local function purge(w)
    for key, o in pairs(w.objects) do
        if o.alive and o.team == 5 and o.key == key and key:sub(1, 5) == "built" then F.kill(key) end
    end
end

-- ------------------------------------------------------------------ the mission, stage by stage
-- The scrap gate, the scouts and the Last GPS Fix.
local function stageScouts(w, p, m, who)
    F.setScrap(p[who or 1].team, 3); F.run(1)
    check(m.scoutsSpawned, "three scrap spawn the scouts")
    F.nearTo(m.leadScout, "trigger_1", 10, 0)
    F.runUntil(function() return m.objective1Complete end, 40)
end
-- The tug and its film.
local function stageTug(w, p, m)
    gather(p, "trigger_1", 330, 0)
    F.runUntil(function() return m.doHaulCam end, 20)
    F.runUntil(function() return not m.doHaulCam end, 40)
end
-- The convoy leaves with a scout in tow, the base is attacked, the party is revealed.
local function stageConvoy(w, p, m)
    F.hook(m.neutralScout, m.tug); F.run(1)
    F.nearTo(m.tug, "trigger_2", 50, 0); gather(p, m.tug, 330, 0)
    F.runUntil(function() return m.factory ~= nil end, 60)
end
local function stageBase(w, p, m)
    gather(p, "base_1", 0, 60)
    F.runUntil(function() return m.team1Time >= 999999 end, 40)
end
-- Until the first wave of the siege.
local function stageSiege(w, p, m)
    F.runUntil(function() return m.annoy1Time < 900000 end, 400, 1)
    F.run(6) -- the runtime builds two tickets a frame
end
local function toSiege(w, p, m)
    stageScouts(w, p, m); stageTug(w, p, m); stageConvoy(w, p, m); stageBase(w, p, m); stageSiege(w, p, m)
end
local function goWave(w, p, m, field)
    m[field] = w.now + 0.5
    F.run(3)
end

-- ------------------------------------------------------------------ offline == faithful
local function outcomes(options, scenario)
    local w, p, m = setup(1, options)
    scenario(w, p, m)
    local out = {}
    for _, name in ipairs({"SucceedMission", "FailMission"}) do
        for _, c in ipairs(F.callsOf(p[1], name)) do out[#out + 1] = name .. ":" .. tostring(c[3]) end
    end
    local audio = table.concat(F.lines(p[1]), ",")
    return table.concat(out, ","), audio, p[1], w, m
end
local scenarios = {
    win = function(w, p, m)
        toSiege(w, p, m)
        F.run(25 * 60, 1)
        check(m.wave7Spawned, "the last wave came")
        for i = 0, m.numMustKill - 1 do F.kill(m.mustKill[i]) end
        F.run(30, 1)
    end,
    stray = function(w, p, m) F.place(p[1].player, 3000, 100900); F.run(5) end,
    nearTug = function(w, p, m)
        stageScouts(w, p, m); gather(p, "trigger_1", 330, 0)
        F.runUntil(function() return m.tug ~= nil end, 20)
        F.nearTo(p[1].player, m.tug, 100, 0); F.run(4)
    end,
    lostTug = function(w, p, m)
        stageScouts(w, p, m); stageTug(w, p, m)
        F.hook(m.neutralScout, m.tug); F.run(1)
        F.nearTo(p[1].player, m.tug, 900, 0); F.run(4)
    end,
    noBase = function(w, p, m)
        stageScouts(w, p, m); stageTug(w, p, m); stageConvoy(w, p, m)
        F.kill("recycler"); F.kill(m.factory); F.run(4)
    end,
}
local NAMES = { "win", "stray", "nearTug", "lostTug", "noBase" }
local EXPECT = { win = "SucceedMission:ch05win.des", stray = "FailMission:ch05lsea.des", nearTug = "FailMission:ch05lseb.des",
    lostTug = "FailMission:ch05lsed.des", noBase = "FailMission:ch05lsec.des" }
for _, name in ipairs(NAMES) do
    local faithful, faudio = outcomes(FAITHFUL, scenarios[name])
    local offline, oaudio, peer = outcomes({}, scenarios[name])
    check(faithful == offline, "offline completes like the faithful port (" .. name .. "): " .. faithful .. " / " .. offline)
    check(offline == EXPECT[name], "offline result of " .. name .. ": " .. offline)
    if name == "win" then
        -- the one difference is the restored victory line (RESTORED_VOICE_LINES), last in the sequence
        check(oaudio == faudio .. ",ch05008.wav", "offline plays the faithful audio plus the restored victory line: " .. oaudio)
        local result = F.last(peer, "SucceedMission")
        check(result[2] >= result.t + 13.5, "the debrief waits for the victory line")
        local plain = outcomes(FAITHFUL, scenarios.win)
        check(plain == offline, "(and the faithful debrief is one second after the victory)")
    else
        check(faudio == oaudio, "offline plays the faithful audio sequence (" .. name .. "): " .. faudio .. " / " .. oaudio)
    end
    noEnemyTeamTwo(peer)
end
do
    local _, _, peer = outcomes({}, scenarios.nearTug)
    check(F.count(peer, "SetAIControl", 5) == 1 and F.count(peer, "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
end

-- ------------------------------------------------------------------ setup, teams, ownership
for n = 1, 4 do
    local w, p, m = setup(n, {})
    F.run(5)
    check(m.startDone and m.user == "crcca_players", "the player is the nearest-human token")
    if n > 1 then check(m.coopMissionStarted, "the shared mission started") end
    check(F.count(p[1], "SetAIControl", 5) == 1 and F.count(p[1], "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
    check(F.index(p[1], "SetAIControl") <= p[1].chunkCalls, "SetAIControl runs at chunk root, before Start")
    local scrap = F.callsOf(p[1], "SetScrap")
    check(#scrap == n and scrap[#scrap][2] == 1 and scrap[#scrap][3] == 0, n .. " human(s): the mission's zero scrap is not topped up per guest")
    for t = 2, n do
        local zeroed = false
        for _, c in ipairs(scrap) do if c[2] == t and c[3] == 0 then zeroed = true end end
        check(zeroed, "team " .. t .. " starts at zero scrap too")
    end
    if n > 1 then
        check(F.count(p[1], "SetPilot") == 0, "pilots are the shared lives in a network game")
    else
        check(F.count(p[1], "SetPilot") == 1 and F.last(p[1], "SetPilot")[2] == 1 and F.last(p[1], "SetPilot")[3] == 10, "offline the body sets its own pilots")
    end
    check(n == 1 or (p[1].rally and p[1].rally[0] == "recycler"), "respawns gather at the shared base")
    for i = 1, n do
        if n > 1 then check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i) end
        local o = F.callsOf(p[i], "AddObjective")
        check(o[1][2] == "ch05001.otf" and o[1][3] == "white", "first objective on peer " .. i)
    end
    perceivedAll(p, 5) -- the cover holds from the first frame, for every human
    F.run(4)
    heardAll(p, "ch05001.wav")
    guestsPassive(p)
    noEnemyTeamTwo(p[1])
    check(F.count(p[1], "Stop", "recycler") == 1, "the recycler is held")
end
do -- the scrap gate counts every human team (a guest's scav fills its own pool)
    local w, p, m = setup(3, {})
    F.run(2)
    check(not m.scoutsSpawned, "no scouts with no scrap")
    F.setScrap(3, 2); F.run(2)
    check(not m.scoutsSpawned, "two scrap are not enough")
    F.setScrap(3, 3); F.run(2)
    check(m.scoutsSpawned, "a guest's three scrap send the scouts")
    local scouts = F.builds(p[1], 0, "cvfighh")
    check(#scouts == 4, "four scouts")
    for _, b in ipairs(scouts) do
        check(b.team == 1 and F.perceived(b.h) == 5, "the scouts are Chinese craft the Soviets take for their own")
    end
    check(F.count(p[1], "SetCommand") == 3, "three wingmen form on the lead scout")
    check(F.count(p[1], "Goto", m.leadScout) == 1, "the lead scout follows the path")
end

-- ------------------------------------------------------------------ the disguise, the reveal, a respawn
for n = 1, 4 do
    local w, p, m = setup(n, {})
    stageScouts(w, p, m, n)
    perceivedAll(p, 5)
    -- a human's new ship (a respawn) is disguised too while the cover holds
    p[n].player = F.spawn("cvscav", p[n].team, 3860, 100900); F.run(2)
    check(F.perceived(p[n].player) == 5, n .. " human(s): a respawned ship is disguised")
    stageTug(w, p, m); stageConvoy(w, p, m)
    perceivedAll(p, 5)
    stageBase(w, p, m)
    perceivedAll(p, "own")
    local newShip = F.spawn("cvscav", p[n].team, 4000, 99100); p[n].player = newShip; F.run(3)
    check(F.perceived(newShip) == nil, "after the reveal a new ship is never disguised again")
    guestsPassive(p)
    noEnemyTeamTwo(p[1])
end

-- ------------------------------------------------------------------ the tug film: shared and unskippable
do
    local w, p, m = setup(3, {})
    stageScouts(w, p, m)
    check(not m.tugSpawned, "no tug before a human nears the fix")
    gather(p, "trigger_1", 330, 0)
    F.runUntil(function() return m.tugSpawned end, 10)
    local tug = F.builds(p[1], 0, "svhaul")
    check(#tug == 1 and tug[1].team == 5 and tug[1].where == "enemy_haul", "the Soviet tug is on the co-op enemy team")
    local defenders = F.builds(p[1], 0, "svfigh")
    check(#defenders == 2 and defenders[1].team == 5 and defenders[1].where == "haul_defend", "two escorts, built directly (not scaled)")
    check(F.count(p[1], "RemovePilot") == 3, "the escorts and the neutral scout are empty")
    check(F.count(p[1], "Defend2") == 2, "the escorts guard the tug")
    w.cancel = { [2] = true } -- a guest presses skip
    F.runUntil(function() return m.doHaulCam end, 10)
    F.run(5)
    check(m.doHaulCam, "a skip does not end the shared film")
    check(p[1].camera == 1 and p[3].camera == 1, "the others keep watching the film")
    check(p[2].camera == 0, "a skip releases only the skipper's own camera")
    w.cancel = { [1] = true }
    F.run(2)
    check(m.doHaulCam and p[1].camera == 0 and p[3].camera == 1, "not even the host's skip ends the shared film")
    w.cancel = false
    check(F.count(p[1], "CameraPath", "haul_cam") >= 4, "the host films the tug")
    F.run(12)
    check(not m.doHaulCam, "the film ends on its own timer")
    for i = 1, 3 do
        check(p[i].camera == 0, "peer " .. i .. " is released")
        local objectives = F.callsOf(p[i], "AddObjective")
        check(objectives[#objectives][2] == "ch05003.otf" and objectives[#objectives][3] == "white", "the follow-the-tug objective reaches peer " .. i)
        check(F.count(p[i], "SetObjectiveOn") >= 2, "the tug is marked on peer " .. i)
    end
    heardAll(p, "ch05005.wav")
    local scrap = 0
    for _, c in ipairs(F.callsOf(p[1], "RemoveObject")) do if c[2]:find("scrap", 1, true) then scrap = scrap + 1 end end
    check(scrap == 2, "the map's scrap is cleared: " .. scrap)
end
do -- offline the film can be skipped
    local w, p, m = setup(1, {})
    stageScouts(w, p, m); gather(p, "trigger_1", 330, 0)
    F.runUntil(function() return m.doHaulCam end, 10)
    w.cancel = true; F.run(1)
    check(not m.doHaulCam, "offline a skip ends the film")
end

-- ------------------------------------------------------------------ the strict rules read the nearest human
do
    local w, p, m = setup(3, {})
    F.place(p[2].player, 3000, 100900) -- one human wanders off: another is still at the silo
    F.place(p[3].player, 3000, 100900)
    F.run(6)
    check(F.count(p[1], "FailMission") == 0, "one human at the silo is enough")
    F.place(p[1].player, 3000, 100900); F.run(5)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "ch05lsea.des", "one shared failure on peer " .. i)
    end
end
do -- seen by the tug: any human within 175 m
    local w, p, m = setup(3, {})
    stageScouts(w, p, m); gather(p, "trigger_1", 330, 0)
    F.runUntil(function() return m.tugSpawned end, 10)
    F.nearTo(p[3].player, m.tug, 120, 0); F.run(4)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "ch05lseb.des", "peer " .. i .. " sees the convoy failure")
    end
end
do -- the convoy is lost only when every human is more than 500 m away
    local w, p, m = setup(3, {})
    stageScouts(w, p, m); stageTug(w, p, m)
    F.hook(m.neutralScout, m.tug); F.run(1)
    F.nearTo(p[2].player, m.tug, 900, 0); F.nearTo(p[3].player, m.tug, 900, 0); F.run(4)
    check(F.count(p[1], "FailMission") == 0, "one human in sight keeps the convoy")
    F.nearTo(p[1].player, m.tug, 900, 0); F.run(4)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "ch05lsed.des", "peer " .. i .. " loses the convoy together")
    end
    local builds = #F.builds(p[1])
    F.run(30)
    check(#F.builds(p[1]) == builds, "nothing is built after the loss")
end
do -- a destroyed tug does not break the body (stock bug: dead handles were read)
    local w, p, m = setup(2, {})
    stageScouts(w, p, m); stageTug(w, p, m)
    F.kill(m.tug); F.hook(m.neutralScout, m.tug); F.run(3)
    check(F.count(p[1], "FailMission") == 1 and F.last(p[1], "FailMission")[3] == "ch05lsed.des", "a lost tug is a lost convoy, with no error")
end

-- ------------------------------------------------------------------ the base is attacked: the convoy and the lines
for n = 1, 4 do
    local w, p, m = setup(n, {})
    stageScouts(w, p, m); stageTug(w, p, m)
    F.hook(m.neutralScout, m.tug); F.run(1)
    check(m.mustBeCloseToTug and F.count(p[1], "Goto", m.tug) == 1, "the tug sets out with its scout")
    F.nearTo(m.tug, "trigger_2", 50, 0); gather(p, m.tug, 330, 0)
    F.runUntil(function() return m.factory ~= nil end, 60)
    F.run(3)
    heardAll(p, "abetty6.wav"); heardAll(p, "abetty14.wav"); heardAll(p, "ch05006.wav")
    local lines = F.lines(p[1])
    local order = {}
    for _, l in ipairs(lines) do order[#order + 1] = l end
    local seq = table.concat(order, ",")
    check(seq:find(table.concat({ "ch05005.wav", "abetty6.wav", "abetty14.wav", "ch05006.wav" }, ","), 1, true), "the lines come in order: " .. seq)
    for i = 1, n do
        local adds = F.callsOf(p[i], "AddObjective")
        check(adds[#adds][2] == "ch05004.otf" and adds[#adds][3] == "white" and adds[#adds - 1][2] == "ch05003.otf" and adds[#adds - 1][3] == "green",
            "peer " .. i .. " shows the new objective")
        check(F.count(p[i], "SetObjectiveOff", m.tug) == 1, "the tug marker is lifted on peer " .. i)
    end
    check(F.count(p[1], "SetObjectiveName", m.navBase) == 1 and F.last(p[1], "SetObjectiveName")[3] == "Base", "the base nav is named")
    local scrap = F.callsOf(p[1], "SetScrap")
    check(scrap[#scrap][2] == 1 and scrap[#scrap][3] == 50, "the base is given 50 scrap")
    -- the convoy: recycler, factory, constructor, two escorts, on the Chinese side
    local builds = F.builds(p[1], 0)
    local seen = {}
    for _, b in ipairs(builds) do seen[b.odf] = b end
    check(seen.cvmuf and seen.cvcnst and seen.apcamr, "the factory, the constructor and the base nav are built")
    check(seen.cvmuf.team == 1 and seen.cvcnst.team == 1, "the convoy is team 1")
    check(F.count(p[1], "Follow") == 2, "the escorts follow the factory")
    guestsPassive(p)
    noEnemyTeamTwo(p[1])
end
do -- the cut "ns" objects are removed with the convoy
    local w, p, m = setup(2, {})
    stageScouts(w, p, m); stageTug(w, p, m)
    local stray = F.spawn("nsxx", 0, 3000, 99000)
    stageConvoy(w, p, m)
    check(not F.alive(stray), "the ns* objects are removed")
end

-- ------------------------------------------------------------------ the waves: scaling, entries, orders
for n = 1, 4 do
    local w, p, m = setup(n, {})
    toSiege(w, p, m)
    local e = extrasFor(n)
    check(m.wave1Time >= 900000, "the siege begins with wave 1")
    local function wave(where, field, wasDone)
        purge(w)
        local mark = #p[1].calls
        if field then goWave(w, p, m, field) end
        local units = {}
        for _, b in ipairs(F.builds(p[1], mark)) do if b.where == where then units[#units + 1] = b end end
        return units, mark
    end
    local first = {}
    for _, b in ipairs(F.builds(p[1], 0)) do if b.where == "wave_1" then first[#first + 1] = b end end
    check(#first == WAVE_UNITS.wave_1 + e, n .. " human(s): wave 1 is seven units + " .. e .. " extras, got " .. #first)
    allSafe(p, first)
    for _, b in ipairs(first) do check(b.team == 5 and SCALED[b.odf], "wave 1 craft are the co-op enemy") end
    local orders = 0
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[3] == "wave_1_path" then orders = orders + 1 end end
    check(orders == #first, "every wave 1 unit, extras included, got its path: " .. orders)
    for _, spec in ipairs({ { "wave_2", "wave2Time" }, { "wave_4", "wave4Time" }, { "wave_5", "wave5Time" }, { "wave_6", "wave6Time" } }) do
        local units = wave(spec[1], spec[2])
        check(#units == WAVE_UNITS[spec[1]] + e, n .. " human(s): " .. spec[1] .. " is " .. WAVE_UNITS[spec[1]] .. " + " .. e .. ", got " .. #units)
        allSafe(p, units)
        local ordered = 0
        for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[3] == spec[1] .. "_path" then ordered = ordered + 1 end end
        check(ordered == #units, spec[1] .. " orders replayed on every unit")
    end
    -- the raiders: one of two paths
    local raid = wave("annoy_1", "annoy1Time")
    check(#raid == 6 + e, n .. " human(s): the raid is six units + " .. e)
    allSafe(p, raid)
    guestsPassive(p)
    noEnemyTeamTwo(p[1])
end
do -- wave 3: soldiers hunt the base and the humans; the silo is a target again
    local w, p, m = setup(3, {})
    toSiege(w, p, m)
    local mark = #p[1].calls
    w.random = 2 -- the third target: recycler, factory, silo
    goWave(w, p, m, "wave3Time")
    local soldiers, users = F.builds(p[1], mark, "sssold"), F.builds(p[1], mark, "ssuser")
    check(#soldiers == 5 and #users == 2, "wave 3 is five soldiers and two sappers, built directly")
    for _, b in ipairs(soldiers) do check(b.team == 5 and b.where == "wave_3", "soldiers are the co-op enemy") end
    local atSilo, atHuman = 0, 0
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do
        if c[3] == "silo" then atSilo = atSilo + 1 end
        if isHuman(p, c[3]) and F.odf(c[2]) == "ssuser" then atHuman = atHuman + 1 end
    end
    check(atSilo == 5, "the cut silo target is back (RESTORED_SILO_TARGET): " .. atSilo)
    check(atHuman == 2, "the sappers hunt a human")
    -- offline == faithful for the target list: the recycler and the factory only
    local fw, fp, fm = setup(1, FAITHFUL)
    toSiege(fw, fp, fm)
    fw.random = 1 -- the last of two
    goWave(fw, fp, fm, "wave3Time")
    local fSilo = 0
    for _, c in ipairs(F.callsOf(fp[1], "Attack")) do if c[3] == "silo" then fSilo = fSilo + 1 end end
    check(fSilo == 0, "the faithful port never targets the silo")
end
do -- the paratroopers
    local w, p, m = setup(2, {})
    toSiege(w, p, m)
    local mark = #p[1].calls
    m.annoy2Time = w.now + 0.5; F.run(3)
    local drops = F.builds(p[1], mark, "sssold")
    check(#drops == 8, "eight paratroopers")
    for _, b in ipairs(drops) do check(b.team == 5 and type(b.where) == "table" and b.where.y > 400, "dropped 400 m up on the co-op enemy") end
    local hunters = 0
    for k = mark + 1, #p[1].calls do
        local c = p[1].calls[k]
        if c[1] == "Attack" and F.odf(c[2]) == "sssold" then hunters = hunters + 1 end
    end
    check(hunters == 8, "each paratrooper hunts the base: " .. hunters)
end
do -- the artillery: the daywreckers stop when both guns are down
    local w, p, m = setup(2, {})
    toSiege(w, p, m)
    local mark = #p[1].calls
    goWave(w, p, m, "day5Time")
    check(m.artl1 ~= nil and m.artl2 ~= nil, "the artillery stands")
    heardAll(p, "ch05007.wav")
    local arts = F.builds(p[1], mark, "svartl")
    check(#arts == 2 and arts[1].team == 5, "two guns on the co-op enemy, built directly")
    F.kill(m.artl1); F.kill(m.artl2); F.run(2)
    check(m.day7Time >= 999999 and m.day8Time >= 999999, "the daywreckers are cancelled")
end

-- ------------------------------------------------------------------ nothing within 460 m of a human; save/load keeps the wave
do
    local w, p, m = setup(3, {})
    toSiege(w, p, m)
    purge(w)
    local saved = {}
    for _, name in ipairs({"wave_1", "wave_2", "wave_4", "wave_5", "wave_6", "wave_7", "annoy_1"}) do
        saved[name] = w.pathPos[name]
        w.pathPos[name] = { x = 2000, y = saved[name].y, z = 97500 }
    end
    F.place(p[2].player, 2000, 97500)
    F.place(p[1].player, 20000, 20000); F.place(p[3].player, 20000, 20000)
    local mark = #p[1].calls
    goWave(w, p, m, "wave6Time")
    local built = 0
    for _, b in ipairs(F.builds(p[1], mark)) do if SCALED[b.odf] then built = built + 1 end end
    check(built == 0, "a fully watched map defers the whole wave")
    local pending = m.crcca.serial
    check(pending >= 8, "the tickets are saved")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    m = p[1].env.Save()
    check(m.crcca.serial == pending, "save/load keeps the pending wave without duplicating it")
    for name, pos in pairs(saved) do w.pathPos[name] = pos end
    F.place(p[2].player, 20000, 20000); F.run(8)
    built = 0
    local ordered = 0
    for _, b in ipairs(F.builds(p[1], mark)) do if SCALED[b.odf] then built = built + 1 end end
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[3] == "wave_6_path" then ordered = ordered + 1 end end
    check(built == 8 + 1, "the whole wave is built exactly once when the watcher leaves: " .. built)
    check(ordered >= 8 + 1, "the remembered orders reach every unit when the tickets are built: " .. ordered)
end
do -- the fallback entry: a human on the authored entry takes the wave from a hidden approach
    local w, p, m = setup(2, {})
    toSiege(w, p, m)
    purge(w)
    F.nearTo(p[2].player, "wave_6", 50, 0)
    F.nearTo(p[1].player, "base_1", 0, 60)
    local mark = #p[1].calls
    goWave(w, p, m, "wave6Time")
    local units = F.builds(p[1], mark)
    local count = 0
    for _, b in ipairs(units) do
        if SCALED[b.odf] then
            count = count + 1
            check(b.where == "wave_7", "the wave comes from the first hidden approach: " .. tostring(b.where))
        end
    end
    check(count == 8 + 1, "all of it, once: " .. count)
    allSafe(p, units)
end
do -- live cap: extras are the only requests dropped
    local w, p, m = setup(4, {})
    toSiege(w, p, m)
    purge(w)
    m.crcca.live = {}
    for i = 1, 40 do m.crcca.live[i] = F.spawn("svfigh", 5, 9000 + i, 9000) end
    local mark = #p[1].calls
    goWave(w, p, m, "wave4Time")
    local built = 0
    for _, b in ipairs(F.builds(p[1], mark)) do if SCALED[b.odf] then built = built + 1 end end
    check(built == 10, "at the live cap the wave keeps its primaries and drops the extras: " .. built)
end

-- ------------------------------------------------------------------ the last wave and the victory
for n = 1, 4 do
    local w, p, m = setup(n, {})
    toSiege(w, p, m)
    purge(w)
    local e = extrasFor(n)
    goWave(w, p, m, "wave7Time")
    check(m.wave7Spawned and m.numMustKill == 13, "wave 7 is thirteen must-kill primaries")
    local last = {}
    for _, b in ipairs(F.builds(p[1], 0)) do if b.where == "wave_7" then last[#last + 1] = b end end
    check(#last == 13 + e, n .. " human(s): thirteen + " .. e .. " extras, got " .. #last)
    allSafe(p, last)
    for i = 0, 12 do check(type(m.mustKill[i]) == "string", "the must-kill list holds real units, not tickets") end
    for i = 0, 12 do F.kill(m.mustKill[i]) end
    F.run(4)
    if e > 0 then
        check(not m.won and F.count(p[1], "SucceedMission") == 0, n .. " human(s): the co-op extras of wave 7 keep the mission going")
        for _, b in ipairs(last) do if F.alive(b.h) then F.kill(b.h) end end
    end
    F.run(20)
    check(m.won, n .. " human(s): the mission is won when wave 7 is dead")
    for i = 1, n do
        check(F.count(p[i], "SucceedMission") == 1 and F.last(p[i], "SucceedMission")[3] == "ch05win.des", "one shared victory on peer " .. i)
        check(F.count(p[i], "FailMission") == 0, "no failure after the win")
        check(F.heardCount(p[i], "ch05008.wav") == 1, "peer " .. i .. " hears the restored victory line once")
        local lines = F.lines(p[i])
        check(lines[#lines] == "ch05008.wav", "and it is the last line")
        check(F.last(p[i], "SucceedMission")[2] >= F.last(p[i], "SucceedMission").t + 5, "the result waits for the line")
        check((p[i].env.Save().coopUnresolved or 0) == 0, "no unresolved presentation identities on peer " .. i)
    end
    local function scaledBuilds() local c = 0; for _, b in ipairs(F.builds(p[1], 0)) do if SCALED[b.odf] then c = c + 1 end end return c end
    local total = scaledBuilds()
    m.annoy1Time = w.now + 1; m.wave6Time = w.now + 1
    F.run(300, 1)
    check(scaledBuilds() == total, "no wave is built after the result")
end

-- ------------------------------------------------------------------ results
do -- both producers lost
    local w, p, m = setup(3, {})
    stageScouts(w, p, m); stageTug(w, p, m); stageConvoy(w, p, m)
    F.kill("recycler"); F.run(3)
    check(F.count(p[1], "FailMission") == 0, "one producer left")
    F.kill(m.factory); F.run(10)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "ch05lsec.des", "one shared failure on peer " .. i)
        check(F.count(p[i], "SucceedMission") == 0, "no victory after a loss")
    end
    local builds = #F.builds(p[1])
    F.run(30)
    check(#F.builds(p[1]) == builds, "no reinforcement is built after the loss")
end
do -- raiders at a dead base: no order on a missing target
    local w, p, m = setup(2, {})
    stageScouts(w, p, m); stageTug(w, p, m); stageConvoy(w, p, m); stageBase(w, p, m)
    F.kill("recycler"); F.kill(m.factory); F.kill("silo")
    local ok = pcall(function() m.annoy2Time = w.now + 0.2; F.run(3) end)
    check(ok, "raiders against a base that is gone cause no error")
end
do -- the lives are the shared ones: one dead human fails nothing
    local w, p, m = setup(3, {})
    F.run(3)
    F.kill(p[1].player); F.run(10)
    check(F.count(p[1], "FailMission") == 0 and F.count(p[2], "FailMission") == 0, "one dead human never fails a network mission")
    check(m.lost ~= true, "the body is not told")
end

-- ------------------------------------------------------------------ stock bugs: a line that never starts, loads
do
    local w, p, m = setup(1, { nilAudio = true })
    F.run(5)
    stageScouts(w, p, m)
    check(m.objective1Complete, "a line the engine cannot play does not stall the chain")
    local fw, fp, fm = setup(1, { faithful = true, script = F.FAITHFUL, nilAudio = true })
    F.setScrap(1, 3); F.run(1)
    F.nearTo(fm.leadScout, "trigger_1", 10, 0); F.run(20)
    check(fm.objective1Complete == false, "(the faithful body does stall on a line without a handle)")
end
do -- the audio chain gate: a busy line holds the next
    local w, p, m = setup(2, { busy = true })
    F.setScrap(1, 3); F.run(1)
    F.nearTo(m.leadScout, "trigger_1", 10, 0); F.run(20)
    check(not m.objective1Complete, "a line that is still playing holds the chain")
    w.audioBusy = false; F.run(20)
    check(m.objective1Complete, "the chain resumes when the line is done")
end
do -- a load right after the scouts republishes the objective and the markers
    local w, p, m = setup(3, {})
    stageScouts(w, p, m)
    local marks = {}
    for i, q in ipairs(p) do marks[i] = #q.calls end
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    m = p[1].env.Save()
    for i, q in ipairs(p) do
        local adds, names, ons = {}, 0, 0
        for k = marks[i] + 1, #q.calls do
            local c = q.calls[k]
            if c[1] == "AddObjective" then adds[#adds + 1] = c[2] .. "/" .. c[3] end
            if c[1] == "SetObjectiveName" and c[3] == "Last GPS Fix" then names = names + 1 end
            if c[1] == "SetObjectiveOn" then ons = ons + 1 end
        end
        check(table.concat(adds, ",") == "ch05001.otf/green,ch05002.otf/white", "peer " .. i .. " republishes " .. table.concat(adds, ","))
        check(names == 1 and ons == 1, "peer " .. i .. " sees the Last GPS Fix again")
    end
    stageTug(w, p, m)
    check(m.tugSpawned, "the mission goes on after the load")
end
do -- a load during the film, and one after the convoy
    local w, p, m = setup(2, {})
    stageScouts(w, p, m); gather(p, "trigger_1", 330, 0)
    F.runUntil(function() return m.doHaulCam end, 10); F.run(3)
    local marks = {}
    for i, q in ipairs(p) do marks[i] = #q.calls end
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(2)
    m = p[1].env.Save()
    check(m.doHaulCam and F.count(p[1], "CameraReady") >= 2, "the host takes the film up again after a load")
    F.run(16)
    check(not m.doHaulCam and p[1].camera == 0 and p[2].camera == 0, "the film still ends")
    stageConvoy(w, p, m); stageBase(w, p, m)
    marks = {}
    for i, q in ipairs(p) do marks[i] = #q.calls end
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    m = p[1].env.Save()
    for i, q in ipairs(p) do
        local adds, base = {}, 0
        for k = marks[i] + 1, #q.calls do
            local c = q.calls[k]
            if c[1] == "AddObjective" then adds[#adds + 1] = c[2] .. "/" .. c[3] end
            if c[1] == "SetObjectiveName" and c[3] == "Base" then base = base + 1 end
        end
        check(table.concat(adds, ",") == "ch05003.otf/green,ch05004.otf/white", "peer " .. i .. " republishes " .. table.concat(adds, ","))
    end
    check(F.count(p[1], "BuildObject", nil) > 0, "the world is intact")
end

-- ------------------------------------------------------------------ leader leaves
do
    local w, p, m = setup(3, {})
    for i = 2, 3 do p[i].env.DeletePlayer(1) end
    F.run(3)
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
local function elysium(record, mode)
    return function(peer)
        local V = { Seed = 4242, Initialized = false }
        function V.Init(o) peer.weatherInit = o; V.Initialized = true; record("ElysiumInit", o.authority, o.send ~= nil, o.seed, o.startLevel, o.targetLevel)
            if mode == "initfail" then error("boom") end end
        function V.Update(dt)
            if peer.weatherInit and peer.weatherInit.authority and peer.weatherInit.send and not V.sent then
                V.sent = true; peer.weatherInit.send("VenusStrike", 1, 0.3, 3, 1)
            end
            if mode == "updatefail" then error("update boom") end
        end
        function V.AnnounceState() record("ElysiumAnnounce") end
        function V.ApplyNetEvent(op, ...) record("ElysiumEvent", op, ...) end
        function V.SetTargetLevel(n) record("ElysiumLevel", n) end
        function V.ForceLevel(n, seconds, blend) record("ElysiumForce", n, seconds, blend) end
        function V.TriggerStrike(target) record("ElysiumStrike", target.x, target.z) end
        function V.OnObjectCreated(h) record("ElysiumCreated", h) end
        function V.Save() return { saved = true } end
        function V.Load(s) record("ElysiumLoad", s and s.saved) end
        function V.Shutdown() record("ElysiumShutdown") end
        return V
    end
end
do
    local sites = dofile("Scripts/CRElysiumSitesCH05.lua")
    check(sites.mission == "chmisn05" and #sites.vents == 3, "the generated sites for this map carry its three geysers")
    local weather = { module = function(peer, record) return elysium(record)(peer) end, sites = sites }
    local w, p, m = setup(3, { weather = weather })
    check(F.count(p[1], "ElysiumInit", true) == 1 and F.last(p[1], "ElysiumInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.last(p[1], "ElysiumInit")[5] == 1 and F.last(p[1], "ElysiumInit")[6] == 1, "the weather starts calm and holds")
    check(F.count(p[2], "ElysiumInit", false) == 1, "guests render only (not the authority)")
    check(F.count(p[1], "ElysiumAnnounce") == 1 and F.count(p[2], "ElysiumAnnounce") == 0, "the leader announces its weather state once")
    check(F.count(p[1], "EnvironmentInit") == 1, "the environment is initialised once")
    for i = 2, 3 do
        local e = F.last(p[i], "ElysiumEvent")
        check(e and e[2] == "VenusStrike" and e[3] == 1, "weather events reach guest " .. i)
    end
    check(p[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    check(F.count(p[1], "ElysiumLevel") == 0, "calm until the first scrap")
    stageScouts(w, p, m)
    check(F.count(p[1], "ElysiumLevel", 2) == 1, "the first scrap brings the haze")
    stageTug(w, p, m)
    check(F.count(p[1], "ElysiumLevel", 3) == 1, "the tug closes the sky")
    stageConvoy(w, p, m); F.run(1)
    check(F.count(p[1], "ElysiumLevel", 4) == 1 and F.count(p[1], "ElysiumStrike") == 1 and F.last(p[1], "ElysiumStrike")[2] == 4080,
        "the attack on the base breaks the storm with a strike over it")
    stageBase(w, p, m); stageSiege(w, p, m)
    check(F.count(p[1], "ElysiumStrike") == 2 and F.last(p[1], "ElysiumStrike")[2] == 3055.06, "the siege opens under a strike at the first entry")
    goWave(w, p, m, "wave4Time"); F.run(1)
    check(F.count(p[1], "ElysiumLevel", 5) == 1, "the armour brings the worst of it")
    goWave(w, p, m, "day5Time")
    check(F.count(p[1], "ElysiumStrike") == 3 and F.last(p[1], "ElysiumStrike")[2] == 2211.92, "lightning walks over the artillery")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "ElysiumShutdown") >= 1 and F.count(p[1], "ElysiumLoad", true) == 1, "load restores the leader's weather state")
    m = p[1].env.Save()
    purge(w)
    goWave(w, p, m, "wave7Time"); F.run(1)
    check(F.count(p[1], "ElysiumForce", 5, 100.0, 12.0) == 1, "the last wave forces a violent burst")
    for i = 0, 12 do F.kill(m.mustKill[i]) end
    purge(w)
    F.run(20)
    check(m.won and F.count(p[1], "ElysiumLevel", 2) == 2, "the debrief eases the sky")
    check(F.count(p[1], "ElysiumCreated") > 0, "new objects are offered to the weather")
    check(F.count(p[2], "ElysiumLevel") == 0 and F.count(p[2], "ElysiumForce") == 0 and F.count(p[2], "ElysiumStrike") == 0, "guests never decide weather events")
end
do -- sites module missing: no weather, never an error
    local w, p, m = setup(2, { weather = { module = function(peer, record) return elysium(record)(peer) end } })
    check(F.count(p[1], "ElysiumInit") == 0 and m.startDone, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local w, p, m = setup(2, { weather = { module = function(peer, record) return elysium(record, mode)(peer) end, sites = dofile("Scripts/CRElysiumSitesCH05.lua") } })
    stageScouts(w, p, m)
    check(m.objective1Complete and F.count(p[1], "FailMission") == 0, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("chmisn05 co-op: " .. checks .. " checks passed")
