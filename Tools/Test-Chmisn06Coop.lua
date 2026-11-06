-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/ch06cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/Test-Chmisn06Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Chmisn06Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local function extrasFor(n) return math.min(math.floor(n / 2), 2) end
local BASE = { "avrecy2_recycler", "avmuf2_factory", "avslf2_armory", "absilo2_scrapsilo", "absilo3_scrapsilo" }
local NEVER = 999999.9

local function setup(n, options, ran)
    options = options or {}
    local w = F.reset()
    w.audioBusy = options.busy == true
    w.ran = ran or 1
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
-- Everything that is the Soviet side's: team 5 (and the DLL's team 2 in the faithful run), never a human craft
-- and never the guests' start buoys unless asked.
local function killEnemies(includeBuoys)
    for _, o in pairs(F.world().objects) do
        if o.team == 5 or (o.team == 2 and o.odf ~= "avtank" and (includeBuoys or o.odf ~= "pspwn_1")) then o.alive = false end
    end
end
-- Calls named `name` whose argument number `index` (counting the name as 1) is `value`.
local function countArg(peer, name, index, value)
    local n = 0
    for _, c in ipairs(peer.calls) do if c[1] == name and c[index] == value then n = n + 1 end end
    return n
end
local function toConvoy(m) F.runUntil(function() return m.ranDone end, 1500) end
local function convoy(m)
    local out = {}
    for i = 1, 12 do out[i] = m.reinf[i] end
    return out
