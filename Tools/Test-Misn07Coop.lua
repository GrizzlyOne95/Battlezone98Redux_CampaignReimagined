-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Run from the repository root: lua5.1 Tools/Test-Misn07Coop.lua
-- Executes the complete misn07 script in separate Lua 5.1 environments over the
-- real CRCoop registry and the E/A/C presentation transport. The engine, AI and
-- physics are mocks: they verify script decisions, not Redux native map loading,
-- pathfinding, parachute physics, Lua wire serialization or EXU hooks.
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

-- ---------------------------------------------------------------- world model
local now, objects, peers, nextObject, transport, dist, pathPos, world, labelAlias
-- Flat ground at 20 m with a high wall between the overlook and the outpost.
local function terrain(x, z)
    if x > 2480 and x < 2560 then return 85 end
    return 20
end
local LABELS = {
    volcano_geyz1 = {odf = "eggeizr1", team = 0, pos = {2429.5, 76.7, 99451.6}},
    volcano_geyz2 = {odf = "eggeizr1", team = 0, pos = {2626.8, 21.2, 99273.7}},
    camera_geyser = {odf = "eggeizr1", team = 0, pos = {2741.1, 18.2, 99542.4}},
    radar_geyser = {odf = "eggeizr1", team = 0, pos = {2650, 18, 99710}},
    show_geyser = {odf = "eggeizr1", team = 0, pos = {2213, 20, 100098}},
    radar_array = {odf = "sbcom7", team = 5, pos = {2682.4, 18.2, 99709.6}},
    cam3 = {odf = "apcamr", team = 1, pos = {1440, 22.4, 99515.6}},
    parked1 = {odf = "svtank", team = 5, pos = {2829.6, 19, 99597.7}},
    parked2 = {odf = "svtank", team = 5, pos = {2831.5, 19, 99582.1}},
    parked3 = {odf = "svfigh", team = 5, pos = {2824.8, 19.7, 99568.7}},
    pturret1 = {odf = "svturr", team = 5, pos = {2771.5, 18.7, 99680.8}},
    pturret2 = {odf = "svturr", team = 5, pos = {2776.8, 18.7, 99672.8}},
    svrecycler = {odf = "svrecy", team = 5, pos = {3560, 18.6, 99567.3}},
    avfigh1 = {odf = "avfigh", team = 1, pos = {2006.8, 28.8, 97804.6}},
    avtank1 = {odf = "avtank", team = 1, pos = {2021.5, 29.4, 97782}},
}
local PATHS = {
    turret1_spot = {2677.9, 20, 99914.4}, hut1_spawn = {2777.6, 18, 99640.4}, hut2_spawn = {2796.3, 18, 99621.7},
    cam_spawn1 = {2720, 20, 98812.5}, cam_spawn2 = {2835.2, 20, 98550.1}, cam_spawn3 = {3168, 20, 98719.7},
    cam_spawn4 = {3344, 20, 98562.9}, cam_spawn5 = {3439.6, 20, 98772.8}, cam_spawn6 = {3260.8, 20, 98985.3},
    test_tank_spawn = {3283.7, 20, 99037.3}, cam1_spawn = {2672.8, 20, 100027}, jump_cam_spawn = {2440, 76, 99460.5},
    recycle_spawn = {2205.5, 20, 100207}, muf_spawn = {2195.2, 20, 100216}, recycle_cam_spawn = {2251.3, 20, 100064},
    recy_cam_spawn = {3604.7, 20, 99571.7}, base_tower1_spawn = {3624.8, 20, 99594.7},
}
for index = 1, 110 do PATHS[string.format("m%03d", index)] = {3000 + index, 20, 98700} end
local function vec(t) return {x = t[1], y = t[2], z = t[3]} end
local function newObject(handle, odf, team, pos)
    objects[handle] = {alive = true, odf = odf, team = team, health = 1, maxHealth = 2000, pos = vec(pos or {100000, 20, 100000}),
        vel = {x = 0, y = 0, z = 0}}
    return objects[handle]
