-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Shared mock world for the bdmisn04 suites (Test-Bdmisn04Coop.lua, Test-Bdmisn04Presentation.lua). Each peer runs
-- the complete Scripts/bd04cr.lua in its own Lua 5.1 environment over the real CRCoop registry and the E/A + C
-- presentation transport. The engine, AI and combat are mocks: they verify script decisions, not Redux
-- native map loading, pathfinding, Lua wire serialization or EXU hooks. Labels and paths are the real
-- Missions/bd04cr.bzn positions (Test-Bdmisn04CoopContract.py checks the names against the map).
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local F = {}
local W

F.LABELS = {
    ["silo"] = {odf="cbsiloa",team=5,pos={1008.49,13.5,101293},craft=false},
    ["portal"] = {odf="cbport",team=5,pos={1690.87,25.2,101184},craft=false},
    ["scav_1"] = {odf="cvscava",team=5,pos={2089.99,18.4,101282},craft=true},
    ["scav_2"] = {odf="cvscava",team=5,pos={2040.39,12.6,101251},craft=true},
    ["scav_3"] = {odf="cvscava",team=5,pos={2144.41,25.2,101340},craft=true},
    ["turret_1"] = {odf="cvturr",team=5,pos={1654.45,22.1,101354},craft=true},
    ["turret_2"] = {odf="cvturr",team=5,pos={1703.31,26.3,101237},craft=true},
    ["turret_3"] = {odf="cvturr",team=5,pos={1639.76,25.7,101202},craft=true},
    ["turret_4"] = {odf="cvturr",team=5,pos={1516.29,9.6,101586},craft=true},
    ["turret_5"] = {odf="cvturr",team=5,pos={1532.48,17.8,101775},craft=true},
    ["turret_6"] = {odf="cvturr",team=5,pos={1287.59,26.8,101660},craft=true},
    ["turret_7"] = {odf="cvturr",team=5,pos={1291.26,27.2,101702},craft=true},
    ["turret_8"] = {odf="cvturr",team=5,pos={1466.92,7.2,101644},craft=true},
    ["turret_9"] = {odf="cvturr",team=5,pos={1307.77,13.7,101496},craft=true},
    ["cvwalk0_walker"] = {odf="cvwalk",team=5,pos={1247.24,35.3,101688},craft=true},
    ["cvwalk1_walker"] = {odf="cvwalk",team=5,pos={1247.24,34.9,101706},craft=true},
    ["fragment"] = {odf="obdataa",team=0,pos={1646.99,21.6,101419},craft=false},
    ["hauler_1"] = {odf="cvhaula",team=5,pos={1598.27,24.6,101363},craft=true},
    ["cbcomm166_commtower"] = {odf="cbcomm",team=5,pos={1656.58,21.6,101381},craft=false},
    ["apcamr0_camerapod"] = {odf="apcamr",team=0,pos={1800.97,110.1,101485},craft=false},
    ["apcamr1_camerapod"] = {odf="apcamr",team=0,pos={1838.41,110.2,101382},craft=false},
    ["coop_spawn1"] = {odf="pspwn_1",team=1,pos={1850.14,108.9,101209},craft=false},
    ["coop_spawn2"] = {odf="pspwn_1",team=2,pos={1846.32,108.9,101184},craft=false},
    ["coop_spawn3"] = {odf="pspwn_1",team=3,pos={1842.5,108.9,101160},craft=false},
    ["coop_spawn4"] = {odf="pspwn_1",team=4,pos={1838.68,108.9,101135},craft=false},
}
F.PATHS = {
    ["edge_path"]={2350,10,100057},
    ["chinese_scout_x6_spawn_point"]={780,10,100367},
    ["proposed_end_area"]={2270,10,100133},
    ["bomber_wing_x5_spawn_point"]={700,10,102187},
    ["attack_1"]={1553.33,10,101390},
    ["attack_2"]={1983.33,10,100377},
    ["attack_3"]={1440,10,100857},
    ["camera_start_up"]={1854.95,10,101379},
    ["nav_1"]={1850.24,10,101316},
    ["nav_2"]={1849.57,10,101242},
    ["unit_path"]={1657.46,10,101229},
    ["camera_portal"]={1624.94,10,101269},
    ["pilot"]={1850.9,10,101358},
    ["pilot_path"]={1850.24,10,101348},
    ["portal_units"]={1672.46,10,101214},
    ["base_limit"]={1333.33,10,101810},
    ["rv_scout"]={606.667,10,101203},
    ["trigger_1"]={1261,10,101691},
    ["escort_units"]={603.333,10,101173},
    ["scav_path"]={2022.72,10,101314},
    ["walker_path"]={1251.83,10,101708},
    ["return_1"]={1313.33,10,100807},
    ["return_2"]={2026.67,10,100813},
    ["return_3"]={646.667,10,100877},
    ["return_4"]={1826.67,10,100400},
}
-- The real base_limit polygon (the whole Chinese base): IsInsideArea tests against it.
F.BASE_LIMIT = {{1333.33,101810},{1173.33,102010},{1206.67,102113},{1293.33,102157},{1406.67,102150},{1483.33,102060},
    {1550,101987},{1636.67,101930},{1683.33,101813},{1673.33,101663},{1736.67,101493},{1800,101363},{1796.67,101173},
    {1726.67,101080},{1530,101130},{1433.33,101153},{1363.33,101260},{1253.33,101297},{1180,101293},{1106.67,101247},
    {1013.33,101217},{900,101260},{973.333,101357},{1110,101447},{1213.33,101537},{1313.33,101587},{1330,101813}}
