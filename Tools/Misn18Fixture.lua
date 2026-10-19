-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Shared mock world for the misn18 suites (Test-Misn18Coop.lua). Each peer runs the complete
-- Scripts/misn18.lua in its own Lua 5.1 environment over the real CRCoop registry and the E/A + C
-- presentation transport. The engine, AI and combat are mocks: they verify script decisions, not Redux
-- native map loading, pathfinding, Lua wire serialization or EXU hooks. Labels and paths are generated from
-- the shipped Missions/misn18.bzn (Tools/Build-Misn18CoopMap.py).
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local F = {}
local W

F.LABELS = {
    ["myCar_hover"] = {odf="player",team=1,pos={1943.08,94.3488,98015.1},craft=true},
    ["eggeizr11_geyser"] = {odf="eggeizr1",team=0,pos={1979.2,93.588,98059.0},craft=false},
    ["eggeizr12_geyser"] = {odf="eggeizr1",team=0,pos={1876.68,94.129,98032.1},craft=false},
    ["avrecy2_recycler"] = {odf="avrecy",team=1,pos={1875.2,95.7931,98035.1},craft=true},
    ["avmuf2_factory"] = {odf="avmuf",team=1,pos={1976.53,95.077,98057.7},craft=true},
    ["avtank0_wingman"] = {odf="avtank",team=1,pos={1909.17,94.6921,98064.6},craft=true},
    ["avtank1_wingman"] = {odf="avtank",team=1,pos={1925.42,94.7896,98074.9},craft=true},
    ["cr18_scrap1"] = {odf="sfield",team=0,pos={1465.25,115.76,97926.7},craft=false},
    ["cr18_scrap2"] = {odf="sfield",team=0,pos={1969.12,103.968,98251.0},craft=false},
    ["cr18_scrap3"] = {odf="sfield",team=0,pos={1823.31,104.876,98269.2},craft=false},
    ["cr18_scrap4"] = {odf="sfield",team=0,pos={1991.96,95.2264,98147.3},craft=false},
    ["cr18_scrap5"] = {odf="sfield",team=0,pos={1680.61,109.985,97890.4},craft=false},
    ["scrapcam"] = {odf="sscr_1",team=0,pos={839.823,181.169,97988.8},craft=false},
    ["scrapcam2"] = {odf="sscr_1",team=0,pos={1176.77,295.741,98897.5},craft=false},
    ["cr18_scrap6"] = {odf="sfield",team=0,pos={1840.78,94.887,97977.4},craft=false},
    ["cr18_scrap7"] = {odf="sfield",team=0,pos={1896.6,95.008,98127.4},craft=false},
    ["basenav"] = {odf="apcamr",team=1,pos={1944.77,94.2619,98108.1},craft=false},
    ["hbtran0038_i76building"] = {odf="hbtran00",team=6,pos={1533.04,3.2,100892.0},craft=false},
    ["hbtrn20049_i76building"] = {odf="hbtrn200",team=6,pos={1530.43,3.2,100867.0},craft=false},
    ["hbtrn20050_i76building"] = {odf="hbtrn200",team=6,pos={1508.32,3.2,100895.0},craft=false},
    ["hbtrn20051_i76building"] = {odf="hbtrn200",team=6,pos={1535.39,3.2,100917.0},craft=false},
    ["hbtrn20052_i76building"] = {odf="hbtrn200",team=6,pos={1558.1,3.2,100890.0},craft=false},
    ["coop_spawn1"] = {odf="pspwn_1",team=1,pos={1943.08,94.3488,98015.1},craft=false},
    ["coop_spawn2"] = {odf="pspwn_1",team=2,pos={1927.75,94.3488,97995.4},craft=false},
    ["coop_spawn3"] = {odf="pspwn_1",team=3,pos={1912.42,94.3488,97975.6},craft=false},
    ["coop_spawn4"] = {odf="pspwn_1",team=4,pos={1897.09,94.3488,97955.9},craft=false},
}
F.PATHS = {
    ["spawn1b"] = {395.965,155,98114.5},
    ["spawnrand"] = {287.443,155,98131.2},
    ["spawn2b"] = {984.487,155,99469.1},
    ["spawn3b"] = {705.558,155,100738},
    ["dontgo"] = {921.878,155,99865},
    ["dgs1"] = {934.4,155,99538.9},
    ["dontgo2"] = {967.791,155,99522.2},
    ["dgs2"] = {976.139,155,99314.6},
    ["dontgo3"] = {926.052,155,99193.6},
    ["dgs3"] = {951.096,155,98958.7},
    ["transfound"] = {1216.69,155,101097},
    ["spawnalt2b"] = {1955.34,155,99607.4},
    ["spawnalt1a"] = {1638.94,155,99012.1},
    ["spawnalt1b"] = {1798.4,155,99132.9},
    ["spawnalt2a"] = {1883.59,155,99356.3},
    ["spawnalt3a"] = {1650.64,155,99807.7},
    ["spawnalt3b"] = {1429.43,155,99891.2},
    ["return1"] = {1870.63,155,99330.4},
    ["return2"] = {863.443,155,98918.1},
    ["spawnreturn"] = {1448.3,155,98448.6},
    ["opencam1"] = {2026.72,155,98061.5},
    ["opencam2"] = {1959.44,155,98007},
    ["blastoffcam"] = {1899.76,155,98093.2},
    ["transdestroyedcam"] = {1466.99,155,100897},
    ["opencam3"] = {1365.7,155,101115},
    ["spawn2a"] = {934.4,155,99256.2},
    ["spawn1a"] = {1281.05,155,97975.3},
    ["spawn3a"] = {809.183,155,100442},
    ["edge_path"] = {2096,155,101243},
    ["spawnrand2"] = {2155.69,155,99297.1},
    ["transport1"] = {1465.88,155,101016},
    ["transport2"] = {1524.31,155,100979},
    ["transport3"] = {1457.53,155,100962},
    ["transport4"] = {1566.05,155,100979},
    ["transport5"] = {1607.79,155,100899},
    ["transport6"] = {1611.97,155,100824},
    ["transport7"] = {1461.7,155,100812},
    ["transport8"] = {1531.73,155,101009},
    ["transport9"] = {1533.07,155,101053},
    ["dontgo1"] = {921.878,155,99755.9},
    ["cheat1a"] = {1242.17,155,98241},
    ["cheatalt1a"] = {2034.8,155,98758.2},
    ["cheat2a"] = {1402.69,155,99426.4},
    ["cheatalt2a"] = {2274.21,155,99385.3},
    ["cheat3a"] = {1986.99,155,100381},
    ["cheatalt3a"] = {1580.89,155,100312},
}
F.FAR = 50000
local CRAFT = {avtank=true,avscav=true,avapc=true,avturr=true,avartl=true,svtank=true,svapc=true,hvsav=true,hvsat=true,crfraz=true}
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
        cancel = false, random = 1, cameraDone = {}, timer = nil}
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
        return math.max(lo, math.min(hi, W.random))
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
            if n == "SetIndependence" then
                local odf = W.objects[(...)].odf
                assert(odf == "hvsat" or odf == "hvsav" or odf == "crfraz", "SetIndependence only on scripted Furies")
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
        CRFuryRoster = assert(loadfile("Scripts/CRFuryRoster.lua"))(),
        CRDrop18 = (not options.noDrop) and assert(loadfile("Scripts/CRDrop18.lua"))() or nil,
        CRWire = assert(loadfile("Scripts/CRWire.lua"))(),
        Environment = {Init=function() record("EnvironmentInit") end,
            BindWeatherSensors=function(name) record("WeatherSensors",name) end,
            Update=noop,OnObjectCreated=noop,InvalidateRenderer=noop},
        PersistentConfig = {Initialize=function() record("PdaInitialize") end,
            UpdateInputs=function() record("PdaUpdate") end,UpdateHeadlights=noop},
    }
    -- options.storm: a CRStorm18 stand-in (a module table, or {Create=...}); nil leaves the module absent.
    if options.storm then modules.CRStorm18 = options.storm(p, record, e, modules) end
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
    modules.CRMisn18 = setfenv(assert(loadfile("Scripts/CRMisn18.lua")),e)()
    setfenv(assert(loadfile("Scripts/misn18.lua")), e)()
    p.chunkCalls = #p.calls -- everything recorded so far ran at chunk load, before Start
    p.env, p.coop, p.runtime = e, modules.CRCoop, modules.CRMisn18
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
