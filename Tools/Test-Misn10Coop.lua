-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Run from the repository root: lua5.1 Tools/Test-Misn10Coop.lua
-- Executes the complete misn10 script in separate Lua 5.1 environments over the
-- real CRCoop registry and the E/A presentation transport. The engine, AI and combat
-- are mocks: they verify script decisions, not Redux native map loading, pathfinding,
-- Lua wire serialization or EXU hooks. The map coordinates below keep the authored
-- geometry's relationships (geyser1 nearest the relic, CCA base far from Utah) but are
-- not read from Missions/misn10.bzn. misn10 has no cameras and no IsInfo relay.
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

-- ---------------------------------------------------------------- world model
local now, objects, peers, nextObject, transport, dist, pathPos, world
local function terrain(x, z) return 20 end
local UTAH, RELIC, GEYSER1 = {1000, 20, 1000}, {3000, 20, 3000}, {3050, 20, 3000}
local LABELS = {
    avrecycler = {odf = "avrecy", team = 1, pos = UTAH},
    relic = {odf = "hvsrb", team = 0, pos = RELIC},
    cam1 = {odf = "apcamr", team = 1, pos = {3000, 20, 2900}},
    cam2 = {odf = "apcamr", team = 1, pos = {5000, 20, 4900}},
    cam3 = {odf = "apcamr", team = 1, pos = {1100, 20, 1000}},
    svrecycler = {odf = "svrecy", team = 5, pos = {5000, 20, 5000}},
    svmuf = {odf = "svmuf", team = 5, pos = {5040, 20, 5000}},
    svartil1 = {odf = "svartl", team = 5, pos = {4000, 20, 4500}},
    svartil2 = {odf = "svartl", team = 5, pos = {4100, 20, 4500}},
    post1_geyser = {odf = "eggeizr1", team = 0, pos = {4500, 20, 4000}},
    post3_geyser = {odf = "eggeizr1", team = 0, pos = {4600, 20, 4100}},
    geyser1 = {odf = "eggeizr1", team = 0, pos = GEYSER1},
    geyser2 = {odf = "eggeizr1", team = 0, pos = {3000, 20, 3600}},
    geyser3 = {odf = "eggeizr1", team = 0, pos = {3700, 20, 3000}},
    geyser4 = {odf = "eggeizr1", team = 0, pos = {2300, 20, 3000}},
    geyser5 = {odf = "eggeizr1", team = 0, pos = {3000, 20, 2300}},
    geyser6 = {odf = "eggeizr1", team = 0, pos = {3800, 20, 3800}},
    geyser7 = {odf = "eggeizr1", team = 0, pos = {2200, 20, 2200}},
    player0_hover = {odf = "player", team = 1, pos = {1010, 20, 1000}},
}
local PATHS = {
    relic_path1 = {3500, 20, 3500}, attack_path_central = {3500, 20, 3000}, attack_path_south = {3000, 20, 2500},
    attack_path_north = {3500, 20, 4000}, artil1_path = {4500, 20, 4000}, artil2_path = {4600, 20, 4100},
    main_return_path = {2000, 20, 2000}, lsouth_return_path = {2500, 20, 1500}, ssouth_return_path = {2000, 20, 1500},
    msouth_return_path = {1500, 20, 1500},
}
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

