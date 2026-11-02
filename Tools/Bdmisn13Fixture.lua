-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Shared mock world for the bdmisn13 suites (Test-Bdmisn13Coop.lua, Test-Bdmisn13Presentation.lua). Each peer runs
-- the complete co-op script in its own Lua 5.1 environment over the real CRCoop registry and the E/A + C
-- presentation transport. The engine, AI and combat are mocks: they verify script decisions, not Redux
-- native map loading, pathfinding, Lua wire serialization or EXU hooks. Labels and paths are the real
-- co-op map positions (Test-Bdmisn13CoopContract.py checks the names against the map).
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local F = {}
local W
-- The engine basename limit applies to string literals; the script name is split like the other suites do.
F.SCRIPT = "Scripts/bdmisn" .. "13cr.lua"
F.FAITHFUL = "Scripts/bdmisn13.lua"

F.LABELS = {
    ["recycler"] = {odf="bvrecy",team=1,pos={2179,22,99816},craft=false},
    ["bvcnst3_constructionrig"] = {odf="bvcnst",team=1,pos={2170,21,99849},craft=true},
    ["chin_recycler"] = {odf="cvrecy",team=5,pos={2995,18,101864},craft=false},
    ["chin_silo1"] = {odf="cbsilo",team=5,pos={1193,17,100217},craft=false},
    ["chin_silo2"] = {odf="cbsilo",team=5,pos={625,28,99234},craft=false},
    ["chin_silo3"] = {odf="cbsilo",team=5,pos={584,11,100954},craft=false},
    ["chin_silo4"] = {odf="cbsilo",team=5,pos={1546,19,101380},craft=false},
    ["chin_silo5"] = {odf="cbsilo",team=5,pos={2459,18,100728},craft=false},
    ["chin_silo6"] = {odf="cbsilo",team=5,pos={3222,22,99570},craft=false},
    ["nav_chin_silo1"] = {odf="apcamr",team=1,pos={1500,21,100244},craft=false},
    ["nav_chin_silo2"] = {odf="apcamr",team=1,pos={903,21,99613},craft=false},
    ["nav_chin_silo3"] = {odf="apcamr",team=1,pos={951,8,100862},craft=false},
    ["nav_chin_silo4"] = {odf="apcamr",team=1,pos={1495,25,101115},craft=false},
    ["nav_chin_silo5"] = {odf="apcamr",team=1,pos={2705,30,100903},craft=false},
    ["nav_chin_silo6"] = {odf="apcamr",team=1,pos={2963,6,99750},craft=false},
    ["eggeizr10_geyser"] = {odf="eggeizr1",team=0,pos={2176.83,20.47,99826.6},craft=false},
    ["eggeizr11_geyser"] = {odf="eggeizr1",team=0,pos={2174.69,20.94,99787.6},craft=false},
    ["coop_spawn1"] = {odf="pspwn_1",team=1,pos={2134,21,99829},craft=false},
    ["coop_spawn2"] = {odf="pspwn_1",team=2,pos={2159,21,99829},craft=false},
    ["coop_spawn3"] = {odf="pspwn_1",team=3,pos={2184,21,99830},craft=false},
    ["coop_spawn4"] = {odf="pspwn_1",team=4,pos={2209,21,99831},craft=false},
}
-- Every point of the paths the script walks (first and last point of the long ones).
F.PATH_POINTS = {
    ["spawn_attack_waves"]={{2459.58,10,102252}},
    ["spawn_defend1"]={{1103.66,10,99822.8}},
    ["spawn_defend6"]={{1905.98,10,100721}},
    ["spawn_defend2"]={{519.57,10,100047}},
    ["spawn_defend5"]={{949.614,10,101440}},
    ["spawn_defend7"]={{2560.67,10,101408}},
    ["spawn_defend8"]={{3096.17,10,100474}},
    ["spawn_defend9"]={{2695.46,10,100099}},
    ["camera_intro"]={{3185.98,10,99729.3},{3052.96,10,99564.3}},
    ["edge_path"]={{352.992,10,102113},{3504.99,10,98816.6}},
}
F.PATHS = {}
for name, points in pairs(F.PATH_POINTS) do F.PATHS[name] = points[1] end
F.FAR = 50000
local CRAFT = {bvtank=true,bvcnst=true,cvfigh=true,cvltnk=true,cvtnk=true,cvrckt=true,cvhraz=true,cvhtnk=true}
local function vec(t) return {x = t[1], y = t[2], z = t[3]} end
local function newObject(handle, odf, team, pos, craft)
    W.objects[handle] = {alive = true, odf = odf, team = team, health = 1, pos = vec(pos or {F.FAR, 6, F.FAR}),
        craft = craft or CRAFT[odf] or false}
    local o = W.objects[handle]
    if F.LABELS[handle] then o.label = handle end
    return o
