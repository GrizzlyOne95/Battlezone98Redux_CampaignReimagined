-- Run from repository root: lua5.1 Tools/Test-BlackDog06.lua
-- API stubs test mission decisions, not engine AI, portal rendering or remapping.
local now, objects, labels, events, messages, camera, nextHandle, nextMessage
local randomValues, randomIndex, audioMissing
AiCommand = {NONE = 0, GO = 3}
local function check(value, why) assert(value, why) end
local function event(kind, ...) events[#events + 1] = {kind, ...} end
local function count(kind, value)
    local n = 0
    for _, e in ipairs(events) do
        if e[1] == kind and (value == nil or e[2] == value) then n = n + 1 end
    end
    return n
end
local function add(label, odf)
    nextHandle = nextHandle + 1
    objects[nextHandle] = {valid = true, alive = true, health = 100, maxHealth = 100,
        command = AiCommand.NONE, distance = 1000, odf = odf}
    if label then labels[label] = nextHandle end
    return nextHandle
end
function GetTime() return now end
function GetHandle(label) return labels[label] end
function GetPlayerHandle() return labels.player end
function IsValid(h) return objects[h] ~= nil and objects[h].valid end
function IsAlive(h) check(IsValid(h), "invalid IsAlive"); return objects[h].alive end
function GetCurHealth(h) check(IsValid(h), "invalid health"); return objects[h].health end
function GetMaxHealth(h) check(IsValid(h), "invalid max health"); return objects[h].maxHealth end
function GetCurrentCommand(h) check(IsValid(h), "invalid command query"); return objects[h].command end
function IsOdf(h, odf) check(IsValid(h), "invalid ODF query"); return objects[h].odf == odf end
function AllObjects()
    local i = 0
    return function()
        i = i + 1
        while objects[i] and not objects[i].valid do i = i + 1 end
        if objects[i] then return i end
    end
end
function GetDistance(h, path)
    check(IsValid(h) and path == "apc_in", "APC distance signature")
    return objects[h].distance
end
function math.random()
    randomIndex = randomIndex + 1
    return randomValues[(randomIndex - 1) % #randomValues + 1]
end
function BuildObject(odf, team, path)
    local h = add(nil, odf)
    objects[h].team, objects[h].path = team, path
    event("build", odf, team, path, h)
    AddObject(h) -- exercise reentrant callback
    return h
end
function BuildObjectAtPortal(odf, team, portal)
    check(IsValid(portal), "invalid portal build")
    local h = BuildObject(odf, team, "@portal")
    event("portal_build", odf, team, portal, h)
    return h
end
local function order(kind, h, target)
    check(IsValid(h), "invalid order subject")
    if target ~= nil and type(target) ~= "string" then check(IsValid(target), "invalid target") end
    objects[h].command, objects[h].target = AiCommand.GO, target
    event(kind, h, target)
end
function Goto(h, target) order("go", h, target) end
function Attack(h, target) order("attack", h, target) end
function Follow(h, target) order("follow", h, target) end
function Hunt(h) order("hunt", h) end
function Deploy(h) check(IsValid(h), "invalid deploy"); event("deploy", h) end
function RemoveObject(h) check(IsValid(h), "invalid removal"); objects[h].valid = false; event("remove", h) end
function PortalOut(h) check(IsValid(h), "invalid portal direction"); event("portal_out", h) end
function ActivatePortal(h) check(IsValid(h), "invalid portal activate"); event("portal_active", h) end
function DeactivatePortal(h) check(IsValid(h), "invalid portal deactivate"); event("portal_close", h) end
function AudioMessage(file)
    event("audio", file)
    if audioMissing[file] then return nil end
    nextMessage = nextMessage + 1
    messages[nextMessage] = {file = file, done = false}
    return nextMessage
end
function IsAudioMessageDone(h) check(messages[h] ~= nil, "invalid audio query"); return messages[h].done end
function SetScrap(team, n) event("scrap", team, n) end
function SetPilot(team, n) event("pilots", team, n) end
function ClearObjectives() event("clear") end
function AddObjective(file, color) event("objective", file, color) end
function CameraReady() event("camera_ready"); return true end
function CameraPath(path, height, speed, target)
    check(IsValid(target), "camera must have a valid target")
    event("camera", path, height, speed, target)
    return camera.arrived
end
function CameraCancelled() return camera.cancelled end
function CameraFinish() event("camera_finish"); return true end
function FailMission(time, file) event("fail", file, time) end
function SucceedMission(time, file) event("success", file, time) end
local function fresh()
    now, objects, labels, events, messages = 0, {}, {}, {}, {}
    camera, nextHandle, nextMessage = {arrived = false, cancelled = false}, 0, 0
    randomValues, randomIndex, audioMissing = {0.1, 0.5, 0.8}, 0, {}
    add("player"); add("portal")
    for i = 1, 10 do add("bdtank_" .. i); add("silo_attack" .. i) end
    for _, n in ipairs({1, 2, 3, 7, 9, 10}) do add("2bdest_" .. n) end
    dofile("Scripts/bd06.lua"); Start()
end
local function step(t) now = t; Update(0.1) end
local function done() messages[Save().soundhandle].done = true end
local function reload()
    local function copy(v)
        if type(v) ~= "table" then return v end
        local x = {}; for k, item in pairs(v) do x[k] = copy(item) end; return x
    end
    local saved = copy(Save())
    dofile("Scripts/bd06.lua"); Load(saved)
end
local function state(s, timer)
    Save().missionState = s
    if timer ~= nil then Save().stateTimer = timer end
end
local function stopWaves() Save().stateTimer3, Save().stateTimer4 = 0, 0 end

-- Opening fallthrough, strict audio gate, save/load and cut timer kept disabled.
fresh(); step(0)
check(Save().missionState == 1 and count("camera", "camera_start") == 1, "startup falls through")
check(events[1][1] == "scrap" and events[1][3] == 75, "initial scrap")
step(2); check(count("audio") == 0, "intro exact boundary")
step(2.1); check(count("audio", "bd06001.wav") == 1, "intro after boundary")
reload(); step(3); check(count("scrap") == 1 and count("audio") == 1, "load no replay")
camera.cancelled = true; step(4); camera.cancelled = false
check(Save().missionState == 2 and Save().stateTimer == 24 and Save().stateTimer2 == 664, "intro finish deadlines")
step(24); check(Save().missionState == 2, "waiting1 strict boundary")
step(24.1); check(Save().missionState == 3 and count("go") == 10, "ten fake attackers")
done(); step(25); check(Save().missionState == 4 and Save().stateTimer == 28, "sound2 gate")
step(28); check(Save().missionState == 4, "fake camera strict boundary")
step(28.1); check(Save().missionState == 5 and count("camera", "camera_go") == 1, "camera fallthrough")
reload(); step(33.2)
check(Save().missionState == 6 and count("remove") == 10, "remove all decoys")
for i = 0, 4 do objects[Save().h2bdest[i]].alive = false end
step(34); check(Save().missionState == 6, "sixth target blocks progression")
objects[Save().h2bdest[5]].alive = false
step(35); check(Save().missionState == 7 and Save().stateTimer == 125, "all six dead")
check(Save().stateTimer3 == 145 and Save().stateTimer4 == 115, "ambient wave deadlines")

-- Exactly five friendly casualties no longer overrun the native array; no cap
-- is invented for >5 casualties. Replacement timing and route stay unchanged.
stopWaves()
for i = 0, 4 do objects[Save().bdtank[i]].alive = false end
step(125); check(count("build", "bvrdeva") == 0, "replacement boundary")
step(125.1); check(count("build", "bvrdeva") == 5, "five replacements")
check(Save().missionState == 8 and Save().stateTimer == 215.1, "90 second next wave")
step(215.1); check(count("build", "cvtnk") == 0, "attack1 boundary")
step(215.2); check(Save().missionState == 9 and count("build", "cvtnk") == 2, "attack1 two tanks")
objects[Save().badguy[0]].alive = false
step(216); check(Save().missionState == 10 and IsAlive(Save().badguy[1]), "first-only gate preserved")
step(396); check(Save().missionState == 10, "attack2 exact boundary")
step(396.1); check(Save().missionState == 11 and count("build", "cvtnk") == 5, "attack2 three tanks")
for i = 0, 1 do objects[Save().badguy[i]].alive = false end
step(397); check(Save().missionState == 11, "third tank blocks sound3")
objects[Save().badguy[2]].alive = false; step(398)
check(Save().missionState == 12 and count("audio", "bd06003.wav") == 1, "all three gate")
done(); step(399)
check(Save().missionState == 13 and count("build", "bvrecy") == 1 and count("follow") == 2, "recycler and two escorts")
step(429); check(Save().missionState == 13, "objective2 strict boundary")
step(429.1); check(Save().missionState == 14, "objective2")
step(430); check(count("deploy") == 0, "recycler moving")
objects[Save().recycler].command = AiCommand.NONE; step(431)
check(Save().missionState == 15 and count("deploy") == 1 and Save().stateTimer == 491, "deploy idle recycler")
step(431.1); check(Save().missionState == 16 and count("build", "cvtnk") == 10, "attack3 immediate despite unused timer")

-- Global APC detection, exact <100 range, entry, valid camera after removal,
-- dummy/portal attacks, 60 seconds inside, exit and one-shot victory.
local apc = add(nil, "bvapc"); objects[apc].distance = 100
step(432); check(not Save().portalours, "APC exact distance excluded")
objects[apc].distance = 99; step(433)
check(Save().portalours and Save().missionState == 17 and count("build", "cvartl") == 3, "APC capture and artillery")
reload(); objects[apc].command = AiCommand.NONE; step(434)
check(not IsValid(apc) and Save().apcEntered and Save().stateTimer2 == 494, "APC enters portal")
check(events[#events][1] == "camera" and events[#events][5] == labels.portal, "removed APC camera fallback")
done(); step(435); check(count("build", "cvtnk") == 17 and Save().stateTimer == 438, "seven dummies and three second camera deadline")
step(438); check(Save().missionState == 17, "end camera strict boundary")
step(438.1); check(Save().missionState == 18, "end camera finishes")
step(443.2); check(Save().missionState == 19 and count("build", "cvfigh") == 7, "seven portal attackers")
step(494); check(Save().missionState == 19, "return exact boundary")
step(494.1); check(Save().missionState == 20 and count("build", "bvapc") == 1, "return APC after 60 seconds")
reload(); step(495); check(count("success") == 0, "APC still moving")
objects[Save().apchandle].command = AiCommand.NONE; step(496)
check(count("success", "bd06wina.des") == 1 and Save().lost, "victory at exit")
check(events[#events][3] == 506, "absolute success time")
step(600); check(count("success") == 1, "terminal latch")

-- Portal distributions, delayed spawn, two slots, closure, recurrence and
-- ground random waves. Lost elapsed time does not manufacture extra waves.
fresh(); state(16); Save().stateTimer4 = 10
step(10); check(count("portal_out") == 0, "portal strict start")
step(10.1); check(count("portal_out") == 1 and count("portal_build") == 0, "portal opens before spawning")
reload(); step(11); check(count("portal_build") == 2, "two portal units after one second")
check(count("portal_build", "cvfigh") == 1 and count("portal_build", "cvtnk") == 1, "portal random branches")
step(12); check(count("portal_close") == 1 and Save().stateTimer4 == 92, "close and +80 recurrence")
step(92); check(count("portal_out") == 1, "portal recurrence strict boundary")
step(93.1); check(count("portal_build", "cvrckt") == 1, "rocket random branch")
step(94.1); check(Save().stateTimer4 == 174.1, "second wave reset")
Save().stateTimer3 = 95; step(95); check(count("hunt") == 0, "ground wave strict start")
step(95.1); check(count("hunt") == 5 and Save().stateTimer3 == 205.1, "five random hunters every110 seconds")

-- Early camera arrival cannot discard APC entry, narration or return timer.
fresh(); state(16); Save().recycler = add(nil, "bvrecy")
apc = add(nil, "bvapc"); objects[apc].distance = 99; camera.arrived = true
step(1); camera.arrived = false
check(Save().missionState == 18 and not Save().apcEntered, "early camera exit")
step(7); check(Save().missionState == 19, "portal attack still occurs")
step(1000); check(count("build", "bvapc") == 0, "old timer cannot create return APC")
objects[apc].command = AiCommand.NONE; step(1001); done(); step(1002)
check(Save().stateTimer2 == 1061 and count("build", "cvtnk") == 7, "entry sequence survived camera")
step(1061.1); check(Save().missionState == 20, "return gate after actual entry")

-- Independent losses, one-shot loss audio, missing narration and invalid handles.
fresh(); state(2, 100); objects[Save().silo_attack[0]].valid = false
step(1); check(Save().missionState == 24 and count("audio", "bd06007.wav") == 1, "destroyed decoy early attack loss")
done(); step(2); check(count("fail", "bd06lsea.des") == 1, "early attack descriptor")
fresh(); state(6); Save().stateTimer2 = 10; step(10); check(count("fail") == 0, "deadline equality")
step(10.1); check(count("fail", "bd06lsed.des") == 1, "11 minute deadline loss")
fresh(); state(16); Save().recycler = add(nil, "bvrecy"); objects[Save().recycler].alive = false
step(1); step(2); check(count("audio", "bd06006.wav") == 1, "recycler audio not restarted")
reload(); done(); step(3); check(count("fail", "bd06lsec.des") == 1, "recycler failure after sound")
fresh(); state(16); Save().recycler = add(nil, "bvrecy"); objects[Save().recycler].alive = false
apc = add(nil, "bvapc"); step(1); check(count("fail") == 0 and Save().missionState == 16, "existing APC permits recovery after recycler loss")
fresh(); state(20); Save().apchandle = add(nil, "bvapc"); objects[labels.portal].alive = false
step(1); check(count("fail", "bd06lseb.des") == 1 and count("success") == 0, "portal failure preempts victory")
fresh(); state(20); Save().apchandle = nil; step(1); check(count("success") == 0, "invalid exit APC no false win")
fresh(); state(12); audioMissing["bd06003.wav"] = true; Save().soundhandle = AudioMessage("bd06003.wav")
step(1); check(Save().missionState == 13, "missing sound3 unblocks same gate")
fresh(); state(16); Save().recycler = add(nil, "bvrecy")
apc = add(nil, "bvapc"); objects[apc].distance = 99
audioMissing["bd06009.wav"] = true
step(1); objects[apc].command = AiCommand.NONE; step(2)
check(Save().apcEntered and count("build", "cvtnk") == 7 and Save().stateTimer == 5, "missing entry narration still spawns dummies once")
reload(); step(3); check(count("build", "cvtnk") == 7, "entry audio latch survives load")
fresh(); state(7, 0); for i = 0, 9 do objects[Save().bdtank[i]].alive = false end
step(1); check(count("build", "bvrdeva") == 10, "ten dead means ten replacements, not invented cap")
print("BlackDog06: full mission, strict boundaries, waves, losses, camera repair and save/load passed")
