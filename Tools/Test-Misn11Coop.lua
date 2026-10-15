-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Run from the repository root: lua5.1 Tools/Test-Misn11Coop.lua
-- Executes the complete misn11 script in separate Lua 5.1 environments over the
-- real CRCoop registry and the E/A presentation transport. The engine, AI and combat
-- are mocks: they verify script decisions, not Redux native map loading, pathfinding,
-- Lua wire serialization or EXU hooks. The map coordinates below are the authored ones
-- (Missions/misn11.bzn). misn11 has no cameras and no IsInfo relay.
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

-- ---------------------------------------------------------------- world model
local now, objects, peers, nextObject, transport, dist, pathPos, world
local function terrain(x, z) return 20 end
local function P(x, z, y) return {x, y or 30, z} end
local LABELS = {
    avhaul0_tug = {odf = "avhaul", team = 1, pos = P(2209, 98833)},
    avhaul1_tug = {odf = "avhaul", team = 1, pos = P(2251, 98796)},
    avhaul2_tug = {odf = "avhaul", team = 1, pos = P(2251, 98746)},
    apcamr3_camerapod = {odf = "apcamr", team = 1, pos = P(1933, 99001)},
    apcamr4_camerapod = {odf = "apcamr", team = 1, pos = P(1985, 99834)},
    apcamr5_camerapod = {odf = "apcamr", team = 1, pos = P(2698, 100170)},
    svturr0_turrettank = {odf = "svturr", team = 5, pos = P(1988, 99168)},
    svturr1_turrettank = {odf = "svturr", team = 5, pos = P(1855, 99426)},
    svturr2_turrettank = {odf = "svturr", team = 5, pos = P(1617, 99017)},
    svturr3_turrettank = {odf = "svturr", team = 5, pos = P(1575, 98896)},
    second_blockade = {odf = "svturr", team = 5, pos = P(2280, 100021)},
    svwalk0_walker = {odf = "svwalk", team = 5, pos = P(2259, 99957)},
    svartl0_howitzer = {odf = "svartl", team = 5, pos = P(1325, 98830)},
    ["svartl0(1)_howitzer"] = {odf = "svartl", team = 5, pos = P(1423, 98751)},
    launch_pad = {odf = "ablpad", team = 1, pos = P(2743, 100284)},
    launch_pad2 = {odf = "ablpad", team = 1, pos = P(2977, 99264)},
    ["player-1_hover"] = {odf = "player", team = 1, pos = P(2196, 98819)},
}
local PATHS = {
    base1 = {2222, 30, 98863}, base2 = {2001, 30, 99869}, escape = {2823, 30, 100181}, openheimer = {1746, 30, 98968},
    strike1 = {1821, 30, 99639}, strike2 = {2481, 30, 100069}, check2 = {1946, 30, 99844},
    launch_attack = {2802, 30, 100201}, last_camera = {2965, 30, 99420},
}
local START = {2196, 30, 98819}
local function vec(t) return {x = t[1], y = t[2], z = t[3]} end
local FAR = 90000
local function newObject(handle, odf, team, pos)
    objects[handle] = {alive = true, odf = odf, team = team, health = 1, pos = vec(pos or {FAR, 20, FAR})}
    local o = objects[handle]
    if LABELS[handle] then o.label = handle end
    return o
end
local function reset()
    now, objects, peers, nextObject, dist = 0, {}, {}, 0, {}
    world = {cargo = {}, scrap = {}, net = false}
    pathPos = {}
    for name, p in pairs(PATHS) do pathPos[name] = vec(p) end
    transport = PeerTransport.New(function(packet)
        local peer = peers[packet.to]
        if peer then peer.env.Receive(packet.from, packet.kind, unpack(packet.args)) end
    end)
end
local function posOf(h)
    if type(h) == "table" then return h end
    if objects[h] then return objects[h].pos end
    return pathPos[h]
end
local function place(h, x, y, z) objects[h].pos = {x = x, y = y, z = z} end
local function at(h, p, dx, dz) place(h, p[1] + (dx or 0), p[2], p[3] + (dz or 0)) end

local function physics(dt)
    for h, o in pairs(objects) do
        if o.removeAt and now >= o.removeAt then o.alive = false end
    end
end

-- ----------------------------------------------------------------------- peers
local function count(peer, name, first)
    local n = 0
    for _, c in ipairs(peer.calls) do
        if c[1] == name and (first == nil or c[2] == first) then n = n + 1 end
    end
    return n
end
local function count2(peer, name, a, b)
    local n = 0
    for _, c in ipairs(peer.calls) do if c[1] == name and c[2] == a and c[3] == b then n = n + 1 end end
    return n
end
local function built(peer, odf)
    local n = 0
    for _, c in ipairs(peer.calls) do if c[1] == "BuildObject" and c[3] == odf then n = n + 1 end end
    return n
