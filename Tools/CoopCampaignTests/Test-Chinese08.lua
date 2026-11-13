-- Run from repository root: lua5.1 Tools/CoopCampaignTests/Test-Chinese08.lua
-- Stock API doubles verify mission logic; this is not an engine playtest.
local script = arg and arg[1] or "Scripts/ch08.lua"
local calls, dist, objs, now, player, done, cancel, cockpit, nearest, next_id, labels
local function log(name, ...) calls[#calls + 1] = {name, ...} end
local function count(name, a)
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == name and (a == nil or c[2] == a) then n = n + 1 end
    end
    return n
end
local function new(odf, label)
    next_id = next_id + 1
    objs[next_id] = {odf = odf, alive = true, hp = 1, cloak = false}
    if label then labels[label] = next_id end
    return next_id
end
function GetHandle(label) return labels[label] end
function GetPlayerHandle() return player end
function GetTime() return now end
function IsValid(h) return objs[h] ~= nil end
function IsAlive(h) assert(objs[h], "IsAlive on invalid handle"); return objs[h].alive end
function GetHealth(h) assert(objs[h]); return objs[h].alive and objs[h].hp or 0 end
function GetDistance(h, t)
    assert(objs[h], "GetDistance on invalid handle")
    return dist[tostring(h) .. ":" .. tostring(t)] or dist[tostring(t)] or 10000
end
function GetNearestUnitOnTeam(path, team) log("GetNearestUnitOnTeam", path, team); return nearest[path] end
function BuildObject(odf, team, path)
    local h = new(odf); log("BuildObject", odf, team, path); return h
end
function RemoveObject(h) objs[h] = nil; log("RemoveObject", h) end
function AudioMessage(n) log("AudioMessage", n); return "snd:" .. n end
function IsAudioMessageDone() return done end
function CameraPath(...) log("CameraPath", ...) end
function CameraCancelled() return cancel end
function IsCloaked(h) return objs[h].cloak end
function Decloak(h) objs[h].cloak = false; log("Decloak", h) end
function GetCockpitTimer() return cockpit end
function GetMaxScrap() return 500 end
function GetCurHealth(h) assert(objs[h]); return objs[h].hp end
function GetMaxHealth(h) assert(objs[h]); return 1 end
function AddHealth(h, v) log("AddHealth", h, v); objs[h].hp = objs[h].hp + v end
function MakeExplosion(odf, where) log("MakeExplosion", odf, where) end
for _, name in ipairs({"SetAIP", "SetScrap", "SetPilot", "Cloak", "CameraReady", "CameraFinish",
    "SetName", "SetUserTarget", "ClearObjectives", "AddObjective", "Attack", "Goto", "Defend2",
    "SetObjectiveOn", "SetObjectiveOff", "SetPerceivedTeam", "EnableCloaking", "FailMission",
    "SucceedMission", "StartCockpitTimer", "HideCockpitTimer"}) do
    _G[name] = function(...) log(name, ...) end
end

local lbl = {"west_1_1", "west_1_2", "west_1_3", "west_1_4", "east_1_1", "east_1_2", "east_1_3",
    "east_1_4", "nav", "howitzer_nw", "howitzer_ne", "west_power", "east_power", "east_bolt",
    "west_bolt", "walker_1", "west_comm", "east_comm"}
local function fresh()
    calls, dist, objs, labels, nearest = {}, {}, {}, {}, {}
    now, done, cancel, cockpit, next_id = 0, false, false, 270, 0
    for _, l in ipairs(lbl) do new("map", l) end
    for i = 1, 6 do new("magpull", "magpull_" .. i) end
    for i = 1, 4 do new("mag", "west_mag_" .. i); new("mag", "east_mag_" .. i) end
    for i = 1, 26 do new("sniper", "sniper_" .. i) end
    player = new("player", "player")
    dofile(script); Start()
    return Save()
end
local function tick(t) now = t; Update(0.1) end
local function last(name)
    for i = #calls, 1, -1 do if calls[i][1] == name then return calls[i] end end
end

-- Startup: AIP, resources, VO, cloaked escort, camera, snipers hunt the player once.
local s = fresh()
tick(0)
assert(count("SetAIP", "chmisn08.aip") == 1 and count("SetPilot") == 1)
assert(count("AudioMessage", "ch08001.wav") == 1 and count("CameraReady") == 1)
assert(count("Cloak") == 8 and count("Attack") == 26 and s.missionState == 3)
tick(1); assert(count("Attack") == 26, "snipers retarget only on player change")
local old = player; player = new("other"); tick(2); assert(count("Attack") == 52); player = old; tick(3)

-- Cutscene trigger, 22s hold, then cleanup and delayed convoy.
dist[tostring(labels.west_1_1) .. ":cut_trigger"] = 49
local w11 = labels.west_1_1
tick(4); assert(s.missionState == 4 and s.stateTimer == 26)
tick(26); assert(s.missionState == 4, "strict timer")
tick(27); assert(s.missionState == 5 and count("CameraFinish") == 1)
assert(count("AudioMessage", "ch08002.wav") == 1 and count("RemoveObject") == 9)
tick(57); assert(s.missionState == 5)
tick(58)
assert(s.missionState == 6 and count("BuildObject", "svapc") == 1 and count("BuildObject", "svfigh") == 2)
assert(count("Defend2") == 2 and count("AudioMessage", "ch08003.wav") == 1)
for i = 1, 4 do tick(58 + i * 5.01) end
assert(s.missionState == 10 and count("BuildObject", "svapc") == 5)
assert(last("AddObjective")[2] == "ch08001.otf")
-- ch08003 VO ends: APC convoy nav spawns once.
done = true; tick(90); tick(91)
assert(count("BuildObject", "apcamr") == 1 and s.soundHandle == nil)
done = false

-- Fail: a convoy APC lost.
local function failed(des) local f = last("FailMission"); return f and f[3] == des end
local saved = Save()
objs[s.apc[1]].alive = false; tick(92)
assert(failed("ch08lsed.des") and s.missionState == 100)

-- Success route.
s = fresh(); tick(0)
dist[tostring(w11)] = nil
dist[tostring(labels.west_1_1) .. ":cut_trigger"] = 10
tick(1); tick(23.01); tick(54); tick(54.1)
local t = 60
for i = 1, 5 do t = t + 6; tick(t) end
assert(s.missionState == 10)
local apc3, apc4 = s.apc[3], s.apc[4]
player = apc4
dist[tostring(apc4) .. ":" .. tostring(s.nav)] = 30
t = t + 1; tick(t); assert(s.missionState == 11)
t = t + 6; tick(t)
assert(s.missionState == 13 and count("SetScrap", 1) >= 1 and last("SetObjectiveOn")[2] == apc3)
assert(count("AudioMessage", "ch08004.wav") == 1)
done = true; t = t + 1; tick(t); assert(s.missionState == 15)
dist.trigger_1 = 29; dist.apc_fail = 200
t = t + 1; tick(t); assert(s.missionState == 16 and count("AudioMessage", "ch08006.wav") == 1)
-- Staying in the APC for 20s fails.
local keep = Save()
t = t + 21; tick(t); assert(failed("ch08lseg.des") and s.missionState == 100)

s = fresh(); tick(0)
-- (Re-run to the jump-out state by editing state; flow above already covered.)
s.missionState = 16; s.stateTimer = 1000
s.apc = {[0] = new("svapc"), new("svapc"), new("svapc"), new("svapc"), new("svapc")}
player = s.apc[4]; tick(5); assert(s.missionState == 16)
player = new("pilot"); tick(6)
assert(s.missionState == 17 and last("SetPerceivedTeam")[3] == 2 and s.stateTimer == 26)
tick(27); assert(s.missionState == 18 and count("CameraReady") == 2)
cancel = false; tick(32); assert(s.missionState == 18, "5s boundary")
tick(32.1)
assert(s.missionState == 19 and last("MakeExplosion")[2] == "xpltrsd")
assert(count("MakeExplosion", "xpltrsr") == 1, "D3D destruction effect on the APC")
assert(count("BuildObject", "cvrecy") == 1 and count("BuildObject", "cvmuf") == 1
    and count("BuildObject", "cvslf") == 1 and count("RemoveObject") >= 6)
assert(last("SetScrap")[3] == 500)
tick(37.2); assert(s.missionState == 21 and count("CameraFinish") == 1)
assert(s.stateTimer == 37.2 + 300)

-- Recycler and factory both lost after the bang fails the mission.
local rf = Save()
objs[s.recycler].alive = false; objs[s.factory].alive = false
tick(40); assert(failed("ch08lsea.des") and s.missionState == 100)

-- Objective reveal, power/comm timer, wrecking sequence, victory.
s = fresh(); tick(0)
s.missionState = 21; s.stateTimer = 10
s.recycler = new("cvrecy"); s.factory = new("cvmuf")
tick(11); assert(count("SetScrap", 2) >= 1 and s.stateTimer == 0)
dist.nw_trigger = 60
tick(12)
assert(s.missionState == 23 and count("AudioMessage", "ch08007.wav") == 1
    and count("AudioMessage", "ch08008.wav") == 1 and count("SetObjectiveOn") == 6)
assert(last("SetUserTarget")[2] == labels.howitzer_nw and last("AddObjective")[2] == "ch08002.otf")
tick(13); assert(count("StartCockpitTimer") == 0)
objs[labels.west_power].alive = false; tick(14)
assert(s.west_powerDead and count("StartCockpitTimer") == 1 and last("StartCockpitTimer")[2] == 270)
assert(count("RemoveObject", labels.west_bolt) == 1)
objs[labels.west_comm].alive = false; objs[labels.east_comm].alive = false
tick(15); assert(count("StartCockpitTimer") == 1 and s.missionState == 23)
-- Timer expiry fails.
local pre = Save()
cockpit = 0; tick(16); assert(failed("ch08lsef.des") and s.missionState == 100)
cockpit = 270
s = fresh(); tick(0)
s.missionState = 23; s.recycler = new("cvrecy"); s.factory = new("cvmuf"); s.stateTimer = 0
objs[labels.west_power].alive = false; objs[labels.east_power].alive = false
objs[labels.west_comm].alive = false; objs[labels.east_comm].alive = false
tick(20)
assert(count("HideCockpitTimer") == 1 and s.missionState == 27 and s.stateTimer == 60)
assert(count("RemoveObject", labels.west_bolt) == 1 and objs[labels.east_bolt], "east_bolt is never removed (source bug kept)")
assert(last("AddObjective")[2] == "ch08004.otf" and last("AddObjective")[3] == "white")
local expect = {{27, 12}, {28, 11}, {29, 9}, {30, 13}, {31, 15}, {32, 15}, {33, 7}, {34, 8}, {35, 6}}
local tt = 60
for _, e in ipairs(expect) do
    assert(s.missionState == e[1], "state " .. e[1])
    tick(tt - 0.01); assert(s.missionState == e[1], "strict timer")
    tick(tt + 0.01)
    assert(s.missionState == e[1] + 1)
    tt = tt + 0.01 + e[2]
end
assert(count("MakeExplosion", "xpltrsd") >= 14)
tick(tt + 1)
assert(s.missionState == 100 and count("AudioMessage", "ch08009.wav") == 1)
local win = last("SucceedMission"); assert(win[3] == "ch08win.des" and win[2] == tt + 11)
assert(last("AddObjective")[3] == "green")

-- Spawn waves fire once each; spawn_2/3 alt triggers share their flag.
s = fresh(); tick(0)
nearest.spawn_1 = new("tank"); dist["spawn_1"] = 99; tick(1); tick(2)
assert(count("BuildObject", "svfigh") == 3)
nearest.spawn_2a = new("tank"); dist["spawn_2a"] = 99; tick(3)
assert(count("BuildObject", "svtank") == 5)
nearest.spawn_2 = new("tank"); dist["spawn_2"] = 99; tick(4); assert(count("BuildObject", "svtank") == 5)
nearest.spawn_4 = nearest.spawn_1; dist["spawn_4"] = 100; tick(5); assert(count("BuildObject", "svwalk") == 0)
dist["spawn_4"] = 99; tick(6); assert(count("BuildObject", "svwalk") == 3)

-- Cloak field disables cloaking and reports core failure once.
s = fresh(); tick(0)
objs[player].cloak = true; dist.west_cloak = 199; tick(1)
assert(count("Decloak") == 1 and count("AudioMessage", "ch04002.wav") == 1 and s.userCloakState == 1)
objs[player].cloak = true; tick(2); assert(count("Decloak") == 1, "waits for the VO")
done = true; tick(3); assert(s.coreFailSound == nil)
tick(4); assert(count("Decloak") == 2)

-- Convoy-formation rules (checkAPCs): lost lead APC, straggler, early break-off.
local function convoy()
    local st = fresh(); tick(0)
    st.missionState = 10
    st.apc = {[0] = new("svapc"), new("svapc"), new("svapc"), new("svapc"), new("svapc")}
    return st
end
s = convoy(); objs[s.apc[4]].alive = false; objs[s.apc[4]].hp = 0; tick(1)
assert(failed("ch08lsed.des") and last("FailMission")[2] == 3 and s.missionState == 100)
s = convoy(); dist[tostring(s.apc[4]) .. ":" .. tostring(s.apc[3])] = 101; s.apcInLine = 1; tick(1)
assert(failed("ch08lsee.des") and last("FailMission")[2] == 21 and count("AudioMessage", "ch08005.wav") == 1)
s = convoy(); dist[tostring(s.apc[4]) .. ":" .. tostring(s.apc[3])] = 101; s.apcInLine = 0.5; tick(1)
assert(s.missionState == 10, "apcInLine 0..2 is inert unless exactly 1")
s.apcInLine = 5; tick(10); assert(failed("ch08lseb.des"))
s = convoy(); dist.break_point = 49; tick(1); assert(s.apcInLine == 2 and s.missionState == 10)
s = convoy(); dist.apc_fail = 29; tick(1)
assert(failed("ch08lsec.des") and last("FailMission")[2] == 21)

-- Save/Load round trip keeps the state table without replaying spawns.
s = fresh(); tick(0)
local snap = Save(); local n = #calls
Load(snap); assert(Save() == snap and #calls == n)


-- TRO 1.3: the opening cut_1 scene is skippable while waiting for the trigger.
do
    local k = fresh(); tick(0); assert(k.missionState == 3)
    cancel = true; tick(1); cancel = false
    assert(k.missionState == 5 and k.stateTimer == 31 and count("CameraFinish") == 1)
    assert(count("AudioMessage", "ch08002.wav") == 1 and count("RemoveObject") == 9)
end
-- ...and while the 22 s hold runs.
do
    local k = fresh(); tick(0)
    dist[tostring(labels.west_1_1) .. ":cut_trigger"] = 49
    tick(1); assert(k.missionState == 4)
    cancel = true; tick(2); cancel = false
    assert(k.missionState == 5 and k.stateTimer == 32 and count("CameraFinish") == 1)
    assert(count("AudioMessage", "ch08002.wav") == 1 and count("RemoveObject") == 9)
end
-- TRO 1.3: comm towers are topped up every frame until the destroy-power-plants phase.
do
    local k = fresh(); tick(0)
    objs[labels.west_comm].hp = 0.25; objs[labels.east_comm].hp = 0.5; tick(1)
    assert(count("AddHealth", labels.west_comm) == 1 and objs[labels.west_comm].hp == 1)
    assert(count("AddHealth", labels.east_comm) == 1 and objs[labels.east_comm].hp == 1)
    k.missionState = 23; objs[labels.west_comm].hp = 0.25; tick(2)
    assert(count("AddHealth", labels.west_comm) == 1 and objs[labels.west_comm].hp == 0.25, "no top-up from state 23")
end
print("Chinese08 behaviour tests passed")
