-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Shared mock world for the chmisn05 suites (Test-Chmisn05Coop.lua, Test-Chmisn05Presentation.lua). Each peer runs
-- the complete co-op script in its own Lua 5.1 environment over the real CRCoop registry and the E/A + C
-- presentation transport. The engine, AI and combat are mocks: they verify script decisions, not Redux
-- native map loading, pathfinding, Lua wire serialization or EXU hooks. Labels and paths are the real
-- co-op map positions (Test-Chmisn05CoopContract.py checks the names against the map).
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local F = {}
local W
-- The engine basename limit applies to string literals; the script name is split like the other suites do.
F.SCRIPT = "Scripts/ch05cr.lua"
F.FAITHFUL = "Scripts/ch" .. "05.lua"

F.LABELS = {
    ["player"] = {odf="cvscav",team=1,pos={3862.63,129.8,100900},craft=true},
    ["silo"] = {odf="cbsilo",team=1,pos={3872.71,129,100928},craft=false},
    ["recycler"] = {odf="cvrecy",team=1,pos={4058.05,207,99204},craft=true},
    ["eggeizr112_geyser"] = {odf="eggeizr1",team=0,pos={4025.05,205.5,99081.6},craft=false},
    ["eggeizr113_geyser"] = {odf="eggeizr1",team=0,pos={4142.81,205.5,99141.7},craft=false},
    ["eggeizr114_geyser"] = {odf="eggeizr1",team=0,pos={4049.4,205.5,99217.2},craft=false},
    ["svturr5_turrettank"] = {odf="svturr",team=5,pos={639.443,133.177,99653.4},craft=true},
    ["abtowe5_turret"] = {odf="cbtowe",team=1,pos={3982.22,205.5,99230.9},craft=false},
    ["npscr36_scrap"] = {odf="npscr3",team=0,pos={3000,100,99900},craft=false},
    ["npscr16_scrap"] = {odf="npscr1",team=0,pos={3100,100,99900},craft=false},
    ["coop_spawn1"] = {odf="pspwn_1",team=1,pos={3862.63,129.8,100900},craft=false},
    ["coop_spawn2"] = {odf="pspwn_1",team=2,pos={3851.36,129.8,100922},craft=false},
    ["coop_spawn3"] = {odf="pspwn_1",team=3,pos={3840.09,129.8,100945},craft=false},
    ["coop_spawn4"] = {odf="pspwn_1",team=4,pos={3828.81,129.8,100967}, craft=false},
}
-- Every path the script names (first and last point of the long ones).
F.PATH_POINTS = {
    ["edge_path"]={{726.667,10,101540},{4713.33,10,98013.3}},
    ["outer_limits"]={{620,10,101600},{620,10,101600}},
    ["scout_1"]={{3713.66,10,98975.8}},
    ["scout_path"]={{3688.47,10,98996.4},{2404.67,10,100677}},
    ["scout_2"]={{3735.2,10,98961.5}},
    ["trigger_1"]={{2404.34,10,100678}},
    ["convoy"]={{3245.86,10,98536.6}},
    ["convoy_path"]={{3239.8,10,98628.3},{4046.46,10,99121.6}},
    ["haul_scout"]={{2315.49,10,100671}},
    ["enemy_haul"]={{2283.98,10,100693}},
    ["haul_defend"]={{2265.65,10,100702}},
    ["haul_path"]={{2257.87,10,100662},{668.963,10,99666.3}},
    ["day_1"]={{3171.4,10,98815.8}},
    ["day_2"]={{3366.86,10,98853}},
    ["day_3"]={{3558.92,10,99186.7}},
    ["day_4"]={{4064.94,10,98652.9}},
    ["day_5"]={{4173.31,10,99388.8}},
    ["day_6"]={{4202.04,10,98857.3}},
    ["day_7"]={{4007.96,10,99108.9}},
    ["day_8"]={{4045.71,10,99090}},
    ["artl_1"]={{2211.92,10,99049.2}},
    ["artl_2"]={{2211.09,10,99033.4}},
    ["artl_defend"]={{2235.98,10,99043.8}},
    ["wave_1"]={{3055.06,10,99216}},
    ["wave_2"]={{3860.89,10,99702.1}},
    ["wave_3"]={{3986.58,10,99011.8}},
    ["wave_4"]={{4008.12,10,98577.2}},
    ["wave_5"]={{3706.59,10,98639}},
    ["wave_6"]={{3245.86,10,99467.3}},
    ["wave_7"]={{2878.21,10,99048.5}},
    ["annoy_1"]={{3033.75,10,99387.1}},
    ["trigger_2"]={{819.156,10,99729.7}},
    ["nav_1"]={{2465.49,10,100691}},
    ["haul_cam"]={{2342.16,10,100714}},
    ["base_1"]={{4080,10,99166.7}},
    ["wave_1_path"]={{3133.33,10,99193.3},{4040.44,10,99167}},
    ["wave_2_path"]={{3860.89,10,99669.8},{4054.81,10,99141.9}},
    ["wave_4_path"]={{3972.21,10,98602.4},{4058.4,10,99126.7}},
    ["wave_5_path"]={{3725.21,10,98708.8},{4069.59,10,99155.5}},
    ["wave_6_path"]={{3287.75,10,99448.7},{4060.28,10,99169.5}},
    ["wave_7_path"]={{2943.37,10,99067.1},{4060.28,10,99150.9}},
    ["aerial_1"]={{4036.1,10,99150.7}},
    ["annoy_path_1"]={{3078.66,10,99366.4},{4049.55,10,99134.9}},
    ["annoy_path_2"]={{3082.12,10,99397.5},{4028.82,10,99190.2}},
}
F.PATHS = {}
for name, points in pairs(F.PATH_POINTS) do F.PATHS[name] = points[1] end
-- Map-authored objects a guest can reach by label on every peer.
F.SHARED = {player = true, silo = true, recycler = true}
F.FAR = 50000
local CRAFT = {cvscav=true,cvtnk=true,cvfighh=true,cvfigh=true,cvrecy=true,cvmuf=true,cvcnst=true,svhaul=true,svfigh=true,
    svwalk=true,svhraz=true,svtank=true,svltnk=true,svrckt=true,svapc=true,svartl=true,svturr=true,sssold=true,ssuser=true,
    apcamr=false}
