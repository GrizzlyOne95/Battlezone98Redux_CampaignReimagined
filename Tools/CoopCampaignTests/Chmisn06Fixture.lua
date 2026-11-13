-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Shared mock world for the chmisn06 suite (Test-Chmisn06Coop.lua). Each peer runs
-- the complete Scripts/ch06cr.lua in its own Lua 5.1 environment over the real CRCoop registry and the E/A + C
-- presentation transport. The engine, AI and combat are mocks: they verify script decisions, not Redux
-- native map loading, pathfinding, Lua wire serialization or EXU hooks. Labels and paths are the real
-- Missions/ch06cr.bzn positions (Test-Chmisn06CoopContract.py checks the names against the map).
local PeerTransport = dofile("Tools/RuntimeTests/BZRPeerTransportSim.lua")
local F = {}
local W

F.LABELS = {
    ["player0_wingman"] = {odf="cvtnk",team=1,pos={2970.82,129.368,99389.7},craft=true},
    ["avrecy2_recycler"] = {odf="cvrecya",team=1,pos={2961.96,129.9,99450.2},craft=true},
    ["avmuf2_factory"] = {odf="cvmufc",team=1,pos={3015.21,129.9,99419.7},craft=true},
    ["avslf2_armory"] = {odf="cvslf",team=1,pos={2902.49,132.72,99406.5},craft=false},
    ["absilo2_scrapsilo"] = {odf="cbsilo",team=1,pos={3119.89,128.4,99368.7},craft=false},
    ["absilo3_scrapsilo"] = {odf="cbsilo",team=1,pos={3061.28,128.4,99470.5},craft=false},
    ["psu_1"] = {odf="sbtowed",team=5,pos={558.499,137.4,99339.8},craft=false},
    ["psu_2"] = {odf="sbtoweb",team=5,pos={476.832,137.4,99342.3},craft=false},
    ["psu_3"] = {odf="sbtowed",team=5,pos={478.499,137.4,99250.6},craft=false},
    ["psu_4"] = {odf="sbtoweb",team=5,pos={559.332,137.4,99250.6},craft=false},
    ["svrecy0_recycler"] = {odf="svrecy",team=5,pos={500.904,115.5,99407.6},craft=true},
    ["svmuf1_factory"] = {odf="svmuf",team=5,pos={424.348,117.887,99273.4},craft=true},
    ["svturr0_turrettank"] = {odf="svturr",team=5,pos={534.988,111.415,99316.1},craft=true},
    ["sbcomm4_commtower"] = {odf="sbcomm",team=5,pos={646.996,116.028,99323.1},craft=false},
    ["stolen"] = {odf="cvmuf",team=5,pos={567.533,117.9,99187.9},craft=true},
    ["coop_spawn1"] = {odf="pspwn_1",team=1,pos={2970.82,129.368,99389.7},craft=false},
    ["coop_spawn2"] = {odf="pspwn_1",team=2,pos={2945.82,129.368,99390.1},craft=false},
    ["coop_spawn3"] = {odf="pspwn_1",team=3,pos={2920.83,129.368,99390.5},craft=false},
    ["coop_spawn4"] = {odf="pspwn_1",team=4,pos={2895.83,129.368,99391},craft=false},
}
-- Labels the map gives to several objects: handle -> spec (the handle is not the label).
F.DUPES = {
    ["sw_patrol1"] = {label="sw_patrol",odf="cvfigh",team=1,pos={1132.71,100.147,97827.1},craft=true},
    ["sw_patrol2"] = {label="sw_patrol",odf="cvfigh",team=1,pos={1179.97,99.4065,97830.2},craft=true},
    ["sw_patrol3"] = {label="sw_patrol",odf="cvfigh",team=1,pos={1201.43,98.6743,97856},craft=true},
    ["nw_patrol1"] = {label="nw_patrol",odf="cvfigh",team=1,pos={727.426,95.5798,101731},craft=true},
    ["nw_patrol2"] = {label="nw_patrol",odf="cvfigh",team=1,pos={758.896,93.8998,101745},craft=true},
    ["nw_patrol3"] = {label="nw_patrol",odf="cvfigh",team=1,pos={805.562,94.8885,101739},craft=true},
    ["ld_power1"] = {label="ld_power",odf="abspowa",team=5,pos={522.983,109.9,99289.5},craft=false,perceived=1},
    ["ld_power2"] = {label="ld_power",odf="abspowa",team=5,pos={522.983,109.9,99304.5},craft=false,perceived=1},
}
F.PATHS = {
    ["ran_1"]={4026.38,10,100663}, ["ran_2"]={4284.05,10,98715.5}, ["ran_3"]={1446.32,10,99491.9},
    ["ran_1_path"]={4002.95,10,100630}, ["ran_2_path"]={4263.97,10,98735.6}, ["ran_3_path"]={1489.83,10,99485.2},
    ["ran_1_trigger"]={3084.05,10,99561.2}, ["ran_2_trigger"]={3119.05,10,99418.7}, ["ran_3_trigger"]={2905.72,10,99483.7},
    ["annoy_1"]={467.677,10,99386.6}, ["annoy_1_path"]={448.115,10,99425.7},
    ["activate_1"]={1220.11,10,98821}, ["activate_2"]={3000.27,10,99392.2},
    ["nav_1"]={1504,10,98773.3},
    ["sw_path"]={1177.48,10,97876.4}, ["nw_path"]={764.143,10,101702},
    ["sw_trigger"]={3025.22,10,99256.9}, ["nw_trigger"]={2929.72,10,99452.2},
    ["alien_1"]={4309.33,10,101931},
}
F.FAR = 50000
local CRAFT = {cvfigh=true,cvltnk=true,cvtnk=true,cvhraz=true,cvwalk=true,cvartl=true,cspilo=true,svfigh=true,svltnk=true,svtank=true,svhraz=true,avtank=true}
local function vec(t) return {x = t[1], y = t[2], z = t[3]} end
local function newObject(handle, odf, team, pos, craft)
    W.objects[handle] = {alive = true, odf = odf, team = team, health = 1, pos = vec(pos or {F.FAR, 6, F.FAR}),
        craft = craft or CRAFT[odf] or false}
    local o = W.objects[handle]
    if F.LABELS[handle] then o.label = handle end
    if F.DUPES[handle] then o.label = F.DUPES[handle].label; o.perceived = F.DUPES[handle].perceived end
    return o