F.FAR = 50000
F.START = {1850.14, 108.9, 101209}
local CRAFT = {bvfigh=true,bvtank=true,bvhraza=true,cvfigh=true,cvfighg=true,cvtnk=true,aspilo=true,bsuser=true}
local function vec(t) return {x = t[1], y = t[2], z = t[3]} end
local function newObject(handle, odf, team, pos, craft)
    W.objects[handle] = {alive = true, odf = odf, team = team, health = 1, pos = vec(pos or {F.FAR, 6, F.FAR}),
        craft = craft or CRAFT[odf] or false, perceived = team}
    local o = W.objects[handle]
    if F.LABELS[handle] then o.label = handle end
    return o
end

function F.reset()
    W = {now = 0, objects = {}, peers = {}, nextObject = 0, missing = {}, audioBusy = false, net = false,
        cancel = false, cameraDone = {}, timer = nil, tug = {}, realTimer = false}
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
function F.perceived(h) return W.objects[h] and W.objects[h].perceived end
function F.hidden(h) return W.objects[h] and W.objects[h].hidden == true end
-- Cargo carried by a tug (GetTug(cargo) == tug).
function F.tug(cargo, tug) W.tug[cargo] = tug end
-- Point in the base_limit polygon.
function F.inBase(x, z)
    local inside, poly = false, F.BASE_LIMIT
    local j = #poly
    for i = 1, #poly do
        local xi, zi, xj, zj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
        if ((zi > z) ~= (zj > z)) and (x < (xj - xi) * (z - zi) / (zj - zi) + xi) then inside = not inside end
        j = i
    end
    return inside
