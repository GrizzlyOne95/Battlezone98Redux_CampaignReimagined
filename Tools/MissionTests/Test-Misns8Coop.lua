-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/misns8cr.lua. Engine AI, rendering and combat remain mocked. Run from the repository root:
--   lua5.1 Tools/MissionTests/Test-Misns8Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/MissionTests/Misns8Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local REC, MUF = "avrecycle", "avmuf"

local function setup(n, options)
    options = options or {}
    local w = F.reset()
    if options.setup then options.setup(w) end
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(options.warmup or 2)
    return w, p, p[1].env.Save()
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
        for _, name in ipairs({"BuildObject", "SetScrap", "AddScrap", "SetAIP", "Goto", "Follow", "Attack", "SetIndependence",
            "RemoveObject", "SetPerceivedTeam", "Build", "Dropoff", "Pickup", "Damage"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
-- Every line a peer announced, whether through the faithful AudioMessage or the runtime's subtitle player.
local function lines(peer)
    local out = {}
    for _, c in ipairs(peer.calls) do
        if c[1] == "AudioMessage" or c[1] == "Play" or c[1] == "Queue" then out[#out + 1] = c[2] end
    end
    return table.concat(out, ",")
end
local function away(p) -- every human parked 1.7 km from the Black Dog base
    for _, q in ipairs(p) do F.place(q.player, 1793 + 20 * (q.id - 1), 100362) end
end

-- ------------------------------------------------------------------ offline vs faithful: same mission outcome and final voice line (not a full behaviour diff)
local function outcome(options, scenario)
    local w, p, m = setup(1, options)
    scenario(w, p, m)
    local out = {}
    for _, name in ipairs({"SucceedMission", "FailMission"}) do
        for _, c in ipairs(F.callsOf(p[1], name)) do out[#out + 1] = name .. ":" .. tostring(c[3]) end
    end
    return table.concat(out, ","), p[1], m
end
local scenarios = {
    -- the recycler dies with no Romeski: misns814
    quickwin = function(w, p, m) F.kill(REC); F.run(10) end,
    -- plan C with Romeski alive: misns803 + misns808
    romeskiwin = function(w, p, m)
        m.plan_a, m.plan_b, m.plan_c = false, false, true
        F.run(3); F.kill(REC); F.run(10)
    end,
}
for name, scenario in pairs(scenarios) do
    local faithful, fpeer = outcome({ faithful = true, script = "Scripts/misns8.lua" }, scenario)
    local offline, peer = outcome({}, scenario)
    check(faithful == offline and faithful ~= "", "offline completes like the faithful port (" .. name .. "): " .. faithful .. " / " .. offline)
    local ending = lines(peer):match("misns8%d+%.wav$")
    check(lines(fpeer):match("misns8%d+%.wav$") == ending, "offline ends with the same closing line (" .. name .. ")")
    check(offline == "SucceedMission:misns8w1.des" and F.count(peer, "SucceedMission") == 1, "one victory request offline")
end
do
    local _, peer = outcome({}, scenarios.romeskiwin)
    check(lines(peer):find("misns803.wav" .. "," .. "misns808.wav", 1, true), "Romeski alive: both closing lines, in order")
    local _, peer2 = outcome({}, scenarios.quickwin)
    check(lines(peer2):find("misns814.wav", 1, true) and not lines(peer2):find("misns808", 1, true), "no Romeski: the short ending")
end

-- ------------------------------------------------------------------ opening, ownership, teams, scrap
local w, p, m = setup(4)
check(m.start_done and m.coopMissionStarted and m.plan_a, "leader starts the shared mission")
check(F.count(p[1], "SetAIControl", 5) == 1 and F.count(p[1], "SetAIControl", 2) == 0, "AI control only for enemy team 5 at chunk load")
check(F.index(p[1], "SetAIControl") <= p[1].chunkCalls, "SetAIControl runs at chunk root, before Start")
do
    local scraps = {}
    for _, c in ipairs(F.callsOf(p[1], "SetScrap")) do scraps[c[2] .. ":" .. c[3]] = true end
    check(scraps["1:55"] and scraps["5:70"] and not scraps["2:40"] and not scraps["2:70"], "shared scrap 25 + 10 per guest, enemy 40 + 10 per guest on team 5")
    check(F.count(p[1], "SetPilot", 5) == 1 and F.count(p[1], "SetPilot", 2) == 0 and F.count(p[1], "SetPilot", 1) == 1, "pilots: humans on 1, Black Dogs on 5")
    check(F.callsOf(p[1], "SetAIP")[1][2] == "crns8.aip" and F.callsOf(p[1], "SetAIP")[1][3] == 5, "the opening plan is issued for team 5")
end
for i = 1, 4 do
    check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
    check(F.heardCount(p[i], "misns800.wav") == 1, "briefing once on peer " .. i)
    check(F.callsOf(p[i], "AddObjective")[1][2] == "misns800.otf", "objective list on peer " .. i)
end
guestsPassive(p)
F.run(2)
do
    local started = F.builds(p[1])
    local scav, nark = 0, 0
    for _, b in ipairs(started) do
        check(b.team == 5, "the Black Dog opening spawns are on team 5, not " .. tostring(b.team))
        if b.odf == "bvsca8" then scav = scav + 1 elseif b.odf == "bvra8" then nark = nark + 1 end
    end
    check(scav == 3 and nark == 1, "scavengers and the scout arrive as concealed requests")
    allSafe(p, started)
    check(type(m.avscav1) == "string" and type(m.nark) == "string", "tickets were replaced by real handles")
end
check(m.cam1 == "cam" and F.count(p[1], "SetObjectiveName", "cam") == 1, "map labels are bound and named")

-- A human standing at the Black Dog spawn: the opening units use an authored alternative entry, never a pop-in.
do
    local w2, q = setup(2, { warmup = 0 })
    F.place(q[2].player, 2917, 98888 + 100) -- on top of american_spawn
    F.run(3)
    local builds = F.builds(q[1], 0)
    check(#builds == 4, "the opening units still arrive")
    for _, b in ipairs(builds) do check(b.where ~= "american_spawn", "not at the occupied spawn: " .. tostring(b.where)) end
    allSafe(q, builds)
end

-- ------------------------------------------------------------------ the enemy team is 5 everywhere
w, p, m = setup(3)
do
    -- scrap too low and no defences: plan C. Every count/scrap query must be for team 5.
    w.scrapOf[5] = 5; w.unitCounts["5:bbtowe"] = 0; w.unitCounts["5:bbwpow"] = 0
    F.run(70)
    check(m.plan_c and not m.plan_a, "plan C starts from the team-5 queries")
    for _, c in ipairs(F.callsOf(p[1], "CountUnitsNearObject")) do check(c[4] == 5, "CountUnitsNearObject asks about team 5") end
    check(F.count(p[1], "CountUnitsNearObject") >= 2, "defences were counted")
    for _, c in ipairs(F.callsOf(p[1], "SetPerceivedTeam")) do check(c[3] == 1 or c[3] == 5, "perceived team is 1 or 5, never 2") end
    check(F.count(p[1], "SetPerceivedTeam", REC) >= 1 and w.objects[REC].perceived == 1, "the fleeing recycler is disguised as the humans' side")
    -- stock AddScrap(2, 2) top-ups go to the enemy
    m.plan_c = false
    m.prep_center_towers, m.rigs_ordered, m.rig_check = true, false, 0
    w.scrapOf[5] = 0
    F.run(1)
    check(F.count(p[1], "AddScrap", 5) >= 1 and F.count(p[1], "AddScrap", 2) == 0, "AddScrap(2, 2) tops up team 5")
    guestsPassive(p)
end

-- ------------------------------------------------------------------ Romeski, the SAVs and "the player"
w, p, m = setup(3)
w.scrapOf[5] = 5; w.unitCounts["5:bbtowe"] = 0; w.unitCounts["5:bbwpow"] = 0
F.run(70)
local key = m.key_tank
check(key ~= nil and m.general_spawn and w.objects[key].odf == "svtank" and w.objects[key].team == 1, "Romeski is built on the humans' team")
check(F.count(p[1], "Follow", key) == 1, "Romeski heads for sv_geyser")
heardAll(p, "misns816.wav", 0); heardAll(p, "misns815.wav", 1)
-- the SAVs report in: first ones follow him (misns807, once)
local savs = {}
for i = 1, 3 do savs[i] = F.spawn("savtnk", 1 + (i % 3), 1900 + 30 * i, 100300) end
F.run(2)
check(m.sav1 == savs[1] and m.sav3 == savs[3], "SAV slots fill from any human team")
check(F.count(p[1], "Follow", savs[1]) == 1 and F.heardCount(p[1], "misns807.wav") == 1, "SAVs follow Romeski, announced once")
-- ANY human close to Romeski triggers his arrival, not only the host
F.place(p[1].player, 1793, 100362); F.place(p[2].player, 1830, 100362); F.place(p[3].player, 1800, 100390)
F.run(6)
check(not m.general_message1, "nobody near: no arrival yet")
F.nearTo(p[3].player, key, 60, 0); F.run(5)
check(m.general_message1, "a guest within 150 m of Romeski triggers him")
check(F.count(p[1], "SetObjectiveName", key) == 1 and F.count(p[1], "Attack", key) >= 1, "Romeski is named and attacks the recycler")
-- a guest shoots him: payback goes at the NEAREST human, as a real handle
F.nearTo(p[2].player, key, 40, 0)
w.objects[key].shotBy = p[3].player
F.run(2)
check(m.player_payback and m.key_open, "a guest's shot is the player's shot")
local attack
for _, c in ipairs(F.callsOf(p[1], "Attack")) do if c[2] == key and c[3] ~= REC then attack = c end end
check(attack and attack[3] == p[2].player, "Romeski attacks the nearest human, as a real handle")
check(F.heardCount(p[1], "misns819.wav") == 1, "his protest plays once")
heardAll(p, "misns819.wav", 1)
guestsPassive(p)

-- sav_payback branch: a swapped hostile SAV shoots him; he asks the nearest human for help and follows them
w, p, m = setup(3)
w.scrapOf[5] = 5; w.unitCounts["5:bbtowe"] = 0; w.unitCounts["5:bbwpow"] = 0
F.run(70)
key = m.key_tank
local sav = F.spawn("savtnk", 1, 1900, 100300)
F.run(2)
F.nearTo(sav, key, 100, 0); F.run(11) -- sav_check fires: the SAV attacks; the betrayal shot holds the swap 3 s
check(m.sav_attack and m.sav1_attack, "a SAV that reaches Romeski turns on him")
F.run(4) -- the swap builds the hostile twin
local twin
for _, b in ipairs(F.builds(p[1], 0, "savfury")) do twin = b end
check(#F.builds(p[1], 0, "savs8") == 0, "the stock savs8 is never built; the infected savfury replaces it")
check(twin and twin.team == 5 and twin.where == sav, "the hostile SAV is built in place on team 5")
check(F.count(p[1], "RemoveObject", sav) == 1 and F.count(p[1], "SetIndependence", twin.h) == 1, "the loyal tank is swapped out, the twin is independent")
w.objects[key].shotBy = twin.h
F.run(2)
check(m.sav_payback and m.key_open and not m.player_payback, "a hostile SAV's shot is the SAV payback")
F.nearTo(p[2].player, key, 70, 0)
F.run(4)
check(m.general_message2 and F.heardCount(p[1], "misns810.wav") == 1, "he cries for help when a human is within 130 m")
local follow
for _, c in ipairs(F.callsOf(p[1], "Follow")) do if c[2] == key and c[3] == p[2].player then follow = c end end
check(follow ~= nil, "and follows that human (token translated to a real handle)")
check(follow ~= nil, "and follows that human (token translated to a real handle)")
-- restored unused lines: 805 then 806 (the whole 818 line plus the rebuttal), 809 once before 810, 813 at his death
do
    local function idx(peer, file) for i, f in ipairs(F.lines(peer)) do if f == file then return i end end end
    for i = 1, 3 do
        local q = p[i]
        check(F.heardCount(q, "misns806.wav") == 1 and F.heardCount(q, "misns818.wav") == 0, "806 replaces 818 once on peer " .. i)
        check(idx(q, "misns805.wav") < idx(q, "misns806.wav"), "806 follows 805 on peer " .. i)
        check(F.heardCount(q, "misns809.wav") == 1 and idx(q, "misns809.wav") < idx(q, "misns810.wav"), "809 once, before 810, on peer " .. i)
        check(F.heardCount(q, "misns813.wav") == 0, "no 813 while he lives on peer " .. i)
    end
    w.objects[key].health = 0.05
    F.run(1)
    check(F.heardCount(p[1], "misns812.wav") == 1 and F.heardCount(p[1], "misns809.wav") == 1, "the scream does not repeat 809")
    F.run(6)
    for i = 1, 3 do
        check(F.heardCount(p[i], "misns813.wav") == 1 and idx(p[i], "misns812.wav") < idx(p[i], "misns813.wav"), "813 once after the scream on peer " .. i)
    end
    F.run(20)
    check(F.heardCount(p[1], "misns813.wav") == 1, "813 never repeats")
end

-- a human flying a SAV is never deleted by the betrayal swap
w, p, m = setup(2)
w.scrapOf[5] = 5; w.unitCounts["5:bbtowe"] = 0; w.unitCounts["5:bbwpow"] = 0
F.run(70)
key = m.key_tank
w.objects[p[2].player].odf = "savtnk"
for _, q in ipairs(p) do q.env.AddObject(p[2].player) end
check(m.sav1 == p[2].player, "the guest's own tank fills a SAV slot")
m.sav_attack = true
F.run(6)
check(F.count(p[1], "RemoveObject", p[2].player) == 0 and F.alive(p[2].player), "the human's ship is not removed")
check(#F.builds(p[1], 0, "savfury") == 1 and m.sav1_swap, "the hostile twin is still built")

-- ------------------------------------------------------------------ the betrayal cutscene (presentation only)
-- Romeski's Furies turn: a shared 11 s shot, the swap 3 s in, the soundtrack ducked on every peer.
local function betrayal(n, options)
    local bw, bp, bm = setup(n, options)
    bw.scrapOf[5] = 5; bw.unitCounts["5:bbtowe"] = 0; bw.unitCounts["5:bbwpow"] = 0
    F.run(70)
    local bsavs = {}
    for i = 1, 2 do bsavs[i] = F.spawn("savtnk", 1, 1900 + 30 * i, 100300) end
    F.run(2)
    return bw, bp, bm, bm.key_tank, bsavs
end
local function trigger(bw, bp, bm)
    bm.sav_attack = true
    F.runUntil(function() return F.count(bp[1], "CameraReady") > 0 end, 5)
    return bw.now
end
local function infected(peer) return F.builds(peer, 0, "savfury") end
local function callTimes(peer, name, first)
    local out = {}
    for _, c in ipairs(F.callsOf(peer, name)) do if first == nil or c[2] == first then out[#out + 1] = c end end
    return out
end
do
    local bw, bp, bm, bkey, bsavs = betrayal(3, { music = true })
    local t0 = trigger(bw, bp, bm)
    local shot = F.last(bp[1], "CameraObject")
    check(F.count(bp[1], "CameraReady") == 1 and shot[2] == bkey and shot[3] == -2500 and shot[4] == 1200 and shot[5] == -4500
        and shot[6] == bsavs[1], "shot 1: Romeski's tank, 25 m left, 12 m up, 45 m behind (cm), looking at the SAV column")
    check(#infected(bp[1]) == 0 and F.count(bp[1], "RemoveObject") == 0, "the swap waits for the parade: nothing built at the start")
    F.run(2.5)
    check(#infected(bp[1]) == 0 and F.count(bp[1], "RemoveObject", bsavs[1]) == 0, "still no swap 2.5 s in")
    F.run(1)
    local twins = infected(bp[1])
    check(#twins == 2 and F.count(bp[1], "RemoveObject", bsavs[1]) == 1 and F.count(bp[1], "RemoveObject", bsavs[2]) == 1,
        "both SAVs swap into savfury")
    for _, c in ipairs(callTimes(bp[1], "BuildObject")) do
        if c[3] == "savfury" then check(c.t == t0 + 3, "the swap happens 3 s into the shot") end
    end
    local seen = false
    for _, b in ipairs(twins) do if F.last(bp[1], "CameraObject")[2] == b.h then seen = true end end
    check(seen and F.last(bp[1], "CameraObject")[6] == F.last(bp[1], "CameraObject")[2], "shot 2 cuts to an infected SAV")
    check(F.count(bp[1], "CameraFinish") == 0, "the camera is still held after the swap")
    F.run(8)
    local finish = callTimes(bp[1], "CameraFinish")
    check(#finish == 1 and finish[1].t == t0 + 11, "the hard timer releases the camera at 11 s")
    check(F.count(bp[1], "CameraReady") == 1 and bp[1].camera == 0, "one balanced camera stack")
    for i = 1, 3 do
        local q = bp[i]
        local fades = callTimes(q, "FadeMusic")
        check(#fades == 2 and fades[1][2] == 0.25 and fades[1][3] == 1.5 and fades[2][2] == 1 and fades[2][3] == 3,
            "peer " .. i .. " ducks the music to 0.25 over 1.5 s and restores it over 3 s")
        check(#callTimes(q, "UpdateMusic") >= 40, "peer " .. i .. " advances the fade every update")
        if i > 1 then check(q.camera == 0 and F.count(q, "CameraReady") >= 1, "guest " .. i .. " saw the shot and released it") end
    end
    heardAll(bp, "misns805.wav", 1)
    heardAll(bp, "misns806.wav", 1)
    local fadesBefore = #callTimes(bp[1], "FadeMusic")
    F.run(40)
    check(F.count(bp[1], "CameraReady") == 1 and #callTimes(bp[1], "FadeMusic") == fadesBefore and #infected(bp[1]) == 2,
        "the cutscene fires once")
    for _, q in ipairs(bp) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(5)
    check(F.count(bp[1], "CameraReady") == 1 and #infected(bp[1]) == 2, "a load after the shot does not replay it")
    for i = 2, 3 do check(F.count(bp[i], "BuildObject") == 0 and F.count(bp[i], "Attack") == 0, "guest " .. i .. " builds and orders nothing") end
end
-- the stock rules are untouched: it starts only once, on the first frame the swap condition holds
do
    local bw, bp, bm = betrayal(1)
    F.run(3)
    check(F.count(bp[1], "CameraReady") == 0 and #infected(bp[1]) == 0, "no shot before the betrayal")
    bm.general_spawn = false -- the swap block needs Romeski's arrival
    bm.sav_attack = true; F.run(3)
    check(F.count(bp[1], "CameraReady") == 0, "no shot without the swap condition")
end
-- the target dies: the hard cap still always releases the camera and restores the music
do
    local bw, bp, bm, bkey, bsavs = betrayal(2, { music = true })
    local t0 = trigger(bw, bp, bm)
    F.run(5)
    for _, b in ipairs(infected(bp[1])) do F.kill(b.h) end
    F.run(9)
    local finish = callTimes(bp[1], "CameraFinish")
    check(#finish == 1 and finish[1].t <= t0 + 11 and bp[1].camera == 0, "the infected SAVs die in shot 2: the camera is still released, once")
    check(#callTimes(bp[1], "FadeMusic") == 2 and #callTimes(bp[2], "FadeMusic") == 2, "and the music is restored on both peers")
    check(callTimes(bp[1], "FadeMusic")[2][2] == 1, "restored to full gain")
end
do
    local bw, bp, bm, bkey, bsavs = betrayal(2, { music = true })
    local t0 = trigger(bw, bp, bm)
    F.run(1)
    F.kill(bkey); for _, s in ipairs(bsavs) do F.kill(s) end -- Romeski and the whole column die in shot 1
    F.run(12)
    local finish = callTimes(bp[1], "CameraFinish")
    check(#finish == 1 and finish[1].t <= t0 + 11 and bp[1].camera == 0, "shot 1's subjects die: the camera is still released, once")
    check(#infected(bp[1]) == 0 and #callTimes(bp[1], "FadeMusic") == 2, "no swap of dead SAVs, and the music comes back")
end
-- without EXU (or an EXU without the soundtrack calls) the mission is untouched
do
    local bw, bp, bm, bkey, bsavs = betrayal(2)
    local t0 = trigger(bw, bp, bm)
    F.run(12)
    check(F.count(bp[1], "FadeMusic") == 0 and F.count(bp[1], "UpdateMusic") == 0, "no music call without EXU support")
    check(#infected(bp[1]) == 2 and #callTimes(bp[1], "CameraFinish") == 1, "the shot and the swap run regardless")
    -- an EXU whose soundtrack calls raise must not break it either
    local bw2, bp2, bm2 = betrayal(1)
    bp2[1].modules.exu.FadeMusic = function() error("no soundtrack") end
    bp2[1].modules.exu.UpdateMusic = function() error("no soundtrack") end
    trigger(bw2, bp2, bm2); F.run(12)
    check(#infected(bp2[1]) == 2 and #callTimes(bp2[1], "CameraFinish") == 1, "a failing EXU does not break the mission")
end
-- save/load mid-shot: the beat resumes on its own clock and never replays
do
    local bw, bp, bm, bkey, bsavs = betrayal(3, { music = true })
    local t0 = trigger(bw, bp, bm)
    F.run(1.5)
    for _, q in ipairs(bp) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(0.25)
    local cs = bp[1].env.Save().crcca.r.cs
    check(cs.t0 == t0 and not cs.swapped, "the saved beat keeps its start time")
    check(#infected(bp[1]) == 0, "load does not swap early")
    F.run(1.5)
    check(#infected(bp[1]) == 2, "the swap still lands 3 s after the beat began")
    for _, c in ipairs(callTimes(bp[1], "BuildObject")) do
        if c[3] == "savfury" then check(c.t == t0 + 3, "the swap time did not move after the load") end
    end
    F.run(10)
    local finish = callTimes(bp[1], "CameraFinish")
    check(finish[#finish].t == t0 + 11 and bp[1].env.Save().crcca.r.cs.done, "the hard timer still ends it at 11 s")
    check(#infected(bp[1]) == 2 and F.count(bp[1], "RemoveObject", bsavs[1]) == 1, "no second swap")
    check(F.count(bp[1], "CameraReady") == 2, "the shot is re-armed once after the load, not restarted")
end
-- an old save (no beat state) whose swap is already done never starts a shot
do
    local bw, bp, bm, bkey, bsavs = betrayal(1)
    bm.sav1_swap, bm.sav2_swap = true, true
    bm.sav_attack = true
    F.run(15)
    check(F.count(bp[1], "CameraReady") == 0 and #infected(bp[1]) == 0, "an old mid-betrayal save plays no shot")
end
-- an offline player's skip releases the camera, but the beat's timing continues
do
    local bw, bp, bm, bkey, bsavs = betrayal(1, { music = true })
    local t0 = trigger(bw, bp, bm)
    bw.cancel = true
    F.run(1)
    bw.cancel = false
    check(bp[1].camera == 0 and #callTimes(bp[1], "CameraFinish") == 1, "the skip releases the camera")
    F.run(2.5)
    check(#infected(bp[1]) == 2, "the swap still lands on time after a skip")
    F.run(8)
    check(#callTimes(bp[1], "CameraFinish") == 1 and #callTimes(bp[1], "FadeMusic") == 2, "the end restores the music, with no second release")
end

-- ------------------------------------------------------------------ victory
for _, n in ipairs({1, 3}) do
    w, p, m = setup(n)
    w.scrapOf[5] = 5; w.unitCounts["5:bbtowe"] = 0; w.unitCounts["5:bbwpow"] = 0
    F.run(70)
    check(F.alive(m.key_tank), "Romeski lives")
    F.kill(REC); F.run(12)
    for i = 1, n do
        check(F.count(p[i], "SucceedMission") == 1 and F.last(p[i], "SucceedMission")[3] == "misns8w1.des", "victory once on peer " .. i)
        check(F.heard(p[i], "misns803.wav") and F.heard(p[i], "misns808.wav"), "closing lines on peer " .. i)
        check(F.count(p[i], "FailMission") == 0, "nothing fails a won mission on peer " .. i)
    end
end
w, p, m = setup(2)
F.kill(REC); F.run(12)
for i = 1, 2 do check(F.heard(p[i], "misns814.wav") and F.count(p[i], "SucceedMission") == 1, "short ending on peer " .. i) end
-- out of lives after the win must not fail it
F.run(30)
check(F.count(p[1], "FailMission") == 0, "no failure after the win")

-- ------------------------------------------------------------------ scaling: the retaliation squad
local expected = { [1] = 2, [2] = 3, [3] = 3, [4] = 4 }
for n = 1, 4 do
    w, p, m = setup(n)
    away(p)
    m.plan_a, m.plan_b, m.convoy_start = false, true, true
    F.kill(MUF); F.run(1)
    F.run(2)
    local tanks = F.builds(p[1], 0, "bvtank")
    check(#tanks == expected[n], "humans " .. n .. ": retaliation squad of " .. expected[n] .. ", got " .. #tanks)
    allSafe(p, tanks)
    for _, b in ipairs(tanks) do
        check(b.team == 5, "retaliation tanks are on team 5")
        check(F.count(p[1], "Attack", b.h) == 1, "each carries the recycler attack order")
    end
    local replacement = F.builds(p[1], 0, "bvmuf")[1]
    check(replacement and replacement.team == 5 and replacement.where == "american_spawn", "the replacement factory is built on team 5")
    check(m.new_muf and m.avmuf == replacement.h and F.count(p[1], "Goto", replacement.h) == 1, "and sent to its geyser")
end
-- twelve live scaled units at most (extras are the only things dropped)
do
    w, p, m = setup(4)
    away(p)
    local s = m.crcca
    for i = 1, 12 do s.live[#s.live + 1] = F.spawn("bvtank", 5, 2000 + i, 99000) end
    m.plan_a, m.plan_b, m.convoy_start = false, true, true
    F.kill(MUF); F.run(3)
    check(#F.builds(p[1], 0, "bvtank") == 2, "at the cap only the two primaries arrive")
end
-- a human at the post: an authored alternative entry is used, never a pop-in
do
    w, p, m = setup(2)
    F.place(p[2].player, 2017, 99690 + 100) -- standing at t1post
    m.plan_a, m.plan_b, m.convoy_start = false, true, true
    F.kill(MUF); F.run(3)
    local tanks = F.builds(p[1], 0, "bvtank")
    check(#tanks == 3, "the squad still arrives")
    for _, b in ipairs(tanks) do check(b.where ~= "t1post", "not at the occupied post: " .. tostring(b.where)) end
    allSafe(p, tanks)
end

-- ------------------------------------------------------------------ the restored Choke Point beacon
do
    w, p, m = setup(3)
    m.recycle_move = true
    F.nearTo(REC, "dis_geyser2", 300, 0); F.run(2)
    check(#F.builds(p[1], 0, "spcamr") == 0, "far from dis_geyser2: no beacon")
    F.nearTo(REC, "dis_geyser2", 60, 0); F.run(2)
    local cams = F.builds(p[1], 0, "spcamr")
    check(#cams == 1 and cams[1].team == 1 and cams[1].where == "last_nav_spawn", "the beacon drops at last_nav_spawn on the humans' team")
    check(m.cam4 == cams[1].h and F.count(p[1], "SetObjectiveName", m.cam4) == 1 and F.last(p[1], "SetObjectiveName")[3] == "Choke Point", "and is named Choke Point")
    check(not F.heard(p[1], "misns802.wav"), "misns802 repeats the retreat call and is not replayed")
    F.run(5)
    check(#F.builds(p[1], 0, "spcamr") == 1, "once only")
    local mark = #p[1].calls
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(5)
    check(#F.builds(p[1], mark, "spcamr") == 0, "a load does not rebuild it")
end
do -- a recycler that was never seen outside the radius cannot drop the beacon at once
    w, p, m = setup(2)
    m.crcca.r.chokeFar = nil
    m.recycle_move = true
    F.nearTo(REC, "dis_geyser2", 60, 0); F.run(3)
    check(#F.builds(p[1], 0, "spcamr") == 0 and m.cam4 == nil, "inside the radius from the start: no beacon")
    F.nearTo(REC, "dis_geyser2", 300, 0); F.run(2)
    F.nearTo(REC, "dis_geyser2", 60, 0); F.run(2)
    check(#F.builds(p[1], 0, "spcamr") == 1 and m.cam4 ~= nil, "once it has been far, coming back inside drops it")
end
do -- the map without the beacon path
    w, p, m = setup(2, { setup = function(world) world.missingPaths = { last_nav_spawn = true } end })
    m.recycle_move = true
    F.nearTo(REC, "dis_geyser2", 60, 0); F.run(3)
    check(#F.builds(p[1], 0, "spcamr") == 0 and m.cam4 == nil, "no beacon path: restoration skipped")
end
do -- offline too
    w, p, m = setup(1)
    m.recycle_move = true
    F.nearTo(REC, "dis_geyser2", 60, 0); F.run(2)
    check(#F.builds(p[1], 0, "spcamr") == 1, "the beacon is restored offline as well")
end

-- ------------------------------------------------------------------ distance to "the player"
do
    w, p, m = setup(3)
    away(p)
    local wrapped = p[1].runtime
    check(wrapped ~= nil, "runtime is reachable")
    -- MUF convoy warning: the nearest human decides, wherever the player-token sits in the call
    m.plan_a, m.plan_b, m.convoy_start, m.warning = false, true, true, false
    m.muf_warning = 0
    F.nearTo(MUF, "dis_geyser1", 50, 0)
    F.nearTo(p[3].player, MUF, 40, 0) -- a guest next to the factory
    F.run(2)
    check(m.warning and not F.heard(p[1], "misns801.wav"), "a human within 100 m of the factory cancels the warning")
    m.warning = false; m.muf_warning = 0
    F.place(p[3].player, 1900, 100362)
    F.run(2)
    check(m.warning and F.heard(p[1], "misns801.wav") and #F.builds(p[1], 0, "spcamr") == 1, "otherwise the Choke Point beacon and objective follow")
end

-- ------------------------------------------------------------------ leader leaves, save/load
w, p, m = setup(3)
for i = 2, 3 do p[i].env.DeletePlayer(1) end
F.run(3)
for i = 2, 3 do check(F.count(p[i], "FailMission") == 1, "the mission fails for guest " .. i .. " when the leader leaves") end
check(F.count(p[1], "FailMission") == 0, "the leader itself keeps playing")

w, p, m = setup(4)
F.run(30)
local before = F.count(p[1], "SetScrap")
for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
F.connect(); F.run(5)
check(F.count(p[1], "SetScrap") == before and F.count(p[1], "BuildObject") == 4, "load does not rerun the first frame")
w.scrapOf[5] = 5; w.unitCounts["5:bbtowe"] = 0; w.unitCounts["5:bbwpow"] = 0
F.run(70)
F.kill(REC); F.run(12)
for i = 1, 4 do check(F.count(p[i], "SucceedMission") == 1, "the loaded mission still ends once on peer " .. i) end

-- ------------------------------------------------------------------ weather: absent, present, broken
local function titan(record, mode)
    return function(peer)
        local V = { Seed = 777, Initialized = true, log = {} }
        function V.Init(o) peer.titanInit = o; record("TitanInit", o.authority, o.send ~= nil, o.startLevel, o.targetLevel); if mode == "initfail" then error("boom") end end
        function V.Update(dt)
            if peer.titanInit and peer.titanInit.authority and peer.titanInit.send and not V.sent then
                V.sent = true; peer.titanInit.send("TitanRoll", 3, 0.5, 60)
            end
            if mode == "updatefail" then error("update boom") end
        end
        function V.AnnounceState() record("TitanAnnounce") end
        function V.ApplyNetEvent(op, ...) record("TitanEvent", op, ...) end
        function V.SetTargetLevel(n) record("TitanLevel", n) end
        function V.Roll(duration, strength) record("TitanRollCall", duration, strength) end
        function V.SkyState() return { storm = 0, bank = 0 } end
        function V.OnObjectCreated(h) record("TitanCreated", h) end
        function V.Save() return { saved = true } end
        function V.Load(s) record("TitanLoad", s and s.saved) end
        function V.Shutdown() record("TitanShutdown") end
        return V
    end
end
do
    w, p, m = setup(3)
    check(F.count(p[1], "EnvironmentInit") == 0 and m.start_done, "no weather module: the mission runs and touches no Environment")
    local printed = false
    for _, c in ipairs(p[1].calls) do if c[1] == "print" and tostring(c[2]):find("weather disabled", 1, true) then printed = true end end
    check(printed, "missing weather is logged, not fatal")
end
do
    -- the shipped sites table is EMPTY (no pools); weather must still start
    local sites = dofile("Scripts/CRTitanSitesS8.lua")
    check(#sites.pools == 0 and sites.mission == "misns8", "the generated Titan sites for this map have no pools")
    local weather = { module = function(peer, record) return titan(record)(peer) end, sites = sites }
    w, p, m = setup(3, { weather = weather })
    check(F.count(p[1], "TitanInit", true) == 1 and F.last(p[1], "TitanInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.last(p[1], "TitanInit")[4] == 2 and F.last(p[1], "TitanInit")[5] == 2, "it opens on the Hazy rung")
    check(F.count(p[2], "TitanInit", false) == 1, "guests render only (not the authority)")
    check(F.count(p[1], "TitanAnnounce") == 1 and F.count(p[2], "TitanAnnounce") == 0, "the leader announces its weather state once")
    check(F.count(p[1], "EnvironmentInit") == 1, "Titan lighting is initialised")
    for i = 1, 3 do check(F.count(p[i], "WeatherSensors", "Titan") == 1, "the sky follows the haze on peer " .. i) end
    for i = 2, 3 do
        local e = F.last(p[i], "TitanEvent")
        check(e and e[2] == "TitanRoll" and e[3] == 3, "weather events reach guest " .. i)
    end
    check(p[1].env.Save().crcca.weatherSeed == 777, "the weather seed is saved with the mission")
    check(F.count(p[1], "TitanCreated") > 0, "new objects are offered to the weather")
    -- beats follow the mission
    check(F.count(p[1], "TitanLevel") == 0, "no beat before the mission moves")
    m.convoy_start = true; F.run(2)
    check(F.count(p[1], "TitanLevel", 3) == 1, "the convoy raises the weather to drizzle")
    m.recycle_pack = true; F.run(2)
    check(F.count(p[1], "TitanLevel", 4) == 1 and F.count(p[1], "TitanRollCall", 70) == 1, "the recycler's flight brings the shroud and a roll")
    m.sav_attack = true; F.run(2)
    check(F.count(p[1], "TitanRollCall", 90) == 1, "the betrayal brings the heavy roll")
    m.game_over = true; F.run(2)
    check(F.count(p[1], "TitanLevel", 2) == 1, "victory eases the weather")
    F.run(3)
    check(F.count(p[1], "TitanLevel") == 3 and F.count(p[1], "TitanRollCall") == 2, "each beat fires once")
    for i = 2, 3 do check(F.count(p[i], "TitanLevel") == 0 and F.count(p[i], "TitanRollCall") == 0, "guests never run beats") end
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "TitanShutdown") >= 1 and F.count(p[1], "TitanLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(p[1], "TitanInit") == 2 and F.count(p[1], "WeatherSensors", "Titan") == 2, "the weather and sky binding re-initialise after a load")
    check(F.count(p[1], "TitanLevel") == 3, "saved beats are not replayed after a load")
end
do -- CR addition: a Black Dog APC attacks a close enemy craft (aiCore APCManager style), leader only, Save/Load safe
    w, p, m = setup(2)
    local apc = F.spawn("bvapc", 5)
    w.objects[apc].command = 3; F.run(6)
    check(F.count(p[1], "Attack", apc) == 0, "an APC already on its run with no enemy near is left alone")
    w.objects[p[2].player].pos = {x = 5000, y = 0, z = 5000} -- far from both bases
    F.nearTo(apc, p[2].player, 60, 0); F.run(6)
    check(F.count(p[1], "Attack", apc) == 1 and F.last(p[1], "Attack")[3] == p[2].player, "an APC 60 m from a guest attacks that guest")
    check(F.count(p[2], "Attack", apc) == 0, "guests never retarget the APC")
    w.objects[apc].target = p[2].player; F.run(12)
    check(F.count(p[1], "Attack", apc) == 1, "an APC already attacking that unit is not re-ordered")
    w.objects[apc].target = nil
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(5) -- one retarget pass (the stub Attack never sets a target)
    check(F.count(p[1], "Attack", apc) == 2 and F.last(p[1], "Attack")[3] == p[2].player, "the tracked APC survives a Save/Load")
    w.objects[apc].command = 11; F.run(12)
    check(F.count(p[1], "Attack", apc) == 2, "an APC going home to reload is left alone")
    w.objects[apc].command = 0
    F.nearTo(apc, p[2].player, 200, 0); F.run(6)
    check(F.count(p[1], "Attack", apc) == 3 and F.last(p[1], "Attack")[3] == m.ccarecycle, "an idle APC with no enemy in 120 m goes back to the recycler")
    local own = F.spawn("bvapc", 1); F.nearTo(own, apc, 30, 0); F.run(12)
    check(F.count(p[1], "Attack", own) == 0, "a human-team APC is never ordered by the script")
    local tank = F.spawn("bvtank", 5); F.nearTo(tank, p[2].player, 60, 0); F.run(12)
    check(#p[1].env.Save().crcca.r.apcs == 2, "only bvapc is tracked")
    F.kill(apc); F.run(6)
    check(#p[1].env.Save().crcca.r.apcs == 1, "dead APCs are dropped")
end
do -- sites module missing: no weather, never an error
    w, p, m = setup(2, { weather = { module = function(peer, record) return titan(record)(peer) end } })
    check(F.count(p[1], "TitanInit") == 0 and m.start_done, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    w, p, m = setup(2, { weather = { module = function(peer, record) return titan(record, mode)(peer) end, sites = {} } })
    F.kill(REC); F.run(12)
    check(F.count(p[1], "SucceedMission") == 1 and F.count(p[2], "SucceedMission") == 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

do -- CR addition: the breakthrough beat (counterattack, walker strike, allied Soviet waves), leader only, Save/Load safe
    local function on(team, odf)
        local out = {}
        for _, b in ipairs(F.builds(p[1], 0, odf)) do if b.team == team then out[#out + 1] = b end end
        return out
    end
    for n = 1, 2 do
        w, p, m = setup(n); away(p)
        local extra = math.floor(n / 2)
        m.plan_a, m.plan_b, m.plan_c = false, false, true
        F.run(3)
        local raz, light = on(5, "bvhraz"), on(5, "bvltnk")
        check(#raz == 3 + extra and #light == 3, "humans " .. n .. ": counterattack of " .. (3 + extra) .. " Razors and 3 light tanks")
        allSafe(p, raz); allSafe(p, light)
        for _, b in ipairs(raz) do
            check(b.team == 5 and F.count(p[1], "Attack", b.h, "svrecycle") == 1, "the counterattack is team 5 and goes for the CCA Recycler")
        end
        check(F.count(p[1], "BuildObject") > 0 and #on(7, "svfigh") == 0, "no allied wave before 60 s")
        F.run(60)
        local figh = on(7, "svfigh")
        check(#figh == 2 + extra, "humans " .. n .. ": " .. (2 + extra) .. " allied fighters")
        for _, b in ipairs(figh) do
            check(b.team == 7 and F.count(p[1], "Defend2", b.h, "svrecycle") == 1, "allies are team 7 and guard the CCA Recycler")
        end
        check(F.count(p[1], "UnAlly", 5, 7) >= 1 and F.count(p[1], "UnAlly", 7, 5) >= 1, "the Black Dogs and the allies are enemies")
        heardAll(p, "misn1606.wav")
        for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
        F.connect(); F.run(180)
        check(#on(7, "svtank") == 2 + extra, "the tank wave arrives at 240 s, after a Save/Load")
        heardAll(p, "misn1607.wav")
        -- The counterattack is dead by then; alive, it would hold the runtime's live cap and drop the walker extra.
        for _, b in ipairs(raz) do F.kill(b.h) end
        for _, b in ipairs(light) do F.kill(b.h) end
        F.run(120)
        check(#on(5, "bvwalk") == 3 + extra, "the Black Dog walker strike follows at 360 s")
        F.run(40)
        check(#on(7, "svwalk") == 2 + extra, "the allied walker wave arrives at 390 s")
        heardAll(p, "misn1608.wav")
        F.run(600)
        check(#on(7, "svfigh") == 2 + extra and #on(5, "bvhraz") == 3 + extra, "every wave is one-shot")
        guestsPassive(p)
    end
    w, p, m = setup(1); away(p)
    F.run(30)
    check(#on(5, "bvhraz") == 0 and #on(7, "svfigh") == 0, "nothing before the Black Dog base breaks")
end

print("misns8 co-op: " .. checks .. " checks passed")
