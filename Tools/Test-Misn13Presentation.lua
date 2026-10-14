-- Run from the repository root: lua5.1 Tools/Test-Misn13Presentation.lua
-- Part A executes the misn13 presentation adapter (the block between "local unpackArgs" and
-- "Presentation adapter ends") in isolated Lua 5.1 peers: protocol decisions only, not native
-- handle serialization. Part B runs the complete Scripts/misn13.lua in four separate environments
-- over the real CRCoop registry and the E/A transport (Tools/BZRPeerTransportSim.lua); the engine,
-- the AI and the Europa director are mocks. misn13 has no cameras and no IsInfo relay: only the
-- ordered E/A event stream exists.
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local checks = 0
local function check(value, why) assert(value, why); checks = checks + 1 end

-- ============================================================ PART A: the adapter in isolation
local file = assert(io.open("Scripts/misn13.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local adapter = assert(source:match("(local unpackArgs =.-)\n%-%- Presentation adapter ends"))
do
    local now, peers, packets = 0, {}, {}
    local registry = {[1]={team=1}, [2]={team=2}, [3]={team=3}, [4]={team=4}}
    local function peer(id)
        local p = {calls={}, valid={}}
        local env = setmetatable({}, {__index=_G})
        local function record(op, ...) p.calls[#p.calls+1] = {op, ...} end
        for _, op in ipairs({"ClearObjectives", "AddObjective", "UpdateObjective", "SetObjectiveOn",
            "SetObjectiveOff", "SetObjectiveName", "SetUserTarget", "RemoveObject", "SucceedMission",
            "FailMission"}) do
            local name = op
            env[name] = function(...) record(name, ...) end
        end
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
        p.eu = {}
        local EUROPA = { EuropaState = true, EuropaPlume = true, EuropaQuake = true, EuropaSurge = true }
        env.CREuropaWeather = { ApplyNetEvent = function(op, ...) p.eu[#p.eu + 1] = { op, ... }; return true end }
        local chunk = assert(loadstring("local CRCoop, M, subtit, LEADER_TEAM, EUROPA_OPS, CREuropaWeather = CRCoop, M, subtit, 1, ...\n" .. adapter .. [[
            return { present=Present, ending=EndMission, receive=ReceivePresentation,
                update=UpdatePresentationTransport, play=subtit.Play, queue=subtit.Queue,
                state=function() return receivedEvent end }
        ]]))
        setfenv(chunk, env)
        p.api = chunk(EUROPA, env.CREuropaWeather); peers[id] = p
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
    local guests = {guest, third, fourth}

    -- Dialogue: the leader gets the native audio handle; Play and Queue reach every peer once, in order.
    check(host.api.play("misn1300.wav") == "audio", "the leader receives the native audio handle")
    host.api.queue("misn1301.wav")
    for _=1,4 do tick() end
    for _, p in pairs(peers) do
        check(count(p, "Play", "misn1300.wav") == 1 and count(p, "Queue", "misn1301.wav") == 1,
            "every peer hears the briefing once and the queued line once")
    end

    -- The DLL objective, then the replacement list: four arguments survive the wire intact.
    host.api.present("ClearObjectives")
    host.api.present("AddObjective", "misn1300.otf", "white")
    host.api.present("ClearObjectives")
    host.api.present("AddObjective", "misn13_recycler", "white", 8.0, "Defend your Recycler")
    host.api.present("AddObjective", "misn13_silos", "white", 8.0, "Destroy the CCA silos (0/4)")
    host.api.present("UpdateObjective", "misn13_silos", "white", 8.0, "Destroy the CCA silos (1/4)")
    for _=1,4 do tick() end
    for _, p in pairs(peers) do
        check(count(p, "ClearObjectives") == 2 and count(p, "AddObjective", "misn1300.otf") == 1,
            "the stock objective and the clear reach every peer once each")
    end
    for _, p in ipairs(guests) do
        local add, upd = last(p, "AddObjective"), last(p, "UpdateObjective")
        check(add[2] == "misn13_silos" and add[3] == "white" and add[4] == 8.0 and add[5] == "Destroy the CCA silos (0/4)",
            "AddObjective keeps all four arguments")
        check(upd[2] == "misn13_silos" and upd[3] == "white" and upd[4] == 8.0 and upd[5] == "Destroy the CCA silos (1/4)",
            "UpdateObjective keeps all four arguments")
        check(p.calls[3][1] == "ClearObjectives" and p.calls[4][1] == "AddObjective" and p.calls[4][2] == "misn1300.otf",
            "objectives arrive in the order the leader issued them")
    end
    -- Guests never originate presentation.
    guest.api.present("AddObjective", "misn1399.otf", "white")
    guest.api.present("UpdateObjective", "misn13_silos", "red", 8.0, "forged")
    for _=1,4 do tick() end
    check(count(host, "AddObjective", "misn1399.otf") == 0 and count(third, "AddObjective", "misn1399.otf") == 0
        and count(host, "UpdateObjective") == 1 and count(fourth, "UpdateObjective") == 1,
        "a guest's own presentation never reaches anyone")
    check(count(guest, "AddObjective", "misn1399.otf") == 0, "a guest's Present does not even apply locally")
    -- Stale or foreign events are ignored.
    local before = third.api.state()
    third.api.receive(3, "E", before + 1, "AddObjective", 15, "misn1398.otf", "white")
    third.api.update()
    check(count(third, "AddObjective", "misn1398.otf") == 0, "events from a non-leader are ignored")
    third.api.receive(1, "E", before + 5, "AddObjective", 15, "misn1397.otf", "white")
    check(count(third, "AddObjective", "misn1397.otf") == 0 and third.api.state() == before, "an out-of-order event is not applied")

    -- Europa weather events carry numbers only: they never get a label or a TTL wait, and guests
    -- apply them through CREuropaWeather.ApplyNetEvent exactly once, in order, behind a waiting marker.
    local NAV = 9100
    host.valid[NAV] = true; host.labels[NAV], host.byLabel.apcamr20_camerapod = "apcamr20_camerapod", NAV
    host.api.present("EuropaState", 77, 0.0, 2, 0, 2)
    host.api.present("SetObjectiveName", NAV, "Drop Zone")
    host.api.present("EuropaPlume", 2, 3, 20, 0.9)
    host.api.present("EuropaQuake", 4, 0.85, 6.0)
    host.api.present("EuropaSurge", 6.0, 0.8)
    host.api.present("AddObjective", "misn13_hangar", "white", 8.0, "Destroy the CCA hangar")
    for _=1,4 do tick() end
    check(#host.eu == 4 and host.eu[1][1] == "EuropaState" and host.eu[4][1] == "EuropaSurge",
        "Present applies the weather op on the leader itself")
    check(#guest.eu == 1 and guest.eu[1][1] == "EuropaState" and guest.eu[1][2] == 77,
        "a weather state event arrives even while the next marker waits for its object")
    check(count(guest, "SetObjectiveName") == 0 and count(guest, "AddObjective", "misn13_hangar") == 0,
        "the stream stays ordered behind the waiting marker")
    for _, p in ipairs(guests) do
        p.byLabel.apcamr20_camerapod = 5000 + 1; p.valid[5001] = true
    end
    guest.byLabel.apcamr20_camerapod = nil; guest.valid[5001] = false -- this guest still cannot resolve it
    for _=1,4 do tick() end
    for _, p in ipairs({third, fourth}) do
        check(#p.eu == 4 and p.eu[2][1] == "EuropaPlume" and p.eu[3][1] == "EuropaQuake" and p.eu[4][1] == "EuropaSurge"
            and p.eu[3][3] == 0.85 and p.eu[3][4] == 6.0 and p.eu[4][2] == 6.0 and p.eu[4][3] == 0.8,
            "every guest receives state, plume, quake and surge exactly once, in order, with arguments intact")
        check(count(p, "SetObjectiveName", 5001) == 1 and last(p, "SetObjectiveName")[3] == "Drop Zone",
            "the nav pod label resolves per guest and the name survives")
        check(count(p, "AddObjective", "misn13_hangar") == 1, "the stream resumes after the marker resolves")
        check(count(p, "SetLabel") >= 1 and last(p, "SetLabel")[3] == "apcamr20_camerapod",
            "the Label event carries the map label to the guest")
    end
    check(#guest.eu == 1 and count(guest, "AddObjective", "misn13_hangar") == 0, "a guest that cannot resolve keeps waiting")
    guest.byLabel.apcamr20_camerapod = 5002; guest.valid[5002] = true
    for _=1,4 do tick() end
    check(#guest.eu == 4 and count(guest, "SetObjectiveName", 5002) == 1 and count(guest, "AddObjective", "misn13_hangar") == 1,
        "the late guest catches up once its object exists")
    check(#host.eu == 4, "the leader is not re-fed its own weather events")

    -- RemoveObject: by label when labelled (the scavenger swap), "!" when already gone, and a removal a
    -- guest cannot resolve never makes it wait.
    for i = 1, 4 do
        local h = 9200 + i
        host.valid[h] = true
        host.labels[h], host.byLabel["svscav" .. i] = "svscav" .. i, h
        for _, p in ipairs(guests) do p.byLabel["svscav" .. i] = 6000 + i; p.valid[6000 + i] = true end
    end
    host.valid[9202] = false -- svscav2 was killed before the swap reached it
    guest.valid[9203] = false
    for i = 1, 4 do host.api.present("RemoveObject", 9200 + i) end
    host.api.present("AddObjective", "misn13_after_swap", "white", 8.0, "after")
    for _=1,6 do tick() end
    for _, p in ipairs(guests) do
        check(count(p, "RemoveObject", 6001) == 1 and count(p, "RemoveObject", 6003) == 1 and count(p, "RemoveObject", 6004) == 1,
            "a labelled removal is resolved by label on every guest")
        check(count(p, "RemoveObject", 6002) == 0 and count(p, "RemoveObject", 9202) == 0,
            "a gone object is skipped (wire '!'), never applied")
        check(count(p, "AddObjective", "misn13_after_swap") == 1, "the stream is not held by removals")
    end
    check(count(host, "RemoveObject", 9201) == 1, "the leader removes the real handle itself")
    -- A labelled removal whose object a guest has not replicated yet is held (in order) by the Label
    -- event that precedes it, then lands once; it is never applied to a missing handle.
    local unresolvedBefore = guest.M.coopUnresolved
    host.valid[9300], host.labels[9300], host.byLabel.late_scav = true, "late_scav", 9300
    third.byLabel.late_scav, fourth.byLabel.late_scav = 7300, 7300
    third.valid[7300], fourth.valid[7300] = true, true
    host.api.present("RemoveObject", 9300)
    host.api.present("AddObjective", "misn13_after_late", "white", 8.0, "later")
    for _=1,6 do tick() end
    check(count(guest, "AddObjective", "misn13_after_late") == 0 and count(guest, "RemoveObject", 7300) == 0,
        "a guest that cannot resolve the removal yet holds the stream in order")
    check(count(third, "RemoveObject", 7300) == 1 and count(third, "AddObjective", "misn13_after_late") == 1,
        "a guest that can resolve it removes by label once and moves on")
    guest.byLabel.late_scav = 7301; guest.valid[7301] = true
    for _=1,4 do tick() end
    check(count(guest, "RemoveObject", 7301) == 1 and count(guest, "AddObjective", "misn13_after_late") == 1,
        "the late guest removes the real object once it replicates")
    check(guest.M.coopUnresolved == unresolvedBefore, "a late-resolving removal never trips the 15 s guard")

    -- Drop the first event and reorder the retransmission; markers wait for replicas; the
    -- result (SucceedMission with its description file) is held until every guest acknowledged everything.
    local MARKER = 9001
    guest.valid[MARKER] = false
    third.valid[MARKER], fourth.valid[MARKER] = true, true
    host.valid[MARKER] = true
    host.api.present("SetObjectiveName", MARKER, "Waypoint")
    host.api.present("AddObjective", "misn13_factory", "white", 8.0, "Destroy the CCA Unit Factory")
    host.api.play("misn1303.wav")
    host.api.ending("SucceedMission", now + 15, "misn13w1.des")
    check(host.M.coopPendingResult and not host.M.coopResult, "the leader only queues the result")
    host.api.update(); packets = {} -- loss
    tick(true)
    check(count(guest, "SetObjectiveName", MARKER) == 0 and count(guest, "SucceedMission") == 0,
        "missing replica and out-of-order events must hold the result")
    check(count(third, "SucceedMission") == 0, "the result is not published before the preceding events are acknowledged")
    guest.valid[MARKER] = true
    for _=1,80 do tick(true) end
    check(count(guest, "SetObjectiveName", MARKER) == 1 and count(guest, "AddObjective", "misn13_factory") == 1
        and count(guest, "Play", "misn1303.wav") == 1, "retries apply ordered events exactly once")
    local times = {}
    for _, p in pairs(peers) do
        check(count(p, "SucceedMission") == 1, "all four peers must receive exactly one result")
        times[#times + 1] = last(p, "SucceedMission")[2]
        check(last(p, "SucceedMission")[3] == "misn13w1.des", "the result debrief file reaches every peer")
    end
    check(times[1] == times[2] and times[2] == times[3] and times[3] == times[4], "the result time is identical on every peer (lock-step)")
    check(host.M.coopResult and guest.M.coopResult and third.M.coopResult, "every peer latches the result")
    check(host.M.coopPendingResult == nil, "the pending result is consumed")
    -- Ordering: the dialogue precedes the result on a guest.
    local playAt, resultAt
    for i, c in ipairs(third.calls) do
        if c[1] == "Play" and c[2] == "misn1303.wav" then playAt = i end
        if c[1] == "SucceedMission" then resultAt = i end
    end
    check(playAt and resultAt and playAt < resultAt, "misn1303 plays before the result lands on a guest")
    -- A second ending is ignored once the first has latched.
    host.api.ending("FailMission", now, "misn13f1.des")
    for _=1,40 do tick() end
    for _, p in pairs(peers) do check(count(p, "FailMission") == 0, "a latched result cannot be overridden") end

    -- FailMission is delivered the same way (fresh pair of peers).
    packets = {}
    for k in pairs(peers) do peers[k] = nil end
    registry[3], registry[4] = nil, nil -- only two humans are in this session
    local failHost = peer(1)
    local failGuest = peer(2)
    failHost.api.play("misn1304.wav")
    failHost.api.ending("FailMission", now + 15, "misn13f1.des")
    for _=1,80 do tick() end
    check(count(failHost, "FailMission") == 1 and count(failGuest, "FailMission") == 1
        and last(failHost, "FailMission")[2] == last(failGuest, "FailMission")[2]
        and last(failGuest, "FailMission")[3] == "misn13f1.des", "a failure reaches every peer once with the same time")
    check(count(failGuest, "Play", "misn1304.wav") == 1 and count(failGuest, "SucceedMission") == 0,
        "the defeat line plays on the guest and no victory is raised")
    peers[1], peers[2], peers[3], peers[4] = host, guest, third, fourth
    registry[3], registry[4] = {team=3}, {team=4}

    -- A label only resolvable late holds the stream; the 15 s guard drops only that marker and logs loudly.
    local STUCK = 9020
    host.valid[STUCK], host.labels[STUCK], host.byLabel.stuck_lbl = true, "stuck_lbl", STUCK
    local unresolved = guest.M.coopUnresolved or 0
    host.api.present("SetObjectiveOn", STUCK)
    host.api.present("AddObjective", "misn13_stuck_after", "white", 8.0, "after")
    for _=1,32 do tick() end -- 8 s
    check(count(guest, "AddObjective", "misn13_stuck_after") == 0, "an unresolved marker keeps the stream waiting well past 5 s")
    for _=1,40 do tick() end
    check(count(guest, "AddObjective", "misn13_stuck_after") == 1 and count(guest, "SetObjectiveOn") == 0,
        "the safety guard drops only the stale marker")
    check((guest.M.coopUnresolved or 0) == unresolved + 1, "the timeout is counted for the harness probe")
    local loud = false
    for _, line in ipairs(guest.printed) do loud = loud or line:find("%[coop%] unresolved stuck_lbl") ~= nil end
    check(loud, "the timeout logs a loud [coop] unresolved line")
end

-- ============================================================ PART B: the full script on four peers
local now, objects, peers, nextObject, transport, world, dropFn, nextHandle
local FAR = 90000
-- Authored teams: the Texas, its nav pod and the player stub are team 1, every other labelled object is the CCA.
local NSDF_LABELS = {avrecycle = true, apcamr20_camerapod = true, player0_hover = true}
local function reset()
    now, objects, peers, nextObject, dropFn, nextHandle = 0, {}, {}, 0, nil, 100
    world = {scrap = {}, labels = {}, net = false}
    transport = PeerTransport.New(function(packet)
        local peer = peers[packet.to]
        if peer then peer.env.Receive(packet.from, packet.kind, unpack(packet.args)) end
    end)
end
local function newObject(odf, team, label)
    nextHandle = nextHandle + 1
    objects[nextHandle] = {alive = true, odf = odf, team = team, health = 1, pos = {x = FAR, y = 20, z = FAR}, label = label}
    if label then world.labels[label] = nextHandle end
    return nextHandle
end
local function count(peer, name, first)
    local n = 0
    for _, c in ipairs(peer.calls) do
        if c[1] == name and (first == nil or c[2] == first) then n = n + 1 end
    end
    return n
end
local function last(peer, name)
    for i = #peer.calls, 1, -1 do if peer.calls[i][1] == name then return peer.calls[i] end end
end
local function sendsOfKind(peer, kind)
    local n = 0
    for _, c in ipairs(peer.calls) do if c[1] == "Send" and c[2] == kind then n = n + 1 end end
    return n
end
local PRESENTATION = {ClearObjectives = true, AddObjective = true, UpdateObjective = true, SetObjectiveName = true,
    RemoveObject = true, Play = true, Queue = true, SucceedMission = true, FailMission = true}
-- A peer's presentation calls, one comparable string per call.
local function stream(peer)
    local out = {}
    for _, c in ipairs(peer.calls) do
        if PRESENTATION[c[1]] and not (c.native) then
            local parts = {}
            for i = 1, #c do parts[#parts + 1] = tostring(c[i]) end
            out[#out + 1] = table.concat(parts, "|")
        end
    end
    return out
end
local function sameStream(a, b)
    local sa, sb = stream(a), stream(b)
    if #sa ~= #sb then return false end
    for i = 1, #sa do if sa[i] ~= sb[i] then return false end end
    return true
end
local function indexOf(peer, name, a, b)
    for i, c in ipairs(peer.calls) do
        if c[1] == name and (a == nil or c[2] == a) and (b == nil or c[3] == b) then return i end
    end
end

local function makePeer(id, team)
    local p = {id = id, team = team, calls = {}, hosting = team == 1, player = nil}
    p.eu = {updates = 0, announces = 0, shutdowns = 0, targets = {}, forces = {}, releases = 0, quakes = {}, surges = {}, events = {}}
    peers[id] = p
    p.player = newObject("avtank", team)
    local function record(name, ...) p.calls[#p.calls + 1] = {name, ...} end
    local e = setmetatable({}, {__index = _G})
    e._G = e
    e.print = function() end
    e.IsNetGame = function() return true end
    e.IsHosting = function() return p.hosting end
    e.GetTime = function() return now end
    e.GetPlayerHandle = function(remote)
        assert(remote == nil, "remote GetPlayerHandle(team) must never be used")
        return p.player
    end
    e.GetHandle = function(label)
        if not world.labels[label] then
            newObject(NSDF_LABELS[label] and "avrecy" or "svtank", NSDF_LABELS[label] and 1 or 5, label)
        end
        local h = world.labels[label]
        return objects[h] and objects[h].alive and h or nil
    end
    e.GetLabel = function(h) return objects[h] and objects[h].label end
    e.SetLabel = function(h, l) record("SetLabel", h, l) end
    e.IsValid = function(h) return objects[h] ~= nil end
    e.IsAlive = function(h) return objects[h] ~= nil and objects[h].alive end
    e.IsOdf = function(h, odf) return e.IsValid(h) and objects[h].odf == odf end
    e.GetTeamNum = function(h) return objects[h] and objects[h].team or 0 end
    e.GetPosition = function(h)
        local o = objects[h]
        return o and {x = o.pos.x, y = o.pos.y, z = o.pos.z} or {x = 0, y = 0, z = 0}
    end
    e.SetVector = function(x, y, z) return {x = x or 0, y = y or 0, z = z or 0} end
    e.GetDistance = function(a, b) return 10000 end
    e.GetHealth = function(h) return objects[h] and objects[h].health or 1 end
    e.GetWhoShotMe = function() return nil end
    e.CountUnitsNearObject = function() return 3 end
    e.AllObjects = function()
        local list = {}
        for h, o in pairs(objects) do if o.alive then list[#list + 1] = h end end
        local i = 0
        return function() i = i + 1; return list[i] end
    end
    e.AllCraft = e.AllObjects
    e.GetPilot = function() return 10 end
    e.GetMaxScrap = function() return 100 end
    e.GetMaxPilot = function() return 30 end
    e.SetMaxScrap = function() end
    e.SetMaxPilot = function() end
    e.IsPerson = function() return false end
    e.GetVelocity = function() return {x = 0, y = 0, z = 0} end
    e.SetVelocity = function() end
    e.GetFront = function() return {x = 1, y = 0, z = 0} end
    e.SetTeamNum = function(h, t) objects[h].team = t end
    e.GetPerceivedTeam = function(h) return objects[h] and objects[h].team end
    e.SetPerceivedTeam = function() end
    e.EjectPilot = function() end
    e.GetIn = function() end
    e.BuildObject = function(odf, objectTeam, where)
        local h = newObject(odf, objectTeam)
        record("BuildObject", odf, objectTeam, where, h)
        e.AddObject(h)
        return h
    end
    e.RemoveObject = function(h)
        record("RemoveObject", h)
        -- The world is shared by every mock peer: removal lands after all of them applied the event.
        if objects[h] then objects[h].removeAt = objects[h].removeAt or (now + 3) end
    end
    e.GetScrap = function(t) return world.scrap[t] or 0 end
    e.SetScrap = function(t, v) record("SetScrap", t, v); world.scrap[t] = v end
    e.AddScrap = function(t, v) record("AddScrap", t, v); world.scrap[t] = (world.scrap[t] or 0) + v end
    e.Send = function(to, kind, ...)
        record("Send", kind)
        local args = {...}
        local bytes = 4
        for _, value in ipairs(args) do bytes = bytes + (type(value) == "string" and #value + 2 or 9) end
        assert(bytes < 244, "mission packet exceeds stock payload budget: " .. kind)
        for target in pairs(peers) do
            if target ~= id and (to == 0 or to == nil or target == to) then transport:Send(id, target, kind, args, false) end
        end
    end
    for _, name in ipairs({"Follow", "Defend", "Stop", "Goto", "Attack", "Retreat", "SetIndependence", "SetAIP",
        "SetAIControl", "SetObjectiveName", "SetObjectiveOn", "SetObjectiveOff", "SetUserTarget", "ClearObjectives",
        "AddObjective", "UpdateObjective", "Ally", "UnAlly", "DisplayMessage", "FailMission", "SucceedMission",
        "SetPilot", "Pickup"}) do
        local n = name
        e[n] = function(...)
            if n == "SetObjectiveOn" or n == "SetObjectiveName" then
                assert(e.IsValid((...)), "presentation used a not-yet-valid handle")
            end
            record(n, ...)
        end
    end
    e.AiCommand = {FORMATION = 6}
    e.SetCommand = function() end
    local function noop() end
    local modules = {
        RequireFix = {Initialize = noop},
        -- The real director has its own suite (Test-CREuropaWeather.lua); this records the mission's wiring.
        -- Quake/Surge/AnnounceState behave like the authority director: they queue their event onto the
        -- mission's ordered stream through the send hook.
        CREuropaWeather = {
            Init = function(options) p.eu.init = options end,
            Update = function() p.eu.updates = p.eu.updates + 1 end,
            Shutdown = function() p.eu.shutdowns = p.eu.shutdowns + 1 end, OnObjectCreated = noop,
            Save = function() return {saved = true} end, Load = function(state) p.eu.loaded = state end,
            AnnounceState = function()
                p.eu.announces = p.eu.announces + 1
                if p.eu.init and p.eu.init.send then p.eu.init.send("EuropaState", 4242, 0.0, 1, 0, 1) end
            end,
            ApplyNetEvent = function(op, ...) p.eu.events[#p.eu.events + 1] = {op, ...}; return true end,
            SetTargetLevel = function(level) p.eu.targets[#p.eu.targets + 1] = level end,
            ForceLevel = function(level, seconds, transition) p.eu.forces[#p.eu.forces + 1] = {level, seconds, transition} end,
            ReleaseForcedLevel = function() p.eu.releases = p.eu.releases + 1 end,
            Quake = function(strength, seconds)
                p.eu.quakes[#p.eu.quakes + 1] = {strength, seconds}
                if p.eu.init and p.eu.init.send then p.eu.init.send("EuropaQuake", strength, seconds) end
            end,
            Surge = function(seconds, strength)
                p.eu.surges[#p.eu.surges + 1] = {seconds, strength}
                if p.eu.init and p.eu.init.send then p.eu.init.send("EuropaSurge", seconds, strength) end
            end,
            Seed = 4242},
        CREuropaSites13 = {mission = "misn13"}, Environment = {Init = noop, Update = noop, OnObjectCreated = noop},
        exu = {GetMyNetID = function() return id end, DisableStartingRecycler = function() record("DisableStartingRecycler") end,
            SetLives = function(n) record("SetLives", n) end},
        ScriptSubtitles = {
            Play = function(file) record("Play", file); return file end,
            Queue = function(file) record("Queue", file) end,
            Stop = function() record("Stop") end, Update = noop, Initialize = noop},
    }
    modules.CRCoopComms = assert(loadfile("Scripts/CRCoopComms.lua"))()
    modules.CRCoopRespawn = assert(loadfile("Scripts/CRCoopRespawn.lua"))()
    e.package = setmetatable({loaded = {exu = modules.exu}}, {__index = package})
    modules.CRCoop = setfenv(assert(loadfile("Scripts/CRCoop.lua")), e)()
    e.require = function(name) return assert(modules[name], name) end
    setfenv(assert(loadfile("Scripts/misn13.lua")), e)()
    p.env, p.coop = e, modules.CRCoop
    e.Start()
    p.state = e.Save()
    return p
end

local function physics()
    for h, o in pairs(objects) do
        if o.removeAt and now >= o.removeAt then objects[h] = nil end
    end
end
local function tick(dt)
    dt = dt or 0.25
    now = now + dt
    physics()
    for _, p in pairs(peers) do p.env.Update(dt) end
    transport:Step(now, false, dropFn)
end
local function run(seconds, dt)
    dt = dt or 0.25
    for _ = 1, math.floor(seconds / dt + 0.5) do tick(dt) end
end
local function eachPeer(fn) for _, p in pairs(peers) do fn(p) end end
local function session(humans)
    reset()
    local host = makePeer(10, 1)
    local guests = {}
    for i = 2, (humans or 4) do guests[#guests + 1] = makePeer(10 * i, i) end
    for _, p in pairs(peers) do
        for id, other in pairs(peers) do p.env.CreatePlayer(id, "P" .. id, other.team) end
    end
    run(3)
    return host, guests
end
local function label(p, name) return p.env.GetHandle(name) end
local function kill(name) objects[world.labels[name]].alive = false end
local function allGuests(guests, fn) for _, g in ipairs(guests) do fn(g) end end
local function lastText(p, key)
    for i = #p.calls, 1, -1 do
        local c = p.calls[i]
        if (c[1] == "UpdateObjective" or c[1] == "AddObjective") and c[2] == key then return c[5], c[3] end
    end
end

-- ------------------------------------------------ 1. startup stream reaches every guest in order
do
    local host, guests = session(4)
    local s = host.state
    check(s.start_done and s.hangar == world.labels.svguntower2, "the leader starts the mission body")
    allGuests(guests, function(g)
        check(not g.state.start_done and count(g, "BuildObject") == 0, "guests never run the mission body")
        check(sendsOfKind(g, "E") == 0, "a guest never emits an E event")
        check(sendsOfKind(g, "A") > 0, "a guest acknowledges the stream")
    end)
    check(sendsOfKind(host, "E") > 0 and sendsOfKind(host, "A") == 0, "the leader emits events and never acknowledges")
    eachPeer(function(p)
        check(count(p, "Play", "misn1300.wav") == 1, "the opening briefing plays once on every peer")
        check(count(p, "AddObjective", "misn1300.otf") == 1, "the DLL objective reaches every peer once")
        check(count(p, "ClearObjectives") == 2, "the DLL clear and the replacement clear reach every peer")
        check(count(p, "AddObjective", "misn13_recycler") == 1 and count(p, "AddObjective", "misn13_factory") == 1
            and count(p, "AddObjective", "misn13_hangar") == 1 and count(p, "AddObjective", "misn13_silos") == 1,
            "the four objectives reach every peer once")
        check(count(p, "SetObjectiveName", label(host, "apcamr20_camerapod")) == 1
            and last(p, "SetObjectiveName")[3] == "Drop Zone", "the nav pod is named Drop Zone on every peer")
        check(p.state.coopUnresolved == nil or p.state.coopUnresolved == 0, "no unresolved marker on any peer")
    end)
    allGuests(guests, function(g)
        check(count(g, "SetLabel", label(host, "apcamr20_camerapod")) == 1
            and last(g, "SetLabel")[3] == "apcamr20_camerapod", "the guest carries the nav pod's map label")
        check(sameStream(host, g), "a guest's presentation stream equals the leader's, call for call")
    end)
    local add = last(guests[1], "AddObjective")
    check(add[2] == "misn13_silos" and add[3] == "white" and add[4] == 8.0 and add[5] == "Destroy the CCA silos (0/4)",
        "four-argument objectives arrive intact on a guest")
    check(count(host, "RemoveObject", label(host, "player0_hover")) == 1
        and count(guests[1], "RemoveObject", label(host, "player0_hover")) == 1,
        "the offline placeholder removal reaches the guests")
    -- Weather: events ride the ordered stream and only guests apply them.
    check(host.eu.init.authority and not guests[1].eu.init.authority, "only the leader runs the weather authority")
    check(host.eu.announces == 1 and #host.eu.events == 0, "the leader announces and never applies its own weather events")
    allGuests(guests, function(g)
        check(#g.eu.events == 1 and g.eu.events[1][1] == "EuropaState" and g.eu.events[1][2] == 4242,
            "the weather state event reaches each guest once through ApplyNetEvent")
        check(g.eu.announces == 0, "guests never announce")
        local onlyMapLabels = true
        for _, c in ipairs(g.calls) do
            if c[1] == "SetLabel" and c[3] ~= "apcamr20_camerapod" and c[3] ~= "player0_hover" then onlyMapLabels = false end
        end
        check(onlyMapLabels, "weather events never create label events")
    end)
    -- Unchanged world: no objective chatter and no new events.
    local updates = count(host, "UpdateObjective")
    run(10)
    eachPeer(function(p) check(count(p, "UpdateObjective") == updates, "objectives update only on change, on every peer") end)
    check(updates == 0, "no progress update before anything changes")
    -- A forged event from a guest or a stale replay changes nothing.
    local g = guests[2]
    local adds = count(g, "AddObjective")
    g.env.Receive(30, "E", 1, "AddObjective", 15, "forged.otf", "red")
    g.env.Receive(10, "E", 5000, "AddObjective", 15, "future.otf", "red")
    check(count(g, "AddObjective") == adds, "a forged or out-of-order event is not applied")
end

-- ------------------------------------------------ 2. progress updates, the win, and the acknowledged flush
do
    local host, guests = session(4)
    local silos = {"svsilo1", "svsilo2", "svsilo3"}
    for i, name in ipairs(silos) do
        kill(name); run(1)
        eachPeer(function(p)
            local text, color = lastText(p, "misn13_silos")
            check(text == "Destroy the CCA silos (" .. i .. "/4)" and color == "white",
                "silo progress " .. i .. "/4 reaches every peer")
        end)
    end
    eachPeer(function(p) check(count(p, "UpdateObjective", "misn13_silos") == 3, "exactly one update per silo on every peer") end)
    kill("svmuf"); run(1)
    eachPeer(function(p)
        local _, color = lastText(p, "misn13_factory")
        check(color == "green" and count(p, "UpdateObjective", "misn13_factory") == 1, "the factory objective completes once on every peer")
    end)
    -- Killing the factory shakes Europa once: quake and surge ride the stream, only guests apply them.
    check(#host.eu.quakes == 1 and host.eu.quakes[1][1] == 0.7 and #host.eu.surges == 1 and #host.eu.forces == 1
        and host.eu.forces[1][1] == 5, "the Unit Factory falling triggers the quake, surge and level-5 burst once")
    allGuests(guests, function(g)
        local quakes, surges = 0, 0
        for _, ev in ipairs(g.eu.events) do
            if ev[1] == "EuropaQuake" then quakes = quakes + 1; check(ev[2] == 0.7 and ev[3] == 5.0, "the quake arguments survive the wire") end
            if ev[1] == "EuropaSurge" then surges = surges + 1; check(ev[2] == 6.0 and ev[3] == 0.8, "the surge arguments survive the wire") end
        end
        check(quakes == 1 and surges == 1, "each guest applies the quake and the surge exactly once")
    end)
    check(#host.eu.events == 0, "the leader never feeds weather events back into ApplyNetEvent")
    kill("svguntower2"); run(1)
    eachPeer(function(p)
        local _, color = lastText(p, "misn13_hangar")
        check(color == "green", "the hangar objective completes on every peer")
        check(count(p, "SucceedMission") == 0, "no result before the last silo falls")
    end)
    -- Withhold one guest's acknowledgements: the result must wait for it.
    dropFn = function(packet) return packet.kind == "A" and packet.from == 30 end
    kill("svsilo4"); run(1)
    check(host.state.game_over and host.state.coopPendingResult ~= nil and not host.state.coopResult,
        "the win is decided and the result queued on the leader")
    run(20)
    eachPeer(function(p)
        check(count(p, "SucceedMission") == 0, "no peer gets the result while one guest has not acknowledged earlier events")
    end)
    check(host.state.coopPendingResult ~= nil, "the result stays pending on the leader")
    -- The silo progress and the misn1303 line did reach the guest whose acks were lost.
    check(count(peers[30], "Play", "misn1303.wav") == 1 and lastText(peers[30], "misn13_silos") == "Destroy the CCA silos (4/4)",
        "the silent guest still received every earlier event")
    dropFn = nil
    run(5)
    local times = {}
    eachPeer(function(p)
        check(count(p, "SucceedMission") == 1, "every peer gets exactly one SucceedMission once acknowledgements resume")
        local c = last(p, "SucceedMission")
        check(c[3] == "misn13w1.des", "the success description file reaches every peer")
        times[#times + 1] = c[2]
        check(count(p, "FailMission") == 0, "no failure alongside the victory")
        check(count(p, "Play", "misn1303.wav") == 1, "misn1303 plays exactly once on every peer")
        local playAt, resultAt = indexOf(p, "Play", "misn1303.wav"), indexOf(p, "SucceedMission")
        check(playAt < resultAt, "the victory line precedes the result on every peer")
    end)
    check(times[1] == times[2] and times[2] == times[3] and times[3] == times[4], "the result time is identical on every peer")
    check(host.state.coopResult and guests[1].state.coopResult and host.state.coopPendingResult == nil, "the result is latched everywhere")
    -- The sky eases back to calm on the leader only.
    check(host.eu.releases == 1 and host.eu.targets[#host.eu.targets] == 1, "victory releases the forced level and calms the leader sky")
    allGuests(guests, function(g) check(g.eu.releases == 0 and #g.eu.targets == 0, "guests never drive the director") end)
    -- Nothing more happens after the result.
    local total = count(host, "SucceedMission")
    run(20)
    eachPeer(function(p) check(count(p, "SucceedMission") == total, "the result is published once") end)
    check(sameStream(host, guests[1]) and sameStream(host, guests[3]), "the whole presentation stream matches the leader on every guest")
end

-- ------------------------------------------------ 3. a guest that leaves does not block the result
do
    local host, guests = session(4)
    for _, name in ipairs({"svsilo1", "svsilo2", "svsilo3", "svsilo4", "svmuf", "svguntower2"}) do kill(name) end
    dropFn = function(packet) return packet.kind == "A" and packet.from == 40 end
    run(1)
    check(host.state.game_over and host.state.coopPendingResult ~= nil, "the base is down and the result is pending")
    run(10)
    eachPeer(function(p) check(count(p, "SucceedMission") == 0, "the lost acknowledgements hold the result") end)
    local departing = peers[40]
    eachPeer(function(p) p.env.DeletePlayer(40, "P40", 4) end)
    peers[40] = nil
    run(3)
    for _, p in pairs(peers) do
        check(count(p, "SucceedMission") == 1 and last(p, "SucceedMission")[3] == "misn13w1.des",
            "the remaining peers get the result once the missing guest has left")
    end
    check(count(departing, "SucceedMission") == 0, "the departed guest never received the result")
end

-- ------------------------------------------------ 4. the defeat path
do
    local host, guests = session(3)
    kill("avrecycle"); run(1)
    check(host.state.game_over, "losing the Recycler ends the mission")
    run(4)
    eachPeer(function(p)
        check(count(p, "FailMission") == 1 and last(p, "FailMission")[3] == "misn13f1.des", "every peer receives one failure with misn13f1.des")
        check(count(p, "SucceedMission") == 0, "no victory on defeat")
        check(count(p, "Play", "misn1304.wav") == 1, "the defeat line plays once on every peer")
        check(indexOf(p, "Play", "misn1304.wav") < indexOf(p, "FailMission"), "the defeat line precedes the result")
        local text, color = lastText(p, "misn13_recycler")
        check(color == "red", "the Recycler objective turns red on every peer")
    end)
    local t = last(host, "FailMission")[2]
    allGuests(guests, function(g) check(last(g, "FailMission")[2] == t, "the failure time is identical") end)
    -- A later win cannot override the latched loss.
    for _, name in ipairs({"svsilo1", "svsilo2", "svsilo3", "svsilo4", "svmuf", "svguntower2"}) do kill(name) end
    run(5)
    eachPeer(function(p) check(count(p, "SucceedMission") == 0 and count(p, "FailMission") == 1, "the latched loss stands") end)
end

-- ------------------------------------------------ 5. the scavenger swap removes by label; guests do not wait on it
do
    local host, guests = session(4)
    world.scrap[5] = 39
    run(62)
    check(host.state.scav_swap, "the CCA scrap shortage starts the scavenger swap")
    for i = 1, 4 do
        local scav = world.labels["svscav" .. i]
        check(count(host, "RemoveObject", scav) == 1, "the leader removes svscav" .. i)
        allGuests(guests, function(g) check(count(g, "RemoveObject", scav) == 1, "svscav" .. i .. " removal reaches each guest once") end)
    end
    allGuests(guests, function(g)
        check(count(g, "BuildObject") == 0, "guests build no replacement scavengers")
        check(g.state.coopUnresolved == nil or g.state.coopUnresolved == 0, "the swap leaves nothing unresolved")
        check(sameStream(host, g), "the stream around the swap matches the leader")
    end)
    check(count(host, "BuildObject", "svscav") == 4, "the leader builds the four replacements")
end

print("misn13 presentation: " .. checks .. " checks passed")