end
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
-- options: faithful/script, vehicle (the human's start craft), weather = false (no weather modules).
function F.makePeer(id, team, network, options)
    options = options or {}
    local p = {id = id, team = team, net = network, hosting = team == 1, calls = {}, player = "player" .. id,
        camera = 0, info = {}, weatherCalls = {}}
    W.peers[id] = p
    newObject(p.player, options.vehicle or "bsuser", team,
        {F.START[1] - 3.8 * (team - 1), F.START[2], F.START[3] - 25 * (team - 1)}, true)
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
    e.IsPerson = function(h) return e.IsValid(h) and (W.objects[h].odf == "bsuser" or W.objects[h].odf == "aspilo") end
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
    e.GetHealth = function(h) assert(e.IsValid(h), "GetHealth on an invalid object"); return W.objects[h].health end
    e.SetCurHealth = function(h, v) record("SetCurHealth", h, v) end
    e.GetPathPointCount = function(name)
        if W.missingPaths and W.missingPaths[name] then return 0 end
        if name == "base_limit" then return #F.BASE_LIMIT end
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
    e.IsInsideArea = function(path, h)
        assert(path == "base_limit" and e.IsValid(h), "IsInsideArea asked about something else")
        local pos = F.posOf(h)
        return F.inBase(pos.x, pos.z)
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
    e.BuildObjectAtPortal = function(odf, objectTeam, portal)
        assert(e.IsValid(portal), "BuildObjectAtPortal at an invalid portal")
        W.nextObject = W.nextObject + 1
        local h = "portal" .. W.nextObject
        local pos = F.posOf(portal)
        newObject(h, odf, objectTeam, {pos.x, pos.y, pos.z})
        record("BuildObjectAtPortal", h, odf, objectTeam)
        for _, peer in pairs(W.peers) do if peer.env then peer.env.AddObject(h) end end
        return h
    end
    e.RemoveObject = function(h)
        record("RemoveObject", h)
        if W.objects[h] then W.objects[h].alive = false end
    end
    e.GetTug = function(h) assert(e.IsValid(h), "GetTug on an invalid object"); return W.tug[h] end
    e.IsInfo = function(odf) return p.info[odf] == true end
    e.Hide = function(h) assert(e.IsValid(h), "Hide on an invalid object"); record("Hide", h); W.objects[h].hidden = true end
    e.UnHide = function(h) assert(e.IsValid(h), "UnHide on an invalid object"); record("UnHide", h); W.objects[h].hidden = false end
    e.SetPerceivedTeam = function(h, t)
        assert(e.IsValid(h), "SetPerceivedTeam on an invalid object")
        record("SetPerceivedTeam", h, t)
        W.objects[h].perceived = t
    end
    e.PortalOut = function(h) assert(e.IsValid(h), "PortalOut on an invalid object"); record("PortalOut", h) end
    e.DeactivatePortal = function(h) assert(e.IsValid(h), "DeactivatePortal on an invalid object"); record("DeactivatePortal", h) end
    e.SetUserTarget = function(h) assert(e.IsValid(h), "SetUserTarget on an invalid object"); record("SetUserTarget", h) end
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
        record("Send", kind, ...)
        local args = {...}
        for index = 1, select("#", ...) do
            -- options.nilAuthoredHandles: Redux without the OpenShim label-id hooks sends a map-authored handle as
            -- nil, which a guest cannot resolve. By default the fixed behaviour: the label travels as the id.
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
    -- MultSTMission restarts the cockpit timer upward every frame (live 2026-10-19): a countdown can never be
    -- read back from the engine. W.realTimer = true answers like a stock countdown instead (the faithful port).
    e.StartCockpitTimer = function(time, warn, alert)
        W.timer = {start = W.now, duration = time}
        record("StartCockpitTimer", time, warn, alert)
    end
    e.StopCockpitTimer = function() W.timer = nil; record("StopCockpitTimer") end
    e.HideCockpitTimer = function() record("HideCockpitTimer") end
    e.GetCockpitTimer = function()
        if W.realTimer and W.timer then return math.max(0, W.timer.duration - (W.now - W.timer.start)) end
        return math.floor(W.now)
    end
    e.GetScrap = function() return W.scrap or 0 end
    e.GetMaxScrap = function() return W.capacity or 30 end
    e.GetCurHealth = function(h) return W.objects[h] and W.objects[h].health or 0 end
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
    -- The Ganymede director stand-in (CREuropaWeather): records the beats the mission asks for. The real generated
    -- site table is used, so the empty vent list is the real one. options.weather = false leaves both out.
    if options.weather ~= false then
        local level, w = 1, p.weatherCalls
        local function mark(name) return function(...) w[#w + 1] = {name, ...} end end
        modules.CREuropaWeather = {
            Seed = 7, Init = mark("Init"), Update = noop, ApplyNetEvent = function(op, ...) w[#w + 1] = {"net", op, ...} end,
            Shutdown = noop, Save = function() return {level = level} end, Load = noop, AnnounceState = noop,
            SetTargetLevel = function(n) level = n; w[#w + 1] = {"SetTargetLevel", n} end,
            GetTargetLevel = function() return level end,
            ReleaseForcedLevel = mark("ReleaseForcedLevel"), Quake = mark("Quake"), Surge = mark("Surge"),
            TriggerPlume = mark("TriggerPlume"), GetVentSites = function() return modules.CRGanymedeSitesBD04.vents or {} end,
        }
        modules.CRGanymedeSitesBD04 = assert(loadfile("Scripts/CRGanymedeSitesBD04.lua"))()
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
    setfenv(assert(loadfile(options.script or "Scripts/bd04cr.lua")), e)()
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
