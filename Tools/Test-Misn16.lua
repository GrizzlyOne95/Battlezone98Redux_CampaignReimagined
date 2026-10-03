-- Stock-host behavioral tests; run from the repository root with Lua 5.1.
local checks = 0
local function eq(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end
local function yes(value, label) eq(not not value, true, label) end

local W
local function event(name, ...)
    W.events[#W.events + 1] = {name, ...}
end
local function events(name)
    local out = {}
    for _, e in ipairs(W.events) do if e[1] == name then out[#out + 1] = e end end
    return out
end
local function object(odf, team, label)
    W.id = W.id + 1
    local h = W.id
    W.objects[h] = {odf = odf, team = team, alive = true, valid = true,
        pos = {x = h, y = 0, z = h * 2}}
    if label then W.labels[label] = h end
    return h
end
local function requireHandle(h)
    assert(IsValid(h), "invalid handle reached native stub: " .. tostring(h))
end
function IsValid(h) return W.objects[h] ~= nil and W.objects[h].valid end
function IsAlive(h) requireHandle(h); return W.objects[h].alive end
function GetTime() return W.time end
function GetPlayerHandle() return W.player end
function GetHandle(label) return W.labels[label] end
function GetPosition(h) requireHandle(h); return W.objects[h].pos end
function GetTeamNum(h) requireHandle(h); return W.objects[h].team end
function IsOdf(h, odf) requireHandle(h); return W.objects[h].odf == odf end
function GetNearestEnemy(h) requireHandle(h); event("nearest", h); return W.enemy end
function GetDistance(a, b) requireHandle(a); requireHandle(b); return W.distance end
function BuildObject(odf, team, where)
    assert(where ~= nil, "nil spawn location")
    if type(where) == "number" then requireHandle(where) end
    local h = object(odf, team)
    event("build", odf, team, where, h)
    AddObject(h) -- exercise synchronous engine callback / newbie tracking
    return h
end
function Attack(me, target, priority)
    requireHandle(me); requireHandle(target); event("attack", me, target, priority)
end
function Goto(me, where, priority)
    requireHandle(me)
    if type(where) == "number" then requireHandle(where) end
    event("go_to", me, where, priority)
end
function Defend(h, priority) requireHandle(h); event("defend", h, priority) end
function SetObjectiveName(h, name) requireHandle(h); event("name", h, name) end
function AudioMessage(name)
    W.message = W.message + 1
    local m = "message" .. W.message
    W.messages[m] = false
    event("audio", name, m)
    return m
end
function IsAudioMessageDone(m)
    assert(W.messages[m] ~= nil, "invalid message reached native stub")
    return W.messages[m]
end
function SetScrap(team, amount) event("scrap", team, amount) end
function SetAIP(name) event("aip", name) end
function ClearObjectives() event("clear") end
function AddObjective(name, color, duration) event("objective", name, color, duration) end
function CameraReady() event("ready"); return true end
function CameraPath(path, height, speed, target)
    requireHandle(target); event("path", path, height, speed, target)
end
function CameraCancelled() return W.cancel end
function CameraFinish() event("finish"); return true end
function CameraObject(base, right, up, forward, target)
    requireHandle(base); requireHandle(target)
    event("camera", base, right, up, forward, target)
end
function SucceedMission(time, desc) event("win", time, desc) end
function FailMission(time, desc) event("lose", time, desc) end

local function fresh(startTime)
    W = {time = startTime or 0, id = 0, message = 0, events = {}, objects = {},
        labels = {}, messages = {}, cancel = false, distance = 151, random = {}}
    W.player = object("avtank", 1)
    object("avrecy", 1, "avrecy0_recycler")
    object("hq", 2, "alien_hq")
    object("hangar", 2, "alien_hangar")
    object("avmuf", 1, "avmuf26_factory")
    for _, label in ipairs({"apcamr12_camerapod", "apcamr15_camerapod",
            "apcamr13_camerapod", "apcamr11_camerapod"}) do object("apcamr", 1, label) end
    for i = 0, 3 do object("sbtowe", 2, "sbtowe" .. i .. "_turret") end
    for i = 0, 2 do object("hvsat", 2, "hvsat" .. i .. "_wingman") end
    math.random = function(lo, hi)
        local value = table.remove(W.random, 1) or lo
        assert(value >= lo and value <= hi, "bad test random choice")
        return value
    end
    dofile("Scripts/misn16.lua")
    Start()
    return Save()
end
local function step(time)
    W.time = time
    Update(0.1)
end
local function boot()
    fresh()
    step(0)
    return Save()
end
local function quiet()
    local m = boot()
    m.camera1 = false
    m.alien_wave = 99999
    m.alien_wave1 = 99999
    W.events = {}
    return m
end
local function remove(h)
    W.objects[h].valid = false
    W.objects[h].alive = false
end
local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

-- Startup, relative timers, literal API parameters, and opening-camera exits.
local m = fresh(30)
eq(m.counter_strike2, 999999, "Setup initial second strike sentinel")
eq(m.wave_gap, 150, "Setup wave gap")
eq(m.rcount, 0, "Setup reinforcement count")
step(30)
m = Save()
eq(m.next_reinforcement, 150, "first reinforcement relative deadline")
eq(m.alien_wave, 90, "first SAV relative deadline")
eq(m.alien_wave1, 120, "first SAT relative deadline")
eq(m.cam_time1, 50, "opening camera relative deadline")
eq(m.rtype, 1, "initial random type 1")
eq(events("audio")[1][2], "misn1601.wav", "first briefing")
eq(events("audio")[2][2], "misn1602.wav", "second briefing")
eq(events("scrap")[1][2], 1, "scrap team")
eq(events("scrap")[1][3], 50, "scrap quantity")
eq(events("aip")[1][2], "misn16.aip", "strategic AI plan")
eq(#events("clear"), 1, "objectives cleared")
eq(events("objective")[1][2], "misn1601.otf", "original objective")
eq(events("objective")[1][3], "white", "objective color")
eq(events("objective")[1][4], nil, "source default objective duration")
eq(#events("name"), 4, "all four beacon names")
for i, name in ipairs({"NW Geyser", "Foothill Geysers", "Geyser Site", "Alien HQ"}) do
    eq(events("name")[i][3], name, "beacon name " .. i)
end
eq(#events("defend"), 3, "all three initial SATs defend")
for _, e in ipairs(events("defend")) do eq(e[3], 1, "defend priority") end
eq(events("path")[1][2], "camera_path1", "opening camera path")
eq(events("path")[1][3], 4000, "opening height")
eq(events("path")[1][4], 500, "opening speed")
eq(events("path")[1][5], m.base2, "opening target")
step(50)
eq(m.camera1, true, "opening does not expire at exact deadline")
step(50.1)
eq(m.camera1, false, "opening expires strictly after deadline")
eq(#events("finish"), 1, "opening finishes once")
step(51)
eq(#events("audio"), 2, "startup does not replay")
fresh(); W.random = {2}; step(0)
eq(Save().rtype, 2, "initial random type 2")
for _, reason in ipairs({"cancel", "audio", "nil audio"}) do
    m = boot()
    if reason == "cancel" then W.cancel = true
    elseif reason == "audio" then W.messages[m.audmsg2] = true
    else m.audmsg2 = nil end
    step(1)
    eq(m.camera1, false, "opening exit: " .. reason)
    eq(#events("finish"), 1, "opening cleanup: " .. reason)
end

-- AddObject chooses a base only for team-1 Soviet combat/support ODFs.
for _, odf in ipairs({"svtank", "svturr", "svfigh", "svwalk", "svscav", "svhaul"}) do
    for choice = 0, 1 do
        m = quiet()
        local h = object(odf, 1)
        W.random = {choice}
        AddObject(h)
        local kind = (odf == "svscav" or odf == "svhaul") and "go_to" or "attack"
        eq(#events(kind), 1, odf .. " callback order")
        eq(events(kind)[1][3], choice == 0 and m.base1 or m.base2, odf .. " chosen base")
        eq(events(kind)[1][4], 0, odf .. " player-commandable priority")
        eq(m.newbie, h, odf .. " camera subject tracking")
    end
end
for _, pair in ipairs({{"svtank", 2}, {"svscav", 2}, {"avtank", 1}, {"avmuf", 1}}) do
    m = quiet()
    AddObject(object(pair[1], pair[2]))
    eq(#W.events, 0, "ignore team/ODF " .. pair[1] .. "/" .. pair[2])
    eq(m.newbie, nil, "unrelated object does not replace camera subject")
end
fresh()
AddObject(object("svtank", 1))
eq(#events("attack"), 0, "pre-Execute callback does not issue null-target order")
AddObject(nil); AddObject(0)
eq(#events("attack"), 0, "null callbacks are harmless")
m = quiet(); remove(m.base1)
W.random = {0}; AddObject(object("svtank", 1))
eq(#events("attack"), 0, "dead chosen base is not rerouted")

-- Exact reinforcement manifests, including native case-5 fallthrough.
local manifests = {
    {{"svfigh", "starta"}, {"svhaul", "starta2"}, {"svhaul", "starta3"}},
    {{"svscav", "startb"}, {"svscav", "startb2"}, {"svfigh", "startb3"}},
    {{"svscav", "starta"}, {"svturr", "starta2"}, {"svfigh", "starta3"}},
    {{"svfigh", "startb"}, {"svfigh", "startb2"}},
    {{"svfigh", "starta"}, {"svfigh", "starta2"}, {"svtank", "starta3"},
        {"svtank", "startb"}, {"svtank", "startb2"}, {"svtank", "startb3"}},
    {{"svtank", "startb"}, {"svtank", "startb2"}, {"svtank", "startb3"}},
    {{"svwalk", "starta"}, {"svwalk", "starta2"}, {"svwalk", "starta3"}},
}
local calls = {"misn1603.wav", "misn1604.wav", "misn1605.wav", "misn1606.wav",
    "misn1607.wav", "misn1607.wav", "misn1608.wav"}
for kind = 1, 7 do
    m = quiet(); m.rtype = kind
    step(120)
    eq(#events("build"), 0, "reinforcement strict 120-second boundary")
    step(120.1)
    local builds = events("build")
    eq(#builds, #manifests[kind], "type " .. kind .. " unit count")
    for i, want in ipairs(manifests[kind]) do
        eq(builds[i][2], want[1], "type " .. kind .. " ODF " .. i)
        eq(builds[i][3], 1, "reinforcement team")
        eq(builds[i][4], want[2], "type " .. kind .. " spawn " .. i)
    end
    eq(#events("audio"), kind == 5 and 2 or 1, "type " .. kind .. " audio count")
    for _, e in ipairs(events("audio")) do eq(e[2], calls[kind], "type radio filename") end
    eq(m.rcount, 1, "reinforcement count")
    eq(m.next_reinforcement, 300.1, "180-second recurrence")
    eq(m.start_time, 122.1, "two-second camera delay")
    eq(m.newbie, builds[#builds][5], "last-built unit is camera subject")
end
m = quiet()
for i = 1, 9 do
    local t = m.next_reinforcement + 0.1
    step(t)
    eq(m.rcount, i, "nine waves count " .. i)
end
local built = #events("build")
step(m.next_reinforcement + 0.1)
eq(m.rcount, 10, "reinforcement exhaustion count")
eq(#events("build"), built, "tenth event does not spawn")
for i = 1, 1000 do step(W.time + 0.1) end
eq(m.rcount, 10, "expired timer no longer increments per frame")
eq(#events("build"), built, "no extra exhausted waves")
for _, e in ipairs(events("audio")) do
    yes(e[2] ~= "misn1614.wav", "cut exhaustion radio remains disabled")
end

-- Reinforcement safety distance, dead-player fix, missing enemy, exits/offsets.
local function prepareCamera(distance)
    local state = quiet()
    state.newbie = object("svtank", 1)
    state.start_time = 2
    W.enemy = object("hvsav", 2)
    W.distance = distance
    return state
end
for _, distance in ipairs({149.9, 150, 150.1}) do
    m = prepareCamera(distance)
    step(2)
    eq(m.rcam, false, "camera two-second strict boundary")
    step(2.1)
    eq(m.rcam, distance > 150, "camera safety distance " .. distance)
    eq(m.start_time, 99999, "camera attempt consumed once")
    if distance > 150 then
        local e = events("camera")[1]
        eq(e[2], m.newbie, "reinforcement camera base")
        eq(e[3], 0, "camera right offset")
        eq(e[4], 2000, "camera up offset")
        eq(e[5], 3000, "camera forward offset")
        eq(e[6], m.newbie, "camera target")
        step(m.rcam_time)
        eq(m.rcam, true, "four-second strict boundary")
        step(m.rcam_time + 0.1)
        eq(m.rcam, false, "four-second camera timeout")
    end
end
m = prepareCamera(151); W.enemy = nil; step(2.1)
eq(m.rcam, true, "no enemy allows safe camera")
m = prepareCamera(151); remove(W.enemy); step(2.1)
eq(m.rcam, true, "invalid enemy allows safe camera without distance call")
m = prepareCamera(151); remove(W.player); step(2.1)
eq(m.rcam, false, "dead player cannot start camera")
eq(#events("nearest"), 0, "no enemy lookup for dead player")
m = prepareCamera(151); remove(m.newbie); step(2.1)
eq(m.rcam, false, "missing subject cannot start camera")
for _, reason in ipairs({"cancel", "subject removed"}) do
    m = prepareCamera(151); step(2.1)
    if reason == "cancel" then W.cancel = true else remove(m.newbie) end
    step(2.2)
    eq(m.rcam, false, "reinforcement camera exit: " .. reason)
    eq(#events("finish"), 1, "reinforcement camera cleanup: " .. reason)
end

-- Wave acceleration, minimum gap, coupled SAT deadlines, and native order.
m = boot(); m.camera1 = false; m.next_reinforcement = 99999
W.events = {}
step(60)
eq(#events("build"), 0, "SAV strict boundary")
step(60.1)
eq(events("build")[1][2], "hvsav", "first alien SAV")
eq(events("build")[1][4], m.base2, "valid hangar uses source handle overload")
eq(m.alien_wave, 210.1, "schedule uses old 150-second gap")
eq(m.wave_gap, 145, "decrement only after scheduling")
step(90)
eq(#events("go_to"), 0, "SAT strict boundary")
step(90.1)
eq(events("build")[2][2], "hvsat", "first SAT ODF")
eq(events("build")[2][4], "sat1", "first SAT location")
eq(events("build")[3][4], "sat2", "second SAT location")
eq(events("go_to")[1][3], "strike1", "first SAT route")
eq(events("go_to")[2][3], "strike2", "second SAT route")
eq(events("go_to")[1][4], nil, "SAT source default priority")
eq(m.alien_wave1, 300.1, "SAT deadline coupled to next SAV")
for i = 1, 20 do step(m.alien_wave + 0.1) end
eq(m.wave_gap, 60, "SAV gap floors at 60")
local t = m.alien_wave + 0.1
step(t)
eq(m.alien_wave, t + 60, "SAV minimum recurrence")
eq(m.wave_gap, 60, "gap never falls below 60")
m = quiet(); m.alien_wave = 1; m.alien_wave1 = 1
step(2)
eq(events("build")[1][2], "hvsav", "SAV runs before simultaneous SAT")
eq(m.alien_wave1, 242, "simultaneous SAT uses updated SAV deadline")

-- Both entrances and either base trigger factory/recycler counterattacks.
for _, trigger in ipairs({"north", "south", "hq", "hangar"}) do
    m = quiet()
    m.next_reinforcement = 99999
    if trigger == "north" then remove(m.tow1); remove(m.tow2)
    elseif trigger == "south" then remove(m.tow3); remove(m.tow4)
    elseif trigger == "hq" then remove(m.base1)
    else remove(m.base2) end
    step(10)
    eq(m.counter, true, "counter trigger " .. trigger)
    eq(#events("build"), 2, "two counterattack SAVs, cut third disabled")
    eq(#events("attack"), 2, "two factory attack orders")
    for _, e in ipairs(events("attack")) do
        eq(e[3], m.muf, "first counter target factory")
        eq(e[4], 1, "counterattack priority")
    end
    if trigger == "hangar" then
        eq(events("build")[1][4], m.base2_position, "destroyed hangar cached location")
    end
    eq(m.counter_strike2, 130, "second strike relative deadline")
    step(130)
    eq(#events("build"), 2, "second strike strict boundary")
    step(130.1)
    eq(#events("build"), 4, "second pair of SAVs")
    eq(events("attack")[3][3], m.recy, "second strike target recycler")
    eq(events("attack")[4][3], m.recy, "both second strike SAVs target recycler")
    eq(m.counter_strike2, 99999, "second strike consumed")
    step(131)
    eq(#events("build"), 4, "counterattack does not repeat")
end
m = quiet(); remove(m.tow1); remove(m.tow3); step(1)
eq(m.counter, false, "one tower per entrance is not an open entrance")
for _, ended in ipairs({"won", "lost"}) do
    m = quiet(); m[ended] = true; remove(m.tow1); remove(m.tow2); step(1)
    eq(m.counter, false, "no new counter after " .. ended)
end
m = quiet(); m.counter = true; m.counter_strike2 = 5; m.won = true
step(6)
eq(#events("build"), 2, "already scheduled second strike survives win flag")
m = quiet(); m.alien_wave = 1; m.alien_wave1 = 1; m.counter = true; m.won = true
remove(m.base2); step(2)
eq(#events("build"), 3, "waves continue during ending delay")
eq(events("build")[1][4], m.base2_position, "ending-delay dead hangar fallback")

-- Independent, one-shot endings preserve same-frame native ordering.
m = quiet(); remove(m.base1); remove(m.base2); step(10)
eq(m.won, true, "both bases destroyed wins")
eq(events("audio")[1][2], "misn1613.wav", "win radio")
eq(events("win")[1][2], 25, "win 15-second delay")
eq(events("win")[1][3], "misn16w1.des", "win description")
step(11)
eq(#events("win"), 1, "win fires once")
m = quiet(); remove(m.recy); step(20)
eq(m.lost, true, "recycler destroyed loses")
eq(events("audio")[1][2], "misn1612.wav", "loss radio")
eq(events("lose")[1][2], 35, "loss 15-second delay")
eq(events("lose")[1][3], "misn16l1.des", "loss description")
step(21)
eq(#events("lose"), 1, "loss fires once")
m = quiet(); remove(m.base1); remove(m.base2); remove(m.recy); step(10)
eq(#events("win"), 1, "simultaneous destruction schedules source win")
eq(#events("lose"), 1, "simultaneous destruction schedules source loss")
eq(events("audio")[1][2], "misn1613.wav", "same-frame win radio first")
eq(events("audio")[2][2], "misn1612.wav", "same-frame loss radio second")

-- Restore active cameras, choices, counters, timers, messages, and position.
for _, camera in ipairs({"opening", "reinforcement"}) do
    m = camera == "opening" and boot() or prepareCamera(151)
    if camera == "reinforcement" then step(2.1) end
    local saved = copy(Save())
    local before = #W.events
    Load(saved)
    eq(#W.events, before, "Load has no engine side effects")
    eq(Save(), saved, "Load keeps supplied serialized table")
    for _, key in ipairs({"rtype", "rcount", "wave_gap", "start_time",
            "next_reinforcement", "alien_wave", "alien_wave1", "counter_strike2",
            "cam_time1", "rcam_time", "newbie", "audmsg1", "audmsg2", "base2"}) do
        eq(Save()[key], m[key], "restore field " .. key)
    end
    eq(Save().base2_position.x, m.base2_position.x, "restore cached spawn vector")
    local audios = #events("audio")
    step(W.time + 0.1)
    eq(#events("audio"), audios, "resume does not replay briefing")
    if camera == "opening" then yes(#events("path") > 1, "opening camera resumes")
    else yes(#events("camera") > 1, "reinforcement camera resumes") end
end

-- Missing optional beacons/SATs, missing map hangar, and failed BuildObject.
fresh()
for label, h in pairs(W.labels) do
    if label:match("^apcamr") or label:match("^hvsat") then remove(h) end
end
step(0)
eq(#events("name"), 0, "absent beacons are ignored")
eq(#events("defend"), 0, "absent SATs are ignored")
fresh(); W.labels.alien_hangar = nil; step(0)
eq(#events("path"), 0, "missing hangar is not passed to camera")
eq(#events("build"), 0, "missing authored hangar does not invent a spawn")
m = quiet(); m.alien_wave1 = 1
local build = BuildObject
BuildObject = function() return nil end
step(2)
eq(#events("go_to"), 0, "failed SAT builds do not issue null orders")
BuildObject = build

print("misn16: " .. checks .. " Lua 5.1 host checks passed")