end
local function reset()
    now, objects, peers, nextObject, dist = 0, {}, {}, 0, {}
    labelAlias = {}
    world = {eject = true, adopt = true, ejected = nil, consoleLog = {}, hold = {}, scrap = {}}
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
local function planar(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end
local function near(a, b, distance)
    dist[tostring(a) .. ":" .. tostring(b)] = distance
    dist[tostring(b) .. ":" .. tostring(a)] = distance
end
local function far(a, b) near(a, b, 10000) end
local function place(h, x, y, z) objects[h].pos = {x = x, y = y, z = z} end

-- Lightweight physics: velocity integration, gravity for pilots, Goto driving, boarding.
local function physics(dt)
    for h, o in pairs(objects) do
        if o.alive then
            if o.airborne then o.vel.y = o.vel.y - 9.8 * dt end
            o.pos.x, o.pos.y, o.pos.z = o.pos.x + o.vel.x * dt, o.pos.y + o.vel.y * dt, o.pos.z + o.vel.z * dt
            if o.airborne then
                local ground = terrain(o.pos.x, o.pos.z)
                o.minClearance = math.min(o.minClearance or math.huge, o.pos.y - ground)
                if o.pos.y <= ground then
                    o.pos.y = ground; o.vel = {x = 0, y = 0, z = 0}; o.airborne = false; o.landed = {x = o.pos.x, z = o.pos.z}
                end
            end
            local target = o.gotoTo or (o.getin and objects[o.getin] and objects[o.getin].pos)
            if target and not o.airborne and not o.frozen then
                local d = planar(o.pos, target)
                local speed = o.odf == "aspilo" and 5 or 10
                if o.getin and d < 4 and objects[o.getin].alive then
                    o.alive = false -- the pilot climbs in; the vehicle takes his team
                    objects[o.getin].team = o.team
                    objects[o.getin].empty = false
                elseif d > 3 then
                    local step = math.min(d, speed * dt)
                    o.pos.x = o.pos.x + (target.x - o.pos.x) / d * step
                    o.pos.z = o.pos.z + (target.z - o.pos.z) / d * step
                end
            end
        end
    end
end

-- ----------------------------------------------------------------------- peers
local function copyTable(t) local r = {}; for k, v in pairs(t) do r[k] = v end; return r end
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
local function callsOf(peer, name)
    local out = {}
    for _, c in ipairs(peer.calls) do if c[1] == name then out[#out + 1] = c end end
    return out
end

local function makePeer(id, team, network)
    local p = {id = id, team = team, net = network, hosting = team == 1, calls = {}, player = "player" .. id,
        rally = nil}
    peers[id] = p
    newObject(p.player, "avtank", team, {100 + id, 20, 100})
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
    e.GetLabel = function(h) return objects[h] and objects[h].label or nil end
    e.SetLabel = function(h, label)
        if objects[h] then objects[h].label = label; labelAlias[label] = h; record("SetLabel", h, label) end
    end
    e.GetHandle = function(label)
        if labelAlias[label] and objects[labelAlias[label]] and objects[labelAlias[label]].alive then return labelAlias[label] end
        if not objects[label] then
            local spec = LABELS[label]
            if spec then
                newObject(label, spec.odf, spec.team, spec.pos)
            else
                local team = (label:find("^sv") or label:find("^sg") or label:find("^hut") or label:find("^power")) and 5 or
                    (label:find("^av") and 1 or 0)
                local odf = label:find("^svpatrol") and "svfigh" or label:find("^svfigh") and "svfigh" or
                    label:find("^svturret") and "svturr" or label:find("^av") and label:gsub("%d+$", "") or "x"
                newObject(label, odf, team)
            end
        end
        objects[label].label = objects[label].label or label
        labelAlias[label] = label
        return objects[label].alive and label or nil
    end
    e.IsValid = function(h) return type(h) == "string" and objects[h] ~= nil and objects[h].alive end
    e.IsAlive = e.IsValid
    e.IsPerson = function(h) return e.IsValid(h) and objects[h].odf == "aspilo" end
    e.IsOdf = function(h, odf) return e.IsValid(h) and objects[h].odf == odf end
    e.GetTeamNum = function(h) return objects[h] and objects[h].team or 0 end
    e.SetTeamNum = function(h, t) record("SetTeamNum", h, t); objects[h].team = t end
    e.GetPerceivedTeam = function(h) return objects[h] and (objects[h].perceived or objects[h].team) end
    e.SetPerceivedTeam = function(h, t) record("SetPerceivedTeam", h, t); if objects[h] then objects[h].perceived = t end end
    e.GetHealth = function(h) return objects[h].health end
    e.GetMaxHealth = function(h) return objects[h].maxHealth end
    e.AddHealth = function(h, v)
        record("AddHealth", h, v)
        objects[h].health = math.max(0, math.min(1, objects[h].health + v / objects[h].maxHealth))
    end
    e.IsDeployed = function(h) return objects[h] and objects[h].deployed end
    e.GetPilot = function() return 10 end
    local resources = {}
    e.GetMaxScrap = function(t) return resources[t] and resources[t].maxScrap or (t == 1 and 100 or 0) end
    e.GetMaxPilot = function(t) return resources[t] and resources[t].maxPilot or (t == 1 and 30 or 0) end
    e.SetMaxScrap = function(t, n) resources[t] = resources[t] or {}; resources[t].maxScrap = n end
    e.SetMaxPilot = function(t, n) resources[t] = resources[t] or {}; resources[t].maxPilot = n end
    e.GetPosition = function(h, point)
        local pos = posOf(h)
        return pos and {x = pos.x, y = pos.y, z = pos.z} or {x = 0, y = 0, z = 0}
    end
    e.GetPositionNear = function(pos) return pos end
    e.GetVelocity = function(h) return copyTable(objects[h].vel) end
    e.SetVelocity = function(h, v) record("SetVelocity", h, v.x, v.y, v.z); objects[h].vel = copyTable(v) end
    e.SetPosition = function(h, pos) objects[h].pos = copyTable(pos) end
    e.SetVector = function(x, y, z) return {x = x or 0, y = y or 0, z = z or 0} end
    e.GetTerrainHeightAndNormal = function(pos) return terrain(pos.x, pos.z), {x = 0, y = 1, z = 0} end
    e.GetPathPointCount = function(path) return pathPos[path] and 1 or 0 end
    e.GetDistance = function(a, b)
        assert(e.IsValid(a), "invalid origin reached native distance query")
        assert(type(b) == "string" or e.IsValid(b), "invalid destination")
        local key = tostring(a) .. ":" .. tostring(b)
        if dist[key] then return dist[key] end
        local pa, pb = posOf(a), posOf(b)
        if pa and pb then
            local dx, dy, dz = pa.x - pb.x, pa.y - pb.y, pa.z - pb.z
            return math.sqrt(dx * dx + dy * dy + dz * dz)
        end
        return 10000
    end
    e.CountUnitsNearObject = function(target, distance, team, odf)
        local n = 0
        for h, o in pairs(objects) do
            if o.alive and o.team == team and (odf == nil or o.odf == odf) and e.GetDistance(h, target) < distance then
                n = n + 1
            end
        end
        return n
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
            if o.alive and planar(o.pos, pos) < distance then list[#list + 1] = h end
        end
        local i = 0
        return function() i = i + 1; return list[i] end
    end
    e.BuildObject = function(odf, objectTeam, where)
        nextObject = nextObject + 1
        local h = "built" .. nextObject
        local pos = posOf(where) or {x = 100000, y = 20, z = 100000}
        local o = newObject(h, odf, objectTeam, {pos.x, pos.y, pos.z})
        record("BuildObject", h, odf, objectTeam, where)
        e.AddObject(h)
        return h
    end
    e.RemoveObject = function(h)
        record("RemoveObject", h)
        if objects[h] then objects[h].alive = false end
    end
    e.EjectPilot = function(h)
        record("EjectPilot", h)
        if world.eject and objects[h] then
            nextObject = nextObject + 1
            local pilot = "pilot" .. nextObject
            local pos = objects[h].pos
            local o = newObject(pilot, "aspilo", objects[h].team, {pos.x, pos.y + 4, pos.z})
            o.vel = {x = 0, y = 8, z = 0}; o.airborne = true
            objects[h].empty = true
            world.ejected = pilot
            if world.adopt then e.AddObject(pilot) end
        end
    end
    e.GetIn = function(pilot, vehicle, priority) record("GetIn", pilot, vehicle, priority); objects[pilot].getin = vehicle end
    e.Goto = function(h, where, priority)
        record("Goto", h, where, priority)
        if objects[h] and type(where) == "table" then objects[h].gotoTo = where end
        if objects[h] and type(where) == "string" and pathPos[where] then objects[h].gotoTo = pathPos[where] end
    end
    e.GetScrap = function(team) return world.scrap[team] or 0 end
    e.AddScrap = function(team, n) record("AddScrap", team, n); world.scrap[team] = (world.scrap[team] or 0) + n end
    e.IsAudioMessageDone = function(handle) return not world.hold[handle] end
    e.CameraCancelled = function() return p.skip == true end
    e.CameraReady = function() assert(not p.cameraUp, "camera opened twice"); p.cameraUp = true; record("CameraReady"); p.skip = false end
    e.CameraFinish = function() assert(p.cameraUp, "camera finished without an active camera"); p.cameraUp = false; record("CameraFinish") end
    e.CameraPath = function(path, h, s, target) assert(p.cameraUp, "camera path without ready"); record("CameraPath", path, h, s, target) end
    e.CameraObject = function(subject, x, y, z, target)
        assert(p.cameraUp, "camera object without ready")
        assert(e.IsValid(subject) and e.IsValid(target), "camera used an invalid handle")
        record("CameraObject", subject, x, y, z, target)
    end
    e.Send = function(to, kind, ...)
        local args = {...}
        local bytes = 4
        for _, value in ipairs(args) do bytes = bytes + (type(value) == "string" and #value + 2 or 9) end
        assert(bytes < 244, "mission packet exceeds stock payload budget: " .. kind)
        for target in pairs(peers) do
            if target ~= id and (to == 0 or to == nil or target == to) then transport:Send(id, target, kind, args, false) end
        end
    end
    for _, name in ipairs({"Attack", "Retreat", "Follow", "Defend", "Patrol", "Stop", "SetIndependence",
        "SetAIP", "SetAIControl", "SetObjectiveName", "SetObjectiveOn", "SetObjectiveOff", "ClearObjectives", "AddObjective",
        "Ally", "UnAlly", "DisplayMessage", "FailMission", "SucceedMission", "SetScrap", "SetPilot"}) do
        local n = name
        e[n] = function(...)
            if n == "SetObjectiveOn" or n == "SetObjectiveName" then
                assert(e.IsValid((...)), "presentation used a not-yet-valid handle")
            end
            record(n, ...)
        end
    end
    local function noop() end
    local modules = {
        RequireFix = {Initialize = noop},
        exu = {GetMyNetID = function() return id end, DisableStartingRecycler = function() record("DisableStartingRecycler") end,
            SetLives = function(n) record("SetLives", n) end},
        ScriptSubtitles = {
            Play = function(file) record("Play", file); return file end,
            Queue = function(file) record("Queue", file) end,
            Stop = function() record("Stop") end, Update = noop, Initialize = noop},
    }
    -- The Venus director is mocked: this suite verifies the mission's wiring (who initializes it,
    -- what rides the event stream, which story beats move the severity ladder), not the sky.
    local venus = {updates = 0, announces = 0, targets = {}, forces = {}, events = {}, created = 0,
        saves = 0, shutdowns = 0, envInit = 0, envUpdates = 0, envCreated = 0}
    p.venus = venus
    modules.CRVenusSites07 = {sites = true}
    modules.Environment = {Init = function() venus.envInit = venus.envInit + 1 end,
        Update = function() venus.envUpdates = venus.envUpdates + 1 end,
        OnObjectCreated = function() venus.envCreated = venus.envCreated + 1 end}
    modules.CRVenusWeather = {
        Init = function(options)
            venus.options = options
            modules.CRVenusWeather.Seed = options.seed or (options.authority and 4242 or nil)
        end,
        Update = function() venus.updates = venus.updates + 1 end,
        AnnounceState = function() venus.announces = venus.announces + 1 end,
        SetTargetLevel = function(n) venus.targets[#venus.targets + 1] = n end,
        ForceLevel = function(a, b, c) venus.forces[#venus.forces + 1] = {a, b, c} end,
        ApplyNetEvent = function(op, ...) venus.events[#venus.events + 1] = {op, ...}; return true end,
        OnObjectCreated = function() venus.created = venus.created + 1 end,
        Save = function() venus.saves = venus.saves + 1; return {saved = true, seed = modules.CRVenusWeather.Seed} end,
        Load = function(state) venus.loaded = state end,
        Shutdown = function() venus.shutdowns = venus.shutdowns + 1 end,
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
    setfenv(assert(loadfile("Scripts/misn07.lua")), e)()
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
local function registerAll()
    for _, p in pairs(peers) do
        for id, other in pairs(peers) do p.env.CreatePlayer(id, "P" .. id, other.team) end
    end
end
-- A four-player session with the leader on team 1; mission clock past the 27 s alarm delay.
local function session(network, humans)
    reset()
    local host = makePeer(10, 1, network)
    local guests = {}
    for i = 2, (humans or 4) do guests[#guests + 1] = makePeer(10 * i, i, network) end
    registerAll()
    run(3)
    return host, guests
end
local function eachPeer(fn) for _, p in pairs(peers) do fn(p) end end
local function allBuildTeams(peer)
    for _, c in ipairs(callsOf(peer, "BuildObject")) do
        check(c[4] == 1 or c[4] == 5 or c[4] == 7, "BuildObject " .. c[3] .. " on guest/unknown team " .. tostring(c[4]))
        if c[3]:find("^sv") and c[3] ~= "svturr" then check(c[4] == 5, c[3] .. " must be CCA team 5") end
    end
end
local function playedOnAll(file)
    local n = 0
    eachPeer(function(p) if count(p, "Play", file) == 1 then n = n + 1 end end)
    return n
end

-- ============================================================ 1. startup, teams
do
    local host, guests = session(true)
    local s = host.state
    check(s.start_done and s.opening_vo == false, "leader starts the mission body")
    for _, g in ipairs(guests) do
        check(not g.state.start_done and count(g, "BuildObject") == 0, "guests never run the mission body")
        check(count(g, "DisableStartingRecycler") == 1, "guests disable the extra starting recycler")
    end
    run(1)
    for _, g in ipairs(guests) do
        check(count(g, "SetScrap", g.team) == 1 and last(g, "SetScrap")[3] == 10, "each human receives starting scrap on their own team")
    end
    check(count(host, "SetScrap", 1) == 1, "the leader receives starting scrap on team 1")
    check(host.rally and host.rally[0] == "cam3" and host.rally[1] == nil, "respawn rally starts at the rendezvous nav")
    for _, g in ipairs(guests) do check(g.rally and g.rally[0] == "cam3", "guests rally at the rendezvous nav") end
    -- The two convoy tanks wait idle on the support team at the map edge.
    local tanks = {}
    for _, c in ipairs(callsOf(host, "BuildObject")) do
        if c[3] == "avtank" then tanks[#tanks + 1] = c end
    end
    check(#tanks == 2 and tanks[1][4] == 7 and tanks[2][4] == 7, "the rendezvous convoy spawns on the support team")
    for _, h in ipairs({s.wingtank2, s.wingtank3}) do
        check(objects[h] and objects[h].pos.x == 779 and objects[h].team == 7, "convoy tanks wait at the NSDF-side map edge")
        check(objects[h].perceived == 1, "convoy tanks are perceived as NSDF")
    end
    check(count(host, "Goto") == 0 and count(host, "Stop") >= 2, "convoy idles until a player approaches")
    -- Co-op alliances: humans allied with each other and with support, enemy 5 isolated.
    check(count(host, "Ally") >= 12 and count(host, "UnAlly") >= 8, "alliances configured")
    allBuildTeams(host)
end

-- ============================================================ 2. convoy and rendezvous
do
    local host, guests = session(true)
    local s = host.state
    run(30)
    check(count(host, "Goto") == 0, "convoy stays idle while every player is far")
    near(guests[2].player, "cam3", 650); run(10)
    check(count(host, "Goto") == 0, "beyond 600 m does not wake the convoy")
    -- The first player (a guest) enters the trigger radius: both tanks are sent.
    s.wingtank2 = s.wingtank2
    local cam3 = host.env.GetHandle("cam3")
    near(guests[2].player, cam3, 550); run(0.5)
    check(count(host, "Goto") == 2, "any player within 600 m of the nav sends both tanks")
    local g1 = callsOf(host, "Goto")
    check(g1[1][2] == s.wingtank2 and g1[1][3].x == 1426.3 and g1[1][3].z == 99546.5, "tank 2 drives to the authored avtank2 position")
    check(g1[2][2] == s.wingtank3 and g1[2][3].x == 1442.5 and g1[2][3].z == 99570.4, "tank 3 drives to the authored avtank3 position")
    run(9); check(count(host, "Goto") == 2, "orders are not repeated every frame")
    run(2); check(count(host, "Goto") == 4, "tanks keep being re-ordered while still driving")
    check(planar(objects[s.wingtank2].pos, {x = 779, z = 99505}) > 20, "convoy is driving")
    -- Kill one en route; the survivor keeps driving and the rendezvous still fires.
    objects[s.wingtank3].alive = false
    run(80)
    check(planar(objects[s.wingtank2].pos, {x = 1426.3, z = 99546.5}) < 30, "the living tank reaches the rendezvous")
    local goto_count = count(host, "Goto")
    run(20); check(count(host, "Goto") == goto_count, "arrived tanks are not re-ordered")
    check(not s.rendezvous, "no rendezvous without a player near a tank")
    near(guests[3].player, s.wingtank2, 140); run(4)
    check(s.rendezvous and playedOnAll("misn0701.wav") == 4, "rendezvous 0701 plays on every peer when ANY player is near")
    check(s.new_tank1 and objects[s.new_tank1].team == 1 and objects[s.new_tank1].odf == "avtank",
        "the convoy tank is replaced by a team-1 avtank")
    check(not objects[s.wingtank2].alive and s.new_tank2 == nil, "the dead convoy tank has no replacement")
    allBuildTeams(host)
end

-- ============================================================ 3. per-player alarm
local function infiltrate(host, player)
    local s = host.state
    near(player, s.camera_geyser, 100); run(0.5)
    far(player, s.camera_geyser)
end
do
    -- A teammate parachutes in; the tank tripwire still trips for a player who has not.
    local host, guests = session(true)
    local s = host.state
    run(30)
    infiltrate(host, guests[1].player)
    check(s.out_of_car and s.infiltrated[20] and not s.infiltrated[10] and not s.alarm_on, "a guest infiltrating is tracked per player")
    check(count(host, "SetObjectiveOn") == 1, "the radar objective is raised once")
    infiltrate(host, guests[2].player)
    check(s.infiltrated[30] and count(host, "SetObjectiveOn") == 1, "a second infiltrator does not repeat the objective")
    near(guests[1].player, "turret1_spot", 40); run(6)
    check(not s.alarm_on, "an infiltrated player at the towers does not trip the alarm")
    near(host.player, "turret1_spot", 60); run(6)
    check(s.alarm_on, "a player who has NOT infiltrated trips the tripwire after a teammate parachuted in")
    check(playedOnAll("misn0710.wav") == 4, "the tripwire alarm line plays on every peer")
    -- Alarm sound: any player within 170 of the radar array.
    near(guests[3].player, s.ccacomtower, 160); run(1)
    check(s.alarm_sound and playedOnAll("misn0708.wav") == 4, "any player near the radar array hears the alarm")
end
do
    local host, guests = session(true)
    local s = host.state
    run(30)
    infiltrate(host, guests[1].player)
    near(guests[1].player, "turret1_spot", 40); run(12)
    check(not s.alarm_on, "the infiltrated player alone never trips the tank tripwire")
    -- Friendly units no longer trip the alarm once anyone is inside (global out_of_car).
    near(s.wingman1, "turret1_spot", 50); run(6)
    check(not s.alarm_on, "friendly-unit tripwires are disarmed once any player has infiltrated")
end
do
    -- With nobody inside the unit tripwire still works, and a late parachute is ignored after the alarm.
    local host, guests = session(true)
    local s = host.state
    run(30)
    near(s.wingman1, "turret1_spot", 50); run(1)
    check(s.alarm_on and playedOnAll("misn0709.wav") == 4, "friendly unit at the towers trips the alarm while nobody is inside")
    infiltrate(host, guests[1].player)
    check(not s.out_of_car and not s.infiltrated[20], "a parachute after the alarm does not count as infiltration")
end

-- ============================================================ 4. special alarm and soldiers
local function spyOn(host, guests)
    local s = host.state
    run(30)
    -- A on hut1, B on hut2 so each soldier has a different nearest player.
    place(guests[1].player, 2780, 20, 99645); place(guests[2].player, 2790, 20, 99625)
    infiltrate(host, guests[1].player); infiltrate(host, guests[2].player)
    return s
end
do
    -- One infiltrator in a Soviet craft, the other on foot: the special soldier alarm.
    local host, guests = session(true)
    local s = spyOn(host, guests)
    objects[guests[1].player].odf = "svtank"; objects[guests[2].player].odf = "aspilo"
    run(1)
    check(s.stolen[20] and not s.stolen[30] and not s.vehicle_stolen, "stolen latch is per player")
    objects[s.barrack1].health = 0.9; run(1)
    check(s.trigger1 and s.alarm_on and s.alarm_special, "one unarmoured infiltrator earns the special alarm")
    run(21)
    check(s.unit_spawn and objects[s.pilot3].odf == "sssold" and objects[s.pilot5].odf == "sssold", "special alarm soldiers spawn")
    for _, name in ipairs({"pilot1", "pilot2", "pilot3", "pilot4", "pilot5"}) do
        check(objects[s[name]].team == 5, "alarm pilots use the CCA team")
    end
    local attacks = {}
    for _, c in ipairs(callsOf(host, "Attack")) do attacks[c[2]] = c[3] end
    check(attacks[s.pilot3] == guests[2].player, "soldier at hut 2 attacks the nearest player")
    check(attacks[s.pilot5] == guests[1].player, "soldier at hut 1 attacks the nearest player")
    allBuildTeams(host)
end
do
    -- Everyone inside has taken a Soviet vehicle: the quiet alarm.
    local host, guests = session(true)
    local s = spyOn(host, guests)
    objects[guests[1].player].odf = "svtank.odf"; objects[guests[2].player].odf = "svfigh"
    run(1)
    objects[guests[1].player].odf = "aspilo"; run(1)
    check(s.vehicle_stolen, "the stolen latch survives leaving the craft")
    objects[s.powrplnt1].health = 0.9; run(1)
    check(s.alarm_on and not s.alarm_special, "all infiltrators in Soviet craft: no special soldiers")
    run(21)
    check(objects[s.pilot3].odf == "sspilo", "standard alarm spawns pilots, not soldiers")
    check(s.spawn_turret1 ~= nil and s.spawn_turret2 ~= nil, "parked turrets are replaced when no player holds them")
    objects[s.pilot1].alive = false; run(1)
    local found = false
    for _, c in ipairs(callsOf(host, "Attack")) do if c[2] == s.parked1 and c[3] ~= nil then found = true end end
    check(found, "a parked tank whose pilot died attacks the nearest player")
end
do
    -- A player sitting in a parked turret keeps it (parkturret ~= any player).
    local host, guests = session(true)
    local s = host.state
    run(30)
    infiltrate(host, guests[1].player)
    objects[guests[1].player].odf = "svtank"; run(1)
    s.parkturret1 = guests[1].player
    objects[s.barrack1].health = 0.9; run(1); run(21)
    check(s.spawn_turret1 == nil and s.spawn_turret2 ~= nil, "the parked turret a player holds is not replaced")
end

-- ============================================================ 5. any-player triggers
do
    local host, guests = session(true)
    local s = host.state
    local cam3 = host.env.GetHandle("cam3")
    s.rendezvous = true; s.patrol2_move_time = 0
    run(1)
    local attacks = {}
    for _, c in ipairs(callsOf(host, "Attack")) do attacks[c[2]] = c[3] end
    check(s.fighter_moved and attacks[s.svpatrol2_1] and attacks[s.svpatrol2_2], "rendezvous fighters attack a player")
    -- Tower warning from the nav: any player.
    near(guests[1].player, s.jump_geyz, 300) -- keeps the rookie back while the warning is tested
    s.nav1 = host.env.BuildObject("apcamr", 1, "cam1_spawn"); s.tower_check = 0
    near(guests[3].player, s.nav1, 80); run(5)
    check(s.tower_warning and playedOnAll("misn0716.wav") == 4, "any player near the outpost nav triggers the tower warning")
    -- Rookie overlook: no player within 400 of the geyser and no svfigh near any player.
    s.recon_message_time = 0
    near(guests[1].player, s.jump_geyz, 300); run(6)
    check(not s.jump_cam_spawned, "a player near the volcano peak holds the rookie back")
    far(guests[1].player, s.jump_geyz)
    local foe = host.env.BuildObject("svfigh", 5, "cam1_spawn"); near(guests[2].player, foe, 150)
    run(6)
    check(not s.jump_cam_spawned, "an enemy fighter near ANY player holds the rookie back")
    objects[foe].alive = false; run(6)
    check(s.jump_cam_spawned and objects[s.rookie].team == 1, "rookie overlook spawns when every player is clear")
    check(playedOnAll(s.take0702) == 4 and (s.take0702 == "misn0702.wav" or s.take0702 == "misn0717.wav"),
        "the overlook call plays on every peer (either take)")
    -- Rookie found: any player within 70.
    near(guests[3].player, s.rookie, 60); run(30)
    check(s.rookie_found and playedOnAll("misn0718.wav") == 4, "any player near the rookie finds him")
    -- Runner: any player within 50 of a patrol fighter.
    s.rendezvous = true; objects[s.svpatrol1_1].alive = false
    near(guests[2].player, s.svpatrol1_2, 40); run(1)
    check(s.p1_retreat and count(host, "Retreat", s.svpatrol1_2) == 1, "any player near a patrol starts the runner")
    run(2)
    local runner = false
    for _, c in ipairs(callsOf(guests[1], "SetObjectiveName")) do if c[2] == s.svpatrol1_2 and c[3] == "Runner" then runner = true end end
    check(runner, "the Runner marker reaches the guests")
end

-- The overlook call is 0702 or its alternate take 0717, picked once by the leader.
for _, case in ipairs({{pick = 0, file = "misn0702.wav", other = "misn0717.wav"},
                       {pick = 1, file = "misn0717.wav", other = "misn0702.wav"}}) do
    for _, network in ipairs({true, false}) do
        local realRandom = math.random
        math.random = function(a, b) check(a == 0 and b == 1, "the take is a 50/50 pick"); return case.pick end
        local host, guests = session(network, network and 4 or 1)
        local s = host.state
        run(30)
        local cam3 = host.env.GetHandle("cam3")
        s.rendezvous = true; s.recon_message_time = 0
        run(6)
        math.random = realRandom
        local peersHeard = network and 4 or 1
        check(s.jump_cam_spawned and s.take0702 == case.file, "the leader picks " .. case.file)
        check(playedOnAll(case.file) == peersHeard and playedOnAll(case.other) == 0,
            case.file .. " reaches every peer and the other take is silent")
        local plays = 0
        for _, c in ipairs(callsOf(host, "Play")) do if c[2] == case.file then plays = plays + 1 end end
        check(plays == 1, "the overlook call plays once")
    end
end
do
    -- The pick is random across a series of games (both takes appear).
    local seen = {}
    math.randomseed(12345)
    for _ = 1, 40 do
        local host = session(false, 1)
        local s = host.state
        run(30); s.rendezvous = true; s.recon_message_time = 0; run(6)
        seen[s.take0702] = true
    end
    check(seen["misn0702.wav"] and seen["misn0717.wav"], "both takes occur at random")
end

-- ============================================================ 6. rally, Utah, win and loss
local function radarDown(host)
    local s = host.state
    objects[s.ccacomtower].alive = false; run(1)
    run(8)
end
do
    local host, guests = session(true)
    local s = host.state
    run(30)
    radarDown(host)
    check(s.first_objective and s.next_mission and playedOnAll("misn0714.wav") == 4, "radar destruction hands off to the Utah")
    check(objects[s.nsdfrecycle].team == 1 and objects[s.ccabaseguntower1].team == 5, "Utah on team 1, CCA tower on team 5")
    local sp = {}
    for _, c in ipairs(callsOf(host, "AddScrap")) do sp[c[2]] = c[3] end
    check(sp[1] == 30 and sp[5] == 60, "Utah scrap goes to team 1, CCA scrap to team 5")
    local aip = last(host, "SetAIP"); check(aip[2] == "misn07.aip" and aip[3] == 5, "the strategic AIP runs the CCA team")
    check(host.rally[1] == nil and guests[1].rally[1] == nil, "rally stays at the rendezvous nav until the Utah deploys")
    check(host.coop.GetMissionPhase() == 0, "mission phase waits for deployment")
    run(100)
    check(playedOnAll("misn0719.wav") == 0, "the Utah reminder waits two minutes after 0714")
    run(20)
    check(playedOnAll("misn0719.wav") == 4, "undeployed Utah earns the 0719 reminder")
    run(30); check(playedOnAll("misn0719.wav") == 4, "the reminder plays once")
    objects[s.nsdfrecycle].deployed = true; run(3)
    check(s.utah_found and host.coop.GetMissionPhase() == 1, "deployment advances the mission phase")
    eachPeer(function(p) check(p.rally and p.rally[0] == "cam3" and p.rally[1] == s.nsdfrecycle, "respawn rally switches to the Utah on every peer") end)
    -- Victory once the CCA recycler is also gone; one result everywhere.
    objects[s.ccarecycle].alive = false; run(2)
    check(s.game_over, "both recyclers gone ends the mission")
    run(8)
    eachPeer(function(p) check(count(p, "SucceedMission") == 1 and last(p, "SucceedMission")[3] == "misn07w1.des", "every peer receives exactly one victory") end)
    check(playedOnAll("misn0713.wav") == 4, "victory line on every peer")
end
do
    local host, guests = session(true)
    local s = host.state
    run(30); radarDown(host)
    objects[s.nsdfrecycle].deployed = true; run(1)
    objects[s.nsdfrecycle].alive = false; run(2)
    run(10)
    eachPeer(function(p) check(count(p, "FailMission") == 1 and last(p, "FailMission")[3] == "misn07f1.des", "losing the Utah fails everyone") end)
    check(playedOnAll("misn0712.wav") == 4, "loss line on every peer")
end
do
    -- Exhausting the five-life respawn service fails the mission.
    local host, guests = session(true)
    host.coop.ReportOutOfLives(); run(8)
    eachPeer(function(p) check(count(p, "FailMission") == 1, "out of lives fails everyone") end)
end
do
    -- The leader leaving ends the mission for the guests.
    local host, guests = session(true)
    guests[1].env.DeletePlayer(10, "P10", 1); run(1)
    check(count(guests[1], "FailMission") == 1, "leader departure fails the mission")
end

-- ============================================================ 7. restored test-range arc
-- Phase 2 settled: the radar is down and the Utah deployed, with Razor One gone (radio-only).
local function arcSession(network)
    local host, guests = session(network)
    local s = host.state
    run(30)
    radarDown(host)
    objects[s.nsdfrecycle].deployed = true
    run(1)
    return host, guests, s
end
do
    -- Nothing starts before the radar is down, and phase 2 waits for the briefing to settle.
    local host, guests = session(true)
    local s = host.state
    run(230)
    check(not s.test_range_started and not s.recon_message2 and s.test_tank == nil and s.test_turret == nil,
        "no test-range content before the radar array is destroyed")
    check(playedOnAll("misn0703.wav") == 0 and s.nav4 == nil, "no 0703 or Testing Range nav in phase 1")
    world.hold["misn0714.wav"] = true
    radarDown(host)
    objects[s.nsdfrecycle].deployed = true; run(5)
    check(s.utah_found and not s.test_range_started, "a deployed Utah still waits for 0714 to finish")
    world.hold["misn0714.wav"] = nil; run(1)
    check(s.test_range_started and s.recon_message2 and playedOnAll("misn0703.wav") == 4,
        "with no Razor One the radio-only 0703 plays once the briefing has settled")
end
do
    -- Without a deployed Utah the arc starts 150 s after 0714, and never over the 0719 nag.
    local host, guests = session(true)
    local s = host.state
    run(30); radarDown(host)
    run(100)
    check(not s.test_range_started, "an undeployed Utah holds the arc before 150 s")
    world.hold["misn0719.wav"] = true
    run(25)
    check(playedOnAll("misn0719.wav") == 4 and not s.test_range_started, "the arc waits while 0719 is playing")
    run(25)
    check(not s.test_range_started, "...even past 150 s")
    world.hold["misn0719.wav"] = nil; run(1)
    check(s.test_range_started and s.recon_message2, "the arc starts after the last line finishes")
end
do
    local host, guests, s = arcSession(true)
    check(s.recon_message2 and playedOnAll("misn0703.wav") == 4, "Razor One announces the test range (0703) on every peer")
    check(objects[s.test_tank].odf == "svtnk7" and objects[s.test_tank].team == 5, "the MAG tank is an svtnk7 on the CCA team")
    check(objects[s.test_turret].odf == "svturr" and objects[s.test_turret].team == 7, "the test turret is a CCA-model turret on the support team")
    local tp = objects[s.test_turret].pos
    check(math.abs(tp.x - 3268.7) < 0.1 and math.abs(tp.z - 99007.6) < 0.1, "the turret stands south of camera_path2's midpoint")
    check(objects[s.test_tank].pos.x == 3283.7, "the MAG tank starts at test_tank_spawn")
    check(count(host, "Stop") >= 5 and count(host, "SetIndependence") >= 4, "test range units wait passively")
    run(14); check(not s.becon_build, "the Testing Range beacon waits 15 s")
    run(2)
    check(s.becon_build and objects[s.nav4].odf == "apcamr" and objects[s.nav4].team == 1, "Testing Range beacon (nav4)")
    check(last(host, "SetObjectiveName")[3] == "Testing Range" and last(guests[1], "SetObjectiveName")[3] == "Testing Range",
        "the Testing Range name reaches the guests")
    -- 0704 only when no player is within 400 m of the Mine Field spawn point.
    s.rookie_rendezvous_time = now - 1
    near(guests[2].player, "cam_spawn1", 300); run(1)
    check(not s.rookie_lost, "a player near cam_spawn1 holds Razor One's distress call")
    far(guests[2].player, "cam_spawn1"); s.rookie_rendezvous_time = now - 1; run(1)
    check(s.rookie_lost and playedOnAll("misn0704.wav") == 4 and objects[s.nav5].team == 1, "0704 and the Mine Field beacon (nav5)")
    check(last(host, "SetObjectiveName")[3] == "Mine Field", "Mine Field marker named")
    -- The four Mine Path beacons appear when ANY player reaches nav5.
    s.reach_mine_time = now - 1; run(1)
    check(not s.mine_pathed, "no mine path before a player reaches nav5")
    near(guests[3].player, s.nav5, 60); s.reach_mine_time = now - 1; run(1)
    check(s.mine_pathed and objects[s.becon4].odf == "apcamr", "any player at nav5 reveals the mine path")
    local names = {}
    for _, c in ipairs(callsOf(guests[1], "SetObjectiveName")) do names[c[3]] = true end
    check(names["Mine Path 1"] and names["Mine Path 2"] and names["Mine Path 3"] and names["Mine Path 4"], "Mine Path names reach the guests")
    for _, c in ipairs(callsOf(host, "Play")) do check(c[2] ~= "misn0711.wav", "the developer joke line stays cut") end
    allBuildTeams(host)
end
do
    -- Streamed minefield.
    local host, guests, s = arcSession(true)
    local function mines() local n = 0; for _, c in ipairs(callsOf(host, "BuildObject")) do if c[3] == "proxmine" then n = n + 1 end end; return n end
    check(mines() == 0, "no mines while every player is far")
    near(guests[1].player, "m050", 300); run(3)
    check(mines() == 1 and s.m_on[50], "a node within 400 m of any player spawns a mine")
    local mine = s.m[50]
    check(objects[mine].team == 5, "mines belong to the CCA team")
    run(3); check(mines() == 1, "a live mine is spawned once")
    near(guests[1].player, "m051", 300); near(guests[1].player, "m001", 300); near(guests[1].player, "m000", 1); run(3)
    check(mines() == 3 and not s.m_on[0] and s.m_on[1] and s.m_on[51], "round robin covers every node; the missing m000 is skipped")
    -- Destroyed mines stay dead; leaving removes the rest.
    objects[mine].alive = false; run(3)
    check(s.m_dead[50] and mines() == 3, "a destroyed mine is marked dead and never respawns")
    far(guests[1].player, "m051"); run(3)
    check(not s.m_on[51] and count(host, "RemoveObject", s.m[51]) == 1, "leaving a node removes its mine")
    check(count(host, "RemoveObject", mine) == 0, "dead mines are not removed again")
    near(guests[1].player, "m051", 300); run(3)
    check(s.m_on[51] and mines() == 4, "re-entering respawns a node that was removed (not dead)")
    allBuildTeams(host)
end
do
    -- The MAG-cannon film.
    local host, guests, s = arcSession(true)
    local tank0 = s.test_tank
    check(count(host, "CameraReady") == 0, "no film until a player reaches the tank")
    near(guests[1].player, tank0, 70); run(1)
    check(count(host, "CameraReady") == 0, "65 m is the film trigger")
    near(guests[1].player, tank0, 60); run(0.5)
    check(count(host, "CameraReady") == 1 and s.camera_ready, "any player at the tank starts the film")
    check(count(host, "AddHealth", s.test_turret) == 1 and last(host, "AddHealth")[3] == -950, "the turret is pre-damaged")
    run(1)
    check(count(host, "CameraObject") >= 1 and last(host, "CameraObject")[2] == tank0, "opening object shot films the tank")
    check(last(host, "CameraObject")[6] == guests[1].player, "the triggering player is the camera target")
    run(1)
    -- Guests watch the film too (their C snapshot kinds).
    for _, g in ipairs(guests) do check(count(g, "CameraReady") == 1 and count(g, "CameraObject") >= 1, "guests receive the object shot") end
    run(5.5)
    check(count(host, "CameraPath", "camera_path1") >= 1, "second shot follows camera_path1")
    run(9)
    check(count(host, "CameraPath", "camera_path2") >= 1, "third shot follows camera_path2 at the turret")
    check(not s.tank_switch, "the tank swap waits five seconds into the third shot")
    run(5)
    check(s.tank_switch and s.test_tank ~= tank0 and objects[s.test_tank].odf == "svtnk7", "the tank is swapped for an attacking svtnk7")
    check(count(host, "Attack", s.test_tank) == 1 and last(host, "Attack")[3] == s.test_turret, "the new tank attacks the turret")
    check(count(host, "RemoveObject", tank0) == 1, "the first tank is removed")
    run(2)
    check(s.camera4_on and last(host, "CameraObject")[2] == s.test_turret, "final object shot films the turret")
    for _, g in ipairs(guests) do check(count(g, "CameraPath", "camera_path2") >= 1, "guests replay the path shots") end
    run(11)
    check(s.camera_off and count(host, "CameraFinish") == 1, "the film finishes once")
    run(3)
    for _, g in ipairs(guests) do check(count(g, "CameraFinish") == 1 and not g.cameraUp, "guests release their cameras") end
    check(objects[s.test_tank].alive, "the MAG tank survives the film")
    near(guests[1].player, s.test_tank, 10); run(5)
    check(count(host, "CameraReady") == 1, "the film runs only once")
    for _, c in ipairs(callsOf(host, "Play")) do check(c[2] ~= "misn0711.wav", "0711 never plays") end
end
do
    -- A guest can skip their own view without moving the shared timeline.
    local host, guests, s = arcSession(true)
    near(guests[1].player, s.test_tank, 40); run(2)
    guests[2].skip = true; run(1)
    check(count(guests[2], "CameraFinish") == 1 and s.camera_ready and not s.camera_off, "a guest skip is local")
    host.skip = true; run(1)
    check(count(host, "CameraFinish") == 1 and not s.camera_off, "a leader skip does not end the shared film")
    host.skip = false
    run(18)
    check(s.tank_switch, "the shared timeline continues to the tank swap")
end
do
    -- The alarm is irrelevant after the radar: the film still runs.
    local host, guests, s = arcSession(true)
    s.alarm_on = true
    near(guests[1].player, s.test_tank, 40); run(3)
    check(count(host, "CameraReady") == 1, "an alarm left on does not block the film")
end

-- ============================================================ 8. Razor One infiltration
-- Puts the rookie at the overlook and lets the DLL eject him.
local function ejectRookie(host)
    local s = host.state
    s.rookie = host.env.BuildObject("avfigh", 1, s.jump_geyz)
    place(s.rookie, 2429.5, 76.7, 99451.6)
    s.rookie_found = true; s.rookie_removed = false; s.rookie_remove_time = 0
    run(0.5)
end
-- Fly until he lands and is ordered into his first vehicle (then stop, before he boards).
local function flyToBoarding(host)
    local s = host.state
    for _ = 1, 400 do
        tick(0.25)
        if s.rk and s.rk.phase == "board" and s.rk.vehicle then return end
    end
    error("never reached boarding")
end
local function flightTrace(host, seconds)
    local s = host.state
    local pilot = s.rk and s.rk.pilot
    local trace = {}
    for _ = 1, math.floor(seconds / 0.25) do
        tick(0.25)
        if pilot and objects[pilot] then
            trace[#trace + 1] = {x = objects[pilot].pos.x, y = objects[pilot].pos.y, z = objects[pilot].pos.z}
        end
    end
    return trace
end
for _, network in ipairs({true, false}) do
    local host, guests = session(network, network and 4 or 1)
    local s = host.state
    run(30)
    local alarmBefore = s.alarm_on
    ejectRookie(host)
    check(s.rookie_removed and count(host, "EjectPilot") == 1 and playedOnAll("misn0715.wav") == (network and 4 or 1), "0715 and EjectPilot happen at the DLL moment")
    check(world.ejected ~= nil and s.rk and s.rk.pilot == world.ejected, "the ejected pilot is captured from AddObject")
    check(objects[s.rookie].empty and objects[s.rookie].alive and objects[s.rookie].team == 1, "the empty avfigh stays as the DLL leaves it")
    check(not s.test_range_started and s.test_tank == nil, "the ejection alone starts nothing of the test-range arc")
    local pilot = s.rk.pilot
    local trace = flightTrace(host, 40)
    check(#trace > 10, "the glide takes several seconds")
    local landing = {x = 2741.1 + 40, z = 99542.4}
    check(objects[pilot].landed and planar(objects[pilot].landed, landing) < 12, "the pilot glides to the landing point inside the outpost")
    -- Horizontal steering toward the target, bounded speed.
    local vs = callsOf(host, "SetVelocity")
    check(#vs > 8, "velocity is driven every frame while airborne")
    local maxSpeed, minVy = 0, 0
    for _, v in ipairs(vs) do
        maxSpeed = math.max(maxSpeed, math.sqrt(v[3] * v[3] + v[5] * v[5])); minVy = math.min(minVy, v[4])
        check(v[3] > -0.001, "steering heads east toward the outpost")
    end
    check(maxSpeed <= 22.001, "horizontal speed is clamped")
    check(minVy >= -5.001, "the descent is limited to a parachute rate")
    local clear = true
    for _, point in ipairs(trace) do if point.y < terrain(point.x, point.z) then clear = false end end
    check(clear, "the pilot clears the wall without clipping it")
    local assisted = false
    for _, v in ipairs(vs) do if v[4] >= 5.99 then assisted = true end end
    check(assisted, "the small upward assist is applied near the wall")
    local calls = #vs
    run(2); check(#callsOf(host, "SetVelocity") == calls, "steering stops once he has landed")
    -- Boarding: the nearest empty parked Soviet vehicle (parked3 is nearest the landing point).
    run(12)
    check(count(host, "GetIn") == 1 and last(host, "GetIn")[3] == s.parked3 or s.parked3 == nil, "he heads for the nearest empty parked vehicle")
    check(last(host, "GetIn")[2] == pilot and last(host, "GetIn")[4] == 1, "the pilot is ordered into the vehicle")
    local stolen = objects["parked3"]
    check(not objects[pilot].alive and stolen.team == 1, "the stolen vehicle ends on team 1")
    run(1)
    check(s.rk and s.rk.phase == "ride" and objects["parked3"].perceived == 1, "the vehicle is NSDF-perceived and riding")
    check(s.parked3 == nil and s.parked1 ~= nil and s.parked2 ~= nil, "the stolen parked handle is cleared from the CCA alarm code")
    run(1)
    local followCall = last(host, "Follow")
    check(followCall and followCall[2] == "parked3" and followCall[3] == (network and guests[1].player or host.player) or followCall[3] ~= nil,
        "the stolen vehicle follows a player")
    check(not s.alarm_on and not s.out_of_car and next(s.infiltrated) == nil, "the quiet theft sets neither alarm nor out_of_car")
    -- Later alarm: the CCA code never commands the stolen vehicle.
    s.alarm_on = true; s.start_evac = true; s.unit_spawn_time = 0; s.alarm_special = false
    run(2)
    for _, c in ipairs(callsOf(host, "Retreat")) do check(c[3] ~= "parked3", "no CCA pilot is sent to the stolen vehicle") end
    objects[s.pilot1].alive = false; objects[s.pilot3].alive = false; run(2)
    for _, c in ipairs(callsOf(host, "Attack")) do check(c[2] ~= "parked3", "the stolen vehicle is never ordered to attack by the CCA alarm") end
    local attacked = false
    for _, c in ipairs(callsOf(host, "Attack")) do if c[2] == "parked1" then attacked = true end end
    check(attacked, "unstolen parked vehicles are still commanded")
    -- Still riding, re-following periodically.
    local follows = count(host, "Follow"); run(12)
    check(count(host, "Follow") > follows, "the follow order is refreshed")
    allBuildTeams(host)
end
do
    -- Fallbacks: the first choice is taken by a player (or destroyed) before he boards.
    local host, guests = session(true)
    local s = host.state
    run(30); ejectRookie(host)
    flyToBoarding(host)
    check(s.rk.phase == "board" and s.rk.vehicle == "parked3", "parked3 is the first choice")
    objects["parked3"].team = 2 -- a player grabs it
    run(1)
    check(s.rk.vehicle == "parked2", "a vehicle taken by a player is skipped for the next nearest")
    objects["parked2"].alive = false; run(1)
    check(s.rk.vehicle == "parked1", "a destroyed vehicle is skipped too")
    check(s.parked3 == nil or s.parked3 == "parked3", "released vehicles return to the CCA alarm code")
    run(15)
    check(objects["parked1"].team == 1, "he finally takes the last empty vehicle")
    check(count(host, "GetIn") == 3, "one boarding order per attempted vehicle")
end
do
    -- Player-occupied vehicles are never candidates.
    local host, guests = session(true)
    local s = host.state
    run(30)
    s.parked3 = guests[1].player
    ejectRookie(host)
    flyToBoarding(host)
    check(s.rk.vehicle == "parked2", "a vehicle a player is sitting in is not chosen")
end
do
    -- Fail-safes: never found, flight timeout, pilot lost.
    local host, guests = session(true)
    local s = host.state
    run(30); world.adopt = false; world.eject = false
    ejectRookie(host)
    check(s.rk ~= nil and s.rk.pilot == nil, "no pilot yet")
    run(4)
    check(s.rk == nil, "an ejection that never produces a pilot drops the behaviour")
    local host2 = session(true)
    local s2 = host2.state
    run(30); world.adopt = true; world.eject = true
    ejectRookie(host2)
    local pilot = s2.rk.pilot
    objects[pilot].vel = {x = 0, y = 0, z = 0}
    -- Pin him in the air by removing gravity and ground so the 60 s limit has to fire.
    objects[pilot].airborne = false; objects[pilot].pos.y = 500
    run(65)
    check(s2.rk == nil, "a glide that never lands is dropped after the time limit")
    local calls2 = #callsOf(host2, "SetVelocity"); run(5)
    check(#callsOf(host2, "SetVelocity") == calls2, "the scripted flight stops steering after the fail-safe")
    -- Pilot killed mid-flight.
    local host3 = session(true)
    local s3 = host3.state
    run(30); ejectRookie(host3); run(2)
    objects[s3.rk.pilot].alive = false; run(1)
    check(s3.rk == nil, "a dead pilot ends the behaviour")
    -- Disabled by flag-free path: scan fallback captures the pilot without AddObject.
    local host4 = session(true)
    local s4 = host4.state
    run(30); world.adopt = false
    ejectRookie(host4); run(0.5)
    check(s4.rk and s4.rk.pilot == world.ejected and s4.rk.phase == "glide", "the next-frame scan captures the pilot when AddObject was missed")
end

-- ============================================================ 8b. Razor One and the test range
local function razorRiding(network)
    local host, guests = session(network, network and 4 or 1)
    local s = host.state
    run(30); ejectRookie(host)
    flyToBoarding(host)
    run(14)
    check(s.rk and s.rk.phase == "ride" and s.razor_unit == "parked3", "Razor One is riding his stolen vehicle")
    return host, guests, s
end
local function phase2(host)
    local s = host.state
    radarDown(host)
    objects[s.nsdfrecycle].deployed = true
    run(1)
end
local function followsOf(host, unit)
    local n = 0
    for _, c in ipairs(callsOf(host, "Follow")) do if c[2] == unit then n = n + 1 end end
    return n
end
do
    local host, guests, s = razorRiding(true)
    phase2(host)
    local unit = s.razor_unit
    check(s.test_range_started and s.tr_hold and s.tr_unit == unit, "Razor One is sent to the test range after phase 2 settles")
    local order = callsOf(host, "Goto")
    check(order[#order][2] == unit and order[#order][3] == "cam_spawn6", "he is ordered to cam_spawn6")
    check(not s.recon_message2 and s.test_tank == nil and s.test_turret == nil and playedOnAll("misn0703.wav") == 0,
        "0703 and the test objects wait for his arrival")
    local follows = followsOf(host, unit)
    run(20)
    check(followsOf(host, unit) == follows, "he stops following the players while on the trip")
    for _ = 1, 400 do if s.recon_message2 then break end; tick(0.25) end; run(1)
    check(s.recon_message2 and playedOnAll("misn0703.wav") == 4, "0703 plays on every peer")
    check(planar(objects[unit].pos, pathPos.cam_spawn6) < 65 and now < 30 + 14 + 120 + 90 + 400, "he arrived at the test range first")
    check(s.test_tank ~= nil and objects[s.test_turret].team == 7, "the test tank and turret spawn with 0703")
    run(16)
    check(s.becon_build and objects[s.nav4].team == 1, "the Testing Range nav follows 15 s later")
    -- The DLL's 120 s later, with no player near the Mine Field spawn: a real ambush, then 0704.
    check(not s.ambushed and playedOnAll("misn0704.wav") == 0, "no ambush before the DLL's 120 s")
    s.rookie_rendezvous_time = now - 1; run(1)
    check(s.ambushed and objects[s.ambush1].odf == "svfigh" and objects[s.ambush1].team == 5 and objects[s.ambush2].team == 5,
        "two CCA fighters ambush him")
    local hit = 0
    for _, c in ipairs(callsOf(host, "Attack")) do if c[3] == unit and (c[2] == s.ambush1 or c[2] == s.ambush2) then hit = hit + 1 end end
    check(hit == 2, "both fighters are ordered onto Razor One")
    check(playedOnAll("misn0704.wav") == 4 and s.nav5 ~= nil and s.rookie_lost, "0704 plays on every peer with the Mine Field nav")
    check(s.tr_hold, "he is still holding the test range while under attack")
    follows = followsOf(host, unit); run(12)
    check(followsOf(host, unit) == follows, "he does not follow anyone mid-ambush")
    objects[s.ambush1].alive = false; objects[s.ambush2].alive = false; run(1)
    check(not s.tr_hold and followsOf(host, unit) >= follows + 1, "once the ambush is cleared he follows the nearest player again")
    run(12)
    check(followsOf(host, unit) >= follows + 2, "the regular follow refresh resumes")
    allBuildTeams(host)
end
do
    -- A player reaches him before the ambush: he rejoins and no false distress call is made.
    local host, guests, s = razorRiding(true)
    phase2(host)
    for _ = 1, 400 do if s.recon_message2 then break end; tick(0.25) end; run(1)
    local unit = s.tr_unit
    near(guests[1].player, unit, 80); run(1)
    check(not s.tr_hold and followsOf(host, unit) >= 1, "a player reaching him ends the trip")
    far(guests[1].player, unit)
    run(16); s.rookie_rendezvous_time = now - 1; run(1)
    check(not s.ambushed and playedOnAll("misn0704.wav") == 0, "no ambush and no distress call once the players are with him")
    check(s.rookie_lost and s.nav5 ~= nil, "the Mine Field nav still drops")
end
do
    -- Killed on the way: the radio-only version at the same points.
    local host, guests, s = razorRiding(true)
    phase2(host)
    objects[s.tr_unit].alive = false; run(1)
    check(s.recon_message2 and playedOnAll("misn0703.wav") == 4 and s.test_tank ~= nil, "a dead Razor One still radios 0703")
    run(16); s.rookie_rendezvous_time = now - 1; run(1)
    check(not s.ambushed and s.ambush1 == nil and playedOnAll("misn0704.wav") == 4, "radio-only 0704 with no ambush")
end
do
    -- Stuck: 0703 plays after the 90 s timeout and the ambush still lands on him.
    local host, guests, s = razorRiding(true)
    phase2(host)
    objects[s.tr_unit].frozen = true
    run(80); check(not s.recon_message2, "0703 waits out most of the 90 s")
    run(15)
    check(s.recon_message2 and playedOnAll("misn0703.wav") == 4, "0703 plays after the 90 s timeout")
    run(16); s.rookie_rendezvous_time = now - 1; run(1)
    check(s.ambushed, "the ambush still targets him")
end
do
    -- A pilot who never got a ride is sent too (offline play as well).
    local host, guests = session(false, 1)
    local s = host.state
    run(30); s.parked1, s.parked2, s.parked3 = nil, nil, nil
    objects.parked1.team, objects.parked2.team, objects.parked3.team = 2, 2, 2
    ejectRookie(host)
    run(30)
    local pilot = s.razor_unit
    check(objects[pilot].alive and objects[pilot].odf == "aspilo", "with no vehicle left he is still a pilot")
    phase2(host)
    check(s.tr_hold and s.tr_unit == pilot and s.rk == nil, "the pilot makes the trip alone")
    for _ = 1, 400 do if s.recon_message2 then break end; tick(0.25) end; run(1)
    check(s.recon_message2, "0703 plays on arrival or at the 90 s timeout")
    run(120)
    check(planar(objects[pilot].pos, pathPos.cam_spawn6) < 65, "the pilot reaches the test range on foot")
end

-- ============================================================ 8d. Razor One's ship regenerates
local function heals(host, ship) return count(host, "AddHealth", ship) end
do
    -- Before the ejection: his avfigh. Nothing happens in the quiet period, then 2% of max per second.
    local host, guests = session(true)
    local s = host.state
    run(30)
    s.rookie = host.env.BuildObject("avfigh", 1, s.jump_geyz)
    local ship = s.rookie
    run(1)
    objects[ship].health = 0.5
    run(1)
    run(2.5)
    check(heals(host, ship) == 0 and objects[ship].health == 0.5, "no healing during the 4 s quiet period")
    run(1.5)
    local at4 = objects[ship].health
    run(10)
    local gained = objects[ship].health - 0.5
    check(gained > 0.17 and gained < 0.23, "about 2% of max health per second afterwards (got " .. gained .. ")")
    local amounts = 0
    for _, c in ipairs(callsOf(host, "AddHealth")) do if c[2] == ship then amounts = math.max(amounts, c[3]) end end
    check(amounts > 0 and amounts < 20, "healing is applied in small per-frame steps scaled by max health")
    -- Stops at max.
    objects[ship].health = 0.99; run(10)
    check(objects[ship].health == 1, "healing stops exactly at max health")
    local n = heals(host, ship); run(10)
    check(heals(host, ship) == n and objects[ship].health == 1, "no healing at full health")
    -- Under fire: continuous damage keeps resetting the quiet period.
    objects[ship].health = 0.8
    local before = heals(host, ship)
    for _ = 1, 16 do objects[ship].health = objects[ship].health - 0.01; run(1) end
    check(heals(host, ship) == before, "no healing while his health keeps falling")
    -- Hit once, then quiet: heals after the delay only.
    objects[ship].health = objects[ship].health - 0.1; run(3.5)
    check(heals(host, ship) == before, "a fresh hit restarts the quiet period")
    run(3)
    check(heals(host, ship) > before, "healing resumes after the quiet period")
    -- Dead: nothing.
    objects[ship].health = 0.4; objects[ship].alive = false
    local dead = heals(host, ship); run(15)
    check(heals(host, ship) == dead, "no healing once dead")
end
do
    -- The pilot on foot and his empty avfigh are not healed after the ejection.
    local host, guests = session(true)
    local s = host.state
    run(30); ejectRookie(host)
    local pilot = s.rk.pilot
    objects[s.rookie].health = 0.5
    local before = count(host, "AddHealth")
    run(1)
    objects[pilot].health = 0.5
    run(12)
    check(count(host, "AddHealth", pilot) == 0, "the pilot on foot is never healed")
    check(count(host, "AddHealth", s.rookie) == 0 and objects[s.rookie].health == 0.5, "the empty avfigh is not healed after the ejection")
end
do
    -- The stolen Soviet vehicle is healed (after the pilot has climbed in), including on the test-range trip.
    local host, guests, s = razorRiding(true)
    local ship = s.razor_unit
    check(ship == "parked3" and s.rk.phase == "ride", "riding the stolen vehicle")
    objects[ship].maxHealth = 2375; objects[ship].health = 0.6
    run(1); run(4)
    local before = objects[ship].health
    run(10)
    local gained = objects[ship].health - before
    check(gained > 0.17 and gained < 0.23, "the stolen vehicle regenerates 2% of max per second")
    local step = 0
    for _, c in ipairs(callsOf(host, "AddHealth")) do if c[2] == ship then step = math.max(step, c[3]) end end
    check(step < 2375 * 0.02, "per-frame heal is scaled by the vehicle's own max health")
    phase2(host)
    check(s.tr_hold and s.tr_unit == ship, "on the trip to the test range")
    objects[ship].health = 0.5; run(1); run(6)
    check(objects[ship].health > 0.5, "he is still healed while driving to the test range")
    -- A pilot who lost his vehicle (dead) heals nothing.
    objects[ship].alive = false
    local n = count(host, "AddHealth", ship); run(10)
    check(count(host, "AddHealth", ship) == n, "no healing after the vehicle is destroyed")
end

-- ============================================================ 8c. prototype svtnk7 production
local function protoBuilds(host)
    local n = 0
    for _, c in ipairs(callsOf(host, "BuildObject")) do
        if c[3] == "svtnk7" and c[5] == host.state.ccamuf then n = n + 1 end
    end
    return n
end
local function runFilm(guests)
    local s = peers[10].state
    near(guests[1].player, s.test_tank, 40)
    run(40)
    far(guests[1].player, s.test_tank)
end
do
    local host, guests, s = arcSession(true)
    world.scrap[5] = 1000
    run(300)
    check(s.proto_start == nil and #s.proto == 0 and protoBuilds(host) == 0, "no prototype production before the film")
    runFilm(guests)
    check(s.camera_off and s.proto_start ~= nil, "the film finishing starts the prototype program")
    local started = s.proto_start
    run(80)
    check(#s.proto == 0, "the first prototype is built no sooner than 90 s after the trigger")
    local scrapBefore = world.scrap[5]
    run(15)
    check(#s.proto == 1 and protoBuilds(host) == 1, "the first prototype is built at the CCA factory")
    local tank = s.proto[1]
    check(objects[tank].odf == "svtnk7" and objects[tank].team == 5, "prototype tanks are team 5")
    check(world.scrap[5] == scrapBefore - 8, "the build charges team-5 scrap")
    local attack
    for _, c in ipairs(callsOf(host, "Attack")) do if c[2] == tank then attack = c[3] end end
    check(attack == s.nsdfrecycle, "prototypes are sent at the Utah")
    -- Solo-sized cap in a 4 player game is 4; production is bounded by the cap and the interval.
    run(135 * 6)
    check(#s.proto == 4 and protoBuilds(host) == 4, "four players allow four live prototypes")
    check(s.proto_start == started, "the trigger fires once")
    -- Losing one lets the factory replace it; losing the factory ends production.
    objects[s.proto[1]].alive = false; run(140)
    check(#s.proto == 4 and protoBuilds(host) == 5, "a destroyed prototype is replaced")
    objects[s.ccamuf].alive = false
    objects[s.proto[1]].alive = false; run(400)
    check(protoBuilds(host) == 5 and #s.proto == 3, "production halts when the factory is destroyed")
    run(40)
    local orders = 0
    for _, c in ipairs(callsOf(host, "Attack")) do if c[2] == s.proto[1] then orders = orders + 1 end end
    check(orders >= 2, "surviving prototypes keep being ordered in")
    allBuildTeams(host)
end
do
    -- The cap scales with the number of human teams: 2 solo, 3 with two players, 4 max.
    for humans, cap in pairs({[1] = 2, [2] = 3, [3] = 4, [4] = 4}) do
        reset()
        local host = makePeer(10, 1, humans > 1)
        for i = 2, humans do makePeer(10 * i, i, true) end
        registerAll(); run(3); run(30)
        local s = host.state
        radarDown(host); objects[s.nsdfrecycle].deployed = true; run(1)
        world.scrap[5] = 1000
        s.camera_off = true
        run(135 * 6 + 90)
        check(#s.proto == cap, humans .. " human team(s): " .. cap .. " prototypes")
    end
end
do
    -- A starved CCA builds nothing and charges nothing; scrap restores production.
    local host, guests, s = arcSession(true)
    world.scrap[5] = 3
    s.camera_off = true
    run(300)
    check(#s.proto == 0 and world.scrap[5] == 3, "without scrap there is no build and no charge")
    world.scrap[5] = 50; run(20)
    check(#s.proto == 1 and world.scrap[5] == 42, "production resumes as soon as scrap allows")
end
do
    -- Skipped film (offline leader) and the no-film engagement both trigger it too.
    local host = session(false, 1)
    local s = host.state
    run(30); radarDown(host); objects[s.nsdfrecycle].deployed = true; run(1)
    near(host.player, s.test_tank, 40); run(1.5)
    check(s.camera_ready and s.proto_start == nil, "no prototypes while the film runs")
    host.skip = true; run(1); host.skip = false
    check(s.camera_off and s.proto_start ~= nil, "an offline skip starts the prototype program")
    local h2, g2, s2 = arcSession(true)
    run(60)
    check(s2.proto_start == nil, "an untouched test tank does not start it")
    objects[s2.test_tank].health = 0.9; run(1)
    check(s2.proto_start ~= nil and not s2.camera_ready, "the test tank engaging without a film starts it")
    local h3, g3, s3 = arcSession(true)
    objects[s3.test_tank].alive = false; run(1)
    check(s3.proto_start ~= nil, "a destroyed test tank starts it")
end

-- ============================================================ 8e. Venus weather wiring
do
    local host, guests = session(true)
    local s = host.state
    -- Who initializes what.
    local o = host.venus.options
    check(o and o.authority == true and o.seed == nil and o.sites.sites and o.startLevel == 1 and o.targetLevel == 2,
        "the leader starts the director with the map sites, ladder 1 -> target 2 and no seed yet")
    check(type(o.send) == "function" and type(o.players) == "function", "the leader sends events and lists the players")
    check(s.venusSeed == 4242, "the leader's seed is saved in the mission table")
    for _, g in ipairs(guests) do
        check(g.venus.options.authority == false and g.venus.options.seed == nil, "guests wait for the host's seed")
    end
    check(host.venus.envInit == 1 and host.venus.announces == 1, "the leader announces its state once the session is ready")
    for _, g in ipairs(guests) do check(g.venus.announces == 0, "guests never announce") end
    run(5)
    for _, peer in pairs(peers) do
        check(peer.venus.updates > 10 and peer.venus.envUpdates == peer.venus.updates, "every peer updates the director and Environment each frame")
    end
    check(host.venus.announces == 1, "the announcement is not repeated")
    -- The host's event queue reaches every guest through the ordered stream, and only the guests.
    local list = host.venus.options.players()
    check(#list == 4, "the director sees every human craft (" .. #list .. ")")
    host.venus.options.send("VenusState", 4242, 12.5, 2, 0, 2, 0, 0)
    host.venus.options.send("VenusStrike", 1, 100, 20, 200, 1, 1.5, 0.7)
    host.venus.options.send("VenusErupt", 1, 3, 20, 0.9)
    run(3)
    for _, g in ipairs(guests) do
        check(#g.venus.events == 3 and g.venus.events[1][1] == "VenusState" and g.venus.events[2][1] == "VenusStrike" and
            g.venus.events[3][1] == "VenusErupt", "every guest receives the weather events in order")
        check(g.venus.events[2][7] == 1.5, "event arguments survive the stream")
    end
    check(#host.venus.events == 0, "the host does not re-apply its own events")
    -- Objects feed both the environment and the director.
    local before = host.venus.created
    host.env.BuildObject("apcamr", 1, "cam1_spawn")
    check(host.venus.created == before + 1 and host.venus.envCreated >= 1, "new objects reach Environment and the director")
    check(guests[1].venus.created >= 0, "guests see engine-created objects too")

    -- Host-only beats: calm approach, rising, burst, storm, easing; each exactly once.
    check(#host.venus.targets == 0 and #host.venus.forces == 0, "the approach stays at the opening target")
    run(30)
    s.alarm_on = true; run(1)
    check(#host.venus.targets == 1 and host.venus.targets[1] == 3, "the infiltration raises the target to 3")
    s.alarm_on = false; run(2)
    check(#host.venus.targets == 1, "the rising beat fires once")
    s.unit_spawn = true; run(1)
    check(#host.venus.forces == 1 and host.venus.forces[1][1] == 5 and host.venus.forces[1][2] == 100 and
        host.venus.forces[1][3] == 14, "the evacuation sets off a 100 s level-5 burst")
    radarDown(host)
    check(host.venus.targets[2] == 4 and #host.venus.targets == 2, "the radar array falling raises the target to 4")
    objects[s.nsdfrecycle].deployed = true; run(2)
    check(host.venus.targets[3] == 3 and #host.venus.targets == 3, "the deployed Utah eases the target back to 3")
    run(30)
    check(#host.venus.targets == 3 and #host.venus.forces == 1, "no beat repeats")
    for _, g in ipairs(guests) do
        check(#g.venus.targets == 0 and #g.venus.forces == 0, "guests never move the ladder themselves")
    end
    -- Save: the leader stores the director's scalars with the mission.
    local m = host.env.Save()
    check(m.weatherState and m.weatherState.saved and m.venusSeed == 4242, "Save carries the weather state and seed")
    check(guests[1].env.Save().weatherState == nil, "guests save no weather state")
    -- Co-op presentation invariants: authored targets went by label, spawned ones were labelled by
    -- the leader and announced, and no guest ever hit the never-hang guard.
    for _, g in ipairs(guests) do
        check(g.env.Save().coopUnresolved == 0, "no guest gave up on an object (coopUnresolved == 0)")
        local carried = 0
        for _, c in ipairs(callsOf(g, "SetLabel")) do if c[3]:find("^crco_") then carried = carried + 1 end end
        check(carried > 0, "guests carry the leader's labels for spawned marker targets")
    end
end
do
    -- A saved weather state is restored on the leader and consumed.
    reset()
    local host = makePeer(10, 1, true)
    host.state.weatherState = {tag = "saved"}
    host.state.venusSeed = 99
    local guest = makePeer(20, 2, true)
    registerAll(); run(3)
    check(host.venus.loaded and host.venus.loaded.tag == "saved" and host.state.weatherState == nil, "a saved state is loaded and consumed")
    check(host.venus.options.seed == 99, "the saved seed is reused")
    local restored = host.env.Save()
    restored.weatherState = {tag = "same-lua"}
    host.env.Load(restored); run(1)
    check(host.venus.loaded and host.venus.loaded.tag == "same-lua" and host.state.weatherState == nil,
        "same-Lua load consumes saved weather and rebuilds the director")
    -- A mission restart in the same process stands the director down first.
    local before = host.venus.shutdowns
    host.env.Start(); run(1)
    check(host.venus.shutdowns > before, "restarting the mission shuts the director down")
end
do
    -- Offline play: the same director, nothing transmitted.
    local host = session(false, 1)
    local o = host.venus.options
    check(o.authority == true and o.send == nil and o.players == nil and host.venus.announces == 0, "offline: host path with no sender")
    host.state.alarm_on = true; run(1)
    check(host.venus.targets[1] == 3, "offline beats work")
end

-- ============================================================ 9. offline play
do
    local host = session(false, 1)
    local s = host.state
    check(s.start_done and count(host, "DisableStartingRecycler") == 0, "offline starts without multiplayer hooks")
    check(count(host, "SetScrap", 1) == 1 and count(host, "Play") == 0, "offline starting scrap is the stock call")
    run(30)
    -- Single player: the one player trips the tripwire until they infiltrate.
    near(host.player, "turret1_spot", 60); run(6)
    check(s.alarm_on, "offline the lone player trips the tank tripwire")
    check(playedOnAll("misn0710.wav") == 1, "offline dialogue reaches the one player")
    local host2 = session(false, 1)
    local s2 = host2.state
    run(30); radarDown(host2)
    objects[s2.nsdfrecycle].deployed = true; run(1)
    near(host2.player, s2.test_tank, 40); run(1.5)
    check(count(host2, "CameraObject") >= 1, "offline film runs natively")
    host2.skip = true; run(1)
    check(s2.camera_off and count(host2, "CameraFinish") == 1 and s2.tank_switch, "an offline skip ends the film and resolves the swap")
    host2.skip = false
    run(2)
    check(count(host2, "CameraReady") == 1, "the offline film does not repeat")
end

print("misn07 co-op: " .. checks .. " complete-script Lua 5.1 checks passed")
