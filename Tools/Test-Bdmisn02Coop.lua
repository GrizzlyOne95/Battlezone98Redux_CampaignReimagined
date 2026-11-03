-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/bdmisn02cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/Test-Bdmisn02Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Bdmisn02Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local MS = { STARTUP = 0, FIRSTWAVE = 1, WAITFORSOUND1 = 2, WAITFORWAVE1 = 3, PLAYDECLOCK = 4, WAITINGOBJ2 = 5, WAVE1DEAD = 6,
    WAITFORWAVE2 = 7, WAVE2DEAD = 8, PLAYSOUND4 = 9, WAITFORSOUND4 = 10, WAITFORSOUND5 = 11, HARRASDEAD = 13,
    WAITFORBOMBERRUN = 14, BOMBERRUN = 15, RECYCLERDIE = 16, ENDWAIT = 17, END = 18 }
local function extrasFor(n) return math.min(math.floor(n / 2), 2) end

local function setup(n, options)
    options = options or {}
    local w = F.reset()
    w.audioBusy = options.busy == true
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
local function toState(m, state, limit) F.runUntil(function() return m.missionState >= state end, limit or 200) end
local function builtAt(peer, where, odf)
    local out = {}
    for _, b in ipairs(F.builds(peer, 0, odf)) do if b.where == where then out[#out + 1] = b end end
    return out
end
local function allSafe(p, builds)
    for _, b in ipairs(builds) do
        for _, q in ipairs(p) do
            check(q.env.GetDistance(q.player, b.h) >= 460, "no scripted ticket is built within 460 m of any human: " .. tostring(b.where))
        end
    end
end
local function heardAll(p, file, count)
    for i, q in ipairs(p) do check(F.heardCount(q, file) == (count or 1), "peer " .. i .. " hears " .. file .. " x" .. (count or 1)) end
end
local function guestsPassive(p)
    for i = 2, #p do
        for _, name in ipairs({"BuildObject", "SetScrap", "SetAIP", "Goto", "Attack", "Stop", "SetCloaked"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on the authored enemy team 2") end
end
local WAVE1 = { "wave1_scout1", "wave1_scout2", "wave1_tank1" }
local WAVE2 = { "wave2_scout1", "wave2_scout2", "wave2_scout3", "wave2_scout4" }
local function killAll(m, keys) for _, k in ipairs(keys) do if type(m[k]) == "string" then F.kill(m[k]) end end end
local function isHuman(p, h) for _, q in ipairs(p) do if q.player == h then return true end end return false end

-- Plays the whole mission as a host would see it; `hook` runs at named points.
local function playthrough(w, m, hook)
    hook = hook or function() end
    w.cameraDone["camera_decloak"] = true
    toState(m, MS.WAVE1DEAD, 120); F.run(1)
    hook("wave1")
    killAll(m, WAVE1)
    toState(m, MS.WAVE2DEAD, 80); F.run(1)
    hook("wave2")
    killAll(m, WAVE2)
    toState(m, MS.HARRASDEAD, 80); F.run(1)
    hook("retreat")
    w.objects.recycler.command = 0
    toState(m, MS.BOMBERRUN, 40); F.run(1)
    hook("bombers")
    F.nearTo(m.bomber1_scripted, "camera_bomber_chasecam", 10, 0)
    toState(m, MS.RECYCLERDIE, 20); F.run(1)
    hook("film")
    w.objects.recycler.health = 0.5; F.run(1)
    F.kill("recycler")
    toState(m, MS.END, 40); F.run(1)
    hook("end")
end

-- ------------------------------------------------------------------ offline == faithful
local function outcomes(options, scenario)
    local w, p, m = setup(1, options)
    scenario(w, p, m)
    local out = {}
    for _, name in ipairs({"SucceedMission", "FailMission"}) do
        for _, c in ipairs(F.callsOf(p[1], name)) do out[#out + 1] = name .. ":" .. tostring(c[3]) end
    end
    return table.concat(out, ","), p[1], w
end
local scenarios = {
    win = function(w, p, m) playthrough(w, m); F.run(8) end,
    playerdies = function(w, p, m) F.run(3); F.kill(p[1].player); F.run(6) end,
    recyclerlost = function(w, p, m) F.run(3); F.kill("recycler"); F.run(4) end,
}
for name, scenario in pairs(scenarios) do
    local faithful = outcomes({ faithful = true, script = "Scripts/bd02.lua" }, scenario)
    local offline = outcomes({}, scenario)
    -- the only intended difference: the debrief that does not ship (see "Stock bugs fixed in the CR layer")
    check(faithful:gsub("bd02lsea", "bd02lose") == offline and offline ~= "", "offline completes like the faithful port (" .. name .. "): " .. faithful .. " / " .. offline)
end
do
    local out, peer = outcomes({}, scenarios.win)
    check(out == "SucceedMission:bd02win.des" and F.count(peer, "SucceedMission") == 1, "offline victory: " .. out)
    noEnemyTeamTwo(peer)
    local lost, lpeer = outcomes({}, scenarios.playerdies)
    check(lost == "FailMission:bd02lose.des" and F.count(lpeer, "FailMission") == 1, "offline player death: " .. lost)
    local gone, gpeer = outcomes({}, scenarios.recyclerlost)
    check(gone == "FailMission:bd02lose.des" and F.count(gpeer, "FailMission") == 1, "offline recycler loss uses the debrief that ships: " .. gone)
    check(select(1, outcomes({ faithful = true, script = "Scripts/bd02.lua" }, scenarios.recyclerlost)) == "FailMission:bd02lsea.des",
        "the faithful body still names the missing debrief")
end
check(F.count(select(2, outcomes({}, scenarios.win)), "SetAIControl", 5) == 1, "AI control only for enemy team 5 at chunk load")

-- ------------------------------------------------------------------ teams, ownership, humans as the player
do
    local w, p, m = setup(4, {})
    F.run(3)
    check(m.coopMissionStarted and m.missionState >= MS.FIRSTWAVE, "leader starts the shared mission")
    check(m.user == "crcca_players", "the player is the nearest-human token")
    check(F.count(p[1], "SetAIControl", 5) == 1 and F.count(p[1], "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
    check(F.index(p[1], "SetAIControl") <= p[1].chunkCalls, "SetAIControl runs at chunk root, before Start")
    local scrap = F.callsOf(p[1], "SetScrap")
    check(#scrap == 1 and scrap[1][2] == 1 and scrap[1][3] == 20 + 10 * 3, "starting scrap on the shared base grows by 10 per guest: " .. tostring(scrap[1] and scrap[1][3]))
    check(F.count(p[1], "SetPilot") == 0, "pilots are the shared lives in a network game")
    check(F.count(p[1], "SetCloaked") == 4, "the four map turrets are cloaked")
    check(F.team("enemy_turret1") == 5 and F.team("enemy_turret3") == 5, "the authored Chinese turrets are on the co-op enemy team")
    for i = 1, 4 do
        check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
        local o = F.callsOf(p[i], "AddObjective")
        check(o[1][2] == "bd02001.otf" and o[1][3] == "white", "first objective on peer " .. i)
    end
    check(p[1].rally and p[1].rally[0] == "recycler", "respawns gather at the shared recycler")
    heardAll(p, "bd02001.wav")
    guestsPassive(p)
end
do -- offline keeps the DLL's pilots
    local w, p, m = setup(1, {})
    check(F.count(p[1], "SetPilot") == 1 and F.last(p[1], "SetPilot")[2] == 1, "offline the body sets its own pilots")
    check(F.last(p[1], "SetScrap")[3] == 20, "offline starting scrap is 20")
end

-- ------------------------------------------------------------------ wave 1: stage-prop scout, scaled rest, the shared decloak film
for n = 1, 4 do
    local w, p, m = setup(n, {})
    toState(m, MS.PLAYDECLOCK, 60)
    F.run(1)
    local e = extrasFor(n)
    local scout1 = builtAt(p[1], "spawn_wave1_scout1")
    check(#scout1 == 1 and scout1[1].odf == "cvfigh" and scout1[1].team == 5, n .. " human(s): the camera scout is one stage prop, never scaled")
    local scouts = builtAt(p[1], "spawn_wave1_scout2", "cvfigh")
    check(#scouts == 1 + e, n .. " human(s): wave 1 scouts = 1 + " .. e .. " extras, got " .. #scouts)
    check(#builtAt(p[1], "spawn_wave1_tank1", "cvtnk") == 1, "the tank is not mirrored (extras copy the first scaled unit)")
    allSafe(p, scouts); allSafe(p, builtAt(p[1], "spawn_wave1_tank1"))
    for _, b in ipairs(F.builds(p[1])) do check(b.team == 5, "wave 1 is team 5") end
    check(type(m.wave1_scout1) == "string" and type(m.wave1_scout2) == "string" and type(m.wave1_tank1) == "string", "tickets resolved to real units")
    local gotos = 0
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[3] == "wave1_scout2_attackpath" then gotos = gotos + 1 end end
    check(gotos == 1 + e, "the extras mirror the first scout's attack path: " .. gotos)
    check(F.count(p[1], "Goto", m.wave1_scout1) == 1 and F.count(p[1], "Goto", m.wave1_tank1) == 1, "the body's own orders reach the real units")
    -- the decloak film: every peer is in the shot, unskippable in a network game
    for i = 1, n do
        check(p[i].camera == 1 and F.last(p[i], "CameraPath")[2] == "camera_decloak", "peer " .. i .. " is in the decloak shot")
    end
    check(F.last(p[1], "CameraPath")[5] == m.wave1_scout1, "the shot follows the stage-prop scout")
    heardAll(p, "bd02002.wav")
    w.cancel = true; F.run(1)
    if n > 1 then
        check(m.missionState == MS.PLAYDECLOCK, "a skip never ends the shared film in a network game")
        w.cancel = false
        -- the host's skip released its own view for good, so the host's camera never arrives: stock hang. The
        -- CR layer ends the film as the body would, after its guard (30 s).
        F.run(20)
        check(m.missionState == MS.PLAYDECLOCK, "the guard does not end the film early")
        F.run(12)
    else
        check(m.missionState > MS.PLAYDECLOCK and p[1].camera == 0, "offline the film is skippable")
        w.cancel = false
    end
    check(m.missionState >= MS.WAITINGOBJ2, "the film ends (n=" .. n .. ", state " .. m.missionState .. ")")
    for i = 1, n do check(p[i].camera == 0, "decloak cameras balanced on peer " .. i) end
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end

-- ------------------------------------------------------------------ wave 2: a hidden approach when the entry is watched
for n = 1, 4 do
    local w, p, m = setup(n, {})
    w.cameraDone["camera_decloak"] = true
    toState(m, MS.WAVE1DEAD, 80); F.run(1)
    heardAll(p, "bd02003.wav")
    killAll(m, WAVE1)
    toState(m, MS.WAVE2DEAD, 60); F.run(1)
    local e = extrasFor(n)
    check(#builtAt(p[1], "spawn_wave2_scout3") == 0 and #builtAt(p[1], "spawn_wave2_scout4") == 0,
        "the two scouts whose spawn is 386 m from the base come from a hidden approach instead")
    local late = 0
    for _, b in ipairs(F.builds(p[1], 0, "cvfigh")) do if b.where:match("^spawn_wave2_scout[12]$") then late = late + 1 end end
    check(late == 2 + e, n .. " human(s): the two clear scouts of wave 2 are built at their own points with " .. e .. " extras, got " .. late)
    local all = F.builds(p[1], 0, "cvfigh")
    check(#all == 1 + (1 + e) + (4 + e), n .. " human(s): fighters = stage scout + wave 1 scouts + wave 2, got " .. #all)
    for _, b in ipairs(all) do
        if b.where ~= "spawn_wave1_scout1" then
            for _, q in ipairs(p) do check(q.env.GetDistance(q.player, b.h) >= 460, "wave units never appear within 460 m: " .. b.where) end
        end
    end
    -- TRO 1.3: wave 2 attacks the recycler directly (no authored attack paths).
    local fighters, attacks = {}, 0
    for _, b in ipairs(all) do fighters[b.h] = true end
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do if c[3] == "recycler" and fighters[c[2]] then attacks = attacks + 1 end end
    check(attacks == 4 + e, "wave 2 orders are mirrored on the extras: " .. attacks)
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end

-- ------------------------------------------------------------------ the massive attack: a stage, not a fight
for n = 1, 4 do
    local w, p, m = setup(n, { busy = false })
    w.cameraDone["camera_decloak"] = true
    toState(m, MS.WAVE1DEAD, 80); F.run(1); killAll(m, WAVE1)
    toState(m, MS.WAVE2DEAD, 60); F.run(1); killAll(m, WAVE2)
    w.audioBusy = true
    toState(m, MS.WAITFORSOUND4, 40); F.run(1)
    local stage = {}
    for _, b in ipairs(F.builds(p[1])) do if b.where:match("^spawn_enemy_") then stage[#stage + 1] = b end end
    check(#stage == 8, n .. " human(s): the massive attack is exactly eight stage props, no extras, got " .. #stage)
    for _, b in ipairs(stage) do check(b.team == 5 and F.alive(b.h), "stage unit is on the enemy team") end
    check(type(m.enemy_tank1) == "string" and type(m.enemy_scout4) == "string", "every stage unit is a real handle at once")
    for i = 1, n do
        local c = F.last(p[i], "CameraPath")
        check(p[i].camera == 1 and c[2] == "camera_massive_attack" and c[5] == m.enemy_tank1, "peer " .. i .. " watches the stage tank")
    end
    heardAll(p, "bd02004.wav")
    for i = 1, 4 do
        local sent = 0
        for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[2] == "enemy_turret" .. i and c[3] == "path_turret" .. i then sent = sent + 1 end end
        check(sent == 1, "turret " .. i .. " is sent along its path")
    end
    w.audioBusy = false
    F.run(1); w.audioBusy = true; F.run(1)
    heardAll(p, "bd02005.wav")
    w.audioBusy = false; F.run(2)
    check(m.missionState >= MS.HARRASDEAD, "the sequence continues")
    for i = 1, n do check(p[i].camera == 0, "massive attack cameras balanced on peer " .. i) end
    local removed = {}
    for _, c in ipairs(F.callsOf(p[1], "RemoveObject")) do removed[c[2]] = true end
    for _, b in ipairs(stage) do check(removed[b.h], "the stage unit is removed with the film") end
    local nav = builtAt(p[1], "spawn_nav_alpha", "apcamr")
    check(#nav == 1 and nav[1].team == 1, "Nav Alpha is a team-1 beacon")
    check(F.count(p[1], "SetObjectiveName", m.nav_alpha) == 1, "Nav Alpha is named on every peer's list")
    noEnemyTeamTwo(p[1])
end

-- ------------------------------------------------------------------ the retreat: harassment, the six-fighter ambush, the bomber run
local function toRetreat(n, options)
    local w, p, m = setup(n, options or {})
    w.cameraDone["camera_decloak"] = true
    toState(m, MS.WAVE1DEAD, 80); F.run(1); killAll(m, WAVE1)
    toState(m, MS.WAVE2DEAD, 60); F.run(1); killAll(m, WAVE2)
    toState(m, MS.HARRASDEAD, 60); F.run(1)
    return w, p, m
end
for n = 1, 4 do
    local w, p, m = toRetreat(n)
    local e = extrasFor(n)
    do
        local sent = 0
        for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[2] == "recycler" and c[3] == "path_recycler_retreat" then sent = sent + 1 end end
        check(sent == 1, "the recycler retreats")
    end
    local harrass = builtAt(p[1], "spawn_scout1_harrass")
    check(#harrass == 1 + e and #builtAt(p[1], "spawn_ltnk1_harrass") == 1, n .. " human(s): harassers = fighter + extras + light tank")
    allSafe(p, harrass)
    -- Goto(harrasser, the player) is Goto(harrasser, the nearest human), also for extras
    local follows = 0
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do
        if isHuman(p, c[3]) then follows = follows + 1; check(type(c[2]) == "string" and F.team(c[2]) == 5, "the harassers chase a human") end
    end
    check(follows == 2 + e, "every harasser chases the nearest human, extras included: " .. follows)
    -- the ambush at trigger_1: six fighters on the nearest human (3-4 humans stand within 460 m of fighter_1,
    -- so the fighters come from a hidden fallback approach)
    local mark = #p[1].calls
    F.nearTo("recycler", "trigger_1", 40, 0); F.run(3)
    local ambush = F.builds(p[1], mark, "cvfigh")
    check(#ambush == 6 + e, n .. " human(s): the ambush is six fighters + " .. e .. " extras, got " .. #ambush)
    allSafe(p, ambush)
    check((ambush[1].where == "fighter_1") == (n < 3), "the ambush uses its own entry only when it is clear (" .. n .. " humans)")
    local attackers = 0
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do
        if isHuman(p, c[3]) and F.team(c[2]) == 5 then attackers = attackers + 1 end
    end
    check(attackers == 6 + e, "all ambushers attack a human, extras included: " .. attackers)
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do
        if isHuman(p, c[3]) then
            local nearest, best
            for _, q in ipairs(p) do
                local d = q.env.GetDistance(c[2], q.player)
                if best == nil or d < best then nearest, best = q.player, d end
            end
            check(c[3] == nearest, "an order at the player goes to the human nearest the unit")
        end
    end
    F.run(2)
    check(#F.builds(p[1], mark, "cvfigh") == 6 + e, "the ambush fires once")
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end
-- ------------------------------------------------------------------ bombers: the restored routes, then the film
for n = 1, 3 do
    local w, p, m = toRetreat(n)
    F.nearTo("recycler", "trigger_1", 40, 0); F.run(1)
    w.objects.recycler.command = 0
    w.audioBusy = true
    toState(m, MS.WAITFORBOMBERRUN, 20); F.run(1)
    heardAll(p, "bd02006.wav")
    w.audioBusy = false
    toState(m, MS.BOMBERRUN, 20); F.run(1)
    local b1, b2 = m.bomber1_scripted, m.bomber2_scripted
    check(type(b1) == "string" and type(b2) == "string", "two scripted bombers")
    check(#builtAt(p[1], "spawn_bomber_1", "cvhraz") == 1 and #builtAt(p[1], "spawn_bomber_2", "cvhraz") == 1, "bombers are never scaled")
    check(F.team(b1) == 5 and F.team(b2) == 5, "bombers are the enemy team")
    heardAll(p, "bd02007.wav")
    -- routes first: the body's Attack in the build frame is replaced by the authored route in the same frame
    local function lastOrder(h)
        local last
        for _, c in ipairs(p[1].calls) do if (c[1] == "Goto" or c[1] == "Attack") and c[2] == h then last = c end end
        return last
    end
    check(lastOrder(b1)[1] == "Goto" and lastOrder(b1)[3] == "path_bomber_1_attackpath", "bomber 1 flies its authored route")
    check(lastOrder(b2)[1] == "Goto" and lastOrder(b2)[3] == "path_bomber_2_attackpath", "bomber 2 flies its authored route")
    F.run(6)
    check(lastOrder(b1)[1] == "Goto", "while the route is flown the bombers do not attack")
    -- bomber 1 finishes its route at the camera trigger: both attack, the film starts
    w.objects[b1].command = 0
    F.nearTo(b1, "camera_bomber_chasecam", 10, 0)
    F.run(2)
    check(m.missionState == MS.RECYCLERDIE, "the chase-camera trigger starts the film")
    check(lastOrder(b1)[1] == "Attack" and lastOrder(b1)[3] == "recycler" and lastOrder(b2)[1] == "Attack", "both bombers attack the recycler once the film starts")
    for i = 1, n do check(p[i].camera == 1 and F.last(p[i], "CameraPath")[2] == "camera_bomber_chasecam", "peer " .. i .. " is in the chase shot") end
    local attacks = F.count(p[1], "Attack", b1)
    F.run(4)
    check(F.count(p[1], "Attack", b1) == attacks, "the bombers are ordered once")
    -- the harassers were removed with the pair (extras included)
    local removed = {}
    for _, c in ipairs(F.callsOf(p[1], "RemoveObject")) do removed[c[2]] = true end
    for _, b in ipairs(F.builds(p[1], 0)) do
        if b.where == "spawn_scout1_harrass" or b.where == "spawn_ltnk1_harrass" then check(removed[b.h], "harassment unit removed: " .. b.h) end
    end
    -- hit, then destroyed
    w.objects.recycler.health = 0.9; F.run(1)
    heardAll(p, "bd02008.wav")
    w.audioBusy = true
    F.kill("recycler"); F.run(2)
    heardAll(p, "bd02009.wav")
    check(m.missionState == MS.RECYCLERDIE, "the end waits for the last narration")
    w.audioBusy = false; F.run(5)
    check(m.missionState == MS.END, "the final hold ends the mission")
    F.run(8)
    for i = 1, n do
        check(F.count(p[i], "SucceedMission") == 1 and F.last(p[i], "SucceedMission")[3] == "bd02win.des", "one shared victory on peer " .. i)
        check(F.count(p[i], "FailMission") == 0, "no failure after the win")
        check(p[i].camera == 0, "final cameras balanced on peer " .. i)
        check((p[i].env.Save().coopUnresolved or 0) == 0, "no unresolved presentation identities on peer " .. i)
    end
    local lastAttack = F.count(p[1], "Attack", b1)
    F.run(10)
    check(F.count(p[1], "Attack", b1) == lastAttack, "nothing further after the result")
end
do -- a bomber that never finishes its route attacks after 60 s
    local w, p, m = toRetreat(2)
    F.nearTo("recycler", "trigger_1", 40, 0); F.run(1)
    w.objects.recycler.command = 0
    toState(m, MS.BOMBERRUN, 30)
    local b1 = m.bomber1_scripted
    F.run(1)
    local base = F.count(p[1], "Attack", b1) -- the body's own order in the build frame
    F.run(30)
    check(F.count(p[1], "Attack", b1) == base, "still flying the route after 30 s")
    F.run(34)
    check(F.count(p[1], "Attack", b1) == base + 1, "the route times out into the attack")
end
do -- a map without the routes: the faithful attack order stands
    local w = F.reset()
    w.missingPaths = { path_bomber_1_attackpath = true, path_bomber_2_attackpath = true }
    local p = { F.makePeer(1, 1, false, {}) }
    F.connect(); F.run(1)
    local m = p[1].env.Save()
    w.cameraDone["camera_decloak"] = true
    toState(m, MS.WAVE1DEAD, 80); F.run(1); killAll(m, WAVE1)
    toState(m, MS.WAVE2DEAD, 60); F.run(1); killAll(m, WAVE2)
    toState(m, MS.HARRASDEAD, 60); F.run(1)
    F.nearTo("recycler", "trigger_1", 40, 0); F.run(1)
    w.objects.recycler.command = 0
    toState(m, MS.BOMBERRUN, 30)
    F.run(70)
    check(F.count(p[1], "Attack", m.bomber1_scripted) == 1 and F.count(p[1], "Goto", m.bomber1_scripted) == 0, "no route on the map: the body's Attack stands")
end
do -- the recycler vanishes before the end (stock CameraPathDir fallback): the shot stays on the shared stream
    local w, p, m = toRetreat(3)
    F.nearTo("recycler", "trigger_1", 40, 0); F.run(1)
    w.objects.recycler.command = 0
    toState(m, MS.BOMBERRUN, 30)
    F.nearTo(m.bomber1_scripted, "camera_bomber_chasecam", 10, 0)
    toState(m, MS.RECYCLERDIE, 10)
    w.objects.recycler.alive = false
    F.run(2)
    check(F.count(p[1], "CameraPathDir") == 0, "the native direction camera is never called")
    local c = F.last(p[1], "CameraPath")
    check(c[2] == "camera_bomber_chasecam" and c[5] == m.bomber1_scripted, "the fallback shot follows a bomber on the shared stream")
    for i = 2, 3 do check(F.last(p[i], "CameraPath")[2] == "camera_bomber_chasecam", "guest " .. i .. " still sees the shot") end
end

-- ------------------------------------------------------------------ results
do -- recycler lost mid-mission: the debrief that ships, once, shared
    local w, p, m = setup(3, {})
    F.run(5); F.kill("recycler"); F.run(10)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd02lose.des", "one shared failure on peer " .. i)
        check(F.count(p[i], "SucceedMission") == 0, "no victory after a loss")
    end
    local builds = #F.builds(p[1])
    F.run(30)
    check(#F.builds(p[1]) == builds, "no reinforcement is built after the loss")
end
do -- a human dying does not fail the shared mission (the shared lives decide)
    local w, p, m = setup(3, {})
    F.run(5); F.kill(p[1].player); F.run(10)
    check(F.count(p[1], "FailMission") == 0 and F.count(p[2], "FailMission") == 0, "one dead human never fails a network mission")
    F.kill(p[2].player); F.kill(p[3].player); F.run(10)
    check(m.lost ~= true, "the body's own death check never runs on the token in a network game")
end
-- ------------------------------------------------------------------ nothing within 460 m, saves, the cap
-- Every approach the waves can use is "at" one spot where a hidden human stands.
local APPROACHES = { "spawn_wave1_scout2", "spawn_wave1_tank1", "spawn_wave2_scout1", "spawn_wave2_scout2", "spawn_wave2_scout3",
    "spawn_wave2_scout4", "spawn_bomber_1", "spawn_scout1_harrass", "spawn_ltnk1_harrass", "fighter_1" }
local function watchEverything(w, p)
    F.place(p[2].player, 4000, 98000)
    local saved = {}
    for _, name in ipairs(APPROACHES) do
        saved[name] = w.pathPos[name]
        w.pathPos[name] = { x = 4000, y = saved[name].y, z = 98000 }
    end
    return function()
        for _, name in ipairs(APPROACHES) do w.pathPos[name] = saved[name] end
        F.place(p[2].player, 20000, 20000)
    end
end
do
    local w, p, m = setup(4, {})
    w.cameraDone["camera_decloak"] = true
    local release = watchEverything(w, p)
    toState(m, MS.PLAYDECLOCK, 60); F.run(1)
    check(#F.builds(p[1], 0, "cvtnk") == 0 and #builtAt(p[1], "spawn_wave1_scout2") == 0, "a fully watched map defers the wave")
    check(type(m.wave1_scout2) == "number" and m.wave1_scout2 < 0 and m.crcca.serial >= 3, "the body holds tickets while the wave waits")
    check(type(m.wave1_scout1) == "string", "the camera scout is a real unit")
    local pending = m.crcca.serial
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(m.crcca.serial == pending and #builtAt(p[1], "spawn_wave1_scout2") == 0, "save/load keeps the pending wave without duplicating it")
    release(); F.run(5)
    check(#builtAt(p[1], "spawn_wave1_scout2", "cvfigh") == 1 + 2 and #builtAt(p[1], "spawn_wave1_tank1", "cvtnk") == 1, "the whole wave is built exactly once when the watcher leaves")
    check(type(m.wave1_scout2) == "string" and type(m.wave1_tank1) == "string", "tickets resolve to real units")
end
do -- orders aimed at the player wait with a ticket
    local w, p, m = toRetreat(2)
    -- (the harassers are already real here) a new watched ambush: the six fighters are tickets with a remembered order
    local release = watchEverything(w, p)
    local priorAttacks = F.count(p[1], "Attack") -- TRO 1.3 wave 2 already attacked the recycler
    F.nearTo("recycler", "trigger_1", 40, 0); F.run(2)
    check(#builtAt(p[1], "fighter_1") == 0 and F.count(p[1], "Attack") == priorAttacks, "watched ambush waits as tickets, no order for a ticket")
    release(); F.run(3)
    local attackers = 0
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do if isHuman(p, c[3]) then attackers = attackers + 1 end end
    check(#builtAt(p[1], "fighter_1") + #F.builds(p[1], 0, "cvfigh") >= 6 and attackers == 6 + 1, "the remembered order is issued to the nearest human when the ticket is built: " .. attackers)
end
do -- the body removing a harassment unit that is still a ticket cancels it
    local w, p, m = setup(2, {})
    w.cameraDone["camera_decloak"] = true
    toState(m, MS.WAVE1DEAD, 80); F.run(1); killAll(m, WAVE1)
    toState(m, MS.WAVE2DEAD, 60); F.run(1); killAll(m, WAVE2)
    w.audioBusy = true
    toState(m, MS.WAITFORSOUND4, 40); F.run(1)
    local release = watchEverything(w, p)
    w.audioBusy = false
    toState(m, MS.HARRASDEAD, 40); F.run(1)
    check(type(m.harrass_scout1) == "number" and m.harrass_scout1 < 0 and type(m.harrass_ltnk1) == "number", "the harassers wait as tickets while the approaches are watched")
    check(F.count(p[1], "Goto", m.harrass_scout1) == 0, "no order was sent for a ticket")
    w.objects.recycler.command = 0
    toState(m, MS.BOMBERRUN, 40); F.run(2)
    local removals = F.count(p[1], "RemoveObject")
    release(); F.run(5)
    check(#builtAt(p[1], "spawn_scout1_harrass") == 0 and #builtAt(p[1], "spawn_ltnk1_harrass") == 0, "the cancelled harassers are never built")
    check(F.count(p[1], "RemoveObject") == removals, "a ticket is cancelled, never sent as a handle to RemoveObject")
end
do -- live cap: extras are the only requests dropped
    local w, p, m = setup(4, {})
    m.crcca.live = {}
    for i = 1, 12 do m.crcca.live[i] = F.spawn("cvfigh", 5, 9000 + i, 9000) end
    toState(m, MS.PLAYDECLOCK, 60); F.run(1)
    check(#builtAt(p[1], "spawn_wave1_scout2", "cvfigh") == 1 and #builtAt(p[1], "spawn_wave1_tank1") == 1, "at the live cap the wave keeps its primaries and drops the extras")
end

-- ------------------------------------------------------------------ saves during films
do -- a load inside the decloak film reopens the camera and the film still ends
    local w, p, m = setup(3, {})
    toState(m, MS.PLAYDECLOCK, 60); F.run(1)
    local opened = F.count(p[1], "CameraReady")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(m.missionState == MS.PLAYDECLOCK, "still in the film after the load")
    check(F.count(p[1], "CameraReady") == opened + 1, "the host reopens its camera after a load")
    w.cameraDone["camera_decloak"] = true; F.run(3)
    check(m.missionState >= MS.WAITINGOBJ2, "the film ends after the load (state " .. m.missionState .. ")")
    for i = 1, 3 do check(p[i].camera == 0, "cameras balanced after a load on peer " .. i) end
end
do -- a load between films does not open a camera
    local w, p, m = setup(2, {})
    F.run(5)
    local before = F.count(p[1], "CameraReady")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "CameraReady") == before, "no camera is opened for a state that holds none")
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
    check(F.count(p[1], "EnvironmentInit") == 0 and m.missionState >= MS.FIRSTWAVE, "no weather module: the mission runs and touches no Environment")
    local printed = false
    for _, c in ipairs(p[1].calls) do if c[1] == "print" and tostring(c[2]):find("weather disabled", 1, true) then printed = true end end
    check(printed, "missing weather is logged, not fatal")
end
local function ganymede(record, mode)
    return function(peer)
        local V = { Seed = 4242, Initialized = false }
        local vents = { { label = "eggeizr10_geyser" }, { label = "eggeizr11_geyser" } }
        function V.Init(o) peer.weatherInit = o; V.Initialized = true; record("EuropaInit", o.authority, o.send ~= nil, o.seed); if mode == "initfail" then error("boom") end end
        function V.Update(dt)
            if peer.weatherInit and peer.weatherInit.authority and peer.weatherInit.send and not V.sent then
                V.sent = true; peer.weatherInit.send("EuropaQuake", 1, 0.3, 3, 1)
            end
            if mode == "updatefail" then error("update boom") end
        end
        function V.AnnounceState() record("EuropaAnnounce") end
        function V.ApplyNetEvent(op, ...) record("EuropaEvent", op, ...) end
        function V.SetTargetLevel(n) record("EuropaLevel", n) end
        function V.GetVentSites() return vents end
        function V.TriggerPlume(index) record("EuropaPlume", index) end
        function V.Quake(strength, duration) record("EuropaQuakeCall", strength, duration) end
        function V.Surge(duration, strength) record("EuropaSurgeCall", duration, strength) end
        function V.OnObjectCreated(h) record("EuropaCreated", h) end
        function V.Save() return { saved = true } end
        function V.Load(s) record("EuropaLoad", s and s.saved) end
        function V.Shutdown() record("EuropaShutdown") end
        return V
    end
end
do
    -- the real generated sites: two geyser vents
    local sites = dofile("Scripts/CRGanymedeSitesBD02.lua")
    check(sites.mission == "bdmisn02" and #sites.vents == 2 and sites.vents[1].label == "eggeizr10_geyser" and sites.vents[2].label == "eggeizr11_geyser",
        "the generated sites for this map carry the two geysers")
    local weather = { module = function(peer, record) return ganymede(record)(peer) end, sites = sites }
    local w, p, m = setup(3, { weather = weather })
    check(F.count(p[1], "EuropaInit", true) == 1 and F.last(p[1], "EuropaInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.count(p[2], "EuropaInit", false) == 1, "guests render only (not the authority)")
    check(F.count(p[1], "EuropaAnnounce") == 1 and F.count(p[2], "EuropaAnnounce") == 0, "the leader announces its weather state once")
    check(F.count(p[1], "EnvironmentInit") == 1 and F.last(p[1], "EnvironmentInit")[2].lightingMode == "orbit", "Jovian orbit lighting is initialised")
    check(F.count(p[1], "WeatherSensors", "Ganymede") == 1 and F.count(p[2], "WeatherSensors", "Ganymede") == 1, "the sensor modifier is bound once on every peer")
    for i = 2, 3 do
        local e = F.last(p[i], "EuropaEvent")
        check(e and e[2] == "EuropaQuake" and e[3] == 1, "weather events reach guest " .. i)
    end
    check(p[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    check(F.count(p[1], "EuropaLevel", 2) == 0, "calm until the first wave")
    w.cameraDone["camera_decloak"] = true
    toState(m, MS.PLAYDECLOCK, 60); F.run(1)
    check(F.count(p[1], "EuropaLevel", 2) == 1, "the first wave stirs the moon")
    toState(m, MS.WAVE1DEAD, 60); F.run(1); killAll(m, WAVE1)
    toState(m, MS.WAVE2DEAD, 60); F.run(1); killAll(m, WAVE2)
    toState(m, MS.WAITFORSOUND4, 40); F.run(1)
    check(F.count(p[1], "EuropaLevel", 3) == 1 and F.count(p[1], "EuropaQuakeCall") == 1 and F.count(p[1], "EuropaSurgeCall") == 1,
        "the massive attack raises the level with a quake and a surge")
    toState(m, MS.HARRASDEAD, 40); F.run(1)
    check(F.count(p[1], "EuropaLevel", 4) == 1 and F.count(p[1], "EuropaPlume", 2) == 1, "the retreat brings level 4 and a plume at the abandoned base (vent eggeizr11)")
    F.nearTo("recycler", "trigger_1", 40, 0); F.run(1)
    w.objects.recycler.command = 0
    toState(m, MS.BOMBERRUN, 30); F.run(1)
    check(F.count(p[1], "EuropaPlume", 1) == 1, "the bomber run opens the other vent")
    F.nearTo(m.bomber1_scripted, "camera_bomber_chasecam", 10, 0)
    toState(m, MS.RECYCLERDIE, 10); F.run(1)
    w.objects.recycler.health = 0.5; F.run(1); F.kill("recycler")
    toState(m, MS.ENDWAIT, 20); F.run(1)
    check(F.count(p[1], "EuropaQuakeCall") == 2, "the recycler's end shakes the ice")
    toState(m, MS.END, 20); F.run(2)
    check(F.count(p[1], "EuropaLevel", 2) == 2, "the debrief eases the sky")
    check(F.count(p[1], "EuropaCreated") > 0, "new objects are offered to the weather")
    check(F.count(p[2], "EuropaQuakeCall") == 0 and F.count(p[2], "EuropaPlume") == 0, "guests never decide weather events")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "EuropaShutdown") >= 1 and F.count(p[1], "EuropaLoad", true) == 1, "load restores the leader's weather state")
end
do -- sites module missing: no weather, never an error
    local w, p, m = setup(2, { weather = { module = function(peer, record) return ganymede(record)(peer) end } })
    check(F.count(p[1], "EuropaInit") == 0 and m.missionState >= MS.FIRSTWAVE, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local w, p, m = setup(2, { weather = { module = function(peer, record) return ganymede(record, mode)(peer) end, sites = dofile("Scripts/CRGanymedeSitesBD02.lua") } })
    playthrough(w, m); F.run(8)
    check(F.count(p[1], "SucceedMission") == 1 and F.count(p[2], "SucceedMission") == 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("bdmisn02 co-op: " .. checks .. " checks passed")
