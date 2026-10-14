-- Run from the repository root: lua5.1 Tools/Test-Misn14.lua
-- Offline (single-player) behaviour of the reworked misn14 (Concept C, Docs/MISN14_COOP.md): the real
-- CRCoop runs with single-player semantics, so every check below is the DLL's own flow plus the documented
-- CR changes (teams 5/6/7, the NSDF Fury squad, the rogue onslaught, the shipped-1.5 restorations, the
-- restored VO, the Titan weather hook). Multi-peer behaviour: Test-Misn14Coop.lua / Test-Misn14Presentation.lua.
assert(_VERSION == "Lua 5.1", "run with Lua 5.1")
local F = dofile("Tools/Misn14Fixture.lua")
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

local W, host
local function boot(options)
    W = F.reset()
    host = F.makePeer(1, 1, false, options)
    return host
end
local function M() return host.env.Save() end
local function squad() return M().fury_squad end
-- Plays the intro (27 s) and returns the time the objective appeared.
local function throughIntro()
    F.runUntil(function() return M().objective_time ~= nil end, 60)
    return M().objective_time
end
local function toPhase(phase, limit)
    F.runUntil(function() return M().fury_phase == phase end, limit or 400)
end

-- ------------------------------------------------------------ chunk load, first frame
boot()
check(F.count(host, "SetAIControl", 5) == 1 and F.index(host, "SetAIControl") <= host.chunkCalls,
    "the CCA strategic AI is enabled once at chunk load, on team 5")
check(F.count(host, "SetAIControl", 2) == 0, "no DLL team-2 AI control survives")
check(F.count(host, "DisableStartingRecycler") == 0, "offline keeps the native recycler rules")
F.tick()
check(F.count(host, "SetAIP") == 1 and F.last(host, "SetAIP")[2] == "misn14.aip" and F.last(host, "SetAIP")[3] == 5,
    "SetAIP names the CCA team (shipped 1.5 passes the team)")
check(F.count(host, "AddPilot", 5) == 1 and F.count(host, "SetScrap", 5) == 1 and F.count(host, "SetScrap", 1) == 1,
    "the DLL's CCA pilots/scrap moved to team 5; the shared base keeps 30 scrap")
