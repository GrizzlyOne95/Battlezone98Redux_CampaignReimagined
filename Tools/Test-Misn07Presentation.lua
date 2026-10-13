-- Execute the mission's presentation adapter in isolated Lua 5.1 peers.
-- This covers primitive protocol decisions, not native handle serialization.
local file = assert(io.open("Scripts/misn07.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local adapter = assert(source:match("(local unpackArgs =.-)\n%-%- Presentation adapter ends"))
local now, peers, packets = 0, {}, {}
local rallyCalls = {}
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
    for _, op in ipairs({"ClearObjectives", "AddObjective", "SetObjectiveOn",
        "SetObjectiveOff", "SetObjectiveName", "SetUserTarget", "RemoveObject", "SucceedMission",
        "FailMission", "CameraReady", "CameraObject", "CameraPath", "CameraFinish"}) do
        local name = op
        env[name] = function(...)
            record(name, ...)
            if name == "CameraObject" and p.cancelOnObject then p.cancelled = true end
        end
    end
    env.CameraCancelled = function() return p.cancelled end
    env.GetMaxScrap = function(team) assert(team == id); return p.resources.maxScrap end
    env.GetMaxPilot = function(team) assert(team == id); return p.resources.maxPilots end
    env.SetMaxScrap = function(team, n) assert(team == id); p.resources.maxScrap = n end
    env.SetMaxPilot = function(team, n) assert(team == id); p.resources.maxPilots = n end
    env.SetScrap = function(team, n) assert(team == id); p.resources.scrap = math.min(n, p.resources.maxScrap) end
    env.SetPilot = function(team, n) assert(team == id); p.resources.pilots = math.min(n, p.resources.maxPilots) end
    -- p.clock offsets this peer's GetTime() from the shared test clock (clock skew).
    -- p.labels maps handle -> map label (GetLabel); p.byLabel maps label -> handle (GetHandle).
    env.GetTime = function() return now + (p.clock or 0) end
    p.labels, p.byLabel = {}, {}
    env.GetPlayerHandle = function() return "craft" .. id end
    p.valid["craft" .. id] = true
    env.GetLabel = function(h) return p.labels[h] end
    p.venus = {}
    env.VENUS_OPS = { VenusState = true, VenusStrike = true, VenusErupt = true }
    env.CRVenusWeather = { ApplyNetEvent = function(op, ...) p.venus[#p.venus + 1] = { op, ... }; return true end }
    env.GetHandle = function(label) return p.byLabel[label] end
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
        GetRespawn=function() return { SetRallyPoints=function(points) rallyCalls[#rallyCalls+1] = { id=id, points=points } end } end,
    }
    env.subtit = {Play=function(...) record("Play", ...); return "audio" end,
        Queue=function(...) record("Queue", ...) end, Stop=function() record("Stop") end}
    env.M = {}
    local chunk = assert(loadstring("local CRCoop, M, subtit, LEADER_TEAM, VENUS_OPS, CRVenusWeather = CRCoop, M, subtit, 1, VENUS_OPS, CRVenusWeather\n" .. adapter .. [[
        return { ready=CameraReady, object=CameraObject, path=CameraPath, finish=CameraFinish,
            cancelled=CameraCancelled, present=Present, ending=EndMission, receive=ReceivePresentation,
            update=UpdatePresentationTransport,
            play=subtit.Play, queue=subtit.Queue,
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

-- Audio is presented to every peer; the leader gets the native handle. Queue follows.
check(host.api.play("misn0700.wav") == "audio", "the leader receives the native audio handle")
host.api.queue("misn0701.wav")
for _=1,4 do tick() end
for _, p in pairs(peers) do
    check(count(p, "Play", "misn0700.wav") == 1 and count(p, "Queue", "misn0701.wav") == 1,
        "every peer hears the first line once and the queued line once")
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

-- Respawn rally: the Utah once deployed. Every peer sets its own service; the stream
-- withholds the event until the Utah replica exists.
local UTAH = 9003
guest.valid[UTAH], third.valid[UTAH], fourth.valid[UTAH], host.valid[UTAH] = false, true, true, true
host.api.present("Rally", UTAH)
tick(); tick()
check(#rallyCalls == 3, "rally reaches the peers whose replica exists (host, third, fourth)")
for _, call in ipairs(rallyCalls) do
    check(call.points[0] == "cam3" and call.points[1] == UTAH, "rally keeps cam3 for phase 0 and the Utah for phase 1")
end
guest.valid[UTAH] = true
for _=1,4 do tick() end
check(#rallyCalls == 4, "the delayed replica applies the rally exactly once")

-- Camera snapshots are label-aware: a non-replicated target (misn03's cam_geyser, here "camgeyser")
-- is resolved by label; a guest that cannot resolve it inside its window plays the film aimed at
-- its own craft instead of skipping it, and re-aims the moment the label resolves.
host.valid.camgeyser, host.labels.camgeyser, host.byLabel.cam_geyser = true, "cam_geyser", "camgeyser"
guest.byLabel.cam_geyser, fourth.byLabel.cam_geyser = nil, nil
third.byLabel.cam_geyser, third.valid["cg@3"] = "cg@3", true
host.api.finish(); tick(); tick()
host.api.ready(); host.api.path("cam1path", 800, 1000, "camgeyser")
tick(); tick(); tick()
check(third.api.state() and last(third, "CameraPath")[5] == "cg@3", "a resolvable label target aims the film at the guest's replica")
check(not guest.api.state() and not fourth.api.state(), "an unresolved target waits inside the guest's window")
guest.byLabel.cam_geyser = "cg@2"; guest.valid["cg@2"] = true
tick()
check(guest.api.state() and last(guest, "CameraPath")[5] == "cg@2", "a late-resolving label target starts the film aimed at it")
for _=1,8 do tick() end
check(fourth.api.state() and last(fourth, "CameraPath")[5] == "craft4",
    "an unresolvable target must play aimed at the guest's craft, not skip the film")
fourth.byLabel.cam_geyser, fourth.valid["cg@4"] = "cg@4", true
tick(); check(last(fourth, "CameraPath")[5] == "cg@4", "the film re-aims when the label finally resolves")
host.api.finish(); tick(); tick()

-- Object camera: the subject and target are both the label-only object.
guest.byLabel.cam_geyser, fourth.byLabel.cam_geyser = nil, nil
fourth.valid["cg@4"] = nil
host.api.finish(); tick(); tick()
host.api.ready(); host.api.object("camgeyser", 0, 500, -500, "camgeyser")
tick(); tick(); tick()
check(third.api.state() and last(third, "CameraObject")[6] == "cg@3", "a resolvable label target aims the film at the guest's replica")
check(not guest.api.state() and not fourth.api.state(), "an unresolved target waits inside the guest's window")
guest.byLabel.cam_geyser = "cg@2"; guest.valid["cg@2"] = true
tick()
check(guest.api.state() and last(guest, "CameraObject")[6] == "cg@2", "a late-resolving label target starts the film aimed at it")
for _=1,8 do tick() end
check(fourth.api.state() and last(fourth, "CameraObject")[6] == "craft4",
    "an unresolvable target must play aimed at the guest's craft, not skip the film")
fourth.byLabel.cam_geyser, fourth.valid["cg@4"] = "cg@4", true
tick(); check(last(fourth, "CameraObject")[6] == "cg@4", "the film re-aims when the label finally resolves")
host.api.finish(); tick(); tick()

-- Drop the first event and reorder the retransmission; markers wait for replicas.
-- Real handles are numbers; strings on the wire are map labels.
local MARKER = 9001
guest.valid[MARKER] = false
third.valid[MARKER], fourth.valid[MARKER] = true, true
host.valid[MARKER] = true
host.api.present("SetObjectiveName", MARKER, "Starport")
host.api.present("AddObjective", "misn0701.otf", "white")
host.api.ending("SucceedMission", now, "misn07w1.des")
host.api.update(); packets = {} -- loss
tick(true)
check(count(guest, "SetObjectiveName") == 0 and count(guest, "SucceedMission") == 0,
    "missing replica and out-of-order events must hold the result")
guest.valid[MARKER] = true
for _=1,8 do tick(true) end
check(count(guest, "SetObjectiveName") == 1 and count(guest, "AddObjective") == 1,
    "retries apply ordered events exactly once")
for _, p in pairs(peers) do
    check(count(p, "SucceedMission") == 1, "all four peers must receive exactly one result")
end
-- A map object the engine cannot carry as a handle (an authored, non-replicated object
-- such as cam3 or the radar array) is nil on every guest. It goes by LABEL. Guest clocks
-- are far from the leader's (the old absolute `expires` made a guest drop the marker on
-- first receipt) and the label may resolve late: the marker must still land, in order,
-- exactly once.
local LABEL = "cam3"
host.labels.geyser, host.byLabel[LABEL], host.valid.geyser = LABEL, "geyser", true
guest.clock, third.clock, fourth.clock = 100, -50, 0
third.byLabel[LABEL], fourth.byLabel[LABEL] = "geyser@3", "geyser@4"
third.valid["geyser@3"], fourth.valid["geyser@4"] = true, true
host.api.present("SetObjectiveName", "geyser", "Rendezvous Point")
host.api.present("SetObjectiveOn", "geyser")
host.api.present("AddObjective", "misn0702.otf", "white")
for _=1,4 do tick() end
check(count(host, "SetObjectiveName", "geyser") == 1 and count(host, "SetObjectiveOn", "geyser") == 1,
    "the leader applies its own marker with the real handle")
check(count(third, "SetObjectiveName", "geyser@3") == 1 and count(fourth, "SetObjectiveOn", "geyser@4") == 1,
    "a label resolves per guest whatever the guest clock reads")
check(last(third, "SetObjectiveName")[3] == "Rendezvous Point", "the objective name survives the label swap")
check(count(guest, "SetObjectiveName", "geyser@2") == 0 and count(guest, "AddObjective", "misn0702.otf") == 0,
    "a label not yet resolvable on a guest holds the stream in order, even with its clock far ahead")
guest.byLabel[LABEL] = "geyser@2"; guest.valid["geyser@2"] = true
for _=1,3 do tick() end
check(count(guest, "SetObjectiveName", "geyser@2") == 1 and count(guest, "SetObjectiveOn", "geyser@2") == 1 and
    count(guest, "AddObjective", "misn0702.otf") == 1, "a late-resolving marker lands once, before the next event")
check(count(third, "SetObjectiveOn", "geyser@3") == 1, "retransmission never double-applies")

-- A label that never resolves (target genuinely gone) drops after the guest's OWN 5 s
-- and never blocks the stream; an Off/RemoveObject for it is skipped without waiting.
host.labels.gone, host.byLabel.gone, host.valid.gone = "gone", "gone", true
for _, p in ipairs({guest, third, fourth}) do p.clock = p.clock + 7 end -- clocks jump: wait is relative
host.api.present("SetObjectiveOn", "gone")
host.api.present("AddObjective", "misn0703.otf", "white")
host.api.present("SetObjectiveOff", "gone")
host.api.present("RemoveObject", "gone")
host.api.present("AddObjective", "misn0704.otf", "white")
for _=1,12 do tick() end
check(count(guest, "AddObjective", "misn0703.otf") == 0, "the guest waits before dropping a marker (3 s of 5)")
for _=1,12 do tick() end
for _, p in ipairs({guest, third, fourth}) do
    check(count(p, "SetObjectiveOn", "gone") == 0 and count(p, "SetObjectiveOff", "gone") == 0 and
        count(p, "RemoveObject", "gone") == 0, "a marker or removal for a vanished target is dropped, not applied with nil")
    check(count(p, "AddObjective", "misn0703.otf") == 1 and count(p, "AddObjective", "misn0704.otf") == 1,
        "the stream resumes after the stale marker")
end

-- An object with no map label still travels as a plain handle (spawned objects: the
-- convoy tanks, navs, Razor One, the prototypes, mines).
local DYN = 9002
host.valid[DYN] = true
for _, p in ipairs({guest, third, fourth}) do p.valid[DYN] = true end
host.api.present("SetUserTarget", DYN); for _=1,4 do tick() end
check(count(guest, "SetUserTarget", DYN) == 1, "unlabelled objects keep the plain handle path")
host.api.present("RemoveObject", DYN); for _=1,4 do tick() end
check(count(guest, "RemoveObject", DYN) == 1, "a spawned object's removal reaches every peer by handle")
-- Venus weather events (seed/state, strikes, eruptions) carry only numbers: they ride the same
-- ordered stream, reach every guest exactly once and never wait on a handle replica.
guest.valid[9100] = false
host.api.present("VenusState", 77, 0.0, 2, 0, 2, 0, 0)
host.api.present("SetObjectiveOn", 9100)
host.api.present("VenusStrike", 1, 10.5, 20, 30.5, 1, 1.5, 0.8)
host.api.present("VenusErupt", 2, 3, 20, 0.9)
host.api.present("AddObjective", "misn0705.otf", "white")
for _=1,4 do tick() end
check(#guest.venus == 1 and guest.venus[1][1] == "VenusState" and guest.venus[1][2] == 77,
    "a state event arrives even while a later marker is waiting for its replica")
check(count(guest, "AddObjective", "misn0705.otf") == 0, "the stream stays ordered behind the waiting marker")
for _, p in ipairs({guest, third, fourth}) do p.valid[9100] = true end
host.valid[9100] = true
for _=1,4 do tick() end
for _, p in ipairs({guest, third, fourth}) do
    check(#p.venus == 3 and p.venus[2][1] == "VenusStrike" and p.venus[2][7] == 1.5 and p.venus[3][1] == "VenusErupt",
        "every guest receives the state, strike and eruption exactly once, in order")
end
check(count(guest, "AddObjective", "misn0705.otf") == 1, "the stream resumes after the marker resolves")

-- A label only the leader knows (SetLabel on a spawned, replicated object): guests that cannot
-- resolve the label use the replicated handle sent beside it ("@handle@label").
local SPAWNED = 9004
host.labels[SPAWNED], host.byLabel.leader_only, host.valid[SPAWNED] = "leader_only", SPAWNED, true
for _, p in ipairs({guest, third, fourth}) do p.valid[SPAWNED] = true end
host.api.present("SetObjectiveOn", SPAWNED); for _=1,4 do tick() end
check(count(guest, "SetObjectiveOn", SPAWNED) == 1 and count(fourth, "SetObjectiveOn", SPAWNED) == 1,
    "a leader-only label falls back to the replicated handle")
print("misn07 path/object-camera, dialogue, rally, replica wait, local skip and ordered result checks passed: " .. checks)
