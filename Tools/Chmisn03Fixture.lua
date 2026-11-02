-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Shared mock world for the chmisn03 suites (Test-Chmisn03Coop.lua, Test-Chmisn03Presentation.lua). Each peer runs
-- the complete Scripts/chmisn03cr.lua in its own Lua 5.1 environment over the real CRCoop registry and the E/A + C
-- presentation transport. The engine, AI and combat are mocks: they verify script decisions, not Redux
-- native map loading, pathfinding, Lua wire serialization or EXU hooks. Labels and paths are the real
-- Missions/chmisn03cr.bzn positions (Test-Chmisn03CoopContract.py checks the names against the map).
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local F = {}
local W

F.LABELS = {
    ["player"] = {odf="csuser",team=1,pos={4821.64,2.4,99543.6},craft=false},
    ["player_tank"] = {odf="cvtnk",team=1,pos={4829.42,2.01594,99564.6},craft=true},
    ["cvminea0_minelayer"] = {odf="cvminea",team=1,pos={4818.68,2.40394,99564.9},craft=true},
    ["howitzer_1"] = {odf="cvartl",team=0,pos={4714.39,177.681,100928},craft=true},
    ["howitzer_2"] = {odf="cvartl",team=0,pos={4888.56,160.792,100626},craft=true},
    ["howitzer_3"] = {odf="cvartl",team=0,pos={2970.9,160.665,101510},craft=true},
    ["howitzer_4"] = {odf="cvartl",team=0,pos={2938.46,129.643,101231},craft=true},
    ["howitzer_5"] = {odf="cvartl",team=0,pos={711.788,155.473,101496},craft=true},
    ["howitzer_6"] = {odf="cvartl",team=0,pos={555.655,129.852,101695},craft=true},
    ["eggeizr17_geyser"] = {odf="eggeizr1",team=0,pos={4834.26,1.25594,99563.6},craft=false},
    ["coop_spawn1"] = {odf="pspwn_1",team=1,pos={4821.64,2.4,99543.6},craft=false},
    ["coop_spawn2"] = {odf="pspwn_1",team=2,pos={4796.66,2.4,99544.7},craft=false},
    ["coop_spawn3"] = {odf="pspwn_1",team=3,pos={4771.69,2.4,99545.7},craft=false},
    ["coop_spawn4"] = {odf="pspwn_1",team=4,pos={4746.71,2.4,99546.8},craft=false},
}
-- First point of each path in Missions/chmisn03cr.bzn.
F.PATHS = {
    ["edge_path"]={80.0001,1,102173},
    ["north_exit"]={3092.51,1,101336},
    ["east_exit"]={4711.05,1,100732},
    ["west_exit"]={610.898,1,101384},
    ["patrol_path_1"]={1426.67,1,98780},
    ["patrol_path_2"]={558.433,1,101541},
    ["patrol_path_3"]={4578.41,1,100530},
    ["factory_path"]={4989.43,1,98552.8},
    ["factory"]={5002.45,1,98535},
    ["apc_east"]={2063.02,1,97313.3},
    ["apc_north"]={2021.35,1,97309.7},
    ["apc_west"]={1976.35,1,97318.8},
    ["west_defend"]={1973.85,1,97307.2},
    ["north_defend"]={2023.02,1,97301.3},
    ["east_defend"]={2063.85,1,97305.5},
    ["north_fail"]={2190.6,1,102257},
    ["east_fail"]={5006.8,1,100733},
    ["west_fail"]={138.434,1,101643},
    ["factory_attack"]={3838.06,1,99275.6},
    ["apc_attack"]={3787.14,1,99276.8},
    ["won_mission"]={4862.41,1,99478.5},
    ["trigger_1"]={4132.63,1,99193},
    ["base_fail"]={1982.09,1,97388.4},
    ["north_path"]={2021.14,1,97325.1},
    ["east_path"]={2046.41,1,97327.6},
    ["west_path"]={1980.88,1,97337.3},
    ["nav_base"]={1997.68,1,97466.7},
    ["west_back"]={617.565,1,101369},
    ["north_back"]={3076.62,1,101337},
    ["east_back"]={4725.56,1,100753},
    ["apc_attack_2"]={4980.31,1,98582.6},
    ["apc_attack_2_path"]={4965.48,1,98599.6},
    ["mine_path"]={3720.56,1,98474.5},
}
F.FAR = 50000
local CRAFT = {svtank=true,svfigh=true,svhraz=true,svapcr=true,svapcq=true,apcamr=true,cvmufa=true,cvslfa=true,cvscav=true,cvtnk=true,cvminea=true,cvartl=true,avtank=true}
local function vec(t) return {x = t[1], y = t[2], z = t[3]} end
local function newObject(handle, odf, team, pos, craft)
    W.objects[handle] = {alive = true, odf = odf, team = team, health = 1, pos = vec(pos or {F.FAR, 6, F.FAR}),
        craft = craft or CRAFT[odf] or false, hp = 0, ammo = 0}
    if not F.LABELS[handle] then W.objects[handle].hp, W.objects[handle].ammo = 1000, 1000 end
    local o = W.objects[handle]
    if F.LABELS[handle] then o.label = handle end
    return o