check(F.count(host, "SetMaxHealth", "sbbarr0_i76building") == 1, "the scientists' barracks is kept alive")
check(F.heard(host, "misn1401.wav") and F.count(host, "CameraPath", "cam_path1") == 1, "the stock intro runs")
local built = F.builds(host, 0, "avsav14")
check(#built == 2, "offline: one dormant pair of NSDF Furies")
for _, b in ipairs(built) do
    check(b.team == 1, "the dormant squad is on the player's team")
    check(F.count(host, "Stop", b.h) == 1 and F.last(host, "Stop")[3] == 1, "dormant Furies are locked (priority 1)")
    local d = math.sqrt((F.posOf(b.h).x - 2573.8) ^ 2 + (F.posOf(b.h).z - 99396.2) ^ 2)
    check(d > 40 and d < 140, "the Fury pad is beside the Texas")
end
check(#F.builds(host, 0, "hvsat") == 0 and #F.builds(host, 0, "hvsav") == 0, "no rogue Fury at the start")

-- ------------------------------------------------------------ intro -> beacon 1
local objective = throughIntro()
check(objective > 26 and objective < 28.5, "intro is 12 s + 15 s as in the DLL")
check(F.count(host, "AddObjective", "misn1401.otf") == 1, "stock objective")
check(M().alien_time > objective + 419 and M().alien_time < objective + 421, "first Fury wave 420 s after the intro")
F.run(16)
check(F.heard(host, "misn1416.wav"), "beacon 1 call")
local guys = F.builds(host, 0, "aspilo")
check(#guys == 3, "three survivors at beacon 1")
for _, g in ipairs(guys) do
    check(g.team == 7, "survivors are on the support team 7")
    local i, d = F.index(host, "SetIndependence", g.h), F.index(host, "Defend", g.h)
    check(i and d and i < d, "shipped 1.5: SetIndependence(guy, 0) before Defend")
    check(host.calls[i][3] == 0 and host.calls[d][3] == 1, "independence 0, Defend priority 1")
end
check(F.count(host, "SetObjectiveName", M().beacon1) == 1 and F.count(host, "SetObjectiveOn", M().beacon1) == 1,
    "beacon 1 marker")

-- ------------------------------------------------------------ activation scene
W.audioBusy = true -- the earlier line is still talking: the scene's lines queue behind it
toPhase("activating", 60)
check(W.now >= objective + 40 - 0.3 and W.now < objective + 41, "activation 40 s after the objective")
local lines = F.lines(host)
check(lines[#lines - 2] == "misn1402.wav" and lines[#lines - 1] == "misn1423.wav" and lines[#lines] == "misn1424.wav",
    "Collins 1402 then Buzz 1423/1424")
check(F.count(host, "Queue", "misn1423.wav") == 1 and F.count(host, "Queue", "misn1424.wav") == 1,
    "the scene's later lines queue instead of cutting each other off")
W.audioBusy = false
F.run(1)
local lead = built[1].h
check(F.count(host, "CameraObject", lead) > 0, "the scene films the Fury squad")
toPhase("control", 20)
check(F.count(host, "Follow", built[1].h) == 1 and F.last(host, "Follow")[3] == host.player
    and F.last(host, "Follow")[4] == 0, "handover: each Fury follows its human at priority 0 (commandable)")
check(host.camera == 0, "the camera stack is balanced after the scene")
F.tick()
check(F.count(host, "AddObjective", "misn14_furies") == 1 and F.last(host, "AddObjective")[3] == "green",
    "the Fury squad objective appears")

-- ------------------------------------------------------------ loss of control
toPhase("losing", 80)
check(F.heard(host, "misn1425.wav"), "Buzz: do you have control?")
local ccaTarget = "svscav54_scavenger"
toPhase("rogue", 10)
for i, b in ipairs(built) do
    check(F.team(b.h) == 6, "the squad turns to the Fury team")
    local attack
    for _, c in ipairs(F.callsOf(host, "Attack")) do if c[2] == b.h then attack = c end end
    check(attack and attack[4] == 1, "rogue Furies are ordered to attack (priority 1)")
    if i % 2 == 1 then
        check(F.team(attack[3]) == 5, "odd squad slots turn on the CCA")
    else
        check(attack[3] == host.player or F.team(attack[3]) == 1, "even squad slots turn on the NSDF")
    end
end
check(F.heard(host, "misn1426.wav"), "Collins: something's not right, proceed with the rescue")
F.tick()
check(F.count(host, "UpdateObjective", "misn14_furies") == 1 and F.last(host, "UpdateObjective")[3] == "red",
    "the objective turns red")
check(host.camera == 0, "camera balanced after the loss scene")
-- Retargeting: kill the squad's targets; a new one is picked within FURY_RETARGET_S.
local before = F.count(host, "Attack", built[1].h)
for _, c in ipairs(F.callsOf(host, "Attack")) do if c[2] == built[1].h and W.objects[c[3]] then F.kill(c[3]) end end
F.run(7)
check(F.count(host, "Attack", built[1].h) > before, "a rogue Fury picks a new target when its own dies")
check(F.team(ccaTarget) == 5 or not F.alive(ccaTarget), "no CCA craft changed side yet")

-- ------------------------------------------------------------ 1427 nag
F.runUntil(function() return F.heard(host, "misn1427.wav") end, 200)
check(W.now - M().fury_rogue_time > 119, "1427 waits 120 s after the squad turned")
check(F.heardCount(host, "misn1427.wav") == 1, "1427 once")
F.runUntil(function() return F.heard(host, "misn1420.wav") end, 200)
check(W.now - M().beacon_seen[1] > 179, "1420 nags 180 s after a beacon appeared")

-- ------------------------------------------------------------ the first wave: no pop-in near the player
local mark = #host.calls
F.runUntil(function() return M().wave_count >= 1 end, 400)
local wave = F.builds(host, mark)
local furies = 0
for _, b in ipairs(wave) do
    if b.odf == "hvsav" then
        furies = furies + 1
        check(b.team == 6, "wave Furies are on team 6")
        local pos = F.posOf(b.h)
        local d = math.sqrt((pos.x - F.posOf(host.player).x) ^ 2 + (pos.z - F.posOf(host.player).z) ^ 2)
        check(d >= 400, "no Fury is built within 400 m of the player")
        check(b.where ~= "alien2" and b.where ~= "alien4", "the drop-zone points are watched")
    end
end
check(furies == 3, "offline wave: three hvsav, as in the DLL")
check(F.heard(host, "misn1403.wav"), "the alien warning on the first wave")
-- Every point watched: the wave waits.
boot()
F.tick()
throughIntro()
local save = M()
check(save.alien_time ~= nil, "schedule set")
-- Park the player by every point (the corners are far, so place a mock player at each candidate).
W.peers[1].env.Save().alien_time = W.now -- force the wave now
-- With the player near alien1 the triplet substitutes another point.
F.nearTo(host.player, "alien1", 10, 0)
mark = #host.calls
F.tick()
for _, b in ipairs(F.builds(host, mark, "hvsav")) do
    check(b.where ~= "alien1" and b.where ~= "alien3" and b.where ~= "alien5", "points near the player are skipped")
end

-- ------------------------------------------------------------ wave cap, Fury Tanks, surrender
boot()
F.tick()
throughIntro()
for n = 1, 4 do
    M().alien_time = W.now
    F.tick()
    check(M().wave_count == n, "wave " .. n .. " counted")
end
local all = F.builds(host, 0)
local tanks = 0
for _, b in ipairs(all) do if b.odf == "hvsat" then tanks = tanks + 1 end end
check(tanks == 1, "Fury Tanks join from wave 4 (one offline)")
local live = 0
for _, b in ipairs(all) do if (b.odf == "hvsav" or b.odf == "hvsat") and F.alive(b.h) then live = live + 1 end end
check(live == 12, "3+3+3 then wave 4 (3 hvsav + 1 hvsat) trimmed to the cap of 12, got " .. live)
check(tanks == 1, "the cap keeps the Fury Tank when it trims a wave")
M().alien_time = W.now
mark = #host.calls
F.tick()
check(#F.builds(host, mark) == 0 and M().wave_count == 5, "a capped wave still counts (the story never stalls)")
local killed = 0
for _, b in ipairs(all) do
    if b.odf == "hvsav" and killed < 2 then F.kill(b.h); killed = killed + 1 end
end
M().alien_time = W.now
mark = #host.calls
F.tick()
check(#F.builds(host, mark) == 2 and M().wave_count == 6, "two dead Furies make room for two in the next wave")

-- Surrender happened at wave 3 (wave_count > 2).
check(M().cca_surrender, "surrender after the third wave")
check(F.team("svscav54_scavenger") == 0 and F.team("svrecy-1_recycler") == 0, "CCA craft go to team 0")
for _, label in ipairs({"sbbarr0_i76building", "sblpow1_powerplant", "sblpow55_powerplant",
    "sbtowe0_turret", "sbtowe1_turret", "sbtowe55_turret", "sbtowe56_turret"}) do
    check(F.team(label) == 7, "surrendered " .. label .. " joins team 7 (power plants as in shipped 1.5)")
end
check(F.team("avrecy-1_recycler") == 1 and F.team(host.player) == 1, "human craft untouched")
for _, b in ipairs(all) do
    if b.odf == "hvsav" then check(F.team(b.h) == 6, "Furies untouched by the surrender loop") end
end
check(F.heard(host, "misn1404.wav") and F.heard(host, "misn1405.wav"), "mayday and the trick line")

-- CcaBroken: the CCA recycler dies after the squad turned -> early surrender.
boot()
F.tick()
throughIntro()
toPhase("rogue", 300)
check(not M().cca_surrender, "no surrender while the CCA stands")
F.kill("svrecy-1_recycler")
F.tick()
check(M().cca_surrender and M().wave_count == 0, "the Fury onslaught breaking the CCA forces the surrender")
-- ...but not before the squad turned.
boot()
F.tick()
throughIntro()
F.kill("svmuf0_factory")
F.run(2)
check(not M().cca_surrender, "a player-destroyed factory before the Furies turn is not a surrender")

-- ------------------------------------------------------------ rescue, the win path
boot()
F.tick()
throughIntro()
F.run(16)
local apc = F.spawn("avapc", 1, 2400, 99300)
check(M().found and M().apc == apc, "a human-team APC is tracked")
local enemyApc = F.spawn("avapc", 5, 2400, 99300)
check(M().apc == apc, "a CCA APC is never tracked")
F.nearTo(apc, "rescue1", 50, 0)
F.tick()
check(M().rescue1 and F.count(host, "CameraObject", apc) > 0, "APC within 100 m starts rescue 1 and its camera")
F.run(26)
check(F.heard(host, "misn1417.wav"), "1417 after rescue 1")
F.run(11)
local beacon2 = M().beacon2
check(beacon2 ~= nil, "beacon 2 spawns 10 s later")
local razor = M().guy1
local named = false
for _, c in ipairs(F.callsOf(host, "SetObjectiveName")) do if c[2] == razor and c[3] == "Razor Two" then named = true end end
check(named, "Razor Two named")
F.nearTo(apc, "rescue2", 0, 0)
F.run(27)
check(F.heard(host, "misn1418.wav"), "Razor Two's 1418")
F.run(11)
F.nearTo(apc, "rescue3", 0, 0)
F.run(27)
check(F.heard(host, "misn1419.wav") and M().rescue3, "all three rescues")
F.nearTo(apc, "avrecy-1_recycler", 30, 0)
F.nearTo(host.player, "avrecy-1_recycler", -800, -800) -- far from the fighting, so the base shot plays
for _ = 1, 5 do M().alien_time = W.now; F.tick() end
check(M().wave_count == 5 and M().gen_message and M().rescue_message, "waves 4/5 bring Collins and the CCA rescue")
check(F.heard(host, "misn1406.wav") and F.heard(host, "misn1407.wav") and F.heard(host, "misn1408.wav"), "1406-1408")
local rescueName = false
for _, c in ipairs(F.callsOf(host, "SetObjectiveName")) do
    if c[2] == "sbbarr0_i76building" and c[3] == "Rescue CCA" then rescueName = true end
end
check(rescueName and F.count(host, "SetObjectiveOn", "sbbarr0_i76building") == 1, "Rescue CCA marker")
F.nearTo(apc, "sbbarr0_i76building", 100, 0)
F.tick()
check(M().pick_up and M().apc == apc, "pickup")
F.run(16)
check(F.heard(host, "misn1410.wav"), "ready to go")
F.nearTo(apc, "avrecy-1_recycler", 150, 0)
F.tick()
check(M().won and F.count(host, "SucceedMission") == 1 and F.last(host, "SucceedMission")[3] == "misn14w1.des",
    "win: APC within 300 m of the Texas")
check(F.heard(host, "misn1411.wav"), "victory line")

-- ------------------------------------------------------------ failures
boot()
F.tick()
throughIntro()
F.run(16)
F.kill(M().guy2)
F.tick()
check(M().lost and F.last(host, "FailMission")[3] == "misn14l2.des" and F.heard(host, "misn1421.wav"),
    "a survivor dies: fail l2")
boot()
F.tick()
F.kill("avrecy-1_recycler")
F.tick()
check(M().lost and F.last(host, "FailMission")[3] == "misn14l1.des" and F.heard(host, "misn1414.wav"),
    "the Texas dies: fail l1")

-- ------------------------------------------------------------ Titan weather hook
local seen = {}
local titan = {MissionHook = function(event, a)
    seen[#seen + 1] = event .. (type(a) == "string" and (":" .. a) or "")
    if event == "init" then seen.init = a end
    if event == "save" then return {saved = true} end
end}
boot({titan = titan})
F.tick()
check(seen.init and seen.init.authority == true and seen.init.mission == "misn14" and seen.init.send == nil,
    "offline: the hook is initialised as authority with no network send")
local has = {}
for _, s in ipairs(seen) do has[s] = true end
check(has["beat:start"] and has["update"], "start beat and per-frame updates")
throughIntro()
toPhase("rogue", 300)
has = {}
for _, s in ipairs(seen) do has[s] = true end
check(has["beat:activation"] and has["beat:rogue"], "activation and rogue beats")
check(M().titanWeather and M().titanWeather.saved, "the director's save is kept in M")
-- A broken director never stops the mission.
boot({titan = {MissionHook = function() error("boom") end}})
F.tick()
throughIntro()
check(M().titanHookError and F.count(host, "print") >= 1, "a failing hook is caught and logged once")
toPhase("control", 120)
-- An absent director: require fails quietly.
boot()
F.tick()
check(M().start_done, "absent CRTitanWeather is fine")

-- ------------------------------------------------------------ save/load
boot()
F.tick()
throughIntro()
toPhase("control", 100)
local saved = host.env.Save()
host.env.Load(saved)
F.run(80)
check(M().fury_phase == "losing" or M().fury_phase == "rogue", "the Fury sequence continues after a load")

print(string.format("misn14 offline: %d checks passed", checks))
