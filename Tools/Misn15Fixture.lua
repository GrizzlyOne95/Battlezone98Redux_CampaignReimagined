-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Shared mock world for the misn15 suites (Test-Misn15.lua offline, Test-Misn15Coop.lua multi-peer,
-- Test-Misn15Presentation.lua). Each peer runs the complete Scripts/misn15.lua in its own Lua 5.1
-- environment over the real CRCoop registry and the E/A + C presentation transport. The engine, AI and
-- combat are mocks: they verify script decisions, not Redux native map loading, pathfinding, Lua wire
-- serialization or EXU hooks. Coordinates are the authored ones (Missions/misn15.bzn).
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local F = {}

local function P(x, z, y) return {x, y or 6, z} end
F.LABELS = {
    ["player0_hover"] = {odf="avhraz",team=1,pos={3268.50000,68.10000,98888.39844},craft=true},
    ["eggeizr10_geyser"] = {odf="eggeizr1",team=0,pos={2651.83008,66.60000,99004.60156},craft=false},
    ["eggeizr11_geyser"] = {odf="eggeizr1",team=0,pos={2530.78003,66.60000,98942.00000},craft=false},
    ["eggeizr12_geyser"] = {odf="eggeizr1",team=0,pos={3649.94995,66.60000,99054.70312},craft=false},
    ["eggeizr13_geyser"] = {odf="eggeizr1",team=0,pos={3558.12012,66.60000,98975.39844},craft=false},
    ["eggeizr14_geyser"] = {odf="eggeizr1",team=0,pos={3342.37988,75.60000,99768.89844},craft=false},
    ["eggeizr15_geyser"] = {odf="eggeizr1",team=0,pos={3745.94995,67.13010,98925.29688},craft=false},
    ["eggeizr16_geyser"] = {odf="eggeizr1",team=0,pos={3245.08008,75.60000,99847.79688},craft=false},
    ["eggeizr17_geyser"] = {odf="eggeizr1",team=0,pos={2785.94995,66.70000,99530.60156},craft=false},
    ["eggeizr18_geyser"] = {odf="eggeizr1",team=0,pos={2581.42993,66.60000,99526.39844},craft=false},
    ["eggeizr19_geyser"] = {odf="eggeizr1",team=0,pos={4058.98999,51.10000,100232.00000},craft=false},
    ["eggeizr110_geyser"] = {odf="eggeizr1",team=0,pos={4008.89990,51.10000,100107.00000},craft=false},
    ["avrecy0_recycler"] = {odf="avrecy",team=1,pos={3223.35010,68.27480,98909.50000},craft=true},
    ["apcamr3_camerapod"] = {odf="apcamr",team=1,pos={2610.63989,66.60000,98942.00000},craft=false},
    ["apcamr0_camerapod"] = {odf="apcamr",team=1,pos={3658.30005,66.93180,98946.20312},craft=false},
    ["apcamr2_camerapod"] = {odf="apcamr",team=1,pos={3235.43994,75.60000,99734.20312},craft=false},
    ["apcamr4_camerapod"] = {odf="apcamr",team=1,pos={2681.60010,71.00700,99580.60156},craft=false},
    ["apcamr1_camerapod"] = {odf="apcamr",team=1,pos={4017.25000,51.10000,100182.00000},craft=false},
    ["sfield14_scrapfield"] = {odf="sfield",team=0,pos={3096.20996,71.63230,99476.00000},craft=false},
    ["sfield14_scrapfield"] = {odf="sfield",team=0,pos={1813.32996,74.18960,99146.70312},craft=false},
    ["sfield14_scrapfield"] = {odf="sfield",team=0,pos={1814.81995,77.17460,99304.89844},craft=false},
    ["sfield14_scrapfield"] = {odf="sfield",team=0,pos={4352.00000,66.60000,99338.70312},craft=false},
    ["sfield14_scrapfield"] = {odf="sfield",team=0,pos={4330.08984,66.60000,99517.20312},craft=false},
    ["sfield14_scrapfield"] = {odf="sfield",team=0,pos={4277.91016,66.60000,99689.29688},craft=false},
    ["sfield14_scrapfield"] = {odf="sfield",team=0,pos={2211.19995,38.10000,100339.00000},craft=false},
    ["sfield14_scrapfield"] = {odf="sfield",team=0,pos={2220.80005,38.10000,100490.00000},craft=false},
    ["sfield14_scrapfield"] = {odf="sfield",team=0,pos={3040.00000,36.12020,100352.00000},craft=false},
    ["sfield14_scrapfield"] = {odf="sfield",team=0,pos={2064.69995,39.20290,100429.00000},craft=false},
    ["sfield14_scrapfield"] = {odf="sfield",team=0,pos={3262.61011,38.10000,100408.00000},craft=false},
    ["sfield14_scrapfield"] = {odf="sfield",team=0,pos={3691.40991,38.10000,100208.00000},craft=false},
    ["sfield0_scrapfield"] = {odf="sfield",team=0,pos={2116.39990,38.02800,100540.00000},craft=false},
    ["sfield0_scrapfield"] = {odf="sfield",team=0,pos={3004.39990,38.10000,100072.00000},craft=false},
    ["sfield0_scrapfield"] = {odf="sfield",team=0,pos={3766.39990,38.10000,100078.00000},craft=false},
    ["sfield0_scrapfield"] = {odf="sfield",team=0,pos={3097.60010,38.10000,100227.00000},craft=false},
    ["sfield0_scrapfield"] = {odf="sfield",team=0,pos={1814.40002,66.60000,99196.79688},craft=false},
    ["apcamr5_camerapod"] = {odf="apcamr",team=1,pos={3187.19995,66.60000,98960.00000},craft=false},
    ["svtank0_wingman"] = {odf="svtank",team=7,pos={2723.19995,67.50010,99520.00000},craft=true},
    ["svtank1_wingman"] = {odf="svtank",team=7,pos={2758.39990,67.48400,99488.00000},craft=true},
    ["svapc0_apc"] = {odf="svapc",team=7,pos={2796.80005,68.20000,99468.79688},craft=true},
    ["abhang0_repairdepot"] = {odf="abhang",team=1,pos={2509.61011,66.60000,99533.20312},craft=false},
    ["abmbld0_supplydepot"] = {odf="abmbld",team=1,pos={2583.34009,66.70000,99607.60156},craft=false},
    ["misn15b"] = {odf="abtowe",team=1,pos={2429.92993,66.60000,99564.89844},craft=false},
    ["sfield1_scrapfield"] = {odf="sfield",team=0,pos={3194.42993,67.60000,99380.89844},craft=false},
    ["sfield1_scrapfield"] = {odf="sfield",team=0,pos={3131.83008,33.98090,100341.00000},craft=false},
    ["sfield1_scrapfield"] = {odf="sfield",team=0,pos={2159.30005,39.99790,100416.00000},craft=false},
    ["sfield1_scrapfield"] = {odf="sfield",team=0,pos={1866.67004,69.54710,99264.00000},craft=false},
    ["ubtart0_i76building"] = {odf="ubtart",team=0,pos={3368.69995,75.60000,99913.00000},craft=false},
    ["sfield0_scrapfield"] = {odf="sfield",team=0,pos={3336.33008,66.60000,99551.20312},craft=false},
    ["avcnst0_constructionrig"] = {odf="avcnst",team=1,pos={3167.17993,67.60000,98937.29688},craft=true},
    ["apsand122_wpnpower"] = {odf="apsand",team=1,pos={3253.59009,66.60000,98882.20312},craft=false},
    ["coop_spawn1"] = {odf="pspwn_1",team=1,pos={3268.50000,68.10000,98888.39844},craft=false},
    ["coop_spawn2"] = {odf="pspwn_1",team=2,pos={3256.91992,68.10000,98866.20312},craft=false},
    ["coop_spawn3"] = {odf="pspwn_1",team=3,pos={3245.35010,68.10000,98844.10156},craft=false},
    ["coop_spawn4"] = {odf="pspwn_1",team=4,pos={3233.77002,68.10000,98821.89844},craft=false},
    ["cr15_nw_scav"] = {odf="avscav",team=7,pos={4055.37012,52.10000,100132.00000},craft=true},
    ["cr15_nw_apc"] = {odf="avapc",team=7,pos={4084.59009,52.10000,100165.00000},craft=true},
    ["cr15_nw_turret"] = {odf="avturr",team=7,pos={4101.29004,52.10000,100194.00000},craft=true},
    ["cr15_ne_scav1"] = {odf="avscav",team=7,pos={3279.03003,76.60000,99898.10156},craft=true},
    ["cr15_ne_scav2"] = {odf="avscav",team=7,pos={3220.59009,76.60000,99873.10156},craft=true},
    ["cr15_ne_artillery"] = {odf="avartl",team=7,pos={3203.89990,76.60000,99831.39844},craft=true},
}
F.PATHS = {
    ["launch1"] = {2741.33008,66.6,100800.00000},
    ["launch2"] = {3008.00000,66.6,100843.00000},
    ["launch3"] = {3168.00000,66.6,100811.00000},
    ["launch4"] = {4618.66992,66.6,99296.00000},
    ["launch6"] = {4516.00000,66.6,99679.60156},
    ["launch7"] = {1942.00000,66.6,99673.60156},
    ["launch8"] = {1972.00000,66.6,99517.60156},
    ["launch9"] = {1960.00000,66.6,99367.60156},
    ["alien1"] = {1994.30005,66.6,100652.00000},
    ["alien2"] = {3822.75000,66.6,100602.00000},
    ["tank_path"] = {2835.19995,66.6,99468.79688},
    ["scav3here"] = {4055.37012,66.6,100132.00000},
    ["mufhere"] = {4084.59009,66.6,100165.00000},
    ["turhere"] = {4101.29004,66.6,100194.00000},
    ["scav1here"] = {3279.03003,66.6,99898.10156},
    ["scav2here"] = {3220.59009,66.6,99873.10156},
    ["arthere"] = {3203.89990,66.6,99831.39844},
    ["rescue_cam1"] = {3996.37988,66.6,100086.00000},
    ["rescue_cam2"] = {3274.30005,66.6,99756.50000},
    ["border"] = {1621.32996,66.6,101024.00000},
    ["edge_path"] = {1568.00000,66.6,100789.00000},
    ["deny1"] = {2207.16992,66.6,100423.00000},
    ["deny2"] = {3096.20996,66.6,100268.00000},
    ["cr15_unused_path_23"] = {2610.09009,66.6,98942.89844},
    ["alien_path"] = {3217.53003,66.6,100423.00000},
    ["cr15_unused_path_25"] = {4672.00000,66.6,99445.29688},
}

