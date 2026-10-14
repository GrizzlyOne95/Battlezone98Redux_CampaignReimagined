-- Execute the misn11 presentation adapter in isolated Lua 5.1 peers.
-- This covers primitive protocol decisions, not native handle serialization.
-- misn11 has no cameras and no IsInfo relay: only the ordered E/A event stream exists (and no cockpit timer).
local file = assert(io.open("Scripts/misn11.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local adapter = assert(source:match("(local unpackArgs =.-)\n%-%- Presentation adapter ends"))
local now, peers, packets = 0, {}, {}
local registry = {[1]={team=1}, [2]={team=2}, [3]={team=3}, [4]={team=4}}
local checks = 0
local function check(value, why) assert(value, why); checks = checks + 1 end
local function peer(id)
    local p = {calls={}, valid={subject=true, target=true}}
    local env = setmetatable({}, {__index=_G})
    local function record(op, ...)
        p.calls[#p.calls+1] = {op, ...}
    end
    for _, op in ipairs({"ClearObjectives", "AddObjective", "UpdateObjective", "SetObjectiveOn",
        "SetObjectiveOff", "SetObjectiveName", "SetUserTarget", "RemoveObject", "SucceedMission",
        "FailMission"}) do
        local name = op
        env[name] = function(...) record(name, ...) end
    end
    -- p.clock offsets this peer's GetTime() from the shared test clock (clock skew).
    -- p.labels maps handle -> map label (GetLabel); p.byLabel maps label -> handle (GetHandle).
    env.GetTime = function() return now + (p.clock or 0) end
    p.labels, p.byLabel = {}, {}
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
    env.subtit = {Play=function(...) record("Play", ...); return "audio" end,
        Queue=function(...) record("Queue", ...) end, Stop=function() record("Stop") end}
    env.M = {}
    p.M = env.M
    p.printed = {}
    env.print = function(...) p.printed[#p.printed + 1] = table.concat({ ... }, " ") end
    env.SetLabel = function(h, l) record("SetLabel", h, l); p.labels[h] = l; p.byLabel[l] = h end
    p.io = {}
    env.IO_OPS = { IoState = true, IoErupt = true, IoQuake = true }
    env.CRIoWeather = { ApplyNetEvent = function(op, ...) p.io[#p.io + 1] = { op, ... }; return true end }
    local chunk = assert(loadstring("local CRCoop, M, subtit, LEADER_TEAM, IO_OPS, CRIoWeather = CRCoop, M, subtit, 1, IO_OPS, CRIoWeather\n" .. adapter .. [[
        return { present=Present, ending=EndMission, receive=ReceivePresentation,
            update=UpdatePresentationTransport, play=subtit.Play, queue=subtit.Queue,
            state=function() return receivedEvent end }
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

-- Audio is presented to every peer; the leader gets the native handle. Queue follows.
check(host.api.play("misn1100.wav") == "audio", "the leader receives the native audio handle")
host.api.queue("misn1101.wav")
for _=1,4 do tick() end
for _, p in pairs(peers) do
    check(count(p, "Play", "misn1100.wav") == 1 and count(p, "Queue", "misn1101.wav") == 1,
        "every peer hears the first line once and the queued line once")
end

-- Objectives and the briefing travel as plain primitives, once each, in order.
host.api.present("ClearObjectives")
host.api.present("AddObjective", "misn1100.otf", "white")
for _=1,4 do tick() end
for _, p in pairs(peers) do
    check(count(p, "ClearObjectives") == 1 and count(p, "AddObjective", "misn1100.otf") == 1, "objectives reach every peer once")
end
check(last(guest, "AddObjective")[3] == "white", "objective arguments survive the wire")
-- Guests never originate presentation.
guest.api.present("AddObjective", "misn1199.otf", "white")
for _=1,4 do tick() end
check(count(host, "AddObjective", "misn1199.otf") == 0 and count(third, "AddObjective", "misn1199.otf") == 0,
    "a guest's own presentation never reaches anyone")
-- Stale or foreign events are ignored.
local before = third.api.state()
third.api.receive(3, "E", before + 1, "AddObjective", 15, "misn1198.otf", "white")
third.api.update()
check(count(third, "AddObjective", "misn1198.otf") == 0, "events from a non-leader are ignored")
third.api.receive(1, "E", before + 5, "AddObjective", 15, "misn1197.otf", "white")
check(count(third, "AddObjective", "misn1197.otf") == 0 and third.api.state() == before, "an out-of-order event is not applied")

-- The Io weather events (state, eruption, quake) carry only numbers: they ride the same
-- ordered stream, reach every guest exactly once and never wait on a handle replica.
guest.valid[9100] = false
host.valid[9100] = true
host.api.present("IoState", 77, 0.0, 2, 0, 2, 0, 0)
host.api.present("SetObjectiveOn", 9100)
host.api.present("IoErupt", 2, 3, 20, 0.9)
host.api.present("IoQuake", 4, 0.85, 6.0, 1)
host.api.present("AddObjective", "misn1105.otf", "white")
for _=1,4 do tick() end
check(#guest.io == 1 and guest.io[1][1] == "IoState" and guest.io[1][2] == 77,
    "a state event arrives even while a later marker is waiting for its replica")
check(count(guest, "AddObjective", "misn1105.otf") == 0, "the stream stays ordered behind the waiting marker")
for _, p in ipairs({guest, third, fourth}) do p.valid[9100] = true end
for _=1,4 do tick() end
for _, p in ipairs({guest, third, fourth}) do
    check(#p.io == 3 and p.io[2][1] == "IoErupt" and p.io[3][1] == "IoQuake" and p.io[3][3] == 0.85 and p.io[3][4] == 6.0,
        "every guest receives the state, eruption and quake exactly once, in order")
end
check(count(host, "SetObjectiveOn", 9100) == 1 and #host.io == 3,
    "the leader applies its own events locally (Present applies the same op)")
check(count(guest, "AddObjective", "misn1105.otf") == 1, "the stream resumes after the marker resolves")

-- Dialogue passes through unchanged.
host.api.play("misn1104.wav")
for _=1,4 do tick() end
for _, p in pairs(peers) do
    check(count(p, "Play", "misn1104.wav") == 1, "the line plays as the DLL names it on every peer")
end

-- Drop the first event and reorder the retransmission; markers wait for replicas; the
-- result is held until every guest has acknowledged everything before it.
local MARKER = 9001
guest.valid[MARKER] = false
third.valid[MARKER], fourth.valid[MARKER] = true, true
host.valid[MARKER] = true
host.api.present("SetObjectiveName", MARKER, "Waypoint 1")
host.api.present("AddObjective", "misn1101.otf", "white")
host.api.ending("SucceedMission", now, "misn11w1.des")
host.api.update(); packets = {} -- loss
tick(true)
check(count(guest, "SetObjectiveName") == 0 and count(guest, "SucceedMission") == 0,
    "missing replica and out-of-order events must hold the result")
check(count(third, "SucceedMission") == 0, "the result is not published before the preceding events are acknowledged")
guest.valid[MARKER] = true
for _=1,40 do tick(true) end
check(count(guest, "SetObjectiveName") == 1 and count(guest, "AddObjective", "misn1101.otf") == 1,
    "retries apply ordered events exactly once")
local times = {}
for _, p in pairs(peers) do
    check(count(p, "SucceedMission") == 1, "all four peers must receive exactly one result")
    times[#times + 1] = last(p, "SucceedMission")[2]
    check(last(p, "SucceedMission")[3] == "misn11w1.des", "the result debrief reaches every peer")
end
check(times[1] == times[2] and times[2] == times[3] and times[3] == times[4], "the result time is identical on every peer (lock-step)")
check(host.M.coopResult and guest.M.coopResult, "every peer latches the result")
-- A second ending is ignored once the first has latched.
host.api.ending("FailMission", now, "misn11l1.des")
for _=1,40 do tick() end
for _, p in pairs(peers) do check(count(p, "FailMission") == 0, "a latched result cannot be overridden") end

-- FailMission is delivered the same way (fresh pair of peers).
packets = {}
for k in pairs(peers) do peers[k] = nil end
local failHost = peer(1)
local failGuest = peer(2)
failHost.api.ending("FailMission", now + 15, "misn11l1.des")
for _=1,60 do tick() end
check(count(failHost, "FailMission") == 1 and count(failGuest, "FailMission") == 1
    and last(failHost, "FailMission")[2] == last(failGuest, "FailMission")[2]
    and last(failGuest, "FailMission")[3] == "misn11l1.des", "a failure reaches every peer once with the same time")
peers[1], peers[2], peers[3], peers[4] = host, guest, third, fourth
now = now + 0

-- A map object the engine cannot carry as a handle (a map-authored object arrives nil on
-- every guest in the live 4-client run) goes by LABEL. Guest clocks are far from the
-- leader's and the label may resolve late: the marker must still land, in order, exactly once.
local LABEL = "launch_pad"
host.labels.launch_pad, host.byLabel[LABEL], host.valid.launch_pad = LABEL, "launch_pad", true
guest.clock, third.clock, fourth.clock = 100, -50, 0
third.byLabel[LABEL], fourth.byLabel[LABEL] = "pad@3", "pad@4"
third.valid["pad@3"], fourth.valid["pad@4"] = true, true
host.api.present("SetObjectiveOn", "launch_pad")
host.api.present("SetObjectiveName", "launch_pad", "Launch Pad")
host.api.present("AddObjective", "misn1110.otf", "white")
for _=1,4 do tick() end
check(count(host, "SetObjectiveName", "launch_pad") == 1 and count(host, "SetObjectiveOn", "launch_pad") == 1,
    "the leader applies its own marker with the real handle")
check(count(third, "SetObjectiveName", "pad@3") == 1 and count(fourth, "SetObjectiveOn", "pad@4") == 1,
    "a label resolves per guest whatever the guest clock reads")
check(last(third, "SetObjectiveName")[3] == "Launch Pad", "the objective name survives the label swap")
check(count(guest, "SetObjectiveOn", "pad@2") == 0 and count(guest, "AddObjective", "misn1110.otf") == 0,
    "a label not yet resolvable on a guest holds the stream in order, even with its clock far ahead")
guest.byLabel[LABEL] = "pad@2"; guest.valid["pad@2"] = true
for _=1,3 do tick() end
check(count(guest, "SetObjectiveOn", "pad@2") == 1 and count(guest, "SetObjectiveName", "pad@2") == 1 and
    count(guest, "AddObjective", "misn1110.otf") == 1, "a late-resolving marker lands once, before the next event")
check(count(third, "SetObjectiveOn", "pad@3") == 1, "retransmission never double-applies")

-- An object with no map label still travels as a plain handle (unchanged path).
local DYN = 9002
host.valid[DYN] = true
for _, p in ipairs({guest, third, fourth}) do p.valid[DYN] = true end
host.api.present("SetUserTarget", DYN); for _=1,4 do tick() end
check(count(guest, "SetUserTarget", DYN) == 1, "unlabelled objects keep the plain handle path")
-- A label only the leader knows: guests that cannot resolve the label use the replicated handle.
local SPAWNED = 9003
host.labels[SPAWNED], host.byLabel.leader_only, host.valid[SPAWNED] = "leader_only", SPAWNED, true
for _, p in ipairs({guest, third, fourth}) do p.valid[SPAWNED] = true end
host.api.present("SetObjectiveOn", SPAWNED); for _=1,4 do tick() end
check(count(guest, "SetObjectiveOn", SPAWNED) == 1 and count(fourth, "SetObjectiveOn", SPAWNED) == 1,
    "a leader-only label falls back to the replicated handle")

-- Genuinely gone: a marker whose target the leader reports gone is skipped without waiting,
-- and an Off for a label nobody can resolve never holds the stream.
host.valid.doomed, host.labels.doomed, host.byLabel.doomed_lbl = true, "doomed_lbl", "doomed"
host.api.present("SetObjectiveOn", "doomed"); host.valid.doomed = false
host.api.present("AddObjective", "misn11111.otf", "white")
host.api.present("SetObjectiveOff", "never_seen")
host.api.present("AddObjective", "misn11112.otf", "white")
for _=1,6 do tick() end
for _, p in ipairs({guest, third, fourth}) do
    check(count(p, "SetObjectiveOn", "doomed") == 0, "a marker the leader reports gone is skipped")
    check(count(p, "AddObjective", "misn11111.otf") == 1 and count(p, "AddObjective", "misn11112.otf") == 1,
        "the stream resumes right after a gone marker")
end

-- A marker waits for the real object past any short window; only the 15 s guard ends it.
local STUCK = 9020
host.valid[STUCK], host.labels[STUCK], host.byLabel.stuck_lbl = true, "stuck_lbl", STUCK
local unresolved = guest.M.coopUnresolved or 0
host.api.present("SetObjectiveOn", STUCK)
host.api.present("AddObjective", "misn11113.otf", "white")
for _=1,32 do tick() end -- 8 s
check(count(guest, "AddObjective", "misn11113.otf") == 0, "an unresolved marker keeps the stream waiting well past 5 s")
for _=1,36 do tick() end
check(count(guest, "AddObjective", "misn11113.otf") == 1 and count(guest, "SetObjectiveOn", STUCK) == 0,
    "the safety guard drops only the stale marker")
check((guest.M.coopUnresolved or 0) == unresolved + 1, "the timeout is counted for the harness probe")
local loud = false
for _, line in ipairs(guest.printed) do loud = loud or line:find("%[coop%] unresolved stuck_lbl") ~= nil end
check(loud, "the timeout logs a loud [coop] unresolved line")

-- A spawned object nobody labelled gets a deterministic unique label from the leader, and a
-- Label event makes the guests carry it before the marker that uses it.
local SPAWN = 9021
host.valid[SPAWN] = true
for _, p in ipairs({guest, third, fourth}) do p.valid[SPAWN] = true end
host.api.present("SetObjectiveOn", SPAWN); for _=1,4 do tick() end
local label = host.labels[SPAWN]
check(type(label) == "string" and label:find("^crco_") ~= nil, "the leader labels an unlabelled spawned target")
for _, p in ipairs({guest, third, fourth}) do
    check(count(p, "SetLabel", SPAWN) == 1 and last(p, "SetLabel")[3] == label, "each guest carries the leader's label")
    check(count(p, "SetObjectiveOn", SPAWN) == 1, "the marker lands on the real replicated object")
end
-- Late-replicating spawn: Label and marker wait, then both land on the real handle.
local LATESPAWN = 9022
host.valid[LATESPAWN] = true
host.api.present("SetObjectiveOn", LATESPAWN)
for _=1,6 do tick() end
check(count(guest, "SetLabel", LATESPAWN) == 0 and count(guest, "SetObjectiveOn", LATESPAWN) == 0,
    "a spawn that has not replicated holds its Label and marker")
guest.valid[LATESPAWN] = true
for _=1,4 do tick() end
check(count(guest, "SetLabel", LATESPAWN) == 1 and count(guest, "SetObjectiveOn", LATESPAWN) == 1,
    "the Label and the marker apply to the real object once it replicates")
print("misn11 dialogue, label markers, replica wait, Io events and ordered result checks passed: " .. checks)
