-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/ch02cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/CoopCampaignTests/Test-Chmisn02Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/CoopCampaignTests/Chmisn02Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local SAFE = 300
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
-- The opening shot ends, then the 2 s pause: the objective is published and the clocks start.
local function startMission(w)
    w.cameraDone["camera_start"] = true; F.run(3)
end
local function killLive(m)
    for _, h in ipairs(m.crcca and m.crcca.live or {}) do if F.alive(h) then F.kill(h) end end
end
local function killAuthored(prefix, count)
    for i = 1, count do F.kill(prefix .. i) end
end
-- attack_5 destroyed: the big raid leaves 60 s later.
local function reachRaid(w, m)
    startMission(w)
    killAuthored("attack_5_", 5); F.run(63)
end
-- the defecting walker 240 s after the raid
local function reachWalker(w, m)
    reachRaid(w, m)
    F.run(240)
end
-- attack_8 300 s after the walker, the convoy 270 s after that
local function reachConvoy(w, m)
    reachWalker(w, m)
    F.run(300); F.run(272)
end
local function scaled(peer, mark)
    local out = {}
    for _, b in ipairs(F.builds(peer, mark or 0)) do
        if b.odf:sub(1, 2) == "sv" and b.team == 5 then out[#out + 1] = b end
    end
    return out
end
local function at(builds, where)
    local out = {}
    for _, b in ipairs(builds) do if b.where == where then out[#out + 1] = b end end
    return out
end
local function allSafe(p, builds)
    for _, b in ipairs(builds) do
        for _, q in ipairs(p) do
            check(q.env.GetDistance(q.player, b.h) >= SAFE, "no scripted unit is built within " .. SAFE .. " m of any human")
        end
    end
end
local function heardAll(p, file, count)
    for i, q in ipairs(p) do check(F.heardCount(q, file) == (count or 1), "peer " .. i .. " hears " .. file .. " x" .. (count or 1)) end
end
local function guestsPassive(p)
    for i = 2, #p do
        for _, name in ipairs({"BuildObject", "SetScrap", "SetAIP", "Goto", "Attack", "Hunt", "Retreat", "Defend2", "SetPerceivedTeam",
            "SetCommand", "SetTeamNum"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on the authored enemy team 2") end
end
local function orderCount(peer, name, target)
    local n = 0
    for _, c in ipairs(F.callsOf(peer, name)) do if c[3] == target then n = n + 1 end end
    return n
end

-- ------------------------------------------------------------------ offline == faithful
local function outcomes(options, scenario)
    local w, p, m = setup(1, options)
    scenario(w, p, m)
    local out = {}
    for _, name in ipairs({"SucceedMission", "FailMission"}) do
        for _, c in ipairs(F.callsOf(p[1], name)) do out[#out + 1] = name .. ":" .. tostring(c[2]) .. ":" .. tostring(c[3]) end
    end
    return table.concat(out, ","), p[1], w
end
local scenarios = {
    win = function(w, p, m)
        reachConvoy(w, m); F.nearTo(m.apc[1], "hanger", 10, 0); F.run(20)
    end,
    hangarLost = function(w, p, m) startMission(w); F.run(5); F.kill("hanger"); F.run(20) end,
    apcsLost = function(w, p, m) reachConvoy(w, m); F.kill(m.apc[0]); F.kill(m.apc[2]); F.run(20) end,
}
for name, scenario in pairs(scenarios) do
    local faithful = outcomes({ faithful = true, script = "Scripts/ch02.lua" }, scenario)
    local offline = outcomes({}, scenario)
    check(faithful == offline and faithful ~= "", "offline completes like the faithful port (" .. name .. "): " .. faithful .. " / " .. offline)
end
do
    local out, peer = outcomes({}, scenarios.win)
    check(out:match("^SucceedMission:[%d%.]+:ch02win%.des$") and F.count(peer, "SucceedMission") == 1, "offline victory: " .. out)
    check(F.count(peer, "StartCockpitTimer", 30) == 1, "offline: the 30 s timer shows once")
    noEnemyTeamTwo(peer)
    check(outcomes({}, scenarios.hangarLost):match("FailMission:[%d%.]+:ch02lsea%.des"), "offline hangar loss")
    check(outcomes({}, scenarios.apcsLost):match("ch02lseb%.des"), "offline: two APCs lost")
    -- the defector's loss: the faithful port fails at once and silently; the CR layer plays the restored reproach first
    local walkerLost = function(w, p, m) reachWalker(w, m); F.run(2); F.kill(m.walker); F.run(20) end
    local faithful = outcomes({ faithful = true, script = "Scripts/ch02.lua" }, walkerLost)
    local offline, offlinePeer = outcomes({}, walkerLost)
    check(faithful:match("^FailMission:[%d%.]+:ch02lsec%.des$") and offline:match("^FailMission:[%d%.]+:ch02lsec%.des$"), "both fail with ch02lsec")
    check(tonumber(offline:match("^FailMission:([%d%.]+)")) - tonumber(faithful:match("^FailMission:([%d%.]+)")) == 7,
        "the restored reproach delays the offline debrief by exactly 7 s")
    check(F.heard(offlinePeer, "ch04005.wav"), "offline: the unused ch04005 plays when the defector dies")
end
do -- offline the layer adds nothing visible
    local w, p, m = setup(1, {})
    check(F.count(p[1], "SetAIControl", 5) == 1 and F.count(p[1], "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
    check(m.user == "crcca_players", "the body's player is the runtime token even offline")
end

-- ------------------------------------------------------------------ teams, ownership, humans as the player
for n = 2, 4 do
    local w, p, m = setup(n, {})
    F.run(2)
    check(m.startDone and m.coopMissionStarted, "leader starts the shared mission")
    check(F.count(p[1], "SetAIControl", 5) == 1 and F.count(p[1], "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
    check(F.index(p[1], "SetAIControl") <= p[1].chunkCalls, "SetAIControl runs at chunk root, before Start")
    check(F.count(p[1], "SetAIP") == 0, "this mission has no AIP")
    check(F.count(p[1], "SetScrap") == 1 and F.last(p[1], "SetScrap")[2] == 1 and F.last(p[1], "SetScrap")[3] == 30 + 10 * (n - 1),
        "shared scrap on team 1 with the guest bonus")
    check(F.count(p[1], "SetPilot") == n, "pilots set once per human team")
    for team = 1, n do
        local found = false
        for _, c in ipairs(F.callsOf(p[1], "SetPilot")) do if c[2] == team and c[3] == 10 then found = true end end
        check(found, "team " .. team .. " gets 10 pilots")
    end
    for i = 1, n do
        check(F.count(p[i], "EnableAllCloaking", false) == 1, "cloaking is disabled once on peer " .. i)
        check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
        check(F.heardCount(p[i], "ch02001.wav") == 1, "briefing once on peer " .. i)
    end
    check(p[1].rally and p[1].rally[0] == "recycler", "respawn rally point is the shared recycler")
    guestsPassive(p)
end

-- ------------------------------------------------------------------ the opening shot is shared; skippable only offline
do
    local w, p, m = setup(3, { busy = true })
    for i = 1, 3 do
        local c = F.last(p[i], "CameraPath")
        check(p[i].camera == 1 and c[2] == "camera_start" and c[3] == 800 and c[4] == 2000 and c[5] == "hanger",
            "the opening shot is the same on peer " .. i)
    end
    w.cancel = true; F.run(1)
    check(not m.cameraComplete[0], "a skip never ends the shared opening in a network game")
    w.cancel = false
    -- the host's own camera was released, so its native path never arrives: the shot ends at its flight time
    F.run(17)
    check(not m.cameraArrived and not m.cameraComplete[0], "the shared opening still runs for its 16.6 s flight")
    F.run(6)
    check(m.cameraArrived and not m.cameraComplete[0], "the opening arrives at its flight time after a skip")
    F.run(3)
    check(m.cameraComplete[0] and m.sound2Time < 1e9, "...and completes after the 2 s pause")
    for i = 1, 3 do check(p[i].camera == 0, "opening cameras balanced on peer " .. i) end
    local objectives = F.callsOf(p[2], "AddObjective")
    check(#objectives == 1 and objectives[1][2] == "ch02001.otf", "the objective reaches the guests once the shot ends")
end
do -- no skip: the shot ends when the native path arrives
    local w, p, m = setup(3, {})
    F.run(5)
    check(not m.cameraArrived, "still flying")
    w.cameraDone["camera_start"] = true; F.run(1)
    check(m.cameraArrived and not m.cameraComplete[0], "the shot arrives, the 2 s pause begins")
    F.run(3)
    check(m.cameraComplete[0], "the opening ends")
    for i = 1, 3 do check(p[i].camera == 0, "opening cameras balanced on peer " .. i) end
end
do -- offline: skippable
    local w, p, m = setup(1, { busy = true })
    F.run(2)
    check(p[1].camera == 1 and m.openingSound ~= nil, "offline opening opens and talks")
    w.cancel = true; F.run(1)
    check(m.cameraComplete[0] and p[1].camera == 0 and F.count(p[1], "StopAudioMessage") == 1, "offline skip ends the opening")
    w.cancel = false; F.run(5)
    check(F.count(p[1], "CameraReady") == 1, "a skipped opening never restarts")
end

-- ------------------------------------------------------------------ the siege: annoy raids, attack_3, the post-attack_5 raid
for n = 1, 4 do
    local e = extrasFor(n)
    local w, p, m = setup(n, {})
    startMission(w)
    heardAll(p, "ch02001.wav")
    F.run(62)
    heardAll(p, "ch02002.wav")
    F.run(60)
    local annoy = at(scaled(p[1]), "annoy_1")
    check(#annoy == 4 + e, n .. " human(s): the annoy raid is 4 + " .. e .. " extras, got " .. #annoy)
    allSafe(p, annoy)
    check(F.count(p[1], "Hunt") == 4 + e, "every raider hunts, extras included")
    killLive(m)
    -- attack_3 destroyed: an artillery tank goes for the hangar
    killAuthored("attack_3_", 5); F.run(1)
    local art = at(scaled(p[1]), "hanger_attack_2")
    check(m.attack3Destroyed and #art == 1 + e, "attack_3 destroyed releases one artillery tank + extras")
    check(orderCount(p[1], "Attack", "hanger") >= 1, "...which attacks the hangar")
    -- attack_5 destroyed: 60 s later the big raid
    killLive(m)
    local mark = #p[1].calls
    killAuthored("attack_5_", 5); F.run(30)
    check(#scaled(p[1], mark) == 0, "the raid waits 60 s")
    F.run(34)
    local raid = scaled(p[1], mark)
    check(#at(raid, "attack_6") == 9 + e and #at(raid, "attack_7") == 9 + e and #at(raid, "hanger_attack_3") == 2 + e,
        n .. " human(s): the raid is 9+9+2 plus " .. e .. " extras per event")
    allSafe(p, raid)
    check(orderCount(p[1], "Goto", "attack_6_path") == 9 + e, "the attack_6 column follows its path, extras included")
    for _, b in ipairs(at(raid, "hanger_attack_3")) do check(b.odf == "svhraz", "the hanger_attack_3 units are heavy razors") end
    check(m.walkerTime < 1e9, "the walker clock starts")
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end
do -- artillery spawn points inside 300 m of a human come from a hidden approach
    local w, p, m = setup(2, {})
    reachWalker(w, m)
    killLive(m)
    local mark = #p[1].calls
    F.run(11)
    local art = at(scaled(p[1], mark), "hanger_attack_5")
    check(#art == 1 + 1, "the hanger_attack_5 artillery (339 m from the spawn buoys) is built where it is, with its extra")
    allSafe(p, scaled(p[1], mark))
end

-- ------------------------------------------------------------------ the defecting walker
for n = 1, 3 do
    local e = extrasFor(n)
    local w, p, m = setup(n, {})
    reachRaid(w, m)
    local before = #p[1].calls
    F.run(240)
    local walkers = F.builds(p[1], before, "svwalk")
    local walker = at(walkers, "walker_spawn")
    check(#walker == 1 and walker[1].team == 0 and m.walker == walker[1].h, n .. " human(s): the defector is one direct neutral build")
    check(F.team(m.walker) == 0 or F.team(m.walker) == 1, "built on team 0")
    check(F.count(p[1], "SetPerceivedTeam", m.walker) == 1 and orderCount(p[1], "Retreat", "walker_path") == 1, "perceived team 1, retreating along its path")
    for i = 1, n do
        check(F.count(p[i], "SetObjectiveOn", m.walker) == 1, "the defector is marked on peer " .. i)
        check(F.heardCount(p[i], "ch02007.wav") == 1, "the defector line plays on peer " .. i)
        local last = F.callsOf(p[i], "AddObjective")
        check(last[#last][2] == "ch02003.otf" and last[#last - 1][2] == "ch02001.otf", "both objectives on peer " .. i)
    end
    -- the cut ambush (walker_attack_1) and the live ambushes
    killLive(m)
    local mark = #p[1].calls
    F.nearTo(m.walker, "walker_attack_1", 100, 0); F.run(6)
    local a1 = at(scaled(p[1], mark), "walker_attack_1")
    check(m.walkerAttack1 and #a1 == 2 + e, n .. " human(s): the restored walker_attack_1 ambush is two fighters + " .. e .. " extras: " .. #a1)
    for _, b in ipairs(a1) do check(b.odf == "svfigh", "ambushers are fighters") end
    check(orderCount(p[1], "Attack", m.walker) >= 2 + e, "they attack the walker")
    killLive(m)
    mark = #p[1].calls
    F.nearTo(m.walker, "walker_attack_2", 50, 0); F.run(6)
    check(#at(scaled(p[1], mark), "walker_attack_2") == 6 + e, "walker_attack_2 ambush: six + extras")
    killLive(m)
    mark = #p[1].calls
    F.nearTo(m.walker, "walker_attack_3", 50, 0); F.run(6)
    local a3 = at(scaled(p[1], mark), "walker_attack_3")
    local razors = 0
    for _, b in ipairs(a3) do if b.odf == "svhraz" then razors = razors + 1 end end
    check(#a3 == 4 + e + 2 and razors == 2, "walker_attack_3 ambush: four + extras, plus the two restored razors, got " .. #a3)
    allSafe(p, a3)
    -- arrival: it joins the base and is recycled
    F.place(m.walker, 3080, 98922)
    local walkerHandle = m.walker
    F.run(2)
    check(m.walker == nil and F.team(walkerHandle) == 1 and F.count(p[1], "SetCommand", walkerHandle) == 1
        and F.last(p[1], "SetCommand")[3] == 18, "the walker joins team 1 and is recycled")
    heardAll(p, "ch02008.wav")
    check(F.count(p[1], "FailMission") == 0, "the walker arriving is not a loss")
    guestsPassive(p)
end

-- ------------------------------------------------------------------ the convoy
for n = 1, 4 do
    local e = extrasFor(n)
    local w, p, m = setup(n, {})
    reachWalker(w, m)
    killLive(m)
    F.run(300)
    killLive(m)
    local mark = #p[1].calls
    F.run(272)
    check(m.apcSpawned, "the convoy spawns")
    local apcs = F.builds(p[1], mark, "cvapcb")
    check(#apcs == 3 and apcs[1].team == 1 and apcs[1].where == "convoy_units", n .. " human(s): three APCs, direct, on team 1")
    check(#F.builds(p[1], mark, "cvfighc") == 6 and orderCount(p[1], "Defend2", m.apc[0]) == 2, "six escorts, two per APC, none mirrored")
    for i = 1, 3 do
        local goes = 0
        for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[2] == m.apc[i - 1] and c[3] == "convoy_path" then goes = goes + 1 end end
        check(goes == 1, "APC " .. i .. " follows the convoy path")
    end
    heardAll(p, "ch02003.wav")
    -- the first attacks, 60 s later
    killLive(m)
    mark = #p[1].calls
    F.run(62)
    local attackers = scaled(p[1], mark)
    check(#at(attackers, "convoy_attack_1") == 4 + e, "four fighters on convoy_attack_1 + extras")
    for w9 = 2, 9 do check(#at(attackers, "convoy_attack_" .. w9) >= 1, "convoy_attack_" .. w9 .. " is built (maybe from a fallback approach)") end
    local onConvoy = 0
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do
        for i = 0, 2 do if c[3] == m.apc[i] and c[4] == 1 then onConvoy = onConvoy + 1 end end
    end
    check(onConvoy >= 12, "the attackers go for the live APCs: " .. onConvoy)
    allSafe(p, attackers)
    -- the first hit
    F.hurt(m.apc[1]); F.run(1)
    check(m.apcDamaged, "damage is noticed")
    heardAll(p, "ch02004.wav")
    local nav = F.builds(p[1], mark, "cpcamr")
    check(#nav == 1 and nav[1].team == 1, "the intercept nav is built once on team 1")
    for i = 1, n do check(F.count(p[i], "SetObjectiveName", nav[1].h) == 1 and F.last(p[i], "SetObjectiveName")[3] == "Convoy Intercept", "the nav is named on peer " .. i) end
    -- triggers
    killLive(m)
    mark = #p[1].calls
    F.nearTo(m.apc[2], "trigger_point_1", 10, 0); F.run(6)
    local t1 = scaled(p[1], mark)
    check(m.apcTrigger1 and #at(t1, "convoy_attack_10") == 6 + e and #at(t1, "hanger_attack_3") == 3 + e, "trigger 1: six fighters and three razors, each event with its extras")
    killLive(m)
    mark = #p[1].calls
    F.nearTo(m.apc[2], "trigger_point_2", 10, 0); F.run(6)
    local t2 = scaled(p[1], mark)
    check(m.apcTrigger2 and #at(t2, "attack_9") == 6 + e and #at(t2, "attack_10") == 6 + e and #at(t2, "hanger_attack_4") == 3 + e,
        "trigger 2: attack_9, attack_10 and the razors")
    -- the restored attack_9 route: the column walks its authored path instead of heading for a building
    check(orderCount(p[1], "Goto", "attack_9_path") == 6 + e, "attack_9 takes attack_9_path, extras included")
    local toBase = 0
    for _, b in ipairs(at(t2, "attack_10")) do
        for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[2] == b.h and type(c[3]) == "string" and F.LABELS[c[3]] then toBase = toBase + 1 end end
    end
    check(toBase == 6 + e, "attack_10 still goes for a base building")
    allSafe(p, t2)
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end
do -- a missing attack_9_path or ambush path degrades to the source behaviour
    local w, p, m = setup(2, {})
    w.missingPaths = { attack_9_path = true, walker_attack_1 = true, walker_attack_3 = true }
    reachConvoy(w, m)
    F.nearTo(m.apc[0], "trigger_point_2", 10, 0); F.run(6)
    check(orderCount(p[1], "Goto", "attack_9_path") == 0, "no attack_9_path on the map: the units go for the base")
    check(not m.walkerAttack1, "no walker_attack_1 on the map: nothing is restored")
end

-- ------------------------------------------------------------------ victory and defeat
for n = 1, 4 do
    local w, p, m = setup(n, {})
    reachConvoy(w, m)
    F.nearTo(m.apc[1], "hanger", 10, 0); F.run(2)
    check(m.won and m.apcAtHangar, "an APC at the hangar wins")
    for i = 1, n do
        check(F.count(p[i], "StartCockpitTimer", 30) == 1, "the 30 s display shows on peer " .. i)
        check(F.heardCount(p[i], "ch02005.wav") == 1, "the victory line plays on peer " .. i)
    end
    F.run(14)
    local before = #F.builds(p[1])
    F.run(260)
    check(#F.builds(p[1]) == before, "no reinforcement is built once the mission is won")
    for i = 1, n do
        check(F.count(p[i], "SucceedMission") == 1 and F.count(p[i], "FailMission") == 0, "one shared victory on peer " .. i)
        check(F.last(p[i], "SucceedMission")[3] == "ch02win.des", "victory debrief on peer " .. i)
        check((p[i].env.Save().coopUnresolved or 0) == 0, "no unresolved presentation identities on peer " .. i)
    end
    F.kill("hanger"); F.run(10)
    check(F.count(p[1], "FailMission") == 0, "a won mission cannot be lost")
    guestsPassive(p)
end
do -- the hangar falls: the line plays, one shared failure, no victory
    local w, p, m = setup(3, {})
    reachConvoy(w, m)
    F.kill("hanger"); F.run(3)
    heardAll(p, "ch02006.wav")
    F.run(14)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "ch02lsea.des", "one shared failure on peer " .. i)
        check(F.count(p[i], "SucceedMission") == 0, "no victory after a loss")
    end
    F.nearTo(m.apc[0], "recycler", 10, 0); F.run(10)
    check(F.count(p[1], "SucceedMission") == 0 and not m.won, "a failed mission cannot be won")
    local before = #F.builds(p[1])
    F.run(130)
    check(#F.builds(p[1]) == before, "no reinforcement is built after the failure")
end
do -- two APCs lost: ch02006 then the unused ch03007 close the loss
    local w, p, m = setup(2, {})
    reachConvoy(w, m)
    F.hurt(m.apc[0]); F.run(2) -- the first hit has been announced long before two APCs fall
    w.busyMessages["audio:" .. "ch02006.wav"] = true
    w.busyMessages["audio:" .. "ch03007.wav"] = true
    F.kill(m.apc[0]); F.kill(m.apc[1]); F.run(1)
    heardAll(p, "ch02006.wav"); heardAll(p, "ch03007.wav")
    local queued = false
    for _, c in ipairs(F.callsOf(p[1], "Queue")) do if c[2] == "ch03007.wav" then queued = true end end
    check(queued, "ch03007 is queued behind ch02006")
    F.run(8)
    check(F.count(p[1], "FailMission") == 0, "the failure waits for both lines")
    w.busyMessages["audio:" .. "ch02006.wav"] = nil
    F.run(8)
    check(F.count(p[1], "FailMission") == 0, "...and for the second line after the first is done")
    w.busyMessages["audio:" .. "ch03007.wav"] = nil
    F.run(14)
    for i = 1, 2 do check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "ch02lseb.des", "convoy failure on peer " .. i) end
    check(F.heardCount(p[1], "ch03007.wav") == 1, "the extra line plays once")
end
do -- the defector dies: ch04005, then the debrief a few seconds later
    local w, p, m = setup(3, {})
    reachWalker(w, m); F.run(2)
    local dead = w.now
    F.kill(m.walker); F.run(1)
    heardAll(p, "ch04005.wav")
    F.run(14)
    for i = 1, 3 do
        local fail = F.last(p[i], "FailMission")
        check(F.count(p[i], "FailMission") == 1 and fail[3] == "ch02lsec.des" and fail[2] >= dead + 7, "the walker's loss is shared and waits for the line on peer " .. i)
    end
end
do -- one APC lost is not a defeat; a hangar loss during the victory line is not a victory
    local w, p, m = setup(2, {})
    reachConvoy(w, m)
    F.kill(m.apc[0]); F.run(4)
    check(not m.lost, "one APC lost does not fail the mission")
    F.nearTo(m.apc[1], "hanger", 10, 0); F.run(1)
    check(m.won, "the second APC still wins")
end

-- ------------------------------------------------------------------ nothing within 300 m: a watched approach defers the raid
do
    local w, p, m = setup(4, {})
    startMission(w)
    local saved = {}
    local names = { "attack_6", "attack_7", "hanger_attack_3", "attack_8", "attack_10", "attack_9", "hanger_attack_4", "convoy_attack_10" }
    F.place(p[2].player, 4000, 98000)
    for _, name in ipairs(names) do
        saved[name] = w.pathPos[name]
        w.pathPos[name] = { x = 4000, y = saved[name].y, z = 98000 }
    end
    killAuthored("attack_5_", 5)
    F.run(66)
    check(#scaled(p[1]) == 0 and m.attack5Destroyed, "a fully watched map defers the raid")
    check(m.crcca.serial > 0, "the requests wait in the saved state")
    local pending = m.crcca.serial
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(m.crcca.serial == pending and #scaled(p[1]) == 0, "save/load keeps the pending raid without duplicating it")
    for _, name in ipairs(names) do w.pathPos[name] = saved[name] end
    F.place(p[2].player, 20000, 20000)
    F.run(8)
    check(#scaled(p[1]) == 20 + 3 * 2, "the whole raid is built exactly once when the watcher leaves, got " .. #scaled(p[1]))
end

-- ------------------------------------------------------------------ loads
do -- a load during the opening ends the shot without a second opening
    local w, p, m = setup(3, { busy = true })
    F.run(3)
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(4)
    check(m.cameraComplete[0] and F.count(p[1], "CameraReady") == 1, "a load in the opening ends the shot without a second opening")
    for i = 1, 3 do check(p[i].camera == 0, "camera balanced after the load on peer " .. i) end
end
do -- a load restores the objective list and the markers the runtime dropped
    local w, p, m = setup(2, {})
    reachWalker(w, m)
    local before = F.count(p[2], "AddObjective")
    local marks = F.count(p[2], "SetObjectiveOn", m.walker)
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    local last = F.callsOf(p[2], "AddObjective")
    check(F.count(p[2], "AddObjective") == before + 2 and last[#last][2] == "ch02003.otf", "the load publishes both objectives again")
    check(F.count(p[2], "SetObjectiveOn", m.walker) == marks + 1, "...and marks the walker again")
end

-- ------------------------------------------------------------------ leader leaves
do
    local w, p, m = setup(3, {})
    for i = 2, 3 do p[i].env.DeletePlayer(1) end
    F.run(3)
    for i = 2, 3 do check(F.count(p[i], "FailMission") == 1, "the mission fails for guest " .. i .. " when the leader leaves") end
    check(F.count(p[1], "FailMission") == 0, "the leader itself keeps playing")
end

-- ------------------------------------------------------------------ weather: Ganymede
do
    local w, p, m = setup(3, {})
    check(F.count(p[1], "EnvironmentInit") == 0 and m.startDone, "no weather module: the mission runs and touches no Environment")
    local printed = false
    for _, c in ipairs(p[1].calls) do if c[1] == "print" and tostring(c[2]):find("weather disabled", 1, true) then printed = true end end
    check(printed, "missing weather is logged, not fatal")
end
local function europa(record, mode, vents)
    return function(peer)
        local V = { Seed = 4242 }
        function V.Init(o) peer.weatherInit = o; record("EuropaInit", o.authority, o.send ~= nil, o.seed, o.startLevel, o.targetLevel); if mode == "initfail" then error("boom") end end
        function V.Update(dt)
            if peer.weatherInit and peer.weatherInit.authority and peer.weatherInit.send and not V.sent then
                V.sent = true; peer.weatherInit.send("EuropaQuake", 3, 4)
            end
            if mode == "updatefail" then error("update boom") end
        end
        function V.AnnounceState() record("EuropaAnnounce") end
        function V.ApplyNetEvent(op, ...) record("EuropaEvent", op, ...) end
        function V.SetTargetLevel(n) record("EuropaLevel", n) end
        function V.ReleaseForcedLevel() record("EuropaRelease") end
        function V.GetVentSites() return vents end
        function V.TriggerPlume(i) record("EuropaPlume", i) end
        function V.Quake(a, b) record("EuropaQuakeCall", a, b) end
        function V.Surge(a, b) record("EuropaSurgeCall", a, b) end
        function V.OnObjectCreated(h) record("EuropaCreated", h) end
        function V.Save() return { saved = true } end
        function V.Load(s) record("EuropaLoad", s and s.saved) end
        function V.Shutdown() record("EuropaShutdown") end
        return V
    end
end
do
    local sites = dofile("Scripts/CRGanymedeSitesCH02.lua")
    check(sites.mission == "chmisn02" and #sites.vents >= 5 and sites.vents[1].label == "eggeizr12_geyser", "the generated sites carry the base geyser first")
    local weather = { module = function(peer, record) return europa(record, nil, sites.vents)(peer) end, sites = sites }
    local w, p, m = setup(3, { weather = weather })
    check(F.count(p[1], "EuropaInit", true) == 1 and F.last(p[1], "EuropaInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.last(p[1], "EuropaInit")[5] == 1 and F.last(p[1], "EuropaInit")[6] == 1, "the sky starts quiescent")
    check(F.count(p[2], "EuropaInit", false) == 1, "guests render only (not the authority)")
    check(F.count(p[1], "EuropaAnnounce") == 1 and F.count(p[2], "EuropaAnnounce") == 0, "the leader announces its weather state once")
    local env = F.last(p[1], "EnvironmentInit")[2]
    check(F.count(p[1], "EnvironmentInit") == 1 and env.lightingMode == "orbit", "Ganymede lighting is initialised")
    for i = 2, 3 do
        local e = F.last(p[i], "EuropaEvent")
        check(e and e[2] == "EuropaQuake" and e[3] == 3 and e[4] == 4, "weather events reach guest " .. i)
    end
    check(m.crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    check(F.count(p[1], "EuropaLevel") == 0, "calm until the story starts")
    startMission(w)
    F.run(62)
    check(F.count(p[1], "EuropaLevel", 2) == 1, "'Incoming CCA forces' stirs the vapour")
    check(F.count(p[1], "EuropaPlume") == 0, "no plume before the raid")
    killAuthored("attack_3_", 5); F.run(1)
    check(F.count(p[1], "EuropaQuakeCall") == 1, "the broken column shakes the ice")
    killAuthored("attack_5_", 5); F.run(63)
    check(F.count(p[1], "EuropaLevel", 3) == 1 and F.count(p[1], "EuropaPlume", 1) == 1, "the raid raises the weather and blows the base vent")
    check(F.count(p[1], "EuropaQuakeCall") == 2 and F.count(p[1], "EuropaSurgeCall") == 1, "...with a quake and a surge")
    F.run(240)
    check(F.count(p[1], "EuropaPlume", 5) == 1 and F.count(p[1], "EuropaQuakeCall") == 3, "the walker's arrival opens the western vent")
    F.run(300); F.run(272)
    check(F.count(p[1], "EuropaLevel", 4) == 1 and F.count(p[1], "EuropaSurgeCall") == 2, "the convoy brings the heaviest rung")
    check(F.count(p[1], "EuropaCreated") > 0, "new objects are offered to the weather")
    F.hurt(m.apc[0]); F.run(1)
    check(F.count(p[1], "EuropaPlume", 2) == 1, "the first hit opens a vent")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "EuropaShutdown") >= 1 and F.count(p[1], "EuropaLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(p[1], "EuropaPlume", 1) == 1 and F.count(p[1], "EuropaLevel", 3) == 1, "beats are not repeated after a load")
    F.nearTo(m.apc[1], "hanger", 10, 0); F.run(3)
    check(F.count(p[1], "EuropaRelease") == 1 and F.count(p[1], "EuropaLevel", 1) == 1, "the arrival eases the sky back")
end
do -- a site list without vents: the plume is skipped, the rest of the weather still follows
    local weather = { module = function(peer, record) return europa(record, nil, {})(peer) end, sites = { mission = "chmisn02", vents = {} } }
    local w, p, m = setup(2, { weather = weather })
    reachRaid(w, m)
    check(F.count(p[1], "EuropaPlume") == 0 and F.count(p[1], "EuropaLevel", 3) == 1 and F.count(p[1], "EuropaQuakeCall") == 1,
        "no vents: no plume, the level and the quake still follow")
end
do -- sites module missing: no weather, never an error
    local w, p, m = setup(2, { weather = { module = function(peer, record) return europa(record, nil, {})(peer) end } })
    check(F.count(p[1], "EuropaInit") == 0 and m.startDone, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local weather = { module = function(peer, record) return europa(record, mode, {})(peer) end, sites = {} }
    local w, p, m = setup(2, { weather = weather })
    reachConvoy(w, m); F.nearTo(m.apc[1], "hanger", 10, 0); F.run(22)
    check(F.count(p[1], "SucceedMission") == 1 and F.count(p[2], "SucceedMission") == 1, "a failing weather director (" .. mode .. ") never stops the mission")
end
do -- a silent audio service (no handle) never wedges the loss gates
    local w, p, m = setup(2, { nilAudio = true })
    startMission(w); F.run(5)
    F.kill("hanger"); F.run(15)
    check(F.count(p[1], "FailMission") == 1 and F.last(p[1], "FailMission")[3] == "ch02lsea.des", "the loss completes without an audio handle")
end

print("chmisn02 co-op: " .. checks .. " checks passed")
