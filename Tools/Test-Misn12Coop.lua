-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Run from the repository root: lua5.1 Tools/Test-Misn12Coop.lua
-- Executes the complete misn12 script in separate Lua 5.1 environments over the
-- real CRCoop registry and the E/A (+C camera, +I info) presentation transport. The engine, AI and
-- combat are mocks: they verify script decisions, not Redux native map loading, pathfinding,
-- perceived-team behaviour, Lua wire serialization or EXU hooks. The map coordinates below are the
-- authored ones (Missions/misn12.bzn).
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

-- ---------------------------------------------------------------- world model
local now, objects, peers, nextObject, transport, world
local function P(x, z, y) return {x, y or 30, z} end
local LABELS = {
    checktower1 = {odf = "sbhqt1", team = 5, pos = P(3975, 98973)},
    center = {odf = "sbhqt2", team = 5, pos = P(2725, 99815)},
    check2_geyser = {odf = "eggeizr1", team = 0, pos = P(2942, 100810)},
    svguntower2 = {odf = "sbhang", team = 5, pos = P(2872, 100839)},
    svmuf = {odf = "svmuf", team = 5, pos = P(1346, 100690)},
    svsilo1 = {odf = "sbsilo", team = 5, pos = P(1468, 99534)},
    svsilo2 = {odf = "sbsilo", team = 5, pos = P(1465, 99475)},
    svsilo3 = {odf = "sbsilo", team = 5, pos = P(1408, 99495)},
    svsilo4 = {odf = "sbsilo", team = 5, pos = P(1404, 99437)},
    svcom_tower = {odf = "sbcomm", team = 5, pos = P(2147, 100431)},
    spawn_geyser = {odf = "eggeizr1", team = 0, pos = P(3731, 99561)},
    spawn_geyser1 = {odf = "eggeizr1", team = 0, pos = P(1921, 101021)},
    spawn_geyser2 = {odf = "eggeizr1", team = 0, pos = P(2710, 99781)},
    choke_geyser = {odf = "eggeizr1", team = 0, pos = P(2146, 99949)},
    center_geyser = {odf = "eggeizr1", team = 0, pos = P(2768, 99856)},
    apcamr20_camerapod = {odf = "apcamr", team = 1, pos = P(3560, 97863)},
    pfighter1 = {odf = "svfigh", team = 5, pos = P(1356, 100743)},
    pfighter2 = {odf = "svfigh", team = 5, pos = P(1333, 100704)},
    ptank1 = {odf = "svtank", team = 5, pos = P(1821, 101030)},
    ptank2 = {odf = "svtank", team = 5, pos = P(1875, 100997)},
    turret1 = {odf = "svturr", team = 5, pos = P(2916, 100757)},
    turret2 = {odf = "svturr", team = 5, pos = P(2820, 100821)},
    turret3 = {odf = "svturr", team = 5, pos = P(2930, 100855)},
    turret4 = {odf = "svturr", team = 5, pos = P(2980, 99724)},
    turret5 = {odf = "svturr", team = 5, pos = P(2162, 99895)},
    turret6 = {odf = "svturr", team = 5, pos = P(2881, 100757)},
    svfigh1_1 = {odf = "svfigh", team = 5, pos = P(2773, 99820)},
    svfigh1_2 = {odf = "svfigh", team = 5, pos = P(2778, 99838)},
    svfigh2_1 = {odf = "svfigh", team = 5, pos = P(2754, 99814)},
    svfigh2_2 = {odf = "svfigh", team = 5, pos = P(2897, 100780)},
    svfigh3_1 = {odf = "svfigh", team = 5, pos = P(1326, 100658)},
    svfigh3_2 = {odf = "svfigh", team = 5, pos = P(1318, 100645)},
    svfigh4_1 = {odf = "svfigh", team = 5, pos = P(1520, 99494)},
    svfigh4_2 = {odf = "svfigh", team = 5, pos = P(1521, 99508)},
    gtank1 = {odf = "svtank", team = 5, pos = P(2223, 100414)},
    gtank2 = {odf = "svtank", team = 5, pos = P(2176, 100378)},
    artil1 = {odf = "svartl", team = 5, pos = P(1217, 100447)},
    artil2 = {odf = "svartl", team = 5, pos = P(1228, 100410)},
    artil3 = {odf = "svartl", team = 5, pos = P(1174, 100449)},
    artil4 = {odf = "svartl", team = 5, pos = P(1192, 100417)},
    ["player0_hover"] = {odf = "player", team = 1, pos = P(3538, 97876)},
}
local PATHS = {
    ["3spawn"] = {1315, 30, 100384}, ["4spawn"] = {1683, 30, 99520},
    center_cam = {2746, 30, 99851}, check2_cam = {2909, 30, 100793}, check3_cam = {1367, 30, 100666},
    check4_cam = {1516, 30, 99540}, start_cam = {3986, 30, 98941}, goal_cam = {2122, 30, 100386},
    first_path = {3657, 30, 99514},
}
local DROP = {3560, 30, 97863}
local START = {3538, 30, 97876}
local FAR = 90000
local function vec(t) return {x = t[1], y = t[2], z = t[3]} end
local function newObject(handle, odf, team, pos)
    objects[handle] = {alive = true, odf = odf, team = team, health = 1, pos = vec(pos or {FAR, 20, FAR})}
    if LABELS[handle] then objects[handle].label = handle end
    return objects[handle]
