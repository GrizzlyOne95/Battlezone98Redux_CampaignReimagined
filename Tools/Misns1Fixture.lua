-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Shared mock world for the misns1 suites (Test-Misns1Coop.lua, Test-Misns1Presentation.lua). Each peer runs
-- the complete Scripts/misns1cr.lua in its own Lua 5.1 environment over the real CRCoop registry and the E/A + C
-- presentation transport. The engine, AI and combat are mocks: they verify script decisions, not Redux
-- native map loading, pathfinding, Lua wire serialization or EXU hooks. Labels and paths are generated from
-- the body's own references (Missions/misns1cr.bzn is not shipped yet; Test-Misns1CoopContract.py checks it).
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local F = {}
local W

F.LABELS = {
    ["svrecy2_recycler"] = {odf="svrecy",team=1,pos={0,95,0},craft=true},
    ["eggeizr10_geyser"] = {odf="eggeizr1",team=0,pos={2500,94,0},craft=false},
    ["avmuf1_factory"] = {odf="avmuf",team=5,pos={2600,95,200},craft=true},
    ["absilo1_i76building"] = {odf="bbsilo",team=5,pos={2650,95,260},craft=false},
    ["avrecy1_recycler"] = {odf="avrecy",team=5,pos={4000,95,500},craft=true},
    ["avfigh3_wingman"] = {odf="avfigh",team=5,pos={4020,95,520},craft=true},
    ["avfigh4_wingman"] = {odf="avfigh",team=5,pos={4040,95,540},craft=true},
    ["avfigh5_wingman"] = {odf="avfigh",team=5,pos={4060,95,560},craft=true},
    ["avtank5_wingman"] = {odf="avtank",team=5,pos={4080,95,580},craft=true},
    ["avtank6_wingman"] = {odf="avtank",team=5,pos={4100,95,600},craft=true},
    ["avtank7_wingman"] = {odf="avtank",team=5,pos={4120,95,620},craft=true},
    ["avtank8_wingman"] = {odf="avtank",team=5,pos={4140,95,640},craft=true},
    ["ambase"] = {odf="spcamr",team=0,pos={5200,95,900},craft=false},
    ["apcamr0_camerapod"] = {odf="spcamr",team=1,pos={40,95,10},craft=false},
    ["coop_spawn1"] = {odf="pspwn_1",team=1,pos={20,95,40},craft=false},
    ["coop_spawn2"] = {odf="pspwn_1",team=2,pos={45,95,40},craft=false},
    ["coop_spawn3"] = {odf="pspwn_1",team=3,pos={70,95,40},craft=false},
    ["coop_spawn4"] = {odf="pspwn_1",team=4,pos={95,95,40},craft=false},
}
F.PATHS = {
    ["spawnwalker1"] = {800,155,300}, ["walkcam1"] = {900,155,320},
    ["hidcamupper"] = {3000,155,1500}, ["hidcammiddle"] = {3200,155,800}, ["hidcamlower"] = {3100,155,100},
    ["tank1"] = {200,155,50}, ["tank2"] = {220,155,60}, ["figh1"] = {240,155,70},
    ["turr1"] = {260,155,80}, ["turr2"] = {280,155,90},
    ["upperpath"] = {3500,155,1500}, ["midpath"] = {3600,155,800}, ["lowerpath"] = {3700,155,100},
    ["retreat1"] = {4600,155,2500}, ["safepoint"] = {5000,155,-500},
    ["halfwayupper"] = {3400,155,1400}, ["halfwaymid"] = {3500,155,700}, ["halfwaylower"] = {3600,155,50},
    ["cavspawn"] = {6000,155,3000}, ["cavpath1"] = {5500,155,2000}, ["cavpath2"] = {5600,155,2500},
}
-- The shipped map has none of the DLL's cinematic paths; tests add them with F.addCinematicPaths(world).
F.CINEMATIC_PATHS = {
    ["cinpath3"] = {10,155,10}, ["cinpath4"] = {4000,155,500}, ["geyserpath"] = {2500,155,0},
    ["approach"] = {3000,155,100}, ["cinpath1"] = {2600,155,200},
}
function F.addCinematicPaths(world)
    for name, p in pairs(F.CINEMATIC_PATHS) do world.pathPos[name] = {x = p[1], y = p[2], z = p[3]} end
