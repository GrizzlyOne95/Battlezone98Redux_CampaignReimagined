-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Shared mock world for the chmisn02 suites (Test-Chmisn02Coop.lua, Test-Chmisn02Presentation.lua). Each peer runs
-- the complete Scripts/ch02cr.lua in its own Lua 5.1 environment over the real CRCoop registry and the E/A + C
-- presentation transport. The engine, AI and combat are mocks: they verify script decisions, not Redux
-- native map loading, pathfinding, Lua wire serialization or EXU hooks. Labels and paths are the real
-- Missions/ch02cr.bzn positions (Test-Chmisn02CoopContract.py checks the names against the map).
local PeerTransport = dofile("Tools/RuntimeTests/BZRPeerTransportSim.lua")
local F = {}
local W

F.LABELS = {
    ["recycler"] = {odf="cvrecy",team=1,pos={3104.95,10,98912.8},craft=false},
    ["hanger"] = {odf="cbhanga",team=1,pos={2957.24,10,98872.9},craft=false},
    ["comm_tower"] = {odf="cbcomm",team=1,pos={2956.65,10,98780.4},craft=false},
    ["armory"] = {odf="cvslf",team=1,pos={2949.87,10,98721.4},craft=false},
    ["attack_3_1"] = {odf="svfigh",team=5,pos={3486.38,10,102259},craft=true},
    ["attack_3_2"] = {odf="svfigh",team=5,pos={3485.06,10,102228},craft=true},
    ["attack_3_3"] = {odf="svfigh",team=5,pos={3489.69,10,102185},craft=true},
    ["attack_3_4"] = {odf="svfigh",team=5,pos={3490.35,10,102139},craft=true},
    ["attack_3_5"] = {odf="svfigh",team=5,pos={3491.01,10,102099},craft=true},
    ["attack_5_1"] = {odf="svtank",team=5,pos={3871.52,10,102899},craft=true},
    ["attack_5_2"] = {odf="svtank",team=5,pos={3871.52,10,102857},craft=true},
    ["attack_5_3"] = {odf="svtank",team=5,pos={3878.24,10,102810},craft=true},
    ["attack_5_4"] = {odf="svtank",team=5,pos={3876.56,10,102750},craft=true},
    ["attack_5_5"] = {odf="svtank",team=5,pos={3878.24,10,102691},craft=true},
    ["coop_spawn1"] = {odf="pspwn_1",team=1,pos={3087.05,10,98925.8},craft=false},
    ["coop_spawn2"] = {odf="pspwn_1",team=2,pos={3092.06,10,98901.3},craft=false},
    ["coop_spawn3"] = {odf="pspwn_1",team=3,pos={3097.06,10,98876.8},craft=false},
    ["coop_spawn4"] = {odf="pspwn_1",team=4,pos={3102.07,10,98852.3},craft=false},
}
-- First point of every path the script names (the real map's coordinates).
F.PATHS = {
    ["camera_start"]={3198.87,10,98941.4}, ["annoy_1"]={3034.38,10,99483.7}, ["hanger_attack_2"]={2440,10,98935},
    ["attack_6"]={2200,10,99275}, ["attack_6_path"]={2240,10,99250}, ["attack_7"]={3615,10,99370},
    ["hanger_attack_3"]={2525,10,100160}, ["walker_spawn"]={2060.38,10,100390}, ["walker_path"]={2071.85,10,100356},
    ["walker_attack_1"]={2025.96,10,100069}, ["walker_attack_2"]={2266.89,10,99732.5}, ["walker_attack_3"]={2300,10,99400},
    ["hanger_attack_5"]={2930,10,99225}, ["hanger_attack_6"]={3315,10,98970}, ["attack_8"]={3225,10,100195},
    ["convoy_units"]={55.58,10,102074}, ["convoy_path"]={69.35,10,102064}, ["convoy_defend"]={54.33,10,102079},
    ["convoy_attack_1"]={29.44,10,102087}, ["convoy_attack_2"]={218.12,10,102106}, ["convoy_attack_3"]={578.71,10,101793},
    ["convoy_attack_4"]={759,10,101525}, ["convoy_attack_5"]={1115.39,10,101202}, ["convoy_attack_6"]={959.79,10,100829},
    ["convoy_attack_7"]={794.17,10,101168}, ["convoy_attack_8"]={389.56,10,101508}, ["convoy_attack_9"]={197.41,10,101761},
    ["convoy_attack_10"]={1953.92,10,100976}, ["nav_convoy"]={1204.8,10,100783}, ["trigger_point_1"]={888.93,10,101271},
    ["trigger_point_2"]={2899.24,10,99898.6}, ["attack_9"]={1920,10,99180}, ["attack_9_path"]={1965,10,99175},
    ["attack_10"]={3654.8,10,99637.6}, ["hanger_attack_4"]={2589.8,10,101073},
}
-- Point counts and last points of the paths the body queries by index (AtEndOfPath).
F.PATH_COUNTS = {["walker_path"]=3}
F.PATH_ENDS = {["walker_path"]={3080.18,10,98922.4}}
F.FAR = 50000
local CRAFT = {svfigh=true,svtank=true,svwalk=true,svhraz=true,svartl=true,svltnk=true,svrckt=true,
    cvapcb=true,cvfighc=true,cvtnk=true,cvfigh=true}
local function vec(t) return {x = t[1], y = t[2], z = t[3]} end
local function newObject(handle, odf, team, pos, craft)
    W.objects[handle] = {alive = true, odf = odf, team = team, health = 1, pos = vec(pos or {F.FAR, 6, F.FAR}),
        craft = craft or CRAFT[odf] or false}
    local o = W.objects[handle]
    if F.LABELS[handle] then o.label = handle end
    return o
end

function F.reset()
    W = {now = 0, objects = {}, peers = {}, nextObject = 0, missing = {}, audioBusy = false, busyMessages = {}, net = false,
        cancel = false, cavalry = 1, cameraDone = {}, timer = nil}
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
function F.kill(h) W.objects[h].alive = false end
function F.hurt(h) W.objects[h].health = 0.5 end
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
-- Audio lines a peer heard (Play and Queue), in order.
function F.lines(peer)
    local out = {}
    for _, c in ipairs(peer.calls) do
        if c[1] == "Play" or c[1] == "Queue" then out[#out + 1] = c[2] end
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
-- options: weather = { module = fn(peer, record), sites = table }: Ganymede stand-ins (absent by default);
-- nilAudio = true: the subtitle service returns no audio handle
function F.makePeer(id, team, network, options)
    options = options or {}
    local p = {id = id, team = team, net = network, hosting = team == 1, calls = {}, player = "player" .. id,
        camera = 0}
    W.peers[id] = p
    W.net = W.net or network
    newObject(p.player, options.vehicle or "cvtnk", team, {3087.05 + 5 * (team - 1), 5, 98925.8 - 24.5 * (team - 1)}, true)
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
    e.SetTeamNum = function(h, t)
        assert(e.IsValid(h), "SetTeamNum on an invalid object")
        record("SetTeamNum", h, t)
        W.objects[h].team = t
    end
    e.SetPerceivedTeam = function(h, t)
        assert(e.IsValid(h), "SetPerceivedTeam on an invalid object")
        record("SetPerceivedTeam", h, t)
    end
    e.SetCommand = function(h, command, priority)
        assert(e.IsValid(h), "SetCommand on an invalid object")
        record("SetCommand", h, command, priority)
    end
    e.EnableAllCloaking = function(on) record("EnableAllCloaking", on) end
    e.GetPosition = function(h, index)
        -- Path overload (path, point): only the last waypoint is modelled (AtEndOfPath).
        if index ~= nil then
            assert(F.PATH_ENDS[h] and index == F.PATH_COUNTS[h] - 1, "native path point must be the last waypoint")
            return vec(F.PATH_ENDS[h])
        end
        local pos = F.posOf(h)
        return pos and {x = pos.x, y = pos.y, z = pos.z} or {x = 0, y = 0, z = 0}
    end
    e.IsCraft = function(h) return W.objects[h] ~= nil and W.objects[h].craft == true end
    e.GetFront = function(h) return {x = 0, y = 0, z = 1} end
    e.GetMaxHealth = function(h) return 1 end
    e.StopCockpitTimer = function() record("StopCockpitTimer") end
    e.HideCockpitTimer = function() record("HideCockpitTimer") end
    e.GetPathPointCount = function(name)
        if W.missingPaths and W.missingPaths[name] then return 0 end
        return F.PATH_COUNTS[name] or (W.pathPos[name] and 4 or 0)
    end
    e.GetDistance = function(a, b, index)
        assert(e.IsValid(a), "invalid origin reached native distance query")
        if index ~= nil then
            -- Path overload (object, path, point): only the last waypoint is modelled.
            assert(F.PATH_ENDS[b] and index == F.PATH_COUNTS[b] - 1, "native path point must be the last waypoint")
            local pa, pe = F.posOf(a), F.PATH_ENDS[b]
            return math.sqrt((pa.x - pe[1]) ^ 2 + (pa.z - pe[3]) ^ 2)
        end
        -- This mock names handles with strings, which the mission's guard reads as path names; a dead
        -- object named by a string is therefore answered "far" (Redux handles are never strings).
        if type(b) == "string" and W.objects[b] and not W.objects[b].alive then return 1e9 end
        assert(type(b) == "table" or (type(b) == "string" and (W.pathPos[b] or e.IsValid(b))), "invalid destination")
        local pa, pb = F.posOf(a), F.posOf(b)
        local dx, dz = pa.x - pb.x, pa.z - pb.z
        return math.sqrt(dx * dx + dz * dz)
    end
    e.GetNearestEnemy = function(h) return nil end
    e.GetHealth = function(h)
        assert(e.IsValid(h), "GetHealth on an invalid handle")
        return W.objects[h].health
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
    e.AllObjects = function()
        local list,seen={},{}
        for h,o in pairs(W.objects) do
            if o.alive and not seen[o] then list[#list+1]=h;seen[o]=true end
        end
        table.sort(list)
        local i=0;return function() i=i+1;return list[i] end
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
        record("RemoveObject", h)
        if W.objects[h] then W.objects[h].alive = false end
    end
    e.SetName = function(h, name)
        assert(e.IsValid(h), "SetName on an invalid handle")
        record("SetName", h, name)
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
    e.CameraObject = function(subject, x, y, z, target)
        assert(e.IsValid(subject) and e.IsValid(target), "invalid object camera")
        record("CameraObject", subject, x, y, z, target)
    end
    e.CameraCancelled = function() return W.cancel end
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
    -- math.random is recorded; the answer is W.cavalry clamped into the asked range (1 = the first candidate).
    e.math = setmetatable({random = function(lo, hi)
        record("random", lo, hi)
        return math.max(lo or 1, math.min(hi or 1, W.cavalry))
    end}, {__index = math})
    for _, name in ipairs({"Defend2", "Follow", "Defend", "Hunt", "Retreat", "Stop", "Goto", "Attack", "SetIndependence", "SetAIP",
        "SetAIControl", "SetObjectiveName", "SetObjectiveOn", "SetObjectiveOff", "ClearObjectives",
        "AddObjective", "UpdateObjective", "Ally", "UnAlly", "DisplayMessage", "FailMission", "SucceedMission",
        "SetScrap", "AddScrap", "SetPilot", "AddPilot", "StartEarthquake", "UpdateEarthQuake", "StopEarthquake"}) do
        local n = name
        e[n] = function(...)
            if n == "SetObjectiveOn" or n == "SetObjectiveOff" or n == "SetObjectiveName" or n == "SetIndependence" or n == "Follow" or n == "Defend2"
                or n == "Attack" or n == "Defend" or n == "Hunt" or n == "Stop" or n == "Goto" or n == "Retreat" then
                assert(e.IsValid((...)), n .. " used a not-yet-valid handle")
            end
            record(n, ...)
        end
    end
    e.StartCockpitTimer = function(time, warn, alert)
        W.timer = {start = W.now, duration = time}
        record("StartCockpitTimer", time, warn, alert)
    end
    e.GetScrap = function() return W.scrap or 0 end
    e.GetMaxScrap = function() return W.capacity or 30 end
    e.IsAudioMessageDone = function(m) return not W.audioBusy and not W.busyMessages[m] end
    e.AiCommand = {NONE=0,ATTACK=3,DEFEND=16,RECYCLE=18}
    local function noop() end
    local modules = {
        RequireFix = {Initialize = noop},
        exu = {GetMyNetID = function() return id end, DisableStartingRecycler = function() record("DisableStartingRecycler") end,
            SetLives = function(n) record("SetLives", n) end},
        ScriptSubtitles = {
            Play = function(file) record("Play", file); if not options.nilAudio then return "audio:" .. file end end,
            Queue = function(file) record("Queue", file); if not options.nilAudio then return "audio:" .. file end end,
            Stop = function() record("Stop") end, Update = noop, Initialize = noop},
        CRWire = assert(loadfile("Scripts/CRWire.lua"))(),
        Environment = {Init=function(o) record("EnvironmentInit", o) end,
            BindWeatherSensors=function(name) record("WeatherSensors",name) end,
            Update=noop,OnObjectCreated=noop,InvalidateRenderer=noop},
        PersistentConfig = {Initialize=function() record("PdaInitialize") end,
            UpdateInputs=function() record("PdaUpdate") end,UpdateHeadlights=noop},
    }
    -- options.weather = { module = fn(peer, record), sites = table|nil }: Ganymede stand-ins; absent by default.
    if options.weather then
        if options.weather.module then modules.CREuropaWeather = options.weather.module(p, record) end
        if options.weather.sites then modules.CRGanymedeSitesCH02 = options.weather.sites end
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
    setfenv(assert(loadfile(options.script or "Scripts/ch02cr.lua")), e)()
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
