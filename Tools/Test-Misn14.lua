-- Run from the repository root: lua5.1 Tools/Test-Misn14.lua
-- A strict stock-API host; native AI, maps, and userdata serialization need BZR.
assert(_VERSION == "Lua 5.1", "run with Lua 5.1")
local now, objects, labels, calls, distances, serial, missing, cancelled, random
local checks = 0
local function check(value, description)
    assert(value, description)
    checks = checks + 1
end
local function record(name, ...)
    calls[#calls + 1] = {name, ...}
end
local function count(name, arg)
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == name and (arg == nil or c[2] == arg) then n = n + 1 end
    end
    return n
end
local function called(name, ...)
    local args = {...}
    for _, c in ipairs(calls) do
        if c[1] == name then
            local match = true
            for i = 1, select("#", ...) do
                if c[i + 1] ~= args[i] then match = false end
            end
            if match then return true end
        end
    end
    return false
end
local function spawn(odf, team, craft)
    serial = serial + 1
    objects[serial] = {alive = true, odf = odf, team = team, craft = craft == true}
    return serial
end
function GetHandle(label)
    if missing[label] then return nil end
    if not labels[label] then labels[label] = spawn("mapobject", 1) end
    return labels[label]
end
function GetPlayerHandle() return GetHandle("player") end
function GetTime() return now end
function IsValid(h) return objects[h] ~= nil end
function IsAlive(h) return IsValid(h) and objects[h].alive end
function IsOdf(h, odf)
    assert(IsValid(h), "invalid IsOdf")
    return objects[h].odf == odf
end
function GetTeamNum(h)
    assert(IsValid(h), "invalid team query")
    return objects[h].team
end
function SetTeamNum(h, team)
    assert(IsValid(h), "invalid team write")
    objects[h].team = team
    record("SetTeamNum", h, team)
end
function AllCraft()
    local list = {}
    for h, o in pairs(objects) do
        if o.craft then list[#list + 1] = h end
    end
    table.sort(list)
    local i = 0
    return function() i = i + 1; return list[i] end
end
local function key(a, b) return tostring(a) .. ":" .. tostring(b) end
function GetDistance(a, b)
    assert(IsAlive(a) and IsAlive(b), "distance queried with dead/missing object")
    return distances[key(a, b)] or distances[key(b, a)] or 10000
end
function GetNearestEnemy(h)
    assert(IsValid(h), "invalid nearest query")
    return labels.foe
end
function math.random(lo, hi)
    check(lo == 0 and hi == 2, "wave RNG range")
    return random
end
function BuildObject(odf, team, path)
    local h = spawn(odf, team, odf ~= "apcamr")
    record("BuildObject", odf, team, path, h)
    AddObject(h) -- deliberately synchronous, as stock callbacks may be
    return h
end
function RemoveObject(h)
    assert(IsAlive(h), "invalid removal")
    objects[h] = nil
    record("RemoveObject", h)
end
function AudioMessage(name)
    record("AudioMessage", name)
    return "message:" .. name
end
function StopAudioMessage(message)
    assert(type(message) == "string", "audio uses message values, not handles")
    record("StopAudioMessage", message)
end
function CameraCancelled() return cancelled end
function SetAIControl(team, enabled)
    assert(not Save().start_done, "strategic AI must only be enabled at startup")
    record("SetAIControl", team, enabled)
end
function CameraPath(path, height, speed, target)
    assert(IsValid(target), "invalid path camera target")
    record("CameraPath", path, height, speed, target)
end
function CameraObject(base, right, up, forward, target)
    assert(IsAlive(base) and IsAlive(target), "invalid object camera target")
    record("CameraObject", base, right, up, forward, target)
end
for _, name in ipairs({"SetObjectiveName", "SetObjectiveOn", "SetMaxHealth", "AddHealth"}) do
    local op = name
    _G[op] = function(h, ...)
        assert(IsValid(h), "invalid object mutation " .. op)
        record(op, h, ...)
    end
end
for _, name in ipairs({"Defend", "Goto", "Retreat", "CameraReady", "CameraFinish",
    "SetAIP", "AddPilot", "SetScrap", "ClearObjectives", "AddObjective",
    "FailMission", "SucceedMission"}) do
    local op = name
    _G[op] = function(...) record(op, ...) end
end
local function clear() calls = {} end
local function near(a, b, distance) distances[key(a, b)] = distance end
local function tick(time) now = time; Update(0.05) end
local function kill(h) objects[h].alive = false end
local function copy(t)
    local result = {}
    for k, v in pairs(t) do
        result[k] = type(v) == "table" and copy(v) or v
    end
    return result
end
local function roundtrip()
    local saved = copy(Save())
    dofile("Scripts/misn14.lua")
    Load(saved)
    return Save()
end
local function reset(absent, earlyApc)
    now, serial, random, cancelled = 0, 0, 0, false
    objects, labels, calls, distances, missing = {}, {}, {}, {}, absent or {}
    dofile("Scripts/misn14.lua")
    if earlyApc then AddObject(spawn("avapc", 1, true)) end
    Start()
    check(not Save().start_done and count("AudioMessage") == 0, "Start does not run Execute")
    Update(0.05)
    return Save()
end
local function skipIntro()
    cancelled = true
    Update(0.05)
    cancelled = false
    return Save()
end
local function apc()
    local h = spawn("avapc", 1, true)
    AddObject(h)
    return h
end
local function finishRescues()
    local m = reset()
    skipIntro()
    local carrier = apc()
    for stage = 1, 3 do
        tick(m["beacon_time" .. stage] + 0.01)
        near(carrier, m["beacon" .. stage], 99)
        Update(0.05)
        tick(m["rescue_finish" .. stage] + 0.01)
    end
    return m, carrier
end

local m = reset(nil, true)
check(called("SetAIControl", 2, true) and count("SetAIControl") == 1, "CCA strategic AI enabled at startup")
check(m.found and IsAlive(m.apc), "pre-Start APC notification retained")
check(called("SetAIP", "misn14.aip") and called("AddPilot", 2, 30), "AIP/pilots")
check(called("SetScrap", 1, 30) and called("SetScrap", 2, 45), "initial scrap")
check(not called("AddPilot", 1, 10) and not called("AudioMessage", "misn1402.wav"), "cut calls stay disabled")
check(called("SetMaxHealth", m.base, 100000), "protected barracks health")
check(called("SetObjectiveName", m.cam1, "Foothill Geysers")
    and called("SetObjectiveName", m.cam2, "Canyon Geysers")
    and called("SetObjectiveName", m.cam3, "CCA Base")
    and called("SetObjectiveName", m.cam4, "Plateau Geysers"), "four camera pod names")
tick(12)
check(m.camera1 and not m.camera2, "intro first strict deadline")
clear(); tick(12.01)
check(not m.camera1 and m.camera2 and m.camera_time == now + 15, "second shot starts after 12 s")
check(count("StopAudioMessage") == 0
    and called("CameraPath", "cam_path2", 2000, 500, m.recy), "briefing spans both shots")
m = roundtrip()
tick(m.camera_time)
check(m.camera2, "second strict deadline")
tick(now + 0.01)
check(not m.camera2 and m.alien_time == now + 720 and m.beacon_time1 == now + 15, "post-intro deadlines")
check(called("AddObjective", "misn1401.otf", "white") and count("CameraFinish") == 1, "intro objective/camera close")
check(m.finishcam2 == false and m.rescuecam2 == false and m.finishcam3 == false
    and m.rescuecam3 == false and m.erecy ~= nil, "unused native state retained")

m = reset(); skipIntro()
check(m.alien_time == 720 and m.beacon_time1 == 15 and not m.camera1 and not m.camera2,
    "cancel skips both introductory shots in source order")
tick(15)
check(m.beacon1 == nil, "beacon strict deadline")
tick(15.01)
check(m.beacon1 ~= nil and count("BuildObject", "aspilo") == 3 and count("Defend") == 3, "first survivors spawn")
near(m.player, m.beacon1, 199); clear(); Update(0.05)
check(called("AudioMessage", "misn1415.wav") and m.rescue_reminder, "no APC reminder without nil distance")
clear(); Update(0.05)
check(count("AudioMessage", "misn1415.wav") == 0, "reminder is one shot")
local carrier = apc()
near(carrier, m.beacon1, 100); Update(0.05)
check(not m.rescue1, "100 m is outside strict rescue trigger")
near(carrier, m.beacon1, 99); Update(0.05)
check(m.rescue1 and m.rescue_finish1 == now + 25 and m.rescuecam1, "first pickup timer/camera")
check(called("Goto", m.guy1, m.beacon1) and called("Goto", m.guy2, m.beacon1)
    and called("Goto", m.guy3, m.beacon1), "first survivors walk toward beacon")
m = roundtrip()
clear(); tick(m.camera_time + 0.01)
check(not m.rescuecam1 and count("CameraFinish") == 1, "first pickup shot ends after 3 s")
tick(m.rescue_finish1)
check(IsAlive(m.beacon1), "first loading strict deadline")
tick(m.rescue_finish1 + 0.01)
check(not IsValid(m.beacon1) and not IsValid(m.guy1) and m.finishcam1
    and m.beacon_time2 == now + 10 and m.rescue_finish1 == 99999, "first completion cleanup/next rescue")
check(called("AudioMessage", "misn1417.wav"), "first completion radio")
tick(m.camera_time + 0.01)
check(not m.finishcam1, "first completion shot ends")
for stage = 2, 3 do
    local deadline = m["beacon_time" .. stage]
    tick(deadline)
    check(m["beacon" .. stage] == nil, "next beacon strict deadline")
    clear(); tick(deadline + 0.01)
    local beacon = m["beacon" .. stage]
    check(count("BuildObject", "aspilo") == 3 and called("BuildObject", "aspilo", 1, "help" .. (stage * 3)), "next survivor paths")
    near(carrier, beacon, 99); Update(0.05)
    check(m["rescue" .. stage] and m["rescue_finish" .. stage] == now + 25
        and count("CameraReady") == 0, "later rescues have no added camera")
    m = roundtrip()
    tick(m["rescue_finish" .. stage] + 0.01)
    check(not IsValid(beacon) and called("AudioMessage", "misn14" .. (16 + stage) .. ".wav"), "later completion cleanup/radio")
end
check(m.rescue3 and not m.gen_message and not m.rescue_message, "rescues alone do not bypass wave gates")

-- Every group must fail if any survivor dies before its APC arrives.
for stage = 1, 3 do
    for victim = 1, 3 do
        m = reset(); skipIntro()
        local carrier2 = apc()
        for done = 1, stage - 1 do
            tick(m["beacon_time" .. done] + 0.01)
            near(carrier2, m["beacon" .. done], 99); Update(0.05)
            tick(m["rescue_finish" .. done] + 0.01)
        end
        tick(m["beacon_time" .. stage] + 0.01)
        kill(m["guy" .. victim]); clear(); Update(0.05)
        check(m.lost and called("FailMission", now + 15, "misn14l2.des"), "survivor death fails each rescue/victim")
        clear(); Update(0.05)
        check(count("FailMission") == 0, "survivor failure latch")
    end
end

-- The three original random spawn triplets, 720 s initial / 180 s repeats.
for choice = 0, 2 do
    m = reset(); skipIntro(); random = choice
    tick(720)
    check(m.wave_count == 0, "alien arrival strict deadline")
    clear(); tick(720.01)
    local expected = ({ {1, 2, 5}, {3, 4, 1}, {5, 6, 3} })[choice + 1]
    for _, path in ipairs(expected) do
        check(called("BuildObject", "hvsav", 3, "alien" .. path), "alien branch path")
    end
    check(count("BuildObject", "hvsav") == 3 and m.wave_count == 1
        and m.alien_time == now + 180, "three aliens and 180 s interval")
    check(called("AudioMessage", "misn1403.wav") and m.alien_warning, "first warning")
    clear(); tick(m.alien_time + 0.01)
    check(m.wave_count == 2 and not m.cca_surrender
        and count("AudioMessage", "misn1403.wav") == 0, "second wave/no repeated warning")
end

m, carrier = finishRescues()
local tank, turret, fighter = spawn("svtank", 2, true), spawn("svturr", 2, true), spawn("svfigh.odf", 2, true)
local utility, enemyBuilding = spawn("svscav", 2, true), spawn("sbpgen", 2, false)
local nsdf, alien = spawn("avtank", 1, true), spawn("hvsav", 3, true)
tick(m.alien_time + 0.01); tick(m.alien_time + 0.01); clear(); tick(m.alien_time + 0.01)
check(m.wave_count == 3 and m.cca_surrender, "third wave surrender")
check(called("AudioMessage", "misn1404.wav") and called("AudioMessage", "misn1405.wav"), "surrender radio")
for _, h in ipairs({tank, turret, fighter, utility}) do check(objects[h].team == 0, "CCA craft neutralized") end
check(called("Retreat", tank, "escape", 1) and called("Retreat", turret, "escape", 1)
    and called("Retreat", fighter, "escape", 1) and not called("Retreat", utility), "only specified combat ODFs flee")
check(objects[enemyBuilding].team == 2 and objects[nsdf].team == 1 and objects[alien].team == 3,
    "unrelated teams/buildings unaffected")
for _, h in ipairs({m.base, m.tow1, m.tow2, m.tow3, m.tow4}) do check(objects[h].team == 1, "CCA base/towers captured") end
clear(); Update(0.05)
check(count("AudioMessage", "misn1404.wav") == 0, "surrender is one shot")
tick(m.alien_time + 0.01)
check(m.wave_count == 4 and m.gen_message and m.camera3 and m.camera_time == now + 20,
    "fourth wave general VO/camera (no nearest enemy)")
check(called("CameraPath", "camera_path", 2500, 300, m.base) and called("SetScrap", 2, 0), "general view/scrap")
m = roundtrip(); clear(); tick(m.camera_time + 0.01)
check(not m.camera3 and count("StopAudioMessage") == 1 and count("CameraFinish") == 1, "general shot closes after save/load")
tick(m.alien_time + 0.01)
check(m.wave_count == 5 and m.rescue_message and m.rescue_start
    and called("SetObjectiveName", m.base, "Rescue CCA"), "fifth wave CCA rescue")
near(carrier, m.base, 200); Update(0.05)
check(not m.pick_up, "CCA pickup strict 200 m trigger")
near(carrier, m.base, 199); Update(0.05)
check(m.pick_up and m.pick_up_time == now + 15, "CCA scientist loading delay")
local original = carrier
carrier = apc()
check(m.apc == original and carrier ~= original, "new APC cannot replace scientist carrier")
m = roundtrip(); clear(); tick(m.pick_up_time)
check(count("AudioMessage", "misn1410.wav") == 0, "CCA loading strict deadline")
tick(m.pick_up_time + 0.01)
check(called("AudioMessage", "misn1410.wav") and m.pick_up_time == 99999, "CCA ready VO")
near(carrier, m.recy, 1); Update(0.05)
check(not m.won, "empty replacement APC cannot win")
near(original, m.recy, 300); Update(0.05)
check(not m.won, "homecoming strict 300 m trigger")
near(original, m.recy, 299); clear(); Update(0.05)
check(m.won and called("SucceedMission", now + 10, "misn14w1.des")
    and called("AudioMessage", "misn1411.wav"), "loaded APC homecoming wins")
clear(); Update(0.05)
check(count("SucceedMission") == 0, "victory one shot")

-- Unsafe edge cases use real source gates, not manually set stage flags.
m, carrier = finishRescues()
for i = 1, 5 do tick(m.alien_time + 0.01) end
near(carrier, m.base, 199); Update(0.05)
near(carrier, m.recy, 1); kill(carrier); apc(); clear(); Update(0.05)
check(m.lost and not m.won and called("FailMission", now + 10, "misn14l3.des")
    and count("SucceedMission") == 0, "destroyed carrier cannot transfer payload or win")
check(called("AudioMessage", "misn1412.wav") and called("AudioMessage", "misn1413.wav"), "carrier loss radio")

m, carrier = finishRescues()
for i = 1, 5 do tick(m.alien_time + 0.01) end
near(carrier, m.base, 199); Update(0.05)
near(carrier, m.recy, 1); kill(m.recy); clear(); Update(0.05)
check(m.lost and not m.won and called("FailMission", now + 10, "misn14l1.des")
    and count("SucceedMission") == 0, "dead recycler cannot win in same frame")

m = reset({sbbarr0_i76building = true}); skipIntro()
tick(15.01); carrier = apc(); near(carrier, m.beacon1, 99); Update(0.05)
kill(carrier); clear(); Update(0.05)
check(not m.rescuecam1 and count("CameraFinish") == 1 and not m.lost, "dead APC safely ends rescue camera")
-- Replace an APC before scientist pickup, as the original AddObject did.
carrier = apc()
check(m.apc == carrier, "pre-pickup APC selection still follows latest build")
tick(m.rescue_finish1 + 0.01)
for stage = 2, 3 do
    tick(m["beacon_time" .. stage] + 0.01)
    near(carrier, m["beacon" .. stage], 99); Update(0.05)
    tick(m["rescue_finish" .. stage] + 0.01)
end
for i = 1, 5 do tick(m.alien_time + 0.01) end
check(m.lost and called("FailMission", now + 5, "misn14l.des")
    and not m.pick_up and not m.won, "missing base fails with relative five seconds")

m = reset({apcamr0_camerapod = true, apcamr1_camerapod = true,
    apcamr2_camerapod = true, apcamr3_camerapod = true,
    sbtowe0_turret = true, sbtowe1_turret = true, sbtowe55_turret = true, sbtowe56_turret = true})
skipIntro(); tick(720.01); tick(m.alien_time + 0.01); tick(m.alien_time + 0.01)
check(m.cca_surrender, "missing optional pods/towers are safe")

m = reset(); skipIntro(); labels.foe = spawn("hvsav", 3, true)
near(m.player, labels.foe, 150)
-- Finish rescues in this world then advance to fourth wave.
carrier = apc()
for stage = 1, 3 do
    tick(m["beacon_time" .. stage] + 0.01)
    near(carrier, m["beacon" .. stage], 99); Update(0.05)
    tick(m["rescue_finish" .. stage] + 0.01)
end
for i = 1, 4 do tick(m.alien_time + 0.01) end
check(m.gen_message and not m.camera3, "nearby enemy suppresses general camera at 150 m")

m = reset(); clear(); tick(1)
check(count("AddHealth") == 0, "base repair strict one-second deadline")
tick(1.01)
check(called("AddHealth", m.base, 5000) and m.next_second == now + 1, "base healing cadence")
clear(); tick(30)
check(count("AddHealth") == 1, "large timestep heals once, source does not catch up")

-- Source gates on arrival at Rescue 3, not on its later cleanup. Wave messages
-- must remain pending while the player has not reached that group.
m = reset(); skipIntro()
for i = 1, 5 do tick(m.alien_time + 0.01) end
check(not m.gen_message and not m.rescue_message, "wave count alone does not skip NSDF rescues")
carrier = apc()
for stage = 1, 2 do
    tick(now + 0.01)
    near(carrier, m["beacon" .. stage], 99); Update(0.05)
    tick(m["rescue_finish" .. stage] + 0.01)
    tick(m["beacon_time" .. (stage + 1)] + 0.01)
end
near(carrier, m.beacon3, 99); clear(); Update(0.05)
check(m.rescue3 and m.gen_message and m.rescue_message and m.rescue_start
    and IsAlive(m.guy1) and m.rescue_finish3 == now + 25,
    "delayed CCA gates fire at final NSDF arrival before 25 s cleanup")
near(carrier, m.base, 199); Update(0.05)
near(carrier, m.recy, 299); clear(); Update(0.05)
check(m.won and now < m.pick_up_time and called("SucceedMission", now + 10, "misn14w1.des"),
    "retain source return-home trigger before CCA ready VO")

m = reset(); skipIntro(); tick(15.01)
carrier = apc(); near(carrier, m.beacon1, 99); Update(0.05)
cancelled = true; clear(); Update(0.05)
check(not m.rescuecam1 and count("CameraFinish") == 1, "cancel first pickup camera")
cancelled = false
tick(m.rescue_finish1 + 0.01)
cancelled = true; clear(); Update(0.05)
check(not m.finishcam1 and count("CameraFinish") == 1, "cancel first completion camera")
cancelled = false

m, carrier = finishRescues()
for i = 1, 4 do tick(m.alien_time + 0.01) end
cancelled = true; clear(); Update(0.05)
check(not m.camera3 and count("CameraFinish") == 1 and count("StopAudioMessage") == 1,
    "cancel general camera and VO")
cancelled = false

m, carrier = finishRescues()
for i = 1, 4 do tick(m.alien_time + 0.01) end
kill(m.base); clear(); Update(0.05)
check(not m.camera3 and count("CameraFinish") == 1, "base destruction ends general shot safely")
tick(m.alien_time + 0.01)
check(m.lost and called("FailMission", now + 5, "misn14l.des"), "destroyed base fails at source wave-five gate")

m = reset(); skipIntro(); tick(15.01)
carrier = apc(); near(carrier, m.beacon1, 1); kill(carrier); clear(); Update(0.05)
check(not m.rescue1, "destroyed APC cannot start an NSDF rescue")

m = reset(); skipIntro()
AddObject(spawn("avapc", 2, true)); AddObject(spawn("svapc", 1, true))
check(not m.found and m.apc == nil, "only friendly American APCs are tracked")

print("misn14: " .. checks .. " checks passed (Lua 5.1)")
