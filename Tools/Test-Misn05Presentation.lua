-- Execute the mission's presentation adapter in isolated Lua 5.1 peers.
-- This covers primitive protocol decisions, not native handle serialization.
local file = assert(io.open("Scripts/misn05.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local adapter = assert(source:match("(local unpackArgs =.-)\n%-%- BuildObject invokes"))
local now, peers, packets = 0, {}, {}
local registry = {[1]={team=1}, [2]={team=2}, [3]={team=3}, [4]={team=4}}
local checks = 0
local function check(value, why) assert(value, why); checks = checks + 1 end
local function peer(id)
    local p = {calls={}, valid={subject=true, target=true}, cancelled=false,
        resources={scrap=0, pilots=0, maxScrap=id == 1 and 35 or 0, maxPilots=id == 1 and 15 or 0}}
    local env = setmetatable({}, {__index=_G})
    local function record(op, ...)
        p.calls[#p.calls+1] = {op, ...}
    end
    for _, op in ipairs({"ClearObjectives", "AddObjective", "UpdateObjective", "SetObjectiveOn",
        "SetObjectiveOff", "SetObjectiveName", "SetUserTarget", "RemoveObject", "SucceedMission",
        "FailMission", "CameraReady", "CameraObject", "CameraFinish"}) do
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
    }
    env.subtit = {Play=function(...) record("Play", ...) end,
        Queue=function(...) record("Queue", ...) end, Stop=function() record("Stop") end}
    env.M = {}
    env.FromLeader = nil
    local chunk = assert(loadstring("local CRCoop, M, subtit, LEADER_TEAM = CRCoop, M, subtit, 1\n" .. adapter .. [[
        return { ready=CameraReady, object=CameraObject, finish=CameraFinish,
            present=Present, ending=EndMission, receive=ReceivePresentation,
            update=UpdatePresentationTransport,
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
-- Native capacities clamp resource writes. Every owner must reserve room,
-- including the three guests whose starting recyclers are suppressed.
for team=1,4 do host.api.present("Resources", team, 40, 10) end
for _=1,4 do tick() end
for _, p in pairs(peers) do
    check(p.resources.scrap == 40 and p.resources.pilots == 10,
        "every owner receives starting resources despite native capacity clamps")
end
check(host.resources.maxPilots == 15, "starting resources must preserve larger authored capacity")
host.api.present("Resources", 4, 20, 5)
for _=1,4 do tick() end
check(fourth.resources.maxScrap == 40 and fourth.resources.maxPilots == 10,
    "resource changes must not reduce the owner's existing capacity")
check(host.resources.scrap == 40 and guest.resources.scrap == 40 and third.resources.scrap == 40,
    "a team's resource presentation must not write another owner's resources")
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
host.api.finish(); tick(); tick()
check(not third.api.state() and not fourth.api.state(), "finish snapshot releases every watcher")
third.api.receive(1, "C", 1, 1, "subject", 0, 1, 2, "target"); third.api.update()
check(not third.api.state(), "stale snapshots cannot restart a finished film")
host.cancelled, guest.cancelled, host.cancelOnObject, guest.cancelOnObject = false, false, false, false
host.api.ready(); host.api.object("subject", -25, 18, -85, "target"); tick(); tick()
check(guest.api.state(), "a new generation clears local skip")
guest.api.receive(3, "C", 999, 99, "", 0, 0, 0); guest.api.update()
check(guest.api.state(), "non-leader camera messages must be ignored")

-- Camera snapshots are label-aware: a non-replicated target (misn03's cam_geyser, here "camgeyser")
-- is resolved by label; a guest that cannot resolve it inside its window plays the film aimed at
-- its own craft instead of skipping it, and re-aims the moment the label resolves.
host.valid.camgeyser, host.labels.camgeyser, host.byLabel.cam_geyser = true, "cam_geyser", "camgeyser"
guest.byLabel.cam_geyser, fourth.byLabel.cam_geyser = nil, nil
third.byLabel.cam_geyser, third.valid["cg@3"] = "cg@3", true
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
host.api.present("SetObjectiveName", MARKER, "Commander Eldritch")
host.api.present("AddObjective", "misn0502.otf", "white")
host.api.ending("SucceedMission", now, "misn05w1.des")
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
-- A map object the engine cannot carry as a handle (the rendezvous geyser, nil on
-- every guest in the live 4-client run) goes by LABEL. Guest clocks are far from the
-- leader's (the old absolute `expires` made a guest drop the marker on first
-- receipt) and the label may resolve late: the marker must still land, in order,
-- exactly once.
local LABEL = "eggeizr1-1_geyser"
host.labels.geyser, host.byLabel[LABEL], host.valid.geyser = LABEL, "geyser", true
guest.clock, third.clock, fourth.clock = 100, -50, 0
third.byLabel[LABEL], fourth.byLabel[LABEL] = "geyser@3", "geyser@4"
third.valid["geyser@3"], fourth.valid["geyser@4"] = true, true
local mark = #guest.calls
host.api.present("SetObjectiveName", "geyser", "5th Platoon")
host.api.present("SetObjectiveOn", "geyser")
host.api.present("AddObjective", "misn0510.otf", "white")
for _=1,4 do tick() end
check(count(host, "SetObjectiveName", "geyser") == 1 and count(host, "SetObjectiveOn", "geyser") == 1,
    "the leader applies its own marker with the real handle")
check(count(third, "SetObjectiveName", "geyser@3") == 1 and count(fourth, "SetObjectiveOn", "geyser@4") == 1,
    "a label resolves per guest whatever the guest clock reads")
check(last(third, "SetObjectiveName")[3] == "5th Platoon", "the objective name survives the label swap")
check(count(guest, "SetObjectiveName", "geyser@2") == 0 and count(guest, "AddObjective", "misn0510.otf") == 0,
    "a label not yet resolvable on a guest holds the stream in order, even with its clock far ahead")
guest.byLabel[LABEL] = "geyser@2"; guest.valid["geyser@2"] = true
for _=1,3 do tick() end
check(count(guest, "SetObjectiveName", "geyser@2") == 1 and count(guest, "SetObjectiveOn", "geyser@2") == 1 and
    count(guest, "AddObjective", "misn0510.otf") == 1, "a late-resolving marker lands once, before the next event")
check(count(third, "SetObjectiveOn", "geyser@3") == 1, "retransmission never double-applies")

-- A label that never resolves (target genuinely gone) drops after the guest's OWN 5 s
-- and never blocks the stream; an Off for it is skipped without waiting.
host.labels.gone, host.byLabel.gone, host.valid.gone = "gone", "gone", true
for _, p in ipairs({guest, third, fourth}) do p.clock = p.clock + 7 end -- clocks jump: wait is relative
host.api.present("SetObjectiveOn", "gone")
host.api.present("AddObjective", "misn0511.otf", "white")
host.api.present("SetObjectiveOff", "gone")
host.api.present("AddObjective", "misn0512.otf", "white")
for _=1,12 do tick() end
check(count(guest, "AddObjective", "misn0511.otf") == 0, "the guest waits before dropping a marker (3 s of 5)")
for _=1,12 do tick() end
for _, p in ipairs({guest, third, fourth}) do
    check(count(p, "SetObjectiveOn", "gone") == 0 and count(p, "SetObjectiveOff", "gone") == 0,
        "a marker for a vanished target is dropped, not applied with nil")
    check(count(p, "AddObjective", "misn0511.otf") == 1 and count(p, "AddObjective", "misn0512.otf") == 1,
        "the stream resumes after the stale marker")
end

-- An object with no map label still travels as a plain handle (unchanged path).
local DYN = 9002
host.valid[DYN] = true
for _, p in ipairs({guest, third, fourth}) do p.valid[DYN] = true end
host.api.present("SetUserTarget", DYN); for _=1,4 do tick() end
check(count(guest, "SetUserTarget", DYN) == 1, "unlabelled objects keep the plain handle path")
-- A label only the leader knows (SetLabel on a spawned, replicated object): guests that cannot
-- resolve the label use the replicated handle sent beside it.
local SPAWNED = 9003
host.labels[SPAWNED], host.byLabel.leader_only, host.valid[SPAWNED] = "leader_only", SPAWNED, true
for _, p in ipairs({guest, third, fourth}) do p.valid[SPAWNED] = true end
host.api.present("SetObjectiveOn", SPAWNED); for _=1,4 do tick() end
check(count(guest, "SetObjectiveOn", SPAWNED) == 1 and count(fourth, "SetObjectiveOn", SPAWNED) == 1,
    "a leader-only label falls back to the replicated handle")print("misn05 object-camera, replica wait, local skip and ordered result checks passed: " .. checks)