local CRAFT = {avtank=true,avscav=true,avapc=true,avturr=true,avartl=true,svtank=true,svapc=true,hvsav=true,hvsat=true}
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
        cancel = false, random = 1}
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
    newObject(p.player, options.vehicle or "avtank", team, {2531.6 - 25 * (team - 1), 6, 99387.9}, true)
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
        for _, value in ipairs(args) do bytes = bytes + (type(value) == "string" and #value + 2 or 9) end
        assert(bytes < 244, "mission packet exceeds stock payload budget: " .. kind)
        for target in pairs(W.peers) do
            if target ~= id and (to == 0 or to == nil or target == to) then W.transport:Send(id, target, kind, args, false) end
        end
    end
    e.math = setmetatable({random = function(lo, hi)
        record("random", lo, hi)
        return math.max(lo, math.min(hi, W.random))
    end}, {__index = math})
    for _, name in ipairs({"Follow", "Defend", "Retreat", "Stop", "Goto", "Attack", "SetIndependence", "SetAIP",
        "SetAIControl", "SetObjectiveName", "SetObjectiveOn", "SetObjectiveOff", "ClearObjectives",
        "AddObjective", "UpdateObjective", "Ally", "UnAlly", "DisplayMessage", "FailMission", "SucceedMission",
        "SetScrap", "AddScrap", "SetPilot", "AddPilot"}) do
        local n = name
        e[n] = function(...)
            if n == "SetObjectiveOn" or n == "SetObjectiveName" or n == "SetIndependence" or n == "Follow"
                or n == "Attack" or n == "Defend" or n == "Stop" or n == "Goto" or n == "Retreat" then
                assert(e.IsValid((...)), n .. " used a not-yet-valid handle")
            end
            if n == "SetIndependence" then
                assert(W.objects[(...)].odf == "aspilo", "SetIndependence on a non-allowlisted object")
            end
            record(n, ...)
        end
    end
    e.GetScrap = function() return W.scrap or 0 end
    e.GetMaxScrap = function() return W.capacity or 30 end
    e.GetCurHealth = function(h) return W.objects[h] and W.objects[h].health or 0 end
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
        CRTitanWeather = options.titan,
        CRTitanSites15 = {},
        PersistentConfig = {Initialize=function() record("PdaInitialize") end,
            UpdateInputs=function() record("PdaUpdate") end,UpdateHeadlights=noop},
    }
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
    modules.CRMisn15 = setfenv(assert(loadfile("Scripts/CRMisn15.lua")),e)()
    setfenv(assert(loadfile("Scripts/misn15.lua")), e)()
    p.chunkCalls = #p.calls -- everything recorded so far ran at chunk load, before Start
    p.env, p.coop = e, modules.CRCoop
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
function F.host() for _, p in pairs(W.peers) do if p.team == 1 then return p end end end
function F.state(p) return p.env.Save() end

return F