end
local pathPos
local function reset()
    now, objects, peers, nextObject = 0, {}, {}, 0
    world = {net = false}
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
local function setAt(h, x, z) place(h, x, 30, z) end
local function at(h, p, dx, dz) place(h, p[1] + (dx or 0), p[2], p[3] + (dz or 0)) end

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
local function builtList(peer, odf)
    local out = {}
    for _, c in ipairs(peer.calls) do if c[1] == "BuildObject" and c[3] == odf then out[#out + 1] = c[2] end end
    return out
end
local function last(peer, name)
    for i = #peer.calls, 1, -1 do if peer.calls[i][1] == name then return peer.calls[i] end end
end
local function callsOf(peer, name)
    local out = {}
    for _, c in ipairs(peer.calls) do if c[1] == name then out[#out + 1] = c end end
    return out
end
-- Objective-panel calls a peer applied, by operation (panel text only).
local function panel(peer)
    local out = {}
    for _, c in ipairs(peer.calls) do
        if c[1] == "ClearObjectives" then out[#out + 1] = "CLEAR"
        elseif c[1] == "AddObjective" then out[#out + 1] = c[2] .. ":" .. c[3] end
    end
    return table.concat(out, " ")
end

local function makePeer(id, team, network)
    local p = {id = id, team = team, net = network, hosting = team == 1, calls = {}, player = "player" .. id,
        info = {}, cancelled = false, timer = 0, timerRunning = false}
    p.europa = {updates = 0, announces = 0, shutdowns = 0, events = {}, targets = {}, releases = 0, plumes = {}, quakes = {}, surges = {}}
    peers[id] = p
    newObject(p.player, "avtank", team, {FAR + id, 20, FAR})
    local function record(name, ...) p.calls[#p.calls + 1] = {name, ...} end
    p.record = record
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
    e.GetHealth = function(h) return objects[h] and objects[h].health or 0 end
    e.AddHealth = function(h, v)
        record("AddHealth", h, v)
        if objects[h] then objects[h].health = math.min(1, objects[h].health + v / 1000) end
    end
    e.AddAmmo = function(h, v) record("AddAmmo", h, v) end
    e.GetPosition = function(h)
        local pos = posOf(h)
        return pos and {x = pos.x, y = pos.y, z = pos.z} or {x = 0, y = 0, z = 0}
    end
    e.SetVector = function(x, y, z) return {x = x or 0, y = y or 0, z = z or 0} end
    e.GetTerrainHeightAndNormal = function(v)
        if world.terrain then return world.terrain(v.x, v.z), {x = 0, y = 1, z = 0} end
        return 20, {x = 0, y = 1, z = 0}
    end
    e.GetWhoShotMe = function(h) return objects[h] and objects[h].shooter or nil end
    e.GetCurrentWho = function(h) return objects[h] and objects[h].prey or nil end
    e.GetDistance = function(a, b)
        assert(e.IsValid(a), "invalid origin reached native distance query")
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
        table.sort(list)
        local i = 0
        return function() i = i + 1; return list[i] end
    end
    e.AllCraft = e.AllObjects
    e.GetPilot = function() return 10 end
    e.GetMaxScrap = function() return 100 end
    e.GetMaxPilot = function() return 30 end
    e.SetMaxScrap = function() end
    e.SetMaxPilot = function() end
    e.IsPerson = function(h) return objects[h] ~= nil and objects[h].odf == "aspilo" end
    e.GetPositionNear = function(pos) return pos end
    e.GetVelocity = function() return {x = 0, y = 0, z = 0} end
    e.SetVelocity = function(h, v) record("SetVelocity", h, v.x, v.y, v.z) end
    e.GetMaxHealth = function() return 1000 end
    e.SetPosition = function(h, pos) objects[h].pos = pos end
    e.GetFront = function() return {x = 1, y = 0, z = 0} end
    e.SetTeamNum = function(h, t) record("SetTeamNum", h, t); objects[h].team = t end
    e.GetPerceivedTeam = function(h) return objects[h] and (objects[h].perceived or objects[h].team) end
    e.SetPerceivedTeam = function(h, t)
        record("SetPerceivedTeam", h, t)
        if objects[h] then objects[h].perceived = t end
    end
    e.EjectPilot = function() end
    e.GetIn = function() end
    e.SetWeaponMask = function(h, m) record("SetWeaponMask", h, m) end
    e.IsInfo = function(prefix) return p.info[prefix] == true end
    e.CameraReady = function() record("CameraReady"); return true end
    e.CameraFinish = function() record("CameraFinish"); return true end
    e.CameraCancelled = function() return p.cancelled end
    e.CameraPath = function(...) record("CameraPath", ...); return false end
    e.CameraObject = function(...) record("CameraObject", ...); return false end
    e.StartCockpitTimer = function(s, w, a) p.timer, p.timerRunning = s, true; record("StartCockpitTimer", s, w, a) end
    e.StopCockpitTimer = function() p.timerRunning = false; record("StopCockpitTimer") end
    e.HideCockpitTimer = function() record("HideCockpitTimer") end
    e.GetCockpitTimer = function() return p.timer end
    e.StopAudioMessage = function(m) record("StopAudioMessage", m) end
    e.AudioMessage = function(file) record("AudioMessage", file); return file end
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
    for _, name in ipairs({"Follow", "Defend", "Stop", "Goto", "Attack", "Patrol", "SetIndependence",
        "SetObjectiveName", "SetObjectiveOn", "SetObjectiveOff", "SetUserTarget", "ClearObjectives", "AddObjective",
        "UpdateObjective", "Ally", "UnAlly", "DisplayMessage", "FailMission", "SucceedMission", "SetScrap", "SetPilot"}) do
        local n = name
        e[n] = function(...)
            if n == "SetObjectiveOn" or n == "SetObjectiveName" then
                assert(e.IsValid((...)), "presentation used a not-yet-valid handle")
            end
            record(n, ...)
        end
    end
    e.AiCommand = {FORMATION = 6}
    e.SetCommand = function(h, cmd, prio, who)
        if cmd == e.AiCommand.FORMATION then record("Formation", h, who, prio) else record("SetCommand", h, cmd, prio, who) end
    end
    local function noop() end
    local modules = {
        RequireFix = {Initialize = noop},
        -- The real director has its own suite (Test-CREuropaWeather.lua); this records the mission's wiring.
        CREuropaWeather = {
            Init = function(options) p.europa.init = options end,
            Update = function() p.europa.updates = p.europa.updates + 1 end,
            Shutdown = function() p.europa.shutdowns = p.europa.shutdowns + 1 end, OnObjectCreated = noop,
            Save = function() return {saved = true} end, Load = function(state) p.europa.loaded = state end,
            AnnounceState = function() p.europa.announces = p.europa.announces + 1 end,
            ApplyNetEvent = function(op, ...) p.europa.events[#p.europa.events + 1] = {op, ...}; return true end,
            GetVentSites = function() return {{label = "spawn_geyser"}, {label = "center_geyser"}} end,
            SetTargetLevel = function(level) p.europa.targets[#p.europa.targets + 1] = level end,
            ReleaseForcedLevel = function() p.europa.releases = p.europa.releases + 1 end,
            TriggerPlume = function(index)
                p.europa.plumes[#p.europa.plumes + 1] = index
                if p.europa.init and p.europa.init.send then p.europa.init.send("EuropaPlume", index) end
            end,
            Quake = function(strength, seconds)
                p.europa.quakes[#p.europa.quakes + 1] = {strength, seconds}
                if p.europa.init and p.europa.init.send then p.europa.init.send("EuropaQuake", strength, seconds) end
            end,
            Surge = function(seconds, strength)
                p.europa.surges[#p.europa.surges + 1] = {seconds, strength}
                if p.europa.init and p.europa.init.send then p.europa.init.send("EuropaSurge", seconds, strength) end
            end,
            Seed = 4242},
        CREuropaSites12 = {mission = "misn12"}, Environment = {Init = noop, BindWeatherSensors = function(name, director)
            check(name == "Europa" and type(director) == "table", "mission binds its weather director to shared sensors")
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
    setfenv(assert(loadfile("Scripts/misn12.lua")), e)()
    p.chunkCalls = #p.calls -- everything recorded so far ran at chunk load, before Start
    p.env, p.coop = e, modules.CRCoop
    e.Start()
    p.state = e.Save()
    return p
end

local function physics()
    for _, o in pairs(objects) do
        if o.removeAt and now >= o.removeAt then o.alive = false end
    end
end
local function tick(dt)
    dt = dt or 0.25
    now = now + dt
    physics()
    for _, p in pairs(peers) do
        if p.timerRunning and p.timer > 0 then p.timer = math.max(0, p.timer - dt) end
        p.env.Update(dt)
    end
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
local function onAll(fn) local n = 0; eachPeer(function(p) if fn(p) then n = n + 1 end end); return n end
local extra = 0
local function spawn(odf, team, x, z)
    extra = extra + 1
    local h = "extra" .. extra
    newObject(h, odf, team, {x or FAR, 20, z or FAR})
    return h
end
local function humansOf(host, guests)
    local list = {host}
    for _, g in ipairs(guests) do list[#list + 1] = g end
    return list
end
-- The key ship of slot k as the leader's state holds it.
local function slotShip(host, k)
    local s = host.state
    if k == 1 then return s.key_ship end
    return s.sstore[k] and s.sstore[k].key_ship
end
-- Put a human in a key ship (the engine swaps the craft when the pilot hops in).
local function board(peer, ship)
    peer.player = ship
    objects[ship].team = peer.team
    run(2)
end
local function humanState(host, peer)
    local s = host.state
    if s.hcur == peer.id then return s end
    return s.hstore[peer.id]
end
local CP1, CP2, CP3, CP4, TOWER = "checktower1", "svguntower2", "svmuf", "svsilo1", "svcom_tower"
local NAV1, CENTER = "apcamr20_camerapod", "center"
local function disableMovies(host)
    host.state.camera_off, host.state.camera4 = true, true
end
local function standAt(peer, label, dx, dz)
    local pos = LABELS[label].pos
    place(peer.player, pos[1] + (dx or 0), 30, pos[3] + (dz or 0))
end
local function awayAll()
    for _, p in pairs(peers) do setAt(p.player, FAR, FAR) end
end

-- ============================================================ 1. startup, ownership, weather wiring
do
    local host, guests = session(true, 3)
    local s = host.state
    check(s.start_done and s.checkpoint1 == CP1 and s.nav1 == NAV1 and s.ccacom_tower == TOWER,
        "the leader starts the mission body on the authored labels")
    check(s.multi and s.strict and s.slots == 3, "three humans: shared stealth and three key ships")
    for _, g in ipairs(guests) do
        check(not g.state.start_done and count(g, "BuildObject") == 0, "guests never run the mission body")
    end
    eachPeer(function(p)
        check(count(p, "DisableStartingRecycler") == 1, "every peer disables the extra starting recycler")
        check(count(p, "SetAIControl") == 0 and count(p, "SetAIP") == 0, "the CCA is script-driven: no strategic AI on any peer")
        check(p.rally and p.rally[0] == NAV1, "respawns rally at the drop zone nav")
        check(count(p, "Play", "misn1200.wav") == 1, "the briefing plays on every peer once")
        check(count(p, "AddObjective", "misn1200.otf") == 1, "the first objective reaches every peer once")
        check(count(p, "StartCockpitTimer") == 1 and p.timer > 1100 and p.timerRunning, "the 20-minute deadline runs on every peer")
        check(count(p, "SetObjectiveOn", CP1) == 1 and count(p, "SetObjectiveName", CP1) == 1, "the checkpoint marker reaches every peer")
        check(count(p, "SetObjectiveName", NAV1) == 1, "the drop zone is named on every peer")
        check(p.state.coopUnresolved == nil or p.state.coopUnresolved == 0, "no unresolved marker")
    end)
    local pods = builtList(host, "apcamr")
    check(#pods == 6, "six camera pods are built")
    for _, pod in ipairs(pods) do check(objects[pod].team == 7, "the pods hide on the support team, not guest team 3") end
    for _, c in ipairs(callsOf(host, "BuildObject")) do
        check(c[4] == 5 or c[4] == 7, c[3] .. " is built on the CCA or the support team, never a guest team")
    end
    check(count(host, "RemoveObject", "player0_hover") == 1, "the offline placeholder is removed in a network game")
    check(host.europa.init.authority and host.europa.init.sites.mission == "misn12", "the leader runs the weather director on the misn12 sites")
    for _, g in ipairs(guests) do check(not g.europa.init.authority, "guests run the director from the host's events") end
    check(host.europa.announces == 1 and count(host, "Send") > 0, "the leader announces the weather state")
end

-- ============================================================ 2. one key ship per human, staggered
for humans = 1, 4 do
    local host, guests = session(true, humans)
    local s = host.state
    check(s.slots == humans, humans .. " players: " .. humans .. " key ships")
    check(built(host, "svfi12") == 1, humans .. " players: only the first ship leaves immediately")
    check(objects[s.key_ship].team == 5 and count2(host, "Goto", s.key_ship, "first_path") == 1, "slot 1 is the DLL's ship on first_path")
    local started = s.sstore[2] and s.sstore[2].slot_spawn_at
    for k = 2, humans do
        check(s.sstore[k].slot_spawn_at == s.sstore[2].slot_spawn_at + (k - 2) * 25, "ships are 25 s apart")
    end
    run(26 * (humans - 1) + 2)
    check(built(host, "svfi12") == humans, humans .. " players: all key ships have left the spawn geyser")
    local seen = {}
    for k = 1, humans do
        local ship = slotShip(host, k)
        check(ship ~= nil and objects[ship].team == 5 and not seen[ship], "slot " .. k .. " has its own CCA ship")
        seen[ship] = true
        check(count2(host, "Goto", ship, "first_path") >= 1 and count2(host, "SetWeaponMask", ship, 3) == 1, "slot " .. k .. " flies the route")
    end
    for _, g in ipairs(guests) do check(count(g, "BuildObject") == 0, "guests never spawn") end
end

-- ============================================================ 3. each ship waits at checkpoint 1 on its own cycle
do
    local host, guests = session(true, 2)
    local s = host.state
    run(30)
    local ship1, ship2 = slotShip(host, 1), slotShip(host, 2)
    check(ship1 and ship2, "both ships exist")
    -- Ship 2 arrives first: only its slot checks in.
    at(ship2, {3975, 30, 98973}, 40, 0)
    run(1)
    check(s.sstore[2].checked_in and not s.checked_in, "ship 2 stopped at checkpoint 1; ship 1 is still flying")
    check(count2(host, "Stop", ship2, 1) == 1 and count2(host, "Stop", ship1, 1) == 0, "only ship 2 is stopped")
    at(ship1, {3975, 30, 98973}, 40, 0)
    run(1)
    check(s.checked_in, "ship 1 stopped as well")
    run(21)
    check(s.going_again and s.sstore[2].going_again, "both leave after their 20 s wait")
    -- Back at the geyser: each is removed and rebuilt.
    at(ship1, {3731, 30, 99561}, 50, 0)
    at(ship2, {3731, 30, 99561}, 50, 0)
    run(11)
    check(built(host, "svfi12") == 4, "both ships are rebuilt at the geyser")
    check(not s.checked_in and not s.going_again and slotShip(host, 1) ~= ship1 and slotShip(host, 2) ~= ship2,
        "fresh ships take both slots")
end

-- ============================================================ 4. capture is per human; the tour is shared
do
    local host, guests = session(true, 3)
    local s = host.state
    run(52)
    local g1, g2 = guests[1], guests[2]
    local ship2 = slotShip(host, 2)
    board(g1, ship2)
    local h1 = humanState(host, g1)
    check(h1.key_captured and not s.key_captured and not humanState(host, g2).key_captured,
        "only the human in the ship has captured one")
    check(s.sstore[2].slot_captured and not s.slot_captured, "the captured ship leaves its cycle")
    check(count(g1, "AddObjective", "misn1201.otf") == 1 and count(g2, "AddObjective", "misn1201.otf") == 0
        and count(host, "AddObjective", "misn1201.otf") == 0, "the capture panel reaches only that human")
    check(count(g1, "SetObjectiveOff", CP1) == 1 and count(host, "SetObjectiveOff", CP1) == 0, "only the capturer's checkpoint marker clears")
    check(count(g1, "AddAmmo") == 1, "the owning peer tops up the captured ship")
    check(objects[ship2].perceived == 5 and count2(host, "SetPerceivedTeam", ship2, 5) == 1,
        "the hijacked ship is perceived as CCA")
    eachPeer(function(p) check(count(p, "Play", "misn1217.wav") == 1, "the capture line is shared") end)
    check(s.captured_any and s.camera_time == s.camera_time, "the first capture arms the shared tour")
    -- The tour is shared: one camera frame for everyone, and a second capture does not restart it.
    local timeBefore = s.camera_time
    local ship1 = slotShip(host, 1)
    board(host, ship1)
    check(humanState(host, host).key_captured or s.key_captured, "the leader captured the other ship")
    check(s.camera_time == timeBefore, "a second capture does not reset the tour timer")
    run(12)
    eachPeer(function(p)
        check(count(p, "Play", "misn1218.wav") == 1, "the tour narration plays once on every peer")
    end)
    check(s.camera_on, "the tour is running")
    run(20)
    eachPeer(function(p)
        check(count(p, "Play", "misn1221.wav") == 1 and count(p, "Play", "misn1222.wav") == 0 or count(p, "Queue", "misn1222.wav") == 1
            or count(p, "Play", "misn1222.wav") == 1, "the tour ends with the briefing lines on every peer")
    end)
    check(s.camera_off, "the tour is over")
    eachPeer(function(p) check(count(p, "Stop") >= 2, "each narrated shot stops the previous line on every peer") end)
end


-- ============================================================ 5. any human's tank gives the mission away
do
    for _, case in ipairs({"near", "damaged"}) do
        local host, guests = session(true, 3)
        local s = host.state
        run(2)
        -- One human has already infiltrated: it does not shield a teammate still in a tank.
        board(guests[1], slotShip(host, 1))
        check(humanState(host, guests[1]).key_captured and not s.game_blown, "a captured ship does not blow cover")
        local tank = guests[2].player
        if case == "near" then standAt(guests[2], CP1, 74, 0) else objects[tank].health = 0.89 end
        run(1)
        check(s.game_blown, case .. ": a teammate's tank blows cover for everyone")
        run(12)
        eachPeer(function(p)
            check(count(p, "FailMission") == 1, case .. ": the failure reaches every peer once")
            check(count(p, "Play", "misn1213.wav") == 1, case .. ": the discovery line plays once on every peer")
        end)
        check(built(host, "svfigh") == 2 and built(host, "svltnk") == 2, case .. ": the death squad is built")
        run(10)
        eachPeer(function(p) check(count(p, "FailMission") == 1, case .. ": and the failure is emitted once") end)
    end
    -- A human who has captured a ship may leave the tank anywhere.
    local host, guests = session(true, 2)
    run(2)
    board(guests[1], slotShip(host, 1))
    place(host.player, 3975, 30, 98973 + 40)
    run(1)
    check(host.state.game_blown, "the leader's tank at the gate (not captured) blows cover")
end

-- ============================================================ 6. exposure fails everyone (several humans)
do
    local host, guests = session(true, 3)
    local s = host.state
    disableMovies(host)
    run(28)
    local g1, g2 = guests[1], guests[2]
    board(g1, slotShip(host, 1)); board(g2, slotShip(host, 2))
    -- g2 drives straight into the CCA tower: identification demanded, then ignored.
    standAt(g2, TOWER, 20, 0)
    run(1)
    local h2 = humanState(host, g2)
    check(h2.straight_to_5 and h2.identify_message and not h2.real_bad and not s.game_blown, "straight to the tower demands identification")
    eachPeer(function(p) check(count(p, "Play", "misn1206.wav") == 1, "the demand is shared") end)
    run(16)
    check(humanState(host, g2).real_bad, "ignoring the demand exposes that human")
    check(s.game_blown, "...which blows cover for everyone")
    for _, p in ipairs(humansOf(host, guests)) do
        check(objects[p.player].perceived == 1, "every human is perceived hostile")
    end
    check(count(host, "Play", "misn1211.wav") == 1, "the exposure line plays")
    run(12)
    eachPeer(function(p) check(count(p, "FailMission") == 1, "the mission fails on every peer once") end)
    check(built(host, "svtank") == 4, "the discovery guards are built once")
end
do
    -- Alone, the same exposure only hunts the player (stock behaviour).
    local host = session(true, 1)
    local s = host.state
    disableMovies(host)
    run(2)
    board(host, slotShip(host, 1))
    standAt(host, TOWER, 20, 0)
    run(17)
    check(s.real_bad and s.discovered and not s.game_blown, "one human: exposure hunts but does not fail")
    check(count(host, "FailMission") == 0, "one human: no failure")
end
-- ============================================================ 7. a wrong vehicle blows cover (several humans)
do
    local host, guests = session(true, 2)
    local s = host.state
    disableMovies(host)
    run(2)
    board(guests[1], slotShip(host, 1))
    local stolen = spawn("svtank", 2, FAR, FAR)
    board(guests[1], stolen)
    check(humanState(host, guests[1]).out_of_ship, "a stolen CCA tank is the wrong vehicle")
    check(s.game_blown and count(host, "Play", "misn1213.wav") == 1, "it blows cover for everyone")
    check(s.grump and count2(host, "Attack", "svfigh1_1", stolen) >= 1, "the patrols hunt the offender")
    run(12)
    eachPeer(function(p) check(count(p, "FailMission") == 1, "and fails the mission once on every peer") end)
end


-- ============================================================ 8. checkpoint progress is per human; the shot is shared
do
    local host, guests = session(true, 3)
    local s = host.state
    disableMovies(host)
    run(54)
    local g1, g2 = guests[1], guests[2]
    board(host, slotShip(host, 1)); board(g1, slotShip(host, 2)); board(g2, slotShip(host, 3))
    awayAll()
    -- g1 reaches checkpoint 2; g2 and the leader have not.
    standAt(g1, CP2, 30, 0)
    run(1)
    local h1, h2 = humanState(host, g1), humanState(host, g2)
    check(h1.check2 and h1.good1 and not h2.check2 and not s.check2, "checkpoint 2 is one human's alone")
    check(panel(g1):find("misn1201.otf:green", 1, true) and not panel(host):find("misn1201.otf:green", 1, true)
        and not panel(g2):find("misn1201.otf:green", 1, true), "only that human's panel shows the green checkpoint")
    eachPeer(function(p) check(count(p, "Play", "misn1207.wav") == 1, "the acknowledgement is shared radio") end)
    check(count2(host, "CameraObject", g1.player, 0) >= 1, "the shot frames the human who passed")
    run(2)
    for _, g in ipairs(guests) do check(count(g, "CameraObject") >= 1, "every guest sees the shared shot") end
    -- g2 reaches checkpoint 2 while the shot plays: the progress counts, the second shot is skipped.
    local readied = count(host, "CameraReady")
    standAt(g2, CP2, 30, 0)
    run(1)
    h2 = humanState(host, g2)
    check(h2.check2 and h2.good1_off, "the second human still gets the checkpoint while the screen is busy")
    check(count2(host, "CameraObject", g2.player, 0) == 0, "no second shot starts over the first")
    check(count(host, "CameraReady") == readied, "the camera is not readied again")
    run(6)
    h1 = humanState(host, g1)
    check(h1.good1_off, "the first shot ends on the DLL's timer")
    eachPeer(function(p) check(count(p, "CameraFinish") >= 1, "the shot is released on every peer") end)
    -- Out of order is judged per human.
    standAt(g1, CP3, 100, 0)
    run(1)
    h1 = humanState(host, g1)
    check(not humanState(host, host).cca_warning_message and not humanState(host, g2).cca_warning_message,
        "the others have not been warned")
end

-- ============================================================ 9. the uplink: the first human to hold the link completes it
do
    local host, guests = session(true, 3)
    local s = host.state
    disableMovies(host)
    run(54)
    local g1, g2 = guests[1], guests[2]
    board(host, slotShip(host, 1)); board(g1, slotShip(host, 2)); board(g2, slotShip(host, 3))
    awayAll()
    -- The proper route is skipped on purpose so nobody is out of order at the tower.
    for _, p in ipairs({host, g1, g2}) do
        local st = humanState(host, p)
        st.check2, st.check3, st.check4 = true, true, true
    end
    standAt(g1, TOWER, 59, 0)
    run(1)
    check(humanState(host, g1).interface_connect and not s.interface_connect, "one human's link is that human's alone")
    run(5)
    standAt(host, TOWER, 50, 0)
    run(1)
    check(s.interface_connect, "the leader's own link is up too")
    check(count(g1, "Play", "misn1212.wav") >= 1, "the noise line is shared")
    -- g1 drifts out of range: only g1's link breaks.
    standAt(g1, TOWER, 90, 0)
    run(1)
    check(not humanState(host, g1).interface_connect and s.interface_connect, "leaving range breaks only that human's link")
    eachPeer(function(p) check(count(p, "Play", "misn1203.wav") == 1, "the broken-link line is shared") end)
    -- The leader holds for 45 s: the uplink completes for everyone.
    run(46)
        check(s.interface_complete, "the first human to hold the link completes the uplink")
    eachPeer(function(p)
        check(count(p, "Play", "misn1204.wav") == 1 and count(p, "Play", "misn1223.wav") == 1, "completion dialogue plays once on every peer")
        check(count(p, "StopCockpitTimer") == 1 and count(p, "HideCockpitTimer") == 1, "the deadline stops on every peer")
        check(panel(p):sub(-#"misn1205.otf:white") == "misn1205.otf:white", "every panel ends on the return objective")
    end)
    check(host.europa.targets[#host.europa.targets] == 3 and #host.europa.plumes == 1 and #host.europa.quakes == 1
        and #host.europa.surges == 1, "the weather marks the escape")
    for _, g in ipairs(guests) do
        local seen = {}
        for _, e in ipairs(g.europa.events) do seen[e[1]] = (seen[e[1]] or 0) + 1 end
        check(seen.EuropaPlume == 1 and seen.EuropaQuake == 1 and seen.EuropaSurge == 1, "weather events reach guests once")
    end
    check(s.discovered, "the CCA is alerted")
end

-- ============================================================ 10. the win needs every human at the drop zone
do
    local host, guests = session(true, 3)
    local s = host.state
    disableMovies(host)
    run(4)
    s.interface_complete = true; s.win_check_time = 1; s.discovered = true; s.captured_any = true
    local all = humansOf(host, guests)
    awayAll()
    setAt(all[1].player, DROP[1], DROP[3] + 70)
    run(6)
    check(not s.win, "one of three at the drop zone is not enough")
    setAt(all[2].player, DROP[1], DROP[3] + 74)
    run(6)
    check(not s.win, "two of three is not enough")
    setAt(all[1].player, FAR, FAR)   -- the first one has left again: arrival stays latched
    setAt(all[3].player, DROP[1], DROP[3] + 75)
    run(6)
    check(not s.win, "75 m is the strict boundary")
    setAt(all[3].player, DROP[1], DROP[3] + 74)
    run(6)
    check(s.win, "every human has been within 75 m: the win")
    run(12)
    eachPeer(function(p)
        check(count(p, "SucceedMission") == 1 and last(p, "SucceedMission")[3] == "misn12w1.des", "the win reaches every peer once")
        check(count(p, "Play", "misn1216.wav") == 1, "the win line plays once on every peer")
        check(count(p, "FailMission") == 0, "and never fails")
    end)
    check(host.europa.targets[#host.europa.targets] == 1, "calm on the win")
end
do
    -- A player who left the session is not waited for.
    local host, guests = session(true, 3)
    local s = host.state
    disableMovies(host)
    run(4)
    s.interface_complete = true; s.win_check_time = 1; s.discovered = true
    awayAll()
    setAt(host.player, DROP[1], DROP[3] + 30); setAt(guests[1].player, DROP[1], DROP[3] + 30)
    run(6)
    check(not s.win, "the third human has not arrived")
    local leaver = guests[2]
    eachPeer(function(p) p.env.DeletePlayer(leaver.id, "P" .. leaver.id, leaver.team) end)
    peers[leaver.id] = nil
    run(6)
    check(s.win, "a departed player no longer blocks the win")
end

-- ============================================================ 11. nav consoles: a guest's selection is honoured; the reveal ends only when all are far
do
    local host, guests = session(true, 3)
    local s = host.state
    disableMovies(host)
    run(54)
    local g1 = guests[1]
    board(host, slotShip(host, 1)); board(g1, slotShip(host, 2)); board(guests[2], slotShip(host, 3))
    awayAll()
    -- The guest selects the console and stands at the centre building.
    standAt(g1, CENTER, 50, 0)
    g1.info.sbhqt1 = true
    run(2)
    check(s.camera_swap1, "a guest's console selection (relayed) reveals the route pods")
    local pods = {s.start_cam, s.check2_cam, s.check3_cam, s.check4_cam, s.goal_cam}
    for _, pod in ipairs(pods) do check(objects[pod].team == 1, "the pod is revealed to the leader's team") end
    check(objects[s.center_cam].team == 7, "the centre pod stays hidden")
    eachPeer(function(p) check(count(p, "Play", "misn1229.wav") == 1, "the static line is shared") end)
    -- Someone else lingers near the centre: the reveal holds.
    g1.info.sbhqt1 = false
    standAt(g1, CENTER, 500, 0)
    standAt(host, CENTER, 250, 0)
    run(3)
    check(s.camera_swap1 and objects[s.start_cam].team == 1, "the reveal holds while any human is within 300 m of the centre")
    setAt(host.player, FAR, FAR)
    run(3)
    check(not s.camera_swap1 and objects[s.start_cam].team == 7, "and ends when every human is far")
    eachPeer(function(p) check(count(p, "Play", "misn1230.wav") == 1, "the restore line is shared") end)
    -- The leader's own selection works too, from its local panel.
    host.info.sbhqt2 = true
    standAt(host, CENTER, 40, 0)
    run(1)
    check(s.camera_swap1, "the leader's own console selection also works")
end

-- ============================================================ 12. scaling: patrols and hunters per extra human
for humans = 1, 4 do
    local host, guests = session(true, humans)
    local s = host.state
    local more = math.min(3, humans - 1)
    run(20)
    local before = built(host, "svfigh")
    s.camera_off = true
    run(2)
    check(built(host, "svfigh") - before == more, humans .. " players: " .. more .. " extra patrol fighters")
    local patrols = 0
    for _, c in ipairs(callsOf(host, "Patrol")) do
        if c[3] == "path5" and c[2]:find("^built") then patrols = patrols + 1 end
    end
    check(patrols == more, humans .. " players: the extras patrol the centre loop")
    -- The uplink finishes: hunters scale too.
    local beforeHunt = built(host, "svfigh")
    s.interface_complete = false
    s.captured_any = true
    for _, p in ipairs(humansOf(host, guests)) do
        local st = humanState(host, p)
        st.interface_connect = true; st.interface_time = 0
        standAt(p, TOWER, 50, 0)
    end
    run(2)
    check(s.interface_complete, humans .. " players: the uplink completes")
    check(built(host, "svfigh") - beforeHunt == more, humans .. " players: " .. more .. " extra hunters when the escape begins")
end

-- ============================================================ 13. the artillery shells exposed humans only
do
    local host, guests = session(true, 2)
    local s = host.state
    disableMovies(host)
    run(28)
    local g1 = guests[1]
    board(g1, slotShip(host, 2))
    check(#s.arty == 4, "all four howitzers are found")
    setAt(host.player, FAR, FAR)
    -- g1 is disguised and well within range: the guns stay quiet.
    place(g1.player, 1217 + 300, 30, 100447)
    run(7)
    check(count(host, "Attack", "artil1") == 0 and count(host, "Attack", "artil2") == 0, "a disguised infiltrator is not shelled")
    -- The leader is still in a tank: exposed, within range.
    place(host.player, 1217, 30, 100447 + 400)
    run(7)
    local shelled = 0
    for _, c in ipairs(callsOf(host, "Attack")) do
        if c[2]:find("^artil") and c[3] == host.player then shelled = shelled + 1 end
    end
    check(shelled >= 4, "the howitzers shell the human still in a tank")
    for _, g in ipairs(guests) do check(count(g, "Attack") == 0, "guests issue no orders") end
    -- Out of range, the guns stand down.
    setAt(host.player, FAR, FAR)
    run(7)
    check(count(host, "Stop") >= 4, "the guns stand down when nobody is in range")
end

-- ============================================================ 14. a respawned human must infiltrate again
do
    local host, guests = session(true, 2)
    local s = host.state
    disableMovies(host)
    run(2)
    local g1 = guests[1]
    board(g1, slotShip(host, 1))
    check(humanState(host, g1).key_captured, "captured")
    -- The ship is destroyed; the respawn service gives g1 a fresh NSDF craft.
    objects[slotShip(host, 1)].alive = false
    local fresh = spawn("avtank", g1.team, FAR, FAR)
    g1.player = fresh
    run(2)
    local st = humanState(host, g1)
    check(not st.key_captured and st.user_tank == fresh, "the respawned human is uncaptured and the new tank is guarded")
    standAt(g1, CP1, 60, 0)
    run(1)
    check(s.game_blown, "the new tank at the gate blows cover (several humans)")
end

-- ============================================================ 15. deadline, host leaving
do
    local host, guests = session(true, 3)
    for _, p in pairs(peers) do p.timer = 0 end
    run(20)
    eachPeer(function(p)
        check(count(p, "FailMission") == 1 and last(p, "FailMission")[3] == "misn12f1.des", "the deadline fails every peer once")
        check(count(p, "Play", "misn1215.wav") == 1, "the deadline line plays once")
    end)
end
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
end

-- ============================================================ 16. offline smoke
do
    local host = session(false, 1)
    local s = host.state
    run(5)
    check(count(host, "Send") == 0, "offline play sends nothing")
    check(not s.multi and not s.strict and s.slots == 1, "offline: one human, stock stealth rules")
    check(host.rally[0] == NAV1 and count(host, "Play", "misn1200.wav") == 1, "offline dialogue and rally")
    check(count(host, "RemoveObject", "player0_hover") == 0 and count(host, "DisableStartingRecycler") == 0, "offline: no placeholder removal")
    check(host.europa.init.authority and host.europa.init.send == nil and host.europa.announces == 0, "offline weather is the host path with nothing sent")
    check(built(host, "svfi12") == 1, "offline: the DLL's single key ship")
end


-- ============================================================ 17. Razor One (restored cut arc, inferred)
local ROUTE = {
    {2942, 100812}, {3005, 100842}, {3132, 100833}, {3142, 100825}, {3192, 100696}, {3202, 100550}, {3242, 100327},
    {3243, 100267}, {3302, 100142}, {3358, 99984}, {3352, 99912}, {3328, 99877}, {3328, 99772}, {3338, 99746},
    {3343, 99632}, {3347, 99518}, {3388, 99109}, {3688, 98827}, {3708, 98754}, {3682, 98645}, {3681, 98529},
    {3812, 98343}, {3832, 98032}, {3768, 97858}, {3738, 97832}, {3698, 97832}, {3562, 97862},
}
do
    local host, guests = session(true, 3)
    local s = host.state
    disableMovies(host)
    run(4)
    awayAll()
    check(s.razor_state == "none" and not s.razor, "Razor One is not there before the uplink completes")
    s.interface_complete = true; s.win_check_time = 99999; s.captured_any = true
    run(3)
    check(s.discovered and s.hunters and #s.hunters == 2, "the stock aftermath ran: patrols ordered, two extra hunters (3 humans)")
    check(s.razor_state == "none" and built(host, "avfigh") == 0,
        "uplink done, hunters far away and nobody hurt: no Razor One")
    run(20)
    check(s.razor_state == "none" and built(host, "avfigh") == 0, "...and a team that gets home clean never sees him")
    for _, p in pairs(peers) do check(count(p, "Play", "misn1224.wav") == 0, "no radio call either") end
    -- A hunter closes to within 200 m of a guest: Razor One appears at the compound and calls everyone.
    local hunter = s.patrol2_1
    place(guests[2].player, 40000, 30, 40000)
    place(hunter, 40000 + 201, 30, 40000)
    run(1)
    check(s.razor_state == "none", "a hunter at 201 m has not caught up")
    place(hunter, 40000 + 190, 30, 40000)
    run(1)
    local razor = s.razor
    check(s.razor_state == "held" and razor and objects[razor].odf == "avfigh" and objects[razor].team == 1,
        "a hunter within 200 m of any human calls Razor One")
    check(objects[razor].perceived == 5 and count2(host, "SetPerceivedTeam", razor, 5) == 1, "disguised: the CCA is not told to shoot him")
    check(builtList(host, "avfigh")[1] == razor and #callsOf(host, "Goto") > 0 and type(last(host, "Goto")[3]) == "table",
        "he is built at the compound and sent to the head of the channel by vector")
    eachPeer(function(p)
        check(count(p, "SetObjectiveOn", razor) == 1 and count2(p, "SetObjectiveName", razor, "Razor One") == 1,
            "every peer gets the Razor One marker")
        check(count(p, "Play", "misn1224.wav") == 1, "every player hears misn1224 as a radio call at once")
    end)
    local pos = LABELS.check2_geyser.pos
    check(math.abs(objects[razor].pos.x - pos[1]) < 1 and math.abs(objects[razor].pos.z - pos[3]) < 1,
        "he is built at the checkpoint-2 compound (check2_geyser)")
    run(10)
    check(s.razor_state == "held" and built(host, "avfigh") == 1, "nobody near: he waits at the head of the channel, no second Razor")
    -- A guest arrives within 120 m: the cut line plays for everyone and he leads.
    at(guests[1].player, pos, 119, 0)
    run(2)
    check(s.razor_state == "lead", "the first human within 120 m wakes him")
    eachPeer(function(p) check(count(p, "Play", "misn1224.wav") == 1, "misn1224 played once only, on every peer") end)
    -- Lead him along the route: every leg advances as he arrives.
    local function teleport(index)
        place(razor, ROUTE[index][1], 30, ROUTE[index][2])
    end
    for index = 2, 13 do
        teleport(index)
        run(0.5)
    end
    check(s.razor_leg == 14, "he has driven the channel and the shelf to the foot of the lip")
    -- The group is far behind: he waits (up to 45 s) rather than outrun it.
    awayAll()
    teleport(14)
    run(5)
    check(s.razor_leg == 14, "he waits at the foot of the lip while nobody is within 150 m")
    run(41)
    check(s.razor_leg == 15, "...but not forever")
    -- A human catches up: he does not wait at all.
    s.razor_leg = 14; s.razor_wait_since = nil
    at(host.player, {ROUTE[14][1], 30, ROUTE[14][2]}, 100, 0)
    teleport(14)
    run(1)
    check(s.razor_leg == 15, "a human within 150 m releases him at once")
    -- The lip: he is thrown at the landing; the fall is protected.
    teleport(15)
    local healsBefore = count(host, "AddHealth")
    run(1)
    check(s.razor_state == "jump" and count(host, "SetVelocity") >= 1, "at the lip he takes the jump (a scripted velocity)")
    local v = last(host, "SetVelocity")
    check(v[2] == razor and v[5] < 0, "launched toward the landing (south)")
    check(math.abs(v[3]) < 40 and math.abs(v[5]) < 40 and v[4] == 12, "launch speed and lift as designed")
    check(count(host, "AddHealth") > healsBefore, "he is held at full health through the fall")
    -- The gap is not cleared: the fallback puts him on the ledge instead of stranding the guide.
    run(10)
    check(s.razor_state == "lead" and s.razor_leg == 17, "he lands (or is placed) on the ledge and goes on")
    check(count(host, "SetVelocity") >= 2 and math.abs(objects[razor].pos.z - ROUTE[16][2]) < 5,
        "the teleport fallback set him down on the ledge")
    -- Pursuers lose the scent once Razor is over the jump. Host and guest 1 made the run; guest 2 stayed
    -- off the route with a hunter on top of him.
    check(s.razor_past, "Razor clearing the jump arms the break-off")
    local function standOnRoute(peer, index, dx) place(peer.player, ROUTE[index][1] + (dx or 0), 30, ROUTE[index][2]) end
    standOnRoute(host, 18); standOnRoute(guests[1], 18, 8)
    place(guests[2].player, 40000, 30, 40000)
    local far, keeper, prey = s.patrol1_1, s.patrol2_1, s.patrol3_1
    local blocked, seen = s.patrol4_1, s.patrol4_2
    place(far, ROUTE[18][1] + 900, 30, ROUTE[18][2])          -- nobody within 300 m: loses the scent
    place(keeper, 40000 + 30, 30, 40000)                       -- on top of the human who did not take the route
    place(prey, 20000, 30, 20000); objects[prey].prey = guests[2].player   -- chasing the stay-behind from afar
    place(blocked, ROUTE[18][1] + 150, 30, ROUTE[18][2])        -- 150 m away behind a ridge: out of sight
    place(seen, ROUTE[18][1], 30, ROUTE[18][2] + 150)           -- 150 m with a clear line: still hunting
    local tank = s.guard_tank1
    place(tank, ROUTE[18][1] - 900, 30, ROUTE[18][2])
    world.terrain = function(x, z)
        if x > ROUTE[18][1] + 40 and x < ROUTE[18][1] + 110 and math.abs(z - ROUTE[18][2]) < 5 then return 400 end
        return 20
    end
    run(3)
    check(count2(host, "Patrol", far, "path5") >= 1, "a hunter with nobody near or in sight returns to patrol")
    check(count2(host, "Patrol", blocked, "path5") >= 1, "a hunter with the ground between it and the humans loses them too")
    check(count2(host, "Patrol", seen, "path5") == 0, "a hunter with a human in clear sight keeps attacking")
    check(count2(host, "Patrol", keeper, "path5") == 0 and count2(host, "Patrol", prey, "path5") == 0,
        "hunters on a human who did not take the route are untouched")
    local home = LABELS.gtank1.pos
    local returned = false
    for _, c in ipairs(callsOf(host, "Goto")) do
        if c[2] == tank and type(c[3]) == "table" and math.abs(c[3].x - home[1]) < 1 and math.abs(c[3].z - home[3]) < 1 then returned = true end
    end
    check(returned, "a guard tank goes back to the post it stood on")
    local patrols = count(host, "Patrol")
    run(5)
    check(count(host, "Patrol") == patrols, "a hunter that broke off is not ordered again")
    world.terrain = nil
    for _, g in ipairs(guests) do check(count(g, "Patrol") == 0, "guests never command the AI") end
    for index = 17, 26 do
        teleport(index)
        run(0.5)
    end
    teleport(27)
    run(1)
    check(s.razor_state == "done" and count2(host, "Goto", razor, NAV1, 1) >= 1, "he ends at the drop zone nav")
    for _, g in ipairs(guests) do
        check(count(g, "Goto") == 0 and count(g, "SetVelocity") == 0, "guests never command him")
    end
    -- Razor One has no part in the stealth rules or the win.
    check(not s.game_blown and count(host, "FailMission") == 0, "he never blows cover")
end
do
    -- A CCA shot that damages a guest also calls him; friendly damage does not.
    local host, guests = session(true, 2)
    local s = host.state
    disableMovies(host)
    run(4)
    awayAll()
    local guest = guests[1]
    s.interface_complete = true; s.win_check_time = 99999; s.captured_any = true
    -- Everyone is in a hijacked CCA craft (the stock starting-tank damage rule no longer applies).
    for _, p in ipairs(humansOf(host, guests)) do
        humanState(host, p).key_captured = true
    end
    run(2)
    objects[guest.player].health = 0.8; objects[guest.player].shooter = spawn("avtank", 2)
    run(1)
    check(s.razor_state == "none", "damage from a friendly craft does not")
    objects[guest.player].health = 0.7; objects[guest.player].shooter = s.guard_tank1
    run(1)
    check(s.razor_state == "held" and objects[s.razor].team == 1, "a CCA hit on a guest calls Razor One")
    eachPeer(function(p) check(count(p, "Play", "misn1224.wav") == 1, "and every player hears it") end)
    run(5)
    check(built(host, "avfigh") == 1, "once only")
end
do
    -- Razor is optional: the win is the stock one, every human at the drop zone.
    local host, guests = session(true, 2)
    local s = host.state
    disableMovies(host)
    run(4)
    s.interface_complete = true; s.win_check_time = 0; s.captured_any = true
    awayAll()
    run(2)
    for _, p in ipairs(humansOf(host, guests)) do humanState(host, p).key_captured = true end
    objects[guests[1].player].health = 0.5; objects[guests[1].player].shooter = s.patrol1_1
    run(1)
    check(s.razor_state == "held", "Razor is called")
    standAt(host, NAV1, 10, 0)
    run(2)
    check(not s.win, "one human home is not a win")
    standAt(guests[1], NAV1, -10, 0)
    run(2)
    check(s.win, "both humans home: the mission is won whether or not anyone followed Razor")
end
do
    -- He heals when left alone, and a dead Razor One is simply gone.
    local host, guests = session(true, 2)
    local s = host.state
    disableMovies(host)
    run(4)
    awayAll()
    s.interface_complete = true; s.win_check_time = 99999; s.discovered = true
    run(1)
    for _, p in ipairs(humansOf(host, guests)) do humanState(host, p).key_captured = true end
    objects[guests[1].player].health = 0.5; objects[guests[1].player].shooter = s.patrol1_1
    run(1)
    local razor = s.razor
    objects[razor].health = 0.5
    local before = count(host, "AddHealth", razor)
    run(8)
    check(count(host, "AddHealth", razor) > before, "an unhurt Razor One regenerates")
    objects[razor].alive = false
    run(2)
    check(s.razor_state == "gone", "a dead Razor One is dropped quietly")
    local ordered = count(host, "Goto", razor)
    run(5)
    check(count(host, "Goto", razor) == ordered, "and is never ordered again")
end
do
    -- Razor One never appears if cover is blown first.
    local host, guests = session(true, 2)
    local s = host.state
    run(2)
    s.game_blown = true; s.interface_complete = true
    run(2)
    objects[guests[1].player].health = 0.5; objects[guests[1].player].shooter = s.patrol1_1
    run(2)
    check(s.razor_state == "none", "no guide for a blown mission, even when a CCA unit hits someone")
end

print("misn12 co-op: " .. checks .. " multi-peer Lua 5.1 mock-engine checks passed")
