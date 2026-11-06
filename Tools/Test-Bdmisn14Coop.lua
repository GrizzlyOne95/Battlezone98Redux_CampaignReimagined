-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/bd14cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/Test-Bdmisn14Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Bdmisn14Fixture.lua")
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
local function builtAt(peer, where, odf)
    local out = {}
    for _, b in ipairs(F.builds(peer, 0, odf)) do
        if b.where == where then out[#out + 1] = b end
    end
    return out
end
local function guestsPassive(p)
    for i = 2, #p do
        for _, name in ipairs({"BuildObject", "SetScrap", "SetPilot", "SetAIP", "Goto", "Follow", "Defend2", "SetCloaked"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on the authored enemy team 2") end
end
-- Every Chinese craft the script built dies, so the live cap never bites a long scenario.
local function reap()
    for h, o in pairs(F.world().objects) do if o.alive and h:match("^built") and o.team == 5 then o.alive = false end end
end
-- Stand a human 140 m from a trigger point (inside its 150 m, outside the 120 m concealment ring of the spawns).
local function atTrigger1(peer) F.nearTo(peer.player, "trigger_attack_1", 0, -140) end
local function atTrigger2(peer) F.nearTo(peer.player, "trigger_attack_2", 0, 140) end
-- Run until just after the APC convoy is built (541 s) with the earlier waves reaped.
local function toApc(w)
    F.run(539)
    reap()
    F.run(6)
end
local function lastObjectives(peer)
    -- the objectives of the last ClearObjectives..AddObjective sequence
    local list, started = {}, false
    for i = #peer.calls, 1, -1 do
        local c = peer.calls[i]
        if c[1] == "AddObjective" then list[#list + 1] = c[2] .. ":" .. c[3]; started = true
        elseif c[1] == "ClearObjectives" and started then break end
    end
    local out = {}
    for i = #list, 1, -1 do out[#out + 1] = list[i] end
    return table.concat(out, ",")
end

-- ------------------------------------------------------------------ offline == faithful
local function summary(peer)
    local items = {}
    for _, c in ipairs(peer.calls) do
        if c[1] == "BuildObject" then
            items[#items + 1] = "B:" .. c[3] .. ":" .. (c[4] == 2 and 5 or c[4]) .. ":" .. tostring(c[5])
        elseif c[1] == "Goto" then
            if c[3] ~= "path_turrets" then items[#items + 1] = "Goto:" .. tostring(c[3]) end
        elseif c[1] == "SucceedMission" or c[1] == "FailMission" then
            items[#items + 1] = c[1] .. ":" .. tostring(c[3])
        elseif c[1] == "Follow" or c[1] == "Defend2" or c[1] == "SetCloaked" or c[1] == "SetObjectiveOn"
            or c[1] == "SetObjectiveOff" then
            items[#items + 1] = c[1]
        end
    end
    -- the restored turret convoy is the one CR addition to the sequence
    local kept = {}
    for _, item in ipairs(items) do
        if item ~= "B:cvturr:5:spawn_turrets" then kept[#kept + 1] = item end
    end
    table.sort(kept)
    local lines = {}
    for _, c in ipairs(peer.calls) do
        if c[1] == "AudioMessage" or c[1] == "Play" then lines[#lines + 1] = c[2] end
    end
    local aip, scrap, pilot = {}, {}, {}
    for _, c in ipairs(peer.calls) do
        if c[1] == "SetAIP" then aip[#aip + 1] = c[2] end
        if c[1] == "SetScrap" then scrap[#scrap + 1] = (c[2] == 2 and 5 or c[2]) .. "=" .. c[3] end
        if c[1] == "SetPilot" then pilot[#pilot + 1] = (c[2] == 2 and 5 or c[2]) .. "=" .. c[3] end
    end
    return table.concat(kept, ",") .. "|" .. table.concat(lines, ",") .. "|" .. table.concat(aip, ",") ..
        "|" .. table.concat(scrap, ",") .. "|" .. table.concat(pilot, ",")
end
local function fullRun(options)
    local w = F.reset()
    local peer = F.makePeer(1, 1, false, options)
    F.connect(); F.run(1)
    atTrigger1(peer); F.run(3) -- the base ambush
    atTrigger2(peer); F.run(3) -- the second ambush
    F.nearTo(peer.player, "recycler", 0, 0)
    F.run(540)
    F.run(65) -- past the fifty second warning, which the CR layer only drops for a dead APC
    local apc = peer.env.Save().apc
    F.kill(apc)
    F.run(250) -- the scavengers
    F.kill("chin_recycler")
    F.run(30)
    return summary(peer), peer
end
do
    local faithful = fullRun({ faithful = true, script = "Scripts/bdmisn14.lua" })
    local offline, peer = fullRun({})
    check(faithful == offline and faithful:find("SucceedMission:bd14win.des", 1, true),
        "offline completes like the faithful port:\n" .. faithful .. "\n" .. offline)
    check(F.count(peer, "SucceedMission") == 1 and F.count(peer, "FailMission") == 0, "one victory, no failure")
    noEnemyTeamTwo(peer)
    check(F.count(peer, "SetAIControl", 5) == 1 and F.count(peer, "SetAIControl", 2) == 0, "AI control only for enemy team 5")
    check(F.index(peer, "SetAIControl") <= peer.chunkCalls, "SetAIControl runs at chunk root, before Start")
end

-- the single-player body drops the late bd14004 itself once the APC is down
do
    local w = F.reset()
    local peer = F.makePeer(1, 1, false, { faithful = true, script = "Scripts/bdmisn14.lua" })
    F.connect(); F.run(1)
    toApc(w)
    F.kill(peer.env.Save().apc)
    F.run(60)
    local played = 0
    for _, c in ipairs(peer.calls) do if c[1] == "AudioMessage" and c[2] == "bd14004.wav" then played = played + 1 end end
    check(played == 0, "the faithful port never plays bd14004 after the APC is down")
end

-- ------------------------------------------------------------------ teams, scrap, pilots, the opening
do
    local w, p, m = setup(4, {})
    F.run(3) -- the guests receive the stream
    check(m.startDone and m.coopMissionStarted, "the leader starts the shared mission")
    check(F.count(p[1], "SetAIP") == 1 and F.callsOf(p[1], "SetAIP")[1][2] == "bdmisn14.aip" and F.callsOf(p[1], "SetAIP")[1][3] == 5,
        "the strategic AI belongs to the co-op enemy team 5")
    check(F.count(p[1], "SetScrap", 1) == 1 and F.callsOf(p[1], "SetScrap")[1][3] == 4 + 10 * 3, "starting scrap: 4 plus 10 per guest")
    check(F.count(p[1], "SetScrap", 5) == 1 and F.callsOf(p[1], "SetScrap")[2][3] == 0, "the enemy's scrap is team 5, not team 2")
    check(F.count(p[1], "SetScrap", 2) == 0, "no scrap is set on a guest's team 2")
    for team = 1, 4 do
        local n = 0
        for _, c in ipairs(F.callsOf(p[1], "SetPilot")) do if c[2] == team and c[3] == 10 then n = n + 1 end end
        check(n == 1, "10 pilots for human team " .. team)
    end
    local enemyPilots, humanHundred = 0, 0
    for _, c in ipairs(F.callsOf(p[1], "SetPilot")) do
        if c[2] == 5 and c[3] == 100 then enemyPilots = enemyPilots + 1 end
        if c[2] <= 4 and c[3] == 100 then humanHundred = humanHundred + 1 end
    end
    check(enemyPilots == 1 and humanHundred == 0, "the Chinese 100 pilots go to team 5, never to human team 2")
    for i = 1, 4 do
        check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
        check(F.heardCount(p[i], "bd14001.wav") == 1, "briefing once on peer " .. i)
    end
    local authored = {}
    for _, c in ipairs(F.callsOf(p[1], "SetCloaked")) do authored[c[2]] = true end
    for _, label in ipairs({"start1_1", "start1_2", "start1_3", "start2_1", "start2_2", "start2_3"}) do
        check(authored[label], "the authored raider is cloaked: " .. label)
    end
    check(p[1].rally ~= nil and p[1].rally[0] == "recycler", "respawns at the Black Dog base")
    guestsPassive(p)
    -- the first raid: five craft (+ extras), cloaked, on the initial route, and the first objective on every peer
    local e = extrasFor(4)
    check(#builtAt(p[1], "spawn_initial_attack") == 4 + e, "the initial raid: four craft plus " .. e .. " extras")
    check(#F.builds(p[1], 0, "cvfigh") == 3 + e and #F.builds(p[1], 0, "cvhraz") == 1, "the raid's composition (extras mirror the first unit)")
    check(F.count(p[1], "SetCloaked") == 6 + 4 + e, "every raider is cloaked, extras included: " .. F.count(p[1], "SetCloaked"))
    check(F.count(p[1], "Goto") == 4 + e, "every raider, extras included, takes the initial route")
    for _, b in ipairs(F.builds(p[1])) do check(b.team == 5, "raiders are the co-op enemy") end
    for i = 1, 4 do check(lastObjectives(p[i]) == "bd14001.otf:white", "the briefing objective on peer " .. i) end
    guestsPassive(p)
    noEnemyTeamTwo(p[1])
end

-- ------------------------------------------------------------------ SkyEye, the big assault, the APC convoy
for _, n in ipairs({ 1, 2 }) do
    local w, p, m = setup(n, {})
    local e = extrasFor(n)
    F.run(118)
    check(F.heardCount(p[1], "bd14002.wav") == 0, "SkyEye waits two minutes")
    F.run(4)
    check(F.heardCount(p[n], "bd14002.wav") == 1, n .. " humans: SkyEye reports the APC on every peer")
    check(lastObjectives(p[n]) == "bd14001.otf:white,bd14002.otf:white", "both objectives are listed")
    F.run(110)
    check(#builtAt(p[1], "spawn_attack_waves") == 0, "the assault waits four minutes")
    F.run(15)
    local assault = builtAt(p[1], "spawn_attack_waves")
    check(#assault == 9 + e, n .. " humans: the assault is nine craft plus " .. e .. " extras: " .. #assault)
    check(#F.builds(p[1], 0, "cvhtnk") == 2 + e and #F.builds(p[1], 0, "cvltnk") == 1 and #F.builds(p[1], 0, "cvtnk") == 2, "heavy tanks lead the assault (TRO 1.3 mix: 1 cvltnk, 2 cvtnk)")
    reap()
    F.run(290)
    check(#F.builds(p[1], 0, "cvapcc") == 0, "the APC waits until five minutes after the assault")
    F.run(8)
    local apcBuilds = F.builds(p[1], 0, "cvapcc")
    check(#apcBuilds == 1 and apcBuilds[1].team == 5 and apcBuilds[1].where == "spawn_apc", "one APC on the co-op enemy team")
    check(F.heardCount(p[n], "bd14003.wav") == 1, "SkyEye warns that the APC is close")
    local apc = p[1].env.Save().apc
    check(apc == apcBuilds[1].h, "the APC is the body's own handle")
    check(F.count(p[1], "SetObjectiveOn") == 1 and F.callsOf(p[1], "SetObjectiveOn")[1][2] == apc, "the APC is marked")
    check(F.count(p[1], "Goto") >= 1, "the APC is sent along its route")
    local route = false
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[2] == apc and c[3] == "path_apc_travel" then route = true end end
    check(route, "the APC travels path_apc_travel")
    local escorts = builtAt(p[1], "spawn_apc", "cvtnk")
    check(#escorts == 4 + e, n .. " humans: four escort tanks plus extras")
    check(F.count(p[1], "Defend2") == 4 + e, "every escort, extras included, defends the APC")
    for _, c in ipairs(F.callsOf(p[1], "Defend2")) do check(c[3] == apc, "the escorts defend the real APC handle") end
    -- the restored turret convoy
    local turrets = builtAt(p[1], "spawn_turrets", "cvturr")
    check(#turrets == 3 + e and F.count(p[1], "Goto", nil) >= 1, n .. " humans: the cut turret convoy is three tanks plus extras")
    local turretGoto = 0
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[3] == "path_turrets" then turretGoto = turretGoto + 1 end end
    check(turretGoto == 3 + e, "the turret convoy takes path_turrets")
    -- the attackers, the walkers and their cargo tanks
    check(#F.builds(p[1], 0, "cvwalk") == 3 and #F.builds(p[1], 0, "cvtnkc") == 3, "three walkers with three cargo tanks")
    check(F.count(p[1], "Follow") == 3, "every cargo tank follows its walker")
    for _, c in ipairs(F.callsOf(p[1], "Follow")) do
        check(type(c[2]) == "string" and type(c[3]) == "string" and c[3]:match("^built"), "the follow target is the real walker, not a ticket")
    end
    check(#builtAt(p[1], "spawn_attack_waves") >= 9 + e + 5 + 3 + 3, "the convoy's attackers join the assault")
    for _, b in ipairs(F.builds(p[1])) do check(b.team == 5, "the whole convoy is the co-op enemy") end
    -- every Chinese craft is cloaked once the real unit exists (the APC and the escorts are not)
    local cloaked = {}
    for _, c in ipairs(F.callsOf(p[1], "SetCloaked")) do cloaked[c[2]] = true end
    for _, b in ipairs(builtAt(p[1], "spawn_attack_waves")) do
        -- the cargo tanks only follow their walkers: the source never cloaks them
        if b.odf ~= "cvtnkc" then check(cloaked[b.h], "wave craft are cloaked: " .. b.odf) end
    end
    check(not cloaked[apc], "the APC is not cloaked")
    -- the fifty second warning
    F.run(40)
    check(F.heardCount(p[1], "bd14004.wav") == 0, "bd14004 waits fifty seconds")
    F.run(10)
    check(F.heardCount(p[n], "bd14004.wav") == 1, "the APC is getting close: line once on every peer")
    -- once only: a long wait builds no second convoy
    F.run(60)
    check(#F.builds(p[1], 0, "cvapcc") == 1 and #builtAt(p[1], "spawn_turrets", "cvturr") == 3 + e, "the convoy comes once")
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end
do -- four humans: all primaries arrive and the live cap bounds only the extras
    local w, p, m = setup(4, {})
    toApc(w)
    local primaries = 4 + 3 + 14
    local total = 0
    for _, b in ipairs(F.builds(p[1])) do if b.team == 5 and b.odf ~= "cvapcc" then total = total + 1 end end
    check(total >= primaries + 5 + 9 and total <= primaries + 5 + 9 + 3 * 2 + 4, "the convoy's primaries all arrive, extras are bounded: " .. total)
    check(#builtAt(p[1], "spawn_turrets", "cvturr") >= 3, "the turret primaries arrive")
end
do -- the restored convoy needs the map's two paths
    local w = F.reset()
    w.missingPaths = { spawn_turrets = true }
    local peer = F.makePeer(1, 1, false, {})
    F.connect(); F.run(1)
    F.run(545)
    check(#F.builds(peer, 0, "cvapcc") == 1 and #F.builds(peer, 0, "cvturr") == 0, "a map without the turret paths gets no restored convoy")
end

-- ------------------------------------------------------------------ the ambushes: any human, any team
for _, n in ipairs({ 1, 2, 4 }) do
    local w, p, m = setup(n, {})
    local e = extrasFor(n)
    -- the nearest human of the last team springs it; the host stays at the start
    atTrigger1(p[n])
    F.run(4)
    check(m.attack1 and not m.attack2, n .. " humans: only the base ambush is marked")
    check(#builtAt(p[1], "spawn_attack_1") == 8 + e, n .. " humans: the eastern ambush is eight craft plus extras")
    check(#builtAt(p[1], "spawn_defend") == 7 + e, n .. " humans: the base defenders are seven craft plus extras")
    -- the first unit of each group is mirrored: the eastern group opens with a raider, the defenders with a walker
    check(#F.builds(p[1], 0, "cvwalk") == 2 + e and #F.builds(p[1], 0, "cvhraz") == 1 + 2 + e, "the ambush composition")
    check(F.count(p[1], "SetCloaked") >= 6 + 8 + e, "the eastern ambush is cloaked")
    local defendGoto = 0
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[3] == "path_defend" then defendGoto = defendGoto + 1 end end
    check(defendGoto == 7 + e, "the defenders take path_defend")
    -- an ambush springs once
    F.run(6)
    check(#builtAt(p[1], "spawn_attack_1") == 8 + e, "the base ambush springs once")
    reap() -- the live cap bounds the extras of a crowded field, not this check
    atTrigger2(p[n])
    F.run(4)
    check(m.attack2 and #builtAt(p[1], "spawn_attack_2") == 5 + e, n .. " humans: the western ambush is five craft plus extras")
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
end
do -- a human beyond 150 m springs nothing
    local w, p, m = setup(2, {})
    F.nearTo(p[1].player, "trigger_attack_1", 0, -170)
    F.nearTo(p[2].player, "trigger_attack_2", 0, 200)
    F.run(4)
    check(not m.attack1 and not m.attack2, "no ambush beyond 150 m")
end
do -- all humans down: the token is infinitely far and nothing springs or errors
    local w, p, m = setup(1, {})
    F.nearTo(p[1].player, "trigger_attack_1", 0, 0)
    F.kill(p[1].player)
    F.run(4)
    check(not m.attack1 and not m.attack2, "no living human, no ambush")
end
do -- a human watching the defenders' spawn: they come from the next hidden eastern staging point
    local w, p, m = setup(2, {})
    F.nearTo(p[1].player, "spawn_defend", 0, 20)
    atTrigger1(p[2])
    F.run(4)
    check(m.attack1, "the second human springs the ambush")
    check(#builtAt(p[1], "spawn_defend") == 0, "nothing pops in within 120 m of a human")
    check(#builtAt(p[1], "spawn_attack_1") == 9 + 8, "the defenders take the hidden eastern entry: " .. #builtAt(p[1], "spawn_attack_1"))
    for _, b in ipairs(F.builds(p[1])) do
        for _, q in ipairs(p) do check(q.env.GetDistance(q.player, b.h) >= 120, "no scripted unit is built within 120 m of any human") end
    end
end

-- ------------------------------------------------------------------ intercepting the APC
do
    local w, p, m = setup(3, {})
    toApc(w)
    local apc = m.apc
    F.run(10)
    F.kill(apc)
    F.run(2)
    check(m.objective2Complete and F.heardCount(p[2], "bd14005.wav") == 1, "a destroyed APC completes the intercept on every peer")
    check(lastObjectives(p[3]) == "bd14002.otf:green,bd14003.otf:white", "the recycler becomes the objective")
    check(F.count(p[1], "SetObjectiveOff") == 0, "a vanished APC needs no marker removal (the body skips an invalid handle)")
    F.run(60)
    check(F.heardCount(p[1], "bd14004.wav") == 0, "bd14004 never plays after the APC is down")
    check(#F.builds(p[1], 0, "cvscav") == 0, "the scavengers wait four minutes")
    F.run(185)
    local scavs = F.builds(p[1], 0, "cvscav")
    check(#scavs == 2 and scavs[1].team == 5 and scavs[1].where == "spawn_scav", "two scavengers rebuild the Chinese economy")
    check(F.count(p[1], "FailMission") == 0, "a dead APC at the end of its route is no loss")
    F.run(30)
    check(F.count(p[1], "FailMission") == 0 and not m.wonLost, "the wreck never loses the mission")
end

-- ------------------------------------------------------------------ the win
do
    local w, p, m = setup(3, {})
    toApc(w)
    F.kill(m.apc); F.run(2)
    F.kill("chin_recycler")
    F.run(1)
    check(m.objective3Complete and m.wonLost, "the Chinese recycler down wins")
    for i = 1, 3 do check(F.heardCount(p[i], "bd14006.wav") == 1, "the closing line plays on peer " .. i) end
    check(lastObjectives(p[2]) == "bd14002.otf:green,bd14003.otf:green", "both objectives turn green")
    F.run(15)
    for i = 1, 3 do
        check(F.count(p[i], "SucceedMission") == 1 and F.last(p[i], "SucceedMission")[3] == "bd14win.des", "one victory on peer " .. i)
        check(F.count(p[i], "FailMission") == 0, "no failure on peer " .. i)
    end
    -- the black dog recycler dying in the debrief changes nothing
    F.kill("recycler"); F.run(10)
    check(F.count(p[1], "FailMission") == 0 and F.heardCount(p[1], "bd14008.wav") == 0, "a late recycler loss is ignored")
end
do -- the win without the intercept (the objective list still turns green) and the same-frame precedence
    local w, p, m = setup(2, {})
    F.kill("chin_recycler"); F.kill("recycler")
    F.run(15)
    check(F.count(p[1], "SucceedMission") == 1 and F.count(p[1], "FailMission") == 0, "the win beats a simultaneous recycler loss")
    check(F.heardCount(p[1], "bd14008.wav") == 0, "the recycler loss line is not played")
end

-- ------------------------------------------------------------------ the two losses
do -- the APC reaches the Chinese base
    local w, p, m = setup(3, {})
    toApc(w)
    F.place(m.apc, 1192.64 + 20, 101026)
    F.run(2)
    check(not m.wonLost, "20 m short of the route end is outside the TRO 1.3 12 m arrival radius")
    F.place(m.apc, 1192.64, 101026)
    F.run(2)
    check(m.wonLost and not m.objective3Complete and F.heardCount(p[2], "bd14007.wav") == 1, "an APC at the end of its route loses the intercept")
    check(lastObjectives(p[1]) == "bd14001.otf:red,bd14002.otf:red", "both objectives turn red")
    F.run(15)
    for i = 1, 3 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd14lsea.des", "the pegasus debrief on peer " .. i)
        check(F.count(p[i], "SucceedMission") == 0, "no victory on peer " .. i)
    end
end
do -- the Black Dog recycler dies
    local w, p, m = setup(2, {})
    F.run(30)
    F.kill("recycler")
    F.run(2)
    check(m.wonLost and F.heardCount(p[2], "bd14008.wav") == 1, "the recycler loss line plays on every peer")
    F.run(15)
    for i = 1, 2 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "bd14lseb.des", "the recycler debrief on peer " .. i)
    end
    -- a result is decided: the pending requests are dropped and the waves never come
    local before = #F.builds(p[1])
    F.run(260)
    check(#F.builds(p[1]) == before, "nothing is built after the result")
end

-- ------------------------------------------------------------------ a failed audio handle never strands the ending
do
    local w, p, m = setup(1, { nilAudio = true })
    F.run(5)
    F.kill("chin_recycler")
    F.run(10)
    check(F.count(p[1], "SucceedMission") == 1, "an ending without audio handles still resolves")
end
do
    local w, p, m = setup(1, { nilAudio = true })
    F.run(5)
    F.kill("recycler")
    F.run(10)
    check(F.count(p[1], "FailMission") == 1 and F.last(p[1], "FailMission")[3] == "bd14lseb.des", "a loss without audio handles still resolves")
end

-- ------------------------------------------------------------------ save / load
do -- a load republishes the whole objective list and the APC marker
    local w, p, m = setup(2, {})
    toApc(w)
    F.run(2)
    local objectives, marks = F.count(p[1], "AddObjective"), F.count(p[1], "SetObjectiveOn")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "AddObjective") == objectives + 2, "a load republishes both objectives")
    check(lastObjectives(p[1]) == "bd14001.otf:white,bd14002.otf:white", "the republished list follows the state")
    check(F.count(p[1], "SetObjectiveOn") == marks + 1, "a load marks the living APC again")
    check(lastObjectives(p[2]) == "bd14001.otf:white,bd14002.otf:white", "the guest gets the list too")
    check(F.heardCount(p[1], "bd14001.wav") == 1 and F.heardCount(p[1], "bd14003.wav") == 1, "a load does not replay the lines")
    local convoy = #F.builds(p[1], 0, "cvturr")
    F.run(20)
    check(#F.builds(p[1], 0, "cvturr") == convoy and #F.builds(p[1], 0, "cvapcc") == 1, "a load repeats no spawn, the turret convoy included")
end
do -- after the intercept the list is [002 green, 003 white] and no marker comes back
    local w, p, m = setup(2, {})
    toApc(w)
    F.kill(m.apc); F.run(2)
    local marks = F.count(p[1], "SetObjectiveOn")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(lastObjectives(p[1]) == "bd14002.otf:green,bd14003.otf:white", "the intercepted state is republished")
    check(F.count(p[1], "SetObjectiveOn") == marks, "no marker for a dead APC")
end
do -- a load before any objective republishes nothing, and a held ambush survives it once
    local w, p, m = setup(2, {})
    F.nearTo(p[1].player, "spawn_defend", 0, 20)
    atTrigger1(p[2])
    F.run(3)
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(4)
    check(#builtAt(p[1], "spawn_attack_1") == 9 + 8, "a load neither loses nor repeats the ambush")
end

-- ------------------------------------------------------------------ leader leaves
do
    local w, p, m = setup(3, {})
    p[2].env.DeletePlayer(1); p[3].env.DeletePlayer(1)
    F.run(3)
    for i = 2, 3 do check(F.count(p[i], "FailMission") == 1, "the mission fails for guest " .. i .. " when the leader leaves") end
    check(F.count(p[1], "FailMission") == 0, "the leader itself keeps playing")
end

-- ------------------------------------------------------------------ weather: absent, present, broken
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
    -- the real generated sites: five geyser vents, two under the Chinese base
    local sites = dofile("Scripts/CRGanymedeSitesBD14.lua")
    check(sites.mission == "bdmisn14" and #sites.vents == 5, "the generated sites carry the five geysers")
    check(sites.vents[3].label == "eggeizr13_geyser" and sites.vents[4].label == "eggeizr15_geyser", "the factory and recycler geysers are vents 3 and 4")
    local weather = { module = function(peer, record) return ganymede(record, nil, sites)(peer) end, sites = sites }
    local w, p, m = setup(3, { weather = weather })
    check(F.count(p[1], "EuropaInit", true) == 1 and F.last(p[1], "EuropaInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.last(p[1], "EuropaInit")[5] == 1 and F.last(p[1], "EuropaInit")[6] == 1, "the moon starts quiet")
    check(F.count(p[2], "EuropaInit", false) == 1, "guests render only (not the authority)")
    check(F.count(p[1], "EuropaAnnounce") == 1 and F.count(p[2], "EuropaAnnounce") == 0, "the leader announces its weather state once")
    local env = F.last(p[1], "EnvironmentInit")[2]
    check(F.count(p[1], "EnvironmentInit") == 1 and env.lightingMode == "orbit", "orbit lighting is initialised")
    for i = 2, 3 do
        check(F.count(p[i], "WeatherSensors") == 1 and F.last(p[i], "WeatherSensors")[2] == "Ganymede", "the sensors are bound on peer " .. i)
    end
    check(p[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    F.run(3)
    check(F.count(p[1], "EuropaLevel", 2) == 1, "the first raid: the moon stirs")
    -- the base ambush opens the factory's geyser, the western one the recycler's
    atTrigger1(p[3]); F.run(4)
    check(F.count(p[1], "EuropaPlume", 3) == 1 and F.count(p[1], "EuropaQuakeCall", 0.3) == 1, "the base ambush opens the factory's geyser")
    atTrigger2(p[3]); F.run(4)
    check(F.count(p[1], "EuropaPlume", 4) == 1 and F.count(p[1], "EuropaQuakeCall", 0.3) == 2, "the western ambush opens the recycler's geyser")
    F.nearTo(p[3].player, "recycler", 0, 0)
    F.run(240)
    check(F.count(p[1], "EuropaLevel", 3) == 1 and F.count(p[1], "EuropaQuakeCall", 0.35) == 1, "the big assault: level 3 and a quake")
    reap()
    F.run(310)
    check(F.count(p[1], "EuropaLevel", 4) == 1 and F.count(p[1], "EuropaSurgeCall", 5.0) == 1, "the APC: level 4 and a surge")
    check(F.count(p[1], "EuropaQuakeCall", 0.5) == 1, "the APC arrives with a quake")
    F.kill(m.apc); F.run(2)
    check(F.count(p[1], "EuropaLevel", 3) == 2 and F.count(p[1], "EuropaQuakeCall", 0.4) == 1, "the intercept settles the sky a step")
    check(F.count(p[1], "EuropaCreated") > 0, "new objects are offered to the weather")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "EuropaShutdown") >= 1 and F.count(p[1], "EuropaLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(p[1], "EuropaPlume") == 2 and F.count(p[1], "EuropaLevel", 4) == 1, "a load repeats no beat")
    F.kill("chin_recycler"); F.run(2)
    check(F.count(p[1], "EuropaPlume", 4) == 2 and F.count(p[1], "EuropaLevel", 2) == 2, "the recycler falls: its geyser opens and the sky eases for the debrief")
    check(F.count(p[1], "EuropaSurgeCall", 6.0) == 0, "a victory is no loss surge")
end
do -- a loss surges the sky over the base
    local sites = dofile("Scripts/CRGanymedeSitesBD14.lua")
    local w, p, m = setup(2, { weather = { module = function(peer, record) return ganymede(record, nil, sites)(peer) end, sites = sites } })
    F.run(5)
    F.kill("recycler"); F.run(2)
    check(F.count(p[1], "EuropaSurgeCall", 6.0) == 1 and F.count(p[1], "EuropaQuakeCall", 0.35) == 1, "a lost mission ends with a last surge")
end
do -- sites module missing: no weather, never an error
    local sites = dofile("Scripts/CRGanymedeSitesBD14.lua")
    local w, p, m = setup(2, { weather = { module = function(peer, record) return ganymede(record, nil, sites)(peer) end } })
    check(F.count(p[1], "EuropaInit") == 0 and m.startDone, "module without sites: disabled")
end
do -- a site table with no vents: the plumes are skipped, the levels still follow the story
    local sites = { vents = {} }
    local w, p, m = setup(2, { weather = { module = function(peer, record) return ganymede(record, nil, sites)(peer) end, sites = sites } })
    atTrigger1(p[2]); F.run(4)
    check(F.count(p[1], "EuropaPlume") == 0 and F.count(p[1], "EuropaLevel", 2) == 1 and m.attack1, "no vents, no plumes")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local sites = dofile("Scripts/CRGanymedeSitesBD14.lua")
    local w, p, m = setup(2, { weather = { module = function(peer, record) return ganymede(record, mode, sites)(peer) end, sites = sites } })
    atTrigger1(p[2]); F.run(4)
    check(#builtAt(p[1], "spawn_attack_1") == 8 + 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("bdmisn14 co-op: " .. checks .. " checks passed")
