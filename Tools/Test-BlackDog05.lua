-- Run from the repository root: lua5.1 Tools/Test-BlackDog05.lua
-- Stock API stubs exercise mission state, not engine rendering/AI behavior.
local script = "Scripts/bd05.lua"
local now, objects, labels, messages, events, camera, audioFailure, spawnFailure
local nextHandle, nextMessage, lastSuccess

local function check(condition, explanation)
    assert(condition, explanation)
end
local function event(kind, ...)
    events[#events + 1] = {kind, ...}
end
local function count(kind, value)
    local n = 0
    for _, e in ipairs(events) do
        if e[1] == kind and (value == nil or e[2] == value) then n = n + 1 end
    end
    return n
end
local function addObject(label)
    nextHandle = nextHandle + 1
    objects[nextHandle] = {alive = true, valid = true, label = label}
    if label then labels[label] = nextHandle end
    return nextHandle
end

function IsValid(h) return objects[h] ~= nil and objects[h].valid end
function IsAlive(h)
    check(IsValid(h), "IsAlive received an invalid handle")
    return objects[h].alive
end
function GetHandle(label) return labels[label] end
function GetPlayerHandle() return labels.player end
function GetTime() return now end
function SetScrap(team, amount) event("scrap", team, amount) end
function SetPilot(team, amount) event("pilots", team, amount) end
function ClearObjectives() event("clear") end
function AddObjective(name, color) event("objective", name, color) end
function BuildObject(odf, team, path)
    event("build", odf, team, path)
    if spawnFailure then return nil end
    local h = addObject()
    objects[h].odf, objects[h].path = odf, path
    -- Exercise the reentrant engine callback; cut code must stay disabled.
    AddObject(h)
    return h
end
function SetCloaked(h)
    check(IsValid(h), "cloak received invalid handle")
    objects[h].cloaked = true
    event("cloak", h)
end
local function command(name, h, target, priority)
    check(IsValid(h), "command received invalid handle")
    if type(target) ~= "string" then check(IsValid(target), "invalid command target") end
    objects[h].command = {name, target, priority}
    event(name, h, target, priority)
end
function Goto(h, target, priority) command("go", h, target, priority) end
function Attack(h, target, priority) command("attack", h, target, priority) end
function Retreat(h, target, priority) command("retreat", h, target, priority) end
function PortalIn(h)
    check(IsValid(h), "invalid portal activation")
    event("portal_in", h)
end
function IsTouching(h, target)
    check(IsValid(h) and IsValid(target), "invalid contact query")
    return objects[h].touching == target
end
function RemoveObject(h)
    check(IsValid(h), "invalid removal")
    objects[h].valid = false
    event("remove", h)
end
function AudioMessage(file)
    event("audio", file)
    if audioFailure[file] then return nil end
    nextMessage = nextMessage + 1
    messages[nextMessage] = {file = file, done = false}
    return nextMessage
end
function IsAudioMessageDone(h)
    check(messages[h] ~= nil, "invalid audio query")
    return messages[h].done
end
function StopAudioMessage(h)
    check(messages[h] ~= nil, "invalid audio stop")
    messages[h].done = true
    event("audio_stop", h)
end
function CameraReady() event("camera_ready") return true end
function CameraPath(path, height, speed, target)
    check(IsValid(target), "invalid camera target")
    event("camera", path, height, speed, target)
    return camera.arrived
end
function CameraCancelled() return camera.cancelled end
function CameraFinish() event("camera_finish") return true end
function SucceedMission(time, file)
    check(time > now, "success must use a future absolute time")
    lastSuccess = {time, file}
    event("success", time, file)
end

local function fresh()
    now, objects, labels, messages, events = 0, {}, {}, {}, {}
    camera, audioFailure, spawnFailure = {arrived = false, cancelled = false}, {}, false
    nextHandle, nextMessage, lastSuccess = 0, 0, nil
    addObject("player")
    addObject("recycler")
    addObject("portal")
    for i = 1, 15 do addObject("unit_" .. i) end
    dofile(script)
    Start()
end
local function step(t) now = t; Update(0.1) end
local function finishIntro()
    camera.arrived = true
    step(now)
    camera.arrived = false
end
local function reload()
    -- Recreate script locals and callbacks, retaining engine objects/messages.
    -- Copy the table to ensure Load restores state rather than relying on M.
    local function copy(v)
        if type(v) ~= "table" then return v end
        local result = {}
        for k, x in pairs(v) do result[k] = copy(x) end
        return result
    end
    local snapshot = copy(Save())
    dofile(script)
    Load(snapshot)
end
local function defeatAll()
    for i = 0, 45 do
        local h = Save().units[i]
        if h and objects[h] then objects[h].alive = false end
    end
end

-- Startup and save/load while the opening camera is active.
fresh()
step(0)
check(count("audio", "bd05001.wav") == 1, "intro starts once")
check(Save().waitTime[4] == 1140, "timers start during intro")
reload()
step(100)
check(count("audio", "bd05001.wav") == 1, "load must not replay intro")
check(count("scrap") == 1 and count("pilots") == 1, "load must not reset resources")
check(Save().waitTime[4] == 1140, "load must not shift timers")
camera.cancelled = true
step(101)
camera.cancelled = false
check(Save().cameraComplete[0] and count("audio_stop") == 1, "intro cancellation")

-- Exact strict boundaries and all seven waves; source ordering is tested by
-- parity separately. Retain each ODF, path, command, priority, and cloak.
local waves = {
    {300, 15, 18, "first_wave", "go", {"cvfigh", "cvfigh", "cvltnk", "cvltnk"}},
    {420, 44, 45, "howit", "go", {"cvartl", "cvartl"}},
    {450, 34, 38, "rear_attack", "attack", {"cvtnk", "cvtnk", "cvtnk", "cvtnk", "cvtnk"}},
    {540, 19, 22, "second_wave", "attack", {"cvltnk", "cvltnk", "cvtnk", "cvtnk"}},
    {660, 39, 43, "rear_attack", "attack", {"cvtnk", "cvtnk", "cvtnk", "cvtnk", "cvtnk"}},
    {840, 23, 27, "third_wave", "go", {"cvtnk", "cvtnk", "cvhraz", "cvhraz", "cvwalk"}},
    {1140, 28, 33, "fourth_wave", "go", {"cvtnk", "cvtnk", "cvhraz", "cvhraz", "cvwalk", "cvwalk"}},
}
step(240)
check(count("audio", "bd05002.wav") == 0, "radio strict boundary")
step(240.1)
check(count("audio", "bd05002.wav") == 1, "radio fires after boundary")
for _, w in ipairs(waves) do
    local before = count("build")
    step(w[1])
    check(count("build") == before, "wave fired at exact boundary")
    step(w[1] + 0.1)
    check(count("build") == before + w[3] - w[2] + 1, "wave count")
    for i = w[2], w[3] do
        local o = objects[Save().units[i]]
        check(o.odf == w[6][i - w[2] + 1] and o.path == w[4], "wave ODF/path")
        check(o.cloaked and o.command[1] == w[5], "wave cloak/command")
        check(o.command[2] == labels.recycler and o.command[3] == 1, "wave target/priority")
    end
end
check(count("build") == 31 and count("cloak") == 31, "all 31 reinforcements")
check(not Save().objective2Complete, "cannot win with enemies alive")
step(1141)
check(count("build") == 31, "waves must not repeat")
reload()
step(1142)
check(count("build") == 31, "load must not duplicate waves")

-- Any of the initial 15 or reinforcement 31 must prevent completion.
defeatAll()
local blocker = Save().units[0]
objects[blocker].alive = true
step(1143)
check(not Save().objective2Complete, "initial-map enemy remains a blocker")
objects[blocker].alive = false
blocker = Save().units[45]
objects[blocker].alive = true
step(1144)
check(not Save().objective2Complete, "last artillery remains a blocker")
objects[blocker].alive = false
step(1145)
check(Save().objective1Complete and Save().objective2Complete, "orphaned objective fix")
check(Save().numBombers == 0 and Save().whichTimer == 0, "cut construction gate stays disabled")
check(count("retreat") == 6 and count("portal_in") == 1, "six quitters and inward portal")
check(count("audio", "bd05004.wav") == 1 and count("audio", "bd05005.wav") == 1, "retreat audio order")
local expected = {"cvtnk", "cvtnk", "cvwalk", "cvwalk", "cspilo", "cvltnk"}
for i = 0, 5 do
    local o = objects[Save().quitters[i]]
    check(o.odf == expected[i + 1] and o.path == "quitters", "retreater ODF/path")
    check(o.command[2] == "portal_in" and o.command[3] == 1, "retreat route/priority")
    check(not o.cloaked, "retreaters are not cloaked in source")
end

-- Only dead/contacting quitters disappear. Survivors do not gate victory.
local q0, q1, q2 = Save().quitters[0], Save().quitters[1], Save().quitters[2]
objects[q0].touching = labels.portal
objects[q1].alive = false
step(1146)
check(Save().quitters[0] == nil and not objects[q0].valid, "portal contact removes unit")
check(Save().quitters[1] == nil and count("remove") == 1, "dead quitter clears without removal")
check(Save().quitters[2] == q2, "noncontacting survivor persists")
reload()
local retreatMessage = Save().quitterSound
messages[retreatMessage].done = true
step(1147)
check(Save().quitterDelay == 1150, "three seconds after narration")
step(1151)
check(not Save().quitterMovieDone, "15-second minimum still applies")
step(1160)
check(not Save().quitterMovieDone, "15-second boundary is strict")
step(1160.1)
check(Save().quitterMovieDone and Save().won, "success after movie without construction gate")
check(lastSuccess == nil, "wait for congratulations audio")
reload()
messages[Save().sound6].done = true
step(1161)
check(lastSuccess[1] == 1161.1 and lastSuccess[2] == "bd05win.des", "absolute success delay")
reload()
step(1162)
check(count("success") == 1, "success does not replay after save/load")

-- Cancellation bypasses narration and minimum duration, just as the source.
fresh()
step(0); finishIntro(); step(1141); defeatAll(); step(1142)
camera.cancelled = true
step(1143)
check(Save().quitterMovieDone and Save().won, "retreat cancellation releases shot")
check(not messages[Save().quitterSound].done, "native cancellation leaves retreat audio running")

-- Missing audio cannot strand the player; normal thresholds are unchanged.
fresh()
audioFailure["bd05005.wav"], audioFailure["bd05006.wav"] = true, true
step(0); finishIntro(); step(1141); defeatAll(); step(1142)
step(1157)
check(not Save().won, "missing audio still respects strict 15-second boundary")
step(1157.1)
check(Save().won and count("success") == 1, "missing audio completes normally")
step(1158)
check(count("success") == 1, "missing final audio succeeds once")

-- Long narration must add its full three seconds even after the minimum.
fresh()
step(0); finishIntro(); step(1141); defeatAll(); step(1142)
step(1160)
check(not Save().quitterMovieDone, "movie waits for unfinished narration")
messages[Save().quitterSound].done = true
step(1161)
check(Save().quitterDelay == 1164, "late narration starts post-audio delay")
reload()
step(1164)
check(not Save().quitterMovieDone, "post-audio boundary is strict")
step(1164.1)
check(Save().quitterMovieDone, "late narration releases after three seconds")

-- Eliminating initial units early never bypasses the final-wave gate.
fresh()
step(0); finishIntro(); defeatAll(); step(250)
check(not Save().objective2Complete and not Save().quittersSpawned,
    "early kills must wait for the fourth wave")

-- Invalid handles/spawn failures must not invoke handle-taking APIs.
fresh()
labels.recycler, labels.portal = nil, nil
for i = 1, 15 do labels["unit_" .. i] = nil end
Start()
spawnFailure = true
step(0); step(1141)
check(Save().quitterMovieDone and Save().won, "invalid camera subjects do not stall")

print("BlackDog05: startup, strict waves, all-enemy gate, retreat, audio, cameras, save/load and handle guards passed")
