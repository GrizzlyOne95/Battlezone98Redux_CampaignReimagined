-- Execute the misn12 presentation adapter in isolated Lua 5.1 peers.
-- This covers primitive protocol decisions, not native handle serialization.
-- misn12 adds to the misn06 adapter: objective-panel ops addressed to ONE human (the E stream carries
-- a target team; every peer acknowledges, only the target applies), an owner-side ammo top-up, the Europa
-- weather ops, per-player IsInfo reports, and a result that is held until 4.5 s before its time.
local file = assert(io.open("Scripts/misn12cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local adapter = assert(source:match("(local unpackArgs =.-)\n%-%- Presentation adapter ends"))
local now, peers, packets = 0, {}, {}
local registry = {[1]={team=1}, [2]={team=2}, [3]={team=3}, [4]={team=4}}
local checks = 0
local function check(value, why) assert(value, why); checks = checks + 1 end
local function peer(id)
    local p = {calls={}, valid={subject=true, target=true}, cancelled=false, info={}, europa={}}
    local env = setmetatable({}, {__index=_G})
    env._G = env -- mission chunks resolve _G.SucceedMission/FailMission at call time
    local function record(op, ...)
        p.calls[#p.calls+1] = {op, ...}
    end
    for _, op in ipairs({"ClearObjectives", "AddObjective", "UpdateObjective", "SetObjectiveOn",
        "SetObjectiveOff", "SetObjectiveName", "SetUserTarget", "RemoveObject", "SucceedMission",
        "FailMission", "CameraReady", "CameraObject", "CameraPath", "CameraFinish",
        "StartCockpitTimer", "StopCockpitTimer", "HideCockpitTimer", "AddAmmo", "StopAudioMessage"}) do
        local name = op
        env[name] = function(...)
            record(name, ...)
            if name == "CameraObject" and p.cancelOnObject then p.cancelled = true end
        end
    end
    env.CameraCancelled = function() return p.cancelled end
    env.IsInfo = function(prefix) return p.info[prefix] == true end
    -- p.clock offsets this peer's GetTime() from the shared test clock (clock skew).
    env.GetTime = function() return now + (p.clock or 0) end
    p.labels, p.byLabel = {}, {}
    env.GetPlayerHandle = function() return "craft" .. id end
    p.valid["craft" .. id] = true
    env.GetLabel = function(h) return p.labels[h] end
    env.GetHandle = function(label) return p.byLabel[label] end
    env.IsValid = function(h) return p.valid[h] == true end
    env.CRWire = assert(loadfile("Scripts/CRWire.lua"))()
    env.Send = function(to, kind, ...)
        for i = 1, select("#", ...) do local v = select(i, ...); assert(type(v) ~= "string" or #v <= 127, "Send string over 127 bytes on " .. tostring(kind)) end
        packets[#packets+1] = {from=id, to=to, kind=kind, args={...}}
    end
    env.CRCoop = {
        IsNetworkGame=function() return true end,
        IsAuthority=function() return id == 1 end,
        GetPlayers=function() return registry end,
        IsHumanTeam=function(t) return t >= 1 and t <= 4 end,
        GetLocalPlayerId=function() return id end,
        GetLocalTeam=function() return id end,
    }
    env.subtit = {Play=function(...) record("Play", ...); return "audio" end,
        Queue=function(...) record("Queue", ...) end, Stop=function() record("Stop") end}
    env.M = {}
    p.M = env.M
    p.printed = {}
    env.print = function(...) p.printed[#p.printed + 1] = table.concat({ ... }, " ") end
    env.SetLabel = function(h, l) record("SetLabel", h, l); p.labels[h] = l; p.byLabel[l] = h end
    env.EUROPA_OPS = { EuropaState = true, EuropaPlume = true, EuropaQuake = true, EuropaSurge = true }
    env.CREuropaWeather = { ApplyNetEvent = function(op, ...) p.europa[#p.europa + 1] = { op, ... }; return true end }
    local chunk = assert(loadstring("local CRCoop, M, subtit, LEADER_TEAM, EUROPA_OPS, CREuropaWeather = CRCoop, M, subtit, 1, EUROPA_OPS, CREuropaWeather\n" .. adapter .. [[
        return { ready=CameraReady, object=CameraObject, path=CameraPath, finish=CameraFinish,
            cancelled=CameraCancelled, present=Present, reset=ResetPresentation, ending=EndMission, receive=ReceivePresentation,
            update=UpdatePresentationTransport, isInfo=IsInfo, relay=UpdateInfoRelay,
            play=subtit.Play, timer=StartCockpitTimer, hide=HideCockpitTimer,
            clear=ClearObjectives, add=AddObjective, on=SetObjectiveOn, off=SetObjectiveOff, user=SetUserTarget,
            focus=function(team, id, isLocal) focusTeam, focusId, focusLocal = team, id, isLocal end,
            broadcast=function(fn) local t = focusTeam; focusTeam = 0; fn(); focusTeam = t end,
            state=function() return localCameraActive, cameraSkipped, receivedEvent end }
    ]]))
    setfenv(chunk, env)
    p.api = chunk(); p.env = env; peers[id] = p
    return p
end
local function count(p, op, first)
    local n = 0
    for _, call in ipairs(p.calls) do
        if call[1] == op and (first == nil or call[2] == first) then n = n + 1 end
    end
    return n
end
local function last(p, op)
    for i = #p.calls, 1, -1 do if p.calls[i][1] == op then return p.calls[i] end end
end
local function deliver(reverse)
    local batch = packets; packets = {}
    for j=1,#batch do
        local packet = batch[reverse and (#batch+1-j) or j]
        for id, p in pairs(peers) do
            if (packet.to == 0 and id ~= packet.from) or packet.to == id then
                p.api.receive(packet.from, packet.kind, unpack(packet.args))
            end
        end
    end
end
local function tick(reverse)
    now = now + 0.25
    for _, p in pairs(peers) do p.api.update() end
    deliver(reverse); deliver()
end
local host, guest = peer(1), peer(2)
local third, fourth = peer(3), peer(4)

-- Shared radio and the cockpit timer reach every peer; the leader gets the handle.
check(host.api.play("misn1200.wav") == "audio", "the leader receives the native audio handle")
host.api.timer(1200, 300, 120)
for _=1,4 do tick() end
for _, p in pairs(peers) do
    check(count(p, "Play", "misn1200.wav") == 1, "every peer hears the narration exactly once")
    local timer = last(p, "StartCockpitTimer")
    check(count(p, "StartCockpitTimer") == 1 and timer[2] == 1200 and timer[3] == 300 and timer[4] == 120,
        "every peer starts the 20-minute cockpit timer once with the stock thresholds")
end
host.api.hide()
for _=1,4 do tick() end
for _, p in pairs(peers) do check(count(p, "HideCockpitTimer") == 1, "every peer hides the cockpit timer") end

-- An objective panel call made while a human is in focus is delivered to that human only.
host.api.focus(3, 30, false)
host.api.clear(); host.api.add("misn1201.otf", "white")
for _=1,4 do tick() end
check(count(third, "ClearObjectives") == 1 and count(third, "AddObjective", "misn1201.otf") == 1, "the focused human gets the panel")
for _, p in ipairs({host, guest, fourth}) do
    check(count(p, "ClearObjectives") == 0 and count(p, "AddObjective") == 0, "nobody else's panel changes")
end
-- Every peer acknowledged the targeted events: the stream keeps moving for the others.
for _, p in ipairs({guest, third, fourth}) do
    local _, _, received = p.api.state()
    check(received == 5, "every guest consumed the three shared and both targeted events in order")
end
-- The leader is itself a human: focus on its own team applies locally and goes nowhere else.
host.api.focus(1, 10, true)
host.api.clear(); host.api.add("misn1202.otf", "green")
for _=1,4 do tick() end
check(count(host, "AddObjective", "misn1202.otf") == 1, "the leader's own panel is applied at once")
for _, p in ipairs({guest, third, fourth}) do check(count(p, "AddObjective", "misn1202.otf") == 0, "and is not shown to guests") end
-- Broadcast stays broadcast even while a human is in focus (the uplink result).
host.api.focus(2, 20, false)
host.api.broadcast(function() host.api.clear(); host.api.add("misn1205.otf", "white") end)
for _=1,4 do tick() end
for _, p in pairs(peers) do check(count(p, "AddObjective", "misn1205.otf") == 1, "the result panel reaches every peer once") end
-- Markers for one human only.
host.api.focus(4, 40, false)
for _, p2 in pairs(peers) do p2.valid.subject = true; p2.labels.subject = "checktower1"; p2.byLabel.checktower1 = "subject" end
host.valid.subject = true
host.api.off("subject")
for _=1,4 do tick() end
check(count(fourth, "SetObjectiveOff", "subject") == 1 and count(third, "SetObjectiveOff") == 0
    and count(guest, "SetObjectiveOff") == 0 and count(host, "SetObjectiveOff") == 0, "a marker clears for its human only")
-- A guest never waits for an object it will not show.
guest.valid.subject = false
host.api.focus(3, 30, false)
host.api.on("subject")
for _=1,6 do tick() end
check(count(third, "SetObjectiveOn", "subject") == 1, "the target resolves and shows the marker")
local _, _, receivedGuest = guest.api.state()
check(receivedGuest >= 7, "a non-target guest acknowledges past a marker it cannot resolve (no wait)")
guest.valid.subject = true
host.api.focus(0, nil, true)

-- The owning peer tops up its own craft.
host.api.focus(3, 30, false)
host.api.present("TopUpAmmo", 2000.0)
for _=1,4 do tick() end
check(count(third, "AddAmmo", "craft3") == 1 and last(third, "AddAmmo")[3] == 2000, "the owner tops up its own craft")
for _, p2 in ipairs({host, guest, fourth}) do check(count(p2, "AddAmmo") == 0, "nobody else is touched") end
host.api.focus(0, nil, true)

-- Weather ops carry only numbers: they bypass labels and waits.
host.api.present("EuropaPlume", 5, 1.0)
host.api.present("EuropaQuake", 0.4, 3.0)
for _=1,4 do tick() end
for _, p2 in ipairs({guest, third, fourth}) do
    check(#p2.europa == 2 and p2.europa[1][1] == "EuropaPlume" and p2.europa[2][1] == "EuropaQuake", "guests receive the weather events in order")
end
check(#host.europa == 2, "the leader applies them locally too")

-- IsInfo is per player: a guest's report counts for that guest only.
guest.info.sbhqt1 = true
now = now + 1
for _, p2 in ipairs({guest, third}) do p2.api.relay() end
deliver()
host.api.focus(1, 10, true)
check(host.api.isInfo("sbhqt1") == false, "the leader's own panel does not show the console")
host.api.focus(1, 2, false)
check(host.api.isInfo("sbhqt1") == true, "the leader honours player 2's relayed selection")
host.api.focus(1, 3, false)
check(host.api.isInfo("sbhqt1") == false, "and does not credit it to another player")
now = now + 1.01
host.api.focus(1, 2, false)
check(host.api.isInfo("sbhqt1") == false, "a report is honoured for one second")
guest.info.sbhqt1 = false
guest.info.sbhqt2 = true
guest.api.relay(); now = now + 1; guest.api.relay(); deliver()
host.api.focus(1, 2, false)
check(host.api.isInfo("sbhqt2") == true and host.api.isInfo("sbhqt1") == false, "the two console prefixes are tracked apart")
guest.info.sbhqt2 = false

-- A forged info report from a non-human or a foreign prefix is ignored.
host.api.receive(99, "I", "sbhqt1")
host.api.focus(1, 99, false)
check(host.api.isInfo("sbhqt1") == false, "an unknown sender cannot fake a selection")
host.api.receive(2, "I", "svmuf")
host.api.focus(1, 2, false)
check(host.api.isInfo("svmuf") == false, "an unlisted prefix is never honoured")
host.api.focus(0, nil, true)

-- Camera frames: a snapshot per 0.2 s; subjects travel by label.
host.api.ready(); host.api.object("subject", 0, 700, -1500, "target")
for _, p2 in pairs(peers) do p2.byLabel.subject, p2.byLabel.target = "subject", "target" end
tick(); tick()
check(third.api.state() and guest.api.state() and fourth.api.state(), "every peer plays the shared shot")
guest.cancelOnObject = true; tick()
local active, skipped = guest.api.state()
check(not active and skipped and third.api.state(), "a guest's skip is local")
check(host.api.cancelled() == false, "net games never surface a skip to the shared mission timing")
host.api.finish(); tick(); tick()
check(not third.api.state(), "finishing releases the shot on every peer")

-- The result is held until 4.5 s before its time, so the DLL's last scheduled beats still run.
host.api.ending("FailMission", now + 10, "misn12f1.des")
for _=1,4 do tick() end
check(count(host, "FailMission") == 0 and count(guest, "FailMission") == 0, "the result waits while the countdown's beats are pending")
for _=1,24 do tick() end
for _, p2 in pairs(peers) do
    check(count(p2, "FailMission") == 1, "the result reaches every peer once")
end
local failure = last(guest, "FailMission")
check(failure[3] == "misn12f1.des" and failure[2] >= now - 7, "with its description and a time at least half a second out")
host.api.ending("FailMission", now + 10, "other.des")
for _=1,8 do tick() end
check(count(host, "FailMission") == 1, "a second result is ignored")

-- No packet exceeds the stock Lua payload budget.
for _, packet in ipairs(packets) do
    local bytes = 4
    for _, value in ipairs(packet.args) do bytes = bytes + (type(value) == "string" and #value + 2 or 9) end
    check(bytes < 244, "packet within budget")
end
print("misn12 presentation: " .. checks .. " Lua 5.1 adapter checks passed")
