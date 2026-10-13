-- Execute the mission's presentation adapter in isolated Lua 5.1 peers.
-- This covers primitive protocol decisions, not native handle serialization.
local file = assert(io.open("Scripts/misn06.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local adapter = assert(source:match("(local unpackArgs =.-)\n%-%- BuildObject invokes"))
local now, peers, packets = 0, {}, {}
local registry = {[1]={team=1}, [2]={team=2}, [3]={team=3}, [4]={team=4}}
local checks = 0
local function check(value, why) assert(value, why); checks = checks + 1 end
local function peer(id)
    local p = {calls={}, valid={subject=true, target=true}, cancelled=false, info={},
        resources={scrap=0, pilots=0, maxScrap=id == 1 and 35 or 0, maxPilots=id == 1 and 15 or 0}}
    local env = setmetatable({}, {__index=_G})
    local function record(op, ...)
        p.calls[#p.calls+1] = {op, ...}
    end
    for _, op in ipairs({"ClearObjectives", "AddObjective", "UpdateObjective", "SetObjectiveOn",
        "SetObjectiveOff", "SetObjectiveName", "SetUserTarget", "RemoveObject", "SucceedMission",
        "FailMission", "CameraReady", "CameraObject", "CameraPath", "CameraFinish",
        "StartCockpitTimer", "StopCockpitTimer", "HideCockpitTimer"}) do
        local name = op
        env[name] = function(...)
            record(name, ...)
            if name == "CameraObject" and p.cancelOnObject then p.cancelled = true end
        end
    end
    env.CameraCancelled = function() return p.cancelled end
    env.IsInfo = function(prefix) return p.info[prefix] == true end
    env.GetMaxScrap = function(team) assert(team == id); return p.resources.maxScrap end
    env.GetMaxPilot = function(team) assert(team == id); return p.resources.maxPilots end
    env.SetMaxScrap = function(team, n) assert(team == id); p.resources.maxScrap = n end
    env.SetMaxPilot = function(team, n) assert(team == id); p.resources.maxPilots = n end
    env.SetScrap = function(team, n) assert(team == id); p.resources.scrap = math.min(n, p.resources.maxScrap) end
    env.SetPilot = function(team, n) assert(team == id); p.resources.pilots = math.min(n, p.resources.maxPilots) end
    env.GetTime = function() return now end
    env.IsValid = function(h) return p.valid[h] == true end
    env.Send = function(to, kind, ...)
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
    local chunk = assert(loadstring("local CRCoop, M, subtit, LEADER_TEAM = CRCoop, M, subtit, 1\n" .. adapter .. [[
        return { ready=CameraReady, object=CameraObject, path=CameraPath, finish=CameraFinish,
            cancelled=CameraCancelled, present=Present, ending=EndMission, receive=ReceivePresentation,
            update=UpdatePresentationTransport, isInfo=IsInfo, relay=UpdateInfoRelay,
            play=subtit.Play, timer=StartCockpitTimer, hide=HideCockpitTimer,
            state=function() return localCameraActive, cameraSkipped, receivedEvent end }
    ]]))
    setfenv(chunk, env)
    p.api = chunk(); peers[id] = p
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

-- Starting resources: every owner reserves native capacity (guests start with none).
for team=1,4 do host.api.present("Resources", team, 5, 10) end
for _=1,4 do tick() end
for _, p in pairs(peers) do
    check(p.resources.scrap == 5 and p.resources.pilots == 10,
        "every owner receives starting resources despite native capacity clamps")
end
check(host.resources.maxPilots == 15, "starting resources must preserve larger authored capacity")
check(host.resources.scrap == 5 and guest.resources.scrap == 5,
    "a team resource presentation must not write another owner")

-- Audio and cockpit timers are presented to every peer; the leader gets the handle.
check(host.api.play("misn0601.wav") == "audio", "the leader receives the native audio handle")
host.api.timer(540.0, 362.0, 180.0)
host.api.hide()
for _=1,4 do tick() end
for _, p in pairs(peers) do
    check(count(p, "Play", "misn0601.wav") == 1, "every peer hears the narration exactly once")
    local timer = last(p, "StartCockpitTimer")
    check(count(p, "StartCockpitTimer") == 1 and timer[2] == 540 and timer[3] == 362 and timer[4] == 180,
        "every peer starts the cockpit timer once with the stock thresholds")
    check(count(p, "HideCockpitTimer") == 1, "every peer hides the cockpit timer")
end

-- Object camera (wAu1 / sim5 shots): waits for replicas; skips are local.
host.api.ready(); host.api.object("subject", 0, 5000, -5000, "target")
guest.valid.target = false
tick(); tick()
check(not guest.api.state(), "a camera must wait for its native target replica")
check(third.api.state() and fourth.api.state(), "other peers should receive the object film")
guest.valid.target = true; tick()
check(guest.api.state(), "a delayed target should start the film")
guest.cancelOnObject = true; tick()
local active, skipped = guest.api.state()
check(not active and skipped and third.api.state(), "guest skip must be local")
host.cancelOnObject = true; host.api.object("subject", 0, 5000, -5000, "target"); tick()
check(not host.api.state() and third.api.state(), "host skip must keep publishing the film")
check(host.api.cancelled() == false, "net games never surface a skip to the shared mission timing")
host.api.finish(); tick(); tick()
check(not third.api.state() and not fourth.api.state(), "finish snapshot releases every watcher")
third.api.receive(1, "C", 1, 1, "O", "subject", 0, 1, 2, "target"); third.api.update()
check(not third.api.state(), "stale snapshots cannot restart a finished film")

-- Path camera (opening flyover / Hephaestus cam1path): snapshot reaches guests.
host.cancelled, guest.cancelled, host.cancelOnObject, guest.cancelOnObject = false, false, false, false
host.api.ready(); host.api.path("openingcampath", 1000, 500, "target"); tick(); tick()
for _, p in ipairs({guest, third, fourth}) do
    local call = last(p, "CameraPath")
    check(p.api.state() and call and call[2] == "openingcampath" and call[3] == 1000 and call[4] == 500 and call[5] == "target",
        "path camera runs natively on every guest with the leader arguments")
end
check(count(host, "CameraPath") >= 1 and host.api.state(), "the leader runs its own path camera")
host.api.path("openingcampath", 1015, 500, "target"); tick(); tick()
check(last(third, "CameraPath")[3] == 1015, "the latest height replaces earlier snapshots")
guest.cancelled = true; tick()
active, skipped = guest.api.state()
check(not active and skipped and third.api.state() and host.api.state(), "guest path skip must be local")
local guestFrames = count(guest, "CameraPath")
tick(); check(count(guest, "CameraPath") == guestFrames, "a skipped guest stays out until the next film")
guest.cancelled = false
host.cancelled = true; host.api.path("openingcampath", 1030, 500, "target"); tick()
check(not host.api.state() and third.api.state(), "host path skip must keep publishing the film")
host.cancelled = false
host.api.finish(); tick(); tick()
check(not third.api.state() and not fourth.api.state() and not guest.api.state(), "finish snapshot releases path watchers")
host.api.ready(); host.api.path("cam1path", 800, 1000, "target"); tick(); tick()
check(guest.api.state() and last(guest, "CameraPath")[2] == "cam1path", "a new generation clears local skip")
guest.api.receive(3, "C", 999, 99, "", 0, 0, 0); guest.api.update()
check(guest.api.state(), "non-leader camera messages must be ignored")
host.api.finish(); tick(); tick()
guest.valid.target = false
host.api.ready(); host.api.path("cam1path", 800, 1000, "target"); tick(); tick()
check(not guest.api.state() and third.api.state(), "a path camera waits for its native target replica")
guest.valid.target = true
host.api.finish(); tick(); tick()

-- IsInfo is guest UI state: guests relay it, the leader honours it for one second.
check(host.api.isInfo("obheph") == false, "no report means no info")
guest.info.obheph = true
guest.api.relay(); guest.api.relay()
check(#packets == 1 and packets[1].kind == "I" and packets[1].to == 1 and packets[1].args[1] == "obheph",
    "guest relay is throttled and addressed to the leader")
deliver()
check(host.api.isInfo("obheph") == true and host.api.isInfo("sblpad") == false, "leader accepts the report")
guest.info.obheph = false
now = now + 0.9
check(host.api.isInfo("obheph") == true, "report persists within one second")
now = now + 0.2
check(host.api.isInfo("obheph") == false, "report expires after one second")
host.info.sblpad = true
check(host.api.isInfo("sblpad") == true, "the leader own native IsInfo still counts")
host.info.sblpad = false
host.api.receive(2, "I", "bogus"); host.api.receive(9, "I", "obstp1"); host.api.receive(2, "I", 5)
check(not host.api.isInfo("bogus") and not host.api.isInfo("obstp1"), "unknown prefixes and non-players are rejected")
guest.api.receive(3, "I", "obstp3")
check(not guest.api.isInfo("obstp3"), "only the leader records reports")
guest.info.obstp3 = true; now = now + 0.3; guest.api.relay(); deliver()
check(host.api.isInfo("obstp3"), "each of the five prefixes is relayed")

-- Drop the first event and reorder the retransmission; markers wait for replicas.
guest.valid.marker = false
third.valid.marker, fourth.valid.marker = true, true
host.valid.marker = true
host.api.present("SetObjectiveName", "marker", "Starport")
host.api.present("AddObjective", "misn0606.otf", "white")
host.api.ending("SucceedMission", now, "misn06w1.des")
host.api.update(); packets = {} -- loss
tick(true)
check(count(guest, "SetObjectiveName") == 0 and count(guest, "SucceedMission") == 0,
    "missing replica and out-of-order events must hold the result")
guest.valid.marker = true
for _=1,8 do tick(true) end
check(count(guest, "SetObjectiveName") == 1 and count(guest, "AddObjective") == 1,
    "retries apply ordered events exactly once")
for _, p in pairs(peers) do
    check(count(p, "SucceedMission") == 1, "all four peers must receive exactly one result")
end
print("misn06 path/object-camera, timer, IsInfo relay, replica wait, local skip and ordered result checks passed: " .. checks)