end
local function builtAt(peer, where, mark)
    local out = {}
    for _, b in ipairs(F.builds(peer, mark or 0)) do
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
        for _, name in ipairs({"BuildObject", "SetScrap", "Goto", "Attack", "SetAIP", "SetTeamNum", "SetPerceivedTeam"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
-- The enemy is team 5 only: nothing is ever aimed at the DLL's literal team 2 (a guest's team here).
local function noTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on team 2") end
    for _, name in ipairs({"SetTeamNum", "SetPerceivedTeam"}) do
        for _, c in ipairs(F.callsOf(peer, name)) do check(c[3] ~= 2, name .. " never names team 2") end
    end
    -- (a human team 2 legitimately receives pilots)
    for _, name in ipairs({"SetScrap", "AddScrap"}) do
        for _, c in ipairs(F.callsOf(peer, name)) do check(c[2] ~= 2, name .. " never names team 2") end
    end
    for _, c in ipairs(F.callsOf(peer, "SetAIP")) do check(c[3] ~= 2, "SetAIP never names team 2") end
end
local function gotosTo(peer, path)
    local n = 0
    for _, c in ipairs(F.callsOf(peer, "Goto")) do if c[3] == path then n = n + 1 end end
    return n
end
local function noTicketOrder(peer)
    for _, name in ipairs({"Goto", "Attack"}) do
        for _, c in ipairs(F.callsOf(peer, name)) do check(type(c[2]) == "string", "no native call ever sees a ticket") end
    end
end
local function turnTraitors(m)
    local reinf = m.reinf
    F.nearTo(reinf[1], "ran_" .. (m.ranChoice + 1) .. "_trigger", 10, 0)
    F.run(2)
end

-- ------------------------------------------------------------------ offline == faithful
local function summary(peer)
    local out, objectives, lines = {}, {}, {}
    for _, c in ipairs(peer.calls) do
        if c[1] == "BuildObject" then
            out[#out + 1] = "B:" .. c[3] .. ":" .. (c[4] == 2 and 5 or c[4]) .. ":" .. tostring(c[5])
        elseif c[1] == "SucceedMission" or c[1] == "FailMission" then
            out[#out + 1] = c[1] .. ":" .. tostring(c[3])
        elseif c[1] == "AddObjective" then
            objectives[#objectives + 1] = "O:" .. c[2] .. ":" .. tostring(c[3])
        elseif c[1] == "SetScrap" or c[1] == "AddScrap" then
            out[#out + 1] = c[1] .. ":" .. (c[2] == 2 and 5 or c[2]) .. ":" .. c[3]
        elseif c[1] == "SetPilot" then
            out[#out + 1] = "P:" .. (c[2] == 2 and 5 or c[2]) .. ":" .. c[3]
        elseif c[1] == "SetAIP" then
            out[#out + 1] = "AIP:" .. c[2]
        elseif c[1] == "SetTeamNum" then
            out[#out + 1] = "T:" .. (c[3] == 2 and 5 or c[3])
        elseif c[1] == "AudioMessage" or c[1] == "Play" then
            -- the restored debrief line is the one voice line the faithful port never plays
            if c[2] ~= "ch06007.wav" then lines[#lines + 1] = c[2] end
        end
    end
    return table.concat(out, ",") .. "|" .. table.concat(objectives, ",") .. "|" .. table.concat(lines, ",")
end
local function fullRun(options)
    local w = F.reset()
    w.ran = 2
    local peer = F.makePeer(1, 1, false, options)
    F.connect(); F.run(1)
    local m = peer.env.Save()
    toConvoy(m)
    F.run(2)
    local reinf = convoy(m)
    F.nearTo(reinf[1], "ran_2_trigger", 10, 0)
    F.run(130)                       -- the betrayal, then the second wave
    F.runUntil(function() return m.numAnnoyRounds >= 1 end, 1500)
    F.run(10)                        -- the first raid
    for i = 1, 12 do F.kill(reinf[i]) end
    F.run(3)
    killEnemies(true)
    F.run(30)
    return summary(peer), peer
end
do
    local faithful = fullRun({ faithful = true, script = "Scripts/ch06.lua" })
    local offline, peer = fullRun({})
    check(faithful == offline and faithful:find("SucceedMission:ch06win.des", 1, true) and faithful:find("ch06006.wav", 1, true),
        "offline completes like the faithful port:\n" .. faithful .. "\n" .. offline)
    check(F.count(peer, "SucceedMission") == 1 and F.count(peer, "FailMission") == 0, "one victory, no failure")
    noTeamTwo(peer)
    noTicketOrder(peer)
    check(F.count(peer, "SetAIControl", 5) == 1 and F.count(peer, "SetAIControl", 2) == 0, "AI control only for enemy team 5")
    check(F.index(peer, "SetAIControl") <= peer.chunkCalls, "SetAIControl runs at chunk root, before Start")
end

-- ------------------------------------------------------------------ teams, scrap, pilots, the opening
do
    local w, p, m = setup(4, {})
    F.run(70)
    check(m.startDone and m.coopMissionStarted, "the leader starts the shared mission")
    check(F.count(p[1], "SetScrap", 1) == 1 and F.callsOf(p[1], "SetScrap")[2][3] == 50 + 10 * 3, "starting scrap: 50 plus 10 per guest")
    check(F.count(p[1], "SetScrap", 5) == 1, "the Soviet scrap is team 5's")
    for team = 1, 4 do check(F.count(p[1], "SetPilot", team) == 1 and F.callsOf(p[1], "SetPilot")[1][3] == 10, "10 pilots for human team " .. team) end
    check(F.count(p[1], "SetAIP", "chmisn06.aip") == 1 and F.last(p[1], "SetAIP")[3] == 5, "the AIP drives the co-op enemy team 5")
    for i = 1, 4 do
        check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
        local lines = F.lines(p[i])
        check(lines[1] == "ch06001.wav" and lines[2] == "ch06002.wav" and #lines == 2, "the opening plays in order on peer " .. i)
        local o = F.callsOf(p[i], "AddObjective")
        check(o[1] and o[1][2] == "ch06001.otf" and o[1][3] == "white", "objective on peer " .. i)
    end
    check(F.count(p[1], "SetObjectiveName") == 1 and F.last(p[1], "SetObjectiveName")[3] == "CCA Base", "the Soviet nav beacon is named")
    for i = 2, 4 do check(F.count(p[i], "SetObjectiveName", F.last(p[1], "SetObjectiveName")[2]) == 1, "the beacon name replicates to guest " .. i) end
    local beacon = F.builds(p[1], 0, "apcamr")
    check(#beacon == 1 and beacon[1].team == 1 and beacon[1].where == "nav_1", "the nav beacon is a team-1 build at nav_1")
    check(m.crcca and m.crcca.serial == 0, "nothing is ticketed before the convoy")
    guestsPassive(p)
    noTeamTwo(p[1])
end

-- ------------------------------------------------------------------ restored: the recon patrols fly their routes
do
    local w, p, m = setup(2, {})
    check(gotosTo(p[1], "sw_path") == 0 and gotosTo(p[1], "nw_path") == 0, "no patrol before the objective is shown")
    F.run(5)
    check(#F.callsOf(p[1], "AddObjective") >= 1, "the objective is shown")
    check(gotosTo(p[1], "sw_path") == 3 and gotosTo(p[1], "nw_path") == 3, "three recon fighters per route set out")
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do
        if c[3] == "sw_path" then check(c[2]:match("^sw_patrol") and c[4] == 1, "the sw fighters fly sw_path at the source's priority 1") end
        if c[3] == "nw_path" then check(c[2]:match("^nw_patrol") and c[4] == 1, "the nw fighters fly nw_path") end
    end
    F.run(60)
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(gotosTo(p[1], "sw_path") == 3 and gotosTo(p[1], "nw_path") == 3, "each patrol is sent once across a load")
    check(F.count(p[2], "Goto") == 0, "the guest never orders")
end
do -- a map without the routes runs the faithful mission
    local w = F.reset()
    w.missingPaths = { sw_path = true, nw_path = true }
    local peer = F.makePeer(1, 1, false, {})
    F.connect(); F.run(30)
    check(gotosTo(peer, "sw_path") == 0 and gotosTo(peer, "nw_path") == 0, "no path, no restored patrol")
end

-- ------------------------------------------------------------------ the reinforcement convoy
for ran = 1, 3 do
    local w, p, m = setup(2, {}, ran)
    toConvoy(m)
    check(m.ranChoice == ran - 1, "the entry is the body's random choice")
    local spawn = "ran_" .. ran
    local kinds = { cvfigh = 0, cvtnk = 0, cvhraz = 0 }
    for _, b in ipairs(builtAt(p[1], spawn)) do
        check(b.team == 1, "the convoy is built on the Chinese team 1")
        kinds[b.odf] = kinds[b.odf] + 1
    end
    check(kinds.cvfigh == 4 and kinds.cvtnk == 4 and kinds.cvhraz == 4, "four fighters, four tanks, four bombers")
    F.run(1)
    check(countArg(p[1], "SetPilotClass", 3, "sspilo") == 12, "twelve convoy members with Soviet pilots")
    check(countArg(p[1], "SetPerceivedTeam", 3, 5) == 12, "the disguise is the co-op enemy team 5, not a guest's team 2")
    check(gotosTo(p[1], "ran_" .. ran .. "_path") == 12, "all twelve follow the entry's route")
    check(not m.turnTraitor, "still disguised")
    heardAll(p, "ch06003.wav"); heardAll(p, "ch06004.wav")
    check(F.heardCount(p[1], "ch06005.wav") == 0, "no betrayal yet")
    noTeamTwo(p[1])
end
for _, how in ipairs({ "trigger", "damage" }) do
    local w, p, m = setup(3, {}, 3)
    toConvoy(m)
    F.run(2)
    local reinf = convoy(m)
    if how == "trigger" then
        F.nearTo(reinf[7], "ran_3_trigger", 20, 0)
    else
        F.world().objects[reinf[9]].health = 0.5
    end
    F.run(2)
    check(m.turnTraitor, "the convoy turns on " .. how)
    check(F.count(p[1], "SetTeamNum") == 12, "all twelve turn")
    for _, c in ipairs(F.callsOf(p[1], "SetTeamNum")) do check(c[3] == 5, "the traitors join team 5, not a guest's team 2") end
    check(countArg(p[1], "SetPerceivedTeam", 3, 5) == 24, "...and are perceived as team 5")
    local attacks = 0
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do
        if F.team(c[2]) == 5 then
            attacks = attacks + 1
            check(c[4] == 0, "native priority 0")
        end
    end
    check(attacks >= 12, "every traitor attacks the base: " .. attacks)
    heardAll(p, "ch06005.wav")
    guestsPassive(p)
    noTeamTwo(p[1])
end

-- ------------------------------------------------------------------ the second wave
for humans = 1, 4 do
    local w, p, m = setup(humans, {}, 1)
    toConvoy(m); F.run(2)
    turnTraitors(m)
    local mark = #p[1].calls
    F.run(135)
    local wave = {}
    for _, b in ipairs(F.builds(p[1], mark)) do
        if b.odf == "svfigh" or b.odf == "svtank" then wave[#wave + 1] = b end
    end
    local e = extrasFor(humans)
    check(#wave == 8 + e, humans .. " human(s): four fighters and four tanks plus " .. e .. " extras, got " .. #wave)
    local entry = wave[1].where
    check(entry == "ran_2" or entry == "ran_3", "the wave comes from an entry the convoy did not use: " .. entry)
    for _, b in ipairs(wave) do
        check(b.team == 5 and b.where == entry, "Soviet units on team 5 at one entry")
        check(b.odf == "svfigh" or b.odf == "svtank", "fighters and tanks only")
    end
    allSafe(p, wave)
    local attacked = 0
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do
        for _, b in ipairs(wave) do if c[2] == b.h then attacked = attacked + 1 end end
    end
    check(attacked >= #wave, "every attacker (extras too) is sent at the base: " .. attacked)
    F.run(30)
    check(#F.builds(p[1], mark, "svfigh") + #F.builds(p[1], mark, "svtank") == 8 + e, "the wave is a one-shot (the stock flood bug is fixed)")
    noTicketOrder(p[1]); noTeamTwo(p[1]); guestsPassive(p)
end
do -- a human at one of the wave's possible entries: it never comes in view
    local w, p, m = setup(2, {}, 1)
    toConvoy(m); F.run(2)
    F.place(p[2].player, 4284, 98715) -- ran_2
    turnTraitors(m)
    F.run(135)
    local wave = {}
    for _, b in ipairs(F.builds(p[1], 0)) do
        if b.odf == "svfigh" or b.odf == "svtank" then wave[#wave + 1] = b end
    end
    check(#wave == 8 + 1, "the wave is complete: " .. #wave)
    for _, b in ipairs(wave) do check(b.where ~= "ran_2", "nothing is built within 460 m of a human") end
    allSafe(p, wave)
end
do -- everything watched: the wave waits, survives a load, arrives once; no victory while it waits
    local w, p, m = setup(2, {}, 1)
    toConvoy(m); F.run(2)
    F.world().objects[p[2].player].craft = false
    F.place(p[2].player, 4000, 98000)
    for _, name in ipairs({ "ran_1", "ran_2", "ran_3" }) do w.pathPos[name] = { x = 4000, y = 10, z = 98000 } end
    turnTraitors(m)
    F.run(135)
    check(#F.builds(p[1], 0, "svfigh") == 0 and #F.builds(p[1], 0, "svtank") == 0, "a fully watched map defers the wave")
    check(type(m.crcca.serial) == "number" and m.crcca.serial >= 8, "tickets are held")
    noTicketOrder(p[1])
    local reinf = convoy(m)
    for i = 1, 12 do F.kill(reinf[i]) end
    killEnemies(true)
    F.run(30)
    check(m.reinfDestroyed and not m.won and F.count(p[1], "SucceedMission") == 0, "a Soviet request still waiting is an enemy: no victory")
    local pending = m.crcca.serial
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(m.crcca.serial == pending and #F.builds(p[1], 0, "svfigh") == 0, "save/load keeps the pending wave without duplicating it")
    w.pathPos.ran_1 = { x = 4026, y = 10, z = 100663 }
    F.place(p[2].player, 20000, 20000)
    F.run(8)
    check(#F.builds(p[1], 0, "svfigh") + #F.builds(p[1], 0, "svtank") == 8 + 1, "the whole wave is built exactly once when the watcher leaves")
    check(not m.won, "the new attackers are alive: still no victory")
    killEnemies(true)
    F.run(30)
    check(m.won and F.count(p[1], "SucceedMission") == 1, "...and the victory comes once they are dead")
end
do -- live cap: extras are the only requests dropped
    local w, p, m = setup(4, {}, 1)
    toConvoy(m); F.run(2)
    m.crcca.live = {}
    for i = 1, 24 do m.crcca.live[i] = F.spawn("svtank", 5, 9000 + i, 9000) end
    turnTraitors(m)
    F.run(135)
    local n = #F.builds(p[1], 0, "svfigh") + #F.builds(p[1], 0, "svtank")
    check(n == 8, "at the live cap the wave keeps its primaries and drops the extras: " .. n)
end

-- ------------------------------------------------------------------ the harassment raids
local function toRaid(m) F.runUntil(function() return m.numAnnoyRounds >= 1 end, 1500) end
for humans = 1, 4 do
    local w, p, m = setup(humans, {}, 1)
    toRaid(m)
    F.run(8)
    local e = extrasFor(humans)
    local raid = builtAt(p[1], "annoy_1")
    check(#raid == 10 + e, humans .. " human(s): the raid is 10 + " .. e .. " extras, got " .. #raid)
    allSafe(p, raid)
    local kinds = {}
    for _, b in ipairs(raid) do
        check(b.team == 5, "raiders are Soviet craft on team 5")
        kinds[b.odf] = true
    end
    check(kinds.svfigh and kinds.svltnk and kinds.svtank and kinds.svhraz, "all four raider kinds are drawn")
    local ordered = 0
    for _, c in ipairs(F.callsOf(p[1], "Goto")) do
        if c[3] == "annoy_1_path" then ordered = ordered + 1 end
    end
    check(ordered == #raid, "every raider (extras too) drives the raid route: " .. ordered)
    check(m.numAnnoyRounds == 1 and m.maxAnnoy == 10, "ten raiders in the first round")
    guestsPassive(p); noTicketOrder(p[1]); noTeamTwo(p[1])
    -- a second round refills only the dead
    local living = {}
    for i, b in ipairs(raid) do if i <= 4 then F.kill(b.h) end end
    local before = #builtAt(p[1], "annoy_1")
    F.run(600)
    local again = #builtAt(p[1], "annoy_1") - before
    check(again >= 4 and again <= 4 + e, "ten minutes later (TRO 1.3) only the dead are replaced: " .. again)
end
do -- the third round shrinks the raid to six
    local w, p, m = setup(1, {}, 1)
    toRaid(m); F.run(8)
    for round = 2, 3 do
        for _, b in ipairs(builtAt(p[1], "annoy_1")) do if F.alive(b.h) then F.kill(b.h) end end
        F.run(600)
    end
    check(m.numAnnoyRounds == 3 and m.maxAnnoy == 6, "the third round sets the cap to six")
end
do -- the PSU towers gate the raids
    local w, p, m = setup(1, {}, 1)
    for i = 1, 4 do F.kill("psu_" .. i) end
    F.run(700)
    check(m.numAnnoyRounds == 0 and #builtAt(p[1], "annoy_1") == 0, "no raid once the long-range power is down")
    check(m.annoyTime >= NEVER, "the raids are over for good")
end
do -- a human at the raid entry: the raid comes from a far edge and drives to the base
    local w, p, m = setup(2, {}, 1)
    F.place(p[2].player, 600, 99400)
    toRaid(m); F.run(8)
    check(#builtAt(p[1], "annoy_1") == 0, "nothing is built within 460 m of a human")
    local raid = {}
    for _, b in ipairs(builtAt(p[1], "ran_1")) do
        if b.odf:sub(1, 2) == "sv" then raid[#raid + 1] = b end -- (the convoy of the same entry is Chinese)
    end
    check(#raid == 10 + 1, "the raid uses the next clear approach: " .. #raid)
    allSafe(p, raid)
    for _, b in ipairs(raid) do
        local last
        for _, c in ipairs(F.callsOf(p[1], "Goto")) do if c[2] == b.h then last = c[3] end end
        check(last == "activate_2", "a fallen-back raider drives to the base, not to the far route start: " .. tostring(last))
    end
end

-- ------------------------------------------------------------------ stock bug: idle attackers hunt again
do
    local w, p, m = setup(2, {}, 1)
    toConvoy(m); F.run(2)
    turnTraitors(m)
    F.run(135)
    local mark = 0
    local wave = {}
    for _, b in ipairs(F.builds(p[1], mark)) do
        if b.odf == "svfigh" or b.odf == "svtank" then wave[#wave + 1] = b end
    end
    local function attacksOn(h)
        local n = 0
        for _, c in ipairs(F.callsOf(p[1], "Attack")) do if c[2] == h then n = n + 1 end end
        return n
    end
    local busy, idle = wave[1].h, wave[2].h
    F.world().objects[busy].command = 3
    local before, busyBefore = attacksOn(idle), attacksOn(busy)
    F.run(45)
    check(attacksOn(idle) > before, "an idle attacker is sent out again")
    check(attacksOn(busy) == busyBefore, "an attacker that is busy keeps its order")
    -- the nearest living building of the base is the target
    for _, name in ipairs(BASE) do if name ~= "avmuf2_factory" and name ~= "absilo2_scrapsilo" then F.kill(name) end end
    F.nearTo(idle, "absilo2_scrapsilo", 100, 0)
    F.run(25)
    local last
    for _, c in ipairs(F.callsOf(p[1], "Attack")) do if c[2] == idle then last = c[3] end end
    check(last == "absilo2_scrapsilo", "the nearest living base building is the target: " .. tostring(last))
    -- a traitor that went idle is sent again too
    local traitor = m.reinf[2]
    F.world().objects[traitor].command = 0
    local tBefore = attacksOn(traitor)
    F.run(45)
    check(attacksOn(traitor) > tBefore, "an idle traitor is sent out again")
    -- no hunt after the loss
    F.kill("avmuf2_factory"); F.run(3)
    check(m.lost, "the base is lost")
    local frozen = #F.callsOf(p[1], "Attack")
    F.run(60)
    check(#F.callsOf(p[1], "Attack") == frozen, "no hunt once the mission is decided")
end

-- ------------------------------------------------------------------ the convoy dies, the base is cleared, the debrief
for humans = 1, 3 do
    local w, p, m = setup(humans, {}, 2)
    toConvoy(m); F.run(2)
    -- everything on the Soviet side dead before the convoy is beaten is no victory
    local reinf = convoy(m)
    check(not m.reinfDestroyed, "the convoy lives")
    for i = 1, 12 do F.kill(reinf[i]) end
    F.run(2)
    check(m.reinfDestroyed, "the convoy is destroyed")
    heardAll(p, "ch06006.wav")
    local stolen = F.world().objects["stolen"]
    check(stolen.perceived == 5, "the stolen factory is revealed as Soviet")
    check(F.world().objects["ld_power1"].perceived == 5 and F.world().objects["ld_power2"].perceived == 5, "...and so are the long-range power plants")
    for i = 1, humans do
        check(F.count(p[i], "SetObjectiveName", "stolen") == 1, "the stolen factory is named on peer " .. i)
        check(F.count(p[i], "SetObjectiveOn", "stolen") == 1, "...and marked on peer " .. i)
    end
    check(countArg(p[1], "SetPerceivedTeam", 3, 5) == 12 + 3, "disguise and reveal are all team 5")
    check(not m.won, "the base still stands")
    check(F.heardCount(p[1], "ch06007.wav") == 0, "no debrief before the victory")
    local t0 = w.now
    killEnemies(false)
    F.run(8)
    check(m.won, "every Soviet object is down (a guest's team-2 craft does not count)")
    check(humans < 2 or F.alive("player2"), "the guest's team-2 craft is alive at the victory")
    heardAll(p, "ch06007.wav")
    for i = 1, humans do
        check(F.count(p[i], "SucceedMission") == 1 and F.count(p[i], "FailMission") == 0, "one shared victory on peer " .. i)
        check(F.last(p[i], "SucceedMission")[3] == "ch06win.des", "victory debrief on peer " .. i)
        check(F.last(p[i], "SucceedMission")[2] >= t0 + 12, "the result waits for the debrief line on peer " .. i)
        check((p[i].env.Save().coopUnresolved or 0) == 0, "no unresolved presentation identities on peer " .. i)
    end
    local ch7 = F.index(p[1], "Play", "ch06007.wav") or F.index(p[1], "AudioMessage", "ch06007.wav")
    check(ch7 and ch7 < F.index(p[1], "SucceedMission"), "the debrief line is spoken before the result is applied")
    for _, name in ipairs(BASE) do F.kill(name) end
    F.run(5)
    for i = 1, humans do check(F.count(p[i], "FailMission") == 0, "a loss after the win is ignored") end
    local builds = #F.builds(p[1])
    F.run(320)
    check(#F.builds(p[1]) == builds, "no raid after the win")
    guestsPassive(p)
end
do -- all dead before the convoy exists: nothing
    local w, p, m = setup(1, {}, 1)
    killEnemies(false); F.run(30)
    check(not m.won and F.count(p[1], "SucceedMission") == 0, "no victory before the convoy has been beaten")
end

-- ------------------------------------------------------------------ loss
do
    local w, p, m = setup(2, {}, 1)
    toConvoy(m)
    F.kill("avrecy2_recycler"); F.run(3)
    check(not m.lost and F.count(p[1], "FailMission") == 0, "the factory alone keeps the base")
    F.kill("avmuf2_factory"); F.run(5)
    check(m.lost, "the recycler and factory are lost")
    for i = 1, 2 do
        check(F.count(p[i], "FailMission") == 1 and F.last(p[i], "FailMission")[3] == "ch06lsea.des", "one shared defeat on peer " .. i)
        check(F.count(p[i], "SucceedMission") == 0, "no victory on peer " .. i)
    end
    local builds = #F.builds(p[1])
    F.run(700)
    check(#F.builds(p[1]) == builds, "no raid after the defeat")
end
do -- the leader leaves
    local w, p, m = setup(3, {})
    for i = 2, 3 do p[i].env.DeletePlayer(1) end
    F.run(3)
    for i = 2, 3 do check(F.count(p[i], "FailMission") == 1, "the mission fails for guest " .. i .. " when the leader leaves") end
    check(F.count(p[1], "FailMission") == 0, "the leader itself keeps playing")
end

-- ------------------------------------------------------------------ load: the objective comes back
do
    local w, p, m = setup(2, {})
    F.run(5)
    local before = #F.callsOf(p[1], "AddObjective")
    check(before >= 1 and m.crcca.r.objectiveShown, "the objective is shown and recorded")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    local o = F.callsOf(p[1], "AddObjective")
    check(#o > before and o[#o][2] == "ch06001.otf" and o[#o][3] == "white", "the objective is back after a load")
end
do -- a load before the objective does not show it early
    local w, p, m = setup(1, {})
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(1)
    check(#F.callsOf(p[1], "AddObjective") == 0 and not (m.crcca.r and m.crcca.r.objectiveShown), "no objective before the opening")
end
do -- an absent audio handle still advances the story
    local w = F.reset()
    w.audioNil = true
    w.ran = 1
    local peer = F.makePeer(1, 1, false, {})
    F.connect(); F.run(1)
    local m = peer.env.Save()
    check(#F.callsOf(peer, "AddObjective") == 0, "nothing before the opening times")
    toConvoy(m)
    check(m.ranDone, "the convoy comes despite nil audio handles")
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
        function V.Init(o)
            peer.weatherInit = o; V.Initialized = true
            record("ElysiumInit", o.authority, o.send ~= nil, o.seed, o.startLevel, o.targetLevel)
            if mode == "initfail" then error("boom") end
        end
        function V.Update()
            if peer.weatherInit and peer.weatherInit.authority and peer.weatherInit.send and not V.sent then
                V.sent = true; peer.weatherInit.send("VenusStrike", 1, 2, 3, 4, 3, 1.0, 1.0)
            end
            if mode == "updatefail" then error("update boom") end
        end
        function V.AnnounceState() record("ElysiumAnnounce") end
        function V.ApplyNetEvent(op, ...) record("ElysiumEvent", op, ...) end
        function V.SetTargetLevel(n) record("ElysiumLevel", n) end
        function V.TriggerStrike(target) record("ElysiumStrike", target.x, target.z) end
        function V.OnObjectCreated(h) record("ElysiumCreated", h) end
        function V.Save() return { saved = true } end
        function V.Load(s) record("ElysiumLoad", s and s.saved) end
        function V.Shutdown() record("ElysiumShutdown") end
        return V
    end
end
do
    local sites = dofile("Scripts/CRElysiumSitesCH06.lua")
    check(sites.mission == "chmisn06" and #sites.vents == 10, "the generated sites belong to chmisn06")
    local weather = { module = function(peer, record) return elysium(record, nil)(peer) end, sites = sites }
    local w, p, m = setup(3, { weather = weather }, 3)
    check(F.count(p[1], "ElysiumInit", true) == 1 and F.last(p[1], "ElysiumInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.last(p[1], "ElysiumInit")[5] == 1 and F.last(p[1], "ElysiumInit")[6] == 2, "the weather starts calm and drifts to haze")
    check(F.count(p[2], "ElysiumInit", false) == 1, "guests render only (not the authority)")
    check(F.count(p[1], "ElysiumAnnounce") == 1 and F.count(p[2], "ElysiumAnnounce") == 0, "the leader announces its weather state once")
    check(F.count(p[1], "EnvironmentInit") == 1 and F.last(p[1], "EnvironmentInit")[2].lightingMode == "subtle", "the default lighting is initialised")
    for i = 2, 3 do
        local e = F.last(p[i], "ElysiumEvent")
        check(e and e[2] == "VenusStrike", "weather events reach guest " .. i)
    end
    check(F.count(p[1], "WeatherSensors") == 0, "the Venus engine owns the sensor modifier: nothing is bound here")
    check(p[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    check(F.count(p[1], "ElysiumLevel") == 0, "calm until the convoy sets out")
    toConvoy(m); F.run(2)
    check(F.count(p[1], "ElysiumLevel", 3) == 1, "the convoy closes the sky in")
    check(#F.callsOf(p[1], "ElysiumStrike") == 0, "...with no strike yet")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "ElysiumShutdown") >= 1 and F.count(p[1], "ElysiumLoad", true) == 1, "load restores the leader's weather state")
    turnTraitors(m)
    check(F.count(p[1], "ElysiumLevel", 4) == 1, "the betrayal breaks the storm")
    local strikes = F.callsOf(p[1], "ElysiumStrike")
    check(#strikes == 1, "...under a strike on the traitors, got " .. #strikes)
    check(F.count(p[1], "ElysiumCreated") > 0, "new objects are offered to the weather")
    F.run(135)
    check(#F.callsOf(p[1], "ElysiumStrike") == 2, "the second wave arrives under a strike")
    local reinf = convoy(m)
    for i = 1, 12 do F.kill(reinf[i]) end
    F.run(3)
    check(F.count(p[1], "ElysiumLevel", 3) == 2, "the convoy's end eases the sky")
    killEnemies(false); F.run(3)
    check(F.count(p[1], "ElysiumLevel", 2) == 1, "the victory eases the weather")
end
do -- a raid arrives under a strike
    local sites = dofile("Scripts/CRElysiumSitesCH06.lua")
    local w, p, m = setup(1, { weather = { module = function(peer, record) return elysium(record, nil)(peer) end, sites = sites } }, 1)
    toRaid(m); F.run(8)
    check(#F.callsOf(p[1], "ElysiumStrike") == 1, "the first raid arrives under a strike")
end
do -- sites module missing: no weather, never an error
    local w, p, m = setup(2, { weather = { module = function(peer, record) return elysium(record, nil)(peer) end } })
    check(F.count(p[1], "ElysiumInit") == 0 and m.startDone, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local sites = dofile("Scripts/CRElysiumSitesCH06.lua")
    local w, p, m = setup(2, { weather = { module = function(peer, record) return elysium(record, mode)(peer) end, sites = sites } }, 1)
    toRaid(m); F.run(10)
    check(#builtAt(p[1], "annoy_1") == 10 + 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("chmisn06 co-op: " .. checks .. " checks passed")
