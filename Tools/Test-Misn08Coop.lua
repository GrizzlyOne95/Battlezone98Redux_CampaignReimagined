-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Run from the repository root: lua5.1 Tools/Test-Misn08Coop.lua
-- Executes the complete misn08 script in separate Lua 5.1 environments over the
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
    colorado = {odf = "avrecy", team = 7, perceived = 1, pos = {3037.8, 24.9, 99508.8}, hp = 3000},
    avrecycle = {odf = "avrec8", team = 1, pos = {2325.7, 34.9, 101138}},
    cam1 = {odf = "apcamr", team = 1, pos = {2280, 34.4, 101036}},
    cam2 = {odf = "apcamr", team = 1, pos = {1640, 34.4, 99090}},
    cam5 = {odf = "apcamr", team = 1, pos = {3011.9, 25, 99475.9}},
    sovgech1 = {odf = "svwalk", team = 5, pos = {1500.8, 23, 99272}},
    sovgech2 = {odf = "svwalk", team = 5, pos = {1850.1, 23.4, 99357.5}},
    svrecycle = {odf = "svrecy", team = 5, pos = {1672.9, 33.4, 98898.2}},
    svmuf = {odf = "svmuf", team = 5, pos = {1738.9, 33.4, 99012.2}},
    svpatrol1_1 = {odf = "svfigh", team = 5, pos = {2290, 29.5, 99390}},
    svpatrol1_2 = {odf = "svfigh", team = 5, pos = {2304.9, 29.5, 99400.4}},
    svpatrol1_3 = {odf = "svfigh", team = 5, pos = {2337, 27, 99412}},
    svpatrol2_1 = {odf = "svfigh", team = 5, pos = {1500, 29.5, 99650}},
    svpatrol2_2 = {odf = "svfigh", team = 5, pos = {1552.8, 27.7, 99679.3}},
    svpatrol2_3 = {odf = "svfigh", team = 5, pos = {1518, 29.5, 99675.6}},
    hbblde1_i76building = {odf = "hbblde", team = 0, pos = {1426.3, 23.5, 99725.3}},
    hbbldf1_i76building = {odf = "hbbldf", team = 0, pos = {2530.4, 23.1, 99940.7}},
    hbcerb1_i76building = {odf = "hbcerb", team = 0, pos = {1665.5, 25.4, 99566.8}},
    giez_spawn2 = {odf = "eggeizr1", team = 0, pos = {2406, 24, 99890}},
    giez_spawn3 = {odf = "eggeizr1", team = 0, pos = {1514, 32, 99925}},
    stop_geyser1 = {odf = "eggeizr1", team = 0, pos = {1504, 24, 99604}},
    stop_geyser2 = {odf = "eggeizr1", team = 0, pos = {2295, 27, 99487}},
    stop_geyser3 = {odf = "eggeizr1", team = 0, pos = {1993, 33, 100812}},
    attack_geyser = {odf = "eggeizr1", team = 0, pos = {3040, 25, 99515}},
    ccarecycle_geyser = {odf = "eggeizr1", team = 0, pos = {1674, 33, 98898}},
    death_scrap = {odf = "sscr_1", team = 0, pos = {3068, 26, 99540}},
    death_scrap2 = {odf = "sscr_1", team = 0, pos = {3042, 25, 99514}},
    death_scrap3 = {odf = "sscr_1", team = 0, pos = {3086, 27, 99532}},
    player0_hover = {odf = "player", team = 1, pos = {2335, 34, 101194}},
}
local PATHS = {
    gech_path1 = {1496, 24, 99285}, gech_path2 = {1890, 24, 99375}, gech_spawn = {2980, 25, 99420},
    cam2_spawn = {2447, 25, 99886}, cam3_spawn = {1521, 32, 99948},
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
    world = {hold = {}, scrap = {}, combat = true, nilMapHandles = true, net = false}
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
local SPEED = {svfigh = 30, svltnk = 12, svwalk = 5}
local DPS = {svfigh = 80, svltnk = 40, svwalk = 120}
local function physics(dt)
    for h, o in pairs(objects) do
        if o.removeAt and now >= o.removeAt then o.alive = false end
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
        if objectTeam == 7 then
            o.hp = ({avtank = 2000, avfigh = 1000, avscav = 1000, avmuf = 4000, avturr = 2000, avapc = 2000})[odf] or 1000
            o.maxhp = o.hp
        end
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
        "Ally", "UnAlly", "DisplayMessage", "FailMission", "SucceedMission", "SetScrap", "SetPilot", "Deploy"}) do
        local n = name
        e[n] = function(...)
            if n == "SetObjectiveOn" or n == "SetObjectiveName" then
                assert(e.IsValid((...)), "presentation used a not-yet-valid handle")
            end
            record(n, ...)
            if n == "SetScrap" then world.scrap[(...)] = select(2, ...) end
            if n == "Deploy" then objects[(...)].deployed = true end
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
        CRVenusSites08 = { mission = "misn08" }, Environment = {Init = noop, Update = noop, OnObjectCreated = noop},
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
    setfenv(assert(loadfile("Scripts/misn08.lua")), e)()
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
        check(c[4] == 1 or c[4] == 5 or c[4] == 7, "BuildObject " .. c[3] .. " on a guest/unknown team " .. tostring(c[4]))
        if c[3]:find("^a[vb]") and c[3] ~= "apcamr" then check(c[4] == 7, c[3] .. " must be the Colorado support team 7") end
        if c[3]:find("^sv") then check(c[4] == 5, c[3] .. " must be CCA team 5") end
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
local function atColorado(dx) return 3037.8 + dx, 24.9, 99508.8 end

