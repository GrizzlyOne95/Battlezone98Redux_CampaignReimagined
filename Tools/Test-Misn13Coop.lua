-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Run from the repository root: lua5.1 Tools/Test-Misn13Coop.lua
-- Executes the complete misn13 script in separate Lua 5.1 environments over the
-- real CRCoop registry and the E/A presentation transport. The engine, AI and combat
-- are mocks: they verify script decisions, not Redux native map loading, pathfinding,
-- Lua wire serialization or EXU hooks. The map coordinates below are the authored ones
-- (Missions/misn13.bzn). This file covers the MULTI-PEER behaviour; the offline DLL flow is
-- Tools/Test-Misn13.lua.
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

-- ---------------------------------------------------------------- world model
local now, objects, peers, nextObject, transport, pathPos, world, dropper, extra, dropCount
local function terrain(x, z) return 20 end
local function P(x, z, y) return {x, y or 30, z} end
local LABELS = {
    avrecycle = {odf = "avrecy", team = 1, pos = P(3488.8, 97963.4, 40.94)},
    apcamr20_camerapod = {odf = "apcamr", team = 1, pos = P(3571.09, 97860.7, 40.1)},
    player0_hover = {odf = "player", team = 1, pos = P(3530.01, 97877, 40.1)},
    svguntower1 = {odf = "sbhqt1", team = 5, pos = P(3980.79, 98969.3, 0)},
    svguntower2 = {odf = "sbhang", team = 5, pos = P(2865.69, 100840, 0)},
    svsilo1 = {odf = "sbsilo", team = 5, pos = P(1473.6, 99472.5, 19)},
    svsilo2 = {odf = "sbsilo", team = 5, pos = P(1469.6, 99532.5, 19)},
    svsilo3 = {odf = "sbsilo", team = 5, pos = P(1410.93, 99500.5, 19)},
    svsilo4 = {odf = "sbsilo", team = 5, pos = P(1413.6, 99439.2, 19.08)},
    svmuf = {odf = "svmuf13", team = 5, pos = P(1337.6, 100684, 1.5)},
    svslf = {odf = "svslf", team = 5, pos = P(3335.51, 98460.4, 85.25)},
    svcom_tower = {odf = "sbcomm", team = 5, pos = P(2144.75, 100439, 0)},
    center = {odf = "sbhqt2", team = 5, pos = P(2724, 99818.1, 0)},
    spawn_geyser1 = {odf = "eggeizr1", team = 0, pos = P(1921.39, 101021, 1.72)},
    spawn_geyser2 = {odf = "eggeizr1", team = 0, pos = P(2710.26, 99781.3, 0)},
    key_geyser1 = {odf = "eggeizr1", team = 0, pos = P(3680, 98648.8, 0.5)},
    key_geyser2 = {odf = "eggeizr1", team = 0, pos = P(3977.41, 98863.4, 0.37)},
    center_geyser = {odf = "eggeizr1", team = 0, pos = P(2757.6, 99784, 0)},
    split_geyser = {odf = "eggeizr1", team = 0, pos = P(3395.73, 98400.2, 83.38)},
    svscav1 = {odf = "svscav", team = 5, pos = P(1376.84, 99497.5, 19.5)},
    svscav2 = {odf = "svscav", team = 5, pos = P(1369.62, 99454.1, 19.5)},
    svscav3 = {odf = "svscav", team = 5, pos = P(1355.19, 99486.1, 19.5)},
    svscav4 = {odf = "svscav", team = 5, pos = P(1354.02, 99439.3, 19.5)},
    turret1 = {odf = "svturr", team = 5, pos = P(2902.26, 100702, 0.5)},
    turret2 = {odf = "svturr", team = 5, pos = P(2899.41, 100737, 0.5)},
    turret3 = {odf = "svturr", team = 5, pos = P(3229.54, 99614.5, 0.5)},
    turret4 = {odf = "svturr", team = 5, pos = P(3219.2, 99565.8, 0.5)},
    turret5 = {odf = "svturr", team = 5, pos = P(2923.13, 100601, 0.5)},
    turret6 = {odf = "svturr", team = 5, pos = P(2918.96, 100635, 1)},
    fighter1 = {odf = "svfigh", team = 5, pos = P(1354.33, 100734, 1.5)},
    fighter2 = {odf = "svfigh", team = 5, pos = P(1303.35, 100692, 1.5)},
    fighter3 = {odf = "svfigh", team = 5, pos = P(3407.3, 99585.4, 1.5)},
    fighter4 = {odf = "svfigh", team = 5, pos = P(3369.74, 99581.2, 1.5)},
    fighter5 = {odf = "svfigh", team = 5, pos = P(3144.59, 99704.2, 1.6)},
    fighter6 = {odf = "svfigh", team = 5, pos = P(3046.66, 99579.7, 2.6)},
    tank1 = {odf = "svtank", team = 5, pos = P(1569.29, 99656.4, 20.67)},
    tank2 = {odf = "svtank", team = 5, pos = P(1561.71, 99623.9, 20.19)},
    tank3 = {odf = "svtank", team = 5, pos = P(3447.81, 99603, 0.8)},
    tank4 = {odf = "svtank", team = 5, pos = P(3467.93, 99573.3, 0.92)},
    artil1 = {odf = "svartl", team = 5, pos = P(1222.13, 100426, 1.5)},
    artil2 = {odf = "svartl", team = 5, pos = P(1212.18, 100459, 2.18)},
    artil3 = {odf = "svartl", team = 5, pos = P(1183.85, 100421, 3.12)},
    artil4 = {odf = "svartl", team = 5, pos = P(1173.8, 100453, 1.5)},
    artil_escort1 = {odf = "svtank", team = 5, pos = P(1221.95, 100422, 0.8)},
    artil_escort2 = {odf = "svtank", team = 5, pos = P(1229.67, 100423, 0.8)},
    artil_escort3 = {odf = "svtank", team = 5, pos = P(1229, 100424, 0.8)},
    cca_reserve1 = {odf = "svtank", team = 5, pos = P(1374.11, 100401, 0.91)},
    cca_reserve2 = {odf = "svtank", team = 5, pos = P(1357.44, 100389, 1.4)},
}
local PATHS = {
    artil_path1 = {1363.73, 30, 100379},
    choke_point1 = {2989.91, 30, 99764.9},
    choke_point2 = {2992.14, 30, 99311.2},
    choke_point3 = {2080.28, 30, 99958.4},
    artil_point4 = {3432.8, 30, 98576},
    artil_point3 = {3548.8, 30, 98416},
    artil_point2 = {3514.93, 30, 98097.8},
    artil_point1 = {3608.27, 30, 97995.2},
    turret_path1 = {2898.83, 30, 100739},
    turret_path2 = {2898.83, 30, 100712},
    turret_path3 = {1598.88, 30, 99571},
    slf_path = {2878.9, 30, 100640},
    silo_spot = {1497.87, 30, 99531.2},
}
local FAR = 90000
local function vec(t) return {x = t[1], y = t[2], z = t[3]} end
local function newObject(handle, odf, team, pos)
    objects[handle] = {alive = true, odf = odf, team = team, health = 1, pos = vec(pos or {FAR, 20, FAR})}
    local o = objects[handle]
    if LABELS[handle] then o.label = handle end
    return o
end
local function reset()
    now, objects, peers, nextObject, extra = 0, {}, {}, 0, 0
    world = {scrap = {}, net = false, nearCount = nil, missing = {}}
    dropper = nil
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
-- Put `h` at (dx, dz) metres from `target` (an object label or a path name), at the target's own height.
local function nearTo(h, target, dx, dz)
    local t = posOf(target)
    place(h, t.x + (dx or 0), t.y, t.z + (dz or 0))