-- The only physics: a Pickup order puts the relic on the tug on the next frame.
local function physics(dt)
    for h, o in pairs(objects) do
        if o.removeAt and now >= o.removeAt then o.alive = false end
        if o.alive and o.pickup and objects[o.pickup] and objects[o.pickup].alive then
            world.cargo[o.pickup] = h
            o.pickup = nil
        end
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
        for i = 1, select("#", ...) do local v = select(i, ...); assert(type(v) ~= "string" or #v <= 127, "Send string over 127 bytes on " .. tostring(kind)) end
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
        "SetObjectiveName", "SetObjectiveOn", "SetObjectiveOff", "ClearObjectives", "AddObjective", "UpdateObjective",
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
        CRIoSites10 = {mission = "misn10"}, Environment = {Init = noop, BindWeatherSensors = function(name, director)
            check(name == "Io" and type(director) == "table", "mission binds its weather director to shared sensors")
            p.sensorBinding = name
        end, Update = noop, OnObjectCreated = noop},
        exu = {GetMyNetID = function() return id end, DisableStartingRecycler = function() record("DisableStartingRecycler") end,
            SetLives = function(n) record("SetLives", n) end},
        ScriptSubtitles = {
            Play = function(file) record("Play", file); return file end,
            Queue = function(file) record("Queue", file) end,
            Stop = function() record("Stop") end, Update = noop, Initialize = noop},
    }
    modules.CRCoopComms = assert(loadfile("Scripts/CRCoopComms.lua"))()
    modules.CRWire = assert(loadfile("Scripts/CRWire.lua"))()
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
    setfenv(assert(loadfile("Scripts/misn10.lua")), e)()
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
-- A unit built by the CCA's AIP: it reaches the mission through AddObject on the leader.
local function aip(host, odf, x, z)
    local h = spawn(odf, 5, x, z)
    host.env.AddObject(h)
    return h
end
local function carry(s, tug) world.cargo[s.sav] = tug end
local function allCCA(host)
    for _, c in ipairs(callsOf(host, "BuildObject")) do
        if c[3]:find("^sv") then check(c[4] == 5, c[3] .. " must be CCA team 5") end
    end
end
-- The CCA's standing army as the AIP would leave it.
local function army(host)
    return {fighter1 = aip(host, "svfigh"), fighter2 = aip(host, "svfigh"), tank1 = aip(host, "svltnk"),
        tank2 = aip(host, "svltnk"), artil3 = aip(host, "svartl")}
end

-- ============================================================ 1. startup, ownership, rally
do
    local host, guests = session(true)
    local s = host.state
    check(s.start_done and s.sav == "relic" and s.ccarecycle == "svrecycler" and s.nsdfrecycle == "avrecycler",
        "the leader starts the mission body")
    check(s.ccamuf == "svmuf" and s.geys1 == "geyser1" and s.geys7 == "geyser7" and s.post1_geyser == "post1_geyser"
        and s.post3_geyser == "post3_geyser", "the authored labels resolve")
    for _, g in ipairs(guests) do
        check(not g.state.start_done and count(g, "BuildObject") == 0, "guests never run the mission body")
    end
    eachPeer(function(p)
        check(count(p, "DisableStartingRecycler") == 1, "every peer disables the extra starting recycler")
        check(count(p, "SetAIControl", 5) == 1 and last(p, "SetAIControl")[3] == true,
            "strategic AI is configured for the CCA team exactly once on every peer")
        local first
        for i, c in ipairs(p.calls) do if c[1] == "SetAIControl" then first = i; break end end
        check(first and first <= p.chunkCalls, "SetAIControl runs at chunk load, before Start")
        check(count(p, "SetAIControl") == 1, "and never from Start or Update")
        check(p.rally and p.rally[0] == "avrecycler", "respawn rally is Utah (avrecycler)")
    end)
    check(count(host, "SetScrap", 1) == 1 and world.scrap[1] == 30 and count(host, "SetPilot", 1) == 1,
        "the host team's resources are set once")
    for _, g in ipairs(guests) do
        check(count(g, "SetScrap") == 0 and count(g, "SetPilot") == 0 and count(g, "SetAIP") == 0,
            "guests configure nothing")
    end
    check(count2(host, "SetAIP", "misn10.aip", 5) == 1 and count(host, "SetAIP") == 1, "the CCA starts on misn10.aip")
    check(count(host, "SetScrap", 2) == 0 and count(host, "SetPilot", 2) == 0, "nothing is configured on guest team 2")
    check(count(host, "Ally") >= 12 and count(host, "UnAlly") >= 8, "alliances configured")
    -- Utah is lost: the rally drops everywhere before the result lands, then every peer fails once.
    objects.avrecycler.alive = false
    run(1)
    eachPeer(function(p) check(p.rally and next(p.rally) == nil, "the rally point is dropped once Utah is gone") end)
    run(25)
    eachPeer(function(p)
        check(count(p, "FailMission") == 1 and last(p, "FailMission")[3] == "misn10f3.des",
            "losing Utah fails every peer once")
        check(count(p, "SucceedMission") == 0, "and never wins")
    end)
    check(playedOnAll("misn1004.wav") == 4, "the Utah-lost line reaches everyone")
