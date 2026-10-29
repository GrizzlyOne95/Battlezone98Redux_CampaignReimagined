-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Run from the repository root: lua5.1 Tools/Test-Misn09Coop.lua
-- Executes the complete misn09 script in separate Lua 5.1 environments over the
-- real CRCoop registry and the E/A/C presentation transport. The engine, AI and
-- combat are mocks: they verify script decisions, not Redux native map loading,
-- pathfinding, weapon damage, Lua wire serialization or EXU hooks.
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

-- ---------------------------------------------------------------- world model
local now, objects, peers, nextObject, transport, dist, pathPos, world
local function terrain(x, z) return 20 end
local LABELS = {
    avmuf = {odf = "avmuf", team = 1, pos = {2991.2, 14.6, 100939}, hp = 4000},
    rig = {odf = "avcns9", team = 1, pos = {3010.4, 14.5, 100942.9}},
    avslf = {odf = "avslf", team = 1, pos = {3000.3, 14.9, 100926.6}},
    scav1 = {odf = "avscav", team = 1, pos = {3000, 14.6, 100915}},
    scav2 = {odf = "avscav", team = 1, pos = {3010, 14.6, 100915}},
    scav3 = {odf = "avscav", team = 1, pos = {3020, 14.6, 100915}},
    cam1 = {odf = "apcamr", team = 1, pos = {2900.4, 14.1, 99640.5}},
    cut_off_geyser = {odf = "eggeizr1", team = 0, pos = {2885.6, 14.2, 99661.1}},
    convoy_geyser = {odf = "eggeizr1", team = 0, pos = {3680.5, 31.3, 100517}},
    launchpad = {odf = "sblpad", team = 5, pos = {2242.4, 91.8, 98903.3}, hp = 5000},
    svmuf = {odf = "svmuf", team = 5, pos = {2151.4, 14.3, 99185.5}, hp = 3000},
    svrecycle = {odf = "svrecy", team = 5, pos = {2226.4, 14.3, 99172.1}, hp = 3000},
    artil1 = {odf = "svartl", team = 5, pos = {2480.2, 88.9, 100089}},
    artil2 = {odf = "svartl", team = 5, pos = {2714.7, 103.3, 100044}},
    artil3 = {odf = "svartl", team = 5, pos = {2807.4, 126.9, 100279}},
    artil4 = {odf = "svartl", team = 5, pos = {2605.5, 141.3, 100471}},
    artil5 = {odf = "svartl", team = 5, pos = {2818.4, 139.7, 100508}},
    artil6 = {odf = "svartl", team = 5, pos = {2863.4, 112.1, 100663.7}},
    hbchar0_i76building = {odf = "hbchar", team = 0, pos = {2547, 100.9, 99820.6}},
    key_scrap = {odf = "sscr_1", team = 0, pos = {2552, 14.6, 101400}},
    player0_hover = {odf = "player", team = 1, pos = {2557.5, 15, 101414.2}},
}
local PATHS = {
    spawn1 = {3669.2, 31, 100508}, spawn2 = {3688.4, 31, 100532}, spawn3 = {3703.1, 31, 100518},
    spawn4 = {3691.3, 31, 100497}, soviet_path = {3660.3, 31, 100474}, return_path = {3027.7, 14, 100951},
    charon_spawn = {2528.5, 100, 99814.9}, post1 = {2183.2, 14, 99249.8}, post2 = {2265.9, 14, 99188.5},
    post3 = {2239.2, 14, 99160.5}, post4 = {2115.2, 14, 99236.5},
}
local function vec(t) return {x = t[1], y = t[2], z = t[3]} end
local function newObject(handle, odf, team, pos)
    objects[handle] = {alive = true, odf = odf, team = team, health = 1, pos = vec(pos or {100000, 20, 100000}),
        vel = {x = 0, y = 0, z = 0}}
    local o = objects[handle]
    if LABELS[handle] then o.label = handle; o.perceived = LABELS[handle].perceived end
    if LABELS[handle] and LABELS[handle].hp then o.hp, o.maxhp = LABELS[handle].hp, LABELS[handle].hp end
    return objects[handle]
end
local function reset()
    now, objects, peers, nextObject, dist = 0, {}, {}, 0, {}
    world = {hold = {}, scrap = {}, cargo = {}, combat = true, nilMapHandles = true, net = false}
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

-- Lightweight physics: Goto/Attack driving and a flat damage model. An attacker
-- closes to 120 m of its target and deals dps to it; the kill is recorded on the victim.
local SPEED = {svfigh = 30, svtank = 15, avtank = 20, svhaul = 0, avmuf = 0}
local DPS = {svfigh = 80, svtank = 100, avtank = 150}
local function physics(dt)
    for h, o in pairs(objects) do
        if o.removeAt and now >= o.removeAt then o.alive = false end
        if o.alive and o.pickup and objects[o.pickup] and objects[o.pickup].alive then
            world.cargo[o.pickup] = h
            o.pickup = nil
        end
        if o.alive then
            local target = o.gotoTo
            local victim = o.attack and objects[o.attack] and objects[o.attack].alive and objects[o.attack] or nil
            if victim then target = victim.pos end
            if target then
                local d = planar(o.pos, target)
                if victim and d <= 120 then
                    if world.combat and victim.hp then
                        victim.hp = victim.hp - (DPS[o.odf] or 50) * dt
                        victim.health = victim.hp / victim.maxhp
                        if victim.hp <= 0 then
                            victim.alive = false; victim.killedBy = h; victim.diedAt = now
                        end
                    end
                elseif d > 3 then
                    local step = math.min(d, (SPEED[o.odf] or 10) * dt)
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