end

function F.reset()
    W = {now = 0, objects = {}, peers = {}, nextObject = 0, missing = {}, audioBusy = false, net = false,
        cancel = false, random = 0, cameraDone = {}, timer = nil}
    W.pathPos = {}
    for name, p in pairs(F.PATHS) do W.pathPos[name] = vec(p) end
    -- Authored objects exist from the start (AllCraft sees them whether or not the script asked for them).
    for label, spec in pairs(F.LABELS) do newObject(label, spec.odf, spec.team, spec.pos, spec.craft) end
    W.transport = PeerTransport.New(function(packet)
        local peer = W.peers[packet.to]
        if peer then peer.env.Receive(packet.from, packet.kind, unpack(packet.args)) end
    end)
    return W
end

function F.posOf(h)
    if type(h) == "table" then return h end
    if W.objects[h] then return W.objects[h].pos end
    return W.pathPos[h]
end
function F.place(h, x, z) local o = W.objects[h]; o.pos = {x = x, y = o.pos.y, z = z} end
function F.nearTo(h, target, dx, dz)
    local t = F.posOf(target)
    W.objects[h].pos = {x = t.x + (dx or 0), y = t.y, z = t.z + (dz or 0)}
end
function F.kill(h) W.objects[h].alive = false; W.objects[h].health = 0 end
function F.alive(h) return W.objects[h] ~= nil and W.objects[h].alive end
function F.team(h) return W.objects[h] and W.objects[h].team end
function F.spawn(odf, team, x, z)
    W.nextObject = W.nextObject + 1
    local h = "test" .. W.nextObject
    newObject(h, odf, team, {x or F.FAR, 6, z or F.FAR})
    for _, p in pairs(W.peers) do p.env.AddObject(h) end
    return h
end

-- ----------------------------------------------------------------------- call queries
function F.count(peer, name, first)
    local n = 0
    for _, c in ipairs(peer.calls) do
        if c[1] == name and (first == nil or c[2] == first) then n = n + 1 end
    end
    return n