end
local function last(peer, name)
    for i = #peer.calls, 1, -1 do if peer.calls[i][1] == name then return peer.calls[i] end end
end
local function callsOf(peer, name)
    local out = {}
    for _, c in ipairs(peer.calls) do if c[1] == name then out[#out + 1] = c end end
    return out
end
-- Attack calls naming a target (any attacker); priority-1 only when `priority` is given.
local function attacksOn(peer, target, priority)
    local n = 0
    for _, c in ipairs(peer.calls) do
        if c[1] == "Attack" and c[3] == target and (priority == nil or c[4] == priority) then n = n + 1 end
    end
    return n
end

local function makePeer(id, team, network)
    local p = {id = id, team = team, net = network, hosting = team == 1, calls = {}, player = "player" .. id}
    p.io = {updates = 0, announces = 0, shutdowns = 0, targets = {}, forces = {}, releases = 0, quakes = {}, events = {}}
    peers[id] = p
    newObject(p.player, "avtank", team, {FAR + id, 20, FAR})
    local function record(name, ...) p.calls[#p.calls + 1] = {name, ...} end
    local e = setmetatable({}, {__index = _G})
    e._G = e
    e.print = function() end
    e.IsNetGame = function() return p.net end
    e.IsHosting = function() return p.hosting end
    e.GetTime = function() return now end
    e.GetPlayerHandle = function(remote)
        assert(remote == nil, "remote GetPlayerHandle(team) must never be used")
        return p.player
    end
    e.GetHandle = function(label)
        if not objects[label] then
            local spec = LABELS[label]
            if spec then newObject(label, spec.odf, spec.team, spec.pos) else newObject(label, "x", 0) end
        end
        return objects[label].alive and label or nil
    end
    e.GetLabel = function(h) return objects[h] and objects[h].label end
    e.IsValid = function(h) return type(h) == "string" and objects[h] ~= nil and objects[h].alive end
    e.IsAlive = e.IsValid
    e.IsOdf = function(h, odf) return e.IsValid(h) and objects[h].odf == odf end
    e.GetTeamNum = function(h) return objects[h] and objects[h].team or 0 end
    e.GetTug = function(h)
        local tug = world.cargo[h]
        if tug and objects[tug] and objects[tug].alive then return tug end
    end
    e.AddHealth = function(h, v) record("AddHealth", h, v) end
    e.GetPosition = function(h)
        local pos = posOf(h)
        return pos and {x = pos.x, y = pos.y, z = pos.z} or {x = 0, y = 0, z = 0}
    end
    e.SetVector = function(x, y, z) return {x = x or 0, y = y or 0, z = z or 0} end
    e.GetTerrainHeightAndNormal = function(pos) return terrain(pos.x, pos.z), {x = 0, y = 1, z = 0} end
    e.GetDistance = function(a, b)
        assert(e.IsValid(a), "invalid origin reached native distance query")
        -- This mock names handles with strings, which the DLL's guard reads as path names; a dead object
        -- named by a string is therefore answered "far" (the guard itself is proven with numeric handles
        -- in Test-Misn11.lua).
        if type(b) == "string" and objects[b] and not objects[b].alive then return 10000 end
        assert(type(b) == "string" and (objects[b] == nil or e.IsValid(b)) or e.IsValid(b), "invalid destination")
        local pa, pb = posOf(a), posOf(b)
        if pa and pb then
            local dx, dy, dz = pa.x - pb.x, pa.y - pb.y, pa.z - pb.z
            return math.sqrt(dx * dx + dy * dy + dz * dz)
        end
        return 10000
    end
    e.AllObjects = function()
        local list = {}
        for h, o in pairs(objects) do if o.alive then list[#list + 1] = h end end
        local i = 0
        return function() i = i + 1; return list[i] end
    end
    e.AllCraft = function()
        local key
        return function()
            key = next(objects, key)
            while key and not objects[key].alive do key = next(objects, key) end
            return key
        end
    end
    e.ObjectsInRange = function(distance, pos)
        local list = {}
        for h, o in pairs(objects) do
            local dx, dz = o.pos.x - pos.x, o.pos.z - pos.z
            if o.alive and math.sqrt(dx * dx + dz * dz) < distance then list[#list + 1] = h end
        end
        local i = 0
        return function() i = i + 1; return list[i] end
    end
    e.GetPilot = function() return 10 end
    e.GetMaxScrap = function() return 100 end
    e.GetMaxPilot = function() return 30 end
    e.SetMaxScrap = function() end
    e.SetMaxPilot = function() end
    e.IsPerson = function() return false end
    e.GetPositionNear = function(pos) return pos end
    e.GetVelocity = function() return {x = 0, y = 0, z = 0} end
    e.SetVelocity = function() end
    e.SetPosition = function(h, pos) objects[h].pos = pos end
    e.GetFront = function() return {x = 1, y = 0, z = 0} end
    e.SetTeamNum = function(h, t) objects[h].team = t end
    e.GetPerceivedTeam = function(h) return objects[h] and objects[h].team end
    e.SetPerceivedTeam = function() end
    e.GetHealth = function() return 1 end
    e.EjectPilot = function() end
    e.GetIn = function() end
    e.BuildObject = function(odf, objectTeam, where)
        nextObject = nextObject + 1
        local h = "built" .. nextObject
        local pos = posOf(where) or {x = FAR, y = 20, z = FAR}
        newObject(h, odf, objectTeam, {pos.x, pos.y, pos.z})
        record("BuildObject", h, odf, objectTeam, where)
        e.AddObject(h)
        return h
    end
    e.RemoveObject = function(h)
        record("RemoveObject", h)
        -- The world is shared by every mock peer: removal lands after all of them applied the event.
        if objects[h] then
            if world.net then objects[h].removeAt = objects[h].removeAt or (now + 3) else objects[h].alive = false end
        end
    end
    e.GetScrap = function(t) return world.scrap[t] or 0 end
    e.Send = function(to, kind, ...)
        record("Send", kind)
        local args = {...}
        for index = 1, select("#", ...) do
            -- A map-authored handle arrives as an invalid handle on a guest.
            if type(args[index]) == "string" and LABELS[args[index]] then args[index] = false end
        end
        local bytes = 4
        for _, value in ipairs(args) do bytes = bytes + (type(value) == "string" and #value + 2 or 9) end
        assert(bytes < 244, "mission packet exceeds stock payload budget: " .. kind)
        for target in pairs(peers) do
            if target ~= id and (to == 0 or to == nil or target == to) then transport:Send(id, target, kind, args, false) end
        end
    end
    for _, name in ipairs({"Follow", "Defend", "Stop", "Goto", "Attack", "SetIndependence", "SetAIP", "SetAIControl",
        "SetObjectiveName", "SetObjectiveOn", "SetObjectiveOff", "SetUserTarget", "ClearObjectives", "AddObjective", "UpdateObjective",
        "Ally", "UnAlly", "DisplayMessage", "FailMission", "SucceedMission", "SetScrap", "SetPilot",
        "Pickup"}) do
        local n = name
        e[n] = function(...)
            if n == "SetObjectiveOn" or n == "SetObjectiveName" then
                assert(e.IsValid((...)), "presentation used a not-yet-valid handle")
            end
            record(n, ...)
            if n == "SetScrap" then world.scrap[(...)] = select(2, ...) end
            if n == "Pickup" then objects[(...)].pickup = select(2, ...) end
        end
    end
    e.AiCommand = {FORMATION = 6}
    e.SetCommand = function(h, cmd, prio, who)
        if cmd == e.AiCommand.FORMATION then record("Formation", h, who, prio) else record("SetCommand", h, cmd, prio, who) end
    end
    local function noop() end
    local modules = {
        RequireFix = {Initialize = noop},
        -- The real director has its own suite (Test-CRIoWeather.lua); this records the mission's wiring:
        -- what it was initialised with, the beats, and the events it received. Quake behaves like the
        -- authority director: it queues IoQuake onto the mission's ordered stream.
        CRIoWeather = {
            Init = function(options) p.io.init = options end,
            Update = function() p.io.updates = p.io.updates + 1 end,
            Shutdown = function() p.io.shutdowns = p.io.shutdowns + 1 end, OnObjectCreated = noop,
            Save = function() return {saved = true} end, Load = function(state) p.io.loaded = state end,
            AnnounceState = function() p.io.announces = p.io.announces + 1 end,
            ApplyNetEvent = function(op, ...) p.io.events[#p.io.events + 1] = {op, ...}; return true end,
            SetTargetLevel = function(level) p.io.targets[#p.io.targets + 1] = level end,
            ForceLevel = function(level, seconds, transition) p.io.forces[#p.io.forces + 1] = {level, seconds, transition} end,
            ReleaseForcedLevel = function() p.io.releases = p.io.releases + 1 end,
            Quake = function(strength, seconds)
                p.io.quakes[#p.io.quakes + 1] = {strength, seconds}
                if p.io.init and p.io.init.send then p.io.init.send("IoQuake", strength, seconds) end
            end,
            Seed = 4242},
        CRIoSites11 = {mission = "misn11"}, Environment = {Init = noop, Update = noop, OnObjectCreated = noop},
        exu = {GetMyNetID = function() return id end, DisableStartingRecycler = function() record("DisableStartingRecycler") end,
            SetLives = function(n) record("SetLives", n) end},
        ScriptSubtitles = {
            Play = function(file) record("Play", file); return file end,
            Queue = function(file) record("Queue", file) end,
            Stop = function() record("Stop") end, Update = noop, Initialize = noop},
    }
    modules.CRCoopComms = assert(loadfile("Scripts/CRCoopComms.lua"))()
    local realRespawn = assert(loadfile("Scripts/CRCoopRespawn.lua"))()
    modules.CRCoopRespawn = {Create = function(d)
        local service = realRespawn.Create(d)
        local original = service.SetRallyPoints
        service.SetRallyPoints = function(points) p.rally = points; return original(points) end
        return service
    end}
    e.package = setmetatable({loaded = {exu = modules.exu}}, {__index = package})
    modules.CRCoop = setfenv(assert(loadfile("Scripts/CRCoop.lua")), e)()
    e.require = function(name) return assert(modules[name], name) end
    setfenv(assert(loadfile("Scripts/misn11.lua")), e)()
    p.chunkCalls = #p.calls -- everything recorded so far ran at chunk load, before Start
    p.env, p.coop = e, modules.CRCoop
    e.Start()
    p.state = e.Save()
    return p
end

local function tick(dt)
    dt = dt or 0.25
    now = now + dt
    physics(dt)
    for _, p in pairs(peers) do p.env.Update(dt) end
    transport:Step(now)
end
local function run(seconds, dt)
    dt = dt or 0.25
    for _ = 1, math.floor(seconds / dt + 0.5) do tick(dt) end
end
local function runTo(t, dt) run(t - now, dt) end
local function registerAll()
    for _, p in pairs(peers) do
        for id, other in pairs(peers) do p.env.CreatePlayer(id, "P" .. id, other.team) end
    end
end
local function session(network, humans)
    reset()
    world.net = network
    local host = makePeer(10, 1, network)
    local guests = {}
    for i = 2, (humans or 4) do guests[#guests + 1] = makePeer(10 * i, i, network) end
    registerAll()
    run(3)
    return host, guests
end
local function eachPeer(fn) for _, p in pairs(peers) do fn(p) end end
local function playedOnAll(file)
    local n = 0
    eachPeer(function(p) if count(p, "Play", file) == 1 then n = n + 1 end end)
    return n
end
local function onAll(fn) local n = 0; eachPeer(function(p) if fn(p) then n = n + 1 end end); return n end
local extra = 0
local function spawn(odf, team, x, z)
    extra = extra + 1
    local h = "extra" .. extra
    newObject(h, odf, team, {x or FAR, 20, z or FAR})
    return h
end
local function builtAt(peer, odf, where)
    local n = 0
    for _, c in ipairs(peer.calls) do
        if c[1] == "BuildObject" and c[3] == odf and c[5] == where then n = n + 1 end
    end
    return n
end
local function builtAtVector(peer, odf)
    local n = 0
    for _, c in ipairs(peer.calls) do
        if c[1] == "BuildObject" and c[3] == odf and type(c[5]) == "table" then n = n + 1 end
    end
    return n
end
local function gotosTo(peer, unit, path)
    local n = 0
    for _, c in ipairs(peer.calls) do if c[1] == "Goto" and c[2] == unit and c[3] == path then n = n + 1 end end
    return n
end
local function noSendCrashes() end
local TUG1, TUG2, OPENH = "avhaul0_tug", "avhaul1_tug", "avhaul2_tug"
local CAM1, CAM2, CAM3 = "apcamr3_camerapod", "apcamr4_camerapod", "apcamr5_camerapod"
local LAUNCH, LAUNCH2 = "launch_pad", "launch_pad2"
local function setAt(h, x, z) place(h, x, 30, z) end
-- Run to the moment the convoy departs.
local function depart(host)
    run(16)
    check(host.state.start_delay == 99999, "the convoy has departed")
end
-- Put the defecting tug on the road; the backup squad is called on the approach, the tug breaks off at
-- Waypoint 1 and defects fifteen seconds later.
local function approachWaypoint(host)
    setAt(OPENH, 2100, 98892)
    run(1)
end
local function defect(host)
    setAt(OPENH, 1940, 99005)
    run(1)
    run(16)
end

-- ============================================================ 1. startup, ownership, rally, weather wiring
do
    local host, guests = session(true)
    local s = host.state
    check(s.start_done and s.tug1 == TUG1 and s.openh == OPENH and s.cam3 == CAM3 and s.launch2 == LAUNCH2,
        "the leader starts the mission body on the authored labels")
    check(s.picket1 == "svturr0_turrettank" and s.walker == "svwalk0_walker" and s.art1 == "svartl0_howitzer"
        and s.art2 == "svartl0(1)_howitzer", "the ambush units resolve by label")
    for _, g in ipairs(guests) do
        check(not g.state.start_done and count(g, "BuildObject") == 0, "guests never run the mission body")
    end
    eachPeer(function(p)
        check(count(p, "DisableStartingRecycler") == 1, "every peer disables the extra starting recycler")
        check(count(p, "SetAIControl") == 0 and count(p, "SetAIP") == 0, "the CCA is script-driven: no strategic AI on any peer")
        check(p.rally and p.rally[0] == "base1" and p.rally[1] == TUG1, "respawn rally is the start, then the lead tug")
        check(count(p, "Play", "misn1101.wav") == 1, "the briefing plays on every peer once")
        check(count(p, "AddObjective", "misn1101.otf") == 1, "the objective reaches every peer once")
        check(p.state.coopUnresolved == nil or p.state.coopUnresolved == 0, "no unresolved marker")
    end)
    check(count(host, "SetScrap", 1) == 1 and world.scrap[1] == 50, "the host base scrap is set once")
    for _, g in ipairs(guests) do
        check(count(g, "SetScrap") == 0 and count(g, "SetPilot") == 0, "guests configure nothing")
        check(count(g, "SetObjectiveName") == 6, "all three waypoint names and three transport names reach guests")
    end
    check(count(host, "RemoveObject", "player-1_hover") == 1, "the offline placeholder is removed in a network game")
    check(host.io.init.authority and host.io.init.sites.mission == "misn11", "the leader runs the weather director on the misn11 sites")
    for _, g in ipairs(guests) do check(not g.io.init.authority, "guests run the director from the host's events") end
    check(host.io.announces == 1 and count(host, "Send") > 0, "the leader announces the weather state")
    check(host.io.targets[1] == 2, "weather steps to level 2 at the start")
    check(count(host, "Ally") >= 4, "alliances configured")
end

-- ============================================================ 2. CCA scaling at 1-4 players, every wave
for humans = 1, 4 do
    local host, guests = session(true, humans)
    local s = host.state
    local more = math.min(3, humans - 1)
    depart(host)
    eachPeer(function(p)
        check(p.coop.GetMissionPhase() == 1, humans .. " players: the rally phase moves with the convoy on every peer")
    end)
    -- A guest craft and an ally of the host: neither is ever retasked by a strike scan.
    local guestFighter = spawn("svfigh", 2, FAR, FAR)
    local allyFighter = spawn("svfigh", 1, FAR, FAR)
    approachWaypoint(host)
    check(s.backup_called and #s.backup == 3 + more, humans .. " players: " .. (3 + more) .. " backup units")
    check(builtAtVector(host, "svtank") == 2 and builtAtVector(host, "svfigh") == 1 + more,
        humans .. " players: 2 svtank + " .. (1 + more) .. " svfigh in the backup squad")
    for _, unit in ipairs(s.backup) do
        check(objects[unit].team == 5, "the backup squad is CCA team 5")
        check(gotosTo(host, unit, "svartl0_howitzer") == 1, "each squad unit is ordered to the outpost artillery before the defection")
    end
    defect(host)
    check(s.betrayal_message and objects[OPENH].team == 5, humans .. " players: the tug defects to team 5")
    check(builtAt(host, "svfigh", "strike1") == 1 + more, humans .. " players: " .. (1 + more) .. " svfigh in the first strike")
    check(gotosTo(host, guestFighter, "strike_path1") == 0 and gotosTo(host, allyFighter, "strike_path1") == 0,
        "a guest's or ally's fighter is never retasked by the strike scan")
    for _, unit in ipairs(s.backup) do
        if objects[unit].odf == "svfigh" then check(gotosTo(host, unit, "strike_path1") == 0, "the squad is not retasked either") end
    end
    -- Second strike at check2.
    place(TUG1, 1946, 30, 99844)
    run(1)
    check(s.check2 and builtAt(host, "svfigh", "strike2") == 1 + more, humans .. " players: second strike scaled")
    -- The blockade turret AND the walker must die before the convoy restarts.
    objects.second_blockade.alive = false
    run(1)
    check(not s.restart, "the walker keeps the convoy halted")
    objects.svwalk0_walker.alive = false
    run(1)
    check(s.restart, "convoy released once blockade and walker are dead")
    -- Pad ambush when any human nears the pad.
    local runner = guests[1] or host
    setAt(runner.player, 2743, 99900)
    run(1)
    check(s.launch_attack and builtAt(host, "svtank", "launch_attack") == 2 + more,
        humans .. " players: " .. (2 + more) .. " tanks in the pad ambush")
    check(s.tank1 and s.tank2, "the DLL's two ambush tanks keep their slots")
    objects[LAUNCH].alive = false
    run(1)
    check(s.launch_gone, "pad loss")
    run(41)
    place(TUG2, 2698, 30, 100170)
    run(1)
    check(s.escape_start, "the convoy reaches the old pad")
    run(16)
    check(s.last_wave, "final wave built")
    local finalWave = builtAt(host, "svfigh", "strike2") - (1 + more)
    check(finalWave == 2 + more, humans .. " players: final wave is 2 + " .. more .. " svfigh")
    check(builtAt(host, "svfigh", LAUNCH2) == 1, "one late fighter at launch pad 2")
    for _, g in ipairs(guests) do
        check(count(g, "BuildObject") == 0, "guests never spawn")
    end
    for _, c in ipairs(callsOf(host, "BuildObject")) do
        if c[3]:find("^sv") then check(c[4] == 5, c[3] .. " must be CCA team 5") end
    end
end

-- ============================================================ 3. any-player triggers and the presentation relays
do
    local host, guests = session(true, 3)
    local s = host.state
    depart(host)
    local guest = guests[1]
    -- Waypoint 1 advances when a GUEST reaches it (the DLL tested the one local player).
    setAt(guest.player, 1933, 99001 + 10)
    run(1)
    check(s.check1, "a guest at Waypoint 1 advances the first checkpoint")
    eachPeer(function(p) check(count(p, "SetUserTarget", CAM2) == 1, "the new target nav reaches every peer") end)
    setAt(guest.player, FAR, FAR)
    -- The pad ambush starts when a guest nears the pad, not only the host or the tug.
    place(TUG1, 1946, 30, 99844); run(1)
    objects.second_blockade.alive = false; objects.svwalk0_walker.alive = false; run(1)
    check(s.restart, "convoy restarted")
    setAt(guests[2].player, 2743, 100284 - 449)
    run(1)
    check(s.launch_attack, "a guest within 450 m of the pad starts the ambush")
    eachPeer(function(p) check(count(p, "Play", "misn1108.wav") == 1, "the ambush warning plays on every peer once") end)
    -- Markers use labels: the pad objective is delivered to guests without unresolved handles.
    objects[LAUNCH].alive = false
    run(45)
    eachPeer(function(p)
        check(count(p, "SetObjectiveOn", LAUNCH2) == 1 and count(p, "SetObjectiveName", LAUNCH2) == 1,
            "the second pad is marked on every peer")
        check(count(p, "Play", "misn1109.wav") == 1 and count(p, "Play", "misn1110.wav") == 1, "the pad dialogue reaches everyone")
        check((p.state.coopUnresolved or 0) == 0, "no marker was left unresolved")
    end)
    check(host.io.forces[1] and host.io.forces[1][1] == 5 and #host.io.quakes == 1,
        "the pad loss triggers the level-5 burst and one quake")
    for _, g in ipairs(guests) do
        local quakes = 0
        for _, e in ipairs(g.io.events) do if e[1] == "IoQuake" then quakes = quakes + 1 end end
        check(quakes == 1, "the quake reaches every guest exactly once")
    end
end

-- ============================================================ 4. the betrayal: squad, chasers, misn1114 / misn1115
do
    local host, guests = session(true, 3)
    local s = host.state
    depart(host)
    approachWaypoint(host)
    check(s.backup_called, "the squad is called on the approach, before the defection")
    check(not s.betrayal, "...while the tug is still loyal")
    for _, unit in ipairs(s.backup) do
        check(count2(host, "Formation", unit, OPENH) == 0, "no formation order before the defection")
        check(math.abs(objects[unit].pos.x - 906) < 100, "the squad enters at the far end of the openheimer path")
    end
    defect(host)
    local g1, g2 = guests[1], guests[2]
    eachPeer(function(p)
        check(count(p, "Play", "misn1103.wav") == 1 and count(p, "Play", "misn1104.wav") == 1
            and count(p, "Play", "misn1105.wav") == 1, "the defection dialogue plays on every peer once")
    end)
    run(1)
    for _, unit in ipairs(s.backup) do
        check(count2(host, "Formation", unit, OPENH) == 1, "every squad unit forms up on the defecting tug")
    end
    check(count(host, "Defend", "svturr2_turrettank") == 1 and count(host, "Defend", "svturr3_turrettank") == 1, "turrets released")
    -- Nobody chases: no engagement orders against humans.
    check(attacksOn(host, g1.player) == 0 and attacksOn(host, host.player) == 0, "an idle squad attacks nobody")
    -- A guest chases within 350 m: the whole squad engages it; a second chaser nearer pulls them over.
    setAt(OPENH, 1500, 98850)
    setAt(g1.player, 1500 + 340, 98850)
    run(3)
    for _, unit in ipairs(s.backup) do
        check(s.squad_order[unit] == g1.player, "the squad engages the chasing guest")
    end
    check(attacksOn(host, g1.player, 1) >= #s.backup, "with priority-1 attack orders")
    setAt(g2.player, 1500 + 100, 98850)
    run(3)
    for _, unit in ipairs(s.backup) do check(s.squad_order[unit] == g2.player, "and switches to the nearest chaser") end
    -- Collins: once, on every peer, when a human nears the defector.
    eachPeer(function(p) check(count(p, "Play", "misn1114.wav") == 1, "misn1114 plays once on every peer") end)
    eachPeer(function(p) check(count(p, "Play", "misn1115.wav") == 0, "misn1115 waits for the break") end)
    -- Breaking contact: everyone pulls beyond 700 m for 8 s.
    setAt(g1.player, FAR, FAR); setAt(g2.player, FAR, FAR); setAt(host.player, FAR, FAR)
    run(7)
    eachPeer(function(p) check(count(p, "Play", "misn1115.wav") == 0, "misn1115 needs the 8 s hold") end)
    run(8)
    eachPeer(function(p) check(count(p, "Play", "misn1115.wav") == 1, "Corbett logs the intel once on every peer") end)
    for _, unit in ipairs(s.backup) do check(count2(host, "Formation", unit, OPENH) >= 2, "the squad returns to formation") end
    run(30)
    eachPeer(function(p)
        check(count(p, "Play", "misn1114.wav") == 1 and count(p, "Play", "misn1115.wav") == 1, "both lines play only once")
        check(count(p, "Play", "misn1106.wav") == 1, "the stock caution plays once")
    end)
    check(host.io.targets[#host.io.targets] >= 3, "weather steps up on the betrayal")
end

-- ============================================================ 5. the ambush: pickets, walker, artillery
do
    local host, guests = session(true, 2)
    local s = host.state
    depart(host)
    check(attacksOn(host, TUG1) == 0, "idle CCA units stay idle until triggered")
    local guest = guests[1]
    setAt(guest.player, 1855, 99426 + 300)
    run(4)
    check(attacksOn(host, guest.player, 1) >= 1 and s.woken["svturr1_turrettank"], "a guest near a picket wakes it, and it hunts the guest")
    check(not s.woken["svturr0_turrettank"], "the other picket stays idle")
    setAt(guest.player, FAR, FAR)
    place(TUG1, 1988 + 300, 30, 99168)
    run(4)
    check(s.woken["svturr0_turrettank"], "the convoy wakes the other picket")
    check(attacksOn(host, TUG1) >= 1, "the picket hunts the convoy tug")
    local function ordersFrom(unit)
        local n = 0
        for _, c in ipairs(host.calls) do if c[1] == "Attack" and c[2] == unit then n = n + 1 end end
        return n
    end
    check(ordersFrom("svwalk0_walker") == 0, "the walker idles before the convoy halts")
    place(TUG1, 1946, 30, 99844); run(4)
    check(s.check2 and ordersFrom("svwalk0_walker") >= 1, "the walker advances once the convoy halts at check2")
    check(ordersFrom("svartl0_howitzer") == 0 and ordersFrom("svartl0(1)_howitzer") == 0, "the artillery holds before the defection")
    s.betrayal_message = true
    setAt(guest.player, 1325 + 300, 98830)
    run(4)
    check(count2(host, "Attack", "svartl0_howitzer", guest.player) == 1 and count2(host, "Attack", "svartl0(1)_howitzer", guest.player) == 1,
        "the artillery shells a human within 650 m after the defection")
    for _, g in ipairs(guests) do check(count(g, "Attack") == 0, "guests issue no orders") end
end

-- ============================================================ 6. the win needs every human at launch pad 2
local function lateGame(host)
    local s = host.state
    s.last_wave = true; s.launch_gone = true; s.launch_attack = true; s.betrayal = true; s.betrayal_message = true
    s.pursuit_warning = true; s.restart = true; s.check1 = true; s.check2 = true; s.start_delay = 99999
    s.backup_called = true; s.warned_massive = true; s.intel_logged = true
    return s
end
do
    local host, guests = session(true, 4)
    local s = lateGame(host)
    setAt(TUG1, 2977, 99264); setAt(TUG2, 2977, 99264 + 50)
    run(2)
    check(not s.won, "no win before any human arrives")
    local all = { host, guests[1], guests[2], guests[3] }
    for i = 1, 3 do
        setAt(all[i].player, 2977, 99264 + 100)
        run(1)
        check(not s.won, i .. " of 4 humans at launch pad 2 is not enough")
    end
    setAt(all[1].player, FAR, FAR)   -- one of them has left again: arrival stays latched
    setAt(all[4].player, 2977, 99264 + 150)
    run(2)
    check(s.won and s.got_there1 and s.got_there2 and s.got_there3, "all four humans have arrived (latched) with both tugs: the win")
    run(30)
    local times = {}
    eachPeer(function(p)
        check(count(p, "SucceedMission") == 1 and last(p, "SucceedMission")[3] == "misn11w1.des", "the win reaches every peer once")
        check(count(p, "Play", "misn1113.wav") == 1, "the win line plays once on every peer")
        times[#times + 1] = last(p, "SucceedMission")[2]
        check(count(p, "FailMission") == 0, "and never fails")
    end)
    for _, t in ipairs(times) do check(math.abs(t - times[1]) < 0.01, "the result lands at one time on every peer") end
    check(host.io.releases >= 1 and host.io.targets[#host.io.targets] == 1, "calm on the win")
end
do
    -- A player who left the session is not waited for.
    local host, guests = session(true, 3)
    local s = lateGame(host)
    setAt(TUG1, 2977, 99264); setAt(TUG2, 2977, 99264 + 50)
    setAt(host.player, 2977, 99264 + 100); setAt(guests[1].player, 2977, 99264 + 100)
    run(2)
    check(not s.won, "the third human has not arrived")
    local leaver = guests[2]
    eachPeer(function(p) p.env.DeletePlayer(leaver.id, "P" .. leaver.id, leaver.team) end)
    peers[leaver.id] = nil
    run(2)
    check(s.won, "a departed player no longer blocks the win")
end

-- ============================================================ 7. failure belongs to the host
do
    local host, guests = session(true, 4)
    depart(host)
    objects[TUG2].alive = false
    run(26)
    eachPeer(function(p)
        check(count(p, "FailMission") == 1 and last(p, "FailMission")[3] == "misn11l1.des", "a lost transport fails every peer once")
        check(count(p, "Play", "misn1111.wav") == 1 and count(p, "Play", "misn1112.wav") == 1, "the loss dialogue plays once")
        check(count(p, "SucceedMission") == 0, "and never wins")
    end)
end
do
    -- Oppenheimer dying after the defection does not fail the mission.
    local host, guests = session(true, 2)
    depart(host); approachWaypoint(host); defect(host)
    objects[OPENH].alive = false
    run(25)
    eachPeer(function(p) check(count(p, "FailMission") == 0, "the defector's death is not a failure") end)
end
do
    -- ...but before the defection it is.
    local host, guests = session(true, 2)
    depart(host)
    objects[OPENH].alive = false
    run(25)
    eachPeer(function(p) check(count(p, "FailMission") == 1, "Oppenheimer's death before the defection fails the mission") end)
end
do
    -- The rally drops once the lead tug is gone.
    local host, guests = session(true, 3)
    depart(host)
    eachPeer(function(p) check(p.rally[1] == TUG1, "rally on the lead tug") end)
    objects[TUG1].alive = false
    run(1)
    eachPeer(function(p) check(next(p.rally) == nil, "no rally at a corpse") end)
end

-- ============================================================ 8. the host leaves
do
    local host, guests = session(true, 4)
    for _, g in ipairs(guests) do g.env.DeletePlayer(10, "P10", 1) end
    peers[10] = nil
    local gone = now
    run(3)
    for _, g in ipairs(guests) do
        check(count(g, "FailMission") == 1, "a guest fails once when the leader leaves")
        local c = last(g, "FailMission")
        check(c[2] > gone and c[2] <= gone + 1.5, "one second after the departure")
    end
    run(20)
    for _, g in ipairs(guests) do check(count(g, "FailMission") == 1, "and only once") end
end

-- ============================================================ 9. offline smoke
do
    local host = session(false, 1)
    local s = host.state
    run(5)
    check(count(host, "Send") == 0, "offline play sends nothing")
    check(count(host, "SetAIControl") == 0 and count(host, "SetAIP") == 0, "offline: no strategic AI either")
    check(host.rally[0] == "base1" and count(host, "Play", "misn1101.wav") == 1, "offline dialogue and rally")
    check(count(host, "RemoveObject", "player-1_hover") == 0 and count(host, "DisableStartingRecycler") == 0, "offline: no placeholder removal")
    check(host.io.init.authority and host.io.init.send == nil and host.io.announces == 0, "offline weather is the host path with nothing sent")
    depart(host)
    approachWaypoint(host)
    check(#s.backup == 3, "offline: the three-unit backup squad")
    lateGame(host)
    setAt(TUG1, 2977, 99264); setAt(TUG2, 2977, 99264 + 50); setAt(host.player, 2977, 99264 + 120)
    run(2)
    check(count(host, "SucceedMission") == 1 and last(host, "SucceedMission")[3] == "misn11w1.des", "offline: the win is a direct pass-through")
    check(count(host, "Send") == 0, "offline: still nothing on the wire")
end

print("misn11 co-op: " .. checks .. " multi-peer Lua 5.1 mock-engine checks passed")