end

function F.reset()
    W = {now = 0, objects = {}, peers = {}, nextObject = 0, missing = {}, audioBusy = false, busy = {}, net = false,
        cancel = false, cameraDone = {}, timer = nil}
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
-- options: weather = { module = fn(peer, record), sites = table }: Europa director stand-ins (absent by default)
function F.makePeer(id, team, network, options)
    options = options or {}
    local p = {id = id, team = team, net = network, hosting = team == 1, calls = {}, player = "player" .. id,
        camera = 0}
    W.peers[id] = p
    W.net = W.net or network
    newObject(p.player, options.vehicle or "avtank", team, {4821.64 - 24.97 * (team - 1), 2.4, 99543.6 + 1.05 * (team - 1)}, true)
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
    e.GetNearestVehicle = function(from, point)
        assert(point == 1, "native path point must remain 1")
        local pos = F.posOf(from)
        local best, bestD
        for h, o in pairs(W.objects) do
            if o.alive and o.craft and not (o.label ~= nil and W.objects[o.label] == o and h ~= o.label) then
                local d = math.sqrt((pos.x - o.pos.x) ^ 2 + (pos.z - o.pos.z) ^ 2)
                if bestD == nil or d < bestD or (d == bestD and tostring(h) < tostring(best)) then best, bestD = h, d end
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
    e.IsAudioMessageDone = function(m) return not (W.audioBusy or W.busy[m]) end
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
            -- options.nilAuthoredHandles: Redux without the OpenShim label-id hooks sends a map-authored handle as
            -- nil, which the host cannot resolve. By default the fixed behaviour: the label travels as the id.
            if options.nilAuthoredHandles and type(args[index]) == "string" and F.LABELS[args[index]] then args[index] = false end
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
    for _, name in ipairs({"Retreat", "Goto", "Attack", "Defend2", "Stop", "SetPerceivedTeam", "MakeExplosion", "Patrol", "SetPilotClass", "SetAIControl", "SetObjectiveName",
        "SetObjectiveOn", "SetObjectiveOff", "SetUserTarget", "ClearObjectives", "AddObjective", "UpdateObjective", "Ally",
        "UnAlly", "DisplayMessage", "FailMission", "SucceedMission", "SetScrap", "AddScrap", "SetPilot", "AddPilot",
        "StartEarthquake", "UpdateEarthQuake", "StopEarthquake"}) do
        local n = name
        e[n] = function(...)
            if n == "SetObjectiveOn" or n == "SetObjectiveName" or n == "SetUserTarget" or n == "Attack" or n == "Goto"
                or n == "Retreat" or n == "Patrol" or n == "SetPilotClass" or n == "Defend2" or n == "Stop" or n == "SetPerceivedTeam" then
                assert(e.IsValid((...)), n .. " used a not-yet-valid handle")
            end
            record(n, ...)
        end
    end
    -- Cloak state, health and deployment: the mission reads them back.
    for _, spec in ipairs({{"Cloak", true}, {"SetCloaked", true}, {"Decloak", false}}) do
        e[spec[1]] = function(h)
            assert(e.IsValid(h), spec[1] .. " on an invalid object")
            W.objects[h].cloaked = spec[2]
            record(spec[1], h)
        end
    end
    e.IsCloaked = function(h) assert(e.IsValid(h)); return W.objects[h].cloaked == true end
    e.IsDeployed = function(h) assert(e.IsValid(h)); return W.objects[h].deployed == true end
    e.GetHealth = function(h) assert(h ~= nil, "GetHealth on nil"); return W.objects[h] and W.objects[h].alive and 1 or 0 end
    -- Nearest craft of a team to a path point; teams 1-4 are humans' side, the answer is a handle or nil.
    e.GetNearestUnitOnTeam = function(path, point, team)
        assert(W.pathPos[path] and point == 0, "nearest overload")
        local best, bestD
        local pos = W.pathPos[path]
        for k, o in pairs(W.objects) do
            if o.alive and o.craft and o.team == team and (o.label == nil or k == o.label) then
                local d = math.sqrt((pos.x - o.pos.x) ^ 2 + (pos.z - o.pos.z) ^ 2)
                if bestD == nil or d < bestD or (d == bestD and tostring(k) < tostring(best)) then best, bestD = k, d end
            end
        end
        return best
    end
    e.StartCockpitTimer = function(time, warn, alert)
        W.timer = {start = W.now, duration = time}
        record("StartCockpitTimer", time, warn, alert)
    end
    e.GetCockpitTimer = function()
        -- The real map runs MultSTMission, which restarts the cockpit timer upward every frame (live 2026-10-19, run
        -- misn18-win-1p-a: the reading equals the mission clock whatever StartCockpitTimer asked for). W.timerUp
        -- reproduces that; by default the mock counts down so the faithful body can be compared offline.
        if W.timerUp or W.timer == nil then return math.floor(W.now) end
        return math.max(0, W.timer.start + W.timer.duration - W.now)
    end
    e.StopCockpitTimer = function() record("StopCockpitTimer"); W.timer = nil end
    e.GetScrap = function() return W.scrap or 0 end
    e.GetMaxScrap = function() return W.capacity or 30 end
    e.GetCurHealth = function(h) assert(e.IsValid(h), "GetCurHealth on an invalid object"); return W.objects[h].hp end
    e.GetCurAmmo = function(h) assert(e.IsValid(h), "GetCurAmmo on an invalid object"); return W.objects[h].ammo end
    e.IsAliveAndPilot = function(h) return e.IsValid(h) and W.objects[h].pilot == true end
    e.GetCurrentCommand = function(h) return W.objects[h] and W.objects[h].command or 0 end
    e.GetLastEnemyShot = function() return 0 end
    e.GetWhoShotMe = function() return nil end
    e.Damage = function(h,amount) assert(e.IsValid(h));record("Damage",h,amount);W.objects[h].alive=false end
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
    -- options.weather = { module = function(peer, record), sites = table|nil }: Europa director stand-ins; absent by default.
    if options.weather then
        if options.weather.module then modules.CREuropaWeather = options.weather.module(p, record) end
        if options.weather.sites then modules.CRGanymedeSitesCH03 = options.weather.sites end
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
    setfenv(assert(loadfile(options.script or "Scripts/chmisn03cr.lua")), e)()
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
-- A human climbs into (or out of) a map howitzer: the player handle is the howitzer, which then belongs to the
-- human's team (a neutral craft takes the team of the pilot who enters it).
function F.board(peer, label)
    peer.player = label
    W.objects[label].team = peer.team
end
function F.unboard(peer) peer.player = "player" .. peer.id end
-- Repair and rearm a howitzer (the body's ready test is absolute health and ammo above 400).
function F.rearm(label, hp, ammo) W.objects[label].hp, W.objects[label].ammo = hp or 1000, ammo or 1000 end

return F
