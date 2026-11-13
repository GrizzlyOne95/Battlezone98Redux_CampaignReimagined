-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/bd06cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/CoopCampaignTests/Test-Bdmisn06Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/CoopCampaignTests/Bdmisn06Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local function extrasFor(n) return math.min(math.floor(n / 2), 2) end
-- mission states of the body (Scripts/bd06.lua)
local MS = { STARTCAMERA = 1, WAITING1 = 2, FAKEATTACKCAMERA = 5, WAITFORALL2BDESTDEAD = 6, WAITFORREDDEVIL = 7,
    WAITFORBADGUY = 8, WAITFORBADGUY1DIE = 9, WAITFORSOUND3 = 12, WAITFORRECYCLER = 14, WAITFORBADGUY3 = 15,
    WAITFORAPC = 16, ENDCUTSCENE = 17, WAITAPCOUT = 20 }
local BASE = { "2bdest_1", "2bdest_2", "2bdest_3", "2bdest_7", "2bdest_9", "2bdest_10" }

local function setup(n, options)
    options = options or {}
    local w = F.reset()
    w.audioBusy = options.busy == true
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
-- Chinese craft the script built at a path (the portal builds are "@portal").
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
        for _, name in ipairs({"BuildObject", "SetScrap", "Goto", "Attack", "Hunt", "Deploy", "PortalOut"}) do
            -- the portal pulse is presentation: guests apply it, they never decide it
            if name ~= "PortalOut" then check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name) end
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on the authored enemy team 2") end
end
local function reap()
    for h, o in pairs(F.world().objects) do
        if o.alive and h:match("^built") and o.odf:sub(1, 2) == "cv" then o.alive = false end
    end
end
local function intro(w) w.cameraDone["camera_start"] = true; F.run(1) end

-- Plays the mission as a player who beats everything: the base falls, every wave dies as it arrives, the recycler
-- and the APC reach their goals. stop() ends the drive; opts.keep leaves the Chinese units alone.
local function drive(w, p, stop, opts)
    opts = opts or {}
    local start, apcSpawned = w.now, false
    while not stop() do
        assert(w.now - start < 2400, "drive timed out in state " .. tostring(p[1].env.Save().missionState))
        F.run(1)
        local m = p[1].env.Save()
        if m.missionState == MS.WAITFORALL2BDESTDEAD and not opts.keepBase then for _, l in ipairs(BASE) do F.kill(l) end end
        if not opts.keep then reap() end
        for h, o in pairs(w.objects) do
            if o.alive and (o.odf == "bvrecy" or o.odf == "bvapc") and o.command == 3 then o.command = 0 end
        end
        if m.missionState == MS.WAITFORAPC and not apcSpawned and not opts.noApc then
            apcSpawned = true
            F.spawn("bvapc", 1, 940, 100712)
        end
    end
end