end
F.FAR = 50000
local CRAFT = {bvtank=true,bvraz=true,bvscav=true,bvturr=true,avtank=true,avfigh=true,avscav=true,avturr=true,svtank=true,svfigh=true,svturr=true,svwalk=true}
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
        cancel = false, random = 1, route = 1, cavalry = 1, cameraDone = {}, timer = nil}
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
-- options: titan = a CRTitanWeather stand-in module (nil: the module is absent)
function F.makePeer(id, team, network, options)
    options = options or {}
    local p = {id = id, team = team, net = network, hosting = team == 1, calls = {}, player = "player" .. id,
        camera = 0}
    W.peers[id] = p
    W.net = W.net or network
    newObject(p.player, options.vehicle or "avtank", team, {1943 - 15 * (team - 1), 94, 98015}, true)
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
    e.GetPosition = function(h)
        local pos = F.posOf(h)
        return pos and {x = pos.x, y = pos.y, z = pos.z} or {x = 0, y = 0, z = 0}
    end
    e.SetVelocity = function(h,v) assert(e.IsValid(h) and W.objects[h].craft,"velocity only on known craft");record("SetVelocity",h,v) end
    e.SetPosition = function(h,pos) assert(e.IsValid(h)); W.objects[h].pos={x=pos.x,y=pos.y,z=pos.z};record("SetPosition",h,pos.y) end
    -- Extraction ending (CRDrop18): matrices are plain tables, SetTransform moves the mock object.
    e.BuildDirectionalMatrix = function(pos, dir) return {x = pos.x, y = pos.y, z = pos.z, dx = dir and dir.x or 0, dz = dir and dir.z or 1} end
    e.BuildPositionRotationMatrix = function(pitch,yaw,roll,x,y,z)
        return {x=x,y=y,z=z,pitch=pitch,yaw=yaw,roll=roll}
    end
    e.SetTransform = function(h, m)
        assert(e.IsValid(h), "SetTransform on an invalid object")
        W.objects[h].pos = {x = m.x, y = m.y, z = m.z}
        record("SetTransform", h, m.x, m.y, m.z)
    end
    e.IsCraft = function(h) return W.objects[h] ~= nil and W.objects[h].craft == true end
    e.GetFront = function(h) return {x = 0, y = 0, z = 1} end
    e.GetMaxHealth = function(h) return 1 end
    e.SetCurHealth = function(h, v) record("SetCurHealth", h, v) end
    e.StopCockpitTimer = function() record("StopCockpitTimer") end
    e.HideCockpitTimer = function() record("HideCockpitTimer") end
    e.GetPathPointCount = function(name)
        if W.missingPaths and W.missingPaths[name] then return 0 end
        return W.pathPos[name] and 4 or 0
    end
    e.SetVector = function(x, y, z) return {x = x or 0, y = y or 0, z = z or 0} end
    e.GetTerrainHeightAndNormal = function(pos) return 6, {x = 0, y = 1, z = 0} end
    e.GetDistance = function(a, b)
        assert(e.IsValid(a), "invalid origin reached native distance query")
        -- This mock names handles with strings, which the mission's guard reads as path names; a dead
        -- object named by a string is therefore answered "far" (Redux handles are never strings).
        if type(b) == "string" and W.objects[b] and not W.objects[b].alive then return 1e9 end
        assert(type(b) == "table" or (type(b) == "string" and (W.pathPos[b] or e.IsValid(b))), "invalid destination")
        local pa, pb = F.posOf(a), F.posOf(b)
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
    e.IsAudioMessageDone = function() return not W.audioBusy end
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
    e.SetMaxHealth = function(h, v) record("SetMaxHealth", h, v) end
    e.AddHealth = function(h, v) record("AddHealth", h, v) end
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
    e.math = setmetatable({random = function(lo, hi)
        record("random", lo, hi)
        return hi == 2 and W.route or W.cavalry
    end}, {__index = math})
    for _, name in ipairs({"Defend2", "Follow", "Defend", "Retreat", "Stop", "Goto", "Attack", "SetIndependence", "SetAIP",
        "SetAIControl", "SetObjectiveName", "SetObjectiveOn", "SetObjectiveOff", "ClearObjectives",
        "AddObjective", "UpdateObjective", "Ally", "UnAlly", "DisplayMessage", "FailMission", "SucceedMission",
        "SetScrap", "AddScrap", "SetPilot", "AddPilot", "StartEarthquake", "UpdateEarthQuake", "StopEarthquake"}) do
        local n = name
        e[n] = function(...)
            if n == "SetObjectiveOn" or n == "SetObjectiveName" or n == "SetIndependence" or n == "Follow"
                or n == "Attack" or n == "Defend" or n == "Stop" or n == "Goto" or n == "Retreat" then
                assert(e.IsValid((...)), n .. " used a not-yet-valid handle")
            end
            record(n, ...)
        end
    end
    e.StartCockpitTimer = function(time, warn, alert)
        W.timer = {start = W.now, duration = time}
        record("StartCockpitTimer", time, warn, alert)
    end
    e.GetCockpitTimer = function()
        -- MultSTMission calls StartCockpitTimerUp every frame (live 2026-10-19, run misn18-win-1p-a: the reading equals the
        -- mission clock whatever StartCockpitTimer asked for), so a countdown can never be read back from the engine.
        return math.floor(W.now)
    end
    e.GetScrap = function() return W.scrap or 0 end
    e.GetMaxScrap = function() return W.capacity or 30 end
    e.GetCurHealth = function(h) return W.objects[h] and W.objects[h].health or 0 end
    e.GetCurrentCommand = function(h) return W.objects[h] and W.objects[h].command or 0 end
    e.GetLastEnemyShot = function() return 0 end
    e.GetWhoShotMe = function() return nil end
    e.Damage = function(h,amount) assert(e.IsValid(h));record("Damage",h,amount);W.objects[h].alive=false end
    e.IsAudioMessageDone = function() return not W.audioBusy end
    e.AiCommand = {NONE=0,ATTACK=3,DEFEND=16}
    e.GetCurrentWho = function(h) return W.objects[h] and W.objects[h].target end
    local function noop() end
    local modules = {
        RequireFix = {Initialize = noop},
        exu = {GetMyNetID = function() return id end, DisableStartingRecycler = function() record("DisableStartingRecycler") end,
            SetLives = function(n) record("SetLives", n) end},
        ScriptSubtitles = {
            Play = function(file) record("Play", file); return "audio:" .. file end,
            Queue = function(file) record("Queue", file); return "audio:" .. file end,
            Stop = function() record("Stop") end, Update = noop, Initialize = noop},
        CRWire = assert(loadfile("Scripts/CRWire.lua"))(),
        Environment = {Init=function(o) record("EnvironmentInit", o) end,
            BindWeatherSensors=function(name) record("WeatherSensors",name) end,
            Update=noop,OnObjectCreated=noop,InvalidateRenderer=noop},
        PersistentConfig = {Initialize=function() record("PdaInitialize") end,
            UpdateInputs=function() record("PdaUpdate") end,UpdateHeadlights=noop},
    }
    -- options.weather = { module = table|nil, sites = table|nil }: Venus stand-ins; absent by default.
    if options.weather then
        if options.weather.module then modules.CRVenusWeather = options.weather.module(p, record) end
        if options.weather.sites then modules.CRVenusSitesS1 = options.weather.sites end
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
    setfenv(assert(loadfile(options.script or "Scripts/misns1cr.lua")), e)()
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