end

function F.reset()
    W = {now = 0, objects = {}, peers = {}, nextObject = 0, missing = {}, audioBusy = false, net = false,
        cancel = false, random = 1, route = 1, cavalry = 1, cameraDone = {}, timer = nil}
    W.pathPos = {}
    for name, p in pairs(F.PATHS) do W.pathPos[name] = vec(p) end
    -- Authored objects exist from the start (AllCraft sees them whether or not the script asked for them).
    for label, spec in pairs(F.LABELS) do newObject(label, spec.odf, spec.team, spec.pos, spec.craft) end
    for handle, spec in pairs(F.DUPES) do newObject(handle, spec.odf, spec.team, spec.pos, spec.craft) end
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
-- options: weather = { module = fn(peer, record), sites = table }: Elysium stand-ins (absent by default)
function F.makePeer(id, team, network, options)
    options = options or {}
    local p = {id = id, team = team, net = network, hosting = team == 1, calls = {}, player = "player" .. id,
        camera = 0}
    W.peers[id] = p
    W.net = W.net or network
    newObject(p.player, options.vehicle or "avtank", team, {2970.82 - 25 * (team - 1), 129.4, 99389.7 + 0.4 * (team - 1)}, true)
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
    e.IsAudioMessageDone = function() return not W.audioBusy end
    e.SetCloaked = function(h)
        assert(e.IsValid(h), "SetCloaked on an invalid handle")
        W.objects[h].cloaked = true
        record("SetCloaked", h)
    end
    e.IsTouching = function(a, b)
        assert(e.IsValid(a) and e.IsValid(b), "IsTouching on an invalid handle")
        local pa, pb = F.posOf(a), F.posOf(b)
        return math.sqrt((pa.x - pb.x) ^ 2 + (pa.z - pb.z) ^ 2) < 30
    end
    e.PortalIn = function(h)
        assert(e.IsValid(h), "PortalIn on an invalid handle")
        record("PortalIn", h)
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
    e.AudioMessage = function(file) record("AudioMessage", file); if W.audioNil then return nil end return "audio:" .. file end
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
    -- random(3) is the body's ran_N choice (W.ran, 1..3, default 1 = ran_1); every other draw rotates so each
    -- of the four raider kinds and each base building comes up.
    e.math = setmetatable({random = function(lo, hi)
        record("random", lo, hi)
        local n = hi or lo
        if n == 3 then return W.ran or 1 end
        W.draw = (W.draw or 0) + 1
        return (W.draw - 1) % n + 1
    end}, {__index = math})
    for _, name in ipairs({"Defend2", "Follow", "Defend", "Retreat", "Stop", "Goto", "Attack", "SetIndependence", "SetAIP",
        "SetAIControl", "SetObjectiveName", "SetObjectiveOn", "SetObjectiveOff", "ClearObjectives",
        "AddObjective", "UpdateObjective", "Ally", "UnAlly", "DisplayMessage", "FailMission", "SucceedMission",
        "SetScrap", "AddScrap", "SetPilot", "AddPilot", "SetPilotClass", "Patrol", "StartEarthquake", "UpdateEarthQuake", "StopEarthquake"}) do
        local n = name
        e[n] = function(...)
            if n == "SetObjectiveOn" or n == "SetObjectiveName" or n == "SetIndependence" or n == "Follow"
                or n == "Attack" or n == "Defend" or n == "Stop" or n == "Goto" or n == "Retreat" then
                assert(e.IsValid((...)), n .. " used a not-yet-valid handle")
            end
            record(n, ...)
        end
    end
    e.SetPerceivedTeam = function(h, t)
        assert(e.IsValid(h), "SetPerceivedTeam on an invalid object")
        record("SetPerceivedTeam", h, t)
        W.objects[h].perceived = t
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
    e.GetScrap = function(team) record("GetScrap", team); return (W.scrapOf and W.scrapOf[team]) or W.scrap or 0 end
    e.GetMaxScrap = function() return W.capacity or 30 end
    e.GetHealth = function(h) assert(e.IsValid(h), "GetHealth on an invalid handle"); return W.objects[h].health end
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
    -- options.weather = { module = fn(peer, record), sites = table|nil }: Elysium stand-ins; absent by default.
    if options.weather then
        if options.weather.module then modules.CRElysiumWeather = options.weather.module(p, record) end
        if options.weather.sites then modules.CRElysiumSitesCH06 = options.weather.sites end
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
    setfenv(assert(loadfile(options.script or "Scripts/ch06cr.lua")), e)()
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
