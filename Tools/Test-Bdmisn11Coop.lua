-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/bd11cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/Test-Bdmisn11Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Bdmisn11Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local function extrasFor(n) return math.min(math.floor(n / 2), 2) end

local function setup(n, options)
    options = options or {}
    local w = F.reset()
    w.audioBusy = options.busy == true
    w.honestTimer = options.honestTimer == true
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
local function builtAt(peer, where, odf)
    local out = {}
    for _, b in ipairs(F.builds(peer, 0, odf)) do
        if b.where == where then out[#out + 1] = b end
    end
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
        for _, name in ipairs({"BuildObject", "SetScrap", "SetCloaked", "Goto", "Attack", "Defend2", "Retreat"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on the authored enemy team 2") end
end
local function reap()
    for h, o in pairs(F.world().objects) do
        if o.alive and h:match("^built") and o.odf:sub(1, 1) == "c" then o.alive = false end
    end
end
local function finishIntro(w) w.cameraDone["camera_start"] = true; F.run(1) end
local function pilotOf(w)
    for h, o in pairs(w.objects) do if o.odf == "aspilo" and o.alive then return h end end
end
-- The APC reaches the Recycler, the pilot walks in, the Recycler drives to the geyser and the waves are armed.
local function crew(w)
    finishIntro(w)
    -- 40 m: the APC stops anywhere inside 50 m and the pilot transfers inside 25 m, so he has a walk.
    F.nearTo("apc", "recycler", 40, 0)
    F.run(1)
    F.nearTo(assert(pilotOf(w), "the transfer pilot is built"), "recycler", 5, 0)
    F.run(3)
end
local function arrive(w)
    F.place("recycler", 370, 101313)
    F.run(1)
    local t0 = w.now
    F.place("recycler", 416.667, 101510)
    F.run(1)
    return t0
end

-- ------------------------------------------------------------------ offline == faithful
local function summary(peer)
    local out, lines, blasts = {}, {}, {}
    for _, c in ipairs(peer.calls) do
        if c[1] == "BuildObject" and c[5] ~= "nav_end" then
            out[#out + 1] = "B:" .. c[3] .. ":" .. (c[4] == 2 and 5 or c[4]) .. ":" .. tostring(c[5])
        elseif c[1] == "SucceedMission" or c[1] == "FailMission" then
            out[#out + 1] = c[1] .. ":" .. tostring(c[3])
        elseif c[1] == "SetCloaked" then
            out[#out + 1] = "C"
        elseif c[1] == "MakeExplosion" then
            blasts[#blasts + 1] = c[2]
        elseif c[1] == "ColorFade" then
            blasts[#blasts + 1] = "flash"
        elseif c[1] == "AudioMessage" or c[1] == "Play" then
            lines[#lines + 1] = c[2]
        end
    end
    -- (the blasts are timed by the countdown, the builds by the waves: compared as separate sequences)
    return table.concat(out, ",") .. "|" .. table.concat(lines, ",") .. "|" .. table.concat(blasts, ",")
end
local function fullRun(options)
    options.honestTimer = true
    local w = F.reset()
    w.honestTimer = true
    local peer = F.makePeer(1, 1, false, options)
    F.connect(); F.run(1)
    -- the human is away from every staging point, so no entry is watched and the offline run equals the faithful one
    F.place(peer.player, 2500, 99000)
    crew(w)
    arrive(w)
    F.runUntil(function() return w.now > 200 end, 400)
    peer.env.Save().goToPortalTime = w.now -- the 26 minutes of attacks are tested on their own
    F.runUntil(function() return F.count(peer, "SucceedMission") > 0 end, 2000)
    F.run(3)
    return summary(peer), peer
end
do
    local faithful = fullRun({ faithful = true, script = "Scripts/bdmisn11.lua" })
    faithful = faithful:gsub("apcamr", "bpcamr") -- intentional CR rename: the nav beacon matches the player faction
    local offline, peer = fullRun({})
    check(faithful == offline and faithful:find("SucceedMission:bd11win.des", 1, true),
        "offline plays like the faithful port:\n" .. faithful .. "\n" .. offline)
    check(F.count(peer, "SucceedMission") == 1 and F.count(peer, "FailMission") == 0, "one victory, no failure")
    noEnemyTeamTwo(peer)
    check(F.count(peer, "SetAIControl", 5) == 1 and F.count(peer, "SetAIControl", 2) == 0, "AI control only for enemy team 5")
    check(F.index(peer, "SetAIControl") <= peer.chunkCalls, "SetAIControl runs at chunk root, before Start")
end

-- ------------------------------------------------------------------ teams, scrap, pilots, the opening film
do
    local w, p, m = setup(4, {})
    check(m.startDone and m.coopMissionStarted, "the leader starts the shared mission")
    check(F.last(p[1], "SetScrap")[3] == 100 + 10 * 3, "starting scrap: 100 plus 10 per guest")
    for team = 1, 4 do check(F.count(p[1], "SetPilot", team) == 1 and F.callsOf(p[1], "SetPilot")[1][3] == 10, "10 pilots for human team " .. team) end
    for i = 1, 4 do
        check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
        check(F.heardCount(p[i], "bd11001.wav") == 1, "briefing once on peer " .. i)
        check(p[i].camera == 1, "the opening film is shared: peer " .. i)
        check(F.last(p[i], "CameraPath")[2] == "camera_start" and F.last(p[i], "CameraPath")[5] == "recycler", "opening shot on peer " .. i)
        check(F.count(p[i], "AddObjective", "bd11001.otf") >= 1, "objective on peer " .. i)
    end
    check(F.count(p[1], "BuildObject", nil) >= 1 and #builtAt(p[1], "recy_nav") == 1, "the Recycler nav beacon is built once")
    check(F.count(p[2], "SetObjectiveName", "Recycler") == 0 and F.count(p[1], "SetObjectiveName") >= 1, "the nav is named on the host and streamed")
    check(not m.cameraComplete[0], "the opening runs until its shot arrives")
    finishIntro(w)
    check(m.cameraComplete[0], "the opening ends when the path is done")
    for i = 1, 4 do check(p[i].camera == 0, "opening cameras balanced on peer " .. i) end
    guestsPassive(p)
end
do -- a host skip releases only the host's camera and the runtime stops driving the shot: the opening ends for all
    local w, p, m = setup(3, {})
    w.cancel = true; F.run(2)
    w.cancel = false; F.run(1)
    check(m.cameraComplete[0], "a host skip ends the shared opening instead of stalling it")
    for i = 1, 3 do check(p[i].camera == 0, "no peer is left in the film after a host skip: " .. i) end
end
do -- offline: skippable
    local w, p, m = setup(1, {})
    check(p[1].camera == 1, "offline opening opens")
    w.cancel = true; F.run(1)
    check(m.cameraComplete[0] and p[1].camera == 0, "offline skip ends the opening")
    w.cancel = false; F.run(40)
    check(F.count(p[1], "CameraReady") == 1, "a skipped opening never restarts")
end

-- ------------------------------------------------------------------ pilot transfer, losses, the Recycler's trip
do
    local w, p, m = setup(2, {})
    finishIntro(w)
    F.nearTo("apc", "recycler", 40, 0)
    F.nearTo("enemy_1", "apc", 100, 0) -- an enemy inside 200 m holds the transfer
    F.run(2)
    check(not m.pilotTransferring and pilotOf(w) == nil, "no transfer with an enemy within 200 m")
    F.kill("enemy_1"); F.run(2)
    local pilot = pilotOf(w)
    check(m.pilotTransferring and pilot ~= nil and F.count(p[1], "Stop", "apc") == 1, "the APC stops and the pilot gets out")
    F.nearTo(pilot, "recycler", 5, 0)
    F.run(1)
    check(m.objective1Complete and F.count(p[1], "SetPilotClass", "recycler") == 1, "the pilot boards")
    heardAll(p, "bd11002.wav")
    F.run(3)
    local order = F.last(p[1], "Goto")
    check(order[2] == "recycler" and order[3] == "recycler_path" and F.team("recycler") == 1, "the Recycler sets off along its path")
    check(F.count(p[1], "AddObjective", "bd11001.otf") >= 1, "objective 1 still shown")
    F.place("recycler", 416.667, 101510)
    F.run(1)
    check(F.count(p[2], "AddObjective", "bd11002.otf") == 1 and F.count(p[2], "AddObjective", "bd11001.otf") >= 2, "at the geyser: objective 1 green, objective 2 white (guests too)")
    guestsPassive(p)
end
do -- losses: one shared failure per cause, with the right debrief
    local function lose(setupFn, file)
        local w, p, m = setup(2, {})
        finishIntro(w)
        setupFn(w, p, m)
        F.run(3)
        check(F.count(p[1], "FailMission") == 1 and F.last(p[1], "FailMission")[3] == file, "loss debrief " .. file)
        check(F.count(p[2], "FailMission") == 1, "the guest shares the failure")
    end
    lose(function() F.kill("apc") end, "bd11lsea.des")
    lose(function(w, p, m) F.kill("recycler") end, "bd11lsed.des")
    lose(function(w) F.nearTo("apc", "recycler", 40, 0); F.run(2); F.kill(pilotOf(w)) end, "bd11lsec.des")
end

-- ------------------------------------------------------------------ the waves: scaling, cloak, orders, no pop-in
local ATTACKS = { 2, 2, 4, 3, 3, 9 }
local DEFENDS = { 4, 5, 5, 7, 9, 12 }
local WAVE_AT = { 120, 300, 540, 840, 1080, 1260 }
for humans = 1, 4 do
    local w, p, m = setup(humans, {})
    crew(w)
    local t0 = arrive(w)
    local e = extrasFor(humans)
    -- (units are beaten as they come, so the live cap never bites)
    while w.now < t0 + 1300 do F.run(1); reap() end
    local function expect(where, n)
        local count = 0
        for _, b in ipairs(builtAt(p[1], where)) do if b.odf ~= "cssold" then count = count + 1 end end
        check(count == n + e, humans .. " human(s): " .. where .. " is " .. n .. " + " .. e .. ", got " .. count)
    end
    local scaled = 0
    for _, b in ipairs(F.builds(p[1])) do if b.odf:sub(1, 2) == "cv" or b.odf == "cssold" then scaled = scaled + 1 end end
    check(scaled == 90 + 16 * e, humans .. " human(s): 90 primaries plus 16 events x " .. e .. " extras, got " .. scaled)
    expect("drive_2", 5); expect("drive_1", 4)
    for k = 1, 6 do expect("attack_" .. k, ATTACKS[k]); expect("defend_" .. k, DEFENDS[k]) end
    -- the aerial drop sits 100 m from the humans' start: both drops come from another hidden approach
    check(#builtAt(p[1], "aerial_1") == 0, "the watched aerial point builds nothing")
    check(#F.builds(p[1], 0, "cssold") == 16 + 2 * e, humans .. " human(s): two aerial drops of 8 + extras")
    allSafe(p, F.builds(p[1]))
    for _, b in ipairs(F.builds(p[1])) do
        if b.odf:sub(1, 2) == "cv" or b.odf == "cssold" then
            check(b.team == 5, "Chinese craft are on team 5")
            if b.odf ~= "cssold" and (b.where:match("^attack_") or b.where:match("^defend_")) then
                check(w.objects[b.h].cloaked, "every wave unit is cloaked (extras too)")
            end
        end
    end
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end
do -- orders: attackers go for the Recycler, defenders guard an attacker of their wave
    local w, p, m = setup(1, {})
    crew(w)
    local t0 = arrive(w)
    F.runUntil(function() return w.now > t0 + 125 end, 400)
    local attackers = builtAt(p[1], "attack_1")
    local defenders = builtAt(p[1], "defend_1")
    check(#attackers == 2 and #defenders == 4, "wave 1 is 2 attackers and 4 defenders")
    local function isIn(list, h) for _, b in ipairs(list) do if b.h == h then return true end end end
    local attackOrders, guardOrders = 0, 0
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do if isIn(attackers, c[2]) and c[3] == "recycler" then attackOrders = attackOrders + 1 end end
    for _, c in ipairs(F.callsOf(p[1], "Defend2")) do
        if isIn(defenders, c[2]) and isIn(attackers, c[3]) and c[4] == 1 then guardOrders = guardOrders + 1 end
    end
    check(attackOrders == 2 and guardOrders == 4, "orders reach the real units: " .. attackOrders .. "/" .. guardOrders)
    local drive = builtAt(p[1], "drive_2")
    check(#drive == 5 and not w.objects[drive[1].h].cloaked, "the drive-in raiders are not cloaked")
end
do -- concealment: wave 1 is staged at two points the humans stand next to, so it comes from a hidden approach
    local w, p, m = setup(2, {})
    crew(w)
    local t0 = arrive(w)
    F.run(30) -- the drive-in raiders are out of the way
    F.place(p[1].player, 303, 100623)
    F.place(p[2].player, 310, 100650)
    local mark = #p[1].calls
    F.runUntil(function() return w.now > t0 + 125 end, 400)
    local wave = {}
    for _, b in ipairs(F.builds(p[1], mark)) do
        check(b.where ~= "attack_1" and b.where ~= "defend_1" and b.where ~= "attack_5", "nothing is built at a watched approach: " .. b.where)
        wave[#wave + 1] = b
    end
    check(#wave == 2 + 4 + 2, "the whole wave (2 attackers, 4 defenders, +1 extra each) arrives from the hidden fallback: " .. #wave)
    for _, b in ipairs(wave) do check(b.where == "drive_1", "the first hidden approach in line is used") end
    allSafe(p, wave)
end

-- ------------------------------------------------------------------ the portal run: timer, destruction, victory
local function finale(options)
    local w, p, m = setup(options.humans or 3, options)
    crew(w)
    arrive(w)
    return w, p, m
end
do
    local w, p, m = finale({ humans = 3 })
    m.goToPortalTime = w.now + 1
    F.run(3)
    check(m.objective2Complete and F.count(p[1], "AddObjective", "bd11002.otf") >= 1, "the evacuation order turns objective 2 green")
    local nav = builtAt(p[1], "nav_end", "bpcamr")
    check(#nav == 1 and F.count(p[1], "SetObjectiveName", nav[1].h) == 1, "restored: the Portal nav beacon appears at nav_end, named once")
    check(F.count(p[1], "BuildObject") > 0 and #builtAt(p[1], "nav_end") == 1, "...and only once")
    heardAll(p, "bd11007.wav")
    F.runUntil(function() return m.cockpitTimerActive end, 200)
    F.run(3)
    for i, q in ipairs(p) do
        check(F.count(q, "StartCockpitTimer") == 1 and F.last(q, "StartCockpitTimer")[2] == 90, "the countdown is shown on peer " .. i)
        check(F.count(q, "AddObjective", "bd11003.otf") >= 1, "objective 3 on peer " .. i)
        check(F.count(q, "SetObjectiveOn") >= 1, "the portal is marked on peer " .. i)
    end
    heardAll(p, "bd11008.wav"); heardAll(p, "bd11009.wav"); heardAll(p, "bd11010.wav"); heardAll(p, "bd11012.wav")
    -- the engine's own clock counts UP on this map; the host counts the 90 s itself
    F.runUntil(function() return m.navDistanceOk end, 120)
    check(w.now - w.timer.start <= 91, "the countdown ran out after ~90 s although the engine clock never reaches zero")
    F.run(1)
    for i, q in ipairs(p) do
        check(F.count(q, "AddObjective", "bd11004.otf") == 1, "restored: the detonation warning objective on peer " .. i)
        check(F.count(q, "HideCockpitTimer") >= 1, "the countdown is hidden on peer " .. i)
    end
    F.runUntil(function() return m.explodePortal end, 40)
    F.run(2)
    for i, q in ipairs(p) do
        check(F.count(q, "MakeExplosion", "xpltrsk") == 4 and F.count(q, "MakeExplosion", "xpltrso") == 1, "the five blasts show on peer " .. i)
        check(F.count(q, "ColorFade") == 1, "the white flash shows once on peer " .. i)
    end
    check(F.last(p[1], "MakeExplosion")[3] == "portal" and F.last(p[2], "MakeExplosion")[3] == "portal", "the guests blast the portal object")
    check(F.count(p[2], "CameraPath", "camera_destruct") >= 1, "the destruction shot is shared")
    F.runUntil(function() return F.count(p[1], "SucceedMission") > 0 end, 60)
    heardAll(p, "bd11011.wav")
    check(F.count(p[1], "SucceedMission") == 1 and F.last(p[1], "SucceedMission")[3] == "bd11win.des" and F.count(p[1], "FailMission") == 0, "one victory")
    F.run(3)
    for i, q in ipairs(p) do check(q.camera == 0, "cameras balanced after the finale on peer " .. i) end
    guestsPassive(p)
end
do -- the blast is the end: a failure raised after it (here the body's own Recycler-loss test) is ignored
    local w, p, m = finale({ humans = 2 })
    m.goToPortalTime = w.now + 1
    F.runUntil(function() return m.explodePortal end, 200)
    F.kill("recycler"); F.run(2)
    check(F.count(p[1], "FailMission") == 0 and F.count(p[2], "FailMission") == 0, "a failure after the blast is ignored")
    F.runUntil(function() return F.count(p[1], "SucceedMission") > 0 end, 60)
    check(m.lost and m.won and F.count(p[1], "SucceedMission") == 1 and F.last(p[1], "SucceedMission")[3] == "bd11win.des",
        "stock fix: the win still comes after the Recycler is lost post-blast (no hang)")
end
do -- a failed AudioMessage (no handle) never stalls the radio chain
    local w, p, m = finale({ humans = 2, noAudio = true })
    m.goToPortalTime = w.now + 1
    F.runUntil(function() return F.count(p[1], "SucceedMission") > 0 end, 400)
    check(F.count(p[1], "SucceedMission") == 1, "the mission still ends without audio handles")
end

-- ------------------------------------------------------------------ restored voice line bd11003
do
    local w, p, m = finale({ humans = 2 })
    F.run(2)
    check(F.heardCount(p[1], "bd11003.wav") == 0, "no distress call at full health")
    w.objects.recycler.health = 0.7
    F.run(2)
    heardAll(p, "bd11003.wav")
    F.run(5)
    check(F.heardCount(p[1], "bd11003.wav") == 1, "once")
    w.objects.recycler.health = 0.45
    F.run(2)
    heardAll(p, "bd11004.wav")
    check(F.heardCount(p[1], "bd11003.wav") == 1, "the calls then follow the body's own order")
end
do -- a Recycler that goes straight to a worse call never plays the mild one
    local w, p, m = finale({ humans = 1 })
    w.objects.recycler.health = 0.4
    F.run(2)
    check(F.heardCount(p[1], "bd11004.wav") == 1 and F.heardCount(p[1], "bd11003.wav") == 0, "bd11003 is never played after bd11004")
end

-- ------------------------------------------------------------------ loads: the presentation comes back
do
    local w, p, m = setup(3, {})
    -- a load during the opening film opens the camera again, once, and the film still ends
    local before = F.count(p[1], "CameraReady")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "CameraReady") == before + 1 and p[1].camera == 1, "the opening camera opens again after a load")
    finishIntro(w)
    for i = 1, 3 do check(p[i].camera == 0, "the film still ends on peer " .. i) end
    crew(w); arrive(w)
    local mark2 = #p[2].calls
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    local green, white = false, false
    for i = mark2 + 1, #p[2].calls do
        local c = p[2].calls[i]
        if c[1] == "AddObjective" and c[2] == "bd11001.otf" and c[3] == "green" then green = true end
        if c[1] == "AddObjective" and c[2] == "bd11002.otf" and c[3] == "white" then white = true end
    end
    check(green and white, "the objective list is published again after a load")
    -- the portal countdown, its marker and the shot come back too
    m.goToPortalTime = w.now + 1
    F.runUntil(function() return m.cockpitTimerActive end, 200)
    F.run(30)
    local mark = #p[2].calls
    local on = F.count(p[2], "SetObjectiveOn")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    local timerShown, shownLeft = false, nil
    for i = mark + 1, #p[2].calls do
        local c = p[2].calls[i]
        if c[1] == "StartCockpitTimer" then timerShown, shownLeft = true, c[2] end
    end
    check(timerShown and shownLeft > 40 and shownLeft < 70, "the countdown is shown again with the time that is left: " .. tostring(shownLeft))
    check(F.count(p[2], "SetObjectiveOn") == on + 1, "the portal marker is shown again")
    local list = {}
    for i = mark + 1, #p[2].calls do
        local c = p[2].calls[i]
        if c[1] == "AddObjective" then list[#list + 1] = c[2] end
    end
    check(#list == 1 and list[1] == "bd11003.otf", "the portal objective is published again")
    F.runUntil(function() return m.explodePortal end, 120)
    F.run(1)
    local destruct = F.count(p[2], "CameraPath", "camera_destruct")
    mark = #p[2].calls
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(1)
    check(F.count(p[2], "CameraPath", "camera_destruct") > destruct and p[2].camera == 1, "a load during the destruction shot opens it again")
    F.runUntil(function() return F.count(p[1], "SucceedMission") > 0 end, 60)
    F.run(3)
    for i = 1, 3 do check(p[i].camera == 0, "cameras balanced at the end on peer " .. i) end
end

-- ------------------------------------------------------------------ leader leaves
do
    local w, p, m = setup(3, {})
    finishIntro(w)
    p[2].env.DeletePlayer(1)
    F.run(3)
    check(F.count(p[2], "FailMission") + F.count(p[3], "FailMission") >= 1, "a departed leader fails the guests")
end

-- ------------------------------------------------------------------ weather: absent, present, broken
local function elysium(record, mode, sites)
    return function(peer)
        local V = { Seed = 4242, Initialized = false }
        function V.Init(o)
            peer.weatherInit = o; V.Initialized = true
            record("ElysiumInit", o.authority, o.send ~= nil, o.seed, o.startLevel, o.targetLevel)
            if mode == "initfail" then error("boom") end
        end
        function V.Update()
            if peer.weatherInit and peer.weatherInit.authority and peer.weatherInit.send and not V.sent then
                V.sent = true; peer.weatherInit.send("VenusStrike", 1, 2, 3)
            end
            if mode == "updatefail" then error("update boom") end
        end
        function V.AnnounceState() record("ElysiumAnnounce") end
        function V.ApplyNetEvent(op, ...) record("ElysiumEvent", op, ...) end
        function V.SetTargetLevel(n) record("ElysiumLevel", n) end
        function V.TriggerStrike(pos) record("ElysiumStrike", pos.x, pos.z) end
        function V.OnObjectCreated(h) record("ElysiumCreated", h) end
        function V.Save() return { saved = true } end
        function V.Load(s) record("ElysiumLoad", s and s.saved) end
        function V.Shutdown() record("ElysiumShutdown") end
        return V
    end
end
do
    local w, p, m = setup(3, {})
    check(F.count(p[1], "EnvironmentInit") == 0 and m.startDone, "no weather module: the mission runs and touches no Environment")
    local printed = false
    for _, c in ipairs(p[1].calls) do if c[1] == "print" and tostring(c[2]):find("weather disabled", 1, true) then printed = true end end
    check(printed, "missing weather is logged, not fatal")
end
do
    local sites = dofile("Scripts/CRElysiumSitesBD11.lua")
    check(sites.mission == "bdmisn11" and #sites.vents == 4 and sites.bounds.minX == 90, "the generated sites are bd11's")
    local weather = { module = function(peer, record) return elysium(record, nil, sites)(peer) end, sites = sites }
    local w, p, m = setup(2, { weather = weather })
    check(F.count(p[1], "ElysiumInit", true) == 1 and F.last(p[1], "ElysiumInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.last(p[1], "ElysiumInit")[5] == 1 and F.last(p[1], "ElysiumInit")[6] == 1, "the sky starts calm and stays calm")
    check(F.count(p[2], "ElysiumInit", false) == 1, "guests render only")
    check(F.count(p[1], "ElysiumAnnounce") == 1 and F.count(p[2], "ElysiumAnnounce") == 0, "the leader announces its weather state once")
    local e = F.last(p[2], "ElysiumEvent")
    check(e and e[2] == "VenusStrike", "weather events reach the guest")
    check(p[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    local function level(n) return F.count(p[1], "ElysiumLevel", n) end
    F.run(5)
    check(level(2) == 0 and level(3) == 0, "calm until the Recycler is crewed")
    crew(w)
    check(level(2) == 1, "the crewed Recycler stirs the sky (level 2)")
    local t0 = arrive(w)
    check(level(3) == 1 and F.count(p[1], "ElysiumStrike") == 0, "the first raiders close the cloud deck (level 3)")
    F.runUntil(function() return w.now > t0 + 125 end, 400)
    check(level(4) == 0, "no storm before the third wave")
    F.runUntil(function() return w.now > t0 + 545 end, 600)
    check(level(4) == 1 and F.count(p[1], "ElysiumStrike") == 1, "the third wave breaks the storm, the first aerial drop brings a strike")
    local rx, rz = F.last(p[1], "ElysiumStrike")[2], F.last(p[1], "ElysiumStrike")[3]
    check(math.abs(rx - 416.667) < 1 and math.abs(rz - 101510) < 1, "the strike is over the Recycler")
    F.runUntil(function() return w.now > t0 + 790 end, 600)
    check(F.count(p[1], "ElysiumStrike") == 2, "the second aerial drop")
    F.runUntil(function() return w.now > t0 + 1265 end, 1000)
    check(F.count(p[1], "ElysiumStrike") == 3, "the last wave")
    check(F.count(p[1], "ElysiumCreated") > 0, "new objects are offered to the weather")
    m.goToPortalTime = w.now + 1
    F.runUntil(function() return m.cockpitTimerActive end, 200)
    F.run(1)
    check(level(5) == 1, "the portal run is made at the worst level")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "ElysiumShutdown") >= 1 and F.count(p[1], "ElysiumLoad", true) == 1, "load restores the leader's weather state")
    check(level(5) == 1 and level(4) == 1, "no beat is replayed after a load")
    F.runUntil(function() return m.explodePortal end, 120)
    F.run(1)
    check(F.count(p[1], "ElysiumStrike") == 4, "lightning over the portal at the blast")
    F.runUntil(function() return m.won end, 60)
    F.run(2)
    check(level(2) == 2, "the victory eases the weather")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local sites = dofile("Scripts/CRElysiumSitesBD11.lua")
    local w, p, m = setup(2, { weather = { module = function(peer, record) return elysium(record, mode, sites)(peer) end, sites = sites } })
    crew(w); local t0 = arrive(w)
    F.runUntil(function() return w.now > t0 + 125 end, 400)
    check(#builtAt(p[1], "attack_1") == 2 + 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("bdmisn11 co-op: " .. checks .. " checks passed")