-- ------------------------------------------------------------------ offline == faithful
local function summary(peer)
    local out = {}
    for _, c in ipairs(peer.calls) do
        if c[1] == "BuildObject" then
            out[#out + 1] = "B:" .. c[3] .. ":" .. (c[4] == 2 and 5 or c[4]) .. ":" .. tostring(c[5])
        elseif c[1] == "SucceedMission" or c[1] == "FailMission" then
            out[#out + 1] = c[1] .. ":" .. tostring(c[3])
        elseif c[1] == "Deploy" or c[1] == "PortalOut" or c[1] == "ActivatePortal" or c[1] == "DeactivatePortal" then
            out[#out + 1] = c[1]
        end
    end
    table.sort(out)
    local lines = {}
    for _, c in ipairs(peer.calls) do
        if c[1] == "AudioMessage" or c[1] == "Play" or c[1] == "Queue" then lines[#lines + 1] = c[2] end
    end
    -- the restored closing narration is the only audio the CR layer adds
    local kept = {}
    for _, l in ipairs(lines) do if l ~= "bd06008.wav" and l ~= "bd06005.wav" then kept[#kept + 1] = l end end
    return table.concat(out, ",") .. "|" .. table.concat(kept, ",")
end
local function fullRun(options)
    local w = F.reset()
    local peer = F.makePeer(1, 1, false, options)
    F.connect(); F.run(1)
    -- the human is away from every staging point, so no entry is watched and the offline run equals the faithful one
    F.place(peer.player, 2500, 99000)
    for _, path in ipairs({ "camera_start", "camera_go", "camera_end_scene" }) do w.cameraDone[path] = true end
    local done = false
    drive(w, { peer }, function()
        for _, c in ipairs(peer.calls) do if c[1] == "SucceedMission" or c[1] == "FailMission" then done = true end end
        return done
    end)
    return summary(peer), peer
end
do
    local faithful = fullRun({ faithful = true, script = "Scripts/bd06.lua" })
    local offline, peer = fullRun({})
    check(faithful == offline and faithful:find("SucceedMission:bd06wina.des", 1, true),
        "offline completes like the faithful port:\n" .. faithful .. "\n" .. offline)
    check(F.count(peer, "SucceedMission") == 1 and F.count(peer, "FailMission") == 0, "one victory, no failure")
    noEnemyTeamTwo(peer)
    check(F.count(peer, "SetAIControl", 5) == 1 and F.count(peer, "SetAIControl", 2) == 0, "AI control only for enemy team 5")
    check(F.index(peer, "SetAIControl") <= peer.chunkCalls, "SetAIControl runs at chunk root, before Start")
end

-- ------------------------------------------------------------------ teams, scrap, pilots, the opening film, the timer
do
    local w, p, m = setup(4, {})
    check(F.count(p[1], "SetScrap", 1) == 1 and F.last(p[1], "SetScrap")[3] == 75 + 10 * 3, "starting scrap: 75 plus 10 per guest")
    for team = 1, 4 do check(F.count(p[1], "SetPilot", team) == 1 and F.callsOf(p[1], "SetPilot")[1][3] == 10, "10 pilots for human team " .. team) end
    for i = 1, 4 do
        check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
        check(p[i].camera == 1, "the opening film is shared: peer " .. i)
        check(F.last(p[i], "CameraPath")[2] == "camera_start" and F.last(p[i], "CameraPath")[5] == "portal", "opening shot on peer " .. i)
        check(F.count(p[i], "StartCockpitTimer") == 0, "no timer during the opening on peer " .. i)
    end
    F.run(3)
    heardAll(p, "bd06001.wav")
    check(m.missionState == MS.STARTCAMERA, "the opening runs until its shot arrives")
    intro(w)
    check(m.missionState == MS.WAITING1, "the opening ends when the shot is done")
    for i = 1, 4 do
        check(p[i].camera == 0, "opening cameras balanced on peer " .. i)
        check(F.count(p[i], "StartCockpitTimer") == 1 and math.abs(F.last(p[i], "StartCockpitTimer")[2] - 660) < 1,
            "the restored 11-minute cockpit timer runs on peer " .. i)
        local o = F.callsOf(p[i], "AddObjective")
        check(o[1] and o[1][2] == "bd06001.otf", "objective on peer " .. i)
    end
    guestsPassive(p)
end
do -- a host skip releases only the host's camera and the runtime stops driving the shot: the opening ends for all
    local w, p, m = setup(3, {})
    w.cancel = true; F.run(2)
    w.cancel = false; F.run(1)
    check(m.missionState == MS.WAITING1, "a host skip ends the shared opening instead of stalling it")
    for i = 1, 3 do check(p[i].camera == 0, "no peer is left in the film after a host skip: " .. i) end
end
do -- offline: skippable
    local w, p, m = setup(1, {})
    check(p[1].camera == 1, "offline opening opens")
    w.cancel = true; F.run(1)
    check(m.missionState == MS.WAITING1 and p[1].camera == 0, "offline skip ends the opening")
end

-- ------------------------------------------------------------------ the diversion, the base, the timer
do -- the 11 minutes run out: one shared failure, with a debrief the game ships
    local w, p, m = setup(3, {})
    intro(w)
    w.cameraDone["camera_go"] = true
    F.run(30)
    check(m.missionState == MS.WAITFORALL2BDESTDEAD, "the fake attack ends: now the base must fall")
    heardAll(p, "bd06002.wav")
    check(F.count(p[1], "RemoveObject", "silo_attack1") == 1, "the diversion fighters are removed (a guest drops removals of map objects it cannot resolve)")
    F.run(660)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd06lsea.des",
            "out of time: bd06lsea (the game ships no bd06lsed) on peer " .. i)
        check(F.count(p[i], "HideCockpitTimer") == 1, "the timer is hidden when the mission is lost on peer " .. i)
    end
    noEnemyTeamTwo(p[1])
end
do -- the base falls: timer hidden, no failure
    local w, p, m = setup(2, {})
    intro(w); w.cameraDone["camera_go"] = true; F.run(30)
    for _, l in ipairs(BASE) do F.kill(l) end
    F.run(2)
    check(m.missionState == MS.WAITFORREDDEVIL, "the base is destroyed")
    for i = 1, 2 do check(F.count(p[i], "HideCockpitTimer") == 1 and F.count(p[i], "FailMission") == 0, "timer hidden on peer " .. i) end
end
do -- attacking the diversion units too early (damage or loss): bd06007 then bd06lsea
    local w, p, m = setup(2, {})
    intro(w); F.run(5)
    F.world().objects["silo_attack2"].health = 0.5
    w.audioBusy = true; F.run(2)
    heardAll(p, "bd06007.wav")
    w.audioBusy = false; F.run(3)
    for i = 1, 2 do check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd06lsea.des", "too early: bd06lsea on peer " .. i) end
end
do -- the portal destroyed: bd06lseb once
    local w, p, m = setup(2, {})
    intro(w); F.run(5)
    F.kill("portal"); F.run(3)
    for i = 1, 2 do check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd06lseb.des", "portal lost: bd06lseb on peer " .. i) end
end

-- ------------------------------------------------------------------ waves: scaling, orders at the nearest human, no pop-in
local function toBaseDown(w)
    intro(w); w.cameraDone["camera_go"] = true; F.run(30)
    for _, l in ipairs(BASE) do F.kill(l) end
    F.run(1)
    return w.now
end
local function humanSet(p)
    local set = {}
    for _, q in ipairs(p) do set[q.player] = true end
    return set
end
for humans = 1, 4 do
    local w, p, m = setup(humans, {})
    local e = extrasFor(humans)
    local t0 = toBaseDown(w)
    -- the portal wave: pulse on every peer, the native build stays direct, extras are concealed tickets
    F.runUntil(function() return w.now > t0 + 83 end)
    for i = 1, humans do
        check(F.count(p[i], "PortalOut") == 1 and F.count(p[i], "ActivatePortal") == 1, "the portal opens on peer " .. i)
    end
    check(F.count(p[1], "PortalOut", "portal") == 1, "the pulse names the portal")
    local portalUnits = builtAt(p[1], "@portal")
    check(#portalUnits == 2, humans .. " human(s): the native portal build is exactly two units: " .. #portalUnits)
    local extraUnits = builtAt(p[1], "portal_spawn")
    check(#extraUnits == e, humans .. " human(s): the portal wave has " .. e .. " co-op extras: " .. #extraUnits)
    allSafe(p, extraUnits)
    for _, b in ipairs(extraUnits) do
        check(b.team == 5 and b.odf == "cvrckt", "portal extras are Chinese craft on team 5, the wave's kind")
        local goto_ = false
        for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[2] == b.h and c[3] == "camera_go" then goto_ = true end end
        check(goto_, "portal extras fly to camera_go like the wave")
    end
    check(next(m.crcca.arrivals) == nil, "the cancelled primary ticket leaves nothing waiting")
    F.runUntil(function() return w.now > t0 + 83.5 end)
    F.run(2)
    check(F.count(p[1], "DeactivatePortal") == 1, "the portal closes after two seconds")
    -- hunters at +110 s: Hunt on tickets
    F.runUntil(function() return w.now > t0 + 112 end)
    local hunters = builtAt(p[1], "attack_always")
    check(#hunters == 5 + e, humans .. " human(s): five hunters + " .. e .. " extras: " .. #hunters)
    allSafe(p, hunters)
    local hunts = {}
    for _, c in ipairs(F.callsOf(p[1], "Hunt")) do hunts[c[2]] = true end
    for _, b in ipairs(hunters) do check(hunts[b.h], "every hunter hunts (extras too)") end
    -- first counter-attack at +180 s
    reap()
    F.runUntil(function() return w.now > t0 + 185 end)
    local tanks = builtAt(p[1], "attack_1")
    check(#tanks == 2 + e, humans .. " human(s): two tanks + " .. e .. " extras: " .. #tanks)
    allSafe(p, tanks)
    local set = humanSet(p)
    for _, b in ipairs(tanks) do
        local target
        for _, c in ipairs(F.callsOf(p[1], "Attack")) do if c[2] == b.h then target = c[3] end end
        check(set[target], "the counter-attack goes for a human, never the token: " .. tostring(target))
    end
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end
do -- a human nearest to the unit is the target
    local w, p, m = setup(3, {})
    F.place(p[3].player, 190, 100560) -- 40 m from the attack_1 entry... and hence too close to use it
    local t0 = toBaseDown(w)
    F.runUntil(function() return w.now > t0 + 185 end)
    local tanks = F.builds(p[1], t0, "cvtnk")
    check(#tanks >= 2, "the counter-attack is built")
    for _, b in ipairs(tanks) do
        check(b.where ~= "attack_1", "the watched entry attack_1 is not used")
        check(p[1].env.GetDistance(p[3].player, b.h) >= 460, "nothing is built near the human at the entry")
    end
    -- hunters come from the next hidden approach too
    for _, b in ipairs(F.builds(p[1], 0, "cvtnk")) do
        for _, q in ipairs(p) do check(q.env.GetDistance(q.player, b.h) >= 460, "no pop-in anywhere") end
    end
end
do -- a counter-attack unit whose target is gone attacks the nearest human again
    local w, p, m = setup(2, {})
    local t0 = toBaseDown(w)
    F.runUntil(function() return w.now > t0 + 185 end)
    local tanks = builtAt(p[1], "attack_1")
    local before = F.count(p[1], "Attack")
    for _, b in ipairs(tanks) do F.world().objects[b.h].command = 0 end
    F.run(12)
    check(F.count(p[1], "Attack") >= before + #tanks, "idle chasers attack a human again")
    local after = F.count(p[1], "Attack")
    F.run(12)
    check(F.count(p[1], "Attack") == after, "busy chasers are left alone")
end
do -- a fully watched map defers the tickets without a native call; a save/load keeps them and builds them once
    local w, p, m = setup(4, {})
    local t0 = toBaseDown(w)
    local saved = {}
    for name, pos in pairs(w.pathPos) do
        if name == "attack_1" or name == "attack_always" or name == "dummy_1" or name == "attack_2" or name == "attack_3"
            or name == "portal_spawn" or name == "portal_attack_1" or name == "portal_attack_2" then
            saved[name] = pos
        end
    end
    for name in pairs(saved) do w.pathPos[name] = { x = 4000, y = 10, z = 98000 } end
    F.place(p[2].player, 4000, 98000)
    F.world().objects[p[2].player].craft = false
    F.runUntil(function() return w.now > t0 + 185 end)
    check(#F.builds(p[1], 0, "cvtnk") == 0, "a watched map defers every wave")
    check(type(m.badguy[0]) == "number" and m.badguy[0] < 0, "the body holds tickets while the wave waits")
    check(F.count(p[1], "Goto", "camera_go") == 0 and F.count(p[1], "Hunt") == 0, "no native order ever sees a ticket")
    local pending = m.crcca.serial
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(m.crcca.serial == pending and #F.builds(p[1], 0, "cvtnk") == 0, "save/load keeps the pending wave without duplicating it")
    for name, pos in pairs(saved) do w.pathPos[name] = pos end
    F.place(p[2].player, 20000, 20000)
    F.run(8)
    local built = #F.builds(p[1], 0, "cvtnk")
    check(built > 0 and next(m.crcca.arrivals) == nil, "everything is built once the watcher leaves: " .. built)
    check(type(m.badguy[0]) == "string", "tickets resolve to real units")
end
do -- live cap: extras are the only requests dropped
    local w, p, m = setup(4, {})
    local t0 = toBaseDown(w)
    m.crcca.live = {}
    for i = 1, 30 do m.crcca.live[i] = F.spawn("cvtnk", 5, 9000 + i, 9000) end
    F.runUntil(function() return w.now > t0 + 185 end)
    check(#builtAt(p[1], "attack_1") == 2, "at the live cap the wave keeps its primaries and drops the extras")
end

-- ------------------------------------------------------------------ the recycler, the APC, the portal, the victory
for humans = 1, 4 do
    local w, p, m = setup(humans, {})
    intro(w); w.cameraDone["camera_go"] = true
    local e = extrasFor(humans)
    drive(w, p, function() return m.missionState == MS.WAITFORAPC end)
    check(m.recycler ~= nil and F.count(p[1], "Deploy", m.recycler) == 1, humans .. ": the recycler deploys once")
    check(F.heardCount(p[1], "bd06004.wav") == 1, "the build-an-APC order is heard")
    local recyclers = F.builds(p[1], 0, "bvrecy")
    check(#recyclers == 1 and recyclers[1].team == 1, "the recycler is the shared Black Dog unit, never a ticket")
    F.run(2) -- two tickets are built per frame
    -- the last raid (attack_3): five hunters + extras
    local raid = builtAt(p[1], "attack_3")
    check(#raid == 5 + e, humans .. " human(s): last raid is 5 + " .. e .. ": " .. #raid)
    -- a human builds the APC and brings it to the portal; every human's pulse and camera follow
    local apc = F.spawn("bvapc", 1, 940, 100712)
    F.world().objects[apc].command = 0
    w.audioBusy = true
    F.run(2)
    check(m.portalours and m.missionState >= MS.ENDCUTSCENE, "the APC at apc_in makes the portal ours")
    for i = 1, humans do
        check(p[i].camera == 1 and F.last(p[i], "CameraPath")[2] == "camera_end_scene", "the end scene is shared: peer " .. i)
    end
    -- the artillery entry is 230 m from the humans' start: the group comes from another hidden approach
    local artillery = F.builds(p[1], 0, "cvartl")
    check(#artillery == 3 + e, humans .. " human(s): three artillery + extras against the portal: " .. #artillery)
    allSafe(p, artillery)
    w.audioBusy = false
    w.cameraDone["camera_end_scene"] = true
    F.world().objects[m.apchandle].command = 0 -- the APC has driven in
    F.run(3)
    for i = 1, humans do check(p[i].camera == 0, "end-scene cameras balanced on peer " .. i) end
    heardAll(p, "bd06009.wav")
    local dummies = builtAt(p[1], "dummy_1")
    check(#dummies == 7 + e, humans .. " human(s): seven dummy tanks + extras: " .. #dummies)
    allSafe(p, dummies)
    drive(w, p, function() return F.count(p[1], "SucceedMission") + F.count(p[1], "FailMission") > 0 or m.missionState == MS.WAITAPCOUT end,
        { noApc = true })
    -- the closing narration: bd06008, then 5 s, then bd06005, then the victory
    w.audioBusy = true
    F.run(3)
    check(F.heardCount(p[1], "bd06008.wav") == 1 and F.heardCount(p[1], "bd06005.wav") == 0 and F.count(p[1], "SucceedMission") == 0,
        "the APC is out: bd06008 plays and nothing else yet")
    F.run(10)
    check(F.heardCount(p[1], "bd06005.wav") == 0, "the victory waits for the line to finish")
    w.audioBusy = false
    F.run(3)
    check(F.heardCount(p[1], "bd06005.wav") == 0, "five seconds after bd06008")
    F.run(4)
    for i = 1, humans do
        check(F.heardCount(p[i], "bd06008.wav") == 1 and F.heardCount(p[i], "bd06005.wav") == 1, "both closing lines on peer " .. i)
        local order = {}
        for _, f in ipairs(F.lines(p[i])) do if f == "bd06008.wav" or f == "bd06005.wav" then order[#order + 1] = f end end
        check(order[1] == "bd06008.wav" and order[2] == "bd06005.wav", "bd06008 before bd06005 on peer " .. i)
    end
    F.run(15)
    for i = 1, humans do
        check(F.count(p[i], "SucceedMission") == 1 and F.count(p[i], "FailMission") == 0, "one shared victory on peer " .. i)
        check(F.last(p[i], "SucceedMission")[3] == "bd06wina.des", "victory debrief on peer " .. i)
        check((p[i].env.Save().coopUnresolved or 0) == 0, "no unresolved presentation identities on peer " .. i)
    end
    -- the victory is latched: a late co-op failure cannot override it, and nothing more spawns
    local builds = #F.builds(p[1])
    F.kill("portal") -- the body has stopped: neither a loss nor a second result follows
    F.run(120)
    check(F.count(p[1], "FailMission") == 0 and #F.builds(p[1]) == builds, "after the victory: no failure and no reinforcements")
    guestsPassive(p)
end
do -- a save during the closing narration does not lose or repeat the victory
    local w, p, m = setup(2, {})
    intro(w); w.cameraDone["camera_go"] = true; w.cameraDone["camera_end_scene"] = true
    drive(w, p, function() return m.missionState == MS.WAITAPCOUT end)
    w.audioBusy = true
    F.run(2)
    check(F.heardCount(p[1], "bd06008.wav") == 1, "bd06008 plays")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); w.audioBusy = false; F.run(40)
    check(F.count(p[1], "SucceedMission") == 1 and F.heardCount(p[1], "bd06008.wav") == 1 and F.heardCount(p[1], "bd06005.wav") == 1,
        "one victory and each closing line once after a load")
end
do -- the recycler lost before the APC: bd06006 then bd06lsec, once
    local w, p, m = setup(3, {})
    intro(w); w.cameraDone["camera_go"] = true
    drive(w, p, function() return m.missionState == MS.WAITFORAPC end, { noApc = true })
    F.kill(m.recycler)
    w.audioBusy = true; F.run(3)
    heardAll(p, "bd06006.wav")
    w.audioBusy = false; F.run(5)
    for i = 1, 3 do check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd06lsec.des", "no production: bd06lsec on peer " .. i) end
end
do -- the cut friendly-damage check stays cut: a damaged Black Dog tank loses nothing
    local w, p, m = setup(2, {})
    intro(w); F.run(5)
    F.world().objects["bdtank_1"].health = 0.2
    F.run(30)
    check(F.count(p[1], "FailMission") == 0 and m.missionState >= MS.WAITING1 and m.missionState ~= 24, "friendly damage is not a loss")
end
do -- the restoration flags: the victory narration is only a restoration
    local w, p, m = setup(1, {})
    intro(w)
    check(F.count(p[1], "StartCockpitTimer") == 1, "the timer is shown")
end

-- ------------------------------------------------------------------ loads and the leader
do -- a load during the opening film opens the camera again, once, and the film still ends
    local w, p, m = setup(3, {})
    F.run(3)
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(p[1].camera == 1, "the film's camera is reopened after a load")
    intro(w)
    for i = 1, 3 do check(p[i].camera == 0, "camera balanced after the load on peer " .. i) end
end
do -- a load while the timer runs shows it again with what is left
    local w, p, m = setup(2, {})
    intro(w); F.run(100)
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    local last = F.last(p[1], "StartCockpitTimer")
    check(F.count(p[1], "StartCockpitTimer") == 2 and last[2] < 660 - 90 and last[2] > 660 - 120, "the timer restarts with the time left: " .. tostring(last and last[2]))
end
do -- a load republishes the objectives (the runtime's Load resets the presentation) and cancels nothing
    local w, p, m = setup(2, {})
    intro(w); F.run(5)
    local before = F.count(p[1], "AddObjective")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "AddObjective") > before and F.last(p[1], "AddObjective")[2] == "bd06001.otf", "objectives are republished after a load")
    check(F.count(p[2], "AddObjective", "bd06001.otf") >= 2, "...and reach the guest")
end
do -- a missing audio handle never blocks a gate nor replays the line
    local w, p, m = setup(1, {})
    p[1].env.AudioMessage = function() return nil end
    w.audioBusy = true
    intro(w); F.run(30)
    check(m.missionState >= 3, "the diversion goes on although the line has no handle")
end
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
    check(F.count(p[1], "EnvironmentInit") == 0 and m.missionState == MS.STARTCAMERA, "no weather module: the mission runs and touches no Environment")
    local printed = false
    for _, c in ipairs(p[1].calls) do if c[1] == "print" and tostring(c[2]):find("weather disabled", 1, true) then printed = true end end
    check(printed, "missing weather is logged, not fatal")
end
local function ganymede(record, mode, sites)
    return function(peer)
        local V = { Seed = 4242, Initialized = false }
        local level = 1
        function V.Init(o)
            peer.weatherInit = o; V.Initialized = true
            record("EuropaInit", o.authority, o.send ~= nil, o.seed, o.startLevel, o.targetLevel)
            if mode == "initfail" then error("boom") end
        end
        function V.Update()
            if peer.weatherInit and peer.weatherInit.authority and peer.weatherInit.send and not V.sent then
                V.sent = true; peer.weatherInit.send("EuropaQuake", 0.5, 2)
            end
            if mode == "updatefail" then error("update boom") end
        end
        function V.AnnounceState() record("EuropaAnnounce") end
        function V.ApplyNetEvent(op, ...) record("EuropaEvent", op, ...) end
        function V.SetTargetLevel(n) level = n; record("EuropaLevel", n) end
        function V.GetTargetLevel() return level end
        function V.ReleaseForcedLevel() record("EuropaRelease") end
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
    -- the real generated sites: four geyser vents (three in the Chinese base)
    local sites = dofile("Scripts/CRGanymedeSitesBD06.lua")
    check(sites.mission == "bdmisn06" and #sites.vents == 4 and sites.vents[3].label == "eggeizr143_geyser", "the generated sites carry the geysers")
    local weather = { module = function(peer, record) return ganymede(record, nil, sites)(peer) end, sites = sites }
    local w, p, m = setup(3, { weather = weather })
    check(F.count(p[1], "EuropaInit", true) == 1 and F.last(p[1], "EuropaInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.last(p[1], "EuropaInit")[5] == 1 and F.last(p[1], "EuropaInit")[6] == 1, "the moon starts quiet")
    check(F.count(p[2], "EuropaInit", false) == 1, "guests render only (not the authority)")
    check(F.count(p[1], "EuropaAnnounce") == 1 and F.count(p[2], "EuropaAnnounce") == 0, "the leader announces its weather state once")
    check(F.last(p[1], "EnvironmentInit")[2].lightingMode == "orbit", "orbit lighting is initialised")
    for i = 2, 3 do
        local ev = F.last(p[i], "EuropaEvent")
        check(ev and ev[2] == "EuropaQuake" and ev[3] == 0.5, "weather events reach guest " .. i)
    end
    check(F.count(p[1], "WeatherSensors", "Ganymede") == 1, "the sensor modifier is bound once")
    check(p[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    check(F.count(p[1], "EuropaLevel", 2) == 0, "calm during the opening")
    intro(w); w.cameraDone["camera_go"] = true
    F.run(22)
    check(F.count(p[1], "EuropaLevel", 2) == 1 and F.count(p[1], "EuropaQuakeCall", 0.3) == 1, "'Delta Three is Go' stirs the moon")
    F.run(10)
    for _, l in ipairs(BASE) do F.kill(l) end
    F.run(2)
    check(F.count(p[1], "EuropaLevel", 3) == 1 and F.count(p[1], "EuropaQuakeCall", 0.4) == 1 and F.count(p[1], "EuropaPlume", 3) == 1,
        "the base falls: level 3, a quake and the vent in its ruins")
    drive(w, p, function() return m.missionState >= MS.WAITFORBADGUY1DIE end, { keepBase = true })
    check(F.count(p[1], "EuropaPlume", 2) == 1, "the first counter-attack opens the next vent")
    drive(w, p, function() return m.missionState >= MS.WAITFORSOUND3 end)
    check(F.count(p[1], "EuropaSurgeCall", 5.0) == 1, "the heavy counter-attack is beaten: a surge")
    drive(w, p, function() return m.missionState >= MS.WAITFORBADGUY3 end)
    F.run(1)
    check(F.count(p[1], "EuropaLevel", 4) == 1 and F.count(p[1], "EuropaPlume", 4) == 1 and F.count(p[1], "EuropaQuakeCall", 0.35) == 1,
        "the recycler deploys: level 4, a quake and the last vent " .. F.count(p[1], "EuropaLevel", 4) .. "/" .. F.count(p[1], "EuropaPlume", 4) .. "/" .. F.count(p[1], "EuropaQuakeCall", 0.35))
    check(F.count(p[1], "EuropaCreated") > 0, "new objects are offered to the weather")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "EuropaShutdown") >= 1 and F.count(p[1], "EuropaLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(p[1], "WeatherSensors", "Ganymede") == 2, "the sensor modifier is bound again after a load")
    drive(w, p, function() return m.portalours end)
    F.run(2)
    check(F.count(p[1], "EuropaSurgeCall", 6.0) == 1 and F.count(p[1], "EuropaQuakeCall", 0.5) == 1, "the portal pulses: a surge and a quake")
    w.cameraDone["camera_end_scene"] = true
    drive(w, p, function() return m.crWon end)
    F.run(2)
    check(F.count(p[1], "EuropaRelease") == 1 and F.count(p[1], "EuropaLevel", 2) == 2, "the victory eases the weather")
end
do -- an empty vent list is legal: plumes are skipped, everything else runs
    local sites = { vents = {} }
    local w, p, m = setup(2, { weather = { module = function(peer, record) return ganymede(record, nil, sites)(peer) end, sites = sites } })
    intro(w); w.cameraDone["camera_go"] = true; F.run(40)
    for _, l in ipairs(BASE) do F.kill(l) end
    F.run(3)
    check(F.count(p[1], "EuropaPlume") == 0 and F.count(p[1], "EuropaLevel", 3) == 1, "no vents, no plumes")
end
do -- sites module missing: no weather, never an error
    local sites = dofile("Scripts/CRGanymedeSitesBD06.lua")
    local w, p, m = setup(2, { weather = { module = function(peer, record) return ganymede(record, nil, sites)(peer) end } })
    check(F.count(p[1], "EuropaInit") == 0 and m.missionState == MS.STARTCAMERA, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local sites = dofile("Scripts/CRGanymedeSitesBD06.lua")
    local w, p, m = setup(2, { weather = { module = function(peer, record) return ganymede(record, mode, sites)(peer) end, sites = sites } })
    intro(w)
    F.run(25)
    local sent = 0
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[3] == "fake_attack" then sent = sent + 1 end end
    check(sent == 10, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("bdmisn06 co-op: " .. checks .. " checks passed")
