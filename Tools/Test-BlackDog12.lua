-- Run from the repository root: lua5.1 Tools/Test-BlackDog12.lua
-- Engine-free behavior checks; portal visuals/physics still need BZR testing.
local script = "Scripts/bdmisn12.lua"
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function NewMission()
    local env = {}
    local health, messages, log = {}, {}, {}
    local nextObject, nextMessage = 100, 0
    local now, arrived, cancelled, missingAudio, failedBuild = 0, false, false, false, false
    local labels = {portal = 1}
    for i = 1, 4 do
        labels["shield_" .. i] = 10 + i
        labels["power_" .. i] = 20 + i
        labels["goal_" .. i] = 30 + i
    end
    for _, h in pairs(labels) do health[h] = 1 end
    local function event(name, ...)
        log[#log + 1] = {name, ...}
    end
    local function valid(h)
        return h ~= nil and health[h] ~= nil
    end
    local function requireHandle(h)
        assert(valid(h), "invalid handle passed to engine mock")
    end
    env.GetHandle = function(label) return labels[label] end
    env.GetPlayerHandle = function() return 99 end
    env.GetTime = function() return now end
    env.IsValid = valid
    env.GetHealth = function(h) requireHandle(h); return health[h] end
    env.BuildObject = function(odf, team, path)
        if failedBuild then event("BuildFailed", odf, team, path); return nil end
        nextObject = nextObject + 1
        health[nextObject] = 1
        event("BuildObject", odf, team, path, nextObject)
        return nextObject
    end
    env.BuildObjectAtPortal = function(odf, team, portal)
        requireHandle(portal)
        if failedBuild then event("PortalBuildFailed", odf); return nil end
        nextObject = nextObject + 1
        health[nextObject] = 1
        event("BuildObjectAtPortal", odf, team, portal, nextObject)
        return nextObject
    end
    for _, name in ipairs({"SetCloaked", "PortalOut", "ActivatePortal", "DeactivatePortal"}) do
        local name = name
        env[name] = function(h) requireHandle(h); event(name, h) end
    end
    for _, name in ipairs({"Attack", "Defend2"}) do
        local name = name
        env[name] = function(h, target, priority)
            requireHandle(h); requireHandle(target); event(name, h, target, priority)
        end
    end
    env.Goto = function(h, path, priority)
        requireHandle(h); event("Goto", h, path, priority)
    end
    env.CameraPath = function(path, height, speed, target)
        requireHandle(target)
        check(path == "camera_start" and height == 300 and speed == 2000, "camera parameters")
        return arrived
    end
    env.CameraCancelled = function() return cancelled end
    for _, name in ipairs({"CameraReady", "CameraFinish", "ClearObjectives", "SetScrap",
                           "SetPilot", "AddObjective", "SucceedMission", "FailMission"}) do
        local name = name
        env[name] = function(...) event(name, ...) end
    end
    env.AudioMessage = function(file)
        event("AudioMessage", file)
        if missingAudio then return nil end
        nextMessage = nextMessage + 1
        messages[nextMessage] = false
        return nextMessage
    end
    env.IsAudioMessageDone = function(msg)
        assert(messages[msg] ~= nil, "invalid audio handle")
        return messages[msg]
    end
    env.StopAudioMessage = function(msg)
        assert(messages[msg] ~= nil, "invalid audio handle")
        messages[msg] = true
        event("StopAudioMessage", msg)
    end
    -- Permit only standard Lua functions used by the mission.
    env.type, env.math, env.pairs, env.ipairs = type, math, pairs, ipairs
    setmetatable(env, {__index = function(_, key) error("unexpected global: " .. key) end})
    local chunk = assert(loadfile(script))
    setfenv(chunk, env)
    chunk()
    env.Start()
    local driver = {env = env, labels = labels, health = health, log = log}
    function driver:step(time) now = time; env.Update(0.1) end
    function driver:camera(a, c) arrived, cancelled = a, c end
    function driver:audioMissing() missingAudio = true end
    function driver:buildFail() failedBuild = true end
    function driver:finish(msg) messages[msg] = true end
    function driver:events(name)
        local result = {}
        for _, e in ipairs(log) do if e[1] == name then result[#result + 1] = e end end
        return result
    end
    function driver:clear() for i = #log, 1, -1 do log[i] = nil end end
    return driver
end

local m = NewMission()
m:step(0)
check(#m:events("SetScrap") == 2 and #m:events("SetPilot") == 1, "one-time resources")
check(m.env.Save().delays[4] == 780 and m.env.Save().scrapDelay == 60, "native timings")
m:step(3)
check(#m:events("AudioMessage") == 0, "intro uses strict timer")
m:step(3.1)
check(m:events("AudioMessage")[1][2] == "bd12001.wav", "intro voice")
m:camera(false, true)
m:step(3.2)
check(#m:events("StopAudioMessage") == 1 and #m:events("CameraFinish") == 1, "cancel intro")
check(m.env.Save().cameraComplete[0], "camera latch")
check(#m:events("SetScrap") == 2, "resource setup does not repeat")

-- Each attacker/defender entry is {ODF, spawn path, command, target slot}.
local waves = {
    {120, {
        {"cvfigh", "attack_1", "Attack", "power1"},
        {"cvfigh", "attack_1", "Attack", "power1"},
        {"cvfigh", "attack_1", "Attack", "power1"},
        {"cvtnk", "defend_1", "Defend2", 1},
        {"cvtnk", "defend_1", "Defend2", 2}}},
    {240, {
        {"cvfigh", "attack_2", "Attack", "power2"},
        {"cvfigh", "attack_2", "Attack", "power2"},
        {"cvfigh", "attack_2", "Attack", "power2"},
        {"cvhtnk", "attack_2", "Attack", "power2"},
        {"cvfigh", "defend_2", "Defend2", 1},
        {"cvfigh", "defend_2", "Defend2", 2},
        {"cvfigh", "defend_2", "Defend2", 3},
        {"cvhtnk", "defend_2", "Defend2", 4}}},
    {360, {
        {"cvhraz", "attack_3", "Attack", "power3"},
        {"cvhraz", "attack_3", "Attack", "power3"},
        {"cvfigh", "attack_3", "Attack", "power3"},
        {"cvfigh", "attack_3", "Attack", "power3"},
        {"cvtnk", "defend_3", "Defend2", 1},
        {"cvtnk", "defend_3", "Defend2", 2},
        {"cvfigh", "defend_3", "Defend2", 3},
        {"cvfigh", "defend_3", "Defend2", 4}}},
    {480, {
        {"cvwalk", "attack_4", "Attack", "shield1"},
        {"cvltnk", "defend_4", "Defend2", 1},
        {"cvltnk", "defend_4", "Defend2", 1},
        {"cvwalk", "attack_5", "Attack", "shield2"},
        {"cvltnk", "defend_5", "Defend2", 4},
        {"cvltnk", "defend_5", "Defend2", 4},
        {"cvwalk", "attack_6", "Attack", "shield3"},
        {"cvtnk", "defend_6", "Defend2", 7},
        {"cvtnk", "defend_6", "Defend2", 7},
        {"cvwalk", "attack_7", "Attack", "shield4"},
        {"cvtnk", "defend_7", "Defend2", 10},
        {"cvtnk", "defend_7", "Defend2", 10},
        {"cvwalk", "attack_8", "Attack", "portal"},
        {"cvhtnk", "defend_8", "Defend2", 13},
        {"cvhtnk", "defend_8", "Defend2", 13}}}
}
for _, wave in ipairs(waves) do
    m:clear(); m:step(wave[1])
    local atBoundary = 0
    for _, e in ipairs(m:events("BuildObject")) do if e[3] == 2 then atBoundary = atBoundary + 1 end end
    check(atBoundary == 0, "strict wave boundary")
    m:clear(); m:step(wave[1] + 0.1)
    local builds = m:events("BuildObject")
    check(#builds == #wave[2], "wave count")
    local commands = {}
    for _, e in ipairs(m.log) do
        if e[1] == "Attack" or e[1] == "Defend2" then commands[#commands + 1] = e end
    end
    local expectedCloaks = 0
    for i, entry in ipairs(wave[2]) do
        local b, cmd = builds[i], commands[i]
        check(b[2] == entry[1] and b[3] == 2 and b[4] == entry[2], "wave ODF/team/path")
        local target = type(entry[4]) == "number" and builds[entry[4]][5] or
            m.labels[entry[4]:gsub("(%a+)(%d)", "%1_%2")]
        check(cmd[1] == entry[3] and cmd[2] == b[5] and cmd[3] == target and cmd[4] == 1,
              "wave command/escort target/priority")
        if entry[1] ~= "cvwalk" then expectedCloaks = expectedCloaks + 1 end
    end
    check(#m:events("SetCloaked") == expectedCloaks, "walker cloak exceptions")
    m:clear(); m:step(wave[1] + 0.2)
    check(#m:events("BuildObject") == 0, "wave only once")
end

m:clear(); m:step(546); check(#m:events("BuildObjectAtPortal") == 0, "strict tank timer")
m:step(546.1); m:step(552.1)
local reinforcement = m:events("BuildObjectAtPortal")
check(#reinforcement == 3 and reinforcement[1][2] == "bvtank" and
      reinforcement[2][2] == "bvtank" and reinforcement[3][2] == "bvfigh", "native escort order")
check(#m:events("Goto") == 3 and m:events("Goto")[1][3] == "follow" and
      m:events("Goto")[1][4] == 1, "reinforcement route/priority")
m:step(554.1); check(#m:events("DeactivatePortal") == 1, "native early portal close")
m:step(555.1)
check(m.env.Save().objective1Complete and not m.env.Save().objective2Complete, "live goals block win")
m:step(778.1)
check(#m:events("PortalOut") == 1 and #m:events("ActivatePortal") == 1, "outward portal")
m:step(780.1)
check(m:events("BuildObjectAtPortal")[4][2] == "bvrecyd", "13-minute recycler retained")
check(m.env.Save().recycler ~= nil, "recycler handle retained")

-- Thresholds, voice mapping, dead infrastructure and one-shot counterattacks.
local h = NewMission(); h:camera(true, false); h:step(0); h:clear()
for i = 1, 4 do h.health[h.labels["power_" .. i]] = 0.25 end
h:step(1); check(#h:events("AudioMessage") == 0, "quarter health is not below threshold")
for i = 1, 4 do
    h.health[h.labels["power_" .. i]] = 0.24
    h.health[h.labels["shield_" .. i]] = 0.24
end
h:step(2)
check(#h:events("AudioMessage") == 8, "eight independent warnings")
for i = 1, 4 do
    check(h:events("AudioMessage")[2*i-1][2] == "bd1200" .. (i + 4) .. ".wav" and
          h:events("AudioMessage")[2*i][2] == "bd1200" .. (i + 4) .. ".wav", "paired warning voices")
    h.health[h.labels["power_" .. i]] = nil -- deleted handles
end
h:clear(); h:step(3)
check(#h:events("BuildObject") == 8 and #h:events("SetCloaked") == 8, "two raiders per dead pair")
for i, b in ipairs(h:events("BuildObject")) do
    check(b[2] == "cvltnk" and b[4] == "despor_" .. math.ceil(i/2), "counterattack paths")
end
h:clear(); h:step(4)
check(#h:events("BuildObject") == 0 and #h:events("AudioMessage") == 0, "death/warnings latch")

local function ReadyForWin()
    local w = NewMission(); w:camera(true, false); w:step(0)
    local state = w.env.Save()
    state.objective1Complete = true
    for i = 1, 4 do w.health[w.labels["goal_" .. i]] = nil end
    return w
end
local w = ReadyForWin(); w:step(1)
check(w.env.Save().objective2Complete and #w:events("SucceedMission") == 0, "victory waits for audio")
w:finish(w.env.Save().winSound); w:step(2)
check(w:events("SucceedMission")[1][2] == 3 and
      w:events("SucceedMission")[1][3] == "bd12win.des", "victory delay/description")
w:step(3); check(#w:events("SucceedMission") == 1, "victory once")
local f = NewMission(); f:camera(true, false); f:step(0); f.health[1] = nil; f:step(1)
check(#f:events("FailMission") == 0, "portal death waits for audio")
f:finish(f.env.Save().portalDeadSound); f:step(2)
check(f:events("FailMission")[1][2] == 4 and f:events("FailMission")[1][3] == "bd12lsea.des",
      "failure delay/description")
f:step(3); check(#f:events("FailMission") == 1, "failure once")
local a = ReadyForWin(); a:audioMissing(); a:step(1)
check(#a:events("SucceedMission") == 1, "missing victory audio")
local b = NewMission(); b:audioMissing(); b.health[1] = nil; b:step(0)
check(#b:events("FailMission") == 1 and #b:events("CameraFinish") == 1, "missing portal/audio")
local c = ReadyForWin(); c:audioMissing(); c.health[1] = nil; c:step(1)
check(#c:events("SucceedMission") == 1 and #c:events("FailMission") == 0, "source success-first tie")
local d = NewMission(); d:camera(true, false); d:step(0); d:buildFail(); d:step(121)
check(#d:events("Attack") == 0 and #d:events("Defend2") == 0, "failed builds do not receive commands")

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end
local s = NewMission(); s:step(0); s:step(3.1)
local snapshot = clone(s.env.Save())
s.env.Load(snapshot); s:clear(); s:camera(false, true); s:step(3.2)
check(#s:events("CameraReady") == 0 and #s:events("AudioMessage") == 0 and
      #s:events("StopAudioMessage") == 1, "load continues active intro")
s:step(121); s:clear(); s.env.Load(clone(s.env.Save())); s:step(122)
check(#s:events("BuildObject") == 0 and #s:events("SetScrap") == 0, "load does not repeat waves/setup")
local scrap = NewMission(); scrap:camera(true, false); scrap:step(0); scrap:step(60)
check(#scrap:events("BuildObject") == 0, "strict scrap boundary")
scrap:step(60.1); scrap:step(120.1)
local scrapCount = 0
for _, e in ipairs(scrap:events("BuildObject")) do
    if e[2] == "npscr1" then scrapCount = scrapCount + 1 end
end
check(scrapCount == 6, "scrap cadence relative to actual spawn")
scrap:clear(); scrap:step(120.2)
check(#scrap:events("BuildObject") == 6, "six scrap on next minute")
print("BlackDog12: " .. checks .. " behavior checks passed (" .. _VERSION .. ")")
