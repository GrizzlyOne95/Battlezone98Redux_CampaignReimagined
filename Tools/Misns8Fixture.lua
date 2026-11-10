-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Shared mock world for the misns8 co-op suite (Test-Misns8Coop.lua). Each peer runs
-- the complete Scripts/misns8cr.lua in its own Lua 5.1 environment over the real CRCoop registry and the E/A + C
-- presentation transport. The engine, AI and combat are mocks: they verify script decisions, not Redux
-- native map loading, pathfinding, Lua wire serialization or EXU hooks. Labels and paths are generated from
-- the body's own references (Test-Misns8CoopContract.py checks them against Missions/misns8cr.bzn; coordinates are the map's).
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local F = {}
local W

F.LABELS = {
    ["player0_wingman"] = {odf="playsv",team=1,pos={1793,16,100362},craft=true},
    ["avmuf_geyser"] = {odf="eggeizr1",team=0,pos={3022,43,98909},craft=false},
    ["eggeizr11_geyser"] = {odf="eggeizr1",team=0,pos={2958,43,98881},craft=false},
    ["sv_geyser"] = {odf="eggeizr1",team=0,pos={3092,43,98918},craft=false},
    ["center_geyser"] = {odf="eggeizr1",team=0,pos={2743,43,99891},craft=false},
    ["eggeizr14_geyser"] = {odf="eggeizr1",team=0,pos={1869,15,100070},craft=false},
    ["eggeizr15_geyser"] = {odf="eggeizr1",team=0,pos={2664,43,100033},craft=false},
    ["dis_geyser2"] = {odf="eggeizr1",team=0,pos={3289,26,99898},craft=false},
    ["last_geyser"] = {odf="eggeizr1",team=0,pos={3313,22,100330},craft=false},
    ["eggeizr18_geyser"] = {odf="eggeizr1",team=0,pos={3330,43,100514},craft=false},
    ["eggeizr19_geyser"] = {odf="eggeizr1",team=0,pos={3163,43,100572},craft=false},
    ["first_geyser"] = {odf="eggeizr1",team=0,pos={2122,15,98963},craft=false},
    ["eggeizr116_geyser"] = {odf="eggeizr1",team=0,pos={2601,117,99718},craft=false},
    ["eggeizr117_geyser"] = {odf="eggeizr1",team=0,pos={2762,146,99618},craft=false},
    ["eggeizr118_geyser"] = {odf="eggeizr1",team=0,pos={2603,116,99897},craft=false},
    ["eggeizr119_geyser"] = {odf="eggeizr1",team=0,pos={2460,145,99884},craft=false},
    ["eggeizr120_geyser"] = {odf="eggeizr1",team=0,pos={2365,113,99978},craft=false},
    ["eggeizr121_geyser"] = {odf="eggeizr1",team=0,pos={2899,128,99808},craft=false},
    ["eggeizr122_geyser"] = {odf="eggeizr1",team=0,pos={2943,123,100103},craft=false},
    ["svrecycle"] = {odf="svrecy",team=1,pos={1836,16,100340},craft=true},
    ["svmuf"] = {odf="savmf",team=1,pos={1801,16,100327},craft=true},
    ["temp_geyser"] = {odf="eggeizr1",team=0,pos={2493,43,99364},craft=false},
    ["dis_geyser1"] = {odf="eggeizr1",team=0,pos={3003,43,99445},craft=false},
    ["cam"] = {odf="apcamr",team=1,pos={3079,44,98881},craft=false},
    ["turret_geyser"] = {odf="eggeizr1",team=0,pos={2051,27,99794},craft=false},
    ["av_geyser"] = {odf="eggeizr1",team=0,pos={1874,15,100368},craft=false},
    ["eggeizr12_geyser"] = {odf="eggeizr1",team=0,pos={1810,15,100270},craft=false},
    ["eggeizr13_geyser"] = {odf="eggeizr1",team=0,pos={1870,15,100250},craft=false},
    ["powerplant1"] = {odf="abwpow",team=5,pos={2996,43,98843},craft=false},
    ["powerplant2"] = {odf="abwpow",team=5,pos={3023,43,98856},craft=false},
    ["basetower1"] = {odf="abtowe",team=5,pos={3066,43,98858},craft=false},
    ["basetower2"] = {odf="abtowe",team=5,pos={2951,43,98820},craft=false},
    ["basecam"] = {odf="apcamr",team=1,pos={1813,16,100358},craft=false},
    ["avmuf"] = {odf="bvmuf",team=5,pos={3030,44,98906},craft=true},
    ["avrecycle"] = {odf="bvrec8",team=5,pos={2959,44,98868},craft=true},
    ["coop_spawn1"] = {odf="pspwn_1",team=1,pos={1793,16,100362},craft=false},
    ["coop_spawn2"] = {odf="pspwn_1",team=2,pos={1813,16,100377},craft=false},
    ["coop_spawn3"] = {odf="pspwn_1",team=3,pos={1833,16,100393},craft=false},
    ["coop_spawn4"] = {odf="pspwn_1",team=4,pos={1852,16,100408},craft=false},
}
F.PATHS = {
    ["world"] = {1281,155,100699},
    ["alien6"] = {2767,155,99595},
    ["escape"] = {4718,155,102278},
    ["convoy_path"] = {2960,155,99014},
    ["mpower1"] = {2759,155,99836},
    ["mtower1"] = {2768,155,99797},
    ["mpower2"] = {2724,155,99923},
    ["mtower2"] = {2711,155,99960},
    ["rpower1"] = {2991,155,98882},
    ["rpower2"] = {3093,155,98926},
    ["rtower1"] = {2973,155,98920},
    ["rtower2"] = {3107,155,98884},
    ["escape_route"] = {3098,155,99013},
    ["alt_tower"] = {3270,155,100260},
    ["main_field1"] = {2437,155,99312},
    ["american_spawn"] = {2917,155,98888},
    ["main_field2"] = {2464,155,99309},
    ["a_post1"] = {2589,155,99264},
    ["t1post"] = {2017,155,99690},
    ["t2post"] = {2088,155,99748},
    ["t3post"] = {2143,155,99798},
    ["alt_silo"] = {3319,155,100323},
    ["alt_power"] = {3283,155,100276},
    ["center_path"] = {2802,155,99060},
    ["center_path2"] = {2831,155,99055},
    ["center_path3"] = {2844,155,99030},
    ["center_silo"] = {2481,155,99348},
    ["go_path"] = {2606,155,99513},
    ["cam_spawn"] = {2752,155,99932},
    ["last_nav_spawn"] = {3368,155,100266},
    ["romeski_spawn"] = {2991,155,98726},
    ["edge_path"] = {1054,155,100982},
}
F.FAR = 50000
local CRAFT = {bvartl=true,bvcnst=true,bvtavk=true,bvsca8=true,bvra8=true,avart8=true,bvmuf=true,bvrec8=true,avcns8=true,bvtur8=true,bvhraz=true,
    bvapc=true,bvwalk=true,savtnk=true,savs8=true,svtank=true,playsv=true,svrecy=true,savmf=true}
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
        scrapOf = {}, unitCounts = {},
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
    newObject(p.player, options.vehicle or "playsv", team, {1793 + 20 * (team - 1), 16, 100362}, true)
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
        "SetPilot", "AddPilot", "Build", "Dropoff", "Pickup", "StartEarthquake", "UpdateEarthQuake", "StopEarthquake"}) do
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
    -- Per-team scrap (the body reads and writes both sides' stock).
    e.GetScrap = function(team) return W.scrapOf[team] or 0 end
    e.SetScrap = function(team, amount) W.scrapOf[team] = amount; record("SetScrap", team, amount) end
    e.AddScrap = function(team, amount) W.scrapOf[team] = (W.scrapOf[team] or 0) + amount; record("AddScrap", team, amount) end
    e.CountUnitsNearObject = function(h, radius, team, odf)
        record("CountUnitsNearObject", h, radius, team, odf)
        return W.unitCounts[team .. ":" .. odf] or 2
    end
    e.SetPerceivedTeam = function(h, team)
        assert(e.IsValid(h), "SetPerceivedTeam on an invalid object")
        W.objects[h].perceived = team; record("SetPerceivedTeam", h, team)
    end
    e.IsDeployed = function(h) return W.objects[h] ~= nil and W.objects[h].deployed == true end
    e.GetHealth = function(h) return W.objects[h] and W.objects[h].health or 0 end
    e.GetMaxScrap = function() return W.capacity or 30 end
    e.GetCurHealth = function(h) return W.objects[h] and W.objects[h].health or 0 end
    e.GetCurrentCommand = function(h) return W.objects[h] and W.objects[h].command or 0 end
    e.GetLastEnemyShot = function() return 0 end
    e.GetWhoShotMe = function(h) return W.objects[h] and W.objects[h].shotBy end
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
            BindWeatherSensors=function(name, director) record("WeatherSensors",name, director ~= nil) end,
            Update=noop,OnObjectCreated=noop,InvalidateRenderer=noop},
        PersistentConfig = {Initialize=function() record("PdaInitialize") end,
            UpdateInputs=function() record("PdaUpdate") end,UpdateHeadlights=noop},
    }
    -- options.weather = { module = fn|nil, sites = table|nil }: CRTitanWeather stand-ins; absent by default.
    if options.weather then
        if options.weather.module then modules.CRTitanWeather = options.weather.module(p, record) end
        if options.weather.sites then modules.CRTitanSitesS8 = options.weather.sites end
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
    setfenv(assert(loadfile(options.script or "Scripts/misns8cr.lua")), e)()
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
