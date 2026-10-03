-- Run from the repository root: lua5.1 Tools/Test-Misns1.lua
-- Strict stock-API mock rejects nonexistent object operands and records flow.
local now, objects, labels, calls, distances, messages, serial, nearest
local route, cavalry_route, random_calls
local checks = 0
local native_random = math.random
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function record(name, ...)
    calls[#calls + 1] = {name, ...}
end
local function matching(name, arg, second)
    local found = {}
    for _, c in ipairs(calls) do
        if c[1] == name and (arg == nil or c[2] == arg)
            and (second == nil or c[3] == second) then
            found[#found + 1] = c
        end
    end
    return found
end
local function called(name, arg, second) return #matching(name, arg, second) > 0 end
local function exists(h) return h ~= nil and objects[h] ~= nil end
function GetHandle(label)
    if not labels[label] then
        serial = serial + 1
        labels[label] = serial
        objects[serial] = {alive = true}
    end
    record("GetHandle", label)
    return labels[label]
end
function GetTime() return now end
function IsValid(h) return exists(h) end
function IsAlive(h) return exists(h) and objects[h].alive end
function GetDistance(h, target)
    assert(exists(h), "invalid distance origin")
    assert(type(target) == "string" or exists(target), "invalid distance target")
    return distances[tostring(h) .. ":" .. tostring(target)] or 10000
end
function GetNearestEnemy(h)
    assert(exists(h), "invalid nearest-enemy origin")
    return nearest
end
function BuildObject(odf, team, where)
    assert(type(where) == "string" or exists(where), "invalid spawn origin")
    serial = serial + 1
    objects[serial] = {alive = true, odf = odf, team = team, where = where}
    record("BuildObject", odf, team, where)
    return serial
end
function RemoveObject(h)
    assert(exists(h), "invalid removal")
    objects[h] = nil
    record("RemoveObject", h)
end
function AudioMessage(filename)
    local message = #messages + 1
    messages[message] = {filename = filename, done = false}
    record("AudioMessage", filename)
    return message
end
function IsAudioMessageDone(message)
    assert(messages[message], "invalid audio message")
    return messages[message].done
end
function Goto(h, where, priority)
    assert(exists(h) and (type(where) == "string" or exists(where)), "invalid Goto")
    record("Goto", h, where, priority)
end
for _, name in ipairs({"Follow", "Attack"}) do
    local operation = name
    _G[operation] = function(h, target, priority)
        assert(exists(h) and exists(target), "invalid " .. operation)
        record(operation, h, target, priority)
    end
end
for _, name in ipairs({"SetObjectiveName", "SetObjectiveOn", "SetIndependence"}) do
    local operation = name
    _G[operation] = function(h, arg)
        assert(exists(h), "invalid " .. operation)
        record(operation, h, arg)
    end
end
function CameraObject(anchor, right, up, forward, target)
    assert(exists(anchor) and exists(target), "invalid camera anchor/target")
    record("CameraObject", anchor, right, up, forward, target)
end
for _, name in ipairs({"SetScrap", "SetAIP", "ClearObjectives", "AddObjective",
    "CameraReady", "CameraFinish", "CameraPath", "FailMission", "SucceedMission"}) do
    local operation = name
    _G[operation] = function(...) record(operation, ...) end
end
math.random = function(low, high)
    random_calls = random_calls + 1
    assert(low == 0 and (high == 2 or high == 3), "unexpected random range")
    return high == 2 and route or cavalry_route
end
local function reset(path, cav)
    now, serial, nearest = 0, 0, nil
    route, cavalry_route, random_calls = path or 0, cav or 0, 0
    objects, labels, calls, distances, messages = {}, {}, {}, {}, {}
    dofile("Scripts/misns1.lua")
    Start()
    Update(0.05)
    return Save()
end
local function near(h, target, distance)
    distances[tostring(h) .. ":" .. tostring(target)] = distance
end
local function kill(h) objects[h].alive = false end
local function finish(message) messages[message].done = true end
local function copy(t)
    local result = {}
    for k, v in pairs(t) do result[k] = type(v) == "table" and copy(v) or v end
    return result
end
local function factory_builds(factory)
    local result = {}
    for _, c in ipairs(matching("BuildObject")) do
        if c[4] == factory then result[#result + 1] = c end
    end
    return result
end

local m = reset()
check(m.missionstart and m.startconvoy == 180, "startup and convoy timer")
check(random_calls == 2 and m.path == 0 and m.cav == 0, "one saved draw per route")
check(#matching("BuildObject") == 10 and #matching("RemoveObject") == 2, "startup unit counts")
check(not IsValid(m.et3) and not IsValid(m.et4) and IsAlive(m.et1), "source escort cuts")
check(m.walker2 == nil and m.walkcam2 == nil and m.geyser2 == nil, "cut objects stay absent")
check(#matching("SetObjectiveName") == 6 and #matching("SetScrap") == 4, "names and resources")
check(#matching("AddObjective") == 3 and called("AddObjective", "misns103.otf", "white"), "initial objectives")
check(m.cintime12 == 99999 and m.aw1a == nil and not m.cindone11, "unused native state retained")
now = 67; Update(0.05)
check(not called("CameraReady") and not called("CameraPath"), "opening cinematic remains disabled")
local before = #calls; AddObject(m.et1)
check(#calls == before, "source AddObject hook remains empty")

for path = 0, 2 do
    m = reset(path)
    now = 180; Update(0.05)
    check(not m.pickpath, "convoy strict boundary " .. path)
    now = 180.001; Update(0.05)
    check(m.pickpath and called("Goto", m.colorado, ({"upperpath", "midpath", "lowerpath"})[path + 1]), "convoy path " .. path)
    check(#matching("Follow") == 5 and #matching("SetIndependence") == 5, "convoy escort commands " .. path)
    check(#matching("AudioMessage", "misns125.wav") == 1, "convoy dispatch radio " .. path)
    near(m.colorado, m.walkcam1, 70); Update(0.05)
    check(not m.enterwarning, "entrance strict boundary " .. path)
    near(m.colorado, m.walkcam1, 69.99); Update(0.05)
    check(m.enterwarning and called("AudioMessage", ({"misns117.wav", "misns116.wav", "misns115.wav"})[path + 1]), "route entrance warning " .. path)
    local midpoint = ({"halfwayupper", "halfwaymid", "halfwaylower"})[path + 1]
    near(m.colorado, midpoint, 100); Update(0.05)
    check(not m.halfwaywarn, "halfway strict boundary " .. path)
    near(m.colorado, midpoint, 99.99); Update(0.05)
    check(m.halfwaywarn and called("AudioMessage", ({"misns102.wav", "misns103.wav", "misns104.wav"})[path + 1]), "route halfway warning " .. path)
    local exit = ({m.hidcam1, m.hidcam2, m.hidcam3})[path + 1]
    near(m.colorado, exit, 70); Update(0.05)
    check(not m.blockaderun, "exit strict boundary " .. path)
    near(m.colorado, exit, 69.99)
    nearest = m.walker1; near(nearest, m.colorado, 10); Update(0.05)
    check(m.blockaderun and not m.retreat, "blockade prevents retreat after exit " .. path)
    near(m.colorado, "safepoint", 60); Update(0.05)
    check(not m.coloradoreachedsafepoint, "escape strict boundary " .. path)
    near(m.colorado, "safepoint", 59.99); Update(0.05)
    check(m.coloradoreachedsafepoint and #matching("CameraObject") == 1, "escape loss shot " .. path)
    local camera = matching("CameraObject")[1]
    check(camera[2] == m.colorado and camera[6] == m.colorado, "unset camera anchor fallback " .. path)
    finish(m.aud20); Update(0.05)
    check(not called("FailMission"), "escape waits for second radio " .. path)
    finish(m.aud21); Update(0.05)
    local outcome = matching("FailMission")[1]
    check(outcome[2] == now and outcome[3] == "misns1l1.des", "escape debrief " .. path)
    Update(0.05)
    check(#matching("FailMission") == 1, "escape outcome is one-shot " .. path)
end

m = reset()
nearest = m.walker1; near(nearest, m.colorado, 199)
near(m.colorado, "halfwayupper", 99); near(m.colorado, m.hidcam1, 69)
Update(0.05)
check(m.retreat and m.halfwaywarn and not m.blockaderun, "source checks retreat before new halfway warning")

m = reset()
near(m.walker1, m.walkcam1, 50); Update(0.05)
check(not m.trapset, "trap strict boundary")
near(m.walker1, m.walkcam1, 49); Update(0.05)
check(m.trapset and called("AudioMessage", "misns123.wav"), "walker blockade trap")
nearest = m.walker1; near(nearest, m.colorado, 200); Update(0.05)
check(not m.retreat, "retreat strict boundary")
near(nearest, m.colorado, 199); Update(0.05)
check(m.retreat and m.retreatpathset and called("Goto", m.colorado, "retreat1"), "retreat dispatch")
check(called("Attack", m.ef1, nearest) and called("Follow", m.ef2, m.ef1), "retreat surviving escorts")
check(not called("Follow", m.et3) and not called("SetIndependence", m.et3), "removed tank never commanded")
near(m.colorado, m.geyser, 50); Update(0.05)
check(not m.coloradosafe, "retreat arrival strict boundary")
now = 10; near(m.colorado, m.geyser, 49); Update(0.05)
check(m.coloradosafe and called("SetAIP", "misn09.aip") and not m.safety1, "retreat strategic branch")
check(m.aw1bt == 40 and m.aw1ct == 45 and m.du1at == 70, "retreat reinforcement offsets")
check(#matching("SetObjectiveOn") == 3, "retreated Colorado added to outpost objectives")
kill(m.colorado); now = 11; Update(0.05)
check(not m.safety1 and not called("BuildObject", "avscav") and m.aw1bt == 40, "later recycler death does not reset retreat waves")

-- Verify each exact source deadline and the factory spawn order on both branches.
for _, retreat_branch in ipairs({false, true}) do
    m = reset()
    if retreat_branch then
        nearest = m.walker1; near(nearest, m.colorado, 199)
        near(m.colorado, m.geyser, 49); Update(0.05)
    else
        kill(m.colorado); Update(0.05)
        check(m.safety1 and m.escortretreat and called("SetAIP", "misn14.aip"), "ambush strategic branch")
        check(#matching("BuildObject", "avscav") == 2 and IsAlive(m.scav1) and IsAlive(m.scav2), "ambush scavengers")
        local escort = matching("Goto", m.ef1, m.muf)[1]
        check(escort[4] == 1000, "source escort-retreat priority retained")
        check(m.wave1 == 180 and m.aw1bt == 35 and m.aw1ct == 40, "ambush reinforcement offsets")
    end
    local schedule = {
        {25, "avtank", "aw1amade"},
        {retreat_branch and 30 or 35, "avfigh", "aw1bmade"},
        {retreat_branch and 35 or 40, "avfigh", "aw1cmade"},
        {60, "avturr", "du1amade"}, {75, "avturr", "du1bmade"},
        {90, "avtank", "aw2amade"}, {95, "avfigh", "aw2bmade"},
        {100, "avtank", "aw2cmade"}, {190, "avtank", "aw3amade"},
        {195, "avtank", "aw3bmade"}, {200, "avfigh", "aw3cmade"},
    }
    for _, step in ipairs(schedule) do
        local count = #factory_builds(m.muf)
        now = step[1]; Update(0.05)
        check(not m[step[3]] and #factory_builds(m.muf) == count, "strict reinforcement boundary " .. step[3])
        now = step[1] + 0.001; Update(0.05)
        local builds = factory_builds(m.muf)
        check(m[step[3]] and #builds == count + 1 and builds[#builds][2] == step[2], "reinforcement ODF/order " .. step[3])
    end
    now = 201; Update(0.05)
    check(#factory_builds(m.muf) == (retreat_branch and 11 or 13), "waves remain one-shot")
    check(m.aw1a == nil and m.aw2a == nil and m.aw3a == nil
        and #matching("Attack") == (retreat_branch and 1 or 0), "cut wave dispatch stays inactive")
end

m = reset(); kill(m.colorado); Update(0.05); kill(m.silo)
now = 96; Update(0.05)
check(m.aw1amade and m.aw2bmade, "silo destruction keeps early waves")
now = 201; Update(0.05)
check(not m.aw3amade and not m.aw3bmade and not m.aw3cmade, "silo destruction prevents third wave")

m = reset(); kill(m.colorado); Update(0.05); kill(m.muf)
now = 61; Update(0.05)
check(not m.aw1amade and m.du1amade and called("BuildObject", "avturr"), "still-valid wreck preserves ungated turret source behavior")
objects[m.muf] = nil; now = 76; local builds_before = #matching("BuildObject"); Update(0.05)
check(m.du1bmade and #matching("BuildObject") == builds_before, "missing factory skips invalid turret position")

m = reset(); objects[m.muf] = nil; objects[m.colorado] = nil; Update(0.05)
check(m.safety1 and m.scav1 == nil and m.scav2 == nil, "missing factory skips scavenger positions")
check(not m.retreat and not m.enterwarning, "missing Colorado cannot trigger proximity events")

for cav = 0, 3 do
    m = reset(0, cav); kill(m.colorado); Update(0.05)
    now = 180; Update(0.05)
    check(not m.cavalry, "cavalry strict timer " .. cav)
    now = 180.001; Update(0.05)
    local path = cav % 2 == 0 and "cavpath1" or "cavpath2"
    check(m.cavalry and m.cavsent and called("Goto", m.cav1, path), "cavalry route mapping " .. cav)
    check(IsAlive(m.cav1) and IsAlive(m.cav2) and IsAlive(m.cav3) and m.cav4 == nil and m.cav5 == nil, "three cavalry units " .. cav)
    if cav % 2 == 0 then
        near(m.cav1, m.walkcam1, 200); Update(0.05)
        check(not m.cav1pathwarn1, "cavalry warning strict boundary")
        near(m.cav1, m.walkcam1, 199); Update(0.05)
        check(m.cav1pathwarn1 and called("AudioMessage", "misns118.wav"), "upper cavalry warning")
    else
        check(not m.cav2pathwarn1 and not called("AudioMessage", "misns119.wav"), "cut middle camera cannot trigger warning")
        m.walkcam2 = GetHandle("restored_walkcam2")
        near(m.cav2, m.walkcam2, 50); Update(0.05)
        check(not m.cav2pathwarn1, "middle cavalry warning strict boundary")
        near(m.cav2, m.walkcam2, 49); Update(0.05)
        check(m.cav2pathwarn1 and called("AudioMessage", "misns119.wav"), "middle warning supports reconstructed camera")
    end
end

m = reset(); kill(m.muf); kill(m.silo); kill(m.colorado); Update(0.05)
check(m.missionwon and m.finish and not called("SucceedMission"), "victory waits for radio")
check(called("AudioMessage", "misns108.wav") and called("AudioMessage", "misns107.wav"), "outpost destruction radio")
Update(0.05)
check(called("AddObjective", "misns103.otf", "green") and not called("AddObjective", "misn103.otf"), "victory objective typo corrected")
finish(m.aud1); now = 7; Update(0.05)
check(called("SucceedMission", 7, "misns1w1.des"), "victory time and debrief")
Update(0.05)
check(#matching("SucceedMission") == 1, "victory outcome one-shot")
local saved = copy(Save()); local count = #calls
dofile("Scripts/misns1.lua"); Load(saved); Update(0.05)
check(Save() == saved and saved.missionwon and saved.success_called, "serialized-state reload preserves victory")
check(#matching("SucceedMission") == 1 and #matching("AudioMessage", "misns101.wav") == 1, "reload never replays outcome/startup")

m = reset(); kill(m.svrec); Update(0.05)
check(m.missionfail and not called("FailMission"), "recycler loss waits for radio")
finish(m.aud22); Update(0.05)
check(not called("FailMission"), "recycler loss waits for second message")
finish(m.aud23); now = 9; Update(0.05)
check(called("FailMission", 9, "misns1l2.des"), "recycler loss debrief")
Update(0.05); check(#matching("FailMission") == 1, "recycler loss outcome one-shot")

m = reset(); kill(m.colorado); Update(0.05); now = 25.001; Update(0.05)
saved = copy(Save()); local factory_count = #factory_builds(m.muf)
dofile("Scripts/misns1.lua"); Load(saved); Update(0.05)
check(#factory_builds(m.muf) == factory_count and saved.aw1amade, "reload does not duplicate prior reinforcements")
now = 35.001; Update(0.05)
check(saved.aw1bmade and #factory_builds(m.muf) == factory_count + 1 and random_calls == 2, "reload resumes saved deadlines and routes")

m = reset(); kill(m.colorado); kill(m.muf); kill(m.silo); kill(m.svrec); Update(0.05)
finish(m.aud1); finish(m.aud22); finish(m.aud23); Update(0.05)
local outcomes = {}
for _, c in ipairs(calls) do
    if c[1] == "SucceedMission" or c[1] == "FailMission" then outcomes[#outcomes + 1] = c end
end
check(#outcomes == 2 and outcomes[1][1] == "SucceedMission" and outcomes[2][3] == "misns1l2.des", "simultaneous outcomes retain source call order")

math.random = native_random
print("misns1: " .. checks .. " checks passed (" .. _VERSION .. ")")