local function vec(t) return {x = t[1], y = t[2], z = t[3]} end
local function newObject(handle, odf, team, pos, craft)
    W.objects[handle] = {alive = true, odf = odf, team = team, health = 1, pos = vec(pos or {F.FAR, 6, F.FAR}),
        craft = craft or CRAFT[odf] or false}
    local o = W.objects[handle]
    o.key = handle
    if F.LABELS[handle] then o.label = handle end
    return o
end

function F.reset()
    W = {now = 0, objects = {}, peers = {}, nextObject = 0, missing = {}, audioBusy = false, net = false,
        cancel = false, random = 0, cameraDone = {}, nilAudio = false, scrap = {}, tug = {}}
    W.pathPos = {}
    for name, p in pairs(F.PATHS) do W.pathPos[name] = vec(p) end
    -- Authored objects exist from the start (AllObjects sees them whether or not the script asked for them).
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
function F.perceived(h) return W.objects[h] and W.objects[h].perceived end
function F.kill(h) W.objects[h].alive = false; W.objects[h].health = 0 end
function F.alive(h) return W.objects[h] ~= nil and W.objects[h].alive end
function F.team(h) return W.objects[h] and W.objects[h].team end
function F.odf(h) return W.objects[h] and W.objects[h].odf end
function F.setScrap(team, n) W.scrap[team] = n end
-- The neutral scout has taken the tug in tow (the engine would do this after the Pickup order).
function F.hook(scout, tug) W.tug[scout] = tug end
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
-- options: weather = { module = fn(peer, record), sites = table }: Elysium stand-ins (absent by default);
-- faithful = true runs options.script (the DLL port) without the CR layer.
function F.makePeer(id, team, network, options)
    options = options or {}
    local p = {id = id, team = team, net = network, hosting = team == 1, calls = {}, player = "player" .. id,
        camera = 0}
    W.peers[id] = p
    W.net = W.net or network
    newObject(p.player, options.vehicle or "cvscav", team, {3862.63 - 11.27 * (team - 1), 129.8, 100900 + 22.4 * (team - 1)}, true)
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
    e.GetClassSig = function(h) return W.objects[h] and (W.objects[h].sig or W.objects[h].odf) end
    e.GetClassLabel = function(h)
        local o = W.objects[h]
        if o and o.odf:sub(1, 5) == "npscr" then return "scrap" end
        return o and "craft" or ""
    end
    e.GetPosition = function(h)
        local pos = F.posOf(h)
        return pos and {x = pos.x, y = pos.y, z = pos.z} or {x = 0, y = 0, z = 0}
    end
    e.SetVector = function(x, y, z) return {x = x, y = y, z = z} end
    e.IsCraft = function(h) return W.objects[h] ~= nil and W.objects[h].craft == true end
    e.StopCockpitTimer = function() record("StopCockpitTimer") end
    e.HideCockpitTimer = function() record("HideCockpitTimer") end
    e.GetPathPointCount = function(name)
        if W.missingPaths and W.missingPaths[name] then return 0 end
        return F.PATH_POINTS[name] and #F.PATH_POINTS[name] or 0
    end
    -- GetDistance(h, to) and the path-point form GetDistance(h, path, index) (zero based).
    e.GetDistance = function(a, b, index)
        -- The faithful body asks about removed handles; the real engine's answer is unknown, so the faithful run
        -- gets "far" and the CR run must never reach the native with an invalid origin.
        if options.faithful and not e.IsValid(a) then return 1e9 end
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
    e.AllObjects = function()
        local list = {}
        for key, o in pairs(W.objects) do if o.alive and o.key == key then list[#list + 1] = key end end
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
        assert(e.IsValid(h), "RemoveObject used a not-yet-valid handle")
        record("RemoveObject", h)
        if W.objects[h] then W.objects[h].alive = false; W.objects[h].health = 0 end
    end
    e.RemovePilot = function(h)
        assert(e.IsValid(h), "RemovePilot used a not-yet-valid handle")
        record("RemovePilot", h)
    end
    e.GetHealth = function(h) return W.objects[h] and W.objects[h].alive and W.objects[h].health or 0 end
    e.GetTug = function(h)
        if options.faithful and not e.IsValid(h) then return nil end
        assert(e.IsValid(h), "GetTug used a not-yet-valid handle")
        return W.tug[h]
    end
    e.Pickup = function(tug, cargo, priority)
        assert(e.IsValid(tug) and e.IsValid(cargo), "Pickup used a not-yet-valid handle")
        record("Pickup", tug, cargo, priority)
    end
    e.SetCommand = function(h, command, priority, target)
        assert(e.IsValid(h) and e.IsValid(target), "SetCommand used a not-yet-valid handle")
        record("SetCommand", h, command, priority, target)
    end
    e.AiCommand = {NONE=0, GO=3, ATTACK=4, STOP=2, FORMATION=11, DEFEND=16}
    e.GetCurrentCommand = function() return 0 end
    e.SetScrap = function(team, amount) W.scrap[team] = amount; record("SetScrap", team, amount) end
    e.GetScrap = function(team) return W.scrap[team] or 0 end
    -- W.audioBusy holds every line; W.busyFile holds one line ("ch05003.wav") while the others finish.
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
    -- W.cancel = true: every peer presses skip; W.cancel = { [id] = true }: only those peers do.
    e.CameraCancelled = function()
        if type(W.cancel) == "table" then return W.cancel[id] == true end
        return W.cancel
    end
    e.AudioMessage = function(file) record("AudioMessage", file); if W.nilAudio then return nil end return "audio:" .. file end
    -- The disguise: the perceived team of an object, as the engine would hold it.
    e.SetPerceivedTeam = function(h, team)
        assert(e.IsValid(h), "SetPerceivedTeam used a not-yet-valid handle")
        W.objects[h].perceived = team
        record("SetPerceivedTeam", h, team)
    end
    e.SetUserTarget = function(h)
        assert(e.IsValid(h), "SetUserTarget used a not-yet-valid handle")
        record("SetUserTarget", h)
    end
    e.Send = function(to, kind, ...)
        record("Send", kind)
        local args = {...}
        for index = 1, select("#", ...) do
            -- A map-authored handle arrives as an invalid handle on a guest.
            if type(args[index]) == "string" and F.LABELS[args[index]] and not F.SHARED[args[index]] then args[index] = false end
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
        if lo == nil then return 0.5 end
        return lo + (W.random % (hi - lo + 1))
    end}, {__index = math})
    -- Orders: every handle they name must already be a real object (a ticket reaching a native is a bug).
    local checked = {Follow = true, Attack = true, Defend2 = true}
    for _, name in ipairs({"Defend2", "Follow", "Defend", "Retreat", "Stop", "Goto", "Attack", "Hunt", "SetIndependence",
        "SetCloaked", "SetAIP", "SetAIControl", "SetObjectiveName", "SetName", "SetObjectiveOn", "SetObjectiveOff",
        "ClearObjectives", "AddObjective", "UpdateObjective", "Ally", "UnAlly", "DisplayMessage", "FailMission",
        "SucceedMission", "AddScrap", "SetPilot", "AddPilot"}) do
        local n = name
        e[n] = function(...)
            if n == "SetObjectiveOn" or n == "SetObjectiveName" or n == "SetName" or n == "SetIndependence" or n == "Follow"
                or n == "Attack" or n == "Defend" or n == "Defend2" or n == "Stop" or n == "Goto" or n == "Retreat"
                or n == "Hunt" or n == "SetCloaked" then
                assert(e.IsValid((...)), n .. " used a not-yet-valid handle")
            end
            if checked[n] then
                local target = select(2, ...)
                assert(e.IsValid(target), n .. " named a not-yet-valid target")
            end
            record(n, ...)
        end
    end
    local function noop() end
    local modules = {
        RequireFix = {Initialize = noop},
        exu = {GetMyNetID = function() return id end, DisableStartingRecycler = function() record("DisableStartingRecycler") end,
            SetLives = function(n) record("SetLives", n) end},
        ScriptSubtitles = {
            Play = function(file) record("Play", file); if W.nilAudio then return nil end return "audio:" .. file end,
            Queue = function(file) record("Queue", file); return "audio:" .. file end,
            Stop = function() record("Stop") end, Update = noop, Initialize = noop},
        CRWire = assert(loadfile("Scripts/CRWire.lua"))(),
        Environment = {Init=function(o) record("EnvironmentInit", o) end,
            BindWeatherSensors=function(name) record("WeatherSensors",name) end,
            Update=noop,OnObjectCreated=noop,InvalidateRenderer=noop},
        PersistentConfig = {Initialize=function() record("PdaInitialize") end,
            UpdateInputs=function() record("PdaUpdate") end,UpdateHeadlights=noop},
    }
    -- options.weather = { module = fn|nil, sites = table|nil }: Elysium stand-ins; absent by default.
    if options.weather then
        if options.weather.module then modules.CRElysiumWeather = options.weather.module(p, record) end
        if options.weather.sites then modules.CRElysiumSitesCH05 = options.weather.sites end
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