end
function F.callsOf(peer, name)
    local out = {}
    for _, c in ipairs(peer.calls) do if c[1] == name then out[#out + 1] = c end end
    return out
end
function F.last(peer, name)
    for i = #peer.calls, 1, -1 do if peer.calls[i][1] == name then return peer.calls[i] end end
end
function F.index(peer, name, first)
    for i, c in ipairs(peer.calls) do if c[1] == name and (first == nil or c[2] == first) then return i end end
end
-- Builds: {h, odf, team, where} since a call mark.
function F.builds(peer, mark, odf)
    local out = {}
    for i = (mark or 0) + 1, #peer.calls do
        local c = peer.calls[i]
        if c[1] == "BuildObject" and (odf == nil or c[3] == odf) then
            out[#out + 1] = {h = c[2], odf = c[3], team = c[4], where = c[5]}
        end
    end
    return out
end
-- Audio lines a peer heard (Play and Queue; AudioMessage in the faithful run), in order.
function F.lines(peer)
    local out = {}
    for _, c in ipairs(peer.calls) do
        if c[1] == "Play" or c[1] == "Queue" or c[1] == "AudioMessage" then out[#out + 1] = c[2] end
    end
    return out
end
function F.heard(peer, file)
    for _, f in ipairs(F.lines(peer)) do if f == file then return true end end
    return false
end
function F.heardCount(peer, file)
    local n = 0
    for _, f in ipairs(F.lines(peer)) do if f == file then n = n + 1 end end
    return n
end

-- ----------------------------------------------------------------------- peers
-- options: weather = { module = fn(peer, record), sites = table }: Europa stand-ins (absent by default);
-- faithful = true runs options.script (the DLL port) without the CR layer.
function F.makePeer(id, team, network, options)
    options = options or {}
    local p = {id = id, team = team, net = network, hosting = team == 1, calls = {}, player = "player" .. id,
        camera = 0}
    W.peers[id] = p
    W.net = W.net or network
    newObject(p.player, options.vehicle or "avtank", team, {2134 + 25 * (team - 1), 21, 99829}, true)
    local function record(name, ...)
        local c = {name, ...}
        c.t, c.n = W.now, select("#", ...)
        p.calls[#p.calls + 1] = c
    end
    p.record = record
    local e = setmetatable({}, {__index = _G})
    e._G = e
    e.print = function(...) record("print", ...) end
    e.IsNetGame = function() return p.net end
    e.IsHosting = function() return p.hosting end
    e.GetTime = function() return W.now end
    e.GetPlayerHandle = function(remote)
        assert(remote == nil, "remote GetPlayerHandle(team) must never be used")
        return p.player
    end
    e.GetHandle = function(label)
        if W.missing[label] then return nil end
        if not W.objects[label] then
            local spec = F.LABELS[label]
            if spec then newObject(label, spec.odf, spec.team, spec.pos, spec.craft) else return nil end
        end
        return W.objects[label].alive and label or nil
    end
    e.GetLabel = function(h) return W.objects[h] and W.objects[h].label end
    e.SetLabel = function(h, label)
        if W.objects[h] then
            W.objects[h].label = label
            if not W.objects[label] then W.objects[label] = W.objects[h] end
        end
    end
    e.IsValid = function(h) return type(h) == "string" and W.objects[h] ~= nil and W.objects[h].alive end
    e.IsAlive = e.IsValid
    e.IsOdf = function(h, odf) return e.IsValid(h) and W.objects[h].odf == odf end
    e.GetOdf = function(h) return W.objects[h] and W.objects[h].odf end
    e.GetTeamNum = function(h) return W.objects[h] and W.objects[h].team or 0 end
    e.GetPosition = function(h)
        local pos = F.posOf(h)
        return pos and {x = pos.x, y = pos.y, z = pos.z} or {x = 0, y = 0, z = 0}
    end
    e.IsCraft = function(h) return W.objects[h] ~= nil and W.objects[h].craft == true end
    -- The cockpit timer: the engine counts down, unless W.stuckTimer says the map class restarts it upward every
    -- frame (MultSTMission), in which case it never reaches zero.
    e.StartCockpitTimer = function(seconds, warn, alert)
        record("StartCockpitTimer", seconds, warn, alert); W.timerEnd = W.now + seconds
    end
    e.StopCockpitTimer = function() record("StopCockpitTimer") end
    e.HideCockpitTimer = function() record("HideCockpitTimer"); W.timerShown = false end
    e.GetCockpitTimer = function()
        if W.stuckTimer or W.timerEnd == nil then return W.now + 1 end
        return math.max(0, W.timerEnd - W.now)
    end
    e.GetScrap = function() return 0 end
    -- A dead handle must reach this query (the body asks after the silo is gone).
    e.IsRecycledByTeam = function(h, team) return W.objects[h] ~= nil and W.objects[h].recycledBy == team end
    e.GetPathPointCount = function(name)
        if W.missingPaths and W.missingPaths[name] then return 0 end
        return F.PATH_POINTS[name] and #F.PATH_POINTS[name] or 0
    end
    -- GetDistance(h, to) and the path-point form GetDistance(h, path, index) (zero based).
    e.GetDistance = function(a, b, index)
        assert(e.IsValid(a), "invalid origin reached native distance query")
        -- This mock names handles with strings, which the mission's guard reads as path names; a dead
        -- object named by a string is therefore answered "far" (Redux handles are never strings).
        if type(b) == "string" and W.objects[b] and not W.objects[b].alive then return 1e9 end
        assert(type(b) == "table" or (type(b) == "string" and (W.pathPos[b] or e.IsValid(b))), "invalid destination")
        local pa, pb = F.posOf(a), F.posOf(b)
        if index ~= nil then
            assert(F.PATH_POINTS[b] and F.PATH_POINTS[b][index + 1], "path point out of range")
            pb = vec(F.PATH_POINTS[b][index + 1])
        end
        local dx, dz = pa.x - pb.x, pa.z - pb.z
        return math.sqrt(dx * dx + dz * dz)
    end
    -- Teams 1-4 and 7 are one alliance; 0 is neutral; everyone else is an enemy of everyone.
    local function allied(t1, t2)
        local function side(t) return (t >= 1 and t <= 4 or t == 7) and "nsdf" or t end
        return t1 == t2 or side(t1) == side(t2)
    end
    e.GetNearestEnemy = function(h)
        local best, bestD
        local mine = F.team(h)
        for k, o in pairs(W.objects) do
            if o.alive and o.craft and k ~= h and o.team ~= 0 and not allied(mine, o.team) then
                local pa, pb = F.posOf(h), o.pos
                local d = math.sqrt((pa.x - pb.x) ^ 2 + (pa.z - pb.z) ^ 2)
                if bestD == nil or d < bestD then best, bestD = k, d end
            end
        end
        return best
    end
    e.AllCraft = function()
        local list = {}
        for h, o in pairs(W.objects) do
            if o.alive and o.craft and o.label ~= nil and W.objects[o.label] == o and h ~= o.label then
                -- an alias created by SetLabel; the real key is listed separately
            elseif o.alive and o.craft then
                list[#list + 1] = h
            end
        end
        table.sort(list)
        local i = 0
        return function() i = i + 1; return list[i] end
    end
    e.BuildObject = function(odf, objectTeam, where)
        assert(type(where) == "table" or W.pathPos[where] or e.IsValid(where), "invalid spawn location")
        W.nextObject = W.nextObject + 1
        local h = "built" .. W.nextObject
        local pos = F.posOf(where)
        newObject(h, odf, objectTeam, {pos.x, pos.y, pos.z})
        record("BuildObject", h, odf, objectTeam, where)
        for _, peer in pairs(W.peers) do if peer.env then peer.env.AddObject(h) end end
        return h
    end
    e.RemoveObject = function(h)
        -- The world is shared between the mock peers: a guest's removal of an object the authority already removed is fine.
        assert(e.IsValid(h) or (W.removed and W.removed[h]), "RemoveObject used a not-yet-valid handle")
        W.removed = W.removed or {}
        W.removed[h] = true
        record("RemoveObject", h)
        if W.objects[h] then W.objects[h].alive = false; W.objects[h].health = 0 end
    end
    e.GetHealth = function(h) return W.objects[h] and W.objects[h].alive and W.objects[h].health or 0 end
    -- W.audioBusy holds every line; W.busyFile holds one line ("bd13002.wav") while the others finish.
    e.IsAudioMessageDone = function(m)
        return not (W.audioBusy or (W.busyFile ~= nil and m == "audio:" .. W.busyFile))
    end
    e.StopAudioMessage = function(m) record("StopAudioMessage", m) end
    e.CameraReady = function() p.camera = p.camera + 1; record("CameraReady") end
    e.CameraFinish = function()
        assert(p.camera > 0, "CameraFinish without CameraReady")
        p.camera = p.camera - 1
        record("CameraFinish")
    end
    e.CameraPath = function(path, height, speed, target)
        assert(target == nil or e.IsValid(target), "invalid camera target")
        record("CameraPath", path, height, speed, target)
        return W.cameraDone[path] == true
    end
    e.CameraCancelled = function() return W.cancel == true or W.cancelFor == id end
    e.AudioMessage = function(file) record("AudioMessage", file); return "audio:" .. file end
    e.Send = function(to, kind, ...)
        record("Send", kind)
        local args = {...}
        for index = 1, select("#", ...) do
            -- A map-authored handle arrives as an invalid handle on a guest.
            if type(args[index]) == "string" and F.LABELS[args[index]] then args[index] = false end
        end
        local bytes = 4
        for _, value in ipairs(args) do
            -- Redux decodes a packet string length as a signed byte; longer strings crash peers.
            assert(type(value) ~= "string" or #value <= 127, "mission packet string over 127 bytes: " .. kind)
            bytes = bytes + (type(value) == "string" and #value + 2 or 9)
        end
        assert(bytes < 244, "mission packet exceeds stock payload budget: " .. kind)
        for target in pairs(W.peers) do
            if target ~= id and (to == 0 or to == nil or target == to) then W.transport:Send(id, target, kind, args, false) end
        end
    end
    -- Deterministic: math.random(lo, hi) answers lo + W.random (mod the range).
    e.math = setmetatable({random = function(lo, hi)
        record("random", lo, hi)
        return lo + (W.random % (hi - lo + 1))
    end}, {__index = math})
    -- Orders: every handle they name must already be a real object (a ticket reaching a native is a bug).
    local checked = {Follow = true, Attack = true, Defend2 = true}
    for _, name in ipairs({"Defend2", "Follow", "Defend", "Retreat", "Stop", "Goto", "Attack", "Hunt", "SetIndependence",
        "SetCloaked", "SetAIP", "SetAIControl", "SetObjectiveName", "SetObjectiveOn", "SetObjectiveOff",
        "ClearObjectives", "AddObjective", "UpdateObjective", "Ally", "UnAlly", "DisplayMessage", "FailMission",
        "SucceedMission", "SetScrap", "AddScrap", "SetPilot", "AddPilot"}) do
        local n = name
        e[n] = function(...)
            if n == "SetObjectiveOn" or n == "SetObjectiveName" or n == "SetIndependence" or n == "Follow"
                or n == "Attack" or n == "Defend" or n == "Defend2" or n == "Stop" or n == "Goto" or n == "Retreat"
                or n == "Hunt" or n == "SetCloaked" then
                assert(e.IsValid((...)), n .. " used a not-yet-valid handle")
            end
            if checked[n] then
                local target = select(2, ...)
                assert(e.IsValid(target), n .. " named a not-yet-valid target")
            end
            if n == "SetCloaked" and W.objects[(...)] then W.objects[(...)].cloaked = true end
            record(n, ...)
        end
    end
    local function noop() end
    local modules = {
        RequireFix = {Initialize = noop},
        exu = {GetMyNetID = function() return id end, DisableStartingRecycler = function() record("DisableStartingRecycler") end,
            SetLives = function(n) record("SetLives", n) end},
        ScriptSubtitles = {
            Play = function(file) record("Play", file); if W.nilAudio then return nil end; return "audio:" .. file end,
            Queue = function(file) record("Queue", file); if W.nilAudio then return nil end; return "audio:" .. file end,
            Stop = function() record("Stop") end, Update = noop, Initialize = noop},
        CRWire = assert(loadfile("Scripts/CRWire.lua"))(),
        Environment = {Init=function(o) record("EnvironmentInit", o) end,
            BindWeatherSensors=function(name) record("WeatherSensors",name) end,
            Update=noop,OnObjectCreated=noop,InvalidateRenderer=noop},
        PersistentConfig = {Initialize=function() record("PdaInitialize") end,
            UpdateInputs=function() record("PdaUpdate") end,UpdateHeadlights=noop},
    }
    -- options.weather = { module = fn|nil, sites = table|nil }: Europa stand-ins; absent by default.
    if options.weather then
        if options.weather.module then modules.CREuropaWeather = options.weather.module(p, record) end
        if options.weather.sites then modules.CRGanymedeSitesBD13 = options.weather.sites end
    end
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
    e.require = function(name)
        local m = modules[name]
        if m == nil then error("module '" .. name .. "' not found") end
        return m
    end
    modules.CRCCARuntime = setfenv(assert(loadfile("Scripts/CRCCARuntime.lua")),e)()
    if options.faithful then e.CR_TEST_FAITHFUL = true end
    setfenv(assert(loadfile(options.script or F.SCRIPT)), e)()
    p.chunkCalls = #p.calls -- everything recorded so far ran at chunk load, before Start
    p.env, p.coop, p.runtime, p.modules = e, modules.CRCoop, modules.CRCCARuntime, modules
    e.Start()
    return p
end

function F.connect()
    -- Every peer learns every other peer (the engine's CreatePlayer/AddPlayer callbacks).
    for _, p in pairs(W.peers) do
        for _, q in pairs(W.peers) do
            if p.net then
                if p == q then p.env.CreatePlayer(q.id, "P" .. q.id, q.team) else p.env.AddPlayer(q.id, "P" .. q.id, q.team) end
            end
        end
    end
end

function F.tick(dt)
    dt = dt or 0.25
    W.now = W.now + dt
    for _, p in pairs(W.peers) do p.env.Update(dt) end
    W.transport:Step(W.now, false, nil)
end
function F.run(seconds, dt)
    dt = dt or 0.25
    for _ = 1, math.floor(seconds / dt + 0.5) do F.tick(dt) end
end
function F.runUntil(predicate, limit, dt)
    local start = W.now
    while not predicate() do
        assert(W.now - start < (limit or 3000), "timed out waiting")
        F.tick(dt)
    end
end
function F.world() return W end
function F.host() for _, p in pairs(W.peers) do if p.team == 1 then return p end end end
function F.state(p) return p.env.Save() end

return F