end
local function kill(h) objects[h].alive = false end
local function hurt(h, health) objects[h].health = health end

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
local function callsOf(peer, name)
    local out = {}
    for _, c in ipairs(peer.calls) do if c[1] == name then out[#out + 1] = c end end
    return out
end
local function last(peer, name)
    for i = #peer.calls, 1, -1 do if peer.calls[i][1] == name then return peer.calls[i] end end
end
local function firstIndex(peer, name)
    for i, c in ipairs(peer.calls) do if c[1] == name then return i end end
end
-- BuildObject calls at one location: (odf, where). Calls record {"BuildObject", handle, odf, team, where}.
local function builtAt(peer, odf, where)
    local n = 0
    for _, c in ipairs(peer.calls) do
        if c[1] == "BuildObject" and c[3] == odf and c[5] == where then n = n + 1 end
    end
    return n
end
local function buildsSince(peer, mark, where)
    local out = {}
    for i = mark + 1, #peer.calls do
        local c = peer.calls[i]
        if c[1] == "BuildObject" and (where == nil or c[5] == where) then
            out[#out + 1] = {h = c[2], odf = c[3], team = c[4], where = c[5]}
        end
    end
    return out
end
local function tally(list)
    local tanks, fighters = 0, 0
    for _, b in ipairs(list) do
        if b.odf == "svtank" then tanks = tanks + 1 elseif b.odf == "svfigh" then fighters = fighters + 1 end
    end
    return tanks, fighters
end
-- Orders recorded as {name, unit, target, priority}.
local function orders(peer, name, unit, target, priority)
    local n = 0
    for _, c in ipairs(peer.calls) do
        if c[1] == name and c[2] == unit and c[3] == target and c[4] == priority then n = n + 1 end
    end
    return n
end
local function ordersTo(peer, name, unit)
    local n = 0
    for _, c in ipairs(peer.calls) do if c[1] == name and c[2] == unit then n = n + 1 end end
    return n
end
local function attacksOn(peer, target, priority)
    local n = 0
    for _, c in ipairs(peer.calls) do
        if c[1] == "Attack" and c[3] == target and (priority == nil or c[4] == priority) then n = n + 1 end
    end
    return n
end
local function gotosTo(peer, unit, path)
    local n = 0
    for _, c in ipairs(peer.calls) do if c[1] == "Goto" and c[2] == unit and c[3] == path then n = n + 1 end end
    return n
end
local function sumOrders(peer, name, units, target, priority)
    local n = 0
    for _, u in ipairs(units) do n = n + orders(peer, name, u, target, priority) end
    return n
end

local function makePeer(id, team, network)
    local p = {id = id, team = team, net = network, hosting = team == 1, calls = {}, player = "player" .. id}
    p.eu = {updates = 0, announces = 0, shutdowns = 0, targets = {}, forces = {}, releases = 0, quakes = {},
        surges = {}, events = {}}
    peers[id] = p
    newObject(p.player, "avtank", team, {FAR + id, 20, FAR})
    local function record(name, ...)
        local c = {name, ...}
        c.t, c.n = now, select("#", ...)
        p.calls[#p.calls + 1] = c
    end
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
        if world.missing[label] then return nil end
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
    e.GetWhoShotMe = function(h) return objects[h] and objects[h].shotBy end
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
        -- in Test-Misn13.lua).
        if type(b) == "string" and objects[b] and not objects[b].alive then return 10000 end
        assert(type(b) == "string" and (objects[b] == nil or e.IsValid(b)) or e.IsValid(b), "invalid destination")
        local pa, pb = posOf(a), posOf(b)
        if pa and pb then
            local dx, dy, dz = pa.x - pb.x, pa.y - pb.y, pa.z - pb.z
            return math.sqrt(dx * dx + dy * dy + dz * dz)
        end
        return 10000
    end
    -- The factory-safety census. `world.nearCount[team]` overrides the geometry so a test can dictate it.
    e.CountUnitsNearObject = function(target, radius, team, odf)
        record("CountUnitsNearObject", target, radius, team, odf)
        assert(e.IsAlive(target), "unit census around a dead object")
        if world.nearCount then return world.nearCount[team] or 0 end
        local n, at = 0, objects[target].pos
        for h, o in pairs(objects) do
            if o.alive and h ~= target and o.team == team and (odf == nil or o.odf == odf) then
                local dx, dz = o.pos.x - at.x, o.pos.z - at.z
                if math.sqrt(dx * dx + dz * dz) < radius then n = n + 1 end
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
    for _, name in ipairs({"Follow", "Defend", "Retreat", "Stop", "Goto", "Attack", "SetIndependence", "SetAIP",
        "SetAIControl", "SetObjectiveName", "SetObjectiveOn", "SetObjectiveOff", "SetUserTarget", "ClearObjectives",
        "AddObjective", "UpdateObjective", "Ally", "UnAlly", "DisplayMessage", "FailMission", "SucceedMission",
        "SetScrap", "AddScrap", "SetPilot", "Pickup"}) do
        local n = name
        e[n] = function(...)
            if n == "SetObjectiveOn" or n == "SetObjectiveName" then
                assert(e.IsValid((...)), "presentation used a not-yet-valid handle")
            end
            record(n, ...)
            if n == "SetScrap" then world.scrap[(...)] = select(2, ...) end
            if n == "AddScrap" then world.scrap[(...)] = (world.scrap[(...)] or 0) + select(2, ...) end
        end
    end
    e.AiCommand = {FORMATION = 6}
    e.SetCommand = function(h, cmd, prio, who) record("SetCommand", h, cmd, prio, who) end
    local function noop() end
    local modules = {
        RequireFix = {Initialize = noop},
        -- The real director has its own suite (Test-CREuropaWeather.lua); this records the mission's wiring:
        -- what it was initialised with, the beats, and the events it received. Plume/Quake/Surge behave like
        -- the authority director: they queue their event onto the mission's ordered stream.
        CREuropaWeather = {
            Init = function(options) p.eu.init = options end,
            Update = function() p.eu.updates = p.eu.updates + 1 end,
            Shutdown = function() p.eu.shutdowns = p.eu.shutdowns + 1 end, OnObjectCreated = noop,
            Save = function() return {saved = true} end, Load = function(state) p.eu.loaded = state end,
            AnnounceState = function() p.eu.announces = p.eu.announces + 1 end,
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
        CREuropaSites13 = {mission = "misn13"}, Environment = {Init = noop, BindWeatherSensors = function(name, director)
            check(name == "Europa" and type(director) == "table", "mission binds its weather director to shared sensors")
            p.sensorBinding = name
        end, Update = noop, OnObjectCreated = noop},
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
    setfenv(assert(loadfile("Scripts/misn13.lua")), e)()
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
    transport:Step(now, false, dropper)
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
-- `pre` runs before any peer exists (world tweaks); `post(host, guests)` runs after registration, before play.
local function session(network, humans, pre, post, settle)
    reset()
    world.net = network
    if pre then pre() end
    local host = makePeer(10, 1, network)
    local guests = {}
    for i = 2, (humans or 4) do guests[#guests + 1] = makePeer(10 * i, i, network) end
    registerAll()
    if post then post(host, guests) end
    run(settle or 3)
    return host, guests
end
local function eachPeer(fn) for _, p in pairs(peers) do fn(p) end end
local function playedOnAll(file)
    local n = 0
    eachPeer(function(p) if count(p, "Play", file) == 1 then n = n + 1 end end)
    return n
end
local function peerCount()
    local n = 0
    eachPeer(function() n = n + 1 end)
    return n
end
local function spawn(odf, team, x, z)
    extra = extra + 1
    local h = "extra" .. extra
    newObject(h, odf, team, {x or FAR, 20, z or FAR})
    return h
end
local function makeDropper(rate)
    local seed = 12345
    dropCount = 0
    return function(packet)
        if packet.ackOnly then return false end
        if packet.kind ~= "E" and packet.kind ~= "A" then return false end
        seed = (seed * 16807) % 2147483647
        if seed / 2147483647 < rate then dropCount = dropCount + 1; return true end
        return false
    end
end

-- Every call a guest must never make: the mission body is the leader's alone.
local LEADER_ONLY = {"BuildObject", "Goto", "SetAIP", "SetScrap", "SetPilot", "Attack", "Follow", "Defend", "Retreat",
    "AddScrap", "SetIndependence"}
local function silentGuests(guests, tag)
    for _, g in ipairs(guests) do
        for _, name in ipairs(LEADER_ONLY) do
            check(count(g, name) == 0, tag .. "a guest never calls " .. name)
        end
    end
end
-- The presentation stream as one peer saw it, in order: the leader and every guest must agree.
local PRESENTATION = {Play = true, ClearObjectives = true, AddObjective = true, UpdateObjective = true,
    SetObjectiveName = true, SetObjectiveOn = true, SetObjectiveOff = true, RemoveObject = true,
    SucceedMission = true, FailMission = true}
local function presentationLog(p)
    local out = {}
    for _, c in ipairs(p.calls) do
        if PRESENTATION[c[1]] then
            if c[1] == "SucceedMission" or c[1] == "FailMission" then
                out[#out + 1] = c[1] .. ":" .. tostring(c[3])
            else
                out[#out + 1] = c[1] .. ":" .. tostring(c[2]) .. ":" .. tostring(c[3])
            end
        end
    end
    return out
end
local function samePresentation(a, b)
    local la, lb = presentationLog(a), presentationLog(b)
    if #la ~= #lb then return false, "length " .. #la .. " vs " .. #lb end
    for i = 1, #la do
        if la[i] ~= lb[i] then return false, "entry " .. i .. ": " .. la[i] .. " vs " .. lb[i] end
    end
    return true
end
local function updatesFor(p, key)
    local n = 0
    for _, c in ipairs(p.calls) do if c[1] == "UpdateObjective" and c[2] == key then n = n + 1 end end
    return n
end

local DLL_FIRST_WAVE_ATTACKS = 4 -- tank3, tank4, fighter5, fighter6
local SILOS = {"svsilo1", "svsilo2", "svsilo3", "svsilo4"}

-- ============================================================ 1. startup, ownership, presentation, weather wiring
do
    local host, guests = session(true, 4)
    local s = host.state
    check(s.start_done and s.ccamuf == "svmuf" and s.hangar == "svguntower2" and s.checkpoint1 == "svguntower1"
        and s.nsdfrecycle == "avrecycle" and s.nav1 == "apcamr20_camerapod", "the leader starts the mission body on the authored labels")
    for i = 1, 4 do check(s["ccasilo" .. i] == "svsilo" .. i, "silo " .. i .. " resolves by label") end
    check(s.spawn_point1 == "spawn_geyser1" and s.spawn_point2 == "spawn_geyser2" and s.center == "center"
        and s.split_geyser == "split_geyser" and s.key_geyser1 == "key_geyser1", "geysers resolve by label")
    check(s.escorts[1] == "artil_escort1" and s.escorts[3] == "artil_escort3" and s.reserves[2] == "cca_reserve2",
        "escorts and reserve resolve by label")
    for _, g in ipairs(guests) do
        check(not g.state.start_done and g.state.first_wave_time == 99999.0, "a guest never runs the mission body")
        check(g.state.hangar == "svguntower2", "a guest still resolves its labels (harmless: nothing acts on them)")
    end
    silentGuests(guests, "startup: ")
    eachPeer(function(p)
        check(count(p, "SetAIControl") == 1, "SetAIControl runs exactly once per peer")
        local c = callsOf(p, "SetAIControl")[1]
        check(c[2] == 5 and c[3] == true, "the CCA strategic AI is enabled for team 5")
        check(firstIndex(p, "SetAIControl") <= p.chunkCalls, "SetAIControl runs at chunk load, before Start")
        check(count(p, "DisableStartingRecycler") == 1 and firstIndex(p, "DisableStartingRecycler") <= p.chunkCalls,
            "the starting recycler is disabled once, at chunk load")
        check(count(p, "SetLives") == 1, "CRCoop configures native lives once")
        check(p.rally and p.rally[0] == "avrecycle" and p.rally[1] == nil, "respawn rally is the Texas recycler label")
        check(count(p, "Play", "misn1300.wav") == 1, "the opening briefing plays on every peer once")
        check(count(p, "AddObjective", "misn1300.otf") == 1, "the DLL's objective reaches every peer once")
        check((p.state.coopUnresolved or 0) == 0, "no marker was left unresolved")
        check(count(p, "Ally") >= 12 and count2(p, "UnAlly", 1, 5) >= 1 and count2(p, "UnAlly", 5, 4) >= 1,
            "co-op alliances configured against the CCA team")
        check(p.eu.updates > 0, "the weather director is updated every frame on every peer")
        check(count(p, "SetObjectiveName", "apcamr20_camerapod") == 1
            and count2(p, "SetObjectiveName", "apcamr20_camerapod", "Drop Zone") == 1, "the nav pod is named Drop Zone on every peer")
    end)
    check(count(host, "SetAIP") == 0, "the strategic AIP is not set at the very start")
    -- The opening resources and pilots are the leader's.
    check(count2(host, "SetPilot", 1, 10) == 1 and count2(host, "SetPilot", 5, 40) == 1, "pilot counts set once, leader only")
    check(count2(host, "SetScrap", 1, 40) == 1 and count2(host, "SetScrap", 5, 200) == 1, "scrap set once, leader only")
    check(world.scrap[1] == 40 and world.scrap[5] == 200, "the base and the CCA start with the DLL's scrap")
    -- The DLL's opening orders.
    for _, h in ipairs({"tank1", "tank2", "artil1", "artil2", "artil3", "artil4"}) do
        check(count(host, "Defend", h) == 1, h .. " starts on defend")
    end
    check(orders(host, "Follow", "tank1", "svmuf") == 1 and orders(host, "Follow", "tank2", "svmuf") == 1
        and orders(host, "Follow", "tank3", "center") == 1 and orders(host, "Follow", "tank4", "center") == 1,
        "the four base tanks follow the factory / the centre tower")
    check(orders(host, "Retreat", "turret1", "turret_path1") == 1 and orders(host, "Retreat", "turret5", "turret_path2") == 1
        and count(host, "Defend", "turret3") == 1 and count(host, "Defend", "turret4") == 1, "the turrets take their positions")
    check(orders(host, "Goto", "svslf", "slf_path") == 1, "the armory walks its path")
    check(builtAt(host, "svtank", "artil1") == 1, "the artillery escort tank is built beside artil1")
    local escortTank = s.escort_tank
    check(objects[escortTank].team == 5 and count(host, "Defend", escortTank) == 1, "the escort tank is CCA and defends")
    for i = 1, 3 do
        check(count(host, "Defend", "artil_escort" .. i) == 1, "map escort " .. i .. " stands on defend")
    end
    for i = 1, 2 do
        check(count(host, "Defend", "cca_reserve" .. i) == 1, "reserve " .. i .. " stands on defend")
    end
    -- The offline placeholder is removed; the map labels stay out of the E stream.
    check(count(host, "RemoveObject", "player0_hover") == 1, "the offline placeholder is removed in a network game")
    -- The objective list: the DLL line first, then the four co-op lines.
    eachPeer(function(p)
        local seq = {}
        for _, c in ipairs(p.calls) do
            if c[1] == "ClearObjectives" then seq[#seq + 1] = "C"
            elseif c[1] == "AddObjective" then seq[#seq + 1] = c[2] end
        end
        check(table.concat(seq, ",") == "C,misn1300.otf,C,misn13_recycler,misn13_factory,misn13_hangar,misn13_silos",
            "objective order on every peer: the DLL's first, then the progress list: " .. table.concat(seq, ","))
        local adds = callsOf(p, "AddObjective")
        check(adds[2][3] == "white" and adds[2][5] == "Defend your Recycler", "recycler objective is white")
        check(adds[3][3] == "white" and adds[3][5] == "Destroy the CCA Unit Factory", "factory objective is white")
        check(adds[4][3] == "white" and adds[4][5] == "Destroy the CCA hangar", "hangar objective is white")
        check(adds[5][3] == "white" and adds[5][5] == "Destroy the CCA silos (0/4)", "silo objective starts at 0/4")
        check(adds[2][4] == 8.0 and adds[5][4] == 8.0, "objective duration is the co-op 8 s")
        check(count(p, "UpdateObjective") == 0, "UpdateObjective fires on change only")
    end)
    -- The stream really crossed the wire.
    check(count(host, "Send", "E") > 0, "the leader sends the E stream")
    for _, g in ipairs(guests) do check(count(g, "Send", "A") > 0, "a guest acknowledges the E stream") end
    -- Weather wiring.
    check(host.eu.init.authority and host.eu.init.sites.mission == "misn13" and host.eu.init.send ~= nil
        and host.eu.init.startLevel == 1 and host.eu.init.seed == nil, "the leader runs the weather director on the misn13 sites")
    check(s.europaSeed == 4242, "the leader remembers the weather seed for saves")
    for _, g in ipairs(guests) do
        check(not g.eu.init.authority and g.eu.init.send ~= nil and g.eu.init.seed == nil,
            "a guest runs the director from the host's events")
        check(g.eu.announces == 0 and #g.eu.targets == 0 and #g.eu.forces == 0, "a guest announces and steers nothing")
    end
    check(host.eu.announces == 1, "the leader announces the weather state once")
    check(host.eu.targets[1] == 2 and #host.eu.targets == 1, "weather steps to level 2 at the start, once")
    for _, p in ipairs({host, guests[1], guests[2], guests[3]}) do
        check(p.eu.shutdowns == 0, "the director is not shut down at the start")
    end
end

-- ============================================================ 2. the DLL timers, leader only
do
    local host, guests = session(true, 2)
    local s = host.state
    local t0 = last(host, "SetPilot").t
    check(s.first_wave_time == t0 + 5.0 and s.next_wave_time == t0 + 300.0 and s.artil_move_time == t0 + 900.0,
        "the DLL's opening timers: first wave +5 s, restored waves +300 s, artillery march +900 s")
    runTo(s.first_wave_time)
    check(not s.first_wave and attacksOn(host, "avrecycle") == 0, "the first wave waits for its strict boundary")
    tick()
    local tFirst = now
    check(s.first_wave and attacksOn(host, "avrecycle", 1) == DLL_FIRST_WAVE_ATTACKS + 2 * 1,
        "the first wave: tank3, tank4, fighter5, fighter6 at priority 1 plus the extra human's pair")
    for _, u in ipairs({"tank3", "tank4", "fighter5", "fighter6"}) do
        check(orders(host, "Attack", u, "avrecycle", 1) == 1, u .. " attacks the recycler at priority 1")
    end
    runTo(s.second_wave_time)
    check(not s.second_wave and gotosTo(host, "fighter1", "choke_point1") == 0, "the second wave waits for its strict boundary")
    tick()
    check(s.second_wave and gotosTo(host, "fighter1", "choke_point1") == 1 and gotosTo(host, "fighter2", "choke_point1") == 1
        and gotosTo(host, "fighter3", "key_geyser1") == 1 and gotosTo(host, "fighter4", "key_geyser2") == 1,
        "the second wave: the fighters stage at the choke / geysers")
    check(s.set_aip_time == now + 60.0, "the AIP timer starts 60 s after the second wave")
    runTo(s.set_aip_time)
    check(count(host, "SetAIP") == 0, "the AIP waits for its strict boundary")
    tick()
    check(orders(host, "SetAIP", "misn13.aip", 5) == 1 and count(host, "SetAIP") == 1, "SetAIP(misn13.aip, 5) fires once")
    local firstAip = last(host, "SetAIP").t
    check(firstAip - t0 > 65 and firstAip - t0 < 73, "the AIP lands about 70 s after the briefing, the DLL's cadence")
    check(firstAip - tFirst > 60 and firstAip - tFirst < 73, "...and about 65 s after the first wave")
    check(s.set_aip_time == now + 240.0 and not s.set_aip, "and repeats every 240 s")
    runTo(s.set_aip_time)
    check(count(host, "SetAIP") == 1, "the repeat waits for its strict boundary")
    tick()
    check(orders(host, "SetAIP", "misn13.aip", 5) == 2 and count(host, "SetAIP") == 2, "SetAIP repeats")
    check(last(host, "SetAIP").t - firstAip > 240 and last(host, "SetAIP").t - firstAip < 241, "240 s between the two")
    for _, g in ipairs(guests) do
        check(count(g, "SetAIP") == 0 and count(g, "SetAIControl") == 1, "a guest never touches the AIP")
    end
    -- Scavenger swap: the CCA is out of scrap, so its scavengers are rebuilt and walk to the centre geyser.
    world.scrap[5] = 10
    runTo(s.scrap_check + 0.25)
    check(s.scav_swap, "low CCA scrap swaps the scavengers")
    for i = 1, 4 do
        check(builtAt(host, "svscav", "svscav" .. i) == 1 and count(host, "RemoveObject", "svscav" .. i) == 1,
            "scavenger " .. i .. " is rebuilt in place and the old one removed")
    end
    check(orders(host, "Goto", s.svscav5, "center_geyser") == 1 and orders(host, "Goto", s.svscav8, "center_geyser") == 1,
        "the new scavengers go to the centre geyser")
    run(2)
    for _, g in ipairs(guests) do
        check(count(g, "BuildObject") == 0 and count(g, "RemoveObject", "svscav1") == 1,
            "a guest builds nothing but still sees the removal")
    end
    local same, why = samePresentation(host, guests[1])
    check(same, "leader and guest presentation streams agree: " .. tostring(why))
end

-- ============================================================ 3. CCA scaling at 1-4 players, every wave
-- Restored waves (spawn geyser, choke point, base): wave 2 = 2 svtank + 1 svfigh at spawn_geyser1, wave 3 =
-- 2 + 2 at spawn_geyser2, wave 4 = 3 + 2 at spawn_geyser2; every extra human adds one svtank and one svfigh.
local function waveSpawn(host, s, spawnLabel, choke, wantTanks, wantFighters, tag)
    local mark = #host.calls
    runTo(s.next_wave_time)
    check(#buildsSince(host, mark, spawnLabel) == 0, tag .. "the wave waits for its strict boundary")
    local before = s.next_wave_time
    tick()
    local list = buildsSince(host, mark, spawnLabel)
    local tanks, fighters = tally(list)
    check(tanks == wantTanks and fighters == wantFighters and #list == tanks + fighters,
        tag .. "the wave is " .. wantTanks .. " svtank + " .. wantFighters .. " svfigh (got " .. tanks .. " + " .. fighters .. ")")
    check(s.next_wave_time == now + 300.0 and now - before == 0.25, tag .. "the next wave is 300 s after this one")
    local units = {}
    for _, b in ipairs(list) do
        units[#units + 1] = b.h
        check(b.team == 5 and objects[b.h].team == 5, tag .. "wave units are CCA team 5")
        check(orders(host, "Goto", b.h, choke, 1) == 1, tag .. "each wave unit drives to " .. choke .. " at priority 1")
    end
    return units
end

local function waveMarch(host, s, number, units, choke, tag)
    local lead = units[1]
    local unitsAlive = 0
    for _, u in ipairs(units) do if objects[u].alive then unitsAlive = unitsAlive + 1 end end
    nearTo(lead, choke, 151, 0)
    run(2.5)
    check(gotosTo(host, lead, "turret_path3") == 0 and not s["wave" .. number .. "_move"],
        tag .. "a lead 151 m from the choke does not advance")
    nearTo(lead, choke, 149, 0)
    run(2.5)
    check(s["wave" .. number .. "_move"], tag .. "a lead within 150 m of the choke advances the wave")
    for _, u in ipairs(units) do
        if objects[u].alive then
            check(orders(host, "Goto", u, "turret_path3", 1) == 1, tag .. "every living unit takes turret_path3 at priority 1")
        end
    end
    local before = sumOrders(host, "Attack", units, "avrecycle", 1)
    nearTo(lead, "svguntower1", 226, 0)
    run(2.5)
    check(sumOrders(host, "Attack", units, "avrecycle", 1) == before and not s["wave" .. number .. "_done"],
        tag .. "a lead 226 m from the east tower does not attack yet")
    nearTo(lead, "svguntower1", 224, 0)
    run(2.5)
    check(sumOrders(host, "Attack", units, "avrecycle", 1) == before + unitsAlive and s["wave" .. number .. "_done"],
        tag .. "a lead within 225 m of the east tower sends the whole wave at the recycler")
end

for humans = 1, 4 do
    local host, guests = session(true, humans)
    local s = host.state
    local more = math.min(3, humans - 1)
    local tag = humans .. " players: "
    -- The opening rush.
    runTo(s.first_wave_time + 8)
    check(builtAt(host, "svtank", "choke_point1") == more and builtAt(host, "svfigh", "choke_point1") == more,
        tag .. more .. " extra svtank + svfigh join the rush at choke_point1")
    local rush = buildsSince(host, 0, "choke_point1")
    check(#rush == 2 * more, tag .. "no other rush unit")
    for _, b in ipairs(rush) do
        check(b.team == 5, tag .. "the rush is CCA team 5")
        check(orders(host, "Attack", b.h, "avrecycle", 1) == 1, tag .. "each rush unit attacks the recycler at priority 1")
    end
    check(attacksOn(host, "avrecycle", 1) == DLL_FIRST_WAVE_ATTACKS + 2 * more, tag .. "the DLL's four attacks plus the rush")
    check(s.rush_extras, tag .. "the rush is a one-shot")
    run(20)
    check(attacksOn(host, "avrecycle", 1) == DLL_FIRST_WAVE_ATTACKS + 2 * more, tag .. "...and is not repeated")
    -- Wave 2: a lead on the way.
    local w2 = waveSpawn(host, s, "spawn_geyser1", "choke_point3", 2 + more, 1 + more, tag .. "wave 2: ")
    waveMarch(host, s, 2, w2, "choke_point3", tag .. "wave 2: ")
    -- Wave 3: the lead never arrives, so the choke timeout carries it.
    local w3 = waveSpawn(host, s, "spawn_geyser2", "choke_point2", 2 + more, 2 + more, tag .. "wave 3: ")
    local t3 = s.wave_time[2]
    runTo(t3 + 118)
    check(gotosTo(host, w3[1], "turret_path3") == 0 and not s.wave3_move, tag .. "wave 3 holds at the choke inside 120 s")
    runTo(t3 + 123)
    check(s.wave3_move and orders(host, "Goto", w3[1], "turret_path3", 1) == 1, tag .. "wave 3 leaves the choke after 120 s")
    if humans == 4 then
        -- 9 + 10 live units: the cap of 16 postpones wave 4 by 30 s.
        local mark = #host.calls
        runTo(s.next_wave_time)
        tick()
        check(not s.wave4 and #buildsSince(host, mark, "spawn_geyser2") == 0, tag .. "the live cap postpones wave 4")
        check(s.next_wave_time == now + 30.0, tag .. "...by 30 s")
        local retry = s.next_wave_time
        runTo(retry)
        tick()
        check(not s.wave4 and s.next_wave_time == now + 30.0, tag .. "and keeps postponing while the field is full")
        for i = 1, 4 do kill(w3[i]) end
        local w4 = waveSpawn(host, s, "spawn_geyser2", "choke_point3", 3 + more, 2 + more, tag .. "wave 4: ")
        check(s.wave4, tag .. "wave 4 spawns once units fall under the cap")
    else
        local w4 = waveSpawn(host, s, "spawn_geyser2", "choke_point3", 3 + more, 2 + more, tag .. "wave 4: ")
        check(s.wave4, tag .. "wave 4 spawns on schedule")
    end
    local total = count(host, "BuildObject")
    run(700)
    check(count(host, "BuildObject") == total and s.next_wave_time == 99999.0, tag .. "there is no fifth wave")
    check(s.artil_move, tag .. "the artillery march has begun by now")
    -- Everything the leader built is CCA.
    for _, c in ipairs(callsOf(host, "BuildObject")) do
        check(c[4] == 5, tag .. c[3] .. " built by the mission is CCA team 5")
    end
    silentGuests(guests, tag)
    for _, g in ipairs(guests) do check(count(g, "Send", "E") == 0, tag .. "a guest never sends the E stream") end
    local same, why = samePresentation(host, guests[1] or host)
    check(same, tag .. "leader and guest presentation streams agree: " .. tostring(why))
    eachPeer(function(p) check((p.state.coopUnresolved or 0) == 0, tag .. "no unresolved marker") end)
end

-- Timeouts: a wave 2 whose lead never reaches the east tower still attacks, 240 s after leaving the choke.
do
    local host = session(true, 2)
    local s = host.state
    local w2 = waveSpawn(host, s, "spawn_geyser1", "choke_point3", 3, 2, "timeouts: ")
    local t2 = s.wave_time[1]
    runTo(t2 + 123)
    check(s.wave2_move, "timeouts: the choke timeout moved wave 2")
    local moved = s.wave_time[1]
    runTo(moved + 238)
    check(sumOrders(host, "Attack", w2, "avrecycle", 1) == 0 and not s.wave2_done, "timeouts: no attack inside 240 s")
    runTo(moved + 243)
    check(sumOrders(host, "Attack", w2, "avrecycle", 1) == #w2 and s.wave2_done,
        "timeouts: the whole wave attacks the recycler after 240 s")
    -- A wave with a dead lead picks the next living unit; a wiped wave is done. (Wave 3 landed during the
    -- 240 s wait above, so wave 4 is the next one on the schedule.)
    check(s.wave3, "timeouts: wave 3 landed on schedule meanwhile")
    local w4 = waveSpawn(host, s, "spawn_geyser2", "choke_point3", 4, 3, "timeouts: ")
    kill(w4[1])
    nearTo(w4[2], "choke_point3", 100, 0)
    run(2.5)
    check(s.wave4_move and orders(host, "Goto", w4[1], "turret_path3", 1) == 0 and orders(host, "Goto", w4[2], "turret_path3", 1) == 1,
        "timeouts: the next living unit leads when the first falls")
    for _, u in ipairs(w4) do kill(u) end
    run(2.5)
    check(s.wave4_done, "timeouts: a wiped wave is done")
end

-- No waves once the Unit Factory is dead, and none from a guest.
do
    local host, guests = session(true, 3)
    local s = host.state
    kill("svmuf")
    runTo(s.next_wave_time + 5)
    check(not s.wave2 and builtAt(host, "svtank", "spawn_geyser1") == 0 and builtAt(host, "svfigh", "spawn_geyser1") == 0,
        "no waves once the Unit Factory is dead")
    check(s.next_wave_time < now, "...the schedule simply lapses")
    silentGuests(guests, "factory dead: ")
end

-- ============================================================ 4. the DLL's capture slots and their team filters
do
    local host, guests = session(true, 4)
    local s = host.state
    local function reg(odf, team)
        local h = spawn(odf, team)
        host.env.AddObject(h)
        return h
    end
    -- svapc13 / svhr13 / svtk13 are the CCA's.
    local a1 = reg("svapc13", 1)
    local a2 = reg("svapc13", 2)
    local a3 = reg("svapc13", 3)
    local a4 = reg("svapc13", 4)
    local a0 = reg("svapc13", 0)
    local a6 = reg("svapc13", 6)
    check(s.sv1 == nil and s.sv2 == nil, "svapc13 on a human team, an unassigned team or team 6 never takes a slot")
    local c1 = reg("svapc13", 5)
    check(s.sv1 == c1, "a CCA svapc13 takes the first slot")
    local c2 = reg("svapc13", 5)
    check(s.sv2 == c2, "the second CCA svapc13 takes the second slot")
    local c3 = reg("svapc13", 5)
    check(s.sv1 == c1 and s.sv2 == c2 and s.sv3 == nil, "a third svapc13 changes nothing: first come")
    local h1 = reg("svhr13", 2)
    check(s.sv3 == nil, "a guest's svhr13 never takes a slot")
    local h2 = reg("svhr13", 5)
    local h3 = reg("svhr13", 5)
    local h4 = reg("svhr13", 5)
    check(s.sv3 == h2 and s.sv4 == h3, "CCA svhr13 fill sv3 then sv4")
    local t1 = reg("svtk13", 3)
    local t5 = reg("svtk13", 5)
    local t6 = reg("svtk13", 5)
    local t7 = reg("svtk13", 5)
    local t8 = reg("svtk13", 5)
    local t9 = reg("svtk13", 5)
    check(s.tank5 == t5 and s.tank6 == t6 and s.tank7 == t7 and s.tank8 == t8, "CCA svtk13 fill tank5..tank8 in order")
    check(s.tank5 ~= t1 and s.tank8 ~= t9, "a guest's svtk13 and the fifth take no slot")
    -- abtowe / abcomm / avmuf / avcnst / avscav belong to a human team, guests included.
    local towerEnemy = reg("abtowe", 5)
    local towerOther = reg("abtowe", 6)
    local towerZero = reg("abtowe", 0)
    check(s.guntower1 == nil, "an abtowe on the CCA, team 6 or team 0 is not the gun tower")
    local tower1 = reg("abtowe", 1)
    check(s.guntower1 == tower1, "the host's abtowe is the gun tower")
    local tower2 = reg("abtowe", 2)
    check(s.guntower1 == tower2, "a guest's abtowe counts too (the DLL keeps the latest tower)")
    local commEnemy = reg("abcomm", 5)
    check(s.controltower == nil, "a CCA abcomm is not the control tower")
    local comm3 = reg("abcomm", 3)
    local comm4 = reg("abcomm", 4)
    check(s.controltower == comm3, "a guest's abcomm is the control tower, first come")
    local mufEnemy = reg("avmuf", 5)
    local mufBlank = reg("avmuf", 0)
    check(s.nsdfmuf == nil, "a CCA avmuf is not the player factory")
    local muf4 = reg("avmuf", 4)
    local muf1 = reg("avmuf", 1)
    check(s.nsdfmuf == muf4, "a guest's avmuf is the player factory, first come")
    local rigEnemy = reg("avcnst", 5)
    local rig2 = reg("avcnst", 2)
    check(s.nsdfrig == rig2, "a guest's avcnst is the construction rig; the CCA's is not")
    local sEnemy = reg("avscav", 5)
    local sa = reg("avscav", 2)
    local sb = reg("avscav", 1)
    local sc = reg("avscav", 3)
    local sd = reg("avscav", 4)
    check(s.avscav1 == sa and s.avscav2 == sb and s.avscav3 == sc, "human-team scavengers fill avscav1..3 in order")
    check(s.avscav3 ~= sd and s.avscav1 ~= sEnemy, "a CCA scavenger and the fourth take no slot")
    -- nil / invalid / dead handles are safe.
    check(pcall(host.env.AddObject, nil), "AddObject(nil) is safe")
    check(pcall(host.env.AddObject, "ghost"), "AddObject of an unknown handle is safe")
    local dead = spawn("svapc13", 5)
    kill(dead)
    check(pcall(host.env.AddObject, dead), "AddObject of a dead handle is safe")
    -- A restricted ODF on the wrong team falls through nothing else: it must not seed another slot.
    check(s.sv1 == c1 and s.sv2 == c2 and s.sv3 == h2 and s.sv4 == h3, "the CCA slots held through every rejected handle")
    -- Order independence: the human craft first, then the CCA's, still ends on the CCA's.
    local host2 = session(true, 2)
    local s2 = host2.state
    host2.env.AddObject(spawn("svapc13", 1))
    local real = spawn("svapc13", 5)
    host2.env.AddObject(real)
    check(s2.sv1 == real, "a rejected first arrival never shadows the CCA's own bomber")
end

-- ============================================================ 5. the factory-safety census
for humans = 1, 4 do
    local host, guests = session(true, humans)
    local s = host.state
    local tag = humans .. " players: "
    local function distribute(total)
        local t, rest = {}, total
        for team = humans, 2, -1 do
            if rest > 0 then t[team] = 1; rest = rest - 1 end
        end
        if rest > 0 then t[1] = rest end
        return t
    end
    world.nearCount = {}
    hurt("svmuf", 0.90)
    run(1)
    check(not s.muf_attacked, tag .. "90 percent health is not an attack (strict)")
    hurt("svmuf", 0.89)
    run(1)
    check(s.muf_attacked and last(host, "AddScrap") and s.safe_time_check == last(host, "AddScrap").t + 120.0, tag .. "below 90 percent the factory is under attack")
    for _, t in ipairs({"turret1", "turret2", "turret5", "turret6"}) do
        check(count2(host, "Goto", t, "svmuf") == 1, tag .. t .. " answers the alarm")
    end
    check(count2(host, "AddScrap", 5, 40) == 1 and world.scrap[5] == 240, tag .. "the CCA gets its +40 scrap once")
    check(orders(host, "SetAIP", "misn13c.aip", 5) == 1, tag .. "the defensive AIP is set")
    check(count2(host, "SetAIP", "misn13.aip", 5) == 0, tag .. "the normal AIP is held while the factory is attacked")
    silentGuests(guests, tag .. "alarm: ")
    -- Not safe: one more unit than the threshold allows.
    world.nearCount = distribute(humans + 1)
    runTo(s.safe_time_check)
    check(count(host, "CountUnitsNearObject") == 0, tag .. "the census waits for its strict boundary")
    tick()
    local census = callsOf(host, "CountUnitsNearObject")
    check(#census == humans, tag .. "one census per human team (" .. #census .. ")")
    local teams = {}
    for _, c in ipairs(census) do
        check(c[2] == "svmuf" and c[3] == 400 and c[5] == nil and c.n == 4, tag .. "the census is CountUnitsNearObject(muf, 400, team, nil)")
        teams[c[4]] = true
    end
    for team = 1, humans do check(teams[team], tag .. "team " .. team .. " is counted") end
    check(not teams[5] and not teams[0], tag .. "the CCA is not counted")
    check(s.check == 2.0 and not s.muf_safe and s.muf_attacked, tag .. "total " .. (humans + 1) .. " minus " .. (humans - 1) .. " is not safe")
    run(40)
    check(not s.muf_safe, tag .. "it stays unsafe while the units stay")
    check(count2(host, "SetAIP", "misn13.aip", 5) == 0, tag .. "the normal AIP stays held")
    -- Safe: exactly the threshold.
    world.nearCount = distribute(humans)
    run(1)
    check(s.muf_safe and not s.muf_attacked and s.check == 1.0, tag .. "total " .. humans .. " is safe")
    run(1)
    check(orders(host, "SetAIP", "misn13.aip", 5) == 1, tag .. "the normal AIP resumes the moment the factory is safe")
    -- Safe is final: hurting it again does not re-trigger the alarm.
    hurt("svmuf", 0.5)
    run(2)
    check(not s.muf_attacked and orders(host, "SetAIP", "misn13c.aip", 5) == 1, tag .. "a safe factory raises no second alarm")
    for _, g in ipairs(guests) do
        check(count(g, "CountUnitsNearObject") == 0 and count(g, "AddScrap") == 0, tag .. "a guest never takes the census")
    end
end
do
    -- Guests' units count: three units on a guest team with two humans is not safe (the DLL looked at team 1 only).
    local host, guests = session(true, 2)
    local s = host.state
    world.nearCount = {[2] = 3}
    hurt("svmuf", 0.5)
    run(1)
    runTo(s.safe_time_check + 0.25)
    check(s.check == 2.0 and not s.muf_safe, "units on a guest team keep the factory unsafe")
    world.nearCount = {[2] = 2}
    run(1)
    check(s.muf_safe, "two units on a guest team with two humans are safe")
    -- The geometric census sees real units: three guest units within 400 m of the factory.
    local host2 = session(true, 2)
    local s2 = host2.state
    for i = 1, 3 do
        local u = spawn("avtank", 2)
        nearTo(u, "svmuf", 100 * i, 0)
    end
    local far = spawn("avtank", 2)
    nearTo(far, "svmuf", 401, 0)
    local cca = spawn("svtank", 5)
    nearTo(cca, "svmuf", 10, 0)
    hurt("svmuf", 0.5)
    run(1)
    runTo(s2.safe_time_check + 0.25)
    check(s2.check == 3.0 - 1.0 and not s2.muf_safe, "geometry: three guest units in range (not the one at 401 m, not the CCA's)")
end

-- ============================================================ 6. the win needs the factory, the hangar and four silos
do
    -- Every subset of the six targets: only the full set wins.
    local targets = {"svmuf", "svguntower2", "svsilo1", "svsilo2", "svsilo3", "svsilo4"}
    for mask = 0, 63 do
        local host, guests = session(true, 2)
        local s = host.state
        local dead, silos = 0, 0
        for i = 1, 6 do
            if math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then
                kill(targets[i])
                dead = dead + 1
                if i >= 3 then silos = silos + 1 end
            end
        end
        run(2)
        check(s.game_over == (mask == 63), "mask " .. mask .. ": only the whole base wins")
        check(count(host, "Play", "misn1303.wav") == (mask == 63 and 1 or 0), "mask " .. mask .. ": victory line only on the win")
        check(count(host, "FailMission") == 0, "mask " .. mask .. ": nothing fails")
        check(updatesFor(host, "misn13_factory") == (math.floor(mask / 1) % 2), "mask " .. mask .. ": factory objective updates on change only")
        check(updatesFor(host, "misn13_hangar") == (math.floor(mask / 2) % 2), "mask " .. mask .. ": hangar objective updates on change only")
        check(updatesFor(host, "misn13_silos") == (silos > 0 and 1 or 0), "mask " .. mask .. ": silo objective updates on change only")
        run(1)
        check(updatesFor(guests[1], "misn13_silos") == (silos > 0 and 1 or 0), "mask " .. mask .. ": the guest sees the same silo updates")
    end
end
do
    -- Progress is visible step by step; the factory last; any human may land any blow.
    local host, guests = session(true, 3)
    local s = host.state
    for i, silo in ipairs(SILOS) do
        kill(silo)
        run(1)
        check(not s.game_over, i .. " silos down is not the win")
    end
    run(1)
    eachPeer(function(p)
        local texts = {}
        for _, c in ipairs(callsOf(p, "UpdateObjective")) do
            if c[2] == "misn13_silos" then texts[#texts + 1] = c[3] .. "|" .. c[5] end
        end
        check(table.concat(texts, ";") == "white|Destroy the CCA silos (1/4);white|Destroy the CCA silos (2/4);white|Destroy the CCA silos (3/4);green|Destroy the CCA silos (4/4)",
            "silo progress reaches every peer in order: " .. table.concat(texts, ";"))
    end)
    kill("svmuf")
    run(1)
    check(not s.game_over, "factory plus four silos without the hangar is not the win")
    check(host.eu.forces[1] and host.eu.forces[1][1] == 5 and host.eu.forces[1][2] == 60.0 and host.eu.forces[1][3] == 10.0,
        "the factory falling forces level 5 for 60 s with a 10 s ramp")
    check(#host.eu.forces == 1 and #host.eu.quakes == 1 and host.eu.quakes[1][1] == 0.7 and host.eu.quakes[1][2] == 5.0,
        "...and one ice quake (0.7, 5 s)")
    check(#host.eu.surges == 1 and host.eu.surges[1][1] == 6.0 and host.eu.surges[1][2] == 0.8, "...and one radiation surge (6 s, 0.8)")
    check(count(host, "Play", "misn1303.wav") == 0, "no victory line yet")
    eachPeer(function(p) check(updatesFor(p, "misn13_factory") == 1, "the factory objective turns green on every peer once") end)
    kill("svguntower2")
    local tVictory
    run(1)
    check(s.game_over, "the hangar completes the base")
    tVictory = last(host, "Play").t
    run(30)
    local times = {}
    eachPeer(function(p)
        check(count(p, "Play", "misn1303.wav") == 1, "the victory line plays once on every peer")
        check(count(p, "SucceedMission") == 1 and last(p, "SucceedMission")[3] == "misn13w1.des", "the win reaches every peer once")
        check(count(p, "FailMission") == 0, "and never fails")
        times[#times + 1] = last(p, "SucceedMission")[2]
        check(updatesFor(p, "misn13_hangar") == 1, "the hangar objective turns green once")
    end)
    for _, t in ipairs(times) do
        check(math.abs(t - times[1]) < 0.01, "the result lands at one time on every peer")
        check(t >= tVictory + 14.5 and t <= tVictory + 16.5, "the result honours the DLL's 15 s delay")
    end
    check(host.eu.releases == 1 and host.eu.targets[#host.eu.targets] == 1, "the weather is calmed once on the win")
    for _, g in ipairs(guests) do
        check(g.eu.releases == 0 and #g.eu.targets == 0, "a guest does not steer the weather")
        local quakes, surges = 0, 0
        for _, ev in ipairs(g.eu.events) do
            if ev[1] == "EuropaQuake" then quakes = quakes + 1 end
            if ev[1] == "EuropaSurge" then surges = surges + 1 end
        end
        check(quakes == 1 and surges == 1, "the quake and the surge reach each guest exactly once")
    end
    check(host.eu.updates > 0 and guests[1].eu.updates > 0, "the sky keeps easing while the result counts down")
    local same, why = samePresentation(host, guests[2])
    check(same, "the whole win presentation matches on a guest: " .. tostring(why))
end
do
    -- Hostile map state: no hangar at all does not block the win.
    local host, guests = session(true, 2, function() world.missing.svguntower2 = true end)
    local s = host.state
    check(s.hangar == nil, "the missing hangar resolves to nil")
    eachPeer(function(p)
        local adds = callsOf(p, "AddObjective")
        check(adds[4][2] == "misn13_hangar" and adds[4][3] == "green", "a missing hangar starts its objective green")
    end)
    for _, silo in ipairs(SILOS) do kill(silo) end
    kill("svmuf")
    run(2)
    check(s.game_over and count(host, "Play", "misn1303.wav") == 1, "a missing hangar does not block the win")
end
do
    -- A recycler loss beats a simultaneous win.
    local host, guests = session(true, 3)
    local s = host.state
    for _, t in ipairs({"svmuf", "svguntower2", "svsilo1", "svsilo2", "svsilo3", "svsilo4", "avrecycle"}) do kill(t) end
    run(1)
    local tLoss = last(host, "Play").t
    run(30)
    check(s.game_over, "the same-frame loss ends the mission")
    eachPeer(function(p)
        check(count(p, "Play", "misn1304.wav") == 1 and count(p, "Play", "misn1303.wav") == 0, "the loss line plays, not the victory line")
        check(count(p, "FailMission") == 1 and last(p, "FailMission")[3] == "misn13f1.des", "the loss fails every peer once")
        check(count(p, "SucceedMission") == 0, "and never wins")
        check(last(p, "FailMission")[2] >= tLoss + 14.5 and last(p, "FailMission")[2] <= tLoss + 16.5, "after the DLL's 15 s")
        check(updatesFor(p, "misn13_recycler") == 1, "the recycler objective turns red once")
    end)
    local red = false
    for _, c in ipairs(callsOf(guests[1], "UpdateObjective")) do
        if c[2] == "misn13_recycler" and c[3] == "red" and c[5] == "Defend your Recycler" then red = true end
    end
    check(red, "...and it is red")
    check(host.eu.releases == 0, "a loss does not calm the weather")
end
do
    -- Recycler loss on its own.
    local host, guests = session(true, 2)
    kill("avrecycle")
    run(30)
    eachPeer(function(p)
        check(count(p, "FailMission") == 1 and count(p, "Play", "misn1304.wav") == 1, "the recycler loss fails once with its line")
    end)
end
do
    -- Out of lives: the host's own death, then a guest's.
    local host, guests = session(true, 3)
    host.coop.ReportOutOfLives()
    local t = now
    run(30)
    eachPeer(function(p)
        check(count(p, "FailMission") == 1 and last(p, "FailMission")[3] == nil, "the host out of lives fails every peer once")
        check(last(p, "FailMission")[2] >= t + 2.9 and last(p, "FailMission")[2] <= t + 7, "the failure lands a few seconds later")
        check(count(p, "SucceedMission") == 0, "and never wins")
    end)
    check(count(host, "DisplayMessage") >= 1, "the host reports the departure of the last life")
    local host2, guests2 = session(true, 3)
    guests2[2].coop.ReportOutOfLives()
    local t2 = now
    run(30)
    eachPeer(function(p)
        check(count(p, "FailMission") == 1 and last(p, "FailMission")[3] == nil, "a guest out of lives fails every peer once")
    end)
    check(count(guests2[2], "Send", "L") >= 1 and count(guests2[1], "Send", "L") == 0, "the guest told the host (L), the others did not")
    check(count(host2, "DisplayMessage") >= 1 and callsOf(host2, "DisplayMessage")[1][2]:find("out of lives"), "the host names the player who ran out")
end
do
    -- The host leaves: a guest fails one second later, once.
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
    for _, g in ipairs(guests) do
        check(count(g, "FailMission") == 1, "and only once")
        check(count(g, "BuildObject") == 0, "and a guest never takes over the body")
    end
end

-- ============================================================ 7. misn1302: the artillery shells any human
do
    local cases = {
        {who = "host", shooter = "artil1", fires = true},
        {who = "guest1", shooter = "artil2", fires = true},
        {who = "guest2", shooter = "artil3", fires = true},
        {who = "guest2", shooter = "artil4", fires = true},
        {who = "host", shooter = "tank3", fires = false},
        {who = "guest1", shooter = "fighter1", fires = false},
        {who = "guest1", shooter = 0, fires = false},
        {who = "host", shooter = nil, fires = false},
        {who = "guest2", shooter = "player10", fires = false},
    }
    for i, case in ipairs(cases) do
        local host, guests = session(true, 3)
        local s = host.state
        s.artil_move2 = true
        local craft = case.who == "host" and host.player or (case.who == "guest1" and guests[1].player or guests[2].player)
        objects[craft].shotBy = case.shooter
        run(2)
        local label = "case " .. i .. " (" .. case.who .. " by " .. tostring(case.shooter) .. "): "
        check(s.artil_message == case.fires, label .. "the warning follows the shooter")
        run(2)
        check(playedOnAll("misn1302.wav") == (case.fires and peerCount() or 0), label .. "misn1302 plays once on every peer, or on none")
    end
    -- Once only, and only after the artillery has split off.
    local host, guests = session(true, 3)
    local s = host.state
    objects[guests[1].player].shotBy = "artil1"
    run(2)
    check(not s.artil_message, "no warning before the artillery march splits")
    s.artil_move2 = true
    run(2)
    check(s.artil_message, "the warning fires once the artillery has split")
    objects[host.player].shotBy = "artil2"
    objects[guests[2].player].shotBy = "artil3"
    run(5)
    eachPeer(function(p) check(count(p, "Play", "misn1302.wav") == 1, "further shots never repeat the warning") end)
    -- The DLL's own targets still count: the recycler shelled by the artillery.
    local host2 = session(true, 2)
    host2.state.artil_move2 = true
    objects.avrecycle.shotBy = "artil4"
    run(2)
    check(host2.state.artil_message and count(host2, "Play", "misn1302.wav") == 1, "a shelled recycler still raises the warning")
end

-- ============================================================ 8. the escort and the reserve
do
    local host, guests = session(true, 3)
    local s = host.state
    for i = 1, 3 do
        check(count(host, "Defend", "artil_escort" .. i) == 1 and count(host, "Retreat", "artil_escort" .. i) == 0,
            "escort " .. i .. " defends and has not marched")
    end
    runTo(s.artil_move_time)
    check(not s.artil_move and count(host, "Retreat", "artil_escort1") == 0, "the march waits for its strict boundary")
    tick()
    check(s.artil_move, "the artillery march starts at 900 s")
    for i = 1, 3 do
        check(orders(host, "Retreat", "artil_escort" .. i, "artil_path1") == 1, "escort " .. i .. " takes artil_path1 once")
    end
    for i = 1, 4 do check(orders(host, "Retreat", "artil" .. i, "artil_path1") == 1, "artillery " .. i .. " marches") end
    check(host.eu.targets[#host.eu.targets] == 3, "the march lifts the weather to level 3")
    run(6)
    for i = 1, 3 do check(count(host, "Retreat", "artil_escort" .. i) == 1, "escort " .. i .. " is not retasked on the march") end
    check(count(host, "Follow", "artil_escort1") == 0, "no follow before the artillery splits")
    nearTo("artil4", "split_geyser", 10, 0)
    run(11)
    check(s.artil_move2, "the artillery splits at the geyser")
    for i = 1, 3 do
        check(orders(host, "Follow", "artil_escort" .. i, "artil" .. i) == 1, "escort " .. i .. " follows artillery " .. i)
    end
    run(12)
    for i = 1, 3 do check(count(host, "Follow", "artil_escort" .. i) == 1, "escort " .. i .. " is not re-ordered while its leader lives") end
    kill("artil2")
    run(6)
    check(orders(host, "Follow", "artil_escort2", "artil1") == 1, "escort 2 follows the first living piece when its own dies")
    kill("artil1")
    run(6)
    check(orders(host, "Follow", "artil_escort1", "artil3") == 1 and orders(host, "Follow", "artil_escort2", "artil3") == 1,
        "with artillery 1 and 2 down, escorts 1 and 2 follow artillery 3")
    check(count(host, "Follow", "artil_escort3") == 1, "escort 3 keeps its own piece")
    kill("artil_escort3")
    kill("artil3")
    run(6)
    check(count(host, "Follow", "artil_escort3") == 1, "a dead escort is never ordered")
    check(orders(host, "Follow", "artil_escort1", "artil4") == 1 and orders(host, "Follow", "artil_escort2", "artil4") == 1,
        "with only artillery 4 left, the living escorts follow it")
    local followsBefore = count(host, "Follow")
    kill("artil4")
    run(6)
    check(count(host, "Follow") == followsBefore, "no living artillery means no new follow target")
    for _, g in ipairs(guests) do
        check(count(g, "Retreat") == 0 and count(g, "Follow") == 0 and count(g, "Defend") == 0, "guests order no escort")
    end
end
do
    -- A dead own-piece before the split: follow the first living one.
    local host = session(true, 2)
    local s = host.state
    kill("artil3")
    s.artil_move2 = true
    run(1)
    check(orders(host, "Follow", "artil_escort3", "artil1") == 1 and orders(host, "Follow", "artil_escort1", "artil1") == 1
        and orders(host, "Follow", "artil_escort2", "artil2") == 1, "an escort whose piece is dead follows artillery 1")
end
do
    -- The reserve: factory alarm.
    local host, guests = session(true, 2)
    local s = host.state
    check(count(host, "Goto", "cca_reserve1") == 0, "the reserve guards until alarmed")
    run(5)
    hurt("svmuf", 0.5)
    run(1)
    local tAlarm = now
    for i = 1, 2 do
        check(orders(host, "Goto", "cca_reserve" .. i, "svmuf", 1) == 1, "reserve " .. i .. " races to the factory at priority 1")
    end
    run(5)
    check(count(host, "Goto", "cca_reserve1") == 1, "and is not ordered again on the way")
    nearTo("cca_reserve1", "svmuf", 59, 0)
    nearTo("cca_reserve2", "svmuf", 61, 0)
    run(1)
    check(count(host, "Defend", "cca_reserve1") == 2, "reserve 1 holds within 60 m")
    check(count(host, "Defend", "cca_reserve2") == 1, "reserve 2 at 61 m keeps driving")
    local held = last(host, "Defend").t
    runTo(held + 89)
    check(count(host, "Goto", "cca_reserve1") == 1, "the held reserve stays put before 90 s")
    runTo(held + 91)
    check(orders(host, "Goto", "cca_reserve1", "svmuf", 1) == 2, "after 90 s the reserve rearms and is called again")
    for _, g in ipairs(guests) do check(count(g, "Goto") == 0, "guests order no reserve") end
end
do
    -- The reserve: a silo is attacked.
    local host = session(true, 2)
    local s = host.state
    hurt("svsilo2", 0.9)
    run(1)
    check(s.silos_attacked, "a damaged silo raises the silo alarm")
    for i = 1, 2 do
        check(orders(host, "Goto", "cca_reserve" .. i, "silo_spot", 1) == 1, "reserve " .. i .. " goes to silo_spot at priority 1")
    end
    nearTo("cca_reserve2", "silo_spot", 59, 0)
    run(1)
    check(count(host, "Defend", "cca_reserve2") == 2, "the reserve holds at the silo spot within 60 m")
    check(count(host, "Defend", "cca_reserve1") == 1, "the other reserve is still on its way")
end
do
    -- Both alarms: the factory comes first.
    local host = session(true, 2)
    hurt("svmuf", 0.5)
    hurt("svsilo1", 0.9)
    run(1)
    check(orders(host, "Goto", "cca_reserve1", "svmuf", 1) == 1 and gotosTo(host, "cca_reserve1", "silo_spot") == 0,
        "the factory alarm outranks the silo alarm")
    kill("cca_reserve2")
    run(2)
    check(count(host, "Goto", "cca_reserve2") == 1, "a dead reserve is never ordered again")
end

-- ============================================================ 9. the respawn rally
do
    local host, guests = session(true, 3)
    eachPeer(function(p) check(p.rally[0] == "avrecycle", "rally on the Texas recycler") end)
    run(60)
    eachPeer(function(p) check(p.rally[0] == "avrecycle", "the rally holds while the recycler lives") end)
    kill("avrecycle")
    run(1)
    eachPeer(function(p) check(next(p.rally) == nil, "no rally at a corpse") end)
end

-- ============================================================ 10. the Europa weather beats
do
    -- The artillery march (900 s) lifts the sky to level 3, once.
    local host, guests = session(true, 3)
    local s = host.state
    check(host.eu.targets[1] == 2 and #host.eu.targets == 1, "level 2 at the start only")
    runTo(s.artil_move_time + 1)
    check(host.eu.targets[#host.eu.targets] == 3, "level 3 at the artillery march")
    local steps = #host.eu.targets
    run(60)
    check(#host.eu.targets == 2 and steps == 2, "the beat is a one-shot: level 2 then level 3, nothing else")
end
do
    -- The third wave also lifts it.
    local host = session(true, 2)
    local s = host.state
    runTo(s.next_wave_time + 1)
    check(host.eu.targets[#host.eu.targets] == 2, "wave 2 alone does not raise the sky")
    runTo(s.next_wave_time + 1)
    check(s.wave3 and host.eu.targets[#host.eu.targets] == 3, "level 3 when the third wave lands")
    check(#host.eu.targets == 2, "...once")
end
do
    -- The factory falls: a burst, a quake and a surge reach everyone exactly once.
    local host, guests = session(true, 4)
    kill("svmuf")
    run(25)
    check(#host.eu.forces == 1 and #host.eu.quakes == 1 and #host.eu.surges == 1, "the factory beats fire once on the leader")
    check(host.eu.forces[1][1] == 5 and host.eu.forces[1][2] == 60.0 and host.eu.forces[1][3] == 10.0, "level 5 for 60 s, ramp 10 s")
    check(host.eu.quakes[1][1] == 0.7 and host.eu.quakes[1][2] == 5.0, "quake 0.7 for 5 s")
    check(host.eu.surges[1][1] == 6.0 and host.eu.surges[1][2] == 0.8, "surge 6 s at 0.8")
    for _, g in ipairs(guests) do
        local seen = {}
        for _, ev in ipairs(g.eu.events) do seen[ev[1]] = (seen[ev[1]] or 0) + 1 end
        check(seen.EuropaQuake == 1 and seen.EuropaSurge == 1, "weather events reach each guest once")
        for _, ev in ipairs(g.eu.events) do
            if ev[1] == "EuropaQuake" then check(ev[2] == 0.7 and ev[3] == 5.0, "the quake arrives with its parameters") end
            if ev[1] == "EuropaSurge" then check(ev[2] == 6.0 and ev[3] == 0.8, "the surge arrives with its parameters") end
        end
        check(#g.eu.forces == 0 and #g.eu.quakes == 0 and #g.eu.surges == 0, "a guest raises no beat of its own")
    end
    check(host.eu.releases == 0, "a factory kill alone does not calm the sky")
end

-- ============================================================ 11. robustness
do
    -- An unsupported team halts the body and warns once.
    local host, guests = session(true, 2, nil, function()
        eachPeer(function(p) p.env.CreatePlayer(60, "Odd", 6) end)
    end)
    local s = host.state
    run(30)
    check(not s.start_done and count(host, "BuildObject") == 0 and count(host, "SetAIP") == 0, "an unsupported team stops the body")
    eachPeer(function(p)
        check(count(p, "DisplayMessage") == 1, "the restart warning shows once")
        check(callsOf(p, "DisplayMessage")[1][2]:find("Use distinct teams"), "the warning explains the restart")
    end)
    check(count(host, "SetPilot") == 0 and count(host, "Play", "misn1300.wav") == 0, "no briefing plays")
end
do
    -- A late joiner halts a running mission.
    local host, guests = session(true, 2)
    local s = host.state
    check(s.start_done, "late joiner: the mission has started")
    local nextWave = s.next_wave_time
    eachPeer(function(p) p.env.CreatePlayer(50, "Late", 4) end)
    runTo(nextWave + 5)
    eachPeer(function(p)
        check(count(p, "DisplayMessage") == 1 and callsOf(p, "DisplayMessage")[1][2]:find("Late join"), "the late-join warning shows once")
    end)
    check(not s.wave2 and builtAt(host, "svtank", "spawn_geyser1") == 0 and s.next_wave_time == nextWave,
        "the body no longer runs after a late join")
    run(20)
    check(count(host, "DisplayMessage") == 1, "and the warning does not repeat")
end
do
    -- A guest that leaves mid-game is not an error.
    local host, guests = session(true, 4)
    eachPeer(function(p) p.env.DeletePlayer(guests[3].id, "P", 4) end)
    peers[guests[3].id] = nil
    run(30)
    check(count(host, "FailMission") == 0 and host.state.start_done, "a departing guest does not stop the mission")
end
do
    -- Presentation survives packet loss: E and A packets are dropped 40 percent of the time.
    reset()
    local lossy = makeDropper(0.4)
    local host, guests = session(true, 4, function() dropper = lossy end, nil, 12)
    local s = host.state
    run(20)
    check(dropCount > 0, "packet loss: packets were actually dropped")
    local sameStart, whyStart = samePresentation(host, guests[1])
    for _, g in ipairs(guests) do
        check(count(g, "Play", "misn1300.wav") == 1 and count(g, "AddObjective", "misn13_silos") == 1,
            "packet loss: the opening reaches every guest exactly once")
        check(count(g, "SetObjectiveName", "apcamr20_camerapod") == 1, "packet loss: the nav marker reaches every guest once")
    end
    for _, g in ipairs(guests) do
        local same, why = samePresentation(host, g)
        check(same, "packet loss: guest " .. g.id .. " matches the leader: " .. tostring(why))
    end
    kill("svmuf")
    run(20)
    for _, g in ipairs(guests) do
        local seen = {}
        for _, ev in ipairs(g.eu.events) do seen[ev[1]] = (seen[ev[1]] or 0) + 1 end
        check(seen.EuropaQuake == 1 and seen.EuropaSurge == 1, "packet loss: weather events arrive once each")
        check(updatesFor(g, "misn13_factory") == 1, "packet loss: the factory update arrives once")
    end
    for _, t in ipairs({"svguntower2", "svsilo1", "svsilo2", "svsilo3", "svsilo4"}) do kill(t) end
    run(60)
    local results = 0
    for _, g in ipairs(guests) do
        check(count(g, "SucceedMission") == 1 and last(g, "SucceedMission")[3] == "misn13w1.des", "packet loss: the win arrives once")
        check(count(g, "Play", "misn1303.wav") == 1, "packet loss: the victory line arrives once")
        check(count(g, "SetAIControl") == 1 and count(g, "BuildObject") == 0, "packet loss: a guest stays silent")
        check((g.state.coopUnresolved or 0) == 0, "packet loss: nothing unresolved")
        results = results + 1
    end
    check(results == 3 and count(host, "SucceedMission") == 1, "packet loss: every peer holds exactly one result")
    for _, g in ipairs(guests) do
        local same, why = samePresentation(host, g)
        check(same, "packet loss: the full stream still matches: " .. tostring(why))
    end
    dropper = nil
end
do
    -- A dead nav pod: the leader reports it gone and nobody waits.
    local host, guests = session(true, 2, nil, nil, 3)
    check((guests[1].state.coopUnresolved or 0) == 0 and (host.state.coopUnresolved or 0) == 0, "no unresolved markers in a clean start")
end

-- ============================================================ 12. misn1301 and the dialogue schedule
do
    local host, guests = session(true, 3)
    local s = host.state
    local tBrief = callsOf(host, "Play")[1].t
    check(callsOf(host, "Play")[1][2] == "misn1300.wav", "the briefing is the first line")
    runTo(s.first_wave_time + 0.25)
    check(s.first_wave, "the first attack has begun")
    local tFirst = s.collins_time - 25.0
    check(s.collins_time < 99998 and tFirst > tBrief, "Collins is scheduled 25 s after the first attack")
    check(s.collins_time - tBrief > 22, "...after the 22 s briefing has ended")
    runTo(s.collins_time)
    eachPeer(function(p) check(count(p, "Play", "misn1301.wav") == 0, "misn1301 waits for its strict boundary") end)
    tick()
    run(1)
    eachPeer(function(p) check(count(p, "Play", "misn1301.wav") == 1, "misn1301 plays once on every peer") end)
    local order = {}
    for _, c in ipairs(guests[1].calls) do if c[1] == "Play" then order[#order + 1] = c[2] end end
    check(order[1] == "misn1300.wav" and order[2] == "misn1301.wav", "the guests hear 1300 before 1301")
    run(120)
    eachPeer(function(p) check(count(p, "Play", "misn1301.wav") == 1 and count(p, "Play", "misn1300.wav") == 1, "neither line repeats") end)
    check(s.collins_done, "the Collins latch is set")
end
do
    -- A mission that ends first never plays it.
    local host, guests = session(true, 2)
    local s = host.state
    runTo(s.first_wave_time + 10)
    kill("avrecycle")
    run(60)
    eachPeer(function(p) check(count(p, "Play", "misn1301.wav") == 0, "no Collins line after the mission has ended") end)
end

-- ============================================================ 13. offline smoke
do
    local host = session(false, 1)
    local s = host.state
    check(s.start_done and count(host, "SetAIControl") == 1 and firstIndex(host, "SetAIControl") <= host.chunkCalls,
        "offline: the AI is enabled once at chunk load")
    check(count(host, "DisableStartingRecycler") == 0, "offline: the starting recycler is untouched")
    check(count(host, "RemoveObject", "player0_hover") == 0, "offline: no placeholder removal")
    check(host.rally[0] == "avrecycle" and count(host, "Play", "misn1300.wav") == 1, "offline dialogue and rally")
    runTo(s.first_wave_time + 8)
    check(attacksOn(host, "avrecycle", 1) == DLL_FIRST_WAVE_ATTACKS and builtAt(host, "svtank", "choke_point1") == 0,
        "offline: the DLL's rush and nothing more")
    local w2 = waveSpawn(host, s, "spawn_geyser1", "choke_point3", 2, 1, "offline wave 2: ")
    check(#w2 == 3, "offline: the three-unit second wave")
    for _, t in ipairs({"svmuf", "svguntower2", "svsilo1", "svsilo2", "svsilo3", "svsilo4"}) do kill(t) end
    run(1)
    check(count(host, "SucceedMission") == 1 and last(host, "SucceedMission")[3] == "misn13w1.des",
        "offline: the win is a direct pass-through")
    check(count(host, "Send") == 0, "offline: nothing on the wire")
    check(host.eu.init.authority and host.eu.init.send == nil and host.eu.announces == 0, "offline weather is the host path with nothing sent")
    check(host.eu.releases == 1 and host.eu.targets[#host.eu.targets] == 1, "offline: calm on the win")
end
do
    local host = session(false, 1)
    run(5)
    kill("avrecycle")
    run(1)
    check(count(host, "FailMission") == 1 and last(host, "FailMission")[3] == "misn13f1.des", "offline: the recycler loss fails directly")
    check(count(host, "Play", "misn1304.wav") == 1, "offline: the loss line plays")
end

-- No pop-in: nothing is built at a spawn point a human is within 400 m of.
do
    local host, guests = session(true, 2)
    local s = host.state
    -- The opening rush: both humans at choke_point1, so the extra pair comes from an unwatched geyser instead.
    nearTo(host.player, "choke_point1", 50, 0)
    nearTo(guests[1].player, "choke_point1", -50, 0)
    runTo(s.first_wave_time + 8)
    check(builtAt(host, "svtank", "choke_point1") == 0 and builtAt(host, "svfigh", "choke_point1") == 0,
        "no pop-in: the rush pair is not built at a watched choke_point1")
    -- spawn_geyser2 is only ~280 m from choke_point1, so it is watched too: the pair comes from spawn_geyser1.
    check(builtAt(host, "svtank", "spawn_geyser2") == 0 and builtAt(host, "svtank", "spawn_geyser1") == 1
        and builtAt(host, "svfigh", "spawn_geyser1") == 1 and s.rush_extras,
        "no pop-in: ...it comes from the first unwatched point, spawn_geyser1")
    -- Wave 2: one human on each geyser, so the wave waits.
    nearTo(host.player, "spawn_geyser1", 100, 0)
    nearTo(guests[1].player, "spawn_geyser2", -100, 0)
    local mark = #host.calls
    runTo(s.next_wave_time)
    tick()
    check(not s.wave2 and #buildsSince(host, mark, "spawn_geyser1") == 0 and #buildsSince(host, mark, "spawn_geyser2") == 0,
        "no pop-in: wave 2 is not built while both geysers are watched")
    check(s.next_wave_time == now + 30.0, "no pop-in: ...it retries in 30 s")
    -- The guest leaves spawn_geyser2: wave 2 falls back to it, still heading for its own choke.
    nearTo(guests[1].player, "spawn_geyser2", 2000, 0)
    mark = #host.calls
    runTo(s.next_wave_time)
    tick()
    local list = buildsSince(host, mark, "spawn_geyser2")
    check(s.wave2 and #list == 5 and #buildsSince(host, mark, "spawn_geyser1") == 0,
        "no pop-in: wave 2 falls back to the unwatched spawn_geyser2")
    for _, b in ipairs(list) do
        check(orders(host, "Goto", b.h, "choke_point3", 1) == 1, "no pop-in: the fallback squad still drives to choke_point3")
    end
end

print("misn13 co-op: " .. checks .. " checks passed (multi-peer Lua 5.1 mock-engine)")
