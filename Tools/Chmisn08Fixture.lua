-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Shared mock world for the chmisn08 suites (Test-Chmisn08Coop.lua, Test-Chmisn08Presentation.lua). Each peer runs
-- the complete Scripts/ch08cr.lua in its own Lua 5.1 environment over the real CRCoop registry and the E/A + C
-- presentation transport. The engine, AI and combat are mocks: they verify script decisions, not Redux
-- native map loading, pathfinding, Lua wire serialization or EXU hooks. Labels and paths are the real
-- Missions/ch08cr.bzn positions (Test-Chmisn08CoopContract.py checks the names against the map).
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local F = {}
local W

-- Every authored [GameObject] with a label, read from Missions/ch08cr.bzn.
F.LABELS = {
    ["player"] = {odf="cvtnk",team=1,pos={3225.51,165.8,97931.6},craft=true},
    ["west_1_1"] = {odf="cvtnkd",team=1,pos={2513.08,208.369,99296.2},craft=true},
    ["west_1_2"] = {odf="cvtnkd",team=1,pos={2511.28,211.34,99276.4},craft=true},
    ["west_1_3"] = {odf="cvtnkd",team=1,pos={2511.28,214.594,99254.7},craft=true},
    ["west_1_4"] = {odf="cvtnkd",team=1,pos={2513.08,217.85,99233.0},craft=true},
    ["east_1_1"] = {odf="cvtnkd",team=1,pos={2596.09,204.56,99301.6},craft=true},
    ["east_1_2"] = {odf="cvtnkd",team=1,pos={2601.5,208.085,99278.1},craft=true},
    ["east_1_3"] = {odf="cvtnkd",team=1,pos={2606.92,211.055,99258.3},craft=true},
    ["east_1_4"] = {odf="cvtnkd",team=1,pos={2614.13,213.69,99236.6},craft=true},
    ["nav"] = {odf="apcamr",team=1,pos={3187.85,165.0,97842.4},craft=false},
    ["howitzer_nw"] = {odf="svartla",team=5,pos={1811.11,384.0,101706.0},craft=true},
    ["howitzer_ne"] = {odf="svartla",team=5,pos={3259.2,384.0,101720.0},craft=true},
    ["west_power"] = {odf="sbspow",team=5,pos={2252.96,262.5,101506.0},craft=false},
    ["east_power"] = {odf="sbspow",team=5,pos={2817.02,262.5,101507.0},craft=false},
    ["west_comm"] = {odf="sbcomm",team=5,pos={2402.7,262.5,101475.0},craft=false},
    ["east_comm"] = {odf="sbcomm",team=5,pos={2658.66,262.5,101476.0},craft=false},
    ["west_bolt"] = {odf="boltmine",team=5,pos={2284.59,262.5,101425.0},craft=false},
    ["east_bolt"] = {odf="boltmine",team=5,pos={2782.92,262.5,101424.0},craft=false},
    ["west_mag_1"] = {odf="magpulla",team=5,pos={2263.33,262.05,101417.0},craft=false},
    ["west_mag_2"] = {odf="magpulla",team=5,pos={2305.0,257.55,101387.0},craft=false},
    ["west_mag_3"] = {odf="magpulla",team=5,pos={2262.5,257.4,101386.0},craft=false},
    ["west_mag_4"] = {odf="magpulla",team=5,pos={2304.17,262.05,101417.0},craft=false},
    ["east_mag_1"] = {odf="magpulla",team=5,pos={2767.5,261.3,101412.0},craft=false},
    ["east_mag_2"] = {odf="magpulla",team=5,pos={2803.33,261.45,101413.0},craft=false},
    ["east_mag_3"] = {odf="magpulla",team=5,pos={2768.33,256.05,101377.0},craft=false},
    ["east_mag_4"] = {odf="magpulla",team=5,pos={2804.17,255.6,101374.0},craft=false},
    ["walker_1"] = {odf="svwalk",team=5,pos={2533.53,10.3389,99987.3},craft=true},
    ["magpull_1"] = {odf="magpulla",team=5,pos={2516.99,12.6002,100074.0},craft=false},
    ["magpull_2"] = {odf="magpulla",team=5,pos={2517.04,25.6502,100161.0},craft=false},
    ["magpull_3"] = {odf="magpulla",team=5,pos={2517.04,35.8502,100229.0},craft=false},
    ["magpull_4"] = {odf="magpulla",team=5,pos={2552.88,25.5002,100160.0},craft=false},
    ["magpull_5"] = {odf="magpulla",team=5,pos={2551.99,12.6002,100074.0},craft=false},
    ["magpull_6"] = {odf="magpulla",team=5,pos={2553.71,35.7002,100228.0},craft=false},
    ["sniper_1"] = {odf="ssusera",team=5,pos={2447.7,250.0,100574.0},craft=true},
    ["sniper_2"] = {odf="ssusera",team=5,pos={2625.2,250.0,100395.0},craft=true},
    ["sniper_3"] = {odf="ssusera",team=5,pos={2948.53,60.0,100410.0},craft=true},
    ["sniper_4"] = {odf="ssusera",team=5,pos={2946.86,60.0,100568.0},craft=true},
    ["sniper_5"] = {odf="ssusera",team=5,pos={2136.05,60.0,100550.0},craft=true},
    ["sniper_6"] = {odf="ssusera",team=5,pos={2136.88,60.0,100408.0},craft=true},
    ["sniper_7"] = {odf="ssusera",team=5,pos={2339.38,97.5,100854.0},craft=true},
    ["sniper_8"] = {odf="ssusera",team=5,pos={2659.38,97.5,100849.0},craft=true},
    ["sniper_9"] = {odf="ssusera",team=5,pos={2007.63,97.5,101055.0},craft=true},
    ["sniper_10"] = {odf="ssusera",team=5,pos={3071.93,97.5,100889.0},craft=true},
    ["sniper_11"] = {odf="ssusera",team=5,pos={3068.27,97.5,101098.0},craft=true},
    ["sniper_12"] = {odf="ssusera",team=5,pos={2669.47,117.509,101333.0},craft=true},
    ["sniper_13"] = {odf="ssusera",team=5,pos={2475.69,153.647,101585.0},craft=true},
    ["sniper_14"] = {odf="ssusera",team=5,pos={2591.95,153.293,101583.0},craft=true},
    ["sniper_15"] = {odf="ssusera",team=5,pos={2192.8,241.92,101316.0},craft=true},
    ["sniper_16"] = {odf="ssusera",team=5,pos={2233.05,247.5,101310.0},craft=true},
    ["sniper_17"] = {odf="ssusera",team=5,pos={2233.05,247.5,101289.0},craft=true},
    ["sniper_18"] = {odf="ssusera",team=5,pos={2233.05,247.5,101273.0},craft=true},
    ["sniper_19"] = {odf="ssusera",team=5,pos={2233.05,247.5,101257.0},craft=true},
    ["sniper_20"] = {odf="ssusera",team=5,pos={2233.05,247.5,101236.0},craft=true},
    ["sniper_21"] = {odf="ssusera",team=5,pos={2838.24,247.5,101312.0},craft=true},
    ["sniper_22"] = {odf="ssusera",team=5,pos={2838.24,247.5,101294.0},craft=true},
    ["sniper_23"] = {odf="ssusera",team=5,pos={2838.24,247.5,101276.0},craft=true},
    ["sniper_24"] = {odf="ssusera",team=5,pos={2839.73,247.5,101258.0},craft=true},
    ["sniper_25"] = {odf="ssusera",team=5,pos={2839.73,247.5,101239.0},craft=true},
    ["sniper_26"] = {odf="ssusera",team=5,pos={3221.33,196.5,101668.0},craft=true},
    ["coop_spawn1"] = {odf="pspwn_1",team=1,pos={3225.51,165.8,97931.6},craft=false},
    ["coop_spawn2"] = {odf="pspwn_1",team=2,pos={3250.33,165.8,97934.6},craft=false},
    ["coop_spawn3"] = {odf="pspwn_1",team=3,pos={3275.15,165.8,97937.6},craft=false},
    ["coop_spawn4"] = {odf="pspwn_1",team=4,pos={3299.98,165.8,97940.5},craft=false},
    -- Unscripted map dressing (never GetHandle'd by the body); present so AllCraft()/counts behave like the
    -- real map. Not exhaustive of every static building, only what a test might plausibly query.
    ["svrecy20_recycler"] = {odf="svrecy",team=5,pos={2065.75,198.0,101469.0},craft=false},
    ["svmuf20_factory"] = {odf="svmuf",team=5,pos={2941.41,198.0,101428.0},craft=false},
    ["svslf20_armory"] = {odf="svslf",team=5,pos={1926.58,198.0,101579.0},craft=false},
    ["guard_1"] = {odf="svwalk",team=5,pos={2548.63,0.0,99987.8},craft=true},
    ["guard_2"] = {odf="svwalk",team=5,pos={2520.92,0.0,99989.6},craft=true},
}
F.PATHS = {
    ["apc_escort"]={246.667,10,97924.9},
    ["apc_fail"]={2540.83,10,99746.6},
    ["apc_nav"]={406.667,10,97866.7},
    ["apc_path"]={306.667,10,97866.7},
    ["apc_spawn"]={240.0,10,97866.7},
    ["break_point"]={2585.0,10,97856.9},
    ["cut_1"]={2424.67,10,99778.0},
    ["cut_bang"]={2618.33,10,99847.5},
    ["cut_trigger"]={2546.67,10,99532.4},
    ["day_1"]={2296.93,10,101274.0},
    ["day_10"]={2528.76,10,99920.7},
    ["day_1a"]={2778.35,10,101271.0},
    ["day_2"]={2210.12,10,101631.0},
    ["day_2a"]={2754.67,10,101623.0},
    ["day_3"]={2538.95,10,101460.0},
    ["day_4"]={2325.87,10,101145.0},
    ["day_4a"]={2728.36,10,101150.0},
    ["day_5"]={1883.91,10,100863.0},
    ["day_5a"]={3178.21,10,100858.0},
    ["day_6"]={2536.32,10,100840.0},
    ["day_7"]={2194.33,10,100484.0},
    ["day_7a"]={2859.9,10,100495.0},
    ["day_8"]={2452.14,10,100340.0},
    ["day_8a"]={2617.88,10,100350.0},
    ["day_9"]={2549.48,10,100198.0},
    ["day_9a"]={2510.02,10,100103.0},
    ["east_cloak"]={2603.95,10,101622.0},
    ["east_scout"]={2587.07,10,99323.3},
    ["east_sniper"]={2709.19,10,101500.0},
    ["edge_path"]={343.654,10,102151.0},
    ["guard_area"]={2440.83,10,100024.0},
    ["military_path"]={4014.65,10,98160.0},
    ["military_spawn"]={4074.65,10,98166.7},
    ["ne_trigger"]={3073.41,10,101277.0},
    ["nw_trigger"]={1988.68,10,101275.0},
    ["scavs"]={2537.91,10,101494.0},
    ["spawn_1"]={2538.97,10,100797.0},
    ["spawn_2"]={1887.16,10,100691.0},
    ["spawn_2a"]={2364.17,10,101142.0},
    ["spawn_3"]={3186.83,10,100681.0},
    ["spawn_3a"]={2698.21,10,101147.0},
    ["spawn_4"]={2536.65,10,101433.0},
    ["spawn_5"]={2497.6,10,101609.0},
    ["spawn_6"]={2572.91,10,101608.0},
    ["trigger_1"]={2532.93,10,99954.9},
    ["walker_path"]={2531.26,10,99973.2},
    ["walker_return"]={2498.33,10,99924.4},
    ["wave_1"]={2633.59,10,100965.0},
    ["wave_2"]={2339.23,10,100793.0},
    ["wave_3"]={2698.21,10,100784.0},
    ["wave_4"]={2413.93,10,101636.0},
    ["wave_5"]={2017.86,10,101488.0},
    ["wave_6"]={2994.09,10,101470.0},
    ["west_cloak"]={2462.6,10,101623.0},
    ["west_scout"]={2514.89,10,99321.5},
    ["west_sniper"]={2249.72,10,101443.0},
    ["wrecker_1"]={2532.93,10,99942.4},
}
F.BASE_LIMIT = {}
F.FAR = 50000
F.START = {3225.51, 165.8, 97931.6}
-- odf -> is-a-craft (mobile unit). Everything else (sb*/cb*/eg*/magpull*/boltmine/sv{recy,muf,slf}) is static.
local CRAFT = {cvtnk=true, cvtnkd=true, svapc=true, svfigh=true, svtank=true, svwalk=true, cvscav=true,
    ssusera=true, svartla=true, apcamr=true}
local function vec(t) return {x = t[1], y = t[2], z = t[3]} end
local function newObject(handle, odf, team, pos, craft)
    W.objects[handle] = {alive = true, odf = odf, team = team, health = 1, pos = vec(pos or {F.FAR, 6, F.FAR}),
        craft = craft or CRAFT[odf] or false, perceived = team, cloaked = false}
    local o = W.objects[handle]
    if F.LABELS[handle] then o.label = handle end
    return o
end

function F.reset()
    W = {now = 0, objects = {}, peers = {}, nextObject = 0, missing = {}, audioBusy = false, net = false,
        cancel = false, cameraDone = {}, timer = nil, realTimer = false}
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
function F.cloaked(h) return W.objects[h] and W.objects[h].cloaked == true end
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
-- options: faithful (CR_TEST_FAITHFUL), vehicle (the human's start craft, default "cvtnk"), weather = false.
function F.makePeer(id, team, network, options)
    options = options or {}
    local p = {id = id, team = team, net = network, hosting = team == 1, calls = {}, player = "player" .. id,
        camera = 0, info = {}, weatherCalls = {}}
    W.peers[id] = p
    newObject(p.player, options.vehicle or "cvtnk", team,
        {F.START[1] - 25 * (team - 1), F.START[2], F.START[3] - 3.8 * (team - 1)}, true)
    -- The human's current craft: GetPlayerHandle() answers this, not a fixed "player" entity (chmisn08's
    -- "player" concept is whoever is driving APC #5 this frame, which changes as humans board/leave). F.board
    -- changes it (boarding APC #5, jumping out into a dead/absent craft, etc).
    p.craft = p.player
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
        return p.craft
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
    e.SetPosition = function(h,pos)
        assert(e.IsValid(h))
        local at = type(pos) == "string" and F.posOf(pos) or pos
        W.objects[h].pos = {x = at.x, y = at.y, z = at.z}
        record("SetPosition", h, pos, at.x, at.z)
    end
    e.BuildDirectionalMatrix = function(pos, dir) return {x = pos.x, y = pos.y, z = pos.z, dx = dir and dir.x or 0, dz = dir and dir.z or 1} end
    e.IsCraft = function(h) return W.objects[h] ~= nil and W.objects[h].craft == true end
    e.GetFront = function(h) return {x = 0, y = 0, z = 1} end
    e.MakeExplosion = function(odf, where) record("MakeExplosion", odf, where) end
    e.ColorFade = function(...) record("ColorFade", ...) end
    e.StartSound = function(...) record("StartSound", ...) end
    e.SetName = function(h, name) record("SetName", h, name) end
    e.GetHealth = function(h) return W.objects[h] and W.objects[h].health or 0 end
    e.SetCurHealth = function(h, v) record("SetCurHealth", h, v); W.objects[h].health = v end
    e.GetCurHealth = function(h) return W.objects[h] and W.objects[h].health or 0 end
    e.GetMaxHealth = function(h) return W.objects[h] and W.objects[h].maxHealth or 1 end
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
    e.GetNearestUnitOnTeam = function(path, team)
        local pos = F.posOf(path)
        if pos == nil then return nil end
        local best, bestDistance
        for h, o in pairs(W.objects) do
            if o.alive and o.team == team then
                local dx, dz = o.pos.x - pos.x, o.pos.z - pos.z
                local d = math.sqrt(dx * dx + dz * dz)
                if bestDistance == nil or d < bestDistance then best, bestDistance = h, d end
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
    e.BuildObject = function(odf, objectTeam, where, point)
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
    e.IsInfo = function(odf) return p.info[odf] == true end
    e.Cloak = function(h) assert(e.IsValid(h), "Cloak on an invalid object"); record("Cloak", h); W.objects[h].cloaked = true end
    e.Decloak = function(h) assert(e.IsValid(h), "Decloak on an invalid object"); record("Decloak", h); W.objects[h].cloaked = false end
    e.IsCloaked = function(h) return W.objects[h] ~= nil and W.objects[h].cloaked == true end
    e.EnableCloaking = function(h, on) assert(e.IsValid(h), "EnableCloaking on an invalid object"); record("EnableCloaking", h, on) end
    e.SetPerceivedTeam = function(h, t)
        assert(e.IsValid(h), "SetPerceivedTeam on an invalid object")
        record("SetPerceivedTeam", h, t)
        W.objects[h].perceived = t
    end
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
    for _, name in ipairs({"Defend2", "Goto", "Attack", "SetObjectiveOn", "SetObjectiveOff",
        "ClearObjectives", "AddObjective", "SetAIP", "FailMission", "SucceedMission", "SetScrap", "SetPilot",
        "AddPilot", "StartEarthquake", "UpdateEarthQuake", "StopEarthquake", "DisplayMessage",
        "SetAIControl", "Ally", "UnAlly", "SetIndependence", "Retreat", "Stop", "Follow", "Defend",
        "SetAIControl", "UpdateObjective", "SetObjectiveName"}) do
        local n = name
        e[n] = function(...)
            if n == "SetObjectiveOn" or n == "Attack" or n == "Goto" or n == "Defend2" then
                assert(e.IsValid((...)), n .. " used a not-yet-valid handle")
            end
            record(n, ...)
        end
    end
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
    -- The Ganymede director stand-in (CREuropaWeather, shared generic ice-moon director): records the beats
    -- the mission asks for. The real generated site table is used. options.weather = false leaves both out.
    if options.weather ~= false then
        local level, w = 1, p.weatherCalls
        local function mark(name) return function(...) w[#w + 1] = {name, ...} end end
        modules.CREuropaWeather = {
            Seed = 7, Init = mark("Init"), Update = noop, ApplyNetEvent = function(op, ...) w[#w + 1] = {"net", op, ...} end,
            Shutdown = noop, Save = function() return {level = level} end, Load = noop, AnnounceState = noop,
            SetTargetLevel = function(n) level = n; w[#w + 1] = {"SetTargetLevel", n} end,
            GetTargetLevel = function() return level end,
            ReleaseForcedLevel = mark("ReleaseForcedLevel"), Quake = mark("Quake"), Surge = mark("Surge"),
            TriggerPlume = mark("TriggerPlume"), GetVentSites = function() return modules.CRGanymedeSitesCH08.vents or {} end,
        }
        modules.CRGanymedeSitesCH08 = assert(loadfile("Scripts/CRGanymedeSitesCH08.lua"))()
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
    setfenv(assert(loadfile(options.script or "Scripts/ch08cr.lua")), e)()
    p.chunkCalls = #p.calls -- everything recorded so far ran at chunk load, before Start
    p.env, p.coop, p.runtime, p.modules = e, modules.CRCoop, modules.CRCCARuntime, modules
    e.Start()
    return p
end

-- Boards peer's current craft onto handle h (h may be nil/a dead handle to simulate "driving nothing").
function F.board(peer, h) peer.craft = h end

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
