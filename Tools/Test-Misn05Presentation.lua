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
local function count(p, op)
    local n = 0; for _, call in ipairs(p.calls) do if call[1] == op then n = n + 1 end end
    return n
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

-- Drop the first event and reorder the retransmission; markers wait for replicas.
guest.valid.marker = false
third.valid.marker, fourth.valid.marker = true, true
host.valid.marker = true
host.api.present("SetObjectiveName", "marker", "Commander Eldritch")
host.api.present("AddObjective", "misn0502.otf", "white")
host.api.ending("SucceedMission", now, "misn05w1.des")
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
print("misn05 object-camera, replica wait, local skip and ordered result checks passed: " .. checks)