local function makePeer(id, team, network)
    local p = {id = id, team = team, net = network, hosting = team == 1, calls = {}, player = "player" .. id,
        rally = nil}
    p.venus = {updates = 0, announces = 0, shutdowns = 0, targets = {}, forces = {}, events = {}}
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
    e.GetHandle = function(label)
        if not objects[label] then
            local spec = LABELS[label]
            if spec then
                newObject(label, spec.odf, spec.team, spec.pos)
            else
                newObject(label, "x", 0)
            end
        end
        return objects[label].alive and label or nil
    end
    e.GetLabel = function(h) return objects[h] and objects[h].label end
    e.IsInfo = function(prefix) return p.info ~= nil and p.info[prefix] == true end
    e.Damage = function(h, n)
        record("Damage", h, n)
        if objects[h] then objects[h].alive = false; objects[h].killedBy = "script" end
    end
    e.Attack = function(h, target, priority)
        record("Attack", h, target, priority)
        if objects[h] then objects[h].attack = target; objects[h].gotoTo = nil end
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
    e.AddHealth = function(h, v)
        record("AddHealth", h, v)
        local o = objects[h]
        if o and o.alive and o.hp then o.hp = math.min(o.maxhp, o.hp + v); o.health = o.hp / o.maxhp end
    end
    e.IsDeployed = function(h) return objects[h] and objects[h].deployed end
    e.GetPilot = function() return 10 end
    e.GetTug = function(h)
        local tug = world.cargo[h]
        if tug and objects[tug] and objects[tug].alive then return tug end
    end
    e.IsAudioMessageDone = function(handle) return not world.hold[handle] end
    e.StopAudioMessage = function() end
    local resources = {}
    e.GetMaxScrap = function(t) return resources[t] and resources[t].maxScrap or (t == 1 and 100 or 0) end
    e.GetMaxPilot = function(t) return resources[t] and resources[t].maxPilot or (t == 1 and 30 or 0) end
    e.SetMaxScrap = function(t, n) resources[t] = resources[t] or {}; resources[t].maxScrap = n end
    e.SetMaxPilot = function(t, n) resources[t] = resources[t] or {}; resources[t].maxPilot = n end
    e.GetPosition = function(h, point)
        if type(point) == "number" and world.route and h == "soviet_path" then return copyTable(world.route[point + 1]) end
        local pos = posOf(h)
        return pos and {x = pos.x, y = pos.y, z = pos.z} or {x = 0, y = 0, z = 0}
    end
    e.GetPositionNear = function(pos) return pos end
    e.GetVelocity = function(h) return copyTable(objects[h].vel) end
    e.SetVelocity = function(h, v) record("SetVelocity", h, v.x, v.y, v.z); objects[h].vel = copyTable(v) end
    e.SetPosition = function(h, pos) objects[h].pos = copyTable(pos) end
    e.SetVector = function(x, y, z) return {x = x or 0, y = y or 0, z = z or 0} end
    e.GetTerrainHeightAndNormal = function(pos) return terrain(pos.x, pos.z), {x = 0, y = 1, z = 0} end
    e.GetPathPointCount = function(path)
        if path == "soviet_path" and world.route then return #world.route end
        return pathPos[path] and 1 or 0
    end
    e.GetFront = function(h) return copyTable(objects[h].front or {x = 1, y = 0, z = 0}) end
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
        o.hp = ({avtank = 2000, svfigh = 800, svtank = 1500, svapc = 1000, svhaul = 1000, obdata = 1000,
            avwalk = 1500})[odf] or 1000
        o.maxhp = o.hp
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
        if objects[h] then objects[h].attack = nil end
        if objects[h] and type(where) == "table" then objects[h].gotoTo = where end
        if objects[h] and type(where) == "string" and pathPos[where] then objects[h].gotoTo = pathPos[where] end
        if objects[h] and type(where) == "string" and objects[where] then objects[h].gotoTo = objects[where].pos end
    end
    e.GetScrap = function(team) return world.scrap[team] or 0 end
    e.AddScrap = function(team, n) record("AddScrap", team, n); world.scrap[team] = (world.scrap[team] or 0) + n end
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
        for i = 1, select("#", ...) do local v = select(i, ...); assert(type(v) ~= "string" or #v <= 127, "Send string over 127 bytes on " .. tostring(kind)) end
        record("Send", kind)
        local args = {...}
        if world.nilMapHandles then
            -- The engine maps a handle across Send only for replicated objects: a
            -- map-authored one arrives as an invalid handle on a guest.
            for index = 1, select("#", ...) do
                if type(args[index]) == "string" and LABELS[args[index]] then args[index] = false end
            end
        end
        local bytes = 4
        for _, value in ipairs(args) do bytes = bytes + (type(value) == "string" and #value + 2 or 9) end
        assert(bytes < 244, "mission packet exceeds stock payload budget: " .. kind)
        for target in pairs(peers) do
            if target ~= id and (to == 0 or to == nil or target == to) then transport:Send(id, target, kind, args, false) end
        end
    end
    for _, name in ipairs({"Retreat", "Follow", "Defend", "Patrol", "Stop", "SetIndependence",
        "SetAIP", "SetAIControl", "SetWeaponMask", "SetObjectiveName", "SetObjectiveOn", "SetObjectiveOff", "ClearObjectives", "AddObjective",
        "Ally", "UnAlly", "DisplayMessage", "FailMission", "SucceedMission", "SetScrap", "SetPilot", "Deploy",
        "Pickup", "Dropoff"}) do
        local n = name
        e[n] = function(...)
            if n == "SetObjectiveOn" or n == "SetObjectiveName" then
                assert(e.IsValid((...)), "presentation used a not-yet-valid handle")
            end
            record(n, ...)
            if n == "SetScrap" then world.scrap[(...)] = select(2, ...) end
            if n == "Deploy" then objects[(...)].deployed = true end
            if n == "Pickup" then objects[(...)].pickup = select(2, ...) end
            if n == "Dropoff" then objects[(...)].gotoTo = nil end
        end
    end
    local function noop() end
    local modules = {
        RequireFix = {Initialize = noop},
        -- The real director has its own suite (Test-CRVenusWeather.lua); this records the
        -- mission's wiring: what it was initialised with, the beats, and the events it received.
        CRVenusWeather = {
            Init = function(options) p.venus.init = options end, Update = function() p.venus.updates = p.venus.updates + 1 end,
            Shutdown = function() p.venus.shutdowns = p.venus.shutdowns + 1 end, OnObjectCreated = noop,
            Save = function() return { saved = true } end, Load = function(state) p.venus.loaded = state end,
            AnnounceState = function() p.venus.announces = p.venus.announces + 1 end,
            ApplyNetEvent = function(op, ...) p.venus.events[#p.venus.events + 1] = { op, ... }; return true end,
            SetTargetLevel = function(level) p.venus.targets[#p.venus.targets + 1] = level end,
            ForceLevel = function(level, seconds, transition) p.venus.forces[#p.venus.forces + 1] = { level, seconds, transition } end,
            Seed = 4242},
        CRVenusSites09 = { mission = "misn09" }, Environment = {Init = noop, Update = noop, OnObjectCreated = noop},
        exu = {GetMyNetID = function() return id end, DisableStartingRecycler = function() record("DisableStartingRecycler") end,
            SetLives = function(n) record("SetLives", n) end},
        PersistentConfig = {Initialize = noop, UpdateInputs = noop, UpdateHeadlights = noop, OnObjectCreated = noop},
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
    setfenv(assert(loadfile("Scripts/misn09cr.lua")), e)()
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
    world.net = network
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
        check(c[4] == 0 or c[4] == 1 or c[4] == 5 or c[4] == 7,
            "BuildObject " .. c[3] .. " on a guest/unknown team " .. tostring(c[4]))
        if c[3]:find("^sv") then check(c[4] == 5, c[3] .. " must be CCA team 5") end
        if c[3] == "obdata" then check(c[4] == 0, "the relic is neutral") end
        if c[3] == "avtank" then check(c[4] == 7, "Prescott's tanks are the support team") end
    end
end
local function playedOnAll(file)
    local n = 0
    eachPeer(function(p) if count(p, "Play", file) == 1 then n = n + 1 end end)
    return n
end

local function runTo(t, dt) run(t - now, dt) end
local extra = 0
local function spawn(odf, team, x, z)
    extra = extra + 1
    local h = "extra" .. extra
    newObject(h, odf, team, {x or 100000, 20, z or 100000})
    return h
end
local function onAll(fn) local n = 0; eachPeer(function(p) if fn(p) then n = n + 1 end end); return n end

local function count2(peer, name, a, b)
    local n = 0
    for _, c in ipairs(peer.calls) do if c[1] == name and c[2] == a and c[3] == b then n = n + 1 end end
    return n
end
local ROUTE = {{3660.3, 31, 100474}, {3300, 25, 100050}, {2885.6, 14.2, 99661.1}}
local MUF, CUT, GEYSER = {2991.2, 14.6, 100939}, {2885.6, 14.2, 99661.1}, {3680.5, 31.3, 100517}
local function at(h, p, dx, dz) place(h, p[1] + (dx or 0), p[2], p[3] + (dz or 0)) end
local function escortOf(s)
    local set = {}
    for _, key in ipairs({"convoy1", "convoy2", "convoy3", "convoy4", "convoy5", "convoy6", "convoy7", "convoy8"}) do set[s[key]] = true end
    for _, h in ipairs(s.convoy_extra or {}) do set[h] = true end
    return set
end
-- Spawns the convoy at once and runs until the CCA tug holds the relic and the convoy has started.
local function convoySession(humans, network)
    local host, guests = session(network ~= false, humans)
    local s = host.state
    runTo(25) -- the opening shot (22 s) is over, as it is 1300 s into the real mission
    s.third_warning_time = 0
    run(1)
    check(s.third_warning and s.relic, "the convoy spawned")
    run(3)
    check(s.relic_seized and s.convoy_started, "the CCA tug seized the relic and the convoy started")
    return host, guests, s
end

-- ============================================================ 1. startup, teams, ownership
do
    local host, guests = session(true)
    local s = host.state
    check(s.start_done and s.start_camera1, "the leader starts the mission body")
    for _, g in ipairs(guests) do
        check(not g.state.start_done and count(g, "BuildObject") == 0, "guests never run the mission body")
        check(count(g, "DisableStartingRecycler") == 1, "guests disable the extra starting recycler")
    end
    check(count(host, "DisableStartingRecycler") == 1, "the leader disables the extra starting recycler too")
    check(host.rally and host.rally[0] == "avmuf", "respawn rally is the Unit Factory (avmuf)")
    for _, g in ipairs(guests) do check(g.rally and g.rally[0] == "avmuf", "guests rally at the Unit Factory") end
    check(count(host, "SetAIControl", 5) == 1 and last(host, "SetAIControl")[3] == true, "strategic AI is configured for the CCA team")
    check(count(host, "SetScrap", 5) == 1 and last(host, "SetScrap")[3] == 40 and count(host, "SetPilot", 5) == 1,
        "CCA scrap and pilots go to team 5")
    check(count(host, "SetScrap", 2) == 0 and count(host, "SetPilot", 2) == 0, "nothing is configured on guest team 2")
    check(count(host, "Ally") >= 12 and count(host, "UnAlly") >= 8, "alliances configured")
    for _, g in ipairs(guests) do
        check(count(g, "SetObjectiveName", "cam1") == 1 and last(g, "SetObjectiveName")[3] == "Choke Point",
            "the Nav 1 name arrives by label on every guest")
        check(count(g, "CameraPath") > 0 and last(g, "CameraPath")[2] == "camera_circle" and last(g, "CameraPath")[5] == "key_scrap",
            "the opening shot reaches every guest, aimed at the scrap field by label")
    end
    run(5)
    check(playedOnAll("misn0900.wav") == 4, "the opening briefing plays on every peer")
    eachPeer(function(p) check(count(p, "AddObjective", "misn0900.otf") == 1, "the objective reaches every peer") end)
    run(20)
    check(s.player_camera_off, "the opening shot ends on the DLL timer for everyone")
    allBuildTeams(host)
end

-- ============================================================ 2. any-player triggers
do
    -- rendezvous: any player within 70 m of the factory
    local host, guests = session(true)
    local s = host.state
    run(5)
    check(s.muf_gobaby, "the factory is released after the briefing")
    at(guests[2].player, MUF, 70.2, 0)
    run(2)
    check(not s.muf_contact, "70 m and beyond does not trigger the rendezvous")
    at(guests[2].player, MUF, 69, 0)
    run(2)
    check(s.muf_contact and playedOnAll("misn0905.wav") == 4, "a guest within 70 m triggers the factory report for everyone")
    check(count(host, "SetScrap", 1) == 1 and world.scrap[1] == 20 and count(host, "SetPilot", 1) == 1,
        "the shared base's 20 scrap and 7 pilots are set once, on the host team")
    for _, g in ipairs(guests) do
        check(count(g, "SetScrap") == 0 and count(g, "SetPilot") == 0, "no per-guest scrap or pilots")
    end
    -- 0914: Nav 1 within 100 m of any player
    s.recon_message_time = 0
    s.recon_artil = true
    at(guests[1].player, {2900.4, 14.1, 99640.5}, 100.2, 0)
    run(3)
    check(not s.base_warning, "100 m and beyond from Nav 1 does not warn")
    at(guests[1].player, {2900.4, 14.1, 99640.5}, 60, 0)
    run(3)
    check(s.base_warning and playedOnAll("misn0914.wav") == 4, "a guest at Nav 1 plays the base warning for everyone")
end
do
    -- 0914 via a CCA fighter within 400 m of any player
    local host, guests = session(true)
    local s = host.state
    local fighter = spawn("svfigh", 5, 2000, 99000)
    host.env.AddObject(fighter)
    check(s.cca5 == fighter, "the CCA fighter fills the fighter slot")
    s.recon_message_time = 0
    s.recon_artil = true
    at(guests[3].player, {2000, 20, 99000}, 399, 0)
    run(3)
    check(s.base_warning, "a guest within 400 m of a CCA fighter triggers the warning")
end
do
    -- the convoy waits while any player is within 500 m of the convoy geyser
    local host, guests = session(true)
    local s = host.state
    s.third_warning_time = 0
    at(guests[2].player, GEYSER, 400, 0)
    run(1)
    check(not s.third_warning and built(host, "obdata") == 0, "a guest near the geyser defers the convoy")
    check(s.third_warning_time > now and s.third_warning_time < now + 12, "the DLL's eleven-second retry")
    at(guests[2].player, GEYSER, 499.8, 0)
    run(12)
    check(not s.third_warning, "just inside 500 m still blocks")
    at(guests[2].player, GEYSER, 500.5, 0)
    run(12)
    check(s.third_warning and built(host, "obdata") == 1, "the convoy spawns once no player is within 500 m")
end
do
    -- Charon: any player within 70 m, then the IsInfo relay from a guest
    local host, guests = session(true)
    local s = host.state
    s.charon_check = 0
    at(guests[1].player, {2547, 100.9, 99820.6}, 70.2, 0)
    run(3)
    check(not s.charon_found, "70 m and beyond does not find the Charon")
    at(guests[1].player, {2547, 100.9, 99820.6}, 50, 0)
    run(3)
    check(s.charon_found and playedOnAll("misn0915.wav") == 4, "a guest finds the Charon for everyone")
    check(not s.charon_build, "the beacon waits for the info panel")
    guests[3].info = {hbchar = true}
    run(2)
    check(s.charon_build and playedOnAll("misn0916.wav") == 4, "a guest's Charon info selection is relayed to the leader")
    local nav = s.charon_nav
    check(nav and objects[nav].odf == "apcamr" and objects[nav].team == 1, "the nav beacon is built on the host team")
    for _, g in ipairs(guests) do
        check(count(g, "SetObjectiveName") >= 2 and last(g, "SetObjectiveName")[3] == "Alien Relic", "the beacon name reaches every guest")
    end
    eachPeer(function(p) check(count(p, "BuildObject", nav) == 0 or p == host, "only the leader builds") end)
    local host2, guests2 = session(true)
    host2.state.charon_check = 0
    at(guests2[1].player, {2547, 100.9, 99820.6}, 50, 0)
    run(5)
    check(host2.state.charon_found and not host2.state.charon_build, "no report, no beacon")
end

-- ============================================================ 3. team remaps, relic, AddObject filter
do
    local host, guests, s = convoySession(4)
    check(objects[s.relic].team == 0 and objects[s.relic].odf == "obdata", "the relic is neutral, not a guest team")
    check(objects[s.ccatug].team == 5 and objects[s.ccatug].odf == "svhaul", "the tug is a CCA unit")
    for _, call in ipairs(callsOf(host, "BuildObject")) do
        if call[3]:find("^sv") then check(call[4] == 5, "CCA spawns on team 5: " .. call[3]) end
    end
    check(count(host, "SetAIP", "misn09.aip") == 0 and count(host, "SetAIP", "misn09b.aip") == 1 and last(host, "SetAIP")[3] == 5,
        "the convoy AIP runs on the CCA team")
    for _, g in ipairs(guests) do check(count(g, "BuildObject") == 0 and count(g, "SetAIP") == 0, "guests spawn and command nothing") end
    allBuildTeams(host)
    -- AddObject filter
    local function add(odf, team) local h = spawn(odf, team); host.env.AddObject(h); return h end
    local s2 = session(true).state
    local h2 = peers[10]
    local function add2(odf, team) local h = spawn(odf, team); h2.env.AddObject(h); return h end
    add2("svturr", 2)
    check(s2.cca1 == nil, "a guest-team svturr is not a CCA turret")
    local turret = add2("svturr", 5)
    check(s2.cca1 == turret, "a CCA turret is tracked")
    add2("avwalk", 5)
    check(s2.nsdfgech1 == nil, "a CCA avwalk is not the player's walker")
    local walker = add2("avwalk", 3)
    check(s2.nsdfgech1 == walker, "a guest team's walker is tracked")
    add2("absilo", 5)
    check(s2.avsilo == nil, "a CCA silo is not the player's silo")
end

-- ============================================================ 4. a guest-held relic is secure
do
    local host, guests = session(true)
    local s = host.state
    s.third_warning_time = 0
    tick(0.25)
    check(s.third_warning and s.relic_free, "the convoy spawned and the relic is free")
    objects[s.ccatug].alive = false -- keep the CCA tug from grabbing it first
    local guestTug = spawn("avhaul", 3)
    world.cargo[s.relic] = guestTug
    run(1)
    check(s.relic_secure and not s.relic_seized and s.tugger == guestTug, "a tug on a guest team secures the relic")
    check(not s.convoy_started, "the convoy does not start")
end

-- ============================================================ 5. convoy scaling at 1-4 players
for humans = 1, 4 do
    local host, guests, s = convoySession(humans)
    local extras = humans - 1
    check(built(host, "svfigh") == 4 + extras and built(host, "svtank") == 4 + extras,
        humans .. " players: 4 fighters and 4 tanks plus one of each per extra human")
    check(built(host, "svapc") == 2 and built(host, "svhaul") == 1 and built(host, "obdata") == 1, humans .. " players: APCs, tug and relic unchanged")
    check(#(s.convoy_extra or {}) == 2 * extras, humans .. " players: extras tracked")
    for _, unit in ipairs(s.convoy_extra or {}) do
        check(objects[unit].team == 5 and (objects[unit].odf == "svtank" or objects[unit].odf == "svfigh"), "extras are CCA tanks and fighters")
        check(count(host, "Defend", unit) == 1 and count2(host, "Follow", unit, s.ccatug) == 1, "extras defend, then follow the tug")
    end
    for _, g in ipairs(guests) do check(count(g, "BuildObject") == 0, "guests never spawn the convoy") end
    allBuildTeams(host)
end

-- ============================================================ 6. Prescott's platoon
local PRESCOTT_COUNT = 5 -- always, at any player count
for humans = 1, 4 do
    local host, guests, s = convoySession(humans)
    run(8)
    check(playedOnAll("misn0903.wav") == humans, "the stock cutoff warning plays at the DLL's time, unchanged by the platoon")
    check(s.prescott == nil, humans .. " players: no platoon while the convoy is far from the cutoff")
    at(s.ccatug, CUT, 0, 351)
    run(1)
    check(s.prescott == nil, "351 m is outside the trigger")
    at(s.ccatug, CUT, 0, 349)
    run(0.5)
    check(s.prescott and not s.prescott.spawned, "the platoon is armed inside 350 m")
    local armed = s.prescott.due - 45
    check(armed <= now and armed > now - 2, "the delay is 45 s from the moment the lead came in range")
    runTo(s.prescott.due - 1)
    check(not s.prescott.spawned and built(host, "avtank") == 0, "players get their first crack: nothing before 45 s")
    local escort = escortOf(s)
    local escortCount = 0
    for _ in pairs(escort) do escortCount = escortCount + 1 end
    check(escortCount == 8 + 2 * (humans - 1), "the escort is the combat units")
    -- Lay the convoy out along its route: convoy1 is the rearmost living unit, on route point 2,
    -- everything else is up the road near the cutoff. The route runs spawn -> cutoff.
    world.route = {vec(ROUTE[1]), vec(ROUTE[2]), vec(ROUTE[3])}
    for handle in pairs(escort) do place(handle, CUT[1] + 40, CUT[2], CUT[3] + 40) end
    place(s.ccatug, CUT[1], CUT[2], CUT[3] + 300)
    place(s.convoy9, CUT[1], CUT[2], CUT[3] + 300)
    place(s.convoy0, CUT[1], CUT[2], CUT[3] + 300)
    place(s.convoy1, ROUTE[2][1], ROUTE[2][2], ROUTE[2][3])
    local p1, p0 = world.route[2], world.route[1]
    local seg = planar(p1, p0)
    local want = {x = p1.x + (p0.x - p1.x) * 250 / seg, z = p1.z + (p0.z - p1.z) * 250 / seg}
    for _ = 1, 20 do tick(); if s.prescott.spawned then break end end
    check(s.prescott.spawned and built(host, "avtank") == PRESCOTT_COUNT, humans .. " players: the platoon is " .. PRESCOTT_COUNT .. " tanks")
    check(#s.prescott.units == PRESCOTT_COUNT, "handles are kept in the saved state")
    local cx, cz = 0, 0
    for i, unit in ipairs(s.prescott.units) do
        local o = objects[unit]
        check(o.team == 7 and o.odf == "avtank" and o.perceived == 1, "an allied avtank perceived as NSDF")
        cx, cz = cx + o.pos.x, cz + o.pos.z
        for _, name in ipairs({"spawn1", "spawn2", "spawn3", "spawn4"}) do
            check(planar(o.pos, pathPos[name]) > 100, "not spawned on " .. name .. " (the convoy's origin)")
        end
        check(o.pos.y == terrain(o.pos.x, o.pos.z), "y is the terrain height")
        if i > 1 then
            check(math.abs(planar(o.pos, objects[s.prescott.units[i - 1]].pos) - 20) < 1, "tanks are spread 20 m apart")
        end
        check(count(host, "SetIndependence", unit) == 1 and count(host, "Attack", unit) >= 1, "ordered at once, on orders only")
    end
    cx, cz = cx / #s.prescott.units, cz / #s.prescott.units
    check(planar({x = cx, z = cz}, want) < 20, "the platoon is centred 250 m back along the route from the rear unit")
    check(planar({x = cx, z = cz}, objects[s.convoy1].pos) > 200 and planar({x = cx, z = cz}, objects[s.convoy1].pos) < 300,
        "about 250 m behind the rear unit")
    for _, g in ipairs(guests) do check(count(g, "BuildObject", "avtank") == 0, "guests never spawn the platoon") end
    tick()
    check(#host.venus.forces == 1 and host.venus.forces[1][1] == 5 and host.venus.forces[1][2] == 60.0,
        "the platoon's arrival bursts the storm to level 5, once")
    local relic, pad = s.relic, s.ccalaunch
    local fullTug, fullApc = objects[s.ccatug].hp, objects[s.convoy9].hp
    run(150)
    local platoon = {}
    for _, unit in ipairs(s.prescott.units) do platoon[unit] = true end
    local attacks = 0
    for _, c in ipairs(callsOf(host, "Attack")) do
        if platoon[c[2]] then
            attacks = attacks + 1
            check(escort[c[3]], "the platoon only ever targets a convoy combat unit, never " .. tostring(c[3]))
        end
    end
    check(attacks >= PRESCOTT_COUNT, "the platoon attacked")
    for handle in pairs(escort) do check(not objects[handle].alive, "the escort was destroyed") end
    check(objects[s.ccatug].alive and objects[s.ccatug].hp == fullTug, "the tug carrying the relic is never touched")
    check(objects[relic].alive and objects[relic].hp == 1000 and objects[pad].alive and objects[pad].hp == 5000,
        "neither the relic nor the launch pad is touched")
    check(objects[s.convoy9].hp == fullApc, "APCs are not combat targets")
    for _, unit in ipairs(s.prescott.units) do
        check(count(host, "Stop", unit) == 1, "with no combat target left the platoon holds, once, and never falls back to the tug")
    end
    check(#host.venus.forces == 1, "the burst fires once")
    allBuildTeams(host)
end
do
    -- retargeting: when its target dies a unit takes the nearest surviving escort unit
    local host, guests, s = convoySession(2)
    at(s.ccatug, CUT, 0, 340)
    run(0.5)
    runTo(s.prescott.due + 0.3)
    local unit = s.prescott.units[1]
    check(s.prescott.spawned and s.prescott.orders[1], "unit 1 has an order")
    local first = s.prescott.orders[1]
    world.combat = false
    objects[first].alive = false
    run(5)
    local second = s.prescott.orders[1]
    check(second and second ~= first and objects[second].alive and escortOf(s)[second], "a dead target is replaced by a living escort unit")
    local attacks = 0
    for _, c in ipairs(callsOf(host, "Attack")) do if c[2] == unit then attacks = attacks + 1 end end
    check(attacks == 2, "unit 1 was ordered twice: once per target (no per-cycle re-issue)")
end
do
    -- no usable route: the rear unit's position minus its facing times 250
    local host, guests, s = convoySession(1)
    at(s.ccatug, CUT, 0, 340)
    run(0.5)
    world.route = nil
    for handle in pairs(escortOf(s)) do place(handle, CUT[1], CUT[2], CUT[3] + 40) end
    place(s.convoy9, CUT[1], CUT[2], CUT[3] + 60)
    place(s.convoy0, CUT[1], CUT[2], CUT[3] + 60)
    place(s.convoy4, CUT[1] + 900, CUT[2], CUT[3] + 900)
    objects[s.convoy4].front = {x = 0, y = 0, z = 1}
    for _ = 1, 400 do tick(); if s.prescott.spawned then break end end
    check(s.prescott.spawned and #s.prescott.units == 5, "the facing fallback spawns the platoon")
    local o = objects[s.prescott.units[3]]
    check(math.abs(o.pos.x - (objects[s.convoy4].pos.x)) < 25 and math.abs(o.pos.z - (objects[s.convoy4].pos.z - 250)) < 25,
        "fallback: rear position minus facing times 250")
end
do
    -- a tug that dies still lets the nearest living escort unit mark the convoy's lead
    local host, guests, s = convoySession(1)
    objects[s.ccatug].alive = false
    at(s.convoy1, CUT, 0, 200)
    for _, key in ipairs({"convoy2", "convoy3", "convoy4", "convoy5", "convoy6", "convoy7", "convoy8"}) do at(s[key], GEYSER, 0, 0) end
    run(1)
    check(s.prescott ~= nil, "the lead falls back to an escort unit when the tug is dead")
end
do
    -- the platoon needs the convoy to have started and the mission to be live
    local host, guests = session(true)
    local s = host.state
    run(5)
    check(s.prescott == nil and built(host, "avtank") == 0, "no platoon before the convoy exists")
end

-- ============================================================ 6b. Prescott: leader, pre-destroyed convoy, drive-in, victory
local PAD = LABELS.launchpad.pos
local CONVOY_KEYS = {"ccatug", "convoy1", "convoy2", "convoy3", "convoy4", "convoy5", "convoy6", "convoy7", "convoy8", "convoy9", "convoy0"}
local function killConvoy(s)
    for _, key in ipairs(CONVOY_KEYS) do
        if s[key] and objects[s[key]] then objects[s[key]].alive = false end
    end
    for _, h in ipairs(s.convoy_extra or {}) do objects[h].alive = false end
end
-- Lays the convoy out along the route (convoy1 rearmost on route point 2) and lets the stored rear settle.
local function layOutConvoy(s)
    world.route = {vec(ROUTE[1]), vec(ROUTE[2]), vec(ROUTE[3])}
    for handle in pairs(escortOf(s)) do place(handle, CUT[1] + 40, CUT[2], CUT[3] + 40) end
    place(s.ccatug, CUT[1], CUT[2], CUT[3] + 300)
    place(s.convoy9, CUT[1], CUT[2], CUT[3] + 300)
    place(s.convoy0, CUT[1], CUT[2], CUT[3] + 300)
    place(s.convoy1, ROUTE[2][1], ROUTE[2][2], ROUTE[2][3])
end
local function behindRoute(from, to)
    local seg = planar({x = from[1], z = from[3]}, {x = to[1], z = to[3]})
    return {x = from[1] + (to[1] - from[1]) * 250 / seg, z = from[3] + (to[3] - from[3]) * 250 / seg}
end
local function centroid(s)
    local cx, cz = 0, 0
    for _, unit in ipairs(s.prescott.units) do cx, cz = cx + objects[unit].pos.x, cz + objects[unit].pos.z end
    return {x = cx / #s.prescott.units, z = cz / #s.prescott.units}
end
-- A live platoon (spawned the normal way), nothing dying in combat, convoy still alive.
local function livePlatoon(humans)
    local host, guests, s = convoySession(humans)
    at(s.ccatug, CUT, 0, 340)
    run(0.5)
    layOutConvoy(s)
    world.combat = false
    runTo(s.prescott.due + 0.5)
    check(s.prescott.spawned, "platoon spawned")
    return host, guests, s
end

for humans = 1, 4 do
    -- one leader, highlighted and named for every peer, and un-highlighted when he dies
    local host, guests, s = livePlatoon(humans)
    run(3)
    local leader = s.prescott.leader
    check(leader == s.prescott.units[3] and objects[leader].alive, humans .. " players: the middle tank is Commander Prescott")
    check(#s.prescott.units == 5, humans .. " players: still five tanks")
    check(count(host, "SetObjectiveOn", leader) == 1 and count2(host, "SetObjectiveName", leader, "Commander Prescott") == 1,
        "the leader highlights and names Prescott")
    for _, g in ipairs(guests) do
        check(count(g, "SetObjectiveOn", leader) == 1 and count2(g, "SetObjectiveName", leader, "Commander Prescott") == 1,
            "every guest gets the highlight and the name through the presentation stream")
    end
    for _, unit in ipairs(s.prescott.units) do
        if unit ~= leader then check(count(host, "SetObjectiveOn", unit) == 0, "only Prescott is highlighted") end
    end
    check(count(host, "SetObjectiveOff", leader) == 0, "alive: not cleared")
    objects[leader].alive = false
    run(1)
    check(count(host, "SetObjectiveOff", leader) == 1, "the highlight is cleared when Prescott dies")
    run(5)
    check(count(host, "SetObjectiveOff", leader) == 1, "and only once")
    allBuildTeams(host)
end

do
    -- the convoy dies before the platoon was armed: it still spawns, after the short delay, behind the last rear
    local host, guests, s = convoySession(2)
    layOutConvoy(s)
    place(s.ccatug, ROUTE[2][1] - 50, ROUTE[2][2], ROUTE[2][3]) -- far from the cutoff: never armed
    for handle in pairs(escortOf(s)) do place(handle, CUT[1] + 40, CUT[2], CUT[3] + 40) end
    place(s.convoy9, CUT[1] + 40, CUT[2], CUT[3] + 40)
    place(s.convoy0, CUT[1] + 40, CUT[2], CUT[3] + 40)
    place(s.convoy1, ROUTE[2][1], ROUTE[2][2], ROUTE[2][3])
    run(1)
    check(s.prescott == nil, "never armed: the convoy is far from the cutoff")
    check(s.convoy_rear and math.abs(s.convoy_rear.x - ROUTE[2][1]) < 1, "the last known rear is stored while the convoy lives")
    world.combat = false
    killConvoy(s)
    local died = now
    run(1)
    check(s.prescott and not s.prescott.spawned and s.prescott.destroyed, "a dead convoy still arms the platoon")
    check(math.abs(s.prescott.due - (died + 10)) < 1.5, "after the short 10 s delay, not the 45 s wait")
    runTo(died + 8)
    check(built(host, "avtank") == 0, "nothing before the delay")
    runTo(died + 11.5)
    check(s.prescott.spawned and built(host, "avtank") == 5, "five tanks spawn 10 s after the convoy died")
    check(now - died < 20, "well inside the 45 s wait")
    local want = behindRoute(ROUTE[2], ROUTE[1])
    check(planar(centroid(s), want) < 20, "spawned 250 m back along the route from the last known rear")
    check(s.prescott.driveStart ~= nil and #callsOf(host, "Attack") == 0, "and it drives in: no hunting orders at all")
    check(count(host, "SetObjectiveOn", s.prescott.leader) == 1, "Prescott is marked in this path too")
    allBuildTeams(host)
end
do
    -- armed (45 s pending) and then the convoy dies: the wait collapses to the short delay
    local host, guests, s = convoySession(1)
    at(s.ccatug, CUT, 0, 340)
    run(0.5)
    layOutConvoy(s)
    world.combat = false
    local due = s.prescott.due
    run(5)
    killConvoy(s)
    local died = now
    run(1)
    check(s.prescott.due < due - 20 and math.abs(s.prescott.due - (died + 10)) < 1.5, "an armed platoon's wait drops to ~10 s")
    runTo(died + 11.5)
    check(s.prescott.spawned and built(host, "avtank") == 5, "and it spawns")
end
do
    -- no rear was ever stored: the route point nearest the cutoff geyser, 250 m back along it
    local host, guests, s = convoySession(1)
    world.route = {vec(ROUTE[1]), vec(ROUTE[2]), vec(ROUTE[3])}
    world.combat = false
    s.convoy_rear = nil
    killConvoy(s)
    run(1)
    s.convoy_rear = nil
    runTo(now + 12)
    check(s.prescott.spawned, "spawned without a stored rear")
    check(planar(centroid(s), behindRoute(ROUTE[3], ROUTE[2])) < 20, "fallback: 250 m back from the route point nearest the geyser")
end

do
    -- drive-in: hunting stops, Prescott goes to the nearest living human, the rest follow him
    local host, guests, s = livePlatoon(3)
    local leader, units = s.prescott.leader, s.prescott.units
    local before = #callsOf(host, "Attack")
    check(before >= 5, "hunting while the convoy lives")
    place("player20", 4000, 20, 100000)
    killConvoy(s)
    run(1)
    check(#callsOf(host, "Attack") == before, "no hunting order once the convoy is destroyed")
    local gotoLeader = {}
    for _, c in ipairs(callsOf(host, "Goto")) do if c[2] == leader then gotoLeader[#gotoLeader + 1] = c end end
    check(#gotoLeader == 1 and gotoLeader[1][3] == "player20", "Prescott drives to the nearest living human")
    for _, unit in ipairs(units) do
        if unit ~= leader then check(count2(host, "Follow", unit, leader) == 1, "the others follow Prescott") end
    end
    run(8.5)
    local n = 0
    for _, c in ipairs(callsOf(host, "Goto")) do if c[2] == leader then n = n + 1 end end
    check(n >= 3, "the Goto is re-issued every few seconds (" .. n .. ")")
    -- the nearest human changes: the re-issue follows
    place("player20", 100000, 20, 100000)
    place("player30", 4000, 20, 100000)
    run(5)
    check(last(host, "Goto")[3] == "player30", "re-targeted to the new nearest human")
end

do
    -- launch pad safety: a human beside the pad gets a standoff point, never the pad itself
    local host, guests, s = livePlatoon(2)
    local leader, units = s.prescott.leader, s.prescott.units
    place("player10", PAD[1] + 60, PAD[2], PAD[3] + 0)
    place("player20", 100000, 20, 100000)
    killConvoy(s)
    run(1)
    local g
    for _, c in ipairs(callsOf(host, "Goto")) do if c[2] == leader then g = c end end
    check(g and type(g[3]) == "table", "a human inside 150 m of the pad gets a point, not a handle")
    check(math.abs(planar(g[3], {x = PAD[1], z = PAD[3]}) - 150) < 1, "the point is 150 m from the pad")
    check(g[3].x > PAD[1] + 100 and math.abs(g[3].z - PAD[3]) < 5, "on the human's side of the pad")
    run(10)
    for _, unit in ipairs(units) do
        for _, c in ipairs(callsOf(host, "Goto")) do
            if c[2] == unit and type(c[3]) == "table" then
                check(planar(c[3], {x = PAD[1], z = PAD[3]}) >= 149, "no tank is ever sent closer than 150 m to the pad")
            end
        end
    end
    -- a human just outside 150 m is driven to directly
    place("player10", PAD[1] + 160, PAD[2], PAD[3])
    run(5)
    local late
    for _, c in ipairs(callsOf(host, "Goto")) do late = c end
    check(late[3] == "player10", "a human at 160 m is driven to directly")
end

do
    -- no order from the platoon ever names the pad, the tug, an APC or the relic
    local host, guests, s = convoySession(2)
    at(s.ccatug, CUT, 0, 340)
    run(0.5)
    layOutConvoy(s)
    local forbidden = {[s.ccalaunch] = true, [s.ccatug] = true, [s.convoy9] = true, [s.convoy0] = true, [s.relic] = true}
    local platoon
    runTo(s.prescott.due + 0.5)
    platoon = {}
    for _, unit in ipairs(s.prescott.units) do platoon[unit] = true end
    place("player10", PAD[1] + 30, PAD[2], PAD[3])
    run(120) -- the fight, then the convoy being destroyed by the platoon or by us
    killConvoy(s)
    run(30)
    local orders = 0
    for _, name in ipairs({"Attack", "Goto", "Follow", "Pickup", "Dropoff", "Retreat", "Patrol", "Defend"}) do
        for _, c in ipairs(callsOf(host, name)) do
            if platoon[c[2]] then
                orders = orders + 1
                check(not forbidden[c[3]], name .. " never names the pad, tug, APC or relic: " .. tostring(c[3]))
            end
        end
    end
    check(orders > 10, "orders were actually issued (" .. orders .. ")")
    for _, unit in ipairs(s.prescott.units) do
        check(count(host, "SetIndependence", unit) == 1, "non-autonomous: independence set once")
    end
    check(objects[s.ccalaunch].alive and objects[s.ccalaunch].hp == 5000, "the pad is untouched")
end

do
    -- victory on arrival within 60 m of any human; relic alive; one win on every peer
    local host, guests, s = livePlatoon(3)
    local leader = s.prescott.leader
    place("player20", 95000, 20, 100000)
    place("player30", 99000, 20, 100000)
    check(not s.game_over, "no win while the convoy lives")
    objects[leader].pos = {x = objects.player10.pos.x + 30, y = 20, z = objects.player10.pos.z}
    run(2)
    check(not s.game_over and onAll(function(p) return count(p, "SucceedMission") == 0 end) == 3, "close to a human but the convoy still lives: no win")
    killConvoy(s)
    objects[leader].pos = {x = objects.player10.pos.x + 70, y = 20, z = objects.player10.pos.z}
    run(0.25) -- one tick: the Goto it is given has not moved it yet
    check(not s.game_over, "70 m is outside the 60 m arrival")
    objects[leader].pos = {x = objects.player10.pos.x + 55, y = 20, z = objects.player10.pos.z}
    run(0.25)
    check(s.game_over, "within 60 m of a human wins")
    run(5)
    eachPeer(function(p)
        check(count(p, "SucceedMission") == 1 and last(p, "SucceedMission")[3] == "misn09w1.des", "the stock win debrief reaches every peer once")
        check(count(p, "FailMission") == 0, "no failure")
        check(count(p, "Play", "misn0909.wav") == 1, "the stock win line plays once")
    end)
    check(host.venus.targets[#host.venus.targets] == 1, "the win calms the storm")
    -- latch: every other trigger arrives afterwards and also the stock relic win
    objects[leader].alive = false
    s.relic_seized = false
    s.win_check = 0
    place(s.relic, MUF[1] + 50, MUF[2], MUF[3])
    run(200)
    eachPeer(function(p)
        check(count(p, "SucceedMission") == 1 and count(p, "Play", "misn0909.wav") == 1, "single win latch")
        check(count(p, "FailMission") == 0, "and still no failure")
    end)
end

do
    -- Prescott dead: before the convoy is destroyed (win the moment it is) ...
    local host, guests, s = livePlatoon(2)
    objects[s.prescott.leader].alive = false
    run(6)
    check(not s.game_over, "Prescott dead alone does not win while the convoy lives")
    killConvoy(s)
    run(8)
    check(s.game_over and onAll(function(p) return count(p, "SucceedMission") == 1 end) == 2, "Prescott dead, convoy destroyed: win")
end
do
    -- ... and after
    local host, guests, s = livePlatoon(2)
    killConvoy(s)
    run(1)
    check(not s.game_over, "driving in, nobody there yet")
    objects[s.prescott.leader].alive = false
    run(8)
    check(s.game_over and onAll(function(p) return count(p, "SucceedMission") == 1 end) == 2, "Prescott dies while driving in: win")
end
do
    -- the whole platoon dead
    local host, guests, s = livePlatoon(1)
    killConvoy(s)
    run(1)
    check(not s.game_over, "still driving in")
    for _, unit in ipairs(s.prescott.units) do objects[unit].alive = false end
    run(8)
    check(s.game_over and count(host, "SucceedMission") == 1, "the whole platoon dead: win")
end
do
    -- timeout: 120 s after the drive-in starts, Prescott never arrives
    local host, guests, s = livePlatoon(2)
    killConvoy(s)
    run(1)
    local start = s.prescott.driveStart
    check(start and start <= now, "the drive-in clock started")
    runTo(start + 118)
    check(not s.game_over, "no win before the timeout")
    runTo(start + 122)
    check(s.game_over, "the timeout wins")
    run(8)
    check(count(host, "SucceedMission") == 1, "and publishes the result")
    run(30)
    check(count(host, "SucceedMission") == 1, "once")
end
do
    -- the pre-destroyed path times out from the spawn
    local host, guests, s = convoySession(1)
    world.route = {vec(ROUTE[1]), vec(ROUTE[2]), vec(ROUTE[3])}
    world.combat = false
    killConvoy(s)
    runTo(now + 12)
    check(s.prescott.spawned and not s.game_over, "pre-destroyed platoon is driving in")
    local start = s.prescott.driveStart
    runTo(start + 118)
    check(not s.game_over, "not yet")
    runTo(start + 122)
    run(8)
    check(s.game_over and count(host, "SucceedMission") == 1, "and it times out into a win")
end
do
    -- a destroyed relic still fails, and Prescott's win never pre-empts it
    local host, guests, s = livePlatoon(2)
    -- Prescott is already beside a human, so only the relic guard stands between him and a win
    objects[s.prescott.leader].pos = {x = objects.player10.pos.x + 20, y = 20, z = objects.player10.pos.z}
    objects[s.relic].alive = false
    killConvoy(s)
    run(20)
    eachPeer(function(p)
        check(count(p, "FailMission") == 1 and last(p, "FailMission")[3] == "misn09f1.des", "relic destroyed fails everyone once")
        check(count(p, "SucceedMission") == 0, "and Prescott does not win it")
    end)
end
do
    -- losing the Unit Factory or the pad still fails with the convoy gone
    local host, guests, s = livePlatoon(1)
    objects.avmuf.alive = false
    killConvoy(s)
    run(20)
    check(count(host, "FailMission") == 1 and last(host, "FailMission")[3] == "misn09f3.des" and count(host, "SucceedMission") == 0,
        "factory lost still fails")
end

-- ============================================================ 7. restored cut radio
do
    local host, guests = session(true)
    local s = host.state
    run(3)
    local function built1(odf, team, x, z)
        local h = spawn(odf, team, x, z)
        host.env.AddObject(h)
        for _, g in ipairs(guests) do g.env.AddObject(h) end
        return h
    end
    built1("avscav", 1, MUF[1] + 20, MUF[3])
    run(2)
    check(playedOnAll("misn0917.wav") == 0, "a scavenger is not a combat unit")
    built1("avtank", 5, MUF[1] + 20, MUF[3])
    built1("avtank", 7, MUF[1] + 20, MUF[3])
    run(2)
    check(playedOnAll("misn0917.wav") == 0, "enemy and allied units are not the player's")
    built1("avtank", 1, MUF[1] + 500, MUF[3])
    run(2)
    check(playedOnAll("misn0917.wav") == 0, "a unit far from the factory was not built from it")
    built1("avtank", 1, MUF[1] + 30, MUF[3])
    run(2)
    check(playedOnAll("misn0917.wav") == 4, "Collins scolds a human unit built from the factory while the artillery stands")
    built1("avtank", 1, MUF[1] + 30, MUF[3])
    built1("avltnk", 3, MUF[1] + 30, MUF[3])
    run(3)
    check(playedOnAll("misn0917.wav") == 4 and count(host, "Play", "misn0917.wav") == 1, "misn0917 plays once")
    check(playedOnAll("misn0910.wav") == 0, "a tank is not a walker")
end
do
    -- 0917 does not play once all six artillery are dead
    local host = session(true)
    local s = host.state
    for i = 1, 6 do objects["artil" .. i].alive = false end
    run(2)
    check(s.objective1, "the artillery is down")
    local h = spawn("avtank", 1, MUF[1] + 30, MUF[3]); host.env.AddObject(h)
    run(3)
    check(count(host, "Play", "misn0917.wav") == 0, "no scolding after the artillery is down")
end
do
    -- 0910: a walker built far from the cutoff geyser (1282 m from the factory)
    local host, guests = session(true)
    local s = host.state
    run(3)
    local near1 = spawn("avwalk", 1, CUT[1] + 100, CUT[3] + 500) -- 510 m from the geyser, but not near the factory
    host.env.AddObject(near1)
    run(2)
    check(playedOnAll("misn0910.wav") == 0, "a walker not built at the factory does not count")
    -- relocate the factory next to the cutoff: a walker built there is not "too slow"
    place("avmuf", CUT[1] + 200, CUT[2], CUT[3] + 100)
    local close = spawn("avwalk", 1, CUT[1] + 200, CUT[3] + 130); host.env.AddObject(close)
    run(2)
    check(playedOnAll("misn0910.wav") == 0, "a walker built within 600 m of the cutoff geyser is on time")
    check(playedOnAll("misn0917.wav") == 4, "(the walker is still a combat unit built before the artillery fell)")
    place("avmuf", MUF[1], MUF[2], MUF[3])
    local slow = spawn("avwalk", 1, MUF[1] + 20, MUF[3]); host.env.AddObject(slow)
    run(3)
    check(playedOnAll("misn0910.wav") == 4, "Sasquatch warns when the walker is built more than 600 m from the cutoff geyser")
    local slow2 = spawn("avwalk", 1, MUF[1] + 20, MUF[3]); host.env.AddObject(slow2)
    run(3)
    check(count(host, "Play", "misn0910.wav") == 1, "misn0910 plays once")
    check(count(host, "Play", "misn0912.wav") == 0, "the duplicate briefing 0912 stays cut")
end
do
    -- both lines due together play one after the other, each once
    local host, guests = session(true)
    run(3)
    local walker = spawn("avwalk", 1, MUF[1] + 20, MUF[3]); host.env.AddObject(walker)
    run(4)
    check(playedOnAll("misn0917.wav") == 4 and playedOnAll("misn0910.wav") == 4, "a far walker built before the artillery falls plays both lines")
    local order = {}
    for _, c in ipairs(host.calls) do if c[1] == "Play" and (c[2] == "misn0917.wav" or c[2] == "misn0910.wav") then order[#order + 1] = c[2] end end
    check(#order == 2 and order[1] == "misn0917.wav", "Collins first, then Sasquatch")
end

-- ============================================================ 8. replacement tug
do
    local host, guests, s = convoySession(2)
    local firstTug = s.ccatug
    local builds = built(host, "svhaul")
    check(builds == 1, "one tug")
    objects[firstTug].alive = false
    run(1)
    local deadAt = now
    check(s.build_new_tug and not s.relic_seized and s.relic_free, "a dead tug frees the relic and arms the rebuild")
    run(86)
    check(built(host, "svhaul") == 1, "nothing before the 90 s delay")
    run(6)
    check(built(host, "svhaul") == 2 and s.ccatug ~= firstTug and s.tug_rebuilds == 1, "a replacement tug is built after 90 s")
    local call = last(host, "BuildObject")
    check(call[3] == "svhaul" and call[4] == 5 and call[5] == "svmuf", "built on team 5 at the CCA factory")
    run(4)
    check(count(host, "Pickup") == 2 and s.relic_seized and count(host, "Dropoff") == 2,
        "the existing tug logic sends the new tug for the relic and on to the pad")
    check(count2(host, "Follow", s.convoy1, s.ccatug) == 1 and count2(host, "Follow", s.convoy9, s.ccatug) == 1,
        "the surviving escort follows the new tug")
    for _, g in ipairs(guests) do check(count(g, "BuildObject") == 0, "guests never build the tug") end
    -- second and third deaths
    objects[s.ccatug].alive = false
    run(97)
    check(built(host, "svhaul") == 3 and s.tug_rebuilds == 2, "a second rebuild")
    run(4)
    check(s.relic_seized, "the second tug has the relic")
    objects[s.ccatug].alive = false
    run(300)
    check(built(host, "svhaul") == 3 and not s.build_new_tug, "two rebuilds is the limit")
    allBuildTeams(host)
end
do
    local host, guests, s = convoySession(1)
    objects[s.ccatug].alive = false
    objects.svmuf.alive = false
    run(200)
    check(built(host, "svhaul") == 1 and not s.build_new_tug, "no rebuild without the CCA factory")
end
do
    local host, guests, s = convoySession(1)
    objects[s.ccatug].alive = false
    run(30)
    objects.svmuf.alive = false
    run(100)
    check(built(host, "svhaul") == 1, "the factory dying during the wait cancels the rebuild")
end
do
    local host, guests, s = convoySession(1)
    objects[s.ccatug].alive = false
    objects[s.relic].alive = false
    run(120)
    check(built(host, "svhaul") == 1, "no tug is rebuilt for a relic that no longer exists")
    run(20)
    eachPeer(function(p) check(count(p, "FailMission") == 1 and last(p, "FailMission")[3] == "misn09f1.des", "the lost relic fails everyone once") end)
end

-- ============================================================ 9. the relic win (the geyser-clear win stays cut)
do
    -- every CCA unit near the geyser dead: 0908 only, no victory (the stock SucceedMission is commented out)
    local host, guests, s = convoySession(3)
    s.unit_check = 0
    for h, o in pairs(objects) do if o.team == 5 and o.odf ~= "sblpad" and o.odf ~= "svmuf" and o.odf ~= "svrecy" then o.alive = false end end
    for _, p in pairs(peers) do
        p.env.CountUnitsNearObject = function() return 0 end
    end
    s.relic_seized = false
    run(12)
    check(s.game_over5 and not s.game_over, "clearing the geyser area latches the 0908 line only")
    eachPeer(function(p) check(count(p, "SucceedMission") == 0, "and never wins") end)
end
do
    -- the stock relic delivery win still works and also calms the storm
    local host, guests, s = convoySession(2)
    objects[s.ccatug].alive = false
    world.cargo[s.relic] = nil
    place(s.relic, MUF[1] + 50, MUF[2], MUF[3])
    s.relic_seized = false
    s.win_check = 0
    run(3)
    check(s.game_over and playedOnAll("misn0909.wav") == 2, "a free relic near the factory still wins")
    check(host.venus.targets[#host.venus.targets] == 1, "that win calms the storm too")
end

-- ============================================================ 10. losing the factory, rally
do
    local host, guests = session(true)
    run(4)
    eachPeer(function(p) check(p.rally and p.rally[0] == "avmuf", "rally is the factory while it lives") end)
    objects.avmuf.alive = false
    run(1)
    eachPeer(function(p) check(p.rally and next(p.rally) == nil, "the rally point is dropped once the factory is gone") end)
    run(25)
    eachPeer(function(p) check(count(p, "FailMission") == 1 and last(p, "FailMission")[3] == "misn09f3.des", "every peer fails once") end)
    check(playedOnAll("misn0911.wav") == 4, "the factory-lost line reaches everyone")
end

-- ============================================================ 11. Venus weather
do
    local host, guests = session(true)
    local s = host.state
    check(host.venus.init and host.venus.init.authority and host.venus.init.sites.mission == "misn09"
        and host.venus.init.targetLevel == 2 and host.venus.init.startLevel == 1, "the leader runs the director as authority, calm at level 2")
    for _, g in ipairs(guests) do
        check(g.venus.init and g.venus.init.authority == false and g.venus.init.seed == nil,
            "guests render the host's weather: no authority and no seed of their own")
    end
    check(host.venus.announces == 1 and onAll(function(p) return p.venus.announces == 0 end) == 3,
        "only the leader announces the state, once, when the session is ready")
    check(host.venus.updates > 0 and onAll(function(p) return p.venus.updates > 0 end) == 4, "every peer updates the director")
    check(s.venusSeed == 4242, "the leader keeps the seed for a save")
    check(#host.venus.targets == 0 and #host.venus.forces == 0, "no beat before the convoy")
    host.venus.init.send("VenusState", 4242, 12.5, 2, 0, 2, 0, 0)
    host.env.AddObjective("misn0900.otf", "white")
    host.venus.init.send("VenusStrike", 1, 100.5, 20, 200.5, 1, 1.5, 1.0)
    host.venus.init.send("VenusErupt", 2, 3, 20, 0.9)
    run(3)
    for _, g in ipairs(guests) do
        check(#g.venus.events == 3 and g.venus.events[1][1] == "VenusState" and g.venus.events[2][1] == "VenusStrike"
            and g.venus.events[3][1] == "VenusErupt", "guests apply every Venus event in order")
        check((g.state.coopUnresolved or 0) == 0, "Venus events never register as unresolved")
    end
    runTo(25)
    s.third_warning_time = 0
    run(3)
    check(#host.venus.targets == 1 and host.venus.targets[1] == 3 and #host.venus.forces == 0, "the convoy's launch lifts the storm to level 3")
    check(s.convoy_started, "the convoy started")
    at(s.ccatug, CUT, 0, 100)
    runTo(s.prescott and s.prescott.due or now + 46)
    run(50)
    check(#host.venus.forces == 1 and host.venus.forces[1][1] == 5, "Prescott's arrival bursts the storm")
    run(40)
    check(#host.venus.targets == 1 and #host.venus.forces == 1, "each beat fires once")
    eachPeer(function(p)
        if p ~= host then check(#p.venus.targets == 0 and #p.venus.forces == 0, "guests never drive the weather") end
    end)
    host.env.Save()
    check(s.weatherState and s.weatherState.saved, "the leader saves the weather state")
    local g1 = guests[1]; g1.env.Save()
    check(g1.state.weatherState == nil, "a guest saves no weather")
end
do
    -- the cutoff warning (misn0903) alone also lifts the storm
    local host, guests = session(true)
    host.state.convoy_cam_ready = true
    run(1)
    check(#host.venus.targets == 1 and host.venus.targets[1] == 3, "the cutoff warning lifts the storm to level 3")
end
do
    -- the final run on the pad also bursts the storm (no platoon needed)
    local host, guests, s = convoySession(1)
    at(s.ccatug, {2242.4, 91.8, 98903.3}, 0, 450)
    run(1)
    check(#host.venus.forces == 1, "the tug's final run bursts the storm")
end

-- ============================================================ 12. loss and win gates reach everyone
do
    local host, guests, s = convoySession(2)
    at(s.ccatug, {2242.4, 91.8, 98903.3}, 0, 99)
    run(25)
    eachPeer(function(p) check(count(p, "FailMission") == 1 and last(p, "FailMission")[3] == "misn09f2.des", "the tug reaching the pad fails everyone once") end)
    check(playedOnAll("misn0907.wav") == 2, "the launch-pad line plays")
end

-- ============================================================ 13. offline smoke
do
    local host = session(false, 1)
    local s = host.state
    runTo(25)
    s.third_warning_time = 0
    run(4)
    check(s.convoy_started and count(host, "Send") == 0, "offline play runs the convoy with no network traffic")
    check(count(host, "BuildObject") == 12 and #(s.convoy_extra or {}) == 0, "offline: the DLL's convoy exactly")
    check(host.rally[0] == "avmuf" and count(host, "Play", "misn0900.wav") == 1, "offline dialogue and rally")
    at(s.ccatug, CUT, 0, 300)
    run(50)
    check(built(host, "avtank") == 5, "offline: a five-tank platoon")
    check(host.venus.init.authority and host.venus.init.send == nil and host.venus.init.players == nil and host.venus.announces == 0,
        "offline weather is the host path with nothing sent")
    check(host.venus.targets[1] == 3 and #host.venus.forces == 1, "offline play follows the same beats")
end

print("misn09 co-op: " .. checks .. " multi-peer Lua 5.1 mock-engine checks passed")