end

-- ============================================================ 2. CCA scaling at 1-4 players
for humans = 1, 4 do
    local host, guests = session(true, humans)
    local s = host.state
    local more = humans - 1
    check(world.scrap[5] == 40 + 10 * more, humans .. " players: CCA scrap " .. (40 + 10 * more))
    check(count(host, "SetScrap", 5) == (more == 0 and 1 or 2), humans .. " players: scrap set once (twice when scaled)")
    check(count(host, "SetPilot", 5) == 1 and last(host, "SetPilot")[3] == 40, humans .. " players: CCA pilots stay 40")
    check(built(host, "svfigh") == more and #s.hunters == more, humans .. " players: " .. more .. " hunters")
    check(s.ccafighter1 == nil and s.ccafighter2 == nil, "hunters never occupy the AIP fighter slots")
    for _, h in ipairs(s.hunters) do
        check(objects[h].team == 5 and objects[h].odf == "svfigh", "hunters are CCA fighters")
        check(count(host, "Defend", h) == 1 and count(host, "Follow", h) == 0, "hunters hold the base")
    end
    local a, b = aip(host, "svfigh"), aip(host, "svfigh")
    check(s.ccafighter1 == a and s.ccafighter2 == b, "the AIP's own fighters fill the slots")
    for _, g in ipairs(guests) do
        check(count(g, "BuildObject") == 0 and count(g, "SetScrap") == 0, "guests never spawn or fund the CCA")
    end
    allCCA(host)
    -- plan B restocks with the scaled scrap, once, on the leader only
    world.scrap[5] = 3
    local tug, t1, t2 = aip(host, "svhaul"), aip(host, "svltnk"), aip(host, "svltnk")
    run(1)
    check(s.plan_b and count2(host, "SetAIP", "misn10b.aip", 5) == 1, humans .. " players: plan B loads")
    check(world.scrap[5] == 40 + 10 * more, humans .. " players: plan B restocks the scaled scrap")
    for _, g in ipairs(guests) do check(count(g, "SetAIP") == 0, "guests never load an AIP") end
end

-- ============================================================ 3. any-human relic carrier
for team = 1, 4 do
    local host, guests = session(true, 4)
    local s = host.state
    local units = army(host)
    local tug = spawn("avhaul", team)
    carry(s, tug)
    run(1)
    check(s.sav_secure and not s.sav_seized and s.tugger == tug and s.chase_tug, "a team " .. team .. " tug secures the relic")
    for _, key in ipairs({"fighter1", "fighter2", "tank1", "tank2", "artil3"}) do
        check(count2(host, "Attack", units[key], tug) == 1 and attacksOn(host, tug, 1) >= 5,
            "team " .. team .. ": " .. key .. " chases the carrier at priority 1")
    end
    check(attacksOn(host, tug) > 0, "the map artillery joins the chase")
    for _, u in ipairs({"svartil1", "svartil2"}) do
        local n = 0
        for _, c in ipairs(host.calls) do if c[1] == "Attack" and c[2] == u and c[3] == tug and c[4] == 1 then n = n + 1 end end
        check(n >= 1, u .. " shells the carrier")
    end
    for _, hunter in ipairs(s.hunters) do
        check(count2(host, "Attack", hunter, tug) == 1, "every hunter joins the chase once")
    end
    local total = attacksOn(host, tug)
    run(10)
    check(attacksOn(host, tug) == total, "the chase is issued once")
    for _, g in ipairs(guests) do check(count(g, "Attack") == 0, "guests command nothing") end
    -- the carrier dies: the relic is free again, and the next carrier is chased in turn
    objects[tug].alive = false
    run(1)
    check(s.sav_free and not s.sav_secure and not s.chase_tug, "a dead carrier frees the relic")
    local tug2 = spawn("avhaul", 5 - team)
    carry(s, tug2)
    run(1)
    check(s.sav_secure and s.chase_tug and count2(host, "Attack", units.fighter1, tug2) == 1, "the next carrier is chased once too")
end
do
    -- a CCA tug seizes the relic and is never chased
    local host, guests = session(true, 3)
    local s = host.state
    local units = army(host)
    local ccatug = aip(host, "svhaul")
    check(s.ccatug == ccatug, "the AIP tug fills the tug slot")
    carry(s, ccatug)
    run(1)
    check(s.sav_seized and not s.sav_secure and s.tugger == ccatug and not s.chase_tug, "a CCA tug seizes the relic")
    check(attacksOn(host, ccatug) == 0, "the CCA never attacks its own carrier")
    check(playedOnAll("misn1005.wav") == 3, "the seized warning reaches everyone")
    -- delivery: relic within 100 m of the CCA recycler
    at("relic", {5000, 20, 5000}, 100, 0)
    run(2)
    check(not s.game_over, "100 m is outside the CCA delivery")
    at("relic", {5000, 20, 5000}, 99, 0)
    run(8)
    check(s.game_over, "within 100 m of the CCA recycler ends the mission")
    eachPeer(function(p)
        check(count(p, "FailMission") == 1 and last(p, "FailMission")[3] == "misn10f1.des", "the CCA win fails everyone once")
        check(count(p, "SucceedMission") == 0 and count(p, "Play", "misn1002.wav") == 1, "no win; the loss line plays once")
    end)
end
do
    -- a tug on a non-human, non-CCA team still holds the relic but draws no pursuit
    local host = session(true, 2)
    local s = host.state
    local units = army(host)
    local tug = spawn("avhaul", 7)
    carry(s, tug)
    run(1)
    check(s.sav_secure and not s.chase_tug and attacksOn(host, tug) == 0, "a support-team tug is not chased")
end
do
    -- delivery to Utah wins on every peer
    local host, guests = session(true, 3)
    local s = host.state
    local tug = spawn("avhaul", 3)
    carry(s, tug)
    at("relic", UTAH, 100, 0)
    run(2)
    check(not s.game_over, "exactly 100 m from Utah is not a delivery")
    at("relic", UTAH, 99, 0)
    run(8)
    check(s.game_over, "within 100 m of Utah wins")
    eachPeer(function(p)
        check(count(p, "SucceedMission") == 1 and last(p, "SucceedMission")[3] == "misn10w1.des", "the debrief reaches every peer once")
        check(count(p, "FailMission") == 0 and count(p, "Play", "misn1001.wav") == 1, "no failure; the win line plays once")
    end)
    check(host.io.releases == 1 and host.io.targets[#host.io.targets] == 1, "the win calms the sky")
    run(60)
    eachPeer(function(p) check(count(p, "SucceedMission") == 1, "single win latch") end)
    for _, g in ipairs(guests) do check(g.io.releases == 0, "guests never release the forced level") end
end
do
    -- the relic destroyed fails everyone once
    local host = session(true, 3)
    objects.relic.alive = false
    run(25)
    eachPeer(function(p)
        check(count(p, "FailMission") == 1 and last(p, "FailMission")[3] == "misn10f2.des", "the lost relic fails everyone once")
    end)
    check(playedOnAll("misn1003.wav") == 3, "the relic-lost line reaches everyone")
end

-- ============================================================ 4. artillery target
do
    -- the 180 s timer shells the nearest player within 200 m, else geyser1
    local host, guests = session(true, 4)
    local s = host.state
    check(s.geys1check == 180, "the first artillery check is at 180 s")
    runTo(179)
    check(count(host, "Attack") == 0, "nothing before 180 s")
    runTo(181)
    for _, u in ipairs({"svartil1", "svartil2"}) do
        check(count2(host, "Attack", u, "geyser1") == 1, u .. " shells geyser1 when no player is near")
    end
    check(s.geys1check > 320 and s.geys1check < 335, "the next check is 150 s later")
    local function fire(playerAt)
        for _, p in pairs(peers) do place(p.player, FAR, 20, FAR) end
        if playerAt then playerAt() end
        s.geys1check = 0
        s.chase_tug = false
        run(1)
    end
    local before = count(host, "Attack")
    fire(function() at(guests[2].player, GEYSER1, 200, 0) end)
    check(count2(host, "Attack", "svartil1", "geyser1") == 2, "200 m is not within range: geyser1 again")
    fire(function() at(guests[2].player, GEYSER1, 199.5, 0); at(guests[1].player, GEYSER1, 120, 0) end)
    check(count2(host, "Attack", "svartil1", guests[1].player) == 1 and count2(host, "Attack", "svartil2", guests[1].player) == 1,
        "the nearest player inside 200 m is shelled by both guns")
    check(count2(host, "Attack", "svartil1", guests[2].player) == 0, "only the nearest")
    fire(function() at(guests[2].player, GEYSER1, 150, 0); at(guests[3].player, GEYSER1, 60, 0) end)
    check(count2(host, "Attack", "svartil1", guests[3].player) == 1, "a guest the closest of several is chosen")
    -- a live chase suppresses the shelling
    for _, p in pairs(peers) do place(p.player, FAR, 20, FAR) end
    army(host) -- a full CCA force keeps chase_tug latched (any missing unit clears it)
    local n = attacksOn(host, "geyser1") + attacksOn(host, guests[3].player)
    s.geys1check = 0
    s.chase_tug = true
    run(1)
    check(attacksOn(host, "geyser1") + attacksOn(host, guests[3].player) == n and s.chase_tug,
        "shelling stops while the carrier is chased")
    for _, g in ipairs(guests) do check(count(g, "Attack") == 0, "guests command no artillery") end
end

-- ============================================================ 5. guest presentation relay
do
    local host, guests = session(true, 4)
    local s = host.state
    eachPeer(function(p)
        check(count(p, "ClearObjectives") == 1 and count2(p, "AddObjective", "misn1000.otf", "white") == 1,
            "the objective reaches every peer once")
    end)
    check(playedOnAll("misn1000.wav") == 4, "the briefing plays on every peer")
    for _, g in ipairs(guests) do
        check(count2(g, "SetObjectiveName", "cam1", "Relic Site") == 1 and count2(g, "SetObjectiveName", "cam2", "CCA Base") == 1
            and count2(g, "SetObjectiveName", "cam3", "Drop Zone") == 1, "the nav names arrive by label on every guest")
    end
    -- the relic marker: strict 100 m from any player
    at(guests[2].player, RELIC, 100, 0)
    run(2)
    check(not s.objective_on, "100 m does not mark the relic")
    at(guests[2].player, RELIC, 99.9, 0)
    run(3)
    check(s.objective_on, "a guest within 100 m marks the relic")
    eachPeer(function(p)
        check(count(p, "SetObjectiveOn", "relic") == 1 and count2(p, "SetObjectiveName", "relic", "Alien Relic") == 1,
            "the 'Alien Relic' marker reaches every peer once")
    end)
    -- the offline placeholder is removed on every peer
    eachPeer(function(p) check(count(p, "RemoveObject", "player0_hover") == 1, "the placeholder removal reaches every peer") end)
    run(4)
    check(not objects.player0_hover.alive, "the placeholder is gone")
    -- the outcome line and the result are lock-step; nothing stayed unresolved
    tug = spawn("avhaul", 2)
    carry(s, tug)
    at("relic", UTAH, 40, 0)
    run(25)
    eachPeer(function(p)
        check(count(p, "Play", "misn1001.wav") == 1 and count(p, "SucceedMission") == 1, "the outcome is heard and shown once per peer")
        check((p.state.coopUnresolved or 0) == 0, "nothing stayed unresolved")
    end)
    local times = {}
    eachPeer(function(p) times[#times + 1] = last(p, "SucceedMission")[2] end)
    for _, t in ipairs(times) do check(math.abs(t - times[1]) < 0.01, "the result lands at one time on every peer") end
end

-- ============================================================ 6. the host leaves
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

-- ============================================================ 7. tug rebuild
do
    local host, guests = session(true, 2)
    local s = host.state
    local first = aip(host, "svhaul")
    run(1)
    check(s.build_tug, "a living CCA tug arms the rebuild")
    local died = now
    objects[first].alive = false
    run(1)
    check(s.making_another_tug, "a dead tug starts the delay")
    runTo(died + 29.5)
    check(built(host, "svhaul") == 0, "nothing inside the 30 s delay")
    runTo(died + 31.5)
    check(built(host, "svhaul") == 1 and s.tug_rebuilds == 1, "a replacement tug is built after 30 s")
    local c = last(host, "BuildObject")
    check(c[3] == "svhaul" and c[4] == 5 and c[5] == "svrecycler", "built on team 5 at the CCA recycler")
    check(s.ccatug == c[2], "the replacement fills the tug slot")
    objects[s.ccatug].alive = false
    run(35)
    check(built(host, "svhaul") == 2 and s.tug_rebuilds == 2, "a second rebuild")
    objects[s.ccatug].alive = false
    run(300)
    check(built(host, "svhaul") == 2, "two rebuilds is the limit")
    for _, g in ipairs(guests) do check(count(g, "BuildObject") == 0, "guests never build the tug") end
    allCCA(host)
end
do
    -- an AIP-built tug appearing first cancels the rebuild
    local host = session(true, 2)
    local s = host.state
    local first = aip(host, "svhaul")
    run(1)
    objects[first].alive = false
    run(10)
    local replacement = aip(host, "svhaul")
    run(40)
    check(built(host, "svhaul") == 0 and s.ccatug == replacement and (s.tug_rebuilds or 0) == 0, "an AIP tug in place skips the rebuild")
end
do
    -- no CCA recycler: the factory builds it; neither: nothing
    local host = session(true, 2)
    local s = host.state
    local first = aip(host, "svhaul")
    run(1)
    objects[first].alive = false
    objects.svrecycler.alive = false
    run(35)
    local c = last(host, "BuildObject")
    check(built(host, "svhaul") == 1 and c[5] == "svmuf", "the CCA factory rebuilds when the recycler is gone")
    local host2 = session(true, 2)
    local f2 = aip(host2, "svhaul")
    run(1)
    objects[f2].alive = false
    objects.svrecycler.alive = false
    objects.svmuf.alive = false
    run(100)
    check(built(host2, "svhaul") == 0, "no rebuild without a CCA factory")
end

-- ============================================================ 8. plan B
do
    local host, guests = session(true, 3)
    local s = host.state
    army(host)
    local tug = aip(host, "svhaul")
    run(1)
    check(s.plan_b and count2(host, "SetAIP", "misn10b.aip", 5) == 1, "plan B loads misn10b.aip on team 5")
    run(60)
    check(count2(host, "SetAIP", "misn10b.aip", 5) == 1, "plan B triggers once")
    for _, g in ipairs(guests) do check(count(g, "SetAIP") == 0 and not g.state.plan_b, "guests never load an AIP") end
end

-- ============================================================ 9. the pickup quake
do
    local host, guests = session(true, 4)
    local s = host.state
    local ccatug = aip(host, "svhaul")
    at(ccatug, RELIC, -60, 0) -- 60 m from the relic, 110 m from geyser1
    run(2)
    check(count2(host, "Pickup", ccatug, "relic") == 1 and s.sav_seized, "the CCA tug picks the relic up")
    check(#host.io.quakes == 1 and host.io.quakes[1][1] == 0.85 and host.io.quakes[1][2] == 6, "the first pickup quakes (0.85, 6)")
    for _, g in ipairs(guests) do
        check(#g.io.events == 1 and g.io.events[1][1] == "IoQuake" and g.io.events[1][2] == 0.85, "IoQuake reaches every guest")
        check(#g.io.quakes == 0, "guests never start a quake themselves")
    end
    -- a later pickup by someone else does not quake again
    objects[ccatug].alive = false
    run(1)
    local human = spawn("avhaul", 2)
    carry(s, human)
    run(2)
    check(s.sav_secure and #host.io.quakes == 1, "only the first pickup quakes")
end
do
    local host, guests = session(true, 3)
    local s = host.state
    local human = spawn("avhaul", 3)
    carry(s, human)
    run(1)
    check(#host.io.quakes == 1, "a human first pickup quakes too")
end

-- ============================================================ 10. weather routing and beats
do
    local host, guests = session(true, 4)
    local s = host.state
    local init = host.io.init
    check(init and init.authority and init.sites.mission == "misn10" and init.startLevel == 1 and init.targetLevel == 1
        and init.send ~= nil, "the leader runs the director as authority, calm at level 1")
    for _, g in ipairs(guests) do
        check(g.io.init and g.io.init.authority == false and g.io.init.seed == nil and g.io.init.targetLevel == 1,
            "guests render the host's weather: no authority and no seed of their own")
    end
    check(host.io.announces == 1 and onAll(function(p) return p.io.announces == 0 end) == 3, "only the leader announces, once")
    check(onAll(function(p) return p.io.updates > 0 end) == 4, "every peer updates the director")
    check(s.ioSeed == 4242, "the leader keeps the seed for a save")
    check(#host.io.targets == 0 and #host.io.forces == 0, "calm at the start: no beat")
    host.io.init.send("IoState", 4242, 12.5, 1, 0, 1, 0, 0)
    host.io.init.send("IoErupt", 2, 3, 20, 0.9)
    host.io.init.send("IoQuake", 0.5, 2)
    run(3)
    for _, g in ipairs(guests) do
        check(#g.io.events == 3 and g.io.events[1][1] == "IoState" and g.io.events[2][1] == "IoErupt"
            and g.io.events[3][1] == "IoQuake", "guests apply every Io event in order")
        check((g.state.coopUnresolved or 0) == 0, "Io events never register as unresolved")
    end
    -- beat 2: the CCA tug exists
    local ccatug = aip(host, "svhaul")
    at(ccatug, RELIC, 400, 0)
    run(1)
    check(#host.io.targets == 1 and host.io.targets[1] == 2, "a CCA tug lifts the sky to level 2")
    run(2)
    check(#host.io.targets == 1, "400 m is not close")
    at(ccatug, RELIC, 399, 0)
    run(1)
    check(#host.io.targets == 2 and host.io.targets[2] == 3, "the tug closing inside 400 m lifts it to 3")
    run(5)
    check(#host.io.targets == 2, "each beat fires once")
    -- beat 4: the carrier within 500 m of its destination bursts the sky
    objects[ccatug].alive = false
    run(1)
    local human = spawn("avhaul", 2)
    carry(s, human)
    at(human, UTAH, 500, 0)
    run(2)
    check(#host.io.forces == 0, "500 m is outside the climax")
    at(human, UTAH, 499, 0)
    run(2)
    check(#host.io.forces == 1 and host.io.forces[1][1] == 5 and host.io.forces[1][2] == 60 and host.io.forces[1][3] == 10,
        "the carrier nearing home bursts the sky to level 5, once")
    run(5)
    check(#host.io.forces == 1, "the burst fires once")
    -- victory calms it
    at("relic", UTAH, 50, 0)
    run(8)
    check(host.io.releases == 1 and host.io.targets[#host.io.targets] == 1, "the win releases the burst and calms the sky")
    eachPeer(function(p)
        if p ~= host then
            check(#p.io.targets == 0 and #p.io.forces == 0 and p.io.releases == 0 and #p.io.quakes == 0,
                "guests never call the weather beats")
        end
    end)
    host.env.Save()
    check(s.weatherState and s.weatherState.saved, "the leader saves the weather state")
    guests[1].env.Save()
    check(guests[1].state.weatherState == nil, "a guest saves no weather")
end
do
    -- a first pickup with no CCA tug goes straight to level 3, once
    local host = session(true, 2)
    local s = host.state
    carry(s, spawn("avhaul", 2))
    run(3)
    check(#host.io.targets == 1 and host.io.targets[1] == 3, "the first pickup lifts the sky to level 3")
end
do
    -- a CCA carrier near the CCA base also bursts the sky
    local host = session(true, 2)
    local s = host.state
    local ccatug = aip(host, "svhaul")
    carry(s, ccatug)
    at(ccatug, {5000, 20, 5000}, 499, 0)
    run(2)
    check(#host.io.forces == 1, "the CCA carrier nearing its base bursts the sky")
end

-- ============================================================ 11. team filter, strict triggers, offline
do
    local host = session(true, 2)
    local s = host.state
    local function add(odf, team) local h = spawn(odf, team); host.env.AddObject(h); return h end
    add("svturr", 2)
    check(s.ccaturret1 == nil, "a guest-team svturr is not a CCA turret")
    local turret = add("svturr", 5)
    check(s.ccaturret1 == turret, "a CCA turret is tracked")
    add("svfigh", 1)
    check(s.ccafighter1 == nil, "a guest-team fighter is not a CCA fighter")
    add("svltnk", 3)
    check(s.ccatank1 == nil, "a guest-team tank is not a CCA tank")
    add("svhaul", 2)
    check(s.ccatug == nil, "a guest-team tug is not the CCA tug")
    add("svartl", 4)
    check(s.ccaartil3 == nil, "a guest-team artillery is not tracked")
    local art = add("svartl", 5)
    check(s.ccaartil3 == art, "a CCA artillery piece takes the free slot")
    local odd = add("avtank", 5)
    check(s.ccatank1 == nil and odd ~= nil, "unlisted odfs pass through untouched")
    check(s.ccamuf == "svmuf", "the map factory keeps its slot")
end
do
    -- offline smoke: the DLL exactly, with nothing on the wire
    local host = session(false, 1)
    local s = host.state
    run(5)
    check(count(host, "Send") == 0, "offline play sends nothing")
    check(count(host, "SetAIControl", 5) == 1 and count(host, "SetScrap", 5) == 1 and world.scrap[5] == 40
        and count(host, "BuildObject") == 0 and #s.hunters == 0, "offline: the DLL's CCA exactly")
    check(host.rally[0] == "avrecycler" and count(host, "Play", "misn1000.wav") == 1, "offline dialogue and rally")
    check(count(host, "RemoveObject", "player0_hover") == 0 and count(host, "DisableStartingRecycler") == 0, "offline: no placeholder removal")
    check(host.io.init.authority and host.io.init.send == nil and host.io.announces == 0, "offline weather is the host path with nothing sent")
    carry(s, spawn("avhaul", 1))
    at("relic", UTAH, 99, 0)
    run(3)
    check(count(host, "SucceedMission") == 1 and last(host, "SucceedMission")[3] == "misn10w1.des", "offline: the win is a direct pass-through")
    check(count(host, "Send") == 0 and #host.io.quakes == 1 and host.io.releases == 1, "offline: quake and calm on the leader path")
end

print("misn10 co-op: " .. checks .. " multi-peer Lua 5.1 mock-engine checks passed")
