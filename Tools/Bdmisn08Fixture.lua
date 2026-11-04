-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Shared mock world for the bdmisn08 suites (Test-Bdmisn08Coop.lua, Test-Bdmisn08Presentation.lua). Each peer runs
-- the complete co-op script in its own Lua 5.1 environment over the real CRCoop registry and the E/A + C
-- presentation transport. The engine, AI and combat are mocks: they verify script decisions, not Redux
-- native map loading, pathfinding, Lua wire serialization or EXU hooks. Labels and paths are the real
-- co-op map positions (Test-Bdmisn08CoopContract.py checks the names against the map).
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local F = {}
local W
-- The engine basename limit applies to string literals; the script name is split like the other suites do.
F.SCRIPT = "Scripts/bdmisn" .. "08cr.lua"
F.FAITHFUL = "Scripts/bdmisn08.lua"

F.LABELS = {
    ["portal"] = {odf="cbport",team=5,pos={1607.28,39,101767},craft=false},
    ["command"] = {odf="bbhqcp",team=1,pos={1254.23,48,100873},craft=false},
    ["recycler"] = {odf="bvrecy",team=1,pos={1242.17,49.5,100976},craft=false},
    ["factory"] = {odf="bvmuf",team=1,pos={1264.9,49.5,100966},craft=false},
    ["nav_base"] = {odf="apcamr",team=1,pos={1236.3,49.063,101050},craft=false},
    ["nav_portal"] = {odf="apcamr",team=1,pos={1520.44,39.0044,101752},craft=false},
    ["eggeizr17_geyser"] = {odf="eggeizr1",team=0,pos={1201.43,48,100954},craft=false},
    ["eggeizr18_geyser"] = {odf="eggeizr1",team=0,pos={1258.61,48,100944},craft=false},
    ["eggeizr19_geyser"] = {odf="eggeizr1",team=0,pos={1238.84,48,100980},craft=false},
    ["bvltnk34_wingman"] = {odf="bvltnk",team=1,pos={1213.73,49,100911},craft=true},
    ["bvraz35_wingman"] = {odf="bvraz",team=1,pos={1217.16,49,100902},craft=true},
    ["bvraz36_wingman"] = {odf="bvraz",team=1,pos={1208.49,49,100914},craft=true},
    ["coop_spawn1"] = {odf="pspwn_1",team=1,pos={1222.82,49,100921},craft=false},
    ["coop_spawn2"] = {odf="pspwn_1",team=2,pos={1245.74,49,100911},craft=false},
    ["coop_spawn3"] = {odf="pspwn_1",team=3,pos={1268.65,49,100901},craft=false},
    ["coop_spawn4"] = {odf="pspwn_1",team=4,pos={1291.57,49,100891},craft=false},
}
-- Every point of the paths the script walks (first and last point of the long ones).
F.PATH_POINTS = {
    ["spawn1"]={{1598.32,10,101758}},
    ["attack_path2"]={{1586.56,10,101751},{1214.81,10,100961}},
    ["attack_path1"]={{1591.23,10,101748},{1280.81,10,100979}},
    ["edge_path"]={{872.135,10,100557},{1892.4,10,102148}},
    ["path_portalcam"]={{1604.01,10,101806},{1572.4,10,101755}},
    ["path_camera_intro"]={{1262.57,10,101196},{1223.9,10,100924}},
    ["portal_in"]={{1580.83,10,101701},{1599.23,10,101751}},
    ["portal_out"]={{1605.23,10,101753},{1588.83,10,101697}},
    ["spawn_pilot"]={{1601.23,10,101746}},
}
F.PATHS = {}
for name, points in pairs(F.PATH_POINTS) do F.PATHS[name] = points[1] end
F.FAR = 50000
local CRAFT = {bvtank=true,bvraz=true,bvltnk=true,bvscav=true,bvturr=true,cspilo=true,
    cvfigh=true,cvltnk=true,cvtnk=true,cvrckt=true,cvhraz=true,cvapc=true}
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
    newObject(p.player, options.vehicle or "avtank", team, {1223 + 23 * (team - 1), 49, 100921 - 10 * (team - 1)}, true)
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
    e.GetPositionNear = function(pos) return {x = pos.x, y = pos.y, z = pos.z} end
    e.SetVector = function(x, y, z) return {x = x, y = y, z = z} end
    e.GetMaxHealth = function(h) return W.objects[h] and (W.objects[h].maxHealth or 1) or 0 end
    e.SetMaxHealth = function(h, v) if W.objects[h] then W.objects[h].maxHealth = v end; record("SetMaxHealth", h, v) end
    e.SetCurHealth = function(h, v) record("SetCurHealth", h, v) end
    e.SetVelocity = function(h, v) record("SetVelocity", h, v) end
    e.IsCraft = function(h) return W.objects[h] ~= nil and W.objects[h].craft == true end
    e.StopCockpitTimer = function() record("StopCockpitTimer") end
    e.HideCockpitTimer = function() record("HideCockpitTimer") end
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
    -- Portal and pilot natives. Touching is "within 30 m"; an object built at a portal carries an AI pilot.
    e.IsTouching = function(a, b)
        assert(e.IsValid(a) and e.IsValid(b), "IsTouching used an invalid handle")
        local pa, pb = F.posOf(a), F.posOf(b)
        return math.sqrt((pa.x - pb.x) ^ 2 + (pa.z - pb.z) ^ 2) < 30
    end
    e.isPortalActive = function(h) assert(e.IsValid(h), "isPortalActive on an invalid handle"); return W.objects[h].active == true end
    e.ActivatePortal = function(h) assert(e.IsValid(h)); W.objects[h].active = true; record("ActivatePortal", h) end
    e.DeactivatePortal = function(h) assert(e.IsValid(h)); W.objects[h].active = false; record("DeactivatePortal", h) end
    e.PortalIn = function(h) assert(e.IsValid(h)); W.objects[h].inward = true; record("PortalIn", h) end
    e.PortalOut = function(h) assert(e.IsValid(h)); W.objects[h].inward = false; record("PortalOut", h) end
    e.BuildObjectAtPortal = function(odf, objectTeam, portal)
        assert(e.IsValid(portal), "BuildObjectAtPortal on an invalid portal")
        W.nextObject = W.nextObject + 1
        local h = "built" .. W.nextObject
        local pos = F.posOf(portal)
        newObject(h, odf, objectTeam, {pos.x, pos.y, pos.z})
        W.objects[h].pilot = "cspilo"
        record("BuildObjectAtPortal", h, odf, objectTeam, portal)
        for _, peer in pairs(W.peers) do if peer.env then peer.env.AddObject(h) end end
        return h
    end
    e.RemovePilot = function(h) assert(e.IsValid(h)); W.objects[h].pilot = nil; record("RemovePilot", h) end
    e.GetPilotClass = function(h) assert(e.IsValid(h)); return W.objects[h].pilot end
    e.IsAliveAndPilot = function(h) return e.IsValid(h) and W.objects[h].pilot ~= nil end
    e.SetPerceivedTeam = function(h, t) assert(e.IsValid(h)); W.objects[h].perceived = t; record("SetPerceivedTeam", h, t) end
    e.GetIn = function(pilot, vehicle, priority)
        assert(e.IsValid(pilot) and e.IsValid(vehicle), "GetIn used an invalid handle")
        record("GetIn", pilot, vehicle, priority)
    end
    -- W.audioBusy holds every line; W.busyFile holds one line ("bd08002.wav") while the others finish.
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
        if options.weather.sites then modules.CRGanymedeSitesBD08 = options.weather.sites end
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
