-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Shared mock world for the misn17 suites (Test-Misn17.lua offline, Test-Misn17Coop.lua multi-peer,
-- Test-Misn17Presentation.lua). Each peer runs the complete Scripts/misn17.lua in its own Lua 5.1
-- environment over the real CRCoop registry and the E/A + C presentation transport. The engine, AI and
-- combat are mocks: they verify script decisions, not Redux native map loading, pathfinding, Lua wire
-- serialization or EXU hooks. Coordinates are the authored ones (Missions/misn17.bzn).
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local F = {}

local function P(x, z, y) return {x, y or 6, z} end
F.LABELS = {
    ["myCar_hover"] = {odf="player",team=1,pos={1813.260009765625,187.43600463867188,99354.796875},craft=false},
    ["avrecy18_recycler"] = {odf="avrecy",team=1,pos={1752.56005859375,184.43699645996094,99319.3984375},craft=true},
    ["avfigh18_wingman"] = {odf="avfigh",team=1,pos={1733.6500244140625,188.197998046875,99464.703125},craft=true},
    ["avfigh19_wingman"] = {odf="avfigh",team=1,pos={1745.8699951171875,187.79100036621094,99454.0},craft=true},
    ["sfield19_scrapfield"] = {odf="sfield",team=0,pos={2533.840087890625,162.99200439453125,99695.203125},craft=false},
    ["sfield21_scrapfield"] = {odf="sfield",team=0,pos={2104.2099609375,155.73599243164062,100519.0},craft=false},
    ["sfield25_scrapfield"] = {odf="sfield",team=0,pos={2409.969970703125,158.93899536132812,100216.0},craft=false},
    ["sfield26_scrapfield"] = {odf="sfield",team=0,pos={1775.300048828125,155.10000610351562,100279.0},craft=false},
    ["sfield28_scrapfield"] = {odf="sfield",team=0,pos={2282.300048828125,158.16600036621094,98743.0},craft=false},
    ["sfield30_scrapfield"] = {odf="sfield",team=0,pos={2953.669921875,155.0,100464.0},craft=false},
    ["sfield32_scrapfield"] = {odf="sfield",team=0,pos={2154.02001953125,179.8000030517578,99600.703125},craft=false},
    ["sfield33_scrapfield"] = {odf="sfield",team=0,pos={2951.280029296875,155.0,100200.0},craft=false},
    ["sfield34_scrapfield"] = {odf="sfield",team=0,pos={2775.10009765625,161.50399780273438,100489.0},craft=false},
    ["sfield35_scrapfield"] = {odf="sfield",team=0,pos={2805.97998046875,155.67300415039062,99309.296875},craft=false},
    ["sfield36_scrapfield"] = {odf="sfield",team=0,pos={3095.10009765625,155.0,100608.0},craft=false},
    ["sfield37_scrapfield"] = {odf="sfield",team=0,pos={2524.469970703125,158.03199768066406,100755.0},craft=false},
    ["sfield0_scrapfield"] = {odf="sfield",team=0,pos={2154.02001953125,158.2989959716797,99938.796875},craft=false},
    ["cr17_scrap17"] = {odf="sfield",team=0,pos={2517.14990234375,155.12899780273438,98943.8984375},craft=false},
    ["cr17_scrap18"] = {odf="sfield",team=0,pos={2493.7099609375,156.83700561523438,99152.3984375},craft=false},
    ["cr17_scrap19"] = {odf="sfield",team=0,pos={2776.14990234375,174.58799743652344,99494.703125},craft=false},
    ["cr17_scrap20"] = {odf="sfield",team=0,pos={3333.010009765625,153.01100158691406,100408.0},craft=false},
    ["cr17_scrap21"] = {odf="sfield",team=0,pos={3546.159912109375,155.0,99391.3984375},craft=false},
    ["cr17_scrap22"] = {odf="sfield",team=0,pos={1362.0899658203125,157.47300720214844,99895.296875},craft=false},
    ["cr17_scrap23"] = {odf="sfield",team=0,pos={1677.469970703125,184.43299865722656,99470.3984375},craft=false},
    ["cr17_scrap24"] = {odf="sfield",team=0,pos={1688.2900390625,180.4080047607422,99308.0},craft=false},
    ["cr17_scrap25"] = {odf="sfield",team=0,pos={1708.52001953125,165.04600524902344,100469.0},craft=false},
    ["cr17_scrap26"] = {odf="sfield",team=0,pos={2062.469970703125,155.0,100795.0},craft=false},
    ["savfactory1"] = {odf="hbfact",team=6,pos={2990.610107421875,64.0999984741211,101376.0},craft=false},
    ["savfactory2"] = {odf="hbfact",team=6,pos={3049.39990234375,64.0999984741211,101378.0},craft=false},
    ["savfactory3"] = {odf="hbfact",team=6,pos={3130.360107421875,64.0999984741211,101377.0},craft=false},
    ["avmuf0_factory"] = {odf="avmuf",team=1,pos={1786.43994140625,190.9969940185547,99428.203125},craft=true},
    ["eggeizr1132_geyser"] = {odf="eggeizr1",team=0,pos={1809.3599853515625,189.99400329589844,99430.6015625},craft=false},
    ["eggeizr1133_geyser"] = {odf="eggeizr1",team=0,pos={1776.3499755859375,183.0449981689453,99295.203125},craft=false},
    ["avturr133_turrettank"] = {odf="avturr",team=1,pos={1753.510009765625,188.83999633789062,99474.8984375},craft=true},
    ["avturr134_turrettank"] = {odf="avturr",team=1,pos={1764.6400146484375,189.9250030517578,99481.796875},craft=true},
    ["avtank134_wingman"] = {odf="avtank",team=1,pos={1791.989990234375,191.0,99484.703125},craft=true},
    ["avltnk134_wingman"] = {odf="avltnk",team=1,pos={1782.4300537109375,191.0,99468.6015625},craft=true},
    ["sfield134_scrapfield"] = {odf="sfield",team=0,pos={1895.22998046875,190.0,99496.296875},craft=false},
    ["factorynav"] = {odf="apcamr",team=1,pos={3130.669921875,158.36700439453125,101674.0},craft=false},
    ["basenav"] = {odf="apcamr",team=1,pos={1889.7099609375,190.0,99362.5},craft=false},
    ["factorypart1"] = {odf="hbcrys",team=6,pos={3011.199951171875,64.0999984741211,101449.0},craft=false},
    ["factorypart2"] = {odf="hbcrys",team=6,pos={3087.179931640625,64.0999984741211,101450.0},craft=false},
    ["factorypart3"] = {odf="hbcrys",team=6,pos={3170.52001953125,64.0999984741211,101448.0},craft=false},
    ["savfactory4"] = {odf="hbfact",team=6,pos={3190.080078125,64.0999984741211,101378.0},craft=false},
    ["coop_spawn1"] = {odf="pspwn_1",team=1,pos={1813.260009765625,187.43600463867188,99354.796875},craft=false},
    ["coop_spawn2"] = {odf="pspwn_1",team=2,pos={1788.5799560546875,187.43600463867188,99350.8984375},craft=false},
    ["coop_spawn3"] = {odf="pspwn_1",team=3,pos={1763.9000244140625,187.43600463867188,99346.8984375},craft=false},
    ["coop_spawn4"] = {odf="pspwn_1",team=4,pos={1739.22998046875,187.43600463867188,99343.0},craft=false},
    ["cr17_tower1"] = {odf="hbptow",team=6,pos={1378.760009765625,204.5,100523.0},craft=false},
    ["cr17_tower2"] = {odf="hbptow",team=6,pos={2020.219970703125,155.1999969482422,100536.0},craft=false},
    ["cr17_tower3"] = {odf="hbptow",team=6,pos={932.802001953125,93.0,100020.0},craft=false},
    ["cr17_tower4"] = {odf="hbptow",team=6,pos={1976.5799560546875,157.8000030517578,100608.0},craft=false},
    ["cr17_tower5"] = {odf="hbptow",team=6,pos={3462.39990234375,54.900001525878906,100070.0},craft=false},
    ["cr17_tower6"] = {odf="hbptow",team=6,pos={3148.530029296875,295.0,98653.0},craft=false},
    ["cr17_tower7"] = {odf="hbptow",team=6,pos={3047.199951171875,157.39999389648438,99488.5},craft=false},
    ["cr17_mine1"] = {odf="crfmine",team=6,pos={3218.159912109375,153.60000610351562,101048.0},craft=false},
    ["cr17_mine2"] = {odf="crfmine",team=6,pos={3288.219970703125,155.0,101141.0},craft=false},
    ["cr17_mine3"] = {odf="crfmine",team=6,pos={3085.840087890625,128.3000030517578,100861.0},craft=false},
    ["cr17_mine4"] = {odf="crfmine",team=6,pos={3251.889892578125,152.6999969482422,101092.0},craft=false},
    ["cr17_mine5"] = {odf="crfmine",team=6,pos={3179.25,155.0,100954.0},craft=false},
    ["cr17_mine6"] = {odf="crfmine",team=6,pos={3231.139892578125,155.0,101012.0},craft=false},
    ["cr17_mine7"] = {odf="crfmine",team=6,pos={3197.409912109375,154.3000030517578,101006.0},craft=false},
    ["cr17_mine8"] = {odf="crfmine",team=6,pos={3083.25,117.0999984741211,100903.0},craft=false},
    ["cr17_mine9"] = {odf="crfmine",team=6,pos={3122.159912109375,145.60000610351562,100822.0},craft=false},
    ["cr17_mine10"] = {odf="crfmine",team=6,pos={3002.81005859375,152.39999389648438,100890.0},craft=false},
    ["cr17_mine11"] = {odf="crfmine",team=6,pos={3420.5400390625,179.1999969482422,101551.0},craft=false},
    ["cr17_mine12"] = {odf="crfmine",team=6,pos={2948.330078125,154.6999969482422,100967.0},craft=false},
    ["cr17_mine13"] = {odf="crfmine",team=6,pos={3148.110107421875,153.60000610351562,100871.0},craft=false},
    ["cr17_mine14"] = {odf="crfmine",team=6,pos={3311.570068359375,153.6999969482422,101188.0},craft=false},
    ["cr17_mine15"] = {odf="crfmine",team=6,pos={2945.72998046875,154.3000030517578,101001.0},craft=false},
    ["cr17_mine16"] = {odf="crfmine",team=6,pos={3397.18994140625,155.0,101385.0},craft=false},
    ["cr17_mine17"] = {odf="crfmine",team=6,pos={2987.25,154.3000030517578,100926.0},craft=false},
    ["cr17_mine18"] = {odf="crfmine",team=6,pos={2790.06005859375,160.89999389648438,101492.0},craft=false},
    ["cr17_mine19"] = {odf="crfmine",team=6,pos={3091.030029296875,130.3000030517578,100843.0},craft=false},
    ["cr17_mine20"] = {odf="crfmine",team=6,pos={3070.27001953125,128.3000030517578,100838.0},craft=false},
    ["cr17_mine21"] = {odf="crfmine",team=6,pos={3067.679931640625,130.89999389648438,100799.0},craft=false},
    ["cr17_mine22"] = {odf="crfmine",team=6,pos={3078.06005859375,129.6999969482422,100814.0},craft=false},
    ["cr17_mine23"] = {odf="crfmine",team=6,pos={2866.090087890625,154.89999389648438,101102.0},craft=false},
    ["cr17_mine24"] = {odf="crfmine",team=6,pos={3109.18994140625,140.89999389648438,100809.0},craft=false},
    ["cr17_mine25"] = {odf="crfmine",team=6,pos={2816.0,155.0,101198.0},craft=false},
    ["cr17_mine26"] = {odf="crfmine",team=6,pos={2774.489990234375,155.0,101240.0},craft=false},
    ["cr17_mine27"] = {odf="crfmine",team=6,pos={3404.97998046875,154.8000030517578,101432.0},craft=false},
    ["cr17_mine28"] = {odf="crfmine",team=6,pos={2771.889892578125,155.10000610351562,101289.0},craft=false},
    ["cr17_mine29"] = {odf="crfmine",team=6,pos={2774.489990234375,159.5,101447.0},craft=false},
    ["cr17_mine30"] = {odf="crfmine",team=6,pos={3142.919921875,153.89999389648438,100851.0},craft=false},
    ["cr17_mine31"] = {odf="crfmine",team=6,pos={2774.489990234375,155.5,101349.0},craft=false},
    ["cr17_mine32"] = {odf="crfmine",team=6,pos={2787.4599609375,165.10000610351562,101549.0},craft=false},
    ["cr17_mine33"] = {odf="crfmine",team=6,pos={2896.429931640625,155.0,101063.0},craft=false},
    ["cr17_mine34"] = {odf="crfmine",team=6,pos={3410.159912109375,164.1999969482422,101489.0},craft=false},
    ["cr17_mine35"] = {odf="crfmine",team=6,pos={2992.429931640625,152.39999389648438,100833.0},craft=false},
    ["cr17_mine36"] = {odf="crfmine",team=6,pos={2779.679931640625,156.8000030517578,101401.0},craft=false},
    ["cr17_mine37"] = {odf="crfmine",team=6,pos={2919.7900390625,155.0,101035.0},craft=false},
    ["cr17_mine38"] = {odf="crfmine",team=6,pos={2844.5400390625,155.0,101144.0},craft=false},
    ["cr17_mine39"] = {odf="crfmine",team=6,pos={2976.8701171875,154.8000030517578,100877.0},craft=false},
    ["cr17_mine40"] = {odf="crfmine",team=6,pos={3184.429931640625,155.0,100879.0},craft=false},
    ["cr17_mine41"] = {odf="crfmine",team=6,pos={3202.60009765625,155.0,100967.0},craft=false},
    ["cr17_mine42"] = {odf="crfmine",team=6,pos={3184.429931640625,155.0,100921.0},craft=false},
    ["cr17_mine43"] = {odf="crfmine",team=6,pos={3062.489990234375,127.4000015258789,100856.0},craft=false},
    ["cr17_mine44"] = {odf="crfmine",team=6,pos={3057.300048828125,122.4000015258789,100897.0},craft=false},
    ["cr17_mine45"] = {odf="crfmine",team=6,pos={3085.840087890625,122.9000015258789,100884.0},craft=false},
    ["cr17_mine46"] = {odf="crfmine",team=6,pos={3044.330078125,133.1999969482422,100814.0},craft=false},
    ["cr17_mine47"] = {odf="crfmine",team=6,pos={3015.7900390625,147.39999389648438,100820.0},craft=false},
    ["cr17_mine48"] = {odf="crfmine",team=6,pos={2953.52001953125,154.8000030517578,100934.0},craft=false},
    ["cr17_mine49"] = {odf="crfmine",team=6,pos={3342.699951171875,155.0,101242.0},craft=false},
    ["cr17_mine50"] = {odf="crfmine",team=6,pos={2971.679931640625,154.3000030517578,100962.0},craft=false},
    ["cr17_mine51"] = {odf="crfmine",team=6,pos={3360.8701171875,155.0,101294.0},craft=false},
    ["cr17_mine52"] = {odf="crfmine",team=6,pos={3013.18994140625,149.89999389648438,100856.0},craft=false},
    ["cr17_mine53"] = {odf="crfmine",team=6,pos={3376.429931640625,154.89999389648438,101336.0},craft=false},
    ["cr17_mine54"] = {odf="crfmine",team=6,pos={3174.06005859375,155.0,100833.0},craft=false},
}
F.PATHS = {
    ["procrysspawn"] = {3681.070068359375,155,101095.0},
    ["rawcrys1spawn"] = {3711.72998046875,155,101080.0},
    ["rawcrys2spawn"] = {3723.72998046875,155,101074.0},
    ["rawcrys3spawn"] = {3734.39990234375,155,101067.0},
    ["rawcrys4spawn"] = {3747.72998046875,155,101059.0},
    ["rawcrys5spawn"] = {3759.72998046875,155,101054.0},
    ["savspawn"] = {3088.429931640625,155,101343.0},
    ["opencampath"] = {2942.6201171875,155,100796.0},
    ["mine1"] = {3218.159912109375,155,101048.0},
    ["mine2"] = {3288.219970703125,155,101141.0},
    ["mine3"] = {3085.840087890625,155,100861.0},
    ["mine4"] = {3251.889892578125,155,101092.0},
    ["mine5"] = {3179.25,155,100954.0},
    ["mine6"] = {3231.139892578125,155,101012.0},
    ["mine7"] = {3197.409912109375,155,101006.0},
    ["mine8"] = {3083.25,155,100903.0},
    ["mine9"] = {3122.159912109375,155,100822.0},
    ["mine10"] = {3002.81005859375,155,100890.0},
    ["mine11"] = {3420.5400390625,155,101551.0},
    ["mine12"] = {2948.330078125,155,100967.0},
    ["mine13"] = {3148.110107421875,155,100871.0},
    ["mine14"] = {3311.570068359375,155,101188.0},
    ["mine15"] = {2945.72998046875,155,101001.0},
    ["mine16"] = {3397.18994140625,155,101385.0},
    ["mine17"] = {2987.25,155,100926.0},
    ["mine18"] = {2790.06005859375,155,101492.0},
    ["mine19"] = {3091.030029296875,155,100843.0},
    ["mine20"] = {3070.27001953125,155,100838.0},
    ["mine21"] = {3067.679931640625,155,100799.0},
    ["mine22"] = {3078.06005859375,155,100814.0},
    ["mine23"] = {2866.090087890625,155,101102.0},
    ["mine24"] = {3109.18994140625,155,100809.0},
    ["mine25"] = {2816.0,155,101198.0},
    ["mine26"] = {2774.489990234375,155,101240.0},
    ["mine27"] = {3404.97998046875,155,101432.0},
    ["mine28"] = {2771.889892578125,155,101289.0},
    ["mine29"] = {2774.489990234375,155,101447.0},
    ["mine30"] = {3142.919921875,155,100851.0},
    ["mine31"] = {2774.489990234375,155,101349.0},
    ["mine32"] = {2787.4599609375,155,101549.0},
    ["mine33"] = {2896.429931640625,155,101063.0},
    ["mine34"] = {3410.159912109375,155,101489.0},
    ["mine35"] = {2992.429931640625,155,100833.0},
    ["mine36"] = {2779.679931640625,155,101401.0},
    ["mine37"] = {2919.7900390625,155,101035.0},
    ["mine38"] = {2844.5400390625,155,101144.0},
    ["mine39"] = {2976.8701171875,155,100877.0},
    ["mine40"] = {3184.429931640625,155,100879.0},
    ["mine41"] = {3202.60009765625,155,100967.0},
    ["mine42"] = {3184.429931640625,155,100921.0},
    ["mine43"] = {3062.489990234375,155,100856.0},
    ["mine44"] = {3057.300048828125,155,100897.0},
    ["mine45"] = {3085.840087890625,155,100884.0},
    ["mine46"] = {3044.330078125,155,100814.0},
    ["mine47"] = {3015.7900390625,155,100820.0},
    ["mine48"] = {2953.52001953125,155,100934.0},
    ["mine49"] = {3342.699951171875,155,101242.0},
    ["mine52"] = {3013.18994140625,155,100856.0},
    ["mine53"] = {3376.429931640625,155,101336.0},
    ["mine54"] = {3174.06005859375,155,100833.0},
    ["mine55"] = {2971.679931640625,155,100962.0},
    ["mine56"] = {3360.8701171875,155,101294.0},
    ["minecin"] = {2992.419921875,155,100784.0},
    ["edge_path"] = {3669.330078125,155,101771.0},
    ["geizer3"] = {932.802001953125,155,100020.0},
    ["geizer1"] = {1378.760009765625,155,100523.0},
    ["geizer4"] = {1976.5799560546875,155,100608.0},
    ["geizer2"] = {2020.219970703125,155,100536.0},
    ["geizer5"] = {3462.39990234375,155,100070.0},
    ["geizer6"] = {3148.530029296875,155,98653.0},
    ["geizer7"] = {3047.199951171875,155,99488.5},
    ["pt1"] = {2787.4599609375,155,101195.0},
    ["pt2"] = {3070.27001953125,155,100876.0},
    ["pt3"] = {3360.8701171875,155,101265.0},
    ["cineractive1"] = {3251.889892578125,155,101392.0},
    ["cineractive3"] = {3222.2099609375,155,98760.296875},
    ["cineractive4"] = {3306.5400390625,155,100137.0},
    ["cineractive2"] = {1436.530029296875,155,100435.0},
    ["cineractive6"] = {1922.6400146484375,155,100627.0},
    ["part1geizer"] = {3027.199951171875,155,101454.0},
    ["part2geizer"] = {3095.199951171875,155,101454.0},
    ["part3geizer"] = {3149.8701171875,155,101456.0},
    ["cinscrap"] = {3198.669921875,155,101326.0},
    ["cineractive5"] = {930.6669921875,155,99947.8984375},
    ["cineractive7"] = {2993.60009765625,155,99453.0},
    ["counter"] = {3872.0,155,101888.0},
    ["mine50"] = {2971.679931640625,155,100962.0},
    ["mine51"] = {3360.8701171875,155,101294.0},
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
    newObject(p.player, options.vehicle or "avtank", team, {1813 - 25 * (team - 1), 187, 99354}, true)
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
    for _, name in ipairs({"Defend2", "Follow", "Defend", "Retreat", "Stop", "Goto", "Attack", "SetIndependence", "SetAIP",
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
                assert(W.objects[(...)].odf == "aspilo" or (W.objects[(...)].odf == "hvsat" and ((...)=="cr16_evac1" or (...)=="cr16_evac2")), "SetIndependence on a non-allowlisted object")
            end
            record(n, ...)
        end
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
    e.GetRidOfSomeScrap = function() error("preplaced field must not invoke stock scrap culling") end
    e.GetCurrentWho = function(h) return W.objects[h] and W.objects[h].target end
    local function noop() end
    local modules = {
        RequireFix = {Initialize = noop},
        CRCrystals17={Create=function() return {Reset=noop,Poll=noop,Update=noop,Report=noop,AddCargo=noop} end},
        CRJungleTrees17={Create=function() return {Update=noop} end},
        CRJungle17 = {Create=function() return {Reset=noop,Update=noop,Apply=noop,Stop=noop,
            Save=function() return {} end,Describe=function() return {} end} end},
        exu = {GetMyNetID = function() return id end, DisableStartingRecycler = function() record("DisableStartingRecycler") end,
            SetLives = function(n) record("SetLives", n) end},
        ScriptSubtitles = {
            Play = function(file) record("Play", file); return "audio:" .. file end,
            Queue = function(file) record("Queue", file); return "audio:" .. file end,
            Stop = function() record("Stop") end, Update = noop, Initialize = noop},
        CRFuryRoster = assert(loadfile("Scripts/CRFuryRoster.lua"))(),
        Environment = {Init=function() record("EnvironmentInit") end,
            BindWeatherSensors=function(name) record("WeatherSensors",name) end,
            Update=noop,OnObjectCreated=noop,InvalidateRenderer=noop},


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
    modules.CRMisn17 = setfenv(assert(loadfile("Scripts/CRMisn17.lua")),e)()
    setfenv(assert(loadfile("Scripts/misn17.lua")), e)()
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