-- ============================================================ 1. startup, teams, label wire
do
    local host, guests = session(true)
    local s = host.state
    check(s.start_done, "leader starts the mission body")
    for _, g in ipairs(guests) do
        check(not g.state.start_done and count(g, "BuildObject") == 0, "guests never run the mission body")
        check(count(g, "DisableStartingRecycler") == 1, "guests disable the extra starting recycler")
    end
    run(1)
    for _, g in ipairs(guests) do
        check(count(g, "SetScrap", g.team) == 1 and last(g, "SetScrap")[3] == 30, "each human receives starting scrap on their own team")
    end
    check(count(host, "SetScrap", 1) == 1, "the leader receives starting scrap on team 1")
    check(host.rally and host.rally[0] == "avrecycle", "respawn rally is the Utah (avrecycle)")
    for _, g in ipairs(guests) do check(g.rally and g.rally[0] == "avrecycle", "guests rally at the Utah") end
    check(count(host, "SetAIControl", 5) == 1, "strategic AI is configured for the CCA team")
    check(count(host, "Ally") >= 12 and count(host, "UnAlly") >= 8, "alliances configured")
    check(objects.colorado.team == 7 and objects.colorado.perceived == 1, "the Colorado stays on the support team")
    -- Nav names reach every guest even though the engine hands them an invalid handle.
    for _, g in ipairs(guests) do
        check(count(g, "SetObjectiveName", "cam1") == 1 and count(g, "SetObjectiveName", "cam5") == 1
            and count(g, "SetObjectiveName", "cam2") == 1, "map nav names arrive by label on every guest")
        check(count(g, "AddObjective") == 2, "objectives reach every guest")
    end
    check(playedOnAll("misn0800.wav") == 4, "the opening briefing plays on every peer")
    allBuildTeams(host)
end

