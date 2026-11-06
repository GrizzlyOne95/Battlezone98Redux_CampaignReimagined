-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Shared mock world for the chmisn07 suites (Test-Chmisn07Coop.lua, Test-Chmisn07Presentation.lua). Each peer runs
-- the complete Scripts/ch07cr.lua in its own Lua 5.1 environment over the real CRCoop registry and the E/A + C
-- presentation transport. The engine, AI and combat are mocks: they verify script decisions, not Redux
-- native map loading, pathfinding, Lua wire serialization or EXU hooks. Labels and paths are the real
-- Missions/ch07cr.bzn positions (Test-Chmisn07CoopContract.py checks the names against the map).
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local F = {}
local W

F.LABELS = {
    ["player"] = {odf="ssuserb",team=1,pos={902.664,40.2,99267.9},craft=true},
    ["tower_3"] = {odf="sbtowe",team=5,pos={1120.43,5.0871,99780},craft=false},
    ["tower_4"] = {odf="sbtowe",team=5,pos={1179.91,5.1,99720.5},craft=false},
    ["spower_2"] = {odf="sbspow",team=5,pos={1120.32,5.1,99719.5},craft=false},
    ["spower_1"] = {odf="sbspow",team=5,pos={879.328,5.1,99518},craft=false},
    ["tower_2"] = {odf="sbtowe",team=5,pos={879.282,5.1,99460.5},craft=false},
    ["tower_1"] = {odf="sbtowe",team=5,pos={820.563,5.1,99520.1},craft=false},
    ["commtower"] = {odf="sbcomm",team=5,pos={996.312,5.1,99618.5},craft=false},
    ["repair"] = {odf="sbhang",team=5,pos={921.158,5.1,99618.9},craft=false},
    ["barracks_2"] = {odf="sbbarr",team=5,pos={1000.17,5.1,99680.5},craft=false},
    ["barracks_1"] = {odf="sbbarr",team=5,pos={980.119,5.1,99680.5},craft=false},
    ["barracks_3"] = {odf="sbbarr",team=5,pos={1019.48,5.1,99680.3},craft=false},
    ["cafe_1"] = {odf="sbcafe",team=5,pos={999.385,5.1,99721},craft=false},
    ["hq"] = {odf="sbhqcp",team=5,pos={1059.81,5.1,99619.9},craft=false},
    ["shield_1"] = {odf="sbshld",team=5,pos={860.061,5.1,99499.7},craft=false},
    ["shield_2"] = {odf="sbshld",team=5,pos={1139.87,5,99739},craft=false},
    ["barracks_5"] = {odf="sbbarr",team=5,pos={999.699,5.1,99559.6},craft=false},
    ["barracks_6"] = {odf="sbbarr",team=5,pos={1020.14,5.1,99559.5},craft=false},
    ["barracks_4"] = {odf="sbbarr",team=5,pos={980.112,5.1,99559.7},craft=false},
    ["supply"] = {odf="sbmbld",team=5,pos={1000.04,5.1,99519.6},craft=false},
    ["bomb_north"] = {odf="abstora",team=5,pos={1241.43,50.1,101799},craft=false},
    ["storage_1"] = {odf="abstor",team=5,pos={1196.03,50.1,101822},craft=false},
    ["cafe_2"] = {odf="sbcafe",team=5,pos={1171.64,50.1,101815},craft=false},
    ["storage_2"] = {odf="abstor",team=5,pos={1229.03,50.1,101845},craft=false},
    ["tower_6"] = {odf="sbtowe",team=5,pos={1688.13,91.4,101849},craft=false},
    ["spower_4"] = {odf="sbspow",team=5,pos={1650.55,91.4,101849},craft=false},
    ["spower_3"] = {odf="sbspow",team=5,pos={951.432,85.5,101851},craft=false},
    ["tower_5"] = {odf="sbtowe",team=5,pos={921.859,85.5,101850},craft=false},
    ["tower_7"] = {odf="sbtowe",team=5,pos={3251.22,89.9878,100150},craft=false},
    ["spower_5"] = {odf="sbspow",team=5,pos={3250.53,89.9947,100119},craft=false},
    ["spower_6"] = {odf="sbspow",team=5,pos={3292.08,103.183,99592.5},craft=false},
    ["tower_8"] = {odf="sbtowe",team=5,pos={3291.59,103.1,99554.8},craft=false},
    ["bomb_east"] = {odf="abstora",team=5,pos={3196.33,57.1,99747.4},craft=false},
    ["storage_3"] = {odf="abstor",team=5,pos={3248.89,57.1,99742.2},craft=false},
    ["storage_4"] = {odf="abstor",team=5,pos={3228.89,57.1,99709.2},craft=false},
    ["cafe_3"] = {odf="sbcafe",team=5,pos={3218.33,57.1,99681.4},craft=false},
    ["foot_1_1"] = {odf="sspilo",team=5,pos={947.448,7.18441,99373.7},craft=true},
    ["foot_1_3"] = {odf="sspilo",team=5,pos={1135.72,5.1,99689.2},craft=true},
    ["foot_1_2"] = {odf="sspilo",team=5,pos={941.448,8.95135,99361.7},craft=true},
    ["pilot_1"] = {odf="sspilo",team=5,pos={389.434,61.9307,100450},craft=true},
    ["pilot_2"] = {odf="sspilo",team=5,pos={811.06,95.6324,100408},craft=true},
    ["pilot_3"] = {odf="sspilo",team=5,pos={1063.4,64.0236,100552},craft=true},
    ["pilot_4"] = {odf="sspilo",team=5,pos={1689.04,104.723,98935.6},craft=true},
    ["pilot_5"] = {odf="sspilo",team=5,pos={1864.72,97.5334,99251.8},craft=true},
    ["pilot_6"] = {odf="sspilo",team=5,pos={2049.98,79.5018,99523.3},craft=true},
    ["foot_2_1"] = {odf="sspilo",team=5,pos={956.779,5.1,99540.2},craft=true},
    ["foot_2_2"] = {odf="sspilo",team=5,pos={957.779,4.8723,99530.2},craft=true},
    ["foot_2_3"] = {odf="sspilo",team=5,pos={852.508,5.1,99544.9},craft=true},
    ["figh_2_3"] = {odf="svfigh",team=5,pos={885.773,6.6,99370.8},craft=true},
    ["proxminf"] = {odf="proxminf",team=5,pos={475.648,82.9801,100692},craft=false},
    ["figh_3_1"] = {odf="svfigh",team=5,pos={1831.13,6.6,99871},craft=true},
    ["figh_3_2"] = {odf="svfigh",team=5,pos={2988.28,14.5601,99758.1},craft=true},
    ["figh_1_1"] = {odf="svfigh",team=5,pos={1460.61,6.6,99719.3},craft=true},
    ["figh_1_2"] = {odf="svfigh",team=5,pos={1669.61,6.6,101216},craft=true},
    ["figh_1_3"] = {odf="svfigh",team=5,pos={1196.61,9.1961,100826},craft=true},
    ["figh_2_2"] = {odf="svfigh",team=5,pos={1643.54,7.55582,101355},craft=true},
    ["figh_2_1"] = {odf="svfigh",team=5,pos={1393.61,6.6,100259},craft=true},
    ["proxminf14_proximity"] = {odf="proxminf",team=5,pos={1088.29,45.071,100779},craft=false},
    ["ammo_1"] = {odf="apammob",team=1,pos={1163.97,50.1,101854},craft=false},
    ["repair_1"] = {odf="aprepab",team=1,pos={1172.18,50.1,101852},craft=false},
    ["ammo_2"] = {odf="apammob",team=1,pos={3260.46,57.1,99688.2},craft=false},
    ["repair_2"] = {odf="aprepab",team=1,pos={3261.46,57.1,99681.2},craft=false},
    ["coop_spawn1"] = {odf="pspwn_1",team=1,pos={902.664,40.2,99267.9},craft=false},
    ["coop_spawn2"] = {odf="pspwn_1",team=2,pos={877.916,40.2,99271.4},craft=false},
    ["coop_spawn3"] = {odf="pspwn_1",team=3,pos={853.168,40.2,99275},craft=false},
    ["coop_spawn4"] = {odf="pspwn_1",team=4,pos={828.419,40.2,99278.5},craft=false},
}
F.PATHS = {
    ["edge_path"]={394.069,10,102105},
    ["zn_1_trig"]={452.469,10,100519},
    ["zn_2_trig"]={1904.33,10,98996.5},
    ["zn_3_trig"]={2503.92,10,100752},
    ["zn_4_trig"]={2776.38,10,99763},
    ["zn_5_trig"]={976.921,10,101305},
    ["zn_6_trig"]={1343.03,10,102058},
    ["north_trig"]={1321.19,10,101961},
    ["east_trig"]={3429.88,10,99863.6},
    ["foot_1_path"]={962.498,10,99399.3},
    ["zn_7_trig"]={3519.66,10,99782.5},
    ["zn_1_snip_1_spn"]={872.418,10,100597},
    ["zn_1_snip_2_spn"]={579.533,10,100015},
    ["zn_1_snip_3_spn"]={570.523,10,100447},
    ["zn_2_snip_4_spn"]={551.827,10,100838},
    ["zn_1_snip_5_spn"]={1115.82,10,100199},
    ["zn_1_pilo_2_spn"]={923.871,10,100641},
    ["zn_1_pilo_1_spn"]={579.648,10,100720},
    ["zn_1_turr_1_spn"]={801.175,10,100047},
    ["zn_1_turr_2_spn"]={603.28,10,100189},
    ["zn_1_turr_3_spn"]={773.47,10,100423},
    ["zn_5_snip_1_spn"]={712.457,10,100838},
    ["zn_5_snip_2_spn"]={683.524,10,101159},
    ["zn_5_snip_3_spn"]={890.235,10,101039},
    ["zn_1_snip_4_spn"]={1033.36,10,100718},
    ["zn_5_snip_5_spn"]={1064.74,10,100867},
    ["zn_5_snip_6_spn"]={1163.63,10,101085},
    ["zn_5_pilo_3_spn"]={1096.95,10,101659},
    ["zn_5_pilo_2_spn"]={810.218,10,101545},
    ["zn_5_pilo_1_spn"]={595.301,10,101396},
    ["zn_5_turr_1_spn"]={887.719,10,100779},
    ["zn_5_turr_2_spn"]={466.031,10,101227},
    ["zn_5_turr_3_spn"]={950.248,10,101492},
    ["zn_6_turr_1_spn"]={944,10,101720},
    ["zn_6_turr_2_spn"]={1695.38,10,101719},
    ["zn_6_turr_3_spn"]={1208.03,10,101792},
    ["zn_6_snip_1_spn"]={1414.07,10,101743},
    ["zn_6_snip_2_spn"]={1509.38,10,101891},
    ["zn_6_turr_4_spn"]={1843.87,10,101495},
    ["zn_3_turr_1_spn"]={2085.61,10,100067},
    ["zn_3_turr_2_spn"]={2104.2,10,101036},
    ["zn_3_turr_4_spn"]={1916.75,10,101006},
    ["zn_3_turr_5_spn"]={2368.74,10,100917},
    ["zn_3_turr_6_spn"]={2082.7,10,100383},
    ["zn_3_turr_3_spn"]={2295.66,10,101197},
    ["zn_3_snip_2_spn"]={2145.61,10,100194},
    ["zn_3_snip_1_spn"]={2440.5,10,100472},
    ["zn_3_snip_3_spn"]={1943.89,10,101217},
    ["zn_3_snip_4_spn"]={2320.67,10,101437},
    ["zn_3_snip_5_spn"]={2665.01,10,100506},
    ["zn_2_snip_1_spn"]={1358.14,10,99055.9},
    ["zn_2_snip_2_spn"]={1221.37,10,99215.8},
    ["zn_2_snip_3_spn"]={1599.57,10,99044},
    ["zn_2_snip_6_spn"]={1801.42,10,99154.8},
    ["zn_2_snip_5_spn"]={1815.51,10,99476.1},
    ["zn_4_snip_5_spn"]={2451.24,10,99214.2},
    ["zn_2_pilo_3_spn"]={2336.46,10,99214.2},
    ["zn_2_pilo_2_spn"]={2328.55,10,98964.8},
    ["zn_2_pilo_1_spn"]={1667.71,10,99355.2},
    ["zn_2_turr_1_spn"]={1362.67,10,99357.1},
    ["zn_2_turr_2_spn"]={2031.7,10,99427.9},
    ["zn_2_turr_3_spn"]={2103.51,10,99676.1},
    ["zn_2_turr_4_spn"]={1844.96,10,99063.8},
    ["zn_2_turr_5_spn"]={2244,10,99016.7},
    ["zn_2_turr_6_spn"]={2372.08,10,99511},
    ["zn_4_snip_1_spn"]={2407.02,10,99750.1},
    ["zn_4_snip_2_spn"]={2673.69,10,100131},
    ["zn_4_snip_3_spn"]={2838.4,10,99475.4},
    ["zn_4_snip_4_spn"]={2953.17,10,99230},
    ["zn_4_pilo_1_spn"]={3243.49,10,99549.1},
    ["zn_4_pilo_2_spn"]={3267.59,10,99337},
    ["zn_4_turr_1_spn"]={2632.58,10,99317.1},
    ["zn_4_turr_2_spn"]={3000.67,10,98972.7},
    ["zn_4_turr_3_spn"]={2465.6,10,99964.3},
    ["zn_7_turr_1_spn"]={3132.85,10,100136},
    ["zn_7_turr_2_spn"]={3128.69,10,99571.1},
    ["zn_7_turr_3_spn"]={3190.89,10,99719.2},
    ["zn_7_snip_1_spn"]={3233.07,10,100029},
    ["zn_7_snip_2_spn"]={3148.27,10,99930.5},
    ["foot_2_path"]={957.36,10,99556.2},
    ["north_path"]={1921.56,10,102245},
    ["north_spn"]={1985.56,10,102293},
    ["north_fail"]={408.258,10,101947},
    ["east_path"]={3629.44,10,100536},
    ["east_spn"]={3692.56,10,100607},
    ["east_fail"]={3512.85,10,99128.2},
    ["figh_1_path"]={1486.56,10,99737.6},
    ["figh_2_path"]={1778.1,10,99929.7},
    ["figh_3_path"]={2061.62,10,99762.8},
    ["expl_north_spn"]={1241.44,10,101791},
    ["expl_east_spn"]={3188.02,10,99748.3},
    ["burglar_exit"]={999.97,10,99638.3},
    ["nav_north"]={1410.59,10,101862},
    ["nav_east"]={3244.89,10,99946.9},
    ["nav_end"]={1480.12,10,99997.4},
    ["snip_end_1_spn"]={1442.76,10,100053},
    ["snip_end_2_spn"]={1562.29,10,99997.4},
    ["snip_end_3_spn"]={1431.56,10,99911.5},
    ["sold_end_1_spn"]={1435.29,10,99997.4},
    ["sold_end_2_spn"]={1461.44,10,100027},
    ["sold_end_3_spn"]={1524.94,10,99993.7},
    ["cin_start"]={884.969,10,99229.9},
    ["fake_spn"]={978.605,10,99583},
    ["cin_north"]={1654.57,10,101772},
    ["cin_east"]={3171.17,10,100139},
    ["cin_burglar"]={981.605,10,99640},
    ["sold_north_1_spn"]={1299.11,10,101767},
    ["sold_north_2_spn"]={1370.11,10,101768},
    ["sold_east_1_spn"]={3169.43,10,99897.4},
    ["sold_east_2_spn"]={3169.43,10,99818.4},
    ["north_wav"]={906.96,10,101763},
    ["east_wav"]={3174.53,10,99521.9},
    ["zn_1_sold_1_spn"]={576.179,10,101142},
    ["zn_1_sold_2_spn"]={896.904,10,100898},
    ["zn_2_sold_1_spn"]={2834.44,10,99091.5},
    ["zn_2_sold_2_spn"]={2174.19,10,99313.1},
    ["zn_4_sold_1_spn"]={3128.69,10,99397.3},
    ["zn_4_sold_2_spn"]={2907.59,10,100174},
    ["zn_5_sold_1_spn"]={1010.26,10,102032},
    ["zn_5_sold_2_spn"]={743.537,10,101825},
    ["zn_3_sold_1_spn"]={2706.2,10,100780},
    ["zn_3_sold_2_spn"]={2303.87,10,100965},
    ["north_sold_1_spn"]={973.689,10,101787},
    ["north_sold_3_spn"]={1438.92,10,101571},
    ["north_sold_2_spn"]={1511.31,10,101934},
    ["east_sold_1_spn"]={3153.12,10,100104},
    ["east_sold_3_spn"]={2945.55,10,99892.4},
    ["east_sold_2_spn"]={3203.99,10,99605.8},
    ["foot_4_path"]={849.801,10,99560.8},
    ["foot_3_path"]={1154.42,10,99674.5},
    ["rescue_1_spn"]={1495.06,10,99937.7},
    ["rescue_2_spn"]={1495.06,10,100031},
    ["rescue_3_spn"]={1450.23,10,99956.3},
    ["rescue_4_spn"]={1472.64,10,99971.3},
    ["rescue_5_spn"]={1416.62,10,100031},
    ["zn_5_snip_4_spn"]={726.228,10,101921},
    ["zn_1_pilo_3_spn"]={504.333,10,100225},
    ["zn_4_pilo_3_spn"]={3262.77,10,100248},
    ["pilo_east_1_spn"]={3229.09,10,99947.3},
    ["pilo_east_2_spn"]={3335.33,10,99690.9},
    ["pilo_north_1_spn"]={1407.59,10,101848},
    ["pilo_north_2_spn"]={1202.17,10,102068},
    ["back_1_1_spn"]={988.631,10,100043},
    ["back_1_2_spn"]={1122.26,10,100389},
    ["back_1_3_spn"]={737.091,10,100586},
    ["back_1_4_spn"]={737.091,10,101010},
    ["back_1_5_spn"]={1986.93,10,100083},
    ["back_1_6_spn"]={2167.72,10,100358},
    ["back_2_6_spn"]={2387.82,10,100059},
    ["back_2_5_spn"]={2419.26,10,100334},
    ["back_2_4_spn"]={2434.98,10,99115.8},
    ["back_2_3_spn"]={2191.31,10,99524.5},
    ["back_2_2_spn"]={1963.35,10,99076.4},
    ["back_2_1_spn"]={1609.62,10,99445.9},
    ["pilo_end_1_spn"]={1266.59,10,100137},
    ["pilo_end_2_spn"]={1266.59,10,99888.4},
    ["pilo_end_3_spn"]={1447.45,10,100227},
    ["pilo_end_4_spn"]={1662.22,10,100143},
    ["pilo_end_5_spn"]={1368.32,10,99792.3},
    ["pilo_end_6_spn"]={1605.7,10,99803.6},
    ["pilo_end_7_spn"]={1735.7,10,99950.5},
    ["pilo_end_8_spn"]={1170.89,10,99441.9},
    ["fake_vanish"]={1004.61,10,99601},
    ["zn_8_trig"]={810.751,10,100709},
    ["zn_9_trig"]={2090.29,10,99515.9},
}
F.BASE_LIMIT = {}
F.FAR = 50000
F.START = {902.664, 40.2, 99267.9}
local CRAFT = {svfigh=true,svapca=true,svapcb=true,sspilo=true,ssuserb=true,sssold=true,ssusera=true,svturr=true}
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
    newObject(p.player, options.vehicle or "ssuserb", team,
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
    e.IsPerson = function(h) return e.IsValid(h) and (W.objects[h].odf == "ssuserb" or W.objects[h].odf == "sspilo") end
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
    e.GetMaxHealth = function(h) return W.objects[h] and W.objects[h].maxHealth or 1 end
    e.GetCurAmmo = function(h) return W.objects[h] and W.objects[h].ammo or 1 end
    e.GetMaxAmmo = function(h) return W.objects[h] and W.objects[h].maxAmmo or 1 end
    e.SetCurAmmo = function(h, v) record("SetCurAmmo", h, v); W.objects[h].ammo = v end
    e.SetPilotClass = function(h, c) assert(e.IsValid(h), "SetPilotClass on an invalid object"); record("SetPilotClass", h, c) end
    e.MakeExplosion = function(odf, where) record("MakeExplosion", odf, where) end
    e.ColorFade = function(...) record("ColorFade", ...) end
    e.StartSound = function(...) record("StartSound", ...) end
    e.SetName = function(h, name) record("SetName", h, name) end
    e.GetHealth = function(h) return W.objects[h] and W.objects[h].health or 0 end
    e.SetCurHealth = function(h, v) record("SetCurHealth", h, v); W.objects[h].health = v end
    e.GetCurHealth = function(h) return W.objects[h] and W.objects[h].health or 0 end
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
            TriggerPlume = mark("TriggerPlume"), GetVentSites = function() return modules.CREuropaSitesCH07.vents or {} end,
        }
        modules.CREuropaSitesCH07 = assert(loadfile("Scripts/CREuropaSitesCH07.lua"))()
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
    setfenv(assert(loadfile(options.script or "Scripts/ch07cr.lua")), e)()
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
