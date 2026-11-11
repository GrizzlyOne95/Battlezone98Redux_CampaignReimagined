-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/bd12cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/Test-Bdmisn12Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Bdmisn12Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

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
-- Chinese craft the script built (never map objects) at a path.
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
    for i, q in ipairs(p) do check(F.heardCount(q, file) == (count or 1), "peer " .. i .. " hears " .. file .. " x" .. (count or 1) .. ", got " .. F.heardCount(q, file)) end
end
local function guestsPassive(p)
    for i = 2, #p do
        for _, name in ipairs({"BuildObject", "BuildObjectAtPortal", "SetScrap", "SetCloaked", "Goto", "Attack", "Defend2"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on the authored enemy team 2") end
end
local function reap() -- every unit the script built is destroyed
    for h, o in pairs(F.world().objects) do
        if o.alive and (h:match("^built") or h:match("^portal%d")) then o.alive = false end
    end
end
local function finishIntro(w) w.cameraDone["camera_start"] = true; F.run(1) end
local function killGoals() for i = 1, 4 do F.kill("goal_" .. i) end end
local STAGING = {}
for i = 1, 8 do STAGING[#STAGING + 1] = "attack_" .. i; STAGING[#STAGING + 1] = "defend_" .. i end
for i = 1, 4 do STAGING[#STAGING + 1] = "despor_" .. i end

-- ------------------------------------------------------------------ offline == faithful
local function summary(peer)
    local waves, out, scrap, lines = {}, {}, 0, {}
    for _, c in ipairs(peer.calls) do
        if c[1] == "BuildObject" then
            if c[3] == "npscr1" then scrap = scrap + 1
            else waves[#waves + 1] = "B:" .. c[3] .. ":" .. (c[4] == 2 and 5 or c[4]) .. ":" .. tostring(c[5]) end
        elseif c[1] == "BuildObjectAtPortal" then
            out[#out + 1] = "P:" .. c[3] .. ":" .. (c[4] == 2 and 5 or c[4])
        elseif c[1] == "SucceedMission" or c[1] == "FailMission" then
            out[#out + 1] = c[1] .. ":" .. tostring(c[3])
        elseif c[1] == "SetCloaked" then
            out[#out + 1] = "C"
        elseif c[1] == "AudioMessage" or c[1] == "Play" then
            if c[2] ~= "bd12002.wav" then lines[#lines + 1] = c[2] end
        elseif c[1] == "ClearObjectives" or c[1] == "AddObjective" then
            if c[1] == "AddObjective" then out[#out + 1] = "O:" .. c[2] .. ":" .. c[3] end
        end
    end
    -- the scrap and the cloaks interleave with the one-frame-late tickets: compare them as sorted tallies
    local cloaks = 0
    local rest = {}
    for _, s in ipairs(out) do if s == "C" then cloaks = cloaks + 1 else rest[#rest + 1] = s end end
    return table.concat(waves, ",") .. "|" .. cloaks .. "|" .. scrap .. "|" .. table.concat(rest, ",") .. "|" .. table.concat(lines, ",")
end
local function fullRun(options)
    local w = F.reset()
    local peer = F.makePeer(1, 1, false, options)
    F.connect(); F.run(1)
    -- the human is away from every staging point, so no entry is watched and the offline run equals the faithful one
    F.place(peer.player, 2500, 99000)
    w.cameraDone["camera_start"] = true
    F.run(500)
    F.kill("power_2") -- the counterattack tanks of pair 2
    F.run(300)
    killGoals()
    F.run(15)
    return summary(peer), peer
end
do
    local faithful = fullRun({ faithful = true, script = "Scripts/bdmisn12.lua" })
    local offline, peer = fullRun({})
    check(faithful == offline and faithful:find("SucceedMission:bd12win.des", 1, true),
        "offline completes like the faithful port:\n" .. faithful .. "\n" .. offline)
    check(F.count(peer, "SucceedMission") == 1 and F.count(peer, "FailMission") == 0, "one victory, no failure")
    noEnemyTeamTwo(peer)
    check(F.count(peer, "SetAIControl", 5) == 1 and F.count(peer, "SetAIControl", 2) == 0, "AI control only for enemy team 5")
    check(F.index(peer, "SetAIControl") <= peer.chunkCalls, "SetAIControl runs at chunk root, before Start")
    local scrap = {}
    for _, c in ipairs(F.callsOf(peer, "SetScrap")) do scrap[c[2]] = c[3] end
    check(scrap[1] == 50 and scrap[5] == 10 and scrap[2] == nil, "scrap 50 for the Black Dogs, 10 for the Chinese (team 5)")
end

-- ------------------------------------------------------------------ teams, scrap, pilots, the opening film
do
    local w, p, m = setup(4, {})
    F.run(4)
    check(m.startDone and m.coopMissionStarted, "the leader starts the shared mission")
    check(F.callsOf(p[1], "SetScrap")[1][3] == 50 + 10 * 3, "starting scrap: 50 plus 10 per guest")
    for team = 1, 4 do check(F.count(p[1], "SetPilot", team) == 1 and F.callsOf(p[1], "SetPilot")[1][3] == 10, "10 pilots for human team " .. team) end
    for i = 1, 4 do
        check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
        check(F.heardCount(p[i], "bd12001.wav") == 1, "briefing once on peer " .. i)
        check(p[i].camera == 1, "the opening film is shared: peer " .. i)
        check(F.last(p[i], "CameraPath")[2] == "camera_start" and F.last(p[i], "CameraPath")[5] == "portal", "opening shot at the portal on peer " .. i)
    end
    check(not m.cameraComplete[0], "the opening runs until its shot arrives")
    finishIntro(w)
    check(m.cameraComplete[0], "the opening ends when the path is done")
    for i = 1, 4 do
        check(p[i].camera == 0, "opening cameras balanced on peer " .. i)
        local o = F.callsOf(p[i], "AddObjective")
        check(o[1] and o[1][2] == "bd12001.otf" and o[1][3] == "white", "first objective on peer " .. i)
    end
    guestsPassive(p)
end
do -- a host skip releases only the host's camera and the runtime stops driving the shot: the opening ends for all
    local w, p, m = setup(3, {})
    w.cancel = true; F.run(2)
    w.cancel = false; F.run(1)
    check(m.cameraComplete[0], "a host skip ends the shared opening instead of stalling it")
    for i = 1, 3 do check(p[i].camera == 0, "no peer is left in the film after a host skip: " .. i) end
end
do -- a skip latched before the shot started does not end it
    local w = F.reset()
    local p = { F.makePeer(1, 1, true, {}), F.makePeer(2, 2, true, {}) }
    w.cancel = true
    F.connect(); F.run(3)
    check(not p[1].env.Save().cameraComplete[0] and p[1].camera == 1, "a stale skip latch is cleared when the shot starts")
    finishIntro(w)
    check(p[1].env.Save().cameraComplete[0], "the shot still ends on its own arrival")
end
do -- offline: skippable
    local w, p, m = setup(1, {})
    check(p[1].camera == 1, "offline opening opens")
    w.cancel = true; F.run(1)
    check(m.cameraComplete[0] and p[1].camera == 0, "offline skip ends the opening")
    w.cancel = false; F.run(40)
    check(F.count(p[1], "CameraReady") == 1, "a skipped opening never restarts")
end

-- ------------------------------------------------------------------ the raids: scaling, cloak, orders, no pop-in
-- { time, path, count of the primaries, order, target-label-prefix }
local RAIDS = {
    { at = 120, group = {
        { "attack_1", 3, "Attack", "power_1" }, { "defend_1", 2, "Defend2" } } },
    { at = 240, group = {
        { "attack_2", 4, "Attack", "power_2" }, { "defend_2", 4, "Defend2" } } },
    { at = 360, group = {
        { "attack_3", 4, "Attack", "power_3" }, { "defend_3", 4, "Defend2" } } },
}
for humans = 1, 4 do
    local w, p, m = setup(humans, {})
    finishIntro(w)
    local e = extrasFor(humans)
    for _, raid in ipairs(RAIDS) do
        F.runUntil(function() return w.now > raid.at + 4 end, 2000)
        for _, g in ipairs(raid.group) do
            local units = builtAt(p[1], g[1])
            check(#units == g[2] + e, humans .. " human(s): " .. g[1] .. " is " .. g[2] .. " + " .. e .. " extras, got " .. #units)
            allSafe(p, units)
            for _, b in ipairs(units) do
                check(b.team == 5 and b.odf:sub(1, 2) == "cv", "raiders are Chinese craft on team 5")
                check(F.world().objects[b.h].cloaked, "every raider of the first three raids is cloaked (extras too)")
            end
            local orders = 0
            for _, c in ipairs(F.callsOf(p[1], g[3])) do
                if (g[4] == nil or c[3] == g[4]) and c[4] == 1 then
                    for _, b in ipairs(units) do if c[2] == b.h then orders = orders + 1 end end
                end
            end
            check(orders >= g[2] + e - (g[4] and 0 or e), g[1] .. ": the orders are issued on the primaries and mirrored on the extras: " .. orders)
        end
        reap(); p[1].env.Save().crcca.live = {}
    end
    -- the walkers (480 s): five attackers, uncloaked, each aimed at a different target, ten escorts
    F.runUntil(function() return w.now > 484 end, 2000)
    local walkers = F.builds(p[1], 0, "cvwalk")
    local primaries = 0
    for _, b in ipairs(walkers) do
        check(not F.world().objects[b.h].cloaked, "walkers are not cloaked")
        allSafe(p, { b })
    end
    local desired = 15 + 10 * e
    local fourth = 0
    for i = 4, 8 do fourth = fourth + #builtAt(p[1], "attack_" .. i) + #builtAt(p[1], "defend_" .. i) end
    if e <= 1 then
        check(fourth == desired, humans .. " human(s): wave 4 is " .. desired .. ", got " .. fourth)
    else
        check(fourth >= 24 and fourth <= desired, "wave 4 drops only extras at the live cap: " .. fourth)
    end
    local primaryWalkers = 0
    for i = 4, 8 do
        local target = (i == 8) and "portal" or ("shield_" .. (i - 3))
        local hit = false
        for _, c in ipairs(F.callsOf(p[1], "Attack")) do
            if c[3] == target and c[4] == 1 and F.world().objects[c[2]] and F.world().objects[c[2]].odf == "cvwalk" then hit = true end
        end
        check(hit, "a walker attacks " .. target)
    end
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end

-- ------------------------------------------------------------------ counterattack tanks and the fallback entry
do
    local w, p, m = setup(1, {})
    finishIntro(w)
    F.kill("shield_1") -- despor_1 is 567 m from the start: authored entry
    F.run(2)
    local tanks = builtAt(p[1], "despor_1", "cvltnk")
    check(#tanks == 2, "a lost shield sends two tanks from despor_1")
    local atPortal = 0
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do if c[3] == "portal" and c[4] == 1 then atPortal = atPortal + 1 end end
    check(atPortal == 2, "...and they attack the portal")
    for _, b in ipairs(tanks) do check(F.world().objects[b.h].cloaked, "counterattack tanks are cloaked") end
    F.kill("power_1"); F.run(2)
    check(#builtAt(p[1], "despor_1", "cvltnk") == 2, "one pair per generator pair, however many are lost")
end
do -- despor_3 is 424 m from the start: another hidden approach is used, never a build in view
    local w, p, m = setup(1, {})
    finishIntro(w)
    F.kill("power_3"); F.run(2)
    check(#builtAt(p[1], "despor_3") == 0, "nothing is built at the watched despor_3")
    local tanks = builtAt(p[1], "attack_1", "cvltnk")
    check(#tanks == 2, "the pair comes from the first clear fallback approach")
    allSafe(p, tanks)
end
do -- more humans, more tanks
    local w, p, m = setup(4, {})
    finishIntro(w)
    F.kill("shield_2"); F.run(2)
    check(#builtAt(p[1], "despor_2", "cvltnk") == 2 + 2, "four humans: the pair plus two extras")
end

-- ------------------------------------------------------------------ the portal: recycler, escorts (TRO 1.3 timing)
do
    for humans = 1, 3 do
        local w, p, m = setup(humans, {})
        finishIntro(w)
        F.runUntil(function() return w.now > 770 end, 2000)
        check(F.count(p[1], "BuildObjectAtPortal") == 0, "nothing comes through the portal before 13 minutes")
        for i = 1, humans do check(F.count(p[i], "PortalOut", "portal") == 0, "the portal is shut until 778 s: peer " .. i) end
        F.runUntil(function() return w.now > 783 end)
        for i = 1, humans do check(F.count(p[i], "PortalOut", "portal") == 1 and F.count(p[i], "ActivatePortal", "portal") == 1,
            "the portal opens once on every peer, ahead of the recycler: peer " .. i) end
        check(F.count(p[1], "BuildObjectAtPortal") == 1 and F.callsOf(p[1], "BuildObjectAtPortal")[1][3] == "bvrecyd", "the recycler arrives first")
        F.runUntil(function() return w.now > 789 end)
        check(F.count(p[1], "BuildObjectAtPortal") == 3, "two tanks follow the recycler at 786 s")
        for _, c in ipairs(F.callsOf(p[1], "BuildObjectAtPortal")) do check(c[4] == 1 and c[5] == "portal", "reinforcements belong to the shared Black Dog team") end
        F.runUntil(function() return w.now > 797 end)
        check(F.count(p[1], "BuildObjectAtPortal") == 4, "then the fighter at 792 s")
        for i = 1, humans do check(F.count(p[i], "DeactivatePortal", "portal") == 1, "the portal closes on peer " .. i) end
        local follows = 0
        for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[3] == "follow" and c[4] == 1 then follows = follows + 1 end end
        check(follows == 4, "the recycler and the escorts follow the player")
        guestsPassive(p)
    end
end

-- ------------------------------------------------------------------ objectives, the win, the loss
for humans = 1, 3 do
    local w, p, m = setup(humans, {})
    finishIntro(w)
    killGoals()
    F.run(30)
    check(not m.objective2Complete and not m.won, "the goals alone do not win before the defence objective advances")
    w.audioBusy = true
    F.runUntil(function() return w.now > 800 end, 2000)
    for i = 1, humans do
        check(F.last(p[i], "AddObjective")[2] == "bd12002.otf" and F.last(p[i], "AddObjective")[3] == "white", "second objective on peer " .. i)
    end
    F.run(3)
    check(m.objective2Complete and not m.won, "all four goals dead: the narration plays first")
    heardAll(p, "bd12003.wav")
    w.audioBusy = false; F.run(8)
    for i = 1, humans do
        check(F.count(p[i], "SucceedMission") == 1 and F.count(p[i], "FailMission") == 0, "one shared victory on peer " .. i)
        check(F.last(p[i], "SucceedMission")[3] == "bd12win.des", "victory debrief on peer " .. i)
        check((p[i].env.Save().coopUnresolved or 0) == 0, "no unresolved presentation identities on peer " .. i)
    end
    guestsPassive(p)
end
for humans = 1, 3 do
    local w, p, m = setup(humans, {})
    finishIntro(w)
    F.run(10)
    F.kill("portal")
    w.audioBusy = true; F.run(3)
    heardAll(p, "bd12004.wav")
    check(F.count(p[1], "FailMission") == 0, "the loss waits for the narration")
    w.audioBusy = false; F.run(5)
    for i = 1, humans do
        check(F.count(p[i], "FailMission") == 1 and F.count(p[i], "SucceedMission") == 0, "one shared loss on peer " .. i)
        check(F.last(p[i], "FailMission")[3] == "bd12lsea.des", "loss debrief on peer " .. i)
    end
    check(m.lost, "the loss latches")
end
do -- missing audio handles never hang an ending
    local w, p, m = setup(1, {})
    finishIntro(w)
    p[1].env.AudioMessage = function() return nil end
    killGoals()
    F.runUntil(function() return w.now > 800 end, 2000)
    F.run(4)
    check(F.count(p[1], "SucceedMission") == 1, "a victory narration that returns nothing still ends the mission")
end

-- ------------------------------------------------------------------ voice lines
do
    local w, p, m = setup(2, {})
    F.run(4)
    check(F.heardCount(p[1], "bd12002.wav") == 0, "no 'back home to roost' during the opening")
    finishIntro(w)
    F.run(1)
    heardAll(p, "bd12002.wav")
    check(F.index(p[1], "Play", "bd12001.wav") < F.index(p[1], "Play", "bd12002.wav") or F.index(p[1], "Queue", "bd12002.wav"), "after the briefing")
    F.run(300)
    heardAll(p, "bd12002.wav")
end
do -- a skipped opening still gets its answer
    local w, p, m = setup(1, {})
    w.cancel = true; F.run(1); w.cancel = false; F.run(2)
    heardAll(p, "bd12002.wav")
end
do -- after the end neither the answer nor a retarget happens
    local w, p, m = setup(1, {})
    m.won = true; m.cameraComplete[0] = true
    F.run(3)
    check(F.heardCount(p[1], "bd12002.wav") == 0, "no 'roost' line after the win")
end
do -- shield and power warnings: each once, on every peer
    local w, p, m = setup(3, {})
    finishIntro(w)
    F.world().objects["shield_2"].health = 0.2; F.run(2)
    heardAll(p, "bd12006.wav")
    F.run(5)
    heardAll(p, "bd12006.wav")
    F.world().objects["power_2"].health = 0.2; F.run(2)
    heardAll(p, "bd12006.wav", 2)
    F.world().objects["power_4"].health = 0.1; F.run(2)
    heardAll(p, "bd12008.wav")
end

do -- repaired units re-arm their warning above 50 %, not between 25 % and 50 %
    local w, p, m = setup(3, {})
    finishIntro(w)
    local o = F.world().objects
    o["shield_2"].health = 0.2; F.run(2)
    heardAll(p, "bd12006.wav")
    o["shield_2"].health = 0.4; F.run(2); o["shield_2"].health = 0.2; F.run(2)
    heardAll(p, "bd12006.wav") -- 25-50 % keeps the latch: no second warning
    o["shield_2"].health = 0.6; F.run(2); o["shield_2"].health = 0.2; F.run(2)
    heardAll(p, "bd12006.wav", 2) -- repaired above 50 %, then low again: warns again
    o["power_3"].health = 0.1; F.run(2)
    heardAll(p, "bd12007.wav")
    F.kill("power_3"); F.run(3)
    check(m.healthLow[2], "a dead unit does not clear its latch")
    m.healthLow[1] = nil; F.run(2) -- an old save without a latch entry loads and runs
    o["power_2"].health = 0.1; F.run(2)
    heardAll(p, "bd12006.wav", 3) -- and a nil latch still warns (power_2 shares shield_2's line)
end

-- ------------------------------------------------------------------ stock bug: a dead target leaves the raiders idle
do
    local w, p, m = setup(3, {})
    finishIntro(w)
    F.kill("power_1"); F.kill("shield_1") -- the first raid's target is gone before it is built
    F.runUntil(function() return w.now > 120 + 25 end)
    local fighters = builtAt(p[1], "attack_1", "cvfigh")
    check(#fighters == 3 + 1, "the first raid is still built without its target")
    local aimedAtDead = 0
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do if c[3] == "power_1" then aimedAtDead = aimedAtDead + 1 end end
    check(aimedAtDead == 0, "no order is aimed at the dead generator")
    local humans = {}
    for _, q in ipairs(p) do humans[q.player] = true end
    local hunts = {}
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do if humans[c[3]] and c[4] == 1 then hunts[c[2]] = true end end
    for _, b in ipairs(fighters) do check(hunts[b.h], "an idle raider is sent against the nearest human: " .. b.h) end
end
do -- ordered units are left alone
    local w, p, m = setup(3, {})
    finishIntro(w)
    F.runUntil(function() return w.now > 170 end)
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do
        check(not (c[3] == p[1].player or c[3] == p[2].player or c[3] == p[3].player), "units with an order keep it")
    end
end

-- ------------------------------------------------------------------ concealment, saves, the cap
local function watchEverything(w, p)
    F.place(p[2].player, 4000, 98000)
    F.world().objects[p[2].player].craft = false
    local saved = {}
    for _, name in ipairs(STAGING) do
        saved[name] = w.pathPos[name]
        w.pathPos[name] = { x = 4000, y = saved[name].y, z = 98000 }
    end
    return function()
        for _, name in ipairs(STAGING) do w.pathPos[name] = saved[name] end
        F.place(p[2].player, 20000, 20000)
    end
end
do
    local w, p, m = setup(4, {})
    finishIntro(w)
    local release = watchEverything(w, p)
    F.runUntil(function() return w.now > 125 end)
    check(#F.builds(p[1], 0, "cvfigh") == 0 and #F.builds(p[1], 0, "cvtnk") == 0, "a fully watched map defers every raider")
    check(type(m.delays) == "table" and m.crcca.serial >= 5, "the body holds tickets while the raid waits")
    check(F.count(p[1], "SetCloaked") == 0 and F.count(p[1], "Attack") == 0 and F.count(p[1], "Defend2") == 0, "no native call ever sees a ticket")
    local pending = m.crcca.serial
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(m.crcca.serial == pending and #F.builds(p[1], 0, "cvfigh") == 0, "save/load keeps the pending raid without duplicating it")
    release(); F.run(5)
    local total = #F.builds(p[1], 0, "cvfigh") + #F.builds(p[1], 0, "cvtnk")
    check(total == 5 + 2 * 2, "the whole raid is built exactly once when the watcher leaves, got " .. total)
    local cloaked = 0
    for _, o in pairs(F.world().objects) do if o.cloaked then cloaked = cloaked + 1 end end
    check(cloaked == 5 + 2 * 2, "the deferred cloak is applied to the primaries and their extras: " .. cloaked)
    local defends = 0
    for _, c in ipairs(F.callsOf(p[1], "Defend2")) do
        if F.world().objects[c[3]] then defends = defends + 1 end
    end
    check(defends == 2 + 2, "defend orders were rewritten to real handles: " .. defends)
end
do -- live cap: extras are the only requests dropped
    local w, p, m = setup(4, {})
    finishIntro(w)
    m.crcca.live = {}
    for i = 1, 24 do m.crcca.live[i] = F.spawn("cvtnk", 5, 9000 + i, 9000) end
    F.runUntil(function() return w.now > 125 end)
    check(#builtAt(p[1], "attack_1") == 3 and #builtAt(p[1], "defend_1") == 2, "at the live cap the raid keeps its primaries and drops the extras")
end
do -- a load during the opening film opens the camera again, once, and the film still ends
    local w, p, m = setup(3, {})
    F.run(3)
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(p[1].camera == 1, "the film's camera is reopened after a load")
    finishIntro(w)
    for i = 1, 3 do check(p[i].camera == 0, "camera balanced after the load on peer " .. i) end
end
for _, stage in ipairs({ { 200, "bd12001.otf", 1 }, { 800, "bd12002.otf", 2 } }) do
    -- the objectives survive a load: republished, in full, from the mission state
    local w, p, m = setup(3, {})
    finishIntro(w)
    F.runUntil(function() return w.now > stage[1] end, 2000)
    local before = {}
    for i = 1, 3 do before[i] = F.count(p[i], "AddObjective") end
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    for i = 1, 3 do
        check(F.count(p[i], "AddObjective") == before[i] + stage[3], "the objective list is rebuilt after a load on peer " .. i)
        check(F.last(p[i], "AddObjective")[2] == stage[2], "...with the right last entry on peer " .. i)
    end
    if stage[3] == 2 then
        local o = F.callsOf(p[2], "AddObjective")
        check(o[#o - 1][2] == "bd12001.otf" and o[#o - 1][3] == "green", "the first objective is green after a load")
    end
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
local function ganymede(record, mode, sites)
    return function(peer)
        local V = { Seed = 4242, Initialized = false }
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
    -- the real generated sites: six geyser vents (three under the Chinese goals)
    local sites = dofile("Scripts/CRGanymedeSitesBD12.lua")
    check(sites.mission == "bdmisn12" and #sites.vents == 6 and sites.vents[4].label == "eggeizr15_geyser", "the generated sites carry the six geysers")
    local weather = { module = function(peer, record) return ganymede(record, nil, sites)(peer) end, sites = sites }
    local w, p, m = setup(3, { weather = weather })
    check(F.count(p[1], "EuropaInit", true) == 1 and F.last(p[1], "EuropaInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.last(p[1], "EuropaInit")[5] == 1 and F.last(p[1], "EuropaInit")[6] == 1, "the moon starts quiet")
    check(F.count(p[2], "EuropaInit", false) == 1, "guests render only (not the authority)")
    check(F.count(p[1], "EuropaAnnounce") == 1 and F.count(p[2], "EuropaAnnounce") == 0, "the leader announces its weather state once")
    local env = F.last(p[1], "EnvironmentInit")[2]
    check(F.count(p[1], "EnvironmentInit") == 1 and env.lightingMode == "orbit", "orbit lighting is initialised")
    for i = 2, 3 do
        local e = F.last(p[i], "EuropaEvent")
        check(e and e[2] == "EuropaQuake" and e[3] == 0.5, "weather events reach guest " .. i)
    end
    check(F.count(p[1], "WeatherSensors", "Ganymede") == 1, "the sensor modifier is bound once")
    check(p[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    finishIntro(w)
    F.runUntil(function() return w.now > 115 end)
    check(F.count(p[1], "EuropaLevel", 2) == 0, "calm until the first raid")
    F.runUntil(function() return w.now > 125 end)
    check(F.count(p[1], "EuropaLevel", 2) == 1, "the first raid stirs the moon")
    F.runUntil(function() return w.now > 245 end)
    check(F.count(p[1], "EuropaLevel", 3) == 1 and F.count(p[1], "EuropaQuakeCall", 0.35) == 1, "the second raid: level 3 and a quake")
    F.runUntil(function() return w.now > 365 end)
    check(F.count(p[1], "EuropaPlume", 1) == 1, "the bombers open the vent next to the base")
    F.runUntil(function() return w.now > 485 end)
    check(F.count(p[1], "EuropaLevel", 4) == 1 and F.count(p[1], "EuropaSurgeCall", 5.0) == 1, "the walkers: level 4 and a surge")
    F.kill("shield_3"); F.run(2)
    check(F.count(p[1], "EuropaPlume", 6) == 1, "a lost generator pair opens a vent under the base")
    check(F.count(p[1], "EuropaCreated") > 0, "new objects are offered to the weather")
    F.kill("goal_1"); F.run(2)
    check(F.count(p[1], "EuropaPlume", 4) == 1, "goal_1 falling opens the geyser under it")
    F.kill("goal_3"); F.run(2)
    check(F.count(p[1], "EuropaPlume", 2) == 1, "goal_3 falling opens the geyser under it")
    F.runUntil(function() return w.now > 785 end, 2000)
    check(F.count(p[1], "EuropaSurgeCall", 6.0) == 1, "the portal opening surges the sky")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "EuropaShutdown") >= 1 and F.count(p[1], "EuropaLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(p[1], "WeatherSensors", "Ganymede") == 2, "the sensor modifier is bound again after a load")
    F.kill("goal_2"); F.kill("goal_4")
    w.audioBusy = true; F.run(3)
    check(F.count(p[1], "EuropaPlume", 3) == 1, "goal_2 falling opens the geyser under it")
    w.audioBusy = false
    F.runUntil(function() return m.won end, 80)
    F.run(3)
    check(F.count(p[1], "EuropaLevel", 2) == 2, "the victory eases the weather")
end
do -- an empty vent list is legal: plumes are skipped, everything else runs
    local sites = { vents = {} }
    local w, p, m = setup(2, { weather = { module = function(peer, record) return ganymede(record, nil, sites)(peer) end, sites = sites } })
    finishIntro(w)
    F.runUntil(function() return w.now > 370 end)
    check(F.count(p[1], "EuropaPlume") == 0 and F.count(p[1], "EuropaLevel", 3) == 1, "no vents, no plumes")
end
do -- sites module missing: no weather, never an error
    local sites = dofile("Scripts/CRGanymedeSitesBD12.lua")
    local w, p, m = setup(2, { weather = { module = function(peer, record) return ganymede(record, nil, sites)(peer) end } })
    check(F.count(p[1], "EuropaInit") == 0 and m.startDone, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local sites = dofile("Scripts/CRGanymedeSitesBD12.lua")
    local w, p, m = setup(2, { weather = { module = function(peer, record) return ganymede(record, mode, sites)(peer) end, sites = sites } })
    finishIntro(w)
    F.runUntil(function() return w.now > 125 end)
    check(#builtAt(p[1], "attack_1") == 3 + 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("bdmisn12 co-op: " .. checks .. " checks passed")
