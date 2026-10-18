-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Shared mock world for the misn16 suites (Test-Misn16.lua offline, Test-Misn16Coop.lua multi-peer,
-- Test-Misn16Presentation.lua). Each peer runs the complete Scripts/misn16.lua in its own Lua 5.1
-- environment over the real CRCoop registry and the E/A + C presentation transport. The engine, AI and
-- combat are mocks: they verify script decisions, not Redux native map loading, pathfinding, Lua wire
-- serialization or EXU hooks. Coordinates are the authored ones (Missions/misn16.bzn).
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local F = {}

local function P(x, z, y) return {x, y or 6, z} end
F.LABELS = {
    ["player0_hover"] = {odf="player",team=1,pos={2875.239990234375,5.9476399421691895,99548.8984375},craft=true},
    ["sbtowe0_turret"] = {odf="cr16tow",team=6,pos={2462.340087890625,59.0,99878.1015625},craft=false},
    ["sbtowe1_turret"] = {odf="cr16tow",team=6,pos={2546.760009765625,56.9010009765625,99869.796875},craft=false},
    ["sbtowe2_turret"] = {odf="cr16tow",team=6,pos={2386.2099609375,55.68519973754883,99623.203125},craft=false},
    ["sbtowe3_turret"] = {odf="cr16tow",team=6,pos={2429.239990234375,57.474998474121094,99585.1015625},craft=false},
    ["alien_hq"] = {odf="cr16cmd",team=6,pos={2452.409912109375,59.0,99660.703125},craft=false},
    ["alien_hangar"] = {odf="cr16hng",team=6,pos={2513.659912109375,59.0,99771.0},craft=false},
    ["sbspow3_powerplant"] = {odf="cr16pwr",team=6,pos={2435.860107421875,59.31809997558594,99875.296875},craft=false},
    ["sbspow4_powerplant"] = {odf="cr16pwr",team=6,pos={2573.239990234375,59.0,99853.796875},craft=false},
    ["sbspow5_powerplant"] = {odf="cr16pwr",team=6,pos={2373.409912109375,59.5885009765625,99644.703125},craft=false},
    ["sbspow6_powerplant"] = {odf="cr16pwr",team=6,pos={2451.199951171875,59.223899841308594,99595.0},craft=false},
    ["avmuf26_factory"] = {odf="avmuf",team=1,pos={2873.3798828125,6.5,99443.6015625},craft=true},
    ["avrecy0_recycler"] = {odf="avrecy",team=1,pos={2898.409912109375,6.5,99447.796875},craft=true},
    ["eggeizr16_geyser"] = {odf="eggeizr1",team=0,pos={2326.72998046875,5.0,100136.0},craft=false},
    ["eggeizr17_geyser"] = {odf="eggeizr1",team=0,pos={2283.699951171875,5.0,100065.0},craft=false},
    ["eggeizr18_geyser"] = {odf="eggeizr1",team=0,pos={2405.800048828125,5.119909763336182,100068.0},craft=false},
    ["eggeizr19_geyser"] = {odf="eggeizr1",team=0,pos={2398.22998046875,5.0,99394.203125},craft=false},
    ["eggeizr110_geyser"] = {odf="eggeizr1",team=0,pos={2467.75,5.0,99289.8984375},craft=false},
    ["eggeizr111_geyser"] = {odf="eggeizr1",team=0,pos={2557.340087890625,5.0,99418.296875},craft=false},
    ["eggeizr112_geyser"] = {odf="eggeizr1",team=0,pos={2827.77001953125,5.0,99118.1015625},craft=false},
    ["eggeizr113_geyser"] = {odf="eggeizr1",team=0,pos={2923.929931640625,5.0,99243.5},craft=false},
    ["eggeizr114_geyser"] = {odf="eggeizr1",team=0,pos={2647.64990234375,5.0,100333.0},craft=false},
    ["eggeizr115_geyser"] = {odf="eggeizr1",team=0,pos={2668.52001953125,5.0,100274.0},craft=false},
    ["eggeizr116_geyser"] = {odf="eggeizr1",team=0,pos={1796.1700439453125,5.0,99731.5},craft=false},
    ["eggeizr117_geyser"] = {odf="eggeizr1",team=0,pos={1750.260009765625,5.0,99685.6015625},craft=false},
    ["apcamr11_camerapod"] = {odf="apcamr",team=1,pos={2452.409912109375,60.000099182128906,99782.1015625},craft=false},
    ["apcamr15_camerapod"] = {odf="apcamr",team=1,pos={2734.090087890625,9.451109886169434,100252.0},craft=false},
    ["apcamr12_camerapod"] = {odf="apcamr",team=1,pos={1866.0400390625,6.000150203704834,99672.796875},craft=false},
    ["apcamr13_camerapod"] = {odf="apcamr",team=1,pos={2805.080078125,6.000150203704834,99191.3984375},craft=false},
    ["boltmine0_weaponmine"] = {odf="boltmine",team=6,pos={2646.89990234375,5.0,100055.0},craft=false},
    ["boltmine1_weaponmine"] = {odf="boltmine",team=6,pos={2671.719970703125,5.8639397621154785,99995.203125},craft=false},
    ["boltmine2_weaponmine"] = {odf="boltmine",team=6,pos={2047.199951171875,5.0,99833.796875},craft=false},
    ["boltmine3_weaponmine"] = {odf="boltmine",team=6,pos={2043.06005859375,5.530869960784912,99784.1015625},craft=false},
    ["boltmine4_weaponmine"] = {odf="boltmine",team=6,pos={2754.760009765625,5.0,99461.3984375},craft=false},
    ["boltmine5_weaponmine"] = {odf="boltmine",team=6,pos={2717.52001953125,5.0,99403.5},craft=false},
    ["hvsat5_wingman"] = {odf="hvsat",team=6,pos={2500.75,60.0,99835.703125},craft=true},
    ["hvsat6_wingman"] = {odf="hvsat",team=6,pos={2406.89990234375,60.0,99653.6015625},craft=true},
    ["hvsat0_wingman"] = {odf="hvsat",team=6,pos={2142.610107421875,6.0,99815.0},craft=true},
    ["hvsat1_wingman"] = {odf="hvsat",team=6,pos={2605.909912109375,6.0,99956.8984375},craft=true},
    ["hvsat2_wingman"] = {odf="hvsat",team=6,pos={2622.5,15.006999969482422,99489.3984375},craft=true},
    ["avcnst0_constructionrig"] = {odf="avcnst",team=1,pos={2893.909912109375,5.939990043640137,99526.0},craft=true},
    ["avslf0_armory"] = {odf="avslf",team=1,pos={2896.580078125,6.5,99495.5},craft=true},
    ["hvsav47_sav"] = {odf="hvsav",team=6,pos={2513.64990234375,60.0,99771.0},craft=true},
    ["npscr347_scrap"] = {odf="npscr3",team=0,pos={2433.780029296875,5.0,99432.6015625},craft=false},
    ["npscr247_scrap"] = {odf="npscr2",team=0,pos={2413.77001953125,5.0,99432.203125},craft=false},
    ["npscr248_scrap"] = {odf="npscr2",team=0,pos={2424.489990234375,5.0,99441.796875},craft=false},
    ["npscr348_scrap"] = {odf="npscr3",team=0,pos={2441.56005859375,5.473909854888916,99422.1015625},craft=false},
    ["npscr249_scrap"] = {odf="npscr2",team=0,pos={2414.389892578125,5.0,99439.3984375},craft=false},
    ["npscr149_scrap"] = {odf="npscr1",team=0,pos={2403.330078125,5.0,99432.1015625},craft=false},
    ["npscr150_scrap"] = {odf="npscr1",team=0,pos={2426.919921875,5.0,99443.6015625},craft=false},
    ["npscr350_scrap"] = {odf="npscr3",team=0,pos={2395.8701171875,5.0,99442.296875},craft=false},
    ["npscr351_scrap"] = {odf="npscr3",team=0,pos={2407.219970703125,5.0,99449.8984375},craft=false},
    ["npscr352_scrap"] = {odf="npscr3",team=0,pos={2396.06005859375,5.0,99429.8984375},craft=false},
    ["npscr353_scrap"] = {odf="npscr3",team=0,pos={2366.919921875,5.291689872741699,99980.5},craft=false},
    ["npscr253_scrap"] = {odf="npscr2",team=0,pos={2352.320068359375,11.884300231933594,100010.0},craft=false},
    ["npscr153_scrap"] = {odf="npscr1",team=0,pos={2364.72998046875,5.0,99958.1015625},craft=false},
    ["npscr354_scrap"] = {odf="npscr3",team=0,pos={2363.1298828125,9.003080368041992,100001.0},craft=false},
    ["npscr355_scrap"] = {odf="npscr3",team=0,pos={2382.3701171875,5.051310062408447,99987.5},craft=false},
    ["npscr255_scrap"] = {odf="npscr2",team=0,pos={2337.5,8.435440063476562,99984.203125},craft=false},
    ["npscr155_scrap"] = {odf="npscr1",team=0,pos={2339.219970703125,11.771699905395508,99998.6015625},craft=false},
    ["npscr156_scrap"] = {odf="npscr1",team=0,pos={2361.659912109375,5.338860034942627,99979.296875},craft=false},
    ["npscr356_scrap"] = {odf="npscr3",team=0,pos={2368.6298828125,5.0,99966.796875},craft=false},
    ["npscr157_scrap"] = {odf="npscr1",team=0,pos={2376.530029296875,5.0,99967.0},craft=false},
    ["npscr257_scrap"] = {odf="npscr2",team=0,pos={2295.81005859375,6.7806901931762695,100010.0},craft=false},
    ["npscr158_scrap"] = {odf="npscr1",team=0,pos={2256.669921875,5.0,99984.6015625},craft=false},
    ["npscr258_scrap"] = {odf="npscr2",team=0,pos={2263.22998046875,5.064599990844727,99992.0},craft=false},
    ["npscr358_scrap"] = {odf="npscr3",team=0,pos={2275.639892578125,5.933199882507324,99997.0},craft=false},
    ["npscr259_scrap"] = {odf="npscr2",team=0,pos={2260.590087890625,5.0117998123168945,99996.6015625},craft=false},
    ["npscr159_scrap"] = {odf="npscr1",team=0,pos={2284.340087890625,8.998339653015137,99990.703125},craft=false},
    ["npscr260_scrap"] = {odf="npscr2",team=0,pos={2270.409912109375,5.468540191650391,99978.296875},craft=false},
    ["npscr160_scrap"] = {odf="npscr1",team=0,pos={2293.47998046875,12.498100280761719,99980.8984375},craft=false},
    ["npscr161_scrap"] = {odf="npscr1",team=0,pos={2272.72998046875,5.0,100013.0},craft=false},
    ["npscr261_scrap"] = {odf="npscr2",team=0,pos={2280.75,7.392660140991211,99972.296875},craft=false},
    ["npscr262_scrap"] = {odf="npscr2",team=0,pos={2249.340087890625,5.0,100006.0},craft=false},
    ["npscr362_scrap"] = {odf="npscr3",team=0,pos={2248.590087890625,5.0,99989.5},craft=false},
    ["npscr263_scrap"] = {odf="npscr2",team=0,pos={2250.669921875,5.0,99974.0},craft=false},
    ["npscr264_scrap"] = {odf="npscr2",team=0,pos={2247.679931640625,5.0,99969.1015625},craft=false},
    ["npscr164_scrap"] = {odf="npscr1",team=0,pos={2228.5400390625,5.0,99966.6015625},craft=false},
    ["npscr364_scrap"] = {odf="npscr3",team=0,pos={2259.239990234375,5.0,100002.0},craft=false},
    ["npscr165_scrap"] = {odf="npscr1",team=0,pos={2247.81005859375,5.0,99977.703125},craft=false},
    ["npscr265_scrap"] = {odf="npscr2",team=0,pos={2264.4599609375,5.1512298583984375,99973.1015625},craft=false},
    ["npscr365_scrap"] = {odf="npscr3",team=0,pos={2274.199951171875,6.434929847717285,99980.296875},craft=false},
    ["npscr166_scrap"] = {odf="npscr1",team=0,pos={2267.7099609375,5.0,100012.0},craft=false},
    ["npscr167_scrap"] = {odf="npscr1",team=0,pos={2460.239990234375,5.0,99434.3984375},craft=false},
    ["npscr168_scrap"] = {odf="npscr1",team=0,pos={2467.9599609375,5.0,99438.6015625},craft=false},
    ["npscr368_scrap"] = {odf="npscr3",team=0,pos={2489.969970703125,5.0,99447.1015625},craft=false},
    ["npscr369_scrap"] = {odf="npscr3",team=0,pos={2455.300048828125,5.002960205078125,99429.8984375},craft=false},
    ["npscr370_scrap"] = {odf="npscr3",team=0,pos={2463.93994140625,5.131959915161133,99425.6015625},craft=false},
    ["npscr170_scrap"] = {odf="npscr1",team=0,pos={2483.550048828125,5.0,99425.0},craft=false},
    ["npscr171_scrap"] = {odf="npscr1",team=0,pos={2475.610107421875,5.0,99425.203125},craft=false},
    ["npscr271_scrap"] = {odf="npscr2",team=0,pos={2451.81005859375,5.0,99434.8984375},craft=false},
    ["npscr272_scrap"] = {odf="npscr2",team=0,pos={2475.35009765625,5.0,99433.1015625},craft=false},
    ["npscr273_scrap"] = {odf="npscr2",team=0,pos={2436.6298828125,5.19881010055542,99425.0},craft=false},
    ["npscr173_scrap"] = {odf="npscr1",team=0,pos={2499.330078125,5.045010089874268,99474.5},craft=false},
    ["npscr174_scrap"] = {odf="npscr1",team=0,pos={2480.27001953125,5.002699851989746,99472.5},craft=false},
    ["npscr374_scrap"] = {odf="npscr3",team=0,pos={2484.6298828125,5.0,99469.6015625},craft=false},
    ["npscr175_scrap"] = {odf="npscr1",team=0,pos={2500.860107421875,5.0,99466.203125},craft=false},
    ["npscr176_scrap"] = {odf="npscr1",team=0,pos={2494.7099609375,5.01701021194458,99471.703125},craft=false},
    ["npscr276_scrap"] = {odf="npscr2",team=0,pos={2484.300048828125,5.0,99454.3984375},craft=false},
    ["npscr376_scrap"] = {odf="npscr3",team=0,pos={2505.320068359375,5.0,99451.3984375},craft=false},
    ["npscr377_scrap"] = {odf="npscr3",team=0,pos={2519.419921875,5.094019889831543,99489.3984375},craft=false},
    ["npscr177_scrap"] = {odf="npscr1",team=0,pos={2480.2900390625,5.002900123596191,99479.296875},craft=false},
    ["npscr178_scrap"] = {odf="npscr1",team=0,pos={2488.419921875,5.032010078430176,99473.203125},craft=false},
    ["npscr179_scrap"] = {odf="npscr1",team=0,pos={1843.239990234375,6.163839817047119,99964.5},craft=false},
    ["npscr379_scrap"] = {odf="npscr3",team=0,pos={1878.6500244140625,5.0,99990.703125},craft=false},
    ["npscr180_scrap"] = {odf="npscr1",team=0,pos={1864.1500244140625,5.0,99968.296875},craft=false},
    ["npscr181_scrap"] = {odf="npscr1",team=0,pos={1874.9000244140625,5.0,99965.3984375},craft=false},
    ["npscr182_scrap"] = {odf="npscr1",team=0,pos={1881.9599609375,5.0,99995.6015625},craft=false},
    ["npscr183_scrap"] = {odf="npscr1",team=0,pos={1854.739990234375,6.135169982910156,99978.5},craft=false},
    ["npscr283_scrap"] = {odf="npscr2",team=0,pos={1875.4599609375,5.0,99974.796875},craft=false},
    ["npscr284_scrap"] = {odf="npscr2",team=0,pos={1882.5899658203125,5.0,99967.0},craft=false},
    ["npscr184_scrap"] = {odf="npscr1",team=0,pos={1860.9100341796875,5.0,99968.203125},craft=false},
    ["npscr384_scrap"] = {odf="npscr3",team=0,pos={1870.1700439453125,5.0,99982.3984375},craft=false},
    ["npscr285_scrap"] = {odf="npscr2",team=0,pos={2892.320068359375,5.487209796905518,100037.0},craft=false},
    ["npscr385_scrap"] = {odf="npscr3",team=0,pos={2907.050048828125,7.085239887237549,100023.0},craft=false},
    ["npscr286_scrap"] = {odf="npscr2",team=0,pos={2904.080078125,8.040900230407715,100038.0},craft=false},
    ["npscr287_scrap"] = {odf="npscr2",team=0,pos={2925.489990234375,9.360950469970703,100035.0},craft=false},
    ["npscr288_scrap"] = {odf="npscr2",team=0,pos={2902.320068359375,5.852109909057617,100016.0},craft=false},
    ["npscr289_scrap"] = {odf="npscr2",team=0,pos={2901.81005859375,8.407050132751465,100045.0},craft=false},
    ["npscr389_scrap"] = {odf="npscr3",team=0,pos={2920.669921875,11.022700309753418,100041.0},craft=false},
    ["npscr390_scrap"] = {odf="npscr3",team=0,pos={2883.429931640625,5.0,100037.0},craft=false},
    ["npscr290_scrap"] = {odf="npscr2",team=0,pos={2930.6298828125,6.537139892578125,100017.0},craft=false},
    ["npscr190_scrap"] = {odf="npscr1",team=0,pos={2905.280029296875,8.833080291748047,100042.0},craft=false},
    ["npscr191_scrap"] = {odf="npscr1",team=0,pos={2987.989990234375,9.737090110778809,99461.796875},craft=false},
    ["npscr391_scrap"] = {odf="npscr3",team=0,pos={2950.60009765625,7.4644598960876465,99442.296875},craft=false},
    ["npscr291_scrap"] = {odf="npscr2",team=0,pos={2974.530029296875,15.70300006866455,99463.3984375},craft=false},
    ["npscr392_scrap"] = {odf="npscr3",team=0,pos={2947.64990234375,10.958399772644043,99457.6015625},craft=false},
    ["npscr192_scrap"] = {odf="npscr1",team=0,pos={2980.8798828125,9.348329544067383,99444.3984375},craft=false},
    ["npscr393_scrap"] = {odf="npscr3",team=0,pos={2963.0400390625,7.187620162963867,99433.203125},craft=false},
    ["npscr293_scrap"] = {odf="npscr2",team=0,pos={2963.75,18.53809928894043,99470.6015625},craft=false},
    ["npscr394_scrap"] = {odf="npscr3",team=0,pos={2951.8798828125,9.965660095214844,99449.3984375},craft=false},
    ["npscr294_scrap"] = {odf="npscr2",team=0,pos={2976.300048828125,12.04740047454834,99450.0},craft=false},
    ["npscr295_scrap"] = {odf="npscr2",team=0,pos={2952.820068359375,12.287300109863281,99454.5},craft=false},
    ["coop_spawn1"] = {odf="pspwn_1",team=1,pos={2875.239990234375,5.9476399421691895,99548.8984375},craft=false},
    ["coop_spawn2"] = {odf="pspwn_1",team=2,pos={2900.139892578125,5.9476399421691895,99551.1015625},craft=false},
    ["coop_spawn3"] = {odf="pspwn_1",team=3,pos={2925.0400390625,5.9476399421691895,99553.3984375},craft=false},
    ["coop_spawn4"] = {odf="pspwn_1",team=4,pos={2949.93994140625,5.9476399421691895,99555.6015625},craft=false},
    ["cr16_transport"] = {odf="hbtran00",team=6,pos={3900.0,5.0,100000.0},craft=false},
    ["cr16_engine1"] = {odf="hbtrn200",team=6,pos={3897.389892578125,5.0,99975.0},craft=false},
    ["cr16_engine2"] = {odf="hbtrn200",team=6,pos={3875.280029296875,5.0,100003.0},craft=false},
    ["cr16_engine3"] = {odf="hbtrn200",team=6,pos={3902.35009765625,5.0,100025.0},craft=false},
    ["cr16_engine4"] = {odf="hbtrn200",team=6,pos={3925.06005859375,5.0,99998.0},craft=false},
    ["cr16_pad_look"] = {odf="apcamr",team=0,pos={3900.0,35.0,100000.0},craft=false},
    ["cr16_evac1"] = {odf="hvsat",team=6,pos={3650.0,12.5,100020.0},craft=true},
    ["cr16_evac2"] = {odf="hvsat",team=6,pos={3680.0,10.0,99980.0},craft=true},
}
F.PATHS = {
    ["camera_path1"] = {2558.7900390625,6,99640.296875},
    ["starta"] = {1671.0899658203125,6,99499.5},
    ["startb"] = {3133.6201171875,6,100219.0},
    ["strike1"] = {2418.330078125,6,99613.296875},
    ["strike2"] = {2523.330078125,6,99843.796875},
    ["edge_path"] = {1610.6700439453125,6,100582.0},
    ["path_4"] = {1525.3299560546875,6,100774.0},
    ["sat1"] = {2464.830078125,6,99827.6015625},
    ["sat2"] = {2388.280029296875,6,99689.0},
    ["starta2"] = {1651.6300048828125,6,99515.703125},
    ["starta3"] = {1664.6099853515625,6,99486.5},
    ["startb2"] = {3123.889892578125,6,100236.0},
    ["startb3"] = {3149.840087890625,6,100210.0},
    ["cr16_evac_route"] = {3740.0,6,100050.0},
    ["cr16_board"] = {3900.0,6,100060.0},
    ["cr16_evac_cam"] = {3900.0,6,99900.0},
    ["cr16_launch_cam"] = {4000.0,6,99940.0},
    ["cr16_ally_a"] = {1200.0,6,99460.0},
    ["cr16_ally_b"] = {3700.0,6,100300.0},
    ["cr16_enemy_a"] = {3650.0,6,98600.0},
    ["cr16_enemy_b"] = {1250.0,6,100550.0},
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
        for i = 1, select("#", ...) do local v = select(i, ...); assert(type(v) ~= "string" or #v <= 127, "Send string over 127 bytes on " .. tostring(kind)) end
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
                assert(W.objects[(...)].odf == "aspilo" or (W.objects[(...)].odf == "hvsat" and ((...)=="cr16_evac1" or (...)=="cr16_evac2")), "SetIndependence on a non-allowlisted object")
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
        Environment = {Init=function() record("EnvironmentInit") end,
            BindWeatherSensors=function(name) record("WeatherSensors",name) end,
            Update=noop,OnObjectCreated=noop,InvalidateRenderer=noop},
        CRTitanSites16 = assert(loadfile("Scripts/CRTitanSites16.lua"))(),
        PersistentConfig = {Initialize=function() record("PdaInitialize") end,
            UpdateInputs=function() record("PdaUpdate") end,UpdateHeadlights=noop},
    }
    modules.CRCoopComms = assert(loadfile("Scripts/CRCoopComms.lua"))()
    modules.CRWire = assert(loadfile("Scripts/CRWire.lua"))()
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
    modules.CRMisn16 = setfenv(assert(loadfile("Scripts/CRMisn16.lua")),e)()
    setfenv(assert(loadfile("Scripts/misn16.lua")), e)()
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