-- ============================================================ 2. the witnessable massacre
do
    local host, guests = session(true)
    local s = host.state
    runTo(279)
    check(not s.colorado_under_attack, "no attack before the DLL time")
    runTo(285)
    check(s.colorado_under_attack and s.ccagech3, "attack on the Colorado begins")
    local walker3 = s.ccagech3
    check(objects[walker3].odf == "svwalk" and objects[walker3].team == 5, "walker 3 is a CCA svwalk")
    check(playedOnAll("misn0801.wav") == 4, "the first Colorado call reaches every peer")
    local ordered = false
    for _, c in ipairs(callsOf(host, "Attack")) do
        if c[2] == s.strike.figh and c[3] == "colorado" then ordered = true end
    end
    check(ordered and s.strike.figh ~= s.strike.ltnk, "the CCA strike fighter is sent at the Colorado")
    local force0 = {}
    for _, h in ipairs(s.cbase.force) do force0[#force0 + 1] = h end
    check(#force0 == 10, "the Colorado entered the massacre with its full base: " .. #force0)
    local kinds = {}
    for _, h in ipairs(force0) do kinds[objects[h].odf] = (kinds[objects[h].odf] or 0) + 1; check(objects[h].team == 7, "base objects are team 7") end
    check(kinds.avtank == 2 and kinds.avfigh == 1 and kinds.avscav == 1 and kinds.avmuf == 1 and kinds.avturr == 2 and kinds.avapc == 3,
        "escort, scavenger, factory, two towers and three APCs")
    check(objects[s.cbase.factory].deployed, "the Colorado factory deployed")
    local healStopped
    for _ = 1, 1600 do
        tick()
        if s.kill_colorado and not healStopped then healStopped = now end
        if not objects.colorado.alive then break end
    end
    check(healStopped, "the DLL kill flag arrives")
    check(not objects.colorado.alive and objects.colorado.diedAt > healStopped, "the Colorado is destroyed only after its heal stops")
    check(objects.colorado.killedBy ~= nil and objects.colorado.killedBy ~= "script", "an attacker destroyed it on screen: " .. tostring(objects.colorado.killedBy))
    check(count(host, "Damage") == 0, "no scripted damage was needed")
    check(playedOnAll("misn0803.wav") == 4 and playedOnAll("misn0802.wav") == 4, "the Colorado radio timeline reaches every peer")
    eachPeer(function(p) check(count(p, "Queue", "misn0804.wav") == 1 and count(p, "Play", "misn0804.wav") == 0,
        "0804 is queued behind 0802 on every peer") end)
    run(2)
    check(s.colorado_message4, "the story proceeds once the Colorado fell")
    -- The base and escort fall to the strike, on screen, no scripted damage.
    local wiped
    for _ = 1, 2400 do
        local alive = 0
        for _, h in ipairs(force0) do if objects[h].alive then alive = alive + 1 end end
        if alive == 0 then wiped = now; break end
        tick()
    end
    check(wiped and count(host, "Damage") == 0, "the whole Colorado base is destroyed by the attackers alone")
    for _, h in ipairs(force0) do check(objects[h].killedBy ~= nil and objects[h].killedBy ~= "script", "base object killed by an attacker") end
    check(s.strike.extra and #s.strike.extra == 4, "a bigger base earns extra CCA strike units")
    for _, h in ipairs(s.strike.extra) do check(objects[h].team == 5 and objects[h].odf:find("^sv"), "extra strike units are CCA") end
    run(1)
    local released
    for _, c in ipairs(callsOf(host, "Goto")) do if c[2] == s.strike.figh and c[3] == "cam1" then released = true end end
    check(released and s.colorado_cleaned, "the strike units resume the DLL Drop Zone order")
    run(18)
    eachPeer(function(p) check(count(p, "RemoveObject", "cam5") == 1, "the Colorado nav is removed on every peer") end)
    run(8)
    check(playedOnAll("misn0805.wav") == 4, "Corbett news reaches every peer")
    check(count(host, "SetAIP", "misn08.aip") == 1 and last(host, "SetAIP")[3] == 5, "the strategic AIP runs on the CCA team")
    check(count(host, "SetScrap", 5) == 1 and count(host, "SetPilot", 5) == 1, "CCA scrap and pilots go to team 5")
    run(31)
    check(playedOnAll("misn0810.wav") == 4, "the general message reaches every peer")
    allBuildTeams(host)
end

-- ============================================================ 3. fallback damage
do
    local host = session(true)
    local s = host.state
    world.combat = false
    runTo(300)
    for _ = 1, 4000 do tick(); if s.colorado_deadline then break end end
    check(s.colorado_deadline and objects.colorado.alive and count(host, "Damage") == 0, "no attacker, no scripted damage yet")
    runTo(s.colorado_deadline - 2)
    check(objects.colorado.alive and count(host, "Damage") == 0, "the fallback waits for its generous timeout")
    run(3)
    check(count(host, "Damage", "colorado") == 1 and not objects.colorado.alive and s.colorado_message4,
        "Damage(colorado, 20000) fires only after the timeout")
    check(last(host, "Damage")[3] == 20000, "fallback damage amount")
    check(s.colorado_deadline - 300 > 0 and s.colorado_deadline > 400, "the timeout is generous")
end

-- ============================================================ 4. hold-off and 0824
do
    local host, guests = session(true)
    local s = host.state
    place(guests[2].player, 3011.9, 25, 99476 + 300) -- 300 m from the Colorado nav
    runTo(300)
    check(not s.colorado_under_attack, "a player within 400 m of the nav holds the attack off")
    check(playedOnAll("misn0824.wav") == 4 and s.colorado_warned, "0824 warns the approaching player on every peer")
    local nearest = false
    for _, c in ipairs(callsOf(host, "Attack")) do if c[3] == guests[2].player then nearest = true end end
    check(nearest, "the nosey-player ambush targets the nearest player")
    place(guests[2].player, 100, 20, 100)
    runTo(340)
    check(s.colorado_under_attack, "the attack proceeds once nobody is within 400 m")
    check(playedOnAll("misn0824.wav") == 4, "0824 is not repeated")
end
do
    -- A player who only approaches after the attack began is warned during the massacre.
    local host, guests = session(true)
    local s = host.state
    runTo(285)
    check(s.colorado_under_attack and not s.colorado_warned, "the attack began unwarned")
    place(guests[3].player, atColorado(350))
    run(2)
    check(s.colorado_warned and playedOnAll("misn0824.wav") == 4, "approaching the Colorado mid-massacre plays 0824 once")
end

-- ============================================================ 5. walker 3 continues to the base
do
    local host = session(true)
    local s = host.state
    near("giez_spawn2", "sovgech2", 50) -- walker 2 reaches its trigger
    runTo(285)
    local walker3 = s.ccagech3
    near(walker3, "stop_geyser2", 20)
    for _ = 1, 4000 do tick(); if s.ccarecycle_spawned then break end end
    run(1)
    check(s.ccarecycle_spawned and s.gech3_move, "walker 3 is sent on once the CCA AIP starts")
    local gotos = 0
    for _, c in ipairs(callsOf(host, "Goto")) do if c[2] == walker3 and c[3] == "gech_path2" then gotos = gotos + 1 end end
    check(gotos == 2, "the DLL order plus the restored advance")
    check(s.gech3_there_time > now + 90 and s.gech3_there_time < now + 100, "arrival check armed about 97 s out")
    near(walker3, "stop_geyser3", 50)
    runTo(s.gech3_there_time + 31)
    check(s.gech3_at_base, "walker 3 reaches the base")
    local attacks = false
    for _, c in ipairs(callsOf(host, "Attack")) do if c[2] == walker3 and c[3] == "avrecycle" then attacks = true end end
    check(attacks, "walker 3 attacks the Utah like walkers 1 and 2")
end

-- ============================================================ 6. 0816 within 75 m of any player
do
    local host, guests = session(true)
    local s = host.state
    place(guests[1].player, 1800.8, 23, 99272) -- 300 m from sovgech1
    runTo(62)
    check(s.gech_found1, "a guest discovers the first walker")
    place(guests[1].player, 1500.8 + 80, 23, 99272)
    run(2)
    check(not s.too_close_message, "80 m is outside the warning range")
    place(guests[1].player, 1500.8 + 70, 23, 99272)
    run(1)
    check(s.too_close_message and playedOnAll("misn0816.wav") == 4, "0816 plays for everyone when a guest is within 75 m")
end

-- ============================================================ 7. heal fix
do
    local host = session(true)
    run(10)
    check(count(host, "AddHealth", "colorado") >= 8, "the Colorado heal runs about once a second")
    check(count(host, "AddHealth", "hbcerb1_i76building") >= 8, "the relic heal runs about once a second")
    check(last(host, "AddHealth")[3] == 500, "500 hp per pass")
    local n = count(host, "AddHealth", "hbcerb1_i76building")
    run(5)
    check(count(host, "AddHealth", "hbcerb1_i76building") >= n + 4, "the relic keeps healing")
end

-- ============================================================ 8. losing the Utah
do
    local host = session(true)
    run(30)
    objects.avrecycle.alive = false
    run(2)
    check(playedOnAll("misn0823.wav") == 4, "0823 plays on every peer when the Utah is lost")
    eachPeer(function(p) check(count(p, "Play", "misn0421.wav") == 0, "0421 is substituted") end)
    run(25)
    eachPeer(function(p) check(count(p, "FailMission") == 1 and last(p, "FailMission")[3] == "misn08f1.des", "every peer fails once") end)
    eachPeer(function(p) check(count(p, "SucceedMission") == 0, "no success on failure") end)
end

-- ============================================================ 9. win gate (any player)
do
    local relic = {1665.5, 25.4, 99566.8}
    local host, guests = session(true)
    local s = host.state
    run(30)
    objects.svrecycle.alive, objects.svmuf.alive = false, false
    run(5)
    check(s.base_dead and playedOnAll("misn0820.wav") == 4, "base-first: the relic objective plays on every peer")
    eachPeer(function(p) check(count(p, "SetObjectiveOn", "hbcerb1_i76building") == 1, "relic marker on every peer") end)
    check(onAll(function(p) return count(p, "SucceedMission") == 0 end) == 4, "no victory without a player at the relic")
    place(guests[2].player, relic[1] + 40, relic[2], relic[3])
    run(25)
    eachPeer(function(p)
        check(count(p, "SucceedMission") == 1 and last(p, "SucceedMission")[3] == "misn08w1.des", "any player at the relic wins for everyone")
        check(count(p, "Play", "misn0818.wav") == 1 and count(p, "Queue", "misn0826.wav") == 1 and count(p, "Play", "misn0826.wav") == 0,
            "0818 plays and 0826 queues on every peer")
    end)
    host, guests = session(true)
    s = host.state
    place(guests[3].player, relic[1] + 50, relic[2], relic[3])
    run(35)
    check(s.cerb_found and playedOnAll("misn0819.wav") == 4, "relic-first: 0819 on every peer")
    check(onAll(function(p) return count(p, "SucceedMission") == 0 end) == 4, "relic-first waits for the CCA base")
    objects.svrecycle.alive, objects.svmuf.alive = false, false
    run(25)
    eachPeer(function(p) check(count(p, "SucceedMission") == 1, "relic-first victory reaches every peer once") end)
end

-- ============================================================ 10. IsInfo relay
do
    local host, guests = session(true)
    local s = host.state
    run(3)
    guests[1].info = {hbblde = true}
    run(2)
    check(s.relic_message and playedOnAll("misn0822.wav") == 4, "a guest selecting the first ruins triggers 0822 for everyone")
    local host2, guests2 = session(true)
    local s2 = host2.state
    objects.svrecycle.alive, objects.svmuf.alive = false, false
    run(3)
    guests2[2].info = {hbbldf = true}
    run(2)
    check(s2.relic_message and playedOnAll("misn0821.wav") == 4, "after the base fell the same selection plays 0821")
    local host3 = session(true)
    run(5)
    check(not host3.state.relic_message, "no report, no relic message")
end

-- ============================================================ 11. team-filtered AddObject
do
    local host = session(true)
    local s = host.state
    local function add(odf, team) local h = spawn(odf, team); host.env.AddObject(h); return h end
    add("avmu8", 5)
    check(s.nsdfmuf == nil, "a CCA avmu8 is not the player factory")
    local factory = add("avmu8", 4)
    check(s.nsdfmuf == factory, "a guest factory counts")
    add("svapc", 1)
    check(s.ccaapc == nil, "a human-team svapc is not the CCA APC")
    local apc = add("svapc", 5)
    check(s.ccaapc == apc, "the CCA APC is tracked")
    add("abtowe", 5)
    check(s.guntower1 == nil, "a CCA tower is not a player gun tower")
    local tower1, tower2 = add("abtowe", 3), add("abtowe", 1)
    check(s.guntower1 == tower1 and s.guntower2 == tower2, "human-team towers fill both slots in order")
    run(1)
    local attack
    for _, c in ipairs(callsOf(host, "Attack")) do if c[2] == apc and c[3] == tower1 then attack = true end end
    check(attack, "the APC attacks the first player tower")
end

-- ============================================================ 12. AIP choice counts every human team
do
    local host = session(true)
    local s = host.state
    for _ = 1, 3 do spawn("avfigh", 2, 2300, 99487) end
    spawn("avtank", 1, 2300, 99487)
    s.new_aip_time = 0
    run(1)
    check(count(host, "SetAIP", "misn08b.aip") == 1 and last(host, "SetAIP")[3] == 5,
        "fighters on a guest team make the fighter-heavy AIP")
    local host2 = session(true)
    spawn("avtank", 3, 2300, 99487)
    host2.state.new_aip_time = 0
    run(1)
    check(count(host2, "SetAIP", "misn08a.aip") == 1, "a guest tank makes the tank-heavy AIP")
end

-- ============================================================ 12b. the Colorado starts allied with a base
do
    local host, guests = session(true)
    local s = host.state
    local escort = {}
    for _, c in ipairs(callsOf(host, "BuildObject")) do escort[#escort + 1] = c end
    check(#escort == 3 and escort[1][4] == 7 and escort[2][4] == 7 and escort[3][4] == 7, "three allied escort units spawn on the support team")
    for _, c in ipairs(escort) do
        local o = objects[c[2]]
        check(planar(o.pos, objects.colorado.pos) < 80 and o.perceived == 1, "the escort stands by the Colorado, perceived as NSDF")
    end
    check(world.scrap[7] == 60 - 0, "team-7 scrap was set at the start")
    for _, g in ipairs(guests) do check(count(g, "BuildObject") == 0, "guests never spawn the escort") end
    run(25)
    check(built(host, "avscav") == 1, "recycler-style scavenger")
    run(70)
    check(built(host, "avmuf") == 1 and count(host, "Deploy") == 1, "factory built and deployed")
    run(150)
    check(built(host, "avturr") == 2 and built(host, "avapc") == 3, "two defenses and the APC cap")
    check(world.scrap[7] == 60 - 4 - 10 - 12 - 15, "the base is paid for from team-7 scrap: " .. tostring(world.scrap[7]))
    local before = count(host, "BuildObject")
    for _, apcCall in ipairs(callsOf(host, "BuildObject", nil)) do end
    allBuildTeams(host)
    check(not s.colorado_under_attack, "all of it before the DLL attack time")
    run(10)
    check(count(host, "BuildObject") == before, "nothing beyond the caps")
    -- every Colorado-team unit is a script spawn; the base never takes a human team
    for _, c in ipairs(callsOf(host, "BuildObject")) do
        if c[3]:find("^a[vb]") and c[3] ~= "apcamr" then check(c[4] == 7, "Colorado units never occupy a guest team") end
    end
end

-- ============================================================ 12c. cleanup fallback for a stalled strike
do
    local host = session(true)
    local s = host.state
    runTo(285)
    world.combat = false
    local force = {}
    for _, h in ipairs(s.cbase.force) do force[#force + 1] = h end
    for _ = 1, 2000 do tick(); if s.kill_colorado then break end end
    local flipped = now
    runTo(flipped + 100)
    check(count(host, "Damage") == 0, "nothing is swept before the timeouts")
    runTo(flipped + 123)
    check(count(host, "Damage", "colorado") == 1, "the Colorado fallback fires first (generous 120 s)")
    check(not s.colorado_cleaned, "the base survives until its own timeout")
    runTo(flipped + 153)
    check(s.colorado_cleaned, "the base sweep follows")
    for _, h in ipairs(force) do check(not objects[h].alive and objects[h].killedBy == "script", "survivor swept") end
    check(count(host, "Damage") == 1 + #force, "one Damage per Colorado-team survivor plus the Colorado")
    run(5)
    check(count(host, "Damage") == 1 + #force, "the sweep runs once")
end

-- ============================================================ 12d. CCA walker production
local function walkerSession(humans)
    local host, guests = session(true, humans)
    local s = host.state
    runTo(285)
    for _ = 1, 2400 do tick(); if s.colorado_message4 then break end end
    return host, s
end
do
    local host, s = walkerSession(4)
    for _ = 1, 2000 do tick(); if s.cw then break end end
    world.scrap[5] = 200
    check(s.ccarecycle_spawned and s.cw and built(host, "svwalk") == 1, "before production only the scripted walker exists")
    run(58)
    check(built(host, "svwalk") == 1, "the first produced walker waits its delay")
    run(4)
    check(built(host, "svwalk") == 2 and #s.cw.list == 1, "a svwalk is built at the CCA factory")
    local buildCalls = callsOf(host, "BuildObject")
    local lastBuild = buildCalls[#buildCalls]
    check(lastBuild[3] == "svwalk" and lastBuild[4] == 5 and lastBuild[5] == s.ccamuf, "built at the factory on team 5")
    check(objects[s.cw.list[1]].attack == "avrecycle", "sent at the Utah")
    local scrap5 = world.scrap[5]
    run(150)
    check(built(host, "svwalk") == 3 and #s.cw.list == 2 and world.scrap[5] == scrap5 - 12, "second walker after 150 s, charged 12 scrap")
    run(150)
    check(built(host, "svwalk") == 4 and #s.cw.list == 3, "third walker")
    run(400)
    check(built(host, "svwalk") == 4 and #s.cw.list == 3, "four humans cap production at three live walkers")
    objects[s.cw.list[1]].alive = false
    run(160)
    check(built(host, "svwalk") == 5, "a lost walker is replaced")
    for _, c in ipairs(callsOf(host, "BuildObject")) do
        if c[3] == "svwalk" then check(c[4] == 5, "walkers are CCA") end
    end
    objects[s.ccamuf].alive = false
    local n = built(host, "svwalk")
    run(400)
    check(built(host, "svwalk") == n, "no production once the CCA factory fell")
end
do
    -- two humans: cap two; a pauper builds nothing; the base falling stops it
    local host, s = walkerSession(2)
    for _ = 1, 2000 do tick(); if s.cw then break end end
    world.scrap[5] = 5
    run(160)
    check(built(host, "svwalk") == 1, "no scrap, no walker")
    world.scrap[5] = 100
    run(400)
    check(#s.cw.list == 2 and built(host, "svwalk") == 3, "two humans cap production at two walkers")
    objects.svrecycle.alive, objects.svmuf.alive = false, false
    objects[s.cw.list[1]].alive = false
    run(300)
    check(built(host, "svwalk") == 3, "no more walkers once the CCA base fell")
end
do
    -- solo (one human team): one walker at a time
    local host, s = walkerSession(1)
    for _ = 1, 2000 do tick(); if s.cw then break end end
    run(700)
    check(#s.cw.list == 1 and built(host, "svwalk") == 2, "a single human caps production at one walker")
end

-- ============================================================ 12e. Venus weather
do
    local host, guests = session(true)
    local s = host.state
    check(host.venus.init and host.venus.init.authority and host.venus.init.sites.mission == "misn08"
        and host.venus.init.targetLevel == 2 and host.venus.init.startLevel == 1, "the leader runs the director as authority, calm at level 2")
    for _, g in ipairs(guests) do
        check(g.venus.init and g.venus.init.authority == false and g.venus.init.seed == nil,
            "guests render the host's weather: no authority and no seed of their own")
    end
    check(host.venus.announces == 1 and onAll(function(p) return p.venus.announces == 0 end) == 3,
        "only the leader announces the state, once, when the session is ready")
    check(host.venus.updates > 0 and onAll(function(p) return p.venus.updates > 0 end) == 4, "every peer updates the director")
    check(s.venusSeed == 4242, "the leader keeps the seed for a save")
    check(#host.venus.targets == 0 and #host.venus.forces == 0, "no beat before the walkers attack")
    -- Venus ops ride the ordered stream with no handles, so they are never labelled or waited on,
    -- and they stay ordered against ordinary events.
    host.venus.init.send("VenusState", 4242, 12.5, 2, 0, 2, 0, 0)
    host.env.AddObjective("misn0800.otf", "white")
    host.venus.init.send("VenusStrike", 1, 100.5, 20, 200.5, 1, 1.5, 1.0)
    host.venus.init.send("VenusErupt", 2, 3, 20, 0.9)
    run(3)
    for _, g in ipairs(guests) do
        check(#g.venus.events == 3 and g.venus.events[1][1] == "VenusState" and g.venus.events[1][2] == 4242
            and g.venus.events[2][1] == "VenusStrike" and g.venus.events[2][5] == 200.5 and g.venus.events[3][1] == "VenusErupt",
            "guests apply every Venus event in order")
        check(count(g, "AddObjective", "misn0800.otf") == 1, "ordinary events keep flowing between Venus events")
        check((g.state.coopUnresolved or 0) == 0, "Venus events never register as unresolved")
    end
    check(#host.venus.events == 0, "the leader does not re-apply its own events")
    -- Beats: level 3 when the walkers attack, a level-5 spike when the heal stops, a steady 3 after.
    runTo(285)
    check(s.colorado_under_attack, "the attack began")
    run(1)
    check(#host.venus.targets == 1 and host.venus.targets[1] == 3 and #host.venus.forces == 0, "the walker attacks lift the storm to level 3")
    for _ = 1, 1600 do tick(); if s.kill_colorado then break end end
    run(1)
    check(#host.venus.forces == 1 and host.venus.forces[1][1] == 5 and host.venus.forces[1][2] == 60.0, "the massacre spikes the storm to level 5")
    for _ = 1, 4000 do tick(); if s.ccarecycle_spawned then break end end
    run(1)
    check(#host.venus.targets == 2 and host.venus.targets[2] == 3 and #host.venus.forces == 1, "CCA walker production settles the storm to level 3")
    eachPeer(function(p)
        if p ~= host then check(#p.venus.targets == 0 and #p.venus.forces == 0, "guests never drive the weather") end
    end)
    run(30)
    check(#host.venus.targets == 2 and #host.venus.forces == 1, "each beat fires once")
    -- A save keeps the seed and the director's state on the leader only.
    host.env.Save()
    check(s.weatherState and s.weatherState.saved, "the leader saves the weather state")
    local g1 = guests[1]; g1.env.Save()
    check(g1.state.weatherState == nil, "a guest saves no weather")
end

-- ============================================================ 13. offline smoke
do
    local host = session(false, 1)
    local s = host.state
    runTo(300)
    check(s.colorado_under_attack and count(host, "Send") == 0, "offline play reaches the Colorado attack with no network traffic")
    check(count(host, "Play", "misn0801.wav") == 1 and host.rally[0] == "avrecycle", "offline dialogue and rally")
    check(host.venus.init.authority and host.venus.init.send == nil and host.venus.init.players == nil and host.venus.announces == 0,
        "offline weather is the host path with nothing sent")
    check(#host.venus.targets == 1 and host.venus.targets[1] == 3, "offline play follows the same beats")
end

print("misn08 co-op: " .. checks .. " multi-peer Lua 5.1 mock-engine checks passed")
